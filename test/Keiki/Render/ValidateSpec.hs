-- | Unit tests for "Keiki.Render.Validate" (EP-66). Pure, hspec-only:
-- each crafted diagram produces exactly the listed warning value, and a
-- well-formed diagram produces the empty list.
--
-- See @docs/plans/66-pure-mermaid-diagram-and-atlas-validation-helpers.md@.
module Keiki.Render.ValidateSpec (spec) where

import Data.Text (Text)
import Data.Text qualified as T
import Keiki.Render.Validate
  ( MermaidValidationOptions (..),
    MermaidValidationWarning (..),
    defaultMermaidValidationOptions,
    validateMermaidAtlas,
    validateMermaidDiagram,
  )
import Test.Hspec

spec :: Spec
spec = do
  describe "validateMermaidDiagram" $ do
    it "passes a well-formed diagram" $
      validateMermaidDiagram defaultMermaidValidationOptions goodDiagram
        `shouldBe` []

    it "flags a missing stateDiagram-v2 header" $
      validateMermaidDiagram defaultMermaidValidationOptions noHeader
        `shouldBe` [MissingStateDiagramHeader]

    it "flags an empty diagram (header with nothing under it)" $
      validateMermaidDiagram defaultMermaidValidationOptions onlyHeader
        `shouldBe` [EmptyDiagram]

    it "flags an over-length label with line, length and text" $
      validateMermaidDiagram tinyBudget goodDiagram
        `shouldBe` [LabelTooLong {warnLine = 3, warnLength = 13, warnLabel = T.pack "A / LongEvent"}]

    it "flags a suspicious unescaped character in a label" $
      validateMermaidDiagram defaultMermaidValidationOptions pipeLabel
        `shouldBe` [SuspiciousUnescapedChar {warnLine = 3, warnChar = '|', warnLabel = T.pack "Cmd / a|b"}]

    it "does not flag the deliberate <br/> tag keiki emits" $
      validateMermaidDiagram defaultMermaidValidationOptions brDiagram
        `shouldBe` []

    it "flags a duplicate declared state id but not endpoint recurrence" $
      validateMermaidDiagram defaultMermaidValidationOptions dupDecls
        `shouldBe` [DuplicateStateId {warnStateId = T.pack "S1"}]

  describe "validateMermaidAtlas" $
    it "aggregates warnings across fenced mermaid blocks in block order" $
      validateMermaidAtlas defaultMermaidValidationOptions atlas
        `shouldBe` [MissingStateDiagramHeader]

-- | A well-formed two-state diagram; its line-3 label is 13 characters.
goodDiagram :: Text
goodDiagram =
  T.intercalate
    (T.pack "\n")
    [ "stateDiagram-v2",
      "    [*] --> S1",
      "    S1 --> S2 : A / LongEvent",
      "    S2 --> [*]"
    ]

-- | 'defaultMermaidValidationOptions' with a 5-character label budget.
tinyBudget :: MermaidValidationOptions
tinyBudget = defaultMermaidValidationOptions {maxLabelLength = Just 5}

-- | No @stateDiagram-v2@ header line.
noHeader :: Text
noHeader =
  T.intercalate
    (T.pack "\n")
    [ "    [*] --> S1",
      "    S1 --> [*]"
    ]

-- | A header with no body.
onlyHeader :: Text
onlyHeader = T.pack "stateDiagram-v2"

-- | A label carrying a single denylisted character (the pipe @|@).
pipeLabel :: Text
pipeLabel =
  T.intercalate
    (T.pack "\n")
    [ "stateDiagram-v2",
      "    [*] --> S1",
      "    S1 --> S2 : Cmd / a|b",
      "    S2 --> [*]"
    ]

-- | A label whose only angle brackets come from a deliberate @<br/>@ tag,
-- which the validator exempts.
brDiagram :: Text
brDiagram =
  T.intercalate
    (T.pack "\n")
    [ "stateDiagram-v2",
      "    [*] --> S1",
      "    S1 --> S2 : Cmd / A<br/>B",
      "    S2 --> [*]"
    ]

-- | The id @S1@ is declared twice (with conflicting display labels) and
-- also recurs as a transition endpoint; only the declaration clash is a
-- duplicate.
dupDecls :: Text
dupDecls =
  T.intercalate
    (T.pack "\n")
    [ "stateDiagram-v2",
      "    state \"First\" as S1",
      "    state \"Second\" as S1",
      "    [*] --> S1",
      "    S1 --> [*]"
    ]

-- | A two-section atlas: one clean block, one block missing its header.
atlas :: Text
atlas =
  T.intercalate
    (T.pack "\n")
    [ "## Good",
      "",
      "```mermaid",
      "stateDiagram-v2",
      "    [*] --> S1",
      "    S1 --> [*]",
      "```",
      "",
      "## Bad",
      "",
      "```mermaid",
      "    [*] --> S1",
      "    S1 --> [*]",
      "```"
    ]
