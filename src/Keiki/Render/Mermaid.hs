{-# LANGUAGE GADTs #-}
{-# LANGUAGE ScopedTypeVariables #-}

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
  , toMermaidComposite
  , toMermaidCompositeNested
  , vertexLabel
  , compositeLabel
  , edgeInputName
  , edgeOutputName
  , edgeLabel
  ) where

import Control.Applicative ((<|>))
import Data.Text (Text)
import qualified Data.Text as T

import Keiki.Composition (Composite (..))
import Keiki.Core
  ( Edge (..)
  , HsPred (..)
  , InCtor (..)
  , OutTerm (..)
  , SymTransducer (..)
  , WireCtor (..)
  )


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
toMermaid = renderTopology vertexLabel


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
renderTopology label t =
  let vertices  = [minBound .. maxBound]
      header    = T.pack "stateDiagram-v2"
      ind       = T.pack "    "
      arrow     = T.pack " --> "
      colon     = T.pack " : "
      initLine  = ind <> T.pack "[*]" <> arrow <> label (initial t)
      edgeLines =
        [ ind <> label s <> arrow
              <> label (target e) <> colon <> edgeLabel e
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


-- | Extract the output-constructor name from an edge's 'OPack', or
-- 'Nothing' for an ε-edge (an edge whose 'output' is 'Nothing').
edgeOutputName :: Edge (HsPred rs ci) rs ci co s -> Maybe Text
edgeOutputName Edge { output = Nothing }                 = Nothing
edgeOutputName Edge { output = Just (OPack _ wc _) }     = Just (T.pack (wcName wc))


-- | The Mermaid edge label for an edge: @<input ctor> / <output ctor>@.
-- A missing input-constructor name (no 'PInCtor' in the guard)
-- becomes @"?"@; a missing output (an ε-edge) becomes @"ε"@.
edgeLabel :: Edge (HsPred rs ci) rs ci co s -> Text
edgeLabel e =
  let inp = maybe (T.pack "?") id (edgeInputName e)
      out = maybe (T.pack "\x03B5") id (edgeOutputName e)
  in inp <> T.pack " / " <> out
