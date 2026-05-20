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
-- loanApplication) == True@ — is now /proven/ (no longer pending).
-- Single-valuedness at @UnderReview@ requires proving
-- @approvalGuard ∧ ¬approvalGuard@ unsatisfiable, which needed two
-- things, both now delivered (this was MasterPlan 12's integration
-- capstone):
--
--   * EP-42 (per-slot memoization): the two reads of @#appCreditScore@
--     (one in each half of the self-mutex) share a single SBV variable.
--   * EP-43 (structural arithmetic): @approvalGuard@'s cap conjunct
--     @appRequestedAmount <= appCreditScore * 1000@ is now a structural
--     'Keiki.Core.TArith' (built with @tmul@) the solver reads, not an
--     opaque 'Keiki.Core.TApp1' that minted an independent fresh
--     variable per occurrence.
--
-- With both, the two copies of @approvalGuard@ range over the same
-- variables and the conjunction is unsatisfiable, so the gate proves
-- @True@.
module Jitsurei.LoanApplicationSymbolicSpec (spec) where

import Test.Hspec

import Jitsurei.LoanApplication
import Keiki.Symbolic


spec :: Spec
spec = do
  describe "isSingleValuedSym (withSymPred loanApplication)" $
    it "answers True (the v2 retrospective gate)" $
      -- Proven as of EP-43 (composed with EP-42): memoization shares the
      -- two reads of #appCreditScore across the self-mutex, and the cap
      -- is now a structural tmul, so approvalGuard ∧ ¬approvalGuard is
      -- unsatisfiable. This was MasterPlan 12's integration capstone.
      isSingleValuedSym (withSymPred loanApplication) `shouldBe` True

  describe "approval edge guard (EP-41 ordering + EP-43 cap)" $
    -- The approval edge out of UnderReview is guarded by
    --   PAnd (PInCtor inCtorContinue) approvalGuard
    -- whose approvalGuard contains PCmp CmpGe #appCreditScore
    -- (lit approvalThresholdScore) (EP-41 ordering) and the cap
    -- PCmp CmpLe #appRequestedAmount (tmul #appCreditScore (lit 1000))
    -- (EP-43 structural arithmetic). symSatExt therefore returns a
    -- witness whose credit score is >= the threshold AND whose requested
    -- amount is within the structural cap — so the /whole/ evalPred holds
    -- on the witness. Before EP-41 the threshold hid in an opaque TApp1
    -- (score unconstrained); before EP-43 the cap hid in another opaque
    -- TApp1, so the full evalPred could not be asserted.
    it "approval edge witness satisfies the whole guard (score + cap)" $
      case edgesOut loanApplication UnderReview of
        []        -> expectationFailure "UnderReview has no outgoing edges"
        (e : _)   -> case symSatExt (guard e) of
          Nothing          -> expectationFailure "approval edge guard reported unsat"
          Just (regs, cmd) -> do
            (regs ! (#appCreditScore :: Index LoanAppRegs Int)
               >= approvalThresholdScore) `shouldBe` True
            evalPred (guard e) regs cmd `shouldBe` True
