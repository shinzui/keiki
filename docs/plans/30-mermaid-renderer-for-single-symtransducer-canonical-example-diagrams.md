---
id: 30
slug: mermaid-renderer-for-single-symtransducer-canonical-example-diagrams
title: "Mermaid renderer for single SymTransducer + canonical example diagrams"
kind: exec-plan
created_at: 2026-05-03T04:05:34Z
intention: "intention_01kqnh7tc1epwvtrf6fnt8jt3t"
master_plan: "docs/masterplans/10-mermaid-topology-renderer-for-symtransducer.md"
---

# Mermaid renderer for single SymTransducer + canonical example diagrams

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this plan ships, a keiki user with a `SymTransducer` value `t` can call
`Keiki.Render.Mermaid.toMermaid t` and get back a `Data.Text.Text` containing a
Mermaid `stateDiagram-v2` block that describes the transducer's full control
topology. That block can be pasted into a Markdown file or a Notion page and
rendered inline — GitHub renders Mermaid fences natively, so a reviewer reading a
PR sees the diagram without running any code.

A **transducer** in keiki is a finite state machine with typed registers and
typed input / output alphabets, defined in `src/Keiki/Core.hs` as the record
`SymTransducer phi rs s ci co`. **Topology** here means the four pieces a state
diagram needs: the set of vertices (the values of `s`), the initial vertex, the
final vertices, and one labelled arrow per outgoing edge. The edge label
`<input ctor> / <output ctor>` (e.g. `StartRegistration / RegistrationStarted`)
is what a domain expert reads to understand "command in, event out" without
opening Haskell. ε-edges (edges that consume an input but emit no event) are
labelled `<input ctor> / ε`.

Concretely, after this plan a contributor can:

1. In `ghci` (or any module that imports the library):

       ghci> import Keiki.Render.Mermaid (toMermaid)
       ghci> import Keiki.Examples.UserRegistration (userReg)
       ghci> import qualified Data.Text.IO as TIO
       ghci> TIO.putStrLn (toMermaid userReg)
       stateDiagram-v2
           [*] --> PotentialCustomer
           PotentialCustomer --> Registering : StartRegistration / RegistrationStarted
           Registering --> RequiresConfirmation : Continue / ConfirmationEmailSent
           RequiresConfirmation --> Confirmed : ConfirmAccount / AccountConfirmed
           RequiresConfirmation --> RequiresConfirmation : ResendConfirmation / ConfirmationResent
           RequiresConfirmation --> Deleted : FulfillGDPRRequest / ε
           Confirmed --> Deleted : FulfillGDPRRequest / AccountDeleted
           Deleted --> [*]

2. Open `docs/guide/diagrams/user-registration.md` in any Markdown previewer
   (GitHub, VS Code's preview, Notion) and see the same four-vertex lifecycle
   rendered as a state diagram.

3. Run `cabal test` and observe `Keiki.Render.Mermaid` pass an exact-match
   regression test pinning `userReg`'s rendered output (so any accidental
   formatting change surfaces in CI).

The MasterPlan
`docs/masterplans/10-mermaid-topology-renderer-for-symtransducer.md`
motivates this: the futures note (`docs/research/future-directions-profunctors-effects-and-composition.md`
§5) and the crem comparison
(`docs/research/architecture-comparison-keiki-vs-crem.md`) both flag
diagram rendering as a "domain-expert communication" gap. This plan closes that
gap for single transducers; the sibling plan
`docs/plans/31-mermaid-rendering-for-composite-symtransducers.md` extends it
to composite transducers.


## Progress

- [x] M0 — Verify prerequisites: `cabal build all` and `cabal test` pass on
      master; record GHC version and z3 availability in Surprises.
      *(2026-05-03: GHC 9.12.3, z3 4.16.0; `cabal build all` Up to date;
      `cabal test` 196 examples, 0 failures.)*
- [x] M1+M2 — Add `src/Keiki/Render/Mermaid.hs` (module + cabal entry +
      real implementation: `toMermaid`, `vertexLabel`, `edgeInputName`,
      `edgeOutputName`, `edgeLabel`); covers initial vertex, final
      vertices, ε-edges, and self-loops; ghci on `userReg` produces the
      canonical block from this plan's Purpose section. M1 was rolled
      into M2 because the placeholder body in M1 triggered
      `-Wredundant-constraints` warnings — the real bodies in M2 use
      the constraints, so the skeleton-only commit was not useful as a
      separate buildable step. *(2026-05-03.)*
- [x] M3 — Render diagrams for `UserRegistration`, `OrderCart`,
      `EmailDelivery`, `UserRegistrationV0`; check in to
      `docs/guide/diagrams/`. *(2026-05-03: four files exist under
      `docs/guide/diagrams/`, each containing the canonical Mermaid
      block produced by `toMermaid` over the corresponding aggregate.)*
- [x] M4 — Add `test/Keiki/Render/MermaidSpec.hs` pinning canonical Mermaid
      output for `userReg`; wire into `test/Spec.hs`; add to `keiki.cabal`
      test-suite `other-modules`; `cabal test` passes. *(2026-05-03:
      `cabal test` reports 197 examples, 0 failures; describe block
      `Keiki.Render.Mermaid (EP-30) -> toMermaid (single SymTransducer) ->
      renders userReg to the canonical stateDiagram-v2 block` is green.
      Anti-validation: temporarily editing the expected `ε` to `EPSILON`
      produced a clear `expected … but got …` diff with both strings
      printed; reverted before commit.)*


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- 2026-05-03 — M0 baseline: GHC 9.12.3, z3 4.16.0. `cabal build all` is
  "Up to date" (no rebuild needed). `cabal test` reports `196 examples,
  0 failures` in `0.3239 seconds`. Suite passes; safe to add the renderer
  module on top of this baseline.

- 2026-05-03 — M1's placeholder `toMermaid _ = T.empty` triggers
  `-Wredundant-constraints` on the `(Enum s, Bounded s, Show s)` triple
  because the body never uses them. Two options: add a temporary
  `{-# OPTIONS_GHC -Wno-redundant-constraints #-}` for the M1-only
  skeleton, or roll M1 and M2 into one commit. Picked the latter — the
  skeleton-only milestone offers nothing observable beyond "module
  parses," and the real implementation in M2 uses the constraints
  meaningfully, so the warning evaporates.

- 2026-05-03 — Render of `Keiki.Examples.OrderCart.orderCart` produces
  a 13-edge, 8-vertex diagram. Hand-inspection against the source file
  (`src/Keiki/Examples/OrderCart.hs`) confirms every edge is accounted
  for: `OpenWithItems` self-loops on `AddItem` / `RemoveItem` /
  `ApplyDiscount` are present, the `Cancel` branches at `OpenWithItems`
  / `Reserved` are both there, and the three terminal vertices
  (`Delivered`, `Cancelled`, `Refunded`) all carry final markers. No
  ε-edges in this aggregate. Useful as a wider stress-test of the
  renderer beyond the smaller `userReg` fixture used by M4.


## Decision Log

- Decision: Constraint discipline on `s` is `(Enum, Bounded, Show)`.
  Rationale: `Keiki.Core.checkHiddenInputs` already requires this triple to
  walk the vertex set, so users who already have a `SymTransducer` whose
  topology is enumerable have all three. `Show` is what we use to derive the
  vertex label (Mermaid identifier). All four shipped Examples modules
  (`UserRegistration`, `OrderCart`, `EmailDelivery`, `UserRegistrationV0`)
  already derive these three, so no churn.
  Date: 2026-05-03

- Decision: The renderer is specialised to `phi ~ HsPred rs ci` rather than
  abstracted over an arbitrary `BoolAlg phi a` carrier.
  Rationale: extracting the input-constructor name from the guard requires
  walking the guard's AST for a `PInCtor` atom. `HsPred` is the only first-
  class guard AST in the repository today (`src/Keiki/Core.hs` defines it;
  `src/Keiki/Symbolic.hs` introduces an SBV-backed translation but the
  user-facing carrier remains `HsPred`). Abstracting now would require either
  a new typeclass with no other instances or threading the input name through
  the guard at construction time. A future extension can introduce
  `class MermaidEdgeLabel phi where inputCtorName :: phi -> Maybe Text` if a
  second carrier appears; for v1 the concrete signature is simpler and
  matches every aggregate the repo currently ships.
  Date: 2026-05-03

- Decision: Edge label format is `<input ctor> / <output ctor>` (or
  `<input ctor> / ε` for ε-edges). If no `PInCtor` atom is found in the
  guard, the input side is omitted and the label is just `/ <output ctor>`
  (or just `/ ε`).
  Rationale: matches the MasterPlan's IP-2 contract. The `Builder.onCmd`
  combinator (`src/Keiki/Builder.hs`) wraps every edge guard in
  `PAnd (PInCtor ic) ...`, so every aggregate authored through the builder
  has a recoverable input name. Hand-AST-authored edges may omit `PInCtor`
  (the legacy `userRegAST` form does not — its guards are `isStart`,
  `isContinue` etc., which TH-derive to `PInCtor` atoms internally) but the
  fallback keeps the renderer total.
  Date: 2026-05-03

- Decision: Diagrams are checked in under `docs/guide/diagrams/` as one
  Markdown file per aggregate, each containing a short header and a fenced
  ` ```mermaid ` code block.
  Rationale: the existing topic guides (`user-guide.md`, `composition.md`,
  etc.) are prose narratives where mid-paragraph diagrams would interrupt
  flow. A separate `diagrams/` folder gives reviewers a single place to look
  for "show me the topology of X" and keeps the prose guides focused on
  composition / view / symbolic explanations. The MasterPlan's IP-3 leaves
  this choice to EP-30.
  Date: 2026-05-03

- Decision: Diagram files are hand-baked from `toMermaid`'s output rather
  than generated by a build step.
  Rationale: a generator (Setup hook, cabal-run target) adds dependency-
  tracking complexity for four small files that change only when the
  underlying aggregate's topology changes. The regression test pinning
  `userReg`'s rendered output catches accidental formatting drift; if it
  fails, the author re-runs `toMermaid` in `ghci` to refresh the four
  diagram files. A future `keiki-render` executable can subsume this if a
  larger fleet of aggregates needs it.
  Date: 2026-05-03


## Outcomes & Retrospective

**2026-05-03 — Plan complete (M0..M4).**

What shipped:

- `src/Keiki/Render/Mermaid.hs` — exports `toMermaid`, `vertexLabel`,
  `edgeInputName`, `edgeOutputName`, `edgeLabel`. Rendering specialised
  to `phi ~ HsPred rs ci`; `(Enum, Bounded, Show)` constraint discipline
  on `s`. Edge label format `<input ctor> / <output ctor>` (or `/ ε`).
- `keiki.cabal` — `Keiki.Render.Mermaid` added to library
  `exposed-modules`; `Keiki.Render.MermaidSpec` added to test-suite
  `other-modules`. No new `build-depends`.
- `docs/guide/diagrams/{user-registration,user-registration-v0,email-delivery,order-cart}.md`
  — four canonical example diagrams checked in as Mermaid source in
  Markdown so GitHub renders them inline.
- `test/Keiki/Render/MermaidSpec.hs` + `test/Spec.hs` — regression test
  pinning the `userReg` block; `cabal test` reports 197 examples,
  0 failures.

Lessons / observations:

- The `M1` skeleton-only milestone was rolled into `M2` because GHC's
  `-Wredundant-constraints` warned on the placeholder body — the
  intermediate "module parses but does nothing" commit offered no value
  beyond the no-warnings guarantee `M2` already provides. Future plans
  with a "skeleton then implementation" split should either accept the
  warning under `OPTIONS_GHC` for the skeleton commit or skip the split
  entirely.
- The four shipped Examples aggregates (UserRegistration,
  UserRegistrationV0, EmailDelivery, OrderCart) all used the
  Builder-form `B.onCmd` for every edge, so 100 % of edges had a
  recoverable input-constructor name; the `?` fallback in `edgeLabel`
  was never triggered. Hand-written-AST aggregates (none in the repo
  today) would be the primary use case for that fallback.
- `OrderCart` proved a useful breadth test — 13 edges, 8 vertices,
  three terminal states, several self-loops. The output renders cleanly
  in GitHub's Markdown previewer with no manual layout adjustment.
- The renderer relied only on `text` (already a dep). No new
  `build-depends`.

Open follow-ups for `EP-31`:

- The composite case (`Composite s1 s2`) is not handled by `toMermaid`
  — its constraint discipline rejects the composite vertex's `Show`
  output (`"Composite a b"` contains spaces, not legal Mermaid
  identifiers). `EP-31` will add a `toMermaidComposite` variant that
  either flat-cross-products the labels (`<show s1>_<show s2>`) or
  uses Mermaid's nested-state syntax. The choice is deferred to
  `EP-31`'s M1 by the MasterPlan.


## Context and Orientation

This section names the files, types, and combinators a novice needs to
understand before implementing.

**Repository layout.** This is a Haskell library project built with `cabal`
(see `keiki.cabal`). Sources live under `src/`, tests under `test/`,
benchmarks under `bench/`. The library module hierarchy starts at
`Keiki.*`. Build / test commands:

    cabal build all
    cabal test

The project compiles with GHC 9.12.x (per `tested-with` in `keiki.cabal`).
The Nix flake (`flake.nix`) provides a development shell with the right GHC
and `z3` (z3 is needed for the symbolic analyses in `Keiki.Symbolic` but
*not* for this plan; pure rendering uses no SMT).

**`SymTransducer`.** Defined in `src/Keiki/Core.hs`:

    data SymTransducer phi rs s ci co = SymTransducer
      { edgesOut    :: s -> [Edge phi rs ci co s]
      , initial     :: s
      , initialRegs :: RegFile rs
      , isFinal     :: s -> Bool
      }

`s` is the vertex (control) type — for `Keiki.Examples.UserRegistration` it
is the data type `Vertex = PotentialCustomer | Registering |
RequiresConfirmation | Confirmed | Deleted` deriving `Eq, Show, Enum,
Bounded`. `phi` is the guard carrier (the boolean algebra used for edge
guards); for every shipped aggregate it is `HsPred rs ci`. `rs` is the
register-file slot list. `ci` and `co` are the input (command) and output
(event) types.

**`Edge`.** Same file:

    data Edge phi rs ci co s where
      Edge
        :: { guard  :: phi
           , update :: Update rs w ci
           , output :: Maybe (OutTerm rs ci co)
           , target :: s
           }
        -> Edge phi rs ci co s

The renderer needs `target` (the next vertex), `guard` (to extract the
input-constructor name), and `output` (to extract the output-constructor
name; `Nothing` ⇒ ε-edge).

**`HsPred`.** Same file. The renderer's input-name extractor walks this
AST:

    data HsPred (rs :: [Slot]) (ci :: Type) where
      PTop    :: HsPred rs ci
      PBot    :: HsPred rs ci
      PAnd    :: HsPred rs ci -> HsPred rs ci -> HsPred rs ci
      POr     :: HsPred rs ci -> HsPred rs ci -> HsPred rs ci
      PNot    :: HsPred rs ci -> HsPred rs ci
      PEq     :: (Eq r, Typeable r)
              => Term rs ci r -> Term rs ci r -> HsPred rs ci
      PInCtor :: InCtor ci ifs -> HsPred rs ci

The `PInCtor` constructor wraps an `InCtor` whose `icName :: String` is
the user-visible name of the command constructor (e.g. `"StartRegistration"`).
The Builder layer always emits the guard as `PAnd (PInCtor ic) inner` for
edges introduced via `Builder.onCmd`, so a leftmost-PInCtor walk recovers
the name.

**`InCtor`.** Same file:

    data InCtor ci (ifs :: [Slot]) where
      InCtor
        :: ...
        => { icName  :: String
           , icMatch :: ci -> Maybe (RegFile ifs)
           , icBuild :: RegFile ifs -> ci
           }
        -> InCtor ci ifs

The renderer reads `icName` only.

**`OutTerm`.** Same file:

    data OutTerm (rs :: [Slot]) (ci :: Type) (co :: Type) where
      OPack :: InCtor ci ifs
            -> WireCtor co fields
            -> OutFields rs ci fields
            -> OutTerm rs ci co

The renderer reads `wcName :: String` from the `WireCtor` only:

    data WireCtor co fields = WireCtor
      { wcName  :: String
      , wcMatch :: co -> Maybe fields
      , wcBuild :: fields -> co
      }

**`Edge`'s existential update.** The `update` field of `Edge` carries an
`Update rs w ci` whose `w :: [Symbol]` is existentially quantified, so
GHC rejects naked uses of `update e` outside a pattern match. The
renderer never reads `update`, so this restriction does not apply here.

**Builder layer.** `src/Keiki/Builder.hs` is a do-notation surface for
authoring transducers. Every `B.onCmd inCtor $ \d -> ...` call produces an
edge whose `guard` is `PAnd (PInCtor inCtor) <inner>` where `<inner>` is
the `requireEq` / `requireXyz` predicates the body adds. So every
builder-authored edge has a recoverable input-constructor name.

**Existing examples.** Four shipped aggregates all derive `Eq, Show, Enum,
Bounded` on their vertex type and use `HsPred` for `phi`:

- `Keiki.Examples.UserRegistration.userReg` — five vertices
  (`PotentialCustomer`, `Registering`, `RequiresConfirmation`,
  `Confirmed`, `Deleted`); `Deleted` is final; one ε-edge
  (`RequiresConfirmation` → `Deleted` on `FulfillGDPRRequest`); seven
  edges total.
- `Keiki.Examples.UserRegistrationV0.userRegV0` — same shape but with the
  v0 (synthesis §4 unfixed) `AccountConfirmed` schema.
- `Keiki.Examples.EmailDelivery.emailDelivery` — two vertices
  (`EmailPending`, `EmailSentVertex`); `EmailSentVertex` is final; one
  edge.
- `Keiki.Examples.OrderCart.orderCart` — eight or nine vertices in an
  Empty → OpenWithItems → Reserved → Paid → Shipped → Delivered + Cancelled
  / Refunded lifecycle. (Read the file for the exact list before producing
  the diagram.)

**Existing test layout.** `test/Spec.hs` registers every spec module with
hspec under a `describe` block. Spec modules export `spec :: Spec`. New
spec modules must be listed in `keiki.cabal` under
`test-suite keiki-test.other-modules`. Run `cabal test` from the repo root.

**Existing docs/guide layout.** `docs/guide/` currently holds five topic
guides in plain Markdown:

    docs/guide/ast-drop-down.md
    docs/guide/b-views.md
    docs/guide/composition.md
    docs/guide/profunctor.md
    docs/guide/symbolic-ci.md
    docs/guide/user-guide.md

This plan adds `docs/guide/diagrams/` as a sibling folder.

**Mermaid `stateDiagram-v2` syntax cheatsheet.** What this plan needs to
emit:

    stateDiagram-v2
        [*] --> Initial
        Initial --> Other : Label
        Other --> Other : Self-loop label
        Other --> [*]

Indentation under the opening `stateDiagram-v2` line is conventional (four
spaces) but not required. Comments use `%%`. The `[*]` token is special
and stands for "outside the state diagram"; `[*] --> X` marks `X` as
initial; `Y --> [*]` marks `Y` as final. State identifiers must match
`[A-Za-z_][A-Za-z0-9_]*`; the renderer's vertex labels are `T.pack . show`
applied to the vertex value, which produces a valid identifier for every
data-constructor name (Haskell constructor names already obey that
regex).

**`Data.Text` library.** `text` is already a library dependency
(`text ^>= 2.1` in `keiki.cabal`). The renderer constructs `Text` values
through `Data.Text.pack`, `Data.Text.intercalate`, and the `<>` operator.
No `Data.Text.Builder` is needed for this small output volume; the simple
form is clearer.


## Plan of Work

The work proceeds in five milestones (M0..M4). Each milestone leaves the
codebase in a buildable, testable state and is independently verifiable.

### M0 — Verify prerequisites

Run `cabal build all` and `cabal test` from the repo root on master before
making any changes. Both must succeed. Record the GHC version
(`ghc --version`) and z3 availability (`z3 --version`) in the Surprises &
Discoveries section. This baseline confirms the work environment is ready
and gives a reference point if a later milestone hits an unrelated build
break.

Acceptance: both commands exit 0; the GHC version is noted.

### M1 — Add the renderer module skeleton

Create `src/Keiki/Render/Mermaid.hs`:

    {-# LANGUAGE GADTs #-}

    -- | Mermaid 'stateDiagram-v2' renderer for 'SymTransducer' values
    -- whose vertex type is enumerable.
    --
    -- See 'docs/masterplans/10-mermaid-topology-renderer-for-symtransducer.md'
    -- and 'docs/plans/30-mermaid-renderer-for-single-symtransducer-canonical-example-diagrams.md'.
    module Keiki.Render.Mermaid
      ( toMermaid
      , vertexLabel
      , edgeInputName
      , edgeOutputName
      , edgeLabel
      ) where

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

    -- placeholder bodies; M2 fills these in
    toMermaid
      :: (Enum s, Bounded s, Show s)
      => SymTransducer (HsPred rs ci) rs s ci co
      -> Text
    toMermaid _ = T.empty

    vertexLabel :: Show s => s -> Text
    vertexLabel = T.pack . show

    edgeInputName :: Edge (HsPred rs ci) rs ci co s -> Maybe Text
    edgeInputName _ = Nothing

    edgeOutputName :: Edge (HsPred rs ci) rs ci co s -> Maybe Text
    edgeOutputName _ = Nothing

    edgeLabel :: Edge (HsPred rs ci) rs ci co s -> Text
    edgeLabel _ = T.empty

Add `Keiki.Render.Mermaid` to the `library.exposed-modules` list in
`keiki.cabal` (the modules are listed alphabetically; insert after
`Keiki.Profunctor`).

Build with `cabal build all` from the repo root. The build must succeed
with no warnings.

Acceptance: `cabal build all` exits 0; `ghci -e ':browse Keiki.Render.Mermaid'`
shows the four exported names.

### M2 — Implement `toMermaid` for single transducers

Replace the placeholder bodies in `src/Keiki/Render/Mermaid.hs` with the
real implementation.

`vertexLabel` is already correct (`T.pack . show`).

`edgeInputName` walks the `Edge`'s guard looking for the leftmost
`PInCtor` atom. Use a local helper:

    edgeInputName Edge { guard = g } = walk g
      where
        walk :: HsPred rs ci -> Maybe Text
        walk (PInCtor InCtor { icName = n }) = Just (T.pack n)
        walk (PAnd a b)                      = walk a <|> walk b
        walk (POr  a b)                      = walk a <|> walk b
        walk (PNot p)                        = walk p
        walk PTop                            = Nothing
        walk PBot                            = Nothing
        walk (PEq _ _)                       = Nothing

`<|>` is `Control.Applicative.(<|>)` for `Maybe` — returns the leftmost
`Just`. Add the import.

`edgeOutputName` reads `wcName` from the `OPack`'s `WireCtor`:

    edgeOutputName Edge { output = Nothing }                  = Nothing
    edgeOutputName Edge { output = Just (OPack _ wc _) }      = Just (T.pack (wcName wc))

`edgeLabel` combines them. The format is `<input> / <output>` where each
side is the extracted name or, if missing, `?` for input and `ε` for
output's missing case (which is the ε-edge):

    edgeLabel e =
      let inp = maybe (T.pack "?") id (edgeInputName e)
          out = maybe (T.pack "ε") id (edgeOutputName e)
      in inp <> T.pack " / " <> out

`toMermaid` enumerates vertices and edges:

    toMermaid t =
      let vertices = [minBound .. maxBound]
          header   = T.pack "stateDiagram-v2"
          ind      = T.pack "    "
          initLine = ind <> T.pack "[*] --> " <> vertexLabel (initial t)
          edgeLines =
            [ ind <> vertexLabel s <> T.pack " --> "
                  <> vertexLabel (target e) <> T.pack " : " <> edgeLabel e
            | s <- vertices
            , e <- edgesOut t s
            ]
          finalLines =
            [ ind <> vertexLabel s <> T.pack " --> [*]"
            | s <- vertices, isFinal t s
            ]
      in T.intercalate (T.pack "\n")
           (header : initLine : edgeLines ++ finalLines)

Edge ordering follows the `edgesOut` list ordering for each source vertex,
which mirrors how the Builder produced them; vertex ordering follows the
`Enum` derivation. Both are deterministic for any one transducer value, so
the regression test in M4 can pin a literal expected string.

Verify in `ghci`:

    cabal repl
    ghci> import Keiki.Render.Mermaid (toMermaid)
    ghci> import Keiki.Examples.UserRegistration (userReg)
    ghci> import qualified Data.Text.IO as TIO
    ghci> TIO.putStrLn (toMermaid userReg)

Expected output (this is the canonical form M4's regression test will
pin):

    stateDiagram-v2
        [*] --> PotentialCustomer
        PotentialCustomer --> Registering : StartRegistration / RegistrationStarted
        Registering --> RequiresConfirmation : Continue / ConfirmationEmailSent
        RequiresConfirmation --> Confirmed : ConfirmAccount / AccountConfirmed
        RequiresConfirmation --> RequiresConfirmation : ResendConfirmation / ConfirmationResent
        RequiresConfirmation --> Deleted : FulfillGDPRRequest / ε
        Confirmed --> Deleted : FulfillGDPRRequest / AccountDeleted
        Deleted --> [*]

If the actual output deviates (for example a different edge ordering,
different ctor name spelling), record the deviation in Surprises &
Discoveries and update both this plan's Purpose section and the M4
expected-string accordingly.

Acceptance: `cabal build all` succeeds with no warnings; the ghci
transcript above matches.

### M3 — Render diagrams for the four Examples modules

Create `docs/guide/diagrams/` and one `.md` per aggregate. Use the same
ghci pipeline from M2 to produce each, copy-pasting the rendered Text
into a fenced Mermaid block. File template:

    # User Registration topology

    Rendered by `Keiki.Render.Mermaid.toMermaid` over
    `Keiki.Examples.UserRegistration.userReg`. Refresh by running:

        cabal repl
        ghci> import Keiki.Render.Mermaid (toMermaid)
        ghci> import Keiki.Examples.UserRegistration (userReg)
        ghci> import qualified Data.Text.IO as TIO
        ghci> TIO.putStrLn (toMermaid userReg)

    ```mermaid
    stateDiagram-v2
        [*] --> PotentialCustomer
        ...
    ```

Files to create (one per aggregate):

- `docs/guide/diagrams/user-registration.md` — for `userReg`.
- `docs/guide/diagrams/user-registration-v0.md` — for `userRegV0`
  (`Keiki.Examples.UserRegistrationV0`).
- `docs/guide/diagrams/email-delivery.md` — for `emailDelivery`
  (`Keiki.Examples.EmailDelivery`).
- `docs/guide/diagrams/order-cart.md` — for `orderCart`
  (`Keiki.Examples.OrderCart`).

Verify each renders by opening the file in a Markdown previewer that
supports Mermaid (GitHub's web view, VS Code's "Markdown Preview"
extension, or the `mermaid-cli` if installed locally). The rendered
diagram must show the expected vertex / edge layout for each aggregate.

Acceptance: four files exist under `docs/guide/diagrams/`; each contains
a valid Mermaid block; `git status` shows the four files as new
untracked entries; the `Keiki.Render.Mermaid` module compiles unchanged.

### M4 — Regression test pinning canonical Mermaid output

Add `test/Keiki/Render/MermaidSpec.hs`:

    module Keiki.Render.MermaidSpec (spec) where

    import qualified Data.Text as T
    import Test.Hspec

    import Keiki.Examples.UserRegistration (userReg)
    import Keiki.Render.Mermaid (toMermaid)

    spec :: Spec
    spec = describe "toMermaid (single SymTransducer)" $ do
      it "renders userReg to the canonical block" $
        toMermaid userReg `shouldBe` T.unlines'
          [ "stateDiagram-v2"
          , "    [*] --> PotentialCustomer"
          , "    PotentialCustomer --> Registering : StartRegistration / RegistrationStarted"
          , "    Registering --> RequiresConfirmation : Continue / ConfirmationEmailSent"
          , "    RequiresConfirmation --> Confirmed : ConfirmAccount / AccountConfirmed"
          , "    RequiresConfirmation --> RequiresConfirmation : ResendConfirmation / ConfirmationResent"
          , "    RequiresConfirmation --> Deleted : FulfillGDPRRequest / ε"
          , "    Confirmed --> Deleted : FulfillGDPRRequest / AccountDeleted"
          , "    Deleted --> [*]"
          ]
        where
          T.unlines' = T.intercalate (T.pack "\n")

(Actual code: define `unlinesNoTrail = T.intercalate (T.pack "\n")` at
module scope rather than as a `where` clause; the `where`-on-`shouldBe`
form above is illustrative only.)

Add `Keiki.Render.MermaidSpec` to `keiki.cabal` under
`test-suite keiki-test.other-modules` (alphabetical order — insert after
`Keiki.ProfunctorSpec`).

Wire into `test/Spec.hs`:

- Add `import qualified Keiki.Render.MermaidSpec` in the import block
  (alphabetical insertion after `Keiki.ProfunctorSpec`).
- Add `describe "Keiki.Render.Mermaid" Keiki.Render.MermaidSpec.spec` in
  the `main` `do`-block (alphabetical).

Run:

    cabal test

Expected last lines of output:

    Keiki.Render.Mermaid
      toMermaid (single SymTransducer)
        renders userReg to the canonical block

    Finished in N.NN seconds
    M examples, 0 failures

If the test fails because the actual output differs, **first** confirm
the deviation is intentional (e.g. a Builder change reordered edges),
then update both the test's expected string and the diagram files in
`docs/guide/diagrams/` to match.

Acceptance: `cabal test` exits 0; the `Keiki.Render.Mermaid` describe
block appears in the output with one passing example.


## Concrete Steps

All commands run from the repo root
(`/Users/shinzui/Keikaku/bokuno/keiki`).

M0:

    cabal build all
    cabal test
    ghc --version
    z3 --version

M1:

    # Edit src/Keiki/Render/Mermaid.hs (new file).
    # Edit keiki.cabal: add `Keiki.Render.Mermaid` to library exposed-modules.
    cabal build all

M2:

    # Edit src/Keiki/Render/Mermaid.hs to fill in real bodies.
    cabal build all
    cabal repl
    ghci> import qualified Data.Text.IO as TIO
    ghci> import Keiki.Render.Mermaid
    ghci> import Keiki.Examples.UserRegistration
    ghci> TIO.putStrLn (toMermaid userReg)
    ghci> :q

M3:

    mkdir -p docs/guide/diagrams
    # Edit four Markdown files — paste rendered Text into Mermaid blocks.

M4:

    # Edit test/Keiki/Render/MermaidSpec.hs (new file).
    # Edit test/Spec.hs to register the spec.
    # Edit keiki.cabal: add `Keiki.Render.MermaidSpec` to test-suite other-modules.
    cabal test

Each milestone's output must be reviewed in `git status`; commit at each
milestone boundary with a `MasterPlan:` and `ExecPlan:` git trailer (and
`Intention:` if active).


## Validation and Acceptance

The plan succeeds when all of the following hold:

1. `cabal build all` produces no warnings or errors.
2. `cabal test` passes; the
   `Keiki.Render.Mermaid -> toMermaid (single SymTransducer) -> renders
   userReg to the canonical block` example is present and green.
3. `Keiki.Render.Mermaid` is exported from the library and the four
   names (`toMermaid`, `vertexLabel`, `edgeInputName`, `edgeOutputName`,
   `edgeLabel`) appear in `:browse Keiki.Render.Mermaid`.
4. `docs/guide/diagrams/` contains four `.md` files, each with a Mermaid
   block, that render correctly when previewed in GitHub's Markdown
   viewer (or any Mermaid-capable previewer).
5. The rendered output for `userReg` matches the canonical block in M2's
   acceptance section.

Anti-validation: the test must fail if the rendered output drifts. Verify
this by transiently editing the expected-string (e.g. dropping the `ε`)
and confirming `cabal test` reports a `shouldBe` mismatch with both
strings printed; revert the edit before completing M4.


## Idempotence and Recovery

All steps are idempotent. Re-running `cabal build all` and `cabal test`
is always safe. The four diagram files can be regenerated by re-running
the ghci pipeline; if a regeneration produces different output (e.g.
because the underlying aggregate's edges were reordered upstream), the
M4 test surfaces the mismatch and the author re-runs the ghci pipeline
for each affected diagram.

If M3's diagrams disagree with M4's regression test, the test is the
source of truth — re-render each diagram from `toMermaid`'s actual output
and update the file. If M4's expected string disagrees with M2's
acceptance transcript, M2's acceptance transcript is the source of truth
(it represents the actual `toMermaid userReg` output).

There are no destructive operations; no migrations; no shared external
state. Recovery from an interrupted milestone is "re-run the milestone's
edit + build + test cycle from scratch."


## Interfaces and Dependencies

**New module:** `Keiki.Render.Mermaid` (file:
`src/Keiki/Render/Mermaid.hs`), exporting:

    toMermaid
      :: (Enum s, Bounded s, Show s)
      => SymTransducer (HsPred rs ci) rs s ci co
      -> Text

    vertexLabel
      :: Show s => s -> Text

    edgeInputName
      :: Edge (HsPred rs ci) rs ci co s -> Maybe Text

    edgeOutputName
      :: Edge (HsPred rs ci) rs ci co s -> Maybe Text

    edgeLabel
      :: Edge (HsPred rs ci) rs ci co s -> Text

**Library dependencies:** `text` (already declared) and `base` (already
declared). No new dependency is added to `keiki.cabal`.

**Cabal changes:**

- `library.exposed-modules` += `Keiki.Render.Mermaid`.
- `test-suite keiki-test.other-modules` += `Keiki.Render.MermaidSpec`.
- No new `build-depends` entries.

**Test wiring:** `test/Spec.hs` adds one import and one `describe` line.

**Downstream consumers:** none in v1. The sibling plan
`docs/plans/31-mermaid-rendering-for-composite-symtransducers.md` will
extend `Keiki.Render.Mermaid` with composite-aware rendering and reuses
the helpers (`vertexLabel`, `edgeInputName`, `edgeOutputName`,
`edgeLabel`) defined here. EP-31's M0 hard-depends on EP-30 being
complete.

**Out of scope (will be cancelled / rejected if attempted):**

- Rendering guards or update bodies into edge labels. Topology-only
  labels are the v1 contract; the MasterPlan's Decision Log records the
  rationale.
- DOT / Graphviz output. A separate MasterPlan will pick this up if
  demand emerges after Mermaid ships.
- A `keiki-render` executable. Library-only for now.
- Composite (`Composite s1 s2`) rendering. EP-31 owns this.
