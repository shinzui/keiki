module Keiki.AcceptorSpec (spec) where

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

import Keiki.Acceptor
import Keiki.Core (initialRegs, isFinal, reconstitute)
import Keiki.Examples.EmailDelivery
  ( EmailEvent (..)
  , EmailSentData (..)
  , emailDelivery
  )
import Keiki.Examples.UserRegistration
  ( AccountConfirmedData (..)
  , ConfirmAccountData (..)
  , FulfillGDPRRequestData (..)
  , StartRegistrationData (..)
  , UserCmd (..)
  , UserEvent (..)
  , Vertex (..)
  , userReg
  )


-- | A trivial UTC-time fixture: every test moment is on the same day,
-- offset by N seconds.
t :: Integer -> UTCTime
t s = UTCTime (fromGregorian 2026 5 1) (secondsToDiffTime s)


-- | The canonical four-step command sequence on 'userReg' that lands
-- in the final 'Deleted' vertex.
--
--   PotentialCustomer    --StartRegistration->  Registering
--   Registering          --Continue->           RequiresConfirmation
--   RequiresConfirmation --ConfirmAccount->     Confirmed
--   Confirmed            --FulfillGDPRRequest-> Deleted
--
-- The 'ConfirmAccount' code matches the code stored at registration,
-- so the @PEq@ guard on the confirmation edge is satisfied.
canonicalUserCmds :: [UserCmd]
canonicalUserCmds =
  [ StartRegistration  (StartRegistrationData  "alice@x" "Z9F4" (t 0))
  , Continue
  , ConfirmAccount     (ConfirmAccountData     "Z9F4"           (t 100))
  , FulfillGDPRRequest (FulfillGDPRRequestData                  (t 200))
  ]


-- | The canonical event log on 'emailDelivery' that lands in the
-- terminal 'EmailSentVertex'.
canonicalEmailLog :: [EmailEvent]
canonicalEmailLog =
  [ EmailSent (EmailSentData "alice@x" "Welcome" (t 0)) ]


spec :: Spec
spec = do
  describe "inputAcceptor userReg" $ do
    it "accepts the canonical command sequence" $
      accepts (inputAcceptor userReg) canonicalUserCmds
        `shouldBe` True

    it "rejects ConfirmAccount from PotentialCustomer" $
      accepts (inputAcceptor userReg)
              [ConfirmAccount (ConfirmAccountData "Z9F4" (t 0))]
        `shouldBe` False

  describe "outputAcceptor emailDelivery" $ do
    it "accepts the canonical event log" $
      accepts (outputAcceptor emailDelivery) canonicalEmailLog
        `shouldBe` True

    it "rejects an event that no edge from PotentialCustomer produces" $ do
      -- userReg's only outgoing edge from PotentialCustomer produces
      -- 'RegistrationStarted'; 'AccountConfirmed' has no matching
      -- inverse, so applyEvent returns Nothing on the first step.
      let badLog =
            [AccountConfirmed
              (AccountConfirmedData "alice@x" "Z9F4" (t 0))]
      accepts (outputAcceptor userReg) badLog `shouldBe` False

    it "agrees with reconstitute on the canonical log" $
      fmap fst (runAcceptor (outputAcceptor emailDelivery) canonicalEmailLog)
        `shouldBe`
          fmap fst (reconstitute emailDelivery canonicalEmailLog)

  describe "aIsFinal" $ do
    it "matches isFinal on userReg under fst" $ do
      let a = inputAcceptor userReg
      aIsFinal a (Deleted,           initialRegs userReg) `shouldBe` True
      aIsFinal a (Confirmed,         initialRegs userReg) `shouldBe` False
      aIsFinal a (PotentialCustomer, initialRegs userReg) `shouldBe` False
      -- And the same predicate on the bare vertex.
      isFinal userReg Deleted   `shouldBe` True
      isFinal userReg Confirmed `shouldBe` False
