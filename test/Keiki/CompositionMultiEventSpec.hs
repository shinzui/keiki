-- | EP-19 M6 acceptance: 'Keiki.Composition.compose' on a multi-event
-- first-edge produces a length-N composite edge via library-side
-- chain expansion. The fixture is intentionally minimal: t1 has one
-- vertex (Q) with a self-loop edge emitting two mid-symbols; t2 has
-- one vertex (Z) with a self-loop edge that consumes any mid and
-- emits one wire event. The composite's single edge from Composite
-- Q Z therefore has output of length 2.
module Keiki.CompositionMultiEventSpec (spec) where

import Data.Proxy (Proxy (..))
import GHC.Generics (Generic)
import Keiki.Composition
  ( ComposeAlignmentWarning (..),
    Composite (..),
    compose,
    composeChecked,
  )
import Keiki.Core
import Keiki.FieldProjSpec qualified as FieldProj
import Keiki.Generics
  ( mkInCtorRecordVia,
    mkInCtorVia,
    mkWireCtor0Via,
    mkWireCtorRecordVia,
  )
import Test.Hspec

-- * t1 ---------------------------------------------------------------------

-- | t1's input alphabet: a single trigger constructor carrying an Int payload.
data T1Cmd = T1Trigger Int deriving (Eq, Show)

inCtorT1Trigger :: InCtor T1Cmd '[ '("payload", Int)]
inCtorT1Trigger =
  InCtor
    { icName = "T1Trigger",
      icSchema = inCtorSchemaUnavailable,
      icMatch = \case
        T1Trigger n -> Just (RCons (Proxy @"payload") n RNil),
      icBuild = \(RCons _ n RNil) -> T1Trigger n
    }

-- | t1's mid (output) alphabet: two constructors A and B.
data Mid = MidA {a :: Int} | MidB {b :: Int}
  deriving stock (Eq, Show, Generic)

inCtorMidA :: InCtor Mid '[ '("a", Int)]
inCtorMidA = mkInCtorRecordVia @"MidA"

inCtorMidB :: InCtor Mid '[ '("b", Int)]
inCtorMidB = mkInCtorRecordVia @"MidB"

wcMidA :: WireCtor Mid (Int, ())
wcMidA = mkWireCtorRecordVia @"MidA"

wcMidB :: WireCtor Mid (Int, ())
wcMidB = mkWireCtorRecordVia @"MidB"

-- | t1's transducer: a single vertex Q with a self-loop edge that
-- emits two mid-symbols ([MidA n, MidB n]) from one T1Trigger input.
data Q = Q deriving (Eq, Ord, Show, Bounded, Enum)

t1 :: SymTransducer (HsPred '[] T1Cmd) '[] Q T1Cmd Mid
t1 =
  SymTransducer
    { edgesOut = \Q ->
        [ Edge
            { guard = matchInCtor inCtorT1Trigger,
              update = UKeep,
              output =
                [ pack
                    inCtorT1Trigger
                    wcMidA
                    ( OFCons
                        ( TInpCtorField
                            inCtorT1Trigger
                            (#payload :: Index '[ '("payload", Int)] Int)
                        )
                        OFNil
                    ),
                  pack
                    inCtorT1Trigger
                    wcMidB
                    ( OFCons
                        ( TInpCtorField
                            inCtorT1Trigger
                            (#payload :: Index '[ '("payload", Int)] Int)
                        )
                        OFNil
                    )
                ],
              target = Q,
              mode = Live
            }
        ],
      initial = Q,
      initialRegs = RNil,
      isFinal = const True
    }

-- * t2 ---------------------------------------------------------------------

-- | t2's output alphabet: one constructor.
data Echo = EchoA Int | EchoB Int deriving (Eq, Show)

wcEchoA :: WireCtor Echo (Int, ())
wcEchoA =
  WireCtor
    { wcName = "EchoA",
      wcSchema = wireSchemaUnavailable,
      wcMatch = \case
        EchoA n -> Just (n, ())
        _ -> Nothing,
      wcBuild = \(n, ()) -> EchoA n
    }

wcEchoB :: WireCtor Echo (Int, ())
wcEchoB =
  WireCtor
    { wcName = "EchoB",
      wcSchema = wireSchemaUnavailable,
      wcMatch = \case
        EchoB n -> Just (n, ())
        _ -> Nothing,
      wcBuild = \(n, ()) -> EchoB n
    }

-- | t2's vertex (single).
data Z = Z deriving (Eq, Ord, Show, Bounded, Enum)

-- | t2's transducer: two edges from Z, one per mid-symbol.
--   Z on MidA → Z / [EchoA payload]
--   Z on MidB → Z / [EchoB payload]
t2 :: SymTransducer (HsPred '[] Mid) '[] Z Mid Echo
t2 =
  SymTransducer
    { edgesOut = \Z ->
        [ Edge
            { guard = matchInCtor inCtorMidA,
              update = UKeep,
              output =
                [ pack
                    inCtorMidA
                    wcEchoA
                    ( OFCons
                        ( TInpCtorField
                            inCtorMidA
                            (#a :: Index '[ '("a", Int)] Int)
                        )
                        OFNil
                    )
                ],
              target = Z,
              mode = Live
            },
          Edge
            { guard = matchInCtor inCtorMidB,
              update = UKeep,
              output =
                [ pack
                    inCtorMidB
                    wcEchoB
                    ( OFCons
                        ( TInpCtorField
                            inCtorMidB
                            (#b :: Index '[ '("b", Int)] Int)
                        )
                        OFNil
                    )
                ],
              target = Z,
              mode = Live
            }
        ],
      initial = Z,
      initialRegs = RNil,
      isFinal = const True
    }

data PendingSourceCmd = PendingSourceCmd FieldProj.DocInfo
  deriving stock (Eq, Show)

pendingSourceCtor :: InCtor PendingSourceCmd '[ '("doc", FieldProj.DocInfo)]
pendingSourceCtor =
  InCtor
    { icName = "PendingSourceCmd",
      icSchema = inCtorSchemaUnavailable,
      icMatch = \(PendingSourceCmd doc) -> Just (RCons (Proxy @"doc") doc RNil),
      icBuild = \(RCons _ doc RNil) -> PendingSourceCmd doc
    }

data PendingMid
  = PendingLoad {doc :: FieldProj.DocInfo}
  | PendingCheck
  deriving stock (Eq, Show, Generic)

pendingLoadCtor :: InCtor PendingMid '[ '("doc", FieldProj.DocInfo)]
pendingLoadCtor = mkInCtorRecordVia @"PendingLoad"

pendingCheckCtor :: InCtor PendingMid '[]
pendingCheckCtor = mkInCtorVia @"PendingCheck"

pendingLoadWire :: WireCtor PendingMid (FieldProj.DocInfo, ())
pendingLoadWire = mkWireCtorRecordVia @"PendingLoad"

pendingCheckWire :: WireCtor PendingMid ()
pendingCheckWire = mkWireCtor0Via @"PendingCheck"

pendingSource ::
  SymTransducer (HsPred '[] PendingSourceCmd) '[] Q PendingSourceCmd PendingMid
pendingSource =
  SymTransducer
    { edgesOut = \Q ->
        [ Edge
            { guard = matchInCtor pendingSourceCtor,
              update = UKeep,
              output =
                [ pack
                    pendingSourceCtor
                    pendingLoadWire
                    (OFCons (TInpCtorField pendingSourceCtor #doc) OFNil),
                  pack pendingSourceCtor pendingCheckWire OFNil
                ],
              target = Q,
              mode = Live
            }
        ],
      initial = Q,
      initialRegs = RNil,
      isFinal = const True
    }

pendingSink ::
  SymTransducer
    (HsPred FieldProj.DocRegs PendingMid)
    FieldProj.DocRegs
    Z
    PendingMid
    ()
pendingSink =
  SymTransducer
    { edgesOut = \Z ->
        [ Edge
            { guard = matchInCtor pendingLoadCtor,
              update =
                USet
                  FieldProj.docN
                  (TApp1 id (TInpCtorField pendingLoadCtor #doc)),
              output = [],
              target = Z,
              mode = Live
            },
          Edge
            { guard =
                PAnd
                  (matchInCtor pendingCheckCtor)
                  ( regProj FieldProj.docHashW FieldProj.docIx
                      .== TLit "pending-match"
                  ),
              update = UKeep,
              output = [],
              target = Z,
              mode = Live
            }
        ],
      initial = Z,
      initialRegs =
        RCons (Proxy @"doc") FieldProj.initialDocInfo RNil,
      isFinal = const True
    }

-- * Specs ------------------------------------------------------------------

spec :: Spec
spec = do
  describe "compose t1 t2 with t1 having one length-2 edge" $ do
    it "every composite edge from (Q, Z) has a length-2 output list" $ do
      -- The chain expansion produces one composite edge per t2-edge
      -- choice per mid-symbol — 2 mid-symbols × 2 t2-edges = 4
      -- composite edges. Three of the four have unsatisfiable
      -- substituted guards (`substPred (PInCtor MidA) MidB ≡ PBot`),
      -- but they're structurally present. All four have a length-2
      -- output list — the chain expansion concatenates per-step
      -- substituted outputs.
      let pipeline = compose t1 t2
          edges = edgesOut pipeline (initial pipeline)
      length edges `shouldBe` 4
      mapM_ (\e -> length (output e) `shouldBe` 2) edges

    it "omega on T1Trigger 42 yields [EchoA 42, EchoB 42]" $ do
      let pipeline = compose t1 t2
      omega pipeline (initial pipeline) (initialRegs pipeline) (T1Trigger 42)
        `shouldBe` [EchoA 42, EchoB 42]

    it "applyEvents round-trips the 2-event chunk to the initial composite state" $ do
      let pipeline = compose t1 t2
          chunk = [EchoA 7, EchoB 7]
      case applyEvents pipeline (initial pipeline, initialRegs pipeline) chunk of
        Just (Composite Q Z, _) -> pure ()
        other ->
          expectationFailure
            ( "expected Just (Composite Q Z, _), got "
                <> show (fmap (\(s, _) -> s) other)
            )

  describe "projection through a multi-event pending write" $ do
    let matchingDoc = FieldProj.DocInfo "pending-match" "title" []

    it "raw composition preserves forward behavior and makes the loss auditable" $ do
      let pipeline = compose pendingSource pendingSink
      opaqueGuardWarnings pipeline `shouldSatisfy` (not . null)
      case stepEither
        pipeline
        (initial pipeline, initialRegs pipeline)
        (PendingSourceCmd matchingDoc) of
        Left failure -> expectationFailure ("pending-write pipeline failed: " <> show failure)
        Right _ -> pure ()

    it "composeChecked rejects the computed pending-write projection" $
      case composeChecked pendingSource pendingSink of
        Right _ -> expectationFailure "computed pending write passed composeChecked"
        Left warnings ->
          warnings
            `shouldSatisfy` any
              ( \case
                  NonStructuralProjectionBoundary
                    { cawProjectionReason = "pending write"
                    } -> True
                  _ -> False
              )
