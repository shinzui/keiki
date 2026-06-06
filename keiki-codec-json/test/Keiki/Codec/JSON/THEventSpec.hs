{-# LANGUAGE TemplateHaskell #-}

{- | EP-59 M3 tests for
'Keiki.Codec.JSON.Event.deriveEventCodecSkeleton'.

The splice derives a @kind@-discriminated encoder/decoder for an event
/sum/ type. This spec exercises round-trip, the @kind@ discriminator,
that a per-field override actually runs (rather than a generic instance),
and the constructor-name list, against a 3-constructor fixture: one
payload event with an overridden newtype field, one all-passthrough
payload event, and one singleton.

== Negative checks (manual)

The no-silent-fallback contract is that an /unhandled/ field (one in
neither 'fieldCodecOverrides' nor 'passthroughFields') is never silently
given a generic codec. There are two behaviours, neither expressible as a
passing unit test:

1. @onMissingCodec = FailAtCompileTime@ (the default). Add a field to a
   payload record without listing it, e.g. give @PlacedData@ a
   @discount :: Int@ field and do NOT add @"discount"@ to
   'passthroughFields'. Run
   @cabal build keiki-codec-json:keiki-codec-json-test@. The build must
   fail with a message of the form:

   @
   deriveEventCodecSkeleton: Keiki.Codec.JSON.THEventSpec.OrderEvent has
   field(s) with no provided codec and onMissingCodec = FailAtCompileTime:
     - Placed.discount :: GHC.Types.Int
   Add each field to fieldCodecOverrides or passthroughFields, or set
   onMissingCodec = EmitTodoBindings.
   @

   (The type name and field type print fully qualified — @show@/@pprint@
   of the reified names.) Revert the field.

2. @onMissingCodec = EmitTodoBindings@. With the same unhandled field but
   @onMissingCodec = EmitTodoBindings@ in the options, the build SUCCEEDS
   and a top-level binding @_todo_Placed_discount :: a@ is emitted whose
   body is @error "TODO: provide a FieldCodec for Placed.discount :: Int"@.
   Any actual encode/decode of that field throws the named error rather
   than guessing. Verify by adding @discount@, switching to
   @EmitTodoBindings@, and observing the module compiles; referencing
   @_todo_Placed_discount@ in @cabal repl@ shows the binding exists.
   Revert afterwards.

Both behaviours were verified by hand on 2026-06-06; the observed
compile-fail text matched (1) verbatim.
-}
module Keiki.Codec.JSON.THEventSpec (spec) where

import Data.Aeson qualified as Aeson
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Test.Hspec (Spec, describe, it, shouldBe)
import Text.Read (readMaybe)

import Keiki.Codec.JSON.Event (
    EventCodecOptions (..),
    FieldCodec (..),
    defaultEventCodecOptions,
    deriveEventCodecSkeleton,
 )

-- * Fixtures -----------------------------------------------------------------

{- | A newtype field whose JSON form is overridden (a @"ord-<n>"@ string),
proving the override hook runs instead of a generic 'Int' encoding.
-}
newtype OrderId = OrderId Int
    deriving stock (Eq, Show)

orderIdToJSON :: OrderId -> Aeson.Value
orderIdToJSON (OrderId n) = Aeson.toJSON (T.pack ("ord-" <> show n))

orderIdFromJSON :: Aeson.Value -> Either String OrderId
orderIdFromJSON v = case v of
    Aeson.String t
        | Just rest <- T.stripPrefix (T.pack "ord-") t
        , Just n <- readMaybe (T.unpack rest) ->
            Right (OrderId n)
    _ -> Left "orderIdFromJSON: expected an \"ord-<int>\" string"

data PlacedData = PlacedData
    { orderId :: OrderId
    , qty :: Int
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
            Map.fromList [("orderId", FieldCodec 'orderIdToJSON 'orderIdFromJSON)]
        , passthroughFields = Set.fromList ["qty", "trackingNo"]
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
        -- == {"kind":"Placed","orderId":"ord-7","qty":3}
        it "Placed carries the kind key, the override output, and the passthrough field" $
            orderEventToJSON placed
                `shouldBe` Aeson.object
                    [ "kind" Aeson..= (T.pack "Placed" :: Text)
                    , "orderId" Aeson..= (T.pack "ord-7" :: Text)
                    , "qty" Aeson..= (3 :: Int)
                    ]

        it "the orderId override ran (string \"ord-7\", not the integer 7)" $
            -- If a generic Int codec had been silently used, this would be 7.
            orderEventFromJSON
                ( Aeson.object
                    [ "kind" Aeson..= (T.pack "Placed" :: Text)
                    , "orderId" Aeson..= (T.pack "ord-7" :: Text)
                    , "qty" Aeson..= (3 :: Int)
                    ]
                )
                `shouldBe` Right placed

        it "Cancelled encodes to just the kind object" $
            orderEventToJSON cancelled
                `shouldBe` Aeson.object ["kind" Aeson..= (T.pack "Cancelled" :: Text)]

    describe "decoder error paths" $ do
        it "an unknown kind is reported" $
            orderEventFromJSON
                (Aeson.object ["kind" Aeson..= (T.pack "Nope" :: Text)])
                `shouldBe` (Left "unknown event kind: Nope" :: Either String OrderEvent)

        it "a non-object is reported" $
            orderEventFromJSON (Aeson.toJSON (5 :: Int))
                `shouldBe` (Left "orderEvent: expected a JSON object" :: Either String OrderEvent)

    describe "Keiro-feeding surfaces" $ do
        it "EventTypes lists the constructors in declaration order" $
            orderEventEventTypes
                `shouldBe` map T.pack ["Placed", "Shipped", "Cancelled"]

        it "KindMap pairs each constructor name with its kind string" $
            orderEventKindMap
                `shouldBe` [ (T.pack "Placed", T.pack "Placed")
                           , (T.pack "Shipped", T.pack "Shipped")
                           , (T.pack "Cancelled", T.pack "Cancelled")
                           ]
