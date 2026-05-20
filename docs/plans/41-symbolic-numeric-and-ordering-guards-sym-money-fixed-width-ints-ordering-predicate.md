---
id: 41
slug: symbolic-numeric-and-ordering-guards-sym-money-fixed-width-ints-ordering-predicate
title: "Symbolic numeric and ordering guards (Sym money, fixed-width ints, ordering predicate)"
kind: exec-plan
created_at: 2026-05-20T18:07:18Z
intention: "intention_01ks3939thethvf26jkpx3ksht"
---

# Symbolic numeric and ordering guards (Sym money, fixed-width ints, ordering predicate)

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

keiki can prove things about an aggregate's guards at build time — that no two
edges out of a vertex fire at once ("single-valuedness"), that a vertex is
reachable, that a guard is satisfiable — by translating the guard predicate to
the z3 SMT solver. Today that proving power only covers a narrow set of guard
shapes: equality (`PEq`), input-constructor match (`PInCtor`), and Boolean
combinations of those, over a small set of value types (`Bool`, `Int`,
`Integer`, `Text`, `UTCTime`). Two everyday guard shapes fall outside it and
become invisible to the solver:

1. Guards over **money and fixed-width integer registers**. keiki's own shipped
   example aggregate `Jitsurei.OrderCart` stores `itemCount :: Word32`,
   `quantity :: Word16`, and `Money = Word64` (cents), yet none of `Word16`,
   `Word32`, `Word64` are in the solver's type registry, so an equality guard
   over any of them translates to a fresh, unconstrained Boolean the solver
   learns nothing from.

2. **Ordering guards** — "amount ≥ threshold", "count < limit". keiki's
   predicate language has no comparison constructor at all, so every threshold
   is written by wrapping a Haskell comparison in an opaque function term
   (`TApp1 (>= n)`), which the solver also cannot see. `Jitsurei.LoanApplication`
   does exactly this for `creditScore >= 650`, and its symbolic test
   (`jitsurei/test/Jitsurei/LoanApplicationSymbolicSpec.hs`) is marked *pending*
   with a comment that says the fix is "extend `HsPred` with a comparison
   constructor."

After this change, a keiki author can write money and fixed-width-integer
equality guards and `<`, `≤`, `>`, `≥` ordering guards, and the solver will
reason about them for real. Concretely, after implementation you will be able to
run the test suite and observe: a guard that is a *constant* ordering
contradiction (for example `lit 5 ≥ lit 10` over money) is reported **empty**
(`symIsBot` returns `True`) where today it is reported satisfiable; a money
equality guard yields a **concrete witness** whose money slot satisfies the
guard (`symSatExt`); and an ordering guard such as `amount ≥ 1000` yields a
witness whose `amount` is actually `≥ 1000` rather than an unconstrained default.

This plan does **not** make every threshold guard fully precise on its own. Two
named follow-on gaps remain out of scope and are documented below: structural
arithmetic in the term language (so a guard over a *computed* value such as a
weighted sum is visible) and per-slot memoization in the translator (so two
reads of the *same* register share one solver variable). Those are separate
ExecPlans; see "Interfaces and Dependencies" → "Sibling follow-ons".


## Progress

- [x] M0 — Baseline (2026-05-20): build green (`cabal build all`), full suite
      green (`cabal test all`): keiki-test 201 examples / 0 failures, jitsurei-test
      88 examples / 0 failures / 1 pending (`LoanApplicationSymbolicSpec`),
      keiki-codec-json-test 40 examples / 0 failures (329 total, 1 pending).
      z3 4.15.8 on PATH. Opaque translation sites enumerated:
      `src/Keiki/Symbolic.hs:246` (`SBV.free "app1"`), `:247` (`"app2"`),
      `:287` (`"neq"` fallback in `goEq`). Threshold `TApp` sites:
      `jitsurei/src/Jitsurei/LoanApplication.hs:394,397,400,408` (`TApp1 (>= n)`)
      and `:414` (`TApp2 (<=)`). `Word*` register/field types in
      `jitsurei/src/Jitsurei/OrderCart.hs`: `DiscountBp = Word16`,
      `ItemQuantity = Word16`, `Money = Word64`, `ItemCount = Word32`
      (register slots `discountBp :: Word16`, `itemCount :: Word32`,
      `amountPaid :: Word64`).
- [x] M1 — Numeric `Sym` registry (2026-05-20): added `Sym` instances for
      `Word64`, `Word32`, `Word16`, `Word8`, `Int64`, `Int32` (each
      `SymRep = Integer`, `toSym`/`fromSym = fromIntegral`, with the
      over-approximation haddock note) in `src/Keiki/Symbolic.hs`; extended
      `discoverSym` with one guard per type; updated the module-header and
      `discoverSym` haddock. `ExtractRegFile`/`symSatExt`/`readModel` needed no
      shape change — the new instances make `Word*` slots automatically
      extractable. Added `Keiki.SymbolicSpec` blocks: six `discoverSym` registry
      assertions and a "numeric Sym registry (EP-41 M1)" block (Word64/Word32
      `isBot` solver-visibility, an `isSingleValuedSym` fixture flipping
      False→True on a now-visible constant `Word64` contradiction, and a
      `symSatExt` Word64 single-read witness round-trip). keiki-test: 212
      examples, 0 failures (was 201). Note: the originally-proposed two-reads-of-
      one-slot `isSingleValuedSym` form is unattainable without the memoization
      sibling (see Surprises / Decision Log 2026-05-20); the memoization-free
      proofs above replace it.
- [x] M2 — Ordering predicate (2026-05-20): added `data Cmp = CmpLt | CmpLe |
      CmpGt | CmpGe` and `PCmp :: (Ord r, Typeable r) => Cmp -> Term rs ci r ->
      Term rs ci r -> HsPred rs ci` to `Keiki.Core` (exported `Cmp(..)`; `PCmp`
      via `HsPred(..)`), with the `evalPred` arm. Added the `PCmp` arm to every
      total `HsPred` walker found by grep so the build stays
      `-Wincomplete-patterns`-clean: `Keiki.Profunctor` (`contraPred`,
      `contraMaybePred`), `Keiki.Composition` (`weakenLPred`, `weakenRPred`,
      `substPred`, `liftLPredAlt`, `liftRPredAlt`), `Keiki.Render.Mermaid`
      (`edgeInputName`'s `walk` → `Nothing`). Added `SymOrdDict` + `discoverSymOrd`
      and the `goCmp` arm of `translatePred` in `Keiki.Symbolic` (opaque
      `SBV.free "cmp"` fallback for non-orderable operand types). Added
      `requireCmp`/`requireLt`/`requireLe`/`requireGt`/`requireGe` and re-exported
      `Cmp(..)` from `Keiki.Builder`. Added a "ordering predicate PCmp (EP-41 M2)"
      block to `Keiki.SymbolicSpec`: constant `5 >= 10` over `Word64` is
      `symIsBot`, `10 >= 5` is not, a `symSatExt` witness with `amount >= 1000`,
      and `evalPred` agreement with Haskell's `<`/`<=`/`>`/`>=` over all
      directions. keiki-test: 216 examples, 0 failures; full suite green (351
      examples, 1 pending).
- [x] M3 — Dogfood (2026-05-20): added
      `jitsurei/test/Jitsurei/OrderCartSymbolicSpec.hs` (registered in
      `jitsurei.cabal` and `jitsurei/test/Spec.hs`): `isSingleValuedSym
      (withSymPred orderCart) == True`, constant `Money`/`Word64` ordering and
      equality contradictions are `symIsBot`, and a `symSatExt` ConfirmPayment
      witness with `amountPaid >= 1000`. Added a `KnownInCtors OrderCmd` instance
      to `Jitsurei.OrderCart` (the EP-22 "no symbolic instance" comment is now
      stale — updated) so witness reconstruction works; all input-field types are
      `Sym` after M1. Migrated `Jitsurei.LoanApplication`'s `readyForReviewGuard`
      and `approvalGuard` from `PEq (TApp1 (>= n) …) (lit True)` / `TApp2 (<=)` to
      `PCmp` (behaviour-preserving — `evalPred` identical by construction). The
      cap conjunct keeps a `TApp1 maxApprovalForScore` on its RHS (arithmetic
      sibling). Updated `LoanApplicationSymbolicSpec`: the self-mutex retrospective
      gate stays pending but its reason now names only the memoization sibling
      (the comparison-constructor half is done), and a new memoization-free
      assertion shows the approval edge guard's `symSatExt` witness has
      `appCreditScore >= approvalThresholdScore` (unconstrained before M3). All
      LoanApplication behavioural + builder-equivalence specs stay green.
      jitsurei-test: 94 examples, 0 failures, 1 pending (was 88/1); full suite 357
      examples, 1 pending.
- [ ] M4 — Docs + close: update `docs/research/sbv-boolalg-design.md`, the money
      note in `docs/research/agent-qualification-decomposition-sketch.md` (§3a/§5),
      and `docs/guide/symbolic-ci.md` if needed; fill Outcomes & Retrospective.


## Surprises & Discoveries

- M0 (2026-05-20): `Jitsurei.LoanApplication` models money and credit score as
  `type Money = Int` / `appCreditScore :: Int` (not `Word64`), so its threshold
  guards are already over a registered `Sym` type (`Sym Int`). The plan's
  Purpose paragraph and Decision Log frame "symbolic money" via `Word64`; that
  applies to `Jitsurei.OrderCart` (`Money = Word64`), which is the aggregate that
  actually needs the new numeric instances. The LoanApplication M3 migration to
  `PCmp` therefore works against `Int` operands using the pre-existing `Sym Int`
  instance plus the new `discoverSymOrd` `Int` arm; no `Word64` is involved on
  the LoanApplication side. Net effect on the plan: unchanged — both numeric and
  ordering work is still required, just split across the two aggregates as the
  plan already anticipates.
- M0 (2026-05-20): baseline total is 329 examples (1 pending), not the ~336 the
  plan estimated; the estimate predated some spec churn. The only pending spec is
  `LoanApplicationSymbolicSpec`, as expected.

- M1 (2026-05-20): **SBV's `free` does not alias repeated names.** The plan's M1
  acceptance proposed proving two edges guarded by `PEq #amount (lit 0)` and
  `PEq #amount (lit 1)` single-valued, on the parenthetical reasoning that "each
  guard reads `amount` once". That reasoning is wrong: `isSingleValuedSym` checks
  `isBot (guard e1 ∧ guard e2)`, which conjoins the two guards into one predicate
  containing *two* reads of `#amount`. `translateTermSym` allocates a fresh SBV
  variable per `TReg` occurrence (`SBV.free "reg/amount"` each time), and SBV
  does **not** unify two `free` calls that share a name — it creates independent
  variables. Empirically (z3 4.15.8, sbv 14.1):

        cabal repl keiki -v0
        > r <- SBV.sat (do x <- SBV.free "reg/amount" :: SBV.Symbolic (SBV.SBV Integer)
        >                  y <- SBV.free "reg/amount" :: SBV.Symbolic (SBV.SBV Integer)
        >                  pure ((x SBV..== 0) SBV..&& (y SBV..== 1)))
        > SBV.modelExists r
        two-reads-same-name SAT (True=>independent): True

  So `(reg/amount == 0) ∧ (reg/amount == 1)` is reported **satisfiable**, hence
  `isSingleValuedSym` over those two guards answers `False` regardless of this
  plan's numeric work. Proving it `True` is exactly the deferred *memoization
  sibling*'s job (share one SBV variable per slot). This plan's numeric
  contribution is proven memoization-free instead; see the Decision Log entry
  dated 2026-05-20 ("M1 acceptance revised").


## Decision Log

- Decision: In keiki, "symbolic money" means `Sym Word64`, not `Sym Scientific`.
  Rationale: keiki's own convention (`Jitsurei.OrderCart`,
  `jitsurei/src/Jitsurei/OrderCart.hs:120`) models money as `Money = Word64`
  fixed-point minor units (cents). Adding symbolic support for the fixed-width
  integer types therefore covers money for free. Raw `Data.Scientific` and SBV's
  real (`SReal`/`AlgReal`) theory are explicitly out of scope: they are
  unnecessary given the convention, the `Scientific`↔`AlgReal` round-trip has
  scale subtleties, and real arithmetic is heavier in z3 than integer
  arithmetic. The motivating external decider (`mls-service-v2`
  `AgentQualificationDecider`) uses raw `Scientific`, but a keiki port would
  adopt the `Word64`-cents convention (this reconciles
  `docs/research/agent-qualification-decomposition-sketch.md`, which placeholdered
  `Money = Scientific`).
  Date: 2026-05-20

- Decision: The fixed-width integer `Sym` representation is `SymRep = Integer`
  (mathematical, unbounded), mirroring the existing `Sym Int` instance
  (`src/Keiki/Symbolic.hs:116-120`). Rationale: SBV's `SInteger` is well
  supported and `OrdSymbolic`, and the existing `Int` instance already takes this
  approach. The known caveat — modular/overflow wraparound of the Haskell `Word*`
  type is not modeled (an over-approximation: sound for satisfiability, may miss
  unsatisfiability that depends on overflow) — is acceptable and is documented in
  the instance haddock, exactly as the `Int` instance documents it.
  Date: 2026-05-20

- Decision: The ordering predicate is a single constructor
  `PCmp :: (Ord r, Typeable r) => Cmp -> Term rs ci r -> Term rs ci r ->
  HsPred rs ci` carrying a four-way relation `data Cmp = CmpLt | CmpLe | CmpGt |
  CmpGe`, rather than four separate `HsPred` constructors. Rationale: one
  constructor means one `evalPred` arm and one `translatePred` arm (each
  switching on `Cmp`), matching the compact style of the existing predicate code;
  the four directions are recovered by builder conveniences (`requireLt`/`Le`/
  `Gt`/`Ge`). Equality is left to the existing `PEq` (so `Cmp` deliberately omits
  an "equal" case).
  Date: 2026-05-20

- Decision: Symbolic translation of `PCmp` is gated by a new `discoverSymOrd`
  companion to `discoverSym` that yields evidence the operand type's `SymRep` is
  `OrdSymbolic`. Types whose `SymRep` is not symbolically ordered (or that are
  not in the registry at all) fall back to a fresh opaque Boolean, exactly as
  `goEq` already falls back for non-`Sym` operands (`src/Keiki/Symbolic.hs:286-291`).
  Rationale: keeps the change sound by construction and additive; never claims a
  guarantee it cannot back.
  Date: 2026-05-20

- Decision: M1 acceptance revised. The plan's original M1/Validation bullet —
  "two edges guarded by `PEq #slot (lit 0)` and `PEq #slot (lit 1)` are proven
  single-valued (`isSingleValuedSym == True`)" — is unattainable without the
  deferred memoization sibling (see the matching Surprises entry: SBV does not
  alias repeated `free` names, so the conjoined guards' two reads of the same
  slot become independent variables). What this plan *can* and *does* prove,
  memoization-free, that the same slot read once per predicate is now solver-
  visible:
  (a) Direct contradiction on Word/fixed-width literals:
  `isBot (SymPred (PEq (TLit (5 :: Word64)) (TLit 6))) == True` (and the same for
  `Word32`). Before M1 this was `False` because `discoverSym @Word64` missed and
  `goEq` emitted an opaque `SBV.free "neq"`; after M1 it is real SBV integer
  equality. This is the crisp solver-visibility proof.
  (b) An `isSingleValuedSym` fixture over a transducer that *carries* a `Word64`
  register, whose two outgoing edges are made mutually exclusive by a now-visible
  constant `Word64` equality (`PEq (lit 5) (lit 6)`, always false) on one edge —
  so the verdict flips from `False` (pre-M1, opaque) to `True` (post-M1). Each
  guard reads the register at most once, so no memoization is needed.
  (c) A `symSatExt` round-trip over a single read of a `Word64` slot
  (`PAnd (PInCtor inCtorAmtTick) (PEq #amount (lit 7))`) whose witness has
  `amount == 7`. The `PInCtor` conjunct pins the input constructor so witness
  reconstruction (`pickCi`) succeeds; the single `#amount` read is memoization-
  safe.
  Rationale: keep the milestone's observable, before/after-falsifiable proofs
  while staying honest about the memoization boundary the plan already draws.
  Date: 2026-05-20

- Decision: Scope excludes (a) structural arithmetic `Term` constructors and
  (b) per-slot/per-field memoization in the translator, both recorded as named
  sibling ExecPlans. Rationale: the user scoped this plan to "numeric +
  ordering". These two are real and related but independently shippable; see
  "Interfaces and Dependencies → Sibling follow-ons" for why each matters and
  what it would unblock (notably, un-pending `LoanApplicationSymbolicSpec`
  requires the memoization sibling in addition to this plan's ordering
  predicate).
  Date: 2026-05-20


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

This section assumes no prior knowledge of keiki. Read it before editing.

keiki is a Haskell library (the package at the repository root, `keiki.cabal`,
module prefix `Keiki.*`) for the pure core of event sourcing. An aggregate is
modeled as a `SymTransducer` — a finite control graph (vertices) plus a typed
register file (named, typed mutable slots) where each edge has a *guard*
(a predicate that must hold for the edge to fire), an *update* (how it writes
registers), an *output* (the events it emits), and a *target* vertex. The
example aggregates live in the sibling package `jitsurei`
(`jitsurei/src/Jitsurei/*.hs`); `cabal.project` lists the packages: `.` (keiki),
`jitsurei`, `keiki-codec-json`, `keiki-codec-json-test`.

The pieces this plan touches:

The predicate language is `HsPred`, defined in `src/Keiki/Core.hs` around
line 400:

    data HsPred (rs :: [Slot]) (ci :: Type) where
      PTop    :: HsPred rs ci
      PBot    :: HsPred rs ci
      PAnd    :: HsPred rs ci -> HsPred rs ci -> HsPred rs ci
      POr     :: HsPred rs ci -> HsPred rs ci -> HsPred rs ci
      PNot    :: HsPred rs ci -> HsPred rs ci
      PEq     :: (Eq r, Typeable r) => Term rs ci r -> Term rs ci r -> HsPred rs ci
      PInCtor :: InCtor ci ifs -> HsPred rs ci

There is no comparison/ordering constructor. `rs` is the register-file slot list
(`Slot = (Symbol, Type)`); `ci` is the input/command type. A `Term rs ci r` is a
pure expression producing an `r`; its constructors are `TLit` (a literal),
`TReg` (read a register), `TInpCtorField` (read a field of the input command),
and `TApp1`/`TApp2` (apply a one- or two-argument Haskell function to
sub-terms). `TApp1`/`TApp2` are the escape hatch: arbitrary Haskell, opaque to
analysis.

`evalPred :: HsPred rs ci -> RegFile rs -> ci -> Bool`
(`src/Keiki/Core.hs`, around line 572) is the concrete evaluator — it actually
runs the predicate on a concrete register file and command. Every new `HsPred`
constructor needs an arm here.

The symbolic surface is `src/Keiki/Symbolic.hs`. Key parts:

- `class Sym a` with associated type `SymRep a` and methods `toSym :: a ->
  SymRep a`, `fromSym :: SymRep a -> a`, `symDefault :: a`. `SymRep a` is the
  SBV-friendly representation (must be an instance of SBV's `SymVal`). Existing
  instances: `Bool` (as `Bool`), `Integer` (as `Integer`), `Int` (as `Integer`),
  `Text` (as `String`), `UTCTime` (as `Integer`). These are the only value types
  the solver understands.

- `discoverSym :: forall r. Typeable r => Maybe (SymDict r)`
  (`src/Keiki/Symbolic.hs:154-161`) — a runtime lookup from a `Typeable` value
  type to its `Sym` instance, by comparing type representations against the
  curated list. A miss returns `Nothing`. This is the registry: a type not
  listed here is invisible to the solver.

- `translateTermSym` (around line 236) turns a `Term` into an SBV expression;
  `TApp1`/`TApp2` translate to `SBV.free "app1"`/`"app2"` — fresh, unconstrained
  variables.

- `translatePred` (around line 271) turns an `HsPred` into an SBV `SBool`. The
  `PEq` arm (`goEq`, around line 284) tries `discoverSym` on the operand type; on
  a hit it emits `translatedA .== translatedB`; on a miss it emits
  `SBV.free "neq"` (opaque). Every new `HsPred` constructor needs an arm here.

- `symSat`, `symIsBot`, `symSatExt`, `isSingleValuedSym` — the analyses. `symSat`
  asks z3 for a model; `symIsBot` asks whether no model exists; `symSatExt`
  extracts a concrete witness `(RegFile rs, ci)` from the model via
  `ExtractRegFile` (which materializes a register file by reading each slot's
  model value through `readModel`, falling back to `symDefault`). A value type
  that is not `Sym` cannot be a witness slot.

- `isSingleValuedSym` checks, for each vertex, that every pair of outgoing edge
  guards is jointly `isBot` (unsatisfiable together).

The symbolic analyses require the **z3** SMT solver on `PATH` at runtime
(`keiki.cabal:47-52`: install via `brew install z3` on macOS or `apt install z3`
on Debian). The pure evaluator (`evalPred`) and everything else do not need z3.

Why the gap matters, with the live evidence:

`jitsurei/src/Jitsurei/LoanApplication.hs` writes its threshold guards as, e.g.,
`PEq (TApp1 (>= 650) (proj #appCreditScore)) (lit True)`
(`jitsurei/src/Jitsurei/LoanApplication.hs:400,408`). The `TApp1 (>= 650)` is
opaque. `jitsurei/test/Jitsurei/LoanApplicationSymbolicSpec.hs` is therefore
`pendingWith` a message that states the fix is a memoising translator "or extend
`HsPred` with a comparison constructor". `Jitsurei.OrderCart` stores money and
counts as `Word64`/`Word32`/`Word16` and has *no* symbolic spec at all — the
numeric gap there is latent.

The keiki test-suite is `keiki-test` (`keiki.cabal:80`, `exitcode-stdio-1.0`,
`main-is: Spec.hs`), with symbolic unit tests in module `Keiki.SymbolicSpec`
(`keiki.cabal:108`). `jitsurei` has its own hspec suite containing
`Jitsurei.LoanApplicationSymbolicSpec` and `Jitsurei.UserRegistrationSymbolicSpec`.


## Plan of Work

The work proceeds in five milestones (M0–M4). Each is independently verifiable.
All edits are additive except the LoanApplication guard migration in M3, which is
behavior-preserving and guarded by the existing LoanApplication specs.

### M0 — Baseline

Goal: a known-good starting point and an exact inventory of what this plan
closes. Confirm z3 is present, build everything, run the full suite, and record
the example counts. Then grep for the opaque sites so the later milestones have
concrete targets.

What exists at the end: a recorded baseline (counts + the opaque-site list) in
the Progress and Surprises sections. No code change.

Commands (working directory `/Users/shinzui/Keikaku/bokuno/keiki`):

    z3 --version
    cabal build all
    cabal test all

Record the total examples/pending reported (the project was last at 336 examples
with 1 pending; confirm the current numbers). Then:

    grep -n "SBV.free \"app" src/Keiki/Symbolic.hs
    grep -rn "TApp1 (>=" jitsurei/src/Jitsurei
    grep -rn "Word16\|Word32\|Word64" jitsurei/src/Jitsurei

Acceptance: build and tests pass; the `LoanApplicationSymbolicSpec` shows as
pending (not failing); the grep output enumerates the threshold/`TApp` sites and
the `Word*` register types.

### M1 — Numeric `Sym` registry (money + fixed-width ints)

Goal: make money and fixed-width-integer register/`PEq` values solver-visible.

In `src/Keiki/Symbolic.hs`, add `Sym` instances next to the existing ones (after
the `Sym Int` instance at line 116), each with `SymRep = Integer`,
`toSym = fromIntegral`, `fromSym = fromIntegral`, `symDefault = 0`, and a haddock
line noting the unbounded-`Integer` over-approximation (copy the wording from the
`Int` instance):

    instance Sym Word16 where { type SymRep Word16 = Integer; toSym = fromIntegral; fromSym = fromIntegral; symDefault = 0 }
    instance Sym Word32 where { type SymRep Word32 = Integer; … }
    instance Sym Word64 where { type SymRep Word64 = Integer; … }
    instance Sym Int32  where { … }
    instance Sym Int64  where { … }
    instance Sym Word8  where { … }

(`Word16/32/64` are required — they are used by `OrderCart`, including
`Money = Word64`. `Int32/Int64/Word8` are added for completeness; include only
those that compile cleanly with the imports.) Add the imports
(`Data.Word (Word8, Word16, Word32, Word64)`, `Data.Int (Int32, Int64)`).

Extend `discoverSym` (line 154) with one guard per new type:

    | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Word16) = Just SymDict
    | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Word32) = Just SymDict
    | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Word64) = Just SymDict
    -- …and the rest

`ExtractRegFile`/`symSatExt`/`readModel` need no change in shape: they already
work for any `Sym` slot via the `Sym t` instance constraint on the `RCons`
instance (`src/Keiki/Symbolic.hs:451-458`). The new instances make `Word*`
registers automatically extractable.

What exists at the end: equality guards over `Word16/32/64` translate to real
SBV integer terms; witnesses round-trip `Word*` slots.

Add to `Keiki.SymbolicSpec` (the keiki-side unit suite) a small fixture
transducer with a `Word64` "amount" register and two edges whose guards are
`PEq #amount (lit 0)` and `PEq #amount (lit 1)`, and assert
`isSingleValuedSym (withSymPred t)` is `True` (the two equalities are mutually
exclusive — and this works without memoization because each guard reads `amount`
once). Also assert `symSatExt` on `PEq #amount (lit 7)` returns a witness whose
`amount` is `7`.

Acceptance: `cabal test all` passes including the new specs; the `Word64`
single-valuedness assertion is `True` (it would be `False`/opaque before this
milestone).

### M2 — Ordering predicate (`PCmp`)

Goal: a first-class comparison guard that the solver sees.

In `src/Keiki/Core.hs`: add, near `HsPred`,

    data Cmp = CmpLt | CmpLe | CmpGt | CmpGe
      deriving stock (Eq, Show)

and a constructor on `HsPred`:

    PCmp :: (Ord r, Typeable r) => Cmp -> Term rs ci r -> Term rs ci r -> HsPred rs ci

Export `Cmp(..)` and `PCmp` from the module's export list. Add the `evalPred`
arm:

    evalPred (PCmp op a b) r c = applyCmp op (evalTerm a r c) (evalTerm b r c)
      where
        applyCmp CmpLt x y = x <  y
        applyCmp CmpLe x y = x <= y
        applyCmp CmpGt x y = x >  y
        applyCmp CmpGe x y = x >= y

In `src/Keiki/Symbolic.hs`: add a `discoverSymOrd` companion to `discoverSym`
that, for orderable representation types, yields evidence of both `Sym r` and
`OrdSymbolic (SBV (SymRep r))`:

    data SymOrdDict r where
      SymOrdDict :: (Sym r, SBV.OrdSymbolic (SBV.SBV (SymRep r))) => SymOrdDict r

    discoverSymOrd :: forall r. Typeable r => Maybe (SymOrdDict r)
    discoverSymOrd
      | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Int)     = Just SymOrdDict
      | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Integer) = Just SymOrdDict
      | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Word16)  = Just SymOrdDict
      | …  -- Word32, Word64, Int32, Int64, Word8, UTCTime (all SymRep Integer, OrdSymbolic)
      | otherwise = Nothing

(Deliberately omit `Bool`/`Text`: `Bool` ordering is not a meaningful guard and
`SString` ordering is out of scope here.) Add the `translatePred` arm:

    go (PCmp op a b) = goCmp op a b

    goCmp :: forall r. Typeable r => Cmp -> Term rs ci r -> Term rs ci r -> SBV.Symbolic SBV.SBool
    goCmp op a b = case discoverSymOrd @r of
      Nothing         -> SBV.free "cmp"          -- sound opaque fallback
      Just SymOrdDict -> do
        sa <- translateTermSym env a
        sb <- translateTermSym env b
        pure (applySymCmp op sa sb)
      where
        applySymCmp CmpLt = (SBV..<)
        applySymCmp CmpLe = (SBV..<=)
        applySymCmp CmpGt = (SBV..>)
        applySymCmp CmpGe = (SBV..>=)

In `src/Keiki/Builder.hs`, next to `requireEq` (line 483), add builder verbs:

    requireCmp :: (Ord r, Typeable r) => Cmp -> Term rs ci r -> Term rs ci r -> EdgeBuilder rs ci co v w w ()
    requireCmp op a b = requireGuard (PCmp op a b)

    requireLt, requireLe, requireGt, requireGe
      :: (Ord r, Typeable r) => Term rs ci r -> Term rs ci r -> EdgeBuilder rs ci co v w w ()
    requireLt = requireCmp CmpLt
    requireLe = requireCmp CmpLe
    requireGt = requireCmp CmpGt
    requireGe = requireCmp CmpGe

Re-export `Cmp(..)`, `PCmp`, and the verbs as appropriate (Builder re-exports the
authoring surface).

What exists at the end: authors can write `requireGe #amount (lit 1000)`, and
the solver reasons about it.

Add to `Keiki.SymbolicSpec`:

- `symIsBot` on a *constant* contradiction over money is `True`:
  `PAnd (PCmp CmpGe (lit (5::Word64)) (lit 10)) PTop` — i.e. `5 ≥ 10` — must be
  `symIsBot == True`. (Before M2 this guard could only be written via `TApp` and
  would be `symIsBot == False`.)
- `symSatExt` on `PCmp CmpGe #amount (lit (1000::Word64))` returns a witness
  whose `amount ≥ 1000`.
- Backward-compatibility: all existing `Keiki.SymbolicSpec` assertions still
  pass; `evalPred` of each `PCmp` direction matches Haskell's `compare`.

Acceptance: `cabal test all` passes including the new specs; the constant
contradiction is detected empty.

### M3 — Dogfood on real aggregates

Goal: prove the feature on shipped aggregates, not just fixtures.

First, add `jitsurei/test/Jitsurei/OrderCartSymbolicSpec.hs` (and list it in
`jitsurei`'s cabal test stanza): assert `isSingleValuedSym (withSymPred
orderCart)` behaves correctly now that `Word32`/`Word64` guards are visible, and
add at least one `symSatExt`/`symIsBot` assertion over a `Word64` money slot.

Second, migrate `Jitsurei.LoanApplication`'s threshold guards from the
`PEq (TApp1 (>= n) (proj #slot)) (lit True)` form to `PCmp CmpGe (proj #slot)
(lit n)` (lines around 394–416). This removes a `TApp` escape and makes the
guards structural. Critically, **every existing LoanApplication behavioral spec
must stay green** — `evalPred (PCmp CmpGe …)` must agree with the old
`TApp1 (>= n)` on all inputs (it does, by construction). Run the LoanApplication
specs before and after to show equivalence.

Honesty about the symbolic spec: `LoanApplicationSymbolicSpec` asserts the
*self-mutex* `approvalGuard ∧ ¬approvalGuard` is unsatisfiable. Even with `PCmp`,
that requires the two reads of `#appCreditScore` to share one solver variable,
which is the **memoization sibling** (out of scope here). So after M3, that spec
**remains pending**, but its pending reason is updated to point at the
memoization sibling alone (the comparison-constructor half is now done). Add a
*new* assertion that does not require shared-register memoization to demonstrate
the ordering win on LoanApplication — for example, that the approval edge guard
is satisfiable with a concrete witness whose credit score is `≥ 650`
(`symSatExt`), which today returns an unconstrained score.

What exists at the end: a real aggregate (OrderCart) with a passing symbolic
spec exercising numeric guards; LoanApplication thresholds expressed structurally
with all behavioral specs green and a sharpened pending reason on its symbolic
spec.

Acceptance: `cabal test all` passes; LoanApplication behavioral specs identical
before/after; the new OrderCart and LoanApplication ordering assertions pass.

### M4 — Documentation and close

Goal: leave the design record consistent.

Update `docs/research/sbv-boolalg-design.md` (the `Sym` registry section, lines
~182-186) to list the new numeric instances and the `PCmp`/`discoverSymOrd`
addition. Update `docs/research/agent-qualification-decomposition-sketch.md`
§3(a)/§5 to record that the money gap is closed via the `Word64`-cents
convention (not `Scientific`) and that the ordering gap is now in the verifiable
fragment, leaving arithmetic-terms and memoization as the remaining siblings.
Mention the new guard verbs in `docs/guide/symbolic-ci.md` and/or
`docs/guide/why-smt.md` if a one-line pointer fits. Fill Outcomes &
Retrospective. Commit.

Acceptance: docs build/read consistently; no stale "no comparison constructor"
claims remain except where explicitly describing history.


## Concrete Steps

All commands run from `/Users/shinzui/Keikaku/bokuno/keiki` unless noted.

Confirm the solver and baseline (M0):

    z3 --version
    cabal build all
    cabal test all

Expected: a passing run; note the totals (≈ "336 examples, 1 pending" or the
current equivalent). The 1 pending is `LoanApplicationSymbolicSpec`.

Iterate per milestone: edit the named files, then

    cabal build all
    cabal test all

To run a single suite while iterating:

    cabal test keiki-test                       # keiki unit suite (incl. Keiki.SymbolicSpec)
    cabal test all --test-options=--match=/Symbolic/   # focus symbolic specs across packages

Expected transcript shape after M1 (illustrative):

    Keiki.SymbolicSpec
      numeric registry
        Word64 equality guards are single-valued [✔]
        symSatExt round-trips a Word64 slot [✔]

Expected after M2:

    Keiki.SymbolicSpec
      ordering predicate
        constant contradiction 5 >= 10 is symIsBot [✔]
        symSatExt witness respects amount >= 1000 [✔]

Commit after each milestone with the trailer (and the Intention trailer, since
this session is linked):

    git add -A
    git commit -m "feat(symbolic): EP-41 M1 — numeric Sym registry (Word16/32/64)

    <body>

    ExecPlan: docs/plans/41-symbolic-numeric-and-ordering-guards-sym-money-fixed-width-ints-ordering-predicate.md
    Intention: intention_01ks3939thethvf26jkpx3ksht"


## Validation and Acceptance

The plan is complete when, from `/Users/shinzui/Keikaku/bokuno/keiki`:

1. `cabal build all` succeeds.

2. `cabal test all` passes with no failures. Pending count is unchanged or
   reduced; specifically `LoanApplicationSymbolicSpec` may remain pending but its
   reason now names only the memoization sibling.

3. New, observable behavior (each asserted by a test that would fail before the
   relevant milestone):
   - A `Word64`/`Word32` equality guard is solver-visible:
     `isBot (SymPred (PEq (TLit (5 :: Word64)) (TLit 6))) == True` (a real SBV
     integer contradiction; `False`/opaque before M1), and an
     `isSingleValuedSym` fixture over a `Word64`-register transducer whose two
     edges are separated by a now-visible constant `Word64` equality flips from
     `False` to `True`. (The originally-proposed two-reads-of-the-same-slot
     `isSingleValuedSym` form — `PEq #slot (lit 0)` ∧ `PEq #slot (lit 1)` —
     requires the deferred memoization sibling, because SBV does not alias the
     two `reg/<slot>` reads; see the Surprises and Decision Log entries dated
     2026-05-20.)
   - A constant ordering contradiction over money — `PCmp CmpGe (lit (5::Word64))
     (lit 10)` — is proven empty (`symIsBot p == True`).
   - An ordering guard yields a faithful witness:
     `symSatExt (PCmp CmpGe #amount (lit (1000::Word64)))` returns
     `Just (regs, _)` with `regs ! #amount >= 1000`.
   - `Jitsurei.OrderCart` has a passing symbolic spec exercising the above on a
     real aggregate.
   - `Jitsurei.LoanApplication`'s thresholds are expressed with `PCmp`, and all
     LoanApplication behavioral specs remain green.

4. `evalPred` agrees with Haskell semantics for every `Cmp` direction (a
   property or example test), so the runtime behavior of `PCmp` guards is
   unchanged from the `TApp` form they replace.


## Idempotence and Recovery

Every step is additive and re-runnable. The `Sym` instances and `discoverSym`
guards are pure additions; re-applying them is a no-op if already present.
`cabal build all` / `cabal test all` are safe to run repeatedly. The only
non-additive edit is the LoanApplication guard migration (M3); it is
behavior-preserving and fully covered by the existing LoanApplication specs, so a
regression shows up immediately as a failing spec. To recover, revert the
guard expressions to the `PEq (TApp1 (>= n) …) (lit True)` form — the rest of the
plan is independent of that migration. If z3 is missing, the symbolic specs fail
loudly with a solver-not-found error; install z3 (`brew install z3` /
`apt install z3`) and re-run. Each milestone is committed separately, so `git
revert` of a single milestone commit cleanly backs out that milestone.


## Interfaces and Dependencies

Libraries: `sbv` (already a dependency, `keiki.cabal:75,115`,
`sbv >= 11.7 && < 15`) for `SBV`, `OrdSymbolic` and its operators `(.<)`,
`(.<=)`, `(.>)`, `(.>=)`, and `SymVal`; the z3 solver on `PATH` at test time.
`base` for `Data.Word`/`Data.Int`. No new dependencies.

Types/signatures that must exist at the end:

In `Keiki.Core` (exported):

    data Cmp = CmpLt | CmpLe | CmpGt | CmpGe
    PCmp :: (Ord r, Typeable r) => Cmp -> Term rs ci r -> Term rs ci r -> HsPred rs ci
    -- plus the evalPred arm for PCmp

In `Keiki.Symbolic` (exported):

    instance Sym Word16   -- SymRep = Integer ; likewise Word32, Word64, Int32, Int64, Word8
    -- discoverSym extended to those types
    data SymOrdDict r where SymOrdDict :: (Sym r, SBV.OrdSymbolic (SBV.SBV (SymRep r))) => SymOrdDict r
    discoverSymOrd :: forall r. Typeable r => Maybe (SymOrdDict r)
    -- translatePred extended with the PCmp arm

In `Keiki.Builder` (exported):

    requireCmp :: (Ord r, Typeable r) => Cmp -> Term rs ci r -> Term rs ci r -> EdgeBuilder rs ci co v w w ()
    requireLt, requireLe, requireGt, requireGe
      :: (Ord r, Typeable r) => Term rs ci r -> Term rs ci r -> EdgeBuilder rs ci co v w w ()

Backward compatibility: all additions are additive. The new `HsPred`
constructor requires updating any *total* function that pattern-matches `HsPred`
exhaustively — at minimum `evalPred` (`Keiki.Core`) and `translatePred`
(`Keiki.Symbolic`); grep for other `HsPred` matches (for example any pretty/
shape/`NoThunks` walkers) and add the `PCmp` arm so the build stays warning-clean
under `-Wincomplete-patterns`. Existing aggregates compile unchanged.

### Sibling follow-ons (explicitly out of scope; record as future ExecPlans)

These were identified alongside this plan and are intentionally deferred:

- Structural arithmetic in `Term` (e.g. `TAdd`/`TSub`/`TMul` or a numeric term
  algebra). Without it, a guard over a *computed* value — a weighted sum such as
  `(listing + buyer) + 0.5*(colisting + cobuyer) ≥ minVolume` — still routes its
  operands through opaque `TApp`, so the comparison's left side is invisible even
  though `PCmp` itself is structural. Needed to make derived-quantity thresholds
  (the `mls-service` `AgentQualificationDecider` qualification rule) fully
  verifiable end-to-end.

- Per-slot/per-field memoization in the translator (`SymEnv` cache). Today
  `translateTermSym` allocates a fresh SBV variable per occurrence, so two reads
  of the same register (`#x .== #x`, or `approvalGuard ∧ ¬approvalGuard`) become
  independent variables and precision is lost; `symSatExt` witnesses can also be
  wrong for predicates with repeated reads. This is what additionally blocks
  un-pending `jitsurei/test/Jitsurei/LoanApplicationSymbolicSpec.hs`: this plan
  supplies the comparison constructor it asks for, the memoization sibling
  supplies the shared-variable half.

Out of scope and not planned here: `Double`/floating-point and SBV real
(`SReal`) support (money uses `Word64` minor units by convention); and
collection-content guards / quantifiers (`PMember`/`PAll`), which are the
separate collection-registers feature (`docs/research/collection-registers-design.md`).
