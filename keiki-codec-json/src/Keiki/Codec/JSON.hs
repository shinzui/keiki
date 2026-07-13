-- |
-- Module      : Keiki.Codec.JSON
-- Description : JSON encoder, decoder, and streaming encoder for @RegFile rs@.
--
-- This module is the public entry point of the @keiki-codec-json@
-- package. It provides
--
-- * 'regFileToJSON'      — strict 'Aeson.Value' encoder.
-- * 'regFileFromJSON'    — strict decoder (rejects missing, extra, or
--   type-mismatched fields with a per-slot error message).
-- * 'regFileToEncoding'  — streaming encoder that walks the slot list
--   directly into 'Aeson.Series', avoiding the O(output-size)
--   intermediate 'Aeson.Value' allocation. Use this on RegFiles whose
--   slot /values/ are large (multi-MB) — see §10 case B in
--   @docs\/plans\/36-regfile-json-codec-and-shape-hash-for-snapshot-persistence.md@.
--
-- The codec is the keiki-side counterpart of the shape hash in
-- @Keiki.Shape@ ("keiki" package). Together they implement the
-- snapshot persistence story: the hash discriminates eligible
-- snapshots (catches structural drift, EP-36 §4 cases #1–9); the
-- codec serialises the eligible ones.
--
-- == Wire-format rules
--
-- Every slot must have been written before encoding. Encoding a register file
-- seeded by @Keiki.Generics.emptyRegFile@ but not fully initialized throws an
-- 'Control.Exception.ErrorCall' whose message starts with @uninit:@. On the
-- streaming path the exception can surface after an earlier part of the object
-- has already been emitted, so snapshot only fully hydrated aggregates.
--
-- A @Nothing@ slot is present as explicit JSON @null@. Omitting the key is
-- not equivalent: 'regFileFromJSON' rejects every absent slot. A nested
-- @Maybe@ is not faithfully representable by aeson's standard instances:
-- @Just Nothing@ and @Nothing@ both encode as @null@ and decode as outer
-- @Nothing@. Avoid @Maybe (Maybe a)@ slots when that distinction matters, or
-- wrap the inner optional value in a newtype with explicit JSON instances.
--
-- The 'Aeson.Value' path serializes object keys in aeson's KeyMap order
-- (alphabetical with aeson 2.2), while 'regFileToEncoding' preserves slot-list
-- order. The byte streams may differ; both decode to the same register file.
--
-- == Slot-value size guidance (P11)
--
-- keiki's per-slot dispatch overhead is microseconds at any realistic
-- slot count (< 1000 slots). The actual cost of encoding is dominated
-- by each slot type's 'Aeson.ToJSON'/'Aeson.FromJSON' instance and the
-- size of the value it carries. The §10 reference cases in EP-36
-- exhibit RegFiles of 50 KB to 10 MB encoded; this codec serves all of
-- them, but users carrying multi-megabyte slot values should:
--
-- 1. Call 'regFileToEncoding' (this module) instead of 'regFileToJSON'
--    to avoid the O(output-size) intermediate 'Aeson.Value' allocation.
--    Concretely: use
--    @'Aeson.encodingToLazyByteString' . 'regFileToEncoding'@ instead
--    of @'Aeson.encode' . 'regFileToJSON'@.
-- 2. Consider whether the bulk slot belongs in the RegFile at all —
--    for some workloads, splitting bulk data into a separate event
--    stream and projecting it via subscriptions is structurally
--    cleaner than carrying it in the workflow's RegFile.
module Keiki.Codec.JSON
  ( -- * The codec class
    RegFileToJSON (..),

    -- * Internal helper (exported so its instances are reachable; users

    -- typically program against 'RegFileToJSON' only)
    RegFileWalk,
  )
where

import Data.Aeson ((.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Aeson.Types qualified as Aeson (Pair)
import Data.Proxy (Proxy (..))
import GHC.TypeLits (KnownSymbol, symbolVal)
import Keiki.Core (RegFile (..), Slot)

-- * Internal walker -----------------------------------------------------------

-- | Inductive walker over a slot list. Internal helper that powers the
-- three public methods on 'RegFileToJSON'; the auto-derived instances
-- cover any slot list whose components satisfy 'Aeson.ToJSON' and
-- 'Aeson.FromJSON'. Users program against 'RegFileToJSON', not against
-- this class.
class RegFileWalk (rs :: [Slot]) where
  -- | The slot list as a flat list of @(Key, Value)@ pairs, in
  -- slot-list order. Used to build 'Aeson.Value' via 'Aeson.object'.
  regFilePairs :: RegFile rs -> [Aeson.Pair]

  -- | The slot list as an 'Aeson.Series', in slot-list order. Used to
  -- build 'Aeson.Encoding' via 'Aeson.pairs', avoiding the
  -- 'Aeson.Value' intermediate.
  regFileSeries :: RegFile rs -> Aeson.Series

  -- | Consume slots from an 'Aeson.Object', returning the populated
  -- 'RegFile' and the leftover keys. The top-level decoder
  -- ('regFileFromJSON') uses the leftover to reject extra fields.
  regFileReadObject ::
    Aeson.Object ->
    Either String (RegFile rs, Aeson.Object)

instance RegFileWalk '[] where
  regFilePairs _ = []
  regFileSeries _ = mempty
  regFileReadObject km = Right (RNil, km)

instance
  ( KnownSymbol s,
    Aeson.ToJSON t,
    Aeson.FromJSON t,
    RegFileWalk rs
  ) =>
  RegFileWalk ('(s, t) ': rs)
  where
  regFilePairs (RCons _ x rest) =
    let k = Key.fromString (symbolVal (Proxy @s))
     in (k .= x) : regFilePairs rest

  regFileSeries (RCons _ x rest) =
    let k = Key.fromString (symbolVal (Proxy @s))
     in (k .= x) <> regFileSeries rest

  regFileReadObject km =
    let slotName = symbolVal (Proxy @s)
        k = Key.fromString slotName
     in case KeyMap.lookup k km of
          Nothing -> Left (slotName <> ": missing slot")
          Just slotVal -> case Aeson.fromJSON slotVal of
            Aeson.Error msg -> Left (slotName <> ": " <> msg)
            Aeson.Success x -> do
              (rest, km') <- regFileReadObject (KeyMap.delete k km)
              Right (RCons (Proxy @s) x rest, km')

-- * Public class --------------------------------------------------------------

-- | The codec class for 'RegFile' slot lists.
--
-- A slot list @rs@ supports JSON serialisation iff every slot value
-- type carries both 'Aeson.ToJSON' and 'Aeson.FromJSON'. The instance
-- is auto-derived for any such slot list — users do not write
-- 'RegFileToJSON' instances themselves; the structural inductive
-- 'RegFileWalk' instances do the work.
--
-- The three methods correspond to the three columns in EP-36 §3:
--
-- * 'regFileToJSON'     — R1, strict encoder over 'Aeson.Value'.
-- * 'regFileFromJSON'   — R2, strict decoder (missing / extra / type-
--   mismatched fields are 'Left' with a per-slot error message).
-- * 'regFileToEncoding' — R10, streaming encoder over 'Aeson.Encoding'
--   that avoids the 'Aeson.Value' intermediate.
class (RegFileWalk rs) => RegFileToJSON (rs :: [Slot]) where
  -- | Encode a slot list as a JSON object whose keys are the slot
  -- symbols, in slot-list order.
  --
  -- Precondition: every slot must have been written. An unwritten
  -- @Keiki.Generics.emptyRegFile@ slot throws an
  -- 'Control.Exception.ErrorCall' whose message starts with @uninit:@.
  regFileToJSON :: RegFile rs -> Aeson.Value
  regFileToJSON = Aeson.object . regFilePairs

  -- | Streaming encoder. Walks the slot list directly into an
  -- 'Aeson.Series' via 'Aeson.pairs', avoiding the
  -- 'Aeson.Value' intermediate. Recommended for RegFiles with
  -- multi-MB slot values; see the module header's "Slot-value size
  -- guidance".
  --
  -- Precondition: every slot must have been written. An unwritten
  -- @Keiki.Generics.emptyRegFile@ slot throws an
  -- 'Control.Exception.ErrorCall' whose message starts with @uninit:@,
  -- potentially after earlier bytes have been emitted downstream.
  regFileToEncoding :: RegFile rs -> Aeson.Encoding
  regFileToEncoding = Aeson.pairs . regFileSeries

  -- | Strict decoder. Returns @Left "\<slotName\>: \<reason\>"@ on any
  -- of: missing slot, type-mismatched slot, malformed JSON, or
  -- unknown extra field at the top level.
  regFileFromJSON :: Aeson.Value -> Either String (RegFile rs)
  regFileFromJSON v = case v of
    Aeson.Object km -> do
      (rf, leftover) <- regFileReadObject km
      if KeyMap.null leftover
        then Right rf
        else
          Left
            ( "regfile: unknown extra fields: "
                <> show (map Key.toString (KeyMap.keys leftover))
            )
    _ -> Left "regfile: expected JSON Object"

-- | Generic instance: every slot list with the inductive 'RegFileWalk'
-- coverage is a 'RegFileToJSON'. Users do not write instances of this
-- class themselves; the inductive 'RegFileWalk' instances (one for
-- @'[]@, one for @\'(s, t) \': rs@) cover every slot list whose
-- component types carry 'Aeson.ToJSON' and 'Aeson.FromJSON'.
instance (RegFileWalk rs) => RegFileToJSON rs
