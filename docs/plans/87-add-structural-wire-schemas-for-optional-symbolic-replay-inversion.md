---
id: 87
slug: add-structural-wire-schemas-for-optional-symbolic-replay-inversion
title: "Add structural wire schemas for optional symbolic replay inversion"
kind: exec-plan
created_at: 2026-08-04T18:39:44Z
intention: "intention_01kz715z62ennb1m6eg94a59vk"
---

# Add structural wire schemas for optional symbolic replay inversion

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

After this change, every inversion-capable generated Keiki event wire carries typed structural
evidence for its event constructor and its ordered fields. Keiki can use that evidence in an
explicit, opt-in SBV check that models two replay candidates against one register file and one
observed head event while keeping their reconstructed commands independent. An output-dependent
pair such as `amount == observedAmount` versus `amount + 1 == observedAmount` can therefore be
proved disjoint even when guard-only reasoning cannot distinguish it. Only a definite solver
`Unsatisfiable` result suppresses the compatibility warning; missing schemas, unsupported field
types, opaque terms, timeouts, and solver failures keep the warning.

The `WireCtor` record gains a schema field, so this is an intentional PVP-major Keiki change. This
plan lands and verifies that breaking work inside the Keiki repository only. It does not bump
package versions, change downstream bounds, prepare a release, or migrate Keiro and application
adopters. Plan 88 contains another public constructor-record change; after all breaking ExecPlans
are complete, a separate user-authored Keiki release plan will choose versions and own the single
coordinated downstream migration.

The observable proof lives in `test/Keiki/FullSymbolicReplayInversionSpec.hs`: the witnessed
output-dependent pair is `InversionProvedDisjoint`, the overlapping control is not proved
disjoint, and removing or poisoning the schema restores the existing warning. The ordinary
`validateTransducer defaultValidationOptions` path starts no solver and runtime replay remains
unchanged. After this plan is complete,
[Plan 85](85-prove-replay-inverse-candidates-disjoint-from-shared-register-conjuncts.md) adds only
the cheaper solver-free shared-register contradiction to default validation against the final
schema representation.


## Progress

- [x] (2026-08-04) Created the follow-up from Plan 86's research result, verified the current
      Keiki/Keiro release and reverse-dependent baselines, and fixed the ownership boundary with
      Plan 85.
- [x] (2026-08-04T20:03:12Z) Milestone 1: added nominally protected abstract structural
      wire-schema types, the source-breaking `WireCtor.wcSchema` field, three-way head
      classification, explicit trusted/unavailable paths, a proper-prefix regression observer,
      and the compile-failure fixture `test/compile-fail/OmittedWireSchema.hs`.
- [x] (2026-08-04T20:03:12Z) Milestone 2: made Generic and TH record/nullary producers trusted,
      preserved schemas through checked `Either` composition and Builder emission, dropped them
      through identity/Strong/Arrow/output-map profunctor paths, and migrated every in-tree manual
      `WireCtor` record to explicit unavailability. Focused results: Generics 27 examples,
      TH 27, WireSchema 10, Composition 60, Profunctor 68, and Builder 32; all reported
      0 failures.
- [x] (2026-08-04T20:40:48Z) Post-review addendum: the `DEPRECATED` pragmas landed with
      Milestone 4 and the numbered replay-verification foundations page landed with Milestone 5
      (recorded after Milestones 1–2 completed; see Decision Log).
- [x] (2026-08-04) Milestone 3: implemented the detailed opt-in dual-candidate symbolic
      checker and fail-conservative compatibility projection. Candidate command tags, arms,
      fields, projections, and opaque values are independent; register and structurally aligned
      observed-field caches are shared. Focused FullSymbolicReplayInversion result: 14 examples,
      0 failures; combined Symbolic result: 105 examples, 0 failures. The finite oracle found no
      double candidate for the output-dependent UNSAT pair. The manual non-CI 100-pair benchmark
      completed in 0.315 CPU seconds, below the Plan 86 per-pair baseline rather than a 3x regression.
- [x] (2026-08-04) Milestone 4: added local `DEPRECATED` guidance to the closure-taking wire
      helpers, documented the unreleased breaking migration, and compiled all in-tree Keiki,
      codec, test-support, and jitsurei packages without editing versions, bounds, or dependent
      repositories. Focused WireSchema and TH results remained 10 and 27 examples, 0 failures.
- [x] (2026-08-04T20:40:48Z) Milestone 5: updated local Haddocks and user/foundations guidance,
      amended ADR-0001/0003/0004/0005 through the strict workflow, refreshed IR-6/IR-7/IR-8 and their
      future-release handoff, and completed every local gate. Final full-suite counts were
      Keiki 681, codec 104, and jitsurei 127 examples (912 total), all with 0 failures;
      replay-alignment and recompute/verify focused counts were 18 and 9, both with 0 failures.
      `nix fmt`, `cabal build all`, `cabal haddock all`, `nix flake check`, `just adr-validate`,
      and `git diff --check` passed.


## Surprises & Discoveries

- Observation: `WireCtor co fields` currently contains only a diagnostic name and two
  consumer-owned closures. Equal `wcName` values and separately existential `OutFields` values do
  not prove that two head fields have the same type or position.
  Evidence: `src/Keiki/Core.hs` defines `WireCtor` with only `wcName`, `wcMatch`, and `wcBuild`;
  Plan 86's typed prototype had to invent a descriptor before it could share observed fields.

- Observation: `identityWireCtor` is polymorphic in its carrier and therefore cannot obtain the
  per-field `Typeable` evidence required by the solver without changing the categorical
  interface.
  Evidence: the category/profunctor implementation constructs identity wires without a
  `Typeable` constraint. This plan marks that schema unavailable instead of manufacturing
  evidence or adding an impossible constraint to `Category`.

- Observation: the Mori reverse-dependent result is broader than the actual application rollout.
  It currently reports twelve source projects, while the user reports two active applications and
  twenty-plus planned adopters.
  Evidence: `mori registry dependents shinzui/keiki --packages --json` on 2026-08-04. Preserve
  Mori's result as future release-plan inventory; do not infer active handles or begin migration
  from repository names in this plan.

- Observation: runtime `solveOutput` never verifies invertible output fields. `recomputeDerivedFields`
  keeps `TLit`, `TOpaqueLit`, `TReg`, and `TInpCtorField` positions at their observed values, so the
  rebuilt-equals-observed check passes for them unconditionally; only derived fields
  (`TArith`/`TApp1`/`TApp2`/`TFieldProj`) are recomputed and compared.
  Evidence: `src/Keiki/Core.hs` (`solveOutput` and `recomputeDerivedFields`), confirmed during the
  2026-08-04 soundness review of this plan;
  `docs/research/full-symbolic-replay-inversion-model.md` marks this absence of a constraint
  load-bearing for the symbolic model. A model that asserts `observed == literal` or
  `observed == currentRegister` is narrower than runtime candidacy and can prove falsely UNSAT.

- Observation: an abstract data constructor is not sufficient to seal trusted evidence when its
  parameters retain permissive roles or its Generic traversal classes remain consumer-instantiable.
  Evidence: the first implementation review found that `WireSchema co fields` could otherwise be
  coerced across phantom carriers and that the previously exported `GHasCtor` methods could admit
  an orphan dishonest matcher. The implementation adds nominal role annotations and keeps the
  sum-path and field-spine classes out of the `Keiki.Generics` export list.

- Observation: the plan's literal `--match=BuilderTypeErrors` command selects zero Hspec examples
  because `test/Spec.hs` registers that module under the human label `Keiki.Builder type errors
  (EP-70)`. Evidence: the command completed with `0 examples, 0 failures`; the full Builder-focused
  and final test gates must be used as the executable coverage rather than treating that empty
  selection as evidence.

- Observation: Hspec options containing the plan's prose phrase `full symbolic replay inversion`
  are split into separate arguments by this Cabal invocation, so the focused command fails before
  test execution. The stable module substring `FullSymbolicReplayInversion` selects the intended
  14 examples.
  Evidence: focused Milestone 3 execution on 2026-08-04.

- Observation: the current Mori improvement-request validator cannot index this repository's
  pinned ADR profile and rejects the established `planned`, `implemented`, and `released`
  lifecycle statuses across pre-existing requests. The repository's strict ADR command remains
  healthy and reports all six concepts valid.
  Evidence: `mori improvement-requests validate --path /Users/shinzui/Keikaku/bokuno/keiki`
  failed on the profile/schema mismatch and IR-1 through IR-6 statuses on 2026-08-04;
  `just adr-validate` passed. IR-6 and IR-8 retain their existing legal repository statuses.


## Decision Log

- Superseded decision: Land the structural change now, before broad application adoption, and
  migrate the current Keiki/Keiro consumers as part of this plan.
  Rationale: The public record change is unavoidable for sound observed-field alignment. Paying
  that cost with two application adopters prevents a second migration across twenty-plus future
  applications and lets all new consumers start on the stable representation.
  Date: 2026-08-04

- Decision: Store an abstract `WireSchema co fields` in every `WireCtor`; trusted schemas carry a
  Generic-derived constructor path and a typed ordered field spine, while manual or lossy paths
  use `wireSchemaUnavailable`.
  Rationale: An abstract trusted constructor prevents arbitrary strings or casts from becoming
  proof evidence. The typed spine supplies one `Typeable` dictionary per field so the symbolic
  layer can discover supported carriers without introducing an import cycle from `Keiki.Core` to
  `Keiki.Symbolic`.
  Date: 2026-08-04

- Decision: `mkWireCtorVia` and TH-derived wires are the normal trusted producers. Existing
  closure-taking `mkWireCtor`, `mkWireCtor0`, direct record construction, unconstrained
  `identityWireCtor`, and inversion-poisoning profunctor rewrites are unavailable unless a typed
  constructor can preserve existing evidence. Add `mkWireCtor0Via` for trusted nullary Generic
  constructors.
  Rationale: The closure-taking functions cannot prove which constructor they match. Conservative
  unavailability preserves soundness while giving generated application code a zero-ceremony
  trusted path.
  Date: 2026-08-04

- Decision: Preserve schemas through structural transformations only: `leftWireCtor` and
  `rightWireCtor` prefix the constructor path with the sum side; any transformation that replaces
  `wcMatch` with `const Nothing`, changes field meaning, or cannot prove a typed relationship drops
  the schema.
  Rationale: This makes composition and profunctor behavior reviewable as an explicit
  preserve-or-drop law instead of relying on matching names.
  Date: 2026-08-04

- Decision: Add a detailed opt-in `IO` checker; do not call it from `validateTransducer`, change
  runtime replay, or alter the SBV bound.
  Rationale: Plan 86 measured useful precision at acceptable opt-in cost, but solver startup and
  z3 availability do not belong in Keiki's pure default validator. The existing `sbv >=11.7 &&
  <15` range already contains the required APIs.
  Date: 2026-08-04

- Decision: Share register variables and structurally witnessed observed-head variables across
  the two candidate formulas, but scope command tags, command fields, input arms, and opaque
  variables per candidate. Suppress a warning only for definite UNSAT.
  Rationale: Runtime replay tests both candidates against the same pre-event state and event, but
  each edge may reconstruct a different command. Sharing candidate inputs would manufacture false
  contradictions; treating unknown as UNSAT would violate the proof-gate policy.
  Date: 2026-08-04

- Decision: Complete this plan before Plan 85. This plan owns the schema, head-relation helper,
  and output-dependent solver fixtures; Plan 85 owns only
  pure shared-register necessary-condition extraction and its default-validator suppression.
  Rationale: Plan 85 can integrate once against the final head representation and avoids building
  temporary name-based identity, duplicate output fixtures, or a solver environment.
  Date: 2026-08-04

- Superseded decision: Prepare one coordinated compatibility line: Keiki, `keiki-codec-json`, and
  `keiki-codec-json-test` move from 0.8 to 0.9; the released Keiro 0.10 packages move together to
  0.11 and depend on Keiki 0.9. Publication remains a separate explicitly authorized release.
  Rationale: `WireCtor` is a source-breaking Keiki API, and Keiro's DSL/generated-code contract is
  the adoption surface. Aligned bounds give future applications one unambiguous combination and
  avoid repeated bound-only releases.
  Date: 2026-08-04

- Decision: Defer every version change, release action, dependency-bound edit, and downstream
  migration until all breaking Keiki ExecPlans are complete. Plan 87 and Plan 88 remain local to
  the Keiki repository; a future user-authored Keiki release plan owns the coordinated Keiki,
  Keiro, and application rollout.
  Rationale: Plan 88 adds another public constructor-record boundary. Migrating adopters or
  choosing the release line now would make them cross an avoidable interim API and would preempt
  the release plan the user intends to write once all breaking work is known.
  Date: 2026-08-04

- Decision: The symbolic model leaves `TLit`, `TOpaqueLit`, and `TReg` output positions
  unconstrained on the shared observed variable, exactly mirroring `recomputeDerivedFields`, and
  the spec must contain adversarial fixtures that go falsely UNSAT under a model asserting
  `observed == literal` or `observed == currentRegister`.
  Rationale: Runtime candidacy never verifies invertible fields, so such an assertion is narrower
  than runtime and could suppress a real ambiguity. Plan 86's research called this absence
  load-bearing; review of this plan found the earlier "observed-value checks" wording ambiguous
  and the hazard untested. The fixtures turn the over-constraint failure mode into a test failure
  instead of a silent unsoundness.
  Date: 2026-08-04

- Decision: Two trusted `WireCtorPath`s witness `WireHeadsStructurallyDifferent` only when they
  diverge at a common index. A path that is a proper prefix of the other never witnesses
  difference; the pair stays may-alias.
  Rationale: Once left/right composition prefixes exist, path inequality is not disjointness
  evidence: a prefix-composed wire such as `leftWireCtor w` and a Generic-derived wire for the sum
  carrier's own arm constructor have unequal paths yet overlapping match sets. Divergence at a
  common index is genuine disjointness evidence and keeps this corner conservative without
  weakening ordinary same-type constructor comparison.
  Date: 2026-08-04

- Decision: Moving TH's nullary route from `mkWireCtor0` to `mkWireCtor0Via` intentionally
  replaces `Eq`-mediated matching with structural Generic matching, changing the generated
  constraint from `Eq co` to `Generic co` plus nullary-constructor evidence. A quotienting custom
  `Eq` that let a wire match a different constructor's value no longer matches; that behavior
  violated the documented `wcMatch` honesty law and is tightened, not preserved.
  Rationale: Trusted-schema disjointness claims are sound only if `wcMatch` is the structural
  matcher. `Eq co` remains required by `solveOutput`, so consumers cannot drop it anyway; the only
  migration cost is `deriving Generic` on all-nullary event sums, surfaced as a compile error at
  the version boundary. Changelogs and golden expansions must record the change.
  Date: 2026-08-04

- Decision: Give `WireCtorPath`, `WireFieldSchema`, and `WireSchema` nominal roles and stop
  exporting the Generic sum-walking classes that participate in trusted construction.
  Rationale: Hidden constructors alone do not prevent `coerce` across phantom parameters or
  consumer-authored orphan class instances from manufacturing proof evidence. Ordinary
  `mkInCtorVia`, `mkWireCtorVia`, and TH call sites continue to resolve the sealed instances
  without naming those constraints.
  Date: 2026-08-04

- Decision: Attach `DEPRECATED` pragmas to the closure-taking `mkWireCtor` and `mkWireCtor0`,
  pointing at the trusted `Via` functions and at explicit record construction with
  `wireSchemaUnavailable`. Because Milestone 2 completed before this amendment was recorded, the
  pragmas are executed with Milestone 4's in-tree compile sweep.
  Rationale: The helpers hide their evidence-free result, so they are the accidental path for the
  twenty-plus planned adopters; explicit record construction remains the sanctioned manual route
  because it states `wcSchema = wireSchemaUnavailable` visibly. Deliberate in-tree uses, if any
  remain, silence the warning locally rather than weakening the signal for consumers.
  Date: 2026-08-04

- Decision: Ship a numbered `docs/foundations/` page on replay verification semantics in
  Milestone 5: invertible output fields (`TLit`, `TOpaqueLit`, `TReg`, `TInpCtorField`) are not
  re-verified on replay, derived fields are recomputed and verified, and what that implies for
  trusting observed events; update `docs/foundations/00-reading-guide.md` accordingly.
  Rationale: This semantic nearly caused an unsound checker through ambiguous plan wording and
  will surprise adopters the same way; onboarding documentation is the cheapest place to prevent
  that, and a Haddock aside is not discoverable enough for application teams.
  Date: 2026-08-04


## Outcomes & Retrospective

Plan 87 delivered the structural prerequisite and the optional solver promised by Plan 86.
`WireCtor` now carries nominally protected structural evidence; Generic and TH constructors are
trusted, checked sum composition prefixes paths, and manual or meaning-changing transformations
state that evidence is unavailable. Public code cannot forge a trusted schema, and diagnostic
constructor or selector names never authorize field alignment.

The opt-in detailed checker models independently reconstructed commands against shared
pre-event registers and structurally aligned observed fields. It removes a compatibility warning
only for definite UNSAT and reports why unsupported or unwitnessed relationships were omitted.
The adversarial literal, register-audit, candidate-scope, duplicate-label, unsupported-term,
nullary-sum, and finite-oracle fixtures make the conservative polarity executable. The existing
pure validator and runtime replay path did not change.

Documentation now distinguishes invertible fields retained from the observation from derived
fields recomputed and verified, records the trusted/unavailable schema boundary in Haddocks and
ADRs, and leaves explicit handoffs to Plan 85, Plan 88/IR-6, schema-evolution research, and the
consumer CI recipe. The 100-pair benchmark completed in 0.315 CPU seconds, all 912 final test
examples passed, Haddock and native flake checks passed, and strict ADR validation passed.

No package version, dependency bound, release artifact, downstream repository, or adopter was
changed. That separation is intentional: the user will author a release plan after all breaking
Keiki ExecPlans are complete, then coordinate Keiki, Keiro, and application migration once.


## Context and Orientation

Keiki describes an output event with `WireCtor co fields` in `src/Keiki/Core.hs`. `wcMatch`
deconstructs an observed `co`, `wcBuild` reconstructs one from the nested-pair field tuple, and
`wcName` is a diagnostic string. `OutFields rs ci ifs fields` is a typed HList of output `Term`s,
and `OPack` ties one `WireCtor` to one `OutFields` value. This proves alignment inside one output
term, but when two edges are unpacked independently their `fields` types are separate
existentials. A string equality between their `wcName`s cannot eliminate those existentials.

`solveOutput` in `src/Keiki/Core.hs` is the concrete inverse. It matches the observed event,
gathers top-level `TInpCtorField` values, reconstructs a candidate command through
`InCtor.icBuild`, recomputes and verifies only the derived fields
(`TArith`/`TApp1`/`TApp2`/`TFieldProj`) while leaving invertible fields (`TLit`, `TOpaqueLit`,
`TReg`, `TInpCtorField`) at their observed values, and later evaluates the guard against the same
pre-event `RegFile`. Invertible positions therefore impose no candidacy constraint on the
observed event; the symbolic model must reproduce that absence, not "fix" it. `inversionAmbiguityWarnings` currently groups same-source, same-mode,
non-empty edges by equal `wcName` and emits `InversionAmbiguity` for every pair except literal
`PBot`. `validateTransducer` calls that pure function by default. Neither default validation nor
`applyEventKernel` may start a solver in this plan.

`Keiki.Symbolic` in `src/Keiki/Symbolic.hs` already translates guards and transition properties
to SBV. `SymEnv` currently represents one command scope; `SymDict`, `discoverSym`,
`discoverSymOrd`, and `discoverSymNum` dispatch from `Typeable` evidence to supported symbolic
carriers. The full replay-inversion checker needs a new environment layered beside this one: one
shared register cache, two candidate caches, and one observed-field cache permitted only after
the two `WireSchema`s establish equal constructor paths and equal ordered field types. It must
reuse the existing carrier discovery rather than duplicate an SBV type registry.

`Keiki.Generics` in `src/Keiki/Generics.hs` defines `FieldsOf`, `GTuple`, `mkWireCtor`,
`mkWireCtor0`, and `mkWireCtorVia`. Only `mkWireCtorVia` selects a constructor through a type-level
name and `GHasCtor`; that structural selection is the basis for trusted evidence. Add an internal
Generic traversal that records the constructor's ordinal sum path and each payload field's
`Typeable` dictionary and optional selector name. Add `mkWireCtor0Via` so TH can generate trusted
zero-field wires. Keep the closure-taking helpers for migration, but make their schema explicitly
unavailable.

`Keiki.Generics.TH` in `src/Keiki/Generics/TH.hs` generates event bindings through
`deriveWireCtors`, `deriveWireCtorsAll`, and `deriveWireCtorsWith`. It already routes record payloads
through `mkWireCtorVia`; change the nullary route from `mkWireCtor0` to `mkWireCtor0Via`. Generated
call sites such as `$(deriveWireCtorsAll ''Event)` should remain textually stable, but the
expansions change (`mkWireCtor0 "C" C` becomes `mkWireCtor0Via @"C"`) and the generated matching
constraint moves from `Eq co` to `Generic co`, so golden expansion snapshots must be updated and
an all-nullary event sum now needs `deriving Generic` (`Eq co` is still required by
`solveOutput`, so it cannot be dropped from event types). Golden and
conformance tests must prove the expanded bindings contain trusted schemas; do not rewrite
unchanged generated domain files merely because the library implementation changed.

`src/Keiki/Composition.hs` and `src/Keiki/Profunctor.hs` construct or transform wires.
`leftWireCtor` and `rightWireCtor` preserve meaning while embedding the event in `Either`, so they
prefix the structural key. `mapWireCtor`, `firstWireCtor`, and `arrWc` deliberately disable
inversion with `wcMatch = const Nothing` and must also return an unavailable schema.
`identityWireCtor` has no `Typeable` constraint and is unavailable for symbolic inversion. Builder
emission in `src/Keiki/Builder.hs` accepts an already constructed `WireCtor`; inferred `B.emit`
call sites should not change.

[Plan 86](86-research-a-full-symbolic-replay-inversion-model.md) and
`docs/research/full-symbolic-replay-inversion-model.md` provide the prerequisite evidence. Its
typed prototype proved an output-dependent pair UNSAT, retained a real overlap as SAT, matched a
finite concrete `solveOutput` oracle, and measured about a 1.04x median cost at 100 pairs versus
the existing guard-only symbolic query. Commits `fd63b32` and `c315db7` preserve the executable
prototype; it is intentionally absent from the final tree. Plan 86 concluded “Proceed after
structural wire-schema prerequisite” and bounded this follow-up to the exact work here.

[Plan 85](85-prove-replay-inverse-candidates-disjoint-from-shared-register-conjuncts.md) is the
solver-free companion. It runs after this plan and must not recreate the schema or solver. Its
shared-register contradiction remains valuable as the microsecond-scale default path and as a
fallback when this optional checker is not invoked.

Four accepted local decisions constrain the design. [ADR-0001](../adr/0001-structural-re-indexing-for-sound-replay.md)
forbids names and casts as replay evidence. [ADR-0003](../adr/0003-proof-gates-fail-conservatively.md)
allows suppression only for definite UNSAT. [ADR-0004](../adr/0004-composition-uses-snapshot-updates-and-checked-boundaries.md)
requires composition to preserve proof evidence only at checked structural boundaries.
[ADR-0005](../adr/0005-persisted-wire-identities-are-explicit-and-versioned.md)
separates persisted wire-kind strings from typed replay evidence. Update those records with the
implemented boundary; do not create a competing identity concept.

Mori identifies Keiki as `mori://shinzui/keiki/packages/keiki`, Keiro's main packages as
`mori://shinzui/keiro/packages/keiro`, `mori://shinzui/keiro/packages/keiro-core`, and
`mori://shinzui/keiro/packages/keiro-dsl`, and SBV as
`mori://LeventErkok/sbv/packages/sbv`. On 2026-08-04, Hackage and upstream tags agree that Keiki
0.8.0.0 (`v0.8.0.0`) and Keiro 0.10.0.0 (`keiro-0.10.0.0`) are current. Reverify those
authoritative sources immediately before changing bounds or preparing a release; the local Mori
corpus may lag. That refresh belongs to the future release plan, not this implementation.


## Plan of Work

Milestone 1 establishes the schema and the intentional compile break. In `src/Keiki/Core.hs`, add
an abstract `WireSchema co fields`, an abstract typed `WireFieldSchema fields`, a public
`wireSchemaUnavailable`, and a public availability observer. A trusted schema contains an
abstract Generic constructor path plus a right-associated field spine whose cons cell brings
`Typeable field` into scope; field position is structural, selector text is diagnostic only. The
trusted constructors stay internal to Keiki's Generic and structural-composition code. Add
`wcSchema :: WireSchema co fields` to the exported `WireCtor` record. Direct record users migrate
by choosing the explicit unavailable value; they cannot mint trusted evidence from a string.

In the same milestone add an internal three-way head classifier: structurally equal,
structurally different, or unwitnessed. Equal means identical abstract constructor path and a
typed field-spine alignment. Different requires two trusted schemas whose paths diverge at a
common index; a path that is a proper prefix of the other is never structural difference — the
pair remains may-alias, because prefix-related match sets can overlap (for example
`leftWireCtor w` against a trusted wire derived for the sum carrier's own arm constructor).
Unwitnessed covers every unavailable case. The optional checker may share observed fields only in
the equal case. Preserve the legacy `wcName` grouping inside `inversionAmbiguityWarnings` for now,
so default validation behavior does not change in this plan. Add tests for zero, one, and multiple
fields; equal labels at distinct positions; distinct constructors with the same short name;
a prefix-related trusted pair that must not classify as structurally different; and
manual unavailable records. Add a compile-failure fixture proving an omitted `wcSchema` is the
expected PVP break. Milestone 1 is complete when `Keiki.Core` compiles, trusted constructors
cannot be forged through the public API, and schema alignment uses no `unsafeCoerce` or
`wcName` equality.

Milestone 2 makes every producer and transformer explicit. In `src/Keiki/Generics.hs`, add the
Generic classes that derive constructor paths and `WireFieldSchema`, make `mkWireCtorVia` trusted,
add trusted `mkWireCtor0Via`, and make `mkWireCtor`/`mkWireCtor0` unavailable. Attach
`DEPRECATED` pragmas to `mkWireCtor` and `mkWireCtor0` directing consumers to the `Via`
functions or explicit record construction with `wireSchemaUnavailable` (amendment recorded
after this milestone first completed; execute with Milestone 4's in-tree sweep). Update
`src/Keiki/Generics/TH.hs` to use the trusted via functions for record and nullary constructors.
Update direct Keiki test/example `WireCtor` records with either a trusted Generic binding or
`wireSchemaUnavailable`; do not assign proof power to test-only hand-written closures.

In `src/Keiki/Composition.hs`, preserve the typed spine and prefix the key in `leftWireCtor` and
`rightWireCtor`. Audit every constructor/substitution path: copying an unchanged wire copies its
schema; combining through a checked sum prefixes it; changing matcher or field meaning drops it.
In `src/Keiki/Profunctor.hs`, mark `mapWireCtor`, `firstWireCtor`, `arrWc`, and unconstrained
`identityWireCtor` unavailable. Builder code passes schemas through unchanged. Extend Generic,
TH, composition, category, choice, profunctor, Builder type-error, and golden tests. Acceptance is
not merely compilation: the tests must inspect availability and constructor-path relations after
each operation, and runtime `wcMatch`/`wcBuild` round trips must remain identical.

Milestone 3 implements the optional checker in `src/Keiki/Symbolic.hs`, with function-free detail
types in `src/Keiki/Internal/SymbolicTypes.hs` if needed for `Eq`/`Show` derivations. Add a
candidate scope (`A`/`B`), one register variable cache shared by both candidates, independent
command tag/arm/field and opaque caches per candidate, and a shared observed-head cache allocated
only through an aligned trusted schema. Traverse paired `OutFields` together with the aligned
field spine. Reproduce `solveOutput` semantics exactly for supported structural terms:
top-level `TInpCtorField` assembles the candidate's command from the shared observed field;
`TArith` and exact structural projections constrain the observed field because runtime recomputes
and verifies them; `TLit`, `TOpaqueLit`, and `TReg` output positions leave the shared observed
variable unconstrained, exactly as `recomputeDerivedFields` keeps invertible fields at their
observed values. The model must never assert `observed == literal` or
`observed == currentRegister`: either assertion is narrower than runtime candidacy and could
manufacture a false disjointness proof. Drop, rather than approximate inward, any equality whose
carrier or term is unsupported. `TApp1`/`TApp2`, unsupported projections, missing schemas, and
unavailable symbolic carriers add a translation issue and widen the formula.

Add public opt-in detailed and compatibility functions. The detailed result reports source and
edge refs, schema availability, translation issues, solver status, and a verdict. The
compatibility function returns the existing `InversionAmbiguity` warnings for every pair except a
definite `InversionProvedDisjoint`. SAT of an over-approximation means only “not proved
disjoint”; do not claim it is a concrete ambiguity. Unknown, timeout, exception, or missing z3
also means retain the warning. Do not add the checker to `ValidationOptions` or call it from
`validateTransducer`.

Create `test/Keiki/FullSymbolicReplayInversionSpec.hs` from the semantic fixtures documented by
Plan 86, not by copying its temporary descriptor. It must cover the output-dependent UNSAT pair,
the real-overlap control, a guard-only disjoint pair, missing/poisoned schema, unsupported field
carrier, unsupported `TApp`, distinct candidate commands, duplicate diagnostic labels, live and
replay-only modes, and structurally different heads with identical short names. It must also
cover the two over-constraint adversarial fixtures: a same-constructor pair whose only difference
is distinct `TLit` values at one field position, and a pair whose distinguishing field is a
`TReg` audit output — both are concretely double-candidate at runtime, go falsely UNSAT under a
model that constrains invertible output positions, and must remain not proved disjoint. Add an
all-nullary Generic event sum whose trusted nullary wires classify pairwise structurally
different. For a finite
fixture domain, enumerate concrete `solveOutput` plus `models` and assert that every solver UNSAT
pair has no concrete double candidate. Keep a manual 100-pair benchmark outside default CI and
compare with the Plan 86 baseline; investigate a regression above 3x, but do not turn wall-clock
noise into a flaky test.

Milestone 4 completes only the local compatibility work. Attach the recorded `DEPRECATED`
guidance to `mkWireCtor` and `mkWireCtor0`, compile every in-tree manual `WireCtor`, TH/golden
fixture, sibling package, and example, and add an unreleased migration note stating the nullary TH
route's constraint change (`Eq co` to `Generic co` for matching; `Eq co` is still required by
`solveOutput`) and that a custom quotienting `Eq` no longer influences `wcMatch`. Refresh Mori's
reverse-dependent inventory as release-planning input, but do not edit package versions, mutual
bounds, Keiro, applications, or any other dependent repository.

Milestone 5 updates durable explanations and closes the handoff. Update the `WireCtor`, Generic/TH,
composition, profunctor, optional checker, and validation Haddocks. Add a numbered
`docs/foundations/` page on replay verification semantics — invertible output fields are kept at
their observed values and never re-verified, derived fields are recomputed and verified, and
what that implies for trusting observed events versus the build-time gates — and update
`docs/foundations/00-reading-guide.md`; cite the Decision Log entry and
`docs/research/full-symbolic-replay-inversion-model.md`. Update the local unreleased changelogs.
Update the implementing improvement request
or create one only if no existing request owns the structural prerequisite; use the repository's
profile and legal statuses. Amend ADR-0001, ADR-0003, ADR-0004, and ADR-0005 through the profiled
ADR workflow and update `docs/adr/log.md` with `okf log add` when their timestamps change.

Run every Keiki repository gate and record focused test counts and benchmark numbers in Progress.
Mark this plan complete before beginning Plan 85. The future user-authored release plan—not this
plan or Plan 88—will reverify versions, choose bounds, exercise downstream overlays, and migrate
adopters after all breaking ExecPlans are green.


## Concrete Steps

Run the Keiki commands from `/Users/shinzui/Keikaku/bokuno/keiki`. Begin each milestone by
preserving user-owned work and refreshing authoritative context:

```bash
git status --short
mori registry show shinzui/keiki --full
mori registry dependents shinzui/keiki --packages --json
mori registry show shinzui/keiro --full
mori registry dependents shinzui/keiro --packages --json
mori registry show LeventErkok/sbv --full
curl -fsSL https://hackage.haskell.org/package/keiki/preferred.json
curl -fsSL https://hackage.haskell.org/package/keiro/preferred.json
git ls-remote --tags https://github.com/shinzui/keiki.git
git ls-remote --tags https://github.com/shinzui/keiro.git
```

Release facts are recorded only as future-release input. This plan must not update bounds or
package versions even if an authoritative release changes while implementation is in progress.

Locate all schema producers and direct constructors without traversing dependency stores:

```bash
rg -n "WireCtor|mkWireCtor|identityWireCtor|leftWireCtor|rightWireCtor|arrWc" src test keiki-codec-json keiki-codec-json-test jitsurei
rg -n "inversionAmbiguityWarnings|data SymEnv|discoverSym|translateTermSym|translatePred" src/Keiki/Core.hs src/Keiki/Symbolic.hs
```

Run focused milestone tests in the GHC 9.12 development shell. Register the new spec in
`test/Spec.hs` and its module in `keiki.cabal` before running the final command:

```bash
nix develop -c cabal test keiki-test --test-options='--match=Generics' --test-show-details=direct
nix develop -c cabal test keiki-test --test-options='--match=TH' --test-show-details=direct
nix develop -c cabal test keiki-test --test-options='--match=Composition' --test-show-details=direct
nix develop -c cabal test keiki-test --test-options='--match=Profunctor' --test-show-details=direct
nix develop -c cabal test keiki-test --test-options='--match=BuilderTypeErrors' --test-show-details=direct
nix develop -c cabal test keiki-test --test-options='--match=FullSymbolicReplayInversion' --test-show-details=direct
nix develop -c cabal test keiki-test --test-options='--match=ValidationReplayAlignmentSpec' --test-show-details=direct
nix develop -c cabal test keiki-test --test-options='--match=RecomputeVerify' --test-show-details=direct
```

Plan 86 established that the active Hspec version does not interpret `|` as alternation, so keep
these commands sequential and separate. Each transcript must end with the actual count and
`0 failures`; record the count in Progress.

Run full local Keiki gates:

```bash
nix fmt -- --no-cache
nix develop -c cabal build all
nix develop -c cabal test all --test-show-details=direct
nix develop -c cabal haddock all
nix flake check
just adr-validate
git diff --check
```

Do not create downstream overlays or edit Keiro/application repositories. Preserve the Mori
reverse-dependent result in the plan as inventory for the future release plan only.

Use Conventional Commits. Keiki implementation commits carry:

```text
ExecPlan: docs/plans/87-add-structural-wire-schemas-for-optional-symbolic-replay-inversion.md
```

Do not prepare version or cross-repository commits, invoke Hackage upload, create/push tags, or
publish a release in this plan.


## Validation and Acceptance

The plan is acceptable only when the following behavior is demonstrated.

A `deriveWireCtorsAll` binding for a record event exposes a trusted schema with the constructor's
Generic sum path and every field in source order. A nullary TH binding is also trusted, matches
structurally rather than through `Eq`, and an all-nullary Generic event sum derives trusted wires
that classify pairwise structurally different. Two
bindings for the same constructor align without names or casts; two different constructors with
the same short name are structurally different. A trusted path that is a proper prefix of another
trusted path is never reported structurally different — the pair stays may-alias. Selector labels
are never used as variable
identity. Direct record construction must state `wcSchema = wireSchemaUnavailable`, and public
code cannot construct a trusted schema directly.

`leftWireCtor` and `rightWireCtor` retain the typed field spine and produce different prefixed
constructor paths. Structure-preserving copies retain evidence. `mapWireCtor`, `firstWireCtor`,
`arrWc`, unconstrained `identityWireCtor`, and any transformation that disables matching report
unavailable. Builder emission neither strengthens nor drops the schema it receives.

For the Plan 86 output-dependent fixture, the detailed opt-in checker reports
`InversionProvedDisjoint` and the compatibility projection removes exactly that pair's existing
`InversionAmbiguity`. The overlapping control, whose concrete enumeration contains two
candidates for a named register/event witness, retains the warning. The finite oracle finds no
double candidate for every pair reported UNSAT.

Candidate A and B use the same symbolic registers and observed fields but different reconstructed
command tags, fields, input arms, and opaque variables. An adversarial fixture becomes falsely
UNSAT if command variables are accidentally shared and therefore must remain not-proved-disjoint.
The test should fail under that incorrect implementation. Symmetrically, `TLit`, `TOpaqueLit`,
and `TReg` output positions leave the observed variable unconstrained: the distinct-literal pair
and the `TReg`-audit-output pair both remain not proved disjoint, and both tests must fail under
an implementation that asserts `observed == literal` or `observed == currentRegister`.

Removing a trusted schema, using an unsupported observed-field carrier, inserting `TApp1` or
`TApp2`, producing a solver `Unknown`, timing out, or running without z3 retains the warning and
records a detailed issue. A satisfying over-approximation is not presented as a concrete replay
witness. Only definite UNSAT suppresses.

The existing `inversionAmbiguityWarnings`, `validateTransducer defaultValidationOptions`, and
runtime replay results remain unchanged throughout this plan. Default validation performs no
`IO`, starts no z3 process, and works without z3 installed. `keiki.cabal` retains `sbv >=11.7 &&
<15`; no new package dependency is added for the solver.

All direct Keiki constructors, sibling packages, TH expansions, examples, and local conformance
suites compile in this repository. Changelogs explain the future manual migration and the
trusted/unavailable distinction without selecting a release version. No dependent repository,
package bound, package version, or release artifact changes. All local commands in Concrete Steps
pass, ADR validation is strict, and `git diff --check` is clean.


## Idempotence and Recovery

Mori inspection, source searches, Cabal builds, tests, Haddocks, formatting, and solver queries
are safe to rerun. The optional solver tests use deterministic formulas; keep timing outside the
required CI assertion.

Inspect `git status --short` before every repository edit. Existing changes belong to the user;
preserve them and use narrow `apply_patch` edits. Never use `git reset --hard`, a broad restore,
or a recursive deletion to recover.

If the schema implementation needs `unsafeCoerce`, runtime equality of `wcName`, persisted wire
kind, or an exported constructor that lets consumers forge trusted evidence, stop and record the
counterexample. Keep that path unavailable. If a Generic event cannot provide `Typeable` for one
field, compile it through the unavailable manual path and retain warnings; do not lie about the
field dictionary or add a global `Eq co` constraint.

If the full formula becomes inconclusive, widen the relation and retain the warning. If z3 is
  missing, record the optional-gate failure and continue the local default/build gates; do not weaken
the acceptance claim or make default validation depend on solver availability. Completion still
requires rerunning the optional focused tests in an environment with the supported solver.

Package publication, tags, versions, bounds, overlays, and dependent builds are deliberately
excluded. The future user-authored release plan will refresh their authoritative state after all
breaking ExecPlans are complete and use the release skill only with explicit authorization.


## Interfaces and Dependencies

The source-breaking public record in `Keiki.Core` has this conceptual final shape; names shown here
are the required API unless implementation records a strictly equivalent naming adjustment in the
Decision Log:

```haskell
data WireSchema co fields          -- constructors not exported
data WireFieldSchema fields        -- constructors not exported

data WireSchemaAvailability
  = WireSchemaTrusted
  | WireSchemaUnavailable

wireSchemaUnavailable :: WireSchema co fields
wireSchemaAvailability :: WireSchema co fields -> WireSchemaAvailability

data WireCtor co fields = WireCtor
  { wcName :: String
  , wcSchema :: WireSchema co fields
  , wcMatch :: co -> Maybe fields
  , wcBuild :: fields -> co
  }
```

Internally, the trusted representation is equivalent to this GADT, with constructors kept out of
the public export list:

```haskell
data WireFieldSchema fields where
  WireFieldsNil :: WireFieldSchema ()
  WireFieldsCons :: Typeable field
                 => Maybe String
                 -> WireFieldSchema rest
                 -> WireFieldSchema (field, rest)

data WireSchema co fields where
  UnavailableWireSchema :: WireSchema co fields
  TrustedWireSchema :: WireCtorPath co
                    -> WireFieldSchema fields
                    -> WireSchema co fields
```

`WireCtorPath` is an abstract Generic constructor-ordinal path with structural left/right
composition prefixes. It is not a constructor name, `wcName`, persisted wire kind, hash, or
consumer-supplied token. An internal comparison returns a typed alignment only after both the path
and every field position/type agree. Path comparison for `classifyWireHeads` is three-valued:
equal paths may align; paths that diverge at a common index are structurally different; a path
that is a proper prefix of the other is neither equal nor different — the pair is treated as
may-alias, because a prefix-composed wire and a wire derived for the sum carrier's own arm
constructor can match the same observed event. Selector names are optional diagnostics.

`Keiki.Core` also supplies the final private head relation consumed by Plan 85:

```haskell
data WireHeadRelation
  = WireHeadsStructurallyEqual
  | WireHeadsStructurallyDifferent
  | WireHeadsUnwitnessed

classifyWireHeads :: WireCtor co fa -> WireCtor co fb -> WireHeadRelation
wireHeadsMayAliasForDefault :: WireCtor co fa -> WireCtor co fb -> Bool
```

`wireHeadsMayAliasForDefault` is `True` for structurally equal heads, `False` for structurally
different trusted heads, and preserves legacy equal-`wcName` grouping only when a schema is
unavailable. A prefix-related trusted pair is unconditionally `True` regardless of names: both
schemas are trusted, so the legacy name fallback does not apply, and there is positive structural
evidence that their match sets can overlap. The fallback is compatibility policy, not typed field
evidence; the opt-in solver may share
observed variables only for `WireHeadsStructurallyEqual`.

`Keiki.Generics` retains its current helpers and adds:

```haskell
mkWireCtorVia
  :: (KnownSymbol name, Generic co, GHasCtor name (Rep co) d,
      Generic d, GTuple (Rep d) fs, GWireFieldSchema (Rep d) fs)
  => WireCtor co fs

mkWireCtor0Via
  :: (KnownSymbol name, Generic co, GHasNullaryCtor name (Rep co))
  => WireCtor co ()
```

The exact internal class decomposition may reuse `GHasCtor` for nullary constructors, but the
public behavior is fixed: the `Via` functions are trusted and closure-taking helpers are
unavailable. Existing TH splices keep their source spelling.

The optional public checker in `Keiki.Symbolic` has these result meanings:

```haskell
data InversionProofVerdict
  = InversionProvedDisjoint
  | InversionNotProvedDisjoint

data InversionAnalysisDetail s = InversionAnalysisDetail
  { iadSource :: s
  , iadLeftEdge :: EdgeRef s
  , iadRightEdge :: EdgeRef s
  , iadVerdict :: InversionProofVerdict
  , iadSolverStatus :: InversionSolverStatus
  , iadTranslationIssues :: [InversionTranslationIssue]
  }

checkInversionAmbiguitySymDetailed
  :: (Bounded s, Enum s, Show s)
  => SymTransducer (HsPred rs ci) rs s ci co
  -> IO [InversionAnalysisDetail s]

checkInversionAmbiguitySym
  :: (Bounded s, Enum s, Show s)
  => SymTransducer (HsPred rs ci) rs s ci co
  -> IO [TransducerValidationWarning s]
```

The implementation may add fields needed to identify the existing warning precisely, but it must
not add `Eq ci` or `Eq co`. The compatibility function begins from the existing conservative
pair set and removes only definite UNSAT details. Detailed `Eq`/`Show` data belongs in
`Keiki.Internal.SymbolicTypes` when keeping functions out of derived values requires it.

Use the existing SBV dependency through `mori://LeventErkok/sbv/packages/sbv`; do not change
`>=11.7 && <15`. Z3 is an optional execution dependency of the new checker, never a runtime or
default-validation dependency. Downstream source discovery and release-version verification are
inputs to the future release plan.


Plan revision note (2026-08-04): Initial plan created from Plan 86's completed research. The plan
intentionally combines the structural PVP boundary, optional solver, and current consumer
migration so Keiki/Keiro adopters cross one stable API boundary before the projected rollout.

Plan revision note (2026-08-04, second revision): Amended after a soundness review, with three new
Decision Log entries. First, the symbolic checker's treatment of invertible output positions is
now explicit: `TLit`, `TOpaqueLit`, and `TReg` output fields leave the shared observed variable
unconstrained, mirroring `recomputeDerivedFields`, and two adversarial fixtures (distinct-literal
pair, `TReg`-audit pair) must fail under an over-constrained model — the earlier "observed-value
checks" wording was ambiguous and the hazard untested. Second, trusted-path difference is defined
as divergence at a common index; a proper-prefix relation is conservatively may-alias
(unconditionally, never via the name fallback), closing a false-disjointness corner between
prefix-composed wires and wires derived for a sum carrier's own arm constructor. Third, the
nullary TH route's `Eq co` to `Generic co` constraint change, the intentional custom-`Eq`
matching tightening, golden-expansion updates, and an all-nullary event fixture are recorded in
Milestones 2–4 and Validation. Plan 85 remains consistent: it consumes
`wireHeadsMayAliasForDefault` as policy and is unaffected by these refinements.

Plan revision note (2026-08-04, third revision): Folded in two follow-ups from the release-scope
review, recorded as Decision Log entries and a Progress addendum because Milestones 1–2 had
already completed: `DEPRECATED` pragmas on the closure-taking `mkWireCtor`/`mkWireCtor0`
(executed with Milestone 4's in-tree sweep) and a numbered foundations page on replay
verification semantics (executed in Milestone 5). Larger follow-ups identified by the same
review are owned elsewhere: IR-6/Plan 88 (structural input-constructor identity, same
unreleased breaking-work sequence), IR-7 (schema evolution research), and IR-8 (opt-in checker
CI gate).

Plan revision note (2026-08-04, fourth revision): At the user's direction, removed the premature
version and adopter-migration milestone. Plans 87 and 88 now land breaking Keiki work locally
without choosing release versions, changing bounds, or editing downstream repositories. A
separate user-authored release plan, created after all breaking ExecPlans are complete, owns the
coordinated Keiki/Keiro/application migration.
