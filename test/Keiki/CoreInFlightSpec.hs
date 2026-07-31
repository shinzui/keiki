module Keiki.CoreInFlightSpec (spec) where

import Data.Proxy (Proxy (..))
import Keiki.Core
import Test.Hspec

-- | A synthetic 2-event command for one transition. The input has one
-- constructor; the output alphabet has two: 'Started' and 'Echoed'.
-- A single edge from 'False' to 'True' emits both, in that order.
data MultiInput = Begin Int deriving (Eq, Show)

data MultiOutput = Started Int | Echoed Int deriving (Eq, Show)

inCtorBegin :: InCtor MultiInput '[ '("payload", Int)]
inCtorBegin =
  InCtor
    { icName = "Begin",
      icMatch = \case
        Begin n -> Just (RCons (Proxy @"payload") n RNil),
      icBuild = \(RCons _ n RNil) -> Begin n
    }

wcStarted :: WireCtor MultiOutput (Int, ())
wcStarted =
  WireCtor
    { wcName = "Started",
      wcMatch = \case
        Started n -> Just (n, ())
        _ -> Nothing,
      wcBuild = \(n, ()) -> Started n
    }

wcEchoed :: WireCtor MultiOutput (Int, ())
wcEchoed =
  WireCtor
    { wcName = "Echoed",
      wcMatch = \case
        Echoed n -> Just (n, ())
        _ -> Nothing,
      wcBuild = \(n, ()) -> Echoed n
    }

-- | A minimal 2-vertex transducer with one length-2 edge:
--
--   False --[guard ci=Begin / output [Started n, Echoed n]]--> True
multi :: SymTransducer (HsPred '[] MultiInput) '[] Bool MultiInput MultiOutput
multi =
  SymTransducer
    { edgesOut = \case
        False ->
          [ Edge
              { guard = matchInCtor inCtorBegin,
                update = UKeep,
                output =
                  [ pack
                      inCtorBegin
                      wcStarted
                      (OFCons (TInpCtorField inCtorBegin (#payload :: Index '[ '("payload", Int)] Int)) OFNil),
                    pack
                      inCtorBegin
                      wcEchoed
                      (OFCons (TInpCtorField inCtorBegin (#payload :: Index '[ '("payload", Int)] Int)) OFNil)
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

spec :: Spec
spec = do
  describe "omega returns a length-2 event list for a multi-event edge" $ do
    it "Begin 42 yields [Started 42, Echoed 42]" $
      omega multi False RNil (Begin 42) `shouldBe` [Started 42, Echoed 42]

  describe "step's third component is the same length-2 list" $ do
    it "step (False, RNil) (Begin 7) returns (True, _, [Started 7, Echoed 7])" $
      case step multi (False, RNil) (Begin 7) of
        Just (True, _, [Started 7, Echoed 7]) -> pure ()
        other -> expectationFailure ("unexpected: " <> show3 other)

  describe "applyEvents (chunked replay)" $ do
    it "round-trips [Started 42, Echoed 42] from Settled False" $
      case applyEvents multi (False, RNil) [Started 42, Echoed 42] of
        Just (s, _) -> s `shouldBe` True
        Nothing -> expectationFailure "applyEvents returned Nothing"

    it "rejects a truncated chunk [Started 42] (queue non-empty at end)" $
      case applyEvents multi (False, RNil) [Started 42] of
        Nothing -> pure ()
        Just _ ->
          expectationFailure
            "applyEvents accepted a chunk that ends mid-flight"

    it "rejects an out-of-order chunk [Echoed 42, Started 42]" $
      case applyEvents multi (False, RNil) [Echoed 42, Started 42] of
        Nothing -> pure ()
        Just _ -> expectationFailure "applyEvents accepted out-of-order events"

  describe "applyEventStreaming (event-by-event)" $ do
    it "Settled False ⊢ Started 42 → InFlight True [Echoed 42]" $
      case applyEventStreaming multi (Settled False) RNil (Started 42) of
        Just (InFlight True [Echoed 42], _) -> pure ()
        other -> expectationFailure ("unexpected: " <> showInFlight other)

    it "InFlight True [Echoed 42] ⊢ Echoed 42 → Settled True" $
      case applyEventStreaming multi (InFlight True [Echoed 42]) RNil (Echoed 42) of
        Just (Settled True, _) -> pure ()
        other -> expectationFailure ("unexpected: " <> showInFlight other)

    it "Settled False ⊢ Echoed 42 → Nothing (out-of-order)" $
      case applyEventStreaming multi (Settled False) RNil (Echoed 42) of
        Nothing -> pure ()
        Just _ -> expectationFailure "accepted out-of-order first event"

    it "InFlight True [Echoed 42] ⊢ Started 42 → Nothing (queue mismatch)" $
      case applyEventStreaming multi (InFlight True [Echoed 42]) RNil (Started 42) of
        Nothing -> pure ()
        Just _ ->
          expectationFailure
            "applyEventStreaming accepted an out-of-order tail event"

  describe "streaming and chunked replay agree on the final state" $ do
    it "step-by-step InFlight threading reaches the same Settled True" $ do
      let chunked = applyEvents multi (False, RNil) [Started 42, Echoed 42]
          streamed = do
            (s1, regs1) <- applyEventStreaming multi (Settled False) RNil (Started 42)
            (s2, regs2) <- applyEventStreaming multi s1 regs1 (Echoed 42)
            case s2 of
              Settled v -> Just (v, regs2)
              _ -> Nothing
      case (chunked, streamed) of
        (Just (cs, _), Just (ss, _)) -> cs `shouldBe` ss
        _ ->
          expectationFailure
            "chunked and streaming replay disagreed on the final state"
  where
    show3 :: Maybe (Bool, x, [MultiOutput]) -> String
    show3 Nothing = "Nothing"
    show3 (Just (s, _, cos_)) =
      "Just (" <> show s <> ", _, " <> show cos_ <> ")"

    showInFlight :: Maybe (InFlight Bool MultiOutput, x) -> String
    showInFlight Nothing = "Nothing"
    showInFlight (Just (w, _)) = "Just (" <> show w <> ", _)"
