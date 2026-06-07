-- | Unit tests for "Keiki.Render.Pretty": the domain-readable
-- pretty-printer for 'HsPred' / 'Term' / 'Update'. Pure 'shouldBe'
-- assertions on exact rendered 'Text'.
module Keiki.Render.PrettySpec (spec) where

import Data.Proxy (Proxy (..))
import Data.Text qualified as T
import Keiki.Core
  ( Cmp (..),
    HsPred (..),
    InCtor (..),
    Index (..),
    NumOp (..),
    RegFile (..),
    Term (..),
    Update (..),
  )
import Keiki.Internal.Slots (IndexN (..))
import Keiki.Render.Pretty (prettyPred, prettyTerm, prettyUpdate)
import Test.Hspec

-- A two-slot register file schema: "balance" :: Int, "limit" :: Int.
type Regs = '[ '("balance", Int), '("limit", Int)]

-- An input type with one constructor "Deposit" carrying one field
-- "amount" :: Int.
data Cmd = Deposit Int
  deriving (Eq, Show)

type DepFields = '[ '("amount", Int)]

inCtorDeposit :: InCtor Cmd DepFields
inCtorDeposit =
  InCtor
    { icName = "Deposit",
      icMatch = \(Deposit n) -> Just (RCons (Proxy @"amount") n RNil),
      icBuild = \(RCons _ n RNil) -> Deposit n
    }

-- Index helpers (built by hand so we do not depend on OverloadedLabels
-- resolution here).
balanceIx :: Index Regs Int
balanceIx = ZIdx

limitIx :: Index Regs Int
limitIx = SIdx ZIdx

amountIx :: Index DepFields Int
amountIx = ZIdx

balanceN :: IndexN "balance" Regs Int
balanceN = IZ

spec :: Spec
spec = do
  describe "prettyTerm" $ do
    it "renders a register read by slot name" $
      prettyTerm (TReg balanceIx :: Term Regs Cmd '[] Int)
        `shouldBe` T.pack "balance"
    it "renders the second register by its slot name" $
      prettyTerm (TReg limitIx :: Term Regs Cmd '[] Int)
        `shouldBe` T.pack "limit"
    it "renders an input-field read as ctor.field" $
      prettyTerm (TInpCtorField inCtorDeposit amountIx :: Term Regs Cmd DepFields Int)
        `shouldBe` T.pack "Deposit.amount"
    it "renders a literal opaquely as <lit>" $
      prettyTerm (TLit (42 :: Int) :: Term Regs Cmd '[] Int)
        `shouldBe` T.pack "<lit>"
    it "renders TApp1 as <fn>(arg)" $
      prettyTerm (TApp1 (+ (1 :: Int)) (TReg balanceIx) :: Term Regs Cmd '[] Int)
        `shouldBe` T.pack "<fn>(balance)"
    it "renders TApp2 as <fn>(a, b)" $
      prettyTerm
        ( TApp2 ((+) :: Int -> Int -> Int) (TReg balanceIx) (TReg limitIx) ::
            Term Regs Cmd '[] Int
        )
        `shouldBe` T.pack "<fn>(balance, limit)"
    it "renders TArith add as (a + b)" $
      prettyTerm (TArith OpAdd (TReg balanceIx) (TReg limitIx) :: Term Regs Cmd '[] Int)
        `shouldBe` T.pack "(balance + limit)"
    it "renders TArith sub as (a - b)" $
      prettyTerm (TArith OpSub (TReg balanceIx) (TReg limitIx) :: Term Regs Cmd '[] Int)
        `shouldBe` T.pack "(balance - limit)"
    it "renders TArith mul as (a * b)" $
      prettyTerm (TArith OpMul (TReg balanceIx) (TReg limitIx) :: Term Regs Cmd '[] Int)
        `shouldBe` T.pack "(balance * limit)"

  describe "prettyPred" $ do
    it "renders PTop / PBot" $ do
      prettyPred (PTop :: HsPred Regs Cmd) `shouldBe` T.pack "true"
      prettyPred (PBot :: HsPred Regs Cmd) `shouldBe` T.pack "false"
    it "renders PInCtor as the constructor name" $
      prettyPred (PInCtor inCtorDeposit :: HsPred Regs Cmd)
        `shouldBe` T.pack "Deposit"
    it "renders PEq structurally with <lit> on the literal side" $
      prettyPred (PEq (TReg balanceIx) (TLit (0 :: Int)) :: HsPred Regs Cmd)
        `shouldBe` T.pack "balance == <lit>"
    it "renders each PCmp direction" $ do
      prettyPred (PCmp CmpLt (TReg balanceIx) (TReg limitIx) :: HsPred Regs Cmd)
        `shouldBe` T.pack "balance < limit"
      prettyPred (PCmp CmpLe (TReg balanceIx) (TReg limitIx) :: HsPred Regs Cmd)
        `shouldBe` T.pack "balance <= limit"
      prettyPred (PCmp CmpGt (TReg balanceIx) (TReg limitIx) :: HsPred Regs Cmd)
        `shouldBe` T.pack "balance > limit"
      prettyPred (PCmp CmpGe (TReg balanceIx) (TReg limitIx) :: HsPred Regs Cmd)
        `shouldBe` T.pack "balance >= limit"
    it "renders boolean structure with && || !" $
      prettyPred
        ( PAnd
            (PInCtor inCtorDeposit)
            ( POr
                (PCmp CmpGe (TReg balanceIx) (TLit (0 :: Int)))
                (PNot (PEq (TReg limitIx) (TLit (0 :: Int))))
            ) ::
            HsPred Regs Cmd
        )
        `shouldBe` T.pack "(Deposit && (balance >= <lit> || !(limit == <lit>)))"

  describe "prettyUpdate" $ do
    it "renders UKeep" $
      prettyUpdate (UKeep :: Update Regs '[] Cmd) `shouldBe` T.pack "(keep)"
    it "renders USet as slot := term" $
      prettyUpdate (USet balanceN (TLit (0 :: Int)) :: Update Regs '["balance"] Cmd)
        `shouldBe` T.pack "balance := <lit>"
    it "renders UCombine comma-separated" $
      prettyUpdate
        ( UCombine
            (USet balanceN (TReg limitIx))
            (USet balanceN (TLit (1 :: Int))) ::
            Update Regs '["balance", "balance"] Cmd
        )
        `shouldBe` T.pack "balance := limit, balance := <lit>"
