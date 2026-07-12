module Keiki.ValidationReplayAlignmentSpec (spec) where

import Control.Monad (foldM)
import Data.Proxy (Proxy (..))
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

data AmbiguousCmd = CmdX Int | CmdY Int
  deriving stock (Eq, Show)

data AmbiguousEvent = Logged Int | LoggedY Int
  deriving stock (Eq, Show)

type AmbiguousFields = '[ '("value", Int)]

inCtorX :: InCtor AmbiguousCmd AmbiguousFields
inCtorX =
  InCtor
    { icName = "CmdX",
      icMatch = \case CmdX value -> Just (RCons (Proxy @"value") value RNil); _ -> Nothing,
      icBuild = \(RCons _ value RNil) -> CmdX value
    }

inCtorY :: InCtor AmbiguousCmd AmbiguousFields
inCtorY =
  InCtor
    { icName = "CmdY",
      icMatch = \case CmdY value -> Just (RCons (Proxy @"value") value RNil); _ -> Nothing,
      icBuild = \(RCons _ value RNil) -> CmdY value
    }

wireLogged :: WireCtor AmbiguousEvent (Int, ())
wireLogged =
  WireCtor
    { wcName = "Logged",
      wcMatch = \case Logged value -> Just (value, ()); _ -> Nothing,
      wcBuild = \(value, ()) -> Logged value
    }

wireLoggedY :: WireCtor AmbiguousEvent (Int, ())
wireLoggedY =
  WireCtor
    { wcName = "LoggedY",
      wcMatch = \case LoggedY value -> Just (value, ()); _ -> Nothing,
      wcBuild = \(value, ()) -> LoggedY value
    }

ambiguousTransducerWith ::
  WireCtor AmbiguousEvent (Int, ()) ->
  SymTransducer (HsPred '[] AmbiguousCmd) '[] Bool AmbiguousCmd AmbiguousEvent
ambiguousTransducerWith secondWire =
  SymTransducer
    { edgesOut = \case
        False ->
          [ Edge
              { guard = matchInCtor inCtorX,
                update = UKeep,
                output =
                  [ pack
                      inCtorX
                      wireLogged
                      (TInpCtorField inCtorX (#value :: Index AmbiguousFields Int) *: oNil)
                  ],
                target = True
              },
            Edge
              { guard = matchInCtor inCtorY,
                update = UKeep,
                output =
                  [ pack
                      inCtorY
                      secondWire
                      (TInpCtorField inCtorY (#value :: Index AmbiguousFields Int) *: oNil)
                  ],
                target = True
              }
          ]
        True -> [],
      initial = False,
      initialRegs = RNil,
      isFinal = id
    }

ambiguousTransducer :: SymTransducer (HsPred '[] AmbiguousCmd) '[] Bool AmbiguousCmd AmbiguousEvent
ambiguousTransducer = ambiguousTransducerWith wireLogged

distinctHeadTransducer :: SymTransducer (HsPred '[] AmbiguousCmd) '[] Bool AmbiguousCmd AmbiguousEvent
distinctHeadTransducer = ambiguousTransducerWith wireLoggedY

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

  describe "cross-edge inversion ambiguity" $ do
    it "predicts the replay failure for two equal head wire constructors" $ do
      Just (True, RNil, emitted) <- pure (runCommands ambiguousTransducer [CmdX 7])
      emitted `shouldBe` [Logged 7]
      case reconstitute ambiguousTransducer emitted of
        Nothing -> pure ()
        Just _ -> expectationFailure "same-head transducer unexpectedly replayed"
      let warnings = validateTransducer defaultValidationOptions ambiguousTransducer
          isAmbiguous
            ( InversionAmbiguity
                { tvwSource = False,
                  tvwEdgeA = 0,
                  tvwEdgeB = 1,
                  tvwWireCtor = "Logged"
                }
              ) = True
          isAmbiguous _ = False
      warnings `shouldSatisfy` any isAmbiguous

    it "distinct head wire constructors validate and replay" $ do
      Just (True, RNil, emitted) <- pure (runCommands distinctHeadTransducer [CmdY 9])
      emitted `shouldBe` [LoggedY 9]
      validateTransducer defaultValidationOptions distinctHeadTransducer `shouldBe` []
      case reconstitute distinctHeadTransducer emitted of
        Just (True, RNil) -> pure ()
        _ -> expectationFailure "distinct-head transducer did not replay"
