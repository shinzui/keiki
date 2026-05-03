{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}

-- | EP-34 M2: per-vertex View projection tests for the
-- LoanApplication aggregate. Builds a fully-populated 'LoanAppRegs'
-- by hand and asserts that 'loanAppView' produces the right per-
-- vertex record at every vertex.
module Jitsurei.LoanApplicationViewSpec (spec) where

import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

import Keiki.Core (RegFile (..))
import Jitsurei.LoanApplication


t :: Integer -> UTCTime
t s = UTCTime (fromGregorian 2026 5 3) (secondsToDiffTime s)


-- | Hand-build a fully-populated 'LoanAppRegs'. Tests of vertex
-- projections that read only a subset of slots can use this and
-- trust that uninitialised-slot crashes will not occur.
mkRegs
  :: Text       -- ^ appApplicantId
  -> Money      -- ^ appRequestedAmount
  -> Text       -- ^ appPurpose
  -> Int        -- ^ appIncomeDocCount
  -> Int        -- ^ appIdDocCount
  -> Int        -- ^ appCreditScore
  -> Bool       -- ^ appEmploymentVerified
  -> UTCTime    -- ^ appDecidedAt
  -> UTCTime    -- ^ appWithdrawnAt
  -> Text       -- ^ appDeclineReason
  -> RegFile LoanAppRegs
mkRegs aid amt prp inc idc score emp dec wd reason =
    RCons (Proxy @"appApplicantId")        aid
  $ RCons (Proxy @"appRequestedAmount")    amt
  $ RCons (Proxy @"appPurpose")            prp
  $ RCons (Proxy @"appIncomeDocCount")     inc
  $ RCons (Proxy @"appIdDocCount")         idc
  $ RCons (Proxy @"appCreditScore")        score
  $ RCons (Proxy @"appEmploymentVerified") emp
  $ RCons (Proxy @"appDecidedAt")          dec
  $ RCons (Proxy @"appWithdrawnAt")        wd
  $ RCons (Proxy @"appDeclineReason")      reason
  $ RNil


spec :: Spec
spec = describe "LoanAppView projection" $ do
  let regs = mkRegs "alice" 250_000 "home" 2 1 720 True (t 100) (t 50) "n/a"

  it "projects Intake to IntakeV with appApplicantId" $
    loanAppView SIntake regs
      `shouldBe` IntakeV { iAppApplicantId = "alice" }

  it "projects CollectingDocuments to CDV with five slots" $
    loanAppView SCollectingDocuments regs
      `shouldBe` CollectingDocumentsV
                   { cdAppApplicantId      = "alice"
                   , cdAppRequestedAmount  = 250_000
                   , cdAppPurpose          = "home"
                   , cdAppIncomeDocCount   = 2
                   , cdAppIdDocCount       = 1
                   }

  it "projects UnderReview to URV with five slots" $
    loanAppView SUnderReview regs
      `shouldBe` UnderReviewV
                   { urAppApplicantId        = "alice"
                   , urAppRequestedAmount    = 250_000
                   , urAppPurpose            = "home"
                   , urAppCreditScore        = 720
                   , urAppEmploymentVerified = True
                   }

  it "projects Approved to AV with four slots" $
    loanAppView SApproved regs
      `shouldBe` ApprovedV
                   { aAppApplicantId     = "alice"
                   , aAppRequestedAmount = 250_000
                   , aAppCreditScore     = 720
                   , aAppDecidedAt       = t 100
                   }

  it "projects Declined to DV with three slots" $
    loanAppView SDeclined regs
      `shouldBe` DeclinedV
                   { dAppApplicantId    = "alice"
                   , dAppDeclineReason  = "n/a"
                   , dAppDecidedAt      = t 100
                   }

  it "projects Withdrawn to WV with two slots" $
    loanAppView SWithdrawn regs
      `shouldBe` WithdrawnV
                   { wAppApplicantId  = "alice"
                   , wAppWithdrawnAt  = t 50
                   }

  it "ignores slots outside the projection's spec" $ do
    -- Approved's spec is appApplicantId / appRequestedAmount /
    -- appCreditScore / appDecidedAt; binding the *other* slots to
    -- bottom must not crash the projection.
    let partial =
            RCons (Proxy @"appApplicantId")        "alice"
          $ RCons (Proxy @"appRequestedAmount")    250_000
          $ RCons (Proxy @"appPurpose")            (error "unread: appPurpose")
          $ RCons (Proxy @"appIncomeDocCount")     (error "unread: appIncomeDocCount")
          $ RCons (Proxy @"appIdDocCount")         (error "unread: appIdDocCount")
          $ RCons (Proxy @"appCreditScore")        720
          $ RCons (Proxy @"appEmploymentVerified") (error "unread: appEmploymentVerified")
          $ RCons (Proxy @"appDecidedAt")          (t 100)
          $ RCons (Proxy @"appWithdrawnAt")        (error "unread: appWithdrawnAt")
          $ RCons (Proxy @"appDeclineReason")      (error "unread: appDeclineReason")
          $ RNil
    loanAppView SApproved partial
      `shouldBe` ApprovedV "alice" 250_000 720 (t 100)
