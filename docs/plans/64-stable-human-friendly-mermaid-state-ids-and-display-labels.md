---
id: 64
slug: stable-human-friendly-mermaid-state-ids-and-display-labels
title: "Stable human-friendly Mermaid state IDs and display labels"
kind: exec-plan
created_at: 2026-06-06T15:47:42Z
intention: "intention_01ktes9wvkekw8nbb69st0naj8"
master_plan: "docs/masterplans/15-keiki-mermaid-diagram-and-documentation-rendering-improvements-surfaced-by-the-seihou-diagram-audit.md"
---

# Stable human-friendly Mermaid state IDs and display labels

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

Today, keiki's Mermaid renderer derives a state's diagram identifier and its visible
display text from the same source: `Show s`. That works as long as a vertex type's
`Show` output is simultaneously (a) a legal Mermaid identifier (the regex
`[A-Za-z_][A-Za-z0-9_]*` — letters, digits, underscores, starting with a letter or
underscore, no spaces) and (b) a label a human wants to read. Those two goals conflict
the moment a caller wants a friendly label with spaces, punctuation, or a longer phrase:
a label like `"Requires Confirmation"` is human-readable but is *not* a legal Mermaid
identifier, so it cannot be used as a transition endpoint.

After this change, a caller can supply **two separate functions** for each vertex: one
producing a stable ASCII identifier (used as the Mermaid node id and in every transition
arrow), and one producing a friendly display label (shown to the reader, allowed to
contain spaces). The new entry point is `toMermaidWithLabels`. Mermaid's
`stateDiagram-v2` syntax supports exactly this split through the declaration form
`state "Friendly Display Label" as StableId`: the quoted string is the visible label, and
the bare identifier after `as` is what transitions reference.

You can see it working by rendering any existing transducer twice: once with the default
`toMermaid` (output unchanged, byte-for-byte), and once with `toMermaidWithLabels` supplying
spaced display labels — the second output gains `state "…" as …` declaration lines and uses
the stable ASCII ids in its arrows. The default path stays exactly as it is today, so every
checked-in diagram and every golden test continues to pass without modification.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] M1: Generalize `renderTopologyWith` in `src/Keiki/Render/Mermaid.hs` to take `idOf` and `displayOf`; splice `state "<display>" as <id>` declaration lines only where `displayOf s /= idOf s`.
- [x] M1: Update `renderTopology` and `toMermaidWith` to pass the same label function twice (preserve byte-identity for `toMermaid` and the composite renderers).
- [x] M1: Add `data MermaidStateLabels s` and `toMermaidWithLabels` (drops `Show s`); export both from the module.
- [x] M1: Add golden cases in `test/Keiki/Render/MermaidSpec.hs` — spaced-display-label block + the id==display byte-identity assertion; confirm existing goldens unchanged.
- [x] M1: `cabal build keiki` and `cabal test keiki-test` pass.
- [x] M2: Add and export pure `duplicateStateIds`; add colliding-id + clean-id unit tests.
- [x] M2: `cabal test keiki-test` passes.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- EP-61 and EP-63 had already landed, so `renderTopologyWith` carried EP-61/EP-63's `guardMode`
  and layout logic through `edgeLabelWith`. The two-function generalization (`idOf`/`displayOf`)
  composes cleanly with that work — it only touched the vertex-label uses (init/edge/final lines
  plus the new `declLines`), leaving `edgeLabelWith opts e` untouched. No interaction surfaced.
- `userReg`'s vertex type `Vertex` is exported with `(..)` from
  `test/Keiki/Fixtures/UserRegistration.hs`, so the test's `userRegLabels` pattern-matches the
  real constructors (`PotentialCustomer`, …) for friendly labels instead of switching on
  `show s` strings — simpler and total. The renderer's exported `vertexLabel` (`= T.pack . show`)
  served directly as the id==display identity function for the byte-identity assertion, so no
  local `vertexLabelShow` helper was needed.
- All goldens matched the renderer on the first run (356 examples, 0 failures); the
  pre-existing `userRegCanonical` and every other golden stayed byte-identical, confirming the
  "declaration only when display ≠ id" rule keeps the default path untouched.


## Decision Log

Record every decision made while working on the plan.

- Decision: Emit a `state "<display>" as <id>` declaration line ONLY for vertices where
  `displayOf s /= idOf s`; never when they are equal.
  Rationale: This is the mechanism that preserves byte-identity. The default path
  (`toMermaid` / `toMermaidWith`) sets `idOf = displayOf = T.pack . show`, so the predicate
  is always false and the declaration list is empty — the spliced output is exactly today's
  bytes, and the existing `userRegCanonical` golden (`test/Keiki/Render/MermaidSpec.hs:132`)
  passes untouched. Emitting declarations for *all* vertices would break that golden.
  Date: 2026-06-06

- Decision: The caller supplies ASCII ids; keiki uses `stateId`'s output verbatim and does
  not sanitize it.
  Rationale: The requirement is "callers can keep stable ASCII Mermaid IDs", which puts the
  caller in control of the id namespace (they alone know which ids are meaningful and
  stable across renders). Sanitizing inside keiki could silently rewrite a caller's chosen
  id and would couple the renderer to a particular escaping policy. A sanitizing helper
  could be added later as a convenience, but it is not part of this plan's contract.
  Date: 2026-06-06

- Decision: Ship a small local pure helper `duplicateStateIds` (M2) rather than depending on
  the sibling validation plan for the "duplicate generated IDs" acceptance, while keeping
  rendering total (no throw).
  Rationale: The audit's acceptance says duplicate ids should "fail with a clear validation
  warning or error." Making rendering throw would make a total pure function partial, which
  is against keiki's house style. Instead, rendering stays total and a separate pure check
  reports collisions. `docs/plans/66-pure-mermaid-diagram-and-atlas-validation-helpers.md`
  performs the same check over rendered text; this AST-level helper keeps this plan
  self-contained if EP-66 is not yet done, and both agree on what an "id" is because both
  use exactly what `stateId` produces.
  Date: 2026-06-06

- Decision: Keep `renderTopologyWith` taking two plain `(s -> Text)` arguments (an `idOf`
  and a `displayOf`) rather than threading the public `MermaidStateLabels` record through
  the core.
  Rationale: The composite renderers call the core via `renderTopology` with a single label
  function; the two-positional-argument form lets `renderTopology label =
  renderTopologyWith … label label` reuse it trivially, and `toMermaidWithLabels` just
  unpacks the record into the two functions. This minimizes the change to shared code that
  `docs/plans/61-...md` and `docs/plans/63-...md` also touch.
  Date: 2026-06-06


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

Delivered as designed. `renderTopologyWith` now takes separate `idOf`/`displayOf` functions and
splices `state "<display>" as <id>` declarations only for vertices whose display differs from
their id; `renderTopology` and `toMermaidWith` pass the same function twice, so `toMermaid`,
`toMermaidWith`, and every composite renderer stay byte-identical. The new public surface is
`MermaidStateLabels (..)`, `toMermaidWithLabels` (which drops the `Show s` constraint), and the
pure total `duplicateStateIds`. Four new tests in `test/Keiki/Render/MermaidSpec.hs` pin the
spaced-label rendering, the id==display byte-identity equivalence, and both duplicate-id cases;
the suite is green at 356 examples with all pre-existing goldens unchanged. The
`duplicateStateIds` AST-level check is the shared-id contract for EP-66, which will detect the
same collisions over rendered text. No core type changed; the work is confined to
`src/Keiki/Render/Mermaid.hs` and the spec. No deviations from the plan.


## Context and Orientation

keiki is a pure-Haskell library at `/Users/shinzui/Keikaku/bokuno/keiki`. The piece this
plan touches is the Mermaid renderer module `src/Keiki/Render/Mermaid.hs`. A *transducer*
here is a value of type `SymTransducer phi rs s ci co` (defined in `src/Keiki/Core.hs`,
around lines 666-671): a small state machine whose vertex type is `s`, with fields
`edgesOut :: s -> [Edge …]`, `initial :: s`, `initialRegs`, and `isFinal :: s -> Bool`.
The renderer turns such a value into a *Mermaid* `stateDiagram-v2` block — a chunk of text
in Mermaid's diagram language that GitHub, Notion, and Markdown previewers render as a
state-machine picture.

How the renderer works today. The public single-transducer entry point is `toMermaid`
(`src/Keiki/Render/Mermaid.hs:97-101`):

```haskell
toMermaid
  :: (Enum s, Bounded s, Show s)
  => SymTransducer (HsPred rs ci) rs s ci co
  -> Text
toMermaid = toMermaidWith defaultMermaidOptions
```

It defers to `toMermaidWith` (`Mermaid.hs:112-117`), which in turn calls the shared core
`renderTopologyWith`, passing it the vertex-label function `vertexLabel`:

```haskell
toMermaidWith
  :: (Enum s, Bounded s, Show s)
  => MermaidOptions
  -> SymTransducer (HsPred rs ci) rs s ci co
  -> Text
toMermaidWith opts = renderTopologyWith opts vertexLabel
```

`vertexLabel` (`Mermaid.hs:547-548`) is simply:

```haskell
vertexLabel :: Show s => s -> Text
vertexLabel = T.pack . show
```

The shared core `renderTopologyWith` (`Mermaid.hs:515-540`) is where the single use of the
label function happens. It enumerates every vertex with `[minBound .. maxBound]`, emits the
`stateDiagram-v2` header, then an initial-state line, one line per outgoing edge, and one
final-state line per vertex where `isFinal` returns `True`:

```haskell
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
```

The critical observation: the single function `label` is used in *three* places — the
initial-state line (`[*] --> label (initial t)`), both endpoints of every edge line
(`label s --> label (target e)`), and the final-state line (`label s --> [*]`). In every
one of those places, the text it produces serves simultaneously as the Mermaid identifier
*and* as the visible name. There is no display text distinct from the identifier today. The
reason this works for keiki's shipped aggregates is that their vertex types' `Show` output
(e.g. `PotentialCustomer`, `RequiresConfirmation`) already happens to be a legal Mermaid
identifier. The moment a caller wants spaces in the visible name, `Show`-as-identifier
breaks down.

The byte-identity invariant. The default output of `toMermaid` and `toMermaidWith
defaultMermaidOptions` is pinned by golden tests in
`test/Keiki/Render/MermaidSpec.hs`. For example `userRegCanonical`
(`MermaidSpec.hs:132-148`) pins, line for line, the block:

```text
stateDiagram-v2
    [*] --> PotentialCustomer
    PotentialCustomer --> RequiresConfirmation : StartRegistration / RegistrationStarted; ConfirmationEmailSent
    RequiresConfirmation --> Confirmed : ConfirmAccount / AccountConfirmed
    RequiresConfirmation --> RequiresConfirmation : ResendConfirmation / ConfirmationResent
    RequiresConfirmation --> Deleted : FulfillGDPRRequest / \x03B5
    Confirmed --> Deleted : FulfillGDPRRequest / AccountDeleted
    Deleted --> [*]
```

There are no `state "…" as …` declaration lines in that golden. This plan must not
introduce any such line in the default path; if it did, the golden would break. That is the
single hardest constraint in this plan and the reason for the "emit a declaration only when
display differs from id" rule described below.

The Mermaid syntax for splitting id from label. In Mermaid's `stateDiagram-v2`, a state
whose visible label differs from its identifier is declared once with the form:

```text
state "Display Label With Spaces" as StateId
```

After that declaration, transitions reference the bare identifier:

```text
StateId --> OtherId : edge label
```

Raw transition endpoints (and the `[*]` initial/final markers' partners) must be ASCII
identifiers with no spaces; the friendly label is attached only through the
`state "…" as Id` declaration. So to support spaced display labels the renderer must
(a) emit a `state "<display>" as <id>` declaration for each vertex whose display text
differs from its id, and (b) use the *id* in every transition line and every `[*]` marker.

This plan is one of six child plans under the MasterPlan at
`docs/masterplans/15-keiki-mermaid-diagram-and-documentation-rendering-improvements-surfaced-by-the-seihou-diagram-audit.md`.
Two facts from that MasterPlan matter here. First, `renderTopologyWith` is shared with the
other renderer plans (`docs/plans/61-…md` and `docs/plans/63-…md`), so the generalization
in this plan must keep `toMermaidWith` byte-identical or those plans' goldens would break.
Second, a sibling plan `docs/plans/66-pure-mermaid-diagram-and-atlas-validation-helpers.md`
detects duplicate state IDs in rendered diagram text and *soft-depends on this plan*: its
duplicate-ID check must key off the exact same identifier token this plan emits (the ASCII
id in the `state "…" as <id>` declaration and in the transition arrows). That shared
identifier token is the contract between the two plans.


## Plan of Work

The work splits the renderer's single label concept into two — an *identifier* and a
*display* — without changing anything observable on the default path. It is delivered in two
milestones: M1 introduces the split and the new `toMermaidWithLabels` entry point with
golden tests; M2 adds a small pure duplicate-id helper so this plan stands alone even if the
sibling validation plan (EP-66) is not yet done.

### Milestone M1 — the id/display split and `toMermaidWithLabels`

Scope. Generalize the shared core `renderTopologyWith` in `src/Keiki/Render/Mermaid.hs` so
that the Mermaid identifier and the visible display text are produced by *two* functions
rather than one. Add a public record `MermaidStateLabels s` carrying those two functions,
and a public entry point `toMermaidWithLabels` that uses it. Keep `toMermaidWith` (and thus
`toMermaid`) byte-identical by routing them through the same generalized core with both
functions set to `T.pack . show`, which guarantees display equals id and therefore *no*
`state "…" as …` lines are emitted. Add new golden cases in
`test/Keiki/Render/MermaidSpec.hs` demonstrating stable ASCII ids with spaced display
labels, and confirm every pre-existing golden is unchanged.

At the end of M1, the module exports `MermaidStateLabels (..)` and `toMermaidWithLabels`,
the test suite has a new describe block proving the labeled output, and the existing
goldens still pass.

The concrete edits, in order:

First, change the signature and body of `renderTopologyWith` so it accepts an
identifier function and a display function instead of one `label`. The cleanest minimal
form keeps `renderTopologyWith` taking two function arguments — call them `idOf :: s ->
Text` and `displayOf :: s -> Text` — and computes, before the existing initial/edge/final
lines, a list of *declaration* lines. A declaration line `state "<display>" as <id>` is
emitted for a vertex only when `displayOf s` differs from `idOf s`. When they are equal
(the `Show`-based default), the declaration list is empty, so the output is byte-identical
to today. The initial/edge/final lines all switch from `label` to `idOf`. The declarations,
when present, go between the header and the initial-state line. (Ordering choice recorded in
the Decision Log; declarations-before-initial is the natural reading order and is only ever
exercised by the new labeled path, so it cannot affect the byte-identical default.)

Second, because both `toMermaidWith` and `toMermaidComposite`-family functions call the
core, preserve their existing behavior. The composite renderers call `renderTopology`
(`Mermaid.hs:502-507`), which is `renderTopologyWith defaultMermaidOptions`. Update
`renderTopology` to pass the *same* function twice (e.g. `renderTopology label =
renderTopologyWith defaultMermaidOptions label label`) so `compositeLabel`,
`compose3Label`, and `feedback1Label` keep producing byte-identical output (display equals
id, no declarations). Likewise `toMermaidWith opts = renderTopologyWith opts vertexLabel
vertexLabel`.

Third, add the public record and entry point. The record holds the two callbacks; the entry
point drops the `Show s` constraint (labels come from the callbacks, not from `Show`):

```haskell
data MermaidStateLabels s = MermaidStateLabels
  { stateId           :: s -> Text
  , stateDisplayLabel :: s -> Text
  }

toMermaidWithLabels
  :: (Bounded s, Enum s)
  => MermaidOptions
  -> MermaidStateLabels s
  -> SymTransducer (HsPred rs ci) rs s ci co
  -> Text
toMermaidWithLabels opts lbls =
  renderTopologyWith opts (stateId lbls) (stateDisplayLabel lbls)
```

Fourth, add `MermaidStateLabels (..)` and `toMermaidWithLabels` to the module's export list
(`Mermaid.hs:25-44`).

Fifth, add golden tests in `test/Keiki/Render/MermaidSpec.hs` (it is already wired into
`keiki.cabal`'s test-suite `other-modules` at line 116 and into `test/Spec.hs` at line 57,
so no new file or wiring is needed). Add a describe block that renders `userReg` with
`MermaidStateLabels` mapping each vertex to a stable ASCII id and a spaced display label,
and pin the resulting block (which now contains `state "…" as …` lines). Add a second tiny
assertion that `toMermaidWithLabels` with an *identity-equal* labels record (id == display)
produces output byte-identical to `toMermaidWith` — proving the "no declaration when
display == id" rule directly. Confirm the pre-existing `userRegCanonical` golden and all
other goldens still pass unchanged.

Commands: from the repo root `/Users/shinzui/Keikaku/bokuno/keiki`, run `cabal build keiki`
then `cabal test keiki-test`. Acceptance: both succeed; the new labeled golden matches; the
existing goldens are untouched.

### Milestone M2 — local duplicate-id helper (recommended, self-containing)

Scope. Add a small, pure, total helper `duplicateStateIds` that, given a
`MermaidStateLabels s` and a transducer, returns the list of ASCII ids that collide (the
same id produced for two or more distinct vertices). This lets a caller detect the failure
mode the audit calls out — "duplicate generated IDs fail with a clear validation warning or
error" — without rendering being made partial: rendering itself never throws. Add a unit
test of a deliberately colliding labels record.

At the end of M2 the module additionally exports `duplicateStateIds`, and the spec has a
test asserting it returns the colliding id for a bad labels record and `[]` for a good one.

The duplicate-id detection in the sibling plan
`docs/plans/66-pure-mermaid-diagram-and-atlas-validation-helpers.md` operates over the
rendered diagram *text* and keys off the very same ASCII identifier token this plan emits.
This M2 helper is the AST-level counterpart, provided so this plan stands alone; the two
agree on what an "id" is by construction (both are exactly what `stateId` produces). If
EP-66 is already done when this plan is implemented, M2 may instead reference EP-66's
`validateMermaidDiagram` for the warning and keep `duplicateStateIds` as a thin convenience
— but the recommended path is to ship the local helper regardless, because it is tiny and
keeps this plan independent. Decision recorded in the Decision Log.

Commands: same as M1 (`cabal build keiki`, `cabal test keiki-test`). Acceptance: the suite
passes and the new duplicate-id test demonstrates a colliding-id case and a clean case.


## Concrete Steps

All commands run from the repository root `/Users/shinzui/Keikaku/bokuno/keiki`.

Step 1 — generalize `renderTopologyWith` to two label functions. Edit
`src/Keiki/Render/Mermaid.hs`. Replace the single `(s -> Text)` argument with two, and add
the conditional declaration lines. The diff (against the body shown in Context) is:

```diff
 renderTopologyWith
   :: (Enum s, Bounded s)
   => MermaidOptions
-  -> (s -> Text)
+  -> (s -> Text)          -- ^ idOf: the stable Mermaid identifier
+  -> (s -> Text)          -- ^ displayOf: the visible display label
   -> SymTransducer (HsPred rs ci) rs s ci co
   -> Text
-renderTopologyWith opts label t =
+renderTopologyWith opts idOf displayOf t =
   let vertices  = [minBound .. maxBound]
       header    = T.pack "stateDiagram-v2"
       ind       = T.pack "    "
       arrow     = T.pack " --> "
       colon     = T.pack " : "
-      initLine  = ind <> T.pack "[*]" <> arrow <> label (initial t)
+      -- A declaration is emitted ONLY when the display differs from the
+      -- id; when they are equal (the Show-based default) this list is
+      -- empty, so the default output stays byte-identical.
+      declLines =
+        [ ind <> T.pack "state \"" <> displayOf s <> T.pack "\" as " <> idOf s
+        | s <- vertices
+        , displayOf s /= idOf s
+        ]
+      initLine  = ind <> T.pack "[*]" <> arrow <> idOf (initial t)
       edgeLines =
-        [ ind <> label s <> arrow
-              <> label (target e) <> colon <> edgeLabelWith opts e
+        [ ind <> idOf s <> arrow
+              <> idOf (target e) <> colon <> edgeLabelWith opts e
         | s <- vertices
         , e <- edgesOut t s
         ]
       finalLines =
-        [ ind <> label s <> arrow <> T.pack "[*]"
+        [ ind <> idOf s <> arrow <> T.pack "[*]"
         | s <- vertices
         , isFinal t s
         ]
   in T.intercalate (T.pack "\n")
-       (header : initLine : edgeLines ++ finalLines)
+       (header : declLines ++ initLine : edgeLines ++ finalLines)
```

Note `declLines` is spliced between the header and the initial-state line. On the default
path it is `[]`, so `header : [] ++ initLine : …` is exactly `header : initLine : …` — the
original list, byte-for-byte.

Step 2 — keep the convenience wrappers byte-identical. Still in
`src/Keiki/Render/Mermaid.hs`, update `renderTopology` and `toMermaidWith` to pass the same
function twice:

```diff
 renderTopology
   :: (Enum s, Bounded s)
   => (s -> Text)
   -> SymTransducer (HsPred rs ci) rs s ci co
   -> Text
-renderTopology = renderTopologyWith defaultMermaidOptions
+renderTopology label = renderTopologyWith defaultMermaidOptions label label
```

```diff
 toMermaidWith
   :: (Enum s, Bounded s, Show s)
   => MermaidOptions
   -> SymTransducer (HsPred rs ci) rs s ci co
   -> Text
-toMermaidWith opts = renderTopologyWith opts vertexLabel
+toMermaidWith opts = renderTopologyWith opts vertexLabel vertexLabel
```

`toMermaid` is unchanged (it already defers to `toMermaidWith`). The composite renderers
that call `renderTopology` (`toMermaidComposite`, `toMermaidCompose3`, `toMermaidFeedback1`)
are unchanged because `renderTopology`'s signature is unchanged.

Step 3 — add the record and the new entry point. Insert near `toMermaidWith` in
`src/Keiki/Render/Mermaid.hs`:

```haskell
-- | A pair of per-vertex label functions for 'toMermaidWithLabels'.
-- 'stateId' produces the stable ASCII Mermaid identifier used as a node
-- id and in every transition arrow; it is the caller's responsibility to
-- return a legal Mermaid identifier ([A-Za-z_][A-Za-z0-9_]*).
-- 'stateDisplayLabel' produces the friendly visible label, which may
-- contain spaces. When the two differ for a vertex, the renderer emits a
-- @state "<display>" as <id>@ declaration.
data MermaidStateLabels s = MermaidStateLabels
  { stateId           :: s -> Text
  , stateDisplayLabel :: s -> Text
  }

-- | Like 'toMermaidWith', but the caller supplies separate stable
-- identifiers and friendly display labels via 'MermaidStateLabels'
-- instead of deriving both from 'Show'. The 'Show s' constraint is
-- dropped: labels come from the callbacks. The default 'toMermaid' /
-- 'toMermaidWith' path is unaffected.
toMermaidWithLabels
  :: (Bounded s, Enum s)
  => MermaidOptions
  -> MermaidStateLabels s
  -> SymTransducer (HsPred rs ci) rs s ci co
  -> Text
toMermaidWithLabels opts lbls =
  renderTopologyWith opts (stateId lbls) (stateDisplayLabel lbls)
```

Step 4 — export the new names. Edit the export list (`Mermaid.hs:25-44`):

```diff
   , toMermaidWith
+  , toMermaidWithLabels
   , MermaidOptions (..)
+  , MermaidStateLabels (..)
   , defaultMermaidOptions
```

Step 5 — build:

```bash
cabal build keiki
```

Expected: a clean build. If GHC complains that `renderTopologyWith` is applied with the old
arity somewhere, search for remaining single-argument call sites:

```bash
grep -n "renderTopologyWith\|renderTopology " src/Keiki/Render/Mermaid.hs
```

and fix them to pass two functions (or, for `renderTopology`, the wrapper from Step 2).

Step 6 — add golden tests. Edit `test/Keiki/Render/MermaidSpec.hs`. Add
`toMermaidWithLabels` and `MermaidStateLabels (..)` to the `Keiki.Render.Mermaid` import
list (`MermaidSpec.hs:54-66`). Add the describe blocks and the canonical fixtures. A worked
example mapping `userReg`'s vertices to stable ids and spaced labels:

```haskell
  describe "toMermaidWithLabels (stable ASCII ids, spaced display labels)" $
    it "renders userReg with friendly labels and stable ids" $
      toMermaidWithLabels defaultMermaidOptions userRegLabels userReg
        `shouldBe` userRegLabeledCanonical

  describe "toMermaidWithLabels (id == display is byte-identical)" $
    it "equals toMermaidWith when stateId == stateDisplayLabel" $
      toMermaidWithLabels defaultMermaidOptions
        (MermaidStateLabels { stateId = vertexLabelShow
                            , stateDisplayLabel = vertexLabelShow })
        userReg
        `shouldBe` toMermaidWith defaultMermaidOptions userReg
```

with the supporting definitions (the display strings deliberately contain spaces; the ids
stay ASCII identifiers):

```haskell
-- Map each userReg vertex to a stable id and a friendly spaced label.
userRegLabels :: MermaidStateLabels UserRegState
userRegLabels = MermaidStateLabels
  { stateId           = T.pack . show           -- e.g. "PotentialCustomer"
  , stateDisplayLabel = friendly
  }
  where
    friendly s = case show s of
      "PotentialCustomer"    -> T.pack "Potential Customer"
      "RequiresConfirmation" -> T.pack "Requires Confirmation"
      "Confirmed"            -> T.pack "Confirmed"
      "Deleted"              -> T.pack "Deleted"
      other                  -> T.pack other

vertexLabelShow :: Show s => s -> Text
vertexLabelShow = T.pack . show
```

(Use `userReg`'s actual vertex type name in the annotation; if it is not directly importable,
drop the annotation and let it be inferred, or use `vertexLabel` from the renderer module
for the identity case instead of a local `vertexLabelShow`.) The canonical labeled block —
note `Confirmed` and `Deleted` get *no* declaration line because their display equals their
id, while the two spaced labels do:

```haskell
userRegLabeledCanonical :: Text
userRegLabeledCanonical = T.intercalate (T.pack "\n")
  [ "stateDiagram-v2"
  , "    state \"Potential Customer\" as PotentialCustomer"
  , "    state \"Requires Confirmation\" as RequiresConfirmation"
  , "    [*] --> PotentialCustomer"
  , "    PotentialCustomer --> RequiresConfirmation : StartRegistration / RegistrationStarted; ConfirmationEmailSent"
  , "    RequiresConfirmation --> Confirmed : ConfirmAccount / AccountConfirmed"
  , "    RequiresConfirmation --> RequiresConfirmation : ResendConfirmation / ConfirmationResent"
  , "    RequiresConfirmation --> Deleted : FulfillGDPRRequest / \x03B5"
  , "    Confirmed --> Deleted : FulfillGDPRRequest / AccountDeleted"
  , "    Deleted --> [*]"
  ]
```

Generate this fixture authoritatively rather than hand-copying: run the renderer at the REPL
(see Step 8) and paste its output. The block above is the expected shape.

Step 7 — run the suite:

```bash
cabal test keiki-test
```

Expected: all examples pass, including the pre-existing `toMermaid (single SymTransducer)`
golden and the new `toMermaidWithLabels` blocks. A short expected transcript fragment:

```text
Keiki.Render.Mermaid (EP-30, EP-31, EP-32, EP-33)
  toMermaid (single SymTransducer)
    renders userReg to the canonical stateDiagram-v2 block [✔]
  ...
  toMermaidWithLabels (stable ASCII ids, spaced display labels)
    renders userReg with friendly labels and stable ids [✔]
  toMermaidWithLabels (id == display is byte-identical)
    equals toMermaidWith when stateId == stateDisplayLabel [✔]
```

Step 8 — (optional) regenerate the fixture at the REPL if `userReg`'s topology ever changes:

```bash
cabal repl keiki-test
```

```text
ghci> import qualified Data.Text.IO as TIO
ghci> import Keiki.Render.Mermaid
ghci> import Keiki.Fixtures.UserRegistration (userReg)
ghci> TIO.putStrLn (toMermaidWithLabels defaultMermaidOptions userRegLabels userReg)
```

Paste the printed block into `userRegLabeledCanonical`.

Step 9 (M2) — add the duplicate-id helper. In `src/Keiki/Render/Mermaid.hs` add:

```haskell
-- | Return the ASCII ids that collide: any id produced by 'stateId' for
-- two or more distinct vertices. Empty means every vertex maps to a
-- unique id. Rendering itself stays total; this is the AST-level check a
-- caller can run before trusting a labeled diagram. The sibling plan
-- docs/plans/66-...md detects the same collisions over rendered text and
-- keys off the same id token.
duplicateStateIds
  :: (Bounded s, Enum s)
  => MermaidStateLabels s
  -> SymTransducer (HsPred rs ci) rs s ci co
  -> [Text]
duplicateStateIds lbls _t =
  let ids = map (stateId lbls) [minBound .. maxBound]
  in [ i | (i, n) <- countOccurrences ids, n > (1 :: Int) ]
  where
    countOccurrences xs =
      [ (x, length (filter (== x) xs)) | x <- nubOrd xs ]
    nubOrd = foldr (\x acc -> if x `elem` acc then acc else x : acc) []
```

(The transducer argument is currently unused beyond fixing `s`; keep it so the signature
matches a caller's mental model "ids for this transducer's vertices" and so a future
implementation could restrict to reachable vertices without an API change. `Data.List.nub`
is acceptable instead of the local `nubOrd` if `Data.List` is already imported; no new
dependency is needed either way — the result order is the first-occurrence order.) Export
`duplicateStateIds` from the module. Add a test:

```haskell
  describe "duplicateStateIds" $ do
    it "is empty for a unique-id labels record" $
      duplicateStateIds userRegLabels userReg `shouldBe` []
    it "reports the colliding id for a clashing labels record" $
      duplicateStateIds collidingLabels userReg
        `shouldBe` [T.pack "X"]
```

with `collidingLabels = MermaidStateLabels { stateId = const (T.pack "X"), stateDisplayLabel = T.pack . show }`
(every vertex maps to the single id `"X"`, so `"X"` is reported once).


## Validation and Acceptance

The behavior to verify is: a caller can render the same transducer two ways and observe that
(1) the default rendering is unchanged from today and (2) the labeled rendering attaches
spaced display labels via `state "…" as …` declarations while keeping stable ASCII ids in
the arrows.

Default unchanged. From `/Users/shinzui/Keikaku/bokuno/keiki`, `cabal test keiki-test` must
keep the pre-existing `toMermaid (single SymTransducer)` golden passing. That golden pins,
byte-for-byte, this default block (no `state "…" as …` lines anywhere):

```text
stateDiagram-v2
    [*] --> PotentialCustomer
    PotentialCustomer --> RequiresConfirmation : StartRegistration / RegistrationStarted; ConfirmationEmailSent
    RequiresConfirmation --> Confirmed : ConfirmAccount / AccountConfirmed
    RequiresConfirmation --> RequiresConfirmation : ResendConfirmation / ConfirmationResent
    RequiresConfirmation --> Deleted : FulfillGDPRRequest / ε
    Confirmed --> Deleted : FulfillGDPRRequest / AccountDeleted
    Deleted --> [*]
```

Labeled output. `toMermaidWithLabels defaultMermaidOptions userRegLabels userReg` must
produce the block below: two declaration lines (only for the two vertices whose display
differs from id), then the same topology with stable ASCII ids in every arrow:

```text
stateDiagram-v2
    state "Potential Customer" as PotentialCustomer
    state "Requires Confirmation" as RequiresConfirmation
    [*] --> PotentialCustomer
    PotentialCustomer --> RequiresConfirmation : StartRegistration / RegistrationStarted; ConfirmationEmailSent
    RequiresConfirmation --> Confirmed : ConfirmAccount / AccountConfirmed
    RequiresConfirmation --> RequiresConfirmation : ResendConfirmation / ConfirmationResent
    RequiresConfirmation --> Deleted : FulfillGDPRRequest / ε
    Confirmed --> Deleted : FulfillGDPRRequest / AccountDeleted
    Deleted --> [*]
```

The acceptance points to confirm by eye: the visible labels `"Potential Customer"` and
`"Requires Confirmation"` contain spaces (impossible as raw identifiers), yet every arrow
still uses the ASCII id (`PotentialCustomer`, `RequiresConfirmation`), and `Confirmed` /
`Deleted` got no declaration line because their display already equals their id.

Byte-identity proof in-suite. The `toMermaidWithLabels (id == display is byte-identical)`
example asserts that feeding identical id/display functions yields exactly
`toMermaidWith defaultMermaidOptions userReg`. This is the direct, mechanical proof of the
"no declaration when display == id" rule.

Duplicate-id detection (M2). `duplicateStateIds userRegLabels userReg` returns `[]` (all ids
unique), and `duplicateStateIds collidingLabels userReg` returns `[T.pack "X"]` (every
vertex collided onto the single id `"X"`). This demonstrates the audit's
"duplicate generated IDs … validation" acceptance without making rendering partial.

The exact commands, run from `/Users/shinzui/Keikaku/bokuno/keiki`:

```bash
cabal build keiki
cabal test keiki-test
```

Success is a clean build and a green suite in which the new describe blocks and every
pre-existing golden pass.


## Idempotence and Recovery

Every step is a pure source edit followed by a rebuild and re-test; there is no migration,
no I/O, and no destructive operation. `cabal build keiki` and `cabal test keiki-test` are
safe to run any number of times.

If a pre-existing golden breaks after Step 1, the cause is almost certainly that a
declaration line leaked into the default path. Recheck the `displayOf s /= idOf s` guard in
`declLines` and that `renderTopology`/`toMermaidWith` pass the same function twice (Step 2):
when id equals display the guard filters out every declaration and the spliced list is
empty. Revert is `git checkout -- src/Keiki/Render/Mermaid.hs test/Keiki/Render/MermaidSpec.hs`.

If the new labeled golden mismatches, regenerate it from the REPL (Concrete Steps, Step 8)
and paste the authoritative output rather than hand-editing — the only legitimate variation
is the exact display strings you chose.

Re-running the implementation against an already-implemented tree is a no-op: the exports,
record, and entry point either already exist (the edits are exact-match) or are added once.


## Interfaces and Dependencies

This plan adds no new package dependency. It uses only `text` (`Data.Text`), already a
dependency of `src/Keiki/Render/Mermaid.hs`, and `Keiki.Core` types (`SymTransducer`,
`HsPred`, `Edge`, etc.) already imported there. The whole change is pure; there is no z3 or
solver involvement (the renderer is pure text assembly).

After Milestone M1, `src/Keiki/Render/Mermaid.hs` must export and define:

```haskell
data MermaidStateLabels s = MermaidStateLabels
  { stateId           :: s -> Text
  , stateDisplayLabel :: s -> Text
  }

toMermaidWithLabels
  :: (Bounded s, Enum s)
  => MermaidOptions
  -> MermaidStateLabels s
  -> SymTransducer (HsPred rs ci) rs s ci co
  -> Text
```

and the internal core must have the generalized shape:

```haskell
renderTopologyWith
  :: (Enum s, Bounded s)
  => MermaidOptions
  -> (s -> Text)   -- idOf
  -> (s -> Text)   -- displayOf
  -> SymTransducer (HsPred rs ci) rs s ci co
  -> Text
```

with `toMermaidWith opts = renderTopologyWith opts vertexLabel vertexLabel` and
`renderTopology label = renderTopologyWith defaultMermaidOptions label label`, so that
`toMermaid`, `toMermaidWith`, and every composite renderer (`toMermaidComposite`,
`toMermaidCompose3`, `toMermaidFeedback1`, and their nested variants) stay byte-identical.

After Milestone M2, the module must additionally export and define:

```haskell
duplicateStateIds
  :: (Bounded s, Enum s)
  => MermaidStateLabels s
  -> SymTransducer (HsPred rs ci) rs s ci co
  -> [Text]
```

Integration contract with siblings. The ASCII identifier token that `stateId` produces (and
that appears in the `state "<display>" as <id>` declaration and in every transition arrow)
is the shared contract with `docs/plans/66-pure-mermaid-diagram-and-atlas-validation-helpers.md`:
EP-66's duplicate-state-ID warning, which scans rendered diagram text, must key off exactly
this token. The generalized `renderTopologyWith` is shared with
`docs/plans/61-...md` and `docs/plans/63-...md`; the byte-identity of `toMermaidWith` is the
invariant those plans rely on, so the two-function generalization here must not change the
default bytes. No other plan calls `toMermaidWithLabels` or `duplicateStateIds`; they are
purely additive to the public surface.
