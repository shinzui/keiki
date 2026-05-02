---
id: 21
slug: ergonomic-emit-for-keiki-builder-drop-redundant-inctor-and-add-field-keyed-record-sugar
title: "Ergonomic emit for Keiki.Builder: drop redundant InCtor, eliminate residual Index annotations, and add field-keyed record sugar"
kind: exec-plan
created_at: 2026-05-02T17:21:52Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
---

# Ergonomic emit for Keiki.Builder: drop redundant InCtor, eliminate residual Index annotations, and add field-keyed record sugar

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

EP-15 shipped `Keiki.Builder` (`src/Keiki/Builder.hs`) with a working
edge-authoring DSL. The slot-write side (`B.slot @"name" .= …`) and
the control side (`B.from`/`B.onCmd`/`B.goto`) read like a clean
imperative state-machine description, but the **output side**
(`B.emit`) and **register-read side** (`proj` in `requireEq` /
`OFCons`) are still awkward.

Current shape (post-EP-15) — the User-Registration `Confirm` edge:

    B.from RequiresConfirmation do
      B.onCmd inCtorConfirm $ \d -> B.do
        B.requireEq d.confirmCode
                    (proj (#confirmCode :: Index UserRegRegs ConfirmationCode))
        B.slot @"confirmedAt" .= d.at
        B.emit inCtorConfirm wireAccountConfirmed
          (OFCons (proj (#email :: Index UserRegRegs Email))
            (OFCons d.confirmCode (OFCons d.at OFNil)))
        B.goto Confirmed

Four sources of friction:

1. **Redundant `InCtor` argument on `emit`.** The enclosing
   `onCmd ic …` already supplied an `InCtor`; `emit` repeats it.
2. **`OFCons … OFNil` HList nesting.** The user has to write a
   nested-pair HList, which has nothing to do with the wire-side
   record's surface.
3. **Positional rather than field-named outputs.** The user must
   remember the wire ctor's field order (matched by `Generic`'s
   `RegFieldsOf` walk on the payload type). A wrong order compiles
   fine and produces wrong output.
4. **`proj (#name :: Index Regs T)` annotations.** Every register
   read in `requireEq` and `emit`-`OFCons` arguments is wrapped in
   `proj` and pinned with a full `:: Index Regs T` annotation
   because GHC's `IsLabel` resolution does not currently produce a
   `Term`-typed result directly. There are five such sites in
   `Keiki.Examples.UserRegistration`'s builder form.

After this plan, a contributor authors the same edge as:

    -- M1: drop the redundant InCtor; eliminate Index annotations.
    --     `#name` resolves directly to a `Term`-typed register read.
    B.from RequiresConfirmation do
      B.onCmd inCtorConfirm $ \d -> B.do
        B.requireEq d.confirmCode #confirmCode
        B.slot @"confirmedAt" .= d.at
        B.emit wireAccountConfirmed
          (OFCons #email (OFCons d.confirmCode (OFCons d.at OFNil)))
        B.goto Confirmed

    -- M2: HList operator sugar.
    B.emit wireAccountConfirmed (#email *: d.confirmCode *: d.at *: oNil)

    -- M3+: field-keyed record-syntax form.
    B.emit wireAccountConfirmed AccountConfirmedTermFields
      { email       = #email
      , confirmCode = d.confirmCode
      , at          = d.at
      }

…with both forms compiling to the same `OPack` AST node consumed
unchanged by `Keiki.Acceptor`, `Keiki.Composition`,
`Keiki.Decider`, and `Keiki.Symbolic`. Behaviour is byte-identical
to the post-EP-15 baseline, asserted by the existing equivalence
specs (`EmailDeliveryBuilderSpec`, `UserRegistrationBuilderSpec`).

The user-visible improvement is verified by:

1. `cabal build` is clean under GHC 9.12.x.
2. `cabal test` is green at ≥138 examples (post-EP-15 M7
   baseline). New cases added by this plan add ≥5 examples.
3. Both example aggregates' `emit` call sites no longer mention
   any `InCtor`-typed argument, no `proj (#name :: Index Regs T)`
   annotations, and no raw `OFCons`/`OFNil`. After M5 they use the
   field-keyed form exclusively.
4. `wc -l` on `src/Keiki/Examples/UserRegistration.hs` drops
   from 464 (post-EP-15) to under 440 (M1 alone — InCtor + Index-
   annotation removal), and to under 420 once the field-keyed
   form lands (M5). EmailDelivery shrinks from 220 to under 215
   (M1) / under 210 (M5).
5. `grep -c ":: Index " src/Keiki/Examples/UserRegistration.hs`
   drops from 10 (5 builder-form + 5 AST-form) to 5 (AST-form
   only) after M1. The AST-form annotations are deliberately not
   touched — the AST form is the lower-level escape hatch and
   keeps the explicit annotations as documentation.

The plan is purely additive on top of the EP-15 surface: the
existing `B.emit ic wc fs` shape becomes deprecated (still works
during the migration) and is removed at M6. Users who prefer the
explicit-InCtor variant can keep using `B.emitWith` (the new name
for the explicit form, retained for `onEpsilon` where there is no
enclosing `onCmd`).


## Progress

This section tracks granular progress. Update at every stopping point: tick
completed items with a date, split partial items into "done" and "remaining"
entries, add new items as discovered.

- [x] M0 (2026-05-02): Verify prerequisites — record baseline test count, build state, current `emit` LOC totals across the two examples. Baseline recorded in Decision Log: 138 tests pass; EmailDelivery 220 LOC, UserRegistration 464 LOC; emit sites 1/5; `:: Index ` annotations 0/10.
- [x] M1 (2026-05-02): Two related ergonomic fixes shipped together:
  1. **Drop the redundant `InCtor` argument from `B.emit`.** Added `peInCtor :: Maybe (PeInCtor ci)` to `PartialEdge` (a builder-local existential, not `Symbolic.SomeInCtor` — see Surprises). `onCmd` sets it; `onEpsilon` leaves it `Nothing`. The new 2-arg `B.emit wc fs` recovers the InCtor from the field; the explicit-InCtor form is renamed `B.emitWith ic wc fs` and exported as the documented escape hatch.
  2. **Eliminated `proj (#name :: Index Regs T)` boilerplate at call sites.** Added `instance HasIndex s rs r => IsLabel s (Term rs ci r)` to `src/Keiki/Core.hs` next to the existing `IsLabel s (Index rs r)` instance. Migrated 5 builder-form sites in `src/Keiki/Examples/UserRegistration.hs` (and the analogous emit site in `EmailDelivery`) to drop both the InCtor and the Index annotations. AST-form sites untouched.

  Acceptance: `cabal test` green at 138 examples; `grep -c ":: Index " src/Keiki/Examples/UserRegistration.hs` reports 5 (AST-only); EmailDelivery 0. LOC: 220 / 458 (M1 acceptance targets of <215/<440 not met — see Surprises; user-visible boilerplate removal is fully delivered).
- [x] M2 (2026-05-02): Added `(*:)` (right-assoc fixity 5) and `oNil` to `Keiki.Builder`, exported alongside `(.=)`. Imported unqualified at example sites for readability (matching the existing `(.=)` convention). Migrated both example aggregates and `BuilderSpike`; left `BuilderSpec` on bare `OFCons`/`OFNil` per the plan (its call sites are not user-facing tutorials). Module-level haddock example updated to show the operator form. 138 tests still pass.
- [ ] M3: Settle field-keyed record sugar shape — write the design note `docs/research/emit-field-keyed-record-sugar.md` resolving the open questions (per-event vs class-driven generation, field-name disambiguation strategy, interaction with DuplicateRecordFields, error-message shape).
- [ ] M4: Implement field-keyed sugar. Extend `Keiki.Generics.TH.deriveWireCtors` (or add a new splice `deriveWireCtorsAndTermRecords`) to emit a per-event `<EventName>TermFields rs ci` record type whose fields are `Term rs ci T` for each wire-side field, plus a typeclass instance `ToOutFields` (or similar) connecting it to the existing `OutFields rs ci fs`. `B.emit wc rec` becomes overloaded over the typeclass.
- [ ] M5: Migrate the two example aggregates to the field-keyed form. Confirm equivalence specs (`EmailDeliveryBuilderSpec`, `UserRegistrationBuilderSpec`) still pass byte-identically.
- [ ] M6: Remove the deprecated InCtor-explicit `emit` form (renamed to `emitWith` at M1) if no remaining call site uses it; otherwise keep as the documented escape hatch. Update `Keiki.Builder` haddock and `docs/research/edge-builder-dsl-shape.md`'s Q3 section to the final shape.


## Surprises & Discoveries

- 2026-05-02 — *M1 LOC targets (< 440 / < 215) are not reachable from
  M1's surface change alone.* The boilerplate removed is per-token,
  not per-line: each dropped `InCtor` word leaves the line count
  unchanged, and each removed `proj (#name :: Index UserRegRegs T)`
  collapses to a shorter same-line form except in the one
  `requireEq` site whose annotation occupied a continuation line.
  After natural single-line-fit compression, UserRegistration sits at
  458 LOC (target < 440) and EmailDelivery at 220 LOC (target <
  215). Remaining LOC savings will come from M2's operator sugar
  (modest, per-line) and M5's field-keyed form (substantial,
  per-emit restructuring). Continuing without gold-plating
  formatting; the *user-visible* improvement (no `InCtor`-typed
  argument on `B.emit`, no `proj (#name :: Index Regs T)`
  annotation in builder forms) is fully delivered.

- 2026-05-02 — *`Keiki.Builder` did not previously depend on
  `Keiki.Symbolic`.* The plan suggested reusing
  `Symbolic.SomeInCtor` for `peInCtor` to "keep the dep graph
  unchanged"; in fact reusing it would add a new edge and pull SBV
  transitively into every consumer of `Keiki.Builder`. Resolved
  with a local `data PeInCtor ci where PeInCtor :: InCtor ci ifs ->
  PeInCtor ci` (no `ExtractRegFile` constraint, no SBV pull).


## Decision Log

The seed entries below capture decisions reached while drafting this plan.
Subsequent decisions made during implementation append below them with a date.

- Decision: This is a follow-up ExecPlan, not a child of a master
  plan. EP-15 closed Complete on 2026-05-02 with all eight milestones
  shipped. The field-keyed sugar was explicitly listed in EP-15's
  Outcomes & Retrospective deferrals as a follow-up and in its
  M1 design note (Q3) as the second of two follow-up paths. This
  plan picks up that thread.
  Date: 2026-05-02

- Decision: Drop the `InCtor` from `emit` by storing it in
  `PartialEdge`, not by walking `peGuard`.
  Rationale: `peGuard` may have additional conjuncts (from
  `requireEq` / `requireGuard`) wrapped around the original
  `PInCtor` atom, so recovery via pattern-match would require a
  walk. Simpler to store the `SomeInCtor ci` directly when `onCmd`
  fires, and read it back when `emit` runs. The cost is one extra
  field on `PartialEdge`; the existential is hidden via
  `SomeInCtor` (already defined in `Keiki.Symbolic`).
  Date: 2026-05-02

- Decision: Eliminate the `proj (#name :: Index Regs T)`
  boilerplate by adding an `IsLabel s (Term rs ci r)` instance to
  `Keiki.Core`, alongside the existing `IsLabel s (Index rs r)`.
  Rationale: The existing pattern `proj (#name :: Index Regs T)`
  is forced by GHC's inability to determine `rs` and `r` for a
  bare `#name` in `Term`-typed contexts without explicit
  annotation. EP-15's M2 spike showed that `#name` cannot resolve
  cleanly to `IndexN` because the `IsLabel s (IndexN s rs r)`
  instance has the symbol at two pattern positions (the
  two-positions-share-`s` issue). The same is *not* true for
  `IsLabel s (Term rs ci r)`: the symbol appears once, and
  GHC's resolution can determine `rs` and `r` from the
  surrounding context (the `Term`-typed slot). Adding the
  instance is a one-liner in `Keiki.Core`; the resulting `#name`
  resolves to `TReg (indexOf @s @rs @r)` whenever the context
  demands a `Term`. The existing `IsLabel s (Index rs r)`
  instance is preserved (so `inpFoo #name` keeps working).
  GHC's instance dispatch is type-directed by the *result type*,
  so the two instances coexist without overlap.
  Date: 2026-05-02

- Decision: The new `IsLabel s (Term rs ci r)` instance is added
  to `Keiki.Core`, not to `Keiki.Builder`.
  Rationale: The instance is useful anywhere a `Term` is
  expected — including the AST form of a transducer, not just
  the builder form. Placing it in `Keiki.Core` makes it part of
  the AST surface; users who choose the AST escape hatch also
  benefit. It preserves the rule that "the AST is the source of
  truth, and the builder is a layer on top": an instance for
  `Term` belongs at the AST layer.
  Date: 2026-05-02

- Decision: AST-form `proj (#name :: Index Regs T)` annotations
  in `userRegASTEdges` and `emailDeliveryASTEdges` are *not*
  migrated by this plan.
  Rationale: The AST form is preserved as the documented escape
  hatch and as the equivalence-test reference. Touching it would
  invalidate the side-by-side comparison that
  `EmailDeliveryBuilderSpec` and `UserRegistrationBuilderSpec`
  depend on (they cite the AST-form's exact shape as the
  contract). A future plan that retires the AST forms entirely
  can also drop their annotations; this plan keeps them as
  documentation of the unmigrated shape.
  Date: 2026-05-02

- Decision: Rename the explicit-InCtor form to `emitWith` rather
  than keep it as `emit` and introduce a new name like `emit'` for
  the implicit form.
  Rationale: the implicit form is the common case (every call
  site inside `onCmd`). It deserves the shorter name. The explicit
  form is only needed inside `onEpsilon` (which doesn't bind an
  InCtor) and as a fallback for users constructing edges outside
  the `onCmd` lexical scope. `emitWith` reads as "emit with this
  InCtor", matching the convention in `mtl`/`base` of `…With` for
  the explicitly-parameterised variant.
  Date: 2026-05-02

- Decision: Defer the field-keyed shape decision to M3 rather than
  baking it into this plan up front.
  Rationale: at draft time the shape has at least three viable
  variants: (a) per-event TH-generated `<EventName>TermFields`
  record + a typeclass instance, (b) one generic
  record-of-Terms type parameterised by an event ctor proxy and a
  type-level field schema, (c) per-event TH-generated `emitFoo`
  helper that takes a record value of the event's payload (with
  fields widened to `Term`s). Each has different
  field-disambiguation tradeoffs (DuplicateRecordFields is on, so
  `email :: Term rs ci Email` clashes across events unless
  scoped by the per-event record type). M3's design note picks
  one with a worked example and an error-message catalog before
  M4 ships code.
  Date: 2026-05-02

- Decision: The plan does not modify `Keiki.Core`, `Keiki.Acceptor`,
  `Keiki.Composition`, `Keiki.Decider`, `Keiki.Symbolic`, or any
  other module the AST depends on.
  Rationale: same reason EP-15 was additive. The AST stays as the
  source of truth. The new emit shape produces the same `OPack`
  AST node; downstream consumers see no difference. The TH
  extension (M4) emits new top-level declarations in the user's
  example module, not new constructors in the core AST.
  Date: 2026-05-02

- Decision: Operator sugar (`(*:)`/`oNil`) is shipped at M2 even
  though M5 will replace it with the field-keyed form.
  Rationale: M2 is one commit's worth of work; it removes the
  `OFCons`/`OFNil` boilerplate at every call site and gives
  contributors something working before M3/M4 land. If M5 makes
  the operator form unused, it can be retired via a deletion-only
  follow-up. The intermediate state is not an end state but is
  a useful intermediate.
  Date: 2026-05-02

- Decision (revision): Use a *local* existential in `Keiki.Builder`
  for `peInCtor`, not `Keiki.Symbolic.SomeInCtor`.
  Rationale: the plan-level rationale assumed reuse "keeps the dep
  graph unchanged", but `Keiki.Builder` does not currently import
  `Keiki.Symbolic`. Reusing `SomeInCtor` would add a `Builder →
  Symbolic` dependency edge and pull SBV transitively into every
  consumer of `Keiki.Builder`. The `SomeInCtor` constructor also
  carries an `ExtractRegFile ifs` constraint that the symbolic
  analyses need but the builder does not — using it would force
  threading that constraint through `onCmd`'s signature, a
  breaking change to the Builder surface. A local existential
  `data PeInCtor ci where PeInCtor :: InCtor ci ifs -> PeInCtor ci`
  has neither cost.
  Date: 2026-05-02

- M0 baseline (2026-05-02):
  - `cabal build` clean under GHC 9.12.3.
  - `cabal test`: 138 examples, 0 failures.
  - `wc -l src/Keiki/Examples/EmailDelivery.hs` → 220.
  - `wc -l src/Keiki/Examples/UserRegistration.hs` → 464.
  - `grep -c "B.emit" src/Keiki/Examples/EmailDelivery.hs` → 1.
  - `grep -c "B.emit" src/Keiki/Examples/UserRegistration.hs` → 5.
  - `grep -c ":: Index " src/Keiki/Examples/EmailDelivery.hs` → 0.
  - `grep -c ":: Index " src/Keiki/Examples/UserRegistration.hs` → 10
    (5 builder + 5 AST).
  Date: 2026-05-02


## Outcomes & Retrospective

(To be filled during and after implementation. At each milestone-completion,
add a paragraph capturing what was achieved, what surprised, and what was
deferred. At plan completion, summarize against the Purpose / Big Picture
section.)


## Context and Orientation

This section gives a complete novice everything they need to follow the plan
without prior context.

### What `Keiki.Builder` is and what `emit` looks like today

`src/Keiki/Builder.hs` is a monadic DSL on top of the `Keiki.Core`
AST, shipped by EP-15
(`docs/plans/15-edge-builder-monadic-dsl-for-authoring-symtransducer-edges.md`).
Three monad layers:

- `VertexBuilder rs ci co v a` — top-level, plain `Monad`.
- `EdgeListBuilder rs ci co v a` — per-source-vertex, plain `Monad`.
- `EdgeBuilder rs ci co v w w' a` — per-edge body, **indexed**
  (carries a type-level slot-set `(w :: [Symbol])`).

`B.emit` is a per-edge primitive (`EdgeBuilder`-typed). Its current
signature in `src/Keiki/Builder.hs:391-398`:

    emit
      :: forall co fs rs ci v w ifs.
         InCtor ci ifs
      -> WireCtor co fs
      -> OutFields rs ci fs
      -> EdgeBuilder rs ci co v w w ()
    emit ic wc fs = EdgeBuilder $ \(PartialEdge g u _o tgs) ->
      ((), PartialEdge g u (Just (pack ic wc fs)) tgs)

`pack` (re-exported from `Keiki.Core`) constructs an `OPack ic wc
fs :: OutTerm rs ci co`. The `InCtor ci ifs` is what `solveOutput`
later uses to invert the OPack on replay.

### How call sites look post-EP-15

`src/Keiki/Examples/EmailDelivery.hs:166-170`:

    B.emit inCtorSendEmail wireEmailSent
      (OFCons d.recipient (OFCons d.subject (OFCons d.at OFNil)))

`src/Keiki/Examples/UserRegistration.hs:296-298`:

    B.emit inCtorStart wireRegistrationStarted
      (OFCons d.email (OFCons d.confirmCode (OFCons d.at OFNil)))

…and four more sites in UserRegistration (`Continue`, `Confirm`,
`Resend`, `GdprFromConfirmed`). Every one has the same shape:
`B.emit <inCtor>` (the same one bound by the enclosing `onCmd`)
followed by an `OFCons … OFCons … OFNil` chain.

### Why `proj (#name :: Index Regs T)` is forced today

`Keiki.Core` provides `proj :: Index rs r -> Term rs ci r` and
the `IsLabel s (Index rs r)` instance, so `proj #name` should in
principle resolve cleanly to a `Term`-typed register read once
the surrounding context pins `rs` and `r`. In practice, GHC's
inference does not commit early enough to discharge the
`HasIndex s rs r` constraint without the user spelling out
`(#name :: Index Regs T)`. The pattern appears in
`src/Keiki/Examples/UserRegistration.hs` at five builder-form
sites:

- `proj (#email :: Index UserRegRegs Email)` (4 OFCons sites in
  edges out of `Registering`, `RequiresConfirmation/Confirm`,
  `RequiresConfirmation/Resend`, and `Confirmed/Gdpr`).
- `proj (#confirmCode :: Index UserRegRegs ConfirmationCode)` (the
  `requireEq` site in `RequiresConfirmation/Confirm`).

The fix (M1 part B) is a one-instance addition to `Keiki.Core`:

    instance HasIndex s rs r => IsLabel s (Term rs ci r) where
      fromLabel = TReg (indexOf @s @rs @r)

With this instance present, `#name` resolves directly to a `Term`
in any `Term`-typed context. The two `IsLabel` instances
(`Index` and `Term`) coexist because GHC's instance dispatch is
type-directed by the result type:

- `inpFoo #name` (`inpFoo`'s arg is `Index ifs r`) → `Index`
  instance fires.
- `requireEq d.x #y` (`requireEq`'s args are `Term rs ci r`) →
  `Term` instance fires.

This is *not* the same problem EP-15 M2 hit on
`IsLabel s (IndexN s rs r)`. The `IndexN` instance has the
symbol at two pattern positions in its head (`s` in
`IsLabel s (IndexN s rs r)`), forcing GHC to commit the symbol
before instance selection. The `Term` instance has the symbol
only in the `IsLabel` head; the body of the constraint
(`HasIndex s rs r`) discharges by the standard FD-driven path
once `rs` is known from context.

### What `PartialEdge` carries (the structural target of M1)

`src/Keiki/Builder.hs:140-147`:

    data PartialEdge rs ci co v (w :: [Symbol]) = PartialEdge
      { peGuard   :: HsPred rs ci
      , peUpdate  :: Update rs w ci
      , peOutput  :: Maybe (OutTerm rs ci co)
      , peTargets :: [v]
      }

M1 adds a fifth field, `peInCtor :: Maybe (SomeInCtor ci)`, set by
`onCmd` and `Nothing` in `onEpsilon`. `SomeInCtor` is already
defined in `src/Keiki/Symbolic.hs` — used by the symbolic
analyses' witness extractor. Reusing it keeps the dep graph
unchanged.

### What `deriveWireCtors` emits today

`src/Keiki/Generics/TH.hs:356-380` (the `genWire` worker invoked by
`deriveWireCtors`). For each `(ctorName, shortName)` pair, it
emits:

    wire<Short> :: WireCtor <EventType> (FieldsOf <PayloadType>)
    wire<Short>  = mkWireCtorVia @"<ctorName>"

`FieldsOf <PayloadType>` is a type family in `Keiki.Generics`
(`src/Keiki/Generics.hs:229`) that walks the payload type's
`Generic` `Rep` and produces a nested-pair tuple type, e.g.
`(Email, (Subject, (UTCTime, ())))` for `EmailSentData`.

M4 extends `deriveWireCtors` (or adds a parallel splice) to also
emit, per event ctor:

- A record type `<CtorName>TermFields rs ci` with one field per
  wire-side field, typed `Term rs ci T` (instead of bare `T`).
- An instance of a typeclass (or a free function) that converts
  this record into the existing `OutFields rs ci fs` shape that
  `pack` consumes.

The slot-list extraction logic is already present in
`reifySlotList` at `src/Keiki/Generics/TH.hs:391-417` (used by
`deriveView`); the wire-side mirror walks the payload type's
fields and emits one record selector per field.

### What `OutFields` looks like and how `pack` works

`src/Keiki/Core.hs:326-330`:

    data OutFields rs ci fs where
      OFNil  :: OutFields rs ci ()
      OFCons :: Term rs ci f
             -> OutFields rs ci fs
             -> OutFields rs ci (f, fs)

`OutFields rs ci fs` is a type-indexed nested-pair HList of `Term`
values; `fs` is the same nested-pair tuple `WireCtor co fs` carries.
`pack ic wc fs = OPack ic wc fs`.

### Terms a novice might not know (already defined in EP-15's note)

- **HList**: a heterogeneous list whose elements may have different
  types, indexed by a type-level list. `OutFields rs ci fs` is an
  HList; `RegFile rs` is too.
- **TH** ("Template Haskell"): GHC's compile-time metaprogramming
  facility. `Keiki.Generics.TH` uses it to emit per-event ctor
  declarations from a name and a spec list.
- **DuplicateRecordFields**: a GHC extension that allows a record
  field name to appear in multiple records in the same module.
  Already on via `keiki.cabal:24`. Without it, M4's per-event
  record types would all have to use distinct field names; with
  it, each event can have an `email :: Term rs ci Email` field
  without clash.

### Build and test commands

Same as EP-15's M0:

    cd /Users/shinzui/Keikaku/bokuno/keiki
    cabal build
    cabal test

Expected baseline (verified at M0):

    Test suite keiki-test: PASS
    Tests passed: 138  (post-EP-15 M7)

GHC 9.12.3, cabal 3.16.1.0, z3 4.16.0 are on PATH on the
development host; `nix-shell -p z3` is the documented portable
entry point but unnecessary on this machine.


## Plan of Work

The work splits into **seven milestones** (M0–M6). Each milestone is
independently verifiable; each ends with a build-and-test green and a
specific observable artefact.

### M0 — Prerequisites

A baseline run: confirm the repo builds, tests pass, and record the
LOC of both example files we will migrate, plus the count of
`emit` call sites. These numbers anchor the M1/M2/M5 success
criteria.

End state: a Decision Log entry recording the post-EP-15 baseline.

Acceptance: `cabal test` is green and we have recorded the
example LOC and the test count.

### M1 — Drop the redundant InCtor and eliminate `Index` annotations

Two related ergonomic fixes shipped together — both remove
boilerplate that EP-15 exposed but did not address.

**Part A: drop `emit`'s redundant `InCtor` argument.**

1. Add `peInCtor :: Maybe (SomeInCtor ci)` to `PartialEdge` (in
   `src/Keiki/Builder.hs`). Set by `onCmd` to `Just (SomeInCtor
   ic)`; `Nothing` in `onEpsilon`.
2. Rename the existing `B.emit` to `B.emitWith` (the InCtor stays
   explicit). Add a new `B.emit` whose signature drops the InCtor:

        emit
          :: forall co fs rs ci v w.
             WireCtor co fs
          -> OutFields rs ci fs
          -> EdgeBuilder rs ci co v w w ()
        emit wc fs = EdgeBuilder $ \pe -> case peInCtor pe of
          Just (SomeInCtor ic) ->
            ((), pe { peOutput = Just (pack ic wc fs) })
          Nothing -> error "Keiki.Builder.emit: no enclosing onCmd \
                          \pinned an InCtor. Use emitWith ic wc fs \
                          \inside onEpsilon, or move emit inside an \
                          \onCmd block."

**Part B: add an `IsLabel s (Term rs ci r)` instance.**

Add to `src/Keiki/Core.hs`, next to the existing
`IsLabel s (Index rs r)` instance:

    instance forall s rs ci r.
             HasIndex s rs r
          => IsLabel s (Term rs ci r) where
      fromLabel = TReg (indexOf @s @rs @r)

This lets `#name` resolve to a `Term`-typed register read in any
context that expects a `Term` (e.g. `requireEq`'s arguments,
`OFCons`'s first argument). The existing `IsLabel s (Index rs r)`
instance is unchanged; GHC dispatches between the two by the
expected result type, so `inpFoo #name` (which expects an `Index`)
continues to resolve to the existing instance, while
`requireEq d.x #y` (which expects a `Term`) resolves to the new
one. No overlap, no ambiguity.

**Migration.**

Migrate the **builder forms** of both example aggregates (and the
spike + BuilderSpec) to drop both the InCtor argument and the
`proj (#name :: Index Regs T)` annotations:

In `src/Keiki/Examples/UserRegistration.hs` (5 builder-form sites):

    -- Before (post-EP-15):
    B.emit inCtorContinue wireConfirmationEmailSent
      (OFCons (proj (#email :: Index UserRegRegs Email)) OFNil)

    -- After (M1):
    B.emit wireConfirmationEmailSent (OFCons #email OFNil)

And one `requireEq` site:

    -- Before:
    B.requireEq d.confirmCode
                (proj (#confirmCode :: Index UserRegRegs ConfirmationCode))

    -- After:
    B.requireEq d.confirmCode #confirmCode

In `src/Keiki/Examples/EmailDelivery.hs`: the builder form has no
`proj`-of-register sites (every emit field is a payload-projected
`d.fieldName`). Only the `inCtorSendEmail` argument is dropped.

The AST forms (`emailDeliveryASTEdges`, `userRegASTEdges`) are
**not** migrated — they remain as the equivalence-test reference
and the documented escape hatch (Decision Log entry above).

The equivalence specs (`EmailDeliveryBuilderSpec`,
`UserRegistrationBuilderSpec`) re-pass without modification — the
runtime behaviour is unchanged because (a) the InCtor recovered
from `peInCtor` is the same one previously passed explicitly, and
(b) `#name` and `proj #name :: Index Regs r` produce the same
`TReg`-rooted `Term`.

End state: the public `emit` signature has two arguments; every
builder-form example call site has lost one InCtor argument and
all `proj (#name :: Index ...)` annotations; tests are green.

Acceptance: `cabal test` is green. `wc -l
src/Keiki/Examples/EmailDelivery.hs` reports < 215; `wc -l
src/Keiki/Examples/UserRegistration.hs` reports < 440. `grep -c
":: Index " src/Keiki/Examples/UserRegistration.hs` reports 5
(AST-form annotations only). The two-argument `emit` in
`src/Keiki/Builder.hs` is exported; the three-argument `emitWith`
is also exported as the documented escape hatch.

### M2 — Operator-style HList sugar

Three changes:

1. In `src/Keiki/Builder.hs`, re-export `OutFields`'s constructors
   under nicer names:

        -- Right-associative HList constructor with the same shape
        -- as 'OFCons'. Fixity 5 matches 'aeson''s '(:)'-like
        -- operators.
        (*:) :: Term rs ci f -> OutFields rs ci fs -> OutFields rs ci (f, fs)
        (*:) = OFCons
        infixr 5 *:

        -- Synonym for 'OFNil'.
        oNil :: OutFields rs ci ()
        oNil = OFNil

2. Migrate the two example aggregates' `emit` call sites to the
   operator form. Migrate the spike and the BuilderSpec equivalent
   sites for consistency.

3. Document the operators in `Keiki.Builder`'s haddock under the
   `emit` section, with a one-line note that they are temporary
   sugar that the field-keyed form (M5) supersedes.

End state: every example `emit` call site uses `(*:)` and `oNil`
in place of `OFCons` and `OFNil`.

Acceptance: `cabal test` is green; LOC drops further on both
examples (no quantitative target — the win is per-line, not
per-aggregate).

### M3 — Design note for field-keyed record sugar

Produce `docs/research/emit-field-keyed-record-sugar.md`,
analogous to EP-15's `edge-builder-dsl-shape.md` but focused on
the emit side. Resolves the four open questions:

1. **Per-event TH-generated record vs class-driven generic
   conversion.** Three candidates:
   - *Per-event TH-generated record `<EventName>TermFields rs
     ci`.* `deriveWireCtors` (or a sibling splice) emits a record
     type per event ctor with `Term rs ci T` fields, plus a
     `ToOutFields` instance.
   - *Generic-Rep-driven record-of-Terms.* A type family
     `TermRec ctor rs ci :: Type` that the TH walks the payload's
     `Generic` Rep to compute. Less code emitted; more type-level
     machinery.
   - *Per-event `emitFoo` helper.* The TH emits a function
     `emitFoo :: <EventName>TermFields rs ci -> EdgeBuilder ...`
     directly, bypassing the typeclass.

2. **Field-name disambiguation.** Two events both having a field
   `email :: Email` produce records both having a field `email
   :: Term rs ci Email` post-conversion. With
   `DuplicateRecordFields` on, this works at construction
   (`OutEventATermFields { email = … }` and
   `OutEventBTermFields { email = … }` are distinct), but
   subsequent `OverloadedRecordDot` access (`rec.email`) requires
   the type to be locally inferred. M3's note shows whether this
   is robust on the realistic case (two events with shared field
   names in the same module).

3. **Interaction with the existing `mkWireCtorVia` and
   `FieldsOf`.** The wire ctor's `fs` (nested-pair tuple) is the
   same shape we need to produce from the per-event record. The
   conversion is a `Generic`-style walk; M3 picks whether to
   share machinery with `Keiki.Generics`'s `GTuple` class or
   inline a smaller variant.

4. **Error-message shape.** Field omissions (the user forgets a
   field in the record literal) currently produce GHC's standard
   "missing field" message. M3 verifies that the message is good
   enough or proposes an enhancement.

End state: the design note exists, answers the four questions
with worked EmailDelivery/UserRegistration examples, and is the
contract M4 consumes verbatim.

Acceptance: a peer review (or a re-read by the author after a
break) can answer "what does the User Registration `Confirm`
edge look like in the new emit form?" by reading only the M3 note
and the existing post-M2 example.

### M4 — Implement field-keyed sugar

Promote the M3 design to working code. Steps:

1. Extend `src/Keiki/Generics/TH.hs`'s `deriveWireCtors` (or add
   a sibling splice — the choice is M3's) to emit, per event
   ctor:
   - A record data type `<CtorName>TermFields rs ci` with one
     field per wire-side field, typed `Term rs ci T`.
   - A `ToOutFields` instance (or free function — M3's pick)
     that converts the record to `OutFields rs ci fs` matching
     the wire ctor's `fs`.

2. Add `B.emit` overload (or a typeclass-method variant) in
   `src/Keiki/Builder.hs` that takes a record value:

        emit
          :: ToOutFields rec rs ci fs
          => WireCtor co fs
          -> rec
          -> EdgeBuilder rs ci co v w w ()

   The typeclass `ToOutFields rec rs ci fs | rec -> rs ci fs`
   has one method `toOutFields :: rec -> OutFields rs ci fs`.
   The TH-emitted instance per event is the only inhabitant; users
   never write a manual instance.

3. Keep the operator-form `emit wc (t1 *: t2 *: oNil)` working (it
   is just the existing two-argument `emit` with the second arg as
   an explicit `OutFields`). One way is to make the existing
   two-arg form an instance of `ToOutFields` over `OutFields`
   itself:

        instance ToOutFields (OutFields rs ci fs) rs ci fs where
          toOutFields = id

   With the two instances (record-typed and `OutFields`-typed),
   GHC dispatches based on the second argument's type.

4. Add unit tests for the new shape in
   `test/Keiki/BuilderSpec.hs`: 2–3 cases asserting the record
   form and the operator form produce identical `OutFields` for
   the same data.

End state: `Keiki.Builder.emit` accepts both an `OutFields` and a
`<EventName>TermFields` record (and the operator form via
`OutFields`). The two example aggregates compile against either
form.

Acceptance: `cabal build` is clean; new BuilderSpec cases pass;
the existing equivalence specs continue to pass byte-identically.

### M5 — Migrate examples to the field-keyed form

Update every `emit` call site in
`Keiki.Examples.EmailDelivery` and
`Keiki.Examples.UserRegistration` to use the record-syntax form.
Confirm equivalence specs (`EmailDeliveryBuilderSpec`,
`UserRegistrationBuilderSpec`) continue to pass byte-identically.

Confirm LOC drops to < 210 (EmailDelivery) and < 420
(UserRegistration). The exact targets are M0-baseline-anchored;
the M0 entry records the actual figures.

End state: every example `emit` is in field-keyed form; LOC
targets met.

Acceptance: `cabal test` is green; LOC `wc -l` numbers within
target.

### M6 — Documentation closure

Three writing tasks:

1. Update `Keiki.Builder`'s module-level haddock — replace the
   `OFCons`-using EmailDelivery example with the record-syntax
   one. Note `emitWith` and the operator form as the lower-level
   escape hatches.

2. Update `docs/research/edge-builder-dsl-shape.md` Q3 ("emit
   shape"). The original deferred two follow-ups; this plan
   landed both. Replace the "deferred" framing with a brief
   summary of the final shape.

3. Update `docs/foundations/06-where-to-go-next.md`'s §"Authoring
   a transducer" to mention the record-syntax `emit` form
   alongside the `slot @"name"` slot syntax.

If the deprecated explicit-InCtor `emit` form (renamed to
`emitWith` at M1) has no remaining call sites in the repo, remove
it as part of M6. Otherwise keep it as the documented escape
hatch and mention this in the Decision Log.

End state: all three docs reflect the post-M5 shape; haddock is
clean; LOC targets met.

Acceptance: `cabal haddock` produces clean haddock for
`Keiki.Builder` (no missing-docs warnings); a quick re-read of
the modified docs matches the M3 design note.


## Concrete Steps

The exact commands to run, in order. Working directory is
`/Users/shinzui/Keikaku/bokuno/keiki` throughout unless stated otherwise.

### M0 — baseline

    cabal build
    cabal test
    wc -l src/Keiki/Examples/EmailDelivery.hs
    wc -l src/Keiki/Examples/UserRegistration.hs
    grep -c "B.emit" src/Keiki/Examples/EmailDelivery.hs
    grep -c "B.emit" src/Keiki/Examples/UserRegistration.hs
    grep -c ":: Index " src/Keiki/Examples/EmailDelivery.hs
    grep -c ":: Index " src/Keiki/Examples/UserRegistration.hs

Expected (post-EP-15 baseline):

    Test suite keiki-test: PASS
    Tests passed: 138
       220 src/Keiki/Examples/EmailDelivery.hs
       464 src/Keiki/Examples/UserRegistration.hs
    1   (EmailDelivery emit count)
    5   (UserRegistration emit count)
    0   (EmailDelivery :: Index annotations)
    10  (UserRegistration :: Index annotations — 5 builder, 5 AST)

Record the exact numbers in the Decision Log under
"M0 baseline (date)".

### M1 — drop InCtor + eliminate Index annotations

Edit `src/Keiki/Core.hs`:
- Add `IsLabel s (Term rs ci r)` instance next to the existing
  `IsLabel s (Index rs r)` instance (around `src/Keiki/Core.hs:156-160`).
- Add `Term` to the `OverloadedLabels` discoverability comment
  near the existing instance, if such a comment exists.

Edit `src/Keiki/Builder.hs`:
- Add `peInCtor :: Maybe (SomeInCtor ci)` to `PartialEdge`.
- Update every `PartialEdge { … }` constructor call (in `onCmd`,
  `onEpsilon`, `(.=)`, `goto`, `emit`, `noEmit`, `requireGuard`)
  to thread `peInCtor` through. `onCmd` initialises it with `Just
  (SomeInCtor ic)`; `onEpsilon` initialises with `Nothing`; the
  rest preserve the existing value.
- Import `SomeInCtor (..)` from `Keiki.Symbolic`.
- Rename the existing 3-arg `emit` to `emitWith`.
- Add a new 2-arg `emit` that reads `peInCtor`.
- Update the module-level haddock to mention both the new `emit`
  shape and the `#name`-as-`Term` resolution.

Edit `src/Keiki/Examples/EmailDelivery.hs` (1 builder-form site):
drop the InCtor argument from the single `B.emit` call. The
builder form has no `proj (#name :: Index Regs T)` sites.

Edit `src/Keiki/Examples/UserRegistration.hs` (5 builder-form
sites): drop the InCtor argument from every `B.emit` call AND
replace each `proj (#name :: Index UserRegRegs T)` with bare
`#name`. The AST-form sites (`userRegASTEdges`) are left
untouched.

Edit `test/Keiki/BuilderSpike.hs`,
`test/Keiki/BuilderSpec.hs`: drop InCtor argument; migrate any
`proj (#name :: ...)` sites if present.

Run:

    cabal build
    cabal test
    grep -c ":: Index " src/Keiki/Examples/UserRegistration.hs
    grep -c ":: Index " src/Keiki/Examples/EmailDelivery.hs

Expected: 138+ examples pass (no test count change at this
point — behaviour is identical). The `grep` reports 5 (AST-form
only) for UserRegistration and 0 or a small AST-form count for
EmailDelivery.

Commit at green.

### M2 — operator sugar

Edit `src/Keiki/Builder.hs`: add `(*:)` and `oNil` exports.

Edit the two example aggregates and the spike: replace `OFCons`
chains with `*:` chains; replace `OFNil` with `oNil`. The
BuilderSpec tests already use `OFCons`/`OFNil` constructors
directly (their call sites are not user-facing); migrating them
is optional.

Run:

    cabal test
    wc -l src/Keiki/Examples/EmailDelivery.hs
    wc -l src/Keiki/Examples/UserRegistration.hs

Expected: tests still green; LOC drops a small amount per emit.
Commit at green.

### M3 — design note

Create:

    touch docs/research/emit-field-keyed-record-sugar.md

Write the four open questions and their resolutions. The note's
"Worked example" section reproduces EmailDelivery's emit and one
of UserRegistration's confirm edge in the chosen surface.

Commit at writing-complete.

### M4 — implementation

Edit `src/Keiki/Generics/TH.hs`: extend `genWire` (or add a
sibling) to emit the per-event TermFields record + ToOutFields
instance.

Edit `src/Keiki/Builder.hs`: introduce the `ToOutFields` typeclass
and the new `emit` overload.

Edit `test/Keiki/BuilderSpec.hs`: add 2–3 cases.

Run:

    cabal build
    cabal test

Expected: build clean; ≥140 examples pass.
Commit at green.

### M5 — migrate examples

Edit `src/Keiki/Examples/EmailDelivery.hs` and
`src/Keiki/Examples/UserRegistration.hs`: every `emit` site uses
record syntax.

Run:

    cabal test
    wc -l src/Keiki/Examples/EmailDelivery.hs
    wc -l src/Keiki/Examples/UserRegistration.hs

Expected: tests green; EmailDelivery < 210 LOC; UserRegistration
< 420 LOC. Commit at green.

### M6 — docs

Edit `Keiki.Builder` haddock,
`docs/research/edge-builder-dsl-shape.md` (Q3 section), and
`docs/foundations/06-where-to-go-next.md`. Remove `emitWith` if
no call site uses it.

Run:

    cabal haddock

Expected: 100% coverage on `Keiki.Builder`; no missing-docs
warnings.

Commit at green.


## Validation and Acceptance

The plan is complete when:

1. `cabal build` is clean under GHC 9.12.x.
2. `cabal test` is green at ≥143 test examples (138 baseline + ≥5
   from M4 + M5 unit additions).
3. Every `B.emit` call site in `Keiki.Examples.EmailDelivery` and
   `Keiki.Examples.UserRegistration` uses the record-syntax form
   (no `OFCons`/`OFNil`/`*:`/`oNil`/explicit InCtor). No
   `proj (#name :: Index Regs T)` annotations remain in the
   builder forms.
4. The equivalence specs (`EmailDeliveryBuilderSpec`,
   `UserRegistrationBuilderSpec`) pass: for every step of the
   canonical event log, `delta` and `omega` agree between the
   builder-form and AST-form transducer. Behaviour is unchanged.
5. `wc -l src/Keiki/Examples/EmailDelivery.hs` reports < 210.
6. `wc -l src/Keiki/Examples/UserRegistration.hs` reports < 420.
7. `Keiki.Builder`'s haddock includes the record-syntax form in
   the worked tutorial; `docs/research/edge-builder-dsl-shape.md`
   Q3 records the final shape; the M3 design note exists.

A skeptical reviewer can verify the user-visible improvement by
diffing pre- and post-M5 emit call sites and confirming the
record-syntax form is shorter, named, and field-disambiguated.


## Idempotence and Recovery

Every milestone is additive on top of the post-EP-15 baseline; M0
reads only; M1 introduces a renamed escape hatch (`emitWith`) so
the old shape stays available; M2's operator sugar is purely
additive; M3 writes a doc; M4 adds typeclass + TH support without
removing anything; M5 migrates call sites (reversible by reverting
the commit); M6's docs are reversible.

If a milestone breaks, the strategy is:

- M1: if `peInCtor` threading breaks any test, revert the
  `Keiki.Builder` edit and migrate examples back. The escape
  hatch `emitWith` was the original `emit`; its semantics are
  unchanged.
- M2: if the operator sugar resolves wrong, the call sites still
  work with `OFCons`/`OFNil` (the operators are aliases).
- M4: if the typeclass-overloaded `emit` causes ambiguity at any
  call site, fall back to the M2 operator form via type
  ascription. The typeclass dispatch's failure mode is a clear
  GHC error pointing at the ambiguous site.
- M5: if any equivalence-test fails, the AST-form transducers
  (`emailDeliveryAST`, `userRegAST`) still exist and the
  equivalence test names the offending edge.

Re-running steps:

- `cabal build` and `cabal test` are deterministic.
- `cabal clean` is safe at any point if the build cache becomes
  inconsistent.
- The plan introduces no migrations of on-disk state, no
  destructive database changes, no shared-resource modifications.

Recovery from an unintended commit: revert with `git revert <sha>`
or amend the prior commit. The plan is implemented on the current
branch (`master`).


## Interfaces and Dependencies

### Modules consumed (and one minor extension)

- `Keiki.Core` (`src/Keiki/Core.hs`): `OutFields`, `OPack`,
  `pack`, `WireCtor`, `OutTerm`, `Term`, `Edge`, `Index`,
  `HasIndex`. M1 adds one new instance — `IsLabel s (Term rs ci
  r)` — alongside the existing `IsLabel s (Index rs r)`. The
  instance reuses the existing `HasIndex` class machinery; no
  other surface change to `Keiki.Core`. M4 produces the same
  `OutFields` shape from the TH-emitted records.
- `Keiki.Symbolic` (`src/Keiki/Symbolic.hs`): `SomeInCtor` —
  reused by M1's `peInCtor` field. The constructor is unchanged.
- `Keiki.Generics` (`src/Keiki/Generics.hs`): `FieldsOf`,
  `GTuple`. M4 may reuse the `GTuple` walk for the record-to-
  OutFields conversion or hand-roll a smaller variant per the M3
  design.
- `Keiki.Generics.TH` (`src/Keiki/Generics/TH.hs`):
  `deriveWireCtors`, `genWire`. M4 extends one of these or adds a
  sibling.

### Modules produced

- **Modified** `Keiki.Builder` (`src/Keiki/Builder.hs`). New surface
  exports: `(*:)`, `oNil`, `emitWith`, the record-syntax overload
  of `emit`. The existing three-argument `emit` is renamed to
  `emitWith`.
- **Modified** `Keiki.Generics.TH` (`src/Keiki/Generics/TH.hs`). New
  per-event declarations emitted alongside the existing `wire<Short>`:
  `<CtorName>TermFields` record + `ToOutFields` instance.
- **Possibly new** `ToOutFields` typeclass — could live in
  `Keiki.Builder` or in a new `Keiki.Builder.Types` if the
  surface bloats. M3's design note picks.

### No new build-time dependencies

This plan adds no packages to `keiki.cabal`'s `build-depends`.

### Test suite

- **New** test cases in `test/Keiki/BuilderSpec.hs` (M4): ≥3
  cases for the record-syntax form and the typeclass dispatch.
- **Migrated** but not changed in count:
  `test/Keiki/Examples/EmailDeliveryBuilderSpec.hs`,
  `test/Keiki/Examples/UserRegistrationBuilderSpec.hs`,
  `test/Keiki/BuilderSpike.hs`.

### Out of scope

- **Changes to the AST.** As in EP-15, the AST stays.
  `OutFields`, `OPack`, `pack` are unchanged.
- **Auto-derived `WireCtor` from the record-of-Terms type alone.**
  We still go through the existing `deriveWireCtors` on the
  payload type, which gives the wire-side `WireCtor co (FieldsOf
  Payload)`. The M4 record type is *parallel* to the wire ctor, not
  a replacement.
- **Eliminating `mkWireCtorVia`.** It stays. The M4 record type
  drives the *user-side* construction; `mkWireCtorVia` remains the
  source of `WireCtor` values.
- **Removing the `FieldsOf` type family.** Same reasoning — it's
  the wire-side schema.
- **A quasi-quoter for emit.** Out of scope (rejected for the
  same reasons EP-15 rejected `[transducer| … |]`).

### Soft external dependencies (all Complete)

- *EP-15.* Complete on 2026-05-02. This plan consumes the post-EP-15
  `Keiki.Builder` surface verbatim.
- *MP-3 (TH-derived per-constructor scaffolding).* Complete.
  `deriveWireCtors` is the entry point M4 extends.
- *MP-6 (escape-hatch retirements).* Complete. Defines the
  `OutFields`/`OPack` shape this plan continues to consume.
