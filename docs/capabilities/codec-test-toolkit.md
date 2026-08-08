---
title: "Codec property-test toolkit for downstream consumers"
type: Capability
description: "Wire per-slot golden, round-trip, and shape-sensitivity checks into your own test suite to catch silent JSON schema drift, without pulling test dependencies into production."
generated:
  by: adopt-capabilities/0.9.2
  at: "2026-08-08T00:00:00Z"
capabilityId: CAP-12
provider: mori://shinzui/keiki
status: shipped
stability: experimental
since: "0.1.0.0"
packages:
  - keiki-codec-json-test
interface:
  - Keiki.Codec.JSON.Test
  - Keiki.Codec.JSON.Test.Golden
  - Keiki.Codec.JSON.Test.GoldenFile
requires:
  - CAP-11
evidence:
  - kind: test
    resource: keiki-codec-json-test/test/Keiki/Codec/JSON/Test/Demo.hs
    proves: Every public helper is exercised against a toy slot type and a baseline/mutation pair, asserting mutations flip the shape hash and goldens catch ToJSON changes.
  - kind: guide
    resource: keiki-codec-json-test/README.md
    proves: How a downstream consumer wires slotGoldenSpec, regFileCodecProps, and regFileShapeSensitivitySpec into their own hspec suite.
---

# Codec property-test toolkit for downstream consumers

The one JSON failure mode neither the codec nor the shape hash can catch is a
slot type's `ToJSON` instance silently changing while its Haskell shape stays the
same. `keiki-codec-json-test` packages the disciplines that catch it as
hspec-callable helpers a consumer wires into their own suite. It tests the codec
from [CAP-11](json-codec.md).

## What you adopt

- **`Keiki.Codec.JSON.Test.Golden.slotGoldenSpec`** — the case-#10 detector:
  pins a per-slot-type golden byte string and fails loudly when the slot's
  `ToJSON` instance changes.
- **`Keiki.Codec.JSON.Test.regFileCodecProps`** — four QuickCheck properties
  (Value- and Encoding-path round-trip plus within-path determinism),
  parameterised over the consumer's own slot list via `ArbitraryRegFile`.
- **`regFileShapeSensitivitySpec`** / `someKnownShape` — a baseline-plus-mutation
  spec asserting each mutation flips the shape hash.

## Shortest real usage

```haskell
spec = do
  slotGoldenSpec "Email" emailGolden
  regFileCodecProps @MySlots
  regFileShapeSensitivitySpec baseline mutations
```

## Limits

- **Split out so production stays lean.** It exists as a separate package
  precisely so a production dependency on `keiki-codec-json` does not
  transitively pull in `QuickCheck` / `hspec` / `quickcheck-instances`. Depend on
  it only from your test component.
- **Weakest self-evidence in the catalog.** The package's own suite is a
  7-assertion self-test against a toy `Email` slot and a `DemoSlots` /
  `DemoSlotsRenamed` pair; it proves the helpers work, not that they cover any
  particular consumer's schema. The value is realised only when a consumer
  supplies their own goldens and slot list.
- The toolkit does not decide *what* your correct wire bytes are; you own the
  golden values it pins.
