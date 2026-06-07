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
import Keiki.Codec.JSON (regFileFromJSON, regFileToEncoding, regFileToJSON)
import Keiki.Codec.JSON.Fixtures (ExemplarSlots, arbRegFile)
import Keiki.Core (RegFile)
import Test.Hspec (Spec, describe, it)
import Test.QuickCheck (Property, forAllShow, (===))

-- | RegFile rs has no Show instance (the slot list is heterogeneous);
-- use the JSON encoding as the renderer for QuickCheck counterexamples.
showRegFile :: RegFile ExemplarSlots -> String
showRegFile = show . regFileToJSON

spec :: Spec
spec = do
  describe "Roundtrip" $ do
    it "Value path round-trips" $
      forAllShow arbRegFile showRegFile valueRoundTrip
    it "Encoding path round-trips" $
      forAllShow arbRegFile showRegFile encodingRoundTrip

  describe "Determinism (R9 within-path)" $ do
    it "Value path is deterministic" $
      forAllShow arbRegFile showRegFile valueDeterministic
    it "Encoding path is deterministic" $
      forAllShow arbRegFile showRegFile encodingDeterministic

-- | @regFileFromJSON . regFileToJSON ≡ Right rf@. We use the encoded
-- bytes as the canonical comparison point: re-encoding the parsed
-- RegFile must yield the same bytes (proving structural equality
-- without requiring a 'Eq' or 'Show' instance on 'RegFile').
valueRoundTrip :: RegFile ExemplarSlots -> Property
valueRoundTrip rf =
  let bytes = Aeson.encode (regFileToJSON rf)
   in case Aeson.decode bytes of
        Nothing ->
          False === error "Aeson.decode failed on our own encoder output"
        Just v -> case regFileFromJSON @ExemplarSlots v of
          Left msg ->
            False === error ("regFileFromJSON failed: " <> msg)
          Right rf' ->
            Aeson.encode (regFileToJSON rf') === bytes

-- | Encoding path round-trip via
-- @regFileFromJSON . fromJust . Aeson.decode . AesonEnc.encodingToLazyByteString . regFileToEncoding@.
encodingRoundTrip :: RegFile ExemplarSlots -> Property
encodingRoundTrip rf =
  let bytes = AesonEnc.encodingToLazyByteString (regFileToEncoding rf)
   in case Aeson.decode bytes of
        Nothing ->
          False === error "Aeson.decode failed on streaming-encoder output"
        Just v -> case regFileFromJSON @ExemplarSlots v of
          Left msg ->
            False === error ("regFileFromJSON failed: " <> msg)
          Right rf' ->
            AesonEnc.encodingToLazyByteString (regFileToEncoding rf') === bytes

-- | Re-encoding the same RegFile via the Value path produces byte-
-- equal output.
valueDeterministic :: RegFile ExemplarSlots -> Property
valueDeterministic rf =
  Aeson.encode (regFileToJSON rf)
    === Aeson.encode (regFileToJSON rf)

-- | Re-encoding via the Encoding path produces byte-equal output.
encodingDeterministic :: RegFile ExemplarSlots -> Property
encodingDeterministic rf =
  AesonEnc.encodingToLazyByteString (regFileToEncoding rf)
    === AesonEnc.encodingToLazyByteString (regFileToEncoding rf)
