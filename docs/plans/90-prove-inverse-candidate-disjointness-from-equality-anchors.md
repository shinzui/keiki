---
id: 90
slug: prove-inverse-candidate-disjointness-from-equality-anchors
title: "Prove inverse-candidate disjointness from equality anchors"
kind: exec-plan
created_at: 2026-08-21T03:53:05Z
intention: "intention_01m0h75jt4eynasvt8pknsqrew"
---

# Prove inverse-candidate disjointness from equality anchors

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

After this change, Keiki's default replay validator will stop reporting an
`InversionAmbiguity` when two same-mode edges with an aliasing head are separated by exact
`Bool` register conditions such as `flag == True` and `flag == False`. The visible proof is
in `test/Keiki/ValidationReplayAlignmentSpec.hs`: the complementary pair produces no warning,
while `flag == True` versus `PTop` still warns and exhibits two concrete replay candidates.
Forward stepping and replay are unchanged.

The motivating consumer is Rei's Intention root. Its current transducer has exactly three
warnings, all blocked by `unsupported register carrier Bool at position 0`, even though each
pair uses complementary `isDormant` guards. This plan supplies a producer-owned exact domain
`[False, True]` so Keiki can evaluate the existing typed comparison closures on every possible
register value. It does not trust arbitrary `Bounded`, `Enum`, or consumer-defined `Eq`
instances, add a solver, or change Keiro's validation policy.

This plan implements
[IR-9](../improvement-requests/prove-inverse-candidate-disjointness-over-finite-enumerated-register-carriers.md)
as technically corrected on 2026-08-21. Publication and Rei adoption remain separate authorized
work: implementation proves that the future released package can remove Rei's opt-out, but this
plan does not publish to Hackage or edit the Rei repository.


## Progress

- [x] (2026-08-21T03:52:41Z) Validated Keiki 0.9.0.0, Keiro's generated validation path, and
      Rei's real Intention transducer; reproduced its three Bool-blocked warnings; rejected
      generic `Bounded`/`Enum` discovery and unrestricted equality anchoring as proof sources;
      corrected IR-9 and created this plan.
- [x] (2026-08-21T04:09:32Z) Milestone 1: added same-command, same-head complementary Bool
      fixtures, pinned the pre-implementation Bool blocker, separated the unregistered-carrier
      control, proved the `PTop` overlap with two concrete candidates, and recorded 12 focused
      and 30 module examples passing.
- [x] (2026-08-21T04:13:07Z) Milestone 2: added the internal producer-owned non-empty Bool
      domain and exhaustive closure evaluation after the unchanged integral path; the
      complementary warning disappeared while the `PTop` and unregistered controls remained,
      with 12 focused and 30 module examples passing and no public export or runtime change.
- [x] (2026-08-21T04:16:28Z) Milestone 3: added the ten-atom, 100-pair Bool relation matrix,
      checked both modes, both register values, and representative observed events, and retained
      named ordering, `PTop`, `PNot`, sibling-contradiction, and unregistered controls; 16
      focused, 34 module, 26 replay-only, and 16 full-symbolic examples passed.
- [ ] Milestone 4: update Haddocks, foundations, changelog, IR-9, ADR-0002, ADR-0003, and the
      profiled logs to describe the delivered proof boundary.
- [ ] Milestone 5: run the focused and complete Keiki gates, audit registered dependents, record
      evidence, and complete the plan's living-document sections.


## Surprises & Discoveries

- Observation: `Typeable` can prove that an existential carrier is one particular known type,
  but it does not recover arbitrary `Bounded` or `Enum` dictionaries. Even if the AST retained
  those dictionaries, Haskell does not enforce the law that `[minBound .. maxBound]` visits
  every inhabitant.
  Evidence: `PEq` retains only `Eq r, Typeable r`; `PCmp` retains only
  `Ord r, Typeable r`; `Term` and the register schema carry no finite-domain evidence.

- Observation: unrestricted equality anchoring also needs a law not enforced by Haskell. From
  `x == a`, replacing `x` with `a` is valid only when the consumer's `Eq` behaves as a
  lawful equivalence relation. A deliberately non-reflexive instance can reject `a == a` while
  accepting another `x == a`, making anchor-only UNSAT inference disagree with concrete
  `evalPred`.
  Evidence: the runtime `PEq` evaluator and the extracted `typedPureAccepts` closure both call
  the consumer dictionary. Exhausting a producer-owned `Bool` domain instead evaluates that
  exact closure at every possible runtime value and needs no added law.

- Observation: Rei uses Keiki and Keiro correctly. The register is `Bool`; both siblings use
  structural `B.requireEq`; replay checks each recovered command's guard against one shared
  pre-update register file; and generated language-5 event streams use
  `mkEventStreamOrThrow`, which delegates to default validation.
  Evidence: executing `inversionAmbiguityWarnings` against
  `mori://shinzui/rei/packages/rei-core` produced exactly three warnings: IntentionActive edges
  4/5 for `ActionRecorded`, IntentionActive edges 44/45 for `OutcomeRecorded`, and
  IntentionCompleted edges 1/2 for `OutcomeRecorded`.

- Observation: Hackage and the public upstream tag set both currently end at Keiki 0.9.0.0; Rei
  declares `keiki ^>=0.9`.
  Evidence: the authoritative Hackage package metadata listed versions through 0.9.0.0, upstream
  listed `v0.9.0.0` as the newest tag, and Mori resolved Rei's package dependency.

- Observation: Cabal splits a quoted multi-word `--test-options='--match=...'` value before
  Hspec receives it. The robust spelling is two `--test-option` arguments.
  Evidence: the first validation command rejected the second word as an unexpected argument;
  `--test-option=--match --test-option='shared-register replay candidate disjointness'` is the
  form this plan uses.

- Observation: The faithful Rei-shaped fixture can use the same `CompleteNonFinal` input
  constructor on both edges; the concrete inverter then recovers the same command for both and
  leaves the shared pre-event Bool register as the only distinguishing fact.
  Evidence: before the proof change, the focused group passed 12 examples, including a
  complementary pair blocked only by `unsupported register carrier Bool`, a `True`/`PTop`
  control with two concrete candidates, and forward/replay agreement from both Bool values. The
  full `ValidationReplayAlignmentSpec` baseline passed 30 examples.

- Observation: Concurrent `cabal test` processes cannot safely share this checkout's
  `dist-newstyle` package cache even when they use different Hspec selectors.
  Evidence: the concurrently launched replay-only selector failed while removing
  `package.conf.inplace/package.cache` as the full-symbolic selector rebuilt the same test suite;
  rerunning replay-only sequentially passed 26 examples, and the concurrent full-symbolic run
  itself passed 16 examples. Validation commands therefore remain sequential.


## Decision Log

- Decision: Register only the standard `Bool` type with a producer-owned complete inhabitant
  list in this plan.
  Rationale: Rei needs exactly Bool. Matching `typeRep @r` against `typeRep @Bool` yields
  `HRefl`, so Keiki can safely return values of the hidden type `r`. The list
  `False :| [True]` is complete by producer construction and cannot be corrupted by consumer
  typeclass instances.
  Date: 2026-08-21

- Decision: Do not implement generic `Bounded`/`Enum` discovery or unrestricted equality
  anchoring.
  Rationale: Both would introduce unenforced consumer laws at a proof gate. Default validation
  may conservatively retain warnings, but it must not suppress one on evidence that can disagree
  with concrete guard evaluation.
  Date: 2026-08-21

- Decision: Reuse each `TypedPureComparison`'s existing `typedPureAccepts :: r -> Bool`
  closure during finite exhaustion.
  Rationale: The closure is created from the exact `Eq` or `Ord` dictionary used by the
  runtime predicate. Evaluating it over every producer-listed inhabitant proves the concrete
  conjunction satisfiable or unsatisfiable without reconstructing a parallel comparison
  interpreter.
  Date: 2026-08-21

- Decision: Support both `PEq` and the four existing structural `PCmp` relations for Bool,
  while keeping `PNot (PEq ...)` and therefore `./=` unsupported.
  Rationale: Both accepted atom forms already normalize to `TypedPureComparison`; exhaustive
  evaluation handles them uniformly. Descending through `PNot` would change the extraction
  rules and is unnecessary for the motivating pair.
  Date: 2026-08-21

- Decision: Keep the exact-domain representation internal and keep all public validation and
  runtime signatures unchanged.
  Rationale: This is an additive precision improvement to the existing pure proof, not a public
  domain-declaration feature. Unknown carriers must retain the existing diagnostic and behavior.
  Date: 2026-08-21

- Decision: Defer Hackage publication, Keiro bound adoption, and Rei's opt-out removal to the
  release and consumer plans that already own those repositories.
  Rationale: This plan can prove producer correctness with a faithful local fixture and dependent
  audit. Publishing packages or mutating a consumer repository would expand the user's
  implementation request and require coordinated release authority.
  Date: 2026-08-21


## Outcomes & Retrospective

Milestone 1 established the executable safety baseline without changing production code. The
motivating Bool pair still warns for exactly the expected missing-domain reason, while the
overlap and unregistered-carrier controls demonstrate that later suppression must remain narrow.

Milestone 2 delivered the smallest production change promised by the plan: closed Bool discovery
and exhaustive evaluation of the existing concrete comparison closures. The same focused group
now proves the complementary pair clean under default validation without weakening either
conservative control.

Milestone 3 exercised every ordered pair of equality and ordering atoms over the complete Bool
domain. Suppression agreed with direct concrete guard evaluation in both edge modes, every
suppressed pair admitted at most one concrete replay candidate, and negation remained outside the
extracted fragment unless a separate supported contradiction was sufficient.


## Context and Orientation

Keiki is a pure Haskell symbolic-register transducer library. A transducer edge has a guard,
register update, ordered output events, target vertex, and mode. During streaming replay,
`applyEventKernel` in `src/Keiki/Core.hs` examines all outgoing edges from the current vertex
in the selected live/replay-only phase. For each edge it inverts only the first observed event
through `solveOutput`, then evaluates the edge guard with `models` against the same pre-event
`RegFile` and that edge's recovered command. Two matching edges are a runtime
`ReplayAmbiguousInversions` failure. Updates and output tails are evaluated only after one edge
has been selected.

`inversionAmbiguityWarnings` is the default, solver-free build-time approximation of that
candidate selection. It compares same-source, same-mode heads and calls
`analyzeCandidateRegisterConstraints` on their guards. The analyzer walks only conjunction
(`PAnd`) spines. It retains register-versus-literal `PEq` and `PCmp` atoms as necessary
conditions and drops command-constructor atoms. Disjunction, negation, projections, arithmetic,
input fields, and opaque applications become precision blockers. Dropping a sibling conjunct is
a weakening: every real candidate still satisfies the retained condition, so an unsatisfiable
retained conjunction proves the full candidates disjoint.

The implementation added by
[Plan 85](85-prove-replay-inverse-candidates-disjoint-from-shared-register-conjuncts.md) lives in
`src/Keiki/Core.hs`. `RegisterComparison` existentially stores a structural register variable,
relation, literal, and comparison closure. `alignRegisterComparison` uses `eqTypeRep` to put
one register group's values at a common type. `knownRegisterComparison` currently rejects every
carrier not recognised by `discoverIntegralDomain`.
`registerComparisonGroupVerdict` uses `integralComparisonsSatisfiable` for recognised
integrals. `analyzeCandidateRegisterConstraints` suppresses a warning only if some group is
`RegisterConstraintsUnsatisfiable`; every unknown result retains it with an actionable detail.

`TypedPureComparison`, `discoverIntegralDomain`, and
`integralComparisonsSatisfiable` are shared with the pure forward-overlap proof later in
`src/Keiki/Core.hs`. The new exact finite helper may share `TypedPureComparison`, but it must
not change the forward proof's polarity: that proof uses a concrete literal only to establish
that overlap exists, whereas this plan exhausts an entire trusted domain before establishing
that overlap is absent.

Tests for the current proof and a concrete replay-candidate counter live in
`test/Keiki/ValidationReplayAlignmentSpec.hs`. Its existing `unsupportedCarrierFixture` uses
complementary Bool equalities and expects the warning IR-9 now removes. Replace or rename that
fixture; retain an unsupported-carrier regression using an unregistered non-integral type.
`test/Keiki/ReplayOnlySpec.hs` covers same-mode replay-only and live-first phase behavior.
`test/Keiki/FullSymbolicReplayInversionSpec.hs` covers the optional SBV/Z3 checker and must keep
showing that default validation starts no solver.

The consumer evidence is in `mori://shinzui/rei/packages/rei-core`, in the project-relative
modules `rei-core/src/Rei/Modules/Intention/Domain/RootTransducer.hs` and
`rei-core/src/Rei/Modules/Intention/Domain/IntentionEventStream.hs`. Rei's adoption work is
`mori://shinzui/rei/plans/206-author-the-rei-service-workspace-at-keiro-dsl-language-5`, finding
S30 and Milestone 6. These are evidence, not build dependencies.

Three local ADRs govern the work:

- [ADR-0001](../adr/0001-structural-re-indexing-for-sound-replay.md) requires proof identity to
  use structural position and type rather than labels. This plan does not change
  `RegisterVariable` or grouping identity.
- [ADR-0002](../adr/0002-event-logs-must-reproduce-forward-state.md) requires default-validated
  persisted models to replay their forward logs. Warning suppression must therefore agree with
  the concrete replay candidate kernel.
- [ADR-0003](../adr/0003-proof-gates-fail-conservatively.md) allows suppression only for a
  definite proof of emptiness. Missing exact-domain evidence, malformed alignment, or an
  unsupported guard remains unknown.


## Plan of Work

Milestone 1 makes the consumer failure and safety controls executable before changing the proof.
In `test/Keiki/ValidationReplayAlignmentSpec.hs`, rename the current unsupported Bool fixture to
describe the complementary Bool case and assert that it initially produces the documented
unsupported-carrier warning. Make both edges invert the same head into the same command
constructor, matching Rei rather than relying on different reconstructed constructors. Add a
same-head control whose guards are `flag == True` and `PTop`; at register value `True`, the
existing concrete candidate counter must return two.
Add an unregistered-carrier fixture, preferably a small local type with `Eq`, `Ord`, `Show`,
and `Typeable` but no producer-owned domain entry, so the unchanged diagnostic is not coupled to
Bool. Run the focused module and record the baseline example count. Milestone 1 is complete when
the disjoint case still fails only because Bool is unsupported and both conservative controls
pass.

Milestone 2 adds the exact finite-domain proof in `src/Keiki/Core.hs`. Define an internal
`ExactFiniteDomain r` whose inhabitant collection is non-empty by construction, using
`Data.List.NonEmpty.NonEmpty`. Add
`discoverExactFiniteDomain :: Typeable r => Maybe (ExactFiniteDomain r)`; its only branch must
compare `typeRep @r` with `typeRep @Bool` and use `HRefl` to return
`False :| [True]`. Do not add an `Enum`, `Bounded`, or public declaration constraint.

Add `exactFiniteComparisonsSatisfiable`, which returns true exactly when at least one listed
inhabitant satisfies every `typedPureAccepts` closure in the aligned group. Update
`knownRegisterComparison` to admit a comparison when either integral or exact-finite discovery
succeeds. Update `registerComparisonGroupVerdict` to retain the current integral interval path,
then use exact finite exhaustion, then return unknown. Do not change blocker precedence:
`RegisterConstraintsUnsatisfiable` may still dominate an unsupported sibling because the
supported contradiction is a necessary condition, while absent domain evidence never proves
unsatisfiability. Milestone 2 is complete when the complementary Bool warning disappears, the
`PTop` and unregistered controls still warn, and no public signature changes.

Milestone 3 proves the new polarity exhaustively. In
`test/Keiki/ValidationReplayAlignmentSpec.hs`, represent the ten structural Bool
register-versus-literal atoms: `PEq`, `CmpLt`, `CmpLe`, `CmpGt`, and `CmpGe`, each at
`False` and `True`. For every pair, build the trusted same-head fixture and enumerate both
register values. Assert that a warning is suppressed if and only if no value satisfies both
guards concretely. For every suppressed pair, enumerate representative observed events and both
`Live` and `ReplayOnly` modes and assert that the concrete candidate count never exceeds one.
Keep named examples for `True` versus `False`, `flag < True` versus `flag == True`, and
`flag <= True` versus `flag == True` so failures are readable.

Also assert that `PNot (PEq flag (TLit ...))` remains a blocker naming `PNot`, and that an
independent supported Bool contradiction may still suppress a warning when that negation is a
sibling conjunction. Extend `test/Keiki/ReplayOnlySpec.hs` only if its existing helper cannot
exercise the Bool domain in both phase modes; preserve all cross-mode exemptions. Run the optional
symbolic inversion suite as a non-regression check. Milestone 3 is complete when the exhaustive
matrix agrees exactly with concrete guard evaluation and every conservative control remains.

Milestone 4 documents the delivered boundary. Update the Haddock above
`inversionAmbiguityWarnings` and the nearby private proof types in `src/Keiki/Core.hs`.
Update `docs/foundations/07-replay-verification-and-trusted-events.md` and `CHANGELOG.md` to
state that default validation uses exact integral intervals plus producer-owned Bool exhaustion.
The prose must explicitly reject arbitrary `Enum` and unregistered equality anchoring.

Update [ADR-0002](../adr/0002-event-logs-must-reproduce-forward-state.md) and
[ADR-0003](../adr/0003-proof-gates-fail-conservatively.md) because the durable supported proof
fragment changes. Preserve their `docId` values, advance their timestamps, add plan 90 to their
plan lists, and update `docs/adr/log.md` through the profiled workflow. Change IR-9 from
`planned` to `implemented` only after all implementation gates pass, advance its timestamp,
and update `docs/improvement-requests/log.md`. Publication remains pending, so do not mark it
`released`.

Milestone 5 runs complete validation and audits consumers without editing them. Use Mori to list
registered dependents and locate exact warning allowlists or validation overrides. The known Rei
override is expected to remain until a released Keiki version is adopted; record it in
Surprises & Discoveries rather than deleting it here. Run formatting, build, full tests, Haddock,
flake checks, strict ADR validation, the improvement-request profile check, and
`git diff --check`. Complete Progress, Surprises & Discoveries, Decision Log, and Outcomes &
Retrospective with actual counts and promote any new durable lesson to the relevant ADR before
marking the plan complete.


## Concrete Steps

Run every Keiki command from `/Users/shinzui/Keikaku/bokuno/keiki`. Start by preserving
unrelated work and rediscovering the relevant symbols:

```bash
git status --short
rg -n "knownRegisterComparison|registerComparisonGroupVerdict|discoverIntegralDomain|TypedPureComparison|unsupportedCarrierFixture" src/Keiki/Core.hs test/Keiki/ValidationReplayAlignmentSpec.hs
```

After Milestone 1 and after each proof change, run the focused replay-alignment group. Use two
`--test-option` arguments so Cabal does not split the multi-word Hspec match:

```bash
nix develop -c cabal test keiki-test \
  --test-option=--match \
  --test-option='shared-register replay candidate disjointness' \
  --test-show-details=direct
```

The pre-implementation run should include a named example showing the Bool warning. After
Milestone 2, the same group should report zero failures and the named complementary example
should expect no warning.

Run the full containing module so a mistakenly empty focused selector cannot count as evidence:

```bash
nix develop -c cabal test keiki-test \
  --test-options='--match=ValidationReplayAlignmentSpec' \
  --test-show-details=direct
```

The plan-creation baseline was:

```text
Finished in 0.0032 seconds
27 examples, 0 failures
```

Run phase and optional-solver non-regression groups:

```bash
nix develop -c cabal test keiki-test \
  --test-option=--match \
  --test-option='replay-only' \
  --test-show-details=direct

nix develop -c cabal test keiki-test \
  --test-option=--match \
  --test-option='full symbolic replay inversion' \
  --test-show-details=direct
```

For the dependent audit, use Mori rather than guessing checkout locations:

```bash
mori registry dependents shinzui/keiki --packages
mori path mori://shinzui/rei/packages/rei-core
```

Search each relevant resolved project path narrowly for
`checkInversionAmbiguity = False`, `InversionAmbiguity`, and
`unsupported register carrier Bool`. Do not search `/` or `/nix/store`, and do not edit a
dependent in this plan.

After documentation, run all producer gates:

```bash
nix fmt -- --no-cache
nix develop -c cabal build all
nix develop -c cabal test all --test-show-details=direct
nix develop -c cabal haddock all
nix flake check
just adr-validate
okf validate docs/improvement-requests \
  --strict \
  --profile mori/improvement-requests-profile.dhall \
  --profile-enforce \
  --log-enforce
git diff --check
git status --short
```

The expected result is zero build/test/Haddock/flake failures, strict ADR acceptance, no new
improvement-request profile errors, and a final diff containing only the files named by this
plan. If the improvement-request validator still reports the repository's already-recorded
status-vocabulary mismatch for older concepts, record the exact unchanged diagnostics and do not
weaken the profile.


## Validation and Acceptance

The primary observable is a trusted same-head fixture with a single `Bool` register. With guards
`flag == True` and `flag == False`, `inversionAmbiguityWarnings` and
`validateTransducer defaultValidationOptions` return no `InversionAmbiguity`. Forward commands
from both initial values emit logs that strict replay accepts and reproduce the same vertex and
register file.

Changing the second guard to `PTop` restores one warning. At `flag == True`, the concrete
candidate counter returns two for the shared observed head, proving the retained warning predicts
a real ambiguous inversion. An unregistered non-integral carrier also retains one warning whose
detail includes the unchanged text `unsupported register carrier` and its type.

The exact Bool relation matrix covers equality and all four ordering relations at both literals.
For each pair, warning suppression is equivalent to the absence of a concrete shared witness in
`[False, True]`. Every suppressed pair has at most one concrete replay candidate across both
modes and representative observed events. The named ordering examples demonstrate both
directions: `flag < True` versus `flag == True` is suppressed; `flag <= True` versus
`flag == True` is retained.

`PNot`, including the AST produced by `./=`, remains unsupported and names `PNot` when it is
the blocker. Opaque applications, disjunction, arithmetic, projections, input-field reads,
duplicate register labels, type mismatches, literal bottom, head classification, and phase
selection retain their existing behavior. The full symbolic checker tests pass unchanged, and
default validation makes no solver call.

No public constructor, type, option, or function signature changes. `RegFile`, `HsPred`,
`validateTransducer`, `inversionAmbiguityWarnings`, and
`TransducerValidationWarning.InversionAmbiguity` remain source-compatible. Runtime
`applyEventKernel`, `solveOutput`, updates, and tail handling are untouched.

Documentation states the actual trust boundary: Keiki owns the complete standard Bool list;
arbitrary `Bounded`/`Enum` and unregistered `Eq` types supply no emptiness evidence.
IR-9 ends as `implemented`, not `released`. Rei's three-warning baseline and opt-out remain
recorded for the later release/adoption step.


## Idempotence and Recovery

All searches, builds, tests, and validators are safe to rerun. Inspect `git status --short`
before each edit and preserve unrelated user changes. Make narrow changes with `apply_patch`;
never reset the worktree or replace a whole user-modified file.

The implementation is additive until the old Bool unsupported expectation is renamed. Add the
new fixtures first, then add exact-domain discovery, then update assertions. If a focused test
fails, keep the warning rather than weakening the verdict: returning
`RegisterConstraintsUnknown` is always the safe recovery. Never recover from a type-alignment
problem with `unsafeCoerce`, and never fall back to `[minBound .. maxBound]`.

If the shared `TypedPureComparison` helper makes the forward-overlap proof regress, keep the new
finite satisfiability function local to the register-disjointness path or factor only the
closure-evaluation primitive whose polarity is explicit. The forward proof may use a found
witness to prove satisfiability; it must not reuse a failed non-exhaustive witness search as proof
of unsatisfiability.

Profiled log commands may warn about a stale local OKF index, as prior plans record. The strict
profile validators are authoritative. Preserve stable `ADR-2`, `ADR-3`, and `IR-9` handles;
never allocate replacements. Release commands are not recoverable implementation steps and are
outside this plan.


## Interfaces and Dependencies

The implementation uses only `base` facilities already available to the `keiki` library:
`Type.Reflection.eqTypeRep`, `typeRep`, `HRefl`, and
`Data.List.NonEmpty.NonEmpty`. It adds no Cabal dependency and does not use SBV or Z3.

The internal shape in `src/Keiki/Core.hs` should be equivalent to:

```haskell
data ExactFiniteDomain r = ExactFiniteDomain
  { exactFiniteValues :: NonEmpty r
  }

discoverExactFiniteDomain ::
  forall r. (Typeable r) => Maybe (ExactFiniteDomain r)
discoverExactFiniteDomain
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Bool) =
      Just (ExactFiniteDomain (False :| [True]))
  | otherwise = Nothing

exactFiniteComparisonsSatisfiable ::
  ExactFiniteDomain r -> [TypedPureComparison r] -> Bool
```

Exact names may follow the surrounding private vocabulary, but these contracts are fixed:
discovery is a closed `Bool` match, the list is non-empty and producer-owned, and
satisfiability is existential over every listed inhabitant while each inhabitant is checked
against every comparison closure.

`knownRegisterComparison` remains internal with its current public invisibility. It admits a
comparison exactly when `discoverIntegralDomain` or `discoverExactFiniteDomain` succeeds.
`registerComparisonGroupVerdict` retains its signature:

```haskell
registerComparisonGroupVerdict ::
  [RegisterComparison] -> RegisterConstraintVerdict
```

It returns `RegisterConstraintsUnsatisfiable` for an aligned Bool group only when exhaustive
evaluation finds no witness. `RegisterConstraintsSatisfiable` means at least one Bool value
satisfies the group. Every unregistered or unaligned group returns
`RegisterConstraintsUnknown`.

The public interfaces remain unchanged:

```haskell
inversionAmbiguityWarnings ::
  (Bounded s, Enum s, Show s) =>
  SymTransducer (HsPred rs ci) rs s ci co ->
  [TransducerValidationWarning s]

validateTransducer ::
  (Bounded s, Enum s, Ord s, Show s) =>
  ValidationOptions ->
  SymTransducer (HsPred rs ci) rs s ci co ->
  [TransducerValidationWarning s]
```

The cross-repository consumer is identified canonically as
`mori://shinzui/rei/packages/rei-core`; it is not added as a package dependency. Authoritative
release verification continues to use Hackage and `mori://shinzui/keiki/repos/keiki`, but
publication is outside this ExecPlan.
