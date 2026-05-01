module Keiki.Examples.UserRegistrationV0Spec (spec) where

import Data.Maybe (isNothing)
import Test.Hspec
import Keiki.Core
import Keiki.Examples.UserRegistrationV0


spec :: Spec
spec = do
  describe "userRegV0 — synthesis-§4 step-4 unfixed schema" $ do
    it "reconstitute returns Nothing on the V0 canonical log" $
      -- The Confirm edge's output (V0) does not carry confirmCode, so
      -- the user-supplied inverse cannot reconstruct ci, and replay
      -- halts. This is the canonical synthesis-§4 step-4 walkthrough,
      -- showing the bug at runtime. (RegFile has no Show instance,
      -- so we collapse the Maybe to a Bool before asserting.)
      isNothing (reconstitute userRegV0 canonicalLogV0) `shouldBe` True

    it "checkHiddenInputs surfaces at least one warning" $ do
      -- v1's check is conservative: it flags every OPack edge whose
      -- OutFields contains TInpField (because v1 cannot field-name-
      -- match input reads). The list is the v1 "candidates to review"
      -- surface; v2 narrows it via structural input projection.
      let warnings = checkHiddenInputs userRegV0
      length warnings `shouldSatisfy` (> 0)

    it "checkHiddenInputs warning includes the RequiresConfirmation source" $
      -- The bad Confirm edge lives in RequiresConfirmation. The
      -- warning list should mention it.
      let warnings = checkHiddenInputs userRegV0
          sources  = map hiwEdgeSource warnings
      in sources `shouldContain` ["RequiresConfirmation"]
