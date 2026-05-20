---
id: 44
slug: real-witnesses-from-boolalg-sat-retire-the-placeholder-witness
title: "Real witnesses from BoolAlg.sat (retire the placeholder witness)"
kind: exec-plan
created_at: 2026-05-20T18:50:57Z
intention: "intention_01ks3939thethvf26jkpx3ksht"
master_plan: "docs/masterplans/12-symbolic-arithmetic-terms-translator-memoization-and-real-boolalg-sat-witnesses.md"
---

# Real witnesses from BoolAlg.sat (retire the placeholder witness)

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

keiki models a guard carrier as a `BoolAlg` — an "effective Boolean algebra" typeclass
(`src/Keiki/Core.hs`, around line 444) with `top`, `bot`, `conj`, `disj`, `neg`, `models`,
`sat`, and `isBot`. The `sat` method's contract is "if this predicate is satisfiable,
return a witness `a` that satisfies it" (`sat :: phi -> Maybe a`). For the SBV-backed
guard wrapper `SymPred` (`src/Keiki/Symbolic.hs`), `sat` today returns a **placeholder
witness**: on a satisfiable predicate it returns `Just (unsafeWitness, unsafeWitness)`,
where `unsafeWitness` is a value that **crashes with an error message if you force it**.
The real witness is only available through a *separate* function, `symSatExt`, because the
`BoolAlg.sat` signature (`phi -> Maybe a`) cannot carry the extra constraints
(`ExtractRegFile`, `KnownInCtors`) that witness reconstruction needs.

The consequence is a sharp edge: `sat (SymPred p)` looks like it returns a witness, but
the witness is a landmine — `models (SymPred p) (fromJust (sat (SymPred p)))` crashes
instead of confirming the witness. Code and tests must remember to call `symSatExt`
instead, and the `BoolAlg` abstraction lies about what `sat` gives you.

After this change, `sat` on `SymPred` returns a **real** witness: a concrete
`(RegFile rs, ci)` reconstructed from the solver model, the same one `symSatExt` produces.
You will be able to write `case sat (SymPred p) of Just w -> models (SymPred p) w` and get
`True` (today this crashes when `w` is forced). The placeholder `unsafeWitness` and the
witness-free `symSat` wrapper are retired.

This is the smallest of the three sibling ExecPlans under MasterPlan 12
(`docs/masterplans/12-symbolic-arithmetic-terms-translator-memoization-and-real-boolalg-sat-witnesses.md`).
It soft-depends on the memoization sibling
(`docs/plans/42-per-slot-and-per-input-field-memoization-in-the-symbolic-translator.md`):
the witness `sat` returns is only correct for predicates with *repeated reads of the same
register/field* once memoization lands (without it, `symSatExt` — and therefore `sat` —
inherits the documented repeated-read caveat). It is independent of the arithmetic-terms
sibling (`docs/plans/43-structural-arithmetic-terms-in-the-keiki-term-language.md`).


## Progress

- [x] M0 — Baseline (2026-05-20): z3 4.15.8; build/test green at the EP-43-close baseline
      (keiki-test 229/0, jitsurei-test 94/0/0-pending, json 40/0 + 7/0). *Before* behavior
      confirmed in `cabal repl keiki` over a satisfiable `PEq (proj #x) (lit 0)`:
      `sat (SymPred p)` is `Just _`, but `models (SymPred p) w` (which forces the witness)
      throws the placeholder exception (transcript in Surprises). EP-42 is complete, so the
      soft-dependency caveat is moot — `sat` witnesses will be correct even for repeated
      reads.
- [ ] M1 — Real `sat` — **DEFERRED 2026-05-20** (user decision; see Decision Log and
      Surprises). The instance-head approach was prototyped and reverted: it does not
      compile against the existing test suite because the `BoolAlg (SymPred)` instance-head
      constraints `(ExtractRegFile rs, KnownInCtors ci)` ripple onto `isBot` /
      `isSingleValuedSym`, and `isSingleValuedSym` is exercised on `SomeSymTransducer` —
      an existential in `Keiki.Profunctor` that hides `rs` and carries no `ExtractRegFile`
      evidence — so the constraint is unsatisfiable without modifying that core type. Not
      attempted further pending a design decision (split `sat` into its own class vs. widen
      the existential). EP-42 and EP-43 (the substantive wins) shipped regardless.
- [ ] M2 — Proofs: add a "real BoolAlg.sat witness (EP-44)" block to `Keiki.SymbolicSpec`
      proving the witness is forceable and satisfies `models`; strengthen
      `Jitsurei.UserRegistrationSymbolicSpec`'s `isJust (sat ...)` checks to also confirm
      `models` on the returned witness.
- [ ] M3 — Docs + close: update `docs/research/sbv-boolalg-design.md` (the "Sat witness
      extraction" decision is superseded — `BoolAlg.sat` on `SymPred` now returns real
      witnesses via instance-head constraints) and any guide that mentions the placeholder.
      Fill Outcomes.


## Surprises & Discoveries

- 2026-05-20 (M0, *before* the fix). In `cabal repl keiki` over a satisfiable
  `p = PEq (proj #x) (lit 0)` (a `Word64` register fixture):

      BEFORE sat is Just = True
      BEFORE models on witness = *** Exception: Keiki.Symbolic.sat: placeholder witness;
        use symSat-backed analyses (isBot, isSingleValuedSym) or a future symSatExt for
        the concrete witness.

  So `sat (SymPred p)` *looks* like it returns a witness, but the witness is a landmine:
  any predicate whose `evalPred` actually inspects the register file or command (here
  `PEq (proj #x) (lit 0)` reads `#x`) crashes when `models` forces it. (`PTop`-style
  predicates don't crash only because `evalPred` never touches the witness.) This is the
  exact sharp edge M1 was meant to remove by pointing `sat` at `symSatExt`.

- 2026-05-20 (M1, **blocker — why EP-44 was deferred**). Prototyping M1 (instance head
  `(ExtractRegFile rs, KnownInCtors ci) => BoolAlg (SymPred rs ci)`, `sat = symSatExt`)
  revealed a blast radius far larger than the plan estimated. `cabal build keiki-test`
  failed at ~11 sites; `jitsurei-test` was clean (all shipped aggregates satisfy the
  constraints). Two root causes the plan did not foresee:

  1. **The `Keiki.Profunctor` existential `SomeSymTransducer ci co` hides `rs`** and carries
     only `(WeakenR rs, KnownSlotNames rs, Bounded s, Enum s)` — *not* `ExtractRegFile rs`.
     `CategorySpec` / `ChoiceSpec` / `StrongSpec` unpack it and call
     `isSingleValuedSym (withSymPred t)`. After the instance-head change that needs
     `ExtractRegFile rs`, but `rs` is existentially hidden with no such evidence, so it is
     **unsatisfiable by any instance or signature** — the only fix is to add
     `ExtractRegFile rs` to the `SomeSymTransducer` constructor (a core profunctor change)
     and thread it through every construction site.

  2. **Composition produces ci types with no natural `KnownInCtors`** — `Int`,
     `Either EmailCmd PingCmd`, `Either EmailCmd Int`, tuples (from `left'`/`right'`/
     `first'`/`second'`). These would need a generic `KnownInCtors (Either a b)` plus
     degenerate `allInCtors = []` instances for `Int`/tuples (which silently make `sat`
     return `Nothing` — a footgun).

  Mitigating facts that informed the defer: `sat` is **never called polymorphically**
  through a `BoolAlg phi` constraint (only at concrete `SymPred` types), and
  `isSingleValuedSym` uses only `isBot`/`conj` — so a cleaner future design could split
  `sat` into its own constrained class, leaving `BoolAlg (SymPred)` unconstrained and the
  whole ripple gone. Also, the real witness is **already available today** via the
  standalone `symSatExt`; EP-44 was only an ergonomics/honesty fix on the `BoolAlg.sat`
  method. Given the modest benefit versus a core-type change, the user chose to defer (see
  Decision Log).


## Decision Log

- Decision: Make `sat` on `SymPred` real by adding `(ExtractRegFile rs, KnownInCtors ci)`
  to the **instance head** of `BoolAlg (SymPred rs ci) (RegFile rs, ci)`, and defining
  `sat (SymPred p) = symSatExt p`.
  Rationale: the `BoolAlg` class types `sat :: phi -> Maybe a` with no per-method
  constraints, and Haskell cannot attach constraints to a single method beyond the
  class/instance head. The constraints witness reconstruction needs
  (`ExtractRegFile rs` to rebuild the register file, `KnownInCtors ci` to rebuild the
  command) therefore have to live on the instance head. Capturing the dictionaries inside
  the `SymPred` value instead does not help: `top :: phi` and `bot :: phi` are nullary and
  have nowhere to capture `rs`/`ci` dictionaries from, so they would still force the
  instance-head constraint. The instance head is the only clean place. This is exactly the
  trade-off `docs/research/sbv-boolalg-design.md`'s "Sat witness extraction" section
  weighed when it chose the placeholder; this plan reverses that choice now that
  `symSatExt` is mature and the witness path is trusted.
  Date: 2026-05-20

- Decision: The cost — the instance-head constraints ripple onto **every** `BoolAlg`
  method for `SymPred`, including `isBot` and (transitively) `isSingleValuedSym` — is
  accepted. After this plan, `isSingleValuedSym (withSymPred t)` requires
  `(ExtractRegFile rs, KnownInCtors ci)` in addition to `(Bounded s, Enum s)`.
  Rationale: every shipped aggregate already satisfies both constraints
  (`Jitsurei.UserRegistration`, `Jitsurei.OrderCart`, `Jitsurei.LoanApplication` all have
  `KnownInCtors`, and their register lists are all `Sym` slots so `ExtractRegFile` derives
  automatically). keiki is pre-1.0, so the minor signature tightening on a generic
  analysis is acceptable. Any keiki/jitsurei *test fixture* command type used with the
  `SymPred` algebra that lacks a `KnownInCtors` instance gets a one-line instance added in
  M1.
  Date: 2026-05-20

- Decision: Retire `unsafeWitness` and the witness-free `symSat` entirely (rather than
  deprecate). `unsafeWitness` has no remaining caller once `sat = symSatExt`. `symSat`'s
  only caller is the old `sat` definition; a witness-free "is it satisfiable?" check
  remains available as `not . symIsBot` (which carries no extraction constraints), so
  nothing is lost.
  Rationale: leaving a crashing placeholder and a near-duplicate wrapper around invites
  exactly the confusion this plan removes.
  Date: 2026-05-20

- Decision: **EP-44 is DEFERRED** (not implemented). The M0 baseline and an M1 prototype
  were done; the prototype was reverted (the only code change, in `src/Keiki/Symbolic.hs`,
  was rolled back, leaving the EP-42/EP-43-close state intact). `unsafeWitness`, `symSat`,
  and the unconstrained `BoolAlg (SymPred)` instance remain as before.
  Rationale: the planned instance-head approach has a much larger blast radius than the
  plan estimated (see Surprises, M1 entry): it makes `isSingleValuedSym` uncompilable on
  the `Keiki.Profunctor` existential `SomeSymTransducer` (which hides `rs` and can't carry
  `ExtractRegFile rs`), and forces `KnownInCtors` instances for non-aggregate ci types
  (`Int`, `Either`, tuples) that have no natural ones. Closing it properly requires either
  (a) splitting `sat` out of `BoolAlg` into its own constrained class — clean (no ripple
  to `isSingleValuedSym`, since `sat` is never used polymorphically) but a Core class-shape
  change, or (b) widening the `SomeSymTransducer` existential — a core profunctor change.
  Both exceed EP-44's stated "smallest plan" scope/risk, and the real witness is already
  available via the standalone `symSatExt`. The user chose to defer (2026-05-20) and keep
  the documented placeholder. A future ExecPlan can pick option (a) or (b).
  Date: 2026-05-20


## Outcomes & Retrospective

**Deferred (2026-05-20), not delivered.** M0 (baseline + the *before* placeholder-crash
capture) was completed; the M1 prototype was built, found to be infeasible without a
core-type change, and reverted. The shipped state is unchanged from EP-43's close:
`BoolAlg (SymPred rs ci)` remains unconstrained, `sat` still returns the crashing
`unsafeWitness` placeholder, and `symSat` is still exported. The real witness remains
available via the standalone `symSatExt` (which EP-42 made correct for repeated reads).

Why deferred: the plan's instance-head approach (put `(ExtractRegFile rs, KnownInCtors ci)`
on the `BoolAlg (SymPred)` head so `sat = symSatExt`) compiles for shipped aggregates
(`jitsurei-test` was clean) but breaks ~11 keiki-test sites, fundamentally because the
`Keiki.Profunctor` existential `SomeSymTransducer` hides `rs` without `ExtractRegFile`
evidence — so `isSingleValuedSym` on profunctor/category-composed transducers can no longer
be type-checked. The constraints also can't be satisfied for composition-produced ci types
(`Int`, `Either`, tuples). Full detail in Surprises (M1 entry) and the Decision Log.

What a future ExecPlan should do: prefer **splitting `sat` into its own constrained
typeclass** (e.g. a `SatWitness phi a` with `satExt`), leaving `BoolAlg (SymPred)`
unconstrained. This is clean because `sat` is never called through a polymorphic `BoolAlg
phi` constraint and `isSingleValuedSym` uses only `isBot`/`conj`, so there is no ripple to
the composition tests. It still must address the `()` / no-`PInCtor` witness case (the
existing M5 `sat top` / `sat (PEq lit5 lit5)` tests over `SymPred '[] ()` rely on a witness
the constructor-tag-keyed `pickCi` can't currently reconstruct). The alternative — widening
the `SomeSymTransducer` existential with `ExtractRegFile rs` — is heavier and touches core
profunctor construction sites.

Net for MasterPlan 12: two of three plans delivered (EP-42 memoization, EP-43 structural
arithmetic), the integration capstone closed (LoanApplication single-valuedness proven),
and EP-44 deferred with a clear, scoped path forward.


## Context and Orientation

This section assumes no prior knowledge of keiki. Read it before editing.

keiki is a Haskell library (the package at the repository root, `keiki.cabal`, module
prefix `Keiki.*`) for the pure core of event sourcing. An aggregate is a `SymTransducer`:
a finite control graph plus a typed *register file* (named, typed mutable slots), with
edges carrying a *guard* (predicate), an *update*, an *output*, and a *target* vertex.
Example aggregates live in `jitsurei` (`jitsurei/src/Jitsurei/*.hs`). The symbolic
analyses need the **z3** SMT solver on `PATH` at runtime
(`brew install z3` / `apt install z3`).

### The `BoolAlg` typeclass and the `HsPred` instance

`src/Keiki/Core.hs`, around line 444:

    class BoolAlg phi a | phi -> a where
      top    :: phi
      bot    :: phi
      conj   :: phi -> phi -> phi
      disj   :: phi -> phi -> phi
      neg    :: phi -> phi
      models :: phi -> a -> Bool
      sat    :: phi -> Maybe a
      isBot  :: phi -> Bool

The `a` is the *witness* type — for guard predicates it is `(RegFile rs, ci)` (a register
file plus an input command). The functional dependency `phi -> a` ties them.

The plain `HsPred` instance (line 458) is the v1 syntactic one: `sat _ = Nothing`,
`isBot PBot = True`, `isBot _ = False`. You do not change this instance.

### The `SymPred` wrapper and its instance (what you change)

`src/Keiki/Symbolic.hs`:

    newtype SymPred (rs :: [Slot]) (ci :: Type) = SymPred { unSymPred :: HsPred rs ci }

    instance BoolAlg (SymPred rs ci) (RegFile rs, ci) where
      top                                = SymPred PTop
      bot                                = SymPred PBot
      conj (SymPred p) (SymPred q)       = SymPred (PAnd p q)
      disj (SymPred p) (SymPred q)       = SymPred (POr  p q)
      neg  (SymPred p)                   = SymPred (PNot p)
      models (SymPred p) (regs, ci)      = evalPred p regs ci
      sat (SymPred p)                    = symSat   p     -- <- placeholder witness
      isBot (SymPred p)                  = symIsBot p

`SymPred` is a `newtype` — its constructor carries **no** constraints. The constraints you
add in M1 go on the `instance` head, not on the constructor; `withSymPred` (below) keeps
wrapping guards with no constraints.

### The placeholder machinery (what you retire)

`src/Keiki/Symbolic.hs`, around lines 453–482:

    unsafeWitness :: a
    unsafeWitness = error "Keiki.Symbolic.sat: placeholder witness; use symSat-backed analyses ... or a future symSatExt for the concrete witness."

    {-# NOINLINE symSat #-}
    symSat :: HsPred rs ci -> Maybe (RegFile rs, ci)
    symSat p = unsafePerformIO $ do
      res <- SBV.sat $ do { env <- mkSymEnv; translatePred env p }
      pure $ if SBV.modelExists res then Just (unsafeWitness, unsafeWitness) else Nothing

`symIsBot` (around line 491) is the witness-free emptiness check; it stays (the
witness-free "is satisfiable?" need is served by `not . symIsBot`).

### The real witness extractor (what `sat` will call)

`src/Keiki/Symbolic.hs`, around line 653:

    {-# NOINLINE symSatExt #-}
    symSatExt
      :: forall rs ci. (ExtractRegFile rs, KnownInCtors ci)
      => HsPred rs ci -> Maybe (RegFile rs, ci)

It runs one `SBV.sat` query and, on a model, reconstructs `(regs, ci)` by reading
`reg/<slot>` and `inp/<ctor>/<field>` from the model (via `readModel`/`pickCi`). It is
*pure* via `unsafePerformIO` + `NOINLINE`, deterministic per predicate. Its two
constraints:

- `ExtractRegFile rs` (around line 573) — a class with instances for `'[]` and
  `'(s,t) ': rs` (requiring `KnownSymbol s`, `Sym t`); it materializes a `RegFile rs` by
  reading each slot by name. **Automatic** for any register list whose value types are all
  in the `Sym` registry — no per-aggregate code.
- `KnownInCtors ci` (around line 618) — `allInCtors :: [SomeInCtor ci]`, a one-line-per-
  constructor list. Each shipped aggregate provides it: `Jitsurei.UserRegistration`
  (`UserCmd`), `Jitsurei.OrderCart` (`OrderCmd`, added in EP-41), `Jitsurei.LoanApplication`
  (`LoanCmd`).

### `withSymPred` and `isSingleValuedSym`

`withSymPred` (around line 533) re-tags a transducer's guards from `HsPred` to `SymPred`;
it has no constraints and stays unchanged. `isSingleValuedSym` (around line 510) is
`BoolAlg`-polymorphic and uses `isBot`/`conj`; instantiated at `SymPred` it will, after
M1, additionally require `(ExtractRegFile rs, KnownInCtors ci)` because those are on the
instance head. Its callers (`isSingleValuedSym (withSymPred someAggregate)`) compile so
long as the aggregate supplies both — which all shipped ones do.

### Where the tests live

- keiki unit tests: `keiki-test` (`keiki.cabal`, `main-is: Spec.hs`), symbolic unit tests
  in `Keiki.SymbolicSpec`. M2's proofs go here. **Important:** scan this module for any
  fixture whose command type is used through the `SymPred` algebra (`isBot (SymPred …)`,
  `isSingleValuedSym (withSymPred …)`, `sat (SymPred …)`) but which lacks a
  `KnownInCtors` instance — after M1's instance-head change, those uses won't compile
  until you add a `KnownInCtors` instance (a `[SomeInCtor …]` list) and ensure the
  register list is all-`Sym` (so `ExtractRegFile` derives). EP-41 already added such
  instances for the fixtures it exercised with `symSatExt`; the ones exercised only with
  `isBot`/`isSingleValuedSym` may not have them yet.
- jitsurei tests: `jitsurei-test` (`jitsurei/jitsurei.cabal`), notably
  `Jitsurei.UserRegistrationSymbolicSpec` (uses `isJust (sat (SymPred p))`, which M2
  strengthens) and `Jitsurei.LoanApplicationSymbolicSpec` /
  `Jitsurei.OrderCartSymbolicSpec` (use `isSingleValuedSym (withSymPred …)`).

### The design note this supersedes

`docs/research/sbv-boolalg-design.md`'s "Sat witness extraction" section (around lines
425–486) records the decision to return `unsafeWitness` from the class `sat` and expose
`symSatExt` separately, precisely because the class `sat` "forces `sat :: phi -> Maybe a`
— no extra context." This plan reverses that decision by putting the context on the
instance head. M3 updates the note to mark the decision superseded.


## Plan of Work

Four milestones (M0–M3). M1 is the substantive change; it is small but rippling, so build
incrementally and let GHC point at every site that needs a `KnownInCtors` instance.

### M0 — Baseline

Goal: known-good start and a recorded *before* picture of the crashing witness.

    z3 --version
    cabal build all
    cabal test all

Record example/pending counts. In `cabal repl keiki-test` (or `keiki`), confirm the
*before* behavior on a satisfiable predicate `p` over a fixture with `KnownInCtors`/
`ExtractRegFile` (reuse a `Keiki.SymbolicSpec` fixture):

    case sat (SymPred p) of
      Just w  -> models (SymPred p) w     -- expect: *** Exception: Keiki.Symbolic.sat: placeholder witness; ...
      Nothing -> error "unexpected unsat"

Record the exception text in Surprises.

Acceptance: build/tests pass; the placeholder crash is recorded.

### M1 — Real `sat`

Goal: `sat` on `SymPred` returns a real, forceable witness; the placeholder is gone.

In `src/Keiki/Symbolic.hs`:

1. Change the instance head to carry the extraction constraints and point `sat` at the
   real extractor:

        instance (ExtractRegFile rs, KnownInCtors ci)
              => BoolAlg (SymPred rs ci) (RegFile rs, ci) where
          top                           = SymPred PTop
          bot                           = SymPred PBot
          conj (SymPred p) (SymPred q)  = SymPred (PAnd p q)
          disj (SymPred p) (SymPred q)  = SymPred (POr  p q)
          neg  (SymPred p)              = SymPred (PNot p)
          models (SymPred p) (regs, ci) = evalPred p regs ci
          sat (SymPred p)               = symSatExt p
          isBot (SymPred p)             = symIsBot p

2. Delete `unsafeWitness` (lines ~460–465) and `symSat` (lines ~474–482). Remove `symSat`
   from the module export list (around line 56). Update the module header haddock (lines
   ~30–37) that describes `symSat`/the placeholder.

3. Build:

        cabal build all

   GHC will now flag every place that uses the `SymPred` `BoolAlg` instance at an `rs`/`ci`
   lacking `ExtractRegFile`/`KnownInCtors`. For each:
   - If it is a real aggregate, it already has the instances (no action).
   - If it is a test fixture command type without `KnownInCtors`, add a one-line instance
     (a `[SomeInCtor …]` list, one entry per `InCtor`, following the pattern in
     `Jitsurei.UserRegistration`'s `KnownInCtors UserCmd`). If a fixture register list has
     a non-`Sym` slot type, switch it to a `Sym` type (all keiki fixtures should already
     be `Sym`-typed). Record each addition in Surprises.

4. Fix comment references to `symSat`/placeholder: `grep -rn "symSat\b\|unsafeWitness\|placeholder witness" src jitsurei docs` and update the prose (e.g.
   `jitsurei/src/Jitsurei/LoanApplication.hs:117`,
   `jitsurei/test/Jitsurei/UserRegistrationSymbolicSpec.hs` comments) to say `sat` now
   returns a real witness.

5. Run the suite:

        cabal test all

   It must stay green. `Jitsurei.UserRegistrationSymbolicSpec`'s `isJust (sat (SymPred p))`
   assertions still pass (now backed by a real witness).

What exists at the end: `sat (SymPred p)` returns the same real witness as `symSatExt p`;
`unsafeWitness` and `symSat` are gone.

Acceptance: `cabal build all` and `cabal test all` pass; no `unsafeWitness`/`symSat`
remain (`grep` returns only historical doc mentions).

### M2 — Proofs

Goal: lock the fix with a before/after-falsifiable assertion.

Add a `describe "real BoolAlg.sat witness (EP-44)"` block to `Keiki.SymbolicSpec`. Using a
fixture with `KnownInCtors`/`ExtractRegFile` and a satisfiable guard `p` (reuse an EP-41
`symSatExt` fixture):

1. The witness is real and satisfies `models`:

        case sat (SymPred p) of
          Nothing -> expectationFailure "expected sat"
          Just w  -> models (SymPred p) w `shouldBe` True   -- forces w; before M1: crash

2. An unsat predicate gives `Nothing`: `sat (SymPred PBot) == Nothing`.

3. Consistency with `symSatExt`: `isJust (sat (SymPred p)) == isJust (symSatExt p)` for a
   few sample `p`.

Strengthen `Jitsurei.UserRegistrationSymbolicSpec`: where it currently asserts
`isJust (sat (SymPred p)) `shouldBe` True`, add a follow-up that forces the witness and
checks `models` (the witness is now safe to inspect).

    cabal test all --test-options=--match=/Symbolic/

What exists at the end: a test that crashed (when forcing the witness) before M1 and
passes after.

Acceptance: `cabal test all` passes including the new block.

### M3 — Documentation and close

Goal: leave the design record consistent.

Update `docs/research/sbv-boolalg-design.md`: in the "Sat witness extraction" section
(~lines 425–486) and the "Purity model" section, mark the `unsafeWitness`-placeholder
decision **superseded by EP-44**: `BoolAlg.sat` on `SymPred` now returns real witnesses by
constraining the instance head with `(ExtractRegFile rs, KnownInCtors ci)`; document the
ripple onto `isBot`/`isSingleValuedSym` and that all shipped aggregates satisfy it. Sweep
the guides (`docs/guide/why-smt.md`, `docs/guide/symbolic-ci.md`) for any "`sat` returns a
placeholder; use `symSatExt`" note and update it. Fill Outcomes & Retrospective.

Acceptance: docs read consistently; no stale "placeholder witness" claim remains except as
history.


## Concrete Steps

All commands run from `/Users/shinzui/Keikaku/bokuno/keiki`.

Baseline (M0):

    z3 --version
    cabal build all
    cabal test all

Iterate per milestone:

    cabal build all
    cabal test all

Focus while iterating:

    cabal test keiki-test
    cabal test all --test-options=--match=/Symbolic/

Find lingering placeholder references:

    grep -rn "symSat\b\|unsafeWitness\|placeholder witness" src jitsurei docs

Commit after each milestone with the MasterPlan, ExecPlan, and Intention trailers:

    git add -A
    git commit -m "feat(symbolic): EP-44 M1 — BoolAlg.sat on SymPred returns a real witness

    <body>

    MasterPlan: docs/masterplans/12-symbolic-arithmetic-terms-translator-memoization-and-real-boolalg-sat-witnesses.md
    ExecPlan: docs/plans/44-real-witnesses-from-boolalg-sat-retire-the-placeholder-witness.md
    Intention: intention_01ks3939thethvf26jkpx3ksht"


## Validation and Acceptance

The plan is complete when, from `/Users/shinzui/Keikaku/bokuno/keiki`:

1. `cabal build all` succeeds.

2. `cabal test all` passes with no failures; pending count unchanged.

3. New, observable behavior (asserted by a test that crashes before M1 and passes after):
   - `case sat (SymPred p) of Just w -> models (SymPred p) w` is `True` for a satisfiable
     `p` (before M1, forcing `w` throws the `unsafeWitness` error).
   - `sat (SymPred PBot) == Nothing`.

4. `unsafeWitness` and `symSat` no longer exist (`grep` returns only historical doc
   mentions); `Jitsurei.UserRegistrationSymbolicSpec` confirms `models` on the
   `sat`-returned witness.


## Idempotence and Recovery

The change is localized to the `BoolAlg (SymPred rs ci)` instance and the removal of two
helpers in `Keiki.Symbolic`, plus mechanical `KnownInCtors` additions GHC points at.
Re-applying the edits is a no-op if already present. `cabal build all`/`cabal test all`
are safe to re-run. To recover, restore `unsafeWitness`/`symSat`, drop the instance-head
constraints, and set `sat (SymPred p) = symSat p`. If z3 is missing, symbolic specs fail
loudly; install z3. The milestone is committed separately, so `git revert` cleanly backs
it out.

The witness `sat` returns inherits `symSatExt`'s correctness, including its repeated-read
caveat *until the memoization sibling
(`docs/plans/42-per-slot-and-per-input-field-memoization-in-the-symbolic-translator.md`)
lands*. If this plan is implemented before EP-42, the M2 proofs should use predicates
*without* repeated reads of the same register/field (single reads are always correct);
note this in Progress.


## Interfaces and Dependencies

Libraries: `sbv` (already a dependency) for the solver call inside `symSatExt`; the z3
solver on `PATH` at test time. No new dependencies.

Types/signatures that must exist at the end:

In `Keiki.Symbolic`:

    instance (ExtractRegFile rs, KnownInCtors ci)
          => BoolAlg (SymPred rs ci) (RegFile rs, ci)
    -- with: sat (SymPred p) = symSatExt p
    -- removed: unsafeWitness, symSat (and the symSat export)

`symSatExt`, `ExtractRegFile`, `KnownInCtors`, `symIsBot`, `withSymPred`,
`isSingleValuedSym` keep their signatures. `isSingleValuedSym`'s *effective* constraint at
`SymPred` widens to include `(ExtractRegFile rs, KnownInCtors ci)`.

Backward compatibility: this is a small breaking change to keiki's public API (it removes
the exported `symSat` and tightens the `SymPred` `BoolAlg` instance and therefore
`isSingleValuedSym`'s constraints at `SymPred`). keiki is pre-1.0, and every shipped
aggregate satisfies the new constraints, so no shipped aggregate breaks. A witness-free
satisfiability check is `not . symIsBot` (no extraction constraints).

Relationship to sibling plans (see the MasterPlan's Dependency Graph and Integration
Points):

- `docs/plans/42-per-slot-and-per-input-field-memoization-in-the-symbolic-translator.md`
  (memoization): soft dependency. The `sat`/`symSatExt` witness is only correct for
  repeated-read predicates after EP-42. Recommended order: EP-42 first.
- `docs/plans/43-structural-arithmetic-terms-in-the-keiki-term-language.md` (arithmetic):
  independent. No shared edit; both touch `Keiki.Symbolic` but in disjoint places
  (EP-43 in the translator/`discoverSymNum`, EP-44 in the `BoolAlg` instance).
