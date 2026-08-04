# Bundle Update Log

## 2026-08-04
* **Addition**: IR-5 requests sound guard-aware inverse-candidate disjointness proofs so the
  default inversion audit can omit a same-head warning only when overlap is impossible; opaque,
  unsupported, and unproved pairs remain conservative warnings. Mori Workflow supplies the
  motivating `openSteps > 1` versus `openSteps == 1` reproducer.

## 2026-08-01
* **Status change**: IR-2 `planned` -> `implemented`. ExecPlan 81's detailed forward-success and
  replay-attribution APIs, laws, documentation, and performance evidence are integrated into public
  `master`. Hackage preferred metadata and public tags still stop at `0.6.0.0`, whose source lacks
  those APIs, so IR-2 remains unreleased.
* **Status change**: IR-3 `planned` -> `implemented`. ExecPlan 82 now makes released one-way field
  projections unverified for exact satisfiability, retains path-stable one-sided emptiness proofs,
  and concretely rechecks every `symSatExt` candidate. Focused and full tests, builds, native flake
  checks, and strict OKF validation all pass; publication remains separate release work.
* **Refinement**: IR-1 was revalidated while deriving the projection follow-ups; its stale Keiro
  `<0.4` adoption note now records the active `>=0.6 && <0.7` bounds and a model review.
* **Refinement**: IR-1 now distinguishes path-stable concrete-to-symbolic agreement from exact
  owner-domain satisfiability; only definite UNSAT remains a proof for the released one-way
  projection witness.
* **Addition**: IR-3 records that one-way `FieldProjection` values are currently reported as
  exact even though the symbolic carrier may contain values outside the getter image; it requests
  a conservative structured verification result without changing concrete projection behavior.
* **Status change**: IR-3 `proposed` -> `planned`. Its correctness repair is specified by ExecPlan
  82 (`docs/plans/82-classify-unconstrained-symbolic-field-projections-conservatively.md`).
* **Refinement**: IR-3 also closes the projection-model gap in `symSatExt` by requiring concrete
  validation of every returned full witness; failure to reconstruct remains distinct from UNSAT.
* **Addition**: IR-4 requests declaration-tagged exact projection domains, symbolic constraints,
  reconstruction, and counterexample attribution for finite enums and validated textual IDs. It
  is the upstream prerequisite for Keiro IR-12 and IR-14.
* **Refinement**: IR-4 now requires predicate-global owner-view consistency, canonical inverse
  laws, and the complete TypeID-style lexical domain; individual projection domains alone do not
  establish joint realizability.
* **Status change**: IR-4 `proposed` -> `planned`. Its exact-domain and model-extraction work is
  specified by ExecPlan 83
  (`docs/plans/83-add-exact-reconstructible-symbolic-field-projection-domains.md`).

## 2026-07-31
* **Addition**: IR-2 requests structured successful edge attribution for forward stepping and
  replay, including live/replay-only mode and completed multi-event input spans, so downstream
  conformance can distinguish guarded siblings without duplicating Keiki semantics.
* **Refinement**: IR-2 was revalidated against Hackage Keiki 0.6.0.0 and the public upstream tag
  set, recording their current skew and strengthening the request with contiguous replay-span
  partition, state-path continuity, epsilon-observability, and exact erasure laws.
* **Status change**: IR-2 `proposed` → `planned`. Accepted after technical validation;
  implementation is specified by ExecPlan 81
  (`docs/plans/81-expose-detailed-step-success-and-replay-attribution-traces.md`).
* **Implementation progress**: IR-2's additive detailed step/replay API, exact erasure examples,
  generated trace laws, documentation, and matched compatibility/detailed allocation benchmarks
  were implemented locally. IR-2 remained `planned` at this update; the 2026-08-01 lifecycle audit
  later advanced it to `implemented`, with `released` still gated on Hackage and a matching public
  upstream tag.

## 2026-07-28
* **Addition**: IR-1 requests typed symbolic field projections over mapped consumer-owned
  values, filed from Keiro (master plan 25 / research note 14 Experiment C) so the Keiki-side
  prerequisite for checked nested guards is recorded before any DSL syntax work begins.
* **Status change**: IR-1 `proposed` → `planned`. Validated against the codebase and accepted;
  implementation specified by ExecPlan 79
  (`docs/plans/79-typed-symbolic-field-projections-over-mapped-consumer-owned-values.md`).
* **Status change**: IR-1 `planned` → `released`. ExecPlan 79 is implemented and the
  coordinated `keiki`, `keiki-codec-json`, and `keiki-codec-json-test` 0.4.0.0 packages and
  documentation are published on Hackage; the release is tagged `v0.4.0.0`.
