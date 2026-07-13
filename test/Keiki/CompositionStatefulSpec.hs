module Keiki.CompositionStatefulSpec (spec) where

import Control.Exception (evaluate)
import Keiki.Composition (compose)
import Keiki.Core
import Keiki.Fixtures.ComposeStateful
import Test.Hspec

spec :: Spec
spec = do
  describe "compose counterSource lastValueSink" $
    it "stores the pre-increment count in the sink" $ do
      pendingWith "EP-74 M3"
      let pipeline = compose counterSource lastValueSink
      case step pipeline (initial pipeline, initialRegs pipeline) Tick of
        Just (_, regs, outputs) -> do
          readSourceCount regs `shouldBe` 1
          readSinkLast regs `shouldBe` 0
          outputs `shouldBe` [OutVal 0]
        Nothing -> expectationFailure "expected the composed counter step to succeed"

  describe "compose pairSource twoPhaseSink" $
    it "fires phase 1 then phase 2 and ends at phase 2" $ do
      pendingWith "EP-74 M4"
      let pipeline = compose pairSource twoPhaseSink
      case step pipeline (initial pipeline, initialRegs pipeline) Go of
        Just (_, regs, outputs) -> do
          readPhase regs `shouldBe` 2
          outputs `shouldBe` [Stage1 10, Stage2 20]
        Nothing -> expectationFailure "expected the composed two-phase step to succeed"

  describe "compose m2aSource wrongOrderSink" $
    it "steps via the M2A edge without raising" $ do
      pendingWith "EP-74 M5"
      let pipeline = compose m2aSource wrongOrderSink
      result <- evaluate (step pipeline (initial pipeline, initialRegs pipeline) ProduceA)
      case result of
        Just (_, _, outputs) -> outputs `shouldBe` [SawA 5]
        Nothing -> expectationFailure "expected the matching M2A edge to fire"
