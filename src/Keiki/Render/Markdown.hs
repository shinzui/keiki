{-# LANGUAGE MultiWayIf #-}

-- | Generic Markdown marker-replacement helper. References no keiki
-- type: it rewrites a marked fenced block inside an arbitrary Markdown
-- document. The marker convention is a matched pair of HTML comments,
-- @\<!-- {namespace}: {id} begin --\>@ and @\<!-- {namespace}: {id} end --\>@.
--
-- This closes the loop on regenerating a diagram document: a section
-- emitted by @'Keiki.Render.Mermaid.toMermaidAtlasWith'@ with
-- @atlasWrapMarkers = Just ns@ produces exactly these markers (keyed by the
-- section's @sectionId@), so 'replaceMarkdownDiagramBlock' can later refresh
-- that one block in place while preserving every byte outside it.
--
-- See @docs/plans/65-mermaid-diagram-atlas-sections-and-markdown-marker-replacement-helper.md@.
module Keiki.Render.Markdown
  ( MarkdownDiagramBlock (..),
    MarkdownDiagramError (..),
    replaceMarkdownDiagramBlock,
    beginMarker,
    endMarker,
  )
where

import Data.Text (Text)
import Data.Text qualified as T

-- | A diagram block to splice into a document. 'blockContent' is the
-- already-rendered block body (no fences); 'replaceMarkdownDiagramBlock'
-- wraps it in a normalized fenced block tagged with 'blockLanguage'.
data MarkdownDiagramBlock = MarkdownDiagramBlock
  { -- | Marker namespace, e.g. a service name.
    blockNamespace :: Text,
    -- | Marker id; the atlas @sectionId@.
    blockId :: Text,
    -- | Fenced-block language tag, e.g. @"mermaid"@.
    blockLanguage :: Text,
    -- | Already-rendered block body (no fences).
    blockContent :: Text
  }
  deriving stock (Eq, Show)

-- | Why a replacement could not be performed. Each carries enough text
-- to print the expected marker.
data MarkdownDiagramError
  = -- | The expected begin marker text, not found in the document.
    MissingBeginMarker Text
  | -- | The expected end marker text, not found in the document.
    MissingEndMarker Text
  | -- | A marker text found more than once, and the count found.
    DuplicateMarker Text Int
  deriving stock (Eq, Show)

-- | The begin marker for a @(namespace, id)@ pair.
beginMarker :: Text -> Text -> Text
beginMarker ns i =
  T.pack "<!-- " <> ns <> T.pack ": " <> i <> T.pack " begin -->"

-- | The end marker for a @(namespace, id)@ pair.
endMarker :: Text -> Text -> Text
endMarker ns i =
  T.pack "<!-- " <> ns <> T.pack ": " <> i <> T.pack " end -->"

-- | Replace everything between the begin and end markers for
-- @(blockNamespace, blockId)@ with a normalized fenced block. Preserves
-- the markers and every byte outside them.
--
-- The normalized block is
-- @```{blockLanguage}\\n{content}\\n```@ where @content@ is
-- 'blockContent' with trailing newlines stripped, placed on its own lines
-- between the (preserved) begin and end markers. Because the trailing
-- newlines are stripped before the closing fence, the helper is
-- __idempotent__: re-applying it to a document it already produced yields
-- the identical document.
--
-- Validation: exactly one begin and one end marker must be present.
-- A missing begin marker yields @'MissingBeginMarker' begin@; a missing
-- end yields @'MissingEndMarker' end@; a repeated marker yields
-- @'DuplicateMarker' marker count@.
replaceMarkdownDiagramBlock ::
  MarkdownDiagramBlock -> Text -> Either MarkdownDiagramError Text
replaceMarkdownDiagramBlock blk doc =
  let b = beginMarker (blockNamespace blk) (blockId blk)
      e = endMarker (blockNamespace blk) (blockId blk)
      nb = T.count b doc
      ne = T.count e doc
   in if
        | nb == 0 -> Left (MissingBeginMarker b)
        | nb > 1 -> Left (DuplicateMarker b nb)
        | ne == 0 -> Left (MissingEndMarker e)
        | ne > 1 -> Left (DuplicateMarker e ne)
        | otherwise ->
            let (pre, restB) = T.breakOn b doc
                afterBegin = T.drop (T.length b) restB
                (_, post) = T.breakOn e afterBegin
                fenced =
                  T.pack "```"
                    <> blockLanguage blk
                    <> T.pack "\n"
                    <> stripTrailingNewlines (blockContent blk)
                    <> T.pack "\n```"
             in Right (pre <> b <> T.pack "\n" <> fenced <> T.pack "\n" <> post)

-- | Drop any run of trailing @'\\n'@ characters.
stripTrailingNewlines :: Text -> Text
stripTrailingNewlines = T.dropWhileEnd (== '\n')
