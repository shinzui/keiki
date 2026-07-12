module Keiki.CoreHiddenInputsGSMSpec (spec) where

import Data.List (isInfixOf)
import Keiki.Core
import Keiki.Fixtures.SplitCoverage
import Test.Hspec

falseEdge ::
  SymTransducer (HsPred '[] SplitCmd) '[] Bool SplitCmd SplitEvent ->
  Edge (HsPred '[] SplitCmd) '[] SplitCmd SplitEvent Bool
falseEdge t = case edgesOut t False of
  [edge] -> edge
  _ -> error "SplitCoverage fixture must have exactly one edge from False"

spec :: Spec
spec = do
  describe "checkHiddenInputs head recoverability (EP-71)" $ do
    it "split coverage reports tail-only slot c" $ do
      let reasons = hiddenInputReasons (falseEdge splitCoverageBad)
      reasons `shouldBe` [HirHeadUnrecoverable "Begin" ["c"]]
      let warnings = checkHiddenInputs splitCoverageBad
      length warnings `shouldBe` 1
      case warnings of
        [w] -> do
          hiwEdgeSource w `shouldBe` "False"
          hiwReason w `shouldSatisfy` ("head event" `isInfixOf`)
          hiwReason w `shouldSatisfy` ("\"c\"" `isInfixOf`)
        _ -> expectationFailure "expected exactly one warning"

    it "union miss keeps naming off-wire slot c" $ do
      let reasons = hiddenInputReasons (falseEdge splitCoverageUnionMiss)
      reasons `shouldBe` [HirUnionMiss "Begin" ["c"]]

    it "single-event miss keeps naming b and c" $ do
      let reasons = hiddenInputReasons (falseEdge splitCoverageSingleMiss)
      reasons `shouldBe` [HirUnionMiss "Begin" ["b", "c"]]

    it "a head-complete multi-event edge is clean" $
      hiddenInputReasons (falseEdge splitCoverageFixed) `shouldBe` []

    it "structured validation reports HeadUnrecoverable" $ do
      let warnings = validateTransducer defaultValidationOptions splitCoverageBad
          isHeadWarning
            ( HeadUnrecoverable
                { tvwEdge = EdgeRef {edgeSource = False, edgeIndex = 0},
                  tvwInCtor = Just "Begin",
                  tvwTailOnlySlots = ["c"]
                }
              ) = True
          isHeadWarning _ = False
      warnings `shouldSatisfy` any isHeadWarning
