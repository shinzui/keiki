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

import Control.Category ((.), id)
import qualified Control.Category as Cat
import Control.Exception (evaluate)
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import Prelude hiding ((.), id)
import Test.Hspec

import Keiki.Core
import Keiki.Fixtures.EmailDelivery
import Keiki.Profunctor
import Keiki.Symbolic (isSingleValuedSym, withSymPred)


-- * Fixtures ----------------------------------------------------------------

sampleAt :: UTCTime
sampleAt = UTCTime (fromGregorian 2026 5 9) (secondsToDiffTime 0)


sampleSendEmail :: EmailCmd
sampleSendEmail = SendEmail SendEmailData
  { recipient = "alice@example.com"
  , subject   = "hello"
  , at        = sampleAt
  }


sampleEmailEvent :: EmailEvent
sampleEmailEvent = EmailSent EmailSentData
  { recipient = "alice@example.com"
  , subject   = "hello"
  , at        = sampleAt
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
    eventToCmd (EmailSent d) = SendEmail SendEmailData
      { recipient = d.recipient
      , subject   = d.subject
      , at        = d.at
      }


-- * Behavioural-equality helpers --------------------------------------------

-- | Run @omega@ on the inner transducer of a 'SomeSymTransducer'
-- starting from its initial state and return the wire output.
-- Behavioural equality between @t1@ and @t2@ on input @ci@ is
-- defined as @runOmega t1 ci == runOmega t2 ci@.
--
-- The 'SomeSymIdentity' sentinel returns its input verbatim — by
-- definition, that is what 'Cat.id' means.
runOmega :: SomeSymTransducer ci co -> ci -> Maybe co
runOmega (SomeSymTransducer t) ci =
  omega t (initial t) (initialRegs t) ci
runOmega SomeSymIdentity ci = Just ci


-- * Specs -------------------------------------------------------------------

spec :: Spec
spec = do

  describe "Cat.id" $ do

    it "lifts identityTransducer at any alphabet" $ do
      let identityAtCmd :: SomeSymTransducer EmailCmd EmailCmd
          identityAtCmd = id
      runOmega identityAtCmd sampleSendEmail
        `shouldBe` Just sampleSendEmail

    it "round-trips an EmailEvent through its EmailEvent identity" $ do
      let identityAtEvent :: SomeSymTransducer EmailEvent EmailEvent
          identityAtEvent = id
      runOmega identityAtEvent sampleEmailEvent
        `shouldBe` Just sampleEmailEvent

  describe "Category laws (behavioural, up to state-isomorphism)" $ do

    it "L1 left identity: id . t behaves like t on a representative input" $
      runOmega (id . someEmail) sampleSendEmail
        `shouldBe` runOmega someEmail sampleSendEmail

    it "L2 right identity: t . id behaves like t on a representative input" $
      runOmega (someEmail . id) sampleSendEmail
        `shouldBe` runOmega someEmail sampleSendEmail

    it "L3 associativity: (t3 . t2) . t1 == t3 . (t2 . t1) on a representative input" $
      let t1 = someEmail
          t2 = id :: SomeSymTransducer EmailEvent EmailEvent
          t3 = id :: SomeSymTransducer EmailEvent EmailEvent
          left  = (t3 . t2) . t1
          right = t3 . (t2 . t1)
      in runOmega left sampleSendEmail
           `shouldBe` runOmega right sampleSendEmail

    it "L1 with concrete output: id . someEmail still emits the wire EmailEvent" $
      runOmega (id . someEmail) sampleSendEmail
        `shouldBe` Just sampleEmailEvent

  describe "CategoryOverlapError on slot-name collision" $ do

    it "raises when both halves share register slots" $ do
      -- adaptedEmail's slot list is the same as emailDelivery's
      -- (EmailRegs); composing them on the EmailEvent boundary
      -- forces the runtime check to fail on all three EmailRegs
      -- slots.
      let composed = adaptedEmail . someEmail
      evaluate composed
        `shouldThrow`
        (\e ->
            let slots = coeSlots e
            in    "emailRecipient" `elem` slots
               && "emailSubject"   `elem` slots
               && "emailSentAt"    `elem` slots)

    it "does NOT raise when one half is the empty-slot identity" $ do
      -- id has rs = '[], so Disjoint reduces statically; the
      -- runtime check finds no overlap.
      let composedL = id . someEmail
          composedR = someEmail . id
      runOmega composedL sampleSendEmail `shouldBe` Just sampleEmailEvent
      runOmega composedR sampleSendEmail `shouldBe` Just sampleEmailEvent

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
