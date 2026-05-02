{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}

-- | Type-level slot-name machinery used by the @(w :: [Symbol])@ index
-- on 'Keiki.Core.Update' (EP-18 of MasterPlan 6).
--
-- The keiki invariant is that slot names within a register file are
-- pairwise distinct. EP-18 promotes that invariant from a runtime
-- check (the old @combine@'s integer-position overlap test) to a
-- type-level constraint by:
--
--   * indexing 'Keiki.Core.Update' over @(w :: [Symbol])@, the set of
--     slot names the update writes; and
--   * requiring 'Disjoint' @w1@ @w2@ on the smart constructor that
--     combines two updates.
--
-- This module owns the type-family / GADT machinery the index uses;
-- 'Keiki.Core' and 'Keiki.Composition' import it. The 'IndexN' GADT
-- below is a slot-name-tagged variant of 'Keiki.Core.Index' so the
-- 'USet' constructor can recover its written slot's symbol at the
-- type level.
module Keiki.Internal.Slots
  ( -- * Type-level lists
    Concat
  , Member
  , Disjoint
    -- * Slot-name projection
  , Names
    -- * Slot-name-tagged register index
  , IndexN (..)
  , HasIndexN (..)
  , indexNToInt
  , indexNName
  ) where

import Data.Kind (Constraint, Type)
import GHC.OverloadedLabels (IsLabel (..))
import GHC.TypeError (ErrorMessage (..), TypeError)
import GHC.TypeLits (CmpSymbol, KnownSymbol, Symbol, symbolVal)
import Data.Proxy (Proxy (..))


-- | Type-level list concatenation on @[Symbol]@.
type family Concat (xs :: [Symbol]) (ys :: [Symbol]) :: [Symbol] where
  Concat '[]       ys = ys
  Concat (x ': xs) ys = x ': Concat xs ys


-- | Type-level membership: @True@ iff @x@ appears in @ys@. Decided by
-- 'CmpSymbol' (compile-time symbol comparison).
type family Member (x :: Symbol) (ys :: [Symbol]) :: Bool where
  Member _ '[]       = 'False
  Member x (y ': ys) = MemberCmp (CmpSymbol x y) x ys

type family MemberCmp (cmp :: Ordering) (x :: Symbol) (ys :: [Symbol]) :: Bool where
  MemberCmp 'EQ _ _   = 'True
  MemberCmp _   x  ys = Member x ys


-- | Disjointness of two slot-name sets. A 'Constraint' that fires a
-- 'TypeError' naming the duplicated symbol when an overlap is detected.
type family Disjoint (xs :: [Symbol]) (ys :: [Symbol]) :: Constraint where
  Disjoint '[]       _  = ()
  Disjoint (x ': xs) ys = (NotMember x ys, Disjoint xs ys)

-- | Per-element disjointness witness used by 'Disjoint'. Walks @ys@,
-- raising 'TypeError' when @x@ collides with an element.
type family NotMember (x :: Symbol) (ys :: [Symbol]) :: Constraint where
  NotMember _ '[]       = ()
  NotMember x (y ': ys) = (NotMemberCmp (CmpSymbol x y) x y, NotMember x ys)

type family NotMemberCmp (cmp :: Ordering) (x :: Symbol) (y :: Symbol) :: Constraint where
  NotMemberCmp 'LT _ _ = ()
  NotMemberCmp 'GT _ _ = ()
  NotMemberCmp 'EQ x _ =
    TypeError ('Text "Keiki.Internal.Slots.Disjoint: slot \""
        ':<>: 'Text x
        ':<>: 'Text "\" is written by both halves of `combine`. "
        ':$$: 'Text "Each register slot may be written at most once per edge update.")


-- | Project the slot-name list out of a slot list. The kind
-- @[(Symbol, Type)]@ is keiki's @[Slot]@ at the kind level (a synonym
-- defined in 'Keiki.Core'); written here in unfolded form to avoid a
-- circular import.
type family Names (rs :: [(Symbol, Type)]) :: [Symbol] where
  Names '[]                = '[]
  Names ('(s, _r) ': rest) = s ': Names rest


-- | A slot-name-tagged register index. Where 'Keiki.Core.Index'
-- existentially hides the slot symbol it points at, 'IndexN' carries
-- it as a phantom @s@. Used by 'Keiki.Core.USet' so the 'Update''s
-- written-slot index can be derived mechanically.
data IndexN (s :: Symbol) (rs :: [(Symbol, Type)]) (r :: Type) where
  IZ :: KnownSymbol s => IndexN s ('(s, r) ': rs) r
  IS :: IndexN s rs r -> IndexN s ('(s', r') ': rs) r


-- | Resolve a label @s@ against a slot list @rs@ to an 'IndexN' for
-- the value at that slot. The functional dependency @s rs -> r@
-- ensures that a label uniquely determines the slot's type.
class HasIndexN (s :: Symbol) (rs :: [(Symbol, Type)]) (r :: Type)
                | s rs -> r where
  indexN :: IndexN s rs r

instance {-# OVERLAPPING #-} (KnownSymbol s)
      => HasIndexN s ('(s, r) ': rs) r where
  indexN = IZ

instance {-# OVERLAPPABLE #-} forall s s' r r' rs.
         (HasIndexN s rs r)
      => HasIndexN s ('(s', r') ': rs) r where
  indexN = IS (indexN @s @rs @r)


-- | Slot-name-tagged label resolution. Lets aggregate authors write
-- @USet (#email :: IndexN "email" UserRegRegs Email) ...@ (or just
-- @USet #email ...@ when GHC can infer the type) and pick up the
-- @s@ phantom that 'Keiki.Core.USet' demands.
instance forall s rs r.
         HasIndexN s rs r
      => IsLabel s (IndexN s rs r) where
  fromLabel = indexN @s @rs @r


-- | The integer position of an 'IndexN' in its slot list.
indexNToInt :: IndexN s rs r -> Int
indexNToInt IZ     = 0
indexNToInt (IS i) = 1 + indexNToInt i


-- | The slot name carried by an 'IndexN'. Recovered from the
-- 'KnownSymbol' constraint at 'IZ'; recurses through 'IS'.
indexNName :: forall s rs r. KnownSymbol s => IndexN s rs r -> String
indexNName _ = symbolVal (Proxy @s)
