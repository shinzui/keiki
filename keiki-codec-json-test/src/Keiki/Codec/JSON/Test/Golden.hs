-- |
-- Module      : Keiki.Codec.JSON.Test.Golden
-- Description : Per-slot-type golden-byte ToJSON-change detector.
--
-- The lede of @keiki-codec-json-test@. The shape hash from
-- @"Keiki.Shape"@ discriminates snapshots on /structural/ changes
-- (slot rename / add / remove / reorder / type change) but is, by
-- design, /insensitive/ to a slot type's 'Data.Aeson.ToJSON' instance
-- content. If a consumer takes a slot type with one @ToJSON@ instance,
-- persists snapshots, then later edits the same type's @ToJSON@ to
-- emit a different shape (e.g. wrap a bare string in
-- @{"address":...}@), the shape hash remains identical and old
-- snapshots silently fail to decode. This is EP-36 §4 case #10.
--
-- The 'slotGoldenSpec' detector is the contract anchor: it pins a
-- golden bytes value for each slot type and fails loudly the moment
-- the bytes diverge. Two assertions per slot type:
--
-- 1. @'Data.Aeson.encode' (sgInput g) == sgBytes g@ — the @ToJSON@
--    instance still emits the pinned bytes.
-- 2. @'Data.Aeson.decode' (sgBytes g) == Just (sgInput g)@ — the
--    @FromJSON@ instance still parses the pinned bytes back to the
--    original value.
--
-- See the keiki-codec-json-test/README.md for a worked example.
module Keiki.Codec.JSON.Test.Golden
  ( SlotGolden (..)
  , slotGoldenSpec
  ) where

import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import Test.Hspec (Spec, describe, it, shouldBe)


-- | A pinned (input, expected-bytes) golden pair for a slot type.
--
-- Authoring tip: capture @sgBytes@ by running @Aeson.encode@ on the
-- canonical input value once, hand-inspecting the bytes, and pasting
-- the result as a string literal. Future drift in @ToJSON@ trips the
-- detector.
data SlotGolden a = SlotGolden
  { sgInput :: a
    -- ^ Canonical input value the golden bytes are pinned against.
  , sgBytes :: LBS.ByteString
    -- ^ Expected @Aeson.encode (sgInput g)@ output, in lazy
    -- ByteString form for direct equality with 'Aeson.encode'.
  }


-- | Run the case-#10 ToJSON-change detector for a slot type. Two
-- assertions inside a @describe@ block:
--
-- * @ToJSON matches golden bytes@ — failure indicates the slot
--   type's @ToJSON@ instance has silently changed since the golden
--   was pinned. The shape hash will NOT catch this; only this
--   detector will.
-- * @FromJSON parses golden bytes back to the input@ — failure
--   indicates either @FromJSON@ has diverged from @ToJSON@, or the
--   golden was authored against bytes the current decoder rejects.
--
-- Wire into an @hspec@ test suite alongside the rest of your specs:
--
-- @
-- spec :: Spec
-- spec = do
--   slotGoldenSpec "Email" (SlotGolden { sgInput = Email "a\@b.c"
--                                      , sgBytes = "\"a\@b.c\"" })
--   ...
-- @
slotGoldenSpec
  :: (Aeson.ToJSON a, Aeson.FromJSON a, Eq a, Show a)
  => String
    -- ^ A human-readable label for the slot type (used as the
    -- @describe@ heading; typically the type's name).
  -> SlotGolden a
  -> Spec
slotGoldenSpec name g = describe name $ do
  it "ToJSON matches golden bytes" $
    Aeson.encode (sgInput g) `shouldBe` sgBytes g
  it "FromJSON parses golden bytes back to the input" $
    Aeson.decode (sgBytes g) `shouldBe` Just (sgInput g)
