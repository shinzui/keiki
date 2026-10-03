-- | Tests for "Keiki.Render.SCXML", the descriptive SCXML exporter.
--
-- These specs pin the exporter's own contract (IDs, element choice,
-- event labels, edge views, error ordering, laziness). Independent
-- parsing and metadata decoding of the generated files is done by
-- @scripts/check-scxml.py@ over the documents in
-- "Keiki.Render.SCXMLFixtures".
module Keiki.Render.SCXMLSpec (spec) where

import Control.Exception (evaluate)
import Data.Char (ord)
import Data.Text (Text)
import Data.Text qualified as T
import Keiki.Core
  ( Edge (..),
    EdgeMode (..),
    HsPred (..),
    RegFile (..),
    SymTransducer (..),
    Update (..),
  )
import Keiki.Fixtures.EmailDelivery (emailDelivery)
import Keiki.Render.SCXML
import Keiki.Render.SCXMLFixtures
import Test.Hspec

spec :: Spec
spec = do
  describe "toSCXML emailDelivery" $ do
    it "renders the exact default document" $
      toSCXML emailDelivery `shouldBe` Right emailDeliveryCanonical

    it "is deterministic" $
      toSCXML emailDelivery `shouldBe` toSCXML emailDelivery

    it "does not read the initial register file" $ do
      let bottomRegs = emailDelivery {initialRegs = error "initialRegs was forced"}
      toSCXML bottomRegs `shouldBe` toSCXML emailDelivery
      toSCXMLWith structural bottomRegs
        `shouldBe` toSCXMLWith structural emailDelivery

  describe "structural view (includeBehavior = False)" $ do
    it "keeps graph, labels, and acceptance but omits behavior" $ do
      doc <- expectRight (toSCXMLWith structural emailDelivery)
      transitions doc `shouldBe` [("SendEmail", "s1_EmailSentVertex")]
      doc `shouldSatisfy` T.isInfixOf "\"includeBehavior\":false"
      doc `shouldSatisfy` T.isInfixOf "<final id=\"s1_EmailSentVertex\">"
      mapM_
        (\key -> doc `shouldNotSatisfy` T.isInfixOf key)
        ["\"guard\"", "\"update\"", "\"assignments\"", "\"outputs\"", "\"updateReads\""]

    it "never forces a literal's Show instance or an opaque function" $ do
      doc <- expectRight (toSCXMLWith structural unshowableLiterals)
      len <- evaluate (T.length doc)
      len `shouldSatisfy` (> 0)
      transitions doc `shouldBe` [("UGo", "s1_UEnd")]

    it "readable view surfaces a partial literal Show (ADR-6 limitation)" $
      evaluate (either (const 0) T.length (toSCXML unshowableLiterals))
        `shouldThrow` errorCall "literal Show instance was forced"

  describe "edge cases" $ do
    it "labels only sole, safe input constructors and never runs opaque terms" $ do
      doc <- expectRight (toSCXML edgeCases)
      transitions doc
        `shouldBe` [ ("keiki_edge_s0_e0", "s1_EcAccepting"),
                     ("keiki_edge_s0_e1", "s2_EcDone"),
                     ("keiki_edge_s0_e2", "s0_EcStart"),
                     ("keiki_edge_s0_e3", "s2_EcDone"),
                     ("keiki_edge_s0_e4", "s2_EcDone"),
                     ("keiki_edge_s0_e5", "s2_EcDone"),
                     ("Go", "s2_EcDone"),
                     ("Ping", "s1_EcAccepting")
                   ]

    it "uses <final> only for accepting states with no displayed edges" $ do
      doc <- expectRight (toSCXML edgeCases)
      elements doc
        `shouldBe` [ ("state", "s0_EcStart"),
                     ("state", "s1_EcAccepting"),
                     ("final", "s2_EcDone"),
                     ("state", "s3_EcIsolated")
                   ]

    it "keeps opaque markers and multi-output order" $ do
      doc <- expectRight (toSCXML edgeCases)
      doc `shouldSatisfy` T.isInfixOf "\"note := <fn>(note)\""
      doc `shouldSatisfy` T.isInfixOf "{\"constructor\":\"A\",\"fields\":[\"<lit>\"]}"
      doc
        `shouldSatisfy` T.isInfixOf
          "[{\"constructor\":\"A\",\"fields\":[\"count\"]},{\"constructor\":\"B\",\"fields\":[]},{\"constructor\":\"C\",\"fields\":[]}]"
      doc `shouldSatisfy` T.isInfixOf "\"outputs\":[]"

  describe "edge views" $ do
    it "forward view draws live edges and records replay-only edges as comments" $ do
      doc <- expectRight (toSCXML replayEdges)
      transitions doc `shouldBe` [("Close", "s1_RpShut")]
      elements doc `shouldBe` [("state", "s0_RpOpen"), ("final", "s1_RpShut")]
      T.count "\"mode\":\"ReplayOnly\",\"displayed\":false" doc `shouldBe` 2

    it "all-edges view adds exactly the replay-only arrows with reserved labels" $ do
      doc <- expectRight (toSCXMLWith allEdges replayEdges)
      transitions doc
        `shouldBe` [ ("Close", "s1_RpShut"),
                     ("keiki_replay_s0_e1", "s0_RpOpen"),
                     ("keiki_replay_s1_e0", "s0_RpOpen")
                   ]
      elements doc `shouldBe` [("state", "s0_RpOpen"), ("state", "s1_RpShut")]
      T.count "\"displayed\":false" doc `shouldBe` 0

  describe "hostile names" $ do
    it "gives colliding names distinct IDs" $ do
      doc <- expectRight (toSCXML hostileNames)
      map snd (elements doc)
        `shouldBe` [ "s0_Same_Name",
                     "s1_Same_Name",
                     "s2_Same_Name",
                     "s3_" <> T.map sanitize (T.pack hostileText)
                   ]

    it "keeps comment content free of -- and XML-forbidden characters" $ do
      doc <- expectRight (toSCXML hostileNames)
      mapM_
        (\c -> c `shouldNotSatisfy` T.isInfixOf "--")
        (comments doc)
      T.filter forbiddenOrEscaped doc `shouldBe` T.empty

  describe "malformed enumerations" $ do
    it "rejects an empty enumeration before checking the initial state" $
      toSCXML emptyEnumeration `shouldBe` Left EmptyStateEnumeration

    it "rejects an unenumerated initial state before checking targets" $
      toSCXML missingInitial `shouldBe` Left InitialStateNotEnumerated

    it "rejects an unenumerated target, including omitted replay-only edges" $ do
      let err = Left TargetStateNotEnumerated {sourceStateId = "s0_NarrowA", edgeIndex = 1}
      toSCXML missingTarget `shouldBe` err
      toSCXMLWith allEdges missingTarget `shouldBe` err
      toSCXMLWith structural missingTarget `shouldBe` err

structural :: ScxmlOptions
structural = defaultScxmlOptions {includeBehavior = False}

allEdges :: ScxmlOptions
allEdges = defaultScxmlOptions {edgeView = AllDeclaredEdges}

expectRight :: (Show e) => Either e a -> IO a
expectRight = either (\e -> expectationFailure (show e) >> error "unreachable") pure

-- | @(event, target)@ of every @\<transition\>@ line, in document order.
transitions :: Text -> [(Text, Text)]
transitions doc =
  [ (attr "event" l, attr "target" l)
  | l <- map T.strip (T.lines doc),
    "<transition " `T.isPrefixOf` l
  ]

-- | @(element, id)@ of every state-level element, in document order.
elements :: Text -> [(Text, Text)]
elements doc =
  [ (T.takeWhile (/= ' ') (T.drop 1 l), attr "id" l)
  | l <- map T.strip (T.lines doc),
    "<state " `T.isPrefixOf` l || "<final " `T.isPrefixOf` l
  ]

attr :: Text -> Text -> Text
attr name l =
  T.takeWhile (/= '"') (snd (T.breakOnEnd (name <> "=\"") l))

-- | The content of every @\<!--…--\>@ comment.
comments :: Text -> [Text]
comments doc =
  [ fst (T.breakOn "-->" chunk)
  | chunk <- drop 1 (T.splitOn "<!--" doc)
  ]

-- | Characters that must never appear raw in the document.
forbiddenOrEscaped :: Char -> Bool
forbiddenOrEscaped c =
  let n = ord c
   in (n < 0x20 && c /= '\n')
        || (n >= 0x7F && n <= 0x9F)
        || (n >= 0xFDD0 && n <= 0xFDEF)
        || n `mod` 0x10000 >= 0xFFFE

-- | The documented ID sanitization: ASCII letters, digits, and underscore
-- are kept; every other character becomes an underscore.
sanitize :: Char -> Char
sanitize c
  | c `elem` (['A' .. 'Z'] ++ ['a' .. 'z'] ++ ['0' .. '9'] ++ "_") = c
  | otherwise = '_'

-- * Malformed enumerations ---------------------------------------------------

-- | A type whose @[minBound .. maxBound]@ is empty: 'minBound' is above
-- 'maxBound'.
data Inverted = InvertedA | InvertedB
  deriving (Eq, Show)

instance Enum Inverted where
  fromEnum InvertedA = 0
  fromEnum InvertedB = 1
  toEnum 0 = InvertedA
  toEnum _ = InvertedB

instance Bounded Inverted where
  minBound = InvertedB
  maxBound = InvertedA

-- | A type whose bounds enumerate only 'NarrowA'.
data Narrow = NarrowA | NarrowB
  deriving (Eq, Show, Enum)

instance Bounded Narrow where
  minBound = NarrowA
  maxBound = NarrowA

loop :: s -> EdgeMode -> Edge (HsPred '[] ()) '[] () () s
loop tgt m = Edge {guard = PTop, update = UKeep, output = [], target = tgt, mode = m}

emptyEnumeration :: SymTransducer (HsPred '[] ()) '[] Inverted () ()
emptyEnumeration =
  SymTransducer
    { edgesOut = const [],
      initial = InvertedA,
      initialRegs = RNil,
      isFinal = const False
    }

missingInitial :: SymTransducer (HsPred '[] ()) '[] Narrow () ()
missingInitial =
  SymTransducer
    { edgesOut = const [loop NarrowB Live],
      initial = NarrowB,
      initialRegs = RNil,
      isFinal = const False
    }

missingTarget :: SymTransducer (HsPred '[] ()) '[] Narrow () ()
missingTarget =
  SymTransducer
    { edgesOut = const [loop NarrowA Live, loop NarrowB ReplayOnly],
      initial = NarrowA,
      initialRegs = RNil,
      isFinal = const False
    }

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
