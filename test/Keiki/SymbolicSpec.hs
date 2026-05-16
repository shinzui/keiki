module Keiki.SymbolicSpec (spec) where

import Data.Kind (Type)
import Data.Maybe (isJust)
import Data.Proxy (Proxy (..))
import qualified Data.SBV as SBV
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.Typeable (Typeable)
import Test.Hspec

import Keiki.Symbolic


-- | A two-constructor input symbol for the 'PInCtor' tests.
data TinyCmd = TinyFoo Int | TinyBar Int deriving (Eq, Show)


inCtorTinyFoo :: InCtor TinyCmd '[ '("a", Int) ]
inCtorTinyFoo = InCtor
  { icName  = "TinyFoo"
  , icMatch = \case
      TinyFoo a -> Just (RCons (Proxy @"a") a RNil)
      _         -> Nothing
  , icBuild = \(RCons _ a RNil) -> TinyFoo a
  }


inCtorTinyBar :: InCtor TinyCmd '[ '("b", Int) ]
inCtorTinyBar = InCtor
  { icName  = "TinyBar"
  , icMatch = \case
      TinyBar b -> Just (RCons (Proxy @"b") b RNil)
      _         -> Nothing
  , icBuild = \(RCons _ b RNil) -> TinyBar b
  }


-- | Run an 'HsPred' through the SBV translator and ask the solver
-- whether the conjunction of the predicate translation is
-- satisfiable. Returns 'True' if SBV reports a model; 'False' if it
-- reports unsat or unknown.
satP :: forall rs ci. HsPred rs ci -> IO Bool
satP p = do
  res <- SBV.sat $ do
    env <- mkSymEnv
    translatePred env p
  pure (SBV.modelExists res)


-- | Run an 'HsPred' as a /claim/ and ask the solver whether its
-- negation is unsatisfiable, i.e. the claim is a tautology.
proveP :: forall rs ci. HsPred rs ci -> IO Bool
proveP p = do
  res <- SBV.prove $ do
    env <- mkSymEnv
    translatePred env p
  pure (not (SBV.modelExists res))


spec :: Spec
spec = do
  describe "discoverSym (curated registry)" $ do
    it "discovers Sym Bool"    $ symKnown (Proxy @Bool)    `shouldBe` True
    it "discovers Sym Int"     $ symKnown (Proxy @Int)     `shouldBe` True
    it "discovers Sym Integer" $ symKnown (Proxy @Integer) `shouldBe` True
    it "discovers Sym Text"    $ symKnown (Proxy @Text)    `shouldBe` True
    it "discovers Sym UTCTime" $ symKnown (Proxy @UTCTime) `shouldBe` True
    it "rejects unknown types" $ symKnown (Proxy @())      `shouldBe` False

  describe "translatePred (boolean skeleton)" $ do
    it "PTop is a tautology" $ do
      proveP (PTop :: HsPred '[] ()) `shouldReturn` True
    it "PBot is unsatisfiable" $ do
      satP (PBot :: HsPred '[] ()) `shouldReturn` False
    it "PAnd PTop PTop is a tautology" $ do
      proveP (PAnd PTop PTop :: HsPred '[] ()) `shouldReturn` True
    it "POr PBot PBot is unsatisfiable" $ do
      satP (POr PBot PBot :: HsPred '[] ()) `shouldReturn` False
    it "PNot PTop is unsatisfiable" $ do
      satP (PNot PTop :: HsPred '[] ()) `shouldReturn` False

  describe "translatePred over PEq (SBV-supported types)" $ do
    it "PEq (TLit 5) (TLit 5) is a tautology" $ do
      proveP (PEq (TLit (5 :: Int)) (TLit 5) :: HsPred '[] ())
        `shouldReturn` True
    it "PEq (TLit 5) (TLit 6) is unsatisfiable" $ do
      satP (PEq (TLit (5 :: Int)) (TLit 6) :: HsPred '[] ())
        `shouldReturn` False

  describe "translatePred over PInCtor (constructor mutual exclusion)" $ do
    it "PInCtor inCtorTinyFoo is satisfiable in isolation" $ do
      satP (PInCtor inCtorTinyFoo :: HsPred '[] TinyCmd)
        `shouldReturn` True
    it "PInCtor inCtorTinyFoo AND PInCtor inCtorTinyBar is unsatisfiable" $ do
      satP ( PAnd (PInCtor inCtorTinyFoo)
                  (PInCtor inCtorTinyBar)
             :: HsPred '[] TinyCmd
           )
        `shouldReturn` False
    it "PInCtor inCtorTinyFoo AND PInCtor inCtorTinyFoo is satisfiable" $ do
      satP ( PAnd (PInCtor inCtorTinyFoo)
                  (PInCtor inCtorTinyFoo)
             :: HsPred '[] TinyCmd
           )
        `shouldReturn` True

  describe "SymPred BoolAlg structural ops (M4)" $ do
    it "top wraps PTop" $
      isPTop (unSymPred (top :: SymPred '[] ())) `shouldBe` True
    it "bot wraps PBot" $
      isPBot (unSymPred (bot :: SymPred '[] ())) `shouldBe` True
    it "conj p q wraps PAnd" $
      isPAnd (unSymPred (conj (top :: SymPred '[] ()) bot))
        `shouldBe` True
    it "disj p q wraps POr" $
      isPOr (unSymPred (disj (top :: SymPred '[] ()) bot))
        `shouldBe` True
    it "neg p wraps PNot" $
      isPNot (unSymPred (neg (top :: SymPred '[] ())))
        `shouldBe` True
    it "models delegates to evalPred (top is True)" $
      models (top :: SymPred '[] ()) (RNil, ())
        `shouldBe` True
    it "models delegates to evalPred (bot is False)" $
      models (bot :: SymPred '[] ()) (RNil, ())
        `shouldBe` False

  describe "SymPred BoolAlg solver-backed methods (M5)" $ do
    it "isBot bot is True" $
      isBot (bot :: SymPred '[] ()) `shouldBe` True
    it "isBot top is False" $
      isBot (top :: SymPred '[] ()) `shouldBe` False
    it "isBot (PEq lit5 lit6) is True (SBV unsat)" $
      isBot (SymPred (PEq (TLit (5 :: Int)) (TLit 6)) :: SymPred '[] ())
        `shouldBe` True
    it "isBot (PEq lit5 lit5) is False (SBV sat)" $
      isBot (SymPred (PEq (TLit (5 :: Int)) (TLit 5)) :: SymPred '[] ())
        `shouldBe` False
    it "isBot (PInCtor TinyFoo AND PInCtor TinyBar) is True (constructor mutex)" $
      isBot (SymPred (PAnd (PInCtor inCtorTinyFoo)
                           (PInCtor inCtorTinyBar))
             :: SymPred '[] TinyCmd)
        `shouldBe` True
    it "sat top is Just _" $ do
      let result = sat (top :: SymPred '[] ()) :: Maybe (RegFile '[], ())
      isJust result `shouldBe` True
    it "sat bot is Nothing" $ do
      let result = sat (bot :: SymPred '[] ()) :: Maybe (RegFile '[], ())
      isJust result `shouldBe` False
    it "sat (PEq lit5 lit5) is Just _" $ do
      let result = sat (SymPred (PEq (TLit (5 :: Int)) (TLit 5))
                       :: SymPred '[] ())
                   :: Maybe (RegFile '[], ())
      isJust result `shouldBe` True
    it "sat (PEq lit5 lit6) is Nothing" $ do
      let result = sat (SymPred (PEq (TLit (5 :: Int)) (TLit 6))
                       :: SymPred '[] ())
                   :: Maybe (RegFile '[], ())
      isJust result `shouldBe` False

  describe "isSingleValuedSym (M6)" $ do
    it "synthetic 2-edge with constructor-mutex guards is single-valued" $
      isSingleValuedSym synth2Mutex `shouldBe` True
    it "synthetic 2-edge with overlapping guards is not single-valued" $
      isSingleValuedSym synth2Overlap `shouldBe` False


-- | 'True' iff a 'Sym' instance is discoverable for @r@ at runtime
-- via the curated registry.
symKnown :: forall (r :: Type). Typeable r => Proxy r -> Bool
symKnown _ = case discoverSym :: Maybe (SymDict r) of
  Just _  -> True
  Nothing -> False


-- | Constructor-shape predicates for the M4 SymPred wrapper tests.
-- Each one is 'True' iff the supplied 'HsPred' has the named outermost
-- constructor.
isPTop, isPBot :: HsPred rs ci -> Bool
isPTop PTop = True; isPTop _ = False
isPBot PBot = True; isPBot _ = False

isPAnd, isPOr, isPNot :: HsPred rs ci -> Bool
isPAnd (PAnd _ _) = True; isPAnd _ = False
isPOr  (POr  _ _) = True; isPOr  _ = False
isPNot (PNot _)   = True; isPNot _ = False


-- * Synthetic transducers for isSingleValuedSym tests --------------------

-- | A two-edge transducer from @False@ whose guards are mutually
-- exclusive ('PInCtor TinyFoo' vs. 'PInCtor TinyBar'). The vertex
-- 'True' has no outgoing edges. The expected verdict is
-- 'isSingleValuedSym == True'.
synth2Mutex :: SymTransducer (SymPred '[] TinyCmd) '[] Bool TinyCmd ()
synth2Mutex = SymTransducer
  { edgesOut = \case
      False ->
        [ Edge { guard  = SymPred (PInCtor inCtorTinyFoo)
               , update = UKeep
               , output = []
               , target = True
               }
        , Edge { guard  = SymPred (PInCtor inCtorTinyBar)
               , update = UKeep
               , output = []
               , target = True
               }
        ]
      True -> []
  , initial     = False
  , initialRegs = RNil
  , isFinal     = (== True)
  }


-- | A two-edge transducer with overlapping ('PTop') guards. The
-- expected verdict is 'isSingleValuedSym == False'.
synth2Overlap :: SymTransducer (SymPred '[] TinyCmd) '[] Bool TinyCmd ()
synth2Overlap = SymTransducer
  { edgesOut = \case
      False ->
        [ Edge { guard = SymPred PTop
               , update = UKeep
               , output = []
               , target = True
               }
        , Edge { guard = SymPred PTop
               , update = UKeep
               , output = []
               , target = True
               }
        ]
      True -> []
  , initial     = False
  , initialRegs = RNil
  , isFinal     = (== True)
  }
