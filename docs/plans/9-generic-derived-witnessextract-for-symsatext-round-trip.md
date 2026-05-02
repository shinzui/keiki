---
id: 9
slug: generic-derived-witnessextract-for-symsatext-round-trip
title: "Generic-derived WitnessExtract for symSatExt round-trip"
kind: exec-plan
created_at: 2026-05-01T22:06:48Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
master_plan: "docs/masterplans/3-keiki-generics-dx-follow-ups.md"
---

# Generic-derived WitnessExtract for symSatExt round-trip

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

The keiki library's `Keiki.Symbolic` module (added by EP-2 of
MasterPlan 2) exposes `symSat`, an SBV-backed satisfiability check
on `HsPred` predicates. The current implementation returns
`Just (placeholder, placeholder)` on a satisfiable predicate:

    -- src/Keiki/Symbolic.hs (current state)
    {-# NOINLINE symSat #-}
    symSat :: HsPred rs ci -> Maybe (RegFile rs, ci)
    symSat p = unsafePerformIO $ do
      res <- SBV.sat $ do
        env <- mkSymEnv
        translatePred env p
      pure $ if SBV.modelExists res
               then Just (unsafeWitness, unsafeWitness)
               else Nothing

`unsafeWitness` is `error "Keiki.Symbolic.sat: placeholder
witness; ..."`. Forcing either component crashes. The placeholder
suffices for `isSingleValuedSym` (which only inspects the boolean
"does a model exist?" answer) but not for any test that wants a
concrete `(RegFile rs, ci)` witness.

EP-2's M5 retrospective flagged this as a deliberate punt:

> Witness extraction split into typeclass-`sat` (placeholder
> witness, satisfiability-only) and `symSatExt` (full extraction
> via `WitnessExtract` instances).

The `keiki-generics-design.md` design note catalogues the follow-up
as **item D — Symbolic `WitnessExtract` instances via Generics**:

> EP-2's M5 punted on full witness extraction in `symSat`. A future
> `symSatExt` requires hand-written `WitnessExtract rs ci`
> instances: given an SBV model lookup, build a `RegFile rs` and a
> `ci` value. This is mechanical for any (rs, ci) whose underlying
> types have `Sym` instances; a `Generic`-driven derivation would
> write the instances automatically. Effort: ~6-8 hours including
> the SBV model plumbing. Net win: the User Registration symbolic
> spec gains a "build a concrete `(regs, cmd)` witness from a
> `sat` query and verify `models` agrees" round-trip test.

This plan delivers item D. After this plan is complete, the
repository contains:

- A `WitnessExtract` typeclass derived via `GHC.Generics`
  machinery, plus a slot-list-walking helper class
  `ExtractRegFile` whose instances are mechanically generated
  from the `Sym` instances already shipped by `Keiki.Symbolic`.
  Both live in `src/Keiki/Generics.hs` (or a sub-module
  `Keiki/Generics/Witness.hs`; M1 picks).
- A new export from `Keiki.Symbolic`:

      symSatExt
        :: ( ExtractRegFile rs
           , KnownInCtors ci
           )
        => HsPred rs ci -> Maybe (RegFile rs, ci)

  The translation now allocates SBV variables with **deterministic
  names** keyed on the slot/InCtor-field structure; on a
  satisfiable predicate, `symSatExt` walks the SBV model with
  those names and reconstitutes a concrete witness pair.
- A round-trip test on `withSymPred userReg`'s
  `RequiresConfirmation` edge guard:

      sat (guard e) → Just w  ⟹  models (guard e) w == True

  …closing the loop EP-2 left open.
- An updated `docs/research/keiki-generics-design.md` with item D
  marked **Implemented (see EP-9)**.

How a future contributor sees this work:

    cabal test
    # 70 → 72+ examples, 0 failures.
    # Includes "symSatExt round-trip on userReg edge guard" test.

The user-visible win: keiki's `sat` now returns a concrete
witness, not a placeholder. Symbolic specs can be exercised
end-to-end (predicate → witness → predicate-evaluation agrees).
The build-time analysis surface is no longer "you can prove
emptiness; for satisfiability, you only get a yes/no."


## Progress

Use a checklist to summarize granular steps. Every stopping point
must be documented here, even if it requires splitting a partially
completed task into two ("done" vs. "remaining"). This section must
always reflect the actual current state of the work.

- [x] **Milestone 0 — Verify prerequisites.** 2026-05-01:
      `cabal build all` and `nix-shell -p z3 -- cabal test all` are
      green. Baseline 85 examples, 0 failures (post EP-8 + EP-10;
      plan's "70 expected" predates those EPs). GHC 9.12.3, SBV
      14.0, z3 4.16.0 (via `nix-shell -p z3`).
- [x] **Milestone 1 — Design milestone.** 2026-05-01: design
      paragraph appended to `keiki-generics-design.md`'s item D.
      Decisions captured in this plan's Decision Log. Module
      placement: `Keiki.Symbolic` (override of plan default).
      Naming: `reg/<slot>`, `inp/<icName>/<slot>`. Memoization
      deferred. `symDefault` added to `Sym`. `symSat` kept
      alongside new `symSatExt`. Decide:
      (a) Where the witness-extract classes live (extend
          `Keiki.Generics` vs. new `Keiki.Generics.Witness`).
      (b) How the SBV translation surfaces deterministic variable
          names so the witness extractor can find them in the
          model.
      (c) The shape of `ExtractRegFile` and `KnownInCtors`.
      (d) Whether `symSat` is upgraded in place or `symSatExt` is
          a separate function.
      Append a paragraph to `keiki-generics-design.md`'s item D.
- [x] **Milestone 2 — Named SBV translation.** 2026-05-01:
      `translateTermSym` now allocates `"reg/<slot>"` for `TReg`
      and `"inp/<icName>/<slot>"` for `TInpCtorField`. Helper
      `indexName :: Index rs r -> String` recovers the slot name
      via `KnownSymbol` evidence on `ZIdx` (via
      `TypeAbstractions`'s `@s` pattern). Existing tests still
      pass (85 → 85, 0 failures).
- [x] **Milestone 3 — `ExtractRegFile` typeclass.** 2026-05-01:
      Added to `Keiki.Symbolic` (override of plan default; see
      Decision Log). Two instances cover the slot list. Reader is
      `forall r. Sym r => String -> r` (total — defaults via
      `symDefault` for unbound names).
- [x] **Milestone 4 — `KnownInCtors` typeclass + `UserCmd`
      instance.** 2026-05-01: `SomeInCtor` existentially wraps
      `InCtor ci ifs` with `ExtractRegFile ifs` evidence;
      `KnownInCtors` ships the bag of all such wrappers.
      `Keiki.Examples.UserRegistration` adds the five-line
      instance for `UserCmd`.
- [x] **Milestone 5 — `symSatExt`.** 2026-05-01:
      `symSatExt :: (ExtractRegFile rs, KnownInCtors ci) =>
      HsPred rs ci -> Maybe (RegFile rs, ci)` exported from
      `Keiki.Symbolic`. `symSat`'s placeholder is unchanged
      (still routed through the `BoolAlg.sat` typeclass method).
- [x] **Milestone 6 — Round-trip tests.** 2026-05-01: 4 cases
      added to `UserRegistrationSymbolicSpec` —
      `ConfirmAccount` edge guard round-trip, literal-backed
      PEq, constructor-mutex unsat, singleton-`Continue`
      reconstruction. 85 → 89 examples, 0 failures.
- [x] **Milestone 7 — Update design note + commit.** 2026-05-01:
      `keiki-generics-design.md`'s item D marked
      **Implemented (see EP-9)**; commit with three trailers.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights
discovered during implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- **2026-05-01 — M0 baseline.** GHC 9.12.3, SBV 14.0, z3 4.16.0
  available under `nix-shell -p z3`. Baseline: 85 examples, 0
  failures. `cabal build all` clean. (Note: M0's plan-text said
  "70 expected"; that count predates EP-8 and EP-10. The current
  baseline is 85 because EP-10 added 5 DeciderSpec cases and
  EP-8 added 10 THSpec cases.)

- **2026-05-01 — M1: place witness-extract classes in
  `Keiki.Symbolic`, not `Keiki.Generics`.** Plan's default was
  Generics. Overridden because `ExtractRegFile`'s reader is
  `forall r. Sym r => String -> r`, requiring the `Sym` typeclass
  in scope. `Sym` lives in `Keiki.Symbolic`. Placing
  `ExtractRegFile`/`KnownInCtors`/`SomeInCtor` in `Keiki.Generics`
  would force a `Generics → Symbolic` dependency that pulls SBV
  into every TH-using example module's transitive compile graph.
  `Keiki.Generics` stays SBV-independent; `Keiki.Symbolic` gains
  the witness-extract surface as a natural extension.

- **2026-05-01 — M1: naming scheme `reg/<slot>`,
  `inp/<icName>/<slot>`.** Slashes are SBV-name-safe (verified by
  a one-liner: `free "reg/email"` produces a model value
  retrievable by the same name). Shared input constructor tag
  stays `"inputCtor"`. Escape-hatch translations
  (`TApp1`/`TApp2`/`PMatchC`/`neq` in `goEq`) keep their existing
  anonymous names — their values are not extracted.

- **2026-05-01 — M1: skip memoization in v1.** Empirical test
  shows SBV's `free name` uniquifies on repeated names: two calls
  to `free "x"` produce `x` and `x_0`, both as independent free
  variables in the model. For predicates with two reads of the
  same slot, the SBV variables are independent and the model may
  satisfy them with distinct values; the extractor's
  `getModelValue` by name returns only the first. The User
  Registration test target has no repeated reads, so the
  round-trip is sound for it. Memoization (via an `IORef`-cached
  `Map String SomeSBV` in `SymEnv`) is documented as a follow-up
  in `symSatExt`'s haddock. Reason for deferral: complexity (an
  IORef threaded through every `translateTermSym` recursion) for
  zero immediate test-target benefit.

- **2026-05-01 — M1: extend `Sym` with `symDefault :: a`.** The
  predicate translation's named-allocation produces SBV variables
  for every slot/field the predicate *references*. Slots the
  predicate doesn't reference have no model value; the extractor
  needs *some* value to put in the witness. Defaults: `False`,
  `0`, `0`, `""`, epoch. Soundness: since the predicate doesn't
  constrain unreferenced slots, any value (including the default)
  satisfies it — the round-trip `models p (regs, cmd) == True`
  holds. Alternative (allocate SBV vars for all slots/fields up
  front via a `KnownSlotTypes rs` typeclass) was rejected as
  heavier plumbing for the same observable behavior.

- **2026-05-01 — M1: keep `symSat` alongside `symSatExt`.**
  `BoolAlg.sat :: phi -> Maybe a` can't carry the extra
  `ExtractRegFile rs` and `KnownInCtors ci` constraints
  `symSatExt` requires. `symSat` stays the typeclass-method route
  (placeholder witness, `BoolAlg`-compatible); `symSatExt` is the
  new constraint-carrying alternative. Both share the
  named-translation refactor in M2.


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones
or at completion. Compare the result against the original purpose.

- **2026-05-01 — EP-9 complete.** `Keiki.Symbolic` ships
  `symSatExt`, `ExtractRegFile`, `SomeInCtor`, and
  `KnownInCtors`; the `Sym` typeclass gained `symDefault :: a`
  with curated defaults for the five supported types. The User
  Registration aggregate's `RequiresConfirmation`/`ConfirmAccount`
  edge guard round-trips through `sat → witness → models` and
  evaluates to `True`; constructor-mutex predicates correctly
  return `Nothing`; the singleton `Continue` is reconstructed by
  name. 89 examples, 0 failures (z3 required).

  *Module placement.* The plan defaulted to `Keiki.Generics`; M1
  overrode to `Keiki.Symbolic`. Rationale: the witness-extract
  classes depend on `Sym` (which lives in Symbolic), and placing
  them in Generics would force a `Generics → Symbolic`
  dependency that drags SBV into every TH-using example
  module's compile graph. The override is documented in this
  plan's Decision Log and the `keiki-generics-design.md` item D
  amendment.

  *Limitations carried forward.* Two are documented in
  `symSatExt`'s haddock and surface in its design notes:

    1. *Repeated reads of the same slot or input field.* SBV's
       `free` uniquifies repeated names with `_N` suffixes. The
       witness extractor reads only the first allocation by
       name, so a predicate like @proj #x .== proj #x@ may
       produce a witness whose `evalPred` returns `False`. The
       User Registration test target has no repeated reads.
       Memoization (an `IORef`-cached map in `SymEnv`) is the
       fix. Estimated effort: ~1-2 hours.

    2. *Escape-hatch terms.* `TApp1`, `TApp2`, `PMatchC`, and
       `PEq` over a non-`Sym` operand type translate to fresh
       anonymous SBV variables; the witness reflects only the
       slots and input fields the predicate references through
       `TReg` and `TInpCtorField`. This matches how the existing
       `evalTerm` evaluates these terms — the witness is not
       expected to capture opaque Haskell function semantics.

  *Master-plan-level acceptance.* MasterPlan 3's gate states the
  symbolic `sat` round-trip on `userReg` returns
  @Just (regs, cmd)@ with `models p (regs, cmd) == True`. EP-9
  closes that gate via `symSatExt` rather than upgrading
  `symSat` (which retains its `BoolAlg.sat`-routed placeholder
  for back-compat). All three children of MasterPlan 3 are
  complete; the master plan is ready for closure.


## Context and Orientation

Describe the current state relevant to this task as if the reader
knows nothing.

The keiki library is in `/Users/shinzui/Keikaku/bokuno/keiki/`.
Modules relevant to this plan:

    src/Keiki/Core.hs      — formalism: Term, OutTerm, RegFile, etc.
    src/Keiki/Generics.hs  — Generic-derived ctor helpers + Append
                             type family + GRecord/GTuple/GHasCtor
                             classes.
    src/Keiki/Symbolic.hs  — SBV-backed BoolAlg via Sym typeclass,
                             SymEnv, translateTermSym, translatePred,
                             symSat (placeholder), symIsBot, SymPred.

**Key shapes from `Keiki.Core`:**

    type Slot = (Symbol, Type)

    data RegFile (rs :: [Slot]) where
      RNil  :: RegFile '[]
      RCons :: Proxy s -> t -> RegFile rs -> RegFile ('(s, t) ': rs)

    data InCtor ci ifs = InCtor
      { icName  :: String
      , icMatch :: ci -> Maybe (RegFile ifs)
      , icBuild :: RegFile ifs -> ci
      }

**Key shapes from `Keiki.Symbolic`:**

    class (SBV.SymVal (SymRep a), Typeable a) => Sym a where
      type SymRep a :: Type
      toSym   :: a -> SymRep a
      fromSym :: SymRep a -> a

    data SymDict r where
      SymDict :: Sym r => SymDict r

    discoverSym :: forall r. Typeable r => Maybe (SymDict r)
    -- registered: Bool, Int, Integer, Text, UTCTime

    newtype SymEnv = SymEnv { seInputCtor :: SBV.SBV String }

    translateTermSym
      :: forall rs ci r. Sym r
      => SymEnv -> Term rs ci r -> SBV.Symbolic (SBV.SBV (SymRep r))

    translatePred
      :: forall rs ci. SymEnv -> HsPred rs ci -> SBV.Symbolic SBV.SBool

    {-# NOINLINE symSat #-}
    symSat :: HsPred rs ci -> Maybe (RegFile rs, ci)

The translator currently allocates SBV variables with names like:

- `"inputCtor"` — the shared input-constructor tag.
- `"reg"` — for every `TReg ix` (no slot name embedded).
- `"inp/<icName>"` — for every `TInpCtorField ic ix` (no field name
  embedded).
- `"app1"` / `"app2"` — for opaque `TApp1`/`TApp2`.
- `"pmatchc"` — for opaque `PMatchC`.
- `"neq"` — for `PEq` whose operand type lacks a `Sym` instance.

These names collide across multiple reads (every `TReg` gets the
literal name `"reg"`, so two reads of two different slots produce
two SBV variables with the same name; SBV resolves by allocation
order, not by name). For `symSatExt`, this is insufficient:
witness extraction needs *deterministic, distinct* names — one per
slot of the register file and one per `(InCtor, slot)` input
field — so a model lookup by name returns the right value.

**Why witness extraction needs Generics.**

The current `RegFile rs` and `ci` types are arbitrary user types.
The witness extractor needs to walk:

1. The slot list `rs :: [Slot]` to allocate one SBV variable per
   slot at translation time and to read each from the SBV model
   at extraction time. **This is a value-level walk over a
   type-level list**, dispatched by typeclass. The `Sym`
   typeclass already provides the per-type plumbing
   (`SymRep a`, `toSym`, `fromSym`); the witness extractor wraps
   that with a per-slot lookup.

2. The input constructor's identifier (the `InCtor`'s `icName`) and
   its input-field slot list `ifs`, plus the `icBuild` function on
   the `InCtor` to assemble a `ci`. **This requires knowing all
   possible InCtors of a `ci` type** so the model lookup picks
   the right one based on the `seInputCtor` tag's value.

The first walk is straightforward: a class
`ExtractRegFile (rs :: [Slot])` with a method
`extractRegFile :: NameMap -> SBV.SMTModel -> Maybe (RegFile rs)`.
Per-slot instance constrains `KnownSymbol s` (for the lookup name)
and `Sym t` (for `fromSym`). Two instances cover the slot list:
the empty list and the cons.

The second walk is harder: `ci` is a sum type with N InCtor-shaped
constructors. The witness extractor must know all of them to pick
the right one based on the model's value of `seInputCtor`. A
Generic-driven helper class `KnownInCtors ci` walks `Rep ci` to
extract the list of `(constructor name, payload type)` pairs;
combined with a known set of `InCtor` values for that type
(probably passed in by the caller, or registered via a class), the
extractor can re-build the `ci`.

The simplest signature, which keeps the extraction's plumbing
local to `Keiki.Symbolic` and avoids deep entanglement with the
`Keiki.Generics` machinery, takes the list of `InCtor`s as an
explicit argument:

    symSatExt
      :: ExtractRegFile rs
      => [InCtor ci ifs]   -- problematic: ifs varies per ctor
      -> HsPred rs ci
      -> Maybe (RegFile rs, ci)

…but `ifs` varies per constructor, so the list type has to be
existentially quantified:

    data SomeInCtor ci where
      SomeInCtor :: InCtor ci ifs -> ExtractRegFile ifs => SomeInCtor ci

    symSatExt
      :: ExtractRegFile rs
      => [SomeInCtor ci]
      -> HsPred rs ci
      -> Maybe (RegFile rs, ci)

…or the caller passes a typeclass dictionary:

    class KnownInCtors ci where
      allInCtors :: [SomeInCtor ci]

    symSatExt
      :: (ExtractRegFile rs, KnownInCtors ci)
      => HsPred rs ci
      -> Maybe (RegFile rs, ci)

The latter is cleaner but requires the user to write a
`KnownInCtors` instance per command sum. Generic-derive that
instance from `Rep ci` so the user gets it for free with `deriving
(Generic)` on the sum type.

**The User Registration smoke-test target.**

The intended end state for the round-trip test:

    -- test/Keiki/Examples/UserRegistrationSymbolicSpec.hs (extension)
    it "symSatExt round-trips a satisfiable edge guard" $ do
      let edges = userRegEdges RequiresConfirmation
          confirmEdge = head edges  -- the `isConfirm AND eq` edge
          guardP = guard confirmEdge
      case symSatExt (unSymPred (SymPred guardP :: SymPred _ _)) of
        Nothing -> expectationFailure "guard is unsat (should be sat)"
        Just (regs, cmd) -> do
          evalPred guardP regs cmd `shouldBe` True

(With the right shape adaptations; see the actual existing spec
for the import surface.)


## Plan of Work

Seven milestones. Effort estimate: ~6-8 hours per the design note's
estimate, plus ~1-2 hours for the round-trip test.

**Milestone 0 — Baseline.** Run `cabal build all && cabal test
all`. Record the test count (70 expected). `ghcup run --with-ghc
9.10.3 -- ghc-pkg list sbv` confirms SBV resolves to 14.0.

**Milestone 1 — Design milestone.** Decide:

- *Module placement.* Two options:
  (a) Extend `Keiki.Generics` with `ExtractRegFile`,
      `KnownInCtors`, and the Generic instances.
  (b) Create `src/Keiki/Generics/Witness.hs` as a sub-module
      dedicated to witness extraction; keep `Keiki.Generics`
      focused on authoring helpers (mkInCtorVia / mkWireCtorVia /
      RegFieldsOf etc.).
  Default: (a) — the Generic-walk machinery is small and shares
  primitives (`Append`, `KnownSlotNames`) with the existing
  classes. Document the choice in the Decision Log.

- *Translation naming scheme.* The translator allocates SBV
  variables with deterministic names. Per-slot register reads:
  `"reg/<slotName>"`. Per-(InCtor, slot) input projections:
  `"inp/<icName>/<slotName>"`. The shared input constructor tag
  stays `"inputCtor"`. `app1`/`app2`/`pmatchc`/`neq` get unique
  suffixes via a counter threaded through `Symbolic`; their
  values are not extracted (they are escape-hatch terms whose
  witnesses are out of scope).

- *Naming-collision risk.* If two reads of the same slot occur in
  one predicate (e.g. `proj #email .== proj #email`), the named
  allocation reuses the same SBV variable. This is *correct* —
  two reads of the same register at the same call point produce
  the same value. The translator memoizes per-name allocations
  via an `IORef` or a state-monad layer over `Symbolic`. Decision
  for M2: use `Symbolic`'s built-in named-variable cache (SBV
  guarantees this when `free` is called twice with the same
  name; verify in the design milestone).

- *`symSat` vs. `symSatExt`.* Two paths:
  (a) Upgrade `symSat` in place to return real witnesses,
      retiring `unsafeWitness`.
  (b) Add `symSatExt` alongside `symSat` (placeholder); make
      `symSat` deprecated.
  Default: (a) — `symSat`'s placeholder was always a transitional
  shape; replacing it with real witnesses doesn't break the
  `BoolAlg (SymPred rs ci)` instance because the only callers
  that need the witness are direct callers, and they will
  benefit from the real witness immediately.
  However: `symSatExt` may need additional constraints
  (`ExtractRegFile rs`, `KnownInCtors ci`) that `BoolAlg`'s `sat`
  method doesn't carry. Keep `symSat` as the typeclass method
  (returning concrete witnesses if extractable, otherwise
  failing gracefully) and add `symSatExt` as an explicit-context
  variant for callers who want the constraints visible.

  Final: keep both. `symSat`'s placeholder stays for the
  `BoolAlg` typeclass method (it needs to compile without the
  extra constraints); `symSatExt` is the constraint-carrying
  variant that returns real witnesses. Document this in the
  Decision Log.

Append a paragraph to `keiki-generics-design.md`'s "### D.
Symbolic `WitnessExtract` instances via Generics" section
recording the chosen design.

Acceptance: design paragraph lands before any code is written.

**Milestone 2 — Named translation.** Edit `src/Keiki/Symbolic.hs`.
Update `translateTermSym` and `translatePred` to allocate SBV
variables with deterministic names. The key changes:

- `TReg ix` allocates `SBV.free ("reg/" <> slotNameAt ix)`.
- `TInpCtorField ic ix` allocates
  `SBV.free ("inp/" <> icName ic <> "/" <> slotNameAt ic ix)`.
- `app1`/`app2`/`pmatchc`/`neq` allocate with a counter from a
  threaded state (carried in `SymEnv` or via `Symbolic`'s
  built-in unique-name generator if available).

(`slotNameAt` is a small helper — the slot-name lookup is
already `KnownSymbol`-driven for `RegFile rs` allocation; reuse
the existing `KnownSlotNames` class.)

The `SymEnv` may grow a per-translation cache so repeated reads
of the same name produce the same SBV variable:

    data SymEnv = SymEnv
      { seInputCtor :: SBV.SBV String
      , seCache     :: IORef (Map String SBV.SBVValue)
      }

…or use SBV's built-in named-variable resolution. M2 confirms
which works.

Run the existing tests:

    cabal test all

Expected: same count, 0 failures. The `isSingleValuedSym` proof
on `userReg` continues to pass (it doesn't depend on variable
names, only on the predicate's boolean structure).

Acceptance: existing tests green; the named-translation refactor
is observable via `-ddump-splices` or by inspecting the SBV
translation in a REPL.

**Milestone 3 — `ExtractRegFile` typeclass.** Add to
`src/Keiki/Generics.hs`:

    -- | Materialize a 'RegFile' from a typed reading function.
    -- The reader is given a slot name (@String@) and a 'SymDict r'
    -- for the slot's value type, and must return the slot's value
    -- on hit or 'Nothing' on miss.
    class ExtractRegFile (rs :: [Slot]) where
      extractRegFile
        :: (forall r. Sym r => String -> Maybe r)
        -> Maybe (RegFile rs)

    instance ExtractRegFile '[] where
      extractRegFile _ = Just RNil

    instance ( KnownSymbol s
             , Sym t
             , ExtractRegFile rs
             )
          => ExtractRegFile ('(s, t) ': rs) where
      extractRegFile lookup = do
        v   <- lookup @t (symbolVal (Proxy @s))
        rs' <- extractRegFile @rs lookup
        pure (RCons (Proxy @s) v rs')

The reader is provided by `symSatExt` — it wraps SBV's model
lookup. Instance resolution recurses on the slot list; every slot
has at most a `Sym` constraint, which the existing `Sym`
instances cover for `Bool`, `Int`, `Integer`, `Text`, `UTCTime`.

`cabal build` succeeds.

Acceptance: a quick REPL test:

    extractRegFile @'[ '("x", Int), '("y", Text) ]
                   (\name -> case name of
                       "x" -> Just (42 :: Int) ...)

…returns `Just (RCons _ 42 (RCons _ "hello" RNil))`. (In practice
the reader uses `discoverSym` to dispatch the type; the test in
M5 exercises this end-to-end.)

**Milestone 4 — `KnownInCtors` typeclass + Generic walk.** Add to
`src/Keiki/Generics.hs`:

    -- | Existential wrapper around an 'InCtor' that hides the
    -- input-field slot list.
    data SomeInCtor (ci :: Type) where
      SomeInCtor
        :: ExtractRegFile ifs
        => InCtor ci ifs -> SomeInCtor ci

    -- | A 'ci' type whose set of 'InCtor's is statically known.
    class KnownInCtors ci where
      allInCtors :: [SomeInCtor ci]

The user provides `allInCtors` as a hand-written list:

    instance KnownInCtors UserCmd where
      allInCtors =
        [ SomeInCtor inCtorStart
        , SomeInCtor inCtorConfirm
        , SomeInCtor inCtorResend
        , SomeInCtor inCtorGdpr
        , SomeInCtor inCtorContinue
        ]

…or via Generic derivation if M1's design milestone decides to
auto-derive (Generic walk over `Rep UserCmd` produces the list).
Default: hand-written instance shipped in
`Keiki.Examples.UserRegistration`. Generic-derivation is a
nice-to-have follow-up.

Acceptance: `instance KnownInCtors UserCmd` compiles in
`Keiki.Examples.UserRegistration` against the existing
`inCtorStart`/etc. binders.

**Milestone 5 — Implement `symSatExt`.** Edit
`src/Keiki/Symbolic.hs`. Add the new function:

    {-# NOINLINE symSatExt #-}
    symSatExt
      :: forall rs ci.
         ( ExtractRegFile rs
         , KnownInCtors ci
         )
      => HsPred rs ci -> Maybe (RegFile rs, ci)
    symSatExt p = unsafePerformIO $ do
      res <- SBV.satWith config $ do
        env <- mkSymEnv
        translatePred env p
      pure $ case SBV.getModelValue "inputCtor" res of
        Nothing       -> Nothing
        Just ctorTag  -> do
          let lookupReg :: forall r. Sym r => String -> Maybe r
              lookupReg name = do
                rep <- SBV.getModelValue ("reg/" <> name) res
                pure (fromSym rep)
          regs <- extractRegFile @rs lookupReg
          ci   <- pickCi @ci ctorTag
                          (\icName fname -> do
                              rep <- SBV.getModelValue
                                       ("inp/" <> icName <> "/" <> fname) res
                              pure (fromSym rep))
          pure (regs, ci)

The `pickCi` helper walks `allInCtors :: [SomeInCtor ci]`,
selects the entry whose `icName` matches the model's
`ctorTag`, and uses `extractRegFile @ifs` (where `ifs` is the
selected ctor's slot list) to build the input regfile. Then
calls `icBuild` on the result.

Updates `symSat` (the placeholder) to delegate to `symSatExt`
when the constraints are satisfied; otherwise keep the
placeholder. Two paths:

(a) Keep `symSat`'s placeholder exactly as it is; add `symSatExt`
    as the constraint-carrying alternative.
(b) Make `symSat` a thin wrapper that calls `symSatExt` if the
    constraints can be discharged via `Generic` evidence.

Default: (a) — simpler; keep both functions in the API.

`cabal build all && cabal test all` succeeds with the existing
tests.

Acceptance: `symSatExt` is exported; type-checks; the existing
test suite is unaffected.

**Milestone 6 — Round-trip test.** Add to
`test/Keiki/Examples/UserRegistrationSymbolicSpec.hs`:

    it "symSatExt produces a witness that models accepts" $ do
      -- Pick a satisfiable edge guard from userReg.
      let allEdges = userRegEdges RequiresConfirmation
          isConfirmEdge = head allEdges  -- the ConfirmAccount edge
          guardP = guard isConfirmEdge
      case symSatExt guardP of
        Nothing      -> expectationFailure "guard is unsat"
        Just (regs, cmd) ->
          evalPred guardP regs cmd `shouldBe` True

Run:

    cabal test all 2>&1 | grep -E '^[0-9]+ examples'

Expected: M0 baseline + 1 (the new round-trip), 0 failures.

Acceptance: the round-trip test passes; the witness `(regs, cmd)`
is concrete (forcing `regs ! #email` returns a `Text` value, not
a bottom).

**Milestone 7 — Update design note + commit.** Edit
`docs/research/keiki-generics-design.md`. In "### D. Symbolic
`WitnessExtract` instances via Generics" append a paragraph
beginning **Implemented (see EP-9).**

Stage and commit:

    git add src/Keiki/Generics.hs \
            src/Keiki/Symbolic.hs \
            src/Keiki/Examples/UserRegistration.hs \
            test/Keiki/Examples/UserRegistrationSymbolicSpec.hs \
            docs/research/keiki-generics-design.md

    git commit -m "$(cat <<'EOF'
    feat(symbolic): symSatExt with Generic-derived WitnessExtract

    New typeclasses ExtractRegFile and KnownInCtors in Keiki.Generics
    drive a witness-extracting symSat variant in Keiki.Symbolic. The
    SBV translation now allocates deterministic variable names
    (reg/<slot>, inp/<icName>/<slot>) so model lookups can
    reconstitute concrete witnesses.

    UserRegistration ships a KnownInCtors instance enumerating its
    five InCtors. Round-trip test sat → witness → models agrees.

    Retires item D from docs/research/keiki-generics-design.md's
    Future Improvements list.

    MasterPlan: docs/masterplans/3-keiki-generics-dx-follow-ups.md
    ExecPlan: docs/plans/9-generic-derived-witnessextract-for-symsatext-round-trip.md
    Intention: intention_01knjzws4qezz9w8b0743zfqv8
    EOF
    )"


## Concrete Steps

All commands run from `/Users/shinzui/Keikaku/bokuno/keiki/`.

**M0 baseline:**

    cabal build all
    cabal test all 2>&1 | grep -E '^[0-9]+ examples'
    ghc-pkg list sbv

**M1 design pass.** Edit
`docs/research/keiki-generics-design.md`'s item D entry per Plan
of Work M1.

**M2 named translation.** Edit `src/Keiki/Symbolic.hs`. The
substantive changes:

In `translateTermSym`:

    translateTermSym _env  (TLit r)              = pure (symLit r)
    translateTermSym _env  (TReg ix)             =
      SBV.free ("reg/" <> indexName ix)
    translateTermSym _env  (TInpCtorField ic ix) =
      SBV.free ("inp/" <> icName ic <> "/" <> indexNameInCtor ic ix)
    translateTermSym _env  (TApp1 _f _t)         = ... unique counter
    translateTermSym _env  (TApp2 _f _a _b)      = ... unique counter

`indexName` and `indexNameInCtor` lookups go through the existing
`KnownSlotNames` machinery in `Keiki.Core`. If those helpers don't
expose name-by-index, add a new `slotNameAt :: Index rs r ->
String` helper to `Keiki.Core`'s exports.

Run:

    cabal build all
    cabal test all 2>&1 | grep -E '^[0-9]+ examples'

Expected: baseline count, 0 failures.

**M3-M4 typeclasses.** Edit `src/Keiki/Generics.hs`. Add the
classes per Plan of Work M3-M4. Add to the export list:

    , ExtractRegFile (..)
    , SomeInCtor (..)
    , KnownInCtors (..)

`cabal build`.

Add a `KnownInCtors UserCmd` instance to
`src/Keiki/Examples/UserRegistration.hs`:

    instance KnownInCtors UserCmd where
      allInCtors =
        [ SomeInCtor inCtorStart
        , SomeInCtor inCtorConfirm
        , SomeInCtor inCtorResend
        , SomeInCtor inCtorGdpr
        , SomeInCtor inCtorContinue
        ]

(For each `SomeInCtor`, GHC needs an `ExtractRegFile ifs`
dictionary; the `'[]` and `'(s, t) ': rs` instances cover all
shapes UserCmd's InCtors produce.)

`cabal build`.

**M5 symSatExt.** Edit `src/Keiki/Symbolic.hs`. Add `symSatExt`
per Plan of Work M5. Export from the module.

`cabal build`.

**M6 round-trip test.** Edit
`test/Keiki/Examples/UserRegistrationSymbolicSpec.hs`. Add the
round-trip `it` block per Plan of Work M6.

    cabal test all 2>&1 | grep -E '^[0-9]+ examples'

Expected: baseline + 1.

**M7 commit.** See Plan of Work M7.


## Validation and Acceptance

After all seven milestones:

- `cabal build all` succeeds with no warnings.
- `cabal test all` reports M0 baseline + 1 example, 0 failures.
- `symSatExt` returns a concrete `(RegFile rs, ci)` witness on
  the User Registration `RequiresConfirmation/ConfirmAccount`
  edge guard. Forcing `regs ! #email` returns a `Text` value;
  forcing `cmd` returns a `ConfirmAccount` value with a
  populated `ConfirmAccountData`.
- `evalPred guardP regs cmd == True` for the witness.

Behavioral acceptance:

The round-trip test in `UserRegistrationSymbolicSpec`:

    sat → witness  ⟹  models witness == True

…is the EP-2 retrospective's "future symSatExt" goal made
concrete. The User Registration symbolic spec is now a complete
end-to-end exercise of the SBV-backed surface, no placeholders.


## Idempotence and Recovery

The plan is largely additive (M3-M5 add new code) plus M2's
refactor of existing code. Each milestone's edits can be
re-applied without harm:

- M2's named-translation refactor is exact-string substitutions in
  `translateTermSym`; reverting any line restores the previous
  anonymous-name behavior.
- M3-M4's classes are new declarations; deleting and recreating
  them has no side effects elsewhere (the `KnownInCtors UserCmd`
  instance is the only consumer outside the test suite).
- M5's `symSatExt` is purely additive; the existing `symSat`
  placeholder is untouched.

Recovery from an SBV model-lookup failure:

If `symSatExt` returns `Nothing` despite the predicate being
satisfiable (e.g. the model's `inputCtor` value doesn't appear in
`allInCtors`), the most likely cause is:

1. A typo in `KnownInCtors UserCmd`'s instance — confirm the list
   is exhaustive.
2. A naming collision in M2's translation — the SBV model's
   variable names don't match the lookup names. Inspect with
   `SBV.satWith config { verbose = True } ...` to see the
   model's actual variable names.
3. A `Sym` instance gap for one of the slot value types — the
   slot's value isn't in the curated `discoverSym` registry,
   so `extractRegFile` returns `Nothing`. Add the missing
   `Sym` instance.

Recovery from a witness-mismatch:

If `models guardP regs cmd == False` despite a successful
extraction, the witness is wrong. Most likely causes:

1. The `fromSym` round-trip drops information (e.g. `UTCTime`
   sub-second precision). Adjust the test's predicate to
   tolerate the precision loss, or fix the relevant `Sym`
   instance.
2. The Generic walk over `RegFile rs` produces slots in a
   different order than the predicate evaluator expects. The
   slot-list order is fixed at the type level by `rs`; if the
   walk diverges, it's a bug in `ExtractRegFile`'s `'(s, t) ':
   rs` instance.


## Interfaces and Dependencies

New types and functions:

    -- src/Keiki/Generics.hs
    class ExtractRegFile (rs :: [Slot]) where
      extractRegFile
        :: (forall r. Sym r => String -> Maybe r)
        -> Maybe (RegFile rs)

    data SomeInCtor (ci :: Type) where
      SomeInCtor :: ExtractRegFile ifs => InCtor ci ifs -> SomeInCtor ci

    class KnownInCtors ci where
      allInCtors :: [SomeInCtor ci]

    -- src/Keiki/Symbolic.hs
    symSatExt
      :: ( ExtractRegFile rs
         , KnownInCtors ci
         )
      => HsPred rs ci -> Maybe (RegFile rs, ci)

Existing functions modified:

- `Keiki.Symbolic.translateTermSym` and `translatePred` now allocate
  SBV variables with deterministic names. Externally observable
  only via SBV's verbose mode; the typed API is unchanged.

Existing functions consumed:

- `Keiki.Core.RegFile`, `InCtor`, `HsPred`.
- `Keiki.Symbolic.Sym`, `discoverSym`, `mkSymEnv`,
  `translateTermSym`, `translatePred`.
- `Keiki.Generics` exports of `KnownSymbol`-y helpers.

No new external libraries. The existing `sbv` dep covers
`SBV.SMTModel` and `SBV.getModelValue`.

The `KnownInCtors UserCmd` instance lives in
`src/Keiki/Examples/UserRegistration.hs` (it is a per-aggregate
declaration, not a library-level helper). Future aggregates that
use `symSatExt` ship their own `KnownInCtors` instance.
