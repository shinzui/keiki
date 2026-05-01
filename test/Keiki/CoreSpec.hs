module Keiki.CoreSpec (spec) where

import Control.Exception (evaluate)
import Data.Proxy (Proxy (..))
import Test.Hspec
import Keiki.Core


-- | A two-constructor input symbol used by the 'TInpCtorField' tests.
data TinyCmd = TinyFoo Int Int | TinyBar Int deriving (Eq, Show)


inCtorTinyFoo :: InCtor TinyCmd
                 '[ '("a", Int), '("b", Int) ]
inCtorTinyFoo = InCtor
  { icName  = "TinyFoo"
  , icMatch = \case
      TinyFoo a b -> Just (RCons (Proxy @"a") a
                          $ RCons (Proxy @"b") b
                          $ RNil)
      _ -> Nothing
  , icBuild = \(RCons _ a (RCons _ b RNil)) -> TinyFoo a b
  }


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

  describe "TInpCtorField (structural input projection)" $ do
    it "evaluates field #a on the matching constructor" $
      evalTerm
        (TInpCtorField inCtorTinyFoo (#a :: Index '[ '("a", Int), '("b", Int) ] Int)
           :: Term '[] TinyCmd Int)
        RNil (TinyFoo 7 9) `shouldBe` 7
    it "evaluates field #b on the matching constructor" $
      evalTerm
        (TInpCtorField inCtorTinyFoo (#b :: Index '[ '("a", Int), '("b", Int) ] Int)
           :: Term '[] TinyCmd Int)
        RNil (TinyFoo 7 9) `shouldBe` 9
    it "errors with the icName when the input is the wrong constructor" $
      evaluate
        (evalTerm
           (TInpCtorField inCtorTinyFoo (#a :: Index '[ '("a", Int), '("b", Int) ] Int)
              :: Term '[] TinyCmd Int)
           RNil (TinyBar 0))
        `shouldThrow` errorCall "evalTerm: TInpCtorField guard violation: TinyFoo"
    it "termReadsInput is True for a TInpCtorField term" $
      termReadsInput
        (TInpCtorField inCtorTinyFoo (#a :: Index '[ '("a", Int), '("b", Int) ] Int)
           :: Term '[] TinyCmd Int)
        `shouldBe` True

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

  describe "solveOutput structural path (TInpCtorField)" $ do
    let -- An output sum mirroring TinyCmd's payload (ci-determined wire).
        wireTinyFoo :: WireCtor TinyCmdOut (Int, (Int, ()))
        wireTinyFoo = WireCtor
          { wcName  = "TinyFooOut"
          , wcMatch = \(TinyFooOut a b) -> Just (a, (b, ()))
          , wcBuild = \(a, (b, ())) -> TinyFooOut a b
          }
        -- Complete OPack: both fields read from inCtorTinyFoo.
        outComplete :: OutTerm '[] TinyCmd TinyCmdOut
        outComplete = OPack
          wireTinyFoo
          (OFCons (TInpCtorField inCtorTinyFoo
                     (#a :: Index '[ '("a", Int), '("b", Int) ] Int))
            (OFCons (TInpCtorField inCtorTinyFoo
                       (#b :: Index '[ '("a", Int), '("b", Int) ] Int))
              OFNil))
          (\_regs _co -> Nothing)  -- fallback unused; structural walk wins
        -- Incomplete OPack: only #a is in OutFields; #b is a constant.
        outIncomplete :: OutTerm '[] TinyCmd TinyCmdOut
        outIncomplete = OPack
          wireTinyFoo
          (OFCons (TInpCtorField inCtorTinyFoo
                     (#a :: Index '[ '("a", Int), '("b", Int) ] Int))
            (OFCons (TLit (0 :: Int)) OFNil))
          (\_regs _co -> Nothing)

    it "evalOut produces TinyFooOut on a matching ci" $
      evalOut outComplete RNil (TinyFoo 7 11) `shouldBe` TinyFooOut 7 11
    it "solveOutput recovers ci structurally (no legacy inverse)" $
      solveOutput outComplete RNil (TinyFooOut 7 11) `shouldBe` Just (TinyFoo 7 11)
    it "solveOutput returns Nothing on incomplete coverage" $
      solveOutput outIncomplete RNil (TinyFooOut 7 0) `shouldBe` Nothing
    it "detectMissingInCtorFields names the missing slot" $
      let mfs = detectMissingInCtorFields
                  (OFCons (TInpCtorField inCtorTinyFoo
                            (#a :: Index '[ '("a", Int), '("b", Int) ] Int))
                    (OFCons (TLit (0 :: Int)) OFNil)
                     :: OutFields '[] TinyCmd (Int, (Int, ())))
      in mfs `shouldBe` Just (MissingInCtorFields "TinyFoo" ["b"])
    it "detectMissingInCtorFields is Nothing on complete coverage" $
      let fs = OFCons (TInpCtorField inCtorTinyFoo
                        (#a :: Index '[ '("a", Int), '("b", Int) ] Int))
                (OFCons (TInpCtorField inCtorTinyFoo
                          (#b :: Index '[ '("a", Int), '("b", Int) ] Int))
                  OFNil) :: OutFields '[] TinyCmd (Int, (Int, ()))
      in detectMissingInCtorFields fs `shouldBe` Nothing
    it "outFieldsHaveInpCtorField is True when at least one TInpCtorField appears" $
      let fs = OFCons (TInpCtorField inCtorTinyFoo
                        (#a :: Index '[ '("a", Int), '("b", Int) ] Int))
                OFNil :: OutFields '[] TinyCmd (Int, ())
      in outFieldsHaveInpCtorField fs `shouldBe` True

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


-- | Output sum mirroring 'TinyCmd' for the M3 structural-path tests.
data TinyCmdOut = TinyFooOut Int Int deriving (Eq, Show)
