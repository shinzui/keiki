---
id: 83
slug: add-exact-reconstructible-symbolic-field-projection-domains
title: "Add exact reconstructible symbolic field projection domains"
kind: exec-plan
created_at: 2026-08-01T02:59:24Z
intention: "intention_01kyxm5322e9mvkcyw7a7zsyd6"
---

# Add exact reconstructible symbolic field projection domains

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

After this change, a consumer can declare the exact image of a typed field projection and a
checked inverse from every symbolic key to a concrete owner. Keiki can then constrain the solver
to the declared image, classify only relation-preserving predicates as translation-exact, and
return projection-origin model values together with reconstructed owners. A finite enum projection
and a validated `Text` projection, including a TypeID-shaped key, become provable in both
directions without teaching Keiki the consumer's owner type.

The visible demonstration belongs in `test/Keiki/FieldProjSpec.hs`. A two-constructor owner whose
keys are `"open"` and `"closed"` rejects a third solver string, reconstructs both satisfying keys,
and reports a broken inverse as a contract violation rather than a verified model. A declarative
TypeID-style text pattern accepts exactly its documented lexical language, including overflow,
version, and variant restrictions. Predicates that read two different projection tags from the
same owner path, or read the owner directly as well as a projection, remain conservative until a
future API can express their joint relation.

This plan implements
[IR-4](../improvement-requests/support-domain-constrained-symbolic-field-projections-with-reconstructible-witnesses.md)
on top of the conservative baseline established by
[Plan 82](82-classify-unconstrained-symbolic-field-projections-conservatively.md), and completes the
exactness and model-extraction portions of
[IR-1](../improvement-requests/support-typed-symbolic-field-projections-over-mapped-consumer-values.md).


## Progress

- [x] (2026-08-01T04:04:27Z) Milestone 1: introduce a backend-neutral exact domain algebra with an executable concrete
      membership test and an equivalent SBV constraint compiler.
- [x] (2026-08-01T04:04:27Z) Milestone 2: add coherent exact projection evidence, checked reconstruction laws, and a
      compatibility-safe constructor beside the existing unconstrained `fieldWitness`.
- [ ] Milestone 3: produce a predicate-wide translation report, impose each projection domain once,
      and reject owner-view combinations whose joint relation is not represented.
- [ ] Milestone 4: add detailed solver/model results and route compatibility verification,
      emptiness, determinism, and dead-edge analysis through one result-aware solving kernel.
- [ ] Milestone 5: add exhaustive and adversarial fixtures, update durable documentation and
      release notes, run all project gates, and perform the ADR distillation pass.


## Surprises & Discoveries

- Observation: The Mori SBV corpus is pinned to 14.2, while both Hackage preferred versions and
  upstream tags identify 14.5 as the current release. The inspected `Data.SBV.RegExp` API is
  sufficient and Keiki's existing `sbv >=11.7 && <15` bound already admits 14.5, so no dependency
  edit is necessary.
  Evidence: `mori registry show LeventErkok/sbv --full` located the 14.2 corpus;
  `https://hackage.haskell.org/package/sbv/preferred.json` lists 14.5 first; upstream tag `v14.5`
  resolves to `42b20bdfc72a0bca6c74092c380a4475cbffa8e3`.

- Observation: `UTCTime` is not whole-carrier exact despite its picosecond representation being
  lossless for ordinary POSIX times. The `time` implementation clamps `utctDayTime` with
  `min posixDayLength`, so a leap-second value at 86,401 seconds is not injective through
  `utcTimeToPOSIXSeconds` and `posixSecondsToUTCTime`.
  Evidence: Mori located `mori://haskell/time/packages/time`; its
  `lib/Data/Time/Clock/POSIX.hs` implements that clamp, and
  `lib/Data/Time/Clock/Internal/UTCTime.hs` documents day times below 86,401 seconds.

- Observation: The Milestone 1 and 2 focused projection run passes all existing compatibility
  tests plus the new domain/compiler and declaration-law fixtures.
  Evidence: `cabal test keiki-test --test-option=--match --test-option=projection` completed with
  48 examples and 0 failures at 2026-08-01T04:04:27Z.


## Decision Log

- Decision: Exactness is a property of the complete predicate translation, not a Boolean stored on
  one projection witness.
  Rationale: Two individually reconstructible getters from one owner path can yield an impossible
  pair when translated as independent variables. A direct owner read plus a projected read has the
  same missing relation. Treating either predicate as exact would admit false satisfying models.
  Date: 2026-08-01

- Decision: In this release, one owner base may participate in at most one nominal exact projection
  tag, repeated any number of times, and may not also be read directly if the predicate is to be
  classified exact.
  Rationale: One reconstructed key then determines one concrete owner and repeated reads already
  share a variable. This rule is sufficient and auditable. Supporting several coordinated views
  requires an explicit owner-domain relation and is deferred rather than guessed.
  Date: 2026-08-01

- Decision: Add a closed declarative `ProjectionDomain` algebra; do not accept an arbitrary Haskell
  predicate as domain evidence.
  Rationale: Exactness requires the concrete membership test and the SBV constraint to denote the
  same set. A closed algebra can supply both interpretations from one value and can reject domain
  forms for which the active SBV backend has no exact compiler.
  Date: 2026-08-01

- Decision: Exact projection evidence is attached to the nominal projection tag through a new
  coherent class and an `exactFieldWitness` constructor. The existing `fieldWitness` remains
  unconstrained and inexact.
  Rationale: This preserves source compatibility and avoids a globally unique class on the owner
  type. Different logical fields of one owner may have distinct tags and distinct exact domains.
  A coherent class also makes the evidence per-tag-unique: `SymEnv` emits each memoized key's
  domain constraint once, so value-level evidence would let two call sites supply competing
  domains for one key, with whichever occurrence translates first silently winning. Class
  coherence removes that failure mode by construction.
  Date: 2026-08-01

- Decision: Reconstruction is checked on every returned model with both domain membership and the
  round trip `projectFieldValue owner == key`; a failure is a contract violation, never a verified
  satisfiable result.
  Rationale: The inverse is consumer-supplied code. Runtime checking prevents a dishonest or stale
  declaration from turning a symbolic valuation into a claimed concrete witness.
  Date: 2026-08-01

- Decision: Add detailed result types instead of extending the exported `PredicateVerification`
  sum, and define the old APIs as conservative projections of the detailed results.
  Rationale: Adding constructors to the old sum breaks exhaustive downstream pattern matches. A
  new API can preserve solver status, translation strength, projection models, and edge attribution
  without weakening existing callers.
  Date: 2026-08-01

- Decision: Projection-origin models do not by themselves imply that `symSatExt` can reconstruct a
  complete `RegFile` or command containing an arbitrary consumer-owned type. When its existing
  `ExtractRegFile`/`KnownInCtors` constraints can construct the full carrier, use relation-safe
  exact projection owners as path overrides and always validate the final candidate concretely.
  Rationale: An inverse reconstructs only the owner at one projection path. The detailed API can
  report that path-local value without full-carrier evidence. The compatibility extractor should
  recover exact witnesses when it can, but its existing `Nothing` result remains the conservative
  answer when a complete satisfying pair cannot be built.
  Date: 2026-08-01

- Decision: Whole-carrier domains are exact only when Keiki's symbolic representation is known to
  be isomorphic to the concrete carrier for the operations in use. In particular, do not advertise
  `ProjectionWhole` for machine `Int` while it is represented by unbounded SMT `Integer`.
  Rationale: ADR-0003 already records the `Int` overflow caveat. Exact projection evidence must not
  launder that pre-existing carrier mismatch into a two-way claim. Finite `Int` domains remain
  usable because every enumerated literal has an exact concrete representative.
  Date: 2026-08-01

- Decision: This plan promotes exact projections only when they are used as structural equality
  operands, including inequality expressed as negated equality. Ordering comparisons and
  arithmetic containing a projection remain conservative.
  Rationale: IR-4 explicitly scopes exact nominal equality. A finite result domain does not by
  itself prove that Haskell ordering, arithmetic overflow, normalization, and the active `SymRep`
  operations agree. Those operations need a separate carrier-and-operation contract.
  Date: 2026-08-01

- Decision: `TextPattern` smart constructors reject literals, character sets, and ranges containing
  code points above U+2FFFF.
  Rationale: SMT-LIB strings range over code points U+0000 through U+2FFFF while Haskell `Char`
  reaches U+10FFFF. Admitting the unrepresentable region would let the pure matcher and the SBV
  constraint denote different sets — exactly the divergence this plan forbids, and in the
  direction that can manufacture a false UNSAT. The whole-carrier exactness audit for `Text` must
  record the same bound.
  Date: 2026-08-01

- Decision: An `exactFieldWitness` makes definite-UNSAT gates conditional on the declaration laws,
  and both the adversarial fixtures and ADR-0003 must say so explicitly.
  Rationale: Runtime model checks police only satisfiable models. A domain that omits a key some
  real owner produces yields false UNSAT — a false `VerifiedUnsatisfiable`, falsely blessed
  determinism disjointness, and false dead edges — and no solve-time check can observe it. Only
  the owner-side declaration-law helpers can catch this direction, so it is a shifted trust
  boundary rather than an implementation bug: `fieldWitness`-only predicates keep the
  unconditional soundness guarantee, exact witnesses trade it for precision under the published
  laws. This conditionality is inherent to the capability Keiro requested, not incidental.
  Date: 2026-08-01

- Decision: Input-constructor domination is judged logically, not by conjunction operand order.
  Rationale: Every model satisfying the predicate also activates the matching `PInCtor` atom, so
  `PAnd (projection atom) (PInCtor ...)` supports the same solver-side exactness verdict as the
  guard-first spelling, and the detailed kernel's model checks always evaluate against a
  constructor-consistent candidate. Concrete `evalPred` remains left-to-right and partial for
  mismatched inputs; that pre-existing sharp edge stays owned by validation warnings and Plan 82's
  exception-guarded `symSatExt` recheck, not by the exactness report.
  Date: 2026-08-01

- Decision: Milestones 3 and 4 form one indivisible release unit.
  Rationale: After Milestone 3, an exact report lets `verifyPredicate` reach `VerifiedSatisfiable`
  with domain constraints applied but with the model-membership, inverse, and round-trip contract
  checks arriving only in Milestone 4. That intermediate state must never be published, tagged, or
  used to mark IR-4 implemented.
  Date: 2026-08-01

- Decision: Keep the existing SBV dependency bounds unchanged and compile the validated text AST
  directly to `Data.SBV.RegExp`.
  Rationale: The current bound already includes the authoritative 14.5 release, the required
  literal/range/concatenation/union/loop constructors are present in the inspected source, and a
  bound change would add PVP surface without improving compatibility.
  Date: 2026-08-01

- Decision: Text literal and character-set smart constructors return
  `Either DomainConstructionError TextPattern`, matching the already-fallible range and repetition
  constructors.
  Rationale: Literals and sets can contain Haskell code points above U+2FFFF. A total constructor
  with a hidden exception would not satisfy the plan's requirement that such declarations be
  rejected before a witness exists.
  Date: 2026-08-01

- Decision: The deferred multi-view mechanism is recorded as finite-owner joint enumeration.
  Rationale: For a finite owner domain the translator can emit
  @⋁ owner (⋀ tag (var_tag == getter_tag owner))@, which represents the joint owner relation
  exactly and would make two exact tags over one base — and direct-plus-projected reads — exact.
  It requires declared owner-enumeration evidence and cannot cover infinite validated-text owners,
  so it stays out of scope here, but naming it prevents the "explicit joint owner-domain relation"
  deferred by IR-4 from being re-derived from scratch.
  Date: 2026-08-01


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

`src/Keiki/Core.hs` owns the typed predicate AST. A `FieldProjection projection` instance associates
a nominal tag with `FieldOwner projection`, `FieldResult projection`, a total getter, and diagnostic
metadata. The abstract `FieldWitness projection` travels inside `TFieldProj`; `PBReg` and `PBInp`
restrict the owner to a stable register or input-field path. Concrete evaluation invokes the getter
through `fieldWitnessGet`.

`src/Keiki/Symbolic.hs` owns the curated `Sym` registry and the SBV translation. Each structural
read is memoized in `SymEnv`. A projection key includes its base path, projection tag `TypeRep`,
owner `TypeRep`, and result `TypeRep`, so repeated occurrences of one tag and base share one solver
variable. The released translator does not constrain that variable to the concrete getter image,
relate different tags over the same base, or extract it into a model. Plan 82 makes this
over-approximation visible to `predicateTranslationExact` while retaining the sound direction:
unsatisfiability over the larger symbolic domain proves concrete unsatisfiability.

An exact projection declaration needs three connected pieces. Its domain denotes every and only
the possible result keys. Its inverse returns an owner for every domain member. Its getter maps the
returned owner back to the same key. These give a per-projection correspondence:

```text
member domain key
  iff reconstructFieldOwner key returns owner
  and projectFieldValue owner == key
```

The reverse direction must also hold for owners exercised by the application:

```text
member domain (projectFieldValue owner)
```

The inverse need not recover the original owner when the owner contains non-projected data, but it
must recover a canonical owner that projects to the requested key. A normalizing getter is allowed
only when each admitted normalized key has such a canonical owner. A many-to-one getter is not a
problem by itself; claiming that two independent projections of the same richer owner are jointly
exact is the problem, because independently reconstructed canonical owners may disagree.

This distinction controls predicate-global exactness. Suppose projections `UserId` and `UserStatus`
both read register `#user`. Even if each has a finite exact domain and inverse, independent symbolic
variables permit `(id1, suspended)` when no concrete user has that combination. Likewise, a direct
comparison on `#user` and a comparison on `UserId #user` omit the getter equation between those
values. The first implementation therefore marks these combinations as a conservative
over-approximation. One tag repeated from one base remains exact, and distinct owner bases remain
independent concrete choices.

Input projections have an additional condition. `PBInp` reads are meaningful only for their
associated `InCtor`. Existing validation warns when a read is not guarded by the matching
`PInCtor`. The exactness report must use the same structural implication analysis so a solver model
cannot claim exactness for a field belonging to an inactive constructor. Extract the existing
guard-checking logic into a shared pure helper where necessary; do not maintain subtly different
rules in validation and symbolic verification.

`src/Keiki/Internal/SymbolicTypes.hs` centralizes runtime discovery of the types accepted by the
symbolic layer. Extend this internal registry with the carrier fact needed to decide whether a
whole-carrier projection domain is exact. Fixed-width integers, `Bool`, `Integer`, exact `Text`,
and other genuinely round-tripping representations may opt in. `Natural` remains exact with its
non-negative `constrainSymDomain`. Machine `Int` does not opt in while its overflow behavior differs
from the SMT representation. The implementation must audit `UTCTime` rather than assuming that its
chosen precision spans every concrete value.

The new domain algebra belongs in an exposed module such as `src/Keiki/ProjectionDomain.hs` so
consumers can construct declarations without importing SBV. It offers finite enumeration for any
supported result type and a declarative full-string pattern language for `Text`. The text language
must be closed under only constructs that have equivalent pure and SBV interpretations: literals,
explicit character sets or ranges, concatenation, alternation, and bounded repetition are enough
for TypeID-shaped values. Smart constructors validate reversed ranges, empty character sets,
negative bounds, invalid repetition intervals, and code points above U+2FFFF before a witness can
be constructed: SMT-LIB strings range over U+0000 through U+2FFFF while Haskell `Char` reaches
U+10FFFF, and admitting the unrepresentable region would let the pure matcher and the SBV
constraint denote different sets.

A TypeID-style fixture must encode the entire accepted lexical domain, not merely a prefix and
length. Its fixed 26-character suffix uses the Crockford Base32 alphabet; the first encoded
character observes the 128-bit overflow restriction; and version/variant positions observe the
same restrictions as the consumer format. This fixture is intentionally schema-derived and local:
Keiki must not gain a dependency on the requester's ID library. The requesting artifacts are
canonically identified as
`mori://shinzui/keiro/okf/improvement-requests/concepts/IR-12` and
`mori://shinzui/keiro/okf/improvement-requests/concepts/IR-14`; current Mori registry coverage may
not resolve those artifact kinds yet, but the URIs remain the durable cross-repository references.

The local SBV dependency is `mori://LeventErkok/sbv/packages/sbv`. Its source includes a declarative
regular-expression AST and full-string `match` support, but the implementation must use Mori to
read the version actually selected by the project and verify the latest compatible release against
Hackage and upstream tags before choosing imports or bounds. Do not infer the API from this plan.

Four accepted ADRs bound the implementation.
[ADR-0003](../adr/0003-proof-gates-fail-conservatively.md) requires definite unsatisfiability
before a proof gate succeeds and records carrier limitations; this plan adds the durable rules for
exact domains and predicate-global owner relations.
[ADR-0002](../adr/0002-event-logs-must-reproduce-forward-state.md) requires forward and replay
state equality, so symbolic evidence cannot change evaluation or event construction.
[ADR-0004](../adr/0004-composition-uses-snapshot-updates-and-checked-boundaries.md) requires
non-structural mapped boundaries to lower visibly to opacity.
[ADR-0001](../adr/0001-structural-re-indexing-for-sound-replay.md) protects typed slot identity
across schema rewrites; the new base-path model must continue to use structural position and type
identity rather than display names alone.


## Plan of Work

Milestone 1 introduces the domain language independently of projection witnesses. Add
`src/Keiki/ProjectionDomain.hs`, expose it from the appropriate Cabal library stanza, and re-export
it from `Keiki.Symbolic` if that remains the documented single-import surface. Use an abstract
definition equivalent to:

```haskell
data ProjectionDomain a
  = ProjectionWhole
  | ProjectionFinite (NonEmpty a)
  | ProjectionText TextPattern

data DomainConstructionError

memberProjectionDomain :: Eq a => ProjectionDomain a -> a -> Bool
finiteProjectionDomain :: NonEmpty a -> ProjectionDomain a
textProjectionDomain :: TextPattern -> ProjectionDomain Text
```

The real representation may use a GADT so `ProjectionText` fixes `a ~ Text`. Deduplicate finite
values in a stable order so both concrete membership and the SBV disjunction use the same set. An
empty exact image is not a valid total projection domain because every well-formed owner projects
to some result; reject it at construction instead of encoding an impossible witness.

Define `TextPattern` through validated smart constructors, not exported data constructors. Include
literal text, an explicit code-point set or inclusive ranges, concatenation, alternation, and
bounded repetition. State and test that matching covers the complete `Text` value. Reject code
points above U+2FFFF in every constructor with a `DomainConstructionError`, and test the boundary
at the last representable and first unrepresentable code point. Provide one pure
interpreter and one internal SBV compiler derived from the same AST. If SBV cannot express one
validated form exactly for the project version, the compiler returns a typed unsupported reason;
translation then omits the constraint and reports an over-approximation. It must never emit a
stronger partial constraint.

Add `test/Keiki/ProjectionDomainSpec.hs` with exhaustive small-alphabet tests comparing the pure
matcher with solver membership, plus boundary examples for every smart constructor. Use generated
strings only over small bounded alphabets; no probabilistic test is a substitute for the explicit
TypeID boundaries in Milestone 5. Extend `src/Keiki/Internal/SymbolicTypes.hs` with a read-only
whole-carrier exactness classification and unit-test every registered `Sym` type. Audit `toSym` and
`fromSym` round trips at minimum and retain separate operation-level caveats where they already
exist. The `Text` classification must record the U+2FFFF representability bound, and the `UTCTime`
audit must include leap-second `DiffTime` values (days longer than 86400 seconds), where the
picosecond encoding's injectivity and surjectivity are least obvious.

Milestone 2 connects a domain and inverse to a nominal tag. In `src/Keiki/Core.hs`, introduce a
coherent class shaped as follows, with final constraints adjusted only when compilation proves they
are necessary:

```haskell
class FieldProjection projection => ExactFieldProjection projection where
  fieldProjectionDomain :: Proxy projection -> ProjectionDomain (FieldResult projection)
  reconstructFieldOwner ::
    Proxy projection ->
    FieldResult projection ->
    Maybe (FieldOwner projection)

exactFieldWitness ::
  ( ExactFieldProjection projection
  , KnownSymbol (FieldName projection)
  , Typeable projection
  , Typeable (FieldOwner projection)
  , Typeable (FieldResult projection)
  , Eq (FieldResult projection)
  ) =>
  FieldWitness projection
```

Keep `FieldWitness` abstract and nominal. Its private exact evidence stores the domain, inverse, and
the dictionaries needed by translation and model checking. The existing `fieldWitness` continues
to build an unconstrained witness, even for a tag that also has an `ExactFieldProjection` instance;
exactness must be an explicit call-site choice. Add eliminators internal to Keiki for compiling the
domain and reconstructing a model, but do not export the private evidence constructor or a Boolean
that can be forged.

Document the declaration laws next to `ExactFieldProjection` and provide executable helpers for
consumer test suites. One helper checks a supplied owner by projecting it, testing membership,
reconstructing that key, and checking the getter round trip. Another checks a supplied domain key.
Finite domains can be checked exhaustively at test time. Infinite text domains cannot prove a
Haskell inverse total in general, so each returned solver model is still checked dynamically and
generators remain responsible for schema/codec conformance testing.

Milestone 3 replaces the local Boolean walk with a predicate-wide report. In
`src/Keiki/Symbolic.hs`, add public report types equivalent to:

```haskell
data TranslationStrength
  = ExactTranslation
  | ConservativeOverApproximation (NonEmpty TranslationIssue)

data TranslationIssue
  = OpaqueApplication
  | UnsupportedEquality SomeTypeRep
  | UnsupportedOrdering SomeTypeRep
  | UnsupportedArithmetic SomeTypeRep
  | UnconstrainedProjection ProjectionDescriptor
  | UnsupportedProjectionDomain ProjectionDescriptor String
  | ProjectionUsedOutsideEquality ProjectionDescriptor
  | ConflictingProjectionViews ProjectionBaseDescriptor
  | DirectAndProjectedOwnerRead ProjectionBaseDescriptor
  | UnguardedProjectionInputRead ProjectionDescriptor

predicateTranslationReport :: HsPred rs ci -> TranslationStrength
predicateTranslationExact :: HsPred rs ci -> Bool
```

The exported descriptors must contain stable structural and nominal metadata but no SBV variable
labels and no functions. Exact constructor names may differ to match project style; the semantic
distinctions may not be collapsed. Preserve issue order by first predicate occurrence and
deduplicate identical issues so tests and diagnostics are deterministic.

Track the term context while building the report. An exact projection is eligible only as an
operand of structural `PEq`; `PNot (PEq ...)` supplies inequality without changing that rule. A
projection beneath `TArith` or used by `PCmp` produces `ProjectionUsedOutsideEquality`, even if its
result carrier otherwise has numeric or ordering dictionaries. The compatibility translator may
still translate that expression as an over-approximation and apply a sound domain constraint.

During the report walk, collect every direct register/input read and every projection read by
structural base. One base with no direct read and exactly one distinct exact tag is relation-safe;
repetition of the same tag is allowed. Two exact tags, an exact and unconstrained tag, or a direct
owner read plus any projection at that base makes the predicate an over-approximation. Distinct
bases do not conflict. Base identity includes constructor identity and slot position for inputs and
slot position for registers, with diagnostic names carried only for display. Apply the shared
input-constructor implication check before calling a `PBInp` projection exact. Judge domination
logically rather than by conjunction operand order: `PAnd (projection atom) (PInCtor ...)`
supports the same exactness verdict as the guard-first spelling, because every satisfying model
also activates the matching constructor atom; concrete evaluation order remains the province of
validation warnings and Plan 82's exception-guarded `symSatExt` recheck.

Extend `SymEnv` with a set of projection keys whose domain constraint has successfully been emitted.
On the first read of an exact witness, allocate or reuse the memoized variable, compile the domain,
constrain it, and only then mark the key constrained. This order handles a predicate in which an
unconstrained witness occurrence precedes an exact witness for the same nominal key: the variable
must still receive the later safe constraint, while the report remains inexact because the caller
selected inconsistent evidence. Repeated exact reads emit one logical constraint. A compiler
failure leaves the key unmarked, emits no partial constraint, and is carried into the detailed
translation result.

Keep translation over-approximate even when the report is inexact. Finite domains and successfully
compiled text domains may still narrow their own projection variables because every concrete
getter result is inside the declared domain. Do not add an equation between unrelated projection
tags or between an owner variable and a projected variable. The global report, not wishful
constraints, is what prevents such a query from being promoted to exact satisfiability.

Milestone 4 introduces a result-aware solver kernel. The translation operation used by the kernel
must return both the SBV predicate and its report/evidence registry. Add public detailed results
equivalent to:

```haskell
data ProjectionModel = ProjectionModel
  { projectionModelDescriptor :: ProjectionDescriptor
  , projectionModelKey :: Dynamic
  , projectionModelOwner :: Dynamic
  }

data PredicateVerificationDetail
  = PredicateSatisfiable TranslationStrength [ProjectionModel]
  | PredicateUnsatisfiable TranslationStrength
  | PredicateSolverUnknown TranslationStrength String
  | PredicateSolverFailure TranslationStrength String
  | PredicateProjectionContractViolation TranslationStrength ProjectionDescriptor String

verifyPredicateDetailed :: HsPred rs ci -> IO PredicateVerificationDetail
```

Use `Dynamic` together with the descriptor's `SomeTypeRep` values because one predicate may contain
several unrelated owner and key types. Export typed eliminators such as
`projectionModelKeyAs` and `projectionModelOwnerAs`; callers must not cast based on a display name.
For every projection variable present in a satisfiable model, decode its `SymRep`, check concrete
domain membership, run the inverse, and verify `fieldWitnessGet witness owner == key`. Preserve one
model entry per structured projection key, ordered by first occurrence. Any missing solver value,
failed cast, rejected domain member, failed inverse, or failed round trip becomes
`PredicateProjectionContractViolation` or a solver/model failure; it never becomes a verified
model.

Define `verifyPredicate` as the compatibility projection of this detailed result. It returns
`VerifiedSatisfiable` only for `PredicateSatisfiable ExactTranslation ...`,
`VerifiedUnsatisfiable` only for `PredicateUnsatisfiable ExactTranslation`, maps every definite
inexact result to `UnverifiedOpaque`, and preserves unknown/failure messages. This deliberately
keeps the Plan 82 behavior even though the detailed result records that an inexact unsatisfiable
query is a sound one-sided proof.

Route `symIsBot` through the same solver-status decoder and return `True` for definite
unsatisfiability regardless of translation strength. It must return `False` for satisfiable,
unknown, failure, or contract-violation outcomes. Do not make `symIsBot` extract projection owners;
no reconstruction is needed to trust UNSAT. Preserve `NOINLINE` and its pure compatibility wrapper.

Add detailed determinism and dead-edge APIs that retain `EdgeRef` attribution and a
`PredicateVerificationDetail` for every tested guard or pair. Define the old
`checkTransitionDeterminismSym` and `checkDeadEdgesSym` in terms of the shared kernel semantics:
only definite UNSAT suppresses an overlap warning or proves an edge dead. SAT, `Unknown`, solver
failure, and an inexact translation all remain conservative; an inexact SAT result is possible
overlap, not a concrete reconstructed pair. Avoid running the solver twice merely to obtain the
detail and compatibility answer.

Leave `symSatExt`'s public type and full-witness requirements unchanged. Extend its internal
register/input extraction path so a relation-safe exact `ProjectionModel` can override the owner at
its structural `PBReg` or `PBInp` position when that owner is part of the extractable full carrier.
Use position and constructor identity, not display names alone; if preserving source compatibility
requires a new private positional traversal or a defaulted method on `ExtractRegFile`, choose the
private traversal where possible and record the choice in the Decision Log. Never combine
inconsistent owners from two inexact views of one base.

After building the complete `(RegFile rs, ci)` candidate, evaluate the original predicate
concretely and return `Just` only if it holds. This recheck, introduced by Plan 82, remains the final
soundness boundary for ordinary, opaque, unconstrained-projection, and exact-projection models. A
path-local `ProjectionModel` is not automatically a complete witness; if the override cannot be
installed or the final check fails, `symSatExt` returns `Nothing`, which is not an UNSAT proof. Add
tests that make this distinction explicit so future documentation cannot again conflate a scalar
projection model with a full consumer model.

Milestone 5 builds end-to-end fixtures. Add a finite enum owner with a bijective key projection and
test every domain value, every owner value, the excluded-third-key UNSAT case, satisfiable model
reconstruction, and repeated-tag memoization. Add a richer owner with two individually exact
projections and prove that different bases are exact while two tags on one base and a direct plus
projected read are reported inexact. Include an unconstrained/exact witness mix in both occurrence
orders to exercise domain-constraint bookkeeping.

Add a validated text owner whose inverse parses only full matches. Exercise accepted and rejected
prefixes, suffix lengths, alphabet boundaries, overflow-leading characters, version nibble, variant
bits, separators, empty strings, and trailing data for the TypeID-style pattern. Assert concrete
membership equals solver membership for each boundary sample and that every satisfying model
round-trips. Deliberately define test-only broken declarations for three law violations: an
inverse that rejects an admitted key, an inverse that returns an owner with a different projected
key, and a domain that omits a key some real owner produces. The two broken inverses must yield a
contract violation. The under-declared domain is the false-UNSAT direction: no solve-time check
can observe it, so its fixture must instead prove that the owner-side declaration-law helper
reports the violation, and the documentation must state that only those helpers police this
direction. Never expose these broken declarations from library code.

Update Haddocks in `src/Keiki/Core.hs`, `src/Keiki/ProjectionDomain.hs`, and
`src/Keiki/Symbolic.hs`; the user guide or README section that introduces symbolic projections;
both improvement requests; ADR-0003; and `CHANGELOG.md`. The documentation must distinguish
path-exactness, domain-exactness, predicate-global relational exactness, one-sided UNSAT proofs,
path-local projection models, and full `symSatExt` witnesses. ADR-0003 must additionally record
the shifted trust boundary: for a predicate containing an `exactFieldWitness`, the definite-UNSAT
gates — `VerifiedUnsatisfiable`, `symIsBot`, determinism blessing, and dead-edge proofs — are
sound only conditional on the declaration laws, because an under-declared domain manufactures
false UNSAT; `fieldWitness`-only predicates keep the unconditional guarantee, and generators such
as Keiro must wire the declaration-law helpers into their generated conformance suites. Mark IR-4
implemented only after all validation passes. At completion, reread this plan's Decision Log, Surprises & Discoveries, and
Outcomes & Retrospective and promote all durable semantic decisions to ADR-0003 or a superseding
ADR.


## Concrete Steps

Run every command from `/Users/shinzui/Keikaku/bokuno/keiki`. Before choosing imports or changing a
dependency bound, locate SBV through Mori and verify releases against both authoritative sources:

```bash
mori registry show LeventErkok/sbv --full
mori registry docs LeventErkok/sbv
mori registry show shinzui/keiki --full
curl -fsSL https://hackage.haskell.org/package/sbv/preferred.json
git ls-remote --tags https://github.com/LeventErkok/sbv.git
curl -fsSL https://hackage.haskell.org/package/keiki/preferred.json
git ls-remote --tags https://github.com/shinzui/keiki.git
```

At plan creation, Keiki's authoritative Hackage release and upstream tag are `0.6.0.0`. The local
Mori SBV corpus reports 14.2, but that observation is not a release decision; repeat all checks when
implementing and record any compatibility choice in the Decision Log.

After Milestone 1, run the domain-specific tests:

```bash
cabal test keiki-test --test-option=--match --test-option="projection domain"
cabal build keiki
```

The focused run must report zero failures, including pure-versus-SBV membership agreement. After
Milestones 2 and 3, run the projection and verification groups:

```bash
cabal test keiki-test --test-option=--match --test-option=projection
cabal test keiki-test --test-option=--match --test-option=verification
```

After Milestone 4, also run the solver-backed analysis groups using their exact current Hspec
labels, updating this plan if those labels differ:

```bash
cabal test keiki-test --test-option=--match --test-option=determinism
cabal test keiki-test --test-option=--match --test-option="dead edge"
cabal test keiki-test --test-option=--match --test-option="witness extraction"
```

Finish with formatting, all build/test gates, repository validation, and whitespace checks:

```bash
nix fmt
cabal test all
cabal build all
nix flake check
okf validate docs/improvement-requests --strict --profile mori/improvement-requests-profile.dhall --profile-enforce --log-enforce
git diff --check
```

Expected successful summaries include `0 failures`, successful Cabal builds, a successful flake
check, `OK: 4 concepts` or a larger current count, and no `git diff --check` output. Review the
rendered Haddocks or generated documentation if the project supplies a documentation gate.

Choose the next package version only after the release checks and a PVP audit. Adding exported
classes, types, constructors, and functions is ordinarily a minor-version change under the Haskell
PVP; changing existing constructor sets or method types is deliberately avoided. Use a
Conventional Commit subject and include both execution trailers, for example:

```text
feat(symbolic): add exact projection domains and models

ExecPlan: docs/plans/83-add-exact-reconstructible-symbolic-field-projection-domains.md
Intention: intention_01kyxm5322e9mvkcyw7a7zsyd6
```


## Validation and Acceptance

The finite projection fixture is accepted when its excluded-third-key predicate is definitely
unsatisfiable under the exact domain, every satisfiable key yields a typed `ProjectionModel`, and
each reported owner projects back to that exact key. The same predicate built with `fieldWitness`
instead of `exactFieldWitness` remains a conservative over-approximation and maps to
`UnverifiedOpaque` through `verifyPredicate`.

The text domain is accepted when the pure matcher and SBV constraint agree for exhaustive bounded
alphabets and for all TypeID-style boundary examples. Partial prefix checks, host-language regexes,
or a parser that accepts a stricter or looser set than the symbolic constraint do not satisfy this
plan. A solver model outside the concrete parser's language is a test failure, not an allowed
approximation. Constructors must reject code points above U+2FFFF, with boundary coverage at the
last representable and first unrepresentable code point.

Predicate-global classification is accepted when repeated uses of one exact tag and base are exact;
the same tag on distinct bases is exact; distinct exact tags on distinct bases are exact; two tags
on one base are inexact; direct and projected reads of one base are inexact; an unguarded input
projection is inexact; and a projection dominated by its matching constructor guard is exact.
Boolean nesting, especially disjunction and negation, must be included so the constructor-guard
analysis does not rely on a syntactically nearby but non-dominating atom, and the reversed
conjunction order `PAnd (projection atom) (PInCtor ...)` must classify exactly as its guard-first
spelling.

Equality and negated equality over exact projections may receive `ExactTranslation`. Ordering or
arithmetic involving a projection must report `ProjectionUsedOutsideEquality` and remain
conservative until a later operation-level contract is implemented.

Contract enforcement is accepted when both malformed inverse fixtures return an explicit detailed
failure and never `VerifiedSatisfiable`, and when the under-declared domain fixture is reported by
the owner-side declaration-law helper. Finite declaration-law helpers exhaust the declared image
and, given an owner enumeration, the owner-side law `member domain (projectFieldValue owner)`.
All extracted keys and owners are recoverable only through matching `TypeRep` evidence, and two
fields with the same display name but different structural paths cannot collide.

Compatibility is accepted when existing `FieldProjection` instances and `fieldWitness` call sites
compile unchanged; existing `PredicateVerification` matches need no new branch; `symIsBot` proves
the same or more definite UNSAT cases without treating `Unknown` as proof; and existing determinism
and dead-edge APIs remain conservative. `symSatExt` retains its signature, uses exact reconstructed
owners when its existing full-carrier evidence permits, rechecks every final pair with concrete
semantics, and never claims that a path-local projection owner alone is a full register file or
command witness.

Concrete evaluation, validation, composition lowering, checked-boundary rejection, update/output
restrictions, forward stepping, emitted events, and replay remain unchanged. The existing replay
and composition suites must pass, satisfying ADR-0002 and ADR-0004.


## Idempotence and Recovery

All lookup, build, test, formatting, and validation commands are safe to repeat. Domain smart
constructors and witness declarations are pure; no persisted representation or data migration is
introduced. Keep the domain compiler behind one function so a failed SBV API experiment can be
replaced without changing the public declaration algebra.

Implement one milestone at a time and keep its focused tests green. Milestones 3 and 4 are one
release unit: after Milestone 3 an exact report can carry `verifyPredicate` to
`VerifiedSatisfiable` while the model and inverse contract checks arrive only in Milestone 4, so
never publish, tag, or mark IR-4 implemented between them. If a text pattern cannot be
compiled exactly with the selected SBV version, return `UnsupportedProjectionDomain`, leave the
symbolic variable unconstrained, and classify the translation conservatively. Do not approximate
with a subset constraint, because that could create a false UNSAT proof. A superset fallback is
sound for UNSAT but is unnecessary when omitting the constraint already supplies the widest safe
superset.

If reconstruction fails for a satisfiable model, retain enough descriptor, key, and law-failure
information in the detailed result to reproduce the declaration bug. Do not silently retry with a
default owner, discard the projection model, or downgrade it to a verified scalar-only model.

If changing `FieldWitness` causes downstream errors, preserve its nominal role and the public
signatures of `fieldWitness`, `fieldWitnessGet`, `regProj`, `inpProj`, and `TFieldProj`. The
constructor remains private. If the full gate exposes unrelated dirty-worktree failures, record the
exact evidence in Surprises & Discoveries and do not revert user changes.


## Interfaces and Dependencies

The final public domain surface is backend-neutral. Exact names may follow existing export style,
but it must provide the capabilities represented by:

```haskell
data ProjectionDomain a
data TextPattern
data DomainConstructionError

finiteProjectionDomain :: Eq a => NonEmpty a -> ProjectionDomain a
wholeProjectionDomain :: ProjectionDomain a
textProjectionDomain :: TextPattern -> ProjectionDomain Text
textLiteral :: Text -> TextPattern
textCharSet :: NonEmpty Char -> TextPattern
textCharRanges :: NonEmpty (Char, Char) -> Either DomainConstructionError TextPattern
textConcat :: NonEmpty TextPattern -> TextPattern
textAlternation :: NonEmpty TextPattern -> TextPattern
textRepeatBetween :: Natural -> Natural -> TextPattern -> Either DomainConstructionError TextPattern
memberProjectionDomain :: Eq a => ProjectionDomain a -> a -> Bool
```

The implementation may choose validated wrapper types for bounds and code points to make invalid
states unrepresentable. The module must not expose SBV types. The internal compiler consumes the
same `ProjectionDomain` value and either emits an equivalent SBV constraint or a typed unsupported
reason.

`src/Keiki/Core.hs` exports `ExactFieldProjection` and `exactFieldWitness` beside the existing
interfaces:

```haskell
class FieldProjection projection => ExactFieldProjection projection where
  fieldProjectionDomain :: Proxy projection -> ProjectionDomain (FieldResult projection)
  reconstructFieldOwner ::
    Proxy projection ->
    FieldResult projection ->
    Maybe (FieldOwner projection)

fieldWitness :: FieldProjection projection => FieldWitness projection
exactFieldWitness :: ExactFieldProjection projection => FieldWitness projection
```

The abbreviated constraints above are completed with the existing `KnownSymbol`, `Typeable`, and
result equality evidence. No global instance is required for `FieldOwner projection`, and no
existing `FieldProjection` instance acquires a new method.

`src/Keiki/Symbolic.hs` exports the translation report, projection descriptors/models, detailed
verification result, typed model eliminators, and detailed transducer analyses. Existing exports
remain source-compatible:

```haskell
predicateTranslationReport :: HsPred rs ci -> TranslationStrength
predicateTranslationExact :: HsPred rs ci -> Bool
verifyPredicateDetailed :: HsPred rs ci -> IO PredicateVerificationDetail
verifyPredicate :: HsPred rs ci -> IO PredicateVerification
symIsBot :: HsPred rs ci -> Bool
symSatExt :: (ExtractRegFile rs, KnownInCtors ci) => HsPred rs ci -> Maybe (RegFile rs, ci)
```

Use the existing `containers`, `text`, `base`, and `sbv` dependencies where possible. `Data.Dynamic`
and `Type.Reflection` come from `base`; `NonEmpty` comes from `base`. Do not add a runtime regex
package or a dependency on `mmzk-typeid`: both would create a second semantics that could diverge
from the SBV constraint. Any `sbv` bound change must be justified by source inspection through Mori,
then verified against Hackage and upstream tags before editing the Cabal file.


Revision note (2026-08-01T04:04:27Z): Recorded completion and focused validation of Milestones 1
and 2, the authoritative dependency audit, the `UTCTime` leap-second carrier finding, and the two
implementation decisions that preserve exact pure/SBV semantics.
