{-# LANGUAGE BlockArguments #-}

-- | Acceptance tests for the 'Data.Profunctor.Strong.Strong' instance
-- on 'SomeSymTransducer' (EP-29 of MasterPlan 9, M2).
--
-- The Strong instance threads an unrelated value through a
-- transducer: @first'@ accepts a pair @(a, c)@ and emits @(b, c)@,
-- where @c@ is read straight from the input and paired with @t@'s
-- output. @second'@ is the symmetric @(c, a) -> (c, b)@.
--
-- Implemented from primitives because MP-8 (EP-24) declined a general
-- @parallel@ combinator. 'Keiki.Profunctor.firstSym' is the one-off
-- equivalent.
--
-- Fixture: 'Keiki.Fixtures.EmailDelivery' wrapped in
-- 'someSymTransducer' with a 'RequestId' threaded through. The tests
-- cover:
--
--   * Forward processing — @first'@ on a sample input
--     @(SendEmail, 42)@ produces @(EmailSent, 42)@.
--   * @second'@ symmetry on the swapped pair.
--   * Survival of 'Keiki.Symbolic.isSingleValuedSym'.
--   * Sentinel preservation: @first' Cat.id == Cat.id@.
module Keiki.StrongSpec (spec) where

import qualified Control.Category as Cat
import Data.Profunctor (Strong (..))
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import Test.Hspec

import Keiki.Core
import Keiki.Fixtures.EmailDelivery
import Keiki.Profunctor
import Keiki.Symbolic (isSingleValuedSym, withSymPred)


-- * Fixtures ----------------------------------------------------------------

newtype RequestId = RequestId Int
  deriving stock (Eq, Show)


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


someEmail :: SomeSymTransducer EmailCmd EmailEvent
someEmail = someSymTransducer emailDelivery


-- * Specs -------------------------------------------------------------------

spec :: Spec
spec = do

  describe "first'" $ do

    it "threads an unrelated RequestId through emailDelivery" $ do
      let routed :: SomeSymTransducer (EmailCmd, RequestId) (EmailEvent, RequestId)
          routed = first' someEmail
          requestId = RequestId 42
      case routed of
        SomeSymTransducer t ->
          omega t (initial t) (initialRegs t) (sampleSendEmail, requestId)
            `shouldBe` [(sampleEmailEvent, requestId)]
        SomeSymIdentity ->
          expectationFailure
            "first' (someSymTransducer emailDelivery) unexpectedly returned \
            \the identity sentinel"

    it "preserves Cat.id on the sentinel: first' Cat.id == Cat.id" $ do
      let lifted :: SomeSymTransducer (Int, Bool) (Int, Bool)
          lifted = first' (Cat.id :: SomeSymTransducer Int Int)
      case lifted of
        SomeSymIdentity     -> pure ()
        SomeSymTransducer _ ->
          expectationFailure "first' Cat.id should preserve the identity sentinel"

  describe "second'" $ do

    it "threads an unrelated RequestId through emailDelivery on the second slot" $ do
      let routed :: SomeSymTransducer (RequestId, EmailCmd) (RequestId, EmailEvent)
          routed = second' someEmail
          requestId = RequestId 99
      case routed of
        SomeSymTransducer t ->
          omega t (initial t) (initialRegs t) (requestId, sampleSendEmail)
            `shouldBe` [(requestId, sampleEmailEvent)]
        SomeSymIdentity ->
          expectationFailure
            "second' (someSymTransducer emailDelivery) unexpectedly returned \
            \the identity sentinel"

    it "preserves Cat.id on the sentinel: second' Cat.id == Cat.id" $ do
      let lifted :: SomeSymTransducer (Bool, Int) (Bool, Int)
          lifted = second' (Cat.id :: SomeSymTransducer Int Int)
      case lifted of
        SomeSymIdentity     -> pure ()
        SomeSymTransducer _ ->
          expectationFailure "second' Cat.id should preserve the identity sentinel"

  describe "isSingleValuedSym survives first' / second'" $ do

    it "single-valuedness is preserved across first'" $
      case first' someEmail
            :: SomeSymTransducer (EmailCmd, RequestId) (EmailEvent, RequestId) of
        SomeSymTransducer t ->
          isSingleValuedSym (withSymPred t) `shouldBe` True
        SomeSymIdentity ->
          expectationFailure
            "first' on a non-identity wrapper returned the identity sentinel"

    it "single-valuedness is preserved across second'" $
      case second' someEmail
            :: SomeSymTransducer (RequestId, EmailCmd) (RequestId, EmailEvent) of
        SomeSymTransducer t ->
          isSingleValuedSym (withSymPred t) `shouldBe` True
        SomeSymIdentity ->
          expectationFailure
            "second' on a non-identity wrapper returned the identity sentinel"
