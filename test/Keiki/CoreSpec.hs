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


-- The synthetic transducer's input-side singleton: matches 'True' only,
-- with an empty payload. 'icName' aligns with the wire-side 'wcName'
-- so 'solveOutput' on the OPack walks an empty 'OutFields' against an
-- empty slot list and recovers 'True'.
inCtorTrue :: InCtor Bool '[]
inCtorTrue = InCtor
  { icName  = "True"
  , icMatch = \case
      True  -> Just RNil
      False -> Nothing
  , icBuild = \RNil -> True
  }


-- The synthetic transducer's wire-side singleton: a one-constructor
-- 'WireCtor' over 'String' carrying no fields, recognising the literal
-- "true". Paired with 'inCtorTrue' under 'OPack' to give the synthetic
-- edge a structural output term (no opaque 'mkOut').
wcStringTrue :: WireCtor String ()
wcStringTrue = WireCtor
  { wcName  = "True"
  , wcMatch = \s -> if s == "true" then Just () else Nothing
  , wcBuild = \() -> "true"
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
      False -> [ Edge { guard  = matchInCtor inCtorTrue
                      , update = UKeep
                      , output = [ pack inCtorTrue wcStringTrue OFNil ]
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
    it "evaluates TApp1" $
      evalTerm (TApp1 (+1) (TLit (5 :: Int)) :: Term '[] () '[] Int) RNil () `shouldBe` 6
    it "evaluates TApp2" $
      evalTerm
        (TApp2 (+) (TLit (5 :: Int)) (TLit 10) :: Term '[] () '[] Int)
        RNil () `shouldBe` 15

  describe "TInpCtorField (structural input projection)" $ do
    it "evaluates field #a on the matching constructor" $
      evalTerm
        (TInpCtorField inCtorTinyFoo (#a :: Index '[ '("a", Int), '("b", Int) ] Int)
           :: Term '[] TinyCmd '[ '("a", Int), '("b", Int) ] Int)
        RNil (TinyFoo 7 9) `shouldBe` 7
    it "evaluates field #b on the matching constructor" $
      evalTerm
        (TInpCtorField inCtorTinyFoo (#b :: Index '[ '("a", Int), '("b", Int) ] Int)
           :: Term '[] TinyCmd '[ '("a", Int), '("b", Int) ] Int)
        RNil (TinyFoo 7 9) `shouldBe` 9
    it "errors with the icName when the input is the wrong constructor" $
      evaluate
        (evalTerm
           (TInpCtorField inCtorTinyFoo (#a :: Index '[ '("a", Int), '("b", Int) ] Int)
              :: Term '[] TinyCmd '[ '("a", Int), '("b", Int) ] Int)
           RNil (TinyBar 0))
        `shouldThrow` errorCall "evalTerm: TInpCtorField guard violation: TinyFoo"
    it "termReadsInput is True for a TInpCtorField term" $
      termReadsInput
        (TInpCtorField inCtorTinyFoo (#a :: Index '[ '("a", Int), '("b", Int) ] Int)
           :: Term '[] TinyCmd '[ '("a", Int), '("b", Int) ] Int)
        `shouldBe` True

  describe "evalPred" $ do
    it "PTop is True; PBot is False" $ do
      evalPred (PTop  :: HsPred '[] ()) RNil () `shouldBe` True
      evalPred (PBot  :: HsPred '[] ()) RNil () `shouldBe` False
    it "PEq compares equal terms" $
      evalPred (TLit (1 :: Int) .== TLit 1 :: HsPred '[] ()) RNil () `shouldBe` True

  describe "synthetic 2-vertex transducer" $ do
    it "delta moves False -> True on input True (state)" $
      fmap fst (delta synthetic False RNil True) `shouldBe` Just True
    it "omega emits \"true\" on the matching edge" $
      omega synthetic False RNil True `shouldBe` ["true"]
    it "delta returns Nothing when the guard is unsatisfied" $
      fmap fst (delta synthetic False RNil False) `shouldBe` Nothing
    it "delta returns Nothing in the True (sink) vertex" $
      fmap fst (delta synthetic True RNil True) `shouldBe` Nothing

  describe "step" $ do
    it "produces (s', _, Just co) on a matching output edge" $ do
      case step synthetic (False, RNil) True of
        Just (s', _, [co]) -> (s', co) `shouldBe` (True, "true")
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
          inCtorTinyFoo
          wireTinyFoo
          (OFCons (TInpCtorField inCtorTinyFoo
                     (#a :: Index '[ '("a", Int), '("b", Int) ] Int))
            (OFCons (TInpCtorField inCtorTinyFoo
                       (#b :: Index '[ '("a", Int), '("b", Int) ] Int))
              OFNil))
        -- Incomplete OPack: only #a is in OutFields; #b is a constant.
        outIncomplete :: OutTerm '[] TinyCmd TinyCmdOut
        outIncomplete = OPack
          inCtorTinyFoo
          wireTinyFoo
          (OFCons (TInpCtorField inCtorTinyFoo
                     (#a :: Index '[ '("a", Int), '("b", Int) ] Int))
            (OFCons (TLit (0 :: Int)) OFNil))
        -- EP-53: an InCtor with the SAME field schema as inCtorTinyFoo but
        -- a different icName. Because 'OutFields' is now indexed by the
        -- input field schema and 'OPack' ties it to the InCtor, a field
        -- projection whose *schema* differs from the OPack's InCtor is a
        -- compile error (un-representable) — the old runtime collision
        -- hazard is gone. The icName is retained only as a runtime
        -- diagnostic: a same-schema projection naming a different
        -- constructor is a clean replay failure ('Nothing'), never a
        -- type-unsound coercion.
        inCtorTinyFooOther :: InCtor TinyCmd '[ '("a", Int), '("b", Int) ]
        inCtorTinyFooOther = InCtor
          { icName  = "OtherName"
          , icMatch = \case
              TinyFoo a b -> Just (RCons (Proxy @"a") a
                                  $ RCons (Proxy @"b") b
                                  $ RNil)
              _ -> Nothing
          , icBuild = \(RCons _ a (RCons _ b RNil)) -> TinyFoo a b
          }
        outNameMismatch :: OutTerm '[] TinyCmd TinyCmdOut
        outNameMismatch = OPack
          inCtorTinyFoo
          wireTinyFoo
          (OFCons (TInpCtorField inCtorTinyFooOther
                     (#a :: Index '[ '("a", Int), '("b", Int) ] Int))
            (OFCons (TInpCtorField inCtorTinyFooOther
                       (#b :: Index '[ '("a", Int), '("b", Int) ] Int))
              OFNil))

    it "evalOut produces TinyFooOut on a matching ci" $
      evalOut outComplete RNil (TinyFoo 7 11) `shouldBe` TinyFooOut 7 11
    it "solveOutput recovers ci structurally (no legacy inverse)" $
      solveOutput outComplete RNil (TinyFooOut 7 11) `shouldBe` Just (TinyFoo 7 11)
    it "solveOutput returns Nothing on incomplete coverage" $
      solveOutput outIncomplete RNil (TinyFooOut 7 0) `shouldBe` Nothing
    it "rejects a same-schema TInpCtorField whose icName differs (EP-53 diagnostic)" $
      solveOutput outNameMismatch RNil (TinyFooOut 7 11) `shouldBe` Nothing
    it "detectMissingInCtorFields names the missing slot" $
      let fs = OFCons (TInpCtorField inCtorTinyFoo
                        (#a :: Index '[ '("a", Int), '("b", Int) ] Int))
                 (OFCons (TLit (0 :: Int)) OFNil)
                 :: OutFields '[] TinyCmd '[ '("a", Int), '("b", Int) ] (Int, (Int, ()))
      in detectMissingInCtorFields inCtorTinyFoo fs
           `shouldBe` Just (MissingInCtorFields "TinyFoo" ["b"])
    it "detectMissingInCtorFields is Nothing on complete coverage" $
      let fs = OFCons (TInpCtorField inCtorTinyFoo
                        (#a :: Index '[ '("a", Int), '("b", Int) ] Int))
                (OFCons (TInpCtorField inCtorTinyFoo
                          (#b :: Index '[ '("a", Int), '("b", Int) ] Int))
                  OFNil) :: OutFields '[] TinyCmd '[ '("a", Int), '("b", Int) ] (Int, (Int, ()))
      in detectMissingInCtorFields inCtorTinyFoo fs `shouldBe` Nothing
    it "outFieldsHaveInpCtorField is True when at least one TInpCtorField appears" $
      let fs = OFCons (TInpCtorField inCtorTinyFoo
                        (#a :: Index '[ '("a", Int), '("b", Int) ] Int))
                OFNil :: OutFields '[] TinyCmd '[ '("a", Int), '("b", Int) ] (Int, ())
      in outFieldsHaveInpCtorField fs `shouldBe` True

  where
    -- 'show' over `Maybe (s, RegFile rs, Maybe co)` is awkward because
    -- RegFile has no Show. Use a thin coercion to a printable summary.
    show3 :: Show s => Show co => Maybe (s, x, [co]) -> String
    show3 Nothing                = "Nothing"
    show3 (Just (s, _, cos_))    = "Just (" ++ show s ++ ", _, " ++ show cos_ ++ ")"


-- | Output sum mirroring 'TinyCmd' for the M3 structural-path tests.
data TinyCmdOut = TinyFooOut Int Int deriving (Eq, Show)
