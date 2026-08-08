---
title: "Generic and Template Haskell derivation of constructors and wire schemas"
type: Capability
description: "Derive input constructors, event wire constructors, and their trusted structural schemas from record types instead of hand-writing them."
generated:
  by: adopt-capabilities/0.9.2
  at: "2026-08-08T00:00:00Z"
capabilityId: CAP-5
provider: mori://shinzui/keiki
status: shipped
stability: experimental
since: "0.1.0.0"
packages:
  - keiki
interface:
  - Keiki.Generics
  - Keiki.Generics.TH
requires:
  - CAP-1
evidence:
  - kind: test
    resource: test/Keiki/Generics/THSpec.hs
    proves: The *All and deriveAggregate splices emit the expected input/wire constructors and views for record-payload aggregates.
  - kind: test
    resource: test/Keiki/WireSchemaSpec.hs
    proves: Derived wire constructors carry Generic-derived structural schemas classified without diagnostic names.
  - kind: test
    resource: test/Keiki/InputSchemaSpec.hs
    proves: Input constructors carry the structural constructor path and typed slot spine used for alignment.
---

# Generic and Template Haskell derivation

Hand-writing an `InCtor` per command and a `WireCtor` per event is boilerplate
that also has to be trustworthy — composition and symbolic exclusion rely on the
constructor evidence being sound. keiki derives both from your record types and
attaches the structural schema that later proofs read. It layers on the core
declaration in [CAP-1](typed-transducer-core.md).

## What you adopt

- **`Keiki.Generics.TH`**: `deriveAggregateCtors`, `deriveWireCtors`,
  `deriveView`, the zero-enumeration `*All` splices
  (`deriveAggregateCtorsAll`, `deriveWireCtorsAll`), the fused
  `deriveAggregate`, and the `*With` variants for per-constructor suffix
  overrides and exclusions.
- **`Keiki.Generics`**: `RegFieldsOf`, `GRecord`, `EmptyRegFile`, and the
  trusted `Via` constructors `mkInCtorVia` / `mkInCtorRecordVia` /
  `mkWireCtorVia` / `mkWireCtorRecordVia`.
- **Structural head classification**: `classifyWireHeads`,
  `classifyInputHeads`, and `classifyInputWireHeads` expose proof-safe
  equal / different / unwitnessed relations without treating diagnostic
  constructor names as evidence.

## Shortest real usage

```haskell
deriveAggregate ''EmailCmd ''EmailRegs ''EmailEvent
-- emits inCtorSendEmail, wireEmailSent, EmailSentTermFields, is* predicates, ...
```

## Limits

- **Trusted evidence roots in lawful `Generic` instances.** A deliberately
  unlawful hand-written `Generic` instance is outside the threat model, exactly
  as `unsafeCoerce` is.
- **The closure-taking constructors are deprecated** (since 0.9.0.0): `mkInCtor`
  / `mkInCtor0` / `mkWireCtor` / `mkWireCtor0` cannot establish trusted evidence.
  Use their `Via` counterparts, or `unavailableInCtor` / `unavailableWireCtor`
  for explicit manual behaviour, and `renameInCtor` / `renameWireCtor` to change
  a diagnostic name while preserving evidence. This is a breaking migration for
  code written against pre-0.9 manual records.
- **Positional payloads are rejected.** TH derivation requires record syntax and
  warns when it skips unsupported GADT or explicitly quantified constructors.
- Per-vertex view *derivation* lives here, but the B-presentation projection it
  produces is documented as its own capability, `CAP-6`, because a consumer
  adopts and verifies the view independently of constructor derivation.
