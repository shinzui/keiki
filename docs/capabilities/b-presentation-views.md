---
title: "Per-vertex B-presentation projections"
type: Capability
description: "Present the state of an aggregate as a per-vertex indexed record view derived from the same transducer declaration."
generated:
  by: adopt-capabilities/0.9.2
  at: "2026-08-08T00:00:00Z"
capabilityId: CAP-6
provider: mori://shinzui/keiki
status: shipped
stability: experimental
since: "0.1.0.0"
packages:
  - keiki
interface:
  - Keiki.Generics.TH
requires:
  - CAP-1
  - CAP-5
evidence:
  - kind: example
    resource: jitsurei/test/Jitsurei/UserRegistrationViewSpec.hs
    proves: deriveView presents each control vertex as its own record projection of the register file.
  - kind: example
    resource: jitsurei/test/Jitsurei/LoanApplicationViewSpec.hs
    proves: A multi-vertex workflow exposes a distinct typed view per vertex.
  - kind: example
    resource: jitsurei/test/Jitsurei/EmailDeliveryViewSpec.hs
    proves: A minimal aggregate's B-view agrees with its register file at each vertex.
---

# Per-vertex B-presentation projections

The register-file transducer is keiki's "C-foundation": one flat register file
threaded through every vertex. The "B-presentation" is the opt-in dual — each
control vertex viewed as its own typed record of exactly the fields meaningful
there. `deriveView` produces that presentation from the same declaration, so a
consumer can hand UI and read models a per-state shape without maintaining a
second model. It builds on the core in [CAP-1](typed-transducer-core.md) and is
emitted by the derivation machinery in [CAP-5](generic-th-derivation.md).

## What you adopt

- **`deriveView`** (from `Keiki.Generics.TH`): a per-vertex record projection of
  the register file, indexed by control state.

## Shortest real usage

```haskell
deriveView ''UserRegistrationVertex ''UserRegistrationRegs
-- each vertex gets a record view of just the registers live at that vertex
```

## Limits

- **This is presentation, not a new source of truth.** The view is a projection
  of the register file; it adds no state and cannot diverge from the transducer,
  but it also does not persist independently.
- **Evidence is worked-example only.** The B-view is exercised entirely through
  the downstream `jitsurei` aggregates' `*ViewSpec` suites; there is no
  view-specific spec in the core package's own test tree. That makes its proof
  slightly weaker than capabilities backed by in-package specs — the guarantee is
  "these eight aggregates' views behave," not a property over arbitrary views.
- The exact release in which `deriveView` was introduced is 0.1.0.0 (it is listed
  in the initial Hackage release); later changelog entries do not revise it.
