---
id: 74
slug: fix-compose-update-snapshot-semantics-and-multi-event-chain-expansion-under-stateful-transducers
title: "Fix compose update-snapshot semantics and multi-event chain expansion under stateful transducers"
kind: exec-plan
created_at: 2026-07-12T04:16:45Z
intention: "intention_01kxc5whw1en3ra4nh728m53ka"
master_plan: "docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md"
---

# Fix compose update-snapshot semantics and multi-event chain expansion under stateful transducers

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

keiki composes two symbolic-register transducers sequentially with `compose`
(`src/Keiki/Composition.hs`): transducer t1 consumes commands of type `ci` and emits
intermediate events of type `mid`; transducer t2 consumes `mid` and emits `co`. The
correctness criterion for `compose` is a *semantic homomorphism*: stepping the composite
on a command must behave exactly like stepping t1 on that command and then feeding each
of t1's emitted `mid` events, in order, through t2 — same final registers, same outputs,
same accept/reject decision.

Today that criterion holds only for transducers whose substituted terms never read a
register that the same composite edge writes. The moment t1's edge both *writes* a
register slot and *emits* that slot's value (the classic "emit the counter, then
increment it" pattern), the composite silently stores a different value than sequential
execution would — a silent state-corruption bug, the worst failure class for an
event-sourcing core. Multi-event edges are worse: when t2 is stateful, the composite can
select a *different t2 path* than sequential execution and emit wrong events without any
error. A third defect makes composites of hand-written guards crash with a misleading
internal error where the plain transducers would not report that error text.

After this plan, `step (compose t1 t2)` agrees with the sequential reference semantics
for stateful t1 and t2, including multi-event chains (or, where the design honestly
cannot deliver that, composition is *statically rejected* with a clear diagnostic
instead of silently diverging); the guard-order crash is gone; and a
semantic-homomorphism test suite proves all of it by running both sides on enumerated
inputs and comparing final registers and outputs. You can see it working by running
`cabal test all` from the repository root inside `nix develop`: the new
`Keiki.CompositionStatefulSpec` and `Keiki.CompositionHomomorphismSpec` suites pass, and
they demonstrably fail on the pre-fix code.

This is Phase 3 of the master plan at
`docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md`
(EP-74 in its registry). The keiro consumer survey recorded there found ZERO downstream
users of any composition operator, so the semantics of `compose` may change freely.
The master plan gates the 0.1.0.0 Hackage release on this plan — with one recorded
fallback: if schedule pressure forces a cut, `Keiki.Composition` may instead ship with
its module haddock explicitly marked *experimental* (see the master plan's Vision
section); in that case this plan's Decision Log must record the cut and the haddock edit
becomes the minimum deliverable.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented
here, even if it requires splitting a partially completed task into two ("done" vs.
"remaining"). This section must always reflect the actual current state of the work.

- [x] (2026-07-13 03:33Z) M1: fixture module `test/Keiki/Fixtures/ComposeStateful.hs` written (counter source, last-value sink, two-phase chain sink, wrong-order-guard sink) and registered in `keiki.cabal`
- [x] (2026-07-13 03:33Z) M1: red tests in `test/Keiki/CompositionStatefulSpec.hs` pinning defect 1 (post-update substitution), defect 2 (stale chain registers / wrong path selection), defect 3 (guard-order crash) — each fails against current `master` with the divergence the Context section predicts and remains committed behind its milestone `pendingWith`
- [x] (2026-07-13 03:37Z) M2 (prototyping): snapshot-semantics prototype for `runUpdate` in `src/Keiki/Core.hs`; full suite green; current-keiro and in-repo consumer blast-radius survey re-verified; promote decision recorded in the Decision Log
- [x] (2026-07-13 03:37Z) M3: defect 1 fixed on the single-mid path; emit-then-increment test green; `runUpdate` haddock updated to match real semantics; `alternative` and `feedback1` audit complete
- [x] (2026-07-13 03:39Z) M4: defect 2 fixed — chain expansion threads symbolic composed terms through a newest-first pending-write environment; two-phase chain and pre-existing stateless multi-event tests green
- [x] (2026-07-13 03:42Z) M5: defect 3 fixed — `substTerm` total via inert poison, guard leaves with mismatched input reads substitute to `PBot`; wrong-order-guard test green; structural walkers (symbolic check, pretty printer, replay) verified crash-free on cross-constructor composites
- [x] (2026-07-13 03:46Z) M6: `test/Keiki/CompositionHomomorphismSpec.hs` — bounded-exhaustive semantic-homomorphism suite green (single-mid, multi-event, reject-agreement), with the documented wrong-order sequential bottom represented as an explicit refinement case
- [ ] M7: documentation — `feedback1` haddock nesting constraint (defect 4), `compose` haddock, `docs/research/composition-combinators-design.md`, `docs/research/gsm-widening-design.md` §5, `CHANGELOG.md`; master plan registry row and progress box updated
- [ ] `nix fmt -- --no-cache` clean; `cabal build all` and `cabal test all` green under GHC 9.12


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- (Plan authoring, 2026-07-11) `runUpdate`'s haddock claims write-order independence —
  "the two halves write to disjoint slots, so the application order does not affect the
  result" (`src/Keiki/Core.hs:839-842`) — but the implementation threads the register
  file left-to-right (`runUpdate (UCombine a b) regs ci = runUpdate b (runUpdate a regs
  ci) ci`, `src/Keiki/Core.hs:846`), so the *right* half's right-hand sides observe the
  *left* half's writes. The claim is false whenever one half reads a slot the other half
  writes, even in a single hand-written edge with no composition involved. This is the
  root enabler of defect 1 and the reason remedy (b) below doubles as a documentation
  fix.
- (Plan authoring, 2026-07-11) The builder's `(.=)` *prepends* each assignment
  (``pe {peUpdate = USet ix t `combine` peUpdate pe}``, `src/Keiki/Builder.hs:403`), so
  `runUpdate`'s left-to-right threading applies builder writes in *reverse declaration
  order*: an earlier-declared assignment's right-hand side observes a later-declared
  assignment's write. Snapshot semantics (remedy b) erases this ordering hazard.
- (Plan authoring, 2026-07-11) Defect 2 is not merely "guards go stale": working the
  two-phase chain fixture by hand shows the composite can satisfy the *wrong* path
  (phase-0 edge taken twice), silently emitting wrong events, and that path's chained
  update writes the same rs2 slot twice inside one composite edge — the raw `UCombine`
  at `src/Keiki/Composition.hs:1044` bypasses the `Disjoint` discipline, so nothing
  reports it. See the worked example in Context.
- (Plan authoring, 2026-07-11) The defect-3 crash is not unique to composites: a plain
  transducer with the wrong-order guard also crashes when a non-matching constructor
  arrives, via `evalTerm`'s `TInpCtorField guard violation` error
  (`src/Keiki/Core.hs:792-794`). What composition changes is (i) the error text becomes
  the misleading "structural mismatch between t1's wireCtor and t2's InCtor"
  (`src/Keiki/Composition.hs:413-424`), pointing the author at `compose` instead of at
  their guard, and (ii) *structural walkers* — the SBV translator pattern-matches term
  constructors and therefore forces the substituted error thunk
  (`src/Keiki/Symbolic.hs:439-440`), as do the pretty/mermaid renderers — can crash on
  composite edges that runtime evaluation would never crash on. The fix therefore aims
  for walker-inert totality, not just runtime order.
- (Implementation M1, 2026-07-13) Activating all three stateful regressions against
  the pre-fix tree reproduced the review exactly: the counter sink stored `1` instead
  of `0`, the two-phase chain ended at phase `1` instead of `2`, and the wrong-order
  guard raised the `TInpCtorField over M2B but ... produced M2A` substitution error.
  Restoring the three `pendingWith` guards left the focused suite at nine examples,
  zero failures, and three pending tests.
- (Implementation M2/M3, 2026-07-13) Snapshot evaluation was observation-equivalent
  across the existing workspace: `cabal test all` passed all four suites, including
  245 keiki examples, 122 jitsurei examples, and both codec suites. The `mori`-located
  current keiro tree contains no raw `UCombine`; every register-reading update found
  in keiki/jitsurei is either a same-slot increment or a rendering-only fixture.
  Activating the counter composition regression now leaves `srcCount = 1`, stores
  `sinkLast = 0`, and emits `OutVal 0` as sequential execution does.
- (Implementation M4, 2026-07-13) The planned typed environment was tractable without
  broadening the unsafe boundary: simultaneous induction over `IndexN` and `Index`
  produces an `(:~:)` witness for equal slots, and the existing documented
  `unsafeCoerceTerm` is needed only to hide the pending term's existential input-field
  schema. The active two-phase regression now emits `[Stage1 10, Stage2 20]` and ends
  at phase `2`; the twelve focused multi-event/replay/rendering examples remain green.
- (Implementation M5, 2026-07-13) Replacing constructor-mismatch and field-overflow
  bottoms with opaque poison terms was sufficient for every structural walker; the
  only remaining `error` in that substitution region is deliberately inside
  `poisonTerm`'s value-level function. Leaf-level mismatch detection makes the
  wrong-order M2B equality `PBot` before term substitution. The active forward step,
  SBV single-valuedness check, pretty-printer traversal, and replay of `[SawA 5]` all
  complete successfully in the focused four-example suite.
- (Implementation M6, 2026-07-13) The homomorphism suite's mutation check has teeth:
  changing `runUpdate`'s `USet` evaluator from the entry `regs` back to the threaded
  `acc` makes the counter comparison fail at `sinkLast`, reporting expected `0` but
  got `1`. Restoring snapshot evaluation returns all four suite cases to green.


## Decision Log

Record every decision made while working on the plan.

- Decision: this plan authors its own stateful fixtures under `test/Keiki/Fixtures/`
  rather than waiting for EP-71's.
  Rationale: master plan integration point 4 says EP-71 defines the first
  `TReg`-in-`OutFields` fixtures and EP-74 reuses them, but
  `docs/plans/71-align-build-time-validation-with-replay-head-recoverability-cross-edge-inversion-ambiguity-and-guard-implies-input-read-checks.md`
  owns replay-specific fixtures and EP-74 has no hard dependency on it. The fixtures
  here are designed to be reusable (plain modules under `test/Keiki/Fixtures/`, no
  compose-specific coupling in the transducers themselves); if EP-71 lands first,
  Milestone 1 reuses a suitable fixture instead of duplicating it — check
  `test/Keiki/Fixtures/` before writing.
  Date: 2026-07-11

- Decision: the leading remedy for defect 1 is (b) — give `UCombine` snapshot
  ("parallel assignment") semantics in `runUpdate`, evaluating every write's right-hand
  side against the register file as it was when the update began, applying writes
  left-to-right — implemented as a change to `runUpdate` only, with no new `Update`
  constructor. Remedies (a) shadow slots and (c) static rejection remain fallbacks,
  evaluated in Milestone 2.
  Rationale: (b) is a one-function change that leaves every structural `Update` walker
  untouched (`updateReadsInput` `src/Keiki/Core.hs:1452`, `Keiki.Profunctor`
  `src/Keiki/Profunctor.hs:902,910`, `Keiki.Render.Pretty` `src/Keiki/Render/Pretty.hs:98`,
  `Keiki.Render.Inspector` `src/Keiki/Render/Inspector.hs:224`, `Keiki.Render.Mermaid`
  `src/Keiki/Render/Mermaid.hs:919`); it makes the existing haddock's order-independence
  claim true instead of false; and the authoring-time consumer survey (see Context,
  "Blast radius of snapshot semantics") found no update right-hand side anywhere in
  keiki's tests, `jitsurei/`, or current keiro that reads a slot written
  by a *sibling* combine half — the only register-reading right-hand sides are
  self-reads (counter increments), whose value is identical under both semantics.
  (a) changes `compose`'s result register-file type away from `Append rs1 rs2`,
  breaking `appendRegFile`, the mermaid composite renderers, and the type-level
  slot-name story, for no semantic gain over (b). (c) is a capability regression kept
  only as the honest fallback.
  Date: 2026-07-11

- Decision: guard-position constructor mismatches substitute to a leaf-level `PBot`;
  non-guard positions (update right-hand sides, output fields) substitute to a
  walker-inert lazily-poisoned term. This makes the composite *more* defined than the
  sequential reference in exactly one corner: a hand-written wrong-order guard that
  would crash sequentially instead evaluates to "edge does not fire".
  Rationale: the sequential crash is an error path (`evalTerm` bottom,
  `src/Keiki/Core.hs:792-794`), not defined semantics; refining bottom to `False` is
  sound for edge selection (the edge could never have been legitimately selected for
  that constructor) and is required anyway so that structural walkers — the SBV
  single-valuedness check, renderers, `validateTransducer`, replay's `solveOutput` —
  never force a poison while merely *inspecting* a composite. An edge-level blanket
  `PBot` was rejected: it is wrong for `POr` guards that legitimately handle several
  mid constructors in different disjuncts. Documented as a deliberate refinement in the
  `compose` haddock (Milestone 7).
  Date: 2026-07-11

- Decision: the homomorphism suite uses bounded-exhaustive enumeration with plain
  hspec, not QuickCheck.
  Rationale: the `keiki-test` suite depends only on hspec (`keiki.cabal:138-148`);
  the fixture input spaces are tiny (an `Int` payload and a bounded command list), so
  exhaustive sweeps over a representative pool are deterministic, reproducible, and add
  no dependency. EP-73 (`docs/plans/73-decide-replay-round-trip-property-harness-across-all-fixtures.md`)
  owns the generalized randomized property harness and can lift this suite's reference
  semantics into it later.
  Date: 2026-07-11

- Decision: keiro impact statement (required by master plan integration point 6 when a
  plan touches `step`'s behavior). Remedy (b) changes `runUpdate`, which sits under
  `step` / `applyEventStreaming` / `applyEvents` — keiro's load-bearing surface. The
  change is observation-equivalent for every update in the surveyed consumers (no
  sibling-half register reads exist; self-reads are unchanged), and *both* the decide
  path and the replay path go through the same `runUpdate`, so decide/replay round-trips
  cannot desynchronize. Milestone 2 re-verifies the survey before promoting the
  prototype; if any consumer update is found to depend on sequential threading, the
  decision flips to a new `UPar` constructor (leaving `UCombine` untouched) and this
  entry must be superseded.
  Date: 2026-07-11

- Decision: promote the M2 snapshot-semantics prototype as the shipped `runUpdate`
  behavior and use it as M3's single-mid composition fix.
  Rationale: the focused Core regression and the complete workspace suite are green;
  `mori registry show shinzui/keiro --full` located the current consumer at
  `/Users/shinzui/Keikaku/bokuno/keiro`, whose source and tests contain no raw
  `UCombine`; all in-repo register-reading updates are self-reads, apart from the new
  explicit snapshot regression and a non-evaluated pretty-printer fixture. The M3
  audit also found `alternative` only weakens/lifts each arm's own update, while
  `feedback1` is defined entirely as two `compose` calls, so neither needs a separate
  update-boundary repair.
  Date: 2026-07-13

- Decision: ship symbolic pending-write threading for multi-event chain expansion;
  do not take the static-restriction fallback, and retain duplicate composite writes.
  Rationale: `PendingWrite` plus the type-safe `matchIndex` witness lets each later t2
  guard, update, and output inline the newest prior t2 write before the composite AST
  is finalized. The only coercion is the same input-field-schema realignment already
  documented for substitution. Retaining the raw duplicate writes preserves the
  chain's visible structure, while snapshot `runUpdate` applies them left-to-right so
  the later step wins exactly as sequential execution does.
  Date: 2026-07-13

- Decision: treat the wrong-order guard fixture as an explicit refinement case in the
  M6 suite, not as a homomorphism equality case.
  Rationale: the plan already records that plain sequential execution is bottom for
  this hand-written guard (`evalTerm: TInpCtorField guard violation: M2B`) while the
  composite deliberately refines the error to a defined M2A step. The first M6 run
  confirmed that comparing those results crashes the reference before an equality can
  exist. The suite now asserts both sides of that documented exception directly and
  reserves exact state/output/reject comparisons for the three defined sequential
  pipelines.
  Date: 2026-07-13


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

Everything in this section is verifiable against the working tree; no other document is
required. Line numbers refer to the tree at the time of writing (branch `master`,
commit `bc987f4`); re-verify them before editing, since Phase 1/2 plans of the same
master plan may land first and shift lines.

### The machine being composed

keiki's core abstraction (defined in `src/Keiki/Core.hs`) is the *symbolic-register
transducer*: a value of type `SymTransducer phi rs s ci co` (`src/Keiki/Core.hs:638-643`)
holding a finite control graph (`edgesOut :: s -> [Edge ...]`), an initial vertex, an
initial *register file*, and a final-vertex predicate. A register file
(`RegFile rs`, `src/Keiki/Core.hs:200-204`) is a typed heterogeneous tuple indexed by a
type-level list of *slots* — (name, type) pairs. An `Edge` (`src/Keiki/Core.hs:627-634`)
carries four things:

- a *guard* `phi` (concretely `HsPred rs ci`, a first-class predicate AST over register
  reads and input-field reads, `src/Keiki/Core.hs:524-552`) deciding whether the edge
  fires for a given (registers, input) pair;
- an *update* (`Update rs w ci`, `src/Keiki/Core.hs:430-442`) — a bag of slot writes,
  each `USet index term` assigning the value of a `Term` to one slot, combined with
  `UCombine`; the type-level `w` index tracks written slot names and the smart
  constructor `combine` (`src/Keiki/Core.hs:450-455`) statically demands the two halves
  write *disjoint* slot sets (the "copyless" discipline: each slot written at most once
  per edge);
- an *output list* `[OutTerm rs ci co]` — zero terms is an ε-edge (no emission), one is
  a letter edge, several is a multi-event edge. Each `OutTerm` is an `OPack`
  (`src/Keiki/Core.hs:504-517`): an input-constructor tag (`InCtor`), an
  output-wire-constructor tag (`WireCtor`), and one `Term` per wire field;
- a *target* vertex.

A `Term` (`src/Keiki/Core.hs:299-330`) is a pure expression: literal (`TLit`), register
read (`TReg`), input-constructor field read (`TInpCtorField`), opaque function
application (`TApp1`/`TApp2`), or structural arithmetic (`TArith`).

The evaluation order that matters for this plan, all in `src/Keiki/Core.hs`:

- `step` (`910-918`) = `delta` + `omega`. `delta` (`868-881`) selects the unique edge
  whose guard holds **against the pre-step registers** and returns the post-update
  registers. `omega` (`889-902`) evaluates the selected edge's output terms **against
  the pre-step registers** (line 897 passes the original `regs`; `step` line 918 calls
  `omega` with the pre-update `regs`). `stepEither` does the same (outputs computed
  from pre-update `regs` at `997-998`).
- `runUpdate` (`843-846`) applies an update. The `UCombine` clause **threads** the
  register file: `runUpdate (UCombine a b) regs ci = runUpdate b (runUpdate a regs ci)
  ci` (line 846) — so `b`'s right-hand-side terms are evaluated against the registers
  **after** `a` ran. `setSlotN` (`859-864`) forces each written value to WHNF (the
  NoThunks/EP-23 strictness discipline); any change here must preserve those bangs.
- `evalPred` (`821-837`) evaluates guards; `PAnd` short-circuits left-to-right via
  Haskell `&&` (line 824). `evalTerm` on a `TInpCtorField` whose constructor does not
  match the input **crashes** with `"evalTerm: TInpCtorField guard violation"`
  (`792-794`).

So the *sequential reference semantics* of one step is: guards on pre-state, outputs on
pre-state, updates from pre-state. The whole plan is about making the composite respect
that.

### How compose works today

`compose` (`src/Keiki/Composition.hs:879-1065`) builds the composite without ever
materializing `mid` at run time. For each t1 edge and each t2 edge it builds one
composite edge by *substituting* t1's output term `o1 :: OutTerm rs1 ci1 mid` into t2's
guard/update/output wherever t2 reads its input:

- `substTerm` (`379-432`): a t2-side `TInpCtorField ic2 ix2` (a read of field `ix2` of
  mid constructor `ic2`) is replaced by the `ix2`-th field term of `o1`'s `OutFields`
  when `icName ic2 == wcName wc1` — i.e., by the t1-side expression (over `rs1` reads
  and `ci1` reads) that *would have produced* that mid field. On a constructor mismatch
  it calls `error` (`413-424`); the comment there says the guard's `PInCtor`
  substitution "should make the edge unsatisfiable before evaluation reaches this
  term" — the fragile shield of defect 3. Type alignment uses `unsafeCoerceTerm`
  (`434-444`), justified by the structural-alignment invariant documented there.
- `substPred` (`448-479`): recurses through the predicate; `PInCtor ic2` becomes `PTop`
  on constructor match, `PBot` on mismatch (`474-479`).
- `substUpdate` (`484-498`) and `substOut` (`501-529`): same recursion over update
  right-hand sides and output fields. t2-side register reads are *weakened* (index
  shifted) into the appended file `Append rs1 rs2`; t1-side contributions are weakened
  from the left.

The single-mid composite edge (`productEdge`, `953-988`) is then:

```haskell
guard  = PAnd (weakenLPred (guard e1)) (substPred (guard e2) o1)   -- lines 978-981
update = UCombine (weakenLUpdate u1) (substUpdate u2 o1)           -- lines 982-985
output = map (\o2 -> substOut o2 o1) (output e2)                   -- line 986
```

Multi-event t1 edges (`output e1 = [o1..oN]`, N ≥ 2) go through *chain expansion*
(`PartialPath` `842-848`, `initialPath` `994-1004`, `expandPaths` `1015-1025`,
`stepPath` `1031-1046`, `finalizePath` `1049-1065`): every path of N t2 edges consuming
the N mid symbols in order becomes one composite edge whose guard is the conjunction of
all substituted step guards, whose update is the `UCombine` chain of t1's update and
all substituted step updates, and whose output is the concatenation of all substituted
step outputs.

### Defect 1 (HIGH): post-update substitution in the composite update

Verified. Sequentially, t1's output `o1` — and therefore everything `substUpdate u2 o1`
inlines into u2's right-hand sides — is evaluated against t1's **pre-update** registers
(`omega`, `src/Keiki/Core.hs:889-902`). But the composite update
`UCombine (weakenLUpdate u1) (substUpdate u2 o1)` (`src/Keiki/Composition.hs:982-985`)
runs through `runUpdate`'s threading clause (`src/Keiki/Core.hs:846`), which evaluates
the right half's right-hand sides against the registers **after** u1 ran.

Failure shape: t1's edge writes slot X and emits `TReg X` (emit-then-increment). With
`count = 0`: sequentially, mid carries 0, so t2's update stores 0 and t1's register
becomes 1. The composite stores **1** — the post-increment value — into t2's slot.
Guards and outputs do *not* diverge (both are evaluated on pre-step registers by
`delta`/`omega`); only the update path diverges, silently. No current test catches this:
neither `test/Keiki/CompositionSpec.hs` nor `test/Keiki/CompositionMultiEventSpec.hs`
routes a register read through substitution (the first's t1 outputs read only input
fields; the second's transducers have empty register files).

### Defect 2 (HIGH for stateful t2): stale registers in chain expansion

Verified. Sequentially, t2 consumes the N mid events in N separate steps, each step's
guard/output evaluated against the registers **updated by the previous step**. The
composite instead evaluates the entire accumulated guard once (in `delta`, against
pre-step registers) and all accumulated outputs once (in `omega`, same snapshot), while
the `UCombine` update chain **does** thread writes — internally inconsistent.

Worked example (this becomes the M1 fixture): t2 has slot `phase :: Int` starting at 0
and two self-loop edges — edge₁ guarded `phase == 0`, setting `phase := 1`, emitting
`Stage1`; edge₂ guarded `phase == 1`, setting `phase := 2`, emitting `Stage2`. t1 emits
two mid events from one command. Sequential: edge₁ then edge₂ fire; outputs
`[Stage1, Stage2]`; final `phase = 2`. Composite today: the path (edge₁, edge₂) has
accumulated guard `(phase == 0) ∧ (phase == 1)`, both conjuncts evaluated at the
pre-chain snapshot `phase = 0` — unsatisfiable; the path (edge₁, edge₁) has
`(phase == 0) ∧ (phase == 0)` — satisfiable! The composite silently fires the wrong
path, emits `[Stage1, Stage1]`, and its chained update writes the same `phase` slot
twice inside one edge (the raw `UCombine` in `stepPath`,
`src/Keiki/Composition.hs:1044`, bypasses the `Disjoint` check), ending at `phase = 1`.
Wrong outputs, wrong state, no error.

### Defect 3 (MEDIUM): guard-order-dependent error shield

Verified. `substTerm`'s mismatch `error` (`src/Keiki/Composition.hs:413-424`) is a
thunk planted inside the composite AST; it stays dormant only if evaluation
short-circuits before reaching it. `evalPred (PAnd p q)` evaluates left-to-right
(`src/Keiki/Core.hs:824`), and builder-authored edges always have the constructor test
leftmost — `onCmd` seeds `peGuard = matchInCtor ic` (`src/Keiki/Builder.hs:672`) and
`requireGuard` appends on the right (`PAnd (peGuard pe) p`, `src/Keiki/Builder.hs:560`)
— so for builder edges the substituted `PBot` (from `substPred`'s `PInCtor` clause,
`src/Keiki/Composition.hs:474-479`) shields the poisoned terms. A hand-written guard in
the other order, e.g. `fieldB .== lit 5 .&& matchInCtor B`, evaluates the poisoned
`PEq` first and the composite crashes with the "structural mismatch between t1's
wireCtor and t2's InCtor" error — misdirecting the author toward a compose bug.
Additionally, walkers that inspect the AST *structurally* rather than evaluating it —
the SBV translator pattern-matches every term constructor and thus forces the thunk's
WHNF (`src/Keiki/Symbolic.hs:439-440`), as do `Keiki.Render.Pretty`/`Mermaid` and
validation — can crash on composites whose runtime behavior is fine. (See Surprises for
the honest comparison with the sequential crash.)

### Defect 4 (DOC): feedback1's advertised nesting is over-constrained

Verified. The `feedback1` haddock advertises multi-round nesting
`twoRounds = feedback1 (feedback1 t f) f` (`src/Keiki/Composition.hs:1223-1227`) and
explains that the constraint set forces `rs1 ~ '[]` (t stateless,
`src/Keiki/Composition.hs:1230-1248`) — but the *nested* call applies the same
`Disjoint (Names rs1') (Names (Append rs2 rs1'))` constraint to
`rs1' = Append rs1 (Append rs2 rs1)`, which is satisfiable only when that whole append
is `'[]`, i.e. it additionally requires `rs2 ~ '[]` (the policy stateless too). The
haddock omits this. Documentation-only fix.

### Blast radius of snapshot semantics (authoring-time survey, to re-verify in M2)

Changing `runUpdate`'s `UCombine` clause changes observable behavior only where one
combine half's right-hand side reads a slot another half writes. Surveyed on
2026-07-11: keiki `src/` and `test/` contain no such update (the only `USet` with a
`TReg` right-hand side outside `Keiki.Composition` is a *rendering* fixture,
`test/Keiki/Render/PrettySpec.hs:128`, never evaluated); `jitsurei/src/` register-reading
right-hand sides are all single-`USet` self-reads (`Jitsurei/OrderCart.hs:595,620`,
`Jitsurei/LoanApplication.hs:749,769` — counter increments, identical under both
semantics). Re-check current keiro using the source path from
`mori registry show shinzui/keiro --full` before promoting the prototype; do not use
stale runtime repositories as compatibility evidence. The grep commands are in
Concrete Steps.

### Why the fix directions are what they are

The core problem, common to defects 1 and 2: substitution inlines t1-state-reading
terms into positions the composite evaluates at a *later register snapshot* than the
sequential semantics prescribes. Three candidate remedies were named by the review and
must be weighed by this plan (Milestone 2 does the weighing with a prototype):

(a) *Shadow slots*: extend the composite update so every rs1 slot that u1 writes and
`o1` reads is first copied into a fresh composite-internal slot, and rewrite the
substituted reads to the shadows. Rejected as leading candidate at authoring time: the
composite register file would no longer be `Append rs1 rs2`, changing `compose`'s
signature and breaking `appendRegFile` (`src/Keiki/Generics.hs`), the composite mermaid
renderers, and the type-level slot-name accounting; fresh type-level names are awkward
to fabricate. Keep as fallback only if (b) is discarded.

(b) *Snapshot ("parallel assignment") update semantics*: make `runUpdate` evaluate
every write's right-hand side against the register file **as it was when the update
began**, applying the writes left-to-right (so a duplicated slot resolves to the
rightmost write — needed by M4, see below). Sketch:

```haskell
runUpdate :: Update rs w ci -> RegFile rs -> ci -> RegFile rs
runUpdate u regs ci = go u regs
  where
    -- Right-hand sides read the outer 'regs' snapshot; writes
    -- accumulate in the second argument, left before right.
    go :: Update rs w' ci -> RegFile rs -> RegFile rs
    go UKeep acc = acc
    go (USet ix t) acc = setSlotN ix (evalTerm t regs ci) acc
    go (UCombine a b) acc = go b (go a acc)
```

This preserves `setSlotN`'s WHNF forcing exactly, touches no walker, makes the
documented order-independence claim true (for disjoint writes), and — because
`o1`-derived terms then evaluate against pre-update registers wherever they sit — fixes
defect 1 with no change to `compose` at all. Under the copyless discipline it is
observation-equivalent for every surveyed consumer.

(c) *Restrict*: at `compose` time, walk each t1 edge and reject (with a clear
diagnostic `error`, or a dedicated validation warning) any edge that writes a slot its
own output reads. This converts silent divergence into a loud refusal but removes a
legitimate capability (emit-then-increment is the natural counter idiom). Acceptable as
the shipped behavior only if (b) is discarded in M2; even then, prefer (c) now +
(a)/(b) later, per the review.

For defect 2, snapshot semantics alone is not enough — sequential t2 steps genuinely
*do* observe each other's writes across steps. The honest per-step semantics is:
step i's substituted guard/output/update-right-hand-sides must be evaluated as if the
registers reflect steps 1..i-1's updates. Since the composite evaluates everything at
one snapshot, chain expansion must *symbolically compose* the updates: maintain, along
each `PartialPath`, a symbolic environment mapping each rs2 slot written by an earlier
chain step to the (already substituted, already weakened) `Term` that computes its new
value; when substituting step i, additionally rewrite every `TReg` read of an
environment slot to the environment's term. Inlining is sound precisely *because* of
snapshot semantics: an earlier step's right-hand side reads only the pre-chain
snapshot, so its inlined copy evaluates to the same value in guard position (pre-step
snapshot), output position (same), and update position (snapshot semantics). Two
mechanical notes: a safe, coercion-free index comparison is derivable by simultaneous
induction —

```haskell
-- In src/Keiki/Composition.hs (new helper). Both indices point into the
-- same slot list, so equal positions force equal value types by GADT
-- refinement; no unsafeCoerce is needed.
matchIndex :: IndexN s rs a -> Index rs b -> Maybe (a :~: b)
matchIndex IZ ZIdx = Just Refl
matchIndex (IS i) (SIdx j) = matchIndex i j
matchIndex _ _ = Nothing
```

— while splicing the environment term into a host `Term` whose input-field-schema
parameter `ifs` differs requires the same existential realignment `substTerm` already
performs with `unsafeCoerceTerm` (`src/Keiki/Composition.hs:434-444`); it is
behaviorally safe for the same reason (the `ifs` parameter only drives inversion of
`OPack` `OutFields`, and `evalTerm` never consults it), and must be documented in the
same style. Term size grows multiplicatively with chain depth; chains are as long as a
single edge's output list (small by construction), so this is acceptable — measure and
record in Surprises if it is not. If prototyping proves the threading intractable, the
honest fallback is to *restrict*: reject at `compose` time (clear diagnostic) any
multi-event chain in which a step's substituted guard/update/output reads an rs2 slot
written by an earlier step — decide honestly in M4 and record the decision.

Defect 3's fix is mechanical and independent: make `substTerm` total by returning a
walker-inert lazily-poisoned term on constructor mismatch — no new `Term` constructor
is needed, because `TApp1` is already opaque to every walker (the SBV translator emits
a fresh variable without touching the function, `src/Keiki/Symbolic.hs:439`; renderers
print it opaquely):

```haskell
-- Total replacement for substTerm's mismatch 'error': structurally a
-- benign TApp1 over a unit literal; bottoms only if the VALUE is
-- demanded, which the guard-side PBot substitution prevents.
poisonTerm :: String -> Term rs ci ifs r
poisonTerm msg = TApp1 (\() -> error msg) (TLit ())
```

and, in `substPred`, detect any `PEq`/`PCmp` leaf containing a mismatched
`TInpCtorField` (a small `Bool`-returning walker over the two operand terms, comparing
each `icName` against `wcName wc1`) and substitute that *leaf* to `PBot` — leaf-level,
not edge-level, so `POr` guards handling several mid constructors in different
disjuncts keep their satisfiable disjuncts. Keep the poison message text close to the
current one but reworded to name the *t2 guard/output position* as the likely culprit.
The `nthTerm` overflow error (`src/Keiki/Composition.hs:401-412`) may stay an `error` —
it indicates a broken `Generic` alignment, not an authoring pattern — but route it
through `poisonTerm` too if that costs nothing.


## Plan of Work

The work is seven milestones. M1 pins the defects with failing tests; M2 is an explicit
prototyping milestone that settles the design decision; M3–M5 land the three code
fixes; M6 proves the homomorphism wholesale; M7 closes the documentation and master
plan bookkeeping. Milestones are ordered but M5 (guard shield) and M7's defect-4 edit
touch disjoint code from M3/M4 and may be done in parallel by separate contributors.
Commit at every green milestone boundary with a conventional-commit message
(`fix(composition): ...`, `test(composition): ...`, `docs(composition): ...`).

### Milestone 1 — stateful fixtures and red tests that pin the defects

Scope: create `test/Keiki/Fixtures/ComposeStateful.hs` and
`test/Keiki/CompositionStatefulSpec.hs`; register both in `keiki.cabal`'s
`other-modules` (the test-suite stanza lists modules at `keiki.cabal:101-137`; keep the
list alphabetical). Before writing fixtures, check whether EP-71 already landed
`TReg`-emitting fixtures under `test/Keiki/Fixtures/` (at authoring time that directory
holds only `EmailDelivery.hs` and `UserRegistration.hs`); if it did, reuse its counter
fixture for t1 and add only what is missing.

The fixture module defines four small transducers, written directly against the Core
AST in the style of `test/Keiki/CompositionMultiEventSpec.hs` (hand-rolled `InCtor` /
`WireCtor` records, no TH, so the module is self-explanatory):

- `counterSource`: registers `'[ '("srcCount", Int) ]` initialized to `0` (build the
  initial `RegFile` explicitly with `RCons (Proxy @"srcCount") 0 RNil` — do not use
  `emptyRegFile`, whose slots are error sentinels). One vertex, one self-loop edge on
  command `Tick` (payload-free `InCtor` is fine): guard `matchInCtor`, update
  `USet #srcCount (proj #srcCount .+ lit 1)`, output
  `[pack inCtorTick wcMidVal (proj #srcCount *: oNil)]` — it emits the *pre-increment*
  count. Mid alphabet: `data MidVal = MidVal Int`.
- `lastValueSink`: registers `'[ '("sinkLast", Int) ]` initialized to `-1`. One vertex,
  one self-loop edge on `MidVal`: guard `matchInCtor inCtorMidVal`, update
  `USet #sinkLast (inpCtor inCtorMidVal #v)`, output echoing the payload
  (`data OutVal = OutVal Int`).
- `twoPhaseSink` (for defect 2): registers `'[ '("phase", Int) ]` initialized to `0`;
  one vertex, two self-loop edges on `MidVal` as in the Context worked example — edge₁
  guarded `matchInCtor .&& (proj #phase .== lit 0)`, update `phase := lit 1`, output
  `Stage1` carrying the payload; edge₂ guarded `matchInCtor .&& (proj #phase .== lit 1)`,
  update `phase := lit 2`, output `Stage2` carrying the payload. Also a
  `pairSource` t1 with empty registers whose single edge on `Go` emits
  `[MidVal 10, MidVal 20]` (literal fields keep the example minimal).
- `wrongOrderSink` (for defect 3): mid alphabet with two constructors
  `data Mid2 = M2A Int | M2B Int`; a `m2aSource` t1 that emits only `M2A`; the sink has
  one edge for `M2A` with a normal builder-order guard, and one edge for `M2B` whose
  guard is hand-written in the *wrong* order:
  `(inpCtor inCtorM2B #b .== lit 5) .&& matchInCtor inCtorM2B`.

Since `RegFile` has no `Eq`/`Show` instance, give the spec small slot readers using
`(!)` with concrete `Index` annotations (e.g.
`readSinkLast rf = rf ! (SIdx ZIdx :: Index (Append CounterRegs SinkRegs) Int)` — or,
more readably, `#sinkLast`-style `HasIndex` labels at an annotated type) and compare
slot values directly.

The spec then pins each defect as a *red* test asserting the **sequential** value:

- Defect 1: `step (compose counterSource lastValueSink)` on one `Tick` from initial
  state must leave `srcCount = 1` and `sinkLast = 0`. (Current code: `sinkLast = 1`.)
- Defect 2: `step (compose pairSource twoPhaseSink)` on `Go` must produce outputs
  `[Stage1 10, Stage2 20]` and final `phase = 2`. (Current code: `[Stage1 10, Stage1 20]`
  and `phase = 1`.)
- Defect 3: `step (compose m2aSource wrongOrderSink)` on the source command must return
  `Just` (the M2A edge fires; the M2B edge simply does not) without raising. Wrap the
  evaluation with `Control.Exception.evaluate` + `try`/`shouldThrow` style so the
  current crash is caught deterministically; before the fix, assert the *current*
  behavior with hspec's pending mechanism or invert the assertion — the committed form
  of this milestone should mark the three tests with a clear
  `-- RED until EP-74 M3/M4/M5` comment and hspec `pendingWith` guards **removed** only
  when the corresponding milestone lands. (Committing failing tests to `master` would
  break CI; use `pendingWith "EP-74 M3"` etc. so the suite stays green while the
  divergence stays documented and one-keystroke re-enableable.)

What exists at the end: the fixtures compile, the spec runs, and flipping any
`pendingWith` off demonstrates the exact divergence predicted above. Acceptance: run
from the repository root

```bash
nix develop --command cabal test keiki-test --test-show-details=direct
```

and observe the suite green with three pending tests naming this plan; temporarily
deleting a `pendingWith` line and re-running shows the corresponding red failure with
the divergent value (capture one transcript into Surprises as evidence).

### Milestone 2 — prototyping: snapshot update semantics and the remedy decision

Scope: *prototyping milestone* (in the PLANS.md sense — additive, testable, with
explicit promote/discard criteria). Change `runUpdate` in `src/Keiki/Core.hs:843-846`
to the snapshot semantics sketched in Context (evaluate all right-hand sides against
the entry register file; apply writes left-to-right so the rightmost write to a slot
wins; preserve `setSlotN`'s strictness). Add a Core-level spec (either extend
`test/Keiki/CoreSpec.hs` or add `test/Keiki/CoreUpdateSnapshotSpec.hs` + cabal
registration) asserting: for `UCombine (USet #x (lit 1)) (USet #y (proj #x))` from
`x = 0`, the result has `y = 0` (snapshot) not `1` (threading); and a self-read
increment `USet #n (proj #n .+ lit 1)` still increments.

Then measure the blast radius: run the full keiki suite; build and test `jitsurei`
(same repo); re-run the focused survey against current keiro and inspect every hit.

Promote criteria: whole keiki suite green except the intentionally-pending M1 tests
and any test that *asserted threading behavior* (fix such a test only if its assertion
contradicts the documented order-independence claim — record each in the Decision
Log); consumer survey still shows no sibling-half register reads. Then keep the change
(it becomes M3's foundation) and update the `runUpdate` haddock (`839-842`) to state
the snapshot semantics precisely, including the write-application order for the
internal duplicated-slot case.

Discard criteria: any real consumer depends on threading, or the suite reveals a
semantic regression that cannot be attributed to reliance on the false doc claim. Then
revert, switch the plan to remedy (c) *now* — a `compose`-time structural check
rejecting any t1 edge that writes a slot its own output reads (walk each
`OutTerm`'s `OutFields` collecting `TReg` positions via `indexInt`
(`src/Keiki/Composition.hs:352-354`) and intersect with the update's written slots
collected by a `writtenSlots`-style walker as in `src/Keiki/Render/Mermaid.hs:919`) —
plus a documented path to (a)/(b) later, and rewrite M3/M4 accordingly (the Decision
Log entry must be superseded, and the M1 defect-1 test's assertion changes from "the
sequential value" to "compose rejects loudly").

Acceptance: the Decision Log contains the promote-or-discard entry with the suite
transcript snippet, and either the snapshot semantics or the structural rejection is on
the branch with its Core spec green.

### Milestone 3 — defect 1 fixed on the single-mid path

Scope: with M2 promoted, defect 1 is largely fixed by `runUpdate` itself — the
composite update's substituted right-hand sides now evaluate against the pre-edge
snapshot, which is exactly what sequential `omega` gave them. This milestone removes
the M1 `pendingWith` guard on the defect-1 test, verifies it green, and audits the
other composition operators for the same assumption: `alternative`
(`src/Keiki/Composition.hs:1112-1198`) never substitutes across the update boundary
(each arm's update is only weakened/lifted), and `feedback1` (`1260-1275`) reduces to
two `compose`s, so both inherit the fix — record the audit conclusion in this plan. If
M2 was discarded, this milestone instead lands the (c) rejection with a
`Keiki.CompositionSpec`-style test asserting the diagnostic message.

Acceptance: `cabal test keiki-test` green with the defect-1 test active; the test's
assertion is the sequential value (`sinkLast = 0`, `srcCount = 1`).

### Milestone 4 — defect 2: chain expansion threads symbolic composed terms

Scope: implement the symbolic environment threading in
`src/Keiki/Composition.hs`. Extend `PartialPath` (`842-848`) with an accumulated write
environment — a list of existential pairs of a written rs2-side index and its
substituted right-hand-side term, e.g.

```haskell
data PendingWrite rs ci where
  PendingWrite ::
    (KnownSymbol s) =>
    IndexN s rs r -> Term rs ci ifs r -> PendingWrite rs ci
```

collected from each step's substituted update (`substUpdate u2 o` produces the
already-weakened `USet`s; harvest them with a small walker). In `stepPath`
(`1031-1046`), before conjoining/chaining step i's substituted guard, update, and
outputs, apply a new rewrite `applyEnvTerm :: [PendingWrite (Append rs1 rs2) ci1] ->
Term (Append rs1 rs2) ci1 ifs r -> Term (Append rs1 rs2) ci1 ifs r` (and its
`Pred`/`Update`/`OutFields` walkers) that replaces `TReg ix` with the environment's
term when `matchIndex` (Context sketch; add `import Data.Type.Equality ((:~:)(..))`)
finds the slot — later environment entries shadow earlier ones for the same slot.
Environment entries must contain **only rs2-side chain writes** (steps' `substUpdate`
results), never t1's `u1` writes — t1's mids are all evaluated against t1's pre-step
snapshot sequentially, and under M2's snapshot `runUpdate` they already are; verify
this invariant with a comment and by construction (`initialPath` seeds an empty
environment; only `stepPath` extends it). Nested `UCombine`s inside one step's
`substUpdate` output are flattened into the environment in left-to-right order.

Note the duplicated-slot case: after threading, a chain in which two steps write the
same rs2 slot produces a composite update writing that slot twice; under M2's
left-to-right write application the later chain step wins, which is the sequential
outcome. Leave the duplicate writes in place (dropping shadowed earlier writes is an
optional simplification — do it only if trivial, and say so in the Decision Log).

If, while prototyping this milestone, the threading proves unsound or intractable
(e.g. the `ifs` realignment cannot be confined to the documented coercion discipline),
implement the honest restriction instead: in `expandPaths`/`stepPath`, detect a step
whose substituted guard/update/output reads an rs2 slot present in the environment and
fail `compose` with a diagnostic `error` naming the slot, the chain position, and the
workaround ("restructure t2 so multi-event chains do not read slots written earlier in
the same chain, or step the transducers separately") — and update the M1 defect-2 test
to assert that diagnostic. Decide honestly; record the decision and the evidence.

Acceptance: `pendingWith` removed from the defect-2 test; `compose pairSource
twoPhaseSink` on `Go` yields `[Stage1 10, Stage2 20]` with final `phase = 2` (or the
documented diagnostic fires, under the fallback); the pre-existing
`test/Keiki/CompositionMultiEventSpec.hs` still passes unchanged (its t2 is stateless,
so its behavior must not move).

### Milestone 5 — defect 3: total substitution and the leaf-level guard shield

Scope: in `src/Keiki/Composition.hs`, replace `substTerm`'s two `error` branches
(`401-424`) with `poisonTerm` (Context sketch) carrying a reworded message that names
the t2-side constructor, the t1-side wire constructor, and the likely cause (a t2
guard/update/output reading a mid constructor this composite edge does not carry). In
`substPred`, add a mismatch pre-check for `PEq` and `PCmp`: if either operand term
contains a `TInpCtorField` whose `icName` differs from `o1`'s `wcName` (a ~10-line
recursive `Bool` walker over `Term`), substitute the whole leaf to `PBot` instead of
recursing into `substTerm`. `PInCtor` handling (`474-479`) is already total and stays.
Do not reorder existing conjuncts — the leaf-level `PBot` makes ordering irrelevant.

Then remove the defect-3 `pendingWith` and extend the spec with walker assertions on
the `m2aSource`/`wrongOrderSink` composite (and on a variant whose *correct-order*
edge reads a field, so a cross-constructor poison exists in output position):
`isSingleValuedSym (withSymPred pipeline)` returns without raising (import pattern as
in `test/Keiki/CompositionSpec.hs:42`), `Keiki.Render.Pretty`'s guard renderer returns
without raising, and `applyEvents`/`reconstitute` on a valid event log succeed (replay
walks every edge's outputs through `solveOutput`; this asserts the poison is never
forced by inversion of *non-matching* wire constructors).

Acceptance: defect-3 test green (composite steps via the M2A edge; no exception);
walker assertions green; grep confirms no `error` call remains in `substTerm`'s
mismatch branch.

### Milestone 6 — the semantic-homomorphism suite

Scope: create `test/Keiki/CompositionHomomorphismSpec.hs` (register in `keiki.cabal`)
with a reusable sequential reference and bounded-exhaustive comparisons. The reference,
written once in the spec:

```haskell
-- The sequential semantics 'compose' must reproduce: run t1's step,
-- then fold t2's step over the emitted mid events in order. Nothing
-- (reject) at any stage is Nothing overall.
sequentialStep t1 t2 (s1, regs1) (s2, regs2) ci = do
  (s1', regs1', mids) <- step t1 (s1, regs1) ci
  let feed (s2c, r2c, acc) m = do
        (s2n, r2n, outs) <- step t2 (s2c, r2c) m
        pure (s2n, r2n, acc <> outs)
  (s2', regs2', outs) <- foldM feed (s2, regs2, []) mids
  pure ((s1', s2'), (regs1', regs2'), outs)
```

Comparisons run over every command sequence of length ≤ 3 drawn from a small pool per
fixture pairing (e.g. for `counterSource ⨾ lastValueSink`: pools of `Tick`; for a
payload-carrying variant, payloads from `[-2, 0, 1, 7]`), for these pairings:
`counterSource ⨾ lastValueSink` (defect 1 regression, now with multi-step folds so the
counter actually advances), `pairSource ⨾ twoPhaseSink` (multi-event, stateful t2),
and the pre-existing register-free pipeline from `test/Keiki/CompositionSpec.hs`
(`alertSource ⨾ emailDelivery`, both exported; this
generalizes that spec's fixed-input equivalence tests to swept inputs — leave the old
spec in place). The `m2aSource ⨾ wrongOrderSink` fixture is an explicit exception:
assert that plain t2 stepping raises its documented field-guard error and that the
composite refines it to the defined `[SawA 5]` step. For each defined sequential
pairing, at every step assert: `step (compose t1 t2)` is
`Just` exactly when `sequentialStep` is (reject-agreement); on `Just`, the composite
vertex equals `Composite s1' s2'`, the outputs list is equal, and every register slot
of the composite file equals the corresponding slot of
`appendRegFile regs1' regs2'` — compare slot-wise through the fixture's typed readers
(no `Eq (RegFile rs)` exists; do not add one in this plan). Thread the fold so later
commands run from the *diverged-or-not* states of both sides independently.

Acceptance: the new spec passes, and a mutation check proves it has teeth — e.g.
temporarily reverting the M2 `runUpdate` change (or the M4 threading) makes at least
one homomorphism case fail with a register or output mismatch naming the slot. Record
the mutation-check transcript snippet in Surprises.

### Milestone 7 — documentation, defect 4, and master plan bookkeeping

Scope: all prose. In `src/Keiki/Composition.hs`: fix the `feedback1` haddock
(`1223-1248`) to state that nesting `feedback1 (feedback1 t f) f` additionally
requires `rs2 ~ '[]` (both the aggregate *and* the policy stateless), with one
sentence of why (the nested call's `Disjoint` constraint ranges over
`Append rs1 (Append rs2 rs1)`); update the `compose` haddock (`850-878`) and the
module header to state the register-snapshot semantics, the chain-threading (or
restriction) behavior, and the leaf-`PBot` refinement for cross-constructor guard
reads. In `src/Keiki/Core.hs`: ensure the `runUpdate`/`combine`/`Update` haddocks
match the shipped semantics (started in M2). Update
`docs/research/composition-combinators-design.md` (the substitution algorithm and
limitations sections — the file's "Substituting a Term / an HsPred / an OutTerm"
sections must describe totality and the snapshot story) and
`docs/research/gsm-widening-design.md` §5 (chain expansion). Add a `CHANGELOG.md`
entry under the unreleased heading describing the behavior changes (update snapshot
semantics; chain threading; total substitution) as breaking-but-consumerless per the
keiro survey. Finally, update the master plan
(`docs/masterplans/16-...md`): registry row 74 status, the EP-74 progress checkbox,
and a Surprises/Decision entry if any fallback was taken. If the release-schedule
fallback was exercised instead of finishing this plan, the module haddock of
`Keiki.Composition` must open with an explicit "**Experimental**" paragraph and the
master plan must record the cut.

Acceptance: `nix fmt -- --no-cache` clean; `cabal build all` haddock-parses (run
`cabal haddock keiki` if in doubt); a reviewer reading only `Keiki.Composition`'s
haddock can predict the emit-then-increment and two-phase-chain outcomes correctly.


## Concrete Steps

All commands run from the repository root `/Users/shinzui/Keikaku/bokuno/keiki` (shown
here as `.`). Enter the dev shell first; GHC is 9.12.

```bash
cd /Users/shinzui/Keikaku/bokuno/keiki
nix develop            # provides cabal, GHC 9.12, z3 for the sbv-backed tests
cabal build all        # keiki, keiki-codec-json, keiki-codec-json-test, jitsurei
cabal test all         # full suite; expect all green before you start
```

Fast iteration on the composition suites while working:

```bash
cabal test keiki-test --test-show-details=direct \
  --test-options='--match Composition'
```

Re-verify the defects before editing (they are claims about the current tree):

```bash
grep -n "UCombine" src/Keiki/Composition.hs | sed -n '1,10p'   # productEdge + stepPath sites
sed -n '843,846p' src/Keiki/Core.hs                            # runUpdate threading
sed -n '889,918p' src/Keiki/Core.hs                            # omega/step pre-state outputs
sed -n '413,424p' src/Keiki/Composition.hs                     # substTerm mismatch error
sed -n '1223,1248p' src/Keiki/Composition.hs                   # feedback1 haddock
```

M1: check for EP-71 fixtures, then add files and register them.

```bash
ls test/Keiki/Fixtures/            # reuse a counter fixture if EP-71 landed one
# create test/Keiki/Fixtures/ComposeStateful.hs
# create test/Keiki/CompositionStatefulSpec.hs
# edit keiki.cabal: add both to the keiki-test other-modules list (alphabetical)
cabal test keiki-test --test-show-details=direct --test-options='--match Stateful'
```

Expected M1 transcript shape (three pendings, no failures):

```text
Keiki.CompositionStatefulSpec
  compose counterSource lastValueSink
    stores the pre-increment count in the sink [✐]
      # PENDING: EP-74 M3
  compose pairSource twoPhaseSink
    fires edge1 then edge2 and ends at phase 2 [✐]
      # PENDING: EP-74 M4
  compose m2aSource wrongOrderSink
    steps via the M2A edge without raising [✐]
      # PENDING: EP-74 M5
```

M2: apply the `runUpdate` change, then run the suite and the consumer survey.

```bash
cabal test all
# survey: sibling-half register reads in keiki and current keiro
grep -rn "USet.*proj\|USet.*TReg\|=:.*reg\|\.=.*reg @\|=:.*proj\|\.=.*proj" \
  --include='*.hs' src test jitsurei/src \
  /Users/shinzui/Keikaku/bokuno/keiro 2>/dev/null \
  | grep -v "Composition.hs"
# every hit must be a self-read (increment) or a rendering-only fixture;
# anything else blocks promotion — record it and follow the discard path.
```

M3–M5: remove the corresponding `pendingWith`, implement, iterate with the `--match`
command above. M6: add the homomorphism spec, register it, run:

```bash
cabal test keiki-test --test-show-details=direct --test-options='--match Homomorphism'
```

Final gate, plus formatting (the canonical fourmolu config is `./fourmolu.yaml`; the
`--no-cache` flag matters — see the memory note about silent style drift):

```bash
cabal build all && cabal test all
nix fmt -- --no-cache
git status --short   # only intended files
```

Commit per milestone, conventional commits, on the current branch (no feature branch
unless asked), e.g.:

```text
test(composition): pin stateful compose divergence (EP-74 M1)
fix(core): snapshot semantics for UCombine right-hand sides (EP-74 M2/M3)
fix(composition): thread symbolic writes through chain expansion (EP-74 M4)
fix(composition): total substitution with leaf-level PBot shield (EP-74 M5)
test(composition): bounded-exhaustive semantic homomorphism suite (EP-74 M6)
docs(composition): snapshot semantics, chain threading, feedback1 nesting (EP-74 M7)
```


## Validation and Acceptance

The plan is done when a novice can demonstrate, from a clean checkout inside
`nix develop`, all of the following:

1. `cabal test all` is green with **no** `pendingWith` guard remaining in
   `test/Keiki/CompositionStatefulSpec.hs`.
2. Emit-then-increment agrees with sequential semantics: in the stateful spec, after
   one `Tick` through `compose counterSource lastValueSink`, the sink's slot holds the
   *pre-increment* count (`0` from a fresh start) and the source's counter holds `1`.
   Reverting the `runUpdate` change (a one-clause `git stash`-able edit) makes exactly
   this test fail with `1 ≠ 0` — beyond-compilation proof the fix is load-bearing.
3. The stateful multi-event chain agrees (or is loudly rejected, if the recorded
   fallback was taken): `compose pairSource twoPhaseSink` on `Go` emits
   `[Stage1 10, Stage2 20]` and lands at `phase = 2`.
4. A hand-written wrong-order guard no longer crashes the composite: the
   `m2aSource ⨾ wrongOrderSink` pipeline steps normally, and
   `isSingleValuedSym`/pretty-rendering/replay over that pipeline complete without
   raising.
5. The homomorphism suite in `test/Keiki/CompositionHomomorphismSpec.hs` passes: over
   every enumerated command sequence, `step (compose t1 t2)` and the in-spec
   `sequentialStep` reference agree on accept/reject, composite vertex, full register
   contents (slot-wise), and the output list — for the stateful, multi-event, and
   pre-existing register-free fixtures alike.
6. `haddock`-visible documentation matches behavior: `feedback1`'s nesting paragraph
   states the `rs2 ~ '[]` requirement; `runUpdate`'s haddock describes snapshot
   evaluation; `compose`'s haddock describes chain threading (or the restriction) and
   the leaf-`PBot` refinement.
7. The master plan registry row for EP-74 and its progress checkbox reflect the final
   state, and every deviation taken en route is in this plan's Decision Log.


## Idempotence and Recovery

Every step is safe to repeat. Fixture and spec files are additive; re-running `cabal
test` is side-effect-free; `nix fmt -- --no-cache` is idempotent. The two risky edits
are (i) the `runUpdate` semantics change and (ii) the chain-expansion rewrite — both
are single-file, and each milestone boundary is a commit, so recovery is `git revert`
of the offending commit (never `reset --hard` on shared history). If M2's prototype is
discarded, the recovery path is written into the milestone itself (revert, switch to
remedy (c), rewrite M3/M4, supersede the Decision Log entry). If a Phase 1/2 plan of
the master plan lands mid-flight and shifts line numbers or the fixture layout,
re-verify the citations in Context against the tree before continuing — the defect
descriptions are behavioral and survive line drift. The `pendingWith` discipline in M1
guarantees the suite is never committed red.


## Interfaces and Dependencies

No new package dependencies. Everything uses what `keiki.cabal` already declares:
`base`, `hspec` (test suite), `sbv` via `Keiki.Symbolic` for the single-valuedness
assertions, and `Data.Type.Equality` from `base` for the `matchIndex` witness.

Modules touched and the shapes that must exist at the end:

- `src/Keiki/Core.hs` — `runUpdate :: Update rs w ci -> RegFile rs -> ci -> RegFile rs`
  keeps its signature; only the `UCombine` evaluation strategy changes (snapshot
  right-hand sides, ordered writes, `setSlotN` strictness preserved). No `Update`
  constructor is added or removed (unless M2's discard path forces `UPar`, which must
  then be threaded through the walkers listed in the Decision Log and recorded here).
- `src/Keiki/Composition.hs` — `compose`, `alternative`, `feedback1` keep their public
  signatures exactly (`compose`'s composite register file stays `Append rs1 rs2`).
  New internal helpers: `matchIndex :: IndexN s rs a -> Index rs b -> Maybe (a :~: b)`;
  `poisonTerm :: String -> Term rs ci ifs r`; `PendingWrite rs ci` and
  `applyEnvTerm`/`applyEnvPred`/`applyEnvUpdate`/`applyEnvOutFields` (names indicative;
  keep them unexported unless a test needs one, in which case export under the existing
  "exposed for advanced uses" section). `substTerm`/`substPred`/`substUpdate`/`substOut`
  keep their exported signatures but become total.
- `test/Keiki/Fixtures/ComposeStateful.hs` (new) — exports the four fixture
  transducers, their command/mid/output types, and typed slot readers; written for
  reuse by EP-71/EP-73 (plain transducer values, no spec imports).
- `test/Keiki/CompositionStatefulSpec.hs`, `test/Keiki/CompositionHomomorphismSpec.hs`
  (new) — hspec specs auto-discovered by `test/Spec.hs`; both, plus the fixture module,
  added to the `keiki-test` `other-modules` list in `keiki.cabal`.
- Documentation: `docs/research/composition-combinators-design.md`,
  `docs/research/gsm-widening-design.md`, `CHANGELOG.md`,
  `docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md`.

Related plans (context only; this plan is self-contained): EP-71 owns the shared
fixture integration point and the validation-warning vocabulary; EP-73 owns the
generalized replay round-trip property harness; EP-75 (hard-dependent on this plan)
documents and validates the composition laws this plan finalizes — coordinate by
finishing this plan's Decision Log before EP-75 starts.

---

Revision note (2026-07-11): replaced the skeleton's placeholder content with the full
plan: verified all four review defects against the current tree with file:line
evidence, added the authoring-time consumer blast-radius survey, selected snapshot
update semantics as the leading remedy with an explicit prototyping milestone and
recorded fallbacks (compose-time rejection now, shadow slots later; chain restriction
for multi-event), designed the stateful fixtures and the bounded-exhaustive
semantic-homomorphism suite, and recorded the master plan's experimental-marking
release fallback. Reason: this is the initial authoring pass for Phase 3 of master
plan 16.
