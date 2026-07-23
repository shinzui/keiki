-- | EP-19 M6 acceptance: 'Keiki.Composition.compose' on a multi-event
-- first-edge produces a length-N composite edge via library-side
-- chain expansion. The fixture is intentionally minimal: t1 has one
-- vertex (Q) with a self-loop edge emitting two mid-symbols; t2 has
-- one vertex (Z) with a self-loop edge that consumes any mid and
-- emits one wire event. The composite's single edge from Composite
-- Q Z therefore has output of length 2.
module Keiki.CompositionMultiEventSpec (spec) where

import Data.Proxy (Proxy (..))
import Keiki.Composition (Composite (..), compose)
import Keiki.Core
import Test.Hspec

-- * t1 ---------------------------------------------------------------------

-- | t1's input alphabet: a single trigger constructor carrying an Int payload.
data T1Cmd = T1Trigger Int deriving (Eq, Show)

inCtorT1Trigger :: InCtor T1Cmd '[ '("payload", Int)]
inCtorT1Trigger =
  InCtor
    { icName = "T1Trigger",
      icMatch = \case
        T1Trigger n -> Just (RCons (Proxy @"payload") n RNil),
      icBuild = \(RCons _ n RNil) -> T1Trigger n
    }

-- | t1's mid (output) alphabet: two constructors A and B.
data Mid = MidA Int | MidB Int deriving (Eq, Show)

inCtorMidA :: InCtor Mid '[ '("a", Int)]
inCtorMidA =
  InCtor
    { icName = "MidA",
      icMatch = \case
        MidA n -> Just (RCons (Proxy @"a") n RNil)
        _ -> Nothing,
      icBuild = \(RCons _ n RNil) -> MidA n
    }

inCtorMidB :: InCtor Mid '[ '("b", Int)]
inCtorMidB =
  InCtor
    { icName = "MidB",
      icMatch = \case
        MidB n -> Just (RCons (Proxy @"b") n RNil)
        _ -> Nothing,
      icBuild = \(RCons _ n RNil) -> MidB n
    }

wcMidA :: WireCtor Mid (Int, ())
wcMidA =
  WireCtor
    { wcName = "MidA",
      wcMatch = \case
        MidA n -> Just (n, ())
        _ -> Nothing,
      wcBuild = \(n, ()) -> MidA n
    }

wcMidB :: WireCtor Mid (Int, ())
wcMidB =
  WireCtor
    { wcName = "MidB",
      wcMatch = \case
        MidB n -> Just (n, ())
        _ -> Nothing,
      wcBuild = \(n, ()) -> MidB n
    }

-- | t1's transducer: a single vertex Q with a self-loop edge that
-- emits two mid-symbols ([MidA n, MidB n]) from one T1Trigger input.
data Q = Q deriving (Eq, Show, Bounded, Enum)

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
      wcMatch = \case
        EchoA n -> Just (n, ())
        _ -> Nothing,
      wcBuild = \(n, ()) -> EchoA n
    }

wcEchoB :: WireCtor Echo (Int, ())
wcEchoB =
  WireCtor
    { wcName = "EchoB",
      wcMatch = \case
        EchoB n -> Just (n, ())
        _ -> Nothing,
      wcBuild = \(n, ()) -> EchoB n
    }

-- | t2's vertex (single).
data Z = Z deriving (Eq, Show, Bounded, Enum)

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
