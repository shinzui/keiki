{-# LANGUAGE TemplateHaskell #-}

-- | EP-47 M1 prototype — recompute-and-verify, demonstrated in isolation
-- *before* any change to the production 'solveOutput'.
--
-- This module mirrors the intended new `solveOutput` arm with a local
-- function ('solveCartRV') over a one-edge, one-derived-field order-cart
-- fixture, so the design is validated against the real keiki types
-- (`OutTerm`/`OutFields`/`Term`/`WireCtor`/`InCtor`, `evalOut`) with no
-- edit to `src/Keiki/Core.hs`.
--
-- It demonstrates:
--
--   (a) a @TArith@-output edge round-tripping — a matching event recovers
--       the command, and a tampered derived field is rejected; and
--   (b) determinism preservation — over a grid of command values, every
--       command round-trips to exactly itself and distinct commands never
--       collide on one observed event.
--
-- The prototype uses the *whole-event* @Eq co@ recompute-verify (recover
-- the command from the invertible fields, recompute the whole output
-- forward via 'evalOut', and compare it to the observed event). That is
-- the same forward-recompute-and-@Eq@-match pattern 'applyEventStreaming'
-- already uses for multi-event *tails*; see the research note
-- @docs/research/recompute-and-verify-derived-outputs.md@ for why this
-- whole-event @Eq co@ mechanism is preferred over a field-level @Eq@ that
-- would require an invasive @Eq r@ on the @TArith@/@TApp@ constructors.
module Keiki.RecomputeVerifySpec (spec) where

import Data.List (nub)
import GHC.Generics (Generic)
import Test.Hspec

import Keiki.Core
  ( OutFields (..)
  , OutTerm (..)
  , RegFile (..)
  , WireCtor (..)
  , evalOut
  , pack
  , (.*)
  )
import Keiki.Generics.TH (deriveAggregateCtors, deriveWireCtors)


-- * Order-cart fixture: one derived (redundant) output field --------------

-- The command carries quantity and unitPrice.
data AddData = AddData { quantity :: Int, unitPrice :: Int }
  deriving (Eq, Show, Generic)

data CartCmd = AddLineItem AddData
  deriving (Eq, Show, Generic)

-- The event mirrors them and ALSO stores a derived lineTotal = q * u.
data AddedData = AddedData { quantity :: Int, unitPrice :: Int, lineTotal :: Int }
  deriving (Eq, Show, Generic)

data CartEvt = LineItemAdded AddedData
  deriving (Eq, Show, Generic)

-- No registers are needed: the derived field reads command fields.
type CartRegs = '[]


$(deriveAggregateCtors ''CartCmd ''CartRegs [ ("AddLineItem", "Add") ])
$(deriveWireCtors      ''CartEvt           [ ("LineItemAdded", "Added") ])


-- The edge's output term. quantity and unitPrice are plain TInpCtorField
-- reads (the invertible fields that recover the command); lineTotal is the
-- redundant derived field, the TArith term @quantity * unitPrice@.
cartOut :: OutTerm CartRegs CartCmd CartEvt
cartOut =
  pack inCtorAdd wireAdded
    (OFCons (inpAdd #quantity)
      (OFCons (inpAdd #unitPrice)
        (OFCons (inpAdd #quantity .* inpAdd #unitPrice) OFNil)))


-- | The prototype's recompute-and-verify, specialised to the cart edge.
-- Phase 1 recovers the command from the *invertible* fields only (quantity
-- and unitPrice — the derived lineTotal is ignored for recovery). Phase 2
-- recomputes the whole output forward and checks it equals the observed
-- event; the derived lineTotal is thereby verified, never trusted.
solveCartRV :: CartEvt -> Maybe CartCmd
solveCartRV ev = do
  -- Phase 1: recover from invertible fields. wcMatch deconstructs the
  -- observed event into its (quantity, (unitPrice, (lineTotal, ()))) HList;
  -- we use only the invertible quantity/unitPrice and discard lineTotal.
  (q, (u, (_lineTotal, ()))) <- wcMatch wireAdded ev
  let ci = AddLineItem (AddData { quantity = q, unitPrice = u })
  -- Phase 2: recompute the whole output forward and verify it matches.
  if evalOut cartOut RNil ci == ev
    then Just ci
    else Nothing


-- The event the edge would emit for a given command (forward direction).
emitCart :: CartCmd -> CartEvt
emitCart ci = evalOut cartOut RNil ci


spec :: Spec
spec = do
  describe "EP-47 M1 prototype: recompute-and-verify a TArith output field" $ do
    it "recovers the command from a matching derived-total event" $
      solveCartRV (LineItemAdded (AddedData 3 7 21))
        `shouldBe` Just (AddLineItem (AddData 3 7))

    it "rejects a tampered derived field (lineTotal /= quantity*unitPrice)" $
      solveCartRV (LineItemAdded (AddedData 3 7 999))
        `shouldBe` Nothing

    it "the recovered command re-emits the observed event (forward fixpoint)" $
      emitCart (AddLineItem (AddData 3 7))
        `shouldBe` LineItemAdded (AddedData 3 7 21)

  describe "EP-47 M1 prototype: determinism preserved (command stays unique)" $ do
    let grid = [ AddLineItem (AddData q u) | q <- [0 .. 5], u <- [0 .. 5] ]

    it "every command in the grid round-trips to exactly itself" $
      [ solveCartRV (emitCart c) | c <- grid ]
        `shouldBe` map Just grid

    it "distinct commands never collide on one observed event" $
      let events = map emitCart grid
      in length (nub events) `shouldBe` length grid
