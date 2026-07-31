{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE QualifiedDo #-}

-- | EP-6 (keiro MasterPlan 24): 'ReplayOnly' edges. A replay-only edge
-- is excluded from forward stepping and participates in inversion only
-- when no 'Live' edge attributes the observed event. The fixture is the
-- keiki-level shape of the "black-acuity" guard-tightening scenario:
-- machine A confirms any reservation; machine B tightens the guard to
-- non-black acuity; the replay-only twin carries the removed region
-- (@acuityBlack == True@) so history stays replayable.
module Keiki.ReplayOnlySpec (spec) where

import Data.Proxy (Proxy (..))
import Keiki.Builder ((.=))
import Keiki.Builder qualified as B
import Keiki.Core
import Test.Hspec

-- * Fixture: the black-acuity scenario at the keiki level ------------------

data DivertCmd = ConfirmReservation Bool
  deriving stock (Eq, Show)

data DivertEvent = ReservationConfirmed Bool
  deriving stock (Eq, Show)

data DivertVertex = Held | Confirmed
  deriving stock (Eq, Ord, Show, Enum, Bounded)

type DivertRegs = '[ '("wasBlack", Bool)]

inCtorConfirm :: InCtor DivertCmd '[ '("acuityBlack", Bool)]
inCtorConfirm =
  InCtor
    { icName = "ConfirmReservation",
      icMatch = \case
        ConfirmReservation b -> Just (RCons (Proxy @"acuityBlack") b RNil),
      icBuild = \(RCons _ b RNil) -> ConfirmReservation b
    }

wireConfirmed :: WireCtor DivertEvent (Bool, ())
wireConfirmed =
  WireCtor
    { wcName = "ReservationConfirmed",
      wcMatch = \case
        ReservationConfirmed b -> Just (b, ()),
      wcBuild = \(b, ()) -> ReservationConfirmed b
    }

initialDivertRegs :: RegFile DivertRegs
initialDivertRegs = RCons (Proxy @"wasBlack") False RNil

acuityRead :: Term DivertRegs DivertCmd '[ '("acuityBlack", Bool)] Bool
acuityRead = inpCtor inCtorConfirm ZIdx

confirmOut :: OutTerm DivertRegs DivertCmd DivertEvent
confirmOut = pack inCtorConfirm wireConfirmed (OFCons acuityRead OFNil)

recordAcuity :: Update DivertRegs '["wasBlack"] DivertCmd
recordAcuity = USet (#wasBlack :: IndexN "wasBlack" DivertRegs Bool) acuityRead

-- | The old rule: confirm any reservation.
oldGuard :: HsPred DivertRegs DivertCmd
oldGuard = matchInCtor inCtorConfirm

-- | The tightened rule: confirm only non-black acuity.
newGuard :: HsPred DivertRegs DivertCmd
newGuard = PAnd (matchInCtor inCtorConfirm) (PEq acuityRead (TLit False))

-- | The removed region, @old ∧ ¬new@: exactly black acuity.
removedRegionGuard :: HsPred DivertRegs DivertCmd
removedRegionGuard = PAnd (matchInCtor inCtorConfirm) (PEq acuityRead (TLit True))

confirmEdge :: HsPred DivertRegs DivertCmd -> EdgeMode -> Edge (HsPred DivertRegs DivertCmd) DivertRegs DivertCmd DivertEvent DivertVertex
confirmEdge g m =
  Edge
    { guard = g,
      update = recordAcuity,
      output = [confirmOut],
      target = Confirmed,
      mode = m
    }

divertMachine ::
  [Edge (HsPred DivertRegs DivertCmd) DivertRegs DivertCmd DivertEvent DivertVertex] ->
  SymTransducer (HsPred DivertRegs DivertCmd) DivertRegs DivertVertex DivertCmd DivertEvent
divertMachine heldEdges =
  SymTransducer
    { edgesOut = \case
        Held -> heldEdges
        Confirmed -> [],
      initial = Held,
      initialRegs = initialDivertRegs,
      isFinal = (== Confirmed)
    }

-- | Machine A: the original rule, before tightening.
machineA :: SymTransducer (HsPred DivertRegs DivertCmd) DivertRegs DivertVertex DivertCmd DivertEvent
machineA = divertMachine [confirmEdge oldGuard Live]

-- | Machine B without the twin: the tightened rule alone. Events
-- written under the old rule in the removed region lose their
-- inverting edge.
machineBBad :: SymTransducer (HsPred DivertRegs DivertCmd) DivertRegs DivertVertex DivertCmd DivertEvent
machineBBad = divertMachine [confirmEdge newGuard Live]

-- | Machine B with the replay-only twin carrying the removed region.
machineBGood :: SymTransducer (HsPred DivertRegs DivertCmd) DivertRegs DivertVertex DivertCmd DivertEvent
machineBGood =
  divertMachine
    [ confirmEdge newGuard Live,
      confirmEdge removedRegionGuard ReplayOnly
    ]

-- | A sloppy twin whose guard overlaps the live edge (it kept the whole
-- old guard instead of the complement). Its update is deliberately
-- distinguishable (constant 'True') so a test can tell which edge
-- applied during replay.
machineOverlap :: SymTransducer (HsPred DivertRegs DivertCmd) DivertRegs DivertVertex DivertCmd DivertEvent
machineOverlap =
  divertMachine
    [ confirmEdge newGuard Live,
      Edge
        { guard = oldGuard,
          update = USet (#wasBlack :: IndexN "wasBlack" DivertRegs Bool) (TLit True),
          output = [confirmOut],
          target = Confirmed,
          mode = ReplayOnly
        }
    ]

-- | Two replay-only edges competing for the same wire constructor with
-- overlapping guards: same-mode ambiguity must still be caught.
machineTwinClash :: SymTransducer (HsPred DivertRegs DivertCmd) DivertRegs DivertVertex DivertCmd DivertEvent
machineTwinClash =
  divertMachine
    [ confirmEdge oldGuard ReplayOnly,
      confirmEdge oldGuard ReplayOnly
    ]

-- | Both overlap edges live: the pre-existing checks must still flag.
machineLiveClash :: SymTransducer (HsPred DivertRegs DivertCmd) DivertRegs DivertVertex DivertCmd DivertEvent
machineLiveClash =
  divertMachine
    [ confirmEdge newGuard Live,
      confirmEdge oldGuard Live
    ]

-- | 'Confirmed' is reachable ONLY through the replay-only edge, and has
-- an outgoing live edge. Replay continuation makes that vertex live
-- (an old stream replays through the twin, then serves new commands),
-- so the dead-edge check must not flag its outgoing edges.
machineTwinOnlyPath :: SymTransducer (HsPred DivertRegs DivertCmd) DivertRegs DivertVertex DivertCmd DivertEvent
machineTwinOnlyPath =
  SymTransducer
    { edgesOut = \case
        Held -> [confirmEdge removedRegionGuard ReplayOnly]
        -- A live self-loop at the vertex reachable only via the twin.
        Confirmed -> [confirmEdge oldGuard Live],
      initial = Held,
      initialRegs = initialDivertRegs,
      isFinal = (== Confirmed)
    }

blackHistory :: [DivertEvent]
blackHistory = [ReservationConfirmed True]

-- * Builder surface --------------------------------------------------------

-- | The same twin-bearing machine written through "Keiki.Builder",
-- marking the twin with 'B.replayOnly'.
builderMachine :: SymTransducer (HsPred DivertRegs DivertCmd) DivertRegs DivertVertex DivertCmd DivertEvent
builderMachine =
  B.buildTransducer Held initialDivertRegs (== Confirmed) $ Prelude.do
    B.from Held Prelude.do
      B.onCmd inCtorConfirm $ \d -> B.do
        B.requireEq d.acuityBlack (TLit False)
        B.slot @"wasBlack" .= d.acuityBlack
        B.emit wireConfirmed (d.acuityBlack B.*: B.oNil)
        B.goto Confirmed
      B.onCmd inCtorConfirm $ \d -> B.do
        B.replayOnly
        B.requireEq d.acuityBlack (TLit True)
        B.slot @"wasBlack" .= d.acuityBlack
        B.emit wireConfirmed (d.acuityBlack B.*: B.oNil)
        B.goto Confirmed
    B.from Confirmed (Prelude.pure ())

-- * Specs ------------------------------------------------------------------

spec :: Spec
spec = do
  describe "forward stepping" $ do
    it "machine A accepts a black-acuity confirmation and emits its event" $
      case stepEither machineA (Held, initialDivertRegs) (ConfirmReservation True) of
        Right (v, regs, outs) -> do
          v `shouldBe` Confirmed
          regs ! #wasBlack `shouldBe` True
          outs `shouldBe` blackHistory
        Left failure -> expectationFailure ("machine A rejected: " <> show failure)

    it "never selects a ReplayOnly edge even when its guard models the command" $
      case stepEither machineBGood (Held, initialDivertRegs) (ConfirmReservation True) of
        Left (NoMatchingEdge Held rejected) ->
          -- Both edges are reported rejected: the live edge by its
          -- guard, the twin by its mode.
          map (edgeIndex . rejectedEdge) rejected `shouldBe` [0, 1]
        Left other -> expectationFailure ("expected NoMatchingEdge, got " <> show other)
        Right (v, _, outs) ->
          expectationFailure ("expected rejection, stepped to " <> show (v, outs))

    it "delta and omega agree that the removed region is rejected" $ do
      case delta machineBGood Held initialDivertRegs (ConfirmReservation True) of
        Nothing -> pure ()
        Just (v, _) -> expectationFailure ("delta stepped to " <> show v)
      omega machineBGood Held initialDivertRegs (ConfirmReservation True)
        `shouldBe` []

    it "still accepts commands under the tightened live rule" $
      case stepEither machineBGood (Held, initialDivertRegs) (ConfirmReservation False) of
        Right (v, regs, outs) -> do
          v `shouldBe` Confirmed
          regs ! #wasBlack `shouldBe` False
          outs `shouldBe` [ReservationConfirmed False]
        Left failure -> expectationFailure ("live edge rejected: " <> show failure)

    it "reports NoMatchingEdge (not NoOutgoingEdges) at a replay-only-only vertex" $
      case stepEither machineTwinOnlyPath (Held, initialDivertRegs) (ConfirmReservation True) of
        Left (NoMatchingEdge Held [rejected]) ->
          rejectedTarget rejected `shouldBe` Confirmed
        Left other -> expectationFailure ("expected one rejected edge, got " <> show other)
        Right (v, _, outs) ->
          expectationFailure ("expected rejection, stepped to " <> show (v, outs))

  describe "two-phase inversion" $ do
    it "black-acuity history fails to invert without the twin" $
      case reconstituteEither machineBBad blackHistory of
        Left failure -> do
          replayFailedIndex failure `shouldBe` 0
          case replayFailureReason failure of
            ReplayEventFailed (ReplayNoInvertingEdge Held _) -> pure ()
            other ->
              expectationFailure ("expected ReplayNoInvertingEdge, got " <> show other)
        Right result ->
          expectationFailure ("expected replay failure, got " <> show (fst result))

    it "black-acuity history inverts through the twin, applying its writes" $
      case reconstituteEither machineBGood blackHistory of
        Right (v, regs) -> do
          v `shouldBe` Confirmed
          regs ! #wasBlack `shouldBe` True
        Left failure -> expectationFailure ("twin replay failed: " <> show failure)

    it "replays machine A's history identically under the twin-bearing machine" $
      case (reconstituteEither machineA blackHistory, reconstituteEither machineBGood blackHistory) of
        (Right (vA, regsA), Right (vB, regsB)) ->
          (vB, regsB ! #wasBlack) `shouldBe` (vA, regsA ! #wasBlack)
        (Left failure, _) -> expectationFailure ("machine A replay failed: " <> show failure)
        (_, Left failure) -> expectationFailure ("machine B replay failed: " <> show failure)

    it "prefers the live edge when a sloppy twin's guard overlaps it" $
      case reconstituteEither machineOverlap [ReservationConfirmed False] of
        Right (v, regs) -> do
          v `shouldBe` Confirmed
          -- The live edge writes the event's own acuity (False); the
          -- sloppy twin would have written the constant True. Live wins.
          regs ! #wasBlack `shouldBe` False
        Left failure ->
          expectationFailure ("expected live-phase attribution: " <> show failure)

    it "falls through to the sloppy twin only for unattributable history" $
      case reconstituteEither machineOverlap blackHistory of
        Right (v, regs) -> do
          v `shouldBe` Confirmed
          regs ! #wasBlack `shouldBe` True
        Left failure -> expectationFailure ("twin fallthrough failed: " <> show failure)

    it "still reports ambiguity between two replay-only candidates" $
      case reconstituteEither machineTwinClash blackHistory of
        Left failure ->
          case replayFailureReason failure of
            ReplayEventFailed (ReplayAmbiguousInversions Held matchedEdges) ->
              map (edgeIndex . matchedEdge) matchedEdges `shouldBe` [0, 1]
            other ->
              expectationFailure ("expected ReplayAmbiguousInversions, got " <> show other)
        Right result ->
          expectationFailure ("expected ambiguity failure, got " <> show (fst result))

    it "applies the same two-phase preference in letter-only applyEvent" $ do
      case applyEvent machineBBad Held initialDivertRegs (ReservationConfirmed True) of
        Nothing -> pure ()
        Just (v, _) -> expectationFailure ("applyEvent inverted to " <> show v)
      case applyEvent machineBGood Held initialDivertRegs (ReservationConfirmed True) of
        Just (v, regs) -> do
          v `shouldBe` Confirmed
          regs ! #wasBlack `shouldBe` True
        Nothing -> expectationFailure "applyEvent could not use the twin"
      case applyEvent machineOverlap Held initialDivertRegs (ReservationConfirmed False) of
        Just (_, regs) -> regs ! #wasBlack `shouldBe` False
        Nothing -> expectationFailure "applyEvent could not use the live edge"

  describe "static checks" $ do
    it "does not flag a live/replay-only pair as an inversion ambiguity" $
      inversionAmbiguityWarnings machineBGood `shouldBe` []

    it "still flags a same-mode replay-only pair as an inversion ambiguity" $
      case inversionAmbiguityWarnings machineTwinClash of
        [InversionAmbiguity {tvwSource = Held, tvwEdgeA = 0, tvwEdgeB = 1}] -> pure ()
        other -> expectationFailure ("expected one same-mode warning, got " <> show other)

    it "does not flag a live/replay-only guard overlap as nondeterminism" $
      checkTransitionDeterminismPure machineOverlap `shouldBe` []

    it "still flags the same overlap when both edges are live" $
      case checkTransitionDeterminismPure machineLiveClash of
        [DeterminismWarning {dwSource = Held, dwEdgeA = 0, dwEdgeB = 1}] -> pure ()
        other -> expectationFailure ("expected one overlap warning, got " <> show other)

    it "keeps vertices reachable through replay-only edges out of the dead-edge report" $
      checkDeadEdges defaultDeadEdgeOptions machineTwinOnlyPath `shouldBe` []

    it "validates the twin-bearing black-acuity machine clean by default" $
      validateTransducer defaultValidationOptions machineBGood `shouldBe` []

    it "flags machineLiveClash through the default umbrella (control)" $
      validateTransducer defaultValidationOptions machineLiveClash
        `shouldNotBe` []

  describe "Keiki.Builder replayOnly" $ do
    it "marks the edge ReplayOnly and leaves unmarked edges Live" $
      map mode (edgesOut builderMachine Held) `shouldBe` [Live, ReplayOnly]

    it "behaves like the hand-written twin machine" $ do
      case stepEither builderMachine (Held, initialDivertRegs) (ConfirmReservation True) of
        Left (NoMatchingEdge Held _) -> pure ()
        Left other -> expectationFailure ("expected forward rejection, got " <> show other)
        Right (v, _, outs) ->
          expectationFailure ("expected rejection, stepped to " <> show (v, outs))
      case reconstituteEither builderMachine blackHistory of
        Right (v, regs) -> do
          v `shouldBe` Confirmed
          regs ! #wasBlack `shouldBe` True
        Left failure -> expectationFailure ("builder twin replay failed: " <> show failure)

  describe "EdgeMode combination" $ do
    it "is Live only when every component is Live" $ do
      Live <> Live `shouldBe` Live
      Live <> ReplayOnly `shouldBe` ReplayOnly
      ReplayOnly <> Live `shouldBe` ReplayOnly
      ReplayOnly <> ReplayOnly `shouldBe` ReplayOnly
      mempty `shouldBe` Live
