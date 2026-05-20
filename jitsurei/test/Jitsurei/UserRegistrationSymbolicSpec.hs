-- | Symbolic-side spec for the User Registration aggregate. Asserts
-- the v2 retrospective gate: 'isSingleValuedSym' answers @True@ on
-- the 'userReg' transducer once its guards are lifted to 'SymPred',
-- proved symbolically by z3. Adds 'sat'-based smoke checks on a
-- non-trivial predicate over the User Registration register file.
-- EP-9 adds 'symSatExt' round-trip tests: sat → concrete witness →
-- 'evalPred' agrees. Since EP-44, 'Keiki.Core.sat' on 'SymPred' /is/
-- the real witness ('symSatExt'), so the smoke checks below can also
-- force the returned witness (see M2).
module Jitsurei.UserRegistrationSymbolicSpec (spec) where

import Data.Maybe (isJust, isNothing)
import Test.Hspec

import Jitsurei.UserRegistration
import Keiki.Symbolic


spec :: Spec
spec = do
  describe "isSingleValuedSym (withSymPred userReg)" $ do
    it "answers True (the v2 retrospective gate)" $
      isSingleValuedSym (withSymPred userReg) `shouldBe` True

  describe "sat over the User Registration aggregate" $ do
    it "satisfiable: PInCtor inCtorConfirm" $ do
      let p = PInCtor inCtorConfirm :: HsPred UserRegRegs UserCmd
      isJust (sat (SymPred p)) `shouldBe` True

    it "satisfiable: PEq (inpConfirm #confirmCode) (lit \"abc123\")" $ do
      let p = (inpConfirm #confirmCode) .== lit "abc123"
              :: HsPred UserRegRegs UserCmd
      isJust (sat (SymPred p)) `shouldBe` True

    it "unsatisfiable: PInCtor inCtorConfirm AND PInCtor inCtorResend" $ do
      let p = PAnd (PInCtor inCtorConfirm) (PInCtor inCtorResend)
              :: HsPred UserRegRegs UserCmd
      isJust (sat (SymPred p)) `shouldBe` False

  describe "symSatExt round-trip (EP-9)" $ do
    -- The RequiresConfirmation/ConfirmAccount edge's guard is
    --   PAnd isConfirm (inpConfirm #confirmCode .== proj #confirmCode)
    -- which constrains the input constructor to ConfirmAccount and
    -- ties the input's confirmCode field to the register's
    -- confirmCode slot. The solver picks any pair satisfying both;
    -- the witness extractor reads the model and reconstructs a
    -- concrete (RegFile, UserCmd). evalPred on the witness must
    -- agree.
    it "ConfirmAccount edge guard: sat → witness → models agrees" $ do
      let g = guard (head (edgesOut userReg RequiresConfirmation))
      case symSatExt g of
        Nothing -> expectationFailure
                     "ConfirmAccount edge guard reported unsat"
        Just (regs, cmd) ->
          evalPred g regs cmd `shouldBe` True

    -- A standalone PEq predicate with a literal: confirms the
    -- witness extractor can recover both an InCtor field value and
    -- the matching register slot from a model where the solver was
    -- given freedom to pick.
    it "isConfirm AND eq lit: witness models the predicate" $ do
      let p = PAnd (PInCtor inCtorConfirm)
                   ((inpConfirm #confirmCode) .== lit "abc123")
              :: HsPred UserRegRegs UserCmd
      case symSatExt p of
        Nothing -> expectationFailure "predicate reported unsat"
        Just (regs, cmd) ->
          evalPred p regs cmd `shouldBe` True

    -- Negative case: an unsatisfiable predicate produces Nothing.
    it "constructor mutex returns Nothing" $ do
      let p = PAnd (PInCtor inCtorConfirm) (PInCtor inCtorResend)
              :: HsPred UserRegRegs UserCmd
      isNothing (symSatExt p) `shouldBe` True

    -- (EP-19 M7 retired the no-payload 'Continue' constructor that
    -- previously demonstrated the singleton-InCtor witness path; the
    -- ConfirmAccount edge above already exercises the symbolic
    -- witness extractor on a payload-bearing constructor.)
