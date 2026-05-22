---
id: 49
slug: builder-ergonomics-assignment-synonym-and-register-read-label-helper
title: "Builder ergonomics: assignment synonym and register-read label helper"
kind: exec-plan
created_at: 2026-05-21T22:59:23Z
intention: "intention_01ks6ber3jedc8ff6zzma2jr53"
master_plan: "docs/masterplans/13-keiki-api-improvements-surfaced-by-the-rei-migration.md"
---

# Builder ergonomics: assignment synonym and register-read label helper

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

This repository is `keiki`, a pure-Haskell library for event sourcing built on a
"symbolic-register finite-state transducer" — a state machine whose states ("vertices")
carry a typed bag of named slots ("registers"), and whose transitions ("edges") guard on,
read, and write those registers. Aggregate authors describe a transducer with a small
embedded language called the *builder*, defined in `src/Keiki/Builder.hs` and used as
`import qualified Keiki.Builder as B`. Inside an edge body the builder offers an
assignment operator, written `(.=)`, that adds one register write: `B.slot @"itemCount" .=
d.quantity` writes the value of the input field `quantity` into the slot named
`itemCount`.

This plan removes two recurring papercuts that an internal migration (informally
"Rei keiki #4") surfaced when adopting the builder in real aggregates. Both were validated
against the live consumer (the Rei migration); one of them — register reads — turned out to
be essential rather than cosmetic, for the reasons spelled out below.

The first papercut is a name clash, and validation against the consumer confirmed it is real
and recurring. The builder's `(.=)` is the same operator name that the popular `lens` library
exports from `Control.Lens` (its state-setting operator). Any module that wants both
`Keiki.Builder.(.=)` and anything from `Control.Lens` must write
`import Control.Lens hiding ((.=))`, an awkward ceremony — and in the Rei migration this exact
`hiding ((.=))` ceremony appears in nine source files. After this change, authors who hit
that clash can instead use a new, identical operator named `(:=)` — a colon-prefixed
*synonym* — so they never have to hide a lens import. The original `(.=)` stays, unchanged,
for everyone already using it. "Synonym" here means a second name for the exact same thing:
`(:=)` is defined literally as `(:=) = (.=)`, with the same type and the same fixity, so the
two are interchangeable and produce identical results.

The second papercut — and, on validation against the real consumer, the higher-value half of
this plan — is *reading* a register inside a `Term` (the builder's small expression AST — see
the glossary in Context and Orientation). This plan adds a `reg @"slot"` helper that reads a
register as a `Term` with the slot name pinned by a *type application* (the `@"slot"` syntax),
needing no type annotation. It deliberately mirrors the existing write-side helper
`slot @"name"` so the two read like a matched pair: `reg @"x"` reads slot `x`,
`slot @"x" .= t` writes it.

Why this is essential rather than a mere annotation-saver: validating this plan against the
live consumer (the Rei migration, an internal aggregate library that imports keiki's builder)
showed that the obvious "lighter" read path — a bare overloaded label `#slot` resolving
through keiki's `IsLabel s (Term rs ci r)` instance — *is not available to that consumer at
all*. Rei's shared prelude `Rei.Prelude` re-exports `generic-lens` (it has
`import "generic-lens" Data.Generics.Labels ()`), and generic-lens ships its own `IsLabel`
instance that **shadows** keiki's `IsLabel s (Term rs ci r)`. The result: in any module that
uses Rei's prelude, a bare `#slot` no longer resolves to a register-read `Term`, so the
bare-`#slot` read path is unusable. This is not a corner case for Rei — it reads every
register via `proj (indexOf @"slot" @Regs @Ty)`, 10 occurrences across its register-bearing
transducers, with **zero** bare `#slot` and **zero** annotated `#slot` reads. The
`reg @"slot"` helper sidesteps the collision entirely because it is *TypeApplication*-based:
it does not go through an overloaded label at all, so generic-lens's `IsLabel` cannot shadow
it. That is precisely why `reg` is needed and why it is the genuine fix for the consumer,
not just a convenience for in-tree authors. (Inside `keiki`'s own tree there is no
generic-lens, so the bare-`#slot` read path *does* still work in inferable positions; the
annotated `proj (#slot :: Index Regs Ty)` form is needed there only where inference fails,
such as hand-written guard conjunctions and some output fields. The dogfood in M3 exercises
`reg` in exactly those non-inferable in-tree positions.)

You can see the result working two ways. First, a builder edge authored with `:=` compiles
and produces the byte-identical `Update` (the data value describing an edge's register
writes) that the same edge authored with `.=` produces — proven by a new unit test. Second,
the worked-example aggregate in `jitsurei/src/Jitsurei/LoanApplication.hs` is rewritten to
use `reg @"slot"` (and, where natural, `:=`) in its guards and output fields, and its
existing cross-form equivalence test (`Jitsurei.LoanApplicationBuilderSpec`) still passes
unchanged — proving the in-tree rewrite is behavior-preserving (the helpers change spelling,
never semantics). The dogfood proves correctness in `keiki`'s own tree; the evidence that the
helpers will see real use is in the consumer, where `reg @"slot"` is the only ergonomic read
path available at all (see Purpose above) and `(:=)` retires nine `hiding ((.=))` ceremonies.

Alongside those two code helpers, this plan also ships a piece of *guidance*. The reason the
consumer lost the bare-`#slot` read path is structural, not accidental, and it is a trap any
new keiki project can avoid by an import discipline that costs nothing. keiki ships
`instance HasIndex s rs r => IsLabel s (Term rs ci r)` in `src/Keiki/Core.hs` (~lines
223–226) so that a bare overloaded label `#slot` resolves to a register-read `Term`
(`TReg (indexOf @s …)`) — the nice, annotation-free read syntax — together with its sibling
`IsLabel s (Index rs r)` (~lines 207–210). The `generic-lens` library provides a competing,
very general `IsLabel` instance via `Data.Generics.Labels` (its field/labels optics). When a
project brings *that* instance into scope everywhere — typically by re-exporting it from a
shared custom prelude with the orphan-instance import `import Data.Generics.Labels ()`, which
is exactly what `Rei.Prelude` does (`rei-core/src/Rei/Prelude.hs` line 73:
`import "generic-lens" Data.Generics.Labels ()`) — then inside a keiki transducer module
*both* `IsLabel` instances are in scope, `#slot` becomes ambiguous (or resolves to the wrong
instance), and the author is forced into the verbose `proj (indexOf @"slot" @Regs @Ty)` form.
That is precisely the cause Rei hit: it reads registers via `proj (indexOf @…)` in 100% of
cases, with zero bare `#slot`.

So this plan adds a short keiki user guide, a new page at
`docs/guide/generic-lens-and-label-reads.md` (a sibling-consistent kebab-case name matching
the existing `docs/guide/` pages such as `modeling-collections.md` and
`deriving-lifecycle-transitions.md`), that establishes a single guiding principle for *new*
projects that use generic-lens: do not globally re-export `Data.Generics.Labels` /
`import Data.Generics.Labels ()` from a shared prelude. Instead, import generic-lens labels
only in the modules that actually use lens-style field optics (read models, view projections,
application/handler code), and keep keiki transducer modules free of that import. Then bare
`#slot` register reads work naturally via keiki's instances, and the `.=` builder operator is
also less likely to clash with `Control.Lens.(.=)`. The guide gives a concrete before/after:
(a) a global `import Data.Generics.Labels ()` in the prelude makes `#slot` ambiguous in
transducers, so authors must write `proj (indexOf @…)` (or use this plan's `reg @"slot"`
helper); (b) a scoped import lets bare `#slot` reads compile in transducer modules.

This guidance is deliberately framed so it never asks an existing project to refactor. The
`reg @"slot"` and `:=` helpers this plan adds *are* the no-refactor path for projects (like
Rei) already committed to a global generic-lens import: those helpers are TypeApplication- and
colon-spelling-based, so they sidestep the `IsLabel` collision and the `Control.Lens.(.=)`
collision without anyone touching their prelude. The import-scoping discipline is the
recommended *default for new projects only*; the helpers remain the supported escape for
everyone else. The two are complementary, not either/or. The same logic covers the parallel
`.=` versus `Control.Lens.(.=)` collision: scoping lens imports reduces it, and this plan's
`(:=)` synonym (M1) handles it where scoping is not possible. The guide is cross-linked from
the builder/guard-authoring sections of `docs/guide/user-guide.md` so authors discover it at
the moment they reach for a register read.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] M1 (2026-05-21): Added `(=:)` in `src/Keiki/Builder.hs` as a non-breaking synonym for
  `(.=)` — same signature, same `infixr 6` fixity, body `(=:) = (.=)`, exported next to `(.=)`
  with a haddock note explaining it dodges the `Control.Lens.(.=)` clash. **Note:** the
  originally-planned `(:=)` spelling is impossible — GHC reserves colon-prefixed operators for
  data constructors (see Surprises). User chose `=:` as the replacement. `(.=)` kept for
  back-compat. `cabal build keiki` clean.
- [x] M2 (2026-05-21): Added the `reg` register-read helper in `src/Keiki/Builder.hs` mirroring
  `slot`: `reg :: forall (name :: Symbol) rs ci r. (KnownSymbol name, HasIndexN name rs r) =>
  Term rs ci r`, body `reg = TReg (indexNToIndex (indexN @name @rs @r))`. Added `TReg` to the
  `Keiki.Core` import (as `Term (TReg)` — the bundled-constructor form, since Core exports
  `Term (..)`). Exported with haddock. `cabal build keiki` clean.
- [ ] M3: Dogfood and document — adopt `reg @"slot"` (and `:=` where natural) in
  `jitsurei/src/Jitsurei/LoanApplication.hs`; confirm the existing
  `Jitsurei.LoanApplicationBuilderSpec` golden/equivalence test still passes unchanged; add
  a new unit test asserting `(:=)` yields the same `Update` as `(.=)`; add a short note to
  the guard-authoring section of `docs/guide/user-guide.md` documenting both additions and
  correcting the read-ergonomics framing; and author a new guide page
  `docs/guide/generic-lens-and-label-reads.md` stating the import-scoping principle for new
  projects (with a before/after) and the no-refactor helper path for existing ones, then
  cross-link it from the builder/guard-authoring sections of `docs/guide/user-guide.md`.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- **`(:=)` is impossible as a value-level operator — the plan's M1 spelling was infeasible
  (2026-05-21).** GHC reserves every operator beginning with a colon (`:`) for *data
  constructors* (the Haskell lexical rule for constructor operators). Attempting
  `(:=) = (.=)` produces `src/Keiki/Builder.hs:411:1: error: [GHC-94426] Invalid data
  constructor '(:=)' in type signature: You can only define data constructors in data type
  declarations.` So a colon-prefixed synonym for `(.=)` cannot exist. The maintainer chose
  `=:` (a valid `=`-prefixed function operator, no clash with `lens`/`aeson`) as the
  replacement; see the Decision Log. M2's `reg` was unaffected. This invalidates the literal
  M1 text and the Plan-of-Work / Concrete-Steps / Interfaces snippets that wrote `(:=)`,
  `infixr 6 :=`, and `:= = (.=)`; substitute `=:` throughout when reading them.
- **`TReg` import requires the bundled-constructor form (2026-05-21).** `Keiki.Core` exports
  `Term (..)` (`src/Keiki/Core.hs:54`), so importing the constructor as a bare `, TReg` is
  rejected by GHC ("To import it use Term(TReg)"). The import was written as `Term (TReg)`
  (replacing the prior `Term` type-only import), which brings both the `Term` type and the
  `TReg` constructor into scope. No other `Term` constructor is referenced in the builder.


## Decision Log

Record every decision made while working on the plan.

- Decision: Use `(=:)` (not `(:=)`) as the assignment synonym. The colon-prefixed `:=` the
  plan named is a hard language impossibility — GHC reserves colon-prefixed operators for data
  constructors (see Surprises), so `(:=) = (.=)` does not compile. Presented the options to the
  maintainer (`.:=` matching keiki's dot-prefixed family; `=:` mirror spelling; or dropping the
  operator and keeping only `reg` + the guide); the maintainer chose `=:`. It is a valid
  `=`-prefixed function operator with the same `infixr 6` fixity and body `(=:) = (.=)`, and
  does not clash with `Control.Lens.(.=)` or `aeson`'s `.=`. Everywhere the plan body says
  `:=` / `infixr 6 :=` / `:= = (.=)`, read `=:`.
  Rationale: the synonym's whole purpose (a non-`.=` spelling that dodges the `Control.Lens.(.=)`
  clash) is preserved; only the exact glyph changed, forced by the language. The choice between
  valid alternatives is an outward-facing public-API decision, so it was put to the maintainer
  rather than picked unilaterally.
  Date: 2026-05-21

- Decision: Add `(=:)` as a *synonym* for the builder's `(.=)` rather than renaming `(.=)`.
  Rationale: Renaming would break every existing aggregate and test that imports
  `Keiki.Builder ((.=))` (the codebase has many — e.g.
  `jitsurei/src/Jitsurei/OrderCart.hs`, `jitsurei/src/Jitsurei/LoanApplication.hs`,
  `test/Keiki/BuilderSpec.hs`). It would also discard the deliberate precedent recorded in
  `docs/plans/15-edge-builder-monadic-dsl-for-authoring-symtransducer-edges.md`: `(.=)` was
  chosen specifically to match the `.=` spelling used by `aeson`, `lens`, and `mtl`, which is
  familiar to Haskell authors. Keeping `(.=)` preserves that familiarity for the common case
  while `(:=)` gives a clean escape only to the minority of modules that must also import
  `Control.Lens`. Additive synonyms are zero-risk: nothing that compiles today stops
  compiling.
  Date: 2026-05-21
- Decision: Place the new `reg` register-read helper in `Keiki.Builder`, directly mirroring
  the existing write-side `slot` helper (same module, same "Slot writes" neighbourhood, same
  `forall (name :: Symbol) … (KnownSymbol name, HasIndexN name …)` shape and the same
  `indexNToIndex (indexN @name …)` body machinery).
  Rationale: `slot`/`reg` are a matched read/write pair an author reaches for together, so
  co-locating them in the builder module — not in `Keiki.Core` — keeps the authoring surface
  discoverable and consistent. Reusing `slot`'s exact constraints and the existing
  `indexNToIndex` bridge avoids inventing new type-class plumbing.
  Date: 2026-05-21
- Decision: Treat `reg @"slot"` as the *essential* register-read fix for consumers, not a
  mere annotation-saver — superseding this plan's earlier framing that called the migration's
  `proj (indexOf @"slot" @Regs @Ty)` reads "partly inaccurate."
  Rationale: The earlier framing argued that a bare `#slot` already works as a register read
  via keiki's `IsLabel s (Term rs ci r)` instance (`src/Keiki/Core.hs` ~line 223), so the
  migration's verbose `proj (indexOf @…)` reads were avoidable and `reg` only saved an
  annotation. Validation against the live consumer (verified in
  `../rei-project/rei.keiro-migration`) showed that argument is *wrong for any realistic
  consumer*. Rei's shared prelude re-exports generic-lens
  (`rei-core/src/Rei/Prelude.hs`: `import "generic-lens" Data.Generics.Labels ()`), and
  generic-lens's `IsLabel` instance **shadows** keiki's `IsLabel s (Term rs ci r)`, making
  the bare-`#slot` read path unusable in every Rei module. Consequently Rei reads registers
  via `proj (indexOf @"slot" @Regs @Ty)` in 100% of cases — 10 occurrences across its
  register-bearing transducers (the four files containing `proj (indexOf @…)`:
  `rei-core/src/Rei/Modules/Cycle/Domain/Transducer.hs`,
  `.../Focus/Domain/Transducer.hs`,
  `.../CustomProperty/Domain/PropertyAssignmentTransducer.hs`,
  `.../IntentionView/Domain/Transducer.hs`) — with **zero** bare `#slot` and **zero**
  annotated `#slot` reads. The `reg @"slot"` helper is TypeApplication-based: it does *not*
  go through an overloaded label, so generic-lens's `IsLabel` cannot shadow it. That is the
  genuine fix, and it is the higher-value half of this plan. Two scope notes preserved from
  the earlier framing, still true *inside `keiki`'s own tree* (no generic-lens there): a bare
  `#slot` does resolve to a register-read `Term` in inferable positions, and the annotated
  `proj (#slot :: Index Regs Ty)` form is needed only in non-inferable positions
  (hand-written guard conjunctions, some output fields) — which is what the in-tree dogfood
  rewrites to `reg @"slot"`. Also still true: the user-guide glossary at
  `docs/guide/user-guide.md` (the "Terms" table, ~line 315–321) describes `#name` as "`proj`
  of an `IndexN`", which is imprecise — the live in-tree instance produces `TReg (indexOf @s)`
  directly via `Index`, not via `proj`/`IndexN`. M3's doc note will correct this in passing.
  Date: 2026-05-21
- Decision: Record the confirmed adoption surface in the consumer as evidence the helpers
  will see real use, while keeping the dogfood target inside `keiki`'s `jitsurei` unchanged.
  Rationale: Validation in `../rei-project/rei.keiro-migration` counted, across its
  register-bearing transducers, 10 verbose `proj (indexOf @…)` register-read sites that
  `reg @"slot"` would replace and nine source files carrying `import Control.Lens hiding
  ((.=))` that `(:=)` would let drop the `hiding` clause. This is *consumer* evidence — it
  justifies shipping both helpers but does not change this plan's scope. The dogfood that
  proves behavior preservation stays `jitsurei/src/Jitsurei/LoanApplication.hs` and its
  equivalence test, exactly as M3 already specifies; Rei is downstream and adopts the helpers
  on its own once they ship.
  Date: 2026-05-21
- Decision: Ship the import-scoping guidance as a dedicated standalone guide page
  (`docs/guide/generic-lens-and-label-reads.md`) cross-linked from
  `docs/guide/user-guide.md`, rather than only as a paragraph buried in the user guide. Fold
  this deliverable into the existing M3 (documentation) milestone so the milestone count stays
  at three.
  Rationale: A dedicated page is discoverable — an author hitting an ambiguous-`#slot` error or
  the `.=`/`Control.Lens.(.=)` clash can be sent straight to a focused page that names the
  cause and the fix, which a buried paragraph cannot do as well; it also matches the existing
  `docs/guide/` convention of one focused page per topic (e.g. `modeling-collections.md`,
  `deriving-lifecycle-transitions.md`). The principle — scope generic-lens label imports to the
  modules that use field optics and keep keiki transducer modules free of
  `import Data.Generics.Labels ()` — applies to *new* projects: it is the cheap default that
  preserves bare `#slot` register reads (via keiki's `IsLabel s (Term rs ci r)` instance in
  `src/Keiki/Core.hs` ~lines 223–226) and reduces the `.=` clash. Critically, the guide must
  *not* tell existing projects to refactor: this plan's `reg @"slot"` and `:=` helpers are the
  no-refactor path for projects (like Rei) already committed to a global generic-lens
  re-export, because they sidestep the `IsLabel` and `Control.Lens.(.=)` collisions without
  touching the prelude. The discipline and the helpers are complementary, not either/or. This
  decision adds documentation only; it leaves the technical design of `reg`/`:=` (signatures,
  milestones, milestone count, and the three-item Progress checklist) entirely unchanged.
  Date: 2026-05-21


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

This is a small, additive change to one Haskell module's authoring surface. To work on it
you need a mental model of a handful of types and where they live. Everything below is in
this repository; no external knowledge is required.

The repository root is `/Users/shinzui/Keikaku/bokuno/keiki`. It is a Cabal project with
two packages: the library `keiki` (described by `keiki.cabal` at the root, source under
`src/`), and a worked-examples package `jitsurei` (described by `jitsurei/jitsurei.cabal`,
source under `jitsurei/src/`, tests under `jitsurei/test/`). All paths below are
repository-relative.

Glossary of terms of art, each defined in plain language and tied to a file:

- *Transducer* (here, "symbolic-register finite-state transducer"): a state machine.
  Defined as `SymTransducer` in `src/Keiki/Core.hs`. Its states are called *vertices*; its
  transitions are called *edges*. Each vertex carries a typed bag of named values called the
  *register file*.
- *Register file* `RegFile rs`: the bag of named typed slots a vertex carries. The phantom
  `rs` is a type-level list of `'(name, type)` pairs — e.g. `'[ '("itemCount", Word32), … ]`.
  A single named value in it is a *slot* (a *register*).
- *Index* `Index rs r` (in `src/Keiki/Core.hs`): a pointer to one slot of type `r` inside a
  register file `rs`. It existentially hides which slot name it points at.
- *IndexN* `IndexN s rs r` (in `src/Keiki/Internal/Slots.hs`, around line 94): the same
  pointer but with the slot's *name* `s` kept visible in the type (a `Symbol`). The builder's
  write side uses `IndexN` so it can statically detect two writes to the same slot.
  `HasIndexN s rs r` (around line 102) is the class that resolves a name `s` against a slot
  list `rs` to an `IndexN`, via its method `indexN`.
- *Term* `Term rs ci r` (in `src/Keiki/Core.hs`): a tiny expression AST that, when evaluated
  against a register file and an input command, yields a value of type `r`. Its constructors
  include `TLit` (a literal, smart constructor `lit`), `TReg` (read a register, smart
  constructor `proj :: Index rs r -> Term rs ci r` at ~line 627), `TInpCtorField` (read a
  field of the input command), and `TApp1`/`TApp2` (apply an opaque Haskell function — an
  escape hatch).
- *Update* `Update rs w ci` (in `src/Keiki/Core.hs`): the data value describing an edge's
  register writes. `UKeep` writes nothing; `USet ix t` writes term `t` to slot `ix`;
  `combine` conjoins two updates. The phantom `w :: [Symbol]` lists the slot names written so
  far, which is how duplicate-write detection works.
- *Overloaded label* `#name`: GHC syntax (from the `OverloadedLabels` extension, enabled
  project-wide in `keiki.cabal`'s `shared-extensions`) that resolves through an `IsLabel`
  instance. `src/Keiki/Core.hs` provides two relevant instances: `IsLabel s (Index rs r)`
  (~line 207) makes `#name` an `Index`, and `IsLabel s (Term rs ci r)` (~line 223) makes
  `#name` a register-read `Term` (specifically `TReg (indexOf @s @rs @r)`). GHC picks between
  them by the expected result type. This second instance is what makes a bare `#slot`
  usable as a register read without `proj` *inside `keiki`'s own tree*. Crucially, this is an
  orphan-prone overlap: a consumer whose prelude re-exports `generic-lens` brings in
  generic-lens's own `IsLabel` instance, which **shadows** keiki's `IsLabel s (Term rs ci r)`
  and makes a bare `#slot` no longer resolve to a register-read `Term`. The Rei migration is
  exactly such a consumer (`rei-core/src/Rei/Prelude.hs` has
  `import "generic-lens" Data.Generics.Labels ()`), which is why the bare-`#slot` read path is
  unavailable there and `reg @"slot"` — which avoids overloaded labels entirely — is the fix.
- *Type application* `@"name"` / `@Type`: GHC syntax for supplying a type argument
  explicitly. `slot @"itemCount"` pins the slot name `"itemCount"` as a type-level `Symbol`.

The module this plan edits is `src/Keiki/Builder.hs`. It is the embedded language for
*authoring* a transducer. Its key pieces, with current line numbers (the file is ~743 lines):

- The module haddock (lines ~1–137) documents the builder, including, at lines ~71–80, the
  instruction that authors must `import Keiki.Builder ((.=))` unqualified and the note that
  `B.(.=)` is "unreadable". The lens clash is implied here; M1 will add an explicit note that
  `(:=)` is the escape from that clash.
- The export list (lines ~138–181). The slot-write helpers are exported under an
  `-- ** Slot writes` haddock subsection (lines ~150–152): `slot` then `(.=)`. M1 adds
  `(:=)` here; M2 adds `reg` here.
- `slot` (lines ~341–345): `slot :: forall (name :: Symbol) rs r. (KnownSymbol name,
  HasIndexN name rs r) => IndexN name rs r`, body `slot = indexN @name @rs @r`. Its haddock
  (lines ~325–340) explains *why* `slot @"name"` is preferred over `#name` on the write side
  (GHC will not commit `s ~ "name"` when `name` is a quantified variable, so the type
  application disambiguates). M2's `reg` mirrors this shape on the read side.
- `(.=)` (lines ~359–367): the slot-assignment operator. Its full signature is

      (.=)
        :: forall name r rs ci co v w.
           ( KnownSymbol name, Disjoint '[name] w )
        => IndexN name rs r
        -> Term rs ci r
        -> EdgeBuilder rs ci co v w (Concat '[name] w) ()
      ix .= t = EdgeBuilder $ \pe ->
        ((), pe { peUpdate = USet ix t `combine` peUpdate pe })
      infixr 6 .=

  Here `EdgeBuilder rs ci co v w w' a` is the indexed-state monad for one edge body; the
  phantoms `w` (before) and `w'` (after) track the set of slot names written, and the
  `Disjoint '[name] w` constraint (from `src/Keiki/Internal/Slots.hs`) makes a second write
  to the same slot fail to type-check. `Concat` and `Disjoint` are imported from
  `Keiki.Internal.Slots`. M1's `(:=)` reuses this signature verbatim.
- `indexNToIndex` (lines ~551–553): `indexNToIndex :: forall name rs r. IndexN name rs r ->
  Index rs r`, a structural recursion translating the name-tagged `IndexN` into the
  name-erased `Index` that `TReg`/`inpCtor` consume. M2's `reg` uses it to turn
  `indexN @name @rs @r` into the `Index` that `TReg` wants.
- The import block (lines ~189–215). From `Keiki.Core` the module already imports `Term`,
  `Index`, `Update (..)` (so `USet`/`UKeep` are in scope), `combine`, etc. — but note `TReg`
  is *not* currently imported (the module uses `USet` for writes; reads have not been needed
  in the builder before now). `proj` is not imported either. M2 therefore must add either
  `TReg` to the `Keiki.Core` import list (and build `reg = TReg (indexNToIndex …)`) or import
  `proj` and build `reg = proj (indexNToIndex …)`; the two are equal because `proj = TReg`.
  This plan uses `TReg` directly to match `slot`'s low-level style, so add `TReg` to the
  import list at lines ~189–208. From `Keiki.Internal.Slots` the module already imports
  `HasIndexN (..)` (so `indexN` is in scope) and `IndexN (..)`. `KnownSymbol`/`Symbol` are
  already imported from `GHC.TypeLits` (line ~185). So M2 needs no new dependency beyond the
  one `TReg` import.

Recent context — EP-45. Two commits already on `master` added an operator/synonym surface
that this plan should match in *style* (naming, export grouping, haddock tone):

- Commit `73c1974` ("feat(core): EP-45 M1 — dot-prefixed predicate & term operators") added,
  in `src/Keiki/Core.hs`, definitional aliases such as `(.<)`, `(.>=)`, `(.&&)`, `pnot`,
  `(.+)`, `(.*)` for the `HsPred`/`Term` constructors, each as a one-liner with a haddock
  note naming what it aliases and its fixity, all proven by `test/Keiki/OperatorsSpec.hs`.
- Commit `01492f9` ("feat(core,symbolic): EP-45 M2 — Pred/Guarded/SymGuarded type synonyms")
  added the type synonyms `Pred rs ci` (for `HsPred rs ci`) and `Guarded rs s ci co` (for
  `SymTransducer (HsPred rs ci) rs s ci co`), with exports and a smoke check appended to the
  same `OperatorsSpec`.

The lesson for this plan: add the new names as small definitional aliases with one-line
haddock that states exactly what they are aliases for, export them grouped with their kin,
and prove them with a tiny test. The two EP-45 commits are the template for `(:=)`.

The dogfood target — `jitsurei/src/Jitsurei/LoanApplication.hs` — is the worked example with
the richest register *reads*. It already adopted the EP-45 operators (see its module haddock
~lines 417–422). Its two guard helpers, `readyForReviewGuard` (lines ~423–428) and
`approvalGuard` (lines ~431–436), are exactly the non-inferable positions where bare `#slot`
does *not* suffice and the verbose `proj (#appCreditScore :: Index LoanAppRegs Int)` form is
used today. For example `approvalGuard` currently reads:

      approvalGuard :: Pred LoanAppRegs LoanCmd
      approvalGuard =
             proj (#appCreditScore :: Index LoanAppRegs Int) .>= lit approvalThresholdScore
        .&&  proj (#appEmploymentVerified :: Index LoanAppRegs Bool) .== lit True
        .&&  proj (#appRequestedAmount :: Index LoanAppRegs Money)
               .<= proj (#appCreditScore :: Index LoanAppRegs Int) .* lit 1000

With `reg`, each `proj (#slot :: Index Regs Ty)` collapses to `reg @"slot"`. The aggregate
also uses `.=` throughout its edge bodies (e.g. lines ~447–453) and bare `#appApplicantId`
register reads as output fields (e.g. lines ~467, 538–541) that already work and should be
left as-is (the bare label suffices there). The aggregate's behavior is pinned by
`jitsurei/test/Jitsurei/LoanApplicationBuilderSpec.hs`, which asserts that the builder-form
`loanApplication` and the hand-written AST-form `loanApplicationAST` agree on `reconstitute`,
`isFinal`, and `edgesOut` over a canonical event log. Because the AST form is *not* being
edited and `reg @"slot"` is by construction equal to `proj (#slot :: Index …)`, that test is
the proof that M3 changed nothing observable.

The unit-test home for the builder is `test/Keiki/BuilderSpec.hs` (registered in
`test/Spec.hs` and in `keiki.cabal`'s `keiki-test` `other-modules`). M3's new
`(:=)`-equals-`(.=)` assertion goes here; no new test module or cabal stanza is needed.

The parent MasterPlan for this work is
`docs/masterplans/13-keiki-api-improvements-surfaced-by-the-rei-migration.md`. This plan is
self-contained and does not depend on its sibling plans.


## Plan of Work

The work is three milestones. M1 and M2 each add one small thing to
`src/Keiki/Builder.hs`; M3 proves both on real code, adds a behavioral test, and updates the
guide. Each milestone leaves the tree compiling and the full suite green, so each is
independently verifiable.


### Milestone 1 — add the `(:=)` assignment synonym

Scope: introduce a colon-prefixed operator `(:=)` that is a non-breaking synonym for the
existing `(.=)`. At the end of this milestone, an aggregate author can write
`B.slot @"x" := t` exactly where they would have written `B.slot @"x" .= t`, and the two
produce the identical `Update`. `(.=)` remains exported and unchanged.

Edit one: the export list in `src/Keiki/Builder.hs` (the `-- ** Slot writes` subsection,
currently lines ~150–152, which reads `slot` then `, (.=)`). Add `, (:=)` immediately after
`, (.=)` so the pair sits together:

      -- ** Slot writes
    , slot
    , (.=)
    , (:=)

Edit two: the definition. Immediately *after* the `(.=)` definition and its `infixr 6 .=`
line (currently ending at line ~367), add the synonym. It reuses `(.=)`'s exact type
signature (so a reader sees they are interchangeable) and the same fixity, and its body is
literally `(:=) = (.=)`:

    -- | Slot assignment, spelled with a colon. An exact synonym for
    -- '(.=)': @slot \@\"x\" := t@ is @slot \@\"x\" .= t@ and produces the
    -- identical 'Keiki.Core.Update'. It exists for one reason — to dodge
    -- the name clash with @Control.Lens.(.=)@. A module that authors edges
    -- /and/ imports "Control.Lens" would otherwise need
    -- @import Control.Lens hiding ((.=))@; with '(:=)' it can keep both
    -- imports unqualified and use '(:=)' for slot writes. Modules that do
    -- not import "Control.Lens" should keep using '(.=)', which matches the
    -- @.=@ spelling of @aeson@ \/ @lens@ \/ @mtl@.
    (:=)
      :: forall name r rs ci co v w.
         ( KnownSymbol name, Disjoint '[name] w )
      => IndexN name rs r
      -> Term rs ci r
      -> EdgeBuilder rs ci co v w (Concat '[name] w) ()
    (:=) = (.=)
    infixr 6 :=

No new imports are required: `KnownSymbol`, `Disjoint`, `IndexN`, `Term`, `EdgeBuilder`,
`Concat` are all already in scope (they are used by `(.=)` itself). The
`{-# OPTIONS_GHC -Wno-redundant-constraints #-}` pragma already present at the top of the
file (line ~2) suppresses the redundant-constraint warning that `Disjoint '[name] w`
otherwise triggers, just as it does for `(.=)`.

Commands to run from the repository root `/Users/shinzui/Keikaku/bokuno/keiki`:

    cabal build keiki

Acceptance: the library compiles. The behavioral proof is folded into M3's new test (a
self-contained check that authoring with `:=` yields the same `Update` as `.=`), because the
builder test module is the natural home for it; M1 alone is verified by a clean
`cabal build keiki`.


### Milestone 2 — add the `reg @"slot"` register-read helper

Scope: introduce `reg`, a read-side mirror of `slot`. At the end of this milestone,
`reg @"appCreditScore"` is a `Term` that reads the named register, with the slot name pinned
by type application so no `:: Index Regs Ty` annotation is needed — usable in positions where
a bare `#slot` would require that annotation (hand-written guards, some output fields).

Edit one: the import of `Keiki.Core` in `src/Keiki/Builder.hs` (lines ~189–208). Add `TReg`
to the import list. It currently imports (among others) `Term`, `Index`, `Update (..)`,
`combine`; insert `TReg` (the `Term` constructor that reads a register) alongside `Term`. The
`Keiki.Internal.Slots` import (lines ~210–215) already brings in `HasIndexN (..)` and
`IndexN (..)`, so `indexN` is in scope; `KnownSymbol`/`Symbol` are already imported from
`GHC.TypeLits`.

Edit two: the export list `-- ** Slot writes` subsection. Add `, reg` after the `(:=)` line
from M1 (it is acceptable to keep `reg` in the "Slot writes" group since `slot`/`reg` are a
matched pair, or to relabel the subsection to `-- ** Slot writes and reads`; this plan keeps
the existing subsection and simply adds `reg`):

    , slot
    , (.=)
    , (:=)
    , reg

Edit three: the definition. Place it immediately after `slot` (currently ending at line
~345), so the write helper and read helper are adjacent. It mirrors `slot`'s constraints
exactly but its result is a `Term` (a register read) instead of an `IndexN`, built by
translating the name-tagged `IndexN` to an `Index` with the existing `indexNToIndex` bridge
and wrapping it in `TReg`:

    -- | Read a register slot into a 'Keiki.Core.Term', the read-side
    -- mirror of 'slot'. The slot name is supplied via @TypeApplication@,
    -- so @reg \@\"appCreditScore\"@ needs no @:: 'Keiki.Core.Index' Regs
    -- Ty@ annotation:
    --
    -- > approvalGuard = reg \@\"appCreditScore\" .>= lit 650
    --
    -- == When to use @reg \@\"name\"@ versus @\#name@
    --
    -- A bare overloaded label @\#name@ already resolves to a register-read
    -- 'Keiki.Core.Term' through the @'GHC.OverloadedLabels.IsLabel' s
    -- ('Keiki.Core.Term' rs ci r)@ instance, and is the lighter form
    -- wherever GHC can infer the slot list @rs@ and value type @r@ — for
    -- example the right-hand side of '(.=)', or an argument of
    -- 'Keiki.Core.TApp1'. In positions where inference fails — notably a
    -- hand-written guard conjunction, or an 'OutFields' element — @\#name@
    -- needs the verbose @'Keiki.Core.proj' (\#name :: 'Keiki.Core.Index'
    -- Regs Ty)@ annotation. 'reg' removes exactly that annotation by
    -- pinning the name with a type application, the same way 'slot' does on
    -- the write side. (Note: register reads do /not/ require
    -- @'Keiki.Core.proj' ('Keiki.Core.indexOf' \@\"name\")@; the bare
    -- @\#name@ idiom already works in inferable positions.)
    reg
      :: forall (name :: Symbol) rs ci r.
         ( KnownSymbol name, HasIndexN name rs r )
      => Term rs ci r
    reg = TReg (indexNToIndex (indexN @name @rs @r))

Commands to run from the repository root:

    cabal build keiki

Acceptance: the library compiles. The behavioral proof is in M3, where `reg @"slot"`
replaces `proj (#slot :: Index …)` in a real aggregate and the unchanged equivalence test
confirms the read resolves to the same `Index`/`TReg`.


### Milestone 3 — dogfood, prove behavior preservation, and document

Scope: prove both additions on real code, add a focused unit test for `(:=)`, and update the
documentation — both the in-place notes in the existing user guide and a new standalone guide
page that establishes the import-scoping principle. At the end of this milestone,
`jitsurei/src/Jitsurei/LoanApplication.hs` uses `reg @"slot"` in its two guard helpers (and
`:=` in at least one edge body to exercise the synonym on real code), its existing equivalence
test passes unchanged, a new builder test asserts `(:=)` and `(.=)` produce identical
`Update`s, `docs/guide/user-guide.md` documents `(:=)` and `reg` and corrects the
read-ergonomics framing, and a new page `docs/guide/generic-lens-and-label-reads.md` states
the guiding principle (scope generic-lens label imports; keep transducer modules free of them)
with a worked before/after, names the helpers as the no-refactor path for existing projects,
and is cross-linked from the builder/guard-authoring sections of the user guide.

Edit one — adopt `reg` in the guards of `jitsurei/src/Jitsurei/LoanApplication.hs`. Rewrite
`readyForReviewGuard` (lines ~423–428) and `approvalGuard` (lines ~431–436) so each
`proj (#slot :: Index LoanAppRegs Ty)` becomes `reg @"slot"`. After the rewrite they read:

    readyForReviewGuard :: Pred LoanAppRegs LoanCmd
    readyForReviewGuard =
           reg @"appIncomeDocCount"     .>= lit minimumIncomeDocs
      .&&  reg @"appIdDocCount"         .>= lit minimumIdDocs
      .&&  reg @"appCreditScore"        .>= lit 1
      .&&  reg @"appEmploymentVerified" .== lit True

    approvalGuard :: Pred LoanAppRegs LoanCmd
    approvalGuard =
           reg @"appCreditScore"     .>= lit approvalThresholdScore
      .&&  reg @"appEmploymentVerified" .== lit True
      .&&  reg @"appRequestedAmount"  .<= reg @"appCreditScore" .* lit 1000

This requires bringing `reg` into scope in that module. It currently does
`import Keiki.Builder ((.=))` (line ~108); change that to
`import Keiki.Builder ((.=), reg)` (and, for edit two, also `(:=)`), keeping the
`import qualified Keiki.Builder as B` line above it. The bodies of these two guards are pure
`Term`/`HsPred` expressions, so `reg` (which is `Term`-typed) drops in directly. Leave the
existing bare `#appApplicantId` reads in the output-field positions (e.g. lines ~467,
538–541) unchanged — those are inferable and already idiomatic; replacing them would not
demonstrate anything new and would be churn.

Edit two — exercise `:=` on one edge body in the same file, to prove the synonym on real
code. Pick the `inCtorStart` body in the `from Intake` block (lines ~446–460): change its
seven `B.slot @"…" .= …` lines to `B.slot @"…" := …`. Add `(:=)` to the
`import Keiki.Builder (…)` list. (Any single edge body works; `inCtorStart` is chosen because
it has the most writes, so the synonym is exercised on several lines.) All other edge bodies
keep `.=`, demonstrating that the two coexist freely in one module.

Edit three — the `(:=)`-equals-`(.=)` unit test in `test/Keiki/BuilderSpec.hs`. The module
already defines a one-slot toy register file `type Regs = '[ '("counter", Int) ]` and imports
`Keiki.Builder ((.=))` (line ~17) plus `Keiki.Builder as B`. Add `(:=)` to that import. Then
add a test that builds the same single-slot edge two ways — once with `.=`, once with `:=` —
and asserts the resulting edges' `update` fields are equal. The most direct route reuses the
spec's existing toy machinery (it already has a `Tick`/`counter` slot and a one-edge builder
elsewhere in the file); the new test runs each authoring through the same `from`/`onCmd`
shape and compares the finalized `Edge`'s `update`. Concretely, add to the `spec` do-block:

    describe "(:=) is a synonym for (.=)" $
      it "produces the identical Update as (.=) for the same slot+term" $ do
        let withDot   = B.buildTransducer A emptyR (const False) $ Prelude.do
              B.from A $ B.onCmd inCtorTick $ \d -> B.do
                B.slot @"counter" .= d.count
                B.goto B
            withColon = B.buildTransducer A emptyR (const False) $ Prelude.do
              B.from A $ B.onCmd inCtorTick $ \d -> B.do
                B.slot @"counter" := d.count
                B.goto B
        map update (edgesOut withDot A)
          `shouldBe` map update (edgesOut withColon A)

Two practical notes for whoever implements this. First, `Update rs w ci` must have an `Eq`
instance for `shouldBe` to work; if it does not, compare a downstream observable instead —
run both transducers' `reconstitute` over a one-event log and assert equal resulting register
files, or assert `delta`/`omega` agree on a sample input. Check `src/Keiki/Core.hs` for
`deriving … Eq` on `Update` (and on `Edge`) before choosing; the equivalence test in
`Jitsurei.LoanApplicationBuilderSpec` already compares via `reconstitute`, which is the safe
fallback pattern to copy. Second, the exact toy names (`A`, `B`, `emptyR`, `inCtorTick`,
`Tick`/`count`) must match what `test/Keiki/BuilderSpec.hs` already defines — read the file
first and reuse its existing fixtures rather than introducing new ones.

Edit four — document both additions in `docs/guide/user-guide.md`. In the "Slot writes"
subsection (around line 298–305) add a sentence introducing `(:=)` as a synonym for `(.=)`
that avoids the `Control.Lens.(.=)` clash. In the "Terms" subsection (around line 307–321),
which currently says register reads use `#name` or `proj`, add a row/sentence for
`reg @"name"` and correct the imprecise claim at lines ~320–321 that `#name` is "`proj` of an
`IndexN`": state precisely that `#name` resolves through the `IsLabel s (Term rs ci r)`
instance to a `TReg` (an `Index`-based read) in inferable positions, and that `reg @"name"`
is the annotation-free form for non-inferable positions (guards, output fields), mirroring
`slot @"name"` on the write side. Also extend the builder-terms glossary (the `(.=)` entry
around line 784 and the `slot @"name"` entry around line 783) with one-line entries for
`(:=)` and `reg @"name"`. If the `Keiki.Builder` module haddock's import instruction (lines
~71–80) is the more natural place for the lens-clash note, add it there too; the haddock note
on `(:=)` from M1 already covers the rationale, so the guide note can be brief.

Edit five — author the new standalone guide page and cross-link it. Create
`docs/guide/generic-lens-and-label-reads.md`. The filename is kebab-case to match the existing
`docs/guide/` siblings (`modeling-collections.md`, `multi-event-commands.md`,
`deriving-lifecycle-transitions.md`); these guide pages are ordinary reader-facing Markdown
(unlike this plan, they may use fenced code blocks and tables, in the house style of the other
guides — read one such as `docs/guide/modeling-collections.md` first and match its tone). The
page must contain, in plain prose: (1) the mechanism — keiki ships
`IsLabel s (Term rs ci r)` and `IsLabel s (Index rs r)` in `src/Keiki/Core.hs` (~lines 207–210
and 223–226) so a bare `#slot` resolves to a register-read `Term` (`TReg (indexOf @s …)`),
and `generic-lens` ships a competing, very general `IsLabel` instance from
`Data.Generics.Labels` that, once globally in scope, makes `#slot` ambiguous inside a
transducer module; (2) the guiding principle, stated for *new* projects — do not globally
re-export `Data.Generics.Labels` / `import Data.Generics.Labels ()` from a shared prelude;
import generic-lens labels only in the modules that use lens-style field optics (read models,
view projections, application/handler code), and keep keiki transducer modules free of that
import, so bare `#slot` reads work and `.=` is less likely to clash; (3) a concrete
before/after — (a) global `import Data.Generics.Labels ()` in the prelude makes `#slot`
ambiguous in transducers, forcing `proj (indexOf @…)` (or this plan's `reg @"slot"` helper),
versus (b) a scoped import where bare `#slot` reads compile in transducer modules; (4) the
no-refactor framing, stated plainly — this guide does *not* tell existing projects to refactor;
the `reg @"slot"` and `:=` helpers are the supported no-refactor path for projects (like Rei)
already committed to a global generic-lens import, the import-scoping discipline is the
recommended default for *new* projects only, and the two are complementary, not either/or; and
(5) the parallel `.=` versus `Control.Lens.(.=)` collision — scoping lens imports reduces it,
and the `(:=)` synonym (M1) handles it where scoping is not possible. Use `Rei.Prelude` as the
real-world example of the global re-export (`rei-core/src/Rei/Prelude.hs` line 73:
`import "generic-lens" Data.Generics.Labels ()`), but do not prescribe that Rei change it.

Then cross-link the new page from the existing user guide. In
`docs/guide/user-guide.md`, add a one-line pointer to
`docs/guide/generic-lens-and-label-reads.md` in the "Terms" subsection (around lines 307–321,
where register reads via `#name` are introduced) and in the "Slot writes" / guard-authoring
neighbourhood (around lines 248–305, where `(.=)` and the operators are introduced), so an
author who reaches for a register read or hits the `.=`/`Control.Lens.(.=)` clash is sent to
the principle. The link text should be brief, e.g. "If you use generic-lens, see
[Generic-lens and label reads](generic-lens-and-label-reads.md) for the import discipline that
keeps bare `#slot` reads working."

Commands to run from the repository root (see Validation for full detail):

    cabal build all
    cabal test keiki:keiki-test
    cabal test jitsurei:jitsurei-test

Acceptance: everything compiles; `Jitsurei.LoanApplicationBuilderSpec` passes unchanged
(proving the `reg`/`:=` rewrite is behavior-preserving); the new
`(:=) is a synonym for (.=)` example in `Keiki.BuilderSpec` passes (proving `:=` and `.=`
produce the same `Update`); the user guide describes both additions and no longer claims
reads require `proj (indexOf @…)`; and the new page
`docs/guide/generic-lens-and-label-reads.md` exists, states the import-scoping principle for
new projects, states plainly that the `reg`/`:=` helpers are the no-refactor path for existing
projects (so the two are complementary, not either/or), includes a worked before/after, and is
cross-linked from the builder/guard-authoring sections of `docs/guide/user-guide.md`.


## Concrete Steps

All commands run from the repository root `/Users/shinzui/Keikaku/bokuno/keiki`. The
toolchain is Cabal with GHC 9.12 (the cabal files declare `tested-with: GHC == 9.12.*` and
`default-language: GHC2024`).

Step 0 — establish a clean baseline before any edit, so you can prove the dogfood is
behavior-preserving by comparing before/after:

    cabal build all
    cabal test jitsurei:jitsurei-test

Expect the build to succeed and the jitsurei suite to report all examples passing, e.g. a
final line resembling:

    Finished in 0.42 seconds
    NN examples, 0 failures

Step 1 — implement M1 (the `(:=)` synonym in `src/Keiki/Builder.hs`), then:

    cabal build keiki

Expect a clean compile. If GHC complains about a redundant `Disjoint '[name] w` constraint on
`(:=)`, confirm the `{-# OPTIONS_GHC -Wno-redundant-constraints #-}` pragma is still at the
top of `src/Keiki/Builder.hs` (it is there for `(.=)` already and covers `(:=)` too).

Step 2 — implement M2 (add `TReg` to the `Keiki.Core` import, add `reg`), then:

    cabal build keiki

Expect a clean compile. If GHC reports `Variable not in scope: TReg`, the import edit in
`src/Keiki/Builder.hs` (lines ~189–208) was missed.

Step 3 — implement M3's source edits (rewrite the two guards in
`jitsurei/src/Jitsurei/LoanApplication.hs` to use `reg @"slot"`, switch the `inCtorStart`
edge body to `:=`, widen its `import Keiki.Builder (…)` to include `reg` and `(:=)`), then:

    cabal build jitsurei

Expect a clean compile. A type error in a guard usually means a `reg @"slot"` name does not
match a slot in `LoanAppRegs` (lines ~277–288 of that file) — check the spelling against that
list.

Step 4 — implement M3's test edit in `test/Keiki/BuilderSpec.hs` and run the keiki suite:

    cabal test keiki:keiki-test

Expect all examples passing, including a new line under the builder describe block:

    Keiki.Builder (EP-15 M6)
      ...
      (:=) is a synonym for (.=)
        produces the identical Update as (.=) for the same slot+term

Step 5 — re-run the jitsurei suite to confirm the dogfood changed nothing observable:

    cabal test jitsurei:jitsurei-test

Expect the same example/failure counts as the Step 0 baseline (the
`LoanApplicationBuilderSpec` examples in particular must still pass), e.g.:

    NN examples, 0 failures

Step 6 — implement M3's doc edits. First, edit `docs/guide/user-guide.md`: re-read the edited
"Slot writes" and "Terms" subsections (around lines 298–321) and the builder-terms glossary
(around lines 783–784) to confirm `(:=)` and `reg @"name"` are described and the `#name` claim
is corrected. Second, create the new page `docs/guide/generic-lens-and-label-reads.md` per
M3 edit five (read a sibling such as `docs/guide/modeling-collections.md` first to match the
house Markdown style), covering the five required points: the `IsLabel` mechanism and the
generic-lens shadowing, the import-scoping principle for new projects, the before/after, the
no-refactor helper framing for existing projects, and the parallel `.=`/`Control.Lens.(.=)`
note. Third, add the cross-links from `docs/guide/user-guide.md` to that page in the "Terms"
and "Slot writes"/guard-authoring neighbourhoods. No command verifies prose; re-read the new
page and the two cross-links to confirm the principle, the helpers-are-not-forced framing, and
the worked before/after are all present.

Step 7 — full sweep to confirm nothing else regressed:

    cabal build all
    cabal test all

Expect every suite green. As work proceeds, tick the matching boxes in Progress and record
anything unexpected under Surprises & Discoveries.


## Validation and Acceptance

Validation has three layers: it compiles, the synonym is behaviorally identical, and the
dogfood changed nothing observable.

Compilation. From the repository root:

    cabal build all

This must succeed for both packages (`keiki` and `jitsurei`). Compilation alone proves the
new `(:=)` and `reg` are well-typed and that the rewritten `jitsurei` guards using
`reg @"slot"` type-check against `LoanAppRegs`.

Synonym is behavior-preserving. The new example in `test/Keiki/BuilderSpec.hs` authors the
same single-slot edge twice — once with `B.slot @"counter" .= d.count`, once with
`B.slot @"counter" := d.count` — and asserts the two resulting edges' `update` fields are
equal (or, if `Update` lacks `Eq`, that `reconstitute` over a one-event log yields equal
register files; choose per the note in M3 edit three). Run:

    cabal test keiki:keiki-test

Expected: all examples pass, including

    (:=) is a synonym for (.=)
      produces the identical Update as (.=) for the same slot+term

This is the concrete proof beyond compilation that `:=` is interchangeable with `.=`: same
slot, same term, same resulting `Update`.

Dogfood preserved behavior. The aggregate
`jitsurei/src/Jitsurei/LoanApplication.hs` now uses `reg @"slot"` in `readyForReviewGuard`
and `approvalGuard` and `:=` in the `inCtorStart` edge body, but its hand-written AST form
`loanApplicationAST` is untouched. The pre-existing test
`jitsurei/test/Jitsurei/LoanApplicationBuilderSpec.hs` asserts the builder form and the AST
form agree on `reconstitute` (final vertex and registers) over the canonical evidence log
`[ApplicationStarted "alice" 250_000 "home", IncomeDocumentReceived ×2, IdDocumentReceived,
CreditScoreRecorded 720, EmploymentChecked True]`, on `isFinal` across all six vertices, and
on `edgesOut` counts per vertex. Because `reg @"slot"` resolves to the same `Index`/`TReg`
that `proj (#slot :: Index …)` did, and `:=` is `.=`, this test must still pass with no
edits to the test file. Run:

    cabal test jitsurei:jitsurei-test

Expected: the same example/failure counts as the Step 0 baseline (all passing), with the
`EP-34 M2: builder vs AST agreement` examples green. A regression here would mean the rewrite
was *not* behavior-preserving — investigate before proceeding.

Full sweep. Finally:

    cabal test all

Expected: every suite in both packages green. Overall acceptance: a builder edge authored
with `:=` produces the identical `Update` as one authored with `.=`; `reg @"slot"` reads a
register as a `Term` in guard/output positions where bare `#slot` would have needed a type
annotation; the dogfooded aggregate's behavior is unchanged; the user guide documents both
additions and no longer claims reads require `proj (indexOf @…)`; and the new guide page
`docs/guide/generic-lens-and-label-reads.md` exists and is cross-linked from the user guide.

Documentation deliverable. Because the guide is prose, its acceptance is read, not run. Open
`docs/guide/generic-lens-and-label-reads.md` and confirm it (1) states the guiding principle
for new projects — scope generic-lens label imports, keep keiki transducer modules free of
`import Data.Generics.Labels ()`; (2) states the helpers-are-not-forced framing plainly — the
`reg @"slot"` and `:=` helpers are the supported no-refactor path for existing projects, and
the import-scoping discipline is the default for new projects only, the two being
complementary; and (3) shows a worked before/after — a global `import Data.Generics.Labels ()`
making `#slot` ambiguous in transducers (forcing `proj (indexOf @…)` or `reg @"slot"`) versus a
scoped import where bare `#slot` reads compile. Then open `docs/guide/user-guide.md` and
confirm the cross-links to the new page are present in the "Terms" and "Slot
writes"/guard-authoring neighbourhoods.


## Idempotence and Recovery

Every edit in this plan is additive or a like-for-like substitution, and all steps are safe
to repeat. Re-running `cabal build` and `cabal test` is always safe and has no side effects
beyond the build cache.

M1 and M2 only *add* declarations and exports to `src/Keiki/Builder.hs`; they remove nothing.
If you add `(:=)` or `reg` twice by accident, GHC reports a duplicate definition or duplicate
export and the fix is to delete the extra copy — no state to unwind. If a build fails partway
through M3, the source edits are localized to four files
(`jitsurei/src/Jitsurei/LoanApplication.hs`, `test/Keiki/BuilderSpec.hs`,
`docs/guide/user-guide.md`, and the new `docs/guide/generic-lens-and-label-reads.md`) and can
be reverted individually with `git checkout -- <path>` (the new guide page, being untracked
until committed, is removed with `rm docs/guide/generic-lens-and-label-reads.md`). The guide
page and its cross-links are pure documentation and never affect the build or tests.

The dogfood substitutions in M3 are reversible by construction: `reg @"slot"` and
`proj (#slot :: Index Regs Ty)` are equal terms, and `:=` and `.=` are the same operator, so
reverting any one site to its prior spelling restores byte-identical behavior. The safety net
is the pre-existing `Jitsurei.LoanApplicationBuilderSpec` equivalence test — if it ever fails
after an M3 edit, revert that edit (`git checkout -- jitsurei/src/Jitsurei/LoanApplication.hs`)
and re-run `cabal test jitsurei:jitsurei-test` to return to the known-good baseline before
retrying.

There are no migrations, no generated artifacts, and no destructive operations anywhere in
this plan.


## Interfaces and Dependencies

This plan is self-contained. It touches only the operator/label authoring surface of one
module, `src/Keiki/Builder.hs`, and reads (without modifying) the `IsLabel`/`Index`/`Term`
machinery in `src/Keiki/Core.hs` and the `IndexN`/`HasIndexN` machinery in
`src/Keiki/Internal/Slots.hs`. No sibling plan under `docs/plans/` modifies these symbols, so
there are no hard or soft dependencies on other plans. The parent MasterPlan is
`docs/masterplans/13-keiki-api-improvements-surfaced-by-the-rei-migration.md`.

No new library dependencies are introduced. The only added intra-package coupling is one new
import in `src/Keiki/Builder.hs`: `TReg` from `Keiki.Core` (M2). Everything else `reg` and
`(:=)` need is already imported by the module.

Signatures and exports that must exist at the end of each milestone, all in module
`Keiki.Builder` (file `src/Keiki/Builder.hs`):

End of M1 — the operator `(:=)` is exported and defined with the same type and fixity as
`(.=)`:

    (:=)
      :: forall name r rs ci co v w.
         ( KnownSymbol name, Disjoint '[name] w )
      => IndexN name rs r
      -> Term rs ci r
      -> EdgeBuilder rs ci co v w (Concat '[name] w) ()
    infixr 6 :=

where `IndexN` and `Concat`/`Disjoint` come from `Keiki.Internal.Slots`, `Term`/`EdgeBuilder`
are the existing builder/core types, and `KnownSymbol` is from `GHC.TypeLits`. `(.=)` remains
exported with its existing signature.

End of M2 — the value `reg` is exported and defined as:

    reg
      :: forall (name :: Symbol) rs ci r.
         ( KnownSymbol name, HasIndexN name rs r )
      => Term rs ci r

with body `reg = TReg (indexNToIndex (indexN @name @rs @r))`, where `HasIndexN` and `indexN`
come from `Keiki.Internal.Slots`, `indexNToIndex` is the existing builder-local bridge
`IndexN name rs r -> Index rs r` (at `src/Keiki/Builder.hs` ~line 551), and `TReg` /
`Term` come from `Keiki.Core`. This mirrors the existing `slot :: forall (name :: Symbol) rs
r. (KnownSymbol name, HasIndexN name rs r) => IndexN name rs r`.

End of M3 — no new exported interfaces; the consumers `jitsurei/src/Jitsurei/LoanApplication.hs`
and `test/Keiki/BuilderSpec.hs` import `reg` and/or `(:=)` from `Keiki.Builder`, and the user
guide `docs/guide/user-guide.md` documents both. The pre-existing public types referenced by
the test — `Edge`, `update`, `edgesOut`, `Update`, `reconstitute` from `Keiki.Core` — are
unchanged. The only new artifact is the documentation page
`docs/guide/generic-lens-and-label-reads.md`, cross-linked from `docs/guide/user-guide.md`;
it adds no code interface.


## Revision Notes

- 2026-05-21: Initial authoring of the plan body into the pre-existing skeleton. The YAML
  frontmatter was left untouched. All prose sections were filled from a direct reading of
  `src/Keiki/Builder.hs`, `src/Keiki/Core.hs`, `src/Keiki/Internal/Slots.hs`, the EP-45
  commits `73c1974` and `01492f9`, the dogfood candidate
  `jitsurei/src/Jitsurei/LoanApplication.hs`, its equivalence test
  `jitsurei/test/Jitsurei/LoanApplicationBuilderSpec.hs`, the builder unit-test module
  `test/Keiki/BuilderSpec.hs`, the two cabal files, and `docs/guide/user-guide.md`. Why: to
  turn the master-plan-derived intent (a non-breaking `(:=)` synonym and a `reg @"slot"`
  read helper, plus the correction that bare `#slot` already works as a read) into a
  self-contained, executable plan with concrete file/line anchors, exact commands, and a
  behavior-preserving acceptance strategy anchored on the existing equivalence test.
- 2026-05-21: Folded in findings from validating the plan against the live consumer (the Rei
  migration, verified in `../rei-project/rei.keiro-migration`). The central correction: the
  earlier framing called the consumer's `proj (indexOf @"slot" @Regs @Ty)` register reads
  "partly inaccurate" on the grounds that a bare `#slot` already works via keiki's
  `IsLabel s (Term rs ci r)` instance. Validation showed that is wrong for any realistic
  consumer — Rei's prelude (`rei-core/src/Rei/Prelude.hs`) re-exports generic-lens, whose
  `IsLabel` instance shadows keiki's, making the bare-`#slot` read path unusable; Rei reads
  every register via `proj (indexOf @…)` (10 occurrences, four register-bearing transducer
  files, zero bare or annotated `#slot` reads). Because `reg @"slot"` is TypeApplication-based
  and never goes through an overloaded label, it sidesteps the collision and is therefore the
  genuine fix and the higher-value half of this plan. Why the change: the plan must not ship
  with a rationale that misrepresents the consumer it was built for. Sections updated: Purpose
  / Big Picture (reframed register reads as essential, not cosmetic; noted the nine
  `hiding ((.=))` files confirming the `(.=)`/`Control.Lens.(.=)` clash is real); Context and
  Orientation (added the generic-lens shadowing caveat to the *Overloaded label* glossary
  entry); Decision Log (replaced the "partly inaccurate" decision with the corrected
  understanding, and added a decision recording the confirmed consumer adoption surface as
  use-evidence). The technical design of `reg`/`:=` (signatures, milestones, the milestone
  count of three, and the Progress checklist) was left unchanged, as was the YAML frontmatter
  and the in-tree `jitsurei` dogfood target.
- 2026-05-21: Added a documentation deliverable — a new standalone keiki user guide page at
  `docs/guide/generic-lens-and-label-reads.md` — and folded it into the existing M3
  (documentation) milestone so the milestone count stays at three and the Progress checklist
  stays at three items (M3's wording was extended, not split). The page establishes a guiding
  principle for *new* projects that use generic-lens: do not globally re-export
  `Data.Generics.Labels` / `import Data.Generics.Labels ()` from a shared prelude; import
  generic-lens labels only in modules that use lens-style field optics (read models, view
  projections, application/handler code), and keep keiki transducer modules free of that
  import, so bare `#slot` register reads keep resolving through keiki's
  `IsLabel s (Term rs ci r)` instance and the `.=` builder operator is less likely to clash
  with `Control.Lens.(.=)`. The mechanism was verified against live source before writing:
  `src/Keiki/Core.hs` ships `IsLabel s (Term rs ci r)` (lines 223–226, body
  `TReg (indexOf @s @rs @r)`) and `IsLabel s (Index rs r)` (lines 207–210), and `proj = TReg`
  (line 627); generic-lens supplies a competing general `IsLabel` from `Data.Generics.Labels`
  that, once globally in scope, makes `#slot` ambiguous inside a transducer module. The cause
  Rei hit was reconfirmed: `rei-core/src/Rei/Prelude.hs` line 73 has
  `import "generic-lens" Data.Generics.Labels ()`, and Rei reads registers via
  `proj (indexOf @…)` in 100% of cases (10 occurrences across four transducer files, zero bare
  `#slot`). Critical framing, stated at the user's explicit instruction: the guide does *not*
  tell existing projects to refactor — the `reg @"slot"` and `:=` helpers this plan already
  adds are the supported no-refactor path for projects (like Rei) already committed to a global
  generic-lens import; the import-scoping discipline is the recommended default for new
  projects only; the two are complementary, not either/or. The parallel
  `.=`/`Control.Lens.(.=)` collision is covered the same way (scope lens imports where you can;
  use `(:=)` from M1 where you cannot). Sections updated: Purpose / Big Picture (new
  guide-and-principle paragraphs); Progress (extended the M3 item, still three items); Plan of
  Work M3 (scope, new "Edit five" authoring the page and adding the cross-links, acceptance);
  Concrete Steps (extended Step 6 to create the page and cross-link it); Validation and
  Acceptance (added a documentation-deliverable acceptance: the guide states the principle, the
  helpers-are-not-forced framing, and a worked before/after); Idempotence and Recovery (added
  the new page to the M3 file list); Interfaces and Dependencies (End-of-M3 notes the new
  doc artifact); Decision Log (new entry recording the dedicated-page choice, the
  new-projects scope, and the helpers-as-no-refactor-path). The technical design of `reg`/`:=`
  (signatures, milestones, the milestone count of three) and the YAML frontmatter were left
  unchanged.
