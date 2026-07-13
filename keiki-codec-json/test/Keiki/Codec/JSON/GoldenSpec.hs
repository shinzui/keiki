-- | EP-36 M3 golden hash file.
--
-- Pins the canonical shape string and hash of 'ExemplarSlots'. Built-in
-- canonical names are module-independent, so these values are shared across
-- supported GHC versions.
module Keiki.Codec.JSON.GoldenSpec (spec) where

import Data.Proxy (Proxy (..))
import Data.Text qualified as T
import Keiki.Codec.JSON.Fixtures (ExemplarSlots)
import Keiki.Shape (regFileShapeCanonical, regFileShapeHash)
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec = describe "Golden hash for ExemplarSlots" $ do
  it "matches the pinned canonical string" $
    regFileShapeCanonical (Proxy @ExemplarSlots)
      `shouldBe` T.pack "retryCount:Int;cooldownUntil:UTCTime;correlationId:Text;regfile:0"

  it "matches the pinned GHC-independent value" $
    regFileShapeHash (Proxy @ExemplarSlots)
      `shouldBe` T.pack "d920c3660d5b2a7bda082cdedb08fa493acd3f74a663434a4cead475096866f9"
