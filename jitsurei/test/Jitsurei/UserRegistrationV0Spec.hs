module Jitsurei.UserRegistrationV0Spec (spec) where

import Data.List (isInfixOf)
import Data.Maybe (isNothing)
import Test.Hspec
import Keiki.Core
import Jitsurei.UserRegistrationV0


spec :: Spec
spec = do
  describe "userRegV0 — synthesis-§4 step-4 unfixed schema" $ do
    it "reconstitute returns Nothing on the V0 canonical log" $
      -- The V0 Confirm edge's OutFields does not carry confirmCode
      -- (the wireAccountConfirmedV0 wire's tuple shape drops it).
      -- The structural inverse (post-EP-1) sees that inCtorConfirm
      -- has a confirmCode slot the OutFields walk never visits, so
      -- assemble returns Nothing and replay halts. Same outcome as
      -- the v1 hand-written-Nothing inverse, but now structurally
      -- observable. RegFile has no Show instance, so we collapse the
      -- Maybe to a Bool before asserting.
      isNothing (reconstitute userRegV0 canonicalLogV0) `shouldBe` True

    it "checkHiddenInputs surfaces at least one warning" $ do
      let warnings = checkHiddenInputs userRegV0
      length warnings `shouldSatisfy` (> 0)

    it "checkHiddenInputs warning includes the RequiresConfirmation source" $
      let warnings = checkHiddenInputs userRegV0
          sources  = map hiwEdgeSource warnings
      in sources `shouldContain` ["RequiresConfirmation"]

    it "checkHiddenInputs warning names the missing InCtor and field" $
      -- Post-EP-1: the structural analyzer names the precise missing
      -- field. The Confirm edge's OutFields walks (#email, #at) but
      -- inCtorConfirm has slots [confirmCode, at]; \"confirmCode\" is
      -- left unrecovered.
      let warnings = checkHiddenInputs userRegV0
          reasons  = map hiwReason warnings
          inAny xs sub = any (sub `isInfixOf`) xs
      in do
        reasons `shouldSatisfy` (`inAny` "ConfirmAccount")
        reasons `shouldSatisfy` (`inAny` "confirmCode")
