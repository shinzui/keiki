# Bundle Update Log

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
