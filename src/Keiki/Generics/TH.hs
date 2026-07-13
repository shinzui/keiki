{-# LANGUAGE TemplateHaskell #-}

-- |
-- Module      : Keiki.Generics.TH
-- Description : Template Haskell splices for aggregate constructor plumbing.
--
-- These splices retire the per-constructor authoring
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
-- 'WireCtor' value per spec entry and, for record-payload events, a
-- field-keyed @\<CtorName\>TermFields@ helper record.
--
-- 'deriveAggregateCtorsAll' and 'deriveWireCtorsAll' are the
-- zero-spec variants: they enumerate every constructor of the named
-- sum type and default each short-name suffix to the constructor's
-- own name, so the common "short name == constructor name" case needs
-- no hand-typed spec list. Keep the enumerated 'deriveAggregateCtors'
-- \/ 'deriveWireCtors' when you need an abbreviated short name that
-- differs from the constructor name.
--
-- 'deriveAggregate' is the fused all-in-one form: it bundles
-- 'deriveAggregateCtorsAll' and 'deriveWireCtorsAll' so an aggregate's
-- entire command- and event-side plumbing is a single splice.
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
--   deriving (Eq, Show, Generic)
--
-- \$('deriveAggregateCtors' \'\'UserCmd \'\'UserRegRegs
--     [ ("StartRegistration",  "Start")
--     , ("ConfirmAccount",     "Confirm")
--     , ("ResendConfirmation", "Resend")
--     , ("FulfillGDPRRequest", "Gdpr")
--     , ("Continue",           "Continue")
--     ])
-- @
--
-- This expands to the same 14 declarations a hand-written module ships
-- (4 record constructors × 3 declarations + 1 singleton × 2 declarations).
--
-- The @*All@ and @*With@ enumeration variants skip unsupported GADT and
-- explicitly quantified constructors, emitting a compile-time warning that
-- names both the skipped constructor and the splice. Explicit spec-list
-- variants fail when asked to generate helpers for an unsupported shape.
--
-- == Negative-test procedure (manual)
--
-- A positional payload is classified as the command constructor's payload,
-- then rejected immediately because it is not a single record-syntax type:
--
-- @
-- data BadCmd = Placed Int
-- type BadRegs = '[]
-- \$(deriveAggregateCtors \'\'BadCmd \'\'BadRegs [("Placed", "Placed")])
-- @
--
-- Compiling that splice must fail with
-- @deriveAggregateCtors: requires a single record-syntax constructor on
-- payload GHC.Types.Int@.
module Keiki.Generics.TH
  ( deriveAggregateCtors,
    deriveAggregateCtorsAll,
    deriveAggregateCtorsWith,
    DeriveCtorOptions (..),
    defaultDeriveCtorOptions,
    deriveWireCtors,
    deriveWireCtorsAll,
    deriveWireCtorsWith,
    DeriveWireOptions (..),
    defaultDeriveWireOptions,
    deriveAggregate,
    deriveView,
  )
where

import Data.Char (isUpper, toLower, toUpper)
import Data.List (group, nub, sort, (\\))
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set (Set)
import Data.Set qualified as Set
import Keiki.Builder (ToOutFields (..))
import Keiki.Core
  ( HsPred,
    InCtor,
    Index,
    OutFields (..),
    RegFile,
    Term (..),
    WireCtor,
    matchInCtor,
    (!),
  )
import Keiki.Generics
  ( FieldsOf,
    RegFieldsOf,
    mkInCtor0,
    mkInCtorVia,
    mkWireCtor0,
    mkWireCtorVia,
  )
import Language.Haskell.TH

-- | Generate per-constructor @inCtor<Short>@, @inp<Short>@,
-- @is<Short>@ declarations from a command sum type and a register-file
-- slot list. Spec entries are @(constructorName, shortName)@ pairs;
-- the short name is appended to the @inCtor@/@inp@/@is@ prefix.
--
-- Singleton constructors (zero-arg 'NormalC') emit only @inCtor@ and
-- @is@; @inp@ is omitted because @'Index' '[]@ is uninhabited.
deriveAggregateCtors ::
  -- | command sum type, e.g. @\'\'UserCmd@
  Name ->
  -- | register-file slot list, e.g. @\'\'UserRegRegs@
  Name ->
  -- | pairs of (constructor name, short name)
  [(String, String)] ->
  Q [Dec]
deriveAggregateCtors cmdName regsName specs = do
  ctors <- reifyCtors cmdName "deriveAggregateCtors"
  let ctorMap = [(nameBase n, c) | c <- ctors, n <- conNames c]
  genAggregateCtors cmdName regsName ctorMap specs

-- | Like 'deriveAggregateCtors', but enumerate every constructor of the
-- command sum type automatically, using each constructor's own name as
-- its short-name suffix. Equivalent to calling 'deriveAggregateCtors'
-- with a spec list of @[(nameBase c, nameBase c) | c <- constructors]@,
-- so it generates @inCtor\<Ctor\>@, @inp\<Ctor\>@, and @is\<Ctor\>@ for
-- each constructor (singletons omit @inp\<Ctor\>@). Reach for the
-- enumerated 'deriveAggregateCtors' when you need an abbreviated short
-- name that differs from the constructor name.
deriveAggregateCtorsAll ::
  -- | command sum type, e.g. @\'\'OrderCmd@
  Name ->
  -- | register-file slot list, e.g. @\'\'OrderCartRegs@
  Name ->
  Q [Dec]
deriveAggregateCtorsAll cmdName regsName = do
  ctors <- reifyCtors cmdName "deriveAggregateCtorsAll"
  warnSkippedConstructors "deriveAggregateCtorsAll" ctors
  let ctorMap = [(nameBase n, c) | c <- ctors, n <- conNames c]
      specs = [(nameBase n, nameBase n) | c <- ctors, n <- conNames c]
  genAggregateCtors cmdName regsName ctorMap specs

-- | Options for 'deriveAggregateCtorsWith'.
--
-- 'suffixOverrides' maps a constructor name to the short-name suffix to
-- use for its generated helpers (e.g. @"DeclareIncident" -> "Declare"@
-- yields @inCtorDeclare@ \/ @inpDeclare@ \/ @isDeclare@). Constructors
-- absent from the map default to their own name as the suffix.
--
-- 'excludeCtors' names constructors to skip entirely: no helpers are
-- generated for them.
--
-- Every key in either field must be an actual constructor of the named
-- sum type; an unknown key aborts the splice at compile time.
data DeriveCtorOptions = DeriveCtorOptions
  { suffixOverrides :: Map String String,
    excludeCtors :: Set String
  }

-- | Default options: no overrides, no exclusions. With this, behaviour
-- is identical to 'deriveAggregateCtorsAll'.
defaultDeriveCtorOptions :: DeriveCtorOptions
defaultDeriveCtorOptions =
  DeriveCtorOptions
    { suffixOverrides = Map.empty,
      excludeCtors = Set.empty
    }

-- | Derive command-constructor helpers for every constructor of the
-- command sum type, like 'deriveAggregateCtorsAll', but honouring
-- per-constructor short-name overrides and an exclude set carried in
-- 'DeriveCtorOptions'. A constructor in 'suffixOverrides' uses the
-- mapped short name; otherwise it defaults to its own name; a
-- constructor in 'excludeCtors' is skipped entirely.
--
-- Unknown override\/exclude keys and duplicate resolved short names both
-- abort the splice at compile time with a precise message. For a
-- constructor present in 'suffixOverrides', the generated declarations
-- are byte-for-byte identical to what 'deriveAggregateCtors' produces
-- for the same @(constructor, short)@ pair.
deriveAggregateCtorsWith ::
  -- | command sum type, e.g. @\'\'IncidentCommand@
  Name ->
  -- | register-file slot list, e.g. @\'\'IncidentRegs@
  Name ->
  DeriveCtorOptions ->
  Q [Dec]
deriveAggregateCtorsWith cmdName regsName opts = do
  ctors <- reifyCtors cmdName "deriveAggregateCtorsWith"
  warnSkippedConstructors "deriveAggregateCtorsWith" ctors
  let ctorMap = [(nameBase n, c) | c <- ctors, n <- conNames c]
      allCtors = map fst ctorMap
  specs <-
    resolveCtorSpecs
      "deriveAggregateCtorsWith"
      allCtors
      (suffixOverrides opts)
      (excludeCtors opts)
  genAggregateCtors cmdName regsName ctorMap specs

-- | Generate per-constructor @wire<Short>@ declarations from an event
-- sum type. Spec entries are @(constructorName, shortName)@ pairs.
-- A record-payload event also gets a @\<Short\>TermFields@ helper
-- record plus its 'ToOutFields' instance. A singleton event gets only
-- the @wire\<Short\>@ binding, because its field tuple is @()@.
deriveWireCtors ::
  -- | event sum type, e.g. @\'\'UserEvent@
  Name ->
  -- | pairs of (constructor name, short name)
  [(String, String)] ->
  Q [Dec]
deriveWireCtors evtName specs = do
  ctors <- reifyCtors evtName "deriveWireCtors"
  let ctorMap = [(nameBase n, c) | c <- ctors, n <- conNames c]
  genWireCtors evtName ctorMap specs

-- | Like 'deriveWireCtors', but enumerate every constructor of the event
-- sum type automatically, using each constructor's own name as its
-- short-name suffix. Generates @wire\<Ctor\>@ (and, for record-payload
-- events, a @\<Ctor\>TermFields@ record plus its 'ToOutFields' instance)
-- for each constructor. Reach for the enumerated 'deriveWireCtors' when
-- you need an abbreviated short name that differs from the constructor
-- name.
deriveWireCtorsAll ::
  -- | event sum type, e.g. @\'\'OrderEvent@
  Name ->
  Q [Dec]
deriveWireCtorsAll evtName = do
  ctors <- reifyCtors evtName "deriveWireCtorsAll"
  warnSkippedConstructors "deriveWireCtorsAll" ctors
  let ctorMap = [(nameBase n, c) | c <- ctors, n <- conNames c]
      specs = [(nameBase n, nameBase n) | c <- ctors, n <- conNames c]
  genWireCtors evtName ctorMap specs

-- | Options for 'deriveWireCtorsWith'. Same semantics as
-- 'DeriveCtorOptions' but for the event side: 'suffixOverridesW' maps an
-- event constructor name to its short-name suffix (used for @wire<Short>@
-- and, for record-payload events, the @<Short>TermFields@ record);
-- 'excludeCtorsW' names event constructors to skip.
data DeriveWireOptions = DeriveWireOptions
  { suffixOverridesW :: Map String String,
    excludeCtorsW :: Set String
  }

-- | Default event options: no overrides, no exclusions. With this,
-- behaviour is identical to 'deriveWireCtorsAll'.
defaultDeriveWireOptions :: DeriveWireOptions
defaultDeriveWireOptions =
  DeriveWireOptions
    { suffixOverridesW = Map.empty,
      excludeCtorsW = Set.empty
    }

-- | Derive event-constructor helpers for every constructor of the event
-- sum type, like 'deriveWireCtorsAll', but honouring per-constructor
-- short-name overrides and an exclude set carried in 'DeriveWireOptions'.
-- A constructor in 'suffixOverridesW' uses the mapped short name;
-- otherwise it defaults to its own name; a constructor in 'excludeCtorsW'
-- is skipped entirely.
--
-- Unknown override\/exclude keys and duplicate resolved short names both
-- abort the splice at compile time with a precise message (via the same
-- 'resolveCtorSpecs' machinery the command side uses). For a constructor
-- present in 'suffixOverridesW', the generated declarations are
-- byte-for-byte identical to what 'deriveWireCtors' produces for the same
-- @(constructor, short)@ pair.
deriveWireCtorsWith ::
  -- | event sum type, e.g. @\'\'OverEvent@
  Name ->
  DeriveWireOptions ->
  Q [Dec]
deriveWireCtorsWith evtName opts = do
  ctors <- reifyCtors evtName "deriveWireCtorsWith"
  warnSkippedConstructors "deriveWireCtorsWith" ctors
  let ctorMap = [(nameBase n, c) | c <- ctors, n <- conNames c]
      allCtors = map fst ctorMap
  specs <-
    resolveCtorSpecs
      "deriveWireCtorsWith"
      allCtors
      (suffixOverridesW opts)
      (excludeCtorsW opts)
  genWireCtors evtName ctorMap specs

-- | Fuse 'deriveAggregateCtorsAll' and 'deriveWireCtorsAll' into one
-- splice covering an aggregate's command and event constructors. Given
-- the command sum type, its register-file slot list, and the event sum
-- type, this emits every declaration both @*All@ variants would, using
-- each constructor's own name as its short-name suffix.
--
-- @
-- \$('deriveAggregate' \'\'OrderCmd \'\'OrderCartRegs \'\'OrderEvent)
-- @
deriveAggregate ::
  -- | command sum type, e.g. @\'\'OrderCmd@
  Name ->
  -- | register-file slot list, e.g. @\'\'OrderCartRegs@
  Name ->
  -- | event sum type, e.g. @\'\'OrderEvent@
  Name ->
  Q [Dec]
deriveAggregate cmdName regsName evtName = do
  cmdDecs <- deriveAggregateCtorsAll cmdName regsName
  evtDecs <- deriveWireCtorsAll evtName
  pure (cmdDecs ++ evtDecs)

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
-- \$('deriveView' \'\'Vertex \'\'UserRegRegs
--     "SUserVertex" "UserView" "userView"
--     [ ("PotentialCustomer",    [])
--     , ("Registering",          [])
--     , ("RequiresConfirmation", ["email", "confirmCode"])
--     , ("Confirmed",            ["email", "confirmedAt"])
--     , ("Deleted",              ["email", "deletedAt"])
--     ])
-- @
deriveView ::
  -- | vertex enum, e.g. @\'\'Vertex@
  Name ->
  -- | register-file slot list, e.g. @\'\'UserRegRegs@
  Name ->
  -- | name of the singletons GADT to generate,
  --     e.g. @"SUserVertex"@
  String ->
  -- | name of the View GADT, e.g. @"UserView"@
  String ->
  -- | name of the projection function,
  --     e.g. @"userView"@
  String ->
  -- | per-vertex spec: pairs of
  --     (vertex constructor name,
  --     list of slot names live in that vertex)
  [(String, [String])] ->
  Q [Dec]
deriveView
  vertexName
  regsName
  sVertexNameStr
  viewNameStr
  viewFunNameStr
  spec = do
    -- Phase 1: reify the vertex enum.
    ctors <- reifyCtors vertexName "deriveView"
    let vertexCtorNames = concatMap conNames ctors
        vertexCtorByBase =
          [(nameBase n, n) | n <- vertexCtorNames]
    -- Phase 2: reify the slot list.
    slotPairs <- reifySlotList regsName
    let slotNamesInRegs = map fst slotPairs
    -- Phase 3: validate (five checks).
    validateSpecCoverage vertexName vertexCtorNames spec
    validateSpecSlots regsName slotNamesInRegs spec
    validatePrefixUniqueness spec
    -- Phase 4: code-gen.
    let sVertexN = mkName sVertexNameStr
        viewN = mkName viewNameStr
        viewFunN = mkName viewFunNameStr
        vIdx = mkName "v"
        vertexCtor name = case lookup name vertexCtorByBase of
          Just n -> n
          Nothing ->
            error $
              "deriveView: bug — validated vertex "
                <> show name
                <> " missing from reified ctor list"
        slotType slotName = case lookup slotName slotPairs of
          Just t -> t
          Nothing ->
            error $
              "deriveView: bug — validated slot "
                <> show slotName
                <> " missing from reified slot list"

    -- (a) Singletons GADT.
    let sCtors =
          [ GadtC
              [mkName ("S" <> vName)]
              []
              (AppT (ConT sVertexN) (PromotedT (vertexCtor vName)))
          | (vName, _) <- spec
          ]
        sDataDec =
          DataD
            []
            sVertexN
            [KindedTV vIdx BndrReq (ConT vertexName)]
            Nothing
            sCtors
            []
        sShowDec =
          StandaloneDerivD
            Nothing
            []
            ( AppT
                (ConT ''Show)
                (AppT (ConT sVertexN) (VarT vIdx))
            )
        sEqDec =
          StandaloneDerivD
            Nothing
            []
            ( AppT
                (ConT ''Eq)
                (AppT (ConT sVertexN) (VarT vIdx))
            )

    -- (b) View GADT.
    let lazyBang = Bang NoSourceUnpackedness NoSourceStrictness
        mkViewCtor (vName, slots) =
          let viewCtorN = mkName (vName <> "V")
              resultT = AppT (ConT viewN) (PromotedT (vertexCtor vName))
              prefix = vertexFieldPrefix vName
           in case slots of
                [] -> GadtC [viewCtorN] [] resultT
                _ ->
                  RecGadtC
                    [viewCtorN]
                    [ ( mkName (vertexFieldName prefix s),
                        lazyBang,
                        slotType s
                      )
                    | s <- slots
                    ]
                    resultT
        viewCtors = map mkViewCtor spec
        viewDataDec =
          DataD
            []
            viewN
            [KindedTV vIdx BndrReq (ConT vertexName)]
            Nothing
            viewCtors
            []
        viewShowDec =
          StandaloneDerivD
            Nothing
            []
            ( AppT
                (ConT ''Show)
                (AppT (ConT viewN) (VarT vIdx))
            )
        viewEqDec =
          StandaloneDerivD
            Nothing
            []
            ( AppT
                (ConT ''Eq)
                (AppT (ConT viewN) (VarT vIdx))
            )

    -- (c) Projection function.
    let regsTy = AppT (ConT ''RegFile) (ConT regsName)
        funTy =
          ForallT
            [PlainTV vIdx SpecifiedSpec]
            []
            ( arrows
                [ AppT (ConT sVertexN) (VarT vIdx),
                  regsTy,
                  AppT (ConT viewN) (VarT vIdx)
                ]
            )
        viewFunSig = SigD viewFunN funTy
    regsVar <- newName "regs"
    let mkClause (vName, slots) =
          let sCtorN = mkName ("S" <> vName)
              viewCtorN = mkName (vName <> "V")
              (regsPat, body) = case slots of
                [] -> (WildP, ConE viewCtorN)
                _ ->
                  let reads_ =
                        [ AppE
                            ( AppE
                                (VarE '(!))
                                (VarE regsVar)
                            )
                            (LabelE s)
                        | s <- slots
                        ]
                   in (VarP regsVar, foldl AppE (ConE viewCtorN) reads_)
           in Clause [ConP sCtorN [] [], regsPat] (NormalB body) []
        viewFunDef = FunD viewFunN (map mkClause spec)

    pure
      [ sDataDec,
        sShowDec,
        sEqDec,
        viewDataDec,
        viewShowDec,
        viewEqDec,
        viewFunSig,
        viewFunDef
      ]
    where
      arrows :: [Type] -> Type
      arrows [] = error "deriveView: arrows on empty list"
      arrows [t] = t
      arrows (t : ts) = AppT (AppT ArrowT t) (arrows ts)

-- | Field name from a vertex prefix and a slot name:
-- @\"<prefix><Slot>\"@ where the slot name's first letter is
-- upper-cased.
vertexFieldName :: String -> String -> String
vertexFieldName prefix slotName = case slotName of
  [] -> prefix
  (c : cs) -> prefix <> (toUpper c : cs)

-- * Internal helpers -----------------------------------------------------

reifyCtors :: Name -> String -> Q [Con]
reifyCtors n caller = do
  info <- reify n
  case info of
    TyConI (DataD _ _ _ _ ctors _) -> pure ctors
    _ ->
      fail $
        caller
          <> ": expected a data declaration for "
          <> show n
          <> ", got "
          <> show info

conNames :: Con -> [Name]
conNames (NormalC n _) = [n]
conNames (RecC n _) = [n]
conNames (InfixC _ n _) = [n]
conNames _ = []

-- | Extract names from every Template Haskell constructor shape, including
-- shapes that keiki deliberately does not generate helpers for.
allConNames :: Con -> [Name]
allConNames (NormalC n _) = [n]
allConNames (RecC n _) = [n]
allConNames (InfixC _ n _) = [n]
allConNames (ForallC _ _ con) = allConNames con
allConNames (GadtC names _ _) = names
allConNames (RecGadtC names _ _) = names

-- | Enumeration splices skip unsupported GADT or explicitly quantified
-- constructors, but never silently. Explicit spec-list splices retain their
-- existing fail-fast behavior when a requested constructor is unsupported.
warnSkippedConstructors :: String -> [Con] -> Q ()
warnSkippedConstructors caller ctors =
  mapM_ warn skipped
  where
    skipped =
      [ name
      | con <- ctors,
        null (conNames con),
        name <- allConNames con
      ]
    warn name =
      reportWarning
        ( caller
            <> ": skipped unsupported GADT or explicitly quantified constructor "
            <> nameBase name
        )

-- | Three-state classification of a constructor's payload.
--
--   * @Just Nothing@  — singleton (zero-arg 'NormalC').
--   * @Just (Just t)@ — single-arg 'NormalC' with payload type @t@.
--   * @Nothing@       — record-syntax or multi-arg ctor (unsupported).
conPayload :: Con -> Maybe (Maybe Type)
conPayload (NormalC _ []) = Just Nothing
conPayload (NormalC _ [(_, t)]) = Just (Just t)
conPayload _ = Nothing

-- | Shared command-side codegen: given the reified constructor map and a
-- resolved @(constructorName, shortName)@ spec list, emit the helper
-- declarations. All command-side entry points route through this so the
-- generated output is identical for identical resolved specs.
genAggregateCtors ::
  Name -> Name -> [(String, Con)] -> [(String, String)] -> Q [Dec]
genAggregateCtors cmdName regsName ctorMap specs =
  fmap concat . mapM (genCtor cmdName regsName ctorMap) $ specs

-- | Resolve options against the reified constructor base-names into a
-- @(constructorName, shortName)@ spec list, validating override\/exclude
-- keys and rejecting duplicate resolved short names. @caller@ is the
-- splice name used in error messages. Sum-type-agnostic so both the
-- command side ('deriveAggregateCtorsWith') and the event side
-- ('deriveWireCtorsWith') reuse it.
resolveCtorSpecs ::
  -- | caller name, e.g. "deriveAggregateCtorsWith"
  String ->
  -- | all constructor base-names of the sum type
  [String] ->
  -- | suffix overrides (constructor -> short)
  Map String String ->
  -- | constructors to exclude
  Set String ->
  Q [(String, String)]
resolveCtorSpecs caller allCtors overrides excludes = do
  -- (a) every override/exclude key must be a real constructor.
  let known = Set.fromList allCtors
      overKeys = Map.keysSet overrides
      badKeys =
        Set.toList
          ( (overKeys `Set.union` excludes)
              `Set.difference` known
          )
  case badKeys of
    [] -> pure ()
    _ ->
      fail $
        caller
          <> ": option(s) name "
          <> showList' badKeys
          <> " which are not constructors of this type; "
          <> "valid constructors: "
          <> showList' allCtors
  -- (b) build the resolved spec, dropping excluded constructors and
  -- applying overrides (default short name = constructor name).
  let kept = [c | c <- allCtors, not (c `Set.member` excludes)]
      specs = [(c, Map.findWithDefault c c overrides) | c <- kept]
  -- (c) reject duplicate resolved short names (would clash at codegen).
  let shorts = map snd specs
      dups = [s | (s : _ : _) <- group (sort shorts)]
  case dups of
    [] -> pure ()
    _ ->
      fail $
        caller
          <> ": short name(s) "
          <> showList' dups
          <> " are produced by more than one constructor; "
          <> "rename via suffixOverrides or exclude one"
  pure specs

genCtor ::
  Name ->
  Name ->
  [(String, Con)] ->
  (String, String) ->
  Q [Dec]
genCtor cmdName regsName ctorMap (ctorStr, shortStr) =
  case lookup ctorStr ctorMap of
    Nothing ->
      fail $
        "deriveAggregateCtors: ctor "
          <> show ctorStr
          <> " not found in "
          <> show cmdName
    Just con -> case conPayload con of
      Nothing ->
        fail $
          "deriveAggregateCtors: ctor "
            <> show ctorStr
            <> " has unsupported shape (multi-arg or record-syntax)"
      Just Nothing ->
        case conNames con of
          (cn : _) -> singletonDecls cmdName regsName ctorStr shortStr cn
          [] ->
            fail $
              "deriveAggregateCtors: could not extract "
                <> "ctor name for "
                <> show ctorStr
      Just (Just payTy) ->
        recordDecls cmdName regsName ctorStr shortStr payTy

singletonDecls ::
  Name -> Name -> String -> String -> Name -> Q [Dec]
singletonDecls cmdName regsName ctorStr shortStr ctorN = do
  let inCtorN = mkName ("inCtor" <> shortStr)
      isN = mkName ("is" <> shortStr)
  inCtorSig <-
    sigD
      inCtorN
      [t|InCtor $(conT cmdName) '[]|]
  inCtorDef <-
    funD
      inCtorN
      [ clause
          []
          ( normalB
              [|
                mkInCtor0
                  $(litE (stringL ctorStr))
                  $(conE ctorN)
                |]
          )
          []
      ]
  isSig <-
    sigD
      isN
      [t|HsPred $(conT regsName) $(conT cmdName)|]
  isDef <-
    funD
      isN
      [ clause
          []
          ( normalB
              [|matchInCtor $(varE inCtorN)|]
          )
          []
      ]
  pure [inCtorSig, inCtorDef, isSig, isDef]

recordDecls ::
  Name -> Name -> String -> String -> Type -> Q [Dec]
recordDecls cmdName regsName ctorStr shortStr payTy = do
  _ <- requireSingleRecordCtor "deriveAggregateCtors" payTy
  let inCtorN = mkName ("inCtor" <> shortStr)
      inpN = mkName ("inp" <> shortStr)
      isN = mkName ("is" <> shortStr)
      slotsT = [t|RegFieldsOf $(pure payTy)|]
  r <- newName "r"
  inCtorSig <-
    sigD
      inCtorN
      [t|InCtor $(conT cmdName) $slotsT|]
  inCtorDef <-
    funD
      inCtorN
      [ clause
          []
          ( normalB
              ( appTypeE
                  [|mkInCtorVia|]
                  (litT (strTyLit ctorStr))
              )
          )
          []
      ]
  inpSig <-
    sigD
      inpN
      [t|
        Index $slotsT $(varT r) ->
        Term $(conT regsName) $(conT cmdName) $slotsT $(varT r)
        |]
  inpDef <-
    funD
      inpN
      [ clause
          []
          ( normalB
              [|TInpCtorField $(varE inCtorN)|]
          )
          []
      ]
  isSig <-
    sigD
      isN
      [t|HsPred $(conT regsName) $(conT cmdName)|]
  isDef <-
    funD
      isN
      [ clause
          []
          ( normalB
              [|matchInCtor $(varE inCtorN)|]
          )
          []
      ]
  pure [inCtorSig, inCtorDef, inpSig, inpDef, isSig, isDef]

-- | Shared event-side codegen: given the reified constructor map and a
-- resolved @(constructorName, shortName)@ spec list, emit the wire
-- declarations. All event-side entry points route through this so the
-- generated output is identical for identical resolved specs.
genWireCtors :: Name -> [(String, Con)] -> [(String, String)] -> Q [Dec]
genWireCtors evtName ctorMap specs =
  fmap concat . mapM (genWire evtName ctorMap) $ specs

genWire ::
  Name ->
  [(String, Con)] ->
  (String, String) ->
  Q [Dec]
genWire evtName ctorMap (ctorStr, shortStr) =
  case lookup ctorStr ctorMap of
    Nothing ->
      fail $
        "deriveWireCtors: ctor "
          <> show ctorStr
          <> " not found in "
          <> show evtName
    Just con -> case conPayload con of
      Just (Just payTy) -> do
        let wireN = mkName ("wire" <> shortStr)
        wireSig <-
          sigD
            wireN
            [t|
              WireCtor
                $(conT evtName)
                (FieldsOf $(pure payTy))
              |]
        wireDef <-
          funD
            wireN
            [ clause
                []
                ( normalB
                    ( appTypeE
                        [|mkWireCtorVia|]
                        (litT (strTyLit ctorStr))
                    )
                )
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
            wireSig <-
              sigD
                wireN
                [t|WireCtor $(conT evtName) ()|]
            wireDef <-
              funD
                wireN
                [ clause
                    []
                    ( normalB
                        [|
                          mkWireCtor0
                            $(litE (stringL ctorStr))
                            $(conE cn)
                          |]
                    )
                    []
                ]
            pure [wireSig, wireDef]
          [] ->
            fail $
              "deriveWireCtors: could not extract ctor name for "
                <> show ctorStr
      Nothing ->
        fail $
          "deriveWireCtors: ctor "
            <> show ctorStr
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
  fields <- requireSingleRecordCtor "deriveWireCtors" payTy
  let recName = mkName (shortStr <> "TermFields")
  rsN <- newName "rs"
  ciN <- newName "ci"
  ifsN <- newName "ifs"
  let lazyBang = Bang NoSourceUnpackedness NoSourceStrictness
      -- EP-53: 'Term' is indexed by the input field schema @ifs@, so the
      -- generated record carries an @ifs@ parameter shared by every
      -- field 'Term'. 'pack' / 'emit' ties it to the 'OPack''s 'InCtor'.
      mkField (selN, _, ty) =
        ( mkName (nameBase selN),
          lazyBang,
          ConT ''Term `AppT` VarT rsN `AppT` VarT ciN `AppT` VarT ifsN `AppT` ty
        )
      recCtor = RecC recName (map mkField fields)
      recDataDec =
        DataD
          []
          recName
          [ PlainTV rsN BndrReq,
            PlainTV ciN BndrReq,
            PlainTV ifsN BndrReq
          ]
          Nothing
          [recCtor]
          []
      recTy = ConT recName `AppT` VarT rsN `AppT` VarT ciN `AppT` VarT ifsN
      -- The 'OutFields' type's @fs@ parameter is the same nested-
      -- pair tuple @FieldsOf <Pay>@ reduces to. Compute it
      -- explicitly so the instance head does not carry a type-
      -- family application (which GHC rejects in instance heads).
      fsTy = mkNestedPairTuple [ty | (_, _, ty) <- fields]
      instHead =
        ConT ''ToOutFields
          `AppT` recTy
          `AppT` VarT rsN
          `AppT` VarT ciN
          `AppT` VarT ifsN
          `AppT` fsTy
  vars <- mapM (\(selN, _, _) -> newName ("v_" <> nameBase selN)) fields
  let recPat =
        RecP
          recName
          [ (mkName (nameBase fn), VarP vn)
          | ((fn, _, _), vn) <- zip fields vars
          ]
      buildBody [] = ConE 'OFNil
      buildBody (v : vs) = ConE 'OFCons `AppE` VarE v `AppE` buildBody vs
      methodDef =
        FunD
          'toOutFields
          [Clause [recPat] (NormalB (buildBody vars)) []]
      instDec = InstanceD Nothing [] instHead [methodDef]
  pure [recDataDec, instDec]

-- | Require a payload type to name a data or newtype with exactly one
-- record-syntax constructor. Shared by command projections and event
-- @TermFields@ generation so both sides reject invalid payloads at the splice
-- boundary with the same diagnostic shape.
requireSingleRecordCtor :: String -> Type -> Q [VarBangType]
requireSingleRecordCtor caller payTy = do
  payName <- typeConstructorName caller payTy
  payInfo <- reify payName
  case payInfo of
    TyConI (DataD _ _ _ _ [RecC _ fields] _) -> pure fields
    TyConI (NewtypeD _ _ _ _ (RecC _ fields) _) -> pure fields
    _ ->
      fail $
        caller
          <> ": requires a single record-syntax constructor on payload "
          <> show payName
          <> ", got "
          <> show payInfo

-- | Extract a type's head constructor name. Accepts @ConT@ and the
-- common forms it might wear after kind-elaboration; rejects
-- function/forall/promoted shapes.
typeConstructorName :: String -> Type -> Q Name
typeConstructorName _ (ConT n) = pure n
typeConstructorName caller (SigT t _) = typeConstructorName caller t
typeConstructorName caller other =
  fail $
    caller
      <> ": payload type must be a type constructor, "
      <> "got "
      <> show other

-- | Build the nested-pair tuple type @(t1, (t2, ..., (tn, ())))@
-- from a list of element types. This is the same shape that
-- 'Keiki.Generics.FieldsOf' reduces a record's 'Rep' to, computed
-- explicitly here so instance heads that mention the shape avoid
-- the type-family application GHC rejects.
mkNestedPairTuple :: [Type] -> Type
mkNestedPairTuple [] = TupleT 0
mkNestedPairTuple (t : ts) = AppT (AppT (TupleT 2) t) (mkNestedPairTuple ts)

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
    _ ->
      fail $
        "deriveView: expected a type synonym for "
          <> show n
          <> " whose right-hand side is a promoted "
          <> "[Slot] list, got "
          <> show info
  where
    walkList :: Type -> Q [(String, Type)]
    walkList (SigT t _) = walkList t
    walkList PromotedNilT = pure []
    walkList (AppT (AppT PromotedConsT headPair) tailList) = do
      pair <- walkPair headPair
      rest <- walkList tailList
      pure (pair : rest)
    walkList other =
      fail $
        "deriveView: expected a promoted-list type at "
          <> show n
          <> ", got "
          <> show other

    walkPair :: Type -> Q (String, Type)
    walkPair (SigT t _) = walkPair t
    walkPair (AppT (AppT (PromotedTupleT 2) (LitT (StrTyLit name))) ty) =
      pure (name, ty)
    walkPair other =
      fail $
        "deriveView: expected a promoted (Symbol, Type) pair "
          <> "in slot list of "
          <> show n
          <> ", got "
          <> show other

-- | Validate that the spec lists every vertex constructor exactly
-- once. Missing, extra, and duplicate spec entries each produce a
-- precise message naming the offenders.
validateSpecCoverage ::
  Name -> [Name] -> [(String, [String])] -> Q ()
validateSpecCoverage vertexName vertexCtorNames spec = do
  let vertexNames = map nameBase vertexCtorNames
      specNames = map fst spec
      duplicates = [n | (n : _ : _) <- group (sort specNames)]
      missing = vertexNames \\ specNames
      extras = specNames \\ vertexNames
  case duplicates of
    [] -> pure ()
    _ ->
      fail $
        "deriveView: spec lists vertex(es) "
          <> showList' duplicates
          <> " more than once"
  case missing of
    [] -> pure ()
    _ ->
      fail $
        "deriveView: spec is missing constructors of "
          <> show vertexName
          <> ": "
          <> showList' missing
  case extras of
    [] -> pure ()
    _ ->
      fail $
        "deriveView: spec names constructors not in "
          <> show vertexName
          <> ": "
          <> showList' extras

-- | Validate that every named slot exists in the register-file slot
-- list, and that no spec entry names the same slot twice.
validateSpecSlots ::
  Name -> [String] -> [(String, [String])] -> Q ()
validateSpecSlots regsName slotNamesInRegs spec =
  mapM_ checkOne spec
  where
    checkOne (vertexCtorName, slots) = do
      let dupSlots = [s | (s : _ : _) <- group (sort slots)]
      case dupSlots of
        [] -> pure ()
        _ ->
          fail $
            "deriveView: spec entry "
              <> show vertexCtorName
              <> " lists slot(s) "
              <> showList' dupSlots
              <> " more than once"
      let missing = slots \\ slotNamesInRegs
      case missing of
        [] -> pure ()
        _ ->
          fail $
            "deriveView: spec entry "
              <> show vertexCtorName
              <> " names slot(s) "
              <> showList' missing
              <> " which are not slots of "
              <> show regsName
              <> "; known slots: "
              <> showList' slotNamesInRegs

-- | Validate that the per-vertex field-name prefixes
-- (@filter isUpper >>> map toLower@) are pairwise distinct so the
-- generated View GADT has no field-name collisions across
-- constructors.
validatePrefixUniqueness :: [(String, [String])] -> Q ()
validatePrefixUniqueness spec =
  case collisions of
    [] -> pure ()
    ((pref, ns) : _) ->
      fail $
        "deriveView: vertices "
          <> showList' ns
          <> " produce the same field-name prefix "
          <> show pref
          <> "; rename one"
  where
    prefixed = [(vertexFieldPrefix n, n) | (n, _) <- spec]
    collisions =
      [ (pref, [n | (p', n) <- prefixed, p' == pref])
      | pref <- nub (map fst prefixed),
        length [() | (p', _) <- prefixed, p' == pref] > 1
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
showList' [] = "{}"
showList' [x] = "{ " <> show x <> " }"
showList' (x : xs) = "{ " <> show x <> concatMap (\y -> ", " <> show y) xs <> " }"
