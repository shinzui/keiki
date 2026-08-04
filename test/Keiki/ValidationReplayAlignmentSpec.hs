{-# LANGUAGE TypeFamilies #-}

module Keiki.ValidationReplayAlignmentSpec (spec) where

import Control.Exception (evaluate)
import Control.Monad (foldM, forM_)
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import GHC.Generics (Generic)
import Keiki.Core
import Keiki.Fixtures.EmailDelivery
import Keiki.Fixtures.RegisterEmission
import Keiki.Fixtures.SplitCoverage
import Keiki.Fixtures.UserRegistration
import Keiki.Generics (FieldsOf, RegFieldsOf, mkInCtorVia, mkWireCtorVia)
import Numeric.Natural (Natural)
import Test.Hspec
import Test.QuickCheck (property)

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
      icSchema = inCtorSchemaUnavailable,
      icMatch = \case CmdX value -> Just (RCons (Proxy @"value") value RNil); _ -> Nothing,
      icBuild = \(RCons _ value RNil) -> CmdX value
    }

inCtorY :: InCtor AmbiguousCmd AmbiguousFields
inCtorY =
  InCtor
    { icName = "CmdY",
      icSchema = inCtorSchemaUnavailable,
      icMatch = \case CmdY value -> Just (RCons (Proxy @"value") value RNil); _ -> Nothing,
      icBuild = \(RCons _ value RNil) -> CmdY value
    }

wireLogged :: WireCtor AmbiguousEvent (Int, ())
wireLogged =
  WireCtor
    { wcName = "Logged",
      wcSchema = wireSchemaUnavailable,
      wcMatch = \case Logged value -> Just (value, ()); _ -> Nothing,
      wcBuild = \(value, ()) -> Logged value
    }

wireLoggedY :: WireCtor AmbiguousEvent (Int, ())
wireLoggedY =
  WireCtor
    { wcName = "LoggedY",
      wcSchema = wireSchemaUnavailable,
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

data ReplayCompletionData = ReplayCompletionData
  { completionId :: Int
  }
  deriving stock (Eq, Show, Generic)

data RegisterReplayCmd
  = CompleteNonFinal ReplayCompletionData
  | CompleteFinal ReplayCompletionData
  deriving stock (Eq, Show, Generic)

data RegisterReplayEvent = StepCompleted ReplayCompletionData
  deriving stock (Eq, Show, Generic)

commandCompletionId :: RegisterReplayCmd -> Int
commandCompletionId (CompleteNonFinal value) = value.completionId
commandCompletionId (CompleteFinal value) = value.completionId

type ReplayCompletionFields = RegFieldsOf ReplayCompletionData

type RegisterReplayRegs = '[ '("openSteps", Natural)]

inCompleteNonFinal :: InCtor RegisterReplayCmd ReplayCompletionFields
inCompleteNonFinal = mkInCtorVia @"CompleteNonFinal"

inCompleteFinal :: InCtor RegisterReplayCmd ReplayCompletionFields
inCompleteFinal = mkInCtorVia @"CompleteFinal"

wireStepCompleted :: WireCtor RegisterReplayEvent (FieldsOf ReplayCompletionData)
wireStepCompleted = mkWireCtorVia @"StepCompleted"

openSteps :: Term RegisterReplayRegs RegisterReplayCmd ifs Natural
openSteps = TReg (#openSteps :: Index RegisterReplayRegs Natural)

opaqueCommandIdentity ::
  InCtor RegisterReplayCmd ReplayCompletionFields ->
  HsPred rs RegisterReplayCmd
opaqueCommandIdentity inputCtor =
  PEq
    ( TApp1
        id
        (TInpCtorField inputCtor (#completionId :: Index ReplayCompletionFields Int))
    )
    (TInpCtorField inputCtor (#completionId :: Index ReplayCompletionFields Int))

registerReplayOutput ::
  InCtor RegisterReplayCmd ReplayCompletionFields ->
  OutTerm rs RegisterReplayCmd RegisterReplayEvent
registerReplayOutput inputCtor =
  pack
    inputCtor
    wireStepCompleted
    (TInpCtorField inputCtor (#completionId :: Index ReplayCompletionFields Int) *: oNil)

registerReplayEdge ::
  EdgeMode ->
  InCtor RegisterReplayCmd ReplayCompletionFields ->
  HsPred RegisterReplayRegs RegisterReplayCmd ->
  Edge
    (HsPred RegisterReplayRegs RegisterReplayCmd)
    RegisterReplayRegs
    RegisterReplayCmd
    RegisterReplayEvent
    Bool
registerReplayEdge edgeMode inputCtor registerCondition =
  customRegisterReplayEdge
    edgeMode
    inputCtor
    (PAnd (opaqueCommandIdentity inputCtor) registerCondition)

customRegisterReplayEdge ::
  EdgeMode ->
  InCtor RegisterReplayCmd ReplayCompletionFields ->
  HsPred RegisterReplayRegs RegisterReplayCmd ->
  Edge
    (HsPred RegisterReplayRegs RegisterReplayCmd)
    RegisterReplayRegs
    RegisterReplayCmd
    RegisterReplayEvent
    Bool
customRegisterReplayEdge edgeMode inputCtor condition =
  Edge
    { guard = PAnd (PInCtor inputCtor) condition,
      update =
        USet
          (#openSteps :: IndexN "openSteps" RegisterReplayRegs Natural)
          (TLit 0),
      output = [registerReplayOutput inputCtor],
      target = True,
      mode = edgeMode
    }

registerReplayFixture ::
  Natural ->
  EdgeMode ->
  HsPred RegisterReplayRegs RegisterReplayCmd ->
  HsPred RegisterReplayRegs RegisterReplayCmd ->
  SymTransducer
    (HsPred RegisterReplayRegs RegisterReplayCmd)
    RegisterReplayRegs
    Bool
    RegisterReplayCmd
    RegisterReplayEvent
registerReplayFixture initialOpenSteps edgeMode nonFinalCondition finalCondition =
  SymTransducer
    { edgesOut = \case
        False ->
          [ registerReplayEdge edgeMode inCompleteNonFinal nonFinalCondition,
            registerReplayEdge edgeMode inCompleteFinal finalCondition
          ]
        True -> [],
      initial = False,
      initialRegs = RCons (Proxy @"openSteps") initialOpenSteps RNil,
      isFinal = id
    }

registerDisjointFixture ::
  Natural ->
  EdgeMode ->
  SymTransducer
    (HsPred RegisterReplayRegs RegisterReplayCmd)
    RegisterReplayRegs
    Bool
    RegisterReplayCmd
    RegisterReplayEvent
registerDisjointFixture initialOpenSteps edgeMode =
  registerReplayFixture
    initialOpenSteps
    edgeMode
    (PCmp CmpGt openSteps (TLit 1))
    (PEq openSteps (TLit 1))

registerOverlappingFixture ::
  SymTransducer
    (HsPred RegisterReplayRegs RegisterReplayCmd)
    RegisterReplayRegs
    Bool
    RegisterReplayCmd
    RegisterReplayEvent
registerOverlappingFixture =
  registerReplayFixture
    2
    Live
    (PCmp CmpGt openSteps (TLit 1))
    (PCmp CmpGt openSteps (TLit 0))

opaqueOnlyFixture ::
  SymTransducer
    (HsPred RegisterReplayRegs RegisterReplayCmd)
    RegisterReplayRegs
    Bool
    RegisterReplayCmd
    RegisterReplayEvent
opaqueOnlyFixture = registerReplayFixture 2 Live PTop PTop

type RegisterReplayCondition =
  InCtor RegisterReplayCmd ReplayCompletionFields ->
  HsPred RegisterReplayRegs RegisterReplayCmd

customRegisterReplayFixture ::
  Natural ->
  EdgeMode ->
  RegisterReplayCondition ->
  RegisterReplayCondition ->
  SymTransducer
    (HsPred RegisterReplayRegs RegisterReplayCmd)
    RegisterReplayRegs
    Bool
    RegisterReplayCmd
    RegisterReplayEvent
customRegisterReplayFixture initialOpenSteps edgeMode nonFinalCondition finalCondition =
  SymTransducer
    { edgesOut = \case
        False ->
          [ customRegisterReplayEdge edgeMode inCompleteNonFinal (nonFinalCondition inCompleteNonFinal),
            customRegisterReplayEdge edgeMode inCompleteFinal (finalCondition inCompleteFinal)
          ]
        True -> [],
      initial = False,
      initialRegs = registerReplayRegs initialOpenSteps,
      isFinal = id
    }

registerReplayRegs :: Natural -> RegFile RegisterReplayRegs
registerReplayRegs value = RCons (Proxy @"openSteps") value RNil

data OpenStepsIdentity

instance FieldProjection OpenStepsIdentity where
  type FieldName OpenStepsIdentity = "value"
  type FieldOwner OpenStepsIdentity = Natural
  type FieldResult OpenStepsIdentity = Natural
  fieldShapeId _ = "natural/identity"
  projectFieldValue _ = id

openStepsProjection :: Term RegisterReplayRegs RegisterReplayCmd ifs Natural
openStepsProjection =
  regProj
    (fieldWitness @OpenStepsIdentity)
    (#openSteps :: Index RegisterReplayRegs Natural)

unsupportedRegisterConditions :: [(String, String, RegisterReplayCondition)]
unsupportedRegisterConditions =
  [ ( "disjunction",
      "POr",
      const
        ( POr
            (PCmp CmpGt openSteps (TLit 1))
            (PEq openSteps (TLit 1))
        )
    ),
    ( "negation",
      "PNot",
      const (PNot (PCmp CmpGt openSteps (TLit 1)))
    ),
    ( "arithmetic",
      "TArith",
      const
        ( PCmp
            CmpGt
            (TArith OpAdd openSteps (TLit 1))
            (TLit 0)
        )
    ),
    ( "projection",
      "TFieldProj",
      const (PCmp CmpGt openStepsProjection (TLit 0))
    ),
    ( "input field",
      "TInpCtorField",
      \inputCtor ->
        PEq
          (TInpCtorField inputCtor (#completionId :: Index ReplayCompletionFields Int))
          (TLit 7)
    ),
    ( "opaque application",
      "TApp1",
      const (PEq (TApp1 id openSteps) openSteps)
    )
  ]

type UnsupportedCarrierRegs = '[ '("enabled", Bool)]

unsupportedCarrierFixture ::
  SymTransducer
    (HsPred UnsupportedCarrierRegs RegisterReplayCmd)
    UnsupportedCarrierRegs
    Bool
    RegisterReplayCmd
    RegisterReplayEvent
unsupportedCarrierFixture =
  SymTransducer
    { edgesOut = \case
        False ->
          [ unsupportedEdge inCompleteNonFinal True,
            unsupportedEdge inCompleteFinal False
          ]
        True -> [],
      initial = False,
      initialRegs = RCons (Proxy @"enabled") True RNil,
      isFinal = id
    }
  where
    unsupportedEdge inputCtor expected =
      Edge
        { guard =
            PAnd
              (PInCtor inputCtor)
              ( PEq
                  (TReg (#enabled :: Index UnsupportedCarrierRegs Bool))
                  (TLit expected)
              ),
          update = UKeep,
          output = [registerReplayOutput inputCtor],
          target = True,
          mode = Live
        }

type DuplicateLabelRegs =
  '[ '("openSteps", Natural),
     '("openSteps", Natural)
   ]

firstDuplicateOpenSteps :: Term DuplicateLabelRegs RegisterReplayCmd ifs Natural
firstDuplicateOpenSteps = TReg ZIdx

secondDuplicateOpenSteps :: Term DuplicateLabelRegs RegisterReplayCmd ifs Natural
secondDuplicateOpenSteps = TReg (SIdx ZIdx)

duplicateLabelFixture ::
  SymTransducer
    (HsPred DuplicateLabelRegs RegisterReplayCmd)
    DuplicateLabelRegs
    Bool
    RegisterReplayCmd
    RegisterReplayEvent
duplicateLabelFixture =
  SymTransducer
    { edgesOut = \case
        False ->
          [ duplicateEdge
              inCompleteNonFinal
              (PCmp CmpGt firstDuplicateOpenSteps (TLit 1)),
            duplicateEdge
              inCompleteFinal
              (PEq secondDuplicateOpenSteps (TLit 1))
          ]
        True -> [],
      initial = False,
      initialRegs =
        RCons
          (Proxy @"openSteps")
          2
          (RCons (Proxy @"openSteps") 1 RNil),
      isFinal = id
    }
  where
    duplicateEdge inputCtor registerCondition =
      Edge
        { guard = PAnd (PInCtor inputCtor) registerCondition,
          update = UKeep,
          output =
            [ pack
                inputCtor
                wireStepCompleted
                ( TInpCtorField
                    inputCtor
                    (#completionId :: Index ReplayCompletionFields Int)
                    *: oNil
                )
            ],
          target = True,
          mode = Live
        }

concreteReplayCandidateCount ::
  (Eq co) =>
  EdgeMode ->
  SymTransducer (HsPred rs ci) rs s ci co ->
  s ->
  RegFile rs ->
  co ->
  Int
concreteReplayCandidateCount candidateMode transducer source registers observed =
  length
    [ ()
    | edge <- edgesOut transducer source,
      mode edge == candidateMode,
      headOutput : _ <- [output edge],
      Just command <- [solveOutput headOutput registers observed],
      models (guard edge) (registers, command)
    ]

data LowerBoundary = LowerStrict | LowerInclusive | LowerEquality

data UpperBoundary = UpperStrict | UpperInclusive | UpperEquality

lowerBoundaryFrom :: Int -> LowerBoundary
lowerBoundaryFrom raw = case abs (toInteger raw) `mod` 3 of
  0 -> LowerStrict
  1 -> LowerInclusive
  _ -> LowerEquality

upperBoundaryFrom :: Int -> UpperBoundary
upperBoundaryFrom raw = case abs (toInteger raw) `mod` 3 of
  0 -> UpperStrict
  1 -> UpperInclusive
  _ -> UpperEquality

boundedNatural :: Int -> Natural
boundedNatural raw = fromInteger (abs (toInteger raw) `mod` 11)

lowerBoundaryPredicate :: LowerBoundary -> Natural -> HsPred RegisterReplayRegs RegisterReplayCmd
lowerBoundaryPredicate LowerStrict value = PCmp CmpGt openSteps (TLit value)
lowerBoundaryPredicate LowerInclusive value = PCmp CmpGe openSteps (TLit value)
lowerBoundaryPredicate LowerEquality value = PEq openSteps (TLit value)

upperBoundaryPredicate :: UpperBoundary -> Natural -> HsPred RegisterReplayRegs RegisterReplayCmd
upperBoundaryPredicate UpperStrict value = PCmp CmpLt openSteps (TLit value)
upperBoundaryPredicate UpperInclusive value = PCmp CmpLe openSteps (TLit value)
upperBoundaryPredicate UpperEquality value = PEq openSteps (TLit value)

intervalAgreementProperty :: Int -> Int -> Int -> Int -> Bool
intervalAgreementProperty rawLower rawUpper rawLowerKind rawUpperKind =
  warningSuppressed == not concreteOverlapExists
  where
    lower = boundedNatural rawLower
    upper = boundedNatural rawUpper
    leftPredicate = lowerBoundaryPredicate (lowerBoundaryFrom rawLowerKind) lower
    rightPredicate = upperBoundaryPredicate (upperBoundaryFrom rawUpperKind) upper
    transducer =
      customRegisterReplayFixture
        0
        Live
        (const leftPredicate)
        (const rightPredicate)
    warningSuppressed = null (inversionAmbiguityWarnings transducer)
    concreteOverlapExists =
      any
        ( \registerValue ->
            concreteReplayCandidateCount
              Live
              transducer
              False
              (registerReplayRegs registerValue)
              (StepCompleted (ReplayCompletionData 7))
              == 2
        )
        [0 .. 12]

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

  describe "shared-register replay candidate disjointness" $ do
    it "suppresses the false positive for openSteps > 1 versus openSteps == 1" $
      inversionAmbiguityWarnings (registerDisjointFixture 2 Live)
        `shouldBe` []

    it "preserves forward/replay agreement for both non-final and final register paths" $ do
      let cases =
            [ (2, CompleteNonFinal (ReplayCompletionData 7)),
              (1, CompleteFinal (ReplayCompletionData 9))
            ]
      mapM_
        ( \(initialOpenSteps, command) -> do
            let transducer = registerDisjointFixture initialOpenSteps Live
            case runCommands transducer [command] of
              Just (forwardVertex, forwardRegs, emitted) -> do
                emitted
                  `shouldBe` [StepCompleted (ReplayCompletionData (commandCompletionId command))]
                case reconstitute transducer emitted of
                  Just (replayVertex, replayRegs) -> do
                    replayVertex `shouldBe` forwardVertex
                    replayRegs ! (#openSteps :: Index RegisterReplayRegs Natural)
                      `shouldBe` (forwardRegs ! (#openSteps :: Index RegisterReplayRegs Natural))
                  Nothing -> expectationFailure "register-disjoint fixture did not replay"
              Nothing -> expectationFailure "register-disjoint fixture did not step"
        )
        cases

    it "bounds every concrete candidate count for the suppressed pair across registers, events, and modes" $ do
      forM_ [Live, ReplayOnly] $ \candidateMode ->
        forM_ [0 .. 5] $ \registerValue -> do
          let transducer = registerDisjointFixture registerValue candidateMode
              registers = registerReplayRegs registerValue
          inversionAmbiguityWarnings transducer `shouldBe` []
          forM_ [-2 .. 2] $ \observedId ->
            concreteReplayCandidateCount
              candidateMode
              transducer
              False
              registers
              (StepCompleted (ReplayCompletionData observedId))
              `shouldSatisfy` (<= 1)

    it "agrees with concrete candidates for generated strict, inclusive, and equality boundaries" $
      property intervalAgreementProperty

    it "retains the overlapping warning with its opaque precision blocker and exhibits two concrete candidates" $ do
      case inversionAmbiguityWarnings registerOverlappingFixture of
        [InversionAmbiguity {tvwDetail = detail}] -> detail `shouldContain` "TApp1"
        other -> expectationFailure ("expected one overlap warning, got " <> show other)
      case reconstituteEither
        registerOverlappingFixture
        [StepCompleted (ReplayCompletionData 7)] of
        Left failure ->
          case replayFailureReason failure of
            ReplayEventFailed (ReplayAmbiguousInversions False matchedEdges) ->
              map (edgeIndex . matchedEdge) matchedEdges `shouldBe` [0, 1]
            other ->
              expectationFailure ("expected ReplayAmbiguousInversions, got " <> show other)
        Right result ->
          expectationFailure ("expected ambiguous replay, got " <> show (fst result))
      concreteReplayCandidateCount
        Live
        registerOverlappingFixture
        False
        (registerReplayRegs 2)
        (StepCompleted (ReplayCompletionData 7))
        `shouldBe` 2

    it "names the opaque conjunct when only command-dependent conditions remain" $
      case inversionAmbiguityWarnings opaqueOnlyFixture of
        [InversionAmbiguity {tvwDetail = detail}] -> detail `shouldContain` "TApp1"
        other -> expectationFailure ("expected one opaque-only warning, got " <> show other)

    it "names an unsupported register carrier and fails conservatively" $
      case inversionAmbiguityWarnings unsupportedCarrierFixture of
        [InversionAmbiguity {tvwDetail = detail}] -> do
          detail `shouldContain` "unsupported register carrier"
          detail `shouldContain` "Bool"
        other -> expectationFailure ("expected one unsupported-carrier warning, got " <> show other)

    it "retains every unsupported guard shape unless a supported sibling proves disjointness" $ do
      forM_ unsupportedRegisterConditions $ \(label, expectedBlocker, condition) -> do
        let blockedFixture = customRegisterReplayFixture 2 Live condition condition
        case inversionAmbiguityWarnings blockedFixture of
          [InversionAmbiguity {tvwDetail = detail}] ->
            detail `shouldContain` expectedBlocker
          other ->
            expectationFailure
              ("expected one " <> label <> " warning, got " <> show other)

        let contradictedFixture =
              customRegisterReplayFixture
                2
                Live
                ( \inputCtor ->
                    PAnd
                      (condition inputCtor)
                      (PCmp CmpGt openSteps (TLit 1))
                )
                ( \inputCtor ->
                    PAnd
                      (condition inputCtor)
                      (PEq openSteps (TLit 1))
                )
        inversionAmbiguityWarnings contradictedFixture `shouldBe` []

    it "does not merge distinct duplicate-labelled register positions" $ do
      case inversionAmbiguityWarnings duplicateLabelFixture of
        [InversionAmbiguity {tvwDetail = detail}] -> do
          detail `shouldContain` "distinct positions [0,1]"
          detail `shouldContain` "duplicate label \"openSteps\""
        other -> expectationFailure ("expected one duplicate-label warning, got " <> show other)
      case reconstituteEither
        duplicateLabelFixture
        [StepCompleted (ReplayCompletionData 7)] of
        Left failure ->
          case replayFailureReason failure of
            ReplayEventFailed (ReplayAmbiguousInversions False matchedEdges) ->
              map (edgeIndex . matchedEdge) matchedEdges `shouldBe` [0, 1]
            other ->
              expectationFailure ("expected duplicate-label ambiguity, got " <> show other)
        Right result ->
          expectationFailure ("expected duplicate-label ambiguity, got " <> show (fst result))

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
