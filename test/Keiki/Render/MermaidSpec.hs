-- | Regression tests for "Keiki.Render.Mermaid".
--
-- Pins the canonical Mermaid 'stateDiagram-v2' blocks produced by
-- 'toMermaid' over 'Keiki.Examples.UserRegistration.userReg' (EP-30),
-- 'toMermaidComposite' over the @AlertSource ⨾ EmailDelivery@
-- composite from "Keiki.CompositionSpec" (EP-31), and
-- 'toMermaidCompositeNested' over the same composite (EP-32) so that
-- any accidental formatting drift surfaces in CI.
--
-- See:
--
--   * @docs/plans/30-mermaid-renderer-for-single-symtransducer-canonical-example-diagrams.md@
--     — single-transducer renderer.
--   * @docs/plans/31-mermaid-rendering-for-composite-symtransducers.md@
--     — composite renderer (flat cross-product, Shape A).
--   * @docs/plans/32-shape-b-nested-subgraph-mermaid-rendering-for-larger-composites.md@
--     — nested-subgraph renderer (Shape B).
module Keiki.Render.MermaidSpec (spec) where

import Data.Text (Text)
import qualified Data.Text as T
import Test.Hspec

import Keiki.Composition (compose)
import Keiki.CompositionSpec (alertSource)
import Keiki.Examples.EmailDelivery (emailDelivery)
import Keiki.Examples.UserRegistration (userReg)
import Keiki.Render.Mermaid
  ( toMermaid
  , toMermaidComposite
  , toMermaidCompositeNested
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
