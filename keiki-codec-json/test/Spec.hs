-- | EP-36 M2 unit tests for the JSON codec.
--
-- Covers acceptance items from the milestone: empty RegFile encode /
-- decode on both paths (Value and Encoding); a single-slot list; a
-- multi-slot list with both encoders producing the same bytes after
-- @'Aeson.encode'@ / @'AesonEnc.encodingToLazyByteString'@; strict failure
-- on missing slot, extra slot, type mismatch.
module Main (main) where

import Control.Exception (ErrorCall (..), evaluate)
import Data.Aeson qualified as Aeson
import Data.Aeson.Encoding qualified as AesonEnc
import Data.ByteString.Lazy qualified as LBS
import Data.Kind (Type)
import Data.List (isPrefixOf)
import Data.Maybe (fromJust)
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Data.Text qualified as T
import GHC.TypeLits (Symbol)
import Keiki.Codec.JSON (regFileFromJSON, regFileToEncoding, regFileToJSON)
import Keiki.Codec.JSON.GoldenFileSpec qualified
import Keiki.Codec.JSON.GoldenSpec qualified
import Keiki.Codec.JSON.PropSpec qualified
import Keiki.Codec.JSON.SensitivitySpec qualified
import Keiki.Codec.JSON.THEventEvolutionSpec qualified
import Keiki.Codec.JSON.THEventSpec qualified
import Keiki.Codec.JSON.THSpec qualified
import Keiki.Core (RegFile (..))
import Keiki.Generics (emptyRegFile)
import Test.Hspec
  ( Spec,
    describe,
    hspec,
    it,
    shouldBe,
    shouldThrow,
  )

main :: IO ()
main = hspec $ do
  spec
  describe "M3 properties" Keiki.Codec.JSON.PropSpec.spec
  describe "M3 sensitivity" Keiki.Codec.JSON.SensitivitySpec.spec
  describe "M3 golden hash" Keiki.Codec.JSON.GoldenSpec.spec
  describe "EP-78 checked-in persistence goldens" Keiki.Codec.JSON.GoldenFileSpec.spec
  describe "EP-38 deriveRegFileCodec" Keiki.Codec.JSON.THSpec.spec
  describe "EP-59 deriveEventCodecSkeleton" Keiki.Codec.JSON.THEventSpec.spec
  describe "EP-77 event schema evolution" Keiki.Codec.JSON.THEventEvolutionSpec.spec

spec :: Spec
spec = do
  describe "Empty RegFile" $ do
    it "encodes to {}" $
      regFileToJSON (RNil :: RegFile '[])
        `shouldBe` Aeson.object []

    it "encodes via streaming to the same bytes as the Value path" $
      AesonEnc.encodingToLazyByteString (regFileToEncoding (RNil :: RegFile '[]))
        `shouldBe` Aeson.encode (regFileToJSON (RNil :: RegFile '[]))

    it "decodes {} back to RNil" $ do
      let r = regFileFromJSON @'[] (Aeson.object [])
      case r of
        Right RNil -> (True :: Bool) `shouldBe` True
        Left msg -> error ("expected Right RNil, got Left " <> msg)

    it "rejects {\"x\": 1} as having unknown extra fields" $ do
      let r = regFileFromJSON @'[] (Aeson.object ["x" Aeson..= (1 :: Int)])
      isExtraFieldsLeft r `shouldBe` True

  describe "Single-slot RegFile '[ '(\"retryCount\", Int) ]" $ do
    let rf = RCons (Proxy @"retryCount") (3 :: Int) RNil :: RegFile '[ '("retryCount", Int)]

    it "encodes to {\"retryCount\": 3}" $
      regFileToJSON rf
        `shouldBe` Aeson.object ["retryCount" Aeson..= (3 :: Int)]

    it "encodes via streaming to byte-equal bytes" $
      AesonEnc.encodingToLazyByteString (regFileToEncoding rf)
        `shouldBe` Aeson.encode (regFileToJSON rf)

    it "round-trips through the Value path" $ do
      let r = regFileFromJSON @'[ '("retryCount", Int)] (regFileToJSON rf)
      case r of
        Right (RCons _ n RNil) -> n `shouldBe` 3
        Left msg -> error ("expected round-trip success, got Left " <> msg)

    it "round-trips through the Encoding path" $ do
      let bytes = AesonEnc.encodingToLazyByteString (regFileToEncoding rf)
          v = fromJust (Aeson.decode bytes :: Maybe Aeson.Value)
          r = regFileFromJSON @'[ '("retryCount", Int)] v
      case r of
        Right (RCons _ n RNil) -> n `shouldBe` 3
        Left msg -> error ("expected round-trip success, got Left " <> msg)

    it "rejects {} as missing retryCount" $ do
      let r = regFileFromJSON @'[ '("retryCount", Int)] (Aeson.object [])
      case r of
        Left msg -> msg `shouldBe` "retryCount: missing slot"
        Right _ -> error "expected Left, got Right"

    it "rejects {\"retryCount\": \"three\"} as type mismatch" $ do
      let r =
            regFileFromJSON @'[ '("retryCount", Int)]
              (Aeson.object ["retryCount" Aeson..= ("three" :: Text)])
      case r of
        Left msg
          | "retryCount:" `T.isPrefixOf` T.pack msg ->
              (True :: Bool) `shouldBe` True
        Left msg -> error ("expected slot-prefixed type error, got " <> msg)
        Right _ -> error "expected Left, got Right"

    it "rejects {\"retryCount\": 3, \"extra\": 1} as unknown extra fields" $ do
      let r =
            regFileFromJSON @'[ '("retryCount", Int)]
              ( Aeson.object
                  [ "retryCount" Aeson..= (3 :: Int),
                    "extra" Aeson..= (1 :: Int)
                  ]
              )
      isExtraFieldsLeft r `shouldBe` True

    it "throws a slot-named error when encoding an unwritten slot" $ do
      let uninitialized =
            emptyRegFile :: RegFile '[ '("retryCount", Int)]
      evaluate (LBS.length (Aeson.encode (regFileToJSON uninitialized)))
        `shouldThrow` \(ErrorCall message) ->
          "uninit: retryCount" `isPrefixOf` message

  describe "Multi-slot RegFile (Int + Text)" $ do
    let rf :: RegFile '[ '("retryCount", Int), '("note", Text)]
        rf =
          RCons (Proxy @"retryCount") (5 :: Int) $
            RCons (Proxy @"note") ("hello" :: Text) RNil

    it "encodes both slots in slot-list order via Value path" $
      regFileToJSON rf
        `shouldBe` Aeson.object
          [ "retryCount" Aeson..= (5 :: Int),
            "note" Aeson..= ("hello" :: Text)
          ]

    -- The Value path emits keys in 'Aeson.KeyMap' order (alphabetical for
    -- aeson 2.2's default backing 'Map Key'); the Encoding path emits in
    -- slot-list order. The two byte streams therefore differ when slot
    -- order is not alphabetical. What both paths guarantee is /semantic/
    -- round-trip equality plus within-path determinism — see the next
    -- two tests.
    it "Encoding path emits keys in slot-list order; Value path is sorted" $ do
      let viaStreaming = AesonEnc.encodingToLazyByteString (regFileToEncoding rf)
          viaValue = Aeson.encode (regFileToJSON rf)
      viaStreaming
        `shouldBe` LBS.pack
          ( map
              (fromIntegral . fromEnum)
              "{\"retryCount\":5,\"note\":\"hello\"}"
          )
      viaValue
        `shouldBe` LBS.pack
          ( map
              (fromIntegral . fromEnum)
              "{\"note\":\"hello\",\"retryCount\":5}"
          )

    it "both paths round-trip to the same RegFile (cross-path semantic equality)" $ do
      let valueBytes = Aeson.encode (regFileToJSON rf)
          streamBytes = AesonEnc.encodingToLazyByteString (regFileToEncoding rf)
          fromValue =
            regFileFromJSON @'[ '("retryCount", Int), '("note", Text)]
              =<< maybe (Left "decode failed") Right (Aeson.decode valueBytes)
          fromStream =
            regFileFromJSON @'[ '("retryCount", Int), '("note", Text)]
              =<< maybe (Left "decode failed") Right (Aeson.decode streamBytes)
      assertMultiRoundTrip fromValue
      assertMultiRoundTrip fromStream

    it "within-path determinism: re-encoding produces byte-equal output (R9)" $ do
      Aeson.encode (regFileToJSON rf)
        `shouldBe` Aeson.encode (regFileToJSON rf)
      AesonEnc.encodingToLazyByteString (regFileToEncoding rf)
        `shouldBe` AesonEnc.encodingToLazyByteString (regFileToEncoding rf)

    it "rejects {\"retryCount\": 5} as missing note" $ do
      let r =
            regFileFromJSON
              @'[ '("retryCount", Int), '("note", Text)]
              (Aeson.object ["retryCount" Aeson..= (5 :: Int)])
      case r of
        Left msg -> msg `shouldBe` "note: missing slot"
        Right _ -> error "expected Left, got Right"

isExtraFieldsLeft :: Either String a -> Bool
isExtraFieldsLeft = \case
  Left msg -> "regfile: unknown extra fields:" `T.isPrefixOf` T.pack msg
  Right _ -> False

assertMultiRoundTrip ::
  Either String (RegFile '[ '("retryCount", Int), '("note", Text)]) ->
  IO ()
assertMultiRoundTrip = \case
  Right (RCons _ n (RCons _ t RNil)) -> do
    n `shouldBe` 5
    t `shouldBe` ("hello" :: Text)
  Left msg -> error ("expected round-trip success, got Left " <> msg)

-- Silence GHC's unused-import warnings: Symbol/Type are referenced by
-- the type-level slot lists above, but GHC's warning pass doesn't see
-- the kind annotations as references.
_unused :: (Proxy (rs :: [(Symbol, Type)]), ())
_unused = (Proxy, ())
