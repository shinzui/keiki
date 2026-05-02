-- | EP-15 M4: cross-form equivalence test for EmailDelivery. Asserts
-- that the builder-form 'emailDelivery' and the AST-form
-- 'emailDeliveryAST' produce identical 'delta' / 'omega' / replay
-- behaviour on the canonical command sequence.
module Keiki.Examples.EmailDeliveryBuilderSpec (spec) where

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec
import Keiki.Core
import Keiki.Examples.EmailDelivery


-- | Hand-computed snapshot equality on the three EmailRegs slots.
-- 'RegFile' has no 'Eq' instance, so we extract a tuple.
type Snapshot = (Email, Subject, UTCTime)


snapshot :: RegFile EmailRegs -> Snapshot
snapshot regs =
  ( regs ! #emailRecipient
  , regs ! #emailSubject
  , regs ! #emailSentAt
  )


canonicalCmd :: EmailCmd
canonicalCmd = SendEmail (SendEmailData "alice@x" "Subject" (t 0))


canonicalEvent :: EmailEvent
canonicalEvent = EmailSent (EmailSentData "alice@x" "Subject" (t 0))


t :: Integer -> UTCTime
t s = UTCTime (fromGregorian 2026 5 2) (secondsToDiffTime s)


spec :: Spec
spec = do
  describe "EP-15 M4: builder vs AST agreement on the canonical SendEmail" $ do

    it "delta moves both forms from EmailPending to EmailSentVertex" $ do
      let astStep   = delta emailDeliveryAST EmailPending emptyEmailRegs canonicalCmd
          builtStep = delta emailDelivery     EmailPending emptyEmailRegs canonicalCmd
      fmap fst astStep   `shouldBe` Just EmailSentVertex
      fmap fst builtStep `shouldBe` Just EmailSentVertex

    it "delta produces identical post-state register snapshots" $ do
      case ( delta emailDeliveryAST EmailPending emptyEmailRegs canonicalCmd
           , delta emailDelivery     EmailPending emptyEmailRegs canonicalCmd
           ) of
        (Just (_, regsA), Just (_, regsB)) ->
          snapshot regsA `shouldBe` snapshot regsB
        _ -> expectationFailure "one of the forms returned Nothing"

    it "omega emits the canonical EmailSent event from both forms" $ do
      omega emailDeliveryAST EmailPending emptyEmailRegs canonicalCmd
        `shouldBe` Just canonicalEvent
      omega emailDelivery     EmailPending emptyEmailRegs canonicalCmd
        `shouldBe` Just canonicalEvent

    it "reconstitute returns the same state for both forms" $ do
      let logEvents = [canonicalEvent]
      case (reconstitute emailDeliveryAST logEvents, reconstitute emailDelivery logEvents) of
        (Just (sA, regsA), Just (sB, regsB)) -> do
          sA `shouldBe` sB
          snapshot regsA `shouldBe` snapshot regsB
        (a, b) ->
          expectationFailure ("reconstitute results differ: "
                             <> show (fmap fst a) <> " vs " <> show (fmap fst b))

    it "isFinal predicate matches between forms" $ do
      isFinal emailDeliveryAST EmailPending     `shouldBe` False
      isFinal emailDelivery    EmailPending     `shouldBe` False
      isFinal emailDeliveryAST EmailSentVertex  `shouldBe` True
      isFinal emailDelivery    EmailSentVertex  `shouldBe` True

    it "edges out of EmailSentVertex are empty in both forms" $ do
      length (edgesOut emailDeliveryAST EmailSentVertex) `shouldBe` 0
      length (edgesOut emailDelivery    EmailSentVertex) `shouldBe` 0
