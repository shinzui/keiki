---
id: 12
slug: symbolic-arithmetic-terms-translator-memoization-and-real-boolalg-sat-witnesses
title: "Symbolic arithmetic terms, translator memoization, and real BoolAlg.sat witnesses"
kind: master-plan
created_at: 2026-05-20T18:50:51Z
intention: "intention_01ks3939thethvf26jkpx3ksht"
---

# Symbolic arithmetic terms, translator memoization, and real BoolAlg.sat witnesses

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Vision & Scope

keiki can prove things about an aggregate's guards at build time by translating each guard
to the z3 SMT solver (via the `sbv` library): are two outgoing edge guards mutually
exclusive (`isSingleValuedSym`), is a guard satisfiable and what concrete input satisfies
it (`symSatExt`), is a guard a contradiction (`symIsBot`). The translator lives in
`src/Keiki/Symbolic.hs`; the guard/term languages it walks live in `src/Keiki/Core.hs`.

A review of the symbolic layer identified five gaps. EP-41
(`docs/plans/41-symbolic-numeric-and-ordering-guards-sym-money-fixed-width-ints-ordering-predicate.md`,
complete) closed the first two: fixed-width integer / money types are now in the `Sym`
registry, and an ordering predicate `PCmp` makes `<`/`≤`/`>`/`≥` thresholds structural.
**This MasterPlan closes the remaining three.**

After this initiative, a keiki author can:

1. Write **structural arithmetic** in a guard — `score * lit 1000`,
   `listingVolume + buyerVolume` — and the solver reasons about the *computed operand*,
   not just the comparison around it. Today such operands route through an opaque
   `TApp1`/`TApp2` and become a fresh unconstrained variable. (Gap #3.)

2. Trust that **two reads of the same register or input field share one solver variable**
   within a predicate. Today each occurrence allocates a fresh variable, so `#x == #x`
   looks satisfiable-but-not-valid, a self-mutex `g ∧ ¬g` over a re-read register is
   reported satisfiable, and `symSatExt` witnesses can be wrong for repeated reads.
   (Gap #4.)

3. Get a **real witness from `BoolAlg.sat`** on a `SymPred`. Today `sat` returns a
   placeholder that crashes if forced; the real witness is only reachable through the
   separate `symSatExt`. (Gap #5.)

The capstone observable that ties the work together: `Jitsurei.LoanApplication`'s
single-valuedness gate (`jitsurei/test/Jitsurei/LoanApplicationSymbolicSpec.hs`), pending
since before EP-41, becomes provable and is un-pended — but only once *both* the
arithmetic-terms work and the memoization work land (see Integration Points).

In scope: `+`/`-`/`*` arithmetic over the existing numeric `Sym` types; per-slot and
per-`(InCtor, field)` memoization in the translator; real `sat` witnesses. Explicitly out
of scope (unchanged from EP-41's boundary): division and floating-point / SBV real
(`SReal`) arithmetic (money is `Word64` minor units by convention); collection-content
guards / quantifiers (`PMember`/`PAll`), which are the separate collection-registers
feature (`docs/research/collection-registers-design.md`); and any new aggregate — the work
is dogfooded on the shipped `Jitsurei.OrderCart` and `Jitsurei.LoanApplication`.


## Decomposition Strategy

The three remaining gaps map cleanly onto three functional concerns, each touching a
different part of the symbolic stack and each independently verifiable:

- **The term language** (`Keiki.Core`'s `Term`) gains arithmetic — EP-43.
- **The translator's variable allocation** (`Keiki.Symbolic`'s `SymEnv` /
  `translateTermSym`) gains memoization — EP-42.
- **The `BoolAlg` witness contract** (`Keiki.Symbolic`'s `SymPred` instance) gains real
  witnesses — EP-44.

This honors the MasterPlan decomposition principles: each child plan produces a
demonstrable, before/after-falsifiable behavior on its own (a constant arithmetic
contradiction detected; `x ≠ x` proven empty; a `sat` witness that survives being forced),
and the plans modify largely disjoint code, so cross-plan coupling is low. Three plans is
within the 2–7 guideline; no phasing is needed.

Alternatives considered and rejected:

- **One big "finish the symbolic layer" ExecPlan.** Rejected: it would span the term
  language, the translator, and the typeclass instance — more than five milestones across
  unrelated modules — exactly the unwieldy single plan the MasterPlan guidance warns
  against. The three concerns have different risk profiles (arithmetic is a wide additive
  AST change; memoization is a focused translator rewrite; witnesses is a small instance
  change) and benefit from separate, independently-revertable milestones.

- **Merging memoization (EP-42) and real witnesses (EP-44)** into one "witness trust"
  plan, since both improve witness correctness. Rejected: they modify different functions
  (the translator vs. the `BoolAlg` instance) and have distinct falsifiers, so they are
  independently verifiable. Keeping them separate lets EP-44 ship on its own timeline and
  keeps each plan's blast radius small. They are linked only by a soft dependency.

- **Adding an AgentQualification end-to-end dogfood plan** (porting
  `docs/research/agent-qualification-decomposition-sketch.md`'s `ChapterQualification`
  weighted-sum-threshold case into a shipped aggregate). Considered and deferred by user
  decision (2026-05-20): the three capability plans, dogfooded on the existing
  `OrderCart`/`LoanApplication`, are the smallest coherent scope that closes the named
  gaps. The AgentQualification port remains a possible future ExecPlan once these land.


## Exec-Plan Registry

Note: the `#` column is the global ExecPlan number (the file lives at
`docs/plans/<#>-…md`), and dependencies reference these same global numbers, so the
registry, the prose below, and the child plans' cross-references all use one numbering.

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| 42 | Per-slot and per-input-field memoization in the symbolic translator | docs/plans/42-per-slot-and-per-input-field-memoization-in-the-symbolic-translator.md | None | None | Complete |
| 43 | Structural arithmetic terms in the keiki Term language | docs/plans/43-structural-arithmetic-terms-in-the-keiki-term-language.md | None (M0–M2, M4); EP-42 for the M3 un-pend capstone | EP-42 | Not Started |
| 44 | Real witnesses from BoolAlg.sat (retire the placeholder witness) | docs/plans/44-real-witnesses-from-boolalg-sat-retire-the-placeholder-witness.md | None | EP-42 | Not Started |

Status values: Not Started, In Progress, Complete, Cancelled.


## Dependency Graph

EP-42 (memoization) is the foundation and has no dependencies; implement it first.

Both EP-43 (arithmetic) and EP-44 (witnesses) can be built independently of EP-42 for the
bulk of their work, and independently of each other — they touch disjoint code (EP-43: the
`Term` AST and `translateTermSym`'s arithmetic arm plus `discoverSymNum`; EP-44: the
`BoolAlg (SymPred …)` instance). After EP-42 is done, EP-43 and EP-44 can proceed in
parallel.

The dependencies that exist are:

- **EP-43 → EP-42 (soft, except one milestone hard).** EP-43's arithmetic translation
  reads its sub-terms through the shared translation environment, so it automatically
  benefits from EP-42's memoization once that lands; nothing in EP-43's arithmetic *needs*
  memoization to compile or to verify its own falsifiers (constant contradictions,
  single-read sums). The exception is EP-43's **M3 integration capstone** — un-pending
  `Jitsurei.LoanApplicationSymbolicSpec`'s single-valuedness gate — which **hard-requires
  EP-42** (see Integration Points). EP-43 is written to detect whether EP-42 is complete:
  if so it un-pends; if not it defers the un-pend and keeps the gate pending with a
  sharpened reason.

- **EP-44 → EP-42 (soft).** EP-44 makes `sat` return the witness `symSatExt` produces.
  That witness is correct for predicates with *repeated reads* only after EP-42; before
  EP-42 it inherits the same repeated-read caveat `symSatExt` documents. EP-44 can ship
  before EP-42 if its proofs use single-read predicates, but the recommended order is
  EP-42 first.

Recommended implementation order: **EP-42, then EP-43 and EP-44 in parallel**, with
EP-43's M3 capstone executed after both EP-42 and EP-43's earlier milestones are done.


## Integration Points

1. **`Keiki.Symbolic.translateTermSym` and `SymEnv` (EP-42 ⇄ EP-43).**
   EP-42 rewrites `SymEnv` (from a single-field newtype to a record carrying an
   `IORef`-backed memo cache) and the `TReg`/`TInpCtorField` arms of `translateTermSym` to
   consult it. EP-43 adds a new `TArith` arm to the same `translateTermSym` function. These
   are disjoint arms of one function. **EP-42 owns the `SymEnv` shape**; EP-43's `TArith`
   arm reads its operands via `translateTermSym env` (the recursive call), so it inherits
   memoization with no extra work regardless of which plan lands first. If EP-43 lands
   first, its `TArith` arm uses the existing `SymEnv`; when EP-42 then rewrites `SymEnv`,
   the recursive call keeps compiling unchanged. No reconciliation step is required beyond
   "whichever lands second adds its arm next to the other's."

2. **Un-pending `Jitsurei.LoanApplicationSymbolicSpec`'s single-valuedness gate (EP-42 +
   EP-43 — the capstone).** The gate asserts
   `isSingleValuedSym (withSymPred loanApplication) == True`. At the `UnderReview` vertex
   two edges are guarded by (roughly) `approvalGuard` and its negation, so the gate reduces
   to proving `approvalGuard ∧ ¬approvalGuard` unsatisfiable. `approvalGuard` contains
   `appRequestedAmount <= maxApprovalForScore appCreditScore`. For the conjunction to be
   unsat, **both** of the following must hold:
   - **(EP-43)** the cap's `maxApprovalForScore appCreditScore` must be *structural
     arithmetic* (`appCreditScore * lit 1000`), not an opaque `TApp1`. Otherwise the two
     copies of `approvalGuard` (one in the left conjunct, one inside `¬approvalGuard`) each
     mint an independent `app1` variable for the cap, and the conjunction stays satisfiable.
   - **(EP-42)** the repeated reads of `#appCreditScore` (and `#appRequestedAmount`,
     `#appEmploymentVerified`) across the two copies must share one solver variable.
     Otherwise the two copies range over independent variables and the conjunction stays
     satisfiable.
   **Ownership:** the un-pend is EP-43's M3 milestone (it makes the last opaque term
   structural), gated on EP-42 being complete. If EP-43 reaches M3 before EP-42 is done,
   it defers the un-pend (keeps the gate pending with an EP-42-only reason) and the un-pend
   becomes an open MasterPlan integration item to close when EP-42 lands. This MasterPlan's
   Progress tracks the capstone explicitly.
   *Correction recorded:* the spec's pre-existing pending message (written after EP-41)
   blamed only the memoization sibling. That is incomplete — the cap's `TApp1` means
   arithmetic terms are *also* required. EP-42's M3 sharpens the message to name EP-43;
   EP-43's M3 closes it. See Surprises & Discoveries.

3. **The witness path: `symSatExt` / `BoolAlg.sat` (EP-42 ⇄ EP-44).** EP-42 makes
   `symSatExt` witnesses correct for repeated reads (by name lookup against a model that
   now binds each name once). EP-44 makes `BoolAlg.sat` on `SymPred` *call* `symSatExt`
   (via instance-head constraints), so EP-44's `sat` witnesses inherit EP-42's correctness.
   No shared edit; EP-44 consumes what EP-42 improves. EP-44 also tightens the
   `BoolAlg (SymPred …)` instance head with `(ExtractRegFile rs, KnownInCtors ci)`, which
   ripples onto `isSingleValuedSym` at `SymPred`; all shipped aggregates and the fixtures
   the other plans use already satisfy it.


## Progress

EP-42 (memoization):

- [x] EP-42 M0 — Baseline + record *before* falsifiers (2026-05-20)
- [x] EP-42 M1 — Memoizing `SymEnv` + translator (`memoFree`, name-keyed `IORef` cache) (2026-05-20)
- [x] EP-42 M2 — keiki-side proofs (`x ≠ x` empty; `PEq #x 0`/`PEq #x 1` single-valued; repeated-read `symSatExt` flip) (2026-05-20)
- [x] EP-42 M3 — Dogfood + sharpen `LoanApplicationSymbolicSpec` pending reason to name EP-43 (2026-05-20)
- [x] EP-42 M4 — Docs (`sbv-boolalg-design.md` memoization marked implemented) + close (2026-05-20)

EP-43 (arithmetic terms):

- [ ] EP-43 M0 — Baseline + authoritative `Term`-walker list
- [ ] EP-43 M1 — `NumOp`/`TArith` + `evalTerm` + every total `Term` walker + smart constructors (warning-clean)
- [ ] EP-43 M2 — SBV translation (`SymNumDict`/`discoverSymNum` + `TArith` arm) + keiki-side proofs
- [ ] EP-43 M3 — Migrate `LoanApplication` cap to `tmul`; **integration capstone:** un-pend the single-valuedness gate iff EP-42 complete
- [ ] EP-43 M4 — Docs (`sbv-boolalg-design.md`, `agent-qualification-decomposition-sketch.md` §3(c)/§5, guides) + close

EP-44 (real witnesses):

- [ ] EP-44 M0 — Baseline + record *before* placeholder crash
- [ ] EP-44 M1 — Constrain `BoolAlg (SymPred …)` head; `sat = symSatExt`; retire `unsafeWitness`/`symSat`; add any missing fixture `KnownInCtors`
- [ ] EP-44 M2 — Proofs (`sat` witness survives forcing and satisfies `models`)
- [ ] EP-44 M3 — Docs (`sbv-boolalg-design.md` "Sat witness extraction" superseded) + close

Integration capstone (cross-plan):

- [ ] `isSingleValuedSym (withSymPred loanApplication) == True` un-pended (requires EP-42 **and** EP-43)


## Surprises & Discoveries

- 2026-05-20 (planning): **The LoanApplication single-valuedness un-pend needs BOTH
  memoization and arithmetic, not memoization alone.** `Jitsurei.LoanApplicationSymbolicSpec`'s
  pending message (shipped after EP-41) names only the per-slot memoization sibling as the
  remaining blocker. That is incomplete: `approvalGuard`'s cap conjunct
  `appRequestedAmount <= maxApprovalForScore appCreditScore` is an opaque `TApp1`, and the
  two copies of `approvalGuard` in the self-mutex `approvalGuard ∧ ¬approvalGuard` each
  translate that `TApp1` to an *independent* fresh variable (the memoization sibling
  deliberately does **not** memoize `TApp` results — opaque functions have no `Eq`). So
  even with register memoization sharing `#appCreditScore`, the conjunction stays
  satisfiable via the cap until the `TApp1` becomes structural arithmetic (EP-43). Net
  effect on the plan: the un-pend is the joint EP-42 + EP-43 capstone (Integration Point
  2), and EP-42's M3 corrects the pending message to name EP-43. Evidence:
  `translateTermSym _env (TApp1 _f _t) = SBV.free "app1"` (`src/Keiki/Symbolic.hs:355`)
  allocates per occurrence; EP-41 verified empirically that same-name `SBV.free` calls do
  not alias (EP-41 Surprises & Discoveries, 2026-05-20).

- 2026-05-20 (EP-42 complete): **Memoization landed; the capstone correctly remains blocked
  on EP-43.** EP-42 shipped the name-keyed `IORef (Map String SomeSBV)` cache in `SymEnv`
  and the four falsifiers flipped (recorded in EP-42's Outcomes). As predicted in the
  planning entry above, the `LoanApplicationSymbolicSpec` single-valuedness gate did *not*
  become un-pendable: with `#appCreditScore` now shared, the surviving blocker is the cap's
  opaque `TApp1` (EP-43). EP-42 M3 corrected the gate's pending message and module haddock
  to name EP-43, and swept the guide/research docs so no stale "repeated reads lose
  precision" claim remains (except the honest `TApp` residual). Two minor implementation
  surprises: `SBV.SymVal` carries a `Typeable` superclass (so `SomeSBV` needs no extra
  constraint), and `containers` was missing from `keiki.cabal`'s library `build-depends`
  (added `>= 0.6 && < 0.9`). The cross-plan handoff for EP-43/EP-44 is exactly as the
  Integration Points describe — both inherit the memoization with no extra work.


## Decision Log

- Decision: Decompose the three remaining symbolic-layer gaps into three sibling ExecPlans
  — EP-42 (memoization), EP-43 (arithmetic terms), EP-44 (real `BoolAlg.sat` witnesses) —
  rather than one combined plan or a memoization+witness merge.
  Rationale: each is an independently-verifiable behavior touching largely disjoint code;
  three is within the 2–7 guideline; separate milestones keep each change revertable. See
  Decomposition Strategy.
  Date: 2026-05-20

- Decision: EP-42 is the foundation and is recommended first; EP-43 and EP-44 each
  soft-depend on it and can otherwise proceed in parallel.
  Rationale: memoization strengthens the precision and witness-correctness that both other
  plans rely on, but neither needs it to compile or to prove its own falsifiers. See
  Dependency Graph.
  Date: 2026-05-20

- Decision: The LoanApplication single-valuedness un-pend is the MasterPlan's integration
  capstone, owned by EP-43's M3 and hard-gated on EP-42.
  Rationale: it is the one observable that demonstrably requires two plans composed
  (structural cap + shared register variable). See Integration Points 2 and the Surprises
  entry.
  Date: 2026-05-20

- Decision: Keep scope to the three capability plans dogfooded on existing aggregates; do
  not add an AgentQualification end-to-end port in this MasterPlan.
  Rationale: user decision (2026-05-20) — smallest coherent scope that closes the named
  gaps. The port stays a possible future ExecPlan.
  Date: 2026-05-20


## Outcomes & Retrospective

(To be filled during and after implementation. Compare against the Vision: are structural
arithmetic operands, repeated-read precision, and real `sat` witnesses all delivered, and
was the LoanApplication single-valuedness gate un-pended? Record which falsifiers flipped
and any decomposition adjustments.)
