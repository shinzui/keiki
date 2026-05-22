-- | Mermaid 'stateDiagram-v2' renderer for 'SymTransducer' values whose
-- vertex type is enumerable.
--
-- The single-transducer entry point is 'toMermaid'; the supporting
-- helpers ('vertexLabel', 'edgeInputName', 'edgeOutputName',
-- 'edgeLabel') are exported so callers can build custom rendering
-- pipelines on top of the same primitives.
--
-- The rendered output is a @stateDiagram-v2@ block as 'Data.Text.Text'.
-- It can be pasted into a Markdown file or Notion page; GitHub renders
-- Mermaid blocks inline so PR reviewers see the topology diff alongside
-- the source diff.
--
-- The renderer is specialised to @phi ~ 'HsPred' rs ci@ — extracting
-- the input-constructor name from an edge guard requires walking the
-- guard's AST, and 'HsPred' is the only first-class guard AST in the
-- repository. See the Decision Log of
-- @docs/plans/30-mermaid-renderer-for-single-symtransducer-canonical-example-diagrams.md@
-- for the rationale.
--
-- See also:
--
--   * @docs/masterplans/10-mermaid-topology-renderer-for-symtransducer.md@
--     for the initiative motivation.
module Keiki.Render.Mermaid
  ( toMermaid
  , toMermaidAlternative
  , toMermaidAlternativeWith
  , toMermaidComposite
  , toMermaidCompositeNested
  , toMermaidCompose3
  , toMermaidCompose3Nested
  , toMermaidFeedback1
  , toMermaidAtlas
  , toMermaidWith
  , MermaidOptions (..)
  , defaultMermaidOptions
  , vertexLabel
  , compositeLabel
  , compose3Label
  , edgeInputName
  , edgeOutputName
  , edgeLabel
  ) where

import Control.Applicative ((<|>))
import Data.Text (Text)
import qualified Data.Text as T

import Keiki.Composition (Composite (..), WeakenR, feedback1)
import Keiki.Core
  ( Disjoint
  , Edge (..)
  , HsPred (..)
  , InCtor (..)
  , Names
  , OutTerm (..)
  , SymTransducer (..)
  , Update (..)
  , WireCtor (..)
  )
import Keiki.Generics (Append)
import Keiki.Internal.Slots (indexNName)


-- | Rendering options for the structural edge-summary suffix. All
-- fields default to 'False' in 'defaultMermaidOptions', so the default
-- rendering is byte-identical to 'toMermaid'.
data MermaidOptions = MermaidOptions
  { showWrittenSlots :: Bool
    -- ^ When 'True', append the update's written-slot names, e.g.
    -- @[w: email; confirmCode; registeredAt]@.
  , showGuardSummary :: Bool
    -- ^ When 'True', append a structural guard summary listing the
    -- guard's constructor / comparison tags, e.g. @[g: PAnd PInCtor PEq]@.
  }


-- | The default: no summary suffix. @'toMermaid' t@ equals
-- @'toMermaidWith' 'defaultMermaidOptions' t@.
defaultMermaidOptions :: MermaidOptions
defaultMermaidOptions = MermaidOptions
  { showWrittenSlots = False
  , showGuardSummary = False
  }


-- | Render a 'SymTransducer' to a Mermaid @stateDiagram-v2@ block.
--
-- The vertex type @s@ must derive 'Enum', 'Bounded', and 'Show'. The
-- enumeration walks @[minBound .. maxBound]@; vertex labels come from
-- 'show'. The output begins with @stateDiagram-v2@, followed by an
-- initial-state line (@[*] --> <initial>@), one line per outgoing
-- edge of every vertex, and a final-state line (@<vertex> --> [*]@)
-- for every vertex where 'isFinal' returns 'True'. Edge labels follow
-- the format described by 'edgeLabel'.
toMermaid
  :: (Enum s, Bounded s, Show s)
  => SymTransducer (HsPred rs ci) rs s ci co
  -> Text
toMermaid = toMermaidWith defaultMermaidOptions


-- | Like 'toMermaid', but takes 'MermaidOptions' controlling the
-- structural edge-summary suffix. @'toMermaidWith' 'defaultMermaidOptions'@
-- is byte-identical to 'toMermaid'. With 'showWrittenSlots' and/or
-- 'showGuardSummary' enabled, each edge label gains a compact bracketed
-- suffix, e.g. @… [w: email; confirmCode; registeredAt; g: PAnd PInCtor PTop]@.
--
-- Only the single-transducer path is annotated; the composite renderers
-- ('toMermaidComposite' and relatives) keep the guard-free default.
toMermaidWith
  :: (Enum s, Bounded s, Show s)
  => MermaidOptions
  -> SymTransducer (HsPred rs ci) rs s ci co
  -> Text
toMermaidWith opts = renderTopologyWith opts vertexLabel


-- | Render a composite 'SymTransducer' (a 'Keiki.Composition.compose'
-- result, vertex type @'Composite' s1 s2@) to a Mermaid
-- @stateDiagram-v2@ block.
--
-- Uses the **flat cross-product** shape: each composite vertex
-- @'Composite' a b@ becomes a single Mermaid identifier
-- @<show a>_<show b>@. The structure is otherwise identical to
-- 'toMermaid' — same initial / final / edge emission rules, same
-- 'edgeLabel' format. See EP-31's Decision Log
-- (@docs/plans/31-mermaid-rendering-for-composite-symtransducers.md@)
-- for why the flat shape was chosen over Mermaid's nested-subgraph
-- syntax (Shape B in the plan).
toMermaidComposite
  :: ( Enum s1, Bounded s1, Show s1
     , Enum s2, Bounded s2, Show s2
     )
  => SymTransducer (HsPred rs ci) rs (Composite s1 s2) ci co
  -> Text
toMermaidComposite = renderTopology compositeLabel


-- | Render a right-associative 3-deep
-- @t1 \`'Keiki.Composition.compose'\` (t2 \`'Keiki.Composition.compose'\` t3)@
-- composite (vertex type @'Composite' s1 ('Composite' s2 s3)@) to a
-- Mermaid @stateDiagram-v2@ block in the **flat cross-product** shape.
--
-- Each composite vertex becomes a single Mermaid identifier
-- @\<show s1\>_\<show s2\>_\<show s3\>@ via 'compose3Label'. The
-- structure is otherwise identical to 'toMermaid' /
-- 'toMermaidComposite' — same initial / final / edge emission rules,
-- same 'edgeLabel' format. See EP-35's plan
-- (@docs/plans/35-mermaid-renderer-for-right-associative-3-deep-compose-composites.md@)
-- for the rationale and for the comparison against the
-- nested-subgraph variant 'toMermaidCompose3Nested'.
toMermaidCompose3
  :: forall rs s1 s2 s3 ci co.
     ( Enum s1, Bounded s1, Show s1
     , Enum s2, Bounded s2, Show s2
     , Enum s3, Bounded s3, Show s3
     )
  => SymTransducer (HsPred rs ci) rs
       (Composite s1 (Composite s2 s3)) ci co
  -> Text
toMermaidCompose3 = renderTopology compose3Label


-- | Render a composite 'SymTransducer' (a 'Keiki.Composition.compose'
-- result, vertex type @'Composite' s1 s2@) using the **nested-subgraph**
-- shape (Shape B): each outer @s1@ vertex hosts a
-- @state \<show s1\> { \<inner ids\> }@ block listing every
-- @\<show s1\>_\<show s2\>@ identifier in the column. Cross-cutting
-- transitions remain at the top level using the same flat identifiers
-- 'compositeLabel' produces, so the renderer never relies on
-- Mermaid's @Outer.Inner@ dotted cross-block reference syntax.
--
-- Use this for composites where the cross-product becomes hard to
-- scan as a single line; use 'toMermaidComposite' for tiny composites
-- (1–4 vertices) where outer-state grouping adds visual overhead with
-- no payoff. Both shapes coexist; pick the one that reads best for
-- the composite at hand.
--
-- Note on edge organisation: 'Keiki.Composition.compose' composites
-- have **zero same-outer edges** — every composite edge advances the
-- outer @s1@ component (the composite-edge construction in
-- @Keiki.Composition.composedEdges@ either advances @s1@ on a t1
-- ε-edge or on the synchronised t1+t2 step, never leaves @s1@
-- fixed). The visual benefit of this layout for those composites is
-- structural grouping of vertices, not edge organisation. Composites
-- produced by @Keiki.Composition.alternative@ (which DOES yield
-- same-outer edges) are rendered by a separate
-- @toMermaidAlternative@ entry point — see
-- @docs/plans/33-shape-aware-mermaid-renderers-for-alternative-and-feedback1-composites.md@.
--
-- See EP-32's plan
-- (@docs/plans/32-shape-b-nested-subgraph-mermaid-rendering-for-larger-composites.md@)
-- for the full rationale and the Mermaid-syntax cheatsheet.
toMermaidCompositeNested
  :: forall rs s1 s2 ci co.
     ( Enum s1, Bounded s1, Show s1
     , Enum s2, Bounded s2, Show s2
     )
  => SymTransducer (HsPred rs ci) rs (Composite s1 s2) ci co
  -> Text
toMermaidCompositeNested t =
  let outers     = [minBound .. maxBound] :: [s1]
      inners     = [minBound .. maxBound] :: [s2]
      composites = [minBound .. maxBound] :: [Composite s1 s2]

      ind   = T.pack "    "
      ind2  = T.pack "        "
      arrow = T.pack " --> "
      colon = T.pack " : "

      header   = T.pack "stateDiagram-v2"
      initLine = ind <> T.pack "[*]" <> arrow
                   <> compositeLabel (initial t)

      outerBlock o = T.intercalate (T.pack "\n") $
        [ ind <> T.pack "state " <> vertexLabel o <> T.pack " {" ]
        ++
        [ ind2 <> compositeLabel (Composite o i) | i <- inners ]
        ++
        [ ind <> T.pack "}" ]

      outerBlocks = [ outerBlock o | o <- outers ]

      edgeLines =
        [ ind <> compositeLabel s <> arrow
              <> compositeLabel (target e) <> colon
              <> edgeLabel e
        | s <- composites
        , e <- edgesOut t s
        ]

      finalLines =
        [ ind <> compositeLabel s <> arrow <> T.pack "[*]"
        | s <- composites
        , isFinal t s
        ]
  in T.intercalate (T.pack "\n")
       (header : initLine : outerBlocks ++ edgeLines ++ finalLines)


-- | Render a right-associative 3-deep
-- @t1 \`'Keiki.Composition.compose'\` (t2 \`'Keiki.Composition.compose'\` t3)@
-- composite (vertex type @'Composite' s1 ('Composite' s2 s3)@) using
-- the **one-level nested-subgraph** shape: each outer @s1@ vertex
-- hosts a @state \<show s1\> { \<inner ids\> }@ block listing every
-- @\<show s1\>_\<show s2\>_\<show s3\>@ identifier under that outer.
-- Cross-cutting transitions remain at the top level using the same
-- flat identifiers 'compose3Label' produces, so the renderer never
-- relies on Mermaid's @Outer.Inner@ dotted cross-block reference
-- syntax (the EP-32 lesson, carried forward).
--
-- The nest is intentionally **one level deep**, not two: a two-level
-- nest @state s1 { state s2 { … } }@ would mirror @compose@'s
-- structural shape more faithfully but adds renderer-compat risk
-- (some Mermaid backends parse nested @state@ blocks
-- inconsistently). One-level groups composites by their outer
-- aggregate, which is the readability win the larger 3-deep
-- composites need; if a tighter grouping is later required for a
-- specific use case, a follow-up renderer can add the two-level
-- variant with explicit backend verification.
--
-- See EP-35's plan
-- (@docs/plans/35-mermaid-renderer-for-right-associative-3-deep-compose-composites.md@)
-- for the design record and for the flat counterpart
-- 'toMermaidCompose3'.
toMermaidCompose3Nested
  :: forall rs s1 s2 s3 ci co.
     ( Enum s1, Bounded s1, Show s1
     , Enum s2, Bounded s2, Show s2
     , Enum s3, Bounded s3, Show s3
     )
  => SymTransducer (HsPred rs ci) rs
       (Composite s1 (Composite s2 s3)) ci co
  -> Text
toMermaidCompose3Nested t =
  let outers     = [minBound .. maxBound] :: [s1]
      inners     = [minBound .. maxBound] :: [Composite s2 s3]
      composites = [minBound .. maxBound] :: [Composite s1 (Composite s2 s3)]

      ind   = T.pack "    "
      ind2  = T.pack "        "
      arrow = T.pack " --> "
      colon = T.pack " : "

      header   = T.pack "stateDiagram-v2"
      initLine = ind <> T.pack "[*]" <> arrow
                   <> compose3Label (initial t)

      outerBlock o = T.intercalate (T.pack "\n") $
        [ ind <> T.pack "state " <> vertexLabel o <> T.pack " {" ]
        ++
        [ ind2 <> compose3Label (Composite o i) | i <- inners ]
        ++
        [ ind <> T.pack "}" ]

      outerBlocks = [ outerBlock o | o <- outers ]

      edgeLines =
        [ ind <> compose3Label s <> arrow
              <> compose3Label (target e) <> colon
              <> edgeLabel e
        | s <- composites
        , e <- edgesOut t s
        ]

      finalLines =
        [ ind <> compose3Label s <> arrow <> T.pack "[*]"
        | s <- composites
        , isFinal t s
        ]
  in T.intercalate (T.pack "\n")
       (header : initLine : outerBlocks ++ edgeLines ++ finalLines)


-- | Render an 'Keiki.Composition.alternative'-shaped composite as
-- two parallel side-by-side state machines.
--
-- Each component transducer becomes its own
-- @state \<arm-name\> { \<topology\> }@ block listing that arm's edges;
-- both arms share top-level @[*] --> \<initial\>@ initial-state
-- markers and top-level @\<final\> --> [*]@ final-state markers, so
-- the parallel-start / parallel-finish semantics is visible at a
-- glance.
--
-- The runtime composite's vertex space is the cross-product
-- @'Composite' s1 s2@ — but the diagram presents the two arms as
-- independent machines because that mirrors the
-- 'Keiki.Composition.alternative' combinator's actual behaviour:
-- each Either-tagged input advances exactly one arm and leaves the
-- other untouched. The cross-product is implicit; the reader infers
-- "the system's actual state is the combination of both arms'
-- current states."
--
-- Default arm names are @LeftArm@ and @RightArm@. Use
-- 'toMermaidAlternativeWith' to override (e.g. for domain-specific
-- naming such as @EmailArm@ / @PingerArm@).
--
-- Edge labels are the standard @\<input ctor\> / \<output ctor\>@ format
-- ('edgeLabel'). Because 'Keiki.Composition' lifters preserve
-- @icName@ and @wcName@ verbatim, the label reads naturally even
-- though the runtime input is @'Left' …@ / @'Right' …@.
--
-- See @docs/plans/33-shape-aware-mermaid-renderers-for-alternative-and-feedback1-composites.md@
-- for the full design record.
toMermaidAlternative
  :: ( Enum s1, Bounded s1, Show s1
     , Enum s2, Bounded s2, Show s2
     )
  => SymTransducer (HsPred rs1 ci1) rs1 s1 ci1 co1
  -> SymTransducer (HsPred rs2 ci2) rs2 s2 ci2 co2
  -> Text
toMermaidAlternative =
  toMermaidAlternativeWith (T.pack "LeftArm") (T.pack "RightArm")


-- | The arm-name-overridable variant of 'toMermaidAlternative'. The
-- two 'Text' arguments name the left and right @state … { … }@
-- blocks; pick names that match the user's domain vocabulary.
--
-- The names must be valid Mermaid identifiers
-- (regex @[A-Za-z_][A-Za-z0-9_]*@); the renderer does not validate
-- them.
toMermaidAlternativeWith
  :: forall rs1 rs2 s1 s2 ci1 ci2 co1 co2.
     ( Enum s1, Bounded s1, Show s1
     , Enum s2, Bounded s2, Show s2
     )
  => Text
  -- ^ Left arm's state-block name.
  -> Text
  -- ^ Right arm's state-block name.
  -> SymTransducer (HsPred rs1 ci1) rs1 s1 ci1 co1
  -> SymTransducer (HsPred rs2 ci2) rs2 s2 ci2 co2
  -> Text
toMermaidAlternativeWith leftName rightName t1 t2 =
  let ind   = T.pack "    "
      ind2  = T.pack "        "
      arrow = T.pack " --> "
      colon = T.pack " : "

      header = T.pack "stateDiagram-v2"

      initLines =
        [ ind <> T.pack "[*]" <> arrow <> vertexLabel (initial t1)
        , ind <> T.pack "[*]" <> arrow <> vertexLabel (initial t2)
        ]

      armBlock
        :: forall rs s ci co.
           (Enum s, Bounded s, Show s)
        => Text
        -> SymTransducer (HsPred rs ci) rs s ci co
        -> Text
      armBlock name t = T.intercalate (T.pack "\n") $
        [ ind <> T.pack "state " <> name <> T.pack " {" ]
        ++
        [ ind2 <> vertexLabel s <> arrow
               <> vertexLabel (target e) <> colon <> edgeLabel e
        | s <- [minBound .. maxBound]
        , e <- edgesOut t s
        ]
        ++
        [ ind <> T.pack "}" ]

      finalLines
        :: forall rs s ci co.
           (Enum s, Bounded s, Show s)
        => SymTransducer (HsPred rs ci) rs s ci co
        -> [Text]
      finalLines t =
        [ ind <> vertexLabel s <> arrow <> T.pack "[*]"
        | s <- [minBound .. maxBound]
        , isFinal t s
        ]

  in T.intercalate (T.pack "\n") $
       [ header ]
       ++ initLines
       ++ [ armBlock leftName t1
          , armBlock rightName t2
          ]
       ++ finalLines t1
       ++ finalLines t2


-- | Render a 'Keiki.Composition.feedback1'-shaped composite as a
-- flat 3-deep cross-product diagram.
--
-- The composite's vertex type is
-- @'Composite' s1 ('Composite' s2 s1)@ — outer-t state, then policy
-- state, then inner-t state. Each composite vertex becomes a single
-- Mermaid identifier @\<show s1\>_\<show s2\>_\<show s1\>@. The two
-- copies of @t@ (outer and inner) share the same Haskell vertex
-- type but occupy distinct dimensions of the composite tuple, so
-- they are labelled independently.
--
-- For the cascade structure (@'feedback1' t f =
-- 'compose' t ('compose' f t)@), see @feedback1@'s haddock and the
-- design note at
-- @docs/research/composition-combinators-design.md@. The renderer
-- treats the resulting transducer as a flat enumerable cross-product;
-- it does not inspect the cascade structure beyond decomposing the
-- composite tuple for labelling.
toMermaidFeedback1
  :: ( Enum s1, Bounded s1, Show s1
     , Enum s2, Bounded s2, Show s2
     , WeakenR rs1, WeakenR rs2
     , Disjoint (Names rs2) (Names rs1)
     , Disjoint (Names rs1) (Names (Append rs2 rs1))
     )
  => SymTransducer (HsPred rs1 ci) rs1 s1 ci co
  -> SymTransducer (HsPred rs2 co) rs2 s2 co ci
  -> Text
toMermaidFeedback1 t f = renderTopology feedback1Label (feedback1 t f)


-- | The Mermaid identifier for a 'feedback1' composite vertex.
-- @\<show outer\>_\<show policy\>_\<show inner\>@. Like
-- 'compositeLabel', joined with underscores so the result still
-- matches Mermaid's identifier regex @[A-Za-z_][A-Za-z0-9_]*@.
feedback1Label
  :: (Show s1, Show s2)
  => Composite s1 (Composite s2 s1) -> Text
feedback1Label (Composite a (Composite b c)) =
  T.pack (show a) <> T.pack "_"
    <> T.pack (show b) <> T.pack "_"
    <> T.pack (show c)


-- | The Mermaid identifier for a right-associative 3-deep
-- @'Composite' s1 ('Composite' s2 s3)@ vertex.
-- @\<show outer\>_\<show middle\>_\<show inner\>@ — joined with
-- underscores so the result still matches Mermaid's identifier regex
-- @[A-Za-z_][A-Za-z0-9_]*@. The default 'Show' for 'Composite' emits
-- @"Composite a (Composite b c)"@ with whitespace and parentheses, which
-- is not a legal Mermaid identifier; this label sidesteps that by
-- destructuring the composite tuple itself and joining the three
-- component shows directly.
--
-- Sibling of 'compositeLabel' (2-deep) and 'feedback1Label' (3-deep
-- with @s1@ recurring at the inner-inner position). 'compose3Label'
-- requires three independent 'Show' constraints because the three
-- component vertex types are unrelated.
compose3Label
  :: (Show s1, Show s2, Show s3)
  => Composite s1 (Composite s2 s3) -> Text
compose3Label (Composite a (Composite b c)) =
  T.pack (show a) <> T.pack "_"
    <> T.pack (show b) <> T.pack "_"
    <> T.pack (show c)


-- | The shared rendering core: walk @[minBound .. maxBound]@, emit
-- the @stateDiagram-v2@ header, the initial-state line, one line per
-- outgoing edge, and one final-state line per vertex where
-- 'isFinal' fires. The vertex-label function is the only piece that
-- varies between 'toMermaid' (single transducer) and
-- 'toMermaidComposite' (composite); factoring it out keeps the
-- rendering logic in one place.
renderTopology
  :: (Enum s, Bounded s)
  => (s -> Text)
  -> SymTransducer (HsPred rs ci) rs s ci co
  -> Text
renderTopology = renderTopologyWith defaultMermaidOptions


-- | The options-aware rendering core. Identical to 'renderTopology'
-- except the per-edge line calls 'edgeLabelWith' so the structural
-- summary suffix appears when 'MermaidOptions' requests it. With
-- 'defaultMermaidOptions' the output is byte-identical to the original
-- 'renderTopology', which is what keeps 'toMermaid' guard-free.
renderTopologyWith
  :: (Enum s, Bounded s)
  => MermaidOptions
  -> (s -> Text)
  -> SymTransducer (HsPred rs ci) rs s ci co
  -> Text
renderTopologyWith opts label t =
  let vertices  = [minBound .. maxBound]
      header    = T.pack "stateDiagram-v2"
      ind       = T.pack "    "
      arrow     = T.pack " --> "
      colon     = T.pack " : "
      initLine  = ind <> T.pack "[*]" <> arrow <> label (initial t)
      edgeLines =
        [ ind <> label s <> arrow
              <> label (target e) <> colon <> edgeLabelWith opts e
        | s <- vertices
        , e <- edgesOut t s
        ]
      finalLines =
        [ ind <> label s <> arrow <> T.pack "[*]"
        | s <- vertices
        , isFinal t s
        ]
  in T.intercalate (T.pack "\n")
       (header : initLine : edgeLines ++ finalLines)


-- | The Mermaid identifier for a vertex. @'T.pack' . 'show'@ — for
-- every shipped aggregate's vertex type, the data-constructor names
-- already obey Mermaid's identifier regex
-- @[A-Za-z_][A-Za-z0-9_]*@.
vertexLabel :: Show s => s -> Text
vertexLabel = T.pack . show


-- | The Mermaid identifier for a composite vertex.
-- @'show' a \<\> "_" \<\> 'show' b@ — joined with an underscore so the
-- result still matches Mermaid's identifier regex
-- @[A-Za-z_][A-Za-z0-9_]*@. (The default 'Show' for 'Composite' emits
-- @"Composite a b"@ with spaces, which is not a legal Mermaid
-- identifier.)
compositeLabel :: (Show s1, Show s2) => Composite s1 s2 -> Text
compositeLabel (Composite a b) =
  T.pack (show a) <> T.pack "_" <> T.pack (show b)


-- | Extract the input-constructor name from an edge's guard, walking
-- the 'HsPred' AST for the leftmost 'PInCtor' atom. Returns 'Nothing'
-- if the guard contains no 'PInCtor'.
--
-- Every edge introduced via @"Keiki.Builder".'Keiki.Builder.onCmd'@
-- has a recoverable input-constructor name because the builder wraps
-- each guard in @'PAnd' ('PInCtor' ic) inner@. Hand-written AST edges
-- that omit 'PInCtor' produce 'Nothing'; 'edgeLabel' substitutes
-- @"?"@ in that case.
edgeInputName :: Edge (HsPred rs ci) rs ci co s -> Maybe Text
edgeInputName Edge { guard = g } = walk g
  where
    walk :: HsPred rs ci -> Maybe Text
    walk (PInCtor InCtor { icName = n }) = Just (T.pack n)
    walk (PAnd a b) = walk a <|> walk b
    walk (POr  a b) = walk a <|> walk b
    walk (PNot p)   = walk p
    walk PTop       = Nothing
    walk PBot       = Nothing
    walk (PEq _ _)  = Nothing
    walk (PCmp {})  = Nothing


-- | Extract the output-constructor name(s) from an edge's output
-- list. Returns 'Nothing' for an ε-edge (an edge whose 'output' is
-- @[]@); 'Just' a length-1/2/N rendering otherwise.
--
-- Per EP-19's design note, the rendering uses a length-based
-- switchover:
--
--   * length 1: @e1@                       — same as the letter case.
--   * length 2: @e1; e2@                   — compact inline separator.
--   * length 3+: @e1\<br/>e2\<br/>…\<br/>eN@ — Mermaid multi-line.
edgeOutputName :: Edge (HsPred rs ci) rs ci co s -> Maybe Text
edgeOutputName Edge { output = outs } = case outs of
  []     -> Nothing
  [o]    -> Just (wcN o)
  [a, b] -> Just (wcN a <> T.pack "; " <> wcN b)
  many   -> Just (T.intercalate (T.pack "<br/>") (Prelude.map wcN many))
  where
    wcN :: OutTerm rs ci co -> Text
    wcN (OPack _ wc _) = T.pack (wcName wc)


-- | The Mermaid edge label for an edge: @<input ctor> / <output ctor>@.
-- A missing input-constructor name (no 'PInCtor' in the guard)
-- becomes @"?"@; a missing output (an ε-edge) becomes @"ε"@.
edgeLabel :: Edge (HsPred rs ci) rs ci co s -> Text
edgeLabel e =
  let inp = maybe (T.pack "?") id (edgeInputName e)
      out = maybe (T.pack "\x03B5") id (edgeOutputName e)
  in inp <> T.pack " / " <> out


-- | The options-aware edge label: 'edgeLabel' plus an optional
-- structural suffix @[w: …; g: …]@. When neither flag is set this is
-- exactly 'edgeLabel' (no trailing space, no brackets), which is what
-- keeps the 'toMermaid' default byte-identical. The written-slots part
-- is omitted entirely when the edge writes nothing (an empty @w:@ would
-- be noise); the guard part renders the full structural tag walk.
edgeLabelWith
  :: MermaidOptions
  -> Edge (HsPred rs ci) rs ci co s
  -> Text
edgeLabelWith opts e@Edge { update = u, guard = g } =
  -- The whole edge @e@ is reused for 'edgeLabel'; @u@ and @g@ are bound
  -- by the pattern so the existential write-set in @update@ does not
  -- escape (the record selector cannot be used as a function for it).
  let base  = edgeLabel e
      ws    = if showWrittenSlots opts then writtenSlots u else []
      wPart = if null ws
                then []
                else [ T.pack "w: " <> T.intercalate (T.pack "; ") ws ]
      gPart = if showGuardSummary opts
                then [ T.pack "g: " <> guardSummary g ]
                else []
      parts = wPart ++ gPart
  in if null parts
       then base
       else base <> T.pack " [" <> T.intercalate (T.pack "; ") parts <> T.pack "]"


-- | Recover the names of the slots an edge's 'Update' writes, by
-- structural recursion over the 'Update' value. 'USet's @KnownSymbol s@
-- constraint (brought into scope by the pattern match) lets
-- 'indexNName' read the slot name off the index; no type-level
-- write-set machinery is needed.
writtenSlots :: Update rs w ci -> [Text]
writtenSlots UKeep          = []
writtenSlots (USet ix _)    = [T.pack (indexNName ix)]
writtenSlots (UCombine a b) = writtenSlots a ++ writtenSlots b


-- | A structural, total summary of a guard predicate: its constructor
-- tags in left-to-right (prefix) order, with 'PCmp' carrying its 'Cmp'
-- direction. It deliberately does NOT print the operand 'Term's — those
-- can hold opaque Haskell functions ('TApp1'\/'TApp2'), and the
-- input-constructor inside 'PInCtor' carries unprintable match\/build
-- functions. This is the faithful renderable projection of an otherwise
-- unprintable AST.
guardSummary :: HsPred rs ci -> Text
guardSummary = T.intercalate (T.pack " ") . go
  where
    go :: HsPred rs ci -> [Text]
    go PTop         = [T.pack "PTop"]
    go PBot         = [T.pack "PBot"]
    go (PAnd a b)   = T.pack "PAnd" : go a ++ go b
    go (POr  a b)   = T.pack "POr"  : go a ++ go b
    go (PNot p)     = T.pack "PNot" : go p
    go (PEq _ _)    = [T.pack "PEq"]
    go (PInCtor _)  = [T.pack "PInCtor"]
    go (PCmp c _ _) = [T.pack "PCmp " <> T.pack (show c)]


-- | Assemble several already-rendered Mermaid diagrams into one
-- document, each under a labelled section. Each input pair is
-- @(sectionLabel, renderedDiagram)@ where @renderedDiagram@ is the
-- 'Text' produced by any single-transducer or composite renderer in
-- this module (e.g. 'toMermaid', 'toMermaidComposite'). The label is
-- emitted as a Markdown level-2 heading; the diagram is emitted inside
-- a fenced @mermaid@ code block so it renders inline in GitHub \/
-- Notion \/ Markdown previewers.
--
-- Transducers are heterogeneously typed (each has its own vertex,
-- register, input and output types), so a single list of transducers
-- would not type-check; taking already-rendered 'Text' lets each caller
-- pick the matching renderer for its own transducer. An empty list
-- yields the empty 'Text'.
toMermaidAtlas :: [(Text, Text)] -> Text
toMermaidAtlas sections =
  T.intercalate (T.pack "\n\n")
    [ T.pack "## " <> label <> T.pack "\n\n"
        <> T.pack "```mermaid\n" <> diagram <> T.pack "\n```"
    | (label, diagram) <- sections
    ]
