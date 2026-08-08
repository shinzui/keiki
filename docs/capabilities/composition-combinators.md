---
title: "Composition and profunctor combinators"
type: Capability
description: "Build larger transducers from smaller ones with checked sequential composition, alternation, feedback, and profunctor/category/arrow instances."
generated:
  by: adopt-capabilities/0.9.2
  at: "2026-08-08T00:00:00Z"
capabilityId: CAP-7
provider: mori://shinzui/keiki
status: shipped
stability: experimental
since: "0.1.0.0"
packages:
  - keiki
interface:
  - Keiki.Composition
  - Keiki.Profunctor
requires:
  - CAP-1
evidence:
  - kind: test
    resource: test/Keiki/CompositionSpec.hs
    proves: Sequential composition matches stepping the two stages in turn.
  - kind: test
    resource: test/Keiki/CompositionAlignmentSpec.hs
    proves: composeChecked reports constructor-name, arity, and boundary drift with source-edge locations.
  - kind: test
    resource: test/Keiki/CompositionHomomorphismSpec.hs
    proves: Stateful and multi-event sequential composition are homomorphic to event-by-event stepping.
  - kind: test
    resource: test/Keiki/ProfunctorSpec.hs
    proves: The Profunctor/Category/Strong/Choice/Arrow instances derive composite register evidence structurally, not by unsafeCoerce.
---

# Composition and profunctor combinators

An aggregate is often assembled from parts. keiki composes transducers while
keeping the boundary honest: `composeChecked` refuses a composition whose stages
do not actually align, and the categorical instances derive the composite
register evidence structurally rather than fabricating it. It operates on the
core declaration in [CAP-1](typed-transducer-core.md).

## What you adopt

- **`Keiki.Composition`**: `composeChecked` (checked sequential composition
  reporting constructor-name, field-arity, and mapped-boundary drift with
  source-edge locations, since 0.2.0.0), the raw `compose`, `alternative` (with
  concrete `PLeftArm` / `PRightArm` arm exclusion), and `feedback1`.
- **`Keiki.Profunctor`**: `SomeSymTransducer`, variance combinators, and the
  `Profunctor`, `Functor`, `Category`, `Strong`, `Choice`, and `Arrow`
  instances. Overlapping slots and poisoned mapped boundaries fail loudly with
  `CategoryOverlapError` / `PoisonedCompositionError`.

## Shortest real usage

```haskell
composeChecked stageA stageB :: Either [ComposeAlignmentWarning] (SymTransducer ...)
```

## Limits

- **The categorical surface is intentionally a fragment.** `Strong` and `arr`
  preserve forward behaviour but *cannot* preserve output inversion, so a
  composite built through them is not guaranteed replayable
  (`CAP-2`). Arbitrary function application is deliberately not added to the
  symbolic term AST merely to make `Arrow` fusion lawful.
- **`feedback1` is a two-copy cascade, not shared-aggregate feedback.** There is
  no `feedback1Checked`; do not read it as fixpoint state sharing.
- **`alternative` uses concrete arm guards**, not symbolic arm proofs.
- Meaning-changing profunctor transformations drop trusted wire evidence (since
  0.9.0.0), so a mapped boundary may no longer authorize
  substitution in `composeChecked`.
