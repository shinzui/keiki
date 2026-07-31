# Bundle Update Log

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
