{-# LANGUAGE TemplateHaskell #-}

-- | Acceptance tests for 'Keiki.Composition.feedback1' under EP-26
-- of MasterPlan 8. The fixture is a tiny aggregate ↔ policy loop:
--
--    ToggleAgg ↔ TogglePolicy
--
-- The aggregate is a two-vertex toggle (Off/On) whose only command
-- 'TgFlip' alternates the vertex and emits a 'TgFlipped' event
-- carrying the same 'tValue' the command supplied. The policy is a
-- stateless one-vertex echo: on every observed 'TgFlipped' event it
-- emits another 'TgFlip' command, forwarding the value field.
--
-- The composite is @feedback1 toggleAgg togglePolicy@. Per the
-- design record at
-- @docs/research/composition-combinators-design.md@'s "`feedback1` —
-- admitted (single-step reduction)" section, this is implemented as
-- @compose t (compose f t)@: t consumes the external command, f
-- maps the resulting event back to a follow-up command, and a
-- second copy of t consumes that follow-up.
--
-- Both halves have empty register files (@'[]@). This is required
-- by 'feedback1''s
-- @Disjoint (Names rs1) (Names (Append rs2 rs1))@ constraint —
-- only @rs1 = '[]@ satisfies it (see EP-26's Decision Log entry
-- dated 2026-05-03). The aggregate's state lives entirely in the
-- vertex.
--
-- The cascade is observable from the composite vertex: after one
-- external command from the initial vertex
-- @Composite Off (Composite Pol Off)@, the composite advances to
-- @Composite On (Composite Pol On)@ — both the outer and the inner
-- copies of t have transitioned, proving the policy's emitted
-- command was consumed by the second t. The output's 'tValue' is
-- the original input's 'tValue', forwarded through the cascade by
-- structural substitution.
module Keiki.CompositionFeedback1Spec
  ( spec,
    -- Re-exported for "Keiki.Render.MermaidSpec" (EP-33 M6). See
    -- @docs/plans/33-shape-aware-mermaid-renderers-for-alternative-and-feedback1-composites.md@'s
    -- IP-5 reference.
    toggleAgg,
    togglePolicy,
    ToggleVertex (..),
    PolicyVertex (..),
    loop,
  )
where

import GHC.Generics (Generic)
import Keiki.Composition (Composite (..), feedback1)
import Keiki.Core
import Keiki.Generics (Append, emptyRegFile)
import Keiki.Generics.TH (deriveAggregateCtors, deriveWireCtors)
import Keiki.Symbolic (isSingleValuedSym, withSymPred)
import Test.Hspec

-- * The Toggle aggregate fixture (stateless) ------------------------------

-- | Single-field payload carried by both the command and event.
-- Forwarded verbatim through every cascade hop, so the composite's
-- final 'TgFlipped' value matches the original 'TgFlip' value.
data TgPayload = TgPayload
  { tValue :: Int
  }
  deriving stock (Eq, Show, Generic)

-- | Single-constructor command type with a record payload (the
-- shape 'deriveAggregateCtors' / 'deriveWireCtors' expect).
data TgCmd = TgFlip TgPayload
  deriving stock (Eq, Show, Generic)

-- | Single-constructor event type with the same record payload.
data TgEv = TgFlipped TgPayload
  deriving stock (Eq, Show, Generic)

-- | Two-vertex toggle: each TgFlip command alternates Off ↔ On.
data ToggleVertex = Off | On
  deriving stock (Eq, Show, Enum, Bounded)

-- | Aggregate has no register slots; the toggle's state is entirely
-- in the vertex.
type ToggleRegs = '[]

-- TH-derived per-constructor projections / guards / wire ctors for
-- the aggregate side. Binding suffixes pick "Flip" / "Flipped" to
-- keep call sites readable.
$( deriveAggregateCtors
     ''TgCmd
     ''ToggleRegs
     [ ("TgFlip", "Flip")
     ]
 )

$( deriveWireCtors
     ''TgEv
     [ ("TgFlipped", "Flipped")
     ]
 )

toggleAgg ::
  SymTransducer
    (HsPred ToggleRegs TgCmd)
    ToggleRegs
    ToggleVertex
    TgCmd
    TgEv
toggleAgg =
  SymTransducer
    { edgesOut = toggleEdges,
      initial = Off,
      initialRegs = emptyRegFile,
      isFinal = const True
    }

toggleEdges ::
  ToggleVertex ->
  [Edge (HsPred ToggleRegs TgCmd) ToggleRegs TgCmd TgEv ToggleVertex]
toggleEdges = \case
  Off ->
    [ Edge
        { guard = isFlip,
          update = UKeep,
          output =
            [ pack
                inCtorFlip
                wireFlipped
                (OFCons (inpFlip #tValue) OFNil)
            ],
          target = On
        }
    ]
  On ->
    [ Edge
        { guard = isFlip,
          update = UKeep,
          output =
            [ pack
                inCtorFlip
                wireFlipped
                (OFCons (inpFlip #tValue) OFNil)
            ],
          target = Off
        }
    ]

-- * The Policy fixture (stateless) ----------------------------------------

-- | Single-vertex policy: on every TgFlipped event, emit another
-- TgFlip command with the same value. This is the "stateless
-- reactor" pattern from the orchestration design note.
data PolicyVertex = Pol
  deriving stock (Eq, Show, Enum, Bounded)

type PolicyRegs = '[]

-- TH-derived guards / wire ctors for the policy side. Distinct
-- binding suffixes ("PFlipped", "PFlip") avoid clashing with the
-- aggregate-side bindings above. The underlying constructor names
-- ("TgFlipped", "TgFlip") still match across the aggregate ↔ policy
-- boundary, so 'compose''s structural-name substitution wires the
-- cascade correctly.
$( deriveAggregateCtors
     ''TgEv
     ''PolicyRegs
     [ ("TgFlipped", "PFlipped")
     ]
 )

$( deriveWireCtors
     ''TgCmd
     [ ("TgFlip", "PFlip")
     ]
 )

togglePolicy ::
  SymTransducer
    (HsPred PolicyRegs TgEv)
    PolicyRegs
    PolicyVertex
    TgEv
    TgCmd
togglePolicy =
  SymTransducer
    { edgesOut = policyEdges,
      initial = Pol,
      initialRegs = emptyRegFile,
      isFinal = const True
    }

policyEdges ::
  PolicyVertex ->
  [Edge (HsPred PolicyRegs TgEv) PolicyRegs TgEv TgCmd PolicyVertex]
policyEdges = \case
  Pol ->
    [ Edge
        { guard = isPFlipped,
          update = UKeep,
          output =
            [ pack
                inCtorPFlipped
                wirePFlip
                (OFCons (inpPFlipped #tValue) OFNil)
            ],
          target = Pol
        }
    ]

-- * The composite --------------------------------------------------------

-- | The single-step feedback composite.
--
-- Vertex: @Composite ToggleVertex (Composite PolicyVertex ToggleVertex)@.
--   Read as "outer toggle, then (policy, inner toggle)". Both
--   toggles are independent copies (the implementation
--   @compose t (compose f t)@ does not share register state across
--   the two t copies — they evolve in parallel within one composite
--   step).
-- Regs:   @Append '[] (Append '[] '[])@ ≡ '[].
-- Input:  TgCmd
-- Output: TgEv
loop ::
  SymTransducer
    (HsPred (Append ToggleRegs (Append PolicyRegs ToggleRegs)) TgCmd)
    (Append ToggleRegs (Append PolicyRegs ToggleRegs))
    (Composite ToggleVertex (Composite PolicyVertex ToggleVertex))
    TgCmd
    TgEv
loop = feedback1 toggleAgg togglePolicy

-- * Test fixtures --------------------------------------------------------

externalCmd :: TgCmd
externalCmd = TgFlip (TgPayload {tValue = 42})

cascadedEvent :: TgEv
cascadedEvent = TgFlipped (TgPayload {tValue = 42})

-- * Specs ---------------------------------------------------------------

spec :: Spec
spec = do
  describe "feedback1 toggleAgg togglePolicy" $ do
    describe "single-step cascade" $ do
      it "Composite Off (Composite Pol Off) -- TgFlip{42} --> Composite On (Composite Pol On), emitting TgFlipped{42}" $
        case step loop (initial loop, initialRegs loop) externalCmd of
          Just (Composite outerT (Composite policy innerT), _, [co]) -> do
            outerT `shouldBe` On -- outer toggle stepped Off → On
            policy `shouldBe` Pol -- policy self-loops
            innerT `shouldBe` On -- inner toggle stepped Off → On (proves cascade ran)
            co `shouldBe` cascadedEvent
          other ->
            expectationFailure
              ( "expected Just (Composite On (Composite Pol On), _, [TgFlipped{42}]), got "
                  <> showStep other
              )

      it "two consecutive composite steps return to the initial vertex" $
        case step loop (initial loop, initialRegs loop) externalCmd of
          Just (s1, regs1, _) ->
            case step loop (s1, regs1) externalCmd of
              Just (Composite outerT (Composite policy innerT), _, [co]) -> do
                outerT `shouldBe` Off -- back to initial
                policy `shouldBe` Pol
                innerT `shouldBe` Off
                co `shouldBe` cascadedEvent
              other ->
                expectationFailure
                  ( "expected Composite Off (Composite Pol Off) after 2 steps, got "
                      <> showStep other
                  )
          Nothing -> expectationFailure "first step returned Nothing"

    describe "round-trip replay" $ do
      it "reconstitute on [cascadedEvent] lands at Composite On (Composite Pol On)" $
        case reconstitute loop [cascadedEvent] of
          Just (Composite outerT (Composite policy innerT), _) -> do
            outerT `shouldBe` On
            policy `shouldBe` Pol
            innerT `shouldBe` On
          Nothing ->
            expectationFailure
              "reconstitute returned Nothing for the canonical one-event log"

      it "reconstitute on [cascadedEvent, cascadedEvent] returns to the initial vertex" $
        case reconstitute loop [cascadedEvent, cascadedEvent] of
          Just (Composite outerT (Composite policy innerT), _) -> do
            outerT `shouldBe` Off
            policy `shouldBe` Pol
            innerT `shouldBe` Off
          Nothing ->
            expectationFailure
              "reconstitute returned Nothing for the two-event log"

    describe "checkHiddenInputs" $ do
      it "reports no warnings on the feedback1 composite" $
        checkHiddenInputs loop `shouldBe` []

    describe "isSingleValuedSym (symbolic)" $ do
      it "the feedback1 composite is single-valued" $
        isSingleValuedSym (withSymPred loop) `shouldBe` True

    describe "omega (the wire event for one external command)" $ do
      it "produces cascadedEvent on externalCmd from the initial composite state" $
        omega loop (initial loop) (initialRegs loop) externalCmd
          `shouldBe` [cascadedEvent]
  where
    showStep ::
      Maybe
        ( Composite ToggleVertex (Composite PolicyVertex ToggleVertex),
          x,
          [TgEv]
        ) ->
      String
    showStep Nothing = "Nothing"
    showStep (Just (cs, _, cos_)) =
      "Just (" <> show cs <> ", _, " <> show cos_ <> ")"
