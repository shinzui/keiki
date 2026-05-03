# Composition combinators on `SymTransducer` — design

This note is the design record for the composition combinators added
to keiki under MasterPlan 4 / ExecPlan 11. It captures the design
space crem's six combinators trace, names the minimum viable subset
keiki ships, and works out the formal semantics each chosen
combinator has against keiki's symbolic-register-transducer
projection.

The companion files referenced throughout this note are:

- `docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`
  — the formal projection.
- `docs/research/core-design-transducer-as-source-of-truth.md` —
  why `SymTransducer` is the source of truth.
- `docs/research/orchestration-sagas-choreography-and-feedback-loops-as-transducers.md`
  — process manager / saga / policy patterns and how they map to
  composition.
- `docs/research/architecture-comparison-fst-aggregate-vs-crem.md`
  — the crem comparison whose §"crem's composition primitives"
  catalogues the six-combinator menu.
- `docs/research/keiki-generics-design.md` — the DX note whose
  "Future improvements" item F asks for these combinators.


## Problem statement

The keiki single-aggregate formalism is mature: a `SymTransducer phi
rs s ci co` is a finite control graph plus a symbolic register file,
edge guards form an *effective* Boolean algebra, and three
load-bearing analyses (`solveOutput`, `checkHiddenInputs`,
`isSingleValuedSym`) work mechanically per transducer.

Real-world systems span multiple aggregates. Three orchestration
patterns (per the orchestration note) need composition:

1. **Choreography** — aggregate A's events feed aggregate B's
   commands. The composite's input is A's `ci`; its output is B's
   `co`. The natural shape is `compose t1 t2`.

2. **Process manager / saga** — a state machine observes events
   from aggregate A and issues commands to aggregate B. The
   process manager is itself a transducer `Trans events_of_A
   commands_of_B`; the composite system is
   `compose A (compose pm B)`.

3. **Aggregate ↔ policy feedback loop** — an aggregate's output
   drives a policy that produces commands which loop back to the
   aggregate. The natural shape is `feedback t f`.

Today, keiki users authoring any of these patterns hand-roll
event/command plumbing. Each per-pair gluing is a candidate site
for the keiki guarantees to break: an opaque `OFn` output silently
loses the inverse, a `PMatchC` guard silently breaks
single-valuedness, an unmatched event silently drops on replay.
Composition combinators that preserve the guarantees end-to-end
are the value proposition.


## The crem catalogue (six combinators)

For reference, crem's `StateMachineT` GADT exposes:

    Sequential  :: StateMachineT m a b -> StateMachineT m b c
                -> StateMachineT m a c
    Parallel    :: StateMachineT m a b -> StateMachineT m c d
                -> StateMachineT m (a, c) (b, d)
    Alternative :: StateMachineT m a b -> StateMachineT m c d
                -> StateMachineT m (Either a c) (Either b d)
    Feedback    :: StateMachineT m a (n b) -> StateMachineT m b (n a)
                -> StateMachineT m a (n b)
    Kleisli     :: StateMachineT m a (n b) -> StateMachineT m b (n c)
                -> StateMachineT m a (n c)

plus the full Profunctor / Strong / Choice / Costrong / Cochoice /
Closed hierarchy via crem's dependency on `profunctors`.

`Sequential` is the categorical `(.)` on transducers. `Parallel`
runs two machines side by side on a tuple input/output. `Alternative`
runs one of two machines on an `Either` input. `Feedback` is the
fixed-point combinator (a.k.a. `compose-and-loop` for one external
command). `Kleisli` lifts `Sequential` over a `Foldable` of inner
events (a generalisation `Sequential` itself doesn't admit when
edges produce zero or many events).


## What keiki ships in EP-11: minimum viable

EP-11's design milestone picks exactly **one combinator**:
`compose`. The other five are deferred to follow-up EPs (per
MasterPlan 4's fan-out protocol) once a real authoring need
surfaces.

Rationale, in order:

1. **`compose` is the minimum viable for choreography and process
   managers.** The orchestration note's three patterns all reduce
   to chains of `compose` (saga = `compose A pm`, choreography =
   `compose A B`, full pipeline = `compose A (compose pm B)`).
   With `compose` alone, every pattern in the note is expressible.

2. **`feedback` requires an iteration model.** The orchestration
   note's "feedback loop" runs aggregate ↔ policy until quiescence.
   Implementing this purely (without an iteration count or a
   termination proof) is non-trivial — keiki's pure formalism
   pushes effects to the runtime boundary
   (`docs/research/effects-boundary.md`), and "iterate until
   quiescence" is itself an effect (it can diverge). A pure
   `feedback` that takes one step (`step (compose t (lift f)) ...`)
   is just `compose` of t with a stateless lift of f, so the
   non-trivial form is the iterating one. Defer.

3. **`alternative` is a separate idiom with its own invariants.**
   Two transducers handling disjoint subsets of the input alphabet.
   Single-valuedness for `alternative` requires the *underlying*
   guards to be globally mutually exclusive (a non-local check).
   That is its own design milestone.

4. **`parallel` is rarely useful at the aggregate level.** Two
   independent aggregates running on independent inputs is just
   "two transducers"; bundling them in a `(s1, s2)`-vertexed
   composite buys nothing keiki users currently ask for. crem
   needs `Parallel` for its profunctor instances; keiki has no
   profunctor obligation.

5. **`Kleisli` requires multi-event edges.** keiki edges produce
   at most one event per step (per synthesis §5's MultiDecider
   discussion, generalisation is out of v2 scope). Without
   multi-event edges, `Kleisli` collapses to `compose`.

6. **Profunctor hierarchy.** Replicating the
   profunctors/Strong/Choice/Costrong/Cochoice/Closed instances on
   `SymTransducer` requires either a `Profunctor` superclass on
   the carrier (which keiki doesn't have) or an entirely new shape
   (which is a separate design milestone). Out of scope.

The EP-11 verdict: **single combinator, `compose`, in a new module
`Keiki.Composition`**, with the understanding that follow-up EPs
add `feedback`, `alternative`, etc. as authoring needs justify.

This decision keeps EP-11 in the "single-EP" shape its plan
anticipated. MasterPlan 4 does **not** fan out into per-combinator
EPs. M5 of EP-11's plan is a no-op.


## Module placement

The combinators live in **`src/Keiki/Composition.hs`** — a new
top-level module, not an extension of `Keiki/Core.hs`. Rationale:

- `Keiki.Core` is the single-transducer formalism. Multi-transducer
  composition is a distinct concern.
- Adding the substitution machinery to `Keiki.Core` would balloon
  its export list and obscure the per-edge data layout that callers
  read first.
- `Keiki.Composition` imports `Keiki.Core` and `Keiki.Generics` (for
  the `Append` type family + `appendRegFile` value-level append).
  It exports `compose` as its single user-facing value.

Tests live in `test/Keiki/CompositionSpec.hs`. The worked example's
second aggregate lives in `src/Keiki/Examples/EmailDelivery.hs`,
following the existing `Keiki/Examples/UserRegistration.hs`
pattern.


## `compose` — type signature

The signature, in full, is:

    compose
      :: forall rs1 rs2 s1 s2 ci1 mid co.
         WeakenR rs1
      => SymTransducer (HsPred rs1 ci1) rs1 s1 ci1 mid
      -> SymTransducer (HsPred rs2 mid) rs2 s2 mid co
      -> SymTransducer
           (HsPred (Append rs1 rs2) ci1)
           (Append rs1 rs2)
           (Composite s1 s2)
           ci1
           co

Key choices:

- **Carrier `phi` is fixed at `HsPred`**, not polymorphic. The
  combinator walks the predicate's structure during substitution
  (replacing `mid`-reads on the t2 side with structural reads on
  the t1 side). A general `BoolAlg phi` carrier doesn't expose its
  AST, so the combinator can't substitute inside an opaque carrier.
  The composite's guard is itself an `HsPred`, which lifts to
  `SymPred` via the existing `withSymPred` wrapper for symbolic
  analysis.

- **Vertex type is `Composite s1 s2`**, a newtype wrapper around
  a pair, with hand-rolled `Bounded`/`Enum` instances. A bare
  `(s1, s2)` would require an orphan `Enum (s1, s2)` instance for
  `[minBound .. maxBound]` enumeration in `checkHiddenInputs` /
  `isSingleValuedSym`; the newtype owns the instance cleanly. The
  trade is ~3 lines per call site (`Composite v1 v2` instead of
  `(v1, v2)`).

- **Register file is `Append rs1 rs2`**. The existing `Append`
  type family in `Keiki.Generics` already concatenates slot lists.
  The composite's initial register file is
  `appendRegFile (initialRegs t1) (initialRegs t2)`. Slot
  references from t1 read the prefix; references from t2 read the
  suffix.

- **`WeakenR rs1` constraint.** The combinator weakens
  `Index rs2 r → Index (Append rs1 rs2) r` for every t2-side read.
  `WeakenR` is a typeclass over `rs1` that walks rs1's slot list
  with `SIdx`-prepends to convert a tail-side index into a
  full-list index. Defined in `Keiki.Composition`.


## `compose` — semantics

The composite's edges from `(s1, s2)`:

1. For each **ε-edge `e1`** in t1 from `s1` (i.e. `output e1 ==
   Nothing`), one composite ε-edge:

       Edge
         { guard  = liftLPred (guard e1)
         , update = liftLU (update e1)
         , output = Nothing
         , target = Composite (target e1) s2
         }

   t2 does not step on a t1 ε-edge — there is no `mid` for it to
   consume. The composite's `s2` is unchanged.

2. For each **non-ε edge `e1`** in t1 from `s1` (i.e. `output e1 ==
   Just o1`), and each `e2` in t2 from `s2`, one composite edge:

       Edge
         { guard  = PAnd (liftLPred (guard e1))
                          (substPred (guard e2) o1)
         , update = liftLU (update e1) `unsafeCombine`
                    substUpdate (update e2) o1
         , output = fmap (\o2 -> substOut o2 o1) (output e2)
         , target = Composite (target e1) (target e2)
         }

   The guard fires when both t1's and t2's guards are satisfied
   *with `mid` substituted out*. The composite's update applies
   t1's first, then t2's (with `mid` substituted). The composite's
   output is t2's output if any (with `mid` substituted). The
   target moves both sub-machines.

   Substitution functions `substPred`, `substUpdate`, `substOut`
   take a t2-side artefact and t1's edge output `o1`, producing a
   t1-context artefact. They are defined recursively over the AST
   in §"Substitution algorithm" below.

3. **`isFinal` of the composite** is `\(Composite s1 s2) ->
   isFinal t1 s1 && isFinal t2 s2` — both sub-machines must be
   final.


## `compose` — single-step example

For intuition, walk a single composite step. Let:

    t1 = SymTransducer { initial = A, isFinal = (== B), ... }   -- A → B
    t2 = SymTransducer { initial = X, isFinal = (== Y), ... }   -- X → Y

with one t1 edge `e1 :: A ⨯ Cmd → B emitting Mid` and one t2 edge
`e2 :: X ⨯ Mid → Y emitting Out`.

The composite has initial state `Composite A X` and one outgoing
edge from there (via the M1 substitution): `Composite A X ⨯ Cmd →
Composite B Y emitting Out`. One external command produces one
output, advancing both internal machines simultaneously.

If t1 has a second edge `e1' :: A → A emitting Mid'` (a self-loop)
and t2 has a single edge `e2 :: X ⨯ Mid → Y` (only matches Mid),
then the composite has *two* outgoing edges from `Composite A X`:

- `(e1, e2)`: guard is `g1 ∧ g2[mid := o1]`. Fires when t1's guard
  matches Cmd and t2's guard matches the Mid o1 produces.
- `(e1', e2)`: guard is `g1' ∧ g2[mid := o1']`. Substituting g2
  against o1' (which produces Mid') — if g2 reads `PInCtor
  inCtorForMid` and o1' is `OPack ic1' wireForMid' ...`, then
  `substPred (PInCtor inCtorForMid) o1' = PBot` (constructors
  don't match), so the edge is dead.

The composite's single-valuedness reduces to: "for each composite
vertex, the two outgoing edges' substituted guards are mutually
exclusive". Provably so when t1's edges have mutually exclusive
guards (since the conjunction's left side already disagrees) and
when the substituted t2 guards don't accidentally agree (which
they won't when their underlying guards on `mid` are structural).


## Substitution algorithm

The composite walks t2's AST and substitutes `mid`-reads with
structural references to t1's edge output. This section defines
the substitution for each AST shape.

### Substituting a `Term rs2 mid r`

Given `o1 :: OutTerm rs1 ci1 mid` (the t1 edge's output, expected
to be `OPack ic1 wc1 of1` for the structural case):

    substTerm
      :: WeakenR rs1
      => Term rs2 mid r
      -> OutTerm rs1 ci1 mid
      -> Term (Append rs1 rs2) ci1 r

    substTerm (TLit r)                _o1 = TLit r
    substTerm (TReg ix2)              _o1 = TReg (weakenR ix2)
    substTerm (TInpCtorField ic2 ix2)  o1
      | OPack ic1 wc1 of1 <- o1
      , icName ic2 == wcName wc1
      = -- mid is structurally wc1.wcBuild (eval of1).
        -- mid's ic2-slot ix2 corresponds to of1's position ix2.
        let n  = indexInt ix2
            tm = nthTerm n of1     -- :: Term rs1 ci1 r' (r' ~ r structurally)
        in weakenLTerm @rs2 (unsafeCoerceTerm tm)
      | OPack _ wc1 _ <- o1
      = -- t2 reads a different ctor than t1 produces — dead branch.
        -- The composite guard's PInCtor substitution carries this
        -- as PBot; a TInpCtorField in this position never evaluates
        -- because the guard is unsatisfiable. We emit a structural
        -- placeholder (a TLit of an unobservable value would crash
        -- 'evalTerm' if reached; instead the placeholder is built
        -- so checkHiddenInputs flags the edge if it survives).
        error ("compose: TInpCtorField over " <> icName ic2
                 <> " but t1 emits " <> wcName wc1
                 <> " — caller should ensure structural alignment")
      | otherwise
      = error "compose: t1 edge has non-OPack output (escape hatch)"
    substTerm (TApp1 f t)              o1  = TApp1 f (substTerm t o1)
    substTerm (TApp2 f a b)            o1  = TApp2 f (substTerm a o1)
                                                       (substTerm b o1)

`weakenLTerm` walks a `Term rs1 ci1 r` and converts every `TReg`
index from `Index rs1 r` to `Index (Append rs1 rs2) r`. `nthTerm`
walks an `OutFields rs ci fs` chain and returns the `n`-th term
(unsafeCoerce'd to the caller's expected `r`).

`weakenR` walks rs1's length to convert `Index rs2 r` to
`Index (Append rs1 rs2) r`.

### Substituting an `HsPred rs2 mid`

    substPred
      :: WeakenR rs1
      => HsPred rs2 mid
      -> OutTerm rs1 ci1 mid
      -> HsPred (Append rs1 rs2) ci1

    substPred PTop          _o1 = PTop
    substPred PBot          _o1 = PBot
    substPred (PAnd p q)     o1 = PAnd (substPred p o1) (substPred q o1)
    substPred (POr p q)      o1 = POr  (substPred p o1) (substPred q o1)
    substPred (PNot p)       o1 = PNot (substPred p o1)
    substPred (PEq a b)      o1 = PEq  (substTerm a o1) (substTerm b o1)
    substPred (PInCtor ic2)  o1
      | OPack _ wc1 _ <- o1, icName ic2 == wcName wc1 = PTop
      | OPack _ _   _ <- o1                            = PBot
      | otherwise = error "compose: PInCtor against non-OPack t1 output"
    substPred (PMatchC _)    _o1 =
      error "compose: PMatchC over mid is unsupported (opaque); \
            \restructure t2's guard to use PInCtor / PEq / TInpCtorField"

### Substituting an `Update rs2 mid`

    substUpdate
      :: WeakenR rs1
      => Update rs2 mid
      -> OutTerm rs1 ci1 mid
      -> Update (Append rs1 rs2) ci1

    substUpdate UKeep            _o1 = UKeep
    substUpdate (USet ix2 t)      o1 = USet (weakenR ix2) (substTerm t o1)
    substUpdate (UCombine a b)    o1 = UCombine (substUpdate a o1)
                                                 (substUpdate b o1)

### Substituting an `OutTerm rs2 mid co`

    substOut
      :: WeakenR rs1
      => OutTerm rs2 mid co
      -> OutTerm rs1 ci1 mid
      -> OutTerm (Append rs1 rs2) ci1 co

    substOut (OPack ic2_co wc2_co of2) o1
      | OPack ic1 _ _ <- o1
      = OPack
          (coerceInCtor ic1)            -- the composite's inverse
                                         --   tag — see below.
          wc2_co                        -- wire form is unchanged.
          (substOutFields of2 o1)
      | otherwise
      = error "compose: OFn output not supported as t1 edge output"
    substOut (OFn _) _o1 = error "compose: t2 edge output is OFn (opaque)"

    substOutFields
      :: WeakenR rs1
      => OutFields rs2 mid fs
      -> OutTerm rs1 ci1 mid
      -> OutFields (Append rs1 rs2) ci1 fs

    substOutFields OFNil           _o1 = OFNil
    substOutFields (OFCons t rest)  o1 = OFCons (substTerm t o1)
                                                 (substOutFields rest o1)

The crucial detail in `substOut`'s `OPack` case: the composite's
`OPack` carries `ic1` (the t1 input constructor — the *original*
ci1's payload schema), **not** `ic2_co` (the t2 output's input —
which is over `mid`, not `ci1`). Because the composite consumes
`ci1` and ultimately produces `co`, `solveOutput` on the composite
runs:

    solveOutput composite_OPack regs co
      ↦ wcMatch wc2_co co                     -- co's field tuple
      ↦ gatherInpEntries of_composite tuple ic1
                                              -- gather (ix1, value)
                                              --   pairs against ic1.
      ↦ assemble entries                      -- build RegFile ifs1
      ↦ icBuild ic1 rf                        -- rebuild ci1.

The composite's `of_composite` reads ci1's fields (because every
`TInpCtorField ic2 ix2` got substituted out to a `TInpCtorField
ic1 ix1` from t1's `of1`). So `gatherInpEntries`'s walk sees
`TInpCtorField ic1 ix1` reads, matching `ic1.icName`, and
correctly populates the `ifs1`-shaped register file.


## How the composite preserves the three guarantees

### Guarantee 1: mechanical inversion (`solveOutput`)

The composite's `OPack ic1 wc2_co of_composite` has `of_composite`
reading ci1's fields directly (via the substitution). `solveOutput`
walks the composite's `OutFields` against `wc2_co.wcMatch co`,
gathers per-field reads against `ic1`, and rebuilds ci1.

This is correct iff every field of ci1's payload is visited by
`of_composite`. The keiki `checkHiddenInputs` analysis fires per
edge if any slot of `ic1` is missed; the composite's edges
inherit this check.

There is a subtle *transitive* hidden-input case: a field of ci1
is read by `of1` (so it goes into `mid`), but `of2` doesn't read
that field of `mid`. Then the field is dropped during t2's
projection. After substitution, `of_composite` doesn't read it
either — so `checkHiddenInputs` on the composite catches the
issue at the same severity as a direct hidden input. This is the
right behaviour: a ci1 field that doesn't reach `co` is a hidden
input by transitivity.

### Guarantee 2: build-time hidden-input check (`checkHiddenInputs`)

`checkHiddenInputs` walks every edge and flags:

- ε-edges whose update reads the input symbol (`updateReadsInput`).
- `OFn` outputs (opaque).
- `OPack` outputs whose `OutFields` walk doesn't visit every slot
  of the named `InCtor`.

The composite's edges inherit these checks. Specifically:

- A composite ε-edge (lifted t1 ε-edge) reads ci1's input via the
  lifted update. `updateReadsInput` works structurally on the
  lifted update, so the warning fires identically.
- A composite non-ε-edge has output `OPack ic1 wc2_co
  of_composite`. `detectMissingInCtorFields ic1 of_composite`
  walks of_composite for `TInpCtorField ic1 ix1` reads. Slots of
  ic1 not visited produce a warning naming the missing field —
  exactly as if t1's `OPack` were checked directly.
- If t2's edge has an `OFn` output, the composite emits an `OFn`
  output too (per `substOut` for the `OFn` case which we'd extend
  rather than error in a future revision). The check fires.

### Guarantee 3: symbolic single-valuedness (`isSingleValuedSym`)

For each composite vertex `(s1, s2)`, `isSingleValuedSym` checks
that every pair of outgoing composite edges has a `bot`
(unsatisfiable) guard conjunction.

The composite's edges from `(s1, s2)` are:

- One per t1 ε-edge (output Nothing).
- One per (t1 non-ε edge) × (t2 edge from s2) cross product.

Pairwise conjunctions split into cases:

- **Two ε-edges from t1.** Conjunction is `g1a ∧ g1b` (no t2
  side). `isBot` reduces to "are t1's edges from s1 mutually
  exclusive at this vertex". By assumption (t1 is single-valued
  per the symbolic check), this holds.

- **One ε-edge and one non-ε edge from t1.** Conjunction is
  `(g1a) ∧ (g1b ∧ subst g2 o1b)`. The first conjunct mentions only
  t1's guards on (rs1, ci1); the second adds substituted t2 guards
  on (Append rs1 rs2, ci1). For this to be unsat, `g1a ∧ g1b`
  alone must be unsat (because the substituted t2 guard is
  conjunctive — adding it can't widen the satisfying set). t1's
  single-valuedness gives this.

- **Two non-ε edges from t1, paired with the same t2 edge from
  s2.** Conjunction is `(g1a ∧ subst g2 o1a) ∧ (g1b ∧ subst g2
  o1b)`. The `g1a ∧ g1b` factor is unsat (t1 single-valued).
  Done.

- **Two non-ε edges from t1, paired with different t2 edges from
  s2.** Conjunction is `(g1a ∧ subst g2_x o1a) ∧ (g1b ∧ subst g2_y
  o1b)`. Two cases:

  - `g1a ∧ g1b` unsat (t1 single-valued): conjunction unsat.
  - `o1a == o1b` (same t1 edge in both): means `e1a == e1b`,
    contradicting "two different t1 edges". Skip.
  - `o1a /= o1b`: substituted t2 guards refer to different `o1`s,
    so the constructor tags may differ. Even when constructors
    coincide, `g2_x ∧ g2_y` is unsat by t2's single-valuedness at
    s2.

  Either way, unsat.

- **Same t1 edge paired with two t2 edges from s2.** Conjunction
  is `(g1 ∧ subst g2_x o1) ∧ (g1 ∧ subst g2_y o1) = g1 ∧ (subst
  g2_x o1 ∧ subst g2_y o1)`. The substitution distributes over
  conjunction (`subst (g2_x ∧ g2_y) o1 = subst g2_x o1 ∧ subst
  g2_y o1`). t2's single-valuedness at s2 gives `g2_x ∧ g2_y`
  unsat at the source level; the substitution preserves
  unsatisfiability (it's a syntactic rewrite), so the composite
  conjunction is unsat.

So **the composite is single-valued whenever t1 and t2 are
individually single-valued.** This is the compositionality
property the design wants.

This is provable as a lemma; the test suite verifies it on the
worked example by calling `isSingleValuedSym` on the composite
and observing `True`. The proof above guarantees the test will
pass when t1 and t2 individually pass.


## What `compose` does **not** preserve

- **Liveness.** A composite edge `(e1, e2)` may be dead even when
  both `e1` and `e2` are live in their respective machines, because
  the substituted guard `g1 ∧ subst g2 o1` may be unsat (e.g.
  `o1`'s constructor doesn't match `e2`'s expected ctor). This is
  semantically correct (dead edges contribute nothing to runtime
  behaviour) and consistent with the keiki formalism (dead edges
  exist freely; `delta` filters via `models`).

- **Strict topology.** The composite's edge graph is a `(s1, s2)`
  cross-product; not every reachable pair from `(initial t1,
  initial t2)` is genuinely reachable in the composite. crem's
  type-level topology would catch this at compile time; keiki
  doesn't aspire to that (item G in the design note, deferred to a
  v3 MasterPlan).


## Limitations and escape hatches

`compose`'s structural substitution requires:

1. **t1's outputs are all `OPack`** (no `OFn`). If t1 has an `OFn`
   edge output, the composite errors at the substitution step.
   Workaround: restructure the t1 transducer to use `OPack` (the
   v2 keiki style); `OFn` is the v1 escape hatch.

2. **t2's guards on `mid` are structural** (`PInCtor`, `PEq` over
   `TInpCtorField` reads, no `PMatchC`). If t2 uses `PMatchC` over
   `mid`, the composite errors. Workaround: use `matchInCtor` /
   `inpCtor` instead.

3. **t2's outputs are all `OPack`** (no `OFn`). Same rationale.

When any of these is violated, `compose` raises a runtime error
naming the offending edge. A future improvement is graceful
fallback: emit a composite edge whose guard / output is wrapped in
`PMatchC` / `OFn` and let `checkHiddenInputs` flag it. EP-11 does
not implement that fallback; the error makes the limitation
visible.


## Worked example — process manager

The worked example in EP-11 demonstrates `compose` on a small
multi-aggregate scenario.

### The Email Delivery aggregate

A second aggregate, modelled as a 2-vertex transducer over a
single command and a single event:

    data EmailVertex = EmailPending | EmailSentVertex
      deriving (Eq, Show, Enum, Bounded)

    data SendEmailData = SendEmailData
      { recipient :: Text
      , subject   :: Text
      , at        :: UTCTime
      } deriving (Eq, Show, Generic)
    data EmailCmd = SendEmail SendEmailData
      deriving (Eq, Show, Generic)

    data EmailSentData = EmailSentData
      { recipient :: Text
      , subject   :: Text
      , at        :: UTCTime
      } deriving (Eq, Show, Generic)
    data EmailEvent = EmailSent EmailSentData
      deriving (Eq, Show, Generic)

    type EmailRegs =
      '[ '("emailRecipient", Text)
       , '("emailSubject",   Text)
       , '("emailSentAt",    UTCTime)
       ]

    emailDelivery
      :: SymTransducer (HsPred EmailRegs EmailCmd)
                       EmailRegs EmailVertex EmailCmd EmailEvent

The single transition is:

    EmailPending ⨯ SendEmail d → EmailSentVertex emitting EmailSent

with an `OPack` output whose fields read `d`'s payload via
`TInpCtorField inCtorSendEmail #recipient/#subject/#at`.

### The process manager

A process manager observes `UserEvent` and emits `EmailCmd`. The
relevant transition: when a `ConfirmationEmailSent` event is
observed, emit `SendEmail` with the recipient set from the event's
`email` field.

    data PmVertex = PmInitial | PmDispatched
      deriving (Eq, Show, Enum, Bounded)

    type PmRegs = '[]

    confirmationEmailProcessManager
      :: SymTransducer (HsPred PmRegs UserEvent)
                       PmRegs PmVertex UserEvent EmailCmd

The single transition (encoded with substitution-friendly
structure):

    PmInitial ⨯ ConfirmationEmailSent d → PmDispatched
      emitting SendEmail
        (SendEmailData
           { recipient = d.email
           , subject   = "Welcome"
           , at        = ...                      -- a fresh literal
           })

The guard reads `PInCtor inCtorConfirmationEmailSent` (an
`InCtor UserEvent (RegFieldsOf ConfirmationEmailSentData)`).

### The full composite

    fullSystem
      :: SymTransducer
           (HsPred (Append UserRegRegs (Append PmRegs EmailRegs)) UserCmd)
           (Append UserRegRegs (Append PmRegs EmailRegs))
           (Composite Vertex (Composite PmVertex EmailVertex))
           UserCmd
           EmailEvent
    fullSystem = compose userReg
                          (compose confirmationEmailProcessManager
                                   emailDelivery)

The acceptance test in `test/Keiki/CompositionSpec.hs` covers:

1. **Single-valuedness.** `isSingleValuedSym (withSymPred
   fullSystem)` reports `True`.
2. **Hidden-input check.** `checkHiddenInputs fullSystem` reports
   `[]` (no warnings).
3. **Round-trip.** Replaying the canonical event log
   `[EmailSent ..., ...]` through `reconstitute fullSystem` lands
   at the expected final composite state.


## Combinators beyond `compose` — per-combinator design records

This section is owned by EP-24 of MasterPlan 8
(`docs/plans/24-composition-combinators-beyond-sequential-design-milestone.md`).
EP-24 re-evaluated the four combinators that EP-11 deferred —
`parallel`, `alternative`, `feedback`, `Kleisli` — against the
post-MP-1..MP-7 keiki core, and produced the verdicts below. Each
admitted combinator gets its own record (signature, semantics,
single-step example, preservation arguments, acceptance criteria).
Each re-deferred combinator gets a "Re-deferred" record naming the
deferral conditions and pointing to the sibling research that
covers the same need. The post-MP-6 retirements (`OFn` retired in
EP-16, `PMatchC` retired in EP-17) eliminate the substitution
caveats EP-11 listed for `compose`, simplifying the new
combinators' design surface.


### `alternative` — admitted

> **2026-05-03 update (EP-25 M4 implementation discovery).** The
> original design specified a sum vertex `CompositeSum s1 s2 = InL
> s1 | InR s2` with `initial = InL (initial t1)`. EP-25's
> acceptance tests revealed this is degenerate: the composite has
> no path from `InL` to `InR`, so it is stuck in t1's arm forever.
> The intended semantics — sibling aggregates with **independent
> state** evolving in parallel as Left/Right inputs arrive —
> requires the *product* vertex `Composite s1 s2` (the same
> vertex `compose` already uses). Each composite vertex emits the
> union of t1's edges (gated on `Left`, target keeps t2's
> sub-vertex) and t2's edges (gated on `Right`, target keeps t1's
> sub-vertex). The signature, semantics, and preservation
> arguments below are the **revised** form that EP-25 actually
> shipped.

#### Signature

    alternative
      :: forall rs1 rs2 s1 s2 ci1 ci2 co1 co2.
         ( WeakenR rs1
         , Disjoint (Names rs1) (Names rs2)
         )
      => SymTransducer (HsPred rs1 ci1) rs1 s1 ci1 co1
      -> SymTransducer (HsPred rs2 ci2) rs2 s2 ci2 co2
      -> SymTransducer
           (HsPred (Append rs1 rs2) (Either ci1 ci2))
           (Append rs1 rs2)
           (Composite s1 s2)
           (Either ci1 ci2)
           (Either co1 co2)

The composite consumes `Either ci1 ci2`: a `Left ci1` routes to t1,
a `Right ci2` routes to t2. The composite emits `Either co1 co2`
correspondingly. The vertex type is the **product** `Composite s1
s2` — the same newtype `compose` uses. Each composite vertex
holds both sub-aggregates' states; each step advances exactly one
arm.

The `Disjoint (Names rs1) (Names rs2)` constraint matches `compose`'s
existing requirement: the appended register file's slot-name domain
is the disjoint union of the two halves. The `WeakenR rs1` constraint
is symmetric to `compose`'s — it lifts t2's indices across the rs1
prefix. (t1's indices use `weakenL` as in `compose`.)

#### Semantics

The composite's edges from `Composite s1 s2` are the union of:

- **t1's edges from `s1`, lifted to fire on `Left` inputs.** Each
  yields a composite edge whose target is `Composite (target e1)
  s2` — t1's sub-vertex advances; t2's stays put.

      Edge
        { guard  = liftLPredAlt @ci2 (weakenLPred (guard e1))
        , update = liftLUpdateAlt @ci2 (weakenLUpdate (update e1))
        , output = fmap (liftLOutAlt @ci2 @co2 . weakenLOut) (output e1)
        , target = Composite (target e1) s2
        }

- **t2's edges from `s2`, lifted to fire on `Right` inputs.**
  Each yields a composite edge whose target is `Composite s1
  (target e2)` — t2's sub-vertex advances; t1's stays put.

      Edge
        { guard  = liftRPredAlt @ci1 (weakenRPred (guard e2))
        , update = liftRUpdateAlt @ci1 (weakenRUpdate (update e2))
        , output = fmap (liftROutAlt @ci1 @co1 . weakenROut) (output e2)
        , target = Composite s1 (target e2)
        }

The lifters `liftL*Alt` walk the relevant AST and adjust the input
type from `ci1` to `Either ci1 ci2`: every `TInpCtorField (ic1 ::
InCtor ci1 ifs) ix` becomes `TInpCtorField (leftInCtor ic1 :: InCtor
(Either ci1 ci2) ifs) ix`, where `leftInCtor` constructs an
`InCtor` whose `icMatch :: Either ci1 ci2 -> Maybe (RegFile ifs)`
matches only on the `Left` arm and runs the underlying `ic1.icMatch`.
The output `OPack` similarly adjusts: every `OPack ic_co wc_co of`
becomes `OPack (leftInCtor ic_co) (leftWireCtor wc_co) of`, where
`leftWireCtor` matches only on `Left co1` and constructs `Left .
wc_co.wcBuild`.

Symmetric lifters `liftR*Alt` handle the t2 side.

`isFinal` of the composite is:

    \(Composite s1 s2) -> isFinal t1 s1 && isFinal t2 s2

Both sub-aggregates must reach a final state for the composite to
be final.

The initial vertex is `Composite (initial t1) (initial t2)` — both
arms start in their respective initial states.

#### Single-step example

Two sibling aggregates (using EP-25's actual fixture):

- `emailDelivery :: SymTransducer ... EmailCmd EmailEvent` (the
  canonical `Keiki.Examples.EmailDelivery`).
- `pinger :: SymTransducer ... PingCmd PingEvent` (an inline
  Pinger fixture in `test/Keiki/CompositionAlternativeSpec.hs`).

The composite:

    siblings :: SymTransducer
                  (HsPred (Append EmailRegs PingRegs) (Either EmailCmd PingCmd))
                  (Append EmailRegs PingRegs)
                  (Composite EmailVertex PingVertex)
                  (Either EmailCmd PingCmd)
                  (Either EmailEvent PingEvent)
    siblings = alternative emailDelivery pinger

A single Left-arm step from initial:

    step siblings (Composite EmailPending PingIdle, initialRegs)
         (Left (SendEmail d))
      = Just ( (Composite EmailSentVertex PingIdle, regsAfterEmail)
             , Just (Left (EmailSent ...)) )

The `SendEmail` advances the EmailDelivery arm to `EmailSentVertex`;
the Pinger arm stays at `PingIdle`. A subsequent Right-arm step:

    step siblings (Composite EmailSentVertex PingIdle, regsAfterEmail)
         (Right (Ping d))
      = Just ( (Composite EmailSentVertex PingDone, regsAfterPing)
             , Just (Right (Pong ...)) )

The `Ping` advances Pinger to `PingDone`; EmailDelivery stays at
`EmailSentVertex`. Each arm's state is preserved across the other
arm's transitions.

#### Preservation arguments

##### Guarantee 1 — `solveOutput`

A Left-arm composite output is `OPack (leftInCtor ic) (leftWireCtor
wc) of_lifted`. `solveOutput composite_OPack regs (Left co1)` runs:

    (leftWireCtor wc).wcMatch (Left co1)
      = wc.wcMatch co1

then walks `of_lifted` (which is `of` from t1's edge with every
`TInpCtorField` adjusted to read the `Left` arm) and rebuilds via
`(leftInCtor ic).icBuild (RegFile ifs1) = Left (ic.icBuild ...)`.
The wrapping is structural; inversion is preserved end-to-end. The
Right-arm side is symmetric.

A composite output of the wrong arm (e.g. inverting `Left _` against
a Right-arm `OPack`) returns `Nothing` immediately at
`(leftWireCtor wc).wcMatch (Left _)` — sound.

##### Guarantee 2 — `checkHiddenInputs`

Each side's check inherits per edge: every t1 edge contributes a
hidden-input warning if and only if the lifted-into-alternative
edge does. The lifting is structural (it preserves
`TInpCtorField` slot reads), so the analysis sees the same field
visit pattern. The composite's warning list is the union of t1's
and t2's per-edge warnings.

##### Guarantee 3 — `isSingleValuedSym`

At composite vertex `Composite s1 s2`, the outgoing edges split
into two groups:

- t1-lifted edges, all carrying `PInCtor (leftInCtor _)` somewhere
  in their guard — guards that match only on `Left _` inputs.
- t2-lifted edges, all carrying `PInCtor (rightInCtor _)`
  somewhere in their guard — guards that match only on `Right _`
  inputs.

For pairwise conjunctions:

- Two t1-lifted edges: conjunction reduces to t1's underlying
  guards' conjunction; unsat iff t1 is single-valued at s1.
- Two t2-lifted edges: symmetric — unsat iff t2 is single-valued
  at s2.
- One t1-lifted + one t2-lifted: conjunction includes
  `PInCtor (leftInCtor _) ∧ PInCtor (rightInCtor _)`, which is
  unsat (an input cannot be both `Left _` and `Right _`).

So the composite is single-valued whenever t1 and t2 are
individually single-valued. **No new cross-transducer
mutual-exclusion check is needed** — the `Either` arms make the
cross-side unsatisfiability automatic via the lifted `PInCtor`
guards.

#### Limitations

- The composite's vertex space is `|s1| × |s2|` (product). Symbolic
  analysis cost is proportional to the product.
- The composite's edge count at each vertex is
  `|edgesOut t1 s1| + |edgesOut t2 s2|`. Per-vertex single-valuedness
  checks compare every pair, so SBV cost grows quadratically with
  the per-vertex edge count.
- The Left-arm and Right-arm aggregates are entirely independent —
  they do not share state, do not observe each other's events, and
  do not synchronize. Authors who need cross-aggregate coordination
  use `compose` (for sequential coordination) or `feedback1` (for
  aggregate ↔ policy round trips).

#### Acceptance criteria for the implementation EP

The per-combinator EP that ships `alternative` must:

1. Add `alternative` and the `liftL*Alt` / `liftR*Alt` family
   (plus the right-side weakening helpers `weakenR*` and the
   output-side weakening helpers `weakenL*Out`) to
   `src/Keiki/Composition.hs` (no new module).
2. Reuse the existing `Composite s1 s2` vertex (no new vertex
   newtype needed).
3. Add an acceptance test under
   `test/Keiki/CompositionAlternativeSpec.hs` that:
   - Composes a fixture aggregate (e.g.
     `Keiki.Examples.EmailDelivery`) with a small inline sibling.
   - Verifies `step` routes correctly on `Left` and `Right` inputs
     and preserves the other arm's sub-vertex.
   - Verifies the interleaved-step case where both arms advance
     independently across the call sequence.
   - Verifies `omega` produces `Left` and `Right` outputs.
   - Verifies `reconstitute` round-trips a mixed-arm event log in
     both orderings (Left+Right and Right+Left).
   - Verifies `checkHiddenInputs` reports `[]` on the composite
     (assuming both sides are clean).
   - Verifies `isSingleValuedSym (withSymPred composite)` returns
     `True`.
4. Update this section with a "What we shipped" subsection
   summarising any divergence from this record.

#### What we shipped (EP-25, 2026-05-03)

EP-25 implemented the **revised** design above (product vertex
`Composite s1 s2`, not the originally-specified sum vertex
`CompositeSum`). The implementation lives in
`src/Keiki/Composition.hs:683-797` (the `alternative` body, the
`liftEdgeL` / `liftEdgeR` helpers) plus the lifter family
introduced earlier in the same file: `leftInCtor` /
`rightInCtor`, `leftWireCtor` / `rightWireCtor`,
`liftLTermAlt` / `liftRTermAlt`, `liftLPredAlt` / `liftRPredAlt`,
`liftLUpdateAlt` / `liftRUpdateAlt`, `liftLOutFieldsAlt` /
`liftROutFieldsAlt`, `liftLOutAlt` / `liftROutAlt`. The
right-side AST-walking weakening helpers (`weakenRTerm`,
`weakenRPred`, `weakenRUpdate`, `weakenROutFields`, `weakenROut`)
and the output-side helpers (`weakenLOutFields`, `weakenLOut`)
were added in the same EP and are reusable by future
combinators.

The acceptance test at `test/Keiki/CompositionAlternativeSpec.hs`
covers nine cases — Left/Right/interleaved step routing,
mixed-arm reconstitute (both orderings), omega for both arms,
`checkHiddenInputs` returning `[]`, and `isSingleValuedSym
(withSymPred siblings)` returning `True` — and all pass against
EP-25's actual fixture (EmailDelivery + an inline Pinger).

Divergences from the record above:

- **Vertex shape.** The original record specified the sum
  `CompositeSum s1 s2`. EP-25's M4 acceptance tests surfaced the
  degeneracy and the implementation switched to the product
  `Composite s1 s2`. Recorded in EP-25's Surprises &
  Discoveries; the corrected analysis is what this section
  documents.
- **No `CompositeSum` type added.** The originally-proposed
  newtype is not in the shipped module.
- **`isFinal` requires both arms final.** The original record
  said "asymmetric (only one side is final at a time)"; the
  product vertex makes both-sides-final the natural definition.


### `feedback1` — admitted (single-step reduction)

#### Signature

    feedback1
      :: forall rs1 rs2 s1 s2 ci co.
         ( WeakenR rs1
         , Disjoint (Names rs1) (Names rs2)
         )
      => SymTransducer (HsPred rs1 ci)  rs1 s1 ci  co
      -> SymTransducer (HsPred rs2 co)  rs2 s2 co  ci
      -> SymTransducer (HsPred (Append rs1 (Append rs2 rs1)) ci)
                       (Append rs1 (Append rs2 rs1))
                       (Composite s1 (Composite s2 s1))
                       ci
                       co

The composite is `compose t (compose policy t)` rendered as a single
combinator: t's output `co` drives the policy, the policy's output
`ci` drives a second copy of t, and the final output is t's `co`.
"Single-step" means exactly one round of policy reaction per external
command. Multi-round patterns are expressed by composing multiple
`feedback1`s.

The asymmetry in the register file (`Append rs1 (Append rs2 rs1)`)
reflects that t appears twice; the second t copy reads its own slot
prefix. Implementation note: the second t may share state with the
first via shared `rs1`; the per-vertex enumeration in
`isSingleValuedSym` walks the composite's full product vertex.

#### Semantics

`feedback1 t f = compose t (compose f t')` where `t'` is a re-keyed
copy of `t`. The "re-keyed copy" detail is necessary because the
two t-instances must have distinct vertex labels in the composite —
the symbolic analysis would otherwise incorrectly merge them. The
implementation EP wraps t's vertex type as `T2 s1` to disambiguate.

The composite's edges from `Composite s1 (Composite s2 s1')` (where
`s1'` is the re-keyed t1 vertex):

1. **Round 1 — t consumes the external `ci`.** Each t edge from
   `s1` produces a `co` that feeds the policy.
2. **Round 2 — policy consumes `co`, produces `ci'`.** Each policy
   edge from `s2` produces a `ci'` that feeds the second t.
3. **Round 3 — the second t consumes `ci'`, produces the final
   `co'`.** Each second-t edge from `s1'` produces the composite's
   `co'`.

These three rounds are folded into one composite edge per (t edge
× policy edge × t edge) triple via two applications of `compose`'s
substitution algorithm.

#### Single-step example

A toy example: aggregate produces an event, policy emits a follow-up
command, aggregate processes it.

    aggregate :: SymTransducer ... AggCmd AggEvent
    policy    :: SymTransducer ... AggEvent AggCmd  -- stateless

    loop :: SymTransducer ... AggCmd AggEvent
    loop = feedback1 aggregate policy

`step loop initial externalCmd` advances the aggregate, runs the
policy on the resulting event to compute a follow-up command,
advances the aggregate again with the follow-up, and emits the
second aggregate event as the composite's output.

#### Preservation arguments

The composite is two `compose` applications stacked. The
preservation arguments for `solveOutput`, `checkHiddenInputs`, and
`isSingleValuedSym` inherit from `compose`'s existing arguments
(see "How the composite preserves the three guarantees" above).
The single-step reduction's purity is trivial because there is no
loop.

#### Limitations

- The vertex space grows multiplicatively: `|s1| * |s2| * |s1|`.
  Authors who need many feedback rounds nest `feedback1`s, which
  multiplies the vertex space further. A bounded-step variant (with
  a fuel parameter) is documented as a future improvement; it is
  not shipped in MP-8.
- The "stateless policy" requirement is convention, not enforced —
  `f` is any `SymTransducer` whose register file the user accepts.
  In practice, a policy with non-trivial state defeats the
  single-step semantics (the policy's own edges may iterate across
  composite steps). The implementation EP's documentation must
  explain.
- Termination is trivial (no loop), so MP-8's bounded-iteration
  concern is moot.

#### Acceptance criteria for the implementation EP

The per-combinator EP that ships `feedback1` must:

1. Add `feedback1` to `src/Keiki/Composition.hs` (no new module).
2. Add an acceptance test under `test/Keiki/CompositionSpec.hs` (or
   a sibling spec module) that:
   - Composes a fixture aggregate with a stateless one-vertex
     policy and verifies the cascade produces the expected
     composite output for a sample external command.
   - Verifies `checkHiddenInputs` reports `[]`.
   - Verifies `isSingleValuedSym (withSymPred composite)` returns
     `True`.
3. Document the bounded-step variant as a future extension in the
   module haddock.
4. Update `docs/research/composition-combinators-design.md`'s
   `feedback1` section with a "What we shipped" subsection.


#### What we shipped (EP-26, 2026-05-03)

`feedback1` shipped to `src/Keiki/Composition.hs` with the literal
implementation `feedback1 t f = compose t (compose f t)`. The
acceptance test lives at `test/Keiki/CompositionFeedback1Spec.hs`.

The implementation aligned with the design record on three points
and deviated on two.

**Aligned.**

1. *Vertex shape.* `Composite s1 (Composite s2 s1)`. EP-26's M1
   picked option (b) — implicit by structure. No `T2 s1` newtype
   was needed because `Composite`'s existing column-major `Enum`
   instance enumerates the inner `s1` as a distinct dimension.
   `isSingleValuedSym`'s per-vertex enumeration walks the full
   `|s1| * |s2| * |s1|` product without conflation.
2. *Implementation = two stacked `compose`s.* No bespoke edge
   construction; the cascade is built by `compose`'s existing
   substitution algorithm applied twice.
3. *Pure-core preservation.* The composite preserves `solveOutput`,
   `checkHiddenInputs`, and `isSingleValuedSym` because each
   `compose` does, and stacking preserves the property.
   Acceptance spec confirms all three on a toggle ↔ echo-policy
   fixture.

**Deviated.**

1. *Constraint set.* The "Acceptance criteria" listed a signature
   with `WeakenR (Append rs1 rs2)` and
   `Disjoint (Names (Append rs1 rs2)) (Names rs1)` constraints.
   The actual constraints required by `compose t (compose f t)`,
   derived mechanically by tracing `compose`'s constraints applied
   twice, are:

   - `WeakenR rs2` (inner `compose f t`'s rs_l).
   - `Disjoint (Names rs2) (Names rs1)` (inner `compose`).
   - `WeakenR rs1` (outer `compose t _`'s rs_l).
   - `Disjoint (Names rs1) (Names (Append rs2 rs1))` (outer
     `compose`).

   The shipped signature uses these four. The original set was a
   transcription error.

2. *Stateless-aggregate restriction.* The shipped `feedback1` only
   typechecks at the call site when the aggregate `t`'s register
   file `rs1 = '[]`. The constraint
   `Disjoint (Names rs1) (Names (Append rs2 rs1))` forces
   `Names rs1` to be disjoint from itself, which only succeeds for
   the empty list. This is an inevitable consequence of the
   "two-stacked-`compose`" reduction: keiki's slot-disjointness
   invariant gives each appearance of `t` its own register file
   copy, and disallows duplicate slot names in the composite.

   For non-empty `rs1`, the call site fails with a slot-collision
   `TypeError`. Authors needing a stateful aggregate inside a
   feedback loop must currently express the loop differently
   (e.g. by encoding the policy's reaction as an extra edge inside
   the aggregate via MP-7's state refinement).

   A "shared-state" variant — where the second `t` reads/writes
   the first `t`'s registers via custom edge construction outside
   `compose` — is documented as a future extension and is **not in
   scope** for MP-8. EP-26's Decision Log entry dated 2026-05-03
   records this trade-off.

The acceptance fixture is a toggle aggregate (Off ↔ On) cascaded
through a stateless echo policy. The cascade is observable from the
composite vertex transition: from
`Composite Off (Composite Pol Off)`, one external command advances
the composite to `Composite On (Composite Pol On)` — both copies of
t have stepped, proving the policy's emitted command was consumed
by the second t. The output's `tValue` field is the original
input's `tValue`, forwarded through the cascade by structural
substitution; `checkHiddenInputs` therefore reports `[]`. Suite:
185 examples, 0 failures (was 178 pre-EP-26, +7 new).


### `parallel` — re-deferred

#### Why re-deferred

Crem's `Parallel :: StateMachineT m a b -> StateMachineT m c d ->
StateMachineT m (a, c) (b, d)` runs both sub-machines on a strict
tuple input, stepping in lock-step. keiki's runtime model (per
`docs/research/effects-boundary.md` §"What the runtime is responsible
for") delivers one command at a time from a queue; there is no
natural source of paired `(ci1, ci2)` inputs in event sourcing. The
use cases MP-8's Vision section listed for `parallel` ("product
aggregates, e.g. distinct bounded contexts within one service") are
operationally *sum* inputs (each external command lands in one
bounded context per tick), which is the `alternative` shape, not the
`parallel` shape.

Two independent transducers with no shared input or register file
produce nothing the user couldn't get by running them as two
separate aggregates with separate queue subscriptions. The composite
does not unlock new symbolic analyses (each side's analyses run
independently). Bundling them into a `Composite s1 s2`-vertexed
transducer would only matter if the user needs the composite as a
single unit for visualization or storage — both of which are runtime
concerns, not pure-formalism concerns.

#### Deferral conditions

Admit `parallel` if and only if a future authoring need surfaces a
paired-input pattern that cannot be modelled as `alternative`. The
canonical such need would be a runtime that genuinely batches
commands across bounded contexts per tick (e.g. a transactional
multi-aggregate write). MP-8 does not deliver such a runtime, and
no current keiki user has requested one.

The deferral does not block MP-9 (Profunctor / Category instances).
MP-9 ships `Strong` only if `parallel` is admitted, but `Choice`
(the more useful instance for command routing) ships on
`alternative` alone.


### `Kleisli` — re-deferred

#### Why re-deferred

Crem's `Kleisli :: StateMachineT m a (n b) -> StateMachineT m b (n
c) -> StateMachineT m a (n c)` lifts sequential composition over a
`Foldable` of inner events. keiki's edge form
(`Edge.output :: Maybe (OutTerm rs ci co)`, defined at
`src/Keiki/Core.hs:458`) emits at most one event per step. Lifting
to multi-event edges requires Approach 3 ("MultiDecider") from
`docs/research/multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md`,
which would widen `Edge.output` to `[OutTerm rs ci co]` and is
explicitly out of MP-8's scope per its Out-of-Scope item 4.

Within MP-8's scope, `Kleisli` collapses to `compose` for the
single-event case keiki actually supports; admitting it would
duplicate `compose` without adding capability.

#### Deferral conditions and redirect

Re-evaluate `Kleisli` if and only if a future MasterPlan promotes
Approach 3 to ship status. Until then, multi-event commands within
one transducer are written via Approach 1 (state refinement, per
MP-7 / EP-20). The relevant ergonomics are:

- `Keiki.Builder.chainTo` for syntactic compression of multi-event
  edge authoring.
- `Keiki.Decider.toMultiDecider` (with `DriverConfig`) for a
  decider façade that drives multi-event chains end-to-end without
  exposing intermediate vertices.
- `Keiki.Core.applyEvents` for chunk replay over a list of events.

Cross-transducer multi-event composition (the use case `Kleisli`
would unlock) has no documented authoring need yet. If one surfaces,
a successor MasterPlan can reopen the question with a v3-class
multi-event edge proposal.


### Profunctor / Strong / Choice instances — out of scope

These are the remit of MasterPlan 9
(`docs/masterplans/9-profunctor-and-category-instances-on-symtransducer.md`,
created alongside MP-8). MP-9 has a soft dependency on MP-8: the
instances it ships are parameterised over the combinators MP-8
actually delivers (concretely: `Choice` follows from `alternative`;
`Category` follows from `compose`; `Strong` is contingent on a
future `parallel` admission). MP-8 ships only the combinators
themselves.


### Graceful fallback for non-structural transducers — moot post-MP-6

EP-11's design note flagged "graceful fallback when t1 has `OFn`
outputs or t2 has `PMatchC` guards" as a future improvement. After
MP-6 (escape-hatch retirements: EP-16 retired `OFn`, EP-17 retired
`PMatchC`), no aggregate authored against the post-MP-6 core has
either form. The fallback is moot. New combinators (`alternative`,
`feedback1`) inherit `compose`'s structural-only contract by
construction and do not need to enumerate fallback rules.


### Static topology safety — out of scope (item G in keiki-generics-design)

crem's compile-time transition enforcement would prevent
constructing composite edges that could never fire. keiki has no
such facility; its `Composite (s1, s2)` and (admitted)
`CompositeSum s1 s2` are the full cross product / disjoint union.
Future v3 work, tracked separately in
`docs/research/keiki-generics-design.md`'s item G.


## Decision summary

### EP-11 / MasterPlan 4 (the original `compose` work)

| Question                                  | Decision                                |
|-------------------------------------------|-----------------------------------------|
| How many combinators in EP-11?            | One — `compose`.                        |
| Module placement                          | New module `Keiki.Composition`.         |
| Predicate carrier                         | `HsPred` (substitution walks AST).      |
| Composite vertex type                     | newtype `Composite s1 s2`.              |
| Composite register file                   | `Append rs1 rs2`.                       |
| Behaviour on t1 ε-edges                   | Composite ε-edge; t2 doesn't step.      |
| Behaviour on t2 ε-edges                   | Composite ε-edge; both machines step.   |
| Behaviour on `OFn` / `PMatchC` in inputs  | Runtime error naming the edge.          |
| MasterPlan fan-out                        | Not needed; EP-11 ships single combinator. |

These decisions are recorded in EP-11's Decision Log with the
date 2026-05-02 and the rationale captured in the matching
sections above.

### EP-24 / MasterPlan 8 (the design milestone for additional combinators)

| Question                                                       | Decision                                            |
|----------------------------------------------------------------|-----------------------------------------------------|
| Which of the four MP-8 combinators are admitted?               | `alternative` and `feedback1`. `parallel` and `Kleisli` are re-deferred. |
| `feedback`'s iteration model                                   | Single-step `feedback1 t f`. Pure trivially; multi-round patterns nest `feedback1`s. |
| `alternative`'s mutual-exclusion check                         | None new. The `Either ci1 ci2` input alphabet makes the cross-transducer check vacuous; `isSingleValuedSym` on the composite suffices. |
| `Kleisli`'s status                                             | Re-deferred. Requires the multi-event edge form (Approach 3 in the multi-event note); MP-7's state-refinement covers the in-aggregate case. |
| `parallel`'s status                                            | Re-deferred. The strict-tuple shape doesn't fit keiki's queue-driven runtime; `alternative` covers the bounded-context use case. |
| Module shape for new combinators                               | Extend `Keiki.Composition`. New combinators reuse `WeakenR` / `weakenL*` / `subst*`. |
| Composite vertex type for `alternative`                        | Reuses `Composite s1 s2` (product). Originally specified `CompositeSum` (sum); EP-25 M4 surfaced the sum-vertex degeneracy and switched to product. |
| Composite register file for `alternative` and `feedback1`     | `Append rs1 rs2` (for `alternative`); `Append rs1 (Append rs2 rs1)` (for `feedback1`, since t appears twice). |
| MasterPlan fan-out                                             | Two child EPs: one for `alternative`, one for `feedback1`. |

These decisions are recorded in EP-24's Decision Log with the date
2026-05-03 and the rationale captured in the per-combinator
sections above.
