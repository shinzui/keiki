-- | EP-19 M7 acceptance: the post-collapse UserRegistration emits a
-- length-2 event chain from 'StartRegistration' directly. Verifies
-- the multi-event 'decide' shape, chunk replay via 'applyEvents',
-- and streaming replay via 'applyEventStreaming' agree on the final
-- state.
module Jitsurei.UserRegistrationGSMSpec (spec) where

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

import Keiki.Core
import Keiki.Decider
import Jitsurei.UserRegistration


t :: Integer -> UTCTime
t s = UTCTime (fromGregorian 2026 5 16) (secondsToDiffTime s)


spec :: Spec
spec = do
  describe "userReg's collapsed entrance (EP-19 M7)" $ do

    it "decide on StartRegistration returns a 2-element event list" $ do
      let d    = toDecider userReg
          cmd  = StartRegistration
                   (StartRegistrationData "alice@x" "Z9F4" (t 0))
          evs  = decide d cmd (initialState d)
      length evs `shouldBe` 2
      case evs of
        [ RegistrationStarted   rs
         , ConfirmationEmailSent ces
         ] -> do
          rs.email   `shouldBe` "alice@x"
          rs.confirmCode `shouldBe` "Z9F4"
          ces.email  `shouldBe` "alice@x"
        _ -> expectationFailure ("unexpected event order: " <> show evs)

    it "applyEvents round-trips the 2-event chunk to RequiresConfirmation" $ do
      let evs =
            [ RegistrationStarted
                (RegistrationStartedData "bob@x" "S0E1" (t 0))
            , ConfirmationEmailSent
                (ConfirmationEmailSentData "bob@x")
            ]
      case applyEvents userReg (PotentialCustomer, emptyRegs) evs of
        Just (s, regs) -> do
          s `shouldBe` RequiresConfirmation
          regs ! #email       `shouldBe` "bob@x"
          regs ! #confirmCode `shouldBe` "S0E1"
        Nothing -> expectationFailure "applyEvents returned Nothing"

    it "streaming applyEventStreaming agrees with chunked applyEvents" $ do
      let evs =
            [ RegistrationStarted
                (RegistrationStartedData "carol@x" "T1V2" (t 0))
            , ConfirmationEmailSent
                (ConfirmationEmailSentData "carol@x")
            ]
          chunked = applyEvents userReg (PotentialCustomer, emptyRegs) evs

          streamed = do
            (w1, r1) <- applyEventStreaming userReg
                          (Settled PotentialCustomer) emptyRegs (head evs)
            (w2, r2) <- applyEventStreaming userReg w1 r1 (evs !! 1)
            case w2 of
              Settled v -> Just (v, r2)
              _         -> Nothing
      case (chunked, streamed) of
        (Just (cs, _), Just (ss, _)) -> cs `shouldBe` ss
        _ -> expectationFailure
               "chunked and streaming replay disagreed"

    it "rejects an out-of-order entrance chunk" $ do
      -- ConfirmationEmailSent before RegistrationStarted is not the
      -- prefix of any active edge's output at PotentialCustomer.
      let bad = [ConfirmationEmailSent (ConfirmationEmailSentData "x@y")]
      case applyEvents userReg (PotentialCustomer, emptyRegs) bad of
        Nothing -> pure ()
        Just _  -> expectationFailure "applyEvents accepted an out-of-order chunk"
