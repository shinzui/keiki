{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeFamilies #-}

module Keiki.FullSymbolicReplayInversionSpec (spec) where

import Data.List.NonEmpty (NonEmpty (..))
import Data.Proxy (Proxy (..))
import GHC.Generics (Generic)
import Keiki.Core
import Keiki.Generics
  ( FieldsOf,
    RegFieldsOf,
    mkInCtorVia,
    mkWireCtor0Via,
    mkWireCtorVia,
  )
import Keiki.Symbolic
import Test.Hspec

data AmountData = AmountData {amount :: Int}
  deriving stock (Eq, Show, Generic)

data Command
  = Submit AmountData
  | Alternate AmountData
  deriving stock (Eq, Show, Generic)

data RecordedData = RecordedData
  { amount :: Int,
    checked :: Int
  }
  deriving stock (Eq, Show, Generic)

data Event
  = Recorded RecordedData
  | OtherRecorded RecordedData
  | FirstNullary
  | SecondNullary
  | ThirdNullary
  deriving stock (Eq, Show, Generic)

data Unsupported = Unsupported Int
  deriving stock (Eq, Show)

data UnsupportedData = UnsupportedData
  { recoveredAmount :: Int,
    unsupportedValue :: Unsupported
  }
  deriving stock (Eq, Show, Generic)

data UnsupportedEvent = UnsupportedRecorded UnsupportedData
  deriving stock (Eq, Show, Generic)

data ProjectedData = ProjectedData
  { projectedAmount :: Int,
    projectedFlag :: Bool
  }
  deriving stock (Eq, Show, Generic)

data ProjectedEvent = ProjectedRecorded ProjectedData
  deriving stock (Eq, Show, Generic)

data FlagProjection

instance FieldProjection FlagProjection where
  type FieldName FlagProjection = "flag"
  type FieldOwner FlagProjection = Bool
  type FieldResult FlagProjection = Bool
  fieldShapeId _ = "bool/identity"
  projectFieldValue _ = id

instance ExactFieldProjection FlagProjection where
  fieldProjectionDomain _ = finiteProjectionDomain (False :| [True])
  reconstructFieldOwner _ = Just

data Vertex = Only
  deriving stock (Eq, Show, Enum, Bounded)

type AmountFields = RegFieldsOf AmountData

inSubmit :: InCtor Command AmountFields
inSubmit = mkInCtorVia @"Submit"

inAlternate :: InCtor Command AmountFields
inAlternate = mkInCtorVia @"Alternate"

wireRecorded :: WireCtor Event (FieldsOf RecordedData)
wireRecorded = mkWireCtorVia @"Recorded"

wireOtherRecorded :: WireCtor Event (FieldsOf RecordedData)
wireOtherRecorded = mkWireCtorVia @"OtherRecorded"

wireUnsupported :: WireCtor UnsupportedEvent (FieldsOf UnsupportedData)
wireUnsupported = mkWireCtorVia @"UnsupportedRecorded"

wireProjected :: WireCtor ProjectedEvent (FieldsOf ProjectedData)
wireProjected = mkWireCtorVia @"ProjectedRecorded"

wireFirstNullary :: WireCtor Event ()
wireFirstNullary = mkWireCtor0Via @"FirstNullary"

wireSecondNullary :: WireCtor Event ()
wireSecondNullary = mkWireCtor0Via @"SecondNullary"

wireThirdNullary :: WireCtor Event ()
wireThirdNullary = mkWireCtor0Via @"ThirdNullary"

submitAmount :: Term rs Command AmountFields Int
submitAmount = TInpCtorField inSubmit (#amount)

alternateAmount :: Term rs Command AmountFields Int
alternateAmount = TInpCtorField inAlternate (#amount)

recordedWith ::
  InCtor Command AmountFields ->
  Term rs Command AmountFields Int ->
  Term rs Command AmountFields Int ->
  OutTerm rs Command Event
recordedWith inputCtor recovered derived =
  pack inputCtor wireRecorded (recovered *: derived *: oNil)

recordedPlus :: Int -> OutTerm rs Command Event
recordedPlus increment =
  recordedWith
    inSubmit
    submitAmount
    (TArith OpAdd submitAmount (TLit increment))

recordedLiteral :: Int -> OutTerm rs Command Event
recordedLiteral value = recordedWith inSubmit submitAmount (TLit value)

recordedOpaqueApplication :: (Int -> Int) -> OutTerm rs Command Event
recordedOpaqueApplication function =
  recordedWith inSubmit submitAmount (TApp1 function submitAmount)

recordedAlternate :: OutTerm rs Command Event
recordedAlternate =
  recordedWith inAlternate alternateAmount alternateAmount

edge ::
  EdgeMode ->
  HsPred rs Command ->
  OutTerm rs Command event ->
  Edge (HsPred rs Command) rs Command event Vertex
edge edgeMode predicate emitted =
  Edge
    { guard = predicate,
      update = UKeep,
      output = [emitted],
      target = Only,
      mode = edgeMode
    }

machine ::
  RegFile rs ->
  [Edge (HsPred rs Command) rs Command event Vertex] ->
  SymTransducer (HsPred rs Command) rs Vertex Command event
machine registers outgoing =
  SymTransducer
    { edgesOut = \Only -> outgoing,
      initial = Only,
      initialRegs = registers,
      isFinal = const True
    }

noRegsMachine ::
  [Edge (HsPred '[] Command) '[] Command event Vertex] ->
  SymTransducer (HsPred '[] Command) '[] Vertex Command event
noRegsMachine = machine RNil

onlyDetail :: [InversionAnalysisDetail Vertex] -> InversionAnalysisDetail Vertex
onlyDetail [detail] = detail
onlyDetail details = error ("expected exactly one inversion detail, got " <> show (length details))

spec :: Spec
spec = describe "full symbolic replay inversion" $ do
  it "proves an output-dependent pair disjoint and removes its compatibility warning" $ do
    let transducer =
          noRegsMachine
            [ edge Live (PInCtor inSubmit) (recordedPlus 0),
              edge Live (PInCtor inSubmit) (recordedPlus 1)
            ]
    detail <- onlyDetail <$> checkInversionAmbiguitySymDetailed transducer
    iadHeadRelation detail `shouldBe` WireHeadsStructurallyEqual
    iadSolverStatus detail `shouldBe` InversionSolverUnsatisfiable
    iadVerdict detail `shouldBe` InversionProvedDisjoint
    checkInversionAmbiguitySym transducer `shouldReturn` []

  it "retains a real overlap and does not call SAT a concrete witness" $ do
    let transducer =
          noRegsMachine
            [ edge Live (PInCtor inSubmit) (recordedPlus 0),
              edge Live (PInCtor inSubmit) (recordedPlus 0)
            ]
    detail <- onlyDetail <$> checkInversionAmbiguitySymDetailed transducer
    iadSolverStatus detail `shouldBe` InversionSolverSatisfiable
    iadVerdict detail `shouldBe` InversionNotProvedDisjoint
    length <$> checkInversionAmbiguitySym transducer `shouldReturn` 1

  it "shares registers and proves guard-only disjointness" $ do
    let registers = RCons (Proxy @"limit") 0 RNil
        lower = PAnd (PInCtor inSubmit) (PCmp CmpLt (TReg (#limit)) (TLit (0 :: Int)))
        upper = PAnd (PInCtor inSubmit) (PCmp CmpGe (TReg (#limit)) (TLit (0 :: Int)))
        transducer =
          machine
            registers
            [ edge Live lower (recordedPlus 0),
              edge Live upper (recordedPlus 0)
            ]
    iadVerdict . onlyDetail <$> checkInversionAmbiguitySymDetailed transducer
      `shouldReturn` InversionProvedDisjoint

  it "keeps candidate commands independent" $ do
    let transducer =
          noRegsMachine
            [ edge Live (PInCtor inSubmit) (recordedPlus 0),
              edge Live (PInCtor inAlternate) recordedAlternate
            ]
    iadSolverStatus . onlyDetail <$> checkInversionAmbiguitySymDetailed transducer
      `shouldReturn` InversionSolverSatisfiable

  it "leaves literal output positions unconstrained" $ do
    let transducer =
          noRegsMachine
            [ edge Live (PInCtor inSubmit) (recordedLiteral 0),
              edge Live (PInCtor inSubmit) (recordedLiteral 1)
            ]
    iadSolverStatus . onlyDetail <$> checkInversionAmbiguitySymDetailed transducer
      `shouldReturn` InversionSolverSatisfiable

  it "leaves TReg audit outputs unconstrained and keys duplicate labels by position" $ do
    let firstDuplicate = ZIdx :: Index '[ '("dup", Int), '("dup", Int)] Int
        secondDuplicate = SIdx ZIdx :: Index '[ '("dup", Int), '("dup", Int)] Int
        registers =
          RCons (Proxy @"dup") 0 (RCons (Proxy @"dup") 1 RNil)
        leftGuard =
          PAnd
            (PInCtor inSubmit)
            (PEq (TReg firstDuplicate) (TLit (0 :: Int)))
        rightGuard =
          PAnd
            (PInCtor inSubmit)
            (PEq (TReg secondDuplicate) (TLit (1 :: Int)))
        leftOutput = recordedWith inSubmit submitAmount (TReg firstDuplicate)
        rightOutput = recordedWith inSubmit submitAmount (TReg secondDuplicate)
        transducer =
          machine
            registers
            [ edge Live leftGuard leftOutput,
              edge Live rightGuard rightOutput
            ]
    iadSolverStatus . onlyDetail <$> checkInversionAmbiguitySymDetailed transducer
      `shouldReturn` InversionSolverSatisfiable

  it "widens opaque TApp verification and records both candidates" $ do
    let transducer =
          noRegsMachine
            [ edge Live (PInCtor inSubmit) (recordedOpaqueApplication id),
              edge Live (PInCtor inSubmit) (recordedOpaqueApplication (+ 1))
            ]
    detail <- onlyDetail <$> checkInversionAmbiguitySymDetailed transducer
    iadSolverStatus detail `shouldBe` InversionSolverSatisfiable
    iadTranslationIssues detail
      `shouldContain` [InversionOpaqueDerivedOutput InversionCandidateA 1]
    iadTranslationIssues detail
      `shouldContain` [InversionOpaqueDerivedOutput InversionCandidateB 1]

  it "does not run a solver when structural evidence is missing" $ do
    let unavailable = wireRecorded {wcSchema = wireSchemaUnavailable}
        outputWith wire = pack inSubmit wire (submitAmount *: submitAmount *: oNil)
        transducer =
          noRegsMachine
            [ edge Live (PInCtor inSubmit) (outputWith wireRecorded),
              edge Live (PInCtor inSubmit) (outputWith unavailable)
            ]
    detail <- onlyDetail <$> checkInversionAmbiguitySymDetailed transducer
    iadHeadRelation detail `shouldBe` WireHeadsUnwitnessed
    iadSolverStatus detail `shouldBe` InversionSolverNotRun
    iadTranslationIssues detail `shouldBe` [InversionWireSchemasUnwitnessed]

  it "widens unsupported observed carriers" $ do
    let outputWith function =
          pack
            inSubmit
            wireUnsupported
            (submitAmount *: TApp1 function submitAmount *: oNil)
        transducer =
          noRegsMachine
            [ edge Live (PInCtor inSubmit) (outputWith Unsupported),
              edge Live (PInCtor inSubmit) (outputWith (Unsupported . (+ 1)))
            ]
    detail <- onlyDetail <$> checkInversionAmbiguitySymDetailed transducer
    iadSolverStatus detail `shouldBe` InversionSolverSatisfiable
    iadTranslationIssues detail
      `shouldSatisfy` any (\case InversionUnsupportedObservedFieldCarrier 1 _ -> True; _ -> False)

  it "relates exact structural projections to the shared observed field" $ do
    let flagA = ZIdx :: Index '[ '("flag", Bool), '("flag", Bool)] Bool
        flagB = SIdx ZIdx :: Index '[ '("flag", Bool), '("flag", Bool)] Bool
        projected index = TFieldProj (exactFieldWitness @FlagProjection) (PBReg index)
        outputWith index =
          pack inSubmit wireProjected (submitAmount *: projected index *: oNil)
        leftGuard =
          PAnd
            (PInCtor inSubmit)
            (PEq (projected flagA) (TLit True))
        rightGuard =
          PAnd
            (PInCtor inSubmit)
            (PEq (projected flagB) (TLit False))
        registers = RCons (Proxy @"flag") False (RCons (Proxy @"flag") False RNil)
        transducer =
          machine
            registers
            [ edge Live leftGuard (outputWith flagA),
              edge Live rightGuard (outputWith flagB)
            ]
    detail <- onlyDetail <$> checkInversionAmbiguitySymDetailed transducer
    iadSolverStatus detail `shouldBe` InversionSolverUnsatisfiable
    iadTranslationIssues detail
      `shouldSatisfy` all (\case InversionUnsupportedDerivedProjection {} -> False; _ -> True)

  it "uses structural head difference even when short names collide" $ do
    let sameNameRecorded = wireRecorded {wcName = "Same"}
        sameNameOther = wireOtherRecorded {wcName = "Same"}
        firstOutput = pack inSubmit sameNameRecorded (submitAmount *: submitAmount *: oNil)
        secondOutput = pack inSubmit sameNameOther (submitAmount *: submitAmount *: oNil)
        transducer =
          noRegsMachine
            [ edge Live (PInCtor inSubmit) firstOutput,
              edge Live (PInCtor inSubmit) secondOutput
            ]
    detail <- onlyDetail <$> checkInversionAmbiguitySymDetailed transducer
    iadHeadRelation detail `shouldBe` WireHeadsStructurallyDifferent
    iadVerdict detail `shouldBe` InversionProvedDisjoint

  it "analyzes live with live and replay-only with replay-only only" $ do
    let one = edge Live (PInCtor inSubmit) (recordedPlus 0)
        two = edge Live (PInCtor inSubmit) (recordedPlus 0)
        three = edge ReplayOnly (PInCtor inSubmit) (recordedPlus 0)
        four = edge ReplayOnly (PInCtor inSubmit) (recordedPlus 0)
        transducer = noRegsMachine [one, two, three, four]
    details <- checkInversionAmbiguitySymDetailed transducer
    ((iadLeftEdge &&& iadRightEdge) <$> details)
      `shouldBe` [(EdgeRef Only 0, EdgeRef Only 1), (EdgeRef Only 2, EdgeRef Only 3)]

  it "derives pairwise-distinct trusted schemas for an all-nullary event sum" $ do
    classifyWireHeads wireFirstNullary wireSecondNullary
      `shouldBe` WireHeadsStructurallyDifferent
    classifyWireHeads wireFirstNullary wireThirdNullary
      `shouldBe` WireHeadsStructurallyDifferent
    classifyWireHeads wireSecondNullary wireThirdNullary
      `shouldBe` WireHeadsStructurallyDifferent

  it "agrees with a finite concrete no-double-candidate oracle for every UNSAT pair" $ do
    let leftOutput = recordedPlus 0 :: OutTerm '[] Command Event
        rightOutput = recordedPlus 1 :: OutTerm '[] Command Event
        transducer =
          noRegsMachine
            [ edge Live (PInCtor inSubmit) leftOutput,
              edge Live (PInCtor inSubmit) rightOutput
            ]
        events =
          [ Recorded (RecordedData amountValue checkedValue)
          | amountValue <- [-2 .. 2],
            checkedValue <- [-2 .. 3]
          ]
        candidate outputTerm event =
          case solveOutput outputTerm RNil event of
            Nothing -> False
            Just command -> evalPred (PInCtor inSubmit) RNil command
        concreteDoubleCandidate event =
          candidate leftOutput event && candidate rightOutput event
    detail <- onlyDetail <$> checkInversionAmbiguitySymDetailed transducer
    iadSolverStatus detail `shouldBe` InversionSolverUnsatisfiable
    any concreteDoubleCandidate events `shouldBe` False

infixr 3 &&&

(&&&) :: (value -> left) -> (value -> right) -> value -> (left, right)
(left &&& right) value = (left value, right value)
