module Keiki.ValidationSpec (spec) where

import Data.List (isInfixOf)
import Data.Proxy (Proxy (..))
import Data.Word (Word8)
import Keiki.Core
import Keiki.Symbolic (checkDeadEdgesSym, checkTransitionDeterminismSym)
import Test.Hspec

-- A tiny two-constructor command for guards.
data Cmd = Foo | Bar
  deriving stock (Eq, Show)

inCtorFoo :: InCtor Cmd '[]
inCtorFoo =
  InCtor
    { icName = "Foo",
      icMatch = \case Foo -> Just RNil; _ -> Nothing,
      icBuild = \RNil -> Foo
    }

inCtorBar :: InCtor Cmd '[]
inCtorBar =
  InCtor
    { icName = "Bar",
      icMatch = \case Bar -> Just RNil; _ -> Nothing,
      icBuild = \RNil -> Bar
    }

data VEvent = Fooed | Bared
  deriving stock (Eq, Show)

wireFooed :: WireCtor VEvent ()
wireFooed =
  WireCtor
    { wcName = "Fooed",
      wcMatch = \case Fooed -> Just (); _ -> Nothing,
      wcBuild = \() -> Fooed
    }

wireBared :: WireCtor VEvent ()
wireBared =
  WireCtor
    { wcName = "Bared",
      wcMatch = \case Bared -> Just (); _ -> Nothing,
      wcBuild = \() -> Bared
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
          [ Edge {guard = PTop, update = UKeep, output = [], target = Mid, mode = Live},
            Edge {guard = PTop, update = UKeep, output = [], target = Mid, mode = Live}
          ]
        _ -> [],
      initial = Start,
      initialRegs = RNil,
      isFinal = (== Mid)
    }

-- (b) an edge leaving the unreachable Orphan vertex.
deadT :: SymTransducer (HsPred '[] Cmd) '[] V Cmd ()
deadT =
  SymTransducer
    { edgesOut = \case
        Start -> [Edge {guard = matchInCtor inCtorFoo, update = UKeep, output = [], target = Mid, mode = Live}]
        Orphan -> [Edge {guard = PTop, update = UKeep, output = [], target = Start, mode = Live}]
        _ -> [],
      initial = Start,
      initialRegs = RNil,
      isFinal = (== Mid)
    }

-- (c) a literal-PBot guard on a reachable edge.
botT :: SymTransducer (HsPred '[] Cmd) '[] V Cmd ()
botT =
  SymTransducer
    { edgesOut = \case
        Start -> [Edge {guard = PBot, update = UKeep, output = [], target = Mid, mode = Live}]
        _ -> [],
      initial = Start,
      initialRegs = RNil,
      isFinal = (== Mid)
    }

-- (d) a clean transducer: mutually exclusive guards, every vertex with edges
-- is reachable, no overlapping/PBot guards. (Orphan has no outgoing edges, so
-- although it is structurally unreachable it contributes no edge to flag.)
cleanT :: SymTransducer (HsPred '[] Cmd) '[] V Cmd VEvent
cleanT =
  SymTransducer
    { edgesOut = \case
        Start ->
          [ Edge {guard = matchInCtor inCtorFoo, update = UKeep, output = [pack inCtorFoo wireFooed oNil], target = Mid, mode = Live},
            Edge {guard = matchInCtor inCtorBar, update = UKeep, output = [pack inCtorBar wireBared oNil], target = Mid, mode = Live}
          ]
        _ -> [],
      initial = Start,
      initialRegs = RNil,
      isFinal = (== Mid)
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
          [ Edge {guard = matchInCtor inCtorFoo, update = UKeep, output = [], target = Mid, mode = Live},
            Edge {guard = PTop, update = UKeep, output = [], target = Mid, mode = Live}
          ]
        _ -> [],
      initial = Start,
      initialRegs = RNil,
      isFinal = (== Mid)
    }

-- (f) an opaque collection-style guard (EP-67): the guard lifts list membership
-- through a TApp closure the symbolic analyses cannot see through. The register
-- slot holds a collection; the guard asks "is 5 in items?" via `elem`, which has
-- no structural keiki node, so it is forced through TApp1.
type ItemRegs = '[ '("items", [Int])]

opaqueT :: SymTransducer (HsPred ItemRegs Cmd) ItemRegs V Cmd VEvent
opaqueT =
  SymTransducer
    { edgesOut = \case
        Start ->
          [ Edge
              { guard =
                  PEq
                    (TApp1 (5 `elem`) (TReg (ZIdx :: Index ItemRegs [Int])))
                    (TLit True),
                update = UKeep,
                output = [pack inCtorFoo wireFooed oNil],
                target = Mid,
                mode = Live
              }
          ]
        _ -> [],
      initial = Start,
      initialRegs = RCons (Proxy @"items") [] RNil,
      isFinal = (== Mid)
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
    { icName = "Begin",
      icMatch = \case
        Begin a b c ->
          Just $
            RCons (Proxy @"a") a $
              RCons (Proxy @"b") b $
                RCons (Proxy @"c") c $
                  RNil,
      icBuild = \(RCons _ a (RCons _ b (RCons _ c RNil))) -> Begin a b c
    }

wcAB :: WireCtor MultiOutput (Int, (Int, ()))
wcAB =
  WireCtor
    { wcName = "OutAB",
      wcMatch = \case OutAB a b -> Just (a, (b, ())),
      wcBuild = \(a, (b, ())) -> OutAB a b
    }

-- A two-state transducer whose only edge recovers slots {a, b} but not {c},
-- so slot c is a hidden input.
hiddenT :: SymTransducer (HsPred '[] MultiInput) '[] Bool MultiInput MultiOutput
hiddenT =
  SymTransducer
    { edgesOut = \case
        False ->
          [ Edge
              { guard = matchInCtor inCtorBegin,
                update = UKeep,
                output =
                  [ pack
                      inCtorBegin
                      wcAB
                      ( OFCons
                          (TInpCtorField inCtorBegin (#a :: Index '[ '("a", Int), '("b", Int), '("c", Int)] Int))
                          (OFCons (TInpCtorField inCtorBegin (#b :: Index '[ '("a", Int), '("b", Int), '("c", Int)] Int)) OFNil)
                      )
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

-- Pure-overlap fixtures (EP-76). Every edge is a state-preserving self-loop so
-- the default validation result isolates determinism from epsilon-state-change
-- diagnostics.
type OverlapRegs = '[ '("x", Int)]

xIdx :: Index OverlapRegs Int
xIdx = ZIdx

overlapFixture ::
  HsPred OverlapRegs Cmd ->
  HsPred OverlapRegs Cmd ->
  SymTransducer (HsPred OverlapRegs Cmd) OverlapRegs V Cmd ()
overlapFixture leftGuard rightGuard =
  SymTransducer
    { edgesOut = \case
        Start ->
          [ Edge leftGuard UKeep [] Start Live,
            Edge rightGuard UKeep [] Start Live
          ]
        _ -> [],
      initial = Start,
      initialRegs = RCons (Proxy @"x") 0 RNil,
      isFinal = const False
    }

fooWith :: HsPred OverlapRegs Cmd -> HsPred OverlapRegs Cmd
fooWith = PAnd (PInCtor inCtorFoo)

barWith :: HsPred OverlapRegs Cmd -> HsPred OverlapRegs Cmd
barWith = PAnd (PInCtor inCtorBar)

motivatingOverlapT ::
  SymTransducer (HsPred OverlapRegs Cmd) OverlapRegs V Cmd ()
motivatingOverlapT =
  overlapFixture
    (fooWith (PCmp CmpGt (proj xIdx) (TLit 0)))
    (fooWith (PCmp CmpGt (proj xIdx) (TLit 5)))

disjointOverlapT ::
  SymTransducer (HsPred OverlapRegs Cmd) OverlapRegs V Cmd ()
disjointOverlapT =
  overlapFixture
    (fooWith (PCmp CmpGt (proj xIdx) (TLit 5)))
    (fooWith (PCmp CmpLt (proj xIdx) (TLit 3)))

unknownOrT ::
  SymTransducer (HsPred OverlapRegs Cmd) OverlapRegs V Cmd ()
unknownOrT =
  overlapFixture
    ( fooWith
        ( POr
            (PCmp CmpGt (proj xIdx) (TLit 0))
            (PCmp CmpLt (proj xIdx) (TLit 0))
        )
    )
    (fooWith (PCmp CmpGt (proj xIdx) (TLit 5)))

unknownOpaqueT ::
  SymTransducer (HsPred OverlapRegs Cmd) OverlapRegs V Cmd ()
unknownOpaqueT =
  overlapFixture
    ( fooWith
        (PCmp CmpGt (TApp1 id (proj xIdx)) (TLit 0))
    )
    (fooWith (PCmp CmpGt (proj xIdx) (TLit 5)))

differentCtorT ::
  SymTransducer (HsPred OverlapRegs Cmd) OverlapRegs V Cmd ()
differentCtorT =
  overlapFixture
    (fooWith (PCmp CmpGt (proj xIdx) (TLit 0)))
    (barWith (PCmp CmpGt (proj xIdx) (TLit 5)))

type ByteOverlapRegs = '[ '("x", Word8)]

byteOverlapIdx :: Index ByteOverlapRegs Word8
byteOverlapIdx = ZIdx

disjointWord8T ::
  SymTransducer (HsPred ByteOverlapRegs Cmd) ByteOverlapRegs V Cmd ()
disjointWord8T =
  SymTransducer
    { edgesOut = \case
        Start ->
          [ Edge
              ( PAnd
                  (PInCtor inCtorFoo)
                  (PCmp CmpGe (proj byteOverlapIdx) (TLit 200))
              )
              UKeep
              []
              Start
              Live,
            Edge
              ( PAnd
                  (PInCtor inCtorFoo)
                  (PCmp CmpLe (proj byteOverlapIdx) (TLit 100))
              )
              UKeep
              []
              Start
              Live
          ]
        _ -> [],
      initial = Start,
      initialRegs = RCons (Proxy @"x") 0 RNil,
      isFinal = const False
    }

type BoolOverlapRegs = '[ '("x", Bool)]

boolOverlapIdx :: Index BoolOverlapRegs Bool
boolOverlapIdx = ZIdx

boolLiteralWitnessT ::
  SymTransducer (HsPred BoolOverlapRegs Cmd) BoolOverlapRegs V Cmd ()
boolLiteralWitnessT =
  SymTransducer
    { edgesOut = \case
        Start ->
          [ Edge
              (PAnd (PInCtor inCtorFoo) (PEq (proj boolOverlapIdx) (TLit True)))
              UKeep
              []
              Start
              Live,
            Edge
              (PAnd (PInCtor inCtorFoo) (PEq (TLit True) (proj boolOverlapIdx)))
              UKeep
              []
              Start
              Live
          ]
        _ -> [],
      initial = Start,
      initialRegs = RCons (Proxy @"x") False RNil,
      isFinal = const False
    }

spec :: Spec
spec = do
  describe "validateTransducer (pure, no solver)" $ do
    it "clean transducer yields no warnings" $
      validateTransducer defaultValidationOptions cleanT `shouldBe` []

    it "overlapping pair yields a NondeterministicPair naming both indices and source" $ do
      let isOverlapStart (NondeterministicPair {tvwSource = Start, tvwEdgeA = 0, tvwEdgeB = 1}) = True
          isOverlapStart _ = False
      filter isOverlapStart (validateTransducer defaultValidationOptions overlapT)
        `shouldSatisfy` (not . null)

    it "edge from an unreachable vertex yields a PossiblyDeadEdge" $ do
      let isDeadOrphan (PossiblyDeadEdge {tvwEdge = EdgeRef {edgeSource = Orphan, edgeIndex = 0}}) = True
          isDeadOrphan _ = False
      validateTransducer defaultValidationOptions deadT
        `shouldSatisfy` any isDeadOrphan

    it "literal-PBot guard on a reachable edge yields a PossiblyDeadEdge" $ do
      let isBotDead (PossiblyDeadEdge {tvwEdge = EdgeRef {edgeSource = Start, edgeIndex = 0}, tvwDetail = d}) =
            "unsatisfiable" `isInfixOf` d
          isBotDead _ = False
      validateTransducer defaultValidationOptions botT
        `shouldSatisfy` any isBotDead

  describe "validateTransducer hidden-input (structured)" $ do
    it "flags slot c as a hidden input with structured ctor/slot data" $ do
      let warnings = validateTransducer defaultValidationOptions hiddenT
          isHiddenC (HiddenInput {tvwEdge = EdgeRef {edgeSource = False, edgeIndex = 0}, tvwInCtor = Just "Begin", tvwMissingSlots = ms}) =
            "c" `elem` ms
          isHiddenC _ = False
      warnings `shouldSatisfy` any isHiddenC

  describe "ValidationOptions toggles" $ do
    it "disabling determinism suppresses NondeterministicPair" $ do
      let opts = defaultValidationOptions {checkDeterminism = False}
          isND (NondeterministicPair {}) = True
          isND _ = False
      filter isND (validateTransducer opts overlapT) `shouldBe` []

  describe "opaque-guard audit (EP-67, opt-in)" $ do
    let optsOn = defaultValidationOptions {warnOpaqueGuards = True}
        isOpaqueStart (OpaqueGuard {tvwEdge = EdgeRef {edgeSource = Start, edgeIndex = 0}}) = True
        isOpaqueStart _ = False

    it "an opaque collection-style guard is flagged when the audit is on" $
      validateTransducer optsOn opaqueT `shouldSatisfy` any isOpaqueStart

    it "a fully structural transducer is never flagged, even with the audit on" $ do
      let isOpaque (OpaqueGuard {}) = True
          isOpaque _ = False
      filter isOpaque (validateTransducer optsOn cleanT) `shouldBe` []

    it "the audit is silent under defaultValidationOptions (backward compat)" $
      validateTransducer defaultValidationOptions opaqueT `shouldBe` []

  describe "checkTransitionDeterminismSym (z3-backed)" $ do
    it "mutually-exclusive PInCtor guards yield no determinism warning" $
      checkTransitionDeterminismSym cleanT `shouldBe` []

    it "agrees with the pure path on a PTop-vs-PInCtor overlap" $ do
      checkTransitionDeterminismPure symOverlapT `shouldSatisfy` (not . null)
      checkTransitionDeterminismSym symOverlapT `shouldSatisfy` (not . null)

  describe "provable overlap through PAnd spines" $ do
    let determinismWarningsOnly = filter isDeterminismWarning
        isDeterminismWarning (NondeterministicPair {}) = True
        isDeterminismWarning _ = False
        warningPair warning = (dwSource warning, dwEdgeA warning, dwEdgeB warning)
        pureIsSubsetOfSymbolic fixture = do
          let purePairs = map warningPair (checkTransitionDeterminismPure fixture)
              symbolicPairs = map warningPair (checkTransitionDeterminismSym fixture)
          purePairs `shouldSatisfy` all (`elem` symbolicPairs)

    it "finds the motivating same-constructor integral overlap" $ do
      determinismWarningsOnly
        (validateTransducer defaultValidationOptions motivatingOverlapT)
        `shouldBe` [ NondeterministicPair
                       { tvwSource = Start,
                         tvwEdgeA = 0,
                         tvwEdgeB = 1,
                         tvwInCtor = Just "Foo",
                         tvwDetail =
                           "edges #0 and #1 out of Start have overlapping guards"
                       }
                   ]

    it "does not warn for disjoint integral intervals" $ do
      checkTransitionDeterminismPure disjointOverlapT `shouldBe` []
      checkTransitionDeterminismPure disjointWord8T `shouldBe` []

    it "uses a mentioned non-integral literal as a concrete witness" $
      checkTransitionDeterminismPure boolLiteralWitnessT
        `shouldSatisfy` (not . null)

    it "does not guess through POr or an opaque TApp term" $ do
      checkTransitionDeterminismPure unknownOrT `shouldBe` []
      checkTransitionDeterminismPure unknownOpaqueT `shouldBe` []

    it "does not warn across different input constructors" $
      checkTransitionDeterminismPure differentCtorT `shouldBe` []

    it "keeps every pure warning inside the symbolic result" $ do
      mapM_
        pureIsSubsetOfSymbolic
        [ motivatingOverlapT,
          disjointOverlapT,
          unknownOrT,
          unknownOpaqueT,
          differentCtorT
        ]

  describe "checkDeadEdgesSym (z3-backed)" $ do
    it "flags a literal-PBot guard as unsatisfiable in isolation" $ do
      let isBotEdge (DeadEdgeWarning {dewEdge = EdgeRef {edgeSource = Start, edgeIndex = 0}}) = True
          isBotEdge _ = False
      checkDeadEdgesSym botT `shouldSatisfy` any isBotEdge
