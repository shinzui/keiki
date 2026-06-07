-- | Tests for "Keiki.Render.Markdown" (EP-65 M2).
--
-- Exercises 'replaceMarkdownDiagramBlock': it rewrites exactly the span
-- between a matched pair of @\<!-- ns: id begin/end --\>@ markers with a
-- normalized fenced block, preserves every byte outside the markers,
-- reports a clear error when a marker is missing or duplicated, and is
-- idempotent.
--
-- See @docs/plans/65-mermaid-diagram-atlas-sections-and-markdown-marker-replacement-helper.md@.
module Keiki.Render.MarkdownSpec (spec) where

import Data.Text (Text)
import Data.Text qualified as T
import Keiki.Render.Markdown
  ( MarkdownDiagramBlock (..),
    MarkdownDiagramError (..),
    replaceMarkdownDiagramBlock,
  )
import Test.Hspec

spec :: Spec
spec = do
  describe "replaceMarkdownDiagramBlock (happy path)" $ do
    it "replaces only the marked span and preserves the markers" $
      replaceMarkdownDiagramBlock newBlock inputDoc
        `shouldBe` Right expectedDoc

    it "preserves the prose above and below byte-for-byte" $
      case replaceMarkdownDiagramBlock newBlock inputDoc of
        Right out -> do
          T.isPrefixOf (T.pack "# Architecture\n\nSome prose above.") out
            `shouldBe` True
          T.isSuffixOf (T.pack "Some prose below.") out `shouldBe` True
        Left err -> expectationFailure ("unexpected error: " <> show err)

    it "is idempotent: replacing the already-normalized block reproduces it" $
      (replaceMarkdownDiagramBlock newBlock expectedDoc)
        `shouldBe` Right expectedDoc

  describe "replaceMarkdownDiagramBlock (errors)" $ do
    it "reports the expected begin marker when it is absent" $
      replaceMarkdownDiagramBlock newBlock (T.pack "no markers here\n")
        `shouldBe` Left (MissingBeginMarker (T.pack "<!-- seihou: incident-command begin -->"))

    it "reports the expected end marker when only the begin is present" $
      replaceMarkdownDiagramBlock newBlock beginOnlyDoc
        `shouldBe` Left (MissingEndMarker (T.pack "<!-- seihou: incident-command end -->"))

    it "fails deterministically when the begin marker is duplicated" $
      replaceMarkdownDiagramBlock newBlock duplicateBeginDoc
        `shouldBe` Left (DuplicateMarker (T.pack "<!-- seihou: incident-command begin -->") 2)

    it "fails deterministically when the end marker is duplicated" $
      replaceMarkdownDiagramBlock newBlock duplicateEndDoc
        `shouldBe` Left (DuplicateMarker (T.pack "<!-- seihou: incident-command end -->") 2)

-- | The block to splice; its content ends in a newline to exercise the
-- trailing-newline stripping that makes the helper idempotent.
newBlock :: MarkdownDiagramBlock
newBlock =
  MarkdownDiagramBlock
    { blockNamespace = T.pack "seihou",
      blockId = T.pack "incident-command",
      blockLanguage = T.pack "mermaid",
      blockContent = T.pack "stateDiagram-v2\n    [*] --> Open\n"
    }

-- | A hand-maintained document with prose around a stale diagram.
inputDoc :: Text
inputDoc =
  T.intercalate
    (T.pack "\n")
    [ "# Architecture",
      "",
      "Some prose above.",
      "",
      "<!-- seihou: incident-command begin -->",
      "```mermaid",
      "OLD DIAGRAM",
      "```",
      "<!-- seihou: incident-command end -->",
      "",
      "Some prose below."
    ]

-- | 'inputDoc' after replacing the marked block with 'newBlock'. Only the
-- span between the markers changed; the markers and surrounding prose are
-- byte-identical, and the trailing newline in 'blockContent' is stripped
-- before the closing fence.
expectedDoc :: Text
expectedDoc =
  T.intercalate
    (T.pack "\n")
    [ "# Architecture",
      "",
      "Some prose above.",
      "",
      "<!-- seihou: incident-command begin -->",
      "```mermaid",
      "stateDiagram-v2",
      "    [*] --> Open",
      "```",
      "<!-- seihou: incident-command end -->",
      "",
      "Some prose below."
    ]

-- | A document with the begin marker but no matching end marker.
beginOnlyDoc :: Text
beginOnlyDoc =
  T.intercalate
    (T.pack "\n")
    [ "<!-- seihou: incident-command begin -->",
      "```mermaid",
      "OLD DIAGRAM",
      "```"
    ]

-- | A document whose begin marker appears twice.
duplicateBeginDoc :: Text
duplicateBeginDoc =
  T.intercalate
    (T.pack "\n")
    [ "<!-- seihou: incident-command begin -->",
      "<!-- seihou: incident-command begin -->",
      "<!-- seihou: incident-command end -->"
    ]

-- | A document whose end marker appears twice.
duplicateEndDoc :: Text
duplicateEndDoc =
  T.intercalate
    (T.pack "\n")
    [ "<!-- seihou: incident-command begin -->",
      "<!-- seihou: incident-command end -->",
      "<!-- seihou: incident-command end -->"
    ]
