# Changelog

All notable changes to this package are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to the
[Haskell PVP](https://pvp.haskell.org).


## [Unreleased]

(Pre-Hackage. The next published release is 0.1.0.0.)


## [0.1.0.0] — TBD

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

- GHC 9.12.4 on macOS aarch64 and Linux x86_64 (CI matrix; see
  `.github/workflows/ci.yml`).
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
