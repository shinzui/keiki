-- | EP-34 M5: end-to-end smoke test for the LoanWorkflow
-- composition. Demonstrates the cross-context flow
--
--   LoanCmd  ⇒  LoanApplication.ApplicationApproved
--           ⇒  CoreBankingSync.LoanCreatedIn
--           ⇒  CoreBankingSync.SyncToLegacyRequested
--           ⇒  (legacy callback channel)
--           ⇒  CoreBankingSync.LegacyAssignmentCommanded
--           ⇒  Loan.AssignLegacyLoanId
--           ⇒  Loan.LegacyLoanIdAssigned
--
-- 'Keiki.Composition.compose' is lockstep, so the natural async
-- creation flow above cannot be a single composite firing.
-- This spec drives each cross-context jump separately, mirroring
-- what the runtime adapter does, and asserts that the *adapter
-- functions* and the *individual aggregates* together produce the
-- expected end-to-end output. The 'loanWorkflow' composite itself
-- exists for the type-level wiring it expresses; see the module
-- haddock.
module Jitsurei.LoanWorkflowSpec (spec) where

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

import Keiki.Core
import Keiki.Decider (Decider (..), toMultiDecider)

import Jitsurei.CoreBankingSync
import Jitsurei.Loan
import Jitsurei.LoanApplication
import Jitsurei.LoanWorkflow


t :: Integer -> UTCTime
t s = UTCTime (fromGregorian 2026 5 3) (secondsToDiffTime s)


-- | A 5-event log that drives 'loanApplication' through evidence
-- collection so the registers sit at 'CollectingDocuments' with
-- every threshold *except* employment satisfied. Used as the pre-
-- state for the threshold-tipping 'RecordEmploymentCheck' command.
preApprovalLog :: [LoanEvent]
preApprovalLog =
  [ ApplicationStarted     (ApplicationStartedData     "alice" 250_000 "home" (t 0))
  , IncomeDocumentReceived (IncomeDocumentReceivedData "i1" (t 10))
  , IncomeDocumentReceived (IncomeDocumentReceivedData "i2" (t 20))
  , IdDocumentReceived     (IdDocumentReceivedData     "id1" (t 30))
  , CreditScoreRecorded    (CreditScoreRecordedData    720 (t 40))
  ]


-- | Drive 'loanApplication's multi-decider with the threshold-
-- tipping 'RecordEmploymentCheck' command and observe the 2-event
-- chain @[EmploymentChecked, ApplicationApproved]@.
recordEmploymentTipsApproval :: [LoanEvent]
recordEmploymentTipsApproval =
  let mdec   = toMultiDecider loanApplication loanApplicationDriverConfig
      preSt  = case reconstitute loanApplication preApprovalLog of
                 Just s  -> s
                 Nothing -> error "preApprovalLog reconstitute failed"
      cmd    = RecordEmploymentCheck
                 (RecordEmploymentCheckData True (t 50))
  in decide mdec cmd preSt


spec :: Spec
spec = do

  describe "Stage 1: LoanApplication ⇒ CoreBankingSync via loanEventToSyncInput" $ do
    it "ApplicationApproved adapts to LoanCreatedIn" $ do
      let appApproved = ApplicationApproved
            (ApplicationApprovedData "alice" 250_000 720 (t 100))
      case loanEventToSyncInput appApproved of
        Just (LoanCreatedIn d) -> do
          d.applicantId `shouldBe` "alice"
          d.principal   `shouldBe` 250_000
        _ -> expectationFailure
               "loanEventToSyncInput rejected ApplicationApproved"

    it "non-approval LoanEvents adapt to Nothing" $ do
      let started = ApplicationStarted
            (ApplicationStartedData "alice" 250_000 "home" (t 0))
      loanEventToSyncInput started `shouldBe` Nothing

    it "LoanCreatedIn drives CoreBankingSync from SyncIdle to SyncRequested" $ do
      let appApproved = ApplicationApproved
            (ApplicationApprovedData "alice" 250_000 720 (t 100))
      case loanEventToSyncInput appApproved of
        Just inp ->
          case step coreBankingSync (initial coreBankingSync, initialRegs coreBankingSync) inp of
            Just (SyncRequested, _, Just (SyncToLegacyRequested d)) -> do
              d.loanId      `shouldBe` "loan-alice"
              d.applicantId `shouldBe` "alice"
              d.principal   `shouldBe` 250_000
            Just _  -> expectationFailure
                         "step on LoanCreatedIn produced unexpected output"
            Nothing -> expectationFailure
                         "step on LoanCreatedIn returned Nothing"
        Nothing -> expectationFailure
                     "loanEventToSyncInput unexpectedly returned Nothing"

  describe "Stage 2: CoreBankingSync ⇒ Loan via syncOutputToLoanCmd" $ do
    it "SyncToLegacyRequested adapts to Nothing (audit only)" $
      syncOutputToLoanCmd (SyncToLegacyRequested
        (SyncToLegacyRequestedData "loan-alice" "alice" 250_000))
        `shouldBe` Nothing

    it "LegacyAssignmentCommanded unwraps to a LoanCmd'" $
      syncOutputToLoanCmd (LegacyAssignmentCommanded
        (LegacyAssignmentCommandedData
          (AssignLegacyLoanId
            (AssignLegacyLoanIdData "loan-alice" "LEG-42"))))
        `shouldBe` Just (AssignLegacyLoanId
          (AssignLegacyLoanIdData "loan-alice" "LEG-42"))

  describe "End-to-end: LoanCmd ⇒ approval ⇒ legacy callback ⇒ LegacyLoanIdAssigned" $
    it "drives the full async creation flow via the adapter functions" $ do
      -- Stage 1: drive LoanApplication's multi-decider with the
      -- threshold-tipping RecordEmploymentCheck. The chain
      -- produces [EmploymentChecked, ApplicationApproved].
      let events1 = recordEmploymentTipsApproval
      length events1 `shouldBe` 2

      -- Stage 2: simulate the runtime feeding ApplicationApproved
      -- to CoreBankingSync via the adapter. Land at SyncRequested
      -- with the audit emit.
      let appApproved = case events1 of
            [_, ev] -> ev
            _       -> error "stage 1 did not produce 2 events"
      Just syncInput <- pure (loanEventToSyncInput appApproved)
      Just (sync1State, sync1Regs) <-
        pure (delta coreBankingSync (initial coreBankingSync)
                                    (initialRegs coreBankingSync) syncInput)
      sync1State `shouldBe` SyncRequested

      -- Stage 3: simulate the legacy callback channel delivering
      -- a LegacyCallbackReceivedIn event with the matching loanId.
      -- CoreBankingSync emits LegacyAssignmentCommanded.
      let callback = LegacyCallbackReceivedIn
            (LegacyCallbackReceivedInData "loan-alice" "LEG-42")
      Just (sync2State, _, Just sync2Out) <-
        pure (step coreBankingSync (sync1State, sync1Regs) callback)
      sync2State `shouldBe` SyncSettled

      -- Stage 4: feed the unwrapped LoanCmd' into Loan and observe
      -- the final LegacyLoanIdAssigned event. (Loan must be at
      -- LoanAwaiting first; in practice a CreateLoan command from
      -- the SyncToLegacyRequested audit handler would land it
      -- there. We bootstrap that step directly.)
      Just loanCmd' <- pure (syncOutputToLoanCmd sync2Out)

      let createCmd = CreateLoan (CreateLoanData "loan-alice" "alice" 250_000)
      Just (loan1State, loan1Regs, Just (LoanCreated _)) <-
        pure (step loan (initial loan, initialRegs loan) createCmd)
      loan1State `shouldBe` LoanAwaiting

      -- Final: the AssignLegacyLoanId from CoreBankingSync drives
      -- Loan to LoanLinked and emits LegacyLoanIdAssigned.
      case step loan (loan1State, loan1Regs) loanCmd' of
        Just (LoanLinked, _, Just (LegacyLoanIdAssigned d)) -> do
          d.loanId       `shouldBe` "loan-alice"
          d.legacyLoanId `shouldBe` "LEG-42"
        Just _  -> expectationFailure
                     "final step produced unexpected output"
        Nothing -> expectationFailure
                     "final step returned Nothing"
