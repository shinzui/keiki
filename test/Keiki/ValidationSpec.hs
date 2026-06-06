module Keiki.ValidationSpec (spec) where

import Data.List (isInfixOf)
import Data.Proxy (Proxy (..))
import Keiki.Core
import Keiki.Symbolic (checkDeadEdgesSym, checkTransitionDeterminismSym)
import Test.Hspec

-- A tiny two-constructor command for guards.
data Cmd = Foo | Bar
    deriving stock (Eq, Show)

inCtorFoo :: InCtor Cmd '[]
inCtorFoo =
    InCtor
        { icName = "Foo"
        , icMatch = \case Foo -> Just RNil; _ -> Nothing
        , icBuild = \RNil -> Foo
        }

inCtorBar :: InCtor Cmd '[]
inCtorBar =
    InCtor
        { icName = "Bar"
        , icMatch = \case Bar -> Just RNil; _ -> Nothing
        , icBuild = \RNil -> Bar
        }

-- A three-state enum: Start (reachable), Mid (reachable), Orphan (unreachable).
data V = Start | Mid | Orphan
    deriving stock (Eq, Ord, Show, Enum, Bounded)

-- (a) overlapping guards out of Start (both PTop).
overlapT :: SymTransducer (HsPred '[] Cmd) '[] V Cmd ()
overlapT =
    SymTransducer
        { edgesOut = \case
            Start ->
                [ Edge{guard = PTop, update = UKeep, output = [], target = Mid}
                , Edge{guard = PTop, update = UKeep, output = [], target = Mid}
                ]
            _ -> []
        , initial = Start
        , initialRegs = RNil
        , isFinal = (== Mid)
        }

-- (b) an edge leaving the unreachable Orphan vertex.
deadT :: SymTransducer (HsPred '[] Cmd) '[] V Cmd ()
deadT =
    SymTransducer
        { edgesOut = \case
            Start -> [Edge{guard = matchInCtor inCtorFoo, update = UKeep, output = [], target = Mid}]
            Orphan -> [Edge{guard = PTop, update = UKeep, output = [], target = Start}]
            _ -> []
        , initial = Start
        , initialRegs = RNil
        , isFinal = (== Mid)
        }

-- (c) a literal-PBot guard on a reachable edge.
botT :: SymTransducer (HsPred '[] Cmd) '[] V Cmd ()
botT =
    SymTransducer
        { edgesOut = \case
            Start -> [Edge{guard = PBot, update = UKeep, output = [], target = Mid}]
            _ -> []
        , initial = Start
        , initialRegs = RNil
        , isFinal = (== Mid)
        }

-- (d) a clean transducer: mutually exclusive guards, every vertex with edges
-- is reachable, no overlapping/PBot guards. (Orphan has no outgoing edges, so
-- although it is structurally unreachable it contributes no edge to flag.)
cleanT :: SymTransducer (HsPred '[] Cmd) '[] V Cmd ()
cleanT =
    SymTransducer
        { edgesOut = \case
            Start ->
                [ Edge{guard = matchInCtor inCtorFoo, update = UKeep, output = [], target = Mid}
                , Edge{guard = matchInCtor inCtorBar, update = UKeep, output = [], target = Mid}
                ]
            _ -> []
        , initial = Start
        , initialRegs = RNil
        , isFinal = (== Mid)
        }

-- (e) sym-only overlap: one PTop and one PInCtor edge out of Start. They DO
-- overlap (PTop always holds; the Foo guard holds on Foo) but the structural
-- pure path cannot prove it (neither both-PTop nor same-ctor), so only the
-- symbolic determinism check flags it.
symOverlapT :: SymTransducer (HsPred '[] Cmd) '[] V Cmd ()
symOverlapT =
    SymTransducer
        { edgesOut = \case
            Start ->
                [ Edge{guard = matchInCtor inCtorFoo, update = UKeep, output = [], target = Mid}
                , Edge{guard = PTop, update = UKeep, output = [], target = Mid}
                ]
            _ -> []
        , initial = Start
        , initialRegs = RNil
        , isFinal = (== Mid)
        }

-- A 3-slot input constructor, mirroring CoreHiddenInputsGSMSpec, used to build
-- a hidden-input edge (its output recovers only slots a, b — never c).
data MultiInput = Begin Int Int Int
    deriving stock (Eq, Show)

data MultiOutput = OutAB Int Int
    deriving stock (Eq, Show)

inCtorBegin :: InCtor MultiInput '[ '("a", Int), '("b", Int), '("c", Int)]
inCtorBegin =
    InCtor
        { icName = "Begin"
        , icMatch = \case
            Begin a b c ->
                Just $
                    RCons (Proxy @"a") a $
                        RCons (Proxy @"b") b $
                            RCons (Proxy @"c") c $
                                RNil
        , icBuild = \(RCons _ a (RCons _ b (RCons _ c RNil))) -> Begin a b c
        }

wcAB :: WireCtor MultiOutput (Int, (Int, ()))
wcAB =
    WireCtor
        { wcName = "OutAB"
        , wcMatch = \case OutAB a b -> Just (a, (b, ()))
        , wcBuild = \(a, (b, ())) -> OutAB a b
        }

-- A two-state transducer whose only edge recovers slots {a, b} but not {c},
-- so slot c is a hidden input.
hiddenT :: SymTransducer (HsPred '[] MultiInput) '[] Bool MultiInput MultiOutput
hiddenT =
    SymTransducer
        { edgesOut = \case
            False ->
                [ Edge
                    { guard = matchInCtor inCtorBegin
                    , update = UKeep
                    , output =
                        [ pack
                            inCtorBegin
                            wcAB
                            ( OFCons
                                (TInpCtorField inCtorBegin (#a :: Index '[ '("a", Int), '("b", Int), '("c", Int)] Int))
                                (OFCons (TInpCtorField inCtorBegin (#b :: Index '[ '("a", Int), '("b", Int), '("c", Int)] Int)) OFNil)
                            )
                        ]
                    , target = True
                    }
                ]
            True -> []
        , initial = False
        , initialRegs = RNil
        , isFinal = id
        }

spec :: Spec
spec = do
    describe "validateTransducer (pure, no solver)" $ do
        it "clean transducer yields no warnings" $
            validateTransducer defaultValidationOptions cleanT `shouldBe` []

        it "overlapping pair yields a NondeterministicPair naming both indices and source" $ do
            let isOverlapStart (NondeterministicPair{tvwSource = Start, tvwEdgeA = 0, tvwEdgeB = 1}) = True
                isOverlapStart _ = False
            filter isOverlapStart (validateTransducer defaultValidationOptions overlapT)
                `shouldSatisfy` (not . null)

        it "edge from an unreachable vertex yields a PossiblyDeadEdge" $ do
            let isDeadOrphan (PossiblyDeadEdge{tvwEdge = EdgeRef{edgeSource = Orphan, edgeIndex = 0}}) = True
                isDeadOrphan _ = False
            validateTransducer defaultValidationOptions deadT
                `shouldSatisfy` any isDeadOrphan

        it "literal-PBot guard on a reachable edge yields a PossiblyDeadEdge" $ do
            let isBotDead (PossiblyDeadEdge{tvwEdge = EdgeRef{edgeSource = Start, edgeIndex = 0}, tvwDetail = d}) =
                    "unsatisfiable" `isInfixOf` d
                isBotDead _ = False
            validateTransducer defaultValidationOptions botT
                `shouldSatisfy` any isBotDead

    describe "validateTransducer hidden-input (structured)" $ do
        it "flags slot c as a hidden input with structured ctor/slot data" $ do
            let warnings = validateTransducer defaultValidationOptions hiddenT
                isHiddenC (HiddenInput{tvwEdge = EdgeRef{edgeSource = False, edgeIndex = 0}, tvwInCtor = Just "Begin", tvwMissingSlots = ms}) =
                    "c" `elem` ms
                isHiddenC _ = False
            warnings `shouldSatisfy` any isHiddenC

    describe "ValidationOptions toggles" $ do
        it "disabling determinism suppresses NondeterministicPair" $ do
            let opts = defaultValidationOptions{checkDeterminism = False}
                isND (NondeterministicPair{}) = True
                isND _ = False
            filter isND (validateTransducer opts overlapT) `shouldBe` []

    describe "checkTransitionDeterminismSym (z3-backed)" $ do
        it "mutually-exclusive PInCtor guards yield no determinism warning" $
            checkTransitionDeterminismSym cleanT `shouldBe` []

        it "catches a PTop-vs-PInCtor overlap the pure path cannot prove" $ do
            checkTransitionDeterminismPure symOverlapT `shouldBe` []
            checkTransitionDeterminismSym symOverlapT `shouldSatisfy` (not . null)

    describe "checkDeadEdgesSym (z3-backed)" $ do
        it "flags a literal-PBot guard as unsatisfiable in isolation" $ do
            let isBotEdge (DeadEdgeWarning{dewEdge = EdgeRef{edgeSource = Start, edgeIndex = 0}}) = True
                isBotEdge _ = False
            checkDeadEdgesSym botT `shouldSatisfy` any isBotEdge
