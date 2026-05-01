module Keiki.CoreSpec (spec) where

import Test.Hspec
import Keiki.Core


-- A minimal 2-vertex transducer over 'Bool' input, 'String' output, no
-- registers. Edges:
--
--   False --[guard ci=True / output \"true\"]--> True
--
-- This is the smallest example that exercises 'delta', 'omega', and
-- 'evalOut' on a real edge while keeping the type machinery simple.
synthetic :: SymTransducer (HsPred '[] Bool) '[] Bool Bool String
synthetic = SymTransducer
  { edgesOut = \case
      False -> [ Edge { guard  = matchCmd id
                      , update = UKeep
                      , output = Just (mkOut (\_ _ -> "true"))
                      , target = True
                      }
                ]
      True  -> []
  , initial     = False
  , initialRegs = RNil
  , isFinal     = id
  }


spec :: Spec
spec = do
  describe "evalTerm" $ do
    it "evaluates TLit" $
      evalTerm (TLit (42 :: Int)) RNil () `shouldBe` 42
    it "evaluates TInpField" $
      evalTerm (TInpField id :: Term '[] Int Int) RNil 7 `shouldBe` 7
    it "evaluates TApp1" $
      evalTerm (TApp1 (+1) (TInpField id) :: Term '[] Int Int) RNil 5 `shouldBe` 6
    it "evaluates TApp2" $
      evalTerm
        (TApp2 (+) (TInpField id) (TLit 10) :: Term '[] Int Int)
        RNil 5 `shouldBe` 15

  describe "evalPred" $ do
    it "PTop is True; PBot is False" $ do
      evalPred (PTop  :: HsPred '[] ()) RNil () `shouldBe` True
      evalPred (PBot  :: HsPred '[] ()) RNil () `shouldBe` False
    it "PEq compares equal terms" $
      evalPred (TLit (1 :: Int) .== TLit 1 :: HsPred '[] ()) RNil () `shouldBe` True
    it "PMatchC dispatches to the carried predicate" $
      evalPred (matchCmd id :: HsPred '[] Bool) RNil True `shouldBe` True

  describe "synthetic 2-vertex transducer" $ do
    it "delta moves False -> True on input True (state)" $
      fmap fst (delta synthetic False RNil True) `shouldBe` Just True
    it "omega emits \"true\" on the matching edge" $
      omega synthetic False RNil True `shouldBe` Just "true"
    it "delta returns Nothing when the guard is unsatisfied" $
      fmap fst (delta synthetic False RNil False) `shouldBe` Nothing
    it "delta returns Nothing in the True (sink) vertex" $
      fmap fst (delta synthetic True RNil True) `shouldBe` Nothing
