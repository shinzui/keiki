---
id: 88
slug: add-structural-input-constructor-evidence-for-composition-and-symbolic-alignment
title: "Add structural input-constructor evidence for composition and symbolic alignment"
kind: exec-plan
created_at: 2026-08-04T20:01:46Z
intention: "intention_01kz715z62ennb1m6eg94a59vk"
---

# Add structural input-constructor evidence for composition and symbolic alignment

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

After this change, input constructors carry the same kind of non-forgeable structural evidence
that [Plan 87](87-add-structural-wire-schemas-for-optional-symbolic-replay-inversion.md) gives
output wire constructors, and the two boundaries that currently trust `icName` string equality
stop doing so. Composition substitution accepts a cross-transducer field read only through a
checked structural alignment instead of authorizing `unsafeCoerceTerm` from a name match, and
the symbolic translator identifies a `PInCtor` constructor structurally when evidence is
available instead of conflating every equal-named constructor into one solver tag.

The observable proof is twofold. First, two distinct trusted input constructors that share a
diagnostic name are no longer symbolically conflated: their `PInCtor` conjunction is
unsatisfiable, and determinism analysis treats them as different constructors. Second, a
composition whose t2-side `InCtor` name-collides with a structurally different t1 wire produces
a loud structural diagnostic where today it silently coerces. Correctly shaped programs behave
identically: all existing composition, category, choice, profunctor, and replay law suites pass
unchanged, and runtime stepping and replay semantics do not change.

This plan implements
[IR-6](../improvement-requests/replace-name-based-input-constructor-identity-with-structural-evidence.md).
It runs after Plan 87 and
[Plan 85](85-prove-replay-inverse-candidates-disjoint-from-shared-register-conjuncts.md) are
complete. Like those plans, it lands breaking work locally without choosing versions or migrating
adopters. After all breaking Keiki ExecPlans are complete, a separate user-authored release plan
will choose the release line and coordinate Keiro and application adoption once.


## Progress

- [x] (2026-08-04) Plan created from the Plan 87 soundness review that identified input
      constructors as the remaining name-trusting boundary; IR-6 filed and marked planned.
- [ ] Milestone 1: confirm the Plan 87/85 prerequisite state and revalidate this plan's
      assumptions against the landed schema representation; record the actual shapes here.
- [ ] Milestone 2: add abstract input-constructor structural evidence to `InCtor` in
      `src/Keiki/Core.hs` with trusted and unavailable construction paths, reusing Plan 87's
      path/spine machinery.
- [ ] Milestone 3: replace name-authorized composition substitution with checked structural
      alignment; propagate or deliberately drop evidence through composition and profunctor
      transformations.
- [ ] Milestone 4: derive symbolic `PInCtor` identity from structural evidence with a
      conservative name fallback for unwitnessed constructors.
- [ ] Milestone 5: migrate in-tree consumers; update Haddocks, unreleased changelogs, IR-6, and
      ADRs; run all local Keiki gates and record the future-release handoff.


## Surprises & Discoveries

- Observation: composition substitution couples a name check to an unchecked coercion.
  `substInputField` in `src/Keiki/Composition.hs` accepts a t2-side field read when
  `icName ic2 == wcName wc1` and then realigns the substituted term with `unsafeCoerceTerm`,
  relying on the assumption that the name-matched constructor mirrors the `OutFields` tuple
  shape; `composeGuard` rewrites `PInCtor` to `PTop` on the same name match. A name collision
  between structurally different constructors is silently coerced rather than rejected.
  Evidence: `src/Keiki/Composition.hs` (`substInputField`, `composeGuard`), reviewed 2026-08-04.

- Observation: the symbolic translator uses the name string as constructor identity.
  `PInCtor` translates to `seInputCtor .== literal (icName ic)` in `src/Keiki/Symbolic.hs`, so
  two distinct constructors sharing a name are conflated into one solver tag, and mutual
  exclusion between differently named constructors is assumed from strings, not witnessed.
  Evidence: `src/Keiki/Symbolic.hs` (`SymEnv.seInputCtor` and the `PInCtor` translation case).

- Observation: the input-side producer surface exactly mirrors the wire side. `mkInCtor`,
  `mkInCtor0` (with `Eq ci`), and structural `mkInCtorVia` live in `src/Keiki/Generics.hs`;
  `leftInCtor`/`rightInCtor` embed constructors in `Either` alphabets; `identityInCtor` in
  `src/Keiki/Profunctor.hs` is polymorphic with a phantom slot; profunctor rewrites poison
  `icBuild`. Plan 87's trusted/unavailable producer taxonomy therefore transfers directly.
  Evidence: `src/Keiki/Generics.hs`, `src/Keiki/Composition.hs`, `src/Keiki/Profunctor.hs`.


## Decision Log

- Decision: Execute this plan only after Plans 87 and 85 are complete, but do not select a
  release version, change bounds, or migrate dependent repositories here.
  Rationale: `InCtor` is public, so adding evidence is a source break. The user will create a
  separate Keiki release plan after every breaking ExecPlan is complete; that plan owns the one
  coordinated Keiro and application migration.
  Date: 2026-08-04

- Decision: Reuse Plan 87's structural-path and typed-spine machinery rather than introducing a
  parallel input-side representation, generalizing it if its final landed form is wire-specific.
  Rationale: Two path algebras would eventually disagree about prefix and divergence semantics.
  The divergence-versus-prefix comparison rule Plan 87 records must hold once, in one place.
  Date: 2026-08-04

- Decision: Name equality never authorizes `unsafeCoerceTerm`. Checked structural alignment is
  the only route to substitution; an unwitnessed or mismatched alignment yields a loud
  structural diagnostic or an unsatisfiable poison leaf, never a coerced term.
  Rationale: [ADR-0001](../adr/0001-structural-re-indexing-for-sound-replay.md) forbids names
  and casts as evidence; [ADR-0004](../adr/0004-composition-uses-snapshot-updates-and-checked-boundaries.md)
  requires checked structural boundaries. The current coercion is exactly the pattern those
  decisions exclude.
  Date: 2026-08-04

- Decision: Symbolic `PInCtor` identity uses structural evidence when both constructors carry
  it and falls back to the name string only when evidence is unavailable, preserving
  conservative polarity: the fallback may conflate (widening satisfiability, retaining
  warnings) but must never manufacture mutual exclusion or disjointness that suppresses one.
  Rationale: [ADR-0003](../adr/0003-proof-gates-fail-conservatively.md). Conflation of
  unwitnessed constructors over-approximates overlap, which keeps warnings; treating unequal
  names as proof of exclusion is the direction that could hide a real problem and is confined
  to today's behavior for unwitnessed values only where analysis of the consuming checks shows
  it cannot suppress a warning; otherwise it is removed.
  Date: 2026-08-04

- Decision: This plan is written before Plan 87 is implemented, against Plan 87's pinned
  interface contract. Milestone 1 is a mandatory revalidation gate: the actual landed
  representation must be re-read and this plan's Context, Plan of Work, and Interfaces
  corrected before any Milestone 2 edit.
  Rationale: The 85/87 resequencing showed the cost of building against a representation that
  is about to change. Writing the plan now preserves the review context; gating implementation
  on revalidation prevents drift from the landed form.
  Date: 2026-08-04


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Keiki models an event-sourced state machine as `SymTransducer` in `src/Keiki/Core.hs`. An input
command constructor is described by `InCtor ci ifs`: a GADT record carrying `AssembleRegFile`
and `KnownSlotNames` constraints over the typed slot schema `ifs`, plus a diagnostic `icName`
string and consumer-owned `icMatch`/`icBuild` closures. Nothing ties the name to the
constructor the closures actually handle. After Plan 87, the output side's `WireCtor` carries a
`WireSchema` — an abstract trusted Generic constructor path plus a typed field spine,
non-forgeable through the public API, with an explicit `wireSchemaUnavailable` for manual
construction and a three-valued path comparison (equal; diverging at a common index; prefix
related, which is conservatively may-alias). This plan gives `InCtor` the equivalent evidence
and consumes it at the two name-trusting boundaries.

Boundary one is composition. `Keiki.Composition` composes transducers through a shared mid
alphabet. `substInputField` substitutes a t2-side input-field read with the corresponding
t1-side output term when `icName ic2 == wcName wc1`, then applies `unsafeCoerceTerm` justified
by a comment that the slot list of `ic2` mirrors the `OutFields` tuple shape via the Generic
derivations. On a name mismatch it produces a `poisonTerm`. `composeGuard` rewrites a t2-side
`PInCtor` guard atom to `PTop` under the same name equality. The honest cases are produced by
the Generic derivations and do mirror structurally; the defect is that the name check cannot
distinguish those honest cases from an accidental collision, and the coercion executes either
way.

Boundary two is symbolic translation. `Keiki.Symbolic` maintains one `SymEnv` per predicate
translation with `seInputCtor :: SBV String`; the `PInCtor` case emits
`seInputCtor .== literal (icName ic)`. Constructor mutual exclusion is therefore string
identity: distinct constructors with equal names become one solver tag, and differently named
constructors are assumed exclusive. Plan 87's dual-candidate checker scopes command tags per
candidate but still identifies each candidate's constructor by this mechanism.

The producer surface mirrors the wire side. `src/Keiki/Generics.hs` exports closure-taking
`mkInCtor` and `mkInCtor0` (requiring `Eq ci`) and structural `mkInCtorVia`, which selects a
constructor through a type-level name and the same `GHasCtor` machinery `mkWireCtorVia` uses.
`src/Keiki/Generics/TH.hs` derives command bindings through the corresponding `derive*`
splices. `src/Keiki/Composition.hs` embeds constructors in `Either` alphabets with
`leftInCtor`/`rightInCtor` (meaning-preserving, so they prefix the structural key exactly as
`leftWireCtor`/`rightWireCtor` do). `src/Keiki/Profunctor.hs` has polymorphic `identityInCtor`
(a phantom `"payload"` slot, no derivable `Typeable` evidence — unavailable, as with
`identityWireCtor`) and rewrites that poison `icBuild` (unavailable). Plan 87's
trusted/unavailable taxonomy and its preserve-or-drop composition laws transfer directly.

Relevant accepted decisions: [ADR-0001](../adr/0001-structural-re-indexing-for-sound-replay.md)
forbids names and casts as replay evidence.
[ADR-0003](../adr/0003-proof-gates-fail-conservatively.md) allows suppression only for definite
proofs and requires conservative failure.
[ADR-0004](../adr/0004-composition-uses-snapshot-updates-and-checked-boundaries.md) requires
composition to preserve proof evidence only at checked structural boundaries.
[ADR-0005](../adr/0005-persisted-wire-identities-are-explicit-and-versioned.md) keeps persisted
identities separate from typed evidence; this plan does not touch persisted identities.

This plan was authored against Plan 87's pinned Interfaces contract before that plan was
implemented. Milestone 1 revalidates every representation assumption against the landed code
and corrects this document first. Mori identifies Keiki as `mori://shinzui/keiki/packages/keiki`
and Keiro's packages as `mori://shinzui/keiro/packages/keiro`,
`mori://shinzui/keiro/packages/keiro-core`, and `mori://shinzui/keiro/packages/keiro-dsl`.
Those downstream identifiers are future release-plan inventory only.


## Plan of Work

Milestone 1 is the prerequisite and revalidation gate. Confirm Plans 87 and 85 are marked
complete with recorded gates. Re-read the landed `WireSchema`, path, spine, availability, and
classifier code in `src/Keiki/Core.hs` and the trusted producers in `src/Keiki/Generics.hs`;
re-run the reverse-dependent inventory; and correct this plan's Context, Plan of Work, and
Interfaces sections to the actual representation, recording every correction in the Decision
Log. No source edit happens before this gate is recorded in Progress.

Milestone 2 adds the evidence. In `src/Keiki/Core.hs`, give `InCtor` an evidence field of an
abstract input-constructor schema type carrying a trusted Generic constructor path plus a typed
slot spine, with a public unavailable value and availability observer, reusing (and if
necessary generalizing) Plan 87's path and comparison machinery including its
divergence-versus-prefix rule. Trusted constructors stay internal. In `src/Keiki/Generics.hs`,
make `mkInCtorVia` the trusted producer; closure-taking `mkInCtor` and `mkInCtor0` become
explicitly unavailable (matching their wire-side deprecation posture from Plan 87). Update
`src/Keiki/Generics/TH.hs` so derived command bindings carry trusted evidence with textually
stable splice call sites. `leftInCtor`/`rightInCtor` prefix the structural key;
`identityInCtor` and every `icBuild`-poisoning or meaning-changing rewrite in
`src/Keiki/Profunctor.hs` report unavailable. Add classifier tests mirroring Plan 87's:
zero/one/many slots, same-name distinct constructors, prefix-related pairs, manual unavailable
records, and a compile-failure fixture for the omitted field.

Milestone 3 rebuilds the composition boundary. Replace the name test in `substInputField` with
a checked structural alignment between the t1 wire's evidence and the t2 input constructor's
evidence: alignment succeeds only when both are trusted and their paths and spines agree, and
only then may the existing (now witnessed) realignment run. When either side is unwitnessed,
preserve current behavior only if a recorded analysis shows the name check plus the Generic
derivation invariants make the coercion safe for every reachable unwitnessed producer;
otherwise produce the loud structural diagnostic. Apply the same discipline to `composeGuard`'s
`PTop` rewrite. Audit every path that copies, wraps, or rewrites an `InCtor` for the
preserve-or-drop law, mirroring Plan 87's Milestone 2 audit. All composition, category, choice,
profunctor, and alignment law suites must pass unchanged for correctly shaped programs.

Milestone 4 rebuilds symbolic identity. Where both constructors in scope carry trusted
evidence, derive the solver tag from the structural path (distinct paths that diverge are
mutually exclusive; equal paths are the same tag; prefix-related paths are treated as possibly
overlapping). Unwitnessed constructors keep the name-string tag, and the translation records
which identity mode each atom used so analyses can stay conservative. Verify with fixtures that
same-name distinct trusted constructors are not conflated, that unwitnessed behavior is
unchanged, and that no determinism, inversion, or reachability analysis suppresses a warning
from name inequality of unwitnessed constructors alone.

Milestone 5 migrates and documents only the Keiki repository. Update in-tree manual `InCtor`
records, TH goldens, and examples; update Haddocks and the unreleased `CHANGELOG.md`, IR-6's
status, and amend ADR-0004 with the checked input-side boundary through the profiled ADR workflow.
Run all local Keiki gates and record results in Progress. Do not edit versions, bounds, Keiro,
applications, overlays, tags, or release artifacts; hand their inventory to the future
user-authored release plan.


## Concrete Steps

Run Keiki commands from `/Users/shinzui/Keikaku/bokuno/keiki`. Begin every milestone by
preserving user-owned work and refreshing context:

```bash
git status --short
rg -n "Milestone 5|Outcomes & Retrospective" docs/plans/87-add-structural-wire-schemas-for-optional-symbolic-replay-inversion.md docs/plans/85-prove-replay-inverse-candidates-disjoint-from-shared-register-conjuncts.md
mori registry dependents shinzui/keiki --packages --json
curl -fsSL https://hackage.haskell.org/package/keiki/preferred.json
```

Do not proceed past Milestone 1 unless both prerequisite plans are complete and the landed
schema representation has been re-read. Locate the boundaries:

```bash
rg -n "InCtor|mkInCtor|identityInCtor|leftInCtor|rightInCtor" src test keiki-codec-json keiki-codec-json-test jitsurei
rg -n "substInputField|composeGuard|unsafeCoerceTerm" src/Keiki/Composition.hs
rg -n "seInputCtor|PInCtor" src/Keiki/Symbolic.hs
```

Run focused tests in the GHC 9.12 development shell, keeping match commands sequential (the
active Hspec does not interpret `|` as alternation):

```bash
nix develop -c cabal test keiki-test --test-options='--match=Generics' --test-show-details=direct
nix develop -c cabal test keiki-test --test-options='--match=TH' --test-show-details=direct
nix develop -c cabal test keiki-test --test-options='--match=Composition' --test-show-details=direct
nix develop -c cabal test keiki-test --test-options='--match=Profunctor' --test-show-details=direct
nix develop -c cabal test keiki-test --test-options='--match=Symbolic' --test-show-details=direct
nix develop -c cabal test keiki-test --test-options='--match=ValidationReplayAlignmentSpec' --test-show-details=direct
```

Each transcript must end with the actual example count and `0 failures`; record counts in
Progress. Full Keiki gates:

```bash
nix fmt -- --no-cache
nix develop -c cabal build all
nix develop -c cabal test all --test-show-details=direct
nix develop -c cabal haddock all
nix flake check
just adr-validate
git diff --check
```

Keiki commits carry:

```text
ExecPlan: docs/plans/88-add-structural-input-constructor-evidence-for-composition-and-symbolic-alignment.md
```

Do not make cross-repository or version commits, publish packages, create or push tags, or invoke
any release.


## Validation and Acceptance

A `mkInCtorVia`- or TH-derived command binding exposes trusted evidence with the constructor's
Generic path and every slot in source order; closure-taking producers and every poisoning or
polymorphic transformation report unavailable; trusted evidence cannot be forged through the
public API and manual `InCtor` records state unavailability explicitly.

Two distinct trusted input constructors with equal diagnostic names are not conflated by the
symbolic translator: their `PInCtor` conjunction is unsatisfiable and determinism analysis
treats them as distinct. Prefix-related trusted paths are never treated as mutually exclusive.
Unwitnessed constructors preserve current name-tag behavior, and no analysis suppresses a
warning from name evidence of unwitnessed constructors alone.

A composition whose t2-side `InCtor` name-collides with a structurally different t1 wire
produces a structural diagnostic instead of a silently coerced term; the fixture must fail
under an implementation that still authorizes `unsafeCoerceTerm` from the name match.
Correctly shaped compositions — including every existing composition, category, choice,
profunctor, and multi-event law suite — behave identically, and runtime stepping and replay
results are unchanged everywhere.

All in-tree consumers and generated conformance suites compile and pass their local gates with
this change included. No package version, dependency bound, persisted identity, or dependent
repository changes in this plan. All local commands in Concrete Steps pass, ADR validation is
strict, and `git diff --check` is clean.


## Idempotence and Recovery

Searches, builds, tests, Haddocks, and formatting are safe to rerun. Inspect
`git status --short` before every repository edit; preserve user-owned changes; use narrow
`apply_patch` edits; never use destructive resets or broad restores.

If checked structural alignment cannot be established for a case the current name check
accepts, and analysis cannot prove the unwitnessed coercion safe, stop and record the
counterexample in Surprises & Discoveries; prefer the loud diagnostic over preserving a
coercion this plan cannot justify. If reusing Plan 87's path machinery requires changing its
landed public surface, fix that under a recorded Decision here only if source-compatible;
otherwise stop and consult the user. Downstream repositories are out of scope.


## Interfaces and Dependencies

The conceptual final shape in `Keiki.Core`, subject to Milestone 1 revalidation against Plan
87's landed representation; names may be adjusted only with a strictly equivalent naming
adjustment recorded in the Decision Log:

```haskell
data InCtorSchema ci (ifs :: [Slot])   -- constructors not exported

data InCtorSchemaAvailability
  = InCtorSchemaTrusted
  | InCtorSchemaUnavailable

inCtorSchemaUnavailable :: InCtorSchema ci ifs
inCtorSchemaAvailability :: InCtorSchema ci ifs -> InCtorSchemaAvailability

data InCtor ci (ifs :: [Slot]) where
  InCtor ::
    (AssembleRegFile ifs, KnownSlotNames ifs) =>
    { icName :: String,
      icSchema :: InCtorSchema ci ifs,
      icMatch :: ci -> Maybe (RegFile ifs),
      icBuild :: RegFile ifs -> ci
    } ->
    InCtor ci ifs
```

The trusted representation reuses Plan 87's abstract constructor path (with its left/right
prefixes and its three-valued comparison: equal; diverging at a common index; prefix-related,
conservatively may-alias) and pairs it with a typed slot spine aligned to `ifs`. The internal
alignment witness consumed by `Keiki.Composition` proves, without `unsafeCoerce` in the
unwitnessed sense, that a t1 wire's field tuple and a t2 input constructor's slot schema
correspond position by position; `substInputField` and `composeGuard` accept a substitution
only through it (or through the explicitly analyzed unwitnessed-compatibility case recorded in
Milestone 3). `Keiki.Symbolic` consumes the same evidence for `PInCtor` tags and records the
identity mode per atom. `Keiki.Generics` keeps `mkInCtorVia` as the trusted producer and adds
no new public class surface beyond what schema derivation requires; `Keiki.Generics.TH` splice
call sites remain textually stable. No new package dependency is permitted, no version or
bound changes occur in this plan, and z3/SBV usage is untouched.


Plan revision note (2026-08-04): At the user's direction, removed downstream migration and
release-line assumptions. This plan now lands only local Keiki breaking work. A separate
user-authored release plan, created after all breaking ExecPlans are complete, will choose
versions and coordinate Keiro and application adoption.
