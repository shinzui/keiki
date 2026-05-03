{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs             #-}
-- The 'NoThunks' instances for 'RegFile' are deliberate orphans: the
-- type lives in "Keiki.Core" (which stays free of observability deps)
-- and the class lives in @nothunks@. See the Decision Log of
-- @docs/plans/23-nothunks-instances-for-regfile-and-symtransducer-state.md@.
{-# OPTIONS_GHC -Wno-orphans #-}
-- | 'NoThunks' instances for keiki state types.
--
-- Long-running embedders that keep aggregate state in memory across
-- many @step@ calls can wrap each step's resulting state in
-- @noThunks ["regfile", "vertex"] (s, regs)@ to detect leaked thunks
-- before they accumulate.
--
-- Scope is intentionally narrow: data-bearing state types only
-- ('RegFile', 'Composite'). Function-bearing types ('Edge',
-- 'SymTransducer', 'HsPred', 'Term', 'OutTerm', 'Update') are excluded
-- — 'NoThunks' cannot meaningfully inspect Haskell closures, so
-- instances would be vacuous.
--
-- The 'RegFile' instance recurses on the slot spine. The @r@ field on
-- 'RCons' is lazy by construction (see 'Keiki.Core.RegFile'); this
-- instance is the canonical way to detect a thunk that has accumulated
-- in a slot value across repeated 'Keiki.Core.runUpdate' calls.
module Keiki.NoThunks () where

import NoThunks.Class (NoThunks (..), allNoThunks)
import Keiki.Core (RegFile (..))


instance NoThunks (RegFile '[]) where
  showTypeOf _   = "RegFile '[]"
  wNoThunks _ RNil = pure Nothing


instance (NoThunks r, NoThunks (RegFile rs))
      => NoThunks (RegFile ('(s, r) ': rs)) where
  showTypeOf _ = "RegFile (s ': rs)"
  wNoThunks ctx (RCons _proxy r rest) = allNoThunks
    [ noThunks ("RCons.value" : ctx) r
    , noThunks ("RCons.tail"  : ctx) rest
    ]
