---
id: 84
slug: preserve-readable-business-semantics-in-keiki-transducers-and-diagrams
title: "Preserve readable business semantics in Keiki transducers and diagrams"
kind: exec-plan
created_at: 2026-08-02T03:36:01Z
intention: "intention_01kz0chaggerxaswdydar94e3c"
mori_publish: true
---

# Preserve readable business semantics in Keiki transducers and diagrams

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Keiki's primary Mermaid renderer must communicate the business behavior of a
transducer, not merely its topology.  After this change, a reader can inspect the
diagram produced by `toMermaid` and see the command, source and target states,
guard expression, register assignments including their right-hand expressions,
and emitted event constructors.  Ordinary literal values are rendered as values
rather than as `<lit>`.  A deliberately compact, topology-only renderer remains
available as an explicit choice.

The change does not add a second source of executable behavior.  Ordinary literal
text is derived from the value's `Show` instance only when a renderer observes the
term; neither concrete execution nor proof code may call `show`.  Tests prove that
readable and display-opaque literals have identical evaluation, update, output,
replay, composition, validation, and symbolic-classification behavior.  The
visible proof is a golden diagram whose edge label contains complete guard and
update expressions, passes Keiki's heuristic Mermaid validator, and renders
through the repository's actual documentation backend.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] (2026-08-01) Validated the plan against the concrete evaluator, replay
  inversion, pure and SBV analyzers, composition/projection transforms, renderer
  variants, ADRs, release evidence, and supported toolchain; recorded the missing
  soundness and backend-escaping obligations without starting implementation.
- [x] (2026-08-01) Created a Keiki-specific intention through Mina and
  replaced the incorrect Keiro-owned intention in this plan's frontmatter.
- [x] (2026-08-02T14:43:53Z) Refreshed Mori ownership and dependent evidence,
  confirmed Hackage and upstream still expose `0.7.0.0`, selected GHC 9.12.4
  through `nix develop`, and captured the clean pre-change full-suite result:
  Keiki 626, codec 104, codec-test 13, and Jitsurei 122 examples, all passing.
- [x] (2026-08-02T14:43:53Z) Milestone 0: captured an EP-84 executable
  guarantee ledger that proves no-`Show` expressiveness and proves a deliberately
  throwing `Show` is not forced by evaluation, predicate comparison, register
  updates, event output, `solveOutput`, replay, or validation.  The strengthened
  full suite passed under GHC 9.12.4: Keiki 630, codec 104, codec-test 13, and
  Jitsurei 122 examples, all with zero failures.  Existing named tests continue
  to pin pure overlap, SBV verification, projection folding, composition,
  alternative/feedback/profunctor behavior, and every legacy topology golden.
- [x] (2026-08-02T14:53:21Z) Milestone 1: added `Show`-carrying `TLit`,
  display-opaque `TOpaqueLit`, and `opaqueLit`; updated every evaluator, replay
  inversion path, pure and SBV analyzer, structural walker, composition rewrite,
  profunctor rewrite, and pretty-printer.  The Keiki suite passed 638 examples
  after focused Core, Symbolic, Composition, Pretty, and Validation coverage
  proved all four readable/opaque proof pairings exact, no-`Show` execution,
  throwing-`Show` non-observation, projection-fold display loss without semantic
  opacity, and safe readable-literal retention through positional substitution.
- [x] (2026-08-02T15:13:30Z) Milestone 2: made readable guards, complete
  updates, multiline layout, and no semantic truncation the primary Mermaid
  policy; added explicit update modes, `toTopologyMermaid`, and options-aware
  routes for every shape.  All 0.7 topology goldens remain byte-exact under
  `topologyMermaidOptions`, while primary single, composite, nested,
  alternative, three-way, feedback, and labeled paths expose business
  semantics.  The special-character fixture passed the heuristic validator,
  exact `beautiful-mermaid` SVG assertions, the 170-page site build, and the
  exact no-`diagram-error` search.  The full suite passed: Keiki 643,
  codec 104, codec-test 13, and Jitsurei 127 examples, all with zero failures.
- [ ] Milestone 3: document the rendering contract, create the governing ADR, and
  update examples and migration guidance for the breaking API.
- [ ] Milestone 4: audit Mori dependents, release the coordinated Keiki packages as
  `0.8.0.0`, and publish the exact tag and registry evidence needed by downstreams.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- Discovery: Plan 61 deliberately rendered every `TLit` as `<lit>` because the
  constructor carried a value without a `Show` dictionary.  It also kept
  `toMermaid` topology-only and made readable guards opt-in.  This plan supersedes
  both product choices; it does not treat them as incidental bugs.
  Evidence: `docs/plans/61-pretty-printer-for-hspred-term-update-and-domain-readable-mermaid-guard-rendering.md`,
  `src/Keiki/Render/Pretty.hs`, and `src/Keiki/Render/Mermaid.hs`.
- Discovery: `prettyUpdate` already renders a complete `slot := expression`.
  Mermaid currently discards that information and emits, at most, the names of
  written slots.  The renderer can therefore share the existing pretty-printer
  instead of introducing diagram-specific semantics.
  Evidence: `src/Keiki/Render/Pretty.hs` and `edgeLabelWith` in
  `src/Keiki/Render/Mermaid.hs`.
- Discovery: Mori reports twelve registered project-level dependents of Keiki.
  Keiro is the downstream changed by the companion plan; the other dependents must
  be audited and recorded before release, not silently assumed compatible.
  Evidence: `mori registry dependents shinzui/keiki --packages`.
- Discovery: the authoritative current release is `0.7.0.0`: it is the version in
  `keiki.cabal`, the preferred Hackage release, and upstream tag `v0.7.0.0` peels to
  commit `7c5d433ef4455e9e626347f89cb3a416bad62e72`.  A structural `Term` API change
  therefore requires the `0.8` PVP line.
- Discovery: display opacity and symbolic opacity are different properties in the
  current implementation.  `TLit` is translated exactly with `symLit`, is excluded
  from `termHasOpaqueFallback`, and participates in the pure equality and ordering
  analyzer.  `TOpaqueLit` must retain every one of those behaviors; only
  `prettyTerm` may distinguish it from `TLit`.
  Evidence: `translateTermSym` and `termReportEvents` in
  `src/Keiki/Symbolic.hs`, and `termHasOpaqueFallback`, `pureEquality`, and
  `pureOrdering` in `src/Keiki/Core.hs`.
- Discovery: `projectThroughTermWithStatus` folds a projected literal owner into a
  literal result, but `FieldProjection` deliberately does not require
  `Show (FieldResult projection)`.  The fold must therefore produce
  `TOpaqueLit` without changing its `ProjectionFolded` status, exact symbolic
  translation, or concrete value.  This is loss of presentation evidence, not a
  lowering to an opaque function.
  Evidence: `FieldProjection` in `src/Keiki/Core.hs`,
  `projectThroughTermWithStatus` in `src/Keiki/Composition.hs`, and
  `docs/adr/0004-composition-uses-snapshot-updates-and-checked-boundaries.md`.
- Discovery: `validateMermaidDiagram` is intentionally a heuristic and explicitly
  does not prove that Mermaid accepts a document.  Readable-label acceptance must
  also exercise the `beautiful-mermaid` backend used by `site/build.mjs` and fail
  if the generated site contains a `diagram-error` fallback.
  Evidence: the module header in `src/Keiki/Render/Validate.hs`, `site/build.mjs`,
  and the `beautiful-mermaid` dependency in `package.json`.
- Discovery: the configured `beautiful-mermaid` backend calls `decodeXML` on the
  whole diagram before splitting lines and treats `<br>`, `<br/>`, and `<br />` as
  label layout.  A single entity-encoding pass is therefore not an isolation
  boundary: `&#10;` becomes a structural newline and `&lt;br/&gt;` becomes a layout
  tag before parsing.
  Evidence: `package.json` and `pnpm-lock.yaml` resolve `beautiful-mermaid` 1.1.3;
  Mori reported no registered project for that dependency, so its resolved source
  and state-label tests were inspected locally, followed by an `entities.decodeXML`
  probe on 2026-08-01.
- Discovery: bare `cabal` in the ambient shell selects GHC 9.10/base 4.20 and
  cannot solve this repository's `base ^>=4.21` packages.  The same full baseline
  passes under the flake's GHC 9.12.4 shell: Keiki 626 examples, codec 104,
  codec-test 13, and Jitsurei 122, all with zero failures.
  Evidence: `cabal test all --test-show-details=direct` failed before compilation;
  `nix develop -c cabal test all --test-show-details=direct` passed on
  2026-08-01.
- Discovery: the plan's original `intention` frontmatter value belonged to Keiro,
  so it could not serve as the execution and commit-trailer identity for work in
  this repository.
  Evidence: the user's ownership correction and Mina's successful JSON result for
  this plan's exact title on 2026-08-01.
- Discovery: `beautiful-mermaid` 1.1.3 accepts quotes, pipes, braces, and
  ampersands after its entity-decode pass, but angle-bracket break tags and both
  raw and backslash-spelled newlines change structure before SVG escaping.
  Keiki can therefore preserve safe punctuation through XML entities while
  rendering angle brackets as full-width visible punctuation, raw CR/LF as
  control pictures, and backslashes as full-width backslashes.  The known
  `<lit>` sentinel is safe to entity-encode directly and remains visually exact.
  Evidence: `site/verify-semantic-label-escaping.mjs` asserts three parsed edges,
  three exact SVG `tspan` lines, and the recovered label text from the checked-in
  four-line fixture.


## Decision Log

Record every decision made while working on the plan.

- Decision: Block AST and default-renderer changes on a before/after guarantee
  ledger.
  Rationale: a rendering improvement may change public source compatibility and
  visible bytes, but it must not silently change executable values, proof results,
  replay, projection coherence, transducer validation, or the availability of
  opaque literals.
  Date: 2026-08-01
- Decision: Treat human readability as part of renderer correctness.
  Rationale: A diagram whose executable conditions and state changes cannot be
  understood by a human does not fulfill the purpose of a behavioral diagram,
  even if its Mermaid syntax and topology are valid.
  Date: 2026-08-01
- Decision: Make ordinary literals self-describing with `TLit :: Show r => r ->
  Term rs ci ifs r`, and represent unavoidable opacity with a distinct
  `TOpaqueLit :: r -> Term rs ci ifs r` plus `opaqueLit`.
  Rationale: deriving text from the actual value prevents a caller-supplied label
  from lying about executable behavior.  A separate opaque constructor makes lost
  evidence explicit instead of silently degrading every literal.
  Date: 2026-08-01
- Decision: Preserve `<lit>` only for explicit `opaqueLit` nodes and for
  transformations that genuinely cannot retain a `Show` dictionary.
  Rationale: Keiki must be honest when it cannot render a value, but opacity should
  be exceptional and visible rather than the normal output of `lit`.
  Date: 2026-08-01
- Decision: Require explicit opacity for sensitive or intentionally redacted
  values, and document that readable diagrams may expose ordinary literals.
  Rationale: changing the primary renderer from hidden to readable must not create
  an undocumented confidentiality trap.  `opaqueLit` and the topology renderer
  are semantic and whole-diagram redaction choices respectively.
  Date: 2026-08-01
- Decision: In `0.8`, make `toMermaid` and `defaultMermaidOptions` select readable
  guards, complete updates, multiline labels, and no semantic truncation.
  Rationale: the main API must serve the main human-understanding use case.  Making
  every caller discover and assemble hidden options perpetuates unreadable output.
  Date: 2026-08-01
- Decision: Add `topologyMermaidOptions` and `toTopologyMermaid` as the explicit
  compact path and pin their output to the `0.7` topology goldens.
  Rationale: callers that need stable shape-only output retain it without forcing
  the primary API to remain semantically empty.
  Date: 2026-08-01
- Decision: Ship the `Term` and default-renderer changes as Keiki `0.8.0.0`.
  Rationale: constructor constraints, exhaustive pattern matches, and changed
  default bytes are intentional breaking changes.  A major PVP bump is clearer
  than compatibility fiction.
  Date: 2026-08-01
- Decision: Define `opaqueLit` as display-opaque but semantically and
  symbolically exact.
  Rationale: redacting a value from prose must not replace a solver constant with
  a free variable, alter pure overlap/dead-edge classification, trigger
  `OpaqueGuard`, or change replay inversion.  Every literal-only analysis must
  treat all four readable/opaque operand pairings identically.
  Date: 2026-08-01
- Decision: Treat `Show` as renderer-only observational evidence, not as a
  canonical serialization, a proof witness, or a security boundary.
  Rationale: a lawful-looking `Show` instance can still be partial, expensive, or
  intentionally stylized.  Executable paths must not force it, and documentation
  must promise value-derived text rather than universally truthful or stable text.
  Date: 2026-08-01
- Decision: Preserve each literal constructor through re-indexing, substitution,
  profunctor mapping, alternative lifting, and pending-write substitution; only a
  literal field-projection fold may lose readability when its result dictionary
  is unavailable.
  Rationale: structural rewrites should not silently disclose an opaque value or
  discard available display evidence.  The projection exception follows the
  existing `FieldProjection` interface and remains an exact literal in concrete
  and symbolic semantics.
  Date: 2026-08-01
- Decision: Remove the legacy `showWrittenSlots` and `showGuardSummary` option
  booleans in `0.8`, leaving `updateMode` and `guardMode` authoritative, and add
  options-aware entry points for every public diagram shape that currently lacks
  them.
  Rationale: two fields controlling one segment can disagree, and a single
  `toTopologyMermaid` function cannot preserve topology-only output for nested,
  alternative, three-way, or feedback renderers.  The PVP-breaking release is the
  appropriate point to make the policy total and unambiguous.
  Date: 2026-08-01
- Decision: Validate readable labels with both Keiki's heuristic validator and
  the checked-in documentation rendering backend.
  Rationale: a warning-free heuristic scan is useful but is not parser evidence.
  The site backend is the concrete renderer this repository ships and can expose
  parsing failures through its `diagram-error` fallback.
  Date: 2026-08-01
- Decision: Keep renderer-owned layout separate from untrusted semantic text and
  reject a one-pass XML-entity scheme as the sole escaping mechanism.
  Rationale: the site backend decodes entities before parsing.  Raw carriage
  returns/newlines must become visible non-structural text, and layout-like input
  must remain inert after that decode step.  Tests must inspect parsed/rendered
  output, not only the pre-decode Mermaid source.
  Date: 2026-08-01
- Decision: Associate this ExecPlan with the newly created Keiki intention
  `intention_01kz0chaggerxaswdydar94e3c` and stop using the prior Keiro-owned
  intention.
  Rationale: intention ownership must match the repository and plan whose work and
  commit trailers it tracks.  Reusing the Keiro intention would merge unrelated
  execution histories.
  Date: 2026-08-01
- Decision: Escape Mermaid edge semantics with a backend-aware visible scheme:
  XML entities for punctuation that is safe after one decode, full-width angle
  brackets and backslashes for parser-active spellings, and control pictures for
  raw line endings; insert renderer-owned `<br/>` only after segment escaping.
  Rationale: this preserves readable punctuation wherever the backend permits it,
  makes control input visible rather than silently deleting it, and gives the
  actual parser no opportunity to reinterpret semantic text as transitions or
  label layout.
  Date: 2026-08-02


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

Plan-validation outcome (2026-08-01): the proposed `Show`-constrained `TLit` plus
`TOpaqueLit` design can preserve Keiki's soundness, but only if display opacity is
kept exact in replay, pure analysis, and SBV translation.  The original draft did
not state the mixed-constructor proof cases, the composition projection-fold
exception, the actual options path for non-single renderers, or the configured
backend's pre-parse entity decoding.  Those obligations are now explicit and
blocking.  No library implementation or release work has begun.

Intention-correction outcome (2026-08-01): Mina created
`intention_01kz0chaggerxaswdydar94e3c` from the plan title, and the plan now uses
that Keiki-owned ID as its authoritative frontmatter intention.  Future commits
for this ExecPlan must use the same value in their `Intention:` trailer.

Milestone 2 outcome (2026-08-02): the primary Mermaid APIs now render the
behavior a reviewer needs to inspect, including full register right-hand sides
and ordinary literal values; explicit topology policy retains every prior golden
without semantic segments.  No public diagram shape bypasses the options-aware
edge-label path.  A checked-in adversarial label proves quotes, apostrophes,
ampersands, pipes, braces, raw CR/LF, literal `\\n`, all three break-tag
spellings, and already-entity-like input stay one transition and render as three
intended SVG text lines through the repository's concrete backend.


## Context and Orientation

Keiki is the typed transducer library underneath generated Keiro aggregates.  A
`Term rs ci ifs r` in `src/Keiki/Core.hs` is both executable syntax and symbolic
data: it can read a register or input field, hold a literal, call a typed function,
or combine subterms.  `HsPred` and `Update` embed these terms in transition guards
and register writes.  Runtime stepping and replay consume the same transition
objects that the renderers inspect.

Today `TLit :: r -> Term rs ci ifs r` carries no `Show r` evidence.  Consequently
`prettyTerm (TLit _)` in `src/Keiki/Render/Pretty.hs` can only emit `<lit>`.
`src/Keiki/Render/Mermaid.hs` has an opt-in `MermaidGuardPretty` mode but its
default hides guards, and its update summary includes only written slot names.
`src/Keiki/Render/Inspector.hs` is more detailed, but it does not repair the
contract of the primary diagram API.  An emitted event is represented by
`WireCtor`, which records its constructor name but not named output fields; this
plan keeps event output at that honest level and does not invent field names.

All constructor matches in `src/Keiki/Core.hs`, `src/Keiki/Symbolic.hs`,
`src/Keiki/Composition.hs`, `src/Keiki/Profunctor.hs`, and
`src/Keiki/Render/Pretty.hs` must handle both readable and opaque literals.
Compiler warnings plus a repository-scoped `rg` over every Haskell source form the
exhaustive migration inventory; compilation alone is not enough because a catch-all
can compile while silently changing a literal's classification.  Tests under
`test/Keiki/` exercise evaluation, replay, symbolic projection, composition,
pretty-printing, Mermaid rendering, and validation.

For this plan, soundness means that any proof reported by Keiki remains valid for
concrete execution, and that forward execution and event replay continue to agree
where the existing validation contract says they agree.  Proof completeness is a
separate concern, but this change is stricter than mere soundness: replacing
`TLit` by `TOpaqueLit` must also preserve verification classifications rather than
unnecessarily weakening them.  Display opacity is therefore not the same as the
symbolic opacity of `TApp1` and `TApp2`.

The blocking guarantee ledger covers:

- Evaluation identity: readable and opaque literal nodes return their stored value
  and predicates/updates evaluate exactly as the corresponding pre-change `TLit`.
- Expressiveness: values without `Show` remain representable through `opaqueLit`;
  the library does not exclude a runtime type merely to render it.
- Replay identity: stepping, encoding emitted events, and replaying them produces
  the same state and registers.  In `solveOutput`, `recomputeDerivedFields`, and
  `gatherInpEntries`, both literal constructors remain invertible constant fields
  that contribute no recovered command slots and are not recomputed.
- Structural coherence: re-indexing, profunctor mapping, composition, alternative,
  and feedback retain literal values, literal presentation policy, and
  input/register path alignment.  A field-projection fold that lacks a result
  `Show` dictionary may change only `TLit` to `TOpaqueLit`; it remains a
  `ProjectionFolded` exact constant rather than a `TApp1` lowering.
- Proof identity: `translateTermSym` translates both constructors with `symLit`;
  `termReportEvents` reports no issue for either; `termHasOpaqueFallback` returns
  `False` for either; and pure equality/ordering handles readable/readable,
  readable/opaque, opaque/readable, and opaque/opaque literal pairs with the same
  result.  `OpaqueGuard` and detailed verification classifications do not change.
- Rendering compatibility: primary readable bytes change intentionally, while
  options-aware topology rendering pins every `0.7` topology golden
  byte-for-byte across single, labeled, flat composite, nested composite,
  alternative, three-way composition, and feedback shapes.
- Confidentiality clarity: ordinary `lit` values are documented as visible in
  readable output, while `opaqueLit` and topology rendering provide intentional
  redaction without changing runtime or proof meaning.  `Show` output is not a
  stable wire encoding and must not be used as one.

The relevant durable decisions are:

- `docs/adr/0001-structural-re-indexing-for-sound-replay.md` makes `Term` structural
  and permits literals in the interface-free fragment.  The new constructor must
  preserve that structural discipline.
- `docs/adr/0002-event-logs-must-reproduce-forward-state.md` requires forward and
  replay state to agree.  Rendering evidence must never affect evaluation.
- `docs/adr/0003-proof-gates-fail-conservatively.md` requires opacity to be explicit.
  `opaqueLit` follows that rule for display text but remains a solver-exact
  constant; it must never fabricate display text or symbolic uncertainty.
- `docs/adr/0004-composition-uses-snapshot-updates-and-checked-boundaries.md`
  requires mapped literal projections to remain constant folds and distinguishes
  them from computed-owner projections lowered to opaque applications.  Losing a
  `Show` dictionary must not change that boundary classification.

No current ADR owns the contract that the primary behavioral renderer is readable.
Implementation must add a filesystem ADR under `docs/adr/` covering literal
evidence, explicit opacity, readable defaults, and the topology-only escape hatch.
Plan 61 is the checked-in predecessor and must be cited in migration notes.  Keiro's
coordinated downstream work has this canonical URI:

```text
mori://shinzui/keiro/plans/179-generate-one-human-readable-authoritative-keiro-transducer
```


## Plan of Work

Milestone 0 pins the guarantees before changing constructors.  Add or strengthen
tests that cover `evalTerm`, `evalPred`, `runUpdate`, `evalOut`, `step`,
`solveOutput`, encoded-event replay, pure overlap/dead-edge classification, SBV
verification detail, validation warnings, structural projection/re-indexing,
profunctor mapping, composition, alternative, feedback, and every current topology
golden.  Record the exact result and classification of each baseline assertion,
not merely whether the test process exits successfully.  Include a fixture literal
whose type has no `Show` instance for the post-change `opaqueLit` path and a
separate value whose `Show` instance throws if forced; concrete execution and
replay of the latter must still succeed.  Record which visible outputs are
intentionally allowed to change; no semantic result, replay decision, validation
warning, pure-analysis result, or SBV classification is in that set.  Milestone 1
does not start until this baseline passes in `nix develop`.

Milestone 1 changes the literal representation without changing behavior.  In
`src/Keiki/Core.hs`, give `TLit` a `Show` constraint, keep `lit` as the ordinary
constructor, add `TOpaqueLit` and `opaqueLit`, and export the smart constructors.
Introduce a small internal literal eliminator if that avoids duplicating the four
readable/opaque cases in `pureEquality` and `pureOrdering`; it must return the stored
value without calling `show`.

Update every constructor match in Core, Symbolic, Composition, and Profunctor.
`evalTerm` returns the stored value for both constructors.  Replay inversion treats
both as the old invertible literal category in `recomputeDerivedFields` and
`gatherInpEntries`.  Input-read, projection-info, constructor-name, composition
alignment, and opaque-fallback walkers give both the same classification as the
old `TLit`.  `translateTermSym` calls `symLit` for both, `termReportEvents` reports
no issue for either, and the pure analyzer compares all four constructor pairings
exactly.  In particular, `TOpaqueLit` must not become a fresh SBV variable, an
`OpaqueApplication`, an `OpaqueGuard`, or `PureUnknown` merely because its text is
redacted.

Operations that retain the original value and dictionary retain `TLit`; operations
that receive `TOpaqueLit` retain it.  This rule applies to left/right weakening,
substitution, alternative lifting, pending-write substitution, and the
`Keiki.Profunctor` term walkers.  `projectThroughTermWithStatus` maps either literal
owner to `TOpaqueLit (fieldWitnessGet witness owner)` because its current
constraints do not provide `Show (FieldResult projection)`; the status remains
`ProjectionFolded`, and `composeChecked` must not report
`NonStructuralProjectionBoundary`.  Do not add a `Show` superclass to
`FieldProjection`, because that would reduce the owner/result types Keiki can
model.

Add unit and property tests demonstrating that `lit` and `opaqueLit` have equal
runtime and proof meaning, including mixed readable/opaque comparisons, and that
composition/re-indexing does not acquire a semantic difference.  Test a composed
readable literal after the existing `unsafeCoerceTerm`-guarded substitution path so
the retained `Show` dictionary is observed safely by `prettyTerm`.  Re-run every
Milestone 0 semantic and proof assertion, not only renderer tests.  This milestone
is accepted when all non-rendering tests pass, the non-`Show` fixture still
executes, the throwing-`Show` fixture executes without forcing `show`, the exact
verification classifications are unchanged, and no partial `Term` match remains.

Milestone 2 makes readable semantics the primary rendering path.  Change
`prettyTerm` so a normal `TLit` renders `show value` and an explicit opaque literal
renders `<lit>`.  Exercise numeric, boolean, enumeration, identifier-like, text,
and time-like examples.  The contract is value-derived `Show` text, not canonical
serialization: a partial `Show` may make rendering fail but must never affect
execution or proof behavior.

Escape at the Mermaid label boundary; do not alter the Haskell-oriented
pretty-printer merely to satisfy Mermaid syntax.  Escape each semantic segment
before joining segments with the renderer-owned `<br/>` separator, so layout tags
are not escaped with the data.  First normalize raw carriage returns and newlines
to visible non-structural text such as `\r` and `\n`.  Then encode suspicious
characters with one documented scheme, with additional protection for any text
that the backend's single `decodeXML` pass would turn into `<br>`, `<br/>`, or
`<br />`.  A one-pass XML-entity replacement by itself is forbidden because the
backend reverses it before parsing.

Add tests for raw newlines, every backend-recognized break-tag spelling, and
already entity-like input.  Assert the number of Mermaid source lines, the exact
edge label recovered by the backend or present in its SVG, and the absence of an
extra transition—not merely that rendering did not throw.  The escaped source
must remain warning-free under `validateMermaidDiagram`, and the checked-in
documentation diagram must render without `diagram-error` in `site-dist`.

In `src/Keiki/Render/Mermaid.hs`, add an update mode parallel to `MermaidGuardMode`.
The readable mode uses `prettyUpdate` and renders complete assignments, while the
written-slot and hidden modes remain explicit compact choices.  Remove the legacy
`showWrittenSlots` and `showGuardSummary` booleans so `updateMode` and `guardMode`
are the only authorities.  Set `defaultMermaidOptions` to readable guard and
update modes, multiline layout, and no truncation that removes business semantics.
Add `topologyMermaidOptions` and `toTopologyMermaid` to reproduce the prior primary
single-transducer output byte-for-byte.

Route every diagram shape through an options-aware edge-label path.  Existing
primary functions keep their shapes and use `defaultMermaidOptions`; add
`toMermaidCompositeWith`, `toMermaidCompositeNestedWith`,
`toMermaidCompose3With`, `toMermaidCompose3NestedWith`,
`toMermaidAlternativeWithOptions`, and `toMermaidFeedback1With` for the paths that
currently hard-code `edgeLabel`.  `toMermaidAlternativeWith` retains its current
arm-name arguments and delegates to the new options-aware function with defaults.
`toMermaidWithLabels` already accepts options.  Pin the old bytes for every shape
by calling its options-aware path with `topologyMermaidOptions`; the API need not
multiply convenience `toTopology...` wrappers beyond `toTopologyMermaid`.

Adapt `src/Keiki/Render/Validate.hs` only where necessary to recognize the chosen
entities as escaped while continuing to warn about raw suspicious text.  Its
Haddock must continue to say that it is heuristic.  Goldens must show both readable
and topology forms, and at least one site-consumed diagram must contain the special
character fixture so the real backend exercises the escaping contract.

Milestone 3 records and teaches the contract.  Create the ADR described above;
update Haddocks, `README.md`, and `CHANGELOG.md`; and replace examples that describe
`toMermaid` as topology-only.  Include a `0.7` to `0.8` migration section: ordinary
custom literals now need `Show`, intentionally opaque values use `opaqueLit`, and
shape-only diagrams use `toTopologyMermaid` or an options-aware shape renderer with
`topologyMermaidOptions`.  Map removed `showWrittenSlots` and `showGuardSummary`
record updates to `MermaidUpdateWrittenSlots` and
`MermaidGuardStructuralSummary`.  Do not solve readability by adding explanatory
comments to an unreadable rendering; examples must be understandable from their
generated edge labels.  State plainly that ordinary literal values are visible in
readable output and that secrets or intentionally redacted values must use
`opaqueLit` or a topology-only diagram.

Milestone 4 audits and releases.  Re-run Mori's reverse-dependency report, record
each registered dependent and whether it compiles unchanged, needs `Show`, needs
`opaqueLit`, or intentionally moves to `toTopologyMermaid`.  Keiro is implemented
by the companion plan; unrelated downstream repositories are audit results unless
their maintainers separately authorize edits.  Set all coordinated Keiki package
versions and internal bounds to `0.8.0.0`, build source distributions, and follow
`agents/skills/release/SKILL.md` after obtaining the operator approval required by
that release workflow.  Verify Hackage and the upstream tag after publication and
record exact evidence in Progress and Outcomes.


## Concrete Steps

Run all commands from `/Users/shinzui/Keikaku/bokuno/keiki`.

Before editing, refresh dependency and release evidence:

```bash
mori registry show shinzui/keiki --full
mori registry docs shinzui/keiki
mori registry dependents shinzui/keiki --packages
curl -fsSL https://hackage.haskell.org/package/keiki/preferred.json
git ls-remote --tags https://github.com/shinzui/keiki.git 'v*'
```

Expected before this plan is implemented: `keiki.cabal` and Hackage identify
`0.7.0.0`, and the upstream output includes `refs/tags/v0.7.0.0`.

Confirm the supported toolchain and capture the clean semantic baseline before
editing.  Do not substitute the ambient `cabal`; it selects the wrong GHC on the
known development machine.

```bash
nix develop -c ghc --version
nix develop -c cabal test all --test-show-details=direct
```

Expected toolchain: GHC 9.12.x.  The 2026-08-01 baseline is Keiki 626 examples,
codec 104, codec-test 13, and Jitsurei 122, all with zero failures.  Test counts may
increase as this plan adds cases, but existing failures or pending cases must not.

Use focused feedback while changing the AST and renderers:

```bash
nix develop -c cabal test keiki-test --test-show-details=direct --test-option=--match --test-option='Keiki.Core'
nix develop -c cabal test keiki-test --test-show-details=direct --test-option=--match --test-option='Keiki.Symbolic'
nix develop -c cabal test keiki-test --test-show-details=direct --test-option=--match --test-option='Keiki.Composition'
nix develop -c cabal test keiki-test --test-show-details=direct --test-option=--match --test-option='Keiki.Render.Pretty'
nix develop -c cabal test keiki-test --test-show-details=direct --test-option=--match --test-option='Keiki.Render.Mermaid'
nix develop -c cabal test keiki-test --test-show-details=direct --test-option=--match --test-option='Keiki.Render.Validate'
```

After adding the constructor, audit every literal match.  Each result must be
classified explicitly as value-preserving, presentation-preserving, or the
documented projection-fold loss of presentation evidence.

```bash
rg -n -C 3 'TLit|TOpaqueLit' -g '*.hs' -g '!dist-newstyle/**' .
nix develop -c cabal build keiki --ghc-options=-Werror=incomplete-patterns
```

Then run the repository-wide gates:

```bash
nix develop -c cabal build all
nix develop -c cabal test all --test-show-details=direct
nix flake check
nix develop -c cabal sdist all
nix develop -c pnpm run build
! rg -n '<pre class="diagram-error">' site-dist -g '*.html'
git diff --check
```

The successful transcript ends with all test suites passing, `nix flake check`
reporting no failed checks, source distributions for the coordinated packages, and
no output from the exact fallback-element search.  Searching only for the word
`diagram-error` is invalid because the site's CSS and this plan mention that class.
Before publishing, read and follow
`agents/skills/release/SKILL.md`; do not infer release authority from this plan.
After an approved release, repeat the Hackage and tag commands and expect
`0.8.0.0` and `v0.8.0.0`.


## Validation and Acceptance

The plan is complete only when all of the following are observable:

- Every Milestone 0 runtime, replay, projection, composition, validation, and
  symbolic-classification assertion passes unchanged.  This includes identical
  pure overlap/dead-edge results and identical `PredicateVerificationDetail` for
  readable, opaque, and mixed literal predicates.  The only accepted baseline
  differences are public constructor/options constraints, documented projection
  display opacity, and primary rendering bytes explicitly listed in this plan.
- `prettyTerm (lit (3 :: Int))` contains `3`, while
  `prettyTerm (opaqueLit (3 :: Int))` is `<lit>`.  The same distinction is tested
  for representative domain and textual values.
- Evaluating otherwise identical terms made with `lit` and `opaqueLit` yields the
  same values.  Forward `step` followed by encoded-event replay reaches the same
  state and registers as before the AST change.  A readable literal whose `Show`
  implementation throws still evaluates, updates, emits, and replays successfully,
  proving executable paths do not force display evidence.
- A value with no `Show` instance remains executable through `opaqueLit`, including
  in a register update and replay path.  Readability does not reduce the domain of
  values Keiki can model.
- SBV translates both literal constructors to the same constant; neither produces
  `OpaqueApplication`/`OpaqueGuard`.  Pure equality and ordering return the same
  result for all four readable/opaque operand pairings.  A folded projection of a
  readable literal may render opaquely when the field result lacks `Show`, but it
  remains `ProjectionFolded`, concrete-exact, solver-exact, and accepted by
  `composeChecked`.
- A primary `toMermaid` golden contains a real guard and a full assignment such as
  `balance := balance + amount`; ordinary values in that expression are not
  `<lit>`.  The reader does not need source comments or a separate inspector dump
  to recover the transition's decision and state change.
- Semantic labels containing quotes, angle brackets, pipes, ampersands, and line
  breaks are escaped once, cannot inject renderer-owned `<br/>`, pass
  `validateMermaidDiagram` without suppressing unrelated validation warnings, and
  render through `site/build.mjs` without a `diagram-error` fallback.  Raw
  newlines and the three backend-recognized break-tag spellings preserve the
  diagram's line/transition count and remain non-layout text after the backend's
  entity-decoding pass.
- `toTopologyMermaid` reproduces the corresponding `0.7` single-transducer golden
  exactly.  Every options-aware composite, nested, alternative, three-way,
  feedback, and labeled path reproduces its `0.7` golden when passed
  `topologyMermaidOptions`.
- Documentation and tests make literal disclosure explicit: ordinary `lit` appears
  in readable diagrams, while `opaqueLit` remains `<lit>` and topology output hides
  semantic expressions.
- Single, composite, alternative, three-way composition, feedback, and labeled
  render paths obey the readable-primary/explicit-topology distinction; no path
  hard-codes `edgeLabel` and silently drops configured semantic segments.
- `nix develop -c cabal test all --test-show-details=direct`, `nix flake check`,
  `nix develop -c cabal sdist all`, and the documentation build succeed under GHC
  9.12.x with no generated `diagram-error` marker.
- Hackage and the upstream repository expose coordinated `0.8.0.0` artifacts, and
  the reverse-dependency audit is recorded before the Keiro plan raises its bound.


## Idempotence and Recovery

AST, renderer, test, and documentation edits are ordinary source changes and their
validation commands are repeatable.  Golden regeneration must be deterministic;
review the textual diff before accepting it and never overwrite a golden merely to
make a failing test disappear.

The release step is not reversible.  Build and inspect source distributions first,
obtain the approval required by the release skill, and publish only after all local
and Nix gates pass.  If publication partially succeeds, do not reuse a released
version: update this living plan with the published state and follow the release
skill's recovery procedure.  Downstream Keiro work must keep its old bound until
both Hackage and the upstream tag independently confirm `0.8.0.0`.


## Interfaces and Dependencies

`Keiki.Core` must expose the following conceptual interface (the implementation may
retain the module's established export style):

```haskell
data Term rs ci ifs r where
  TLit :: Show r => r -> Term rs ci ifs r
  TOpaqueLit :: r -> Term rs ci ifs r

lit :: Show r => r -> Term rs ci ifs r
opaqueLit :: r -> Term rs ci ifs r
```

Both constructors store the executable value.  No API accepts arbitrary display
text for a literal.  Matching `TLit` brings `Show r` into scope for renderers, but
every non-rendering eliminator must ignore that dictionary.  `TOpaqueLit` is not a
symbolically opaque application: when the result type has symbolic support, its
translation is the same `symLit` constant as `TLit`.

`Keiki.Render.Mermaid` must expose an explicit update policy and topology entry
point, alongside its existing guard policy:

```haskell
data MermaidUpdateMode
  = MermaidUpdateHidden
  | MermaidUpdateWrittenSlots
  | MermaidUpdatePretty

topologyMermaidOptions :: MermaidOptions

toTopologyMermaid
  :: (Show cs, Show ci, Show eo)
  => SymTransducer cs rs ci ifs eo efs
  -> Text
```

`MermaidOptions` gains `updateMode :: MermaidUpdateMode`.  During the breaking
migration, remove `showWrittenSlots` and `showGuardSummary`; do not permit legacy
booleans and mode fields to disagree.  `defaultMermaidOptions` selects
`MermaidGuardPretty` and `MermaidUpdatePretty`.  `topologyMermaidOptions` selects
hidden semantics and pins the old compact layout.  The exact constraints on
`toTopologyMermaid` must match the existing `toMermaid` signature in source if it
differs from the conceptual signature above.

Every public shape renderer must have an options-aware route.  The implementation
adds the following names with the corresponding existing renderer's constraints
and arguments plus one leading `MermaidOptions` argument:

```haskell
toMermaidCompositeWith
toMermaidCompositeNestedWith
toMermaidCompose3With
toMermaidCompose3NestedWith
toMermaidAlternativeWithOptions
toMermaidFeedback1With
```

`toMermaidAlternativeWithOptions` takes `MermaidOptions`, then the existing left
and right arm names, then the two transducers.  Existing no-options functions
delegate with `defaultMermaidOptions`.  Topology compatibility tests call these
functions with `topologyMermaidOptions`.

The local package has this canonical package URI:

```text
mori://shinzui/keiki/packages/keiki
```

The coordinated downstream plan has this canonical URI:

```text
mori://shinzui/keiro/plans/179-generate-one-human-readable-authoritative-keiro-transducer
```

No Keiro source change belongs in this repository's plan.


Revision note (2026-08-01): Validated the proposed literal and renderer changes
against concrete evaluation, replay inversion, pure guard analysis, SBV
translation, composition projection folding, every current diagram shape, the
accepted soundness ADRs, the flake toolchain, Hackage, and upstream release tags.
The revision makes display opacity explicitly solver-exact, adds mixed-literal and
throwing-`Show` regression obligations, preserves `ProjectionFolded` behavior,
requires options-aware topology compatibility for every renderer, distinguishes
the heuristic validator from the real site backend, rejects entity-only escaping
after inspecting that backend's pre-parse decoding, includes ADR-0004, and fixes
all validation commands and code-block language tags.  These changes close the
soundness gaps without expanding executable semantics.

Revision note (2026-08-01): Replaced the incorrect Keiro-owned frontmatter
intention after creating `intention_01kz0chaggerxaswdydar94e3c` with
the exact plan title.  Updated Progress, Surprises & Discoveries, Decision Log,
and Outcomes so the plan and future commit trailers consistently track the Keiki
work.
