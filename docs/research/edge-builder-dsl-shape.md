# Edge-builder DSL: shape decisions for `Keiki.Builder`

This note records the seven design decisions that shape
`Keiki.Builder`. The builder is *additive*: it sits on top of
`Keiki.Core`'s AST and produces values of the existing AST types.
The AST is unchanged. Users who prefer the AST keep writing the
AST; the builder is recommended but not mandatory.


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

    B.from EmailPending $ do
      B.onCmd inCtorSendEmail $ \d -> B.do
        B.slot @"emailRecipient" B..= d.recipient
        B.slot @"emailRecipient" B..= d.recipient   -- duplicate
        B.goto EmailSentVertex

GHC fails the second `(.=)` with the existing `TypeError` from
`Keiki.Internal.Slots.NotMemberCmp`:

    jitsurei/src/Jitsurei/EmailDelivery.hs:NN:NN: error: [GHC-64725]
        • Keiki.Internal.Slots.Disjoint: slot "emailRecipient" is
          written by both halves of `combine`. Each register slot
          may be written at most once per edge update.
        • In a stmt of a 'do' block:
            slot @"emailRecipient" .= d.recipient

The line number points at the offending duplicate `(.=)` (the
indexed-bind's `>>=` is desugared from that statement, and GHC
attributes the failed `Disjoint` constraint to it). The slot name is
quoted in the message verbatim — the user does not need to read the
indexed-monad type to locate the bug.

(The `B.do` qualifier applies only to the per-edge body. The outer
`from`/`onCmd` blocks are plain `Monad`-typed `do`-notation; only
`EdgeBuilder` (the per-edge layer) is the indexed monad. See Q4 for
the three-monad layering.)


## Q2 — `(.=)` shape

**Decision.** RHS is always a `Term rs ci r`. The slot LHS is
`slot @"name"` (a TypeApplication-driven helper), not `#name`. No
`ToTerm` overload class.

The existing AST examples never write a bare value as a slot RHS:
every `USet` is `USet ix (inpFoo #x)` or `USet ix (proj #y)` or
`USet ix (TLit v)`-via-`lit`. All three already produce a `Term`.
Adding a `ToTerm` overload would buy a small win for the literal
case (`slot @"x" .= 42` instead of `slot @"x" .= lit 42`) at the
cost of an overlap-instance dance. The conservative shape now keeps
the type-error story crisp.

Pragmatic shape:

    -- A label-style helper that lifts a slot name (via TypeApplication)
    -- to its slot-name-tagged register index.
    slot
      :: forall (name :: Symbol) rs r.
         (KnownSymbol name, HasIndexN name rs r)
      => IndexN name rs r

    (.=) :: (Disjoint '[s] w, KnownSymbol s)
         => IndexN s rs r
         -> Term rs ci r
         -> EdgeBuilder rs ci co s_vert pin w ('[s] `Concat` w) ()
    infixr 6 .=

The `(Disjoint '[s] w)` constraint is what the type error
referenced in Q1 lifts.

**Why `slot @"name"` instead of `#name`.** EP-15 M2 (the spike)
discovered that `#name` does not resolve cleanly to `IndexN "name"
rs r` when `name` is a quantified type variable in `(.=)`'s
signature. The IsLabel instance in `Keiki.Internal.Slots` is
`IsLabel s (IndexN s rs r)`, and GHC's instance lookup will not
commit to `s ~ "name"` when the pattern-side `s` appears at two
positions in the constraint head and the call-site `name` is itself
unsolved (the existing AST works around this by writing
`(#name :: IndexN "name" Regs T)` everywhere). The `slot @"name"`
helper sidesteps the problem by pinning the symbol via
TypeApplication. Inside `slot`, the `HasIndexN name rs r` constraint
fires once `rs` is determined from the surrounding `EdgeBuilder`,
returning `IndexN name rs r` for the chosen `name`.

The user surface goes from

    USet (#emailRecipient :: IndexN "emailRecipient" EmailRegs Email) ...

(AST, name appears twice) to

    slot @"emailRecipient" .= ...

(builder, name appears once). The win is preserved; the syntax
becomes `slot @"name"` instead of `#name`.

If a future GHC release fixes the IsLabel instance-head unification
(or a future plan adds a class-driven label resolution that handles
the two-positions case), `slot` can be made an alias for `id` and
the user surface flips back to `#name .= …` without touching
`(.=)` itself. The current shape commits to the working surface.

If a follow-up plan finds `lit`-noise on literal-heavy aggregates
sufficient to motivate a `ToTerm`-style RHS overload, the type
signature widens without rewriting any existing call site.


## Q3 — `emit` shape

**Decision (post-EP-21).** `emit` takes a `WireCtor` and an
*overloaded* second argument that resolves through the
`ToOutFields` typeclass to an `OutFields rs ci fs`. The
typeclass admits two inhabitants: a TH-emitted per-event record
type (the *primary* surface) and a bare `OutFields` value (the
*lower-level* escape hatch, useful for ad-hoc data not modelled
by an event ctor). Both produce the same AST node (`OPack`),
consumed unchanged by every downstream module.

Current signature (EP-70 pins the enclosing input schema in the
builder index):

    emit :: ToOutFields rec rs ci ifs fs
         => WireCtor co fs
         -> rec
         -> EdgeBuilder rs ci co v ('Just ifs) w w ()

The InCtor is recovered from the lexically-enclosing `onCmd`
(stored on `PartialEdge` as a schema-indexed pin). This makes a
term-fields record from another command schema fail to type-check,
and makes `emit` inside `onEpsilon` a compile error. The
explicit-InCtor form `emitWith` remains available for `onEpsilon`;
inside `onCmd`, eager validation rejects a constructor whose name or
slot-name list differs from the enclosing constructor.

The two `ToOutFields` instances:

1. *Per-event record* — `deriveWireCtors` emits
   `<CtorName>TermFields rs ci` for every event ctor with a
   record payload, plus a `ToOutFields` instance walking its
   fields in declaration order. Call sites read top-to-bottom
   keyed by the wire side's payload field names:

        B.emit wireAccountConfirmed AccountConfirmedTermFields
          { email       = #email
          , confirmCode = d.confirmCode
          , at          = d.at
          }

   Wrong-field-order or missing-field bugs are caught at
   compile time.

2. *Bare `OutFields`* — the operator-style sugar `(*:)` /
   `oNil` (re-exports of `OFCons` / `OFNil` with `infixr 5 *:`)
   builds an `OutFields` directly. The passthrough instance
   `instance ToOutFields (OutFields rs ci fs) rs ci fs` lets
   the same `B.emit` overload accept it:

        B.emit wireBrewed (d.amount *: B.oNil)

The history (this section's pre-EP-21 framing recorded both
follow-ups as deferred):

- Operator HList sugar shipped at EP-21 M2.
- Field-keyed record sugar shipped at EP-21 M4 (TH splice
  extension) + M5 (example migration).
- The redundant explicit `InCtor` argument on the M3 signature
  was dropped at EP-21 M1.
- A new `IsLabel s (Term rs ci r)` instance on `Keiki.Core`
  (EP-21 M1) lets `#name` resolve directly to a `Term`-typed
  register read in any `Term`-typed context, replacing
  `proj (#name :: Index Regs T)` annotations at builder-form
  call sites.

See `docs/research/emit-field-keyed-record-sugar.md` (EP-21 M3)
for the full design rationale and the four open-question
resolutions.

For the ε-output case (the edge consumes input but emits no event),
the surface is `noEmit`:

    noEmit :: EdgeBuilder rs ci co s_vert pin w w ()

`noEmit` leaves the edge's `output` list empty. It is optional in the
current EP-70 surface: a fresh edge also starts with an empty output
list, so an edge with neither `emit` nor `noEmit` is an ε-edge. EP-68
is the dependency-ready follow-up that makes this marker load-bearing
and rejects silent output intent by omission through the eager defect
pass described in Q6.


## Q4 — Vertex grouping (`from`)

**Decision.** Vertex-keyed sub-builders. The builder is a *three-
layer* construction:

1. **`VertexBuilder rs ci co v a`** — top-level, plain `Monad`. The
   runtime state is `[(v, [Edge ...])]`; `from V` writes one entry.
2. **`EdgeListBuilder rs ci co v a`** — per-source-vertex, plain
   `Monad`. The runtime state is `[Edge ...]`; `onCmd` and
   `onEpsilon` each prepend one Edge.
3. **`EdgeBuilder rs ci co v pin w w' a`** — per-edge body, *indexed*
   monad. The type-level slot-set `(w :: [Symbol])` threads through
   every `(.=)` so the `Disjoint` check fires at compile time.

Only layer 3 is indexed. `QualifiedDo` (`B.do`) is used *only* in
the per-edge body; the outer `from V $ do { … }` and
`buildTransducer initS regs isF $ do { … }` use plain `do` (which
GHC desugars against Prelude's `Monad`).

EP-15 M2 (the spike) discovered this layering is necessary:
`QualifiedDo` redirects `(>>=)` to a single named operator, but
the three layers each have a different bind type signature (the
indexed bind threads `w`; the plain binds do not). Trying to use
`B.do` for all three layers fails to type-check because the indexed
bind cannot accept a `VertexBuilder` argument. M3 ships the
three-layer design verbatim.

    -- Top-level entry: produce a SymTransducer from an initial vertex,
    -- initial register file, and a do-block of `from V $ do …` clauses.
    buildTransducer
      :: (DistinctNames (Names rs), Eq s, Show s)
      => s
      -> RegFile rs
      -> (s -> Bool)              -- isFinal predicate
      -> VertexBuilder rs ci co s ()
      -> SymTransducer (HsPred rs ci) rs s ci co

    -- Group edges by source vertex.
    from :: s
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
      -> (PayloadProj rs ci ifs -> EdgeBuilder rs ci co s ('Just ifs) '[] w ())
      -> EdgeListBuilder rs ci co s ()

    onEpsilon
      :: forall rs ci co s w.
         EdgeBuilder rs ci co s 'Nothing '[] w ()
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
exactly once. Missing or duplicate `goto`s are collected by the eager
builder validation pass and produce diagnostics naming the source
vertex and the edge's positional index within that vertex.

    goto :: s -> EdgeBuilder rs ci co s_vert pin w w ()

`goto` prepends to `peTargets` in the threaded edge state. Calling it
twice leaves two targets; `finalizeEdge` returns a structured defect:

    Keiki.Builder: edge #<n> from <show vertex>: goto called more
    than once. Each onCmd/onEpsilon body must end with exactly one
    goto V.

A missing `goto` (an empty `peTargets`) returns the companion defect:

    Keiki.Builder: edge #<n> from <show vertex>: goto missing.
    Each onCmd/onEpsilon body must end with exactly one goto V.

`buildTransducerEither` returns every located `BuilderError` in
declaration order. The compatibility entry point `buildTransducer`
renders the same messages and raises them when the returned
transducer is first evaluated to weak head normal form. Validation
does not wait for `edgesOut` to inspect the affected vertex.

`requireGuard`, `requireEq`, `(.=)`, `emit`, and `noEmit` all leave
`peTargets` untouched. Only `goto` writes it.

The `goto`-must-be-called-exactly-once invariant is enforced by an
eager value-level pass rather than at the type level because doing it
at the type level would require pushing a "target set?" boolean into
the indexed-monad's index alongside `w`. That doubles the noise in
every type signature for a check the user encounters once during
initial debug. The structured pass fails loudly, names every
offender precisely, and remains available to tooling without
exception plumbing.

**Design update (2026-07-12, EP-70).** Builder construction now has
one eager `Either`-based validation pass. It merges duplicate `from`
blocks in declaration order, assigns indices after merging, and no
longer needs `Bounded`/`Enum` vertex constraints. `EdgeBuilder` also
carries the enclosing input schema as a phantom pin, eliminating the
builder's `unsafeCoerce`; ordinary `emit` mismatches are compile-time
errors, while `emitWith` constructor overrides are rejected eagerly.
Finally, `DistinctNames (Names rs)` makes duplicate register slot
names a compile-time `TypeError`. The standard keiro authoring shape
(`B.emit wireCtorX XTermFields {..}`) remains source-compatible.


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

The full `emailDeliveryEdges` re-expressed in the builder surface,
side-by-side with the AST form that
`jitsurei/src/Jitsurei/EmailDelivery.hs:163` ships today.

    -- AST form (lines 163–183).
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
            , output = [pack
                inCtorSendEmail
                wireEmailSent
                (OFCons (inpSendEmail #recipient)
                  (OFCons (inpSendEmail #subject)
                    (OFCons (inpSendEmail #at) OFNil)))]
            , target = EmailSentVertex
            }
        ]

      EmailSentVertex -> []

    -- Builder form (M3 surface).
    emailDelivery = B.buildTransducer
                      EmailPending
                      emptyEmailRegs
                      (\case EmailSentVertex -> True; _ -> False)
                      $ do  -- VertexBuilder (plain Monad)

      B.from EmailPending $ do  -- EdgeListBuilder (plain Monad)
        B.onCmd inCtorSendEmail $ \d -> B.do  -- EdgeBuilder (indexed)
          B.slot @"emailRecipient" B..= d.recipient
          B.slot @"emailSubject"   B..= d.subject
          B.slot @"emailSentAt"    B..= d.at
          B.emit wireEmailSent
            ( OFCons d.recipient
            ( OFCons d.subject
            ( OFCons d.at OFNil )))
          B.goto EmailSentVertex

      B.from EmailSentVertex (pure ())  -- terminal

The visible differences:

- The `Edge { guard, update, output, target }` record literal is
  gone. `onCmd` sets the guard implicitly; `(.=)` accumulates the
  update; `emit` sets the output; `goto` sets the target.
- The `IndexN "name" Regs T` annotation on every `USet` is gone.
  `slot @"name"` lifts the slot name to its `IndexN` in one place;
  `(.=)` reads the threaded edge state to determine `rs` and `r`.
- The `infix combine` chain is gone. Sequential `(.=)` lines are
  joined by the indexed-monad's `(>>)` (which itself emits a
  `combine` in the threaded `Update`).
- The `pack inCtorSendEmail wireEmailSent` prefix on `OPack` is no
  longer hand-written; `emit` packages the `OPack` itself using the
  schema-pinned `InCtor` from its enclosing `onCmd`. `emitWith` is
  the explicit-constructor form for `onEpsilon`.
- The list wrapper around the `OutTerm` is gone. Each `emit`
  snoc-appends to `peOutput`; `noEmit` (or omission, until EP-68)
  leaves that list empty.
- Field names appear once each in the body of an edge, instead of
  twice (once on the LHS of `USet`, once via `IndexN "name"`).

LOC delta on this single edge: 19 → 9 lines. Multiplied across the
six edges of UserRegistration, the projected reduction matches the
plan's <310 LOC target.


## Imports the user writes

The minimum imports for an aggregate module migrated to the
builder:

    {-# LANGUAGE QualifiedDo #-}

    module Jitsurei.EmailDelivery (...) where

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


## Out of scope for M3 (the EP-15 baseline) — status update

- *Operator-style HList sugar for `OutFields`.* Shipped at
  EP-21 M2 (`(*:)` / `oNil`).
- *Field-keyed record sugar for `emit`.* Shipped at EP-21 M4
  (TH splice extension) + M5 (example migration).
- *A `withCompletenessCheck` combinator.* Still deferred.
- *`ToTerm`-overload on `(.=)`'s RHS.* Still deferred.
- *A quasi-quoter `[transducer| … |]`.* Rejected (EP-15
  Out-of-scope list); not revisited.

Each follow-up was a single-EP plan that picked up later
without changing M3's signatures — both delivered ones widened
the surface without narrowing it.
