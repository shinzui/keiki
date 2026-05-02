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
  ) where

import Language.Haskell.TH
import Keiki.Core (HsPred, InCtor, Index, Term (..), WireCtor, matchInCtor)
import Keiki.Generics
  ( FieldsOf
  , RegFieldsOf
  , mkInCtor0
  , mkInCtorVia
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
        pure [wireSig, wireDef]
      _ -> fail $ "deriveWireCtors: ctor " <> show ctorStr
               <> " has unsupported payload shape (singleton or "
               <> "multi-arg/record-syntax)"
