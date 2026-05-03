-- | Regression tests for "Keiki.Render.Mermaid".
--
-- Pins the canonical Mermaid 'stateDiagram-v2' blocks produced by
-- 'toMermaid' over 'Keiki.Examples.UserRegistration.userReg' (EP-30),
-- 'toMermaidComposite' over the @AlertSource ⨾ EmailDelivery@
-- composite from "Keiki.CompositionSpec" (EP-31),
-- 'toMermaidCompositeNested' over the same composite (EP-32),
-- 'toMermaidAlternative' over @alternative emailDelivery pinger@
-- from "Keiki.CompositionAlternativeSpec" (EP-33), and
-- 'toMermaidFeedback1' over @feedback1 toggleAgg togglePolicy@ from
-- "Keiki.CompositionFeedback1Spec" (EP-33), so that any accidental
-- formatting drift surfaces in CI.
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
module Keiki.Render.MermaidSpec (spec) where

import Data.Text (Text)
import qualified Data.Text as T
import Test.Hspec

import Keiki.Composition (compose)
import Keiki.CompositionAlternativeSpec (pinger)
import Keiki.CompositionFeedback1Spec (toggleAgg, togglePolicy)
import Keiki.CompositionSpec (alertSource)
import Keiki.Examples.EmailDelivery (emailDelivery)
import Keiki.Examples.UserRegistration (userReg)
import Keiki.Render.Mermaid
  ( toMermaid
  , toMermaidAlternative
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


-- | The canonical Mermaid block for @userReg@, mirrored verbatim from
-- the aggregate's diagram in @docs/guide/diagrams/user-registration.md@.
-- Stored inline (not in an external fixture file) so a formatting change
-- requires touching this file alongside the producer change.
userRegCanonical :: Text
userRegCanonical = unlinesNoTrail
  [ "stateDiagram-v2"
  , "    [*] --> PotentialCustomer"
  , "    PotentialCustomer --> Registering : StartRegistration / RegistrationStarted"
  , "    Registering --> RequiresConfirmation : Continue / ConfirmationEmailSent"
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
