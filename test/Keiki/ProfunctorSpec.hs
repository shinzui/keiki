{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

-- | Acceptance tests for 'Keiki.Profunctor' (EP-27 of MasterPlan 9).
--
-- The fixture is the existing 'Keiki.Fixtures.EmailDelivery'
-- aggregate. Each combinator is applied and forward processing /
-- inversion / single-valuedness / hidden-input behaviour is asserted
-- against the documented contract.
module Keiki.ProfunctorSpec (spec) where

import Control.Exception (ErrorCall (..), evaluate)
import Data.Profunctor (Profunctor (..), dimap)
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import GHC.Generics (Generic)
import Test.Hspec

import Keiki.Core
import Keiki.Fixtures.EmailDelivery
import Keiki.Profunctor
import Keiki.Symbolic (isSingleValuedSym, withSymPred)


-- | A wrapper command type used to exercise 'lmapCi'.
newtype WrappedCmd = WrappedCmd { unwrapCmd :: EmailCmd }
  deriving stock (Eq, Show, Generic)


-- | A wrapper event type used to exercise 'rmapCo'.
newtype WrappedEvent = WrappedEvent { unwrapEvent :: EmailEvent }
  deriving stock (Eq, Show, Generic)


-- | A sum command type used to exercise 'lmapMaybeCi' as a router.
data RouterCmd
  = ToEmail EmailCmd
  | OtherCmd
  deriving stock (Eq, Show, Generic)


-- | Routing function: project the EmailCmd arm of 'RouterCmd'.
router :: RouterCmd -> Maybe EmailCmd
router (ToEmail c) = Just c
router OtherCmd    = Nothing


-- | A representative input we will fire through transducers.
sampleEmailCmd :: EmailCmd
sampleEmailCmd = SendEmail SendEmailData
  { recipient = "alice@example.com"
  , subject   = "hello"
  , at        = sampleAt
  }


sampleAt :: UTCTime
sampleAt = UTCTime (fromGregorian 2026 5 3) (secondsToDiffTime 0)


-- | Fire a single command through a transducer's initial state and
-- collect '(target, output)' pairs from every active (guard-true)
-- edge. This is sufficient to assert the rewriters preserve forward
-- behaviour without going through 'delta'/'omega''s
-- single-valuedness gate.
fireFromInitial
  :: SymTransducer (HsPred rs ci) rs s ci co
  -> ci
  -> [(s, Maybe co)]
fireFromInitial t ci =
  [ (target e, fmap (\o -> evalOut o (initialRegs t) ci) (output e))
  | e <- edgesOut t (initial t)
  , evalPred (guard e) (initialRegs t) ci
  ]


-- | Pull a single edge's structural OPack output (if present) for
-- assertions about the rewriter's effect on the AST itself.
firstEdgeOutput
  :: SymTransducer (HsPred rs ci) rs s ci co
  -> Maybe (OutTerm rs ci co)
firstEdgeOutput t = case edgesOut t (initial t) of
  []      -> Nothing
  (e : _) -> output e


-- | 'fireFromInitial' but drops the (existential) vertex type so the
-- result can escape an existential pattern. Returns the per-edge
-- output (or Nothing for ε-edges) in the same order edges were
-- fired.
fireOutputsOnly
  :: SymTransducer (HsPred rs ci) rs s ci co
  -> ci
  -> [Maybe co]
fireOutputsOnly t ci = map snd (fireFromInitial t ci)


spec :: Spec
spec = do

  describe "lmapCi" $ do

    it "preserves forward processing through the rewritten transducer" $ do
      let lmapped = lmapCi unwrapCmd emailDelivery
          original = emailDelivery
          fromOriginal = fireFromInitial original sampleEmailCmd
          fromLmapped  = fireFromInitial lmapped (WrappedCmd sampleEmailCmd)
      length fromOriginal `shouldBe` length fromLmapped
      map fst fromOriginal `shouldBe` map fst fromLmapped
      map snd fromOriginal `shouldBe` map snd fromLmapped

    it "raises a poisoned-icBuild error when solveOutput is forced on lmapped edges" $ do
      let lmapped = lmapCi unwrapCmd emailDelivery
      case firstEdgeOutput lmapped of
        Nothing -> expectationFailure "lmapped EmailDelivery should have a non-eps edge output"
        Just o  -> do
          -- The structural inverse returns 'Just (icBuild …)' — the
          -- 'Just' is in WHNF but the inner thunk only fires when
          -- forced. lmapCi's contract: if you try to recover a 'ci'
          -- from a wire event, the poisoned icBuild raises a clear
          -- error. We force the inner value and assert the throw.
          let event = EmailSent EmailSentData
                { recipient = "alice@example.com"
                , subject   = "hello"
                , at        = sampleAt
                }
              recovered :: Maybe WrappedCmd
              recovered = solveOutput o (initialRegs lmapped) event
          case recovered of
            Nothing -> expectationFailure
              "lmapped solveOutput unexpectedly returned Nothing — \
              \the contract is 'Just (poison)' not 'Nothing'"
            Just c -> evaluate c
              `shouldThrow` errorCall' "icBuild on a contramapped InCtor"

    it "preserves isSingleValuedSym" $ do
      isSingleValuedSym (withSymPred (lmapCi unwrapCmd emailDelivery))
        `shouldBe` True

  describe "rmapCo" $ do

    it "post-composes the output through the supplied function" $ do
      let rmapped = rmapCo WrappedEvent emailDelivery
          fromRmapped = fireFromInitial rmapped sampleEmailCmd
          expected =
            [ ( EmailSentVertex
              , Just (WrappedEvent
                       (EmailSent EmailSentData
                         { recipient = "alice@example.com"
                         , subject   = "hello"
                         , at        = sampleAt
                         })) )
            ]
      fromRmapped `shouldBe` expected

    it "returns Nothing from solveOutput on rmapped edges" $ do
      let rmapped = rmapCo WrappedEvent emailDelivery
      case firstEdgeOutput rmapped of
        Nothing -> expectationFailure "rmapped EmailDelivery should have a non-eps edge output"
        Just o  -> do
          let wrappedEvent = WrappedEvent
                ( EmailSent EmailSentData
                    { recipient = "alice@example.com"
                    , subject   = "hello"
                    , at        = sampleAt
                    } )
          solveOutput o (initialRegs rmapped) wrappedEvent
            `shouldBe` (Nothing :: Maybe EmailCmd)

    it "preserves isSingleValuedSym" $ do
      isSingleValuedSym (withSymPred (rmapCo WrappedEvent emailDelivery))
        `shouldBe` True

  describe "dimapTransducer" $ do

    it "agrees with rmapCo . lmapCi on forward output" $ do
      let viaDimap   = dimapTransducer unwrapCmd WrappedEvent emailDelivery
          viaSplit   = rmapCo WrappedEvent (lmapCi unwrapCmd emailDelivery)
          input      = WrappedCmd sampleEmailCmd
      fireFromInitial viaDimap input
        `shouldBe` fireFromInitial viaSplit input

  describe "lmapMaybeCi" $ do

    it "filters non-routed inputs (no edges fire)" $ do
      let routed = lmapMaybeCi router emailDelivery
      fireFromInitial routed OtherCmd `shouldBe` []

    it "passes routed inputs through" $ do
      let routed = lmapMaybeCi router emailDelivery
          fired = fireFromInitial routed (ToEmail sampleEmailCmd)
      length fired `shouldBe` 1
      map fst fired `shouldBe` [EmailSentVertex]

  describe "Profunctor SomeSymTransducer" $ do

    it "dimap on the wrapper agrees with dimapTransducer on the inner" $ do
      let viaWrapper =
            dimap unwrapCmd WrappedEvent (someSymTransducer emailDelivery)
          viaConcrete =
            dimapTransducer unwrapCmd WrappedEvent emailDelivery
          input = WrappedCmd sampleEmailCmd
          fromConcrete = fireOutputsOnly viaConcrete input
      case viaWrapper of
        SomeSymTransducer t -> fireOutputsOnly t input `shouldBe` fromConcrete

    it "fmap on the wrapper post-composes the output" $ do
      let mapped = fmap WrappedEvent (someSymTransducer emailDelivery)
          expected =
            [ Just (WrappedEvent
                     (EmailSent EmailSentData
                       { recipient = "alice@example.com"
                       , subject   = "hello"
                       , at        = sampleAt
                       }))
            ]
      case mapped of
        SomeSymTransducer t ->
          fireOutputsOnly t sampleEmailCmd `shouldBe` expected


-- * Hspec helpers ----------------------------------------------------------

-- | A loose 'errorCall' matcher: asserts the thrown 'ErrorCall'
-- contains the given substring. Hspec ships an 'errorCall' matcher
-- for exact match; the substring variant is useful when the message
-- is partially a runtime-formatted string.
errorCall' :: String -> Selector ErrorCall
errorCall' needle (ErrorCall msg) = needle `isInfixOf'` msg


isInfixOf' :: String -> String -> Bool
isInfixOf' needle haystack
  | length needle > length haystack = False
  | take (length needle) haystack == needle = True
  | otherwise = isInfixOf' needle (drop 1 haystack)
