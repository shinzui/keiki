-- | Tests for the CoreBankingSync Process aggregate (EP-34 M4).
-- The Process exercises the legacy-call idempotency mechanism:
--
--   1. Happy path: 'LoanCreatedIn' tips the Process into pending,
--      the matching 'LegacyCallbackReceivedIn' commands the
--      'AssignLegacyLoanId' downstream and lands at 'SyncSettled'.
--   2. Idempotent replay: a second 'LegacyCallbackReceivedIn'
--      after settle finds no outgoing edges (terminal vertex);
--      'delta' returns 'Nothing'.
--   3. Mismatched callback: a 'LegacyCallbackReceivedIn' whose
--      loanId differs from the pending loanId fails the
--      'requireEq' guard; 'delta' returns 'Nothing'.
module Jitsurei.CoreBankingSyncSpec (spec) where

import Jitsurei.CoreBankingSync
import Jitsurei.Loan
  ( AssignLegacyLoanIdData (..),
    LoanCmd' (AssignLegacyLoanId),
  )
import Keiki.Core
import Test.Hspec

happyPathInput :: SyncInput
happyPathInput =
  LoanCreatedIn
    (LoanCreatedInData "loan-001" "alice" 250_000)

callbackInput :: SyncInput
callbackInput =
  LegacyCallbackReceivedIn
    (LegacyCallbackReceivedInData "loan-001" "LEG-42")

mismatchedCallback :: SyncInput
mismatchedCallback =
  LegacyCallbackReceivedIn
    (LegacyCallbackReceivedInData "loan-OTHER" "LEG-X")

spec :: Spec
spec = do
  describe "happy path: pending -> settled" $ do
    it "step on LoanCreatedIn emits SyncToLegacyRequested" $
      case step
        coreBankingSync
        (initial coreBankingSync, initialRegs coreBankingSync)
        happyPathInput of
        Just (SyncRequested, _, [SyncToLegacyRequested d]) -> do
          d.loanId `shouldBe` "loan-001"
          d.applicantId `shouldBe` "alice"
          d.principal `shouldBe` 250_000
        Just _ -> expectationFailure "unexpected output payload"
        Nothing -> expectationFailure "step on LoanCreatedIn returned Nothing"

    it "step on LegacyCallbackReceivedIn at SyncRequested emits LegacyAssignmentCommanded" $
      case delta
        coreBankingSync
        (initial coreBankingSync)
        (initialRegs coreBankingSync)
        happyPathInput of
        Just (SyncRequested, regs') ->
          case step coreBankingSync (SyncRequested, regs') callbackInput of
            Just (SyncSettled, _, [LegacyAssignmentCommanded d]) ->
              d.assignment
                `shouldBe` AssignLegacyLoanId (AssignLegacyLoanIdData "loan-001" "LEG-42")
            Just _ -> expectationFailure "unexpected output payload at SyncRequested"
            Nothing -> expectationFailure "step on callback returned Nothing"
        _ -> expectationFailure "first step did not land at SyncRequested"

  describe "idempotent replay: duplicate callback after settle" $
    it "delta on a duplicate LegacyCallbackReceivedIn returns Nothing" $
      case delta
        coreBankingSync
        (initial coreBankingSync)
        (initialRegs coreBankingSync)
        happyPathInput of
        Just (SyncRequested, regs') ->
          case delta coreBankingSync SyncRequested regs' callbackInput of
            Just (SyncSettled, regs'') ->
              -- After settle, the Process is terminal — no outgoing
              -- edges fire even on a second matching callback.
              fmap fst (delta coreBankingSync SyncSettled regs'' callbackInput)
                `shouldBe` Nothing
            _ -> expectationFailure "first callback did not settle"
        _ -> expectationFailure "first step did not land at SyncRequested"

  describe "mismatched callback: requireEq guard fails" $
    it "delta on a callback with a different loanId returns Nothing" $
      case delta
        coreBankingSync
        (initial coreBankingSync)
        (initialRegs coreBankingSync)
        happyPathInput of
        Just (SyncRequested, regs') ->
          fmap fst (delta coreBankingSync SyncRequested regs' mismatchedCallback)
            `shouldBe` Nothing
        _ -> expectationFailure "first step did not land at SyncRequested"
