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
- [x] (2026-08-04T23:14:31Z) Milestone 1: confirmed Plans 87 and 85 complete with all recorded
      gates passing; re-read the landed hidden `Keiki.Internal.WireSchema` representation;
      refreshed Mori's 12-project reverse-dependent inventory; and verified Hackage still lists
      `0.8.0.0` as the preferred Keiki release. The actual reusable pieces are the nominal
      `WireCtorPath`, private three-way path comparison, and public trusted/unavailable pattern;
      the wire field spine is tuple-indexed and therefore needs a slot-list-indexed input sibling.
- [x] (2026-08-04T23:24:59Z) Milestone 2: added abstract nominal input-constructor schemas, a
      slot-indexed typed spine, input/input and input/wire comparisons, trusted and unavailable
      construction paths, checked `Either` prefixes, and explicit evidence on every in-tree
      manual record. `mkInCtorVia` and both TH record/nullary derivations are trusted;
      closure-taking, identity, profunctor-poisoned, and meaning-changing paths are unavailable.
      InputSchema passed 9 examples and Generics/TH passed 29, both with 0 failures; the omitted
      `icSchema` fixture failed with `-Werror=missing-fields` at the intended field.
- [x] (2026-08-04T23:41:59Z) Milestone 3: replaced name-authorized composition substitution
      and guard rewriting with checked typed input-to-wire alignment. Structural mismatch and
      unavailable evidence now produce explicit composition diagnostics or poison leaves; no
      result-type cast remains on the substitution path. Added safe Generic producers for direct
      record constructors and composition-only identity evidence that cannot become symbolic
      identity. Composition passed 61 examples, Category 21, Choice 11, and the complete
      Profunctor match 69, all with 0 failures.
- [x] (2026-08-04T23:53:18Z) Milestone 4: encoded trusted `PInCtor` atoms as shared
      Boolean constructor-path decisions in both ordinary and replay-candidate translation.
      Unwitnessed names now key independent fallback atoms and record a conservative translation
      issue, so unequal names cannot prove exclusion; model reconstruction uses a separate stable
      constructor ordinal. The Symbolic match passed 107 examples, ValidationReplayAlignmentSpec
      27, and the cross-suite PInCtor match 10, all with 0 failures.
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

- Observation: Plan 87 landed the evidence implementation in the hidden module
  `src/Keiki/Internal/WireSchema.hs`, not directly in `src/Keiki/Core.hs`. Its reusable path is
  `WireCtorPath carrier`; its output spine is `WireFieldSchema fields`, indexed by the nested-pair
  tuple used by `OutFields`; and `WireFieldAlignment left right` proves equal tuple positions.
  An input schema cannot reuse that spine verbatim because `InCtor` is indexed by a type-level
  list of named slots rather than a tuple, so the implementation needs a slot-list-indexed sibling
  while retaining the same hidden path and comparison algebra.
  Evidence: `src/Keiki/Internal/WireSchema.hs` and `src/Keiki/Core.hs`, read 2026-08-04.

- Observation: the mandatory dependency refresh found 12 registered reverse-dependent projects
  (`danwa`, `kawa`, `keiro`, three Keiro runtime documentation/example projects, `kikan`,
  `kioku`, `kizashi`, `kotei`, `meibo`, and `shikigami`). Hackage's authoritative preferred-version
  document still reports `0.8.0.0` first. These facts do not expand this local-only plan.
  Evidence: `mori registry dependents shinzui/keiki --packages --json` and Hackage
  `preferred.json`, run 2026-08-04.

- Observation: TH singleton command bindings previously called closure-taking `mkInCtor0`, which
  cannot carry trusted path evidence. The existing Generic `GHasCtor` and empty-payload `GRecord`
  instances already support nullary commands, so the generated binding can call
  `mkInCtorVia @"Constructor"` exactly like record commands without adding a new public helper.
  Evidence: `src/Keiki/Generics/TH.hs`; the focused TH suite passed 29 examples with 0 failures.

- Observation: removing the unwitnessed composition fallback exposed 14 focused composition
  failures, all from in-tree fixtures that manually constructed direct record constructors.
  Those constructors were structurally honest but could not use the existing `mk*Via` helpers,
  whose Generic contract expects a constructor wrapping a record payload. Safe direct-record
  Generic producers made the evidence available without restoring name authorization.
  Evidence: the initial focused Composition run failed 14 of 56 examples; after fixture migration
  the expanded suite passed 61 examples with 0 failures.

- Observation: categorical identity must compose at a polymorphic one-field boundary even though
  its unconstrained constructor cannot supply ordinary trusted evidence. A hidden composition-only
  schema can tie the root field to the carrier and survive checked `Either` prefixes, while its
  public availability remains unavailable and it is excluded from ordinary input/input and
  wire/wire identity comparisons.
  Evidence: the first focused Choice run failed 2 of 11 examples under strict unwitnessed
  rejection; the composition-only identity path restored all 11 without a name-based fallback.

- Observation: existing symbolic mutual-exclusion fixtures manually constructed unavailable
  `InCtor`s and therefore encoded the very name-only assumption this milestone removes. The
  general Symbolic fixture now distinguishes the conservative fallback from trusted structural
  exclusion, while Validation's intentionally well-shaped nullary `Foo`/`Bar` fixture derives
  trusted Generic evidence.
  Evidence: the first Symbolic run after the translator change had 2 expected-value failures out
  of 107, and the first cross-suite PInCtor run found 1 stale Validation expectation out of 10;
  the corrected focused runs passed 107 and 10 respectively with 0 failures.


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
  it and falls back to name-keyed Boolean atoms only when evidence is unavailable, preserving
  conservative polarity: equal names share an atom, while unequal names remain independent.
  The fallback may conflate or widen satisfiability but must never manufacture mutual exclusion
  or disjointness that suppresses a warning.
  Rationale: [ADR-0003](../adr/0003-proof-gates-fail-conservatively.md). Conflation of
  unwitnessed constructors over-approximates overlap, which keeps warnings. Treating unequal
  names as proof of exclusion could hide a real problem, so that legacy behavior is removed.
  Date: 2026-08-04

- Decision: Encode trusted constructor paths as shared Boolean decisions by path depth, and keep
  the `symSatExt` model selector separate as the stable ordinal in `KnownInCtors` order. Apply the
  same path formula independently inside each replay candidate environment and record every
  unwitnessed atom or replay head as a translation issue.
  Rationale: path conjunction gives the required algebra directly: equal paths are identical,
  divergent paths contradict at their first differing step, and a proper prefix remains
  satisfiable with its extension. Separating witness selection prevents diagnostic names from
  re-entering proof identity while still reconstructing the exact same-named trusted constructor.
  Date: 2026-08-04

- Decision: This plan is written before Plan 87 is implemented, against Plan 87's pinned
  interface contract. Milestone 1 is a mandatory revalidation gate: the actual landed
  representation must be re-read and this plan's Context, Plan of Work, and Interfaces
  corrected before any Milestone 2 edit.
  Rationale: The 85/87 resequencing showed the cost of building against a representation that
  is about to change. Writing the plan now preserves the review context; gating implementation
  on revalidation prevents drift from the landed form.
  Date: 2026-08-04

- Decision: Extend the landed hidden schema module rather than moving proof constructors into
  `Keiki.Core`. Retain one nominal constructor-path algebra, add a slot-list-indexed input field
  spine and typed input-to-wire alignment beside the existing tuple-indexed wire spine, and
  re-export only abstract schemas and availability observers from `Keiki.Core`.
  Rationale: this is the landed Plan 87 non-forgeability boundary. The two field encodings have
  different kinds, so pretending they are one GADT would obscure rather than prove the
  composition correspondence; a hidden typed alignment can bridge them position by position.
  Date: 2026-08-04

- Decision: Keep input-spine derivation in a new private `GInCtorFieldSchema` class and switch
  TH singleton declarations from deprecated `mkInCtor0` to `mkInCtorVia`, while leaving the
  public splice invocation and generated binding names unchanged.
  Rationale: closure-taking helpers must remain explicitly unwitnessed. The private class obtains
  `Typeable` evidence for each Generic record slot without adding methods to the exported
  `GRecord` class or letting consumers mint trusted schemas.
  Date: 2026-08-04

- Decision: Do not retain any name-authorized unwitnessed fallback in composition. Add
  `mkInCtorRecordVia` and `mkWireCtorRecordVia` as safe Generic producers for constructors whose
  fields are declared directly with record syntax, and migrate the affected in-tree fixtures.
  Rationale: the 14 legacy failures identified missing producer coverage, not a soundness reason
  to keep the coercion. The new helpers derive both the record value and structural schema from
  the same selected Generic constructor.
  Date: 2026-08-04

- Decision: Give library-defined categorical identity a hidden composition-only input/wire
  capability. Equal prefixed structural paths authorize a one-field alignment, but availability
  remains unavailable and the capability never participates in symbolic constructor identity.
  Rationale: identity's root field is definitionally its carrier, yet the polymorphic API cannot
  manufacture ordinary `Typeable` evidence. Restricting the witness to the two library identity
  constructors preserves lawful composition without widening the public trust boundary.
  Date: 2026-08-04


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Keiki models an event-sourced state machine as `SymTransducer` in `src/Keiki/Core.hs`. An input
command constructor is described by `InCtor ci ifs`: a GADT record carrying `AssembleRegFile`
and `KnownSlotNames` constraints over the typed slot schema `ifs`, plus a diagnostic `icName`
string and consumer-owned `icMatch`/`icBuild` closures. Nothing ties the name to the constructor
the closures actually handle. Plan 87's landed output evidence lives in the hidden
`src/Keiki/Internal/WireSchema.hs`: `WireSchema co fields` combines a nominal
`WireCtorPath co` with `WireFieldSchema fields`, whose index is the nested-pair tuple used by
`OutFields`; `WireSchemaAvailability` exposes only trusted versus unavailable; and
`compareWireSchemas` distinguishes equal paths with typed field alignment, paths that diverge at
a common index, and unavailable or proper-prefix relationships. `Keiki.Core` re-exports the
schema abstractly. This plan gives `InCtor` the equivalent hidden evidence. Because `InCtor` is
indexed by `ifs :: [Slot]`, its field spine is a separate slot-list-indexed GADT, while its path
and three-valued comparison reuse the landed algebra exactly.

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

Milestone 2 adds the evidence. Extend the hidden `src/Keiki/Internal/WireSchema.hs` proof boundary
with an abstract input-constructor schema carrying the existing nominal constructor path plus a
new typed slot spine, typed input-to-input comparison, and typed input-to-wire alignment. Keep
the existing private divergence-versus-prefix comparison and trusted constructors internal. In
`src/Keiki/Core.hs`, add the abstract schema field to `InCtor` and re-export only the unavailable
value and availability observer. In `src/Keiki/Generics.hs`,
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
For direct record constructors, use the safe Generic `mkInCtorRecordVia` and
`mkWireCtorRecordVia` producers rather than manual unavailable records. Categorical identity uses
a hidden composition-only one-field capability: it is sufficient for checked input-to-wire
alignment, remains unavailable through the public observer, and is not structural evidence for
symbolic identity.

Milestone 4 rebuilds symbolic identity. Where both constructors in scope carry trusted
evidence, derive the solver constraint from the structural path (distinct paths that diverge are
mutually exclusive; equal paths are the same constraint; prefix-related paths are treated as
possibly overlapping). Unwitnessed constructors use name-keyed fallback atoms: equal names share
one atom, but unequal names are independent rather than exclusive. The translation records
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
Unwitnessed constructors preserve equal-name conflation, while unequal names remain independent;
no analysis suppresses a warning from name evidence of unwitnessed constructors alone.

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

The revalidated public shape in `Keiki.Core` is:

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

The hidden implementation remains in `Keiki.Internal.WireSchema`. It reuses Plan 87's nominal
`WireCtorPath carrier` and its left/right prefixes, but pairs it with an input-specific spine
indexed by `ifs :: [Slot]`; each cons cell retains the slot's field `Typeable` evidence. The
existing path comparator remains the single definition of equal, divergent, and proper-prefix
relations. An internal input-to-wire alignment witness proves position-by-position correspondence
between the input slot list and the wire nested-pair tuple and lets `Keiki.Composition` select a
field without a result-type cast; only the composite term's independently existential input schema
may need the already documented local realignment after this witness exists. `substInputField` and
`composeGuard` accept substitution only through this checked comparison. `Keiki.Symbolic` consumes
the same hidden path steps for structural `PInCtor` constraints and records trusted versus fallback
identity. `Keiki.Generics` keeps `mkInCtorVia` as the trusted producer by generalizing the private
Generic path class and adding a private input-slot spine derivation; public
`mkInCtorRecordVia` and `mkWireCtorRecordVia` helpers cover direct record constructors without
exporting their private classes or adding a package dependency. `Keiki.Generics.TH` record and nullary call sites both become
trusted while remaining textually stable at their declarations. No version or bound changes occur,
and z3/SBV usage remains within the existing dependency.


Plan revision note (2026-08-04): At the user's direction, removed downstream migration and
release-line assumptions. This plan now lands only local Keiki breaking work. A separate
user-authored release plan, created after all breaking ExecPlans are complete, will choose
versions and coordinate Keiro and application adoption.

Plan revision note (2026-08-04): Milestone 1 revalidated the draft against Plan 87's landed
hidden `Keiki.Internal.WireSchema` implementation. The plan now distinguishes the reusable
nominal path from the tuple-indexed wire spine and specifies the slot-list-indexed input spine
and typed input-to-wire alignment required by the actual code.

Plan revision note (2026-08-04): Milestone 2 recorded the implemented private input-spine
derivation and the TH nullary switch to trusted `mkInCtorVia`, plus focused and compile-failure
evidence. These details resolve the producer choices left conceptual at plan creation.

Plan revision note (2026-08-04): Milestone 3 records the strict no-fallback composition boundary,
the safe direct-record Generic producers needed by legacy fixtures, and the deliberately narrower
composition-only evidence used by categorical identity. Focused law-suite evidence is recorded in
Progress.

Plan revision note (2026-08-04): Milestone 4 replaces the draft's ambiguous "name-string
fallback" with the implemented conservative rule: equal unwitnessed names share an atom and
unequal names remain independent. It also records the separate ordinal witness selector and the
same structural encoding in replay-candidate translation.
