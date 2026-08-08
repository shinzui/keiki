---
title: "Static replay-safety and determinism validation"
type: Capability
description: "Run a pure build-time pass that reports the replay-safety and determinism defects that would make a transducer unsafe at a durable boundary."
generated:
  by: adopt-capabilities/0.9.2
  at: "2026-08-08T00:00:00Z"
capabilityId: CAP-3
provider: mori://shinzui/keiki
status: shipped
stability: experimental
since: "0.1.0.0"
packages:
  - keiki
interface:
  - Keiki.Core
requires:
  - CAP-1
evidence:
  - kind: test
    resource: test/Keiki/ValidationSpec.hs
    proves: validateTransducer emits the documented replay-safety and determinism warnings on defective transducers.
  - kind: test
    resource: test/Keiki/ValidationReplayAlignmentSpec.hs
    proves: The default validation warnings agree with what replay actually rejects.
  - kind: test
    resource: test/Keiki/CoreHiddenInputsGSMSpec.hs
    proves: Hidden-input detection requires the head event of a multi-event edge to recover every consumed command field.
---

# Static replay-safety and determinism validation

`validateTransducer` is the build-time gate a consumer runs to learn whether a
transducer is safe to admit to a durable boundary — before any event is stored.
It returns structured warnings from a pure pass; no solver is required. It is the
static counterpart to runtime replay (`CAP-2`) and depends on the core
declaration in [CAP-1](typed-transducer-core.md).

## What you adopt

- **`validateTransducer` with `defaultValidationOptions`**, whose default checks
  cover hidden command inputs, head-event recoverability, cross-edge inversion
  ambiguity, constructor guards before input-field reads, state-changing ε-edges,
  forward determinism, and possibly-dead edges.
- **Typed warnings**: `TransducerValidationWarning` constructors including
  `HeadUnrecoverable`, `InversionAmbiguity`, `UnguardedInputRead`,
  `StateChangingEpsilon`, and `NondeterministicPair`.
- **The pure determinism pass**, which proves guard overlap through supported
  conjunction spines (constructor consistency, exact integral intervals,
  concrete literal witnesses).

## Shortest real usage

```haskell
validateTransducer defaultValidationOptions transducer :: [TransducerValidationWarning]
```

An empty list is the go-ahead; each warning names the offending edge.

## Limits

- **The pure pass is deliberately incomplete.** Unsupported disjunctions,
  negations, arithmetic, opaque terms, and variable-to-variable comparisons
  produce no pure warning. The exact gate for those is the opt-in solver-backed
  analysis `CAP-4`, which requires z3. Absence of a warning here is not proof of
  safety.
- **Opaque-guard auditing is opt-in**, not part of the default option set.
- **The check set grew after 0.1.0.0.** Four of the default replay-safety checks
  (head recoverability, inversion ambiguity, guard-implies-input-read,
  state-changing ε) were added in 0.2.0.0. A consumer pinning 0.1.0.0 validates
  against a smaller set. Record-update `defaultValidationOptions` rather than
  constructing `ValidationOptions` from scratch so future checks stay enabled.
- New `NondeterministicPair` warnings on a previously-quiet transducer are true
  positives to repair, not noise to suppress.
