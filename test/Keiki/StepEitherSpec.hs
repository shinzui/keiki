module Keiki.StepEitherSpec (spec) where

import Keiki.Core
import Test.Hspec

-- Vertices: 0 has two always-true edges (ambiguous); 1 has one
-- always-false edge (no match); 2 has no edges; 3 has one always-true
-- edge (the normal accepting case).
data V = V0 | V1 | V2 | V3 | VReplay | VEnd
  deriving stock (Eq, Show)

-- A no-op output term is awkward to build generically; instead each
-- edge below uses an empty output list ([]), so a successful step emits
-- no events. That keeps the fixture free of WireCtor/InCtor plumbing
-- while still exercising the Right path.
fixture :: SymTransducer (HsPred '[] Bool) '[] V Bool String
fixture =
  SymTransducer
    { edgesOut = \case
        V0 ->
          [ Edge {guard = PTop, update = UKeep, output = [], target = VEnd, mode = Live},
            Edge {guard = PTop, update = UKeep, output = [], target = V3, mode = Live}
          ]
        V1 -> [Edge {guard = PBot, update = UKeep, output = [], target = VEnd, mode = Live}]
        V2 -> []
        V3 -> [Edge {guard = PTop, update = UKeep, output = [], target = VEnd, mode = Live}]
        VReplay -> [Edge {guard = PTop, update = UKeep, output = [], target = VEnd, mode = ReplayOnly}]
        VEnd -> [],
      initial = V0,
      initialRegs = RNil,
      isFinal = (== VEnd)
    }

data IdentityCommand = ChooseFirst | ChooseSecond
  deriving stock (Eq, Show)

data IdentityEvent = Chosen
  deriving stock (Eq, Show)

firstCtor :: InCtor IdentityCommand '[]
firstCtor =
  InCtor
    { icName = "ChooseFirst",
      icMatch = \case ChooseFirst -> Just RNil; _ -> Nothing,
      icBuild = \RNil -> ChooseFirst
    }

secondCtor :: InCtor IdentityCommand '[]
secondCtor =
  InCtor
    { icName = "ChooseSecond",
      icMatch = \case ChooseSecond -> Just RNil; _ -> Nothing,
      icBuild = \RNil -> ChooseSecond
    }

chosenWire :: WireCtor IdentityEvent ()
chosenWire =
  WireCtor
    { wcName = "Chosen",
      wcMatch = \case Chosen -> Just (),
      wcBuild = \() -> Chosen
    }

-- The two live siblings are behaviorally indistinguishable after erasure:
-- they preserve the same registers, reach the same target, and emit equal
-- values. Only their local edge references distinguish them.
identityFixture :: SymTransducer (HsPred '[] IdentityCommand) '[] V IdentityCommand IdentityEvent
identityFixture =
  SymTransducer
    { edgesOut = \case
        V0 ->
          [ Edge
              { guard = matchInCtor firstCtor,
                update = UKeep,
                output = [pack firstCtor chosenWire oNil],
                target = VEnd,
                mode = Live
              },
            Edge
              { guard = matchInCtor secondCtor,
                update = UKeep,
                output = [pack secondCtor chosenWire oNil],
                target = VEnd,
                mode = Live
              }
          ]
        _ -> [],
      initial = V0,
      initialRegs = RNil,
      isFinal = (== VEnd)
    }

-- NOTE: 'RegFile' has no 'Eq'/'Show' instance (verified 2026-06-06), so we
-- cannot 'shouldBe' a whole 'Either (StepFailure V) (V, RegFile '[], [String])'.
-- The failure ('Left') values carry no register data and ARE 'Eq'/'Show', so
-- we pattern-match the result and compare only the inspectable parts. The
-- register file for the empty slot list @'[]@ has exactly one inhabitant
-- ('RNil'), so register equality on the success path is trivially preserved.
spec :: Spec
spec = do
  describe "stepEither" $ do
    it "reports NoOutgoingEdges for a vertex with no edges" $
      case stepEither fixture (V2, RNil) True of
        Left f -> f `shouldBe` NoOutgoingEdges V2
        Right _ -> expectationFailure "expected Left NoOutgoingEdges"

    it "reports NoMatchingEdge with one rejected summary per edge" $
      case stepEither fixture (V1, RNil) True of
        Left f ->
          f
            `shouldBe` NoMatchingEdge
              V1
              [ RejectedEdgeSummary
                  { rejectedEdge = EdgeRef {edgeSource = V1, edgeIndex = 0},
                    rejectedTarget = VEnd,
                    rejectedGuard = False
                  }
              ]
        Right _ -> expectationFailure "expected Left NoMatchingEdge"

    it "reports AmbiguousEdges listing every matched edge" $
      case stepEither fixture (V0, RNil) True of
        Left f ->
          f
            `shouldBe` AmbiguousEdges
              V0
              [ MatchedEdgeSummary
                  { matchedEdge = EdgeRef {edgeSource = V0, edgeIndex = 0},
                    matchedTarget = VEnd
                  },
                MatchedEdgeSummary
                  { matchedEdge = EdgeRef {edgeSource = V0, edgeIndex = 1},
                    matchedTarget = V3
                  }
              ]
        Right _ -> expectationFailure "expected Left AmbiguousEdges"

    it "returns Right with the same target/regs/events as a normal edge" $
      case stepEither fixture (V3, RNil) True of
        Right (tgt, _regs, evs) -> (tgt, evs) `shouldBe` (VEnd, [])
        Left _ -> expectationFailure "expected Right"

    it "Right payload matches step exactly on the accepting edge" $
      case (step fixture (V3, RNil) True, stepEither fixture (V3, RNil) True) of
        (Just (s1, _r1, e1), Right (s2, _r2, e2)) -> (s1, e1) `shouldBe` (s2, e2)
        (Nothing, _) -> expectationFailure "step returned Nothing on the accepting edge"
        (_, Left f) -> expectationFailure ("stepEither returned Left: " <> show f)

  describe "stepDetailedEither" $ do
    it "distinguishes behaviorally identical guarded siblings by local EdgeRef" $
      case ( stepDetailedEither identityFixture (V0, RNil) ChooseFirst,
             stepDetailedEither identityFixture (V0, RNil) ChooseSecond,
             stepEither identityFixture (V0, RNil) ChooseFirst,
             stepEither identityFixture (V0, RNil) ChooseSecond
           ) of
        (Right first, Right second, Right (firstState, _, firstOut), Right (secondState, _, secondOut)) -> do
          stepSuccessEdge first `shouldBe` EdgeRef V0 0
          stepSuccessEdge second `shouldBe` EdgeRef V0 1
          stepSuccessMode first `shouldBe` Live
          stepSuccessMode second `shouldBe` Live
          (stepSuccessState first, stepSuccessOutputs first)
            `shouldBe` (firstState, firstOut)
          (stepSuccessState second, stepSuccessOutputs second)
            `shouldBe` (secondState, secondOut)
          (firstState, firstOut) `shouldBe` (secondState, secondOut)
        _ -> expectationFailure "expected four successful stepping results"

    it "attributes an accepted epsilon-output edge" $
      case stepDetailedEither fixture (V3, RNil) True of
        Right success -> do
          stepSuccessEdge success `shouldBe` EdgeRef V3 0
          stepSuccessMode success `shouldBe` Live
          (stepSuccessState success, stepSuccessOutputs success) `shouldBe` (VEnd, [])
        Left failure -> expectationFailure ("expected Right, got " <> show failure)

    it "never selects a replay-only edge during forward stepping" $ do
      let expected =
            NoMatchingEdge
              VReplay
              [ RejectedEdgeSummary
                  { rejectedEdge = EdgeRef VReplay 0,
                    rejectedTarget = VEnd,
                    rejectedGuard = False
                  }
              ]
      case (stepDetailedEither fixture (VReplay, RNil) True, stepEither fixture (VReplay, RNil) True) of
        (Left detailedFailure, Left compatibilityFailure) -> do
          detailedFailure `shouldBe` expected
          compatibilityFailure `shouldBe` expected
        _ -> expectationFailure "expected replay-only edge rejection"

    it "returns exactly the compatibility failures" $ do
      let cases = [(V0, True), (V1, True), (V2, True)]
      mapM_
        ( \(source, command) ->
            case ( stepDetailedEither fixture (source, RNil) command,
                   stepEither fixture (source, RNil) command
                 ) of
              (Left detailedFailure, Left compatibilityFailure) ->
                detailedFailure `shouldBe` compatibilityFailure
              _ -> expectationFailure "expected paired failures"
        )
        cases
