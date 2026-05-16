{-# LANGUAGE TemplateHaskell #-}

-- | Acceptance tests for 'Keiki.Composition.compose' under EP-11 of
-- MasterPlan 4. The fixture is a tiny pipeline:
--
--    AlertSource ⨾ EmailDelivery
--
-- Aggregate 1 ('AlertSource', defined inline in this spec) is a
-- two-vertex transducer that consumes a 'TriggerAlert' command and
-- emits an 'EmailCmd' as its event. Its output type is exactly
-- 'EmailCmd' so that the composite's @mid@ alphabet aligns with
-- 'Keiki.Fixtures.EmailDelivery''s input alphabet without an
-- explicit lifting.
--
-- Aggregate 2 is the canonical 'Keiki.Fixtures.EmailDelivery'
-- transducer.
--
-- The pipeline shape — every transition produces a wire event —
-- means the composite's 'reconstitute' round-trip is well-defined
-- (the design note discusses the ε-edge restriction).
module Keiki.CompositionSpec
  ( spec
    -- Exported for re-use in 'Keiki.Render.MermaidSpec' (EP-31 M4).
    -- See the Decision Log of
    -- @docs/plans/31-mermaid-rendering-for-composite-symtransducers.md@
    -- for why we re-export rather than duplicate the fixture.
  , alertSource
  , AlertVertex (..)
  ) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import GHC.Generics (Generic)
import Test.Hspec

import Keiki.Composition (Composite (..), compose)
import Keiki.Core
import Keiki.Fixtures.EmailDelivery
import Keiki.Generics (Append, emptyRegFile)
import Keiki.Generics.TH (deriveAggregateCtors, deriveWireCtors)
import Keiki.Symbolic (isSingleValuedSym, withSymPred)


-- * The AlertSource test fixture ------------------------------------------

-- | Command payload for the source aggregate. Carries the full set
-- of fields the composite ultimately writes into 'EmailEvent', so
-- the round-trip can verify each field arrives intact.
data TriggerAlertData = TriggerAlertData
  { recipient :: Text
  , subject   :: Text
  , at        :: UTCTime
  } deriving stock (Eq, Show, Generic)


-- | Command sum for the source aggregate.
data AlertCmd = TriggerAlert TriggerAlertData
  deriving stock (Eq, Show, Generic)


-- | The source aggregate's *output* type is EmailCmd — so the
-- composite's mid alphabet aligns with EmailDelivery's input.
type AlertEvent = EmailCmd


-- | Register file for the source aggregate. Mirrors EmailRegs in
-- field shape but with distinct slot names so 'Append AlertRegs
-- EmailRegs' has no name collisions (the keiki RegFile is
-- positional, but distinct names also keep the SBV translation's
-- free-variable names unambiguous).
type AlertRegs =
  '[ '("alertRecipient", Text)
   , '("alertSubject",   Text)
   , '("alertAt",        UTCTime)
   ]


data AlertVertex = AlertQuiescent | AlertEmitted
  deriving stock (Eq, Show, Enum, Bounded)


emptyAlertRegs :: RegFile AlertRegs
emptyAlertRegs = emptyRegFile


-- TH-derived per-constructor projections + guards.
$(deriveAggregateCtors ''AlertCmd ''AlertRegs
    [ ("TriggerAlert", "Trigger")
    ])


-- The output of AlertSource is EmailCmd — reuse the wire
-- constructor TH splice over EmailCmd by piggy-backing on
-- EmailDelivery's @SendEmail@ data ctor. We can't @deriveWireCtors@
-- against 'EmailCmd' here because that would conflict with
-- EmailDelivery's TH splice's binding of @wireSendEmail@. Build
-- the wire ctor manually using the same generic shape.
$(deriveWireCtors ''EmailCmd
    [ ("SendEmail", "SendEmailEvent")
    ])


alertSource
  :: SymTransducer (HsPred AlertRegs AlertCmd)
                   AlertRegs AlertVertex AlertCmd EmailCmd
alertSource = SymTransducer
  { edgesOut    = alertEdges
  , initial     = AlertQuiescent
  , initialRegs = emptyAlertRegs
  , isFinal     = \case AlertEmitted -> True; _ -> False
  }


alertEdges
  :: AlertVertex
  -> [Edge (HsPred AlertRegs AlertCmd) AlertRegs AlertCmd EmailCmd AlertVertex]
alertEdges = \case

  AlertQuiescent ->
    [ Edge
        { guard  = isTrigger
        , update =
            USet (#alertRecipient :: IndexN "alertRecipient" AlertRegs Text)
                 (inpTrigger #recipient)
              `combine`
            USet (#alertSubject :: IndexN "alertSubject" AlertRegs Text)
                 (inpTrigger #subject)
              `combine`
            USet (#alertAt :: IndexN "alertAt" AlertRegs UTCTime)
                 (inpTrigger #at)
          -- The output is EmailCmd — built from the trigger's payload.
        , output = [ pack
            inCtorTrigger
            wireSendEmailEvent
            (OFCons (inpTrigger #recipient)
              (OFCons (inpTrigger #subject)
                (OFCons (inpTrigger #at) OFNil))) ]
        , target = AlertEmitted
        }
    ]

  AlertEmitted -> []


-- * The composite ---------------------------------------------------------

-- | The composite pipeline: AlertSource ⨾ EmailDelivery.
--
-- Input:  AlertCmd
-- Output: EmailEvent
-- Vertex: Composite AlertVertex EmailVertex
-- Regs:   Append AlertRegs EmailRegs
pipeline
  :: SymTransducer
       (HsPred (Append AlertRegs EmailRegs) AlertCmd)
       (Append AlertRegs EmailRegs)
       (Composite AlertVertex EmailVertex)
       AlertCmd
       EmailEvent
pipeline = compose alertSource emailDelivery


-- * Test fixtures ---------------------------------------------------------

sampleAt :: UTCTime
sampleAt = UTCTime (fromGregorian 2026 5 2) (secondsToDiffTime 36000)


sampleTrigger :: AlertCmd
sampleTrigger = TriggerAlert (TriggerAlertData
  { recipient = "alice@example.com"
  , subject   = "Hello"
  , at        = sampleAt
  })


sampleEmailEvent :: EmailEvent
sampleEmailEvent = EmailSent (EmailSentData
  { recipient = "alice@example.com"
  , subject   = "Hello"
  , at        = sampleAt
  })


-- * Specs -----------------------------------------------------------------

spec :: Spec
spec = do
  describe "compose alertSource emailDelivery" $ do

    describe "step (one external command in, one wire event out)" $ do
      it "produces EmailSent on TriggerAlert" $
        case step pipeline (initial pipeline, initialRegs pipeline) sampleTrigger of
          Just (Composite av ev, _, [co]) -> do
            av `shouldBe` AlertEmitted
            ev `shouldBe` EmailSentVertex
            co `shouldBe` sampleEmailEvent
          other ->
            expectationFailure ("expected Just (Composite AlertEmitted EmailSentVertex, _, Just EmailSent ...), got "
                                  <> showStep other)

      it "rejects TriggerAlert at the terminal composite vertex" $
        let terminalState = Composite AlertEmitted EmailSentVertex
        in case step pipeline (terminalState, initialRegs pipeline) sampleTrigger of
             Nothing -> pure ()
             other   -> expectationFailure ("expected Nothing, got " <> showStep other)

    describe "checkHiddenInputs" $ do
      it "reports no warnings on the composite" $
        checkHiddenInputs pipeline `shouldBe` []

    describe "isSingleValuedSym (symbolic)" $ do
      it "the composite is single-valued" $
        isSingleValuedSym (withSymPred pipeline) `shouldBe` True

    describe "reconstitute (multi-aggregate event log replay)" $ do
      it "lands at the expected final composite state" $
        case reconstitute pipeline [sampleEmailEvent] of
          Just (Composite av ev, _) -> do
            av `shouldBe` AlertEmitted
            ev `shouldBe` EmailSentVertex
          Nothing ->
            expectationFailure "reconstitute returned Nothing for the canonical event log"

    describe "omega (the wire event for one external command)" $ do
      it "produces sampleEmailEvent on TriggerAlert from initial state" $
        omega pipeline (initial pipeline) (initialRegs pipeline) sampleTrigger
          `shouldBe` [sampleEmailEvent]
  where
    showStep :: Maybe (Composite AlertVertex EmailVertex, x, [EmailEvent]) -> String
    showStep Nothing                = "Nothing"
    showStep (Just (Composite a b, _, cos_)) =
      "Just (Composite " <> show a <> " " <> show b <> ", _, " <> show cos_ <> ")"


