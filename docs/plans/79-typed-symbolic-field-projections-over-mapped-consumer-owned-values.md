---
id: 79
slug: typed-symbolic-field-projections-over-mapped-consumer-owned-values
title: "Typed symbolic field projections over mapped consumer-owned values"
kind: exec-plan
created_at: 2026-07-28T11:35:00Z
intention: "intention_01kym838n3emd9f6qgw288sx0x"
---

# Typed symbolic field projections over mapped consumer-owned values

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.

This plan implements the improvement request
`docs/improvement-requests/support-typed-symbolic-field-projections-over-mapped-consumer-values.md`
(Keiki IR-1, filed by the `shinzui/keiro` project). The IR is the source statement of intent,
but this plan repeats every fact and acceptance condition needed to implement the change; a
reader does not need any document outside the working tree and this plan.


## Purpose / Big Picture

Keiki is a pure Haskell library for event-sourced workflow transducers: a spec author
declares states, edges, guards, register updates, and output events, and Keiki both executes
the spec and *analyzes* it — an SBV/z3-backed symbolic layer proves guards mutually
exclusive, detects dead edges, and checks that recorded events can deterministically replay
the state.

Today a guard can read a scalar register or input field structurally, but if a register slot
(or input-constructor field) holds a whole consumer-owned record — say a `DocInfo` value with
a `contentHash` field, copied wholesale into the register by a mapping layer — the only way a
guard can read `contentHash` is `TApp1 getContentHash`, an opaque function application. The
solver cannot see through it, the mutual-exclusion and dead-edge analyses silently degrade,
and the opt-in `OpaqueGuard` audit flags the edge. Downstream, the Keiro DSL therefore forces
authors to duplicate every decision-relevant scalar into a separate command or register
field.

This need is grounded in a concrete cross-repository migration, not an invented convenience.
Mori MasterPlan 22 replaces Mori's legacy Project decider/event mirror with functional Keiki
transducers generated through `keiro-dsl`; its ExecPlan 171 supplies the structural mapped-type
prerequisite. That work exposed the gap for structural consumer-owned records and filed
Keiro IR-1. Keiro MasterPlan 25 implements the mapped-type and codec foundation but
deliberately sends solver-visible field projection
back to Keiki as this IR because only Keiki can define an AST node whose concrete evaluator,
symbolic translator, replay validator, and composition behavior agree. The active Mori port
can remain sound by promoting identity and content hashes to scalar registers; that is the
safe compatibility path, not evidence that the missing structural operation belongs in
Keiro or in an opaque Haskell escape hatch.

Keiro research note 14 classifies first-class symbolic field projection as a medium-risk
extension that can preserve the guarantees with new checked machinery, and recommends
Experiment C: one solver-visible `Text` field, with evaluation, validation, diagnostics,
mutation testing, and unchanged replay proved before DSL syntax. This plan implements that
experiment and the additional total-walker/composition obligations imposed by Keiki's current
public `Term` type; it does not turn nested projection into the default domain model.

After this change, a spec author writes a guard over one *field* of such a mapped value
through a new first-class term, `TFieldProj`, backed by an abstract `FieldWitness` for a
nominal projection tag. The tag has one coherent `FieldProjection` instance defining the
owner type, result type, field name, diagnostic shape label, and total getter. Concretely,
where today one must promote `contentHash` to its own
register slot, after this plan the guard

```haskell
regProj docHashW #doc .== inpProj docHashW newDocCtor #doc
```

(comparing `doc.contentHash` in the register against `doc.contentHash` in the incoming
command) evaluates by applying the getter and translates both complete paths to SBV
variables. Register and input paths remain distinct, while repeated reads of either exact
path share one variable, so the solver can reason about equality/inequality combinations
without falsely equating the two bases. The guard does not trigger the `OpaqueGuard` audit,
renders with dotted paths in diagnostics, and leaves replay semantics untouched. The
capability is released and tagged so Keiro can pin it; Keiro generates nominal tags,
`FieldProjection` instances, and witnesses and proves their provenance against its codecs —
Keiki defines and tests the laws.

Observable outcome: after Milestone 5, `cabal test all` passes with new z3-backed tests
proving `proj == proj` is valid, a concrete-to-symbolic agreement property passes for both
register and input bases, structurally preservable compositions remain solver-visible, and
`TApp1` guards still audit as opaque. The repository then carries a `v0.4.0.0` tag whose
changelog names this capability and its checked-composition boundary.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] (2026-07-28T13:06:23Z) M1: add the nominal `FieldProjection` class, abstract `FieldWitness`, `ProjBase`, `TFieldProj`, and smart constructors `fieldWitness`/`regProj`/`inpProj` to `src/Keiki/Core.hs`
- [x] (2026-07-28T13:06:23Z) M1: extend every total `Term` walker in `src/Keiki/Core.hs`, `src/Keiki/Render/Pretty.hs`, `src/Keiki/Composition.hs`, and `src/Keiki/Profunctor.hs`; preserve or explicitly lower projections during composition
- [x] (2026-07-28T13:06:23Z) M1: export the new Core names and add evaluation, dotted-path, opacity, profunctor, and checked/raw composition tests
- [x] (2026-07-28T13:06:23Z) M2: add the cycle-free curated-type classifier in `src/Keiki/Internal/SymbolicTypes.hs` and make `discoverSym`/`discoverSymOrd`/`discoverSymNum` delegate to it
- [x] (2026-07-28T13:06:23Z) M2: translate `TFieldProj` through a structured memo key containing the base path and projection-tag/owner/result `TypeRep`s; keep all caller strings diagnostic-only and add the concrete-projection constraint helper
- [x] (2026-07-28T13:06:23Z) M2: z3-backed tests — same projection shares, distinct projections do not, adversarial string segments cannot collide, and concrete/symbolic agreement holds in the required direction
- [x] (2026-07-28T13:06:23Z) M3: unconditional `ProjectionResultUnsupported`, `ProjectionOrderingUnsupported`, and `ProjectionOutsideGuard` validation warnings
- [x] (2026-07-28T13:06:23Z) M3: hidden-input / `PInCtor` discipline tests; forward-vs-replay equality test over a projection-guarded transducer
- [x] (2026-07-28T13:13:36Z) M4: Haddocks with the projection-instance laws and provenance division; exported law harness (`fieldWitnessAgrees`) plus negative test proving a wrong instance fails
- [x] (2026-07-28T13:13:36Z) M4: documentation and ADR pass — projection design note plus updates to ADR-0003 and ADR-0004 (IR already points here; status advances to `released` in M5)
- [ ] M5: changelog entry, version bump to 0.4.0.0, Hackage/upstream-tag re-check, release and tag per `docs/research/release-procedure.md`
- [ ] Final: ADR distillation pass and Outcomes & Retrospective
- [x] (2026-07-28) Planning audit: checked the proposal against all five `Term`-handling modules, relevant ADRs, the IR, Mori-located SBV source, Hackage, and upstream tags; revised the unsound or unimplementable parts below


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- Observation: `symSatExt` cannot be the projection agreement harness proposed by the first
  draft. Its `ExtractRegFile rs` and `KnownInCtors ci` constraints require `Sym` for every
  register and input field, whereas this feature deliberately projects from an `owner` that
  needs no `Sym` instance. Even when an owner happens to have `Sym`, a free projection result
  cannot be inverted into an owner value.
  Evidence: `src/Keiki/Symbolic.hs:815-915` reconstructs only `reg/<slot>` and
  `inp/<ctor>/<field>` model variables through `Sym`; it has no inverse for a getter.
- Observation: the original validator instruction would create a module cycle. `Core` owns
  `validateTransducer`, while `Keiki.Symbolic` imports and re-exports `Core`; therefore `Core`
  cannot import `discoverSym` from `Keiki.Symbolic`.
  Evidence: the imports and module headers in `src/Keiki/Core.hs` and
  `src/Keiki/Symbolic.hs` show that direction directly.
- Observation: composition is not a simple index-realignment case. `substTerm` replaces a
  downstream `TInpCtorField` with the upstream term that produced that field, and
  `applyEnvTerm` replaces a register read with a pending write. Projecting after either
  substitution may have a computed base with no stable symbolic path.
  Evidence: `src/Keiki/Composition.hs:486-533` and `src/Keiki/Composition.hs:1005-1042`.
- Observation: SBV rejects duplicate calls to `free` with the same textual label; sharing
  must happen in Keiki's cache before allocating the second variable. A delimiter-concatenated
  user-name key is therefore both collision-prone and incapable of safely delegating identity
  to SBV.
  Evidence: Mori located SBV at `/Users/shinzui/Keikaku/hub/haskell/sbv-project/sbv`;
  `Data/SBV/Core/Symbolic.hs`'s `registerLabel` rejects duplicate names and the characters
  `|` and `\\`.
- Observation: the release baseline remains current at audit time. Hackage's authoritative
  `preferred.json` lists `0.3.1.0` first, and `git ls-remote --tags
  https://github.com/shinzui/keiki.git` lists `refs/tags/v0.3.1.0`. Hackage lists SBV 13.6,
  which remains within the existing `>=11.7 && <15` bound. Repeat the Keiki checks at release
  time because this evidence is time-sensitive.
- Observation: Mori's reverse-dependency query lists Keiro and several other project-level
  consumers, and the current Keiro Cabal files consistently bound Keiki below 0.4. Releasing
  this deliberate PVP break will not be selected by those consumers until their own follow-up
  raises the bound.
  Evidence: `mori registry dependents shinzui/keiki --packages` lists `shinzui/keiro` among
  the dependents; Mori located Keiro at `/Users/shinzui/Keikaku/bokuno/keiro`, where
  `keiro/keiro.cabal`, `keiro-core/keiro-core.cabal`, `keiro-dsl/keiro-dsl.cabal`, and
  `jitsurei/jitsurei.cabal` use upper bounds `<0.4`. This plan releases the capability and
  records the break; changing those sibling-package bounds belongs to the Keiro adoption plan.
- Observation: the request traces to an actual Mori-to-Keiro migration, although the current
  migration deliberately remains unblocked by using scalar identity/hash registers. Mori
  MasterPlan 22 makes checked `keiro-dsl` structure and functional Keiki transducers part of
  the target architecture; Mori ExecPlan 171 requested structural mapped values; Keiro IR-1
  and MasterPlan 25 accepted that foundation and split solver-visible projection into this
  Keiki-owned request. Keiro's exclusion of Experiment C is therefore a repository and
  sequencing boundary, not a rejection of the capability.
  Evidence: Mori was located through `mori registry show shinzui/mori --full` at
  `/Users/shinzui/Keikaku/bokuno/mori-project/mori`; read
  `docs/masterplans/22-model-first-class-schema-and-extension-domain-events.md` and
  `docs/plans/171-extend-keiro-dsl-for-structural-mori-domain-contracts.md` there, then
  `docs/improvement-requests/support-structural-consumer-owned-types-in-keiro-dsl.md` and
  `docs/masterplans/25-structural-consumer-type-ergonomics-and-soundness-preserving-adoption-for-keiro-dsl.md`
  in the Mori-resolved Keiro checkout.
- Observation: the complete Keiro research note does not classify scalar field projection as
  research-grade. It places first-class symbolic field projections in the medium-risk tier
  and names the minimal one-`Text`-field implementation as recommended Experiment C.
  Solver-visible bounded collections and recursive mappings are the research-grade items.
  Evidence: `docs/research/14-structural-consumer-type-tradeoffs.md`, "Improvement Directions
  by Risk" and "Recommended Near-Term Experiments". This supports implementing the narrow
  scalar term while preserving the plan's explicit exclusions for collections and chaining.
- Observation: a freely constructible `FieldWitness name owner r` containing a `String`
  identity and getter is not the best Keiki proof API. Two separately constructed witnesses
  can accidentally reuse the same shape/name/type strings with different getters; memoizing
  them as one variable can over-constrain the formula and falsely prove deadness or mutual
  exclusion. A test harness documents the law but cannot enforce cross-value coherence.
  Evidence: this is the same over-sharing failure mode that requires a structured cache key,
  but it occurs before key construction. Keying by a nominal projection tag and obtaining the
  getter through one Haskell class instance makes accidental string collision irrelevant and
  gives normal instance coherence one getter per tag. A deliberately dishonest instance can
  still misdescribe a wire field, but it cannot give two concrete meanings to one tag within a
  normal program; provenance remains a generator-owned law rather than solver identity.
- Observation: GHC 9.12's `GHC2024` language set does not imply `TypeFamilies`, although the
  proposed nominal projection class uses associated types. The isolated class, abstract
  nominal-role witness, instance, and `fieldWitness @Tag` example compile under the repository's
  GHC 9.12.4 when `TypeFamilies` is enabled.
  Evidence: a temporary no-code compile through `cabal exec -- ghc -fno-code` first failed with
  GHC-39191/GHC-06206 without `TypeFamilies`, then passed with it; the temporary source was
  removed. Milestone 1 therefore adds the pragma explicitly and requires generators to emit it
  in instance-owning modules.
- Observation: the abstract witness already proves that callers passed through
  `fieldWitness`, so `constrainFieldProjection` does not need to repeat
  `FieldProjection` or `KnownSymbol (FieldName projection)` constraints. GHC 9.12 reports
  both as redundant because the constraint helper uses only the witness, the structural base,
  the projection/owner `TypeRep`s, and the result's `Sym` dictionary.
  Evidence: `cabal build` emitted `-Wredundant-constraints` for the first implementation;
  removing only those two constraints restored a warning-free build without changing the
  helper body or public behavior.
- Observation: the structured projection key prevents SBV label failures as well as cache
  aliasing. A test projection whose slot, field, and shape diagnostics contain `/`, `|`, and
  `\\` proves successfully because only Keiki's generated `proj/<ordinal>` label reaches SBV.
  Evidence: the `FieldProjSpec` adversarial-label example passes alongside SBV's documented
  `registerLabel` rejection of `|`, `\\`, and duplicate labels.


## Decision Log

Record every decision made while working on the plan.

- Decision: Restrict projection bases at the type level with a dedicated `ProjBase` GADT
  (register slot or input-constructor field only) instead of letting `TFieldProj` wrap an
  arbitrary `Term`.
  Rationale: Memoizing a projection as one shared solver variable is only sound when the
  base has a stable identity. A projection over a computed base (`TApp1`, `TArith`) has no
  stable path, and IR clause 6 allows rejecting multi-hop projection outright. Making the
  restriction structural means there is nothing to reject at run time and no diagnostic to
  maintain; chaining can be staged later by extending `ProjBase`. This is the same move
  ADR-0001 made for schema agreement: prefer un-representable over runtime-checked.
  Date: 2026-07-28
- Decision: Replace the cache's raw `String` key with a structured `SymVarKey`. A projection
  key contains a structured register-or-input base including its index position,
  `SomeTypeRep projection`, `SomeTypeRep owner`, and `SomeTypeRep result`. Existing
  register/input keys remain distinct
  constructors. Projection SBV labels are fresh internal ordinals (`proj/0`, `proj/1`, ...),
  while the structured map — not delimiter parsing — decides sharing.
  Rationale: Accidental over-sharing is unsound because it can falsely prove mutual exclusion
  or deadness. Delimiter concatenation is not injective for arbitrary constructor/slot/shape/
  field strings, and names alone do not distinguish manually constructed duplicate-labelled
  indices. A nominal projection tag gives each projection an ordinary Haskell type identity;
  shape and field strings become diagnostics only and cannot make variables alias. Keeping
  owner/result `TypeRep`s is defensive and makes malformed associated-type changes fail rather
  than silently sharing; this matters because `Int` and `Integer` use the same SBV
  representation. These `TypeRep`s are used only inside one `SymEnv`; they are neither
  persisted nor exposed as a cross-version identity, so module-renaming stability is not
  required. Structured identity makes malformed declarations under-share or fail validation
  instead of over-sharing.
  Date: 2026-07-28
- Decision: Represent a projection with a nominal tag class and abstract witness, not a public
  record containing an identity string and getter. `FieldProjection projection` has associated
  types `FieldName projection`, `FieldOwner projection`, and `FieldResult projection`, plus
  `fieldShapeId` and `projectFieldValue`. A tag has one normal coherent instance;
  `fieldWitness` constructs the otherwise-abstract, nominal-role `FieldWitness projection`.
  The symbolic key uses `TypeRep projection`.
  Rationale: Keiki proof soundness should not depend on callers manually coordinating runtime
  strings and extensionally equal functions across multiple witness values. Nominal tag
  identity prevents accidental key collision, the nominal role prevents `coerce` from changing
  the tag, associated types make owner/result/name part of the API contract, and instance
  coherence supplies one getter per projection. A generated or
  hand-written instance still carries totality and schema-provenance laws, as any semantic
  adapter must, but violating provenance changes what field is named rather than causing two
  getters to be unsoundly merged. Defining the tag beside its instance also avoids orphan
  instances in generated binding modules.
  Date: 2026-07-28
- Decision: Treat projection variables as a sound over-approximation, and test the required
  simulation direction explicitly. For every concrete `(regs, ci)`, bind each projection key
  to `projectFieldValue` of its concrete base and prove that the translated predicate equals
  `evalPred`.
  Do not claim that an arbitrary symbolic projection model can be inverted into an owner or
  returned by `symSatExt`.
  Rationale: Different fields are intentionally independent unless their full keys match, so
  the symbolic domain may contain combinations no concrete owner realizes. This loses proofs
  but is conservative: every concrete execution still induces a symbolic valuation. Therefore
  symbolic unsatisfiability implies concrete unsatisfiability. The reverse/model-extraction
  direction is neither needed for the proof gates nor implementable without an owner
  constructor/inverse.
  Date: 2026-07-28
- Decision: The inversion and replay machinery treats `TFieldProj` as a *derived,
  non-invertible* term — exactly the existing `TApp1` treatment: `gatherInpEntries`/`stepOne`
  contribute no recovered entries, `recomputeOne` recomputes it forward, and the
  hidden-input analysis counts it as a read of the whole underlying slot/field.
  Rationale: The `Term` GADT cannot ban `TFieldProj` from `OutFields` or `Update`
  right-hand sides (a constructor is usable anywhere `Term` is accepted), so "guards only"
  cannot be a type-level fact. Falling through the inversion pattern matches would break
  replay soundness (ADR-0002); classifying the constructor as derived keeps every walker
  total and replay semantics unchanged. The default validator reports the placement error
  as `ProjectionOutsideGuard` for every use in an update or output rather than making raw
  evaluation or recovery partial. This preserves the request's guards-only contract even
  though the reusable `Term` GADT cannot enforce that placement by kind.
  Date: 2026-07-28
- Decision: Unsupported symbolic capability is an unconditional `validateTransducer` warning,
  not an opt-in opacity warning. `ProjectionResultUnsupported` covers a result outside the
  equality registry; `ProjectionOrderingUnsupported` covers a projection-bearing `PCmp` whose
  operand type is outside the ordering registry. Keiro and release validation treat either as
  rejection.
  Rationale: IR clause 2 demands "a construction- or validation-time rejection, never a
  silent fallback to opacity." The existing `PEq`/`PCmp` translation falls back to a fresh
  `SBool` on a `discoverSym` miss; without this check a projection at an unsupported type
  would silently degrade to exactly the opacity the term exists to avoid, while *not*
  triggering `OpaqueGuard` (since `TFieldProj` is not opaque) — the worst combination.
  A new `src/Keiki/Internal/SymbolicTypes.hs` GADT is the single cycle-free list of curated
  types; `Core` queries it for validation and `Keiki.Symbolic` delegates all three
  `discoverSym*` functions to it. Checking only `discoverSym` misses `PCmp Bool`/`PCmp Text`,
  which still falls back to opaque `cmp`. Duplicating the registry in `Core` risks drift,
  while importing `Keiki.Symbolic` creates a cycle. A dictionary-free type classifier below
  both modules keeps one authoritative list without pulling SBV into `Core`.
  Date: 2026-07-28
- Decision: Composition preserves `TFieldProj` only when the substituted owner is still a
  stable `TReg`/`TInpCtorField` base, and constant-folds a `TLit` owner. Raw `compose` lowers
  every other substituted owner to `TApp1 (fieldWitnessGet w) ownerTerm`, preserving forward
  semantics but deliberately becoming opaque. `composeChecked` rejects any path that would
  require that lowering, including pending-write substitution in a multi-event path.
  Rationale: Pretending that an arbitrary computed owner has a path would over-share and be
  unsound. Rejecting all composition would discard safe pass-through cases. The
  preserve/fold/lower split maintains the raw combinator's sequential semantics while keeping
  ADR-0004's checked boundary honest about lost symbolic structure.
  Date: 2026-07-28
- Decision: The fast pure overlap validator (the structural fragment described in ADR-0003)
  treats `TFieldProj` as an unsupported shape and stays silent; only the z3-backed gate
  reasons about projections.
  Rationale: ADR-0003 already defines this posture: the pure validator proves overlaps only
  inside its documented fragment and must have no false positives there. Extending the
  fragment is optional future work, not an acceptance requirement.
  Date: 2026-07-28
- Decision: Bump the package version to 0.4.0.0.
  Rationale: `Term` is exported with all constructors; adding `TFieldProj` breaks
  downstream exhaustive pattern matches, which under the PVP is a major bump from 0.3.1.0.
  Date: 2026-07-28
- Decision: Spellings — class `FieldProjection` with associated types `FieldName`,
  `FieldOwner`, and `FieldResult`; methods `fieldShapeId` and `projectFieldValue`; abstract
  witness `FieldWitness` built by `fieldWitness`; constructor `TFieldProj`; base GADT
  `ProjBase` with `PBReg`/`PBInp`; smart constructors `regProj` and `inpProj`; diagnostic
  helper `fieldProjectionPath`; internal getter eliminator `fieldWitnessGet`; one-way symbolic
  binding helper `constrainFieldProjection`; and law harness `fieldWitnessAgrees`.
  Rationale: The IR leaves spelling to Keiki. These names follow existing class/associated-
  type and `T*`-constructor/lowercase-smart-constructor conventions while making the witness
  constructor and symbolic identity impossible to fabricate from strings.
  Date: 2026-07-28
- Decision: Proceed with the implementation as a good addition to Keiki; do not require a
  second demand-validation gate before Milestone 1. Keep scalar promotion documented as the
  preferred model for identity, revision, lifecycle, and externally computed content hashes,
  and keep projection limited to single-hop scalar reads in guards.
  Rationale: The feature fills a general hole in Keiki's core promise: a typed structural
  guard should retain the same meaning in concrete evaluation, solver analysis, diagnostics,
  validation, and checked composition. Implementing it in Keiro would duplicate or
  misrepresent Keiki semantics, and lowering it to `TApp1` loses the proof value. The
  instance-provenance trust boundary and PVP
  cost are real, but nominal tag identity, the abstract witness, narrow base/result/placement
  restrictions, conservative symbolic over-approximation, and explicit composition rejection
  contain them.
  The present Mori plans' use of promoted scalar registers proves a safe fallback exists; it
  does not make the library primitive speculative.
  The research note independently classifies this exact primitive as medium-risk checked
  machinery and recommends its minimal experiment.
  Date: 2026-07-28
- Decision: Treat Mori and Keiro as motivating consumers and compatibility probes, not as the
  authority for Keiki's public API. The Core API contains no Keiro schema-graph, codec, wire,
  or Mori domain type. Projection identity is a nominal Haskell tag; any generator or direct
  Keiki author can define an instance.
  Rationale: A concrete downstream problem is useful evidence that an abstraction matters,
  but consumer-specific design can be wrong or temporary. Keiki's API must instead follow its
  own invariants: stable typed term identity, conservative proofs, total AST handling, replay
  preservation, and explicit checked-composition loss. The nominal `FieldProjection` design
  satisfies those independently; Keiro's graph is only one source of lawful instances.
  Date: 2026-07-28
- Decision: Keep `constrainFieldProjection`'s exported constraints minimal: `Typeable` for the
  nominal tag and owner plus `Sym` for the result. Do not retain redundant
  `FieldProjection`/`KnownSymbol` constraints merely to mirror `fieldWitness`'s constructor
  signature.
  Rationale: external code cannot fabricate `FieldWitness`, so instance provenance is already
  established at witness construction. The helper binds a result variable and never calls the
  getter or renders a field name; adding unused constraints creates warnings and falsely
  suggests those dictionaries participate in symbolic identity.
  Date: 2026-07-28


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

(To be filled during and after implementation.)

Planning outcome (2026-07-28): the soundness audit completed and implementation has not
started. The revised plan now states the concrete-to-symbolic simulation argument, removes
the infeasible `symSatExt` claim, closes cache-key collision cases, gives the validator a
cycle-free registry source, and makes composition behavior explicit. The architectural-value
review traced the request from Mori MasterPlan 22 / ExecPlan 171 through Keiro IR-1 and
MasterPlan 25, then re-evaluated the abstraction against Keiki's own API and proof invariants.
The resulting GO does not depend on Mori's domain design: the nominal tag/instance API is
consumer-neutral and removes string identity from the trusted proof boundary. Scalar promotion
remains the sound default for explicit decision state, but it is not a substitute for every
solver-visible field read.

Milestones 1–3 outcome (2026-07-28): the public term/witness API, all total walkers,
structured symbolic cache, cycle-free type registry, validation warnings, and exact
composition-boundary diagnostics are implemented. The Keiki suite passes 559 examples. New
tests prove register/input evaluation, dotted paths, opacity discrimination, profunctor and
Strong rewrites, stable/literal/computed composition behavior, multi-event pending-write
rejection, z3 sharing/non-sharing (including adversarial labels and `Int`/`Integer`), both
directions of the generated concrete comparisons, guards-only validation, hidden-input and
`PInCtor` discipline, and forward/replay state equality.

Milestone 4 outcome (2026-07-28): public Haddocks now state totality, nominal identity,
instance coherence, schema-provenance ownership, duplicate-tag precision loss, and the
one-way symbolic simulation. The exported `fieldWitnessAgrees` harness has passing and
mutation-style expected-failure properties. The new field-projection design note records the
structured cache key, `symSatExt` limitation, validation placement, replay treatment, and
composition policy; ADR-0003 and ADR-0004 retain the corresponding conservative-proof and
checked-boundary decisions. `cabal haddock` completes and `cabal test all` remains green with
559 Keiki examples plus the workspace's codec and Jitsurei suites.


## Context and Orientation

Everything below is verifiable in the working tree; file paths are repository-relative.
The reader is assumed to know Haskell (GADTs, type-level lists, `Typeable`) but nothing
about this repository.

**Cross-repository provenance.** Mori MasterPlan 22
(`mori://shinzui/mori/plans/171-extend-keiro-dsl-for-structural-mori-domain-contracts` is its
first child plan) needs `keiro-dsl` to carry existing Mori domain records through functional
Keiki transducers. Its request became Keiro IR-1 and Keiro MasterPlan 25. That master plan
owns structural/opaque mapped types and generated codecs, but explicitly excludes its
Experiment C and points to this Keiki IR: the symbolic term must exist below the DSL before
the DSL can truthfully advertise nested guard syntax. Current Mori plans use scalar
identity/hash registers plus whole payloads, so this plan adds a later ergonomic and
expressiveness tier without blocking or weakening the safe migration design.

**What keiki is.** A single Haskell package (`keiki.cabal`, currently version 0.3.1.0,
git-tagged `v0.3.1.0`) providing a pure event-sourcing/workflow-transducer core. The two
files this plan mostly touches are `src/Keiki/Core.hs` (~2,100 lines: the term/predicate
ASTs, evaluators, replay/inversion machinery, and `validateTransducer`) and
`src/Keiki/Symbolic.hs` (the SBV/z3 translation layer). Rendering lives under
`src/Keiki/Render/` (`Pretty.hs` renders terms and predicates as domain-readable text).
Tests are hspec suites under `test/Keiki/`, listed *manually* both in `test/Spec.hs` and in
the `other-modules` stanza of the `keiki-test` suite in `keiki.cabal` (there is no
hspec-discover). QuickCheck `^>=2.15` is already a test dependency.

**The Term AST.** `Term rs ci ifs r` (around `src/Keiki/Core.hs:323`) is a pure expression
over a register file (`rs :: [Slot]`, a type-level list of name/type pairs) and the input
symbol `ci`, producing `r`. Its constructors: `TLit` (constant), `TReg (Index rs r)` (read a
register slot), `TInpCtorField (InCtor ci ifs) (Index ifs r)` (read field of the matched
input constructor; pins the `ifs` schema parameter — see ADR-0001), and three
function-application forms: opaque `TApp1`/`TApp2` (arbitrary Haskell functions) and
structural `TArith` (numeric ops the solver sees through). `Index` values are written with
`OverloadedLabels` (`#doc`), and `indexName` (in `Symbolic.hs`) recovers the slot's name
string. `InCtor ci ifs` carries `icName :: String` plus the `icMatch`/`icBuild` round trip.
Guards are `HsPred rs ci` values (`PEq`/`PCmp` existentially hide their operands' `ifs` and
carry `Typeable` evidence for the operand type; `PInCtor ic` pins which input constructor
the edge accepts).

**Evaluation.** `evalTerm :: Term rs ci ifs r -> RegFile rs -> ci -> r`
(`src/Keiki/Core.hs:853`): `TReg ix` is `regs ! ix`; `TInpCtorField ic ix` matches the
constructor via `icMatch` and errors on a mismatch (the `PInCtor` guard discipline makes
that unreachable on validated transducers).

**Symbolic translation.** `translateTermSym` (`src/Keiki/Symbolic.hs`, ~line 426) maps a
term to an SBV expression, requiring `Sym r` — a *curated closed registry* (`Bool`, `Int`,
`Integer`, `Text`, `UTCTime`, `Word8/16/32/64`, `Int32/64`) discovered at run time from
`Typeable` evidence by `discoverSym`. `TReg`/`TInpCtorField` allocate deterministic
variables named `reg/<slot>` and `inp/<ctor>/<slot>` through `memoFree`, a per-translation
memo cache in `SymEnv` (`seVarCache`, currently an `IORef (Map String SomeSBV)`, from EP-42
of MasterPlan 12): the first read of a key allocates `SBV.free`, later reads return the
cached variable, so repeated reads of one slot are *one* solver variable and `x /= x` is
provably unsat. SBV itself rejects duplicate textual variable labels, so the cache must
decide identity before allocation. `TApp1`/`TApp2` translate to per-occurrence fresh
variables (sound but opaque). `translatePred` dispatches `PEq`/`PCmp` through
`discoverSym`/`discoverSymOrd` and falls back to a fresh `SBool` on a miss. `symIsBot` asks
z3 whether a predicate is unsatisfiable; per ADR-0003 only a definite `Unsatisfiable`
counts as proof.

Projection variables are an over-approximation, not a symbolic encoding of the whole owner.
Each full projection key gets a free result variable. Different keys have no relationship,
even when their getters read fields of the same record, so the solver may admit impossible
field combinations; this is conservative for emptiness proofs. Soundness requires the other
direction: every concrete owner must induce an assignment that binds each projection key to
its getter result. Milestone 2 adds and tests exactly that binding operation.

**Witness extraction limitation.** `symSatExt` rebuilds registers and input constructors only
through `ExtractRegFile`/`KnownInCtors`, which require `Sym` on each stored field. It therefore
cannot generally be called when a slot contains the consumer-owned type this feature exists
to keep outside the registry. Even if an owner has `Sym`, a projected result does not provide
an inverse that can rebuild it. Projection variables stay out of model extraction; this plan
does not promise a concrete witness from a projection-only satisfiable model.

**Opacity audit.** `predHasOpaqueTerm` / `termHasOpaqueApp` (`src/Keiki/Core.hs:2030`)
report whether a guard contains `TApp1`/`TApp2` anywhere. `validateTransducer` runs
`opaqueGuardWarnings` only when `warnOpaqueGuards` is set (off in
`defaultValidationOptions`); Keiro's boundary turns the warning into a failure.

**Replay/inversion machinery.** Output events are built from `OutFields` of terms;
`solveOutput` recovers the input command from an observed event by walking those terms.
*Invertible* fields (`TLit`/`TReg`/`TInpCtorField`) contribute recovered values;
*derived* fields (`TApp1`/`TApp2`/`TArith`) are skipped during recovery (`gatherInpEntries`
and its helper `stepOne` return no entries for them) and recomputed forward by
`recomputeOne`. The hidden-input analysis (`hiddenInputReasons`, surfaced as
`HeadUnrecoverable`/`HirHeadUnrecoverable` warnings) reports input fields that are read
only inside derived fields. `termInCtorNames`/`predInCtorReadNames` collect which input
constructors a term/guard reads, powering the guard-implies-input-read check;
`updateReadsInput`/`edgeReadsInput` ask whether an edge's update reads the input at all.

**Whole-AST transformers.** Adding a `Term` constructor affects more than the Core walkers.
`src/Keiki/Profunctor.hs` rehomes input constructors in `firstOutFields`, `contraTerm`, and
`contraMaybeTerm`. `src/Keiki/Composition.hs` weakens register indices, lifts either arms,
substitutes downstream input reads through upstream outputs, applies pending writes during
multi-event composition, and scans expected boundary reads. The last two operations may
replace a stable base with a computed term; they are the reason composition needs an explicit
preserve/fold/lower policy rather than an `unsafeCoerceTerm` case (that function is only a
raw coercion, not a structural walker).

**Relevant ADRs** (in `docs/adr/`; scanned all five, four matter here):

- `docs/adr/0001-structural-re-indexing-for-sound-replay.md` — why `Term` carries the `ifs`
  schema parameter and why the project prefers making invalid states un-representable over
  runtime checks. The new `ProjBase` follows the same pinning rules: the register variant
  leaves `ifs` free (like `TReg`), the input variant pins it (like `TInpCtorField`).
- `docs/adr/0002-event-logs-must-reproduce-forward-state.md` — replay must reproduce
  forward state; this is why `TFieldProj` must slot into the derived-field classification
  rather than being ignored by the inversion walkers.
- `docs/adr/0003-proof-gates-fail-conservatively.md` — solver uncertainty is never proof;
  under-constraining (fresh variables) is conservative, over-constraining (accidental
  variable sharing) is not. This drives the memo-key design and the unsupported-type
  rejection.
- `docs/adr/0004-composition-uses-snapshot-updates-and-checked-boundaries.md` — raw
  `compose` preserves sequential forward behavior, while durable callers use
  `composeChecked` so mapped or structurally lossy boundaries fail explicitly. Projection
  substitution extends this boundary: stable pass-through bases remain structural, computed
  bases lower to opaque terms only in raw composition, and the checked entry point rejects
  that loss.

ADR-0005 (wire identities) is not affected because this plan adds no persisted wire format.
The compiler's incomplete-pattern warnings are useful but not the whole audit: wildcard
classifiers such as `pureVariable`, `visitedSlotsOf`, and `detectMissingInCtorFields` remain
intentionally silent for a derived projection, so their behavior must be asserted in tests
rather than discovered through `-Wincomplete-patterns`.

**The improvement request's boundaries.** Guards only: projections in `OutFields` or
register writes are reported by the default validator as `ProjectionOutsideGuard` (the
evaluator and replay walkers remain total defensively). Mapped values otherwise move as
whole-value copies. No collection semantics, no new `Sym` registry types, and no
`keiro-dsl` surface work. Keiro generates nominal tags, instances, and witnesses from its
structural binding graph and proves their provenance with mutation tests; Keiki defines the
laws and ships the harness — Haddocks must state this division.

**Keiro proposal-test fit.** The ten-question proposal test in Keiro research note 14 is
discharged as follows:

1. Authority: Keiro's resolved structural binding graph owns the declared field identity and
   generates a nominal tag instance; Keiki owns only the term semantics and never claims
   wire-schema authority. `FieldWitness` is abstract. Hand-written `FieldProjection`
   instances are a documented provenance/totality trust boundary, while their nominal tag—
   not a string supplied by the instance—is solver identity.
2. Replay: projections are guard-only under default validation. They do not write state or
   construct events, and the end-to-end forward/replay test proves unchanged reconstruction.
3. Visibility: `TFieldProj` is a first-class term handled by concrete evaluation, symbolic
   translation, validation, rendering, and opacity audit.
4. Compatibility direction: no persisted bytes or schema-evolution classification changes in
   Keiki. Keiro continues to classify the containing structural field at each use site.
5. Ownership: the term projects private consumer-owned values only; it neither generates nor
   reuses public DTOs.
6. Completeness: the audited walker list, compiler exhaustiveness checks, explicit wildcard-
   classifier tests, and the shared symbolic-type registry make omissions fail build/tests.
7. Migration: Keiki has no wire migration. Keiro must generate each nominal tag and instance
   from the same graph whose codec is proven against existing goldens before exposing DSL
   syntax.
8. Recovery: M1-M4 are additive and green at every commit; M5 follows the release procedure
   and fixes forward after any published partial release.
9. Performance: concrete execution adds exactly the selected total getter when a projection
   guard is evaluated; symbolic execution is build-time and allocates one memo entry/free
   variable per distinct path. No codec traversal or runtime effect is added. Record any
   material regression found by the existing end-to-end suite before release; do not cache
   owner values or introduce a second schema authority as an optimization.
10. Negative proof: distinct tags with identical diagnostic strings, adversarial memo-key
    tests, unsupported-placement/type tests, composition-boundary rejection, and the wrong-
    instance `expectFailure` property prove that incomplete identity, validation, or provenance
    machinery loses a required guarantee.


## Plan of Work

The work is five milestones, each independently verifiable, each leaving `cabal test all`
green. Run all commands from the repository root. GHC 9.12 is the toolchain (see
`docs/research/release-procedure.md` for the `GHCUP_GHC_VERSION` invocation if your default
`ghc` differs).

### Milestone 1 — the term, its evaluator, and total-walker coverage

Scope: `src/Keiki/Core.hs` gains the witness and term; every total walker learns the new
constructor; rendering produces dotted paths; opacity classification is correct. At the end
the library compiles warning-free and unit tests cover evaluation, rendering, and opacity.

Add `{-# LANGUAGE TypeFamilies #-}` to `src/Keiki/Core.hs`; GHC 9.12's `GHC2024` set does
not imply that extension. Modules defining `FieldProjection` instances likewise need
`TypeFamilies` (Keiro's generator must emit it). The exact class/witness sketch below was
compiled in isolation with the repository's GHC 9.12.4 toolchain and these existing language
settings before this plan was finalized.

Add to `src/Keiki/Core.hs`, near `InCtor` (the "structural projection" neighborhood):

```haskell
-- | One nominal, solver-visible field projection. Define a fresh tag type and
-- one instance per logical projection. The tag's 'TypeRep', not any caller
-- string, is its symbolic identity.
--
-- Laws (see Milestone 4): 'projectFieldValue' is total for every well-formed
-- owner. Its field name and shape label truthfully describe that getter.
class FieldProjection projection where
  type FieldName projection :: Symbol
  type FieldOwner projection :: Type
  type FieldResult projection :: Type
  fieldShapeId :: Proxy projection -> String
  projectFieldValue ::
    Proxy projection -> FieldOwner projection -> FieldResult projection

-- | Abstract nominal token for a 'FieldProjection' instance. The constructor is private;
-- use 'fieldWitness'.
type role FieldWitness nominal
data FieldWitness projection = FieldWitness

fieldWitness ::
  ( FieldProjection projection,
    KnownSymbol (FieldName projection),
    Typeable projection,
    Typeable (FieldOwner projection),
    Typeable (FieldResult projection)
  ) =>
  FieldWitness projection
fieldWitness = FieldWitness

-- Exported only in Core's documented internals group so sibling modules can
-- eliminate the abstract witness without seeing its constructor.
fieldWitnessGet ::
  forall projection.
  (FieldProjection projection) =>
  FieldWitness projection ->
  FieldOwner projection ->
  FieldResult projection
fieldWitnessGet _ = projectFieldValue (Proxy @projection)

-- | Where a field projection may read from: a register slot or a field of the
-- matched input constructor. Restricting the base structurally (rather than
-- wrapping an arbitrary 'Term') is what makes path-keyed symbolic memoization
-- sound; see the Decision Log of docs/plans/79-….md and ADR-0001's precedent.
data ProjBase (rs :: [Slot]) (ci :: Type) (ifs :: [Slot]) owner where
  PBReg :: Index rs owner -> ProjBase rs ci ifs owner
  PBInp :: InCtor ci ifs -> Index ifs owner -> ProjBase rs ci ifs owner
```

and the `Term` constructor (after `TArith`):

```haskell
  TFieldProj ::
    ( FieldProjection projection,
      KnownSymbol (FieldName projection),
      Typeable projection,
      Typeable (FieldOwner projection),
      Typeable (FieldResult projection)
    ) =>
    FieldWitness projection ->
    ProjBase rs ci ifs (FieldOwner projection) ->
    Term rs ci ifs (FieldResult projection)
```

with smart constructors mirroring `inpCtor`/`tadd`:

```haskell
regProj ::
  ( FieldProjection projection,
    KnownSymbol (FieldName projection),
    Typeable projection,
    Typeable (FieldOwner projection),
    Typeable (FieldResult projection)
  ) =>
  FieldWitness projection ->
  Index rs (FieldOwner projection) ->
  Term rs ci ifs (FieldResult projection)
regProj w ix = TFieldProj w (PBReg ix)

inpProj ::
  ( FieldProjection projection,
    KnownSymbol (FieldName projection),
    Typeable projection,
    Typeable (FieldOwner projection),
    Typeable (FieldResult projection)
  ) =>
  FieldWitness projection ->
  InCtor ci ifs ->
  Index ifs (FieldOwner projection) ->
  Term rs ci ifs (FieldResult projection)
inpProj w ic ix = TFieldProj w (PBInp ic ix)
```

Then let the compiler drive the total-pattern work and use this audited list to cover the
wildcard classifiers. The required semantics are:

- `evalTerm` — mirror the base read, then apply the getter:
  `PBReg ix` is `fieldWitnessGet w (regs ! ix)`; `PBInp ic ix` matches `icMatch ic ci`
  and applies `fieldWitnessGet w (rf ! ix)` on `Just`, erroring like
  `TInpCtorField` on `Nothing` (same guard discipline, same message shape naming `icName`).
- `termHasOpaqueApp` — `False` for `TFieldProj` (this is the whole point; the two-direction
  test in this milestone proves `TApp1` still returns `True`).
- `termInCtorNames` — `[]` for `PBReg`, `[icName ic]` for `PBInp`, so the
  guard-implies-input-read discipline sees the projected read.
- `updateReadsInput`'s term walker (and anything else `edgeReadsInput` relies on) — a
  `PBInp` base reads the input.
- `outFieldsHaveInpCtorField`'s nested walker — a `PBInp` base counts as an input read. Keep
  `visitedSlotsOf` and `detectMissingInCtorFields` from counting it as a recovered top-level
  field: projection output is derived, so the underlying owner slot remains hidden.
- `gatherInpEntries`/`stepOne` — `Just []` (derived field: contributes no recovered
  entries), matching the `TApp1` clause.
- `recomputeOne` — recompute forward via `evalTerm`, matching the `TApp1` clause.
- `src/Keiki/Render/Pretty.hs` `prettyTerm` — dotted path: `PBReg ix` renders
  `indexName ix <> "." <> fieldName`, `PBInp ic ix` renders
  `icName ic <> "." <> indexName ix <> "." <> fieldName`, where `fieldName` is
  `symbolVal` of `FieldName projection`. Move or share only the pure base-path helper needed
  by Core diagnostics; `Pretty.hs` already owns and exports its slot `indexName` helper.

Extend every structural transformer in `src/Keiki/Profunctor.hs`: `firstOutFields` shifts a
`PBInp` index and replaces its `InCtor` exactly as it does for `TInpCtorField`; `contraTerm`
and `contraMaybeTerm` contramap the `PBInp` constructor; `PBReg` is unchanged.

Extend all seven `Term` walkers in `src/Keiki/Composition.hs`: `weakenLTerm`, `weakenRTerm`,
`termHasCtorMismatch`, `substTerm`, `liftLTermAlt`, `liftRTermAlt`, `applyEnvTerm`, and the
boundary scanner `termExpectedReads` (seven transformers plus the scanner). The simple
weaken/lift/contramap cases preserve the witness and transform `PBReg`/`PBInp` exactly as
their direct-read counterparts. The substitution cases use one shared helper over an owner
term:

```haskell
projectThroughTerm ::
  ( FieldProjection projection,
    KnownSymbol (FieldName projection),
    Typeable projection,
    Typeable (FieldOwner projection),
    Typeable (FieldResult projection)
  ) =>
  FieldWitness projection ->
  Term rs ci ifs (FieldOwner projection) ->
  Term rs ci ifs (FieldResult projection)
projectThroughTerm w (TReg ix) = TFieldProj w (PBReg ix)
projectThroughTerm w (TInpCtorField ic ix) = TFieldProj w (PBInp ic ix)
projectThroughTerm w (TLit owner) = TLit (fieldWitnessGet w owner)
projectThroughTerm w ownerTerm = TApp1 (fieldWitnessGet w) ownerTerm
```

`substTerm` applies this helper to the upstream owner-producing field after the existing
positional alignment/coercion for a `PBInp`; a `PBReg` is simply weakened into the appended
register file. `applyEnvTerm` leaves `PBInp` alone and applies the helper when a projected
`PBReg` has a pending write; with no pending write it keeps the original projection. In
pseudocode, the nontrivial cases are:

```haskell
substTerm (TFieldProj w (PBReg ix)) _ =
  TFieldProj w (PBReg (weakenR @rs1 ix))
substTerm (TFieldProj w (PBInp _ic ix)) upstream =
  projectThroughTerm w (alignedUpstreamField ix upstream)

applyEnvTerm env original@(TFieldProj w (PBReg ix)) =
  maybe original (projectThroughTerm w) (lookupPending ix env)
applyEnvTerm _ (TFieldProj w (PBInp ic ix)) = TFieldProj w (PBInp ic ix)
```

`alignedUpstreamField` denotes the existing `nthTerm` plus documented alignment coercion;
implement it by factoring the current `TInpCtorField` branch rather than adding a second
unchecked lookup. Have the shared projection helper also return a small internal status
(`ProjectionPreserved`, `ProjectionFolded`, or `ProjectionLowered path reason`) alongside
the term. The existing raw substitution wrappers discard that status; the checked path
collects every `ProjectionLowered`. Thread the collection through the same paired-edge and
`PartialPath` expansion that already owns the actual upstream `OutFields` and pending-write
environment, rather than writing a second approximate AST scan. A
`NonStructuralProjectionBoundary` warning carries the originating t1/t2 `EdgeRef`s when
available, the dotted projection path, `fieldShapeId`, and whether the unstable base came from
an upstream computed output or a pending write. The `projectThroughTerm` fallback is forward-correct but
opaque. Extend `checkComposeAlignment`/`composeChecked` with this
`NonStructuralProjectionBoundary` warning whenever path expansion shows that a downstream
guard projection would take the fallback, including a computed pending write in a
multi-event path. Raw `compose` still lowers and remains forward-equivalent; checked
composition refuses to claim a structurally analyzable boundary. `termHasCtorMismatch` and
`termExpectedReads` treat `PBInp` like the corresponding direct input-field read.

Export `FieldProjection(..)`, the abstract `FieldWitness`, `fieldWitness`, `ProjBase(..)`,
`regProj`, `inpProj`,
`fieldProjectionPath`, and `fieldWitnessAgrees` (the small law helper may be added now and
documented fully in Milestone 4) from `Keiki.Core`. Keep `fieldWitnessGet` in the explicit
testing/internals group for Core sibling modules, along with `indexPosition` for cross-module
reuse. `TFieldProj` is already exposed through `Term(..)`. There is no umbrella `Keiki` module
in this package, so no additional re-export is required. Add
`FieldProjection`/`FieldWitness`/`ProjBase` to explicit import lists such as
`src/Keiki/Render/Pretty.hs` where necessary.

Tests (new file `test/Keiki/FieldProjSpec.hs`, registered in `test/Spec.hs` and in
`keiki.cabal` `other-modules`): define a tiny consumer-owned record
(`data DocInfo = DocInfo { diHash :: Text, diTitle :: Text }`), nominal tags
`DocContentHash`/`DocTitle`, their `FieldProjection` instances, and witnesses
`docHashW = fieldWitness @DocContentHash` / `docTitleW = fieldWitness @DocTitle`;
this is a minimal in-package test stand-in, not a claim that Mori's current `DocInfo` has a
`contentHash` field (the current Mori migration computes that hash separately);
assert `evalTerm (regProj docHashW #doc) regs ci` and the matching `inpProj` return the hash;
assert `prettyTerm` renders `doc.contentHash` and `NewDoc.doc.contentHash`; through the
exported `opaqueGuardWarnings`, assert a projection-only guard produces no `OpaqueGuard` and
the equivalent `TApp1 diHash` guard does. Add focused profunctor tests proving
`lmap`/`first'` retain evaluation and the rehomed input path. Add composition tests proving:
a pass-through upstream `TReg` or
`TInpCtorField` keeps a `TFieldProj`; a literal owner folds; a computed owner is forward-
equivalent after raw composition but becomes `TApp1`; and `composeChecked` returns
`NonStructuralProjectionBoundary` for that computed case. Include a multi-event pending-
write case so `applyEnvTerm` is not left to an untested pattern match. Put pretty-print cases
in `test/Keiki/Render/PrettySpec.hs`, contramap/strong cases in
`test/Keiki/ProfunctorSpec.hs` and `test/Keiki/StrongSpec.hs`, and composition cases in
`test/Keiki/CompositionAlignmentSpec.hs` and `test/Keiki/CompositionMultiEventSpec.hs`; keep
the reusable `DocInfo` fixture and core/symbolic properties in the new `FieldProjSpec`.

The fixture demonstrates the consumer-neutral nominal API directly:

```haskell
data DocContentHash

instance FieldProjection DocContentHash where
  type FieldName DocContentHash = "contentHash"
  type FieldOwner DocContentHash = DocInfo
  type FieldResult DocContentHash = Text
  fieldShapeId _ = "test.doc-info.v1"
  projectFieldValue _ = diHash

docHashW :: FieldWitness DocContentHash
docHashW = fieldWitness @DocContentHash
```

Define each tag in the same module as its instance. Generated consumers follow the same rule,
which avoids orphan instances and makes normal Haskell instance coherence part of the API
contract.

Acceptance: `cabal build` warning-free; `cabal test all` green including the new spec.

### Milestone 2 — symbolic translation with path-keyed memoization

Scope: `src/Keiki/Symbolic.hs` translates `TFieldProj` to a memoized solver variable; z3
tests prove sharing and non-sharing are both right; QuickCheck properties prove the
concrete-to-symbolic simulation needed by the proof gates. This milestone first removes the
Core/Symbolic registry cycle so Milestone 3 can validate without duplicating supported types.

Create `src/Keiki/Internal/SymbolicTypes.hs` and list it in the library's `other-modules` in
`keiki.cabal`. Define a closed `SymbolicType r` GADT with one constructor for each currently
supported type and `discoverSymbolicType :: Typeable r => Maybe (SymbolicType r)`. Add pure
classifiers for equality, ordering, and numeric support. Refactor `discoverSym`,
`discoverSymOrd`, and `discoverSymNum` in `src/Keiki/Symbolic.hs` to pattern-match that one
GADT and return their existing SBV dictionaries. Do not change the supported set; the
existing registry tests must continue to pin it.

Replace `SymEnv`'s `Map String SomeSBV` with a structured key:

```haskell
data ProjectionBaseKey
  = ProjectionReg String Int
  | ProjectionInp String String Int
  deriving stock (Eq, Ord, Show)

data SymVarKey
  = RegVar String
  | InpVar String String
  | ProjectionVar
      ProjectionBaseKey
      SomeTypeRep -- nominal projection tag: authoritative identity
      SomeTypeRep -- owner (defensive)
      SomeTypeRep -- result (defensive)
  deriving stock (Eq, Ord, Show)
```

`TReg` and `TInpCtorField` now call `memoFree` with `RegVar`/`InpVar`; render those to their
existing labels so `symSatExt` remains byte-for-byte compatible. On the first
`ProjectionVar`, allocate an internal label `proj/<ordinal>` where the ordinal is unique in
that `SymEnv`; projection user strings never become an SBV label. The structured map controls
reuse, so arbitrary slashes, `|`, backslashes, and empty segments in names cannot collide or
trip SBV's label restrictions. Include `SomeTypeRep projection` as the projection identity,
plus both `SomeTypeRep (FieldOwner projection)` and
`SomeTypeRep (FieldResult projection)` defensively. `fieldShapeId` and `FieldName` are used
only for diagnostics, never cache equality. `memoFree` retains its representation-type check
as a defensive assertion.

Add one pure `indexPosition :: Index xs a -> Int` helper (zero at `ZIdx`, increment through
`SIdx`) in `Keiki.Core`'s internals and reuse it from Symbolic and Composition instead of the
current local `indexInt`/`indexPos` copies where practical. Position is part of symbolic
identity; the human-readable path continues to show names only.

Add to `translateTermSym` (the `Sym r` constraint the function already carries is exactly
IR clause 2's "only the result type must be in the registry" — the `owner` type never needs
`Sym`):

```haskell
translateTermSym env (TFieldProj (w :: FieldWitness projection) base) =
  memoFree env (projectionVarKey w base)
```

with a helper computing the structured key per the Decision Log:

```haskell
projectionVarKey ::
  forall projection rs ci ifs.
  ( FieldProjection projection,
    KnownSymbol (FieldName projection),
    Typeable projection,
    Typeable (FieldOwner projection),
    Typeable (FieldResult projection)
  ) =>
  FieldWitness projection ->
  ProjBase rs ci ifs (FieldOwner projection) ->
  SymVarKey
projectionVarKey w base =
  ProjectionVar
    (case base of
      PBReg ix -> ProjectionReg (indexName ix) (indexPosition ix)
      PBInp ic ix -> ProjectionInp (icName ic) (indexName ix) (indexPosition ix))
    (SomeTypeRep (typeRep @projection))
    (SomeTypeRep (typeRep @(FieldOwner projection)))
    (SomeTypeRep (typeRep @(FieldResult projection)))
```

Export a narrow lower-level helper from `Keiki.Symbolic` for the agreement harness:

```haskell
constrainFieldProjection ::
  ( Typeable projection,
    Typeable (FieldOwner projection),
    Sym (FieldResult projection)
  ) =>
  SymEnv ->
  FieldWitness projection ->
  ProjBase rs ci ifs (FieldOwner projection) ->
  FieldResult projection ->
  SBV.Symbolic ()
```

It obtains the same memoized projection variable and constrains it equal to `symLit` of the
provided concrete getter result. Document that it is a one-way concrete-binding helper, not
an inverse for `symSatExt`. Extend the `translateTermSym` and `symSatExt` Haddocks: internal
`proj/<ordinal>` variables are never extracted; a consumer-owned register/input field without
`Sym` makes `symSatExt` unavailable, and a projected model alone cannot reconstruct an owner.

Tests (extend `test/Keiki/SymbolicSpec.hs`'s "memoization (EP-42)" describe block, plus
`test/Keiki/FieldProjSpec.hs`):

- `symIsBot (regProj docHashW #doc ./= regProj docHashW #doc)` is `True` — same path,
  one shared variable, `x /= x` unsat (this is the IR's headline z3-backed validity test).
- `symIsBot (regProj docHashW #doc ./= regProj docTitleW #doc)` is `False` —
  different fields of the same slot are independent variables.
- Key-separation tests: two nominal tags with identical shape/field diagnostic strings must
  remain independent; different owner types and different result types (specifically `Int`
  versus `Integer`, whose `SymRep`s coincide) must remain independent; and adversarial path
  strings containing the old `/` separators cannot affect identity or SBV labels. Add a
  manually indexed duplicate-label register/input schema to prove different positions do not
  share even when their rendered dotted paths are identical; generated/builder schemas still
  retain their existing distinct-name rule. These tests prove that only the base plus nominal
  tag decides sharing and every caller-controlled string is diagnostic-only.
- Agreement properties (QuickCheck), one for `regProj` and one for `inpProj`: generate a
  concrete `DocInfo` and comparison literal, build the predicate, create one `SymEnv`, call
  `translatePred`, constrain the projection with `constrainFieldProjection env w base
  (fieldWitnessGet w owner)`, and ask SBV to prove that the resulting Boolean equals
  `evalPred` on the concrete registers/input. Because this starts z3 per case, cap each
  property explicitly
  (for example 25 cases) and use a generator that guarantees both true and false comparisons
  rather than relying on chance. This
  proves that every concrete state has a matching symbolic valuation; do not use
  `symSatExt`, and do not assert the false converse that every free projection model can be
  rebuilt into an owner.

Acceptance: `cabal test all` green; the new z3-backed examples run alongside the existing
EP-42 suite (z3 must be on PATH, as for the current suite). The existing `symSatExt` tests for
ordinary scalar slots remain unchanged and green.

### Milestone 3 — validator integration and replay proof

Scope: `validateTransducer` rejects every use that would silently lose the promised symbolic
semantics or violate the guards-only boundary; projected reads follow the established
input-read and hidden-input disciplines; a forward-vs-replay test proves replay is unchanged.

In `src/Keiki/Core.hs`:

- Add three `TransducerValidationWarning` constructors, each carrying the `EdgeRef`, dotted
  path, `fieldShapeId`, result-type text where relevant, and a human-readable detail:
  `ProjectionResultUnsupported`, `ProjectionOrderingUnsupported`, and
  `ProjectionOutsideGuard`. They are unconditional entries in `validateTransducer`'s result,
  not controlled by `ValidationOptions`. They are warnings in the API's established sense;
  the release fixture and Keiro boundary reject a non-empty result.
- Walk every guard term. For each `TFieldProj @projection`, query
  `discoverSymbolicType @(FieldResult projection)` from
  `Keiki.Internal.SymbolicTypes`; emit
  `ProjectionResultUnsupported` on a miss. For every `PCmp` whose operands contain a
  projection, query the same registry's ordering classifier for the comparison operand type;
  emit `ProjectionOrderingUnsupported` on a miss. This closes the `Bool`/`Text` ordering
  hole that a plain `discoverSym` check would miss. Equality over a supported projection
  remains accepted. Opaque `TApp1`/`TApp2` still receive the separate opt-in `OpaqueGuard`
  warning; the projection checks do not pretend those functions became structural.
- Walk every update right-hand side and every `OutFields` term and emit
  `ProjectionOutsideGuard` for each projection found. Keep evaluation and replay total for
  such malformed raw transducers, but make `validateTransducer defaultValidationOptions`
  reject them. Use `fieldProjectionPath` for diagnostics so Core does not import Pretty.
- Confirm (with tests, not new code, if Milestone 1 did its job) that: a guard using
  `inpProj … newDocCtor #doc` without the matching `PInCtor` guard trips the same
  guard-implies-input-read validation as a bare `TInpCtorField` read; and an output event
  that reads an input field *only* through a projection reports that field as a hidden
  input (`HirHeadUnrecoverable`/`HeadUnrecoverable`), i.e. the projected read counts,
  conservatively, as a read of the whole field.

Tests: in `test/Keiki/ValidationSpec.hs`, build a small two-state transducer fixture whose
edges guard on `regProj`/`inpProj` comparisons
(follow the fixture style in `test/Keiki/Fixtures/`); assert `validateTransducer` under
`defaultValidationOptions` is clean; assert the `ProjectionResultUnsupported` case fires for
a witness whose result type is outside the registry (e.g. project a `[Int]` field); assert
`ProjectionOrderingUnsupported` for `PCmp` on a `Text` projection while `PEq` on the same
projection is accepted; assert `ProjectionOutsideGuard` separately for an update and an
output term; assert `OpaqueGuard` (with `warnOpaqueGuards = True`) stays silent for
projection guards and still fires for `TApp1` guards; and prove replay unchanged — run the
fixture forward over a command sequence, `reconstituteEither` from the recorded events, and
assert the final vertex and complete `RegFile` equal the forward result (follow the permanent
property style in `test/Keiki/RoundTrip.hs` and the fixtures in
`test/Keiki/RoundTripSpec.hs` / `ReplayOnlySpec.hs`). Put that forward/replay fixture in
`test/Keiki/FieldProjSpec.hs` so the capability's end-to-end proof stays together.

Acceptance: `cabal test all` green with the validator and replay tests included.

### Milestone 4 — laws, harness, and documentation

Scope: the projection-instance laws are written where users will read them; a reusable law harness is
exported so Keiro's generated conformance tests can instantiate it; documentation
cross-references land.

- Haddocks on `FieldProjection`, `FieldWitness`, `fieldWitness`, `TFieldProj`, `regProj`,
  and `inpProj` state: `projectFieldValue` is total on well-formed owners; one fresh nominal
  tag denotes one logical projection; `FieldName` and `fieldShapeId` truthfully describe its
  getter; and concrete/symbolic agreement is one-way. Explain that the normal Haskell instance
  coherence rule supplies one getter per tag and `TypeRep projection` supplies cache identity,
  so caller strings cannot cause unsound sharing. Provenance remains divided exactly as the
  research requires: Keiki defines and tests term/law behavior; truthfulness against a wire
  schema comes from the generator (Keiro) and its mutation-tested conformance harness. A
  dishonest instance can mislabel which concrete field the DSL denotes, but cannot create two
  meanings for one tag without explicitly opting into incoherent-instance behavior outside
  Keiki's supported contract. Generators should reuse one canonical tag for every occurrence
  of one logical projection; emitting duplicate tags is sound but loses proof precision because
  the solver deliberately treats them as independent.
- Keep the law harness exported from `Keiki.Core`, beside `FieldWitness`:

```haskell
-- | Does the witness's getter agree with a reference projection on this value?
-- Generators instantiate this over their own 'Gen owner' to prove a generated
-- instance right — and, mutated, to prove a wrong instance fails.
fieldWitnessAgrees ::
  forall projection.
  (FieldProjection projection, Eq (FieldResult projection)) =>
  FieldWitness projection ->
  (FieldOwner projection -> FieldResult projection) ->
  FieldOwner projection ->
  Bool
fieldWitnessAgrees w ref o = fieldWitnessGet w o == ref o
```

- Positive and negative harness tests: QuickCheck the real witness against its reference
  getter. Define a separate deliberately wrong nominal tag whose coherent instance selects
  the other same-result-type field, then wrap its property in QuickCheck's `expectFailure` and
  show that `fieldWitnessAgrees` finds a counterexample. Do not use a constant alternate record
  that might accidentally agree for some generated values without controlling the generator;
  use a record with two `Int` fields and swap them while filtering or generating unequal fields.
- Documentation: create `docs/research/field-projection-design.md`; the topic now includes a
  simulation argument, structured cache identity, validation placement, model-extraction
  limitation, and composition policy, so appending a short section to
  `docs/research/tinpproj-design.md` would obscure the distinct trust boundary. Link the new
  note from the existing input-projection design. Update
  `docs/adr/0003-proof-gates-fail-conservatively.md` with the concrete-to-symbolic
  over-approximation rule and `docs/adr/0004-composition-uses-snapshot-updates-and-checked-boundaries.md`
  with the preserve/fold/lower behavior. The IR file already carries `status: planned` and a
  `plan:` pointer; at release (Milestone 5) advance it to `status: released` and append the
  change to `docs/improvement-requests/log.md`.

Acceptance: `cabal haddock` builds cleanly; `cabal test all` green including the negative
property.

### Milestone 5 — release

Scope: the capability is released and tagged so Keiro can pin it, per the IR's
Compatibility Baseline.

Invoke the repository's `$release` skill and follow `docs/research/release-procedure.md` end
to end. Specifically, re-verify the baseline first with both authoritative commands (the IR
requires repeating this check at implementation time, not trusting the planning snapshot):

```bash
curl -fsSL https://hackage.haskell.org/package/keiki/preferred.json
git ls-remote --tags https://github.com/shinzui/keiki.git
mori registry dependents shinzui/keiki --packages
```

As of the 2026-07-28 audit, both identify 0.3.1.0/v0.3.1.0 as latest. If either has advanced,
stop and recompute the PVP target rather than blindly publishing 0.4.0.0. Otherwise bump
`keiki.cabal` to `0.4.0.0`; write the changelog entry naming the new Core and Symbolic exports,
the validation/composition warnings, the `symSatExt` limitation, and the breaking `Term`
constructor addition; run the full release test matrix; publish in the procedure's order;
then tag `v0.4.0.0`. Record in the handoff that Keiro's current `<0.4` bounds intentionally
exclude the new major version and must be raised by its later adoption plan; do not mutate
sibling repositories from this Keiki ExecPlan.

Acceptance: `git tag` lists `v0.4.0.0`; the changelog names `TFieldProj`; the release
procedure's checks all pass.


## Concrete Steps

All commands run from the repository root `/Users/shinzui/Keikaku/bokuno/keiki` (adjust to
wherever the repo is checked out).

Build and test loop, used at every stopping point:

```bash
cabal build
cabal test all
```

Expected shape of a passing test run (counts will grow as specs are added):

```text
All N examples behaved as expected
Test suite keiki-test: PASS
```

If the default `ghc` is not the project toolchain, use the release procedure's form:

```bash
GHCUP_GHC_VERSION=9.12.2 cabal test all
```

Formatting before each commit (canonical shared fourmolu config; see
`docs/research/release-procedure.md` if `nix fmt` is wired):

```bash
nix fmt -- --no-cache
```

Commit after each milestone (and at natural stopping points inside them), leaving the tree
green, with both trailers:

```text
feat(core): add TFieldProj typed field projection over mapped values

<body>

ExecPlan: docs/plans/79-typed-symbolic-field-projections-over-mapped-consumer-owned-values.md
Intention: intention_01kym838n3emd9f6qgw288sx0x
```

Suggested commit granularity: one commit per milestone minimum; Milestone 1 splits well
into "term + walkers" and "tests".


## Validation and Acceptance

The plan is done when every item in the IR's Acceptance section is demonstrated:

1. Term and witness exist with law-stating Haddocks (Milestone 1 + 4). Verify:
   `cabal haddock` renders `FieldProjection`/`FieldWitness` docs stating totality, nominal
   identity, instance coherence, and provenance.
2. Evaluation, translation, and predicate support with an agreement property
   (Milestones 1–2). Verify: both concrete-binding QuickCheck properties pass, including
   generated cases where the comparison is false; the test must not rely on `symSatExt`.
3. Path-keyed memoization with a z3-backed validity proof (Milestone 2). Verify: the
   `symIsBot (proj /= proj)` example passes, while tag/owner/result/base collision tests
   remain satisfiable and adversarial delimiter strings stay independent.
4. `OpaqueGuard` discrimination in both directions (Milestones 1 and 3). Verify: the
   two-direction tests pass.
5. Validator discipline and replay unchanged (Milestone 3). Verify: `PInCtor`,
   hidden-input, outside-guard, ordering-support, and forward-vs-replay tests pass;
   `ProjectionResultUnsupported` fires on the negative fixture.
6. Dotted-path diagnostics (Milestone 1). Verify: `prettyTerm` test asserts
   `doc.contentHash`.
7. Negative projection-instance harness (Milestone 4). Verify: the wrong-getter instance's
   property fails through QuickCheck `expectFailure`, while the reference instance's property
   passes.
8. Released and tagged (Milestone 5). Verify: `git tag` shows `v0.4.0.0`.
9. Composition stays honest (Milestones 1 and 4). Verify: stable pass-through projections
   remain `TFieldProj`, raw composition of a computed owner remains forward-equivalent but
   opaque, and `composeChecked` rejects that lossy boundary.
10. The Keiro proposal test stays satisfied (all milestones). Verify the ten answers in
    Context against the final API and tests; in particular, no implementation change gives
    Keiki wire authority, permits projected writes, or turns a hand-written projection
    instance into a checked wire-provenance claim.

Beyond compilation, the main end-to-end demonstration is the Milestone 3 fixture: a transducer
whose edge guards compare projected fields, validated clean under default options, executed
forward, and replayed to the same state — something that before this plan required either
promoted scalar fields or an `OpaqueGuard`-tripping `TApp1`. The composition fixture is a
second end-to-end check that this claim survives a stable checked pipeline and fails loudly
when the boundary cannot retain a stable projection path.


## Idempotence and Recovery

Every step is additive until Milestone 5 except the internal registry extraction, which is a
behavior-preserving move covered by the existing registry and symbolic suites.
`cabal build`/`cabal test all` are safe to re-run indefinitely. If a milestone is interrupted,
the compiler's incomplete-pattern warnings enumerate total walkers still lacking a
`TFieldProj` case; resume from the explicit five-module walker list as well, because wildcard
classifiers do not warn. Commits land only on green trees, so `git log` plus the Progress
checklist is sufficient to resume; update Progress before stopping. If composition lowering
is half-implemented, temporarily keep `composeChecked` rejecting every downstream projection
rather than returning a falsely checked composite, then narrow the rejection only after its
preservation tests pass. The only externally non-additive step is release (version bump,
upload, and tag): delete no published artifact after a partial failure; fix forward with a
new patch version per the release procedure. Do not tag until the full matrix passes.


## Interfaces and Dependencies

No new dependencies. The work uses the existing `sbv >=11.7 && <15` (z3 backend),
`hspec ^>=2.11`, and `QuickCheck ^>=2.15` already in `keiki.cabal`; z3 must be on PATH for
the symbolic tests, as it already is for `test/Keiki/SymbolicSpec.hs`. Mori located the SBV
source at `/Users/shinzui/Keikaku/hub/haskell/sbv-project/sbv`; the audit read `free` and
`registerLabel` there rather than assuming name-reuse behavior. Hackage reported SBV 13.6 on
2026-07-28, inside the existing bound. No dependency bound changes are planned.

At the end of Milestone 1, `Keiki.Core` exports:

```haskell
class FieldProjection projection where
  type FieldName projection :: Symbol
  type FieldOwner projection :: Type
  type FieldResult projection :: Type
  fieldShapeId :: Proxy projection -> String
  projectFieldValue ::
    Proxy projection -> FieldOwner projection -> FieldResult projection

type role FieldWitness nominal
data FieldWitness projection = FieldWitness -- export the type, not the constructor

fieldWitness ::
  ( FieldProjection projection,
    KnownSymbol (FieldName projection),
    Typeable projection,
    Typeable (FieldOwner projection),
    Typeable (FieldResult projection)
  ) =>
  FieldWitness projection

data ProjBase (rs :: [Slot]) (ci :: Type) (ifs :: [Slot]) owner where
  PBReg :: Index rs owner -> ProjBase rs ci ifs owner
  PBInp :: InCtor ci ifs -> Index ifs owner -> ProjBase rs ci ifs owner

-- new Term constructor (via the existing Term(..) export)
TFieldProj ::
  ( FieldProjection projection,
    KnownSymbol (FieldName projection),
    Typeable projection,
    Typeable (FieldOwner projection),
    Typeable (FieldResult projection)
  ) =>
  FieldWitness projection ->
  ProjBase rs ci ifs (FieldOwner projection) ->
  Term rs ci ifs (FieldResult projection)

regProj ::
  ( FieldProjection projection,
    KnownSymbol (FieldName projection),
    Typeable projection,
    Typeable (FieldOwner projection),
    Typeable (FieldResult projection)
  ) =>
  FieldWitness projection ->
  Index rs (FieldOwner projection) ->
  Term rs ci ifs (FieldResult projection)

inpProj ::
  ( FieldProjection projection,
    KnownSymbol (FieldName projection),
    Typeable projection,
    Typeable (FieldOwner projection),
    Typeable (FieldResult projection)
  ) =>
  FieldWitness projection ->
  InCtor ci ifs ->
  Index ifs (FieldOwner projection) ->
  Term rs ci ifs (FieldResult projection)

fieldProjectionPath ::
  (FieldProjection projection, KnownSymbol (FieldName projection)) =>
  FieldWitness projection ->
  ProjBase rs ci ifs (FieldOwner projection) ->
  String

fieldWitnessAgrees ::
  (FieldProjection projection, Eq (FieldResult projection)) =>
  FieldWitness projection ->
  (FieldOwner projection -> FieldResult projection) ->
  FieldOwner projection ->
  Bool

-- exported under Keiki.Core's internals for Symbolic/Composition reuse
fieldWitnessGet ::
  (FieldProjection projection) =>
  FieldWitness projection ->
  FieldOwner projection ->
  FieldResult projection
indexPosition :: Index xs a -> Int
```

At the end of Milestone 2, `Keiki.Symbolic` additionally exports
`constrainFieldProjection` for the one-way agreement harness. Keep `projectionVarKey` and
`SymVarKey` internal; exercise key separation through satisfiability/unsatisfiability tests,
including a conjunction over `Int` and `Integer` projections that would become falsely
unsatisfiable if their same SBV representation were shared.
Its `translateTermSym` accepts the new constructor with only
`Sym (FieldResult projection)`—the owner type never requires `Sym`.
`src/Keiki/Internal/SymbolicTypes.hs` is a hidden
library module, while `Keiki.Symbolic` continues to export the existing `Sym` and
`discoverSym*` API.

At the end of Milestone 3, `TransducerValidationWarning(..)` exposes
`ProjectionResultUnsupported`, `ProjectionOrderingUnsupported`, and
`ProjectionOutsideGuard`. `src/Keiki/Composition.hs` exposes the new
`NonStructuralProjectionBoundary` constructor through its existing
`ComposeAlignmentWarning(..)` export. Both additions are source-breaking for exhaustive
downstream matches and must be named in the 0.4.0.0 changelog.


## Revision Notes

- 2026-07-28: At the user's request, the IR file
  (`docs/improvement-requests/support-typed-symbolic-field-projections-over-mapped-consumer-values.md`)
  was cross-linked to this plan at planning time rather than waiting for Milestone 4: its
  frontmatter gained `plan:` pointing here, its `status:` moved `proposed` → `planned`, and
  `docs/improvement-requests/log.md` records the change. Milestone 4 and the Progress
  checklist were updated accordingly; the remaining IR obligation is the `status: released`
  advance in Milestone 5.
- 2026-07-28: Soundness/correctness audit revised the plan after checking the current code,
  relevant ADRs, Mori-located SBV source, Hackage, and upstream tags. Replaced the ambiguous
  string memo key with a structured key (subsequently strengthened to nominal projection-tag/
  owner/result identity); replaced the infeasible
  `symSatExt` agreement test with a one-way concrete binding proof; introduced a cycle-free
  shared symbolic-type classifier and ordering-aware validation; made guards-only placement
  an unconditional validation rule; enumerated all Core/Composition/Profunctor walkers; and
  specified preservation, safe opacity lowering, and checked rejection at composition
  boundaries. These changes are necessary to prevent false unsatisfiability proofs and to
  make every planned step implementable in the current module graph.
- 2026-07-28: Architectural-value review traced the complete provenance from Mori MasterPlan
  22 / ExecPlan 171 through Keiro IR-1 / MasterPlan 25 to this Keiki IR. Recorded a GO on the
  addition: it is a Keiki-owned structural AST gap discovered by a real migration, while
  promoted scalar decision registers remain the sound default and the current Mori port's
  non-blocking fallback. Also clarified that the plan's small `DocInfo` test fixture is not
  the current Mori record, whose content hash is computed separately.
- 2026-07-28: Read Keiro research note 14 and Keiro IR-1 end to end at the user's direction.
  Added the research note's ten-question proposal-test answers, recorded its medium-risk (not
  research-grade) classification and recommended Experiment C, and changed the primary test
  fixture to a `Text` projection so the first acceptance slice matches that experiment.
- 2026-07-28: Re-ran the design review library-first rather than treating Mori's domain model
  as API authority. Replaced the public `(String, getter)` witness record with a consumer-
  neutral nominal `FieldProjection` tag class and abstract `FieldWitness`; symbolic identity
  now uses `TypeRep projection`, while shape/field strings are diagnostic-only. This removes
  accidental same-string/different-getter over-sharing from the trusted proof boundary and
  leaves only the unavoidable totality and schema-provenance laws of the projection instance.
  Recorded explicitly that Mori/Keiro are motivating consumers and conformance probes, not
  sources of Keiki API semantics.
- 2026-07-28: Implemented Milestones 1–3 and refined the documented
  `constrainFieldProjection` signature after GHC proved its class/name constraints redundant.
  The abstract witness remains the instance-provenance gate; the binding helper now advertises
  only the dictionaries it actually consumes.
- 2026-07-28: Completed Milestone 4. Expanded public Haddocks, added the self-contained
  field-projection research note and input-projection cross-link, and updated ADR-0003 and
  ADR-0004 with the one-way over-approximation and preserve/fold/lower composition decisions.
