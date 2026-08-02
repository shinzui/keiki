---
id: 84
slug: preserve-readable-business-semantics-in-keiki-transducers-and-diagrams
title: "Preserve readable business semantics in Keiki transducers and diagrams"
kind: exec-plan
created_at: 2026-08-02T03:36:01Z
intention: "intention_01kz08h2rrekw87j8d7fv1zmmt"
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

The change does not add a second source of executable behavior.  Literal display
evidence is carried by the same typed `Term` node that evaluation, symbolic
execution, composition, and replay consume.  Tests prove that adding this evidence
does not change evaluation or replay results.  The visible proof is a golden
diagram whose edge label contains complete guard and update expressions and which
passes Keiki's Mermaid validator.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] Milestone 0: capture an executable guarantee ledger for evaluation, replay,
  symbolic conservatism, composition, projection, validation, and legacy rendering.
- [ ] Milestone 1: preserve trustworthy literal display evidence in `Term` while
  keeping evaluation, symbolic execution, composition, and replay behavior equal.
- [ ] Milestone 2: render full guards and register assignments in the primary
  Mermaid API, with an explicit topology-only compatibility API.
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
  Evidence: `src/Keiki/Render/Pretty.hs` and `renderEdgeSummary` in
  `src/Keiki/Render/Mermaid.hs`.
- Discovery: Mori reports twelve registered project-level dependents of Keiki.
  Keiro is the downstream changed by the companion plan; the other dependents must
  be audited and recorded before release, not silently assumed compatible.
  Evidence: `mori registry dependents shinzui/keiki --packages`.
- Discovery: the authoritative current release is `0.7.0.0`: it is the version in
  `keiki.cabal`, the preferred Hackage release, and upstream tag `v0.7.0.0` peels to
  commit `7c5d433ef4455e9e626347f89cb3a416bad62e72`.  A structural `Term` API change
  therefore requires the `0.8` PVP line.


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


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

(To be filled during and after implementation.)


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
Compiler errors are the exhaustive migration list.  Tests under `test/Keiki/`
exercise evaluation, replay, symbolic projection, composition, pretty-printing,
Mermaid rendering, and validation.

The blocking guarantee ledger covers:

- Evaluation identity: readable and opaque literal nodes return their stored value
  and predicates/updates evaluate exactly as the corresponding pre-change `TLit`.
- Expressiveness: values without `Show` remain representable through `opaqueLit`;
  the library does not exclude a runtime type merely to render it.
- Replay identity: stepping, encoding emitted events, and replaying them produces
  the same state and registers.
- Structural coherence: re-indexing, profunctor mapping, composition, alternative,
  and feedback retain literal values and input/register path alignment.
- Proof conservatism: symbolic translation and validation classify equivalent
  terms no more optimistically after display evidence is added; opacity remains
  explicit.
- Rendering compatibility: primary readable bytes change intentionally, while
  the explicit topology API pins every `0.7` topology golden byte-for-byte.
- Confidentiality clarity: ordinary `lit` values are documented as visible in
  readable output, while `opaqueLit` and topology rendering provide intentional
  redaction without changing runtime meaning.

The relevant durable decisions are:

- `docs/adr/0001-structural-re-indexing-for-sound-replay.md` makes `Term` structural
  and permits literals in the interface-free fragment.  The new constructor must
  preserve that structural discipline.
- `docs/adr/0002-event-logs-must-reproduce-forward-state.md` requires forward and
  replay state to agree.  Rendering evidence must never affect evaluation.
- `docs/adr/0003-proof-gates-fail-conservatively.md` requires opacity to be explicit.
  `opaqueLit` follows that rule and must never fabricate display text.

No current ADR owns the contract that the primary behavioral renderer is readable.
Implementation must add a filesystem ADR under `docs/adr/` covering literal
evidence, explicit opacity, readable defaults, and the topology-only escape hatch.
Plan 61 is the checked-in predecessor and must be cited in migration notes.  Keiro's
coordinated downstream work has this canonical URI:

    mori://shinzui/keiro/plans/179-generate-one-human-readable-authoritative-keiro-transducer


## Plan of Work

Milestone 0 pins the guarantees before changing constructors.  Add or strengthen
tests that cover `evalTerm`, predicate and update evaluation, `step`, encoded-event
replay, validation warnings, SBV verification classification, structural
projection/re-indexing, profunctor mapping, composition, alternative, feedback,
and every current topology golden.  Include a fixture literal whose type has no
`Show` instance so the post-change `opaqueLit` path must preserve Keiki's existing
runtime expressiveness.  Record which visible outputs are intentionally allowed to
change; no semantic result or proof classification is in that set.  Milestone 1
does not start until this baseline passes.

Milestone 1 changes the literal representation without changing behavior.  In
`src/Keiki/Core.hs`, give `TLit` a `Show` constraint, keep `lit` as the ordinary
constructor, add `TOpaqueLit` and `opaqueLit`, and export the smart constructors.
Update every constructor match in Core, Symbolic, Composition, and Profunctor.
Operations that retain the original value and dictionary retain `TLit`; operations
such as a projection whose result has no available `Show` constraint explicitly
produce `TOpaqueLit`.  Both nodes evaluate to their stored value and participate
identically in stepping and replay.  Add unit and property tests demonstrating that
`lit` and `opaqueLit` have equal runtime meaning and that composition/re-indexing
does not acquire a semantic difference.  Re-run every Milestone 0 semantic and
proof assertion, not only renderer tests.  This milestone is accepted when all
non-rendering tests pass, the non-`Show` fixture still executes, and no partial
`Term` match remains.

Milestone 2 makes readable semantics the primary rendering path.  Change
`prettyTerm` so a normal `TLit` renders `show value` and an explicit opaque literal
renders `<lit>`.  Exercise numeric, boolean, enumeration, identifier-like, text,
and time-like examples.  Escape the resulting text at the Mermaid label boundary;
do not alter the Haskell-oriented pretty-printer merely to satisfy Mermaid syntax.

In `src/Keiki/Render/Mermaid.hs`, add an update mode parallel to `MermaidGuardMode`.
The readable mode uses `prettyUpdate` and renders complete assignments, while the
written-slot and hidden modes remain explicit compact choices.  Set
`defaultMermaidOptions` to readable guard and update modes, multiline layout, and
no truncation that removes business semantics.  Add `topologyMermaidOptions` and
`toTopologyMermaid` to reproduce the prior primary output byte-for-byte.  Apply the
same readable-default policy to composite, alternative, composed, feedback, and
labeled entry points rather than fixing only a single transducer.  Adapt
`src/Keiki/Render/Validate.hs` only where necessary to accept correctly escaped
semantic labels while continuing to warn about actually suspicious Mermaid.
Goldens must show both readable and topology forms.

Milestone 3 records and teaches the contract.  Create the ADR described above;
update Haddocks, `README.md`, and `CHANGELOG.md`; and replace examples that describe
`toMermaid` as topology-only.  Include a `0.7` to `0.8` migration section: ordinary
custom literals now need `Show`, intentionally opaque values use `opaqueLit`, and
shape-only diagrams use `toTopologyMermaid`.  Do not solve readability by adding
explanatory comments to an unreadable rendering; examples must be understandable
from their generated edge labels.  State plainly that ordinary literal values are
visible in readable output and that secrets or intentionally redacted values must
use `opaqueLit` or a topology-only diagram.

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

    mori registry show shinzui/keiki --full
    mori registry docs shinzui/keiki
    mori registry dependents shinzui/keiki --packages
    curl -fsSL https://hackage.haskell.org/package/keiki/preferred.json
    git ls-remote --tags https://github.com/shinzui/keiki.git 'v*'

Expected before this plan is implemented: `keiki.cabal` and Hackage identify
`0.7.0.0`, and the upstream output includes `refs/tags/v0.7.0.0`.

Use focused feedback while changing the AST and renderers:

    cabal test keiki-test --test-show-details=direct --test-option=--match --test-option='Keiki.Core'
    cabal test keiki-test --test-show-details=direct --test-option=--match --test-option='Keiki.Symbolic'
    cabal test keiki-test --test-show-details=direct --test-option=--match --test-option='Keiki.Composition'
    cabal test keiki-test --test-show-details=direct --test-option=--match --test-option='Keiki.Render.Pretty'
    cabal test keiki-test --test-show-details=direct --test-option=--match --test-option='Keiki.Render.Mermaid'
    cabal test keiki-test --test-show-details=direct --test-option=--match --test-option='Keiki.Render.Validate'

Then run the repository-wide gates:

    cabal build all
    cabal test all --test-show-details=direct
    nix flake check
    cabal sdist all
    git diff --check

The successful transcript ends with all test suites passing, `nix flake check`
reporting no failed checks, and source distributions for the coordinated packages.
Before publishing, read and follow `agents/skills/release/SKILL.md`; do not infer
release authority from this plan.  After an approved release, repeat the Hackage
and tag commands and expect `0.8.0.0` and `v0.8.0.0`.


## Validation and Acceptance

The plan is complete only when all of the following are observable:

- Every Milestone 0 runtime, replay, projection, composition, validation, and
  symbolic-classification assertion passes unchanged.  The only accepted baseline
  differences are public constructor constraints/API migration and primary
  rendering bytes explicitly listed in this plan.
- `prettyTerm (lit (3 :: Int))` contains `3`, while
  `prettyTerm (opaqueLit (3 :: Int))` is `<lit>`.  The same distinction is tested
  for representative domain and textual values.
- Evaluating otherwise identical terms made with `lit` and `opaqueLit` yields the
  same values.  Forward `step` followed by encoded-event replay reaches the same
  state and registers as before the AST change.
- A value with no `Show` instance remains executable through `opaqueLit`, including
  in a register update and replay path.  Readability does not reduce the domain of
  values Keiki can model.
- A primary `toMermaid` golden contains a real guard and a full assignment such as
  `balance := balance + amount`; ordinary values in that expression are not
  `<lit>`.  The reader does not need source comments or a separate inspector dump
  to recover the transition's decision and state change.
- Semantic labels containing quotes, angle brackets, pipes, ampersands, and line
  breaks are escaped into valid Mermaid and pass `validateMermaidDiagram` without
  suppressing unrelated validation warnings.
- `toTopologyMermaid` reproduces the corresponding `0.7` topology golden exactly.
- Documentation and tests make literal disclosure explicit: ordinary `lit` appears
  in readable diagrams, while `opaqueLit` remains `<lit>` and topology output hides
  semantic expressions.
- Single, composite, alternative, three-way composition, feedback, and labeled
  render paths obey the readable-primary/explicit-topology distinction.
- `cabal test all --test-show-details=direct`, `nix flake check`, and
  `cabal sdist all` succeed.
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
text for a literal.

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
migration, remove or deprecate `showWrittenSlots` rather than permit two fields to
disagree; the chosen final record must have one authoritative update policy.
`defaultMermaidOptions` selects `MermaidGuardPretty` and
`MermaidUpdatePretty`.  `topologyMermaidOptions` selects hidden semantics and pins
the old compact layout.  The exact constraints on `toTopologyMermaid` must match
the existing `toMermaid` signature in source if it differs from the conceptual
signature above.

The local dependency has this canonical package URI:

    mori://shinzui/keiki/packages/keiki

The coordinated downstream plan has this canonical URI:

    mori://shinzui/keiro/plans/179-generate-one-human-readable-authoritative-keiro-transducer

No Keiro source change belongs in this repository's plan.
