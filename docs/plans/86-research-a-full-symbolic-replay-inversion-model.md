---
id: 86
slug: research-a-full-symbolic-replay-inversion-model
title: "Research a full symbolic replay-inversion model"
kind: exec-plan
created_at: 2026-08-04T17:28:38Z
intention: intention_01kz6xycp7ebttv8tj6w4kz77n
---

# Research a full symbolic replay-inversion model

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

This plan determines whether Keiki should eventually model the complete symbolic relation between
one observed head event and two independently reconstructed replay commands. At completion, the
repository will contain an evidence-backed research report, reproducible solver prototypes, a
measured maintenance and compatibility assessment, and a clear decision: proceed, proceed only
after a named structural-schema prerequisite, or do not proceed.

The research must demonstrate value beyond the pure shared-register proof delivered by
[Plan 85](85-prove-replay-inverse-candidates-disjoint-from-shared-register-conjuncts.md). A
successful prototype must prove at least one genuinely output-dependent candidate pair disjoint
that Plan 85 must conservatively warn about, while exhaustive concrete evaluation over the same
finite fixture finds no ambiguous candidate. It must also retain warnings for solver uncertainty,
opaque Haskell functions, or unrepresented wire relationships. Merely translating both guards
with one symbolic command is not success because runtime replay reconstructs a separate command
for each edge.

This is a research plan, not authorization to change default validation or publish a public API.
The main deliverable is `docs/research/full-symbolic-replay-inversion-model.md`. Production work,
if justified, requires a subsequent ExecPlan based on the selected design and migration surface.


## Progress

- [x] (2026-08-04T17:44:15Z) Created and attached active intention
      `intention_01kz6xycp7ebttv8tj6w4kz77n`; completed the ExecPlan/ADR preflight and confirmed a
      clean starting worktree.
- [x] (2026-08-04T17:51:31Z) Milestone 1: formalized concrete replay candidacy, inventoried
      current symbolic and structural evidence, verified the released SBV and reverse-dependency
      baselines, and published the capability matrix in
      `docs/research/full-symbolic-replay-inversion-model.md`. Sequential focused baselines passed
      with 3, 5, and 9 examples respectively and zero failures.
- [x] (2026-08-04T17:59:16Z) Milestone 2: added an unsupported test-only dual-candidate SBV
      environment with shared structural register variables, candidate-scoped constructors,
      fields, arms, and opaque atoms. The separate-command and finite concrete controls pass; the
      intentionally wrong single-command control demonstrates false UNSAT.
- [x] (2026-08-04T17:59:16Z) Milestone 3: added a typed one-field observed-head descriptor,
      output-dependent disjoint and overlapping fixtures, real `solveOutput` candidate
      enumeration, and fail-conservative mismatched-schema, dishonest-descriptor, derived,
      projection, register-audit, and multi-event controls. The focused suite passes 14 examples.
- [x] (2026-08-04T18:05:49Z) Milestone 4 measurement and audit: ran adversarial classification,
      inspected generated SMT variable ownership, measured five samples at 1, 10, 50, and 100
      pairs against `checkTransitionDeterminismSymDetailed`, and completed the source/PVP audit.
      The 100-pair full-model median was 894.728 ms versus 864.075 ms guard-only (about 1.04x).
- [ ] Milestone 4 remaining: checkpoint the reproducible measurement prototype, then remove its
      test module and registrations because the selected structural-prerequisite result does not
      leave a reusable internal production foundation.
- [ ] Milestone 5: finish the research report, record a go/no-go/prerequisite decision, distill
      durable conclusions into the relevant ADRs, and validate all surviving repository changes.


## Surprises & Discoveries

- The plan's combined Hspec `--match` alternation selected zero examples in the active Hspec
  version. Stable substrings run sequentially selected 3 `satResultIsProvablyUnsat`, 5 ambiguity,
  and 9 EP-47 examples, all passing.
  Evidence: focused test transcripts recorded in
  `docs/research/full-symbolic-replay-inversion-model.md`.

- Concurrent Cabal test invocations race on the shared `dist-newstyle` package cache and produced
  missing cache/lock-file errors. This is a command-reproducibility constraint, not a semantic
  failure; every subsequent Cabal command must run sequentially.
  Evidence: the failed parallel baseline named `package.cache` and `package.cache.lock` paths,
  while the same tests passed sequentially.

- Mori's local SBV corpus is on an unreleased 14.6 `master`, while Hackage, upstream tags, and
  Keiki's resolved build agree on released 14.5. The corpus remains useful for source discovery
  but cannot justify a released-version compatibility claim by itself.
  Evidence: corpus commit `62aa7532f714368696456e50026581cdf611721f` declares 14.6; Hackage and
  tag `v14.5` identify the current release, and `dist-newstyle/cache/plan.json` resolves 14.5.

- Mori's `--packages --json` reverse-dependent query currently returned project-level entries
  with null package fields. The bounded source audit found extensive generated wire-schema use but
  no confirmed non-Mori same-source/same-head output-dependent false positive.
  Evidence: the audit and canonical project references are recorded in the research report.


## Decision Log

- Decision: Treat the full problem as a relation over one register file, one observed event, and
  two independently scoped commands.
  Rationale: Runtime `applyEventKernel` calls `solveOutput` separately for each edge and evaluates
  each guard on its own reconstructed command. Reusing one input-constructor tag or one input-field
  variable cache would incorrectly make different command constructors mutually exclusive and
  could manufacture a false proof.
  Date: 2026-08-04

- Decision: Require an output-dependent precision win over Plan 85 before recommending production
  implementation.
  Rationale: A full inversion model has substantially higher maintenance cost. If its only useful
  proof is shared-register disjointness, the smaller pure implementation already owns that case
  without solver, schema, or API complexity.
  Date: 2026-08-04

- Decision: Keep all solver prototypes test-only and non-public until the final research decision.
  Rationale: Research must not accidentally create a supported API, change default warning output,
  or force downstream migration before feasibility, proof polarity, and performance are known.
  Date: 2026-08-04

- Decision: Evaluate conservative over-approximation as a valid implementation technique, but call
  it a full candidate model only when the shared-event relation is represented.
  Rationale: Dropping unsupported constraints is sound for proving unsatisfiability, yet treating
  the two edges' observed fields as independent collapses the model back to guard-only reasoning.
  The research must state exactly which replay constraints are shared and which are widened.
  Date: 2026-08-04

- Decision: Prototype shared observed fields only behind a small typed structural descriptor and
  use adversarial controls to falsify the public-types-unchanged alternative.
  Rationale: Equal `wcName` values and two independently unpacked `OutFields` do not prove that
  opaque matchers expose the same field tuple. The typed descriptor tests feasibility without
  changing `WireCtor` or relying on a cast during research.
  Date: 2026-08-04

- Decision: Run all Cabal build and test commands sequentially for this plan.
  Rationale: Parallel invocations mutated the same `dist-newstyle` cache and produced spurious
  missing-file failures, obscuring the semantic evidence.
  Date: 2026-08-04

- Decision: Model literal and `TReg` output fields as exact absence of a verification constraint.
  Rationale: `solveOutput` retains their observed values when rebuilding the event. Equating a
  literal output to its term literal or a register output to the current register would be stricter
  than runtime and could manufacture false UNSAT.
  Date: 2026-08-04

- Decision: Select `Proceed after structural wire-schema prerequisite` for the final report.
  Rationale: A typed descriptor produces the required output-dependent precision with acceptable
  measured cost, but current `WireCtor` closures and `OutFields` existentials cannot safely align
  observed fields across edges. Equal names and casts are rejected, and the bounded consumer audit
  found no broader real false-positive set that would justify bypassing the prerequisite.
  Date: 2026-08-04

- Decision: Remove the research test module after checkpointing its measurement evidence.
  Rationale: The module duplicates a hypothetical descriptor and solver driver rather than forming
  a reusable internal boundary against today's public types. Its ongoing maintenance cost is not
  justified before the structural prerequisite exists; the report and Git history preserve the
  experiment.
  Date: 2026-08-04


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

The runtime authority is `applyEventKernel` in `src/Keiki/Core.hs`. At a settled vertex it selects
live candidates first and consults replay-only candidates only when the live set is empty. Within
the chosen phase, edge `e` is a candidate for pre-event registers `r` and observed event `o` when:

```text
Candidate(e, r, o) =
  there exists c such that
    solveOutput(head(e), r, o) = Just c
    and evalPred(guard(e), r, c) = True
```

Two edges are replay-ambiguous exactly when both candidate relations hold for the same `r` and
`o`. The commands produced by their two `solveOutput` calls may be different constructors of the
same `ci` sum type. Multi-event tails are not inversion keys: after a head selects an edge, replay
evaluates that edge's tail forward and later equality-checks it.

`solveOutput` in `src/Keiki/Core.hs` operates on `OutTerm rs ci co`. The only `OutTerm` constructor
is `OPack`, which combines an `InCtor ci ifs`, a `WireCtor co fields`, and a typed `OutFields` list.
Top-level `TInpCtorField` terms recover command fields. Literal and register fields do not recover
command data. Derived `TArith`, `TApp1`, `TApp2`, and `TFieldProj` fields are recomputed after
command reconstruction, and the rebuilt event is compared with the observed `co` using its
concrete `Eq` instance. A `TReg` output is deliberately not rechecked against the current register
file; it keeps the observed field value. Any model that constrains such a field equal to the
register would be stricter than runtime and could produce an unsound false UNSAT.

`WireCtor` is currently a record of three values: a diagnostic `wcName`, an opaque Haskell
matcher `co -> Maybe fields`, and an opaque builder `fields -> co`. Equal `wcName` strings are an
honesty-law assumption used by validation, not type evidence that two `fields` tuples have the
same Haskell type or that the two matchers expose the same projection of `co`. `InCtor` has the
same distinction: its structural `ifs` type is real evidence within one `OPack`, while `icName` and
the matcher/builder functions remain consumer-supplied. A full shared-event encoding must confront
this evidence gap rather than cast existential field tuples by name.

The existing SBV translation is in `src/Keiki/Symbolic.hs`; public function-free result metadata
lives in `src/Keiki/Internal/SymbolicTypes.hs`. `SymEnv` currently allocates one symbolic input
constructor tag, one outer `Either` arm, and one variable cache. Repeated register and input reads
share variables inside one guard translation. Two candidate guards cannot simply share the entire
environment: registers must be shared, while constructor tags and input-field variables must be
separately scoped to candidate A and candidate B. Projection variables additionally carry
path-local identity and exactness rules established by Plans 79, 82, and 83.

The solver dependency is SBV, registered as `mori://LeventErkok/sbv/packages/sbv`. The Mori corpus
is located with `mori registry show LeventErkok/sbv --full`; it has no curated docs, so relevant
source must be read directly from that registered project. `Data.SBV` provides typed free
variables, constraints, satisfiability results, and uninterpreted values/functions. SBV also has
symbolic algebraic data-type support, but that does not automatically make arbitrary consumer
`ci` and `co` values symbolic: Keiki would still need structural type evidence and a translation
contract. Before relying on an SBV API or choosing a compatibility bound, compare the corpus with
Hackage preferred versions and upstream release tags as required by the repository instructions.
Do not search `/nix/store` or `/`.

`inversionAmbiguityWarnings` in `src/Keiki/Core.hs` is intentionally pure and has no `Eq co`,
symbolic-carrier, or solver constraint. `checkTransitionDeterminismSymDetailed` in
`src/Keiki/Symbolic.hs` demonstrates the optional solver-backed pattern: return detailed status and
translation strength, then project a conservative compatibility warning. Research must assess an
analogous optional inversion API before considering any default-path integration.

Use `test/Keiki/ValidationReplayAlignmentSpec.hs`, `test/Keiki/RecomputeVerifySpec.hs`,
`test/Keiki/ReplayOnlySpec.hs`, `test/Keiki/FieldProjSpec.hs`, and
`test/Keiki/SymbolicSpec.hs` as semantic fixtures. If executable prototype code is needed, create
`test/Keiki/InversionModelResearchSpec.hs`, register it in `keiki.cabal` and `test/Spec.hs`, and
label the module test-only and unsupported. It must not be exposed by the library.

The cross-repository motivating plan is
`mori://shinzui/mori/plans/176-rewrite-the-workflow-aggregate-with-real-step-completion-and-causation`.
Plan 85 handles its shared-register split. This research therefore needs additional real shapes
from registered reverse dependents, discovered with
`mori registry dependents shinzui/keiki --packages`, rather than assuming the Mori case alone
justifies a full event relation.

Four accepted local ADRs apply.
[ADR-0001](../adr/0001-structural-re-indexing-for-sound-replay.md) forbids name-based casts at the
replay boundary. [ADR-0002](../adr/0002-event-logs-must-reproduce-forward-state.md) makes candidate
uniqueness part of default-validation correctness.
[ADR-0003](../adr/0003-proof-gates-fail-conservatively.md) permits a disjointness blessing only
after definite UNSAT and records symbolic encoding gaps.
[ADR-0005](../adr/0005-persisted-wire-identities-are-explicit-and-versioned.md) separates stable
wire identity from Haskell declaration names. Summarize these constraints in the research report;
update the existing ADRs or create one profiled ADR at the end only if the final decision adds
durable context not already represented.


## Plan of Work

Milestone 1 creates `docs/research/full-symbolic-replay-inversion-model.md` and establishes the
baseline before writing prototype code. Write the concrete candidate equation above, the live-first
phase rule, and a constraint-by-constraint account of `solveOutput`, including command-field
assembly, derived-field recomputation, concrete event equality, unverified `TReg` fields, and
head-only inversion. Add a capability matrix for every `Term` constructor and guard form. For each
row state whether the current AST provides exact symbolic evidence, a sound over-approximation, or
no usable relationship, and explain the safe failure direction.

In the same report, inventory the API evidence carried by `InCtor`, `WireCtor`, `OutFields`,
`HsPred`, `SymEnv`, and `PredicateVerificationDetail`. Run Mori dependency discovery before reading
SBV source, then verify current Hackage/upstream versions before citing APIs or proposing bounds.
Audit registered Keiki reverse dependents for actual same-head false positives that cannot be
resolved by Plan 85. Record exact canonical `mori://` references when an artifact handle exists;
otherwise use the canonical project URI plus project-relative path and explicitly say the
artifact-level URI is pending. Milestone 1 is complete when another contributor can identify every
proof obligation and evidence gap from the report alone.

Milestone 2 tests the dual-command requirement independently of output modeling. In a test-only
prototype, split the current symbolic environment conceptually into one shared register cache and
two candidate scopes. A candidate scope has its own input-constructor tag, outer-arm discriminator,
input-field cache, opaque-application occurrences, and candidate-prefixed model labels. Register
reads at the same structural position and type resolve to the same SBV variable in both scopes.
Input reads resolve to different variables even when their diagnostic constructor and field names
match.

Do not immediately refactor production `SymEnv`. First write the smallest local prototype capable
of translating two fixture guards. Compare its solver verdict with exhaustive concrete evaluation
over finite register and command domains. Required controls include different command constructors
that are both eligible, the same command constructor with correlated fields, distinct `Either`
arms, opaque atoms, duplicate diagnostic labels at different positions, and a solver
`Unknown`/`ProofError` verdict passed through `satResultIsProvablyUnsat`. The current single-command
translation should be included as a negative control showing why it answers the wrong question.
Milestone 2 passes only if separate commands and shared registers agree with concrete semantics and
no inconclusive solver result becomes a disjointness proof.

Milestone 3 adds the shared observed-head relation for a deliberately small structural fragment.
Prototype an abstract observed field tuple only when the two heads can supply sound structural
alignment evidence. Support top-level command-field projections and exact literals first. Treat
register output fields according to runtime: their observed values are shared event values but are
not equated with current registers. Derived fields are supported only when their concrete and
symbolic semantics are represented exactly; otherwise drop their verification constraint and mark
the translation conservative. Never interpret equal `wcName` strings as a type equality, use
`unsafeCoerce`, or assume two opaque `wcMatch` functions expose equivalent fields.

The prototype must examine and document three possible evidence designs. The first augments
`WireCtor` with a structural field-schema descriptor carrying position, type, and symbolic
dictionaries. The second derives a canonical wire-constructor descriptor alongside `WireCtor`
through Keiki Generics/TH while preserving the closures for runtime. The third keeps the public
types unchanged and models only relationships provable from the two `OutFields`; if this cannot
share observed fields safely, record that it offers no precision beyond Plan 85. Implement only
enough of each design to falsify or support its central feasibility claim. Do not pick a design by
aesthetic preference.

Required Milestone 3 fixtures include an output-dependent disjoint pair that Plan 85 warns about
and an overlapping control. For example, two commands may reconstruct values from one shared event
field and then impose incompatible input-field constraints, while their register guards remain
unconstrained. The solver must prove the first candidate conjunction UNSAT and find the second SAT;
bounded concrete enumeration must agree. Also test mismatched existential field types under the
same `wcName`, dishonest/misaligned wire descriptors, derived `TApp`, exact and unconstrained field
projections, a `TReg` audit field, and a multi-event edge whose tail would distinguish edges but
whose head would not. All unsupported cases remain not-proved.

Milestone 4 measures whether the additional precision is maintainable. Record solver query size,
wall time, and result classification for representative vertices with 1, 10, 50, and 100
same-head pairs. Compare the optional full-model prototype with
`checkTransitionDeterminismSymDetailed` on guards of comparable complexity and with the pure Plan
85 analysis. Timing assertions must not enter the permanent test suite; record the machine,
solver, sample count, median, and worst observed values in the report. Inspect generated SMT-LIB
or SBV debug output for accidental variable independence or duplicated constraints.

Audit source compatibility and PVP impact for every viable design. Specifically record whether it
changes the `WireCtor`, `InCtor`, `Term`, `OutFields`, Builder, Generics/TH, composition,
profunctor, or generated downstream surfaces; whether it adds `Eq co`, `Typeable`, `Sym`, or
schema-witness constraints; and whether it changes default validation performance or z3
availability requirements. Use Mori's package-level reverse-dependency output to identify affected
projects. No compatibility claim may rely solely on Keiki's in-tree fixtures.

At the end of Milestone 4, remove `test/Keiki/InversionModelResearchSpec.hs` and its registrations
if the chosen result is “do not proceed” or “structural prerequisite required” and the prototype
does not provide a reusable internal foundation. Preserve concise source excerpts, commands, and
test transcripts in the report so the experiment remains reproducible from version history. Keep
the module only if it is small, green, documents a reusable boundary, and the report explicitly
accepts its ongoing test maintenance cost. Never expose it from the library merely to preserve the
prototype.

Milestone 5 applies the promotion criteria and writes one of three unambiguous conclusions in the
report:

1. `Proceed`: the model has a sound shared-event over-approximation, proves at least one real
   output-dependent case beyond Plan 85, has acceptable measured cost, and has a bounded production
   API path. Name the exact follow-up ExecPlan scope but do not implement it here.
2. `Proceed after structural wire-schema prerequisite`: the precision is real but current
   `WireCtor` evidence is insufficient. Specify the minimal prerequisite, migration surface, and
   why name-based or opaque alternatives were rejected.
3. `Do not proceed`: no material precision win or the compatibility/performance/maintenance cost
   exceeds the evidenced benefit. State which narrower analyses remain appropriate.

“Proceed” requires every suppressed prototype pair to be justified by definite UNSAT over a sound
over-approximation; finite tests alone are insufficient. It also requires at least one registered
consumer shape beyond Mori Workflow or a clearly reusable class of generated schemas, and median
solver time for the 100-pair fixture no worse than five times the guard-only symbolic baseline on
the same machine. If these gates are not met, choose one of the other conclusions.

Finally, distill the selected durable boundary into ADR-0001, ADR-0003, ADR-0005, or a new profiled
ADR as appropriate. A rejection is still durable if it explains why opaque wire closures prevent a
sound model; record it rather than leaving future work to repeat the experiment. Validate all
surviving documentation, tests, ADR metadata, and repository gates.


## Concrete Steps

Run all commands from `/Users/shinzui/Keikaku/bokuno/keiki`. Start by observing repository state and
locating the semantic authorities:

```bash
git status --short
rg -n "applyEventKernel|solveOutput|recomputeDerivedFields|gatherInpEntries|inversionAmbiguityWarnings" src/Keiki/Core.hs
rg -n "data SymEnv|mkSymEnv|translateTermSym|translatePred|runPredicateSolver|satResultIsProvablyUnsat" src/Keiki/Symbolic.hs
```

Discover SBV through Mori before reading its registered source:

```bash
mori registry search sbv
mori registry show LeventErkok/sbv --full
mori registry docs LeventErkok/sbv
```

The current registry reports the source at
`/Users/shinzui/Keikaku/hub/haskell/sbv-project`. Scope every source search to that path and never
traverse `/nix/store`:

```bash
rg -n "free_|constrain|SatResult|SMTResult|mkSymbolic|uninterpret|SEither" /Users/shinzui/Keikaku/hub/haskell/sbv-project/sbv/Data/SBV
```

Before relying on a version-specific API or recommending dependency bounds, verify Hackage and
upstream tags. Record the results and date in the research report:

```bash
curl -fsSL https://hackage.haskell.org/package/sbv/preferred.json
git ls-remote --tags https://github.com/LeventErkok/sbv.git
```

Discover Keiki consumers and inspect only registered project paths returned by Mori:

```bash
mori registry dependents shinzui/keiki --packages --json
mori registry show shinzui/mori --full
mori registry show shinzui/keiro --full
```

Establish the current symbolic baseline inside the GHC 9.12 shell:

```bash
nix develop -c cabal test keiki-test --test-options='--match=Symbolic|ValidationReplayAlignmentSpec|RecomputeVerify' --test-show-details=direct
```

If combined Hspec matching differs in the active version, run each stable substring separately and
record all outputs. During prototype milestones run:

```bash
nix develop -c cabal test keiki-test --test-options='--match=full symbolic replay-inversion research' --test-show-details=direct
```

A successful focused transcript looks like this, with the actual example count substituted:

```text
... examples, 0 failures
```

Capture solver debug/SMT output only in a temporary directory created with `mktemp -d`; do not add
machine-specific paths or large solver dumps to Git. Copy only the small formulas or statistics
needed as evidence into `docs/research/full-symbolic-replay-inversion-model.md`.

After the final keep/remove decision, run the surviving repository gates:

```bash
nix fmt -- --no-cache
nix develop -c cabal build all
nix develop -c cabal test all --test-show-details=direct
nix develop -c cabal haddock keiki
nix flake check
just adr-validate
git diff --check
```

If `just adr-validate` is blocked by unrelated in-progress ADR-profile changes in the working tree,
preserve them, record the exact failure in this plan, and do not claim completion until the strict
gate can be rerun successfully.


## Validation and Acceptance

The research report is self-contained: it defines the exact concrete candidate relation, maps each
runtime constraint to symbolic evidence, distinguishes exact translation from conservative
over-approximation, and lists every trust assumption. A reader does not need this conversation or
an uncommitted prototype to understand the result.

The dual-command prototype shares register variables and separates command constructor tags,
input fields, outer arms, projections, and opaque occurrences. Finite concrete enumeration agrees
with solver SAT/UNSAT for every supported fixture. The negative single-command control demonstrates
the incorrect constructor-exclusion result that the production design must avoid.

At least one fixture is disjoint only because both inversions refer to the same observed head
field; Plan 85's register-only proof must retain its warning. The full prototype proves the pair
UNSAT, finds the overlapping control SAT, and bounded concrete evaluation agrees. If no viable
structural evidence can express that relationship, the final decision cannot be `Proceed`.

Every `Unknown`, `ProofError`, unsupported carrier, opaque relationship, dishonest schema witness,
same-name/different-field-schema pair, unsupported projection relationship, and derived-function
gap produces “not proved disjoint.” A `TReg` output is never equated with current registers merely
because it appears on the wire. Multi-event tails never distinguish head candidates.

The report contains a dated SBV version/API verification, canonical Mori dependency references,
reverse-dependent impact, solver timing data, representative SMT evidence, and a source/PVP
migration analysis. It names which prototype files were retained or removed and why.

The final conclusion is exactly one of `Proceed`, `Proceed after structural wire-schema
prerequisite`, or `Do not proceed`, evaluated against the promotion criteria in Plan of Work. It
names a bounded next action and does not silently change `inversionAmbiguityWarnings`,
`validateTransducer`, `WireCtor`, or any other public API.

All surviving focused and full tests, formatting, Haddocks, Nix checks, strict ADR validation, and
diff checks pass. If the result is documentation-only after removing the spike, the complete
existing test matrix must still pass unchanged.


## Idempotence and Recovery

Mori discovery, source inspection, Hackage/tag verification, solver queries, bounded enumeration,
and timing runs are read-only or create only build artifacts. They can be repeated safely. Use a
fresh `mktemp -d` directory for solver dumps and delete only that exact validated temporary path
after evidence is extracted.

The working tree may already contain user-owned documentation changes. Inspect `git status
--short` before every milestone and never use destructive reset or restore commands. Prototype
edits must be narrow additions to the named test module and registrations. Commit a green
prototype before experimenting with a competing design so Git history preserves reproducible
evidence; every commit must include this plan's required trailer:

```text
ExecPlan: docs/plans/86-research-a-full-symbolic-replay-inversion-model.md
```

If a prototype requires `unsafeCoerce`, trusts equal `wcName` strings as type evidence, changes
runtime replay, or treats an inconclusive result as UNSAT, stop that branch immediately. Record the
failed design and counterexample in Surprises & Discoveries and the research report; do not repair
it by weakening acceptance.

If SBV corpus APIs differ from the authoritative current release, prototype against the version
allowed by `keiki.cabal`, record both versions, and avoid changing bounds in this research plan.
Any dependency update requires a separate compatibility decision after upstream tags and Hackage
are verified.

If the retained prototype becomes costly or flaky, remove it and its `keiki.cabal`/`test/Spec.hs`
registrations together, run the complete suite, and preserve the experiment in the report and
version history. A research rejection is a successful plan outcome when it is evidence-backed.


## Interfaces and Dependencies

The concrete semantics come from `Keiki.Core` in `src/Keiki/Core.hs`; the existing symbolic
translator comes from `Keiki.Symbolic` in `src/Keiki/Symbolic.hs`; function-free detailed result
metadata comes from `Keiki.Internal.SymbolicTypes` in
`src/Keiki/Internal/SymbolicTypes.hs`. The research may import `Data.SBV` only through the existing
`sbv >=11.7 && <15` dependency. It must not add a library dependency or change a dependency bound.

The test-only prototype should make candidate scoping explicit. One possible research shape is:

```haskell
data CandidateScope = CandidateA | CandidateB

data InversionTranslationStrength
  = InversionExact
  | InversionConservative [InversionTranslationIssue]

data InversionProofVerdict
  = InversionProvedDisjoint
  | InversionSatisfiable
  | InversionUnknown String
```

These names are not a promised production API. The essential contract is that registers are
shared, command and input variables are candidate-scoped, observed head variables are shared only
under structural evidence, and only definite SBV `Unsatisfiable` produces
`InversionProvedDisjoint`.

The report must evaluate, but not necessarily implement publicly, a future detailed function with
the conceptual signature:

```haskell
checkInversionAmbiguitySymDetailed ::
  SymTransducer (HsPred rs ci) rs s ci co ->
  IO [InversionAnalysisDetail s]
```

The research must state the additional constraints or schema witnesses such a real signature
would require; omitting them from the conceptual sketch is not evidence that they are unnecessary.
Compatibility projection to the existing `InversionAmbiguity` warning would remain conservative.

External codebases are evidence sources, not build dependencies. Refer to SBV as
`mori://LeventErkok/sbv/packages/sbv`, Keiki as `mori://shinzui/keiki/packages/keiki`, and other
registered projects through their exact Mori handles. Read dependency source only from paths
returned by `mori registry show --full` and verify release state through authoritative Hackage and
upstream tags before making compatibility claims.
