{-# LANGUAGE TypeFamilies #-}

-- | DX spike (EP-2 follow-up): generic-derived inversions between
-- Haskell records and 'RegFile's so users can build 'InCtor' values
-- without hand-rolling RCons-towers.
--
-- Status: experimental. See the EP-2 retrospective for context.
--
-- == Trust model
--
-- Trusted structural schemas minted by the @Via@ producers are rooted in the
-- lawfulness of the consumer type's 'GHC.Generics.Generic' instance: the
-- constructor path, field spine, and the match\/build closures are all read
-- from the same @Rep@. A derived instance is always lawful, so
-- @deriving stock Generic@ types get honest evidence by construction. A
-- hand-written, deliberately unlawful 'GHC.Generics.Generic' instance can
-- pair trusted evidence with behavior it does not describe; that path is
-- outside the threat model in exactly the way 'Unsafe.Coerce.unsafeCoerce'
-- is. Keiki's sealed boundaries defend against /accidental/ decoupling —
-- record updates, closure-taking helpers, forged capabilities — not against a
-- consumer determined to lie to the compiler.
module Keiki.Generics
  ( -- * Generic-derived InCtor
    mkInCtor,
    mkInCtor0,
    mkInCtorVia,
    mkInCtorRecordVia,

    -- * Generic-derived WireCtor
    mkWireCtor,
    mkWireCtor0,
    mkWireCtorVia,
    mkWireCtor0Via,
    mkWireCtorRecordVia,
    FieldsOf,
    FieldsOfRep,

    -- * Slot-list deriving
    RegFieldsOf,
    RegFieldsOfRep,

    -- * Empty register file
    EmptyRegFile (..),

    -- * Internals
    GRecord (..),
    GTuple (..),
    Append,
    appendRegFile,
    SplitRegFile (..),
    ConcatT,
    SplitT (..),
  )
where

import Data.Kind (Type)
import Data.Proxy (Proxy (..))
import Data.Type.Bool (type (||))
import Data.Typeable (Typeable)
import GHC.Generics
import GHC.TypeLits (KnownSymbol, Symbol, symbolVal)
import Keiki.Core
import Keiki.Internal.ConstructorEvidence (constructorEvidence)
import Keiki.Internal.WireSchema
  ( AppendInCtorFields,
    AppendWireFields,
    InCtorFieldSchema,
    WireCtorPath,
    appendInCtorFieldSchema,
    appendWireFieldSchema,
    genericPrefixWireCtorPathLeft,
    genericPrefixWireCtorPathRight,
    inCtorFieldsCons,
    inCtorFieldsNil,
    trustedInCtorSchema,
    trustedWireSchema,
    wireCtorPathRoot,
    wireFieldsCons,
    wireFieldsNil,
  )

-- | Walk a 'GHC.Generics' record representation to/from a 'RegFile'.
-- Slot lists are derived from the record's field metadata: every
-- selector @M1 S ('MetaSel ('Just name) ...)@ contributes a slot
-- @'(name, fieldType)@; products concatenate.
class GRecord (rep :: Type -> Type) (ifs :: [Slot]) | rep -> ifs where
  gToRegFile :: rep a -> RegFile ifs
  gFromRegFile :: RegFile ifs -> rep a

-- M1 D wrapper (data type metadata): pass through.
instance (GRecord inner ifs) => GRecord (M1 D meta inner) ifs where
  gToRegFile (M1 r) = gToRegFile r
  gFromRegFile rf = M1 (gFromRegFile rf)

-- M1 C wrapper (constructor metadata): pass through.
instance (GRecord inner ifs) => GRecord (M1 C meta inner) ifs where
  gToRegFile (M1 r) = gToRegFile r
  gFromRegFile rf = M1 (gFromRegFile rf)

-- Named selector with a leaf field: one slot.
instance
  (KnownSymbol name) =>
  GRecord
    (M1 S ('MetaSel ('Just name) su ss ds) (K1 r t))
    '[ '(name, t)]
  where
  gToRegFile (M1 (K1 v)) = RCons (Proxy @name) v RNil
  gFromRegFile (RCons _ v _) = M1 (K1 v)

-- No-arg constructor: empty slot list.
instance GRecord U1 '[] where
  gToRegFile U1 = RNil
  gFromRegFile RNil = U1

-- Product: concatenate slot lists.
instance
  ( GRecord l ls,
    GRecord r rs,
    Append ls rs ~ ifs,
    SplitRegFile ls rs
  ) =>
  GRecord (l :*: r) ifs
  where
  gToRegFile (a :*: b) = appendRegFile (gToRegFile a) (gToRegFile b)
  gFromRegFile rf = case splitRegFile @ls @rs rf of
    (lrf, rrf) -> gFromRegFile lrf :*: gFromRegFile rrf

-- | Type-level append for slot lists.
type family Append (xs :: [Slot]) (ys :: [Slot]) :: [Slot] where
  Append '[] ys = ys
  Append (x ': xs) ys = x ': Append xs ys

-- | Value-level append for register files.
appendRegFile :: RegFile ls -> RegFile rs -> RegFile (Append ls rs)
appendRegFile RNil rs = rs
appendRegFile (RCons p v xs) rs = RCons p v (appendRegFile xs rs)

-- | Split a register file at the boundary between two slot lists.
class SplitRegFile (ls :: [Slot]) (rs :: [Slot]) where
  splitRegFile :: RegFile (Append ls rs) -> (RegFile ls, RegFile rs)

instance SplitRegFile '[] rs where
  splitRegFile rf = (RNil, rf)

instance (SplitRegFile ls rs) => SplitRegFile ('(s, t) ': ls) rs where
  splitRegFile (RCons p v rest) =
    case splitRegFile @ls @rs rest of
      (lrf, rrf) -> (RCons p v lrf, rrf)

-- | Build an 'InCtor' from a constructor name, a sum-side matcher,
-- and a pack function. The 'RegFile' inversion is derived from the
-- record's 'GHC.Generics.Generic' instance — no RCons-tower required.
--
-- Example:
--
-- > inCtorStart :: InCtor UserCmd
-- >                       '[ '("email",       Email)
-- >                        , '("confirmCode", ConfirmationCode)
-- >                        , '("at",          UTCTime)
-- >                        ]
-- > inCtorStart = mkInCtor "StartRegistration"
-- >                        (\case StartRegistration d -> Just d; _ -> Nothing)
-- >                        StartRegistration
--
-- The slot list is inferred from @StartRegistrationData@'s 'Generic'
-- field metadata. The record type must have @deriving (Generic)@.
mkInCtor ::
  forall ci d ifs.
  ( Generic d,
    GRecord (Rep d) ifs,
    AssembleRegFile ifs,
    KnownSlotNames ifs
  ) =>
  String ->
  (ci -> Maybe d) ->
  (d -> ci) ->
  InCtor ci ifs
{-# DEPRECATED mkInCtor "Use mkInCtorVia for Generic constructors, or unavailableInCtor for manual behavior." #-}
mkInCtor name match wrap =
  unavailableInCtor
    name
    ( \ci -> case match ci of
        Just d -> Just (gToRegFile (from d))
        Nothing -> Nothing
    )
    (\rf -> wrap (to (gFromRegFile rf)))

-- | Build an 'InCtor' for a no-payload (singleton) constructor. The
-- 'icMatch' compares against the named singleton via 'Eq'; 'icBuild'
-- ignores the empty 'RegFile' and returns the singleton.
--
-- Example:
--
-- > inCtorContinue :: InCtor UserCmd '[]
-- > inCtorContinue = mkInCtor0 "Continue" Continue
mkInCtor0 :: forall ci. (Eq ci) => String -> ci -> InCtor ci '[]
{-# DEPRECATED mkInCtor0 "Use mkInCtorVia for Generic nullary constructors, or unavailableInCtor for manual behavior." #-}
mkInCtor0 name singleton =
  unavailableInCtor
    name
    (\ci -> if ci == singleton then Just RNil else Nothing)
    (\RNil -> singleton)

-- * Generic-derived WireCtor ----------------------------------------------

-- | Walk a 'GHC.Generics' record representation to/from the nested-
-- pair tuple shape that 'WireCtor' / 'OutFields' carry. A record with
-- fields @f1, f2, f3@ corresponds to the tuple @(f1, (f2, (f3, ())))@.
class GTuple (rep :: Type -> Type) (fs :: Type) | rep -> fs where
  gToTuple :: rep a -> fs
  gFromTuple :: fs -> rep a

instance (GTuple inner fs) => GTuple (M1 D meta inner) fs where
  gToTuple (M1 r) = gToTuple r
  gFromTuple t = M1 (gFromTuple t)

instance (GTuple inner fs) => GTuple (M1 C meta inner) fs where
  gToTuple (M1 r) = gToTuple r
  gFromTuple t = M1 (gFromTuple t)

instance GTuple (M1 S meta (K1 r t)) (t, ()) where
  gToTuple (M1 (K1 v)) = (v, ())
  gFromTuple (v, ()) = M1 (K1 v)

instance GTuple U1 () where
  gToTuple U1 = ()
  gFromTuple () = U1

instance
  ( GTuple l ls,
    GTuple r rs,
    ConcatT ls rs ~ fs,
    SplitT ls rs
  ) =>
  GTuple (l :*: r) fs
  where
  gToTuple (a :*: b) = appendT (gToTuple a) (gToTuple b)
  gFromTuple t = case splitT @ls @rs t of
    (lt, rt) -> gFromTuple lt :*: gFromTuple rt

-- | Type-level concat for nested-pair tuples. @ConcatT (f1, (f2, ())) (f3, ()) ~ (f1, (f2, (f3, ())))@.
type ConcatT (a :: Type) (b :: Type) = AppendWireFields a b

-- | Split a concatenated nested-pair tuple back into its halves; also
-- the inverse direction (append).
class SplitT (a :: Type) (b :: Type) where
  splitT :: ConcatT a b -> (a, b)
  appendT :: a -> b -> ConcatT a b

instance SplitT () b where
  splitT b = ((), b)
  appendT () b = b

instance (SplitT xs b) => SplitT (x, xs) b where
  splitT (x, rest) = case splitT @xs @b rest of
    (a, c) -> ((x, a), c)
  appendT (x, xs) b = (x, appendT xs b)

-- | Resolve a record type to its nested-pair field tuple. With this
-- alias, @WireCtor UserEvent (FieldsOf RegistrationStartedData)@
-- replaces the hand-written @WireCtor UserEvent (Email,
-- (ConfirmationCode, (UTCTime, ())))@.
type FieldsOf d = FieldsOfRep (Rep d)

-- | The nested-pair tuple shape derived from a 'GHC.Generics' Rep.
type family FieldsOfRep (rep :: Type -> Type) :: Type where
  FieldsOfRep (M1 D _ inner) = FieldsOfRep inner
  FieldsOfRep (M1 C _ inner) = FieldsOfRep inner
  FieldsOfRep (M1 S _ (K1 _ t)) = (t, ())
  FieldsOfRep U1 = ()
  FieldsOfRep (l :*: r) = ConcatT (FieldsOfRep l) (FieldsOfRep r)

-- | Resolve a record type to its 'RegFile' slot list. With this
-- alias, @InCtor UserCmd (RegFieldsOf StartRegistrationData)@
-- replaces the hand-written @InCtor UserCmd '[ '("email", Email),
-- '("confirmCode", ConfirmationCode), '("at", UTCTime) ]@.
type RegFieldsOf d = RegFieldsOfRep (Rep d)

-- | The slot-list shape derived from a 'GHC.Generics' Rep. Mirrors
-- 'FieldsOfRep' but emits @[Slot]@ instead of a nested-pair tuple,
-- preserving the selector name on every field.
type family RegFieldsOfRep (rep :: Type -> Type) :: [Slot] where
  RegFieldsOfRep (M1 D _ inner) = RegFieldsOfRep inner
  RegFieldsOfRep (M1 C _ inner) = RegFieldsOfRep inner
  RegFieldsOfRep (M1 S ('MetaSel ('Just n) _ _ _) (K1 _ t)) =
    '[ '(n, t)]
  RegFieldsOfRep U1 = '[]
  RegFieldsOfRep (l :*: r) =
    Append
      (RegFieldsOfRep l)
      (RegFieldsOfRep r)

-- | Build a 'WireCtor' from a constructor name, a sum-side matcher,
-- and a pack function. The nested-pair conversion is derived from the
-- record's 'GHC.Generics.Generic' instance.
--
-- Example:
--
-- > wireRegistrationStarted
-- >   :: WireCtor UserEvent (FieldsOf RegistrationStartedData)
-- > wireRegistrationStarted = mkWireCtor "RegistrationStarted"
-- >   (\case RegistrationStarted d -> Just d; _ -> Nothing)
-- >   RegistrationStarted
{-# DEPRECATED mkWireCtor "Use mkWireCtorVia for Generic constructors, or unavailableWireCtor for manual behavior." #-}
mkWireCtor ::
  forall co d fs.
  ( Generic d,
    GTuple (Rep d) fs
  ) =>
  String ->
  (co -> Maybe d) ->
  (d -> co) ->
  WireCtor co fs
mkWireCtor name match wrap =
  unavailableWireCtor
    name
    ( \co -> case match co of
        Just d -> Just (gToTuple (from d))
        Nothing -> Nothing
    )
    (\fs -> wrap (to (gFromTuple fs)))

-- | Build a 'WireCtor' for a no-payload (singleton) event constructor —
-- the event-side twin of 'mkInCtor0'. Its field tuple is @()@ (a
-- payload-free event carries nothing), matching @'OutFields' rs ci ()@ /
-- @OFNil@. 'wcMatch' compares against the named singleton via 'Eq';
-- 'wcBuild' ignores the empty tuple and returns the singleton. The
-- @'Eq' co@ constraint matches 'mkInCtor0'\'s @'Eq' ci@; event sums in
-- this codebase already derive 'Eq', so it is not a new burden.
--
-- Example:
--
-- > wireOpened :: WireCtor DoorEvent ()
-- > wireOpened = mkWireCtor0 "Opened" Opened
{-# DEPRECATED mkWireCtor0 "Use mkWireCtor0Via for Generic nullary constructors, or unavailableWireCtor for manual behavior." #-}
mkWireCtor0 :: forall co. (Eq co) => String -> co -> WireCtor co ()
mkWireCtor0 name singleton =
  unavailableWireCtor
    name
    (\co -> if co == singleton then Just () else Nothing)
    (\() -> singleton)

-- * Empty register file ---------------------------------------------------

-- | Derive an initial 'RegFile' for any slot list. Every slot is
-- pre-bound to a deferred error tagged with the slot's name so reads
-- of an uninitialized slot crash with a targeted message instead of
-- a silent bottom. Every slot must be written before the register file is
-- read or encoded; 'emptyRegFile' is an initialization scaffold, not an
-- encodable snapshot.
class EmptyRegFile (rs :: [Slot]) where
  emptyRegFile :: RegFile rs

instance EmptyRegFile '[] where
  emptyRegFile = RNil

instance
  (KnownSymbol s, EmptyRegFile rs) =>
  EmptyRegFile ('(s, r) ': rs)
  where
  emptyRegFile =
    RCons
      (Proxy @s)
      ( error
          ( "uninit: "
              ++ symbolVal (Proxy @s)
              ++ " (slot read before first write; a RegFile must be fully initialized before it is read or encoded)"
          )
      )
      emptyRegFile

-- * Sum-walking machinery -------------------------------------------------

-- | Does the constructor named @n@ appear anywhere in the 'Generic'
-- representation @rep@? Used to dispatch sum-side resolution to the
-- correct branch.
type family NameInRep (n :: Symbol) (rep :: Type -> Type) :: Bool where
  NameInRep n (M1 D _ inner) = NameInRep n inner
  NameInRep n (l :+: r) = NameInRep n l || NameInRep n r
  NameInRep n (M1 C ('MetaCons n _ _) _) = 'True
  NameInRep _ _ = 'False

-- | Walk a 'Generic' representation looking for a constructor named
-- @name@; resolve its payload type @d@. Two payload shapes are
-- supported:
--
--   * @M1 C ('MetaCons name _ _) (M1 S _ (K1 _ d))@ — single-field
--     constructor wrapping a record value of type @d@.
--   * @M1 C ('MetaCons name _ _) U1@ — no-payload constructor;
--     @d ~ ()@.
--
-- The functional dependency @name rep -> d@ pins the payload uniquely.
class
  GHasCtor (name :: Symbol) (rep :: Type -> Type) (d :: Type)
    | name rep -> d
  where
  gMatchCtor :: rep a -> Maybe d
  gBuildCtor :: d -> rep a

-- | Derive the ordinal sum path of a named constructor. This class is kept
-- private so consumers cannot supply a dishonest path instance.
class GWireCtorPath (name :: Symbol) (rep :: Type -> Type) where
  gWireCtorPath :: WireCtorPath carrier

instance (GWireCtorPath name inner) => GWireCtorPath name (M1 D meta inner) where
  gWireCtorPath = gWireCtorPath @name @inner

instance GWireCtorPath name (M1 C ('MetaCons name fix lazy) payload) where
  gWireCtorPath = wireCtorPathRoot

instance
  ( hasLeft ~ NameInRep name left,
    GWireCtorPathIf hasLeft name left right
  ) =>
  GWireCtorPath name (left :+: right)
  where
  gWireCtorPath = gWireCtorPathIf @hasLeft @name @left @right

class
  GWireCtorPathIf
    (hasLeft :: Bool)
    (name :: Symbol)
    (left :: Type -> Type)
    (right :: Type -> Type)
  where
  gWireCtorPathIf :: WireCtorPath carrier

instance (GWireCtorPath name left) => GWireCtorPathIf 'True name left right where
  gWireCtorPathIf =
    genericPrefixWireCtorPathLeft (gWireCtorPath @name @left)

instance (GWireCtorPath name right) => GWireCtorPathIf 'False name left right where
  gWireCtorPathIf =
    genericPrefixWireCtorPathRight (gWireCtorPath @name @right)

-- | Derive a typed, source-ordered field spine from a payload's Generic
-- representation. Like 'GWireCtorPath', this class is private so only the
-- library's Generic instances can mint trusted evidence.
class GWireFieldSchema (rep :: Type -> Type) (fields :: Type) | rep -> fields where
  gWireFieldSchema :: WireFieldSchema fields

instance (GWireFieldSchema inner fields) => GWireFieldSchema (M1 D meta inner) fields where
  gWireFieldSchema = gWireFieldSchema @inner

instance (GWireFieldSchema inner fields) => GWireFieldSchema (M1 C meta inner) fields where
  gWireFieldSchema = gWireFieldSchema @inner

instance
  (Typeable field, Selector meta) =>
  GWireFieldSchema (M1 S meta (K1 r field)) (field, ())
  where
  gWireFieldSchema =
    wireFieldsCons selectorLabel wireFieldsNil
    where
      selectorText = selName (undefined :: M1 S meta (K1 r field) ())
      selectorLabel
        | null selectorText = Nothing
        | otherwise = Just selectorText

instance GWireFieldSchema U1 () where
  gWireFieldSchema = wireFieldsNil

instance
  ( GWireFieldSchema left leftFields,
    GWireFieldSchema right rightFields,
    ConcatT leftFields rightFields ~ fields
  ) =>
  GWireFieldSchema (left :*: right) fields
  where
  gWireFieldSchema =
    appendWireFieldSchema
      (gWireFieldSchema @left)
      (gWireFieldSchema @right)

-- | Derive a typed, source-ordered slot spine from an input payload's
-- Generic representation. This class is private so only Keiki's Generic
-- implementation can mint trusted input-constructor evidence.
class
  GInCtorFieldSchema
    (rep :: Type -> Type)
    (fields :: [Slot])
    | rep -> fields
  where
  gInCtorFieldSchema :: InCtorFieldSchema fields

instance
  (GInCtorFieldSchema inner fields) =>
  GInCtorFieldSchema (M1 D meta inner) fields
  where
  gInCtorFieldSchema = gInCtorFieldSchema @inner

instance
  (GInCtorFieldSchema inner fields) =>
  GInCtorFieldSchema (M1 C meta inner) fields
  where
  gInCtorFieldSchema = gInCtorFieldSchema @inner

instance
  (KnownSymbol name, Typeable field) =>
  GInCtorFieldSchema
    (M1 S ('MetaSel ('Just name) su ss ds) (K1 r field))
    '[ '(name, field)]
  where
  gInCtorFieldSchema =
    inCtorFieldsCons
      (Just (symbolVal (Proxy @name)))
      inCtorFieldsNil

instance GInCtorFieldSchema U1 '[] where
  gInCtorFieldSchema = inCtorFieldsNil

instance
  ( GInCtorFieldSchema left leftFields,
    GInCtorFieldSchema right rightFields,
    AppendInCtorFields leftFields rightFields ~ fields
  ) =>
  GInCtorFieldSchema (left :*: right) fields
  where
  gInCtorFieldSchema =
    appendInCtorFieldSchema
      (gInCtorFieldSchema @left)
      (gInCtorFieldSchema @right)

-- Pass through the data-type wrapper.
instance (GHasCtor n inner d) => GHasCtor n (M1 D meta inner) d where
  gMatchCtor (M1 r) = gMatchCtor @n r
  gBuildCtor d = M1 (gBuildCtor @n d)

-- Match a constructor whose payload is a single record value.
instance GHasCtor n (M1 C ('MetaCons n fix lazy) (M1 S meta (K1 r d))) d where
  gMatchCtor (M1 (M1 (K1 d))) = Just d
  gBuildCtor d = M1 (M1 (K1 d))

-- Match a no-payload constructor; payload is the unit type '()'.
instance GHasCtor n (M1 C ('MetaCons n fix lazy) U1) () where
  gMatchCtor (M1 U1) = Just ()
  gBuildCtor () = M1 U1

-- Sum dispatch: pick the side that contains the named constructor.
instance
  ( hasL ~ NameInRep n l,
    GHasCtorIf hasL n l r d
  ) =>
  GHasCtor n (l :+: r) d
  where
  gMatchCtor x = gMatchCtorIf @hasL @n @l @r x
  gBuildCtor d = gBuildCtorIf @hasL @n @l @r d

-- | Sum-dispatch helper: reduce 'GHasCtor' on @l :+: r@ to a
-- 'GHasCtor' on the side that contains the named constructor.
class
  GHasCtorIf
    (b :: Bool)
    (n :: Symbol)
    (l :: Type -> Type)
    (r :: Type -> Type)
    (d :: Type)
    | b n l r -> d
  where
  gMatchCtorIf :: (l :+: r) a -> Maybe d
  gBuildCtorIf :: d -> (l :+: r) a

instance (GHasCtor n l d) => GHasCtorIf 'True n l r d where
  gMatchCtorIf (L1 x) = gMatchCtor @n x
  gMatchCtorIf (R1 _) = Nothing
  gBuildCtorIf d = L1 (gBuildCtor @n d)

instance (GHasCtor n r d) => GHasCtorIf 'False n l r d where
  gMatchCtorIf (L1 _) = Nothing
  gMatchCtorIf (R1 x) = gMatchCtor @n x
  gBuildCtorIf d = R1 (gBuildCtor @n d)

-- | Direct-record counterpart of 'GHasCtor'. Instead of resolving one
-- wrapped payload value, this class derives a 'RegFile' directly from the
-- named constructor's own record fields.
class
  GRecordCtor
    (name :: Symbol)
    (rep :: Type -> Type)
    (fields :: [Slot])
    | name rep -> fields
  where
  gMatchRecordCtor :: rep a -> Maybe (RegFile fields)
  gBuildRecordCtor :: RegFile fields -> rep a
  gRecordCtorSchema :: InCtorFieldSchema fields

instance
  (GRecordCtor name inner fields) =>
  GRecordCtor name (M1 D meta inner) fields
  where
  gMatchRecordCtor (M1 representation) = gMatchRecordCtor @name representation
  gBuildRecordCtor fields = M1 (gBuildRecordCtor @name fields)
  gRecordCtorSchema = gRecordCtorSchema @name @inner

instance
  ( GRecord inner fields,
    GInCtorFieldSchema inner fields
  ) =>
  GRecordCtor name (M1 C ('MetaCons name fix lazy) inner) fields
  where
  gMatchRecordCtor (M1 representation) = Just (gToRegFile representation)
  gBuildRecordCtor fields = M1 (gFromRegFile fields)
  gRecordCtorSchema = gInCtorFieldSchema @inner

instance
  ( hasLeft ~ NameInRep name left,
    GRecordCtorIf hasLeft name left right fields
  ) =>
  GRecordCtor name (left :+: right) fields
  where
  gMatchRecordCtor = gMatchRecordCtorIf @hasLeft @name
  gBuildRecordCtor = gBuildRecordCtorIf @hasLeft @name
  gRecordCtorSchema = gRecordCtorSchemaIf @hasLeft @name @left @right

class
  GRecordCtorIf
    (hasLeft :: Bool)
    (name :: Symbol)
    (left :: Type -> Type)
    (right :: Type -> Type)
    (fields :: [Slot])
    | hasLeft name left right -> fields
  where
  gMatchRecordCtorIf :: (left :+: right) a -> Maybe (RegFile fields)
  gBuildRecordCtorIf :: RegFile fields -> (left :+: right) a
  gRecordCtorSchemaIf :: InCtorFieldSchema fields

instance (GRecordCtor name left fields) => GRecordCtorIf 'True name left right fields where
  gMatchRecordCtorIf (L1 representation) = gMatchRecordCtor @name representation
  gMatchRecordCtorIf (R1 _) = Nothing
  gBuildRecordCtorIf fields = L1 (gBuildRecordCtor @name fields)
  gRecordCtorSchemaIf = gRecordCtorSchema @name @left

instance (GRecordCtor name right fields) => GRecordCtorIf 'False name left right fields where
  gMatchRecordCtorIf (L1 _) = Nothing
  gMatchRecordCtorIf (R1 representation) = gMatchRecordCtor @name representation
  gBuildRecordCtorIf fields = R1 (gBuildRecordCtor @name fields)
  gRecordCtorSchemaIf = gRecordCtorSchema @name @right

-- | Direct-record wire counterpart of 'GRecordCtor'.
class
  GTupleCtor
    (name :: Symbol)
    (rep :: Type -> Type)
    (fields :: Type)
    | name rep -> fields
  where
  gMatchTupleCtor :: rep a -> Maybe fields
  gBuildTupleCtor :: fields -> rep a
  gTupleCtorSchema :: WireFieldSchema fields

instance
  (GTupleCtor name inner fields) =>
  GTupleCtor name (M1 D meta inner) fields
  where
  gMatchTupleCtor (M1 representation) = gMatchTupleCtor @name representation
  gBuildTupleCtor fields = M1 (gBuildTupleCtor @name fields)
  gTupleCtorSchema = gTupleCtorSchema @name @inner

instance
  ( GTuple inner fields,
    GWireFieldSchema inner fields
  ) =>
  GTupleCtor name (M1 C ('MetaCons name fix lazy) inner) fields
  where
  gMatchTupleCtor (M1 representation) = Just (gToTuple representation)
  gBuildTupleCtor fields = M1 (gFromTuple fields)
  gTupleCtorSchema = gWireFieldSchema @inner

instance
  ( hasLeft ~ NameInRep name left,
    GTupleCtorIf hasLeft name left right fields
  ) =>
  GTupleCtor name (left :+: right) fields
  where
  gMatchTupleCtor = gMatchTupleCtorIf @hasLeft @name
  gBuildTupleCtor = gBuildTupleCtorIf @hasLeft @name
  gTupleCtorSchema = gTupleCtorSchemaIf @hasLeft @name @left @right

class
  GTupleCtorIf
    (hasLeft :: Bool)
    (name :: Symbol)
    (left :: Type -> Type)
    (right :: Type -> Type)
    (fields :: Type)
    | hasLeft name left right -> fields
  where
  gMatchTupleCtorIf :: (left :+: right) a -> Maybe fields
  gBuildTupleCtorIf :: fields -> (left :+: right) a
  gTupleCtorSchemaIf :: WireFieldSchema fields

instance (GTupleCtor name left fields) => GTupleCtorIf 'True name left right fields where
  gMatchTupleCtorIf (L1 representation) = gMatchTupleCtor @name representation
  gMatchTupleCtorIf (R1 _) = Nothing
  gBuildTupleCtorIf fields = L1 (gBuildTupleCtor @name fields)
  gTupleCtorSchemaIf = gTupleCtorSchema @name @left

instance (GTupleCtor name right fields) => GTupleCtorIf 'False name left right fields where
  gMatchTupleCtorIf (L1 _) = Nothing
  gMatchTupleCtorIf (R1 representation) = gMatchTupleCtor @name representation
  gBuildTupleCtorIf fields = R1 (gBuildTupleCtor @name fields)
  gTupleCtorSchemaIf = gTupleCtorSchema @name @right

-- * Generic-derived InCtor / WireCtor (Via builders) ----------------------

-- | Build an 'InCtor' from a constructor name alone. The sum-side
-- match\/wrap pair and the record-side RegFile inversion are both
-- derived from the 'Generic' representations of @ci@ and the inferred
-- payload @d@. With no-payload constructors (e.g. 'Continue') the
-- inferred slot list is @\'[]@.
--
-- Example:
--
-- > inCtorStart    :: InCtor UserCmd StartFields
-- > inCtorStart     = mkInCtorVia @"StartRegistration"
-- >
-- > inCtorContinue :: InCtor UserCmd '[]
-- > inCtorContinue  = mkInCtorVia @"Continue"
mkInCtorVia ::
  forall (name :: Symbol) ci d ifs.
  ( KnownSymbol name,
    Generic ci,
    GHasCtor name (Rep ci) d,
    GWireCtorPath name (Rep ci),
    Generic d,
    GRecord (Rep d) ifs,
    GInCtorFieldSchema (Rep d) ifs,
    AssembleRegFile ifs,
    KnownSlotNames ifs
  ) =>
  InCtor ci ifs
mkInCtorVia =
  trustedInCtorInternal
    constructorEvidence
    (symbolVal (Proxy @name))
    ( trustedInCtorSchema
        (gWireCtorPath @name @(Rep ci))
        (gInCtorFieldSchema @(Rep d))
    )
    ( \ci -> case gMatchCtor @name (from ci) of
        Just d -> Just (gToRegFile (from d))
        Nothing -> Nothing
    )
    (\rf -> to (gBuildCtor @name (to (gFromRegFile rf) :: d)))

-- | Build a trusted 'InCtor' for a constructor whose payload fields are
-- declared directly with record syntax. Use 'mkInCtorVia' when the sum
-- constructor instead wraps a separate record value.
mkInCtorRecordVia ::
  forall (name :: Symbol) ci ifs.
  ( KnownSymbol name,
    Generic ci,
    GRecordCtor name (Rep ci) ifs,
    GWireCtorPath name (Rep ci),
    AssembleRegFile ifs,
    KnownSlotNames ifs
  ) =>
  InCtor ci ifs
mkInCtorRecordVia =
  trustedInCtorInternal
    constructorEvidence
    (symbolVal (Proxy @name))
    ( trustedInCtorSchema
        (gWireCtorPath @name @(Rep ci))
        (gRecordCtorSchema @name @(Rep ci))
    )
    (gMatchRecordCtor @name . from)
    (to . gBuildRecordCtor @name)

-- | Build a trusted 'WireCtor' from a constructor name alone. Mirrors
-- 'mkInCtorVia' on the wire side: the nested-pair field tuple comes
-- from the inferred payload's 'Generic' field metadata, while the carrier's
-- Generic sum path and ordered field types become its structural schema.
--
-- Example:
--
-- > wireRegistrationStarted
-- >   :: WireCtor UserEvent (FieldsOf RegistrationStartedData)
-- > wireRegistrationStarted = mkWireCtorVia @"RegistrationStarted"
mkWireCtorVia ::
  forall (name :: Symbol) co d fs.
  ( KnownSymbol name,
    Generic co,
    GHasCtor name (Rep co) d,
    GWireCtorPath name (Rep co),
    Generic d,
    GTuple (Rep d) fs,
    GWireFieldSchema (Rep d) fs
  ) =>
  WireCtor co fs
mkWireCtorVia =
  trustedWireCtorInternal
    constructorEvidence
    (symbolVal (Proxy @name))
    ( trustedWireSchema
        (gWireCtorPath @name @(Rep co))
        (gWireFieldSchema @(Rep d))
    )
    ( \co -> case gMatchCtor @name (from co) of
        Just d -> Just (gToTuple (from d))
        Nothing -> Nothing
    )
    (\fs -> to (gBuildCtor @name (to (gFromTuple fs) :: d)))

-- | Build a trusted 'WireCtor' for a named no-payload constructor using
-- structural Generic matching. Unlike 'mkWireCtor0', matching is not
-- mediated by the carrier's 'Eq' instance.
mkWireCtor0Via ::
  forall (name :: Symbol) co.
  ( KnownSymbol name,
    Generic co,
    GHasCtor name (Rep co) (),
    GWireCtorPath name (Rep co)
  ) =>
  WireCtor co ()
mkWireCtor0Via = mkWireCtorVia @name @co @() @()

-- | Build a trusted 'WireCtor' for a constructor whose fields are declared
-- directly with record syntax. Use 'mkWireCtorVia' for a constructor that
-- wraps a separate record value.
mkWireCtorRecordVia ::
  forall (name :: Symbol) co fields.
  ( KnownSymbol name,
    Generic co,
    GTupleCtor name (Rep co) fields,
    GWireCtorPath name (Rep co)
  ) =>
  WireCtor co fields
mkWireCtorRecordVia =
  trustedWireCtorInternal
    constructorEvidence
    (symbolVal (Proxy @name))
    ( trustedWireSchema
        (gWireCtorPath @name @(Rep co))
        (gTupleCtorSchema @name @(Rep co))
    )
    (gMatchTupleCtor @name . from)
    (to . gBuildTupleCtor @name)
