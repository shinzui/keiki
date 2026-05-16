{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE QualifiedDo #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Spike for EP-15 M2: validate the builder against a tiny coffee-
-- dispenser two-vertex toy. After M3 promoted the builder to
-- 'Keiki.Builder', this module is the smallest end-to-end consumer
-- and stays in the test suite as a thin smoke test (the full unit
-- coverage is in 'Keiki.BuilderSpec' under M6).
module Keiki.BuilderSpike (spec) where

import Control.Exception (evaluate)
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import GHC.Generics (Generic)
import Test.Hspec

import qualified Keiki.Builder as B
import Keiki.Builder ((.=), (*:))
import Keiki.Core
  ( Edge (..)
  , HsPred
  , Index
  , OutFields (..)
  , RegFile
  , SymTransducer (..)
  , Update (..)
  , combine
  , delta
  , omega
  , pack
  )
import qualified Keiki.Core as K
import Keiki.Generics (emptyRegFile)
import Keiki.Generics.TH (deriveAggregateCtors, deriveWireCtors)
import Keiki.Internal.Slots (IndexN)


-- * Coffee-dispenser toy ---------------------------------------------------

-- | Money the dispenser tracks. Two slots: the price quoted at
-- insertion time (\"price\") and a sentinel timestamp for when the
-- brew started (\"brewStartedAt\").
type CoffeeRegs =
  '[ '("price",          Int)
   , '("brewStartedAt",  UTCTime)
   ]


emptyCoffeeRegs :: RegFile CoffeeRegs
emptyCoffeeRegs = emptyRegFile


data CoffeeVertex = Idle | Brewing
  deriving (Eq, Show, Enum, Bounded)


-- Two commands: insert money (with an amount and a timestamp); a
-- silent Continue tick that completes the brew.
data InsertData = InsertData
  { amount :: Int
  , at     :: UTCTime
  } deriving (Eq, Show, Generic)

data CoffeeCmd = Insert InsertData | Continue
  deriving (Eq, Show, Generic)


-- One event: the dispenser brewed a coffee at amount C cents.
data BrewedData = BrewedData { paid :: Int }
  deriving (Eq, Show, Generic)

data CoffeeEvent = Brewed BrewedData
  deriving (Eq, Show, Generic)


-- TH: per-input-ctor projections + guards.
$(deriveAggregateCtors ''CoffeeCmd ''CoffeeRegs
    [ ("Insert",   "Insert")
    , ("Continue", "Continue")
    ])


-- TH: per-event-ctor wire ctors.
$(deriveWireCtors ''CoffeeEvent
    [ ("Brewed", "Brewed")
    ])


-- * The toy transducer, twice -----------------------------------------------

-- AST form. Two edges:
--   Idle    --[Insert]--> Brewing  emits Brewed { paid = inp.amount }
--                                  writes price=inp.amount, brewStartedAt=inp.at
--   Brewing --[Continue]-> Idle    epsilon (no event), no register changes
coffeeAST
  :: SymTransducer (HsPred CoffeeRegs CoffeeCmd)
                   CoffeeRegs CoffeeVertex CoffeeCmd CoffeeEvent
coffeeAST = SymTransducer
  { edgesOut    = coffeeASTEdges
  , initial     = Idle
  , initialRegs = emptyCoffeeRegs
  , isFinal     = const False
  }


coffeeASTEdges
  :: CoffeeVertex
  -> [Edge (HsPred CoffeeRegs CoffeeCmd) CoffeeRegs CoffeeCmd CoffeeEvent
           CoffeeVertex]
coffeeASTEdges = \case
  Idle ->
    [ Edge
        { guard  = isInsert
        , update =
            USet (#price :: IndexN "price" CoffeeRegs Int)
                 (inpInsert #amount)
              `combine`
            USet (#brewStartedAt :: IndexN "brewStartedAt" CoffeeRegs UTCTime)
                 (inpInsert #at)
        , output = [ pack
            inCtorInsert
            wireBrewed
            (OFCons (inpInsert #amount) OFNil) ]
        , target = Brewing
        }
    ]
  Brewing ->
    [ Edge
        { guard  = isContinue
        , update = UKeep
        , output = []
        , target = Idle
        }
    ]


-- Builder form. Reads as sequential commands.
--
-- The outer @do@ is plain (VertexBuilder is a regular Monad); the
-- per-vertex @do@ is also plain (EdgeListBuilder is a regular Monad);
-- only the per-edge body uses 'B.do' because it is the indexed-state
-- layer that threads the type-level slot-set.
coffeeBuilt
  :: SymTransducer (HsPred CoffeeRegs CoffeeCmd)
                   CoffeeRegs CoffeeVertex CoffeeCmd CoffeeEvent
coffeeBuilt = B.buildTransducer Idle emptyCoffeeRegs (const False) do

    B.from Idle do
      B.onCmd inCtorInsert $ \d -> B.do
        B.slot @"price"         .= d.amount
        B.slot @"brewStartedAt" .= d.at
        B.emit wireBrewed (d.amount *: B.oNil)
        B.goto Brewing

    B.from Brewing do
      B.onCmd inCtorContinue $ \_d -> B.do
        B.goto Idle


-- * Misuse demonstrations --------------------------------------------------

-- A transducer with a missing-goto edge. Top-level binding evaluation
-- raises the finalize-time error; we wrap in an IO action and use
-- 'evaluate' to force the error in-spec.
coffeeMissingGoto
  :: SymTransducer (HsPred CoffeeRegs CoffeeCmd)
                   CoffeeRegs CoffeeVertex CoffeeCmd CoffeeEvent
coffeeMissingGoto = B.buildTransducer Idle emptyCoffeeRegs (const False) do

    B.from Idle do
      B.onCmd inCtorInsert $ \_d -> B.do
        -- intentional: no goto
        B.noEmit


-- A transducer with two gotos in one body.
coffeeDoubleGoto
  :: SymTransducer (HsPred CoffeeRegs CoffeeCmd)
                   CoffeeRegs CoffeeVertex CoffeeCmd CoffeeEvent
coffeeDoubleGoto = B.buildTransducer Idle emptyCoffeeRegs (const False) do

    B.from Idle do
      B.onCmd inCtorInsert $ \_d -> B.do
        B.goto Brewing
        B.goto Idle


-- * In-spec assertions -----------------------------------------------------

t0 :: UTCTime
t0 = UTCTime (fromGregorian 2026 5 2) (secondsToDiffTime 0)

t100 :: UTCTime
t100 = UTCTime (fromGregorian 2026 5 2) (secondsToDiffTime 100)

t200 :: UTCTime
t200 = UTCTime (fromGregorian 2026 5 2) (secondsToDiffTime 200)


spec :: Spec
spec = do

  describe "EP-15 M2 spike: builder vs AST agreement" $ do

    it "delta and omega agree on Idle + Insert" $ do
      let cmd = Insert (InsertData 250 t0)
      fmap fst (delta coffeeAST    Idle emptyCoffeeRegs cmd)
        `shouldBe` fmap fst (delta coffeeBuilt Idle emptyCoffeeRegs cmd)
      omega coffeeAST    Idle emptyCoffeeRegs cmd
        `shouldBe` omega coffeeBuilt Idle emptyCoffeeRegs cmd

    it "delta and omega agree on Brewing + Continue" $ do
      let insertCmd = Insert (InsertData 250 t0)
      Just (_, regs) <- pure (delta coffeeAST Idle emptyCoffeeRegs insertCmd)
      fmap fst (delta coffeeAST    Brewing regs Continue)
        `shouldBe` fmap fst (delta coffeeBuilt Brewing regs Continue)
      omega coffeeAST    Brewing regs Continue
        `shouldBe` omega coffeeBuilt Brewing regs Continue

    it "delta is Nothing on Idle + Continue (guard mismatch)" $ do
      fmap fst (delta coffeeAST    Idle emptyCoffeeRegs Continue) `shouldBe` Nothing
      fmap fst (delta coffeeBuilt Idle emptyCoffeeRegs Continue) `shouldBe` Nothing

    it "omega round-trips event through the AST and builder forms" $ do
      let cmd = Insert (InsertData 300 t100)
      omega coffeeAST    Idle emptyCoffeeRegs cmd
        `shouldBe` [(Brewed (BrewedData 300))]
      omega coffeeBuilt Idle emptyCoffeeRegs cmd
        `shouldBe` [(Brewed (BrewedData 300))]

  describe "EP-15 M2 spike: misuse error messages" $ do

    it "missing goto fires at finalize time with the expected message" $
      -- `head` forces the first element of the edges list, which is
      -- the result of `finalizeEdge`. `length` would only walk the
      -- spine and not trigger the error.
      evaluate (head (edgesOut coffeeMissingGoto Idle))
        `shouldThrow`
          errorCall ("Keiki.Builder: edge #0 from Idle: goto missing. "
                    <> "Each onCmd/onEpsilon body must end with "
                    <> "exactly one goto V.")

    it "duplicated goto fires at finalize time with the expected message" $
      evaluate (head (edgesOut coffeeDoubleGoto Idle))
        `shouldThrow`
          errorCall ("Keiki.Builder: edge #0 from Idle: goto called "
                    <> "more than once. Each onCmd/onEpsilon body must "
                    <> "end with exactly one goto V.")

  describe "EP-15 M2 spike: timestamp also threads correctly" $
    it "second slot 'brewStartedAt' is written" $ do
      let cmd = Insert (InsertData 200 t200)
      Just (_, regs1) <- pure (delta coffeeAST    Idle emptyCoffeeRegs cmd)
      Just (_, regs2) <- pure (delta coffeeBuilt Idle emptyCoffeeRegs cmd)
      (regs1 K.! (#brewStartedAt :: Index CoffeeRegs UTCTime))
        `shouldBe` (regs2 K.! (#brewStartedAt :: Index CoffeeRegs UTCTime))
