{-# LANGUAGE BlockArguments #-}

-- | Acceptance tests for the 'Control.Category.Category' instance on
-- 'SomeSymTransducer' (EP-28 of MasterPlan 9).
--
-- The fixture is the existing 'Keiki.Fixtures.EmailDelivery'
-- aggregate and the identity transducer shipped from
-- 'Keiki.Profunctor'. Tests assert the three Category laws (left
-- identity, right identity, associativity) up to state-isomorphism
-- via forward output equality, plus the runtime
-- 'CategoryOverlapError' path and survival of 'isSingleValuedSym'
-- across @id . t@.
module Keiki.CategorySpec (spec) where

import Control.Category (id, (.))
import Control.Exception (evaluate)
import Data.Either (isRight)
import Data.Profunctor (lmap, rmap)
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import Keiki.Composition
import Keiki.Core
import Keiki.Fixtures.CounterPipeline
import Keiki.Fixtures.EmailDelivery
import Keiki.Generics (Append)
import Keiki.LawHelpers (emittedLog)
import Keiki.Profunctor
import Keiki.Symbolic (isSingleValuedSym, withSymPred)
import Test.Hspec
import Prelude hiding (id, (.))

-- * Fixtures ----------------------------------------------------------------

sampleAt :: UTCTime
sampleAt = UTCTime (fromGregorian 2026 5 9) (secondsToDiffTime 0)

sampleSendEmail :: EmailCmd
sampleSendEmail =
  SendEmail
    SendEmailData
      { recipient = "alice@example.com",
        subject = "hello",
        at = sampleAt
      }

sampleEmailEvent :: EmailEvent
sampleEmailEvent =
  EmailSent
    EmailSentData
      { recipient = "alice@example.com",
        subject = "hello",
        at = sampleAt
      }

-- | @emailDelivery@ wrapped in the existential.
someEmail :: SomeSymTransducer EmailCmd EmailEvent
someEmail = someSymTransducer emailDelivery

-- | An "adapted" copy of @emailDelivery@ whose input alphabet is
-- bridged from 'EmailEvent' back to 'EmailCmd' via 'lmapCi'. Used
-- by the overlap test: @adaptedEmail Cat.. someEmail@ has middle
-- alphabet 'EmailEvent' and forces both halves to share
-- @emailDelivery@'s @EmailRegs@ slots, triggering
-- 'CategoryOverlapError'.
--
-- The 'lmapCi' step poisons @icBuild@ on the rewritten transducer
-- ('Keiki.Profunctor.lmapCi''s documented variance caveat) but the
-- forward-only overlap assertion below never invokes
-- 'Keiki.Core.solveOutput', so the poisoned 'icBuild' is harmless
-- here.
adaptedEmail :: SomeSymTransducer EmailEvent EmailEvent
adaptedEmail = someSymTransducer (lmapCi eventToCmd emailDelivery)
  where
    eventToCmd :: EmailEvent -> EmailCmd
    eventToCmd (EmailSent d) =
      SendEmail
        SendEmailData
          { recipient = d.recipient,
            subject = d.subject,
            at = d.at
          }

-- * Behavioural-equality helpers --------------------------------------------

-- | Run @omega@ on the inner transducer of a 'SomeSymTransducer'
-- starting from its initial state and return the wire output.
-- Behavioural equality between @t1@ and @t2@ on input @ci@ is
-- defined as @runOmega t1 ci == runOmega t2 ci@.
--
-- The 'SomeSymIdentity' sentinel returns its input verbatim — by
-- definition, that is what 'Cat.id' means.
runOmega :: SomeSymTransducer ci co -> ci -> [co]
runOmega (SomeSymTransducer t) ci =
  omega t (initial t) (initialRegs t) ci
runOmega SomeSymIdentity ci = [ci]

-- | Fold 'step' over an input sequence from the initial state,
-- collecting each step's emissions. 'Nothing' means a step rejected.
runSteps :: SomeSymTransducer ci co -> [ci] -> Maybe [[co]]
runSteps (SomeSymTransducer t) inputs = go (initial t, initialRegs t) inputs
  where
    go _ [] = Just []
    go st (ci : rest) = case step t st ci of
      Nothing -> Nothing
      Just (s', regs', cos_) -> (cos_ :) <$> go (s', regs') rest
runSteps SomeSymIdentity inputs = Just (map (: []) inputs)

replays :: (Eq co) => SomeSymTransducer ci co -> [ci] -> Bool
replays (SomeSymTransducer transducer) inputs =
  isRight (reconstituteEither transducer (emittedLog transducer inputs))
replays SomeSymIdentity _ = True

-- | The slot names the wrapper's hidden register file reports.
wrapperSlotNames :: SomeSymTransducer ci co -> [String]
wrapperSlotNames someT = case someT of
  SomeSymTransducer (_ :: SymTransducer (HsPred rs ci) rs s ci co) ->
    slotNames @rs
  SomeSymIdentity -> []

-- * Specs -------------------------------------------------------------------

spec :: Spec
spec = do
  describe "Cat.id" $ do
    it "lifts identityTransducer at any alphabet" $ do
      let identityAtCmd :: SomeSymTransducer EmailCmd EmailCmd
          identityAtCmd = id
      runOmega identityAtCmd sampleSendEmail
        `shouldBe` [sampleSendEmail]

    it "round-trips an EmailEvent through its EmailEvent identity" $ do
      let identityAtEvent :: SomeSymTransducer EmailEvent EmailEvent
          identityAtEvent = id
      runOmega identityAtEvent sampleEmailEvent
        `shouldBe` [sampleEmailEvent]

  describe "Category laws (behavioural, up to state-isomorphism)" $ do
    it "L1 left identity: id . t behaves like t on a representative input" $
      runOmega (id . someEmail) sampleSendEmail
        `shouldBe` runOmega someEmail sampleSendEmail

    it "L2 right identity: t . id behaves like t on a representative input" $
      runOmega (someEmail . id) sampleSendEmail
        `shouldBe` runOmega someEmail sampleSendEmail

    it "L3 associativity: three stateful stages agree under both associations" $ do
      let wa = someSymTransducer stageA
          wb = someSymTransducer stageB
          wc = someSymTransducer stageC
          inputs = [MsgA 1, MsgA 5, MsgA 2, MsgA 3]
          expected = Just [[MsgD 3], [MsgD 14], [MsgD 19], [MsgD 26]]
          left = runSteps ((wc . wb) . wa) inputs
          right = runSteps (wc . (wb . wa)) inputs
      left `shouldBe` right
      left `shouldBe` expected
      right `shouldBe` expected

      -- stageA's derived-only MsgB output cannot reconstruct MsgA, so neither
      -- association repairs the fixture's pre-existing replay defect. Keep
      -- this as an explicit inversion counterexample alongside the forward
      -- associativity observation above.
      replays ((wc . wb) . wa) inputs `shouldBe` False
      replays (wc . (wb . wa)) inputs `shouldBe` False

    it "L1 with concrete output: id . someEmail still emits the wire EmailEvent" $
      runOmega (id . someEmail) sampleSendEmail
        `shouldBe` [sampleEmailEvent]

  describe "CategoryOverlapError on slot-name collision" $ do
    it "raises when both halves share register slots" $ do
      -- adaptedEmail's slot list is the same as emailDelivery's
      -- (EmailRegs); composing them on the EmailEvent boundary
      -- forces the runtime check to fail on all three EmailRegs
      -- slots.
      let composed = adaptedEmail . someEmail
      evaluate composed
        `shouldThrow` ( \e ->
                          let slots = coeSlots e
                           in "emailRecipient" `elem` slots
                                && "emailSubject" `elem` slots
                                && "emailSentAt" `elem` slots
                      )

    it "does NOT raise when one half is the empty-slot identity" $ do
      -- id has rs = '[], so Disjoint reduces statically; the
      -- runtime check finds no overlap.
      let composedL = id . someEmail
          composedR = someEmail . id
      runOmega composedL sampleSendEmail `shouldBe` [sampleEmailEvent]
      runOmega composedR sampleSendEmail `shouldBe` [sampleEmailEvent]

  describe "PoisonedCompositionError on mapped boundaries" $ do
    it "rejects an upstream rmap boundary" $ do
      let wa = someSymTransducer stageA
          wb = someSymTransducer stageB
          mapped = rmap (\(MsgB n) -> MsgB (n + 100)) wa
      evaluate (wb . mapped)
        `shouldThrow` (\e -> pceSide e == "upstream output")

    it "rejects a downstream lmap boundary" $ do
      let wa = someSymTransducer stageA
          wb = someSymTransducer stageB
          mapped = lmap (\(MsgB n) -> MsgB (n + 100)) wb
      evaluate (mapped . wa)
        `shouldThrow` (\e -> pceSide e == "downstream input")

    it "allows an output map outside composition and applies it" $ do
      let wa = someSymTransducer stageA
          wb = someSymTransducer stageB
          mapped = rmap (\(MsgC n) -> MsgC (n + 100)) (wb . wa)
      runOmega mapped (MsgA 2) `shouldBe` [MsgC 105]

    it "carries an outer output poison into the next boundary" $ do
      let wa = someSymTransducer stageA
          wb = someSymTransducer stageB
          wc = someSymTransducer stageC
          mapped = rmap (\(MsgC n) -> MsgC (n + 100)) (wb . wa)
      evaluate (wc . mapped)
        `shouldThrow` (\e -> pceSide e == "upstream output")

    it "stamped concrete composition is dead instead of silently bypassing rmap" $ do
      let concrete = compose (rmapCo id stageA) stageB
      case step concrete (initial concrete, initialRegs concrete) (MsgA 2) of
        Nothing -> pure ()
        Just _ -> expectationFailure "stamped boundary unexpectedly fired"

  describe "nested stateful composition regressions" $ do
    it "touches the final stage's slots after a nested upstream composite" $ do
      let wa = someSymTransducer stageA
          wb = someSymTransducer stageB
          wc = someSymTransducer stageC
      runSteps (wc . (wb . wa)) [MsgA 1, MsgA 5, MsgA 2]
        `shouldBe` Just [[MsgD 3], [MsgD 14], [MsgD 19]]

    it "reports the real concatenated slot names" $ do
      let wa = someSymTransducer stageA
          wb = someSymTransducer stageB
          wc = someSymTransducer stageC
      wrapperSlotNames (wc . (wb . wa))
        `shouldBe` ["regA", "regB", "regC"]

    it "detects slot overlap against a nested composite" $ do
      let wa = someSymTransducer stageA
          wb = someSymTransducer stageB
          wc = someSymTransducer stageC
          conflict = someSymTransducer stageConflict
          composed = conflict . (wc . (wb . wa))
      evaluate composed
        `shouldThrow` (\e -> "regA" `elem` coeSlots e)

  describe "slot-list witness toolkit" $ do
    it "reports names for a concrete witness" $
      witnessNames (slotWitness @ARegs) `shouldBe` ["regA"]

    it "appends concrete witnesses in register order" $
      witnessNames (appendWitness (slotWitness @ARegs) (slotWitness @BRegs))
        `shouldBe` ["regA", "regB"]

    it "derives KnownSlots for an appended witness" $
      withKnownSlots
        (appendWitness (slotWitness @ARegs) (slotWitness @BRegs))
        (slotNames @(Append ARegs BRegs))
        `shouldBe` ["regA", "regB"]

  describe "isSingleValuedSym survives id . t" $ do
    it "single-valuedness is preserved across left identity" $
      case id . someEmail of
        SomeSymTransducer t ->
          isSingleValuedSym (withSymPred t) `shouldBe` True
        SomeSymIdentity ->
          expectationFailure
            "id . someEmail unexpectedly short-circuited to SomeSymIdentity \
            \— someEmail is not the identity sentinel"

    it "single-valuedness is preserved across right identity" $
      case someEmail . id of
        SomeSymTransducer t ->
          isSingleValuedSym (withSymPred t) `shouldBe` True
        SomeSymIdentity ->
          expectationFailure
            "someEmail . id unexpectedly short-circuited to SomeSymIdentity"
