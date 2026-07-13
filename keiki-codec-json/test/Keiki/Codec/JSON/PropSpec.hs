-- | EP-36 M3 property tests: roundtrip on both encoder paths plus
-- within-path encoding determinism (R9).
--
-- The Value path and Encoding path are exercised independently. Cross-
-- path byte equality is /not/ asserted because aeson 2.2's
-- @Aeson.Value@ Object iterates 'Aeson.KeyMap' in (alphabetical)
-- KeyMap order, while the Encoding path emits in slot-list order via
-- @Aeson.Series@. See EP-36 Surprises & Discoveries for the
-- 2026-05-13 M2 entry documenting this.
module Keiki.Codec.JSON.PropSpec (spec) where

import Data.Aeson qualified as Aeson
import Data.Aeson.Encoding qualified as AesonEnc
import Data.Proxy (Proxy (..))
import Keiki.Codec.JSON (RegFileToJSON, regFileFromJSON, regFileToEncoding, regFileToJSON)
import Keiki.Codec.JSON.Fixtures
  ( ArbitraryRegFile (arbRegFile),
    EqRegFile (eqRegFile),
    ExemplarSlots,
    MaybeSlots,
    NestedMaybeSlots,
  )
import Keiki.Core (RegFile)
import Keiki.Core qualified as Core
import Test.Hspec (Spec, describe, it, shouldBe)
import Test.QuickCheck (Property, forAllShow, (===))

-- | RegFile rs has no Show instance (the slot list is heterogeneous);
-- use the JSON encoding as the renderer for QuickCheck counterexamples.
showRegFile :: (RegFileToJSON rs) => RegFile rs -> String
showRegFile = show . regFileToJSON

spec :: Spec
spec = do
  describe "ExemplarSlots" (codecProps @ExemplarSlots)
  describe "MaybeSlots" (codecProps @MaybeSlots)
  nestedMaybeSpec

codecProps ::
  forall rs.
  (RegFileToJSON rs, ArbitraryRegFile rs, EqRegFile rs) =>
  Spec
codecProps = do
  describe "Roundtrip" $ do
    it "Value path round-trips" $
      forAllShow (arbRegFile @rs) showRegFile (valueRoundTrip @rs)
    it "Encoding path round-trips" $
      forAllShow (arbRegFile @rs) showRegFile (encodingRoundTrip @rs)

  describe "Determinism (R9 within-path)" $ do
    it "Value path is deterministic" $
      forAllShow (arbRegFile @rs) showRegFile valueDeterministic
    it "Encoding path is deterministic" $
      forAllShow (arbRegFile @rs) showRegFile encodingDeterministic

-- | @regFileFromJSON . regFileToJSON ≡ Right rf@. We compare decoded
-- slot values with the inductive 'EqRegFile' walker, so a lossy decode
-- cannot hide behind identical re-encoded bytes.
valueRoundTrip :: forall rs. (RegFileToJSON rs, EqRegFile rs) => RegFile rs -> Property
valueRoundTrip rf =
  let bytes = Aeson.encode (regFileToJSON rf)
   in case Aeson.decode bytes of
        Nothing ->
          False === error "Aeson.decode failed on our own encoder output"
        Just v -> case regFileFromJSON @rs v of
          Left msg ->
            False === error ("regFileFromJSON failed: " <> msg)
          Right rf' -> eqRegFile rf' rf === True

-- | Encoding path round-trip via
-- @regFileFromJSON . fromJust . Aeson.decode . AesonEnc.encodingToLazyByteString . regFileToEncoding@.
encodingRoundTrip :: forall rs. (RegFileToJSON rs, EqRegFile rs) => RegFile rs -> Property
encodingRoundTrip rf =
  let bytes = AesonEnc.encodingToLazyByteString (regFileToEncoding rf)
   in case Aeson.decode bytes of
        Nothing ->
          False === error "Aeson.decode failed on streaming-encoder output"
        Just v -> case regFileFromJSON @rs v of
          Left msg ->
            False === error ("regFileFromJSON failed: " <> msg)
          Right rf' -> eqRegFile rf' rf === True

-- | Re-encoding the same RegFile via the Value path produces byte-
-- equal output.
valueDeterministic :: (RegFileToJSON rs) => RegFile rs -> Property
valueDeterministic rf =
  Aeson.encode (regFileToJSON rf)
    === Aeson.encode (regFileToJSON rf)

-- | Re-encoding via the Encoding path produces byte-equal output.
encodingDeterministic :: (RegFileToJSON rs) => RegFile rs -> Property
encodingDeterministic rf =
  AesonEnc.encodingToLazyByteString (regFileToEncoding rf)
    === AesonEnc.encodingToLazyByteString (regFileToEncoding rf)

nestedMaybeSpec :: Spec
nestedMaybeSpec = describe "Nested Maybe wire semantics" $ do
  it "encodes Just Nothing as null and decodes it as outer Nothing" $ do
    let rf = nestedRegFile (Just Nothing)
    regFileToJSON rf
      `shouldBe` Aeson.object ["nested" Aeson..= Aeson.Null]
    assertNestedDecode rf Nothing

  it "round-trips Just (Just 42)" $
    assertNestedDecode (nestedRegFile (Just (Just 42))) (Just (Just 42))

  it "round-trips Nothing" $
    assertNestedDecode (nestedRegFile Nothing) Nothing

  it "rejects an absent Maybe slot rather than treating it as Nothing" $
    case regFileFromJSON @MaybeSlots
      ( Aeson.object
          [ "approvedAt" Aeson..= Aeson.Null,
            "shippingAddress" Aeson..= Aeson.Null
          ]
      ) of
      Left message -> message `shouldBe` "lastError: missing slot"
      Right _ -> error "expected an absent-slot failure"

nestedRegFile :: Maybe (Maybe Int) -> RegFile NestedMaybeSlots
nestedRegFile value = Core.RCons (Proxy @"nested") value Core.RNil

assertNestedDecode :: RegFile NestedMaybeSlots -> Maybe (Maybe Int) -> IO ()
assertNestedDecode rf expected =
  case regFileFromJSON @NestedMaybeSlots (regFileToJSON rf) of
    Left message -> error ("nested Maybe decode failed: " <> message)
    Right (Core.RCons _ actual Core.RNil) -> actual `shouldBe` expected
