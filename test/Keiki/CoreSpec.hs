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

  describe "step" $ do
    it "produces (s', _, Just co) on a matching output edge" $ do
      case step synthetic (False, RNil) True of
        Just (s', _, Just co) -> (s', co) `shouldBe` (True, "true")
        other                 -> expectationFailure (show3 other)
    it "returns Nothing in the sink vertex" $
      case step synthetic (True, RNil) True of
        Nothing -> pure ()
        other   -> expectationFailure (show3 other)

  describe "reconstitute" $ do
    it "returns the initial state for the empty log" $
      case reconstitute synthetic ([] :: [String]) of
        Just (s, _) -> s `shouldBe` False
        Nothing     -> expectationFailure "expected Just (initial, _)"

  describe "solveOutput on a tiny OPack" $ do
    let -- A tiny output sum.
        wireFooCtor :: WireCtor TinyOut (Int, (Int, ()))
        wireFooCtor = WireCtor
          { wcName  = "Foo"
          , wcMatch = \(Foo a b) -> Just (a, (b, ()))
          , wcBuild = \(a, (b, ())) -> Foo a b
          }
        -- forward: Foo (ci+1) (ci*2)
        outFoo :: OutTerm '[] Int TinyOut
        outFoo = OPack
          wireFooCtor
          (OFCons (TApp1 (+1) (TInpField id))
                  (OFCons (TApp1 (*2) (TInpField id)) OFNil))
          -- v1 hand-written inverse: pull the first field minus 1.
          (\_regs co -> case co of Foo a _ -> Just (a - 1))

    it "evalOut produces Foo (ci+1) (ci*2)" $
      evalOut outFoo RNil 5 `shouldBe` Foo 6 10
    it "solveOutput recovers ci from the observed output" $
      solveOutput outFoo RNil (Foo 6 10) `shouldBe` Just 5
    it "solveOutput on OFn returns Nothing (opaque)" $ do
      let opaqueOut :: OutTerm '[] Int TinyOut
          opaqueOut = OFn (\_ ci -> Foo ci ci)
      solveOutput opaqueOut RNil (Foo 7 7) `shouldBe` Nothing

  describe "checkHiddenInputs" $ do
    it "synthetic transducer's OFn output is flagged" $ do
      let warnings = checkHiddenInputs synthetic
      length warnings `shouldBe` 1
      hiwReason (head warnings) `shouldContain` "OFn output is opaque"
  where
    -- 'show' over `Maybe (s, RegFile rs, Maybe co)` is awkward because
    -- RegFile has no Show. Use a thin coercion to a printable summary.
    show3 :: Show s => Show co => Maybe (s, x, Maybe co) -> String
    show3 Nothing                = "Nothing"
    show3 (Just (s, _, mco))     = "Just (" ++ show s ++ ", _, " ++ show mco ++ ")"


-- | Tiny output sum for the solveOutput micro-test.
data TinyOut = Foo Int Int deriving (Eq, Show)
