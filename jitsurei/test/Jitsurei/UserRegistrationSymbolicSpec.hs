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
import Jitsurei.UserRegistration
import Keiki.Symbolic
import Test.Hspec

spec :: Spec
spec = do
  describe "isSingleValuedSym (withSymPred userReg)" $ do
    it "answers True (the v2 retrospective gate)" $
      isSingleValuedSym (withSymPred userReg) `shouldBe` True

  describe "sat over the User Registration aggregate" $ do
    -- Since EP-44 'sat' returns a real witness; each satisfiable case
    -- forces it through 'models' (before EP-44 the placeholder witness
    -- crashed when 'models' inspected it). The predicates pin the input
    -- constructor so 'evalPred' on the reconstructed command is total.
    it "satisfiable: PInCtor inCtorConfirm (witness satisfies models)" $ do
      let p = PInCtor inCtorConfirm :: HsPred UserRegRegs UserCmd
      isJust (sat (SymPred p)) `shouldBe` True
      case sat (SymPred p) of
        Nothing -> expectationFailure "expected satisfiable"
        Just w -> models (SymPred p) w `shouldBe` True

    it "satisfiable: isConfirm AND confirmCode == \"abc123\" (witness satisfies models)" $ do
      let p =
            PAnd
              (PInCtor inCtorConfirm)
              ((inpConfirm #confirmCode) .== lit "abc123") ::
              HsPred UserRegRegs UserCmd
      isJust (sat (SymPred p)) `shouldBe` True
      case sat (SymPred p) of
        Nothing -> expectationFailure "expected satisfiable"
        Just w -> models (SymPred p) w `shouldBe` True

    it "unsatisfiable: PInCtor inCtorConfirm AND PInCtor inCtorResend" $ do
      let p =
            PAnd (PInCtor inCtorConfirm) (PInCtor inCtorResend) ::
              HsPred UserRegRegs UserCmd
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
      case edgesOut userReg RequiresConfirmation of
        [] -> expectationFailure "RequiresConfirmation has no outgoing edges"
        edge : _ -> do
          let g = guard edge
          case symSatExt g of
            Nothing ->
              expectationFailure
                "ConfirmAccount edge guard reported unsat"
            Just (regs, cmd) ->
              evalPred g regs cmd `shouldBe` True

    -- A standalone PEq predicate with a literal: confirms the
    -- witness extractor can recover both an InCtor field value and
    -- the matching register slot from a model where the solver was
    -- given freedom to pick.
    it "isConfirm AND eq lit: witness models the predicate" $ do
      let p =
            PAnd
              (PInCtor inCtorConfirm)
              ((inpConfirm #confirmCode) .== lit "abc123") ::
              HsPred UserRegRegs UserCmd
      case symSatExt p of
        Nothing -> expectationFailure "predicate reported unsat"
        Just (regs, cmd) ->
          evalPred p regs cmd `shouldBe` True

    -- Negative case: an unsatisfiable predicate produces Nothing.
    it "constructor mutex returns Nothing" $ do
      let p =
            PAnd (PInCtor inCtorConfirm) (PInCtor inCtorResend) ::
              HsPred UserRegRegs UserCmd
      isNothing (symSatExt p) `shouldBe` True

-- (EP-19 M7 retired the no-payload 'Continue' constructor that
-- previously demonstrated the singleton-InCtor witness path; the
-- ConfirmAccount edge above already exercises the symbolic
-- witness extractor on a payload-bearing constructor.)
