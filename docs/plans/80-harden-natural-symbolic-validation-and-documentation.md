---
id: 80
slug: harden-natural-symbolic-validation-and-documentation
title: "Harden Natural symbolic validation and documentation"
kind: exec-plan
created_at: 2026-07-31T13:05:34Z
intention: "intention_01kyjq57qyezm8xdyme7w9x85g"
---

# Harden Natural symbolic validation and documentation

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Keiki recently added `Natural`—the arbitrary-precision non-negative integer from
`base`—to its symbolic equality and ordering registry. This follow-up makes that support
honest and complete at the validation boundary. After the work, the opt-in opaque-guard
audit identifies `Natural` arithmetic that the solver cannot interpret structurally, the
fast pure determinism validator reasons about the full `Natural` interval `[0, infinity)`,
and the public documentation accurately distinguishes structural equality/ordering from
opaque generic arithmetic.

The result is observable in `Keiki.ValidationSpec`: a `Natural` guard containing
`TArith` produces `OpaqueGuard`, while two edges guarded by `n > 1` and `n < 3` produce a
pure `NondeterministicPair` because `n = 2` satisfies both. The full Cabal and Nix gates
must remain green.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] (2026-07-31 13:00Z) Reviewed commit `af8a14f` and reproduced the three findings with
  GHCi probes: partial subtraction, a missed opaque-arithmetic audit, and a missed pure
  overlap.
- [x] (2026-07-31 13:05Z) Created this focused ExecPlan and associated it with the
  intention already carried by the `Natural` support commit.
- [x] (2026-07-31 13:08Z) Updated `Keiki.Core` so the opaque audit consults the numeric
  registry and the pure integral domain includes `Natural`.
- [x] (2026-07-31 13:10Z) Added regression fixtures for unsupported `Natural` arithmetic,
  supported `Int` arithmetic, and a strict-bound interior `Natural` overlap; the focused
  validation suite passes 27 examples with zero failures.
- [x] (2026-07-31 13:11Z) Corrected the subtraction rationale and refreshed the module
  Haddock, changelog, and current guides to distinguish the equality/ordering and arithmetic
  registries.
- [x] (2026-07-31 13:11Z) Extended ADR-0003 with the durable non-negative encoding,
  partial-arithmetic, opaque-audit, and pure-domain decisions.
- [x] (2026-07-31 13:14Z) Ran the 27-example focused validation suite, all four Cabal
  suites (806 examples total), `nix flake check`, and diff hygiene checks with zero
  failures.
- [x] (2026-07-31 13:14Z) Recorded the final evidence and prepared the change for a
  Conventional Commit carrying the required ExecPlan and Intention trailers.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- Observation: `Natural` subtraction is partial, not saturating. Evaluating
  `1 - 2 :: Natural` on GHC 9.12.4 raises `arithmetic underflow`.
  Evidence:

  ```text
  ghci> print ((1 - 2) :: Natural)
  *** Exception: arithmetic underflow
  ```

- Observation: before this follow-up, the opaque audit treated every `TArith` as
  structural even though `discoverSymNum @Natural` returns `Nothing` and the translator
  creates a fresh value. A one-edge `Natural` arithmetic fixture returned no warning.
  Evidence:

  ```text
  ghci> validateTransducer optsWithOpaqueAudit naturalArithmeticFixture
  []
  ```

- Observation: the pure validator used concrete mentioned literals as witnesses for
  `Natural`, so it missed a non-literal interior witness. The z3-backed validator found
  the overlap.
  Evidence:

  ```text
  ghci> checkTransitionDeterminismPure naturalInteriorOverlap
  []
  ghci> checkTransitionDeterminismSym naturalInteriorOverlap
  [DeterminismWarning {dwSource = False, dwEdgeA = 0, dwEdgeB = 1, ...}]
  ```


## Decision Log

Record every decision made while working on the plan.

- Decision: Keep `Natural` outside the type-wide symbolic arithmetic registry.
  Rationale: `TArith` includes subtraction, and Haskell's `Natural` subtraction throws
  `Underflow` when the mathematical result is negative. Ordinary SMT integer subtraction
  returns a negative integer instead, so registering the carrier would not preserve
  concrete behavior. An operation-specific arithmetic registry is outside this focused
  hardening change.
  Date: 2026-07-31

- Decision: Classify unsupported `TArith` carriers as opaque in the existing opt-in audit.
  Rationale: the symbolic translator already uses a sound, domain-constrained fresh value
  for this case. The audit should expose that loss of precision rather than implying that
  every structural arithmetic node reached the solver unchanged.
  Date: 2026-07-31

- Decision: Give the pure validator an explicit `Natural` domain with lower bound zero and
  no upper bound.
  Rationale: `Natural` is an integral discrete domain. Exact interval reasoning finds
  interior witnesses such as `2` for `n > 1 && n < 3`, while the generic literal-witness
  fallback cannot.
  Date: 2026-07-31

- Decision: Update ADR-0003 rather than create a new ADR.
  Rationale: `docs/adr/0003-proof-gates-fail-conservatively.md` already owns numeric
  encodings, conservative symbolic fallbacks, and the relationship between the pure and
  z3-backed validators. The `Natural` rule is a direct extension of that decision.
  Date: 2026-07-31


## Outcomes & Retrospective

The implementation met the original purpose without changing a public type signature or
the default validation policy. `warnOpaqueGuards` now exposes both `TApp` and unsupported
`TArith` fallbacks, while registry-backed `Int` arithmetic remains structural. The fast
pure overlap validator now finds the interior witness `n = 2` in the exact non-negative
`Natural` domain, and its warning pair is also present in the z3-backed result.

The stale saturation rationale was corrected in source comments, tests, the changelog,
current user guides, and the older symbolic-design research note. The guides now describe
the capability boundary as equality/ordering support versus numeric-registry support,
rather than presenting one undifferentiated curated type set. ADR-0003 records the durable
encoding and conservative-fallback rules.

Validation finished with 27 focused examples and four full Cabal suites totaling 806
examples, all with zero failures. `nix flake check` passed both the treefmt and pre-commit
checks, and `git diff --check` reported no whitespace errors. There are no known gaps left
within this plan; operation-specific `Natural` addition or multiplication could be a
future feature, but is intentionally outside this hardening change.


## Context and Orientation

`src/Keiki/Internal/SymbolicTypes.hs` defines the closed registry of types that Keiki can
recognize at runtime. It separately answers whether a registered type supports equality,
ordering, and numeric `TArith` translation. `Natural` supports equality and ordering but
not the numeric registry.

`src/Keiki/Symbolic.hs` maps a concrete `Sym a` carrier to an SBV representation. `Natural`
uses `Integer` and adds `value >= 0` whenever Keiki allocates a symbolic variable. A
`TArith` whose carrier is missing from `discoverSymNum` becomes a fresh symbolic value;
this is an over-approximation, meaning it may lose proof precision but cannot manufacture
an unsatisfiability proof.

`src/Keiki/Core.hs` owns two relevant pure checks. `opaqueGuardWarnings` walks guards when
`warnOpaqueGuards` is enabled and reports terms the symbolic layer cannot see through.
`discoverIntegralDomain` supplies lower and upper bounds to the fast, solver-free overlap
checker. Before this plan, the first check recognized only `TApp` closures and the second
did not include `Natural`.

`test/Keiki/ValidationSpec.hs` tests both validator paths. `test/Keiki/SymbolicSpec.hs`
tests the z3-backed registry, constraints, and witness extraction. Public explanations live
in `src/Keiki/Symbolic.hs`, `CHANGELOG.md`, `docs/guide/why-smt.md`,
`docs/guide/symbolic-ci.md`, and `docs/guide/user-guide.md`.

The relevant durable context is `docs/adr/0003-proof-gates-fail-conservatively.md`: only a
definite solver `Unsatisfiable` result proves a predicate empty, and approximations must
fail conservatively. This plan extends that ADR with the `Natural` representation and
arithmetic caveat. `docs/adr/0005-persisted-wire-identities-are-explicit-and-versioned.md`
is also relevant because the original change pins `CanonicalTypeName Natural`; this plan
does not alter that identity or its already-added golden coverage.


## Plan of Work

Milestone 1 hardens the two pure validators. In `src/Keiki/Core.hs`, import
`symbolicTypeSupportsNumeric` and make the term-opacity walker check the result carrier of
`TArith`. A carrier absent from the numeric registry is opaque; a supported carrier remains
structural and recursion continues into its operands. Add an explicit `Natural`
`IntegralDomain` whose conversion is `toInteger`, minimum is `Just 0`, and maximum is
`Nothing`. At the end of this milestone, narrow validation tests must demonstrate both new
behaviors without invoking z3 for the pure assertion.

Milestone 2 adds regression fixtures in `test/Keiki/ValidationSpec.hs`. One single-edge
fixture uses `tadd` over `Natural` and must produce `OpaqueGuard` only when the opt-in audit
is enabled. A two-edge fixture uses `n > 1` and `n < 3`; the pure validator must report the
same edge pair that the symbolic validator reports. Retain a supported `Int` arithmetic
case or equivalent assertion so the broader audit does not misclassify arithmetic that
`discoverSymNum` handles structurally.

Milestone 3 corrects public documentation. Replace every statement that `Natural`
subtraction saturates with the actual behavior: negative results throw `Underflow`, which
ordinary SMT integer subtraction does not model. Add `Natural` to all current curated-type
lists, state that its equality and ordering are structural, and state that generic
`TArith @Natural` is opaque. Update ADR-0003 with the durable encoding rule.

Milestone 4 validates and records the result. Run the targeted validation and symbolic
specs, then the whole Cabal project and Nix formatting/pre-commit checks. Update this living
plan with exact counts and any surprises before committing.


## Concrete Steps

Run all commands from `/Users/shinzui/Keikaku/bokuno/keiki`.

First exercise the focused tests:

```bash
cabal test keiki:keiki-test \
  --test-options='--match Keiki.Core.validateTransducer' \
  --test-show-details=direct
```

Expected evidence includes the new opaque arithmetic and `Natural` interior-overlap examples
with zero failures.

Then run every package test:

```bash
cabal test all --test-show-details=direct
```

The baseline before this plan was four passing suites and 803 Hspec examples. The final
run passes four suites with 806 examples and zero failures.

Run repository formatting and pre-commit checks:

```bash
nix flake check
```

Expected final lines include:

```text
checks.aarch64-darwin.treefmt
checks.aarch64-darwin.pre-commit
```

Finally inspect hygiene and the exact change:

```bash
git diff --check
git status --short
git diff --stat
```


## Validation and Acceptance

Acceptance requires all of the following observable behavior:

With `warnOpaqueGuards = True`, a guard that compares a `TArith @Natural` result produces
an `OpaqueGuard` naming the edge. The same transducer under `defaultValidationOptions`
retains backward-compatible behavior because the advisory audit remains off.

For two `Natural` edges guarded by `n > 1` and `n < 3`,
`checkTransitionDeterminismPure` reports their overlap. The z3-backed
`checkTransitionDeterminismSym` reports the same pair, preserving the invariant that every
pure warning is contained in the symbolic result.

An `Int` `TArith` handled by the numeric registry remains structural and does not produce
an `OpaqueGuard`. Existing `Natural` equality, ordering, witness extraction, shape-name,
and JSON tests continue to pass.

No current documentation says `Natural` subtraction saturates. Current user guides list
`Natural` among equality/ordering carriers and explicitly identify its generic arithmetic
as opaque. The full Cabal and Nix gates pass.


## Idempotence and Recovery

All source, test, documentation, and ADR edits are ordinary text changes and are safe to
repeat. Cabal and Nix checks are read-only with respect to tracked source. If a focused
test fails, rerun it after correcting the fixture; no database, generated artifact, or
external state must be restored. Preserve unrelated working-tree changes and never use a
destructive Git reset.


## Interfaces and Dependencies

The implementation uses only existing dependencies. `base` supplies
`Numeric.Natural.Natural`; its `Num` subtraction throws `Underflow` for a negative result.
SBV remains the solver interface already wrapped by `Keiki.Symbolic`; no version or bound
changes are needed.

`Keiki.Internal.SymbolicTypes.symbolicTypeSupportsNumeric :: SymbolicType r -> Bool` is the
single source of truth for whether `translateTermSym` interprets `TArith` structurally.
`Keiki.Core` must use the same query for opaque diagnostics.

`Keiki.Core.discoverIntegralDomain` remains internal and returns
`Maybe (IntegralDomain r)`. Its `Natural` branch must construct
`IntegralDomain toInteger (Just 0) Nothing`.

No public data constructors or function signatures change. `OpaqueGuard` remains the
existing advisory warning, and `warnOpaqueGuards` remains disabled in
`defaultValidationOptions`.


Revision note (2026-07-31): Completed the implementation, expanded the stale-documentation
audit to the historical symbolic-design note, and recorded final Cabal, Nix, and diff
validation evidence.
