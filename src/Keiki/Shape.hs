{-# LANGUAGE DefaultSignatures #-}

-- | The /shape hash/ for @RegFile rs@.
--
-- A snapshot persister (see keiro's @StateCodec (s, RegFile rs)@) needs a
-- compact, GHC-upgrade-safe discriminator for the type-level slot list.
-- 'regFileShapeHash' provides it: a SHA-256 of a canonical, deterministic
-- rendering of every slot's name and type.
--
-- The hash is sensitive to structural changes (slot rename / addition /
-- removal / reordering / type change) and insensitive to incidental
-- changes (GHC patch version, cabal dependency tree, the slot type's
-- typeclass instances). See @docs\/plans\/36-regfile-json-codec-and-shape-hash-for-snapshot-persistence.md@
-- §3 R3–R5 for the contract and §4 for the schema-evolution cases the
-- hash catches.
--
-- This module is the keiki-side primitive. The JSON codec lives in the
-- sibling package @keiki-codec-json@. Together they are the two halves
-- of the snapshot story: the hash discriminates eligible snapshots; the
-- codec serialises the eligible ones.
module Keiki.Shape
  ( -- * Shape hash
    KnownRegFileShape (..),
    regFileShapeHash,

    -- * Per-type canonical name (escape hatch)
    CanonicalTypeName (..),

    -- * TypeRep rendering
    renderStableTypeRep,

    -- * SHA-256 helper
    sha256Hex,
  )
where

import Crypto.Hash.SHA256 qualified as SHA256
import Data.Bits (shiftR, (.&.))
import Data.ByteString qualified as BS
import Data.Char (intToDigit)
import Data.Int (Int16, Int32, Int64, Int8)
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time.Calendar (Day)
import Data.Time.Clock (UTCTime)
import Data.Typeable (Typeable)
import Data.Word (Word16, Word32, Word64, Word8)
import GHC.TypeLits (KnownSymbol, symbolVal)
import Keiki.Core (Slot)
import Type.Reflection
  ( SomeTypeRep (..),
    TypeRep,
    someTypeRep,
    splitApps,
    tyConModule,
    tyConName,
  )

-- * Canonical type names ----------------------------------------------------

-- | Stable, human-readable name for a slot type. The default
-- implementation uses 'renderStableTypeRep' on the type's 'Typeable'
-- runtime representation; users with stability concerns (a slot type
-- whose defining module is likely to be renamed, or a slot type that
-- straddles libraries with unstable module layouts) can override and
-- pin the name explicitly.
--
-- See P9 in EP-36 (@docs\/plans\/36-regfile-json-codec-and-shape-hash-for-snapshot-persistence.md@).
class CanonicalTypeName a where
  canonicalTypeName :: Proxy a -> Text
  default canonicalTypeName :: (Typeable a) => Proxy a -> Text
  canonicalTypeName p = renderStableTypeRep (someTypeRep p)

-- ** Built-in instances ------------------------------------------------------

--
-- Default instances for the common scalar and primitive container types
-- that a typical 'RegFile' carries. Each is empty-bodied, picking up the
-- 'Typeable' default. Users who want a custom canonical name override
-- with a non-empty instance.

instance CanonicalTypeName ()

instance CanonicalTypeName Bool

instance CanonicalTypeName Char

instance CanonicalTypeName Int

instance CanonicalTypeName Int8

instance CanonicalTypeName Int16

instance CanonicalTypeName Int32

instance CanonicalTypeName Int64

instance CanonicalTypeName Integer

instance CanonicalTypeName Word

instance CanonicalTypeName Word8

instance CanonicalTypeName Word16

instance CanonicalTypeName Word32

instance CanonicalTypeName Word64

instance CanonicalTypeName Double

instance CanonicalTypeName Float

instance CanonicalTypeName Text

instance CanonicalTypeName UTCTime

instance CanonicalTypeName Day

instance (Typeable a) => CanonicalTypeName (Maybe a)

instance (Typeable a) => CanonicalTypeName [a]

instance (Typeable a, Typeable b) => CanonicalTypeName (Either a b)

instance (Typeable a, Typeable b) => CanonicalTypeName (a, b)

instance (Typeable a, Typeable b, Typeable c) => CanonicalTypeName (a, b, c)

-- * Shape hash --------------------------------------------------------------

-- | The class governing slot-lists that carry a shape hash. The
-- inductive method 'regFileShapeCanonical' assembles the pre-hash
-- canonical encoding; 'regFileShapeHash' (top-level, below) is the
-- SHA-256 of that encoding in lower-case hex.
--
-- Per EP-36 §3 R3 the hash is a single SHA-256 over the byte
-- concatenation of, for each slot in slot-list order,
--
-- > <slotSymbol> ":" <renderStableTypeRep tr> ";"
--
-- with the empty list anchored at the literal canonical form
-- @"regfile:0"@. The recursive structure of the class is therefore
-- /string/ concatenation, not nested hashing — the byte-string is built
-- end-to-end and hashed once. This means a slot-list of length /n/
-- performs exactly one SHA-256, not /n/ chained ones.
class KnownRegFileShape (rs :: [Slot]) where
  -- | The full canonical pre-hash encoding of the slot list. Exposed
  -- so that consumers can attach their own hash algorithm or use the
  -- canonical form for debugging; 'regFileShapeHash' wraps this in
  -- SHA-256.
  regFileShapeCanonical :: Proxy rs -> Text

instance KnownRegFileShape '[] where
  regFileShapeCanonical _ = T.pack "regfile:0"

instance
  ( KnownSymbol s,
    CanonicalTypeName t,
    KnownRegFileShape rs
  ) =>
  KnownRegFileShape ('(s, t) ': rs)
  where
  regFileShapeCanonical _ =
    T.concat
      [ T.pack (symbolVal (Proxy @s)),
        T.pack ":",
        canonicalTypeName (Proxy @t),
        T.pack ";",
        regFileShapeCanonical (Proxy @rs)
      ]

-- | Shape hash of a slot list, as lower-case hexadecimal SHA-256 over
-- the UTF-8 bytes of 'regFileShapeCanonical'. Pure, no 'IO'.
regFileShapeHash :: forall rs. (KnownRegFileShape rs) => Proxy rs -> Text
regFileShapeHash p = sha256Hex (regFileShapeCanonical p)

-- * TypeRep rendering -------------------------------------------------------

-- | Render a 'SomeTypeRep' as a stable, application-tree-shaped string.
-- Each 'TyCon' contributes @<tyConModule>.<tyConName>@; applied type
-- arguments are rendered recursively and surrounded by parentheses,
-- comma-separated.
--
-- Examples (the exact module names depend on the GHC base layout; the
-- shape is what's guaranteed):
--
-- > renderStableTypeRep (someTypeRep (Proxy @Int))         = "GHC.Types.Int"
-- > renderStableTypeRep (someTypeRep (Proxy @(Maybe Int))) = "GHC.Internal.Maybe.Maybe(GHC.Types.Int)"
--
-- The implementation uses only 'tyConModule', 'tyConName', and
-- 'splitApps' — never 'tyConPackage' (which varies with cabal version
-- pins), never 'Show' on 'TypeRep' (which is not contractually stable),
-- and never the raw 'Type.Reflection.Fingerprint'. See EP-36 §3 R5
-- and §5 P5.
renderStableTypeRep :: SomeTypeRep -> Text
renderStableTypeRep (SomeTypeRep tr) = renderTypeRep tr

renderTypeRep :: forall k (a :: k). TypeRep a -> Text
renderTypeRep tr =
  let (tc, args) = splitApps tr
      base =
        T.pack (tyConModule tc)
          <> T.pack "."
          <> T.pack (tyConName tc)
   in case args of
        [] -> base
        _ ->
          base
            <> T.pack "("
            <> T.intercalate (T.pack ",") (map renderStableTypeRep args)
            <> T.pack ")"

-- * SHA-256 helper ----------------------------------------------------------

-- | SHA-256 over the UTF-8 encoding of the input, rendered as
-- lower-case hexadecimal.
sha256Hex :: Text -> Text
sha256Hex =
  T.pack . concatMap byteToHex . BS.unpack . SHA256.hash . TE.encodeUtf8

byteToHex :: Word8 -> String
byteToHex b =
  [ intToDigit (fromIntegral (b `shiftR` 4)),
    intToDigit (fromIntegral (b .&. 0x0F))
  ]
