-- | Checked-in persistence fixtures for whole register files and their shape.
--
-- Each register fixture is checked in both directions: current code decodes
-- historical bytes to a fixed heterogeneous value, and current encoding must
-- remain byte-identical. The Value and Encoding paths have separate files
-- because their object-key orders deliberately differ.
--
-- To regenerate only for an intentional wire-format change:
--
-- > KEIKI_UPDATE_GOLDENS=1 cabal test keiki-codec-json:keiki-codec-json-test
-- > cabal test keiki-codec-json:keiki-codec-json-test
-- > git diff keiki-codec-json/test/golden/
--
-- The first command rewrites the files and fails deliberately. The second must
-- be green after the environment variable is unset and the diff reviewed.
module Keiki.Codec.JSON.GoldenFileSpec (spec) where

import Data.Aeson qualified as Aeson
import Data.Aeson.Encoding qualified as AesonEnc
import Data.ByteString.Lazy qualified as LBS
import Data.Proxy (Proxy (..))
import Data.Text qualified as T
import Data.Time.Clock (UTCTime)
import Keiki.Codec.JSON (RegFileToJSON, regFileFromJSON, regFileToEncoding, regFileToJSON)
import Keiki.Codec.JSON.Fixtures
  ( Address (..),
    EqRegFile (eqRegFile),
    ExemplarSlots,
    MaybeSlots,
  )
import Keiki.Core (RegFile (..))
import Keiki.Shape (regFileShapeCanonical, regFileShapeHash)
import System.Environment (lookupEnv)
import Test.Hspec (Spec, describe, expectationFailure, it, runIO, shouldBe)

data EncoderPath = ValuePath | EncodingPath

spec :: Spec
spec = do
  describe "checked-in RegFile bytes" $ do
    regFileGoldenSpec
      "exemplar Value path"
      "test/golden/exemplar-regfile.value.json"
      ValuePath
      exemplarRegFile
    regFileGoldenSpec
      "exemplar Encoding path"
      "test/golden/exemplar-regfile.encoding.json"
      EncodingPath
      exemplarRegFile
    regFileGoldenSpec
      "all-Just Maybe slots, Value path"
      "test/golden/maybe-regfile-just.value.json"
      ValuePath
      maybeJustRegFile
    regFileGoldenSpec
      "all-Just Maybe slots, Encoding path"
      "test/golden/maybe-regfile-just.encoding.json"
      EncodingPath
      maybeJustRegFile
    regFileGoldenSpec
      "all-Nothing Maybe slots, Value path"
      "test/golden/maybe-regfile-nothing.value.json"
      ValuePath
      maybeNothingRegFile
    regFileGoldenSpec
      "all-Nothing Maybe slots, Encoding path"
      "test/golden/maybe-regfile-nothing.encoding.json"
      EncodingPath
      maybeNothingRegFile

  shapeGoldenSpec

regFileGoldenSpec ::
  forall rs.
  (RegFileToJSON rs, EqRegFile rs) =>
  String ->
  FilePath ->
  EncoderPath ->
  RegFile rs ->
  Spec
regFileGoldenSpec label path encoder expected = describe label $ do
  update <- runIO (lookupEnv "KEIKI_UPDATE_GOLDENS")
  case update of
    Just _ -> do
      runIO (LBS.writeFile path currentBytes)
      it "regenerates and requires a clean review run" $
        expectationFailure regenerationMessage
    Nothing -> do
      historicalBytes <- runIO (LBS.readFile path)
      it "decodes checked-in bytes to the fixed value" $
        case Aeson.decode historicalBytes of
          Nothing -> expectationFailure "golden file is not valid JSON"
          Just value -> case regFileFromJSON @rs value of
            Left message -> expectationFailure ("golden decode failed: " <> message)
            Right actual -> eqRegFile actual expected `shouldBe` True
      it "freezes current encoder bytes" $
        currentBytes `shouldBe` historicalBytes
  where
    currentBytes = case encoder of
      ValuePath -> Aeson.encode (regFileToJSON expected)
      EncodingPath -> AesonEnc.encodingToLazyByteString (regFileToEncoding expected)

shapeGoldenSpec :: Spec
shapeGoldenSpec = describe "checked-in ExemplarSlots shape" $ do
  update <- runIO (lookupEnv "KEIKI_UPDATE_GOLDENS")
  case update of
    Just _ -> do
      runIO (LBS.writeFile shapePath currentBytes)
      it "regenerates and requires a clean review run" $
        expectationFailure regenerationMessage
    Nothing -> do
      historicalBytes <- runIO (LBS.readFile shapePath)
      it "pins the canonical text and hash" $
        Aeson.decode historicalBytes `shouldBe` Just currentValue
      it "freezes the shape fixture bytes" $
        currentBytes `shouldBe` historicalBytes
  where
    shapePath = "test/golden/exemplar-shape.json"
    currentValue =
      Aeson.object
        [ "canonical" Aeson..= regFileShapeCanonical (Proxy @ExemplarSlots),
          "hash" Aeson..= regFileShapeHash (Proxy @ExemplarSlots)
        ]
    currentBytes = Aeson.encode currentValue

exemplarRegFile :: RegFile ExemplarSlots
exemplarRegFile =
  RCons (Proxy @"retryCount") (3 :: Int) $
    RCons (Proxy @"cooldownUntil") exemplarTime $
      RCons (Proxy @"correlationId") (T.pack "order-123") RNil

maybeJustRegFile :: RegFile MaybeSlots
maybeJustRegFile =
  RCons (Proxy @"lastError") (Just (T.pack "address invalid")) $
    RCons (Proxy @"approvedAt") (Just exemplarTime) $
      RCons
        (Proxy @"shippingAddress")
        (Just (Address (T.pack "1 Main St") (T.pack "Portland") (T.pack "97201")))
        RNil

maybeNothingRegFile :: RegFile MaybeSlots
maybeNothingRegFile =
  RCons (Proxy @"lastError") Nothing $
    RCons (Proxy @"approvedAt") Nothing $
      RCons (Proxy @"shippingAddress") Nothing RNil

exemplarTime :: UTCTime
exemplarTime = read "2026-01-02 03:04:05 UTC"

regenerationMessage :: String
regenerationMessage =
  "golden regenerated; unset KEIKI_UPDATE_GOLDENS, re-run, and review git diff"
