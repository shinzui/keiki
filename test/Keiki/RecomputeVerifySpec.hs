{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE QualifiedDo #-}
{-# LANGUAGE TemplateHaskell #-}

-- | EP-47 — recompute-and-verify derived event outputs, tested against the
-- real (relaxed) 'Keiki.Core.solveOutput'.
--
-- An order-cart aggregate stores a /derived/ output field
-- @lineTotal = quantity * unitPrice@. Three groups:
--
--   (i)   round-trip — the derived-total event replays through 'applyEvents',
--         and a tampered total is rejected;
--   (ii)  determinism — over a grid of commands, every command round-trips to
--         exactly itself and distinct commands never collide on one event;
--   (iii) negative — a /hidden input/ (a command slot read only inside a
--         derived field) is still flagged at build time by 'checkHiddenInputs'.
--
-- (The EP-47 M1 prototype validated the same logic with a local function
-- before the core change; that is now subsumed by exercising the production
-- 'solveOutput'/'applyEvents' directly.)
module Keiki.RecomputeVerifySpec (spec) where

import Data.List (isInfixOf, nub)
import Data.Maybe (isNothing)
import GHC.Generics (Generic)
import Test.Hspec

import qualified Keiki.Builder as B
import Keiki.Builder ((.=))
import Keiki.Core
  ( Edge (..)
  , HiddenInputWarning (..)
  , HsPred (..)
  , Index
  , OutTerm
  , RegFile (..)
  , SymTransducer (..)
  , Update (..)
  , applyEvents
  , checkHiddenInputs
  , evalOut
  , pack
  , solveOutput
  , (!)
  , (.*)
  )
import Keiki.Generics (emptyRegFile)
import Keiki.Generics.TH (deriveAggregateCtors, deriveWireCtors)


-- * Order-cart fixture --------------------------------------------------

data AddData = AddData { quantity :: Int, unitPrice :: Int }
  deriving (Eq, Show, Generic)

data CartCmd = AddLineItem AddData
  deriving (Eq, Show, Generic)

-- The event mirrors quantity/unitPrice and ALSO stores a derived total.
data AddedData = AddedData { quantity :: Int, unitPrice :: Int, lineTotal :: Int }
  deriving (Eq, Show, Generic)

data CartEvt = LineItemAdded AddedData
  deriving (Eq, Show, Generic)

type CartRegs = '[ '("quantity", Int), '("unitPrice", Int) ]

data CartV = CartOpen
  deriving (Eq, Show, Enum, Bounded)


$(deriveAggregateCtors ''CartCmd ''CartRegs [ ("AddLineItem", "Add") ])
$(deriveWireCtors      ''CartEvt           [ ("LineItemAdded", "Added") ])


emptyCartRegs :: RegFile CartRegs
emptyCartRegs = emptyRegFile


-- The well-formed aggregate: quantity and unitPrice are plain command-field
-- projections in the event (the invertible fields that recover the command);
-- lineTotal is the redundant derived field @quantity * unitPrice@.
cart :: SymTransducer (HsPred CartRegs CartCmd) CartRegs CartV CartCmd CartEvt
cart = B.buildTransducer CartOpen emptyCartRegs (const True) do
  B.from CartOpen do
    B.onCmd inCtorAdd $ \d -> B.do
      B.slot @"quantity"  .= d.quantity
      B.slot @"unitPrice" .= d.unitPrice
      B.emit wireAdded AddedTermFields
        { quantity  = d.quantity
        , unitPrice = d.unitPrice
        , lineTotal = d.quantity .* d.unitPrice
        }
      B.goto CartOpen


-- The head output term of the cart edge, for the determinism group.
cartOut :: OutTerm CartRegs CartCmd CartEvt
cartOut = case edgesOut cart CartOpen of
  e : _ | o : _ <- output e -> o
  _                          -> error "RecomputeVerifySpec: cart edge/output missing"


-- * A malformed variant: quantity hidden inside the derived field --------

data BadData = BadData { unitPrice :: Int, total :: Int }
  deriving (Eq, Show, Generic)

data BadEvt = BadAdded BadData
  deriving (Eq, Show, Generic)

$(deriveWireCtors ''BadEvt [ ("BadAdded", "Bad") ])


-- The output recovers only unitPrice invertibly; quantity is read ONLY
-- inside the derived @total@ field, so the command cannot be recovered —
-- a genuine hidden input that checkHiddenInputs must still flag.
badOut :: OutTerm CartRegs CartCmd BadEvt
badOut =
  pack inCtorAdd wireBad
    (B.toOutFields BadTermFields
       { unitPrice = inpAdd #unitPrice
       , total     = inpAdd #quantity .* inpAdd #unitPrice
       })

badCart :: SymTransducer (HsPred CartRegs CartCmd) CartRegs CartV CartCmd BadEvt
badCart = SymTransducer
  { edgesOut    = \CartOpen ->
      [ Edge { guard = PInCtor inCtorAdd
             , update = UKeep
             , output = [badOut]
             , target = CartOpen
             } ]
  , initial     = CartOpen
  , initialRegs = emptyCartRegs
  , isFinal     = const True
  }


spec :: Spec
spec = do
  describe "EP-47 (i): a derived-total event round-trips" $ do
    it "applyEvents replays LineItemAdded {3,7,21} and reconstructs the registers" $
      case applyEvents cart (initial cart, initialRegs cart)
             [ LineItemAdded (AddedData 3 7 21) ] of
        Just (s, regs) ->
          (s, regs ! (#quantity :: Index CartRegs Int), regs ! (#unitPrice :: Index CartRegs Int))
            `shouldBe` (CartOpen, 3, 7)
        Nothing -> expectationFailure "expected the derived-total event to round-trip"

    it "rejects a tampered lineTotal (3*7 = 21 /= 999)" $
      isNothing (applyEvents cart (initial cart, initialRegs cart)
                   [ LineItemAdded (AddedData 3 7 999) ])
        `shouldBe` True

  describe "EP-47 (ii): event determines command (determinism preserved)" $ do
    let grid     = [ AddLineItem (AddData q u) | q <- [0 .. 5], u <- [0 .. 5] ]
        emit c   = evalOut cartOut emptyCartRegs c

    it "every command in the grid round-trips through solveOutput to itself" $
      [ solveOutput cartOut emptyCartRegs (emit c) | c <- grid ]
        `shouldBe` map Just grid

    it "distinct commands never collide on one observed event" $
      length (nub (map emit grid)) `shouldBe` length grid

  describe "EP-47 (iii): a hidden input still fails the build-time check" $ do
    it "checkHiddenInputs flags the well-formed cart with NO warning" $
      checkHiddenInputs cart `shouldBe` []

    it "checkHiddenInputs flags badCart: quantity read only inside the derived field" $ do
      let warnings = checkHiddenInputs badCart
      length warnings `shouldSatisfy` (>= 1)
      let reasons = map hiwReason warnings
      any (\r -> "AddLineItem" `isInfixOf` r && "quantity" `isInfixOf` r) reasons
        `shouldBe` True
