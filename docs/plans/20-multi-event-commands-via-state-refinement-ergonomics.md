---
id: 20
slug: multi-event-commands-via-state-refinement-ergonomics
title: "Multi-event commands via state-refinement ergonomics"
kind: exec-plan
created_at: 2026-05-02T14:53:05Z
intention: "intention_01kqmjp9k8e478db6xjah31455"
master_plan: "docs/masterplans/7-multi-event-command-support-gsm-widening-vs-state-refinement-ergonomics.md"
---

# Multi-event commands via state-refinement ergonomics

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

The keiki library's pure core today is a *letter Finite State Transducer*
(letter FST): every edge produces zero or exactly one event. This is the
shape committed to in
`docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`,
the working baseline that names letter FST as the foundation. Multi-event
commands — those that semantically emit two or more events on a single
input — are handled today by *state refinement*: the user adds an
intermediate vertex (`Registering`) and a synthetic internal command
(`Continue`) so that each transition stays a letter edge. The synthesis
note explicitly endorses this approach (line 974) as "the cleanest under
the symbolic-register formalism."

State refinement is mathematically clean but ergonomically loose. The
user has to:

1. Declare the intermediate vertex in their `Vertex` enum.
2. Declare the internal command in their `ci` enum.
3. Hand-write the ε-edge between them (today's "register `Continue`
   edge in `Registering`" pattern).
4. From a *caller's* perspective, drive the chain with two `decide`
   calls (one for `StartRegistration`, one for `Continue`) and chain
   the events. Or replay the chain event-by-event with `applyEvent`,
   re-checking the intermediate state.

This plan ships ergonomic support for state refinement so that pieces
3 and 4 are handled by the library, while the AST and the foundation
stay strict letter FST. After this plan completes:

- `Keiki.Core.applyEvents :: SymTransducer phi rs s ci co -> (s, RegFile rs)
  -> [co] -> Maybe (s, RegFile rs)` exists. It folds `applyEvent` over a
  chunk of events (corresponding to one logical command's emission) and
  returns the unwrapped final state. Useful for runtimes that have
  command boundaries.

- `Keiki.Decider.DriverConfig` and `Keiki.Decider.toMultiDecider` exist.
  `DriverConfig s ci` lets the user mark which vertices are *internal*
  (must not surface as terminal-of-decide states) and which `ci`
  constructor advances them. `toMultiDecider t cfg` produces a
  `Decider`-shaped record whose `decide :: c -> s -> [e]` drives the
  letter chain end-to-end automatically: run the user's command, check
  if landed in an internal vertex, auto-emit the configured advancement
  command, repeat until back in a public vertex, return the collected
  events.

- `Keiki.Builder.chainTo` (a new verb extending `Keiki.Builder`,
  whose monadic DSL was shipped by Plan 15
  (`docs/plans/15-edge-builder-monadic-dsl-for-authoring-symtransducer-edges.md`)
  on 2026-05-02 with all milestones complete) exists. It compiles a
  multi-`emit` block into a chain of letter edges through user-named
  intermediate vertices. The user names the vertices explicitly; the
  DSL synthesizes the ε-step edges between them. The original M5
  soft-deferral plan is no longer needed since `Keiki.Builder` is
  in place; M1's design note now treats M5 as unconditional and
  preserves the deferral text only as a "what would have happened"
  note for posterity.

- `Keiki.Examples.UserRegistration`'s existing state-refinement form
  (vertex `Registering`, command `Continue`) is preserved unchanged.
  Note that as of master post-Plan-15, `userReg` is now built via
  `Keiki.Builder.buildTransducer` (the canonical form); the AST form
  is preserved as `userRegAST` for cross-form equivalence testing.
  EP-20's additions are purely on the consumer side
  (`userRegDriverConfig` adds a value; the transducer itself is
  unchanged in either form). A new spec file
  `test/Keiki/Examples/UserRegistrationMultiSpec.hs` demonstrates that
  `toMultiDecider` produces, from a single `StartRegistration` command,
  the two-element event list `[RegistrationStarted, ConfirmationEmailSent]`
  while the underlying transducer remains a letter FST.

A future contributor verifies the work as follows:

    cd /Users/shinzui/Keikaku/bokuno/keiki
    nix-shell -p z3 --run "cabal test all" 2>&1 | tail -3
    # Expect: 110 + N examples (N from the new specs added by this plan), 0 failures.

The user-visible win:

    > let mdec = toMultiDecider userReg userRegDriverConfig
    > decide mdec (StartRegistration startData) (PotentialCustomer, emptyRegs)
    [ RegistrationStarted (RegistrationStartedData "alice@x" "Z9F4" t0)
    , ConfirmationEmailSent (ConfirmationEmailSentData "alice@x")
    ]

The single command produces a 2-element event list, **with no AST
change and no widening of `Edge.output`**. The intermediate vertex
(`Registering`) and the internal command (`Continue`) are declared by
the user as part of the model, but the caller of `decide` never sees
them — the façade drives the chain end-to-end.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be
documented here, even if it requires splitting a partially completed task
into two ("done" vs. "remaining"). This section must always reflect the
actual current state of the work.

- [x] **Milestone 0 — Verify prerequisites.** *(2026-05-02 — done.)*
      Baseline:
      - `cabal build all`: clean (no warnings, "Up to date").
      - `nix-shell -p z3 --run "cabal test all"`: **149 examples, 0
        failures** (was ≥110 in plan-draft estimate; grew with
        Plan 15's builder specs and other intervening work).
      - GHC 9.12.3, cabal-install 3.16.1.0.
      - `src/Keiki/Examples/UserRegistration.hs:124` has `Continue`
        in `UserCmd`; line 179 has `Registering` in `Vertex`.
      - `Keiki.Decider.toDecider` is the single-event lift (lines
        109-122 of `src/Keiki/Decider.hs`).
      - `Keiki.Builder` exports `buildTransducer`, `from`, `onCmd`,
        `onEpsilon`, `slot`, `(.=)`, `emit`, `emitWith`, `noEmit`,
        `(*:)`, `oNil`, `requireEq`, `requireGuard`, `goto` and the
        QualifiedDo binds. Plan 15's M5 `chainTo` is unconditional.
      - `Keiki.Core` exports include `step`, `reconstitute`,
        `applyEvent` under "Pure-layer entry points"; `applyEvent`
        currently lives at `src/Keiki/Core.hs:642-654`,
        `reconstitute` at lines 660-670, `step` at lines 625-633.
        M2's `applyEvents` will sit between them.

- [x] **Milestone 1 — Design note.** *(2026-05-02 — done.)* Wrote
      `docs/research/multi-decider-via-state-refinement.md` (335
      lines, longer than the original 150-200 estimate to give each
      section enough depth). Sections shipped: problem statement,
      why state refinement is canonical (citing synthesis line 974
      + Approach 1 + MasterPlan 7's three reinforcing reasons), the
      three-piece ergonomics layer with signatures and worked
      compilation strategy for `chainTo`, what's preserved
      (everything: AST, all analyses, composition, symbolic
      emptiness, both example aggregates), explicit non-goals
      (AST widening, hand-written apply, parallel formalism,
      conditional output lists, runtime concerns), the M5
      deferral plan preserved for posterity, and a verification
      plan listing the load-bearing acceptance tests.

- [x] **Milestone 2 — `applyEvents` in `Keiki.Core`.** *(2026-05-02
      — done.)* Added `applyEvents` immediately after `reconstitute`
      in `src/Keiki/Core.hs` (now at lines 686-696) with the planned
      6-line implementation. Exported from `Keiki.Core` under
      "Pure-layer entry points." Created
      `test/Keiki/CoreApplyEventsSpec.hs` with three assertions:
      canonical-log round-trip, multi-event chunk replay
      `(PotentialCustomer, emptyRegs) → (RequiresConfirmation,
      regs)` for `[RegistrationStarted, ConfirmationEmailSent]`,
      and out-of-order rejection. Wired into `test/Spec.hs` and
      `keiki.cabal`. Test count grew from 149 → 152 (the three new
      assertions); 0 failures. The third assertion uses a manual
      `case` on `Maybe` because `RegFile UserRegRegs` has no
      `Show` instance, so `shouldBe` / `shouldSatisfy` would not
      type-check.
      Original spec body retained below for reference:

          applyEvents
            :: BoolAlg phi (RegFile rs, ci)
            => SymTransducer phi rs s ci co
            -> (s, RegFile rs) -> [co]
            -> Maybe (s, RegFile rs)
          applyEvents _ acc []         = Just acc
          applyEvents t (s, regs) (co : rest) = do
            (s', regs') <- applyEvent t s regs co
            applyEvents t (s', regs') rest

      This is a fold of the existing `applyEvent`. The semantic
      difference from `reconstitute` is the start state: `reconstitute`
      starts from the transducer's `(initial, initialRegs)`;
      `applyEvents` starts from a caller-supplied `(s, RegFile rs)`,
      letting the runtime adapter chunk-replay events corresponding to
      one logical command from any current state. Export it from
      `Keiki.Core`.

      Add a test spec
      `test/Keiki/CoreApplyEventsSpec.hs` with three assertions:
      (1) round-trip on UserRegistration's canonical 5-event log
      starting from `(PotentialCustomer, emptyRegs)`; (2) replay of
      the two events from a multi-event command starting at the
      command's source vertex returns the command's target vertex with
      registers set; (3) malformed event sequence returns `Nothing`.

- [x] **Milestone 3 — `DriverConfig` + `toMultiDecider`.**
      *(2026-05-02 — done.)* Added `DriverConfig` newtype and
      `toMultiDecider` to `src/Keiki/Decider.hs` (now lines
      127-225) per the planned implementation. Imported `step`
      from `Keiki.Core` to drive the chain. The driver loop
      `driveDecide` is exposed only via `toMultiDecider`'s
      `decide` field (not exported separately).
      `toDecider` is unchanged. Created
      `test/Keiki/DeciderMultiSpec.hs` with three assertions:
      multi-event decide returns the 2-element list; underlying
      letter-FST behavior via `toDecider` remains length-1; a
      single-event command from a public vertex still returns a
      singleton (regression test for the driver not over-driving).
      Wired into `test/Spec.hs` and `keiki.cabal`. Test count
      grew 152 → 155; 0 failures. Spec uses a local
      `userRegCfg` so M3 is independent of M4's
      `userRegDriverConfig` export.
      Original spec body retained below for reference:

          -- | Identifies internal control vertices and the command that
          -- advances them. Used by 'toMultiDecider' to drive multi-event
          -- letter chains end-to-end transparently.
          --
          -- 'isInternal v' returns 'Just c' when 'v' is internal and
          -- 'c' is the command to use to advance it; 'Nothing' for
          -- public vertices that 'decide' should treat as terminal of
          -- one driver step.
          newtype DriverConfig s ci = DriverConfig
            { isInternal :: s -> Maybe ci }

          -- | Construct a 'Decider' that drives multi-event letter chains
          -- end-to-end. Compared to 'toDecider', the produced 'decide'
          -- function may return event lists of length ≥ 2 by chaining
          -- automatically through internal vertices.
          --
          -- 'decide' runs the supplied command from the current public
          -- vertex; if it lands in an internal vertex (per 'cfg'), it
          -- auto-advances with the configured command and accumulates
          -- the emitted event; this repeats until landing in a public
          -- vertex.
          toMultiDecider
            :: BoolAlg phi (RegFile rs, ci)
            => SymTransducer phi rs s ci co
            -> DriverConfig s ci
            -> Decider ci co (s, RegFile rs)
          toMultiDecider t cfg = Decider
            { decide       = driveDecide t cfg
            , evolve       = \(s, regs) ev -> case applyEvent t s regs ev of
                Just (s', regs') -> (s', regs')
                Nothing          -> (s, regs)
            , initialState = (initial t, initialRegs t)
            , isTerminal   = \(s, _) -> isFinal t s
            }

          driveDecide
            :: BoolAlg phi (RegFile rs, ci)
            => SymTransducer phi rs s ci co
            -> DriverConfig s ci
            -> ci -> (s, RegFile rs) -> [co]
          driveDecide t cfg ci0 (s0, regs0) = go ci0 (s0, regs0) []
            where
              go ci (s, regs) acc = case step t (s, regs) ci of
                Nothing -> reverse acc   -- guard didn't fire; return what we have
                Just (s', regs', mco) ->
                  let acc' = case mco of
                        Just co -> co : acc
                        Nothing -> acc
                  in case isInternal cfg s' of
                       Just ciNext -> go ciNext (s', regs') acc'
                       Nothing     -> reverse acc'

      Export `DriverConfig` (the constructor and the field) and
      `toMultiDecider` from `Keiki.Decider`.

      Note: `evolve` over a multi-event chain uses the existing
      `applyEvent`, which steps one letter edge. For event-by-event
      replay through a chain, the runtime adapter calls `evolve`
      repeatedly with each event in turn; intermediate states (in the
      user's `Vertex` enum, e.g. `Registering`) are observable
      mid-replay. This is the price of "the user owns the state
      space" in this approach. For chunk-replay across a logical
      command's events, callers use `Keiki.Core.applyEvents` (M2).

      Add a test spec
      `test/Keiki/DeciderMultiSpec.hs` asserting that
      `toMultiDecider userReg userRegDriverConfig` produces a `decide`
      that returns `[RegistrationStarted, ConfirmationEmailSent]` from
      a single `StartRegistration` command, even though `userReg`'s AST
      remains a letter FST.

- [x] **Milestone 4 — Worked example: `userRegDriverConfig`.**
      *(2026-05-02 — done.)* Added `userRegDriverConfig ::
      DriverConfig Vertex UserCmd` to
      `src/Keiki/Examples/UserRegistration.hs` (lines 477-498) and
      exported it under a new "Multi-event driver configuration
      (EP-20 M4)" section. Added an import of
      `Keiki.Decider.DriverConfig` to the module. Created
      `test/Keiki/Examples/UserRegistrationMultiSpec.hs` with the
      three planned assertions: `decide` via `toMultiDecider`
      returns the 2-element event list; `applyEvents` round-trips
      the same chunk to `(RequiresConfirmation, regs)` with email
      = "alice@x" and confirmCode = "Z9F4"; underlying
      single-event lift via `toDecider` is unchanged (length-1
      results from both letter edges in the chain). Wired into
      `test/Spec.hs` and `keiki.cabal`. Test count grew 155 →
      158; 0 failures.
      Original spec body retained below for reference:

          -- | Driver configuration for the multi-event façade. Marks
          -- 'Registering' as an internal vertex advanced by 'Continue';
          -- all other vertices are public.
          userRegDriverConfig :: DriverConfig Vertex UserCmd
          userRegDriverConfig = DriverConfig
            { isInternal = \case
                Registering -> Just Continue
                _           -> Nothing
            }

      Add the export to the module's export list under a new section
      "B-presentation views (TH-derived; see EP-13 / MP-5)" or a fresh
      "Multi-event driver configuration" section.

      The transducer itself (`userReg`) is unchanged. The vertex enum,
      command enum, edges, TH-derived InCtors/WireCtors/View — all
      stay as today. Only the `userRegDriverConfig` value is new.

      Add a test spec
      `test/Keiki/Examples/UserRegistrationMultiSpec.hs`:

      - One test asserts `decide` via `toMultiDecider userReg
        userRegDriverConfig` on `StartRegistration` returns the
        2-element event list.
      - One test asserts `applyEvents` on the same 2-event chunk
        round-trips to `(RequiresConfirmation, regs)` with registers
        populated.
      - One test asserts the underlying letter FST behavior is
        unchanged: `decide (toDecider userReg) (StartRegistration ..)
        (PotentialCustomer, emptyRegs)` returns `[RegistrationStarted ..]`
        (length 1, the letter form), and `decide (toDecider userReg)
        Continue (Registering, regs)` returns `[ConfirmationEmailSent ..]`
        (length 1). This is the regression test that confirms the
        AST-level behavior is unchanged.

      Wire the new spec into `test/Spec.hs` and `keiki.cabal`.

- [x] **Milestone 5 — `chainTo` DSL verb.** *(2026-05-02 —
      done.)* Added `chainTo` to `src/Keiki/Builder.hs` per the
      plan, with one signature adjustment recorded in the
      Decision Log: the post-state slot-set index is `'[]` rather
      than `w` (the plan's draft) so that `peUpdate` can reset to
      `UKeep`. Added a new `ChainPrefix` GADT for storing
      completed chain segments with existential `w` on the
      captured `Update`. Refactored `EdgeListBuilder` from
      `[Edge]`-only accumulator to `EdgeListAcc { elaMain,
      elaChain }` so chained-source edges from `chainTo`
      expansion can flow up to `from`. Updated `from` to merge
      chained-source edges into the `VertexBuilder` map (with a
      new `groupBySourceFirstSeen` helper preserving declaration
      order). Updated `buildTransducer` to merge
      duplicate-vertex entries via `concatMap+filter` instead of
      `lookup` (so `chainTo`'s implicit `Registering` entry and
      a hypothetical explicit `from Registering` would both be
      reachable). Added `from`'s `Eq v` constraint.
      Authored `userRegChained` in
      `src/Keiki/Examples/UserRegistration.hs` using `chainTo`
      between two `emit` calls in the `PotentialCustomer`
      `onCmd` block; dropped the explicit `from Registering`
      block. Created
      `test/Keiki/Examples/UserRegistrationChainedSpec.hs` (8
      assertions) mirroring `UserRegistrationBuilderSpec`'s
      pattern: `reconstitute` agreement, `isFinal` agreement,
      edge-count agreement, and per-step `applyEvent`
      agreement on all 5 events of the canonical log. Wired
      into `test/Spec.hs` and `keiki.cabal`. Test count grew
      158 → 166; 0 failures.
      Original spec body retained below for reference:

          -- | Within an 'onCmd' block, chain through the named
          -- intermediate vertex. The block following 'chainTo' is
          -- compiled to an ε-edge originating from the intermediate
          -- vertex; the events accumulated before 'chainTo' produce
          -- the first edge ending at the intermediate vertex.
          --
          -- The intermediate vertex must be a constructor of the user's
          -- 'Vertex' enum, and the chain advancement must be a
          -- constructor of the user's command enum. 'chainTo' takes
          -- both as label-style references compiled to the
          -- corresponding 'InCtor'.
          chainTo :: v -> InCtor ci '[] -> EdgeBuilder rs ci co v w w ()

      The compilation strategy: `chainTo Registering inCtorContinue`
      followed by `emit wireConfirmationEmailSent ...` produces:

      - A first edge from the current vertex (the `from`
        scope's vertex) emitting whatever events were accumulated
        before `chainTo`, with `target = Registering`.
      - A second edge from `Registering` with guard
        `matchInCtor inCtorContinue`, `update = UKeep`, output
        emitting whatever events are accumulated after `chainTo`, and
        `target = <next chainTo's vertex, or the goto target>`.

      A multi-`chainTo` block (length ≥ 3 events) is parsed left-to-
      right into a chain of letter edges through the named
      intermediates.

      Acceptance: write a new top-level binding
      `userRegChained :: SymTransducer ...` in
      `src/Keiki/Examples/UserRegistration.hs` that authors the
      `PotentialCustomer → RequiresConfirmation` chain using
      `chainTo Registering inCtorContinue` between the two `emit`s.
      Assert in the equivalence spec that `userRegChained`
      produces traces byte-identical to `userReg` (the existing
      builder-form transducer) on the canonical command sequence.
      The two builder forms must produce identical `Edge` lists
      because they describe the same letter FST — `chainTo` is a
      pure syntactic compression.

- [x] **Milestone 6 — Documentation update.** *(2026-05-02 —
      done.)* Updated the synthesis note's closing paragraph
      (was line 974) to name state refinement as the canonical
      multi-event model and list the three ergonomic primitives
      shipped by EP-20. Replaced the multi-event note's
      Recommendation section: explicit endorsement of Approach 1
      with the EP-20 ergonomic layer, explanation of why
      Approach 2 was deliberately not selected (citing
      MasterPlan 7's Vision & Scope reasons), and re-statement
      that Approach 3 is rejected as incompatible with the
      mechanically-derived-apply foundation.
      Original spec body retained below for reference:

      - `docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`
        line 974 ("the multi-event document's three approaches still
        apply (state refinement is the cleanest under the symbolic-
        register formalism, as the User Registration example shows)")
        — replace with: "State refinement is the canonical multi-event
        model. The library ships ergonomic support
        (`Keiki.Core.applyEvents`, `Keiki.Decider.toMultiDecider`, and
        — once Plan 15 lands — `Keiki.Builder.chainTo`) so that
        callers can drive multi-event chains end-to-end without
        observing the intermediate vertices. The AST stays a strict
        letter FST."
      - `docs/research/multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md`'s
        Recommendation section (currently "Default to Approach 3") —
        replace with: "Approach 1 (state refinement) is the canonical
        path. The library ships ergonomics — `applyEvents` for chunk
        replay, `toMultiDecider` for transparent driver chains, and
        `chainTo` for builder syntax — so the cost of authoring
        intermediate vertices is one declared constructor and one
        declared command per multi-event command. Approach 2 (GSM
        expansion) is documented and was deliberately not selected;
        Approach 3 (hand-written apply) is rejected as theoretically
        incompatible with the foundation."

- [x] **Milestone 7 — Commit.** *(In progress at commit time.)*
      Final test run before commit: `cabal build all` clean, 166
      examples, 0 failures (baseline 149 + 17 new across M2/M3/M4/M5).


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights
discovered during implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- **Decision**: `DriverConfig s ci` is a separate value supplied to
  `toMultiDecider` rather than a new field on `SymTransducer`.
  **Rationale**: the configuration is *meta about the user's state
  space* — which vertices are public, which are internal, what
  command advances them. It is not part of the formalism. Putting it
  outside `SymTransducer` keeps the formalism unchanged and lets
  multiple driver configurations exist for the same transducer
  (useful for testing or for runtimes that want different views of
  the same state machine).
  **Date**: 2026-05-02

- **Decision**: `evolve` on `toMultiDecider` is one-letter-edge,
  identical to `toDecider`'s `evolve`.
  **Rationale**: event-by-event replay through a chain genuinely
  passes through the user's intermediate vertices — they're real
  states the user declared. Auto-driving `evolve` would hide them,
  but since they're in the user's enum, hiding makes the value-level
  state of the system invisible mid-replay. Leaving `evolve` as
  letter-step gives runtime adapters full visibility. Chunk replay
  for end-to-end transparency is available via
  `Keiki.Core.applyEvents`.
  **Date**: 2026-05-02

- **Decision**: `applyEvents` is added to `Keiki.Core`, not
  `Keiki.Decider` or a new façade module.
  **Rationale**: it is a pure replay primitive, structurally a fold
  of `applyEvent`. Callers other than `Keiki.Decider` will want it
  (e.g., `Keiki.Acceptor`, `Keiki.Composition` testing). Placing it
  in `Keiki.Core` matches the placement of `reconstitute` and
  `applyEvent`.
  **Date**: 2026-05-02

- **Decision**: M5 (`chainTo` DSL verb) is soft-deferred behind Plan
  15.
  **Rationale**: Plan 15 specifies the entire builder DSL
  (`from`, `onCmd`, `emit`, `goto`, etc.). `chainTo` extends that
  surface; building it requires the `EdgeBuilder` monad to exist.
  Sequencing EP-20 to require Plan 15 as a hard dependency would
  serialize the work unnecessarily — the rest of EP-20 (M2, M3, M4,
  M6) is independent of the builder. The deferral plan is documented
  in M1's design note so Plan 15's implementation picks up `chainTo`
  cleanly.
  **Date**: 2026-05-02
  **Superseded 2026-05-02**: Plan 15 has now shipped (M0–M7
  complete). The deferral path is no longer needed; M5 is
  unconditional. M1's design note retains the deferral text only as
  a "what would have happened if Plan 15 had not landed" note.

- **Decision**: `chainTo`'s output slot-set index is `'[]`, not `w`.
  **Rationale**: the plan's draft signature was
  `chainTo :: v -> InCtor ci '[] -> EdgeBuilder rs ci co v w w ()`.
  During implementation, the type of `peUpdate` (which has type
  `Update rs w ci` where `w` is the current EdgeBuilder slot-set)
  needs to reset to `UKeep :: Update rs '[] ci` after `chainTo`,
  because the post-chain segment starts with no writes. The output
  slot-set of `chainTo` therefore must be `'[]` to type-check the
  reset. The shipped signature is
  `chainTo :: v -> InCtor ci '[] -> EdgeBuilder rs ci co v w '[] ()`.
  This has the side-benefit that the user can write to the same
  slot name on either side of a `chainTo` (different segments
  are different edges with their own update fields), which the
  draft `w w` signature would have prevented via the `Disjoint`
  constraint on `(.=)`.
  **Date**: 2026-05-02

- **Decision**: `EdgeListBuilder` accumulator changes from
  `[Edge]` to `{ elaMain :: [Edge], elaChain :: [(v, Edge)] }`;
  `buildTransducer`'s `edgesOut` switches from `lookup` to
  `concatMap snd . filter ((==v) . fst)`.
  **Rationale**: `chainTo` produces edges from a different
  source vertex than the surrounding `from` block. The simplest
  refactor that doesn't break the existing single-edge
  `onCmd`/`onEpsilon` path is to add a second accumulator slot
  for chained-source edges and have `from` distribute them into
  the `VertexBuilder` map. With chained edges flowing in,
  duplicate-vertex entries become possible (e.g. user writes
  both `from Registering ...` and an `chainTo Registering ...`
  via another vertex). The old `lookup` semantics would silently
  drop one entry; `concatMap+filter` preserves both, with the
  earlier-declared entry's edges checked first.
  **Date**: 2026-05-02

- **Decision**: The internal command (`Continue`) is *user-declared*,
  not library-synthesized.
  **Rationale**: the formalism doesn't distinguish internal from
  public commands at the AST level — all commands are constructors
  of `ci`. The user already declares `Continue` in their `UserCmd`
  enum (today's pattern); `DriverConfig` just records that
  `Registering` is advanced by `Continue`. Synthesizing
  `Continue` would require either a wrapper type (`Either UserCmd
  Synthetic`) — propagating to all consumers — or TH that mutates the
  user's enum, which Haskell doesn't permit cleanly.
  **Date**: 2026-05-02


## Outcomes & Retrospective

EP-20 shipped all seven milestones in one session on 2026-05-02.
Test count grew from 149 to 166 (17 new specs across M2/M3/M4/M5);
0 failures throughout.

What was achieved against the original purpose:

- *Multi-event façade works end-to-end.* `decide (toMultiDecider
  userReg userRegDriverConfig) (StartRegistration sd)
  (PotentialCustomer, emptyRegs)` returns the 2-element event list
  `[RegistrationStarted, ConfirmationEmailSent]` while the
  underlying letter FST is unchanged — `decide (toDecider userReg)
  StartRegistration ...` still returns a singleton ending at
  `Registering`.
- *Chunk-replay primitive in place.* `Keiki.Core.applyEvents`
  is a six-line fold of `applyEvent` from a caller-supplied start;
  it round-trips both the canonical 5-event log and a 2-event
  chunk for a single multi-event command.
- *Authoring sugar shipped.* `Keiki.Builder.chainTo` compresses
  the two-`from`-block authoring of a multi-event entrance into
  one `onCmd` body with a `chainTo` between two `emit`s. The
  cross-form equivalence test (`UserRegistrationChainedSpec`)
  confirms `userRegChained` produces identical `Edge`-level and
  per-step replay behavior to the existing builder-form
  `userReg`.
- *Foundation preserved.* The `Keiki.Core.Edge` declaration is
  unchanged; every existing analysis (`omega`, `applyEvent`,
  `step`, `reconstitute`, `checkHiddenInputs`, the symbolic
  emptiness story) keeps its signature and body. `toDecider` is
  unchanged. The 152-line `userReg` builder block is preserved
  byte-for-byte.

Surprises discovered during implementation (also recorded in the
Decision Log):

- The plan's draft `chainTo :: ... EdgeBuilder rs ci co v w w ()`
  signature was not type-correct. The post-state slot-set must be
  `'[]` to allow `peUpdate` to reset to `UKeep`. The shipped
  signature `EdgeBuilder rs ci co v w '[] ()` has a useful
  side-effect: it lets the user reuse slot names across a
  `chainTo` boundary, which the draft signature would have
  rejected via `Disjoint`.
- The plan implicitly assumed `EdgeListBuilder`'s `[Edge]`
  accumulator was sufficient; chained-source edges from `chainTo`
  expansion required a second accumulator slot. Refactor:
  `EdgeListBuilder` now carries `EdgeListAcc { elaMain, elaChain
  }` with chained-source pairs flowing up to `from`. Side-effect:
  `buildTransducer`'s `edgesOut` now uses `concatMap+filter`
  instead of `lookup` so duplicate-vertex entries (which can
  arise when `chainTo`'s implicit registration coexists with an
  explicit `from`) merge their edge lists in declaration order.

Gaps / follow-ups not pursued:

- Multi-`chainTo` (chains of length ≥ 3) work in principle (the
  `walk` helper in `explodePartialEdge` handles the recursive
  case) but no spec exercises a 3+-event chain. Adding one is a
  trivial follow-up.
- The plan's M3 Decision Log entry sketched a possible
  `evolveStreaming :: InFlight s co -> ...` field on `Decider`.
  The shipped implementation goes the simpler route: `evolve` on
  the multi-decider is single-letter-step, identical to
  `toDecider`'s, and chunk replay across a logical command's
  events uses `applyEvents` from `Keiki.Core`. Mid-replay state
  is observable as the user-declared `Registering` vertex, which
  is a feature, not a bug.
- The plan's M5 originally floated a "soft-defer behind Plan 15"
  fallback. Plan 15 had shipped before EP-20 began, so the
  fallback was unused; the deferral text remains in the design
  note (`docs/research/multi-decider-via-state-refinement.md`,
  §6) for posterity.

Lessons:

- Indexed-monad type indices (the slot-set tracking in
  `EdgeBuilder`) and value-level state (the `peUpdate` field)
  must agree at every step. When introducing a new "reset"
  primitive (`chainTo`), the type-level reset must precede the
  value-level reset in the design — and the most natural reset
  is to `'[]` rather than the prior `w`.
- `Prelude.lookup`-backed maps silently drop duplicates; if a new
  feature can produce duplicates by design, switch to a merging
  combinator (`concatMap+filter`) at the consumer instead of
  trying to forbid duplicates at the producer.


## Context and Orientation

The keiki library lives at `/Users/shinzui/Keikaku/bokuno/keiki/`. The
pure core under `src/Keiki/` is a Haskell implementation of the
symbolic-register transducer formalism specified in
`docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`.
This plan adds new module-level definitions and a new test spec; the
AST remains unchanged.

**The current AST.** `src/Keiki/Core.hs:411-419`:

    data Edge phi rs ci co s = Edge
      { guard  :: phi
      , update :: Update rs ci
      , output :: Maybe (OutTerm rs ci co)
      , target :: s
      }

`output = Nothing` is an ε-edge (transition with no observable event);
`output = Just o` produces exactly one event. This declaration is
preserved unchanged by this plan.

**State refinement today.**
`src/Keiki/Examples/UserRegistration.hs` ships the canonical worked
example with state refinement. Multi-event command
`StartRegistration` is split into two letter edges:

    PotentialCustomer ->
      [ Edge { guard = isStart, update = ..., 
               output = Just $ pack inCtorStart wireRegistrationStarted ...,
               target = Registering } ]

    Registering ->
      [ Edge { guard = isContinue, update = UKeep,
               output = Just $ pack inCtorContinue wireConfirmationEmailSent ...,
               target = RequiresConfirmation } ]

The first edge fires on `StartRegistration` from `PotentialCustomer`
and emits `RegistrationStarted`. The state lands in the intermediate
vertex `Registering`. To progress further the runtime fires
`Continue` (the synthetic internal command); the second edge fires
and emits `ConfirmationEmailSent`, ending in `RequiresConfirmation`.
This is two `decide` calls and two `applyEvent` calls from the
caller's perspective today.

**The existing `Keiki.Decider`.**
`src/Keiki/Decider.hs:108-119`:

    toDecider
      :: BoolAlg phi (RegFile rs, ci)
      => SymTransducer phi rs s ci co
      -> Decider ci co (s, RegFile rs)
    toDecider t = Decider
      { decide = \cmd (s, regs) -> case omega t s regs cmd of
          Just co -> [co]
          Nothing -> []
      , evolve = \(s, regs) ev -> case applyEvent t s regs ev of
          Just (s', regs') -> (s', regs')
          Nothing          -> (s, regs)
      , initialState = (initial t, initialRegs t)
      , isTerminal   = \(s, _regs) -> isFinal t s
      }

The plan extends this module with `DriverConfig` and `toMultiDecider`
(see M3). The existing `toDecider` is preserved unchanged; users who
do not need the multi-event façade keep using it.

**The existing reconstitution.**
`src/Keiki/Core.hs:617-630`:

    reconstitute
      :: BoolAlg phi (RegFile rs, ci)
      => SymTransducer phi rs s ci co
      -> [co]
      -> Maybe (s, RegFile rs)
    reconstitute t = go (initial t, initialRegs t)
      where
        go acc []         = Just acc
        go (s, regs) (co : rest) = do
          next <- applyEvent t s regs co
          go next rest

This plan adds `applyEvents` (M2) — same fold structure but with a
caller-supplied start state. Both functions coexist.

**Plan 15 status.**
`docs/plans/15-edge-builder-monadic-dsl-for-authoring-symtransducer-edges.md`
shipped on 2026-05-02 with all milestones complete (M0–M7). The
`Keiki.Builder` module exists at `src/Keiki/Builder.hs` and exports
the full monadic DSL: `buildTransducer`, `from`, `onCmd`,
`onEpsilon`, `(.=)`, `slot`, `emit`, `emitWith`, `noEmit`, `goto`,
`requireEq`, `requireGuard`. The internal accumulator
`PartialEdge rs ci co v (w :: [Symbol])` (declared at
`src/Keiki/Builder.hs:235-260`) holds a single optional `OutTerm`,
mirroring the AST's `Maybe (OutTerm rs ci co)`.

EP-20's M5 adds a new verb `chainTo` to this module. The verb
compiles a multi-`emit` block into a sequence of letter edges
through user-named intermediate vertices; it is purely a syntactic
compression that produces the same letter-FST `Edge` values that a
hand-written builder block (with `goto` to the intermediate, then a
separate `from intermediate $ onCmd ...`) would produce. The
existing `emit` semantics (single event per `onCmd` block) is
preserved; `chainTo` partitions the block at the chain point.

**Builder-form aggregates.** Both example aggregates have been
migrated to the builder. The current shape:

- `src/Keiki/Examples/EmailDelivery.hs:153-156` declares
  `emailDelivery` via `B.buildTransducer EmailPending
  emptyEmailRegs (...)`. Lines 182-202 declare `emailDeliveryAST`
  preserving the AST form for cross-form equivalence
  (`test/Keiki/Examples/EmailDeliveryBuilderSpec.hs`).
- `src/Keiki/Examples/UserRegistration.hs:284-360` declares
  `userReg` via `B.buildTransducer PotentialCustomer emptyRegs
  (...)`. Lines 361-470 declare `userRegAST` preserving the AST
  form. The cross-form equivalence test is
  `test/Keiki/Examples/UserRegistrationBuilderSpec.hs`.

EP-20's M4 (add `userRegDriverConfig`) is purely additive at the
module level — the transducer definition is unchanged in either
form. M5 adds a new top-level `userRegChained` (or similar) that
authors the `PotentialCustomer → RequiresConfirmation` chain
using `chainTo` and asserts equivalence to `userReg`.

**The example aggregate this plan demonstrates on.**
`src/Keiki/Examples/UserRegistration.hs:163-176` declares the vertex
enum:

    data Vertex
      = PotentialCustomer
      | Registering
      | RequiresConfirmation
      | Confirmed
      | Deleted
      deriving (Eq, Show, Enum, Bounded)

`Registering` is the intermediate vertex used by state refinement.
This plan does not modify the enum; it only adds a `userRegDriverConfig`
value declaring `Registering` internal.

**Test infrastructure.** Tests live under `test/`. The entry point
`test/Spec.hs` imports each spec module qualified and registers it
under hspec's `describe`. New specs added by this plan must be wired
in there and listed in `keiki.cabal`'s `keiki-test:other-modules`.
The full suite is run via `nix-shell -p z3 --run "cabal test all"`
because the SBV-backed symbolic specs require z3 in PATH.

**MasterPlan parent.** This plan is one of two alternatives under
`docs/masterplans/7-multi-event-command-support-gsm-widening-vs-state-refinement-ergonomics.md`.
The MasterPlan recommends this plan (EP-20) over EP-19 (the GSM
widening alternative). Selecting EP-20 cancels EP-19; the cancellation
is recorded in the MasterPlan's Decision Log.


## Plan of Work

Seven milestones. Effort estimate: 4–7 hours total. The plan is
additive throughout; no AST changes; no cascade-fix work.

**Milestone 0 — Baseline.** Confirm the working tree builds and the
test suite passes:

    cd /Users/shinzui/Keikaku/bokuno/keiki
    cabal build all
    nix-shell -p z3 --run "cabal test all" 2>&1 | tail -3

Expected: `110 examples, 0 failures` (per master at plan-draft time).
Confirm `Vertex` and `UserCmd` in `src/Keiki/Examples/UserRegistration.hs`
still have `Registering` and `Continue`. Confirm
`Keiki.Decider.toDecider` is exported and works.

Check Plan 15's status:

    grep -A 2 '^- \[' docs/plans/15-edge-builder-monadic-dsl-for-authoring-symtransducer-edges.md \
      | head -30

If any milestones are checked, Plan 15 is in progress; record the
state in Progress so M5 can re-check.

**Milestone 1 — Design note.** Create
`docs/research/multi-decider-via-state-refinement.md`. Sections:

1. *Problem statement.* Letter FST today; multi-event commands
   require state refinement. The user authoring a new aggregate
   with a multi-event command pays one extra vertex constructor and
   one extra command constructor. Caller side, today driving the
   chain requires multiple `decide` calls.

2. *Why state refinement is the canonical path.* Cite synthesis note
   line 974, Approach 1 in
   `docs/research/multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md`.
   Letter FST preserves: per-edge `solveOutput` invertibility;
   per-edge `checkHiddenInputs` decidability; vertex enumeration via
   `(Bounded, Enum)`; clean composition; clean diagram generation;
   alignment with future dependent-typing.

3. *The three-piece ergonomics layer.*
   - `applyEvents` for chunk replay (a fold of `applyEvent`).
   - `DriverConfig` + `toMultiDecider` for transparent driver chains
     (auto-advance through internal vertices on `decide`).
   - `chainTo` builder verb (Plan 15 follow-up) for syntactic
     compression of multi-event authoring.

4. *What's preserved.* Every existing API and every existing
   analysis. The AST is unchanged. UserRegistration's existing
   shape is unchanged.

5. *What's not in scope.* AST widening (covered by EP-19, the
   alternative). Hand-written apply (Approach 3, rejected as
   incompatible with the foundation). A parallel formalism module.

6. *M5 deferral plan.* If Plan 15 has not landed by the time EP-20
   reaches M5, EP-20 closes after M4, M6, M7. Plan 15's
   implementation absorbs `chainTo` per this design note's M5
   specification.

Acceptance: file exists, ~150-200 lines, covers all sections.

**Milestone 2 — `applyEvents`.** Add the function and its export
to `src/Keiki/Core.hs`. Add the test spec
`test/Keiki/CoreApplyEventsSpec.hs`. Wire into `test/Spec.hs` and
`keiki.cabal`. Run tests.

Acceptance: `cabal test all` passes, including the three new
`CoreApplyEventsSpec` assertions.

**Milestone 3 — `DriverConfig` + `toMultiDecider`.** Edit
`src/Keiki/Decider.hs` per the M3 specification in Progress. Add the
test spec `test/Keiki/DeciderMultiSpec.hs` with:

- One assertion that `toMultiDecider t cfg` produces a `Decider`
  whose `decide` returns the expected event list for each command in
  the user's `ci` enum.
- One assertion that internal vertices are not surfaced as
  `decide`'s output: after a `decide` call lands the public state in
  `RequiresConfirmation`, `decide` was internally driven through
  `Registering` but the caller never sees that.

Wire into `test/Spec.hs` and `keiki.cabal`. Run tests.

Acceptance: `cabal test all` passes; the new tests demonstrate
multi-event-via-driver behavior on UserRegistration.

**Milestone 4 — `userRegDriverConfig`.** Edit
`src/Keiki/Examples/UserRegistration.hs` to add and export
`userRegDriverConfig`. Add the test spec
`test/Keiki/Examples/UserRegistrationMultiSpec.hs` with the three
assertions from Progress. Wire into `test/Spec.hs` and
`keiki.cabal`. Run tests.

Acceptance: `cabal test all` passes; the new spec asserts the
multi-event façade produces the expected 2-element event list and
the underlying letter-FST behavior is unchanged.

**Milestone 5 — `chainTo` builder verb (deferred or in-place).**
Re-check Plan 15's status. If `Keiki.Builder` exists:

- Add `chainTo` per the M5 specification.
- Rewrite `userRegEdges`'s `PotentialCustomer` case using `chainTo`
  in a separate top-level `userRegBuilder`-style binding (kept
  alongside the AST-form `userRegEdges` for cross-form equivalence
  testing per Plan 15's pattern).
- Add a cross-form equivalence test asserting the two transducers
  produce identical traces on the canonical command sequence.

If `Keiki.Builder` does not exist, mark M5 as deferred. The Plan 15
implementation will absorb `chainTo` per M1's design note.

**Milestone 6 — Documentation update.** Edit synthesis note line
974; edit multi-event note's Recommendation. Both edits per the M6
specification in Progress.

**Milestone 7 — Commit.** Stage and commit per Concrete Steps.


## Concrete Steps

All commands run from `/Users/shinzui/Keikaku/bokuno/keiki/`.

**M0:**

    cabal build all
    nix-shell -p z3 --run "cabal test all" 2>&1 | tail -3

    grep -n 'Registering\|Continue' src/Keiki/Examples/UserRegistration.hs \
      | head -10

    head -30 docs/plans/15-edge-builder-monadic-dsl-for-authoring-symtransducer-edges.md

**M1:** Create the design note. Use the section structure above.

**M2:** Edit `src/Keiki/Core.hs`:

- Add the `applyEvents` function near `reconstitute` (around line
  617).
- Add `applyEvents` to the module's export list (near `reconstitute`,
  around line 75).

Create `test/Keiki/CoreApplyEventsSpec.hs`:

    module Keiki.CoreApplyEventsSpec (spec) where
    
    import Test.Hspec
    import Keiki.Core (applyEvents, initial, initialRegs, ...)
    import Keiki.Examples.UserRegistration

    spec :: Spec
    spec = describe "applyEvents" $ do
      it "round-trips the canonical UserRegistration log" $ do
        let log_ = canonicalUserRegLog   -- defined in the spec or imported
        applyEvents userReg (initial userReg, initialRegs userReg) log_
          `shouldSatisfy` ...
      ...

Wire `Keiki.CoreApplyEventsSpec` into `test/Spec.hs` and
`keiki.cabal`. Run tests.

**M3:** Edit `src/Keiki/Decider.hs` per M3 spec. Create
`test/Keiki/DeciderMultiSpec.hs`. Wire and run.

**M4:** Edit `src/Keiki/Examples/UserRegistration.hs` to add
`userRegDriverConfig`. Create
`test/Keiki/Examples/UserRegistrationMultiSpec.hs`. Wire and run.

**M5:** Edit `src/Keiki/Builder.hs` to add the `chainTo` verb (the
module exists; Plan 15 shipped). Add a `userRegChained` binding to
`src/Keiki/Examples/UserRegistration.hs` that authors the chain
via `chainTo`. Extend
`test/Keiki/Examples/UserRegistrationBuilderSpec.hs` (or add a
parallel spec) with a cross-form equivalence assertion comparing
`userRegChained` to `userReg`. Run tests.

**M6:** Edit docs.

**M7:** Stage and commit:

    git add src/Keiki/Core.hs src/Keiki/Decider.hs \
            src/Keiki/Examples/UserRegistration.hs \
            test/Keiki/CoreApplyEventsSpec.hs \
            test/Keiki/DeciderMultiSpec.hs \
            test/Keiki/Examples/UserRegistrationMultiSpec.hs \
            test/Spec.hs keiki.cabal \
            docs/research/multi-decider-via-state-refinement.md \
            docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md \
            docs/research/multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md \
            docs/plans/20-multi-event-commands-via-state-refinement-ergonomics.md \
            docs/masterplans/7-multi-event-command-support-gsm-widening-vs-state-refinement-ergonomics.md

    # If M5 landed, also add src/Keiki/Builder.hs and the cross-form spec.

    git commit -m "$(cat <<'EOF'
    feat(decider): EP-20 — state-refinement ergonomics for multi-event commands

    Add applyEvents to Keiki.Core (chunk replay), DriverConfig +
    toMultiDecider to Keiki.Decider (transparent driver chains
    through user-declared internal vertices), and userRegDriverConfig
    to the UserRegistration example. The AST remains a strict letter
    FST; multi-event commands are handled by user-declared
    intermediate vertices with library-driven chaining.

    MasterPlan: docs/masterplans/7-multi-event-command-support-gsm-widening-vs-state-refinement-ergonomics.md
    ExecPlan: docs/plans/20-multi-event-commands-via-state-refinement-ergonomics.md
    Intention: intention_01kqmjp9k8e478db6xjah31455
    EOF
    )"


## Validation and Acceptance

After all seven milestones (M5 unconditional now that Plan 15 has
shipped):

- `cabal build all` succeeds with no warnings.
- `nix-shell -p z3 --run "cabal test all"` reports the master
  baseline (re-recorded at M0; ≥110 from earlier baseline plus
  Plan 15's added specs) + ≥7 examples (3 from M2, 2 from M3,
  3 from M4, ≥1 from M5), 0 failures.
- `docs/research/multi-decider-via-state-refinement.md` exists.
- `Keiki.Core.applyEvents` is exported with the signature documented
  in M2.
- `Keiki.Decider.DriverConfig` and `Keiki.Decider.toMultiDecider` are
  exported.
- `Keiki.Examples.UserRegistration.userRegDriverConfig` is exported.
- `docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`
  line 974 is updated.

Behavioral acceptance (the load-bearing tests):

1. **Multi-event decide via façade.** Given the multi-event decider
   `mdec = toMultiDecider userReg userRegDriverConfig`,
   `decide mdec (StartRegistration sd) (PotentialCustomer, emptyRegs)`
   returns a 2-element list `[RegistrationStarted ...,
   ConfirmationEmailSent ...]` in that order, ending in
   `RequiresConfirmation`.

2. **Underlying letter FST unchanged.** `decide (toDecider userReg)
   (StartRegistration sd) (PotentialCustomer, emptyRegs)` returns
   `[RegistrationStarted ...]` (length 1), ending in `Registering`.
   `decide (toDecider userReg) Continue (Registering, regs)` returns
   `[ConfirmationEmailSent ...]` (length 1), ending in
   `RequiresConfirmation`. The AST is unchanged.

3. **Chunk replay round-trips.** `applyEvents userReg
   (PotentialCustomer, emptyRegs) [RegistrationStarted ...,
   ConfirmationEmailSent ...]` returns `Just (RequiresConfirmation,
   regs)` with `regs ! #email == "alice@x"`.

4. **Streaming replay through the chain works.** Two consecutive
   `applyEvent` calls — one with `RegistrationStarted` from
   `(PotentialCustomer, emptyRegs)`, one with `ConfirmationEmailSent`
   from the resulting `(Registering, regs)` — end at
   `(RequiresConfirmation, regs)`. The intermediate `Registering`
   state is observable to the caller (which is the price of state
   refinement).

5. **`isInternal` correctly classifies.**
   `isInternal userRegDriverConfig Registering` is `Just Continue`;
   for every other vertex it is `Nothing`.

6. **Builder cross-form equivalence (M5).** The
   `chainTo`-authored `userRegChained` produces byte-identical
   traces to the existing builder-form `userReg` on the canonical
   command sequence.


## Idempotence and Recovery

The plan is fully additive:

- M0 reads only.
- M1 creates a new file.
- M2 adds a new function and a new test spec.
- M3 adds new types and a new test spec.
- M4 adds a new exported value and a new test spec.
- M5 adds a builder verb and a cross-form spec
  (`Keiki.Builder` is shipped; M5 is unconditional).
- M6 edits two existing docs.
- M7 stages and commits.

No existing API is modified; no existing test broken. Each milestone
can be tested independently by running `cabal test all` after the
edit.

Recovery from a failing test in M3:

- `driveDecide`'s loop terminates when `step` returns `Nothing` or
  `isInternal` returns `Nothing`. If the loop diverges in tests,
  the `DriverConfig` is mis-declared (e.g. a public vertex marked
  internal or vice versa). Inspect `userRegDriverConfig` in M4 to
  match the test's `cfg`.

Recovery from a failing M5 build:

- The builder DSL is well-tested (Plan 15's M6 covers it). If
  `chainTo` introduces a type error in `Keiki.Builder`, isolate by
  reverting just the verb addition; the existing `from`/`onCmd`/
  `emit`/`goto` surface stays untouched.

Recovery from a bad commit:

- `git revert` and reopen.


## Interfaces and Dependencies

New types and functions:

    -- src/Keiki/Core.hs (additive)
    applyEvents
      :: BoolAlg phi (RegFile rs, ci)
      => SymTransducer phi rs s ci co
      -> (s, RegFile rs) -> [co]
      -> Maybe (s, RegFile rs)

    -- src/Keiki/Decider.hs (additive)
    newtype DriverConfig s ci = DriverConfig
      { isInternal :: s -> Maybe ci }

    toMultiDecider
      :: BoolAlg phi (RegFile rs, ci)
      => SymTransducer phi rs s ci co
      -> DriverConfig s ci
      -> Decider ci co (s, RegFile rs)

    -- src/Keiki/Examples/UserRegistration.hs (additive)
    userRegDriverConfig :: DriverConfig Vertex UserCmd

    -- src/Keiki/Builder.hs (M5 — additive; Plan 15 shipped)
    chainTo :: v -> InCtor ci '[] -> EdgeBuilder rs ci co v w w ()

Modified modules:

- `Keiki.Core` (additive only) — adds `applyEvents`.
- `Keiki.Decider` (additive only) — adds `DriverConfig`,
  `toMultiDecider`. The existing `Decider` record and `toDecider`
  are preserved unchanged.
- `Keiki.Examples.UserRegistration` (additive only) — adds
  `userRegDriverConfig`.
- `Keiki.Builder` (M5 — additive) — adds `chainTo`. The module
  exists at `src/Keiki/Builder.hs` from Plan 15.

New test specs:

- `test/Keiki/CoreApplyEventsSpec.hs`
- `test/Keiki/DeciderMultiSpec.hs`
- `test/Keiki/Examples/UserRegistrationMultiSpec.hs`
- (M5) extension of `test/Keiki/Examples/UserRegistrationBuilderSpec.hs`
  to add a cross-form equivalence assertion comparing
  `userRegChained` to `userReg` — or a new sibling spec
  `UserRegistrationChainedSpec.hs` if the existing spec is busy.

Existing functions consumed:

- `Keiki.Core.step` — used by `driveDecide` to advance state and
  collect events.
- `Keiki.Core.applyEvent` — used by `applyEvents` to fold over a
  chunk.
- `Keiki.Core.omega`, `Keiki.Core.delta` — unchanged; new façade
  uses `step` which is built on them.

No new external dependencies. The existing `template-haskell`,
`sbv`, `text`, `time` are sufficient.

The MasterPlan parent
(`docs/masterplans/7-multi-event-command-support-gsm-widening-vs-state-refinement-ergonomics.md`)
documents this plan's relationship to its alternative
`docs/plans/19-multi-event-commands-via-edge-output-widening-gsm-expansion.md`.
The two plans are mutually exclusive: selecting EP-20 cancels EP-19
and vice versa. The MasterPlan recommends EP-20 (this plan).


## Revision Notes

- **2026-05-02 (initial draft)**: plan created with M5 documented as
  soft-deferred behind Plan 15.

- **2026-05-02 (Plan 15 shipped)**: Plan 15 completed all milestones
  (M0–M7) on master before any work on EP-20 began. `Keiki.Builder`
  is in place; both example aggregates are now in builder form
  (`userReg`, `emailDelivery`) with AST forms preserved as
  `userRegAST`, `emailDeliveryAST` for cross-form equivalence
  testing. Updated:
  - **Purpose / Big Picture**: M5 is no longer conditional; the
    soft-defer note is preserved for posterity.
  - **Progress**: M5 milestone description is unconditional.
  - **Plan of Work**: M5 paragraph rewritten to author a
    `userRegChained` value via `chainTo` and assert cross-form
    equivalence to the existing builder-form `userReg`.
  - **Concrete Steps M5**: removed the "if Plan 15 implemented…"
    branch.
  - **Validation and Acceptance**: M5 is now a load-bearing
    acceptance item.
  - **Idempotence and Recovery**: replaced M5 deferral guidance
    with builder-edit recovery guidance.
  - **Interfaces and Dependencies**: `chainTo` signature corrected
    to match Plan 15's `EdgeBuilder rs ci co v w w` shape (not the
    earlier sketched `phi rs ci co s` shape that pre-dated
    Plan 15's monad design).
  - **Decision Log**: amended the M5-defer entry with a "Superseded"
    note.
  - **Context and Orientation**: added a "Builder-form aggregates"
    paragraph documenting `userReg`/`userRegAST` and
    `emailDelivery`/`emailDeliveryAST`.
