---
id: 73
slug: decide-replay-round-trip-property-harness-across-all-fixtures
title: "Decide-replay round-trip property harness across all fixtures"
kind: exec-plan
created_at: 2026-07-12T04:16:45Z
intention: "intention_01kxc5whw1en3ra4nh728m53ka"
master_plan: "docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md"
---

# Decide-replay round-trip property harness across all fixtures

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

keiki is a pure event-sourcing core. Its foundational promise is that the event log is
a faithful record of state: if you run a transducer forward over a sequence of commands
(via `step` in `src/Keiki/Core.hs`, lines 910-918) and collect the events it emits,
then replaying that log through the inversion machinery (`reconstitute` at
Core.hs:1131-1136, `applyEvents` at Core.hs:1167-1179) must reproduce exactly the state
— both the control vertex and the register values — that forward execution produced.
Everything downstream (snapshots, hydration in the keiro framework, the `Decider`
facade) leans on this law.

The 2026-07 architecture review found that this law is not property-tested anywhere in
the repository. At least three latent defects — multi-event head-recoverability, the
`evolve` tail-drop, and cross-edge inversion ambiguity — would each have been caught by
a single QuickCheck property that generates command sequences, runs them forward, and
replays the log. This plan builds that property harness as permanent regression
infrastructure: a reusable `roundTripSpec` function so that registering a new fixture is
one line, state-aware command generators per fixture, a negative "tamper" layer proving
the harness has teeth, and coverage of every fixture in `test/Keiki/Fixtures/` plus the
eight worked-example aggregates in `jitsurei/`.

After this plan, `cabal test all` runs the round-trip property over every fixture, and
a developer who reintroduces the head-recoverability bug's edge shape sees a readable
QuickCheck counterexample naming the command sequence, the emitted log, the forward
state, and the replay outcome. This is Phase 2 of the master plan at
`docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md`
and is release-gating for `0.1.0.0`.

Dependency status (from the master plan's registry): this plan has a HARD dependency on
plan 71 (`docs/plans/71-align-build-time-validation-with-replay-head-recoverability-cross-edge-inversion-ambiguity-and-guard-implies-input-read-checks.md`)
— before EP-71's fix, the property provably fails on union-covered multi-event
fixtures, and EP-71 also supplies the stateful (`TReg`-emitting) and multi-event
fixtures this harness must reuse (master plan integration point 4). It has a SOFT
dependency on plan 72 (`docs/plans/72-structured-replay-diagnostics-reconstituteeither-strict-evolve-policy-and-multi-event-outputacceptor.md`),
whose `reconstituteEither` structured failure reasons the harness renders in
counterexample output when available. Milestones 1-3 below compile and pass against
today's fixtures without EP-71 (the two existing fixtures are head-recoverable), but
this plan is only complete — and its acceptance only meaningful — once EP-71 is
Complete in the master plan registry.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented
here, even if it requires splitting a partially completed task into two ("done" vs.
"remaining"). This section must always reflect the actual current state of the work.

- [x] Preflight: confirm EP-71 status in the master plan registry; enumerate the fixture modules it added under `test/Keiki/Fixtures/`
- [x] M1: add `QuickCheck ^>=2.15` to the `keiki-test` suite in `keiki.cabal`
- [x] M1: create `test/Keiki/RoundTrip.hs` (fixture bundle, complete-run forward driver, whole-log property, chunked property, validation sanity check, counterexample rendering)
- [x] M1: add `Ord` to the vertex enums of the two existing fixtures if EP-71 has not already
- [x] M1: create `test/Keiki/RoundTripSpec.hs` with bundles (generator + observation) for `Keiki.Fixtures.EmailDelivery` and `Keiki.Fixtures.UserRegistration`; wire into `test/Spec.hs`
- [x] M1: deterministic invalid-fixture spec pairing `StateChangingEpsilon` with the replay divergence it prevents
- [x] M2: tamper-case vocabulary in `test/Keiki/RoundTrip.hs`; tamper cases for both existing fixtures (drop, swap, duplicate, mid-chain truncation, foreign splice)
- [x] M3: `test/Keiki/Fixtures/BrokenTailCoverage.hs` (deliberately head-unrecoverable); teeth spec via `expectFailure` paired with a validator-flags-it assertion
- [x] M4: bundles for every EP-71 fixture (stateful `TReg`-emitting and multi-event ones); harness green over all of `test/Keiki/Fixtures/`
- [ ] M5: verbatim harness copy at `jitsurei/test/Jitsurei/RoundTrip.hs`; bundles for the 8 jitsurei aggregates (`UserRegistrationV0` under the teeth group); drift-check documented
- [ ] M6: measure suite wall-clock, pin property counts, document the deep-run command; run `nix fmt -- --no-cache`; update master plan registry row 73 and its Progress checklist


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

Authoring-time findings that shaped the design (recorded here because they are
observations about the code, not choices):

- During EP-71 implementation, the naive round-trip law exposed the
  GDPR-before-confirmation edge of `Keiki.Fixtures.UserRegistration`: it moved
  `RequiresConfirmation → Deleted` while emitting nothing. EP-71 migrated that edge
  to emit `AccountDeleted`, so the fixture now belongs in this plan's green property
  corpus. Keep the regression in the corpus; do not recreate the old silent edge or
  truncate generated command sequences to hide it.
- `Keiki.Render.Inspector` (`src/Keiki/Render/Inspector.hs`) renders edge *structure*
  (guards, written-slot names via `writtenSlots`, output field terms), not the runtime
  *values* in a `RegFile`, so it cannot serve as the state-comparison vehicle.
- `validateTransducer` (Core.hs:1622-1626) requires `(Bounded s, Enum s, Ord s, Show s)`
  but both existing fixture vertex enums derive only `(Eq, Show, Enum, Bounded)`
  (`test/Keiki/Fixtures/EmailDelivery.hs:101-102`,
  `test/Keiki/Fixtures/UserRegistration.hs:185-190`); the harness's validation sanity
  check needs `Ord` added.
- The `keiki-test` suite has no QuickCheck dependency today (`keiki.cabal`,
  `test-suite keiki-test`); the sibling `keiki-codec-json` test suite already pins
  `QuickCheck ^>=2.15` and demonstrates the house style in
  `keiki-codec-json/test/Keiki/Codec/JSON/PropSpec.hs` (`forAllShow` with an explicit
  renderer, because heterogeneous types lack `Show`).
- `Jitsurei.UserRegistrationV0` (`jitsurei/src/Jitsurei/UserRegistrationV0.hs`) is
  *deliberately* head-unrecoverable — its `AccountConfirmed` event drops the
  `confirmCode` field for the hidden-input demonstration — so it belongs in the teeth
  group (expected failure), not the green group.

- The preflight found five pre-existing fixture modules. `RegisterEmission` is the
  stateful `TReg`-emitting replay fixture and `SplitCoverage.fixed` is the
  head-recoverable multi-event fixture added by EP-71; both pass the green harness.
  `CounterPipeline` predates EP-71 and its output carries the command only inside a
  derived arithmetic term, which `solveOutput` deliberately cannot invert. The
  validator reports it and the harness falsifies it, so `stageA` is represented in
  the teeth group instead of making a false green claim.


## Decision Log

Record every decision made while working on the plan.

- Decision: compare register files through a per-fixture total observation function
  `rtObserve :: s -> RegFile rs -> Text` that reads exactly the slots provably written
  on every event-emitting path into the given vertex, and nothing else.
  Rationale: `RegFile` (src/Keiki/Core.hs:200-204) has no `Eq` instance and unwritten
  slots are lazy `error "uninit: <slot>"` thunks seeded by `emptyRegFile`
  (src/Keiki/Generics.hs:319-332), so any comparison that forces all slots is partial.
  Rejected alternatives: (a) `Keiki.Codec.JSON.regFileToJSON` — forces every slot
  (throws on uninit), would bias fixtures toward initializing all slots, and couples
  keiki's test suite to the codec package; (b) `Keiki.Render.Inspector` — renders edge
  structure, not slot values (see Surprises); (c) spoon-style
  `unsafePerformIO`/`evaluate`/`try` thunk-catching to treat uninit as
  equal-if-both-uninit — impure, fragile, and comparing error messages is meaningless;
  (d) an `Eq (RegFile rs)` instance — needs `Eq` on every slot type and is still
  partial on uninit slots. The observation function is exactly how existing specs
  already compare state (`test/Keiki/CoreApplyEventsSpec.hs` reads `regs ! #email`
  etc. per vertex), it compares real register *values*, and it stays total. The
  TH-derived B-views (`userView`, `emailView`) are used where their live-slot lists
  cover all written slots, but they underapproximate in general (`registeredAt`
  appears in no `UserView` constructor), so each bundle hand-writes its observation.
  Date: 2026-07-12

- Decision: the round-trip property runs every generated command to completion; it
  never truncates before an accepted epsilon edge. Every green fixture must pass
  `defaultValidationOptions`, including EP-71's `StateChangingEpsilon` check. A
  deliberately invalid epsilon fixture pairs the warning with observed divergence.
  Rationale: truncation would certify only a prefix while claiming every produced log
  is replayable. State-preserving `UKeep` self-loops may remain in green fixtures
  because they do not change the compared state; state-changing silent transitions
  belong in the teeth group or must emit an event.
  Date: 2026-07-12

- Decision: the harness lives in keiki's own test suite (`test/Keiki/RoundTrip.hs`);
  jitsurei's test suite receives a verbatim copy (`jitsurei/test/Jitsurei/RoundTrip.hs`,
  differing only in the module header) with a documented `diff` drift check. Promotion
  to a published `keiki-quickcheck` support package is deferred to a post-`0.1.0.0`
  follow-up.
  Rationale: repo precedent deliberately isolates QuickCheck-carrying test toolkits
  from production dependency closures (`keiki-codec-json-test.cabal` exists precisely
  so that "packages built for production do not transitively pick up QuickCheck"), so
  neither the keiki library nor a public sublibrary of the about-to-be-released keiki
  package should carry it; creating and releasing a *new* Hackage package is release
  mechanics out of scope for a test-infrastructure plan; and jitsurei is unpublished
  (no `source-repository head` stanza in `jitsurei/jitsurei.cabal`), so a monorepo
  copy with a drift check is the cheapest correct sharing today. Cross-package
  `hs-source-dirs: ../test` sharing was rejected as sdist-hostile and HLS-fragile.
  Date: 2026-07-12

- Decision: command generators are state-aware — each fixture supplies
  `rtGenCommand :: s -> RegFile rs -> Gen ci` and the harness threads the generated
  prefix through `step` while generating, so most commands are plausible at the
  current vertex — with a weighted minority of implausible/garbage commands to
  exercise the rejected-command skip path. `UTCTime` and `Text` generators are
  hand-rolled in the harness (seconds-since-epoch via `Data.Time.Clock.POSIX`; short
  lowercase `Text` drawn partly from small pools so guard mismatches like a wrong
  confirmation code actually occur).
  Rationale: arbitrary garbage is rejected by guards and tests nothing; reading the
  live register file (e.g. `regs ! #confirmCode`) lets the generator produce the
  *correct* code most of the time, which is the only way to reach deep vertices. Small
  pools create deliberate collisions/mismatches. Hand-rolling avoids a
  `quickcheck-instances` dependency.
  Date: 2026-07-12

- Decision: the negative layer is a fixture-declared list of tamper cases, each with
  one of two expectations — `MustFailReplay` (replay returns `Nothing`) or
  `MustNotSilentlyMatch` (replay either fails or produces a vertex/observation pair
  different from the forward-final one) — rather than a universal "any mutation makes
  replay fail" property.
  Rationale: log validity is not provenance — some mutations of a valid log are other
  valid logs. Duplicating a `ConfirmationResent` event replays successfully to an
  identical state (the resend is idempotent on the same code); dropping the *last*
  event yields a valid shorter log; splicing a well-formed `ConfirmationResent` with a
  never-issued code at `RequiresConfirmation` replays fine because `solveOutput`
  inverts it to a valid `ResendConfirmation` command. A universal property would be
  false. Each fixture therefore declares mutations whose failure (or divergence) is
  semantically guaranteed by its own shape. Also note: "splice an event from a
  different fixture" is ill-typed (each log is `[co]` for that fixture's event type),
  so it is reinterpreted as splicing a well-typed event *value* at a vertex where no
  edge's head can invert it.
  Date: 2026-07-12

- Decision: the harness's teeth are proven permanently by a checked-in deliberately
  broken fixture (`test/Keiki/Fixtures/BrokenTailCoverage.hs`, the
  head-recoverability bug's edge shape) whose properties run under QuickCheck's
  `expectFailure`, paired with an assertion that `validateTransducer` flags it.
  Rationale: `expectFailure` passes when the property is falsified, so CI stays green
  while continuously proving the harness detects exactly the defect class that
  motivated this plan; the validator pairing demonstrates the Phase-2 agreement — the
  build-time gate (EP-71) and the runtime law reject the same shape.
  Date: 2026-07-12

- Decision: property counts start at QuickCheck's default 100 cases per property with
  command sequences capped at 15; the budget is measured in M6 and reduced (or the
  cap lowered) only if `cabal test all` wall-clock more than doubles. Deep runs use
  hspec's pass-through: `cabal test keiki-test --test-options='--qc-max-success=2000'`.
  Rationale: the forward/replay path is pure and z3-free (the `HsPred` `BoolAlg`
  instance evaluates with `evalPred`, Core.hs:595-601), so cases are microseconds;
  measurement beats guessing; the hspec flag gives a zero-code deep-run knob.
  Date: 2026-07-12

- Decision: `Jitsurei.UserRegistrationV0` registers in the teeth group (expected
  failure), not the green group.
  Rationale: it exists to demonstrate the hidden-input defect (its `AccountConfirmed`
  drops `confirmCode`), so a green round-trip over it is impossible by design; running
  it under `expectFailure` turns the pedagogical module into a second permanent teeth
  test.
  Date: 2026-07-12


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

This section is self-contained: a reader with only the working tree can implement the
plan from here.

**What keiki is.** keiki is a Haskell library (GHC 9.12, built with `nix develop` +
`cabal`) whose core abstraction is the *symbolic-register transducer*: a finite control
graph plus a typed register file. The single source of truth is the record
`SymTransducer phi rs s ci co` in `src/Keiki/Core.hs` (around line 636): `s` is the
control-vertex type (a small enum like `Vertex` or `EmailVertex`), `rs` is a type-level
list of named register slots, `ci` is the command (input) type, `co` is the event
(output) type, and `phi` is the guard-predicate carrier — always `HsPred rs ci` for
every fixture in this plan. Each vertex has outgoing `Edge`s; an edge has a `guard`
(predicate over registers and the command), an `update` (register writes), an `output`
(a list of event templates), and a `target` vertex.

**The register file.** `RegFile rs` (src/Keiki/Core.hs:200-204) is a heterogeneous
tuple indexed by the slot list. Slots are read with `(!)` and an `OverloadedLabels`
index: `regs ! #email`. Crucially, `emptyRegFile` (src/Keiki/Generics.hs:319-332)
seeds every slot with a *lazy error thunk* `error "uninit: <slot>"`, so reading a slot
that no edge has written crashes with a targeted message. `RegFile` has no `Eq` or
`Show` instance. This is why state comparison in this plan goes through per-fixture
observation functions (see Decision Log).

**Forward execution.** `step t (s, regs) ci` (Core.hs:910-918) finds the unique
outgoing edge of `s` whose guard is satisfied; it returns `Nothing` if zero or more
than one edge matches (a *rejected* command), or `Just (s', regs', events)` where
`events` is `[]` for an ε-edge (a silent transition), `[e]` for a letter edge, or
`[e1, e2, ...]` for a *multi-event edge* (one command atomically emitting several
events — e.g. the `StartRegistration` edge of the UserRegistration fixture emits
`RegistrationStarted` then `ConfirmationEmailSent`).

**Replay (inversion).** Replay walks the log without the commands: at a settled vertex
it finds the unique outgoing edge whose *head* output template inverts against the
observed event via `solveOutput` (rebuilding the command from the event's invertible
fields), checks the guard on the recovered command, applies the update, and — for
multi-event edges — queues the evaluated tail as an `InFlight` state
(Core.hs:1063-1066) that subsequent events must match one-by-one
(`applyEventStreaming`, Core.hs:1089-1118). `reconstitute t log` (Core.hs:1131-1136)
replays a whole log from `(initial t, initialRegs t)`; `applyEvents t (s, regs) chunk`
(Core.hs:1167-1179) replays a chunk from an arbitrary start. Both return `Maybe`; a
log ending mid-chain returns `Nothing`. *Head-recoverability* is the property that the
head event of a multi-event edge alone carries enough invertible fields to rebuild the
command — if a command field is only recoverable from a *tail* event, replay fails at
that edge; EP-71 makes `validateTransducer` (Core.hs:1622-1626) reject that shape at
build time.

**The fixtures.** `test/Keiki/Fixtures/EmailDelivery.hs` is a minimal two-vertex
aggregate (`EmailPending → EmailSentVertex` on `SendEmail`, emitting `EmailSent`).
`test/Keiki/Fixtures/UserRegistration.hs` is the canonical worked example: vertices
`PotentialCustomer | RequiresConfirmation | Confirmed | Deleted`; a multi-event
`StartRegistration` edge; a `ConfirmAccount` edge guarded by `requireEq` on the stored
`confirmCode`; a code-rotating `ResendConfirmation` self-loop; and event-emitting GDPR
edges from both `RequiresConfirmation` and `Confirmed`. EP-71 adds further fixtures
under `test/Keiki/Fixtures/` whose outputs
read registers (`TReg` fields) and whose multi-event edges are the review's risk
shapes; this plan must reuse them, not fork them (master plan integration point 4).
The `jitsurei/` package holds eight larger worked-example aggregates under
`jitsurei/src/Jitsurei/`: `CoreBankingSync`, `EmailDelivery`, `Loan`,
`LoanApplication`, `LoanWorkflow`, `OrderCart`, `UserRegistration`,
`UserRegistrationV0`.

**The test framework.** Both test suites are hspec `exitcode-stdio-1.0` suites with a
hand-maintained `Spec.hs` (`test/Spec.hs`, `jitsurei/test/Spec.hs`) that imports each
spec module and calls `describe`. Property testing exists in the repo only in
`keiki-codec-json/test/Keiki/Codec/JSON/PropSpec.hs` (QuickCheck `^>=2.15` with
`forAllShow` and an explicit counterexample renderer); the `keiki-test` suite must gain
the QuickCheck dependency in this plan.

**A property test**, for the novice: a QuickCheck property is a function from randomly
generated inputs to a pass/fail verdict; the runner generates (by default) 100 inputs,
and on failure *shrinks* the input to a minimal failing case and prints it (the
*counterexample*). hspec integrates via `Test.Hspec.QuickCheck.prop`.


## Plan of Work

### The property, precisely

For every registered fixture transducer `t` (guard carrier `HsPred rs ci`) and every
generated command sequence `cs :: [ci]`:

Define the *forward trace* by folding `step t` from `(initial t, initialRegs t)` over
`cs`: a command for which `step` returns `Nothing` is **skipped** (state unchanged, no
log contribution); a command for which `step` returns `Just (s', regs', es)` with
`es` non-empty **advances** the state and appends `es` (in order) to the log; an
accepted command with `es = []` also advances the forward state and the driver
continues. Green fixtures may contain such a step only when default validation proves
it state-preserving. Let `log` be the concatenation of all emitted
chunks, `sF` the forward-final vertex, `regsF` the forward-final register file, and
`obs = rtObserve` the fixture's observation function.

- **P1 (whole-log round trip).** `reconstitute t log` must be `Just (sR, regsR)` with
  `sR == sF` and `obs sR regsR == obs sF regsF`. (Replay only traverses event-emitting
  edges, so `sR` is always a vertex for which `obs` is total.)
- **P2 (chunked round trip).** Folding per-command chunks through `applyEvents`:
  starting from `r0 = (initial t, initialRegs t)`, for each accepted step `i` with
  chunk `es_i`, forward vertex `s_i`, and forward observation `o_i`,
  `applyEvents t r_{i-1} es_i` must be `Just r_i = Just (v_i, w_i)` with `v_i == s_i`
  and `obs v_i w_i == o_i`. This checks that replay agrees with forward execution at
  *every command boundary*, from every intermediate state — not just at the end.
- **P3 (tamper / negative).** For each fixture-declared tamper case (a named log
  mutation — dropping an event, swapping two events, duplicating an event, truncating
  mid-chain, splicing a foreign event value — together with an expectation): when the
  mutation applies to the generated log, replay of the mutated log must satisfy the
  expectation — `MustFailReplay` (result is `Nothing`) or `MustNotSilentlyMatch`
  (result is `Nothing`, or a state whose vertex/observation differs from the forward
  final). Replay must never silently reproduce the forward state from a log the run
  did not produce, for mutations whose divergence the fixture's shape guarantees.

Each fixture also gets one deterministic sanity example: `validateTransducer
defaultValidationOptions t` returns `[]` — tying the harness to the Phase-2 law "a
transducer that passes validation replays every log it produces".

### Milestone 1 — harness core over the two existing fixtures

Scope: the reusable harness module, the QuickCheck dependency, bundles for
`EmailDelivery` and `UserRegistration`, and the invalid-epsilon teeth spec. At the end
of M1, `cabal test keiki-test` runs P1/P2 (plus the validation example) green over both
fixtures.

Edit `keiki.cabal`: in `test-suite keiki-test`, add `QuickCheck ^>=2.15` to
`build-depends` and add `Keiki.RoundTrip` and `Keiki.RoundTripSpec` to
`other-modules`.

Create `test/Keiki/RoundTrip.hs` — the generic harness, fixture-agnostic. Its public
surface (see Interfaces and Dependencies for the full signatures):

```haskell
-- test/Keiki/RoundTrip.hs (shape sketch; the implementer owns the details)
data RoundTripFixture where
  RoundTripFixture ::
    (Bounded s, Enum s, Eq s, Ord s, Show s, Show ci, Eq co, Show co) =>
    { rtName :: String,
      rtTransducer :: SymTransducer (HsPred rs ci) rs s ci co,
      rtGenCommand :: s -> RegFile rs -> Gen ci,
      rtObserve :: s -> RegFile rs -> Text,
      rtTamperCases :: [TamperCase co]
    } ->
    RoundTripFixture

roundTripSpec :: RoundTripFixture -> Spec  -- registering a fixture is one line
teethSpec :: RoundTripFixture -> Spec      -- same properties under expectFailure
```

Notes for the implementer: the constraint set matches what the entry points need
(`Eq co` for `reconstitute`/`applyEvents`; `Bounded s, Enum s, Ord s, Show s` for
`validateTransducer`; `Show`s for counterexamples). GADT record fields over
existential variables cannot be used as selectors — pattern-match the constructor.
Inside the module implement:

1. The forward driver exactly as specified above (skip on `Nothing`, process every
   accepted step including zero-output steps), returning the per-step trace
   `[(events, vertex, observation)]` plus the final vertex and observation.
2. The sequence generator: `sized`, capped at 15 commands, threading `(s, regs)`
   through `step` while generating so `rtGenCommand` always sees the state the
   command will actually meet (rejected commands keep state; accepted epsilon commands
   use the returned state). Shrinking via
   `shrinkList (const [])` (element deletion only — deleting commands is always
   meaningful; mutating them is not), through `forAllShrinkShow` with a renderer that
   numbers the commands.
3. P1 and P2 as `Property` values, every failure path wrapped in `counterexample`
   output listing: the command sequence (marking each command accepted `*`, rejected
   `-`, or accepted-with-zero-output `ε`), the emitted log, the forward final `vertex | observation`,
   and the replay outcome. For the replay outcome: if `Keiki.Core` exports
   `reconstituteEither`/`applyEventsEither` by the time you implement (EP-72), call
   the `Either` variants and `show` the structured failure reason; otherwise render
   `Nothing` as `"Nothing (replay found no uniquely inverting edge or ended mid-chain)"`.
   Check the export list of `src/Keiki/Core.hs` at implementation time and record
   which branch you took in this plan's Decision Log.
4. Shared value generators `genUTCTime :: Gen UTCTime` (whole seconds via
   `posixSecondsToUTCTime . fromInteger <$> choose (0, 2_000_000_000)`) and
   `genShortText :: Gen Text` plus `genFromPool :: [Text] -> Gen Text` (mostly pool
   draws, occasionally fresh) for fixture generators to reuse.
5. The `validateTransducer defaultValidationOptions t == []` example inside
   `roundTripSpec`, and its negation (warnings must be non-empty) inside `teethSpec`.

If EP-71 has not already done so, add `Ord` to the `deriving` clauses of `EmailVertex`
(`test/Keiki/Fixtures/EmailDelivery.hs:102`) and `Vertex`
(`test/Keiki/Fixtures/UserRegistration.hs:190`) — a non-breaking addition needed by
`validateTransducer`.

Create `test/Keiki/RoundTripSpec.hs` holding `allFixtures :: [RoundTripFixture]`, the
per-fixture generators and observations (they live here, next to the harness, so the
shared fixture modules stay unforked), and `spec = mapM_ roundTripSpec allFixtures <>
teeth-group`. The two M1 bundles:

- **EmailDelivery**: generator emits `SendEmail` with generated recipient/subject/at
  at any vertex (at the terminal vertex every command is rejected, exercising the skip
  path). Observation: `EmailPending → "(no slots)"`; `EmailSentVertex →` render
  `regs ! #emailRecipient`, `regs ! #emailSubject`, `regs ! #emailSentAt` (all three
  are written on the only path in; equivalently render the derived
  `emailView SEmailSentVertex regs`, whose live-slot list is complete for this
  fixture).
- **UserRegistration**: state-aware generator — at `PotentialCustomer` mostly
  `StartRegistration` (fresh email, code from a small pool, `genUTCTime`), sometimes
  other constructors (rejected); at `RequiresConfirmation` a weighted mix of
  `ConfirmAccount` with the *correct* code (read `regs ! #confirmCode`),
  `ConfirmAccount` with a wrong pool code (rejected by `requireEq`),
  `ResendConfirmation` with a new pool code, and `FulfillGDPRRequest`; use the
  post-EP-71 fixture in which every durable state-changing path emits an event; at
  `Confirmed` mostly `FulfillGDPRRequest` (emits
  `AccountDeleted`); at `Deleted` anything (rejected). Observation by vertex, reading
  only provably-written slots: `PotentialCustomer → "(no slots)"`;
  `RequiresConfirmation → email, confirmCode, registeredAt`; `Confirmed →` those plus
  `confirmedAt`; `Deleted →` every slot guaranteed by the event-emitting path that
  reached it. Keep observations total across both deletion paths.

Wire into `test/Spec.hs`: import `Keiki.RoundTripSpec qualified` and add
`describe "Keiki.RoundTrip (EP-73)" Keiki.RoundTripSpec.spec`.

Also in M1, add a deliberately invalid transducer with the old state-changing epsilon
shape. Assert that EP-71 reports `StateChangingEpsilon`, forward execution changes its
state without extending the log, and replay remains at the pre-transition state. Keep
this fixture under `teethSpec`; the post-EP-71 `userReg` belongs in the green registry.

Acceptance: from the repository root, `nix develop` then `cabal test keiki-test` —
suite green; the run output shows the new `Keiki.RoundTrip (EP-73)` group with both
fixtures. Temporarily changing the P1 assertion to compare against the wrong vertex
must produce a counterexample naming commands, log, forward state, and replay outcome
(then revert).

### Milestone 2 — tamper layer (negative properties)

Scope: the tamper vocabulary in `test/Keiki/RoundTrip.hs` and guaranteed-divergence
cases for both existing fixtures. At the end, replay's refusal to silently accept
corrupted logs is under test.

Add to the harness:

```haskell
data TamperExpectation = MustFailReplay | MustNotSilentlyMatch

data TamperCase co = TamperCase
  { tcName :: String,
    tcMutate :: [co] -> Maybe [co], -- Nothing when the log has no applicable site
    tcExpect :: TamperExpectation
  }
```

`roundTripSpec` runs one property per tamper case: generate a run as in P1; if
`tcMutate log` is `Nothing`, the case is vacuously true for that input but must be
`QuickCheck.cover`-ed (target ≥ 30% applicability; use `checkCoverage` only if the
rate proves unstable) so a fixture whose generator never produces an applicable log is
flagged. Otherwise assert the expectation against `reconstitute t mutatedLog` (and the
forward final observation for `MustNotSilentlyMatch`).

UserRegistration tamper cases (each guaranteed by the fixture's shape — see the
Decision Log entry for why universal mutations are unsound):

1. `"drop chain tail"` — remove the first `ConfirmationEmailSent`; the replay queue
   expects it next and nothing else can equal it → `MustFailReplay`.
2. `"swap chain events"` — swap the first `RegistrationStarted` with the following
   `ConfirmationEmailSent`; at `PotentialCustomer` the only edge head inverts
   `RegistrationStarted`, not `ConfirmationEmailSent` → `MustFailReplay`.
3. `"truncate mid-chain"` — cut the log immediately after the first
   `RegistrationStarted`; replay ends `InFlight` → `MustFailReplay`.
4. `"duplicate chain head"` — insert a second copy of the first `RegistrationStarted`
   after its chain completes; no edge out of `RequiresConfirmation` has a
   `RegistrationStarted` head (ε-edges never match during replay) → `MustFailReplay`.
5. `"foreign splice"` — prepend a well-typed `AccountConfirmed` event with generated
   payload; no edge out of `PotentialCustomer` inverts it → `MustFailReplay`.

EmailDelivery tamper cases: `"drop only event"` (empty log replays to `EmailPending`,
differing from forward `EmailSentVertex`) → `MustNotSilentlyMatch`; `"duplicate event"`
(second `EmailSent` at the terminal vertex has no edge) → `MustFailReplay`.

Acceptance: `cabal test keiki-test` green; temporarily weakening one tamper case's
expected outcome (e.g. asserting `MustFailReplay` succeeds) makes it fail with a
counterexample showing the mutated log (then revert).

### Milestone 3 — teeth: the head-recoverability regression shape

Scope: a deliberately broken fixture reproducing the review's head-recoverability
defect, run under `expectFailure`, paired with the validator. This is the acceptance
demonstration required of this plan and it stays in the tree permanently.

Create `test/Keiki/Fixtures/BrokenTailCoverage.hs` (add to `other-modules`): a minimal
two-vertex aggregate whose single edge's command coverage lives in the *tail* event —
command `Provision ProvisionData { owner :: Text, quota :: Int }`, events
`OwnerRecorded OwnerRecordedData { owner :: Text }` then
`QuotaAssigned QuotaAssignedData { quota :: Int }`, vertices `BtcIdle | BtcProvisioned`
(derive `Eq, Show, Enum, Bounded, Ord`), both slots written. Follow the TH pattern of
`test/Keiki/Fixtures/EmailDelivery.hs` (`deriveAggregateCtors`, `deriveWireCtors`,
builder syntax with two `B.emit`s). The head event `OwnerRecorded` cannot rebuild
`ProvisionData` (the `quota` field is only in the tail), so `solveOutput` fails on the
head and `reconstitute` returns `Nothing` for every non-empty log. Module haddock must
state loudly that the module is intentionally defective, exists as the EP-73 teeth
test for the EP-71 defect class, and must never be used as an example. If EP-70/71
have made `buildTransducer` reject this shape eagerly by the time you implement,
construct the transducer through the raw `SymTransducer`/`Edge` records instead (the
AST style at the bottom of `test/Keiki/Fixtures/EmailDelivery.hs`), which bypasses the
builder gate on purpose.

In `test/Keiki/RoundTripSpec.hs` register it via `teethSpec`: P1/P2 under
`expectFailure` (QuickCheck passes the test when the property is falsified — the suite
stays green while proving the harness catches this shape) and an example asserting
`validateTransducer defaultValidationOptions brokenTailCoverage` is non-empty
(post-EP-71 it must flag head-unrecoverability), demonstrating that the build-time
gate and the runtime law agree on this shape from both directions.

Acceptance: suite green; removing `expectFailure` from the teeth property shows the
readable counterexample reproduced in Validation and Acceptance below (then restore).

### Milestone 4 — every EP-71 fixture

Scope: extend `allFixtures` to all of `test/Keiki/Fixtures/`. Precondition: EP-71 is
Complete (check the Status column of the registry in
`docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md`
and plan 71's own Progress section) — before its fix the property provably fails on
union-covered multi-event fixtures.

List the modules under `test/Keiki/Fixtures/` at implementation time (EP-71 adds
stateful fixtures whose outputs carry `TReg` register reads, and multi-event fixtures
splitting coverage across outputs; their names are EP-71's to choose). For each: read
the module; write a state-aware generator and a per-vertex observation reading exactly
the provably-written slots (derive the written-slot sets by reading each edge's
`update` — the builder's `.=` lines — along every event-emitting path into the
vertex); add tamper cases where the shape guarantees divergence (at minimum
`"truncate mid-chain"` for every fixture with a multi-event edge — guaranteed by
`InFlight` semantics); register the bundle. Do not modify the fixtures themselves
beyond a missing `Ord` derivation (integration point 4: reuse, do not fork).

Acceptance: `cabal test keiki-test` green with every fixture module represented in the
`Keiki.RoundTrip (EP-73)` output; this checks off the master plan Progress item
"EP-73: round-trip property ... green over every fixture including multi-event and
stateful ones".

### Milestone 5 — the eight jitsurei aggregates

Scope: extend coverage to `jitsurei/`. Copy `test/Keiki/RoundTrip.hs` verbatim to
`jitsurei/test/Jitsurei/RoundTrip.hs`, changing only the `module` line (keep the
declaration on one line) and adding a header comment naming the master copy and the
drift check. Create `jitsurei/test/Jitsurei/RoundTripSpec.hs` with bundles for
`Jitsurei.CoreBankingSync`, `Jitsurei.EmailDelivery`, `Jitsurei.Loan`,
`Jitsurei.LoanApplication`, `Jitsurei.LoanWorkflow`, `Jitsurei.OrderCart`, and
`Jitsurei.UserRegistration` (green group), and `Jitsurei.UserRegistrationV0` under
`teethSpec` (deliberately head-unrecoverable — see Decision Log; verify against EP-71's
outcome and record what you find). Read each aggregate before writing its generator;
apply the same method as M1/M4 (state-aware weights, correct-vs-wrong guard values
drawn from pools, observations over provably-written slots). Every green bundle must
pass post-EP-71 default validation. Any remaining state-changing epsilon example is
either migrated to an emitted event or placed in the invalid teeth group; the driver
does not truncate around it.
Update `jitsurei/jitsurei.cabal`'s test-suite: add `QuickCheck ^>=2.15` (plus `text`
and `time` if not present) to `build-depends` and the two new modules to
`other-modules`; wire the describe line into `jitsurei/test/Spec.hs`.

Acceptance: `cabal test all` green across all four packages; the drift check below
prints nothing:

```bash
diff <(sed 's/Keiki\.RoundTrip/HARNESS/g' test/Keiki/RoundTrip.hs) \
     <(sed 's/Jitsurei\.RoundTrip/HARNESS/g' jitsurei/test/Jitsurei/RoundTrip.hs)
```

(Only the module-name occurrences and the header comment may differ; if the header
comment also differs, extend the `sed` normalization accordingly and record it here.)

### Milestone 6 — CI budget, formatting, bookkeeping

Scope: keep `cabal test all` fast and close the plan. Time the suite before and after
(`cabal test all` wall-clock, e.g. via `time`); if the total more than doubles, lower
the per-property case count with `Test.Hspec.QuickCheck.modifyMaxSuccess` on the
round-trip groups (floor: 50) or reduce the sequence cap, and record the numbers in
Surprises & Discoveries. Document the deep-run knob (it already works with no code):

```bash
cabal test keiki-test --test-options='--qc-max-success=2000'
```

(hspec forwards `--qc-max-success` to QuickCheck; `--seed <n>` reproduces a failing
run.) Run `nix fmt -- --no-cache` and fix any drift. Update the master plan
(`docs/masterplans/16-...md`): registry row 73 → Complete, tick its EP-73 Progress
item. Fill this plan's Outcomes & Retrospective. Commit per milestone throughout, with
Conventional Commits messages, e.g. `test(round-trip): add decide-replay round-trip
property harness (EP-73 M1)`.


## Concrete Steps

All commands run from the repository root (`/Users/shinzui/Keikaku/bokuno/keiki` on
the authoring machine; adjust to your checkout). Enter the dev shell first:

```bash
nix develop
```

Preflight (before M1):

```bash
grep -n "| 71 |" docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md
ls test/Keiki/Fixtures/
grep -n "reconstituteEither" src/Keiki/Core.hs || echo "EP-72 not landed: render Maybe outcomes"
```

The first command shows EP-71's registry row (Status must be Complete before M4; M1-M3
may proceed earlier). The second enumerates the fixture modules to cover. The third
decides the counterexample-rendering branch (see M1 step 3).

Build and test loop, after each edit:

```bash
cabal build all
cabal test keiki-test --test-show-details=direct
```

Expected shape of the new output once M1 lands (case counts appear on properties with
hspec's default formatter when they fail; on success you see the green items):

```text
Keiki.RoundTrip (EP-73)
  EmailDelivery
    passes validateTransducer with defaultValidationOptions [✔]
    P1: whole-log replay reproduces the forward state [✔]
    P2: chunked replay agrees at every command boundary [✔]
  UserRegistration
    passes validateTransducer with defaultValidationOptions [✔]
    P1: whole-log replay reproduces the forward state [✔]
    P2: chunked replay agrees at every command boundary [✔]
  StateChangingEpsilon (teeth)
    default validation rejects the silent state change [✔]
    replay divergence is demonstrated intentionally [✔]
```

After M5, the full matrix:

```bash
cabal test all
```

Formatting before every commit:

```bash
nix fmt -- --no-cache
```

Deep run (manual, before release or after touching replay code):

```bash
cabal test keiki-test --test-options='--qc-max-success=2000'
cabal test jitsurei-test --test-options='--qc-max-success=2000'
```


## Validation and Acceptance

The plan is accepted when all of the following hold.

1. `cabal test all` (from the repo root, inside `nix develop`) is green, and the
   round-trip groups cover: both original fixtures, every EP-71 fixture under
   `test/Keiki/Fixtures/` (including the stateful `TReg`-emitting and multi-event
   ones), and the eight jitsurei aggregates (`UserRegistrationV0` in the teeth
   group). Registering a fixture is one entry in `allFixtures` — verify by reading
   `test/Keiki/RoundTripSpec.hs`.

2. The harness has demonstrable teeth: `test/Keiki/Fixtures/BrokenTailCoverage.hs`
   (an edge whose command coverage lives in the tail event — the head-recoverability
   defect shape) is falsified by P1. With the `expectFailure` wrapper temporarily
   removed, the failure must read like this (payload values will differ; the shape —
   commands, log, forward state, replay outcome — must not):

   ```text
   Failures:

     test/Keiki/RoundTrip.hs:NN:
     1) Keiki.RoundTrip (EP-73), BrokenTailCoverage (teeth: deliberately head-unrecoverable), P1: whole-log replay reproduces the forward state
          Falsified (after 1 test and 2 shrinks):
            commands (* accepted, - rejected, ε accepted-with-zero-output):
              1. * Provision (ProvisionData {owner = "a", quota = 0})
            event log:
              [OwnerRecorded (OwnerRecordedData {owner = "a"}),
               QuotaAssigned (QuotaAssignedData {quota = 0})]
            forward final: BtcProvisioned | owner="a" quota=0
            replay: Nothing (replay found no uniquely inverting edge or ended mid-chain)

   Randomized with seed 1841503716
   ```

   With EP-72 landed, the `replay:` line instead renders `reconstituteEither`'s
   structured reason (which event index, which vertex, why no edge inverted). Restore
   `expectFailure` after observing this; the checked-in form passes precisely because
   the property fails.

3. The teeth pairing holds: the same broken fixture is flagged by
   `validateTransducer defaultValidationOptions` (non-empty warnings, post-EP-71),
   asserted by a green example — the build-time gate and the runtime law reject the
   same shape.

4. The negative layer is live: each fixture's tamper cases pass, their applicability
   coverage labels show mutations actually firing, and the invalid epsilon fixture
   pairs `StateChangingEpsilon` with the forward/replay divergence it prevents. No
   green property run is truncated.

5. `nix fmt -- --no-cache` produces no diff, and the master plan registry row for
   EP-73 reads Complete with its Progress item checked.

Beyond-compilation proof for a reviewer in a hurry: run
`cabal test keiki-test --test-options='--qc-max-success=1000 --match "RoundTrip"'`,
then open `src/Keiki/Core.hs`, swap the order of two events in
`applyEventStreaming`'s evaluated tail (or make `applyEvents` ignore a trailing
`InFlight`), rebuild, and watch the harness fail with a counterexample; revert.


## Idempotence and Recovery

Every step is additive: new test modules, new cabal `other-modules`/`build-depends`
entries, one new deliberately-broken fixture, and (at most) `Ord` derivations on
fixture vertex enums. Re-running any milestone's edits is safe; re-running the test
commands is always safe. Nothing touches library code, wire formats, or published API,
so there is no rollback hazard: reverting is `git revert` of the test-only commits. If
M4 begins and the EP-71 fixtures turn out not to exist yet (dependency slipped), stop,
record the fact in Surprises & Discoveries, and land M1-M3 alone — they are
independently valuable and green. If a property is flaky (a tamper case whose
mutation applicability collapses under shrinking, for example), pin the failing seed
with `--seed`, minimize by hand, and either strengthen the fixture's tamper mutation
or downgrade the expectation to `MustNotSilentlyMatch` with a dated Decision Log
entry explaining why.


## Interfaces and Dependencies

Dependencies added: `QuickCheck ^>=2.15` to `test-suite keiki-test` in `keiki.cabal`
and to `test-suite jitsurei-test` in `jitsurei/jitsurei.cabal` (matching the pin in
`keiki-codec-json/keiki-codec-json.cabal`). No library-component dependency changes
anywhere; no new packages (see Decision Log on the deferred `keiki-quickcheck`).

From `Keiki.Core` (src/Keiki/Core.hs) the harness consumes: `SymTransducer` (fields
`initial`, `initialRegs`, `edgesOut`, `isFinal`), `RegFile`, `(!)`, `HsPred`, `step`,
`reconstitute`, `applyEvents`, `validateTransducer`, `ValidationOptions`,
`defaultValidationOptions`, and — when EP-72 has landed — the `Either`-returning
replay variants and their failure type.

Module `Keiki.RoundTrip` (`test/Keiki/RoundTrip.hs`; verbatim copy
`Jitsurei.RoundTrip` at `jitsurei/test/Jitsurei/RoundTrip.hs`) must export, by end of
M2:

```haskell
data RoundTripFixture where
  RoundTripFixture ::
    (Bounded s, Enum s, Eq s, Ord s, Show s, Show ci, Eq co, Show co) =>
    { rtName :: String,
      rtTransducer :: SymTransducer (HsPred rs ci) rs s ci co,
      rtGenCommand :: s -> RegFile rs -> Gen ci,
      rtObserve :: s -> RegFile rs -> Text,
      rtTamperCases :: [TamperCase co]
    } ->
    RoundTripFixture

data TamperExpectation = MustFailReplay | MustNotSilentlyMatch

data TamperCase co = TamperCase
  { tcName :: String,
    tcMutate :: [co] -> Maybe [co],
    tcExpect :: TamperExpectation
  }

roundTripSpec :: RoundTripFixture -> Spec
teethSpec :: RoundTripFixture -> Spec
genUTCTime :: Gen UTCTime
genShortText :: Gen Text
genFromPool :: [Text] -> Gen Text
```

Module `Keiki.RoundTripSpec` (`test/Keiki/RoundTripSpec.hs`) exports `spec :: Spec`
and holds `allFixtures :: [RoundTripFixture]` plus the per-fixture generators,
observations, and tamper cases; `Jitsurei.RoundTripSpec`
(`jitsurei/test/Jitsurei/RoundTripSpec.hs`) mirrors it for the eight aggregates. New
fixture `Keiki.Fixtures.BrokenTailCoverage`
(`test/Keiki/Fixtures/BrokenTailCoverage.hs`) exports its transducer and types for the
teeth group only. Test entry points touched: `test/Spec.hs` and
`jitsurei/test/Spec.hs` (one import + one `describe` line each).

---

Revision note (2026-07-12): removed epsilon truncation from the property domain.
Green fixtures must pass EP-71's default-on `StateChangingEpsilon` check and generated
runs execute completely; a deliberately invalid silent-transition fixture pairs the
warning with its replay divergence.

Revision note (2026-07-12): initial full authoring, replacing the scaffold generated
by the master-plan decomposition. Design decisions (register-file comparison via
per-fixture observations, fixture-declared
tamper cases, harness sharing with jitsurei by verbatim copy, teeth via
`expectFailure` + validator pairing) are recorded with rationale in the Decision Log;
authoring-time code findings that forced them are in Surprises & Discoveries.
