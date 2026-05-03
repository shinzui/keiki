-- | EP-34 M3: 'toMultiDecider' end-to-end test for LoanApplication.
-- Drives a single 'RecordEmploymentCheck' command on a register
-- snapshot where every other threshold is already met; the multi-
-- decider then chains through 'CollectingDocuments → UnderReview'
-- (silent) and 'UnderReview → Approved' (Continue with
-- approvalGuard) in the same step, returning a 2-event list:
--
--   [EmploymentChecked, ApplicationApproved]
--
-- The silent advance contributes no event of its own (the
-- @CollectingDocuments → UnderReview@ edge has @output = Nothing@);
-- only the final approval is observable as a public event.
module Jitsurei.LoanApplicationMultiSpec (spec) where

import Data.Proxy (Proxy (..))
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

import Keiki.Core (RegFile (..))
import Keiki.Decider (Decider (..), toDecider, toMultiDecider)
import Jitsurei.LoanApplication


t :: Integer -> UTCTime
t s = UTCTime (fromGregorian 2026 5 3) (secondsToDiffTime s)


epoch :: UTCTime
epoch = read "1970-01-01 00:00:00 UTC"


-- | Hand-build a register snapshot at 'CollectingDocuments' where
-- every threshold *except* employment is already met. Issuing
-- 'RecordEmploymentCheck' on this state with @verified = True@
-- tips the threshold; the multi-decider drives through to
-- 'Approved' in one decide call.
preApprovalRegs :: RegFile LoanAppRegs
preApprovalRegs =
    RCons (Proxy @"appApplicantId")        "alice"
  $ RCons (Proxy @"appRequestedAmount")    250_000
  $ RCons (Proxy @"appPurpose")            "home"
  $ RCons (Proxy @"appIncomeDocCount")     2
  $ RCons (Proxy @"appIdDocCount")         1
  $ RCons (Proxy @"appCreditScore")        720
  $ RCons (Proxy @"appEmploymentVerified") False
  $ RCons (Proxy @"appDecidedAt")          (error "unread: appDecidedAt")
  $ RCons (Proxy @"appWithdrawnAt")        (error "unread: appWithdrawnAt")
  $ RCons (Proxy @"appDeclineReason")      (error "unread: appDeclineReason")
  $ RNil


recordEmploymentCmd :: LoanCmd
recordEmploymentCmd = RecordEmploymentCheck
  (RecordEmploymentCheckData True (t 50))


-- | The expected 2-event chunk produced by the multi-decider on
-- 'recordEmploymentCmd'.
expectedChunk :: [LoanEvent]
expectedChunk =
  [ EmploymentChecked   (EmploymentCheckedData   True   (t 50))
  , ApplicationApproved (ApplicationApprovedData "alice" 250_000 720 epoch)
  ]


spec :: Spec
spec = do
  let mdec = toMultiDecider loanApplication loanApplicationDriverConfig
      sdec = toDecider      loanApplication

  describe "loanApplicationDriverConfig + toMultiDecider" $ do
    it "decide on RecordEmploymentCheck returns the 2-event chain" $
      decide mdec recordEmploymentCmd
             (CollectingDocuments, preApprovalRegs)
        `shouldBe` expectedChunk

    it "underlying letter FST behavior is unchanged via toDecider" $ do
      -- Single-event lift: only the EmploymentChecked event fires
      -- in the first step; the multi-event façade chains the rest.
      decide sdec recordEmploymentCmd
             (CollectingDocuments, preApprovalRegs)
        `shouldBe`
          [ EmploymentChecked (EmploymentCheckedData True (t 50)) ]
