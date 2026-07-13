# Changelog

All notable changes to this package are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to the
[Haskell PVP](https://pvp.haskell.org).


## [Unreleased]

### Added

- Event-codec schema evolution through pinned constructor wire kinds,
  default-on-missing payload decoding, and a compile-time-complete chain of
  one-envelope-to-one-envelope upcasters.
- `fieldCodec`, a strict smart constructor for `FieldCodec`, plus generated
  `<prefix>SchemaVersion` bindings.

### Changed

- Encoding now documents and pins the existing fully-initialized-register
  precondition. Unwritten `emptyRegFile` slots throw a slot-named `ErrorCall`;
  keiro already snapshots only fully populated register files, so it needs no
  source change.
- **Breaking:** snapshot shape hashes now use keiki's pinned built-in type names.
  Every non-empty shape hash changes once; stores keyed by an old hash ignore that
  snapshot and replay from the event log. Keiro already treats this mismatch as a
  benign cache miss.
- Container slot types now require their arguments to have
  `CanonicalTypeName`, not merely `Typeable`, so user-defined types may need to
  derive or define that class. This makes application overrides propagate through
  `Maybe`, lists, `Either`, and tuples.
- **Breaking:** `EventCodecOptions` now also carries `kindOverrides`,
  `versionFieldName`, `currentVersion`, and `upcasters`.
- **Breaking:** `FieldCodec` gains the `fcOnMissing` field. Positional
  construction should be replaced with `fieldCodec` and a record update when a
  missing-key default is required.
- **Breaking:** generated event envelopes now contain an in-band `"v"` field;
  version-absent historical objects decode as version 1.
- **Breaking:** generated `EventTypes` and `KindMap` bindings contain resolved
  wire kinds, including pinned values, rather than assuming constructor names.


## [0.1.0.0] — 2026-06-07

Initial Hackage release. Co-released with `keiki-0.1.0.0`; this
package depends on `keiki ^>= 0.1`.

### Added

- `Keiki.Codec.JSON` — three-method codec class `RegFileToJSON
  (rs :: [Slot])`:
  - `regFileToJSON :: RegFile rs -> Aeson.Value` (strict Value-path encoder).
  - `regFileFromJSON :: Aeson.Value -> Either String (RegFile rs)`
    (strict decoder; rejects missing / extra / type-mismatched
    fields with per-slot error messages).
  - `regFileToEncoding :: RegFile rs -> Aeson.Encoding` (streaming
    encoder over `Aeson.Series` that avoids the O(output-size)
    intermediate `Aeson.Value` allocation).
  - A single auto-derived instance for every slot list whose slot
    types have `Aeson.ToJSON` + `Aeson.FromJSON`; users do not
    write instances by hand.
- `Keiki.Codec.JSON.TH` — Template Haskell helpers
  `deriveRegFileCodec` and `deriveRegFileCodecAs` that emit
  three top-level codec functions (`<prefix>ToJSON`,
  `<prefix>ToEncoding`, `<prefix>FromJSON`) for a record type
  with `deriving (Generic)`.

### Validated against

- GHC 9.12.2 locally on macOS aarch64 and in CI on Ubuntu Linux
  x86_64 (see `.github/workflows/ci.yml`).
- 40 hspec assertions, including 4 QuickCheck properties (100
  samples each), 9 schema-evolution sensitivity assertions
  (EP-36 §4 cases #1–9), a pinned golden shape hash, and 10
  `Keiki.Codec.JSON.TH` derivation tests.
- A `tasty-bench` baseline (`bench/baseline.csv`) for four
  representative `RegFile` size scenarios (multi-party signing,
  batch reconciliation, ticket aggregate, auction); the
  Encoding-path is ~1.5× faster than the Value-path on the
  streaming-motivating case (5,000-entry list) with 33 % less
  allocation.
