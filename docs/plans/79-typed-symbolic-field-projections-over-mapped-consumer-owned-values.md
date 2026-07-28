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
(Keiki IR-1, filed by the `shinzui/keiro` project). Read that file first; this plan repeats
everything needed to implement it, but the IR is the statement of intent and its Acceptance
section is the contract this plan must discharge.


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

After this change, a spec author writes a guard over one *field* of such a mapped value
through a new first-class term, `TFieldProj`, backed by a `FieldWitness` (a total getter plus
a stable shape identity). Concretely, where today one must promote `contentHash` to its own
register slot, after this plan the guard

```haskell
peq (regProj docHashW #doc) (inpProj docHashW newDocCtor #doc)
```

(comparing `doc.contentHash` in the register against `doc.contentHash` in the incoming
command) evaluates by applying the getter, translates to a *shared* SBV variable per field
path so the solver treats two reads of the same field as equal, does not trigger the
`OpaqueGuard` audit, renders as the dotted path `doc.contentHash` in diagnostics, and leaves
replay semantics untouched. The capability is released and tagged so Keiro can pin it; Keiro
generates the witnesses and proves them against its codecs — Keiki defines and tests the
laws.

Observable outcome: after Milestone 5, `cabal test all` passes with new z3-backed tests
proving `proj == proj` is valid and `TApp1` guards still audit as opaque, and the repository
carries a `v0.4.0.0` tag whose changelog names this capability.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] M1: add `FieldWitness`, `ProjBase`, `TFieldProj`, smart constructors `regProj`/`inpProj` to `src/Keiki/Core.hs`
- [ ] M1: extend every total `Term` walker in `src/Keiki/Core.hs` (`evalTerm`, `termHasOpaqueApp`, `termInCtorNames`, `gatherInpEntries`/`stepOne`, `recomputeOne`, `updateReadsInput`'s term walker) and `prettyTerm` in `src/Keiki/Render/Pretty.hs`
- [ ] M1: export the new names from `Keiki.Core` (and re-export via `Keiki` if the umbrella module re-exports term constructors)
- [ ] M1: unit tests — evaluation, dotted-path rendering, opacity in both directions
- [ ] M2: `translateTermSym` case in `src/Keiki/Symbolic.hs` with path-keyed memoization (owner `TypeRep` + `fwShapeId` + base path + field name)
- [ ] M2: z3-backed tests — `proj == proj` valid, distinct fields independent, shape-collision key test, concrete/symbolic agreement property
- [ ] M3: `ProjectionResultUnsupported` validation error in `validateTransducer` (on by default)
- [ ] M3: hidden-input / `PInCtor` discipline tests; forward-vs-replay equality test over a projection-guarded transducer
- [ ] M4: Haddocks with the witness laws and provenance division; exported witness-law harness (`fieldWitnessAgrees`) plus negative test proving a wrong witness fails
- [ ] M4: documentation pass — `docs/research/tinpproj-design.md` cross-reference or a short design note (IR already points here; status advances to `released` in M5)
- [ ] M5: changelog entry, version bump to 0.4.0.0, Hackage/upstream-tag re-check, release and tag per `docs/research/release-procedure.md`
- [ ] Final: ADR distillation pass and Outcomes & Retrospective


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


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
- Decision: Key the symbolic memo cache by
  `"proj/" <> basePath <> "/" <> fwShapeId <> "@" <> show (typeRep @owner) <> "/" <> fieldName`,
  where `basePath` is the existing `reg/<slot>` or `inp/<ctor>/<slot>` name.
  Rationale: Accidental key collision is an *unsoundness*, not a precision loss: if two
  genuinely different fields shared a cache key, the solver would see one variable where
  there are two, over-constraining the formula and potentially *falsely proving* mutual
  exclusion or edge deadness (violating ADR-0003's "never bless an unsafe model"). A
  `fwShapeId` string alone could collide across distinct owner types; including the owner's
  `TypeRep` makes intra-translation collision require both a shape-id collision *and* a type
  coincidence at the same slot, which the witness identity law (Milestone 4) forbids.
  Under-sharing (free variables) is merely conservative; over-sharing is not, so the key
  errs toward more discrimination.
  Date: 2026-07-28
- Decision: The inversion and replay machinery treats `TFieldProj` as a *derived,
  non-invertible* term — exactly the existing `TApp1` treatment: `gatherInpEntries`/`stepOne`
  contribute no recovered entries, `recomputeOne` recomputes it forward, and the
  hidden-input analysis counts it as a read of the whole underlying slot/field.
  Rationale: The `Term` GADT cannot ban `TFieldProj` from `OutFields` or `Update`
  right-hand sides (a constructor is usable anywhere `Term` is accepted), so "guards only"
  cannot be a type-level fact. Falling through the inversion pattern matches would break
  replay soundness (ADR-0002); classifying the constructor as derived keeps every walker
  total and replay semantics unchanged, and matches IR clause 4's whole-value-copy
  contract without inventing a new rejection path.
  Date: 2026-07-28
- Decision: An unsupported projection *result* type is a hard `validateTransducer` error
  (`ProjectionResultUnsupported`), checked unconditionally (not gated behind an option like
  `warnOpaqueGuards`).
  Rationale: IR clause 2 demands "a construction- or validation-time rejection, never a
  silent fallback to opacity." The existing `PEq`/`PCmp` translation falls back to a fresh
  `SBool` on a `discoverSym` miss; without this check a projection at an unsupported type
  would silently degrade to exactly the opacity the term exists to avoid, while *not*
  triggering `OpaqueGuard` (since `TFieldProj` is not opaque) — the worst combination.
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
- Decision: Spellings — constructor `TFieldProj`, witness `FieldWitness` with `fwShapeId`
  and `fwGet` (as in the IR), base GADT `ProjBase` with `PBReg`/`PBInp`, smart constructors
  `regProj` and `inpProj`, law harness `fieldWitnessAgrees`.
  Rationale: The IR leaves spelling to Keiki; these follow the existing `T*`-constructor /
  lowercase-smart-constructor convention (`inpCtor`, `tadd`).
  Date: 2026-07-28


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

(To be filled during and after implementation.)


## Context and Orientation

Everything below is verifiable in the working tree; file paths are repository-relative.
The reader is assumed to know Haskell (GADTs, type-level lists, `Typeable`) but nothing
about this repository.

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
memo cache in `SymEnv` (`seVarCache`, an `IORef (Map String SomeSBV)`, from EP-42 of
MasterPlan 12): the first read of a name allocates `SBV.free`, later reads return the cached
variable, so repeated reads of one slot are *one* solver variable and `x /= x` is provably
unsat. `TApp1`/`TApp2` translate to per-occurrence fresh variables (sound but opaque).
`translatePred` dispatches `PEq`/`PCmp` through `discoverSym`/`discoverSymOrd` and falls
back to a fresh `SBool` on a miss. `symIsBot` asks z3 whether a predicate is unsatisfiable;
per ADR-0003 only a definite `Unsatisfiable` counts as proof.

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

**Relevant ADRs** (in `docs/adr/`; scanned all five, three matter here):

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

ADR-0004 (composition boundaries) and ADR-0005 (wire identities) are not affected: this
plan adds no wire format and does not change composition. Note for Milestone 1: the
composition substitution in `src/Keiki/Composition.hs` (`unsafeCoerceTerm`) and any other
total `Term` walkers found by the compiler must be extended for the new constructor —
building with `-Wincomplete-patterns` (already the project default via `-Wall`) finds them
all.

**The improvement request's boundaries.** Guards only: projections in `OutFields` or
register writes stay out of scope (mapped values move as whole-value copies). No collection
semantics, no new `Sym` registry types, no `keiro-dsl` surface work. Keiro generates
witnesses from its structural binding graph and proves them with mutation tests; Keiki
defines the laws and ships the harness — Haddocks must state this division.


## Plan of Work

The work is five milestones, each independently verifiable, each leaving `cabal test all`
green. Run all commands from the repository root. GHC 9.12 is the toolchain (see
`docs/research/release-procedure.md` for the `GHCUP_GHC_VERSION` invocation if your default
`ghc` differs).

### Milestone 1 — the term, its evaluator, and total-walker coverage

Scope: `src/Keiki/Core.hs` gains the witness and term; every total walker learns the new
constructor; rendering produces dotted paths; opacity classification is correct. At the end
the library compiles warning-free and unit tests cover evaluation, rendering, and opacity.

Add to `src/Keiki/Core.hs`, near `InCtor` (the "structural projection" neighborhood):

```haskell
-- | Witness that field @name@ of the consumer-owned type @owner@ has type @r@.
-- Laws (see Haddock section written in Milestone 4): 'fwGet' is total for every
-- well-formed @owner@; 'fwShapeId' stably and uniquely names the owning declared
-- shape within one specification. Keiki checks these laws via 'fieldWitnessAgrees';
-- provenance (that the witness matches the wire schema) is the generator's burden.
data FieldWitness (name :: Symbol) owner r = FieldWitness
  { fwShapeId :: String
  , fwGet :: owner -> r
  }

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
    (KnownSymbol name, Typeable owner, Typeable r) =>
    FieldWitness name owner r ->
    ProjBase rs ci ifs owner ->
    Term rs ci ifs r
```

with smart constructors mirroring `inpCtor`/`tadd`:

```haskell
regProj :: (KnownSymbol name, Typeable owner, Typeable r)
        => FieldWitness name owner r -> Index rs owner -> Term rs ci ifs r
regProj w ix = TFieldProj w (PBReg ix)

inpProj :: (KnownSymbol name, Typeable owner, Typeable r)
        => FieldWitness name owner r -> InCtor ci ifs -> Index ifs owner
        -> Term rs ci ifs r
inpProj w ic ix = TFieldProj w (PBInp ic ix)
```

Then let the compiler drive: every incomplete-pattern warning is a walker to extend.
The required semantics per walker:

- `evalTerm` — mirror the base read, then apply the getter:
  `PBReg ix` is `fwGet w (regs ! ix)`; `PBInp ic ix` matches `icMatch ic ci` and applies
  `fwGet w (rf ! ix)` on `Just`, erroring like `TInpCtorField` on `Nothing` (same guard
  discipline, same message shape naming `icName`).
- `termHasOpaqueApp` — `False` for `TFieldProj` (this is the whole point; the two-direction
  test in this milestone proves `TApp1` still returns `True`).
- `termInCtorNames` — `[]` for `PBReg`, `[icName ic]` for `PBInp`, so the
  guard-implies-input-read discipline sees the projected read.
- `updateReadsInput`'s term walker (and anything else `edgeReadsInput` relies on) — a
  `PBInp` base reads the input.
- `gatherInpEntries`/`stepOne` — `Just []` (derived field: contributes no recovered
  entries), matching the `TApp1` clause.
- `recomputeOne` — recompute forward via `evalTerm`, matching the `TApp1` clause.
- `src/Keiki/Composition.hs` `unsafeCoerceTerm` (and any sibling substitution walkers) —
  extend structurally, re-aligning the base's index/`InCtor` exactly as the `TReg`/
  `TInpCtorField` clauses do, under the same documented alignment invariant.
- `src/Keiki/Render/Pretty.hs` `prettyTerm` — dotted path: `PBReg ix` renders
  `indexName ix <> "." <> fieldName`, `PBInp ic ix` renders
  `icName ic <> "." <> indexName ix <> "." <> fieldName`, where `fieldName` is
  `symbolVal` of the witness's `name`. (`indexName` currently lives in `Symbolic.hs`;
  `Pretty.hs` already renders slot names its own way — reuse whichever helper it uses.)

Export `FieldWitness(..)`, `ProjBase(..)`, `regProj`, `inpProj` (and `TFieldProj` via the
existing `Term(..)` export) from `Keiki.Core`, and thread through the umbrella `Keiki`
module if it re-exports these groups.

Tests (new file `test/Keiki/FieldProjSpec.hs`, registered in `test/Spec.hs` and in
`keiki.cabal` `other-modules`): define a tiny consumer-owned record
(`data DocInfo = DocInfo { diHash :: Int, diTitle :: Text }`) and a witness
`docHashW = FieldWitness "doc-info" diHash :: FieldWitness "contentHash" DocInfo Int`;
assert `evalTerm (regProj docHashW #doc) regs ci` equals the hash in the register; assert
`prettyTerm` renders `doc.contentHash`; assert `predHasOpaqueTerm` is `False` for a
projection-only guard and `True` for the equivalent `TApp1 diHash` guard.

Acceptance: `cabal build` warning-free; `cabal test all` green including the new spec.

### Milestone 2 — symbolic translation with path-keyed memoization

Scope: `src/Keiki/Symbolic.hs` translates `TFieldProj` to a memoized solver variable; z3
tests prove sharing and non-sharing are both right; a QuickCheck property ties concrete and
symbolic semantics together.

Add to `translateTermSym` (the `Sym r` constraint the function already carries is exactly
IR clause 2's "only the result type must be in the registry" — the `owner` type never needs
`Sym`):

```haskell
translateTermSym env (TFieldProj (w :: FieldWitness name owner r) base) =
  memoFree env (projKey w base)
```

with a helper computing the key per the Decision Log:

```haskell
projKey ::
  forall name owner r rs ci ifs.
  (KnownSymbol name, Typeable owner) =>
  FieldWitness name owner r -> ProjBase rs ci ifs owner -> String
projKey w base =
  "proj/" <> basePath <> "/" <> fwShapeId w
    <> "@" <> show (typeRep @owner)
    <> "/" <> symbolVal (Proxy @name)
  where
    basePath = case base of
      PBReg ix -> "reg/" <> indexName ix
      PBInp ic ix -> "inp/" <> icName ic <> "/" <> indexName ix
```

Also extend the `translateTermSym` Haddock's variable-naming section: `symSatExt`'s by-name
witness extraction ignores `proj/…` variables (they are not slot values; do not add them to
extracted witnesses — check how `symSatExt` filters names and keep projections out, the same
way `app1`/`app2`/`arith` variables are not extracted).

Tests (extend `test/Keiki/SymbolicSpec.hs`'s "memoization (EP-42)" describe block, plus
`test/Keiki/FieldProjSpec.hs`):

- `symIsBot (pneq (regProj docHashW #doc) (regProj docHashW #doc))` is `True` — same path,
  one shared variable, `x /= x` unsat (this is the IR's headline z3-backed validity test).
- `symIsBot (pneq (regProj docHashW #doc) (regProj docTitleLenW #doc))` is `False` —
  different fields of the same slot are independent variables.
- Shape-collision key test: two witnesses over *different* owner types that share
  `fwShapeId` string and field name must still produce different keys (assert on `projKey`
  directly, and/or via `symIsBot` being `False` on cross-owner inequality through two slots).
- Agreement property (QuickCheck): for a generated register value, a satisfying concrete
  assignment makes `evalPred` and the symbolic translation agree — follow the shape of the
  existing agreement tests in `SymbolicSpec.hs` (the file's `proveP` helper and the EP-42
  memoization examples show the established pattern).

Acceptance: `cabal test all` green; the new z3-backed examples run alongside the existing
EP-42 suite (z3 must be on PATH, as for the current suite).

### Milestone 3 — validator integration and replay proof

Scope: `validateTransducer` rejects unsupported projection result types; projected reads
follow the established input-read and hidden-input disciplines; a forward-vs-replay test
proves replay is unchanged.

In `src/Keiki/Core.hs`:

- Add a `TransducerValidationWarning` constructor `ProjectionResultUnsupported` carrying the
  `EdgeRef` and a detail string naming the dotted path and the result type. Emit it from a
  new unconditional check in `validateTransducer` (not behind an option — see Decision Log):
  walk every edge's guard (and, defensively, its update and output terms, since the type
  system cannot keep projections out of them) and for every `TFieldProj` at result type `r`,
  flag it when `discoverSym @r` (from `Keiki.Symbolic`) misses. If importing `discoverSym`
  into `Core.hs` creates a module cycle, invert the dependency: export a term-walking
  helper from `Core.hs` (e.g. `projResultTypes :: HsPred rs ci -> [SomeTypeRep]` walking
  with the `Typeable r` evidence the constructor carries) and run the registry check
  wherever `validateTransducer`'s symbolic-facing checks already live — follow how
  `symIsBot`-based checks are wired today and put the check at the same layer.
- Confirm (with tests, not new code, if Milestone 1 did its job) that: a guard using
  `inpProj … newDocCtor #doc` without the matching `PInCtor` guard trips the same
  guard-implies-input-read validation as a bare `TInpCtorField` read; and an output event
  that reads an input field *only* through a projection reports that field as a hidden
  input (`HirHeadUnrecoverable`/`HeadUnrecoverable`), i.e. the projected read counts,
  conservatively, as a read of the whole field.

Tests (in `test/Keiki/FieldProjSpec.hs` and/or `test/Keiki/ValidationSpec.hs`): build a
small two-state transducer fixture whose edges guard on `regProj`/`inpProj` comparisons
(follow the fixture style in `test/Keiki/Fixtures/`); assert `validateTransducer` under
`defaultValidationOptions` is clean; assert the `ProjectionResultUnsupported` case fires for
a witness whose result type is outside the registry (e.g. project a `[Int]` field); assert
`OpaqueGuard` (with `warnOpaqueGuards = True`) stays silent for projection guards and still
fires for `TApp1` guards; and prove replay unchanged — run the fixture forward over a
command sequence, `reconstitute` from the recorded events, and assert state equality
(follow the pattern of `test/Keiki/RoundTripSpec.hs` / `ReplayOnlySpec.hs`).

Acceptance: `cabal test all` green with the validator and replay tests included.

### Milestone 4 — laws, harness, and documentation

Scope: the witness laws are written where users will read them; a reusable law harness is
exported so Keiro's generated conformance tests can instantiate it; documentation
cross-references land.

- Haddocks on `FieldWitness`, `TFieldProj`, `regProj`, `inpProj` stating: the totality law
  (`fwGet` total on well-formed owners; partial projections are not expressible), the
  identity law (one `fwShapeId` per declared shape; two witnesses agreeing on shape id,
  owner type, and field name must denote the same projection — this is what makes memo
  sharing sound), the evaluation/translation agreement guarantee, and the provenance
  division verbatim in spirit: Keiki defines and tests the laws; truthfulness against the
  wire schema comes from the generator (Keiro) and its mutation-tested conformance harness.
- Export a law harness from `Keiki.Core` (or a small new module if `Core`'s export list is
  the wrong home — decide and record):

```haskell
-- | Does the witness's getter agree with a reference projection on this value?
-- Generators instantiate this over their own 'Gen owner' to prove a generated
-- witness right — and, mutated, to prove a wrong witness fails.
fieldWitnessAgrees :: (Eq r) => FieldWitness name owner r -> (owner -> r) -> owner -> Bool
fieldWitnessAgrees w ref o = fwGet w o == ref o
```

- Negative test: a QuickCheck property over `DocInfo` showing `fieldWitnessAgrees` with a
  deliberately wrong getter (`diHash . const someOtherDoc`, or a field swap) fails — proving
  the harness can catch a lying witness, which is the IR's "negative property harness"
  acceptance item.
- Documentation: add a short section to `docs/research/tinpproj-design.md` (or a new
  `docs/research/field-projection-design.md` if the addition doesn't fit — decide and
  record) describing `TFieldProj`, the base restriction, the memo key, and the guards-only
  contract. The IR file already carries `status: planned` and a `plan:` frontmatter pointer
  to this plan (added at planning time on 2026-07-28); at release (Milestone 5) advance it
  to `status: released` and append the change to `docs/improvement-requests/log.md`.

Acceptance: `cabal haddock` builds cleanly; `cabal test all` green including the negative
property.

### Milestone 5 — release

Scope: the capability is released and tagged so Keiro can pin it, per the IR's
Compatibility Baseline.

Follow `docs/research/release-procedure.md` end to end. Specifically: re-verify the
baseline first — check Hackage and `git tag` still say 0.3.1.0 is the latest release before
choosing bounds (the IR requires repeating this check at implementation time, not trusting
the 2026-07-28 snapshot); bump `keiki.cabal` to `0.4.0.0`; write the changelog entry naming
the new exports and the breaking `Term` constructor addition; run the full release test
matrix from the procedure doc; tag `v0.4.0.0`.

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
   `cabal haddock` renders `FieldWitness` docs stating totality, identity, and provenance.
2. Evaluation, translation, and predicate support with an agreement property
   (Milestones 1–2). Verify: the QuickCheck agreement property in the test suite passes.
3. Path-keyed memoization with a z3-backed validity proof (Milestone 2). Verify: the
   `symIsBot (proj /= proj)` example passes in `SymbolicSpec.hs`'s memoization block.
4. `OpaqueGuard` discrimination in both directions (Milestones 1 and 3). Verify: the
   two-direction tests pass.
5. Validator discipline and replay unchanged (Milestone 3). Verify: `PInCtor`,
   hidden-input, and forward-vs-replay tests pass; `ProjectionResultUnsupported` fires on
   the negative fixture.
6. Dotted-path diagnostics (Milestone 1). Verify: `prettyTerm` test asserts
   `doc.contentHash`.
7. Negative witness harness (Milestone 4). Verify: the wrong-getter property fails through
   `fieldWitnessAgrees` as asserted.
8. Released and tagged (Milestone 5). Verify: `git tag` shows `v0.4.0.0`.

Beyond compilation, the end-to-end demonstration is the Milestone 3 fixture: a transducer
whose edge guards compare projected fields, validated clean under default options, executed
forward, and replayed to the same state — something that before this plan required either
promoted scalar fields or an `OpaqueGuard`-tripping `TApp1`.


## Idempotence and Recovery

Every step is additive until Milestone 5. `cabal build`/`cabal test all` are safe to re-run
indefinitely. If a milestone is interrupted, the compiler's incomplete-pattern warnings
enumerate exactly which walkers still lack the `TFieldProj` case — re-running `cabal build`
recovers the worklist. Commits land only on green trees, so `git log` plus the Progress
checklist is sufficient to resume from any point; update Progress before stopping. The only
non-additive step is the release (version bump + tag): if a release attempt fails midway,
delete no published artifacts — fix forward with a new patch version per the release
procedure. Do not tag until the full test matrix passes.


## Interfaces and Dependencies

No new dependencies. The work uses the existing `sbv` (z3 backend), `hspec ^>=2.11`, and
`QuickCheck ^>=2.15` already in `keiki.cabal`; z3 must be on PATH for the symbolic tests,
as it already is for `test/Keiki/SymbolicSpec.hs`.

At the end of Milestone 1, `Keiki.Core` exports:

```haskell
data FieldWitness (name :: Symbol) owner r = FieldWitness
  { fwShapeId :: String, fwGet :: owner -> r }

data ProjBase (rs :: [Slot]) (ci :: Type) (ifs :: [Slot]) owner where
  PBReg :: Index rs owner -> ProjBase rs ci ifs owner
  PBInp :: InCtor ci ifs -> Index ifs owner -> ProjBase rs ci ifs owner

-- new Term constructor (via the existing Term(..) export)
TFieldProj ::
  (KnownSymbol name, Typeable owner, Typeable r) =>
  FieldWitness name owner r -> ProjBase rs ci ifs owner -> Term rs ci ifs r

regProj :: (KnownSymbol name, Typeable owner, Typeable r)
        => FieldWitness name owner r -> Index rs owner -> Term rs ci ifs r
inpProj :: (KnownSymbol name, Typeable owner, Typeable r)
        => FieldWitness name owner r -> InCtor ci ifs -> Index ifs owner
        -> Term rs ci ifs r
```

At the end of Milestone 3, `Keiki.Core` additionally exports the
`ProjectionResultUnsupported` constructor of `TransducerValidationWarning`. At the end of
Milestone 4, `fieldWitnessAgrees :: (Eq r) => FieldWitness name owner r -> (owner -> r) ->
owner -> Bool` is exported for downstream conformance harnesses. `Keiki.Symbolic` gains no
new exports (the `projKey` helper may stay internal), but its `translateTermSym` accepts
the new constructor with only the existing `Sym r` constraint — the `owner` type never
requires a `Sym` instance.


## Revision Notes

- 2026-07-28: At the user's request, the IR file
  (`docs/improvement-requests/support-typed-symbolic-field-projections-over-mapped-consumer-values.md`)
  was cross-linked to this plan at planning time rather than waiting for Milestone 4: its
  frontmatter gained `plan:` pointing here, its `status:` moved `proposed` → `planned`, and
  `docs/improvement-requests/log.md` records the change. Milestone 4 and the Progress
  checklist were updated accordingly; the remaining IR obligation is the `status: released`
  advance in Milestone 5.
