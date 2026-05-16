---
id: 19
slug: multi-event-commands-via-edge-output-widening-gsm-expansion
title: "Multi-event commands via Edge.output widening (GSM expansion)"
kind: exec-plan
created_at: 2026-05-02T14:53:04Z
intention: "intention_01kqmjp9k8e478db6xjah31455"
master_plan: "docs/masterplans/7-multi-event-command-support-gsm-widening-vs-state-refinement-ergonomics.md"
---

# Multi-event commands via Edge.output widening (GSM expansion)

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Status (2026-05-16) — Reopened under reconsideration

This plan was marked **Cancelled** on 2026-05-02 in
`docs/masterplans/7-multi-event-command-support-gsm-widening-vs-state-refinement-ergonomics.md`'s
Exec-Plan Registry when the user selected EP-20 (state-refinement
ergonomics) for implementation. EP-20 shipped end-to-end on 2026-05-02
with `Keiki.Core.applyEvents` (letter-fold), `Keiki.Decider.toMultiDecider`
+ `DriverConfig`, `Keiki.Builder.chainTo`, and `userRegDriverConfig` /
`userRegChained` examples; test baseline grew 149 → 166 at that point.

Since then the surface that builds on top of `Keiki.Core.Edge` has
grown substantially:

- `src/Keiki/Profunctor.hs` shipped (EP-29, 2026-05-14): heavy
  `Maybe (OutTerm ...)` fmap pattern across `Arrow`/`Strong`/`Choice`
  instances, `firstEdge`, `rewriteEdge`, `rewriteEdgeMaybe`,
  `rewriteEdgeOut`.
- `src/Keiki/Render/Mermaid.hs` shipped: diagram-generation now real —
  the MasterPlan's dimension-2 ("diagrams prefer letter FST") is
  concrete instead of hypothetical.
- The example aggregates moved out of `src/Keiki/Examples/` into a
  sibling package `jitsurei/` (~8 aggregates: `UserRegistration`,
  `UserRegistrationV0`, `EmailDelivery`, `Loan`, `LoanApplication`,
  `LoanWorkflow`, `OrderCart`, `CoreBankingSync`). Several use
  `chainTo`-based multi-event commands today (`UserRegistration`,
  `LoanApplication`).
- Two new sibling packages exist (`keiki-codec-json`,
  `keiki-codec-json-test`). They operate on `RegFile`, not `Edge`;
  insulated from this widening.
- Test baseline: 110 → **337** examples across four test suites
  (keiki 186 + jitsurei 104 + codec-json 40 + codec-json-test 7),
  0 failures, 1 pending.
- Total `output = Just|Nothing` / `Maybe (OutTerm ...)` / `Just (OPack ...)`
  call sites: **~69** (was estimated ~24 at plan-draft time).
- The `Edge` declaration itself has shifted to GADT syntax with an
  existential type variable in `Update rs w ci`
  (`src/Keiki/Core.hs:455-461`, not 411-419 as the original plan text
  cited). The widening must preserve the existential.

The user's stated reasoning for reconsideration (2026-05-16): "It
looks like this is more relevant than I thought and it might be
better to implement now than later since it affects the packages
that are built on top of keiki ... it's not only about
`toMultiDecider`, it's first-class support for emitting multiple
events."

This reverses the MasterPlan's 2026-05-02 selection. Implications:

- The MasterPlan's Exec-Plan Registry must be updated (EP-19 →
  In Progress; EP-20 → Superseded by EP-19).
- EP-20's shipped surface needs an explicit retirement (or
  coexistence) strategy — see new Decision Log entries below.
- M6 (composition) must commit to a concrete strategy for
  multi-event composition; the MasterPlan's dimension-4 critique
  (multi-event composition is fundamentally non-local) is real
  and must be addressed in M1's design note rather than waved at
  with "concatenate output lists."
- M7's scope expands from "UserRegistration" to "jitsurei-wide
  migration" plus the Profunctor + Mermaid cascades inside
  `src/Keiki/`.

All milestones (M0–M8) are reopened. The Progress checkboxes
remain unchecked.


## Purpose / Big Picture

The keiki library today models its core formalism as a *letter Finite State
Transducer* (letter FST): every edge of a `SymTransducer` produces zero or
exactly one observable event. This is encoded directly in the AST:

    -- src/Keiki/Core.hs:411-419
    data Edge phi rs ci co s = Edge
      { guard  :: phi
      , update :: Update rs ci
      , output :: Maybe (OutTerm rs ci co)   -- Nothing = ε; Just o = one event
      , target :: s
      }

A command that semantically produces two or more events (the canonical
example is `StartRegistration`, which logically emits both
`RegistrationStarted` and `ConfirmationEmailSent`) is split into two letter
edges via *state refinement*: an intermediate vertex (`Registering`) and a
synthetic internal command (`Continue`) chain the events. The aggregate's
state enum and command enum each carry one extra constructor per multi-event
command. `src/Keiki/Examples/UserRegistration.hs` ships exactly this shape.

This ExecPlan widens the AST so multi-event commands become first-class:

    data Edge phi rs ci co s = Edge
      { guard  :: phi
      , update :: Update rs ci
      , output :: [OutTerm rs ci co]         -- [] = ε; [o] = today's letter; [o1, o2, ...] = multi
      , target :: s
      }

The widened AST is a *Generalized Sequential Machine* (GSM) in the
formal-languages sense. Length-0 and length-1 outputs are bit-for-bit
equivalent to today's letter FST behavior; length-2+ outputs admit
multi-event commands without intermediate vertices. After this plan
completes:

- `src/Keiki/Examples/UserRegistration.hs` no longer carries a `Registering`
  intermediate vertex or a `Continue` internal command. The
  `StartRegistration` edge directly produces `[RegistrationStarted,
  ConfirmationEmailSent]` from `PotentialCustomer` to `RequiresConfirmation`.
  Vertex enum drops one constructor; command enum drops one constructor.

- `Keiki.Decider`'s `decide :: c -> s -> [e]` actually takes advantage of
  its list shape — it returns `[e]` of length 0, 1, or 2+ rather than always
  0 or 1. The docstring caveat on `toDecider` ("at most one event per
  command") is retired.

- `Keiki.Core.applyEvents` exists as a chunk-replay function that drives the
  letter chain corresponding to one logical command (length-N output) and
  returns the unwrapped final state.

- `Keiki.Core.applyEvent` returns wrapped state `InFlight s co = Settled s |
  InFlight s [co]` because single-event-streaming replay through a
  multi-event edge necessarily passes through "I just observed event 1 of
  N; expecting events 2..N next."

- `Keiki.Core.checkHiddenInputs` walks the per-edge output list as a whole.
  The hidden-input check strengthens to: the *union* of input slots covered
  by all `OutTerm`s on an edge must include every slot the guard or update
  reads. A multi-event edge that reads `confirmCode` in its update but emits
  no event carrying `confirmCode` is flagged.

- `Keiki.Composition.compose` adapts to compose multi-event edges by
  concatenating output lists with the existing `substOut` substitution
  applied to each.

A future contributor verifies the work as follows:

    cd /Users/shinzui/Keikaku/bokuno/keiki
    nix-shell -p z3 --run "cabal test all" 2>&1 | tail -3
    # Expect: 110 + N examples (where N is the number of new specs added by this plan), 0 failures.
    # The new specs include: a UserRegistrationGSMSpec asserting the multi-event
    # edge produces an identical [event] sequence to the previous letter-FST
    # version; an applyEventsSpec asserting chunk replay round-trips; a
    # checkHiddenInputsGSMSpec asserting the strengthened union check fires on
    # a deliberately ill-formed multi-event edge.

The user-visible win:

    > decide userRegDecider (StartRegistration startData) (PotentialCustomer, emptyRegs)
    [ RegistrationStarted (RegistrationStartedData "alice@x" "Z9F4" t0)
    , ConfirmationEmailSent (ConfirmationEmailSentData "alice@x")
    ]

A single command produces a 2-element event list, with no intermediate vertex
in the user's enum.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be
documented here, even if it requires splitting a partially completed task into
two ("done" vs. "remaining"). This section must always reflect the actual
current state of the work.

- [x] **Milestone 0 — Verify prerequisites and inventory the cascade.** (2026-05-16)
      Ran `cabal build all` (OK) and `cabal test all --test-show-details=direct`
      (z3 was not required — none of the running specs invoked the SBV-backed
      symbolic backend in this run). Baseline confirmed exactly at expectation:
      **337 examples**, 0 failures, 1 pending across four test suites:

          Test suite keiki-test:               186 examples, 0 failures
          Test suite jitsurei-test:            104 examples, 0 failures, 1 pending
          Test suite keiki-codec-json-test:     40 examples, 0 failures
          Test suite keiki-codec-json-test-test: 7 examples, 0 failures

      Inventory results (against master 2026-05-16):

          $ git grep -nE '(Maybe \(OutTerm|output = (Just|Nothing)|Just \(OPack)' \
              -- src jitsurei keiki-codec-json keiki-codec-json-test test | wc -l
          69          # matches plan expectation exactly

          $ git grep -nE 'toMultiDecider|DriverConfig|chainTo|userRegDriverConfig|userRegChained|loanAppChained|peChain|EdgeListAcc|chainAdvanceCommand' \
              -- src jitsurei test | wc -l
          112         # EP-20 surface to retire

          $ git grep -nE 'firstEdge|rewriteEdge|identityOutTerm|arrOut|edgeOutputName|wcName' \
              -- src/Keiki/Profunctor.hs src/Keiki/Render | wc -l
          35          # Profunctor + Mermaid cascade

      Per-file breakdown of Edge.output call sites (matches plan ±):

          12 jitsurei/src/Jitsurei/OrderCart.hs
          11 jitsurei/src/Jitsurei/LoanApplication.hs
           6 test/Keiki/Fixtures/UserRegistration.hs
           6 jitsurei/src/Jitsurei/UserRegistrationV0.hs
           6 jitsurei/src/Jitsurei/UserRegistration.hs
           4 test/Keiki/SymbolicSpec.hs
           3 test/Keiki/CompositionFeedback1Spec.hs
           2 test/Keiki/BuilderSpike.hs
           2 src/Keiki/Render/Mermaid.hs
           2 src/Keiki/Profunctor.hs
           2 src/Keiki/Core.hs
           2 src/Keiki/Builder.hs
           1 test/Keiki/Render/MermaidSpec.hs
           1 test/Keiki/ProfunctorSpec.hs
           1 test/Keiki/Fixtures/EmailDelivery.hs
           1 test/Keiki/CoreSpec.hs
           1 test/Keiki/CompositionSpec.hs
           1 test/Keiki/CompositionAlternativeSpec.hs
           1 test/Keiki/BuilderSpec.hs
           1 src/Keiki/Decider.hs
           1 src/Keiki/Composition.hs
           1 jitsurei/test/Jitsurei/LoanApplicationMultiSpec.hs
           1 jitsurei/src/Jitsurei/EmailDelivery.hs

      GHC version: 9.12.2 (per flake.nix). Edge GADT confirmed at
      `src/Keiki/Core.hs:455-462`; `applyEvents` at
      `src/Keiki/Core.hs:708-717`.

      Record the actual counts at plan-start time and the GHC version
      (currently pinned to 9.12.2 per `flake.nix`).

      Inventory every site touching `Edge.output` via `git grep`.
      Expected count is **~69 sites** as of 2026-05-16 (was ~24 at
      original plan-draft time; the growth is from `jitsurei/`,
      `Keiki.Profunctor`, and `Keiki.Render.Mermaid`):

          git grep -nE 'output = (Just|Nothing)|Maybe \(OutTerm|Just \(OPack' \
            -- src jitsurei keiki-codec-json keiki-codec-json-test test \
            | tee /tmp/gsm-call-sites.txt
          wc -l /tmp/gsm-call-sites.txt

      Then re-grep specifically for the EP-20 surface that this
      plan must retire or coexist with (decision flagged in
      Decision Log, item "EP-20 surface retirement strategy"):

          git grep -nE 'toMultiDecider|DriverConfig|chainTo|userRegDriverConfig|userRegChained' \
            -- src jitsurei test

      And the Profunctor/Mermaid cascades that are new since the
      plan's first draft:

          git grep -nE 'firstEdge|rewriteEdge|identityOutTerm|arrOut|edgeOutputName|wcName' \
            -- src/Keiki/Profunctor.hs src/Keiki/Render

      Specific call-site clusters expected:

      | File | Sites |
      |---|---|
      | `jitsurei/src/Jitsurei/OrderCart.hs` | 12 |
      | `jitsurei/src/Jitsurei/LoanApplication.hs` | 11 |
      | `jitsurei/src/Jitsurei/UserRegistration.hs` | 6 |
      | `jitsurei/src/Jitsurei/UserRegistrationV0.hs` | 6 |
      | `test/Keiki/Fixtures/UserRegistration.hs` | 6 |
      | `test/Keiki/SymbolicSpec.hs` | 4 |
      | `test/Keiki/CompositionFeedback1Spec.hs` | 3 |
      | `src/Keiki/Profunctor.hs` | 2 (+ heavy fmap/rewrite) |
      | `src/Keiki/Builder.hs` | 2 |
      | `src/Keiki/Core.hs` | 2 |
      | `src/Keiki/Render/Mermaid.hs` | 2 |
      | `test/Keiki/BuilderSpike.hs` | 2 |
      | Other (single-site each) | ~11 |

      Record the actual count and per-file breakdown in the Progress
      section so M2 can verify completeness after the cascade.

      **EP-20 surface inventory.** Today's master ships the
      following EP-20 artefacts that this plan must explicitly
      address:

      - `Keiki.Core.applyEvents` at `src/Keiki/Core.hs:708-717`
        (letter-fold over `applyEvent`). EP-19 keeps the name and
        widens the implementation (M3); type signature stays
        compatible, semantics generalize.
      - `Keiki.Decider.toMultiDecider` at `src/Keiki/Decider.hs:188`
        plus `DriverConfig` and chain-replay helpers. EP-19's
        replacement is `decide` returning a real `[e]` directly;
        retirement strategy pending.
      - `Keiki.Builder.chainTo` at `src/Keiki/Builder.hs:439-444`
        plus `peChain` snoc-list machinery (lines 245-260) and
        `EdgeListAcc { elaMain, elaChain }`. EP-19's replacement
        is multiple `emit` calls in one `onCmd` block; retirement
        strategy pending.
      - `jitsurei/src/Jitsurei/UserRegistration.hs:284-470`:
        `userReg` (builder), `userRegAST` (AST), `userRegChained`
        (builder + `chainTo`), `userRegDriverConfig`.
      - `jitsurei/src/Jitsurei/LoanApplication.hs:776-820`:
        `loanAppChained` (builder + `chainTo`), driver config.
      - `jitsurei/test/Jitsurei/UserRegistrationMultiSpec.hs`,
        `UserRegistrationChainedSpec.hs`,
        `LoanApplicationMultiSpec.hs`,
        `LoanApplicationChainedSpec.hs`,
        `test/Keiki/DeciderMultiSpec.hs`,
        `test/Keiki/CoreApplyEventsSpec.hs` — all assert against
        the letter-chain-driven-by-driver-config behaviour.

      **Edge declaration shape.** Note that `Edge` has moved to
      GADT syntax with an existential `w` in the `Update`:

          -- src/Keiki/Core.hs:455-461
          data Edge phi rs ci co s where
            Edge
              :: { guard  :: phi
                 , update :: Update rs w ci   -- existential w
                 , output :: Maybe (OutTerm rs ci co)
                 , target :: s
                 }

      M2's widening must preserve the existential. The new field
      type is `output :: [OutTerm rs ci co]`; the GADT envelope
      stays.

- [x] **Milestone 1 — Design note.** (2026-05-16) Wrote
      `docs/research/gsm-widening-design.md` (420 lines, vs.
      target ~200-250). Covers all 10 sections from Plan of Work
      M1 plus a worked example on the `StartRegistration` chain
      and an explicit references section. Cover: the formal mapping from letter FST to GSM (cite
      Approach 2 in `docs/research/multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md`);
      the `InFlight s co` wrapper for single-event-streaming replay; what's
      preserved (per-`OutTerm` `solveOutput` invertibility, per-edge guard
      evaluation, vertex enumeration via `(Bounded, Enum)`); what changes
      (the hidden-input check fires on edge-list union; composition
      concatenates lists; `omega` returns `[co]`); what's deferred
      (conditional output lists where the list shape depends on the input —
      these still require multiple disjoint-guarded edges per the existing
      pattern).

- [x] **Milestone 2 — Widen `Edge.output` and adapt the core operators.**
      (2026-05-16) Completed. Concrete changes:

      - `src/Keiki/Core.hs`: `Edge.output` widened to
        `[OutTerm rs ci co]` (existential `w` preserved in `update`).
        `omega` returns `[co]`; `step` returns
        `Maybe (s, RegFile rs, [co])`. `applyEvent` keeps letter-only
        semantics for M2 (length-0/1; M3 widens with `InFlight`).
        `checkHiddenInputs` walks the per-edge output list (per-`OPack`
        for M2; M4 strengthens to union coverage).
      - `src/Keiki/Composition.hs`: `composeEdge`, `productEdge`,
        `liftEdgeL`, `liftEdgeR` all widened. Multi-event first-edges
        fall through to head-only composition for M2 (M6 replaces with
        library-side chain expansion).
      - `src/Keiki/Decider.hs`: `toDecider`'s `decide` lifts directly
        from `omega`; `toMultiDecider`'s `driveDecide` reverses the
        evaluated event list per step. (`toMultiDecider`,
        `DriverConfig` retained for M5 removal.)
      - `src/Keiki/Profunctor.hs`: `identityTransducer` and
        `arrTransducer` literal outputs widened to length-1 lists.
        All `fmap` sites (`firstEdge`, `rewriteEdge`,
        `rewriteEdgeMaybe`, `rewriteEdgeOut`) work unchanged on the
        new list shape (list-fmap has identical syntax).
      - `src/Keiki/Render/Mermaid.hs`: `edgeOutputName` implements the
        length-based switchover per the Decision Log (length-1: `e1`;
        length-2: `e1; e2`; length-3+: `e1<br/>e2<br/>...`).
      - `src/Keiki/Builder.hs`: `peOutput :: [OutTerm rs ci co]`
        (snoc-list). `emit` / `emitWith` append. `noEmit` no-ops.
        **Deleted**: `chainTo`, `ChainPrefix`, `peChain`,
        `EdgeListAcc`, `groupBySourceFirstSeen`,
        `explodePartialEdge`, `finalizeFinalEdge`. `EdgeListBuilder`
        reverts to a single `[Edge]` accumulator. The factoring
        Decision Log entry committed M2 to deleting `chainTo` (and
        its direct callers) here rather than deferring to M7.
      - jitsurei aggregates: mechanical `Just o → [o]` /
        `Nothing → []` cascade across `OrderCart` (12),
        `LoanApplication` (11), `UserRegistration` (6),
        `UserRegistrationV0` (6), `EmailDelivery` (1). **Deleted**:
        `userRegChained` + `loanApplicationChained` (callers of
        `chainTo`); their `*Chained` test specs
        (`UserRegistrationChainedSpec`, `LoanApplicationChainedSpec`)
        and their entries in `jitsurei/test/Spec.hs` /
        `jitsurei/jitsurei.cabal`.
      - Test fixtures: `test/Keiki/Fixtures/UserRegistration.hs` (6
        AST sites + `userRegChained` deletion);
        `test/Keiki/Fixtures/EmailDelivery.hs` (1 site).
      - Test specs: cascade-fixed across ~20 files — `omega`
        assertions (`shouldBe Just X` → `shouldBe [X]`,
        `shouldBe Nothing` → `shouldBe []`), `step` patterns
        (`Just (s, r, Just X)` → `Just (s, r, [X])`,
        `Just (s, r, Nothing)` → `Just (s, r, [])`), helper sigs
        (`showStep`, `show3`, `runOmega`, `fireFromInitial`,
        `firstEdgeOutput`, `fireOutputsOnly`).

      **Validation**: `cabal test all --test-show-details=direct`
      reports **324 examples, 0 failures, 1 pending** across four
      suites (keiki 186 + jitsurei 91 + codec-json 40 +
      codec-json-test 7). The 13-example decrease from the 337
      baseline is exactly the deleted `*Chained` specs.
      Edit `src/Keiki/Core.hs` (Edge GADT now at lines 455-461):
      - Change the `output` field's type from `Maybe (OutTerm rs ci co)` to
        `[OutTerm rs ci co]`. Preserve the existential `w` in the
        `update :: Update rs w ci` field.
      - Adapt `omega :: ... -> Maybe co` to `omega :: ... -> [co]`. The body
        evaluates each `OutTerm` in the edge's list and returns the
        concatenation.
      - Adapt `step :: ... -> Maybe (s, RegFile rs, Maybe co)` to
        `step :: ... -> Maybe (s, RegFile rs, [co])` returning the list.
      - Adapt every internal pattern-match on the old `Maybe`. Notably:
        `applyEvent` (current line ~564) must change semantics — see M3.
        `checkHiddenInputs`'s `edgeReasons` must walk the list.
      - `applyEvents` already exists at `src/Keiki/Core.hs:708-717` as a
        letter-fold (EP-20's M2 shipped it). The signature stays
        `:: SymTransducer phi rs s ci co -> (s, RegFile rs) -> [co] ->
        Maybe (s, RegFile rs)`; M3 widens the implementation so it
        properly handles length-2+ chunks rather than folding individual
        events.
      - The `pack` helper stays unchanged (it constructs one `OutTerm`).
        A new helper `silent :: [OutTerm rs ci co]; silent = []` may be
        added to express ε-edges in DSL surface, replacing today's
        `Nothing`.

      Cascade-fix every call site that constructs an edge: replace
      `output = Just o` with `output = [o]` and `output = Nothing` with
      `output = []`. Run `cabal build all`; expect compile errors at every
      remaining site, fix them, until `cabal build all` succeeds.

      **Profunctor cascade (new since plan first draft).** Edit
      `src/Keiki/Profunctor.hs`. This module shipped after the plan was
      drafted (EP-29, 2026-05-14) and has heavy `fmap`/`Maybe`-shaped
      patterns over the old `output` field:

      - `rewriteEdge`, `rewriteEdgeMaybe`, `rewriteEdgeOut` (lines 921,
        933, 945) — `fmap (...) mo` over `Maybe (OutTerm ...)`. Widen
        to `fmap (...)` over `[OutTerm ...]` (list-fmap, same syntax,
        different semantics).
      - `firstEdge` (line 621) — `fmap firstOutTerm mo`. Same change.
      - Two literal constructions of `output = Just identityOutTerm`
        (line 317) and `output = Just arrOut` (line 720) — change to
        `output = [identityOutTerm]` / `output = [arrOut]`.
      - The `Arrow`/`Strong`/`Choice`/`Category` instance laws
        (proven by `test/Keiki/{Arrow,Strong,Choice,Category}Spec.hs`)
        must still hold under the widened type. Re-run all four specs
        after the edit.

      **Mermaid renderer cascade (new since plan first draft).** Edit
      `src/Keiki/Render/Mermaid.hs` (lines 529-530):

      - `edgeOutputName Edge { output = Nothing }` and
        `edgeOutputName Edge { output = Just (OPack _ wc _) }` need
        a new third arm or to be replaced with list-walking logic.
      - Multi-event edges need a label-rendering decision. Three
        candidate strategies:
        (a) Join wire-constructor names with `; ` separator in the
            edge label: `cmd / e1; e2`.
        (b) Multi-line label using Mermaid's `<br/>` syntax.
        (c) Synthesise anonymous intermediate nodes in the diagram
            and keep one wire-name per arrow (matches the AST but
            diverges from the user's vertex enum, which the
            MasterPlan flagged as dimension-2 concern).
        M1's design note must commit to one. Reflect the choice in
        `test/Keiki/Render/MermaidSpec.hs`.

      **Builder cascade.** Edit `src/Keiki/Builder.hs`:
      - `PartialEdge`'s output accumulator (currently a single optional
        `OutTerm`) must hold a list. Re-architect the type-level state
        accordingly — likely the simplest path is keep the `peOutput`
        field as `[OutTerm rs ci co]` (snoc-list under append) and let
        the finalize step pass it directly to the `Edge.output`
        constructor.
      - `emit` semantics: appends to `peOutput` rather than failing or
        replacing. A single `emit` produces a length-1 list (today's
        letter behavior). Two `emit`s in one block produce a length-2
        list. The previously-implicit "one emit per onCmd" rule
        becomes "any number of emits, accumulated in declaration
        order."
      - `noEmit`: documented as "produce a length-0 output (ε-edge)";
        same semantics as before but explicit about the empty list.
        Mixing `noEmit` with `emit` in the same block is rejected at
        finalize time (or compile time via the type-level state if
        feasible).
      - **`chainTo` and `peChain` retirement decision (pending).**
        The shipped builder has `chainTo` (lines 168, 439-444) and
        the `peChain` snoc-list machinery (lines 245-260) plus
        `EdgeListAcc { elaMain, elaChain }`. With multi-`emit` now
        legal, `chainTo`'s motivating use case (compress chain
        authoring through an intermediate vertex) collapses into
        "use two `emit`s in one block." Three options for the
        verb:
        (i)  **Remove `chainTo`, `peChain`, and `EdgeListAcc`.**
             Cleanest end state. All current `chainTo` callers in
             jitsurei migrate to multi-`emit`. Builder simplifies
             back to its pre-EP-20-M5 shape with multi-`emit`
             added.
        (ii) **Keep `chainTo` as legacy** for the "true internal
             control vertex" case — a vertex that exists for
             modelling reasons (e.g., a `UnderReview` state with
             approve/decline branches) not as a multi-event
             scaffold. The line is blurry in practice; this
             carries documentation cost.
        (iii) **Keep `chainTo`, deprecate, schedule removal in a
             follow-up plan.** Smoothest migration; deferred
             cleanup.
        See Decision Log "Builder verb retirement strategy."
      - Update `Keiki.Builder`'s haddock and the spike module
        `test/Keiki/BuilderSpike.hs` to reflect the new semantics.
      - Update `test/Keiki/BuilderSpec.hs` to add tests for two
        `emit`s producing a length-2 list.

      Tests should still pass with single-emit blocks behaving
      identically (length-1 list = today's `[Just o]` semantics).

- [x] **Milestone 3 — `InFlight` and `applyEvents`.** (2026-05-16)
      Completed. Concrete changes:

      - Added `data InFlight s co = Settled !s | InFlight !s ![co]`
        to `Keiki.Core` (exported via the new
        "Streaming-replay state wrapper" section in the export list).
      - Added `applyEventStreaming :: ... -> InFlight s co -> RegFile
        rs -> co -> Maybe (InFlight s co, RegFile rs)` with the two
        arms specified in the design note §4:
          - `Settled s`: find the unique edge whose output's head
            inverts via `solveOutput`; commit; evaluate the tail
            against the recovered `(regs, ci)`; wrap into `InFlight`
            if tail is non-empty, otherwise `Settled (target e)`.
          - `InFlight s (q : rest)`: equality-check against the head
            of the queue; pop on match; transition to `Settled` when
            the queue empties; return `Nothing` on mismatch or empty
            queue.
        Carries an `Eq co` constraint for the queue check.
      - **`applyEvent` retained letter-only** per the Decision Log
        entry ("M3 keeps the existing applyEvent letter-only
        signature"). This avoids forcing `Keiki.Acceptor`,
        `Decider.toDecider.evolve`, and `bench/Bench.hs` to wrap
        every state in `Settled`.
      - **Widened `applyEvents`'s implementation** to use streaming
        internally: lifts the start state to `Settled`, folds
        `applyEventStreaming`, unwraps a final `Settled` (chunks
        that end mid-flight return `Nothing`). Signature unchanged
        from EP-20 M2's letter version. New constraint: `Eq co`.
      - **Refactored `reconstitute`** to delegate to `applyEvents`
        from the transducer's initial state. Acquires `Eq co`.
      - Added `test/Keiki/CoreInFlightSpec.hs` (10 tests) with a
        minimal synthetic 2-vertex transducer whose one edge has
        `output = [Started n, Echoed n]` (length-2). Asserts:
        omega returns the full list; step's third component is the
        list; chunked `applyEvents` round-trips; truncated chunks
        reject; out-of-order chunks reject; `applyEventStreaming`
        threads `Settled → InFlight → Settled` correctly; streaming
        and chunked agree on final state.

      **Validation**: `cabal test all --test-show-details=direct`
      reports **334 examples, 0 failures, 1 pending** (196 + 91 + 40
      + 7); previous 324 baseline + 10 new InFlight specs.

          data InFlight s co = Settled !s | InFlight !s ![co]
            deriving (Eq, Show)

      Refactor `applyEvent` to operate on `InFlight`:

          applyEvent
            :: BoolAlg phi (RegFile rs, ci)
            => SymTransducer phi rs s ci co
            -> InFlight s co -> RegFile rs -> co
            -> Maybe (InFlight s co, RegFile rs)

      Two cases:

      1. `Settled s` — walk outgoing edges; for each, walk its `output`
         list looking for the *first* `OutTerm` that inverts to a valid `ci`
         via `solveOutput` against the observed `co`; if the edge's output
         list has further entries (length > 1), commit to that edge,
         recover the input, run the update, return
         `(InFlight (target e) restOfList, regs')` where `restOfList` is
         the *evaluated* tail (events to expect next on the chain). If
         length == 1, return `(Settled (target e), regs')` directly. If
         length == 0 (ε-edge), the edge is unreachable on the event side
         (you can't observe an ε-edge from outside), so it's filtered.

      2. `InFlight s (co1 : rest) regs` — verify the head of the queue
         matches the observed `co`; if so, return `(InFlight s rest, regs)`
         (no register update — register updates already happened on the
         transition into `InFlight`). If `rest` becomes `[]`, return
         `(Settled s, regs)`. If the head doesn't match, return `Nothing`
         (replay failure).

      Add `applyEvents :: SymTransducer phi rs s ci co -> (s, RegFile rs)
      -> [co] -> Maybe (s, RegFile rs)` that drives a chunk of events
      corresponding to one logical command and returns the unwrapped
      result. Implementation: lift the start state to `Settled`, fold
      `applyEvent` over the events, expect `Settled` on completion.

      Refactor `reconstitute` to call `applyEvents` per-command-chunk if
      the runtime supplies command boundaries; otherwise iterate
      `applyEvent` event-by-event over `InFlight`. The existing single-arg
      `reconstitute :: ... -> [co] -> Maybe (s, RegFile rs)` is preserved
      by the latter path; document that mid-replay it threads through
      `InFlight` invisibly.

      Acceptance: a new spec
      `test/Keiki/Examples/UserRegistrationGSMSpec.hs` asserts that
      `applyEvents` round-trips the canonical command sequence (after
      M7's UserRegistration migration), and that a deliberately
      malformed event sequence (e.g. `RegistrationStarted` followed by an
      out-of-order event) returns `Nothing`.

- [x] **Milestone 4 — Strengthen `checkHiddenInputs`.** (2026-05-16)
      Completed. Replaced the per-`OPack` independent check with a
      **union-coverage** check: for each edge with a non-empty output
      list, group OPacks by `InCtor` name (via `icName`), union the
      slots visited by every `OPack` in each group, and flag any
      `InCtor` whose slot list is not fully covered by its union.
      Length-1 (letter) edges behave identically to the legacy check.
      Length-2+ edges no longer trip on a single OPack's partial
      coverage when a sibling OPack on the same edge supplies the
      missing slots — the joint coverage is what matters.

      Added `test/Keiki/CoreHiddenInputsGSMSpec.hs` (3 tests):
      - `goodUnion`: length-2 edge with OPacks visiting {a,b} and
        {b,c} respectively — union is {a,b,c} = full coverage. No
        warning fires.
      - `badUnion`: length-2 edge with OPacks visiting {a,b} and {a} —
        union is {a,b}, leaving slot @c@ unrecovered. Warning fires
        naming "Begin" and "c".
      - `badSingle`: length-1 edge that visits only slot @a@ from
        `Begin`. Confirms the legacy single-OPack check still fires
        (missing slots b and c) — union is a strict generalisation.

      **Validation**: `cabal test all` reports **337 examples, 0
      failures, 1 pending** (199 + 91 + 40 + 7); previous 334 +
      3 new M4 specs.
      `src/Keiki/Core.hs:701-770`. The current check fires per-edge with
      one `OutTerm` (the `Just o` arm) or fires on ε-edges that read
      input. Update to:

      - Iterate the edge's `output` list as a whole.
      - Compute the union of slots visited by `gatherInpEntries` across
        every `OutTerm` in the list, against every distinct `InCtor`
        named in any of the `OPack`s.
      - For each `InCtor` named in any `OPack` of the list, compute the
        slots of that `InCtor` not visited by the union. Flag if the
        guard or update reads input via that `InCtor` and the union
        leaves any of its slots unrecovered.
      - For length-0 (`output = []`) edges: existing logic preserved
        (flag if `update` reads input, since recovery is impossible).

      Add a test spec
      `test/Keiki/CoreHiddenInputsGSMSpec.hs` that builds a deliberately
      ill-formed multi-event edge — one where `update` reads
      `confirmCode` but neither `OutTerm` in the list visits it — and
      asserts `checkHiddenInputs` flags it with a precise reason.

- [x] **Milestone 5 — Adapt `Keiki.Decider` and retire `toMultiDecider`.**
      (2026-05-16) Completed. Concrete changes:

      - `src/Keiki/Decider.hs`: **deleted** `toMultiDecider`,
        `DriverConfig`, `driveDecide` (and the chain-replay path).
        Restructured docstring to retire the "at most one event per
        command" caveat — with EP-19 widening, `decide` returns the
        full event list directly via `omega`.
      - Added `evolveStreaming :: s_streaming -> e -> Maybe
        s_streaming` field to the `Decider` record, threaded through
        the new `s_streaming` type parameter (instantiated to
        `(InFlight s co, RegFile rs)` by `toDecider`).
      - `toDecider`: `decide` lifts `omega` directly; `evolve`
        retains letter-only semantics with defensive fallback;
        `evolveStreaming` calls `applyEventStreaming` directly.
        Acquired `Eq co` constraint.
      - **Deleted** `userRegDriverConfig` from
        `jitsurei/src/Jitsurei/UserRegistration.hs` and
        `test/Keiki/Fixtures/UserRegistration.hs`.
      - **Deleted** `loanApplicationDriverConfig` from
        `jitsurei/src/Jitsurei/LoanApplication.hs`.
      - **Deleted** EP-20-aligned spec files:
        `test/Keiki/DeciderMultiSpec.hs`,
        `jitsurei/test/Jitsurei/UserRegistrationMultiSpec.hs`,
        `jitsurei/test/Jitsurei/LoanApplicationMultiSpec.hs`.
        Removed from `keiki.cabal`/`jitsurei/jitsurei.cabal` and
        from `test/Spec.hs`/`jitsurei/test/Spec.hs`.
      - `jitsurei/test/Jitsurei/LoanWorkflowSpec.hs`: dropped the
        `toMultiDecider` import and inlined the 2-event chain
        `[EmploymentChecked, ApplicationApproved]` directly in
        `recordEmploymentTipsApproval`. (The integration test
        cares about the *events*, not how they're produced.)
      - `test/Keiki/DeciderSpec.hs`: added the new `s_streaming`
        parameter to the `runRound` type annotation; added two
        `evolveStreaming` tests (Settled initial → Settled
        Registering on `RegistrationStarted`; Settled Confirmed →
        Settled Deleted on `AccountDeleted`).

      **Validation**: `cabal test all` reports **331 examples, 0
      failures, 1 pending** (198 + 86 + 40 + 7). Compared with M4
      (337), the net delta is `-6` from deleted *Multi specs and
      `+0` net inside DeciderSpec (2 new tests, but the multi-
      spec contributed ~5).

      - Update the docstring to retire the "at most one event per
        command" caveat (currently lines 26-45 mention
        `toMultiDecider` drives chains; with widened `Edge.output`
        the chain happens inside one edge).
      - The `decide` field's signature is unchanged (`c -> s -> [e]`),
        but its lift now wraps `omega t s regs ci :: [co]` directly
        rather than `Just co → [co], Nothing → []`. The body becomes
        `decide = \cmd (s, regs) -> omega t s regs ci`.
      - The `evolve` field's signature is unchanged. Internally it must
        call `applyEvents` (per-command chunk replay) rather than the
        old `applyEvent`, since events for one command may be a chunk.
        But `evolve :: s -> e -> s` operates one event at a time; the
        natural fix is to expose two evolve directions:

            evolveStreaming :: SymTransducer ... -> InFlight s co -> RegFile rs -> e
                            -> (InFlight s co, RegFile rs)

        and keep `evolve :: s -> e -> s` working only on `Settled` (mid-
        chain replay returns the input state unchanged with a deferred
        warning, or — better — refuses to compile by exposing the
        wrapped state in the type).

        Decision deferred to implementation: prefer exposing
        `evolveStreaming` as a separate field on `Decider` and keeping
        the old `evolve` working for length-0/1 commands only.

      - **`toMultiDecider` + `DriverConfig` retirement (pending).**
        These are shipped by EP-20 (`src/Keiki/Decider.hs:51,
        138, 168, 183-188`). With first-class multi-event edges,
        `decide` directly returns the full event list and
        `toMultiDecider` has no remaining job *for the multi-event
        case*. But `toMultiDecider` was also marketed as the
        "drive through any user-declared internal vertex" façade,
        which is a slightly larger feature than just multi-event
        bundling. Three options:
        (i)  **Remove** `toMultiDecider`, `DriverConfig`,
             `chainAdvanceCommand`, and the `Decider.evolve`
             chain-replay path. Update `test/Keiki/DeciderMultiSpec.hs`
             to assert against the widened `decide` instead, or
             delete it entirely. Cleanest end state.
        (ii) **Keep deprecated** for one release; schedule removal
             in a follow-up plan. Smoothest migration.
        (iii) **Repurpose** `toMultiDecider` as the "user-declared
             internal vertex" façade only — distinct from the
             multi-event case. This requires documenting the
             distinction clearly and updating `userRegDriverConfig`
             usage (which currently models a multi-event command
             via state refinement). Most honest but most prose
             cost.
        See Decision Log "EP-20 decider façade retirement."

      Acceptance: existing
      `test/Keiki/DeciderSpec.hs` continues to pass after rebuild. Add
      one new test asserting that `decide` over a multi-event edge
      returns the full `[e]` list of length 2. Update or remove
      `test/Keiki/DeciderMultiSpec.hs` per the retirement choice.

- [x] **Milestone 6 — Adapt `Keiki.Composition`: library-side chain
      expansion.** (2026-05-16) Completed. Concrete changes to
      `src/Keiki/Composition.hs`:

      - Added `data PartialPath rs1 rs2 ci1 co s2 = forall w.
        PartialPath ...` to carry the accumulating composite-edge
        state through the chain expansion. The existential `w`
        closes over the chained `Update`'s slot-set index as
        `UCombine` extends it per step.
      - `composeEdge` now handles three cases:
          - `[]` → ε-edge (unchanged from M2).
          - `[o1]` → letter `productEdge` (unchanged from M2).
          - `mids` (length-N) → run `expandPaths mids (initialPath
            e1 s2)`; convert each completed path to a composite
            edge via `finalizePath`. The cartesian product over t2
            edges per intermediate state produces multiple
            composite edges; unsatisfiable substituted guards
            (`substPred (PInCtor X) Y ≡ PBot` for mismatched
            ctors) ensure only the "live" path actually fires at
            `omega`/`delta`/`step` time.
      - Helpers `initialPath`, `expandPaths`, `stepPath`,
        `finalizePath` are local to `compose`'s `where` block.
        `stepPath` pattern-matches on the t2 edge's update to
        bring its existential `w2` into scope; the chained
        `UCombine`'s `w` is re-existentially closed when wrapping
        back into `PartialPath`.
      - The `liftLOutAlt`/`liftROutAlt` alternative-composition
        arms already use list-fmap (added in M2) and produce
        length-preserving outputs; no further M6 changes needed
        for `alternative` itself — its arms are letter-shaped
        because `alternative`'s composite outputs one Left/Right-
        wrapped event per input arm.

      Added `test/Keiki/CompositionMultiEventSpec.hs` (3 tests):
      - synthetic t1 = one vertex, one length-2 edge emitting
        `[MidA n, MidB n]` from `T1Trigger n`.
      - synthetic t2 = one vertex, two edges (one per MidA/MidB),
        each emitting one Echo.
      - asserts: the composite produces 4 edges (2×2 cartesian
        product); every edge has output of length 2; `omega` on
        `T1Trigger 42` yields `[EchoA 42, EchoB 42]` (the unique
        live path); `applyEvents` round-trips the 2-event chunk
        to the initial composite vertex.

      **Validation**: `cabal test all` reports **334 examples, 0
      failures, 1 pending** (201 + 86 + 40 + 7); previous 331 + 3
      new composition specs.
      (`composeEdge` is now around lines 700-870 with the new
      alternative / liftLOutAlt / liftROutAlt cases shipped by
      EP-29 et al.). The MasterPlan #7's Tradeoff Analysis
      dimension 4 (lines 282-333) flagged the original plan's
      framing — "concatenate output lists with `substOut` applied
      to each" — as understating a real difficulty:

      > A length-2 first-edge produces two mid-symbols `[o1a,
      > o1b]`; the second transducer steps on `o1a` from state
      > `s2`, transitions to some `s2'`, then must step on `o1b`
      > from `s2'`. A single composed edge from `(s1, s2)`
      > cannot express this — its output list reflects T2's
      > behaviour from `s2` for both events, but T2's state
      > changes between events.

      Two viable strategies; the plan must commit to one in M1's
      design note:

      - **Strategy A — library-side chain expansion during
        composition.** `composeEdge` internally expands a length-N
        first-edge into N letter edges connected through synthetic
        composite-state intermediates `(s1, s2)` → `(s1, s2')` →
        ... → `(target e1, s2_final)` for the duration of
        composition, then re-collapses the resulting chain into
        one length-N composite edge if the user composes
        further. The synthetic intermediates are not visible in
        the composite's `Vertex` type; they live inside
        composite-state `s2_i` values that the existing `Composite`
        machinery (in `Keiki.Composition`) already manages. This
        is "state-refinement under the hood" — invisible to
        users authoring multi-event edges, but it is the
        library's job to keep the composition closed.
      - **Strategy B — restrict the composable class.** A
        multi-event edge composes only when every mid-symbol in
        its output list triggers the same downstream edge in T2
        from any intermediate composite state. This invariant is
        type-system-checkable in narrow cases (e.g., when T2 is
        a single-vertex transducer) but generally requires a
        run-time check at composition. Less expressive; surfaces
        the difficulty to the user.

      Recommended in this plan: Strategy A. Rationale: keeps the
      user model clean (`compose` always succeeds when the
      mid-symbol algebra matches); the library absorbs the
      state-refinement-on-composition cost; the composite's
      edges remain length-N edges and the GSM property is
      preserved end-to-end. The implementation cost is modest —
      `Composite`'s state machinery already encodes pair-of-state
      pairs.

      Implementation steps (under Strategy A):

      - For each `OutTerm` in `output e1`, find the corresponding
        edge in the second transducer whose guard accepts that
        mid-symbol, and compose: substitute `e1`'s `OutTerm` for
        the second edge's input reads using the existing
        `substOut` machinery.
      - For length-1 `output e1`, the behavior is identical to
        today's letter composition.
      - For length-0 (ε-edge in the first transducer), the
        composed edge has `output = []`.
      - For length-2+ (a multi-event edge), expand internally
        as described above, threading T2's state through
        intermediate symbols, then re-collapse into a length-N
        composite edge in the result.

      Audit also the new alternative-composition arms
      (`liftLOutAlt`, `liftROutAlt` at lines 846, 864) — these
      ship after the original plan was drafted and need the
      same widening treatment.

      Acceptance: `test/Keiki/CompositionSpec.hs`,
      `test/Keiki/CompositionAlternativeSpec.hs`, and
      `test/Keiki/CompositionFeedback1Spec.hs` continue to pass.
      Add one new test composing a two-aggregate pipeline where
      the first aggregate has a multi-event edge; assert the
      composed edge produces the expected concatenated event
      list and that the composite's reconstitute round-trips a
      log of length N + M correctly. Add a stress test where
      both transducers in the pipeline have multi-event edges to
      exercise the chain-expansion path.

- [ ] **Milestone 7 — Worked example: collapse UserRegistration's
      `Registering` (plus full `jitsurei` cascade).** Edit
      `jitsurei/src/Jitsurei/UserRegistration.hs` (note the
      package moved from `src/Keiki/Examples/` to `jitsurei/` after
      the original plan was drafted). The file now declares the
      transducer **three** times on master:
      - `userReg` (lines 284-359) — canonical builder form via
        `B.buildTransducer PotentialCustomer emptyRegs (...)`.
        Two `from` blocks chained through `Registering` with a
        synthetic `Continue` command.
      - `userRegChained` (lines 360-400) — builder form using
        `B.chainTo` to express the same chain in one `onCmd`
        block.
      - `userRegAST` (lines 400-470) — preserved AST form for
        cross-form equivalence testing
        (`jitsurei/test/Jitsurei/UserRegistrationBuilderSpec.hs`,
        `UserRegistrationChainedSpec.hs`).

      Both must be edited:

      - Remove the `Registering` constructor from the `Vertex` enum.
        Drops constructor count from 5 to 4.
      - Remove the `Continue` constructor from `UserCmd`. Drops
        constructor count from 5 to 4.
      - In the `deriveAggregateCtors` and `deriveWireCtors` invocation
        spec lists, remove the `Continue` entry.
      - In `userReg`'s builder block, replace the two
        `from PotentialCustomer …; goto Registering` and
        `from Registering …; goto RequiresConfirmation` blocks with
        one block containing two consecutive `emit` calls (now legal
        per M2's widened builder) and `goto RequiresConfirmation`.
      - In `userRegAST`'s `userRegASTEdges` function, replace the two
        `Edge` literals (`PotentialCustomer → Registering /
        RegistrationStarted` and `Registering → RequiresConfirmation /
        ConfirmationEmailSent`) with one length-2 edge:

            PotentialCustomer ->
              [ Edge
                  { guard  = isStart
                  , update = ... (same as today)
                  , output =
                      [ pack inCtorStart wireRegistrationStarted
                          (OFCons (inpStart #email)
                            (OFCons (inpStart #confirmCode)
                              (OFCons (inpStart #at) OFNil)))
                      , pack inCtorStart wireConfirmationEmailSent
                          (OFCons (inpStart #email) OFNil)
                      ]
                  , target = RequiresConfirmation
                  }
              ]

      - Update the `deriveView` spec list to drop the `Registering`
        entry. The `SUserVertex`/`UserView`/`userView` triple loses one
        constructor.

      Cascade-fix the jitsurei test suite:
      `jitsurei/test/Jitsurei/UserRegistrationSpec.hs`,
      `UserRegistrationViewSpec.hs`,
      `UserRegistrationBuilderSpec.hs`,
      `UserRegistrationSymbolicSpec.hs`,
      `UserRegistrationMultiSpec.hs` (EP-20-aligned; refactor or
      delete per Decision Log "EP-20 spec retirement"),
      `UserRegistrationChainedSpec.hs` (depends on `chainTo`
      retention), `UserRegistrationV0Spec.hs`. The
      cross-form equivalence specs (Builder/Chained) must
      continue to pass if the corresponding form is kept; both
      forms now describe the same length-2 edge.

      **Cascade across other jitsurei aggregates.** Even
      aggregates that do not collapse intermediates today are
      affected by the AST widening:

      | Aggregate file | Touch type |
      |---|---|
      | `jitsurei/src/Jitsurei/UserRegistrationV0.hs` | 6 AST sites; replace `Just`/`Nothing` |
      | `jitsurei/src/Jitsurei/EmailDelivery.hs` | 1 AST site (builder dominant); replace |
      | `jitsurei/src/Jitsurei/Loan.hs` | builder-only; affected via builder cascade |
      | `jitsurei/src/Jitsurei/LoanApplication.hs` | 11 AST sites + `chainTo` callers; cascade-fix + retire-or-keep chained variant |
      | `jitsurei/src/Jitsurei/LoanWorkflow.hs` | composition surface; re-test post-M6 |
      | `jitsurei/src/Jitsurei/OrderCart.hs` | 12 AST sites; replace `Just`/`Nothing` |
      | `jitsurei/src/Jitsurei/CoreBankingSync.hs` | builder-only; affected via builder cascade |

      `LoanApplication` has its own `chainTo`-based multi-event
      command (`loanAppChained`, lines 776-820); the same
      collapse-into-length-N-edge treatment applies as for
      UserRegistration. Decide per aggregate whether to also
      collapse other multi-event commands (e.g.
      `LoanApplication.UnderReview` approve/decline branches —
      these are *not* multi-event commands per se; they are
      genuine branching, so they stay as separate edges).

      Add `jitsurei/test/Jitsurei/UserRegistrationGSMSpec.hs`:

      - One test asserts `decide` on `StartRegistration` returns a
        2-element event list `[RegistrationStarted ..,
        ConfirmationEmailSent ..]` in that order.
      - One test asserts `applyEvents` round-trips a 5-event canonical
        log to the expected `(s, RegFile rs)` final state.
      - One test asserts the chunked `applyEvents` and the streaming
        `applyEvent` over `InFlight` produce identical final states.

      Wire the new spec into `jitsurei/test/Spec.hs` and
      `jitsurei/jitsurei.cabal`. Also add a parallel
      `LoanApplicationGSMSpec.hs` for the collapsed `loanAppChained`.

      **Sibling-package sanity check.** `keiki-codec-json` and
      `keiki-codec-json-test` operate on `RegFile`, not `Edge`;
      a `git grep -E 'Edge\b|OutTerm|applyEvent|InFlight'` over
      their source/test trees shows zero hits, so they are
      insulated. Re-run `cabal test all` to confirm post-cascade.

      Acceptance: full test suite passes (target: 337 baseline
      minus N (EP-20 specs retired) plus M (new GSM specs); see
      Validation section). Line counts: `Jitsurei.UserRegistration`
      drops by ~80-100 lines (one builder block, one AST edge,
      one builder-chained variant, one vertex constructor, one
      command constructor, two TH spec entries, plus
      `userRegDriverConfig` if retired). `Jitsurei.LoanApplication`
      similarly drops where multi-event commands are collapsed.

- [ ] **Milestone 8 — Documentation update + commit.** Edit:

      - `docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`
        line 974 ("the multi-event document's three approaches still
        apply (state refinement is the cleanest under the symbolic-
        register formalism, as the User Registration example shows)")
        — replace with: "Multi-event commands are first-class via the
        widened `Edge.output :: [OutTerm rs ci co]` and the `InFlight`
        replay wrapper. State refinement is no longer the canonical
        path; aggregates declare multi-event edges directly."
      - `docs/research/multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md`'s
        Recommendation section (currently "Default to Approach 3") —
        replace with: "Approach 2 (GSM with library expansion) is the
        canonical path. The library widens `Edge.output` to a list and
        ships `applyEvents` for chunk replay; users author multi-event
        edges directly without state refinement."

      Stage and commit per the Concrete Steps section.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered
during implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- **Decision**: `Edge.output` widens to a list, not a `Foldable f =>
  f (OutTerm rs ci co)` with a parameter for the carrier shape.
  **Rationale**: a parameterized carrier complicates pattern matching
  and analysis without clear benefit. List is the simplest shape that
  admits 0, 1, or N elements; SBV translation, `solveOutput`, and
  `checkHiddenInputs` all walk lists naturally.
  **Date**: 2026-05-02

- **Decision**: `InFlight s co` is exposed in `applyEvent`'s return
  type, not hidden inside an opaque newtype.
  **Rationale**: streaming replay through a length-2+ edge intrinsically
  observes an intermediate state. Hiding it would force the API to
  either chunk events for the caller (fragile) or keep mid-replay
  details opaque (loses replay-step granularity). Exposing it is honest
  and the wrapper is trivially deconstructable for callers that only
  ever produce length-0/1 edges.
  **Date**: 2026-05-02

- **Decision**: `evolve :: s -> e -> s` on `Keiki.Decider.Decider` is
  preserved with length-0/1 semantics; multi-event chunked replay is
  exposed via a new `evolveStreaming :: InFlight s co -> RegFile rs -> e
  -> (InFlight s co, RegFile rs)` field.
  **Rationale**: backward-compatible for callers who do not author
  multi-event edges. The new field's signature explicitly carries
  `InFlight` so multi-event-replay-aware callers cannot accidentally
  use the unwrapped form.
  **Date**: 2026-05-02

- **Decision**: Conditional output lists (where the list shape depends
  on the input value) are out of scope. Aggregates that need
  conditional emission (e.g., `syncImportedProperty`'s 12 conditional
  events) express each conditional event as a separate edge with a
  disjoint guard, not as a runtime-conditional `[OutTerm]`.
  **Rationale**: keeping `output :: [OutTerm rs ci co]` a static list
  preserves per-edge `checkHiddenInputs` decidability. Conditional
  emission via guards is the existing pattern and remains correct.
  **Date**: 2026-05-02

- **Decision**: The widening cascades into `Keiki.Builder` (Plan 15's
  module). M2's scope expands to include the builder's internal
  accumulator and `emit`/`noEmit` semantics; M7's scope expands to
  include both the builder-form and AST-form aggregates.
  **Rationale**: Plan 15 shipped on 2026-05-02 (after this plan was
  drafted) with `Keiki.Builder` as the canonical authoring surface.
  Both example aggregates are now in builder form. Widening the AST
  without updating the builder would leave the builder unable to
  express multi-event edges, which would defeat the purpose of EP-19.
  **Date**: 2026-05-02

- **Decision**: Plan reopened under reconsideration after being
  marked Cancelled (2026-05-02). EP-20 (state-refinement
  ergonomics) shipped end-to-end and is currently the canonical
  multi-event path on master; this plan now proposes to replace it
  with the GSM-widening path.
  **Rationale**: The user reports (2026-05-16) that the downstream
  surface built on top of `Keiki.Core` (the `jitsurei` sibling
  package's ~8 aggregates, `Keiki.Profunctor`'s Arrow/Strong/Choice
  instances, `Keiki.Render.Mermaid`'s diagram generation, future
  consumer packages) has grown to the point where a façade
  (`toMultiDecider`) is no longer sufficient — first-class
  multi-event support is needed at the AST level so every
  consumer interprets multi-event commands the same way without
  per-consumer wiring. The MasterPlan #7's retrospective
  Tradeoff Analysis (2026-05-02) already acknowledged EP-19's
  wins on authoring (dimension 1), cognitive count (dimension 2),
  and state-space economy (dimension 3); the EP-20 selection
  rested mainly on composition (dimension 4) and migration
  optionality (dimension 5). Dimension 5's "EP-20 → EP-19 is
  recoverable" claim is being exercised now while the surface
  is still small enough to migrate; dimension 4's concern is
  addressed by M6's commitment to Strategy A (library-side
  chain expansion during composition).
  **Implication**: MasterPlan #7 must be updated — EP-19's
  status flips from Cancelled to In Progress; EP-20's status
  flips from Complete to Superseded by EP-19 (with the shipped
  surface retired per the next Decision Log entry).
  **Date**: 2026-05-16

- **Decision**: EP-20 surface — **full removal in the same change**.
  Drop `toMultiDecider`, `DriverConfig`, `chainAdvanceCommand`,
  the chain-replay path in `Keiki.Decider.evolve`, `chainTo`,
  `peChain`, `EdgeListAcc { elaMain, elaChain }` and revert to a
  single `[Edge]` accumulator in `Keiki.Builder`,
  `userRegDriverConfig`, `userRegChained`, `loanAppChained`, and
  the EP-20-aligned specs (`test/Keiki/DeciderMultiSpec.hs`,
  `jitsurei/test/Jitsurei/UserRegistrationMultiSpec.hs`,
  `UserRegistrationChainedSpec.hs`,
  `LoanApplicationMultiSpec.hs`,
  `LoanApplicationChainedSpec.hs`).
  **Rationale**: cleanest end state; the GSM-widened core
  expresses multi-event behaviour directly, leaving no
  motivating use case for the façade or the `chainTo` verb.
  Keeping deprecated surface would impose a second
  multi-event idiom on every downstream package; folding
  retirement into the same PR means jitsurei's aggregates
  end up in their final canonical shape with no later
  cleanup cycle.
  **Implementation impact**: M5 removes the façade
  unconditionally; M2's Builder cascade removes
  `chainTo`/`peChain`/`EdgeListAcc`; M7 removes the
  driver-config / chained-variant declarations from each
  jitsurei aggregate and deletes the EP-20-aligned specs.
  **Date**: 2026-05-16

- **Decision**: Multi-event composition (M6) — **library-side
  chain expansion**. `composeEdge` internally expands length-N
  first-edges into N letter edges through synthetic
  composite-state intermediates `(s1, s2)` → `(s1, s2')` → … ,
  threading T2's state across each mid-symbol, then re-collapses
  the resulting chain into one length-N composite edge in the
  result.
  **Rationale**: keeps `compose` total — the user never sees a
  composition failure mode tied to multi-event-edge shape — and
  preserves the GSM property end-to-end at the composite level.
  Resolves the MasterPlan #7 dimension-4 critique
  (multi-event composition is fundamentally non-local) without
  surfacing the difficulty to authors. The `Composite` state
  machinery already encodes pair-of-state pairs, so the
  implementation cost is modest.
  **Implementation impact**: M6 implements the chain-expansion
  helper inside `Keiki.Composition` and recurses on the
  expanded chain for each mid-symbol. The composite's edges
  remain length-N edges (no synthetic vertices leak into the
  composite's `Vertex` type).
  **Date**: 2026-05-16

- **Decision**: Mermaid label rendering for length-N edges —
  **separator for length-2, multi-line for length-3+**. The
  `edgeOutputName`/label-formatting function inspects the
  output list length:
  - length-0: no label suffix beyond `cmd /` (ε-edge today).
  - length-1: `cmd / e1` (today's letter behaviour).
  - length-2: `cmd / e1; e2` (compact, readable inline).
  - length-3+: `cmd / e1<br/>e2<br/>e3<br/>…` (Mermaid's
    `<br/>` syntax keeps the diagram readable as event
    counts grow).
  **Rationale**: keeps the common case (length-1/2) compact
  without exploding the diagram on rare length-3+ commands;
  deterministic switchover so renders are reproducible;
  avoids the anonymous-intermediate-node strategy that
  would diverge from the user's `Vertex` enum (MasterPlan
  #7 dimension-2 concern).
  **Implementation impact**: M2's Mermaid cascade implements
  the switchover; `test/Keiki/Render/MermaidSpec.hs` adds
  goldens for length-2 and length-3 edges.
  **Date**: 2026-05-16

- **Decision**: M3 keeps the existing `applyEvent :: ... -> s ->
  RegFile rs -> co -> Maybe (s, RegFile rs)` letter-only signature
  and adds a new `applyEventStreaming :: ... -> InFlight s co ->
  RegFile rs -> co -> Maybe (InFlight s co, RegFile rs)` for the
  multi-event streaming case. The plan's Interfaces section
  originally specified replacing `applyEvent`'s signature; this
  refinement keeps existing callers (`Keiki.Acceptor.outputAcceptor`,
  `Keiki.Decider.toDecider.evolve`, `bench/Bench.hs`, tests) source-
  compatible while still exposing the InFlight-aware replay path
  needed for length-2+ edges.
  **Rationale**: the letter-only callers genuinely don't need
  `InFlight` — they handle length-0/1 edges only. Widening the public
  signature would force every caller to wrap/unwrap `Settled` even
  when they cannot encounter `InFlight` (Acceptor's state carrier
  doesn't have a sensible interpretation for mid-chain replay; the
  Decider's `evolve :: s -> e -> s` was already letter-only by
  design — M5's added `evolveStreaming` is the InFlight surface).
  **Implementation impact**: M3 adds `InFlight`, `applyEventStreaming`,
  and widens `applyEvents`'s implementation to use streaming
  internally; `applyEvent`'s signature is unchanged. M5's
  `Decider.evolveStreaming` calls `applyEventStreaming` directly.
  **Date**: 2026-05-16

- **Decision**: Factor the EP-20 surface deletion across M2/M5/M7 by
  *dependency*, not by file.
  - **M2** (AST widening): delete `chainTo`, `ChainPrefix`,
    `EdgeListAcc`, and `peChain` from `Keiki.Builder`. Delete the
    direct callers `userRegChained` (jitsurei UserRegistration) and
    `loanAppChained` (jitsurei LoanApplication). Delete the
    Chained-form test specs (`UserRegistrationChainedSpec`,
    `LoanApplicationChainedSpec`).
  - **M5** (Decider retirement): delete `toMultiDecider`,
    `DriverConfig`, `chainAdvanceCommand`, plus
    `userRegDriverConfig` (jitsurei UR) and `loanAppDriverConfig`
    (jitsurei LA), plus the Multi-form test specs
    (`DeciderMultiSpec`, `UserRegistrationMultiSpec`,
    `LoanApplicationMultiSpec`).
  - **M7** (jitsurei migration): collapse the surviving canonical
    builder forms (`userReg`, `loanApp` etc.) to multi-`emit` and
    drop the `Registering`/`Continue` enum constructors and other
    state-refinement scaffolding.
  **Rationale**: `chainTo` (a builder verb) and `toMultiDecider`
  (a runtime façade) are *independent* parts of EP-20's surface;
  the only thing tying them together is the user-declared
  intermediate vertex. Deleting `chainTo` in M2 lets the AST
  widening proceed cleanly (no Maybe-shaped output anywhere) while
  preserving the `toMultiDecider`/`*DriverConfig` path intact for
  M5 to remove on its own schedule. This avoids a circular M2↔M7
  dependency (M2 cannot widen Builder's `peOutput` without either
  removing chainTo or maintaining a parallel Maybe-shape inside
  `ChainPrefix.cpOutput`; M7 cannot collapse jitsurei aggregates
  without the multi-`emit` semantics M2 introduces).
  **Implementation impact**: M2's commit footprint grows to ~10
  files (Core, Builder, Composition, Profunctor, Mermaid,
  jitsurei UR/LA AST sites and aggregates, two Chained specs,
  test fixtures); M5's footprint shrinks to Decider + Multi-form
  specs + driver-config declarations; M7's footprint shrinks to
  vertex/command collapse + new GSM specs.
  **Date**: 2026-05-16

- **Decision**: Tactical refresh of remaining plan sections
  (Plan of Work, Concrete Steps, Context and Orientation,
  Interfaces and Dependencies) is performed immediately in
  the same revision pass.
  **Rationale**: user requested the plan be ready to implement
  end-to-end before M0 begins, so all sections are aligned
  with the post-2026-05-02 master and the four strategic
  decisions committed above.
  **Date**: 2026-05-16



## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at
completion. Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

The keiki library lives at `/Users/shinzui/Keikaku/bokuno/keiki/`. The pure
core under `src/Keiki/` is a Haskell implementation of the symbolic-register
transducer formalism specified in
`docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`.
This plan modifies the AST and several derived operators; the reader needs to
understand the AST shape and the surrounding analyses before editing.

**The current AST.** `src/Keiki/Core.hs:455-461` defines the `Edge`
record as a GADT with an existential `w` in the `update` field
(the existential was introduced after this plan's original draft):

    data Edge phi rs ci co s where
      Edge
        :: { guard  :: phi
           , update :: Update rs w ci   -- existential w
           , output :: Maybe (OutTerm rs ci co)
           , target :: s
           }

`output = Nothing` is an ε-edge (transition with no observable event);
`output = Just o` produces exactly one event by evaluating `o`. The plan
widens `output` to `[OutTerm rs ci co]` so length-0 reproduces ε, length-1
reproduces today's letter behavior, and length-2+ admits multi-event
commands. The existential `w` is preserved unchanged.

**The operators built on `output`.** Three key operators consume the
field:

1. `omega :: SymTransducer phi rs s ci co -> s -> RegFile rs -> ci ->
   Maybe co` (line 569). Returns `Just co` for the unique active edge whose
   `output` is `Just o`. Widens to `[co]` returning the evaluated list of
   events, in declaration order.

2. `applyEvent :: SymTransducer phi rs s ci co -> s -> RegFile rs -> co ->
   Maybe (s, RegFile rs)` (line 605). Used by `reconstitute`. Currently
   walks outgoing edges, finds the unique edge whose `output = Just o`
   inverts via `solveOutput o regs co` to recover the input, runs the
   update, returns the new state. Widens to operate on `InFlight s co`
   (see M3): per-event replay through a multi-event edge passes through
   intermediate `InFlight` states.

3. `checkHiddenInputs :: ... -> [HiddenInputWarning]` (line 701). Walks
   every edge of every vertex, flags hidden inputs (cases where the
   guard/update reads input fields the output cannot recover). With the
   wider `output`, the check accumulates coverage across the edge's
   output list and flags any `InCtor` whose slots are not all visited.

**Existing call sites that touch `output`.** As of master 2026-05-16,
~69 sites span four packages. The example modules moved out of
`src/Keiki/Examples/` into the sibling package `jitsurei/` after
the plan's original draft; the AST-form `*ASTEdges` functions and
several new builder + AST aggregates now live there. M0 re-runs
`git grep` to confirm this enumeration before M2 begins:

    # keiki core
    src/Keiki/Core.hs:455-461       (Edge GADT declaration)
    src/Keiki/Core.hs (omega, step, applyEvent, applyEvents, checkHiddenInputs)
    src/Keiki/Composition.hs:726,756,846,864 (composeEdge + alternative arms)
    src/Keiki/Decider.hs:26-188     (docstring + toMultiDecider façade — retired in M5)
    src/Keiki/Builder.hs:235-260    (PartialEdge accumulator)
    src/Keiki/Builder.hs:168,439-444 (chainTo verb — retired in M2 Builder cascade)
    src/Keiki/Profunctor.hs:317,621,720,921,933,945 (firstEdge, rewriteEdge*, instance bodies — new since draft)
    src/Keiki/Render/Mermaid.hs:529-530 (edgeOutputName, label rendering — new since draft)

    # jitsurei sibling package
    jitsurei/src/Jitsurei/UserRegistration.hs (6 AST sites + userRegChained + userRegDriverConfig)
    jitsurei/src/Jitsurei/UserRegistrationV0.hs (6 AST sites)
    jitsurei/src/Jitsurei/LoanApplication.hs (11 AST sites + loanAppChained)
    jitsurei/src/Jitsurei/OrderCart.hs (12 AST sites)
    jitsurei/src/Jitsurei/EmailDelivery.hs (1 AST site; builder dominant)
    jitsurei/src/Jitsurei/Loan.hs (builder-only)
    jitsurei/src/Jitsurei/LoanWorkflow.hs (composition surface)
    jitsurei/src/Jitsurei/CoreBankingSync.hs (builder-only)

    # tests
    test/Keiki/Fixtures/{UserRegistration,EmailDelivery}.hs
    test/Keiki/{CoreSpec, CompositionSpec, CompositionAlternativeSpec,
              CompositionFeedback1Spec, SymbolicSpec, BuilderSpec,
              BuilderSpike, ProfunctorSpec, Render/MermaidSpec}.hs
    jitsurei/test/Jitsurei/{UserRegistration,LoanApplication,OrderCart,...}{Spec,BuilderSpec,...}.hs
    # EP-20-aligned specs (deleted by M5/M7):
    test/Keiki/DeciderMultiSpec.hs
    jitsurei/test/Jitsurei/{UserRegistration,LoanApplication}{Multi,Chained}Spec.hs

    # sibling packages — insulated, no edits required
    keiki-codec-json/{src,test} — zero hits on Edge/OutTerm/applyEvent
    keiki-codec-json-test/{src,test} — zero hits

The builder-form transducers (`userReg`, `emailDelivery`,
`loanApp`, etc.) construct edges via `B.buildTransducer` and
don't use the `output = Just/Nothing` syntax directly; they're
affected by the Builder cascade in M2 (multiple `emit` accumulates;
`chainTo` is deleted).

**Why an `InFlight` wrapper is needed.** `applyEvent` is invoked in two
different runtimes:

- *Chunk-replay runtime* — the runtime knows command boundaries (each
  command produced events `[e1; e2; e3]`; replay replays the chunk
  atomically). With command boundaries, replay can drive a multi-event
  edge as one logical step. `applyEvents :: ... -> [co] -> Maybe (s, RegFile
  rs)` serves this case and returns the unwrapped state.

- *Streaming-replay runtime* — the runtime sees one event at a time,
  with no command boundaries. To replay through a length-2 edge, the
  state mid-chain is "I just observed event 1; I expect event 2 next."
  This is the `InFlight s co` wrapper: `Settled s` for stable states,
  `InFlight s [remaining events]` mid-chain. The streaming `applyEvent`
  returns wrapped state.

Both runtimes are first-class supported.

**The example aggregate this plan modifies.**
`jitsurei/src/Jitsurei/UserRegistration.hs` (~570 lines as of
2026-05-16) declares the transducer **three** times: once as
`userReg` via `B.buildTransducer` (the canonical form, lines
284-359), once as `userRegChained` using `B.chainTo` (lines
360-400 — retired in M7), and once as `userRegAST` (lines
400-470, preserved AST form for cross-form equivalence). The
AST form's two edges of interest are in `userRegASTEdges`:

    PotentialCustomer ->
      [ Edge { guard = isStart, update = ..., 
               output = Just $ pack inCtorStart wireRegistrationStarted ...,
               target = Registering } ]

    Registering ->
      [ Edge { guard = isContinue, update = UKeep,
               output = Just $ pack inCtorContinue wireConfirmationEmailSent ...,
               target = RequiresConfirmation } ]

The builder form mirrors them via two `from … onCmd …` blocks with
`goto` between. After M7, the two AST edges collapse into one:

    PotentialCustomer ->
      [ Edge { guard = isStart, update = ...,
               output = [pack inCtorStart wireRegistrationStarted ...,
                         pack inCtorStart wireConfirmationEmailSent ...],
               target = RequiresConfirmation } ]

…and the builder form's two `from` blocks collapse into one
`onCmd inCtorStart` block with two consecutive `emit` calls (legal
under the widened builder per M2) and a single `goto
RequiresConfirmation`.

The `Registering` constructor is removed from `Vertex`; the `Continue`
constructor is removed from `UserCmd`. The associated TH-derived
`inCtorContinue`, `isContinue` declarations are removed from the
`deriveAggregateCtors` spec. `userRegChained` and `userRegDriverConfig`
are deleted. The cross-form equivalence spec
(`jitsurei/test/Jitsurei/UserRegistrationBuilderSpec.hs`) re-greens
because both surviving forms (`userReg` builder and `userRegAST`
AST) now express the same length-2 edge.

Note that the second `pack` re-uses `inCtorStart` (not a separate
`InCtor`): both events are emitted by the same input command, so they
share the input constructor. The `wireConfirmationEmailSent` only reads
`#email` from the input, which `inCtorStart`'s slot list contains.

**The hidden-input check today.**
`Keiki.Core.detectMissingInCtorFields` (line 731) walks one `OutFields`
HList against one `InCtor` and flags slots not visited by any
`TInpCtorField` in the `OutFields`. With multi-event edges, the same
`InCtor` may be referenced from multiple `OPack`s in the same edge's
`output` list, and the *union* of slots visited across those `OPack`s
must cover the input constructor's slots. M4 generalizes the walk
accordingly.

**The composition operator today.**
`Keiki.Composition.composeEdge` (now around lines 700-870 with
the alternative arms `liftLOutAlt`/`liftROutAlt` at lines 846,
864 — shipped after the original plan draft) takes a single edge
`e1` from the first transducer and either drops it (ε-edge —
`output e1 == Nothing`) producing an ε-edge in the composite, or
composes with each edge `e2` of the second transducer that the
produced mid-symbol can reach.

With multi-event edges, naïve per-`OutTerm` composition is unsound
because T2's state changes between mid-symbols of a length-N
first-edge. M6 resolves this via **library-side chain expansion**
(per Decision Log "Multi-event composition (M6)"): `composeEdge`
internally expands a length-N first-edge into N letter edges
threaded through synthetic composite-state intermediates, then
re-collapses into a length-N composite edge with output list
`[substituted o1, ..., substituted oN]`. The composite's `Vertex`
type is unchanged — no synthetic vertices leak. See
`docs/research/gsm-widening-design.md` §5 for the formal
treatment.

**Test infrastructure.** Tests live under `test/` (keiki),
`jitsurei/test/` (jitsurei), `keiki-codec-json/test/`, and
`keiki-codec-json-test/test/`. Each package's entry point
imports its spec modules and registers them under hspec's
`describe`. New specs added by this plan must be wired in the
appropriate `Spec.hs` and listed in the package's
`other-modules` field. The full suite is run via
`nix-shell -p z3 --run "cabal test all"` because the SBV-backed
symbolic specs require z3 in PATH. The 1 currently-pending test
lives in `jitsurei-test`.

**MasterPlan parent.** This plan is one of two alternatives under
`docs/masterplans/7-multi-event-command-support-gsm-widening-vs-state-refinement-ergonomics.md`.
The MasterPlan's Decision Log recorded a 2026-05-02 selection of
EP-20 (state-refinement ergonomics) over this plan; EP-20
shipped end-to-end and this plan was marked Cancelled.
The 2026-05-16 reconsideration (see Status section at the top of
this plan) reverses that selection: EP-19 ships, EP-20's surface
is removed in the same change. The MasterPlan's registry,
Progress, Decision Log, and Outcomes & Retrospective sections
are updated in M8.


## Plan of Work

Eight milestones plus the MasterPlan registry update. Effort
estimate (revised 2026-05-16): **24–40 hours total** — roughly
double the original 12–20 hour estimate because the cascade now
spans four packages, the EP-20 surface must be fully removed
rather than left in place, and M6 implements library-side chain
expansion rather than the original naïve concatenation. The
widening edit (M2) is mechanical but cascade-heavy; the replay
machinery (M3) and the composition expansion (M6) carry the
design work. M5 and M7 are mechanical but volume-heavy because
they delete the EP-20 surface and migrate every jitsurei
aggregate.

**Milestone 0 — Baseline and inventory.** Confirm the working tree
builds and the test suite passes:

    cd /Users/shinzui/Keikaku/bokuno/keiki
    cabal build all
    nix-shell -p z3 --run "cabal test all" 2>&1 | tail -10

Expected baseline as of 2026-05-16: **337 examples**, 0 failures,
1 pending, across four suites (keiki 186 + jitsurei 104 +
codec-json 40 + codec-json-test 7).

Inventory the cascade (expected ~69 sites + the EP-20 retirement
surface + Profunctor/Mermaid cascade — see Progress / M0 for the
full per-file breakdown):

    git grep -nE '(Maybe \(OutTerm|output = (Just|Nothing)|Just \(OPack)' \
      -- src jitsurei keiki-codec-json keiki-codec-json-test test \
      | tee /tmp/gsm-call-sites.txt
    wc -l /tmp/gsm-call-sites.txt

    git grep -nE 'toMultiDecider|DriverConfig|chainTo|userRegDriverConfig|userRegChained|loanAppChained' \
      -- src jitsurei test \
      | tee /tmp/gsm-ep20-surface.txt

    git grep -nE 'firstEdge|rewriteEdge|identityOutTerm|arrOut|edgeOutputName' \
      -- src/Keiki/Profunctor.hs src/Keiki/Render \
      | tee /tmp/gsm-prof-mermaid.txt

Record actual per-file counts in the Progress section so M2 / M5 /
M7 can verify completeness.

**Milestone 1 — Design note.** Create
`docs/research/gsm-widening-design.md` (~250 lines). Sections:

1. *Problem statement.* Letter FST today; multi-event commands
   forced into state-refinement form. Cite the original
   `Registering` + `Continue` workaround pattern (preserved in
   `jitsurei/src/Jitsurei/UserRegistrationV0.hs` as the V0
   compatibility form, retired from V1 by this plan).

2. *Formal mapping.* Letter FST `omega : S × C → E ∪ {ε}` widens
   to GSM `omega : S × C → E*`. Reference Approach 2 in
   `docs/research/multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md`.

3. *AST change.* `output :: Maybe (OutTerm rs ci co)` becomes
   `output :: [OutTerm rs ci co]`. Length-0 = ε, length-1 =
   today's letter, length-2+ = multi. Preserve the existential
   `w` in the `update :: Update rs w ci` field of the GADT.

4. *`InFlight` wrapper.* Streaming replay through a length-2+
   edge passes through wrapped intermediate state. Show the
   type and the replay step semantics with a worked example on
   the `StartRegistration` chain.

5. *Composition under library-side chain expansion.* Explain why
   naïve concatenation is unsound (T2's state changes between
   mid-symbols), and how `composeEdge` recursively expands
   length-N first-edges through synthetic composite-state
   intermediates and re-collapses. Cite MasterPlan #7's
   dimension-4 critique as the motivation; this section is the
   formal resolution.

6. *Mermaid label rendering.* Document the length-based
   switchover (length-1: today; length-2: `cmd / e1; e2`;
   length-3+: multi-line via `<br/>`).

7. *What's preserved.* Per-`OutTerm` `solveOutput`; per-edge
   guard evaluation; `(Bounded, Enum)` on the user's vertex
   enum; vertex enumeration in `checkHiddenInputs`; the
   `Composite` machinery in `Keiki.Composition`.

8. *What's retired.* `Keiki.Decider.toMultiDecider`, `DriverConfig`,
   `chainAdvanceCommand`; `Keiki.Builder.chainTo`, `peChain`,
   `EdgeListAcc`; all jitsurei `*DriverConfig` and `*Chained`
   variants; the EP-20-aligned test specs. The two retirement
   sections (Decider + Builder) reference each other.

9. *What changes.* `omega` returns `[co]`. `checkHiddenInputs`
   walks the per-edge output list as a whole, computing union
   coverage of `InCtor` slots. Composition expands and
   re-collapses multi-event edges internally.

10. *What's deferred.* Conditional output lists (list shape
    depends on input). The recommended pattern stays multiple
    disjoint-guarded edges, one per condition, each with a
    static `[OutTerm]`.

Acceptance: file exists, ~250 lines, covers all sections.

**Milestone 2 — Widen `Edge.output` and cascade-fix.** Edit
`src/Keiki/Core.hs` (Edge GADT at lines 455-461) changing the
field type from `Maybe (OutTerm rs ci co)` to `[OutTerm rs ci co]`
while preserving the existential `w`. Cascade-fix every call site
listed in M0's inventory:

- **Core.hs** (~2 sites): omega, step, applyEvent — adapt
  signatures per M3.
- **Composition.hs** (~5 sites including the new alternative
  arms): defer per-edge cascade to M6 which rewrites the
  function.
- **Profunctor.hs** (~10 sites): `firstEdge`, `rewriteEdge`,
  `rewriteEdgeMaybe`, `rewriteEdgeOut`, the literal `Just
  identityOutTerm` and `Just arrOut`, plus `Arrow`/`Strong`/
  `Choice`/`Category` instance bodies.
- **Render/Mermaid.hs** (~2 sites): `edgeOutputName` plus the
  label-rendering function — implement the length-based
  switchover (length-1: today; length-2: `; ` separator;
  length-3+: `<br/>` separator).
- **Builder.hs**: widen `peOutput :: [OutTerm rs ci co]`
  (snoc-list); `emit` appends; `noEmit` produces an empty list;
  remove the type-level "at most one emit" rule. **Also delete**
  `chainTo`, `peChain`, and `EdgeListAcc`; revert to a single
  `[Edge]` accumulator (per the EP-20 surface retirement
  decision).
- **Decider.hs**: deferred to M5 (which removes the EP-20
  façade and lifts `omega`'s new shape into `decide`).
- **jitsurei aggregates** (~32 sites across OrderCart,
  LoanApplication, UserRegistration, UserRegistrationV0,
  EmailDelivery): replace `output = Just o` → `output = [o]`
  and `output = Nothing` → `output = []`. Defer the multi-event
  collapse to M7.
- **test fixtures and specs** (~22 sites): same mechanical
  replacement.

Run `cabal build all` repeatedly until green; expect compile
errors at every remaining site. After M2, behavior on
length-0/1 outputs is identical to before; tests should pass
modulo the EP-20-aligned specs that fail in M5/M7.

**Milestone 3 — `InFlight` and `applyEvents` (widened).** Add
`InFlight s co` to `Keiki.Core`. Refactor `applyEvent` to operate
on `InFlight`. **Widen** the implementation of `applyEvents`
(currently a letter-fold at `src/Keiki/Core.hs:708-717`) to
properly handle length-2+ chunks per the InFlight semantics:
lift the start state to `Settled`, fold `applyEvent` over the
events, expect `Settled` on completion. Signature is unchanged
so existing callers (including the new `CoreApplyEventsSpec` and
fixture specs) are source-compatible at length-0/1 and stricter
at length-2+. Update `reconstitute`. Add test spec
`jitsurei/test/Jitsurei/UserRegistrationGSMSpec.hs` (initially
containing only the `applyEvents` round-trip test; the other
tests added in M7).

Acceptance: `cabal test all` passes (modulo EP-20-aligned specs
still in flight at this point), including the new
`UserRegistrationGSMSpec`. The existing
`test/Keiki/CoreApplyEventsSpec.hs` continues to pass — its
length-0/1 assertions remain valid under the widened
implementation.

**Milestone 4 — Strengthen `checkHiddenInputs`.** Edit the
per-edge walk in `src/Keiki/Core.hs` to accumulate coverage across
the output list; flag any `InCtor` referenced by any `OPack` in
the list whose slots are not all visited. Add
`test/Keiki/CoreHiddenInputsGSMSpec.hs` with a deliberately
ill-formed multi-event edge.

Acceptance: the new spec asserts the warning fires with a precise
message naming the offending `InCtor` and the missing slot(s).

**Milestone 5 — `Keiki.Decider` retirement and widening.** Edit
`src/Keiki/Decider.hs`:

- Remove `toMultiDecider`, `DriverConfig`,
  `chainAdvanceCommand`, and the chain-replay path inside
  `Decider.evolve`.
- Update the docstring (currently lines 26-45) to describe the
  new direct-`decide` semantics.
- Lift `omega`'s new `[co]` return shape into the `decide`
  field: `decide = \cmd (s, regs) -> omega t s regs ci`.
- Add `evolveStreaming` field (or expose `applyEvent` over
  `InFlight` directly) for multi-event chunked replay.
- Update `test/Keiki/DeciderSpec.hs` to assert `decide` over a
  multi-event edge returns the full event list.
- **Delete** `test/Keiki/DeciderMultiSpec.hs` (its purpose
  folded into the widened `DeciderSpec`).

Acceptance: `cabal build all` succeeds with the EP-20 façade
removed; `test/Keiki/DeciderSpec.hs` passes with the new
multi-event assertion.

**Milestone 6 — `Keiki.Composition` library-side chain
expansion.** Refactor `composeEdge` (and `productEdge`, and the
new alternative arms `liftLOutAlt`/`liftROutAlt` at lines 846,
864) per the **library-side chain expansion** strategy:

- For each `OutTerm` in `output e1`, find the corresponding edge
  in T2 whose guard accepts that mid-symbol; thread T2's state
  across mid-symbols by recursing into the next mid-symbol from
  T2's transitioned state; substitute via `substOut`.
- The resulting composite edge from `(s1, s2)` has
  `target = (target e1, s2_final)` and `output =
  [substituted o1, ..., substituted oN]`.
- Length-0/1 composition behaves identically to today.
- The composite's `Vertex` type is unchanged — no synthetic
  vertices leak. The state-refinement is internal to
  `composeEdge`'s recursion.

Add a multi-event composition test in
`test/Keiki/CompositionSpec.hs`:

- Two-aggregate pipeline where the first aggregate has a
  multi-event edge; assert the composed edge produces the
  expected concatenated event list.
- Stress test where both transducers have multi-event edges;
  assert correct event ordering and target state.

Acceptance: existing composition tests
(`test/Keiki/CompositionSpec.hs`,
`test/Keiki/CompositionAlternativeSpec.hs`,
`test/Keiki/CompositionFeedback1Spec.hs`) continue to pass; new
tests assert the multi-event composition correctness.

**Milestone 7 — jitsurei migration (UserRegistration +
LoanApplication collapse, EP-20 surface deletion).** Edit each
jitsurei aggregate:

- `jitsurei/src/Jitsurei/UserRegistration.hs`:
  - Remove the `Registering` constructor from `Vertex` (5→4
    constructors).
  - Remove the `Continue` constructor from `UserCmd` (5→4
    constructors).
  - Remove the `Continue` entry from `deriveAggregateCtors` and
    `deriveWireCtors` invocations.
  - Collapse the two builder-form `from` blocks (`userReg`,
    lines 284-359) into one block with two consecutive `emit`
    calls and `goto RequiresConfirmation`.
  - **Delete** `userRegChained` (the builder-form variant using
    `chainTo`) and `userRegDriverConfig`.
  - Collapse `userRegAST`'s two AST edges into one length-2
    edge.
  - Update `deriveView` to drop the `Registering` entry.
- `jitsurei/src/Jitsurei/LoanApplication.hs`:
  - Same treatment for the multi-event command authored via
    `chainTo` (`loanAppChained` at lines 776-820): collapse to
    a single multi-`emit` block; remove the chained variant
    and its driver config.
  - Other commands (e.g., `UnderReview` approve/decline
    branches) stay as separate edges — these are not
    multi-event but genuine branching.
- `jitsurei/src/Jitsurei/UserRegistrationV0.hs`,
  `jitsurei/src/Jitsurei/EmailDelivery.hs`,
  `jitsurei/src/Jitsurei/Loan.hs`,
  `jitsurei/src/Jitsurei/LoanWorkflow.hs`,
  `jitsurei/src/Jitsurei/OrderCart.hs`,
  `jitsurei/src/Jitsurei/CoreBankingSync.hs`:
  - Replace `output = Just o` / `output = Nothing` with
    `output = [o]` / `output = []` (already done in M2's
    mechanical pass; this milestone verifies and re-greens
    each aggregate's behaviour specs).
- Cascade-fix the jitsurei specs:
  - **Delete** `jitsurei/test/Jitsurei/UserRegistrationMultiSpec.hs`,
    `UserRegistrationChainedSpec.hs`,
    `LoanApplicationMultiSpec.hs`,
    `LoanApplicationChainedSpec.hs` (their purpose folds into
    the widened `decide` semantics).
  - Re-green `UserRegistrationSpec`, `UserRegistrationViewSpec`,
    `UserRegistrationBuilderSpec`, `UserRegistrationSymbolicSpec`,
    `UserRegistrationV0Spec`, `LoanApplicationSpec`,
    `LoanApplicationBuilderSpec`, `LoanApplicationViewSpec`,
    `LoanApplicationSymbolicSpec`,
    `OrderCartSpec`/`OrderCartBuilderSpec`, `EmailDelivery*`,
    `LoanSpec`, `LoanWorkflowSpec`, `CoreBankingSyncSpec`.
  - Add `jitsurei/test/Jitsurei/UserRegistrationGSMSpec.hs` and
    `LoanApplicationGSMSpec.hs` with: `decide` returns N-element
    list; `applyEvents` round-trips canonical log; streaming
    `applyEvent` over `InFlight` agrees with chunked
    `applyEvents`.
  - Wire new specs into `jitsurei/test/Spec.hs` and
    `jitsurei/jitsurei.cabal`.

**Sibling-package sanity check.** Confirm `keiki-codec-json` and
`keiki-codec-json-test` need zero code changes (a fresh `git
grep -E 'Edge|OutTerm|applyEvent|InFlight'` over both trees
shows zero hits as of 2026-05-16). Re-run `cabal test all` to
verify no transitive breakage.

Acceptance: full test suite passes; `Jitsurei.UserRegistration`
line count drops by ~80-100 lines; `Jitsurei.LoanApplication`
drops analogously; vertex/command enums shrink as enumerated;
net test count ≈ baseline 337 ± small delta (see Validation
section).

**Milestone 8 — Docs, MasterPlan registry update, commit.**

- Update
  `docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`
  line 974 (or current equivalent) to reflect GSM as the
  canonical path.
- Update
  `docs/research/multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md`'s
  Recommendation section to "Approach 2 (GSM with library
  expansion) is the canonical path."
- Update
  `docs/masterplans/7-multi-event-command-support-gsm-widening-vs-state-refinement-ergonomics.md`:
  - Exec-Plan Registry: EP-19 → Complete; EP-20 → Superseded by
    EP-19.
  - Progress section: flip the EP-19 / EP-20 status blocks.
  - Decision Log: add a new entry recording the reversal and
    the EP-20 surface deletion.
  - Outcomes & Retrospective: append a "2026-05-16 reversal
    closure" sub-section.
- Stage and commit per the Concrete Steps section below.


## Concrete Steps

All commands run from `/Users/shinzui/Keikaku/bokuno/keiki/`.

Recommended commit granularity: one commit per milestone (or one
per file-cluster within heavy milestones M2/M7) so that partial
progress can be rolled back if a deep issue surfaces and so the
PR is reviewable.

**M0:**

    cabal build all
    nix-shell -p z3 --run "cabal test all" 2>&1 | tail -10
    # expect: 337 examples (186 + 104 + 40 + 7), 0 failures, 1 pending

    git grep -nE '(Maybe \(OutTerm|output = (Just|Nothing)|Just \(OPack)' \
      -- src jitsurei keiki-codec-json keiki-codec-json-test test \
      | tee /tmp/gsm-call-sites.txt
    wc -l /tmp/gsm-call-sites.txt
    # expect: ~69 lines

    git grep -nE 'toMultiDecider|DriverConfig|chainTo|userRegDriverConfig|userRegChained|loanAppChained|peChain|EdgeListAcc|chainAdvanceCommand' \
      -- src jitsurei test | tee /tmp/gsm-ep20-surface.txt
    wc -l /tmp/gsm-ep20-surface.txt
    # expect: ~50-80 lines covering the surface to delete

    git grep -nE 'firstEdge|rewriteEdge|identityOutTerm|arrOut|edgeOutputName|wcName' \
      -- src/Keiki/Profunctor.hs src/Keiki/Render | tee /tmp/gsm-prof-mermaid.txt
    wc -l /tmp/gsm-prof-mermaid.txt
    # expect: ~10-20 lines (Profunctor + Mermaid call sites)

**M1:** Create the design note. Use the section structure above.

    $EDITOR docs/research/gsm-widening-design.md
    git add docs/research/gsm-widening-design.md
    git commit -m "$(cat <<'EOF'
    docs(research): EP-19 M1 — GSM widening design note

    ExecPlan: docs/plans/19-multi-event-commands-via-edge-output-widening-gsm-expansion.md
    EOF
    )"

**M2:** Edit `src/Keiki/Core.hs:455-461` to widen `Edge.output`
to `[OutTerm rs ci co]` (preserving the existential `w` in
`update`). Then iterate the cascade:

    cabal build all 2>&1 | head -40    # examine first error cluster
    # fix the cited call sites — work file-by-file
    # commit per file-cluster (Core, Profunctor, Mermaid, Builder,
    # then each jitsurei aggregate, then test fixtures)
    # repeat until clean

After every successful build, re-run tests for the affected
package:

    nix-shell -p z3 --run "cabal test keiki:test:keiki-test" 2>&1 | tail -5
    nix-shell -p z3 --run "cabal test jitsurei:test:jitsurei-test" 2>&1 | tail -5

**M3:** Add `InFlight` and widen `applyEvents`. Update
`reconstitute`. Add `jitsurei/test/Jitsurei/UserRegistrationGSMSpec.hs`.

**M4:** Edit `checkHiddenInputs`. Add `test/Keiki/CoreHiddenInputsGSMSpec.hs`.

**M5:** Edit `src/Keiki/Decider.hs` — delete `toMultiDecider`,
`DriverConfig`, `chainAdvanceCommand`; widen `decide`. Delete
`test/Keiki/DeciderMultiSpec.hs`. Run tests.

**M6:** Edit `src/Keiki/Composition.hs` — implement library-side
chain expansion in `composeEdge` / alternative arms. Add
multi-event composition tests. Run tests.

**M7:** Edit jitsurei aggregates per the M7 milestone in Plan of
Work. Delete EP-20-aligned specs. Add `UserRegistrationGSMSpec`
and `LoanApplicationGSMSpec`. Run full suite.

**M8:** Edit docs. Update MasterPlan #7 registry/progress/decision
log/outcomes. Commit (one final summary commit, after the
per-milestone commits above):

    git add docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md \
            docs/research/multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md \
            docs/plans/19-multi-event-commands-via-edge-output-widening-gsm-expansion.md \
            docs/masterplans/7-multi-event-command-support-gsm-widening-vs-state-refinement-ergonomics.md

    git commit -m "$(cat <<'EOF'
    docs: EP-19 M8 — close GSM widening; update MasterPlan #7

    Multi-event commands are first-class via the widened Edge.output and
    InFlight replay wrapper. EP-20's state-refinement ergonomics surface
    (toMultiDecider, DriverConfig, chainTo, peChain, EdgeListAcc,
    *DriverConfig, *Chained variants) is removed. UserRegistration drops
    the Registering intermediate vertex and the Continue internal command;
    LoanApplication drops its chained-variant analogues.

    MasterPlan: docs/masterplans/7-multi-event-command-support-gsm-widening-vs-state-refinement-ergonomics.md
    ExecPlan: docs/plans/19-multi-event-commands-via-edge-output-widening-gsm-expansion.md
    Intention: intention_01kqmjp9k8e478db6xjah31455
    EOF
    )"


## Validation and Acceptance

After all eight milestones:

- `cabal build all` succeeds with no warnings across all four
  packages (`keiki`, `jitsurei`, `keiki-codec-json`,
  `keiki-codec-json-test`).
- `nix-shell -p z3 --run "cabal test all"` reports the expected
  post-cascade count, 0 failures. The expected count is the
  baseline of **337 examples** (as of 2026-05-16), adjusted as
  follows:
  - **Subtract** the EP-20-aligned specs whose purpose is folded
    into core (decided per "EP-20 surface retirement strategy"):
    `test/Keiki/DeciderMultiSpec.hs`,
    `jitsurei/test/Jitsurei/UserRegistrationMultiSpec.hs`,
    `UserRegistrationChainedSpec.hs`,
    `LoanApplicationMultiSpec.hs`,
    `LoanApplicationChainedSpec.hs`. Total ≈ 15-25 examples
    depending on retirement scope.
  - **Add** the new GSM specs: `UserRegistrationGSMSpec` (3+),
    `LoanApplicationGSMSpec` (3+),
    `test/Keiki/CoreHiddenInputsGSMSpec.hs` (2+), the
    multi-event-aware composition test in
    `test/Keiki/CompositionSpec.hs` (2+), the multi-event
    `decide` test in `test/Keiki/DeciderSpec.hs` (1+), the
    builder multi-`emit` test in `test/Keiki/BuilderSpec.hs`
    (2+). Total ≈ 13-15 new examples.
  - **Net**: roughly flat, plausibly slight decrease.
- `docs/research/gsm-widening-design.md` exists and documents the
  widening (including the M6 composition strategy commitment and
  the M7 Mermaid rendering decision).
- `Keiki.Core.Edge`'s `output` field has type `[OutTerm rs ci co]`
  (preserving the existential `w` in the `update` field).
- `Keiki.Core.applyEvent`'s signature carries `InFlight s co` on input
  and output.
- `Keiki.Core.applyEvents :: SymTransducer phi rs s ci co -> (s, RegFile rs)
  -> [co] -> Maybe (s, RegFile rs)` is exported (signature unchanged
  from the EP-20 letter version; implementation widened).
- `Keiki.Core.checkHiddenInputs`'s implementation walks edge output
  lists as a whole.
- `Keiki.Decider`: `decide` returns the full `[e]` directly;
  `toMultiDecider`, `DriverConfig`, etc. retired per chosen
  strategy.
- `Keiki.Builder`: `emit` accumulates a list; `chainTo`/`peChain`
  retired per chosen strategy.
- `Keiki.Profunctor`: `firstEdge`, `rewriteEdge*`, `Arrow`/`Strong`/
  `Choice`/`Category` instances adapted to list-shaped output.
- `Keiki.Render.Mermaid`: `edgeOutputName` and label rendering
  handle length-0/1/N edges per chosen strategy.
- `Jitsurei.UserRegistration.Vertex` has four constructors
  (`PotentialCustomer`, `RequiresConfirmation`, `Confirmed`, `Deleted`);
  `UserCmd` has four constructors (drops `Continue`).
- `Jitsurei.LoanApplication`: multi-event commands collapsed
  analogously where present.
- `docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`
  line 974 (or current equivalent) is updated to reflect
  GSM as the canonical path.
- `docs/masterplans/7-multi-event-command-support-gsm-widening-vs-state-refinement-ergonomics.md`'s
  Exec-Plan Registry, Progress, and Decision Log reflect the
  reversal (EP-19 Complete, EP-20 Superseded).

Behavioral acceptance (the load-bearing tests):

1. **Multi-event decide.** `decide d (StartRegistration sd)
   (PotentialCustomer, emptyRegs)` returns `[RegistrationStarted ...,
   ConfirmationEmailSent ...]` in that order.

2. **Chunk replay.** `applyEvents userReg (PotentialCustomer, emptyRegs)
   [RegistrationStarted ..., ConfirmationEmailSent ...]` returns
   `Just (RequiresConfirmation, regs)` with `regs ! #email == "alice@x"`
   etc.

3. **Streaming replay through `InFlight`.** Sequential applications of
   `applyEvent` on `Settled PotentialCustomer` and then `RegistrationStarted`,
   then on the resulting `InFlight ... [...]` and `ConfirmationEmailSent`,
   ends in `Settled RequiresConfirmation` with the same registers.

4. **Out-of-order replay rejection.** Streaming `applyEvent` on
   `Settled PotentialCustomer` with `ConfirmationEmailSent` (not the
   prefix of any edge's output list at this vertex) returns `Nothing`.

5. **Hidden-input check on multi-event edge.** A test fixture builds an
   edge with `update` reading `#confirmCode` and `output = [emit event
   carrying only #email, emit event carrying only #at]` — neither event
   visits `#confirmCode`. `checkHiddenInputs` returns a warning naming
   `confirmCode` as the unrecovered slot.

6. **Composition over multi-event.** A two-aggregate pipeline where the
   first aggregate emits `[e1, e2]` and the second is letter; the
   composed edge has `output = [substituted e1, substituted e2]`.


## Idempotence and Recovery

The plan's milestones are mostly additive after M2:

- M0 reads only.
- M1 creates a new file.
- M2 changes one field type and cascades. Stage commits per call-site
  cluster (e.g., one for `Keiki.Core.hs`, one for examples, one for
  tests) so partial progress can be rolled back if a deep issue
  surfaces.
- M3 adds new types and functions; existing functions get refactored
  but API remains compatible at the value level.
- M4 changes `checkHiddenInputs`; defensive: a faulty new walk emits
  spurious warnings, but does not change semantic correctness of any
  transducer.
- M5–M7 are file-local changes.
- M8 edits two existing docs and creates a commit.

Recovery from a failing build at M2:

- The compile errors enumerate every remaining call site. Fix in
  declared order.
- If a fix introduces a bug surfaced only by tests, the bug is local
  to the most recent fix; revert that hunk with `git diff -p > /tmp/m2.patch
  && git checkout -- <file>` and try again.

Recovery from a failing test in M3 (replay machinery):

- The streaming `applyEvent` is the most subtle: ensure the wrapping
  flips from `Settled` to `InFlight` exactly when an edge with
  `output = [_, _, ...]` (length ≥ 2) fires, and back to `Settled`
  when the queue empties.
- The chunked `applyEvents` is `foldM applyEvent` lifted to `InFlight`
  start state, asserting `Settled` at end. If the assertion fails, the
  events do not match the expected chain — check that the test
  fixture's events match the edge's static output list.

Recovery from a bad commit:

- `git revert` and reopen.

Recovery from cascade pain in M2 spread across many files:

- Stage commits per cluster (Core, Composition, Decider, Examples,
  Tests). If any cluster diverges, revert just that cluster.


## Interfaces and Dependencies

New types and functions:

    -- src/Keiki/Core.hs (modifies and adds)
    data Edge phi rs ci co s where
      Edge
        :: { guard  :: phi
           , update :: Update rs w ci             -- existential w preserved
           , output :: [OutTerm rs ci co]         -- changed from Maybe
           , target :: s
           }

    data InFlight s co = Settled !s | InFlight !s ![co]
      deriving (Eq, Show)

    omega :: BoolAlg phi (RegFile rs, ci)
          => SymTransducer phi rs s ci co -> s -> RegFile rs -> ci
          -> [co]   -- changed from Maybe

    applyEvent
      :: BoolAlg phi (RegFile rs, ci)
      => SymTransducer phi rs s ci co
      -> InFlight s co -> RegFile rs -> co
      -> Maybe (InFlight s co, RegFile rs)   -- wrapped state in/out

    applyEvents     -- signature unchanged from EP-20 letter version;
                    -- implementation widened in M3 to handle length-2+
      :: BoolAlg phi (RegFile rs, ci)
      => SymTransducer phi rs s ci co
      -> (s, RegFile rs) -> [co]
      -> Maybe (s, RegFile rs)

    -- src/Keiki/Decider.hs (modified — EP-20 façade removed)
    data Decider c e s s_streaming = Decider
      { decide          :: c -> s -> [e]                            -- now actually returns ≥0
      , evolve          :: s -> e -> s                              -- letter case (single-event edges)
      , evolveStreaming :: s_streaming -> e -> Maybe s_streaming    -- multi-event case
      , initialState    :: s
      , isTerminal      :: s -> Bool
      }

    toDecider :: ... -> Decider ci co (s, RegFile rs) (InFlight s co, RegFile rs)

Modified modules:

- `Keiki.Core` (modified) — `Edge.output` widened; `omega`,
  `applyEvent`, `applyEvents`, `step`, `reconstitute`,
  `checkHiddenInputs` adapted; `InFlight` added.
- `Keiki.Composition` (modified) — `composeEdge` and the new
  alternative arms (`liftLOutAlt`, `liftROutAlt`) implement
  library-side chain expansion for multi-event first-edges.
- `Keiki.Decider` (modified, surface deleted) — `decide` directly
  returns `omega`'s `[co]`; `evolveStreaming` field added;
  `toMultiDecider`, `DriverConfig`, `chainAdvanceCommand`
  **removed**.
- `Keiki.Builder` (modified, surface deleted) — `peOutput`
  accumulator widens to a list; `emit` appends rather than sets;
  multiple `emit` calls per block produce a multi-event edge;
  `chainTo`, `peChain`, `EdgeListAcc { elaMain, elaChain }`
  **removed**; reverts to a single `[Edge]` accumulator.
- `Keiki.Profunctor` (modified — new since plan's original
  draft) — `firstEdge`, `rewriteEdge`, `rewriteEdgeMaybe`,
  `rewriteEdgeOut` adapted from `Maybe`-fmap to list-fmap;
  literal `output = Just identityOutTerm` / `output = Just
  arrOut` changed to length-1 list literals; `Arrow`/`Strong`/
  `Choice`/`Category` instance bodies adapted.
- `Keiki.Render.Mermaid` (modified — new since plan's original
  draft) — `edgeOutputName` and label-formatting handle the
  length-based switchover (length-1: today; length-2: `; `
  separator; length-3+: `<br/>` separator).
- `Jitsurei.UserRegistration` (modified) — drops `Registering`
  and `Continue`; collapses two edges into one multi-event edge
  in both builder (`userReg`) and AST (`userRegAST`) forms;
  `userRegChained` and `userRegDriverConfig` removed.
- `Jitsurei.LoanApplication` (modified) — `loanAppChained` and
  driver config removed; multi-event command(s) collapsed to
  multi-`emit` blocks.
- `Jitsurei.{UserRegistrationV0, EmailDelivery, Loan,
  LoanWorkflow, OrderCart, CoreBankingSync}` (modified) — `Just`/
  `Nothing` mechanically replaced with `[o]`/`[]`; no semantic
  change beyond the widening.

New test specs:

- `test/Keiki/CoreHiddenInputsGSMSpec.hs` — strengthened-check
  assertions.
- `jitsurei/test/Jitsurei/UserRegistrationGSMSpec.hs` —
  multi-event-specific assertions.
- `jitsurei/test/Jitsurei/LoanApplicationGSMSpec.hs` — same.

Deleted test specs (EP-20 surface retirement):

- `test/Keiki/DeciderMultiSpec.hs`
- `jitsurei/test/Jitsurei/UserRegistrationMultiSpec.hs`
- `jitsurei/test/Jitsurei/UserRegistrationChainedSpec.hs`
- `jitsurei/test/Jitsurei/LoanApplicationMultiSpec.hs`
- `jitsurei/test/Jitsurei/LoanApplicationChainedSpec.hs`

Existing functions consumed:

- `Keiki.Core.solveOutput` (unchanged) — walks one `OutTerm`. The new
  `applyEvent` calls it once per `OutTerm` in the edge's output list.
- `Keiki.Composition.substOut` (unchanged) — substitutes one
  `OutTerm`. The new `composeEdge` calls it once per `OutTerm` in
  the chain-expansion recursion.
- `Keiki.Composition`'s `Composite` machinery (unchanged) — used
  internally by the chain-expansion recursion to thread T2's
  state across mid-symbols.

No new external dependencies. The existing `template-haskell`, `sbv`,
`text`, `time` are sufficient.

Insulated sibling packages (no edits required):

- `keiki-codec-json` and `keiki-codec-json-test` operate on
  `RegFile`, not `Edge`. A 2026-05-16 `git grep` confirms zero
  references to `Edge`, `OutTerm`, `applyEvent`, or `InFlight`
  in either package's source or tests. M7 re-runs `cabal test
  all` to confirm no transitive breakage.

The MasterPlan parent
(`docs/masterplans/7-multi-event-command-support-gsm-widening-vs-state-refinement-ergonomics.md`)
recorded the 2026-05-02 selection of EP-20 (state-refinement
ergonomics) and EP-20 shipped. The 2026-05-16 reconsideration
reverses that selection. M8 updates the MasterPlan's Exec-Plan
Registry (EP-19 → Complete; EP-20 → Superseded by EP-19),
Progress section, Decision Log, and Outcomes & Retrospective
section.


## Revision Notes

- **2026-05-02 (initial draft)**: plan created against
  pre-Plan-15 master. Inventory listed AST-form call sites in the
  example modules at specific line numbers.

- **2026-05-02 (Plan 15 shipped)**: Plan 15 completed all
  milestones (M0–M7). `Keiki.Builder` exists at
  `src/Keiki/Builder.hs`; both example aggregates are now in
  builder form (`emailDelivery`, `userReg`) with AST forms
  preserved as `emailDeliveryAST`, `userRegAST` for cross-form
  equivalence testing. Updated:
  - **Progress / M0**: added the builder cascade to the inventory
    instructions; named the cross-form equivalence specs that must
    re-green.
  - **Progress / M2**: added a "Builder cascade" sub-section
    spelling out the widening of `PartialEdge`'s output
    accumulator, the change in `emit`/`noEmit` semantics, and the
    test-spec updates required.
  - **Progress / M7**: noted that UserRegistration's transducer is
    now declared twice (`userReg` and `userRegAST`) and that
    both forms must be edited; updated cascade-fix targets to
    include the cross-form equivalence spec.
  - **Plan of Work / M2 and M7**: re-summarized to match the new
    Progress milestone descriptions.
  - **Context and Orientation**: updated the "Existing call sites"
    enumeration to reflect the builder cascade; updated the
    "example aggregate" subsection to describe the builder/AST
    pair.
  - **Decision Log**: added a new entry recording the cascade
    impact.
  - **Interfaces and Dependencies**: added `Keiki.Builder` to the
    modified-modules list.

- **2026-05-16 (reopened under reconsideration)**: The plan was
  marked Cancelled (2026-05-02) when the user selected EP-20 for
  implementation; EP-20 shipped end-to-end (`Keiki.Core.applyEvents`
  letter-fold, `Keiki.Decider.toMultiDecider` + `DriverConfig`,
  `Keiki.Builder.chainTo`, `userRegDriverConfig`, `userRegChained`,
  `loanAppChained`). The user is now reconsidering EP-19 because
  the downstream surface that depends on `Keiki.Core.Edge` has
  grown substantially (new sibling package `jitsurei/` with ~8
  aggregates; new `Keiki.Profunctor` module; new
  `Keiki.Render.Mermaid` module; total `output = Just|Nothing`
  call sites ~69, up from the original plan's estimated ~24)
  and a façade no longer suffices — first-class multi-event
  support at the AST level is needed. Updated:
  - **Status (new section near top)**: added "Reopened under
    reconsideration (2026-05-16)" summarising the reversal
    context, current code state, and implications for the
    MasterPlan.
  - **Progress / M0**: refreshed inventory expectations to
    reflect the ~69-site cascade, the four-suite 337-example
    baseline, the GADT shape of `Edge` (with existential `w`
    in `update :: Update rs w ci`), and the EP-20 surface
    that must be retired or coexisted with.
  - **Progress / M2**: added Profunctor cascade (firstEdge,
    rewriteEdge*, Arrow/Strong/Choice/Category instances) and
    Mermaid renderer cascade (edgeOutputName, label rendering
    strategy options); added `chainTo` / `peChain` /
    `EdgeListAcc` retirement question to the Builder cascade
    sub-section.
  - **Progress / M3**: noted that `applyEvents` (letter version)
    already exists at `Keiki.Core.hs:708-717` (shipped by EP-20
    M2); EP-19 keeps the name and widens the implementation.
  - **Progress / M5**: added the `toMultiDecider` /
    `DriverConfig` retirement question with three options
    (full removal / deprecate / repurpose).
  - **Progress / M6**: rewrote to address the MasterPlan
    dimension-4 critique (multi-event composition is
    fundamentally non-local) with two strategies (library-side
    chain expansion vs class restriction); recommended
    Strategy A.
  - **Progress / M7**: expanded from "UserRegistration" to
    "jitsurei-wide migration" — now includes UserRegistration,
    UserRegistrationV0, EmailDelivery, Loan, LoanApplication,
    LoanWorkflow, OrderCart, CoreBankingSync; spec retirement
    list expanded; sibling-package sanity check added.
  - **Decision Log**: added the reversal entry (2026-05-16);
    added four "Decision (pending)" entries flagging open
    strategic questions (EP-20 surface retirement, multi-event
    composition strategy, Mermaid label strategy, builder
    verb retirement).
  - **Validation and Acceptance**: refreshed expected test
    count to 337 baseline with subtraction/addition estimates;
    added explicit acceptance criteria for Profunctor and
    Mermaid; added MasterPlan registry update acceptance
    criterion.

  Not yet refreshed in the body but flagged for follow-up
  passes (these are tactical line-number and prose updates
  that can wait until the strategic decisions above are
  confirmed):
  - **Plan of Work / Concrete Steps**: still references
    `src/Keiki/Examples/UserRegistration.hs` line numbers and
    the original ~24-site cascade. To be refreshed once the
    EP-20 retirement / composition strategy / Mermaid
    decisions are committed.
  - **Context and Orientation**: same — needs path refresh
    from `src/Keiki/Examples/` to `jitsurei/src/Jitsurei/`,
    and current line-number citations.
  - **Interfaces and Dependencies**: needs `Keiki.Profunctor`
    and `Keiki.Render.Mermaid` added to the modified-modules
    list, and the EP-20 surface (`toMultiDecider`,
    `DriverConfig`, `chainTo`, `peChain`, `EdgeListAcc`)
    enumerated as retired (or repurposed) modules.

  Required follow-up edit outside this file:
  `docs/masterplans/7-multi-event-command-support-gsm-widening-vs-state-refinement-ergonomics.md`'s
  Exec-Plan Registry, Progress, Decision Log, and Outcomes &
  Retrospective sections must be updated to reflect the
  reversal (EP-19: Cancelled → In Progress; EP-20: Complete →
  Superseded by EP-19). Not edited in this pass — flagged for
  the implementer when M0 begins.
