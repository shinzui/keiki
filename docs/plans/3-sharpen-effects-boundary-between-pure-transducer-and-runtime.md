---
id: 3
slug: sharpen-effects-boundary-between-pure-transducer-and-runtime
title: "Sharpen effects boundary between pure transducer and runtime"
kind: exec-plan
created_at: 2026-05-01T05:20:23Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
master_plan: "docs/masterplans/1-validate-symbolic-register-direction-via-haskell-prototype.md"
---

# Sharpen effects boundary between pure transducer and runtime

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

The keiki library is being designed (no code yet) to handle the **pure** part of event
sourcing, workflow engines, and durable execution. "Pure" is the headline word: the
core type — the symbolic-register transducer defined in
`docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md` — has no
`IO`, no clock, no random, no side effects of any kind. Everything that talks to the
outside world (the event store, message queues, subscriptions, timers, the wall clock)
lives in a separate runtime layer described qualitatively in
`docs/research/fst-as-workflow-runtime.md`.

But "qualitatively described" is not the same as "specified." The boundary between
these two layers — the **effects boundary** — has never been written down with the
precision that prototyping needs. Concretely:

- Where exactly does the pure layer end?
- What is the type signature of the boundary, on the runtime side?
- What does the runtime hand to the pure layer, what does the pure layer hand back?
- How does the runtime turn an emitted output event into "send a command to another
  aggregate" (per synthesis §5's Order Fulfillment example)?
- How does the runtime turn an external happening (a timer firing, a foreign event
  arriving) into an input the pure layer can consume?
- How does time enter? The synthesis has been clear that timestamps are command/event
  fields, not pulled from a clock inside `delta` — but who pulls them, and where?

Before the prototype is built, this plan must pin those boundaries down so that:
(a) the prototype's pure module is unambiguously pure (no accidental `IO`); (b) the
prototype's runtime stub (or absence thereof) is correctly scoped; (c) future plans
that wire the pure core to a real event store / queue / subscription system have a
clear interface to consume.

After this plan is complete, a new design note exists at
`docs/research/effects-boundary.md` that fully specifies: the responsibilities of each
side, the types that cross the boundary in each direction, the timer / clock / random
discipline, the dispatch and routing model for outputs/inputs across context
boundaries, and the v1 prototype's scope (almost certainly: pure module only, no
runtime).

The user-visible win: a future contributor reading the design note can write the
runtime layer in any monad they like (IO, ReaderT IO, ResourceT, Effectful) without
worrying about the pure core leaking, and the prototype contributor knows exactly
what types to expose so the runtime can sit on top later.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] Re-read the synthesis note (especially §5 "Order Fulfillment" and the
      "How the runtime threads the alphabets" / "Timer" subsections), and
      `docs/research/fst-as-workflow-runtime.md` from start to finish. (2026-05-01)
- [x] Enumerate every external concern the runtime is responsible for and every place
      the synthesis or research notes wave their hands at "the runtime does this".
      (2026-05-01)
- [x] Survey how comparable libraries draw the line: read `effectful` and
      `tan/message-db-hs` (via `mori`) for their effect-handling style; reasoned
      about `crem` from published documentation knowledge (no local registry entry).
      Note where each draws its purity boundary. (2026-05-01)
- [x] Sketch the boundary in both directions: the pure layer's exposed surface (what
      the runtime calls), and the runtime's exposed surface (what the application calls
      to wire things up). For each, write concrete Haskell type signatures. (2026-05-01)
- [x] Decide the time discipline: who calls `getCurrentTime`, where it goes
      (synthesis says "command/event field"), how the prototype handles it. (2026-05-01)
- [x] Decide the randomness discipline (e.g., `freshCode` in the User Registration
      aggregate): same shape — generated outside, passed in via command. (2026-05-01)
- [x] Decide the routing/dispatch model: the synthesis names `lmapMaybeC` and
      "subscriptions". Make those types concrete (or specify them precisely enough that
      the prototype can declare placeholders). (2026-05-01)
- [x] Decide the timer model: an output event consumed by the timer service, then
      delivered later as a typed input. Write the input/output type signatures.
      (2026-05-01)
- [x] State the v1 prototype scope: what it implements (almost certainly nothing on
      the runtime side), what it merely *names* (the boundary types as data only), and
      what it explicitly defers. (2026-05-01)
- [x] Write the design note at `docs/research/effects-boundary.md`. (2026-05-01)
- [ ] Commit (with `MasterPlan:`, `ExecPlan:`, `Intention:` trailers) and update this
      plan's living sections. (Deferred to orchestrator — sibling plans commit
      serially.)


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- **`crem` is not in the local mori registry.** Confirmed via
  `mori registry list | grep -i crem`. Fell back to reasoning from
  published documentation. The lessons drawn (effectful interpretation by
  lifting; composition at the value level; in-process feedback loops are
  hostile to durable execution) are uncontroversial and do not require
  source inspection. Date: 2026-05-01.

- **`tan-event-source` is not in the local mori registry either.** What is
  registered is `tan/message-db-hs`, a different (Haskell-flavored)
  event-sourcing library at `/Users/shinzui/Keikaku/work/libraries/haskell/message-db-hs-master`.
  Used it as the local IO-boundary reference. Its `MessageDb` effect surface
  (Get/Write stream messages) is the exact shape `Keiki.Runtime`'s eventual
  event-store port should mirror. Date: 2026-05-01.

- **IP-3 (step/reconstitute signatures) is fully pinned.** Both signatures
  in §5 of the design note are unambiguous and parameter-for-parameter ready
  for plan 4 to implement. `step` returns `Maybe (s, RegFile rs, Maybe co)`
  (the inner `Maybe` carries the ε case); `reconstitute` returns
  `Maybe (s, RegFile rs)`. No surprises that would force plan 4 to deviate
  during implementation. Cross-cuts plan 4. Date: 2026-05-01.

- **IP-4 (module layout) proposes `Keiki.Core` only for v1.** No
  `Keiki.Runtime` module in the v1 cabal file — even an empty one —
  because it would risk a contributor putting `IO` in it before the
  runtime design is ready. Plan 4 adds only `Keiki.Core` and
  `Keiki.Examples.UserRegistration`. Cross-cuts plan 4. Date: 2026-05-01.

- **IP-6 (time / randomness discipline) is now a normative rule, not a
  guideline.** Both rules (§6, §7 of the design note) are stated as
  one-sentence rules with worked examples through `RegistrationStarted.at`
  and `ResendConfirmationData.code`. The synthesis's pseudosyntax
  `Set #confirmCode freshCode` becomes
  `Set #confirmCode (\(ResendConfirmation d) -> d.code)`. Plan 4 must
  add a `code :: ConfirmationCode` field to `ResendConfirmationData` —
  this is a small but real divergence from the synthesis pseudosyntax that
  plan 4 needs to track. Cross-cuts plan 4 and the master plan IP-6. Date:
  2026-05-01.

- **`isSingleValued` is exposed but best-effort in v1.** Synthesis §7
  defers a general decision procedure to v2 (SBV-backed). The v1 surface
  is a syntactic conservative approximation. Plan 4 may implement only the
  conservative form; it is not exercised by the smoke test. Cross-cuts
  plan 4 and possibly plan 1 (DSL shape may affect approximation
  precision). Date: 2026-05-01.

- **Hidden-input check returns `[HiddenInputWarning]`, not `Bool`.** Multi-warning
  reporting in one pass is more useful for the user than a single
  yes/no. The exact shape of `HiddenInputWarning` is plan 1's territory
  (it depends on how structurally `OutTerm` is encoded — the IP-2
  coordination point). Cross-cuts plan 1 and plan 4. Date: 2026-05-01.


## Decision Log

Record every decision made while working on the plan.

- Decision: This plan produces a design note, not Haskell code.
  Rationale: The prototype lives in plan 4
  (`docs/plans/4-prototype-symbolic-register-core-with-user-registration-smoke-test.md`).
  The effects-boundary specification is consumed by plan 4 to know what *not* to put
  in the pure module, but plan 4 does not need to implement any of the runtime side.
  Settling this in prose first lets the prototype focus on the synthesis-validation
  question.
  Date: 2026-04-30

- Decision: `step` is the canonical pure-layer entry point.
  Signature:
      step
        :: SymTransducer phi rs s ci co
        -> (s, RegFile rs)
        -> ci
        -> Maybe (s, RegFile rs, Maybe co)
  Rationale: Following synthesis §2's promise that "familiar functions are
  projections, not fields," `delta` and `omega` remain available but are
  analysis-only. Carving them as the runtime's primary call sites would risk
  inconsistency between control-state transitions and output emission;
  `step` makes that impossible by construction. The inner `Maybe co`
  carries the ε case (no output emitted on this transition).
  Date: 2026-05-01

- Decision: `reconstitute` consumes `[output]`, not `[command]`.
  Signature:
      reconstitute
        :: SymTransducer phi rs s ci co
        -> [co]
        -> Maybe (s, RegFile rs)
  Rationale: The event store is the durable record of what the transducer
  *emitted*, not what it *received*. Replay reconstructs received inputs
  by inverting outputs via `solveOutput`. Returning `Nothing` on
  hidden-input failure surfaces the same condition the build-time
  `checkHiddenInputs` analysis catches statically.
  Date: 2026-05-01

- Decision: `checkHiddenInputs` returns `[HiddenInputWarning]`, not `Bool`.
  Signature:
      checkHiddenInputs
        :: SymTransducer phi rs s ci co
        -> [HiddenInputWarning]
  Rationale: One-pass multi-warning reporting is more useful for the user.
  The exact shape of `HiddenInputWarning` is plan 1's territory, since it
  depends on the structural encoding of `OutTerm`.
  Date: 2026-05-01

- Decision: Time discipline rule.
  Rule: All values that depend on the wall clock are carried in the input
  alphabet; the adapter (an unspecified runtime component) stamps them by
  calling `getCurrentTime` before constructing the input.
  Rationale: Synthesis §4's data discipline notes already established this;
  the boundary note re-states it as a normative rule. Worked example:
  `RegistrationStarted.at` is stamped by the HTTP adapter before
  `step` is called, persisted in the event, and recovered by
  `reconstitute` on replay — no clock involvement during replay.
  Date: 2026-05-01

- Decision: Randomness discipline rule.
  Rule: All values that depend on randomness or fresh-ID generation are
  carried in the input alphabet; the adapter stamps them by calling the
  appropriate `IO` generator before constructing the input.
  Rationale: Same shape as time. Worked example: `freshCode` (synthesis §4
  pseudosyntax) becomes `code :: ConfirmationCode` field of
  `ResendConfirmationData`, populated by the adapter. The synthesis's
  `Set #confirmCode freshCode` becomes
  `Set #confirmCode (\(ResendConfirmation d) -> d.code)`. An alternative
  discipline (deterministic register-derived fresh values, e.g.,
  `hash (oldCode, registeredAt)`) is also pure and the boundary note
  allows it; the choice is a DSL-shape question owned by plan 1.
  Date: 2026-05-01

- Decision: Subscription shape is `type Subscription a b = a -> Maybe b`.
  With concrete combinator:
      lmapMaybeC :: (a -> Maybe b) -> InputSource a -> InputSource b
  Rationale: Matches the `lmapMaybeC` shape from
  `future-directions-profunctors-effects-and-composition.md`. Pure layer
  does not see `InputSource`/`lmapMaybeC` as runtime ops — those live in
  `Keiki.Runtime`. Pure layer sees only the typed sum constructor for
  inputs.
  Date: 2026-05-01

- Decision: Dispatch shape is `type Dispatch a m = a -> m ()`.
  Rationale: The runtime author chooses `m` (`IO`, `Eff es`, `ReaderT env IO`,
  ...). Pure layer never sees this. Library specifies that dispatchers
  exist; does not specify how they are wired.
  Date: 2026-05-01

- Decision: Module layout proposes `Keiki.Core` (pure) and `Keiki.Runtime`
  (deferred). Plan 4 adds only `Keiki.Core` and `Keiki.Examples.UserRegistration`.
  Rationale: An empty `Keiki.Runtime` module in v1 would risk a contributor
  putting `IO` in it before the runtime design is ready. The boundary is the
  constraint, not the file count.
  Date: 2026-05-01

- Decision: v1 prototype scope (canonical paragraph for plan 4 to copy).
  "The v1 prototype implements only `Keiki.Core`. It provides `step` and
  `reconstitute`. It does NOT implement `runTransducer`, `InputSource`,
  `OutputSink`, `Subscription`, `Dispatch`, or any timer code. The smoke
  test calls `step` and `reconstitute` directly with hardcoded inputs and a
  hardcoded `[Output]` event log."
  Rationale: Captures the validation gate exactly: AST ergonomics tolerable
  AND `solveOutput` works. No runtime concerns; no `IO`; no event store; no
  time mocking; no random mocking. The fixtures *are* the clock and RNG.
  Date: 2026-05-01


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

The boundary is now pinned. `Keiki.Core` is pure Haskell, with `step`,
`reconstitute`, `checkHiddenInputs`, and `isSingleValued` as its primary
exports — concrete, parameter-for-parameter signatures that plan 4 can
implement directly. `Keiki.Runtime` is named but deferred: its types
(`InputSource`, `OutputSink`, `runTransducer`, `Subscription`, `Dispatch`)
exist in this note as targets for future runtime plans, not as code in
the v1 cabal file. The time and randomness disciplines are stated as
one-sentence normative rules (clock and RNG live in the adapter, never in
the transducer) with worked walkthroughs for `RegistrationStarted.at` and
`ResendConfirmationData.code`. The subscription model is `lmapMaybeC`-shaped;
the dispatch model is `a -> m ()` for runtime-author-chosen `m`; the timer
model is two alphabet members and a runtime service, with cancellation
falling out of `step`'s partiality.

The v1 prototype scope (§11 of the design note) is the paragraph plan 4
copies verbatim into its scope. Following it is sufficient to keep
`Keiki.Core` `IO`-free and to keep the smoke test deterministic without
any time-mocking or random-mocking machinery.

Compared to the plan's original purpose: every question listed in the
plan's "What this plan must settle" list now has a concrete answer
recorded in the Decision Log above. A non-author reviewer reading
`docs/research/effects-boundary.md` should be able to predict, for any
proposed function, whether it belongs in `Keiki.Core` or `Keiki.Runtime`
without consulting the synthesis. The note's §12 "Cross-check" section
exercises that prediction directly on five concrete cases.

Gaps: the SBV-backed `BoolAlg` instance (synthesis §7's v2 work) and a
runtime-side reference implementation (a future plan, not this one) remain
out of scope. The exact shape of `HiddenInputWarning` is left to plan 1
because it depends on the chosen `OutTerm` encoding (IP-2 in the master
plan).


## Context and Orientation

The keiki repository currently contains no Haskell code. The directory layout is:

    docs/
      foundations/    team onboarding
      research/       design notes for the library itself
    docs/masterplans/   coordination plans
    docs/plans/         execution plans (this is one)

Essential reads before starting, in order:

1. `docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md` —
   the working baseline. The relevant passages: §4's "Notes on data discipline" lists
   the two existing purity disciplines (`UTCTime` is a command field, not pulled from
   a clock inside `delta`; `ConfirmationCode` is generated outside the transducer).
   §5's "How the runtime threads the alphabets," "Timer," and "Reconstitution"
   subsections paint the most concrete picture of the runtime so far. §6 "Composition"
   distinguishes formal composition (analysis-only) from runtime composition
   (subscriptions).
2. `docs/research/fst-as-workflow-runtime.md` — the runtime architecture document. Per
   the synthesis "the runtime architecture is unchanged" — but this plan must verify
   that document actually pins down the boundary in detail. If it doesn't, this plan
   is the place to do it.
3. `docs/research/orchestration-sagas-choreography-and-feedback-loops-as-transducers.md`
   — covers the subscription/routing model from a different angle.
4. `docs/research/future-directions-profunctors-effects-and-composition.md` — explicitly
   names `lmapMaybeC`, the routing combinator the synthesis references.

### Terms used in this plan

- **Pure layer** (a.k.a. "pure core"): the part of keiki that has no `IO` and no
  unhandled side effects. Concretely the `SymTransducer`, `Edge`, `Term`, `OutTerm`,
  `Update`, `RegFile`, `BoolAlg phi`, `solveOutput`, the `delta` / `omega` projections,
  and any analyses (hidden-input check, single-valuedness, language inclusion). All
  Haskell-level pure.
- **Runtime layer**: everything outside the pure layer that makes a deployed system
  work — event store, message queue, subscriptions, timer service, snapshot store,
  serialization to/from JSON, error reporting, retries.
- **Effects boundary**: the contract between the two. Captured as Haskell type
  signatures: a function exported by the pure layer is a "boundary call" if the
  runtime invokes it; a function the runtime exports for the application to call is
  a "wiring API."
- **Subscription**: a runtime concept. A function from a wider event stream (e.g., the
  event log of another bounded context) into `Maybe Input` for a particular
  transducer. The synthesis names this `lmapMaybeC` (left-map-maybe over the
  contravariant alphabet position). For this plan it suffices to know it is a routing
  function the runtime registers.
- **Dispatch**: the inverse of a subscription. A function from a transducer's
  `Output` event to a side effect (e.g., "send command to Payment aggregate," "schedule
  a delayed message on the queue"). The synthesis's `dispatchPaymentRequests` is an
  example.
- **Timer service**: a runtime component that consumes a `*Scheduled` output event,
  schedules a delayed delivery, and re-injects a `*Expired` event back into the
  transducer's input alphabet at the appropriate time.
- **Replay**: the act of recovering state from stored events; the runtime drives it,
  but the pure layer's `solveOutput` does the work. See plan 1 / synthesis §4 step 4.

### What the synthesis note already settles (do not re-litigate)

- `delta`, `omega`, `runUpdate`, `evalTerm`, `evalOut`, `models`, `solveOutput` are
  all pure functions on the register file and input.
- Timestamps and other "external" values arrive in command payloads, not via `IO`
  inside the transducer.
- Subscriptions and dispatch are runtime, not formalism.
- Composition for runtime is via the event store and queue, not formal product
  construction.

### What this plan must settle

- **The `step` function signature.** Plain `step` is the canonical pure-layer entry
  point: given a transducer, a current `(state, regs)`, and an input, return
  `Maybe (state, regs, Maybe output)`. Decide whether the prototype needs `step`
  directly, just `delta`/`omega`, or both. Recommended: name `step` as the canonical
  primary export and let `delta`/`omega` be analysis-only projections.
- **The `reconstitute` function signature.** Given a transducer and a `[output]` (an
  event log), return `Maybe (state, regs)`. This is the function plan 4 must
  implement; this plan ensures the type is unambiguous.
- **The runtime port shape.** The runtime must offer the pure layer a way to read
  events from the event store and write events back. The simplest port is two pure
  functions provided by the runtime that the pure layer never calls — instead, the
  *runtime* drives the pure layer in a loop:

      runtimeLoop :: SymTransducer phi rs s ci co -> InputSource ci -> OutputSink co -> IO ()

  with `InputSource` and `OutputSink` being runtime-side types. Confirm or replace
  this shape.
- **Time discipline.** Who calls `getCurrentTime`? Recommended: the runtime's
  *adapter* layer — the bit that takes a foreign request (HTTP, queue message) and
  produces a typed input. The adapter calls `getCurrentTime` and stamps the input.
  The pure layer never sees `IO`.
- **Randomness / fresh ID discipline.** Same as time. The synthesis's
  `freshCode` helper in the User Registration aggregate is a fiction in a fully pure
  formalism — `freshCode` would have to be supplied by the command. Document the
  fix: `ResendConfirmationData` carries the fresh code as a field. The adapter
  generates the code before calling `step`.
- **Subscription type.** Make `lmapMaybeC` concrete. It is a function
  `forall a b. (b -> Maybe a) -> Subscription b -> Subscription a` (or however the
  routing primitive is shaped); decide whether the library exports a `Subscription`
  type or whether subscriptions are just functions the runtime registers.
- **Dispatch type.** Same: `Dispatch a = a -> IO ()` is a starting point. The pure
  layer never sees this; only the runtime does.
- **Timer model.** The synthesis paints a clear picture: an output event tagged as a
  timer schedule is consumed by the timer service, which schedules a queue message;
  later the queue message arrives and is routed back as an input event. Pin the type
  signatures: `Schedule = (Output, UTCTime)` for the timer service, and the
  re-injection is just another subscription.
- **What the v1 prototype implements.** Almost certainly: nothing of the runtime.
  The prototype's pure module exports `step` and `reconstitute`; the prototype's
  smoke test calls those directly with a hardcoded `[Output]`. State this
  explicitly so plan 4 has a clear scope.
- **Module layout proposal.** Even though plan 4 only implements the pure module, this
  note should propose where the runtime layer eventually lives (e.g., `Keiki.Core`
  for pure, `Keiki.Runtime` for runtime). This is a forward-looking aid.

### Tooling

Use `mori` for dependency surveys per the user's global instructions:

    mori registry list
    mori registry search effectful
    mori registry show effectful --full
    mori registry search crem
    mori registry show crem --full

If the packages are present, follow `source-paths` and read their effect-boundary
treatment on disk. **Never search `/nix/store`.**


## Plan of Work

Single milestone — produce a design note. Within the milestone, work outside-in: list
the runtime concerns first (so we see the full surface), then carve the pure side from
them, then specify the boundary types.

### Milestone 1 — Author the effects-boundary design note

**Scope:** produce a single Markdown document at `docs/research/effects-boundary.md`
that fully specifies the boundary types, the time / randomness disciplines, the
subscription / dispatch / timer models, and the v1 prototype scope.

**What will exist at the end:** a design note that the prototype plan
(`docs/plans/4-prototype-symbolic-register-core-with-user-registration-smoke-test.md`)
treats as a directional input, and that any future plan implementing the runtime
layer treats as the contract.

**Sub-steps in order:**

1. **Enumerate runtime concerns.** Write a list of every external concern: event
   store reads/writes, queue dequeue/enqueue, subscription registration, dispatch,
   timer scheduling, snapshot reads/writes, serialization, errors, retries,
   observability. Keep the list specific — "logging" is fine if you also note where
   logging crosses the boundary (probably never; the pure layer does not log).

2. **Walk the synthesis's Order Fulfillment example.** Trace one happy-path event
   end-to-end:

   - The customer hits an HTTP endpoint with a `SubmitOrder` request.
   - The runtime adapter parses it, calls `getCurrentTime`, fills in
     `SubmitOrderData`, and produces a typed `OrderInput`.
   - The runtime calls `step orderPM (s, regs) input` (pure).
   - `step` returns `Just (s', regs', Just output)`.
   - The runtime writes `output` to the order's event stream.
   - A subscription routes the output to a dispatcher; the dispatcher sends a
     command to the Payment aggregate (HTTP / queue / direct call — runtime's
     choice).
   - When the Payment aggregate emits its own event, a subscription routes it back
     into `OrderInput`, calls `step` again, and so on.

   Identify every line where `IO` happens. The pure layer never appears in those
   lines.

3. **Survey comparable approaches.** Read `crem`'s effect handling, `tan-event-source`'s
   event-store interface, and `effectful`'s style of effect interpretation (via
   `mori`). Note where each draws the boundary. Embed the relevant insights in the
   design note in your own words; do not link to external URLs.

4. **Specify the pure-layer entry points.** Concrete signatures (these are tentative
   and must be reconciled with plan 1's DSL choices):

       step
         :: SymTransducer phi rs s ci co
         -> (s, RegFile rs)
         -> ci
         -> Maybe (s, RegFile rs, Maybe co)

       reconstitute
         :: SymTransducer phi rs s ci co
         -> [co]
         -> Maybe (s, RegFile rs)

       -- Pure analysis primitives (out of scope for plan 4 but exposed by the pure layer)
       checkHiddenInputs :: SymTransducer phi rs s ci co -> [HiddenInputWarning]
       isSingleValued    :: SymTransducer phi rs s ci co -> Bool   -- v1: best-effort

   Note: `reconstitute` is what plan 4 implements via `solveOutput`. Its signature
   here drives plan 4's milestone definitions.

5. **Specify the runtime-side ports.** These are *names of types*, not implementations
   plan 4 builds. Recommended shapes:

       data InputSource ci   -- runtime-defined; produces ci values from somewhere
       data OutputSink co    -- runtime-defined; consumes co values somewhere

       runTransducer
         :: SymTransducer phi rs s ci co
         -> InputSource ci
         -> OutputSink co
         -> IO Void   -- or whatever monad the runtime sits in

   These types will be defined in `Keiki.Runtime` (or equivalent) in a future plan.
   For now, they must be *named* so the design note has something to point at.

6. **Pin the time discipline.** State the rule in one sentence and back it up with a
   walked example. Suggested rule: *"All values that depend on the wall clock are
   carried in the input alphabet; the adapter (an unspecified runtime component)
   stamps them by calling `getCurrentTime` before constructing the input."* Walk
   through how `RegistrationStarted`'s `at` field gets there.

7. **Pin the randomness discipline.** Same rule, same shape: confirmation codes,
   UUIDs, anything else random must be a field of the input. Walk through how
   `freshCode` is fed into a `ResendConfirmation` command.

8. **Pin the subscription model.** Define `Subscription a = forall b. SomeInput b ->
   Maybe a` (or another shape if the survey suggests better). State that the library
   does *not* prescribe how subscriptions are stored or dispatched — that is runtime
   territory.

9. **Pin the dispatch model.** Same: `Dispatch a = a -> SomeRuntimeMonad ()`. The
   library specifies that dispatchers exist; it does not specify how they are wired.

10. **Pin the timer model.** State that timer scheduling is "another output event"
    and timer firing is "another input event," with the runtime handling the
    in-between via its queue and clock. Walk through `PaymentTimerScheduled` →
    `PaymentDeadlineExpired` from synthesis §5.

11. **Propose module layout.** Two modules at a minimum:

        Keiki.Core      -- pure types and projections; what plan 4 implements
        Keiki.Runtime   -- IO-wired event store, queue, subscriptions, timer (future)

    Optionally also `Keiki.Examples.UserRegistration` for the smoke test (plan 4's
    deliverable).

12. **State the v1 prototype scope.** The v1 prototype:
    - Implements only `Keiki.Core`.
    - Provides `step` and `reconstitute`.
    - Does **not** implement `runTransducer`, `InputSource`, `OutputSink`,
      `Subscription`, `Dispatch`, or any timer code.
    - The smoke test calls `step` and `reconstitute` directly with hardcoded inputs
      and a hardcoded `[Output]` event log.

    Plan 4 should be able to copy this paragraph verbatim.

13. **Write the design note.**

14. **Cross-check.** A reader of the note should be able to write a Haskell module
    boundary that compiles with `Keiki.Core` having no `IO` import and `Keiki.Runtime`
    having free reign over `IO`. They should know exactly which functions they would
    add to `Keiki.Runtime` to wire to a real event store.

**Acceptance:** the design note exists at the path above; the type signatures for
`step` and `reconstitute` are written; the time / randomness / subscription /
dispatch / timer disciplines are stated; the v1 prototype scope is a paragraph
plan 4 can copy.

**Commands to verify:**

    test -f docs/research/effects-boundary.md && echo "design note present"

    grep -c '^## ' docs/research/effects-boundary.md
    # expect at least 7 sections

    grep -E '(step|reconstitute|InputSource|OutputSink|Keiki\.Core|Keiki\.Runtime)' \
      docs/research/effects-boundary.md | head
    # expect every named entry point and module to appear


## Concrete Steps

All work happens at the repository root: `/Users/shinzui/Keikaku/bokuno/keiki`.

1. Read the inputs:

       cat docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md
       cat docs/research/fst-as-workflow-runtime.md
       cat docs/research/orchestration-sagas-choreography-and-feedback-loops-as-transducers.md
       cat docs/research/future-directions-profunctors-effects-and-composition.md

2. Survey comparable libraries:

       mori registry search effectful
       mori registry show effectful --full
       mori registry search crem
       mori registry show crem --full
       mori registry search tan-event-source
       mori registry show tan-event-source --full

3. Draft the design note structure:

       # Effects boundary between pure transducer and runtime

       ## Inputs and prerequisites

       ## What the runtime is responsible for
       (the enumeration)

       ## Walked Order Fulfillment trace
       (where IO happens, where it doesn't)

       ## Pure-layer entry points
       (step, reconstitute, analyses)

       ## Runtime-side ports
       (InputSource, OutputSink, runTransducer)

       ## Time discipline

       ## Randomness discipline

       ## Subscriptions and dispatch

       ## Timer model

       ## Module layout (Keiki.Core, Keiki.Runtime)

       ## Prototype scope (v1)

4. Write the note section by section. Verify by trying to mentally compile a
   `Keiki.Core` module that uses none of the runtime types — if any signature in §4
   forces an `IO` import, fix it.

5. Run the verification commands.

6. Commit:

       git add docs/research/effects-boundary.md \
               docs/plans/3-sharpen-effects-boundary-between-pure-transducer-and-runtime.md \
               docs/masterplans/1-validate-symbolic-register-direction-via-haskell-prototype.md
       git commit -m "$(cat <<'EOF'
       docs(research): sharpen effects boundary between pure transducer and runtime

       Pin the pure-layer entry points (step, reconstitute), the runtime-side
       ports (InputSource, OutputSink, runTransducer), the time / randomness /
       subscription / dispatch / timer disciplines, and the proposed module
       layout. Scope the v1 prototype to Keiki.Core only.

       MasterPlan: docs/masterplans/1-validate-symbolic-register-direction-via-haskell-prototype.md
       ExecPlan: docs/plans/3-sharpen-effects-boundary-between-pure-transducer-and-runtime.md
       Intention: intention_01knjzws4qezz9w8b0743zfqv8
       EOF
       )"

7. Update this plan's living sections and the master plan's registry/progress.


## Validation and Acceptance

Validation is by reading the design note against this checklist:

1. **Self-containment.** A reader who has read only the synthesis note can implement
   the runtime layer from this design note.
2. **Pure-layer entry points have type signatures.** Not just names. Plan 4 will copy
   them.
3. **Time and randomness disciplines are stated as one-sentence rules** plus a worked
   example each.
4. **The v1 prototype scope is stated explicitly.** Plan 4 should be able to copy that
   paragraph verbatim.
5. **`Keiki.Core` and `Keiki.Runtime` modules are named.** This proposal might be
   overridden later, but having a name to point at is essential for plan 4.

A non-author reviewer should be able to use the design note to predict whether a
proposed function belongs in `Keiki.Core` or `Keiki.Runtime` without consulting the
synthesis note again.


## Idempotence and Recovery

This plan produces a single Markdown file. All steps are repeatable. If the design
note already exists when work resumes, read it, find the first incomplete section, and
continue. The boundary type choices in step 5 are the most likely to be revisited; if
revised, walk the Order Fulfillment trace from step 2 again to ensure the new shapes
still cover it.


## Interfaces and Dependencies

Inputs (read-only):

- `docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`
- `docs/research/fst-as-workflow-runtime.md`
- `docs/research/orchestration-sagas-choreography-and-feedback-loops-as-transducers.md`
- `docs/research/future-directions-profunctors-effects-and-composition.md`

Outputs:

- `docs/research/effects-boundary.md` — new design note.
- This plan's living sections, kept current.
- The master plan's Exec-Plan Registry and Progress section, updated on completion.

Tooling:

- `mori` for surveying comparable libraries. **Never search `/nix/store`.**
- `git` for commits with the required trailers.

This plan does not depend on plan 1 (DSL shape) or plan 2 (schema evolution) — the
effects boundary is largely independent of both. Plan 4 (prototype) consumes the
directional guidance produced here ("v1 implements only `Keiki.Core`, with `step` and
`reconstitute` as primary exports") to scope its own work.
