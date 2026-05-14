{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}

-- | EP-38 M3 tests for 'Keiki.Codec.JSON.TH.deriveRegFileCodec'.
--
-- The splice emits three top-level functions per record type. This spec
-- exercises the round-trip and strict-decoder properties of the emitted
-- functions against two test records — a non-trivial @TestRec@ and the
-- @Empty@ singleton — and verifies the encoding-path / value-path
-- semantic-round-trip agreement (the same invariant the in-tree M2 and
-- M3 specs exercise for the underlying class).
--
-- == Negative-test procedure (manual)
--
-- The splice's contract is that a record whose field type lacks
-- 'Aeson.ToJSON' or 'Aeson.FromJSON' fails to compile. This is not
-- expressible in a passing unit test, so the procedure is manual:
--
-- 1. Edit @TestRec@ below to add a field @trBad :: Int -> Int@.
-- 2. Run @cabal build keiki-codec-json:keiki-codec-json-test@.
-- 3. The build must fail with @No instance for 'Aeson.ToJSON' (Int -> Int)@
--    pointing at the use site of @testRecToJSON@.
-- 4. Revert. The expected error proves the splice's elaboration trips
--    the missing-instance check; an automated should-not-compile test
--    is out of scope for v0.2.
module Keiki.Codec.JSON.THSpec (spec) where

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Encoding as AesonEnc
import Data.Maybe (fromJust)
import qualified Data.Text as T
import Data.Text (Text)
import GHC.Generics (Generic)
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

import Keiki.Codec.JSON.TH (deriveRegFileCodec)


-- * Test fixtures -----------------------------------------------------------

-- | Non-trivial two-field record used to exercise round-trip and strict
-- decoder behaviour.
data TestRec = TestRec
  { trCount :: Int
  , trNote  :: Text
  }
  deriving stock (Eq, Show, Generic)


$(deriveRegFileCodec ''TestRec)


-- | Singleton record used to exercise the empty-slot-list edge case.
data Empty = Empty
  deriving stock (Eq, Show, Generic)


$(deriveRegFileCodec ''Empty)


-- * Spec --------------------------------------------------------------------


spec :: Spec
spec = describe "deriveRegFileCodec" $ do
  let tr  = TestRec { trCount = 7, trNote = T.pack "hi" }

  describe "TestRec — round-trip and encoding agreement" $ do
    it "Value path round-trips" $
      testRecFromJSON (testRecToJSON tr) `shouldBe` Right tr

    it "Encoding path bytes parse back to the same value" $ do
      let bytes = AesonEnc.encodingToLazyByteString (testRecToEncoding tr)
          v     = fromJust (Aeson.decode bytes :: Maybe Aeson.Value)
      testRecFromJSON v `shouldBe` Right tr

    it "Value path emits both slots in slot-list order" $
      testRecToJSON tr
        `shouldBe`
        Aeson.object
          [ "trCount" Aeson..= (7 :: Int)
          , "trNote"  Aeson..= T.pack "hi"
          ]

  describe "TestRec — strict decoder" $ do
    it "rejects an Object missing trCount with a slot-prefixed message" $ do
      let v = Aeson.object [ "trNote" Aeson..= T.pack "hi" ]
      testRecFromJSON v `shouldBe` Left "trCount: missing slot"

    it "rejects an Object with an unknown extra field" $ do
      let v = Aeson.object
                [ "trCount" Aeson..= (7 :: Int)
                , "trNote"  Aeson..= T.pack "hi"
                , "bogus"   Aeson..= (1 :: Int)
                ]
      testRecFromJSON v `shouldSatisfy` isExtraFieldsLeft

    it "rejects a type-mismatched field with a slot-prefixed message" $ do
      let v = Aeson.object
                [ "trCount" Aeson..= T.pack "seven"
                , "trNote"  Aeson..= T.pack "hi"
                ]
      testRecFromJSON v `shouldSatisfy` hasPrefix "trCount:"

  describe "Empty — empty-slot-list edge case" $ do
    it "encodes Empty to the empty JSON object" $
      emptyToJSON Empty `shouldBe` Aeson.object []

    it "decodes the empty JSON object back to Empty" $
      emptyFromJSON (Aeson.object []) `shouldBe` Right Empty

    it "encodes Empty via the streaming path to the literal bytes {}" $
      AesonEnc.encodingToLazyByteString (emptyToEncoding Empty)
        `shouldBe` AesonEnc.encodingToLazyByteString (AesonEnc.pairs mempty)

    it "rejects a non-empty JSON object as unknown extra fields" $
      emptyFromJSON (Aeson.object [ "x" Aeson..= (1 :: Int) ])
        `shouldSatisfy` isExtraFieldsLeft


-- * Helpers -----------------------------------------------------------------

isExtraFieldsLeft :: Either String a -> Bool
isExtraFieldsLeft = \case
  Left msg -> T.pack "regfile: unknown extra fields:" `T.isPrefixOf` T.pack msg
  Right _  -> False


hasPrefix :: String -> Either String a -> Bool
hasPrefix p = \case
  Left msg -> T.pack p `T.isPrefixOf` T.pack msg
  Right _  -> False
