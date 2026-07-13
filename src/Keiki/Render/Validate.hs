{-# OPTIONS_GHC -Wno-partial-fields #-}

-- | Pure, cheap structural-heuristic validators for rendered keiki
-- Mermaid diagrams and Mermaid atlas documents.
--
-- These are __not__ a Mermaid parser. They scan rendered 'Text' for a small
-- set of common problems and return a deterministic, document-ordered list
-- of structured warnings. An empty list means \"no problems detected\" —
-- never \"guaranteed valid Mermaid\". The checks can miss problems Mermaid
-- would reject (false negatives) and can flag text Mermaid accepts (false
-- positives); they exist so a downstream unit test can catch the common,
-- cheap-to-detect mistakes before a rendered document is committed.
--
-- Mirrors the pure list-of-warnings house style of
-- 'Keiki.Core.validateTransducer' (EP-56), but operates on rendered 'Text'
-- rather than a 'Keiki.Core.SymTransducer', so there is no shared code.
--
-- See @docs/plans/66-pure-mermaid-diagram-and-atlas-validation-helpers.md@.
-- The warning type intentionally exposes constructor-specific record fields;
-- callers are expected to pattern-match on its constructors before reading
-- them.
module Keiki.Render.Validate
  ( MermaidValidationOptions (..),
    defaultMermaidValidationOptions,
    MermaidValidationWarning (..),
    validateMermaidDiagram,
    validateMermaidAtlas,
  )
where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T

-- | Tunable knobs for the heuristic checks. The denylist and the label
-- budget are caller-tunable so a downstream test can match its own house
-- rules.
data MermaidValidationOptions = MermaidValidationOptions
  { -- | If @'Just' n@, a transition label longer than @n@ characters
    --     yields 'LabelTooLong'. 'Nothing' disables the length check.
    maxLabelLength :: Maybe Int,
    -- | Whether to run the suspicious-unescaped-character check at all.
    checkSuspiciousChars :: Bool,
    -- | The denylist of characters that commonly break Mermaid labels.
    --     The literal substring @\"<br/>\"@ is always exempt from this check
    --     regardless of what this set contains, because keiki emits @<br/>@
    --     deliberately for multi-event and multiline labels.
    suspiciousChars :: [Char]
  }
  deriving stock (Eq, Show)

-- | Sensible defaults: an 80-character label budget, suspicious-char
-- checking on, and the curated denylist @{ '"', '<', '>', '|', '{', '}' }@.
defaultMermaidValidationOptions :: MermaidValidationOptions
defaultMermaidValidationOptions =
  MermaidValidationOptions
    { maxLabelLength = Just 80,
      checkSuspiciousChars = True,
      suspiciousChars = ['"', '<', '>', '|', '{', '}']
    }

-- | One detected problem. Every constructor carries enough context to act
-- on the warning. Line numbers are 1-based, counted in the diagram text
-- handed to 'validateMermaidDiagram'.
data MermaidValidationWarning
  = -- | The first non-blank line is not (and does not start with) @stateDiagram-v2@.
    MissingStateDiagramHeader
  | -- | The document has a header but no transition, declaration, or grouping line under it.
    EmptyDiagram
  | -- | A transition label exceeds 'maxLabelLength'.
    LabelTooLong {warnLine :: Int, warnLength :: Int, warnLabel :: Text}
  | -- | The same @state \"…\" as \<id\>@ identifier is declared more than once, or with conflicting display labels.
    DuplicateStateId {warnStateId :: Text}
  | -- | A transition label contains a denylisted character.
    SuspiciousUnescapedChar {warnLine :: Int, warnChar :: Char, warnLabel :: Text}
  deriving stock (Eq, Show)

-- | Validate a single rendered diagram's 'Text'. Returns warnings in
-- document order: the header check, then the empty-diagram check, then the
-- per-transition-line label checks in line order, then the duplicate-id
-- warnings in first-declaration order. An empty result means no problem was
-- detected (not a guarantee of Mermaid validity — see the module header).
validateMermaidDiagram ::
  MermaidValidationOptions -> Text -> [MermaidValidationWarning]
validateMermaidDiagram opts diagram =
  let numbered = zip [1 :: Int ..] (T.lines diagram)
      contentLns = [(n, T.strip l) | (n, l) <- numbered, not (T.null (T.strip l))]
      headerWs = case contentLns of
        [] -> [MissingStateDiagramHeader]
        ((_, h) : _) ->
          [ MissingStateDiagramHeader
          | not (h == "stateDiagram-v2" || "stateDiagram-v2 " `T.isPrefixOf` h)
          ]
      bodyLns = drop 1 contentLns
      hasBody = any (\(_, l) -> isTransition l || isDecl l || isGroup l) bodyLns
      emptyWs = [EmptyDiagram | not (null contentLns) && not hasBody]
      labelWs =
        concatMap
          (\(n, l) -> labelWarnings opts n l)
          [ (n, l)
          | (n, l) <- numbered,
            isTransition (T.strip l),
            T.strip (transitionTarget l) /= "[*]"
          ]
      dupWs = duplicateStateIdWarnings [T.strip l | (_, l) <- numbered]
   in headerWs ++ emptyWs ++ labelWs ++ dupWs
  where
    isTransition l = " --> " `T.isInfixOf` l
    isDecl l = "state \"" `T.isInfixOf` l && " as " `T.isInfixOf` l
    isGroup l = "state " `T.isPrefixOf` l && "{" `T.isSuffixOf` l

-- | The target token of a transition line (between @ --> @ and @ : @, or
-- to end of line for a final marker). Used only to skip @--> [*]@ finals,
-- which carry no label.
transitionTarget :: Text -> Text
transitionTarget l =
  case T.breakOn " --> " l of
    (_, rest)
      | not (T.null rest) ->
          T.takeWhile (/= ':') (T.drop (T.length " --> ") rest)
    _ -> ""

-- | Per-transition-line label checks (length + suspicious chars).
labelWarnings ::
  MermaidValidationOptions -> Int -> Text -> [MermaidValidationWarning]
labelWarnings opts n line =
  case extractLabel line of
    Nothing -> []
    Just label ->
      let lenWs = case maxLabelLength opts of
            Just maxN
              | T.length label > maxN ->
                  [LabelTooLong {warnLine = n, warnLength = T.length label, warnLabel = label}]
            _ -> []
          charWs
            | checkSuspiciousChars opts =
                [ SuspiciousUnescapedChar {warnLine = n, warnChar = c, warnLabel = label}
                | c <- T.unpack (stripBrTags label),
                  c `elem` suspiciousChars opts
                ]
            | otherwise = []
       in lenWs ++ charWs

-- | The label of a transition line: the text after the first @ : @,
-- trimmed. 'Nothing' when the line has no @ : @ (e.g. a final marker).
extractLabel :: Text -> Maybe Text
extractLabel line =
  case T.breakOn " : " line of
    (_, rest) | not (T.null rest) -> Just (T.strip (T.drop 3 rest))
    _ -> Nothing

-- | Blank out @<br/>@ so its angle brackets are not flagged as suspicious.
stripBrTags :: Text -> Text
stripBrTags = T.replace "<br/>" " "

-- | Collect @state \"\<display\>\" as \<id\>@ declarations and report any
-- id declared twice or with conflicting display labels. Ids that merely
-- recur as transition endpoints are never reported (that is normal, and
-- keys off exactly the declaration lines EP-64's 'toMermaidWithLabels'
-- emits). Reported in first-declared (sorted-key) order.
duplicateStateIdWarnings :: [Text] -> [MermaidValidationWarning]
duplicateStateIdWarnings ls =
  let decls = [d | Just d <- map parseDecl ls]
      tally = foldl' (\m (i, disp) -> Map.insertWith (++) i [disp] m) Map.empty decls
   in [ DuplicateStateId {warnStateId = i}
      | (i, disps) <- Map.toList tally,
        length disps > 1 || length (nubText disps) > 1
      ]
  where
    nubText = foldr (\x acc -> if x `elem` acc then acc else x : acc) []

-- | Parse a @state \"\<display\>\" as \<id\>@ declaration line into its
-- @(id, display)@ pair; 'Nothing' for any other line.
parseDecl :: Text -> Maybe (Text, Text)
parseDecl l0 =
  case T.stripPrefix "state \"" (T.strip l0) of
    Nothing -> Nothing
    Just rest ->
      case T.breakOn "\" as " rest of
        (disp, afterDisp)
          | not (T.null afterDisp) ->
              Just (T.strip (T.drop (T.length "\" as ") afterDisp), disp)
        _ -> Nothing

-- | Validate a multi-section atlas: split into fenced @```mermaid@ blocks
-- and run 'validateMermaidDiagram' on each, aggregating warnings in block
-- order.
validateMermaidAtlas ::
  MermaidValidationOptions -> Text -> [MermaidValidationWarning]
validateMermaidAtlas opts doc =
  concatMap (validateMermaidDiagram opts) (mermaidBlocks (T.lines doc))

-- | Extract the inner text of each @```mermaid@ … @```@ fenced block: the
-- lines strictly between an opening fence line whose trimmed content is
-- exactly @```mermaid@ and the next line whose trimmed content is exactly
-- @```@.
mermaidBlocks :: [Text] -> [Text]
mermaidBlocks = go
  where
    go [] = []
    go (l : rest)
      | T.strip l == "```mermaid" =
          let (body, after) = break (\x -> T.strip x == "```") rest
           in T.intercalate "\n" body : go (dropOne after)
      | otherwise = go rest
    dropOne (_ : xs) = xs
    dropOne [] = []
