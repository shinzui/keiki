---
id: 76
slug: symbolic-soundness-solver-unknown-handling-encoding-gap-caveats-and-a-stronger-pure-overlap-check
title: "Symbolic soundness: solver Unknown handling, encoding-gap caveats, and a stronger pure overlap check"
kind: exec-plan
created_at: 2026-07-12T04:16:45Z
intention: "intention_01kxc5whw1en3ra4nh728m53ka"
master_plan: "docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md"
---

# Symbolic soundness: solver Unknown handling, encoding-gap caveats, and a stronger pure overlap check

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This plan is Phase 4 of the master plan at
`docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md`
and is release-gating for keiki 0.1.0.0. It has a soft dependency on
`docs/plans/71-align-build-time-validation-with-replay-head-recoverability-cross-edge-inversion-ambiguity-and-guard-implies-input-read-checks.md`
(EP-71): EP-71 owns the coordinated breaking change to the
`TransducerValidationWarning` type that the keiro consumer pattern-matches
exhaustively. This plan deliberately adds **no** new warning constructors and reuses
the existing vocabulary, so it can land before or after EP-71 without conflict; see
the Decision Log.


## Purpose / Big Picture

keiki is a pure-core library for event sourcing: an aggregate is modeled as a
*symbolic register transducer* — a finite control graph (`SymTransducer` in
`src/Keiki/Core.hs`) whose edges carry a *guard* (a predicate over the current
register values and the incoming command), an update, and an output. A transducer is
only well-behaved when it is *single-valued*: at every vertex, for any one input, at
most one outgoing edge's guard can be satisfied. If two guards overlap, the runtime
step function faces an ambiguous choice, which surfaces downstream as an
`AmbiguousEdges` step failure — a command silently rejected (or worse,
nondeterministically handled) in production.

keiki decides single-valuedness at build time in two ways, and both feed
`validateTransducer` (in `src/Keiki/Core.hs`), which current keiro runs at its stream boundary
(`keiro-core/src/Keiro/EventStream/Validate.hs` in the keiro repository):

1. A **pure structural pass** (`checkTransitionDeterminismPure` /
   `provablyOverlap` in `src/Keiki/Core.hs`) that must *never* report a false
   positive, and
2. An **exact solver-backed pass** (`checkTransitionDeterminismSym` /
   `symIsBot` in `src/Keiki/Symbolic.hs`) that translates guards into the SBV
   library's symbolic terms and asks the z3 SMT solver whether the conjunction of
   two guards is satisfiable.

This plan fixes three soundness defects and one documentation gap in those passes,
all verified against the current sources (file-and-line citations are in Context and
Orientation):

- **The Unknown inversion (high severity).** When z3 *gives up* on a query (result
  `Unknown` — realistic for `Text`-typed guards, which translate to z3's string
  theory, a well-known source of Unknown results), `symIsBot` currently declares the
  predicate *provably empty*, so a possibly-overlapping guard pair is blessed as
  disjoint. That is exactly the wrong direction: a solver timeout silently
  certifies a transducer that may be nondeterministic at runtime. After this plan,
  any solver result other than a definite "unsatisfiable" is treated as "not
  provably empty" — the check may then report an overlap that isn't there, but it
  can never bless one that is.
- **Encoding gaps (medium).** The translator encodes the fixed-width integer types
  (`Word8/16/32/64`, `Int32/64`) as *unbounded* mathematical integers and truncates
  `UTCTime` to whole seconds. Both can make the symbolic conjunction of two guards
  unsatisfiable while the concrete evaluator `evalPred` satisfies both — the
  determinism gate passes while the runtime is nondeterministic. After this plan the
  fixed-width types use SBV's exact machine words (wraparound modeled), and
  `UTCTime` is encoded at picosecond resolution (lossless).
- **A near-vacuous pure overlap check (medium).** `provablyOverlap` proves overlap
  only for two bare `PTop` guards or two bare `PInCtor` guards naming the same
  constructor — but every guarded Builder edge is a `PAnd` (the `onCmd` entry seeds
  `matchInCtor ic` and each `requireGuard` wraps another `PAnd` around it), so real
  overlapping pairs like `matchInCtor A .&& x .> 0` versus `matchInCtor A .&& x .> 5`
  pass the pure path silently while the `validateTransducer` haddock invites
  projects to assert `validateTransducer opts t == []` in unit tests. After this
  plan the pure pass walks `PAnd` spines and proves overlap for a precisely
  documented decidable fragment (same-constructor atoms plus variable-versus-literal
  comparisons), still with zero false positives.
- **Documentation (minor).** The solver calls are wrapped in `unsafePerformIO`, so a
  missing z3 binary surfaces as an exception thrown from *pure* code. That caveat is
  documented on the check functions but not on the `BoolAlg (SymPred rs ci)`
  instance whose `isBot` method routes through the solver; this plan documents it
  there.

How to see it working: after implementation, a two-edge fixture whose guards
overlap only at a `Word8` wraparound point (see Milestone 2) makes
`checkTransitionDeterminismSym` return a non-empty warning list where before it
returned `[]`; the guard pair `matchInCtor A .&& x .> 0` / `matchInCtor A .&& x .> 5`
makes plain `validateTransducer defaultValidationOptions t` return a
`NondeterministicPair` warning where before it returned `[]`; and a hand-built
`Unknown` solver result is interpreted as "not provably empty" by a directly
testable pure function. Run `cabal test all` inside `nix develop` to observe all of
this.


## Progress

- [x] Plan authored; every defect below verified against the working tree and the
      SBV package sources (citations in Context and Orientation; evidence in
      Surprises & Discoveries). 2026-07-11.
- [x] Milestone 1: factor the pure solver-verdict interpreter
      `satResultIsProvablyUnsat` in `src/Keiki/Symbolic.hs` and rewire `symIsBot`
      through it. 2026-07-12.
- [x] Milestone 1: audit every other `SBV.SatResult` inspection in
      `src/Keiki/Symbolic.hs` (`symSatExt` is the only other one; its direction is
      correct — document, don't change). 2026-07-12.
- [x] Milestone 1: correct the `symIsBot` haddock (it currently *claims* the
      conservative Unknown behavior the code does not implement) and document the
      `Nothing`-means-unsat-or-unknown semantics on `symSatExt`. 2026-07-12.
- [x] Milestone 1: unit tests for `satResultIsProvablyUnsat` over hand-built
      `Unknown` / `ProofError` results and real z3-produced `Satisfiable` /
      `Unsatisfiable` results, in `test/Keiki/SymbolicSpec.hs`. 2026-07-12.
- [x] Milestone 1 (optional prototype): deliberately skipped the timeout-based
      end-to-end prototype because the pure constructor-level regression covers every
      verdict deterministically without introducing a timing-sensitive test. 2026-07-12.
- [ ] Milestone 2: switch `Sym Word8/16/32/64` and `Sym Int32/64` to exact
      fixed-width `SymRep`s in `src/Keiki/Symbolic.hs`; rewrite the
      over-approximation comment block.
- [ ] Milestone 2: switch `Sym UTCTime` to picosecond-resolution `Integer`
      encoding; keep or revert per the fallback criterion in Milestone 2.
- [ ] Milestone 2: regression tests — the `Word8` wraparound overlap the old
      encoding missed, and the sub-second `UTCTime` overlap the old encoding
      missed, in `test/Keiki/SymbolicSpec.hs`.
- [ ] Milestone 2: confirm `test/Keiki/SymbolicSpec.hs`, `test/Keiki/ValidationSpec.hs`
      and `jitsurei/test/Jitsurei/OrderCartSymbolicSpec.hs` still pass (jitsurei's
      money type is `Word64` — its fixtures exercise the changed instances).
- [ ] Milestone 3: implement the spine-walking `provablyOverlap` in
      `src/Keiki/Core.hs` (atom collection, constructor-consistency, integral
      interval reasoning, literal-witness probing).
- [ ] Milestone 3: make `determinismWarnings`'s `overlapCtor` spine-aware so
      `tvwInCtor` is populated for `PAnd` guards.
- [ ] Milestone 3: tests in `test/Keiki/ValidationSpec.hs` — true positive on the
      motivating pair, no warning on provably-disjoint and on unknown-fragment
      pairs, `tvwInCtor` population, and the pure-implies-symbolic agreement check.
- [ ] Milestone 3: haddock rewrite for `provablyOverlap`,
      `checkTransitionDeterminismPure`, and `validateTransducer` documenting the
      exact decidable fragment and pushing the z3 pass as the exact gate.
- [ ] Milestone 4: document the `unsafePerformIO` / missing-z3 failure mode on the
      `BoolAlg (SymPred rs ci)` instance; add remaining caveats to
      `validateTransducer`'s haddock; changelog entry; format with
      `nix fmt -- --no-cache`; final `cabal build all && cabal test all`.


## Surprises & Discoveries

These entries were established during plan authoring (2026-07-11); add new ones as
implementation proceeds.

- **The Unknown inversion is real and is the opposite of the docstring.**
  `symIsBot` (`src/Keiki/Symbolic.hs:596-602`) returns
  `not (SBV.modelExists res)`, and SBV's `modelExists` — verified in the SBV
  package source at
  `/Users/shinzui/Keikaku/hub/haskell/sbv-project/sbv/Data/SBV/SMT/SMT.hs:483-485` —
  is defined:

  ```haskell
  modelExists Satisfiable{}   = True
  modelExists Unknown{}       = False -- don't risk it
  modelExists _               = False
  ```

  So `Unknown` (and also `DeltaSat`, `SatExtField`, and `ProofError`, per the
  `SMTResult` definition at
  `/Users/shinzui/Keikaku/hub/haskell/sbv-project/sbv/Data/SBV/Core/Symbolic.hs:2271-2276`)
  makes `modelExists` `False`, hence `symIsBot` `True` — "provably empty". SBV's
  own "don't risk it" comment is conservative *for its use case* (claiming a model
  exists); negated by `symIsBot`, it becomes anti-conservative for ours. The
  `symIsBot` docstring (`src/Keiki/Symbolic.hs:590-595`) claims
  "`False` otherwise (including the conservative 'Unknown' fallback)" — the code
  does the opposite of its own documentation.
- **`symSatExt` uses `modelExists` in the *correct* direction.** At
  `src/Keiki/Symbolic.hs:839` it extracts a witness only from a `Satisfiable`
  result; `Unknown` yields `Nothing`. That is the only honest option for witness
  extraction (there is no model to decode), but it silently conflates
  "unsatisfiable" with "solver gave up" — a documentation fix, not a code fix.
  These are the only two `SatResult` inspections in the module (audited the whole
  file).
- **Every guarded Builder edge is a `PAnd`, so the current pure check is vacuous
  in practice.** `onCmd` seeds the guard with the bare constructor match
  (`src/Keiki/Builder.hs:672`, `peGuard = matchInCtor ic`) and `requireGuard`
  conjoins every refinement (`src/Keiki/Builder.hs:558-560`,
  `peGuard = PAnd (peGuard pe) p`), so any edge with at least one requirement has a
  `PAnd` guard — a shape `provablyOverlap` (`src/Keiki/Core.hs:1803-1806`) never
  matches.
- **SBV exposes what the fixes need.** `Data.SBV` exports `SatResult(..)`,
  `SMTResult(..)` and `SMTReasonUnknown(..)` (verified in
  `/Users/shinzui/Keikaku/hub/haskell/sbv-project/sbv/Data/SBV.hs:443`;
  `SMTReasonUnknown` constructors `UnknownMemOut | UnknownIncomplete |
  UnknownTimeOut | UnknownOther String` at
  `/Users/shinzui/Keikaku/hub/haskell/sbv-project/sbv/Data/SBV/Control/Types.hs:53-56`),
  so a pure verdict function can be unit-tested against a hand-built
  `Unknown` result. It also exports `setTimeOut :: Integer -> m ()` (a
  `SolverContext` method, `Data/SBV/Core/Data.hs:572`) for the optional
  Unknown-provocation prototype. keiki's cabal bound is `sbv >=11.7 && <15`
  (`keiki.cabal:91`).
- **Milestone 1 kept the regression deterministic.** The focused test run reported
  three passing examples for `satResultIsProvablyUnsat`: a hand-built `Unknown`, a
  hand-built `ProofError`, and real z3 sat/unsat results. The `Unknown` test also
  evaluates the old expression `not (SBV.modelExists unknown)` to `True`, directly
  pinning the inversion before asserting the new verdict is `False`. A timeout-based
  end-to-end prototype was deliberately not promoted because its timing behavior
  would make the suite less reliable without expanding verdict coverage.


## Decision Log

- Decision: Interpret every solver result other than `Unsatisfiable` as "not
  provably empty" in `symIsBot` (i.e. `Unknown`, `ProofError`, `DeltaSat`,
  `SatExtField`, and of course `Satisfiable` all mean *not* bot).
  Rationale: `isBot` answering `True` is what *blesses* a guard pair as disjoint
  and an edge as dead. The safe failure direction is a spurious warning (a human
  investigates, finds nothing) — never a silent blessing of a real runtime
  nondeterminism. `DeltaSat`/`SatExtField` cannot occur under plain `SBV.sat` with
  z3, but matching them explicitly costs nothing and future-proofs against
  configuration changes.
  Date: 2026-07-11.
- Decision: Fix the fixed-width integer encodings (`Word8/16/32/64`, `Int32/64`)
  by giving each type its own `SymRep` (SBV models these exactly, with modular
  wraparound); keep `Sym Int` and `Sym Integer` encoded as unbounded `Integer` and
  document that `Int` wraparound is not modeled.
  Rationale: the sized types are where the gap bites real consumers (jitsurei's
  money type is `Word64`), and the change is mechanical — SBV has native
  `SymVal`/`OrdSymbolic`/`Num` support for all six types, so the
  `discoverSym`/`discoverSymOrd`/`discoverSymNum` registries and the witness
  extractor need no structural change. `Int`'s width is platform-defined; pinning
  it to `SInt64` would bake a 64-bit assumption into the library, and guards whose
  truth depends on `Int` overflow are a code smell better served by the documented
  caveat.
  Date: 2026-07-11.
- Decision: Encode `UTCTime` at picosecond resolution (attempt first), with the
  documented-caveat fallback only if the exact encoding proves disruptive.
  Rationale: `NominalDiffTime` *is* a fixed-point picosecond value
  (`Fixed E12`), so the picosecond `Integer` encoding is lossless — it removes the
  gap rather than documenting it, at the cost of a two-line `toSym`/`fromSym`
  change. Fallback criterion: if any existing test (keiki's `SymbolicSpec`,
  jitsurei's `OrderCartSymbolicSpec`) depends on second-granularity round-tripping
  in a way that cannot be fixed locally in the test, revert to the
  round-to-seconds encoding and instead add a loud caveat to `symIsBot`,
  `isSingleValuedSym`, `checkTransitionDeterminismSym`, `checkDeadEdgesSym`, and
  `validateTransducer` haddocks stating that sub-second time bounds may be
  conflated.
  Date: 2026-07-11.
- Decision: Add **no** new `TransducerValidationWarning` constructors and **no**
  new `ValidationOptions` field in this plan.
  Rationale: master plan 16, integration point 1, gives EP-71
  (`docs/plans/71-align-build-time-validation-with-replay-head-recoverability-cross-edge-inversion-ambiguity-and-guard-implies-input-read-checks.md`)
  ownership of the coordinated breaking change to the warning type — the keiro
  consumer pattern-matches it exhaustively at
  `keiro-core/src/Keiro/EventStream/Validate.hs:147-155`, so every constructor
  addition breaks keiro. Everything this plan reports fits the existing
  `NondeterministicPair` and `PossiblyDeadEdge` constructors, and the strengthened
  pure determinism check rides the existing `checkDeterminism` option. If, during
  implementation, a new constructor turns out to be genuinely needed, STOP and
  coordinate with EP-71 rather than adding one here.
  Date: 2026-07-11.
- Decision: Keep the names and signatures of `symIsBot`, `symSatExt`,
  `isSingleValuedSym`, `withSymPred`, `checkTransitionDeterminismSym`, and
  `checkDeadEdgesSym` exactly as they are; new exports are additive only
  (`satResultIsProvablyUnsat`).
  Rationale: these are published keiki APIs and in-tree symbolic specs call them by
  name. Behavior *does* change: after the Unknown fix and the strengthened pure
  check, current keiro may see new validation warnings that are true positives the
  old code missed. The downstream fix is to repair or explicitly acknowledge the
  flagged transducer, not to pin the old keiki. Record this in the changelog entry.
  Date: 2026-07-11.
- Decision: The strengthened `provablyOverlap` returns `True` only when a
  satisfying assignment for *both* guards provably exists, using two proof
  techniques — exact integer-interval reasoning for a curated registry of
  integral types, and concrete literal-witness probing for everything else — and
  answers "unknown" (no warning) for any guard containing an atom outside the
  fragment.
  Rationale: preserves the existing zero-false-positive contract (the
  `validateTransducer` haddock promises projects can assert `== []` in unit
  tests); interval reasoning is what catches the motivating
  `x .> 0` / `x .> 5` pair, which pure literal probing alone cannot (no mentioned
  literal satisfies both strict bounds).
  Date: 2026-07-11.


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Everything in this section is stated from scratch; no prior plan is assumed.

**The repository.** `/Users/shinzui/Keikaku/bokuno/keiki` is a Haskell cabal
project (GHC 9.12). The library lives under `src/`; the test suite under `test/`
(hspec, entry point `test/Spec.hs`, one module per area, e.g.
`test/Keiki/SymbolicSpec.hs` and `test/Keiki/ValidationSpec.hs`). A worked-example
consumer package lives in-repo under `jitsurei/` with its own test suite. Enter the
development shell with `nix develop` from the repository root; it provides GHC,
cabal, and the z3 solver binary on `PATH`. Build with `cabal build all`, test with
`cabal test all`, format with `nix fmt -- --no-cache`.

**Transducers and guards.** `src/Keiki/Core.hs` defines `SymTransducer` — a finite
control graph: `edgesOut :: s -> [Edge phi rs ci co s]` gives each vertex's
outgoing edges, and each `Edge` carries a guard of type `phi`, an update, an output
list, and a target vertex. For the concrete carrier, `phi` is
`HsPred rs ci` (`src/Keiki/Core.hs:524-552`) — a small first-order predicate
language with constructors `PTop` (always true), `PBot` (always false), `PAnd`,
`POr`, `PNot`, `PEq` (equality of two `Term`s), `PCmp` (ordering of two `Term`s,
with a `Cmp` tag `CmpLt | CmpLe | CmpGt | CmpGe`), and `PInCtor` (the input command
is a particular constructor, identified by an `InCtor` value whose `icName` is the
constructor's name). A `Term rs ci ifs r` (`src/Keiki/Core.hs:299-330`) is a
literal (`TLit`), a register read (`TReg`, indexed by an `Index` whose leaf
carries the slot name as a `KnownSymbol`), an input-field read (`TInpCtorField`,
naming a constructor and a field), an opaque function application
(`TApp1`/`TApp2` — real Haskell closures the analyses cannot see through), or
structural arithmetic (`TArith` with `OpAdd | OpSub | OpMul`). Concrete evaluation
is `evalPred`/`evalTerm` (`src/Keiki/Core.hs:789` onward); note
`evalTerm (TInpCtorField ic ix)` *errors* if the input is not the named
constructor (`src/Keiki/Core.hs:792-794`), which matters for witness soundness in
Milestone 3.

**"Single-valued" and "bot".** A transducer is single-valued when at every vertex,
for every input, at most one outgoing guard holds. The check reduces to: for every
pair of outgoing guards `g1, g2`, is `g1 AND g2` unsatisfiable ("bot")? The
`BoolAlg` class (`src/Keiki/Core.hs:568-575`) abstracts the guard algebra; its
`isBot` method answers "is this predicate provably empty?". The `HsPred` instance's
`isBot` is syntactic (`True` only for the literal `PBot`,
`src/Keiki/Core.hs:602-603`).

**The two determinism passes.** `validateTransducer`
(`src/Keiki/Core.hs:1622-1638`) is the build-time umbrella producing
`[TransducerValidationWarning s]` (`src/Keiki/Core.hs:1538-1580`; constructors
`HiddenInput`, `NondeterministicPair`, `PossiblyDeadEdge`, `OpaqueGuard`). Its
determinism component is `determinismWarnings` (`src/Keiki/Core.hs:1812-1834`),
which — like the exported `checkTransitionDeterminismPure`
(`src/Keiki/Core.hs:1769-1787`) — flags a pair only when the *private* helper
`provablyOverlap` (`src/Keiki/Core.hs:1803-1806`) proves overlap. Today that
helper is three lines: two bare `PTop`s overlap, two bare `PInCtor`s with the same
name overlap, everything else is "no". The exact pass lives in
`src/Keiki/Symbolic.hs`: `withSymPred` re-tags guards into the `SymPred` newtype
(whose `BoolAlg` instance at `src/Keiki/Symbolic.hs:568-575` routes `isBot`
through the solver), `isSingleValuedSym` (`src/Keiki/Symbolic.hs:615-632`) does
the pairwise `isBot (conj g1 g2)` sweep, `checkTransitionDeterminismSym`
(`src/Keiki/Symbolic.hs:667-671`) produces `DeterminismWarning`s from the same
sweep, and `checkDeadEdgesSym` (`src/Keiki/Symbolic.hs:680-691`) flags edges whose
guard is `symIsBot` in isolation.

**The SBV translation.** SBV ("SMT Based Verification") is a Haskell library that
builds symbolic expressions and hands them to an external SMT solver process (z3
here). `translatePred`/`translateTermSym` (`src/Keiki/Symbolic.hs:428-540`) walk
`HsPred`/`Term` into SBV expressions; the `Sym` class
(`src/Keiki/Symbolic.hs:126-229`) maps each supported Haskell type to its SBV
representation via the associated type `SymRep` with a `toSym`/`fromSym`
round-trip. Today `Int`, `Integer`, `Word8/16/32/64`, and `Int32/64` all map to
unbounded `Integer` (`src/Keiki/Symbolic.hs:138-211`), `Text` maps to `String`
(z3's string theory, `src/Keiki/Symbolic.hs:213-218`), and `UTCTime` maps to
`Integer` *rounded to whole epoch seconds* (`src/Keiki/Symbolic.hs:225-229`).
`symIsBot` (`src/Keiki/Symbolic.hs:596-602`) runs `SBV.sat` on the translation
inside `unsafePerformIO` and currently returns `not (SBV.modelExists res)`;
`symSatExt` (`src/Keiki/Symbolic.hs:814-854`) additionally decodes a concrete
witness from the model. An `SBV.SatResult` wraps an `SMTResult` with constructors
`Unsatisfiable`, `Satisfiable`, `DeltaSat`, `SatExtField`, `Unknown`, `ProofError`
(SBV source: `Data/SBV/Core/Symbolic.hs:2271-2276` in the sbv package, on disk at
`/Users/shinzui/Keikaku/hub/haskell/sbv-project/sbv/`). `SBV.modelExists` is
`True` only for `Satisfiable` (SBV source `Data/SBV/SMT/SMT.hs:483-485`).

**The current integration boundary.** The keiro runtime (separate repository,
`/Users/shinzui/Keikaku/bokuno/keiro`) calls `validateTransducer` at its stream
boundary and renders every warning constructor exhaustively at
`keiro-core/src/Keiro/EventStream/Validate.hs:147-155` — which is why this plan
adds no constructors. In this repository, the callers of the symbolic API are
`test/Keiki/SymbolicSpec.hs`, `test/Keiki/ValidationSpec.hs`, and
`jitsurei/test/Jitsurei/OrderCartSymbolicSpec.hs`.

**Why the runtime consequence matters.** A guard overlap the gates miss is not a
theoretical blemish: at runtime the step function finds two eligible edges for one
command and fails with `AmbiguousEdges` (the dynamic witness named in the
`NondeterministicPair` haddock, `src/Keiki/Core.hs:1550-1552`), i.e. a command that
validated cleanly at build time is rejected — or handled nondeterministically — in
production.


## Plan of Work

The work is four milestones, each independently verifiable with
`cabal test all` from the repository root inside `nix develop`. Milestones 1 and 2
touch `src/Keiki/Symbolic.hs` and `test/Keiki/SymbolicSpec.hs`; Milestone 3
touches `src/Keiki/Core.hs` and `test/Keiki/ValidationSpec.hs`; Milestone 4 is
documentation and release notes. Do Milestone 1 first (Milestone 2's regression
tests rely on the corrected verdict direction); 3 is independent; 4 last.


### Milestone 1 — solver-verdict soundness: Unknown means "not provably empty"

Scope: `src/Keiki/Symbolic.hs` and `test/Keiki/SymbolicSpec.hs`. At the end of
this milestone, `symIsBot` returns `True` only when z3 answers a definite
"unsatisfiable", the verdict interpretation is a pure, directly testable function,
and the docstrings tell the truth.

In `src/Keiki/Symbolic.hs`, add a pure interpreter next to `symIsBot` and export
it from the module's "Solver-backed analyses" section:

```haskell
-- | Interpret a solver result for emptiness ('Keiki.Core.isBot') purposes.
-- 'True' only for a definite 'SBV.Unsatisfiable'. Everything else —
-- 'SBV.Satisfiable', but also 'SBV.Unknown' (solver gave up: timeout,
-- incompleteness, e.g. z3's string theory on 'Text' guards),
-- 'SBV.ProofError', 'SBV.DeltaSat', 'SBV.SatExtField' — is 'False':
-- "not provably empty". This is the conservative direction for every
-- caller: 'isBot' blessing a guard pair as disjoint (or an edge as dead)
-- must never rest on a solver that gave up. A 'False' from 'Unknown' can
-- produce a spurious overlap warning, never a missed one.
satResultIsProvablyUnsat :: SBV.SatResult -> Bool
satResultIsProvablyUnsat (SBV.SatResult r) = case r of
  SBV.Unsatisfiable {} -> True
  SBV.Satisfiable {} -> False
  SBV.DeltaSat {} -> False
  SBV.SatExtField {} -> False
  SBV.Unknown {} -> False
  SBV.ProofError {} -> False
```

Rewire `symIsBot` (currently `pure (not (SBV.modelExists res))` at
`src/Keiki/Symbolic.hs:602`) to `pure (satResultIsProvablyUnsat res)`, and rewrite
its haddock: the current text at `src/Keiki/Symbolic.hs:590-595` claims "`False`
otherwise (including the conservative 'Unknown' fallback)" — after this change
that sentence finally matches the code; extend it to say a `False` answer means
"satisfiable *or* solver gave up" and name the `Text`/string-theory case as the
realistic Unknown source. (Match on the constructors, not on `modelExists`: the
whole defect is that `modelExists` collapses `Unknown` and `Unsatisfiable` into
one bucket when negated.)

Audit the rest of the module for other `SatResult` inspections. There is exactly
one: `symSatExt` at `src/Keiki/Symbolic.hs:839` uses `SBV.modelExists res` to
decide whether to decode a witness. That direction is already conservative
(`Unknown` ⇒ no witness ⇒ `Nothing`), so leave the code alone but extend its
haddock (the block starting at `src/Keiki/Symbolic.hs:783`) to state explicitly
that `Nothing` means "no model was found — the predicate is unsatisfiable *or*
the solver gave up (`Unknown`)", so callers must not read `Nothing` as a proof of
emptiness; `symIsBot` (post-fix) is the function whose `True` is a proof.
`isSingleValuedSym`, `checkTransitionDeterminismSym`, and `checkDeadEdgesSym` all
inherit the fix through `isBot`/`symIsBot` and need only haddock touch-ups noting
the new failure direction (a solver give-up now surfaces as a warning for the
determinism checks, and as *silence* for the dead-edge check — each the safe
direction for what the answer is used for).

Tests, in `test/Keiki/SymbolicSpec.hs` (a new `describe "satResultIsProvablyUnsat"`
block). `Data.SBV` exports `SatResult(..)`, `SMTResult(..)`, `SMTReasonUnknown(..)`
and the `z3` config value, so build the give-up cases by hand and get the definite
cases from tiny real solver calls (z3 is on `PATH` in the test environment):

```haskell
it "treats Unknown as NOT provably empty (the old code inverted this)" $ do
  let unk = SBV.SatResult (SBV.Unknown SBV.z3 SBV.UnknownTimeOut)
  satResultIsProvablyUnsat unk `shouldBe` False

it "treats ProofError as NOT provably empty" $ do
  let err = SBV.SatResult (SBV.ProofError SBV.z3 ["boom"] Nothing)
  satResultIsProvablyUnsat err `shouldBe` False

it "trusts a definite Unsat / rejects a definite Sat" $ do
  unsat <- SBV.sat (pure SBV.sFalse :: SBV.Symbolic SBV.SBool)
  satisf <- SBV.sat (pure SBV.sTrue :: SBV.Symbolic SBV.SBool)
  satResultIsProvablyUnsat unsat `shouldBe` True
  satResultIsProvablyUnsat satisf `shouldBe` False
```

(If the `Unknown`/`ProofError` constructors' argument lists differ under the
installed sbv version — the cabal bound is `>=11.7 && <15` — adjust the
hand-built values to match; the constructors and their exports were verified
against the sbv sources at
`/Users/shinzui/Keikaku/hub/haskell/sbv-project/sbv/Data/SBV/Core/Symbolic.hs:2271-2276`.)

Optional prototype (clearly scoped as such): try to provoke a *real* end-to-end
`Unknown` deterministically, so the whole `symIsBot` pipeline is covered, not just
the verdict function. SBV provides `setTimeOut :: Integer -> m ()` inside the
`Symbolic` monad (milliseconds, passed to z3). A throwaway test can call `SBV.sat`
on a deliberately hard constraint — nonlinear integer arithmetic (e.g.
`x*x*x + y*y*y .== 29` style multiplication chains over large free integers) or a
recursive string constraint — with `setTimeOut 1`. Promotion criterion: the query
yields `Unknown` on 10 consecutive runs on the development machine; then wire an
internal variant of `symIsBot` that accepts an extra `SBV.Symbolic ()`
preamble (not exported; used only by the test) and assert the end-to-end verdict
is `False`. Discard criterion: the tiny timeout races (sometimes solving,
sometimes not) — then delete the prototype, keep only the pure-function tests, and
record the observed flakiness in Surprises & Discoveries.

Acceptance: `cabal test all` passes; the new spec block passes; before the
`symIsBot` rewire, the hand-built-`Unknown` expectation written against the *old*
composition (`not (SBV.modelExists unk)`) would be `True` — i.e. the test fails
before and passes after. `checkDeadEdgesSym` on any existing fixture emits no new
warnings (its verdicts only ever move from "dead" to "silent" under this change).


### Milestone 2 — exact encodings: machine words and picosecond time

Scope: the `Sym` instances in `src/Keiki/Symbolic.hs:138-229` and regression tests
in `test/Keiki/SymbolicSpec.hs`. At the end of this milestone, a guard overlap
that exists only because of `Word8` wraparound (or a sub-second time bound) is
found by the solver.

Change the six fixed-width instances so each type is its own `SymRep` — SBV has
native exact support (`SBV Word8` is z3's 8-bit bitvector with modular
semantics, and likewise for the others), and all six types already satisfy the
constraints the discovery registries require (`SBV.SymVal`, `SBV.OrdSymbolic (SBV
(SymRep r))`, `Num (SBV (SymRep r))`):

```haskell
instance Sym Word64 where
  type SymRep Word64 = Word64
  toSym = id
  fromSym = id
  symDefault = 0
```

…and the same shape for `Word32`, `Word16`, `Word8`, `Int64`, `Int32`. Delete the
"over-approximation" comment block at `src/Keiki/Symbolic.hs:152-163` and replace
it with a short note that fixed-width types are modeled exactly (wraparound
included) since this plan, while `Int`/`Integer` stay unbounded — and add the
`Int`-wraparound caveat to the `Sym Int` haddock (`src/Keiki/Symbolic.hs:144-150`).
No changes are needed in `discoverSym`/`discoverSymOrd`/`discoverSymNum`
(dispatch is on the Haskell type, which is unchanged), in `memoFree` (the cache is
keyed by name and checked by `TypeRep` of the *rep* type, still one type per
name), or in `readModel`/`extractRegFile` (`SBV.getModelValue` works at any
`SymVal` type). Guards never mix operand types (`PEq`/`PCmp`/`TArith` are
homogeneous in `r`), so no cross-width coercion sites exist.

Change `Sym UTCTime` (`src/Keiki/Symbolic.hs:225-229`) to picosecond resolution.
`utcTimeToPOSIXSeconds` yields a `NominalDiffTime`, which is exactly a fixed-point
picosecond count (`Pico = Fixed E12`); unwrap it losslessly with `Data.Fixed
(Fixed (MkFixed))` and `Data.Time.Clock (nominalDiffTimeToSeconds,
secondsToNominalDiffTime)`:

```haskell
instance Sym UTCTime where
  type SymRep UTCTime = Integer
  toSym t = let MkFixed ps = nominalDiffTimeToSeconds (utcTimeToPOSIXSeconds t) in ps
  fromSym ps = posixSecondsToUTCTime (secondsToNominalDiffTime (MkFixed ps))
  symDefault = posixSecondsToUTCTime 0
```

Update the haddock (the current one at `src/Keiki/Symbolic.hs:220-224` documents
the truncation as intentional; it no longer is). Then run the full test suite. If
an existing test in `test/Keiki/SymbolicSpec.hs` or
`jitsurei/test/Jitsurei/OrderCartSymbolicSpec.hs` asserted second-granularity
round-tripping, fix the test if the new exact behavior is simply *better*; only if
something genuinely depends on truncation (fallback criterion in the Decision Log)
revert the instance and add the loud caveats instead — and record which path was
taken in the Decision Log.

Regression tests (new `describe` blocks in `test/Keiki/SymbolicSpec.hs`, following
the existing fixture style in that file, e.g. the `AmountRegs` fixture near the
top). First, the `Word8` wraparound overlap the old encoding missed. Build a
two-edge fixture over `'[ '("w", Word8)]` with an epsilon-style trivial command
(reuse the `AmtCmd`/`KnownInCtors` pattern already in the file), guards:

- edge A: `PCmp CmpLe (TArith OpAdd (proj wIdx) (TLit 6)) (TLit 5)` — "w + 6 <= 5"
- edge B: `PCmp CmpGe (proj wIdx) (TLit 250)` — "w >= 250"

Concretely these co-hold at `w = 255` (255 + 6 wraps to 5, and 5 <= 5; 255 >= 250)
— verify inside the test with `evalPred`. Under the old unbounded-`Integer`
encoding the conjunction is `x <= -1 && x >= 250`, unsatisfiable, so
`checkTransitionDeterminismSym` returned `[]` and `isSingleValuedSym` returned
`True` — the gate passed while the runtime was ambiguous. Assert the new behavior:
`checkTransitionDeterminismSym fixture` is non-empty and `isSingleValuedSym
(withSymPred fixture)` is `False`. Second (only if the picosecond encoding is
kept), the sub-second time overlap: guards `t .> 12:00:00.2` and `t .< 12:00:00.9`
(as `PCmp` over a `UTCTime` register against `TLit` timestamps built with
`posixSecondsToUTCTime`). Under the old rounding these became `t > 0 && t < 1`
over whole-second integers — unsatisfiable — while concretely `12:00:00.5`
satisfies both; assert the pair is now flagged.

Acceptance: both new tests fail on the pre-milestone code and pass after;
`cabal test all` (including the jitsurei suite) is green.


### Milestone 3 — a pure overlap check that sees through PAnd

Scope: `src/Keiki/Core.hs` (`provablyOverlap`, `determinismWarnings`'s
`overlapCtor`, haddocks) and `test/Keiki/ValidationSpec.hs`. At the end of this
milestone, `validateTransducer defaultValidationOptions t` — with no solver
anywhere — reports the motivating overlap `matchInCtor A .&& x .> 0` versus
`matchInCtor A .&& x .> 5`, still without any possibility of a false positive.

The contract, restated: `provablyOverlap g1 g2` must return `True` only when a
concrete `(regs, ci)` satisfying *both* guards provably exists ("provably
co-satisfiable"), and `False` both when the guards are provably disjoint and when
the answer is unknown. `provablyOverlap` is private to `src/Keiki/Core.hs` (it is
not in the export list), so its signature may change freely; keep the exported
`checkTransitionDeterminismPure` and the internal `determinismWarnings` calling
shapes unchanged.

The algorithm. A guard is *in the fragment* when it is a conjunction spine — the
guard is `PAnd` trees whose leaves ("atoms") are each one of: `PTop` (dropped);
`PInCtor ic`; or a comparison atom `PCmp op lhs rhs` / `PEq lhs rhs` in which one
side is a `TLit` and the other side is a *named variable* — a `TReg ix` (name it
`"reg/" <> slotName`, recovering the slot name from the `Index`'s `KnownSymbol`
leaf exactly as `Keiki.Symbolic.indexName` does at `src/Keiki/Symbolic.hs:481-483`;
write a private clone in Core, since Core must not import the SBV-backed module)
or a `TInpCtorField ic ix` (name it `"inp/" <> icName ic <> "/" <> fieldName`).
Comparisons with the literal on the left are normalized by flipping the relation.
An atom comparing two literals is evaluated concretely with the `Eq`/`Ord`
dictionary the `PEq`/`PCmp` constructor carries: constant-true atoms are dropped,
and a constant-false atom makes its guard unsatisfiable, so the verdict for the
pair is `False`. *Any* other leaf — `POr`, `PNot`, `PBot`, `PEq`/`PCmp` between
two non-literal terms, or any operand containing `TApp1`/`TApp2`/`TArith` — puts
the pair outside the fragment: return `False` (unknown; no warning; the z3 pass is
the exact gate).

With both guards in the fragment, decide in three steps:

1. *Constructor consistency.* Collect each guard's `PInCtor` names. Two different
   names inside one guard, or a nonempty name-set in each guard that disagrees
   across the pair, means "not provably overlapping" — return `False` (these are
   in fact provably disjoint, which lands on the same answer). Additionally — a
   soundness requirement, not an optimization — every `inp/<ctor>/…` variable
   appearing in a comparison atom must have its `<ctor>` equal to the pair's
   common `PInCtor` name (and such a name must exist): `evalTerm (TInpCtorField
   ic ix)` errors when the input is not `ic`'s constructor
   (`src/Keiki/Core.hs:792-794`), so a claimed witness touching a field of an
   unmatched constructor is not a witness. Violations ⇒ return `False` (unknown).
2. *Group by variable.* Pool the comparison atoms of *both* guards and group them
   by variable name. Two atoms on the same name always have the same operand type
   (a slot has one type in `rs`; a constructor field has one type in its schema),
   but the GADT has erased it — align the groups with `eqTypeRep` on the
   `Typeable r` evidence each atom carries, and treat any mismatch (impossible by
   construction) as unknown.
3. *Per-group provable satisfiability.* The variables are independent (every atom
   relates one variable to one literal), so the pair overlaps if every group is
   provably satisfiable — by either technique:
   - *Exact interval reasoning* for a curated registry of integral types (`Int`,
     `Integer`, `Word8/16/32/64`, `Int32/64`, discovered by `eqTypeRep` dispatch
     on the atom's `Typeable` evidence, mirroring the style of
     `Keiki.Symbolic.discoverSym` but pure and private to Core). Map each atom to
     an `Integer` interval — `x > c` ⇒ `[c+1, ∞)`, `x >= c` ⇒ `[c, ∞)`, dually
     for `<`/`<=`, `x == c` ⇒ `[c, c]` — intersect the group, clamp to the
     type's `[minBound, maxBound]` image (no clamp for `Integer`), and answer
     "provably satisfiable" iff the result is nonempty. This is exact because
     each registry type's `Ord` agrees with `Integer` order under `toInteger`
     and its values are precisely the integers in `[minBound, maxBound]`.
   - *Literal-witness probing* for every other type (`Text`, `UTCTime`, `Bool`,
     anything user-defined with `Ord`): the group is provably satisfiable if one
     of the literal values mentioned in the group satisfies *all* the group's
     atoms, checked concretely with each atom's captured `Eq`/`Ord` dictionary.
     (Represent each atom's check as a closure `r -> Bool` built at
     pattern-match time, where the constructor's dictionaries are in scope.)
     This proves things like `x == "a"` in both guards, or `t >= lit && t <=
     lit`; it deliberately cannot prove strict-bound combinations like
     `t > a && t < b` — those stay unknown, which is sound.

The preserved base cases fall out: two bare `PTop`s have empty atom sets and
consistent (empty) constructor sets ⇒ `True`; two bare `PInCtor`s with the same
name likewise ⇒ `True` — matching the current `src/Keiki/Core.hs:1804-1805`
behavior exactly. (Both, like the current code, assume the register and command
types are inhabited; note this in the haddock.) The motivating pair now proves:
common constructor `A`; one group for `x` with atoms `> 0` and `> 5`; intervals
`[1, ∞) ∩ [6, ∞) = [6, ∞)`, nonempty within any of the integral registry types ⇒
warning. And `x .> 5` versus `x .< 3` intersects to the empty interval ⇒ no
warning (provably disjoint), preserving zero false positives.

Also update `overlapCtor` inside `determinismWarnings`
(`src/Keiki/Core.hs:1831-1834`), which currently populates `tvwInCtor` only for
two *bare* `PInCtor` guards: make it return the common constructor name found
during the spine walk (expose a small helper from the new machinery), so keiro's
rendered warning names the ambiguous command constructor for Builder-authored
edges too. No `TransducerValidationWarning` constructor is added or changed
(Decision Log; EP-71 owns that surface), and no `ValidationOptions` field is
added — the strengthened check runs under the existing `checkDeterminism` flag.

Rewrite the haddocks to state the fragment *precisely*:
on `provablyOverlap` and `checkTransitionDeterminismPure`
(`src/Keiki/Core.hs:1763-1806`), enumerate what the pure pass can prove
(conjunction spines; same-constructor atoms; variable-vs-literal comparisons —
exact intervals on the integral registry, literal-witness probing elsewhere) and
what it cannot (disjunction, negation, arithmetic, opaque terms, var-vs-var,
strict-bound density questions on non-integral types), each answered "unknown, no
warning"; on `validateTransducer` (`src/Keiki/Core.hs:1609-1621`), keep the
"assert `== []` in unit tests" invitation but pair it with the explicit statement
that the pure pass proves overlap only in the documented fragment and that
`Keiki.Symbolic.checkTransitionDeterminismSym` (z3-backed) is the exact gate a
release should run.

Tests in `test/Keiki/ValidationSpec.hs` (new `describe "provable overlap through
PAnd spines"` block, building two-edge fixtures in the file's existing style —
directly with `Edge`/`SymTransducer` records or via `Keiki.Builder`, whichever
matches the neighboring tests):

- *True positive (the motivating pair):* edges guarded
  `PAnd (PInCtor icA) (PCmp CmpGt (proj xIdx) (TLit (0 :: Int)))` and
  `PAnd (PInCtor icA) (PCmp CmpGt (proj xIdx) (TLit 5))` ⇒
  `validateTransducer defaultValidationOptions t` contains exactly one
  `NondeterministicPair`, with `tvwInCtor == Just "A"`. This test fails before
  this milestone and passes after.
- *Zero false positives, disjoint:* same shape with `x .> 5` / `x .< 3` ⇒ no
  determinism warning. Also `Word8` bounds: `x .>= 200` / `x .<= 100` ⇒ none.
- *Zero false positives, unknown fragment:* a guard containing `POr`, and a guard
  whose comparison wraps a `TApp1` ⇒ no determinism warning.
- *Different constructors:* `PAnd (PInCtor icA) …` vs `PAnd (PInCtor icB) …` ⇒
  none.
- *Agreement with the exact pass:* for every fixture in the block, every pair the
  pure check flags is also flagged by `checkTransitionDeterminismSym` (pure ⊆
  symbolic). This is the zero-false-positive contract made executable — z3 is on
  `PATH` in the test environment.

Acceptance: the true-positive test fails before and passes after; all existing
`ValidationSpec` and `SymbolicSpec` tests still pass (any *new* warning on an
existing fixture must be manually confirmed as a true overlap before adjusting
the fixture or the expectation — record such cases in Surprises & Discoveries).


### Milestone 4 — documentation, changelog, and consumer notes

Scope: haddocks in `src/Keiki/Symbolic.hs` and `src/Keiki/Core.hs`,
`CHANGELOG.md`. At the end, the failure modes a consumer can hit are documented at
the surfaces where they will hit them.

On the `BoolAlg (SymPred rs ci)` instance (`src/Keiki/Symbolic.hs:568-575` — the
haddock block above it), document that `isBot` performs an external z3 solver call
through `unsafePerformIO`: if the z3 binary is not on `PATH`, evaluating `isBot`
(and therefore `isSingleValuedSym`, `checkTransitionDeterminismSym`,
`checkDeadEdgesSym`, and any `validateTransducer`-style sweep a caller builds over
this carrier) throws an exception *from pure code* (SBV's solver-not-found
error). Name the operational requirement (z3 on `PATH`; the nix dev shell
provides it) and cross-reference from the `symIsBot` haddock, which is currently
the only place the `unsafePerformIO` justification lives. Keep the existing
per-function "Requires z3 on @PATH@" notes.

Update `CHANGELOG.md` (top, under the unreleased/0.1.0.0 section, matching the
file's existing format) with entries for: the `symIsBot` Unknown-direction fix
(behavioral: previously-blessed guard pairs may now warn — these are true
positives); the exact fixed-width and picosecond-time encodings (behavioral:
previously-missed wraparound/sub-second overlaps are now found); the strengthened
pure overlap check (behavioral: `validateTransducer` may newly report
`NondeterministicPair` on Builder-authored edges — true positives); the additive
`satResultIsProvablyUnsat` export. State the consumer guidance explicitly: no
names or signatures changed; current keiro validation that newly fails is surfacing
real defects the old gates missed, and the fix is in
the flagged transducer, not in pinning keiki.

Finish with `nix fmt -- --no-cache`, a final `cabal build all && cabal test all`,
and update this plan's Progress, Decision Log (encoding fallback outcome, any
constructor-coordination note for EP-71), and Outcomes & Retrospective.

Acceptance: `cabal haddock keiki` builds without new warnings; the changelog
renders the four entries; all living sections of this plan reflect the final
state.


## Concrete Steps

All commands run from the repository root, `/Users/shinzui/Keikaku/bokuno/keiki`.

```bash
nix develop            # provides GHC 9.12, cabal, z3 on PATH
cabal build all        # must be green before starting
cabal test all         # baseline: must be green before starting
```

Confirm the solver is available (the symbolic tests need it):

```bash
which z3               # expect a store path, e.g. /nix/store/…/bin/z3
```

Per milestone, the loop is: edit the files named in the milestone, then

```bash
cabal build all
cabal test all
```

To run just the affected specs while iterating (hspec pattern match):

```bash
cabal test keiki-test --test-options='--match "satResultIsProvablyUnsat"'
cabal test keiki-test --test-options='--match "provable overlap"'
```

A successful full run ends like:

```text
All N examples passed. (or: N examples, 0 failures)
Test suite keiki-test: PASS
```

Fail-before/pass-after evidence: for each milestone's headline test, run the test
*before* applying the source fix (expect a failure naming the new expectation),
then apply the fix and re-run (expect pass). Capture both transcripts into
Surprises & Discoveries.

Before committing (commit per milestone, Conventional Commits style, e.g.
`fix(symbolic): treat solver Unknown as not-provably-empty in symIsBot`):

```bash
nix fmt -- --no-cache
git add -p && git commit
```


## Validation and Acceptance

The change is effective when all of the following are observable, in this
repository, via `cabal test all` inside `nix develop`:

1. *Unknown direction.* `satResultIsProvablyUnsat (SBV.SatResult (SBV.Unknown
   SBV.z3 SBV.UnknownTimeOut))` is `False`. Written against the pre-fix
   interpretation (`not . SBV.modelExists`), the same input yields `True` — the
   defect, pinned by a test that fails before and passes after.
2. *Wraparound overlap found.* The Milestone 2 `Word8` fixture — guards
   `w + 6 <= 5` and `w >= 250`, concretely co-satisfied at `w = 255` (asserted via
   `evalPred` in the same test) — yields a non-empty
   `checkTransitionDeterminismSym` result and `isSingleValuedSym (withSymPred t)
   == False`. Before Milestone 2 both report the pair disjoint.
3. *Sub-second overlap found* (if the picosecond encoding is kept): the
   `t > …00.2` / `t < …00.9` fixture is flagged by
   `checkTransitionDeterminismSym`; before, it was blessed.
4. *Pure pass catches the Builder shape.* For the motivating fixture,
   `validateTransducer defaultValidationOptions t` contains a
   `NondeterministicPair` with `tvwInCtor = Just "A"`; before Milestone 3 it is
   `[]`.
5. *Zero false positives preserved.* The disjoint (`x .> 5` vs `x .< 3`),
   unknown-fragment (`POr`, `TApp1`), and different-constructor fixtures produce
   no determinism warning, and the agreement test shows every purely-flagged pair
   is also z3-flagged.
6. *Nothing regressed.* The entire pre-existing suite (including
   `jitsurei/test/Jitsurei/OrderCartSymbolicSpec.hs`, whose `Word64` money
   fixtures exercise the changed encodings) passes, and `cabal haddock keiki`
   builds cleanly.

Downstream coordination: current keiro compiles against the new keiki without
symbolic API name/signature changes or warning-constructor additions. If its suite reports
new warnings, each is a true positive by construction of the checks above — the
expected, desirable migration recorded in the changelog.


## Idempotence and Recovery

Every step is an ordinary source edit plus a test run; all are safe to repeat.
Milestones are independent commits, so a bad state recovers with
`git restore <file>` (or `git revert <sha>` after commit) without touching the
other milestones. The riskiest single change is the `Sym UTCTime` encoding
(Milestone 2), which has an explicit, pre-agreed fallback: revert the instance to
round-to-seconds and switch to the documented-caveat variant, recording the
outcome in the Decision Log. The optional Unknown-provocation prototype in
Milestone 1 has explicit promote/discard criteria and touches only test code. If
`cabal test all` fails in an unrelated suite after an edit, suspect a genuinely
newly-surfaced true positive first (see Milestone 3 acceptance) before weakening
any check.


## Interfaces and Dependencies

Libraries: `sbv` (bounds `>=11.7 && <15` in `keiki.cabal`; symbolic terms and the
z3 driver; sources for verification on disk at
`/Users/shinzui/Keikaku/hub/haskell/sbv-project/sbv/`), `time` (`Data.Time.Clock`:
`nominalDiffTimeToSeconds`, `secondsToNominalDiffTime`), `base` (`Data.Fixed
(Fixed (MkFixed))`), `hspec` (tests). No new dependencies. z3 must be on `PATH`
for the test suite and for any consumer using `Keiki.Symbolic`; the nix dev shell
provides it.

At the end of the plan the following hold, with full module paths:

- `Keiki.Symbolic.satResultIsProvablyUnsat :: Data.SBV.SatResult -> Bool` — new,
  exported, pure; `True` only for `Unsatisfiable`.
- `Keiki.Symbolic.symIsBot :: HsPred rs ci -> Bool` — signature unchanged;
  verdict now routed through `satResultIsProvablyUnsat`.
- `Keiki.Symbolic.symSatExt`, `Keiki.Symbolic.isSingleValuedSym`,
  `Keiki.Symbolic.withSymPred`, `Keiki.Symbolic.checkTransitionDeterminismSym`,
  `Keiki.Symbolic.checkDeadEdgesSym` — names and signatures unchanged; behavior of the determinism/dead-edge checks
  changes only via `symIsBot` and the encodings.
- `Keiki.Symbolic.Sym` instances: `SymRep Word8 = Word8` (and likewise
  `Word16/32/64`, `Int32/64`); `SymRep UTCTime = Integer` at picosecond
  resolution (or documented-caveat fallback per the Decision Log); `Sym Int` /
  `Sym Integer` unchanged and documented.
- `Keiki.Core.provablyOverlap` — private; spine-walking, three-way-internally
  (overlap / disjoint / unknown), `Bool`-externally; zero false positives.
- `Keiki.Core.checkTransitionDeterminismPure`, `Keiki.Core.validateTransducer`,
  `Keiki.Core.ValidationOptions`, `Keiki.Core.TransducerValidationWarning` —
  exported surfaces unchanged in shape (no new constructors, no new options
  field; coordination with EP-71 per the Decision Log); `determinismWarnings`
  populates `tvwInCtor` for spine guards.
