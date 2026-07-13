module Keiki.CompositionHomomorphismSpec (spec) where

import Control.Exception (evaluate)
import Control.Monad (foldM, forM_)
import Data.Text (Text)
import Data.Time (UTCTime)
import Keiki.Composition (Composite (..), compose)
import Keiki.CompositionSpec (AlertCmd, AlertRegs, alertSource, sampleTrigger)
import Keiki.Core
import Keiki.Fixtures.ComposeStateful
import Keiki.Fixtures.EmailDelivery (EmailRegs, emailDelivery)
import Keiki.Generics (Append)
import Test.Hspec

sequentialStep ::
  SymTransducer (HsPred rs1 ci) rs1 s1 ci mid ->
  SymTransducer (HsPred rs2 mid) rs2 s2 mid co ->
  (s1, RegFile rs1) ->
  (s2, RegFile rs2) ->
  ci ->
  Maybe ((s1, RegFile rs1), (s2, RegFile rs2), [co])
sequentialStep t1 t2 state1 state2 command = do
  (s1', regs1', mids) <- step t1 state1 command
  let feed (s2, regs2, outputs) mid = do
        (s2', regs2', emitted) <- step t2 (s2, regs2) mid
        pure (s2', regs2', outputs <> emitted)
  (s2', regs2', outputs) <- foldM feed (fst state2, snd state2, []) mids
  pure ((s1', regs1'), (s2', regs2'), outputs)

spec :: Spec
spec = do
  describe "bounded-exhaustive compose homomorphism" $ do
    it "agrees for counterSource then lastValueSink through three steps" $
      forM_ [replicate n Tick | n <- [0 .. 3]] checkCounterSequence

    it "agrees for pairSource then twoPhaseSink, including later rejection" $
      forM_ [[], [Go], [Go, Go]] checkPhaseSequence

    it "records the wrong-order guard as a deliberate refinement of sequential bottom" $ do
      evaluate
        ( step
            wrongOrderSink
            (initial wrongOrderSink, initialRegs wrongOrderSink)
            (M2A 5)
        )
        `shouldThrow` errorCall "evalTerm: TInpCtorField guard violation: M2B"
      let pipeline = compose m2aSource wrongOrderSink
      case step pipeline (initial pipeline, initialRegs pipeline) ProduceA of
        Just (_, _, outputs) -> outputs `shouldBe` [SawA 5]
        Nothing -> expectationFailure "expected composition to refine the guard error to a defined step"

    it "agrees for alertSource then emailDelivery, including terminal rejection" $
      forM_ [[], [sampleTrigger], [sampleTrigger, sampleTrigger]] checkAlertSequence

checkCounterSequence :: [SourceCmd] -> Expectation
checkCounterSequence =
  go
    (initial pipeline, initialRegs pipeline)
    (initial counterSource, initialRegs counterSource)
    (initial lastValueSink, initialRegs lastValueSink)
  where
    pipeline = compose counterSource lastValueSink

    go _ _ _ [] = pure ()
    go compositeState sourceState sinkState (command : rest) =
      case ( step pipeline compositeState command,
             sequentialStep counterSource lastValueSink sourceState sinkState command
           ) of
        (Nothing, Nothing) -> pure ()
        (Just (compositeVertex, compositeRegs, compositeOutputs), Just ((sourceVertex, sourceRegs), (sinkVertex, sinkRegs), sequentialOutputs)) -> do
          compositeVertex `shouldBe` Composite sourceVertex sinkVertex
          compositeOutputs `shouldBe` sequentialOutputs
          readSourceCount compositeRegs
            `shouldBe` sourceRegs ! (#srcCount :: Index CounterRegs Int)
          readSinkLast compositeRegs
            `shouldBe` sinkRegs ! (#sinkLast :: Index SinkRegs Int)
          go
            (compositeVertex, compositeRegs)
            (sourceVertex, sourceRegs)
            (sinkVertex, sinkRegs)
            rest
        _ -> expectationFailure "counter pipeline disagreed on accept/reject"

checkPhaseSequence :: [PairCmd] -> Expectation
checkPhaseSequence =
  go
    (initial pipeline, initialRegs pipeline)
    (initial pairSource, initialRegs pairSource)
    (initial twoPhaseSink, initialRegs twoPhaseSink)
  where
    pipeline = compose pairSource twoPhaseSink

    go _ _ _ [] = pure ()
    go compositeState sourceState sinkState (command : rest) =
      case ( step pipeline compositeState command,
             sequentialStep pairSource twoPhaseSink sourceState sinkState command
           ) of
        (Nothing, Nothing) -> pure ()
        (Just (compositeVertex, compositeRegs, compositeOutputs), Just ((sourceVertex, sourceRegs), (sinkVertex, sinkRegs), sequentialOutputs)) -> do
          compositeVertex `shouldBe` Composite sourceVertex sinkVertex
          compositeOutputs `shouldBe` sequentialOutputs
          readPhase compositeRegs
            `shouldBe` sinkRegs ! (#phase :: Index PhaseRegs Int)
          go
            (compositeVertex, compositeRegs)
            (sourceVertex, sourceRegs)
            (sinkVertex, sinkRegs)
            rest
        _ -> expectationFailure "two-phase pipeline disagreed on accept/reject"

checkAlertSequence :: [AlertCmd] -> Expectation
checkAlertSequence =
  go
    (initial pipeline, initialRegs pipeline)
    (initial alertSource, initialRegs alertSource)
    (initial emailDelivery, initialRegs emailDelivery)
  where
    pipeline = compose alertSource emailDelivery

    go _ _ _ [] = pure ()
    go compositeState sourceState sinkState (command : rest) =
      case ( step pipeline compositeState command,
             sequentialStep alertSource emailDelivery sourceState sinkState command
           ) of
        (Nothing, Nothing) -> pure ()
        (Just (compositeVertex, compositeRegs, compositeOutputs), Just ((sourceVertex, sourceRegs), (sinkVertex, sinkRegs), sequentialOutputs)) -> do
          compositeVertex `shouldBe` Composite sourceVertex sinkVertex
          compositeOutputs `shouldBe` sequentialOutputs
          compareAlertRegisters compositeRegs sourceRegs sinkRegs
          go
            (compositeVertex, compositeRegs)
            (sourceVertex, sourceRegs)
            (sinkVertex, sinkRegs)
            rest
        _ -> expectationFailure "alert/email pipeline disagreed on accept/reject"

compareAlertRegisters ::
  RegFile (Append AlertRegs EmailRegs) ->
  RegFile AlertRegs ->
  RegFile EmailRegs ->
  Expectation
compareAlertRegisters compositeRegs sourceRegs sinkRegs = do
  compositeRegs ! (#alertRecipient :: Index (Append AlertRegs EmailRegs) Text)
    `shouldBe` sourceRegs ! (#alertRecipient :: Index AlertRegs Text)
  compositeRegs ! (#alertSubject :: Index (Append AlertRegs EmailRegs) Text)
    `shouldBe` sourceRegs ! (#alertSubject :: Index AlertRegs Text)
  compositeRegs ! (#alertAt :: Index (Append AlertRegs EmailRegs) UTCTime)
    `shouldBe` sourceRegs ! (#alertAt :: Index AlertRegs UTCTime)
  compositeRegs ! (#emailRecipient :: Index (Append AlertRegs EmailRegs) Text)
    `shouldBe` sinkRegs ! (#emailRecipient :: Index EmailRegs Text)
  compositeRegs ! (#emailSubject :: Index (Append AlertRegs EmailRegs) Text)
    `shouldBe` sinkRegs ! (#emailSubject :: Index EmailRegs Text)
  compositeRegs ! (#emailSentAt :: Index (Append AlertRegs EmailRegs) UTCTime)
    `shouldBe` sinkRegs ! (#emailSentAt :: Index EmailRegs UTCTime)
