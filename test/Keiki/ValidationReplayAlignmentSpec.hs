module Keiki.ValidationReplayAlignmentSpec (spec) where

import Control.Exception (evaluate)
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
                target = True,
                mode = Live
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
                target = True,
                mode = Live
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

type ReadRegs = '[ '("seen", Int)]

readGuardTransducer :: HsPred ReadRegs AmbiguousCmd -> SymTransducer (HsPred ReadRegs AmbiguousCmd) ReadRegs Bool AmbiguousCmd ()
readGuardTransducer edgeGuard =
  SymTransducer
    { edgesOut = \case
        False ->
          [ Edge
              { guard = edgeGuard,
                update =
                  USet
                    (#seen :: IndexN "seen" ReadRegs Int)
                    (TInpCtorField inCtorX (#value :: Index AmbiguousFields Int)),
                output = [],
                target = True,
                mode = Live
              }
          ]
        True -> [],
      initial = False,
      initialRegs = RCons (Proxy @"seen") 0 RNil,
      isFinal = id
    }

unguardedReadTransducer :: SymTransducer (HsPred ReadRegs AmbiguousCmd) ReadRegs Bool AmbiguousCmd ()
unguardedReadTransducer = readGuardTransducer PTop

safeReadTransducer :: SymTransducer (HsPred ReadRegs AmbiguousCmd) ReadRegs Bool AmbiguousCmd ()
safeReadTransducer = readGuardTransducer (PAnd (matchInCtor inCtorX) PTop)

wrongOrderReadTransducer :: SymTransducer (HsPred ReadRegs AmbiguousCmd) ReadRegs Bool AmbiguousCmd ()
wrongOrderReadTransducer =
  readGuardTransducer
    ( PAnd
        (PEq (TInpCtorField inCtorX (#value :: Index AmbiguousFields Int)) (TLit 7))
        (matchInCtor inCtorX)
    )

rightOrderReadTransducer :: SymTransducer (HsPred ReadRegs AmbiguousCmd) ReadRegs Bool AmbiguousCmd ()
rightOrderReadTransducer =
  readGuardTransducer
    ( PAnd
        (matchInCtor inCtorX)
        (PEq (TInpCtorField inCtorX (#value :: Index AmbiguousFields Int)) (TLit 7))
    )

data EpsilonVertex = EpsilonStart | EpsilonEnd
  deriving stock (Eq, Ord, Show, Enum, Bounded)

data EpsilonCase
  = ChangesVertexOnly
  | WritesRegistersOnly
  | ChangesBoth
  | NoOpSelfLoop

epsilonTransducer :: EpsilonCase -> SymTransducer (HsPred ReadRegs AmbiguousCmd) ReadRegs EpsilonVertex AmbiguousCmd ()
epsilonTransducer epsilonCase =
  SymTransducer
    { edgesOut = \case
        EpsilonStart ->
          case epsilonCase of
            ChangesVertexOnly ->
              [Edge (matchInCtor inCtorX) UKeep [] EpsilonEnd Live]
            WritesRegistersOnly ->
              [Edge (matchInCtor inCtorX) setSeen [] EpsilonStart Live]
            ChangesBoth ->
              [Edge (matchInCtor inCtorX) setSeen [] EpsilonEnd Live]
            NoOpSelfLoop ->
              [Edge (matchInCtor inCtorX) UKeep [] EpsilonStart Live]
        EpsilonEnd -> [],
      initial = EpsilonStart,
      initialRegs = RCons (Proxy @"seen") 0 RNil,
      isFinal = (== EpsilonEnd)
    }
  where
    setSeen =
      USet
        (#seen :: IndexN "seen" ReadRegs Int)
        (TInpCtorField inCtorX (#value :: Index AmbiguousFields Int))

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
      validateTransducer defaultValidationOptions userReg `shouldBe` []
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

  describe "guard implies input reads" $ do
    let isUnguarded
          ( UnguardedInputRead
              { tvwEdge = EdgeRef {edgeSource = False, edgeIndex = 0},
                tvwInCtor = Just "CmdX"
              }
            ) = True
        isUnguarded _ = False

    it "flags a PTop-guarded update read" $
      guardImpliesInputReadWarnings unguardedReadTransducer
        `shouldSatisfy` any isUnguarded

    it "accepts a read protected by an earlier constructor guard" $ do
      guardImpliesInputReadWarnings safeReadTransducer `shouldBe` []
      case step safeReadTransducer (False, initialRegs safeReadTransducer) (CmdY 3) of
        Nothing -> pure ()
        Just _ -> expectationFailure "safe constructor guard accepted CmdY"

    it "flags a guard read that appears before its constructor guard" $
      guardImpliesInputReadWarnings wrongOrderReadTransducer
        `shouldSatisfy` any isUnguarded

    it "accepts a guard read after its constructor guard" $
      guardImpliesInputReadWarnings rightOrderReadTransducer `shouldBe` []

    it "predicts the runtime TInpCtorField crash" $
      evaluate
        ( case step unguardedReadTransducer (False, initialRegs unguardedReadTransducer) (CmdY 3) of
            Just (_, regs, _) -> regs ! (#seen :: Index ReadRegs Int)
            Nothing -> 0
        )
        `shouldThrow` errorCall "evalTerm: TInpCtorField guard violation: CmdX"

  describe "state-changing epsilon" $ do
    let warningShape transducer =
          [ (tvwChangesVertex, tvwWritesRegisters)
          | StateChangingEpsilon
              { tvwEdge = EdgeRef {edgeSource = EpsilonStart, edgeIndex = 0},
                tvwChangesVertex,
                tvwWritesRegisters
              } <-
              stateChangingEpsilonWarnings transducer
          ]

    it "reports vertex-only, register-only, and combined changes exactly" $ do
      warningShape (epsilonTransducer ChangesVertexOnly) `shouldBe` [(True, False)]
      warningShape (epsilonTransducer WritesRegistersOnly) `shouldBe` [(False, True)]
      warningShape (epsilonTransducer ChangesBoth) `shouldBe` [(True, True)]

    it "keeps a UKeep self-loop clean" $
      validateTransducer defaultValidationOptions (epsilonTransducer NoOpSelfLoop)
        `shouldBe` []

    it "allows only this check to be disabled explicitly" $
      validateTransducer
        defaultValidationOptions {checkStateChangingEpsilon = False}
        (epsilonTransducer ChangesVertexOnly)
        `shouldBe` []

    it "predicts empty-log replay divergence" $ do
      let transducer = epsilonTransducer ChangesVertexOnly
      Just (EpsilonEnd, _, emitted) <- pure (runCommands transducer [CmdX 7])
      emitted `shouldBe` []
      case reconstitute transducer emitted of
        Just (EpsilonStart, _) -> pure ()
        _ -> expectationFailure "empty log unexpectedly reproduced the forward vertex"

    it "does not let the hidden-input and state-change checks mask each other" $ do
      let warnings = validateTransducer defaultValidationOptions (epsilonTransducer ChangesBoth)
      warnings `shouldSatisfy` any (\case HiddenInput {} -> True; _ -> False)
      warnings `shouldSatisfy` any (\case StateChangingEpsilon {} -> True; _ -> False)
