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
-- unsatisfiable, which needs the two reads of @#appCreditScore@ (one in
-- each half) to share a single SBV variable. EP-41 supplies the
-- comparison constructor that half of the original pending reason asked
-- for; the remaining half is the per-slot /memoization sibling/: the
-- translator allocates a fresh @reg/appCreditScore@ per occurrence and
-- SBV does not alias same-named 'Data.SBV.free' variables, so the two
-- reads stay independent and the conjunction is reported satisfiable.
module Jitsurei.LoanApplicationSymbolicSpec (spec) where

import Test.Hspec

import Jitsurei.LoanApplication
import Keiki.Symbolic


spec :: Spec
spec = do
  describe "isSingleValuedSym (withSymPred loanApplication)" $
    it "answers True (the v2 retrospective gate)" $ do
      pendingWith
        "Needs the per-slot memoization sibling: approvalGuard ∧ PNot \
        \approvalGuard is mutex only if the two reads of #appCreditScore \
        \share one SBV variable, but the translator allocates a fresh \
        \reg/appCreditScore per occurrence and SBV does not alias \
        \same-named `free` vars. EP-41 supplied the comparison \
        \constructor (PCmp); the shared-variable half remains."
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
