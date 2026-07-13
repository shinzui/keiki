# keiki-codec-json

Optional JSON codec support for
[`keiki`](https://hackage.haskell.org/package/keiki)'s type-level
register file, `RegFile rs`.

This package is separate by design: the `keiki` core remains
`aeson`-free, while applications that persist snapshots as JSON can opt
in here. The structural shape hash
(`Keiki.Shape.regFileShapeHash`) stays in `keiki` so consumers can
discriminate snapshot shapes without pulling in a JSON dependency.

This package ships:

- `Keiki.Codec.JSON.RegFileToJSON` — three-method class providing
  - `regFileToJSON :: RegFile rs -> Aeson.Value` (strict object encoder)
  - `regFileFromJSON :: Aeson.Value -> Either String (RegFile rs)`
    (strict decoder; missing / extra / type-mismatched fields are
    rejected with a per-slot error message)
  - `regFileToEncoding :: RegFile rs -> Aeson.Encoding` — streaming
    encoder over `Aeson.Series`, avoiding the O(output-size)
    intermediate `Aeson.Value` allocation for users with multi-MB slot
    values
- `Keiki.Codec.JSON.TH` — Template Haskell helpers for deriving record
  codecs through the same `RegFileToJSON` path
- `Keiki.Codec.JSON.Event` — Template Haskell helpers for generating a
  `kind`-discriminated event codec skeleton from event sum types

## Using

```haskell
import Data.Proxy (Proxy (..))
import Keiki.Codec.JSON (regFileFromJSON, regFileToEncoding, regFileToJSON)
import Keiki.Shape (regFileShapeHash)

type Snapshot = '[ '("retryCount", Int), '("note", Text) ]

-- Snapshot persister:
let bytes = encodingToLazyByteString (regFileToEncoding rf)
    hash = regFileShapeHash (Proxy @Snapshot)
writeRow (snapshotTable hash bytes)

-- Hydration:
case Aeson.decode bytes of
  Nothing -> Left "snapshot bytes not JSON"
  Just v  -> regFileFromJSON @Snapshot v
```

## Deriving the codec for a record type

If you have a plain Haskell record and want the three codec functions
without writing them by hand, use the TH splice from
`Keiki.Codec.JSON.TH`:

```haskell
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
-- emits:
--   snapshotToJSON     :: Snapshot -> Aeson.Value
--   snapshotToEncoding :: Snapshot -> Aeson.Encoding
--   snapshotFromJSON   :: Aeson.Value -> Either String Snapshot
```

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

## Register-file wire rules

Every register slot is present in the JSON object. A `Nothing` slot encodes as
explicit JSON `null`; omitting its key is an error, not another spelling of
`Nothing`. A nested optional value is lossy under aeson's standard instances:
`Just Nothing :: Maybe (Maybe a)` and outer `Nothing` both encode as `null` and
decode as outer `Nothing`. Avoid nested-`Maybe` slots when that distinction
matters, or wrap the inner optional value in a newtype with explicit JSON
instances.

The Value encoder emits aeson's object-key order, while the streaming Encoding
path emits slot-list order. Their bytes may differ, but both decode to the same
register file.

## Deriving an event codec skeleton

A service that stores its events as JSON usually hand-writes a
`kind`-discriminated encoder/decoder per event *sum* type — a large
`case` with one branch per constructor and one `.=` per payload field,
plus a matching parser. `deriveEventCodecSkeleton` (from
`Keiki.Codec.JSON.Event`) removes that boilerplate. Given a sum type whose
constructors each wrap a single record payload, or are no-argument
singletons:

```haskell
{-# LANGUAGE TemplateHaskell #-}

import qualified Data.Aeson as Aeson
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import Keiki.Codec.JSON.Event
  ( EventCodecOptions (..)
  , FieldCodec (fcOnMissing)
  , defaultEventCodecOptions
  , deriveEventCodecSkeleton
  , fieldCodec
  )

newtype OrderId = OrderId Int deriving stock (Eq, Show)
orderIdToJSON   :: OrderId -> Aeson.Value
orderIdFromJSON :: Aeson.Value -> Either String OrderId

data PlacedData = PlacedData
  { orderId :: OrderId
  , qty     :: Int
  }
  deriving stock (Eq, Show)

data ShippedData = ShippedData
  { trackingNo :: Text
  }
  deriving stock (Eq, Show)

data OrderEvent
  = Placed PlacedData
  | Shipped ShippedData
  | Cancelled
  deriving stock (Eq, Show)

$(deriveEventCodecSkeleton
    defaultEventCodecOptions
      { fieldCodecOverrides =
          Map.fromList [("orderId", fieldCodec 'orderIdToJSON 'orderIdFromJSON)]
      , passthroughFields = Set.fromList ["qty", "trackingNo"]
      }
    ''OrderEvent)
-- emits, using the lower-cased type name as prefix:
--   orderEventToJSON     :: OrderEvent -> Aeson.Value
--   orderEventFromJSON   :: Aeson.Value -> Either String OrderEvent
--   orderEventEventTypes :: [Text]
--   orderEventKindMap    :: [(Text, Text)]
--   orderEventSchemaVersion :: Int
```

Each constructor encodes to an object carrying a `"kind"` discriminator
(its constructor name unless pinned) and a `"v"` schema version, plus one
entry per payload field, so
`orderEventToJSON (Placed (PlacedData (OrderId 7) 3))` is
`{"kind":"Placed","v":1,"orderId":"ord-7","qty":3}` — note `orderId`
is the override's output, not a generic `Int`. The
`orderEventEventTypes` / `orderEventKindMap` bindings contain the resolved
wire kinds as plain `Text` (no Keiro dependency), and
`orderEventSchemaVersion` contains the configured current version.

**No silent generic fallback.** Each payload field is encoded by *name*:
an override (`fieldCodecOverrides`), a passthrough using the field's own
aeson instances (`passthroughFields`), or — for a field in neither —
whatever `onMissingCodec` says. The default `FailAtCompileTime` aborts the
splice listing every unhandled `<Event>.<field> :: <Type>`; the
alternative `EmitTodoBindings` emits a `_todo_<Event>_<field>` placeholder
that compiles but fails when evaluated. Adding a field to a payload
record therefore forces a compile-time decision instead of silently
changing, or dropping, the stored JSON.

Constructors that are multi-argument, use record syntax directly, or are
GADT/infix are rejected at splice time with a precise message; wrap a
single record payload type instead (`Placed PlacedData`).

### Evolving an event schema

There are three common changes, each with a distinct codec move.

1. **Add a payload field without bumping the version.** For an optional
   field such as `note :: Maybe Text`, add `"note"` to
   `passthroughFields`; a missing key decodes as `Nothing`, while an
   explicit JSON `null` also follows aeson's normal `Maybe` decoder. For a
   non-`Maybe` field, provide a named default constant through the override:

   ```haskell
   defaultPriority :: Priority
   defaultPriority = NormalPriority

   priorityCodec :: FieldCodec
   priorityCodec =
     (fieldCodec 'priorityToJSON 'priorityFromJSON)
       { fcOnMissing = Just 'defaultPriority }
   ```

   Put `priorityCodec` in `fieldCodecOverrides`. Keep `currentVersion`
   unchanged: this is an additive compatibility rule, not a structural
   migration. Required fields without either form of default still fail with
   `missing field: <name>`.

2. **Rename a Haskell constructor without changing stored bytes.** Pin the
   renamed constructor to its historical discriminator:

   ```haskell
   kindOverrides = Map.fromList [("OrderPlaced", "Placed")]
   ```

   Override keys are current constructor names. The splice rejects unknown
   keys and duplicate resolved wire kinds, while encoding, decoding,
   `EventTypes`, and `KindMap` all use the pinned wire value.

3. **Restructure a payload.** Increment `currentVersion` and register one
   whole-envelope upcaster for every historical step:

   ```haskell
   upcastOrderV1 :: Aeson.Value -> Either String Aeson.Value
   upcastOrderV1 = ... -- rewrite a version-1 object into version-2 shape

   currentVersion = 2
   upcasters = [(1, 'upcastOrderV1)]
   ```

   An absent `"v"` is version 1. Before constructor dispatch, the decoder
   runs every rung from the stored version to the current version. For
   `currentVersion = n`, the splice requires exactly the source versions
   `[1 .. n - 1]`; gaps, duplicates, and out-of-range entries fail at compile
   time. A rung is one-envelope-to-one-envelope. If one historical event must
   split into several current events, do that in the application's event-store
   adapter as described in
   [`docs/research/schema-evolution.md`](../docs/research/schema-evolution.md).

Unknown object keys are intentionally ignored by the event decoder so additive
deployments can overlap. This differs from the RegFile snapshot decoder, which
rejects extra keys because a snapshot must match one exact register shape.

The in-band `"v"` is opt-in version ownership for applications that have no
outer event envelope. If an application already owns out-of-band metadata — for
example, a keiro-style `schemaVersion` beside the payload — keep this codec's
`currentVersion = 1` and evolve at that outer layer. Running both schemes with
different version numbers is a configuration error; neither layer detects the
disagreement for the other.

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

```sh
cabal bench keiki-codec-json:keiki-codec-json-bench
```

Four fixtures cover representative snapshot sizes:

| Fixture                | Scenario                 | Condensed size           |
|------------------------|--------------------------|--------------------------|
| `BenchA_ContractSign`  | Contract signing         | 5 parties, 50 audit rows |
| `BenchB_BatchRecon`    | Batch reconciliation     | 5,000 processedItems     |
| `BenchC_TicketAgg`     | Ticket aggregate         | 100 comments             |
| `BenchD_Auction`       | Auction                  | 1,000 bids               |

Per fixture: `encode-via-Value`, `encode-via-Encoding`, `decode`, `hash`.

`bench/baseline.csv` carries reference numbers from a GHC 9.12.2 run on
macOS aarch64. The benchmark is a tracked metric, not a correctness
gate; the golden shape-hash tests are the release-blocking checks.

## Test toolkit for downstream consumers

If you persist `RegFile rs` to JSON and want to guard against the
schema-evolution case the shape hash cannot catch by design — a
silent change to a slot type's `Aeson.ToJSON` instance — see the
sibling package
[`keiki-codec-json-test`](../keiki-codec-json-test/README.md). It
ships a per-slot-type golden-byte detector (`slotGoldenSpec`) plus
library versions of the round-trip and sensitivity disciplines,
parameterised over your own slot list. Production consumers of
`keiki-codec-json` do not need to depend on it.

## Test suite

```sh
cabal test keiki-codec-json:keiki-codec-json-test
```

Covers unit tests, four QuickCheck properties, schema-evolution
sensitivity assertions, and the golden hash fixture pinned for
GHC 9.12.*.
