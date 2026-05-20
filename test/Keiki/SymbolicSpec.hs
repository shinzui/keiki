module Keiki.SymbolicSpec (spec) where

import Data.Kind (Type)
import Data.Maybe (isJust)
import Data.Proxy (Proxy (..))
import qualified Data.SBV as SBV
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.Typeable (Typeable)
import Data.Word (Word8, Word16, Word32, Word64)
import Data.Int (Int32, Int64)
import Test.Hspec

import Keiki.Symbolic


-- | A two-constructor input symbol for the 'PInCtor' tests.
data TinyCmd = TinyFoo Int | TinyBar Int deriving (Eq, Show)


-- * Numeric-registry fixtures (EP-41 M1) ---------------------------------

-- | A single-slot register file whose value type is the money/count
-- carrier 'Word64'. Used to prove the EP-41 numeric instances make
-- fixed-width-integer slots solver-visible and witness-extractable.
type AmountRegs = '[ '("amount", Word64) ]


-- | A one-constructor (empty-payload) input symbol for the numeric
-- fixture. The 'KnownInCtors' instance lets 'symSatExt' rebuild it.
data AmtCmd = AmtTick deriving (Eq, Show)


inCtorAmtTick :: InCtor AmtCmd '[]
inCtorAmtTick = InCtor
  { icName  = "AmtTick"
  , icMatch = \case AmtTick -> Just RNil
  , icBuild = \RNil -> AmtTick
  }


instance KnownInCtors AmtCmd where
  allInCtors = [ SomeInCtor inCtorAmtTick ]


-- | The 'amount' slot index, named once for reuse.
amountIdx :: Index AmountRegs Word64
amountIdx = ZIdx


-- | A two-edge transducer over a 'Word64' register. Both edges leave
-- the @False@ vertex; the second edge carries a constant 'Word64'
-- equality that is always false (@5 == 6@), so the pair is mutually
-- exclusive /iff/ the solver can see that @5 == 6@ is unsatisfiable
-- over 'Word64'. Before EP-41 added @Sym Word64@, that equality
-- translated to an opaque fresh 'SBool' and the verdict was @False@;
-- after EP-41 it is real SBV integer equality and the verdict is
-- @True@. Each guard reads the register at most once, so the verdict
-- does not depend on the deferred per-slot memoization.
amountFixture :: SymTransducer (HsPred AmountRegs AmtCmd)
                               AmountRegs Bool AmtCmd ()
amountFixture = SymTransducer
  { edgesOut = \case
      False ->
        [ Edge { guard  = PEq (proj amountIdx) (lit (0 :: Word64))
               , update = UKeep, output = [], target = True }
        , Edge { guard  = PEq (lit (5 :: Word64)) (lit (6 :: Word64))
               , update = UKeep, output = [], target = True }
        ]
      True -> []
  , initial     = False
  , initialRegs = RCons (Proxy @"amount") 0 RNil
  , isFinal     = (== True)
  }


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
    -- EP-41: fixed-width integers (money + counts).
    it "discovers Sym Word64"  $ symKnown (Proxy @Word64)  `shouldBe` True
    it "discovers Sym Word32"  $ symKnown (Proxy @Word32)  `shouldBe` True
    it "discovers Sym Word16"  $ symKnown (Proxy @Word16)  `shouldBe` True
    it "discovers Sym Word8"   $ symKnown (Proxy @Word8)   `shouldBe` True
    it "discovers Sym Int64"   $ symKnown (Proxy @Int64)   `shouldBe` True
    it "discovers Sym Int32"   $ symKnown (Proxy @Int32)   `shouldBe` True
    it "rejects unknown types" $ symKnown (Proxy @())      `shouldBe` False

  describe "numeric Sym registry (EP-41 M1)" $ do
    it "Word64 equality is solver-visible: isBot (PEq lit5 lit6) is True" $
      -- Before M1 this was False (opaque 'neq' fallback); after M1 it is
      -- a real SBV integer contradiction.
      isBot (SymPred (PEq (TLit (5 :: Word64)) (TLit 6)) :: SymPred '[] ())
        `shouldBe` True
    it "Word64 equality stays sat when consistent: isBot (PEq lit5 lit5) is False" $
      isBot (SymPred (PEq (TLit (5 :: Word64)) (TLit 5)) :: SymPred '[] ())
        `shouldBe` False
    it "Word32 equality is solver-visible: isBot (PEq lit10 lit11) is True" $
      isBot (SymPred (PEq (TLit (10 :: Word32)) (TLit 11)) :: SymPred '[] ())
        `shouldBe` True
    it "isSingleValuedSym sees a now-visible constant Word64 contradiction" $
      -- The amountFixture's second edge guard is the always-false
      -- Word64 equality 5 == 6, which only becomes solver-visible with
      -- the EP-41 'Sym Word64' instance. Verdict flips False -> True.
      isSingleValuedSym (withSymPred amountFixture) `shouldBe` True
    it "symSatExt round-trips a Word64 slot (amount == 7)" $ do
      -- Single read of #amount (memoization-safe); PInCtor pins the
      -- input constructor so witness reconstruction succeeds.
      let p = PAnd (PInCtor inCtorAmtTick)
                   (PEq (proj amountIdx) (lit (7 :: Word64)))
              :: HsPred AmountRegs AmtCmd
      case symSatExt p of
        Nothing          -> expectationFailure "Word64 equality reported unsat"
        Just (regs, cmd) -> do
          (regs ! amountIdx) `shouldBe` (7 :: Word64)
          cmd `shouldBe` AmtTick
          evalPred p regs cmd `shouldBe` True

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
