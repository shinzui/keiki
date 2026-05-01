{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}

-- | DX spike (EP-2 follow-up): generic-derived inversions between
-- Haskell records and 'RegFile's so users can build 'InCtor' values
-- without hand-rolling RCons-towers.
--
-- Status: experimental. See the EP-2 retrospective for context.
module Keiki.Generics
  ( -- * Generic-derived InCtor
    mkInCtor
  , mkInCtor0
    -- * Generic-derived WireCtor
  , mkWireCtor
  , FieldsOf
  , FieldsOfRep
    -- * Internals
  , GRecord (..)
  , GTuple (..)
  , Append
  , appendRegFile
  , SplitRegFile (..)
  , ConcatT
  , SplitT (..)
  ) where

import Data.Kind (Type)
import Data.Proxy (Proxy (..))
import GHC.Generics
import GHC.TypeLits (KnownSymbol)
import Keiki.Core


-- | Walk a 'GHC.Generics' record representation to/from a 'RegFile'.
-- Slot lists are derived from the record's field metadata: every
-- selector @M1 S ('MetaSel ('Just name) ...)@ contributes a slot
-- @'(name, fieldType)@; products concatenate.
class GRecord (rep :: Type -> Type) (ifs :: [Slot]) | rep -> ifs where
  gToRegFile   :: rep a -> RegFile ifs
  gFromRegFile :: RegFile ifs -> rep a

-- M1 D wrapper (data type metadata): pass through.
instance GRecord inner ifs => GRecord (M1 D meta inner) ifs where
  gToRegFile (M1 r) = gToRegFile r
  gFromRegFile rf   = M1 (gFromRegFile rf)

-- M1 C wrapper (constructor metadata): pass through.
instance GRecord inner ifs => GRecord (M1 C meta inner) ifs where
  gToRegFile (M1 r) = gToRegFile r
  gFromRegFile rf   = M1 (gFromRegFile rf)

-- Named selector with a leaf field: one slot.
instance KnownSymbol name
      => GRecord (M1 S ('MetaSel ('Just name) su ss ds) (K1 r t))
                 '[ '(name, t) ] where
  gToRegFile (M1 (K1 v))     = RCons (Proxy @name) v RNil
  gFromRegFile (RCons _ v _) = M1 (K1 v)

-- No-arg constructor: empty slot list.
instance GRecord U1 '[] where
  gToRegFile U1     = RNil
  gFromRegFile RNil = U1

-- Product: concatenate slot lists.
instance ( GRecord l ls
         , GRecord r rs
         , Append ls rs ~ ifs
         , SplitRegFile ls rs
         ) => GRecord (l :*: r) ifs where
  gToRegFile (a :*: b) = appendRegFile (gToRegFile a) (gToRegFile b)
  gFromRegFile rf      = case splitRegFile @ls @rs rf of
    (lrf, rrf) -> gFromRegFile lrf :*: gFromRegFile rrf


-- | Type-level append for slot lists.
type family Append (xs :: [Slot]) (ys :: [Slot]) :: [Slot] where
  Append '[]       ys = ys
  Append (x ': xs) ys = x ': Append xs ys


-- | Value-level append for register files.
appendRegFile :: RegFile ls -> RegFile rs -> RegFile (Append ls rs)
appendRegFile RNil           rs = rs
appendRegFile (RCons p v xs) rs = RCons p v (appendRegFile xs rs)


-- | Split a register file at the boundary between two slot lists.
class SplitRegFile (ls :: [Slot]) (rs :: [Slot]) where
  splitRegFile :: RegFile (Append ls rs) -> (RegFile ls, RegFile rs)

instance SplitRegFile '[] rs where
  splitRegFile rf = (RNil, rf)

instance SplitRegFile ls rs => SplitRegFile ('(s, t) ': ls) rs where
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
mkInCtor
  :: forall ci d ifs.
     ( Generic d
     , GRecord (Rep d) ifs
     , AssembleRegFile ifs
     , KnownSlotNames ifs
     )
  => String
  -> (ci -> Maybe d)
  -> (d -> ci)
  -> InCtor ci ifs
mkInCtor name match wrap = InCtor
  { icName  = name
  , icMatch = \ci -> case match ci of
      Just d  -> Just (gToRegFile (from d))
      Nothing -> Nothing
  , icBuild = \rf -> wrap (to (gFromRegFile rf))
  }


-- | Build an 'InCtor' for a no-payload (singleton) constructor. The
-- 'icMatch' compares against the named singleton via 'Eq'; 'icBuild'
-- ignores the empty 'RegFile' and returns the singleton.
--
-- Example:
--
-- > inCtorContinue :: InCtor UserCmd '[]
-- > inCtorContinue = mkInCtor0 "Continue" Continue
mkInCtor0 :: forall ci. Eq ci => String -> ci -> InCtor ci '[]
mkInCtor0 name singleton = InCtor
  { icName  = name
  , icMatch = \ci -> if ci == singleton then Just RNil else Nothing
  , icBuild = \RNil -> singleton
  }


-- * Generic-derived WireCtor ----------------------------------------------

-- | Walk a 'GHC.Generics' record representation to/from the nested-
-- pair tuple shape that 'WireCtor' / 'OutFields' carry. A record with
-- fields @f1, f2, f3@ corresponds to the tuple @(f1, (f2, (f3, ())))@.
class GTuple (rep :: Type -> Type) (fs :: Type) | rep -> fs where
  gToTuple   :: rep a -> fs
  gFromTuple :: fs -> rep a

instance GTuple inner fs => GTuple (M1 D meta inner) fs where
  gToTuple (M1 r) = gToTuple r
  gFromTuple t    = M1 (gFromTuple t)

instance GTuple inner fs => GTuple (M1 C meta inner) fs where
  gToTuple (M1 r) = gToTuple r
  gFromTuple t    = M1 (gFromTuple t)

instance GTuple (M1 S meta (K1 r t)) (t, ()) where
  gToTuple (M1 (K1 v)) = (v, ())
  gFromTuple (v, ())   = M1 (K1 v)

instance GTuple U1 () where
  gToTuple U1     = ()
  gFromTuple ()   = U1

instance ( GTuple l ls
         , GTuple r rs
         , ConcatT ls rs ~ fs
         , SplitT ls rs
         ) => GTuple (l :*: r) fs where
  gToTuple (a :*: b) = appendT (gToTuple a) (gToTuple b)
  gFromTuple t       = case splitT @ls @rs t of
    (lt, rt) -> gFromTuple lt :*: gFromTuple rt


-- | Type-level concat for nested-pair tuples. @ConcatT (f1, (f2, ())) (f3, ()) ~ (f1, (f2, (f3, ())))@.
type family ConcatT (a :: Type) (b :: Type) :: Type where
  ConcatT ()       b = b
  ConcatT (x, xs)  b = (x, ConcatT xs b)


-- | Split a concatenated nested-pair tuple back into its halves; also
-- the inverse direction (append).
class SplitT (a :: Type) (b :: Type) where
  splitT  :: ConcatT a b -> (a, b)
  appendT :: a -> b -> ConcatT a b

instance SplitT () b where
  splitT  b      = ((), b)
  appendT () b   = b

instance SplitT xs b => SplitT (x, xs) b where
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
  FieldsOfRep (M1 D _ inner)         = FieldsOfRep inner
  FieldsOfRep (M1 C _ inner)         = FieldsOfRep inner
  FieldsOfRep (M1 S _ (K1 _ t))      = (t, ())
  FieldsOfRep U1                     = ()
  FieldsOfRep (l :*: r)              = ConcatT (FieldsOfRep l) (FieldsOfRep r)


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
mkWireCtor
  :: forall co d fs.
     ( Generic d
     , GTuple (Rep d) fs
     )
  => String
  -> (co -> Maybe d)
  -> (d -> co)
  -> WireCtor co fs
mkWireCtor name match wrap = WireCtor
  { wcName  = name
  , wcMatch = \co -> case match co of
      Just d  -> Just (gToTuple (from d))
      Nothing -> Nothing
  , wcBuild = \fs -> wrap (to (gFromTuple fs))
  }
