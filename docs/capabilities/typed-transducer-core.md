---
title: "Typed transducer authoring and forward execution"
type: Capability
description: "Declare an aggregate or workflow once as a typed symbolic-register transducer and make deterministic forward decisions from that single declaration."
generated:
  by: adopt-capabilities/0.9.2
  at: "2026-08-08T00:00:00Z"
capabilityId: CAP-1
provider: mori://shinzui/keiki
status: shipped
stability: experimental
since: "0.1.0.0"
packages:
  - keiki
interface:
  - Keiki.Core
  - Keiki.Builder
  - Keiki.Operators
  - Keiki.NoThunks
evidence:
  - kind: test
    resource: test/Keiki/BuilderSpec.hs
    proves: The monadic authoring DSL builds well-formed transducers and reports eager builder defects.
  - kind: test
    resource: test/Keiki/StepEitherSpec.hs
    proves: Forward decisions succeed or fail with a structured StepFailure carrying the selected edge and post-state.
  - kind: test
    resource: test/Keiki/CoreSpec.hs
    proves: The register-file, predicate, command, event, and output algebra evaluate concretely without a solver in the hot path.
  - kind: example
    resource: jitsurei/src/Jitsurei/EmailDelivery.hs
    proves: A complete worked aggregate authored end to end against the public Builder DSL.
---

# Typed transducer authoring and forward execution

keiki gives you one modelling primitive — the symbolic-register finite-state
transducer — and one place to declare it. A consumer describes an aggregate,
workflow, or durable process a single time as a `SymTransducer` over a typed
register file (`RegFile rs`), predicate-labelled guards, commands, and
list-shaped event output, then reads forward decisions out of that declaration.

## What you adopt

- **The core algebra** (`Keiki.Core`): the typed `RegFile rs`, the
  `SymTransducer` GADT, and the slot / predicate / command / event / output
  vocabulary. Edge output is list-shaped (`output :: [OutTerm rs ci co]`), so a
  single command can emit zero, one, or many events in declaration order.
- **The authoring DSL** (`Keiki.Builder`): a monadic edge builder (`from`,
  `onCmd`, `onEpsilon`, `goto`, `emit` / `emitWith` / `noEmit`, and the
  register writes `.=` / `=:` / `reg`). Finalization is eager:
  `buildTransducerEither` returns every located `BuilderError`, and
  `buildTransducer` keeps the exception-based convenience path.
- **Forward execution**: `step`, the diagnostic `stepEither` / `StepFailure`
  surface, and (since 0.7.0.0) the proof-relevant `stepDetailedEither` /
  `StepSuccess` that expose the selected `EdgeRef`, mode, post-state, registers,
  and ordered output word. `delta` / `omega` / `runUpdate` use concrete
  predicate evaluation with snapshot (parallel-assignment) update semantics.
- **Strictness assertions** (`Keiki.NoThunks`): `noThunks`-based checks over
  `RegFile` and per-vertex state for long-running embedders.

## Shortest real usage

```haskell
emailDelivery = B.buildTransducer EmailPending emptyRegFile
                  (\case EmailSentVertex -> True; _ -> False) do
  B.from EmailPending do
    B.onCmd inCtorSendEmail $ \d -> B.do
      B.slot @"emailRecipient" .= d.recipient
      B.emit wireEmailSent EmailSentTermFields { recipient = d.recipient, .. }
      B.goto EmailSentVertex
```

`stepEither emailDelivery EmailPending emptyRegFile someCommand` returns the next
vertex, updated registers, and emitted events, or a `StepFailure` explaining why
no edge fired.

## Limits

- **Every edge must declare output intent.** Since 0.1.0.0 a body that reaches
  `goto` without `emit` / `emitWith` / `noEmit` is a build error, not a silent
  ε-edge. This is deliberate but is a migration hazard for code written against
  pre-release drafts.
- **Register slot names must satisfy `DistinctNames`.** Duplicate slot names are
  a compile-time rejection, not a first-wins resolution.
- **Concrete evaluation only.** Forward stepping never calls the solver; nothing
  in this record depends on z3. Solver-backed reasoning is a separate capability
  (`CAP-4`).
- **The `NoThunks` scope is narrow.** Only data-bearing state (`RegFile`,
  `Composite`) has instances; function-bearing types are excluded because
  `NoThunks` cannot inspect closures, so those assertions would be vacuous.
- The categorical and codec concerns are intentionally elsewhere: replay
  (`CAP-2`), composition (`CAP-7`), and serialization (`CAP-11`) each ship as
  their own capability. This record is the base every other capability requires.
