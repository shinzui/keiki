---
id: 71
slug: align-build-time-validation-with-replay-head-recoverability-cross-edge-inversion-ambiguity-and-guard-implies-input-read-checks
title: "Align build-time validation with replay: head-recoverability, cross-edge inversion ambiguity, and guard-implies-input-read checks"
kind: exec-plan
created_at: 2026-07-12T04:16:45Z
intention: "intention_01kxc5whw1en3ra4nh728m53ka"
master_plan: "docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md"
---

# Align build-time validation with replay: head-recoverability, cross-edge inversion ambiguity, and guard-implies-input-read checks

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture


keiki is a pure event-sourcing core: an application author describes an aggregate as a
*symbolic-register transducer* (a finite control graph plus a typed register file), keiki
runs commands through it to produce events, and later *replays* the event log to
reconstruct the exact `(vertex, registers)` state. keiki also ships a build-time
validator, `validateTransducer`, whose promise — relied on by the downstream keiro
framework as a release gate for its event streams — is: **a transducer that validates
clean can always replay every log it can produce.**

The 2026-07 architecture review found four places where that promise is false today,
and this plan closes all four. After this plan:

1. A transducer whose multi-event edge spreads command information across several
   emitted events — so that the *first* event alone cannot reconstruct the command —
   is flagged at build time with a new `HeadUnrecoverable` warning telling the author
   to move the missing field into the first emitted event. Today such a transducer
   passes validation and then **fails to replay its own log** (empirically reproduced;
   transcript below). This is the highest-severity finding and the reason this plan is
   release-gating for `0.1.0.0`: keiki targets critical business applications, and a
   validated aggregate that cannot rehydrate its own history is the worst failure class
   an event-sourcing core can have.

2. Two edges leaving the same vertex whose first emitted events use the same event
   constructor can *both* invert one observed event during replay; replay demands a
   unique inverting edge and returns `Nothing` on a perfectly legitimate log. A new
   conservative structural check, `InversionAmbiguity`, flags such pairs at build time.

3. An edge whose guard does not pin the command constructor, but whose guard, update,
   or output reads a field of that constructor, makes `step`/`decide` **crash** (via
   `error`) instead of rejecting when a different command arrives. A new structural
   check, `UnguardedInputRead`, flags such edges at build time.

4. An empty-output edge that changes the vertex or can write registers is flagged as
   `StateChangingEpsilon`. The transition may be meaningful in a pure transducer, but
   an emitted event log cannot reconstruct it. The check is enabled by default;
   non-persisted callers may opt out deliberately, while current keiro rejects it at
   the `ValidatedEventStream` boundary for aggregates and process managers.

The observable outcome: running `cabal test all` shows a new spec proving, for every
shared fixture, "`validateTransducer` clean implies `reconstitute` of a step-produced
log succeeds"; the review's counterexample transducer now produces a
`HeadUnrecoverable` warning; and the keiro migration for the new warning constructors
is fully documented in this file (keiro pattern-matches the warning type exhaustively,
so the additions are a breaking change downstream that must land with its migration
recipe).


## Progress


Use this checklist to track granular steps. Every stopping point must be documented
here, splitting partially-done items into "done" and "remaining" parts.

- [x] Milestone 1: shared fixtures `test/Keiki/Fixtures/SplitCoverage.hs` and
      `test/Keiki/Fixtures/RegisterEmission.hs` created, registered in `keiki.cabal`,
      and compiling. (completed 2026-07-12 16:14 -0700)
- [x] Milestone 1: defect spec `test/Keiki/ValidationReplayAlignmentSpec.hs` added;
      the current validator-clean/replay-fails behavior is pinned and the future
      warning assertion is the sole pending example, keeping milestone commits green.
      (completed 2026-07-12 16:14 -0700)
- [x] Milestone 2: `hiddenInputReasons` reworked to head-based analysis;
      `HirHeadUnrecoverable` reason added; `HeadUnrecoverable` constructor added to
      `TransducerValidationWarning`; `checkHeadRecoverability` option added.
      (completed 2026-07-12 16:18 -0700)
- [x] Milestone 2: `test/Keiki/CoreHiddenInputsGSMSpec.hs` rewritten against the new
      semantics (the old union-passes-clean pin is deleted); red spec from Milestone 1
      goes green. (completed 2026-07-12 16:18 -0700)
- [ ] Milestone 3: `InversionAmbiguity` check implemented
      (`inversionAmbiguityWarnings`), wired into `validateTransducer`, specs added.
- [ ] Milestone 4: `UnguardedInputRead` check implemented
      (`guardImpliesInputReadWarnings`), wired into `validateTransducer`, specs added.
- [ ] Milestone 5: `StateChangingEpsilon` warning and
      `checkStateChangingEpsilon` option added; no-op `UKeep` self-loop remains clean;
      state-changing cases and replay divergence tested.
- [ ] Milestone 6: full-suite audit — every pre-existing fixture/spec that now warns is
      classified and fixed; `cabal test all` green; `nix fmt -- --no-cache` clean.
- [ ] Milestone 7: haddocks updated (replay contract stated on `validateTransducer`,
      `applyEventStreaming`, `solveOutput`); `CHANGELOG.md` entry written; keiro
      migration section below confirmed against keiro's actual source.
- [ ] Master plan registry row for EP-71 flipped to Complete; Outcomes &
      Retrospective written.


## Surprises & Discoveries


Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation, with concise evidence.

- **(from plan authoring, 2026-07-12)** The head-recoverability defect was re-reproduced
  in GHCi while writing this plan. Using the exact `goodUnion` transducer from
  `test/Keiki/CoreHiddenInputsGSMSpec.hs` (command `Begin a b c`, one edge emitting
  `[OutAB a b, OutBC b c]`):

  ```text
  ghci> checkHiddenInputs goodUnion
  []
  ghci> let Just (_, _, log1) = step goodUnion (False, RNil) (Begin 1 2 3)
  ghci> log1
  [OutAB 1 2,OutBC 2 3]
  ghci> reconstitute goodUnion log1
  Nothing        -- REPLAY OF THE TRANSDUCER'S OWN LOG FAILS
  ```

  The validator is clean; replay of the transducer's own freshly-produced log returns
  `Nothing`.

- **(from plan authoring, 2026-07-12)** `TLit` carries no `Eq` or `Typeable` evidence
  (`src/Keiki/Core.hs`, `data Term`, first constructor: `TLit :: r -> Term rs ci ifs r`),
  and the field types of an `OutTerm` are existentially hidden. Consequently the
  "differing literal fields" refinement originally imagined for the inversion-ambiguity
  check is **not implementable** against the current AST: two literals of unknown
  existential types cannot be compared. The distinguishability criterion in Milestone 3
  is therefore deliberately minimal (see Decision Log).

- **(scope correction, 2026-07-12)** Compatibility claims are based on keiki and
  current keiro only. The previous production-edge claim came from an outdated
  runtime example and has been removed. The in-tree SplitCoverage fixture is the
  reproducible worked example for head recoverability.

- **(implementation, 2026-07-12)** The canonical `EmailVertex` and User
  Registration `Vertex` fixtures did not derive `Ord`, so they could not be passed
  to `validateTransducer`, whose reachability check uses an ordered set. Both shared
  fixtures and the new `RegisterVertex` now derive `Ord`; no runtime behavior changed.

- **(implementation, 2026-07-12)** `userReg` is not validation-clean before
  Milestone 5 because its pre-confirmation GDPR edge is a state-changing ε-edge whose
  update reads the command. Milestone 1 therefore pins replay agreement on the
  persisted canonical path without claiming the whole fixture is clean; Milestone 6
  will migrate the ε-edge and add the clean assertion.


## Decision Log


- Decision: fix the validator, not replay. The hidden-input check will demand that the
  **head** output alone recovers every consumed command slot; replay
  (`applyEvent`/`applyEventStreaming`) is left semantically unchanged.
  Rationale (restated from the master plan
  `docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md`,
  Decision Log): making replay invert against the whole output chain would require
  running `solveOutput` across the `InFlight` queue with partially-committed register
  state — a semantic redesign of streaming replay — whereas head-recoverability is
  exactly the property `applyEventStreaming` already assumes. The validator should
  enforce the evaluator's actual contract. Authors who need tail-only fields
  restructure the edge (move the field into the first emitted event); revisit only if
  a real aggregate cannot be expressed.
  Date: 2026-07-12

- Decision: split the diagnosis into two constructors rather than widening
  `HiddenInput`. A slot missing from the head OPack **but present somewhere in the
  tail** gets the new `HeadUnrecoverable` warning ("the data is on the wire, but
  replay cannot reach it — move it into the first emitted event"). A slot missing from
  the union of **all** OPacks keeps the existing `HiddenInput` warning ("the data is
  not on the wire at all"). The two situations have different fixes, so they get
  different constructors and different guidance text.
  Date: 2026-07-12

- Decision: the inversion-ambiguity check flags **every** pair of same-vertex edges
  whose head OPacks name the same `WireCtor` (by `wcName`), exempting only pairs whose
  guard conjunction is the literal `PBot` (via `isBot` on the pure carrier). No
  literal-field distinguishability is attempted: `TLit` carries no `Eq`/`Typeable`
  evidence, so literals of existential type cannot be compared (see Surprises). This
  is conservative in the correct direction — false positives surface as warnings the
  author can suppress via `ValidationOptions`; false negatives would be silent replay
  failures. What the check cannot see is documented in Milestone 3.
  Date: 2026-07-12

- Decision: all four new checks are ON in `defaultValidationOptions`
  (`checkHeadRecoverability = True`, `checkInversionAmbiguity = True`,
  `checkGuardImpliesInputRead = True`, `checkStateChangingEpsilon = True`).
  Head-recoverability and absence of state-changing epsilon are the replay contract
  itself, so it cannot be off by default. The other two fire only on genuinely
  dangerous shapes: an `InversionAmbiguity` pair means some replayable log is
  ambiguous unless guards happen to disambiguate semantically (which the author can
  confirm and then opt out per-stream), and an `UnguardedInputRead` edge means `step`
  can call `error` on live input. This deliberately differs from the opt-in posture of
  `warnOpaqueGuards` (which is advisory about analysis blind spots, not about runtime
  failure).
  Date: 2026-07-12

- Decision: `StateChangingEpsilon` is a warning, not a hard Core or Builder
  prohibition. It fires when `output == []` and either `target /= source` or the
  update is structurally not `UKeep`.
  Rationale: keiki can also model pure, non-persisted transducers, so an explicit
  opt-out remains possible. The structural update test is conservative—a write may
  happen to preserve a particular value—but durable event sourcing cannot prove that
  from an absent event. Current keiro's normal `ValidatedEventStream` path rejects the
  default-on warning for aggregate and process-manager streams.
  Date: 2026-07-12

- Decision: the legacy string-based `checkHiddenInputs` reflects the new semantics too
  (it reports head-unrecoverable slots with a new message form). Its haddock's
  "byte-identical output" guarantee is narrowed to the reasons that keep existing
  (`HirEpsilonReadsInput`, `HirUnionMiss`); the union-passes-clean behaviour pinned by
  `test/Keiki/CoreHiddenInputsGSMSpec.hs:161` is deleted as a defect pin, not preserved
  as compatibility. Pre-`0.1.0.0` there are no external consumers of the string API to
  protect, and preserving a wrong answer in one API while fixing it in the other would
  reintroduce the disagreement this plan exists to remove.
  Date: 2026-07-12

- Decision: extending `ValidationOptions` with four new record fields is accepted as
  a source-breaking change for anyone constructing the record literally. Current
  keiro never constructs it literally — it passes
  `defaultValidationOptions` or a caller-supplied value
  (`keiro-core/src/Keiro/EventStream/Validate.hs`) — so downstream migration is limited
  to the `renderWarning` match arms documented below. The haddock on
  `ValidationOptions` will direct users to build options by record-update on
  `defaultValidationOptions` so future field additions stay cheap.
  Date: 2026-07-12

- Decision: the new fixtures live under `test/Keiki/Fixtures/` (module namespace
  `Keiki.Fixtures.*`), alongside the existing `UserRegistration` and `EmailDelivery`
  fixtures, and are written to be **shared**: plan 73
  (`docs/plans/73-decide-replay-round-trip-property-harness-across-all-fixtures.md`)
  will fold them into its property harness and plan 74
  (`docs/plans/74-fix-compose-update-snapshot-semantics-and-multi-event-chain-expansion-under-stateful-transducers.md`)
  will reuse the stateful/multi-event shapes. They must therefore export their
  transducers, commands, events, and (for the bad variant) the specific defective
  edge shape by name, with haddocks saying which plan consumes what.
  Date: 2026-07-12

- Decision: keep Milestone 1 green by asserting the current split-coverage defect
  and marking only the future `HeadUnrecoverable` expectation pending.
  Rationale: the plan explicitly permits a pending red assertion when CI policy
  requires working commits. The test still proves both halves of the defect:
  forward execution emits `[OutAB 1 2, OutBC 2 3]`, replay returns `Nothing`, and
  current default validation returns `[]`.
  Date: 2026-07-12


## Outcomes & Retrospective


(To be filled during and after implementation. Compare the result against the Purpose
section: does the red spec from Milestone 1 pass, does the GHCi counterexample warn,
is the keiro migration complete?)


## Context and Orientation


This section is self-contained; read it even if you know the repository.

### The library in one paragraph

keiki (this repository, library source under `src/`) models an event-sourced aggregate
as a `SymTransducer` (`src/Keiki/Core.hs:638`): a finite set of control *vertices*
(type parameter `s`, required to be `Bounded`/`Enum`), a typed *register file*
(`RegFile rs`, a heterogeneous list of named slots), and for each vertex a list of
outgoing `Edge`s (`src/Keiki/Core.hs:627`). An `Edge` has a `guard` (a predicate over
`(registers, command)`), an `update` (register writes), an `output` (a list of zero or
more event templates), and a `target` vertex. Running a command through `step`
(`src/Keiki/Core.hs:910`) finds the unique edge whose guard holds, applies its update,
and emits its outputs: an empty `output` is an "ε-edge" (silent transition), a
one-element `output` is a "letter edge", a two-or-more-element `output` is a
"multi-event edge" (one command, several events).

### How replay works, precisely

Replay reconstructs `(vertex, registers)` from the event log alone — the commands are
NOT stored. Each event template in an edge's `output` is an `OPack`
(`src/Keiki/Core.hs:779` builder `pack`): it names the *input constructor* (`InCtor`)
of the command the edge consumes, the *wire constructor* (`WireCtor`) of the event it
emits, and an `OutFields` list of `Term`s saying how each event field is computed —
from a literal (`TLit`), a register (`TReg`), a command field (`TInpCtorField`), or a
derived computation (`TApp1`/`TApp2`/`TArith`).

`solveOutput` (`src/Keiki/Core.hs:1212`) is the inverse direction: given one observed
event and one `OPack`, it walks the `OutFields` gathering the values of every
top-level `TInpCtorField` read, then calls `assemble` (`src/Keiki/Core.hs:385-402`) to
rebuild the command payload. **`assemble` returns `Just` only if every slot of the
input constructor is covered** — a single missing slot makes the whole inversion fail.

The replay drivers are `applyEvent` (`src/Keiki/Core.hs:1030-1045`, letter-only) and
`applyEventStreaming` (`src/Keiki/Core.hs:1089-1118`, the real one, used by
`reconstitute`/`applyEvents` and by keiro's hydration). Read
`applyEventStreaming`'s `Settled` arm carefully (`src/Keiki/Core.hs:1096-1110`): for
each outgoing edge it takes **only the head** of the edge's `output` list
(`o : _ <- [output e]`), inverts the observed event through that head via
`solveOutput`, checks the guard on the recovered command, and — if exactly one edge
succeeds — commits: it applies the update and *evaluates the tail templates forward*
against the recovered command, storing the resulting expected events in an `InFlight`
queue (`src/Keiki/Core.hs:1063`). Subsequent observed events are only
**equality-checked** against that queue (`src/Keiki/Core.hs:1111-1118`); they are
never inverted. So on replay, the command is recovered **from the head event alone**.

### Defect 1: the validator disagrees with replay about multi-event edges

The hidden-input validator's per-edge analysis is `hiddenInputReasons`
(`src/Keiki/Core.hs:1369-1424`). For a non-empty `output` it groups the edge's OPacks
by input-constructor name and computes the **union** of command slots visited across
*all* OPacks of the edge (`groupByInCtorName`, `src/Keiki/Core.hs:1385-1398`),
warning only if the union misses a slot. But as just described, replay uses the head
OPack alone. An edge for command `Begin a b c` emitting `[OutAB a b, OutBC b c]` has
union coverage `{a,b,c}` (validator: clean) but head coverage `{a,b}` (replay:
`assemble` misses `c`, `solveOutput` returns `Nothing`, no edge matches,
`reconstitute` of the transducer's OWN log returns `Nothing`). The transcript in
Surprises & Discoveries shows this live. The existing test
`test/Keiki/CoreHiddenInputsGSMSpec.hs:161` pins the union behaviour as correct
("well-formed multi-event edge (union covers all slots) ⇒ no warnings") and never
replays its fixture — the pin is itself the bug.

### Defect 2: nothing checks that replay's edge choice is unambiguous

Both `applyEvent` (`src/Keiki/Core.hs:1037-1045`) and `applyEventStreaming`
(`src/Keiki/Core.hs:1096-1110`) require a **unique** successfully-inverting edge —
the list comprehension must produce exactly one candidate or the result is `Nothing`.
If two edges out of one vertex both emit (as their head event) the same event
constructor, one observed event can invert through both: each edge's `solveOutput`
recovers *its own* command (they may even name different input constructors), and each
recovered command can satisfy its own guard. A legitimately-produced log then fails
replay. No existing check covers this output-side distinguishability: the determinism
checks are input-side guard-overlap only — `isSingleValuedSym`
(`src/Keiki/Symbolic.hs:615-632`) and `checkTransitionDeterminism`
(`src/Keiki/Core.hs:1743-1761`) both test `isBot (guard e1 ⊓ guard e2)`, which says
two guards cannot accept the same *command*, and says nothing about two edges' outputs
colliding on the same *event*.

### Defect 3: an unguarded input read crashes instead of rejecting

`evalTerm` on `TInpCtorField` (`src/Keiki/Core.hs:792-794`) calls `error` when the
runtime command is a different constructor than the term expects:

```haskell
evalTerm (TInpCtorField ic ix) _ ci = case icMatch ic ci of
  Just rf -> rf ! ix
  Nothing -> error ("evalTerm: TInpCtorField guard violation: " ++ icName ic)
```

The Builder's `onCmd` always conjoins `matchInCtor` (= `PInCtor`,
`src/Keiki/Core.hs:674`) into the guard, so builder-authored command edges are safe by
construction. But `onEpsilon` blocks, hand-built `Edge` records (see
`userRegASTEdges` in `test/Keiki/Fixtures/UserRegistration.hs` for the hand-built
style), or misuse of `emitWith` can pair a `PTop`-or-unrelated guard with an input
read in the guard's own terms, in the update, or in the output. Then evaluating the
edge — inside `delta`/`step`/`decide` — **crashes** on a mismatched command instead of
rejecting it. Nothing flags this statically today.

### Defect 4 (consequence, not code): the new warnings break keiro

The new checks extend `TransducerValidationWarning` (`src/Keiki/Core.hs:1538-1580`,
currently four constructors: `HiddenInput`, `NondeterministicPair`,
`PossiblyDeadEdge`, `OpaqueGuard`) and `ValidationOptions`
(`src/Keiki/Core.hs:1584-1607`, currently four flags). Current keiro pattern-matches
the warning type **exhaustively** in `renderWarning` at
`/Users/shinzui/Keikaku/bokuno/keiro/keiro-core/src/Keiro/EventStream/Validate.hs:147-155`.
Adding constructors makes keiro fail to compile (it builds with
`-Wincomplete-patterns` promoted appropriately) until the migration in the dedicated
section below is applied. This plan owns deciding the final constructor set for the
whole master-plan initiative — see "Coordination with plan 76" below.

### Where things live

All library changes in this plan land in `src/Keiki/Core.hs` (the validation section,
roughly lines 1300–1903, and the module export list at lines ~90–170). All test
changes land under `test/Keiki/` with module registration in `keiki.cabal`
(test-suite `keiki-test`, `other-modules`). The test entry point is
`test/Spec.hs`, a hand-maintained `main` that imports each spec module and runs it —
new spec modules must be added there as well as to the cabal file. The build
environment is `nix develop` (GHC 9.12); formatting is fourmolu via
`nix fmt -- --no-cache`.


## Plan of Work


The work is seven milestones. Milestone 1 makes the defect fail a test (red);
Milestones 2–5 add the four checks (each independently verifiable); Milestone 6
audits the whole suite against the new, stricter validator; Milestone 7 is
documentation, changelog, and downstream coordination. Work strictly in this order:
the red test first is not ceremony — it is the proof that the fixture reproduces the
production failure mode, and it becomes the permanent regression test.


### Milestone 1: shared fixtures and the red alignment spec

Scope: create the first test fixtures whose edges emit register reads and whose
multi-event edges split command coverage across outputs, plus a spec that states the
alignment law and fails on the defective fixture. At the end of this milestone the
suite has one deliberately-failing test demonstrating the bug; nothing in `src/` has
changed yet. (If the project's CI policy forbids committing a red test even briefly,
mark it `pendingWith "EP-71 Milestone 2 fixes this"` and un-pend it in Milestone 2 —
record whichever you did in Progress.)

Create `test/Keiki/Fixtures/SplitCoverage.hs`, module `Keiki.Fixtures.SplitCoverage`.
This is the review's GHCi repro promoted to a shared fixture (the template is the
`goodUnion`/`badUnion` code in `test/Keiki/CoreHiddenInputsGSMSpec.hs`, which you
should read now). It defines: a command type `data SplitCmd = Begin Int Int Int`
with an `InCtor` for `Begin` over slots `a`, `b`, `c` (hand-written like
`inCtorBegin` in the GSM spec, or TH-derived — hand-written is fine and keeps the
fixture dependency-free); an event type with wire constructors `OutAB Int Int`,
`OutBC Int Int`, and `OutABC Int Int Int`; and two transducers over vertex type
`Bool` (initial `False`):

- `splitCoverageBad` — one edge from `False` guarded `matchInCtor inCtorBegin`,
  emitting `[OutAB a b, OutBC b c]` (command coverage split: head covers `{a,b}`,
  tail covers `{b,c}`, union covers everything, head misses `c`). This is the exact
  transducer from the Surprises transcript.
- `splitCoverageFixed` — the repaired shape: same command, emitting
  `[OutABC a b c, OutBC b c]` (head covers everything; the tail event is then pure
  forward recomputation, which replay equality-checks).

Create `test/Keiki/Fixtures/RegisterEmission.hs`, module
`Keiki.Fixtures.RegisterEmission`. This is the first fixture whose edge outputs read
registers (`TReg` — spelled `proj #slot` — inside `OutFields`), isolated and
round-tripped. (The `UserRegistration` fixture already contains incidental `TReg`
emissions — e.g. the `AccountConfirmed` event's `email` field at
`test/Keiki/Fixtures/UserRegistration.hs:335` — but no fixture isolates the shape or
replays it from fresh registers, which is what plans 73/74 need.) Give it: registers
`'[ '("owner", Text), '("total", Int) ]`; a command `Open Text` whose edge writes
`owner` and emits `Opened Text` (command coverage only); and a command `Add Int`
whose edge (from the post-open vertex) writes `total` and emits a single event
`Added Int Text` where the `Int` field is the command field and the `Text` field is
`proj #owner` — a register read on the wire. Add a second, multi-event variant edge
for a command `Close` (no payload) emitting `[Closed Text, Archived Text]` where both
fields are `proj #owner` register reads — this gives plan 74 a multi-event edge whose
outputs depend on register state. Every command's slots must be head-recoverable
(this fixture is a *good* fixture; its point is `TReg` emission, not defects).
Remember `solveOutput` keeps observed values for `TReg` fields rather than
re-verifying them against current registers (`src/Keiki/Core.hs:1229-1251`), so this
fixture replays even from empty registers — the spec should assert exactly that.

Both fixture modules carry a module haddock stating: "Shared fixture, integration
point 4 of `docs/masterplans/16-...md`: consumed by EP-71 (validation alignment),
EP-73 (round-trip property harness), EP-74 (composition semantics). Do not fold into
a spec module." Register both in `keiki.cabal` under the `keiki-test` suite's
`other-modules` and (if any spec needs them re-exported) nowhere else.

Create `test/Keiki/ValidationReplayAlignmentSpec.hs`, module
`Keiki.ValidationReplayAlignmentSpec`, registered in `keiki.cabal` and imported/run
from `test/Spec.hs`. It states the alignment law as targeted examples (the full
property harness over generated command sequences is plan 73's job — do NOT build a
generator here):

- For each fixture transducer `t` in: `splitCoverageFixed`, the `RegisterEmission`
  transducer, `Keiki.Fixtures.UserRegistration.userReg`, and
  `Keiki.Fixtures.EmailDelivery`'s transducer — and a hand-chosen command sequence
  that exercises every edge at least once: fold `step` to produce the concatenated
  event log, assert `validateTransducer defaultValidationOptions t == []` (for
  fixtures expected clean), and assert `reconstitute t log` returns `Just` with the
  same `(vertex, registers)` the forward fold reached. (`RegFile` has no `Eq`
  instance in general; compare vertices directly and registers via the fixtures'
  slot reads with `!`, or via `show` where the fixture's slot types all have `Show`.)
- For `splitCoverageBad`: assert the forward fold succeeds and produces
  `[OutAB 1 2, OutBC 2 3]`, assert `reconstitute splitCoverageBad thatLog ==
  Nothing` (the defect, pinned forever), and assert — THIS IS THE RED ASSERTION —
  that `validateTransducer defaultValidationOptions splitCoverageBad` is non-empty.
  Before Milestone 2 that last assertion fails, because today the validator returns
  `[]` for it.

Acceptance for Milestone 1: `cabal build all` compiles; `cabal test all` runs and
fails with exactly the one expected red assertion (or shows it pending), whose failure
message demonstrates "validator clean but replay Nothing".


### Milestone 2: head-recoverability in the hidden-input analysis

Scope: make the validator demand that the head OPack alone recovers every consumed
command slot. At the end, `splitCoverageBad` produces a `HeadUnrecoverable` warning,
the Milestone 1 red test is green, and the GSM spec is rewritten.

Edit `src/Keiki/Core.hs`. Extend `HiddenInputReason` (line ~1353) with a third
constructor:

```haskell
  | -- | Slots of the named input constructor that ARE recovered somewhere in
    --   the edge's output union, but NOT by the head 'OPack' — so the data is
    --   on the wire, yet replay ('applyEventStreaming' inverts the head only)
    --   cannot reach it. Fix: move the field into the first emitted event.
    HirHeadUnrecoverable String [String]
```

Rework `hiddenInputReasons` (line ~1369). Keep the ε-edge arm unchanged. For the
non-empty-output arm, keep the existing `groupByInCtorName` union walk, and compute
additionally the head coverage: pattern-match the head OPack
(`OPack headIc _ headFields`) and reuse `detectMissingInCtorFields`
(`src/Keiki/Core.hs:1492-1520`) — it is essentially the right primitive: it returns
the slots of an `InCtor` that a given `OutFields` walk does not visit at top level.
Then for each input-constructor group `(icN, allSlots, unionVisited)`:

- `missingFromUnion = allSlots \\ nub unionVisited` — report `HirUnionMiss icN
  missingFromUnion` when non-empty (unchanged semantics: this data is nowhere on the
  wire).
- `headVisited` = the head OPack's visited slots when `icN == icName headIc`,
  otherwise `[]` (an input constructor named only by tail OPacks contributes nothing
  replay can use).
- `headOnlyMiss = (allSlots \\ nub headVisited) \\ missingFromUnion` — report
  `HirHeadUnrecoverable icN headOnlyMiss` when non-empty.

The union logic thereby survives only to *classify* the miss (off-wire vs
tail-only); it no longer suffices to pass. Update `formatHiddenInputReason`
(line ~1429) with a message for the new reason; suggested text (keep the established
"edge #N:" prefix):

```text
edge #0: head event does not recover InCtor "Begin" field(s) {"c"}; the data
appears only in later events of this edge, which replay cannot invert - move the
field(s) into the FIRST emitted event
```

Extend `TransducerValidationWarning` (line ~1538) with:

```haskell
  | -- | A multi-event edge whose FIRST emitted event cannot alone recover the
    --   consumed command. Replay ('applyEventStreaming') inverts only the head
    --   output and equality-checks the tail, so this edge produces logs the
    --   transducer cannot replay. Fix by moving the named slots into the first
    --   emitted event.
    HeadUnrecoverable
      { tvwEdge :: EdgeRef s,
        tvwInCtor :: Maybe String,
        tvwTailOnlySlots :: [String],
        tvwDetail :: String
      }
```

(Record fields shared across constructors of one GADT-less data type must agree in
type; `tvwEdge`, `tvwInCtor`, `tvwDetail` already exist at these exact types, so this
compiles. `tvwInCtor` stays `Maybe String` for that sharing even though it is always
`Just` here.)

Extend `ValidationOptions` (line ~1584) with `checkHeadRecoverability :: Bool`,
default `True` in `defaultValidationOptions` (line ~1600); update both haddocks, and
add to the `ValidationOptions` haddock: "construct via record update on
`defaultValidationOptions`; new fields are added as new checks land."

Split the routing in `hiddenInputWarnings` (line ~1646): reasons
`HirEpsilonReadsInput`/`HirUnionMiss` become `HiddenInput` warnings exactly as today
(gated by `failOnEpsilonReadsInput` in `validateTransducer`, unchanged);
`HirHeadUnrecoverable` becomes the new `HeadUnrecoverable` warning, emitted by a new
`headRecoverabilityWarnings` function gated by `checkHeadRecoverability` in
`validateTransducer` (line ~1627). The cleanest factoring: keep `hiddenInputReasons`
as the single per-edge analysis, and have the two warning functions filter it.
Export `headRecoverabilityWarnings` from the module export list next to
`hiddenInputWarnings`.

Rewrite `test/Keiki/CoreHiddenInputsGSMSpec.hs`: delete its local `goodUnion`/
`badUnion`/`badSingle` transducers in favour of importing
`Keiki.Fixtures.SplitCoverage` (add whatever the spec still needs — e.g. a
`badSingle`-shaped single-event-missing-slots transducer — to the fixture module so
everything lives in one shared place). The three tests become: split-coverage edge ⇒
exactly one `HirHeadUnrecoverable` naming `"Begin"` and `"c"` (this replaces the
deleted "union covers all slots ⇒ no warnings" pin — the union fixture is no longer
well-formed, by design); union-miss edge ⇒ `HirUnionMiss` naming `c` (or both `b`,`c`
for the single-event case) exactly as before; and `splitCoverageFixed` ⇒ no reasons
at all. Also assert the structured side: `validateTransducer` on `splitCoverageBad`
yields `[HeadUnrecoverable {..}]` with `tvwTailOnlySlots == ["c"]`.

Acceptance for Milestone 2: the Milestone 1 red assertion is green; `cabal test all`
still fails only where later milestones will act (record in Progress if the audit of
Milestone 5 has to begin early because some other spec pinned union semantics).


### Milestone 3: cross-edge inversion-ambiguity check

Scope: a new structural check flagging pairs of outgoing edges replay might not be
able to tell apart. At the end, `validateTransducer` warns on such pairs and a spec
demonstrates both the warning and the actual replay failure it predicts.

Add to `src/Keiki/Core.hs` (validation section, near `determinismWarnings`):

```haskell
inversionAmbiguityWarnings ::
  (Bounded s, Enum s, Show s) =>
  SymTransducer (HsPred rs ci) rs s ci co ->
  [TransducerValidationWarning s]
```

For every vertex `s`, for every pair `(i, e1)`, `(j, e2)` with `i < j` of edges in
`edgesOut t s` (mirror the pairing structure of `checkTransitionDeterminism`,
`src/Keiki/Core.hs:1743-1761`): skip the pair unless both edges have non-empty
`output`; take each edge's head OPack and compare `wcName` (`WireCtor`'s name field,
`src/Keiki/Core.hs:463`); if equal and NOT `isBot (guard e1 `conj` guard e2)` (on the
pure `HsPred` carrier `isBot` recognises only the literal `PBot` — the exemption is
trivial but sound and free), emit a new warning:

```haskell
  | -- | Two outgoing edges of one vertex whose FIRST emitted events use the
    --   same wire constructor. Replay requires a unique inverting edge, so an
    --   observed event of this constructor may invert through both edges
    --   (each recovering its own command satisfying its own guard) and replay
    --   returns Nothing on a legitimate log. Conservative and structural:
    --   guards that are semantically disjoint over registers or recovered
    --   fields are still flagged; confirm disjointness manually (or with the
    --   solver-backed determinism check) before suppressing via
    --   'checkInversionAmbiguity'.
    InversionAmbiguity
      { tvwSource :: s,
        tvwEdgeA :: Int,
        tvwEdgeB :: Int,
        tvwWireCtor :: String,
        tvwDetail :: String
      }
```

Suggested `tvwDetail` text: `edges #0 and #1 out of Vertex both emit "OutAB" as
their first event; replay may not be able to attribute an observed "OutAB" to a
unique edge`.

Document (in the function's haddock, verbatim ideas): what the check cannot see.
It is an over-approximation in three known ways. (a) Guards that are semantically
disjoint (e.g. `amount .< lit 100` vs `amount .>= lit 100`, or disjoint register
states) make replay deterministic in practice, but the pure carrier cannot prove
disjointness (its `isBot` sees only literal `PBot`), so the pair is still flagged.
(b) Two heads with the same `wcName` but differing literal field values can never
both match one event, but `TLit` carries no `Eq`/`Typeable` evidence so the values
cannot be compared (see this plan's Surprises & Discoveries); a follow-up could add
those constraints to `TLit` and refine the check. (c) Recompute-and-verify on derived
fields (`solveOutput`, `src/Keiki/Core.hs:1212-1227`) can reject one candidate at
replay time in ways no structural check predicts. It has no known false negatives for
head events: two edges whose heads use *different* `wcName`s can never both invert
one event, because `wcMatch` is constructor-honest (an observed event is exactly one
constructor of `co`). Note the check deliberately ignores tail OPacks: tails are
equality-checked, not inverted, so they cannot cause edge-choice ambiguity.

Wire it into `validateTransducer` gated by a new `checkInversionAmbiguity ::
Bool` field of `ValidationOptions` (default `True`). Export
`inversionAmbiguityWarnings`.

Add a spec section (in `test/Keiki/ValidationReplayAlignmentSpec.hs`, or a small new
`test/Keiki/InversionAmbiguitySpec.hs` if it grows — register it if so): construct
inline a two-command transducer where `CmdX x` and `CmdY y` from vertex `False` both
emit head event `Logged Int` (each from its own command field, each edge guarded by
its own `matchInCtor`). Show: (1) `step` on `CmdX 7` produces `[Logged 7]`; (2)
`reconstitute` of `[Logged 7]` is `Nothing` — both edges invert it, uniqueness fails;
(3) `validateTransducer defaultValidationOptions` yields an `InversionAmbiguity` with
`tvwWireCtor == "Logged"`; (4) a repaired variant with distinct head wire
constructors validates clean and replays. Keep this pathological transducer inline in
the spec (it is a counterexample, not a shared fixture — plans 73/74 must not inherit
a transducer that cannot replay for reasons EP-71 does not fix).

Acceptance for Milestone 3: the four assertions above pass under `cabal test all`.


### Milestone 4: guard-implies-input-read check

Scope: a structural check that every input read is protected by a constructor guard,
so `step` rejects instead of crashing. At the end, an edge pairing a `PTop` guard
with a `TInpCtorField` read is flagged.

The rule, precisely. Define the *established set* of a guard as the set of input
constructor names `A` such that a `PInCtor A` atom appears as a conjunct on the
guard's top-level `PAnd` spine (walk `PAnd` recursively; every other node —
`POr`, `PNot`, `PEq`, `PCmp`, `PTop`, `PBot`, and any `PInCtor` nested under them —
is a leaf that establishes nothing; `POr`/`PNot` are treated conservatively as
not-implying because their truth does not force the constructor). Evaluation
semantics justifying this: `evalPred (PAnd p q)` is Haskell `&&`
(`src/Keiki/Core.hs:824`), so if the whole guard evaluated `True`, every spine
conjunct evaluated `True`, and a `True` `PInCtor A` means the input IS an `A`
(`src/Keiki/Core.hs:828-830`); updates and outputs run only after the guard holds.

The check, per edge:

- **Update and output reads.** Collect every constructor name read via
  `TInpCtorField` anywhere in the edge's `update` and in every OPack's `OutFields`
  (write `updateInCtorNames :: Update rs w ci -> [String]` and
  `outFieldsInCtorNames :: OutFields rs ci ifs fs -> [String]`, structural walks
  mirroring `updateReadsInput`/`outFieldsHaveInpCtorField`,
  `src/Keiki/Core.hs:1449-1475`, but returning `icName`s; `TApp1`/`TApp2`/`TArith`
  recurse into operands — a read inside a derived term still evaluates). Every such
  name must be in the guard's established set.
- **Guard-internal reads.** Reads inside the guard itself evaluate *before* the
  guard finishes, so ordering matters: `PAnd (PInCtor A) (inpA #x .== …)` is safe
  (lazy `&&` short-circuits) but `PAnd (inpA #x .== …) (PInCtor A)` crashes on a
  non-`A` command. Walk the `PAnd` spine in evaluation order (left to right),
  threading the set of already-established constructor names; at each non-`PAnd`
  conjunct, first check that every `TInpCtorField` name read anywhere inside that
  conjunct (including under `POr`/`PNot`/derived terms — those all evaluate) is
  already established, then, if the conjunct is `PInCtor A`, add `A` to the set.

Every violation emits a new warning constructor:

```haskell
  | -- | The edge reads a field of input constructor A (in its guard, update,
    --   or output) without a top-level PInCtor A conjunct established first in
    --   its guard. If a different command reaches this edge, evaluation calls
    --   'error' (see 'evalTerm' on 'TInpCtorField') instead of rejecting.
    --   Builder 'onCmd' edges are safe by construction; this fires on
    --   hand-built edges and epsilon blocks.
    UnguardedInputRead
      { tvwEdge :: EdgeRef s,
        tvwInCtor :: Maybe String,
        tvwDetail :: String
      }
```

with `tvwInCtor = Just theCtorName` and detail text naming where the read sits, e.g.
`update reads InCtor "Begin" but the guard does not establish PInCtor "Begin"
before it; a non-"Begin" command reaching this edge crashes instead of being
rejected`. Implement as `guardImpliesInputReadWarnings` (same shape and constraints
as the other warning functions; it needs the `HsPred` carrier since it walks the
guard AST, matching `validateTransducer`'s existing specialisation). Gate behind a
new `checkGuardImpliesInputRead :: Bool` option, default `True`. Export the function.

Known conservative edge cases to note in the haddock: a guard establishing two
different constructors (`PAnd (PInCtor A) (PInCtor B)`) passes this check while
being unsatisfiable — that is dead-edge/determinism territory, not crash territory.
An ε-edge with `PTop` guard and an input-reading update is flagged by BOTH
`HiddenInput` (`HirEpsilonReadsInput` — the data is off the wire) and
`UnguardedInputRead` (the read can crash); the warnings describe different failures
of the same edge and both are correct.

Spec (extend `test/Keiki/ValidationReplayAlignmentSpec.hs` or a sibling): a
hand-built edge with `guard = PTop` and an update `USet` from `TInpCtorField` ⇒
exactly one `UnguardedInputRead`; the same edge with `guard = PAnd (matchInCtor ic)
PTop` ⇒ clean; the wrong-order guard `PAnd (inp-read .== lit …) (matchInCtor ic)` ⇒
flagged; the right-order guard ⇒ clean. Also pin the crash it predicts, with
`shouldThrow` on `evaluate`: `step` of the `PTop`+read edge on a command of a
different constructor throws an `ErrorCall` containing
`"TInpCtorField guard violation"`.

Acceptance for Milestone 4: those five assertions pass; every builder-authored
fixture in the suite (`userReg`, `EmailDelivery`, the composition specs) still
validates clean, because `onCmd` conjoins `matchInCtor` — if one does not, that is a
genuine bug to record in Surprises & Discoveries.


### Milestone 5: detect state-changing epsilon

Add `StateChangingEpsilon` to `TransducerValidationWarning` with an `EdgeRef`, whether
the target differs from the source, whether the update is structurally capable of a
write, and actionable detail. Add `stateChangingEpsilonWarnings`, gated by
`checkStateChangingEpsilon :: Bool`, default `True`.

The structural rule is exact for control state and conservative for registers:

- `output /= []` is outside this check;
- `output == []`, `target == source`, and `update == UKeep` is clean;
- a different target warns;
- `USet` or any `UCombine` containing a write warns, even when a particular runtime
  value could make the write observationally equal.

Add a fixture with vertex-only, update-only, both-changing, and no-op self-loop cases.
The first three warn. The no-op case stays clean. A deterministic companion test
drives a state-changing case, replays its empty log, and demonstrates the divergence
the warning prevents.

The check is independent of `failOnEpsilonReadsInput`: an ε-edge that both reads
input and changes state produces both warnings — add a fixture case proving neither
masks the other. The `checkStateChangingEpsilon` haddock must state the durability
contract in the master plan's terms: never disable this check for a transducer whose
events are persisted; downstream frameworks must treat it as non-optional at their
durable boundary (current keiro force-enables it at `ValidatedEventStream`).

Do not migrate or forbid every in-tree epsilon edge in this milestone. Classify them
in Milestone 6: durable aggregate examples should emit a domain event or explicitly
document why they are non-persisted; state-preserving epsilon remains legal.

Acceptance: default validation reports the exact warning for all unsafe fixture cases,
the explicit option disables only this check, and the no-op self-loop remains clean.


### Milestone 6: suite-wide audit under the stricter validator

Scope: the new checks run by default, so every existing spec and fixture is now held
to the replay contract. Run `cabal test all` and classify every new failure:

- A spec that pinned the union semantics (only `test/Keiki/CoreHiddenInputsGSMSpec.hs`
  is known — already rewritten in Milestone 2).
- A fixture that is genuinely head-unrecoverable, inversion-ambiguous,
  unguarded, or contains state-changing epsilon: restructure the fixture (move fields
  into the head event; rename a colliding head wire constructor; add the missing
  `matchInCtor` conjunct; emit a domain event for durable state change) and note
  it in Surprises & Discoveries — each such fixture is a latent replay bug this plan
  just caught, which is evidence for the master plan.
- A spec asserting `validateTransducer … == []` on a transducer that now (correctly)
  warns: fix the transducer, never the assertion.

Multi-event edges known to exist in the suite besides the fixtures already handled:
`test/Keiki/CoreInFlightSpec.hs` (line ~54: single-slot command, head emits the slot
— expected to pass), `test/Keiki/CompositionMultiEventSpec.hs` (line ~83: same shape
— expected to pass), and `test/Keiki/Fixtures/UserRegistration.hs`'s
`StartRegistration` edge (head `RegistrationStarted` carries `email`, `confirmCode`,
`at` — all three command slots — expected to pass). Verify each; do not assume.

Also confirm the two GHCi-facing examples the review used still behave: run the
Surprises transcript's session and observe `checkHiddenInputs splitCoverageBad` now
returns a warning whose text contains `head event does not recover`.

Acceptance for Milestone 6: `cabal test all` fully green in `nix develop`;
`nix fmt -- --no-cache` produces no diff (run it before judging the tree clean —
per project memory, a missing/ignored fourmolu run causes silent style drift).


### Milestone 7: docs, changelog, and downstream coordination

Scope: make the contract discoverable and the breaking change navigable.

- Haddock on `validateTransducer`: state the alignment law positively — "a
  transducer for which this returns `[]` under `defaultValidationOptions` can replay
  every log it produces via `reconstitute`; the head-recoverability, inversion-
  ambiguity, unguarded-input-read, and state-changing-epsilon checks exist to make that sentence true" — and
  cross-reference `applyEventStreaming`.
- Haddock on `applyEventStreaming` and `solveOutput`: name the head-only inversion
  contract explicitly and point at `HeadUnrecoverable`.
- `CHANGELOG.md`: under `0.1.0.0`, describe the four new checks, the new warning
  constructors, the four new `ValidationOptions` fields, and the
  behavioural change to `checkHiddenInputs` (union no longer sufficient), with a
  one-line migration pointer for exhaustive matchers.
- Verify the keiro migration section below against keiro's current source (do not
  edit keiro in this plan — the master plan's integration point 1 says EP-71
  *documents* the migration; keiro applies it when it bumps keiki).
- Update the master plan registry (`docs/masterplans/16-...md`): EP-71 status, and
  tick its two EP-71 progress boxes.

Acceptance for Milestone 7: `cabal haddock keiki` builds without new warnings; the
changelog entry exists; this plan's keiro section matches keiro's real code
(file/line re-checked).


## keiro Migration (documented here, applied in keiro when it bumps keiki)


keiro consumes the warning type exhaustively in exactly one place:
`/Users/shinzui/Keikaku/bokuno/keiro/keiro-core/src/Keiro/EventStream/Validate.hs`,
function `renderWarning` (lines 147–155 as of 2026-07-12). After this plan, that
`case` has four missing arms. The migration is: add the following arms (matching the
existing rendering style — a kebab-case tag, the source vertex, then `tvwDetail`),
and update the function's haddock sentence "All four constructors carry @tvwDetail@"
to "All eight constructors carry @tvwDetail@":

```haskell
    HeadUnrecoverable{tvwEdge = e, tvwDetail = d} ->
        "head-unrecoverable @" <> showT (edgeSource e) <> ": " <> Text.pack d
    InversionAmbiguity{tvwSource = s, tvwDetail = d} ->
        "inversion-ambiguity @" <> showT s <> ": " <> Text.pack d
    UnguardedInputRead{tvwEdge = e, tvwDetail = d} ->
        "unguarded-input-read @" <> showT (edgeSource e) <> ": " <> Text.pack d
    StateChangingEpsilon{tvwEdge = e, tvwDetail = d} ->
        "state-changing-epsilon @" <> showT (edgeSource e) <> ": " <> Text.pack d
```

No other keiro change is required: keiro never constructs `ValidationOptions`
literally (it imports `defaultValidationOptions` and threads caller-supplied values),
so the four new record fields are source-compatible there; `mkEventStream` /
`mkEventStreamOrThrow` automatically become stricter, which is the point. Operational
impact to communicate to keiro: any keiro stream whose transducer trips a new check
will now fail `mkEventStream` at startup instead of failing hydration in production.
Current keiro's aggregate and process-manager streams will receive these checks at
their existing `ValidatedEventStream` boundary. Its follow-up MasterPlan 14 EP-95
owns the exhaustive warning-renderer migration and runtime adoption after keiki
MP-16 lands. Its EP-99 must consume and pin this default-on warning at the durable
stream boundary rather than implement a second silent-edge AST traversal.
Enforcement there is non-negotiable (master plan Decision Log, 2026-07-12): keiro
force-enables `checkStateChangingEpsilon` and `checkHeadRecoverability` regardless
of caller-supplied `ValidationOptions` — caller options may only strengthen
validation at the durable boundary — and its only bypass is a separately named
unchecked constructor, not an options field.


## Coordination with plan 76 (symbolic posture)


This plan owns the final `TransducerValidationWarning` constructor set for the
master-plan initiative (integration point 1), landing the one coordinated
keiro-breaking change. `docs/plans/76-symbolic-soundness-solver-unknown-handling-encoding-gap-caveats-and-a-stronger-pure-overlap-check.md`
must REUSE this vocabulary rather than extend it: its stronger pure overlap check
(same-constructor `PAnd` pairs) emits the existing `NondeterministicPair`; its
solver-`Unknown` conservatism needs no warning constructor at all if `Unknown` is
simply treated as not-bot (the analyses just get stricter); if EP-76 wants an
"analysis could not decide" advisory, it should express it through the existing
advisory `OpaqueGuard`'s pattern (an opt-in `ValidationOptions` flag plus detail
text) before ever adding a constructor. EP-76 additionally extends
`ValidationOptions`; it should follow the record-update-on-defaults convention this
plan documents on the type. If EP-76 nevertheless proves to need a new constructor,
it owns a fresh keiro migration note for it — do not retrofit it into this plan.


## Concrete Steps


All commands run from the repository root `/Users/shinzui/Keikaku/bokuno/keiki`,
inside the dev shell (GHC 9.12):

```bash
cd /Users/shinzui/Keikaku/bokuno/keiki
nix develop
```

Then, per milestone:

```bash
cabal build all
cabal test all
```

To run only the new spec while iterating (hspec filters by description substring):

```bash
cabal test keiki-test --test-options='--match "ValidationReplayAlignment"'
```

Expected transcript at the end of Milestone 1 (abbreviated):

```text
Keiki.ValidationReplayAlignmentSpec
  validate-clean transducers replay their own logs
    splitCoverageFixed replays its own log [✔]
    splitCoverageBad: validator flags the head-unrecoverable edge [✘]

  ...
  expected: non-empty warnings
   but got: []
```

Expected at the end of Milestone 6:

```text
All N examples passed.
```

Formatting before every commit (canonical fourmolu config; do not skip the flag):

```bash
nix fmt -- --no-cache
```

Commit per milestone with Conventional Commits, e.g.:

```text
feat(core): demand head-recoverability in the hidden-input validator

validateTransducer now agrees with applyEventStreaming that replay
inverts the head output only. New HeadUnrecoverable warning; the
union-covered GHCi counterexample from the 2026-07 review is rejected.

BREAKING CHANGE: TransducerValidationWarning gains constructors;
exhaustive matchers (keiro renderWarning) need new arms.
```


## Validation and Acceptance


The plan is complete when a reviewer can observe all of the following, in order,
with no knowledge beyond this document:

1. In GHCi (`cabal repl keiki-test` inside `nix develop`), the review counterexample
   is rejected at build time: `validateTransducer defaultValidationOptions
   splitCoverageBad` (import `Keiki.Core` and `Keiki.Fixtures.SplitCoverage`)
   returns a single-element list whose constructor is `HeadUnrecoverable` and whose
   `tvwTailOnlySlots` is `["c"]` — where before this plan the same expression
   returned `[]` while `reconstitute splitCoverageBad [OutAB 1 2, OutBC 2 3]`
   returned `Nothing`. The silent validate-clean-then-fail-replay path no longer
   exists for this shape.
2. `cabal test all` is green and includes `Keiki.ValidationReplayAlignmentSpec`
   proving, for `splitCoverageFixed`, `Keiki.Fixtures.RegisterEmission`,
   `Keiki.Fixtures.UserRegistration.userReg`, and `Keiki.Fixtures.EmailDelivery`:
   validator clean AND `reconstitute` of a `step`-produced log returns `Just` the
   forward-fold state. (Targeted examples only; the generative property harness is
   plan 73.)
3. The inversion-ambiguity spec shows the trio: same-head-`wcName` transducer replays
   `Nothing` on its own log, is flagged `InversionAmbiguity`, and its
   renamed-constructor repair is clean and replays.
4. The unguarded-read spec shows: `PTop`-guard-with-read edge is flagged
   `UnguardedInputRead` and demonstrably crashes `step` (caught `ErrorCall`), while
   the `matchInCtor`-conjoined repair is clean and rejects gracefully.
5. The epsilon spec shows vertex-changing and register-writing empty-output edges are
   flagged `StateChangingEpsilon`, a no-op `UKeep` self-loop is clean, and replay of
   the deliberately invalid run demonstrates the missing state change.
6. `grep -n "HeadUnrecoverable\|InversionAmbiguity\|UnguardedInputRead\|StateChangingEpsilon"
   CHANGELOG.md` hits; the keiro migration section above names the real keiro
   file and lines; `nix fmt -- --no-cache` is a no-op.


## Idempotence and Recovery


Every step is additive-then-adjust and safe to re-run: re-running `cabal build`/
`cabal test`/`nix fmt` is idempotent; re-applying an edit that already exists is a
no-op. The risky ordering is Milestone 2's rewrite of
`test/Keiki/CoreHiddenInputsGSMSpec.hs` — do it in the same commit as the
`hiddenInputReasons` rework so no commit has a suite that contradicts itself. If a
milestone must be abandoned midway, `git checkout -- src test keiki.cabal` restores
the tree; the fixtures of Milestone 1 are independent of the validator changes and
can always be kept. No migrations, no persisted data, no destructive operations are
involved; the library is pure and the test suite is hermetic (no solver process is
needed — all new checks are structural, running on the `HsPred` carrier exactly like
the existing `validateTransducer` path).


## Interfaces and Dependencies


No new package dependencies; everything is `src/Keiki/Core.hs` plus tests (hspec,
already a test dependency). GHC 9.12 via `nix develop`. The surface that must exist
at the end, all exported from `Keiki.Core` (add to the export list around
`src/Keiki/Core.hs:145-168`):

```haskell
-- extended (new constructors marked):
data HiddenInputReason
  = HirEpsilonReadsInput
  | HirUnionMiss String [String]
  | HirHeadUnrecoverable String [String]          -- NEW (ctor, tail-only slots)

data TransducerValidationWarning s
  = HiddenInput { tvwEdge :: EdgeRef s, tvwInCtor :: Maybe String,
                  tvwMissingSlots :: [String], tvwDetail :: String }
  | NondeterministicPair { tvwSource :: s, tvwEdgeA :: Int, tvwEdgeB :: Int,
                           tvwInCtor :: Maybe String, tvwDetail :: String }
  | PossiblyDeadEdge { tvwEdge :: EdgeRef s, tvwDetail :: String }
  | OpaqueGuard { tvwEdge :: EdgeRef s, tvwDetail :: String }
  | HeadUnrecoverable { tvwEdge :: EdgeRef s, tvwInCtor :: Maybe String,   -- NEW
                        tvwTailOnlySlots :: [String], tvwDetail :: String }
  | InversionAmbiguity { tvwSource :: s, tvwEdgeA :: Int, tvwEdgeB :: Int, -- NEW
                         tvwWireCtor :: String, tvwDetail :: String }
  | UnguardedInputRead { tvwEdge :: EdgeRef s, tvwInCtor :: Maybe String,  -- NEW
                         tvwDetail :: String }
  | StateChangingEpsilon { tvwEdge :: EdgeRef s,                           -- NEW
                           tvwChangesVertex :: Bool,
                           tvwWritesRegisters :: Bool,
                           tvwDetail :: String }

data ValidationOptions = ValidationOptions
  { failOnEpsilonReadsInput :: Bool,
    checkDeterminism :: Bool,
    checkReachability :: Bool,
    warnOpaqueGuards :: Bool,
    checkHeadRecoverability :: Bool,      -- NEW, default True
    checkInversionAmbiguity :: Bool,      -- NEW, default True
    checkGuardImpliesInputRead :: Bool,   -- NEW, default True
    checkStateChangingEpsilon :: Bool     -- NEW, default True
  }

-- new warning producers (same constraint shape as hiddenInputWarnings /
-- determinismWarnings; HsPred carrier where the guard AST is walked):
headRecoverabilityWarnings ::
  (Bounded s, Enum s) =>
  SymTransducer phi rs s ci co -> [TransducerValidationWarning s]
inversionAmbiguityWarnings ::
  (Bounded s, Enum s, Show s) =>
  SymTransducer (HsPred rs ci) rs s ci co -> [TransducerValidationWarning s]
guardImpliesInputReadWarnings ::
  (Bounded s, Enum s, Show s) =>
  SymTransducer (HsPred rs ci) rs s ci co -> [TransducerValidationWarning s]
stateChangingEpsilonWarnings ::
  (Bounded s, Enum s, Eq s, Show s) =>
  SymTransducer phi rs s ci co -> [TransducerValidationWarning s]
```

Test modules that must exist and be registered in `keiki.cabal`
(`test-suite keiki-test`, `other-modules`) and imported by `test/Spec.hs`:
`Keiki.Fixtures.SplitCoverage` (`test/Keiki/Fixtures/SplitCoverage.hs`),
`Keiki.Fixtures.RegisterEmission` (`test/Keiki/Fixtures/RegisterEmission.hs`), and
`Keiki.ValidationReplayAlignmentSpec`
(`test/Keiki/ValidationReplayAlignmentSpec.hs`). The rewritten
`test/Keiki/CoreHiddenInputsGSMSpec.hs` keeps its module name. Downstream (not
edited here, verified against): current keiro's
`keiro-core/src/Keiro/EventStream/Validate.hs` `renderWarning` and follow-up
MasterPlan 14 EP-95.

---

Revision note (2026-07-12): added default-on `StateChangingEpsilon` detection while
preserving explicit opt-out for pure non-persisted transducers. Current keiro enforces
the warning for durable aggregate and process-manager streams through its follow-up
MasterPlan 14; EP-73 now tests complete validation-clean runs instead of truncating at
epsilon.

Revision note (2026-07-12): replaced the skeleton with the full plan. Authored from a
fresh read of `src/Keiki/Core.hs` (evaluators, replay, and validation sections),
`src/Keiki/Symbolic.hs` (determinism checks), the GSM/InFlight/composition specs, the
current keiro `Validate.hs` integration, and in-tree fixtures; the
head-recoverability defect was re-reproduced empirically in GHCi (transcript in
Surprises & Discoveries) before the plan was written. Outdated external example
claims were removed during validation on 2026-07-12.
