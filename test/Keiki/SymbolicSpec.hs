module Keiki.SymbolicSpec (spec) where

import Data.Kind (Type)
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


-- | 'True' iff a 'Sym' instance is discoverable for @r@ at runtime
-- via the curated registry.
symKnown :: forall (r :: Type). Typeable r => Proxy r -> Bool
symKnown _ = case discoverSym :: Maybe (SymDict r) of
  Just _  -> True
  Nothing -> False
