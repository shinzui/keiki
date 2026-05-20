# Direction C: Symbolic and Register Automata as a Basis for keiki

The base `Transducer s c e` requires `(Enum, Bounded)` on every parameter.
That is what makes input/output projection, deadlock detection, and
exhaustive contract checks possible — and what keeps payload data off the
formal map. `StartRegistration Email`, `SubmitApproval UserId`,
`ActivitySucceeded ActivityId Result`: in such a model these are tags
and the data they carry lives in an opaque `ctx`, opaque to δ and ω.
Guards over `ctx` work at runtime but evaporate the moment we try to
*enumerate* anything.

This note picks the **symbolic / register / nominal** family off that
landscape and asks what would actually carry over into a Haskell library.
The other directions are scoped elsewhere.

---

## 1. The Survey, Compressed

### Symbolic Finite Transducers (SFTs)

Veanes, Hooimeijer, Livshits, Molnar, Bjorner (POPL 2012). Edges are
labelled with **predicates** ψ over an *effective Boolean algebra* with
decidable satisfiability — typically SMT. A transition `s --[ψ / f]--> s'`
fires when the input satisfies ψ, with output the term `f` over the input.
The alphabet is described, not enumerated. With a decidable alphabet
theory you keep: closure under intersection / complement; **composition**
of single-valued SFTs; **equivalence** for single-valued SFTs; emptiness;
pre-image (D'Antoni & Veanes, *Automata Modulo Theories*, CACM 2021). Cost:
every analytical operation calls the SMT solver. The **Extended SFT**
variant (multi-symbol reads) loses closure under composition and
equivalence becomes undecidable (D'Antoni/Veanes, FMSD 2015) — a sharp
warning about how easily these properties break.

### Register Automata (Kaminski–Francez Finite-Memory Automata)

Kaminski & Francez 1994. Finite control + a finite tuple of registers
holding values from an infinite domain. Transitions read, compare for
equality with a register, and store. Equality only — no order, no
arithmetic. **Emptiness is decidable**; closed under union and
intersection; **universality and equivalence are undecidable** in general
(Neven, Schwentick, Vianu 2004; Demri & Lazic 2009). The **single-use**
restriction (Bojańczyk, arXiv 1907.10504, 2019) — registers consumed on
use — recovers a much more robust theory with decidable equivalence in
the deterministic case.

### Streaming String Transducers (SSTs)

Alur & Černý, POPL 2011. Deterministic one-way transducer with a finite
set of string-valued registers that can be concatenated and reassigned
linearly (**copyless** — no register content may be duplicated on a
transition). Captures exactly the MSO-definable string transformations.
**Equivalence is decidable** for copyless SSTs, including the
finite-valued case (Muscholl & Puppis, ICALP 2019). For keiki, the
interesting feature isn't string-output — it's the *structural pattern*: a
finite control graph whose transitions update a small typed register file
under explicit, copyless rules. That pattern fits an event-sourced
workflow far better than SFT predicates alone.

### Nominal Automata

Bojańczyk, Klin, Lasota, *Automata theory in nominal sets* (LMCS 2014).
Sets with an action of a symmetric group on infinite atoms, finitely
supported. Slogan: program over an infinite domain as if it were finite,
with α-equivalence and freshness first-class. Classical decidability
lifts. The catch: you must build the nominal-set machinery (orbits,
supports, equivariant functions). Haskell support is research-grade. Best
fit when the data domain has *binding structure* — names, scopes,
channels — which is not where most workflow data lives.

### Skipped

- **Symbolic Visibly Pushdown / Tree Transducers** (D'Antoni 2015):
  hierarchical workflows. Out of scope for v1; the place to look later.
- **Weighted / Quantitative Transducers**: covered in
  `future-directions.md` §3. Orthogonal — weights are a payload on
  transitions, not a way to handle data alphabets.

---

## 2. Best Fit: a Hybrid SFT + SST

Each formalism solves a piece and only a piece:

- **SFT** lets predicates over payloads label transitions while keeping
  the control graph finite and analyzable. Directly addresses
  "commands and events carry data".
- **SST** gives a discipline for *evolving registers* across transitions
  with retained decidability — exactly the unsolved part of the current
  EFSM extension, where `rho :: s -> ctx -> c -> ctx` is opaque and so
  projections lose `apply` derivability.
- **Register automata / nominal** are the cleanest core for
  equality-only data (fresh IDs, "is this the same approver?"). Real
  workflows need more than equality, so this isn't enough on its own —
  but the **single-use** discipline is a useful sanity rail for any
  register that holds a fresh identifier.

Recommendation: a **Symbolic-Register Transducer** unifying the SFT
predicate-on-guard pattern with an SST-style register file. Predicates
speak about both the input symbol and the current register valuation;
updates are written in a small total combinator language so they can be
analyzed. This is the symbolic EFSM the workflow literature has been
gesturing at for two decades, with the missing piece — a decidable
update language — supplied by SST.

Why not pure SFT? The hardest payload case in workflows — "have we
collected enough approvals?" — is register state, not a guard over a
single input. Pure SFT can guard `payload.amount > 1000` but cannot
formalize "accumulate approvers, fire when count crosses N".

Why not pure SST? SST inputs are concrete symbols. We need predicates on
commands and events for "this command applies in any state where context
has property P" cases — SFT territory.

Why not Kaminski–Francez / nominal alone? Equality-only cripples
expressiveness for amounts, sums, timestamps.

The hybrid keeps the existing FST analytical apparatus (input/output
projection, composition, deadlock detection, exhaustive contract checks)
on the **control skeleton** and pushes data semantics into a per-edge
predicate-and-update layer the toolchain can reason about — discharge
guards via SMT, search the control graph symbolically, mechanically
derive `apply` for the data-determined cases.

---

## 3. Concrete Re-formulation

```haskell
-- Effective Boolean algebra. SMT is the canonical instance; a plain
-- Haskell-function instance is the no-dep fallback.
class BoolAlg phi a | phi -> a where
  top, bot :: phi
  conj, disj :: phi -> phi -> phi
  neg :: phi -> phi
  sat :: phi -> Maybe a              -- witness; EP-44 moved this to a `Sat` subclass
  isBot :: phi -> Bool
  models :: phi -> a -> Bool

-- Typed heterogeneous register tuple. Use a hand-rolled GADT or vinyl.
data RegFile (rs :: [Type])

-- Closed term language for register updates — analyzable, copyless.
data Update (rs :: [Type]) (a :: Type) where
  Keep    :: Update rs a
  Set     :: Index rs r -> Term rs a r -> Update rs a
  Combine :: Update rs a -> Update rs a -> Update rs a   -- distinct targets

-- Terms over registers + current input. SMT-backed instances embed
-- these as solver terms.
data Term (rs :: [Type]) (a :: Type) (r :: Type)

-- A guarded edge unifies guard, update, output, and target.
data Edge phi rs ci co s = Edge
  { guard  :: phi                 -- BoolAlg phi (RegFile rs, ci)
  , update :: Update rs ci        -- copyless
  , output :: Maybe (OutTerm rs ci co)   -- Nothing = ε
  , target :: s
  }

data SymTransducer phi rs s ci co = SymTransducer
  { edgesOut    :: s -> [Edge phi rs ci co s]
  , initial     :: s
  , initialRegs :: RegFile rs
  , isFinal     :: s -> Bool
  }
```

The plain `Transducer s c e` is the degenerate case: `rs = '[]`, every
`Update` is `Keep`, every guard is `\(_, c') -> c' == c` for one of the
finitely many `c`. The current `ExtTransducer s ctx c e` is the same
shape with `ctx` as a single opaque register and an arbitrary Haskell
update — i.e., a `SymTransducer` with no analyzable theory.

Crucially, `delta` and `omega` are no longer separate fields. They are
projections of a single edge structure, lifting the existing
"single source of truth" property to the symbolic setting:

```haskell
delta :: SymTransducer phi rs s ci co
      -> s -> RegFile rs -> ci -> Maybe (s, RegFile rs)
delta t s regs ci = case
  [ (target e, applyUpdate (update e) regs ci)
  | e <- edgesOut t s, models (guard e) (regs, ci)
  ] of
    [single] -> Just single
    []       -> Nothing
    _        -> error "non-deterministic edge — rejected by smart ctor"

omega :: SymTransducer phi rs s ci co
      -> s -> RegFile rs -> ci -> Maybe co
omega t s regs ci = case
  [ evalOut o regs ci
  | e <- edgesOut t s, models (guard e) (regs, ci), Just o <- [output e]
  ] of
    [o] -> Just o
    _   -> Nothing
```

`(Enum, Bounded)` survives **on the control state `s` only** — the
finite-control / infinite-data trade-off you wanted.

---

## 4. What Carries Over, What Breaks

| Operation | Status under Symbolic-Register |
|-----------|-------------------------------|
| `inputProjection :: ... -> SymAcceptor phi rs s ci` | **Carries over.** Drop output and update; keep guard and target. Emptiness decidable iff `phi` is. |
| `outputProjection :: ... -> SymAcceptor phi' rs s co` | **Partial.** Structural projection always works, but the new guard is existentially quantified over input: ψ'(regs, co) = ∃ci. ψ(regs, ci) ∧ output ≡ co. Decidable iff the theory admits quantifier elimination (Presburger, EUF, linear real arithmetic); **semi-decidable** for nonlinear arithmetic or arbitrary uninterpreted functions. |
| `toDecider :: ... -> SymDecider phi rs ci co (s, RegFile rs)` | **Carries over** with caveat — see §5. State is now `(s, RegFile rs)`. |
| `reconstitute :: ... -> [co] -> Maybe (s, RegFile rs)` | **Carries over.** Same fold; per-step `apply` is the symbolic version. Cost rises by the predicate evaluator per step. |
| `compose :: ... -> ... -> SymTransducer phi (rs1++rs2) (s1,s2) ci co` | **Carries over.** SFT composition closure is established (Veanes 2012); register files take the disjoint union (still copyless). **Single-valued only** for retained equivalence-decidability — nondeterministic composition is closed but escapes the decidable fragment. |
| `union`, `concatenate` (acceptors) | **Carry over verbatim.** Boolean operations on symbolic acceptors reduce to Boolean operations on `phi`; SFT closure under ∧/∨/¬ is the headline result. |
| `deadlocks` (control-only) | **Decidable**, polynomial in `|S|`. |
| `deadlocks` (data-aware: rule out spurious deadlocks) | **Decidable** for Presburger / linear-arithmetic fragments via symbolic pre-image + fixed-point iteration; **semi-decidable** in general — the standard EFSM-reachability situation. |
| `equivalent` | **Decidable** for single-valued SFTs (Veanes 2012, §5). **Undecidable** for nondeterministic / multi-valued machines, and also for ESFT-style multi-symbol reads (D'Antoni & Veanes 2015). |
| `language inclusion` | **Undecidable** for nondeterministic SFTs. Genuine loss vs. the plain finite case. |

The pattern: **structural** operations (composition, union, projection on
control) carry over for free. **Decision** operations push complexity into
the predicate algebra and are at the mercy of the theory.

---

## 5. Mechanical Derivation of `apply`

The current `toDecider` derivation relies on `(Enum, Bounded)` over
commands: given an event `e` from state `s`, search for the unique `c`
such that `omega(s, c) = Just e`, recover `delta(s, c)`. With infinite
data, enumeration is impossible — but under the symbolic-register
formulation the search becomes a *logical query* over `phi`, and in many
cases the answer is determined without any search at all.

### Symbolic `apply`

```haskell
applySym
  :: BoolAlg phi (RegFile rs, ci)
  => SymTransducer phi rs s ci co
  -> (s, RegFile rs) -> co -> Maybe (s, RegFile rs)
applySym t (s, regs) co = case
  -- For each outgoing edge: solve  guard(regs, ci) ∧ output(regs, ci) = co
  -- for ci, then apply the (deterministic) update.
  [ (target e, applyUpdate (update e) regs ci)
  | e <- edgesOut t s
  , Just ci <- [solveOutput e regs co]
  , models (guard e) (regs, ci)
  ] of
    [single] -> Just single
    []       -> Nothing   -- no edge produces this event
    _        -> Nothing   -- ambiguous; model not functional on events
```

Works automatically when (1) the output term is *invertible* — given
`(regs, co)`, recover `ci` — and (2) the update is functional given the
recovered `ci`, which it is by construction (closed combinator language).
This handles the bread-and-butter case: event payload composed from input
fields (`StartRegistration email → RegistrationStarted email`), register
update a simple set or accumulate.

### Where the user must intervene

**Hidden inputs.** A command field absent from the event (password,
one-time token, idempotency key not echoed back). `solveOutput` returns
`Nothing` for that field. Remediation: either include the field in the
event, mark it as "not needed for replay" (meaning the update must not
depend on it), or hand-write `apply` for that edge with the
event-determinism contract verified by property test. **Detected at
model-build time** by checking whether each edge's update depends on
input variables absent from the output term.

**Non-injective output.** Two distinct inputs producing the same event in
the same state with different register effects — the event stream is not
enough to recover state. A modelling error in event-sourcing terms.
**Detected by a sat-check** on `output(regs, ci₁) = output(regs, ci₂) ∧
update(regs, ci₁) ≠ update(regs, ci₂)`.

### Bottom line

`apply` derivation **survives the move to symbolic alphabets** for
well-designed schemas; for pathological schemas it fails *detectably and
at build time* with a clear remediation. This is strictly better than the
current EFSM extension, which silently hands the problem back to the user.

---

## 6. Implementation Reality

### Minimum viable shape (no SMT)

- **Pluggable `BoolAlg phi a` class** with a default Haskell-function
  instance (`phi = (RegFile rs, ci) -> Bool`). Users write predicates as
  ordinary Haskell; emptiness/satisfiability falls back to enumeration
  over user-supplied witnesses (Hedgehog generators).
- **A small total `Update` combinator language** restricted to copyless
  rewrites (`Set`, `Combine`, no `Copy`).
- **Pure-Haskell evaluator** for `delta` / `omega` / `apply` — no SMT.

This gets the cleaner control-vs-register separation, mechanical `apply`
derivation for well-formed cases, structural composition. Estimate:
~1–2 weeks once the core type is in place.

### SMT-backed phase (v2)

A `BoolAlg` instance backed by SBV / z3-haskell unlocks symbolic
emptiness / `deadlocks` over data, equivalence checking for single-valued
models, symbolic counterexample generation, and build-time detection of
the §5 schema failures. Cost: 4–6 weeks for a first version, plus
ongoing maintenance. **Defer to v2.** The minimum shape gives ~80% of the
value with no external dependency.

### Other notes

- **Nominal sets**: do not depend on a Haskell nominal-set library —
  ecosystem is research-grade. The single feature that matters
  (equality-with-freshness) can be a built-in `IsFresh r` predicate
  the SMT backend translates to a quantified inequality.
- **Register file**: hand-rolled GADT-indexed tuple for v1. `vinyl` is
  fine if the boilerplate gets bad; not worth the dependency up front.

---

## 7. What keiki Should Adopt

> **Status (historical record).** Both v1 and v2 below have shipped.
> v1 lives in `Keiki.Core` (`SymTransducer`, `RegFile`, `Update`,
> structural `InCtor`/`WireCtor`, mechanical `applyEvent` /
> `reconstitute` / `solveOutput`, `checkHiddenInputs`, the v1
> `HsPred` `BoolAlg`). v2 lives in `Keiki.Symbolic` (SBV-backed
> `SymPred`, `sat`/`isBot`/`isSingleValuedSym`/`symSatExt`).
> v3 (extended-FST features) was not pursued. Read this section as
> the prospective plan that produced the shipped library, not as a
> roadmap.

A focused slice, sequenced:

**v1 — adopt the symbolic-register *shape*, not the SMT plumbing.**

- Replace `Transducer s c e` with `SymTransducer phi rs s ci co` where
  the default `phi` is a Haskell-function predicate.
- Make `RegFile rs` and the `Update` combinator language first-class,
  with the copyless restriction enforced statically (smart constructors
  or type-level guarantees).
- Edges as a unified data type (`Edge`), with `delta`, `omega`, `rho`
  derived from it. This kills the current bug-class where `delta`,
  `omega`, `rho` can disagree.
- Mechanical `apply` derivation with the §5 build-time checks
  (output-injectivity, hidden inputs) implemented enumeratively over
  the control graph plus user-supplied generators for the data
  axis (Hedgehog generators are already in the plan).
- All existing operations ported to the new shape with the signatures
  from §4. Shipped names: `Keiki.Acceptor.inputAcceptor` /
  `outputAcceptor`, `Keiki.Composition.compose` / `alternative` /
  `feedback1`, `Keiki.Core.reconstitute`. The earlier prototype
  `union` / `concatenate` collapsed into `alternative` /`compose`.

**v2 — SMT-backed `BoolAlg` instance.**

- One `BoolAlg phi a` instance built on SBV, with a curated "supported
  fragment" of predicates. Outside the fragment, the user gets a
  pleasant compile-time error pointing at the non-symbolic Haskell
  predicate they wrote.
- Symbolic deadlock / reachability over data.
- Symbolic equivalence (single-valued only — document the restriction
  loudly).

**v3 — extended-FST or hierarchical features only if a real workflow
needs them.** The literature's clear: every step beyond single-valued
SFT on letter-by-letter input chips at decidability. Do not chase
expressiveness for its own sake.

What keiki should *not* adopt: nominal sets as a foundation, ESFT-style
multi-symbol reads, SST string-concatenation registers (the *register*
idea ports; the *string concatenation* part is not what workflow
registers need).

---

## 8. What Verifiable Claims Survive

| Claim | Plain FST | Symbolic-Register |
|-------|-----------|-------------------|
| Soundness / deadlock-freedom (control only) | Decidable, polynomial | Decidable, polynomial |
| Soundness / deadlock-freedom (data-aware, ruling out spurious deadlocks) | n/a | **Decidable for Presburger / linear-arithmetic fragments**; semi-decidable in general |
| Language equivalence | Decidable | **Decidable for single-valued models**; undecidable in general |
| Language inclusion | Decidable | **Undecidable** for nondeterministic SFTs (genuine loss) |
| Event-determinism contract (apply ≡ delta over the event stream) | Decidable, exhaustive over `(Enum, Bounded)` | Decidable structurally on the control graph; per-edge decidable if the theory admits QE; property-test-supplemented otherwise |
| Composition produces a valid model | Trivial | SFT composition closed; copyless register-union closed. Single-valuedness composes; nondeterminism does not. |
| `apply` derivation correct by construction | Yes | Yes for the well-formed fragment of §5; user-provided + property-test for the rest |
| Bisimilarity | Decidable | Decidable for finite control + decidable theory; same fragility as equivalence |

**Structural and control-flow guarantees are preserved with no loss.
Equivalence-style guarantees survive in the single-valued deterministic
fragment — the fragment aggregates and workflows naturally inhabit.
Inclusion checking and reasoning over nondeterministic data behaviours is
genuinely lost.** For event sourcing this is the right trade: the
interesting questions ("does my model handle every command", "does
replay reproduce state", "do these two refactorings accept the same
inputs and produce the same outputs?") all survive.

---

## 9. Summary

Adopt the **symbolic-register** shape (SFT predicates on guards + SST-style
copyless register file) as the v1 core. Defer the SMT backend to v2; ship
v1 with a Haskell-function `BoolAlg` so the model shape is in place
without an external dependency. Skip nominal sets, extended SFTs, and
hierarchical extensions for now.

The structural and event-sourcing guarantees motivating the FST choice
survive. Decidability of equivalence survives within the single-valued
fragment — the fragment you would write anyway. The genuine loss is
reasoning about nondeterministic data behaviours and language inclusion
in general; neither was exploited by the existing design.

The decisive win: `apply` derivation moves from "blocked by data" (current
EFSM extension) to "automatic for well-formed schemas, build-time-flagged
otherwise". That is the property the EFSM extension surrendered, and it
returns here.

---

### Citations

- Veanes, Hooimeijer, Livshits, Molnar, Bjorner. *Symbolic Finite State
  Transducers: Algorithms and Applications.* POPL 2012.
- D'Antoni, Veanes. *Extended Symbolic Finite Automata and Transducers.*
  FMSD 2015 (loss of closure for multi-symbol reads).
- D'Antoni, Veanes. *Automata Modulo Theories.* CACM 2021 (survey).
- Kaminski, Francez. *Finite-Memory Automata.* TCS 1994 (the original).
- Neven, Schwentick, Vianu. *Finite state machines for strings over
  infinite alphabets.* TOCL 2004 (undecidability landscape).
- Demri, Lazic. *LTL with the Freeze Quantifier and Register Automata.*
  TOCL 2009.
- Bojańczyk. *Single use register automata for data words.* arXiv
  1907.10504, 2019 (single-use restriction recovers good theory).
- Bojańczyk, Klin, Lasota. *Automata theory in nominal sets.* LMCS 2014.
- Alur, Černý. *Streaming transducers for algorithmic verification of
  single-pass list-processing programs.* POPL 2011.
- Muscholl, Puppis. *Equivalence of Finite-Valued Streaming String
  Transducers Is Decidable.* ICALP 2019.
- Bouajjani et al. *Comparison of Presburger Engines for EFSM
  Reachability.* (For the EFSM-reachability decidability landscape.)
- Alur, Dohmen. *Composing Copyless Streaming String Transducers.* arXiv
  2209.05448 (composition closure result for SST).
