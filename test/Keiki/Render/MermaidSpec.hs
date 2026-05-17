-- | Regression tests for "Keiki.Render.Mermaid".
--
-- Pins the canonical Mermaid 'stateDiagram-v2' blocks produced by
-- 'toMermaid' over 'Keiki.Fixtures.UserRegistration.userReg' (EP-30),
-- 'toMermaidComposite' over the @AlertSource ⨾ EmailDelivery@
-- composite from "Keiki.CompositionSpec" (EP-31),
-- 'toMermaidCompositeNested' over the same composite (EP-32),
-- 'toMermaidAlternative' over @alternative emailDelivery pinger@
-- from "Keiki.CompositionAlternativeSpec" (EP-33),
-- 'toMermaidFeedback1' over @feedback1 toggleAgg togglePolicy@ from
-- "Keiki.CompositionFeedback1Spec" (EP-33), and 'toMermaidCompose3' /
-- 'toMermaidCompose3Nested' over the inline three-toy fixture
-- @toy3deep = toy1 \`compose\` (toy2 \`compose\` toy3)@ defined at
-- the bottom of this file (EP-35), so that any accidental formatting
-- drift surfaces in CI.
--
-- See:
--
--   * @docs/plans/30-mermaid-renderer-for-single-symtransducer-canonical-example-diagrams.md@
--     — single-transducer renderer.
--   * @docs/plans/31-mermaid-rendering-for-composite-symtransducers.md@
--     — composite renderer (flat cross-product, Shape A).
--   * @docs/plans/32-shape-b-nested-subgraph-mermaid-rendering-for-larger-composites.md@
--     — nested-subgraph renderer (Shape B).
--   * @docs/plans/33-shape-aware-mermaid-renderers-for-alternative-and-feedback1-composites.md@
--     — shape-aware renderers for `alternative` (parallel arms) and
--     `feedback1` (flat 3-deep cross-product).
--   * @docs/plans/35-mermaid-renderer-for-right-associative-3-deep-compose-composites.md@
--     — right-associative 3-deep compose renderers (flat + one-level
--     nested) and the synthetic three-toy fixture.
module Keiki.Render.MermaidSpec (spec) where

import Data.Text (Text)
import qualified Data.Text as T
import Test.Hspec

import Keiki.Composition (Composite, compose)
import Keiki.CompositionAlternativeSpec (pinger)
import Keiki.CompositionFeedback1Spec (toggleAgg, togglePolicy)
import Keiki.CompositionSpec (alertSource)
import Keiki.Core
  ( Edge (..)
  , HsPred (..)
  , InCtor (..)
  , OutFields (..)
  , RegFile (..)
  , SymTransducer (..)
  , Update (..)
  , WireCtor (..)
  , pack
  )
import Keiki.Fixtures.EmailDelivery (emailDelivery)
import Keiki.Fixtures.UserRegistration (userReg)
import Keiki.Render.Mermaid
  ( toMermaid
  , toMermaidAlternative
  , toMermaidCompose3
  , toMermaidCompose3Nested
  , toMermaidComposite
  , toMermaidCompositeNested
  , toMermaidFeedback1
  )


spec :: Spec
spec = do
  describe "toMermaid (single SymTransducer)" $
    it "renders userReg to the canonical stateDiagram-v2 block" $
      toMermaid userReg `shouldBe` userRegCanonical

  describe "toMermaidComposite (composite SymTransducer)" $
    it "renders the AlertSource ⨾ EmailDelivery pipeline" $
      toMermaidComposite (compose alertSource emailDelivery)
        `shouldBe` alertEmailCompositeCanonical

  describe "toMermaidCompositeNested (composite SymTransducer)" $
    it "renders the AlertSource ⨾ EmailDelivery pipeline in nested form" $
      toMermaidCompositeNested (compose alertSource emailDelivery)
        `shouldBe` alertEmailCompositeNestedCanonical

  describe "toMermaidAlternative (alternative composite)" $
    it "renders alternative emailDelivery pinger as parallel arms" $
      toMermaidAlternative emailDelivery pinger
        `shouldBe` emailPingerAltCanonical

  describe "toMermaidFeedback1 (feedback1 composite)" $
    it "renders feedback1 toggleAgg togglePolicy as flat 3-deep cross-product" $
      toMermaidFeedback1 toggleAgg togglePolicy
        `shouldBe` toggleFeedback1Canonical

  describe "toMermaidCompose3 (right-associative 3-deep compose)" $
    it "renders the toy1 ⨾ (toy2 ⨾ toy3) flat block" $
      toMermaidCompose3 toy3deep `shouldBe` toy3deepFlatCanonical

  describe "toMermaidCompose3Nested (right-associative 3-deep compose)" $
    it "renders the toy1 ⨾ (toy2 ⨾ toy3) one-level nested block" $
      toMermaidCompose3Nested toy3deep `shouldBe` toy3deepNestedCanonical


-- | The canonical Mermaid block for @userReg@, mirrored verbatim from
-- the aggregate's diagram in @docs/guide/diagrams/user-registration.md@.
-- Stored inline (not in an external fixture file) so a formatting change
-- requires touching this file alongside the producer change.
userRegCanonical :: Text
userRegCanonical = unlinesNoTrail
  -- EP-19 M7: the entrance is now a single length-2 multi-event edge;
  -- the renderer's length-based switchover formats it with a "; "
  -- separator (per the design note's Mermaid section).
  [ "stateDiagram-v2"
  , "    [*] --> PotentialCustomer"
  , "    PotentialCustomer --> RequiresConfirmation : StartRegistration / RegistrationStarted; ConfirmationEmailSent"
  , "    RequiresConfirmation --> Confirmed : ConfirmAccount / AccountConfirmed"
  , "    RequiresConfirmation --> RequiresConfirmation : ResendConfirmation / ConfirmationResent"
  , "    RequiresConfirmation --> Deleted : FulfillGDPRRequest / \x03B5"
  , "    Confirmed --> Deleted : FulfillGDPRRequest / AccountDeleted"
  , "    Deleted --> [*]"
  ]
  where
    unlinesNoTrail = T.intercalate (T.pack "\n")


-- | The canonical Mermaid block for the @AlertSource ⨾ EmailDelivery@
-- composite, mirrored verbatim from the diagram in
-- @docs/guide/diagrams/composite-alert-email.md@. Three lines: the
-- initial-state marker pointing at @Composite AlertQuiescent
-- EmailPending@, the single cross-product edge that advances both
-- component vertices in one step, and the final-state marker for the
-- terminal composite vertex. The other two reachable composite
-- vertices have no outgoing edges and are not final, so the renderer
-- omits them (same convention as 'toMermaid').
alertEmailCompositeCanonical :: Text
alertEmailCompositeCanonical = T.intercalate (T.pack "\n")
  [ "stateDiagram-v2"
  , "    [*] --> AlertQuiescent_EmailPending"
  , "    AlertQuiescent_EmailPending --> AlertEmitted_EmailSentVertex : TriggerAlert / EmailSent"
  , "    AlertEmitted_EmailSentVertex --> [*]"
  ]


-- | The canonical Mermaid block for the same composite under
-- 'toMermaidCompositeNested' (Shape B). Differences from
-- 'alertEmailCompositeCanonical': the body adds two
-- @state AlertQuiescent { … } / state AlertEmitted { … }@ blocks
-- (between the initial-state line and the edge line) listing every
-- composite vertex grouped under its outer @s1@ parent. The
-- cross-cutting transition and the final-state line are emitted at
-- the top level using the same flat
-- @\<show s1\>_\<show s2\>@ identifiers; no Mermaid
-- @Outer.Inner@ dotted syntax is used. See
-- @docs/guide/diagrams/composite-alert-email-nested.md@.
alertEmailCompositeNestedCanonical :: Text
alertEmailCompositeNestedCanonical = T.intercalate (T.pack "\n")
  [ "stateDiagram-v2"
  , "    [*] --> AlertQuiescent_EmailPending"
  , "    state AlertQuiescent {"
  , "        AlertQuiescent_EmailPending"
  , "        AlertQuiescent_EmailSentVertex"
  , "    }"
  , "    state AlertEmitted {"
  , "        AlertEmitted_EmailPending"
  , "        AlertEmitted_EmailSentVertex"
  , "    }"
  , "    AlertQuiescent_EmailPending --> AlertEmitted_EmailSentVertex : TriggerAlert / EmailSent"
  , "    AlertEmitted_EmailSentVertex --> [*]"
  ]


-- | The canonical Mermaid block for @toMermaidAlternative
-- emailDelivery pinger@. Two top-level @[*] -->@ initial markers,
-- one for each arm; two named @state … { … }@ blocks holding each
-- arm's edges; two top-level @--> [*]@ final markers. Mirrors the
-- diagram in
-- @docs/guide/diagrams/composite-email-pinger-alternative.md@.
emailPingerAltCanonical :: Text
emailPingerAltCanonical = T.intercalate (T.pack "\n")
  [ "stateDiagram-v2"
  , "    [*] --> EmailPending"
  , "    [*] --> PingIdle"
  , "    state LeftArm {"
  , "        EmailPending --> EmailSentVertex : SendEmail / EmailSent"
  , "    }"
  , "    state RightArm {"
  , "        PingIdle --> PingDone : Ping / Pong"
  , "    }"
  , "    EmailSentVertex --> [*]"
  , "    PingDone --> [*]"
  ]


-- | The canonical Mermaid block for @toMermaidFeedback1 toggleAgg
-- togglePolicy@. Flat 3-deep cross-product labels
-- @\<outer\>_\<policy\>_\<inner\>@. All four composite vertices
-- appear because the cascade fires at every enumerated vertex
-- (the policy + inner-toggle synchronisation is independent of
-- which vertex the outer toggle currently occupies), and both
-- 'toggleAgg' and 'togglePolicy' use @isFinal = const True@ so
-- every composite vertex is final. Two of the four (the
-- @Off_Pol_On@ / @On_Pol_Off@ pair) are unreachable from the
-- initial vertex; the renderer surfaces them anyway because the
-- enumeration walks the static cross-product. See the diagram in
-- @docs/guide/diagrams/composite-toggle-feedback1.md@ and the
-- Decision Log entry of 2026-05-03 in
-- @docs/plans/33-shape-aware-mermaid-renderers-for-alternative-and-feedback1-composites.md@.
toggleFeedback1Canonical :: Text
toggleFeedback1Canonical = T.intercalate (T.pack "\n")
  [ "stateDiagram-v2"
  , "    [*] --> Off_Pol_Off"
  , "    Off_Pol_Off --> On_Pol_On : TgFlip / TgFlipped"
  , "    Off_Pol_On --> On_Pol_Off : TgFlip / TgFlipped"
  , "    On_Pol_Off --> Off_Pol_On : TgFlip / TgFlipped"
  , "    On_Pol_On --> Off_Pol_Off : TgFlip / TgFlipped"
  , "    Off_Pol_Off --> [*]"
  , "    Off_Pol_On --> [*]"
  , "    On_Pol_Off --> [*]"
  , "    On_Pol_On --> [*]"
  ]


-- * Synthetic 3-deep compose fixture (EP-35 M1 / M2) -------------------

-- | A minimal shared command/event type for the three toy aggregates.
-- Single nullary constructor so each toy's edge needs only a trivial
-- guard ('PInCtor' on 'inCtorTick') and a trivial output ('pack' over
-- the same constructor on both sides). The empty payload also makes
-- the 'InCtor' / 'WireCtor' values fully recoverable without any TH.
data Tick = Tick
  deriving (Eq, Show)


inCtorTick :: InCtor Tick '[]
inCtorTick = InCtor
  { icName  = "Tick"
  , icMatch = \Tick -> Just RNil
  , icBuild = \RNil -> Tick
  }


wireTick :: WireCtor Tick ()
wireTick = WireCtor
  { wcName  = "Tick"
  , wcMatch = \Tick -> Just ()
  , wcBuild = \() -> Tick
  }


data T1 = T1A | T1B
  deriving (Eq, Show, Enum, Bounded)


data T2 = T2A | T2B
  deriving (Eq, Show, Enum, Bounded)


data T3 = T3A | T3B
  deriving (Eq, Show, Enum, Bounded)


-- | Each toy advances on a single 'Tick' command from the @A@ vertex
-- to the @B@ vertex; the @B@ vertex is final and has no outgoing
-- edges. All three toys share the @Tick@ alphabet so the
-- right-associative 'compose' chain type-checks without lifters.
toy1 :: SymTransducer (HsPred '[] Tick) '[] T1 Tick Tick
toy1 = mkToy T1A T1B (\case T1A -> True; T1B -> False)
                    (\case T1B -> True; T1A -> False)


toy2 :: SymTransducer (HsPred '[] Tick) '[] T2 Tick Tick
toy2 = mkToy T2A T2B (\case T2A -> True; T2B -> False)
                    (\case T2B -> True; T2A -> False)


toy3 :: SymTransducer (HsPred '[] Tick) '[] T3 Tick Tick
toy3 = mkToy T3A T3B (\case T3A -> True; T3B -> False)
                    (\case T3B -> True; T3A -> False)


-- | Shared toy-aggregate factory: one Tick edge from the source
-- vertex to the target vertex; target is final. Parameterised on the
-- vertex predicates so each call site uses its own concrete vertex
-- type.
mkToy
  :: s -> s -> (s -> Bool) -> (s -> Bool)
  -> SymTransducer (HsPred '[] Tick) '[] s Tick Tick
mkToy src tgt isSrc isFinalAt = SymTransducer
  { edgesOut    = \s -> if isSrc s
                          then [Edge
                                 { guard  = PInCtor inCtorTick
                                 , update = UKeep
                                 , output = [ pack inCtorTick wireTick OFNil ]
                                 , target = tgt
                                 }]
                          else []
  , initial     = src
  , initialRegs = RNil
  , isFinal     = isFinalAt
  }


-- | The right-associative 3-deep compose @toy1 \`compose\` (toy2
-- \`compose\` toy3)@. Vertex type
-- @'Composite' T1 ('Composite' T2 T3)@; 2 × 2 × 2 = 8 composite
-- vertices walked by the renderer's @[minBound .. maxBound]@.
toy3deep
  :: SymTransducer (HsPred '[] Tick) '[]
       (Composite T1 (Composite T2 T3))
       Tick Tick
toy3deep = toy1 `compose` (toy2 `compose` toy3)


-- | Canonical Mermaid block for @toMermaidCompose3 toy3deep@.
-- Generated by running the renderer at the REPL and pasted verbatim;
-- regenerate via the recipe in
-- @docs/plans/35-mermaid-renderer-for-right-associative-3-deep-compose-composites.md@'s
-- Concrete Steps section if 'toMermaidCompose3' or 'compose'
-- semantics ever change.
toy3deepFlatCanonical :: Text
toy3deepFlatCanonical = T.intercalate (T.pack "\n")
  [ "stateDiagram-v2"
  , "    [*] --> T1A_T2A_T3A"
  , "    T1A_T2A_T3A --> T1B_T2B_T3B : Tick / Tick"
  , "    T1B_T2B_T3B --> [*]"
  ]


-- | Canonical Mermaid block for @toMermaidCompose3Nested toy3deep@.
-- Same fixture as the flat variant; differs in the per-outer
-- @state … { … }@ wrapping. Outer @T1@ vertices each list four
-- @T1?_T2?_T3?@ inner identifiers (the @T2@ × @T3@ cross-product
-- enumerated within @Composite T2 T3@'s 'Bounded' / 'Enum'
-- instances). Edges and finals remain at the top level using flat
-- identifiers.
toy3deepNestedCanonical :: Text
toy3deepNestedCanonical = T.intercalate (T.pack "\n")
  [ "stateDiagram-v2"
  , "    [*] --> T1A_T2A_T3A"
  , "    state T1A {"
  , "        T1A_T2A_T3A"
  , "        T1A_T2A_T3B"
  , "        T1A_T2B_T3A"
  , "        T1A_T2B_T3B"
  , "    }"
  , "    state T1B {"
  , "        T1B_T2A_T3A"
  , "        T1B_T2A_T3B"
  , "        T1B_T2B_T3A"
  , "        T1B_T2B_T3B"
  , "    }"
  , "    T1A_T2A_T3A --> T1B_T2B_T3B : Tick / Tick"
  , "    T1B_T2B_T3B --> [*]"
  ]
