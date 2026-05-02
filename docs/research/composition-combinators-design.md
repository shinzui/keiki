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


## Future improvements (deferred)

- **`feedback`** — fixed-point combinator for aggregate ↔ policy
  loops. Requires either a bounded iteration scheme or a
  termination proof. Defer to a follow-up EP.

- **`alternative`** — disjoint-input parallel composition. The
  single-valuedness check needs to verify the two underlying
  transducers' guards are globally mutually exclusive. Separate
  design milestone.

- **`parallel`** — independent parallel composition with a
  `(ci1, ci2)` input. Useful for product-of-aggregates models.

- **`Kleisli`** — generalisation of `compose` over multi-event
  edges. Requires a multi-event edge form (synthesis §5
  MultiDecider; out of v2 scope).

- **Profunctor / Strong / Choice instances.** Replicating crem's
  hierarchy. Tied to general structural algebraic upgrades.

- **Graceful fallback for non-structural transducers.** Currently
  `compose` errors when t1 has `OFn` outputs or t2 has `PMatchC`
  guards. A future revision could emit composite edges with
  appropriate escape hatches and let `checkHiddenInputs` flag
  them. The cost is added complexity in the substitution code;
  the benefit is composing with v1-style escape-hatched
  aggregates.

- **Static topology safety.** crem's compile-time transition
  enforcement would prevent constructing composite edges that
  could never fire. keiki has no such facility (item G in the
  design note); its Composite `(s1, s2)` is the full cross
  product. Future v3 work.


## Decision summary

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
