{-# LANGUAGE TemplateHaskell #-}

-- | EP-77 evolution regressions for additive event fields.
module Keiki.Codec.JSON.THEventEvolutionSpec
  ( spec,
    Discount (..),
    ItemAddedData (..),
    AdditiveEvent (..),
    additiveEventToJSON,
    additiveEventFromJSON,
    QuantityRecordedData (..),
    StructuralEvent (..),
    structuralEventToJSON,
    structuralEventFromJSON,
  )
where

import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy (ByteString)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Keiki.Codec.JSON.Event
  ( EventCodecOptions (..),
    FieldCodec (fcOnMissing),
    defaultEventCodecOptions,
    deriveEventCodecSkeleton,
    fieldCodec,
  )
import Test.Hspec (Spec, describe, it, shouldBe)
import Test.QuickCheck
  ( Gen,
    Property,
    chooseInt,
    elements,
    forAllShow,
    listOf1,
    oneof,
    (===),
  )

newtype Discount = Discount Int
  deriving stock (Eq, Show)

discountToJSON :: Discount -> Aeson.Value
discountToJSON (Discount amount) = Aeson.toJSON amount

discountFromJSON :: Aeson.Value -> Either String Discount
discountFromJSON value = case Aeson.fromJSON value of
  Aeson.Success amount -> Right (Discount amount)
  Aeson.Error message -> Left message

missingDiscount :: Discount
missingDiscount = Discount 0

data ItemAddedData = ItemAddedData
  { orderId :: Text,
    discount :: Discount,
    note :: Maybe Text
  }
  deriving stock (Eq, Show)

data AdditiveEvent = ItemAdded ItemAddedData
  deriving stock (Eq, Show)

$( deriveEventCodecSkeleton
     defaultEventCodecOptions
       { fieldCodecOverrides =
           Map.fromList
             [ ( "discount",
                 (fieldCodec 'discountToJSON 'discountFromJSON)
                   { fcOnMissing = Just 'missingDiscount
                   }
               )
             ],
         passthroughFields = Set.fromList ["orderId", "note"]
       }
     ''AdditiveEvent
 )

data QuantityRecordedData = QuantityRecordedData
  { quantity :: Int
  }
  deriving stock (Eq, Show)

data StructuralEvent = QuantityRecorded QuantityRecordedData
  deriving stock (Eq, Show)

upcastQuantityV1 :: Aeson.Value -> Either String Aeson.Value
upcastQuantityV1 value = case value of
  Aeson.Object object -> case KeyMap.lookup (Key.fromString "qty") object of
    Nothing -> Left "missing qty"
    Just quantityValue ->
      Right
        ( Aeson.Object
            (KeyMap.insert (Key.fromString "quantity") quantityValue object)
        )
  _ -> Left "expected an object"

$( deriveEventCodecSkeleton
     defaultEventCodecOptions
       { passthroughFields = Set.fromList ["quantity"],
         currentVersion = 2,
         upcasters = [(1, 'upcastQuantityV1)]
       }
     ''StructuralEvent
 )

-- These bytes predate the note and discount fields; do not regenerate them.
oldAdditiveBytes :: ByteString
oldAdditiveBytes = "{\"kind\":\"ItemAdded\",\"orderId\":\"ord-7\"}"

decodeAdditiveBytes :: ByteString -> Either String AdditiveEvent
decodeAdditiveBytes bytes = do
  value <- Aeson.eitherDecode bytes
  additiveEventFromJSON value

decodeStructuralBytes :: ByteString -> Either String StructuralEvent
decodeStructuralBytes bytes = do
  value <- Aeson.eitherDecode bytes
  structuralEventFromJSON value

arbAdditiveEvent :: Gen AdditiveEvent
arbAdditiveEvent = do
  orderNumber <- chooseInt (0, 100000)
  discountAmount <- chooseInt (-1000, 1000)
  generatedNote <-
    oneof
      [ pure Nothing,
        Just . T.pack <$> listOf1 (elements ['a' .. 'z'])
      ]
  pure
    ( ItemAdded
        ItemAddedData
          { orderId = T.pack ("ord-" <> show orderNumber),
            discount = Discount discountAmount,
            note = generatedNote
          }
    )

roundTripProperty :: AdditiveEvent -> Property
roundTripProperty event =
  additiveEventFromJSON (additiveEventToJSON event) === Right event

spec :: Spec
spec = describe "default-on-missing event fields" $ do
  it "exports the additive fixture's wire metadata" $ do
    additiveEventSchemaVersion `shouldBe` 1
    additiveEventEventTypes `shouldBe` [T.pack "ItemAdded"]
    additiveEventKindMap
      `shouldBe` [(T.pack "ItemAdded", T.pack "ItemAdded")]

  it "decodes bytes written before the additive fields existed" $
    decodeAdditiveBytes oldAdditiveBytes
      `shouldBe` Right
        ( ItemAdded
            ItemAddedData
              { orderId = T.pack "ord-7",
                discount = missingDiscount,
                note = Nothing
              }
        )

  it "decodes a present null Maybe field as Nothing" $
    decodeAdditiveBytes
      "{\"kind\":\"ItemAdded\",\"orderId\":\"ord-7\",\"discount\":12,\"note\":null}"
      `shouldBe` Right
        ( ItemAdded
            ItemAddedData
              { orderId = T.pack "ord-7",
                discount = Discount 12,
                note = Nothing
              }
        )

  it "round-trips a fully populated value" $
    let event =
          ItemAdded
            ItemAddedData
              { orderId = T.pack "ord-8",
                discount = Discount 15,
                note = Just (T.pack "priority")
              }
     in additiveEventFromJSON (additiveEventToJSON event) `shouldBe` Right event

  it "round-trips generated Nothing and Just values" $
    forAllShow arbAdditiveEvent show roundTripProperty

  it "keeps required fields strict" $
    decodeAdditiveBytes "{\"kind\":\"ItemAdded\"}"
      `shouldBe` (Left "missing field: orderId" :: Either String AdditiveEvent)

  describe "upcaster chain" $ do
    let expected = QuantityRecorded (QuantityRecordedData 3)

    it "exports the structural fixture's current wire metadata" $ do
      structuralEventSchemaVersion `shouldBe` 2
      structuralEventEventTypes `shouldBe` [T.pack "QuantityRecorded"]
      structuralEventKindMap
        `shouldBe` [(T.pack "QuantityRecorded", T.pack "QuantityRecorded")]

    it "decodes version-1 bytes after renaming qty to quantity" $
      decodeStructuralBytes
        "{\"kind\":\"QuantityRecorded\",\"v\":1,\"qty\":3}"
        `shouldBe` Right expected

    it "runs the version-1 upcaster for an absent version stamp" $
      decodeStructuralBytes
        "{\"kind\":\"QuantityRecorded\",\"qty\":3}"
        `shouldBe` Right expected

    it "decodes current-version bytes without running an old rung" $ do
      decodeStructuralBytes
        "{\"kind\":\"QuantityRecorded\",\"v\":2,\"quantity\":3}"
        `shouldBe` Right expected
      structuralEventFromJSON (structuralEventToJSON expected)
        `shouldBe` Right expected

    it "surfaces a rung failure with its source version" $
      decodeStructuralBytes
        "{\"kind\":\"QuantityRecorded\",\"v\":1}"
        `shouldBe` ( Left "upcaster from version 1: missing qty" ::
                       Either String StructuralEvent
                   )
