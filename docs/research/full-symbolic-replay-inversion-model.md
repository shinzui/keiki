# Full symbolic replay-inversion model research

This report asks whether Keiki can soundly prove that two replay edges cannot both accept one
observed head event by modeling their complete inversion relation. It records the concrete runtime
semantics, the evidence present in today's public types, executable prototypes, downstream and
compatibility evidence, measurements, and the final promotion decision. The work is research:
`inversionAmbiguityWarnings`, default validation, runtime replay, and the public API are unchanged.

The governing plan is
[`docs/plans/86-research-a-full-symbolic-replay-inversion-model.md`](../plans/86-research-a-full-symbolic-replay-inversion-model.md).
Plan 85 is the narrower shared-register analysis in
[`docs/plans/85-prove-replay-inverse-candidates-disjoint-from-shared-register-conjuncts.md`](../plans/85-prove-replay-inverse-candidates-disjoint-from-shared-register-conjuncts.md).


## Executive conclusion

The decision and measured evidence are filled after the prototype milestones. The three allowed
outcomes are `Proceed`, `Proceed after structural wire-schema prerequisite`, and `Do not proceed`.
Until then, no prototype result is production authority.


## Concrete replay relation

At a settled vertex, `applyEventKernel` in `src/Keiki/Core.hs` examines live edges first. It
examines replay-only edges only when the live candidate set is empty. Ambiguity is therefore
judged within one phase, never between a live edge and a replay-only edge.

For an edge `e`, pre-event register file `r`, and observed event `o`, candidacy is:

```text
Candidate(e, r, o) =
  there exists c such that
    solveOutput(head(e), r, o) = Just c
    and evalPred(guard(e), r, c) = True
```

Two same-phase edges are ambiguous exactly when both candidate relations hold for the same `r`
and `o`. Their reconstructed commands are independent values: `applyEventKernel` calls
`solveOutput` once per edge and evaluates each edge's guard on that edge's result. Reusing one
symbolic command constructor or one input-field cache would answer a different question and can
manufacture false unsatisfiability when the edges reconstruct different constructors.

Only the first output term is inverted. After one head chooses an edge, a multi-event tail is
evaluated forward and checked sequentially by the `InFlight` replay state. A tail may reject a
chosen edge later, but it never distinguishes candidates at the head.


## What `solveOutput` actually constrains

The only `OutTerm` constructor is `OPack inCtor wireCtor outFields`. `WireCtor.wcMatch` first
projects the observed event into the existential nested-pair field tuple. `gatherInpEntries` walks
that tuple and `OutFields` together. A top-level `TInpCtorField` contributes its observed value to
command assembly; literals, register reads, and derived expressions contribute no command field.
Assembly succeeds only if every field in the `InCtor` schema was recovered exactly once.

After assembly, `icBuild` constructs the candidate command. `recomputeDerivedFields` then
re-evaluates `TApp1`, `TApp2`, `TArith`, and `TFieldProj` fields from the candidate and the
pre-event registers. `wcBuild` rebuilds the event and concrete `Eq co` must agree with the original
observation. In contrast, `TLit`, `TOpaqueLit`, `TReg`, and `TInpCtorField` retain their observed
values during this comparison.

That last distinction is load-bearing. In particular, a `TReg` output field is an audit value in
the observed event; runtime does not equate it with the current register file. A symbolic model
that adds `observedField == currentRegister` would be stronger than runtime and could suppress a
real ambiguity with a false UNSAT result.


## Soundness polarity

The safe proof uses an over-approximation. Every concrete pair of candidates must map to a model
of the symbolic formula, but the formula may contain extra models. Definite SBV `Unsatisfiable`
then proves the concrete pair impossible. Satisfiable, `Unknown`, `ProofError`, `DeltaSat`, solver
startup failure, an unsupported carrier, an opaque relation, or missing structural evidence all
mean only “not proved disjoint.”

This is the same polarity required by
[`docs/adr/0003-proof-gates-fail-conservatively.md`](../adr/0003-proof-gates-fail-conservatively.md).
Finite enumeration checks the prototype, but cannot replace the one-way simulation argument.


## Capability matrix

“Exact” means the current AST and symbolic carrier represent the concrete relation without adding
models, subject to the existing `InCtor` and projection declaration laws. “Over-approximate” means
unsupported relationships are widened while preserving every concrete case. “No alignment” means
the expression can be translated within one guard, but today's public wire evidence cannot safely
connect two edges through one observed event.

### Terms

| `Term` form | Current guard translation | Full inversion use | Safe failure direction |
| --- | --- | --- | --- |
| `TLit` | Exact for a supported, exactly encoded `Sym` carrier. | Its output position retains the observed value; it is not verified against the literal. | Leave the observed field unconstrained if the carrier or shared field is unsupported. |
| `TOpaqueLit` | Same solver meaning as `TLit`; only rendering is opaque. | Same runtime behavior as `TLit`. | Widen as for `TLit`; display opacity is not semantic opacity. |
| `TReg` | Exact scalar read for a supported carrier within one environment. | Guard reads must share one register variable across candidates. An output `TReg` is an observed audit value and must not equal the current register. | Preserve the guard relationship; drop the output-to-register equality. |
| `TInpCtorField` | Exact scalar read within one candidate scope when the carrier is supported. | Top-level output occurrences assemble that candidate's command from the observed field. Candidate A and B require different input caches and constructor tags. | Keep candidate fields independent unless one structural observed-field witness relates them. |
| `TApp1` | Fresh per-occurrence symbolic result. | Runtime recomputes and verifies it after command recovery, but its Haskell function is opaque. | Drop the verification relation and mark the candidate translation conservative. |
| `TApp2` | Fresh per-occurrence symbolic result. | Same as `TApp1`. | Drop the verification relation and mark conservative. |
| `TArith` | Exact for registered symbolic numeric carriers, including total monus for `Natural`; otherwise fresh. | Runtime recomputes and verifies it. It can be related to the observed field only after structural field alignment. | Drop the derived equality on an unsupported carrier. |
| `TFieldProj` | One path-identified scalar. A one-way witness is an over-approximation; an exact domain constrains the scalar but does not generally reconstruct all owner relations. | Runtime recomputes and verifies the projection. Current evidence does not expose a cross-edge wire field or a general base-owner relation. | Drop the derived equality unless all path, carrier, domain, and observed-field evidence is exact. |

The existing `SymEnv` memoizes ordinary register and input reads using diagnostic names. A
candidate-pair model needs stronger keys: register position plus type for the shared register
cache, and candidate scope plus constructor identity, field position, and type for input caches.
Duplicate labels must never merge structural positions.

### Predicates

| `HsPred` form | Candidate-scoped classification | Notes |
| --- | --- | --- |
| `PTop`, `PBot` | Exact | Tautology and contradiction. |
| `PAnd`, `POr`, `PNot` | Exact Boolean structure over translated children | A widened child stays a sound over-approximation because its fresh value admits every concrete child value. |
| `PEq` | Exact when both term translations and their carrier are exact; otherwise over-approximate | An unsupported carrier becomes a fresh Boolean atom. |
| `PInCtor` | Exact only inside its candidate command scope, conditional on the existing `InCtor` honesty law | Candidate A and B must not share the tag. Names are diagnostics, not cross-edge type evidence. |
| `PLeftArm`, `PRightArm` | Exact inside one candidate scope | Each candidate needs its own outer-arm discriminator. |
| `PCmp` | Exact when both term translations and the ordered carrier are exact; otherwise over-approximate | All four comparison directions preserve the same classification. |


## Evidence inventory

`InCtor ci ifs` carries a real type-level input-field schema, `icMatch`, `icBuild`, and automatic
assembly and slot-name dictionaries. Within one `OPack`, the shared `ifs` parameter proves that a
top-level `TInpCtorField` index is valid for the command being assembled. `icName` remains a
diagnostic string and the matcher and builder remain consumer-owned closures.

`WireCtor co fields` carries `wcName`, `co -> Maybe fields`, and `fields -> co`. The existential
`fields` type is useful within one edge, but two separately unpacked edges do not expose evidence
that their field tuples are the same type or that their matchers select the same projection of
`co`. Equal `wcName` values are part of an honesty law used by conservative validation, not a
safe cast or a shared-field witness.

`OutFields rs ci ifs fields` preserves field order and term result types, and ties command
projections to one `InCtor`. It does not preserve selector names and does not identify a field of
one edge with a field of another edge after both `OPack` existentials are opened.

`HsPred` retains Boolean structure, input constructors and arms, equality/ordering carrier
`Typeable` evidence, and the complete term AST. It is sufficient for a candidate-scoped guard
formula once variable ownership is split correctly.

`SymEnv` currently owns one input tag, one outer-arm bit, and one variable cache. It is correct for
one predicate translation. It is not a candidate-pair environment because sharing it would merge
commands, while creating two independent environments would also duplicate registers.

`PredicateVerificationDetail` demonstrates the desired optional-API shape: one solver run retains
translation strength, exact result classification, checked projection models, and explicit
unknown/failure cases. A future inversion API should follow that detailed-first pattern, with a
conservative projection to the existing warning.


## Structural wire evidence designs

The prototype evaluates three designs rather than choosing by taste.

1. Add a structural field-schema descriptor to `WireCtor`. It would identify every field by
   position, result type, and symbolic dictionary, and would carry a constructor identity that is
   distinct from `wcName`. This directly supports safe pairwise alignment, but changing the
   `WireCtor` record constructor is source-breaking for manual users and propagates through
   Builder, Generics, TH, composition, and profunctor code.
2. Derive a canonical descriptor alongside `WireCtor`. `FieldsOf` and `deriveWireCtorsAll` already
   know the ordered payload types, and TH also sees selector names. A generated descriptor can be
   accurate without interpreting the runtime closures. Manual `WireCtor` users still need an
   explicit descriptor or must remain unsupported, and generated declaration/source surfaces grow.
3. Keep public types unchanged and inspect only the two `OutFields`. This can classify the terms
   at matching list positions, but it cannot prove that two opaque `wcMatch` closures expose the
   same event constructor, the same field order, or even the same existential tuple type. It has
   no sound way to share observed values and therefore offers no event-dependent precision beyond
   guard/register-only analysis.

The executable prototype implements only the central feasibility claim of design 1: a small
typed descriptor permits shared observed-field constraints. Design 2 is assessed from the actual
Generics/TH generation path. Design 3 is falsified by same-name/different-schema and dishonest
matcher controls; no cast or name-based shortcut is attempted.


## Dependency and release baseline

The dependency was discovered through Mori before source inspection:
`mori://LeventErkok/sbv/packages/sbv` resolves to the registered source project
`/Users/shinzui/Keikaku/hub/haskell/sbv-project/sbv`; Mori has no curated SBV documents.

On 2026-08-04, Hackage's authoritative preferred-version endpoint and latest Cabal file reported
SBV 14.5. Upstream `git ls-remote --tags --refs --sort=-v:refname` reported `v14.5` at
`26d4990a27d2340799112a8f48b1a94b174e814e`. Keiki's resolved Cabal plan also uses 14.5 and its
existing bounds are `sbv >=11.7 && <15`; this research changes neither bound.

The local Mori corpus is ahead of the release: its `master` at
`62aa7532f714368696456e50026581cdf611721f` declares version 14.6 and has no matching release tag.
It is useful for source orientation, not evidence of a released API. The prototype therefore uses
only APIs already compiled by Keiki against 14.5: typed `free`, `constrain`, `sat`, `SatResult`,
and the explicit `SMTResult` constructors.


## Reverse-dependent audit

`mori registry dependents shinzui/keiki --packages --json` reported twelve registered projects:
Danwa, Kawa, Keiro, Keiro Runtime Docs, Keiro Runtime Jitsurei, Keiro Runtime Patterns, Kikan,
Kioku, Kizashi, Kotei, Meibo, and Shikigami. Several registry entries currently describe only a
project-level dependency, so “package-level” output cannot by itself name the affected package.

Source inspection at the registered paths found extensive `deriveWireCtorsAll` and `B.emit` use in
generated and hand-owned aggregates. Examples include the two packages under
`mori://shinzui/keiro-runtime-jitsurei` (artifact-level source URI pending; see
`services/hospital-capacity/src/HospitalCapacity/Capacity/Transducer.hs`),
`mori://shinzui/danwa` (artifact-level source URI pending; see
`danwa-core/src/Danwa/Conversation/Holes.hs`), and `mori://shinzui/kotei` (artifact-level source
URI pending; see `kotei-core/src/Kotei/Run/Holes.hs`). These are real migration surfaces for a
`WireCtor` or TH change and evidence that a generated schema facility would be reusable.

The audited sources contain repeated wire constructors across different vertices, but no
confirmed same-source, same-phase, same-head pair whose false positive requires the observed-field
relation rather than register-only reasoning. The only concrete motivating case currently remains
`mori://shinzui/mori/plans/176-rewrite-the-workflow-aggregate-with-real-step-completion-and-causation`.
Absence from this bounded audit is not proof no consumer has such a pair, but it prevents a
`Proceed` decision from claiming an evidenced broad downstream precision win.


## Applicable architecture decisions

[`docs/adr/0001-structural-re-indexing-for-sound-replay.md`](../adr/0001-structural-re-indexing-for-sound-replay.md)
forbids name-based casts at replay boundaries. Any shared-event relation must use structural type
evidence and must not introduce `unsafeCoerce`.

[`docs/adr/0002-event-logs-must-reproduce-forward-state.md`](../adr/0002-event-logs-must-reproduce-forward-state.md)
makes unique head attribution part of default-validation correctness and confirms that tails only
complete an attribution selected by the head.

[`docs/adr/0003-proof-gates-fail-conservatively.md`](../adr/0003-proof-gates-fail-conservatively.md)
allows suppression only after definite UNSAT over a sound encoding and requires unknown,
unsupported, or solver-failure cases to retain warnings.

[`docs/adr/0005-persisted-wire-identities-are-explicit-and-versioned.md`](../adr/0005-persisted-wire-identities-are-explicit-and-versioned.md)
separates stable wire identity from Haskell names. A future schema identity must compose with that
boundary instead of treating declaration names as persisted or type-safe identity.


## Reproducible baseline

The plan's combined Hspec alternation is not supported by the active substring matcher and
selected zero examples. Running stable substrings sequentially produced:

```text
satResultIsProvablyUnsat: 3 examples, 0 failures
ambiguity:                 5 examples, 0 failures
EP-47:                     9 examples, 0 failures
```

Parallel Cabal test processes raced on `dist-newstyle` package-cache files, so all subsequent
prototype and gate commands are intentionally sequential. This is a build-tool reproducibility
constraint, not a Keiki semantic failure.


## Prototype results

The unsupported test-only prototype lives in `test/Keiki/InversionModelResearchSpec.hs` while the
experiment is active. It defines a `DualCandidateEnv` with two register variables shared by both
candidates and two `CandidateVars` records. Each candidate record owns its constructor tag, outer
`Either` arm, two input fields, and an opaque atom. Every SBV label is prefixed by ownership and
structural position; the two register variables deliberately share a human diagnostic suffix but
remain distinct positions.

The focused command is:

```bash
nix develop -c cabal test keiki-test \
  --test-options='--match=replay-inversion' \
  --test-show-details=direct
```

It passed 14 examples with zero failures in 0.1092 seconds of Hspec-reported example time. Solver
process startup is included in the wall-clock command but not in that Hspec summary.

### Dual-command result

The correct separate-command formula constrains candidate A's constructor tag to `0` and candidate
B's tag to `1`; z3 reports SAT. The negative control uses one shared tag and reports UNSAT for
`tag == 0 && tag == 1`. The negative result is precisely the false disjointness proof a direct
reuse of today's single `SymEnv` could manufacture.

The shared-register fixture asks both candidate guards about the same scalar and proves
`register < 0 && register >= 0` UNSAT. Enumeration over `[-3..3]` finds no concrete overlap.
Same-constructor fields remain candidate-local, so A can satisfy `(a1 = a0 + 1, a0 = 3)` while B
satisfies `(b1 = b0 + 1, b0 = 9)`. Separate outer arms and opaque occurrences are SAT, and two
register positions carrying the same diagnostic label remain distinct and SAT at values `0` and
`1`. Constructed `Unknown` and `ProofError` results both classify as inconclusive through
`satResultIsProvablyUnsat`.

### Shared observed-head result

A generated/validated structural descriptor with one integer field permits one shared observed
variable. Candidate A and B each reconstruct their own command field from that variable. Guards
`a.value == 0` and `b.value == 1` make the conjunction UNSAT; guards `a.value == 0` and
`b.value == 0` are SAT.

The same shape is also built with real `Keiki.Core` values: two `InCtor` values, one `WireCtor`,
two `OPack` heads, and input-field-only guards. Current `inversionAmbiguityWarnings` retains a
warning because the head names match. A Plan-85-style register-only extraction must also retain it
because neither guard contains a register conjunct. Concrete `solveOutput` candidacy over observed
integers `[-3..3]` finds at most one candidate for the disjoint pair and exactly two candidates at
observed `0` for the overlapping control.

This is the required precision win in the hypothetical structurally witnessed fragment: the
proof depends on both inversions sharing the same observed event field and cannot be obtained by
sharing registers alone.

### Unsupported and runtime-specific cases

Two descriptors with equal `schemaDiagnosticName` but integer versus Boolean field carriers do not
align. A descriptor marked dishonest or manual-but-unvalidated does not align. These controls
represent the missing law evidence behind today's opaque `wcMatch`/`wcBuild` closures; the
prototype never casts their existential tuples.

Top-level command fields contribute equality with the shared observation. Exact arithmetic and a
fully witnessed structural projection may contribute a derived equality. Opaque `TApp` and an
unconstrained projection drop that equality and mark the translation conservative. `TReg` audit
fields and output literals leave the observation unconstrained because that is exactly what
`solveOutput` does: neither is recomputed during its final event equality check. “Supporting an
exact literal” therefore means representing this exact absence of a literal constraint, not
adding `observed == literal`.

The multi-event control adds no tail constraint and remains SAT. This matches runtime order:
head inversion selects an edge before `InFlight` compares its evaluated tail.


## Adversarial and performance results

To be completed by Milestone 4.


## API and PVP assessment

To be completed by Milestone 4.


## Final decision and bounded next action

To be completed by Milestone 5 with exactly one allowed decision label.
