{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}

module Keiki.Examples.EmailDeliveryViewSpec (spec) where

import Data.Proxy (Proxy (..))
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

import Keiki.Core (RegFile (..))
import Keiki.Examples.EmailDelivery


-- | UTC-time fixture: every test moment is on the same day, offset
-- by N seconds.
t :: Integer -> UTCTime
t s = UTCTime (fromGregorian 2026 5 2) (secondsToDiffTime s)


-- | Hand-build an 'EmailRegs' register file with all three slots
-- bound. Mirrors the pattern in 'UserRegistrationViewSpec'.
mkRegs :: Email -> Subject -> UTCTime -> RegFile EmailRegs
mkRegs recipient_ subject_ sentAt_ =
    RCons (Proxy @"emailRecipient") recipient_
  $ RCons (Proxy @"emailSubject")   subject_
  $ RCons (Proxy @"emailSentAt")    sentAt_
  $ RNil


spec :: Spec
spec = describe "EmailView projection" $ do
  let regs = mkRegs "alice@x" "hello" (t 100)

  it "projects EmailPending to the empty EmailPendingV" $
    emailView SEmailPending regs `shouldBe` EmailPendingV

  it "projects EmailSentVertex to ESVV with all three slots" $
    emailView SEmailSentVertex regs
      `shouldBe` EmailSentVertexV
                   { esvEmailRecipient = "alice@x"
                   , esvEmailSubject   = "hello"
                   , esvEmailSentAt    = t 100
                   }

  it "ignores slots when projecting an empty-vertex view" $ do
    -- EmailPending's spec is []; the projection should not read any
    -- slot, so binding every slot to bottom must not crash.
    let bottomRegs =
            RCons (Proxy @"emailRecipient") (error "unread: emailRecipient")
          $ RCons (Proxy @"emailSubject")   (error "unread: emailSubject")
          $ RCons (Proxy @"emailSentAt")    (error "unread: emailSentAt")
          $ RNil
    emailView SEmailPending bottomRegs `shouldBe` EmailPendingV
