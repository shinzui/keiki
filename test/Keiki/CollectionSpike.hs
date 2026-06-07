-- | EP-60 M1 ratification-gate spike — first-class collection registers.
--
-- This module is a __prototype__, not the final implementation. Per the EP-60
-- ratification gate it deliberately touches __no__ file under @src/Keiki/@: it
-- models the proposed collection vocabulary (FR1–FR6 of
-- @docs/research/collection-registers-design.md@) as a /local mini-AST/ and proves,
-- by construction plus runnable @hspec@ assertions, that the design satisfies its
-- invariants (INV1–INV6) before any core edit is made.
--
-- What it demonstrates:
--
--   * __FR1\/FR2\/FR4 (zero-@TApp@ authoring).__ A @BlockerBoard@ aggregate
--     (@Map BlockerId BlockerState@) is authored entirely with structural
--     constructors — @CInsert@\/@CDelete@\/@CAdjust@ carrying /terms/, never
--     closures. A structural walker confirms the whole program contains zero
--     opaque escape hatches.
--   * __INV1 (derived replay).__ A forward fold of the structural updates
--     reconstitutes the same @Map@ a reference @Data.Map@ fold produces, over a
--     finite enumeration of command sequences — no hand-written @apply@.
--   * __INV2 (@solveOutput@ invertibility).__ A model of @stepOne@'s
--     recoverability classification shows @TLookupField@ joins @TReg@ on the
--     /structural/ side (register-recoverable), distinct from the opaque @TApp@
--     side — so an edge emitting a @TLookupField@-derived field stays invertible.
--   * __INV3 (@checkHiddenInputs@ understands collection updates).__ A model of
--     the @updateReadsInput@ + union-coverage walk flags a silent ε-edge insert
--     while passing an insert whose element data is on the wire.
--   * __INV4 (static output arity).__ Each edge's output length is constant,
--     independent of board size.
--   * __INV6 (NoThunks).__ A long replay over a strict map yields a fully forced
--     board (no thunk tower), by construction.
--   * __FR6 (symbolic translation).__ Option B is modeled as a /named, queryable/
--     @SymStatus@: a collection guard yields @SkippedCollectionGuard "PMember"@
--     (honest and inspectable), a scalar guard yields @Verified@ — never a silent
--     free Boolean that the single-valuedness gate would trust blindly.
--
-- The accompanying written analysis (FR6 A-vs-B decision, Seihou reconciliation,
-- INV1–INV6 satisfiability argument) lives in the EP-60 plan,
-- @docs\/plans\/60-first-class-collection-registers-design-gated.md@.
module Keiki.CollectionSpike (spec) where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
-- Real keiki, used only to demonstrate the scalar path is untouched (INV5).
import Keiki.Core (RegFile (..), Term (TLit), evalTerm)
import Test.Hspec

-- ---------------------------------------------------------------------------
-- The BlockerBoard domain (the §6 worked example, in miniature)
-- ---------------------------------------------------------------------------

type BlockerId = Int

data Status = Open | Resolved | Escalated
  deriving (Eq, Show)

-- | An element record. FR1 wants the element type expressible as a sub-record
-- so its fields are projectable by FR4's 'TLookupField'; here that is an
-- ordinary record with two fields.
data BlockerState = BlockerState
  { bsStatus :: !Status,
    bsSeverity :: !Int
  }
  deriving (Eq, Show)

type Board = Map BlockerId BlockerState

-- | The command sum (@ci@ in keiki terms). Positional rather than record-style
-- so @severity@ is not a partial field (it exists only on 'AddBlocker').
data Cmd
  = AddBlocker BlockerId Int
  | ResolveBlocker BlockerId
  | EscalateBlocker BlockerId
  deriving (Eq, Show)

-- | The blocker id every command carries (total).
cId :: Cmd -> BlockerId
cId (AddBlocker i _) = i
cId (ResolveBlocker i) = i
cId (EscalateBlocker i) = i

-- | The severity field, present only on 'AddBlocker'. Read only by the
-- @AddBlocker@ edge's term, which fires only on an @AddBlocker@ command —
-- mirroring how keiki's 'Keiki.Core.TInpCtorField' read is guarded by the
-- edge's 'InCtor' match.
cSeverity :: Cmd -> Int
cSeverity (AddBlocker _ s) = s
cSeverity c = error ("cSeverity: not an AddBlocker: " ++ show c)

-- ---------------------------------------------------------------------------
-- FR1/FR2/FR4: a local model of the structural term + update vocabulary
-- ---------------------------------------------------------------------------

-- | A miniature of keiki's 'Keiki.Core.Term', restricted to the four
-- recoverability classes that matter to @solveOutput@\/@stepOne@. Concrete at
-- @ci ~ Cmd@ for the spike.
--
-- The first three constructors are /structural/ — an analysis can read them. The
-- last, 'KClosure', is the opaque @TApp@ escape hatch the collection feature
-- exists to /avoid/ for element operations; it appears here only as the negative
-- contrast in the zero-@TApp@ and recoverability tests.
data KTerm a where
  -- | @TLit@: a constant. Structural, carries no command information.
  KLit :: a -> KTerm a
  -- | @TInpCtorField@: read a named field of the command. Structural and
  --     /on the wire/ (recoverable from the emitted event when it carries it).
  KInpField :: String -> (Cmd -> a) -> KTerm a
  -- | @TLookupField@ (FR4): read field @field@ of the collection element at
  --     @key@. The @(BlockerState -> a)@ stands for the structural element-field
  --     @Index velems f@ (a record selector, not an opaque command transform).
  --     Structural and recoverable from the /replayed register file/ — it joins
  --     @TReg@, not @TApp@.
  KLookup :: String -> KTerm BlockerId -> String -> (BlockerState -> a) -> KTerm a
  -- | @TApp1@\/@TApp2@: opaque closure over the command. Analysis-blind.
  KClosure :: String -> (Cmd -> a) -> KTerm a

-- | Evaluate a 'KTerm' forward against the current board and command — the
-- spike's analogue of 'Keiki.Core.evalTerm'.
evalK :: Board -> Cmd -> KTerm a -> a
evalK _ _ (KLit a) = a
evalK _ ci (KInpField _ f) = f ci
evalK b ci (KLookup _ keyT _ proj) = proj (b Map.! evalK b ci keyT)
evalK _ ci (KClosure _ f) = f ci

-- | FR2 structural update combinators, carrying /terms/ not closures. The
-- element value of 'CInsert' is itself a structural record-builder ('ElemBuild')
-- so the whole insert is closure-free.
data CUpdate
  = CInsert (KTerm BlockerId) ElemBuild
  | CDelete (KTerm BlockerId)
  | CAdjust (KTerm BlockerId) ElemUpd

-- | A structural builder for a 'BlockerState' element from per-field terms
-- (FR1's "element as sub-record"): no opaque function assembles the record.
data ElemBuild = BuildBlocker (KTerm Status) (KTerm Int)

-- | A structural update of one element field (the @sub \@"status" .= t@ form).
newtype ElemUpd = SetStatus (KTerm Status)

evalElem :: Board -> Cmd -> ElemBuild -> BlockerState
evalElem b ci (BuildBlocker st sv) = BlockerState (evalK b ci st) (evalK b ci sv)

-- | Run a structural collection update /forward/ — the spike's analogue of
-- 'Keiki.Core.runUpdate'. This is what makes replay derived (INV1): no
-- hand-written @apply@, just forward re-evaluation of a structural update.
runCUpdate :: Board -> Cmd -> CUpdate -> Board
runCUpdate b ci (CInsert keyT elemB) =
  Map.insert (evalK b ci keyT) (evalElem b ci elemB) b
runCUpdate b ci (CDelete keyT) =
  Map.delete (evalK b ci keyT) b
runCUpdate b ci (CAdjust keyT (SetStatus st)) =
  Map.adjust (\e -> e {bsStatus = evalK b ci st}) (evalK b ci keyT) b

-- ---------------------------------------------------------------------------
-- FR3: structural content guards
-- ---------------------------------------------------------------------------

-- | FR3 collection-content predicates, plus a 'PScalar' stand-in for any
-- ordinary scalar guard (@PEq@\/@PCmp@) that the symbolic layer already handles.
data CPred
  = PMemberC (KTerm BlockerId)
  | PNotMemberC (KTerm BlockerId)
  | PAllC ElemPred
  | PScalar Bool

-- | A bounded element predicate (the body of a @PAll@\/@PAny@).
data ElemPred = StatusIs Status | StatusNot Status

matchElem :: ElemPred -> BlockerState -> Bool
matchElem (StatusIs s) e = bsStatus e == s
matchElem (StatusNot s) e = bsStatus e /= s

evalCPred :: Board -> Cmd -> CPred -> Bool
evalCPred b ci (PMemberC keyT) = Map.member (evalK b ci keyT) b
evalCPred b ci (PNotMemberC keyT) = not (Map.member (evalK b ci keyT) b)
evalCPred b _ (PAllC ep) = all (matchElem ep) (Map.elems b)
evalCPred _ _ (PScalar v) = v

-- ---------------------------------------------------------------------------
-- The BlockerBoard program — authored with ZERO closures
-- ---------------------------------------------------------------------------

-- | One guarded edge: a guard and a structural collection update.
data Edge = Edge {eGuard :: CPred, eUpdate :: CUpdate}

keyOf :: KTerm BlockerId
keyOf = KInpField "id" cId

-- | The BlockerBoard transducer, as a command-dispatched guarded program.
-- Every guard and update is built from structural constructors only — there is
-- not a single 'KClosure' in this definition, which the zero-@TApp@ test checks
-- mechanically.
--
--   * @AddBlocker@: requires the id is /not/ already present, inserts a fresh
--     @Open@ blocker carrying the command's severity.
--   * @ResolveBlocker@ \/ @EscalateBlocker@: require the id /is/ present, adjust
--     that one element's status.
program :: Cmd -> Edge
program (AddBlocker _ _) =
  Edge
    { eGuard = PNotMemberC keyOf,
      eUpdate = CInsert keyOf (BuildBlocker (KLit Open) (KInpField "severity" cSeverity))
    }
program (ResolveBlocker _) =
  Edge {eGuard = PMemberC keyOf, eUpdate = CAdjust keyOf (SetStatus (KLit Resolved))}
program (EscalateBlocker _) =
  Edge {eGuard = PMemberC keyOf, eUpdate = CAdjust keyOf (SetStatus (KLit Escalated))}

-- | "Cannot close the board while any blocker is unresolved" — the lifecycle
-- guard, a @PAll@ over the elements.
closeBoardGuard :: CPred
closeBoardGuard = PAllC (StatusNot Open)

-- | Apply one command through its guarded edge, if the guard holds; otherwise
-- leave the board unchanged (the spike's analogue of @step@ rejecting a
-- command). This is the derived replay step — no hand-written @apply@ (INV1).
stepBoard :: Board -> Cmd -> Board
stepBoard b ci =
  let Edge g u = program ci
   in if evalCPred b ci g then runCUpdate b ci u else b

reconstitute :: [Cmd] -> Board
reconstitute = foldl' stepBoard Map.empty

-- ---------------------------------------------------------------------------
-- Zero-TApp structural walkers
-- ---------------------------------------------------------------------------

termHasClosure :: KTerm a -> Bool
termHasClosure (KLit _) = False
termHasClosure (KInpField _ _) = False
termHasClosure (KLookup _ keyT _ _) = termHasClosure keyT
termHasClosure (KClosure _ _) = True

elemBuildHasClosure :: ElemBuild -> Bool
elemBuildHasClosure (BuildBlocker st sv) = termHasClosure st || termHasClosure sv

updateHasClosure :: CUpdate -> Bool
updateHasClosure (CInsert keyT e) = termHasClosure keyT || elemBuildHasClosure e
updateHasClosure (CDelete keyT) = termHasClosure keyT
updateHasClosure (CAdjust keyT (SetStatus st)) = termHasClosure keyT || termHasClosure st

predHasClosure :: CPred -> Bool
predHasClosure (PMemberC keyT) = termHasClosure keyT
predHasClosure (PNotMemberC keyT) = termHasClosure keyT
predHasClosure (PAllC _) = False
predHasClosure (PScalar _) = False

edgeHasClosure :: Edge -> Bool
edgeHasClosure (Edge g u) = predHasClosure g || updateHasClosure u

-- ---------------------------------------------------------------------------
-- INV2: a model of stepOne's recoverability classification
-- ---------------------------------------------------------------------------

-- | How @solveOutput@\/@stepOne@ treats an output field. Mirrors the verified
-- arms of @stepOne@ in @src\/Keiki\/Core.hs@ (lines ~1349–1359), where every arm
-- returns @Just …@ (never @Nothing@) but the /kind/ of recovery differs:
--
--   * 'FromWire' — @TInpCtorField@: contributes a recovered command slot.
--   * 'FromRegisters' — @TLit@\/@TReg@\/@TLookupField@: @Just []@, deterministically
--     reproducible from the replayed register file. __TLookupField joins here__
--     (INV2): the analysis can see exactly what it reads.
--   * 'OpaqueRecompute' — @TApp1@\/@TApp2@: @Just []@ too, but recompute-and-verify
--     (EP-47) — the closure is analysis-blind. A collection op must never land
--     here.
data Recoverability = FromWire | FromRegisters | OpaqueRecompute
  deriving (Eq, Show)

classify :: KTerm a -> Recoverability
classify (KLit _) = FromRegisters
classify (KInpField _ _) = FromWire
classify (KLookup {}) = FromRegisters
classify (KClosure _ _) = OpaqueRecompute

-- | The @stepOne@ result shape: the recovered command slots (here just slot
-- names). Crucially never @Nothing@ for these arms — a structural lookup does
-- not break the gather the way an opaque term returning @Nothing@ would.
stepOneSlots :: KTerm a -> Maybe [String]
stepOneSlots (KLit _) = Just []
stepOneSlots (KInpField name _) = Just [name]
stepOneSlots (KLookup {}) = Just []
stepOneSlots (KClosure _ _) = Just []

-- ---------------------------------------------------------------------------
-- INV3: a model of checkHiddenInputs over collection updates
-- ---------------------------------------------------------------------------

-- | Does this term read the command (@TInpCtorField@ anywhere)? Mirrors
-- @termReadsInput@ in @src\/Keiki\/Core.hs@.
termReadsInputK :: KTerm a -> Bool
termReadsInputK (KLit _) = False
termReadsInputK (KInpField _ _) = True
termReadsInputK (KLookup _ keyT _ _) = termReadsInputK keyT
termReadsInputK (KClosure _ _) = False

elemBuildReadsInput :: ElemBuild -> Bool
elemBuildReadsInput (BuildBlocker st sv) = termReadsInputK st || termReadsInputK sv

-- | The collection-update extension INV3 asks for: @updateReadsInput@ taught to
-- recurse into the new constructors. A @CInsert@\/@CAdjust@ whose key or element
-- data comes from the command reads the input.
collUpdateReadsInput :: CUpdate -> Bool
collUpdateReadsInput (CInsert keyT e) = termReadsInputK keyT || elemBuildReadsInput e
collUpdateReadsInput (CDelete keyT) = termReadsInputK keyT
collUpdateReadsInput (CAdjust keyT (SetStatus st)) = termReadsInputK keyT || termReadsInputK st

-- | The command-field names a collection update consumes (for coverage).
updateReadSlots :: CUpdate -> [String]
updateReadSlots (CInsert keyT e) = termSlots keyT ++ elemSlots e
updateReadSlots (CDelete keyT) = termSlots keyT
updateReadSlots (CAdjust keyT (SetStatus st)) = termSlots keyT ++ termSlots st

termSlots :: KTerm a -> [String]
termSlots (KLit _) = []
termSlots (KInpField name _) = [name]
termSlots (KLookup _ keyT _ _) = termSlots keyT
termSlots (KClosure _ _) = []

elemSlots :: ElemBuild -> [String]
elemSlots (BuildBlocker st sv) = termSlots st ++ termSlots sv

-- | A miniature of @checkHiddenInputs@ for a single edge. @wireSlots@ is the
-- union of command-field names recovered across the edge's emitted events. The
-- edge is flagged (result 'True') when its update reads the input but that input
-- is not fully covered on the wire — exactly the union-coverage rule, including
-- the ε-edge (empty @wireSlots@) case where any input-reading update is flagged.
checkHiddenEdge :: [String] -> CUpdate -> Bool
checkHiddenEdge wireSlots u =
  collUpdateReadsInput u && not (all (`elem` wireSlots) (updateReadSlots u))

-- ---------------------------------------------------------------------------
-- FR6: Option B — a named, queryable symbolic status
-- ---------------------------------------------------------------------------

-- | The Option B contract: instead of a guard silently becoming an opaque
-- @SBV.free@ Boolean (today's behavior, which a caller /cannot distinguish/ from a
-- real verification), a collection guard yields a named, inspectable status. The
-- scalar part of every aggregate keeps full verification.
--
-- (Option A would instead translate @PMember@\/@PSizeCmp@ to z3 array\/finite-set
-- theory and @PAll@\/@PAny@ to quantifiers — higher value, but the quantifiers
-- risk making the single-valuedness check undecidable\/slow. The Seihou cases need
-- only membership\/emptiness, so Option B is sufficient for the committed
-- consumer; a later EP can upgrade specific forms to Option A.)
data SymStatus = Verified | SkippedCollectionGuard String
  deriving (Eq, Show)

translateOptionB :: CPred -> SymStatus
translateOptionB (PScalar _) = Verified
translateOptionB (PMemberC _) = SkippedCollectionGuard "PMember"
translateOptionB (PNotMemberC _) = SkippedCollectionGuard "PNotMember"
translateOptionB (PAllC _) = SkippedCollectionGuard "PAll"

-- ---------------------------------------------------------------------------
-- INV4: static output arity — output length is a function of the command only
-- ---------------------------------------------------------------------------

-- | The (fixed) number of events each edge emits. Independent of the board, so
-- output arity is static (INV4). A collection mutation is a register update,
-- never a source of per-element output multiplicity.
outputArity :: Cmd -> Int
outputArity (AddBlocker _ _) = 1
outputArity (ResolveBlocker _) = 1
outputArity (EscalateBlocker _) = 1

-- ---------------------------------------------------------------------------
-- The spec
-- ---------------------------------------------------------------------------

-- A finite enumeration of command sequences (the suite is hspec-only; no
-- QuickCheck — see the EP-60 Surprises).
seqs :: [[Cmd]]
seqs =
  [ [],
    [AddBlocker 1 5],
    [AddBlocker 1 5, AddBlocker 2 3],
    [AddBlocker 1 5, ResolveBlocker 1],
    [AddBlocker 1 5, AddBlocker 1 9], -- second Add rejected (already member)
    [ResolveBlocker 7], -- rejected (not a member)
    [AddBlocker 1 5, AddBlocker 2 3, EscalateBlocker 2, ResolveBlocker 1],
    [AddBlocker 1 1, AddBlocker 2 2, AddBlocker 3 3, ResolveBlocker 2, EscalateBlocker 3]
  ]

-- | A reference semantics computed independently of the structural-update
-- machinery, to check INV1's derived replay against (a hand-written oracle used
-- ONLY in the test, never in the library path).
reference :: [Cmd] -> Board
reference = foldl' apply Map.empty
  where
    apply b (AddBlocker i sev)
      | Map.member i b = b
      | otherwise = Map.insert i (BlockerState Open sev) b
    apply b (ResolveBlocker i)
      | Map.member i b = Map.adjust (\e -> e {bsStatus = Resolved}) i b
      | otherwise = b
    apply b (EscalateBlocker i)
      | Map.member i b = Map.adjust (\e -> e {bsStatus = Escalated}) i b
      | otherwise = b

-- | The three edge shapes, one per command constructor.
allCmds :: [Cmd]
allCmds = [AddBlocker 1 5, ResolveBlocker 1, EscalateBlocker 1]

spec :: Spec
spec = do
  describe "FR1/FR2/FR4 — zero-TApp authoring (the headline acceptance)" $ do
    it "the entire BlockerBoard program contains no opaque closure" $
      any (edgeHasClosure . program) allCmds `shouldBe` False
    it "the close-board lifecycle guard (PAll) contains no closure" $
      predHasClosure closeBoardGuard `shouldBe` False

  describe "INV1 — derived replay reconstitutes the correct Map" $
    it "structural forward replay matches the reference oracle on every sequence" $
      map reconstitute seqs `shouldBe` map reference seqs

  describe "INV2 — solveOutput invertibility: TLookupField joins the structural side" $ do
    let priorSeverity = KLookup "blockers" keyOf "severity" bsSeverity
    it "TLookupField classifies as register-recoverable, like a literal read" $ do
      classify priorSeverity `shouldBe` FromRegisters
      classify (KLit (0 :: Int)) `shouldBe` FromRegisters
    it "an opaque closure is the contrasting NON-structural class" $
      classify (KClosure "sz" (const (0 :: Int))) `shouldBe` OpaqueRecompute
    it "a TLookupField output field never breaks the gather (Just, like TReg)" $
      stepOneSlots priorSeverity `shouldBe` Just []
    it "an on-wire input field contributes its recovered slot" $
      stepOneSlots (KInpField "severity" cSeverity) `shouldBe` Just ["severity"]

  describe "INV3 — checkHiddenInputs understands collection updates" $ do
    let addUpd = eUpdate (program (AddBlocker 1 5))
    it "an insert whose element data IS on the wire is clean" $
      checkHiddenEdge ["id", "severity"] addUpd `shouldBe` False
    it "a silent ε-edge insert (no output) whose data reads the input is FLAGGED" $
      checkHiddenEdge [] addUpd `shouldBe` True
    it "an insert that recovers id but NOT severity is flagged (partial coverage)" $
      checkHiddenEdge ["id"] addUpd `shouldBe` True
    it "a delete that only reads the key is clean once the key is on the wire" $
      checkHiddenEdge ["id"] (CDelete keyOf) `shouldBe` False

  describe "INV4 — static output arity (no per-element multiplicity)" $
    it "every edge emits a fixed number of events independent of the board" $
      map outputArity allCmds `shouldBe` [1, 1, 1]

  describe "INV6 — NoThunks: long replay over a strict map yields a forced board" $
    it "reconstituting 2000 commands forces fully (size computable, no bottom)" $ do
      let cmds = [AddBlocker i (i `mod` 7) | i <- [1 .. 2000]]
          b = reconstitute cmds
      Map.size b `shouldBe` 2000
      -- force every element to WHNF; a thunk tower would leak here
      sum (map bsSeverity (Map.elems b)) `shouldBe` sum [i `mod` 7 | i <- [1 .. 2000]]

  describe "FR6 — Option B: honest, queryable symbolic status" $ do
    it "a scalar guard is fully Verified" $
      translateOptionB (PScalar True) `shouldBe` Verified
    it "a PMember collection guard yields a NAMED, queryable skipped status" $
      translateOptionB (PMemberC keyOf) `shouldBe` SkippedCollectionGuard "PMember"
    it "the PAll lifecycle guard is skipped-but-named, never a silent free Bool" $
      translateOptionB closeBoardGuard `shouldBe` SkippedCollectionGuard "PAll"
    it "collection-guarded edges report unverified; the statuses are inspectable" $
      map (translateOptionB . eGuard . program) allCmds
        `shouldBe` [ SkippedCollectionGuard "PNotMember",
                     SkippedCollectionGuard "PMember",
                     SkippedCollectionGuard "PMember"
                   ]

  describe "INV5 — the scalar core path is untouched (real keiki still works)" $
    it "a scalar keiki Term evaluates exactly as before" $
      evalTerm (TLit 42 :: Term '[] () '[] Int) RNil () `shouldBe` 42
