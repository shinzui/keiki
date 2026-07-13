-- | Three-stage stateful counter pipeline used by the EP-69 Category
-- and Choice regression tests. See the plan at
-- docs/plans/69-replace-the-fabricated-weakenr-and-knownslotnames-dictionary-in-category-composition-with-real-induction-witnesses.md
-- for the two design constraints (mid-alphabet constructor-name
-- alignment; no cross-stage register reads in substituted update RHSs).
module Keiki.Fixtures.CounterPipeline
  ( MsgA (..),
    MsgB (..),
    MsgC (..),
    MsgD (..),
    StageVertex (..),
    ARegs,
    BRegs,
    CRegs,
    stageA,
    stageB,
    stageC,
    stageConflict,
    inMsgB,
    inMsgC,
    inMsgD,
    wireMsgB,
    wireMsgC,
    wireMsgD,
  )
where

import Data.Proxy (Proxy (..))
import GHC.TypeLits (KnownSymbol)
import Keiki.Core

newtype MsgA = MsgA Int deriving stock (Eq, Show)

newtype MsgB = MsgB Int deriving stock (Eq, Show)

newtype MsgC = MsgC Int deriving stock (Eq, Show)

newtype MsgD = MsgD Int deriving stock (Eq, Show)

-- | Every stage is a one-vertex machine that loops on itself.
data StageVertex = StageVertex deriving stock (Eq, Ord, Show, Bounded, Enum)

type ARegs = '[ '("regA", Int)]

type BRegs = '[ '("regB", Int)]

type CRegs = '[ '("regC", Int)]

-- | One-field input schema shared by all pipeline messages.
type PayloadSchema = '[ '("payload", Int)]

mkInCtor :: String -> (msg -> Int) -> (Int -> msg) -> InCtor msg PayloadSchema
mkInCtor name unwrap rebuild =
  InCtor
    { icName = name,
      icMatch = \m -> Just (RCons (Proxy @"payload") (unwrap m) RNil),
      icBuild = \(RCons _ n RNil) -> rebuild n
    }

mkWireCtor :: String -> (msg -> Int) -> (Int -> msg) -> WireCtor msg (Int, ())
mkWireCtor name unwrap rebuild =
  WireCtor
    { wcName = name,
      wcMatch = \m -> Just (unwrap m, ()),
      wcBuild = \(n, ()) -> rebuild n
    }

inMsgA :: InCtor MsgA PayloadSchema
inMsgA = mkInCtor "MsgA" (\(MsgA n) -> n) MsgA

inMsgB :: InCtor MsgB PayloadSchema
inMsgB = mkInCtor "MsgB" (\(MsgB n) -> n) MsgB

inMsgC :: InCtor MsgC PayloadSchema
inMsgC = mkInCtor "MsgC" (\(MsgC n) -> n) MsgC

inMsgD :: InCtor MsgD PayloadSchema
inMsgD = mkInCtor "MsgD" (\(MsgD n) -> n) MsgD

wireMsgB :: WireCtor MsgB (Int, ())
wireMsgB = mkWireCtor "MsgB" (\(MsgB n) -> n) MsgB

wireMsgC :: WireCtor MsgC (Int, ())
wireMsgC = mkWireCtor "MsgC" (\(MsgC n) -> n) MsgC

wireMsgD :: WireCtor MsgD (Int, ())
wireMsgD = mkWireCtor "MsgD" (\(MsgD n) -> n) MsgD

-- | Shared stage shape: guard reads the register (a real read, always
-- satisfied for this fixture's inputs); update accumulates the input
-- payload into the register; output is the caller-supplied field term.
counterStage ::
  forall name inMsg outMsg.
  (KnownSymbol name) =>
  InCtor inMsg PayloadSchema ->
  WireCtor outMsg (Int, ()) ->
  ( Term '[ '(name, Int)] inMsg PayloadSchema Int ->
    Term '[ '(name, Int)] inMsg PayloadSchema Int
  ) ->
  SymTransducer
    (HsPred '[ '(name, Int)] inMsg)
    '[ '(name, Int)]
    StageVertex
    inMsg
    outMsg
counterStage ic wc mkField =
  SymTransducer
    { edgesOut = \StageVertex ->
        [ Edge
            { guard =
                PAnd
                  (PInCtor ic)
                  (PCmp CmpGe (TReg ZIdx) (TLit (0 :: Int))),
              update = USet IZ (tadd (TReg ZIdx) (TInpCtorField ic ZIdx)),
              output =
                [pack ic wc (OFCons (mkField (TInpCtorField ic ZIdx)) OFNil)],
              target = StageVertex
            }
        ],
      initial = StageVertex,
      initialRegs = RCons (Proxy @name) 0 RNil,
      isFinal = const True
    }

-- | Stage a: doubles the payload; accumulates inputs into @regA@.
stageA :: SymTransducer (HsPred ARegs MsgA) ARegs StageVertex MsgA MsgB
stageA = counterStage inMsgA wireMsgB (\p -> tmul p (lit 2))

-- | Stage b: increments the payload; accumulates inputs into @regB@.
stageB :: SymTransducer (HsPred BRegs MsgB) BRegs StageVertex MsgB MsgC
stageB = counterStage inMsgB wireMsgC (\p -> tadd p (lit 1))

-- | Stage c adds its own accumulator to the payload. The register
-- read detects a composite dictionary that fails to shift past the
-- upstream slots.
stageC :: SymTransducer (HsPred CRegs MsgC) CRegs StageVertex MsgC MsgD
stageC = counterStage inMsgC wireMsgD (\p -> tadd p (TReg ZIdx))

-- | A @MsgD -> MsgD@ stage that deliberately reuses stage a's slot
-- name. Composing it after a pipeline containing stage a must raise
-- 'Keiki.Profunctor.CategoryOverlapError'.
stageConflict ::
  SymTransducer
    (HsPred '[ '("regA", Int)] MsgD)
    '[ '("regA", Int)]
    StageVertex
    MsgD
    MsgD
stageConflict =
  counterStage
    inMsgD
    (mkWireCtor "MsgDOut" (\(MsgD n) -> n) MsgD)
    id
