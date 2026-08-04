---
id: 85
slug: prove-replay-inverse-candidates-disjoint-from-shared-register-conjuncts
title: "Prove replay inverse candidates disjoint from shared-register conjuncts"
kind: exec-plan
created_at: 2026-08-04T17:28:34Z
intention: intention_01kz7att76e2trqcrrz3n2vetr
---

# Prove replay inverse candidates disjoint from shared-register conjuncts

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

After this change, Keiki's default validator will stop reporting an
`InversionAmbiguity` for two same-mode replay edges when a small pure proof can show that their
guards cannot both succeed on one pre-event register file. The motivating shape has one
reconstructed command guarded by `openSteps > 1` and another guarded by `openSteps == 1`. The
commands may be different constructors and the guards may contain opaque input-dependent sibling
conjuncts; the shared-register conditions alone are sufficient to prove that replay can never
select both edges for one observed head event.

This is deliberately the cheap default companion to
[Plan 87](87-add-structural-wire-schemas-for-optional-symbolic-replay-inversion.md), which must be
completed first. Plan 87 owns the source-breaking `WireCtor` schema, final structural head
relation, Generics/TH/composition/profunctor propagation, output-dependent symbolic solver,
Keiki/Keiro version line, and consumer source migration. This plan consumes that final
representation and adds only a solver-free necessary-condition proof. It does not build an
interim identity layer, encode `OutTerm`, start z3, change package versions, or repeat the
downstream migration.

The visible behavior belongs in `test/Keiki/ValidationReplayAlignmentSpec.hs`. A local
register-only fixture matching Mori Workflow's guard shape replays its non-final and final paths,
and `validateTransducer defaultValidationOptions` returns no `InversionAmbiguity` for the pair.
Changing the second condition to `openSteps > 0` retains the warning and produces a concrete
ambiguous replay witness. Unsupported predicates retain the warning. Plan 87's
output-dependent fixtures remain in `test/Keiki/FullSymbolicReplayInversionSpec.hs` and are not
reimplemented here. Runtime replay does not change.

This plan implements
[IR-5](../improvement-requests/prove-inverse-candidates-disjoint-before-reporting-ambiguity.md)
after the structural prerequisite is stable.


## Progress

- [x] (2026-08-04) Revised the plan after Plan 86 completed: sequenced it after Plan 87 and removed
      structural-schema, output-inversion, solver, versioning, and consumer-migration work now
      owned by that follow-up.
- [x] (2026-08-04T21:32:43Z) Milestone 1: added the same trusted-head register-disjoint,
      register-overlapping, opaque-only, and duplicate-register-label fixtures. The focused
      ValidationReplayAlignmentSpec baseline grew from 18 to 23 examples with 0 failures; the
      disjoint pair still pinned the pre-implementation false-positive warning, while the overlap
      and duplicate-label controls produced concrete two-candidate replay failures.
- [x] (2026-08-04T21:39:42Z) Milestone 2: implemented the internal `PAnd`-spine extractor for exact
      integral register-versus-literal equality and ordering, structural `(position, TypeRep)`
      variables, explicit satisfiable/unsatisfiable/unknown verdicts, and fail-conservative
      blocker diagnostics. Unsupported siblings are weakening-only and cannot supply proof.
- [x] (2026-08-04T21:39:42Z) Milestone 3: integrated the proof through
      `wireHeadsMayAliasForDefault`; only definite register UNSAT suppresses the warning, while
      retained warnings name opaque applications, unsupported carriers, or duplicate positions.
      ValidationReplayAlignmentSpec passed 24 examples, `validateTransducer` passed 32,
      ReplayOnly passed 2 selected examples, and FullSymbolicReplayInversion passed 14, all with
      0 failures. Runtime replay and the optional solver path were unchanged.
- [x] (2026-08-04T21:46:18Z) Milestone 4: added a concrete candidate counter following
      mode eligibility, `solveOutput`, and `models`; exhaustive Natural-register/event coverage
      for both modes; 100 generated strict/inclusive/equality boundary cases; and conservative
      disjunction, negation, arithmetic, projection, input-field, application, unsupported-carrier,
      and duplicate-label controls. ValidationReplayAlignmentSpec passed 27 examples and the
      complete lower-case `replay-only` selection passed 26, both with 0 failures. The Plan 87
      output-dependent fixture now explicitly asserts that pure default validation retains one
      warning; FullSymbolicReplayInversion passed 14 examples with 0 failures.
- [ ] Milestone 5: update Haddocks, the changelog, IR status, and relevant ADRs; run Keiki gates and
      only the downstream warning-allowlist checks justified by Plan 87's recorded audit.


## Surprises & Discoveries

- Observation: Plan 86 proved that a full model has real output-dependent precision and acceptable
  opt-in cost, but also proved that current `WireCtor` values cannot soundly align two existential
  head field lists.
  Evidence: `docs/research/full-symbolic-replay-inversion-model.md` concludes “Proceed after
  structural wire-schema prerequisite” and specifies the follow-up now recorded as Plan 87.

- Observation: Keiki and Keiro have two active application adopters now and are expected to serve
  twenty-plus applications.
  Evidence: user-provided rollout context on 2026-08-04. This makes the source-breaking structural
  boundary urgent and makes temporary Plan 85 identity work actively wasteful.

- Observation: the pure register contradiction does not need observed-field evidence and remains
  useful after the full schema exists.
  Evidence: every real candidate implies its complete guard on the shared pre-event `RegFile`.
  Unsatisfiability of weakened register-only necessary conditions therefore proves disjointness
  regardless of command reconstruction or output inversion.

- Observation: two structurally distinct register positions with the same label can satisfy
  `position 0 > 1` and `position 1 == 1` simultaneously, and concrete replay then selects both
  candidates.
  Evidence: the Milestone 1 `duplicateLabelFixture` replays `StepCompleted 7` from registers
  `(2, 1)` to `ReplayAmbiguousInversions` naming edges 0 and 1. Any proof key based only on the
  diagnostic label would suppress this real ambiguity unsoundly.

- Observation: the plan's literal `--match=ReplayOnly` selector matches only two example names,
  not the complete replay-only module whose top-level Hspec label is lower-case `replay-only`.
  Evidence: the Milestone 3 command completed with 2 examples and 0 failures. Later focused proof
  uses the module's lower-case label so the complete phase-selection group is exercised.


## Decision Log

- Decision: Execute Plan 87 before this plan and integrate only against its final head relation.
  Rationale: This prevents a temporary `wcName`-based identity implementation and a second change
  when typed schemas arrive. It also keeps the source-breaking migration in one owning plan.
  Date: 2026-08-04

- Decision: Plan 87 exclusively owns structural wire types, schema trust, field alignment,
  output-dependent formulas and fixtures, solver APIs, version/bound changes, Keiro/generated-code
  migration, and the two active application source migrations.
  Rationale: Duplicating any of those here would create the consumer churn this sequencing is
  intended to avoid. Plan 85 may consume the stable helper and rerun relevant behavior checks but
  must not reshape it.
  Date: 2026-08-04

- Decision: Prove a sufficient shared-register condition rather than encode `OutTerm`, observed
  events, or two reconstructed commands.
  Rationale: If successful replay candidacy for edge `e` implies a register-only condition
  `N_e(regs)`, then unsatisfiability of `N_a(regs) && N_b(regs)` proves the real candidate pair
  disjoint. Output inversion and all dropped guard conjuncts can only narrow that over-approximate
  set. The optional Plan 87 checker owns cases that need observed-output relationships.
  Date: 2026-08-04

- Decision: Unsupported and opaque top-level conjuncts are dropped as weakening, but never used as
  proof evidence.
  Rationale: Mori's real Workflow guards contain opaque identity and step-book checks alongside
  the exact `openSteps` comparison. Rejecting the whole guard because one conjunct is opaque would
  preserve the false positive. Descending through `POr` or `PNot`, however, would not preserve the
  necessary-condition implication and is forbidden.
  Date: 2026-08-04

- Decision: Keep the analysis internal, pure, source-compatible relative to Keiki 0.9, and
  fail-conservative.
  Rationale: `validateTransducer` promises a microsecond-scale path with no external solver. The
  externally visible change is only that a proved false-positive warning disappears. Unknown,
  unsupported, malformed, or type-inconsistent cases remain warnings.
  Date: 2026-08-04

- Decision: Give proof variables structural identity using register position and value type;
  labels are diagnostics only.
  Rationale: Lower-level users can construct duplicate-labelled `RegFile` schemas. Treating two
  positions with the same label as one variable could manufacture false unsatisfiability and
  suppress a real ambiguity.
  Date: 2026-08-04

- Decision: Use Plan 87's three-way head classifier. Structurally different trusted heads are not
  candidates for one observed head; structurally equal heads are comparable; unwitnessed wires
  preserve the legacy equal-`wcName` fallback.
  Rationale: This consumes the final structural representation once while keeping manually
  unavailable wires behaviorally conservative. Register contradiction remains sound in the
  fallback because it does not use name equality as typed field evidence.
  Date: 2026-08-04

- Decision: Do not repeat Plan 87's reverse-dependent source migration or version gates. Consult
  its recorded audit and touch a downstream repository only if this plan removes a warning that
  the repository explicitly allowlists.
  Rationale: A stale warning assertion is a behavior-specific consequence of Plan 85 and cannot be
  migrated earlier; all `WireCtor`, TH, bounds, and generated-code changes belong to Plan 87.
  Date: 2026-08-04

- Decision: A retained warning names the blocking construct in its human-readable `tvwDetail`
  string — the first opaque or unsupported top-level conjunct kind, an unsupported carrier, a
  type-alignment failure, or an unknown verdict — while the `InversionAmbiguity` constructor
  shape, fields, and every structured payload stay unchanged. "Preserve warning payload"
  elsewhere in this plan means the constructor and structured fields; the detail prose may be
  enriched.
  Rationale: IR-5's 2026-08-04 refinement requests actionable diagnostics: a team seeing a
  retained warning should learn which conjunct to restructure into the supported register
  fragment. Enriching only the detail string keeps the change source-compatible and adds no
  validation option. Downstream tests asserting exact detail strings, if any exist, fall under
  the same allowlist-only downstream policy as suppressed warnings.
  Date: 2026-08-04

- Decision: Treat `PInCtor` as a benign dropped conjunct rather than the retained warning's
  blocker, while `POr`, `PNot`, input-arm tests, input-field terms, applications, arithmetic, and
  projections are precision blockers.
  Rationale: Replay reconstructs one command independently per edge, so two constructor tests do
  not constrain the shared register file and are expected in every well-guarded pair. Naming them
  first would hide the actionable opaque or unsupported sibling that consumers can restructure.
  Date: 2026-08-04

- Decision: Test the private proof through the public warning boundary and concrete replay
  candidacy rather than export an internal verdict solely for tests.
  Rationale: The observable contract is warning suppression, and the candidate counter exercises
  the runtime recipe independently. Generated agreement at that boundary proves the required
  polarity without turning private extraction types into supported API.
  Date: 2026-08-04


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

This plan starts only after
[Plan 87](87-add-structural-wire-schemas-for-optional-symbolic-replay-inversion.md) is marked
complete. At that point `WireCtor co fields` in `src/Keiki/Core.hs` carries a final
`WireSchema co fields`, and Keiki has an internal three-way structural head classifier. Generated
and Generic event wires normally carry trusted evidence; manual and lossy transformations may
carry an unavailable schema. The optional `Keiki.Symbolic` checker can model output-dependent
pairs but is not part of default validation. Do not begin this plan against the old three-field
`WireCtor` or introduce a compatibility copy of the new types.

Keiki models an event-sourced state machine as `SymTransducer` in `src/Keiki/Core.hs`. Each
outgoing `Edge` has a guard, register update, output word, target vertex, and `EdgeMode`. `Live`
edges participate in command handling and replay. `ReplayOnly` edges participate only in replay
after no live edge accepts the observed event. Runtime replay in `applyEventKernel` uses the same
pre-event `RegFile rs` for every edge, calls `solveOutput` on each edge's first `OutTerm`, evaluates
the edge guard against the independently reconstructed command, and accepts only a unique
candidate in the selected phase. A candidate is:

```text
Candidate(e, regs, observed) =
  there exists command such that
    solveOutput(head(e), regs, observed) = Just command
    and evalPred(guard(e), regs, command) = True
```

The default build-time check `inversionAmbiguityWarnings` emits
`TransducerValidationWarning.InversionAmbiguity`. After Plan 87 it can classify trusted heads
structurally and fall back conservatively for unavailable schemas, but it still warns for every
possibly same-head, same-mode pair except literal `PBot`. `validateTransducer` enables the check
through `ValidationOptions.checkInversionAmbiguity`. This plan adds one sufficient reason to omit
that existing warning; it adds no warning type or validation option.

`HsPred` contains `PAnd`, `POr`, `PNot`, constructor tests, equality, and ordering over `Term`
values. `TReg` reads a register, `TInpCtorField` reads the reconstructed command, and
`TApp1`/`TApp2` are opaque functions. Here a “top-level conjunct” is an atom reached only by
recursively traversing `PAnd`. A “necessary condition” must hold whenever the complete guard is
true. Dropping a conjunct weakens a conjunction, so supported register atoms remain necessary
even when sibling atoms are opaque. Traversing into `POr` or `PNot` would not preserve that
implication.

`src/Keiki/Core.hs` already contains exact integral interval machinery for pure forward
determinism: `PureRelation`, `PureComparison`, `discoverIntegralDomain`, and
`integralComparisonsSatisfiable`. That check proves overlap, the opposite polarity from this plan.
Its `PureFragment` rejects a whole guard for an opaque atom, and its `PureVariable` uses diagnostic
names. Do not negate or directly reuse its Boolean result. Share small exact primitives only after
their contracts are explicit. In particular, `literalWitnessSatisfies == False` means no mentioned
literal was found; it is not proof of unsatisfiability.

`indexPosition` in `src/Keiki/Core.hs` computes a zero-based structural position for an `Index`.
The symbolic projection implementation already pairs position with `TypeRep` because
duplicate-labelled schemas are legal below Builder. The new proof follows that precedent.

Tests for replay/validation alignment live in `test/Keiki/ValidationReplayAlignmentSpec.hs`, phase
selection in `test/Keiki/ReplayOnlySpec.hs`, and the existing pure interval matrix in
`test/Keiki/ValidationSpec.hs`. Extend those modules. Do not modify Plan 87's
`test/Keiki/FullSymbolicReplayInversionSpec.hs` except to fix a genuine regression caused by the
shared internal helper; never duplicate its output-dependent or solver fixtures.

The cross-repository reproducer is
`mori://shinzui/mori/plans/176-rewrite-the-workflow-aggregate-with-real-step-completion-and-causation`.
Its non-final/final completion edges share `WorkflowStepCompleted`; failure edges share
`WorkflowStepFailed`. Guards contain `openSteps > 1` and `openSteps == 1` plus opaque identity and
step-book conjuncts. It is evidence, not a build dependency; the local test fixture must be
self-contained.

[ADR-0001](../adr/0001-structural-re-indexing-for-sound-replay.md) requires structural identity at
soundness boundaries. [ADR-0002](../adr/0002-event-logs-must-reproduce-forward-state.md) requires
produced logs to reproduce forward state. [ADR-0003](../adr/0003-proof-gates-fail-conservatively.md)
permits suppression only for definite unsatisfiability. Plan 87 records the wire-schema boundary;
this plan updates ADR-0002 and ADR-0003 only with the pure sufficient-proof rule.


## Plan of Work

Milestone 1 establishes only the register-fragment behavior. Extend
`test/Keiki/ValidationReplayAlignmentSpec.hs` with a small `Natural` register file, two command
constructors, and one trusted generated event head. Build a pair whose guards contain their
respective `PInCtor`, an opaque harmless sibling conjunct, and `openSteps > 1` versus
`openSteps == 1`. Keep output fields literal or direct input projections that do not contribute to
the proof. Demonstrate both forward/replay paths concretely and pin the current false-positive
warning. Add an overlapping `openSteps > 0` control with a concrete
`ReplayAmbiguousInversions` witness and an opaque-only pair that retains its warning.

Use Plan 87's existing structural-head tests; do not add same-name/different-constructor schema
fixtures here. The only adversarial identity fixture this milestone owns is a register schema with
two distinct positions carrying the same diagnostic label. Milestone 1 is complete when focused
tests pass while documenting the one warning Milestone 3 will remove.

Milestone 2 adds an internal proof path beside pure validation in `src/Keiki/Core.hs`. Introduce a
register variable containing the zero-based `Index` position, the value's `SomeTypeRep`, and a
diagnostic label. Normalize only `TReg relation literal` and `literal relation TReg` atoms from
`PEq` and `PCmp`. Accept `TLit` and `TOpaqueLit`. Admit a comparison only when
`discoverIntegralDomain` supplies an exact domain. Flatten `PAnd`, preserve `PBot` as an
unsatisfiable necessary condition, and return no constraint for every other atom. Do not enter
`POr`, `PNot`, `TApp1`, `TApp2`, `TArith`, `TFieldProj`, output fields, or input-field reads.

Use explicit verdicts:

```haskell
data RegisterConstraintVerdict
  = RegisterConstraintsUnsatisfiable
  | RegisterConstraintsSatisfiable
  | RegisterConstraintsUnknown

data CandidateDisjointness
  = ProvenCandidateDisjoint
  | CandidateDisjointnessNotProven
```

Exact names may follow the surrounding private `Pure*` vocabulary, but the meanings must remain
distinct. Group comparisons only when position and `TypeRep` match. Exact interval intersection
may return `RegisterConstraintsUnsatisfiable`; type-alignment failure or unsupported domain returns
`Unknown`. Add a proof comment: every real candidate implies the extracted register condition, so
an unsatisfiable conjunction proves the candidates disjoint without modeling their outputs.

Milestone 3 integrates immediately before warning construction. Use Plan 87's final helper, whose
conceptual interface is:

```haskell
data WireHeadRelation
  = WireHeadsStructurallyEqual
  | WireHeadsStructurallyDifferent
  | WireHeadsUnwitnessed

wireHeadsMayAliasForDefault :: WireCtor co fa -> WireCtor co fb -> Bool
```

The helper returns `True` for structurally equal heads, `False` for structurally different trusted
heads, and uses legacy equal `wcName` only for unwitnessed schemas. This plan must call it rather
than inspect `wcSchema` or compare `wcName` itself. For pairs that may alias, emit the existing
warning unless shared-register disjointness is `ProvenCandidateDisjoint`. When the warning is
retained, append the blocking reason to its `tvwDetail` string — the first opaque or unsupported
top-level conjunct kind, unsupported carrier, type-alignment failure, or unknown verdict — so the
diagnostic tells the consumer which construct to restructure into the supported register
fragment. Preserve source, mode,
literal-bottom, non-empty-output, pair order, phase selection, the warning constructor's shape
and structured fields, and the pure signature; only the detail prose is enriched.
Do not call `checkInversionAmbiguitySym`, add an option, or change runtime replay.

Milestone 4 makes the proof polarity executable. Add a local candidate counter that follows the
runtime recipe: pair eligibility, `solveOutput`, then `models` on the recovered command and shared
registers. Exhaustively enumerate bounded `openSteps`, observed events, and both modes. Every pair
whose warning the register proof suppresses must have at most one concrete candidate. The overlap
control must exhibit two for a named witness. Add QuickCheck coverage for strict, inclusive, and
equality interval boundaries over a bounded integral domain.

Add adversarial coverage for duplicate register labels, unsupported carriers, disjunction,
negation, arithmetic, projections, input fields, and opaque-only guards; all must retain warnings
unless an independent supported register contradiction is present as a sibling conjunction.
Extend `test/Keiki/ReplayOnlySpec.hs` with a same-mode replay-only register-disjoint pair and retain
cross-mode live-first exemptions. Do not test output-dependent suppression here: the pure default
must continue warning for Plan 87's full-model-only fixture.

Milestone 5 updates the Haddock above `inversionAmbiguityWarnings`, the
`InversionAmbiguity` constructor, `validateTransducer`, `CHANGELOG.md`, and
[IR-5](../improvement-requests/prove-inverse-candidates-disjoint-before-reporting-ambiguity.md).
Explain that structural head classification comes from Plan 87, while this plan suppresses only a
shared-register necessary-condition contradiction, and that a retained warning's detail string
names the construct that blocked the proof so consumers know what to restructure. Update ADR-0002 and ADR-0003 through the
profiled workflow and update `docs/adr/log.md` when timestamps change. Do not reopen Plan 87's
wire-schema ADR text unless implementation finds a real schema defect.

Run all Keiki gates. Read Plan 87's recorded dependent audit rather than rerunning its source
migration. Search the two active applications and confirmed source dependents for explicit
`InversionAmbiguity` warning allowlists. Rerun only those repositories' validation-focused gates;
remove a stale expected warning if and only if this proof now eliminates it. Do not change their
`WireCtor` construction, generated sources, package bounds, or versions in this plan. Release
remains a separate authorized operation after both plans are complete.


## Concrete Steps

Run from `/Users/shinzui/Keikaku/bokuno/keiki`. Confirm the prerequisite and preserve unrelated
work:

```bash
git status --short
rg -n "Milestone 5|Outcomes & Retrospective|WireSchema" docs/plans/87-add-structural-wire-schemas-for-optional-symbolic-replay-inversion.md src/Keiki/Core.hs
rg -n "inversionAmbiguityWarnings|PureComparison|discoverIntegralDomain|indexPosition|wireHeadsMayAliasForDefault" src/Keiki/Core.hs
```

Do not proceed unless Plan 87's five implementation milestones are checked, its complete gates are
recorded, and the final helper exists. Run focused tests:

```bash
nix develop -c cabal test keiki-test --test-options='--match=ValidationReplayAlignmentSpec' --test-show-details=direct
nix develop -c cabal test keiki-test --test-options='--match=ReplayOnly' --test-show-details=direct
nix develop -c cabal test keiki-test --test-options='--match=validateTransducer' --test-show-details=direct
nix develop -c cabal test keiki-test --test-options='--match=full symbolic replay inversion' --test-show-details=direct
```

The first three commands prove this plan. The last is a non-regression check: its
output-dependent case still warns under pure default validation while the explicit Plan 87
checker can prove it disjoint. Record actual example counts and `0 failures` in Progress.

Run complete gates after documentation:

```bash
nix fmt -- --no-cache
nix develop -c cabal build all
nix develop -c cabal test all --test-show-details=direct
nix develop -c cabal haddock all
nix flake check
just adr-validate
git diff --check
```

Consult, rather than recreate, the reverse-dependent inventory in Plan 87. For each canonical
project it identified as a current source consumer, locate only exact warning assertions from the
Mori-returned checkout path:

```bash
rg -n "InversionAmbiguity|checkInversionAmbiguity|validateTransducer" <registered-project-path>
```

Run and record that project's validation-focused native gate only when the search finds a warning
allowlist or validator snapshot. No match means no Plan 85 downstream edit or rebuild is required.

Every implementation commit carries:

```text
ExecPlan: docs/plans/85-prove-replay-inverse-candidates-disjoint-from-shared-register-conjuncts.md
```


## Validation and Acceptance

The same-source, same-mode, structurally equal-head fixture with different reconstructed command
constructors, opaque sibling conjuncts, and `openSteps > 1` versus `openSteps == 1` produces no
`InversionAmbiguity`. Forward execution and replay still reach identical vertices and registers
for non-final and final paths.

Changing the second condition to `openSteps > 0` preserves the warning. The fixture includes a
pre-event register file and observed event for which replay returns
`ReplayAmbiguousInversions` naming both edges. An opaque-only split retains its warning.

A disjunction, negation, structural arithmetic, field projection, input-field comparison,
unsupported carrier, or internal unknown verdict never supplies proof. A supported register
contradiction may still suppress with opaque sibling conjuncts because those siblings were dropped
only as weakening. Different command constructors alone never suppress.

Every retained warning's `tvwDetail` names the blocking construct, and focused tests assert the
named reason for representative fixtures: the opaque-only pair names its opaque conjunct, the
unsupported-carrier fixture names the carrier, and the duplicate-register-label fixture reports
its type-alignment or position outcome rather than a generic message. The
`InversionAmbiguity` constructor shape and structured fields are unchanged and the enrichment
is source-compatible.

Structurally different trusted heads are filtered by Plan 87's helper. Structurally equal heads are
analyzed. Unwitnessed manual wires preserve the legacy equal-name fallback and remain conservative.
This plan contains no independent field alignment, schema constructors, or `wcName` comparison.

Cross-mode live/replay-only pairs remain exempt under live-first replay. Same-mode replay-only
pairs use the register proof exactly as live pairs. Multi-event tails do not participate in head
identity or the proof.

For every suppressed fixture pair, bounded concrete enumeration finds no register/event
combination with two actual candidates. The duplicate-register-label fixture retains its warning
and proves that positions, not labels, identify variables.

Plan 87's output-dependent fixture remains a warning in `validateTransducer` and remains provable
only through its opt-in symbolic function. Default validation starts no solver and succeeds
without z3. No package version, dependency bound, public warning type, `ValidationOptions`,
`WireCtor`, Generic/TH API, generated source, or runtime replay code changes in this plan.

All focused and complete Keiki commands pass. Downstream changes, if any, are limited to removing
exact warning expectations rendered stale by this proof; the Plan 87 source migration is not
repeated.


## Idempotence and Recovery

Source edits, fixtures, exhaustive enumeration, formatting, and Cabal gates are deterministic and
safe to rerun. Inspect `git status --short`; preserve user-owned changes and use narrow
`apply_patch` edits. Never use a destructive reset, broad restore, or dependency-store search.

If the motivating pair cannot be proved without using opaque atoms, output relationships, command
identity, or schema names as evidence, stop and record the counterexample. Do not expand this plan:
Plan 87's opt-in solver is the owner for output-dependent precision. If the helper from Plan 87 is
insufficient, fix and validate that helper under Plan 87 before resuming rather than creating a
second representation here.

If strict ADR validation is blocked by unrelated work, preserve the changes and exact failure,
then rerun after the owner resolves it. Do not weaken the profile. If a downstream repository has
no explicit warning allowlist, do not edit or rebuild it for this plan merely because Mori listed
it during Plan 87.

Package publication, tags, and new compatibility bounds are excluded. Use the release skill only
after explicit authorization and after this plan and Plan 87 are complete.


## Interfaces and Dependencies

The implementation remains in `Keiki.Core` at `src/Keiki/Core.hs`. It uses `HsPred`, `Term`,
`Index`, `SomeTypeRep`, the final `wireHeadsMayAliasForDefault` helper from Plan 87, and the exact
integral-domain machinery already present. No new dependency is permitted. In particular, this
plan does not import `Keiki.Symbolic` into `Keiki.Core`, invoke SBV, or start z3.

The production signature remains:

```haskell
inversionAmbiguityWarnings
  :: (Bounded s, Enum s, Show s)
  => SymTransducer (HsPred rs ci) rs s ci co
  -> [TransducerValidationWarning s]
```

Add only private necessary-condition and verdict helpers. Their contract is:

```text
ProvenCandidateDisjoint means no RegFile value can satisfy the extracted necessary register
conditions of both guards. Every other result means emit the existing warning.
```

`test/Keiki/ValidationReplayAlignmentSpec.hs`, `test/Keiki/ReplayOnlySpec.hs`, and
`test/Keiki/ValidationSpec.hs` use existing Hspec and QuickCheck dependencies. The external Mori
reproducer and Plan 87's downstream audit are context, not build dependencies.


Plan revision note (2026-08-04): Resequenced after the completed Plan 86 research and new Plan 87.
Removed temporary head-identity work, output-dependent fixtures, symbolic modeling, version/bound
changes, Keiro/generated-code migration, and broad consumer rebuilds. Plan 85 now implements only
the pure shared-register proof against Plan 87's stable structural helper, with downstream work
limited to warning expectations this proof actually changes.

Plan revision note (2026-08-04, second revision): Added actionable retained-warning diagnostics
per IR-5's refinement of the same date: retained warnings name the blocking construct in the
`tvwDetail` string, the constructor shape and structured fields stay unchanged, and focused
tests assert the named reason for representative fixtures. Recorded in the Decision Log with the
clarified meaning of "preserve warning payload"; Milestones 3 and 5 and Validation updated
accordingly.
