module Keiki.StepEitherSpec (spec) where

import Keiki.Core
import Test.Hspec

-- Vertices: 0 has two always-true edges (ambiguous); 1 has one
-- always-false edge (no match); 2 has no edges; 3 has one always-true
-- edge (the normal accepting case).
data V = V0 | V1 | V2 | V3 | VEnd
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
                [ Edge{guard = PTop, update = UKeep, output = [], target = VEnd}
                , Edge{guard = PTop, update = UKeep, output = [], target = V3}
                ]
            V1 -> [Edge{guard = PBot, update = UKeep, output = [], target = VEnd}]
            V2 -> []
            V3 -> [Edge{guard = PTop, update = UKeep, output = [], target = VEnd}]
            VEnd -> []
        , initial = V0
        , initialRegs = RNil
        , isFinal = (== VEnd)
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
                                { rejectedEdge = EdgeRef{edgeSource = V1, edgeIndex = 0}
                                , rejectedTarget = VEnd
                                , rejectedGuard = False
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
                                { matchedEdge = EdgeRef{edgeSource = V0, edgeIndex = 0}
                                , matchedTarget = VEnd
                                }
                            , MatchedEdgeSummary
                                { matchedEdge = EdgeRef{edgeSource = V0, edgeIndex = 1}
                                , matchedTarget = V3
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
