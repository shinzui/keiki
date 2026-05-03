{-# LANGUAGE GADTs #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Existential wrapper for 'SymTransducer' enabling participation in
-- the standard 'Profunctor' / 'Category' ecosystem, plus standalone
-- variance combinators on the concrete 'SymTransducer' type.
--
-- The wrapper 'SomeSymTransducer ci co' hides the register-file slot
-- list and the control-vertex type, exposing only the input alphabet
-- @ci@ and the output alphabet @co@. This is the form ecosystem
-- typeclasses ('Profunctor', 'Category', 'Strong', 'Choice', 'Arrow')
-- expect.
--
-- See @docs/plans/27-existential-wrapper-for-symtransducer-plus-profunctor-instance-and-variance-combinators.md@
-- for the design rationale and the documented variance caveat:
-- transducers produced by 'lmapCi' / 'rmapCo' / 'dimapTransducer' /
-- 'lmapMaybeCi' do *not* preserve the round-trip guarantee of
-- 'Keiki.Core.solveOutput'. Forward processing
-- ('Keiki.Core.delta', 'Keiki.Core.omega', 'Keiki.Core.evalPred',
-- 'Keiki.Core.evalTerm') is unaffected; only the inversion-from-event
-- path is dropped on lmapped/rmapped edges. See each combinator's
-- haddock for the precise contract.
module Keiki.Profunctor
  ( -- * Existential wrapper
    SomeSymTransducer (..)
  , someSymTransducer
    -- * Standalone variance combinators on the concrete 'SymTransducer'
  , lmapCi
  , rmapCo
  , dimapTransducer
  , lmapMaybeCi
  ) where

import Data.Profunctor (Profunctor (..))

import Keiki.Core


-- | Existential wrapper hiding @rs@ (register-file slot list) and
-- @s@ (control vertex), exposing only the input alphabet @ci@ and
-- output alphabet @co@. Predicate carrier is fixed to 'HsPred' since
-- "Keiki.Composition"'s combinators are pinned to that carrier.
--
-- Pattern-match on the constructor to recover the underlying
-- 'SymTransducer' (the @rs@ and @s@ variables come into scope as
-- skolem types — they may not escape the pattern match).
data SomeSymTransducer ci co where
  SomeSymTransducer
    :: SymTransducer (HsPred rs ci) rs s ci co
    -> SomeSymTransducer ci co


-- | Smart constructor: lift a concrete 'SymTransducer' into the
-- wrapper. Equivalent to applying the data constructor; provided for
-- naming consistency with the rest of @Keiki.Profunctor@'s exports
-- and for users who prefer functions over constructors.
someSymTransducer
  :: SymTransducer (HsPred rs ci) rs s ci co
  -> SomeSymTransducer ci co
someSymTransducer = SomeSymTransducer


-- * Standalone variance combinators ---------------------------------------

-- | Pre-compose with a contramap on the input alphabet. Walks every
-- 'InCtor' inside the transducer's guards / updates / outputs and
-- replaces each with one whose 'icMatch' is precomposed with @f@.
--
-- /Variance caveat:/ the rewritten 'InCtor's 'icBuild' is poisoned
-- (raises a runtime error if invoked) — callers must not invoke
-- 'Keiki.Core.solveOutput' on edges produced by this combinator. The
-- forward evaluation path ('Keiki.Core.evalPred',
-- 'Keiki.Core.evalTerm', 'Keiki.Core.delta', 'Keiki.Core.omega') only
-- ever consults 'icMatch'; it is unaffected by the poisoned
-- 'icBuild'.
lmapCi
  :: forall ci ci' rs s co.
     (ci' -> ci)
  -> SymTransducer (HsPred rs ci)  rs s ci  co
  -> SymTransducer (HsPred rs ci') rs s ci' co
lmapCi f t = SymTransducer
  { edgesOut    = \s -> map (rewriteEdge f) (edgesOut t s)
  , initial     = initial t
  , initialRegs = initialRegs t
  , isFinal     = isFinal t
  }


-- | Pre-compose with a partial contramap on the input alphabet.
-- Inputs for which @f@ returns 'Nothing' fail every guard's
-- structural 'PInCtor' check, effectively filtering them out of the
-- transducer's command stream.
--
-- /Variance caveat:/ same as 'lmapCi' — 'Keiki.Core.solveOutput' is
-- not preserved.
lmapMaybeCi
  :: forall ci ci' rs s co.
     (ci' -> Maybe ci)
  -> SymTransducer (HsPred rs ci)  rs s ci  co
  -> SymTransducer (HsPred rs ci') rs s ci' co
lmapMaybeCi f t = SymTransducer
  { edgesOut    = \s -> map (rewriteEdgeMaybe f) (edgesOut t s)
  , initial     = initial t
  , initialRegs = initialRegs t
  , isFinal     = isFinal t
  }


-- | Post-compose with a covariant map on the output alphabet. Walks
-- every 'WireCtor' inside the transducer's outputs and replaces each
-- with one whose 'wcBuild' is post-composed with @g@.
--
-- /Variance caveat:/ the rewritten 'WireCtor's 'wcMatch' is set to
-- @const Nothing@ — 'Keiki.Core.solveOutput' on rewritten edges
-- returns 'Nothing'. The forward output construction (which only
-- uses 'wcBuild') is unaffected.
rmapCo
  :: forall ci co co' rs s.
     (co -> co')
  -> SymTransducer (HsPred rs ci) rs s ci co
  -> SymTransducer (HsPred rs ci) rs s ci co'
rmapCo g t = SymTransducer
  { edgesOut    = \s -> map (rewriteEdgeOut g) (edgesOut t s)
  , initial     = initial t
  , initialRegs = initialRegs t
  , isFinal     = isFinal t
  }


-- | Bidirectional map on input and output alphabets. Equivalent to
-- @'rmapCo' g . 'lmapCi' f@. /Variance caveat/ as both 'lmapCi' and
-- 'rmapCo': 'Keiki.Core.solveOutput' is not preserved on the result.
dimapTransducer
  :: (ci' -> ci)
  -> (co  -> co')
  -> SymTransducer (HsPred rs ci)  rs s ci  co
  -> SymTransducer (HsPred rs ci') rs s ci' co'
dimapTransducer f g = rmapCo g . lmapCi f


-- * Profunctor / Functor instances on the wrapper -----------------------

-- | Standard 'Data.Profunctor.Profunctor' instance. Delegates to the
-- standalone combinators above. Inherits their /variance caveat/:
-- 'lmap' / 'rmap' / 'dimap' on the wrapper produce transducers whose
-- 'Keiki.Core.solveOutput' is no longer informative — see each
-- combinator's haddock.
instance Profunctor SomeSymTransducer where
  dimap f g (SomeSymTransducer t) =
    SomeSymTransducer (dimapTransducer f g t)
  lmap  f   (SomeSymTransducer t) =
    SomeSymTransducer (lmapCi f t)
  rmap    g (SomeSymTransducer t) =
    SomeSymTransducer (rmapCo g t)


-- | 'Functor' on the output alphabet. @'fmap' = 'rmap'@.
instance Functor (SomeSymTransducer ci) where
  fmap = rmap


-- * Internal rewriters --------------------------------------------------

-- These walk the closed AST of 'Edge', 'HsPred', 'Update', 'Term',
-- 'OutTerm', 'OutFields', 'InCtor', and 'WireCtor', threading a
-- contramap on @ci@ (or a covariant map on @co@) through every
-- position the type parameter occupies.

-- | Contramap an 'InCtor' over its alphabet. The resulting 'InCtor's
-- 'icBuild' is poisoned: callers must not invoke
-- 'Keiki.Core.solveOutput' on edges built from this 'InCtor'.
contraInCtor :: (ci' -> ci) -> InCtor ci ifs -> InCtor ci' ifs
contraInCtor f InCtor { icName = n, icMatch = m } = InCtor
  { icName  = n
  , icMatch = m . f
  , icBuild = poisonedIcBuild n
  }


-- | Partial-contramap an 'InCtor'. The 'icMatch' becomes
-- @\ci' -> f ci' >>= m@; 'icBuild' is poisoned (same caveat as
-- 'contraInCtor').
contraMaybeInCtor :: (ci' -> Maybe ci) -> InCtor ci ifs -> InCtor ci' ifs
contraMaybeInCtor f InCtor { icName = n, icMatch = m } = InCtor
  { icName  = n
  , icMatch = \ci' -> f ci' >>= m
  , icBuild = poisonedIcBuild n
  }


poisonedIcBuild :: String -> a -> b
poisonedIcBuild icN = \_ -> error
  ( "Keiki.Profunctor: icBuild on a contramapped InCtor \""
    <> icN
    <> "\" was invoked. lmapCi/lmapMaybeCi-rewritten transducers \
       \cannot rebuild ci from a wire event via solveOutput. See \
       \the haddock for Keiki.Profunctor.lmapCi."
  )


-- | Covariant map a 'WireCtor' over its alphabet. The resulting
-- 'WireCtor's 'wcMatch' is set to @const Nothing@.
mapWireCtor :: (co -> co') -> WireCtor co fs -> WireCtor co' fs
mapWireCtor g WireCtor { wcName = n, wcBuild = b } = WireCtor
  { wcName  = n
  , wcMatch = \_co' -> Nothing
  , wcBuild = g . b
  }


-- ** Term ---------------------------------------------------------------

contraTerm :: forall ci ci' rs r. (ci' -> ci) -> Term rs ci r -> Term rs ci' r
contraTerm f = go
  where
    go :: forall a. Term rs ci a -> Term rs ci' a
    go (TLit r)              = TLit r
    go (TReg ix)             = TReg ix
    go (TInpCtorField ic ix) = TInpCtorField (contraInCtor f ic) ix
    go (TApp1 h a)           = TApp1 h (go a)
    go (TApp2 h a b)         = TApp2 h (go a) (go b)


contraMaybeTerm :: forall ci ci' rs r. (ci' -> Maybe ci) -> Term rs ci r -> Term rs ci' r
contraMaybeTerm f = go
  where
    go :: forall a. Term rs ci a -> Term rs ci' a
    go (TLit r)              = TLit r
    go (TReg ix)             = TReg ix
    go (TInpCtorField ic ix) = TInpCtorField (contraMaybeInCtor f ic) ix
    go (TApp1 h a)           = TApp1 h (go a)
    go (TApp2 h a b)         = TApp2 h (go a) (go b)


-- ** HsPred -------------------------------------------------------------

contraPred :: forall ci ci' rs. (ci' -> ci) -> HsPred rs ci -> HsPred rs ci'
contraPred f = go
  where
    go :: HsPred rs ci -> HsPred rs ci'
    go PTop         = PTop
    go PBot         = PBot
    go (PAnd p q)   = PAnd (go p) (go q)
    go (POr  p q)   = POr  (go p) (go q)
    go (PNot p)     = PNot (go p)
    go (PEq  a b)   = PEq  (contraTerm f a) (contraTerm f b)
    go (PInCtor ic) = PInCtor (contraInCtor f ic)


contraMaybePred :: forall ci ci' rs. (ci' -> Maybe ci) -> HsPred rs ci -> HsPred rs ci'
contraMaybePred f = go
  where
    go :: HsPred rs ci -> HsPred rs ci'
    go PTop         = PTop
    go PBot         = PBot
    go (PAnd p q)   = PAnd (go p) (go q)
    go (POr  p q)   = POr  (go p) (go q)
    go (PNot p)     = PNot (go p)
    go (PEq  a b)   = PEq  (contraMaybeTerm f a) (contraMaybeTerm f b)
    go (PInCtor ic) = PInCtor (contraMaybeInCtor f ic)


-- ** Update -------------------------------------------------------------

contraUpdate :: forall ci ci' rs w. (ci' -> ci) -> Update rs w ci -> Update rs w ci'
contraUpdate f = go
  where
    go :: forall w'. Update rs w' ci -> Update rs w' ci'
    go UKeep            = UKeep
    go (USet ixn term)  = USet ixn (contraTerm f term)
    go (UCombine u1 u2) = UCombine (go u1) (go u2)


contraMaybeUpdate :: forall ci ci' rs w. (ci' -> Maybe ci) -> Update rs w ci -> Update rs w ci'
contraMaybeUpdate f = go
  where
    go :: forall w'. Update rs w' ci -> Update rs w' ci'
    go UKeep            = UKeep
    go (USet ixn term)  = USet ixn (contraMaybeTerm f term)
    go (UCombine u1 u2) = UCombine (go u1) (go u2)


-- ** OutTerm + OutFields -----------------------------------------------

contraOutTerm :: (ci' -> ci) -> OutTerm rs ci co -> OutTerm rs ci' co
contraOutTerm f (OPack ic wc fields) =
  OPack (contraInCtor f ic) wc (contraOutFields f fields)


contraOutFields :: forall ci ci' rs fs. (ci' -> ci) -> OutFields rs ci fs -> OutFields rs ci' fs
contraOutFields f = go
  where
    go :: forall fs'. OutFields rs ci fs' -> OutFields rs ci' fs'
    go OFNil          = OFNil
    go (OFCons t fs)  = OFCons (contraTerm f t) (go fs)


contraMaybeOutTerm :: (ci' -> Maybe ci) -> OutTerm rs ci co -> OutTerm rs ci' co
contraMaybeOutTerm f (OPack ic wc fields) =
  OPack (contraMaybeInCtor f ic) wc (contraMaybeOutFields f fields)


contraMaybeOutFields :: forall ci ci' rs fs. (ci' -> Maybe ci) -> OutFields rs ci fs -> OutFields rs ci' fs
contraMaybeOutFields f = go
  where
    go :: forall fs'. OutFields rs ci fs' -> OutFields rs ci' fs'
    go OFNil          = OFNil
    go (OFCons t fs)  = OFCons (contraMaybeTerm f t) (go fs)


-- | Covariant map of a single OPack over its co alphabet.
mapOutTermCo :: (co -> co') -> OutTerm rs ci co -> OutTerm rs ci co'
mapOutTermCo g (OPack ic wc fields) =
  OPack ic (mapWireCtor g wc) fields


-- ** Edge ---------------------------------------------------------------

rewriteEdge :: (ci' -> ci) -> Edge (HsPred rs ci) rs ci co s -> Edge (HsPred rs ci') rs ci' co s
rewriteEdge f Edge { guard = g, update = u, output = mo, target = tgt } = Edge
  { guard  = contraPred f g
  , update = contraUpdate f u
  , output = fmap (contraOutTerm f) mo
  , target = tgt
  }


rewriteEdgeMaybe
  :: (ci' -> Maybe ci)
  -> Edge (HsPred rs ci) rs ci co s
  -> Edge (HsPred rs ci') rs ci' co s
rewriteEdgeMaybe f Edge { guard = g, update = u, output = mo, target = tgt } = Edge
  { guard  = contraMaybePred f g
  , update = contraMaybeUpdate f u
  , output = fmap (contraMaybeOutTerm f) mo
  , target = tgt
  }


rewriteEdgeOut
  :: (co -> co')
  -> Edge (HsPred rs ci) rs ci co s
  -> Edge (HsPred rs ci) rs ci co' s
rewriteEdgeOut g Edge { guard = guardP, update = u, output = mo, target = tgt } = Edge
  { guard  = guardP
  , update = u
  , output = fmap (mapOutTermCo g) mo
  , target = tgt
  }
