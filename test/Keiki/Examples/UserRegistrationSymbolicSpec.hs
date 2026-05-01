-- | Symbolic-side spec for the User Registration aggregate. Asserts
-- the v2 retrospective gate: 'isSingleValuedSym' answers @True@ on
-- the 'userReg' transducer once its guards are lifted to 'SymPred',
-- proved symbolically by z3. Adds 'symSat'-based smoke checks on a
-- non-trivial predicate over the User Registration register file.
module Keiki.Examples.UserRegistrationSymbolicSpec (spec) where

import Data.Maybe (isJust)
import Test.Hspec

import Keiki.Examples.UserRegistration
import Keiki.Symbolic


spec :: Spec
spec = do
  describe "isSingleValuedSym (withSymPred userReg)" $ do
    it "answers True (the v2 retrospective gate)" $
      isSingleValuedSym (withSymPred userReg) `shouldBe` True

  describe "symSat over the User Registration aggregate" $ do
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
