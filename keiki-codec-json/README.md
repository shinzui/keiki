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

## Deriving the codec for a record type

If you have a plain Haskell record and want the three codec functions
without writing them by hand, use the TH splice from
`Keiki.Codec.JSON.TH`:

    {-# LANGUAGE DeriveGeneric #-}
    {-# LANGUAGE TemplateHaskell #-}
    import qualified Data.Aeson as Aeson
    import Data.Text (Text)
    import GHC.Generics (Generic)
    import Keiki.Codec.JSON.TH (deriveRegFileCodec)

    data Snapshot = Snapshot
      { retryCount :: Int
      , note       :: Text
      }
      deriving stock (Eq, Show, Generic)

    $(deriveRegFileCodec ''Snapshot)
    --  emits:
    --    snapshotToJSON     :: Snapshot -> Aeson.Value
    --    snapshotToEncoding :: Snapshot -> Aeson.Encoding
    --    snapshotFromJSON   :: Aeson.Value -> Either String Snapshot

The emitted functions route through the same `RegFileToJSON` class as
the hand-written path: the record's field names become the JSON object's
keys, missing/extra/type-mismatched fields are rejected with the same
per-slot error messages, and the encoding path streams without
allocating an intermediate `Aeson.Value`.

Every field type must carry `Aeson.ToJSON` + `Aeson.FromJSON`. If a
field type lacks either instance, compilation fails at the use site of
the emitted function with a precise per-field error pointing at the
missing instance.

The record must have `deriving (Generic)` — the splice does not emit
a `Generic` instance for you. Multi-constructor sum types, positional
(non-record-syntax) constructors, and type synonyms are rejected at
splice time with a precise error message.

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

`bench/baseline.csv` carries the reference numbers from a GHC 9.12.2
run on macOS aarch64. CI runs the bench on every push and flags drift
(>20%) as a PR comment but does NOT block merges. The cross-GHC hash
gate (EP-36 M5) is the release-blocking gate; the bench is a tracked
metric.

## Test toolkit for downstream consumers

If you persist `RegFile rs` to JSON and want to guard against the
schema-evolution case the shape hash cannot catch by design — a
silent change to a slot type's `Aeson.ToJSON` instance — see the
sibling package
[`keiki-codec-json-test`](../keiki-codec-json-test/README.md). It
ships a per-slot-type golden-byte detector (`slotGoldenSpec`) plus
library-ised versions of the EP-36 M3 round-trip and sensitivity
disciplines, parameterised over your own slot list. Production
consumers of `keiki-codec-json` do not need to depend on it.

## Test suite

    cabal test keiki-codec-json:keiki-codec-json-test

Covers M2 unit tests (16 cases), M3 properties (4 properties × 100
QuickCheck samples each), M3 schema-evolution sensitivity assertions
(9 cases, one per EP-36 §4 mutation #1–#9), and the M3 golden hash
fixture pinned for GHC 9.12.*.
