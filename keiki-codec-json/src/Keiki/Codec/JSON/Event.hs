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
-- the splice @$(deriveEventCodecSkeleton opts ''OrderEvent)@ emits five
-- top-level bindings (prefix derived by lower-casing the first letter of the
-- type name):
--
-- > orderEventToJSON     :: OrderEvent -> Aeson.Value
-- > orderEventFromJSON   :: Aeson.Value -> Either String OrderEvent
-- > orderEventEventTypes :: [Data.Text.Text]                    -- wire kinds, in order
-- > orderEventKindMap    :: [(Data.Text.Text, Data.Text.Text)]  -- (ctor, kind)
-- > orderEventSchemaVersion :: Int
--
-- Each constructor encodes to a JSON object carrying a @"kind"@
-- discriminator (the pinned wire kind, or the constructor name by default)
-- and an in-band @"v"@ schema version, plus one entry per payload field.
-- The decoder validates the stored version, runs every required whole-object
-- upcaster, then reads @"kind"@ and reassembles the payload field by field.
--
-- == No silent generic fallback (the anti-drift property)
--
-- A payload field is encoded one of three ways, chosen by /field name/:
--
--   * if its name is a key of 'fieldCodecOverrides', the author-supplied
--     'FieldCodec' functions are spliced in; an absent key uses
--     'fcOnMissing' when supplied and otherwise remains an error;
--   * else if its name is in 'passthroughFields', the field's own
--     'Aeson.ToJSON' \/ 'Aeson.FromJSON' instances are used. A field whose
--     reified type is syntactically @Maybe t@ decodes an absent key as
--     'Nothing'; type synonyms are not expanded, and all other passthrough
--     fields remain strict;
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
    fieldCodec,
    OnMissingCodec (..),
    EventCodecOptions (..),
    defaultEventCodecOptions,

    -- * Splices
    deriveEventCodecSkeleton,
    deriveEventCodecSkeletonAs,

    -- * Runtime helpers (referenced by generated code; not usually called directly)
    lookupField,
    lookupFieldMaybe,
    lookupText,
    lookupVersion,
    migrateEnvelope,
    aesonResultToEither,
  )
where

import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Char (toLower)
import Data.List (group, intercalate, sort, sortOn, (\\))
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Scientific qualified as Scientific
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
--     (e.g. @parseIdText@);
--   * 'fcOnMissing' optionally names a top-level /constant/ of the field type,
--     used only when the JSON key is absent.
data FieldCodec = FieldCodec
  { fcEncode :: Name,
    fcDecode :: Name,
    fcOnMissing :: Maybe Name
  }

-- | Construct a strict field codec with no missing-key default.
fieldCodec :: Name -> Name -> FieldCodec
fieldCodec encodeName decodeName =
  FieldCodec
    { fcEncode = encodeName,
      fcDecode = decodeName,
      fcOnMissing = Nothing
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
    -- | constructor base name to stable wire kind. Constructors omitted from
    --     this map use their Haskell name. Override keys and resolved wire kinds
    --     are validated when the splice runs.
    kindOverrides :: Map String String,
    -- | the in-band schema-version key; default @"v"@
    versionFieldName :: String,
    -- | current schema version stamped by the encoder; must be at least @1@
    currentVersion :: Int,
    -- | one whole-envelope migration per historical from-version. A version
    --     @n@ function upgrades to version @n + 1@; the splice requires exact
    --     coverage of @[1 .. currentVersion - 1]@.
    upcasters :: [(Int, Name)],
    -- | behaviour for unhandled fields; default 'FailAtCompileTime'
    onMissingCodec :: OnMissingCodec
  }

-- | Empty field and kind overrides, empty passthrough,
-- @kindFieldName = "kind"@, @versionFieldName = "v"@,
-- @currentVersion = 1@, no upcasters, and
-- @onMissingCodec = 'FailAtCompileTime'@.
defaultEventCodecOptions :: EventCodecOptions
defaultEventCodecOptions =
  EventCodecOptions
    { fieldCodecOverrides = Map.empty,
      passthroughFields = Set.empty,
      kindFieldName = "kind",
      kindOverrides = Map.empty,
      versionFieldName = "v",
      currentVersion = 1,
      upcasters = [],
      onMissingCodec = FailAtCompileTime
    }

-- * Runtime helpers (referenced by generated code) ---------------------------

-- | Look a key up in a JSON object, with a per-field error on absence.
lookupField :: Key.Key -> Aeson.Object -> Either String Aeson.Value
lookupField k o = case KeyMap.lookup k o of
  Just v -> Right v
  Nothing -> Left ("missing field: " <> Key.toString k)

-- | Total object lookup: 'Nothing' when the key is absent.
lookupFieldMaybe :: Key.Key -> Aeson.Object -> Maybe Aeson.Value
lookupFieldMaybe = KeyMap.lookup

-- | Look a key up and require its value to be a JSON string.
lookupText :: Key.Key -> Aeson.Object -> Either String Text
lookupText k o = do
  v <- lookupField k o
  case v of
    Aeson.String t -> Right t
    _ -> Left ("field " <> Key.toString k <> ": expected a string")

-- | Read an in-band schema version. An absent key means version @1@; a
-- present value must be an integral JSON number representable as an 'Int'.
lookupVersion :: Key.Key -> Aeson.Object -> Either String Int
lookupVersion k o = case KeyMap.lookup k o of
  Nothing -> Right 1
  Just (Aeson.Number number) ->
    maybe
      (Left expectedInteger)
      Right
      (Scientific.toBoundedInteger number)
  Just _ -> Left expectedInteger
  where
    expectedInteger =
      "field " <> Key.toString k <> ": expected an integer schema version"

-- | Replay a compile-time-complete chain from the stored version to the
-- current version. Rungs run in ascending source-version order; the only
-- expected runtime failure is a rung rejecting its input.
migrateEnvelope ::
  Int ->
  [(Int, Aeson.Value -> Either String Aeson.Value)] ->
  Int ->
  Aeson.Value ->
  Either String Aeson.Value
migrateEnvelope targetVersion chain storedVersion =
  go applicableRungs
  where
    applicableRungs =
      [ rung
      | rung@(fromVersion, _) <- sortOn fst chain,
        fromVersion >= storedVersion,
        fromVersion < targetVersion
      ]

    go [] value = Right value
    go ((fromVersion, upcast) : rest) value =
      case upcast value of
        Left message ->
          Left ("upcaster from version " <> show fromVersion <> ": " <> message)
        Right nextValue -> go rest nextValue

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

  validateWireKinds opts tyName ctors
  validateVersionEnvelope opts ctors
  validateUpcasters opts

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
      schemaVersionN = mkName (prefix <> "SchemaVersion")
      tyT = conT tyName

  -- Encoder: one clause per constructor.
  toSig <- sigD toJSONN [t|$tyT -> Aeson.Value|]
  toDef <- funD toJSONN (map (encodeClause opts) ctors)

  -- Decoder: a single \v -> case ... clause.
  vVar <- newName "v"
  oVar <- newName "o"
  kVar <- newName "kind"
  versionVar <- newName "version"
  fromSig <- sigD fromJSONN [t|Aeson.Value -> Either String $tyT|]
  fromDef <-
    funD
      fromJSONN
      [ clause
          [varP vVar]
          (normalB (decoderBody opts prefix vVar oVar kVar versionVar ctors))
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
                  [ [|T.pack $(stringE (wireKindOf opts (ecCtorName ec)))|]
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
                  [ [|
                      ( T.pack $(stringE (nameBase (ecCtorName ec))),
                        T.pack $(stringE (wireKindOf opts (ecCtorName ec)))
                      )
                      |]
                  | ec <- ctors
                  ]
              )
          )
          []
      ]
  svSig <- sigD schemaVersionN [t|Int|]
  svDef <-
    funD
      schemaVersionN
      [clause [] (normalB (litE (IntegerL (fromIntegral (currentVersion opts))))) []]

  pure $
    todoBindings
      <> [ toSig,
           toDef,
           fromSig,
           fromDef,
           etSig,
           etDef,
           kmSig,
           kmDef,
           svSig,
           svDef
         ]

-- * Encoder generation -------------------------------------------------------

-- | One @toJSON@ clause for a constructor.
encodeClause :: EventCodecOptions -> EvCtor -> Q Clause
encodeClause opts ec = case ecPayload ec of
  Nothing ->
    clause
      [conP (ecCtorName ec) []]
      (normalB [|Aeson.object [$(kindPair), $(versionPair)]|])
      []
  Just (_pc, fields) -> do
    pVar <- newName "p"
    let pairs =
          kindPair
            : versionPair
            : map (fieldPair opts (ecCtorName ec) pVar) fields
    clause
      [conP (ecCtorName ec) [varP pVar]]
      (normalB [|Aeson.object $(listE pairs)|])
      []
  where
    kindPair =
      [|
        $(keyE (kindFieldName opts))
          Aeson..= (T.pack $(stringE (wireKindOf opts (ecCtorName ec))) :: Text)
        |]
    versionPair =
      [|
        $(keyE (versionFieldName opts))
          Aeson..= ($(litE (IntegerL (fromIntegral (currentVersion opts)))) :: Int)
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
  EventCodecOptions -> String -> Name -> Name -> Name -> Name -> [EvCtor] -> Q Exp
decoderBody opts prefix vVar oVar kVar versionVar ctors =
  caseE
    (varE vVar)
    [ match
        (conP 'Aeson.Object [varP oVar])
        ( normalB
            ( infixE
                (Just [|lookupVersion $(keyE (versionFieldName opts)) $(varE oVar)|])
                (varE '(>>=))
                (Just (lamE [varP versionVar] versionGuard))
            )
        )
        [],
      match
        wildP
        (normalB [|Left $(stringE (prefix <> ": expected a JSON object"))|])
        []
    ]
  where
    currentVersionE = litE (IntegerL (fromIntegral (currentVersion opts)))
    dispatchMigrated migratedObjectVar =
      infixE
        ( Just
            [|
              lookupText
                $(keyE (kindFieldName opts))
                $(varE migratedObjectVar)
              |]
        )
        (varE '(>>=))
        ( Just
            ( lamE
                [varP kVar]
                (dispatch opts migratedObjectVar kVar ctors)
            )
        )
    migratedObjectCase migratedValueVar migratedObjectVar =
      caseE
        (varE migratedValueVar)
        [ match
            (conP 'Aeson.Object [varP migratedObjectVar])
            (normalB (dispatchMigrated migratedObjectVar))
            [],
          match
            wildP
            (normalB [|Left $(stringE (prefix <> ": expected a JSON object"))|])
            []
        ]
    migrateCurrent migratedValueVar migratedObjectVar =
      infixE
        ( Just
            [|
              migrateEnvelope
                ($currentVersionE :: Int)
                $(upcasterChainE opts)
                $(varE versionVar)
                (Aeson.Object $(varE oVar))
              |]
        )
        (varE '(>>=))
        ( Just
            ( lamE
                [varP migratedValueVar]
                (migratedObjectCase migratedValueVar migratedObjectVar)
            )
        )
    versionGuard = do
      migratedValueVar <- newName "migratedValue"
      migratedObjectVar <- newName "migratedObject"
      [|
        if $(varE versionVar) < 1
          then Left ("invalid event schema version: " <> show $(varE versionVar))
          else
            if $(varE versionVar) > ($currentVersionE :: Int)
              then
                Left
                  ( "event schema version "
                      <> show $(varE versionVar)
                      <> " is ahead of codec version "
                      <> show ($currentVersionE :: Int)
                  )
              else $(migrateCurrent migratedValueVar migratedObjectVar)
        |]

upcasterChainE :: EventCodecOptions -> Q Exp
upcasterChainE opts =
  listE
    [ [|($(litE (IntegerL (fromIntegral fromVersion))) :: Int, $(varE upcastName))|]
    | (fromVersion, upcastName) <- sortOn fst (upcasters opts)
    ]

-- | Nested @if kind == "C" then <build C> else ...@ ending in an
-- unknown-kind 'Left'.
dispatch :: EventCodecOptions -> Name -> Name -> [EvCtor] -> Q Exp
dispatch opts oVar kVar ctors =
  foldr
    ( \ec elseQ ->
        [|
          if $(varE kVar) == T.pack $(stringE (wireKindOf opts (ecCtorName ec)))
            then $(buildCtorDecode opts oVar ec)
            else $elseQ
          |]
    )
    [|
      Left
        ( "unknown event kind: "
            <> T.unpack $(varE kVar)
            <> $(stringE expectedKinds)
        )
      |]
    ctors
  where
    expectedKinds =
      " (expected one of: "
        <> intercalate ", " (map (wireKindOf opts . ecCtorName) ctors)
        <> ")"

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
decodeFieldExpr opts oVar ctorName (fn, _sel, ft) =
  let getV = [|lookupField $(keyE fn) $(varE oVar)|]
   in case classify opts fn of
        Override fc -> case fcOnMissing fc of
          Nothing -> [|$(varE (fcDecode fc)) =<< $getV|]
          Just missingDefault ->
            [|
              case lookupFieldMaybe $(keyE fn) $(varE oVar) of
                Nothing -> Right $(varE missingDefault)
                Just fieldValue -> $(varE (fcDecode fc)) fieldValue
              |]
        Passthrough
          | isSyntacticMaybe ft ->
              [|
                case lookupFieldMaybe $(keyE fn) $(varE oVar) of
                  Nothing -> Right Nothing
                  Just fieldValue -> aesonResultToEither (Aeson.fromJSON fieldValue)
                |]
          | otherwise -> [|(aesonResultToEither . Aeson.fromJSON) =<< $getV|]
        Unhandled -> [|$(varE (todoName ctorName fn)) =<< $getV|]

isSyntacticMaybe :: Type -> Bool
isSyntacticMaybe (SigT ty _) = isSyntacticMaybe ty
isSyntacticMaybe (ParensT ty) = isSyntacticMaybe ty
isSyntacticMaybe (AppT (ConT maybeName) _) = maybeName == ''Maybe
isSyntacticMaybe _ = False

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

-- * Wire-kind validation ----------------------------------------------------

wireKindOf :: EventCodecOptions -> Name -> String
wireKindOf opts ctorName =
  Map.findWithDefault ctorBase ctorBase (kindOverrides opts)
  where
    ctorBase = nameBase ctorName

validateWireKinds :: EventCodecOptions -> Name -> [EvCtor] -> Q ()
validateWireKinds opts tyName ctors = do
  case unknownOverrideKeys of
    [] -> pure ()
    unknownKeys ->
      fail . intercalate "\n" $
        [ "deriveEventCodecSkeleton: kindOverrides key "
            <> show key
            <> " is not a constructor of "
            <> nameBase tyName
            <> "."
        | key <- unknownKeys
        ]

  case duplicateWireKinds of
    [] -> pure ()
    duplicates ->
      fail . intercalate "\n" $
        [ "deriveEventCodecSkeleton: wire kind "
            <> show wireKind
            <> " is claimed by more than one constructor: "
            <> intercalate ", " owners
            <> ". Wire kinds must be unique per event type."
        | (wireKind, owners) <- duplicates
        ]

  case discriminatorCollisions of
    [] -> pure ()
    collisions ->
      fail . intercalate "\n" $
        [ "deriveEventCodecSkeleton: payload field "
            <> nameBase ctorName
            <> "."
            <> fieldName
            <> " collides with kindFieldName "
            <> show (kindFieldName opts)
            <> "; rename the field or choose a kindFieldName no payload uses."
        | (ctorName, fieldName) <- collisions
        ]
  where
    ctorBaseNames = map (nameBase . ecCtorName) ctors
    knownConstructors = Set.fromList ctorBaseNames
    unknownOverrideKeys =
      Set.toList (Map.keysSet (kindOverrides opts) `Set.difference` knownConstructors)
    wireKindOwners =
      Map.fromListWith
        (flip (<>))
        [ (wireKindOf opts (ecCtorName ec), [nameBase (ecCtorName ec)])
        | ec <- ctors
        ]
    duplicateWireKinds =
      [ (wireKind, owners)
      | (wireKind, owners) <- Map.toList wireKindOwners,
        length owners > 1
      ]
    discriminatorCollisions =
      [ (ecCtorName ec, fieldName)
      | ec <- ctors,
        (_, fields) <- maybe [] (: []) (ecPayload ec),
        (fieldName, _, _) <- fields,
        fieldName == kindFieldName opts
      ]

validateVersionEnvelope :: EventCodecOptions -> [EvCtor] -> Q ()
validateVersionEnvelope opts ctors = do
  if currentVersion opts < 1
    then
      fail $
        "deriveEventCodecSkeleton: currentVersion must be >= 1, got "
          <> show (currentVersion opts)
          <> "."
    else pure ()

  if kindFieldName opts == versionFieldName opts
    then
      fail $
        "deriveEventCodecSkeleton: kindFieldName "
          <> show (kindFieldName opts)
          <> " collides with versionFieldName "
          <> show (versionFieldName opts)
          <> "; choose distinct envelope keys."
    else pure ()

  case versionCollisions of
    [] -> pure ()
    collisions ->
      fail . intercalate "\n" $
        [ "deriveEventCodecSkeleton: payload field "
            <> nameBase ctorName
            <> "."
            <> fieldName
            <> " collides with versionFieldName "
            <> show (versionFieldName opts)
            <> "; rename the field or choose a versionFieldName no payload uses."
        | (ctorName, fieldName) <- collisions
        ]
  where
    versionCollisions =
      [ (ecCtorName ec, fieldName)
      | ec <- ctors,
        (_, fields) <- maybe [] (: []) (ecPayload ec),
        (fieldName, _, _) <- fields,
        fieldName == versionFieldName opts
      ]

validateUpcasters :: EventCodecOptions -> Q ()
validateUpcasters opts = do
  case duplicateSources of
    [] -> pure ()
    duplicates ->
      fail $
        "deriveEventCodecSkeleton: duplicate upcaster from-versions: "
          <> show duplicates

  case outOfRangeSources of
    [] -> pure ()
    invalidSources ->
      fail $
        "deriveEventCodecSkeleton: upcaster from-versions must be >= 1 and < currentVersion "
          <> show (currentVersion opts)
          <> "; out of range: "
          <> show invalidSources

  case missingSources of
    [] -> pure ()
    missing ->
      fail $
        "deriveEventCodecSkeleton: upcasters must cover from-versions [1.."
          <> show (currentVersion opts - 1)
          <> "] exactly; missing: "
          <> show missing
  where
    sources = map fst (upcasters opts)
    expectedSources = [1 .. currentVersion opts - 1]
    duplicateSources =
      [ source
      | source : _ : _ <- group (sort sources)
      ]
    outOfRangeSources =
      [ source
      | source <- sort sources,
        source < 1 || source >= currentVersion opts
      ]
    missingSources = expectedSources \\ sources

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
