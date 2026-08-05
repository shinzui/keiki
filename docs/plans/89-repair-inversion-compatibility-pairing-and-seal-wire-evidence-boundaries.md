---
id: 89
slug: repair-inversion-compatibility-pairing-and-seal-wire-evidence-boundaries
title: "Repair inversion compatibility pairing and seal wire evidence boundaries"
kind: exec-plan
created_at: 2026-08-05T01:39:52Z
intention: "intention_01kz715z62ennb1m6eg94a59vk"
---

# Repair inversion compatibility pairing and seal wire evidence boundaries

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

After this change, the defects found by the 2026-08-04/05 four-dimension soundness review of
[Plan 87](87-add-structural-wire-schemas-for-optional-symbolic-replay-inversion.md),
[Plan 85](85-prove-replay-inverse-candidates-disjoint-from-shared-register-conjuncts.md), and
[Plan 88](88-add-structural-input-constructor-evidence-for-composition-and-symbolic-alignment.md)
are repaired, so the pre-release breaking line is sound end to end:

1. `checkInversionAmbiguitySym` stops matching solver verdicts to warnings by positional zip over
   a non-isomorphic pair enumeration. A demonstrated misalignment let one pair's UNSAT proof
   suppress a different, genuinely ambiguous pair's warning, and the common fail-closed case
   silently disabled suppression transducer-wide. After the fix, a verdict can only ever remove
   the warning for the exact source-and-edges pair it proved.
2. Trusted evidence can no longer be decoupled from behavior by record update: replacing
   `wcMatch`/`wcBuild` (or `icMatch`/`icBuild`) while keeping a trusted schema becomes a compile
   error, renaming keeps evidence through a sanctioned helper, and manual construction goes
   through explicit unavailable constructors.
3. The one remaining `unsafeCoerce` in schema alignment (the composition-only identity case) is
   replaced by a typed spine whose GADT refinement proves the same equality, so alignment code
   contains no casts at all, fully honoring ADR-0001.
4. The review's minor gaps close: stale Profunctor Haddocks describing the removed name-based
   substitution rule, the untested unwitnessed-composition failure path, and the manual-only
   compile-fail fixtures.

Item 2 is a source break, so this plan belongs to the same local breaking-work sequence as Plans
87/88: no version selection, no downstream migration; the future user-authored release plan owns
the coordinated rollout after all breaking ExecPlans are complete. No new improvement request is
filed: this plan repairs unreleased local work delivered by Plans 85/87/88 rather than
implementing a new consumer-facing request.


## Progress

- [x] (2026-08-05) Plan created from the recorded four-dimension review results; reproducers for
      the compatibility-projection defect were demonstrated against the built library during
      review and are captured in Surprises & Discoveries.
- [x] (2026-08-05T01:51:31Z) Milestone 1: repaired the compatibility projection with
      source-and-edge keyed verdict matching, derived solver candidates from the canonical pure
      warning keys, and added both positional-misalignment regressions. Corrected focused command
      passed with 16 examples and 0 failures.
- [ ] Milestone 2: seal the `WireCtor`/`InCtor` construction and update boundary with
      unidirectional record pattern synonyms, explicit unavailable constructors, and
      evidence-preserving rename helpers; migrate in-tree uses.
- [ ] Milestone 3: replace the composition-only alignment coercion with a typed prefix spine.
- [ ] Milestone 4: sweep the minor review findings (Haddocks, unwitnessed-composition test,
      compile-fail automation).
- [ ] Milestone 5: update changelog, plan/ADR records, and run all gates.


## Surprises & Discoveries

- Observation: `checkInversionAmbiguitySym` pairs verdicts with warnings positionally while the
  two enumerations diverge. `inversionCandidatePairs` filters by `wcName` equality
  (`src/Keiki/Symbolic.hs:1591`) but `inversionAmbiguityWarnings` filters by
  `wireHeadsMayAliasForDefault` and additionally drops register-proven pairs
  (`src/Keiki/Core.hs:3258,3261`); the "intentionally isomorphic" comment
  (`src/Keiki/Symbolic.hs:1559-1562`) has been false since Plans 85/87 landed.
  Evidence: reproduced against the built library during review. Fail-closed direction: a
  transducer with one register-proven pair produced 5 warnings versus 6 details, so the length
  guard (`src/Keiki/Symbolic.hs:2253-2260`) retained all warnings, including three whose details
  were `InversionProvedDisjoint`. Unsound direction: a register-proven pair at one vertex plus a
  structurally-aliasing pair at another whose second edge used a renamed wire copy (present in
  warnings via structural may-alias, absent from details because of the `wcName` filter)
  produced equal-length lists whose zip suppressed the genuine ambiguity's warning with the
  unrelated pair's UNSAT verdict.

- Observation: GHC record update does not require the data constructor in scope — exported record
  fields alone make `trustedWire { wcMatch = dishonest }` compile, silently rebinding trusted
  evidence to closures it no longer describes.
  Evidence: `WireCtor (..)`/`InCtor (..)` are exported with fields from `Keiki.Core`; the review
  noted `test/Keiki/SymbolicSpec.hs:41-46` already relies on record update for `icName`
  relabeling, which is the one evidence-safe update now that names are diagnostics only.

- Observation: the composition-only alignment case carries the only cast in schema-alignment
  code. `src/Keiki/Internal/WireSchema.hs:443-447` uses `unsafeCoerce` to equate two skolem
  field types when two composition-only schemas share equal paths, justified in prose
  (composition-only evidence is mintable only at root with `fields` equal to `(carrier, ())`;
  prefixes preserve the relationship). The trusted-Generic path needs no cast because its field
  spine yields honest `Typeable` equalities per position.
  Evidence: review of `compareInCtorWireSchemas` and the composition-only constructors; the
  prose invariant is exactly the shape a typed prefix GADT can carry.

- Observation: Cabal splits the plan's quoted `--test-options='--match=full symbolic replay
  inversion'` value before Hspec receives it, producing `unexpected argument 'symbolic'`.
  Evidence: the first Milestone 1 validation compiled successfully but ran zero examples and
  failed at argument parsing. Passing the filter as two Cabal options,
  `--test-option=--match --test-option='full symbolic replay inversion'`, ran 16 examples with
  0 failures. Use the split form for every focused command whose match contains spaces.


## Decision Log

- Decision: Match solver details to warnings by identity key — source vertex plus both edge
  indices — rather than repairing the positional zip by making the enumerations isomorphic again.
  Rationale: Keyed matching is correct under any future drift between the enumerations, whereas
  isomorphism is an invariant nobody enforces (it already rotted once, silently). The pair
  enumeration itself should still adopt the warnings' predicate so the solver does not waste work
  on pairs that can never carry a warning, but correctness must not depend on it.
  Date: 2026-08-05

- Decision: Seal construction and update with unidirectional record pattern synonyms named
  exactly `WireCtor`/`InCtor` (pattern matching and field selection stay source-compatible),
  plus explicit `unavailableWireCtor`/`unavailableInCtor` manual constructors and
  evidence-preserving `renameWireCtor`/`renameInCtor`.
  Rationale: Unidirectional synonyms reject construction and record update at the type level,
  closing the decoupling hole while keeping every legitimate consumer operation. Renaming is
  provably evidence-safe now that names are diagnostics only; behavioral replacement is forced
  through the unavailable constructors, which is the correct semantics — new behavior inherits no
  evidence. This supersedes the "direct record with explicit unavailable schema" migration idiom
  from Plans 87/88 before any external consumer adopts it.
  Date: 2026-08-05

- Decision: Give composition-only evidence a typed prefix spine (root constructor pinning
  `fields ~ (carrier, ())`, Left/Right prefix constructors carrying the `Either` structure) and
  derive the alignment equality by lockstep GADT refinement, deleting the `unsafeCoerce`.
  Rationale: Both schemas in an alignment share the same outer carrier, so matched prefix steps
  refine both inner carriers together and the roots discharge the field equality with no cast.
  The prose soundness argument becomes unnecessary instead of merely reviewed.
  Date: 2026-08-05

- Decision: Wire both compile-fail fixtures into an automated gate (a recipe that invokes GHC
  with `-fno-code` on each fixture and asserts failure at the expected message), extended with a
  new fixture asserting record update of a trusted wire is rejected.
  Rationale: A compile-failure boundary that no gate executes is documentation, not enforcement;
  the review found both existing fixtures unreferenced by any runner.
  Date: 2026-08-05

- Decision: File no new improvement request for this plan.
  Rationale: Every item repairs or hardens unreleased local work produced by Plans 85/87/88; the
  IR bundle tracks consumer-facing requests, and IR-5/IR-6 already record the features these
  repairs protect. The review evidence lives in this plan's Surprises & Discoveries.
  Date: 2026-08-05

- Decision: Build the symbolic candidate set from the canonical warning keys and retain a warning
  unless exactly one matching detail carries both `InversionSolverUnsatisfiable` and
  `InversionProvedDisjoint`.
  Rationale: Reusing the pure warning result guarantees the solver analyzes precisely the pairs
  eligible for compatibility suppression without exporting the pure register-analysis internals.
  Requiring a unique matching detail makes accidental duplicate analysis fail closed.
  Date: 2026-08-05


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Plans 85, 87, and 88 landed a coordinated local breaking line: `WireCtor` and `InCtor` carry
abstract trusted/unavailable structural schemas (hidden module
`src/Keiki/Internal/WireSchema.hs`, listed under `other-modules` in `keiki.cabal`), default
validation suppresses inversion-ambiguity warnings only on a pure shared-register
unsatisfiability proof (`inversionAmbiguityWarnings`, `src/Keiki/Core.hs:3221-3262`), and
`Keiki.Symbolic` provides the opt-in dual-candidate checker
(`checkInversionAmbiguitySymDetailed` and `checkInversionAmbiguitySym`,
`src/Keiki/Symbolic.hs:2246-2260`). A four-dimension review on 2026-08-04/05 verified the
soundness core of all three plans — variable scoping, the unconstrained invertible output
positions, the prefix/divergence path rule, extraction polarity, checked composition alignment,
symbolic fallback polarity — and found the defects this plan owns; the evidence is recorded in
Surprises & Discoveries above.

Definitions used below. A "warning pair" is one `InversionAmbiguity` value identified by its
source vertex `tvwSource` and edge indices `tvwEdgeA`/`tvwEdgeB` (`src/Keiki/Core.hs:2567-2573`).
A "detail" is one `InversionAnalysisDetail` from the detailed checker carrying the same
identifying refs plus schema availability, translation issues, solver status, and verdict. The
compatibility projection must return exactly the pure warnings minus those whose *own* detail is
`InversionProvedDisjoint` with a definite `Unsatisfiable` solver status.

The construction boundary today: `Keiki.Core` exports `WireCtor (..)` and `InCtor (..)` with
record fields. GHC permits record update whenever the fields are in scope, without the data
constructor, so exported fields alone allow `wc { wcMatch = f }`. The trusted schema field is
abstract and non-forgeable (nominal roles, hidden constructors, sealed Generic classes — verified
by review), but nothing ties it to the closures beside it after an update. `InCtor` is a GADT
whose constructor carries `AssembleRegFile ifs` and `KnownSlotNames ifs`; pattern synonyms over
such constructors expose those as provided constraints when matching.

Relevant ADRs: [ADR-0001](../adr/0001-structural-re-indexing-for-sound-replay.md) forbids names
and casts as replay evidence — Milestone 3 removes the last alignment cast, and Milestone 2
closes an evidence/behavior decoupling that would let a cast-free forgery arise by update.
[ADR-0003](../adr/0003-proof-gates-fail-conservatively.md) requires that only definite proofs
suppress — Milestone 1 restores that contract for the compatibility projection, whose current
misalignment can suppress on the wrong pair's proof.
[ADR-0004](../adr/0004-composition-uses-snapshot-updates-and-checked-boundaries.md) requires
checked structural boundaries in composition — Milestone 3 strengthens the checked boundary's
implementation, and Milestone 4 tests its unwitnessed arm. No new ADR is expected; amend these
three only if implementation changes their recorded shape.


## Plan of Work

Milestone 1 repairs the compatibility projection in `src/Keiki/Symbolic.hs`. Give every
`InversionAnalysisDetail` an identity key equal to the warning identity (source vertex, edge A
index, edge B index, normalized to the warnings' pair order). Reimplement
`checkInversionAmbiguitySym` to start from the pure `inversionAmbiguityWarnings` result and
remove a warning only when a detail with the *same key* reports `InversionProvedDisjoint` under
a definite `Unsatisfiable`; delete the length-equality guard and the positional zip. Update
`inversionCandidatePairs` to enumerate with the warnings' own predicate
(`wireHeadsMayAliasForDefault` plus the same mode, non-bottom, and non-empty-output filters and
the register-proof drop) so the solver analyzes exactly the pairs that can carry warnings;
correct the stale "intentionally isomorphic" comment to state the keyed contract instead. In
`test/Keiki/FullSymbolicReplayInversionSpec.hs`, add the two review reproducers as regression
fixtures: (a) a transducer combining one register-proven pair with solver-provable pairs, where
compatibility must now remove exactly the solver-proved warnings; (b) the equal-length
misalignment shape — a register-proven pair at one vertex plus a renamed-wire structural pair at
another — where the genuine ambiguity's warning must be retained. Assert in both that every
removed warning's key has a matching definite-UNSAT detail. Both fixtures must fail under the
old positional-zip implementation.

Milestone 2 seals the construction boundary in `src/Keiki/Core.hs`. Stop exporting the real
`WireCtor`/`InCtor` data constructors and record fields; export unidirectional record pattern
synonyms with the existing names and fields so matching and selection remain source-compatible,
plus `unavailableWireCtor :: String -> (co -> Maybe fs) -> (fs -> co) -> WireCtor co fs`,
`unavailableInCtor` (carrying the GADT constraints), `renameWireCtor :: String -> WireCtor co fs
-> WireCtor co fs`, and `renameInCtor`, where the rename helpers preserve the schema and the
unavailable constructors always stamp unavailable evidence. Trusted producers in
`src/Keiki/Generics.hs`, TH, composition, and profunctor code keep using the internal real
constructor. Migrate every in-tree direct record construction and record update: manual records
become `unavailableWireCtor`/`unavailableInCtor` calls, and the `icName` relabel sites in
`test/Keiki/SymbolicSpec.hs` use `renameInCtor`. Update the two existing compile-fail fixtures to
the new idiom and add `test/compile-fail/TrustedWireCtorUpdate.hs` proving `wc { wcMatch = ... }`
on a trusted wire no longer compiles. Update the changelog migration notes that named the old
direct-record idiom.

Milestone 3 removes the alignment cast in `src/Keiki/Internal/WireSchema.hs`. Replace the
path-list representation of composition-only evidence with a typed spine: a root constructor
whose type pins `fields ~ (carrier, ())`, and Left/Right prefix constructors typed over the
`Either` carrier structure, constructed by the existing `compositionOnly*Schema` and
`prefix*Left/Right` entry points so `src/Keiki/Composition.hs` and `src/Keiki/Profunctor.hs`
call sites do not change shape. Reimplement the composition-only arm of the alignment by
lockstep recursion on the two spines: matched prefix steps refine both inner carriers together,
the roots discharge the field-type equality by GADT refinement, and the `unsafeCoerce` at the
former `src/Keiki/Internal/WireSchema.hs:443-447` is deleted. Path comparison semantics
(equal, diverge at a common index, prefix-related) and the public availability behavior must be
observably unchanged; the existing WireSchema, InputSchema, Composition, Category, Choice, and
Profunctor suites plus the identity-alignment law tests are the guard.

Milestone 4 sweeps the minor findings. Rewrite the four stale Haddock sites in
`src/Keiki/Profunctor.hs` (approximately lines 153-159, 508-517, 840-847, and 899-904) that
still describe `icName ic2 == wcName wc1` as the substitution mechanism, stating the typed
input-to-wire alignment rule instead. Add the missing unwitnessed-composition test to
`test/Keiki/CompositionAlignmentSpec.hs`: compose a manual (unavailable-evidence) `InCtor`
against a manual wire and assert the `UnwitnessedInputWireAlignment` diagnostic, the
poison/`PBot` guard leaf, and that `composeChecked` fails Left. Automate the compile-fail
fixtures: a `just compile-fail-check` recipe (wired into the flake check or the default gate
set) that runs GHC with `-fno-code` over every file in `test/compile-fail/` and asserts each
fails mentioning its expected token (`wcSchema`, `icSchema`, and the new update-rejection
message).

Milestone 5 closes the record. Update `CHANGELOG.md`'s `[Unreleased]` section: the compatibility
repair, the sealed construction boundary with its new manual idiom, the rename helpers, and the
cast removal. Fill this plan's Outcomes section; amend ADR-0001/0003/0004 only if their recorded
shapes changed, through the profiled ADR workflow. Run the full gates and record counts in
Progress.


## Concrete Steps

Run from `/Users/shinzui/Keikaku/bokuno/keiki`. Before each milestone:

```bash
git status --short
rg -n "inversionCandidatePairs|checkInversionAmbiguitySym|intentionally isomorphic" src/Keiki/Symbolic.hs
rg -n "WireCtor \(\.\.\)|InCtor \(\.\.\)" src/Keiki/Core.hs
rg -n "unsafeCoerce" src/Keiki/Internal/WireSchema.hs src/Keiki/Composition.hs
```

Focused milestone tests (sequential; the active Hspec does not interpret `|` as alternation):

```bash
nix develop -c cabal test keiki-test --test-options='--match=full symbolic replay inversion' --test-show-details=direct
nix develop -c cabal test keiki-test --test-options='--match=Symbolic' --test-show-details=direct
nix develop -c cabal test keiki-test --test-options='--match=WireSchema' --test-show-details=direct
nix develop -c cabal test keiki-test --test-options='--match=InputSchema' --test-show-details=direct
nix develop -c cabal test keiki-test --test-options='--match=CompositionAlignment' --test-show-details=direct
nix develop -c cabal test keiki-test --test-options='--match=Profunctor' --test-show-details=direct
nix develop -c cabal test keiki-test --test-options='--match=ValidationReplayAlignmentSpec' --test-show-details=direct
just compile-fail-check
```

Each transcript must end with its actual example count and `0 failures` (or, for
`compile-fail-check`, one expected-failure line per fixture); record counts in Progress. Full
gates:

```bash
nix fmt -- --no-cache
nix develop -c cabal build all
nix develop -c cabal test all --test-show-details=direct
nix develop -c cabal haddock all
nix flake check
just adr-validate
just compile-fail-check
git diff --check
```

Every commit carries:

```text
ExecPlan: docs/plans/89-repair-inversion-compatibility-pairing-and-seal-wire-evidence-boundaries.md
Intention: intention_01kz715z62ennb1m6eg94a59vk
```

Do not select versions, publish packages, create or push tags, or edit dependent repositories;
the future user-authored release plan owns all of that.


## Validation and Acceptance

Compatibility projection: for the mixed fixture, `checkInversionAmbiguitySym` returns exactly
the pure warnings minus the pairs whose own details are definite UNSAT; for the misalignment
fixture, the genuine ambiguity's warning survives even though an unrelated pair is proved
disjoint; both fixtures fail under the old positional zip. No length guard remains; a missing
detail for a warning key always retains that warning. `checkInversionAmbiguitySymDetailed`
output for the shared fixtures is unchanged.

Construction boundary: existing pattern matches and field selections on `WireCtor`/`InCtor`
compile unchanged; record update and record construction outside Keiki fail to compile (the new
compile-fail fixture proves the update case); `renameWireCtor`/`renameInCtor` preserve trusted
evidence and behavior; `unavailableWireCtor`/`unavailableInCtor` always report unavailable. All
in-tree consumers, including jitsurei and both codec packages, build and pass against the sealed
exports.

Alignment: `rg -n "unsafeCoerce" src/Keiki/Internal/WireSchema.hs` returns nothing; the
composition-only identity law suites (Category identity, `arr` composition, Strong) pass
unchanged; prefix-related and divergent classifications are byte-identical to before on the
existing spec fixtures.

Minor sweep: the four Profunctor Haddock sites describe the typed alignment rule; the
unwitnessed-composition test asserts the diagnostic, the poison leaf, and `composeChecked`
failure; the compile-fail gate runs in the default gate set and fails if any fixture
unexpectedly compiles. All commands in Concrete Steps pass and `git diff --check` is clean.


## Idempotence and Recovery

All searches, builds, and tests are safe to rerun. Inspect `git status --short` before edits;
preserve user-owned changes; use narrow edits; never use destructive resets. If the pattern
synonym approach hits a GHC limitation for the `InCtor` GADT (provided-constraint or
record-syntax corner), fall back to exporting plain selector functions plus the smart
constructors, and record the substitution in the Decision Log — the acceptance criterion is that
update and construction are rejected, not the specific mechanism. If the typed composition-only
spine cannot express an existing construction site, stop and record the counterexample rather
than reintroducing a cast; the documented-prose coercion may remain only with an explicit
Decision Log entry stating why the typed form is impossible. If keyed matching surfaces a
warning with two details or a detail order dependency, prefer dropping the extra detail
conservatively (retain the warning) and record the cause.


## Interfaces and Dependencies

`Keiki.Symbolic` keeps the public signatures of `checkInversionAmbiguitySymDetailed` and
`checkInversionAmbiguitySym`; `InversionAnalysisDetail` may gain or expose the identity key
needed for matching, but must not gain `Eq ci` or `Eq co` constraints.

`Keiki.Core` exports, replacing the current constructor/field exports:

```haskell
pattern WireCtor
  :: String -> WireSchema co fields -> (co -> Maybe fields) -> (fields -> co)
  -> WireCtor co fields               -- unidirectional: match/select only

pattern InCtor
  :: () => (AssembleRegFile ifs, KnownSlotNames ifs)
  => String -> InCtorSchema ci ifs -> (ci -> Maybe (RegFile ifs)) -> (RegFile ifs -> ci)
  -> InCtor ci ifs                    -- unidirectional: match/select only

unavailableWireCtor :: String -> (co -> Maybe fs) -> (fs -> co) -> WireCtor co fs
unavailableInCtor
  :: (AssembleRegFile ifs, KnownSlotNames ifs)
  => String -> (ci -> Maybe (RegFile ifs)) -> (RegFile ifs -> ci) -> InCtor ci ifs
renameWireCtor :: String -> WireCtor co fs -> WireCtor co fs
renameInCtor :: String -> InCtor ci ifs -> InCtor ci ifs
```

Exact pattern-synonym signatures may be adjusted to GHC's checked form for record pattern
synonyms over GADTs; the behavioral requirements are fixed by Validation and Acceptance. The
typed composition-only spine stays inside `Keiki.Internal.WireSchema` (still an
`other-module`); its public observers (availability, classifiers, prefix helpers) keep their
signatures. No new package dependency; no version or bound changes; z3/SBV usage unchanged.
