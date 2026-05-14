{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}

-- | Shared fixtures for the property, sensitivity, and golden hash
-- specs. Defines an exemplar slot list (used by every spec as the
-- baseline), schema-evolution mutations of it, and an inductive
-- 'Arbitrary' generator for 'RegFile rs'.
module Keiki.Codec.JSON.Fixtures
  ( -- * Baseline slot list
    ExemplarSlots
    -- * Schema-evolution mutations (EP-36 §4 cases #1–9)
  , AddSlots
  , RemoveSlots
  , RenameSlots
  , ReorderSlots
  , TypeChangeSameJsonSlots
  , NewtypeWrapSlots
  , RecordReplaceSlots
  , SplitSlots
  , RenamedTypeSlots
    -- * Auxiliary types for the mutations
  , OrderId (..)
  , Address (..)
  , RenamedAddress (..)
    -- * Arbitrary generator
  , ArbitraryRegFile (..)
  ) where

import qualified Data.Aeson as Aeson
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Data.Time.Clock (UTCTime)
import Data.Word (Word32)
import GHC.Generics (Generic)
import GHC.TypeLits (KnownSymbol)
import Test.QuickCheck (Arbitrary (..), Gen)
import Test.QuickCheck.Instances ()  -- Arbitrary UTCTime, Text, etc.

import Keiki.Core (RegFile (..), Slot)
import Keiki.Shape (CanonicalTypeName)


-- * Baseline slot list -------------------------------------------------------

-- | Exemplar three-slot list used by every spec as the baseline against
-- which mutations are compared.
type ExemplarSlots =
  '[ '("retryCount", Int)
   , '("cooldownUntil", UTCTime)
   , '("correlationId", Text)
   ]


-- * Schema-evolution mutations (EP-36 §4) ------------------------------------

-- | §4 case #1 — Add slot. A fourth slot is appended to the baseline.
type AddSlots =
  '[ '("retryCount", Int)
   , '("cooldownUntil", UTCTime)
   , '("correlationId", Text)
   , '("dispatchedAt", UTCTime)
   ]


-- | §4 case #2 — Remove slot. The baseline minus @correlationId@.
type RemoveSlots =
  '[ '("retryCount", Int)
   , '("cooldownUntil", UTCTime)
   ]


-- | §4 case #3 — Rename slot. @cooldownUntil@ becomes @retryAfter@.
type RenameSlots =
  '[ '("retryCount", Int)
   , '("retryAfter", UTCTime)
   , '("correlationId", Text)
   ]


-- | §4 case #4 — Reorder slots. @cooldownUntil@ and @retryCount@ swap.
type ReorderSlots =
  '[ '("cooldownUntil", UTCTime)
   , '("retryCount", Int)
   , '("correlationId", Text)
   ]


-- | §4 case #5 — Slot type change, same JSON. @retryCount@ moves from
-- 'Int' to 'Word32' (both encode identically on positive integers, but
-- the TypeRep differs).
type TypeChangeSameJsonSlots =
  '[ '("retryCount", Word32)
   , '("cooldownUntil", UTCTime)
   , '("correlationId", Text)
   ]


-- | §4 case #6 — Newtype wrap. @correlationId :: Text@ becomes
-- @correlationId :: OrderId@ where 'OrderId' is a 'Text' newtype with
-- @deriving newtype@ JSON instances. Wire-compatible, but the type's
-- name differs (@OrderId@ vs @Text@) so the hash changes.
type NewtypeWrapSlots =
  '[ '("retryCount", Int)
   , '("cooldownUntil", UTCTime)
   , '("correlationId", OrderId)
   ]


-- | §4 case #7 — Replace primitive with record. @correlationId :: Text@
-- becomes @correlationId :: Address@.
type RecordReplaceSlots =
  '[ '("retryCount", Int)
   , '("cooldownUntil", UTCTime)
   , '("correlationId", Address)
   ]


-- | §4 case #8 — Split slot. @correlationId :: Text@ is split into two
-- slots @correlationStream :: Text@ + @correlationId :: Text@.
type SplitSlots =
  '[ '("retryCount", Int)
   , '("cooldownUntil", UTCTime)
   , '("correlationStream", Text)
   , '("correlationId", Text)
   ]


-- | §4 case #9 — Slot type's internal record changes. To exercise the
-- hash's sensitivity here we use a /distinctly-named/ second type
-- 'RenamedAddress' in place of 'Address'. (Two definitions of @data
-- Address@ with different fields cannot coexist in one Haskell
-- module; for the hash to discriminate them they must differ in
-- @tyConModule + tyConName@. The §4 row notes "Maybe (TypeRep)" — the
-- hash flips when the user actually renames the type to signal the
-- breaking change, which is the disciplined practice.)
type RenamedTypeSlots =
  '[ '("retryCount", Int)
   , '("cooldownUntil", UTCTime)
   , '("correlationId", RenamedAddress)
   ]


-- * Auxiliary types used by the mutations ------------------------------------

newtype OrderId = OrderId Text
  deriving stock (Eq, Show, Generic)
  deriving newtype (Aeson.ToJSON, Aeson.FromJSON, Arbitrary)
  deriving anyclass (CanonicalTypeName)


data Address = Address
  { line :: Text
  , city :: Text
  , postcode :: Text
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (Aeson.ToJSON, Aeson.FromJSON, CanonicalTypeName)


instance Arbitrary Address where
  arbitrary = Address <$> arbitrary <*> arbitrary <*> arbitrary


-- | A distinctly-named near-copy of 'Address' used by 'RenamedTypeSlots'
-- to demonstrate the §4 case #9 detection path (rename-on-breaking-
-- change). Adds a @country@ field to also illustrate the "Address adds
-- country field" example from §4.
data RenamedAddress = RenamedAddress
  { line :: Text
  , city :: Text
  , postcode :: Text
  , country :: Text
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (Aeson.ToJSON, Aeson.FromJSON, CanonicalTypeName)


instance Arbitrary RenamedAddress where
  arbitrary =
    RenamedAddress <$> arbitrary <*> arbitrary <*> arbitrary <*> arbitrary


-- * Arbitrary generator for 'RegFile rs' -------------------------------------

-- | Inductive generator over the slot list. Each slot value comes from
-- the slot type's 'Arbitrary' instance.
class ArbitraryRegFile (rs :: [Slot]) where
  arbRegFile :: Gen (RegFile rs)


instance ArbitraryRegFile '[] where
  arbRegFile = pure RNil


instance
  ( KnownSymbol s
  , Arbitrary t
  , ArbitraryRegFile rs
  )
  => ArbitraryRegFile ('(s, t) ': rs)
  where
  arbRegFile = RCons (Proxy @s) <$> arbitrary <*> arbRegFile
