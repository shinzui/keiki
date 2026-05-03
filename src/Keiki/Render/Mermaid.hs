{-# LANGUAGE GADTs #-}

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
  , vertexLabel
  , edgeInputName
  , edgeOutputName
  , edgeLabel
  ) where

import Control.Applicative ((<|>))
import Data.Text (Text)
import qualified Data.Text as T

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
toMermaid t =
  let vertices  = [minBound .. maxBound]
      header    = T.pack "stateDiagram-v2"
      ind       = T.pack "    "
      arrow     = T.pack " --> "
      colon     = T.pack " : "
      initLine  = ind <> T.pack "[*]" <> arrow <> vertexLabel (initial t)
      edgeLines =
        [ ind <> vertexLabel s <> arrow
              <> vertexLabel (target e) <> colon <> edgeLabel e
        | s <- vertices
        , e <- edgesOut t s
        ]
      finalLines =
        [ ind <> vertexLabel s <> arrow <> T.pack "[*]"
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
