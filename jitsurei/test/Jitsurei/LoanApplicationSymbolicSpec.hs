-- | Symbolic-side spec for the LoanApplication aggregate.
--
-- EP-41 migrated the aggregate's threshold guards from the opaque
-- @PEq (TApp1 (>= n) …) (lit True)@ / @TApp2 (<=)@ form to the
-- structural ordering guard 'Keiki.Core.PCmp', so "credit score >= 650"
-- and friends are now visible to the SBV translator. The ordering-win
-- assertion below ('symSatExt' on the approval edge guard yields a
-- witness whose credit score is >= the approval threshold) exercises
-- that directly; before EP-41 the same witness carried an unconstrained
-- score (the comparison hid inside an opaque 'TApp1').
--
-- The retrospective gate — @isSingleValuedSym (withSymPred
-- loanApplication) == True@ — remains /pending/. Single-valuedness at
-- @UnderReview@ requires proving @approvalGuard ∧ ¬approvalGuard@
-- unsatisfiable. As of EP-42 (per-slot memoization) the two reads of
-- @#appCreditScore@ (one in each half) /do/ now share a single SBV
-- variable — that half of the original pending reason is closed. The
-- remaining blocker is the /arithmetic-terms sibling/ (EP-43):
-- @approvalGuard@'s cap conjunct
-- @appRequestedAmount <= maxApprovalForScore appCreditScore@ still
-- routes @maxApprovalForScore@ through an opaque 'Keiki.Core.TApp1',
-- which the memoizing translator deliberately does /not/ cache (opaque
-- functions have no 'Eq'). So the two copies of that 'TApp1' (one in
-- @approvalGuard@, one in @PNot approvalGuard@) still mint independent
-- fresh variables and the self-mutex stays satisfiable until the
-- 'TApp1' becomes structural arithmetic. Un-pending this gate is
-- MasterPlan 12's integration capstone, owned by EP-43.
module Jitsurei.LoanApplicationSymbolicSpec (spec) where

import Test.Hspec

import Jitsurei.LoanApplication
import Keiki.Symbolic


spec :: Spec
spec = do
  describe "isSingleValuedSym (withSymPred loanApplication)" $
    it "answers True (the v2 retrospective gate)" $ do
      pendingWith
        "Needs the arithmetic-terms sibling (EP-43): memoization (EP-42) \
        \now shares register reads, but the cap conjunct's \
        \maxApprovalForScore is still an opaque TApp1 that mints a fresh \
        \variable per occurrence, so approvalGuard ∧ PNot approvalGuard \
        \stays satisfiable via the cap. The un-pend is MasterPlan 12's \
        \integration capstone, owned by EP-43."
      isSingleValuedSym (withSymPred loanApplication) `shouldBe` True

  describe "ordering-guard win (EP-41)" $
    -- The approval edge out of UnderReview is guarded by
    --   PAnd (PInCtor inCtorContinue) approvalGuard
    -- whose approvalGuard now contains PCmp CmpGe #appCreditScore
    -- (lit approvalThresholdScore). symSatExt therefore returns a
    -- witness whose credit score is actually >= the threshold (a single
    -- read of #appCreditScore, so no memoization is needed). Before
    -- EP-41 the threshold lived inside an opaque TApp1 and the witness
    -- score was unconstrained (defaulted to 0). We assert only the
    -- credit-score bound: the cap conjunct (requestedAmount <=
    -- maxApprovalForScore creditScore) still routes its right-hand side
    -- through an opaque TApp1, so the full evalPred need not hold on the
    -- witness (that is the arithmetic-terms sibling's job).
    it "approval edge guard witness has credit score >= threshold" $
      case edgesOut loanApplication UnderReview of
        []        -> expectationFailure "UnderReview has no outgoing edges"
        (e : _)   -> case symSatExt (guard e) of
          Nothing          -> expectationFailure "approval edge guard reported unsat"
          Just (regs, _cmd) ->
            (regs ! (#appCreditScore :: Index LoanAppRegs Int)
               >= approvalThresholdScore) `shouldBe` True
