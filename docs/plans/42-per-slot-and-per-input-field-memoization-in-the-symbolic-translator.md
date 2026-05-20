---
id: 42
slug: per-slot-and-per-input-field-memoization-in-the-symbolic-translator
title: "Per-slot and per-input-field memoization in the symbolic translator"
kind: exec-plan
created_at: 2026-05-20T18:50:57Z
intention: "intention_01ks3939thethvf26jkpx3ksht"
master_plan: "docs/masterplans/12-symbolic-arithmetic-terms-translator-memoization-and-real-boolalg-sat-witnesses.md"
---

# Per-slot and per-input-field memoization in the symbolic translator

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

keiki can ask an SMT solver (z3, via the `sbv` library) precise questions about an
aggregate's edge guards: "are these two guards mutually exclusive?"
(`isSingleValuedSym`), "is this guard ever satisfiable, and if so give me a concrete
input that satisfies it" (`symSatExt`), "is this guard a contradiction?" (`symIsBot`).
The translator that turns a guard into solver constraints lives in
`src/Keiki/Symbolic.hs`.

Today that translator has a precision bug: **it allocates a brand-new solver variable
on every occurrence of a register read or an input-field read, even when two reads
name the same register or field.** A "register" is a named, typed mutable slot in the
aggregate's register file; reading one is the `TReg` term constructor. An "input field"
is a field of the input command; reading one is the `TInpCtorField` term constructor.

Because each read becomes a *fresh, independent* variable, the solver does not know
that two reads of `#x` must produce the *same* value. Concretely, the guard
`proj #x == proj #x` (read register `x` twice and compare) translates to
`v1 == v2` over two independent variables `v1`, `v2` — which the solver reports as
*satisfiable but not valid*. So:

- `proj #x /= proj #x` is reported satisfiable (it should be empty);
- a self-mutex `g ∧ ¬g` over a guard that re-reads a register is reported satisfiable
  (it should be unsatisfiable);
- two outgoing edges guarded by `PEq #x (lit 0)` and `PEq #x (lit 1)` are reported as
  *possibly co-firing* (`isSingleValuedSym == False`), because the conjunction of the
  two guards reads `#x` twice and the two reads can disagree;
- `symSatExt` can return a *witness that does not actually satisfy the predicate*,
  because the witness reconstructs each register/field once by name while the predicate
  internally constrained two different variables.

After this change, the translator allocates **one** solver variable per distinct
register slot and per distinct `(input-constructor, field)` pair *within a single
predicate translation*, and reuses it for every read. So two reads of `#x` share one
variable and the solver knows they are equal.

You will be able to observe the fix directly. Before this plan,
`symIsBot (PNot (PEq (proj #x) (proj #x)))` is `False` (the solver thinks `x ≠ x` is
possible); after, it is `True`. Before, an `isSingleValuedSym` fixture whose two edges
are `PEq #x (lit 0)` and `PEq #x (lit 1)` is `False`; after, it is `True`. And a
`symSatExt` witness for a repeated-read predicate now satisfies the predicate under
`models`.

This plan is one of three sibling ExecPlans under MasterPlan 12
(`docs/masterplans/12-symbolic-arithmetic-terms-translator-memoization-and-real-boolalg-sat-witnesses.md`).
It is the foundational one: the other two (structural arithmetic terms,
`docs/plans/43-structural-arithmetic-terms-in-the-keiki-term-language.md`; and real
`BoolAlg.sat` witnesses,
`docs/plans/44-real-witnesses-from-boolalg-sat-retire-the-placeholder-witness.md`) both
become *more* trustworthy once reads are memoized. This plan has no hard dependency on
either of them and can be implemented first.


## Progress

- [x] M0 — Baseline (2026-05-20): `z3 --version` → 4.15.8; `cabal build all` and
      `cabal test all` green. Counts: keiki-test 216/0, jitsurei-test 94/0/**1 pending**
      (the LoanApplication single-valuedness gate), keiki-codec-json-test 40/0,
      keiki-codec-json-test-test 7/0. *Before* values of falsifiers 1–3 captured via
      `cabal repl keiki` (recorded in Surprises & Discoveries); falsifier 4 (repeated-read
      `symSatExt`) needs a `KnownInCtors` fixture so its before/after is captured at M2.
- [x] M1 — Memoizing `SymEnv` + translator (2026-05-20): `SymEnv` is now a record with
      `seVarCache :: IORef (Map String SomeSBV)`; added `SomeSBV` existential and
      `memoFree`; rewrote the `TReg`/`TInpCtorField` arms to call `memoFree`; `mkSymEnv`
      allocates the cache via `liftIO (newIORef Map.empty)`. Added `containers` to
      `keiki.cabal`'s library `build-depends`. Library builds warning-clean; `cabal test
      all` green with M0 counts unchanged (keiki-test 216/0, jitsurei-test 94/0/1-pending,
      json 40/0 + 7/0). Repl re-check: falsifiers flipped F1 `False→True`, F2a
      `True→False`, F3 `False→True`; F2b stays `False`.
- [x] M2 — keiki-side proofs (2026-05-20): added a `describe "memoization (EP-42)"` block
      to `Keiki.SymbolicSpec` (6 assertions) plus a `twoReadEdgeFixture`. `cabal test
      keiki-test` → 222 examples (was 216), 0 failures. The four falsifiers are locked in:
      `symIsBot (PNot (PEq #amount #amount))` True, `symSat …` Nothing, the two-edge
      `PEq #amount 0`/`PEq #amount 1` fixture single-valued, and the repeated-read witness
      path (contradiction → `Nothing`; satisfiable round-trip → `models` True). See the
      Decision Log on strengthening the repeated-read falsifier.
- [x] M3 — Dogfood + pending-reason sharpening (2026-05-20): jitsurei-test green
      (94/0/1-pending). Sharpened both the `pendingWith` message and the module haddock on
      `jitsurei/test/Jitsurei/LoanApplicationSymbolicSpec.hs` to record that memoization
      (EP-42) is done and the *only* remaining blocker for the single-valuedness gate is
      the arithmetic-terms sibling (EP-43)'s cap `TApp1`; the un-pend is MasterPlan 12's
      capstone owned by EP-43. No memoization-only single-valuedness assertion was added to
      a shipped aggregate: `OrderCart`'s edges are constructor-disambiguated (`PInCtor`, no
      register re-read) and `LoanApplication`'s gate also needs arithmetic — neither offers
      a memoization-*only* win, so M2's keiki-side proofs stand as the lock-in (see the
      Surprises entry).
- [x] M4 — Docs + close (2026-05-20): updated `docs/research/sbv-boolalg-design.md`
      (Translation environment + Term translation rules → "implemented in EP-42", with the
      single name-keyed-`IORef` simplification documented); softened the repeated-read
      caveats in `docs/guide/why-smt.md`, `docs/research/symbolic-analysis-and-runtime-implications.md`,
      `docs/research/keiki-generics-design.md` (item 3), and the LoanApplication caveats in
      `docs/guide/loan-application-tutorial.md` (both mentions now name EP-43 as the
      remaining blocker); softened the `symSatExt` haddock and module-header in
      `src/Keiki/Symbolic.hs`. `docs/guide/symbolic-ci.md` had no repeated-read caveat (its
      only caveat is the `TApp` residual, still accurate). Build warning-clean (the two
      pre-existing `Jitsurei/Loan.hs` + `CoreBankingSync.hs` unused-bind warnings are
      unrelated); full suite green (keiki-test 222/0, jitsurei-test 94/0/1-pending, json
      40/0 + 7/0).


## Surprises & Discoveries

- 2026-05-20 (M0 baseline, *before* the fix). Captured in `cabal repl keiki` over a
  one-slot fixture `'[ '("x", Word64) ]` (full transcript reproducible from the Concrete
  Steps repl recipe):

      F1  symIsBot (PNot (PEq (TReg xIdx) (TReg xIdx)))   = False   -- BUG: x /= x looks possible; want True
      F2a isJust (symSat (PNot (PEq (TReg xIdx) (TReg xIdx)))) = True   -- BUG: x /= x reported sat; want False (Nothing)
      F2b symIsBot (PEq (TReg xIdx) (TReg xIdx))          = False   -- correct: x == x is satisfiable
      F3  isSingleValuedSym (two edges PEq #x 0 / PEq #x 1) = False   -- BUG: reads of #x disagree; want True

  These confirm the per-occurrence `SBV.free` allocation bug exactly as the plan predicts:
  two reads of the same register `#x` translate to independent solver variables, so the
  solver believes `x` can differ from itself. F2b is the sanity baseline (it is and stays
  `False`). M2 will lock F1/F3 (and the repeated-read `symSatExt` falsifier F4) into the
  suite and show them flip after M1.

- 2026-05-20 (M1). `Data.SBV`'s `SymVal` class confirmed to carry a `Typeable`
  superclass (`:info SBV.SymVal` shows `class (SBV.HasKind a, ... Typeable a, …) =>
  SymVal a`), so the `SomeSBV` existential needs no extra constraint: matching
  `SomeSBV (v :: SBV.SBV b)` brings `Typeable b` into scope for the `eqTypeRep` check in
  `memoFree`. The plan's fallback (adding `Typeable (SymRep a)` to the `Sym` context) was
  not needed. After M1 the repl falsifiers flip exactly as predicted (F1 `True`, F2a
  `False`, F2b `False`, F3 `True`), and the full suite is unchanged at M0 counts — the
  `SymEnv` newtype→record widening is internal and caused no regression.

- 2026-05-20 (M1). `keiki.cabal`'s library `build-depends` did **not** list `containers`
  even though `Data.Map.Strict` is now required; added `containers >= 0.6 && < 0.9`. (The
  package was previously only available transitively via `sbv`.)

- 2026-05-20 (M3, honesty correction). The `LoanApplicationSymbolicSpec` pending message
  that shipped after EP-41 named *only* the per-slot memoization sibling as the remaining
  blocker for the single-valuedness gate. That was incomplete: memoization alone does
  **not** un-pend it. `approvalGuard`'s cap conjunct
  `appRequestedAmount <= maxApprovalForScore appCreditScore` routes its right-hand side
  through an opaque `TApp1`, and the memoizing translator deliberately does *not* cache
  `TApp` results (opaque functions have no `Eq` — see the Decision Log). So the two copies
  of that `TApp1` in `approvalGuard ∧ PNot approvalGuard` still mint independent fresh
  variables and the self-mutex stays satisfiable via the cap — even though memoization now
  correctly shares `#appCreditScore`. The remaining blocker is therefore the
  arithmetic-terms sibling (EP-43), which makes the cap structural so it stops minting
  per-occurrence variables. This matches the MasterPlan's Integration Point 2 (the un-pend
  is the joint EP-42 + EP-43 capstone). M3 corrects both the `pendingWith` message and the
  module haddock to name EP-43.


## Decision Log

- Decision: The memo cache is scoped to **one predicate translation** (the lifetime of a
  single `translatePred env p` call / single `SBV.sat` query), not global.
  Rationale: each `symSat`/`symIsBot`/`symSatExt` call creates a fresh `SymEnv` via
  `mkSymEnv` and runs one solver query; variables must be shared *within* that query but
  must not leak across queries (different queries are independent problems). This matches
  how `seInputCtor` is already scoped (one fresh tag per `mkSymEnv`).
  Date: 2026-05-20

- Decision: Memoize **only** register reads (`TReg`) and input-field reads
  (`TInpCtorField`), not opaque applications (`TApp1`/`TApp2`).
  Rationale: `TApp1`/`TApp2` carry an opaque Haskell function with no `Eq`, so two
  applications cannot be recognized as equal and must each translate to a fresh variable.
  This is a real precision limit and is exactly why un-pending
  `Jitsurei.LoanApplicationSymbolicSpec`'s single-valuedness gate *also* needs the
  arithmetic-terms sibling (EP-43), which replaces the relevant `TApp` with structural
  arithmetic so it stops minting fresh per-occurrence variables. See the MasterPlan's
  Integration Points.
  Date: 2026-05-20

- Decision: Strengthen M2's repeated-read `symSatExt` falsifier (the plan's item 4). The
  plan suggested `PAnd (PInCtor inCtorX) (PEq (proj #x) (proj #x))` and asserting the
  witness satisfies `models`. On inspection that is *not* a before/after flip: concrete
  `evalPred` reads the same register twice, so `proj #x == proj #x` is trivially `True`
  for any witness regardless of memoization — the pre-EP-42 by-name witness already
  satisfied `models` for that predicate. The witness can only *fail* `models` when the
  solver exploited the two reads' independence to satisfy a constraint no single value can
  (e.g. `#x == 0 ∧ #x == 1`); but that exact predicate is precisely the one that becomes
  *unsatisfiable* after memoization, so the genuine flip is `Just`(bogus witness)
  → `Nothing`. M2 therefore asserts both: (a) the repeated-read contradiction
  `PInCtor ∧ #amount==0 ∧ #amount==1` now has *no* witness (`symSatExt … == Nothing`,
  whose pre-EP-42 satisfiability is the same conjunction empirically captured as
  falsifier F3 — the single-valuedness gate's conjunct), and (b) a positive round-trip
  (`PInCtor ∧ #amount==#amount` yields a witness satisfying `models`) as a regression
  guard on the witness path.
  Rationale: keep the test suite's claims accurate — every "before/after-falsifiable"
  assertion must really flip. The contradiction form is the honest repeated-read flip; the
  round-trip is a genuine (non-flipping) regression guard, labelled as such.
  Date: 2026-05-20


## Outcomes & Retrospective

Delivered (2026-05-20). The symbolic translator now memoizes register (`TReg`) and
input-field (`TInpCtorField`) reads: within one predicate translation, two reads of the
same slot or `(InCtor, field)` pair share a single SBV variable. Implemented as a single
`IORef (Map String SomeSBV)` cache keyed by the deterministic variable name in `SymEnv`
(simpler than the design note's two-structure sketch; equivalent because `"reg/…"` and
`"inp/…/…"` names are prefix-disjoint). `TApp1`/`TApp2` stay per-occurrence fresh by
design (opaque functions have no `Eq`).

Falsifiers that flipped (all locked into `Keiki.SymbolicSpec`'s "memoization (EP-42)"
block, before-values in Surprises & Discoveries):

- `symIsBot (PNot (PEq (proj #x) (proj #x)))`: `False → True` (x ≠ x is now empty).
- `symSat (PNot (PEq (proj #x) (proj #x)))`: `Just → Nothing`.
- An `isSingleValuedSym` fixture with edges `PEq #x 0` / `PEq #x 1`: `False → True`.
- A repeated-read contradiction `PInCtor ∧ #x==0 ∧ #x==1` via `symSatExt`:
  `Just`(bogus witness) `→ Nothing`. (The plan's literal "`proj #x == proj #x` witness
  satisfies models" is *not* a flip — concrete `evalPred` makes it trivially true — so it
  is kept only as a positive regression guard; see the Decision Log.)

`Jitsurei.LoanApplicationSymbolicSpec`'s single-valuedness gate did **not** become
un-pendable here: it remains blocked on EP-43. Memoization is necessary but not sufficient
because `approvalGuard`'s cap conjunct `appRequestedAmount <= maxApprovalForScore
appCreditScore` routes `maxApprovalForScore` through an opaque `TApp1`, which is not
memoized, so the two copies in `approvalGuard ∧ ¬approvalGuard` still mint independent
variables. M3 sharpened that gate's pending message (and module haddock) to name EP-43 as
the sole remaining blocker — correcting the post-EP-41 message that had blamed memoization
alone. The un-pend is MasterPlan 12's integration capstone, owned by EP-43.

Surprises worth carrying forward: (1) `SBV.SymVal` carries a `Typeable` superclass, so
`SomeSBV` needs no extra constraint; (2) `containers` was missing from `keiki.cabal`'s
library `build-depends` despite being used transitively; (3) the post-EP-41 pending
message under-counted the gate's blockers (memoization-only, when arithmetic is also
required) — now corrected.

Lessons: the `SymEnv` newtype→record widening was fully internal and caused zero
regressions, validating the additive-with-internal-shape-change approach. Sibling plans
EP-43 (arithmetic) and EP-44 (real `sat` witnesses) inherit this memoization
automatically: EP-43's `TArith` arm reads operands via the recursive `translateTermSym
env` call, and EP-44's `sat = symSatExt` consumes the now-correct repeated-read witnesses.


## Context and Orientation

This section assumes no prior knowledge of keiki. Read it before editing.

keiki is a Haskell library (the package at the repository root, `keiki.cabal`, module
prefix `Keiki.*`) for the pure core of event sourcing. An aggregate is modeled as a
`SymTransducer` — a finite control graph (vertices) plus a typed *register file* (named,
typed mutable slots) where each edge has a *guard* (a predicate that must hold for the
edge to fire), an *update* (how it writes registers), an *output* (events it emits), and
a *target* vertex. Example aggregates live in the sibling package `jitsurei`
(`jitsurei/src/Jitsurei/*.hs`). `cabal.project` lists the packages: `.` (keiki),
`jitsurei`, `keiki-codec-json`, `keiki-codec-json-test`.

The symbolic analyses require the **z3** SMT solver on `PATH` at runtime
(`keiki.cabal` documents `brew install z3` on macOS, `apt install z3` on Debian). The
pure evaluator and everything non-symbolic do not need z3.

### The predicate and term languages

`HsPred rs ci` is the guard predicate AST (`src/Keiki/Core.hs`, around line 401). `rs` is
the register-file slot list (`Slot = (Symbol, Type)` — a name paired with its value
type); `ci` is the input/command type. Its constructors are `PTop`, `PBot`, `PAnd`,
`POr`, `PNot`, `PEq` (equality of two terms), `PInCtor` (input-constructor match), and
`PCmp` (ordering comparison of two terms, added by EP-41). You do not need to change
`HsPred` in this plan.

`Term rs ci r` is a pure expression producing an `r` (`src/Keiki/Core.hs`, around line
196). Its constructors:

- `TLit r` — a literal value.
- `TReg :: Index rs r -> Term rs ci r` — read a register. `Index rs r` is a type-safe
  pointer to a slot of type `r` in the slot list `rs`. The helper `proj = TReg`
  (`src/Keiki/Core.hs:534`) plus `OverloadedLabels` lets authors write `proj #x` (or
  `#x` directly via `fromLabel`, `src/Keiki/Core.hs:186`).
- `TInpCtorField :: InCtor ci ifs -> Index ifs r -> Term rs ci r` — read field `ix` of
  the input constructor named by `ic`.
- `TApp1 (a -> r) (Term rs ci a)` and `TApp2 (a -> b -> r) (Term rs ci a) (Term rs ci b)`
  — apply an opaque Haskell function to sub-terms. These are the escape hatch: arbitrary
  Haskell, opaque to symbolic analysis.

### The symbolic surface (`src/Keiki/Symbolic.hs`)

This is the only source file this plan changes. Key parts as they exist today:

- `class Sym a` with associated type `SymRep a` and methods `toSym :: a -> SymRep a`,
  `fromSym :: SymRep a -> a`, `symDefault :: a`. `SymRep a` is the SBV-friendly
  representation; the class constraint is `(SBV.SymVal (SymRep a), Typeable a)`. Instances
  exist for `Bool`, `Integer`, `Int`, `Text`, `UTCTime`, and (since EP-41) the fixed-width
  integers `Word8`/`Word16`/`Word32`/`Word64`/`Int32`/`Int64`. The SBV class `SymVal`
  provides `SBV.literal`, `SBV.free`, and `SBV.unliteral`.

- `discoverSym :: forall r. Typeable r => Maybe (SymDict r)` — runtime lookup from a
  `Typeable` value type to its `Sym` instance. A miss returns `Nothing`. (Unchanged here.)

- `SymEnv` (around line 296) — **this is what you replace.** Today it is:

        newtype SymEnv = SymEnv
          { seInputCtor :: SBV.SBV String }

  carrying only the shared symbolic input-constructor tag. Its haddock explicitly says
  "Per-slot register variables and per-(InCtor, field) input variables are allocated
  fresh on each occurrence; this loses the precision of recognizing two reads of the same
  slot as the same value." That is the bug this plan fixes.

- `mkSymEnv :: SBV.Symbolic SymEnv` (around line 307) — allocates a fresh `SymEnv`. It
  currently does `ctor <- SBV.free "inputCtor"; pure (SymEnv ctor)`. The `SBV.Symbolic`
  monad is `SymbolicT IO`, so it is a `MonadIO` — you can create `IORef`s here with
  `liftIO (newIORef ...)`.

- `translateTermSym :: forall rs ci r. Sym r => SymEnv -> Term rs ci r -> SBV.Symbolic (SBV.SBV (SymRep r))`
  (around line 345) — **the second thing you change.** Today:

        translateTermSym _env  (TLit r)              = pure (symLit r)
        translateTermSym _env  (TReg ix)             = SBV.free ("reg/" <> indexName ix)
        translateTermSym _env  (TInpCtorField ic ix) = SBV.free ("inp/" <> icName ic <> "/" <> indexName ix)
        translateTermSym _env  (TApp1 _f _t)         = SBV.free "app1"
        translateTermSym _env  (TApp2 _f _a _b)      = SBV.free "app2"

  The `TReg` and `TInpCtorField` arms call `SBV.free` *every time*, minting a new
  variable per occurrence. The variable *name* is deterministic (`reg/<slot>`,
  `inp/<ctor>/<field>`), but **SBV does not alias two `SBV.free` calls that share a
  name** — it uniquifies the second by appending `_1`, `_2`, … So same-name does not mean
  same variable. (This was verified empirically during EP-41; see that plan's Surprises &
  Discoveries: `cabal repl keiki` with two `SBV.free "reg/amount"` calls and a constraint
  `x == 0 ∧ y == 1` reports SAT, proving the two are independent.)

- `indexName :: Index rs r -> String` (around line 363) — recovers the slot name a `TReg`
  points at, by walking to the leaf `ZIdx` and reading its `KnownSymbol` evidence. The
  translator already uses this to name register variables. (Unchanged.)

- `translatePred :: SymEnv -> HsPred rs ci -> SBV.Symbolic SBV.SBool` (around line 384) —
  walks `HsPred`, calling `translateTermSym env` on operand terms. `PEq` (`goEq`) and
  `PCmp` (`goCmp`) both translate two terms via `translateTermSym env` and combine them.
  You do not change `translatePred`'s structure; it benefits automatically once
  `translateTermSym` memoizes through the shared `env`.

- `symSat`, `symIsBot`, `symSatExt` (around lines 475, 491, 653) — pure wrappers
  (`unsafePerformIO` + `NOINLINE`) that build one `SBV.sat` query. Each does
  `env <- mkSymEnv; translatePred env p`. Because they create `env` once and pass it to
  the whole walk, the memo cache you add to `env` is automatically shared across the whole
  predicate. **No change needed in these functions** beyond confirming they still
  typecheck against the new `SymEnv`.

- `symSatExt` extracts a witness by reading `reg/<name>` and `inp/<ctor>/<field>` from the
  SBV model **by name** (`readModel`, `pickCi`, around lines 659–711). Today, with
  per-occurrence allocation, a repeated read produces `reg/x` and `reg/x_1` in the model,
  and the extractor reads only `reg/x` — so the witness can disagree with the predicate's
  second read. After memoization, there is exactly one `reg/x`, so reading by name returns
  the value the predicate actually constrained: **memoization fixes `symSatExt` for
  repeated reads for free.** No change to `symSatExt` is required; its haddock caveat
  about repeated reads (around lines 626–643) should be softened in M4.

### The design note already specifies this

`docs/research/sbv-boolalg-design.md` is the design record for the SBV layer. Its
"Translation environment" section (around lines 256–289) already describes the intended
memoizing `SymEnv` with a per-slot register file and a
`seInpFieldCache :: IORef (Map (String, String) SomeSBV)`. EP-2 of MasterPlan 2 shipped
the simplified non-memoizing version for the User Registration smoke test and left the
cache as future work. This plan implements what that note describes. In M4 you update the
note to mark it implemented (changing "future improvement" wording to "implemented in
EP-42").

### Where the tests live

- keiki unit tests: suite `keiki-test` (`keiki.cabal`, `main-is: Spec.hs`), with the
  symbolic unit tests in module `Keiki.SymbolicSpec` (listed in `keiki.cabal`'s
  `other-modules`). This is where M2's proofs go. It already imports `Keiki.Symbolic`
  and builds small fixture transducers; read it to match its style.
- jitsurei tests: suite `jitsurei-test` (`jitsurei/jitsurei.cabal`, `main-is: Spec.hs`),
  containing `Jitsurei.LoanApplicationSymbolicSpec`, `Jitsurei.OrderCartSymbolicSpec`,
  and `Jitsurei.UserRegistrationSymbolicSpec`. M3 touches the first.


## Plan of Work

The work proceeds in five milestones (M0–M4). All edits are additive except the `SymEnv`
newtype's shape (M1), which is internal to `Keiki.Symbolic` and exercised by the existing
specs, so a regression shows up immediately.

### M0 — Baseline

Goal: a known-good starting point and a recorded *before* picture of the four falsifiers.

Confirm z3 is present, build everything, run the full suite, and record example/pending
counts in Progress. Then capture the current (buggy) behavior of the falsifiers so M2 can
show them flipping. The cleanest way is a short `cabal repl`:

    z3 --version
    cabal build all
    cabal test all
    cabal repl keiki-test    # or `cabal repl keiki` and import the spec helpers

In the repl, evaluate (record outputs in Surprises & Discoveries):

    -- needs a fixture with a Word64/Int register named "x"; reuse or mirror an existing
    -- Keiki.SymbolicSpec fixture. Illustrative shape:
    symIsBot (PNot (PEq (proj #x) (proj #x)))      -- expect: False (buggy: x /= x looks possible)

What exists at the end: recorded counts and *before* outputs. No code change.

Acceptance: build and tests pass; the four falsifiers' *before* values are recorded.

### M1 — Memoizing `SymEnv` + translator

Goal: register and input-field reads share one solver variable per name within a
predicate translation.

In `src/Keiki/Symbolic.hs`:

1. Add imports: `import Data.IORef (IORef, newIORef, readIORef, modifyIORef')`,
   `import qualified Data.Map.Strict as Map`, `import Data.Map.Strict (Map)`,
   `import Control.Monad.IO.Class (liftIO)`. (`Type.Reflection`'s `eqTypeRep`/`typeRep`/
   `HRefl` are already imported.)

2. Add a small existential wrapper so the cache can hold SBV variables of different
   representation types under one map:

        -- | An SBV variable of some representation type, with the 'Typeable'
        -- evidence ('SBV.SymVal' provides 'Typeable') needed to recover its type
        -- on a cache hit.
        data SomeSBV where
          SomeSBV :: SBV.SymVal a => SBV.SBV a -> SomeSBV

   Note: `Data.SBV`'s `SymVal` class has a `Typeable` superclass, so pattern-matching
   `SomeSBV (v :: SBV.SBV a)` brings `Typeable a` into scope for the `eqTypeRep` check
   below. Confirm this at compile time. If for some reason it does not, the fallback is to
   add `Typeable (SymRep a)` to the `Sym` class context in `src/Keiki/Symbolic.hs`
   (every `SymRep` is already a concrete `Typeable` type, so all instances still compile)
   and carry that constraint on `SomeSBV`.

3. Replace the `SymEnv` newtype with a record carrying the input-constructor tag plus a
   single memo cache keyed by the full variable name string (`"reg/x"`,
   `"inp/Ctor/field"`). One map suffices because the names are disjoint by prefix:

        data SymEnv = SymEnv
          { seInputCtor :: SBV.SBV String
            -- ^ The shared symbolic input constructor tag (unchanged from before).
          , seVarCache  :: IORef (Map String SomeSBV)
            -- ^ Memo cache: maps a deterministic variable name ("reg/<slot>" or
            -- "inp/<ctor>/<field>") to the single SBV variable allocated for it
            -- during this predicate translation. Lazily populated on first read so
            -- unread slots stay unconstrained (and 'symSatExt' falls back to
            -- 'symDefault' for them).
          }

4. Update `mkSymEnv` to create the cache:

        mkSymEnv :: SBV.Symbolic SymEnv
        mkSymEnv = do
          ctor  <- SBV.free "inputCtor"
          cache <- liftIO (newIORef Map.empty)
          pure (SymEnv ctor cache)

5. Add a memoized allocator and rewrite the two relevant `translateTermSym` arms to use
   it. `TLit`/`TApp1`/`TApp2` are unchanged (`TLit` is a literal, the `TApp`s stay
   per-occurrence fresh — see Decision Log):

        -- | Look up @name@ in the env's cache; on a hit, recover the SBV variable
        -- (checking the representation type matches, which it always will because a
        -- name maps to exactly one type); on a miss, allocate a fresh 'SBV.free',
        -- store it, and return it.
        memoFree
          :: forall a. SBV.SymVal a
          => SymEnv -> String -> SBV.Symbolic (SBV.SBV a)
        memoFree env name = do
          m <- liftIO (readIORef (seVarCache env))
          case Map.lookup name m of
            Just (SomeSBV (v :: SBV.SBV b)) ->
              case eqTypeRep (typeRep @a) (typeRep @b) of
                Just HRefl -> pure v
                Nothing    ->
                  -- Unreachable: a name maps to exactly one representation type.
                  error ("memoFree: type mismatch for cached variable " <> name)
            Nothing -> do
              v <- SBV.free name
              liftIO (modifyIORef' (seVarCache env) (Map.insert name (SomeSBV v)))
              pure v

        translateTermSym _env  (TLit r)              = pure (symLit r)
        translateTermSym env   (TReg ix)             = memoFree env ("reg/" <> indexName ix)
        translateTermSym env   (TInpCtorField ic ix) = memoFree env ("inp/" <> icName ic <> "/" <> indexName ix)
        translateTermSym _env  (TApp1 _f _t)         = SBV.free "app1"
        translateTermSym _env  (TApp2 _f _a _b)      = SBV.free "app2"

   `memoFree`'s result type `SBV.SBV a` unifies with `translateTermSym`'s required
   `SBV.SBV (SymRep r)` because `Sym r` gives `SymVal (SymRep r)`.

6. Update the `SymEnv` haddock (around line 296) to describe the cache and that
   per-occurrence freshness is gone for `TReg`/`TInpCtorField`. Update
   `translateTermSym`'s haddock "Note on repeated reads" (around lines 336–344) to say
   repeated reads now share a variable; keep the note that `TApp1`/`TApp2` results remain
   per-occurrence fresh.

Build and run the whole suite. The existing specs (which never relied on the buggy
behavior) must stay green — in particular `Jitsurei.UserRegistrationSymbolicSpec`'s
`symSatExt` round-trips, which had "no repeated reads" and so are unaffected, must still
pass.

What exists at the end: the translator memoizes register and input-field reads.

Acceptance: `cabal build all` and `cabal test all` pass with the same example/pending
counts as M0 (plus nothing new yet).

### M2 — keiki-side proofs

Goal: lock the fix in with before/after-falsifiable assertions.

Add a `describe "memoization (EP-42)"` block to `Keiki.SymbolicSpec`. Reuse or add a tiny
fixture transducer carrying an integer register `x` (mirror the `Word64`/`Int` fixtures
already in that module — read it first to match naming and helpers). Assert:

1. `symIsBot (PNot (PEq (proj #x) (proj #x))) == True` — "x ≠ x" is empty. (Before M1:
   `False`.)
2. `symSat (PNot (PEq (proj #x) (proj #x)))` is `Nothing` (same fact via `symSat`), and
   `symIsBot (PEq (proj #x) (proj #x)) == False` (x == x is satisfiable, sanity check).
3. An `isSingleValuedSym` fixture: a transducer with one source vertex and two outgoing
   edges guarded by `PEq (proj #x) (lit 0)` and `PEq (proj #x) (lit 1)`. Assert
   `isSingleValuedSym (withSymPred t) == True`. (Before M1: `False`. This is the exact
   form EP-41 documented as unattainable without memoization — see
   `docs/plans/41-...md` Decision Log entry "M1 acceptance revised".)
4. A `symSatExt` round-trip over a repeated-read predicate whose witness must satisfy it:
   e.g. `PAnd (PInCtor inCtorX) (PEq (proj #x) (proj #x))` — assert the returned witness
   `(regs, cmd)` satisfies `models (SymPred p) (regs, cmd) == True`. (The `PInCtor`
   conjunct pins the input constructor so witness reconstruction succeeds, mirroring how
   EP-41's `symSatExt` tests are structured.) Before M1 the second read used a separate
   variable, so the by-name witness could fail `models`; after, it holds.

Build and run `cabal test keiki-test`.

What exists at the end: four assertions that fail before M1 and pass after.

Acceptance: `cabal test all` passes including the new block.

### M3 — Dogfood + pending-reason sharpening

Goal: confirm shipped aggregates still behave, and record honestly what memoization does
and does not un-block.

First, run the jitsurei symbolic specs and confirm they pass unchanged:

    cabal test jitsurei-test --test-options=--match=/Symbolic/

Second, sharpen the pending reason on
`jitsurei/test/Jitsurei/LoanApplicationSymbolicSpec.hs`. Its single-valuedness gate
(`isSingleValuedSym (withSymPred loanApplication) == True`) is `pendingWith` a message
that today blames the missing comparison constructor (supplied by EP-41) and the
memoization sibling. After this plan, memoization is done, so the message must name the
**remaining** blocker accurately: the gate also requires the arithmetic-terms sibling
(EP-43), because `approvalGuard`'s cap conjunct
`appRequestedAmount <= maxApprovalForScore appCreditScore` routes its right-hand side
through an opaque `TApp1`. Even with register memoization sharing `#appCreditScore`, the
two copies of that `TApp1` (one in `approvalGuard`, one inside `PNot approvalGuard`) mint
*independent* `app1` variables, so the self-mutex stays satisfiable until the `TApp1`
becomes structural arithmetic (which EP-43 does). Update the message to say: "Needs the
arithmetic-terms sibling (EP-43): memoization (EP-42) now shares register reads, but the
cap conjunct's `maxApprovalForScore` is still an opaque `TApp1` that mints a fresh
variable per occurrence; the un-pend is MasterPlan 12's integration capstone, owned by
EP-43." Keep the gate `pendingWith` (do not un-pend here).

This is an important honesty correction: the message that shipped after EP-41 named only
memoization as the remaining blocker, but arithmetic is *also* required. Record this in
Surprises & Discoveries with the reasoning above (the cap's `TApp1` is the second
independent variable).

Optionally, if a shipped aggregate has a guard that re-reads a register *without* an
intervening `TApp` (so memoization alone tightens it), add a memoization-only assertion
there. If none exists without arithmetic, say so in Progress and rely on the keiki-side
M2 proofs.

What exists at the end: jitsurei symbolic specs green; LoanApplication's pending reason
corrected to name EP-43 as the remaining blocker.

Acceptance: `cabal test all` passes; the LoanApplication pending message names the
arithmetic sibling.

### M4 — Documentation and close

Goal: leave the design record consistent.

Update `docs/research/sbv-boolalg-design.md`: the "Translation environment" and "Term
translation rules" sections (around lines 256–304) describe the memoizing cache as the
design but the shipped code did not have it; change the wording from aspirational/future
to "implemented in EP-42" and note the one-map-keyed-by-name simplification chosen here
(the design sketched separate `seRegFile` + `seInpFieldCache`; this plan uses a single
name-keyed `IORef (Map String SomeSBV)`, which is simpler and equivalent because the
names are prefix-disjoint). Sweep the guide docs (`docs/guide/why-smt.md`,
`docs/guide/symbolic-ci.md`) for any "repeated reads lose precision" caveat and update it
to "repeated reads of the same register/field now share a solver variable; opaque
`TApp1`/`TApp2` results remain per-occurrence" — keep the honest residual about `TApp`.

Fill Outcomes & Retrospective.

Acceptance: docs read consistently; no stale "repeated reads lose precision" claim
remains except where describing the `TApp` residual or history.


## Concrete Steps

All commands run from `/Users/shinzui/Keikaku/bokuno/keiki`.

Confirm solver and baseline (M0):

    z3 --version
    cabal build all
    cabal test all

Iterate per milestone:

    cabal build all
    cabal test all

To focus suites while iterating:

    cabal test keiki-test                              # keiki unit suite (incl. Keiki.SymbolicSpec)
    cabal test all --test-options=--match=/Symbolic/   # symbolic specs across packages

Expected transcript shape after M2 (illustrative):

    Keiki.SymbolicSpec
      memoization (EP-42)
        x /= x is symIsBot [✔]
        two edges PEq #x 0 / PEq #x 1 are single-valued [✔]
        symSatExt witness over a repeated read satisfies models [✔]

Commit after each milestone with both the MasterPlan and ExecPlan trailers and the
Intention trailer:

    git add -A
    git commit -m "feat(symbolic): EP-42 M1 — memoize register/input-field reads in the translator

    <body>

    MasterPlan: docs/masterplans/12-symbolic-arithmetic-terms-translator-memoization-and-real-boolalg-sat-witnesses.md
    ExecPlan: docs/plans/42-per-slot-and-per-input-field-memoization-in-the-symbolic-translator.md
    Intention: intention_01ks3939thethvf26jkpx3ksht"


## Validation and Acceptance

The plan is complete when, from `/Users/shinzui/Keikaku/bokuno/keiki`:

1. `cabal build all` succeeds.

2. `cabal test all` passes with no failures; the pending count is unchanged
   (`LoanApplicationSymbolicSpec`'s single-valuedness gate stays pending, with its reason
   now naming EP-43 as the remaining blocker).

3. New, observable behavior (each asserted by a test that fails before M1 and passes
   after):
   - `symIsBot (PNot (PEq (proj #x) (proj #x))) == True` (x ≠ x is empty).
   - An `isSingleValuedSym` fixture whose two edges are `PEq #x (lit 0)` and
     `PEq #x (lit 1)` is `True` (was `False`).
   - A `symSatExt` witness over a repeated-read predicate satisfies `models`.

4. The existing `Jitsurei.UserRegistrationSymbolicSpec` `symSatExt` round-trips and all
   other symbolic specs still pass (no regression from the `SymEnv` shape change).


## Idempotence and Recovery

The translator change is internal to `Keiki.Symbolic` and is exercised by the existing
specs, so a mistake surfaces immediately as a failing or differently-answered spec.
`cabal build all` / `cabal test all` are safe to run repeatedly. The new `SymEnv` shape
and `memoFree` are pure additions to the module; re-applying the edit is a no-op if
already present. To recover, revert `SymEnv` to the single-field newtype and the two
`translateTermSym` arms to their `SBV.free`-per-occurrence form — the rest of the module
is independent. If z3 is missing, the symbolic specs fail loudly with a solver-not-found
error; install z3 (`brew install z3` / `apt install z3`) and re-run. Each milestone is
committed separately, so `git revert` of a milestone commit cleanly backs it out.


## Interfaces and Dependencies

Libraries: `sbv` (already a dependency) for `SBV`, `Symbolic`, `SymVal`, `free`;
`base`/`containers` for `Data.IORef` and `Data.Map.Strict`; `Type.Reflection` (already
imported) for `eqTypeRep`/`typeRep`/`HRefl`. The z3 solver on `PATH` at test time. No new
dependencies (containers and base are already transitive/direct; confirm `containers` is
listed in `keiki.cabal`'s `build-depends` and add it if not — it almost certainly is).

Types/signatures that must exist at the end (all in `Keiki.Symbolic`, internal — not
necessarily exported):

    data SymEnv = SymEnv { seInputCtor :: SBV.SBV String, seVarCache :: IORef (Map String SomeSBV) }
    data SomeSBV where SomeSBV :: SBV.SymVal a => SBV.SBV a -> SomeSBV
    mkSymEnv     :: SBV.Symbolic SymEnv
    memoFree     :: forall a. SBV.SymVal a => SymEnv -> String -> SBV.Symbolic (SBV.SBV a)
    translateTermSym :: forall rs ci r. Sym r => SymEnv -> Term rs ci r -> SBV.Symbolic (SBV.SBV (SymRep r))

Backward compatibility: `SymEnv` is constructed only inside `Keiki.Symbolic` (via
`mkSymEnv`) and consumed only by `translateTermSym`/`translatePred`; widening it from a
newtype to a record is internal. `mkSymEnv` and `translateTermSym` keep their public
signatures. `symSat`/`symIsBot`/`symSatExt`/`isSingleValuedSym` are unchanged in type and
become more precise in behavior.

Relationship to sibling plans (see the MasterPlan's Dependency Graph and Integration
Points):

- `docs/plans/43-structural-arithmetic-terms-in-the-keiki-term-language.md` (arithmetic
  terms) adds new `Term` constructors with their own `translateTermSym` arms. Those arms
  read sub-terms through the same `env`, so they inherit this plan's memoization
  automatically. The **integration capstone** — un-pending
  `Jitsurei.LoanApplicationSymbolicSpec`'s single-valuedness gate — requires *both* this
  plan (to share `#appCreditScore`) and EP-43 (to make the cap's `maxApprovalForScore`
  structural so it stops minting independent variables). That capstone is owned by EP-43's
  final milestone.
- `docs/plans/44-real-witnesses-from-boolalg-sat-retire-the-placeholder-witness.md` (real
  `BoolAlg.sat` witnesses) makes `sat (SymPred p)` return a real witness via the
  `symSatExt` machinery. Those witnesses are only correct for repeated-read predicates
  once this plan lands, so EP-44 soft-depends on this plan.
