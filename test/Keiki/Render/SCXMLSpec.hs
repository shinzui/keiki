-- | Tests for "Keiki.Render.SCXML", the descriptive SCXML exporter.
--
-- These specs pin the exporter's own contract (IDs, element choice,
-- event labels, error ordering, laziness). Independent parsing of the
-- generated files is done by @scripts/check-scxml.py@ over the documents
-- in "Keiki.Render.SCXMLFixtures".
module Keiki.Render.SCXMLSpec (spec) where

import Data.Text (Text)
import Data.Text qualified as T
import Keiki.Fixtures.EmailDelivery (emailDelivery)
import Keiki.Render.SCXML
import Test.Hspec

spec :: Spec
spec = do
  describe "toSCXML emailDelivery" $ do
    it "renders the exact default document" $
      toSCXML emailDelivery `shouldBe` Right emailDeliveryCanonical

    it "is deterministic" $
      toSCXML emailDelivery `shouldBe` toSCXML emailDelivery

-- | The canonical export of 'emailDelivery'. Also committed as
-- @docs/examples/email-delivery.scxml@ (compared by
-- @scripts/check-scxml.sh@).
emailDeliveryCanonical :: Text
emailDeliveryCanonical =
  T.unlines
    [ "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
      "<scxml xmlns=\"http://www.w3.org/2005/07/scxml\" version=\"1.0\" datamodel=\"null\" initial=\"s0_EmailPending\">",
      "  <!--keiki-scxml-v1 {\"kind\":\"document\",\"purpose\":\"descriptive\\u002donly\",\"edgeView\":\"forward\\u002dedges\",\"includeBehavior\":true,\"warning\":\"This document describes a keiki transducer; it is not an executable state machine. Guards, register assignments, outputs, and replay are not executed by an SCXML interpreter. Event attributes are diagram labels, not a command encoding.\",\"replayEdges\":\"Replay\\u002donly edges are recorded as comments inside their source state and are not drawn as transitions.\",\"edgeIndex\":\"edgeIndex is the 0\\u002dbased local declaration position in the source state's edge list, not a durable identifier.\",\"updateSemantics\":\"Every assignment's right\\u002dhand side reads the register values from before the edge (the edge\\u002dentry snapshot); assignments are not sequential.\"}-->",
      "  <state id=\"s0_EmailPending\">",
      "    <!--keiki-scxml-v1 {\"kind\":\"state\",\"id\":\"s0_EmailPending\",\"index\":0,\"label\":\"EmailPending\",\"accepting\":false}-->",
      "    <transition event=\"SendEmail\" target=\"s1_EmailSentVertex\">",
      "      <!--keiki-scxml-v1 {\"kind\":\"edge\",\"source\":\"s0_EmailPending\",\"target\":\"s1_EmailSentVertex\",\"edgeIndex\":0,\"mode\":\"Live\",\"displayed\":true,\"event\":\"SendEmail\",\"eventSource\":\"input\\u002dconstructor\",\"guard\":\"SendEmail\",\"update\":\"emailSentAt := SendEmail.at, emailSubject := SendEmail.subject, emailRecipient := SendEmail.recipient, (keep)\",\"assignments\":[\"emailSentAt := SendEmail.at\",\"emailSubject := SendEmail.subject\",\"emailRecipient := SendEmail.recipient\"],\"updateReads\":\"edge\\u002dentry\\u002dsnapshot\",\"outputs\":[{\"constructor\":\"EmailSent\",\"fields\":[\"SendEmail.recipient\",\"SendEmail.subject\",\"SendEmail.at\"]}]}-->",
      "    </transition>",
      "  </state>",
      "  <final id=\"s1_EmailSentVertex\">",
      "    <!--keiki-scxml-v1 {\"kind\":\"state\",\"id\":\"s1_EmailSentVertex\",\"index\":1,\"label\":\"EmailSentVertex\",\"accepting\":true}-->",
      "  </final>",
      "</scxml>"
    ]
