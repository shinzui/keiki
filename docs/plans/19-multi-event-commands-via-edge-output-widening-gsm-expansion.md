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

- [ ] **Milestone 0 — Verify prerequisites.** Run `cabal build all` and
      `nix-shell -p z3 --run "cabal test all"`. Record the test count
      (master grew after Plan 15's specs landed; re-record at plan
      start) and GHC version. Inventory every site that pattern-matches
      `Maybe (OutTerm ...)` or constructs `Just (OPack ...)` / `Nothing`
      for an edge `output` field via `git grep`. Record the count in the
      Progress section so M2 can verify completeness.

      Plan 15 (`docs/plans/15-edge-builder-monadic-dsl-for-authoring-symtransducer-edges.md`)
      shipped on 2026-05-02 with all milestones complete; this adds
      `src/Keiki/Builder.hs` (683 lines on master) to the inventory.
      The builder's internal `PartialEdge rs ci co v (w :: [Symbol])`
      (declared at `src/Keiki/Builder.hs:235-260`) holds a single
      optional `OutTerm`, mirroring today's AST. M2 must widen this
      accumulator alongside the AST and adapt `emit`/`noEmit`
      semantics so multiple `emit` calls in one `onCmd` block
      append rather than fail or replace. Re-grep specifically:

          git grep -n 'PartialEdge\|peOutput\|emit ::\|noEmit\|Maybe.*OutTerm' \
            -- src/Keiki/Builder.hs test/Keiki/Builder*.hs

      Both example aggregates have been migrated to builder form
      (`emailDelivery`, `userReg` are now built via
      `B.buildTransducer`; the AST forms are preserved as
      `emailDeliveryAST`, `userRegAST` for cross-form equivalence
      tested by `test/Keiki/Examples/EmailDeliveryBuilderSpec.hs`
      and `test/Keiki/Examples/UserRegistrationBuilderSpec.hs`).
      M7's UserRegistration migration must edit both forms
      (`userReg` builder block and `userRegAST` literal) and re-run
      both the per-form behavior specs and the cross-form
      equivalence spec.

- [ ] **Milestone 1 — Design note.** Write `docs/research/gsm-widening-design.md`
      (~200 lines). Cover: the formal mapping from letter FST to GSM (cite
      Approach 2 in `docs/research/multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md`);
      the `InFlight s co` wrapper for single-event-streaming replay; what's
      preserved (per-`OutTerm` `solveOutput` invertibility, per-edge guard
      evaluation, vertex enumeration via `(Bounded, Enum)`); what changes
      (the hidden-input check fires on edge-list union; composition
      concatenates lists; `omega` returns `[co]`); what's deferred
      (conditional output lists where the list shape depends on the input —
      these still require multiple disjoint-guarded edges per the existing
      pattern).

- [ ] **Milestone 2 — Widen `Edge.output` and adapt the core operators.**
      Edit `src/Keiki/Core.hs`:
      - Change the `output` field's type from `Maybe (OutTerm rs ci co)` to
        `[OutTerm rs ci co]`.
      - Adapt `omega :: ... -> Maybe co` to `omega :: ... -> [co]`. The body
        evaluates each `OutTerm` in the edge's list and returns the
        concatenation.
      - Adapt `step :: ... -> Maybe (s, RegFile rs, Maybe co)` to
        `step :: ... -> Maybe (s, RegFile rs, [co])` returning the list.
      - Adapt every internal pattern-match on the old `Maybe`. Notably:
        `applyEvent` (line 564 today) must change semantics — see M3.
        `checkHiddenInputs`'s `edgeReasons` (line 714) must walk the list.
      - The `pack` helper at line 449 stays unchanged (it constructs one
        `OutTerm`); a new helper `silent :: [OutTerm rs ci co] = []` may be
        added to express ε-edges in DSL surface, replacing today's
        `Nothing`.

      Cascade-fix every call site that constructs an edge: replace
      `output = Just o` with `output = [o]` and `output = Nothing` with
      `output = []`. Run `cabal build all`; expect compile errors at every
      remaining site, fix them, until `cabal build all` succeeds.

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
      - Update `Keiki.Builder`'s haddock and the spike module
        `test/Keiki/BuilderSpike.hs` to reflect the new semantics.
      - Update `test/Keiki/BuilderSpec.hs` to add tests for two
        `emit`s producing a length-2 list.

      Tests should still pass with single-emit blocks behaving
      identically (length-1 list = today's `[Just o]` semantics).

- [ ] **Milestone 3 — `InFlight` and `applyEvents`.** Add to
      `src/Keiki/Core.hs`:

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

- [ ] **Milestone 4 — Strengthen `checkHiddenInputs`.** Edit
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

- [ ] **Milestone 5 — Adapt `Keiki.Decider`.** Edit
      `src/Keiki/Decider.hs`:

      - Update the docstring to retire the "at most one event per
        command" caveat (currently lines 30-39).
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

      Acceptance: existing
      `test/Keiki/DeciderSpec.hs` continues to pass after rebuild. Add
      one new test asserting that `decide` over a multi-event edge
      returns the full `[e]` list of length 2.

- [ ] **Milestone 6 — Adapt `Keiki.Composition`.** Edit
      `src/Keiki/Composition.hs:401-447`. The current `composeEdge`
      pattern-matches on `output e1`'s `Just (OPack ...)`; with the
      widened `output :: [OutTerm rs1 ci1 mid]`, sequential composition
      must:

      - For each `OutTerm` in `output e1`, find the corresponding edge in
        the second transducer whose guard accepts that mid-symbol, and
        compose: substitute `e1`'s `OutTerm` for the second edge's input
        reads using the existing `substOut` machinery.
      - Concatenate the resulting list of `OutTerm`s for the composed
        edge's `output`.

      For length-1 `output e1`, behavior is identical to today's. For
      length-0 (ε-edge in the first transducer), the composed edge has
      `output = []`. For length-2+ (a multi-event edge in the first
      transducer), the composition fans out across the second
      transducer's edges per mid-symbol.

      Acceptance: `test/Keiki/CompositionSpec.hs` continues to pass. Add
      one new test composing a two-aggregate pipeline where the first
      aggregate has a multi-event edge; assert the composed edge
      produces the expected concatenated event list.

- [ ] **Milestone 7 — Worked example: collapse UserRegistration's
      `Registering`.** Edit `src/Keiki/Examples/UserRegistration.hs`.
      The file declares the transducer twice on master:
      - `userReg` (lines 284-360) — built via
        `B.buildTransducer PotentialCustomer emptyRegs (...)`. This
        is the canonical form used by all consumer specs.
      - `userRegAST` (lines 361-470) — preserved AST form for
        cross-form equivalence testing
        (`test/Keiki/Examples/UserRegistrationBuilderSpec.hs`).

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

      Cascade-fix `test/Keiki/Examples/UserRegistrationSpec.hs`,
      `test/Keiki/Examples/UserRegistrationViewSpec.hs`, and
      `test/Keiki/Examples/UserRegistrationBuilderSpec.hs` if they
      reference `Registering` or `Continue` directly. The
      cross-form equivalence spec must continue to pass — both
      forms now describe the same length-2 edge. Most behavior
      assertions should be unaffected because the user-observable
      event sequence is identical.

      Add `test/Keiki/Examples/UserRegistrationGSMSpec.hs`:

      - One test asserts `decide` on `StartRegistration` returns a
        2-element event list `[RegistrationStarted ..,
        ConfirmationEmailSent ..]` in that order.
      - One test asserts `applyEvents` round-trips a 5-event canonical
        log to the expected `(s, RegFile rs)` final state.
      - One test asserts the chunked `applyEvents` and the streaming
        `applyEvent` over `InFlight` produce identical final states.

      Wire the new spec into `test/Spec.hs` and `keiki.cabal`.

      Acceptance: full test suite passes; line count of
      `src/Keiki/Examples/UserRegistration.hs` drops by ~30 lines (one
      vertex, one command, one edge block removed).

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

**The current AST.** `src/Keiki/Core.hs:411-419` defines the `Edge` record:

    data Edge phi rs ci co s = Edge
      { guard  :: phi
      , update :: Update rs ci
      , output :: Maybe (OutTerm rs ci co)
      , target :: s
      }

`output = Nothing` is an ε-edge (transition with no observable event);
`output = Just o` produces exactly one event by evaluating `o`. The plan
widens `output` to `[OutTerm rs ci co]` so length-0 reproduces ε, length-1
reproduces today's letter behavior, and length-2+ admits multi-event
commands.

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

**Existing call sites that touch `output`.** As of master at plan-draft
time (note: the example modules' call-site lines moved when Plan 15
migrated them to builder form; the AST-form `*ASTEdges` functions now
contain the call sites):

    src/Keiki/Core.hs:411           (declaration)
    src/Keiki/Core.hs:564,569       (omega)
    src/Keiki/Core.hs:586-611       (applyEvent)
    src/Keiki/Core.hs:711-720       (checkHiddenInputs / detectMissingInCtorFields)
    src/Keiki/Composition.hs:411-447 (composeEdge)
    src/Keiki/Decider.hs:36-39      (docstring caveat about "at most one event")
    src/Keiki/Builder.hs:235-260    (PartialEdge accumulator — Plan 15)
    src/Keiki/Builder.hs (emit/noEmit/finalize sites — Plan 15)
    src/Keiki/Examples/UserRegistration.hs (userRegASTEdges — AST form)
    src/Keiki/Examples/UserRegistrationV0.hs (still AST-form)
    src/Keiki/Examples/EmailDelivery.hs (emailDeliveryASTEdges — AST form)
    test/Keiki/CoreSpec.hs:64
    test/Keiki/CompositionSpec.hs:130
    test/Keiki/SymbolicSpec.hs:202,207,226,231

M0's first task is to re-run `git grep` to confirm this enumeration is
current after Plan 15's migration. The builder-form transducers
(`userReg`, `emailDelivery`) construct edges via `B.buildTransducer`
and don't use the `output = Just/Nothing` syntax directly; they're
affected only insofar as `Keiki.Builder`'s own internals widen.

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
`src/Keiki/Examples/UserRegistration.hs` (471 lines as of
post-Plan-15 master) declares the transducer twice: once as
`userReg` via `B.buildTransducer` (the canonical form, lines
284-360) and once as `userRegAST` (lines 361-470, preserved AST
form for cross-form equivalence). The AST form's two edges of
interest are now in `userRegASTEdges`:

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
`deriveAggregateCtors` spec. The cross-form equivalence spec
(`test/Keiki/Examples/UserRegistrationBuilderSpec.hs`) re-greens
because both forms now express the same length-2 edge.

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
`Keiki.Composition.composeEdge` (line 401) takes a single edge `e1`
from the first transducer and either drops it (ε-edge — `output e1 ==
Nothing`) producing an ε-edge in the composite, or composes with each
edge `e2` of the second transducer that the produced mid-symbol can
reach. With multi-event edges, the composition becomes per-`OutTerm`:
each `OutTerm` in `output e1`'s list is composed against the second
transducer's edges, and the resulting `[OutTerm]` list is concatenated
in order. M6 handles this.

**Test infrastructure.** Tests live under `test/`. The entry point
`test/Spec.hs` imports each spec module and registers it under hspec's
`describe`. New specs added by this plan must be wired in there and
listed in `keiki.cabal`'s `keiki-test:other-modules`. The full suite is
run via `nix-shell -p z3 --run "cabal test all"` because the SBV-backed
symbolic specs require z3 in PATH.

**MasterPlan parent.** This plan is one of two alternatives under
`docs/masterplans/7-multi-event-command-support-gsm-widening-vs-state-refinement-ergonomics.md`.
The MasterPlan's Decision Log records the recommendation toward
EP-2 (state-refinement ergonomics) over this plan; selecting EP-1 for
implementation reverses that recommendation. Selecting EP-2 retires
this plan as Cancelled.


## Plan of Work

Eight milestones. Effort estimate: 12–20 hours total. The widening edit
(M2) is mechanical but cascade-heavy; the replay machinery (M3) and the
hidden-input strengthening (M4) carry the design work. M5–M7 are
mechanical adaptations.

**Milestone 0 — Baseline.** Confirm the working tree builds and the
test suite passes:

    cd /Users/shinzui/Keikaku/bokuno/keiki
    cabal build all
    nix-shell -p z3 --run "cabal test all" 2>&1 | tail -3

Expected: `110 examples, 0 failures` (per master at plan-draft time).
Inventory call sites:

    git grep -n 'Maybe (OutTerm\|output = Just\|output = Nothing\|Just (OPack' -- src test

Expected: ~24 hits across `src/Keiki/Core.hs`, `src/Keiki/Composition.hs`,
`src/Keiki/Decider.hs`, the three example modules, and the four test
specs. Record the actual count in Progress so M2 can verify
completeness.

**Milestone 1 — Design note.** Create
`docs/research/gsm-widening-design.md`. Sections:

1. *Problem statement.* Letter FST today; multi-event commands forced
   into state-refinement form. Cite UserRegistration's `Registering` +
   `Continue` as the canonical workaround.

2. *Formal mapping.* Letter FST `omega : S × C → E ∪ {ε}` widens to GSM
   `omega : S × C → E*`. Reference Approach 2 in
   `docs/research/multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md`.

3. *AST change.* `output :: Maybe (OutTerm rs ci co)` becomes `output ::
   [OutTerm rs ci co]`. Length-0 = ε, length-1 = today's letter,
   length-2+ = multi.

4. *`InFlight` wrapper.* Streaming replay through a length-2+ edge
   passes through wrapped intermediate state. Show the type and the
   replay step semantics with a worked example on the
   `StartRegistration` chain.

5. *What's preserved.* Per-`OutTerm` `solveOutput`; per-edge guard
   evaluation; `(Bounded, Enum)` on the user's vertex enum; vertex
   enumeration in `checkHiddenInputs`.

6. *What changes.* `omega` returns `[co]`. `checkHiddenInputs` walks
   the per-edge output list as a whole, computing union coverage of
   `InCtor` slots. Composition concatenates per-edge output lists with
   the existing `substOut` substitution.

7. *What's deferred.* Conditional output lists (list shape depends on
   input). The recommended pattern stays multiple disjoint-guarded
   edges, one per condition, each with a static `[OutTerm]`.

Acceptance: file exists, ~200 lines, covers all sections.

**Milestone 2 — Widen `Edge.output`.** Edit `src/Keiki/Core.hs:411-419`
changing the field type. Cascade-fix every call site listed in M0's
inventory, **including** the builder cascade in
`src/Keiki/Builder.hs` (widen `PartialEdge`'s output accumulator;
adapt `emit`/`noEmit` semantics; allow multiple `emit` calls per
block). Run `cabal build all` repeatedly until green.

After M2, behavior on length-0/1 outputs is identical to before; tests
should pass. The builder's existing tests (`test/Keiki/BuilderSpec.hs`,
`test/Keiki/BuilderSpike.hs`, the two cross-form equivalence specs)
must re-green. Record in Progress: any unexpected call site discovered
beyond M0's inventory.

**Milestone 3 — `InFlight` and `applyEvents`.** Add `InFlight s co` to
`Keiki.Core`. Refactor `applyEvent` to operate on `InFlight`; add
`applyEvents` for chunk replay. Update `reconstitute`. Add test spec
`test/Keiki/Examples/UserRegistrationGSMSpec.hs` (initially containing
only the `applyEvents` round-trip test; the other tests added in M7).

Acceptance: `cabal test all` passes, including the new
`UserRegistrationGSMSpec`.

**Milestone 4 — Strengthen `checkHiddenInputs`.** Edit the per-edge
walk to accumulate coverage across the output list; flag any `InCtor`
referenced by any `OPack` in the list whose slots are not all visited.
Add `test/Keiki/CoreHiddenInputsGSMSpec.hs` with a deliberately
ill-formed multi-event edge.

Acceptance: the new spec asserts the warning fires with a precise
message naming the offending `InCtor` and the missing slot(s).

**Milestone 5 — `Keiki.Decider`.** Update docstring. Lift `omega`
returning `[co]` directly into the `decide` field. Add
`evolveStreaming` field to `Decider` carrying the wrapped-state replay.

Acceptance: `test/Keiki/DeciderSpec.hs` passes; new test asserts
`decide` over a multi-event edge returns the full event list.

**Milestone 6 — `Keiki.Composition`.** Refactor `composeEdge` to
concatenate output lists per-`OutTerm` substitution. Add a multi-event
composition test in `test/Keiki/CompositionSpec.hs`.

Acceptance: existing composition tests pass; new test asserts the
composed edge produces a concatenated event list.

**Milestone 7 — UserRegistration migration.** Drop `Registering` and
`Continue`; collapse the two edges into one length-2 edge in **both**
the builder form (`userReg`) and the AST form (`userRegAST`). Update
TH-derived spec lists. Cascade-fix `UserRegistrationSpec`,
`UserRegistrationViewSpec`, `UserRegistrationBuilderSpec` (the
cross-form equivalence). Add the multi-event-specific tests to
`UserRegistrationGSMSpec` (decide returns 2-element list; streaming
and chunked replay agree).

Acceptance: full test suite passes including cross-form
equivalence; UserRegistration line count drops by ~50–60 lines
(removing one builder block, one AST edge, one vertex constructor,
one command constructor, two TH spec entries); vertex enum and
command enum each have 4 constructors (down from 5).

**Milestone 8 — Docs + commit.** Update synthesis note line 974;
update multi-event note's Recommendation. Stage and commit per the
Concrete Steps section below.


## Concrete Steps

All commands run from `/Users/shinzui/Keikaku/bokuno/keiki/`.

**M0:**

    cabal build all
    nix-shell -p z3 --run "cabal test all" 2>&1 | tail -3
    git grep -nE '(Maybe \(OutTerm|output = (Just|Nothing)|Just \(OPack)' -- src test \
      | tee /tmp/gsm-call-sites.txt
    wc -l /tmp/gsm-call-sites.txt

**M1:** Create the design note. Use the section structure above.

**M2:** Edit `src/Keiki/Core.hs:411-419` as described. Then iterate:

    cabal build 2>&1 | head -20    # examine first error
    # fix the cited call site
    # repeat until clean

After every successful build, re-run tests:

    nix-shell -p z3 --run "cabal test all" 2>&1 | tail -3

**M3:** Add `InFlight` and `applyEvents`. Run tests after each step.

**M4:** Edit `checkHiddenInputs`. Add the test spec; run it.

**M5:** Edit `Keiki.Decider`. Run tests.

**M6:** Edit `Keiki.Composition`. Run tests.

**M7:** Edit `Keiki.Examples.UserRegistration`. Cascade-fix dependent
tests. Run full suite.

**M8:** Edit docs. Commit:

    git add src/Keiki/Core.hs src/Keiki/Composition.hs src/Keiki/Decider.hs \
            src/Keiki/Examples/UserRegistration.hs \
            test/Keiki/Examples/UserRegistrationGSMSpec.hs \
            test/Keiki/CoreHiddenInputsGSMSpec.hs \
            test/Spec.hs keiki.cabal \
            docs/research/gsm-widening-design.md \
            docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md \
            docs/research/multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md \
            docs/plans/19-multi-event-commands-via-edge-output-widening-gsm-expansion.md \
            docs/masterplans/7-multi-event-command-support-gsm-widening-vs-state-refinement-ergonomics.md

    git commit -m "$(cat <<'EOF'
    feat(core): EP-19 — widen Edge.output to [OutTerm rs ci co] for multi-event commands

    Multi-event commands are first-class via the widened Edge.output and
    InFlight replay wrapper. State refinement is no longer the canonical
    path; aggregates declare multi-event edges directly. UserRegistration
    drops the Registering intermediate vertex and the Continue internal
    command.

    MasterPlan: docs/masterplans/7-multi-event-command-support-gsm-widening-vs-state-refinement-ergonomics.md
    ExecPlan: docs/plans/19-multi-event-commands-via-edge-output-widening-gsm-expansion.md
    Intention: intention_01kqmjp9k8e478db6xjah31455
    EOF
    )"


## Validation and Acceptance

After all eight milestones:

- `cabal build all` succeeds with no warnings.
- `nix-shell -p z3 --run "cabal test all"` reports 110 + ≥4 examples
  (10+ if M3, M4, M6, M7 each add multiple tests), 0 failures.
- `docs/research/gsm-widening-design.md` exists and documents the
  widening.
- `Keiki.Core.Edge`'s `output` field has type `[OutTerm rs ci co]`.
- `Keiki.Core.applyEvent`'s signature carries `InFlight s co` on input
  and output.
- `Keiki.Core.applyEvents :: SymTransducer phi rs s ci co -> (s, RegFile rs)
  -> [co] -> Maybe (s, RegFile rs)` is exported.
- `Keiki.Core.checkHiddenInputs`'s implementation walks edge output
  lists as a whole.
- `Keiki.Examples.UserRegistration.Vertex` has four constructors
  (`PotentialCustomer`, `RequiresConfirmation`, `Confirmed`, `Deleted`);
  `UserCmd` has four constructors (drops `Continue`).
- `docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`
  line 974 is updated.

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
    data Edge phi rs ci co s = Edge
      { guard  :: phi
      , update :: Update rs ci
      , output :: [OutTerm rs ci co]   -- changed from Maybe
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

    applyEvents
      :: BoolAlg phi (RegFile rs, ci)
      => SymTransducer phi rs s ci co
      -> (s, RegFile rs) -> [co]
      -> Maybe (s, RegFile rs)

    -- src/Keiki/Decider.hs (extends)
    data Decider c e s s_streaming = Decider
      { decide          :: c -> s -> [e]                            -- now actually returns ≥0
      , evolve          :: s -> e -> s                              -- letter case (single-event edges)
      , evolveStreaming :: s_streaming -> e -> Maybe s_streaming    -- multi-event case
      , initialState    :: s
      , isTerminal      :: s -> Bool
      }

    toDecider :: ... -> Decider ci co (s, RegFile rs) (InFlight s co, RegFile rs)

Modified modules:

- `Keiki.Core` (modified) — `Edge.output` widened; `omega`, `applyEvent`,
  `applyEvents`, `step`, `reconstitute`, `checkHiddenInputs` adapted.
- `Keiki.Composition` (modified) — `composeEdge` concatenates output
  lists.
- `Keiki.Decider` (modified) — adds `evolveStreaming` field, lifts
  `decide` over the new `omega` shape.
- `Keiki.Builder` (modified) — `PartialEdge` accumulator widens to a
  list; `emit` appends rather than sets; multiple `emit` calls per
  block produce a multi-event edge.
- `Keiki.Examples.UserRegistration` (modified) — drops `Registering` and
  `Continue`; collapses two edges into one multi-event edge in both
  builder (`userReg`) and AST (`userRegAST`) forms.
- `Keiki.Examples.UserRegistrationGSMSpec` (new) — multi-event-specific
  assertions.
- `Keiki.CoreHiddenInputsGSMSpec` (new) — strengthened-check
  assertions.

Existing functions consumed:

- `Keiki.Core.solveOutput` (unchanged) — walks one `OutTerm`. The new
  `applyEvent` calls it once per `OutTerm` in the edge's output list.
- `Keiki.Composition.substOut` (unchanged) — substitutes one `OutTerm`.
  The new `composeEdge` calls it once per `OutTerm` in the inner edge's
  output list.

No new external dependencies. The existing `template-haskell`, `sbv`,
`text`, `time` are sufficient.

The MasterPlan parent
(`docs/masterplans/7-multi-event-command-support-gsm-widening-vs-state-refinement-ergonomics.md`)
documents this plan's relationship to its alternative
`docs/plans/20-multi-event-commands-via-state-refinement-ergonomics.md`.
The two plans are mutually exclusive: selecting EP-19 cancels EP-20 and
vice versa. The MasterPlan recommends EP-20.


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
