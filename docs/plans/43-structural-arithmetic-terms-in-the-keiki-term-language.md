---
id: 43
slug: structural-arithmetic-terms-in-the-keiki-term-language
title: "Structural arithmetic terms in the keiki Term language"
kind: exec-plan
created_at: 2026-05-20T18:50:57Z
intention: "intention_01ks3939thethvf26jkpx3ksht"
master_plan: "docs/masterplans/12-symbolic-arithmetic-terms-translator-memoization-and-real-boolalg-sat-witnesses.md"
---

# Structural arithmetic terms in the keiki Term language

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

keiki proves things about an aggregate's guards at build time by translating the guard to
the z3 SMT solver (via the `sbv` library). EP-41 made *comparisons* structural: a
threshold like `creditScore >= 650` is now a first-class `PCmp` predicate the solver
reads exactly, instead of an opaque Haskell function wrapped in a `TApp`. But the
*operands* of a comparison can still be opaque. keiki's term language
(`Term`, in `src/Keiki/Core.hs`) has no arithmetic: sums, differences, and products are
built by wrapping a Haskell `(+)`/`(-)`/`(*)` in `TApp1`/`TApp2`, which translate to a
fresh, unconstrained solver variable. So a guard over a *computed* value — a weighted
sum, a running delta, a derived cap — is invisible to the solver even though the
comparison around it is structural.

The shipped instance of this is `Jitsurei.LoanApplication`'s approval guard. Its cap
conjunct is `appRequestedAmount <= maxApprovalForScore appCreditScore`, where
`maxApprovalForScore score = score * 1000` (`jitsurei/src/Jitsurei/LoanApplication.hs:146`).
Today the right-hand side is `TApp1 maxApprovalForScore (proj #appCreditScore)` — an
opaque term. The solver sees `appRequestedAmount <= v` for a fresh `v` and learns
nothing about the relationship between the cap and the credit score.

After this change, a keiki author can write structural arithmetic — `score * lit 1000`,
`listingVolume + buyerVolume` — and the solver reasons about it for real. Concretely,
after implementation you will be able to run the test suite and observe: a *constant*
arithmetic ordering contradiction such as `lit 2 + lit 3 > lit 10` is reported empty
(`symIsBot` returns `True`) where today it can only be written through `TApp` and is
reported satisfiable; an ordering guard over a structural sum such as
`#a + #b >= lit 10` yields a concrete witness whose `a + b` is actually `>= 10` rather
than an unconstrained default; and `Jitsurei.LoanApplication`'s cap conjunct becomes a
structural multiplication that the solver reads.

This plan is one of three sibling ExecPlans under MasterPlan 12
(`docs/masterplans/12-symbolic-arithmetic-terms-translator-memoization-and-real-boolalg-sat-witnesses.md`).
Its **final milestone is the MasterPlan's integration capstone**: once the cap conjunct
is structural arithmetic *and* the per-slot memoization sibling
(`docs/plans/42-per-slot-and-per-input-field-memoization-in-the-symbolic-translator.md`)
has landed, `Jitsurei.LoanApplicationSymbolicSpec`'s single-valuedness gate becomes
provable and is un-pended. That capstone requires EP-42; the rest of this plan does not.


## Progress

- [x] M0 — Baseline (2026-05-20): z3 4.15.8; build/test green at the EP-42-close baseline
      (keiki-test 222/0, jitsurei-test 94/0/1-pending, json 40/0 + 7/0). Walker grep
      reproduced the Context list exactly (14 sites: `evalTerm`, `stepOne`, two `goTerm`s,
      `termReadsInput`, `termHasInpCtorField` in Core; `weakenLTerm`, `weakenRTerm`,
      `substTerm`, `liftLTermAlt`, `liftRTermAlt` in Composition; two `go`s in Profunctor;
      `translateTermSym` in Symbolic). `-Wincomplete-patterns` confirmed completeness at M1.
- [x] M1 — `Term` arithmetic + evalTerm + every walker (2026-05-20): added `data NumOp`
      and `TArith` to `Keiki.Core`, the `evalTerm` arm (+ `applyNumOp` helper), smart
      constructors `tadd`/`tsub`/`tmul`, exports `NumOp(..)`/`tadd`/`tsub`/`tmul`, and a
      `TArith` arm to all 14 walkers (placeholder `SBV.free "arith"` in `Symbolic`). Build
      warning-clean under `-Wincomplete-patterns` (the two pre-existing `Jitsurei/Loan.hs`
      + `CoreBankingSync.hs` unused-bind warnings are unrelated); full suite green with M0
      counts unchanged — purely additive, no behavior change. The two `goTerm` walkers in
      Core carry a `_ = []` wildcard, so the explicit `TArith` arms there are for
      correctness (hidden-input detection through arithmetic operands), not to satisfy the
      checker.
- [x] M2 — SBV translation + keiki-side proofs (2026-05-20): added `SymNumDict` +
      `discoverSymNum` (exported) and the real `TArith` arm of `translateTermSym` (emits
      `(+)`/`(-)`/`(*)` over translated operands on a `discoverSymNum` hit, opaque
      `SBV.free "arith"` fallback otherwise); updated `translateTermSym`'s haddock. Added a
      `describe "structural arithmetic (EP-43)"` block to `Keiki.SymbolicSpec` (7
      assertions: constant `2+3>10` / `10-3==8` are `symIsBot`, satisfiable companions are
      not; `symSatExt` witnesses respect `#a+#b>=10` and `#req<=#score*1000`;
      `evalPred`/`evalTerm` agree with Haskell `+`/`-`/`*`). `cabal test keiki-test` → 229
      examples (was 222), 0 failures. No SBV `Num`-on-`SInteger` surprises — `SBV.SBV
      Integer`'s `Num` instance is exactly what `SymNumDict` carries.
- [ ] M3 — Dogfood + integration capstone: migrate
      `Jitsurei.LoanApplication`'s `maxApprovalForScore` cap from `TApp1` to structural
      `tmul` (behavior-preserving; all LoanApplication behavioural + builder-equivalence
      specs stay green). If EP-42 (memoization) is complete, un-pend
      `Jitsurei.LoanApplicationSymbolicSpec`'s single-valuedness gate
      (`isSingleValuedSym (withSymPred loanApplication) == True`); otherwise keep it
      pending with a reason naming EP-42 as the remaining blocker and record the deferral.
- [ ] M4 — Docs + close: update `docs/research/sbv-boolalg-design.md`,
      `docs/research/agent-qualification-decomposition-sketch.md` (§3(c)/§5: the
      `weightedVolume` operand and `maxApprovalForScore` are now structural; arithmetic
      gap closed), and the guides; sweep for stale "no arithmetic in Term" claims. Fill
      Outcomes.


## Surprises & Discoveries

- 2026-05-20 (M1). The authoritative `Term`-walker set matched the plan's Context list
  exactly — no walker beyond the 14 enumerated, and `-Wincomplete-patterns` raised nothing
  after the additions. The two `goTerm` walkers in `Keiki.Core`
  (`checkHiddenInputs`/`detectMissingInCtorFields`) end in a `goTerm _ = []` wildcard, so
  they would *not* have warned about a missing `TArith` arm; the explicit recursing arms
  added there are a correctness fix (a `TInpCtorField` nested inside a `TArith` operand in
  an output term must still be discovered by hidden-input detection), not a checker
  requirement. `applyNumOp :: Num r => NumOp -> r -> r -> r` is a top-level helper; the
  `Num r` evidence in `evalTerm`'s `TArith` arm comes from matching the GADT constructor.


## Decision Log

- Decision: Arithmetic is a single `Term` constructor `TArith :: (Num r, Typeable r) =>
  NumOp -> Term rs ci r -> Term rs ci r -> Term rs ci r` carrying a tag
  `data NumOp = OpAdd | OpSub | OpMul`, rather than separate `TAdd`/`TSub`/`TMul`
  constructors.
  Rationale: one constructor means one arm per walker (each switching on `NumOp`),
  matching the compact style EP-41 used for `Cmp`/`PCmp`. Adding `Term` constructors is
  expensive precisely because every total `Term` walker needs a new arm; minimizing the
  constructor count minimizes that cost. The three directions are recovered by smart
  constructors `tadd`/`tsub`/`tmul`.
  Date: 2026-05-20

- Decision: Scope is `+`, `-`, `*` over the existing numeric `Sym` types only
  (`Int`/`Integer`/`Word8`/`Word16`/`Word32`/`Word64`/`Int32`/`Int64`). No division,
  no `Double`/`SReal`, no power.
  Rationale: division introduces solver-side partiality (division by zero) and is not
  needed by the motivating aggregates (money is `Word64` minor units; the cap is a
  multiply; weighted sums are `+`/`*`). `Double`/`SReal` is already excluded by the
  money-is-`Word64` convention (EP-41 Decision Log). The over-approximation note that
  EP-41 attached to the fixed-width `Sym` instances (modular wraparound is not modeled
  because `SymRep = Integer`) carries over unchanged to `TArith` and is acceptable for
  in-range money/count arithmetic.
  Date: 2026-05-20

- Decision: Symbolic translation of `TArith` is gated by a new `discoverSymNum`
  companion to `discoverSym`/`discoverSymOrd`, yielding evidence that the operand type's
  `SymRep` is a `Num` instance under SBV (`Num (SBV (SymRep r))`). A type whose `SymRep`
  is not SBV-`Num` (or that is not in the registry) falls back to a fresh opaque variable,
  exactly as `goEq`/`goCmp` fall back. The `Num r` constraint on the `TArith` constructor
  already prevents constructing arithmetic at non-numeric types (e.g. `Text`), so the
  fallback is only reachable for a numeric type intentionally left out of the registry.
  Rationale: keeps the change sound by construction and additive.
  Date: 2026-05-20

- Decision: Un-pending `Jitsurei.LoanApplicationSymbolicSpec`'s single-valuedness gate is
  this plan's M3 capstone but **hard-requires EP-42 (memoization)**. The self-mutex
  `approvalGuard ∧ ¬approvalGuard` is unsatisfiable only when (a) the cap conjunct's
  `maxApprovalForScore` is structural arithmetic (this plan) *and* (b) the two reads of
  `#appCreditScore` across the two copies of `approvalGuard` share one solver variable
  (EP-42). With only this plan, the cap is structural but each copy still reads
  `#appCreditScore` as an independent variable, so the conjunction stays satisfiable.
  Rationale: this is the canonical MasterPlan-12 integration point; it is owned here
  because this plan makes the last opaque term structural, and it is documented in the
  MasterPlan's Integration Points.
  Date: 2026-05-20


## Outcomes & Retrospective

(To be filled during and after implementation. Record the final walker list, whether the
LoanApplication single-valuedness gate was un-pended here or deferred to await EP-42, and
the observable falsifiers that flipped.)


## Context and Orientation

This section assumes no prior knowledge of keiki. Read it before editing.

keiki is a Haskell library (the package at the repository root, `keiki.cabal`, module
prefix `Keiki.*`) for the pure core of event sourcing. An aggregate is a `SymTransducer`:
a finite control graph plus a typed *register file* (named, typed mutable slots) whose
edges carry a *guard* (a predicate), an *update* (register writes), an *output* (events),
and a *target* vertex. Example aggregates live in `jitsurei`
(`jitsurei/src/Jitsurei/*.hs`). `cabal.project` lists `.` (keiki), `jitsurei`,
`keiki-codec-json`, `keiki-codec-json-test`.

### The term language you are extending

`Term rs ci r` (`src/Keiki/Core.hs`, around line 196) is a pure expression producing an
`r`. `rs` is the register-file slot list (`Slot = (Symbol, Type)`); `ci` is the input
command type. Today's constructors:

    data Term (rs :: [Slot]) (ci :: Type) (r :: Type) where
      TLit          :: r -> Term rs ci r
      TReg          :: Index rs r -> Term rs ci r
      TInpCtorField :: InCtor ci ifs -> Index ifs r -> Term rs ci r
      TApp1         :: (a -> r)      -> Term rs ci a -> Term rs ci r
      TApp2         :: (a -> b -> r) -> Term rs ci a -> Term rs ci b -> Term rs ci r

`TApp1`/`TApp2` are the escape hatch: arbitrary Haskell, opaque to analysis. Smart
constructors live near line 534: `proj = TReg`, `inpCtor = TInpCtorField`, `lit = TLit`.
`OverloadedLabels` lets `#x` mean `TReg (indexOf …)` via `fromLabel` (line 186).

`evalTerm :: Term rs ci r -> RegFile rs -> ci -> r` (line 570) is the concrete evaluator;
every `Term` constructor needs an arm. `evalPred` (line 596) evaluates `HsPred`; you do
not change `HsPred` — `PCmp` (from EP-41) already gives you the comparison; this plan
makes the comparison's *operands* structural.

### Every total `Term` walker (the cost of a new constructor)

Adding a `Term` constructor requires a new arm in **every function that pattern-matches
`Term` exhaustively**, or the build breaks under `-Wincomplete-patterns` (this repo
treats incomplete patterns as warnings that the milestones must keep clean). Enumerated by
grep (`grep -rn 'TLit \|TReg \|TInpCtorField \|TApp1 \|TApp2 ' src/Keiki/*.hs`), the
walkers are:

In `src/Keiki/Core.hs`:

1. `evalTerm` (line 570) — concrete evaluation. New arm computes the arithmetic.
2. `solveOutput`'s `stepOne` (lines 895–902) — output inversion. `TApp1`/`TApp2` return
   `Nothing` (cannot invert an opaque computation). `TArith` is likewise a computation,
   so it returns `Nothing`. Arm: `stepOne (TArith _ _ _) _val _ = Nothing`.
3. `checkHiddenInputs`' inner `goTerm` (lines 1003–1010) — gathers input-field reads from
   a term. Recurse into both operands: `goTerm (TArith _ a b) = goTerm a ++ goTerm b`.
4. `termReadsInput` (lines 1038–1043) — does the term read the input?
   `termReadsInput (TArith _ a b) = termReadsInput a || termReadsInput b`.
5. `termHasInpCtorField` (lines 1053–1056, inside another helper) —
   `termHasInpCtorField (TArith _ a b) = termHasInpCtorField a || termHasInpCtorField b`.
6. A second `goTerm` (lines 1092–1099, a different hidden-input walker) —
   `goTerm (TArith _ a b) = goTerm a ++ goTerm b`.

In `src/Keiki/Composition.hs` (these rebuild terms under register/input weakening and
substitution; recurse structurally, preserving `op`):

7. `weakenLTerm` (line 159) — `weakenLTerm (TArith op a b) = TArith op (weakenLTerm @rs1 @rs2 a) (weakenLTerm @rs1 @rs2 b)`.
8. `weakenRTerm` (line 216) — analogous with `weakenRTerm`.
9. `substTerm` (line 342) — `substTerm (TArith op a b) o1 = TArith op (substTerm @rs1 @rs2 a o1) (substTerm @rs1 @rs2 b o1)`.
10. `liftLTermAlt` (line 533) — `liftLTermAlt (TArith op a b) = TArith op (liftLTermAlt @rs @ci1 @ci2 a) (liftLTermAlt @rs @ci1 @ci2 b)`.
11. `liftRTermAlt` (line 546) — analogous with `liftRTermAlt`.

In `src/Keiki/Profunctor.hs` (these re-target the input type of a term; recurse,
preserving `op`):

12. The `go` inside `contraTerm` (lines 818–822) — `go (TArith op a b) = TArith op (go a) (go b)`.
13. The `go` inside `contraMaybeTerm` (lines 829–833) — analogous.

In `src/Keiki/Symbolic.hs`:

14. `translateTermSym` (line 345) — the SBV arm. Placeholder/opaque in M1
    (`SBV.free "arith"`); real in M2 via `discoverSymNum`.

`src/Keiki/Render/Mermaid.hs`'s `edgeInputName` walks `HsPred` (the guard) to find the
input constructor name, not `Term` arithmetic, so it likely needs no change — but **trust
`-Wincomplete-patterns`**: build after M1 and add an arm anywhere the compiler flags one.
The grep list above is the expected set; the compiler is the authority.

### The symbolic surface (`src/Keiki/Symbolic.hs`)

- `class Sym a` with `SymRep a`, `toSym`/`fromSym`/`symDefault`; constraint
  `(SBV.SymVal (SymRep a), Typeable a)`. Numeric instances (post-EP-41): `Int`,
  `Integer`, `Word8`/`Word16`/`Word32`/`Word64`, `Int32`/`Int64` — all with
  `SymRep = Integer`.
- `discoverSym` (line 224) — `Typeable r -> Maybe (SymDict r)`, the curated registry.
- `discoverSymOrd` (line 259) — EP-41's companion yielding `OrdSymbolic` evidence for the
  numeric/time types; the model for `discoverSymNum`. Note its `SymOrdDict` shape:

        data SymOrdDict r where
          SymOrdDict :: (Sym r, SBV.OrdSymbolic (SBV.SBV (SymRep r))) => SymOrdDict r

- `translateTermSym :: Sym r => SymEnv -> Term rs ci r -> SBV.Symbolic (SBV.SBV (SymRep r))`
  (line 345) — structural for `TLit`/`TReg`/`TInpCtorField`; `TApp1`/`TApp2` →
  `SBV.free`. (If the memoization sibling EP-42 has already landed, `TReg`/`TInpCtorField`
  go through a memoizing `memoFree env` instead of `SBV.free`; your new `TArith` arm reads
  its sub-terms via `translateTermSym env`, so it inherits memoization automatically
  regardless of EP-42's status.)
- `translatePred` (line 384) — walks `HsPred`; `PEq`/`PCmp` translate operand terms via
  `translateTermSym env`. Your structural arithmetic flows straight into `PCmp`/`PEq`
  operands with no change to `translatePred`.
- `symIsBot`/`symSat`/`symSatExt`/`isSingleValuedSym` — the analyses. (Unchanged.)

### The shipped aggregate you migrate

`jitsurei/src/Jitsurei/LoanApplication.hs`:

- `maxApprovalForScore :: Int -> Int; maxApprovalForScore score = score * 1000` (line
  146). `type Money = Int` here (LoanApplication uses `Int`, not `Word64` — see EP-41's
  Surprises). `appCreditScore`, `appRequestedAmount`, the doc counts are all `Int`.
- `approvalGuard` (lines 419–428): a `PAnd` of `PCmp CmpGe #appCreditScore (lit
  approvalThresholdScore)`, `PEq #appEmploymentVerified (lit True)`, and the cap
  `PCmp CmpLe (proj #appRequestedAmount) (TApp1 maxApprovalForScore (proj #appCreditScore))`.
  You replace the `TApp1 maxApprovalForScore (proj #appCreditScore)` with
  `tmul (proj #appCreditScore) (lit 1000)`. `evalTerm (TArith OpMul score (lit 1000))
  == score * 1000 == maxApprovalForScore score`, so this is behavior-preserving and every
  LoanApplication behavioural spec stays green.

### The pending spec this plan can un-pend

`jitsurei/test/Jitsurei/LoanApplicationSymbolicSpec.hs` has two describe blocks: an
"ordering-guard win (EP-41)" block that passes, and a single-valuedness gate
(`isSingleValuedSym (withSymPred loanApplication) == True`) that is `pendingWith` a
message. After EP-42 (memoization) the message names the arithmetic sibling (this plan)
as the remaining blocker; after this plan's M3 cap migration *and* EP-42, both halves are
present and the gate is provable. Un-pend it (delete the `pendingWith` line) **only if
EP-42 is complete**; otherwise leave it pending with a reason naming EP-42.

### Where the tests live

- keiki unit tests: `keiki-test` (`keiki.cabal`, `main-is: Spec.hs`), symbolic unit tests
  in `Keiki.SymbolicSpec`. Arithmetic proofs (M2) go here; read it to match style and
  reuse fixtures (it has `Word64`/`Int` register fixtures from EP-41).
- jitsurei tests: `jitsurei-test` (`jitsurei/jitsurei.cabal`), with
  `Jitsurei.LoanApplicationSymbolicSpec`, `Jitsurei.LoanApplicationSpec`,
  `Jitsurei.LoanApplicationBuilderSpec` (the behavioural/builder-equivalence specs that
  guard the M3 migration).


## Plan of Work

Five milestones (M0–M4). M1 is purely additive (no behavior change — arithmetic exists in
the AST and evaluates, but is not yet solver-visible). M2 makes it solver-visible. M3 is
the only non-additive edit (the LoanApplication cap migration), which is
behavior-preserving and guarded by the existing specs.

### M0 — Baseline

Goal: known-good start and the authoritative walker list.

    z3 --version
    cabal build all
    cabal test all

Record example/pending counts in Progress. Re-run the walker grep and confirm it matches
the Context list:

    grep -rn 'TLit \|TReg \|TInpCtorField \|TApp1 \|TApp2 ' src/Keiki/Core.hs src/Keiki/Composition.hs src/Keiki/Profunctor.hs src/Keiki/Symbolic.hs

Acceptance: build/tests pass; counts recorded.

### M1 — `Term` arithmetic constructor + evaluator + every walker

Goal: arithmetic exists in the AST, evaluates concretely, and the build is clean under
`-Wincomplete-patterns`. No solver visibility yet.

In `src/Keiki/Core.hs`:

1. Add the tag near `Term` (mirror `Cmp`'s placement and deriving):

        data NumOp = OpAdd | OpSub | OpMul
          deriving stock (Eq, Show)

2. Add the constructor to `Term`:

        TArith :: (Num r, Typeable r)
               => NumOp -> Term rs ci r -> Term rs ci r -> Term rs ci r

3. Export `NumOp(..)` and `TArith` from the module's export list (the list already
   exports `Term(..)` or the individual constructors — match what is there; if `Term` is
   exported with all constructors, `TArith` comes along, but `NumOp(..)` must be added
   explicitly).

4. Add smart constructors next to `lit` (line 545):

        tadd, tsub, tmul :: (Num r, Typeable r) => Term rs ci r -> Term rs ci r -> Term rs ci r
        tadd = TArith OpAdd
        tsub = TArith OpSub
        tmul = TArith OpMul

   Export them too.

5. Add the `evalTerm` arm (line 570 area):

        evalTerm (TArith op a b) regs ci = applyNumOp op (evalTerm a regs ci) (evalTerm b regs ci)
          where
            applyNumOp OpAdd = (+)
            applyNumOp OpSub = (-)
            applyNumOp OpMul = (*)

   (`applyNumOp` can be a top-level helper or a `where`-local; the `Num r` evidence comes
   from the constructor's context, brought into scope by matching `TArith`.)

6. Add the `TArith` arm to the four remaining `Core` walkers (items 2–6 in the Context
   list): `stepOne` → `Nothing`; both `goTerm`s → recurse and concatenate; `termReadsInput`
   and `termHasInpCtorField` → recurse and `||`.

In `src/Keiki/Composition.hs`: add the structural recursive arm to `weakenLTerm`,
`weakenRTerm`, `substTerm`, `liftLTermAlt`, `liftRTermAlt` (items 7–11), each rebuilding
`TArith op` over the recursively transformed operands. Match the existing `TApp2` arm's
type-application style (e.g. `weakenLTerm @rs1 @rs2`).

In `src/Keiki/Profunctor.hs`: add the recursive arm to both `go` walkers (items 12–13),
mirroring their `TApp2` arms.

In `src/Keiki/Symbolic.hs`: add a **placeholder** `translateTermSym` arm so the build
stays warning-clean before M2 wires the real translation:

        translateTermSym _env (TArith _op _a _b) = SBV.free "arith"

Now build:

    cabal build all

Fix any `-Wincomplete-patterns` warning the compiler raises beyond the listed walkers
(record it in Surprises). Then:

    cabal test all

Everything must stay green: M1 changes no behavior (arithmetic evaluates via `evalTerm`
exactly as the equivalent `TApp` did, and the solver still treats it opaquely via the
placeholder, so no symbolic answer changes yet).

What exists at the end: `tadd`/`tsub`/`tmul` build `Term`s that evaluate correctly and
compile through every walker.

Acceptance: `cabal build all` is warning-clean for incomplete patterns; `cabal test all`
passes with M0's counts.

### M2 — SBV translation + keiki-side proofs

Goal: arithmetic operands become solver-visible.

In `src/Keiki/Symbolic.hs`, add the `Num` companion to `discoverSymOrd` (place it right
after `discoverSymOrd`, around line 270):

    data SymNumDict r where
      SymNumDict :: (Sym r, Num (SBV.SBV (SymRep r))) => SymNumDict r

    discoverSymNum :: forall r. Typeable r => Maybe (SymNumDict r)
    discoverSymNum
      | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Int)     = Just SymNumDict
      | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Integer) = Just SymNumDict
      | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Word64)  = Just SymNumDict
      | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Word32)  = Just SymNumDict
      | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Word16)  = Just SymNumDict
      | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Word8)   = Just SymNumDict
      | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Int64)   = Just SymNumDict
      | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Int32)   = Just SymNumDict
      | otherwise                                                = Nothing

   (All these have `SymRep = Integer`, and `SBV.SBV Integer` is a `Num` instance, so each
   `SymNumDict` constructs. `Bool`/`Text`/`UTCTime` are omitted — not meaningfully
   arithmetic here. Export `SymNumDict(..)` and `discoverSymNum`.)

Replace the placeholder `translateTermSym` arm with the real one:

    translateTermSym env (TArith op a b) = case discoverSymNum @r of
      Nothing         -> SBV.free "arith"   -- sound opaque fallback
      Just SymNumDict -> do
        sa <- translateTermSym env a
        sb <- translateTermSym env b
        let apply = case op of
              OpAdd -> (+)
              OpSub -> (-)
              OpMul -> (*)
        pure (apply sa sb)

   `r` is in scope via `ScopedTypeVariables`/`TypeApplications` on `translateTermSym`'s
   `forall rs ci r` (the function already uses `forall … r`). `discoverSymNum @r` needs
   `Typeable r`, available from the `Sym r` constraint. The arithmetic `apply` is over
   `SBV.SBV (SymRep r)`, whose `Num` instance is exactly what `SymNumDict` carries.

Update haddocks: `translateTermSym`'s doc (lines ~315–344) and the module header should
note `TArith` translates structurally on a `discoverSymNum` hit and falls back opaque on a
miss.

Add a `describe "structural arithmetic (EP-43)"` block to `Keiki.SymbolicSpec`:

1. Constant contradiction is empty: `symIsBot (PCmp CmpGt (tadd (lit (2::Int)) (lit 3)) (lit 10)) == True`
   (2 + 3 > 10 is always false). And the satisfiable companion
   `symIsBot (PCmp CmpGe (tadd (lit (2::Int)) (lit 3)) (lit 5)) == False`.
2. Single-read sum witness: `symSatExt` over `PAnd (PInCtor inCtorX) (PCmp CmpGe (tadd (proj #a) (proj #b)) (lit 10))`
   returns a witness `(regs, _)` with `(regs ! #a) + (regs ! #b) >= 10`. (`#a`, `#b` are
   distinct registers, so this needs no memoization.)
3. A multiply witness: `symSatExt` over `PCmp CmpLe (proj #req) (tmul (proj #score) (lit 1000))`
   returns a witness with `req <= score * 1000`.
4. `evalTerm`/`evalPred` agreement: for sample register files, `evalPred` of a `PCmp`/`PEq`
   over `tadd`/`tsub`/`tmul` equals the corresponding Haskell `+`/`-`/`*` then compare.

Build and run `cabal test keiki-test`.

What exists at the end: arithmetic operands are solver-visible; constant arithmetic
contradictions are detected; arithmetic-ordering witnesses are faithful.

Acceptance: `cabal test all` passes including the new block.

### M3 — Dogfood + integration capstone

Goal: prove arithmetic on a shipped aggregate, and close the MasterPlan's integration
capstone if its prerequisite is met.

First, migrate `Jitsurei.LoanApplication`'s cap conjunct. In `approvalGuard` (line ~426),
replace:

        PCmp CmpLe (proj (#appRequestedAmount :: Index LoanAppRegs Money))
                   (TApp1 maxApprovalForScore
                     (proj (#appCreditScore :: Index LoanAppRegs Int)))

   with:

        PCmp CmpLe (proj (#appRequestedAmount :: Index LoanAppRegs Money))
                   (tmul (proj (#appCreditScore :: Index LoanAppRegs Int)) (lit 1000))

   This is behavior-preserving: `evalTerm (tmul score (lit 1000)) = score * 1000 =
   maxApprovalForScore score`. Keep `maxApprovalForScore` defined (it may still be used
   elsewhere or in docs); if it becomes entirely unused, either leave it with a haddock
   note that the guard now inlines it structurally, or remove it and update references —
   check with `grep -rn maxApprovalForScore jitsurei`. Update the comment block above
   `approvalGuard` (lines ~395–404) that currently says the cap's RHS "needs the
   arithmetic-terms sibling" to say it is now structural `tmul` (EP-43).

   Run the LoanApplication behavioural and builder specs before and after to show
   equivalence:

        cabal test jitsurei-test --test-options=--match=/LoanApplication/

   All must stay green.

Second, the integration capstone. Check whether EP-42 (memoization) is complete:

    git log --oneline | grep "EP-42"        # or inspect the MasterPlan registry

   - **If EP-42 is complete:** un-pend the single-valuedness gate in
     `jitsurei/test/Jitsurei/LoanApplicationSymbolicSpec.hs` — delete the `pendingWith`
     block so the assertion `isSingleValuedSym (withSymPred loanApplication) == True` runs
     for real. Update the module haddock and the surrounding comments to record that the
     gate is now proven (memoization shares `#appCreditScore`; structural `tmul` makes the
     cap visible). Run `cabal test jitsurei-test --test-options=--match=/Symbolic/` and
     confirm it passes with **one fewer pending**.
   - **If EP-42 is not complete:** keep the gate `pendingWith`, but update its reason to
     name EP-42 as the *sole* remaining blocker (the arithmetic half is now done). Record
     in Progress and Decision Log that the un-pend is deferred until EP-42 lands, and note
     it as an open MasterPlan integration item. Add a *new* memoization-free assertion that
     demonstrates the arithmetic win on LoanApplication without needing the self-mutex —
     e.g. `symSatExt` on the approval edge guard returns a witness satisfying the cap
     `appRequestedAmount <= appCreditScore * 1000` (a single read of each register, so no
     memoization needed), strengthening EP-41's existing credit-score-only assertion.

What exists at the end: LoanApplication's cap is structural; its behavioural specs are
green; and the single-valuedness gate is either un-pended (EP-42 done) or pending with a
sharpened EP-42-only reason plus a new arithmetic-win assertion.

Acceptance: `cabal test all` passes; LoanApplication behavioural/builder specs identical
before/after; pending count drops by one iff EP-42 is complete.

### M4 — Documentation and close

Goal: leave the design record consistent.

Update `docs/research/sbv-boolalg-design.md`: the "Term translation rules" section
(~lines 290–310) lists only `TLit`/`TReg`/`TInpCtorField`/`TApp1`/`TApp2`; add `TArith`
(structural on a `discoverSymNum` hit, opaque fallback otherwise) and mention
`SymNumDict`/`discoverSymNum`.

Update `docs/research/agent-qualification-decomposition-sketch.md`: §3(c) and §5 say the
`weightedVolume` operand and `maxApprovalForScore` "still route through opaque `TApp`" and
list structural arithmetic as a remaining sibling. Rewrite to say arithmetic terms are
**delivered by EP-43**: a weighted sum written with `tadd`/`tmul` (or
`weightedVolume = tadd (tadd #listingVolume #buyerVolume) …`) is now solver-visible, and
`maxApprovalForScore`'s `* 1000` is a structural `tmul`. Note the remaining caveat is only
the per-slot memoization sibling (EP-42) if it has not yet landed; if both are done, state
that derived-quantity money thresholds are fully verifiable.

Update the guides (`docs/guide/why-smt.md`, `docs/guide/symbolic-ci.md`,
`docs/guide/loan-application-tutorial.md`): the curated-translation list and any
"thresholds over computed values are opaque" caveat now include `TArith`; the
loan-application tutorial's cap guard code block migrates to `tmul`.

Sweep for stale "no arithmetic in Term" / "arithmetic is opaque" claims
(`grep -rn "arithmetic" docs src jitsurei`); keep only those describing history (e.g. the
EP-41 plan, which references arithmetic as a then-future sibling).

Fill Outcomes & Retrospective.

Acceptance: docs read consistently; no stale "no structural arithmetic" claim remains
except as history.


## Concrete Steps

All commands run from `/Users/shinzui/Keikaku/bokuno/keiki`.

Baseline (M0):

    z3 --version
    cabal build all
    cabal test all

Iterate per milestone:

    cabal build all          # watch for -Wincomplete-patterns after M1
    cabal test all

Focus suites while iterating:

    cabal test keiki-test                                    # Keiki.SymbolicSpec
    cabal test jitsurei-test --test-options=--match=/LoanApplication/
    cabal test all --test-options=--match=/Symbolic/

Expected transcript shape after M2 (illustrative):

    Keiki.SymbolicSpec
      structural arithmetic (EP-43)
        constant 2 + 3 > 10 is symIsBot [✔]
        symSatExt witness respects #a + #b >= 10 [✔]
        symSatExt witness respects #req <= #score * 1000 [✔]
        evalPred over tadd/tsub/tmul matches Haskell [✔]

Commit after each milestone with the MasterPlan, ExecPlan, and Intention trailers:

    git add -A
    git commit -m "feat(core): EP-43 M1 — structural arithmetic Term (NumOp/TArith) + walkers

    <body>

    MasterPlan: docs/masterplans/12-symbolic-arithmetic-terms-translator-memoization-and-real-boolalg-sat-witnesses.md
    ExecPlan: docs/plans/43-structural-arithmetic-terms-in-the-keiki-term-language.md
    Intention: intention_01ks3939thethvf26jkpx3ksht"


## Validation and Acceptance

The plan is complete when, from `/Users/shinzui/Keikaku/bokuno/keiki`:

1. `cabal build all` succeeds and is clean under `-Wincomplete-patterns` (every total
   `Term` walker has a `TArith` arm).

2. `cabal test all` passes with no failures. The pending count is unchanged if EP-42 is
   not yet complete (LoanApplication single-valuedness gate stays pending with an
   EP-42-only reason), or drops by one if EP-42 is complete (the gate un-pends).

3. New, observable behavior (each asserted by a test that fails before the relevant
   milestone):
   - A constant arithmetic ordering contradiction `lit 2 + lit 3 > lit 10` is
     `symIsBot == True`.
   - `symSatExt` over `#a + #b >= lit 10` yields a witness with `a + b >= 10`.
   - `symSatExt` over `#req <= #score * lit 1000` yields a witness with
     `req <= score * 1000`.
   - `Jitsurei.LoanApplication`'s cap conjunct is structural `tmul`, all LoanApplication
     behavioural and builder-equivalence specs stay green, and (iff EP-42 is complete)
     `isSingleValuedSym (withSymPred loanApplication) == True`.

4. `evalTerm`/`evalPred` agree with Haskell arithmetic for each `NumOp` (a property or
   example test), so runtime behavior of arithmetic terms matches the `TApp` form they
   replace.


## Idempotence and Recovery

M1 is a pure addition (new constructor, new arms, new smart constructors); re-applying it
is a no-op if already present. M2 is additive (`discoverSymNum`, one real translator arm
replacing the M1 placeholder). The only non-additive edit is the M3 LoanApplication cap
migration, which is behavior-preserving and fully covered by the LoanApplication
behavioural/builder specs — a regression shows up immediately as a failing spec; to
recover, revert the cap expression to `TApp1 maxApprovalForScore (proj #appCreditScore)`.
The single-valuedness un-pend is reversible by restoring the `pendingWith` block.
`cabal build all`/`cabal test all` are safe to re-run. If z3 is missing, symbolic specs
fail loudly; install z3 (`brew install z3` / `apt install z3`). Each milestone is
committed separately, so `git revert` of a milestone commit cleanly backs it out.


## Interfaces and Dependencies

Libraries: `sbv` (already a dependency) for `SBV`, `Symbolic`, `SymVal`, and the `Num`
instance on `SBV.SBV Integer`; `base` for `Num`/`Typeable`. The z3 solver on `PATH` at
test time. No new dependencies.

Types/signatures that must exist at the end:

In `Keiki.Core` (exported):

    data NumOp = OpAdd | OpSub | OpMul
    TArith :: (Num r, Typeable r) => NumOp -> Term rs ci r -> Term rs ci r -> Term rs ci r
    tadd, tsub, tmul :: (Num r, Typeable r) => Term rs ci r -> Term rs ci r -> Term rs ci r
    -- plus the evalTerm arm and arms in solveOutput/checkHiddenInputs/termReadsInput/etc.

In `Keiki.Symbolic` (exported):

    data SymNumDict r where SymNumDict :: (Sym r, Num (SBV.SBV (SymRep r))) => SymNumDict r
    discoverSymNum :: forall r. Typeable r => Maybe (SymNumDict r)
    -- translateTermSym extended with the TArith arm

In `Keiki.Composition` / `Keiki.Profunctor`: `TArith` arms in `weakenLTerm`,
`weakenRTerm`, `substTerm`, `liftLTermAlt`, `liftRTermAlt`, and the two `go` walkers
(internal; not exported).

Backward compatibility: all additions are additive except the cap migration in M3
(behavior-preserving, spec-guarded). Existing aggregates compile unchanged; the new
`Term` constructor only obliges the total walkers to add an arm, which this plan does.

Relationship to sibling plans (see the MasterPlan's Dependency Graph and Integration
Points):

- `docs/plans/42-per-slot-and-per-input-field-memoization-in-the-symbolic-translator.md`
  (memoization): EP-43's `TArith` translation reads sub-terms via `translateTermSym env`,
  so it automatically benefits from memoization once EP-42 lands. The M3 integration
  capstone (un-pending `LoanApplicationSymbolicSpec`'s single-valuedness gate)
  **hard-requires EP-42**: structural arithmetic removes the cap's opaque term, and EP-42
  shares the repeated `#appCreditScore` reads — both are needed for the self-mutex to be
  unsatisfiable.
- `docs/plans/44-real-witnesses-from-boolalg-sat-retire-the-placeholder-witness.md`
  (real `BoolAlg.sat` witnesses): independent of this plan. A `sat` witness over a guard
  containing structural arithmetic is faithful once both EP-44 and (for repeated reads)
  EP-42 land; no coordination beyond that.
