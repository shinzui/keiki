---
id: 85
slug: prove-replay-inverse-candidates-disjoint-from-shared-register-conjuncts
title: "Prove replay inverse candidates disjoint from shared-register conjuncts"
kind: exec-plan
created_at: 2026-08-04T17:28:34Z
---

# Prove replay inverse candidates disjoint from shared-register conjuncts

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

After this change, Keiki's default validator will stop reporting an
`InversionAmbiguity` for two same-mode, same-head replay edges when a small pure proof can show
that their guards cannot both succeed on one pre-event register file. The motivating shape has
one reconstructed command guarded by `openSteps > 1` and another reconstructed command guarded
by `openSteps == 1`. The commands may be different constructors and the guards may also contain
opaque input-dependent conjuncts; the shared-register conditions alone are sufficient to prove
that replay can never select both edges for one observed head event.

The change is visible in `test/Keiki/ValidationReplayAlignmentSpec.hs`. A local fixture matching
Mori Workflow's shape will replay both its non-final and final paths, and
`validateTransducer defaultValidationOptions` will return no `InversionAmbiguity` for the pair.
Changing the second condition to `openSteps > 0` will retain the warning and produce a concrete
ambiguous replay witness. Unsupported predicates will also retain the warning. The runtime replay
kernel does not change.

This plan implements
[IR-5](../improvement-requests/prove-inverse-candidates-disjoint-before-reporting-ambiguity.md)
with a deliberately narrower proof boundary than a full symbolic model of `OutTerm` inversion.
[Plan 86](86-research-a-full-symbolic-replay-inversion-model.md) separately investigates whether
that larger model would provide enough additional precision to justify its maintenance cost.


## Progress

- [ ] Milestone 1: add the same-head disjoint, overlapping, opaque-only, and structural-identity
      fixtures, pinning the current false-positive warning before production code changes.
- [ ] Milestone 2: implement an internal necessary-condition extractor for exact integral
      register-versus-literal conjuncts and an explicit conservative disjointness verdict.
- [ ] Milestone 3: integrate the proof into `inversionAmbiguityWarnings` without changing replay,
      phase selection, the warning type, validation options, or the pure default-validation
      contract.
- [ ] Milestone 4: add exhaustive and generated agreement tests against concrete replay candidate
      evaluation, including live, replay-only, opaque, unsupported, and duplicate-label cases.
- [ ] Milestone 5: update Haddocks, the changelog, IR status, and relevant ADRs; run every project
      validation gate and record the release/adoption handoff.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Prove a sufficient shared-register condition rather than encode `OutTerm`, observed
  events, or two reconstructed commands.
  Rationale: If successful replay candidacy for edge `e` implies a register-only condition
  `N_e(regs)`, then unsatisfiability of `N_a(regs) && N_b(regs)` proves the real candidate pair
  disjoint. Output inversion and all dropped guard conjuncts can only narrow that over-approximate
  set. This gives the motivating precision without changing `WireCtor`, adding `Eq co` to the
  validator, or starting z3 in default validation.
  Date: 2026-08-04

- Decision: Unsupported and opaque top-level conjuncts are dropped as weakening, but never used as
  proof evidence.
  Rationale: Mori's real Workflow guards contain opaque identity and step-book checks alongside
  the exact `openSteps` comparison. Rejecting the whole guard because one conjunct is opaque would
  preserve the false positive. Descending through `POr` or `PNot`, however, would not preserve the
  necessary-condition implication and is forbidden.
  Date: 2026-08-04

- Decision: Keep the analysis internal, pure, source-compatible, and fail-conservative.
  Rationale: `validateTransducer` promises a microsecond-scale path with no external solver. The
  only externally visible change should be that a proven false-positive warning disappears.
  Unknown, unsupported, malformed, or type-inconsistent cases remain warnings.
  Date: 2026-08-04

- Decision: Give proof variables structural identity using register position and value type;
  labels are diagnostics only.
  Rationale: Builder-authored schemas have distinct names, but lower-level users can construct
  duplicate-labelled `RegFile` schemas. Treating two positions with the same label as one variable
  could manufacture false unsatisfiability and suppress a real ambiguity.
  Date: 2026-08-04


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Keiki models an event-sourced state machine as `SymTransducer` in `src/Keiki/Core.hs`. Each
outgoing `Edge` has a guard, register update, output word, target vertex, and `EdgeMode`. `Live`
edges participate in command handling and replay. `ReplayOnly` edges participate only in replay
after no live edge accepts the observed event. Runtime replay is implemented by
`applyEventKernel`. At a settled vertex it uses the same pre-event `RegFile rs` for every edge,
calls `solveOutput` on each edge's first `OutTerm`, evaluates that edge's guard against the
independently reconstructed command, and succeeds only when one edge in the selected phase is a
candidate. A candidate is therefore:

```text
Candidate(e, regs, observed) =
  there exists command such that
    solveOutput(head(e), regs, observed) = Just command
    and evalPred(guard(e), regs, command) = True
```

The build-time check `inversionAmbiguityWarnings`, also in `src/Keiki/Core.hs`, currently warns for
every pair with the same source, `EdgeMode`, and first `WireCtor` name unless either guard is the
literal `PBot`. This is conservative and preserves correctness, but it reports pairs whose
candidacy is mutually exclusive because of their shared register state. The warning is one
constructor of `TransducerValidationWarning`; `validateTransducer` enables the check by default
through `ValidationOptions.checkInversionAmbiguity`.

The predicate language `HsPred` contains `PAnd`, `POr`, `PNot`, constructor tests, equality, and
ordering. Its operands are `Term` values. `TReg` reads a register, `TInpCtorField` reads the
reconstructed command, and `TApp1`/`TApp2` are opaque Haskell functions. For this plan, a
"top-level conjunct" means an atom reached only by recursively traversing `PAnd`; the traversal
must not enter `POr` or `PNot`. A "necessary condition" is a predicate that must be true whenever
the complete guard returns true. Dropping a conjunct weakens a conjunction, so the remaining
conjuncts are necessary conditions even when dropped atoms are opaque.

`src/Keiki/Core.hs` already contains exact integral interval machinery for the pure forward
determinism check: `PureRelation`, `PureComparison`, `discoverIntegralDomain`, and
`integralComparisonsSatisfiable`. That check proves overlap, which is the opposite proof polarity
from this plan. Its `PureFragment` rejects an entire guard when it sees an opaque atom, and its
`PureVariable` uses diagnostic names. Do not negate or directly reuse its Boolean result for a
disjointness proof. Share small exact primitives only after their contracts are made explicit.
In particular, `literalWitnessSatisfies == False` means only that no mentioned literal was found;
it is not proof of unsatisfiability.

`indexPosition` in `src/Keiki/Core.hs` already computes a structural zero-based position for an
`Index`. The symbolic projection implementation uses position and `TypeRep` because manually
constructed duplicate-labelled schemas are legal below the Builder boundary. The new proof must
follow that precedent.

Tests for replay/validation alignment live in `test/Keiki/ValidationReplayAlignmentSpec.hs`.
Tests for phase selection live in `test/Keiki/ReplayOnlySpec.hs`, and the existing pure interval
matrix lives in `test/Keiki/ValidationSpec.hs`. `test/Spec.hs` already registers all three modules,
so this plan should extend them rather than add another test module unless implementation reveals
a clear cohesion problem.

The cross-repository reproducer is
`mori://shinzui/mori/plans/176-rewrite-the-workflow-aggregate-with-real-step-completion-and-causation`.
Mori's generated non-final/final completion edges share `WorkflowStepCompleted`; its failure edges
share `WorkflowStepFailed`. The relevant guards contain `openSteps > 1` and `openSteps == 1` plus
opaque identity and step-book conjuncts. The current Mori registry cannot resolve that artifact
URI yet, but `mori registry show shinzui/mori --full` identifies the owning project and the URI is
the producer's canonical plan handle. Do not replace it with an absolute checkout path in durable
prose.

Three accepted local ADRs constrain the implementation. [ADR-0001](../adr/0001-structural-re-indexing-for-sound-replay.md)
requires structural rather than name-based evidence at replay soundness boundaries.
[ADR-0002](../adr/0002-event-logs-must-reproduce-forward-state.md) says default validation may accept
only transducers whose produced logs reproduce forward state.
[ADR-0003](../adr/0003-proof-gates-fail-conservatively.md) says only definite unsatisfiability can
bless disjointness; uncertainty must retain the warning. Update ADR-0002 and ADR-0003 during the
final milestone to record the new sufficient-proof boundary. Do not create a new ADR unless
implementation discovers a distinct durable decision not covered by those records.


## Plan of Work

Milestone 1 establishes the behavior before changing the validator. Extend
`test/Keiki/ValidationReplayAlignmentSpec.hs` with a small `Natural` register file, two command
constructors that carry compatible payloads, and one shared event constructor. Build one pair with
guards containing their respective `PInCtor`, an opaque but harmless sibling conjunct, and
`openSteps > 1` versus `openSteps == 1`. Demonstrate both forward/replay paths concretely, then pin
that the current validator reports one false-positive `InversionAmbiguity`. Add an overlapping
variant whose second guard is `openSteps > 0`; at `openSteps = 2` one observed event must become a
runtime `ReplayAmbiguousInversions`. Add an opaque-only pair and a different-command-constructor
pair so later suppression cannot be attributed to constructor difference or guessed opaque
semantics. This milestone is complete when focused tests pass while explicitly documenting the
one warning that Milestone 3 will remove.

Milestone 2 adds a new internal proof path in the pure validation section of
`src/Keiki/Core.hs`. Introduce a structurally identified register variable containing the
zero-based `Index` position, the value's `SomeTypeRep`, and a label used only for diagnostics.
Normalize only `TReg relation literal` and `literal relation TReg` atoms from `PEq` and `PCmp`.
Accept `TLit` and `TOpaqueLit` equally. Admit a comparison only when
`discoverIntegralDomain` supplies an exact domain for the operand type. Flatten `PAnd`, preserve
`PBot` as an unsatisfiable necessary condition, and return no constraint for every other atom.
Do not descend into `POr`, `PNot`, `TApp1`, `TApp2`, `TArith`, `TFieldProj`, or input-field reads.

Give the satisfiability kernel an explicit verdict rather than a misleading Boolean. A suitable
internal shape is:

```haskell
data RegisterConstraintVerdict
  = RegisterConstraintsUnsatisfiable
  | RegisterConstraintsSatisfiable
  | RegisterConstraintsUnknown

data CandidateDisjointness
  = ProvenCandidateDisjoint
  | CandidateDisjointnessNotProven
```

Exact names may follow the surrounding `Pure*` vocabulary, but the three meanings must remain
distinct. Group comparisons only when both position and `TypeRep` match. Use exact interval
intersection to return `RegisterConstraintsUnsatisfiable`; a type-alignment failure or unsupported
domain returns `RegisterConstraintsUnknown`, never unsatisfiable. Add a concise proof comment:
every real candidate implies the extracted condition, so an unsatisfiable conjunction of the two
extractions proves the candidate pair disjoint even though output inversion is not modeled.

Milestone 3 integrates the proof into `inversionAmbiguityWarnings`. Preserve the current source,
mode, literal-bottom, non-empty-output, same-head-name, and pair-order filters. Immediately before
constructing the warning, ask the new helper whether shared-register disjointness is proved; emit
the existing `InversionAmbiguity` unchanged unless the answer is `ProvenCandidateDisjoint`. Do not
add a public warning constructor, `ValidationOptions` field, typeclass constraint, `Eq co`
constraint, solver call, or dependency. Update the Milestone 1 disjoint fixture to expect no
warning. The overlap and unknown fixtures must still expect the existing warning.

Milestone 4 makes the proof polarity executable. In
`test/Keiki/ValidationReplayAlignmentSpec.hs`, add a helper that counts actual candidates by
following the public runtime recipe: same mode, non-empty output, `solveOutput`, then `models` on
the recovered command and the same registers. Exhaustively enumerate a bounded set of
`openSteps`, observed event payloads, and both fixture modes. Every pair whose warning is
suppressed must have candidate count at most one. The overlapping control must exhibit count two
for a named state/event witness. Add QuickCheck coverage over a bounded generated integral domain
so strict/inclusive/equality boundary combinations are compared with concrete guard evaluation.
The generated test is regression evidence; the necessary-condition implication and exact interval
kernel remain the soundness argument.

Add two adversarial tests. First, manually construct a register schema with two positions carrying
the same diagnostic label and arrange values so conditions on the two positions can both hold;
the warning must remain. This bypasses Builder's `DistinctNames` constraint and proves that
structural identity is used. Second, give a disjoint supported register pair additional opaque
conjuncts and confirm suppression still occurs, while an opaque-only apparent split remains a
warning. Extend `test/Keiki/ReplayOnlySpec.hs` with a same-mode replay-only disjoint pair and prove
it receives the same treatment as live edges; retain the existing cross-mode exemption tests.

Milestone 5 updates the public explanation and durable project memory. Rewrite the Haddock above
`inversionAmbiguityWarnings` and the `InversionAmbiguity` constructor to say that equal head names
are conservative evidence of possible ambiguity and are suppressed only by a proved shared-state
necessary-condition contradiction. Update `validateTransducer`'s Haddock, `CHANGELOG.md`, and
[IR-5](../improvement-requests/prove-inverse-candidates-disjoint-before-reporting-ambiguity.md).
The IR must say opaque siblings may be dropped as weakening but cannot be proof evidence, and it
must describe the change as source-compatible but behaviorally observable because exact-warning
allowlists lose entries. Advance its status only to the state allowed by
`mori/improvement-requests-profile.dhall`; do not invent `implemented` or `released` if the profile
does not permit them.

Update [ADR-0002](../adr/0002-event-logs-must-reproduce-forward-state.md) and
[ADR-0003](../adr/0003-proof-gates-fail-conservatively.md) through the profiled ADR workflow in
`agents/skills/exec-plan/ADR.md`. Preserve their `docId`s, add strict-authoring metadata only as
allowed by `docs/adr/profile.dhall`, and update `docs/adr/log.md` with `okf log add` when timestamps
advance. The plan is complete after focused tests, the complete repository test matrix, Haddocks,
formatting, strict ADR validation, and diff checks pass. Release and downstream adoption occur only
from an authoritative Hackage version and upstream tag; use the repository's `release` skill as a
separate explicitly authorized operation after this implementation plan is complete.


## Concrete Steps

Run every command from `/Users/shinzui/Keikaku/bokuno/keiki`. Start by preserving unrelated work
and locating the exact implementation points:

```bash
git status --short
rg -n "inversionAmbiguityWarnings|PureComparison|discoverIntegralDomain|indexPosition" src/Keiki/Core.hs
rg -n "cross-edge inversion ambiguity|static checks" test/Keiki/ValidationReplayAlignmentSpec.hs test/Keiki/ReplayOnlySpec.hs
```

Do not restore or overwrite unrelated dirty files. Run the focused pre-change and milestone tests
inside the repository's GHC 9.12 development shell:

```bash
nix develop -c cabal test keiki-test --test-options='--match=ValidationReplayAlignmentSpec|ReplayOnly|validateTransducer' --test-show-details=direct
```

If Hspec treats the combined expression differently in the active version, run the three stable
substrings separately:

```bash
nix develop -c cabal test keiki-test --test-options='--match=ValidationReplayAlignmentSpec' --test-show-details=direct
nix develop -c cabal test keiki-test --test-options='--match=ReplayOnly' --test-show-details=direct
nix develop -c cabal test keiki-test --test-options='--match=validateTransducer' --test-show-details=direct
```

After Milestone 3, the focused transcript must include the new disjoint and overlap examples with
zero failures. Record the actual counts in Progress rather than copying a stale number:

```text
... examples, 0 failures
```

Format and run the complete gates after Milestone 5:

```bash
nix fmt -- --no-cache
nix develop -c cabal build all
nix develop -c cabal test all --test-show-details=direct
nix develop -c cabal haddock keiki
nix flake check
just adr-validate
git diff --check
```

`just adr-validate` first type-checks `docs/adr/profile.dhall` and then enforces the profile and
bundle log. If it fails because the current checkout contains an unrelated in-progress ADR-profile
migration, do not weaken or bypass the gate. Record the exact failure, preserve those user-owned
changes, and rerun after the profile owner resolves them.

Before release handoff, verify the owning package and reverse-dependency surface without relying on
stale memory:

```bash
mori registry show shinzui/keiki --full
mori registry dependents shinzui/keiki --packages
```


## Validation and Acceptance

The implementation is acceptable only when all of the following behavior is observable.

The same-source, same-mode, same-head fixture with different reconstructed command constructors,
opaque sibling conjuncts, and `openSteps > 1` versus `openSteps == 1` produces no
`InversionAmbiguity`. Forward execution and replay still reach identical vertices and registers
for both the non-final and final paths.

Changing the second register condition to `openSteps > 0` preserves the warning. The fixture
contains a concrete pre-event register file and observed head event for which
`applyEventStreamingEither` returns `ReplayAmbiguousInversions` naming both edges.

Different `PInCtor` atoms alone never suppress a warning. An opaque-only split, a disjunction, a
negation, structural arithmetic, a field projection, an input-field comparison, an unsupported
carrier, or any internal unknown verdict retains the warning. A supported register contradiction
may still suppress when opaque atoms appear as sibling conjuncts because those atoms were dropped
only as weakening.

Cross-mode live/replay-only pairs remain exempt under the runtime's live-first rule. Same-mode
replay-only pairs use the new proof exactly as live pairs do. Multi-event tails never participate
in the proof or head identity.

For every same-head fixture pair suppressed by the test matrix, bounded concrete enumeration finds
no register/event combination with two actual candidates. The duplicate-label adversarial fixture
retains its warning and exhibits two distinct structural register positions despite identical
labels.

The public types and signatures of `TransducerValidationWarning`, `ValidationOptions`,
`validateTransducer`, and `inversionAmbiguityWarnings` are unchanged. `keiki.cabal` adds no
dependency. Default validation starts no solver process and still succeeds when z3 is absent.

All focused and complete commands in Concrete Steps pass, Haddocks explain the sufficient proof,
and the changelog calls out that downstream exact-warning assertions may need to remove warnings
which Keiki now proves false.


## Idempotence and Recovery

All source edits and tests are ordinary tracked-file changes and can be repeated safely. The
fixtures use pure values and create no external state. Solver-free focused tests are deterministic.
Formatting and Cabal build/test commands are safe to rerun.

Before editing, inspect `git status --short`. Existing modifications belong to the user; never use
`git reset --hard`, `git checkout --`, or a broad restore to recover from a failed milestone. If an
edit overlaps an existing change, preserve both intents with a narrow `apply_patch` and inspect the
resulting file diff.

If Milestone 2 cannot prove the motivating pair without using opaque atoms as evidence, stop and
record the counterexample in Surprises & Discoveries. Do not weaken the conservative gate. If the
proof requires z3, `Eq co`, a public API change, or structural changes to `WireCtor`, leave
`inversionAmbiguityWarnings` unchanged and defer that work to
[Plan 86](86-research-a-full-symbolic-replay-inversion-model.md).

If strict ADR validation is blocked by unrelated profile work, keep the implementation and ADR
edits uncommitted or in a working commit that is not presented as complete, record the blocker, and
rerun the exact gate after the profile is repaired. Never edit the profile merely to make this plan
pass unless the profile change is independently in scope.


## Interfaces and Dependencies

The implementation belongs in `Keiki.Core` at `src/Keiki/Core.hs`. It uses `HsPred`, `Term`,
`Index`, `SomeTypeRep`, `PureRelation`, and the exact integral-domain machinery already in that
module. No new library dependency is permitted. In particular, this plan does not use `sbv` or
`Keiki.Symbolic` at runtime.

The production integration point remains source-compatible:

```haskell
inversionAmbiguityWarnings ::
  (Bounded s, Enum s, Show s) =>
  SymTransducer (HsPred rs ci) rs s ci co ->
  [TransducerValidationWarning s]
```

Add internal, non-exported types or helpers expressing necessary register conditions and a
fail-conservative verdict. Their exact names may match surrounding style, but callers must not see
a new public proof API in this plan. The helper contract is:

```text
ProvenCandidateDisjoint means there is no RegFile value that can satisfy the extracted necessary
conditions of both guards. Every other outcome means emit the existing warning.
```

`test/Keiki/ValidationReplayAlignmentSpec.hs`, `test/Keiki/ReplayOnlySpec.hs`, and
`test/Keiki/ValidationSpec.hs` use Hspec and QuickCheck, both already declared in `keiki.cabal`.
Do not add a test dependency. The external Mori reproducer is context and downstream acceptance,
not a build dependency: Keiki tests must carry a self-contained local fixture.
