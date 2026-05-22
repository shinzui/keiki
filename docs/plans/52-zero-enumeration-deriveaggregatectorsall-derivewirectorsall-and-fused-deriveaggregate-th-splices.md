---
id: 52
slug: zero-enumeration-deriveaggregatectorsall-derivewirectorsall-and-fused-deriveaggregate-th-splices
title: "Zero-enumeration deriveAggregateCtorsAll/deriveWireCtorsAll and fused deriveAggregate TH splices"
kind: exec-plan
created_at: 2026-05-22T14:05:57Z
intention: "intention_01ks7zzzdkepyad2dzecejffj6"
---

# Zero-enumeration deriveAggregateCtorsAll/deriveWireCtorsAll and fused deriveAggregate TH splices

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

Today, to wire an aggregate's command and event constructors into the keiki DSL, a
user writes two Template Haskell splices and, in each, hand-types a list of
`(constructorName, shortName)` pairs — one pair per constructor. "Template Haskell"
(TH) means Haskell code that runs at compile time to generate more Haskell code; a
"splice" is the `$( ... )` form that injects that generated code into the module. In
the overwhelmingly common case the short name is identical to the constructor name, so
that list is pure boilerplate that merely repeats what the compiler can already read off
the data type. A real example, from `jitsurei/src/Jitsurei/OrderCart.hs`, spends 24
lines listing twenty `("Name", "Name")` pairs across two splices.

After this change, a user can write instead:

```haskell
$(deriveAggregateCtorsAll ''OrderCmd ''OrderCartRegs)
$(deriveWireCtorsAll ''OrderEvent)
```

or collapse both into a single fused splice:

```haskell
$(deriveAggregate ''OrderCmd ''OrderCartRegs ''OrderEvent)
```

Both forms generate exactly the same top-level declarations the enumerated forms
generate today (`inCtor<Ctor>`, `inp<Ctor>`, `is<Ctor>` for each command constructor;
`wire<Ctor>`, `<Ctor>TermFields`, and a `ToOutFields` instance for each event
constructor), with each constructor's own name used as the suffix. The existing
enumerated splices (`deriveAggregateCtors`, `deriveWireCtors`) remain, because they are
the only way to request *abbreviated* short names (for example `"StartRegistration" ->
"Start"`, which the fixture `test/Keiki/Fixtures/UserRegistration.hs` actually uses).

You will see it working four ways: (1) new unit tests in
`test/Keiki/Generics/THSpec.hs` that exercise the auto-enumerated and fused splices on
toy aggregates and assert the generated identifiers exist and behave correctly; (2) the
real `jitsurei/src/Jitsurei/OrderCart.hs` example migrated from the two enumerated
splices to the single fused `deriveAggregate`, with the existing `jitsurei-test` suite
passing unchanged (proving the generated names and behavior are byte-for-byte
equivalent, since that module's `KnownInCtors OrderCmd` instance references the generated
`inCtorAddItem`, `inCtorRemoveItem`, ... by name); (3) updated user-facing documentation
(`docs/guide/user-guide.md`, `docs/foundations/06-where-to-go-next.md`, and
`docs/guide/ast-drop-down.md`) describing when to reach for each form; and (4) a new
entry in the package's `CHANGELOG.md` so the other teams that already consume `keiki`
learn about the new splices.

Because `keiki` is now a dependency of other teams, every public-surface change must be
announced in the changelog. The repository already ships a `CHANGELOG.md` at its root in
[Keep a Changelog](https://keepachangelog.com/) format, wired into `keiki.cabal` via
`extra-doc-files` so it is bundled with the package. This plan adds the new splices to its
`[Unreleased]` section rather than creating a new file.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] M1: Add `deriveAggregateCtorsAll` and `deriveWireCtorsAll` to `src/Keiki/Generics/TH.hs`, export them, and update the module Haddock header. (2026-05-22)
- [x] M1: Add toy `AutoCmd`/`AutoRegs`/`AutoEvent` types and `deriveAggregateCtorsAll`/`deriveWireCtorsAll` splices plus assertions to `test/Keiki/Generics/THSpec.hs`. (2026-05-22)
- [x] M1: `cabal test keiki-test` passes including the new `*All` examples. (2026-05-22 — 275 examples, 0 failures; the 6 new `*All` examples pass under `--match "no spec list"`.)
- [x] M2: Add fused `deriveAggregate` to `src/Keiki/Generics/TH.hs`, export it, and document it in the module Haddock header. (2026-05-22)
- [x] M2: Add toy `FusedCmd`/`FusedRegs`/`FusedEvent` types and a `deriveAggregate` splice plus assertions to `test/Keiki/Generics/THSpec.hs`. (2026-05-22)
- [x] M2: `cabal test keiki-test` passes including the fused example. (2026-05-22 — 278 examples, 0 failures; the 3 fused examples pass under `--match "deriveAggregate (fused"`. No compiler warnings.)
- [x] M3: Migrate `jitsurei/src/Jitsurei/OrderCart.hs` to the single fused `deriveAggregate` splice and update its import list. (2026-05-22)
- [x] M3: `cabal test all` is green (in particular `jitsurei-test`, unchanged). (2026-05-22 — jitsurei-test 96 examples, 0 failures, no test edits; keiki-codec-json-test 40, 0 failures; full build with zero compiler warnings.)
- [ ] M4: Add a subsection 4.3 to `docs/guide/user-guide.md` covering the `*All` and fused forms and guidance on when the enumerated forms are still needed.
- [ ] M4: Name the new splices in `docs/foundations/06-where-to-go-next.md` where it lists what `Keiki.Generics.TH` derives.
- [ ] M4: Add a one-line note to `docs/guide/ast-drop-down.md` that the `*All`/fused forms produce identical declarations to the enumerated ones.
- [ ] M4: Add an `### Added` entry under `[Unreleased]` in `CHANGELOG.md` describing `deriveAggregateCtorsAll`, `deriveWireCtorsAll`, and `deriveAggregate`.
- [ ] M4: Confirm no historical docs (`docs/research/`, `docs/masterplans/`, `docs/plans/`) were edited.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Keep the existing enumerated splices (`deriveAggregateCtors`,
  `deriveWireCtors`) rather than replacing them.
  Rationale: The second element of each spec tuple is a *short name* used as the suffix on
  generated identifiers, and abbreviation is genuinely used in
  `test/Keiki/Fixtures/UserRegistration.hs` (e.g. `("StartRegistration", "Start")`,
  `("FulfillGDPRRequest", "Gdpr")`). Auto-enumeration can only default the short name to
  the constructor name, so it cannot express abbreviation. The two forms are
  complementary, not substitutes.
  Date: 2026-05-22

- Decision: Implement the `*All` variants directly (reify once, build the spec list with
  `(nameBase n, nameBase n)`) rather than delegating to the enumerated splices.
  Rationale: Delegating would `reify` the type twice (once in the `*All` wrapper to build
  the spec, once again inside the enumerated splice). Reifying directly and calling the
  existing internal generators `genCtor`/`genWire` mirrors the enumerated splices'
  bodies exactly with no duplicated reflection and no behavioral divergence.
  Date: 2026-05-22

- Decision: Implement the fused `deriveAggregate` by composing the two `*All` variants
  (`deriveAggregateCtorsAll` for the command side, `deriveWireCtorsAll` for the event
  side) and concatenating their declarations.
  Rationale: The fused splice is purely a convenience that bundles the command and event
  derivations. Composing the `*All` variants keeps a single source of truth for each
  side's code generation; there is no shared reflection to dedupe because the command and
  event types are distinct.
  Date: 2026-05-22

- Decision: `deriveAggregate`'s argument order is command sum type, register-file slot
  list, event sum type — i.e. `deriveAggregate ''Cmd ''Regs ''Event`.
  Rationale: It reads as "an aggregate is a command, over some state, producing an event,"
  and keeps the `(''Cmd ''Regs ...)` prefix identical to `deriveAggregateCtors` /
  `deriveAggregateCtorsAll` so the event type is simply appended.
  Date: 2026-05-22

- Decision: Migrate the `jitsurei/src/Jitsurei/OrderCart.hs` worked example to the fused
  `deriveAggregate`, but leave `test/Keiki/Fixtures/UserRegistration.hs` on the
  enumerated forms.
  Rationale: OrderCart uses short-name-equals-constructor-name throughout, so the
  migration is name-preserving and serves as the strongest end-to-end demonstration via
  the existing `jitsurei-test`. UserRegistration uses abbreviated short names and must
  stay enumerated, so it continues to document that form.
  Date: 2026-05-22

- Decision: Extend the existing root `CHANGELOG.md` rather than create a new changelog
  file, and record the new splices under its `[Unreleased]` → `### Added` section.
  Rationale: A `CHANGELOG.md` already exists at the repository root in Keep a Changelog
  format and is already referenced by `keiki.cabal`'s `extra-doc-files` (lines 29–30), so
  it ships with the package to Hackage and to the teams consuming `keiki`. Its
  `[0.1.0.0]` section is still TBD/unreleased; the canonical Keep a Changelog place for
  changes that have landed since the last snapshot is `[Unreleased]`, which folds into
  0.1.0.0 at release. Creating a second file would fragment the record and break the
  cabal wiring.
  Date: 2026-05-22

- Decision: No PVP version bump in `keiki.cabal` as part of this plan.
  Rationale: The library is pre-Hackage and `version: 0.1.0.0` is still unreleased, so
  these purely additive exports fold into the unreleased 0.1.0.0 rather than triggering a
  new version. (Were 0.1.0.0 already published, adding to the public API would warrant a
  PVP minor bump to 0.2.0.0; that is out of scope here.)
  Date: 2026-05-22

- Decision: Update only the living user-facing docs (`docs/guide/user-guide.md`,
  `docs/foundations/06-where-to-go-next.md`, `docs/guide/ast-drop-down.md`) plus the
  module Haddock and `CHANGELOG.md`; do not touch `docs/research/`, `docs/masterplans/`,
  or `docs/plans/`.
  Rationale: The `docs/research/`, `docs/masterplans/`, and `docs/plans/` directories are
  point-in-time design and history records — retroactively editing them to mention a
  later API would falsify the historical record. Several of them mention
  `deriveAggregateCtors`/`deriveWireCtors` precisely because that was the state when they
  were written. `docs/guide/composition.md` also mentions `deriveWireCtors` but only to
  explain unchanged event-codec behavior, so it needs no edit.
  Date: 2026-05-22


- Decision: In the OrderCart migration, place the single fused
  `$(deriveAggregate ''OrderCmd ''OrderCartRegs ''OrderEvent)` under the existing
  `-- * Per-constructor input projections + guards (TH-derived)` section header, and
  retain the `-- * Wire constructors for events (TH-derived)` section header below it
  with a short comment noting the wire constructors are now emitted by the fused splice
  above (rather than leaving a dangling header or deleting it).
  Rationale: A fused splice can only live in one location, and it must appear *before* the
  `instance KnownInCtors OrderCmd` block (lines 337–349) that references `inCtorAddItem`
  etc., because Template Haskell only brings spliced names into scope textually after the
  splice. Keeping both section headers preserves the document's command-side/event-side
  orientation that the plan asked to retain; the explanatory comment under the second
  header keeps it from being misleading now that no splice sits beneath it.
  Date: 2026-05-22

- Decision: Left the guide's running example (`docs/guide/user-guide.md` lines 44/97/100)
  on the enumerated `deriveAggregateCtors`/`deriveWireCtors` forms rather than rewriting it
  to the fused form (M4 Edit 2, marked optional in the plan).
  Rationale: Keeping the running example enumerated lets the guide continue to show the
  enumerated style end-to-end, while the new subsection 4.3 introduces and demonstrates the
  `*All`/fused forms. Showing both styles serves readers better than converging the example
  on one.
  Date: 2026-05-22

## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

This repository is a Haskell library, `keiki`, built with Cabal. The Cabal project file
`cabal.project` at the repository root lists four packages: `.` (the `keiki` library and
its test suite), `jitsurei` (worked examples that depend on `keiki`), and two
`keiki-codec-json` packages (not touched by this plan). The `keiki` library's component
metadata lives in `keiki.cabal`; its test suite is named `keiki-test`. The `jitsurei`
package's metadata lives in `jitsurei/jitsurei.cabal`; its test suite is named
`jitsurei-test`.

All the code you will change for the helper itself lives in one module:
`src/Keiki/Generics/TH.hs`. This module defines Template Haskell splices that generate
the per-constructor "plumbing" declarations a command or event constructor needs in the
keiki DSL. Three terms of art used throughout:

- A **command sum type** is an ordinary Haskell `data` type whose constructors are the
  commands an aggregate accepts, e.g. `data OrderCmd = AddItem AddItemData | ... `. Each
  constructor either wraps a single record "payload" type (e.g. `AddItemData`) or takes
  no argument at all (a "singleton" command).
- An **event sum type** is the dual: a `data` type whose constructors are the events the
  aggregate emits, e.g. `data OrderEvent = ItemAdded ItemAddedData | ...`.
- A **register-file slot list** is a type-level list describing the aggregate's state
  fields, written as `type OrderCartRegs = '[ '("qty", Word16), ... ]`. The generated
  command helpers are parameterized by this type.

The existing public splices, exported from `src/Keiki/Generics/TH.hs` (the export list is
at lines 44–48), are:

```haskell
deriveAggregateCtors
  :: Name              -- command sum type, e.g. ''OrderCmd
  -> Name              -- register-file slot list, e.g. ''OrderCartRegs
  -> [(String, String)]  -- pairs of (constructorName, shortName)
  -> Q [Dec]

deriveWireCtors
  :: Name              -- event sum type, e.g. ''OrderEvent
  -> [(String, String)]  -- pairs of (constructorName, shortName)
  -> Q [Dec]

deriveView :: ...      -- unrelated to this plan; do not touch
```

`Name`, `Q`, and `Dec` come from `Language.Haskell.TH`, imported at line 52. `Name` is a
reference to a Haskell name (here, a type name supplied at the call site as `''OrderCmd`);
`Q` is the Template Haskell code-generation monad; `[Dec]` is a list of generated
top-level declarations.

The two splices already read the full constructor list of the named type by reflection
and only consult the supplied spec list to (a) choose which constructors to emit and (b)
pick each one's short-name suffix. Concretely, `deriveAggregateCtors` (lines 88–91) is:

```haskell
deriveAggregateCtors cmdName regsName specs = do
  ctors <- reifyCtors cmdName "deriveAggregateCtors"
  let ctorMap = [ (nameBase n, c) | c <- ctors, n <- conNames c ]
  fmap concat . mapM (genCtor cmdName regsName ctorMap) $ specs
```

and `deriveWireCtors` (lines 103–106) is the dual:

```haskell
deriveWireCtors evtName specs = do
  ctors <- reifyCtors evtName "deriveWireCtors"
  let ctorMap = [ (nameBase n, c) | c <- ctors, n <- conNames c ]
  fmap concat . mapM (genWire evtName ctorMap) $ specs
```

The internal helpers they rely on are all defined later in the same file:

- `reifyCtors :: Name -> String -> Q [Con]` (lines 262–268) runs `reify` on the named
  type and returns its constructor list (`[Con]`), failing with a precise message if the
  name is not a `data` declaration. `Con` is Template Haskell's representation of a single
  data constructor.
- `conNames :: Con -> [Name]` (lines 271–275) returns the name(s) of a constructor:
  `[n]` for `NormalC`, `RecC`, and `InfixC`, and `[]` for shapes it does not handle
  (GADT/forall constructors). `nameBase :: Name -> String` (from `Language.Haskell.TH`)
  strips a `Name` down to its bare identifier text, e.g. `nameBase ''AddItem == "AddItem"`.
- `genCtor :: Name -> Name -> [(String, Con)] -> (String, String) -> Q [Dec]`
  (lines 289–308) generates the declarations for *one* command constructor given the
  command type name, the regs type name, the constructor lookup map, and a single
  `(constructorName, shortName)` spec entry.
- `genWire :: Name -> [(String, Con)] -> (String, String) -> Q [Dec]` (lines 368–412) is
  the event-side equivalent.

So adding "all constructors, short name = constructor name" support requires no new code
generation at all — only building the spec list automatically from the reflected
constructor list and feeding it to the existing generators.

Two observable facts that matter for correctness and that this plan relies on:

1. Constructor names are unique within a sum type, so using each constructor's own name as
   its short-name suffix yields unique generated identifiers with no collisions.
2. The generated declarations are top-level bindings; their relative order is irrelevant,
   so emitting them in the type's declaration order (what reflection returns) is fine.

The test module is `test/Keiki/Generics/THSpec.hs` (95 lines today). It exercises the
splices on a toy aggregate `ToyCmd`/`ToyRegs` declared inline, with a record-payload
constructor `DoIt ToyData` and a singleton constructor `NoArgs`, and asserts the
generated `inCtorDoIt`, `inpDoIt`, `isDoIt`, `inCtorNoArgs`, `isNoArgs` identifiers exist
and behave (name, match/build, projection, predicate). The accessors it uses come from
`Keiki.Core`: `InCtor` is a record with `icName :: String`, `icMatch :: ci -> Maybe
(RegFile ifs)`, and `icBuild :: RegFile ifs -> ci` (defined at `src/Keiki/Core.hs`
lines 297–302). The event/wire side uses `WireCtor co fields` with `wcName :: String`,
`wcMatch`, and `wcBuild :: fields -> co` (defined at `src/Keiki/Core.hs` lines 404–407);
`THSpec.hs` does not currently test the wire side, so this plan adds the first wire-side
assertions there. For an event constructor with a record payload of one `Int` field, the
`fields` type that `wcBuild` accepts is the nested-pair tuple `(Int, ())` (this is the
shape `Keiki.Generics.FieldsOf` reduces a single-field record to); for a singleton event
it is `()`.

The real worked example to migrate in M3 is `jitsurei/src/Jitsurei/OrderCart.hs`. Its
current splices are at lines 317–328 (`deriveAggregateCtors ''OrderCmd ''OrderCartRegs
[...]`, ten `("Name","Name")` entries) and lines 354–365 (`deriveWireCtors ''OrderEvent
[...]`, ten `("Name","Name")` entries). Every entry there has short name equal to
constructor name. All ten `OrderCmd` constructors carry record payloads (`AddItem
AddItemData`, etc.; see lines 183–193) and all ten `OrderEvent` constructors carry record
payloads (`ItemAdded ItemAddedData`, etc.; see lines 261–271), so there are no singletons
to worry about in that example. The module currently imports the helpers at line 101:
`import Keiki.Generics.TH (deriveAggregateCtors, deriveWireCtors)`. It also defines
`instance KnownInCtors OrderCmd` (lines 337–349) which references `inCtorAddItem`,
`inCtorRemoveItem`, ... by name — these names are preserved by the migration because the
short name still equals the constructor name.

The user-facing documentation lives in `docs/guide/user-guide.md`. Section 4, "The TH
derivations" (starting at line 404), documents `deriveAggregateCtors` in subsection 4.1
(line 409) and `deriveWireCtors` in subsection 4.2 (line 424). The import example at
line 44 lists the helpers currently imported in the guide's running example. Two further
living docs reference the helpers in prose and should gain a mention of the new ones:
`docs/foundations/06-where-to-go-next.md` (line 28 says "How `Keiki.Generics` and
`Keiki.Generics.TH` derive `InCtor`, ..."; line 132 mentions `deriveWireCtors`), and
`docs/guide/ast-drop-down.md` (line 116 attributes `isConfirm` to `deriveAggregateCtors`;
lines 174/184 attribute the wire ctor and `<Ctor>TermFields` record to `deriveWireCtors`).
`docs/guide/composition.md` also mentions `deriveWireCtors` (lines 409/456) but only to
describe event-codec and singleton-event behavior that this change does not alter, so it
needs no edit.

Important: the directories `docs/research/`, `docs/masterplans/`, and `docs/plans/`
contain point-in-time design notes, master plans, and prior ExecPlans. Several mention
`deriveAggregateCtors`/`deriveWireCtors` because that was the state of the world when they
were authored. Do not edit them — they are historical records, and rewriting them to
mention a later API would falsify that history.

Change announcement for downstream teams happens through the changelog. The repository
already ships `CHANGELOG.md` at its root, in [Keep a Changelog](https://keepachangelog.com/)
format, declared in `keiki.cabal` `extra-doc-files` (lines 29–30) so it is bundled into the
package. The file has a `## [Unreleased]` section (currently just a "(Pre-Hackage. The
next published release is 0.1.0.0.)" note) followed by a `## [0.1.0.0] — TBD` section whose
`### Added` list already includes a `Keiki.Generics.TH` bullet naming `deriveAggregateCtors`,
`deriveWireCtors`, and `deriveView`. Because 0.1.0.0 has not been released yet but other
teams already consume the library from source, new additions go under `[Unreleased]`. The
sibling package's `keiki-codec-json/CHANGELOG.md` follows the identical format and is a good
template for the wording and the `### Added` heading.


## Plan of Work

The work proceeds in four milestones. M1 and M2 are additive library changes with their
own tests; M3 is a name-preserving migration of a real example that demonstrates
equivalence; M4 is documentation. Each milestone leaves the tree building and all tests
green.

### Milestone 1 — the `*All` variants

Scope: add two new public splices to `src/Keiki/Generics/TH.hs` and prove them on toy
types. At the end, `deriveAggregateCtorsAll ''Cmd ''Regs` and `deriveWireCtorsAll
''Event` generate the same declarations the enumerated forms generate when every short
name equals its constructor name — but with no spec list typed by hand.

Edit 1 (export list, `src/Keiki/Generics/TH.hs` lines 44–48). Add the two new names to
the module export list so they read:

```haskell
module Keiki.Generics.TH
  ( deriveAggregateCtors
  , deriveAggregateCtorsAll
  , deriveWireCtors
  , deriveWireCtorsAll
  , deriveAggregate
  , deriveView
  ) where
```

(`deriveAggregate` is added now to avoid a second export-list edit in M2; it will be
defined in M2. If you prefer to keep each milestone's diff self-contained, add
`deriveAggregate` to the export list in M2 instead — either is fine, but do not leave an
exported name undefined across a commit boundary, so if you export it here, define a stub
or simply defer the export to M2.)

To keep every commit compiling, the simplest sequencing is: in M1 export only
`deriveAggregateCtorsAll` and `deriveWireCtorsAll`; in M2 add `deriveAggregate` to both
the export list and the body in the same commit.

Edit 2 (new definitions, `src/Keiki/Generics/TH.hs`, immediately after
`deriveAggregateCtors`, i.e. after line 91). Add:

```haskell
-- | Like 'deriveAggregateCtors', but enumerate every constructor of the
-- command sum type automatically, using each constructor's own name as
-- its short-name suffix. Equivalent to calling 'deriveAggregateCtors'
-- with a spec list of @[(nameBase c, nameBase c) | c <- constructors]@,
-- so it generates @inCtor\<Ctor\>@, @inp\<Ctor\>@, and @is\<Ctor\>@ for
-- each constructor (singletons omit @inp\<Ctor\>@). Reach for the
-- enumerated 'deriveAggregateCtors' when you need an abbreviated short
-- name that differs from the constructor name.
deriveAggregateCtorsAll
  :: Name              -- ^ command sum type, e.g. @\'\'OrderCmd@
  -> Name              -- ^ register-file slot list, e.g. @\'\'OrderCartRegs@
  -> Q [Dec]
deriveAggregateCtorsAll cmdName regsName = do
  ctors <- reifyCtors cmdName "deriveAggregateCtorsAll"
  let ctorMap = [ (nameBase n, c)            | c <- ctors, n <- conNames c ]
      specs   = [ (nameBase n, nameBase n)   | c <- ctors, n <- conNames c ]
  fmap concat . mapM (genCtor cmdName regsName ctorMap) $ specs
```

Edit 3 (new definitions, `src/Keiki/Generics/TH.hs`, immediately after `deriveWireCtors`,
i.e. after line 106). Add:

```haskell
-- | Like 'deriveWireCtors', but enumerate every constructor of the event
-- sum type automatically, using each constructor's own name as its
-- short-name suffix. Generates @wire\<Ctor\>@ (and, for record-payload
-- events, a @\<Ctor\>TermFields@ record plus its 'ToOutFields' instance)
-- for each constructor. Reach for the enumerated 'deriveWireCtors' when
-- you need an abbreviated short name that differs from the constructor
-- name.
deriveWireCtorsAll
  :: Name              -- ^ event sum type, e.g. @\'\'OrderEvent@
  -> Q [Dec]
deriveWireCtorsAll evtName = do
  ctors <- reifyCtors evtName "deriveWireCtorsAll"
  let ctorMap = [ (nameBase n, c)            | c <- ctors, n <- conNames c ]
      specs   = [ (nameBase n, nameBase n)   | c <- ctors, n <- conNames c ]
  fmap concat . mapM (genWire evtName ctorMap) $ specs
```

Note the two list comprehensions in each definition iterate the same `ctors`/`conNames`
structure and could be fused into one pass; they are written separately to mirror the
existing `deriveAggregateCtors`/`deriveWireCtors` bodies (which build `ctorMap` the same
way) so a reader can diff them at a glance. Either form is acceptable.

Edit 4 (module Haddock header, top of `src/Keiki/Generics/TH.hs`, lines 1–43). Extend the
header prose to mention the two new splices alongside the existing ones — a sentence
stating that `deriveAggregateCtorsAll`/`deriveWireCtorsAll` are the zero-spec variants
that default each short name to the constructor name, and that the enumerated forms remain
for abbreviated short names.

Edit 5 (tests, `test/Keiki/Generics/THSpec.hs`). Add a new toy aggregate with distinct
constructor names (so the generated identifiers do not collide with the existing `ToyCmd`
splice output in the same module), the two new splices, and a `describe` block per side.
Insert after the existing `toyRegs` definition (after line 48) and add the new `describe`
blocks inside `spec` (after line 95). Suggested toy types and splices:

```haskell
data WidgetData = WidgetData { wa :: Int, wb :: Int }
  deriving (Eq, Show, Generic)

data AutoCmd
  = MakeWidget WidgetData
  | Sweep
  deriving (Eq, Show, Generic)

type AutoRegs =
  '[ '("wa", Int)
   , '("wb", Int)
   ]

data GadgetData = GadgetData { gz :: Int }
  deriving (Eq, Show, Generic)

data AutoEvent
  = WidgetMade GadgetData
  | Swept
  deriving (Eq, Show, Generic)

$(deriveAggregateCtorsAll ''AutoCmd ''AutoRegs)
$(deriveWireCtorsAll ''AutoEvent)

autoRegs :: RegFile AutoRegs
autoRegs = RCons (Proxy @"wa") 0 (RCons (Proxy @"wb") 0 RNil)
```

The new assertions (added to `spec`) should prove that auto-enumeration discovered each
constructor and that the generated identifiers behave. Concretely:

```haskell
  describe "deriveAggregateCtorsAll (no spec list)" $ do
    it "discovers the record-payload command and names it after the ctor" $
      icName inCtorMakeWidget `shouldBe` "MakeWidget"

    it "matches MakeWidget and yields a populated RegFile" $
      let regfile = case icMatch inCtorMakeWidget (MakeWidget (WidgetData 3 4)) of
            Just rf -> rf
            Nothing -> error "icMatch returned Nothing on MakeWidget"
      in (regfile ! #wa, regfile ! #wb) `shouldBe` (3, 4)

    it "evalTerm (inpMakeWidget #wa) reads the wa field" $
      evalTerm (inpMakeWidget #wa) autoRegs (MakeWidget (WidgetData 5 9)) `shouldBe` 5

    it "discovers the singleton command and its guard" $ do
      icName inCtorSweep `shouldBe` "Sweep"
      evalPred isSweep autoRegs Sweep                       `shouldBe` True
      evalPred isSweep autoRegs (MakeWidget (WidgetData 0 0)) `shouldBe` False

  describe "deriveWireCtorsAll (no spec list)" $ do
    it "discovers the record-payload event and rebuilds it" $ do
      wcName wireWidgetMade `shouldBe` "WidgetMade"
      wcBuild wireWidgetMade (7, ()) `shouldBe` WidgetMade (GadgetData 7)

    it "discovers the singleton event and rebuilds it" $ do
      wcName wireSwept `shouldBe` "Swept"
      wcBuild wireSwept () `shouldBe` Swept
```

If `THSpec.hs` does not already import `wcName`/`wcBuild`, they come from `Keiki.Core`
(already imported as `import Keiki.Core` at line 9, which is unqualified and brings them
into scope). The `(7, ())` literal is the `FieldsOf GadgetData` value for the single-field
payload; `wcBuild` reconstructs the event from it.

Acceptance for M1: from the repository root, `cabal test keiki-test` builds and runs, and
the new `deriveAggregateCtorsAll`/`deriveWireCtorsAll` examples pass alongside the
existing ones.

### Milestone 2 — the fused `deriveAggregate`

Scope: add a single splice that performs both the command-side and event-side derivation,
so an aggregate's entire DSL plumbing is one line. At the end,
`deriveAggregate ''Cmd ''Regs ''Event` is equivalent to `deriveAggregateCtorsAll ''Cmd
''Regs` followed by `deriveWireCtorsAll ''Event`.

Edit 1 (export list). Add `deriveAggregate` to the export list of
`src/Keiki/Generics/TH.hs` (if not already added in M1).

Edit 2 (new definition, `src/Keiki/Generics/TH.hs`, after `deriveWireCtorsAll`). Add:

```haskell
-- | Fuse 'deriveAggregateCtorsAll' and 'deriveWireCtorsAll' into one
-- splice covering an aggregate's command and event constructors. Given
-- the command sum type, its register-file slot list, and the event sum
-- type, this emits every declaration both @*All@ variants would, using
-- each constructor's own name as its short-name suffix.
--
-- @
-- $('deriveAggregate' \'\'OrderCmd \'\'OrderCartRegs \'\'OrderEvent)
-- @
deriveAggregate
  :: Name              -- ^ command sum type, e.g. @\'\'OrderCmd@
  -> Name              -- ^ register-file slot list, e.g. @\'\'OrderCartRegs@
  -> Name              -- ^ event sum type, e.g. @\'\'OrderEvent@
  -> Q [Dec]
deriveAggregate cmdName regsName evtName = do
  cmdDecs <- deriveAggregateCtorsAll cmdName regsName
  evtDecs <- deriveWireCtorsAll evtName
  pure (cmdDecs ++ evtDecs)
```

Edit 3 (module Haddock header). Add a sentence describing `deriveAggregate` as the fused
all-in-one form.

Edit 4 (tests, `test/Keiki/Generics/THSpec.hs`). Add a third toy aggregate with fresh
constructor names and a single fused splice, then assert that both a command-side and an
event-side identifier were generated and behave:

```haskell
data FooData = FooData { fa :: Int }
  deriving (Eq, Show, Generic)

data FusedCmd
  = Foo FooData
  | Tick
  deriving (Eq, Show, Generic)

type FusedRegs =
  '[ '("fa", Int) ]

data FizzData = FizzData { fb :: Int }
  deriving (Eq, Show, Generic)

data FusedEvent
  = Fizzed FizzData
  deriving (Eq, Show, Generic)

$(deriveAggregate ''FusedCmd ''FusedRegs ''FusedEvent)

fusedRegs :: RegFile FusedRegs
fusedRegs = RCons (Proxy @"fa") 0 RNil
```

```haskell
  describe "deriveAggregate (fused command + event)" $ do
    it "generates the command-side InCtor" $ do
      icName inCtorFoo `shouldBe` "Foo"
      evalTerm (inpFoo #fa) fusedRegs (Foo (FooData 11)) `shouldBe` 11

    it "generates the command-side singleton guard" $ do
      evalPred isTick fusedRegs Tick            `shouldBe` True
      evalPred isTick fusedRegs (Foo (FooData 0)) `shouldBe` False

    it "generates the event-side WireCtor" $ do
      wcName wireFizzed `shouldBe` "Fizzed"
      wcBuild wireFizzed (13, ()) `shouldBe` Fizzed (FizzData 13)
```

Acceptance for M2: `cabal test keiki-test` passes including the fused example, proving one
splice produced both `inCtorFoo`/`inpFoo`/`isTick` (command side) and `wireFizzed`/
`FizzedTermFields` (event side).

### Milestone 3 — adopt the fused splice in the OrderCart worked example

Scope: replace the two enumerated splices in `jitsurei/src/Jitsurei/OrderCart.hs` with a
single fused `deriveAggregate`, and update the import. This is the headline
demonstration: a real 24-line block of `("Name","Name")` pairs collapses to one line, and
the unchanged `jitsurei-test` suite proves the generated names and behavior are identical.

Edit 1 (import, `jitsurei/src/Jitsurei/OrderCart.hs` line 101). Change

```haskell
import Keiki.Generics.TH (deriveAggregateCtors, deriveWireCtors)
```

to

```haskell
import Keiki.Generics.TH (deriveAggregate)
```

Edit 2 (splices, `jitsurei/src/Jitsurei/OrderCart.hs`). Replace the two splice blocks
(the `deriveAggregateCtors ''OrderCmd ''OrderCartRegs [...]` at lines 317–328 and the
`deriveWireCtors ''OrderEvent [...]` at lines 354–365) with the single line:

```haskell
$(deriveAggregate ''OrderCmd ''OrderCartRegs ''OrderEvent)
```

Keep the surrounding section comments that explain what the generated identifiers are used
for; only the splice expressions change. The `instance KnownInCtors OrderCmd` block
(lines 337–349) is untouched and still compiles because `inCtorAddItem`,
`inCtorRemoveItem`, ..., are still generated under the same names (short name = ctor name).

Acceptance for M3: from the repository root, `cabal build all` succeeds and `cabal test
all` is green — in particular `jitsurei-test` passes without any change to its test code,
demonstrating the migration is behavior-preserving.

### Milestone 4 — documentation and changelog

Scope: teach users the new forms and announce them to downstream teams. At the end, the
living guide documents the `*All` and fused splices, the two other living docs that name
the helpers mention the new ones, and `CHANGELOG.md` carries an `[Unreleased]` entry. No
historical doc is touched.

Edit 1 (`docs/guide/user-guide.md`, section 4, after subsection 4.2 which ends near line
443). Add a subsection 4.3 (and renumber any following subsection if present) that:

- introduces `deriveAggregateCtorsAll ''Cmd ''Regs` and `deriveWireCtorsAll ''Event` as
  the zero-spec variants that enumerate every constructor and default each short name to
  the constructor name;
- introduces `deriveAggregate ''Cmd ''Regs ''Event` as the fused form that does both,
  showing the one-line OrderCart-style invocation;
- states the rule of thumb: use the `*All`/fused forms when short name = constructor name
  (the common case), and the enumerated `deriveAggregateCtors`/`deriveWireCtors` when you
  want an abbreviated short name (cross-reference the `UserRegistration` fixture, which
  maps e.g. `StartRegistration -> Start`).

Edit 2 (`docs/guide/user-guide.md`, optional). If the guide's running example at lines
44/97/100 would read better with the fused form, you may update it; otherwise leave the
enumerated example in place so the guide continues to show both styles. Record which you
chose in the Decision Log.

Edit 3 (`docs/foundations/06-where-to-go-next.md`). Where the file lists what
`Keiki.Generics.TH` derives (the prose around line 28 and the `deriveWireCtors` mention
around line 132), add the new splice names so a new reader pointed at this onboarding doc
learns the zero-spec and fused forms exist. Keep it to a phrase or sentence — this file is
a signpost, not a reference.

Edit 4 (`docs/guide/ast-drop-down.md`). Near the existing attributions (line 116 for
`isConfirm` via `deriveAggregateCtors`; lines 174/184 for the wire ctor and
`<Ctor>TermFields` via `deriveWireCtors`), add a one-line note that
`deriveAggregateCtorsAll`/`deriveWireCtorsAll` and the fused `deriveAggregate` produce the
identical declarations, so the AST walk-through applies unchanged regardless of which form
authored the constructors. Do not rewrite the existing attributions.

Edit 5 (`CHANGELOG.md`, repository root). Under the `## [Unreleased]` heading, add an
`### Added` subsection (Keep a Changelog convention) describing the new public surface.
Keep the existing "(Pre-Hackage ...)" note as the section's lead line and add the entry
below it, mirroring the wording style of the `[0.1.0.0]` `Keiki.Generics.TH` bullet.
Suggested content:

```markdown
## [Unreleased]

(Pre-Hackage. The next published release is 0.1.0.0.)

### Added

- `Keiki.Generics.TH` — zero-enumeration TH splices that retire the
  hand-typed `(constructorName, shortName)` spec list in the common case
  where the short name equals the constructor name:
  - `deriveAggregateCtorsAll ''Cmd ''Regs` — enumerates every command
    constructor and emits `inCtor<Ctor>` / `inp<Ctor>` / `is<Ctor>`
    (singletons omit `inp<Ctor>`), defaulting each short-name suffix to
    the constructor name.
  - `deriveWireCtorsAll ''Event` — the event-side dual, emitting
    `wire<Ctor>` plus, for record-payload events, the `<Ctor>TermFields`
    record and its `ToOutFields` instance.
  - `deriveAggregate ''Cmd ''Regs ''Event` — fuses both `*All` variants
    into one splice covering an aggregate's command and event
    constructors.
  The enumerated `deriveAggregateCtors` / `deriveWireCtors` remain for
  abbreviated short names that differ from the constructor name.
```

Do not edit any file under `docs/research/`, `docs/masterplans/`, or `docs/plans/`; those
are historical records (see Decision Log).

Acceptance for M4: subsection 4.3 exists and accurately names the three new identifiers
and their signatures; `docs/foundations/06-where-to-go-next.md` and
`docs/guide/ast-drop-down.md` name the new splices; `CHANGELOG.md` has an `[Unreleased]`
`### Added` entry covering all three; and `git diff --stat` shows changes only under
`docs/guide/`, `docs/foundations/`, and `CHANGELOG.md` (no `docs/research/`,
`docs/masterplans/`, or `docs/plans/` doc edits other than this plan file itself).


## Concrete Steps

All commands are run from the repository root `/Users/shinzui/Keikaku/bokuno/keiki`
unless stated otherwise.

Establish a clean baseline before editing:

```bash
cabal build all
cabal test keiki-test
```

You should see the existing `keiki-test` suite report all examples passing, ending with a
line like:

```text
Finished in 0.0123 seconds
NN examples, 0 failures
```

After implementing M1 (the `*All` variants and their tests):

```bash
cabal test keiki-test
```

Expected: the example count increases by the number of new `it` blocks added in
`THSpec.hs`, still with `0 failures`. The new `describe` headers
"deriveAggregateCtorsAll (no spec list)" and "deriveWireCtorsAll (no spec list)" appear in
the output when run with `--match` or verbose reporting:

```bash
cabal test keiki-test --test-options='--match "deriveAggregateCtorsAll"'
```

Expected: only the `deriveAggregateCtorsAll` examples run, all passing.

After implementing M2 (the fused splice and its test):

```bash
cabal test keiki-test --test-options='--match "deriveAggregate (fused"'
```

Expected: the fused examples run and pass.

After implementing M3 (OrderCart migration):

```bash
cabal build all
cabal test all
```

Expected: every suite passes, including `jitsurei-test`, with no edits to any
`jitsurei/test/**` file. If `cabal test all` does not run `jitsurei-test` on your setup,
run it explicitly:

```bash
cabal test jitsurei-test
```

After implementing M4 (docs and changelog), confirm the additions and that no historical
docs were touched:

```bash
git diff --stat docs/ CHANGELOG.md
```

Expected: changes appear only in `docs/guide/user-guide.md` (new subsection 4.3),
`docs/foundations/06-where-to-go-next.md`, `docs/guide/ast-drop-down.md`, `CHANGELOG.md`,
and this plan file under `docs/plans/`. There must be no changes to any other file under
`docs/research/`, `docs/masterplans/`, or `docs/plans/`. Confirm the changelog entry
landed under the right heading:

```bash
git diff CHANGELOG.md
```

Expected: an `### Added` block under `## [Unreleased]` naming
`deriveAggregateCtorsAll`, `deriveWireCtorsAll`, and `deriveAggregate`.

Commit after each milestone. Every commit must carry both trailers (this plan and the
session intention). Example for M1:

```text
feat(generics): add deriveAggregateCtorsAll/deriveWireCtorsAll zero-spec TH splices

Enumerate every constructor of the command/event sum type and default each
short-name suffix to the constructor name, removing the hand-typed spec list
in the common case. Add THSpec coverage on a fresh toy aggregate.

ExecPlan: docs/plans/52-zero-enumeration-deriveaggregatectorsall-derivewirectorsall-and-fused-deriveaggregate-th-splices.md
Intention: intention_01ks7zzzdkepyad2dzecejffj6
```


## Validation and Acceptance

The change is validated by behavior, not just compilation:

1. Unit behavior (M1/M2). In `test/Keiki/Generics/THSpec.hs`, the auto-enumerated and
   fused splices generate identifiers that are then exercised: `icName inCtorMakeWidget`
   returns `"MakeWidget"` (proving the splice discovered the constructor and used its name
   as the suffix); `icMatch`/`! #field` round-trips a payload into the register file;
   `evalTerm (inp… #field)` reads a field; `evalPred is…` agrees with constructor identity
   for both record-payload and singleton commands; and on the event side `wcName` returns
   the constructor name while `wcBuild` reconstructs the event value from its `FieldsOf`
   payload. These assertions would fail to even compile if the splices did not generate
   the expected identifiers, and would fail at runtime if they generated wrong behavior.

2. Equivalence on a real aggregate (M3). The `jitsurei-test` suite is run unchanged after
   migrating `OrderCart` to the fused splice. Because that module's `KnownInCtors
   OrderCmd` instance and its edge-builder code reference the generated names
   (`inCtorAddItem`, `wireItemAdded`, `ItemAddedTermFields`, ...) directly, a passing
   suite with no test edits proves the fused splice produces the same names and behavior
   as the two enumerated splices it replaced.

3. Documentation and changelog (M4). `docs/guide/user-guide.md` gains a subsection naming
   the three new identifiers with their exact signatures so a reader can choose the right
   form; `docs/foundations/06-where-to-go-next.md` and `docs/guide/ast-drop-down.md` name
   the new splices; and `CHANGELOG.md` gains an `[Unreleased]` `### Added` entry so the
   teams already depending on `keiki` are told about the new public surface. No file under
   `docs/research/`, `docs/masterplans/`, or `docs/plans/` (other than this plan) is
   edited, preserving the historical record.

Acceptance is met when, from the repository root, `cabal test all` is green and the new
`THSpec.hs` examples cover: a record-payload command, a singleton command, a
record-payload event, a singleton event (all via `*All`), and a fused command+event
aggregate.


## Idempotence and Recovery

All edits are additive to `src/Keiki/Generics/TH.hs` and `test/Keiki/Generics/THSpec.hs`
(M1/M2) plus a localized, name-preserving change to one example module (M3) and additive
edits to a handful of living docs and `CHANGELOG.md` (M4). Re-running the `cabal` commands
is safe and repeatable; they rebuild only what changed. The doc and changelog edits are
plain Markdown additions with no build effect. There is no migration, no generated
artifact on disk, and no destructive operation.

If M3 causes any compile error in `jitsurei` (for example, a constructor in `OrderCmd`
turns out to be a singleton you did not expect, or a name is referenced that the migration
did not preserve), the fix is local: either keep that one type on its enumerated splice,
or correct the reference. To roll back M3 entirely, restore the two original splices and
the original import line in `jitsurei/src/Jitsurei/OrderCart.hs` with `git checkout --
jitsurei/src/Jitsurei/OrderCart.hs`; M1 and M2 (the library additions) are independent and
remain valid.

If the toy types added to `THSpec.hs` collide with existing generated names, rename the
toy constructors — collisions can only arise from a duplicated constructor name across the
toy types in that single module, which renaming resolves.


## Interfaces and Dependencies

No new library dependencies. The work uses only `Language.Haskell.TH` (already imported in
`src/Keiki/Generics/TH.hs` at line 52) and the existing internal generators in that
module.

By the end of M1, `Keiki.Generics.TH` exports two new functions with these signatures:

```haskell
deriveAggregateCtorsAll :: Name -> Name -> Q [Dec]
deriveWireCtorsAll      :: Name -> Q [Dec]
```

By the end of M2, it additionally exports:

```haskell
deriveAggregate :: Name -> Name -> Name -> Q [Dec]
```

Existing exports `deriveAggregateCtors`, `deriveWireCtors`, and `deriveView` are unchanged.
The test module `test/Keiki/Generics/THSpec.hs` depends on `Keiki.Core` (for `InCtor`,
`WireCtor`, `RegFile`, `evalTerm`, `evalPred`, the `icName`/`icMatch`/`wcName`/`wcBuild`
accessors, and the `!`/`#field` register read operators), `Keiki.Generics` (instances),
and `Keiki.Generics.TH` (the splices) — all already in scope in that module. The migrated
example `jitsurei/src/Jitsurei/OrderCart.hs` depends on `Keiki.Generics.TH (deriveAggregate)`
after M3, replacing its dependency on `deriveAggregateCtors`/`deriveWireCtors`.


## Revision History

- 2026-05-22 — Expanded Milestone 4 from "documentation" to "documentation and changelog"
  at the user's request to (a) make sure all relevant living docs are updated and (b)
  announce the change to downstream teams now that `keiki` is consumed by other teams.
  Discovered that a root `CHANGELOG.md` already exists (Keep a Changelog format, wired into
  `keiki.cabal` `extra-doc-files`), so the plan now extends it under `[Unreleased]` rather
  than creating a new file. Broadened the doc scope beyond `docs/guide/user-guide.md` to
  also touch `docs/foundations/06-where-to-go-next.md` and `docs/guide/ast-drop-down.md`,
  and added an explicit prohibition on editing the historical `docs/research/`,
  `docs/masterplans/`, and `docs/plans/` records. Reflected the change across Purpose,
  Progress, Decision Log (four new decisions, including no PVP version bump while 0.1.0.0
  is unreleased), Context and Orientation, Plan of Work (M4), Concrete Steps, Validation
  and Acceptance, and Idempotence and Recovery.
