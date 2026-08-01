---
id: 82
slug: classify-unconstrained-symbolic-field-projections-conservatively
title: "Classify unconstrained symbolic field projections conservatively"
kind: exec-plan
created_at: 2026-08-01T02:59:23Z
intention: "intention_01kyxm5322e9mvkcyw7a7zsyd6"
---

# Classify unconstrained symbolic field projections conservatively

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

After this change, Keiki no longer calls a satisfiability result exact when the result depends on
a one-way field projection whose concrete image is unknown. A two-constructor owner projected to
`Text` can no longer produce `VerifiedSatisfiable` merely because z3 invented a third string that
no owner can produce. Existing concrete evaluation, replay, path memoization, and conservative
emptiness proofs continue to behave as before. `symSatExt` also stops returning a reconstructed
register/input pair unless concrete evaluation confirms that the pair satisfies the predicate.

The behavior is visible in `test/Keiki/FieldProjSpec.hs`: an exhaustive two-value projection is
reported as `UnverifiedOpaque` by `verifyPredicate`, while an ordinary scalar contradiction still
returns `VerifiedUnsatisfiable` and a repeated projection read still proves `x /= x` empty through
`symIsBot`. This plan implements
[IR-3](../improvement-requests/classify-unconstrained-symbolic-field-projections-as-inexact.md)
and prepares the witness representation for the exact-domain capability in
[Plan 83](83-add-exact-reconstructible-symbolic-field-projection-domains.md).


## Progress

- [ ] Milestone 1: add the finite-owner counterexample and make projection exactness depend on
      witness evidence that defaults to unconstrained.
- [ ] Milestone 2: preserve and document the one-sided guarantees of compatibility solving,
      transducer analysis, replay, validation, and projection identity.
- [ ] Milestone 3: update durable documentation and release notes, run all project gates, and
      perform the ADR distillation pass.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Existing `fieldWitness` values remain valid but carry no exact-domain evidence, and
  therefore make `predicateTranslationExact` return `False` whenever their `TFieldProj` occurs in
  a supported equality or ordering predicate.
  Rationale: This is the compatibility-safe default. The released class describes only a total
  getter, so inferring surjectivity or reconstructibility would repeat the false claim being fixed.
  Date: 2026-08-01

- Decision: Keep `PredicateVerification` unchanged in this repair and map an unconstrained
  projection to the existing `UnverifiedOpaque` constructor.
  Rationale: Adding a constructor to an exported Haskell sum breaks exhaustive matches. Plan 83
  can add a separate detailed result without changing the compatibility sum, while this plan can
  ship the correctness fix independently.
  Date: 2026-08-01

- Decision: Do not disable `symIsBot`, `checkTransitionDeterminismSym`, or `checkDeadEdgesSym` for
  unconstrained projections.
  Rationale: A free projection scalar is an over-approximation of concrete owners. Definite
  unsatisfiability over that larger valuation set still proves concrete unsatisfiability. A
  satisfiable result is only a possible model and must not be promoted to an exact witness.
  Date: 2026-08-01

- Decision: Add an internal evidence-aware query on the abstract `FieldWitness` now rather than
  hard-code `TFieldProj` as permanently inexact.
  Rationale: Plan 83 must be able to construct an exact witness without changing `Term` again.
  Keeping the witness constructor abstract lets the representation grow while existing instance
  declarations and call sites remain source-compatible.
  Date: 2026-08-01

- Decision: Re-evaluate every `symSatExt` candidate concretely before returning it and return
  `Nothing` when an unconstrained projection model cannot be realized by the reconstructed owner.
  Rationale: The current extractor omits projection variables and fills an unread owner slot with
  `symDefault`. When the owner itself has a `Sym` instance, that default can disagree with the
  solver's free projection key, violating the documented guarantee that a returned witness models
  the predicate. `Nothing` already means that no concrete model was recovered, not proof of
  unsatisfiability. Plan 83 uses exact inverses to recover more such witnesses.
  Date: 2026-08-01

- Decision: Run the `symSatExt` concrete recheck under an exception guard and translate a thrown
  `evalTerm` input-guard violation into `Nothing`.
  Rationale: Concrete evaluation of a `PBInp` projection or direct `TInpCtorField` read errors when
  the evaluated command is a different constructor. `evalPred` short-circuits `PAnd` left to right,
  so predicates following the guard-first `PInCtor` discipline evaluate safely against their own
  model, but an unguarded read — which validation already warns about — must not turn a previously
  total `symSatExt` call into an imprecise exception from pure code.
  Date: 2026-08-01

- Decision: The concrete recheck deliberately covers opaque `TApp1`/`TApp2` terms and the non-`Sym`
  equality fallback, not only projections, and the release notes must say so.
  Rationale: The current Haddock scopes the `models` guarantee as "modulo escape-hatch terms."
  After this plan, a predicate whose only symbolic support was a fabricated opaque assignment
  returns `Nothing` where it previously returned a non-modeling pair. That is the intended
  restoration of the witness postcondition, but it is a caller-visible behavior change beyond the
  projection repair and must be documented as one.
  Date: 2026-08-01


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Keiki models guards with the `HsPred` syntax tree in `src/Keiki/Core.hs`. A `Term` is a typed value
inside a predicate. `TFieldProj` is the term that reads a scalar from a consumer-owned register or
input field. Its `FieldProjection projection` instance supplies a total getter, while the abstract
`FieldWitness projection` and the projection tag's `TypeRep` provide stable nominal identity. A
`ProjBase` restricts the owner to a direct register slot or a direct input-constructor field, which
is why repeated reads have a stable structural path.

`src/Keiki/Symbolic.hs` maps supported scalar terms to SBV expressions. `translateTermSym` currently
maps every `TFieldProj` to a memoized free variable keyed by base path, projection tag, owner type,
and result type. This is a conservative over-approximation: every concrete getter result can be
assigned to that variable, but the solver can also choose result values outside the getter's
image. `constrainFieldProjection` exists only for concrete-to-symbolic agreement tests and does not
provide an inverse.

`predicateTranslationExact` is the gate used by `verifyPredicate`. It walks the predicate and
currently returns `True` for every `TFieldProj` whose result type is present in the curated
symbolic registry. `verifyPredicate` then translates and solves the predicate and returns either
`VerifiedSatisfiable` or `VerifiedUnsatisfiable` for a definite solver answer. The projection case
is wrong because satisfiability over the free result carrier need not correspond to a concrete
owner.

`symSatExt` reconstructs complete register and input values only from ordinary `TReg` and
`TInpCtorField` model labels. It currently omits `TFieldProj` labels. If a projection owner happens
to be a supported `Sym` carrier, the extractor can therefore fill that unread owner with
`symDefault` while the solver chose an unrelated projection result and return a pair that fails
`models`. This plan restores the documented witness soundness guarantee by checking the candidate
with concrete predicate evaluation. It does not claim completeness for an inexact translation:
`Nothing` may mean that the over-approximate solver model could not be realized.

This plan distinguishes exact verification from conservative emptiness. `symIsBot` returns `True`
only after a definite solver `Unsatisfiable` result. Because the free projection domain contains
all concrete getter results, such an answer remains a sound proof of emptiness. A `False` result
means only “not proved empty”; it does not prove a concrete owner exists. The same direction is
used by `checkTransitionDeterminismSym`: only an unsatisfiable conjunction blesses two guards as
disjoint. `checkDeadEdgesSym` reports an edge dead only after the same definite unsatisfiability
answer.

The principal fixtures are in `test/Keiki/FieldProjSpec.hs`. They define several
`FieldProjection` tags, prove repeated-read memoization, check concrete-to-symbolic agreement,
exercise projection validation, and preserve forward/replay equality. Exactness and structured
solver-result tests already live in `test/Keiki/SymbolicSpec.hs`. Add the finite projection
counterexample to `FieldProjSpec` so its owner, getter, and path are close to the existing
projection fixtures, and add any generic result-classification assertions to `SymbolicSpec`.

Three accepted ADRs constrain this work. `docs/adr/0003-proof-gates-fail-conservatively.md` says
that only definite unsatisfiability may bless a proof gate and already documents projection
variables as one-way over-approximations; this plan must amend it to distinguish exact verification
from sound over-approximate emptiness. `docs/adr/0002-event-logs-must-reproduce-forward-state.md`
requires validated transducers to replay their emitted logs to the forward state; no projection
classification change may alter evaluation, output construction, or replay. Finally,
`docs/adr/0004-composition-uses-snapshot-updates-and-checked-boundaries.md` requires projections
crossing a non-structural mapped boundary to lower visibly to opacity; this plan must retain that
behavior and its `NonStructuralProjectionBoundary` diagnostics.

The released implementation and its original design are recorded in
`docs/plans/79-typed-symbolic-field-projections-over-mapped-consumer-owned-values.md`. In
particular, that plan states that different projection keys have no relationship and that
projection models cannot generally be extracted into consumer-owned slots. Treat that text as
historical evidence for the conservative semantics, not as permission to label the translation
exact.


## Plan of Work

Milestone 1 introduces the failing example before changing behavior. In
`test/Keiki/FieldProjSpec.hs`, use a two-value owner with existing `Sym` evidence, such as `Bool`, a
fresh projection tag whose result is `Text`, and a one-slot register schema. The getter maps the two
values to two distinct keys. Form the predicate “the projected key is neither known key.”
Before the fix, `predicateTranslationExact` is `True` and `verifyPredicate` returns
`VerifiedSatisfiable`, even though evaluating the predicate for either constructor is false. Keep
that pre-fix observation in a test comment, not as an expected result.

Then change the private representation of `FieldWitness` in `src/Keiki/Core.hs` so it records
whether exact-domain evidence exists. At this milestone there is only the unconstrained case, and
the existing `fieldWitness` constructor always selects it. Preserve the nominal role and keep the
data constructor private. Export a narrowly named eliminator such as
`fieldWitnessHasExactDomain` in the existing “Internals exposed for testing” section; Plan 83 will
extend the private evidence and use richer internal eliminators. Do not add a public way to claim
exactness in this plan.

Update the `TFieldProj` branch of `predicateTranslationExact` in `src/Keiki/Symbolic.hs` to query
the witness evidence. It must return `False` for every witness constructible through the released
API. Do not change `translateTermSym`, `projectionVarKey`, or `memoFree`. Extend the regression to
assert all of the following observable results:

```text
predicateTranslationExact exhaustiveProjectionPredicate == False
verifyPredicate exhaustiveProjectionPredicate == UnverifiedOpaque
predicateTranslationExact repeatedProjectionContradiction == False
verifyPredicate repeatedProjectionContradiction == UnverifiedOpaque
symIsBot repeatedProjectionContradiction == True
```

The last two lines deliberately differ: exact verification refuses to make either exact claim,
while the compatibility emptiness operation retains its sound one-sided proof. Also assert that
`symSatExt exhaustiveProjectionPredicate == Nothing`; before the candidate recheck it can return
the default Boolean owner even though that owner does not satisfy the predicate.

Milestone 2 pins every compatibility boundary. Add table-style examples, expressed as individual
Hspec cases, for an unsupported projection result, a supported-but-unconstrained result, an opaque
`TApp1`, an ordinary exact scalar, and structural arithmetic. Assert that only the ordinary exact
cases reach the two `Verified` constructors. Keep the existing path-key tests proving that the
same tag and base share one variable, distinct tags remain independent, index position separates
duplicate diagnostic names, and adversarial schema strings never become SBV labels.

Run the projection through `validateTransducer` and the existing forward/replay fixture. The
classification repair must not create `OpaqueGuard`, must not change `ProjectionResultUnsupported`
or `ProjectionOrderingUnsupported`, and must not make a projection legal in an update or output.
`TFieldProj` remains a structured term rather than an opaque Haskell application. The
input-constructor guard and hidden-input checks remain unchanged.

At the final return point of `symSatExt` in `src/Keiki/Symbolic.hs`, evaluate a reconstructed
candidate with the same concrete `evalPred`/`models` semantics used by `SymPred`. Return `Just` only
when that check is true. Return `Nothing` for a candidate that cannot realize an opaque or projected
symbolic assignment. Do not reinterpret this `Nothing` as UNSAT, and do not change `symIsBot`.
Run the recheck inside the existing `unsafePerformIO` block under an exception guard that forces
the Boolean result and maps `evalTerm`'s input-guard-violation error to `Nothing`. `evalPred`
short-circuits `PAnd` left to right, so a predicate following the guard-first `PInCtor` discipline
evaluates safely against its own model, but a predicate with an unguarded `PBInp` read — which
validation already warns about — must degrade to "no witness recovered" rather than turn a
previously total call into an exception from pure code. Add a regression with a deliberately
unguarded input projection asserting `symSatExt` returns `Nothing` without raising, and a positive
ordinary-register extraction regression beside the new negative projection case so the guard does
not discard sound existing witnesses.

Revise Haddocks in `src/Keiki/Core.hs` and `src/Keiki/Symbolic.hs` to use three precise terms.
“Path-exact” means repeated reads share the same variable. “Over-approximate” means the solver may
choose values no owner produces. “Translation-exact” means every satisfying symbolic valuation
corresponds to concrete values under the documented carrier laws. Avoid describing an
unconstrained projection as precise without qualifying which of these meanings applies.

Milestone 3 updates durable documentation. Amend
`docs/improvement-requests/support-typed-symbolic-field-projections-over-mapped-consumer-values.md`
with a post-release clarification: IR-1 delivered path-stable, solver-visible over-approximation,
not exact owner-domain satisfiability. Replace the statement that mutual-exclusion and dead-edge
analyses treat all projections “precisely” with the conservative guarantee above, and clarify that
the agreement property is concrete-to-symbolic only. Keep cross-repository references in canonical
`mori://` form. Mark IR-3 implemented only after all validation passes.

Update `docs/adr/0003-proof-gates-fail-conservatively.md` with the durable distinction between
exact verification and unsatisfiability proved over an over-approximation. Add an Unreleased
changelog entry naming the prior `predicateTranslationExact` result as an overclaim and explaining
that existing `fieldWitness` callers receive `UnverifiedOpaque` from `verifyPredicate` but retain
conservative `symIsBot` behavior. The same entry must state that the restored `symSatExt`
postcondition also covers the opaque `TApp1`/`TApp2` terms and the non-`Sym` equality fallback: a
predicate whose only symbolic support was a fabricated opaque assignment now returns `Nothing`
where it previously returned a pair that failed `models`, and the Haddock carve-out that scoped
the witness guarantee as "modulo escape-hatch terms" is removed rather than restated. At completion, reread the plan's Decision Log, Surprises &
Discoveries, and Outcomes & Retrospective and promote any additional durable finding to ADR-0003
instead of leaving it only here.


## Concrete Steps

Run every command from `/Users/shinzui/Keikaku/bokuno/keiki`. Begin by recording the authoritative
release and upstream tag before choosing release metadata or dependency bounds:

```bash
mori registry show shinzui/keiki --full
curl -fsSL https://hackage.haskell.org/package/keiki/preferred.json
git ls-remote --tags https://github.com/shinzui/keiki.git
```

As of plan creation, the expected authoritative package and tag are both `0.6.0.0`; repeat the
check during implementation because registry state can change.

After adding the regression and classifier change, run the focused cases:

```bash
cabal test keiki-test --test-option=--match --test-option=projection
cabal test keiki-test --test-option=--match --test-option=verification
```

The projection run must report zero failures, including the new exhaustive-owner example. If the
second match selects no test because Hspec descriptions changed, use the exact new `describe`
label rather than weakening the assertion.

Run formatting and the complete gates after documentation and code are finished:

```bash
nix fmt
cabal test all
cabal build all
nix flake check
okf validate docs/improvement-requests --strict --profile mori/improvement-requests-profile.dhall --profile-enforce --log-enforce
```

Expected successful summaries include `0 failures`, successful Cabal builds, a successful flake
check, and `OK: 4 concepts` or a larger count if more requests have been added by then.

Use a Conventional Commit message and include both required trailers on every implementation
commit:

```text
fix(symbolic): classify unconstrained projections conservatively

ExecPlan: docs/plans/82-classify-unconstrained-symbolic-field-projections-conservatively.md
Intention: intention_01kyxm5322e9mvkcyw7a7zsyd6
```


## Validation and Acceptance

The implementation is accepted when a two-constructor owner projected into `Text` demonstrates
that z3 can satisfy the unrestricted third-value formula, yet `verifyPredicate` returns
`UnverifiedOpaque` and never `VerifiedSatisfiable`. Evaluating that predicate against both concrete
owners must be false. `symSatExt` must return `Nothing` rather than a default-owner pair that fails
concrete `models`; its documentation must identify that outcome as reconstruction failure, not an
unsatisfiability proof. The recheck must not throw: a fixture with a deliberately unguarded input
projection returns `Nothing` instead of raising `evalTerm`'s input-guard violation, and an
opaque-only predicate whose fabricated witness fails `models` likewise returns `Nothing`. A predicate containing the same projection on both sides of `./=` must
remain provably empty through `symIsBot` but must not be called translation-exact.

Ordinary `Bool`, `Integer`, fixed-width numeric, `Text`, `UTCTime`, and supported `Natural`
predicate cases retain their existing exactness subject to ADR-0003's documented carrier caveats.
Opaque `TApp1`/`TApp2`, unsupported equality or ordering carriers, unsupported projection results,
and supported-but-unconstrained projections are distinguished in tests and never reach a
`Verified` constructor.

All existing `FieldProjection` declarations and `fieldWitness` call sites compile without source
changes. Projection path identity remains the tuple of structural base, nominal tag, owner type,
and result type. Concrete `evalTerm`, dotted rendering, hidden-input checks, guarded input reads,
projection-outside-guard validation, raw composition lowering, checked-composition rejection,
forward stepping, and replay produce their pre-plan results.

The documentation must state that `symIsBot == False` means only “not proved empty,” whereas
`verifyPredicate == VerifiedSatisfiable` is reserved for exact translations. The Unreleased
changelog must identify this as a semantic correctness fix and describe the caller-visible
migration.


## Idempotence and Recovery

All test and validation commands are safe to repeat. The code change is additive inside the
abstract `FieldWitness` representation and a one-branch classification change in
`predicateTranslationExact`; no persisted data or generated artifacts are migrated. Do not delete
or rewrite `dist-newstyle` to recover from a failed test. Fix the focused test or implementation
and rerun it.

If changing `FieldWitness` causes downstream type errors, preserve its nominal role and the public
signatures of `fieldWitness`, `fieldWitnessGet`, `regProj`, `inpProj`, and `TFieldProj`. The data
constructor must remain unexported. If a proposed fix requires exposing an exactness Boolean that a
caller can forge, stop and use the private evidence plus read-only eliminator described above.

If the full gate reveals unrelated pre-existing worktree failures, record the exact command and
output in Surprises & Discoveries, run the narrow tests that prove this plan, and do not revert or
overwrite unrelated user changes.


## Interfaces and Dependencies

This plan changes no external dependency bounds. It uses the existing `sbv` dependency and z3
runtime. Mori identifies the local dependency sources, but release selection must still be checked
against Hackage and upstream tags before publishing.

The public compatibility interface remains:

```haskell
data PredicateVerification
  = VerifiedSatisfiable
  | VerifiedUnsatisfiable
  | UnverifiedOpaque
  | UnverifiedSolverUnknown String
  | UnverifiedSolverFailure String

predicateTranslationExact :: HsPred rs ci -> Bool
verifyPredicate :: HsPred rs ci -> IO PredicateVerification
```

`FieldWitness projection` remains abstract and nominal. Its private representation gains a
future-proof evidence discriminator. The only witness constructor available to existing callers
remains:

```haskell
fieldWitness ::
  ( FieldProjection projection
  , KnownSymbol (FieldName projection)
  , Typeable projection
  , Typeable (FieldOwner projection)
  , Typeable (FieldResult projection)
  ) =>
  FieldWitness projection
```

The implementation may expose the following read-only helper from the documented-internals
section so `Keiki.Symbolic` and tests can classify the abstract witness:

```haskell
fieldWitnessHasExactDomain :: FieldWitness projection -> Bool
```

For every witness constructible in this plan, that helper returns `False`. Plan 83 adds the exact
constructor and makes exact-domain evidence necessary but not by itself sufficient: predicate-wide
owner-view consistency is also required before a translation can be exact. The type of `symSatExt`
does not change; its returned `Just` value gains the unconditional concrete postcondition already
claimed by its Haddocks:

```haskell
maybe True (models (SymPred predicate)) (symSatExt predicate)
```
