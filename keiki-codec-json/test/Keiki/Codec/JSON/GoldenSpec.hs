-- | EP-36 M3 golden hash file.
--
-- Pins the shape hash of 'ExemplarSlots' for the current GHC version.
-- The cross-GHC CI gate (M5) compares this value across every GHC in
-- @tested-with@; a divergence is a release-blocking bug per EP-36 §8.
module Keiki.Codec.JSON.GoldenSpec (spec) where

import Data.Proxy (Proxy (..))
import qualified Data.Text as T
import Test.Hspec (Spec, describe, it, shouldBe)

import Keiki.Shape (regFileShapeHash)

import Keiki.Codec.JSON.Fixtures (ExemplarSlots)


spec :: Spec
spec = describe "Golden hash for ExemplarSlots" $ do
  -- This value is pinned for GHC 9.12.*. Drift here means either
  -- GHC's `tyConModule` / `tyConName` semantics changed for one of
  -- the slot types (Int / UTCTime / Text), or `renderStableTypeRep`
  -- inadvertently picked up a non-stable accessor. Per EP-36 §8 the
  -- release is blocked until the cause is understood; the fix may be a
  -- `CanonicalTypeName` override for the affected slot type.
  it "matches the pinned GHC-9.12.* value" $
    regFileShapeHash (Proxy @ExemplarSlots)
      `shouldBe`
      T.pack "a37b2b77042a635f394a082765f3410ea23a0b89745b0c77242b925a03aa172b"
