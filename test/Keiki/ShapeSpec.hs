
-- | EP-36 M1: golden-value tests for 'Keiki.Shape'.
--
-- The expected strings are pinned for GHC 9.12.* (the current sole entry
-- in @tested-with@). If a future GHC moves @Int@ out of @GHC.Types@ or
-- renames @GHC.Internal.Maybe@, these tests catch the drift; EP-36 §8
-- documents the procedure (audit, mitigate via 'CanonicalTypeName'
-- overrides, decide whether to ship a migration). See EP-36 §3 R4 (cross-
-- version stability) and §5 P5 (the hash uses only stable accessors).
module Keiki.ShapeSpec (spec) where

import Data.Kind (Type)
import Data.Proxy (Proxy (..))
import qualified Data.Text as T
import Data.Time.Clock (UTCTime)
import GHC.TypeLits (Symbol)
import Test.Hspec (Spec, describe, it, shouldBe)
import Type.Reflection (someTypeRep)

import Keiki.Shape
  ( regFileShapeCanonical
  , regFileShapeHash
  , renderStableTypeRep
  , sha256Hex
  )


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
      regFileShapeCanonical (Proxy @('[ '("retryCount", Int) ] :: [(Symbol, Type)]))
        `shouldBe` T.pack "retryCount:GHC.Types.Int;regfile:0"

  describe "regFileShapeHash" $ do
    it "produces the pinned SHA-256 of \"regfile:0\" for the empty list" $
      regFileShapeHash (Proxy @('[] :: [(Symbol, Type)]))
        `shouldBe`
        T.pack "0b262a9e301796f7a5b36bb6ea874e9ffccf7d1b4aff78a8d4b5436bd23914a6"

    it "produces the pinned hash for a one-slot list (retryCount :: Int)" $
      regFileShapeHash (Proxy @('[ '("retryCount", Int) ] :: [(Symbol, Type)]))
        `shouldBe`
        T.pack "e2c8839d9ae8e89baebbc1adf6dfd5a35608712d9bf994c7cef4ea774e739700"

    it "differs when slot order is reversed (P10: slot order is identity)" $
      regFileShapeHash
        (Proxy @('[ '("retryCount", Int), '("cooldownUntil", UTCTime) ] :: [(Symbol, Type)]))
        `shouldBe`
        T.pack "944d775449408b12b78b2a41770af207bae37d0a833c046310eb6ff3902ea44f"

    it "matches its sha256Hex-of-canonical definition" $ do
      let p = Proxy @('[ '("retryCount", Int), '("cooldownUntil", UTCTime) ] :: [(Symbol, Type)])
      regFileShapeHash p `shouldBe` sha256Hex (regFileShapeCanonical p)

  describe "sha256Hex" $ do
    -- "" → e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
    -- "abc" → ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
    it "matches the empty-string SHA-256 vector" $
      sha256Hex (T.pack "")
        `shouldBe`
        T.pack "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    it "matches the \"abc\" SHA-256 vector" $
      sha256Hex (T.pack "abc")
        `shouldBe`
        T.pack "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
