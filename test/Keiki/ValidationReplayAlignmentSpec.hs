module Keiki.ValidationReplayAlignmentSpec (spec) where

import Control.Monad (foldM)
import Data.Text (Text)
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Keiki.Core
import Keiki.Fixtures.EmailDelivery
import Keiki.Fixtures.RegisterEmission
import Keiki.Fixtures.SplitCoverage
import Keiki.Fixtures.UserRegistration
import Test.Hspec

runCommands ::
  (BoolAlg phi (RegFile rs, ci)) =>
  SymTransducer phi rs s ci co ->
  [ci] ->
  Maybe (s, RegFile rs, [co])
runCommands t = foldM advance (initial t, initialRegs t, [])
  where
    advance (s, regs, logSoFar) cmd = do
      (s', regs', emitted) <- step t (s, regs) cmd
      pure (s', regs', logSoFar ++ emitted)

atTime :: Integer -> UTCTime
atTime n = UTCTime (fromGregorian 2026 7 12) (secondsToDiffTime n)

spec :: Spec
spec = do
  describe "validate-clean transducers replay their own logs" $ do
    it "splitCoverageFixed replays its own log" $ do
      Just (forwardVertex, RNil, emitted) <-
        pure (runCommands splitCoverageFixed [Begin 1 2 3])
      emitted `shouldBe` [OutABC 1 2 3, OutBC 2 3]
      validateTransducer defaultValidationOptions splitCoverageFixed `shouldBe` []
      case reconstitute splitCoverageFixed emitted of
        Just (replayVertex, RNil) -> replayVertex `shouldBe` forwardVertex
        Nothing -> expectationFailure "splitCoverageFixed did not replay its own log"

    it "registerEmission replays command fields and TReg audit fields" $ do
      Just (forwardVertex, forwardRegs, emitted) <-
        pure (runCommands registerEmission registerCommands)
      emitted
        `shouldBe` [Opened "alice", Added 7 "alice", Closed "alice", Archived "alice"]
      validateTransducer defaultValidationOptions registerEmission `shouldBe` []
      case reconstitute registerEmission emitted of
        Just (replayVertex, replayRegs) -> do
          replayVertex `shouldBe` forwardVertex
          (replayRegs ! (#owner :: Index RegisterEmissionRegs Text))
            `shouldBe` (forwardRegs ! (#owner :: Index RegisterEmissionRegs Text))
          (replayRegs ! (#total :: Index RegisterEmissionRegs Int))
            `shouldBe` (forwardRegs ! (#total :: Index RegisterEmissionRegs Int))
        Nothing -> expectationFailure "registerEmission did not replay its own log"

    it "emailDelivery validates clean and replays its own log" $ do
      let cmd =
            SendEmail
              SendEmailData
                { recipient = "alice@example.com",
                  subject = "hello",
                  at = atTime 0
                }
      Just (forwardVertex, forwardRegs, emitted) <- pure (runCommands emailDelivery [cmd])
      validateTransducer defaultValidationOptions emailDelivery `shouldBe` []
      case reconstitute emailDelivery emitted of
        Just (replayVertex, replayRegs) -> do
          replayVertex `shouldBe` forwardVertex
          (replayRegs ! (#emailRecipient :: Index EmailRegs Text))
            `shouldBe` (forwardRegs ! (#emailRecipient :: Index EmailRegs Text))
          (replayRegs ! (#emailSubject :: Index EmailRegs Text))
            `shouldBe` (forwardRegs ! (#emailSubject :: Index EmailRegs Text))
          (replayRegs ! (#emailSentAt :: Index EmailRegs UTCTime))
            `shouldBe` (forwardRegs ! (#emailSentAt :: Index EmailRegs UTCTime))
        Nothing -> expectationFailure "emailDelivery did not replay its own log"

    it "userReg's persisted canonical path replays its own log" $ do
      let commands =
            [ StartRegistration (StartRegistrationData "alice@x" "Z9F4" (atTime 0)),
              ResendConfirmation (ResendConfirmationData "K2P7" (atTime 100)),
              ConfirmAccount (ConfirmAccountData "K2P7" (atTime 200)),
              FulfillGDPRRequest (FulfillGDPRRequestData (atTime 300))
            ]
      Just (forwardVertex, forwardRegs, emitted) <- pure (runCommands userReg commands)
      case reconstitute userReg emitted of
        Just (replayVertex, replayRegs) -> do
          replayVertex `shouldBe` forwardVertex
          (replayRegs ! (#email :: Index UserRegRegs Text))
            `shouldBe` (forwardRegs ! (#email :: Index UserRegRegs Text))
          (replayRegs ! (#confirmCode :: Index UserRegRegs Text))
            `shouldBe` (forwardRegs ! (#confirmCode :: Index UserRegRegs Text))
          (replayRegs ! (#registeredAt :: Index UserRegRegs UTCTime))
            `shouldBe` (forwardRegs ! (#registeredAt :: Index UserRegRegs UTCTime))
          (replayRegs ! (#confirmedAt :: Index UserRegRegs UTCTime))
            `shouldBe` (forwardRegs ! (#confirmedAt :: Index UserRegRegs UTCTime))
          (replayRegs ! (#deletedAt :: Index UserRegRegs UTCTime))
            `shouldBe` (forwardRegs ! (#deletedAt :: Index UserRegRegs UTCTime))
        Nothing -> expectationFailure "userReg did not replay its persisted path"

  describe "split-coverage counterexample" $ do
    it "produces a log that its current validator accepts but replay rejects" $ do
      Just (True, RNil, emitted) <- pure (runCommands splitCoverageBad [Begin 1 2 3])
      emitted `shouldBe` [OutAB 1 2, OutBC 2 3]
      case reconstitute splitCoverageBad emitted of
        Nothing -> pure ()
        Just _ -> expectationFailure "splitCoverageBad unexpectedly replayed its own log"

    it "validator flags the head-unrecoverable edge" $ do
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
