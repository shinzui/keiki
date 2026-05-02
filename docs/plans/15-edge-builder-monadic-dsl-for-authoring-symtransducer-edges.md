---
id: 15
slug: edge-builder-monadic-dsl-for-authoring-symtransducer-edges
title: "Edge-builder monadic DSL for authoring SymTransducer edges"
kind: exec-plan
created_at: 2026-05-02T13:05:18Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
---

# Edge-builder monadic DSL for authoring SymTransducer edges

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

Today, defining a `SymTransducer` (the symbolic-register transducer that is
keiki's source of truth) means writing every edge as a record literal that
threads several typed AST constructors by hand. Even after MasterPlan 3
retired the per-constructor authoring boilerplate at the example layer and
MasterPlan 6 retired the v1 escape hatches and added a static `Disjoint`
check on `combine`, the remaining surface is still heavy: every register
write is `USet (#slot :: IndexN "slot" Regs T) (term)`; updates are
stitched with `combine` (now type-level checked but still infix-by-hand);
outputs are nested-pair `OFCons … OFNil` chains; the edge itself is a
`Edge { guard = …, update = …, output = Just $ pack …, target = … }`
literal. The type-level state evolution (the typed register file plus the
`(w :: [Symbol])` written-slot index on `Update`) is doing useful work,
but the syntax around it makes the average-developer experience harder
than the formalism warrants.

After this plan, a novice can author the same transducer as a do-block
that reads almost like an imperative state-machine description. The
existing `Keiki.Core` AST is unchanged; the new module `Keiki.Builder`
sits on top and compiles do-blocks down to that AST. The two example
aggregates (`Keiki.Examples.EmailDelivery`,
`Keiki.Examples.UserRegistration`) ship a builder-form transducer
alongside the existing AST-form one, and a test asserts the two produce
byte-identical behaviour on the canonical command sequence.

Concretely, after this plan a contributor can write:

    {-# LANGUAGE QualifiedDo #-}      -- or RebindableSyntax — M1 picks
    import qualified Keiki.Builder as B

    emailDelivery :: SymTransducer (HsPred EmailRegs EmailCmd)
                                   EmailRegs EmailVertex
                                   EmailCmd EmailEvent
    emailDelivery = B.buildTransducer EmailPending emptyEmailRegs B.do

      B.from EmailPending B.do
        B.onCmd inCtorSendEmail $ \d -> B.do
          #emailRecipient .= d.recipient
          #emailSubject   .= d.subject
          #emailSentAt    .= d.at
          B.emit wireEmailSent
            EmailSentData { recipient = d.recipient
                          , subject   = d.subject
                          , at        = d.at }
          B.goto EmailSentVertex

      B.from EmailSentVertex (B.pure ())  -- terminal

The `(.=)` operator's left side is the same `#label` syntax users write
today (the existing `IsLabel s (IndexN s rs r)` instance from MP-6
EP-18 resolves it). Each `(.=)` extends a type-level `(w :: [Symbol])`
written-slot index threaded through the builder's indexed-monad
carrier, so a duplicated label fails to type-check at the offending
line — the same `Disjoint`-driven static check `combine` carries today,
inherited mechanically from the smart constructor.

…and observe `cabal test` produce identical pass results to the hand-written
form, with the line-count of the example file dropping by ~30%.

The user-visible behaviour is verified by:

1. `cabal build` succeeds under GHC 9.12.x.
2. `cabal test all` passes the existing tests (107 on master at plan
   draft time, per MP-6 EP-15 M0) **plus** a new `Keiki.BuilderSpec`
   and two cross-form equivalence tests
   (`Keiki.Examples.EmailDeliveryBuilderSpec`,
   `Keiki.Examples.UserRegistrationBuilderSpec`) that assert the
   builder-form transducer produces the same trace as the AST-form one
   on the canonical command sequence, for a final test count of ≥117.
3. The `wc -l` of `src/Keiki/Examples/UserRegistration.hs` drops from
   385 (post-MP-6 baseline) to under 310 (target ≥20% reduction) when
   its `userRegEdges` function is migrated to the builder.
   EmailDelivery shrinks from 185 to under 150. The post-MP-6 LOC is
   higher than pre-MP-6 (385 vs 355; 185 vs 165) because MP-6 EP-18
   replaced the bare `Index Regs T` annotations with slot-name-tagged
   `IndexN "name" Regs T`, doubling the slot-name token count per
   USet line; the builder removes that duplication entirely (the
   slot name appears exactly once, in `(.=)`'s `#label`).


## Progress

This section tracks granular progress. Update at every stopping point: tick
completed items with a date, split partial items into "done" and "remaining"
entries, add new items as discovered.

- [x] M0: Verify prerequisites — record GHC version, baseline test count, baseline LOC of both example files. (MP-6 is Complete on master at draft time; no per-child status record needed.) Completed 2026-05-02.
- [x] M1: Settle builder shape — write the design note `docs/research/edge-builder-dsl-shape.md` resolving the open questions (do-notation mechanism `QualifiedDo`-vs-`RebindableSyntax`, `(.=)` lifting, `emit` shape, `from`/`onCmd` shape, error-message shape, error reporting). Append a paragraph to `docs/research/dsl-shape-for-symbolic-register.md`'s "Open follow-ups" section pointing at the new note. Completed 2026-05-02.
- [x] M2: Spike — implement a throwaway `EdgeBuilderSpike.hs` against a coffee-dispenser two-vertex toy. Show the builder compiles to the same `Edge` AST as a hand-written reference; validated by per-edge `delta`/`omega` agreement on a short input log. Decide whether the spike's shape is what M3 ships or needs revision; record verdict. Completed 2026-05-02. Verdict: **shape revised**, design note amended in lockstep — see Surprises & Discoveries entry "EP-15 M2 spike findings".
- [ ] M3: Implement the production module `src/Keiki/Builder.hs` and expose it from `keiki.cabal`. Surface includes `buildTransducer`, `from`, `onCmd`, `onEpsilon`, `(.=)`, `emit`, `noEmit`, `goto`, `requireEq`, `requireGuard`. Distinct-targets check happens at builder-finalize time and produces a precise error message.
- [ ] M4: Migrate `Keiki.Examples.EmailDelivery`'s `emailDeliveryEdges` to the builder. Keep the AST-form value behind a new internal name (`emailDeliveryAST`) for the equivalence test. Add `test/Keiki/Examples/EmailDeliveryBuilderSpec.hs` asserting `delta`/`omega` agree on the single canonical command. Confirm the migrated file's LOC dropped by the targeted amount.
- [ ] M5: Migrate `Keiki.Examples.UserRegistration`'s `userRegEdges` to the builder. Same structure: AST form preserved as `userRegAST`, builder form named `userReg`, equivalence test added. Confirm `Keiki.Examples.UserRegistrationSpec` still passes (it uses `userReg` by name).
- [ ] M6: Add unit tests in `test/Keiki/BuilderSpec.hs` covering: single `(.=)`, sequential `(.=)` with distinct slots, duplicate `(.=)` to the same slot fails, `emit` round-trips through `solveOutput`, `noEmit` produces an ε-edge, `goto` sets `target`, missing `goto` fails, `requireEq` extends the guard, `onEpsilon` (no `onCmd`) builds a guard-only edge.
- [ ] M7: Documentation — update `docs/research/dsl-shape-for-symbolic-register.md` with a new §"Authoring DSL on top of the AST" linking to the builder module's haddock. If `docs/foundations/06-where-to-go-next.md` references the AST surface as the authoring path, update it to point at the builder first.


## Surprises & Discoveries

(None yet — to be populated as work proceeds. Record any deviation from the
plan, any optimizer/typechecker behaviour that shaped the final shape, and
any discovered limit of the builder DSL with concise evidence.)

- 2026-05-02 — `nix-shell` is unnecessary on this dev machine: `z3`,
  `ghc-9.12.3`, and `cabal-3.16.1.0` are already on PATH (z3 supplied
  by `/nix/var/nix/profiles/default`). Running `cabal build` / `cabal
  test` directly works; the plan's `nix-shell -p z3 --run "..."` form
  is still the documented portable entry point but the shorter form
  is what M0 actually executed.

- 2026-05-02 (M1) — The design note overshot the plan's
  ≤300-line target (came in at ~470 lines). The overshoot is in the
  per-question prose and the worked-example section; the seven
  questions each justify their answer with ≥1 paragraph of context
  rather than a one-liner. M2/M3 consume the note verbatim, so the
  note stays at its current length; if the longer form turns out to
  hide the contract, M2's spike-completion will note it and a follow-
  up commit will tighten.

- 2026-05-02 (M2 spike findings) — Two design adjustments forced
  by the spike, both amended into `docs/research/edge-builder-dsl-shape.md`
  in lockstep:

  1. **`#name .= …` does not type-check.** The `IsLabel s (IndexN
     s rs r)` instance in `Keiki.Internal.Slots` is shaped so GHC
     will not commit to `s ~ "name"` when `s` is a quantified type
     variable in `(.=)`'s signature (the pattern-side `s` appears
     at two positions in the constraint head; GHC defers
     commitment without an explicit annotation). The existing AST
     works around this with `(#name :: IndexN "name" Regs T)`. The
     builder needs to remove that annotation.

     Resolution: introduce `slot :: forall name rs r. (KnownSymbol
     name, HasIndexN name rs r) => IndexN name rs r` and have the
     user write `slot @"name" .= …`. The TypeApplication pins the
     symbol, GHC discharges `HasIndexN` from the EdgeBuilder's
     `rs`. Slot name still appears once. The `#name` form is left
     for a future GHC release or a class-driven label resolution
     fix.

  2. **`B.do` cannot be used for the outer `from`/`buildTransducer`
     blocks.** `QualifiedDo` redirects to a single named `(>>=)`,
     but the builder has three monad layers: `VertexBuilder`
     (plain), `EdgeListBuilder` (plain), and `EdgeBuilder`
     (indexed). Trying to use `B.do` for all three fails to
     type-check because the indexed bind cannot accept a plain-
     monad argument.

     Resolution: only the per-edge body uses `B.do`. Outer layers
     use plain `do`. Documented in the design note's Q4. The
     three-layer design is reflected in the M3 surface signatures.

  Both findings shipped to the design note. M3 will inherit the
  revised shape verbatim.


## Decision Log

The seed entries below capture decisions reached while drafting this plan.
Subsequent decisions made during M1 and beyond append below them with a
date.

- Decision: Default operator name for register-slot assignment is `(.=)`.
  Rationale: aeson, lens, and `mtl`'s `MonadState` all use `(.=)` for "assign
  to a slot." Reusing the precedent makes the builder read naturally to
  Haskell-experienced users. The operator's semantics in keiki is *neither*
  `KeyValue` (aeson) nor a `MonadState` setter — it emits a `USet` into a
  builder writer. Users importing `lens` in the same module hide it via
  `import Control.Lens hiding ((.=))`. The keiki haddock states this
  explicitly so users coming from those libraries do not expect mid-edge
  read-back semantics (which copyless updates do not allow).
  Date: 2026-05-02

- Decision: This is a standalone ExecPlan, not a child of a master plan.
  Rationale: MP-3 ("Keiki.Generics DX follow-ups") closed on 2026-05-01
  with all three children Complete. The edge-builder DSL is thematically
  continuous (authoring DX) but addresses a different surface (per-edge
  authoring, not per-constructor scaffolding) and has a single
  validation gate (the two example migrations both pass). Single-EP
  themes precedent: EP-7 (GHC upgrade). If a sibling DX initiative
  appears later (e.g., a per-vertex builder, or a quasi-quoter), promote
  this to MP-6 retroactively.
  Date: 2026-05-02

- Decision: The plan does not modify `Keiki.Core` or any other module
  the `SymTransducer` AST depends on. The builder is purely additive:
  it lives in a new module `Keiki.Builder`, consumes the existing AST
  constructors, and produces values of the existing AST types.
  Rationale: the AST is the source of truth and is exercised by every
  downstream module (`Keiki.Acceptor`, `Keiki.Composition`,
  `Keiki.Decider`, `Keiki.Symbolic`, `Keiki.Generics`, all examples and
  tests). Touching it would balloon scope and invalidate MP-3's
  closure. Keeping the builder additive lets it ship without touching
  any consumer; users who prefer the AST keep writing the AST.
  History: MP-6 (Complete 2026-05-02) modified `Keiki.Core` to remove
  `OFn`, `mkOut`, `PMatchC`, `matchCmd`, and `unsafeCombine`, and to
  reshape `Update rs ci` to `Update rs w ci` with a static `Disjoint
  w1 w2` constraint on the smart constructor `combine`. This plan
  builds *on top* of post-MP-6 master and consumes only the
  surviving surface.
  Date: 2026-05-02

- Decision: M1 produces a focused design note rather than baking the
  carrier-monad shape into this plan up front.
  Rationale: at draft time the carrier shape is genuinely open. Three
  candidates are viable (Free monad with an interpreter, indexed
  Writer over a builder-state record, plain Reader-of-mutable-builder
  via `ST`). Each has different error-reporting and complexity
  tradeoffs. The spike (M2) validates the M1 choice on a toy
  transducer before M3 commits to it.
  Date: 2026-05-02

- Decision: The two example migrations preserve the original AST form
  under a renamed binding for the lifetime of this plan, so the
  equivalence test can compare both forms.
  Rationale: the goal is not to retire the AST surface — it remains
  the load-bearing source of truth — but to validate that the builder
  produces the same behaviour. Keeping
  `userRegAST`/`emailDeliveryAST` alongside the builder forms
  `userReg`/`emailDelivery` (the names every other test uses) means
  `Keiki.Examples.UserRegistrationSpec`, `Keiki.AcceptorSpec`,
  `Keiki.CompositionSpec` etc. need no changes: they import `userReg`
  and get the builder version. Once M5 lands and is stable, a
  follow-up plan may delete `userRegAST`; this plan does not.
  Note: the AST is intentionally *less* of an escape hatch after MP-6
  (EP-16, EP-17, EP-18). The builder is the recommended authoring
  surface; the AST is what it compiles to.
  Date: 2026-05-02

- M0 baseline (2026-05-02): GHC 9.12.3, cabal-install 3.16.1.0,
  z3 4.16.0. `cabal test` is green with **107 examples, 0
  failures**. Example LOC: `src/Keiki/Examples/EmailDelivery.hs` is
  **185 lines**; `src/Keiki/Examples/UserRegistration.hs` is **385
  lines**. These match the post-MP-6 baseline figures the plan's
  Purpose / Big Picture cites verbatim, so no re-baselining is
  needed.
  Date: 2026-05-02

- Decision: Builder carrier is an indexed monad threading the
  type-level written-slot set `(w :: [Symbol])`.
  Rationale: MP-6 EP-18 made `combine :: Disjoint w1 w2 => Update rs
  w1 ci -> Update rs w2 ci -> Update rs (Concat w1 w2) ci` the smart
  constructor for `Update`, with the raw `UCombine` left
  unconstrained for internal walks (per MP-6 retrospective lesson #1).
  The builder is a *public introduction point* — its purpose is to
  give aggregate authors a tighter authoring surface — so it must
  inherit the static `Disjoint` check mechanically, the way `combine`
  does. A plain `Monad` carrier with a value-level slot log would
  force the builder to emit either the raw `UCombine` (forfeiting the
  static check at the do-block level) or `combine` with manual
  constraint discharge (impossible without `unsafeCoerce`). The
  indexed-monad path threads `w` at the type level through the
  do-block; each `(.=)` produces a builder step from `w` to
  `Concat '[s] w` and inherits `Disjoint '[s] w` at the type level,
  so a duplicated `(.=)` fails to type-check at the offending line.
  GHC machinery: `RebindableSyntax` or `QualifiedDo` (GHC ≥9.0,
  available on master under GHC 9.12.3). M1 picks one and records
  the verdict; `QualifiedDo` is the default recommendation because
  it's local to the builder import (`B.do`) and does not affect any
  other do-block in the user's module.
  Date: 2026-05-02


## Outcomes & Retrospective

(To be filled during and after implementation. At each milestone-completion,
add a paragraph capturing what was achieved, what surprised, and what was
deferred. At plan completion, summarize against the Purpose / Big Picture
section.)


## Context and Orientation

This section gives a complete novice everything they need to follow the plan
without prior context.

### What `keiki` is

`keiki` is a Haskell library that provides a pure core for event sourcing,
workflow engines, and durable execution. Its formalism is the
**symbolic-register transducer** ("SymTransducer"): a finite control graph
whose vertices are user-defined states and whose edges carry a guard
(predicate over the input symbol and a register file), an update
(register writes that depend on the input), an optional output (an event
type), and a target vertex. The whole library hangs off the
`SymTransducer` type defined in `src/Keiki/Core.hs`.

A user-defined transducer compiles down to four AST values:

- A **register file** schema: a type-level list of `(Symbol, Type)` pairs
  declaring named typed slots. Example
  (`src/Keiki/Examples/EmailDelivery.hs`, lines 84–88):

        type EmailRegs =
          '[ '("emailRecipient", Email)
           , '("emailSubject",   Subject)
           , '("emailSentAt",    UTCTime)
           ]

- A **vertex enum** for control state. Example: `EmailPending |
  EmailSentVertex`.

- A **command sum type** (`ci` parameter) and an **event sum type**
  (`co` parameter), with one record-payload per non-singleton
  constructor. Example: `data EmailCmd = SendEmail SendEmailData`.

- The transducer itself: a `SymTransducer phi rs s ci co` value built
  out of `Edge` records, one per outgoing transition.

### What an `Edge` looks like today

`src/Keiki/Examples/EmailDelivery.hs:163` shows the only edge in that
example. Reproduced here verbatim (post-MP-6 form, with the static
`Disjoint`-checked `combine` and the slot-name-tagged `IndexN`):

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

The visible boilerplate that this plan replaces:

- `USet (#x :: IndexN "x" Regs T) …` — every register write needs the
  full `IndexN "x" Regs T` annotation because the `IsLabel` resolution
  alone cannot disambiguate a label that appears in more than one slot
  list in scope. Post-MP-6 EP-18, the annotation also pins the slot
  name twice (once via the label, once via the `Symbol` type
  argument); the builder removes both visible duplications.
- `combine` chains — sequential register writes are stitched with the
  smart-constructor `combine`, which carries a `Disjoint w1 w2`
  constraint that GHC discharges at compile time. The static check
  fires when a slot label is repeated, but the syntax is still verbose
  (every `combine` is an explicit infix call). The builder collapses
  the chain into a sequence of `(.=)` lines, with the same
  `Disjoint`-driven static check inherited mechanically.
- `OFCons … OFNil` chains — the `OutFields` HList is built by hand,
  one constructor per output field, terminated with `OFNil`. The order
  must match the wire constructor's field order in the source record.
- The `Edge { … }` record literal — every edge repeats the same four
  field labels.

Note that the per-constructor declarations (`isSendEmail`,
`inpSendEmail`, `inCtorSendEmail`, `wireEmailSent`) **are already
auto-generated** by the `deriveAggregateCtors` and `deriveWireCtors` TH
splices that MP-3 EP-8 delivered. Those splices fire on
lines 103–105 (`deriveAggregateCtors`) and 117–119 (`deriveWireCtors`)
of `src/Keiki/Examples/EmailDelivery.hs`. This plan does **not** touch
those splices; the per-constructor declarations they emit are inputs
to the new builder.

### Recent context: MP-6 escape-hatch retirements (Complete)

`docs/masterplans/6-retire-remaining-v1-escape-hatches-in-pure-core-ofn-pmatchc-unsafecombine-static-check.md`
(MP-6) closed **Complete** on 2026-05-02. All four of its child plans
are Complete and have shipped to master. The relevant changes for
this plan:

- `OFn` (the opaque `OutTerm` constructor) and `mkOut` are removed.
  This plan never produced them.
- `PMatchC` (the opaque `HsPred` constructor) and `matchCmd` are
  removed. This plan never produced them.
- `Update (rs :: [Slot]) (ci :: Type)` is now
  `Update (rs :: [Slot]) (w :: [Symbol]) (ci :: Type)`, where `w` is
  the type-level set of slots written by the update. `combine` is
  the smart constructor with a `Disjoint w1 w2` constraint; the raw
  `UCombine` data constructor is unconstrained (per MP-6's
  retrospective lesson on smart-vs-raw-constructor invariant
  promotion). `unsafeCombine` is removed. The post-MP-6 shape, now
  in `src/Keiki/Core.hs`:

        data Update (rs :: [Slot]) (w :: [Symbol]) (ci :: Type) where
          UKeep    :: Update rs '[] ci
          USet     :: ... => IndexN s rs r -> Term rs ci r
                          -> Update rs '[s] ci
          UCombine :: Update rs w1 ci
                   -> Update rs w2 ci
                   -> Update rs (Concat w1 w2) ci   -- raw, unconstrained

        combine :: Disjoint w1 w2
                => Update rs w1 ci
                -> Update rs w2 ci
                -> Update rs (Concat w1 w2) ci      -- smart, checked
        combine = UCombine

- `IndexN s rs r` is the new slot-name-tagged variant of `Index rs r`.
  The existing `IsLabel` instance was updated; user-facing `#email`
  syntax still resolves but now produces `IndexN "email" rs T`.
  Type annotations on slot writes have shifted from
  `(#x :: Index Regs T)` to `(#x :: IndexN "x" Regs T)` — the slot
  name appears twice (label + Symbol arg).
- `Edge`'s `update` field is existentially quantified over `w`. GHC
  does not generate a record selector for an existential field, so
  consumers use either pattern-binding (`Edge { update = u } -> …`)
  or the helper functions `applyEdgeUpdate` / `edgeReadsInput`
  introduced by EP-18 in `Keiki.Core`.
- `-Wredundant-constraints` fires on the `Disjoint` constraint of
  `combine` (and on `Disjoint (Names rs1) (Names rs2)` in
  `Keiki.Composition.compose`). MP-6 suppressed it module-locally on
  both modules with a justifying comment.

Implications for the builder:

- The builder is a *public introduction point* (per MP-6's smart-vs-
  raw-constructor lesson) and so must inherit the static `Disjoint`
  check mechanically. The carrier is an indexed monad threading
  `(w :: [Symbol])`; each `(.=)` extends `w` and inherits the
  constraint from `combine` at the smart-constructor call site.
- The builder uses `IndexN`-style slot writes internally but the
  user-facing surface is unchanged — `#slotname` syntax resolves to
  `IndexN s rs r` automatically.
- The builder module enables `-Wno-redundant-constraints` at the
  module level for the same reason `Keiki.Core` and
  `Keiki.Composition` do.
- The existential `w` on `Edge`'s `update` field means the
  builder's `Edge` constructor call packs the existential at the
  end of each edge's do-block. This is mechanical: the builder
  produces `Edge { … , update = u }` for whatever final `u :: Update
  rs w ci` the do-block accumulates, and the existential closes
  over `w`.

### Numbering namespace note

MP-6's narrative uses the label "EP-15" to refer to its design
milestone, whose plan file is `docs/plans/14-...md`. This plan,
file `docs/plans/15-...md`, has the same numerical id (15) by file
numbering. The two are separate plans — MP-6's "EP-15" is its
design milestone (Complete); this plan is the edge-builder DSL
authoring layer. When citing them, prefer file paths over the
short "EP-15" label to avoid confusion. MP-6 is closed and its
narrative references will not be revised; readers must rely on the
file-path discipline.

### Key files touched by this plan

- **New** `src/Keiki/Builder.hs` — the builder module. Roughly 400–500
  lines including haddock.
- **New** `test/Keiki/BuilderSpec.hs` — unit tests for the builder
  combinators.
- **New** `test/Keiki/Examples/EmailDeliveryBuilderSpec.hs` — equivalence
  test between AST-form and builder-form `emailDelivery`.
- **New** `test/Keiki/Examples/UserRegistrationBuilderSpec.hs` —
  equivalence test between AST-form and builder-form `userReg`.
- **New** `docs/research/edge-builder-dsl-shape.md` — the M1 design
  note.
- **Modified** `src/Keiki/Examples/EmailDelivery.hs` — `emailDeliveryEdges`
  is rewritten in the builder; the AST form is preserved as a
  module-internal binding for the equivalence test.
- **Modified** `src/Keiki/Examples/UserRegistration.hs` — same
  treatment for `userRegEdges`.
- **Modified** `keiki.cabal` — adds the new library module
  `Keiki.Builder` to `exposed-modules` and the new test modules to
  `keiki-test`'s `other-modules`.
- **Modified** `test/Spec.hs` — register the three new spec modules
  with hspec. (Read this file at M3 start to confirm its discovery
  pattern; the existing modules are listed by name there.)
- **Modified** `docs/research/dsl-shape-for-symbolic-register.md` — a
  new §"Authoring DSL on top of the AST" pointing to the builder.
- **Possibly modified** `docs/foundations/06-where-to-go-next.md` — if
  it currently steers readers at the AST authoring path, update it to
  start with the builder.

### The libraries already in use

`keiki.cabal` (lines 48–52) currently declares:

    build-depends:      base ^>= 4.21,
                        sbv >= 11.7 && < 15,
                        template-haskell ^>= 2.23,
                        text ^>= 2.1,
                        time ^>= 1.12

This plan adds **no new dependencies**. The builder is implemented in
plain Haskell over the existing `Keiki.Core` AST. (M1 may discover that a
small reusable monad transformer from `mtl` would simplify the carrier;
if so, M1's design note records the tradeoff and either justifies the
hand-rolled approach or amends the dep list. Default position: hand-roll
to keep the dependency footprint zero — this matches the precedent set by
the `RegFile` representation choice in
`docs/research/dsl-shape-for-symbolic-register.md`.)

### Terms a novice might not know

- **AST** ("abstract syntax tree"): the data structure produced by
  parsing or, here, by hand-construction. `Term`, `Update`, `OutTerm`,
  `Edge`, and `SymTransducer` are AST types defined in
  `src/Keiki/Core.hs`.
- **DSL** ("domain-specific language"): a syntactic surface tailored to
  one domain. The "edge-builder DSL" is the new monadic surface this
  plan introduces; it compiles to the existing AST.
- **GADT** ("generalized algebraic data type"): a Haskell extension that
  lets data constructors refine type parameters. `RegFile`, `Index`,
  `Term`, `Update`, `OutFields`, `OutTerm`, `HsPred` are all GADTs.
- **HList** ("heterogeneous list"): a list whose elements may have
  different types, indexed by a type-level list. `RegFile rs` and
  `OutFields rs ci fs` are HLists.
- **OverloadedLabels**: a GHC extension that lets `#email` resolve to a
  user-defined value (here, an `Index UserRegRegs Email`) via the
  `IsLabel` typeclass. Already in use throughout the example modules
  via the `IsLabel` instance in `src/Keiki/Core.hs:152`.
- **OverloadedRecordDot**: a GHC extension (default-on in keiki via
  `keiki.cabal:25`) that lets `d.email` resolve to the record-field
  selector `email d`. Used in the builder's payload-projection sugar.
- **TH** ("Template Haskell"): the GHC mechanism for compile-time
  metaprogramming. `Keiki.Generics.TH` uses it to emit per-constructor
  declarations. This plan does **not** use TH; the builder is plain
  Haskell.
- **ε-edge** ("epsilon-edge"): an edge whose `output` is `Nothing`. It
  consumes an input symbol and updates registers/state without
  emitting an event. The builder exposes `noEmit` for this.

### Build and test commands

The repository builds and tests under cabal with `nix-shell -p z3` to
provide the SMT solver SBV depends on.

    cd /Users/shinzui/Keikaku/bokuno/keiki
    nix-shell -p z3 --run "cabal build"
    nix-shell -p z3 --run "cabal test"

Expected baseline (verified at M0):

    Test suite keiki-test: PASS
    Tests passed: 107  (the count cited by MP-6 EP-15 M0 on
                        2026-05-02; M0 records the actual current
                        number, which may be higher if EP-16/EP-17/
                        EP-18 have landed in the meantime)

If `nix-shell` is unavailable, install z3 via `brew install z3` and run
`cabal test` directly.


## Plan of Work

The work splits into **eight milestones** (M0–M7). Each milestone is
independently verifiable; each ends with a build-and-test green and a
specific observable artefact.

### M0 — Prerequisites

A baseline run: confirm the repo builds, tests pass, and record the
GHC version, the cabal version, the SBV version, the test count, and
the LOC of both example files we will migrate. These numbers anchor
the M4–M7 success criteria. No code change.

End state: a Decision Log entry recording the GHC + library + LOC +
test-count baseline.

Acceptance: `nix-shell -p z3 --run "cabal test"` is green and we have
recorded the example LOC and the test count.

### M1 — Settle the builder shape

A focused design milestone. Produces `docs/research/edge-builder-dsl-shape.md`
that resolves the open questions below and is the contract M2 and M3
consume. The design note is short (target ≤300 lines) and concrete: it
shows the chosen shape on the EmailDelivery example end-to-end. It
deliberately does **not** include the User Registration example to keep
the note focused; that aggregate is covered at M5.

Open questions M1 resolves (Q1–Q7 are intrinsic to the builder
design):

1. **Indexed-monad carrier shape.** The carrier kind is settled by
   the Decision Log entry above: indexed monad threading
   `(w :: [Symbol])`. The remaining open question is the do-notation
   mechanism. Two candidates:
   - *`QualifiedDo` (GHC ≥9.0).* `B.do { … }` re-binds `(>>=)` and
     `(>>)` to indexed analogues exported from `Keiki.Builder`. Local
     to the builder import; any other do-block in the user's module
     remains plain `Monad`. Requires no extension at the call site
     beyond `LANGUAGE QualifiedDo`. **Default recommendation.**
   - *`RebindableSyntax`.* Re-binds `(>>=)`, `(>>)`, `pure`, `return`,
     and `fail` module-wide. Heavier — every do-block in the user's
     module is now using the rebound names. Reasonable if the user's
     module is dedicated to defining a single transducer; awkward
     otherwise.
   M1 picks one and records the verdict with a worked-example error
   message for a duplicate-`(.=)` misuse under the chosen mechanism
   (the message must read clearly enough that a novice can locate
   the duplicated slot from the GHC error alone).

2. **`(.=)` shape.** The LHS is `Index rs r`; the RHS must be coerced
   to `Term rs ci r`. Three candidates:
   - *RHS is always a `Term`*, with a numeric `Term` literal (`lit`)
     wrapper required for plain Haskell values (`#registeredAt .= lit
     (t 0)`). Verbose but unambiguous.
   - *RHS overloaded via a typeclass `class ToTerm a rs ci r | a -> r`*
     so `Term`s and `r`-typed Haskell values both work.
     `#registeredAt .= t 0` works without `lit`. Opens a small
     overlap-instance dance because `Term rs ci r` and bare `r` need to
     overlap.
   - *RHS is always an `r`*, with the user wrapping with explicit
     `proj`/`inpStart` for register/input reads (mirroring how
     EmailDelivery already writes them). Loses no expressiveness because
     the existing helpers stay; just less ergonomic for the literal
     case.
   M1 picks one. Default recommendation in this plan: option 2
   (typeclass-overloaded RHS), with a clearly documented overlap rule
   and a fallback to `lit` when the overlap fails.

3. **`emit` shape.** Two candidates:
   - *Field-keyed via record-syntax sugar.* The user writes
     `emit RegistrationStarted { email = ..., confirmCode = ..., at =
     ... }`; the builder consumes a Haskell record value and inverts
     it through `mkWireCtorVia`'s existing `Generic` machinery to
     produce an `OPack`. This re-uses the field-name discipline GHC
     already enforces.
   - *Function over the post-edge `RegFile`*: the user writes `emit
     wireEmailSent $ \rf -> EmailSentData { recipient = rf #emailRecipient,
     ... }` (a closed function over the post-update register file). The
     builder partially evaluates the function structurally to recover
     the `OutFields` AST.
   The second form is more flexible (lets the user mention `inpFoo
     #x` arbitrarily inside the function body) but requires structural
     evaluation that the existing `OutTerm` does not support. The first
     form is more restrictive (every output field is a single `Term`,
     which already covers every existing example) but ships immediately
     because `OPack` already takes that shape. Default recommendation:
     start with the first form; add the second in a follow-up plan if
     real aggregates need it.

4. **Vertex grouping (`from`).** Two candidates:
   - *Vertex-keyed sub-builders.* The top-level do-block contains
     `from V $ do { onCmd …; onCmd … }` blocks; the result is the
     `Vertex -> [Edge …]` function the `SymTransducer.edgesOut` field
     expects. Vertices not mentioned default to `[]` (terminal). The
     `Bounded`/`Enum` instance on the vertex enum is used for the
     completeness check (every constructor either appears in a `from`
     block or is asserted terminal).
   - *Flat list of `(Vertex, EdgeBuilder)`*: the do-block produces
     `[(EmailPending, edge1), (EmailSentVertex, edge2), …]` and the
     library pivots it. Less ergonomic for multi-edge vertices.
   Default: vertex-keyed.

5. **Distinct-targets enforcement.** The slot-set is type-level
   (`w :: [Symbol]`, accumulated through the indexed-monad carrier).
   The check is a `Disjoint '[s] w` constraint that GHC discharges at
   each `(.=)` — duplicates fail to type-check, with an error
   pointing at the offending line. The emitted AST uses `combine`
   directly. M1's job is to pick the exact shape of the error
   message and verify (with a worked example) that the duplicate-
   slot case produces a readable diagnostic. The
   `-Wredundant-constraints` warning will fire on the builder's
   `combine` use sites (per MP-6 EP-18 retrospective); the builder
   module suppresses it at module level with the same justification
   `Keiki.Core` and `Keiki.Composition` use.

6. **`goto` and termination.** Every `onCmd`/`onEpsilon` block must end
   with exactly one `goto V`. The builder enforces this at finalize
   time; missing `goto` produces a runtime error naming the edge.
   Multiple `goto`s in the same block produce a runtime error.

7. **Module placement and naming.** The default name is
   `Keiki.Builder`. Alternatives considered: `Keiki.DSL` (heavier,
   risks confusion with the AST being "the DSL"), `Keiki.Edge`
   (narrower than the surface delivers — the module also has
   `from`/`buildTransducer`). Default recommendation: `Keiki.Builder`.

End state: `docs/research/edge-builder-dsl-shape.md` exists and answers
each of the seven questions above with a worked EmailDelivery
example in the chosen surface; a one-paragraph addendum to
`docs/research/dsl-shape-for-symbolic-register.md` points at it.

Acceptance: a peer review (or a re-read by the author after a break)
can answer "what does the User Registration `RequiresConfirmation`
vertex look like in the new DSL?" by reading only the M1 note and the
existing `userReg` source. If the answer is unclear, M1 is not done.

### M2 — Spike on a coffee-dispenser toy

A throwaway spike. Implement the M1 surface against a tiny two-vertex,
one-command, one-event toy transducer (the canonical "coffee dispenser"
shape: `Idle --[Insert]--> Brewing --[ε on Continue]--> Idle`). The
spike's purpose is to validate that the M1 design compiles, that error
messages on misuse (duplicate `(.=)`, missing `goto`, multiple `goto`,
out-of-scope label) read clearly, and that the resulting `Edge` AST is
structurally what a hand-written reference produces.

The spike lives in `test/Keiki/BuilderSpike.hs` (test-only,
not exported from the library) so it can be deleted after M3 lands.
A small set of in-spec assertions:

- `delta` and `omega` of the builder-form transducer agree with the
  reference on a 4-step input log.
- A test that intentionally calls `(.=)` twice on the same slot
  produces a runtime error matching a specific substring.
- A test that omits `goto` produces a specific runtime error.

End state: `Keiki.BuilderSpike` exists and passes; if the spike
revealed shape revisions, the M1 design note is amended and
`docs/research/edge-builder-dsl-shape.md` is rewritten in lockstep.

Acceptance: `nix-shell -p z3 --run "cabal test --test-options='--match
\"Keiki.BuilderSpike\"'"` is green; the design note still matches the
spike's surface verbatim.

### M3 — Implement `Keiki.Builder`

Promote the spike's design to a production module. The new file is
`src/Keiki/Builder.hs` with full haddock. `keiki.cabal` adds it to
`exposed-modules`. The signature surface (subject to M1
ratification — the indexed-monad mechanism is `QualifiedDo` by
default, recorded in the Decision Log entry on the indexed-monad
carrier):

    -- The edge-builder carrier, indexed by the type-level slot-set.
    -- `w` is the set of slots written *before* this builder step;
    -- `w'` is the set written *after*. Each `(.=)` extends `w` to
    -- `w' ~ Concat '[s] w` and inherits a `Disjoint '[s] w`
    -- constraint from `combine`.
    data EdgeBuilder rs ci co s (w :: [Symbol]) (w' :: [Symbol]) a

    -- Indexed Functor / Applicative / Monad. The exact typeclass
    -- shape depends on M1's pick (do-notation library — built-in
    -- `IxFunctor`/`IxApplicative`/`IxMonad` newtypes hand-rolled in
    -- `Keiki.Builder`, or imported from a small dependency like
    -- `indexed-extras`). Default recommendation: hand-roll inside
    -- `Keiki.Builder` to keep the dep footprint zero.
    --
    -- The (>>=) and (>>) operators that `QualifiedDo` resolves
    -- against `B.do` blocks are exported as `(>>=)`, `(>>)`, `pure`,
    -- `return` from `Keiki.Builder` (or a sub-module
    -- `Keiki.Builder.Indexed` per M1).

    -- The vertex-block carrier.
    data VertexBuilder rs ci co s a

    instance Functor (VertexBuilder rs ci co s)
    instance Applicative (VertexBuilder rs ci co s)
    instance Monad (VertexBuilder rs ci co s)

    -- Top-level entry: produce a SymTransducer from an initial vertex,
    -- initial register file, and a do-block of `from V $ do …` clauses.
    buildTransducer
      :: (Bounded s, Enum s, Show s)
      => s
      -> RegFile rs
      -> VertexBuilder rs ci co s ()
      -> SymTransducer (HsPred rs ci) rs s ci co

    -- Group edges by source vertex.
    from :: s
         -> EdgeBuilder rs ci co s '[] w ()
         -> VertexBuilder rs ci co s ()

    -- Per-edge entry. The argument lambda receives a typed projection
    -- handle the user can call `d.fieldName` on, with OverloadedRecordDot.
    -- The lambda runs inside a fresh `EdgeBuilder` indexed from `'[]`
    -- (no slots written) to whatever set the body accumulates.
    onCmd
      :: InCtor ci ifs
      -> (PayloadProj ifs ci -> EdgeBuilder rs ci co s '[] w ())
      -> EdgeBuilder rs ci co s '[] w ()

    -- ε-edge entry: no input projection, no `onCmd` constructor match.
    onEpsilon :: EdgeBuilder rs ci co s '[] w ()
              -> EdgeBuilder rs ci co s '[] w ()

    -- Slot assignment. The fixity and operator precedence match aeson's
    -- (.= :: Text -> v -> Pair); infixr 6. The `Disjoint '[s] w`
    -- constraint is what gives the duplicate-slot static check.
    (.=) :: (Disjoint '[s] w, ToTerm v rs ci r)
         => IndexN s rs r
         -> v
         -> EdgeBuilder rs ci co s w (Concat '[s] w) ()
    infixr 6 .=

    -- Output: pin the wire ctor and the field map. Implementation
    -- depends on M1's emit choice.
    emit  :: WireCtor co fields
          -> OutFields rs ci fields
          -> EdgeBuilder rs ci co s w w ()
    -- (or, if M1 picks the field-keyed shape, a record-syntax variant.)

    -- ε-output for a non-ε-edge that produces no event.
    noEmit :: EdgeBuilder rs ci co s w w ()

    -- Set the edge's target vertex. Required exactly once.
    goto :: s -> EdgeBuilder rs ci co s w w ()

    -- Extend the edge's guard with an extra equality predicate.
    requireEq :: (Eq r, Typeable r)
              => Term rs ci r -> Term rs ci r
              -> EdgeBuilder rs ci co s w w ()

    -- Extend the edge's guard with an arbitrary HsPred.
    requireGuard :: HsPred rs ci -> EdgeBuilder rs ci co s w w ()

    -- A small overload typeclass so .= accepts both `Term rs ci r` and
    -- bare `r` values. (Or whatever shape M1 picks.)
    class ToTerm v rs ci r | v rs -> r where
      toTerm :: v -> Term rs ci r

End state: `Keiki.Builder` builds clean, the spike is rewritten on top
of it (or deleted), and one toy unit test inside `BuilderSpec` exercises
the surface.

Acceptance: `cabal build` is green with `Keiki.Builder` exposed;
`Keiki.BuilderSpec` (even if it has only one or two tests at this
point) passes.

### M4 — Migrate EmailDelivery

The smaller of the two example aggregates. One vertex with one edge,
plus the terminal vertex. The migration steps:

1. In `src/Keiki/Examples/EmailDelivery.hs`, rename the existing
   `emailDeliveryEdges` function to `emailDeliveryASTEdges` (still in
   the same file). The existing `emailDelivery :: SymTransducer …`
   value is renamed to `emailDeliveryAST` and built from
   `emailDeliveryASTEdges`. Both are added to the export list under
   a section comment "AST form (legacy, retained for equivalence
   tests)".
2. Add a new builder-form `emailDelivery` that uses
   `Keiki.Builder.buildTransducer` over the same vertices and
   commands. Export it under the existing top-level name (so every
   downstream consumer keeps working with no import change).
3. Add `test/Keiki/Examples/EmailDeliveryBuilderSpec.hs` with a single
   spec: for the canonical command `SendEmail (SendEmailData …)`,
   `delta emailDelivery EmailPending emptyEmailRegs cmd ==
   delta emailDeliveryAST EmailPending emptyEmailRegs cmd` and the
   same for `omega`.
4. Register the new spec in `test/Spec.hs` (mirrors how the existing
   `Keiki.Examples.UserRegistrationSpec` is registered).
5. Add the new test module to `keiki-test`'s `other-modules` in
   `keiki.cabal:59`.
6. Confirm the file's LOC dropped from 185 (post-MP-6 baseline) to
   under 150.

End state: `emailDelivery` is the builder form; `emailDeliveryAST` is
the legacy form; the equivalence test is green; the file is shorter.

Acceptance: `cabal test` is green; the Progress entry records the
exact post-migration LOC.

### M5 — Migrate UserRegistration

The flagship example. Five vertices, six edges, including the
non-trivial `RequiresConfirmation` vertex with two `inpConfirm
#confirmCode .== proj #confirmCode`-guarded confirm edges and a
resend that rotates the code. The migration steps mirror M4:

1. Rename `userRegEdges` → `userRegASTEdges`; add `userRegAST` value
   driving it.
2. Rewrite `userReg` over the builder:

        userReg = buildTransducer PotentialCustomer emptyRegs $ do

          from PotentialCustomer $ do
            onCmd inCtorStart $ \d -> do
              #email        .= d.email
              #confirmCode  .= d.confirmCode
              #registeredAt .= d.at
              emit wireRegistrationStarted (...)  -- per M1
              goto Registering

          from Registering $ do
            onCmd inCtorContinue $ \_d -> do
              emit wireConfirmationEmailSent (...)
              goto RequiresConfirmation

          from RequiresConfirmation $ do
            onCmd inCtorConfirm $ \d -> do
              requireEq (inpCtor inCtorConfirm #confirmCode)
                        (proj (#confirmCode :: Index UserRegRegs ConfirmationCode))
              #confirmedAt .= d.at
              emit wireAccountConfirmed (...)
              goto Confirmed
            onCmd inCtorResend $ \d -> do
              #confirmCode  .= d.code
              #registeredAt .= d.at
              emit wireConfirmationResent (...)
              goto RequiresConfirmation
            onCmd inCtorGdpr $ \d -> do
              #deletedAt .= d.at
              noEmit
              goto Deleted

          from Confirmed $ do
            onCmd inCtorGdpr $ \d -> do
              #deletedAt .= d.at
              emit wireAccountDeleted (...)
              goto Deleted

          from Deleted $ pure ()  -- terminal

   (The `…` in `emit` calls is filled in by whichever shape M1 picks
   for the `emit` operator.)

3. Add `test/Keiki/Examples/UserRegistrationBuilderSpec.hs` with the
   equivalence assertion across the canonical event log already
   defined in `test/Keiki/Examples/UserRegistrationSpec.hs:34` (the
   list `canonicalLog`). The spec re-derives the matching command
   sequence (mirroring `DeciderSpec`'s pattern, per the EP-10
   discovery noted in MP-3) and asserts both forms agree on every
   step.
4. Register the new spec in `test/Spec.hs` and `keiki.cabal`.
5. Confirm the file's LOC dropped from 385 (post-MP-6 baseline) to
   under 310.

End state: `userReg` is the builder form; `userRegAST` is the legacy
form; both `Keiki.Examples.UserRegistrationSpec` and the new
`UserRegistrationBuilderSpec` are green.

Acceptance: `cabal test` is green; the Progress entry records the
exact post-migration LOC.

### M6 — Builder unit tests

Backfill the hand-written unit tests against the production
`Keiki.Builder`. A new file `test/Keiki/BuilderSpec.hs` covers the
behaviours below, using a tiny in-test toy transducer (re-using or
adapting the M2 coffee-dispenser shape):

1. Single `(.=)` produces a `USet` whose evaluator agrees with a
   reference register update.
2. Sequential `(.=)` to distinct slots produces an `Update` whose
   evaluator agrees with the composite reference.
3. Sequential `(.=)` to the **same** slot fails with an error message
   containing the slot name and the source vertex.
4. `emit` followed by replay through `solveOutput` round-trips: for
   any input, `applyEvent t s regs (omega t s regs ci) == Just (s',
   regs')` whenever `delta t s regs ci == Just (s', regs')`.
5. `noEmit` produces an `Edge` whose `output` is `Nothing`.
6. `goto V` sets `target = V`.
7. Missing `goto` fails with an error message containing the edge
   index and the source vertex.
8. Multiple `goto`s fail with an error message containing the edge
   index and the source vertex.
9. `requireEq a b` extends the edge's `guard` with `PEq a b` (asserted
   by structural inspection of the resulting `HsPred`).
10. `onEpsilon` (no `onCmd`) builds an edge whose guard is `PTop` (or
    whatever the M1 design picks for "always") and whose update can
    still read input via `inpCtor`. (M1 must clarify whether this is
    allowed; default: ε-edges may not read input via `inpCtor`,
    matching the existing `checkHiddenInputs` warning rule.)

End state: `Keiki.BuilderSpec` covers ≥ 10 cases.

Acceptance: `cabal test` is green; the new spec contributes ≥10 to
the test count.

### M7 — Documentation

Three small writing tasks:

1. Append a §"Authoring DSL on top of the AST" to
   `docs/research/dsl-shape-for-symbolic-register.md` summarizing
   what the builder is, where it lives, and what it does not change
   (the AST is unchanged; the symbolic-register formalism is
   unchanged). Include a six-line excerpt of the EmailDelivery
   migration to make the visual difference concrete.
2. If `docs/foundations/06-where-to-go-next.md` currently steers
   readers at the AST authoring path, add a paragraph at the top
   redirecting them to `Keiki.Builder` first and listing the AST as
   the lower-level escape hatch.
3. The haddock on `Keiki.Builder` itself must be a complete tutorial:
   a worked EmailDelivery example end-to-end, the operator surface
   in one place, the error-message catalog (each kind of misuse with
   its message), and a "when to drop down to the AST" paragraph.

End state: a contributor reading only `Keiki.Builder`'s haddock and
the foundations doc can author a new aggregate without touching the
AST.

Acceptance: `cabal haddock` produces clean haddock for the new module
(no missing-docs warnings); a quick re-read of the modified docs
matches the M1 design note.


## Concrete Steps

The exact commands to run, in order. Working directory is
`/Users/shinzui/Keikaku/bokuno/keiki` throughout unless stated otherwise.

### M0 — baseline

    nix-shell -p z3 --run "cabal build"
    nix-shell -p z3 --run "cabal test"
    wc -l src/Keiki/Examples/EmailDelivery.hs
    wc -l src/Keiki/Examples/UserRegistration.hs

Expected (post-MP-6 baseline at draft time):

    Test suite keiki-test: PASS
    Tests passed: 107  (or higher; baseline drifts upward as
                        unrelated features land)
       185 src/Keiki/Examples/EmailDelivery.hs
       385 src/Keiki/Examples/UserRegistration.hs

Record the exact numbers in the Decision Log under
"M0 baseline (date)".

### M1 — design note

Create the file:

    touch docs/research/edge-builder-dsl-shape.md

Write the seven open questions and their resolutions. The note's
"Worked example" section reproduces EmailDelivery in the chosen
surface. Append the cross-link to the parent design note:

Edit `docs/research/dsl-shape-for-symbolic-register.md`, adding a new
section near the bottom:

    ## Authoring DSL on top of the AST

    The shapes settled in this note describe the *AST* of a
    `SymTransducer`. A separate authoring DSL — `Keiki.Builder`,
    designed in
    `docs/research/edge-builder-dsl-shape.md` — sits on top of that
    AST and is the recommended way for users to write transducers.
    See that note for the operator surface; this note remains the
    contract for the underlying AST.

Commit:

    git add docs/research/edge-builder-dsl-shape.md docs/research/dsl-shape-for-symbolic-register.md
    git commit -m "docs(builder): EP-15 M1 — design note for edge-builder DSL

    Resolves seven open questions (carrier monad, .= shape, emit shape,
    from grouping, distinct-target enforcement, goto/termination,
    module placement). Worked EmailDelivery example in the chosen
    surface.

    ExecPlan: docs/plans/15-edge-builder-monadic-dsl-for-authoring-symtransducer-edges.md
    Intention: intention_01knjzws4qezz9w8b0743zfqv8"

### M2 — spike

Create the spike module:

    mkdir -p test/Keiki
    touch test/Keiki/BuilderSpike.hs

Implement the toy coffee-dispenser transducer twice — once in the
existing AST, once in the M1 surface — and assert agreement. Run:

    nix-shell -p z3 --run "cabal test --test-options='--match \"Keiki.BuilderSpike\"'"

Expected: 4–6 examples pass.

If the spike forces a redesign, amend `docs/research/edge-builder-dsl-shape.md`
and the Surprises & Discoveries section before committing. Commit
either at green spike (preferred) or with a `wip:` prefix and a
follow-up commit at green.

### M3 — implementation

    touch src/Keiki/Builder.hs

Implement the surface listed in the M3 milestone. Edit `keiki.cabal`
to add `Keiki.Builder` to `exposed-modules` (line 37 onwards). Run:

    nix-shell -p z3 --run "cabal build"

Expected: clean build with no new warnings.

Rewrite the spike on top of `Keiki.Builder` (or delete it), then:

    nix-shell -p z3 --run "cabal test"

Commit at green.

### M4 — EmailDelivery migration

Edit `src/Keiki/Examples/EmailDelivery.hs` per the M4 milestone.
Edit `keiki.cabal` to add the new test module. Create
`test/Keiki/Examples/EmailDeliveryBuilderSpec.hs`. Edit `test/Spec.hs`
to register it. Run:

    nix-shell -p z3 --run "cabal test"
    wc -l src/Keiki/Examples/EmailDelivery.hs

Expected: all tests green; the LOC count is below 130. Commit at green.

### M5 — UserRegistration migration

Same shape as M4 but for the larger aggregate. Run the same commands
plus:

    wc -l src/Keiki/Examples/UserRegistration.hs

Expected: LOC count is below 280; `Keiki.Examples.UserRegistrationSpec`
is still green (it still imports `userReg` by name). Commit at green.

### M6 — builder unit tests

    touch test/Keiki/BuilderSpec.hs

Implement the 10 cases listed in the M6 milestone. Edit `keiki.cabal`
and `test/Spec.hs`. Run:

    nix-shell -p z3 --run "cabal test"

Expected: ≥117 examples pass (107 baseline + 10 new + 1–2 from M4 +
1–2 from M5; baseline shifts upward if EP-16/17/18 land first and
add their own tests).

### M7 — docs

Edit `docs/research/dsl-shape-for-symbolic-register.md` and (if needed)
`docs/foundations/06-where-to-go-next.md`. Run:

    nix-shell -p z3 --run "cabal haddock --haddock-internal"

Expected: clean haddock with no missing-doc warnings on `Keiki.Builder`'s
exported names. Commit at green.


## Validation and Acceptance

The plan is complete when:

1. `nix-shell -p z3 --run "cabal build"` is clean under GHC 9.12.x.
2. `nix-shell -p z3 --run "cabal test"` is green with ≥117 test
   examples (107 baseline + ≥10 new).
3. `wc -l src/Keiki/Examples/EmailDelivery.hs` reports < 130.
4. `wc -l src/Keiki/Examples/UserRegistration.hs` reports < 280.
5. The two equivalence specs (`EmailDeliveryBuilderSpec`,
   `UserRegistrationBuilderSpec`) pass: for every step of the
   canonical event log, `delta` and `omega` agree between the
   builder-form and AST-form transducer.
6. `Keiki.BuilderSpec` covers the ten cases listed at M6.
7. `Keiki.Builder`'s haddock is a self-contained tutorial; a
   contributor reading only that haddock can author a new toy
   aggregate.
8. `docs/research/edge-builder-dsl-shape.md` exists and answers
   the seven open questions; `docs/research/dsl-shape-for-symbolic-register.md`
   has the §"Authoring DSL on top of the AST" pointer.

A skeptical reviewer can verify the user-visible improvement by
diffing pre- and post-migration `userRegEdges` (now `userRegASTEdges`)
against the new builder form on disk and confirming the latter is
shorter, contains no infix `combine`, no `OFCons`/`OFNil`, no `USet
(#x :: IndexN "x" … …)` annotations, and reads like sequential
commands.


## Idempotence and Recovery

Every milestone is additive until M4–M5. M0 reads only; M1 writes new
docs; M2 writes a test-only spike; M3 adds a new library module. None
of those steps modifies an existing source file beyond cabal-level
additions, so re-running them is safe.

M4 and M5 modify the example files. The strategy preserves the
original AST form under a renamed binding (`emailDeliveryAST`,
`userRegAST`) so the migrations are reversible at any time:

- If M4's equivalence test fails, revert the builder-form
  `emailDelivery` to import `emailDeliveryAST` directly until the
  bug is found, with a one-line shim.
- If M5's equivalence test fails on a specific edge, the test names
  the offending edge index and source vertex, and the AST form is
  available on disk to compare against.
- If the builder design itself proves wrong at M4/M5 (the surface
  cannot express something the AST can), pause migration and
  amend M1's design note + the implementation in M3 before
  resuming. Do not start M5 if M4's migration revealed any
  workaround the builder forced.

Re-running steps after a failed cabal test:

- `cabal build` and `cabal test` are deterministic and idempotent.
- `cabal clean` is safe at any point if the build cache becomes
  inconsistent.
- The plan introduces no migrations of on-disk state, no destructive
  database changes, no shared-resource modifications.

Recovery from an unintended commit: the plan is implemented on the
current branch (`master`), one commit per milestone (M1, M2, M3,
M4, M5, M6, M7). A failed milestone is rolled back with `git revert
<sha>`; a stuck milestone is amended with a new commit.


## Interfaces and Dependencies

### Modules consumed (no new code)

- `Keiki.Core` (`src/Keiki/Core.hs`): the AST. Post-MP-6 surface;
  the builder consumes every constructor it produces:
  - `RegFile rs`, `IndexN s rs r`, `(!)`. (`IndexN` is the slot-
    name-tagged label-resolution shape; the legacy unindexed `Index`
    is removed.)
  - `Term rs ci r` (constructors `TLit`, `TReg`, `TInpCtorField`,
    `TApp1`, `TApp2`).
  - `InCtor ci ifs` (the per-input-constructor projection record;
    fields `icName`, `icMatch`, `icBuild`).
  - `Update rs w ci` (`UKeep :: Update rs '[] ci`, `USet :: …`,
    `UCombine :: …`) and the smart constructor
    `combine :: Disjoint w1 w2 => Update rs w1 ci -> Update rs w2 ci
    -> Update rs (Concat w1 w2) ci`. The builder emits `combine`,
    inheriting the static `Disjoint` check; the raw `UCombine` is
    used only by internal `Keiki.Composition` walks and is not
    consumed by the builder.
  - `WireCtor co fields`, `OutFields rs ci fs` (`OFNil`, `OFCons`),
    `OutTerm rs ci co` (`OPack` only). `OFn` and `mkOut` were
    removed by MP-6 EP-16.
  - `HsPred rs ci` (`PTop`, `PAnd`, `PEq`, `PInCtor`); the builder
    composes guards from `PInCtor` (via `matchInCtor`) and `PEq`
    (via `requireEq`). `PMatchC` and `matchCmd` were removed by
    MP-6 EP-17.
  - `Edge phi rs ci co s` (with the existential `w` on the `update`
    field) and `SymTransducer phi rs s ci co`. The builder emits
    `Edge { … }` literals; the existential closes over the indexed-
    monad's final `w`.
  - Type-level machinery: `Disjoint :: [Symbol] -> [Symbol] ->
    Constraint`, `Concat :: [Symbol] -> [Symbol] -> [Symbol]`. The
    builder's `(.=)` signature uses both.
  - Helpers: `proj`, `inpCtor`, `lit`, `(.==)`, `pack`, `matchInCtor`.

- `Keiki.Generics` (`src/Keiki/Generics.hs`): consumed by the existing
  TH splices in the example modules. The builder does not directly
  use `Keiki.Generics`, but the `InCtor`/`WireCtor` values it
  consumes are produced by `mkInCtorVia` / `mkWireCtorVia`.

- `Keiki.Generics.TH` (`src/Keiki/Generics/TH.hs`): `deriveAggregateCtors`
  and `deriveWireCtors` — used at the example layer, not at the
  builder layer.

### Modules produced

- **New** `Keiki.Builder` (`src/Keiki/Builder.hs`). Surface listed
  under M3 above. The exact carrier-monad representation, the exact
  signature of `emit`, and the exact `ToTerm` overload are M1
  decisions, recorded in `docs/research/edge-builder-dsl-shape.md`
  and reflected back into the M3 surface.

### No new build-time dependencies

This plan adds no packages to `keiki.cabal`'s `build-depends`. The
indexed-monad mechanism is hand-rolled inside `Keiki.Builder` (a
small `IxFunctor`/`IxApplicative`/`IxMonad` newtype trio plus
`(>>=)`/`(>>)`/`pure`/`return` re-exports for `QualifiedDo`'s
elaboration). If M1 finds a strong reason to add a tiny helper
package (`indexed`, `indexed-extras`, `do-notation`), it must
record the rationale in the Decision Log and amend this section.
The default position is to hand-roll, both to keep the dep
footprint zero and to keep the error-message shape under our
control.

### Test suite

- **New** `test/Keiki/BuilderSpec.hs` — unit tests for
  `Keiki.Builder`.
- **New** `test/Keiki/Examples/EmailDeliveryBuilderSpec.hs` —
  cross-form equivalence test for EmailDelivery.
- **New** `test/Keiki/Examples/UserRegistrationBuilderSpec.hs` —
  cross-form equivalence test for UserRegistration.

All three new modules are added to `keiki.cabal:59`'s
`other-modules` list and registered in `test/Spec.hs` following the
existing pattern there.

### Out of scope

- **Quasi-quoter or external DSL.** The builder is a plain Haskell
  monadic surface. A `[edges| … |]` quasi-quoter is a possible
  future direction; this plan rejects it because (a) the monadic
  surface composes naturally with regular Haskell control flow
  (`when`, `forM_`), and (b) a quasi-quoter creates a second source
  of truth that the haddock cannot easily document.
- **Per-vertex GADT view (B-presentation).** EP-13 owns that
  (`docs/plans/13-genview-th-splice-and-b-presentation-view-v-gadt.md`,
  Complete). The edge-builder operates on the same flat register
  file the AST does; it does not interact with the per-vertex
  `View v` GADT.
- **MP-6 escape-hatch retirements.** EP-16 / EP-17 / EP-18 are
  Complete. The builder consumes the post-MP-6 `Keiki.Core` surface
  (no `OFn`, no `PMatchC`, no `unsafeCombine`; `Update rs w ci`
  with `Disjoint` on `combine`). No ongoing coordination cost.
- **Compile-time topology safety.** Item G in MP-3's design note
  ("compile-time topology safety via a `SymTransducerStrict`
  parameterized over a type-level topology") is a future-MasterPlan
  v3 direction. The builder does not block it; if a future plan
  delivers G, the builder can be re-typed over `SymTransducerStrict`
  with no changes to the user surface, only to the implementation.
- **Replacing the AST surface entirely.** The AST is the load-bearing
  source of truth and stays. Users who prefer the AST keep writing
  it; the builder is recommended but not mandatory. `Keiki.Builder`'s
  haddock includes a "when to drop down to the AST" paragraph.
- **Composition combinators in the builder.** EP-11 (Complete) and
  the `Keiki.Composition` module own composition. The builder
  produces values of the same `SymTransducer` type, so they compose
  with no special handling.

### Soft external dependencies (all Complete)

- *MP-6 (escape-hatch retirements).* Complete. Defines the
  post-MP-6 `Keiki.Core` surface this plan consumes (`Update rs w
  ci`, `IndexN s rs r`, `combine`'s `Disjoint` constraint). No
  coordination required.
- *EP-7 (GHC 9.12 upgrade).* Complete. Cited because the builder's
  indexed-monad type-class resolution and the type-level set
  machinery (`Disjoint`, `Concat`) benefit from 9.12's improved
  error messages and `QualifiedDo` support.
- *MP-4 children.* EP-11 (`Keiki.Composition`'s `compose`, Complete)
  consumes the `SymTransducer` values the builder produces. No
  coordination required because the builder's output type matches
  the AST's exactly.
- *MP-5 children.* EP-12 (`Keiki.Acceptor`, Complete) and EP-13
  (`deriveView` TH splice, Complete) similarly consume
  `SymTransducer` values. No coordination required.


---

## Revisions

### 2026-05-02 — Reconcile with MP-6 escape-hatch retirements

After this plan was drafted, a survey of recent commits surfaced
MasterPlan 6 (`docs/masterplans/6-...md`, retire `OFn` / `PMatchC` /
`unsafeCombine`) and its four child plans (file numbers 14, 16, 17,
18). MP-6's design milestone (file 14) had already landed Complete;
the three implementation children (EP-16 `OFn`, EP-17 `PMatchC`,
EP-18 `unsafeCombine` static check) were Not Started.

Two of MP-6's retirements (`OFn`/`mkOut` via EP-16, `PMatchC`/
`matchCmd` via EP-17) are no-op interactions for this plan: the
builder neither produces nor consumes the deleted constructors. The
third (`unsafeCombine` via EP-18) is a real interaction: EP-18
refactors `Update rs ci` to `Update rs w ci` and replaces the
runtime distinct-targets check with a type-level `Disjoint w1 w2`
constraint on `combine`. The builder's distinct-targets enforcement
is exactly the obligation EP-18 lifts to the type level.

Changes applied to this plan to reflect the new context:

- **Purpose / Big Picture.** Updated baseline test count from "89"
  to "107" (the count cited by MP-6 EP-15 M0); final acceptance test
  count from "≥99" to "≥117".
- **Progress / M0.** Recording MP-6 child status (EP-16 / EP-17 /
  EP-18 Not Started vs. Complete vs. In Progress) is now part of
  M0's required record.
- **Progress / M1.** Added Q8 ("MP-6 / EP-18 sequencing") to the
  set of questions M1 settles.
- **Decision Log.** Updated the "no `Keiki.Core` modification"
  entry with a caveat acknowledging MP-6's concurrent
  modification, and the precise interaction with each of EP-16,
  EP-17, EP-18. Added a new Decision Log entry capturing the soft
  dependency on EP-18 and deferring final sequencing to M1 Q8.
  Updated the AST-preservation entry to reflect that the AST is
  intentionally *less* of an escape hatch after MP-6.
- **Context and Orientation.** Added a "Recent context: MP-6
  escape-hatch retirements" subsection naming each child plan,
  describing the post-EP-18 `Update rs w ci` shape, and
  enumerating the two paths (pre-EP-18 and post-EP-18) the M1
  design milestone may take. Added a "Numbering namespace note"
  flagging that MP-6's narrative refers to the design milestone as
  "EP-15" while file 15 is this plan; readers should prefer file
  paths over the short label. Edited the `unsafeCombine` paragraph
  in "What an Edge looks like today" to point at the new
  subsection.
- **Plan of Work / M1.** Reworded Q5 (Distinct-targets enforcement)
  to lay out two paths (pre-EP-18 value-level / post-EP-18
  type-level) keyed off Q8. Added Q8 itself, listing three sub-
  cases (EP-18 Complete / In Progress / Not Started) and naming the
  default recommendation (pre-EP-18 path unless EP-18 is already
  Complete at M1 time). Updated the M1 end-state paragraph from
  "seven questions" to "eight questions".
- **Plan of Work / M3.** Marked the surface-signature sketch of
  `EdgeBuilder` as "kind depends on Q8's resolution" and added a
  post-EP-18 indexed-monad alternative shape.
- **Concrete Steps / M0.** Added a `grep` step to record the MP-6
  child statuses. Updated the expected baseline transcript from
  "89" to "107". Updated the M6 expected transcript from "≥99" to
  "≥117".
- **Validation and Acceptance.** Updated the test-count gate from
  "≥99" to "≥117". Updated the open-questions-answered gate from
  "seven" to "eight".
- **Interfaces and Dependencies.** Removed `OFn`, `OFn`-related
  helpers (`mkOut`), `PMatchC`, and `matchCmd` from the consumed-
  module list with a note that EP-16 / EP-17 are deleting them.
  Updated the `Update` entry to acknowledge the pre-EP-18 vs.
  post-EP-18 shape split. Added a new "Soft external dependencies"
  subsection naming MP-6 / EP-18, EP-7, MP-4 children, MP-5
  children. Updated the "No new build-time dependencies" entry
  with a note about possible indexed-monad helpers for the
  post-EP-18 path. Reframed the "Out of scope" entry that
  previously called the AST a "documented escape hatch" to call it
  the "load-bearing source of truth" — the AST is staying, but it
  is no longer the recommended authoring path.

The plan's overall scope, milestone count, and acceptance shape are
unchanged. The revision sharpens the boundary against MP-6 and
forces the M1 design milestone to commit to a sequencing path
explicitly rather than punting on it.

### 2026-05-02 (later that day) — MP-6 closed Complete; collapse pre-/post-EP-18 split

MP-6 closed Complete the same day. All four child plans (EP-15
design milestone, EP-16 `OFn`, EP-17 `PMatchC`, EP-18
`unsafeCombine`) shipped to master. Verified via direct read of
`Keiki.Core.hs`: `Update rs w ci` is current; `combine` carries the
`Disjoint w1 w2` constraint; `IndexN s rs r` is the user-facing
slot-name-tagged index; `OFn`, `mkOut`, `PMatchC`, `matchCmd`,
`unsafeCombine` are all gone; `Edge`'s `update` field is
existentially quantified over `w`. EmailDelivery's edge already
uses `combine` and `IndexN "name" Regs T`. The earlier
revision's "two paths" framing (pre-EP-18 vs. post-EP-18) is
obsolete: only the post-EP-18 path applies.

Changes applied:

- **Purpose / Big Picture.** Updated the prose snippet to mention
  MP-6 explicitly, reference `IndexN "slot" Regs T` and the
  `(w :: [Symbol])` index, and frame `combine` as "type-level
  checked but still infix-by-hand." Updated the post-state code
  example to use `QualifiedDo` (`B.do`) and `IndexN`-resolving
  `#labels`, with an explicit paragraph explaining the indexed-
  monad-driven static `Disjoint` check. Updated the LOC targets
  from "165→<130" / "355→<280" to "185→<150" /
  "385→<310" — the post-MP-6 baselines are higher because EP-18's
  `IndexN`-style slot annotations doubled the slot-name token
  count per `USet` line. Added a paragraph explaining why the
  builder removes that duplication entirely.
- **Decision Log.** Updated the "no `Keiki.Core` modification"
  entry: the MP-6-caveat paragraph shifted from "is concurrently
  modifying" to past-tense "modified" with the precise list of
  changes shipped. Replaced the "soft-dep on EP-18 / M1 Q8"
  decision with a definitive "indexed-monad carrier" decision
  citing MP-6's smart-vs-raw-constructor lesson.
- **Context and Orientation.** Replaced the verbatim
  EmailDelivery `unsafeCombine`-form snippet with the actual
  current `combine`-form snippet (re-read from
  `src/Keiki/Examples/EmailDelivery.hs:163`). Updated the
  surrounding bullet list: "Index Regs T" → "IndexN \"x\" Regs T"
  with a note about the duplicated slot name; "unsafeCombine
  chains" → "combine chains" with a note that the static check is
  there but the syntax is still verbose.
- **Recent context: MP-6 escape-hatch retirements.** Rewrote
  end-to-end to past tense ("Complete on 2026-05-02"). Listed each
  retirement's effect on the current `Keiki.Core` surface. Added a
  new "Implications for the builder" subsection covering: the
  builder is a public introduction point (per MP-6's lesson), the
  carrier is indexed, the user-facing surface is unchanged
  (`#labels` resolve), `-Wno-redundant-constraints` is enabled at
  the module level, and the existential `w` on `Edge`'s `update`
  field is closed over by the builder. Updated the "Numbering
  namespace note" to reflect that MP-6 is closed and the EP-15
  label conflict will not be resolved by a future MP-6 revision.
- **Plan of Work / M1.** Removed Q8 (sequencing) entirely. Q5
  (distinct-targets) collapsed to one path — type-level
  `Disjoint`-driven via the indexed-monad carrier — with a
  `-Wredundant-constraints` note. Q1 (carrier monad) collapsed
  from "three candidates" to "the indexed-monad shape is settled;
  the open question is `QualifiedDo` vs `RebindableSyntax`," with
  `QualifiedDo` as default. M1 end-state goes from "eight
  questions" back to "seven." Updated the M1 Progress entry text
  to drop the Q8 reference.
- **Plan of Work / M3.** Replaced the dual-shape `EdgeBuilder`
  type with the single indexed-monad shape `EdgeBuilder rs ci co
  s w w' a`. Updated `(.=)`'s signature to add the `Disjoint '[s]
  w` constraint and the `IndexN s rs r` argument. Updated `from`,
  `onCmd`, `onEpsilon`, `goto`, `requireEq`, `requireGuard`,
  `emit`, `noEmit` signatures to thread the indexed-monad indices.
- **Concrete Steps / M0.** Removed the MP-6 child-status grep
  (no longer needed). Updated the expected baseline transcript
  from "165 / 355" to "185 / 385" lines.
- **Validation and Acceptance.** Updated point 3 (LOC targets) to
  the post-MP-6 numbers. Updated the post-migration verification
  paragraph to drop "no `unsafeCombine`" and add "no infix
  `combine`" / "no `IndexN \"x\" … …` annotations." Updated the
  open-questions count from "eight" back to "seven."
- **Interfaces and Dependencies.** Replaced the dual-shape
  `Update` consumed-list entry with the single post-MP-6 shape.
  Added an explicit `IndexN`/`Disjoint`/`Concat` consumed-list
  entry. Removed the comment about "may benefit from indexed-
  monad helpers post-EP-18" from "No new build-time
  dependencies"; replaced with a paragraph confirming the
  indexed-monad mechanism is hand-rolled inside `Keiki.Builder`.
  Replaced the MP-6 / EP-7 / MP-4 / MP-5 "Soft external
  dependencies" subsection with one that marks them all Complete.

The plan's overall scope, milestone count, and acceptance shape
remain unchanged from the previous revision. The change is purely a
simplification: the dual-path framing was a hedge against MP-6's
landing time, and that hedge is no longer needed. M1's design note
is now clearer (one path, seven questions, the duplicate-slot
diagnostic is the only design freedom in Q5).
