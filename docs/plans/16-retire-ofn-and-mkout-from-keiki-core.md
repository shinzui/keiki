---
id: 16
slug: retire-ofn-and-mkout-from-keiki-core
title: "Retire OFn and mkOut from Keiki.Core"
kind: exec-plan
created_at: 2026-05-02T13:37:03Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
master_plan: "docs/masterplans/6-retire-remaining-v1-escape-hatches-in-pure-core-ofn-pmatchc-unsafecombine-static-check.md"
---

# Retire OFn and mkOut from Keiki.Core

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

`Keiki.Core` exports a v1 escape-hatch constructor `OFn` on the
`OutTerm` type that carries an opaque Haskell function `RegFile rs ->
ci -> co`. The constructor is authored through the `mkOut` helper.
Because `OFn` carries arbitrary code rather than a structural
description of how the output is built from the inputs and the
register file, three keiki guarantees fail on `OFn`-shaped edges:

- **Mechanical inversion** (`solveOutput`) returns `Nothing` — the
  inverse of an opaque function cannot be computed by walking AST
  shape.
- **Hidden-input check** (`checkHiddenInputs`) emits a warning like
  *"OFn output is opaque (no inverse)"* — the analysis cannot tell
  which input fields the function reads.
- **Composition** (`Keiki.Composition.compose`) refuses to thread
  `OFn` outputs through substitution and aborts with a runtime
  `error` naming the unsupported edge.

A 2026-05-02 survey (recorded in
`docs/research/v1-escape-hatch-retirements-design.md`) found that
**no example aggregate uses `OFn` or `mkOut`**:

    $ grep -rn "OFn\|mkOut" src/Keiki/Examples/
    (no output)

The only consumers are (a) `Keiki.Core` itself (the constructor and
helper), (b) `src/Keiki/Composition.hs`'s defensive `OFn _ -> error`
clauses, and (c) `test/Keiki/CoreSpec.hs`'s synthetic test cases that
exercise the OFn-specific behaviour.

After this plan lands, the user can no longer write an output term
through `mkOut`. Every output term in the keiki library must be
authored through the structural `pack` / `OPack` form (which carries
an `InCtor`, a `WireCtor`, and an `OutFields` chain). The user
verifies the change by running `cabal build && cabal test all` (still
green, with the test count reduced by the removed OFn-specific
describe blocks) and by checking that `Keiki.Core` no longer exports
`mkOut` or `OFn` (compilation error if any code still imports them).

The change is a strict deletion plus a synthetic-test rewrite. There
is no behavioural successor; the language simply gets smaller. This
follows the design-note recommendation of "remove outright (no
successor needed)" because there is no current usage to cover.


## Progress

Use a checklist to summarize granular steps. Every stopping point
must be documented here, even if it requires splitting a partially
completed task into two ("done" vs. "remaining"). This section must
always reflect the actual current state of the work.

- [x] M0: Verify prerequisites — `cabal build && cabal test all` is
  green; record GHC version if it differs from EP-15's M0 baseline
  (GHC 9.12.3, 110 examples passing — up from EP-15's recorded 107
  due to EP-13 follow-up's `deriveView` on EmailDelivery).
- [x] M1: Remove `OFn` constructor and `mkOut` helper from
  `src/Keiki/Core.hs`; update the export list and the evaluator /
  analysis clauses (`evalOut`, `solveOutput`, `checkHiddenInputs`).
- [x] M2: Remove the `OFn _ -> error` clauses in
  `src/Keiki/Composition.hs` (`substTerm`, `substPred`, `substOut`).
  After M1's GADT-narrowing the cases are unreachable; this milestone
  deletes them and confirms the file still type-checks.
- [x] M3: Rewrite `test/Keiki/CoreSpec.hs` — replaced the
  `mkOut (\_ _ -> "true")` synthetic transducer with a structural
  `OPack` fixture using new `inCtorTrue` (singleton InCtor over
  `True :: Bool`, empty payload) and `wcStringTrue` (singleton
  WireCtor over `String` recognising "true", empty fields). Deleted
  the "solveOutput on OFn (opaque)" describe block and the
  "synthetic transducer's OFn output is flagged" assertion plus the
  surrounding `describe "checkHiddenInputs"`. Removed the now-unused
  `data TinyOut = Foo Int Int`. Test count: 108 (down from M0's 110
  by exactly the two OFn-specific cases removed).
- [x] M4: Removed the OFn bullet from the module-header retirement
  block of `src/Keiki/Core.hs:22-33` (PMatchC and unsafeCombine
  bullets retained). Same removal applied to the closing list in
  `docs/research/dsl-shape-for-symbolic-register.md:1001-1015`.
- [x] M5: Verdict — `cabal build && cabal test all` green (108/108);
  `grep "OFn\|mkOut" src/Keiki/Core.hs src/Keiki/Composition.hs`
  empty; commit and MP-6 registry update next.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights
discovered during implementation. Provide concise evidence.

- M0 baseline differs from EP-15's recorded 107 examples: the suite
  now reports 110, three additional `Keiki.Examples.EmailDelivery
  (view)` cases added by `4489ec4 feat(examples): EP-13 follow-up —
  deriveView on EmailDelivery`. Final post-M3 count: 108 (110 minus
  the two OFn-specific cases removed in M3, no others affected).

- The structural `OPack` replacement for the synthetic transducer
  needed both an InCtor *and* a WireCtor with `icName == wcName ==
  "True"` so `solveOutput` accepts the empty walk. The empty-payload
  case (`InCtor Bool '[]`, `WireCtor String ()`, `OFNil`) is the
  cleanest mechanical inverse: `assemble [] = Just RNil`, then
  `icBuild inCtorTrue RNil = True`. This is a worked example of the
  empty-payload recovery path documented in `solveOutput`'s
  Haddock — useful as a fixture-pattern reference for future tests
  needing a degenerate OPack.


## Decision Log

Record every decision made while working on the plan.

- Decision: No structural successor for `OFn`. Remove outright.
  Rationale: EP-15's M1 survey found zero aggregate uses. Speculatively
  keeping a renamed escape hatch for a constructor with no current
  users would be dead weight; the language simply gets smaller. If a
  future user needs an opaque output, a named hatch can be
  re-introduced at that time.
  Date: 2026-05-02

- Decision: Rewrite the synthetic-transducer fixture in
  `test/Keiki/CoreSpec.hs` to use `OPack` rather than introducing a
  new test-only opaque hatch.
  Rationale: The synthetic transducer's purpose is to exercise the
  pure-core machinery (delta, omega, step). It can do that with any
  `OutTerm`; a one-field `OPack` over a singleton input constructor
  is mechanical to author and keeps the test fixture inside the
  surface that user code is required to use. This avoids leaking a
  back-door into the test fixtures.
  Date: 2026-05-02


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or
at completion. Compare the result against the original purpose.

**Outcome.** EP-16 landed as designed — pure mechanical deletion. The
`OFn` constructor and `mkOut` helper are gone from `Keiki.Core`; the
four `OFn _ -> error` clauses in `Keiki.Composition`'s substitution
helpers are gone (GHC narrows the GADT exhaustively without them).
The synthetic test transducer in `test/Keiki/CoreSpec.hs` now uses a
structural `OPack` and exercises `solveOutput`'s empty-payload
recovery path. The retirement-block comments in `Keiki.Core` and
`docs/research/dsl-shape-for-symbolic-register.md` no longer mention
`OFn`; they keep the PMatchC and unsafeCombine bullets pending
EP-17 / EP-18.

**Acceptance gates met.**

- `cabal build && cabal test all` green (108/108, GHC 9.12.3).
- `grep "OFn\|mkOut" src/Keiki/Core.hs src/Keiki/Composition.hs`
  returns empty.
- Importing `mkOut` from `Keiki.Core` is a compile error (export
  removed).
- Constructing an `OFn` value is a compile error (constructor
  removed).

**Test count delta.** 110 → 108 (M0 → M5). Exactly two cases removed
as planned: the "solveOutput on OFn (opaque)" describe block and the
"synthetic transducer's OFn output is flagged" assertion. No other
test cases were affected.

**Lessons for sibling EPs.**

- EP-17 (PMatchC retirement) is structurally identical to this plan:
  remove a constructor, narrow the analyses, rewrite the synthetic
  test, tick the retirement bullet. It will likely take a similar
  amount of work.
- EP-18 (unsafeCombine static check) is the substantive one and
  benefits from this plan's clean retirement-block state — when EP-18
  performs its IP-5 sweep, only the `unsafeCombine` bullet will
  remain to remove, then the whole block goes.


## Context and Orientation

A reader picking up this plan needs:

- **The keiki pure core** lives in `src/Keiki/Core.hs`. The two
  types directly affected:

  - `OutTerm (rs :: [Slot]) (ci :: Type) (co :: Type)` — pure
    expressions yielding output values. As of master, the constructors
    are `OPack` (structural; carries an `InCtor ci ifs`, a `WireCtor
    co fields`, and an `OutFields rs ci fields`) and `OFn` (the
    opaque-function escape hatch this plan retires). The constructor
    declarations are at lines 327-343.

  - `Edge phi rs ci co s` — a transition. Carries
    `output :: Maybe (OutTerm rs ci co)`. ε-edges (no event) have
    `output = Nothing`; output-bearing edges carry an `OutTerm`.

  After this plan lands, `OutTerm` has only `OPack`.

- **The helper functions** affected:

  - `mkOut :: (RegFile rs -> ci -> co) -> OutTerm rs ci co` at line
    445 — wraps `OFn`. Removed by this plan.
  - `pack :: InCtor ci ifs -> WireCtor co fields -> OutFields rs ci
    fields -> OutTerm rs ci co` at line 477 — wraps `OPack`. Stays.

- **The evaluator and analyses** that case-match on `OutTerm`:

  - `evalOut :: OutTerm rs ci co -> RegFile rs -> ci -> co` at line
    around 504. The `OFn` clause is `evalOut (OFn f) regs ci = f regs
    ci`. Removed by this plan.
  - `solveOutput :: OutTerm rs ci co -> RegFile rs -> co -> Maybe ci`
    at line around 642. The `OFn _` clause returns `Nothing`. Removed
    by this plan.
  - `checkHiddenInputs :: SymTransducer ... -> [HiddenInputWarning]`
    at line around 716. The `OFn _ -> ...` clause emits a warning
    *"edge #N: OFn output is opaque (no inverse)"*. Removed by this
    plan.

- **The composition module** at `src/Keiki/Composition.hs` exports
  `compose`. Composition substitutes a `t2`-side AST against a
  `t1`-edge's `OutTerm` (its `OPack` constructor specifically); the
  algorithm cannot thread an opaque function through substitution, so
  four clauses currently abort with `error`:

  - `substTerm` at line 221, `substPred` at line 261, `substOut` at
    line 314 (matched against `t1`'s output), `substOut` at line 316
    (matched against `t2`'s output).

  These clauses become statically impossible once `OFn` is gone (GHC
  narrows the GADT match), so they are deleted. The compose algorithm
  itself does not change.

- **The test file** `test/Keiki/CoreSpec.hs` contains:

  - Line 38: a synthetic transducer using `mkOut (\_ _ -> "true")` as
    one edge's output.
  - Lines 120-123: a "solveOutput on OFn (opaque)" describe block
    that constructs an `OFn (\_ ci -> Foo ci ci)` and asserts
    `solveOutput` returns `Nothing`.
  - Lines 180-183: an assertion inside the `checkHiddenInputs`
    describe block that the synthetic transducer's `OFn` output is
    flagged with a warning whose `hiwReason` contains
    `"OFn output is opaque"`.

- **The retirement-block comment** in `src/Keiki/Core.hs:22-33`
  enumerates the v1 escape hatches still owned by MasterPlan 6.
  After this plan, the OFn bullet (lines 27-28) is removed; the block
  stays because PMatchC and unsafeCombine remain. The whole block is
  removed by EP-18 (the last retirement) per MP-6's IP-5.

- **The MasterPlan 6 design note** at
  `docs/research/v1-escape-hatch-retirements-design.md` records the
  rationale for "remove outright (no successor needed)". Read its
  "OFn — REMOVE outright" section for the framing this plan
  implements.

Terms of art used in this plan:

- **Escape hatch.** A constructor in the pure-core DSL that holds an
  opaque Haskell value (a function or a closure). Escape hatches
  evaluate correctly but defeat structural analyses.
- **Mechanical inversion.** Recovery of an input from an output by
  walking the structure of the `OutTerm`'s `OutFields` chain against
  the named `InCtor`'s slot list. The function `solveOutput` performs
  this; on `OPack` it succeeds when fields cover every input slot;
  on `OFn` it always returns `Nothing`.
- **GADT narrowing.** GHC's pattern-match coverage check eliminates
  case clauses for constructors that have been removed from a GADT.
  After this plan removes `OFn`, any `OFn _ -> ...` clause becomes
  unreachable and (with `-Wincomplete-patterns`) raises a warning.


## Plan of Work

The work is one cohesive change but split into milestones so the
intermediate states compile.

### M0 — Prerequisites

Verify the working tree builds and tests pass before any edits:

    cabal build
    cabal test all

Acceptance: 107 examples, 0 failures (matches EP-15's M0 baseline).

This milestone produces no source-tree changes.

### M1 — Remove `OFn` and `mkOut` from `Keiki.Core`

Edit `src/Keiki/Core.hs`:

1. **Export list** (around line 67): remove the `, mkOut` line.
2. **`OutTerm` constructor** (lines 340-343): remove the `OFn` clause
   along with its Haddock comment ("v1 escape hatch: opaque
   function..."). The remaining `OPack` clause becomes the sole
   constructor; clean up any trailing comma. Keep the type's Haddock
   header.
3. **`mkOut` helper** (lines 442-446): remove the helper, its
   signature, and its Haddock comment.
4. **`evalOut`** (line ~504): remove the `evalOut (OFn f) regs ci =
   f regs ci` clause. The remaining `OPack` clause stays.
5. **`solveOutput`** (line ~642): remove the
   `solveOutput (OFn _) _regs _co = Nothing` clause.
6. **`checkHiddenInputs`** (lines ~716-717): remove the
   `Just (OFn _) -> [ "edge #" <> show n <> ": OFn output is opaque
   (no inverse)" ]` clause. The function's other branches stay
   (notably the structural-coverage analysis on `OPack`).

After this milestone, `cabal build` should succeed (the synthetic
test fixture in `test/Keiki/CoreSpec.hs` will fail to compile because
it references `mkOut` / `OFn`; that's M3's work). To check core in
isolation:

    cabal build keiki:lib

Expected: success. The library no longer exports `mkOut` and the
`OutTerm` GADT no longer has an `OFn` constructor.

### M2 — Remove `OFn`-handling clauses in `Keiki.Composition`

Edit `src/Keiki/Composition.hs`:

1. **`substTerm`** at line 221: remove the
   `OFn _ -> error "..."` clause inside the `case o1 of` block. The
   remaining `OPack ...` clauses cover the GADT exhaustively.
2. **`substPred`** at line 261: same — remove the `OFn _ -> error
   "..."` clause inside `case o1 of`.
3. **`substOut`** at line 314: remove the `OFn _ -> error "..."`
   inside the inner `case o1 of`.
4. **`substOut`** at line 316: remove the `substOut (OFn _) _o1 =
   error "..."` standalone clause.

After this milestone:

    cabal build keiki:lib

Expected: success with no warnings about missing `-Wincomplete-patterns`
clauses (the four clauses are no longer reachable; with `OFn` gone
they would otherwise be flagged as redundant).

### M3 — Rewrite `test/Keiki/CoreSpec.hs`

Edit `test/Keiki/CoreSpec.hs`:

1. **Synthetic transducer fixture** (line ~38): replace
   `mkOut (\_ _ -> "true")` with a structural `OPack`. The simplest
   replacement: introduce a one-constructor input-side `InCtor` (or
   reuse an existing tiny one in the file if one is defined) and a
   one-field `WireCtor`, and pack the literal "true" through them.
   If no convenient `InCtor` exists in the file, define a local
   tiny-`InCtor` near the synthetic transducer. The exact shape:

       output = Just $ pack tinyIc tinyWc (OFCons (TLit "true") OFNil)

   where `tinyIc :: InCtor TestInput '[]` is a singleton constructor
   over the test's input symbol (use `RNil`-shaped `icMatch` /
   `icBuild`) and `tinyWc :: WireCtor String '(String, ())` matches
   the wire output as a single-field tuple.

   Read the existing `Keiki.Generics.TH` test fixture or the
   `UserRegistration`-style `inCtorContinue` for a worked example of
   a singleton `InCtor` and a one-field `WireCtor`.

2. **"solveOutput on OFn (opaque)" describe block** (lines
   120-123): delete the whole describe block.

3. **"checkHiddenInputs" describe block** (line ~180): delete the
   `it "synthetic transducer's OFn output is flagged"` test case.
   Keep the rest of the describe block (e.g. the V0 unfixed-schema
   warning test, which is structural and survives this plan).

After this milestone:

    cabal test keiki:keiki-test

Expected: green; the example count drops by exactly the number of
test cases removed (one for the `solveOutput on OFn` block, one for
the synthetic-OFn-flagged assertion, plus any others that no longer
apply — verify against the M0 baseline of 107 and record the new
total in the Surprises & Discoveries section).

### M4 — Tick the retirement block

Edit `src/Keiki/Core.hs:22-33` — the module-header comment listing
"v1 escape hatches still pending retirement, all owned by MasterPlan 6".
Remove the OFn bullet (the two-line entry starting `* 'OFn' carries
an opaque...`). Keep the block header and the PMatchC and
unsafeCombine bullets.

This milestone makes no other source-tree changes; it's a comment
edit so future readers of `Keiki.Core` see the up-to-date status.

The same retirement-block comment in
`docs/research/dsl-shape-for-symbolic-register.md:1001-1015` is
similarly trimmed: remove the `OFn` bullet, keep the `PMatchC` and
`unsafeCombine` bullets and the surrounding header. The whole block
is deleted by EP-18 (the last retirement) per MP-6's IP-5.

### M5 — Verdict

Run the full test suite:

    cabal build
    cabal test all

Acceptance:

- All examples pass (count is M0's 107 minus the OFn-specific cases
  removed in M3).
- `Keiki.Core` no longer exports `mkOut` or the `OFn` constructor
  (verify with `grep -n "OFn\|mkOut" src/Keiki/Core.hs` returning
  only Haddock-comment references, if any remain).
- `src/Keiki/Composition.hs` no longer contains the four
  `OFn _ -> error` clauses (verify with `grep -n "OFn" src/Keiki/Composition.hs`
  returning empty).

Commit the work. Update MP-6's Exec-Plan Registry to mark this plan
**Complete**. Write the Outcomes & Retrospective entry.


## Concrete Steps

Run from the repository root.

M0:

    cabal build
    cabal test all
    # expect: 107 examples, 0 failures

M1 — surface check after editing `Keiki.Core`:

    cabal build keiki:lib

M2 — surface check after editing `Keiki.Composition`:

    cabal build keiki:lib

M3 — exercise the rewritten test file:

    cabal test keiki:keiki-test 2>&1 | tail -20

M5 — final acceptance:

    cabal build
    cabal test all
    grep -n "OFn\|mkOut" src/Keiki/Core.hs src/Keiki/Composition.hs
    # expect: empty (or only Haddock-prose references that were
    # intentionally left)

Commit (with `MasterPlan:`, `ExecPlan:`, and `Intention:` trailers
per the master-plan / exec-plan skill protocols).


## Validation and Acceptance

After M5, the user should observe:

- `cabal build` produces no warnings related to OFn (no
  `-Wincomplete-patterns` warnings about missing `OFn` cases — the
  constructor is gone, so the previously-required clauses are no
  longer relevant).
- `cabal test all` is green; the test count is M0's 107 minus the
  OFn-specific cases removed in M3 (typically 2-3 cases).
- `grep` confirms no remaining `OFn` or `mkOut` references in
  `src/Keiki/Core.hs` or `src/Keiki/Composition.hs`.
- The MP-6 retirement-block comment in `Keiki.Core` and the v1
  surfaces note in `docs/research/dsl-shape-for-symbolic-register.md`
  no longer mention `OFn`.
- A user attempting to import `mkOut` from `Keiki.Core` gets a
  compile error: *"Module 'Keiki.Core' does not export 'mkOut'"*.
- A user attempting to construct an `OFn` value gets a compile error:
  *"Data constructor not in scope: 'OFn'"*.

The behavioural acceptance — that no aggregate's behaviour changes —
is implicit because no aggregate uses OFn. The test suite covers the
synthetic cases.


## Idempotence and Recovery

Each milestone is independently re-runnable; rerunning a successful
milestone is a no-op. If a milestone fails partway:

- M1 / M2 source edits: `git diff` shows the partial state. Either
  finish the edits or `git checkout -- <file>` to reset and retry.
- M3 test rewrite: the new fixture (`tinyIc` / `tinyWc`) is the only
  net-new test machinery. If GHC reports a structural mismatch
  between the `InCtor` slot list and the `WireCtor` field tuple,
  re-derive both from the same singleton type to keep them aligned
  (the keiki invariant is that `icName` equals `wcName` and the slot
  positions correspond — see
  `docs/research/composition-combinators-design.md` for the
  structural alignment rule).
- M4 comment edit: trivially recoverable.

There is no destructive-operation hazard in this plan; all changes
are local source edits to the keiki library and its test suite.


## Interfaces and Dependencies

After this plan, the following must hold:

- `Keiki.Core` exports do **not** include `mkOut`. The export list
  spans roughly lines 36-94; the `mkOut` line (currently around line
  67) is removed.
- `OutTerm` has exactly one constructor: `OPack`.
- `evalOut`, `solveOutput`, and `checkHiddenInputs` each have one
  fewer clause than at the start of the plan.
- `src/Keiki/Composition.hs`'s substitution helpers (`substTerm`,
  `substPred`, `substOut`) handle only `OPack`; the GADT shape makes
  the case exhaustive.
- `test/Keiki/CoreSpec.hs`'s synthetic transducer uses `pack` (the
  `OPack` helper) rather than `mkOut`.

Soft dependencies:

- **EP-15** (`docs/plans/14-design-milestone-decompose-v1-escape-hatch-retirements-ofn-pmatchc-unsafecombine-static-check.md`)
  — its design note at
  `docs/research/v1-escape-hatch-retirements-design.md` is the
  rationale for "remove outright". Read it before starting in case
  questions about backwards compatibility come up.

- **EP-17 and EP-18** (sibling retirement EPs) — independently
  mergeable. Order convention is EP-16 → EP-17 → EP-18 because the
  module-header retirement-block cleanup is cleanest when EP-18 (last)
  removes the whole block. EP-16 only ticks its own bullet.

No hard dependencies; no external library bumps; no GHC version
constraints beyond the existing GHC 9.12.3 baseline.
