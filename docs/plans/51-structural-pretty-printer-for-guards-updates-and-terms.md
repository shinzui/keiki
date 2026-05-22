---
id: 51
slug: structural-pretty-printer-for-guards-updates-and-terms
title: "Structural pretty-printer for guards, updates, and terms"
kind: exec-plan
created_at: 2026-05-22T00:22:58Z
intention: "intention_01ks6h02qkeywtcgvec3d1wm60"
---

# Structural pretty-printer for guards, updates, and terms

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

This repository, `keiki`, is a pure-Haskell library for building event-sourced
workflow engines. A workflow is modelled as a *symbolic transducer*: a finite-state
machine whose vertices are workflow states and whose edges carry a *guard* (a boolean
condition over stored data and the incoming command), an *update* (how stored data
changes), and an *output* (the event emitted). The guard, update, and output are all
expressed as small abstract-syntax trees ("ASTs" — tree-shaped data describing an
expression rather than running it): `HsPred` for guards, `Update` for updates, `Term`
for the scalar expressions inside both, and `OutTerm` for outputs. These types live in
`src/Keiki/Core.hs`.

Today there is exactly one way to display any of this structure to a human: the Mermaid
diagram renderer in `src/Keiki/Render/Mermaid.hs`. Mermaid is a text-based diagram
language; GitHub and Notion render it inline, so a reviewer sees a state-diagram picture
in a pull request. That renderer labels each edge with just `<input ctor> / <output ctor>`
— the name of the command constructor that triggers the edge and the name of the event
constructor it emits (see `edgeLabel`, `edgeInputName`, and `edgeOutputName` in
`src/Keiki/Render/Mermaid.hs`). It deliberately shows *nothing* about the guard condition
or the update arithmetic. So a reader cannot, from any existing tool, see that an edge
fires only when `appCreditScore >= 650`, or that it sets `itemCount := itemCount + 1`.
There is **no pretty-printer** anywhere in the codebase that turns a `Term`, `HsPred`, or
`Update` back into readable text.

After this change, a developer can call a new function — `prettyPred`, `prettyUpdate`, or
`prettyTerm` in a new module `src/Keiki/Render/Pretty.hs` — on any guard, update, or term
from any aggregate and get back a human-readable string such as
`appCreditScore >= 650` or `itemCount := itemCount + 1` (the latter only once the optional
Milestone 2 lands; before that it reads `itemCount := ‹fn›(itemCount)`). They can see this
working by running the test suite, which feeds real guards and updates from the example
aggregates in `jitsurei/src/Jitsurei/` to the printer and checks the exact output strings.
This unlocks two downstream surfaces (Milestone 3): a standalone "edge inspector" view
that spells out every edge's guard, update, and output in full; and an opt-in fuller-label
mode for the Mermaid renderer. Both are additive — the default Mermaid diagram label
format does not change one byte.

The single deep constraint that shapes the entire plan is this: one corner of the `Term`
AST is fundamentally un-printable. The constructors `TApp1` and `TApp2` (in
`src/Keiki/Core.hs`) carry a raw Haskell function (`a -> r` and `a -> b -> r`). A raw
function value has no `Show` instance and no inspectable structure — there is no way to
recover "this is `(+ 1)`" from a closure at run time. So a *literally complete* printer is
impossible unless that escape hatch is changed to describe itself. This plan therefore
delivers a faithful **structural core first** (Milestone 1), which renders everything that
*does* have structure and prints a clearly-marked placeholder for the opaque function; and
then offers an **optional path to full labels** (Milestone 2) by making the escape hatch
carry an optional human-written label.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] **M1 — structural pretty-printer core.** Create `src/Keiki/Render/Pretty.hs` with
  `prettyTerm`, `prettyPred`, `prettyUpdate`, and `prettyOutTerm`, all returning
  `Data.Text.Text`. Register the module in `keiki.cabal` library `exposed-modules`. Render
  every structural node; render `TApp1`/`TApp2` as a `‹fn›(args…)` placeholder over their
  recursable argument terms; render `TLit` as the placeholder `‹lit›` (no AST change).
- [ ] **M1 — tests.** Create `test/Keiki/Render/PrettySpec.hs`, register it in
  `keiki.cabal` test `other-modules` and in `test/Spec.hs` (both the `import qualified`
  line and a `describe … spec` line). Assert exact output strings for real guards/updates
  from `jitsurei/src/Jitsurei/LoanApplication.hs` and `jitsurei/src/Jitsurei/OrderCart.hs`.
- [ ] **M2 (optional) — self-describing escape hatches.** Add an optional `Maybe Text`
  label to `TApp1`/`TApp2` (or add named smart constructors `tapp1Named`/`tapp2Named`).
  Sweep every total walker that pattern-matches `TApp1`/`TApp2` (enumerated below) to
  carry the new field. Teach `prettyTerm` to print the label when present, the placeholder
  when absent.
- [ ] **M2 (optional) — tests.** Add a named-`TApp` example to `PrettySpec` and assert it
  prints its label; assert an unnamed `TApp` still prints the placeholder; confirm the full
  suite still passes after the walker sweep.
- [ ] **M3 — consumption surface.** Pick and build either (a) an "edge inspector" renderer
  emitting a per-edge detail block, and/or (b) an opt-in fuller-label Mermaid variant.
  Add a golden test proving the *default* `toMermaid` output is byte-identical to before.

(Mark items done only when the named command in Concrete Steps prints the stated output.)


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Deliver the structural core first (Milestone 1), and for the two unprintable
  cases — the opaque `TApp1`/`TApp2` function and a `TLit` whose payload type has no `Show`
  — emit a clearly-marked placeholder (`‹fn›(…)` and `‹lit›`) rather than changing the
  `Term` AST.
  Rationale: This keeps Milestone 1 purely additive: a brand-new module plus a new test
  module, touching no existing constructor signature and therefore no existing walker. A
  `Show r =>` constraint on the `TLit` constructor would be the cleanest faithful rendering
  of literals, but it is a constructor-signature change that ripples through every total
  walker over `Term` and would also force `Show` onto operand types that do not have it.
  The placeholder buys the entire high-value core (slot names, field reads, arithmetic,
  comparisons, set-assignments) at zero blast radius. `Show`-aware overloads can be added
  later as a refinement once the core is proven useful.
  Date: 2026-05-22

- Decision: Full, faithful labels for opaque applications require the escape hatch to
  describe itself; Milestone 2 adds an optional `Maybe Text` label to `TApp1`/`TApp2` (or
  named smart constructors that store one).
  Rationale: A raw Haskell closure carries no `Show` and no structure — there is no
  run-time path from `(+ 1)` back to the text `+ 1`. The only honest way to print it is to
  have the author supply the text when they build the term. This is additive (existing
  unlabelled `TApp` values keep working and keep printing the placeholder) but its cost is
  a mechanical sweep of every total walker that pattern-matches `TApp1`/`TApp2`, because
  adding a field changes the constructor's arity. Milestone 2 is therefore marked optional
  and isolated from Milestone 1.
  Date: 2026-05-22

- Decision: Fuller guard/update/output labels live only in an opt-in or detail surface
  (Milestone 3), never in the default Mermaid topology label.
  Rationale: Two checked-in documents pin this. `docs/guide/deriving-lifecycle-transitions.md`
  teaches a bug-spotting technique that depends on the renderer "deliberately omitting the
  guard" (its words): a missing return arrow is glaring precisely because guards are not
  shown, so two same-input edges that differ only by guard look identical and the absence
  of one jumps out. Putting guards in the default label would defeat that lesson.
  Separately, `docs/masterplans/10-mermaid-topology-renderer-for-symtransducer.md` (its
  "Non-goals" / "Out of scope" section, around lines 102–105 and 245–247) explicitly
  rejects rendering the `HsPred`/`Update` AST inline in topology labels as clutter, and
  anticipates "a richer edge inspector view" as the right home. That is a UX decision,
  distinct from the feasibility question this plan answers; this plan honours it by keeping
  full labels out of the default label and offering them only on an opt-in/detail surface.
  Date: 2026-05-22


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

This section assumes no prior knowledge of the repository. Read it before touching any code.

The library source lives under `src/Keiki/`. The example aggregates ("aggregate" =
a single workflow definition: its states, commands, events, and edges) live under
`jitsurei/src/Jitsurei/` — `jitsurei` (実例, "worked examples") is a separate Cabal
package in the same repository that depends on the library and exercises it. The test
suite lives under `test/`.

The four AST types this plan prints all live in `src/Keiki/Core.hs`. Verify each by
opening the file; line numbers below are approximate and may drift.

The **term language** is the GADT (a "generalised algebraic data type" — a data type
whose constructors can each have a different, more specific result type) `Term` (around
lines 245–273). Its constructors are: `TLit :: r -> Term rs ci r` (a literal constant of
type `r`); `TReg :: Index rs r -> Term rs ci r` (read a stored register / slot named by
the `Index`); `TInpCtorField :: InCtor ci ifs -> Index ifs r -> Term rs ci r` (read field
`ix` of the input command constructor described by `ic`); `TApp1 :: (a -> r) -> Term rs ci a
-> Term rs ci r` and `TApp2 :: (a -> b -> r) -> Term rs ci a -> Term rs ci b -> Term rs ci r`
(the **opaque escape hatches**: apply an arbitrary Haskell function to one or two computed
arguments — the function itself has no `Show` and no inspectable structure); and
`TArith :: (Num r, Typeable r) => NumOp -> Term rs ci r -> Term rs ci r -> Term rs ci r`
(structural arithmetic). `NumOp` (around lines 239–240) is `OpAdd | OpSub | OpMul` and
derives `Show`; these are `+`, `-`, `*`. Authors build arithmetic through the smart
constructors `tadd`/`tsub`/`tmul` (re-exported as the operators `.+`/`.-`/`.*`), so a
guard over a *computed* value stays structural and visible — only `TApp1`/`TApp2` are
opaque.

A **slot** is a named stored register; the type parameter `rs :: [Slot]` is the list of
all slots (each a `(name, type)` pair). The names of slots and constructors are recoverable
at run time through these helpers (verify each):

- `indexName :: Index rs r -> String` — the slot name for a register read. **Correction to
  the original brief:** this helper lives in `src/Keiki/Symbolic.hs` (around line 485), not
  in `src/Keiki/Core.hs`. It is *not* currently exported from `Keiki.Symbolic`'s module
  header. The new printer module must obtain a slot name for `TReg`; rather than depend on
  `Keiki.Symbolic` (which would pull the SBV/SMT solver dependency into a pure renderer) or
  widen that module's export list, the cleanest move is to copy this tiny two-line walker
  into `src/Keiki/Render/Pretty.hs` as a private helper. It is three lines:
  `indexName (ZIdx @s) = symbolVal (Proxy @s)` and `indexName (SIdx i) = indexName i`,
  where `ZIdx`/`SIdx` are `Index`'s constructors. Inspect `src/Keiki/Symbolic.hs` lines
  485–487 to copy it verbatim, and inspect `Index`'s definition in `src/Keiki/Core.hs` to
  confirm the constructor names and that `ZIdx` carries the `KnownSymbol s` evidence needed
  by `symbolVal`.
- `icName :: InCtor ci ifs -> String` — the input constructor's name; it is a record field
  of the `InCtor` constructor (around lines 297–304 of `src/Keiki/Core.hs`).
- `wcName :: WireCtor co fields -> String` — the output wire constructor's name; a record
  field of `WireCtor` (around lines 404–408).
- `indexNName :: KnownSymbol s => IndexN s rs r -> String` — the slot name for an update's
  write target. This one lives in `src/Keiki/Internal/Slots.hs` (around line 134) and *is*
  exported from that module's header. `USet` uses `IndexN` (a slot-name-tagged index), not
  `Index`, so this is the helper to call for the left-hand side of a `USet`.
- For the *field name* read by `TInpCtorField ic ix`, note that `ix :: Index ifs r` is a
  plain `Index`, so the same `indexName`-style walk recovers the field name; the printer can
  reuse its private `indexName` helper here too.

The **predicate (guard) AST** is the GADT `HsPred` (around lines 462–488 of
`src/Keiki/Core.hs`). Its constructors: `PTop` (always true), `PBot` (always false),
`PAnd a b`, `POr a b`, `PNot p`, `PEq :: (Eq r, Typeable r) => Term rs ci r -> Term rs ci r
-> HsPred rs ci` (two terms compared for equality), `PInCtor :: InCtor ci ifs -> HsPred rs ci`
(true iff the input is the named constructor), and `PCmp :: (Ord r, Typeable r) => Cmp ->
Term rs ci r -> Term rs ci r -> HsPred rs ci` (an ordering comparison). `Cmp` (around lines
497–498) is `CmpLt | CmpLe | CmpGt | CmpGe`, derives `Show`, and means `<`, `<=`, `>`, `>=`.

The **update AST** is the GADT `Update` (around lines 374–394). Its constructors: `UKeep`
(leave all slots unchanged), `USet :: KnownSymbol s => IndexN s rs r -> Term rs ci r ->
Update rs '[s] ci` (set the slot named `s` to the value of the term), and `UCombine ::
Update rs w1 ci -> Update rs w2 ci -> Update rs (Concat w1 w2) ci` (do two updates to
disjoint slot sets). The type parameter `w :: [Symbol]` is the "write set" — the names of
the slots this update writes.

The **output term AST** is `OutTerm` (around line 442–454), whose single constructor is
`OPack :: InCtor ci ifs -> WireCtor co fields -> OutFields rs ci fields -> OutTerm rs ci co`:
it tags the consumed input constructor, the produced wire constructor, and an HList
("heterogeneous list" — a list whose elements may have different types) of `Term`s, one per
field of the wire constructor. That HList is `OutFields` (around lines 414–418), with
constructors `OFNil` and `OFCons (Term rs ci f) (OutFields rs ci fs)`.

The **existing structural-walk precedent** is `edgeInputName` in
`src/Keiki/Render/Mermaid.hs` (around lines 513–524). It folds an `HsPred` looking for the
leftmost `PInCtor` and returns its `icName`. Read it: it is the template for the recursive
shape of `prettyPred` (match each constructor, recurse on sub-predicates), differing only
in that the new printer renders *every* node instead of extracting a single name. Note that
`Keiki.Render.Mermaid` already imports `HsPred (..)`, `InCtor (..)`, `OutTerm (..)`, and
`WireCtor (..)` from `Keiki.Core` — the new module will import the same set plus `Term (..)`,
`Update (..)`, `OutFields (..)`, `NumOp (..)`, and `Cmp (..)`.

The Mermaid renderer's hard constraint is captured in two checked-in documents that you must
respect (do not weaken them): `docs/guide/deriving-lifecycle-transitions.md` (around lines
30–44) explains that the renderer "deliberately omits the guard" and that a teaching
technique depends on it; and `docs/masterplans/10-mermaid-topology-renderer-for-symtransducer.md`
(around lines 102–105 and 245–247) records the decision that guard/update AST in topology
labels is clutter and that an "edge inspector" view is the right home for full detail.

Two related but independent plans exist as checked-in files. This plan is **independent and
stands alone** — you need nothing from them to implement it — but they are cited for context.
`docs/plans/50-mermaid-renderer-atlas-entry-point-and-structural-edge-summary-annotations.md`
adds a *shallow structural summary* annotation to edges (a compact, lossy hint such as a
guard's input-constructor name plus a flag that there is more). The pretty-printer in this
plan is the *deep, full-fidelity* cousin of that summary: where EP-50 says "this edge has a
guard", this plan can render the guard's actual text. The two can coexist; this plan could
later supersede or feed EP-50's summary, but neither depends on the other.
`docs/masterplans/10-mermaid-topology-renderer-for-symtransducer.md` is the originating
design record for the Mermaid renderer and the source of the "no full AST in labels"
decision quoted above.


## Plan of Work

The work is three milestones. Milestone 1 is the high-value, fully self-contained core and
should be done first. Milestone 2 is an optional, additive AST change that unlocks fully
faithful labels for the opaque escape hatch. Milestone 3 is the consumption surface that
shows the fuller labels somewhere a user will look. Each milestone is independently
verifiable.


### Milestone 1 — the structural pretty-printer (the high-value core)

Scope: create one new library module and one new test module. At the end of this milestone,
a developer can call `prettyTerm`, `prettyPred`, `prettyUpdate`, and `prettyOutTerm` on any
guard, update, term, or output from any aggregate and get a readable `Data.Text.Text` back,
and the test suite proves the exact output for real examples. No existing source file
changes except `keiki.cabal` (to register the two new modules) and `test/Spec.hs` (to wire
the new spec into the manual aggregator).

Create `src/Keiki/Render/Pretty.hs`. Make it a sibling of `Keiki.Render.Mermaid` with a
module header that exports the four entry points:

    module Keiki.Render.Pretty
      ( prettyTerm
      , prettyPred
      , prettyUpdate
      , prettyOutTerm
      ) where

Import `Data.Text (Text)` and `qualified Data.Text as T`, and from `Keiki.Core` import
`Cmp (..)`, `HsPred (..)`, `InCtor (..)`, `NumOp (..)`, `OutFields (..)`, `OutTerm (..)`,
`Term (..)`, `Update (..)`, and `WireCtor (..)`. Also import what `indexName` needs:
`Data.Proxy (Proxy (..))` and `GHC.TypeLits (KnownSymbol, symbolVal)`, plus `Index`'s
constructors from `Keiki.Core` (confirm their exported names — they are `ZIdx` and `SIdx`;
read `src/Keiki/Core.hs` to verify both the constructor names and that `Index (..)` or the
individual constructors are exported, and add to the export list if not). From
`Keiki.Internal.Slots` import `indexNName`.

Write the private slot-name helper by copying the three lines from `src/Keiki/Symbolic.hs`
(lines ~485–487):

    indexName :: forall rs r. Index rs r -> String
    indexName (ZIdx @s) = symbolVal (Proxy @s)
    indexName (SIdx i)  = indexName i

Now write `prettyTerm`, recursing structurally and returning `Text`:

    prettyTerm :: Term rs ci r -> Text
    prettyTerm (TLit _)              = T.pack "\x2039lit\x203A"        -- ‹lit›
    prettyTerm (TReg ix)             = T.pack (indexName ix)
    prettyTerm (TInpCtorField _ ix)  = T.pack (indexName ix)
    prettyTerm (TApp1 _ a)           =
      T.pack "\x2039fn\x203A(" <> prettyTerm a <> T.pack ")"          -- ‹fn›(a)
    prettyTerm (TApp2 _ a b)         =
      T.pack "\x2039fn\x203A(" <> prettyTerm a <> T.pack ", "
        <> prettyTerm b <> T.pack ")"
    prettyTerm (TArith op a b)       =
      prettyTerm a <> T.pack " " <> numOpSym op <> T.pack " " <> prettyTerm b

where `numOpSym OpAdd = T.pack "+"`, `numOpSym OpSub = T.pack "-"`, `numOpSym OpMul =
T.pack "*"`. The characters `‹` and `›` are the single-guillemet marks `U+2039`/`U+203A`;
they make the placeholder visually unmistakable and cannot collide with a slot name (which
matches the identifier regex `[A-Za-z_][A-Za-z0-9_]*`). The Mermaid renderer already emits
non-ASCII (`\x03B5`, the ε character, in `edgeLabel`), so non-ASCII output is established
practice in this codebase.

For `TInpCtorField _ ix` the printer renders just the field name. If you prefer the fuller
`ctor.field` form, render `T.pack (icName ic) <> T.pack "." <> T.pack (indexName ix)` and
bind the `ic` instead of discarding it; choose one form and keep the tests consistent with
it. The plan's worked examples below use the bare field name, which is what an aggregate
author reads in their guard source (e.g. `appCreditScore`).

Write `prettyPred` mirroring `edgeInputName`'s recursion shape but rendering every node:

    prettyPred :: HsPred rs ci -> Text
    prettyPred PTop          = T.pack "true"
    prettyPred PBot          = T.pack "false"
    prettyPred (PAnd a b)    = paren a <> T.pack " && " <> paren b
    prettyPred (POr  a b)    = paren a <> T.pack " || " <> paren b
    prettyPred (PNot p)      = T.pack "!" <> paren p
    prettyPred (PEq  a b)    = prettyTerm a <> T.pack " == " <> prettyTerm b
    prettyPred (PInCtor ic)  = T.pack "is " <> T.pack (icName ic)
    prettyPred (PCmp op a b) =
      prettyTerm a <> T.pack " " <> cmpSym op <> T.pack " " <> prettyTerm b

with `cmpSym CmpLt = "<"`, `cmpSym CmpLe = "<="`, `cmpSym CmpGt = ">"`, `cmpSym CmpGe =
">="`, and `paren` a small helper that wraps a sub-predicate in parentheses only when it is
a compound (`PAnd`/`POr`/`PNot`) so that atoms like `appCreditScore >= 650` are not
needlessly parenthesised. A correct, minimal `paren` is:

    paren :: HsPred rs ci -> Text
    paren p@(PAnd _ _) = T.pack "(" <> prettyPred p <> T.pack ")"
    paren p@(POr  _ _) = T.pack "(" <> prettyPred p <> T.pack ")"
    paren p            = prettyPred p

Decide once whether the *top-level* call adds outer parentheses; the worked examples below
assume the top level does **not** parenthesise, so call `prettyPred` (not `paren`) at the
entry point. Right-nested conjunctions — which is how the builder operators `.&&` associate
— then render flat: `a && b && c` rather than `a && (b && c)`, because each right operand
of a `PAnd` is itself either an atom (no parens) or a deeper `PAnd` whose own rendering is
again parenthesised by `paren`. Verify the exact parenthesisation against the worked
example for `approvalGuard` below and adjust `paren` if your chosen associativity differs;
the test is the source of truth.

Write `prettyUpdate`:

    prettyUpdate :: Update rs w ci -> Text
    prettyUpdate UKeep         = T.pack "keep"
    prettyUpdate (USet ix t)   =
      T.pack (indexNName ix) <> T.pack " := " <> prettyTerm t
    prettyUpdate (UCombine a b) =
      prettyUpdate a <> T.pack "; " <> prettyUpdate b

Note `USet` uses `indexNName` (the `IndexN` helper from `Keiki.Internal.Slots`), not the
private `indexName`. `UCombine` joins the two halves with `"; "`, matching how
`edgeOutputName` joins a length-2 output list in the Mermaid renderer.

Write `prettyOutTerm`, walking the `OutFields` HList:

    prettyOutTerm :: OutTerm rs ci co -> Text
    prettyOutTerm (OPack _ wc fields) =
      T.pack (wcName wc) <> T.pack "(" <> prettyFields fields <> T.pack ")"
      where
        prettyFields :: OutFields rs ci fs -> Text
        prettyFields OFNil          = T.empty
        prettyFields (OFCons t OFNil) = prettyTerm t
        prettyFields (OFCons t rest)  =
          prettyTerm t <> T.pack ", " <> prettyFields rest

This renders an output as `WireCtorName(field1, field2, …)`. Confirm `OutFields`'s
constructors (`OFNil`, `OFCons`) by reading `src/Keiki/Core.hs` around lines 414–418.

Register the module: open `keiki.cabal`, find the `library` stanza's `exposed-modules`
(around lines 56–68, where `Keiki.Render.Mermaid` already appears), and add
`Keiki.Render.Pretty` to the list, keeping alphabetical-ish order next to the existing
`Keiki.Render.Mermaid` line.

Commands to run (from the repository root `/Users/shinzui/Keikaku/bokuno/keiki`):

    cabal build keiki

Acceptance for the build half: the library compiles with the new module. Then write the
tests (next paragraph) and run them.

Create the test module `test/Keiki/Render/PrettySpec.hs`. The keiki test suite is a
**manual aggregator**, not `hspec-discover`: every spec module is listed explicitly in
`test/Spec.hs` with an `import qualified … Spec` line and a matching `describe … spec` line
inside `main`, and it is also listed in `keiki.cabal`'s test stanza `other-modules`. The
test dependencies are `hspec` only — there is **no QuickCheck and no Hedgehog** — so any
"property" must be a finite enumeration of explicit cases, not a randomized generator.

The spec must construct real guards and updates and assert the exact printed strings.
The richest real examples are:

- From `jitsurei/src/Jitsurei/LoanApplication.hs`, the value `approvalGuard` (around lines
  431–436). It is `appCreditScore >= approvalThresholdScore && appEmploymentVerified ==
  True && appRequestedAmount <= appCreditScore * 1000`, built with the operators `.>=`
  (→ `PCmp CmpGe`), `.&&` (→ `PAnd`), `.==` (→ `PEq`), `.<=` (→ `PCmp CmpLe`), `.*`
  (→ `tmul`, i.e. `TArith OpMul`), `proj` (→ `TReg` via `OverloadedLabels`), and `lit`
  (→ `TLit`). `approvalThresholdScore` is a named constant (read the file for its value;
  the threshold is described as 650 in the module docs around lines 18–24). The literal
  `appCreditScore * 1000` renders the slot name on the left and the placeholder `‹lit›` for
  the `1000` literal (because Milestone 1 does not require `Show` on `TLit`).
- From `jitsurei/src/Jitsurei/OrderCart.hs`, the `OpenWithItems` self-loop on `AddItem`
  (around lines 540–541): `update = USet #itemCount (TApp1 (+ 1) (proj #itemCount))`. This
  is the canonical real `TApp1` case. Under Milestone 1 it prints `itemCount := ‹fn›(itemCount)`.
  The sibling `RemoveItem` edge (around lines 553–555) uses `TApp1 (subtract 1) (proj
  #itemCount)` and prints `itemCount := ‹fn›(itemCount)` as well — these two opaque
  closures are indistinguishable in the structural core, which is exactly the motivation
  for Milestone 2. Also useful: the `Empty` edge's `USet #itemCount (lit (1 :: ItemCount))`
  (around lines 524–525), which prints `itemCount := ‹lit›`.

For the spec, you do not need to import the whole aggregate if that pulls in heavy
machinery; you may either import the named values directly from the `jitsurei` package (add
`jitsurei` to the test stanza's `build-depends` if it is not already a dependency — check
first) or, more robustly and with zero new dependency, construct small equivalent guards
and updates inline in the spec using the public AST constructors and the same operators.
Constructing inline keeps the test self-contained and avoids coupling the test to the
example package's build. Prefer the inline approach: build, for instance,

    -- a slot list and an index for a register named "appCreditScore"
    -- (use the same OverloadedLabels / proj surface the aggregates use,
    --  or the raw TReg with a hand-built Index — read CoreSpec.hs and
    --  Render/MermaidSpec.hs for the established way to build test ASTs)

Read `test/Keiki/Render/MermaidSpec.hs` and `test/Keiki/CoreSpec.hs` first to copy the
project's established idiom for constructing `Term`/`HsPred`/`Update` test values; reuse
that idiom so the spec matches house style.

The expected-output assertions (see the exact transcripts in Validation and Acceptance)
are, at minimum: a `PCmp CmpGe` over a register and a literal prints `appCreditScore >= ‹lit›`
(or, if you build the comparison against a structural `tmul`, `appCreditScore >= … * ‹lit›`);
the `approvalGuard`-shaped conjunction prints with `&&` joiners; `USet #itemCount (TApp1 (+ 1)
(proj #itemCount))` prints `itemCount := ‹fn›(itemCount)`; and `USet #itemCount (lit 1)`
prints `itemCount := ‹lit›`.

Register the spec in both places. In `keiki.cabal`, add `Keiki.Render.PrettySpec` to the
test stanza `other-modules` (around lines 86–110, next to `Keiki.Render.MermaidSpec`). In
`test/Spec.hs`, add `import qualified Keiki.Render.PrettySpec` near the other imports and a
line `describe "Keiki.Render.Pretty (EP-51)" Keiki.Render.PrettySpec.spec` inside `main`'s
`hspec $ do` block, next to the existing `Keiki.Render.Mermaid` describe line.

Commands and acceptance:

    cabal test keiki-test

Expect a final summary of the form `N examples, 0 failures` (where `N` is the previous
total plus the number of cases you added). The new `Keiki.Render.Pretty (EP-51)` describe
block must appear in the output with all its examples passing.


### Milestone 2 — optional path to full labels (self-describing escape hatches)

Scope: make the opaque `TApp1`/`TApp2` escape hatch carry an optional human-written label,
so an application that the author chooses to name prints meaningfully (e.g. `itemCount + 1`
or a named operation) while unlabelled applications keep printing the Milestone 1
placeholder. At the end of this milestone a named `TApp` prints its label, an unnamed one
prints the placeholder, and the entire existing test suite still passes after the walker
sweep. This milestone is **optional** and **additive** but its cost is a mechanical sweep
of every total walker that pattern-matches `TApp1`/`TApp2`, because changing a constructor's
fields changes its arity and every match site must be updated.

There are two viable shapes; choose one and record the choice in the Decision Log.

Shape A — add a field to the constructors. Change `TApp1` and `TApp2` in `src/Keiki/Core.hs`
to carry a `Maybe Text` (or a `Maybe String` to avoid adding a `text` import to `Core.hs` —
check whether `Core.hs` already imports `Data.Text`; if not, `Maybe String` keeps the
dependency footprint unchanged). For example:

    TApp1 :: Maybe Label -> (a -> r) -> Term rs ci a -> Term rs ci r
    TApp2 :: Maybe Label -> (a -> b -> r) -> Term rs ci a -> Term rs ci b -> Term rs ci r

with `type Label = String` (or `Text`). Then provide smart constructors so the common cases
read well: `tapp1 f a = TApp1 Nothing f a`, `tapp1Named lbl f a = TApp1 (Just lbl) f a`, and
the `tapp2`/`tapp2Named` analogues. Existing call sites that wrote `TApp1 f a` directly
(for example in `jitsurei/src/Jitsurei/OrderCart.hs` lines ~541 and ~554) must change to
either `TApp1 Nothing f a` or the `tapp1` smart constructor — prefer migrating them to the
smart constructor so future call sites never see the raw `Maybe` field.

Shape B — keep the constructors as they are and add *parallel* named constructors. This
avoids touching the existing walkers entirely but means two ways to build an application
exist; it is simpler to land but leaves the older opaque form un-printable forever. Shape A
is recommended because it makes every `TApp` uniformly carry the optional label and the
sweep, while mechanical, is bounded and verifiable.

If you take Shape A, you must update every **total walker** that pattern-matches `TApp1` or
`TApp2`. Enumerate them by reading the source (verified for this plan; line numbers
approximate):

- `evalTerm` in `src/Keiki/Core.hs` (around lines 734–735): the term evaluator. Ignore the
  new label field; keep applying the function.
- `translateTermSym` in `src/Keiki/Symbolic.hs` (around lines 442–443): the SMT translator,
  which already emits a fresh opaque solver variable for `TApp1`/`TApp2` (`SBV.free "app1"`
  / `"app2"`). Add the new field to the patterns; behaviour is unchanged (the label does not
  make the closure solver-visible).
- `goTerm` inside `checkHiddenInputs` in `src/Keiki/Core.hs` (around lines 1177–1178).
- `stepOne` inside `gatherInpEntries` in `src/Keiki/Core.hs` (around lines 1069–1070).
- `termReadsInput` in `src/Keiki/Core.hs` (around lines 1212–1213).
- `termHasInpCtorField` (the helper inside `detectMissingInCtorFields`'s neighbourhood) in
  `src/Keiki/Core.hs` (around lines 1227–1228), and `goTerm` inside
  `detectMissingInCtorFields` itself (around lines 1269–1270).
- The composition lifters in `src/Keiki/Composition.hs`: `weakenLTerm` (lines ~162–166),
  `weakenRTerm` (lines ~221–225), `substTerm` (lines ~375–379), `liftLTermAlt` (lines
  ~542–546), and `liftRTermAlt` (lines ~557–561). Each reconstructs a `TApp1`/`TApp2`, so
  each must thread the label through unchanged.
- The two `go` walkers in `Keiki.Profunctor`'s contravariant remap, in
  `src/Keiki/Profunctor.hs` (around lines 821–822 and 833–834). Each rebuilds
  `TApp1 h (go a)` / `TApp2 h (go a) (go b)`; thread the label through unchanged.

A reliable way to find every remaining site after you change the constructor is to let the
compiler enumerate them: make the change, then run `cabal build all` and fix each
"constructor `TApp1` should have N arguments" error in turn. The list above is the expected
set; if the compiler reports a site not on this list, add it to the list in this plan (so
the plan stays accurate) and to the Surprises section.

Then teach the printer: in `src/Keiki/Render/Pretty.hs`, change the `TApp1`/`TApp2` cases to
print the label when present and the placeholder when absent:

    prettyTerm (TApp1 (Just lbl) _ a) =
      T.pack lbl   -- or a richer form that also shows the argument
    prettyTerm (TApp1 Nothing  _ a) =
      T.pack "\x2039fn\x203A(" <> prettyTerm a <> T.pack ")"

Decide whether a named unary application prints just the label, or the label applied to its
argument (e.g. a label `"+ 1"` rendered as `itemCount + 1`). For the OrderCart example,
storing the label `"+ 1"` and rendering `prettyTerm a <> " " <> T.pack lbl` yields
`itemCount + 1`, which reads best; record the chosen convention in the Decision Log so all
call sites name their applications consistently.

Commands and acceptance:

    cabal build all
    cabal test keiki-test

Acceptance: a `TApp` built with `tapp1Named "+ 1" (+ 1) (proj #itemCount)` prints
`itemCount + 1` (or `+ 1` if you chose the bare-label convention); an unnamed `TApp` still
prints `‹fn›(itemCount)`; and the suite reports `0 failures`, proving the walker sweep
preserved every existing behaviour. Add the named/unnamed cases to `PrettySpec`.


### Milestone 3 — consumption surface (where the fuller labels are shown)

Scope: build a rendering surface that *uses* the printer, without disturbing existing
defaults. At the end of this milestone there is a place a user can look to read full
structural guard/update/output text for each edge, and a golden test proves the default
`toMermaid` output is byte-identical to before. The critical constraint, restated: the
default Mermaid topology label format must stay guard-free and byte-identical, because
`docs/guide/deriving-lifecycle-transitions.md` teaches a bug-spotting technique that relies
on guards being omitted, and `docs/masterplans/10-mermaid-topology-renderer-for-symtransducer.md`
rejected full AST in topology labels as clutter. Full labels therefore belong only in an
opt-in or detail surface.

Two faithful options; pick one (or both) and record the choice:

Option (a) — an "edge inspector" renderer. Add a function (in `src/Keiki/Render/Pretty.hs`
or a new sibling `src/Keiki/Render/EdgeInspector.hs`) that takes a transducer and emits, per
edge, a detail block spelling out the guard (`prettyPred (guard e)`), the update
(`prettyUpdate (update e)`), and the outputs (`prettyOutTerm` over each element of
`output e`), grouped by source vertex. This is exactly the "richer edge inspector view"
that the masterplan anticipates as the correct home for full detail. The output can be
plain text or a Markdown list — it is a separate artefact from the topology diagram, so it
does not touch `toMermaid` at all. Read the `Edge` record's fields (`guard`, `update`,
`output`, `target`) in `src/Keiki/Core.hs` and the vertex-enumeration pattern in
`renderTopology` (`src/Keiki/Render/Mermaid.hs` lines ~458–482) for how to walk
`[minBound .. maxBound]` and `edgesOut`.

Option (b) — an opt-in fuller-label Mermaid variant. Add a *new* entry point alongside
`toMermaid` (for example `toMermaidWithGuards`) that builds an edge label combining the
existing `edgeLabel e` with `prettyPred (guard e)` and `prettyUpdate (update e)`. Crucially,
do not change `toMermaid`, `edgeLabel`, `edgeInputName`, or `edgeOutputName`; the new
function is a separate code path. If EP-50's structural-summary annotation has landed by the
time you do this, this fuller variant can be offered as the "expand the summary" mode that
EP-50 leaves room for.

Whichever you build, add a **golden test** that asserts the *default* `toMermaid` output for
a representative aggregate is unchanged. The simplest form: in
`test/Keiki/Render/MermaidSpec.hs` (or `PrettySpec`), assert `toMermaid someAggregate` equals
the exact string it produced before this plan — copy the current expected string from the
existing Mermaid spec, or capture it once and pin it. The point is to fail loudly if any
edit in this milestone leaks a guard into the default label.

Commands and acceptance:

    cabal test keiki-test

Acceptance: the new detail/opt-in view, when run on a representative aggregate (use
LoanApplication or OrderCart), shows full structural labels — for OrderCart's `OpenWithItems`
`AddItem` edge, the inspector shows `is AddItem`, `itemCount := itemCount + 1` (if Milestone
2 landed) or `itemCount := ‹fn›(itemCount)` (if not), and the `ItemAdded(...)` output. The
default-`toMermaid` golden assertion passes, proving the topology label is byte-identical.


## Concrete Steps

Run all commands from the repository root, `/Users/shinzui/Keikaku/bokuno/keiki`.

First, confirm the ground truth before editing (these are read-only and safe to repeat):

    grep -n "TApp1\|TApp2\|TArith\|TReg\|TLit\|TInpCtorField" src/Keiki/Core.hs
    grep -n "data HsPred\|PCmp\|PEq\|PInCtor\|data Cmp" src/Keiki/Core.hs
    grep -n "data Update\|UKeep\|USet\|UCombine" src/Keiki/Core.hs
    grep -n "indexName" src/Keiki/Symbolic.hs
    grep -n "indexNName" src/Keiki/Internal/Slots.hs

Expected: the constructor signatures match the Context section; `indexName` is at
`src/Keiki/Symbolic.hs:485`; `indexNName` is at `src/Keiki/Internal/Slots.hs:134`.

Milestone 1, create the module:

    # write src/Keiki/Render/Pretty.hs with the four entry points (see Plan of Work)
    # add `Keiki.Render.Pretty` to keiki.cabal library exposed-modules
    cabal build keiki

Expected: `keiki` builds with no errors. If GHC complains that `ZIdx`/`SIdx` are not in
scope, add `Index (..)` (or the two constructors by name) to `Keiki.Core`'s export list and
import them; rebuild.

Milestone 1, create and wire the test:

    # write test/Keiki/Render/PrettySpec.hs (see Plan of Work for the assertions)
    # add Keiki.Render.PrettySpec to keiki.cabal test other-modules
    # add the import + describe line to test/Spec.hs
    cabal test keiki-test

Expected tail of the output (the example count `N` is your prior total plus the cases added):

    Keiki.Render.Pretty (EP-51)
      prettyPred renders a >= comparison
      prettyUpdate renders a TApp1 update as a placeholder
      prettyUpdate renders a literal set as a placeholder
      ...

    Finished in 0.0xxx seconds
    N examples, 0 failures

Milestone 2 (optional), change the constructor and sweep:

    # edit src/Keiki/Core.hs: add the Maybe label field to TApp1/TApp2
    # add tapp1/tapp1Named/tapp2/tapp2Named smart constructors and export them
    cabal build all   # let GHC enumerate every walker that must change

Then fix each reported site (the expected set is enumerated in Milestone 2), re-run
`cabal build all` until clean, update the printer's `TApp` cases, and:

    cabal test keiki-test

Expected: `0 failures`, plus the new named/unnamed `TApp` examples passing.

Milestone 3, build the consumption surface and pin the golden:

    # add the edge-inspector function and/or the opt-in Mermaid variant
    # add a golden assertion that default toMermaid output is unchanged
    cabal test keiki-test

Expected: `0 failures`, including the default-`toMermaid` golden assertion.


## Validation and Acceptance

Validation is behavioural: feed concrete, real guards/updates/terms to the printer and
check the exact strings, and prove the default Mermaid output is unchanged.

For Milestone 1, the following are the acceptance transcripts. (`prettyPred` /
`prettyUpdate` / `prettyTerm` results are shown as the `Text` they return.) Build the inputs
from the public AST surface as the example aggregates do.

A single ordering comparison — `proj #appCreditScore .>= lit 650` — which is `PCmp CmpGe
(TReg appCreditScore) (TLit 650)`:

    prettyPred (PCmp CmpGe (proj #appCreditScore) (lit 650))
      == "appCreditScore >= \x2039lit\x203A"
    -- displayed: appCreditScore >= ‹lit›

The structural cap conjunct from `approvalGuard` —
`proj #appRequestedAmount .<= proj #appCreditScore .* lit 1000` — which is
`PCmp CmpLe (TReg appRequestedAmount) (TArith OpMul (TReg appCreditScore) (TLit 1000))`:

    prettyPred (PCmp CmpLe (proj #appRequestedAmount)
                           (proj #appCreditScore .* lit 1000))
      == "appRequestedAmount <= appCreditScore * \x2039lit\x203A"
    -- displayed: appRequestedAmount <= appCreditScore * ‹lit›

The OrderCart `OpenWithItems`/`AddItem` update —
`USet #itemCount (TApp1 (+ 1) (proj #itemCount))`:

    prettyUpdate (USet #itemCount (TApp1 (+ 1) (proj #itemCount)))
      == "itemCount := \x2039fn\x203A(itemCount)"
    -- displayed: itemCount := ‹fn›(itemCount)

The OrderCart `Empty`/`AddItem` update — `USet #itemCount (lit (1 :: ItemCount))`:

    prettyUpdate (USet #itemCount (lit 1))
      == "itemCount := \x2039lit\x203A"
    -- displayed: itemCount := ‹lit›

If you also assert the full `approvalGuard` (a three-way right-nested `PAnd`), the expected
rendering with the chosen flat-conjunction parenthesisation is:

    appCreditScore >= \x2039lit\x203A && appEmploymentVerified == \x2039lit\x203A && appRequestedAmount <= appCreditScore * \x2039lit\x203A
    -- displayed: appCreditScore >= ‹lit› && appEmploymentVerified == ‹lit› && appRequestedAmount <= appCreditScore * ‹lit›

(The `== ‹lit›` for `appEmploymentVerified == True` reflects that `True` is a `TLit Bool`,
which Milestone 1 renders as the placeholder; Milestone 2 with a labelled literal-rendering
refinement, or a future `Show`-aware overload, would render `True`.)

For Milestone 2, the acceptance is that a *named* application prints meaningfully and an
unnamed one still prints the placeholder:

    prettyUpdate (USet #itemCount (tapp1Named "+ 1" (+ 1) (proj #itemCount)))
      == "itemCount := itemCount + 1"     -- with the "label after argument" convention
    prettyUpdate (USet #itemCount (tapp1 (+ 1) (proj #itemCount)))
      == "itemCount := \x2039fn\x203A(itemCount)"

For Milestone 3, the acceptance is the edge inspector showing full text for a real edge and
the default Mermaid golden remaining unchanged. Concretely, the inspector for OrderCart's
`OpenWithItems` `AddItem` edge contains the lines (text form; exact framing is your design):

    OpenWithItems --AddItem--> OpenWithItems
      guard:  is AddItem
      update: itemCount := itemCount + 1
      output: ItemAdded(sku, quantity, price, at)

and the golden assertion `toMermaid orderCart == <pinned previous string>` passes,
demonstrating the topology label format did not change.

The exact test command for every milestone, run from the repository root, is:

    cabal test keiki-test

A successful run ends with `N examples, 0 failures`. A failure prints the failing example's
name, the expected string, and the actual string, so a mismatch is unambiguous. The keiki
suite uses `hspec` only (no QuickCheck, no Hedgehog — confirmed in `keiki.cabal`'s test
`build-depends`), so every assertion is a concrete, finite case.


## Idempotence and Recovery

Milestone 1 is purely additive: it creates two new files and adds two lines to `keiki.cabal`
and two lines to `test/Spec.hs`. Re-running the steps is safe; if the build fails, the only
state changed is the new files and the four registration lines, all trivially revertible
with `git checkout -- keiki.cabal test/Spec.hs` and `git rm` of the new files. Nothing in
Milestone 1 changes existing behaviour, so it cannot break the existing suite.

Milestone 2 changes a constructor signature and is the only risky step. Do it on a clean
working tree so `git diff` shows exactly the sweep. The recovery path is the compiler
itself: until every walker is updated, `cabal build all` fails with explicit
"`TApp1` should have N arguments" errors naming each unfixed site, so a half-done sweep is
never silently wrong — it simply does not compile. If you need to abandon Milestone 2,
`git checkout -- .` restores the pre-sweep tree; Milestone 1 stands alone and remains valid.

Milestone 3 is additive (new functions, new entry points) plus one golden assertion. If the
golden fails, it means a Milestone 3 edit leaked into the default label path; revert that
edit. Re-running is safe.


## Interfaces and Dependencies

The new library module is `src/Keiki/Render/Pretty.hs`, registered in `keiki.cabal`'s
`library` stanza under `exposed-modules`. It depends only on `Data.Text` (already a library
dependency), `Data.Proxy`, `GHC.TypeLits`, `Keiki.Core` (for the AST types and `icName`,
`wcName`), and `Keiki.Internal.Slots` (for `indexNName`). It must **not** depend on
`Keiki.Symbolic`, to keep the pure renderer free of the SBV/SMT solver dependency; the small
`indexName` helper it needs is copied in as a private function rather than imported.

At the end of Milestone 1 these functions exist with these signatures (all in
`Keiki.Render.Pretty`):

    prettyTerm    :: Term rs ci r        -> Data.Text.Text
    prettyPred    :: HsPred rs ci        -> Data.Text.Text
    prettyUpdate  :: Update rs w ci      -> Data.Text.Text
    prettyOutTerm :: OutTerm rs ci co    -> Data.Text.Text

At the end of Milestone 2 (if taken, Shape A) these additional smart constructors exist in
`Keiki.Core`, exported from its module header:

    tapp1      :: (a -> r) -> Term rs ci a -> Term rs ci r
    tapp1Named :: Label -> (a -> r) -> Term rs ci a -> Term rs ci r
    tapp2      :: (a -> b -> r) -> Term rs ci a -> Term rs ci b -> Term rs ci r
    tapp2Named :: Label -> (a -> b -> r) -> Term rs ci a -> Term rs ci b -> Term rs ci r

with the `TApp1`/`TApp2` constructors gaining a leading `Maybe Label` field, where
`type Label = String` (or `Text`).

At the end of Milestone 3, the consumption surface adds either an edge-inspector function
(in `Keiki.Render.Pretty` or `Keiki.Render.EdgeInspector`) or an opt-in Mermaid entry point
such as `toMermaidWithGuards` in `Keiki.Render.Mermaid`, exported from the respective module
header. The existing `toMermaid`, `edgeLabel`, `edgeInputName`, and `edgeOutputName` keep
their current signatures and behaviour unchanged.

The test module is `test/Keiki/Render/PrettySpec.hs`, exporting `spec :: Test.Hspec.Spec`,
registered in `keiki.cabal`'s test stanza `other-modules` and wired into `test/Spec.hs`
(both the `import qualified` and the `describe … spec` line). The test suite name is
`keiki-test`; the only test framework dependency is `hspec` (version `^>= 2.11`).
