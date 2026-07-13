-- | EP-36 M1: golden-value tests for 'Keiki.Shape'.
--
-- The raw 'renderStableTypeRep' expectations remain pinned for GHC 9.12.*.
-- Shape canonicalization uses explicit built-in names instead, so GHC-internal
-- module moves no longer change snapshot hashes.
module Keiki.ShapeSpec (spec) where

import Data.Int (Int16, Int32, Int64, Int8)
import Data.Kind (Type)
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Calendar (Day)
import Data.Time.Clock (UTCTime)
import Data.Word (Word16, Word32, Word64, Word8)
import GHC.TypeLits (Symbol)
import Keiki.Shape
  ( CanonicalTypeName (..),
    regFileShapeCanonical,
    regFileShapeHash,
    renderStableTypeRep,
    sha256Hex,
  )
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)
import Type.Reflection (someTypeRep)

data ApplicationType

instance CanonicalTypeName ApplicationType where
  canonicalTypeName _ = T.pack "ApplicationType-v1"

type BuiltInSlots =
  '[ '("unit", ()),
     '("bool", Bool),
     '("char", Char),
     '("int", Int),
     '("int8", Int8),
     '("int16", Int16),
     '("int32", Int32),
     '("int64", Int64),
     '("integer", Integer),
     '("word", Word),
     '("word8", Word8),
     '("word16", Word16),
     '("word32", Word32),
     '("word64", Word64),
     '("double", Double),
     '("float", Float),
     '("text", Text),
     '("utcTime", UTCTime),
     '("day", Day),
     '("maybe", Maybe Int),
     '("list", [Text]),
     '("either", Either Int Text),
     '("pair", (Int, Text)),
     '("triple", (Int, Text, Bool))
   ]

spec :: Spec
spec = do
  describe "renderStableTypeRep" $ do
    it "renders Int as GHC.Types.Int (no module path drift on 9.12.*)" $
      renderStableTypeRep (someTypeRep (Proxy @Int))
        `shouldBe` T.pack "GHC.Types.Int"

    it "renders Maybe Int as a parenthesised application" $
      renderStableTypeRep (someTypeRep (Proxy @(Maybe Int)))
        `shouldBe` T.pack "GHC.Internal.Maybe.Maybe(GHC.Types.Int)"

    it "renders UTCTime as its time-library module path" $
      renderStableTypeRep (someTypeRep (Proxy @UTCTime))
        `shouldBe` T.pack "Data.Time.Clock.Internal.UTCTime.UTCTime"

  describe "regFileShapeCanonical" $ do
    it "anchors the empty slot list at \"regfile:0\"" $
      regFileShapeCanonical (Proxy @('[] :: [(Symbol, Type)]))
        `shouldBe` T.pack "regfile:0"

    it "concatenates one slot in the documented R3 form" $
      regFileShapeCanonical (Proxy @('[ '("retryCount", Int)] :: [(Symbol, Type)]))
        `shouldBe` T.pack "retryCount:Int;regfile:0"

    it "keeps GHC-internal module paths out of every built-in name" $ do
      let canonical = regFileShapeCanonical (Proxy @BuiltInSlots)
      canonical `shouldSatisfy` (not . T.isInfixOf (T.pack "GHC.Internal"))
      canonical `shouldSatisfy` (not . T.isInfixOf (T.pack "GHC.Types"))

    it "propagates an application override through containers" $
      regFileShapeCanonical
        (Proxy @('[ '("application", Maybe ApplicationType)] :: [(Symbol, Type)]))
        `shouldBe` T.pack "application:Maybe(ApplicationType-v1);regfile:0"

  describe "regFileShapeHash" $ do
    it "produces the pinned SHA-256 of \"regfile:0\" for the empty list" $
      regFileShapeHash (Proxy @('[] :: [(Symbol, Type)]))
        `shouldBe` T.pack "0b262a9e301796f7a5b36bb6ea874e9ffccf7d1b4aff78a8d4b5436bd23914a6"

    it "produces the pinned hash for a one-slot list (retryCount :: Int)" $
      regFileShapeHash (Proxy @('[ '("retryCount", Int)] :: [(Symbol, Type)]))
        `shouldBe` T.pack "de03289268ae222f84d8a1b9af8f4f78bc9d23a747c97c12f4974e2504485978"

    it "differs when slot order is reversed (P10: slot order is identity)" $
      regFileShapeHash
        (Proxy @('[ '("retryCount", Int), '("cooldownUntil", UTCTime)] :: [(Symbol, Type)]))
        `shouldBe` T.pack "22a08cf2b847545bf0ce24f505de379ee49c2edb8c2236b6f6bcfadba984b1ea"

    it "matches its sha256Hex-of-canonical definition" $ do
      let p = Proxy @('[ '("retryCount", Int), '("cooldownUntil", UTCTime)] :: [(Symbol, Type)])
      regFileShapeHash p `shouldBe` sha256Hex (regFileShapeCanonical p)

  describe "sha256Hex" $ do
    -- "" → e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
    -- "abc" → ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
    it "matches the empty-string SHA-256 vector" $
      sha256Hex (T.pack "")
        `shouldBe` T.pack "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    it "matches the \"abc\" SHA-256 vector" $
      sha256Hex (T.pack "abc")
        `shouldBe` T.pack "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
