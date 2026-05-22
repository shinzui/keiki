{-# LANGUAGE TemplateHaskell #-}

-- | Template Haskell splices that retire the per-constructor authoring
-- boilerplate at the example layer.
--
-- 'deriveAggregateCtors' emits, for each entry in its spec list, the
-- three top-level declarations a command constructor needs in the
-- keiki DSL: an 'InCtor' value, an @inp@ field projection, and an
-- @is@ guard predicate. Singleton (no-payload) constructors get
-- 'InCtor' and the guard only — there is no field projection because
-- @'Index' '[]@ is uninhabited.
--
-- 'deriveWireCtors' is the dual on the event side, emitting one
-- 'WireCtor' value per spec entry.
--
-- Both splices read the constructor list of the named sum type via
-- 'reify' and dispatch on the constructor's payload shape: zero-arg
-- 'NormalC' is a singleton; one-arg 'NormalC' takes a record-payload
-- type. Record-syntax constructors ('RecC') and multi-arg 'NormalC'
-- are rejected with a precise error.
--
-- == Worked example
--
-- @
-- data UserCmd
--   = StartRegistration  StartRegistrationData
--   | ConfirmAccount     ConfirmAccountData
--   | ResendConfirmation ResendConfirmationData
--   | FulfillGDPRRequest FulfillGDPRRequestData
--   | Continue
--   deriving ('Eq', 'Show', 'GHC.Generics.Generic')
--
-- $('deriveAggregateCtors' \'\'UserCmd \'\'UserRegRegs
--     [ ("StartRegistration",  "Start")
--     , ("ConfirmAccount",     "Confirm")
--     , ("ResendConfirmation", "Resend")
--     , ("FulfillGDPRRequest", "Gdpr")
--     , ("Continue",           "Continue")
--     ])
-- @
--
-- expands to the same 14 declarations a hand-written module ships
-- (4 record ctors × 3 decls + 1 singleton × 2 decls).
module Keiki.Generics.TH
  ( deriveAggregateCtors
  , deriveWireCtors
  , deriveView
  ) where

import Data.Char (isUpper, toLower, toUpper)
import Data.List (group, nub, sort, (\\))
import Language.Haskell.TH
import Keiki.Core
  ( HsPred
  , InCtor
  , Index
  , OutFields (..)
  , RegFile
  , Term (..)
  , WireCtor
  , (!)
  , matchInCtor
  )
import Keiki.Builder (ToOutFields (..))
import Keiki.Generics
  ( FieldsOf
  , RegFieldsOf
  , mkInCtor0
  , mkInCtorVia
  , mkWireCtor0
  , mkWireCtorVia
  )


-- | Generate per-constructor @inCtor<Short>@, @inp<Short>@,
-- @is<Short>@ declarations from a command sum type and a register-file
-- slot list. Spec entries are @(constructorName, shortName)@ pairs;
-- the short name is appended to the @inCtor@/@inp@/@is@ prefix.
--
-- Singleton constructors (zero-arg 'NormalC') emit only @inCtor@ and
-- @is@; @inp@ is omitted because @'Index' '[]@ is uninhabited.
deriveAggregateCtors
  :: Name              -- ^ command sum type, e.g. @\'\'UserCmd@
  -> Name              -- ^ register-file slot list, e.g. @\'\'UserRegRegs@
  -> [(String, String)]
                       -- ^ pairs of (constructor name, short name)
  -> Q [Dec]
deriveAggregateCtors cmdName regsName specs = do
  ctors <- reifyCtors cmdName "deriveAggregateCtors"
  let ctorMap = [ (nameBase n, c) | c <- ctors, n <- conNames c ]
  fmap concat . mapM (genCtor cmdName regsName ctorMap) $ specs


-- | Generate per-constructor @wire<Short>@ declarations from an event
-- sum type. Spec entries are @(constructorName, shortName)@ pairs.
-- Every event constructor must have a single record payload;
-- singleton events are not currently supported.
deriveWireCtors
  :: Name              -- ^ event sum type, e.g. @\'\'UserEvent@
  -> [(String, String)]
                       -- ^ pairs of (constructor name, short name)
  -> Q [Dec]
deriveWireCtors evtName specs = do
  ctors <- reifyCtors evtName "deriveWireCtors"
  let ctorMap = [ (nameBase n, c) | c <- ctors, n <- conNames c ]
  fmap concat . mapM (genWire evtName ctorMap) $ specs


-- | Generate the per-aggregate B-presentation view: a singletons GADT
-- (one constructor per vertex, indexed by the promoted vertex type),
-- a per-vertex View GADT (one constructor per vertex carrying the
-- live slots as record fields), and the projection function
-- @viewFor :: SVertex v -> RegFile rs -> View v@.
--
-- See @docs/research/genview-th-splice-design.md@ for the full
-- design — splice signature, spec format, validation rules, and
-- worked expansion against 'Jitsurei.UserRegistration'.
--
-- == Worked invocation
--
-- @
-- $('deriveView' \'\'Vertex \'\'UserRegRegs
--     "SUserVertex" "UserView" "userView"
--     [ ("PotentialCustomer",    [])
--     , ("Registering",          [])
--     , ("RequiresConfirmation", ["email", "confirmCode"])
--     , ("Confirmed",            ["email", "confirmedAt"])
--     , ("Deleted",              ["email", "deletedAt"])
--     ])
-- @
deriveView
  :: Name              -- ^ vertex enum, e.g. @\'\'Vertex@
  -> Name              -- ^ register-file slot list, e.g. @\'\'UserRegRegs@
  -> String            -- ^ name of the singletons GADT to generate,
                       --   e.g. @"SUserVertex"@
  -> String            -- ^ name of the View GADT, e.g. @"UserView"@
  -> String            -- ^ name of the projection function,
                       --   e.g. @"userView"@
  -> [(String, [String])]
                       -- ^ per-vertex spec: pairs of
                       --   (vertex constructor name,
                       --    list of slot names live in that vertex)
  -> Q [Dec]
deriveView vertexName regsName sVertexNameStr viewNameStr
           viewFunNameStr spec = do
  -- Phase 1: reify the vertex enum.
  ctors <- reifyCtors vertexName "deriveView"
  let vertexCtorNames = concatMap conNames ctors
      vertexCtorByBase =
        [ (nameBase n, n) | n <- vertexCtorNames ]
  -- Phase 2: reify the slot list.
  slotPairs <- reifySlotList regsName
  let slotNamesInRegs = map fst slotPairs
  -- Phase 3: validate (five checks).
  validateSpecCoverage vertexName vertexCtorNames spec
  validateSpecSlots regsName slotNamesInRegs spec
  validatePrefixUniqueness spec
  -- Phase 4: code-gen.
  let sVertexN   = mkName sVertexNameStr
      viewN      = mkName viewNameStr
      viewFunN   = mkName viewFunNameStr
      vIdx       = mkName "v"
      vertexCtor name = case lookup name vertexCtorByBase of
        Just n  -> n
        Nothing -> error $ "deriveView: bug — validated vertex "
                        <> show name <> " missing from reified ctor list"
      slotType slotName = case lookup slotName slotPairs of
        Just t  -> t
        Nothing -> error $ "deriveView: bug — validated slot "
                        <> show slotName <> " missing from reified slot list"

  -- (a) Singletons GADT.
  let sCtors =
        [ GadtC [mkName ("S" <> vName)] []
            (AppT (ConT sVertexN) (PromotedT (vertexCtor vName)))
        | (vName, _) <- spec
        ]
      sDataDec = DataD [] sVertexN
                       [KindedTV vIdx BndrReq (ConT vertexName)]
                       Nothing sCtors []
      sShowDec = StandaloneDerivD Nothing []
                   (AppT (ConT ''Show)
                         (AppT (ConT sVertexN) (VarT vIdx)))
      sEqDec   = StandaloneDerivD Nothing []
                   (AppT (ConT ''Eq)
                         (AppT (ConT sVertexN) (VarT vIdx)))

  -- (b) View GADT.
  let lazyBang = Bang NoSourceUnpackedness NoSourceStrictness
      mkViewCtor (vName, slots) =
        let viewCtorN = mkName (vName <> "V")
            resultT   = AppT (ConT viewN) (PromotedT (vertexCtor vName))
            prefix    = vertexFieldPrefix vName
        in case slots of
             [] -> GadtC [viewCtorN] [] resultT
             _  -> RecGadtC [viewCtorN]
                     [ ( mkName (vertexFieldName prefix s)
                       , lazyBang
                       , slotType s
                       )
                     | s <- slots
                     ] resultT
      viewCtors  = map mkViewCtor spec
      viewDataDec = DataD [] viewN
                          [KindedTV vIdx BndrReq (ConT vertexName)]
                          Nothing viewCtors []
      viewShowDec = StandaloneDerivD Nothing []
                      (AppT (ConT ''Show)
                            (AppT (ConT viewN) (VarT vIdx)))
      viewEqDec   = StandaloneDerivD Nothing []
                      (AppT (ConT ''Eq)
                            (AppT (ConT viewN) (VarT vIdx)))

  -- (c) Projection function.
  let regsTy   = AppT (ConT ''RegFile) (ConT regsName)
      funTy    = ForallT [PlainTV vIdx SpecifiedSpec] []
                   (arrows [ AppT (ConT sVertexN) (VarT vIdx)
                           , regsTy
                           , AppT (ConT viewN) (VarT vIdx)
                           ])
      viewFunSig = SigD viewFunN funTy
  regsVar <- newName "regs"
  let mkClause (vName, slots) =
        let sCtorN    = mkName ("S" <> vName)
            viewCtorN = mkName (vName <> "V")
            (regsPat, body) = case slots of
              [] -> (WildP, ConE viewCtorN)
              _  ->
                let reads_ = [ AppE (AppE (VarE '(!))
                                          (VarE regsVar))
                                    (LabelE s)
                             | s <- slots
                             ]
                in (VarP regsVar, foldl AppE (ConE viewCtorN) reads_)
        in Clause [ConP sCtorN [] [], regsPat] (NormalB body) []
      viewFunDef = FunD viewFunN (map mkClause spec)

  pure
    [ sDataDec, sShowDec, sEqDec
    , viewDataDec, viewShowDec, viewEqDec
    , viewFunSig, viewFunDef
    ]
  where
    arrows :: [Type] -> Type
    arrows []     = error "deriveView: arrows on empty list"
    arrows [t]    = t
    arrows (t:ts) = AppT (AppT ArrowT t) (arrows ts)


-- | Field name from a vertex prefix and a slot name:
-- @\"<prefix><Slot>\"@ where the slot name's first letter is
-- upper-cased.
vertexFieldName :: String -> String -> String
vertexFieldName prefix slotName = case slotName of
  []     -> prefix
  (c:cs) -> prefix <> (toUpper c : cs)


-- * Internal helpers -----------------------------------------------------


reifyCtors :: Name -> String -> Q [Con]
reifyCtors n caller = do
  info <- reify n
  case info of
    TyConI (DataD _ _ _ _ ctors _) -> pure ctors
    _ -> fail $ caller <> ": expected a data declaration for "
             <> show n <> ", got " <> show info


conNames :: Con -> [Name]
conNames (NormalC n _)  = [n]
conNames (RecC n _)     = [n]
conNames (InfixC _ n _) = [n]
conNames _              = []


-- | Three-state classification of a constructor's payload.
--
--   * @Just Nothing@  — singleton (zero-arg 'NormalC').
--   * @Just (Just t)@ — single-arg 'NormalC' with payload type @t@.
--   * @Nothing@       — record-syntax or multi-arg ctor (unsupported).
conPayload :: Con -> Maybe (Maybe Type)
conPayload (NormalC _ [])         = Just Nothing
conPayload (NormalC _ [(_, t)])   = Just (Just t)
conPayload _                      = Nothing


genCtor
  :: Name
  -> Name
  -> [(String, Con)]
  -> (String, String)
  -> Q [Dec]
genCtor cmdName regsName ctorMap (ctorStr, shortStr) =
  case lookup ctorStr ctorMap of
    Nothing -> fail $ "deriveAggregateCtors: ctor " <> show ctorStr
                   <> " not found in " <> show cmdName
    Just con -> case conPayload con of
      Nothing -> fail $ "deriveAggregateCtors: ctor " <> show ctorStr
                     <> " has unsupported shape (multi-arg or record-syntax)"
      Just Nothing ->
        case conNames con of
          (cn : _) -> singletonDecls cmdName regsName ctorStr shortStr cn
          []       -> fail $ "deriveAggregateCtors: could not extract "
                          <> "ctor name for " <> show ctorStr
      Just (Just payTy) ->
        recordDecls cmdName regsName ctorStr shortStr payTy


singletonDecls
  :: Name -> Name -> String -> String -> Name -> Q [Dec]
singletonDecls cmdName regsName ctorStr shortStr ctorN = do
  let inCtorN = mkName ("inCtor" <> shortStr)
      isN     = mkName ("is"     <> shortStr)
  inCtorSig <- sigD inCtorN
                 [t| InCtor $(conT cmdName) '[] |]
  inCtorDef <- funD inCtorN
                 [ clause [] (normalB
                     [| mkInCtor0 $(litE (stringL ctorStr))
                                  $(conE ctorN) |])
                     []
                 ]
  isSig     <- sigD isN
                 [t| HsPred $(conT regsName) $(conT cmdName) |]
  isDef     <- funD isN
                 [ clause [] (normalB
                     [| matchInCtor $(varE inCtorN) |])
                     []
                 ]
  pure [inCtorSig, inCtorDef, isSig, isDef]


recordDecls
  :: Name -> Name -> String -> String -> Type -> Q [Dec]
recordDecls cmdName regsName ctorStr shortStr payTy = do
  let inCtorN = mkName ("inCtor" <> shortStr)
      inpN    = mkName ("inp"    <> shortStr)
      isN     = mkName ("is"     <> shortStr)
      slotsT  = [t| RegFieldsOf $(pure payTy) |]
  r <- newName "r"
  inCtorSig <- sigD inCtorN
                 [t| InCtor $(conT cmdName) $slotsT |]
  inCtorDef <- funD inCtorN
                 [ clause [] (normalB
                     (appTypeE [| mkInCtorVia |]
                               (litT (strTyLit ctorStr))))
                     []
                 ]
  inpSig    <- sigD inpN
                 [t| Index $slotsT $(varT r)
                       -> Term $(conT regsName) $(conT cmdName) $(varT r) |]
  inpDef    <- funD inpN
                 [ clause [] (normalB
                     [| TInpCtorField $(varE inCtorN) |])
                     []
                 ]
  isSig     <- sigD isN
                 [t| HsPred $(conT regsName) $(conT cmdName) |]
  isDef     <- funD isN
                 [ clause [] (normalB
                     [| matchInCtor $(varE inCtorN) |])
                     []
                 ]
  pure [inCtorSig, inCtorDef, inpSig, inpDef, isSig, isDef]


genWire
  :: Name
  -> [(String, Con)]
  -> (String, String)
  -> Q [Dec]
genWire evtName ctorMap (ctorStr, shortStr) =
  case lookup ctorStr ctorMap of
    Nothing -> fail $ "deriveWireCtors: ctor " <> show ctorStr
                   <> " not found in " <> show evtName
    Just con -> case conPayload con of
      Just (Just payTy) -> do
        let wireN = mkName ("wire" <> shortStr)
        wireSig <- sigD wireN
                     [t| WireCtor $(conT evtName)
                                  (FieldsOf $(pure payTy)) |]
        wireDef <- funD wireN
                     [ clause [] (normalB
                         (appTypeE [| mkWireCtorVia |]
                                   (litT (strTyLit ctorStr))))
                         []
                     ]
        termRecDecs <- genTermFieldsRecord shortStr payTy
        pure ([wireSig, wireDef] ++ termRecDecs)
      Just Nothing ->
        -- Zero-arg (singleton) event: emit only the wire<Short> binding
        -- via mkWireCtor0 (no payload, so no <Short>TermFields record).
        -- Mirrors the command side's singletonDecls/mkInCtor0.
        case conNames con of
          (cn : _) -> do
            let wireN = mkName ("wire" <> shortStr)
            wireSig <- sigD wireN
                         [t| WireCtor $(conT evtName) () |]
            wireDef <- funD wireN
                         [ clause [] (normalB
                             [| mkWireCtor0 $(litE (stringL ctorStr))
                                            $(conE cn) |])
                             []
                         ]
            pure [wireSig, wireDef]
          [] -> fail $ "deriveWireCtors: could not extract ctor name for "
                    <> show ctorStr
      Nothing -> fail $ "deriveWireCtors: ctor " <> show ctorStr
               <> " has unsupported payload shape "
               <> "(multi-arg or record-syntax)"


-- | Per-event field-keyed record for 'B.emit' (EP-21 M4).
--
-- For each event ctor with a record payload @<Pay>@ whose fields are
-- @f1 :: T1@, @f2 :: T2@, ..., @fn :: Tn@, this emits two decls:
--
-- > data <Short>TermFields rs ci = <Short>TermFields
-- >   { f1 :: Term rs ci T1
-- >   , f2 :: Term rs ci T2
-- >   , ...
-- >   }
--
-- > instance ToOutFields (<Short>TermFields rs ci) rs ci
-- >                      (FieldsOf <Pay>) where
-- >   toOutFields <Short>TermFields { f1 = v1, f2 = v2, ... } =
-- >     OFCons v1 (OFCons v2 ... OFNil)
--
-- Field-name disambiguation across multiple events with shared
-- field names is handled by 'DuplicateRecordFields' (already on at
-- the project level); the record pattern in the instance body
-- pins the constructor explicitly so the field lookup is
-- unambiguous.
genTermFieldsRecord :: String -> Type -> Q [Dec]
genTermFieldsRecord shortStr payTy = do
  payName <- typeConstructorName payTy
  payInfo <- reify payName
  fields  <- case payInfo of
    TyConI (DataD _ _ _ _ [RecC _ fs] _) -> pure fs
    TyConI (NewtypeD _ _ _ _ (RecC _ fs) _) -> pure fs
    _ -> fail $ "deriveWireCtors: TermFields generation requires "
             <> "a single record-syntax constructor on payload "
             <> show payName <> ", got " <> show payInfo
  let recName = mkName (shortStr <> "TermFields")
  rsN <- newName "rs"
  ciN <- newName "ci"
  let lazyBang = Bang NoSourceUnpackedness NoSourceStrictness
      mkField (selN, _, ty) =
        ( mkName (nameBase selN)
        , lazyBang
        , ConT ''Term `AppT` VarT rsN `AppT` VarT ciN `AppT` ty
        )
      recCtor   = RecC recName (map mkField fields)
      recDataDec = DataD [] recName
                          [ PlainTV rsN BndrReq
                          , PlainTV ciN BndrReq
                          ]
                          Nothing [recCtor] []
      recTy = ConT recName `AppT` VarT rsN `AppT` VarT ciN
      -- The 'OutFields' type's @fs@ parameter is the same nested-
      -- pair tuple @FieldsOf <Pay>@ reduces to. Compute it
      -- explicitly so the instance head does not carry a type-
      -- family application (which GHC rejects in instance heads).
      fsTy  = mkNestedPairTuple [ty | (_, _, ty) <- fields]
      instHead = ConT ''ToOutFields
                  `AppT` recTy
                  `AppT` VarT rsN
                  `AppT` VarT ciN
                  `AppT` fsTy
  vars <- mapM (\(selN, _, _) -> newName ("v_" <> nameBase selN)) fields
  let recPat   = RecP recName
                   [ (mkName (nameBase fn), VarP vn)
                   | ((fn, _, _), vn) <- zip fields vars
                   ]
      buildBody []     = ConE 'OFNil
      buildBody (v:vs) = ConE 'OFCons `AppE` VarE v `AppE` buildBody vs
      methodDef = FunD 'toOutFields
                    [Clause [recPat] (NormalB (buildBody vars)) []]
      instDec = InstanceD Nothing [] instHead [methodDef]
  pure [recDataDec, instDec]


-- | Extract a type's head constructor name. Accepts @ConT@ and the
-- common forms it might wear after kind-elaboration; rejects
-- function/forall/promoted shapes.
typeConstructorName :: Type -> Q Name
typeConstructorName (ConT n)   = pure n
typeConstructorName (SigT t _) = typeConstructorName t
typeConstructorName other =
  fail $ "deriveWireCtors: payload type must be a type constructor, "
      <> "got " <> show other


-- | Build the nested-pair tuple type @(t1, (t2, ..., (tn, ())))@
-- from a list of element types. This is the same shape that
-- 'Keiki.Generics.FieldsOf' reduces a record's 'Rep' to, computed
-- explicitly here so instance heads that mention the shape avoid
-- the type-family application GHC rejects.
mkNestedPairTuple :: [Type] -> Type
mkNestedPairTuple []     = TupleT 0
mkNestedPairTuple (t:ts) = AppT (AppT (TupleT 2) t) (mkNestedPairTuple ts)


-- * deriveView internals -------------------------------------------------


-- | Walk a type-synonym whose right-hand side is a promoted @[Slot]@
-- list, extracting the @(slotName, slotType)@ pairs. The walk
-- pattern-matches @PromotedConsT@ \/ @PromotedNilT@ at the list level
-- and @PromotedTupleT 2@ over @LitT (StrTyLit name)@ + slot type at
-- each cell.
reifySlotList :: Name -> Q [(String, Type)]
reifySlotList n = do
  info <- reify n
  case info of
    TyConI (TySynD _ _ rhs) -> walkList rhs
    _ -> fail $ "deriveView: expected a type synonym for "
             <> show n <> " whose right-hand side is a promoted "
             <> "[Slot] list, got " <> show info
  where
    walkList :: Type -> Q [(String, Type)]
    walkList (SigT t _) = walkList t
    walkList PromotedNilT = pure []
    walkList (AppT (AppT PromotedConsT headPair) tailList) = do
      pair <- walkPair headPair
      rest <- walkList tailList
      pure (pair : rest)
    walkList other =
      fail $ "deriveView: expected a promoted-list type at "
          <> show n <> ", got " <> show other

    walkPair :: Type -> Q (String, Type)
    walkPair (SigT t _) = walkPair t
    walkPair (AppT (AppT (PromotedTupleT 2) (LitT (StrTyLit name))) ty) =
      pure (name, ty)
    walkPair other =
      fail $ "deriveView: expected a promoted (Symbol, Type) pair "
          <> "in slot list of " <> show n <> ", got " <> show other


-- | Validate that the spec lists every vertex constructor exactly
-- once. Missing, extra, and duplicate spec entries each produce a
-- precise message naming the offenders.
validateSpecCoverage
  :: Name -> [Name] -> [(String, [String])] -> Q ()
validateSpecCoverage vertexName vertexCtorNames spec = do
  let vertexNames = map nameBase vertexCtorNames
      specNames   = map fst spec
      duplicates  = [ n | (n : _ : _) <- group (sort specNames) ]
      missing     = vertexNames \\ specNames
      extras      = specNames   \\ vertexNames
  case duplicates of
    [] -> pure ()
    _  -> fail $ "deriveView: spec lists vertex(es) " <> showList' duplicates
              <> " more than once"
  case missing of
    [] -> pure ()
    _  -> fail $ "deriveView: spec is missing constructors of "
              <> show vertexName <> ": " <> showList' missing
  case extras of
    [] -> pure ()
    _  -> fail $ "deriveView: spec names constructors not in "
              <> show vertexName <> ": " <> showList' extras


-- | Validate that every named slot exists in the register-file slot
-- list, and that no spec entry names the same slot twice.
validateSpecSlots
  :: Name -> [String] -> [(String, [String])] -> Q ()
validateSpecSlots regsName slotNamesInRegs spec =
  mapM_ checkOne spec
  where
    checkOne (vertexCtorName, slots) = do
      let dupSlots = [ s | (s : _ : _) <- group (sort slots) ]
      case dupSlots of
        [] -> pure ()
        _  -> fail $ "deriveView: spec entry " <> show vertexCtorName
                  <> " lists slot(s) " <> showList' dupSlots
                  <> " more than once"
      let missing = slots \\ slotNamesInRegs
      case missing of
        [] -> pure ()
        _  -> fail $ "deriveView: spec entry " <> show vertexCtorName
                  <> " names slot(s) " <> showList' missing
                  <> " which are not slots of " <> show regsName
                  <> "; known slots: " <> showList' slotNamesInRegs


-- | Validate that the per-vertex field-name prefixes
-- (@filter isUpper >>> map toLower@) are pairwise distinct so the
-- generated View GADT has no field-name collisions across
-- constructors.
validatePrefixUniqueness :: [(String, [String])] -> Q ()
validatePrefixUniqueness spec =
  case collisions of
    []                -> pure ()
    ((pref, ns) : _)  ->
      fail $ "deriveView: vertices " <> showList' ns
          <> " produce the same field-name prefix " <> show pref
          <> "; rename one"
  where
    prefixed   = [ (vertexFieldPrefix n, n) | (n, _) <- spec ]
    collisions =
      [ (pref, [ n | (p', n) <- prefixed, p' == pref ])
      | pref <- nub (map fst prefixed)
      , length [ () | (p', _) <- prefixed, p' == pref ] > 1
      ]


-- | Field-name prefix for a vertex name: lower-cased concatenation
-- of the vertex name's upper-case letters. Examples:
-- @\"PotentialCustomer\" -> \"pc\"@,
-- @\"RequiresConfirmation\" -> \"rc\"@,
-- @\"Confirmed\" -> \"c\"@,
-- @\"Deleted\" -> \"d\"@.
vertexFieldPrefix :: String -> String
vertexFieldPrefix = map toLower . filter isUpper


-- | Show a list of strings in @{ "a", "b", "c" }@ form for error
-- messages.
showList' :: [String] -> String
showList' []     = "{}"
showList' [x]    = "{ " <> show x <> " }"
showList' (x:xs) = "{ " <> show x <> concatMap (\y -> ", " <> show y) xs <> " }"
