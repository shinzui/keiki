---
id: 26
slug: single-step-feedback-combinator-on-symtransducer
title: "Single-step feedback combinator on SymTransducer"
kind: exec-plan
created_at: 2026-05-03T01:53:06Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
master_plan: "docs/masterplans/8-composition-combinators-beyond-sequential-parallel-alternative-feedback-kleisli.md"
---


# Single-step feedback combinator on SymTransducer

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this change, an aggregate author can express a **single round
of aggregate ↔ stateless-policy reaction** with one library call:

    loop :: SymTransducer ... ci co
    loop = feedback1 aggregate policy

Where `aggregate :: SymTransducer ... ci co` is the user's
event-sourced aggregate and `policy :: SymTransducer ... co ci` is
a stateless reactor that observes one of the aggregate's events and
emits one follow-up command. `feedback1` runs:

    aggregate → policy → aggregate (one more time)

per external command, with the final aggregate event as the
composite's output. There is no loop and no fuel parameter — single
step is the entire semantics. Multi-round patterns nest:

    twoRoundLoop = feedback1 (feedback1 aggregate policy) policy

The composite preserves all three load-bearing keiki analyses
(`solveOutput`, `checkHiddenInputs`, `isSingleValuedSym`) end-to-end
because it is implemented as two `compose` applications stacked
(`compose t (compose policy t')`, where `t'` is a re-keyed copy of
`t` to keep the symbolic analysis from incorrectly merging the two
aggregate copies).

The user-visible behavior:

- Aggregate ↔ policy patterns from
  `docs/research/orchestration-sagas-choreography-and-feedback-loops-as-transducers.md`
  §5 are expressible without hand-rolling event/command plumbing.
- Round-trip replay over the composite produces the cascaded event
  stream the runtime would have produced via separate aggregate
  and policy invocations.
- `checkHiddenInputs (feedback1 t f)` returns the union of t's,
  f's, and t's-second-copy warnings.
- `isSingleValuedSym (withSymPred (feedback1 t f))` returns `True`
  when t and f are individually single-valued.

How a reader sees it working:

    cabal test --test-show-details=streaming \
        --test-options "--match Keiki.CompositionFeedback1Spec"

reports the new spec passing with cases for: single-step cascade,
round-trip replay, `checkHiddenInputs`, `isSingleValuedSym`.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] **M0 — Confirm starting state.** Run `cabal build all` and
  `cabal test all`; both green. Record GHC version. (Should be
  9.12.3 per `keiki.cabal`'s `tested-with`.)
- [ ] **M1 — Decide on the re-keying mechanism for the second
  copy of t.** Either (a) a vertex newtype `T2 s1 = T2 !s1` that
  the implementation wraps t's vertex on its second appearance, or
  (b) symbolic indexing where the composite vertex is structurally
  `Composite s1 (Composite s2 s1)` and the inner `s1` is treated
  as distinct by `isSingleValuedSym`'s per-vertex enumeration. The
  decision is logged in this plan's Decision Log.
- [ ] **M2 — Add the re-keying machinery.** If (a) is chosen, add
  `data T2 s1 = T2 !s1` with the same instance set as `Composite`
  / `CompositeSum`. If (b), no new type is needed; the existing
  `Composite` plus the existing `compose` machinery suffice.
- [ ] **M3 — Add the `feedback1` combinator.** Implement as
  `feedback1 t f = compose t (compose f tCopy)` where `tCopy` is t
  with vertex re-keyed. Confirm the type signature matches the
  design record.
- [ ] **M4 — Acceptance test.** Add
  `test/Keiki/CompositionFeedback1Spec.hs` composing a fixture
  aggregate with a stateless one-vertex policy (defined inline)
  and verifying step / cascade / reconstitute / checkHiddenInputs
  / isSingleValuedSym.
- [ ] **M5 — Wire spec into test suite.** Add the new module to
  `keiki.cabal`'s `keiki-test` `other-modules` and to
  `test/Spec.hs`. Run `cabal test all` and confirm the new cases
  pass.
- [ ] **M6 — Update design note and MP-8.** Append a "What we
  shipped" subsection under
  `docs/research/composition-combinators-design.md`'s `feedback1`
  section. Mark this EP "Complete" in MP-8's Exec-Plan Registry;
  tick the corresponding entry in MP-8's Progress section.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Adopt the design from EP-24's per-combinator design
  record at `docs/research/composition-combinators-design.md`'s
  `feedback1` section without revision.
  Rationale: EP-24 ran the design pass with full context. Any
  deviation found during implementation gets logged as a new
  decision here and back-propagated to the design note.
  Date: 2026-05-03

- Decision: This EP ships **single-step `feedback1`** only. A
  bounded-step variant (`feedbackN n t f`) is documented as a
  future extension but is not in scope.
  Rationale: Per EP-24's M2 verdict — single-step is the smallest
  reduction that preserves the keiki guarantees, and bounded-step
  can be added later without disturbing the single-step API.
  Date: 2026-05-03


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

The reader has the working tree at the keiki repository root and
nothing else.

### What keiki is, in one paragraph

`keiki` is a pure-core Haskell library that models a single
event-sourced aggregate as a **symbolic-register transducer**: a
finite control graph, an existentially-typed register file `RegFile
rs` indexed by a type-level slot list `rs :: [Slot]`, and edges that
carry a guard predicate `phi`, a register update term, an optional
output term, and a target vertex. The library lives entirely in
`src/Keiki/` and exposes its types and operations through the
modules listed in `keiki.cabal`'s `exposed-modules`. It has no `IO`.

### What `compose` already does

`src/Keiki/Composition.hs` exports the existing sequential
combinator `compose` (defined at line 383). It walks t2's AST and
substitutes `mid`-reads with structural references to t1's edge
output, building a composite `SymTransducer` whose vertex is
`Composite s1 s2` (a strict-product newtype at line 64) and whose
register file is `Append rs1 rs2`. The substitution machinery —
`WeakenR`, `weakenL`, `weakenLTerm`, `weakenLPred`, `weakenLUpdate`,
`substTerm`, `substPred`, `substUpdate`, `substOut`,
`substOutFields` — is exported for advanced uses and is reused by
`feedback1` indirectly (through the two stacked `compose`
applications).

The full design record for `compose` is at
`docs/research/composition-combinators-design.md`. Read its
"`compose` — type signature", "`compose` — semantics", "Substitution
algorithm", and "How the composite preserves the three guarantees"
sections before starting M3.

### What this plan adds

A combinator `feedback1` that is operationally `compose t (compose
policy t')` for a stateless policy and a re-keyed copy `t'` of the
aggregate `t`. The design record for `feedback1` is at
`docs/research/composition-combinators-design.md` under "Combinators
beyond `compose` — per-combinator design records" → "`feedback1` —
admitted (single-step reduction)". Read the four subsections
(Signature, Semantics, Single-step example, Preservation arguments)
before starting M3.

### Why "re-keying" is needed

If we wrote `feedback1 t f = compose t (compose f t)` directly, the
two copies of t would share a vertex type `s1`. The
`isSingleValuedSym` analysis enumerates `[minBound .. maxBound :: s
]` for each composite vertex; the inner `s1` would be conflated with
the outer `s1`, and a vertex like `Composite a (Composite x a)`
would be analysed as if both `a`s were the same automaton state.
This is incorrect: each `a` is a distinct point in the composite's
state space.

The re-keying makes the second copy of t use a distinct vertex
type. Two implementation styles:

- **(a) Newtype wrap.** `data T2 s1 = T2 !s1`. The implementation
  wraps t's vertex on its second appearance: `compose t (compose f
  (renamed t))`, where `renamed t` is t with `target = T2 . target`
  and `initial = T2 (initial t)`. The composite's vertex is
  `Composite s1 (Composite s2 (T2 s1))`.
- **(b) Implicit by structure.** Use the existing `Composite` shape
  recursively: `Composite s1 (Composite s2 s1)`. The inner `s1` is
  the same Haskell type but is positioned distinctly in the
  composite's vertex tuple, and `isSingleValuedSym`'s per-vertex
  enumeration walks the full product. **This is the same as (a) at
  the type level — `Composite s1 (Composite s2 s1)`'s inner `s1`
  has its own `Bounded`/`Enum` enumeration position.** No newtype
  needed.

The implementation EP picks (b) — implicit by structure — by
default, because (a) would force an extra `Bounded` / `Enum` /
`NoThunks` instance set for `T2` without observable benefit. M1 of
this plan re-evaluates the choice if (b) reveals a problem.

### The three load-bearing analyses

Each new combinator must preserve all three on the composite:

1. **`solveOutput`** at `src/Keiki/Core.hs:730`. Mechanical
   inversion of an `OutTerm rs ci co` plus a `RegFile rs` plus an
   observed `co`, producing the `ci` that produced it. Walks the
   structural `OPack` form (post-MP-6 — `OFn` was retired in EP-16
   and is not in the current core).
2. **`checkHiddenInputs`** at `src/Keiki/Core.hs:786`. Walks every
   edge and flags ε-edges whose update reads input, edges whose
   `OutFields` chain doesn't visit every slot of the named
   `InCtor` (a hidden input that breaks event-sourced replay).
3. **`isSingleValuedSym`** at `src/Keiki/Symbolic.hs:384`. For each
   reachable composite vertex, checks that every distinct pair of
   outgoing edges has an `isBot` (unsatisfiable) guard conjunction.
   `BoolAlg phi`-polymorphic; with `SymPred` (lifted via
   `withSymPred` at `src/Keiki/Symbolic.hs:407`) the `isBot` is
   SBV/Z3-backed.

### Why it's pure (no iteration model needed)

`docs/research/effects-boundary.md` pins effects to the runtime
layer. An iterate-until-quiescence loop is itself an effect because
it can diverge. `feedback1`'s single-step semantics has no loop —
it runs `compose · compose` exactly once — so termination is
trivial. The pure-core boundary is preserved.

Multi-round patterns are expressible by nesting `feedback1`s. The
nesting is finite by construction (the user writes a fixed number
of `feedback1` applications) and adds one round per nesting level.


## Plan of Work

Six milestones. Each is independently verifiable.

### M0 — Confirm starting state

**Scope.** Establish the green baseline. No code changes.

**Commands (working directory: repository root).**

    cabal build all
    cabal test all
    ghc --version

**Acceptance.** Both `cabal` commands succeed (exit 0). Test
summary: 169 examples, 0 failures (or higher, if EP-25 has landed
first — see "Coordination with EP-25" below). GHC version matches
`keiki.cabal`'s `tested-with: GHC == 9.12.*` (currently 9.12.3).

### M1 — Decide on the re-keying mechanism for the second copy of t

**Scope.** A small design pass: review whether the implicit
structural form (`Composite s1 (Composite s2 s1)`) suffices, or
whether a `T2 s1` newtype is needed for clarity. This milestone
adds no code; it logs the decision in this Decision Log.

**Acceptance.** A new entry in this Decision Log naming the chosen
form and rationale.

### M2 — Add the re-keying machinery (if needed)

**Scope.** If M1 chose newtype-style (a), add `data T2 s1 = T2
!s1` with the same instance set as `Composite` (lines 64–100 of
`src/Keiki/Composition.hs`). If M1 chose implicit-structural (b),
this milestone is a no-op and is closed immediately.

**Acceptance.** Either: a new `T2` data type is exported from
`Keiki.Composition` with the right instances, OR the milestone is
closed with a "no-op per M1" entry in Progress.

### M3 — Add the `feedback1` combinator

**Scope.** Implement as two stacked `compose` applications.

**Edit target.** `src/Keiki/Composition.hs`. Add a "* feedback1"
section after the existing "* compose" section (line 354) — or
after `alternative`'s section if EP-25 has landed first. Add
`feedback1` to the export list.

**What will exist at the end.** The `feedback1` function with the
signature in the design record:

    feedback1
      :: forall rs1 rs2 s1 s2 ci co.
         ( WeakenR rs1
         , Disjoint (Names rs1) (Names rs2)
         , WeakenR (Append rs1 rs2)
         , Disjoint (Names (Append rs1 rs2)) (Names rs1)
         )
      => SymTransducer (HsPred rs1 ci)  rs1 s1 ci  co
      -> SymTransducer (HsPred rs2 co)  rs2 s2 co  ci
      -> SymTransducer (HsPred (Append rs1 (Append rs2 rs1)) ci)
                       (Append rs1 (Append rs2 rs1))
                       (Composite s1 (Composite s2 s1))
                       ci
                       co

**Implementation sketch.**

    feedback1 t f = compose t (compose f t)

The signature's nested `Composite` and nested `Append` reflect the
stacked `compose`. The constraints — `WeakenR rs1`,
`WeakenR (Append rs1 rs2)`, `Disjoint` for both halves — propagate
from `compose`'s constraints applied twice.

If the type-level constraints don't resolve cleanly, the
implementation EP introduces helper type aliases or partial-application
forms; the M1 decision determines which.

**Acceptance.** `cabal build all` clean. Unit acceptance is via M4.

### M4 — Acceptance test

**Scope.** A new spec module that exercises every preservation
property the design record promises.

**Edit target.** New file
`test/Keiki/CompositionFeedback1Spec.hs`. Pattern matches
`test/Keiki/CompositionSpec.hs` (the existing `compose` spec).
Compose `Keiki.Examples.UserRegistration` (or a smaller fixture)
with a stateless one-vertex policy defined inline. The policy
observes one event type and emits one follow-up command type.

**Tests to author** (from the design record's "Acceptance criteria
for the implementation EP"):

- The single-step cascade produces the expected composite output
  for a sample external command. Concretely: feed
  `t.initial → command → t.s_intermediate → policy reacts →
  policy_command → t.s_intermediate → final command processing →
  t.s_final` and observe the final aggregate output emerging from
  the composite.
- `reconstitute composite final-event-log` lands at the expected
  composite final state.
- `checkHiddenInputs (feedback1 t f)` returns `[]` (or the
  expected non-empty list when the fixture intentionally contains
  a hidden input — pick a clean fixture for the happy-path test).
- `isSingleValuedSym (withSymPred (feedback1 t f))` returns
  `True`.

**Commands.**

    cabal test --test-show-details=streaming \
        --test-options "--match Keiki.CompositionFeedback1Spec"

**Acceptance.** All four test cases pass.

### M5 — Wire spec into test suite

**Scope.** Make the spec discoverable by hspec.

**Edit targets.** `keiki.cabal` (`keiki-test`'s `other-modules`)
and `test/Spec.hs` (the hspec auto-discovery file or the
hand-listed spec runner).

**Commands.**

    cabal test all

**Acceptance.** The full suite (170+ examples now) passes with no
regressions.

### M6 — Update design note and MP-8

**Scope.** Append a "What we shipped" subsection under
`docs/research/composition-combinators-design.md`'s `feedback1`
section. Mark this EP "Complete" in MP-8's Exec-Plan Registry. Tick
the corresponding entry in MP-8's Progress section.

**Edit targets.**

- `docs/research/composition-combinators-design.md` — under
  "`feedback1` — admitted (single-step reduction)", add a "What we
  shipped" subsection.
- `docs/masterplans/8-composition-combinators-beyond-sequential-parallel-alternative-feedback-kleisli.md`
  — registry status update for this EP; Progress checkbox tick.
- `docs/research/keiki-generics-design.md` — extend item F's "In
  progress (see EP-24 / MP-8)" paragraph to note the `feedback1`
  shipped.

**Acceptance.** A reader can locate every artefact this EP
produced from the registry and the design note.


## Concrete Steps

Run from the repository root.

Build and run all tests:

    cabal build all
    cabal test all

Run only the new spec while iterating:

    cabal test --test-show-details=streaming \
        --test-options "--match Keiki.CompositionFeedback1Spec"

### Coordination with EP-25

EP-25 (`docs/plans/25-alternative-composition-combinator-on-symtransducer.md`)
also edits `src/Keiki/Composition.hs` and adds a sibling spec file.
EP-25 and this EP are independent (no hard dependency), but they
should be merged in series rather than in parallel to avoid trivial
merge conflicts in `Keiki.Composition`'s export list and the
`-- * compose` haddock section ordering. If EP-25 lands first, this
EP's M3 places the `feedback1` section after `alternative`'s; if
this EP lands first, M6 of EP-25 places `alternative`'s section
between `compose` and `feedback1`.


## Validation and Acceptance

Acceptance is observable via `cabal test all`:

1. The full suite passes with no regressions vs M0's baseline.
2. The new `Keiki.CompositionFeedback1Spec` reports its four test
   cases all green:

       Keiki.CompositionFeedback1Spec
         feedback1 cascade
           single external command produces the expected composite output [✔]
         feedback1 round-trip
           reconstitute on the canonical event log lands at the expected state [✔]
         feedback1 analyses
           checkHiddenInputs returns [] [✔]
           isSingleValuedSym (withSymPred composite) returns True [✔]

3. `git diff src/Keiki/Composition.hs` shows additive changes only
   (no rewrites of `compose`'s substitution machinery). The
   existing `compose` tests still pass.

4. `git diff docs/research/composition-combinators-design.md`
   shows only the "What we shipped" subsection added.

Beyond compilation and tests, a peer reading the new spec can see
the cascade behavior on a concrete event log without consulting any
other file.


## Idempotence and Recovery

The implementation steps are additive to `src/Keiki/Composition.hs`
and additive in `test/`. Reverting any one milestone is safe via
`git revert`.

If M3's type-level constraints don't resolve cleanly, the most
likely cause is that the nested `WeakenR (Append rs1 rs2)`
constraint requires an explicit `WeakenR` instance for `Append`-of-
two-`WeakenR`-instances. If so, the implementation EP adds the
instance to `Keiki.Composition` (it follows mechanically from the
existing `instance WeakenR rs1 => WeakenR ('(s, t) ': rs1)` by
induction on `Append`). Log the addition in this Decision Log.

If `cabal test all` reveals `isSingleValuedSym` returning `False`
on the composite when both halves are individually `True`, the
likely cause is the re-keying decision (M1) being wrong — i.e.
the inner copy of t is being merged with the outer at the
symbolic level. Investigate by inspecting the composite's vertex
enumeration and confirming each vertex has the expected pair of
distinct s1 components. Revisit M1 in this Decision Log with the
revised choice.


## Interfaces and Dependencies

This plan introduces no new package dependencies. It edits the
following:

**Read:**

- `src/Keiki/Composition.hs` — for the `compose` precedent and the
  substitution machinery.
- `src/Keiki/Core.hs` — for `Edge`, `SymTransducer`, `OutTerm`,
  `Update`, `HsPred`, `solveOutput`, `checkHiddenInputs`.
- `src/Keiki/Symbolic.hs` — for `isSingleValuedSym`, `withSymPred`.
- `src/Keiki/Generics.hs` — for `Append`, `appendRegFile`, `Names`,
  `Disjoint`.
- `test/Keiki/CompositionSpec.hs` — for the `AlertSource` fixture
  pattern and the spec style.
- `docs/research/composition-combinators-design.md` — the
  authoritative design record for `feedback1`.
- `docs/research/orchestration-sagas-choreography-and-feedback-loops-as-transducers.md`
  — the orchestration patterns motivating feedback.

**Write:**

- `src/Keiki/Composition.hs` — add `feedback1` (and possibly `T2`
  re-keying newtype if M1 chooses (a)).
- `test/Keiki/CompositionFeedback1Spec.hs` — the new spec module.
- `keiki.cabal` and `test/Spec.hs` — wire the spec into the suite.
- `docs/research/composition-combinators-design.md` — append "What
  we shipped" subsection.
- `docs/research/keiki-generics-design.md` — extend item F's MP-8
  paragraph.
- `docs/masterplans/8-composition-combinators-beyond-sequential-parallel-alternative-feedback-kleisli.md`
  — registry status + Progress tick.

**Required signatures at the end of M3:**

    feedback1
      :: forall rs1 rs2 s1 s2 ci co.
         ( WeakenR rs1
         , Disjoint (Names rs1) (Names rs2)
         , WeakenR (Append rs1 rs2)
         , Disjoint (Names (Append rs1 rs2)) (Names rs1)
         )
      => SymTransducer (HsPred rs1 ci)  rs1 s1 ci  co
      -> SymTransducer (HsPred rs2 co)  rs2 s2 co  ci
      -> SymTransducer (HsPred (Append rs1 (Append rs2 rs1)) ci)
                       (Append rs1 (Append rs2 rs1))
                       (Composite s1 (Composite s2 s1))
                       ci
                       co

**Git trailers.** Every commit must include:

    MasterPlan: docs/masterplans/8-composition-combinators-beyond-sequential-parallel-alternative-feedback-kleisli.md
    ExecPlan: docs/plans/26-single-step-feedback-combinator-on-symtransducer.md
    Intention: intention_01knjzws4qezz9w8b0743zfqv8
