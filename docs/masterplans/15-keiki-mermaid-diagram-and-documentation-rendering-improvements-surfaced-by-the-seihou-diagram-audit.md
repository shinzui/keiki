---
id: 15
slug: keiki-mermaid-diagram-and-documentation-rendering-improvements-surfaced-by-the-seihou-diagram-audit
title: "Keiki Mermaid diagram and documentation-rendering improvements surfaced by the keiro-runtime-jitsurei diagram audit"
kind: master-plan
created_at: 2026-06-06T15:47:26Z
intention: "intention_01ktes9wvkekw8nbb69st0naj8"
---

# Keiki Mermaid diagram and documentation-rendering improvements surfaced by the keiro-runtime-jitsurei diagram audit

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Vision & Scope

The **keiro-runtime-jitsurei** consumer (the disaster-response runtime at
`../keiro-runtime-jitsurei`, with Incident Command and Hospital Capacity services) generates
Mermaid diagrams from its service-owned keiki transducers into a checked-in
`docs/diagrams/keiki.md`. The diagrams are structurally correct as
a topology snapshot (states, command and event constructors, initial and final states), but the
keiro-runtime-jitsurei team found them weak as *explanatory* material and wrote up eight diagram-renderer
improvements in `../keiro-runtime-jitsurei/docs/keiki-diagram-feature-requirements.md`. This
MasterPlan addresses all eight. It is a sibling to MasterPlan 14 (which addresses the *DSL/codec*
requirements from the same audit team); this one is scoped entirely to the diagram and
documentation-rendering surface that lives under `src/Keiki/Render/`.

Every requirement was validated against keiki's actual code before planning, because the
requirements were authored by a different team working from the rendered output rather than the
AST. The validation (recorded in the Decision Log) found all eight feasible and appropriate for
keiki — keiki already owns the renderer module `src/Keiki/Render/Mermaid.hs`, including the
document-assembly helper `toMermaidAtlas` — but five requirements rest on assumptions that do not
hold against the type definitions and required adjustment. Those adjustments are baked into the
child plans.

After this MasterPlan is complete:

- A diagram author can render guards in **domain-readable** form (`MermaidGuardPretty`) instead of
  the structural constructor walk (`PAnd PInCtor PEq`) that the renderer emits today. A new pure
  pretty-printer for keiki's predicate/term ASTs (`HsPred`, `Term`, `Update`) renders constructor
  names, register reads by slot name, input-field reads by field name, equality, ordering,
  arithmetic, and boolean structure — clearly marking the two things that are *provably*
  unprintable: applied opaque functions (`<fn>(...)`) and literal *values* (`<lit>` at baseline,
  because `Term` literals carry no `Show`; optionally `<lit::T>` — the type name only — within the
  `PEq`/`PCmp` arms where a `Typeable` instance is in scope). (Req 1)
- An audit or documentation reader can call `renderEdgeInspector` to get a deterministic Markdown
  block — edges grouped by source state, each showing source, target, edge index, input
  constructor, output constructor(s), structural and/or pretty guard, and written slots — instead
  of cramming everything into a state-diagram label. (Req 3)
- A caller can switch dense edge labels to a multi-line layout (`<br/>`-separated) and truncate
  long written-slot lists with a deterministic `+N more` suffix, and can choose how multi-event
  outputs render (semicolon, one-per-line, or counted). (Reqs 2 and 8)
- A caller can supply stable ASCII Mermaid identifiers separate from friendly display labels via
  `toMermaidWithLabels`, instead of being forced to use `Show s` for both. (Req 7)
- A downstream project can assemble many diagrams into one document with typed sections
  (`toMermaidAtlasWith` / `MermaidSection` / `MermaidSectionKind`, distinguishing aggregate,
  process-manager, and workflow diagrams) and can replace a marked block inside an existing
  Markdown file with `replaceMarkdownDiagramBlock`, instead of hand-rolling marker glue in each
  service. (Reqs 4 and 5)
- A downstream unit test can call pure `validateMermaidDiagram` / `validateMermaidAtlas` helpers
  that return structured warnings (missing `stateDiagram-v2`, empty diagram, over-length labels,
  duplicate state IDs, suspicious unescaped characters) — heuristic checks, not a full Mermaid
  parser. (Req 6)

**The load-bearing invariant for every plan here:** the default `toMermaid` / `toMermaidWith
defaultMermaidOptions` output, and the existing golden tests in
`test/Keiki/Render/MermaidSpec.hs`, must remain **byte-identical**. All new behavior is opt-in.
This is why the `MermaidOptions` record is extended *additively* (new fields defaulted to current
behavior, `showGuardSummary` preserved) rather than redesigned as the audit literally proposed
(see Decision Log).

**Explicitly out of scope:**

- Any change to keiki's core formalism (`Term`/`HsPred`/`Update`/`SymTransducer` in
  `src/Keiki/Core.hs`). Every plan here is read-only with respect to the ASTs: the pretty-printer
  and inspectors *consume* the existing structure. No constructor is added, removed, or changed.
- Adding a real Mermaid parser. Req 6's validation is structural heuristics over the rendered
  `Text`, not parsing (see Decision Log).
- Generating the process-manager diagrams *into keiro-runtime-jitsurei's document*. Keiki's deliverable for Req 4
  is the atlas/section vocabulary; wiring keiro-runtime-jitsurei's process managers into its own
  `docs/diagrams/keiki.md` is downstream work in the `keiro-runtime-jitsurei` repo (the
  requirement itself acknowledges this is "partly a downstream documentation gap").
- Adding any dependency to `keiki.cabal` beyond what the renderer already uses (`text`,
  `containers`). The pretty-printer and validation helpers are written by hand against `text`.


## Decomposition Strategy

The eight requirements were grouped by functional concern into six child plans, following the same
principles MasterPlans 13 and 14 used: each stream produces an independently verifiable behavior,
cross-plan coupling is minimized, and natural ordering (a consumed artifact precedes its
consumers) is respected. The grouping deliberately tracks the keiro-runtime-jitsurei team's own priority
recommendation, which puts the pretty-printer first, the inspector second, and the
label/layout/atlas/validation work after.

- **EP-61 (pretty-printer + readable guards, Req 1)** is the foundation. It adds a new pure module
  `src/Keiki/Render/Pretty.hs` that turns `HsPred`/`Term`/`Update` values into domain-readable
  `Text`, plus the `indexName` helper that recovers a register/field slot name from an `Index`. It
  then wires a `MermaidGuardMode` (`Hidden` / `StructuralSummary` / `Pretty`) into
  `toMermaidWith`. It goes first because both EP-62 (inspector) and EP-63 (multiline guard
  rendering) reuse the same pretty-printer; defining it once keeps the readable-guard vocabulary
  identical across the topology renderer and the inspector.
- **EP-62 (edge inspector, Req 3)** adds `renderEdgeInspector` + `EdgeInspectorOptions` producing
  Markdown grouped by source state. It is a separate stream from EP-61 because it is a different
  output surface (Markdown detail block, not a Mermaid label) with its own acceptance, but it soft
  depends on EP-61 so its `includePrettyGuard` option reuses `Keiki.Render.Pretty` rather than
  duplicating it.
- **EP-63 (label & output layout, Reqs 2 + 8)** bundles multiline edge labels (Req 2) and
  multi-event output layout (Req 8) because both extend the same `MermaidOptions` record and both
  modify the same edge-label assembly function (`edgeLabelWith` / `edgeOutputName` in
  `src/Keiki/Render/Mermaid.hs`). Splitting them would have two plans editing the same function in
  the same release. It soft depends on EP-61 because multiline *pretty* guard rendering reuses the
  pretty-printer.
- **EP-64 (stable state IDs, Req 7)** adds `MermaidStateLabels` + `toMermaidWithLabels`, touching
  the vertex-label/identifier generation in the topology renderer. It is independent of the
  label-content plans.
- **EP-65 (atlas sections + marker replacement, Reqs 4 + 5)** is the document-assembly stream:
  the typed-section atlas (`toMermaidAtlasWith`) and the generic Markdown marker-replacement helper
  (`replaceMarkdownDiagramBlock`, in a new `src/Keiki/Render/Markdown.hs`). Both are about
  assembling rendered diagrams into a Markdown document; grouping them keeps the
  regenerate-a-doc toolkit in one stream. Independent of the label-rendering streams.
- **EP-66 (validation helpers, Req 6)** adds pure `validateMermaidDiagram` / `validateMermaidAtlas`
  returning structured warnings. It mirrors the `validateTransducer` pure-warnings pattern from
  MasterPlan 14's EP-56 (a deliberate house style). It soft depends on EP-64 so the
  duplicate-state-ID warning and EP-64's duplicate-ID detection agree on what a "duplicate ID"
  means.

Principles applied: each stream is verifiable by its own golden/unit test; coupling is minimal
(EP-61's pretty module is the one widely shared artifact; the `MermaidOptions` record is the one
widely touched type); ordering is respected (the pretty-printer precedes its two consumers). The
four streams with no consumed-artifact dependency (EP-61, EP-64, EP-65, EP-66) form Phase 1 and
parallelize; EP-62 and EP-63 form Phase 2 behind EP-61.

Alternatives considered and rejected: (1) Making the pretty-printer its own micro-plan separate
from the Req 1 guard-mode wiring — rejected because the guard-mode wiring is small once the printer
exists, and keeping them together makes EP-61 a substantial, self-contained foundation rather than
two thin plans. (2) Splitting Req 2 (multiline labels) and Req 8 (output layout) into separate
plans — rejected because they edit the same function and the same record. (3) Redesigning
`MermaidOptions` to drop `showGuardSummary` exactly as the audit wrote it — rejected on
byte-identity grounds (see Decision Log); the additive path preserves every existing caller and
golden test. (4) Treating Req 5 (marker replacement) and Req 6 (validation) as out-of-keiki generic
utilities — considered because neither references a keiki type, but rejected because keiki already
owns the render-to-Mermaid and `toMermaidAtlas` doc-assembly surface, so the `Keiki.Render.*`
namespace is their natural home.


## Exec-Plan Registry

| #  | Title | Path | Hard Deps | Soft Deps | Status |
|----|-------|------|-----------|-----------|--------|
| 61 | Pretty-printer for HsPred/Term/Update and domain-readable Mermaid guard rendering | docs/plans/61-pretty-printer-for-hspred-term-update-and-domain-readable-mermaid-guard-rendering.md | None | None | Complete |
| 62 | Edge inspector Markdown renderer for SymTransducer | docs/plans/62-edge-inspector-markdown-renderer-for-symtransducer.md | None | EP-61 | Complete |
| 63 | Multiline Mermaid edge labels and multi-event output layout controls | docs/plans/63-multiline-mermaid-edge-labels-and-multi-event-output-layout-controls.md | None | EP-61 | Complete |
| 64 | Stable human-friendly Mermaid state IDs and display labels | docs/plans/64-stable-human-friendly-mermaid-state-ids-and-display-labels.md | None | None | Complete |
| 65 | Mermaid diagram atlas sections and Markdown marker replacement helper | docs/plans/65-mermaid-diagram-atlas-sections-and-markdown-marker-replacement-helper.md | None | None | Complete |
| 66 | Pure Mermaid diagram and atlas validation helpers | docs/plans/66-pure-mermaid-diagram-and-atlas-validation-helpers.md | None | EP-64 | Complete |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix (e.g., EP-61).


## Dependency Graph

There are no hard dependencies: every plan compiles and is verifiable on its own. Ordering is
governed by three soft dependencies.

EP-62 and EP-63 soft-depend on EP-61. EP-61 introduces `src/Keiki/Render/Pretty.hs`, exporting
`prettyPred :: HsPred rs ci -> Text`, `prettyTerm`, `prettyUpdate`, and the `indexName :: Index rs
r -> String` helper. EP-62's `includePrettyGuard` option and EP-63's multiline *pretty* guard
rendering both want readable guard text. Doing EP-61 first means they reuse one pretty-printer with
identical output. If either is taken before EP-61, it must render structural-only guard text and
add the pretty rendering once EP-61 lands; the child plans note this fallback.

EP-66 soft-depends on EP-64. EP-64 lets callers supply stable Mermaid state identifiers; EP-66's
validation detects duplicate state IDs. The two must agree on what an "ID" is (the ASCII token
before a state's display label in the rendered diagram). Doing EP-64 first means EP-66 validates
exactly what EP-64 emits. If EP-66 is taken first, it defines duplicate-ID detection over the
`Show s`-derived identifiers the renderer emits today, and EP-64 conforms to it.

EP-64 and EP-65 are independent of every other plan and can be done at any time.

Recommended waves: **Phase 1** — EP-61, EP-64, EP-65, EP-66 in parallel (EP-66 ideally after
EP-64, but it can start independently). **Phase 2** — EP-62 and EP-63, after EP-61.


## Integration Points

- **The `MermaidOptions` record and `edgeLabelWith` in `src/Keiki/Render/Mermaid.hs`.** Involved:
  EP-61 (adds `guardMode`), EP-63 (adds `labelLayout`, `maxInlineWrittenSlots`,
  `maxInlineGuardWidth`, and an output-layout field). The shared rule, owned jointly, is that
  `MermaidOptions` is extended *additively*: every new field has a default in
  `defaultMermaidOptions` that reproduces today's behavior, and the existing `showWrittenSlots` /
  `showGuardSummary` fields stay. EP-61 must keep `showGuardSummary = True` rendering the exact
  structural summary it renders today (so the existing golden test passes) while introducing
  `guardMode`; the two are reconciled by treating `showGuardSummary` as the legacy spelling of
  `guardMode = MermaidGuardStructuralSummary` (EP-61 documents the precedence). EP-63 adds its
  fields after EP-61's, never reordering. Both plans modify `edgeLabelWith`; EP-61 changes how the
  guard segment is produced, EP-63 changes how segments are laid out (inline vs multiline) and how
  the output segment is produced. They must not clobber each other: EP-61 routes guard text through
  a single `renderGuardSegment opts` helper, and EP-63 wraps the *assembly* of segments, leaving
  EP-61's guard-text production intact.

- **The `src/Keiki/Render/Pretty.hs` module.** Involved: EP-61 (defines), EP-62 and EP-63
  (consume). The shared artifact is the pretty-printer API: `prettyPred :: HsPred rs ci -> Text`,
  `prettyTerm :: Term rs ci ifs r -> Text`, `prettyUpdate :: Update rs w ci -> Text`, and
  `indexName :: Index rs r -> String`. EP-61 owns the module and its export list and the rules for
  rendering opaque pieces (`<fn>(...)` for `TApp1`/`TApp2`, `<lit::T>` for `TLit` via the
  `Typeable` `TypeRep`, `<lit>` where no `Typeable` is available). EP-62 and EP-63 import these and
  must not re-implement guard prettifying.

- **State-identifier generation and duplicate-ID semantics.** Involved: EP-64 (emits IDs via
  `MermaidStateLabels.stateId`), EP-66 (validates duplicate IDs). The shared concept is the Mermaid
  state identifier: the ASCII token keiki emits for a vertex (today derived from `Show s` in
  `vertexLabel`; under EP-64, from the caller's `stateId` callback). EP-66's
  `MermaidValidationWarning` for duplicate IDs must key off the same token EP-64 produces. EP-64
  owns the identifier-generation change; EP-66 owns the validation. EP-64's acceptance criterion
  "duplicate generated IDs fail with a clear validation warning" is satisfied by EP-66's check, so
  EP-64 should reference EP-66's warning type if EP-66 is done first, or define a minimal local
  check if not.

- **The existing golden tests in `test/Keiki/Render/MermaidSpec.hs`.** Involved: every plan that
  touches the renderer (EP-61, EP-63, EP-64). The shared constraint is byte-identity of the default
  output: none of these plans may change the bytes that `toMermaid` / `toMermaidWith
  defaultMermaidOptions` / `toMermaidAtlas` produce for the existing fixtures. Each plan adds *new*
  golden cases for its opt-in behavior and must run the full spec to confirm the pre-existing
  goldens are untouched.


## Progress

Track milestone-level progress across all child plans. Each entry names the child plan and the
milestone. Milestones are seeded top-down here for coordination; each child plan owns the
authoritative, detailed version.

- [x] EP-61 M1: `src/Keiki/Render/Pretty.hs` with `prettyPred`/`prettyTerm`/`prettyUpdate` + `indexName`; pure unit tests covering slot reads, input-field reads, comparisons, arithmetic, boolean structure, opaque `<fn>(...)` and `<lit>` markers. (2026-06-06)
- [x] EP-61 M2: `MermaidGuardMode` (`Hidden`/`StructuralSummary`/`Pretty`) added to `MermaidOptions`; `showGuardSummary` reconciled as the legacy spelling; default output byte-identical; new golden for `MermaidGuardPretty`. (2026-06-06)
- [x] EP-62 M1: `renderEdgeInspector` + `EdgeInspectorOptions` Markdown renderer grouped by source state; deterministic, golden-tested. (2026-06-06)
- [x] EP-62 M2: structural-and-pretty guard option, output-field term rendering (positional, field-name-free per validation), written-slot listing; golden cases. (2026-06-06)
- [x] EP-63 M1: `MermaidLabelLayout` + `maxInlineWrittenSlots`/`maxInlineGuardWidth` added additively; multiline `<br/>` labels with deterministic `+N more` truncation; default byte-identical. (2026-06-06)
- [x] EP-63 M2: `MermaidOutputLayout` (`Semicolon`/`Multiline`/`Counted`); default reproduces current length-based behavior; golden cases. (2026-06-06)
- [x] EP-64 M1: `MermaidStateLabels` + `toMermaidWithLabels`; stable ASCII IDs with friendly display labels; default rendering still `Show s`; golden cases. (2026-06-06)
- [x] EP-64 M2: pure total `duplicateStateIds` (AST-level duplicate-ID check, the shared-id contract for EP-66); colliding + clean unit tests. (2026-06-06)
- [x] EP-65 M1: `MermaidSection` + `MermaidSectionKind` + `toMermaidAtlasWith` (typed sections, stable section IDs); default `toMermaidAtlas` byte-identical. (2026-06-06)
- [x] EP-65 M2: `src/Keiki/Render/Markdown.hs` with `replaceMarkdownDiagramBlock` + `MarkdownDiagramBlock`/`MarkdownDiagramError`; begin/end/duplicate-marker errors; content-preservation tests. (2026-06-06)
- [x] EP-66 M1: `validateMermaidDiagram` + `MermaidValidationOptions`/`MermaidValidationWarning` (missing header, empty, over-length labels, suspicious unescaped chars). (2026-06-06)
- [x] EP-66 M2: duplicate-state-ID detection (aligned with EP-64) + `validateMermaidAtlas`; pure unit tests. (2026-06-06)


## Surprises & Discoveries

Document cross-plan insights, dependency changes, scope adjustments, or unexpected interactions
between child plans. Provide concise evidence.

- `Term` literals are not `Show`able. `TLit :: r -> Term rs ci ifs r` carries an *unconstrained*
  `r` (verified at `src/Keiki/Core.hs:306-339`), and `PEq`/`PCmp` constrain their operands to
  `(Eq r, Typeable r)` / `(Ord r, Typeable r)` only — no `Show` (`Core.hs:544-574`). So the
  pretty-printer (EP-61) can render predicate/term *structure* and slot/field *names*, but a
  literal value renders as `<lit>` at baseline (and at most `<lit::T>`, the `Typeable` type name,
  within the `PEq`/`PCmp` arms where `Typeable` is in scope), never its value. This bounds Req 1's
  "`PEq` renders as `<left> == <right>`": the shape renders, the literal value does not.
- Register/field slot names ARE recoverable from any `Index`. `Index`'s head constructor `ZIdx ::
  KnownSymbol s => Index ('(s,r)':rs) r` carries the slot's `KnownSymbol` (`Core.hs:210-212`), so a
  recursive `indexName` (walk `SIdx` to the `ZIdx`, return `symbolVal`) recovers it with no extra
  class constraint. EP-61 adds this; it is the enabler for "register reads render by slot name".
- `WireCtor` has no field names. `WireCtor` carries only `wcName :: String`, `wcMatch`, `wcBuild`
  (`Core.hs:478-482`) — there is no list of output-field names. So EP-62's `includeOutputFields`
  can pretty-print each output field's *term* positionally but cannot label fields by name. The
  keiro-runtime-jitsurei team's Req 3 assumed otherwise.
- The current multi-event output default is NOT pure-semicolon. `edgeOutputName`
  (`Mermaid.hs:595-604`) emits `;` for exactly two events and `<br/>` for three or more
  (length-based). Req 8's claim that "default semicolon output remains unchanged" only holds if
  `MermaidOutputSemicolon` is defined to reproduce this exact length-based behavior, which EP-63
  does.
- `Edge`'s write-set `w` is existentially quantified (`Core.hs:654-661`), so the `update` record
  selector cannot be used as a function (GHC-55876, also recorded in MasterPlans 13 and 14). Every
  plan that walks an edge's update (EP-61's `prettyUpdate` call sites, EP-62's written-slot
  listing) must pattern-match the `Edge` constructor, never apply `update` as a selector. The
  existing `edgeLabelWith` already does this (`Mermaid.hs:622`, `Edge { update = u, guard = g }`).
- **Adding a field to `MermaidOptions` is byte-identical for output and for record-*update*
  callers, but breaks full record-*literal* constructors at run time** (discovered in EP-61 M2).
  The existing annotated-golden test built `MermaidOptions { showWrittenSlots = True,
  showGuardSummary = True }` as a full literal; once EP-61 added `guardMode`, GHC only *warns*
  (`-Wmissing-fields`, no `-Werror` here) and leaves `guardMode` as a bottom thunk that explodes
  with a `RecConError` the moment `renderGuardSegment` forces it. The fix is to construct options
  via record-update on `defaultMermaidOptions` (`defaultMermaidOptions { … }`); the pinned golden
  *text* is unchanged, so byte-identity holds. **This directly affects EP-63**, which also appends
  `MermaidOptions` fields (`labelLayout`, `maxInlineWrittenSlots`, `maxInlineGuardWidth`,
  output-layout): EP-63 must (a) append after `guardMode`, never reorder; (b) default each new
  field in `defaultMermaidOptions`; and (c) ensure any test or downstream caller that constructs
  `MermaidOptions` uses record-update on `defaultMermaidOptions`, not a full record literal. The
  Integration Points "extend additively" rule should be read as "extend additively **and**
  construct via record-update on `defaultMermaidOptions`." The downstream keiro-runtime-jitsurei consumer must do
  the same for any full-literal `MermaidOptions` it builds.
- **EP-63 landed after EP-61, so `MermaidOptions`'s field order is now fixed as**
  `showWrittenSlots`, `showGuardSummary`, `guardMode` (EP-61), `labelLayout`,
  `maxInlineWrittenSlots`, `maxInlineGuardWidth`, `outputLayout` (EP-63). Any later plan that
  extends the record (none of the remaining Phase-1 plans do — EP-64 adds the separate
  `MermaidStateLabels`/`toMermaidWithLabels`, EP-65/EP-66 add their own types) must append after
  `outputLayout`, default the new field in `defaultMermaidOptions`, and construct test/consumer
  values via record-update on `defaultMermaidOptions`. EP-63 added six goldens
  (`test/Keiki/Render/MermaidSpec.hs`) and the suite is green at 352 examples with every
  pre-existing renderer golden byte-identical, re-confirming the load-bearing invariant.


- **EP-65 landed; the atlas/marker surface is the input shape EP-66 validates.** EP-65 added
  `toMermaidAtlasWith` (typed `MermaidSection`/`MermaidSectionKind`/`MermaidAtlasOptions`/
  `AtlasKindDisplay` in `src/Keiki/Render/Mermaid.hs`) and the new `src/Keiki/Render/Markdown.hs`
  (`replaceMarkdownDiagramBlock`). `toMermaidAtlas` is now a thin wrapper over
  `toMermaidAtlasWith defaultMermaidAtlasOptions`; the pre-existing `atlasCanonical` golden is
  byte-identical, re-confirming the load-bearing invariant. The full suite is green at **364
  examples** (was 357 after EP-64). **Note for EP-66:** the document `toMermaidAtlasWith` produces
  — `## {title}` headings, fenced ```` ```mermaid ```` blocks, optional `<!-- ns: id begin/end -->`
  markers — is exactly the `Text` shape `validateMermaidAtlas` inspects. EP-66 is *not* a dependency
  of EP-65 in either direction (neither imports the other), but EP-66's atlas-level heuristics
  should be written against this concrete output (per-section fenced blocks joined by a blank line).
- **`MultiWayIf` is not in the GHC2024 default set** and keiki's `shared-extensions` cabal stanza
  does not enable it. `src/Keiki/Render/Markdown.hs` therefore carries a per-module
  `{-# LANGUAGE MultiWayIf #-}` pragma for its four-way marker-count validation. Any later plan that
  wants `if | … ` in a new module must add the pragma itself; the project does not enable it
  globally.
- **EP-66 landed; MasterPlan 15 is complete (all six plans).** EP-66 added the pure
  `src/Keiki/Render/Validate.hs` (`validateMermaidDiagram`/`validateMermaidAtlas`,
  `MermaidValidationOptions`, `MermaidValidationWarning`). Its duplicate-state-ID check keys off
  exactly the `state "<display>" as <id>` declaration lines EP-64's `toMermaidWithLabels` emits and
  ignores endpoint recurrence — the shared-id contract held with no rework because EP-64 was done
  first (the soft dependency paid off as planned). Two cross-plan notes for any downstream/future
  work: (1) `MermaidValidationWarning`'s per-constructor record fields trip `-Wpartial-fields`;
  this is *accepted, not suppressed*, matching EP-56's `TransducerValidationWarning`
  (`src/Keiki/Core.hs:1608`), which uses the same sum-of-records shape — the house style is to
  tolerate the warning in exchange for `shouldBe`-assertable warnings. (2) The suspicious-char check
  emits one warning per denylisted `Char` and exempts the literal `<br/>` substring; a fixture like
  `Cmd / "quoted"` yields *two* warnings, not one. Final suite state: **372 examples, 0 failures**,
  every pre-existing renderer/atlas golden byte-identical.


## Decision Log

- Decision: Create this as a new MasterPlan (15), separate from MasterPlan 14.
  Rationale: MasterPlan 14 is scoped to the *DSL/codec* requirements from the keiro-runtime-jitsurei audit
  (`keiki-dsl-feature-requirements.md`: `stepEither`, `validateTransducer`, TH, operators, codec,
  collections). This work addresses a *separate* requirements file
  (`keiki-diagram-feature-requirements.md`), a *separate* concern (diagram and documentation
  rendering under `src/Keiki/Render/`), and a *separate* intention
  (`intention_01ktes9wvkekw8nbb69st0naj8` vs MasterPlan 14's `intention_01ktensqv9ecmv5cd5jrbcfej7`).
  Date: 2026-06-06

- Decision: Validate all eight requirements against the actual ASTs before planning, because they
  were authored by the keiro-runtime-jitsurei team from rendered output. Verdict: all eight feasible and
  keiki-appropriate; five need adjustment (recorded as Surprises). Adjustments: (1) literal values
  render opaquely as `<lit>` at baseline (`<lit::T>` only where `Typeable` is in scope) (Req 1); (2) `MermaidOptions` extended additively, not redesigned
  (Reqs 1/2/8); (3) `MermaidOutputSemicolon` reproduces the current length-based `;`/`<br/>`
  behavior, not pure semicolon (Req 8); (4) output fields render positionally without field names
  (Req 3); (5) validation is structural heuristics, not Mermaid parsing (Req 6).
  Date: 2026-06-06

- Decision: Scope the MasterPlan to all eight requirements as six child plans (EP-61..EP-66).
  Rationale: the user confirmed full scope after reviewing the validation; all eight land in the
  `Keiki.Render.*` namespace that keiki already owns.
  Date: 2026-06-06

- Decision: Evolve `MermaidOptions` additively, preserving byte-identity, rather than redesigning
  the record as the audit literally wrote it (which drops `showGuardSummary :: Bool` in favor of
  `guardMode :: MermaidGuardMode`).
  Rationale: the user chose the additive path. There is a golden byte-identity test in
  `test/Keiki/Render/MermaidSpec.hs` and existing callers (in tests and in keiro-runtime-jitsurei) that construct
  `MermaidOptions` by field name. Keeping `defaultMermaidOptions` byte-identical and treating
  `showGuardSummary` as the legacy spelling of `guardMode = MermaidGuardStructuralSummary` honors
  each requirement's own "default remains unchanged" acceptance criterion while avoiding a breaking
  migration. Should a clean redesign be wanted later, it is a separate, deliberate breaking change.
  Date: 2026-06-06

- Decision: Make the pretty-printer (`src/Keiki/Render/Pretty.hs`, EP-61) a shared foundation
  consumed by the inspector (EP-62) and the multiline label renderer (EP-63), rather than letting
  each define its own.
  Rationale: the keiro-runtime-jitsurei team's own priority recommendation puts "structural pretty-printers" first
  and the inspector/guard-mode after; one printer keeps readable-guard output identical across the
  topology renderer and the inspector. EP-62/EP-63 soft-depend on EP-61 for this reason.
  Date: 2026-06-06

- Decision: Group Req 2 (multiline labels) with Req 8 (output layout) as EP-63, and Req 4 (atlas
  sections) with Req 5 (marker replacement) as EP-65.
  Rationale: Req 2 and Req 8 edit the same record (`MermaidOptions`) and the same function
  (`edgeLabelWith`/`edgeOutputName`); Req 4 and Req 5 are both document-assembly concerns. Grouping
  avoids two plans editing the same code in the same release and keeps cohesive surfaces together.
  Date: 2026-06-06

- Decision: Keep Req 5 (marker replacement) and Req 6 (validation) inside keiki rather than treating
  them as generic out-of-repo utilities.
  Rationale: although neither references a keiki type, keiki already owns the render-to-Mermaid and
  `toMermaidAtlas` document-assembly surface, so `Keiki.Render.Markdown` (Req 5) and the validation
  helpers (Req 6) belong in the same `Keiki.Render.*` namespace. Req 6 also mirrors the
  `validateTransducer` pure-warnings house style from MasterPlan 14's EP-56.
  Date: 2026-06-06

- Decision: Correct the consumer's name throughout this MasterPlan and its child plans from
  "Seihou" to **keiro-runtime-jitsurei** (the disaster-response runtime at
  `../keiro-runtime-jitsurei`).
  Rationale: "Seihou" is the name of the *planning toolkit* (the `seihou:` master-plan /
  exec-plan skills), not the consumer; it was mistakenly applied as the consumer's name when this
  MasterPlan was authored. The actual consumer that drove the diagram audit is
  keiro-runtime-jitsurei. Prose, title, and heading are corrected here and in EP-61/EP-62/EP-65/EP-66
  (EP-63/EP-64 had no occurrences); the file slug/filename is left unchanged to keep the child
  plans' `master_plan:` frontmatter links and prior commits' `MasterPlan:` git trailers (which
  reference the original path) valid. The lowercase `seihou:` skill markers are untouched. This
  mirrors the same correction made to MasterPlan 14.
  Date: 2026-06-06


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion. Compare the
result against the original vision.

**Complete.** All eight keiro-runtime-jitsurei diagram-audit requirements shipped across six child plans
(EP-61..EP-66), every one of which is Complete. The full test suite is green at **372 examples, 0
failures**, and every pre-existing renderer/atlas golden in `test/Keiki/Render/MermaidSpec.hs` is
byte-identical — the load-bearing invariant ("default `toMermaid`/`toMermaidWith
defaultMermaidOptions`/`toMermaidAtlas` output unchanged; all new behavior opt-in") held end to
end.

What now exists that did not before, mapped to the vision:

- **Readable guards (Req 1, EP-61):** `src/Keiki/Render/Pretty.hs` (`prettyPred`/`prettyTerm`/
  `prettyUpdate` + `indexName`) and `MermaidGuardMode` (`Hidden`/`StructuralSummary`/`Pretty`) wired
  into `toMermaidWith`. Literal values render opaquely (`<lit>` / `<lit::T>`) exactly as the
  validation predicted.
- **Edge inspector (Req 3, EP-62):** `renderEdgeInspector` + `EdgeInspectorOptions` Markdown detail
  block grouped by source state; output fields render positionally (no field names, per validation).
- **Label & output layout (Reqs 2 + 8, EP-63):** multiline `<br/>` labels, `+N more` written-slot
  truncation, guard-width truncation, and `MermaidOutputLayout`
  (`Semicolon`/`Multiline`/`Counted`) — `Semicolon` reproduces the historical length-based default.
- **Stable state IDs (Req 7, EP-64):** `MermaidStateLabels` + `toMermaidWithLabels` (ASCII id vs.
  friendly display) and the total `duplicateStateIds` AST check.
- **Atlas sections + marker replacement (Reqs 4 + 5, EP-65):** typed `toMermaidAtlasWith`
  (`MermaidSection`/`MermaidSectionKind`/`AtlasKindDisplay`) and `src/Keiki/Render/Markdown.hs`'s
  `replaceMarkdownDiagramBlock`, which compose via `sectionId == blockId`.
- **Validation helpers (Req 6, EP-66):** pure `validateMermaidDiagram`/`validateMermaidAtlas`
  returning structured `MermaidValidationWarning`s — heuristics, not a parser.

Decomposition assessment: the planned ordering worked. EP-61's `Keiki.Render.Pretty` was the one
widely-shared artifact (consumed by EP-62 and EP-63) and defining it first kept readable-guard
output identical across surfaces. `MermaidOptions` was the one widely-touched type; the additive
discipline (append fields, default in `defaultMermaidOptions`, construct via record-update — see the
EP-61 M2 `RecConError` discovery) preserved byte-identity through EP-61 and EP-63. EP-64-before-EP-66
let the duplicate-id contract land with no rework. No child plan needed to be split, merged, or
cancelled.

Lessons / house-style reaffirmations captured in Surprises for future plans: (1) `MermaidOptions`
must be constructed via record-update on `defaultMermaidOptions`, never a full record literal, or a
new field becomes a `RecConError` bottom thunk. (2) `MultiWayIf` needs a per-module pragma (not in
GHC2024, not enabled globally). (3) Sum-of-records warning types trip `-Wpartial-fields` and the
house style is to tolerate it (matching `TransducerValidationWarning`) in exchange for assertable
warnings.

Gaps (all pre-declared out of scope, none surprising): wiring these renderer capabilities into
keiro-runtime-jitsurei's own `docs/diagrams/keiki.md` (process-manager diagrams, marker-based regeneration, a
validation test) is downstream work in `keiro-runtime-jitsurei`. Keiki's deliverable — the
vocabulary and the pure helpers — is done.
