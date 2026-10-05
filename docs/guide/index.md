---
okf_version: "0.2"
---

# Subdirectories

- [diagrams/](diagrams/index.md)

# Files

- [profile.dhall](profile.dhall)

# Explanation

- [Modeling collections](modeling-collections.md) - Understand the analysis trade-offs of collection registers and choose scalar projections or separate aggregates.
- [Why keiki uses an SMT solver](why-smt.md) - Understand why Keiki uses an SMT solver, which bugs symbolic analysis detects, and its limitations.

# Guide

- [Architecture Decision Records (ADRs)](adr-conventions.md) - Write and maintain architecture decision records using the shared ADR profile and repository conventions.
- [Authoring against the AST directly](ast-drop-down.md) - Hand-author transducer edges against the Core AST when the Builder DSL cannot express a model.
- [B-presentation views](b-views.md) - Derive and consume per-vertex B-presentation views that expose the register slots live at each control vertex.
- [Composition](composition.md) - Combine transducers with sequential composition, disjoint alternatives, and the experimental feedback1 cascade.
- [Deriving lifecycle transitions](deriving-lifecycle-transitions.md) - Model threshold-derived lifecycle transitions and place re-evaluation where state changes cannot silently miss them.
- [Generic-lens and label reads](generic-lens-and-label-reads.md) - Keep Keiki register labels resolving alongside generic-lens and handle operator-name collisions.
- [Multi-event commands](multi-event-commands.md) - Author multi-event edges and understand their snapshot, replay, composition, and rendering behavior.
- [Profunctor wrappers and variance combinators](profunctor.md) - Reshape transducer input and output alphabets with profunctor wrappers and variance combinators.

# Navigation

- [Keiki guides](README.md) - Find authoring tutorials, modeling guidance, interface references, and documentation maintenance commands.

# Reference

- [Mermaid rendering](mermaid-rendering.md) - Look up Mermaid rendering options, readable edge semantics, topology views, atlases, and validation helpers.
- [Output invertibility — which events round-trip on replay](output-invertibility.md) - Look up the replay invertibility contract, derived-field verification rules, diagnostics, and modeling recipes.
- [SCXML state-chart export](scxml-export.md) - Look up the descriptive SCXML export API, document subset, metadata comments, and verification procedure.

# Runbook

- [Symbolic CI](symbolic-ci.md) - Wire symbolic single-valuedness checks into CI and diagnose failures, solver requirements, and analysis costs.

# Tutorial

- [Loan Application — a worked tutorial](loan-application-tutorial.md) - Build a loan-underwriting workflow with evidence accumulation, threshold guards, B-views, and aggregate composition.
- [keiki User Guide](user-guide.md) - Learn to author aggregates, run forward decisions and replay, derive views, compose transducers, and use symbolic analysis.

