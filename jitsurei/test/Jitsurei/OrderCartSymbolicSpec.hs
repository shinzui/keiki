-- | Symbolic-side spec for the OrderCart aggregate (EP-41 M3). Dogfoods
-- the EP-41 numeric ('Sym Word16'\/'Word32'\/'Word64') and ordering
-- ('PCmp') support on a /shipped/ aggregate whose registers are money
-- and counts ('Money = Word64', 'ItemCount = Word32',
-- 'DiscountBp = Word16').
--
-- Before EP-41 the OrderCart fixture had no symbolic spec at all: its
-- 'Word*' register types were absent from the curated
-- 'Keiki.Symbolic.Sym' registry, so any equality or ordering over them
-- translated to an opaque fresh 'SBool' and witnesses could not be
-- reconstructed (there was deliberately no 'KnownInCtors OrderCmd'
-- instance). EP-41 added the numeric instances and the instance, so the
-- assertions below now hold.
module Jitsurei.OrderCartSymbolicSpec (spec) where

import Test.Hspec

import Jitsurei.OrderCart
import Keiki.Symbolic


-- | The money register slot, named once for reuse.
amountPaidIdx :: Index OrderCartRegs Money
amountPaidIdx = #amountPaid


spec :: Spec
spec = do
  describe "isSingleValuedSym (withSymPred orderCart)" $
    -- orderCart's outgoing edges are disambiguated by input
    -- constructor (PInCtor), so the mutex is decided symbolically by
    -- the shared constructor tag. This confirms the SBV-backed
    -- analysis runs end-to-end over a transducer whose register file
    -- carries Word16/Word32/Word64 slots (which only became
    -- solver-extractable with EP-41's Sym instances).
    it "answers True over a Word*-bearing aggregate" $
      isSingleValuedSym (withSymPred orderCart) `shouldBe` True

  describe "Word64 money guards are solver-visible (EP-41)" $ do
    it "constant ordering contradiction over Money (10 < 5) is symIsBot" $
      symIsBot (PCmp CmpLt (lit (10 :: Money)) (lit 5)
                :: HsPred OrderCartRegs OrderCmd)
        `shouldBe` True
    it "constant equality contradiction over Money (5 == 6) is symIsBot" $
      symIsBot (PEq (lit (5 :: Money)) (lit 6)
                :: HsPred OrderCartRegs OrderCmd)
        `shouldBe` True
    it "satisfiable money ordering (10 >= 5) is not symIsBot" $
      symIsBot (PCmp CmpGe (lit (10 :: Money)) (lit 5)
                :: HsPred OrderCartRegs OrderCmd)
        `shouldBe` False

    it "symSatExt reconstructs a ConfirmPayment witness with amountPaid >= 1000" $ do
      -- A single read of the #amountPaid (Word64) register, conjoined
      -- with the ConfirmPayment input-constructor match so witness
      -- reconstruction (pickCi) can rebuild a concrete OrderCmd.
      let p = PAnd (PInCtor inCtorConfirmPayment)
                   (PCmp CmpGe (proj amountPaidIdx) (lit (1000 :: Money)))
              :: HsPred OrderCartRegs OrderCmd
      case symSatExt p of
        Nothing          -> expectationFailure "amountPaid >= 1000 reported unsat"
        Just (regs, cmd) -> do
          (regs ! amountPaidIdx >= 1000) `shouldBe` True
          case cmd of
            ConfirmPayment _ -> pure ()
            other            -> expectationFailure
                                  ("expected a ConfirmPayment witness, got " <> show other)

    it "sat (BoolAlg/Sat surface) yields the same real witness; models accepts it (EP-44)" $ do
      -- Since EP-44, `sat` on 'SymPred' is the real 'symSatExt' witness
      -- (via the 'Sat' instance), so the public algebra surface also gives
      -- a forceable witness on this shipped Word*-bearing aggregate — and
      -- 'models' on it holds.
      let p = PAnd (PInCtor inCtorConfirmPayment)
                   (PCmp CmpGe (proj amountPaidIdx) (lit (1000 :: Money)))
              :: HsPred OrderCartRegs OrderCmd
      case sat (SymPred p) of
        Nothing -> expectationFailure "amountPaid >= 1000 reported unsat"
        Just w  -> models (SymPred p) w `shouldBe` True
