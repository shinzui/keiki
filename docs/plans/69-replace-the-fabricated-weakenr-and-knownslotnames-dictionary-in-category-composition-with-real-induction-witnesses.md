---
id: 69
slug: replace-the-fabricated-weakenr-and-knownslotnames-dictionary-in-category-composition-with-real-induction-witnesses
title: "Replace the fabricated WeakenR and KnownSlotNames dictionary in Category composition with real induction witnesses"
kind: exec-plan
created_at: 2026-07-12T04:16:45Z
intention: "intention_01kxc5whw1en3ra4nh728m53ka"
master_plan: "docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md"
---

# Replace the fabricated WeakenR and KnownSlotNames dictionary in Category composition with real induction witnesses

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.

This plan is Phase 1 of the master plan at
`docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md`
(EP-69 in its registry). That master plan gates the `0.1.0.0` Hackage release: this
defect is one of the two findings from the 2026-07 architecture review where the
compiler's guarantees are actually subverted, so the release is held until this plan
is complete.


## Purpose / Big Picture

keiki is a pure event-sourcing core. Its central value is the *symbolic-register
transducer* (`SymTransducer` in `src/Keiki/Core.hs:638-643`): a finite state machine
whose transitions read and write a typed, heterogeneous tuple of named "registers".
`src/Keiki/Profunctor.hs` wraps that concrete type in an existential wrapper,
`SomeSymTransducer`, and gives the wrapper a `Control.Category.Category` instance so
users can chain transducers with the ordinary `(.)` operator.

Today that instance is unsound. To satisfy the compiler at the existential boundary,
`src/Keiki/Profunctor.hs:392-396` *fabricates* a typeclass dictionary with
`unsafeCoerce` — and the two classes involved carry methods, so the fabricated
dictionary carries the *wrong method implementations*, not merely wrong static
evidence. The concrete consequence: composing three stateful transducers with the
right-associative `c . b . a` produces a composite whose third stage reads and writes
the *wrong register slots* — silently wrong values when the slot types coincide,
undefined behavior (a value of one type reinterpreted as another, potentially a
segfault) when they do not. A second consequence: the runtime slot-name overlap check
that guards `(.)` is silently disabled for nested composites, so the one safety net
the module documents is gone exactly when it is needed.

After this plan, the fabricated dictionary is deleted and replaced by *real*
evidence: a small value-level induction witness for the register-slot list, packed
into the wrapper at construction time (where the compiler can still see the concrete
types), plus lemma functions that build evidence for a composite's slot list by
structural recursion on the witnesses — every step of which the compiler checks. The
observable outcomes: a new three-stage stateful pipeline test proves `(c . b) . a`
and `c . (b . a)` behave identically over multiple steps (they do not today); the
overlap check fires on nested composites (it does not today); and `left'`/`right'`
results compose correctly afterwards. `grep -n unsafeCoerceWrapperDict src/` returns
nothing.

The keiro consumer survey (2026-07, recorded in the master plan) found **zero
downstream users** of `SomeSymTransducer`, the Category/Profunctor/Choice/Strong/Arrow
instances, and every composition operator. The wrapper's internal representation and
the constraints on its constructor may therefore change freely.


## Progress

Use this checklist to track granular steps. Every stopping point must be documented
here, splitting partially-done items into "done" and "remaining" parts as needed.

- [x] (2026-07-12 01:13 PDT) M1: `test/Keiki/Fixtures/CounterPipeline.hs` created with three stateful stages and registered in `keiki.cabal`
- [x] (2026-07-12 01:13 PDT) M1: vacuous associativity test at `test/Keiki/CategorySpec.hs:118-125` replaced with the real three-stage stateful test
- [x] (2026-07-12 01:13 PDT) M1: nested-composition slot-correctness regression test added to `test/Keiki/CategorySpec.hs`
- [x] (2026-07-12 01:13 PDT) M1: composite-slot-names and nested-overlap regression tests added to `test/Keiki/CategorySpec.hs`
- [x] (2026-07-12 01:13 PDT) M1: `left'`/`right'` compose-afterwards tests added to `test/Keiki/ChoiceSpec.hs`
- [x] (2026-07-12 01:13 PDT) M1: targeted suite run; five new tests failed against the current code and the actual corruptions are recorded below
- [x] (2026-07-12 01:17 PDT) M2: witness toolkit (`SlotListWitness`, `KnownSlots`, `appendWitness`, `withKnownSlots`, `withDisjointNil`, `witnessNames`) added to `src/Keiki/Composition.hs` and exported
- [x] (2026-07-12 01:18 PDT) M2: witness-toolkit sanity assertions added; targeted `slot-list` run passed 3 examples with 0 failures
- [x] (2026-07-12 01:23 PDT) M3: `SomeSymTransducer` repacked over `KnownSlots`; `composeWrappers`, `leftWrap`, `rightWrap` rewritten; `DictWrapper`/`unsafeCoerceWrapperDict` deleted
- [x] (2026-07-12 01:24 PDT) M3: full test suite green, including every M1 test; keiki reported 380 examples and 0 failures
- [x] (2026-07-12 01:26 PDT) M4: haddocks corrected (wrapper docs, `unsafeCoerceDisjointness` docs, module header)
- [x] (2026-07-12 01:26 PDT) M4: `CHANGELOG.md` entry written; master plan registry row 69 and its two progress boxes updated
- [x] (2026-07-12 01:30 PDT) M4: `nix fmt -- --no-cache` clean on a second run; final `cabal build all && cabal test all` green; work committed

## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation, with concise evidence (test output is ideal).

- Observation: the fail-before Category run matched the predicted corruption exactly.
  `c . (b . a)` emitted `[MsgD 3, MsgD 15, MsgD 25]` while `(c . b) . a` emitted
  the correct `[MsgD 3, MsgD 14, MsgD 19]`; the nested wrapper reported `[]` rather
  than `["regA", "regB", "regC"]`; and composing the conflicting `regA` stage did
  not raise `CategoryOverlapError`.
  Evidence: `cabal test keiki-test --test-show-details=direct --test-options='--match Keiki.Profunctor'`
  reported the three value/name mismatches and the missing exception on 2026-07-12.

- Observation: the fail-before Choice behavior is asymmetric. Composing two `left'`
  results produced the predicted final `Left (MsgD 6)` instead of `Left (MsgD 5)`,
  but the corresponding `right'` composition already produced the correct sequence.
  `Append '[] rs` reduces definitionally to `rs`, so GHC can retain enough real
  structure on this path despite the unnecessary fabricated dictionary. The test is
  retained to prevent a future regression, and M3 still removes the coercion because
  it is unjustified and unnecessary.


## Decision Log

- Decision: represent the induction witness as a class `KnownSlots rs` whose single
  method returns a singleton GADT `SlotListWitness rs`, with `WeakenR rs` and
  `KnownSlotNames rs` as superclasses, and pack only `KnownSlots rs` (plus the
  existing `Bounded s, Enum s`) in `SomeSymTransducer` — rather than packing a bare
  witness field next to the two existing class constraints.
  Rationale: the task offered two shapes: (a) witness + a lemma returning a `Dict` of
  both classes, (b) deriving the instances from the witness on demand. The superclass
  form is shape (b) with the ergonomics of shape (a): pattern-matching the wrapper
  still brings `WeakenR rs` and `KnownSlotNames rs` into scope automatically (GHC
  extracts superclass dictionaries), so every existing use site — `compose`'s
  `WeakenR rs1` constraint, the `slotNames` overlap check, all five spec files that
  match on the constructor — keeps compiling unchanged; and no separate `Dict` type
  needs to be invented, because the one CPS discharger `withKnownSlots` delivers all
  three constraints at once. A bare witness field would force CPS plumbing at every
  pattern-match site; packing three separate constraints plus a witness would be
  redundant. Zero downstream consumers make the constructor-signature change free.
  Date: 2026-07-12

- Decision: host the entire witness toolkit in `src/Keiki/Composition.hs`, next to
  `WeakenR`.
  Rationale: `KnownSlots`'s superclass `WeakenR` is defined in `Keiki.Composition`,
  so the class cannot live earlier in the module graph; `appendWitness` needs the
  `Append` family from `Keiki.Generics`, which `Keiki.Composition` already imports
  (`src/Keiki/Composition.hs:88`); splitting the type into `Keiki.Core` and the class
  into `Keiki.Composition` would scatter a seven-definition toolkit across three
  modules for no benefit. One module keeps the induction story readable in one place.
  Date: 2026-07-12

- Decision: keep `unsafeCoerceDisjointness` at exactly one call site
  (`composeWrappers`), and eliminate its two other call sites (`leftWrap`,
  `rightWrap`) with a real induction lemma / definitional reduction.
  Rationale: `Disjoint` (`src/Keiki/Internal/Slots.hs:61-63`) is a methodless
  constraint family, so fabricating it cannot corrupt behavior — the review scoped it
  as harmless. In `composeWrappers` the disjointness of two *unknown* slot lists is
  genuinely a runtime fact (established by the value-level name check), so a
  coercion guarded by that check is the honest encoding, and this fix restores the
  guard (the composite's `slotNames` becomes real again). But in `leftWrap` the claim
  `Disjoint (Names rs) '[]` is *provable* for every `rs`, and in `rightWrap`
  `Disjoint '[] (Names rs)` already reduces definitionally — the master plan's vision
  ("no `unsafeCoerce` rests on an invariant the types do not enforce") demands both
  become proofs. The cost is one three-line lemma.
  Date: 2026-07-12

- Decision: design the test fixture so that stage outputs read only the input payload
  (never a register), except the *final* stage's output, which reads its own
  register; register writes read only the writer's own register plus the input.
  Rationale: EP-74 (Phase 3 of the same master plan) documents genuine
  compose-semantics findings around update snapshotting: `runUpdate` applies
  `UCombine` sequentially (`src/Keiki/Core.hs:846`), so a downstream stage's
  substituted update right-hand side that mentions an upstream register would observe
  the upstream stage's *post*-update value, diverging from sequential semantics. That
  is EP-74's bug to fix, not this plan's. The fixture shape above keeps every
  cross-stage substituted term register-free, so this plan's hardcoded expected
  values hold both before and after EP-74 lands, and a test failure here always means
  *this* plan's defect. (Guards and outputs are snapshot-safe regardless: `delta` at
  `src/Keiki/Core.hs:875-881` and `omega` at `src/Keiki/Core.hs:896-902` both
  evaluate against the pre-step register file.)
  Date: 2026-07-12

- Decision: register values are asserted behaviorally (through the register-reading
  output of the final stage on every subsequent step, plus the accumulator updates),
  not by comparing `RegFile` values across the two associations directly.
  Rationale: the two composites hide their slot lists existentially; two values of
  type `SomeSymTransducer ci co` expose no common `RegFile` type to compare, and
  keiki has no generic register-file printer. A three-step input sequence makes every
  step-N output a function of the register state left by step N-1, which is a
  complete observation of the corrupted slot for this fixture: the predicted
  divergence (14 vs 15, 19 vs 25) is exactly a register-value divergence. The
  composite's slot-*names* are additionally asserted directly via a
  `wrapperSlotNames` helper, which pins consequence (b) of the defect.
  Date: 2026-07-12

- Decision: keep the small `runSteps` fold local to `CategorySpec` and `ChoiceSpec`
  rather than exporting it from `CounterPipeline`.
  Rationale: the fixture remains a concrete-transducer module with no dependency on
  the existential `Keiki.Profunctor` wrapper, while each spec owns the observation
  helper appropriate to the API it tests. The duplicated helper is seven lines and
  avoids coupling a reusable fixture to Category/Choice machinery.
  Date: 2026-07-12


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion,
comparing the result against the original purpose.

EP-69 is complete. `SomeSymTransducer` now packs a real `KnownSlots` witness, and
`composeWrappers` appends the hidden witnesses before structurally re-deriving the
composite's `KnownSlots`, `WeakenR`, and `KnownSlotNames` dictionaries. `leftWrap`
uses the same witness induction to prove its empty-right disjointness; `rightWrap`
now relies on the definitional empty-left reductions. `DictWrapper` and
`unsafeCoerceWrapperDict` are gone, leaving one checked use of
`unsafeCoerceDisjointness` for the methodless runtime-validated constraint.

The new three-stage fixture makes register state externally observable across three
steps. Before the fix, right-associated composition emitted `[MsgD 3, MsgD 15,
MsgD 25]`, reported no slot names, and missed a deliberate `regA` collision. After
the fix, both associations emit `[MsgD 3, MsgD 14, MsgD 19]`, the wrapper reports
all three names, the collision raises `CategoryOverlapError`, and both Choice
composition regressions pass. The full pre-format suite reported 380 keiki examples,
96 jitsurei examples, 50 codec examples, and 7 codec-toolkit examples with zero
failures.


## Context and Orientation

Everything in this section is verifiable by reading the named files; nothing depends
on any prior plan or conversation.

### The vocabulary, from the ground up

A **symbolic-register transducer** is keiki's core value: `SymTransducer phi rs s ci
co` (`src/Keiki/Core.hs:638-643`) is a finite state machine with control vertices of
type `s`, an input alphabet `ci` (commands), an output alphabet `co` (events), and a
**register file** — a typed record of named mutable slots — described by the
type-level list `rs`. Each transition (`Edge`, `src/Keiki/Core.hs:627-634`) has a
guard (a predicate over registers and the current input), an update (register
writes), a list of output terms, and a target vertex.

A **slot** is a name/type pair at the type level: `type Slot = (Symbol, Type)`
(`src/Keiki/Core.hs:188`). `Symbol` is GHC's kind of type-level strings. A register
file over slots `rs` is the GADT `RegFile rs` (`src/Keiki/Core.hs:200-204`): `RNil`
for the empty list, `RCons` prepending one named value. A **GADT** (generalized
algebraic data type) is a data type whose constructors refine the type parameters —
pattern-matching on one teaches the compiler type equalities.

An **`Index rs r`** (`src/Keiki/Core.hs:208-210`) is a type-safe pointer to a slot of
type `r` inside `rs`: `ZIdx` points at the head, `SIdx i` skips one slot. The lookup
`regs ! ix` (`src/Keiki/Core.hs:215-217`) walks the register file positionally. This
is the crux of the defect: an `Index` is *unary position arithmetic in types*. If an
`Index` built for slot list `rsC` is used against a longer list `rsA ++ rsB ++ rsC`
without being shifted past the prefix, it reads slot 0 of the big list — a different
slot, possibly of a different type — and the type system cannot object if the index
was coerced. `IndexN` (`src/Keiki/Internal/Slots.hs:94-96`) is the same idea tagged
with the slot's name; updates (`USet`) use it for writes, and `setSlotN`
(`src/Keiki/Core.hs:859-864`) walks it positionally too.

**Sequential composition** is `compose` (`src/Keiki/Composition.hs:879-891`): given
`t1 : ci -> mid` and `t2 : mid -> co`, the composite runs both machines in lockstep,
its register file being the concatenation `Append rs1 rs2` (`Append` is the
type-level list append in `src/Keiki/Generics.hs:98-100`; `appendRegFile` at
`src/Keiki/Generics.hs:103-105` is its value twin). To build the composite's edges,
every register access of t2 must be **weakened** — shifted right past the `rs1`
prefix. That shift is the class `WeakenR` (`src/Keiki/Composition.hs:147-159`):

```haskell
class WeakenR (rs1 :: [Slot]) where
  weakenR :: forall rs2 r. Index rs2 r -> Index (Append rs1 rs2) r
  weakenRIndexN :: forall rs2 s r. IndexN s rs2 r -> IndexN s (Append rs1 rs2) r

instance WeakenR '[] where
  weakenR i = i
  weakenRIndexN i = i

instance (WeakenR rs1) => WeakenR ('(s, t) ': rs1) where
  weakenR i = SIdx (weakenR @rs1 i)
  weakenRIndexN i = IS (weakenRIndexN @rs1 i)
```

Note this is a **method-carrying class**: the dictionary for `WeakenR rs1` *is* the
shifting function, and the `'[]` instance's method is the identity. `compose` invokes
it at `src/Keiki/Composition.hs:386` (shifting every t2 register read during term
substitution) and `:493` (shifting every t2 register write).

**`KnownSlotNames`** (`src/Keiki/Core.hs:366-376`) is the other method-carrying
class: `slotNames :: [String]` returns the slot names of `rs` at the value level. The
`'[]` instance returns `[]`.

**`Disjoint`** (`src/Keiki/Internal/Slots.hs:61-63`) is different in kind: a
type *family* returning a `Constraint`, with **no methods** — it either reduces to
the empty constraint or raises a compile-time `TypeError`. Evidence for it carries no
behavior, which is why fabricating it (unlike the other two) cannot corrupt anything.

### The wrapper and the defect

`SomeSymTransducer ci co` (`src/Keiki/Profunctor.hs:110-119`) is an **existential
wrapper**: it hides `rs` and `s`, exposing only the alphabets, so the standard
`Category`/`Profunctor` machinery can apply. "Existential" means the constructor
remembers *that* some `rs` existed and packs the constraint dictionaries for it, but
the type no longer says which. Today it packs `(WeakenR rs, KnownSlotNames rs,
Bounded s, Enum s)`.

The `Category` instance (`src/Keiki/Profunctor.hs:434-440`) delegates `(.)` to
`composeWrappers` (`:447-469`). Because the wrapper hides `rs`, GHC cannot check
`compose`'s static `Disjoint (Names rs1) (Names rs2)` precondition, so
`composeWrappers` checks slot-name disjointness *at runtime* using `slotNames`,
throws `CategoryOverlapError` (`:341-346`) on collision, and otherwise fabricates the
`Disjoint` evidence with `unsafeCoerceDisjointness` (`:365-369`). That part is
defensible: the constraint is methodless and a real check guards it.

The unsound part is the *second* fabrication. The freshly composed transducer has
slot list `Append rs1 rs2`, and to re-wrap it the constructor demands
`WeakenR (Append rs1 rs2)` and `KnownSlotNames (Append rs1 rs2)`. GHC cannot derive
those (the spines of `rs1`/`rs2` are hidden), so the code conjures them
(`src/Keiki/Profunctor.hs:378-396`):

```haskell
data DictWrapper rs where
  DictWrapper :: (WeakenR rs, KnownSlotNames rs) => DictWrapper rs

unsafeCoerceWrapperDict :: forall rs. DictWrapper rs
unsafeCoerceWrapperDict = unsafeCoerce (DictWrapper :: DictWrapper '[])
```

The coerced dictionary is the `'[]` instance's dictionary. Its methods are therefore
`weakenR = id`, `weakenRIndexN = id`, and `slotNames = []` — *regardless of the
actual slot list*. The comment above it claims this is safe "because the structural
property is inherited"; that reasoning confuses the *existence* of an instance with
the *identity* of its methods. The instance for `Append rs1 rs2` exists, but its
`weakenR` shifts by `length rs1 + length rs2`, not by zero.

Three consequences, all verified against the code:

1. **Register type confusion under nested composition.** Haskell's `(.)` is
   right-associative, so `c . b . a` parses as `c . (b . a)`. The inner `b . a` is
   packed with the fabricated dictionary. When it then serves as `t1` in the outer
   `compose` (constraint `WeakenR rs1` with `rs1 = Append rsA rsB`,
   `src/Keiki/Composition.hs:881`), every register read and write of `c` is shifted
   by `weakenR = id` — i.e. not at all. `c`'s `Index`/`IndexN` values, built for
   `rsC`, are silently reinterpreted against `rsA ++ rsB ++ rsC` and land on slot 0
   onward: `a`'s registers. Reads return `a`'s values at `c`'s expected types
   (undefined behavior when the types differ — this is an `unsafeCoerce` of the slot
   value in effect, and can segfault); writes clobber `a`'s registers. The
   left-associated `(c . b) . a` happens to escape this particular corruption because
   its outer `t1` is the directly wrapped `a`, whose real `WeakenR rsA` dictionary
   was captured at wrap time — which is why the two associations *diverge* and an
   associativity test can catch it.

2. **The overlap safety net is disabled for composites.** The fabricated
   `slotNames = []` means a nested composite reports no slot names, so the runtime
   check at `src/Keiki/Profunctor.hs:461-465` sees no overlap even when the composite
   shares slot names with the other operand. Since that check is the *stated
   justification* for fabricating `Disjoint`, the module's own safety argument is
   void exactly for nested composition.

3. **The existing associativity test is vacuous.** At
   `test/Keiki/CategorySpec.hs:118-125`, two of the three composed values are
   `Cat.id`, which is the `SomeSymIdentity` sentinel; `(.)` short-circuits on the
   sentinel (`src/Keiki/Profunctor.hs:437-438`), so `compose` — and the fabricated
   dictionary — is never exercised. The test passes today and proves nothing.

The same fabrication is also invoked by the `Choice` instance's helpers: `leftWrap`
(`src/Keiki/Profunctor.hs:526-540`) packs `alternative t identityTransducer` (slot
list `Append rs '[]`) and `rightWrap` (`:544-558`) packs
`alternative identityTransducer t` (slot list `Append '[] rs`) with
`unsafeCoerceWrapperDict`. Both therefore hand out `weakenR = id` / `slotNames = []`
dictionaries for **non-empty** slot lists; the corruption fires as soon as a
`left'`/`right'` result participates in a later composition as the left operand
(`t1`) of `compose`, and the wrapper's slot names are `[]` in the overlap check.

### Why the fix is possible without coercion

The fabrication exists because instances are resolved *statically* and the spines of
`rs1`/`rs2` are hidden. But the wrapper is *constructed* at sites where the spines
are concrete and the real instances are in scope. A value-level **singleton witness**
of the slot-list spine — one constructor per list constructor — can be packed at
construction time and *recursed on* later: each recursion step re-exposes one cons
cell to the compiler, and at each step the real instance for that shape is derivable.
This is ordinary induction, checked by GHC, with no coercion anywhere. The witness
for `Append rs1 rs2` is computed by a structurally recursive append of the two
witnesses — the value-level mirror of `appendRegFile`
(`src/Keiki/Generics.hs:103-105`), which already does exactly this for register
files.

### Files this plan touches

All paths are repository-relative; the working directory for every command is the
repository root `/Users/shinzui/Keikaku/bokuno/keiki` (write commands relative to
that root).

- `src/Keiki/Composition.hs` — gains the witness toolkit (M2).
- `src/Keiki/Profunctor.hs` — wrapper repacked; fabrication deleted (M3).
- `test/Keiki/Fixtures/CounterPipeline.hs` — new fixture: three stateful stages (M1).
- `test/Keiki/CategorySpec.hs` — real associativity + regression tests (M1).
- `test/Keiki/ChoiceSpec.hs` — `left'`/`right'` compose-afterwards tests (M1).
- `keiki.cabal` — register the new fixture module (M1).
- `CHANGELOG.md`, `docs/masterplans/16-…​.md` — bookkeeping (M4).

Build and test environment: GHC 9.12 via the Nix dev shell. Enter it once per
session with `nix develop` from the repository root; inside it, `cabal build all`
builds the library and test packages and `cabal test all` runs the hspec suites. The
test suite is `keiki-test` (`keiki.cabal:96`), whose `test/Spec.hs` lists spec
modules explicitly (no automatic discovery) — but this plan adds no new *spec*
module, only a new *fixture* module, which must be added to `other-modules` in the
`test-suite keiki-test` stanza (the list starting at `keiki.cabal:101`; note
`Keiki.Fixtures.EmailDelivery` is already there as precedent). Formatting is
fourmolu via `nix fmt -- --no-cache`.


## Plan of Work

The work is four milestones. M1 builds the tests that expose the defect and records
the failure (proof the tests are not vacuous like their predecessor). M2 builds the
witness toolkit as a standalone, independently green addition. M3 rewires the wrapper
onto the toolkit and deletes the fabrication, turning M1's tests green. M4 is
documentation and release bookkeeping. Do not commit between M1 and M3 — M1
intentionally leaves the suite red; the first commit lands when the suite is green
again (see Idempotence and Recovery).

### Milestone 1 — Reproduce the defect with real stateful tests

Scope: a new test fixture of three genuinely stateful transducers with aligned
alphabets; a real associativity test replacing the vacuous one; regression tests for
each consequence of the defect. At the end of this milestone the code under
`src/` is untouched, the fixture and tests compile, and the new tests *fail* in the
precise way the analysis predicts — which is the evidence that they will guard the
fix. Commands: `cabal build all && cabal test all --test-show-details=direct`.
Acceptance: the associativity, slot-correctness, slot-names, overlap, and
Choice-composition tests fail; all pre-existing tests still pass; the observed
failure values are recorded in Surprises & Discoveries.

#### The fixture: `test/Keiki/Fixtures/CounterPipeline.hs`

Create a module `Keiki.Fixtures.CounterPipeline` providing three single-vertex
stateful stages over `Int`-payload newtypes. Newtypes keep the `Category` alphabets
honest (`a : MsgA -> MsgB`, `b : MsgB -> MsgC`, `c : MsgC -> MsgD`, so only the
intended compositions typecheck). Each stage owns exactly one `Int` register,
initialized to a real `0` (not the `emptyRegFile` error-thunk sentinel, because the
stage reads its register before first writing it): the register is **read** by the
stage's guard and by its update right-hand side, and **written** by its update on
every step — satisfying the "written and read" requirement — and stage `c`'s
register is additionally read by its *output*, which is what makes register state
observable in emitted events.

Two compose-imposed design constraints, both explained in the module haddock so the
fixture survives review:

- *Name alignment.* `compose` substitutes t2's input reads against t1's emission and
  demands the constructor-name strings match (`icName ic2 == wcName wc1`,
  `src/Keiki/Composition.hs:387-424`); on mismatch the composite edge is
  unsatisfiable or errors. So the `WireCtor` (event constructor descriptor) each
  stage emits and the `InCtor` (command constructor descriptor) the next stage reads
  must share a name; name both after the mid type (`"MsgB"`, `"MsgC"`, …).
- *EP-74 orthogonality.* Only the final stage's output reads a register, and each
  update reads only its own register — see the Decision Log entry for why this keeps
  the expected values stable across the (separate) EP-74 compose-semantics fix.

The module, in full (adjust only if the compiler demands it, and record any
deviation in Surprises & Discoveries):

```haskell
-- | Three-stage stateful counter pipeline used by the EP-69 Category
-- and Choice regression tests. See the plan at
-- docs/plans/69-replace-the-fabricated-weakenr-and-knownslotnames-dictionary-in-category-composition-with-real-induction-witnesses.md
-- for the two design constraints (mid-alphabet constructor-name
-- alignment; no cross-stage register reads in substituted update RHSs).
module Keiki.Fixtures.CounterPipeline
  ( MsgA (..), MsgB (..), MsgC (..), MsgD (..),
    StageVertex (..),
    ARegs, BRegs, CRegs,
    stageA, stageB, stageC, stageConflict,
    inMsgB, inMsgC, inMsgD, wireMsgB, wireMsgC, wireMsgD,
  )
where

import Data.Proxy (Proxy (..))
import Keiki.Core

newtype MsgA = MsgA Int deriving stock (Eq, Show)
newtype MsgB = MsgB Int deriving stock (Eq, Show)
newtype MsgC = MsgC Int deriving stock (Eq, Show)
newtype MsgD = MsgD Int deriving stock (Eq, Show)

-- | Every stage is a one-vertex machine that loops on itself.
data StageVertex = StageVertex deriving stock (Eq, Show, Bounded, Enum)

type ARegs = '[ '("regA", Int)]
type BRegs = '[ '("regB", Int)]
type CRegs = '[ '("regC", Int)]

-- | One-field input schema shared by all pipeline messages.
type PayloadSchema = '[ '("payload", Int)]

mkInCtor :: String -> (msg -> Int) -> (Int -> msg) -> InCtor msg PayloadSchema
mkInCtor name unwrap rebuild =
  InCtor
    { icName = name,
      icMatch = \m -> Just (RCons (Proxy @"payload") (unwrap m) RNil),
      icBuild = \(RCons _ n RNil) -> rebuild n
    }

mkWireCtor :: String -> (msg -> Int) -> (Int -> msg) -> WireCtor msg (Int, ())
mkWireCtor name unwrap rebuild =
  WireCtor
    { wcName = name,
      wcMatch = \m -> Just (unwrap m, ()),
      wcBuild = \(n, ()) -> rebuild n
    }

inMsgA :: InCtor MsgA PayloadSchema
inMsgA = mkInCtor "MsgA" (\(MsgA n) -> n) MsgA

inMsgB :: InCtor MsgB PayloadSchema
inMsgB = mkInCtor "MsgB" (\(MsgB n) -> n) MsgB

inMsgC :: InCtor MsgC PayloadSchema
inMsgC = mkInCtor "MsgC" (\(MsgC n) -> n) MsgC

inMsgD :: InCtor MsgD PayloadSchema
inMsgD = mkInCtor "MsgD" (\(MsgD n) -> n) MsgD

wireMsgB :: WireCtor MsgB (Int, ())
wireMsgB = mkWireCtor "MsgB" (\(MsgB n) -> n) MsgB

wireMsgC :: WireCtor MsgC (Int, ())
wireMsgC = mkWireCtor "MsgC" (\(MsgC n) -> n) MsgC

wireMsgD :: WireCtor MsgD (Int, ())
wireMsgD = mkWireCtor "MsgD" (\(MsgD n) -> n) MsgD

-- | Shared stage shape: guard reads the register (a real read, always
-- satisfied for this fixture's inputs); update accumulates the input
-- payload into the register; output is the caller-supplied field term.
counterStage ::
  forall name inMsg outMsg.
  (KnownSymbol name) =>
  InCtor inMsg PayloadSchema ->
  WireCtor outMsg (Int, ()) ->
  ( Term '[ '(name, Int)] inMsg PayloadSchema Int ->
    Term '[ '(name, Int)] inMsg PayloadSchema Int
  ) ->
  SymTransducer
    (HsPred '[ '(name, Int)] inMsg)
    '[ '(name, Int)]
    StageVertex
    inMsg
    outMsg
counterStage ic wc mkField =
  SymTransducer
    { edgesOut = \StageVertex ->
        [ Edge
            { guard =
                PAnd
                  (PInCtor ic)
                  (PCmp CmpGe (TReg ZIdx) (TLit (0 :: Int))),
              update = USet IZ (tadd (TReg ZIdx) (TInpCtorField ic ZIdx)),
              output =
                [pack ic wc (OFCons (mkField (TInpCtorField ic ZIdx)) OFNil)],
              target = StageVertex
            }
        ],
      initial = StageVertex,
      initialRegs = RCons (Proxy @name) 0 RNil,
      isFinal = const True
    }

-- | Stage a: doubles the payload; accumulates inputs into "regA".
stageA :: SymTransducer (HsPred ARegs MsgA) ARegs StageVertex MsgA MsgB
stageA = counterStage inMsgA wireMsgB (\p -> tmul p (lit 2))

-- | Stage b: increments the payload; accumulates inputs into "regB".
stageB :: SymTransducer (HsPred BRegs MsgB) BRegs StageVertex MsgB MsgC
stageB = counterStage inMsgB wireMsgC (\p -> tadd p (lit 1))

-- | Stage c: adds its own accumulator to the payload — the register
-- READ whose misdirection the EP-69 tests detect. Note tadd's second
-- operand reads slot 0 of c's OWN register file; under the fabricated
-- dictionary this index is not shifted past the upstream slots.
stageC :: SymTransducer (HsPred CRegs MsgC) CRegs StageVertex MsgC MsgD
stageC = counterStage inMsgC wireMsgD (\p -> tadd p (TReg ZIdx))

-- | A MsgD -> MsgD stage that deliberately reuses stage a's slot name
-- "regA". Composing it after a pipeline containing stage a MUST raise
-- CategoryOverlapError; before the EP-69 fix the nested composite
-- reports no slot names and the collision is silently missed.
stageConflict ::
  SymTransducer
    (HsPred '[ '("regA", Int)] MsgD)
    '[ '("regA", Int)]
    StageVertex
    MsgD
    MsgD
stageConflict = counterStage inMsgD (mkWireCtor "MsgDOut" (\(MsgD n) -> n) MsgD) (\p -> p)
```

Imports to note: `KnownSymbol` comes via `Keiki.Core`'s re-exports or directly from
`GHC.TypeLits`; add `import GHC.TypeLits (KnownSymbol)` if the compiler asks. `pack`,
`tadd`, `tmul`, `lit`, `Cmp (..)`, `OFCons`/`OFNil`, `TReg`, `TLit`,
`TInpCtorField`, `IZ`, `ZIdx`, `USet`, `PAnd`, `PInCtor`, `PCmp` are all exported
from `Keiki.Core` (export list at `src/Keiki/Core.hs:45-…`).

Register the module: in `keiki.cabal`, add `Keiki.Fixtures.CounterPipeline` to the
`other-modules` list of `test-suite keiki-test` (alphabetically, next to
`Keiki.Fixtures.EmailDelivery`).

#### Expected behavior, worked by hand

Feed the pipeline the input sequence `[MsgA 1, MsgA 5, MsgA 2]`. Correct semantics
(both associations, post-fix), remembering that outputs are evaluated against
pre-step registers and updates land after:

- step 1, n=1: a emits `MsgB 2`, b emits `MsgC 3`, c emits `3 + regC(0) = MsgD 3`;
  registers after: regA=1, regB=2, regC=3.
- step 2, n=5: mid values 10 and 11; c emits `11 + 3 = MsgD 14`; registers after:
  regA=6, regB=12, regC=14.
- step 3, n=2: mid values 4 and 5; c emits `5 + 14 = MsgD 19`; registers after:
  regA=8, regB=16, regC=19.

Expected outputs: `[MsgD 3, MsgD 14, MsgD 19]`. Steps 2 and 3 are pure functions of
the register state left by earlier steps, so this sequence *is* the register-value
assertion.

Predicted corrupted behavior of `c . (b . a)` before the fix (c's slot-0 accesses
land on regA; verify and record actuals in M1): step 1 emits `MsgD 3` (regA is still
0 pre-step, coincidentally agreeing), but c's update then clobbers regA; step 2 emits
`MsgD 15`, step 3 `MsgD 25`. The left association emits the correct sequence, so the
two associations observably diverge from step 2 on.

#### Test edits: `test/Keiki/CategorySpec.hs`

Add `import Keiki.Fixtures.CounterPipeline` and two helpers near the existing
`runOmega`:

```haskell
-- | Fold 'step' over an input sequence from the initial state,
-- collecting each step's emissions. Nothing if any step rejects
-- (no unique satisfied edge).
runSteps :: SomeSymTransducer ci co -> [ci] -> Maybe [[co]]
runSteps (SomeSymTransducer t) inputs = go (initial t, initialRegs t) inputs
  where
    go _ [] = Just []
    go st (ci : rest) = case step t st ci of
      Nothing -> Nothing
      Just (s', regs', cos_) -> (cos_ :) <$> go (s', regs') rest
runSteps SomeSymIdentity inputs = Just (map (: []) inputs)

-- | The slot names the wrapper's hidden register file reports.
wrapperSlotNames :: SomeSymTransducer ci co -> [String]
wrapperSlotNames someT = case someT of
  SomeSymTransducer (_ :: SymTransducer (HsPred rs ci) rs s ci co) ->
    slotNames @rs
  SomeSymIdentity -> []
```

(The pattern type signature naming `rs` requires `ScopedTypeVariables`, which
GHC2024 enables. If GHC balks at the annotation shape, bind the transducer and use
a local helper with an explicit `forall` instead.)

Replace the vacuous L3 test at `test/Keiki/CategorySpec.hs:118-125` with, and add
alongside it, tests to this effect (exact hspec phrasing is free; assertions are
not):

- *L3 associativity, real and stateful.* With `wa = someSymTransducer stageA`,
  `wb = someSymTransducer stageB`, `wc = someSymTransducer stageC` and
  `inputs = [MsgA 1, MsgA 5, MsgA 2]`: assert
  `runSteps ((wc . wb) . wa) inputs == runSteps (wc . (wb . wa)) inputs` **and**
  that both equal `Just [[MsgD 3], [MsgD 14], [MsgD 19]]`. The second conjunct keeps
  the test meaningful even if both associations someday break identically.
- *Nested composition touches the right slots (regression for consequence 1).*
  Assert `runSteps (wc . (wb . wa)) inputs == Just [[MsgD 3], [MsgD 14], [MsgD 19]]`
  as its own named test — this is the exact scenario the fabricated dictionary
  corrupts, kept separate so its failure message names the defect.
- *Composite slot names are real (regression for consequence 2a).* Assert
  `wrapperSlotNames (wc . (wb . wa)) == ["regA", "regB", "regC"]` (order is
  concatenation order: t1's slots then t2's, per `appendRegFile`). Pre-fix this
  returns `[]`.
- *Overlap check fires on nested composites (regression for consequence 2b).* With
  `conflict = someSymTransducer stageConflict`, assert that
  `evaluate (conflict . (wc . (wb . wa)))` throws `CategoryOverlapError` whose
  `coeSlots` contains `"regA"` (mirror the existing overlap test at
  `test/Keiki/CategorySpec.hs:131-144`, which imports `Control.Exception
  (evaluate)` already). Pre-fix, no exception is thrown.

Keep every existing test in the file unchanged.

#### Test edits: `test/Keiki/ChoiceSpec.hs`

Add `import Keiki.Fixtures.CounterPipeline`, `import Control.Category ((.))` with a
`Prelude` hiding (or use `(Cat..)` qualified — the file already imports
`Control.Category qualified as Cat`), a copy of the `runSteps` helper (or move
`runSteps` into the fixture module to share it — either is fine; record the choice),
and tests:

- *`left'` results compose correctly afterwards.* Let
  `bL = left' (someSymTransducer stageB)` and `cL = left' (someSymTransducer stageC)`
  at right-arm type `Bool`, so `cL Cat.. bL :: SomeSymTransducer (Either MsgB Bool)
  (Either MsgD Bool)`. This composes because `left'` preserves wire/input
  constructor names on the `Left` arm (`leftInCtor`/`leftWireCtor`,
  `src/Keiki/Composition.hs:549-582`) and both `Right` arms use the identity
  transducer's `"Identity"` constructors. Feed
  `[Left (MsgB 1), Right True, Left (MsgB 2)]` and assert the result is
  `Just [[Left (MsgD 2)], [Right True], [Left (MsgD 5)]]` (b: 1+1=2, then 2+1=3;
  c: 2+regC(0)=2, then 3+regC(2)=5; the `Right` input passes both identity arms
  untouched). Pre-fix, `bL`'s fabricated dictionary for `Append BRegs '[]` leaves
  `cL`'s register index unshifted onto regB and the third emission is
  `Left (MsgD 6)`.
- *`right'` results compose correctly afterwards.* Symmetric:
  `right' (someSymTransducer stageC) Cat.. right' (someSymTransducer stageB)` at
  left-arm type `Bool`, inputs `[Right (MsgB 1), Left False, Right (MsgB 2)]`,
  expected `Just [[Right (MsgD 2)], [Left False], [Right (MsgD 5)]]`. (Pre-fix,
  `rightWrap` fabricates a dictionary even though `Append '[] rs` is just `rs` —
  replacing the *real* dictionary that was in scope — so the same corruption shape
  applies.)

Run `cabal test all --test-show-details=direct`. Acceptance for M1: exactly the new
tests fail; capture the failing output (the wrong `MsgD` values, the `[]` slot
names, the missing exception) into Surprises & Discoveries. If a *prediction* is off
(e.g. the corrupted run crashes on an uninitialized-slot thunk instead of producing
a value), that is fine and interesting — record it; the acceptance is that the tests
fail pre-fix and the failure is explained by the fabricated dictionary.

### Milestone 2 — The witness toolkit in `src/Keiki/Composition.hs`

Scope: add the singleton witness and its lemmas, fully standalone — nothing else
references them yet, so the tree stays buildable and all pre-existing tests stay
green (M1's new tests remain red). At the end, the toolkit compiles, is exported,
and small sanity assertions pass. Commands: `cabal build all`, then
`cabal test all --test-show-details=direct`.

Add to `src/Keiki/Composition.hs`, in a new section directly after the `WeakenR`
instances (`src/Keiki/Composition.hs:159`), with haddocks in the module's style:

```haskell
-- | Value-level singleton of a slot-list spine. 'WNil' mirrors @'[]@;
-- 'WCons' mirrors one cons cell, capturing the slot name's
-- 'KnownSymbol'. Packed by 'Keiki.Profunctor.SomeSymTransducer' at
-- wrap time (where @rs@ is concrete) so that instance dictionaries
-- for hidden slot lists can later be RE-DERIVED by structural
-- recursion instead of fabricated with unsafeCoerce.
data SlotListWitness (rs :: [Slot]) where
  WNil :: SlotListWitness '[]
  WCons :: (KnownSymbol s) => SlotListWitness rs -> SlotListWitness ('(s, t) ': rs)

-- | The class that conjures a 'SlotListWitness' for any concrete slot
-- list. Superclasses bundle the two structural classes every wrapper
-- consumer needs, so a packed @KnownSlots rs@ hands out 'WeakenR' and
-- 'KnownSlotNames' dictionaries for free at pattern-match sites.
class (WeakenR rs, KnownSlotNames rs) => KnownSlots (rs :: [Slot]) where
  slotWitness :: SlotListWitness rs

instance KnownSlots '[] where
  slotWitness = WNil

instance (KnownSymbol s, KnownSlots rs) => KnownSlots ('(s, t) ': rs) where
  slotWitness = WCons (slotWitness @rs)

-- | Append two witnesses. The value-level mirror of
-- 'Keiki.Generics.appendRegFile': each equation matches one 'Append'
-- reduction step, so GHC checks the induction.
appendWitness ::
  SlotListWitness rs1 -> SlotListWitness rs2 -> SlotListWitness (Append rs1 rs2)
appendWitness WNil w2 = w2
appendWitness (WCons w1) w2 = WCons (appendWitness w1 w2)

-- | Discharge @KnownSlots rs@ (hence also @WeakenR rs@ and
-- @KnownSlotNames rs@) from a witness, by induction on the spine. Each
-- case has the real instance in scope: 'WNil' refines @rs@ to @'[]@;
-- 'WCons' exposes one cons cell whose head instance needs only the
-- captured 'KnownSymbol' and the recursively discharged tail.
withKnownSlots :: SlotListWitness rs -> ((KnownSlots rs) => r) -> r
withKnownSlots WNil k = k
withKnownSlots (WCons w) k = withKnownSlots w k

-- | Discharge @Disjoint (Names rs) '[]@ — nothing collides with the
-- empty name list — by the same induction. Replaces the fabricated
-- disjointness evidence in 'Keiki.Profunctor''s @left'@ helper.
withDisjointNil :: SlotListWitness rs -> ((Disjoint (Names rs) '[]) => r) -> r
withDisjointNil WNil k = k
withDisjointNil (WCons w) k = withDisjointNil w k

-- | The slot names a witness describes. Defined via 'withKnownSlots'
-- so there is exactly one induction in the module.
witnessNames :: forall rs. SlotListWitness rs -> [String]
witnessNames w = withKnownSlots w (slotNames @rs)
```

Notes for the implementer: `Slot`, `KnownSlotNames`, `slotNames`, `Disjoint`, and
`Names` are already imported via `import Keiki.Core` (`src/Keiki/Composition.hs:87`);
`Append` via `import Keiki.Generics` (`:88`); add
`import GHC.TypeLits (KnownSymbol)`. Extend the module export list
(`src/Keiki/Composition.hs:27-84`) with a new group — `SlotListWitness (..)`,
`KnownSlots (..)`, `appendWitness`, `withKnownSlots`, `withDisjointNil`,
`witnessNames` — placed after the existing "Index / term weakening" group. Why each
piece type-checks, spelled out so a reviewer can confirm there is no hidden
coercion: in `appendWitness`, the `WNil` equation is at type
`SlotListWitness (Append '[] rs2)` and `Append '[] rs2` reduces to `rs2`
(`src/Keiki/Generics.hs:99`); the `WCons` equation reduces
`Append ('(s,t) ': rs1) rs2` to `'(s,t) ': Append rs1 rs2` (`:100`) and rebuilds the
head with the pattern-bound `KnownSymbol s`. In `withKnownSlots`, the `WNil` case
refines `rs ~ '[]` so the ground instance applies; the `WCons` case has
`KnownSymbol s` from the pattern and `KnownSlots rs'` from the recursive call, which
is exactly the cons instance's context (and GHC derives the superclass obligations
from the corresponding `WeakenR`/`KnownSlotNames` cons instances at
`src/Keiki/Composition.hs:157-159` and `src/Keiki/Core.hs:372-376`). In
`withDisjointNil`, the `WCons` case's goal
`Disjoint (s ': Names rs') '[]` unfolds per `src/Keiki/Internal/Slots.hs:61-69` to
`(NotMember s '[], Disjoint (Names rs') '[])`, whose first component reduces to the
empty constraint and whose second is the recursive call's gift.

Add a short describe-block of sanity assertions to `test/Keiki/CategorySpec.hs`
(import the new names from `Keiki.Composition`):

- `witnessNames (slotWitness @ARegs) == ["regA"]`;
- `witnessNames (appendWitness (slotWitness @ARegs) (slotWitness @BRegs)) == ["regA", "regB"]`;
- `withKnownSlots (appendWitness (slotWitness @ARegs) (slotWitness @BRegs)) (slotNames @(Append ARegs BRegs)) == ["regA", "regB"]`
  (this one exercises dictionary *derivation* for an `Append`, the exact obligation
  the fabrication used to fake — here `ARegs`/`BRegs` are concrete, but the code path
  is the same recursion the wrapper will run on hidden lists).

Acceptance: `cabal build all` succeeds with no new warnings; the sanity assertions
pass; nothing outside `src/Keiki/Composition.hs` and the spec changed.

### Milestone 3 — Rewire the wrapper; delete the fabrication

Scope: `src/Keiki/Profunctor.hs` only. At the end, `DictWrapper` and
`unsafeCoerceWrapperDict` no longer exist, `unsafeCoerceDisjointness` survives at
exactly one call site, and the full suite — including every M1 test — is green.

The edits, in order:

1. **Repack the wrapper** (`src/Keiki/Profunctor.hs:110-119`): replace the
   constraint tuple `(WeakenR rs, KnownSlotNames rs, Bounded s, Enum s)` in the
   `SomeSymTransducer` constructor with `(KnownSlots rs, Bounded s, Enum s)`, and
   make the same change in the smart constructor `someSymTransducer` (`:125-133`).
   Because `WeakenR` and `KnownSlotNames` are superclasses of `KnownSlots`, every
   pattern-match site in the library and the five spec files
   (`test/Keiki/ArrowSpec.hs`, `CategorySpec.hs`, `ChoiceSpec.hs`,
   `ProfunctorSpec.hs`, `StrongSpec.hs`) that consumes those constraints keeps
   compiling; every construction site has concrete `rs`, for which the `KnownSlots`
   instances resolve automatically. Add `KnownSlots`, `slotWitness`,
   `appendWitness`, `withKnownSlots`, `withDisjointNil` to the import from
   `Keiki.Composition` (`src/Keiki/Profunctor.hs:65`). Update the wrapper's haddock
   (`:70-109`), which currently explains the packed `WeakenR`/`KnownSlotNames` pair —
   it should now explain that the wrapper packs `KnownSlots` (witness + the two
   structural classes as superclasses) precisely so composite dictionaries can be
   derived by induction rather than fabricated.

2. **Delete the fabrication** (`:371-396`): remove `DictWrapper` and
   `unsafeCoerceWrapperDict` and their haddocks entirely.

3. **Rewrite `composeWrappers`** (`:447-469`): change the constraint pair
   `(WeakenR rs1, KnownSlotNames rs1, KnownSlotNames rs2, …)` to
   `(KnownSlots rs1, KnownSlots rs2, Bounded s1, Enum s1, Bounded s2, Enum s2)` and
   replace the body's dictionary conjuring:

   ```haskell
   composeWrappers t1 t2 =
     let names1 = slotNames @rs1
         names2 = slotNames @rs2
         overlap = filter (`elem` names2) names1
      in if not (null overlap)
           then throw (CategoryOverlapError overlap)
           else case unsafeCoerceDisjointness @(Names rs1) @(Names rs2) of
             DictDisjoint ->
               withKnownSlots
                 (appendWitness (slotWitness @rs1) (slotWitness @rs2))
                 (SomeSymTransducer (compose t1 t2))
   ```

   `compose`'s `WeakenR rs1` obligation is met by `KnownSlots rs1`'s superclass —
   the *real* shifting dictionary captured at wrap time. The re-wrap's
   `KnownSlots (Append rs1 rs2)` obligation is met by `withKnownSlots` on the real
   appended witness — so the composite's `weakenR` shifts by `length rs1 + length
   rs2` and its `slotNames` are the real concatenation, which is what turns M1's
   tests green. `unsafeCoerceDisjointness` stays: the disjointness of two unknown
   lists is a runtime fact, checked immediately above, and the constraint it forges
   is methodless (see Decision Log).

4. **Rewrite `leftWrap`** (`:526-540`): constraints become
   `(KnownSlots rs, Bounded s, Enum s)`; body becomes coercion-free:

   ```haskell
   leftWrap t =
     let w = slotWitness @rs
      in withDisjointNil w $
           withKnownSlots
             (appendWitness w WNil)
             (SomeSymTransducer (alternative t (identityTransducer @c)))
   ```

   (`alternative` needs `WeakenR rs` — superclass — and
   `Disjoint (Names rs) (Names '[])`; `Names '[]` reduces to `'[]`, and
   `withDisjointNil` proves the rest. The result's slot list is `Append rs '[]`,
   whose `KnownSlots` comes from the appended witness.)

5. **Rewrite `rightWrap`** (`:544-558`): constraints as in `leftWrap`; the body
   collapses to a single line with *no* helper at all:

   ```haskell
   rightWrap t = SomeSymTransducer (alternative (identityTransducer @c) t)
   ```

   because on the left-empty side everything reduces definitionally:
   `Append '[] rs` *is* `rs` (so the packed `KnownSlots rs` re-covers the
   composite), `WeakenR '[]` has a ground instance, and
   `Disjoint (Names '[]) (Names rs)` reduces to the empty constraint via
   `Disjoint '[] ys = ()` (`src/Keiki/Internal/Slots.hs:62`). The pre-fix code
   fabricated a dictionary here *needlessly* — and harmfully, since the coerced
   `'[]`-dictionary replaced the real one for a non-empty `rs`.

6. **Sweep the module haddocks**: the module header's `OPTIONS_GHC` comment
   (`:1-6`) mentions only `unsafeCoerceDisjointness` — still true, keep it; update
   the `unsafeCoerceDisjointness` haddock (`:354-364`) to note it is now the *only*
   fabrication in the module and is guarded by a runtime check whose `slotNames` are
   real for composites too; update the `Category` instance haddock (`:400-433`) and
   `Choice` instance haddock (`:471-506`) where they describe the old mechanism.

Run `cabal build all && cabal test all --test-show-details=direct`. Acceptance:
zero test failures; `grep -rn "unsafeCoerceWrapperDict\|DictWrapper" src/ test/`
returns nothing; `grep -c "unsafeCoerceDisjointness" src/Keiki/Profunctor.hs`
finds only the definition and the single `composeWrappers` use.

### Milestone 4 — Documentation, bookkeeping, format, commit

Scope: no behavior changes. Update `CHANGELOG.md` under the unreleased/`0.1.0.0`
heading with an entry along the lines of: "`Keiki.Profunctor`: the `Category`,
`Choice` composition paths no longer fabricate `WeakenR`/`KnownSlotNames`
dictionaries via `unsafeCoerce`; nested composition of stateful transducers
(`c . b . a`) previously read and wrote misindexed register slots and bypassed the
`CategoryOverlapError` check. `SomeSymTransducer` now packs a `KnownSlots` witness
(new, exported from `Keiki.Composition` together with `SlotListWitness`,
`appendWitness`, `withKnownSlots`, `withDisjointNil`, `witnessNames`);
`someSymTransducer`'s constraints changed from `(WeakenR rs, KnownSlotNames rs)` to
`KnownSlots rs` (auto-derived for all concrete slot lists)." In
`docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md`,
set registry row 69's Status to Complete and tick the two EP-69 progress boxes.
Update this plan's own living sections (Progress, Surprises & Discoveries, Outcomes
& Retrospective). Then:

```bash
nix fmt -- --no-cache
cabal build all && cabal test all
git add -A && git commit
```

Use a conventional-commit message, e.g.
`fix(profunctor): derive composite WeakenR/KnownSlotNames dictionaries by induction instead of unsafeCoerce`,
with a body naming the defect and the new tests. Acceptance: formatter makes no
further changes on a second run; suite green; single commit containing M1–M4.


## Concrete Steps

All commands run from the repository root `/Users/shinzui/Keikaku/bokuno/keiki`,
inside the Nix dev shell.

```bash
cd /Users/shinzui/Keikaku/bokuno/keiki
nix develop            # GHC 9.12 toolchain; run once per shell session
cabal build all        # should succeed before any edits (baseline)
cabal test all --test-show-details=direct
```

Then, per milestone:

1. M1 — create `test/Keiki/Fixtures/CounterPipeline.hs` (content in Plan of Work);
   add `Keiki.Fixtures.CounterPipeline` to `other-modules` of `test-suite keiki-test`
   in `keiki.cabal`; edit `test/Keiki/CategorySpec.hs` (replace lines 118–125's test;
   add helpers and the four new tests) and `test/Keiki/ChoiceSpec.hs` (two new
   tests). Run the suite; the targeted run is faster while iterating:

   ```bash
   cabal test keiki-test --test-show-details=direct \
     --test-options='--match "Category"'
   cabal test keiki-test --test-show-details=direct \
     --test-options='--match "Choice"'
   ```

   Expect failures shaped like (values to be confirmed and recorded):

   ```text
   expected: Just [[MsgD 3],[MsgD 14],[MsgD 19]]
    but got: Just [[MsgD 3],[MsgD 15],[MsgD 25]]
   ```

   and, for the slot-name regression, `expected: ["regA","regB","regC"] but got: []`,
   and a "did not get expected exception: CategoryOverlapError" for the overlap test.

2. M2 — edit `src/Keiki/Composition.hs` (toolkit + exports); add the sanity
   assertions to `test/Keiki/CategorySpec.hs`; `cabal build all`; run the Category
   match — only M1's behavioral tests may still fail.

3. M3 — edit `src/Keiki/Profunctor.hs` per the six numbered edits; then:

   ```bash
   cabal build all
   cabal test all --test-show-details=direct
   grep -rn "unsafeCoerceWrapperDict\|DictWrapper" src/ test/   # expect no output
   ```

4. M4 — `CHANGELOG.md`, master plan updates, this plan's living sections; then:

   ```bash
   nix fmt -- --no-cache
   cabal build all && cabal test all
   git add -A
   git commit   # conventional commit; see M4 for suggested message
   ```

Expected final test transcript shape (counts will differ; zero failures is the
contract):

```text
Finished in ...s
N examples, 0 failures
```


## Validation and Acceptance

The change is internal (no new user-visible feature), so its impact is demonstrated
by tests that fail before and pass after, each tied to a concrete misbehavior:

- *Associativity, for real.* `runSteps ((wc . wb) . wa) [MsgA 1, MsgA 5, MsgA 2]`
  equals `runSteps (wc . (wb . wa)) …` equals
  `Just [[MsgD 3], [MsgD 14], [MsgD 19]]` — three genuinely stateful stages, each
  with a register slot written every step and read by its guard, its update, and (for
  stage c) its output; steps 2–3's expected values are functions of the register
  state, so this asserts register values, not just a single output. Before the fix
  the right association diverges from step 2 on.
- *Nested slot correctness.* The standalone right-association test pins the exact
  corrupted scenario independently of the equality test.
- *Safety net restored.* `wrapperSlotNames (wc . (wb . wa)) == ["regA","regB","regC"]`
  (was `[]`), and composing a slot-name-colliding stage after the nested composite
  throws `CategoryOverlapError` naming `"regA"` (was: silently composes, corrupt).
- *Choice helpers.* `left'`-then-compose and `right'`-then-compose over stateful
  stages produce the hand-computed sequences above (were corrupted from the second
  `Left`/`Right` input on).
- *No fabrication remains.* `grep -rn "unsafeCoerceWrapperDict\|DictWrapper" src/`
  is empty; `unsafeCoerceDisjointness` appears at exactly one call site
  (`composeWrappers`), guarded by the now-functional runtime check.
- *Nothing else regressed.* The full pre-existing suite (`cabal test all`) is green,
  including the identity-law, overlap, `isSingleValuedSym`, Profunctor, Strong, and
  Arrow specs that pattern-match the re-packed wrapper.

Success is `cabal test all` reporting `0 failures` with all of the above tests
present; failure of any single new test after M3 means the induction is wired wrong
(most likely a constraint still being satisfied by a stale coerced dictionary — grep
for `unsafeCoerce` in `src/Keiki/Profunctor.hs` and re-check edit 2).


## Idempotence and Recovery

Every step is an ordinary source edit plus a build/test cycle; all are safe to
repeat. Re-running `cabal build`/`cabal test`/`nix fmt` any number of times causes
no drift. If a milestone goes sideways, `git checkout -- <path>` restores any file
(the plan file itself excepted — keep its living sections current even when
reverting code).

The suite is deliberately red between the end of M1 and the end of M3; that is the
fail-before/pass-after evidence, not a mistake. Do not commit in that window — the
single commit lands at M4 when the tree is green, so `master` never carries a red
suite. If work must pause mid-window, either stash (`git stash`) or note the exact
stopping point in Progress so the next contributor can resume from the working tree.

Two known recovery paths for M3 compile errors:

- If GHC reports it cannot deduce `KnownSlots …` at a *construction* site in a spec,
  that site is building the wrapper with a slot list GHC cannot see as concrete —
  add a type annotation pinning `rs` (all existing spec sites are concrete and
  should not need this).
- If GHC reports an untouchable/escaping type variable inside `withKnownSlots`
  continuations, bind the continuation's result type explicitly (the CPS argument's
  `r` must not mention the locally quantified constraint's variables); restructuring
  the call as a local `let` with a type signature resolves it.

If the M1 corrupted run turns out to crash (e.g. forcing an `uninit:` register
thunk) instead of producing wrong values, the tests still fail pre-fix and pass
post-fix — record the actual behavior in Surprises & Discoveries and proceed; no
redesign is needed.


## Interfaces and Dependencies

No new package dependencies; no version bounds change. Everything uses
already-present imports (`base`'s `GHC.TypeLits`, `Data.Proxy`; keiki's own
modules); the test additions use only `hspec` and `Control.Exception.evaluate`,
both already in `keiki-test`'s build-depends (`keiki.cabal:133-146`).

At the end of M2, `src/Keiki/Composition.hs` exports, in addition to its current
surface:

```haskell
data SlotListWitness (rs :: [Slot]) where
  WNil :: SlotListWitness '[]
  WCons :: (KnownSymbol s) => SlotListWitness rs -> SlotListWitness ('(s, t) ': rs)

class (WeakenR rs, KnownSlotNames rs) => KnownSlots (rs :: [Slot]) where
  slotWitness :: SlotListWitness rs

appendWitness :: SlotListWitness rs1 -> SlotListWitness rs2 -> SlotListWitness (Append rs1 rs2)
withKnownSlots :: SlotListWitness rs -> ((KnownSlots rs) => r) -> r
withDisjointNil :: SlotListWitness rs -> ((Disjoint (Names rs) '[]) => r) -> r
witnessNames :: SlotListWitness rs -> [String]
```

At the end of M3, `src/Keiki/Profunctor.hs`'s changed public surface is exactly:

```haskell
data SomeSymTransducer ci co where
  SomeSymTransducer ::
    (KnownSlots rs, Bounded s, Enum s) =>
    SymTransducer (HsPred rs ci) rs s ci co ->
    SomeSymTransducer ci co
  SomeSymIdentity :: SomeSymTransducer a a

someSymTransducer ::
  (KnownSlots rs, Bounded s, Enum s) =>
  SymTransducer (HsPred rs ci) rs s ci co ->
  SomeSymTransducer ci co
```

with `DictWrapper`/`unsafeCoerceWrapperDict` gone (they were never exported;
their deletion is invisible to the API) and every other export unchanged. Per the
master plan's consumer ledger (integration point 6), `SomeSymTransducer` and all
composition operators have zero downstream consumers, so this constraint change
requires no coordination; the changelog entry from M4 is the only external notice
needed. EP-75 (composition alignment validation) soft-depends on this plan and
should be written against the `KnownSlots`-witness representation defined here.


## Revision Notes

- 2026-07-12: Implemented all four milestones. Added fail-before/pass-after
  stateful composition coverage, introduced and exported the slot-list witness
  toolkit, repacked `SomeSymTransducer`, removed the fabricated method dictionaries,
  updated public documentation and changelog, and recorded final validation evidence.
