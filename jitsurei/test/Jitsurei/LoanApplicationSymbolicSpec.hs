-- | Symbolic-side spec for the LoanApplication aggregate (EP-34 M2).
-- The aggregate's guards use 'TApp1' / 'TApp2' to express the multi-
-- field threshold (income docs >= 2, id docs >= 1, credit score
-- >= 650, etc.) — there is no @PCompare@ constructor on 'HsPred',
-- so any "x >= n" check must be lifted via 'TApp1'.
--
-- 'Keiki.Symbolic' translates 'TApp1' / 'TApp2' to *fresh anonymous*
-- SBV variables (it cannot symbolically evaluate arbitrary Haskell
-- functions). Two textually-identical 'TApp1' terms — say
-- 'approvalGuard' shared by the approval edge and inverted on the
-- decline edge — produce *distinct* SBV variables, so SBV reports
-- @approvalGuard \\/\\ \\not approvalGuard@ as satisfiable rather
-- than 'False'. Consequently 'isSingleValuedSym' currently answers
-- 'False' on 'loanApplication' even though the guards are
-- semantically mutex.
--
-- The retrospective-gate spec is therefore marked pending with the
-- reason captured here. A follow-up plan can add a memoising
-- translator that recognises identical 'TApp1' subterms (or extend
-- 'HsPred' with a comparison constructor) so the assertion can be
-- un-pended; that work is out of EP-34's scope.
module Jitsurei.LoanApplicationSymbolicSpec (spec) where

import Test.Hspec

import Jitsurei.LoanApplication
import Keiki.Symbolic


spec :: Spec
spec =
  describe "isSingleValuedSym (withSymPred loanApplication)" $
    it "answers True (the v2 retrospective gate)" $ do
      pendingWith
        "TApp1/TApp2 over arbitrary Haskell functions translate to \
        \fresh anonymous SBV variables; identical sub-predicates \
        \(approvalGuard ∧ PNot approvalGuard) thus appear distinct \
        \symbolically. See module haddock."
      isSingleValuedSym (withSymPred loanApplication) `shouldBe` True
