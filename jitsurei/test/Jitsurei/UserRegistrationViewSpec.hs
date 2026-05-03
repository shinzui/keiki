{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}

module Jitsurei.UserRegistrationViewSpec (spec) where

import Data.Proxy (Proxy (..))
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

import Keiki.Core (RegFile (..))
import Jitsurei.UserRegistration


-- | UTC-time fixture: every test moment is on the same day, offset
-- by N seconds.
t :: Integer -> UTCTime
t s = UTCTime (fromGregorian 2026 5 2) (secondsToDiffTime s)


-- | Hand-build a 'UserRegRegs' register file with all five slots
-- bound. This avoids 'emptyRegs' (which pre-fills every slot with a
-- deferred @"uninit: <slot>"@ error so reading would crash) for tests
-- that exercise the projection's slot reads.
mkRegs
  :: Email -> ConfirmationCode -> UTCTime -> UTCTime -> UTCTime
  -> RegFile UserRegRegs
mkRegs email_ code regAt confAt delAt =
    RCons (Proxy @"email")        email_
  $ RCons (Proxy @"confirmCode")  code
  $ RCons (Proxy @"registeredAt") regAt
  $ RCons (Proxy @"confirmedAt")  confAt
  $ RCons (Proxy @"deletedAt")    delAt
  $ RNil


spec :: Spec
spec = describe "UserView projection" $ do
  let regs = mkRegs "alice@x" "Z9F4" (t 0) (t 100) (t 200)

  it "projects PotentialCustomer to the empty PotentialCustomerV" $
    userView SPotentialCustomer regs `shouldBe` PotentialCustomerV

  it "projects Registering to the empty RegisteringV" $
    userView SRegistering regs `shouldBe` RegisteringV

  it "projects RequiresConfirmation to RCV with email + confirmCode" $
    userView SRequiresConfirmation regs
      `shouldBe` RequiresConfirmationV
                   { rcEmail       = "alice@x"
                   , rcConfirmCode = "Z9F4"
                   }

  it "projects Confirmed to ConfirmedV with email + confirmedAt" $
    userView SConfirmed regs
      `shouldBe` ConfirmedV
                   { cEmail       = "alice@x"
                   , cConfirmedAt = t 100
                   }

  it "projects Deleted to DeletedV with email + deletedAt" $
    userView SDeleted regs
      `shouldBe` DeletedV
                   { dEmail     = "alice@x"
                   , dDeletedAt = t 200
                   }

  it "ignores slots not named in the spec" $ do
    -- Confirmed's spec is ["email", "confirmedAt"]; the projection
    -- should not read registeredAt or deletedAt, so binding those
    -- two slots to bottom must not crash the projection.
    let partial =
            RCons (Proxy @"email")        "alice@x"
          $ RCons (Proxy @"confirmCode")  (error "unread: confirmCode")
          $ RCons (Proxy @"registeredAt") (error "unread: registeredAt")
          $ RCons (Proxy @"confirmedAt")  (t 100)
          $ RCons (Proxy @"deletedAt")    (error "unread: deletedAt")
          $ RNil
    userView SConfirmed partial
      `shouldBe` ConfirmedV "alice@x" (t 100)
