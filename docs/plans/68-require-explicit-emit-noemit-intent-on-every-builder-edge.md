---
id: 68
slug: require-explicit-emit-noemit-intent-on-every-builder-edge
title: "Require explicit emit/noEmit intent on every Builder edge"
kind: exec-plan
created_at: 2026-07-03T22:59:17Z
intention: "intention_01kxc5whw1en3ra4nh728m53ka"
master_plan: docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md
---

# Require explicit emit/noEmit intent on every Builder edge

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

`Keiki.Builder` is a small embedded language (a "DSL", domain-specific language)
for writing the state machines that this project calls **transducers**. A
developer describes each transition ("edge") as a short block: which register
slots it writes, which event it emits, and which target state it moves to. The
block is written with `B.do { … }` and ends with `B.goto SomeState`.

Today the language lets a developer write an edge that moves to a new state but
says *nothing* about output — they call `B.goto` without ever calling `B.emit`
(produce an event) or `B.noEmit` (declare "this edge deliberately produces no
event"). When that happens the builder silently treats the edge as an **ε-edge**
(pronounced "epsilon edge"): a transition that changes state but emits no event
on the wire. That silence is indistinguishable from a bug — the developer may
simply have *forgotten* to emit. In an event-sourcing system, where the usual
reason to take an edge is to record an event, a forgotten `emit` is a real and
easy mistake, and nothing catches it.

This plan has a hard dependency on EP-70. References below to a lazy finalize-time
`error` describe the original design and are superseded by the 2026-07-12 Decision
Log: the same intent flag and message are emitted as an eager structured
`BuilderDefect` through `buildTransducerEither`, with `buildTransducer` forcing and
rendering that result.

After this change, **every edge body must state its output intent explicitly.**
An edge that calls `B.goto` but neither `B.emit`/`B.emitWith` nor `B.noEmit`
becomes a hard error during eager builder validation, with a message naming the source
vertex and edge index and telling the developer exactly what to add. Developers
who genuinely want a silent transition keep writing `B.noEmit` — which, for the
first time, becomes a *load-bearing* keyword instead of pure documentation.
Deliberate ε-edges remain fully expressible; only *silence-by-omission* becomes
impossible.

You can see the new behavior working by writing an `onCmd` block that ends with
`B.goto` and no output call, evaluating the resulting transducer to weak head normal
form, and
observing a runtime error like:

```text
Keiki.Builder: edge #0 from A: no emit or noEmit. Each onCmd/onEpsilon body
must call 'emit' (or 'emitWith') to produce an event, or 'noEmit' to declare
the edge deliberately silent (ε-edge).
```

This mirrors the existing "goto missing" and "goto called more than once"
diagnostics: the same message and precedence, now produced through EP-70's eager
structured defect pass. `buildTransducerEither` returns the defect; the legacy
`buildTransducer` wrapper renders and raises it when the returned transducer is forced
to WHNF as specified by EP-70.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] **M1 — Enforce explicit output intent in the builder.** (completed 2026-07-12 16:01 -0700)
  - [x] Add `peOutputDecided :: Bool` field to `PartialEdge` in `src/Keiki/Builder.hs`.
  - [x] Initialize `peOutputDecided = False` in the `onCmd` initial record.
  - [x] Initialize `peOutputDecided = False` in the `onEpsilon` initial record.
  - [x] Set `peOutputDecided = True` in `emit` (the `PinCtor` branch).
  - [x] Set `peOutputDecided = True` in `emitWith`.
  - [x] Change `noEmit` from a no-op to setting `peOutputDecided = True`.
  - [x] Add `DefectMissingOutputIntent` to `BuilderDefect` and return it from the
        structured defect produced from the `[t]` branch of `finalizeEdge`.
  - [x] Update the module-header "Misuse diagnostics" haddock to list the new diagnostic.
  - [x] Update the `noEmit` haddock (it is no longer a documentation no-op).
  - [x] Update the `finalizeEdge` haddock to mention the output-intent requirement.
  - [x] `cabal build all` succeeds.
- [x] **M2 — Migrate the two in-repo silent edges and prove the new rule with tests.** (completed 2026-07-12 16:03 -0700)
  - [x] Add `B.noEmit` to `coffeeBuilt`'s Brewing→Idle edge in `test/Keiki/BuilderSpike.hs`.
  - [x] Add `B.noEmit` to case 10 (`onEpsilon`) in `test/Keiki/BuilderSpec.hs`.
  - [x] Add a positive regression test: `onCmd` bare `goto` (no emit/noEmit) is rejected when the transducer is evaluated to WHNF.
  - [x] Add a positive regression test: `onEpsilon` bare `goto` is rejected when the transducer is evaluated to WHNF.
  - [x] Confirm existing double-goto and missing-goto tests still pass unchanged (goto-arity check precedes the output-intent check).
  - [x] `cabal test all` is green (all four suites: `keiki-test`, `jitsurei-test`, and both codec suites).
  - [x] Re-run the silent-edge audit; confirm zero unintended silent blocks remain across `src`, `test`, and `jitsurei` (the five reported blocks are deliberate negative tests).
- [ ] **M3 — Documentation and changelog.**
  - [ ] Update `docs/research/edge-builder-dsl-shape.md` (the `noEmit` paragraph + a design-decision note).
  - [ ] Add a `### Changed` entry under `## [Unreleased]` in `CHANGELOG.md`.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- **Discovery (research, 2026-07-03): the change is effectively non-breaking for
  real consumers.** Every worked example in `jitsurei/src/Jitsurei/*.hs` and every
  fixture in `test/Keiki/Fixtures/*.hs` already calls `emit`/`emitWith`/`noEmit`
  at least once per `goto`. A per-block scan found the only *silent* edges (a
  `goto` with no output call) live in two test modules. Evidence — emit/noEmit
  count is `>=` goto count in every consumer file:

  ```text
  jitsurei/src/Jitsurei/EmailDelivery.hs    goto=1   emit/noEmit=1
  jitsurei/src/Jitsurei/Loan.hs             goto=2   emit/noEmit=2
  jitsurei/src/Jitsurei/CoreBankingSync.hs  goto=2   emit/noEmit=2
  jitsurei/src/Jitsurei/OrderCart.hs        goto=12  emit/noEmit=12
  jitsurei/src/Jitsurei/LoanApplication.hs  goto=11  emit/noEmit=11
  test/Keiki/Fixtures/EmailDelivery.hs      goto=1   emit/noEmit=1
  test/Keiki/Fixtures/UserRegistration.hs   goto=5   emit/noEmit=6
  jitsurei/src/Jitsurei/UserRegistration.hs goto=5   emit/noEmit=6
  ```

- **Discovery (research, 2026-07-03): the goto-arity check must run *before* the
  output-intent check** so that the existing double-goto test
  (`coffeeDoubleGoto`, two `goto`s and no `emit`) keeps throwing the *double-goto*
  error rather than the new one. `finalizeEdge` already cases on `peTargets`
  first (`[t]` / `[]` / `(_:_:_)`); nesting the new check inside the `[t]` branch
  preserves that precedence for free. See Decision Log.

- **Discovery (implementation, 2026-07-12): the fail-before test run reports six
  failing examples but only two omitted-intent edges.** `BuilderSpec` case 10 owns
  one edge; the top-level `coffeeBuilt` edge is forced by five independent spike
  examples. Every failure carried the exact new diagnostic, while the existing
  missing- and double-`goto` tests remained green. Evidence: `cabal test
  keiki-test` completed 386 examples with 6 expected failures before M2 migration.

- **Discovery (implementation, 2026-07-12): the plan's raw silent-edge audit
  cannot reach an empty or double-`goto`-only result after adding the required
  regressions.** It reports five deliberate malformed bodies: three double-`goto`
  fixtures (including EP-70's structured-error aggregation case) and the two new
  bare-`goto` EP-68 tests. Manual inspection confirmed that no production, example,
  or positive-test edge omits output intent.


## Decision Log

Record every decision made while working on the plan.

- Decision: enforce output intent during EP-70's eager structured finalization, not at
  the type level and not through a new lazy `error` thunk.
  Rationale: a type-level guarantee would require another phantom index through the
  builder monad; EP-70 already supplies `BuilderDefect`, `finalizeEdge :: ... ->
  Either BuilderDefect Edge`, and `buildTransducerEither`. Reusing that path makes the
  documented construction-time timing true and preserves uniform diagnostics.
  Date: 2026-07-12 (supersedes the 2026-07-03 runtime-error decision)

- Decision (EP-70 handoff landed): add `DefectMissingOutputIntent` to the existing
  `BuilderDefect` sum, return it from `finalizeEdge`'s exactly-one-`goto` branch when
  `peOutputDecided` is false, and render this plan's exact message in
  `renderBuilderErrors`. Tests force `evaluate tr`, not
  `evaluate (head (edgesOut tr A))`.
  Rationale: EP-70 now evaluates every declared edge eagerly, aggregates located
  defects, and preserves goto-arity precedence through `finalizeEdge`'s case order.
  Reusing that path makes missing output intent visible even when the affected vertex
  is never queried and gives `buildTransducerEither` the structured defect.
  Date: 2026-07-12

- Decision: Track intent with a single `Bool` field `peOutputDecided` on
  `PartialEdge`, set by `emit`, `emitWith`, and `noEmit`.
  Rationale: An explicit `noEmit` and a forgotten output both leave `peOutput`
  empty, so the empty output list alone cannot distinguish them — a dedicated
  flag is required. A `Bool` is the minimal representation; there is no need to
  count or order output decisions.
  Date: 2026-07-03

- Decision: The new check lives **inside the `[t]` (exactly-one-goto) branch** of
  `finalizeEdge`, so goto-arity errors take precedence.
  Rationale: An edge that both omits output *and* misuses `goto` is more usefully
  reported as a `goto` problem first (it has no valid target at all). This also
  preserves the existing `coffeeDoubleGoto` / "case 8" tests without edits.
  Date: 2026-07-03

- Decision: This plan is adopted into
  `docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md`
  (Phase 1) with a hard dependency on
  `docs/plans/70-builder-correctness-hardening-eager-finalize-validation-closing-the-emit-unsafecoerce-schema-hole-and-declaration-order-edge-merging.md`.
  The original 2026-07-03 decision (now superseded above) rested on an assumption the
  architecture review disproved: `buildTransducer` does
  NOT evaluate the builder eagerly — `finalizeEdge`'s errors are lazy thunks
  forced only when `edgesOut` is first demanded for the affected vertex, so the
  diagnostic "fires the moment `buildTransducer` is evaluated" only after plan 70
  makes finalization eager. EP-70 must land first; register the missing-intent
  diagnostic as a `BuilderDefect` in its eager structured validation path, preserving
  this plan's message text and goto-arity precedence. Do not add a temporary lazy
  `error` path. The `peOutputDecided` tracking remains unchanged.
  Date: 2026-07-12

- Decision: Migrate the two in-repo silent edges by adding `B.noEmit` (rather than
  by inventing events to emit).
  Rationale: Both are genuinely silent by design — `coffeeBuilt`'s Brewing→Idle
  edge mirrors an AST reference whose `output = []` (`test/Keiki/BuilderSpike.hs`
  line 140), and "case 10" exists to assert `onEpsilon` produces a `PTop`
  guard-only edge, not to emit. `B.noEmit` records that intent without changing
  observable output.
  Date: 2026-07-03

- Decision: Ship this as a `### Changed` (behavioral) entry in the `[Unreleased]`
  section of `CHANGELOG.md`.
  Rationale: The package is at `0.1.0.0`. This tightens a previously-accepted
  program shape (bare `goto`) into an error, so it is a behavioral change worth
  recording, even though no in-tree consumer is affected.
  Date: 2026-07-03

- Decision: interpret the post-M2 audit acceptance as zero *unintended* silent
  blocks, with deliberate malformed-edge tests retained.
  Rationale: the plan itself requires two bare-`goto` regression tests, and EP-70
  added a third double-`goto` fixture after the original audit expectation was
  written. Removing or disguising those cases would weaken validation coverage.
  Date: 2026-07-12


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

This section assumes no prior knowledge of the repository. Read it fully before editing.

**What this project is.** `keiki` is a Haskell library for building *transducers*:
pure state machines that read commands, update an internal register file, emit
events, and move between states. The relevant packages here are the main library
(`keiki.cabal`, source under `src/`) and a companion package of worked examples,
`jitsurei` (`jitsurei/jitsurei.cabal`, source under `jitsurei/src/`). Both build
with Cabal; there is no custom test runner (the `justfile` only has website
recipes), so tests run with `cabal test`.

**The one file that changes behavior:** `src/Keiki/Builder.hs`. It defines the
edge-authoring DSL. The pieces you need to understand:

- **`PartialEdge`** (around line 249): a mutable-feeling accumulator threaded
  through one edge body. It has fields `peGuard`, `peUpdate`, `peOutput`
  (the list of events this edge emits — empty list means "no event"),
  `peTargets` (the list of `goto` targets seen — must end up length 1), and
  `pePinned` (schema-indexed bookkeeping for `emit`). Each builder step updates one or more
  fields.

- **`emit` / `emitWith`** (around lines 459 and 502): append one event to
  `peOutput`. `emit` recovers the input constructor from the enclosing `onCmd`;
  `emitWith` takes it explicitly (needed inside `onEpsilon`, which pins none).

- **`noEmit`** (around line 512): **currently a no-op** — `noEmit = EdgeBuilder $
  \pe -> ((), pe)`. Its haddock even says "an edge with no `emit` or `noEmit`
  call is also an ε-edge by default; `noEmit` exists only so the user can be
  explicit about intent." This plan makes that statement false: `noEmit` becomes
  the *required* way to declare a silent edge.

- **`goto`** (around line 434): appends a target to `peTargets`. Required exactly
  once per body.

- **`onCmd` / `onEpsilon`** (around lines 663 and 689): start an edge body by
  constructing an initial `PartialEdge`, run the user's body over it, then call
  `finalizeEdge`. `onCmd` matches on an input command constructor and pins its
  `InCtor` (so `emit` can recover it); `onEpsilon` matches nothing (guard starts
  at `PTop`) and pins no `InCtor`.

- **`finalizeEdge`** (around line 714): validates the accumulated `PartialEdge`
  and returns `Either BuilderDefect Edge`. It cases on `peTargets`: exactly one
  target proceeds to output-constructor validation and builds the `Edge`; zero
  targets returns `DefectMissingGoto`; two-or-more returns `DefectMultipleGoto`.
  **The new check goes inside the exactly-one-target branch.**

**Key term — "ε-edge" (epsilon edge):** an edge whose `output` list is empty, so
it changes state (and may write registers) but emits no event. In `Keiki.Core`,
`output = []` *is* the ε-edge; `[o]` is a single-event ("letter") edge; `[o1,o2,…]`
is a multi-event edge. ε-edges are a legitimate, needed concept — this plan does
**not** forbid them. It only forbids reaching one *by accident* (omitting both
`emit` and `noEmit`).

**Key term — "eager builder validation":** EP-70 runs the complete builder,
merges duplicate `from` blocks, finalizes every edge, and forces the resulting
defect list before returning a transducer. `buildTransducerEither` returns located
structured defects; `buildTransducer` renders and raises them when its returned
transducer is evaluated to weak head normal form. No `edgesOut` lookup is needed.

**The migration surface** (established by research, see Surprises & Discoveries):
every real consumer already declares output intent. Only two test edges are
silent today and must be migrated:

1. `test/Keiki/BuilderSpike.hs`, the `coffeeBuilt` transducer, Brewing→Idle edge
   (around lines 166–168):

   ```haskell
   B.from Brewing do
     B.onCmd inCtorContinue $ \_d -> B.do
       B.goto Idle
   ```

   This mirrors an AST reference (`coffeeAST`, same file) whose Brewing edge has
   `output = []` (line 140). Migration: insert `B.noEmit` before `B.goto Idle`.
   Because `noEmit` leaves `peOutput` empty, the transducer's observable output is
   unchanged and the existing "delta and omega agree on Brewing + Continue" test
   (lines 223–229) keeps passing.

2. `test/Keiki/BuilderSpec.hs`, "case 10" (around lines 261–270):

   ```haskell
   B.from A do
     B.onEpsilon B.do
       B.goto B
   ```

   This test asserts `onEpsilon` yields a `PTop` guard-only edge. Migration:
   insert `B.noEmit` before `B.goto B`.

The double-goto cases (`coffeeDoubleGoto` in `BuilderSpike.hs`, "case 8" in
`BuilderSpec.hs`) are silent too, but they hit the two-or-more-`goto` branch of
`finalizeEdge`, which fires *before* the new output-intent check. They require no
edits and must keep passing unchanged — that is a correctness check on ordering.


## Plan of Work

The work is one small library change plus its migration and documentation, split
into three independently verifiable milestones. Total code delta in the library is
roughly a dozen lines; the rest is tests and prose.

### Milestone M1 — Enforce explicit output intent in the builder

Scope: make `src/Keiki/Builder.hs` reject an edge that reaches `goto` without
declaring output intent. At the end of this milestone the library compiles and the
new rule is implemented, but the two in-repo silent test edges will fail until M2 —
that is expected and called out in acceptance.

Edits, all in `src/Keiki/Builder.hs`:

1. **Add the intent field to `PartialEdge`.** In the record (around lines
   249–266), add a `Bool` field with a haddock comment:

   ```haskell
   -- | Whether the body made an explicit output decision. Set to
   -- 'True' by any 'emit', 'emitWith', or 'noEmit' call and checked by
   -- 'finalizeEdge': an edge that reaches 'goto' with this still 'False'
   -- (neither emitted an event nor declared 'noEmit') is rejected,
   -- rather than silently becoming an ε-edge.
   peOutputDecided :: Bool
   ```

   Add it as the last field. Remember to add a comma after the preceding
   `pePinned` field's type.

2. **Initialize it to `False` in both edge starters.** In `onCmd` (initial record
   around lines 670–677) and in `onEpsilon` (initial record around lines 695–702),
   add `peOutputDecided = False` to each `PartialEdge { … }` literal.

3. **Flip it to `True` where output intent is declared.**
   - In `emit` (around lines 465–481), the `PinCtor ic` branch returns
     `pe { peOutput = … }`; add `, peOutputDecided = True` to that record update.
   - In `emitWith` (around lines 509–510), change the record update from
     `pe {peOutput = …}` to also set `, peOutputDecided = True`.
   - In `noEmit` (around lines 518–519), change the body from `((), pe)` to
     `((), pe {peOutputDecided = True})`.

4. **Add the structured defect and check.** Add
   `DefectMissingOutputIntent` to `BuilderDefect`. In `finalizeEdge`'s `[t]`
   branch, after the existing `outputCtorMismatch` check, return that defect when
   `peOutputDecided pe` is false; otherwise build the edge:

   ```haskell
   [t] -> case outputCtorMismatch (pePinned pe) (peOutput pe) of
     Just defect -> Left defect
     Nothing
       | not (peOutputDecided pe) -> Left DefectMissingOutputIntent
       | otherwise -> Right Edge { ... }
   ```

   Add the exact message from Purpose / Big Picture to the
   `DefectMissingOutputIntent` case of `renderBuilderError`. Leave the `[]` (goto
   missing) and `(_ : _ : _)` (goto too many) branches exactly as they are, and
   keep the output-intent check inside `[t]` so goto arity retains precedence.

5. **Update the haddocks so the docs match the behavior.**
   - Module-header "== Misuse diagnostics" section (around lines 111–121): add a
     fourth bullet, e.g. "Edge with neither `emit`/`emitWith` nor `noEmit`: caught
     by eager validation with a located structured defect directing the user to add
     `emit` or `noEmit`."
   - `noEmit` haddock (around lines 512–517): rewrite. It is no longer idempotent
     documentation; it now *satisfies a requirement*. New text, in substance:
     "Declare the edge deliberately silent (ε-edge, `output = []`). Required in any
     edge body that does not `emit`: an edge reaching `goto` with neither `emit`
     nor `noEmit` is an eager builder error. Mixing `noEmit` and `emit` in one body
     is allowed; the `emit`s still populate the output list."
   - `finalizeEdge` haddock (around lines 708–713): add a sentence noting that a
     valid edge must also have declared output intent (`emit`/`emitWith`/`noEmit`),
     else it returns `DefectMissingOutputIntent`.

Acceptance for M1: `cabal build all` succeeds (see Concrete Steps). The library
change is complete. `cabal test all` is expected to show the two silent test edges
now failing with the new error; that is the proof the check fires, and M2 fixes
them.

### Milestone M2 — Migrate silent edges and lock the rule with tests

Scope: update the two in-repo silent edges to declare intent, add positive
regression tests that prove the new error fires for both `onCmd` and `onEpsilon`,
confirm the goto-arity tests are unaffected, and re-run the repo-wide silent-edge
audit. At the end, `cabal test all` is fully green and no silent edge remains.

Edits:

1. **`test/Keiki/BuilderSpike.hs`** — in `coffeeBuilt`, the Brewing block (around
   lines 166–168), insert `B.noEmit` before `B.goto Idle`:

   ```haskell
   B.from Brewing do
     B.onCmd inCtorContinue $ \_d -> B.do
       B.noEmit
       B.goto Idle
   ```

2. **`test/Keiki/BuilderSpec.hs`** — in "case 10" (around lines 261–270), insert
   `B.noEmit` before `B.goto B`:

   ```haskell
   B.from A do
     B.onEpsilon B.do
       B.noEmit
       B.goto B
   ```

3. **Add two positive regression tests in `test/Keiki/BuilderSpec.hs`.** Place
   them near the existing goto diagnostics ("case 7", "case 8"). They build a
   transducer with a bare `goto` and assert the new error fires when the transducer
   is evaluated. Build with `B.buildTransducer`, force with `evaluate tr`, and match
   with `shouldThrow` / `errorCall`. Sketch:

   ```haskell
   it "bare goto in onCmd (no emit/noEmit) fires the new error" $ do
     let tr = B.buildTransducer A emptyR (const False) do
           B.from A do
             B.onCmd inCtorTick $ \_d -> B.do
               B.goto B
     evaluate tr
       `shouldThrow` errorCall
         ( "Keiki.Builder: edge #0 from A: no emit or noEmit. "
             <> "Each onCmd/onEpsilon body must call 'emit' "
             <> "(or 'emitWith') to produce an event, or 'noEmit' "
             <> "to declare the edge deliberately silent (ε-edge)."
         )

   it "bare goto in onEpsilon (no emit/noEmit) fires the new error" $ do
     let tr = B.buildTransducer A emptyR (const False) do
           B.from A do
             B.onEpsilon B.do
               B.goto B
     evaluate tr
       `shouldThrow` errorCall
         ( "Keiki.Builder: edge #0 from A: no emit or noEmit. "
             <> "Each onCmd/onEpsilon body must call 'emit' "
             <> "(or 'emitWith') to produce an event, or 'noEmit' "
             <> "to declare the edge deliberately silent (ε-edge)."
         )
   ```

   The exact string in the assertion **must** match the string produced in M1
   step 4 byte-for-byte (including the `ε` character and spacing). If the test
   fails only on the message text, reconcile the two literals — do not weaken the
   test to a prefix match.

4. **Confirm no edits are needed to the double-goto / missing-goto tests.**
   `coffeeDoubleGoto` ("duplicated goto…" in `BuilderSpike.hs`) and "case 8"
   (`BuilderSpec.hs`) must still pass with their *existing* messages, proving the
   goto-arity check runs before the output-intent check. If either now throws the
   new message instead, the branch ordering in `finalizeEdge` is wrong — fix M1,
   do not edit these tests.

Acceptance for M2: `cabal test all` is green for all four suites. The silent-edge
audit (see Concrete Steps) reports only deliberate malformed-edge tests; manual
inspection confirms that no production, example, or positive-test edge omits intent.

### Milestone M3 — Documentation and changelog

Scope: bring the prose in line with the new rule.

1. **`docs/research/edge-builder-dsl-shape.md`.** Around lines 209–218 the doc
   says an edge with neither `emit` nor `noEmit` "is treated as an ε-edge."
   Update that paragraph to state that `noEmit` is now required to declare a
   silent edge and that omitting both is an eager builder error. Add a short
   dated design-decision note (near the Q6 "goto and termination" section around
   line 346, which is the closest existing discussion of builder
   diagnostics) recording *why* — forgotten `emit` is a likely bug in an
   event-sourcing DSL, and the fix reuses EP-70's eager structured defect
   mechanism and gives `noEmit` a real purpose.

2. **`CHANGELOG.md`.** Under `## [Unreleased]`, add a `### Changed` subsection:

   ```markdown
   ### Changed

   - `Keiki.Builder` now requires every edge body to declare its output
     intent explicitly. An `onCmd`/`onEpsilon` body that reaches `goto`
     without calling `emit`/`emitWith` (produce an event) or `noEmit`
     (declare a deliberately silent ε-edge) is now an eager construction error,
     rather than silently becoming an ε-edge. Deliberately silent edges
     keep working by adding `noEmit`.
   ```

Acceptance for M3: the two documents read consistently with the code; a reader of
either the changelog or the research doc learns that `noEmit` is now required for
silent edges.


## Concrete Steps

All commands run from the repository root, `/Users/shinzui/Keikaku/bokuno/keiki`.

**Before starting — reproduce the research audit** (establishes the migration
surface; should print exactly the two known silent test blocks):

```bash
for f in $(grep -rln --include='*.hs' 'B\.goto\|B\.onEpsilon\|B\.onCmd' src test jitsurei); do
  awk -v F="$f" '
    /B\.onCmd|B\.onEpsilon/ { inblk=1; start=NR; hasterm=0; next }
    inblk && /B\.emit|B\.emitWith|B\.noEmit/ { hasterm=1 }
    inblk && /B\.goto/ { if (!hasterm) print F":"start": SILENT (goto, no emit/noEmit)"; inblk=0 }
  ' "$f"
done
```

Expected before the change (double-goto blocks are reported too because they never
emit; they are handled by the goto-arity branch and need no edit):

```text
test/Keiki/BuilderSpec.hs:234: SILENT (goto, no emit/noEmit)
test/Keiki/BuilderSpec.hs:265: SILENT (goto, no emit/noEmit)
test/Keiki/BuilderSpec.hs:346: SILENT (goto, no emit/noEmit)
test/Keiki/BuilderSpike.hs:167: SILENT (goto, no emit/noEmit)
test/Keiki/BuilderSpike.hs:198: SILENT (goto, no emit/noEmit)
```

Of these, lines 167 (BuilderSpike `coffeeBuilt`) and 265 (BuilderSpec case 10) are
the real ε-edges to migrate with `noEmit`; the other three are double-`goto`
misuse fixtures, including EP-70's structured-error aggregation case, and stay
untouched.

**M1 — build the library after the code edits:**

```bash
cabal build all
```

Expected: compiles with no errors. Warnings about the new field are not expected
(record construction is total in all three `PartialEdge` sites).

**M1 — confirm the check fires (before M2 migration):**

```bash
cabal test keiki-test 2>&1 | tail -40
```

Expected at this point: failures in the spike's "Brewing + Continue" agreement
test and in "case 10", each surfacing the new "no emit or noEmit" error. This is
the intended proof that the check is live; M2 resolves it.

**M2 — after migrating and adding tests, run the full suite:**

```bash
cabal test all 2>&1 | tail -60
```

Expected: both suites pass. Look for the two new example lines, e.g.:

```text
  bare goto in onCmd (no emit/noEmit) fires the new error
  bare goto in onEpsilon (no emit/noEmit) fires the new error
```

and no failures.

**M2 — re-run the audit; expect only deliberate negative fixtures to remain:**

```bash
for f in $(grep -rln --include='*.hs' 'B\.goto\|B\.onEpsilon\|B\.onCmd' src test jitsurei); do
  awk -v F="$f" '
    /B\.onCmd|B\.onEpsilon/ { inblk=1; start=NR; hasterm=0; next }
    inblk && /B\.emit|B\.emitWith|B\.noEmit/ { hasterm=1 }
    inblk && /B\.goto/ { if (!hasterm) print F":"start": SILENT (goto, no emit/noEmit)"; inblk=0 }
  ' "$f"
done
```

Expected:

```text
test/Keiki/BuilderSpec.hs:234: SILENT (goto, no emit/noEmit)
test/Keiki/BuilderSpec.hs:247: SILENT (goto, no emit/noEmit)
test/Keiki/BuilderSpec.hs:260: SILENT (goto, no emit/noEmit)
test/Keiki/BuilderSpec.hs:373: SILENT (goto, no emit/noEmit)
test/Keiki/BuilderSpike.hs:199: SILENT (goto, no emit/noEmit)
```

The entries at BuilderSpec lines 247 and 260 are the new bare-`goto` regressions.
The other three are double-`goto` fixtures handled by the goto-arity branch. All
five are intentionally malformed and correct as-is; there must be no additional
entry from a production, example, or positive-test edge.

**Commits.** Commit once per milestone. Every commit message must carry all three
trailers:

```text
MasterPlan: docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md
ExecPlan: docs/plans/68-require-explicit-emit-noemit-intent-on-every-builder-edge.md
Intention: intention_01kxc5whw1en3ra4nh728m53ka
```

Suggested commit subjects (Conventional Commits):

- M1: `feat(builder)!: require explicit emit/noEmit intent on every edge`
- M2: `test(builder): migrate silent edges to noEmit; cover the new error`
- M3: `docs(builder): document required output intent and changelog entry`

The `!` on M1 marks the behavioral tightening.


## Validation and Acceptance

The change is validated by behavior, not just compilation:

1. **The new error fires for a forgotten emit.** After M1+M2, an `onCmd` body that
   ends in `B.goto` with no output call causes `evaluate tr`
   to throw an `errorCall` whose message is exactly:

   ```text
   Keiki.Builder: edge #0 from A: no emit or noEmit. Each onCmd/onEpsilon body must call 'emit' (or 'emitWith') to produce an event, or 'noEmit' to declare the edge deliberately silent (ε-edge).
   ```

   This is asserted by the two new regression tests (`onCmd` and `onEpsilon`
   forms).

2. **Deliberate silence still works.** "case 5" in `test/Keiki/BuilderSpec.hs`
   (`noEmit` yields `output = []`) continues to pass, proving `noEmit` still
   produces an ε-edge — now as the *sanctioned* way to do so. The migrated
   `coffeeBuilt` edge (with `noEmit`) keeps `output = []`, so the spike's
   delta/omega agreement tests for "Brewing + Continue" continue to pass.

3. **Emit still works and is unaffected.** All existing `emit`-based cases
   (cases 1, 2, 4 in `BuilderSpec.hs`, the Idle+Insert agreement in
   `BuilderSpike.hs`, and every `jitsurei` example) pass unchanged, proving the
   new flag does not disturb the emit path.

4. **Goto-arity precedence is preserved.** The double-goto and missing-goto tests
   pass with their original messages, proving the new check does not shadow the
   goto diagnostics.

5. **Whole-suite green.** `cabal test all` passes all four test suites,
   demonstrating no real consumer or codec regressed.

Acceptance is the conjunction of all five, plus the silent-edge audit reporting
only the five deliberate malformed-edge fixtures described above.


## Idempotence and Recovery

Every step is safe to repeat. The code edits are small and local; re-running
`cabal build` / `cabal test` is idempotent. The audit scripts are read-only.

If M1's build fails because the new `peOutputDecided` field was added to the record
type but not to one of the three construction sites (`onCmd`, `onEpsilon`, and the
error is a "fields not initialised" warning-as-error or a type error), add the
missing `peOutputDecided = False`/`= True` to the offending `PartialEdge { … }`
literal. GHC names the site.

If M2's new tests fail *only* on message text, the assertion string and the
`error` string have drifted — reconcile them character-for-character (the `ε`
symbol is easy to lose in a copy). Do not relax the test to a substring match; the
exact message is part of the contract.

If, after M1, one of the double-goto tests reports the *new* message instead of the
double-goto message, the branch ordering in `finalizeEdge` is wrong: ensure the
`(_ : _ : _)` case still precedes nothing that could catch two targets, and that
the output-intent guard lives strictly inside the single-target `[t]` branch.

To roll back entirely, revert the commits for M1–M3; there are no migrations,
generated artifacts, or external state involved.


## Interfaces and Dependencies

No new libraries. All work is inside the existing `keiki` package (`src/`,
`test/`) and its documentation, plus a changelog entry. The `jitsurei` package is
only *exercised* (via `cabal test all`) to confirm no regression; it is not edited.

Signatures and shapes that must exist at the end of each milestone (all in
`src/Keiki/Builder.hs` unless noted):

- **After M1:**
  - `PartialEdge` gains `peOutputDecided :: Bool` (its public-facing type is
    internal to the module; `PartialEdge` is not exported).
  - `noEmit :: EdgeBuilder rs ci co v pin w w ()` — unchanged signature, new behavior
    (sets `peOutputDecided = True`).
  - `emit`, `emitWith` — unchanged signatures, each now also sets
    `peOutputDecided = True`.
  - `BuilderDefect` gains `DefectMissingOutputIntent`.
  - `finalizeEdge :: PartialEdge rs ci co v pin w -> Either BuilderDefect (Edge …)`
    — unchanged EP-70 signature, with a new defect when an edge has exactly one
    `goto` but `peOutputDecided == False`.
  - `renderBuilderErrors` renders the exact missing-output-intent message.
  - The public exports of `Keiki.Builder` (the module export list) are unchanged;
    this is purely an added runtime precondition, not an API surface change.

- **After M2:** `test/Keiki/BuilderSpec.hs` contains two new `it "…"` regression
  tests asserting the new error for `onCmd` and `onEpsilon`; `BuilderSpike.hs` and
  `BuilderSpec.hs` case 10 carry an added `B.noEmit`. Test suites `keiki-test` and
  `jitsurei-test` both pass.

- **After M3:** `CHANGELOG.md` has a `### Changed` entry under `[Unreleased]`;
  `docs/research/edge-builder-dsl-shape.md` states that `noEmit` is required for
  silent edges and carries a dated decision note.


## Revision Notes

- 2026-07-12: Adopted into MasterPlan 16
  (`docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md`)
  with a hard dependency on plan 70 (eager builder validation). Added a Decision
  Log entry correcting this plan's assumption that `buildTransducer` evaluates
  the builder eagerly — the 2026-07 architecture review showed `finalizeEdge`
  errors are lazy thunks until plan 70 makes finalization eager. The missing-intent
  case must use EP-70's structured `BuilderDefect`; the lazy-first landing order is no
  longer allowed. Frontmatter gained the
  `master_plan` field. No change to the diagnostic's design (`peOutputDecided`
  flag, message text, test list).
- 2026-07-12: Applied EP-70's completed handoff. Rewrote the implementation and
  acceptance instructions around `DefectMissingOutputIntent`,
  `Either BuilderDefect Edge`, `renderBuilderErrors`, and `evaluate tr`; removed
  the obsolete lazy `finalizeEdge` forcing assumptions while preserving exact
  message text and goto-arity precedence.
