---
title: "Codec-independent snapshot shape discrimination"
type: Capability
description: "Discriminate register-file and control-state snapshots by a GHC-upgrade-safe canonical shape and SHA-256 hash, independent of any serialization codec."
generated:
  by: adopt-capabilities/0.9.2
  at: "2026-08-08T00:00:00Z"
capabilityId: CAP-10
provider: mori://shinzui/keiki
status: shipped
stability: experimental
since: "0.1.0.0"
packages:
  - keiki
interface:
  - Keiki.Shape
requires:
  - CAP-1
evidence:
  - kind: test
    resource: test/Keiki/ShapeSpec.hs
    proves: The canonical shape text and SHA-256 hash are stable across GHC-internal module paths and change exactly when the register-file shape changes.
---

# Codec-independent snapshot shape discrimination

If you snapshot aggregate state, you need to know when a stored snapshot is no
longer shape-compatible with the current code — without coupling that decision to
whichever codec wrote it. `Keiki.Shape` provides a canonical, GHC-upgrade-safe
description of a register file (and control state) plus a SHA-256 hash over it.
It describes the register file from [CAP-1](typed-transducer-core.md) and is the
snapshot half of the persistence story whose codec half is `CAP-11`.

## What you adopt

- **`Keiki.Shape`**: `class CanonicalTypeName a`, `class KnownRegFileShape (rs
  :: [Slot])`, `regFileShapeCanonical`, `regFileShapeHash`,
  `renderStableTypeRep`, and `sha256Hex`. Built-in and container type names are
  pinned independently of GHC-internal module paths.
- **Control-state discrimination** (since 0.3.1.0): `CanonicalStateShape`,
  `stateShapeCanonical`, and `stateShapeHash`.

## Shortest real usage

```haskell
regFileShapeHash @rs :: ByteString   -- store alongside a snapshot; compare on load
```

## Limits

- **The shape hash discriminates shape, not semantics.** A change to the fold or
  to a slot type's `ToJSON` meaning that leaves the shape identical is invisible
  here by design; catching a silent `ToJSON` change is the job of the codec
  test toolkit (`CAP-12`), and a semantic fold change still needs an explicit
  version or fold fingerprint.
- **Built-in canonical names changed in 0.2.0.0.** Pinned module-independent
  names (`Int`, `Text`, `Maybe(Int)`, …) changed every non-empty shape hash once
  in that release; the intended recovery is a benign cache-miss that replays the
  event log. A consumer pinning 0.1.0.0 has the older hashes.
- **Container instances recurse through `CanonicalTypeName`, not `Typeable`**
  (since 0.2.0.0). A custom type used inside a container may now need
  `deriving anyclass (CanonicalTypeName)`; missing evidence is a compile-time
  migration, which is safer than silent hash drift but is still a migration.
