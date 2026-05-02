{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE QualifiedDo #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeOperators #-}
-- 'Disjoint' on '(.=)' is the static check itself; GHC otherwise warns.
{-# OPTIONS_GHC -Wno-redundant-constraints #-}
-- The spike defines several public API names that the toy transducer
-- does not exercise (pure, return, requireGuard, requireEq,
-- onEpsilon); they are kept so M3 inherits the full surface.
{-# OPTIONS_GHC -Wno-unused-top-binds #-}

-- | Spike for EP-15 M2: validate the M1 design of 'Keiki.Builder'
-- against a tiny coffee-dispenser two-vertex toy. The full builder
-- machinery is *inlined* in this module so M3 can promote a working
-- shape into the production module 'Keiki.Builder'. The test suite
-- below asserts that the builder-form transducer agrees byte-for-byte
-- with a hand-written AST reference on a 4-step input log.
--
-- This module is test-only and is rewritten on top of 'Keiki.Builder'
-- (or deleted) at M3 finalize.
module Keiki.BuilderSpike (spec) where

import Control.Exception (evaluate)
import Data.Maybe (fromMaybe)
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Data.Typeable (Typeable)
import GHC.Generics (Generic)
import GHC.Records (HasField (..))
import GHC.TypeLits (KnownSymbol, Symbol)
import Test.Hspec
import Prelude hiding ((>>), (>>=), pure, return)
import qualified Prelude

import Keiki.Core
  ( Edge (..)
  , HsPred (..)
  , IndexN (..)
  , InCtor
  , OutFields (..)
  , OutTerm
  , RegFile
  , SymTransducer (..)
  , Term (..)
  , Update (..)
  , WireCtor
  , combine
  , delta
  , inpCtor
  , matchInCtor
  , omega
  , pack
  )
import Keiki.Core qualified as K
import Keiki.Generics (emptyRegFile)
import Keiki.Generics.TH (deriveAggregateCtors, deriveWireCtors)
import Keiki.Internal.Slots (Concat, Disjoint, HasIndexN (..))


-- * Coffee-dispenser toy ---------------------------------------------------

-- | Money the dispenser tracks. Two slots: the price quoted at
-- insertion time (\"price\") and a sentinel timestamp for when the
-- brew started (\"brewStartedAt\").
type CoffeeRegs =
  '[ '("price",          Int)
   , '("brewStartedAt",  UTCTime)
   ]


emptyCoffeeRegs :: RegFile CoffeeRegs
emptyCoffeeRegs = emptyRegFile


data CoffeeVertex = Idle | Brewing
  deriving (Eq, Show, Enum, Bounded)


-- Two commands: insert money (with an amount and a timestamp); a
-- silent Continue tick that completes the brew.
data InsertData = InsertData
  { amount :: Int
  , at     :: UTCTime
  } deriving (Eq, Show, Generic)

data CoffeeCmd = Insert InsertData | Continue
  deriving (Eq, Show, Generic)


-- One event: the dispenser brewed a coffee at amount C cents.
data BrewedData = BrewedData { paid :: Int }
  deriving (Eq, Show, Generic)

data CoffeeEvent = Brewed BrewedData
  deriving (Eq, Show, Generic)


-- TH: per-input-ctor projections + guards.
$(deriveAggregateCtors ''CoffeeCmd ''CoffeeRegs
    [ ("Insert",   "Insert")
    , ("Continue", "Continue")
    ])


-- TH: per-event-ctor wire ctors.
$(deriveWireCtors ''CoffeeEvent
    [ ("Brewed", "Brewed")
    ])


-- * Spike-local builder machinery -----------------------------------------

-- The full 'Keiki.Builder' surface inlined here. The plan-of-record is
-- to move this verbatim into 'src/Keiki/Builder.hs' at M3.

-- | The growing edge state: guard, update (whose written-slot index
-- @w@ moves through the type system as the user adds @(.=)@s), output,
-- and the list of 'goto' calls observed (finalized to exactly one).
data PartialEdge rs ci co v (w :: [Symbol]) = PartialEdge
  { peGuard   :: HsPred rs ci
  , peUpdate  :: Update rs w ci
  , peOutput  :: Maybe (OutTerm rs ci co)
  , peTargets :: [v]
  }


-- | The per-edge indexed-state monad. @w@ is the set of slots written
-- so far; @w'@ is the set after this step.
newtype EdgeBuilder rs ci co v (w :: [Symbol]) (w' :: [Symbol]) a = EdgeBuilder
  { runEdgeBuilder :: PartialEdge rs ci co v w
                   -> (a, PartialEdge rs ci co v w') }


-- | QualifiedDo entry points. @B.do { ... }@ desugars to chained
-- '(>>=)' / '(>>)' calls; we expose the indexed analogues so the
-- type-level slot-set threads through automatically.
(>>=)
  :: EdgeBuilder rs ci co v w1 w2 a
  -> (a -> EdgeBuilder rs ci co v w2 w3 b)
  -> EdgeBuilder rs ci co v w1 w3 b
EdgeBuilder f >>= k = EdgeBuilder $ \pe ->
  let (a, pe1)        = f pe
      EdgeBuilder g   = k a
  in g pe1


(>>)
  :: EdgeBuilder rs ci co v w1 w2 a
  -> EdgeBuilder rs ci co v w2 w3 b
  -> EdgeBuilder rs ci co v w1 w3 b
m >> n = m Keiki.BuilderSpike.>>= \_ -> n


pure :: a -> EdgeBuilder rs ci co v w w a
pure a = EdgeBuilder $ \pe -> (a, pe)


return :: a -> EdgeBuilder rs ci co v w w a
return = Keiki.BuilderSpike.pure


-- | Slot assignment. The slot name is supplied via a TypeApplication
-- on 'at'; the value is assigned with @.=@. The @Disjoint '[name] w@
-- constraint inherits the type-level distinct-targets check from
-- 'combine'; a duplicated @(.=)@ to the same slot fails to type-check
-- at the offending line with the existing
-- 'Keiki.Internal.Slots.NotMemberCmp' TypeError.
--
-- == Why @at \@\"name\"@ instead of @\#name@
--
-- The @\#name@ overloaded-label syntax tries to resolve the constraint
-- @IsLabel \"name\" (IndexN s rs r)@ against the instance head
-- @IsLabel s (IndexN s rs r)@ — but GHC will not commit to @s ~
-- \"name\"@ when @name@ is a quantified type variable in the
-- enclosing operator's signature (the pattern-side @s@ is shared
-- across both instance arguments, and GHC defers commitment).
-- @at \@\"name\"@ pins the symbol explicitly via TypeApplication, so
-- the inference proceeds without ambiguity.
slot
  :: forall (name :: Symbol) rs r.
     ( KnownSymbol name, HasIndexN name rs r )
  => IndexN name rs r
slot = indexN @name @rs @r


(.=)
  :: forall name r rs ci co v w.
     ( KnownSymbol name, Disjoint '[name] w )
  => IndexN name rs r
  -> Term rs ci r
  -> EdgeBuilder rs ci co v w (Concat '[name] w) ()
ix .= t = EdgeBuilder $ \(PartialEdge g u o tgs) ->
  ((), PartialEdge g (USet ix t `combine` u) o tgs)
infixr 6 .=


-- | Set the edge's target vertex. Required exactly once; finalize-time
-- check raises a runtime error naming the source vertex and edge index
-- if missing or duplicated.
goto :: v -> EdgeBuilder rs ci co v w w ()
goto v = EdgeBuilder $ \(PartialEdge g u o tgs) ->
  ((), PartialEdge g u o (v : tgs))


-- | Emit an event. Takes the wire-side ctor and an explicit
-- 'OutFields' HList. The InCtor is recovered from the lexically-
-- enclosing 'onCmd' (via the threaded edge state's guard).
emit
  :: forall co fs rs ci v w ifs.
     InCtor ci ifs
  -> WireCtor co fs
  -> OutFields rs ci fs
  -> EdgeBuilder rs ci co v w w ()
emit ic wc fs = EdgeBuilder $ \(PartialEdge g u _o tgs) ->
  ((), PartialEdge g u (Just (pack ic wc fs)) tgs)


-- | ε-output (an edge that consumes input but emits no event).
-- Idempotent: leaves 'peOutput' as 'Nothing'. Provided for
-- documentation-by-syntax; an edge with neither 'emit' nor 'noEmit'
-- is also an ε-edge.
noEmit :: EdgeBuilder rs ci co v w w ()
noEmit = EdgeBuilder $ \pe -> ((), pe)


-- | Add a guard conjunct.
requireGuard :: HsPred rs ci -> EdgeBuilder rs ci co v w w ()
requireGuard p = EdgeBuilder $ \(PartialEdge g u o tgs) ->
  ((), PartialEdge (PAnd g p) u o tgs)


-- | Add an equality conjunct to the guard.
requireEq
  :: (Eq r, Typeable r)
  => Term rs ci r -> Term rs ci r -> EdgeBuilder rs ci co v w w ()
requireEq a b = requireGuard (PEq a b)


-- | An opaque wrapper around an InCtor, used to project the input
-- symbol's fields via OverloadedRecordDot inside an 'onCmd' body.
-- The HasField instance below makes @d.fieldName@ resolve to a
-- 'TInpCtorField'-built term. PayloadProj has no record fields of
-- its own so the user's @d.fieldName@ never collides with a built-in
-- selector.
data PayloadProj rs ci ifs = PayloadProj (InCtor ci ifs)


instance ( HasIndexN name ifs r )
      => HasField name (PayloadProj rs ci ifs) (Term rs ci r) where
  getField (PayloadProj ic) = inpCtor ic (indexNToIndex (indexN @name @ifs @r))


-- The InCtor's TInpCtorField wants a 'Index' (unindexed), not an
-- 'IndexN'. The two have the same runtime structure; we translate.
-- (M3 may want to promote 'inpCtor' to take 'IndexN' instead, but
-- that's outside this spike.)
indexNToIndex :: forall name rs r. IndexN name rs r -> K.Index rs r
indexNToIndex IZ      = K.ZIdx
indexNToIndex (IS i)  = K.SIdx (indexNToIndex i)


-- | Per-edge entry: wire the InCtor's match-guard, give the user a
-- record-projection handle for OverloadedRecordDot, and finalize the
-- accumulated edge into a closed 'Edge' value.
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
        }
      (_, finalPE) = runEdgeBuilder (body (PayloadProj ic)) initial
      edgeIx       = length edges
  in ((), finalizeEdge edgeIx src finalPE : edges)


-- | ε-edge entry: no input projection, no InCtor match-guard. The
-- guard starts at 'PTop' so any non-input-conditioned conjuncts the
-- body adds (via 'requireEq', 'requireGuard') are the full guard.
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
        }
      (_, finalPE) = runEdgeBuilder body initial
      edgeIx       = length edges
  in ((), finalizeEdge edgeIx src finalPE : edges)


-- | Close out a 'PartialEdge' into an 'Edge'. The existential @w@ on
-- 'Edge''s @update@ field closes here.
finalizeEdge
  :: Show v
  => Int
  -> v
  -> PartialEdge rs ci co v w
  -> Edge (HsPred rs ci) rs ci co v
finalizeEdge n src (PartialEdge g u o tgs) = case tgs of
  [t]      -> Edge { guard = g, update = u, output = o, target = t }
  []       -> error $ "Keiki.Builder: edge #" <> show n <> " from "
                   <> show src <> ": goto missing. Each onCmd/"
                   <> "onEpsilon body must end with exactly one goto V."
  (_:_:_)  -> error $ "Keiki.Builder: edge #" <> show n <> " from "
                   <> show src <> ": goto called more than once. "
                   <> "Each onCmd/onEpsilon body must end with "
                   <> "exactly one goto V."


-- | The plain-Monad carrier for a list of edges out of one source
-- vertex. @'EdgeListBuilder' rs ci co v a@ accumulates edges
-- (head-prepended) under a fixed source vertex.
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
    let (f, es1)  = kf src es
        (a, es2) = ka src es1
    in (f a, es2)

instance Monad (EdgeListBuilder rs ci co v) where
  (>>=) (EdgeListBuilder k) f = EdgeListBuilder $ \src es ->
    let (a, es') = k src es
        EdgeListBuilder k' = f a
    in k' src es'


-- | The plain-Monad carrier for the top-level transducer build.
newtype VertexBuilder rs ci co v a = VertexBuilder
  { runVertexBuilder :: [(v, [Edge (HsPred rs ci) rs ci co v])]
                     -> (a, [(v, [Edge (HsPred rs ci) rs ci co v])]) }


instance Functor (VertexBuilder rs ci co v) where
  fmap f (VertexBuilder k) = VertexBuilder $ \vs ->
    let (a, vs') = k vs in (f a, vs')

instance Applicative (VertexBuilder rs ci co v) where
  pure a = VertexBuilder $ \vs -> (a, vs)
  VertexBuilder kf <*> VertexBuilder ka = VertexBuilder $ \vs ->
    let (f, vs1)  = kf vs
        (a, vs2) = ka vs1
    in (f a, vs2)

instance Monad (VertexBuilder rs ci co v) where
  (>>=) (VertexBuilder k) f = VertexBuilder $ \vs ->
    let (a, vs') = k vs
        VertexBuilder k' = f a
    in k' vs'


-- | Group edges by source vertex.
from
  :: Show v
  => v
  -> EdgeListBuilder rs ci co v ()
  -> VertexBuilder rs ci co v ()
from v eb = VertexBuilder $ \vs ->
  let (_, edges) = runEdgeListBuilder eb v []
  in ((), (v, reverse edges) : vs)


-- | Top-level: produce a SymTransducer from an initial vertex,
-- initial register file, finality predicate, and a do-block of
-- @from V $ do …@ clauses.
buildTransducer
  :: forall rs ci co v.
     (Bounded v, Enum v, Eq v, Show v)
  => v
  -> RegFile rs
  -> (v -> Bool)
  -> VertexBuilder rs ci co v ()
  -> SymTransducer (HsPred rs ci) rs v ci co
buildTransducer initS initR isF vb = SymTransducer
  { edgesOut    = \v -> fromMaybe [] (lookup v vmap)
  , initial     = initS
  , initialRegs = initR
  , isFinal     = isF
  }
  where
    (_, vmap) = runVertexBuilder vb []


-- * The toy transducer, twice -----------------------------------------------

-- AST form. Two edges:
--   Idle    --[Insert]--> Brewing  emits Brewed { paid = inp.amount }
--                                  writes price=inp.amount, brewStartedAt=inp.at
--   Brewing --[Continue]-> Idle    epsilon (no event), no register changes
coffeeAST
  :: SymTransducer (HsPred CoffeeRegs CoffeeCmd)
                   CoffeeRegs CoffeeVertex CoffeeCmd CoffeeEvent
coffeeAST = SymTransducer
  { edgesOut    = coffeeASTEdges
  , initial     = Idle
  , initialRegs = emptyCoffeeRegs
  , isFinal     = const False
  }


coffeeASTEdges
  :: CoffeeVertex
  -> [Edge (HsPred CoffeeRegs CoffeeCmd) CoffeeRegs CoffeeCmd CoffeeEvent
           CoffeeVertex]
coffeeASTEdges = \case
  Idle ->
    [ Edge
        { guard  = isInsert
        , update =
            USet (#price :: IndexN "price" CoffeeRegs Int)
                 (inpInsert #amount)
              `combine`
            USet (#brewStartedAt :: IndexN "brewStartedAt" CoffeeRegs UTCTime)
                 (inpInsert #at)
        , output = Just $ pack
            inCtorInsert
            wireBrewed
            (OFCons (inpInsert #amount) OFNil)
        , target = Brewing
        }
    ]
  Brewing ->
    [ Edge
        { guard  = isContinue
        , update = UKeep
        , output = Nothing
        , target = Idle
        }
    ]


-- Builder form. Reads as sequential commands.
--
-- The outer @do@ is plain (VertexBuilder is a regular Monad); the
-- per-vertex @do@ is also plain (EdgeListBuilder is a regular Monad);
-- only the per-edge body uses 'Keiki.BuilderSpike.do' (M3 will
-- alias this to @B.do@) because it is the indexed-state layer that
-- threads the type-level slot-set.
coffeeBuilt
  :: SymTransducer (HsPred CoffeeRegs CoffeeCmd)
                   CoffeeRegs CoffeeVertex CoffeeCmd CoffeeEvent
coffeeBuilt = buildTransducer Idle emptyCoffeeRegs (const False) Prelude.do

    from Idle Prelude.do
      onCmd inCtorInsert $ \d -> Keiki.BuilderSpike.do
        slot @"price"         .= d.amount
        slot @"brewStartedAt" .= d.at
        emit inCtorInsert wireBrewed (OFCons d.amount OFNil)
        goto Brewing

    from Brewing Prelude.do
      onCmd inCtorContinue $ \_d -> Keiki.BuilderSpike.do
        goto Idle


-- * Misuse demonstrations --------------------------------------------------

-- A transducer with a missing-goto edge. Top-level binding evaluation
-- raises the finalize-time error; we wrap in an IO action and use
-- 'evaluate' to force the error in-spec.
coffeeMissingGoto
  :: SymTransducer (HsPred CoffeeRegs CoffeeCmd)
                   CoffeeRegs CoffeeVertex CoffeeCmd CoffeeEvent
coffeeMissingGoto = buildTransducer Idle emptyCoffeeRegs (const False) Prelude.do

    from Idle Prelude.do
      onCmd inCtorInsert $ \_d -> Keiki.BuilderSpike.do
        -- intentional: no goto
        noEmit


-- A transducer with two gotos in one body.
coffeeDoubleGoto
  :: SymTransducer (HsPred CoffeeRegs CoffeeCmd)
                   CoffeeRegs CoffeeVertex CoffeeCmd CoffeeEvent
coffeeDoubleGoto = buildTransducer Idle emptyCoffeeRegs (const False) Prelude.do

    from Idle Prelude.do
      onCmd inCtorInsert $ \_d -> Keiki.BuilderSpike.do
        goto Brewing
        goto Idle


-- * In-spec assertions -----------------------------------------------------

t0 :: UTCTime
t0 = UTCTime (fromGregorian 2026 5 2) (secondsToDiffTime 0)

t100 :: UTCTime
t100 = UTCTime (fromGregorian 2026 5 2) (secondsToDiffTime 100)

t200 :: UTCTime
t200 = UTCTime (fromGregorian 2026 5 2) (secondsToDiffTime 200)


spec :: Spec
spec = do

  describe "EP-15 M2 spike: builder vs AST agreement" $ do

    it "delta and omega agree on Idle + Insert" $ do
      let cmd = Insert (InsertData 250 t0)
      fmap fst (delta coffeeAST    Idle emptyCoffeeRegs cmd)
        `shouldBe` fmap fst (delta coffeeBuilt Idle emptyCoffeeRegs cmd)
      omega coffeeAST    Idle emptyCoffeeRegs cmd
        `shouldBe` omega coffeeBuilt Idle emptyCoffeeRegs cmd

    it "delta and omega agree on Brewing + Continue" $ do
      -- Use the registers post-Insert as the Brewing-state registers.
      let insertCmd = Insert (InsertData 250 t0)
      Just (_, regs) <- Prelude.pure (delta coffeeAST Idle emptyCoffeeRegs insertCmd)
      fmap fst (delta coffeeAST    Brewing regs Continue)
        `shouldBe` fmap fst (delta coffeeBuilt Brewing regs Continue)
      omega coffeeAST    Brewing regs Continue
        `shouldBe` omega coffeeBuilt Brewing regs Continue

    it "delta is Nothing on Idle + Continue (guard mismatch)" $ do
      fmap fst (delta coffeeAST    Idle emptyCoffeeRegs Continue) `shouldBe` Nothing
      fmap fst (delta coffeeBuilt Idle emptyCoffeeRegs Continue) `shouldBe` Nothing

    it "omega round-trips event through the ASTand builder forms" $ do
      let cmd = Insert (InsertData 300 t100)
      omega coffeeAST    Idle emptyCoffeeRegs cmd
        `shouldBe` Just (Brewed (BrewedData 300))
      omega coffeeBuilt Idle emptyCoffeeRegs cmd
        `shouldBe` Just (Brewed (BrewedData 300))

  describe "EP-15 M2 spike: misuse error messages" $ do

    it "missing goto fires at finalize time with the expected message" $
      -- `head` forces the first element of the edges list, which is
      -- the result of `finalizeEdge`. `length` would only walk the
      -- spine and not trigger the error.
      evaluate (head (edgesOut coffeeMissingGoto Idle))
        `shouldThrow`
          errorCall ("Keiki.Builder: edge #0 from Idle: goto missing. "
                    <> "Each onCmd/onEpsilon body must end with "
                    <> "exactly one goto V.")

    it "duplicated goto fires at finalize time with the expected message" $
      evaluate (head (edgesOut coffeeDoubleGoto Idle))
        `shouldThrow`
          errorCall ("Keiki.Builder: edge #0 from Idle: goto called "
                    <> "more than once. Each onCmd/onEpsilon body must "
                    <> "end with exactly one goto V.")

  describe "EP-15 M2 spike: timestamp also threads correctly" $
    it "second slot 'brewStartedAt' is written" $ do
      let cmd = Insert (InsertData 200 t200)
      Just (_, regs1) <- Prelude.pure (delta coffeeAST    Idle emptyCoffeeRegs cmd)
      Just (_, regs2) <- Prelude.pure (delta coffeeBuilt Idle emptyCoffeeRegs cmd)
      (regs1 K.! (#brewStartedAt :: K.Index CoffeeRegs UTCTime))
        `shouldBe` (regs2 K.! (#brewStartedAt :: K.Index CoffeeRegs UTCTime))
