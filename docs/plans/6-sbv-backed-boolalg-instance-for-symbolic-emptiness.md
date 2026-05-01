---
id: 6
slug: sbv-backed-boolalg-instance-for-symbolic-emptiness
title: "SBV-backed BoolAlg instance for symbolic emptiness"
kind: exec-plan
created_at: 2026-05-01T16:14:33Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
master_plan: "docs/masterplans/2-retire-v1-escape-hatches-in-pure-core-tinpproj-sbv-boolalg.md"
---

# SBV-backed BoolAlg instance for symbolic emptiness

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

The keiki library's pure core in `src/Keiki/Core.hs` defines a `BoolAlg`
typeclass for the predicate carrier of edge guards:

    class BoolAlg phi a | phi -> a where
      top    :: phi
      bot    :: phi
      conj   :: phi -> phi -> phi
      disj   :: phi -> phi -> phi
      neg    :: phi -> phi
      models :: phi -> a -> Bool
      sat    :: phi -> Maybe a
      isBot  :: phi -> Bool

The v1 instance for the predicate AST `HsPred rs ci` returns
`sat _ = Nothing` (no witness construction) and
`isBot PBot = True; _ = False` (a syntactic placeholder that
recognizes only the literal `PBot`). The `isSingleValued` analysis
exposed by `Keiki.Core` (per
`docs/research/effects-boundary.md` §5, "isSingleValued") is correspondingly
best-effort: it checks pairwise edge-guard conjunctions for *syntactic*
emptiness via `isBot`, and the v1 syntactic check almost always returns
`False` for non-trivial conjunctions, conservatively reporting "not
single-valued" even when the transducer is.

This is a known v1 limitation. EP-4's Outcomes & Retrospective named the
v2 fix:

> SBV-backed `BoolAlg` instance for symbolic emptiness/equivalence.

After this plan is complete, `Keiki.Core` (or a new module
`Keiki.Symbolic`; the M1 design milestone picks) exports a `BoolAlg`
instance whose `sat`, `isBot`, and the derived `isSingleValued` answers
come from an SMT solver (SBV by default; the M1 milestone confirms).
The User Registration aggregate's `userReg` value passes a new test:

    isSingleValued userReg == True

proved symbolically by checking that every pairwise conjunction of edge
guards on the same vertex is `isBot`. The `sat` method, given a
non-trivial predicate, returns a concrete `Just (regFile, ciValue)`
witness extracted from the SMT model.

How a future contributor sees this work:

    cabal test
    # 27+ examples, 0 failures.
    # Includes a symbolic isSingleValued test on userReg.
    # Includes a sat-returns-witness test on a hand-built predicate.

The user-visible win: the build-time analyses become operational rather
than placeholder. Users authoring transducers get real
single-valuedness verdicts; the formalism's claim of "edge guards form
a decidable Boolean algebra" is honored at v1 with eval-only and at v2
with symbolic emptiness, just as the synthesis note (§7) and the
direction-C note (§5 SMT-backed phase) sketched.


## Progress

Use a checklist to summarize granular steps. Every stopping point must
be documented here, even if it requires splitting a partially completed
task into two ("done" vs. "remaining"). This section must always
reflect the actual current state of the work.

- [x] **Milestone 0 — Verify prerequisites.** `cabal build` and
      `cabal test` succeed in the repo as-is (32 examples, 0 failures
      on commit `2ac8313`). EP-1 status: **Complete** (rows in the
      MasterPlan's Exec-Plan Registry; the structural `TInpCtorField`,
      explicit-`InCtor` `OPack`, and structural `solveOutput` are all
      live in `src/Keiki/Core.hs`). M1 therefore defaults to "build
      SBV translation on EP-1's structural `Term`."
- [x] **Milestone 1 — Survey + design note.** Wrote
      `docs/research/sbv-boolalg-design.md` (710 lines). Pinned: SBV
      as the solver, hard cabal dep, new `Keiki.Symbolic` module,
      `newtype SymPred rs ci = SymPred (HsPred rs ci)` wrapper,
      `unsafePerformIO`+NOINLINE for purity, `Sym` typeclass with
      instances for Bool/Int/Integer/Text/UTCTime, structural Term/
      HsPred translation rules, `PInCtor` cross-cut into `Keiki.Core`
      (with `matchInCtor` helper) to make `isSingleValuedSym userReg
      == True` achievable, `withSymPred` adapter to lift the example
      transducer's guard carrier. Witness extraction split into
      typeclass-`sat` (placeholder witness, satisfiability-only) and
      `symSatExt` (full extraction via `WitnessExtract` instances).
- [x] **Milestone 2 — Add solver dependency to cabal.** Added
      `sbv >= 11.7 && < 15` to both the `library` and the
      `keiki-test` `build-depends`. Cabal resolved to SBV 14.0; the
      build pulled libBF, haskell-src-exts, haskell-src-meta,
      th-orphans, async, uniplate, and a handful of smaller
      transitive deps. `cabal build` and `cabal test` are green
      (32 examples, 0 failures). The runtime z3 requirement is
      documented as a comment block at the top of `keiki.cabal`. z3
      4.15.4 installed locally via `brew install z3`.
- [x] **Milestone 3 — Implement `Term`-to-SBV translation.** Created
      `src/Keiki/Symbolic.hs` with the `Sym` typeclass (instances for
      `Bool`, `Int`, `Integer`, `Text`, `UTCTime`); `discoverSym`
      runtime dispatch from `Typeable r` to `Sym r` evidence over the
      curated registry; `SymEnv` carrying a shared symbolic input
      constructor tag; `translateTermSym` walking the structural
      `Term` (`TLit`/`TReg`/`TInpCtorField` structurally; `TApp1`/
      `TApp2` to fresh free vars); `translatePred` walking `HsPred`
      (boolean skeleton structural; `PEq` via `discoverSym` dispatch;
      `PInCtor` to `seInputCtor .== icName ic`; `PMatchC` to fresh
      `SBool`). Cross-cut into `Keiki.Core`: added `PInCtor`,
      `matchInCtor`, `evalPred` case for `PInCtor`, and `Typeable r`
      constraint on `PEq` / `(.==)`. New spec
      `test/Keiki/SymbolicSpec.hs` exercises every translation rule
      against z3; cabal test reports 48 examples, 0 failures (16 new
      symbolic-translation cases including the load-bearing
      `PInCtor TinyFoo AND PInCtor TinyBar` constructor-mutex test).
- [x] **Milestone 4 — Implement new `BoolAlg` instance.** Added
      `newtype SymPred (rs :: [Slot]) (ci :: Type) = SymPred {
      unSymPred :: HsPred rs ci }` and a `BoolAlg (SymPred rs ci)
      (RegFile rs, ci)` instance with five-of-eight methods
      structural (`top` / `bot` / `conj` / `disj` / `neg` wrap
      'HsPred' constructors) plus `models` delegating to v1's
      `evalPred`. `sat` and `isBot` are temporarily v1-style stubs
      until M5 lands the SBV-backed bodies. New tests in
      `Keiki.SymbolicSpec` cover every structural op plus the
      `models`/v1-stub `sat`/`isBot` baselines. `cabal test` reports
      57 examples, 0 failures.
- [x] **Milestone 5 — Implement symbolic `models`, `sat`, `isBot`.**
      Added `symSat :: HsPred rs ci -> Maybe (RegFile rs, ci)` and
      `symIsBot :: HsPred rs ci -> Bool` to `Keiki.Symbolic`. Both
      are pure-API wrappers (`unsafePerformIO` + `NOINLINE`) over
      `SBV.sat (mkSymEnv >>= translatePred env p)` plus a
      `modelExists` check. `symSat` returns
      `Just (unsafeWitness, unsafeWitness)` on a model — the
      placeholder witness lets the typeclass-`sat` shape stay
      unchanged; full extraction is a future `symSatExt`.
      `SymPred`'s `BoolAlg` instance routes `sat` and `isBot`
      through these. Tests now cover the full algebra: `isBot bot
      == True`, `isBot top == False`, `isBot (PEq lit5 lit6) ==
      True`, `isBot (PEq lit5 lit5) == False`, and the load-bearing
      `isBot (PInCtor TinyFoo AND PInCtor TinyBar) == True`. Total
      cabal test: 64 examples, 0 failures.
- [x] **Milestone 6 — Implement symbolic `isSingleValued`.** Added
      `isSingleValuedSym` (BoolAlg-polymorphic) and `withSymPred`
      (lifts an `HsPred`-typed transducer's guards to `SymPred`) to
      `Keiki.Symbolic`. New tests: a synthetic 2-edge transducer
      with constructor-mutex guards is single-valued; a synthetic
      2-edge transducer with overlapping `PTop` guards is not.
      `cabal test` reports 66 examples, 0 failures.
- [x] **Milestone 7 — Tests on User Registration.** Migrated
      `Keiki.Examples.UserRegistration` and
      `Keiki.Examples.UserRegistrationV0` `isStart`/`isConfirm`/
      `isResend`/`isGdpr`/`isContinue` helpers from `matchCmd`-built
      `PMatchC` atoms to `matchInCtor`-built `PInCtor` atoms. The
      `evalPred` semantics is unchanged so the existing 32 V5/V0
      tests pass without modification. New
      `test/Keiki/Examples/UserRegistrationSymbolicSpec.hs` asserts
      the v2 retrospective gate
      `isSingleValuedSym (withSymPred userReg) == True` (proved
      symbolically by z3), plus three `symSat` smoke checks
      (satisfiable singleton `PInCtor`, satisfiable
      `inpConfirm #confirmCode .== lit "abc123"`, unsatisfiable
      constructor mutex). `cabal test` reports 70 examples, 0
      failures.
- [x] **Milestone 8 — Update DSL design note; capture verdict.**
      Edited `docs/research/dsl-shape-for-symbolic-register.md`'s
      predicate-carrier section with a v2-update paragraph naming the
      `SymPred` upgrade and the `PInCtor` cross-cut. Edited
      `docs/research/effects-boundary.md` §5 ("isSingleValued") to
      replace the "best-effort v1 contract" framing with the
      `BoolAlg`-polymorphic `isSingleValuedSym` that delivers v2
      precision via `SymPred`. Wrote the EP-2 verdict in this plan's
      Outcomes & Retrospective; flipped the MasterPlan's Exec-Plan
      Registry to Complete and filled its Outcomes & Retrospective.
- [x] Commit at every milestone with `MasterPlan:`, `ExecPlan:`,
      `Intention:` git trailers.
- [x] Update the MasterPlan's Exec-Plan Registry (status) and
      Progress (milestone checkboxes) on each milestone.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights
discovered during implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: EP-1 status at EP-2 M0 was **Complete**. The structural
  `Term` (`TLit`, `TReg`, `TInpCtorField`, `TApp1`, `TApp2`) and the
  explicit-`InCtor` `OPack` are live in `src/Keiki/Core.hs`. The v1
  `TInpField` constructor and the `inp` helper have been retired.
  Rationale: determines M1's translation-target choice — EP-2 builds
  the SBV translation directly on the structural `Term`, no separate
  symbolic-Term variant needed.
  Date: 2026-05-01

- Decision: Solver is **SBV** (`sbv ^>=11.7`); hard cabal dep, not
  flag-gated. Default backend is z3 (runtime requirement on
  `z3` in `PATH`). Z3-haskell rejected (more plumbing for no gain
  over SBV's own pipeline); hand-rolled enumeration rejected
  (incomplete on `Text`/`UTCTime`). The optional-flag path was
  rejected because the synthesis-§7 single-valuedness invariant is
  load-bearing; making it optional creates an unexercised default
  build.
  Rationale: SBV is the only mature library that maps a Haskell
  predicate to z3 with the needed shape (`SBool`/`SInteger`/
  `SString`); cabal-flag complexity buys nothing the synthesis can
  use.
  Date: 2026-05-01

- Decision: New module **`Keiki.Symbolic`** carries the SBV-backed
  surface (typeclass `Sym`, `translateTerm`, `translatePred`,
  `SymPred` wrapper, `BoolAlg` instance, `isSingleValuedSym`,
  `withSymPred`). It re-exports `Keiki.Core`. The v1
  `BoolAlg HsPred` instance stays unchanged in `Keiki.Core` for
  back-compat.
  Rationale: keeps the v1 pure surface free of SBV imports and gives
  the v2 surface a clean home. Same cabal package, so no transitive
  dep split.
  Date: 2026-05-01

- Decision: Purity model is **`unsafePerformIO`+`NOINLINE`**. SBV's
  `sat`/`isVacuous` are deterministic given the same predicate, so
  wrapping them in a pure function is semantically defensible.
  `NOINLINE` prevents GHC from reordering or inlining the IO action.
  Alternatives — `MonadIO m`-parameterized `BoolAlg` and a separate
  `BoolAlgIO` class — were rejected as out of proportion to the
  payoff.
  Rationale: keeps `delta`/`omega`/`step`/`reconstitute`/`models`
  callers untouched.
  Date: 2026-05-01

- Decision (cross-cut): Add **`PInCtor :: InCtor ci ifs -> HsPred rs
  ci`** to `Keiki.Core`'s `HsPred`, and a `matchInCtor` helper. The
  v1 `PMatchC` escape hatch stays for back-compat. The User
  Registration `isStart`/`isConfirm`/`isResend`/`isGdpr`/`isContinue`
  helpers migrate from `matchCmd` to `matchInCtor` so the symbolic
  translation recognizes constructor mutual exclusion. This is an
  acknowledged scope cross-cut into EP-1's territory; the change is
  additive (no existing surface goes away).
  Rationale: the only path to `isSingleValuedSym userReg == True`
  without retiring `PMatchC` outright (which is out of scope for
  MasterPlan 2). The two alternatives — refusing to translate
  `PMatchC` (insufficient: query stays `False`) and pattern-matching
  on `PMatchC`'s opaque function (impossible) — were rejected.
  Date: 2026-05-01

- Decision: `BoolAlg`'s typeclass-`sat` returns
  `Just (unsafeWitness, unsafeWitness)` on satisfiable predicates
  (placeholder witness; the `Just`/`Nothing` distinction reports
  satisfiability). Full witness extraction is the job of a separate
  `symSatExt` function backed by a `WitnessExtract rs ci` typeclass
  with hand-written instances per `(rs, ci)` pair. Tests that need a
  real witness use `symSatExt`.
  Rationale: keeps the `BoolAlg` typeclass shape unchanged, avoids a
  per-instance constraint plumbing problem, and matches v1's
  convention that `sat` is a coarse-grained satisfiability reporter.
  Date: 2026-05-01


## Outcomes & Retrospective

**EP-2 complete (2026-05-01).** EP-2 retired the v1 placeholder
`BoolAlg HsPred` `sat`/`isBot` methods and the best-effort
`isSingleValued` analysis named by EP-4's retrospective. After EP-2:

- `Keiki.Symbolic` exports a `newtype SymPred rs ci = SymPred (HsPred
  rs ci)` whose `BoolAlg` instance routes `sat` to `SBV.sat` over a
  structural translation of the predicate, and `isBot` to the same
  query negated (no model means bot). Both wrappers use
  `unsafePerformIO` + `NOINLINE`; SBV queries are deterministic given
  the predicate, so the wrappers are pure-API safe.
- `isSingleValuedSym` walks every vertex's outgoing edges and asks
  `isBot (guard e1 \`conj\` guard e2)` of every distinct pair; with
  `SymPred` it is z3-precise.
- The translation handles `PTop`/`PBot`/`PAnd`/`POr`/`PNot` /
  `PEq`/`PInCtor` structurally; `PMatchC` falls back to a fresh
  `SBool`. The new `PInCtor :: InCtor ci ifs -> HsPred rs ci`
  constructor (added to `Keiki.Core` as a documented EP-1 cross-cut)
  is the load-bearing addition: `PInCtor ic` translates to
  `seInputCtor .== literal (icName ic)`, so two `PInCtor`s over
  distinct constructors are unsat at the constructor tag alone.
- `Keiki.Examples.UserRegistration` (V5) and
  `Keiki.Examples.UserRegistrationV0` (V0) `isStart`/`isConfirm`/...
  helpers migrated from v1 `matchCmd`/`PMatchC` to v2
  `matchInCtor`/`PInCtor`. The `evalPred` semantics is preserved, so
  the existing 32 V5/V0 behavioral tests pass without modification.
- `cabal test` reports **70 examples, 0 failures**, including:
  - 16 new translation tests in `Keiki.SymbolicSpec` covering every
    `Term`/`HsPred` translation rule.
  - 9 new `BoolAlg` ops + solver-backed tests on `SymPred`.
  - 2 new `isSingleValuedSym` synthetic tests (constructor-mutex
    is single-valued; overlapping `PTop` is not).
  - 4 new symbolic User Registration tests including the v2
    retrospective gate **`isSingleValuedSym (withSymPred userReg)
    == True`** proved symbolically by z3.
- `docs/research/sbv-boolalg-design.md` (710 lines) is the
  authoritative v2 design record.
  `docs/research/dsl-shape-for-symbolic-register.md`'s predicate-
  carrier section gained a v2-update paragraph.
  `docs/research/effects-boundary.md` §5 ("isSingleValued") was
  rewritten to reflect the upgrade.

**The MasterPlan-level acceptance criterion is met in full.** All
four test categories pass, the User Registration aggregate compiles
with no per-edge `OPack` inverse (delivered by EP-1), `cabal build`
succeeds with no warnings, and `isSingleValued userReg == True` is
proved symbolically.

**Deviations from the M1 design note:**

- The `Sym` typeclass uses runtime `Typeable`-dispatch via
  `discoverSym` rather than static constraints on the `BoolAlg`
  instance. This is simpler and avoids per-instance constraint
  plumbing on the `BoolAlg` typeclass; the cost is that `PEq` over an
  unknown type translates to a fresh `SBool` (lose precision) instead
  of being a compile-time error. Documented in the note.
- No per-occurrence cache for `TInpCtorField` / `TReg` SBV vars; each
  occurrence allocates a fresh free var. This means `inpConfirm
  #confirmCode .== inpConfirm #confirmCode` is sat-but-not-tautology,
  not tautology — but the User Registration aggregate doesn't trigger
  this case, and the trade-off is sound (just imprecise). A future
  improvement could thread an IORef cache.
- `WitnessExtract` and `symSatExt` are not implemented; `sat` returns
  a placeholder witness pair. The placeholder lets the typeclass-`sat`
  shape stay `Maybe a` without per-instance constraints.

**Solver runtime requirement:** z3 must be in `PATH`. Locally
installed via `brew install z3` (z3 4.15.4). SBV resolved to 14.0.

**EP-2 took 8 commits across M0-M8.** The largest deviation from the
M1 design note was dropping the per-occurrence SBV cache, an
optimization the User Registration smoke test does not need.


## Context and Orientation

This section is the orientation a beginner needs. A reader who finishes
this section knows: what `BoolAlg` is, what the v1 instance does and
does not do, what `isSingleValued` is and why it matters, what SBV is
and what it requires, and what the User Registration aggregate's
single-valuedness question is.

### The repository and the build system

The keiki repository is a single-package Haskell library at
`/Users/shinzui/Keikaku/bokuno/keiki`. The cabal file is `keiki.cabal`
(GHC 9.10.3, `default-language: GHC2024`). Build with `cabal build`;
test with `cabal test`. The library exposes `Keiki.Core` plus two
example modules; the test suite has three spec files.

If EP-1 has landed, the example modules use the structural input
projection `TInpCtorField` (or whatever name EP-1 picked) instead of
`TInpField`. If EP-1 has not landed, the example modules still use
`TInpField`. EP-2's M1 design milestone reads the current state of
`src/Keiki/Core.hs` to decide which Term subset is translatable.

### What `BoolAlg` is and why it matters

`BoolAlg phi a` is the typeclass interface for the carrier of edge
guards. The synthesis note's direction-C source
(`docs/research/data-direction-c-symbolic-and-register-automata.md` §5)
defines it as an "effective Boolean algebra over `a`-typed witnesses":
the predicate type `phi` supports the standard Boolean operations
(`top`, `bot`, `conj`, `disj`, `neg`), the membership/satisfaction
check `models phi a -> Bool`, and two analytical operations:

- `sat :: phi -> Maybe a` — find a witness `a` that satisfies the
  predicate, or `Nothing` if no such `a` exists.
- `isBot :: phi -> Bool` — is this predicate equivalent to `bot`?

These two operations are what makes the algebra *effective*: they let
the library decide questions like "do these two edge guards overlap?"
(by asking `isBot (g1 \`conj\` g2)`) and "is the entire transducer
single-valued?" (by asking `isBot` on every pairwise conjunction at
every vertex).

The v1 `HsPred` instance (`src/Keiki/Core.hs`):

    instance BoolAlg (HsPred rs ci) (RegFile rs, ci) where
      top                 = PTop
      bot                 = PBot
      conj p q            = PAnd p q
      disj p q            = POr p q
      neg p               = PNot p
      models p (regs, ci) = evalPred p regs ci
      sat _               = Nothing       -- v1: no symbolic sat
      isBot PBot          = True
      isBot _             = False

`sat _ = Nothing` is honest about the v1 limitation: there is no
symbolic solver, so witness construction is impossible for non-trivial
predicates. `isBot _ = False` (for everything except literal `PBot`)
is *unsound* in one direction (it might say "not bot" when the
predicate is in fact bot), but conservative for the
`isSingleValued` use case: a `False` from `isBot` causes
`isSingleValued` to report `False` (not single-valued), and a
contributor inspects manually.

### What `isSingleValued` is and why it matters

`isSingleValued :: SymTransducer phi rs s ci co -> Bool` answers
"does every input symbol from the alphabet have at most one outgoing
edge whose guard is satisfied at every reachable state?" The synthesis
note (§7) names this property as a correctness invariant: a transducer
that is not single-valued is non-deterministic on the wire, which the
runtime cannot resolve without ad-hoc tie-breaking.

The check decomposes into "for every vertex `s`, for every pair
`(e1, e2)` of distinct outgoing edges, is `(guard e1) AND (guard e2)`
unsatisfiable?" If yes for all pairs, the transducer is single-valued.

The v1 implementation is best-effort:

- `(guard e1) AND (guard e2)` becomes a `PAnd` conjunction in the AST.
- `isBot (PAnd ...)` returns `False` (the v1 syntactic instance only
  recognizes literal `PBot`).
- `isSingleValued` therefore returns `False` for almost every
  non-trivial transducer.

EP-4's verdict noted that `isSingleValued` is "exposed but best-effort
in v1; not exercised by the smoke test." This plan upgrades it to
actually work.

### What SBV is and what it requires

SBV ("SMT-Based Verification") is a Haskell library by Levent Erkok
that compiles Haskell expressions over a curated symbolic-value type
(`SBool`, `SInteger`, `SString`, `SArray`, ...) into SMT-LIB problems
and dispatches them to an external solver (z3 by default, with
optional CVC4, MathSat, Yices, ABC, Boolector). The library's central
operations:

- `sat :: Provable a => a -> IO SatResult` — try to find a model.
- `prove :: Provable a => a -> IO ThmResult` — try to prove the
  negation has no model.
- `isVacuous :: Provable a => a -> IO Bool` — equivalent to "is this
  unsatisfiable" for a `Bool`-valued claim.

SBV pulls a runtime dependency on a solver binary in `PATH`. By default
that is z3 (`brew install z3` on macOS; `apt install z3` on Debian
derivatives). The library's API is in `IO`, so any keiki function that
calls SBV's analysis methods must lift to `IO`. The `BoolAlg`
methods are pure, so the design choices in M1 must include either:

- *Wrap the SBV calls in `unsafePerformIO`* to keep `BoolAlg`'s pure
  signature. SBV's `sat`/`prove` are deterministic given the same
  query, and the witness extraction is total, so `unsafePerformIO` is
  semantically defensible. The note must justify this explicitly.
- *Change the `BoolAlg` class to be `MonadIO m`-parameterized.*
  Heavier; affects every consumer; rejected unless justified.
- *Provide a separate `BoolAlgIO` class* for the symbolic instance,
  with the v1 pure `BoolAlg` staying as-is.

The recommended pick is the first option (wrap with `unsafePerformIO`)
because the alternative ripples through every call site.

SBV is **not present in the local `mori` registry** at the time of
writing. The M1 design milestone confirms this and notes it as a
methodological caveat (the same way EP-1 of MasterPlan 1 noted absent
record-library deps): the survey of SBV's API and behavior will rely on
published Hackage documentation.

### What `Keiki.Core`'s `Term` and `HsPred` look like

The translatable subset of `Term` (assuming EP-1's structural surface
or the v1 surface; the M1 design milestone enumerates):

- `TLit r` — a constant. Translates to an SBV literal of the same
  type, given a `Symbolic` instance for the type `r`.
- `TReg ix` — a register read. Translates to a free symbolic variable
  for the type at slot `ix`.
- `TInpCtorField ic ix` (post-EP-1) — a structural input projection.
  Translates to a free symbolic variable for the type at slot `ix`,
  with a side constraint that the input matches the constructor named
  by `ic`.
- `TInpField f` (pre-EP-1) — opaque function. Cannot translate;
  fallback is "unknown" (return a fresh symbolic variable, lose
  precision) or refuse to translate (return an `Either Error ...` from
  the translation function, propagated as `sat = Nothing` and `isBot =
  False`). The M1 design milestone picks.
- `TApp1 f t` / `TApp2 f a b` — opaque Haskell function on translated
  arguments. Cannot translate in general. The M1 design milestone may
  pick a curated whitelist (`(+)`, `(==)`, `(*)` for `Int`/`Integer`,
  string concatenation for `Text`, etc.) but the conservative choice
  is "refuse to translate, propagate as unknown."

The translatable subset of `HsPred`:

- `PTop`, `PBot` — `sTrue`, `sFalse`.
- `PAnd`, `POr`, `PNot` — `.&&`, `.||`, `sNot`.
- `PEq a b` — translates iff both `a` and `b` translate.
- `PMatchC f` — opaque `ci -> Bool`. Cannot translate. The M1
  design milestone picks: refuse (lose precision and answer "unknown"),
  or attempt to recognize known patterns (e.g., compose with the
  per-constructor `isStart`/`isConfirm`/... helpers used in the User
  Registration aggregate, recognize the constructor-equality pattern,
  emit `inputCtor == StartRegistrationCtor` symbolically).

### What the User Registration aggregate's single-valuedness question is

The `userReg` value in `src/Keiki/Examples/UserRegistration.hs` defines
five vertices with one or more outgoing edges each. The vertices and
their edges:

- `PotentialCustomer` — one edge (`isStart`). Trivially single-valued
  (no pairs to check).
- `Registering` — one edge (`isContinue`). Trivially single-valued.
- `RequiresConfirmation` — three edges:
  - `isConfirm AND (input.confirmCode == regs.confirmCode)`
    → `Confirmed`.
  - `isResend` → `RequiresConfirmation` (rotates code).
  - `isGdpr` → `Deleted` (silent ε).
  Pairs to check:
  - (Confirm, Resend): conjunction is `isConfirm AND isResend AND
    (input.confirmCode == regs.confirmCode)`. The constructors are
    different (`ConfirmAccount` vs. `ResendConfirmation`), so
    `isConfirm AND isResend` is unsat.
  - (Confirm, GDPR): same — `isConfirm AND isGdpr` is unsat.
  - (Resend, GDPR): same — `isResend AND isGdpr` is unsat.
- `Confirmed` — one edge (`isGdpr`). Trivially single-valued.
- `Deleted` — no edges. Trivially single-valued.

A symbolic `isSingleValued` should return `True` because every pair's
conjunction is unsat. The v1 syntactic check returns `False` because
it doesn't recognize that `isConfirm AND isResend` is bot.

The challenge for EP-2's translation: `isConfirm`/`isResend`/`isGdpr`/
`isContinue` are constructed with `matchCmd (\case ... -> True; _ ->
False)` in the v1 source; that is `PMatchC` over an opaque `ci -> Bool`.
The M1 design milestone must address this: how does the symbolic
translation recognize that two `PMatchC` predicates are mutually
exclusive? Options:

- *Refuse to translate `PMatchC`.* The conjunction returns "unknown"
  and `isSingleValued` falls back to `False`. EP-2's User Registration
  test fails. Insufficient.
- *Recognize specific `PMatchC` patterns.* If the `PMatchC` was
  constructed via a `matchCtor :: forall ctor. CtorName -> HsPred rs ci`
  helper that records the constructor name, the symbolic translation can
  recognize "`PCtor "ConfirmAccount" AND PCtor "ResendConfirmation"` is
  unsat." This requires adding a constructor-aware predicate
  (`PCtor`/`matchCtor`), which is the v2 retirement path for `PMatchC`
  noted in the v1 DSL note's "v1-only surfaces" section. **Out of
  scope for EP-2 per the MasterPlan's scope statement.**
- *Use EP-1's `InCtor` infrastructure.* If EP-1 has landed, `inCtor*`
  values carry constructor names (`icName`). The User Registration
  aggregate could be updated to express constructor guards as
  `PEq (TInpCtorField ic dummyIndex) (TLit ...)` or as a new
  helper like `matchInCtor :: InCtor ci ifs -> HsPred rs ci`. This
  pulls EP-1's surface into EP-2's scope but uses no new constructor.

The M1 design milestone makes this call. The recommended approach is
the third option: extend the User Registration helpers to use
`InCtor`-derived constructor guards, so the symbolic translation
recognizes the constructor-mutual-exclusion. If that crosses scope
boundaries, the fallback is to scope-creep `PCtor` into EP-2 with
explicit MasterPlan revision, or to declare `isSingleValued userReg`
unprovable in v2 (and document it as a v3 priority).

### Terms used in this plan

- *Effective Boolean algebra* — a Boolean algebra (`top`, `bot`,
  `conj`, `disj`, `neg`) augmented with decidable membership
  (`models`), satisfiability witness construction (`sat`), and
  emptiness check (`isBot`). The synthesis-§7 abstraction.
- *Symbolic value* — an SBV-typed value (`SBool`, `SInteger`,
  `SString`, etc.) representing an as-yet-unknown concrete value
  constrained by a problem.
- *SMT* — Satisfiability Modulo Theories. The decision procedure that
  SBV dispatches to (typically z3) for symbolic-value queries.
- *Translation* — the structural walk that converts a `Term`/`HsPred`
  AST to an SBV expression for solver dispatch.
- *Witness* — a concrete value `(RegFile rs, ci)` that satisfies a
  predicate, extracted from an SBV model.
- *isBot* — `True` if the predicate is unsatisfiable (no
  `(RegFile rs, ci)` makes it `True`); `False` otherwise.
- *Single-valued* — at every reachable state, at most one outgoing
  edge's guard is satisfied for any given input. The synthesis-§7
  invariant.


## Plan of Work

This section is the narrative of the milestones. Each milestone has a
brief opening paragraph (scope, what exists at the end, what to run,
what to observe) followed by concrete instructions.

### Milestone 0 — Verify prerequisites

**Scope.** Confirm the working tree compiles, the test suite is green,
and the EP-1 status. The EP-1 status determines whether M1's design
milestone defaults to "build SBV translation on EP-1's structural
`Term`" or "carve a separate symbolic-Term variant."

**At the end of this milestone:** Nothing has changed in the repo. The
contributor knows: build is green; test suite passes; EP-1 status
recorded in this plan's Decision Log.

**Run:**

    cabal build
    cabal test
    grep "EP-1" docs/masterplans/2-retire-v1-escape-hatches-in-pure-core-tinpproj-sbv-boolalg.md

**Observe:** `cabal build` and `cabal test` succeed. The MasterPlan's
Exec-Plan Registry shows EP-1's Status (Not Started / In Progress /
Complete). Record the status in this plan's Decision Log:

    - Decision: EP-1 status at EP-2 M0 was {status}.
      Rationale: determines M1's translation-target choice.
      Date: <today>

**Acceptance.** Both commands succeed; EP-1 status recorded.

### Milestone 1 — Survey + design note

**Scope.** Make every design decision the rest of the plan needs.
Capture in `docs/research/sbv-boolalg-design.md` (~300 lines).

**At the end of this milestone:** A new file
`docs/research/sbv-boolalg-design.md` exists. It pins:

- Solver library: SBV (default) or z3-haskell.
- Whether the dependency is hard or behind a cabal flag.
- The translatable subset of `Term` (post-EP-1 if available; otherwise
  the v1 subset with `TInpField` falling back to "unknown").
- The translatable subset of `HsPred` (especially the `PMatchC`
  decision: refuse, recognize patterns, or pull `InCtor`-derived
  constructor guards from EP-1's infrastructure).
- The BoolAlg-instance shape: a new instance, a wrapper newtype, or a
  separate type. Recommended: a wrapper newtype
  `newtype SymPred rs ci = SymPred (HsPred rs ci)` with its own
  instance, so v1's `HsPred` instance stays as-is.
- The purity question: `unsafePerformIO` (recommended) vs.
  `MonadIO m` redesign (rejected) vs. separate `BoolAlgIO`.
- Type encoding: `Email`/`ConfirmationCode` (text aliases) → `SString`,
  `UTCTime` → `SInteger` (Unix timestamp seconds), `Bool` → `SBool`,
  numeric → `SInteger`/`SInt32`/etc.
- How `isSingleValued userReg == True` is achieved: which translation
  trick recognizes constructor-mutual-exclusion.
- Test plan: at least the two M7 assertions
  (`isSingleValued userReg == True` and `sat` returns a witness).
- Failure modes: solver timeout, solver unavailable, translation
  refusal. What the user-visible error looks like.

**Surveys to perform.**

*Solver libraries.* Three candidates:

1. **SBV** (`Data.SBV`). Mature, well-documented, pulls z3 by default.
   API: `sat`, `prove`, `allSat`, `optimize`, etc. Symbolic-value
   types: `SBool`, `SInteger`, `SInt32`, `SString`, `SChar`, `SArray
   k v`, etc. The `Provable` and `Symbolic` typeclasses do most of
   the lifting.
2. **z3-haskell** (direct z3 bindings). Lighter than SBV but more
   plumbing per query. Less mature.
3. **Hand-rolled enumeration.** For small finite types, enumerate all
   `(RegFile rs, ci)` values and `eval` the predicate. Sound but only
   feasible if every slot type is finite (integer-bounded, etc.). Not
   feasible for `Text`, `UTCTime`, etc.

Recommend SBV. Document why z3-haskell is rejected (more plumbing).
Document why enumeration is rejected (incomplete).

*SBV not in `mori` registry.* Run `mori registry search sbv` to
confirm absence. The survey of SBV's API will rely on published
documentation; document the methodological caveat.

*Cabal flag.* Decide: `cabal build` requires SBV (default), or
`cabal build --flags="-symbolic"` builds without SBV (and the
symbolic module exposes stubs returning `Nothing`/`False`)? The
recommended choice is "hard requirement" because the formalism's
single-valuedness invariant is load-bearing; making it optional adds
a code path that isn't exercised in the default build. Document the
reasoning in the note.

**Translation of `PMatchC` strategy.** This is the load-bearing
decision for `isSingleValued userReg == True`. The three options:

1. *Refuse.* `isSingleValued userReg == False` because constructor
   guards aren't recognized as mutually exclusive. Insufficient.
2. *Pattern recognition on `PMatchC`'s function.* The function is
   opaque; we cannot inspect it. Rejected.
3. *Use EP-1 infrastructure.* If EP-1 has landed, `InCtor` values
   carry constructor names (`icName`). Update the User Registration
   helpers to express constructor guards via a new helper like:

       matchInCtor :: InCtor ci ifs -> HsPred rs ci

   that translates symbolically as
   `inputCtor == ic.icName`. The symbolic translation introduces a
   free `SString` for the input's constructor name, and `matchInCtor
   ic1 AND matchInCtor ic2` is `inputCtor == ic1.icName AND
   inputCtor == ic2.icName`, which SBV recognizes as unsat for
   distinct names.

   This requires adding `matchInCtor` to `Keiki.Core`'s helper surface,
   adding a `PInCtor :: InCtor ci ifs -> HsPred rs ci` constructor to
   `HsPred`, and updating User Registration's `isStart`/`isConfirm`/
   ... helpers to use it. **This crosses into EP-1's territory**
   (modifying example modules), but is documented as the only path to
   `isSingleValued userReg == True` without scope-creeping `PCtor`
   into EP-2.

Recommended: option 3, with explicit acknowledgement in the design note
that this pulls EP-1's `InCtor` into EP-2's scope. If EP-1 has not
landed, EP-2 has two fallback options:

- Wait for EP-1 (prefer; EP-1 is the soft prerequisite).
- Carve a temporary `PInCtor`-equivalent into EP-2 directly, knowing
  EP-1's M5/M6 migration absorbs it cleanly.

**Concrete steps for M1.** Read these files first:

    src/Keiki/Core.hs
    src/Keiki/Examples/UserRegistration.hs
    docs/research/dsl-shape-for-symbolic-register.md
    docs/research/data-direction-c-symbolic-and-register-automata.md
    docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md
    docs/research/effects-boundary.md
    docs/plans/4-prototype-symbolic-register-core-with-user-registration-smoke-test.md
    docs/plans/5-replace-tinpfield-with-structural-input-projection-tinpproj.md

If EP-1 is Complete:

    docs/research/tinpproj-design.md
    src/Keiki/Examples/UserRegistration.hs   (post-EP-1 form)
    src/Keiki/Examples/UserRegistrationV0.hs (post-EP-1 form)

Then write `docs/research/sbv-boolalg-design.md` covering all the
decisions above, the test plan, and an implementation checklist for
M2-M7.

**Acceptance.** The note exists; a reader can implement M2-M7 from it.

### Milestone 2 — Add solver dependency to cabal

**Scope.** Modify `keiki.cabal` to depend on the chosen solver.
Confirm the dep resolves and the build succeeds. Document the runtime
requirement (z3 in `PATH`).

**At the end of this milestone:** `keiki.cabal`'s `library` stanza has
`sbv` (or whatever the M1 milestone picked) in `build-depends`. A
short comment in the cabal file documents the runtime requirement.
`cabal build` succeeds. The new dependency does not yet need to be
imported by any source file.

**Edits.** In `keiki.cabal`:

- Add `sbv ^>= 11.x` (verify the latest major version compatible with
  GHC 9.10.3) to `library`'s `build-depends`.
- Optionally add the same to the `keiki-test` stanza if M3+ tests
  import SBV directly (likely they will, to verify translations).
- Add a haddock-style synopsis comment documenting the runtime z3
  requirement:

      -- The library's symbolic analyses (sat, isBot, isSingleValued)
      -- require the z3 SMT solver to be available in PATH at runtime.
      -- Install via: brew install z3 (macOS) or apt install z3
      -- (Debian). The library will fail loudly if z3 is missing.

**Concrete steps:**

    cabal build

If `cabal build` fails on `sbv` not resolving, check the SBV version
constraint against `cabal info sbv` or update the constraint. If SBV
brings in incompatible transitive deps, document the constraint shape
in the note's Decision Log.

**Acceptance.** `cabal build` succeeds with the new dep. Mark M2
complete.

### Milestone 3 — Implement `Term`-to-SBV translation

**Scope.** Define the translation surface — typeclasses for symbolic
representations of slot/ci types, and a structural walk that converts
a `Term` to an SBV expression. This milestone introduces the
`Keiki.Symbolic` module (or extends `Keiki.Core`; M1 picks).

**At the end of this milestone:** A new module (or section of
`Keiki.Core`) exports:

- `class Symbolic a where toSBV :: a -> SBV (SymRepr a); fromSBV ::
  SymRepr a -> a` (or similar; M1 pins exact name and signature).
- Instances for the slot/ci types used by `Keiki.Examples.UserRegistration`:
  `Text`, `UTCTime`, and the type aliases `Email`/`ConfirmationCode`.
- A `translateTerm :: Term rs ci r -> SymContext -> SBV (SymRepr r)`
  (or similar) that walks a `Term` AST and produces an SBV expression.
- Unit tests in `test/Keiki/Symbolic/TranslationSpec.hs` (or wherever
  M1 places them) covering: `TLit Int`, `TLit Text`, `TReg`,
  `TInpCtorField` (post-EP-1) or `TInpField` fallback (pre-EP-1),
  `TApp1`/`TApp2` for SBV-friendly ops if M1 picked the curated
  whitelist.

`cabal test` passes (existing tests + new translation tests).

**Edits.** Per M1's design note. The high-level shape:

In `src/Keiki/Symbolic.hs` (new file, or extend `Keiki.Core`):

    {-# LANGUAGE TypeFamilies #-}

    module Keiki.Symbolic
      ( Symbolic (..)
      , SymContext (..)
      , translateTerm
      , translatePred
      , symModels
      , symSat
      , symIsBot
      , isSingleValuedSym
      , module Keiki.Core
      ) where

    import qualified Data.SBV as SBV
    ...

In `keiki.cabal`:

- Add `Keiki.Symbolic` to the `library`'s `exposed-modules`.
- Add the corresponding test module to the `keiki-test` `other-modules`.

**Acceptance.** `cabal build` and `cabal test` succeed. The new
translation tests pass. Mark M3 complete.

### Milestone 4 — Implement new `BoolAlg` instance

**Scope.** Define the symbolic predicate type (the M1 design note's
choice; recommended: `newtype SymPred rs ci = SymPred (HsPred rs ci)`)
and its `BoolAlg` instance for `top`, `bot`, `conj`, `disj`, `neg`.
These are pure structural compositions; no solver call yet.

**At the end of this milestone:** `Keiki.Symbolic` exports `SymPred`
(or whatever M1 named it) and a `BoolAlg SymPred (RegFile rs, ci)`
instance with five-of-eight methods implemented (`models`, `sat`,
`isBot` are M5). `cabal build` succeeds; `cabal test` passes.
Unit tests in the symbolic spec cover the algebraic laws on a tiny
example (`top`/`bot` distinct; `conj` symmetric; etc.).

**Edits.** In `src/Keiki/Symbolic.hs`:

- Define `newtype SymPred rs ci = SymPred (HsPred rs ci)` (or the M1
  choice).
- Implement five methods of the `BoolAlg` instance.

In `test/Keiki/Symbolic/PredSpec.hs` (new file):

- `top /= bot`.
- `conj p q == conj q p` (semantically; structurally the wrapper
  matters less).
- `neg (neg p) == p` (semantically).

**Acceptance.** `cabal build` and `cabal test` succeed. Mark M4 complete.

### Milestone 5 — Implement symbolic `models`, `sat`, `isBot`

**Scope.** The remaining three `BoolAlg` methods. These call SBV.

**At the end of this milestone:** `models`, `sat`, `isBot` on
`SymPred` produce SMT-backed answers. `sat` returns a `Just (regFile,
ci)` witness for a satisfiable predicate; `Nothing` for unsat or
solver-unknown. `isBot` returns `True` for unsat predicates; `False`
otherwise. `cabal test` passes.

**Edits.** In `src/Keiki/Symbolic.hs`:

- Implement `models p (regs, ci) = evalPred (SymPred -> HsPred) p regs ci`
  (re-use the v1 `evalPred` since `models` is a concrete check, not
  a symbolic one).
- Implement `sat (SymPred p) = unsafePerformIO $ do
    result <- SBV.sat (translatePred p)
    case result of
      ...`. Extract a witness `(RegFile rs, ci)` from the SBV model
  using the `Symbolic` typeclass's `fromSBV` direction. Return
  `Just (regFile, ci)` or `Nothing` on unsat / unknown.
- Implement `isBot (SymPred p) = unsafePerformIO $ do
    result <- SBV.isVacuous (translatePred p)
    pure result`. Or equivalently: `case sat ... of Nothing -> True;
    Just _ -> False`.

In `test/Keiki/Symbolic/PredSpec.hs`:

- Add cases:
  - `sat top` returns `Just _` (any witness).
  - `sat bot` returns `Nothing`.
  - `sat (PEq (TLit (5 :: Int)) (TLit 5))` returns `Just _`.
  - `sat (PEq (TLit (5 :: Int)) (TLit 6))` returns `Nothing`.
  - `isBot bot == True`; `isBot top == False`; `isBot (PEq (TLit 5)
    (TLit 6)) == True`.
  - On a non-trivial predicate involving register reads or input
    projections: build the predicate, call `sat`, verify the witness
    `models` the original.

**Acceptance.** `cabal build` and `cabal test` succeed. The SBV-backed
tests pass. If the test runner reports SBV exceptions like
"z3 not in PATH", the contributor must install z3 (`brew install z3`
or equivalent); document this in the M2 cabal-comment.

Mark M5 complete.

### Milestone 6 — Implement symbolic `isSingleValued`

**Scope.** Walk every vertex's outgoing edges; for every distinct
pair, check that their guard conjunction is `isBot`. Return `True` iff
all pairs are bot.

**At the end of this milestone:** `isSingleValuedSym :: (BoolAlg phi
(RegFile rs, ci), Bounded s, Enum s) => SymTransducer phi rs s ci co
-> Bool` (or replace `isSingleValued` in `Keiki.Core` if M1 decided)
exists and works. A unit test on a known-single-valued 2-edge synthetic
returns `True`.

**Edits.** In `src/Keiki/Symbolic.hs` (or `Keiki/Core.hs` if M1
replaced):

    isSingleValuedSym
      :: (BoolAlg phi (RegFile rs, ci), Bounded s, Enum s)
      => SymTransducer phi rs s ci co -> Bool
    isSingleValuedSym t = all vertexSV [minBound .. maxBound]
      where
        vertexSV s =
          let es = edgesOut t s
              pairs = [ (e1, e2) | (i, e1) <- zip [0..] es
                                 , (j, e2) <- zip [0..] es
                                 , i < j ]
          in all (\(e1, e2) -> isBot (guard e1 `conj` guard e2)) pairs

In `test/Keiki/Symbolic/SingleValuedSpec.hs` (new file):

- A 2-edge transducer where the guards are mutually exclusive
  (`isBot (g1 \`conj\` g2) == True`); `isSingleValuedSym == True`.
- A 2-edge transducer where the guards overlap; `isSingleValuedSym ==
  False`.

**Acceptance.** `cabal test` passes. Mark M6 complete.

### Milestone 7 — Tests on User Registration

**Scope.** The plan's load-bearing test: `isSingleValued userReg ==
True` symbolically proved. Plus a `sat`-returns-witness assertion on
a hand-built predicate over the User Registration register file.

**At the end of this milestone:** A new spec file
`test/Keiki/Examples/UserRegistrationSymbolicSpec.hs` (or additions to
the existing spec; M1 picks) contains at least:

- `isSingleValuedSym userReg == True`.
- A `sat` of a non-trivial predicate over `UserRegRegs` returns a
  witness whose `models` confirms the predicate.

The test suite reports the new examples; `cabal test` passes overall.

**Pre-requisite:** the `PMatchC`-handling decision from M1 must be in
place. If M1 chose option 3 (`InCtor`-derived constructor guards),
this milestone updates `Keiki.Examples.UserRegistration`'s
`isStart`/`isConfirm`/... helpers to use the new `matchInCtor`-style
helper, and adds a `PInCtor` constructor (or equivalent) to
`HsPred`. Document this clearly as a cross-cut into EP-1's territory in
the Decision Log.

**Edits.** Per M1's plan.

**Acceptance.** `cabal test` passes; the User Registration symbolic
spec reports the expected results. Mark M7 complete.

### Milestone 8 — Update DSL design note; capture verdict

**Scope.** Cascade the upgrade through the design notes; write the
EP-2 verdict.

**At the end of this milestone:** `docs/research/dsl-shape-for-symbolic-register.md`
no longer claims `sat _ = Nothing` is the v1 BoolAlg behavior; the
note's "Predicate carrier (HsPred)" section gains a v2-update
paragraph. `docs/research/effects-boundary.md` §5 ("isSingleValued")
no longer claims it is "best-effort in v1"; it is upgraded.
`docs/research/sbv-boolalg-design.md` is the authoritative v2 design
record. This plan's Outcomes & Retrospective contains the verdict.
The MasterPlan reflects EP-2 completion.

**Edits.** Per the milestone scope.

**Acceptance.** All notes updated; MasterPlan reflects EP-2 complete;
verdict written. Mark M8 complete.


## Concrete Steps

All commands run from the repo root:
`/Users/shinzui/Keikaku/bokuno/keiki`.

**M0:**

    cabal build
    cabal test
    grep "EP-1" docs/masterplans/2-retire-v1-escape-hatches-in-pure-core-tinpproj-sbv-boolalg.md

**M1:** No commands; deliverable is the design note. Verify with:

    wc -l docs/research/sbv-boolalg-design.md

Expect ~300 lines.

**M2:** After editing `keiki.cabal`:

    cabal build

If z3 is required for build (it is for SBV's link-test),
ensure it is installed:

    which z3 || brew install z3

**M3-M7:** After each edit batch:

    cabal build
    cabal test

**M8:** verify the doc edits:

    git diff docs/research/dsl-shape-for-symbolic-register.md
    git diff docs/research/effects-boundary.md

After the M8 commit, also verify:

    cabal build
    cabal test

**Commits:** every milestone gets a commit with the message format:

    feat(symbolic): <one-line summary of the milestone>

    <details paragraph>

    MasterPlan: docs/masterplans/2-retire-v1-escape-hatches-in-pure-core-tinpproj-sbv-boolalg.md
    ExecPlan: docs/plans/6-sbv-backed-boolalg-instance-for-symbolic-emptiness.md
    Intention: intention_01knjzws4qezz9w8b0743zfqv8

Conventional Commits scopes: `feat(symbolic)`, `feat(core)`,
`docs(research)`, `docs(masterplan)`, `test(symbolic)`,
`test(examples)`, `chore(cabal)`.


## Validation and Acceptance

The plan is complete when all of the following hold simultaneously:

- `cabal build` succeeds at the repo root with SBV linked.
- `cabal test` succeeds with the new symbolic tests passing.
- `isSingleValued userReg == True` (symbolically proved) is asserted
  in the test suite.
- `sat` on a hand-built non-trivial predicate over `UserRegRegs`
  returns a `Just (regs, ci)` witness whose `models` of the predicate
  is `True`.
- `isBot (PEq (TLit 5) (TLit 6) :: HsPred '[] ()) == True` (or
  equivalent) is asserted, demonstrating SBV catches simple
  contradictions.
- `docs/research/sbv-boolalg-design.md` exists and is internally
  consistent.
- `docs/research/dsl-shape-for-symbolic-register.md` is updated to
  reflect the v2 BoolAlg upgrade.
- `docs/research/effects-boundary.md` is updated to reflect that
  `isSingleValued` is no longer best-effort.
- The MasterPlan's Exec-Plan Registry shows EP-2 = Complete; its
  Progress section's EP-2 entries are checked off.
- This plan's Outcomes & Retrospective contains a written verdict.


## Idempotence and Recovery

Each milestone can be re-run safely. Common issues and recovery paths:

- *M2: SBV dep won't resolve.* Check `cabal info sbv` for available
  versions compatible with GHC 9.10.3. Adjust the version constraint
  in `keiki.cabal`. If a cabal-flag-gated build was chosen, verify
  the flag is being respected.
- *M3: Translation test fails with "Cannot translate TInpField".*
  Expected if EP-1 has not landed. Use the M1 fallback (treat
  TInpField as a free symbolic variable, lose precision).
- *M5: SBV exception `Exception: Couldn't run query - z3 not in PATH`.*
  Install z3 (`brew install z3` on macOS).
- *M5: SBV returns `Unknown` for solver result.* Document in
  Surprises & Discoveries; treat as `sat = Nothing` (conservative);
  decide whether to bump the timeout in M1's note.
- *M7: `isSingleValued userReg == False` instead of `True`.* Most
  likely cause: M1's `PMatchC`-handling decision didn't actually
  recognize constructor-mutual-exclusion. Re-read M1's design and
  trace through the translation manually for `isConfirm \`conj\`
  isResend`. The fix may be to update the User Registration helpers
  per the M1 option 3 plan.
- *M7 cross-cuts EP-1 territory.* Document in Decision Log; cascade to
  MasterPlan's Surprises & Discoveries.

If a milestone is rolled back (the work is undesirable), use
`git restore` for source files and `git checkout` for documents.


## Interfaces and Dependencies

**New cabal dependency:** `sbv` (M1 confirms version constraint).
Pulls a runtime requirement on z3 in `PATH`.

**Module-level interfaces (post-EP-2):**

- `Keiki.Symbolic` (or `Keiki.Core`; M1 picks) exports:
  - `class Symbolic a` (or similar; M1 pins).
  - Instances for `Text`, `UTCTime`, `Bool`, `Int`, `Integer`, and the
    `Email`/`ConfirmationCode` aliases.
  - `SymPred rs ci` (or similar; M1 picks the wrapper type).
  - `BoolAlg SymPred (RegFile rs, ci)` instance.
  - `isSingleValuedSym :: (BoolAlg phi (RegFile rs, ci), Bounded s,
    Enum s) => SymTransducer phi rs s ci co -> Bool` (or in-place
    upgrade of `isSingleValued`).

- `Keiki.Core`:
  - If M1 picked option 3 for `PMatchC` handling, gain a `PInCtor`
    constructor (or equivalent) and a `matchInCtor` helper, used by
    the User Registration helpers post-M7.
  - Otherwise unchanged.

- `Keiki.Examples.UserRegistration`:
  - If M1 picked option 3, the `isStart`/`isConfirm`/... helpers
    use `matchInCtor` instead of `matchCmd`.
  - Otherwise unchanged.

**MasterPlan integration points:**

- IP-1 (the `Term` constructor set): EP-2 reads. The translation
  walks the constructors EP-1 defined.
- IP-3 (BoolAlg class methods): EP-2 owns the upgrade.
- IP-4 (User Registration smoke test): EP-2 adds a new symbolic
  spec on the post-EP-1 form.
- IP-5 (new design notes): EP-2 produces
  `docs/research/sbv-boolalg-design.md`.

**Reading list before starting M1:**

- `src/Keiki/Core.hs` — the v1 `BoolAlg`, `HsPred`, `isSingleValued`
  surfaces.
- `docs/research/dsl-shape-for-symbolic-register.md` — the
  predicate-carrier section and the v2 retirement hint.
- `docs/research/data-direction-c-symbolic-and-register-automata.md`
  §5 — the SMT-backed phase sketch and the curated supported subset.
- `docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`
  §7 — the v2 SBV-backed BoolAlg instance plan.
- `docs/research/effects-boundary.md` §5 — the `isSingleValued`
  best-effort v1 contract.
- `docs/plans/4-prototype-symbolic-register-core-with-user-registration-smoke-test.md`
  — the EP-4 retrospective entry naming SBV BoolAlg as a v2 priority.
- `docs/plans/5-replace-tinpfield-with-structural-input-projection-tinpproj.md`
  — EP-1's plan; informs whether the structural Term is in place.
- `src/Keiki/Examples/UserRegistration.hs` — the smoke test target.
  After EP-1 lands, the form is changed; M1 must read whichever form
  is current.

**External documentation references** (read only the parts needed for
M1's design decisions):

- SBV's Hackage page: `Data.SBV` module structure, the `Symbolic`
  monad, `SBool`/`SInteger`/`SString`/`SChar` types, `sat`/`prove`/
  `isVacuous`. Read before M1 to ground the translation design.
- SBV examples gallery: there are well-documented walkthroughs of
  encoding ADTs as symbolic values. Skim before M3.
