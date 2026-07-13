{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE QualifiedDo #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Acceptance tests for 'Keiki.Composition.alternative' under EP-25
-- of MasterPlan 8. The fixture composes 'Keiki.Fixtures.EmailDelivery'
-- with a small inline 'Pinger' aggregate via 'alternative':
--
--    Either EmailCmd PingCmd  →  Either EmailEvent PingEvent
--
-- The two aggregates have disjoint slot-name domains
-- (EmailDelivery: @emailRecipient@, @emailSubject@, @emailSentAt@;
-- Pinger: @pingNonce@), so the @Disjoint (Names rs1) (Names rs2)@
-- constraint on 'alternative' resolves automatically.
--
-- The composite vertex is 'Composite' EmailVertex PingVertex
-- (product, not sum): each input updates exactly one sub-aggregate
-- and leaves the other's state unchanged. See EP-25's Surprises &
-- Discoveries entry dated 2026-05-03 for the design discovery that
-- led to this shape.
module Keiki.CompositionAlternativeSpec
  ( spec,
    -- Re-exported for "Keiki.Render.MermaidSpec" (EP-33 M6). Following
    -- the test-fixture-re-export pattern EP-31's M4 established (see
    -- @docs/plans/33-shape-aware-mermaid-renderers-for-alternative-and-feedback1-composites.md@'s
    -- IP-5 reference).
    pinger,
    PingVertex (..),
    siblings,
  )
where

import Data.Text (Text)
import Data.Time (UTCTime)
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import GHC.Generics (Generic)
import Keiki.Builder qualified as B
import Keiki.Composition (Composite (..), alternative)
import Keiki.Core
import Keiki.Fixtures.EmailDelivery
import Keiki.Generics (Append, emptyRegFile)
import Keiki.Generics.TH (deriveAggregateCtors, deriveWireCtors)
import Keiki.Symbolic (isSingleValuedSym, withSymPred)
import Test.Hspec

-- * The Pinger fixture ----------------------------------------------------

-- | Single-field command payload: the nonce echoed back as the
-- event's nonce.
data PingData = PingData
  { nonce :: Text
  }
  deriving stock (Eq, Show, Generic)

data PingCmd = Ping PingData
  deriving stock (Eq, Show, Generic)

-- | Single-field event payload: same nonce, different wrapping.
data PongData = PongData
  { nonce :: Text
  }
  deriving stock (Eq, Show, Generic)

data PingEvent = Pong PongData
  deriving stock (Eq, Show, Generic)

-- | Two-vertex aggregate: idle → pinged on a 'Ping'.
data PingVertex = PingIdle | PingDone
  deriving stock (Eq, Show, Enum, Bounded)

-- | Disjoint slot name from EmailDelivery's @emailRecipient@ /
-- @emailSubject@ / @emailSentAt@ so 'alternative''s
-- @Disjoint (Names rs1) (Names rs2)@ constraint resolves.
type PingRegs =
  '[ '("pingNonce", Text)
   ]

emptyPingRegs :: RegFile PingRegs
emptyPingRegs = emptyRegFile

-- TH-derived per-constructor projections + guards. The third element
-- (the binding-suffix) is "Ping" so the bindings are @inCtorPing@,
-- @inpPing@, @isPing@.
$( deriveAggregateCtors
     ''PingCmd
     ''PingRegs
     [ ("Ping", "Ping")
     ]
 )

$( deriveWireCtors
     ''PingEvent
     [ ("Pong", "Pong")
     ]
 )

pinger ::
  SymTransducer
    (HsPred PingRegs PingCmd)
    PingRegs
    PingVertex
    PingCmd
    PingEvent
pinger =
  SymTransducer
    { edgesOut = pingerEdges,
      initial = PingIdle,
      initialRegs = emptyPingRegs,
      isFinal = \case PingDone -> True; _ -> False
    }

pingerEdges ::
  PingVertex ->
  [Edge (HsPred PingRegs PingCmd) PingRegs PingCmd PingEvent PingVertex]
pingerEdges = \case
  PingIdle ->
    [ Edge
        { guard = isPing,
          update =
            USet
              (#pingNonce :: IndexN "pingNonce" PingRegs Text)
              (inpPing #nonce),
          output =
            [ pack
                inCtorPing
                wirePong
                (OFCons (inpPing #nonce) OFNil)
            ],
          target = PingDone
        }
    ]
  PingDone -> []

-- * The composite --------------------------------------------------------

-- | The alternative composite: emailDelivery on the left arm, pinger
-- on the right arm. The composite's vertex is the product
-- 'Composite EmailVertex PingVertex' — each arm has its own state
-- that evolves independently as Left / Right inputs arrive.
--
-- Input:  Either EmailCmd PingCmd
-- Output: Either EmailEvent PingEvent
-- Vertex: Composite EmailVertex PingVertex
-- Regs:   Append EmailRegs PingRegs
siblings ::
  SymTransducer
    (HsPred (Append EmailRegs PingRegs) (Either EmailCmd PingCmd))
    (Append EmailRegs PingRegs)
    (Composite EmailVertex PingVertex)
    (Either EmailCmd PingCmd)
    (Either EmailEvent PingEvent)
siblings = alternative emailDelivery pinger

epsilonRight :: SymTransducer (HsPred '[] PingCmd) '[] Bool PingCmd PingEvent
epsilonRight =
  B.buildTransducer False RNil id do
    B.from False do
      B.onEpsilon B.do
        B.noEmit
        B.goto True

epsilonSiblings ::
  SymTransducer
    (HsPred EmailRegs (Either EmailCmd PingCmd))
    EmailRegs
    (Composite EmailVertex Bool)
    (Either EmailCmd PingCmd)
    (Either EmailEvent PingEvent)
epsilonSiblings = alternative emailDelivery epsilonRight

-- * Test fixtures --------------------------------------------------------

sampleAt :: UTCTime
sampleAt = UTCTime (fromGregorian 2026 5 3) (secondsToDiffTime 36000)

sampleSendEmail :: EmailCmd
sampleSendEmail =
  SendEmail
    ( SendEmailData
        { recipient = "alice@example.com",
          subject = "Hello",
          at = sampleAt
        }
    )

sampleEmailEvent :: EmailEvent
sampleEmailEvent =
  EmailSent
    ( EmailSentData
        { recipient = "alice@example.com",
          subject = "Hello",
          at = sampleAt
        }
    )

samplePing :: PingCmd
samplePing = Ping (PingData {nonce = "abc123"})

samplePingEvent :: PingEvent
samplePingEvent = Pong (PongData {nonce = "abc123"})

-- * Specs ----------------------------------------------------------------

spec :: Spec
spec = do
  describe "alternative emailDelivery pinger" $ do
    describe "step routing" $ do
      it "arm-restricts an onEpsilon-authored right edge on Left input" $
        case step
          epsilonSiblings
          (initial epsilonSiblings, initialRegs epsilonSiblings)
          (Left sampleSendEmail) of
          Just (Composite ev rightVertex, _, [Left co]) -> do
            ev `shouldBe` EmailSentVertex
            rightVertex `shouldBe` False
            co `shouldBe` sampleEmailEvent
          other ->
            expectationFailure
              ("expected only the Left edge to fire, got " <> showStep other)

      it "Left input advances the EmailDelivery arm and emits Left output" $
        case step
          siblings
          (initial siblings, initialRegs siblings)
          (Left sampleSendEmail) of
          Just (Composite ev pv, _, [Left co]) -> do
            ev `shouldBe` EmailSentVertex
            pv `shouldBe` PingIdle -- Pinger arm unchanged
            co `shouldBe` sampleEmailEvent
          other ->
            expectationFailure
              ( "expected Just (Composite EmailSentVertex PingIdle, _, Just (Left EmailSent ...)), got "
                  <> showStep other
              )

      it "Right input advances the Pinger arm and emits Right output" $
        case step
          siblings
          (initial siblings, initialRegs siblings)
          (Right samplePing) of
          Just (Composite ev pv, _, [Right co]) -> do
            ev `shouldBe` EmailPending -- EmailDelivery arm unchanged
            pv `shouldBe` PingDone
            co `shouldBe` samplePingEvent
          other ->
            expectationFailure
              ( "expected Just (Composite EmailPending PingDone, _, Just (Right Pong ...)), got "
                  <> showStep other
              )

      it "two-step interleave: Left then Right advances both arms independently" $
        case step
          siblings
          (initial siblings, initialRegs siblings)
          (Left sampleSendEmail) of
          Just (s1, regs1, _) ->
            case step siblings (s1, regs1) (Right samplePing) of
              Just (Composite ev pv, _, [Right co]) -> do
                ev `shouldBe` EmailSentVertex -- preserved from step 1
                pv `shouldBe` PingDone
                co `shouldBe` samplePingEvent
              other ->
                expectationFailure
                  ( "expected both arms advanced after Left+Right, got "
                      <> showStep other
                  )
          Nothing -> expectationFailure "first step (Left) returned Nothing"

    describe "checkHiddenInputs" $ do
      it "reports no warnings on the alternative composite" $
        checkHiddenInputs siblings `shouldBe` []

    describe "isSingleValuedSym (symbolic)" $ do
      it "the alternative composite is single-valued" $
        isSingleValuedSym (withSymPred siblings) `shouldBe` True

      it "keeps an alternative with a PTop right edge single-valued" $
        isSingleValuedSym (withSymPred epsilonSiblings) `shouldBe` True

    describe "reconstitute (mixed-arm event log replay)" $ do
      it "lands at Composite EmailSentVertex PingDone on a Left+Right log" $
        case reconstitute siblings [Left sampleEmailEvent, Right samplePingEvent] of
          Just (Composite ev pv, _) -> do
            ev `shouldBe` EmailSentVertex
            pv `shouldBe` PingDone
          Nothing ->
            expectationFailure
              "reconstitute returned Nothing on the canonical mixed-arm log"

      it "preserves cross-arm state across reconstitute order (Right then Left)" $
        case reconstitute siblings [Right samplePingEvent, Left sampleEmailEvent] of
          Just (Composite ev pv, _) -> do
            ev `shouldBe` EmailSentVertex
            pv `shouldBe` PingDone
          Nothing ->
            expectationFailure
              "reconstitute returned Nothing on the reordered mixed-arm log"

    describe "omega (the wire event for one external command)" $ do
      it "produces Left sampleEmailEvent on Left sampleSendEmail" $
        omega
          siblings
          (initial siblings)
          (initialRegs siblings)
          (Left sampleSendEmail)
          `shouldBe` [(Left sampleEmailEvent)]

      it "produces Right samplePingEvent on Right samplePing" $
        omega
          siblings
          (initial siblings)
          (initialRegs siblings)
          (Right samplePing)
          `shouldBe` [(Right samplePingEvent)]
  where
    showStep ::
      (Show pv) =>
      Maybe
        ( Composite EmailVertex pv,
          x,
          [Either EmailEvent PingEvent]
        ) ->
      String
    showStep Nothing = "Nothing"
    showStep (Just (cs, _, cos_)) =
      "Just (" <> show cs <> ", _, " <> show cos_ <> ")"
