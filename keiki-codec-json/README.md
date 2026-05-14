# keiki-codec-json

Optional JSON codec and shape hash interop for [keiki](https://hackage.haskell.org/package/keiki)'s
type-level register file `RegFile rs`. Sibling package — keiki itself
remains aeson-free.

This package ships:

- `Keiki.Codec.JSON.RegFileToJSON` — three-method class providing
  - `regFileToJSON :: RegFile rs -> Aeson.Value` (strict object encoder)
  - `regFileFromJSON :: Aeson.Value -> Either String (RegFile rs)`
    (strict decoder; missing / extra / type-mismatched fields are
    rejected with a per-slot error message)
  - `regFileToEncoding :: RegFile rs -> Aeson.Encoding` (streaming
    encoder over `Aeson.Series`, avoiding the O(output-size)
    intermediate `Aeson.Value` allocation for users with multi-MB slot
    values)
- The structural shape hash (`Keiki.Shape.regFileShapeHash`) ships in
  `keiki` core so consumers of the hash do not pull `aeson` in.

## Using

    import Data.Proxy (Proxy (..))
    import Keiki.Codec.JSON (regFileFromJSON, regFileToEncoding, regFileToJSON)
    import Keiki.Shape (regFileShapeHash)

    type Snapshot = '[ '("retryCount", Int), '("note", Text) ]

    -- snapshot persister:
    let bytes = encodingToLazyByteString (regFileToEncoding rf)
        hash = regFileShapeHash (Proxy @Snapshot)
    writeRow (snapshotTable hash bytes)

    -- hydration:
    case Aeson.decode bytes of
      Nothing -> Left "snapshot bytes not JSON"
      Just v  -> regFileFromJSON @Snapshot v

## When to use the streaming encoder

`regFileToJSON` builds an `Aeson.Value` whose `Object` is an
`Aeson.KeyMap` — internally a `Map Key Value` in aeson 2.2, so its
serialised form orders keys alphabetically. `regFileToEncoding` walks
the slot list directly into `Aeson.Series` (slot-list order) without
materialising the intermediate `Aeson.Value`. Both paths round-trip
through `regFileFromJSON` to the same `RegFile`, but for multi-MB
RegFiles the Encoding path saves a substantial allocation (see
`bench/baseline.csv` — for the 5000-item batch reconciliation fixture
the Encoding path is ~1.5× faster and allocates roughly two-thirds the
bytes).

## Benchmarks

    cabal bench keiki-codec-json:keiki-codec-json-bench

Four fixtures condensed from EP-36 §10:

| Fixture                | Source     | Condensed size           |
|------------------------|------------|--------------------------|
| `BenchA_ContractSign`  | §10 Case A | 5 parties, 50 audit rows |
| `BenchB_BatchRecon`    | §10 Case B | 5,000 processedItems     |
| `BenchC_TicketAgg`     | §10 Case C | 100 comments             |
| `BenchD_Auction`       | §10 Case D | 1,000 bids               |

Per fixture: `encode-via-Value`, `encode-via-Encoding`, `decode`, `hash`.

`bench/baseline.csv` carries the reference numbers from a GHC 9.12.3
run on macOS aarch64. CI runs the bench on every push and flags drift
(>20%) as a PR comment but does NOT block merges. The cross-GHC hash
gate (EP-36 M5) is the release-blocking gate; the bench is a tracked
metric.

## Test suite

    cabal test keiki-codec-json:keiki-codec-json-test

Covers M2 unit tests (16 cases), M3 properties (4 properties × 100
QuickCheck samples each), M3 schema-evolution sensitivity assertions
(9 cases, one per EP-36 §4 mutation #1–#9), and the M3 golden hash
fixture pinned for GHC 9.12.*.
