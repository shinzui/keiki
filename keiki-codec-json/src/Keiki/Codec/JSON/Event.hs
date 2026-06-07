{-# LANGUAGE TemplateHaskell #-}

-- |
-- Module      : Keiki.Codec.JSON.Event
-- Description : Template Haskell that derives a @kind@-discriminated JSON
--               encoder/decoder skeleton for an event /sum/ type.
--
-- Where 'Keiki.Codec.JSON.TH.deriveRegFileCodec' handles a single-record
-- snapshot, this module handles an event sum — a @data@ type with several
-- constructors, each wrapping a single record payload (or a no-arg
-- singleton). For
--
-- > data OrderEvent
-- >   = Placed PlacedData
-- >   | Shipped ShippedData
-- >   | Cancelled
-- >   deriving stock (Eq, Show)
--
-- the splice @$(deriveEventCodecSkeleton opts ''OrderEvent)@ emits four
-- top-level bindings (prefix derived by lower-casing the first letter of the
-- type name):
--
-- > orderEventToJSON     :: OrderEvent -> Aeson.Value
-- > orderEventFromJSON   :: Aeson.Value -> Either String OrderEvent
-- > orderEventEventTypes :: [Data.Text.Text]                    -- ctor names, in order
-- > orderEventKindMap    :: [(Data.Text.Text, Data.Text.Text)]  -- (ctor, kind)
--
-- Each constructor encodes to a JSON object carrying a @"kind"@
-- discriminator (the constructor name) plus one entry per payload field.
-- The decoder reads @"kind"@, branches, and reassembles the payload field
-- by field.
--
-- == No silent generic fallback (the anti-drift property)
--
-- A payload field is encoded one of three ways, chosen by /field name/:
--
--   * if its name is a key of 'fieldCodecOverrides', the author-supplied
--     'FieldCodec' functions are spliced in;
--   * else if its name is in 'passthroughFields', the field's own
--     'Aeson.ToJSON' \/ 'Aeson.FromJSON' instances are used;
--   * otherwise the field is /unhandled/, and 'onMissingCodec' decides:
--     'FailAtCompileTime' (the default) aborts the splice listing every
--     unhandled field, while 'EmitTodoBindings' emits a clearly-named
--     @_todo_Event_field@ placeholder that compiles but is
--     @error "TODO: ..."@-bodied.
--
-- There is never a quiet generic guess: adding a field to a payload record
-- forces the author to make a decision at compile time.
--
-- This module lives in @keiki-codec-json@, not @keiki@ core, because the
-- generated code references @aeson@ and @keiki@ core must stay aeson-free
-- (EP-36 §3 R8; MP-11 Decision Log). It consumes no keiki-core symbols at
-- all; the constructor/field reflection mirrors @keiki@'s
-- @Keiki.Generics.TH@ (@conPayload@, @genTermFieldsRecord@) so the two stay
-- aligned.
--
-- == Negative-test procedure (manual)
--
-- See @Keiki.Codec.JSON.THEventSpec@ for the documented procedure that
-- exercises the 'FailAtCompileTime' and 'EmitTodoBindings' behaviours; the
-- two cases cannot live as a passing unit test because one is a compile
-- failure.
module Keiki.Codec.JSON.Event
  ( -- * Options
    FieldCodec (..),
    OnMissingCodec (..),
    EventCodecOptions (..),
    defaultEventCodecOptions,

    -- * Splices
    deriveEventCodecSkeleton,
    deriveEventCodecSkeletonAs,

    -- * Runtime helpers (referenced by generated code; not usually called directly)
    lookupField,
    lookupText,
    aesonResultToEither,
  )
where

import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Char (toLower)
import Data.List (intercalate)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Language.Haskell.TH

-- * Public option types ------------------------------------------------------

-- | A per-field encode/decode hook. Both fields name top-level functions
-- to splice in (so the hook is untyped at the TH boundary):
--
--   * 'fcEncode' names a function @fieldType -> Aeson.Value@ (e.g. @idText@);
--   * 'fcDecode' names a function @Aeson.Value -> Either String fieldType@
--     (e.g. @parseIdText@).
data FieldCodec = FieldCodec
  { fcEncode :: Name,
    fcDecode :: Name
  }

-- | What to do for a payload field whose name appears in neither
-- 'fieldCodecOverrides' nor 'passthroughFields'.
data OnMissingCodec
  = -- | Default: abort the splice with @fail@, listing every unhandled field.
    FailAtCompileTime
  | -- | Emit a named @_todo_\<Event\>_\<field\>@ stub and route the field
    --       through it, so the module compiles but any use throws an
    --       obviously-named @error@.
    EmitTodoBindings

-- | Options controlling 'deriveEventCodecSkeleton'.
data EventCodecOptions = EventCodecOptions
  { -- | keyed by payload field name (e.g. @"reservationId"@, @"divertStatus"@)
    fieldCodecOverrides :: Map String FieldCodec,
    -- | field names whose type already has aeson instances and may use them
    --     directly (e.g. @"sourceMessageId"@, @"lifeCriticalOverride"@)
    passthroughFields :: Set String,
    -- | the discriminator key; default @"kind"@
    kindFieldName :: String,
    -- | behaviour for unhandled fields; default 'FailAtCompileTime'
    onMissingCodec :: OnMissingCodec
  }

-- | Empty overrides, empty passthrough, @kindFieldName = "kind"@,
-- @onMissingCodec = 'FailAtCompileTime'@.
defaultEventCodecOptions :: EventCodecOptions
defaultEventCodecOptions =
  EventCodecOptions
    { fieldCodecOverrides = Map.empty,
      passthroughFields = Set.empty,
      kindFieldName = "kind",
      onMissingCodec = FailAtCompileTime
    }

-- * Runtime helpers (referenced by generated code) ---------------------------

-- | Look a key up in a JSON object, with a per-field error on absence.
lookupField :: Key.Key -> Aeson.Object -> Either String Aeson.Value
lookupField k o = case KeyMap.lookup k o of
  Just v -> Right v
  Nothing -> Left ("missing field: " <> Key.toString k)

-- | Look a key up and require its value to be a JSON string.
lookupText :: Key.Key -> Aeson.Object -> Either String Text
lookupText k o = do
  v <- lookupField k o
  case v of
    Aeson.String t -> Right t
    _ -> Left ("field " <> Key.toString k <> ": expected a string")

-- | Adapt aeson's 'Aeson.Result' to @Either String@.
aesonResultToEither :: Aeson.Result a -> Either String a
aesonResultToEither (Aeson.Success a) = Right a
aesonResultToEither (Aeson.Error e) = Left e

-- * Splices ------------------------------------------------------------------

-- | Derive the @kind@-discriminated codec skeleton for an event sum type,
-- with the function-name prefix derived from the type name by lower-casing
-- its first letter.
deriveEventCodecSkeleton :: EventCodecOptions -> Name -> Q [Dec]
deriveEventCodecSkeleton opts n = deriveEventCodecSkeletonAs (defaultPrefix n) opts n

-- | Variant of 'deriveEventCodecSkeleton' taking the prefix explicitly,
-- mirroring 'Keiki.Codec.JSON.TH.deriveRegFileCodecAs'.
deriveEventCodecSkeletonAs :: String -> EventCodecOptions -> Name -> Q [Dec]
deriveEventCodecSkeletonAs prefix opts tyName = do
  ctors <- reifyEventCtors tyName
  case ctors of
    [] ->
      fail $
        "deriveEventCodecSkeleton: "
          <> show tyName
          <> " has no constructors; pass an event sum type."
    _ -> pure ()

  -- No-silent-fallback safety net: classify each payload field; an
  -- unhandled field is one in neither overrides nor passthrough.
  let unhandled =
        [ (ecCtorName ec, fn, ft)
        | ec <- ctors,
          (_, fields) <- maybe [] (: []) (ecPayload ec),
          (fn, _sel, ft) <- fields,
          isUnhandled opts fn
        ]
  todoBindings <- case onMissingCodec opts of
    FailAtCompileTime
      | not (null unhandled) ->
          fail $
            "deriveEventCodecSkeleton: "
              <> show tyName
              <> " has field(s) with no provided codec and "
              <> "onMissingCodec = FailAtCompileTime:\n"
              <> intercalate
                "\n"
                [ "  - " <> nameBase c <> "." <> fn <> " :: " <> pprint ft
                | (c, fn, ft) <- unhandled
                ]
              <> "\nAdd each field to fieldCodecOverrides or passthroughFields, "
              <> "or set onMissingCodec = EmitTodoBindings."
      | otherwise -> pure []
    EmitTodoBindings -> concat <$> mapM mkTodoBinding unhandled

  let toJSONN = mkName (prefix <> "ToJSON")
      fromJSONN = mkName (prefix <> "FromJSON")
      eventTypesN = mkName (prefix <> "EventTypes")
      kindMapN = mkName (prefix <> "KindMap")
      tyT = conT tyName

  -- Encoder: one clause per constructor.
  toSig <- sigD toJSONN [t|$tyT -> Aeson.Value|]
  toDef <- funD toJSONN (map (encodeClause opts) ctors)

  -- Decoder: a single \v -> case ... clause.
  vVar <- newName "v"
  oVar <- newName "o"
  kVar <- newName "kind"
  fromSig <- sigD fromJSONN [t|Aeson.Value -> Either String $tyT|]
  fromDef <-
    funD
      fromJSONN
      [ clause
          [varP vVar]
          (normalB (decoderBody opts prefix vVar oVar kVar ctors))
          []
      ]

  -- Keiro-feeding surfaces: plain Text, no Keiro import.
  etSig <- sigD eventTypesN [t|[Text]|]
  etDef <-
    funD
      eventTypesN
      [ clause
          []
          ( normalB
              ( listE
                  [ [|T.pack $(stringE (nameBase (ecCtorName ec)))|]
                  | ec <- ctors
                  ]
              )
          )
          []
      ]
  kmSig <- sigD kindMapN [t|[(Text, Text)]|]
  kmDef <-
    funD
      kindMapN
      [ clause
          []
          ( normalB
              ( listE
                  [ [|(T.pack $(stringE nm), T.pack $(stringE nm))|]
                  | ec <- ctors,
                    let nm = nameBase (ecCtorName ec)
                  ]
              )
          )
          []
      ]

  pure $
    todoBindings
      <> [ toSig,
           toDef,
           fromSig,
           fromDef,
           etSig,
           etDef,
           kmSig,
           kmDef
         ]

-- * Encoder generation -------------------------------------------------------

-- | One @toJSON@ clause for a constructor.
encodeClause :: EventCodecOptions -> EvCtor -> Q Clause
encodeClause opts ec = case ecPayload ec of
  Nothing ->
    clause
      [conP (ecCtorName ec) []]
      (normalB [|Aeson.object [$(kindPair)]|])
      []
  Just (_pc, fields) -> do
    pVar <- newName "p"
    let pairs = kindPair : map (fieldPair opts (ecCtorName ec) pVar) fields
    clause
      [conP (ecCtorName ec) [varP pVar]]
      (normalB [|Aeson.object $(listE pairs)|])
      []
  where
    kindPair =
      [|
        $(keyE (kindFieldName opts))
          Aeson..= (T.pack $(stringE (nameBase (ecCtorName ec))) :: Text)
        |]

-- | One @"field" .= <encoded>@ pair.
fieldPair :: EventCodecOptions -> Name -> Name -> (String, Name, Type) -> Q Exp
fieldPair opts ctorName pVar f@(fn, _, _) =
  [|$(keyE fn) Aeson..= $(encodeFieldExpr opts ctorName pVar f)|]

-- | The encoded 'Aeson.Value' for one field of a constructor.
encodeFieldExpr :: EventCodecOptions -> Name -> Name -> (String, Name, Type) -> Q Exp
encodeFieldExpr opts ctorName pVar (fn, sel, _ft) =
  case classify opts fn of
    Override fc -> [|$(varE (fcEncode fc)) ($(varE sel) $(varE pVar))|]
    Passthrough -> [|Aeson.toJSON ($(varE sel) $(varE pVar))|]
    Unhandled ->
      [|($(varE (todoName ctorName fn)) ($(varE sel) $(varE pVar)) :: Aeson.Value)|]

-- * Decoder generation -------------------------------------------------------

-- | The full @fromJSON@ body: @case v of Object o -> ...; _ -> Left ...@.
decoderBody ::
  EventCodecOptions -> String -> Name -> Name -> Name -> [EvCtor] -> Q Exp
decoderBody opts prefix vVar oVar kVar ctors =
  caseE
    (varE vVar)
    [ match
        (conP 'Aeson.Object [varP oVar])
        ( normalB
            ( infixE
                (Just [|lookupText $(keyE (kindFieldName opts)) $(varE oVar)|])
                (varE '(>>=))
                (Just (lamE [varP kVar] (dispatch opts oVar kVar ctors)))
            )
        )
        [],
      match
        wildP
        (normalB [|Left $(stringE (prefix <> ": expected a JSON object"))|])
        []
    ]

-- | Nested @if kind == "C" then <build C> else ...@ ending in an
-- unknown-kind 'Left'.
dispatch :: EventCodecOptions -> Name -> Name -> [EvCtor] -> Q Exp
dispatch opts oVar kVar =
  foldr
    ( \ec elseQ ->
        [|
          if $(varE kVar) == T.pack $(stringE (nameBase (ecCtorName ec)))
            then $(buildCtorDecode opts oVar ec)
            else $elseQ
          |]
    )
    [|Left ("unknown event kind: " <> T.unpack $(varE kVar))|]

-- | Decode one constructor's payload: @C \<$> (PayloadCtor \<$> d1 \<*> ...)@.
buildCtorDecode :: EventCodecOptions -> Name -> EvCtor -> Q Exp
buildCtorDecode opts oVar ec = case ecPayload ec of
  Nothing -> [|Right $(conE (ecCtorName ec))|]
  Just (pc, fields) ->
    let decs = map (decodeFieldExpr opts oVar (ecCtorName ec)) fields
     in [|$(conE (ecCtorName ec)) <$> $(mkApplicative (conE pc) decs)|]

-- | Build @ctor \<$> d1 \<*> d2 \<*> ...@ (or @Right ctor@ for no fields)
-- in the @Either String@ applicative.
mkApplicative :: Q Exp -> [Q Exp] -> Q Exp
mkApplicative ctorQ [] = [|Right $ctorQ|]
mkApplicative ctorQ (d : ds) =
  foldl (\acc x -> [|$acc <*> $x|]) [|$ctorQ <$> $d|] ds

-- | @Either String fieldType@ decoder for one field.
decodeFieldExpr :: EventCodecOptions -> Name -> Name -> (String, Name, Type) -> Q Exp
decodeFieldExpr opts oVar ctorName (fn, _sel, _ft) =
  let getV = [|lookupField $(keyE fn) $(varE oVar)|]
   in case classify opts fn of
        Override fc -> [|$(varE (fcDecode fc)) =<< $getV|]
        Passthrough -> [|(aesonResultToEither . Aeson.fromJSON) =<< $getV|]
        Unhandled -> [|$(varE (todoName ctorName fn)) =<< $getV|]

-- * TODO bindings ------------------------------------------------------------

-- | The placeholder binding name for an unhandled field.
todoName :: Name -> String -> Name
todoName ctorName fn = mkName ("_todo_" <> nameBase ctorName <> "_" <> fn)

-- | Emit @_todo_C_field :: a; _todo_C_field = error "TODO: ..."@.
mkTodoBinding :: (Name, String, Type) -> Q [Dec]
mkTodoBinding (cn, fn, ft) = do
  let nm = todoName cn fn
      msg =
        "TODO: provide a FieldCodec for "
          <> nameBase cn
          <> "."
          <> fn
          <> " :: "
          <> pprint ft
  aV <- newName "a"
  sig <- sigD nm (varT aV)
  def <- funD nm [clause [] (normalB [|error $(stringE msg)|]) []]
  pure [sig, def]

-- * Field classification -----------------------------------------------------

-- | How one field is encoded/decoded.
data FieldClass
  = Override FieldCodec
  | Passthrough
  | Unhandled

classify :: EventCodecOptions -> String -> FieldClass
classify opts fn =
  case Map.lookup fn (fieldCodecOverrides opts) of
    Just fc -> Override fc
    Nothing
      | fn `Set.member` passthroughFields opts -> Passthrough
      | otherwise -> Unhandled

isUnhandled :: EventCodecOptions -> String -> Bool
isUnhandled opts fn =
  not (fn `Map.member` fieldCodecOverrides opts)
    && not (fn `Set.member` passthroughFields opts)

-- * Reflection ---------------------------------------------------------------

-- | A reflected event constructor: its name plus, for a payload
-- constructor, the payload record's data-constructor name and its
-- @(fieldName, selectorName, fieldType)@ list. 'Nothing' for a singleton.
data EvCtor = EvCtor
  { ecCtorName :: Name,
    ecPayload :: Maybe (Name, [(String, Name, Type)])
  }

reifyEventCtors :: Name -> Q [EvCtor]
reifyEventCtors tyName = do
  info <- reify tyName
  case info of
    TyConI (DataD _ _ _ _ ctors _) -> mapM (toEvCtor tyName) ctors
    TyConI (NewtypeD _ _ _ _ ctor _) -> mapM (toEvCtor tyName) [ctor]
    _ ->
      fail $
        "deriveEventCodecSkeleton: expected a data declaration for "
          <> show tyName
          <> ", got "
          <> show info

toEvCtor :: Name -> Con -> Q EvCtor
toEvCtor tyName con = case con of
  NormalC cn [] -> pure (EvCtor cn Nothing)
  NormalC cn [(_, payTy)] -> do
    payload <- reifyPayloadFields tyName cn payTy
    pure (EvCtor cn (Just payload))
  NormalC cn _ ->
    fail $
      "deriveEventCodecSkeleton: constructor "
        <> nameBase cn
        <> " of "
        <> show tyName
        <> " is multi-argument; wrap a single record payload "
        <> "type instead, e.g. `Placed PlacedData`."
  RecC cn _ ->
    fail $
      "deriveEventCodecSkeleton: constructor "
        <> nameBase cn
        <> " of "
        <> show tyName
        <> " uses record syntax directly; wrap a single record "
        <> "payload type instead, e.g. `Placed PlacedData`."
  _ ->
    fail $
      "deriveEventCodecSkeleton: "
        <> show tyName
        <> " has an unsupported constructor shape (infix or GADT)."

reifyPayloadFields :: Name -> Name -> Type -> Q (Name, [(String, Name, Type)])
reifyPayloadFields tyName cn payTy = do
  payName <- typeConName payTy
  info <- reify payName
  case info of
    TyConI (DataD _ _ _ _ [RecC pcn fs] _) -> pure (pcn, map field fs)
    TyConI (NewtypeD _ _ _ _ (RecC pcn fs) _) -> pure (pcn, map field fs)
    _ ->
      fail $
        "deriveEventCodecSkeleton: payload of constructor "
          <> nameBase cn
          <> " in "
          <> show tyName
          <> " must be a single record-syntax "
          <> "constructor type, got "
          <> show info
  where
    field (sel, _, ty) = (nameBase sel, sel, ty)

typeConName :: Type -> Q Name
typeConName (ConT n) = pure n
typeConName (SigT t _) = typeConName t
typeConName other =
  fail $
    "deriveEventCodecSkeleton: payload type must be a type constructor, "
      <> "got "
      <> show other

-- * Small helpers ------------------------------------------------------------

-- | Lower-case the first character of the type name for the conventional
-- function-name prefix.
defaultPrefix :: Name -> String
defaultPrefix n = case nameBase n of
  [] -> error "deriveEventCodecSkeleton: empty type name"
  (c : cs) -> toLower c : cs

-- | An 'Key.fromString'-built JSON key expression.
keyE :: String -> Q Exp
keyE s = [|Key.fromString $(stringE s)|]
