# Why keiki uses an SMT solver

A short explainer for keiki users who've encountered the phrase "SMT
solver" or "z3" in the docs and want to know what it is, what it does,
and why an aggregate author should care.

No automata-theory or formal-methods prerequisites. If you've written
tests and shipped code with bugs in it, you have the background.

The operational follow-up — wiring this into a CI pipeline — is
`docs/guide/symbolic-ci.md`. The cost analysis is
`docs/research/symbolic-analysis-and-runtime-implications.md`.

---

## 1. The bug we're trying to prevent

A keiki aggregate is a transducer: at each control vertex, some number
of outgoing edges. Each edge has a *guard* — a predicate over the
register file and the input command — that says "fire when this is
true."

Suppose at vertex `Pending` you have two edges that both react to a
`Submit` command:

```
Edge "Process"  fires when:  input is Submit  AND  submittedAt ≤ deadline
Edge "Reject"   fires when:  input is Submit  AND  submittedAt ≥ deadline
```

Read in isolation, each guard looks correct. Read together, they share
a boundary: when `submittedAt == deadline`, both guards are true.

This is non-determinism. The runtime has to pick one edge to fire.
Whichever it picks, the other edge's update and output are silently
dropped. State diverges from intent. The aggregate is broken in a way
no exception ever raises.

The bug doesn't surface immediately. It surfaces as the wrong event
being emitted on the day a `Submit` lands at exactly the deadline, six
months after release.

---

## 2. Why tests don't reliably catch it

Three things might catch this bug. None reliably do.

**Code review** is the weakest. Two predicates expressed in different
shapes can be logically equivalent or overlapping in ways a human
reading the code at glance won't see. The boundary case in §1 is a
one-character difference between the two guards — `<` vs. `≤`, `>` vs.
`≥`. Easy to miss in review.

**Unit tests** check cases you wrote. They cannot catch a guard
overlap unless someone happens to test the offending input — which is
exactly the input nobody knew was a problem.

**Property tests** (Hedgehog, QuickCheck) do better: a generator
produces many random inputs, and a property like "at most one edge
fires" can be checked across them. But a property test is only as good
as its generator. If `submittedAt` and `deadline` are generated
independently from infinite domains, the probability that they land on
exactly the same nanosecond is effectively zero. The boundary bug
hides indefinitely.

What we want is a method that doesn't sample, doesn't depend on which
cases someone thought to test, and proves the property over the entire
(infinite) input space. That's what an SMT solver does.

---

## 3. What an SMT solver is

"SMT" stands for **Satisfiability Modulo Theories**. The solver is a
program — `z3`, in keiki's case — that answers one type of question:

> Given a logical formula over typed variables, is there any
> assignment of values to those variables that makes the formula true?

Three possible answers: `sat` (yes, and here's an example assignment),
`unsat` (no, the formula is contradictory), or `unknown` (couldn't
decide within the budget given).

A tiny example. Let `x` and `y` be integers. The formula

```
x > 5   AND   y > 0   AND   x + y < 3
```

is unsatisfiable: if `x > 5` and `y > 0`, then `x + y > 5`, which
contradicts `x + y < 3`. The solver returns `unsat` — for *any*
integers `x` and `y`, no assignment makes the formula true. That's a
strong claim about an infinite space, decided in milliseconds.

The "modulo theories" part is what makes the tool useful for real
code. The solver knows about integers, reals, bit vectors, strings,
arrays, algebraic datatypes, and more. Each "theory" is a body of math
about one of those domains, and the solver composes them. That's why
a question like "do these two date-comparisons ever overlap?" is
something it can answer at all.

You don't write SMT formulas by hand. You write Haskell, and a library
(SBV, in keiki) translates it.

---

## 4. How keiki uses the solver

Two outgoing edges from the same vertex are mutually exclusive iff
their guards are never simultaneously true. Phrased as an SMT
question: the conjunction `g1 ∧ g2` is unsatisfiable.

For the §1 example:

```
g1 = (input is Submit) AND (submittedAt ≤ deadline)
g2 = (input is Submit) AND (submittedAt ≥ deadline)
g1 ∧ g2  ≡  (input is Submit) AND (submittedAt = deadline)
```

The solver returns `sat` with a witness like `submittedAt = deadline =
0`. keiki reports the offending edge pair and the CI gate fails.

`isSingleValuedSym` walks every reachable vertex, takes every pair of
outgoing edges, asks the solver "is `g1 ∧ g2` satisfiable?", and
returns `True` only if every answer is `unsat`. The translation from
your Haskell guards to SMT formulas is mechanical: SBV maps `PEq`,
`PAnd`, `POr`, `PNot`, the ordering guard `PCmp` (`<`/`<=`/`>`/`>=`,
authored with `requireLt`/`requireLe`/`requireGt`/`requireGe`), and
equalities/orderings over `Int`/`Integer`/`Bool`/`Text`/`UTCTime` and
the fixed-width integers (`Word8`/`Word16`/`Word32`/`Word64`/`Int32`/
`Int64` — keiki's money convention is `Word64` minor units), into the
solver's language.

The result, when it's `True`, is closer to a proof than to a passed
test. Every input that could fire two edges has been searched for and
ruled out, across the entire input space, by the solver's decision
procedure.

---

## 5. The catch

Three places where the assurance weakens:

- **Curated types only.** The translation has built-in support for
  `Bool`, `Int`, `Integer`, `Text`, `UTCTime`, and the fixed-width
  integers `Word8`/`Word16`/`Word32`/`Word64`/`Int32`/`Int64`. Slot or
  input types outside this set fall back to a fresh symbolic variable —
  the solver can't reason about their internals, and precision drops.
  You can add a `Sym` instance for a new type if it has a natural SBV
  representation.
- **Escape hatches.** The predicate AST has `TApp1` / `TApp2`
  constructors that lift opaque Haskell functions (e.g. a *computed*
  threshold operand such as a weighted sum). The solver can't see
  inside them, so it picks "some" value and the answer becomes an
  over-approximation: the gate may fail (`False`) when the truth is
  "they really are mutually exclusive." Never the reverse. (A bare
  threshold like `amount >= 1000` no longer needs an escape — write it
  as `requireGe #amount (lit 1000)` and the solver sees it.)
- **Repeated reads of one register.** *Fixed in EP-42 of MasterPlan
  12.* The translator now memoizes register and input-field reads, so a
  predicate that reads the same slot twice (e.g. a self-mutex `g ∧ ¬g`
  over a shared register) shares one solver variable and the gate
  decides it correctly. The one residual is reads routed through a
  `TApp1` / `TApp2` escape hatch (the bullet above): those are not
  memoized (opaque functions have no `Eq`), so two applications still
  mint independent variables — the gate may fail (`False`) when the
  truth is mutual exclusion. Never the reverse.
- **`Unknown` from the solver.** Some predicate shapes push z3 outside
  its decidable fragment. keiki treats `Unknown` conservatively — as
  if the predicate were satisfiable — so a spurious `Unknown` causes
  the CI gate to fail, not pass. Loud, not silent.

Cost is ~10ms per solver call warm. A typical aggregate runs the gate
in a few hundred milliseconds total. Not a hot-path tool — it's a CI
/ test-stage check, never on the per-event path.

---

## 6. The benefit, restated

Without the symbolic check, single-valuedness is a property test: you
trust your generators to find any guard overlap. With it, the property
is *decided*. You add one line to your spec —

```haskell
isSingleValuedSym (withSymPred yourAggregate) `shouldBe` True
```

— and ship the aggregate with the assurance that no input, anywhere
in the input space, fires two edges. That's the guarantee a property
test can never give you, and the reason keiki has an SMT solver in the
build.

---

## 7. Pointers

- `docs/guide/symbolic-ci.md` — wiring this into a CI pipeline.
- `docs/research/symbolic-analysis-and-runtime-implications.md` —
  what the solver actually does, what it costs, and what fragments it
  covers.
- `docs/foundations/05-data-carrying-alphabets.md` — the formalism
  (predicates instead of enumerated symbols).
- `docs/research/sbv-boolalg-design.md` — the design log behind the
  SBV-backed `BoolAlg` instance.
