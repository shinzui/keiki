{-# LANGUAGE GADTs #-}
{-# LANGUAGE TypeApplications #-}

-- | The cycle-free, curated set of concrete types understood by Keiki's
-- symbolic layer. This module deliberately contains no SBV dictionaries:
-- 'Keiki.Core' can use it for validation without importing
-- 'Keiki.Symbolic', while 'Keiki.Symbolic' turns the same constructors into
-- the required dictionaries.
module Keiki.Internal.SymbolicTypes
  ( SymbolicType (..),
    discoverSymbolicType,
    symbolicTypeSupportsEquality,
    symbolicTypeSupportsOrdering,
    symbolicTypeSupportsNumeric,
  )
where

import Data.Int (Int32, Int64)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.Typeable (Typeable)
import Data.Word (Word16, Word32, Word64, Word8)
import Type.Reflection (eqTypeRep, typeRep, type (:~~:) (HRefl))

-- | Evidence that a type belongs to Keiki's closed symbolic registry.
data SymbolicType r where
  SymbolicBool :: SymbolicType Bool
  SymbolicInt :: SymbolicType Int
  SymbolicInteger :: SymbolicType Integer
  SymbolicText :: SymbolicType Text
  SymbolicUTCTime :: SymbolicType UTCTime
  SymbolicWord64 :: SymbolicType Word64
  SymbolicWord32 :: SymbolicType Word32
  SymbolicWord16 :: SymbolicType Word16
  SymbolicWord8 :: SymbolicType Word8
  SymbolicInt64 :: SymbolicType Int64
  SymbolicInt32 :: SymbolicType Int32

-- | Discover membership in the curated registry without importing SBV.
discoverSymbolicType :: forall r. (Typeable r) => Maybe (SymbolicType r)
discoverSymbolicType
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Bool) = Just SymbolicBool
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Int) = Just SymbolicInt
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Integer) = Just SymbolicInteger
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Text) = Just SymbolicText
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @UTCTime) = Just SymbolicUTCTime
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Word64) = Just SymbolicWord64
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Word32) = Just SymbolicWord32
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Word16) = Just SymbolicWord16
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Word8) = Just SymbolicWord8
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Int64) = Just SymbolicInt64
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Int32) = Just SymbolicInt32
  | otherwise = Nothing

-- | Every curated type supports symbolic equality.
symbolicTypeSupportsEquality :: SymbolicType r -> Bool
symbolicTypeSupportsEquality _ = True

-- | Whether the registry supplies symbolic ordering for this type.
symbolicTypeSupportsOrdering :: SymbolicType r -> Bool
symbolicTypeSupportsOrdering SymbolicBool = False
symbolicTypeSupportsOrdering SymbolicText = False
symbolicTypeSupportsOrdering _ = True

-- | Whether the registry supplies symbolic numeric operations for this type.
symbolicTypeSupportsNumeric :: SymbolicType r -> Bool
symbolicTypeSupportsNumeric SymbolicInt = True
symbolicTypeSupportsNumeric SymbolicInteger = True
symbolicTypeSupportsNumeric SymbolicWord64 = True
symbolicTypeSupportsNumeric SymbolicWord32 = True
symbolicTypeSupportsNumeric SymbolicWord16 = True
symbolicTypeSupportsNumeric SymbolicWord8 = True
symbolicTypeSupportsNumeric SymbolicInt64 = True
symbolicTypeSupportsNumeric SymbolicInt32 = True
symbolicTypeSupportsNumeric _ = False
