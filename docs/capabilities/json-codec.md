---
title: "Optional JSON codec for register files and events"
type: Capability
description: "Encode and decode a register file and persisted events as JSON — strict or streaming — with pinned wire kinds, in-band schema versions, and explicit upcaster chains, without pulling aeson into the pure core."
generated:
  by: adopt-capabilities/0.9.2
  at: "2026-08-08T00:00:00Z"
capabilityId: CAP-11
provider: mori://shinzui/keiki
status: shipped
stability: experimental
since: "0.1.0.0"
packages:
  - keiki-codec-json
interface:
  - Keiki.Codec.JSON
  - Keiki.Codec.JSON.Event
  - Keiki.Codec.JSON.TH
requires:
  - CAP-1
  - CAP-10
evidence:
  - kind: test
    resource: keiki-codec-json/test/Keiki/Codec/JSON/PropSpec.hs
    proves: Value-path and Encoding-path codecs round-trip and are deterministic under QuickCheck.
  - kind: conformance
    resource: keiki-codec-json/test/Keiki/Codec/JSON/GoldenFileSpec.hs
    proves: Whole-register-file golden files pin the exact on-wire JSON.
  - kind: test
    resource: keiki-codec-json/test/Keiki/Codec/JSON/THEventEvolutionSpec.hs
    proves: The event codec applies a compile-time-complete upcaster chain across pinned wire kinds and schema versions.
  - kind: benchmark
    resource: keiki-codec-json/bench/baseline.csv
    proves: The streaming Encoding path avoids the intermediate Value allocation on large register files.
---

# Optional JSON codec for register files and events

The keiki core is deliberately codec-free — it talks only typed Haskell values.
When you do need JSON on the wire, `keiki-codec-json` is the opt-in package that
provides it, so an application chooses serialization without the pure core ever
depending on `aeson`. It serializes the register file from
[CAP-1](typed-transducer-core.md) and pairs with the shape hash in
[CAP-10](snapshot-shape-hash.md) as the two halves of snapshot persistence.

## What you adopt

- **`Keiki.Codec.JSON`** — the three-method class `RegFileToJSON rs`:
  `regFileToJSON` (strict `Value`), `regFileFromJSON` (strict decode with
  per-slot error messages), and `regFileToEncoding` (streaming over
  `Aeson.Series`). One auto-derived instance covers any slot list whose slot
  types have `ToJSON` + `FromJSON`.
- **`Keiki.Codec.JSON.Event`** — the persisted-event codec: explicitly pinned
  wire kinds, an in-band schema version, default-on-missing additive fields, and
  a compile-time-complete one-envelope-to-one-envelope upcaster chain.
- **`Keiki.Codec.JSON.TH`** — `deriveRegFileCodec` / `deriveRegFileCodecAs` emit
  the three codec functions for a record type deriving `Generic`.

## Shortest real usage

```haskell
regFileToEncoding regfile :: Aeson.Encoding      -- streaming, for multi-MB slots
regFileFromJSON value     :: Either String (RegFile rs)
```

## Limits

- **Semantic splits and merges are application-owned.** The upcaster chain
  evolves one envelope shape into the next; it does not decide how to split one
  event into two or merge two into one.
- **A silent `ToJSON` instance change is invisible to the codec and the shape
  hash.** Detecting it is exactly what the companion toolkit `CAP-12` exists for;
  without wiring those goldens, this failure mode is undetected.
- **Encoding an uninitialized register is a slot-named failure**, and duplicate
  slot names are rejected at compile time.
- `since` is 0.1.0.0: the package co-released with `keiki-0.1.0.0` carrying the
  three-method class and TH; the event codec's pinned-kind/upcaster surface is
  part of the current coordinated `0.9.0.0` line — a consumer pinning 0.1.0.0
  has the register-file codec but should confirm the event-codec surface against
  that version's changelog.
