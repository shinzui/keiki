{-# LANGUAGE TemplateHaskell #-}

-- | EP-59 M3 tests for
-- 'Keiki.Codec.JSON.Event.deriveEventCodecSkeleton'.
--
-- The splice derives a @kind@-discriminated encoder/decoder for an event
-- /sum/ type. This spec exercises round-trip, the @kind@ discriminator,
-- that a per-field override actually runs (rather than a generic instance),
-- and the constructor-name list, against a 3-constructor fixture: one
-- payload event with an overridden newtype field, one all-passthrough
-- payload event, and one singleton.
--
-- == Negative checks (manual)
--
-- The no-silent-fallback contract is that an /unhandled/ field (one in
-- neither 'fieldCodecOverrides' nor 'passthroughFields') is never silently
-- given a generic codec. There are two behaviours, neither expressible as a
-- passing unit test:
--
-- 1. @onMissingCodec = FailAtCompileTime@ (the default). Add a field to a
--    payload record without listing it, e.g. give @PlacedData@ a
--    @discount :: Int@ field and do NOT add @"discount"@ to
--    'passthroughFields'. Run
--    @cabal build keiki-codec-json:keiki-codec-json-test@. The build must
--    fail with a message of the form:
--
--    @
--    deriveEventCodecSkeleton: Keiki.Codec.JSON.THEventSpec.OrderEvent has
--    field(s) with no provided codec and onMissingCodec = FailAtCompileTime:
--      - Placed.discount :: GHC.Types.Int
--    Add each field to fieldCodecOverrides or passthroughFields, or set
--    onMissingCodec = EmitTodoBindings.
--    @
--
--    (The type name and field type print fully qualified — @show@/@pprint@
--    of the reified names.) Revert the field.
--
-- 2. @onMissingCodec = EmitTodoBindings@. With the same unhandled field but
--    @onMissingCodec = EmitTodoBindings@ in the options, the build SUCCEEDS
--    and a top-level binding @_todo_Placed_discount :: a@ is emitted whose
--    body is @error "TODO: provide a FieldCodec for Placed.discount :: Int"@.
--    Any actual encode/decode of that field throws the named error rather
--    than guessing. Verify by adding @discount@, switching to
--    @EmitTodoBindings@, and observing the module compiles; referencing
--    @_todo_Placed_discount@ in @cabal repl@ shows the binding exists.
--    Revert afterwards.
--
-- 3. Duplicate wire kinds. Add
--    @kindOverrides = Map.fromList [("Placed", "order.event"),
--    ("Shipped", "order.event")]@, build the test target, and expect:
--
--    @
--    deriveEventCodecSkeleton: wire kind "order.event" is claimed by more
--    than one constructor: Placed, Shipped. Wire kinds must be unique per
--    event type.
--    @
--
--    Revert the override.
--
-- 4. Discriminator collision. Add @kind :: Text@ to @PlacedData@ and list
--    @"kind"@ in 'passthroughFields', build the test target, and expect:
--
--    @
--    deriveEventCodecSkeleton: payload field Placed.kind collides with
--    kindFieldName "kind"; rename the field or choose a kindFieldName no
--    payload uses.
--    @
--
--    Revert the field and passthrough entry.
--
-- 5. Incomplete upcaster chain. In @THEventEvolutionSpec@, set the
--    @StructuralEvent@ codec's @currentVersion = 3@ while retaining only
--    @upcasters = [(1, 'upcastQuantityV1)]@. Build the test target and expect:
--
--    @
--    deriveEventCodecSkeleton: upcasters must cover from-versions [1..2]
--    exactly; missing: [2]
--    @
--
--    Restore @currentVersion = 2@.
--
-- Checks (1) and (2) were verified by hand on 2026-06-06; the observed
-- compile-fail text matched (1) verbatim. Checks (3), (4), and (5) were
-- verified by hand on 2026-07-12 with the messages above.
module Keiki.Codec.JSON.THEventSpec
  ( spec,
    OrderId (..),
    PlacedData (..),
    OrderEvent (..),
    orderEventToJSON,
    orderEventFromJSON,
  )
where

import Data.Aeson qualified as Aeson
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Keiki.Codec.JSON.Event
  ( EventCodecOptions (..),
    defaultEventCodecOptions,
    deriveEventCodecSkeleton,
    fieldCodec,
  )
import Test.Hspec (Spec, describe, it, shouldBe)
import Text.Read (readMaybe)

-- * Fixtures -----------------------------------------------------------------

-- | A newtype field whose JSON form is overridden (a @"ord-<n>"@ string),
-- proving the override hook runs instead of a generic 'Int' encoding.
newtype OrderId = OrderId Int
  deriving stock (Eq, Show)

orderIdToJSON :: OrderId -> Aeson.Value
orderIdToJSON (OrderId n) = Aeson.toJSON (T.pack ("ord-" <> show n))

orderIdFromJSON :: Aeson.Value -> Either String OrderId
orderIdFromJSON v = case v of
  Aeson.String t
    | Just rest <- T.stripPrefix (T.pack "ord-") t,
      Just n <- readMaybe (T.unpack rest) ->
        Right (OrderId n)
  _ -> Left "orderIdFromJSON: expected an \"ord-<int>\" string"

data PlacedData = PlacedData
  { orderId :: OrderId,
    qty :: Int
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

$( deriveEventCodecSkeleton
     defaultEventCodecOptions
       { fieldCodecOverrides =
           Map.fromList [("orderId", fieldCodec 'orderIdToJSON 'orderIdFromJSON)],
         passthroughFields = Set.fromList ["qty", "trackingNo"],
         kindOverrides = Map.fromList [("Placed", "order.placed")]
       }
     ''OrderEvent
 )

-- * Spec --------------------------------------------------------------------

spec :: Spec
spec = describe "deriveEventCodecSkeleton" $ do
  let placed = Placed (PlacedData (OrderId 7) 3)
      shipped = Shipped (ShippedData (T.pack "1Z999"))
      cancelled = Cancelled

  describe "round-trip (decode . encode == Right)" $ do
    it "Placed (payload with an overridden field) round-trips" $
      orderEventFromJSON (orderEventToJSON placed) `shouldBe` Right placed

    it "Shipped (all-passthrough payload) round-trips" $
      orderEventFromJSON (orderEventToJSON shipped) `shouldBe` Right shipped

    it "Cancelled (singleton) round-trips" $
      orderEventFromJSON (orderEventToJSON cancelled) `shouldBe` Right cancelled

  describe "kind discriminator + override usage" $ do
    -- orderEventToJSON (Placed (PlacedData (OrderId 7) 3))
    -- == {"kind":"order.placed","v":1,"orderId":"ord-7","qty":3}
    it "Placed carries the kind key, the override output, and the passthrough field" $
      orderEventToJSON placed
        `shouldBe` Aeson.object
          [ "kind" Aeson..= (T.pack "order.placed" :: Text),
            "v" Aeson..= (1 :: Int),
            "orderId" Aeson..= (T.pack "ord-7" :: Text),
            "qty" Aeson..= (3 :: Int)
          ]

    it "a pinned wire kind decodes independently of the Haskell constructor name" $
      -- If a generic Int codec had been silently used, this would be 7.
      orderEventFromJSON
        ( Aeson.object
            [ "kind" Aeson..= (T.pack "order.placed" :: Text),
              "orderId" Aeson..= (T.pack "ord-7" :: Text),
              "qty" Aeson..= (3 :: Int)
            ]
        )
        `shouldBe` Right placed

    it "Cancelled encodes to just the envelope keys" $
      orderEventToJSON cancelled
        `shouldBe` Aeson.object
          [ "kind" Aeson..= (T.pack "Cancelled" :: Text),
            "v" Aeson..= (1 :: Int)
          ]

  describe "schema version envelope" $ do
    it "exports the current schema version" $
      orderEventSchemaVersion `shouldBe` 1

    it "treats a missing version key as version 1" $
      orderEventFromJSON
        ( Aeson.object
            [ "kind" Aeson..= (T.pack "order.placed" :: Text),
              "orderId" Aeson..= (T.pack "ord-7" :: Text),
              "qty" Aeson..= (3 :: Int)
            ]
        )
        `shouldBe` Right placed

    it "rejects an event written by a newer codec" $
      orderEventFromJSON
        ( Aeson.object
            [ "kind" Aeson..= (T.pack "Cancelled" :: Text),
              "v" Aeson..= (2 :: Int)
            ]
        )
        `shouldBe` ( Left "event schema version 2 is ahead of codec version 1" ::
                       Either String OrderEvent
                   )

    it "rejects a schema version below 1" $
      orderEventFromJSON
        ( Aeson.object
            [ "kind" Aeson..= (T.pack "Cancelled" :: Text),
              "v" Aeson..= (0 :: Int)
            ]
        )
        `shouldBe` (Left "invalid event schema version: 0" :: Either String OrderEvent)

    it "rejects a non-integral schema-version value" $
      orderEventFromJSON
        ( Aeson.object
            [ "kind" Aeson..= (T.pack "Cancelled" :: Text),
              "v" Aeson..= (T.pack "one" :: Text)
            ]
        )
        `shouldBe` ( Left "field v: expected an integer schema version" ::
                       Either String OrderEvent
                   )

  describe "decoder error paths" $ do
    it "an unknown kind is reported" $
      orderEventFromJSON
        (Aeson.object ["kind" Aeson..= (T.pack "Nope" :: Text)])
        `shouldBe` ( Left
                       "unknown event kind: Nope (expected one of: order.placed, Shipped, Cancelled)" ::
                       Either String OrderEvent
                   )

    it "a non-object is reported" $
      orderEventFromJSON (Aeson.toJSON (5 :: Int))
        `shouldBe` (Left "orderEvent: expected a JSON object" :: Either String OrderEvent)

  describe "Keiro-feeding surfaces" $ do
    it "EventTypes lists resolved wire kinds in declaration order" $
      orderEventEventTypes
        `shouldBe` map T.pack ["order.placed", "Shipped", "Cancelled"]

    it "KindMap pairs each constructor name with its kind string" $
      orderEventKindMap
        `shouldBe` [ (T.pack "Placed", T.pack "order.placed"),
                     (T.pack "Shipped", T.pack "Shipped"),
                     (T.pack "Cancelled", T.pack "Cancelled")
                   ]
