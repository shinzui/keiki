{-# LANGUAGE TemplateHaskell #-}

-- \$('deriveRegFileCodec' \'\'MySnapshot)
-- @
--
-- to emit three top-level functions
--
-- @
-- mySnapshotToJSON     :: MySnapshot -> Aeson.Value
-- mySnapshotToEncoding :: MySnapshot -> Aeson.Encoding
-- mySnapshotFromJSON   :: Aeson.Value -> Either String MySnapshot
-- @
--
-- Each function routes through the existing
-- 'Keiki.Codec.JSON.RegFileToJSON' class against the slot list
-- @'Keiki.Generics.RegFieldsOf' MySnapshot@. The record's field names
-- become the JSON object's keys; the record's field types must each
-- carry 'Aeson.ToJSON' and 'Aeson.FromJSON' or compilation fails with a
-- precise per-field error.
--
-- This splice lives in @keiki-codec-json@ (not in @keiki@'s
-- @Keiki.Generics.TH@). The class @RegFileToJSON@ is defined here, and
-- moving the splice to @keiki@ would force an @aeson@ dependency on
-- @keiki@ core — violating the load-bearing
-- /keiki MUST NOT gain @aeson@/ requirement (EP-36 §3 R8; MP-11
-- Decision Log 2026-05-10). The splice does reuse the structural
-- machinery in @keiki@'s @Keiki.Generics@ ('Keiki.Generics.RegFieldsOf',
-- 'Keiki.Generics.gToRegFile', 'Keiki.Generics.gFromRegFile') so the
-- composition with the existing 'Keiki.Generics.TH' ergonomics
-- (@mkInCtorVia@, @mkWireCtorVia@, @deriveAggregateCtors@, etc.) is
-- preserved.

-- |
-- Module      : Keiki.Codec.JSON.TH
-- Description : Template Haskell helpers that emit @RegFile@-routed JSON
--               codec functions for plain Haskell record types.
--
-- A user with a record type
--
-- @
-- data MySnapshot = MySnapshot
--   { retryCount    :: Int
--   , correlationId :: Text
--   , dispatchedAt  :: UTCTime
--   }
--   deriving stock ('Eq', 'Show', GHC.Generics.'GHC.Generics.Generic')
-- @
--
-- invokes
--
-- @
module Keiki.Codec.JSON.TH
  ( deriveRegFileCodec,
    deriveRegFileCodecAs,
  )
where

import Data.Aeson qualified as Aeson
import Data.Char (toLower)
import GHC.Generics qualified as Generics
import Keiki.Codec.JSON (regFileFromJSON, regFileToEncoding, regFileToJSON)
import Keiki.Generics (RegFieldsOf, gFromRegFile, gToRegFile)
import Language.Haskell.TH
  ( Con (NormalC, RecC),
    Dec (DataD, NewtypeD, TySynD),
    Info (TyConI),
    Name,
    Q,
    clause,
    conT,
    funD,
    mkName,
    nameBase,
    normalB,
    reify,
    sigD,
  )

-- | Emit three top-level JSON-codec functions for the record type
-- @t@, with names derived from the type's name by lower-casing the
-- first character.
--
-- For @t = MySnapshot@ the splice emits
--
-- * @mySnapshotToJSON     :: MySnapshot -> Aeson.Value@
-- * @mySnapshotToEncoding :: MySnapshot -> Aeson.Encoding@
-- * @mySnapshotFromJSON   :: Aeson.Value -> Either String MySnapshot@
--
-- The record must have @deriving (Generic)@ (the splice does not
-- emit a @Generic@ instance). Every field type must have
-- @Aeson.ToJSON@ and @Aeson.FromJSON@ in scope, or compilation fails
-- at the use site of the emitted function with a missing-instance
-- error naming the field's type.
--
-- The splice rejects:
--
-- * Type synonyms, classes, value bindings, primitive types — only
--   @data@ and @newtype@ declarations are accepted.
-- * Multi-constructor types (@data Foo = A | B@) — a single slot list
--   cannot represent a sum.
-- * Positional (non-record-syntax) constructors — there are no field
--   names to use as slot symbols.
--
-- Singleton constructors with no fields (@data Empty = Empty@) are
-- accepted; the slot list is @'[]@ and the emitted functions codec
-- the empty JSON object.
deriveRegFileCodec :: Name -> Q [Dec]
deriveRegFileCodec n = deriveRegFileCodecAs (defaultPrefix n) n

-- | Variant of 'deriveRegFileCodec' that takes the function-name
-- prefix explicitly. The three emitted functions are named
-- @\<prefix\>ToJSON@, @\<prefix\>ToEncoding@, @\<prefix\>FromJSON@.
deriveRegFileCodecAs :: String -> Name -> Q [Dec]
deriveRegFileCodecAs prefix tyName = do
  validateRecord tyName
  let recTy = conT tyName
      toJSONN = mkName (prefix <> "ToJSON")
      toEncN = mkName (prefix <> "ToEncoding")
      fromJSONN = mkName (prefix <> "FromJSON")

  toJSONSig <-
    sigD
      toJSONN
      [t|$recTy -> Aeson.Value|]
  toJSONDef <-
    funD
      toJSONN
      [ clause
          []
          ( normalB
              [|
                regFileToJSON
                  @(RegFieldsOf $recTy)
                  . gToRegFile
                  . Generics.from
                |]
          )
          []
      ]

  toEncSig <-
    sigD
      toEncN
      [t|$recTy -> Aeson.Encoding|]
  toEncDef <-
    funD
      toEncN
      [ clause
          []
          ( normalB
              [|
                regFileToEncoding
                  @(RegFieldsOf $recTy)
                  . gToRegFile
                  . Generics.from
                |]
          )
          []
      ]

  fromJSONSig <-
    sigD
      fromJSONN
      [t|Aeson.Value -> Either String $recTy|]
  fromJSONDef <-
    funD
      fromJSONN
      [ clause
          []
          ( normalB
              [|
                fmap (Generics.to . gFromRegFile)
                  . regFileFromJSON
                    @(RegFieldsOf $recTy)
                |]
          )
          []
      ]

  pure
    [ toJSONSig,
      toJSONDef,
      toEncSig,
      toEncDef,
      fromJSONSig,
      fromJSONDef
    ]

-- * Internal helpers ---------------------------------------------------------

-- | Lower-case the first character of the type name to produce the
-- conventional function-name prefix.
defaultPrefix :: Name -> String
defaultPrefix n = case nameBase n of
  [] -> error "deriveRegFileCodec: empty type name"
  (c : cs) -> toLower c : cs

-- | Validate that @tyName@ refers to a single-constructor record-syntax
-- @data@ or @newtype@ declaration. Reject every other shape with a
-- precise error message.
validateRecord :: Name -> Q ()
validateRecord tyName = do
  info <- reify tyName
  case info of
    TyConI dec -> case dec of
      DataD _ _ _ _ ctors _ ->
        validateCtors tyName ctors
      NewtypeD _ _ _ _ ctor _ ->
        validateCtors tyName [ctor]
      TySynD {} ->
        failure "a type synonym; only `data` and `newtype` are supported"
      _ ->
        failure
          ( "an unsupported declaration shape; only `data` and "
              <> "`newtype` are supported"
          )
    _ ->
      failure
        ( "not a type constructor; pass a record type name like "
            <> "''MyRecord"
        )
  where
    failure :: String -> Q a
    failure detail =
      fail $ "deriveRegFileCodec: " <> show tyName <> " is " <> detail

-- | Inspect the constructor list. Accept iff there is exactly one
-- constructor, and that constructor is either @RecC@ (record syntax
-- with named fields) or @NormalC@ with zero positional arguments
-- (the no-field singleton case).
validateCtors :: Name -> [Con] -> Q ()
validateCtors tyName ctors = case ctors of
  [RecC _ _] -> pure ()
  [NormalC _ []] -> pure ()
  [NormalC _ _] ->
    fail $
      "deriveRegFileCodec: "
        <> show tyName
        <> " has a positional (non-record-syntax) "
        <> "constructor; switch to record syntax so "
        <> "field names are available as slot symbols, "
        <> "e.g. `data Foo = Foo { x :: Int }`."
  [] ->
    fail $
      "deriveRegFileCodec: "
        <> show tyName
        <> " has no constructors; pass a record type."
  (_ : _ : _) ->
    fail $
      "deriveRegFileCodec: "
        <> show tyName
        <> " has multiple constructors; a single slot "
        <> "list cannot represent a sum type."
  _ ->
    fail $
      "deriveRegFileCodec: "
        <> show tyName
        <> " has an unsupported constructor shape "
        <> "(infix or GADT); pass a plain record type."
