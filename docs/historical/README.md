# Historical design notes

These notes record earlier directions the project explored before
landing on the symbolic-register transducer as the keiki core. They
are preserved here because they document the reasoning that produced
the current design, but they are *not* references for the shipped
library:

- Code examples typically use the toy `Transducer s c e` shape, the
  rejected `ExtTransducer` (EFSM) formalism, or the v1 prototype DSL
  with retired escape hatches (`OFn`, `PMatchC`, `unsafeCombine`,
  `TInpField`).
- Type signatures and module names predate the keiki rename.
- "Future directions" listed here have shipped, been deferred, or
  been declined under different names.

For the current design, read in order:

1. `docs/foundations/00-reading-guide.md` — entry point.
2. `docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`
   — the load-bearing design synthesis.
3. `docs/research/effects-boundary.md` — the pure-core / runtime split.
4. `docs/research/architecture-comparison-keiki-vs-crem.md` — where
   keiki sits relative to the closest neighbour library.
5. `docs/guide/user-guide.md` — how to author a transducer in
   practice.

## What's in this folder

| File | Subject | Superseded by |
|------|---------|---------------|
| `core-design-transducer-as-source-of-truth.md` | Early kernel sketch when the project was *fst-aggregate* | synthesis-c, architecture-comparison-keiki-vs-crem |
| `efsm-based-workflow-engine-technical-analysis.md` | Workflow-engine survey under the rejected EFSM formalism | data-direction-c, synthesis-c |
| `fst-as-workflow-runtime.md` | Runtime architecture sketch using `ExtTransducer` | effects-boundary |
| `future-directions-profunctors-effects-and-composition.md` | Pre-keiki "what we should build" | architecture-comparison-keiki-vs-crem |
| `orchestration-sagas-choreography-and-feedback-loops-as-transducers.md` | Saga / process-manager patterns in the toy formalism | composition-combinators-design, effects-boundary |
| `performance-analysis-projection-costs-and-production-architecture.md` | Perf analysis of the toy `Transducer s c e` formalism | symbolic-analysis-and-runtime-implications, `bench/README.md` |
| `workflow-modeling-approvals-pipelines-and-human-in-the-loop-as-transducers.md` | Workflow patterns catalogue in the toy formalism | docs/guide/user-guide.md, the worked examples in `jitsurei/` |
| `dsl-shape-for-symbolic-register.md` | v1 prototype DSL design with retired escape hatches | edge-builder-dsl-shape, `Keiki.Builder` haddock |
| `v1-escape-hatch-retirements-design.md` | Record of which v1 escape hatches were retired and what replaced them | (this is itself the historical record) |
