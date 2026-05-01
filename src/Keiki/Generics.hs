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
    -- * Internals
  , GRecord (..)
  , Append
  , appendRegFile
  , SplitRegFile (..)
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
