# Changelog

All notable changes to this package are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to the
[Haskell PVP](https://pvp.haskell.org).


## [Unreleased]

(Pre-Hackage. The next published release is 0.1.0.0.)


## [0.1.0.0] — TBD

Initial Hackage release. Co-released with `keiki-0.1.0.0` and
`keiki-codec-json-0.1.0.0`.

### Added

- `Keiki.Codec.JSON.Test.Golden` — the case-#10 detector:
  `data SlotGolden a = SlotGolden { sgInput :: a, sgBytes :: LBS.ByteString }`
  and `slotGoldenSpec :: (Aeson.ToJSON a, Aeson.FromJSON a, Eq a, Show a)
  => String -> SlotGolden a -> Hspec.Spec`. Pins a per-slot-type
  golden bytes value; fails loudly when the slot's `ToJSON`
  instance silently changes (the schema-evolution failure mode the
  shape hash cannot detect by design).
- `Keiki.Codec.JSON.Test` — library-ised exposure of the EP-36 M3
  round-trip and sensitivity disciplines:
  - `class ArbitraryRegFile (rs :: [Slot])` with inductive
    `arbRegFile :: Gen (RegFile rs)`.
  - `regFileCodecProps @rs :: Spec` — four QuickCheck properties
    (Value-path round-trip, Encoding-path round-trip, within-path
    determinism on both paths).
  - `data SomeKnownRegFileShape`, `someKnownShape @rs`,
    `regFileShapeSensitivitySpec` — parameterised baseline +
    mutation list; asserts each mutation flips the shape hash.

### Validated against

- GHC 9.12.4 on macOS aarch64 and Linux x86_64 (CI matrix; see
  `.github/workflows/ci.yml`).
- 7 self-test assertions exercising every public helper against a
  toy `Email` slot type and `DemoSlots` / `DemoSlotsRenamed`
  baseline + mutation pair.
