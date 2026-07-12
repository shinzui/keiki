{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE QualifiedDo #-}
{-# LANGUAGE TemplateHaskell #-}

-- | EP-15 M6: hand-written unit tests for 'Keiki.Builder'. Tests use
-- a tiny in-spec toy transducer (single-slot register file, two
-- vertices, one or two edges) so each behaviour is exercised in
-- isolation.
module Keiki.BuilderSpec (spec) where

import Control.Exception (evaluate)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import GHC.Generics (Generic)
import Keiki.Builder ((.=), (=:))
import Keiki.Builder qualified as B
import Keiki.Core
  ( Edge (..),
    HsPred (..),
    Index,
    OutFields (..),
    RegFile,
    SymTransducer (..),
    applyEvent,
    delta,
    lit,
    omega,
  )
import Keiki.Core qualified as K
import Keiki.Generics (emptyRegFile)
import Keiki.Generics.TH (deriveAggregateCtors, deriveWireCtors)
import Test.Hspec

-- * Toy transducer ---------------------------------------------------------

-- Single-slot register file. The slot's value is set by the
-- 'Tick' command and emitted by the 'TickEvent' wire ctor.
type Regs = '[ '("counter", Int)]

emptyR :: RegFile Regs
emptyR = emptyRegFile

data ToyVertex = A | B
  deriving (Eq, Show, Enum, Bounded)

data TickData = TickData {count :: Int}
  deriving (Eq, Show, Generic)

data ToyCmd = Tick TickData | Idle
  deriving (Eq, Show, Generic)

data TickEventData = TickEventData {count :: Int}
  deriving (Eq, Show, Generic)

data ToyEvent = Ticked TickEventData
  deriving (Eq, Show, Generic)

$( deriveAggregateCtors
     ''ToyCmd
     ''Regs
     [ ("Tick", "Tick"),
       ("Idle", "Idle")
     ]
 )

$( deriveWireCtors
     ''ToyEvent
     [ ("Ticked", "Ticked")
     ]
 )

t0 :: UTCTime
t0 = UTCTime (fromGregorian 2026 5 2) (secondsToDiffTime 0)

-- * Auxiliary toy: 2-slot register file for case 2 -----------------------

type TwoRegs = '[ '("x", Int), '("y", Int)]

emptyTwoR :: RegFile TwoRegs
emptyTwoR = emptyRegFile

data TwoData = TwoData {x :: Int, y :: Int}
  deriving (Eq, Show, Generic)

data TwoCmd = Two TwoData
  deriving (Eq, Show, Generic)

data TwoEventData = TwoEventData {x :: Int, y :: Int}
  deriving (Eq, Show, Generic)

data TwoEvent = TwoEv TwoEventData
  deriving (Eq, Show, Generic)

$( deriveAggregateCtors
     ''TwoCmd
     ''TwoRegs
     [ ("Two", "Two")
     ]
 )

$( deriveWireCtors
     ''TwoEvent
     [ ("TwoEv", "TwoEv")
     ]
 )

-- * Pretty-printing aids -------------------------------------------------

showGuard :: HsPred rs ci -> String
showGuard PTop = "PTop"
showGuard PBot = "PBot"
showGuard (PAnd a b) = "PAnd (" <> showGuard a <> ") (" <> showGuard b <> ")"
showGuard (POr a b) = "POr (" <> showGuard a <> ") (" <> showGuard b <> ")"
showGuard (PNot p) = "PNot (" <> showGuard p <> ")"
showGuard (PEq _ _) = "PEq <term> <term>"
showGuard (PInCtor _) = "PInCtor <ic>"

-- * Spec -------------------------------------------------------------------

spec :: Spec
spec = do
  describe "EP-15 M6: Keiki.Builder unit cases" $ do
    -- Case 1: single (.=) produces a USet whose evaluator agrees
    -- with the reference register update.
    it "case 1: single (.=) writes the slot the evaluator reads" $ do
      let tr = B.buildTransducer A emptyR (const False) do
            B.from A do
              B.onCmd inCtorTick $ \d -> B.do
                B.slot @"counter" .= d.count
                B.emit wireTicked (OFCons d.count OFNil)
                B.goto B
          cmd = Tick (TickData 42)
      case delta tr A emptyR cmd of
        Just (_, regs) -> regs K.! (#counter :: Index Regs Int) `shouldBe` 42
        Nothing -> expectationFailure "delta returned Nothing"

    -- Case 2: sequential (.=) to distinct slots agrees with the
    -- composite reference. Use a 2-slot register file inline.
    it "case 2: sequential (.=) to distinct slots writes both" $ do
      let tr2 = B.buildTransducer A emptyTwoR (const False) do
            B.from A do
              B.onCmd inCtorTwo $ \d -> B.do
                B.slot @"x" .= d.x
                B.slot @"y" .= d.y
                B.emit wireTwoEv (OFCons d.x (OFCons d.y OFNil))
                B.goto B
          cmd = Two (TwoData 7 11)
      case delta tr2 A emptyTwoR cmd of
        Just (_, regs) -> do
          regs K.! (#x :: Index TwoRegs Int) `shouldBe` 7
          regs K.! (#y :: Index TwoRegs Int) `shouldBe` 11
        Nothing -> expectationFailure "delta returned Nothing"

    -- Case 3: sequential (.=) to the SAME slot. Compile-time error.
    -- Not exercised here as a runtime hspec assertion: the GHC
    -- TypeError fires at compile time, not runtime, so it cannot be
    -- caught with `evaluate` / `shouldThrow` without enabling
    -- -fdefer-type-errors module-wide. Instead, the spec/spike
    -- modules' own compilation success is the (positive) proof:
    -- both type-check because they only ever write each slot once.
    -- See docs/research/edge-builder-dsl-shape.md Q1 for the worked
    -- error message.

    -- Case 4: emit followed by replay via solveOutput round-trips.
    -- For any cmd: applyEvent (omega ...) recovers the (s', regs')
    -- that delta produced.
    it "case 4: emit then solveOutput round-trips delta/applyEvent" $ do
      let tr = B.buildTransducer A emptyR (const False) do
            B.from A do
              B.onCmd inCtorTick $ \d -> B.do
                B.slot @"counter" .= d.count
                B.emit wireTicked (OFCons d.count OFNil)
                B.goto B
          cmd = Tick (TickData 9)
      case delta tr A emptyR cmd of
        Nothing -> expectationFailure "delta returned Nothing"
        Just (s', regs') -> case omega tr A emptyR cmd of
          [] -> expectationFailure "omega returned []"
          [co] -> case applyEvent tr A emptyR co of
            Nothing -> expectationFailure "applyEvent returned Nothing"
            Just (s'', regs'') -> do
              s'' `shouldBe` s'
              (regs'' K.! (#counter :: Index Regs Int))
                `shouldBe` (regs' K.! (#counter :: Index Regs Int))
          cos_ ->
            expectationFailure
              ( "omega returned an unexpected multi-event list of "
                  <> show (length cos_)
              )

    -- Case 5: noEmit produces an Edge whose output is [] (ε-edge).
    it "case 5: noEmit yields output = []" $ do
      let tr = B.buildTransducer A emptyR (const False) do
            B.from A do
              B.onCmd inCtorTick $ \_d -> B.do
                B.noEmit
                B.goto B
      case edgesOut tr A of
        [e] -> case output e of
          [] -> pure ()
          _ -> expectationFailure "expected ε-edge but got non-empty output list"
        es -> expectationFailure ("expected exactly 1 edge, got " <> show (length es))

    -- Case 6: goto V sets target = V.
    it "case 6: goto V sets target to V" $ do
      let tr = B.buildTransducer A emptyR (const False) do
            B.from A do
              B.onCmd inCtorTick $ \_d -> B.do
                B.noEmit
                B.goto B
      case edgesOut tr A of
        [e] -> target e `shouldBe` B
        _ -> expectationFailure "expected exactly 1 edge"

    -- Case 7: missing goto. Runtime error names source vertex and
    -- edge index.
    it "case 7: missing goto fires the expected runtime error" $ do
      let tr = B.buildTransducer A emptyR (const False) do
            B.from A do
              B.onCmd inCtorTick $ \_d -> B.do
                B.noEmit -- intentional: no goto
      evaluate tr
        `shouldThrow` errorCall
          ( "Keiki.Builder: edge #0 from A: goto missing. "
              <> "Each onCmd/onEpsilon body must end with "
              <> "exactly one goto V."
          )

    -- Case 8: multiple goto. Runtime error names source vertex and
    -- edge index.
    it "case 8: multiple goto fires the expected runtime error" $ do
      let tr = B.buildTransducer A emptyR (const False) do
            B.from A do
              B.onCmd inCtorTick $ \_d -> B.do
                B.goto B
                B.goto A
      evaluate tr
        `shouldThrow` errorCall
          ( "Keiki.Builder: edge #0 from A: goto called "
              <> "more than once. Each onCmd/onEpsilon body "
              <> "must end with exactly one goto V."
          )

    -- Case 9: requireEq extends the guard. The starting guard from
    -- onCmd is matchInCtor (a PInCtor); requireEq adds a PAnd-PEq
    -- conjunct. We assert this by structural inspection.
    it "case 9: requireEq extends the guard with PAnd-PEq" $ do
      let tr = B.buildTransducer A emptyR (const False) do
            B.from A do
              B.onCmd inCtorTick $ \d -> B.do
                B.requireEq d.count (lit 7)
                B.noEmit
                B.goto B
      case edgesOut tr A of
        [e] -> case guard e of
          PAnd (PInCtor _) (PEq _ _) -> pure ()
          other -> expectationFailure ("guard shape mismatch: " <> showGuard other)
        _ -> expectationFailure "expected exactly 1 edge"

    -- Case 10: onEpsilon (no onCmd) builds a guard-only edge with
    -- guard = PTop.
    it "case 10: onEpsilon builds a guard-only edge with guard = PTop" $ do
      let tr = B.buildTransducer A emptyR (const False) do
            B.from A do
              B.onEpsilon B.do
                B.goto B
      case edgesOut tr A of
        [e] -> case guard e of
          PTop -> pure ()
          other -> expectationFailure ("guard shape mismatch: " <> showGuard other)
        _ -> expectationFailure "expected exactly 1 edge"

    -- Case 11: two onCmd blocks under one `from` produce two
    -- edges, in order. Demonstrates that EdgeListBuilder's plain-Monad
    -- (>>=) sequences edge-list-prepends correctly and that `from`
    -- reverses them so the final edge order matches authoring order.
    it "case 11: two onCmd blocks under one `from` produce two edges in order" $ do
      let tr = B.buildTransducer A emptyR (const False) do
            B.from A do
              B.onCmd inCtorTick $ \_d -> B.do
                B.noEmit
                B.goto B
              B.onCmd inCtorIdle $ \_d -> B.do
                B.noEmit
                B.goto A
      case edgesOut tr A of
        [e1, e2] -> do
          target e1 `shouldBe` B -- Tick goes to B (first onCmd)
          target e2 `shouldBe` A -- Idle goes to A (second onCmd)
        es -> expectationFailure ("expected exactly 2 edges, got " <> show (length es))

    it "EP-70: missing goto on an undriven vertex fails at construction" $ do
      let tr = B.buildTransducer A emptyR (const False) do
            B.from A do
              B.onCmd inCtorTick $ \_d -> B.do
                B.noEmit
                B.goto A
            B.from B do
              B.onCmd inCtorIdle $ \_d -> B.do
                B.noEmit
      evaluate tr
        `shouldThrow` errorCall
          ( "Keiki.Builder: edge #0 from B: goto missing. "
              <> "Each onCmd/onEpsilon body must end with "
              <> "exactly one goto V."
          )

    it "EP-70: duplicate `from` blocks merge in declaration order" $ do
      let tr = B.buildTransducer A emptyR (const False) do
            B.from A do
              B.onCmd inCtorTick $ \_d -> B.do
                B.noEmit
                B.goto B
            B.from A do
              B.onCmd inCtorIdle $ \_d -> B.do
                B.noEmit
                B.goto A
      case edgesOut tr A of
        [e1, e2] -> do
          target e1 `shouldBe` B
          target e2 `shouldBe` A
        es -> expectationFailure ("expected exactly 2 edges, got " <> show (length es))

    it "EP-70: merged blocks report globally consistent edge indices" $ do
      let tr = B.buildTransducer A emptyR (const False) do
            B.from A do
              B.onCmd inCtorTick $ \_d -> B.do
                B.noEmit
                B.goto B
            B.from A do
              B.onCmd inCtorIdle $ \_d -> B.do
                B.noEmit
      evaluate tr
        `shouldThrow` errorCall
          ( "Keiki.Builder: edge #1 from A: goto missing. "
              <> "Each onCmd/onEpsilon body must end with "
              <> "exactly one goto V."
          )

    it "EP-70: buildTransducerEither returns every defect structurally" $ do
      let malformed = B.buildTransducerEither A emptyR (const False) do
            B.from A do
              B.onCmd inCtorTick $ \_d -> B.do
                B.noEmit
            B.from B do
              B.onCmd inCtorIdle $ \_d -> B.do
                B.goto A
                B.goto B
          expected =
            [ B.BuilderError A 0 B.DefectMissingGoto,
              B.BuilderError B 0 (B.DefectMultipleGoto 2)
            ]
      case malformed of
        Left errors -> NonEmpty.toList errors `shouldBe` expected
        Right _ -> expectationFailure "expected structured builder defects"

      let wellFormed = B.buildTransducerEither A emptyR (const False) do
            B.from A do
              B.onCmd inCtorTick $ \_d -> B.do
                B.noEmit
                B.goto B
      case wellFormed of
        Left errors -> expectationFailure ("unexpected errors: " <> show errors)
        Right tr -> case edgesOut tr A of
          [edge] -> target edge `shouldBe` B
          edges -> expectationFailure ("expected exactly 1 edge, got " <> show (length edges))

  describe "EP-21 M4: field-keyed record sugar for B.emit" $ do
    -- Case 12: emit with the per-event record form produces the
    -- same omega output as the operator form for the same data.
    it "case 12: record-form emit and operator-form emit agree on omega" $ do
      let trRec = B.buildTransducer A emptyR (const False) do
            B.from A do
              B.onCmd inCtorTick $ \d -> B.do
                B.slot @"counter" .= d.count
                B.emit wireTicked TickedTermFields {count = d.count}
                B.goto B
          trOp = B.buildTransducer A emptyR (const False) do
            B.from A do
              B.onCmd inCtorTick $ \d -> B.do
                B.slot @"counter" .= d.count
                B.emit wireTicked (OFCons d.count OFNil)
                B.goto B
          cmd = Tick (TickData 17)
      omega trRec A emptyR cmd `shouldBe` omega trOp A emptyR cmd

    -- Case 13: multi-field record form preserves field-name order.
    -- Two events with shared field names compile and produce the
    -- correct OutFields under DuplicateRecordFields.
    it "case 13: record-form emit on a 2-field event applies fields in order" $ do
      let trRec = B.buildTransducer A emptyTwoR (const False) do
            B.from A do
              B.onCmd inCtorTwo $ \d -> B.do
                B.slot @"x" .= d.x
                B.slot @"y" .= d.y
                B.emit
                  wireTwoEv
                  TwoEvTermFields {x = d.x, y = d.y}
                B.goto B
          trOp = B.buildTransducer A emptyTwoR (const False) do
            B.from A do
              B.onCmd inCtorTwo $ \d -> B.do
                B.slot @"x" .= d.x
                B.slot @"y" .= d.y
                B.emit wireTwoEv (OFCons d.x (OFCons d.y OFNil))
                B.goto B
          cmd = Two (TwoData 7 11)
      omega trRec A emptyTwoR cmd `shouldBe` omega trOp A emptyTwoR cmd

    -- Case 14: emitWith (explicit InCtor) accepts the record form.
    -- Useful inside onEpsilon and as an escape hatch.
    it "case 14: emitWith with the record form produces the same omega" $ do
      let trEmitWith = B.buildTransducer A emptyR (const False) do
            B.from A do
              B.onCmd inCtorTick $ \d -> B.do
                B.slot @"counter" .= d.count
                B.emitWith
                  inCtorTick
                  wireTicked
                  TickedTermFields {count = d.count}
                B.goto B
          trEmit = B.buildTransducer A emptyR (const False) do
            B.from A do
              B.onCmd inCtorTick $ \d -> B.do
                B.slot @"counter" .= d.count
                B.emit
                  wireTicked
                  TickedTermFields {count = d.count}
                B.goto B
          cmd = Tick (TickData 5)
      omega trEmitWith A emptyR cmd `shouldBe` omega trEmit A emptyR cmd

  describe "EP-49: (=:) is a synonym for (.=)" $
    -- Authoring the same single-slot edge with `.=` and with `=:`
    -- produces the identical register write. `Update` carries `Term`s
    -- (which hold opaque functions) so it has no `Eq`; we compare the
    -- observable instead — the register file `delta` produces.
    it "produces the same register write as (.=) for the same slot+term" $ do
      let withDot = B.buildTransducer A emptyR (const False) do
            B.from A do
              B.onCmd inCtorTick $ \d -> B.do
                B.slot @"counter" .= d.count
                B.emit wireTicked (OFCons d.count OFNil)
                B.goto B
          withColon = B.buildTransducer A emptyR (const False) do
            B.from A do
              B.onCmd inCtorTick $ \d -> B.do
                B.slot @"counter" =: d.count
                B.emit wireTicked (OFCons d.count OFNil)
                B.goto B
          cmd = Tick (TickData 42)
      case (delta withDot A emptyR cmd, delta withColon A emptyR cmd) of
        (Just (_, r1), Just (_, r2)) ->
          (r1 K.! (#counter :: Index Regs Int))
            `shouldBe` (r2 K.! (#counter :: Index Regs Int))
        _ -> expectationFailure "delta returned Nothing for one of the forms"
