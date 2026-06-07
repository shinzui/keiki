-- | A Markdown edge-detail renderer for 'SymTransducer', a sibling to
-- the Mermaid topology renderer in "Keiki.Render.Mermaid". Where
-- 'Keiki.Render.Mermaid.toMermaid' shows the /shape/ of a workflow (one
-- line per edge), this renderer lays out every edge in /full/: its
-- source and target states, its 0-based edge index, the input
-- (command) constructor, the output (event) constructor(s), the guard
-- predicate (structural and/or domain-readable), the register slots it
-- writes, and — optionally — each output field's term.
--
-- The output is a deterministic 'Data.Text.Text' Markdown document with
-- edges grouped under a level-3 heading per source state. It is pure:
-- no IO, no SMT solver.
module Keiki.Render.Inspector
  ( EdgeInspectorOptions (..),
    defaultEdgeInspectorOptions,
    renderEdgeInspector,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Keiki.Core
  ( Edge (..),
    HsPred (..),
    OutFields (..),
    OutTerm (..),
    SymTransducer (..),
    Update (..),
    WireCtor (..),
  )
import Keiki.Internal.Slots (indexNName)
import Keiki.Render.Mermaid (edgeInputName)
import Keiki.Render.Pretty (prettyPred, prettyTerm)

-- | Which detail fields each edge block carries. Every field is opt-in
-- via a 'Bool'. 'defaultEdgeInspectorOptions' turns on everything that
-- needs no domain-readable rendering; the two pretty options
-- ('includePrettyGuard', 'includeOutputFields') reuse
-- "Keiki.Render.Pretty" and default to 'False'.
data EdgeInspectorOptions = EdgeInspectorOptions
  { -- | Show @edge index: N@ (the 0-based position in @edgesOut t s@).
    includeEdgeIndex :: Bool,
    -- | Show the structural guard summary, e.g. @PAnd PInCtor PEq@.
    includeStructuralGuard :: Bool,
    -- | Show the domain-readable guard from
    --     'Keiki.Render.Pretty.prettyPred', e.g.
    --     @(ConfirmAccount && ConfirmAccount.confirmCode == confirmCode)@.
    includePrettyGuard :: Bool,
    -- | Show the register slots the edge writes.
    includeWrittenSlots :: Bool,
    -- | Show each output field's term, positionally (field 0, field 1,
    --     …), via 'Keiki.Render.Pretty.prettyTerm'. 'WireCtor' carries no
    --     field names, so fields are labelled by position only.
    includeOutputFields :: Bool
  }

-- | The default: everything on except the two pretty options that reuse
-- "Keiki.Render.Pretty".
defaultEdgeInspectorOptions :: EdgeInspectorOptions
defaultEdgeInspectorOptions =
  EdgeInspectorOptions
    { includeEdgeIndex = True,
      includeStructuralGuard = True,
      includePrettyGuard = False,
      includeWrittenSlots = True,
      includeOutputFields = False
    }

-- | Render a 'SymTransducer' to a Markdown edge-detail document. Edges
-- are grouped under a @### \<state\>@ heading per source state, in
-- @[minBound .. maxBound]@ order; states with no outgoing edges produce
-- no section. The state type's @Bounded@/@Enum@ enumerate the states and
-- @Show@ names them, mirroring 'Keiki.Render.Mermaid.toMermaid'.
renderEdgeInspector ::
  (Bounded s, Enum s, Show s) =>
  EdgeInspectorOptions ->
  SymTransducer (HsPred rs ci) rs s ci co ->
  Text
renderEdgeInspector opts t =
  let states = [minBound .. maxBound]
      section s = case edgesOut t s of
        [] -> Nothing
        edges -> Just (renderState opts s edges)
   in T.intercalate
        (T.pack "\n\n")
        ( T.pack "# Edge inspector"
            : [blk | Just blk <- map section states]
        )

-- | One @### \<state\>@ section: the heading, a blank line, then one
-- block per outgoing edge (in @edgesOut@ order, with its 0-based index).
-- Edge blocks are separated by a single newline (no blank line between
-- them).
renderState ::
  (Show s) =>
  EdgeInspectorOptions ->
  s ->
  [Edge (HsPred rs ci) rs ci co s] ->
  Text
renderState opts s edges =
  T.intercalate
    (T.pack "\n")
    ( (T.pack "### " <> T.pack (show s))
        : T.pack ""
        : [renderEdge opts s i e | (i, e) <- zip [0 ..] edges]
    )

-- | One edge block: a header bullet naming the transition, then one
-- indented detail bullet per enabled, non-empty field. @update@ is bound
-- by the 'Edge' pattern (never via the @update@ selector) so the
-- existential write-set does not escape.
renderEdge ::
  (Show s) =>
  EdgeInspectorOptions ->
  s ->
  Int ->
  Edge (HsPred rs ci) rs ci co s ->
  Text
renderEdge opts s i e@Edge {guard = g, update = u, target = tgt} =
  T.intercalate (T.pack "\n") (header : details)
  where
    header =
      T.pack "- **"
        <> T.pack (show s)
        <> T.pack " -> "
        <> T.pack (show tgt)
        <> T.pack "**"

    details =
      concat
        [ bullet
            (includeEdgeIndex opts)
            (T.pack "edge index: " <> T.pack (show i)),
          [detail (T.pack "input: " <> maybe (T.pack "?") id (edgeInputName e))],
          [detail (T.pack "output: " <> maybe (T.pack "\x03B5") id (outputName e))],
          outputFieldsBullets,
          bullet
            (includeStructuralGuard opts)
            (T.pack "guard (structural): " <> guardSummary g),
          bullet
            (includePrettyGuard opts)
            (T.pack "guard (pretty): " <> prettyPred g),
          writtenBullets
        ]

    -- An edge's written-slot listing; omitted when the edge writes
    -- nothing (an empty list would be noise).
    writtenBullets
      | not (includeWrittenSlots opts) = []
      | otherwise = case writtenSlots u of
          [] -> []
          ws -> [detail (T.pack "written slots: " <> T.intercalate (T.pack "; ") ws)]

    -- Each output's fields, positionally. Only outputs that have at
    -- least one field contribute; the bullet is omitted when no output
    -- carries a field.
    outputFieldsBullets
      | not (includeOutputFields opts) = []
      | otherwise = case [grp | Just grp <- map outputGroup (output e)] of
          [] -> []
          grps -> [detail (T.pack "output fields: " <> T.intercalate (T.pack "; ") grps)]

    detail x = T.pack "  - " <> x
    bullet cond x = if cond then [detail x] else []

-- | One output's field listing: @\<wcName\>[field 0: t0; field 1: t1]@,
-- or 'Nothing' when the output constructor has no fields.
outputGroup :: OutTerm rs ci co -> Maybe Text
outputGroup (OPack _ wc fs) = case zip [0 :: Int ..] (prettyOutFields fs) of
  [] -> Nothing
  fields ->
    Just
      ( T.pack (wcName wc)
          <> T.pack "["
          <> T.intercalate
            (T.pack "; ")
            [ T.pack "field " <> T.pack (show k) <> T.pack ": " <> ft
            | (k, ft) <- fields
            ]
          <> T.pack "]"
      )

-- | Pretty-print each field 'Term' of an 'OutFields' HList, in order,
-- reusing 'Keiki.Render.Pretty.prettyTerm'.
prettyOutFields :: OutFields rs ci ifs fs -> [Text]
prettyOutFields OFNil = []
prettyOutFields (OFCons t rest) = prettyTerm t : prettyOutFields rest

-- | The output constructor name(s) for an edge, joined with @"; "@ for
-- Markdown (the Mermaid renderer uses @\<br/\>@ for three or more, which
-- is a diagram-only line break). 'Nothing' for an ε-edge (empty output).
outputName :: Edge (HsPred rs ci) rs ci co s -> Maybe Text
outputName Edge {output = outs} = case outs of
  [] -> Nothing
  many -> Just (T.intercalate (T.pack "; ") (map wcN many))
  where
    wcN :: OutTerm rs ci co -> Text
    wcN (OPack _ wc _) = T.pack (wcName wc)

-- | A structural, total summary of a guard predicate: its constructor
-- tags in left-to-right (prefix) order, with 'PCmp' carrying its
-- direction. Replicated from "Keiki.Render.Mermaid" (where it is not
-- exported); kept byte-identical to that original.
guardSummary :: HsPred rs ci -> Text
guardSummary = T.intercalate (T.pack " ") . go
  where
    go :: HsPred rs ci -> [Text]
    go PTop = [T.pack "PTop"]
    go PBot = [T.pack "PBot"]
    go (PAnd a b) = T.pack "PAnd" : go a ++ go b
    go (POr a b) = T.pack "POr" : go a ++ go b
    go (PNot p) = T.pack "PNot" : go p
    go (PEq _ _) = [T.pack "PEq"]
    go (PInCtor _) = [T.pack "PInCtor"]
    go (PCmp c _ _) = [T.pack "PCmp " <> T.pack (show c)]

-- | Recover the names of the slots an edge's 'Update' writes.
-- Replicated from "Keiki.Render.Mermaid" (not exported there); kept
-- byte-identical. 'USet's @KnownSymbol s@ (from the pattern match) lets
-- 'indexNName' read the slot name off the index.
writtenSlots :: Update rs w ci -> [Text]
writtenSlots UKeep = []
writtenSlots (USet ix _) = [T.pack (indexNName ix)]
writtenSlots (UCombine a b) = writtenSlots a ++ writtenSlots b
