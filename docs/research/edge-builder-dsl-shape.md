# Edge-builder DSL: shape decisions for `Keiki.Builder`

This note settles the seven open questions raised by EP-15
(`docs/plans/15-edge-builder-monadic-dsl-for-authoring-symtransducer-edges.md`)
M1. The output is the contract that M2 (spike) and M3
(`src/Keiki/Builder.hs`) consume verbatim.

`Keiki.Builder` is *additive*: it sits on top of the post-MP-6
`Keiki.Core` AST and produces values of the existing AST types. The
AST is unchanged. Users who prefer the AST keep writing the AST; the
builder is recommended but not mandatory.


## Q1 — Indexed-monad carrier shape

**Decision.** Hand-rolled indexed-state monad, surfaced via
`QualifiedDo` (`B.do { … }`). `RebindableSyntax` is rejected.

The carrier kind was settled in EP-15's Decision Log: the builder
threads a type-level slot-set `(w :: [Symbol])` through every step so
the static `Disjoint` check on `combine` propagates to a duplicated
`(.=)` at the offending line. The two viable do-notation mechanisms
are `QualifiedDo` and `RebindableSyntax`. Both are available under
GHC 9.12.

`QualifiedDo` (default): `import qualified Keiki.Builder as B` and
write `B.do { … }`. The bind operator is `Keiki.Builder.>>=` (the
indexed bind). Other do-blocks in the same module (e.g. an `IO`
do-block) are unaffected. The pragma is per-module (`{-# LANGUAGE
QualifiedDo #-}`), and the user's module-level `Monad`-bound
operators stay live for non-builder do-blocks. This is the
recommended import shape.

`RebindableSyntax` re-binds `(>>=)`, `(>>)`, `pure`, `return`, and
`fail` *module-wide*. Every do-block in the user's module then uses
the rebound names. This is awkward in any module that mixes the
builder with another monadic computation (a Hedgehog spec, a quick
`IO` runner, etc.); it forces the user to either split modules or
re-import `Prelude.>>=` for the other side. The cost outweighs the
ergonomics win — `B.do` is a four-character prefix.

The hand-rolled carrier and `QualifiedDo`-compatible exports avoid a
new dependency (the `indexed` and `do-notation` packages each carry
their own typeclass hierarchy; `Keiki.Builder` exports its own
`(>>=)`/`(>>)`/`pure`/`return` directly so `B.do` resolves with no
intermediary).

**Worked error message — duplicate `(.=)`.** Given:

    B.from EmailPending B.do
      B.onCmd inCtorSendEmail $ \d -> B.do
        #emailRecipient .= d.recipient
        #emailRecipient .= d.recipient   -- duplicate
        B.goto EmailSentVertex

GHC fails the second `(.=)` with the existing `TypeError` from
`Keiki.Internal.Slots.NotMemberCmp`:

    src/Keiki/Examples/EmailDelivery.hs:NN:NN: error: [GHC-64725]
        • Keiki.Internal.Slots.Disjoint: slot "emailRecipient" is
          written by both halves of `combine`. Each register slot
          may be written at most once per edge update.
        • In a stmt of a 'do' block:
            #emailRecipient .= d.recipient

The line number points at the offending duplicate `(.=)` (the
indexed-bind's `>>=` is desugared from that statement, and GHC
attributes the failed `Disjoint` constraint to it). The slot name is
quoted in the message verbatim — the user does not need to read the
indexed-monad type to locate the bug.


## Q2 — `(.=)` shape

**Decision.** RHS is always a `Term rs ci r`. No `ToTerm` overload
class.

The existing AST examples never write a bare value as a slot RHS:
every `USet` is `USet ix (inpFoo #x)` or `USet ix (proj #y)` or
`USet ix (TLit v)`-via-`lit`. All three already produce a `Term`.
Adding a `ToTerm` overload would buy a small win for the literal
case (`#slot .= 42` instead of `#slot .= lit 42`) at the cost of an
overlap-instance dance (the `Term rs ci r` instance must take
precedence over the bare-value instance, and GHC's type inference
on the bare-value side has to defer until both sides resolve).

Pragmatic shape:

    (.=) :: (Disjoint '[s] w, KnownSymbol s)
         => IndexN s rs r
         -> Term rs ci r
         -> EdgeBuilder rs ci co s_vert w ('[s] `Concat` w) ()
    infixr 6 .=

The `(Disjoint '[s] w)` constraint is what the type error
referenced in Q1 lifts. `IndexN s rs r` is the slot-name-tagged
index; `#slot` resolves to it via the `IsLabel` instance in
`Keiki.Internal.Slots`.

If a follow-up plan finds `lit`-noise on literal-heavy aggregates
sufficient to motivate the overload, the type signature widens
without rewriting any existing call site. The conservative shape now
keeps the type-error story crisp.


## Q3 — `emit` shape

**Decision.** `emit` takes a `WireCtor` and an explicit
`OutFields rs ci fs`. No record-syntax sugar in M3.

Signature:

    emit :: KnownInCtor ci ifs
         => WireCtor co fs
         -> OutFields rs ci fs
         -> EdgeBuilder rs ci co s_vert w w ()

(The `KnownInCtor` constraint is satisfied automatically inside
`onCmd`'s body — see Q4.)

The user constructs the `OutFields` HList with the existing
`OFCons`/`OFNil` constructors:

    B.emit wireEmailSent
      ( OFCons d.recipient
      ( OFCons d.subject
      ( OFCons d.at OFNil )))

The win over the AST form is that `pack` and the InCtor argument are
gone — the InCtor is recovered from the lexically-enclosing `onCmd`
(the only `onCmd`-introduction-site that pinned an InCtor; `emit`
reads it back from the threaded edge state). The `Just` wrapper
around `OPack` is also gone.

Two follow-up paths are explicitly *not* delivered in M3 and are
recorded here so a future plan can pick them up cleanly:

1. *Operator-style HList sugar.* Re-export `OFCons` as `(*:)` and
   `OFNil` as a name like `oNil`, with `infixr 5 *:`, so the user
   writes `d.recipient *: d.subject *: d.at *: oNil`. Saves
   parentheses; preserves semantics.
2. *Field-keyed record sugar.* For each event constructor `Foo`,
   the `deriveWireCtors` splice could emit a parallel
   `Foo`-shaped record type whose fields are `Term`s, plus a
   `mkWireOutFromTermRecord :: TermFoo -> OutFields rs ci fs`. The
   user then writes `emit wireFoo TermFoo { recipient = d.x, … }`.
   This is the "record syntax" exemplar the EP-15 plan sketches; it
   requires a non-trivial extension to the TH splice and is
   deferred.

The M3 surface delivers the bigger ergonomic win (no `pack`, no
explicit `InCtor`, no `Just`-wrapping) without committing to either
follow-up.

For the ε-output case (the edge consumes input but emits no event),
the surface is `noEmit`:

    noEmit :: EdgeBuilder rs ci co s_vert w w ()

`noEmit` leaves the edge's `output` field as `Nothing`. It is
optional — the default state of `output` in a fresh edge is
`Nothing`. `noEmit` exists only so the user can be explicit about
intent (and so unit tests have a syntactic anchor to assert
against). An edge with neither `emit` nor `noEmit` is treated as an
ε-edge.


## Q4 — Vertex grouping (`from`)

**Decision.** Vertex-keyed sub-builders. The top-level builder is a
plain `Monad`-carrier `VertexBuilder rs ci co s a` whose runtime
state is a `[(s, Edge phi rs ci co s)]` writer. `from V $ do { … }`
parses the inner do-block's `onCmd`/`onEpsilon` blocks into a list
of `Edge` values and tags each with `V`.

    -- Top-level entry: produce a SymTransducer from an initial vertex,
    -- initial register file, and a do-block of `from V $ do …` clauses.
    buildTransducer
      :: (Bounded s, Enum s, Show s)
      => s
      -> RegFile rs
      -> (s -> Bool)              -- isFinal predicate
      -> VertexBuilder rs ci co s ()
      -> SymTransducer (HsPred rs ci) rs s ci co

    -- Group edges by source vertex.
    from :: Show s
         => s
         -> EdgeListBuilder rs ci co s ()
         -> VertexBuilder rs ci co s ()

`EdgeListBuilder` is the thin layer that runs many `onCmd`/`onEpsilon`
blocks under one source vertex. It is a plain (non-indexed)
`Monad` because each per-edge build is self-contained — the
indexed-monad threading happens *inside* an `onCmd` body, not across
them.

    -- Per-edge entries. The body is a fresh EdgeBuilder indexed from
    -- '[] (no slots written) to whatever set the body accumulates.
    onCmd
      :: forall ci ifs rs co s w.
         InCtor ci ifs
      -> (PayloadProj rs ci ifs -> EdgeBuilder rs ci co s '[] w ())
      -> EdgeListBuilder rs ci co s ()

    onEpsilon
      :: forall rs ci co s w.
         EdgeBuilder rs ci co s '[] w ()
      -> EdgeListBuilder rs ci co s ()

`PayloadProj rs ci ifs` is a record-shaped wrapper that gives the
user `OverloadedRecordDot` access to the input symbol's fields:

    -- newtype wrapper around an InCtor; HasField instances dispatch
    -- to inpCtor.
    newtype PayloadProj rs ci ifs = PayloadProj (InCtor ci ifs)

    -- HasField machinery lets the user write `d.email` instead of
    -- `inpStart #email`.
    instance ( HasIndex name ifs r )
          => HasField name (PayloadProj rs ci ifs)
                           (Term rs ci r) where
      getField (PayloadProj ic) =
        TInpCtorField ic (indexOf @name @ifs @r)

Vertices not mentioned in any `from` block default to `[]`
(terminal). This matches the AST behaviour and avoids forcing the
user to write `from Deleted $ pure ()` for every terminal vertex.
A future plan can add a `withCompletenessCheck` combinator that
walks `[minBound..maxBound]` against the vertices touched by the
builder and reports unmentioned ones if the user wants the stricter
behaviour.

The `isFinal` predicate is passed explicitly to `buildTransducer` —
it is not derived from `from` blocks. Reason: the AST's `isFinal` is
a function `s -> Bool`, not data the builder accumulates, and the
two example aggregates compute it as a one-line case-match. Asking
the user to write that one line is cheaper than introducing a
`final V` builder primitive.


## Q5 — Distinct-targets enforcement

**Decision.** Type-level via the indexed-monad's threaded
`(w :: [Symbol])`. Inherited mechanically from `combine`'s
`Disjoint w1 w2` constraint. M1 commits to using the existing
`Keiki.Internal.Slots.Disjoint` `TypeError` verbatim.

The error message is already in
`Keiki.Internal.Slots.NotMemberCmp` (lines 76–83 of
`src/Keiki/Internal/Slots.hs`) and reads:

    Keiki.Internal.Slots.Disjoint: slot "<name>" is written by both
    halves of `combine`. Each register slot may be written at most
    once per edge update.

The wording is precise enough that a novice can locate the
duplicated slot from the GHC error alone (verified by the worked
example in Q1). No new TypeError formatting is needed in
`Keiki.Builder`.

Because `(.=)` is the only public introduction point in the
builder, every `combine` call site goes through the smart
constructor (the unconstrained raw `UCombine` is reserved for
internal `Keiki.Composition` walks). The
`-Wredundant-constraints` warning fires on `combine`'s body in
`Keiki.Core` for the same reason it does in `Keiki.Composition` —
the `Disjoint w1 w2` constraint *is* the static check, and GHC
sees it as unused. The builder module enables
`-Wno-redundant-constraints` at the module level with a justifying
comment, mirroring `Keiki.Core` and `Keiki.Composition`.


## Q6 — `goto` and termination

**Decision.** Every `onCmd`/`onEpsilon` body must call `goto V`
exactly once. Missing or duplicate `goto`s are caught at builder
finalize time and produce a runtime error naming the source vertex
and the edge's positional index within that vertex.

    goto :: s -> EdgeBuilder rs ci co s_vert w w ()

`goto` writes `peTarget = Just v` into the threaded edge state.
Calling it twice produces a `peTarget` already-`Just` situation;
the finalize-time check (run when `from V $ do { … }` collapses
the inner builder into a list of `Edge`s) raises:

    Keiki.Builder: edge #<n> from <show vertex>: goto called more
    than once. Each onCmd/onEpsilon body must end with exactly one
    goto V.

A missing `goto` (peTarget still `Nothing` at finalize) raises:

    Keiki.Builder: edge #<n> from <show vertex>: goto missing.
    Each onCmd/onEpsilon body must end with exactly one goto V.

The error is a plain `error` call (not a typed exception); it
fires at `buildTransducer` time, which on a typical aggregate is
during top-level binding evaluation in the `Examples` module.
Aggregates that build correctly never see the error.

`requireGuard`, `requireEq`, `(.=)`, `emit`, `noEmit` all leave
`peTarget` untouched. Only `goto` writes it.

The `goto`-must-be-called-exactly-once invariant is enforced at
runtime rather than at the type level because doing it at the
type level would require pushing a "target set?" boolean into
the indexed-monad's index alongside `w`. That doubles the noise
in every type signature for a check the user encounters once
during initial debug. The runtime error fires at top-level
evaluation, fails loud, and names the offender precisely — the
ergonomic cost is acceptable.


## Q7 — Module placement and naming

**Decision.** `Keiki.Builder` (`src/Keiki/Builder.hs`).

Alternatives considered:

- *`Keiki.DSL`.* Heavier name; risks confusing readers into
  thinking the AST is *not* a DSL. The AST is also a DSL, just
  the lower-level one. Rejected.
- *`Keiki.Edge`.* Narrower than the surface. The module also
  exposes `from`/`buildTransducer`/`onCmd`, none of which are
  edge-level. Rejected.
- *`Keiki.Author`.* Cute but unconventional; reads as
  authorial-attribution rather than authoring-tool. Rejected.

`Keiki.Builder` matches the convention in adjacent libraries
(`Data.Aeson.KeyMap.Builder`, `Data.ByteString.Builder`,
`hedgehog`'s `Hedgehog.Gen`/`Range`). The user writes
`import qualified Keiki.Builder as B` once and `B.do` /
`B.from` / `B.onCmd` everywhere.

Sub-modules are not introduced. The hand-rolled
`(>>=)`/`(>>)`/`pure`/`return` exports for `QualifiedDo` live in
the same module as the rest of the surface. If a future plan
adds sufficient surface to warrant splitting (a `Keiki.Builder.View`
for the per-vertex GADT view, a `Keiki.Builder.Spec` for
HSpec-like assertions), it can do so without breaking the
existing import.


## Worked example — EmailDelivery in the new DSL

The full `emailDeliveryEdges` re-expressed in the M3 surface,
side-by-side with the post-MP-6 AST form. The AST form is what
`src/Keiki/Examples/EmailDelivery.hs:163` ships today.

    -- AST form (post-MP-6, current master, lines 163–183).
    emailDeliveryASTEdges = \case

      EmailPending ->
        [ Edge
            { guard  = isSendEmail
            , update =
                USet (#emailRecipient :: IndexN "emailRecipient" EmailRegs Email)
                     (inpSendEmail #recipient)
                  `combine`
                USet (#emailSubject :: IndexN "emailSubject" EmailRegs Subject)
                     (inpSendEmail #subject)
                  `combine`
                USet (#emailSentAt :: IndexN "emailSentAt" EmailRegs UTCTime)
                     (inpSendEmail #at)
            , output = Just $ pack
                inCtorSendEmail
                wireEmailSent
                (OFCons (inpSendEmail #recipient)
                  (OFCons (inpSendEmail #subject)
                    (OFCons (inpSendEmail #at) OFNil)))
            , target = EmailSentVertex
            }
        ]

      EmailSentVertex -> []

    -- Builder form (M3 surface).
    emailDelivery = B.buildTransducer
                      EmailPending
                      emptyEmailRegs
                      (\case EmailSentVertex -> True; _ -> False)
                      $ B.do

      B.from EmailPending B.do
        B.onCmd inCtorSendEmail $ \d -> B.do
          #emailRecipient .= d.recipient
          #emailSubject   .= d.subject
          #emailSentAt    .= d.at
          B.emit wireEmailSent
            ( OFCons d.recipient
            ( OFCons d.subject
            ( OFCons d.at OFNil )))
          B.goto EmailSentVertex

      B.from EmailSentVertex (B.pure ())  -- terminal

The visible differences:

- The `Edge { guard, update, output, target }` record literal is
  gone. `onCmd` sets the guard implicitly; `(.=)` accumulates the
  update; `emit` sets the output; `goto` sets the target.
- The `IndexN "name" Regs T` annotation on every `USet` is gone.
  `#name` resolves to `IndexN s rs r` directly via `IsLabel`, and
  `(.=)` infers the `s rs r` from the threaded edge state.
- The `infix combine` chain is gone. Sequential `(.=)` lines are
  joined by the indexed-monad's `(>>)` (which itself emits a
  `combine` in the threaded `Update`).
- The `pack inCtorSendEmail wireEmailSent` prefix is gone. `emit`
  picks up the InCtor from the enclosing `onCmd` and packages the
  `OPack` itself.
- The `Just $` wrapper around the OutTerm is gone. `emit` writes
  `peOutput = Just …`; `noEmit` (or omission) leaves it `Nothing`.
- Field names appear once each in the body of an edge, instead of
  twice (once on the LHS of `USet`, once via `IndexN "name"`).

LOC delta on this single edge: 19 → 9 lines. Multiplied across the
six edges of UserRegistration, the projected reduction matches the
plan's <310 LOC target.


## Imports the user writes

The minimum imports for an aggregate module migrated to the
builder:

    {-# LANGUAGE QualifiedDo #-}

    module Keiki.Examples.EmailDelivery (...) where

    import qualified Keiki.Builder as B
    import Keiki.Builder ((.=))                -- so (.=) resolves at use sites

    -- Existing imports unchanged:
    import Keiki.Core         (...)
    import Keiki.Generics.TH  (deriveAggregateCtors, deriveView, deriveWireCtors)
    -- TH-derived `inCtor*`, `inp*`, `is*`, `wire*` declarations stay.

The `import qualified … as B` is what `B.do` / `B.from` / `B.onCmd`
resolves against. The unqualified `(.=)` import is what the
record-syntax-style assignment needs (qualifying it as `B..=` is
unreadable). No other change to the import list.

If the user's module also imports `Control.Lens` or
`Data.Aeson.Types`, both of which also export `(.=)`, they hide it
from those imports:

    import Control.Lens hiding ((.=))
    import Data.Aeson    hiding ((.=))

The `Keiki.Builder.(.=)` is the only one in scope unqualified, and
its semantics ("accumulate a `USet` into the builder writer") is
documented in the module's haddock so users coming from those
libraries do not expect mid-edge read-back semantics.


## Out of scope for M3

- Operator-style HList sugar for `OutFields` (Q3 follow-up).
- Field-keyed record sugar for `emit` (Q3 follow-up — TH on the
  wire side).
- A `withCompletenessCheck` combinator that asserts every vertex
  appears in some `from` block (Q4 follow-up).
- `ToTerm`-overload on `(.=)`'s RHS (Q2 follow-up).
- A quasi-quoter `[transducer| … |]` (rejected in EP-15's
  Out-of-scope list).

Each follow-up is a single-EP plan that can be picked up later
without changing M3's signatures — they widen the surface, never
narrow it.
