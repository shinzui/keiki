module Jitsurei.UserRegistrationMultiSpec (spec) where

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec
import Keiki.Core (applyEvents, (!))
import Keiki.Decider (Decider (..), toDecider, toMultiDecider)
import Jitsurei.UserRegistration


-- | Trivial UTC fixture matching the other UserRegistration specs.
t :: Integer -> UTCTime
t s = UTCTime (fromGregorian 2026 5 1) (secondsToDiffTime s)


startCmd :: UserCmd
startCmd = StartRegistration (StartRegistrationData "alice@x" "Z9F4" (t 0))


multiEventChunk :: [UserEvent]
multiEventChunk =
  [ RegistrationStarted   (RegistrationStartedData   "alice@x" "Z9F4" (t 0))
  , ConfirmationEmailSent (ConfirmationEmailSentData "alice@x")
  ]


spec :: Spec
spec = do
  describe "userRegDriverConfig + toMultiDecider on the canonical chain" $ do
    let mdec = toMultiDecider userReg userRegDriverConfig
        sdec = toDecider userReg

    it "decide on StartRegistration returns the 2-element event list" $
      decide mdec startCmd (PotentialCustomer, emptyRegs) `shouldBe`
        multiEventChunk

    it "applyEvents round-trips the same 2-event chunk" $
      case applyEvents userReg (PotentialCustomer, emptyRegs) multiEventChunk of
        Just (s, regs) -> do
          s `shouldBe` RequiresConfirmation
          (regs ! #email, regs ! #confirmCode, regs ! #registeredAt)
            `shouldBe` ("alice@x", "Z9F4", t 0)
        Nothing -> expectationFailure "applyEvents returned Nothing"

    it "underlying letter FST behavior is unchanged via toDecider" $ do
      -- The single-event lift produces RegistrationStarted from
      -- StartRegistration and lands at the intermediate Registering
      -- vertex.
      decide sdec startCmd (PotentialCustomer, emptyRegs) `shouldBe`
        [ RegistrationStarted (RegistrationStartedData "alice@x" "Z9F4" (t 0)) ]
      -- Registering then advances on Continue, reading #email from
      -- the registers populated by step 1. Set up registers via the
      -- multi-event façade's evolve, then assert the singleton.
      let s0 = (PotentialCustomer, emptyRegs)
          s1 = evolve mdec s0
                 (RegistrationStarted
                   (RegistrationStartedData "alice@x" "Z9F4" (t 0)))
      decide sdec Continue s1 `shouldBe`
        [ ConfirmationEmailSent (ConfirmationEmailSentData "alice@x") ]
