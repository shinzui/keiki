{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE TypeOperators #-}
-- 'Disjoint' on '(.=)' is the static check itself; GHC otherwise warns.
{-# OPTIONS_GHC -Wno-redundant-constraints #-}

-- | A monadic edge-builder DSL for authoring 'SymTransducer's. The
-- builder is purely additive on top of "Keiki.Core": every edge it
-- produces is a value of the existing 'Keiki.Core.Edge' type, and
-- the resulting 'Keiki.Core.SymTransducer' is consumed unchanged by
-- "Keiki.Acceptor", "Keiki.Composition", "Keiki.Decider",
-- "Keiki.Symbolic", and the example-side specs.
--
-- == Why a builder
--
-- A hand-written transducer in the AST surface needs four nested
-- pieces of boilerplate per edge: the 'Edge' record literal, an
-- @'IndexN' \"name\" Regs T@ annotation on every register write, an
-- infix @\`combine\`@ chain stitching the writes together, and an
-- @'OFCons' … 'OFNil'@ chain (plus a 'pack' prefix and a 'Just'
-- wrapper) describing the output. The builder collapses each piece:
--
--   * 'buildTransducer' assembles a 'SymTransducer' from a
--     'VertexBuilder' and three scalar arguments (initial vertex,
--     initial register file, finality predicate).
--   * 'from' tags one source vertex; 'onCmd' / 'onEpsilon' add one
--     edge each.
--   * '(.=)' adds one register write to the edge under construction.
--     The slot name flows through a type-level @(w :: [Symbol])@
--     index so that a duplicated @'(.=)'@ to the same slot fails to
--     type-check at the offending line.
--   * 'emit' takes a 'WireCtor' and an 'OutFields' and packages
--     'OPack' with the InCtor recovered from the enclosing 'onCmd'.
--     The 'OutFields' value is built with the right-associative
--     '(*:)' / 'oNil' operators (synonyms for 'OFCons' / 'OFNil').
--
-- See @docs\/research\/edge-builder-dsl-shape.md@ for the full
-- design and per-question rationale (carrier monad,
-- distinct-targets enforcement, 'goto' termination semantics, etc).
--
-- == Worked example: the EmailDelivery aggregate
--
-- @
-- import qualified Keiki.Builder as B
-- import Keiki.Builder        ((.=), (*:))
-- import qualified Prelude
--
-- emailDelivery
--   :: 'Keiki.Core.SymTransducer' ('Keiki.Core.HsPred' EmailRegs EmailCmd)
--                                  EmailRegs EmailVertex
--                                  EmailCmd EmailEvent
-- emailDelivery = B.'buildTransducer' EmailPending emptyEmailRegs
--                   (\\case EmailSentVertex -> True; _ -> False)
--                   $ Prelude.do        -- VertexBuilder is a plain Monad
--
--     B.'from' EmailPending Prelude.do  -- EdgeListBuilder is plain
--       B.'onCmd' inCtorSendEmail $ \\d -> B.do  -- EdgeBuilder is indexed
--         B.'slot' \@\"emailRecipient\" .= d.recipient
--         B.'slot' \@\"emailSubject\"   .= d.subject
--         B.'slot' \@\"emailSentAt\"    .= d.at
--         B.'emit' wireEmailSent (d.recipient *: d.subject *: d.at *: B.'oNil')
--         B.'goto' EmailSentVertex
--
--     B.'from' EmailSentVertex (Prelude.pure ())  -- terminal
-- @
--
-- The user's aggregate module needs three pragmas / imports:
--
--   * @{-\# LANGUAGE QualifiedDo \#-}@ — so @B.do@ resolves to this
--     module's indexed bind.
--   * @{-\# LANGUAGE BlockArguments \#-}@ — so a @B.do@ block can
--     appear as a function argument without parentheses.
--   * @import qualified Keiki.Builder as B@ /and/
--     @import Keiki.Builder ((.=), (*:))@ — the operators must be
--     in scope unqualified; @B.(.=)@ / @B.(*:)@ is unreadable.
--
-- == Three-layer monad shape
--
-- Three carriers, only the innermost is indexed:
--
--   1. 'VertexBuilder' (plain 'Monad') — the top-level. State is
--      a list @[(v, [Edge ...])]@; 'from' writes one entry.
--   2. 'EdgeListBuilder' (plain 'Monad') — the per-source-vertex
--      layer. State is the list of edges out of that vertex;
--      'onCmd' \/ 'onEpsilon' each prepend one.
--   3. 'EdgeBuilder' (indexed) — the per-edge body. Type-level
--      @(w :: [Symbol])@ tracks the slots written so far; '(.=)'
--      extends @w@ and inherits a 'Disjoint'-driven static check.
--
-- The 'QualifiedDo' machinery only re-binds @(>>=)@/@(>>)@ for the
-- innermost layer; the outer two use 'Prelude.do'.
--
-- == Misuse diagnostics
--
-- * Duplicate '(.=)' to the same slot: caught at compile time via
--   the 'Keiki.Internal.Slots.Disjoint' 'GHC.TypeError.TypeError',
--   which names the duplicated slot.
--
-- * Missing 'goto': caught at finalize time (when 'buildTransducer'
--   evaluates the 'VertexBuilder' do-block) with a runtime error
--   naming the source vertex and edge index.
--
-- * Multiple 'goto's in the same edge body: caught the same way.
--
-- == When to drop down to the AST
--
-- Use the AST directly when:
--
--   * The aggregate has bespoke guard logic the builder does not
--     express (a hand-built 'HsPred' tree the builder cannot
--     accumulate via 'requireEq' / 'requireGuard').
--   * The aggregate composes 'Edge' values from helper functions
--     defined elsewhere (the builder is meant to /author/ edges, not
--     to be a pluggable assembly tool).
--
-- Both directions can coexist in one module: the builder produces
-- @'SymTransducer'@s of the same type the AST does, and
-- "Keiki.Composition" 'Keiki.Composition.compose' takes the
-- builder-produced values without modification.
module Keiki.Builder
  ( -- * Top-level entry point
    buildTransducer
    -- * Vertex-level builder
  , VertexBuilder
  , from
    -- * Edge-list builder (per source vertex)
  , EdgeListBuilder
  , onCmd
  , onEpsilon
    -- * Edge body builder (per outgoing transition)
  , EdgeBuilder
    -- ** Slot writes
  , slot
  , (.=)
    -- ** Outputs
  , emit
  , emitWith
  , noEmit
    -- ** Output-fields HList sugar
  , (*:)
  , oNil
    -- ** Guards
  , requireEq
  , requireGuard
    -- ** Termination
  , goto
    -- ** Payload projection (OverloadedRecordDot)
  , PayloadProj
    -- * QualifiedDo bind/return exports
    -- $qualifiedDo
  , (>>=)
  , (>>)
  , pure
  , return
  ) where

import Data.Maybe (fromMaybe)
import Data.Typeable (Typeable)
import GHC.Records (HasField (..))
import GHC.TypeLits (KnownSymbol, Symbol)
import Prelude hiding ((>>), (>>=), pure, return)
import qualified Prelude

import Keiki.Core
  ( Edge (..)
  , HsPred (..)
  , Index
  , InCtor
  , OutFields (..)
  , OutTerm
  , RegFile
  , SymTransducer (..)
  , Term
  , Update (..)
  , WireCtor
  , combine
  , inpCtor
  , matchInCtor
  , pack
  )
import Keiki.Core qualified as K
import Keiki.Internal.Slots
  ( Concat
  , Disjoint
  , HasIndexN (..)
  , IndexN (..)
  )


-- $qualifiedDo
--
-- @QualifiedDo@ desugars @B.do { … }@ to @B.>>=@, @B.>>@, @B.pure@,
-- @B.return@. These exports are the indexed analogues that thread
-- the type-level slot-set through every edge-body step. They are
-- not the right operators for the outer 'VertexBuilder' /
-- 'EdgeListBuilder' layers — those use the regular 'Prelude.do'
-- syntax with the 'Monad' instances declared below.


-- * The per-edge state ----------------------------------------------------

-- | The growing edge state inside an 'EdgeBuilder' body. Lifecycle:
-- 'onCmd' / 'onEpsilon' construct an initial 'PartialEdge' (with
-- 'PTop' or @'matchInCtor' ic@ as guard, 'UKeep' as update, no
-- output, no targets); each step in the body modifies one or more
-- fields; 'finalizeEdge' validates that exactly one 'goto' was
-- called and packages the result into a closed 'Edge'. The
-- existential @w@ on 'Edge''s 'update' field closes here.
data PartialEdge rs ci co v (w :: [Symbol]) = PartialEdge
  { peGuard   :: HsPred rs ci
  , peUpdate  :: Update rs w ci
  , peOutput  :: Maybe (OutTerm rs ci co)
  , peTargets :: [v]
    -- ^ Reverse-order list of every 'goto' invocation in the body.
    -- Finalization requires exactly one element.
  , peInCtor  :: Maybe (PeInCtor ci)
    -- ^ The 'InCtor' bound by the enclosing 'onCmd', so that the
    -- 2-argument 'emit' can recover it without the user repeating
    -- it. 'Nothing' inside an 'onEpsilon' body — 'emit' there must
    -- use 'emitWith' to supply the 'InCtor' explicitly.
  }


-- | Existential wrapper hiding the @ifs@ slot list of an 'InCtor'.
-- Stored on 'PartialEdge' by 'onCmd' and read back by 'emit'.
--
-- This is a builder-local existential rather than a reuse of
-- 'Keiki.Symbolic.SomeInCtor' because the latter carries an
-- 'ExtractRegFile' constraint the builder does not need and lives
-- in a module that pulls SBV; reusing it would add an SBV edge to
-- every consumer of "Keiki.Builder".
data PeInCtor ci where
  PeInCtor :: InCtor ci ifs -> PeInCtor ci


-- | The per-edge indexed-state monad. The two phantom slot-set
-- indices @(w :: [Symbol])@ (before this step) and @(w' :: [Symbol])@
-- (after this step) make every '(.=)' visible to the type system,
-- so a duplicated @'(.=)'@ to the same slot fails at the offending
-- line via the 'Keiki.Internal.Slots.Disjoint' constraint that
-- 'Keiki.Core.combine' carries.
--
-- Functor / Applicative / Monad instances are not provided because
-- they would be 'IxFunctor' / 'IxApplicative' / 'IxMonad' (the
-- type-level slot-set changes between operand and result), which
-- requires a separate type-class hierarchy. Instead, this module
-- exports its own @(>>=)@ / @(>>)@ / 'pure' / 'return' for use
-- with @QualifiedDo@.
newtype EdgeBuilder rs ci co v (w :: [Symbol]) (w' :: [Symbol]) a
  = EdgeBuilder
      { runEdgeBuilder :: PartialEdge rs ci co v w
                       -> (a, PartialEdge rs ci co v w') }


-- * QualifiedDo bind/return exports ----------------------------------------

-- | Indexed bind. The @w@ index of the first argument flows through
-- the second argument's @w@ argument, and the second argument's @w'@
-- index becomes the result's @w'@. Re-export for @QualifiedDo@.
(>>=)
  :: EdgeBuilder rs ci co v w1 w2 a
  -> (a -> EdgeBuilder rs ci co v w2 w3 b)
  -> EdgeBuilder rs ci co v w1 w3 b
EdgeBuilder f >>= k = EdgeBuilder $ \pe ->
  let (a, pe1)        = f pe
      EdgeBuilder g   = k a
  in g pe1
infixl 1 >>=


-- | Sequence. Defined in terms of '(>>=)'.
(>>)
  :: EdgeBuilder rs ci co v w1 w2 a
  -> EdgeBuilder rs ci co v w2 w3 b
  -> EdgeBuilder rs ci co v w1 w3 b
m >> n = m Keiki.Builder.>>= \_ -> n
infixl 1 >>


-- | Embed a value. Slot-set unchanged.
pure :: a -> EdgeBuilder rs ci co v w w a
pure a = EdgeBuilder $ \pe -> (a, pe)


-- | Synonym for 'pure'. Re-exported for @QualifiedDo@.
return :: a -> EdgeBuilder rs ci co v w w a
return = Keiki.Builder.pure


-- * Slot writes ----------------------------------------------------------

-- | Lift a slot name (supplied via @TypeApplication@) to its
-- slot-name-tagged register index. Use with '(.=)':
--
-- > slot @"emailRecipient" .= d.recipient
--
-- == Why @slot \@\"name\"@ instead of @\#name@
--
-- The @\#name@ overloaded-label syntax tries to resolve
-- @IsLabel \"name\" (IndexN s rs r)@ against the instance head
-- @IsLabel s (IndexN s rs r)@. GHC will not commit to @s ~ \"name\"@
-- when @name@ is a quantified type variable in the enclosing
-- operator's signature (the pattern-side @s@ appears at two
-- positions in the constraint head; without an explicit annotation,
-- GHC defers commitment). 'slot' pins the symbol via TypeApplication
-- so the inference proceeds without ambiguity. Slot name still
-- appears once.
slot
  :: forall (name :: Symbol) rs r.
     ( KnownSymbol name, HasIndexN name rs r )
  => IndexN name rs r
slot = indexN @name @rs @r


-- | Slot assignment. The slot name is supplied by 'slot' (via
-- TypeApplication); the value is a 'Term'. The
-- @'Disjoint' '[name] w@ constraint inherits the type-level
-- distinct-targets check from 'Keiki.Core.combine': a duplicated
-- @'(.=)'@ to the same slot fails to type-check at the offending
-- line, with the existing 'Keiki.Internal.Slots.Disjoint'
-- 'GHC.TypeError.TypeError' naming the slot.
--
-- The RHS is a 'Term' (not a bare value); use
-- 'Keiki.Core.lit' / 'Keiki.Core.proj' / 'Keiki.Core.inpCtor' or
-- @d.fieldName@ via 'PayloadProj' to construct it.
(.=)
  :: forall name r rs ci co v w.
     ( KnownSymbol name, Disjoint '[name] w )
  => IndexN name rs r
  -> Term rs ci r
  -> EdgeBuilder rs ci co v w (Concat '[name] w) ()
ix .= t = EdgeBuilder $ \pe ->
  ((), pe { peUpdate = USet ix t `combine` peUpdate pe })
infixr 6 .=


-- * Termination -----------------------------------------------------------

-- | Set the edge's target vertex. Required exactly once per edge
-- body; missing 'goto' produces a finalize-time runtime error
-- naming the source vertex and edge index, and so does multiple
-- 'goto's in the same body.
goto :: v -> EdgeBuilder rs ci co v w w ()
goto v = EdgeBuilder $ \pe ->
  ((), pe { peTargets = v : peTargets pe })


-- * Outputs ---------------------------------------------------------------

-- | Emit an event. Takes the wire-side 'WireCtor' and an 'OutFields'
-- HList of 'Term's matching the wire ctor's field schema. The
-- input-side 'InCtor' is recovered from the enclosing 'onCmd'; an
-- 'emit' inside 'onEpsilon' (where no 'InCtor' is bound) raises a
-- finalize-time error directing the user to 'emitWith'.
emit
  :: forall co fs rs ci v w.
     WireCtor co fs
  -> OutFields rs ci fs
  -> EdgeBuilder rs ci co v w w ()
emit wc fs = EdgeBuilder $ \pe -> case peInCtor pe of
  Just (PeInCtor ic) ->
    ((), pe { peOutput = Just (pack ic wc fs) })
  Nothing ->
    error "Keiki.Builder.emit: no enclosing onCmd pinned an InCtor. \
          \Use 'emitWith ic wc fs' inside 'onEpsilon', or move the \
          \emit inside an 'onCmd' block."


-- | Emit an event with an explicit 'InCtor'. The escape hatch for
-- 'onEpsilon' bodies (which do not pin an 'InCtor') and for any
-- caller that needs to override the one bound by the enclosing
-- 'onCmd'. Inside 'onCmd' the InCtor-less 'emit' is preferred.
emitWith
  :: forall co fs rs ci v w ifs.
     InCtor ci ifs
  -> WireCtor co fs
  -> OutFields rs ci fs
  -> EdgeBuilder rs ci co v w w ()
emitWith ic wc fs = EdgeBuilder $ \pe ->
  ((), pe { peOutput = Just (pack ic wc fs) })


-- | Mark the edge as ε-output (no event). Idempotent: an edge with
-- no 'emit' or 'noEmit' call is also an ε-edge by default; 'noEmit'
-- exists only so the user can be explicit about intent.
noEmit :: EdgeBuilder rs ci co v w w ()
noEmit = EdgeBuilder $ \pe -> ((), pe)


-- | Right-associative HList constructor synonym for 'OFCons'.
-- Lets 'emit' call sites read top-to-bottom in the wire ctor's
-- field order:
--
-- > B.emit wireEmailSent (d.recipient *: d.subject *: d.at *: oNil)
--
-- Identical AST: @t1 *: t2 *: oNil@ produces the same 'OutFields'
-- value as @OFCons t1 (OFCons t2 OFNil)@. Provided as the
-- intermediate step before the field-keyed record form (M5).
(*:) :: Term rs ci f -> OutFields rs ci fs -> OutFields rs ci (f, fs)
(*:) = OFCons
infixr 5 *:


-- | The empty 'OutFields' HList. Synonym for 'OFNil'.
oNil :: OutFields rs ci ()
oNil = OFNil


-- * Guards ----------------------------------------------------------------

-- | Conjoin an arbitrary 'HsPred' with the edge's existing guard.
-- Use this when the structural sugar of 'requireEq' is not enough
-- (e.g. for negated predicates, disjunctions, or guards constructed
-- by helper functions).
requireGuard :: HsPred rs ci -> EdgeBuilder rs ci co v w w ()
requireGuard p = EdgeBuilder $ \pe ->
  ((), pe { peGuard = PAnd (peGuard pe) p })


-- | Conjoin an equality predicate (@a '==' b@) with the edge's
-- existing guard.
requireEq
  :: (Eq r, Typeable r)
  => Term rs ci r
  -> Term rs ci r
  -> EdgeBuilder rs ci co v w w ()
requireEq a b = requireGuard (PEq a b)


-- * Payload projection ----------------------------------------------------

-- | An opaque wrapper around an 'InCtor' that lets the user project
-- the input symbol's fields via 'OverloadedRecordDot' inside an
-- 'onCmd' body. The 'HasField' instance translates @d.fieldName@ to
-- @inpCtor ic (indexN \@fieldName \@ifs \@r)@.
--
-- 'PayloadProj' has no record selectors of its own so the user's
-- @d.fieldName@ never collides with a built-in selector.
data PayloadProj rs ci ifs = PayloadProj (InCtor ci ifs)


-- | OverloadedRecordDot resolution: @d.fieldName@ on a 'PayloadProj'
-- builds a 'TInpCtorField' term that projects the named field of the
-- input symbol's payload.
instance ( HasIndexN name ifs r )
      => HasField name (PayloadProj rs ci ifs) (Term rs ci r) where
  getField (PayloadProj ic) =
    inpCtor ic (indexNToIndex (indexN @name @ifs @r))


-- | Translate the slot-name-tagged 'IndexN' into the legacy
-- existentially-typed 'Index' that 'Keiki.Core.inpCtor' expects.
-- Both indices have the same runtime structure; the translation is
-- a structural recursion. (M3+ may widen 'inpCtor' to take 'IndexN'
-- directly; this helper keeps the spike's legacy bridge.)
indexNToIndex :: forall name rs r. IndexN name rs r -> Index rs r
indexNToIndex IZ      = K.ZIdx
indexNToIndex (IS i)  = K.SIdx (indexNToIndex i)


-- * Edge-list builder -----------------------------------------------------

-- | Per-source-vertex builder. Accumulates a list of 'Edge' values,
-- one per 'onCmd' / 'onEpsilon' call. The source vertex is read
-- from the 'from' caller's argument (threaded as the first state
-- field). The list is built head-prepended for cheap concatenation
-- and reversed in 'from' before storage.
newtype EdgeListBuilder rs ci co v a = EdgeListBuilder
  { runEdgeListBuilder :: v
                       -> [Edge (HsPred rs ci) rs ci co v]
                       -> (a, [Edge (HsPred rs ci) rs ci co v]) }


instance Functor (EdgeListBuilder rs ci co v) where
  fmap f (EdgeListBuilder k) = EdgeListBuilder $ \src es ->
    let (a, es') = k src es in (f a, es')


instance Applicative (EdgeListBuilder rs ci co v) where
  pure a = EdgeListBuilder $ \_ es -> (a, es)
  EdgeListBuilder kf <*> EdgeListBuilder ka = EdgeListBuilder $ \src es ->
    let (f, es1) = kf src es
        (a, es2) = ka src es1
    in (f a, es2)


instance Monad (EdgeListBuilder rs ci co v) where
  (>>=) (EdgeListBuilder k) f = EdgeListBuilder $ \src es ->
    let (a, es') = k src es
        EdgeListBuilder k' = f a
    in k' src es'


-- | Per-edge entry. Wires the InCtor's match-guard, gives the user
-- a 'PayloadProj' handle (so OverloadedRecordDot resolves
-- @d.field@), runs the body to accumulate the edge, and finalizes
-- into a closed 'Edge'.
onCmd
  :: forall ci ifs rs co v w.
     Show v
  => InCtor ci ifs
  -> (PayloadProj rs ci ifs -> EdgeBuilder rs ci co v '[] w ())
  -> EdgeListBuilder rs ci co v ()
onCmd ic body = EdgeListBuilder $ \src edges ->
  let initial = PartialEdge
        { peGuard   = matchInCtor ic
        , peUpdate  = UKeep
        , peOutput  = Nothing
        , peTargets = []
        , peInCtor  = Just (PeInCtor ic)
        }
      (_, finalPE) = runEdgeBuilder (body (PayloadProj ic)) initial
      edgeIx       = length edges
  in ((), finalizeEdge edgeIx src finalPE : edges)


-- | ε-edge entry: no input projection, no input-ctor match-guard.
-- The guard starts at 'PTop' (so any conjuncts the body adds via
-- 'requireEq' / 'requireGuard' constitute the full guard). Inside
-- the body, no 'PayloadProj' is supplied, so 'OverloadedRecordDot'
-- access to the input is unavailable; use 'Keiki.Core.inpCtor'
-- directly with an explicit 'InCtor' if needed.
onEpsilon
  :: forall rs ci co v w.
     Show v
  => EdgeBuilder rs ci co v '[] w ()
  -> EdgeListBuilder rs ci co v ()
onEpsilon body = EdgeListBuilder $ \src edges ->
  let initial = PartialEdge
        { peGuard   = PTop
        , peUpdate  = UKeep
        , peOutput  = Nothing
        , peTargets = []
        , peInCtor  = Nothing
        }
      (_, finalPE) = runEdgeBuilder body initial
      edgeIx       = length edges
  in ((), finalizeEdge edgeIx src finalPE : edges)


-- | Close a 'PartialEdge' into an 'Edge'. The existential @w@ on
-- 'Edge''s 'update' field closes here. Validation: 'peTargets' must
-- have exactly one entry; missing or duplicated 'goto' calls raise
-- a runtime 'error' naming the source vertex and edge index.
finalizeEdge
  :: Show v
  => Int
  -> v
  -> PartialEdge rs ci co v w
  -> Edge (HsPred rs ci) rs ci co v
finalizeEdge n src pe = case peTargets pe of
  [t]      -> Edge { guard  = peGuard pe
                   , update = peUpdate pe
                   , output = peOutput pe
                   , target = t
                   }
  []       -> error $ "Keiki.Builder: edge #" <> show n <> " from "
                   <> show src <> ": goto missing. Each onCmd/"
                   <> "onEpsilon body must end with exactly one goto V."
  (_:_:_)  -> error $ "Keiki.Builder: edge #" <> show n <> " from "
                   <> show src <> ": goto called more than once. "
                   <> "Each onCmd/onEpsilon body must end with "
                   <> "exactly one goto V."


-- * Vertex builder --------------------------------------------------------

-- | Top-level builder. Accumulates @[(v, [Edge ...])]@ entries, one
-- per 'from' call. 'buildTransducer' converts the result into a
-- 'SymTransducer''s 'edgesOut' function via @lookup@ with @[]@ as
-- default for unmentioned vertices.
newtype VertexBuilder rs ci co v a = VertexBuilder
  { runVertexBuilder :: [(v, [Edge (HsPred rs ci) rs ci co v])]
                     -> (a, [(v, [Edge (HsPred rs ci) rs ci co v])]) }


instance Functor (VertexBuilder rs ci co v) where
  fmap f (VertexBuilder k) = VertexBuilder $ \vs ->
    let (a, vs') = k vs in (f a, vs')


instance Applicative (VertexBuilder rs ci co v) where
  pure a = VertexBuilder $ \vs -> (a, vs)
  VertexBuilder kf <*> VertexBuilder ka = VertexBuilder $ \vs ->
    let (f, vs1) = kf vs
        (a, vs2) = ka vs1
    in (f a, vs2)


instance Monad (VertexBuilder rs ci co v) where
  (>>=) (VertexBuilder k) f = VertexBuilder $ \vs ->
    let (a, vs') = k vs
        VertexBuilder k' = f a
    in k' vs'


-- | Group edges by source vertex. The argument is an
-- 'EdgeListBuilder' do-block of 'onCmd' / 'onEpsilon' calls; each
-- call adds one outgoing edge to the named vertex.
--
-- A vertex not mentioned in any 'from' block defaults to @[]@
-- (terminal). To assert "this vertex is terminal" explicitly, write
-- @from V (Prelude.pure ())@.
from
  :: Show v
  => v
  -> EdgeListBuilder rs ci co v ()
  -> VertexBuilder rs ci co v ()
from v eb = VertexBuilder $ \vs ->
  let (_, edges) = runEdgeListBuilder eb v []
  in ((), (v, Prelude.reverse edges) : vs)


-- | Top-level entry. Run the 'VertexBuilder' do-block to produce a
-- list of @(vertex, edges)@ pairs, then assemble a 'SymTransducer'
-- from the initial vertex, initial register file, finality
-- predicate, and a closure over the lookup table.
--
-- The @Bounded v@ / @Enum v@ constraints are not currently used by
-- 'buildTransducer' itself but are recorded as reserved for a
-- future @withCompletenessCheck@ combinator that would assert every
-- vertex appears in some 'from' block.
buildTransducer
  :: forall rs ci co v.
     (Bounded v, Enum v, Eq v, Show v)
  => v
  -> RegFile rs
  -> (v -> Bool)
  -> VertexBuilder rs ci co v ()
  -> SymTransducer (HsPred rs ci) rs v ci co
buildTransducer initS initR isF vb = SymTransducer
  { edgesOut    = \v -> fromMaybe [] (Prelude.lookup v vmap)
  , initial     = initS
  , initialRegs = initR
  , isFinal     = isF
  }
  where
    (_, vmap) = runVertexBuilder vb []
