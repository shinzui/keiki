{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE QualifiedDo #-}
{-# LANGUAGE TemplateHaskell #-}
-- Constructor derivation emits helpers beyond those needed by these
-- compile-time error fixtures.
{-# OPTIONS_GHC -fdefer-type-errors -Wno-deferred-type-errors -Wno-unused-top-binds #-}

module Keiki.BuilderTypeErrorsSpec (spec) where

import Control.Exception (TypeError, evaluate)
import Data.Proxy (Proxy (..))
import GHC.Generics (Generic)
import Keiki.Builder qualified as B
import Keiki.Core (HsPred, OutFields (..), RegFile (..), SymTransducer)
import Keiki.Generics (emptyRegFile)
import Keiki.Generics.TH (deriveAggregateCtors, deriveWireCtors)
import Test.Hspec

type Regs = '[ '("value", Int)]

data Vertex = Start | Done
  deriving (Eq, Show)

data OneData = OneData {value :: Int}
  deriving (Eq, Show, Generic)

data TwoData = TwoData {other :: Int}
  deriving (Eq, Show, Generic)

data Cmd = One OneData | Two TwoData
  deriving (Eq, Show, Generic)

data EventData = EventData {value :: Int}
  deriving (Eq, Show, Generic)

data Event = Emitted EventData
  deriving (Eq, Show, Generic)

$(deriveAggregateCtors ''Cmd ''Regs [("One", "One"), ("Two", "Two")])
$(deriveWireCtors ''Event [("Emitted", "Emitted")])

mismatchedSchemaEmit :: SymTransducer (HsPred Regs Cmd) Regs Vertex Cmd Event
mismatchedSchemaEmit =
  B.buildTransducer Start (emptyRegFile :: RegFile Regs) (const False) do
    B.from Start do
      B.onCmd inCtorOne $ \_d -> B.do
        B.emit wireEmitted (OFCons (inpTwo #other) OFNil)
        B.goto Done

isTypeError :: TypeError -> Bool
isTypeError _ = True

type DupRegs = '[ '("dup", Int), '("dup", Bool)]

_dupRegs :: RegFile DupRegs
_dupRegs = RCons (Proxy @"dup") 0 (RCons (Proxy @"dup") False RNil)

_duplicateSlots :: SymTransducer (HsPred DupRegs ()) DupRegs Vertex () ()
_duplicateSlots =
  B.buildTransducer Start _dupRegs (const False) do
    B.from Start (pure ())

-- Removing -fdefer-type-errors makes '_duplicateSlots' fail compilation with:
--
-- Keiki: register file declares slot "dup" more than once.
-- Slot names in a register file must be pairwise distinct;
-- a duplicated name silently shadows the later slot.
--
-- GHC erases the unsatisfied type-family dictionary under deferred errors,
-- so evaluating the binding cannot catch it as 'TypeError'. Keeping the
-- binding here preserves a compile-only regression alongside the executable
-- mismatched-schema test.

spec :: Spec
spec = do
  it "rejects emit fields projected from a different command schema" $
    evaluate mismatchedSchemaEmit `shouldThrow` isTypeError
