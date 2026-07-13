-- |
-- Module      : Keiki.Codec.JSON.Test
-- Description : Library-ised round-trip and sensitivity disciplines
--               for downstream @keiki-codec-json@ consumers.
--
-- Wires three helpers into a consumer's @hspec@ test suite:
--
-- * 'regFileCodecProps' / 'regFileCodecPropsEq' — four QuickCheck properties (Value-path and
--   Encoding-path round-trip, within-path determinism on both
--   paths) against the consumer's own slot list. Mirror of the
--   EP-36 M3 in-tree property suite at
--   @keiki-codec-json/test/Keiki/Codec/JSON/PropSpec.hs@,
--   parameterised so the consumer applies it to their own slot list
--   instead of @ExemplarSlots@.
--
-- * 'regFileShapeSensitivitySpec' — for each named schema-evolution
--   mutation the consumer supplies, assert
--   @'regFileShapeHash' mutation /= 'regFileShapeHash' baseline@.
--   Mirror of the EP-36 M3 in-tree sensitivity assertions at
--   @keiki-codec-json/test/Keiki/Codec/JSON/SensitivitySpec.hs@,
--   parameterised over arbitrary baseline + mutation list.
--
-- * 'ArbitraryRegFile' — an inductive QuickCheck generator class
--   for @'Keiki.Core.RegFile' rs@, building a slot value per slot
--   via each slot type's 'Test.QuickCheck.Arbitrary' instance.
--   Lifted verbatim from the in-tree definition at
--   @keiki-codec-json/test/Keiki/Codec/JSON/Fixtures.hs@.
--
-- These helpers re-expose existing EP-36 disciplines through a
-- stable consumer-facing API. The /new/ test surface in
-- @keiki-codec-json-test@ is the case-#10 detector in
-- "Keiki.Codec.JSON.Test.Golden"; see that module's documentation.
module Keiki.Codec.JSON.Test
  ( -- * Arbitrary generator for slot lists
    ArbitraryRegFile (..),

    -- * Value equality for slot lists
    EqRegFile (..),

    -- * Round-trip + determinism properties
    regFileCodecProps,
    regFileCodecPropsEq,

    -- * Sensitivity helper
    SomeKnownRegFileShape (..),
    someKnownShape,
    regFileShapeSensitivitySpec,
  )
where

import Data.Aeson qualified as Aeson
import Data.Aeson.Encoding qualified as AesonEnc
import Data.Proxy (Proxy (..))
import GHC.TypeLits (KnownSymbol)
-- Arbitrary UTCTime, Text, etc.

import Keiki.Codec.JSON
  ( RegFileToJSON,
    regFileFromJSON,
    regFileToEncoding,
    regFileToJSON,
  )
import Keiki.Core (RegFile (..), Slot)
import Keiki.Shape (KnownRegFileShape, regFileShapeHash)
import Test.Hspec (Spec, describe, it, shouldSatisfy)
import Test.QuickCheck (Arbitrary (..), Gen, Property, forAllShow, (===))
import Test.QuickCheck.Instances ()

-- * Arbitrary generator for slot lists --------------------------------------

-- | Inductive QuickCheck generator over a slot list. Any slot list
-- whose slot types all have 'Arbitrary' instances automatically has
-- an 'ArbitraryRegFile' instance through the inductive pair below.
--
-- @
-- type MySlots = '[ '(\"count\", Int), '(\"note\", Text) ]
-- gen :: Gen (RegFile MySlots)
-- gen = arbRegFile
-- @
--
-- Verbatim mirror of the in-tree definition in
-- @keiki-codec-json/test/Keiki/Codec/JSON/Fixtures.hs@, exposed here
-- so external consumers can import the class.
class ArbitraryRegFile (rs :: [Slot]) where
  arbRegFile :: Gen (RegFile rs)

instance ArbitraryRegFile '[] where
  arbRegFile = pure RNil

instance
  ( KnownSymbol s,
    Arbitrary t,
    ArbitraryRegFile rs
  ) =>
  ArbitraryRegFile ('(s, t) ': rs)
  where
  arbRegFile = RCons (Proxy @s) <$> arbitrary <*> arbRegFile

-- * Value equality for slot lists -------------------------------------------

-- | Inductive equality for a heterogeneous 'RegFile'. Consumers receive an
-- instance automatically when every slot value has 'Eq'.
class EqRegFile (rs :: [Slot]) where
  eqRegFile :: RegFile rs -> RegFile rs -> Bool

instance EqRegFile '[] where
  eqRegFile _ _ = True

instance (Eq t, EqRegFile rs) => EqRegFile ('(s, t) ': rs) where
  eqRegFile (RCons _ x xs) (RCons _ y ys) = x == y && eqRegFile xs ys

-- * Round-trip + determinism properties -------------------------------------

-- | Run the EP-36 M3 codec property suite against an arbitrary slot
-- list. Four properties, 100 QuickCheck samples each by default
-- (override with @--qc-max-success@):
--
-- * /Value path round-trip:/
--   @'regFileFromJSON' . 'regFileToJSON' === Right@
--   (compared via re-encoded bytes; see implementation note below).
-- * /Encoding path round-trip:/ same, via 'regFileToEncoding' and
--   round-tripping through 'Aeson.decode'.
-- * /Value path within-path determinism (R9):/ re-encoding the same
--   'RegFile' yields byte-equal output.
-- * /Encoding path within-path determinism (R9):/ same.
--
-- Implementation note: 'RegFile' has no general 'Eq' or 'Show' instance (the
-- slot list is heterogeneous), so this compatibility helper compares re-encoded
-- bytes. That cannot detect a lossy decode when the changed value re-encodes to
-- the same bytes; aeson's @Just Nothing -> null -> Nothing@ collapse is the known
-- example. Consumers whose slot values have 'Eq' should prefer
-- 'regFileCodecPropsEq', which compares decoded values through 'EqRegFile'.
--
-- Type-application invocation form:
--
-- @
-- regFileCodecProps \@MyAppSnapshotSlots
-- @
--
-- The constraint requires (a) the slot list be a 'RegFileToJSON'
-- (auto-derived when each slot's type has 'Aeson.ToJSON' +
-- 'Aeson.FromJSON' + 'KnownSymbol'), and (b) an 'ArbitraryRegFile'
-- instance (auto-derived when each slot's type has 'Arbitrary').
regFileCodecProps ::
  forall rs.
  ( RegFileToJSON rs,
    ArbitraryRegFile rs
  ) =>
  Spec
regFileCodecProps = do
  describe "Roundtrip" $ do
    it "Value path round-trips" $
      forAllShow (arbRegFile @rs) showRf valueRoundTrip
    it "Encoding path round-trips" $
      forAllShow (arbRegFile @rs) showRf encodingRoundTrip

  describe "Determinism (R9 within-path)" $ do
    it "Value path is deterministic" $
      forAllShow (arbRegFile @rs) showRf valueDeterministic
    it "Encoding path is deterministic" $
      forAllShow (arbRegFile @rs) showRf encodingDeterministic
  where
    showRf :: RegFile rs -> String
    showRf = show . regFileToJSON

    valueRoundTrip :: RegFile rs -> Property
    valueRoundTrip rf =
      let bytes = Aeson.encode (regFileToJSON rf)
       in case Aeson.decode bytes of
            Nothing ->
              False
                === error
                  "Aeson.decode failed on our own Value-path encoder output"
            Just v -> case regFileFromJSON @rs v of
              Left msg ->
                False === error ("regFileFromJSON failed: " <> msg)
              Right rf' ->
                Aeson.encode (regFileToJSON rf') === bytes

    encodingRoundTrip :: RegFile rs -> Property
    encodingRoundTrip rf =
      let bytes = AesonEnc.encodingToLazyByteString (regFileToEncoding rf)
       in case Aeson.decode bytes of
            Nothing ->
              False
                === error
                  "Aeson.decode failed on streaming-encoder output"
            Just v -> case regFileFromJSON @rs v of
              Left msg ->
                False === error ("regFileFromJSON failed: " <> msg)
              Right rf' ->
                AesonEnc.encodingToLazyByteString (regFileToEncoding rf')
                  === bytes

    valueDeterministic :: RegFile rs -> Property
    valueDeterministic rf =
      Aeson.encode (regFileToJSON rf)
        === Aeson.encode (regFileToJSON rf)

    encodingDeterministic :: RegFile rs -> Property
    encodingDeterministic rf =
      AesonEnc.encodingToLazyByteString (regFileToEncoding rf)
        === AesonEnc.encodingToLazyByteString (regFileToEncoding rf)

-- | Value-comparing form of 'regFileCodecProps'. It runs the same four
-- properties but compares decoded slot values through 'EqRegFile', closing the
-- byte-idempotence blind spot of the compatibility helper.
--
-- @
-- regFileCodecPropsEq \@MyAppSnapshotSlots
-- @
regFileCodecPropsEq ::
  forall rs.
  ( RegFileToJSON rs,
    ArbitraryRegFile rs,
    EqRegFile rs
  ) =>
  Spec
regFileCodecPropsEq = do
  describe "Roundtrip" $ do
    it "Value path round-trips by value" $
      forAllShow (arbRegFile @rs) showRf valueRoundTrip
    it "Encoding path round-trips by value" $
      forAllShow (arbRegFile @rs) showRf encodingRoundTrip

  describe "Determinism (R9 within-path)" $ do
    it "Value path is deterministic" $
      forAllShow (arbRegFile @rs) showRf valueDeterministic
    it "Encoding path is deterministic" $
      forAllShow (arbRegFile @rs) showRf encodingDeterministic
  where
    showRf :: RegFile rs -> String
    showRf = show . regFileToJSON

    valueRoundTrip :: RegFile rs -> Property
    valueRoundTrip rf =
      let bytes = Aeson.encode (regFileToJSON rf)
       in case Aeson.decode bytes of
            Nothing ->
              False
                === error
                  "Aeson.decode failed on our own Value-path encoder output"
            Just value -> case regFileFromJSON @rs value of
              Left message ->
                False === error ("regFileFromJSON failed: " <> message)
              Right decoded -> eqRegFile decoded rf === True

    encodingRoundTrip :: RegFile rs -> Property
    encodingRoundTrip rf =
      let bytes = AesonEnc.encodingToLazyByteString (regFileToEncoding rf)
       in case Aeson.decode bytes of
            Nothing ->
              False === error "Aeson.decode failed on streaming-encoder output"
            Just value -> case regFileFromJSON @rs value of
              Left message ->
                False === error ("regFileFromJSON failed: " <> message)
              Right decoded -> eqRegFile decoded rf === True

    valueDeterministic :: RegFile rs -> Property
    valueDeterministic rf =
      Aeson.encode (regFileToJSON rf)
        === Aeson.encode (regFileToJSON rf)

    encodingDeterministic :: RegFile rs -> Property
    encodingDeterministic rf =
      AesonEnc.encodingToLazyByteString (regFileToEncoding rf)
        === AesonEnc.encodingToLazyByteString (regFileToEncoding rf)

-- * Sensitivity helper ------------------------------------------------------

-- | A type-erased witness that a slot list is hashable. The
-- existential is what lets 'regFileShapeSensitivitySpec' take a
-- heterogeneous list of mutated slot lists in one parameter.
--
-- Construct values via 'someKnownShape' with a type application.
data SomeKnownRegFileShape where
  SomeKnownRegFileShape ::
    (KnownRegFileShape rs) => Proxy rs -> SomeKnownRegFileShape

-- | Convenience constructor for 'SomeKnownRegFileShape'.
--
-- @
-- someKnownShape \@MyMutatedSlots
-- @
--
-- equivalent to
--
-- @
-- SomeKnownRegFileShape ('Proxy' \@MyMutatedSlots)
-- @
someKnownShape ::
  forall rs.
  (KnownRegFileShape rs) =>
  SomeKnownRegFileShape
someKnownShape = SomeKnownRegFileShape (Proxy @rs)

-- | Run the EP-36 M3 sensitivity discipline against a baseline slot
-- list and a list of mutations. For each @(label, mutation)@ pair,
-- the spec asserts @'regFileShapeHash' mutation /= 'regFileShapeHash'
-- baseline@.
--
-- A failure means a structural change (the kind the hash MUST detect
-- per EP-36 R5 — slot rename / add / remove / reorder / type change /
-- newtype wrap / primitive→record / split / type rename) was silently
-- absorbed by the hash. The fix is to investigate why the canonical
-- pre-hash bytes did not differ for the named mutation.
--
-- Worked invocation:
--
-- @
-- regFileShapeSensitivitySpec \@MySlots ('Proxy' \@MySlots)
--   [ (\"add slot\", someKnownShape \@MySlotsPlusOne)
--   , (\"rename\",   someKnownShape \@MySlotsRenamed)
--   ]
-- @
regFileShapeSensitivitySpec ::
  forall baseline.
  (KnownRegFileShape baseline) =>
  Proxy baseline ->
  [(String, SomeKnownRegFileShape)] ->
  Spec
regFileShapeSensitivitySpec p mutations = do
  let baseline = regFileShapeHash p
  describe "Shape-hash sensitivity" $
    mapM_ (assertFlip baseline) mutations
  where
    assertFlip baseline (label, SomeKnownRegFileShape p') =
      it (label <> " flips the hash") $
        regFileShapeHash p' `shouldSatisfy` (/= baseline)
