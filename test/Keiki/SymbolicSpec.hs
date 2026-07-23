module Keiki.SymbolicSpec (spec) where

import Data.Int (Int32, Int64)
import Data.Kind (Type)
import Data.Maybe (isJust, isNothing)
import Data.Proxy (Proxy (..))
import Data.SBV qualified as SBV
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Data.Typeable (Typeable)
import Data.Word (Word16, Word32, Word64, Word8)
import Keiki.Symbolic
import Test.Hspec

-- | A two-constructor input symbol for the 'PInCtor' tests.
data TinyCmd = TinyFoo Int | TinyBar Int deriving (Eq, Show)

-- * Numeric-registry fixtures (EP-41 M1) ---------------------------------

-- | A single-slot register file whose value type is the money/count
-- carrier 'Word64'. Used to prove the EP-41 numeric instances make
-- fixed-width-integer slots solver-visible and witness-extractable.
type AmountRegs = '[ '("amount", Word64)]

-- | A one-constructor (empty-payload) input symbol for the numeric
-- fixture. The 'KnownInCtors' instance lets 'symSatExt' rebuild it.
data AmtCmd = AmtTick deriving (Eq, Show)

inCtorAmtTick :: InCtor AmtCmd '[]
inCtorAmtTick =
  InCtor
    { icName = "AmtTick",
      icMatch = \case AmtTick -> Just RNil,
      icBuild = \RNil -> AmtTick
    }

instance KnownInCtors AmtCmd where
  allInCtors = [SomeInCtor inCtorAmtTick]

-- | The 'amount' slot index, named once for reuse.
amountIdx :: Index AmountRegs Word64
amountIdx = ZIdx

-- | A small exact-bit-vector fixture whose overlapping guards are visible only
-- when Word8 arithmetic wraps as it does at runtime.
type ByteRegs = '[ '("byte", Word8)]

byteIdx :: Index ByteRegs Word8
byteIdx = ZIdx

byteWrapGuard, byteHighGuard :: HsPred ByteRegs AmtCmd
byteWrapGuard =
  PCmp
    CmpLe
    (TArith OpAdd (proj byteIdx) (TLit 6))
    (TLit 5)
byteHighGuard = PCmp CmpGe (proj byteIdx) (TLit 250)

byteWrapFixture ::
  SymTransducer
    (HsPred ByteRegs AmtCmd)
    ByteRegs
    Bool
    AmtCmd
    ()
byteWrapFixture =
  SymTransducer
    { edgesOut = \case
        False ->
          [ Edge byteWrapGuard UKeep [] True Live,
            Edge byteHighGuard UKeep [] True Live
          ]
        True -> [],
      initial = False,
      initialRegs = RCons (Proxy @"byte") 0 RNil,
      isFinal = (== True)
    }

-- | A picosecond-time fixture whose guards overlap between two sub-second
-- bounds. Whole-second rounding used to turn this into an empty interval.
type TimeRegs = '[ '("at", UTCTime)]

timeIdx :: Index TimeRegs UTCTime
timeIdx = ZIdx

timeLower, timeUpper, timeWitness :: UTCTime
timeLower = posixSecondsToUTCTime 0.2
timeUpper = posixSecondsToUTCTime 0.9
timeWitness = posixSecondsToUTCTime 0.5

timeAfterGuard, timeBeforeGuard :: HsPred TimeRegs AmtCmd
timeAfterGuard = PCmp CmpGt (proj timeIdx) (TLit timeLower)
timeBeforeGuard = PCmp CmpLt (proj timeIdx) (TLit timeUpper)

timePrecisionFixture ::
  SymTransducer
    (HsPred TimeRegs AmtCmd)
    TimeRegs
    Bool
    AmtCmd
    ()
timePrecisionFixture =
  SymTransducer
    { edgesOut = \case
        False ->
          [ Edge timeAfterGuard UKeep [] True Live,
            Edge timeBeforeGuard UKeep [] True Live
          ]
        True -> [],
      initial = False,
      initialRegs = RCons (Proxy @"at") (posixSecondsToUTCTime 0) RNil,
      isFinal = (== True)
    }

-- | A two-edge transducer over a 'Word64' register. Both edges leave
-- the @False@ vertex; the second edge carries a constant 'Word64'
-- equality that is always false (@5 == 6@), so the pair is mutually
-- exclusive /iff/ the solver can see that @5 == 6@ is unsatisfiable
-- over 'Word64'. Before EP-41 added @Sym Word64@, that equality
-- translated to an opaque fresh 'SBool' and the verdict was @False@;
-- after EP-41 it is real SBV integer equality and the verdict is
-- @True@. Each guard reads the register at most once, so the verdict
-- does not depend on the deferred per-slot memoization.
amountFixture ::
  SymTransducer
    (HsPred AmountRegs AmtCmd)
    AmountRegs
    Bool
    AmtCmd
    ()
amountFixture =
  SymTransducer
    { edgesOut = \case
        False ->
          [ Edge
              { guard = PEq (proj amountIdx) (lit (0 :: Word64)),
                update = UKeep,
                output = [],
                target = True,
                mode = Live
              },
            Edge
              { guard = PEq (lit (5 :: Word64)) (lit (6 :: Word64)),
                update = UKeep,
                output = [],
                target = True,
                mode = Live
              }
          ]
        True -> [],
      initial = False,
      initialRegs = RCons (Proxy @"amount") 0 RNil,
      isFinal = (== True)
    }

-- | A two-edge transducer over the 'Word64' @amount@ register whose
-- /both/ guards read the register: @PEq #amount 0@ and @PEq #amount 1@.
-- Single-valuedness forms the conjunction @#amount == 0 ∧ #amount == 1@,
-- which is unsatisfiable only if the two reads of @#amount@ (one per
-- guard) share a single SBV variable. Before EP-42's per-slot
-- memoization the two reads were independent fresh variables, so the
-- conjunction stayed satisfiable and the verdict was @False@; after
-- EP-42 the shared variable makes it a real contradiction and the
-- verdict flips to @True@. Contrast 'amountFixture', whose second guard
-- is a /constant/ contradiction (@5 == 6@) that needs no memoization.
twoReadEdgeFixture ::
  SymTransducer
    (HsPred AmountRegs AmtCmd)
    AmountRegs
    Bool
    AmtCmd
    ()
twoReadEdgeFixture =
  SymTransducer
    { edgesOut = \case
        False ->
          [ Edge
              { guard = PEq (proj amountIdx) (lit (0 :: Word64)),
                update = UKeep,
                output = [],
                target = True,
                mode = Live
              },
            Edge
              { guard = PEq (proj amountIdx) (lit (1 :: Word64)),
                update = UKeep,
                output = [],
                target = True,
                mode = Live
              }
          ]
        True -> [],
      initial = False,
      initialRegs = RCons (Proxy @"amount") 0 RNil,
      isFinal = (== True)
    }

-- * Structural-arithmetic fixtures (EP-43) -------------------------------

-- | A four-slot 'Int' register file for structural-arithmetic proofs:
-- @#a@/@#b@ feed a sum, @#score@/@#req@ feed a multiply-cap.
type ArithRegs = '[ '("a", Int), '("b", Int), '("score", Int), '("req", Int)]

aIdx, bIdx, scoreIdx, reqIdx :: Index ArithRegs Int
aIdx = #a
bIdx = #b
scoreIdx = #score
reqIdx = #req

-- | A one-constructor (empty-payload) input for the arithmetic
-- fixtures. The 'KnownInCtors' instance lets 'symSatExt' rebuild it.
data ArithCmd = ArithTick deriving (Eq, Show)

inCtorArithTick :: InCtor ArithCmd '[]
inCtorArithTick =
  InCtor
    { icName = "ArithTick",
      icMatch = \case ArithTick -> Just RNil,
      icBuild = \RNil -> ArithTick
    }

instance KnownInCtors ArithCmd where
  allInCtors = [SomeInCtor inCtorArithTick]

-- | A full 'ArithRegs' register file from four 'Int' values, in slot
-- order @a, b, score, req@. Used by the @evalPred@/@evalTerm@ agreement
-- proof.
arithRegs :: Int -> Int -> Int -> Int -> RegFile ArithRegs
arithRegs a b s r =
  RCons
    (Proxy @"a")
    a
    ( RCons
        (Proxy @"b")
        b
        ( RCons
            (Proxy @"score")
            s
            (RCons (Proxy @"req") r RNil)
        )
    )

inCtorTinyFoo :: InCtor TinyCmd '[ '("a", Int)]
inCtorTinyFoo =
  InCtor
    { icName = "TinyFoo",
      icMatch = \case
        TinyFoo a -> Just (RCons (Proxy @"a") a RNil)
        _ -> Nothing,
      icBuild = \(RCons _ a RNil) -> TinyFoo a
    }

inCtorTinyBar :: InCtor TinyCmd '[ '("b", Int)]
inCtorTinyBar =
  InCtor
    { icName = "TinyBar",
      icMatch = \case
        TinyBar b -> Just (RCons (Proxy @"b") b RNil)
        _ -> Nothing,
      icBuild = \(RCons _ b RNil) -> TinyBar b
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
  describe "satResultIsProvablyUnsat" $ do
    it "treats Unknown as not provably empty" $ do
      let unknown = SBV.SatResult (SBV.Unknown SBV.z3 SBV.UnknownTimeOut)
      -- The old implementation negated modelExists, which turns Unknown into
      -- the unsound "provably empty" verdict pinned by this contrast.
      not (SBV.modelExists unknown) `shouldBe` True
      satResultIsProvablyUnsat unknown `shouldBe` False

    it "treats ProofError as not provably empty" $ do
      let proofError = SBV.SatResult (SBV.ProofError SBV.z3 ["boom"] Nothing)
      satResultIsProvablyUnsat proofError `shouldBe` False

    it "trusts a definite unsatisfiable result and rejects a satisfiable one" $ do
      unsatisfiable <- SBV.sat (pure SBV.sFalse :: SBV.Symbolic SBV.SBool)
      satisfiable <- SBV.sat (pure SBV.sTrue :: SBV.Symbolic SBV.SBool)
      satResultIsProvablyUnsat unsatisfiable `shouldBe` True
      satResultIsProvablyUnsat satisfiable `shouldBe` False

  describe "Either-arm predicates" $ do
    let leftTinyFoo :: InCtor (Either TinyCmd Bool) '[]
        leftTinyFoo =
          InCtor
            { icName = "TinyFoo",
              icMatch = \case Left (TinyFoo _) -> Just RNil; _ -> Nothing,
              icBuild = \RNil -> Left (TinyFoo 0)
            }

    it "proves Left and Right arms mutually exclusive" $
      symIsBot
        (PAnd PLeftArm PRightArm :: HsPred '[] (Either TinyCmd Bool))
        `shouldBe` True

    it "keeps an arm test satisfiable alongside a constructor test" $
      symIsBot
        (PAnd PLeftArm (PInCtor leftTinyFoo) :: HsPred '[] (Either TinyCmd Bool))
        `shouldBe` False

  describe "discoverSym (curated registry)" $ do
    it "discovers Sym Bool" $ symKnown (Proxy @Bool) `shouldBe` True
    it "discovers Sym Int" $ symKnown (Proxy @Int) `shouldBe` True
    it "discovers Sym Integer" $ symKnown (Proxy @Integer) `shouldBe` True
    it "discovers Sym Text" $ symKnown (Proxy @Text) `shouldBe` True
    it "discovers Sym UTCTime" $ symKnown (Proxy @UTCTime) `shouldBe` True
    -- EP-41: fixed-width integers (money + counts).
    it "discovers Sym Word64" $ symKnown (Proxy @Word64) `shouldBe` True
    it "discovers Sym Word32" $ symKnown (Proxy @Word32) `shouldBe` True
    it "discovers Sym Word16" $ symKnown (Proxy @Word16) `shouldBe` True
    it "discovers Sym Word8" $ symKnown (Proxy @Word8) `shouldBe` True
    it "discovers Sym Int64" $ symKnown (Proxy @Int64) `shouldBe` True
    it "discovers Sym Int32" $ symKnown (Proxy @Int32) `shouldBe` True
    it "rejects unknown types" $ symKnown (Proxy @()) `shouldBe` False

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
      let p =
            PAnd
              (PInCtor inCtorAmtTick)
              (PEq (proj amountIdx) (lit (7 :: Word64))) ::
              HsPred AmountRegs AmtCmd
      case symSatExt p of
        Nothing -> expectationFailure "Word64 equality reported unsat"
        Just (regs, cmd) -> do
          (regs ! amountIdx) `shouldBe` (7 :: Word64)
          cmd `shouldBe` AmtTick
          evalPred p regs cmd `shouldBe` True

  describe "exact fixed-width and picosecond encodings" $ do
    it "finds a Word8 overlap that exists only through modular wraparound" $ do
      let runtimeRegs = RCons (Proxy @"byte") 255 RNil
      evalPred byteWrapGuard runtimeRegs AmtTick `shouldBe` True
      evalPred byteHighGuard runtimeRegs AmtTick `shouldBe` True
      checkTransitionDeterminismSym byteWrapFixture `shouldSatisfy` (not . null)
      isSingleValuedSym (withSymPred byteWrapFixture) `shouldBe` False

    it "round-trips UTCTime at sub-second precision" $ do
      fromSym (toSym timeWitness) `shouldBe` timeWitness

    it "finds an overlap between sub-second UTCTime bounds" $ do
      let runtimeRegs = RCons (Proxy @"at") timeWitness RNil
      evalPred timeAfterGuard runtimeRegs AmtTick `shouldBe` True
      evalPred timeBeforeGuard runtimeRegs AmtTick `shouldBe` True
      checkTransitionDeterminismSym timePrecisionFixture `shouldSatisfy` (not . null)
      isSingleValuedSym (withSymPred timePrecisionFixture) `shouldBe` False

  describe "ordering predicate PCmp (EP-41 M2)" $ do
    it "constant contradiction 5 >= 10 over Word64 is symIsBot" $
      -- Before M2 this guard could only be written via TApp (opaque)
      -- and would be symIsBot == False.
      symIsBot
        ( PAnd (PCmp CmpGe (TLit (5 :: Word64)) (TLit 10)) PTop ::
            HsPred '[] ()
        )
        `shouldBe` True
    it "satisfiable constant 10 >= 5 over Word64 is not symIsBot" $
      symIsBot (PCmp CmpGe (TLit (10 :: Word64)) (TLit 5) :: HsPred '[] ())
        `shouldBe` False
    it "symSatExt witness respects amount >= 1000" $ do
      let p =
            PAnd
              (PInCtor inCtorAmtTick)
              (PCmp CmpGe (proj amountIdx) (lit (1000 :: Word64))) ::
              HsPred AmountRegs AmtCmd
      case symSatExt p of
        Nothing -> expectationFailure "amount >= 1000 reported unsat"
        Just (regs, cmd) -> do
          (regs ! amountIdx >= 1000) `shouldBe` True
          evalPred p regs cmd `shouldBe` True
    it "evalPred agrees with Haskell comparison for every Cmp direction" $ do
      let vals = [3, 5, 5, 7] :: [Int]
          chk op f =
            and
              [ evalPred
                  (PCmp op (TLit x) (TLit y) :: HsPred '[] ())
                  RNil
                  ()
                  == f x y
              | x <- vals,
                y <- vals
              ]
      chk CmpLt (<) `shouldBe` True
      chk CmpLe (<=) `shouldBe` True
      chk CmpGt (>) `shouldBe` True
      chk CmpGe (>=) `shouldBe` True

  describe "memoization (EP-42)" $ do
    -- All four assertions exercise repeated reads of the same register
    -- #amount. Before EP-42 each read minted a fresh SBV variable, so
    -- the solver believed two reads of #amount could disagree; after
    -- EP-42 they share one variable. Recorded before-values (M0 repl,
    -- mirrored on #x): F1 symIsBot (x /= x) = False, symSatExt = Just;
    -- F3 the two-edge fixture verdict = False. See the plan's
    -- Surprises & Discoveries.
    let pNeq =
          PNot (PEq (proj amountIdx) (proj amountIdx)) ::
            HsPred AmountRegs AmtCmd
        pEq =
          PEq (proj amountIdx) (proj amountIdx) ::
            HsPred AmountRegs AmtCmd

    it "x /= x is empty: symIsBot (PNot (PEq #amount #amount)) is True" $
      symIsBot pNeq `shouldBe` True

    it "x /= x is unsat via symSatExt: symSatExt (PNot (PEq #amount #amount)) is Nothing" $
      isJust (symSatExt pNeq) `shouldBe` False

    it "x == x stays satisfiable: symIsBot (PEq #amount #amount) is False (sanity)" $
      symIsBot pEq `shouldBe` False

    it "two edges PEq #amount 0 / PEq #amount 1 are single-valued" $
      -- The single-valuedness conjunction is #amount == 0 ∧ #amount == 1,
      -- a contradiction only when the two reads share one variable.
      isSingleValuedSym (withSymPred twoReadEdgeFixture) `shouldBe` True

    it "a repeated-read contradiction has no witness: symSatExt (#amount==0 ∧ #amount==1) is Nothing" $ do
      -- Same conjunction as the single-valuedness gate, surfaced through
      -- symSatExt. Before EP-42 the independent reads let the solver
      -- satisfy #amount==0 and #amount==1 separately, so symSatExt
      -- returned a Just whose by-name witness failed models; after EP-42
      -- the shared variable makes it a true contradiction (Nothing).
      let pContra =
            PAnd
              (PInCtor inCtorAmtTick)
              ( PAnd
                  (PEq (proj amountIdx) (lit (0 :: Word64)))
                  (PEq (proj amountIdx) (lit (1 :: Word64)))
              ) ::
              HsPred AmountRegs AmtCmd
      isNothing (symSatExt pContra) `shouldBe` True

    it "symSatExt witness over a repeated read satisfies models" $ do
      -- Positive round-trip: a satisfiable repeated-read predicate. The
      -- by-name witness now coincides with the single shared variable,
      -- so it satisfies models. (PInCtor pins the constructor so witness
      -- reconstruction succeeds.)
      let p =
            PAnd
              (PInCtor inCtorAmtTick)
              (PEq (proj amountIdx) (proj amountIdx)) ::
              HsPred AmountRegs AmtCmd
      case symSatExt p of
        Nothing -> expectationFailure "repeated-read predicate reported unsat"
        Just (regs, cmd) -> models (SymPred p) (regs, cmd) `shouldBe` True

  describe "structural arithmetic (EP-43)" $ do
    -- Before EP-43 a computed operand could only be written through an
    -- opaque TApp, so the solver saw a fresh unconstrained variable and
    -- a constant arithmetic contradiction was reported satisfiable.

    it "constant 2 + 3 > 10 is symIsBot (empty)" $
      symIsBot
        ( PCmp CmpGt (tadd (lit (2 :: Int)) (lit 3)) (lit 10) ::
            HsPred '[] ()
        )
        `shouldBe` True

    it "constant 2 + 3 >= 5 is not symIsBot (satisfiable)" $
      symIsBot
        ( PCmp CmpGe (tadd (lit (2 :: Int)) (lit 3)) (lit 5) ::
            HsPred '[] ()
        )
        `shouldBe` False

    it "constant 10 - 3 == 8 is symIsBot (contradiction)" $
      symIsBot
        ( PEq (tsub (lit (10 :: Int)) (lit 3)) (lit 8) ::
            HsPred '[] ()
        )
        `shouldBe` True

    it "constant 4 * 3 == 12 is not symIsBot (consistent)" $
      symIsBot
        ( PEq (tmul (lit (4 :: Int)) (lit 3)) (lit 12) ::
            HsPred '[] ()
        )
        `shouldBe` False

    it "symSatExt witness respects #a + #b >= 10" $ do
      -- #a and #b are distinct registers, so this needs no memoization;
      -- the witness sum must actually clear the bound.
      let p =
            PAnd
              (PInCtor inCtorArithTick)
              (PCmp CmpGe (tadd (proj aIdx) (proj bIdx)) (lit 10)) ::
              HsPred ArithRegs ArithCmd
      case symSatExt p of
        Nothing -> expectationFailure "#a + #b >= 10 reported unsat"
        Just (regs, cmd) -> do
          ((regs ! aIdx) + (regs ! bIdx) >= 10) `shouldBe` True
          evalPred p regs cmd `shouldBe` True

    it "symSatExt witness respects #req <= #score * 1000" $ do
      let p =
            PAnd
              (PInCtor inCtorArithTick)
              (PCmp CmpLe (proj reqIdx) (tmul (proj scoreIdx) (lit 1000))) ::
              HsPred ArithRegs ArithCmd
      case symSatExt p of
        Nothing -> expectationFailure "#req <= #score * 1000 reported unsat"
        Just (regs, cmd) -> do
          ((regs ! reqIdx) <= (regs ! scoreIdx) * 1000) `shouldBe` True
          evalPred p regs cmd `shouldBe` True

    it "evalTerm/evalPred over tadd/tsub/tmul matches Haskell arithmetic" $ do
      let vals = [-2, 0, 3, 7] :: [Int]
          chk f mk =
            and
              [ evalPred
                  ( PEq (mk (proj aIdx) (proj bIdx)) (lit (f a b)) ::
                      HsPred ArithRegs ArithCmd
                  )
                  (arithRegs a b 0 0)
                  ArithTick
              | a <- vals,
                b <- vals
              ]
      chk (+) tadd `shouldBe` True
      chk (-) tsub `shouldBe` True
      chk (*) tmul `shouldBe` True

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
      satP
        ( PAnd
            (PInCtor inCtorTinyFoo)
            (PInCtor inCtorTinyBar) ::
            HsPred '[] TinyCmd
        )
        `shouldReturn` False
    it "PInCtor inCtorTinyFoo AND PInCtor inCtorTinyFoo is satisfiable" $ do
      satP
        ( PAnd
            (PInCtor inCtorTinyFoo)
            (PInCtor inCtorTinyFoo) ::
            HsPred '[] TinyCmd
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
      isBot
        ( SymPred
            ( PAnd
                (PInCtor inCtorTinyFoo)
                (PInCtor inCtorTinyBar)
            ) ::
            SymPred '[] TinyCmd
        )
        `shouldBe` True
    it "sat top is Just _" $ do
      let result = sat (top :: SymPred '[] ()) :: Maybe (RegFile '[], ())
      isJust result `shouldBe` True
    it "sat bot is Nothing" $ do
      let result = sat (bot :: SymPred '[] ()) :: Maybe (RegFile '[], ())
      isJust result `shouldBe` False
    it "sat (PEq lit5 lit5) is Just _" $ do
      let result =
            sat
              ( SymPred (PEq (TLit (5 :: Int)) (TLit 5)) ::
                  SymPred '[] ()
              ) ::
              Maybe (RegFile '[], ())
      isJust result `shouldBe` True
    it "sat (PEq lit5 lit6) is Nothing" $ do
      let result =
            sat
              ( SymPred (PEq (TLit (5 :: Int)) (TLit 6)) ::
                  SymPred '[] ()
              ) ::
              Maybe (RegFile '[], ())
      isJust result `shouldBe` False

  describe "real BoolAlg.sat witness (EP-44)" $ do
    -- Before EP-44 'sat' on 'SymPred' returned a placeholder whose
    -- components crash when forced, so 'models' on the returned witness
    -- threw. These tests force the witness (via 'models', or by pattern-
    -- matching it), so each crashes before M1 and passes after.
    let pAmt =
          PEq (proj amountIdx) (lit (7 :: Word64)) ::
            HsPred AmountRegs AmtCmd
        pCtor =
          PInCtor inCtorAmtTick ::
            HsPred AmountRegs AmtCmd

    it "sat's witness is forceable and satisfies models (register guard)" $
      case sat (SymPred pAmt) of
        Nothing -> expectationFailure "expected pAmt satisfiable"
        Just w -> models (SymPred pAmt) w `shouldBe` True

    it "sat's witness reconstructs the command and satisfies models (PInCtor)" $
      case sat (SymPred pCtor) of
        Nothing -> expectationFailure "expected pCtor satisfiable"
        Just w -> models (SymPred pCtor) w `shouldBe` True

    it "sat on an unsatisfiable predicate is Nothing" $
      isNothing (sat (bot :: SymPred AmountRegs AmtCmd)) `shouldBe` True

    it "sat agrees with symSatExt on satisfiability" $ do
      isJust (sat (SymPred pAmt)) `shouldBe` isJust (symSatExt pAmt)
      isJust (sat (SymPred pCtor)) `shouldBe` isJust (symSatExt pCtor)

    it "sat over SymPred '[] () yields a real () witness (not a crashing placeholder)" $
      -- No 'PInCtor' pins the constructor; the EP-44 'seInputCtor' domain
      -- constraint + 'KnownInCtors ()' still reconstruct a real '()'.
      -- Forcing @c@ would have thrown the placeholder error before M1.
      case sat (top :: SymPred '[] ()) of
        Nothing -> expectationFailure "expected top satisfiable"
        Just (_, c) -> c `shouldBe` ()

  describe "isSingleValuedSym (M6)" $ do
    it "synthetic 2-edge with constructor-mutex guards is single-valued" $
      isSingleValuedSym synth2Mutex `shouldBe` True
    it "synthetic 2-edge with overlapping guards is not single-valued" $
      isSingleValuedSym synth2Overlap `shouldBe` False

-- | 'True' iff a 'Sym' instance is discoverable for @r@ at runtime
-- via the curated registry.
symKnown :: forall (r :: Type). (Typeable r) => Proxy r -> Bool
symKnown _ = case discoverSym :: Maybe (SymDict r) of
  Just _ -> True
  Nothing -> False

-- | Constructor-shape predicates for the M4 SymPred wrapper tests.
-- Each one is 'True' iff the supplied 'HsPred' has the named outermost
-- constructor.
isPTop, isPBot :: HsPred rs ci -> Bool
isPTop PTop = True; isPTop _ = False
isPBot PBot = True; isPBot _ = False

isPAnd, isPOr, isPNot :: HsPred rs ci -> Bool
isPAnd (PAnd _ _) = True; isPAnd _ = False
isPOr (POr _ _) = True; isPOr _ = False
isPNot (PNot _) = True; isPNot _ = False

-- * Synthetic transducers for isSingleValuedSym tests --------------------

-- | A two-edge transducer from @False@ whose guards are mutually
-- exclusive ('PInCtor TinyFoo' vs. 'PInCtor TinyBar'). The vertex
-- 'True' has no outgoing edges. The expected verdict is
-- 'isSingleValuedSym == True'.
synth2Mutex :: SymTransducer (SymPred '[] TinyCmd) '[] Bool TinyCmd ()
synth2Mutex =
  SymTransducer
    { edgesOut = \case
        False ->
          [ Edge
              { guard = SymPred (PInCtor inCtorTinyFoo),
                update = UKeep,
                output = [],
                target = True,
                mode = Live
              },
            Edge
              { guard = SymPred (PInCtor inCtorTinyBar),
                update = UKeep,
                output = [],
                target = True,
                mode = Live
              }
          ]
        True -> [],
      initial = False,
      initialRegs = RNil,
      isFinal = (== True)
    }

-- | A two-edge transducer with overlapping ('PTop') guards. The
-- expected verdict is 'isSingleValuedSym == False'.
synth2Overlap :: SymTransducer (SymPred '[] TinyCmd) '[] Bool TinyCmd ()
synth2Overlap =
  SymTransducer
    { edgesOut = \case
        False ->
          [ Edge
              { guard = SymPred PTop,
                update = UKeep,
                output = [],
                target = True,
                mode = Live
              },
            Edge
              { guard = SymPred PTop,
                update = UKeep,
                output = [],
                target = True,
                mode = Live
              }
          ]
        True -> [],
      initial = False,
      initialRegs = RNil,
      isFinal = (== True)
    }
