---
id: 61
slug: pretty-printer-for-hspred-term-update-and-domain-readable-mermaid-guard-rendering
title: "Pretty-printer for HsPred/Term/Update and domain-readable Mermaid guard rendering"
kind: exec-plan
created_at: 2026-06-06T15:47:42Z
intention: "intention_01ktes9wvkekw8nbb69st0naj8"
master_plan: "docs/masterplans/15-keiki-mermaid-diagram-and-documentation-rendering-improvements-surfaced-by-the-seihou-diagram-audit.md"
---

# Pretty-printer for HsPred/Term/Update and domain-readable Mermaid guard rendering

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

Today, when you render a keiki workflow to a Mermaid diagram and ask for a guard
annotation, you get a *structural* summary like `[g: PAnd PInCtor PEq]`. That tells you the
shape of the guard's syntax tree (an "and" of an input-constructor check and an equality)
but says nothing a domain reader cares about: *which* constructor, *which* register, *what*
is being compared. The Seihou disaster-response team, who consume keiki diagrams in
`../keiro-runtime-jitsurei/docs/diagrams/keiki.md`, asked for a **domain-readable** rendering
mode where that same guard renders as something like `(ConfirmAccount && confirmCode == confirmCode)`.

After this change, a diagram author can call `toMermaidWith (defaultMermaidOptions { guardMode = MermaidGuardPretty }) t`
and see guards rendered with real names: input-constructor names, register reads by slot
name, input-field reads by field name, equality `==`, ordering `< <= > >=`, arithmetic
`+ - *`, and boolean structure `&& || !`. The few things keiki *provably cannot* print —
applied opaque Haskell functions and literal values — are rendered with explicit placeholder
markers (`<fn>(...)`, `<lit>`) rather than silently dropped, so the reader is never misled.

The reusable engine behind this is a brand-new, pure, dependency-free module
`src/Keiki/Render/Pretty.hs` that turns keiki's predicate/term/update syntax trees into
`Data.Text.Text`. It is reusable on purpose: two sibling plans (the edge inspector,
`docs/plans/62-edge-inspector-markdown-renderer-for-symtransducer.md`, and the multiline
label/output-layout plan, `docs/plans/63-multiline-mermaid-edge-labels-and-multi-event-output-layout-controls.md`)
import this exact module instead of re-implementing guard prettifying.

You can see it working two ways. First, a pure unit test (`test/Keiki/Render/PrettySpec.hs`)
builds predicate/term/update values by hand and asserts their exact pretty strings. Second,
a new golden case in `test/Keiki/Render/MermaidSpec.hs` renders the real `userReg` fixture
with `MermaidGuardPretty` and pins the resulting diagram. Critically, the *default* output of
`toMermaid` stays byte-for-byte identical — every new behavior is opt-in.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] M1.1 Create `src/Keiki/Render/Pretty.hs` with module header and exports `indexName`, `prettyTerm`, `prettyPred`, `prettyUpdate`.
- [ ] M1.2 Implement `indexName :: Index rs r -> String` (walk `SIdx` to `ZIdx`, return `symbolVal`).
- [ ] M1.3 Implement `prettyTerm`, `prettyPred`, `prettyUpdate` with the exact rendering rules in this plan.
- [ ] M1.4 Register `Keiki.Render.Pretty` in `keiki.cabal` `library: exposed-modules`.
- [ ] M1.5 Create `test/Keiki/Render/PrettySpec.hs` with hand-built values covering slot reads, input-field reads, `==`, `< <= > >=`, arithmetic, boolean structure, `<fn>(...)`, `<lit>`, and `prettyUpdate`.
- [ ] M1.6 Register `Keiki.Render.PrettySpec` in `keiki.cabal` `test-suite: other-modules` and wire it into `test/Spec.hs`.
- [ ] M1.7 `cabal build keiki` and `cabal test keiki-test` pass; new describe block green.
- [ ] M2.1 Add `data MermaidGuardMode = MermaidGuardHidden | MermaidGuardStructuralSummary | MermaidGuardPretty` (derive `Eq`, `Show`) to `src/Keiki/Render/Mermaid.hs` and export it.
- [ ] M2.2 Add `guardMode :: MermaidGuardMode` field to `MermaidOptions`, set its default in `defaultMermaidOptions`.
- [ ] M2.3 Add `renderGuardSegment :: MermaidOptions -> HsPred rs ci -> Maybe Text` and route the guard segment of `edgeLabelWith` through it.
- [ ] M2.4 Confirm default and `showGuardSummary = True` goldens unchanged; add `MermaidGuardPretty` golden to `test/Keiki/Render/MermaidSpec.hs`.
- [ ] M2.5 `cabal build keiki` and `cabal test keiki-test` pass; full suite green.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Evolve `MermaidOptions` **additively** — keep `showWrittenSlots :: Bool` and
  `showGuardSummary :: Bool`, and ADD `guardMode :: MermaidGuardMode` — rather than replacing
  `showGuardSummary` with `guardMode` as the Seihou audit literally proposed.
  Rationale: there is a byte-identity golden in `test/Keiki/Render/MermaidSpec.hs`
  (`test/Keiki/Render/MermaidSpec.hs:108-117`, the `toMermaidWith (MermaidOptions { showWrittenSlots = True, showGuardSummary = True })`
  case) and downstream callers (Seihou) construct `MermaidOptions` by field name. Dropping a
  field is a breaking change with no payoff here. The MasterPlan records the same decision
  (`docs/masterplans/15-...md` Decision Log, 2026-06-06).
  Date: 2026-06-06
- Decision: Reconcile `showGuardSummary` and `guardMode` with this precedence rule —
  **`showGuardSummary` is the legacy spelling of `MermaidGuardStructuralSummary`, and it is
  honored only when `guardMode` is left at its default (`MermaidGuardHidden`)**. Concretely,
  `renderGuardSegment` decides the *effective* mode as: if `guardMode /= MermaidGuardHidden`
  use `guardMode`; otherwise if `showGuardSummary == True` use `MermaidGuardStructuralSummary`;
  otherwise `MermaidGuardHidden`. So `defaultMermaidOptions` sets `guardMode = MermaidGuardHidden`
  and `showGuardSummary = False`, which yields no guard segment (byte-identical default); and
  the legacy `MermaidOptions { showGuardSummary = True }` (with `guardMode` left at the default)
  still produces the exact `[g: PAnd PInCtor PEq]` structural summary it produces today.
  Rationale: this is the only reconciliation that makes BOTH the byte-identical default AND the
  existing `showGuardSummary = True` golden pass unchanged, while letting a caller who sets
  `guardMode` explicitly take full control. The alternative (defaulting `guardMode` to
  `MermaidGuardStructuralSummary` when `showGuardSummary` is true) was rejected because it would
  mean `defaultMermaidOptions` cannot have a single fixed `guardMode` value without re-deriving
  it from `showGuardSummary`, complicating the record's defaults.
  Date: 2026-06-06
- Decision: Render literal *values* opaquely as `<lit>` in `prettyTerm`.
  Rationale: `TLit :: r -> Term rs ci ifs r` carries an *unconstrained* `r`
  (`src/Keiki/Core.hs:307`) — there is no `Show r` to call, ever. Even inside `PEq`/`PCmp`
  the operands carry only `(Eq r, Typeable r)` / `(Ord r, Typeable r)`
  (`src/Keiki/Core.hs:550-552`, `src/Keiki/Core.hs:572-574`), so a bare `prettyTerm` has no
  `Typeable` in scope and cannot even print the type name. The baseline rendering is therefore
  `<lit>`. (Optional future refinement: the `PEq`/`PCmp` arms of `prettyPred` *do* have
  `Typeable r` in scope, so they could annotate a literal with its `TypeRep`, e.g. `<lit::Int>`;
  this plan does not do that to keep `prettyTerm`'s rules uniform, but the Interfaces section
  notes where it would go.) This bounds the audit's "PEq renders as `<left> == <right>`": the
  *shape* and any slot/field reads render; the literal renders as `<lit>`.
  Date: 2026-06-06
- Decision: Isolate guard-text production behind a single helper
  `renderGuardSegment :: MermaidOptions -> HsPred rs ci -> Maybe Text` in
  `src/Keiki/Render/Mermaid.hs`.
  Rationale: a sibling plan
  (`docs/plans/63-multiline-mermaid-edge-labels-and-multi-event-output-layout-controls.md`)
  will change how edge-label *segments are laid out* (inline vs. multiline). This plan owns how
  the guard *text* is produced. Routing all guard text through one helper means EP-63 can wrap
  the *assembly* of segments without touching this plan's text-production logic, and the two
  plans will not clobber each other. The MasterPlan's Integration Points section
  (`docs/masterplans/15-...md`) records this shared rule.
  Date: 2026-06-06


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

You are working in the keiki library, a pure-Haskell event-sourcing / symbolic-register
transducer library at the repository root `/Users/shinzui/Keikaku/bokuno/keiki`. You only need
this file and the working tree; no prior plan knowledge is assumed. Here are the terms and
files you will touch, defined from scratch.

**SymTransducer.** keiki models a workflow as a state machine called a `SymTransducer`
(defined in `src/Keiki/Core.hs`). It has vertices (states), and from each vertex a list of
outgoing *edges*. Each edge carries a *guard* (a predicate that decides whether the edge
fires for a given input), an *update* (how the register file changes), an *output* (the
events emitted), and a *target* vertex.

**HsPred — the guard predicate AST.** Defined at `src/Keiki/Core.hs:544-574`. "AST" means
"abstract syntax tree": a data type whose constructors mirror the grammar of an expression.
`HsPred rs ci` is a guard over a register file with slot list `rs` and an input symbol type
`ci`. Its constructors:

- `PTop` — always true.
- `PBot` — always false.
- `PAnd a b` — logical "and" of two predicates.
- `POr a b` — logical "or".
- `PNot p` — logical "not".
- `PEq l r` — equality of two `Term`s of the same type. The operands carry `(Eq r, Typeable r)`
  but **no `Show`** (`src/Keiki/Core.hs:550-552`).
- `PInCtor ic` — true iff the input symbol is the constructor named by the `InCtor` value `ic`.
- `PCmp c l r` — ordering comparison of two `Term`s with relation `c :: Cmp`. Operands carry
  `(Ord r, Typeable r)`, again **no `Show`** (`src/Keiki/Core.hs:572-574`).

**Cmp — the four-way ordering tag.** Defined at `src/Keiki/Core.hs:583-584`:
`data Cmp = CmpLt | CmpLe | CmpGt | CmpGe`, deriving `Eq, Show`. These mean `< <= > >=`
respectively (`src/Keiki/Core.hs:576-582`).

**Term — the expression AST.** Defined at `src/Keiki/Core.hs:306-339`. `Term rs ci ifs r` is a
pure expression yielding a value of type `r`, over register file `rs`, input `ci`, and input
field schema `ifs`. Its constructors:

- `TLit r` — a literal value. The `r` is **unconstrained** (`src/Keiki/Core.hs:307`); there is
  no `Show`, no `Typeable`. We cannot print the value.
- `TReg ix` — read a register at index `ix :: Index rs r`.
- `TInpCtorField ic ix` — read field `ix :: Index ifs r` of the input constructor described by
  `ic :: InCtor ci ifs`.
- `TApp1 f a` — apply an opaque Haskell function `f :: a -> r` to a sub-term. The function is
  unprintable.
- `TApp2 f a b` — apply an opaque binary function. Unprintable.
- `TArith op a b` — structural arithmetic, `op :: NumOp`, operands carry `(Num r, Typeable r)`.

**NumOp — the arithmetic tag.** Defined at `src/Keiki/Core.hs:288-289`:
`data NumOp = OpAdd | OpSub | OpMul`, deriving `Eq, Show`. Meaning `+ - *`
(`src/Keiki/Core.hs:282-287`).

**Index — a type-safe pointer into a register file, and the key to slot names.** Defined at
`src/Keiki/Core.hs:210-212`:

```haskell
data Index (rs :: [Slot]) (r :: Type) where
    ZIdx :: (KnownSymbol s) => Index ('(s, r) ': rs) r
    SIdx :: Index rs r -> Index ('(s', r') ': rs) r
```

The crucial fact: `ZIdx` carries `KnownSymbol s` for the slot it points at. So a recursive
walk that goes `SIdx i -> recurse on i` and at `ZIdx -> symbolVal (Proxy @s)` recovers the
slot's name with **no extra class constraint**. That walk is the `indexName` helper this plan
adds. (Compare `IndexN`'s `indexNName` at `src/Keiki/Internal/Slots.hs:132-135`, which does the
same for the name-tagged `IndexN` variant used by `USet`. We need the plain-`Index` analogue.)

**InCtor — a named input constructor.** Defined at `src/Keiki/Core.hs:363-370`:
`InCtor { icName :: String, icMatch, icBuild }` with constraints `(AssembleRegFile ifs,
KnownSlotNames ifs)`. The `icName` field is the human-readable constructor name we render.

**Update — how registers change on an edge.** Defined at `src/Keiki/Core.hs:444-456`:

```haskell
data Update (rs :: [Slot]) (w :: [Symbol]) (ci :: Type) where
    UKeep   :: Update rs '[] ci
    USet    :: KnownSymbol s => IndexN s rs r -> Term rs ci ifs r -> Update rs '[s] ci
    UCombine :: Update rs w1 ci -> Update rs w2 ci -> Update rs (Concat w1 w2) ci
```

`USet` uses the name-tagged `IndexN`, whose name is recovered by `indexNName`
(`src/Keiki/Internal/Slots.hs:134-135`). The write-set `w :: [Symbol]` is a phantom type-level
list. Note `UKeep` has `w ~ '[]` and `USet` has `w ~ '[s]`.

**The existential-`w` gotcha (load-bearing).** When an `Update` lives inside an `Edge`, the
write-set `w` is existentially quantified. Because of GHC bug #55876, the `update` record
selector cannot be applied as a function in that context. Wherever you have an `Edge`, you
must **pattern-match** the `Edge` constructor to bind the update, never write `update e`. The
existing `edgeLabelWith` already does this (`src/Keiki/Render/Mermaid.hs:626`,
`Edge { update = u, guard = g }`). This plan's `prettyUpdate` takes an `Update rs w ci`
directly, so the gotcha only bites at the call site, which already pattern-matches.

**The renderer — `src/Keiki/Render/Mermaid.hs`.** This module turns a `SymTransducer` into a
Mermaid `stateDiagram-v2` text block. Key pieces this plan touches:

- `MermaidOptions` (`src/Keiki/Render/Mermaid.hs:69-76`): a record with
  `showWrittenSlots :: Bool` and `showGuardSummary :: Bool`.
- `defaultMermaidOptions` (`src/Keiki/Render/Mermaid.hs:81-85`): both fields `False`.
- `toMermaid` (`src/Keiki/Render/Mermaid.hs:97-101`): `toMermaid = toMermaidWith defaultMermaidOptions`.
- `toMermaidWith` (`src/Keiki/Render/Mermaid.hs:112-117`): `= renderTopologyWith opts vertexLabel`.
- `edgeLabelWith` (`src/Keiki/Render/Mermaid.hs:622-641`): assembles the per-edge label,
  appending an optional `[w: ...; g: ...]` suffix. It pattern-matches
  `e@Edge { update = u, guard = g }` and calls `guardSummary g` when `showGuardSummary opts`.
- `guardSummary` (`src/Keiki/Render/Mermaid.hs:662-673`): the current structural prefix walk,
  e.g. `PAnd PInCtor PEq`; the `PCmp` arm renders `"PCmp " <> show c`.
- `edgeInputName` (`src/Keiki/Render/Mermaid.hs:571-582`): walks a guard for the first
  `PInCtor` and returns its `icName`.

**The existing golden tests — `test/Keiki/Render/MermaidSpec.hs`.** The byte-identity invariant
is enforced by:
- the default golden (`test/Keiki/Render/MermaidSpec.hs:108-110`,
  `toMermaidWith defaultMermaidOptions userReg \`shouldBe\` toMermaid userReg`), and
- the annotated golden (`test/Keiki/Render/MermaidSpec.hs:112-117`) that sets
  `MermaidOptions { showWrittenSlots = True, showGuardSummary = True }` and pins
  `userRegAnnotatedCanonical` (`test/Keiki/Render/MermaidSpec.hs:156-166`), which contains
  exact structural summaries like `[w: confirmedAt; g: PAnd PInCtor PEq]`.

Both must keep passing **unchanged** after this plan.

**The test fixture — `test/Keiki/Fixtures/UserRegistration.hs`.** Exposes `userReg`, a real
transducer whose edges carry real guards (`PInCtor`, and `PAnd PInCtor PEq` where `requireEq`
is used). Its register slots include `email`, `confirmCode`, `registeredAt`, `confirmedAt`,
`deletedAt` (see `test/Keiki/Fixtures/UserRegistration.hs:165-166` and the builder body around
`test/Keiki/Fixtures/UserRegistration.hs:286-334`). This fixture is what M2's golden renders.

**Project conventions.** Build from the repository root `/Users/shinzui/Keikaku/bokuno/keiki`
with `cabal build keiki`; test with `cabal test keiki-test`. The test suite is a **manual
aggregator** (`test/Spec.hs`) — there is NO `hspec-discover`. The only test framework available
is `hspec` (`keiki.cabal:127`, `hspec ^>=2.11`); there is NO QuickCheck and NO Hedgehog, so all
tests are example-based `shouldBe` assertions. A new library module must be added to
`keiki.cabal` `library: exposed-modules` (`keiki.cabal:59-72`). A new test module must be added
to `keiki.cabal` `test-suite keiki-test: other-modules` (`keiki.cabal:92-121`) AND imported and
described in `test/Spec.hs`. The language is GHC2024 with default extensions including
`OverloadedStrings`, `OverloadedRecordDot`, and `DuplicateRecordFields` (the `shared-extensions`
import). Rendering and pretty-printing are **pure** — no z3 / SBV needed at runtime for this
work (it consumes only `text`, already a dependency at `keiki.cabal:84`).

**Commit conventions.** Follow Conventional Commits. Every commit for this plan must carry these
trailers:

```text
MasterPlan: docs/masterplans/15-keiki-mermaid-diagram-and-documentation-rendering-improvements-surfaced-by-the-seihou-diagram-audit.md
ExecPlan: docs/plans/61-pretty-printer-for-hspred-term-update-and-domain-readable-mermaid-guard-rendering.md
Intention: intention_01ktes9wvkekw8nbb69st0naj8
```

Commit directly to the current branch; do not create a feature branch unless asked.


## Plan of Work

The work is two milestones. M1 builds the reusable pretty-printer and proves it with pure unit
tests. M2 wires a guard-mode option into the Mermaid renderer that reuses M1, with a golden
test, while preserving byte-identity of the default output. Do M1 first: M2 depends on M1's
`prettyPred`.

### Milestone M1 — the pure pretty-printer module

Scope: add `src/Keiki/Render/Pretty.hs` exporting `indexName`, `prettyTerm`, `prettyPred`,
`prettyUpdate`; register it in `keiki.cabal`; add `test/Keiki/Render/PrettySpec.hs` proving
the exact rendering of every constructor; register that spec in `keiki.cabal` and `test/Spec.hs`.

At the end of M1, a caller can `import Keiki.Render.Pretty (prettyPred, prettyTerm, prettyUpdate, indexName)`
and turn any `HsPred`/`Term`/`Update` value into readable `Text`. The two sibling plans
(`docs/plans/62-...md`, `docs/plans/63-...md`) consume exactly this API and must not
re-implement it.

The new module body. Create `src/Keiki/Render/Pretty.hs` with this shape (the exact rendering
strings are mandatory — the golden tests pin them):

```haskell
-- | Pure, domain-readable pretty-printer for keiki's predicate, term,
-- and update syntax trees ('HsPred', 'Term', 'Update'). Produces
-- 'Data.Text.Text'. No solver, no IO. Shared by the Mermaid topology
-- renderer ('Keiki.Render.Mermaid') and the sibling edge-inspector /
-- multiline-label renderers.
--
-- Two things are provably unprintable and are marked, not dropped:
-- applied opaque Haskell functions render as @<fn>(...)@; literal
-- values render as @<lit>@ (a 'TLit' carries an unconstrained type
-- with no 'Show').
module Keiki.Render.Pretty
  ( indexName
  , prettyTerm
  , prettyPred
  , prettyUpdate
  ) where

import Data.Proxy (Proxy (..))
import Data.Text (Text)
import qualified Data.Text as T
import GHC.TypeLits (KnownSymbol, symbolVal)

import Keiki.Core
  ( Cmp (..)
  , HsPred (..)
  , InCtor (..)
  , Index (..)
  , NumOp (..)
  , Term (..)
  , Update (..)
  )
import Keiki.Internal.Slots (IndexN, indexNName)

-- | Recover the slot name an 'Index' points at, by walking 'SIdx' down
-- to the 'ZIdx' and reading its 'KnownSymbol'. No extra class
-- constraint is needed: 'ZIdx' carries the slot's symbol.
indexName :: Index rs r -> String
indexName = go
  where
    go :: Index rs' r' -> String
    go (ZIdx :: Index rs' r') = symbolVal (Proxy @s)  -- s from ZIdx's KnownSymbol
    go (SIdx i)               = go i
```

Implementation note for `indexName`: the `ZIdx` pattern brings its own existential
`KnownSymbol s` into scope, so `symbolVal (Proxy @s)` typechecks inside that branch. You will
need `ScopedTypeVariables` (in GHC2024 by default) and to bind `s` via a pattern type
signature, or equivalently use a helper. A simple, robust spelling that avoids the
scoped-variable fiddliness is:

```haskell
indexName :: Index rs r -> String
indexName (ZIdx @s) = symbolVal (Proxy @s)
indexName (SIdx i)  = indexName i
```

The `ZIdx @s` type-application pattern binds the existential symbol directly; this is the
preferred form. If GHC rejects it under the current extension set, fall back to a `case` with
an explicit `Proxy` argument helper.

`prettyTerm`. Total structural recursion. The exact strings:

```haskell
prettyTerm :: Term rs ci ifs r -> Text
prettyTerm (TLit _)             = T.pack "<lit>"
prettyTerm (TReg ix)            = T.pack (indexName ix)
prettyTerm (TInpCtorField ic ix) =
  T.pack (icName ic) <> T.pack "." <> T.pack (indexName ix)
prettyTerm (TApp1 _ a)          = T.pack "<fn>(" <> prettyTerm a <> T.pack ")"
prettyTerm (TApp2 _ a b)        =
  T.pack "<fn>(" <> prettyTerm a <> T.pack ", " <> prettyTerm b <> T.pack ")"
prettyTerm (TArith op a b)      =
  T.pack "(" <> prettyTerm a <> T.pack " " <> numOpSym op
            <> T.pack " " <> prettyTerm b <> T.pack ")"
  where
    numOpSym OpAdd = T.pack "+"
    numOpSym OpSub = T.pack "-"
    numOpSym OpMul = T.pack "*"
```

`prettyPred`. Total structural recursion. The exact strings:

```haskell
prettyPred :: HsPred rs ci -> Text
prettyPred PTop          = T.pack "true"
prettyPred PBot          = T.pack "false"
prettyPred (PAnd a b)    =
  T.pack "(" <> prettyPred a <> T.pack " && " <> prettyPred b <> T.pack ")"
prettyPred (POr a b)     =
  T.pack "(" <> prettyPred a <> T.pack " || " <> prettyPred b <> T.pack ")"
prettyPred (PNot p)      = T.pack "!(" <> prettyPred p <> T.pack ")"
prettyPred (PEq l r)     = prettyTerm l <> T.pack " == " <> prettyTerm r
prettyPred (PInCtor ic)  = T.pack (icName ic)
prettyPred (PCmp c l r)  =
  prettyTerm l <> T.pack " " <> cmpSym c <> T.pack " " <> prettyTerm r
  where
    cmpSym CmpLt = T.pack "<"
    cmpSym CmpLe = T.pack "<="
    cmpSym CmpGt = T.pack ">"
    cmpSym CmpGe = T.pack ">="
```

`prettyUpdate`. Total structural recursion. `USet`'s index is an `IndexN`, whose name comes
from `indexNName` (`src/Keiki/Internal/Slots.hs:134-135`), not from this module's `indexName`:

```haskell
prettyUpdate :: Update rs w ci -> Text
prettyUpdate UKeep          = T.pack "(keep)"
prettyUpdate (USet ix t)    = T.pack (indexNName ix) <> T.pack " := " <> prettyTerm t
prettyUpdate (UCombine a b) = prettyUpdate a <> T.pack ", " <> prettyUpdate b
```

Register the module in `keiki.cabal` `library: exposed-modules` (alphabetical-ish next to
`Keiki.Render.Mermaid`).

Then write `test/Keiki/Render/PrettySpec.hs`. Because the only framework is `hspec` with
`shouldBe`, the spec builds values directly from `Keiki.Core` constructors (and one fixture
read), asserting exact strings. Cover: a register read by slot name (`TReg`), an input-field
read by `ctor.field` (`TInpCtorField`), `PEq` shape with `<lit>` on one side and a slot read on
the other, each `PCmp` direction, a `TArith` expression, `PAnd`/`POr`/`PNot` nesting, a
`TApp1`/`TApp2` rendering `<fn>(...)`, `PTop`/`PBot`, `PInCtor` rendering its `icName`, and a
`prettyUpdate` `USet`/`UCombine`/`UKeep`. See Concrete Steps for the exact test source.

Register the spec module in `keiki.cabal` `test-suite keiki-test: other-modules` and wire it
into `test/Spec.hs`.

Acceptance for M1: `cabal build keiki` succeeds; `cabal test keiki-test` passes, and the new
`Keiki.Render.Pretty` describe block reports all its examples passing.

### Milestone M2 — the `MermaidGuardPretty` mode

Scope: add `MermaidGuardMode`, add the `guardMode` field to `MermaidOptions` additively, route
the guard segment through a new `renderGuardSegment` helper that reuses `prettyPred`, and add a
golden case. Default output stays byte-identical; the existing `showGuardSummary = True` golden
stays unchanged.

At the end of M2, `toMermaidWith (defaultMermaidOptions { guardMode = MermaidGuardPretty }) userReg`
produces a diagram whose edge labels carry `[g: <readable guard>]`, and a new golden pins it.

Edits in `src/Keiki/Render/Mermaid.hs`:

1. Add the mode type near `MermaidOptions`:

```haskell
data MermaidGuardMode
  = MermaidGuardHidden            -- ^ No guard segment.
  | MermaidGuardStructuralSummary -- ^ The structural tag walk ('guardSummary').
  | MermaidGuardPretty            -- ^ Domain-readable guard text ('prettyPred').
  deriving stock (Eq, Show)
```

2. Add `guardMode :: MermaidGuardMode` to `MermaidOptions` (after `showGuardSummary`, never
   reordering — EP-63 will append its fields after this one), and set its default in
   `defaultMermaidOptions` to `MermaidGuardHidden`.

3. Add the single guard-text helper:

```haskell
-- | Produce the guard segment text for an edge, or 'Nothing' when no
-- guard segment should appear. The effective mode reconciles the legacy
-- 'showGuardSummary' flag with the new 'guardMode': an explicit
-- 'guardMode' (anything other than 'MermaidGuardHidden') wins; otherwise
-- 'showGuardSummary' is honored as the legacy spelling of
-- 'MermaidGuardStructuralSummary'.
renderGuardSegment :: MermaidOptions -> HsPred rs ci -> Maybe Text
renderGuardSegment opts g =
  case effectiveMode of
    MermaidGuardHidden            -> Nothing
    MermaidGuardStructuralSummary -> Just (guardSummary g)
    MermaidGuardPretty            -> Just (prettyPred g)
  where
    effectiveMode
      | guardMode opts /= MermaidGuardHidden = guardMode opts
      | showGuardSummary opts                = MermaidGuardStructuralSummary
      | otherwise                            = MermaidGuardHidden
```

4. Rewrite the `gPart` branch of `edgeLabelWith` (`src/Keiki/Render/Mermaid.hs:635-637`) to use
   the helper. Today it is:

```haskell
gPart = if showGuardSummary opts
          then [ T.pack "g: " <> guardSummary g ]
          else []
```

Replace with:

```haskell
gPart = case renderGuardSegment opts g of
          Just t  -> [ T.pack "g: " <> t ]
          Nothing -> []
```

5. Add `MermaidGuardMode (..)` to the module export list (`src/Keiki/Render/Mermaid.hs:25-44`),
   and add `import Keiki.Render.Pretty (prettyPred)` to the imports.

Edits in `test/Keiki/Render/MermaidSpec.hs`:

6. Add a new `describe`/`it` that renders `userReg` with
   `defaultMermaidOptions { guardMode = MermaidGuardPretty }` (you will need to import
   `MermaidGuardMode (..)` and `defaultMermaidOptions`; `defaultMermaidOptions` is already
   imported at `test/Keiki/Render/MermaidSpec.hs:56`) and assert it equals a new
   `userRegPrettyGuardCanonical`. Determine the exact canonical text by building once and
   pasting (see Concrete Steps for the generate-and-pin recipe). Also keep `showWrittenSlots`
   at its default `False` for this case so the label carries only the `[g: ...]` segment.

Acceptance for M2: `cabal build keiki` succeeds; `cabal test keiki-test` passes with the
pre-existing default and `showGuardSummary` goldens unchanged and the new pretty-guard golden
green.


## Concrete Steps

All commands run from the repository root `/Users/shinzui/Keikaku/bokuno/keiki`.

### Step 1 — create the pretty-printer module

Write `src/Keiki/Render/Pretty.hs` with the body shown in Plan of Work (the `module` header
through `prettyUpdate`). Use the `indexName (ZIdx @s) = symbolVal (Proxy @s)` form.

### Step 2 — register the library module

Edit `keiki.cabal` `library: exposed-modules` (`keiki.cabal:59-72`):

```diff
     Keiki.Profunctor
     Keiki.Render.Mermaid
+    Keiki.Render.Pretty
     Keiki.Shape
```

### Step 3 — build the library

```bash
cabal build keiki
```

Expected (abbreviated):

```text
Building library 'keiki' ...
[ n of m] Compiling Keiki.Render.Pretty ...
```

with no errors. If GHC rejects `ZIdx @s` in the pattern, switch to the `case` + helper form
described in Plan of Work and rebuild.

### Step 4 — write the pure spec

Create `test/Keiki/Render/PrettySpec.hs`. This source is self-contained: it builds values from
`Keiki.Core` constructors and one tiny local `InCtor`. It avoids needing `Show` on any literal
by always pairing a `TLit` with a slot read or by asserting it renders `<lit>`.

```haskell
-- | Unit tests for "Keiki.Render.Pretty": the domain-readable
-- pretty-printer for 'HsPred' / 'Term' / 'Update'. Pure 'shouldBe'
-- assertions on exact rendered 'Text'.
module Keiki.Render.PrettySpec (spec) where

import Data.Text (Text)
import qualified Data.Text as T
import Test.Hspec

import Keiki.Core
  ( Cmp (..)
  , HsPred (..)
  , InCtor (..)
  , Index (..)
  , NumOp (..)
  , RegFile (..)
  , Term (..)
  , Update (..)
  )
import Keiki.Internal.Slots (IndexN (..))
import Keiki.Render.Pretty (prettyPred, prettyTerm, prettyUpdate)

-- A two-slot register file schema: "balance" :: Int, "limit" :: Int.
type Regs = '[ '("balance", Int), '("limit", Int) ]

-- An input type with one constructor "Deposit" carrying one field
-- "amount" :: Int.
data Cmd = Deposit Int
  deriving (Eq, Show)

type DepFields = '[ '("amount", Int) ]

inCtorDeposit :: InCtor Cmd DepFields
inCtorDeposit = InCtor
  { icName  = "Deposit"
  , icMatch = \(Deposit n) -> Just (RCons (undefined) n RNil)  -- see note
  , icBuild = \(RCons _ n RNil) -> Deposit n
  }

-- Index helpers (built by hand so we do not depend on OverloadedLabels
-- resolution here).
balanceIx :: Index Regs Int
balanceIx = ZIdx

limitIx :: Index Regs Int
limitIx = SIdx ZIdx

amountIx :: Index DepFields Int
amountIx = ZIdx

balanceN :: IndexN "balance" Regs Int
balanceN = IZ

spec :: Spec
spec = do
  describe "prettyTerm" $ do
    it "renders a register read by slot name" $
      prettyTerm (TReg balanceIx :: Term Regs Cmd '[] Int)
        `shouldBe` T.pack "balance"
    it "renders the second register by its slot name" $
      prettyTerm (TReg limitIx :: Term Regs Cmd '[] Int)
        `shouldBe` T.pack "limit"
    it "renders an input-field read as ctor.field" $
      prettyTerm (TInpCtorField inCtorDeposit amountIx :: Term Regs Cmd DepFields Int)
        `shouldBe` T.pack "Deposit.amount"
    it "renders a literal opaquely as <lit>" $
      prettyTerm (TLit (42 :: Int) :: Term Regs Cmd '[] Int)
        `shouldBe` T.pack "<lit>"
    it "renders TApp1 as <fn>(arg)" $
      prettyTerm (TApp1 (+ (1 :: Int)) (TReg balanceIx) :: Term Regs Cmd '[] Int)
        `shouldBe` T.pack "<fn>(balance)"
    it "renders TApp2 as <fn>(a, b)" $
      prettyTerm
        (TApp2 ((+) :: Int -> Int -> Int) (TReg balanceIx) (TReg limitIx)
           :: Term Regs Cmd '[] Int)
        `shouldBe` T.pack "<fn>(balance, limit)"
    it "renders TArith add as (a + b)" $
      prettyTerm (TArith OpAdd (TReg balanceIx) (TReg limitIx) :: Term Regs Cmd '[] Int)
        `shouldBe` T.pack "(balance + limit)"
    it "renders TArith sub as (a - b)" $
      prettyTerm (TArith OpSub (TReg balanceIx) (TReg limitIx) :: Term Regs Cmd '[] Int)
        `shouldBe` T.pack "(balance - limit)"
    it "renders TArith mul as (a * b)" $
      prettyTerm (TArith OpMul (TReg balanceIx) (TReg limitIx) :: Term Regs Cmd '[] Int)
        `shouldBe` T.pack "(balance * limit)"

  describe "prettyPred" $ do
    it "renders PTop / PBot" $ do
      prettyPred (PTop :: HsPred Regs Cmd) `shouldBe` T.pack "true"
      prettyPred (PBot :: HsPred Regs Cmd) `shouldBe` T.pack "false"
    it "renders PInCtor as the constructor name" $
      prettyPred (PInCtor inCtorDeposit :: HsPred Regs Cmd)
        `shouldBe` T.pack "Deposit"
    it "renders PEq structurally with <lit> on the literal side" $
      prettyPred (PEq (TReg balanceIx) (TLit (0 :: Int)) :: HsPred Regs Cmd)
        `shouldBe` T.pack "balance == <lit>"
    it "renders each PCmp direction" $ do
      prettyPred (PCmp CmpLt (TReg balanceIx) (TReg limitIx) :: HsPred Regs Cmd)
        `shouldBe` T.pack "balance < limit"
      prettyPred (PCmp CmpLe (TReg balanceIx) (TReg limitIx) :: HsPred Regs Cmd)
        `shouldBe` T.pack "balance <= limit"
      prettyPred (PCmp CmpGt (TReg balanceIx) (TReg limitIx) :: HsPred Regs Cmd)
        `shouldBe` T.pack "balance > limit"
      prettyPred (PCmp CmpGe (TReg balanceIx) (TReg limitIx) :: HsPred Regs Cmd)
        `shouldBe` T.pack "balance >= limit"
    it "renders boolean structure with && || !" $
      prettyPred
        (PAnd (PInCtor inCtorDeposit)
              (POr (PCmp CmpGe (TReg balanceIx) (TLit (0 :: Int)))
                   (PNot (PEq (TReg limitIx) (TLit (0 :: Int)))))
           :: HsPred Regs Cmd)
        `shouldBe`
          T.pack "(Deposit && (balance >= <lit> || !(limit == <lit>)))"

  describe "prettyUpdate" $ do
    it "renders UKeep" $
      prettyUpdate (UKeep :: Update Regs '[] Cmd) `shouldBe` T.pack "(keep)"
    it "renders USet as slot := term" $
      prettyUpdate (USet balanceN (TLit (0 :: Int)) :: Update Regs '["balance"] Cmd)
        `shouldBe` T.pack "balance := <lit>"
    it "renders UCombine comma-separated" $
      prettyUpdate
        (UCombine (USet balanceN (TReg limitIx))
                  (USet balanceN (TLit (1 :: Int)))
           :: Update Regs '["balance", "balance"] Cmd)
        `shouldBe` T.pack "balance := limit, balance := <lit>"
```

Note on `inCtorDeposit`'s `icMatch`: building a `RegFile` for a one-slot schema needs a
`Proxy "amount"`. If the `undefined` placeholder for the `Proxy` triggers a warning-as-error
under the `warnings` import, replace it with `(Proxy @"amount")` and add
`import Data.Proxy (Proxy (..))`. The pretty-printer never *calls* `icMatch`/`icBuild`
(it only reads `icName`), so any total definition that typechecks is fine; the test only
exercises `icName = "Deposit"`. If constructing a valid `InCtor` by hand proves fiddly under
the fixture's constraints, an equally acceptable alternative is to import a ready-made `InCtor`
from `Keiki.Fixtures.UserRegistration` (e.g. `inCtorStart`, exported at
`test/Keiki/Fixtures/UserRegistration.hs:61`) and assert `prettyPred (PInCtor inCtorStart)`
equals its `icName`. Prefer whichever compiles cleanly; the assertion content (the rendered
strings) is what matters.

### Step 5 — register the spec in cabal and Spec.hs

Edit `keiki.cabal` `test-suite keiki-test: other-modules` (`keiki.cabal:92-121`):

```diff
     Keiki.Render.MermaidSpec
+    Keiki.Render.PrettySpec
     Keiki.ShapeSpec
```

Edit `test/Spec.hs` — add the import (alphabetical, after the Mermaid import at
`test/Spec.hs:24`):

```diff
 import Keiki.Render.MermaidSpec qualified
+import Keiki.Render.PrettySpec qualified
```

and add the describe line (after `test/Spec.hs:57`):

```diff
     describe "Keiki.Render.Mermaid (EP-30, EP-31, EP-32, EP-33)" Keiki.Render.MermaidSpec.spec
+    describe "Keiki.Render.Pretty (EP-61)" Keiki.Render.PrettySpec.spec
```

### Step 6 — run the suite (M1 acceptance)

```bash
cabal test keiki-test
```

Expected (abbreviated, with the new block green):

```text
Keiki.Render.Pretty (EP-61)
  prettyTerm
    renders a register read by slot name
    renders the second register by its slot name
    renders an input-field read as ctor.field
    renders a literal opaquely as <lit>
    ...
  prettyPred
    ...
  prettyUpdate
    ...

Finished in ...
NNN examples, 0 failures
```

Commit M1:

```bash
git add src/Keiki/Render/Pretty.hs test/Keiki/Render/PrettySpec.hs keiki.cabal test/Spec.hs
git commit
```

with a Conventional Commit message such as
`feat(render): add pure HsPred/Term/Update pretty-printer (EP-61 M1)` and the three trailers
listed in Context and Orientation.

### Step 7 — add MermaidGuardMode and the guardMode field

Apply edits 1–5 from Plan of Work's M2 section to `src/Keiki/Render/Mermaid.hs`. Then build:

```bash
cabal build keiki
```

Expect a clean build. The `(/=)` in `renderGuardSegment` requires `Eq MermaidGuardMode`, which
the `deriving stock (Eq, Show)` provides.

### Step 8 — confirm byte-identity, then generate and pin the pretty golden

First, confirm the two existing goldens still pass:

```bash
cabal test keiki-test
```

The pre-existing `toMermaidWith defaultMermaidOptions` (byte-identical default) and
`toMermaidWith (MermaidOptions { showWrittenSlots = True, showGuardSummary = True })`
(`userRegAnnotatedCanonical`) cases must be green and unchanged. If either fails, the
`renderGuardSegment` precedence is wrong — re-check that `defaultMermaidOptions` sets
`guardMode = MermaidGuardHidden` and that the `showGuardSummary` legacy path still returns the
structural summary.

Now obtain the exact pretty-guard text. Add the new `describe`/`it` to
`test/Keiki/Render/MermaidSpec.hs` with a *placeholder* expected value of `T.pack ""`, run the
test, and read the actual rendered diagram from hspec's failure diff. Paste that verbatim into
`userRegPrettyGuardCanonical`. The label segments will look like `[g: Deposit]`-style pretty
guards; for `userReg`, edges built by `onCmd` carry `PInCtor` (rendering the command name) and
the `ConfirmAccount` edge additionally carries a `PEq` from `requireEq`, so its guard renders as
`(ConfirmAccount && confirmCode == confirmCode)` (the exact left/right of the `==` follow from
the fixture's `requireEq d.confirmCode #confirmCode` at
`test/Keiki/Fixtures/UserRegistration.hs:304` — `d.confirmCode` is a `TInpCtorField` rendering
`ConfirmAccount.confirmCode`, and `#confirmCode` is a `TReg` rendering `confirmCode`, giving
`ConfirmAccount.confirmCode == confirmCode`; verify by running and pinning rather than trusting
this prose). The new golden block:

```haskell
  describe "toMermaidWith (MermaidGuardPretty, EP-61)" $
    it "renders userReg guards in domain-readable form" $
      toMermaidWith
        (defaultMermaidOptions { guardMode = MermaidGuardPretty })
        userReg
        `shouldBe` userRegPrettyGuardCanonical
```

Add `MermaidGuardMode (..)` to the import list from `Keiki.Render.Mermaid` in the spec
(`test/Keiki/Render/MermaidSpec.hs:54-66`).

### Step 9 — run the full suite (M2 acceptance)

```bash
cabal test keiki-test
```

Expect all examples passing, including the new pretty-guard block and the unchanged
default/`showGuardSummary` goldens.

Commit M2:

```bash
git add src/Keiki/Render/Mermaid.hs test/Keiki/Render/MermaidSpec.hs
git commit
```

with a message such as
`feat(render): add MermaidGuardPretty mode reusing the pretty-printer (EP-61 M2)` and the three
trailers.


## Validation and Acceptance

Validation is behavioral, not "it compiles". Run every check from
`/Users/shinzui/Keikaku/bokuno/keiki`.

**M1 acceptance.** `cabal test keiki-test` passes, and the `Keiki.Render.Pretty (EP-61)`
describe block reports every example green. The substantive proof is that the printer renders
*names and structure*, not constructor tags: `prettyTerm (TReg balanceIx)` is `balance` (a slot
name, via `indexName`), `prettyTerm (TInpCtorField inCtorDeposit amountIx)` is `Deposit.amount`
(constructor + field name), the four `PCmp` directions render `< <= > >=`, arithmetic renders
`(a + b)` / `(a - b)` / `(a * b)`, boolean structure renders `&& || !` with parentheses, opaque
functions render `<fn>(...)`, and literals render `<lit>`. These are exactly the audit's
acceptance criteria for Requirement 1, with the documented adjustment that literal *values*
render opaquely (`<lit>`) because `TLit` carries no `Show`.

**M2 acceptance — byte-identity of the default.** This is the load-bearing invariant. After the
change, `toMermaidWith defaultMermaidOptions userReg` must equal `toMermaid userReg` byte-for-
byte, which the pre-existing golden at `test/Keiki/Render/MermaidSpec.hs:108-110` asserts. The
existing annotated golden at `test/Keiki/Render/MermaidSpec.hs:112-117` (which sets
`showGuardSummary = True`) must still produce `userRegAnnotatedCanonical` with its structural
summaries like `[w: confirmedAt; g: PAnd PInCtor PEq]` — unchanged. Both being green proves the
additive evolution did not regress any existing caller.

**M2 acceptance — the new behavior is real.** The new golden renders `userReg` with
`MermaidGuardPretty` and shows readable guards in the label, e.g. (illustrative; pin the exact
text by running):

```text
    RequiresConfirmation --> Confirmed : ConfirmAccount / AccountConfirmed [g: (ConfirmAccount && ConfirmAccount.confirmCode == confirmCode)]
```

versus the same edge under `MermaidGuardStructuralSummary` today:

```text
    RequiresConfirmation --> Confirmed : ConfirmAccount / AccountConfirmed [g: PAnd PInCtor PEq]
```

The contrast — `PAnd PInCtor PEq` versus `(ConfirmAccount && ...)` — is the user-visible payoff.

If any golden's actual text differs from what this plan guessed in prose, trust the running
test: pin the actual rendered bytes. The plan's prose about specific guard strings is a
prediction; the generate-and-pin recipe in Concrete Steps Step 8 is the source of truth.


## Idempotence and Recovery

Every step is additive and safe to repeat. Re-running `cabal build keiki` / `cabal test
keiki-test` is idempotent. The Edits to `keiki.cabal` and `test/Spec.hs` add lines; if a line
is already present, do not add it again (the build will fail on a duplicate module entry, which
is a clear signal). If the new module fails to compile, the library and the existing tests are
untouched, so you can iterate on `src/Keiki/Render/Pretty.hs` alone.

The single risky spot is the `renderGuardSegment` precedence in M2: if it is wrong, the
*existing* goldens break (not just the new one). Recovery is to re-read the Decision Log
precedence rule and confirm `defaultMermaidOptions` sets `guardMode = MermaidGuardHidden`. Until
M2's edits are committed, `git checkout -- src/Keiki/Render/Mermaid.hs` restores the renderer to
its byte-identical state. The pretty-printer module from M1 is independent of M2 and need not be
reverted.

No migrations, no destructive operations, no external services are involved. All work is pure
Haskell over `text`.


## Interfaces and Dependencies

**New module: `src/Keiki/Render/Pretty.hs`** (added to `keiki.cabal` `library: exposed-modules`).
Depends only on `base`, `text` (already at `keiki.cabal:84`), `Keiki.Core`, and
`Keiki.Internal.Slots` — all already in the library. The exported API, which is the shared
contract for sibling plans `docs/plans/62-...md` and `docs/plans/63-...md` (they import these
and must NOT re-implement guard prettifying):

```haskell
indexName   :: Index rs r       -> String   -- walk SIdx to ZIdx, return symbolVal
prettyTerm  :: Term rs ci ifs r -> Text
prettyPred  :: HsPred rs ci     -> Text
prettyUpdate :: Update rs w ci  -> Text
```

The exact rendering strings (mandatory; pinned by tests) are specified in Plan of Work. An
optional `prettyOutTerm :: OutTerm rs ci co -> Text` could be added later for the inspector
plan, but it is not required by this plan and is left to EP-62. An optional refinement to
`prettyPred`'s `PEq`/`PCmp` arms — annotating a `TLit` operand with its `TypeRep` (e.g.
`<lit::Int>`) since `Typeable r` is in scope there — is explicitly deferred; the baseline is
`<lit>` everywhere because `prettyTerm` has no `Typeable` in scope.

**Modified module: `src/Keiki/Render/Mermaid.hs`.** Adds, after M2:

```haskell
data MermaidGuardMode
  = MermaidGuardHidden
  | MermaidGuardStructuralSummary
  | MermaidGuardPretty
  deriving stock (Eq, Show)

data MermaidOptions = MermaidOptions
  { showWrittenSlots :: Bool
  , showGuardSummary :: Bool
  , guardMode        :: MermaidGuardMode   -- NEW, additive
  }

defaultMermaidOptions :: MermaidOptions
-- showWrittenSlots = False, showGuardSummary = False, guardMode = MermaidGuardHidden

renderGuardSegment :: MermaidOptions -> HsPred rs ci -> Maybe Text
```

`MermaidGuardMode (..)` is added to the module export list. `renderGuardSegment` need not be
exported (it is internal), but exporting it is harmless. The shared-record rule (jointly owned
with EP-63): `MermaidOptions` is extended *additively*; EP-63 appends its layout/output fields
*after* `guardMode`, never reordering, and `defaultMermaidOptions` must stay byte-identical.
EP-63 owns segment *layout*; this plan owns guard *text* via `renderGuardSegment`; the two must
not clobber each other.

**Test modules.** `test/Keiki/Render/PrettySpec.hs` (new, registered in `keiki.cabal:116` area
and `test/Spec.hs`) and the extended `test/Keiki/Render/MermaidSpec.hs`. Both use only `hspec`
(no QuickCheck / Hedgehog).

**Toolchain.** `cabal build keiki`, `cabal test keiki-test`, from the repo root. GHC2024 with
`OverloadedStrings`, `OverloadedRecordDot`, `DuplicateRecordFields` enabled via the cabal
`shared-extensions` import.
