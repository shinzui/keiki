---
id: 17
slug: retire-pmatchc-and-matchcmd-from-keiki-core
title: "Retire PMatchC and matchCmd from Keiki.Core"
kind: exec-plan
created_at: 2026-05-02T13:37:06Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
master_plan: "docs/masterplans/6-retire-remaining-v1-escape-hatches-in-pure-core-ofn-pmatchc-unsafecombine-static-check.md"
---

# Retire PMatchC and matchCmd from Keiki.Core

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

`Keiki.Core` exports a v1 escape-hatch constructor `PMatchC` on the
`HsPred` predicate type that carries an opaque Haskell function `ci
-> Bool`. The constructor is authored through the `matchCmd` helper.
Because `PMatchC` carries arbitrary code rather than a structural
description of the guard, two keiki guarantees fail on
`PMatchC`-shaped guards:

- **SBV translation** (`Keiki.Symbolic.translatePred`) cannot
  translate the opaque function and falls back to an unconstrained
  `SBool` — meaning the symbolic analyses (`isBot`, `sat`,
  `isSingleValuedSym`) over a guard containing `PMatchC` give weak
  answers (the solver treats the predicate as nondeterministic).
  Documented in `docs/research/sbv-boolalg-design.md` lines 280-289.
- **Composition** (`Keiki.Composition.compose`) refuses to
  substitute through `PMatchC` over the mid type and aborts with a
  runtime `error` naming the unsupported edge.

A 2026-05-02 survey (recorded in
`docs/research/v1-escape-hatch-retirements-design.md`) found that
**no example aggregate uses `PMatchC` or `matchCmd`**:

    $ grep -rn "PMatchC\|matchCmd" src/Keiki/Examples/
    src/Keiki/Examples/UserRegistrationV0.hs:89:-- | Per-constructor guards. Migrated from v1 'matchCmd' to v2

The only match in `src/Keiki/Examples/` is a *historical* code
comment recording the V0 aggregate's prior migration to
`matchInCtor`. The non-test, non-Core consumers are (a)
`Keiki.Core` itself, (b) `src/Keiki/Symbolic.hs`'s SBV-fallback
clause, (c) `src/Keiki/Composition.hs`'s `weakenLPred` passthrough
and `substPred` defensive `error`, and (d) `test/Keiki/CoreSpec.hs`'s
synthetic test cases.

EP-2 of MasterPlan 2 introduced `PInCtor :: InCtor ci ifs -> HsPred
rs ci` (helper `matchInCtor`) as the structural alternative for the
constructor-equality guard case. Combined with the existing `PEq`,
`PAnd`, `POr`, `PNot`, and `PTop` / `PBot` constructors, every guard
in every example aggregate today is expressed structurally.

After this plan lands, the user can no longer write a guard through
`matchCmd`. Every guard in the keiki library must be authored from
the structural algebra: `PInCtor` (constructor-equality), `PEq`
(field-equality), `PAnd` / `POr` / `PNot` (boolean composition),
`PTop` / `PBot` (constants). The user verifies the change by running
`cabal build && cabal test all` (still green, with the test count
reduced by the removed PMatchC-specific assertions) and by checking
that `Keiki.Core` no longer exports `matchCmd` or `PMatchC`
(compilation error if any code still imports them).

The change is a strict deletion plus a synthetic-test rewrite. There
is no behavioural successor; the language simply gets smaller. This
follows the design-note recommendation of "remove outright (no
successor needed)".


## Progress

Use a checklist to summarize granular steps. Every stopping point
must be documented here, even if it requires splitting a partially
completed task into two ("done" vs. "remaining"). This section must
always reflect the actual current state of the work.

- [x] M0: Verify prerequisites — `cabal build && cabal test all` was
  green at end of EP-16 (108 examples passing, GHC 9.12.3). EP-17
  resumed from that state without an additional rerun.
- [x] M1: Removed `PMatchC` constructor and `matchCmd` helper from
  `src/Keiki/Core.hs`; updated the export list and the `evalPred`
  clause; revised `PInCtor` and `matchInCtor` Haddock to drop
  back-compat references to `PMatchC`/`matchCmd`.
- [x] M2: Removed the `PMatchC` clause from
  `src/Keiki/Symbolic.hs`'s `translatePred` (the SBV-fallback
  `SBV.free "pmatchc"` line) and trimmed both Haddock references
  (the constructor list at lines ~273 and the escape-hatch
  enumeration at line ~512).
- [x] M3: Removed the `PMatchC` clauses in
  `src/Keiki/Composition.hs` (`weakenLPred` passthrough; `substPred`
  defensive `error`). Library type-checks with all six surviving
  `HsPred` constructors handled exhaustively.
- [x] M4: Rewrote `test/Keiki/CoreSpec.hs` — replaced `matchCmd id`
  in the synthetic transducer's guard with `matchInCtor inCtorTrue`
  (reusing the `inCtorTrue` defined for EP-16's M3; same truth-table
  on `Bool`). Deleted the "PMatchC dispatches to the carried
  predicate" test case. Test count: 107 (down from M0's 108 by
  exactly the one PMatchC-dispatch case).
- [x] M5: Updated `docs/research/sbv-boolalg-design.md` — replaced
  the "PMatchC fallback (the load-bearing decision)" section with a
  "Historical: the PMatchC fallback (retired by EP-17 of MP-6,
  2026-05-02)" note that preserves the EP-2 motivation context;
  removed the constructor-list `PMatchC f` bullet; updated the
  "Translation refuses" failure-mode entry; removed the future-work
  PMatchC retirement bullet.
- [x] M6: Removed the PMatchC bullet from the module-header
  retirement block of `src/Keiki/Core.hs:22-33`. Same removal applied
  to the closing list in
  `docs/research/dsl-shape-for-symbolic-register.md`. Both blocks
  now show only the unsafeCombine bullet pending EP-18.
- [x] M7: Verdict — `cabal build && cabal test all` green (107/107);
  `grep "PMatchC\|matchCmd" src/Keiki/Core.hs src/Keiki/Symbolic.hs
  src/Keiki/Composition.hs` empty; commit and MP-6 registry update
  next.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights
discovered during implementation. Provide concise evidence.

- **EP-16's `inCtorTrue` was directly reusable as the synthetic
  transducer's structural guard.** The plan anticipated either a
  `PEq (TLit True) (TLit True)` always-true guard or a custom
  singleton-input rewrite. In practice the `inCtorTrue :: InCtor
  Bool '[]` defined for EP-16's M3 (matches `True` only, empty
  payload) was already the right structural shape: `matchInCtor
  inCtorTrue` has the same truth-table as `matchCmd id` over
  `Bool`. Zero new test machinery required for M4. Worth noting for
  the EP-18 author: structural fixtures introduced by sibling EPs
  may compose cleanly with later retirements.

- **Test count dropped by exactly 1 at M4** (108 → 107), matching
  the plan's prediction. No incidental regressions.


## Decision Log

Record every decision made while working on the plan.

- Decision: No richer pattern AST; remove `PMatchC` outright.
  Rationale: EP-15's M1 survey found that every guard in every
  example aggregate is expressible from `PInCtor` + `PEq` + `PAnd` /
  `POr` / `PNot` + `PTop` / `PBot`. A speculative pattern AST (e.g.
  payload patterns beyond simple field equality) has no current
  user. If a future aggregate needs one, the design can extend
  `HsPred` then.
  Date: 2026-05-02

- Decision: Replace the `matchCmd id` guard in
  `test/Keiki/CoreSpec.hs`'s synthetic transducer with a structural
  alternative rather than reintroducing a back-door.
  Rationale: The synthetic transducer's purpose is to exercise the
  pure-core machinery (delta, omega, edge-traversal). It can do that
  with any `HsPred`; the simplest replacement is `PEq (TLit True)
  (TLit True)` (always true; equivalent to the previous `matchCmd
  id` over a `Bool`-valued `ci`) or `PInCtor` over a singleton
  input-type.
  Date: 2026-05-02


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or
at completion. Compare the result against the original purpose.

**Outcome.** EP-17 landed as designed — pure mechanical deletion.
`HsPred` has seven constructors now (PTop, PBot, PAnd, POr, PNot,
PEq, PInCtor). `matchCmd` is no longer exported. The SBV
`translatePred` handles the surviving constructors exhaustively and
has no predicate-level fallback. The composition substitution
helpers (`weakenLPred`, `substPred`) are exhaustive with no
defensive errors.

**Acceptance gates met.**

- `cabal build && cabal test all` green (107/107, GHC 9.12.3).
- `grep "PMatchC\|matchCmd" src/Keiki/Core.hs src/Keiki/Symbolic.hs
  src/Keiki/Composition.hs` returns empty.
- `Keiki.Symbolic.translatePred` no longer has a `PMatchC` clause
  and its Haddock no longer enumerates `PMatchC`.
- Importing `matchCmd` from `Keiki.Core` is a compile error.
- Constructing a `PMatchC` value is a compile error.
- The retirement-block comments in `Keiki.Core` and
  `dsl-shape-for-symbolic-register.md` no longer mention `PMatchC`.

**Test count delta.** 108 → 107 (M0 → M7). Exactly one case removed
as planned: the "PMatchC dispatches to the carried predicate"
assertion in the `evalPred` describe block. No other test cases
were affected. The symbolic gates
(`isSingleValuedSym (withSymPred userReg) == True`, `symSatExt`
round-trips) continue to pass — they were already structural
through `PInCtor` since EP-2 of MP-2.

**Lessons for EP-18.**

- The retirement-block comments in `Keiki.Core` and
  `dsl-shape-for-symbolic-register.md` now contain only the
  `unsafeCombine` bullet. EP-18's M9 (IP-5 sweep) removes the entire
  block in both files.
- EP-17's M5 design-note rewrite preserved historical EP-2 context
  as a "Historical: ..." subsection rather than deleting it. EP-18
  may face a similar choice with the `unsafeCombine` static-check
  rationale in `dsl-shape-for-symbolic-register.md`'s section 8 —
  preserve, don't delete, the design rationale.


## Context and Orientation

A reader picking up this plan needs:

- **The keiki pure core** lives in `src/Keiki/Core.hs`. The type
  directly affected:

  - `HsPred (rs :: [Slot]) (ci :: Type)` — the predicate AST,
    declared at lines 351-367. As of master, the constructors are
    `PTop`, `PBot`, `PAnd`, `POr`, `PNot`, `PEq`, `PInCtor`, and
    `PMatchC` (the opaque escape hatch this plan retires). After this
    plan lands, `HsPred` no longer has `PMatchC`.

- **The helper functions** affected:

  - `matchCmd :: (ci -> Bool) -> HsPred rs ci` at line 426 — wraps
    `PMatchC`. Removed by this plan.
  - `matchInCtor :: InCtor ci ifs -> HsPred rs ci` at line 438 —
    wraps `PInCtor`. Stays.
  - `(.==) :: Term rs ci r -> Term rs ci r -> HsPred rs ci` at line
    466 — sugar over `PEq`. Stays.

- **The evaluator clause**:

  - `evalPred :: HsPred rs ci -> RegFile rs -> ci -> Bool` at line
    around 524. The `PMatchC` clause is `evalPred (PMatchC f) _ c =
    f c`. Removed by this plan.

- **The symbolic layer** at `src/Keiki/Symbolic.hs`. The function
  `translatePred` (lines ~275-296) translates an `HsPred` to an SBV
  `SBool`. The `PMatchC` clause is

      go (PMatchC _) = SBV.free "pmatchc"

  at line 287. Removed by this plan. The Haddock at lines 273-274
  explaining the fallback is also removed.

  The symbolic layer also has a pair of comments at lines 273 and
  515 referring to `PMatchC` as a translation-refusal point. Both
  are removed by this plan.

- **The composition module** at `src/Keiki/Composition.hs`. Two
  clauses reference `PMatchC`:

  - `weakenLPred` at line 137: `weakenLPred (PMatchC f) = PMatchC f`
    (passes through unchanged across an `rs2` weakening).
  - `substPred` at lines 264-269: `substPred (PMatchC _) _o1 =
    error "..."` (composition refuses to substitute through an
    opaque guard over the mid type).

  Both clauses become statically impossible once `PMatchC` is gone
  (GHC narrows the GADT match), so they are deleted.

- **The test file** `test/Keiki/CoreSpec.hs` contains:

  - Line 36: a synthetic transducer using `matchCmd id :: HsPred '[]
    Bool` as one edge's guard.
  - Lines 91-92: a "PMatchC dispatches to the carried predicate"
    describe / it block: `evalPred (matchCmd id :: HsPred '[] Bool)
    RNil True \`shouldBe\` True`.

- **The retirement-block comment** in `src/Keiki/Core.hs:22-33` and
  the corresponding block in
  `docs/research/dsl-shape-for-symbolic-register.md` (lines
  1001-1015) enumerate the v1 escape hatches still owned by MP-6.
  After this plan, the PMatchC bullet is removed; the unsafeCombine
  bullet remains (and the OFn bullet is gone if EP-16 has landed
  first; otherwise it remains until EP-16 lands). The whole block is
  removed by EP-18 (the last retirement) per MP-6's IP-5.

- **The SBV design note** at `docs/research/sbv-boolalg-design.md`
  has substantial commentary on the PMatchC-fallback decision (lines
  205, 273-289 documenting the fallback to a fresh `SBool`; lines
  315-331 the load-bearing-decision section; lines 599-612 the
  "future work" enumeration). After this plan, those sections are
  rewritten to reflect that the fallback is gone (because the
  constructor is gone). A small "Retired by EP-17 of MP-6" note is
  added pointing forward.

- **The User Registration aggregates** at
  `src/Keiki/Examples/UserRegistration.hs` and
  `src/Keiki/Examples/UserRegistrationV0.hs` were already migrated
  to `matchInCtor` in EP-2 of MP-2 (see V0's line-89 comment). Their
  guards are `isStart = matchInCtor inCtorStart` (and the rest of
  the `isFoo = matchInCtor inCtorFoo` set), `PEq` for confirmation
  code equality, `PAnd` for joint guards. Nothing in either
  aggregate references `PMatchC` or `matchCmd`. No aggregate
  changes are required by this plan.

Terms of art used in this plan:

- **Escape hatch.** A constructor in the pure-core DSL that holds
  an opaque Haskell value. Defeats structural analyses.
- **SBV.** *Symbolic Bit Vectors*, a Haskell library that translates
  symbolic Haskell expressions to SMT and runs a backend solver
  (z3). `Keiki.Symbolic` uses SBV to decide
  satisfiability/single-valuedness of guard predicates.
- **GADT narrowing.** GHC's pattern-match coverage check eliminates
  case clauses for constructors that have been removed from a GADT.
  After this plan removes `PMatchC`, any `PMatchC _ -> ...` clause
  becomes unreachable.


## Plan of Work

The work is one cohesive change but split into milestones so the
intermediate states compile.

### M0 — Prerequisites

Verify the working tree builds and tests pass:

    cabal build
    cabal test all

Acceptance: 107 examples, 0 failures (matches EP-15's M0 baseline,
or 107 minus EP-16's removed cases if EP-16 has landed first).

This milestone produces no source-tree changes.

### M1 — Remove `PMatchC` and `matchCmd` from `Keiki.Core`

Edit `src/Keiki/Core.hs`:

1. **Export list** (around line 65): remove the `, matchCmd` line.
   The `, matchInCtor` line stays (one line below it).
2. **`HsPred` constructor** (lines 366-367): remove the `PMatchC ::
   (ci -> Bool) -> HsPred rs ci` clause along with its Haddock
   comment ("v1 escape hatch: opaque predicate over the input
   symbol"). Clean up trailing comma. Also revise the Haddock at the
   `PInCtor` line (lines 359-365) — the comment currently says
   "the opaque-function alternative ('PMatchC') stays for back-compat"
   and points at `docs/research/sbv-boolalg-design.md`. Drop the
   reference to `PMatchC` and the back-compat note; keep the
   structural-rationale.
3. **`matchCmd` helper** (lines 423-427): remove the helper, its
   signature, and its Haddock comment.
4. **`matchInCtor` helper Haddock** (lines 430-439): the comment
   currently says "Added in EP-2 of MasterPlan 2 as a structural
   alternative to 'matchCmd'/'PMatchC'..." and "the v1 'matchCmd'
   escape hatch stays available for users who want to opt out of
   structural recognition." Drop the back-compat sentence; keep the
   semantics statement.
5. **`evalPred`** (line ~524): remove the `evalPred (PMatchC f) _
   c = f c` clause.

After this milestone:

    cabal build keiki:lib

Expected: success. The library no longer exports `matchCmd` and the
`HsPred` GADT no longer has a `PMatchC` constructor. The
`Keiki.Symbolic` and `Keiki.Composition` modules will fail to
compile because they reference `PMatchC`; that's M2 and M3's work.

### M2 — Remove `PMatchC` from `Keiki.Symbolic`

Edit `src/Keiki/Symbolic.hs`:

1. **`translatePred` clause** at line 287: remove `go (PMatchC _) =
   SBV.free "pmatchc"`. The remaining `PTop`, `PBot`, `PAnd`, `POr`,
   `PNot`, `PEq`, `PInCtor` clauses cover the `HsPred` GADT
   exhaustively.
2. **Haddock for `translatePred`** (lines 273-274): remove the
   bullet *"`'PMatchC'` (the v1 escape hatch) emits a fresh `'SBool'`:
   the opaque Haskell function is unanalyzable."* The bullet list at
   lines 261-274 enumerates the constructors; after this plan there
   are seven constructors and seven bullets.
3. **Haddock at line 515** (the function's escape-hatch enumeration):
   the comment says *"2. /Escape-hatch terms/ ('TApp1', 'TApp2',
   'PMatchC', and 'PEq' over types not in the SBV-supported
   whitelist)"*. Drop the `'PMatchC'` reference; keep the rest.

After this milestone:

    cabal build keiki:lib

Expected: success.

### M3 — Remove `PMatchC` from `Keiki.Composition`

Edit `src/Keiki/Composition.hs`:

1. **`weakenLPred`** at line 137: remove the `weakenLPred (PMatchC
   f) = PMatchC f` clause.
2. **`substPred`** at lines 264-269: remove the `substPred (PMatchC
   _) _o1 = error "..."` clause along with its multi-line error
   message string.

After this milestone:

    cabal build keiki:lib

Expected: success with no `-Wincomplete-patterns` warnings.

### M4 — Rewrite `test/Keiki/CoreSpec.hs`

Edit `test/Keiki/CoreSpec.hs`:

1. **Synthetic transducer fixture** (line ~36): replace `matchCmd
   id` (which produced a guard that was true iff the input `Bool` was
   `True`) with a structural equivalent. Two reasonable
   replacements:

   - `PEq (proj (#flag :: Index '[ '("flag", Bool)] Bool)) (TLit
     True)` — but this requires the synthetic fixture's `rs` slot
     list to include a `flag` slot.
   - Simpler: change the synthetic transducer's input type from
     `Bool` to a singleton sum type like `data Tick = Tick`, define a
     local `inCtorTick :: InCtor Tick '[]`, and use `matchInCtor
     inCtorTick` as the guard (always true on a singleton input).
     The existing test `evalPred isStart RNil StartRegistration{}`
     style in `test/Keiki/Examples/` provides the worked example.

   Pick whichever fits the existing fixture's input type with the
   least churn. Record the choice in the Decision Log.

2. **"PMatchC dispatches to the carried predicate" describe / it
   block** (lines 91-92): delete it.

After this milestone:

    cabal test keiki:keiki-test 2>&1 | tail -20

Expected: green. Test count drops by exactly 1 (the
`PMatchC dispatches` case) — confirm in Surprises & Discoveries.

### M5 — Update `docs/research/sbv-boolalg-design.md`

Edit `docs/research/sbv-boolalg-design.md`:

1. **PMatchC fallback section** (lines ~205, ~273-289): rewrite to
   record that the fallback is gone because `PMatchC` was retired by
   EP-17 of MP-6 (this plan). The historical context — that the
   fallback existed and why — is preserved as a paragraph headed
   *"Historical: the PMatchC fallback (retired 2026-05-XX)"*. The
   forward-looking statements (e.g. "PMatchC stays in the language
   as a v1-grandfathered escape hatch") are deleted because they are
   no longer true.
2. **Future-work enumeration** (lines ~599-612): remove the
   "PMatchC retirement (opaque guard) — partially addressed by
   adding `PInCtor`, but the `PMatchC` constructor stays for
   back-compat" bullet. The OFn and unsafeCombine bullets stay (or
   are also revised if EP-16 / EP-18 are landing in parallel).

This is documentation-only; no source changes.

### M6 — Tick the retirement-block comments

Edit `src/Keiki/Core.hs:22-33`. Remove the PMatchC bullet (the
three-line entry starting `* 'PMatchC' carries an opaque...`). Keep
the block header and the unsafeCombine bullet (and OFn if EP-16 has
not landed).

Edit `docs/research/dsl-shape-for-symbolic-register.md:1001-1015`.
Remove the PMatchC bullet (the four-line entry starting `*
\`PMatchC\` (replace with...`). Keep the surrounding block.

This is comment / prose only.

### M7 — Verdict

Run the full test suite:

    cabal build
    cabal test all

Acceptance:

- All examples pass (count is M0's baseline minus 1 — the
  PMatchC-dispatch case removed in M4).
- `Keiki.Core` no longer exports `matchCmd` or the `PMatchC`
  constructor (verify with `grep -n "PMatchC\|matchCmd" src/Keiki/Core.hs`
  returning empty or only Haddock-prose mentions intentionally
  preserved).
- `src/Keiki/Symbolic.hs` no longer contains the `PMatchC` clause
  (verify with `grep -n "PMatchC" src/Keiki/Symbolic.hs` returning
  only the historical SBV-design-note pointer if any).
- `src/Keiki/Composition.hs` no longer contains the two `PMatchC`
  clauses.

Commit the work. Update MP-6's Exec-Plan Registry to mark this plan
**Complete**. Write the Outcomes & Retrospective entry.


## Concrete Steps

Run from the repository root.

M0:

    cabal build
    cabal test all

M1 — surface check after editing `Keiki.Core`:

    cabal build keiki:lib

M2 — surface check after editing `Keiki.Symbolic`:

    cabal build keiki:lib

M3 — surface check after editing `Keiki.Composition`:

    cabal build keiki:lib

M4 — exercise the rewritten test file:

    cabal test keiki:keiki-test 2>&1 | tail -20

M7 — final acceptance:

    cabal build
    cabal test all
    grep -n "PMatchC\|matchCmd" src/Keiki/Core.hs src/Keiki/Symbolic.hs src/Keiki/Composition.hs

Commit (with `MasterPlan:`, `ExecPlan:`, and `Intention:` trailers
per the master-plan / exec-plan skill protocols).


## Validation and Acceptance

After M7, the user should observe:

- `cabal build` produces no warnings related to PMatchC.
- `cabal test all` is green; the test count is M0's baseline minus 1.
- `grep` confirms no remaining `PMatchC` or `matchCmd` references in
  the named source files (or only intentional doc-pointer references).
- `Keiki.Symbolic`'s `translatePred` no longer has a `PMatchC` clause
  and its Haddock no longer enumerates `PMatchC` as a translation case.
- The MP-6 retirement-block comments in `Keiki.Core` and
  `dsl-shape-for-symbolic-register.md` no longer mention `PMatchC`.
- A user attempting to import `matchCmd` from `Keiki.Core` gets a
  compile error: *"Module 'Keiki.Core' does not export 'matchCmd'"*.
- A user attempting to construct a `PMatchC` value gets a compile
  error: *"Data constructor not in scope: 'PMatchC'"*.

The behavioural acceptance — that no aggregate's behaviour changes —
is implicit because no aggregate uses `PMatchC`. The symbolic gates
(`isSingleValuedSym (withSymPred userReg) == True`) continue to pass
because they were already structural.


## Idempotence and Recovery

Each milestone is independently re-runnable. M5's documentation
edits to `sbv-boolalg-design.md` are subjective in style; if a later
reviewer prefers a different framing, edit and re-commit — no
behavioural impact.

If a milestone fails:

- M1 / M2 / M3 source edits: `git diff` shows the partial state.
  Either finish or `git checkout -- <file>` and retry.
- M4 test rewrite: if the structural replacement guard fails to
  match the intended truth-table, switch to `PEq (TLit True) (TLit
  True)` (always true; type-trivial) for the synthetic case.

There is no destructive-operation hazard.


## Interfaces and Dependencies

After this plan, the following must hold:

- `Keiki.Core` exports do **not** include `matchCmd`.
- `HsPred` has exactly seven constructors: `PTop`, `PBot`, `PAnd`,
  `POr`, `PNot`, `PEq`, `PInCtor`.
- `evalPred` has one fewer clause than at the start of the plan.
- `Keiki.Symbolic.translatePred` handles seven `HsPred` constructors
  exhaustively; no `PMatchC` fallback.
- `Keiki.Composition.weakenLPred` and `substPred` handle seven
  `HsPred` constructors exhaustively; no `PMatchC` clauses.
- `test/Keiki/CoreSpec.hs`'s synthetic transducer uses a structural
  guard (e.g. `matchInCtor`).

Soft dependencies:

- **EP-15** (`docs/plans/14-design-milestone-decompose-v1-escape-hatch-retirements-ofn-pmatchc-unsafecombine-static-check.md`)
  — its design note at
  `docs/research/v1-escape-hatch-retirements-design.md` is the
  rationale for "remove outright".
- **EP-16 and EP-18** (sibling retirement EPs) — independently
  mergeable. Conventional order is EP-16 → EP-17 → EP-18 because the
  module-header retirement-block cleanup is cleanest when EP-18 (last)
  removes the whole block. EP-17 only ticks its own bullet.

No hard dependencies; no external library bumps; no GHC version
constraints beyond the existing GHC 9.12.3 baseline.
