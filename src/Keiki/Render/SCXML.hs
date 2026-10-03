{-# OPTIONS_GHC -Wno-partial-fields #-}

-- | Descriptive State Chart XML (SCXML) export for 'SymTransducer' values
-- whose control-state type is finitely enumerable.
--
-- 'toSCXML' renders a flat state chart: one @\<state\>@ or @\<final\>@ per
-- enumerated control state and one event-labelled @\<transition\>@ per
-- displayed edge. Guards, register assignments, and emitted events are
-- retained as readable descriptions inside XML comments of the form
-- @\<!--keiki-scxml-v1 {…}--\>@, each holding one JSON object with a
-- @kind@ discriminator.
--
-- __This is a descriptive export, not an executable program.__ The
-- document uses @datamodel="null"@ and carries no @cond@, @\<assign\>@,
-- or @\<send\>@: loading it into an SCXML interpreter does not reproduce
-- keiki's command rejection, guard evaluation, register updates, event
-- emission, or replay. Every @event@ attribute is a diagram label, not a
-- command encoding. Generic viewers may ignore or drop the comments.
--
-- The exporter is pure. It never reads 'initialRegs', never applies a
-- stored function inside a term, and in structural mode
-- (@'includeBehavior' = False@) never calls the pretty-printers or any
-- literal's 'Show' instance. In the default readable mode, ordinary
-- 'Keiki.Core.TLit' values render through their retained 'Show' evidence
-- (ADR-6), so a partial 'Show' instance surfaces when the text is forced.
--
-- See @docs/guide/scxml-export.md@ for the document subset and the
-- comment schema.
module Keiki.Render.SCXML
  ( ScxmlEdgeView (..),
    ScxmlOptions (..),
    defaultScxmlOptions,
    ScxmlError (..),
    toSCXML,
    toSCXMLWith,
  )
where

import Data.Bits ((.&.))
import Data.Char (isAsciiLower, isAsciiUpper, isDigit, ord)
import Data.List (find)
import Data.Text (Text)
import Data.Text qualified as T
import Keiki.Core
  ( Edge (..),
    EdgeMode (..),
    HsPred (..),
    InCtor (..),
    OutFields (..),
    OutTerm (..),
    SymTransducer (..),
    Update (..),
    WireCtor (..),
  )
import Keiki.Render.Pretty (prettyPred, prettyTerm, prettyUpdate)
import Numeric (showHex)

-- | Which declared edges become drawn @\<transition\>@ arrows.
--
--   * 'ForwardEdges' (the default) draws only 'Live' edges. 'ReplayOnly'
--     edges are kept as non-transition comment records inside their
--     source state, so the forward graph is not altered.
--   * 'AllDeclaredEdges' draws both modes. Replay-only arrows carry the
--     reserved label @keiki_replay_sN_eM@; they are historical inversion
--     paths for interpreting past events, not forward command transitions.
data ScxmlEdgeView = ForwardEdges | AllDeclaredEdges
  deriving stock (Eq, Show)

-- | Export options.
data ScxmlOptions = ScxmlOptions
  { -- | Which edges are drawn; see 'ScxmlEdgeView'.
    edgeView :: ScxmlEdgeView,
    -- | 'True' (the default) records the pretty guard, register
    --     assignments, and output descriptions of every edge. 'False' is
    --     an explicit structural view: names, references, acceptance,
    --     edge mode and index, and event labels only.
    includeBehavior :: Bool
  }
  deriving stock (Eq, Show)

-- | @'ScxmlOptions' 'ForwardEdges' 'True'@: the forward graph with
-- readable behavior.
defaultScxmlOptions :: ScxmlOptions
defaultScxmlOptions =
  ScxmlOptions
    { edgeView = ForwardEdges,
      includeBehavior = True
    }

-- | Why a transducer could not be exported. The exporter checks, in
-- order: an empty enumeration, then membership of the initial state,
-- then every edge target (including replay-only edges that are not
-- drawn) in state-enumeration and edge-declaration order. No partial
-- document is ever produced.
data ScxmlError
  = -- | @[minBound .. maxBound]@ is empty.
    EmptyStateEnumeration
  | -- | 'initial' is not equal to any enumerated state.
    InitialStateNotEnumerated
  | -- | An edge's target is not equal to any enumerated state.
    TargetStateNotEnumerated
      { -- | The generated ID of the edge's source state.
        sourceStateId :: Text,
        -- | The edge's 0-based position in @edgesOut t source@ — a local
        --     declaration position, not a durable identifier.
        edgeIndex :: Int
      }
  deriving stock (Eq, Show)

-- | Export with 'defaultScxmlOptions'.
toSCXML ::
  (Eq s, Enum s, Bounded s, Show s) =>
  SymTransducer (HsPred rs ci) rs s ci co ->
  Either ScxmlError Text
toSCXML = toSCXMLWith defaultScxmlOptions

-- | Export a transducer as a descriptive SCXML 1.0 document (UTF-8 XML
-- text with a trailing newline). The result is deterministic for a fixed
-- declaration and options.
--
-- States are enumerated with @[minBound .. maxBound]@ and located with
-- '(==)', so the 'Eq', 'Enum', and 'Bounded' instances must be lawful
-- and finite. State IDs have the form @s\<i\>_\<name\>@: the decimal
-- enumeration position followed by the 'show' text with every character
-- outside ASCII letters, digits, and underscore replaced by @_@. The
-- exact 'show' text is kept in the state's metadata record.
toSCXMLWith ::
  (Eq s, Enum s, Bounded s, Show s) =>
  ScxmlOptions ->
  SymTransducer (HsPred rs ci) rs s ci co ->
  Either ScxmlError Text
toSCXMLWith opts t = do
  let states = [minBound .. maxBound]
      table = [(i, s, stateId i s) | (i, s) <- zip [0 ..] states]
      lookupId x = case find (\(_, s, _) -> s == x) table of
        Just (_, _, sid) -> Just sid
        Nothing -> Nothing
  if null table then Left EmptyStateEnumeration else Right ()
  initialId <- maybe (Left InitialStateNotEnumerated) Right (lookupId (initial t))
  vertices <- traverse (buildVertex opts t lookupId) table
  pure (renderDocument opts initialId vertices)

-- * Intermediate model ------------------------------------------------------

-- | One enumerated control state, ready to render.
data Vertex = Vertex
  { vIndex :: Int,
    vId :: Text,
    vLabel :: Text,
    vAccepting :: Bool,
    vEdges :: [EdgeRec]
  }

-- | One declared edge, ready to render. Behavior fields are 'Nothing' in
-- structural mode so their pretty-printers are never forced.
data EdgeRec = EdgeRec
  { eIndex :: Int,
    eSource :: Text,
    eTarget :: Text,
    eMode :: EdgeMode,
    eDisplayed :: Bool,
    eEvent :: Text,
    eEventFromInput :: Bool,
    eBehavior :: Maybe Behavior
  }

data Behavior = Behavior
  { bGuard :: Text,
    bUpdate :: Text,
    bAssignments :: [Text],
    bOutputs :: [(Text, [Text])]
  }

buildVertex ::
  (Show s) =>
  ScxmlOptions ->
  SymTransducer (HsPred rs ci) rs s ci co ->
  (s -> Maybe Text) ->
  (Int, s, Text) ->
  Either ScxmlError Vertex
buildVertex opts t lookupId (i, s, sid) = do
  edges <- traverse edgeRec (zip [0 ..] (edgesOut t s))
  pure
    Vertex
      { vIndex = i,
        vId = sid,
        vLabel = T.pack (show s),
        vAccepting = isFinal t s,
        vEdges = edges
      }
  where
    edgeRec (j, e@Edge {guard = g, target = tgt, mode = m}) = do
      tid <-
        maybe
          (Left TargetStateNotEnumerated {sourceStateId = sid, edgeIndex = j})
          Right
          (lookupId tgt)
      let displayed = m == Live || edgeView opts == AllDeclaredEdges
          inputLabel = case m of
            Live -> soleInputConstructor g
            ReplayOnly -> Nothing
          synthetic = case m of
            Live -> syntheticLabel "keiki_edge_s" i j
            ReplayOnly -> syntheticLabel "keiki_replay_s" i j
      pure
        EdgeRec
          { eIndex = j,
            eSource = sid,
            eTarget = tid,
            eMode = m,
            eDisplayed = displayed,
            eEvent = maybe synthetic id inputLabel,
            eEventFromInput = maybe False (const True) inputLabel,
            eBehavior =
              if includeBehavior opts then Just (behaviorOf e) else Nothing
          }

-- | Readable behavior descriptions for an edge. @update@ is bound by the
-- 'Edge' pattern so its existential write-set does not escape.
behaviorOf :: Edge (HsPred rs ci) rs ci co s -> Behavior
behaviorOf Edge {guard = g, update = u, output = outs} =
  Behavior
    { bGuard = prettyPred g,
      bUpdate = prettyUpdate u,
      bAssignments = assignments u,
      bOutputs = map outputOf outs
    }
  where
    outputOf :: OutTerm rs ci co -> (Text, [Text])
    outputOf (OPack _ wc fs) = (T.pack (wcName wc), outFields fs)

    outFields :: OutFields rs ci ifs fs -> [Text]
    outFields OFNil = []
    outFields (OFCons x rest) = prettyTerm x : outFields rest

-- | Each 'USet' of an update as its own @slot := term@ description, in
-- declaration order. 'UKeep' contributes nothing.
assignments :: Update rs w ci -> [Text]
assignments UKeep = []
assignments u@(USet _ _) = [prettyUpdate u]
assignments (UCombine a b) = assignments a ++ assignments b

-- | The single input-constructor name of a purely conjunctive guard, when
-- it is a safe SCXML event token. A guard qualifies only when it contains
-- no disjunction or negation and exactly one 'PInCtor'; the name must
-- match @[A-Za-z_][A-Za-z0-9_]*@ and must not start with the reserved
-- exporter prefix @keiki_@. Anything else gets a synthetic label: the
-- exporter does not pretend that a disjunction, negation, wildcard, or
-- arbitrary display string denotes a single SCXML event.
soleInputConstructor :: HsPred rs ci -> Maybe Text
soleInputConstructor g = case conj g of
  Just [n]
    | isEventToken n && not (T.pack "keiki_" `T.isPrefixOf` n) -> Just n
  _ -> Nothing
  where
    conj :: HsPred rs ci -> Maybe [Text]
    conj (PAnd a b) = (++) <$> conj a <*> conj b
    conj (POr _ _) = Nothing
    conj (PNot _) = Nothing
    conj (PInCtor InCtor {icName = n}) = Just [T.pack n]
    conj PTop = Just []
    conj PBot = Just []
    conj PLeftArm = Just []
    conj PRightArm = Just []
    conj (PEq _ _) = Just []
    conj (PCmp {}) = Just []

isEventToken :: Text -> Bool
isEventToken n = case T.uncons n of
  Just (c, rest) -> (isAsciiAlpha c || c == '_') && T.all isIdChar rest
  Nothing -> False

isAsciiAlpha :: Char -> Bool
isAsciiAlpha c = isAsciiUpper c || isAsciiLower c

isIdChar :: Char -> Bool
isIdChar c = isAsciiAlpha c || isDigit c || c == '_'

syntheticLabel :: String -> Int -> Int -> Text
syntheticLabel prefix i j = T.pack (prefix ++ show i ++ "_e" ++ show j)

-- | @s\<i\>_\<sanitized show\>@. The positional prefix keeps IDs legal and
-- distinct even when two 'show' values coincide or sanitize identically.
stateId :: (Show s) => Int -> s -> Text
stateId i s =
  T.pack ("s" ++ show i ++ "_")
    <> T.map (\c -> if isIdChar c then c else '_') (T.pack (show s))

-- * Rendering ---------------------------------------------------------------

renderDocument :: ScxmlOptions -> Text -> [Vertex] -> Text
renderDocument opts initialId vertices =
  T.concat (map (<> T.pack "\n") docLines)
  where
    docLines =
      [ T.pack "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
        T.pack "<scxml xmlns=\"http://www.w3.org/2005/07/scxml\" version=\"1.0\" datamodel=\"null\" initial=\""
          <> xmlAttr initialId
          <> T.pack "\">",
        indent 1 (comment (documentRecord opts))
      ]
        ++ concatMap renderVertex vertices
        ++ [T.pack "</scxml>"]

renderVertex :: Vertex -> [Text]
renderVertex v =
  [indent 1 (T.pack "<" <> element <> T.pack " id=\"" <> xmlAttr (vId v) <> T.pack "\">")]
    ++ [indent 2 (comment (stateRecord v))]
    ++ concatMap renderEdge (vEdges v)
    ++ [indent 1 (T.pack "</" <> element <> T.pack ">")]
  where
    -- A keiki accepting state becomes a terminal <final> only when nothing
    -- leaves it in this view: SCXML <final> cannot carry transitions, and
    -- keiki's 'isFinal' is an acceptance predicate that does not stop
    -- forward stepping.
    element
      | vAccepting v && not (any eDisplayed (vEdges v)) = T.pack "final"
      | otherwise = T.pack "state"

    renderEdge e
      | eDisplayed e =
          [ indent
              2
              ( T.pack "<transition event=\""
                  <> xmlAttr (eEvent e)
                  <> T.pack "\" target=\""
                  <> xmlAttr (eTarget e)
                  <> T.pack "\">"
              ),
            indent 3 (comment (edgeRecord e)),
            indent 2 (T.pack "</transition>")
          ]
      | otherwise = [indent 2 (comment (edgeRecord e))]

indent :: Int -> Text -> Text
indent n x = T.replicate n (T.pack "  ") <> x

-- | A metadata comment. The JSON encoder never emits a hyphen, so the
-- content cannot contain @--@ or end in @-@.
comment :: Json -> Text
comment j = T.pack "<!--keiki-scxml-v1 " <> encodeJson j <> T.pack "-->"

documentRecord :: ScxmlOptions -> Json
documentRecord opts =
  JObject
    [ ("kind", JString (T.pack "document")),
      ("purpose", JString (T.pack "descriptive-only")),
      ("edgeView", JString edgeViewName),
      ("includeBehavior", JBool (includeBehavior opts)),
      ( "warning",
        JString
          ( T.pack
              "This document describes a keiki transducer; it is not an executable \
              \state machine. Guards, register assignments, outputs, and replay are \
              \not executed by an SCXML interpreter. Event attributes are diagram \
              \labels, not a command encoding."
          )
      ),
      ("replayEdges", JString replayNote),
      ( "edgeIndex",
        JString
          ( T.pack
              "edgeIndex is the 0-based local declaration position in the source \
              \state's edge list, not a durable identifier."
          )
      ),
      ( "updateSemantics",
        JString
          ( T.pack
              "Every assignment's right-hand side reads the register values from \
              \before the edge (the edge-entry snapshot); assignments are not \
              \sequential."
          )
      )
    ]
  where
    edgeViewName = case edgeView opts of
      ForwardEdges -> T.pack "forward-edges"
      AllDeclaredEdges -> T.pack "all-declared-edges"
    replayNote = case edgeView opts of
      ForwardEdges ->
        T.pack
          "Replay-only edges are recorded as comments inside their source state \
          \and are not drawn as transitions."
      AllDeclaredEdges ->
        T.pack
          "Replay-only edges are drawn with keiki_replay_ event labels. These \
          \arrows are historical inversion paths used to interpret past events, \
          \not forward command transitions."

stateRecord :: Vertex -> Json
stateRecord v =
  JObject
    [ ("kind", JString (T.pack "state")),
      ("id", JString (vId v)),
      ("index", JInt (vIndex v)),
      ("label", JString (vLabel v)),
      ("accepting", JBool (vAccepting v))
    ]

edgeRecord :: EdgeRec -> Json
edgeRecord e =
  JObject
    ( [ ("kind", JString (T.pack "edge")),
        ("source", JString (eSource e)),
        ("target", JString (eTarget e)),
        ("edgeIndex", JInt (eIndex e)),
        ("mode", JString (T.pack (show (eMode e)))),
        ("displayed", JBool (eDisplayed e)),
        ("event", JString (eEvent e)),
        ( "eventSource",
          JString
            ( if eEventFromInput e
                then T.pack "input-constructor"
                else T.pack "synthetic"
            )
        )
      ]
        ++ replayFields
        ++ maybe [] behaviorFields (eBehavior e)
    )
  where
    replayFields = case eMode e of
      Live -> []
      ReplayOnly ->
        [ ( "note",
            JString
              ( T.pack
                  "Replay-only: a historical inversion path for interpreting past \
                  \events; it is never taken by a forward command."
              )
          )
        ]
    behaviorFields b =
      [ ("guard", JString (bGuard b)),
        ("update", JString (bUpdate b)),
        ("assignments", JArray (map JString (bAssignments b))),
        ("updateReads", JString (T.pack "edge-entry-snapshot")),
        ( "outputs",
          JArray
            [ JObject
                [ ("constructor", JString n),
                  ("fields", JArray (map JString fs))
                ]
            | (n, fs) <- bOutputs b
            ]
        )
      ]

-- * XML attribute escaping --------------------------------------------------

-- | Escape attribute text. Exporter-generated attributes are already
-- restricted to ASCII identifier characters, so this is defensive.
xmlAttr :: Text -> Text
xmlAttr = T.concatMap esc
  where
    esc '&' = T.pack "&amp;"
    esc '<' = T.pack "&lt;"
    esc '>' = T.pack "&gt;"
    esc '"' = T.pack "&quot;"
    esc '\'' = T.pack "&apos;"
    esc '\t' = T.pack "&#9;"
    esc '\n' = T.pack "&#10;"
    esc '\r' = T.pack "&#13;"
    esc c = T.singleton c

-- * Private JSON encoder ----------------------------------------------------

-- | The fixed shapes the metadata records need. Object fields keep their
-- listed order so output is byte-stable.
data Json
  = JObject [(String, Json)]
  | JArray [Json]
  | JString Text
  | JBool Bool
  | JInt Int

encodeJson :: Json -> Text
encodeJson (JObject kvs) =
  T.pack "{"
    <> T.intercalate
      (T.pack ",")
      [jsonString (T.pack k) <> T.pack ":" <> encodeJson v | (k, v) <- kvs]
    <> T.pack "}"
encodeJson (JArray xs) =
  T.pack "[" <> T.intercalate (T.pack ",") (map encodeJson xs) <> T.pack "]"
encodeJson (JString s) = jsonString s
encodeJson (JBool True) = T.pack "true"
encodeJson (JBool False) = T.pack "false"
encodeJson (JInt n) = T.pack (show n)

-- | A JSON string literal that is also safe as XML comment content.
--
-- Comment content does not decode XML entities, so nothing is
-- entity-escaped; instead every character that XML 1.0 forbids or
-- discourages, every hyphen (so @--@ and @--\>@ cannot form), and every
-- JSON-significant character is written as a JSON escape. After XML
-- parsing plus JSON decoding the original text is recovered exactly.
jsonString :: Text -> Text
jsonString s = T.pack "\"" <> T.concatMap esc s <> T.pack "\""
  where
    esc '"' = T.pack "\\\""
    esc '\\' = T.pack "\\\\"
    esc '\n' = T.pack "\\n"
    esc '\r' = T.pack "\\r"
    esc '\t' = T.pack "\\t"
    esc '\b' = T.pack "\\b"
    esc '\f' = T.pack "\\f"
    esc '-' = T.pack "\\u002d"
    esc c
      | mustEscape (ord c) = unicodeEscape (ord c)
      | otherwise = T.singleton c

    mustEscape n =
      n < 0x20 -- C0 controls (XML-forbidden except tab/newline/return)
        || (n >= 0x7F && n <= 0x9F) -- DEL and C1 controls (discouraged)
        || (n >= 0xD800 && n <= 0xDFFF) -- surrogate code points
        || (n >= 0xFDD0 && n <= 0xFDEF) -- noncharacters
        || (n .&. 0xFFFE) == 0xFFFE -- U+xFFFE / U+xFFFF noncharacters
    unicodeEscape n
      | n >= 0x10000 =
          let m = n - 0x10000
           in hex4 (0xD800 + m `div` 0x400) <> hex4 (0xDC00 + m `mod` 0x400)
      | otherwise = hex4 n

    hex4 n =
      let h = showHex n ""
       in T.pack ("\\u" ++ replicate (4 - length h) '0' ++ h)
