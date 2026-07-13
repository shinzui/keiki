{-# LANGUAGE DeriveAnyClass #-}

-- | Toy fixtures for the @keiki-codec-json-test@ self-test suite.
-- A demonstration of the typical consumer pattern: one custom slot
-- type ('Email'), a baseline slot list ('DemoSlots'), and a mutated
-- variant ('DemoSlotsRenamed') used to exercise the sensitivity
-- helper.
module Keiki.Codec.JSON.Test.Demo
  ( Email (..),
    DemoSlots,
    DemoSlotsRenamed,
    demoRegFile,
  )
where

import Data.Aeson qualified as Aeson
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Data.Text qualified as T
import GHC.Generics (Generic)
import Keiki.Core (RegFile (..))
import Keiki.Shape (CanonicalTypeName)
import Test.QuickCheck (Arbitrary (..))
import Test.QuickCheck.Instances ()

-- | A consumer-supplied slot type. Production users would carry
-- richer invariants (e.g. validate the @\@@ separator on
-- construction); for the self-test the structural type is enough.
newtype Email = Email Text
  deriving stock (Eq, Show, Generic)
  deriving newtype (Aeson.ToJSON, Aeson.FromJSON, Arbitrary)
  deriving anyclass (CanonicalTypeName)

-- | A consumer's snapshot slot list. The 'regFileCodecProps' helper
-- runs the EP-36 M3 property discipline against any slot list whose
-- slot types satisfy 'Aeson.ToJSON' / 'Aeson.FromJSON' /
-- 'Arbitrary' / 'CanonicalTypeName'.
type DemoSlots =
  '[ '("email", Email),
     '("count", Int)
   ]

-- | A schema-evolution mutation of 'DemoSlots': @email@ has been
-- renamed to @emailAddress@. The 'regFileShapeSensitivitySpec'
-- helper must observe a hash flip for this mutation.
type DemoSlotsRenamed =
  '[ '("emailAddress", Email),
     '("count", Int)
   ]

demoRegFile :: RegFile DemoSlots
demoRegFile =
  RCons (Proxy @"email") (Email (T.pack "a@b.c")) $
    RCons (Proxy @"count") (7 :: Int) RNil
