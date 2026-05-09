# SBV-backed BoolAlg design — symbolic emptiness, satisfiability, and single-valuedness (EP-2 of MasterPlan 2)

This note pins the v2 retirement of the v1 best-effort `BoolAlg` instance
on `HsPred` and the v1 placeholder `sat`/`isBot` methods. It is the
hand-off contract for `docs/plans/6-sbv-backed-boolalg-instance-for-symbolic-emptiness.md`'s
M2-M7 milestones.

The goal is to upgrade `isBot`, `sat`, and the derived `isSingleValued`
from "syntactic placeholder / always Nothing / Hedgehog property" to a
real symbolic decision procedure dispatched to an SMT solver. After
EP-2, asking "are these two edge guards mutually exclusive?" is a
mechanical question with a precise answer; the synthesis-§7 invariant
that edge guards form an *effective* Boolean algebra is honored at v2
just as the synthesis note (§7) and the direction-C note (§5
"SMT-backed phase") sketched.

This note is the design record. It picks every load-bearing decision
EP-2's M2 through M7 require and explains why. Each decision is named
inline so the implementing milestones can refer back by section
heading.


## Context recap (one paragraph)

The v1 prototype's `BoolAlg (HsPred rs ci) (RegFile rs, ci)` instance in
`src/Keiki/Core.hs` is honest about its scope: `sat _ = Nothing` and
`isBot PBot = True; isBot _ = False`. The v1 single-valuedness check is
correspondingly best-effort (the DSL note's "isSingleValued" section in
`docs/research/effects-boundary.md` §5 explicitly names it as such). EP-1
of MasterPlan 2 retired the input-side opacity (`TInpField`) and the
hand-written `OPack` inverse, leaving the `Term` constructor set
structural: `TLit`, `TReg`, `TInpCtorField` (with explicit `InCtor`
metadata), `TApp1`, `TApp2`. EP-2 inherits that surface and translates
it to SBV.


## Goal in one paragraph

After this milestone, `Keiki.Symbolic` exports a `BoolAlg (SymPred rs
ci) (RegFile rs, ci)` instance whose `isBot` answers symbolically and
whose `sat` reports satisfiability via SBV. A new
`isSingleValuedSym :: SymTransducer phi rs s ci co -> Bool` walks every
vertex's pairwise edge-guard conjunctions and asks `isBot` of each.
For the User Registration aggregate, every pair is unsat and
`isSingleValuedSym userReg == True` — the v1 limitation noted in EP-4
is gone.


## Survey: solver choice

Three candidates fall out of the v1 DSL note's "v2 SBV-backed BoolAlg
instance" hint and the direction-C note's §5 SMT-backed phase sketch.

### Candidate 1 — SBV (`Data.SBV`) — recommended

SBV ("SMT-Based Verification") is Levent Erkok's mature Haskell library
that compiles symbolic-value Haskell expressions to SMT-LIB and
dispatches to a back-end solver (z3 by default). The library is on
Hackage as `sbv` (latest 14.0 at time of writing; supports `base
>=4.19.2 && <5`, which covers GHC 9.10.3's base 4.20.x). The library's
central operations:

- `sat :: Provable a => a -> IO SatResult` — try to find a model.
- `prove :: Provable a => a -> IO ThmResult` — try to prove the claim
  has no counter-example (i.e. `sNot p` is unsat).
- `isVacuous :: Provable a => a -> IO Bool` — is the claim
  unsatisfiable.
- Symbolic-value types: `SBool`, `SInteger`, `SInt32`, `SString`,
  `SChar`, `SArray k v`, etc. The `Symbolic` monad allocates fresh
  variables via `free :: SymVal a => String -> Symbolic (SBV a)`.
- Concrete extraction from a model: `getModelValue :: SymVal a =>
  String -> SatResult -> Maybe a`.

SBV pulls a runtime requirement on the z3 binary in `PATH`. On macOS:
`brew install z3`. On Debian: `apt install z3`. The library raises an
exception if the solver is missing or returns an error.

**SBV is not in the local `mori` registry.** Confirmed by `mori
registry search sbv` returning "No projects matching 'sbv'". The survey
of SBV's API in this note is grounded in the package's Hackage
description (`cabal info sbv`) and its prior use in keiki's design notes
(direction-C §5). The implementation milestones rely on SBV's published
documentation; readers who need source-level grounding should clone
`https://github.com/LeventErkok/sbv` outside the keiki tree.

### Candidate 2 — `z3-haskell` (direct z3 bindings)

Direct C-level bindings to z3. Lighter than SBV but every query
requires explicit handle management, AST construction, and solver-state
plumbing. SBV does this work in its compilation pipeline; replicating
it here is reinventing infrastructure for no gain.

**Rejected.** The plumbing cost is real and SBV already supports z3 as
its default backend.

### Candidate 3 — Hand-rolled enumeration

For finite slot/input types, enumerate all `(RegFile rs, ci)` values and
`evalPred` the predicate. Sound but only feasible if every slot is
finite. The User Registration register file's `Email` and
`ConfirmationCode` are `Text`, and `UTCTime` is unbounded. Hedgehog
generators would fall back to property-test semantics, which is what
v1 already does.

**Rejected.** Incomplete on the User Registration aggregate; falls
back to the v1 best-effort behavior we are trying to retire.

### Decision: SBV

EP-2 uses SBV. Version constraint: `^>=11.7` (the lowest version still
compatible with GHC 9.10.3 at time of writing — newer is fine; M2
verifies the resolver picks a compatible major). Default solver: z3,
installed at runtime; the library will fail loudly if z3 is missing.


## Cabal flag — hard dependency or optional?

Two choices:

- **Hard requirement.** SBV is in `keiki.cabal`'s `library`
  `build-depends`. `cabal build` requires SBV to resolve. `cabal test`
  requires z3 in `PATH` to run the symbolic tests.
- **Optional behind a cabal flag.** `cabal build` works without SBV;
  `Keiki.Symbolic` is built only when the `symbolic` flag is on (or
  off; default-on or default-off depending on policy).

### Decision: hard requirement

The synthesis-§7 invariant of single-valuedness is load-bearing for the
formalism. Making it optional would split the test matrix into "with
SBV" and "without SBV" code paths and create an unexercised default
build. The v1 best-effort behavior is documented as v1; v2 is the
upgrade. The cost is one transitive dep on SBV plus one runtime
requirement on z3.

A reader in an environment that cannot install z3 should pin to the
v1 commit (where `BoolAlg HsPred` is the only instance and `sat _ =
Nothing` / `isBot _ = False`-on-non-PBot is documented).


## Module placement: a new `Keiki.Symbolic`

Two valid choices: extend `Keiki.Core` or carve `Keiki.Symbolic`.

### Decision: `Keiki.Symbolic`

A separate module is preferred because:

1. **Code organization.** `Keiki.Core` is the v1 pure surface. SBV
   integration is the v2 *symbolic* surface. Keeping them separate
   matches the EP-4 retrospective's framing.
2. **Re-exports.** `Keiki.Symbolic` re-exports `Keiki.Core` so users
   import only `Keiki.Symbolic` to get the union.
3. **Cabal organization.** `keiki.cabal` adds `Keiki.Symbolic` to
   `exposed-modules` and lists `sbv` in `build-depends`.
4. **Future split.** If the SBV dep ever needs to live in a sub-package
   (`keiki-symbolic`), the boundary already exists.

The module name *does not* mean the code paths are optional — they are
mandatory per the previous section. It is purely an organizational
choice.


## Symbolic representation typeclass

We need to lift Haskell values to SBV's symbolic universe and decode
SBV concrete values back. The cleanest shape is a typeclass that pins
the SBV repr type and provides the round-trip:

    class SymVal (SymRep a) => Sym a where
      type SymRep a :: Type
      toSym   :: a -> SymRep a
      fromSym :: SymRep a -> a

The `SymVal (SymRep a)` superclass is SBV's own typeclass — it provides
`literal :: a -> SBV a` and `free :: String -> Symbolic (SBV a)` and
`unliteral :: SBV a -> Maybe a`. So pinning `SymRep a` automatically
gives us all the SBV machinery for the representation type.

Instances required by EP-2:

    instance Sym Bool         where { type SymRep Bool         = Bool;         toSym = id; fromSym = id }
    instance Sym Int          where { type SymRep Int          = Integer;      toSym = fromIntegral; fromSym = fromIntegral }
    instance Sym Integer      where { type SymRep Integer      = Integer;      toSym = id; fromSym = id }
    instance Sym Text         where { type SymRep Text         = String;       toSym = T.unpack; fromSym = T.pack }
    instance Sym UTCTime      where { type SymRep UTCTime      = Integer;      toSym = posixToInt; fromSym = intToPosix }

`Email` and `ConfirmationCode` are `type` aliases for `Text` — no
separate instance needed.

Helpers:

    symLit  :: Sym a => a -> SBV (SymRep a)
    symLit   = literal . toSym

    symFree :: Sym a => String -> Symbolic (SBV (SymRep a))
    symFree  = free


## Term and HsPred translation

The translation walks `Term rs ci r` and `HsPred rs ci` structurally,
producing SBV expressions in the `Symbolic` monad. The walk is total
modulo one remaining opaque escape hatch (`TApp1`/`TApp2` outside a
curated whitelist) which becomes a free symbolic variable (i.e.
"unknown to the solver"). The `HsPred` side has no escape hatches
since EP-17 of MasterPlan 6 retired `PMatchC` (2026-05-02).

### Translation environment

The translation needs:

- A symbolic register file: one fresh `SBV (SymRep r)` per slot.
- A symbolic input constructor tag: one fresh `SString`. Used to encode
  `PInCtor` (see below) and to permit constructor-mutual-exclusion to
  be discharged by the solver.
- Per-`InCtor`-per-field symbolic value cache: each unique
  `(icName, slotName)` pair maps to one fresh SBV var of the field's
  representation type. Caching ensures two reads of the same
  `(InCtor, slot)` translate to the same SBV var.
- A registry of `Sym`-typed slots so we can decode model values back
  for witness extraction.

Concretely:

    data SymEnv rs ci = SymEnv
      { seRegFile      :: SymRegFile rs
        -- ^ Per-slot fresh SBV vars + decoders.
      , seInputCtor    :: SBV String
        -- ^ One fresh tag for the input constructor name.
      , seInpFieldCache :: IORef (Map (String, String) SomeSBV)
        -- ^ Per-(icName, slotName) cache of SBV vars + decoders.
      }

`SymRegFile rs` is itself a heterogeneous tuple of SBV vars, indexed by
the slot list. We carry a pre-allocated SBV var per slot so that
register-read translation is a constant-time lookup.

The cache uses an `IORef` because `Symbolic` is `SymbolicT IO`. The
`IORef` is created at the top of each translation and discarded after
the SBV call.

### Term translation rules

For each `Term rs ci r`:

- `TLit r` — `pure (symLit r)`. Requires `Sym r`.
- `TReg ix` — `pure (lookupSlot ix env.seRegFile)`. Requires the slot's
  type to be `Sym`-able.
- `TInpCtorField ic ix` — query the per-`(icName ic, slotName ix)`
  cache; allocate a fresh SBV var on cache miss. Returns the cached
  var. Requires the field's type to be `Sym`-able.
- `TApp1 f t` — opaque function. Translation produces a fresh free
  variable of the result type and the predicate the term participates
  in becomes "soft" (the solver is free to pick any value). Loses
  precision but does not corrupt soundness.
- `TApp2 f a b` — same as `TApp1`.

There is a curated whitelist for `TApp1`/`TApp2`-with-SBV-friendly-ops
(e.g. integer addition, equality, string concatenation). EP-2 does not
require it for the User Registration smoke test (no `TApp1`/`TApp2` in
that aggregate). The whitelist is **out of scope**; the fallback is
"fresh free variable, lose precision."

### HsPred translation rules

The current `HsPred rs ci` set:

- `PTop` → `sTrue`.
- `PBot` → `sFalse`.
- `PAnd p q` → `(.&&)` of translations.
- `POr p q` → `(.||)` of translations.
- `PNot p` → `sNot` of translation.
- `PEq a b` — translate both terms. If both translations succeed, emit
  `(.==)`. If either has a non-`Sym`-able type, fall back to a fresh
  `SBool` (lose precision).
- `PInCtor ic` → `seInputCtor .== literal (icName ic)`.

### Historical: the PMatchC fallback (retired by EP-17 of MP-6, 2026-05-02)

The v1 `HsPred` carried a `PMatchC :: (ci -> Bool) -> HsPred rs ci`
escape hatch over an opaque Haskell function. EP-2 of MasterPlan 2
(this design note's home) added `PInCtor` so the User Registration
aggregate's constructor guards
(`isStart`/`isConfirm`/`isResend`/`isGdpr`/`isContinue`) could be
authored structurally and the SBV translation could decide
constructor mutual exclusion symbolically:

    isStart    = matchInCtor inCtorStart
    isConfirm  = matchInCtor inCtorConfirm
    isResend   = matchInCtor inCtorResend
    isGdpr     = matchInCtor inCtorGdpr
    isContinue = matchInCtor inCtorContinue

Translation: `PInCtor ic` → `seInputCtor .== literal (icName ic)`. The
conjunction `isConfirm AND isResend` translates to
`seInputCtor == "ConfirmAccount" AND seInputCtor == "ResendConfirmation"`,
which SBV's z3 dispatches and recognizes as unsat in microseconds. ✓

EP-2 deferred *retirement* of `PMatchC` to MasterPlan 6, where it
would have remained available as a v1-grandfathered escape hatch
trading symbolic precision for ergonomics. EP-17 of MP-6
(`docs/plans/17-retire-pmatchc-and-matchcmd-from-keiki-core.md`)
removed `PMatchC` and `matchCmd` entirely on 2026-05-02 — the survey
in `docs/research/v1-escape-hatch-retirements-design.md` confirmed
zero aggregate uses, so the back-compat hatch had no users to
preserve. The `translatePred` function now handles the seven
remaining `HsPred` constructors exhaustively and the SBV side has no
predicate-level fallback.


## Purity model: `unsafePerformIO`

SBV's analysis methods (`sat`, `prove`, `isVacuous`) are in `IO` because
they shell out to z3. The `BoolAlg` typeclass methods (`sat`, `isBot`)
are pure. Three options:

- **Wrap with `unsafePerformIO` (recommended).** SBV's queries are
  deterministic given the same predicate (the solver is referentially
  transparent for our use case — same predicate same answer modulo
  unknown), and the witness extraction is total. `unsafePerformIO`
  with a `NOINLINE` pragma on each wrapper is semantically defensible.
- **Change `BoolAlg` to be `MonadIO m`-parameterized.** Heavy; ripples
  through `delta`, `omega`, `step`, `reconstitute`, `applyEvent`,
  `models`. Out of proportion to the value.
- **Provide a separate `BoolAlgIO` class.** Forks the surface; users
  have to choose between pure and IO instances at call sites.

### Decision: `unsafePerformIO` with NOINLINE

Each pure wrapper (`isBot`, `sat`) is annotated with
`{-# NOINLINE symIsBot #-}` so GHC does not inline-and-reorder the IO
action. The wrappers are documented as "deterministic given the
predicate; safe under `unsafePerformIO`". The cost of an SBV call
(~10ms warm, mostly solver dispatch) is paid lazily and at compile-or-
test-time, not in production hot paths.

Pseudocode:

    {-# NOINLINE symIsBot #-}
    symIsBot :: HsPred rs ci -> Bool
    symIsBot p = unsafePerformIO $ do
      result <- SBV.isVacuous (do
        env <- mkSymEnv
        sb  <- translatePred env p
        pure sb)
      pure result


## SymPred wrapper

The new instance lives on a wrapper so v1's `BoolAlg HsPred` instance
stays unchanged:

    newtype SymPred rs ci = SymPred (HsPred rs ci)

    instance BoolAlg (SymPred rs ci) (RegFile rs, ci) where
      top                       = SymPred PTop
      bot                       = SymPred PBot
      conj (SymPred p) (SymPred q) = SymPred (PAnd p q)
      disj (SymPred p) (SymPred q) = SymPred (POr  p q)
      neg  (SymPred p)             = SymPred (PNot p)
      models (SymPred p) (regs, ci) = evalPred p regs ci
      sat   (SymPred p)             = symSat   p
      isBot (SymPred p)             = symIsBot p

The instance carries a constraint-set requirement on `rs` and `ci` —
enough `Sym` instances to allow translation. The class signature
itself doesn't admit per-instance constraints, so the constraint
appears on the helper functions instead and is propagated by
GHC-derived dictionary inference. Concretely, the `Sym` instances must
be in scope for every slot type the predicate touches and for every
field of every `InCtor` referenced by `PInCtor`/`TInpCtorField`. For
User Registration: `Sym Text`, `Sym UTCTime`. Both are provided by
`Keiki.Symbolic`.


## Sat witness extraction

SBV's `sat` returns a `SatResult` carrying a model: a map from
variable names to concrete `CV` (Concrete Value) tags. To produce a
`(RegFile rs, ci)` from the model we need:

1. For each register slot, look up its model value (or use a default
   when the model leaves it unconstrained), decode via `fromSym`, and
   reassemble a `RegFile rs`.
2. For the input symbol, look up `seInputCtor`'s model value, find the
   matching `InCtor` (by `icName`), look up each of its fields' model
   values, decode, and call `icBuild`.

This is non-trivial. The `BoolAlg` typeclass forces `sat :: phi -> Maybe
a` — no extra context. Two ways forward:

- **Bundle the context with the predicate (heavy).** The `SymPred`
  newtype carries an extraction context. Every helper has to thread it.
- **Return a placeholder witness from the typeclass `sat`; expose a
  separate `symSatExt` for full extraction (recommended).** The
  typeclass `sat` returns `Just (regs, ci)` whenever SBV says sat,
  using `unsafeWitness` defaults. The defaults are documented as "do
  not call `models p witness`; use `symSatExt` for that." `symSatExt`
  takes an explicit `WitnessExtract rs ci` typeclass instance and
  returns a real witness; tests call `symSatExt` for the round-trip
  check.

### Decision: `unsafeWitness` defaults + `symSatExt`

The class `sat` reports satisfiability; full witness extraction is the
job of `symSatExt`. This matches v1's convention that `BoolAlg`'s `sat`
is a coarse-grained "is there at least one witness" rather than a
constructive returner. v1's `Nothing` becomes v2's `Just (?, ?)`; the
upgrade is the *answer* (now precise), not the *form* (still `Maybe`).

Concretely:

    {-# NOINLINE symSat #-}
    symSat :: HsPred rs ci -> Maybe (RegFile rs, ci)
    symSat p = unsafePerformIO $ do
      result <- SBV.sat (do
        env <- mkSymEnv
        sb  <- translatePred env p
        pure sb)
      case result of
        SatResult (Satisfiable {}) -> pure (Just unsafeWitness)
        _                          -> pure Nothing

    -- Used as a placeholder when the caller did not provide a
    -- WitnessExtract instance; safe to inspect *only* at the
    -- "is there a witness" level.
    unsafeWitness :: (RegFile rs, ci)
    unsafeWitness = (error "Keiki.Symbolic.sat: witness placeholder; use symSatExt for the real witness", error "...")

    symSatExt
      :: forall rs ci. WitnessExtract rs ci
      => HsPred rs ci -> IO (Maybe (RegFile rs, ci))

`WitnessExtract` is a typeclass per (`rs`, `ci`) pair providing the
default register file, the constructor-name dispatch, and the field
value extraction. Tests that need full witnesses provide explicit
instances for `'[]`/`()` (trivial: `RNil`/`()`) and for
`UserRegRegs`/`UserCmd` (writes by hand).

This trade-off keeps the typeclass-`sat` shape fixed and the EP-2
acceptance tests achievable. M5 verifies satisfiability on simple
cases via the typeclass; M7 verifies witness extraction on the User
Registration aggregate via `symSatExt`.


## isSingleValuedSym

The function lives in `Keiki.Symbolic`. Signature:

    isSingleValuedSym
      :: forall phi rs s ci co.
         (BoolAlg phi (RegFile rs, ci), Bounded s, Enum s)
      => SymTransducer phi rs s ci co
      -> Bool

It walks every vertex's outgoing edges; for every distinct pair, asks
`isBot (guard e1 \`conj\` guard e2)`. Returns `True` iff all pairs are
bot. This is `BoolAlg`-polymorphic so it works with any precise `isBot`
implementation; the speed of the answer depends on the chosen instance
(SymPred → SBV; HsPred → fast but always `False` for non-trivial).

Implementation:

    isSingleValuedSym t = all vertexSV [minBound .. maxBound]
      where
        vertexSV s =
          let es    = edgesOut t s
              pairs = [ (e1, e2)
                      | (i, e1) <- zip [0..] es
                      , (j, e2) <- zip [0..] es
                      , i < j
                      ]
          in all (\(e1, e2) -> isBot (guard e1 `conj` guard e2)) pairs

For User Registration:

- `PotentialCustomer` has 1 edge: vacuously single-valued.
- `Registering` has 1 edge: vacuously single-valued.
- `RequiresConfirmation` has 3 edges. Pairs:
  - (Confirm, Resend): `(matchInCtor inCtorConfirm AND eqCheck) AND
    matchInCtor inCtorResend` ⇒ `inputCtor == "ConfirmAccount" AND
    inputCtor == "ResendConfirmation"` ⇒ unsat. ✓
  - (Confirm, GDPR): same shape, unsat. ✓
  - (Resend, GDPR): same shape, unsat. ✓
- `Confirmed` has 1 edge: vacuously single-valued.
- `Deleted` has 0 edges: vacuously single-valued.

Verdict: `isSingleValuedSym (SymPred-wrapped userReg) == True`.

Wait — `userReg :: SymTransducer (HsPred ...) ...`. The
`isSingleValuedSym` call site needs the `SymPred` instance. Two ways:

- **Use a coercion adapter.** Wrap the transducer's edges so their
  guards are `SymPred`-ed. A small helper `withSymPred :: SymTransducer
  (HsPred rs ci) rs s ci co -> SymTransducer (SymPred rs ci) rs s ci
  co` does this by mapping `SymPred` over each edge's `guard`.
- **Make `userReg` polymorphic in the predicate carrier.** Rewrite the
  example to use `BoolAlg phi a => phi`-style functions throughout.
  Heavier than the adapter.

### Decision: `withSymPred` adapter

A small wrapper `withSymPred` re-tags the transducer's guards. The
example stays in `HsPred`-shape; the symbolic spec wraps with
`withSymPred` before calling `isSingleValuedSym`. This means the v1 and
v2 instances coexist on the same example without source-level changes.


## Test plan

Tests live in `test/Keiki/SymbolicSpec.hs` (translation, BoolAlg ops,
sat, isBot, isSingleValuedSym on a synthetic) and
`jitsurei/test/Jitsurei/UserRegistrationSymbolicSpec.hs` (the User
Registration symbolic spec).

### Translation tests (M3)

- `translatePred PTop` ⇒ a tautology under SBV's `prove`.
- `translatePred PBot` ⇒ unsat under SBV's `sat`.
- `translatePred (PEq (TLit 5 :: Term '[] () Int) (TLit 5))` ⇒ sat;
  `translatePred (PEq (TLit 5) (TLit 6))` ⇒ unsat.
- `translatePred (PInCtor inCtorStart)` over a `UserCmd`-typed env ⇒
  `seInputCtor .== "StartRegistration"`.
- `translatePred (PAnd (PInCtor inCtorStart) (PInCtor inCtorConfirm))`
  ⇒ unsat.

### BoolAlg ops tests (M4)

- `top /= bot` (structurally distinct).
- `conj p q` is structural `PAnd`-wrapping; `disj` is `POr`-wrapping;
  `neg` is `PNot`-wrapping.

### Symbolic sat / isBot tests (M5)

- `isJust (sat (top :: SymPred '[] ()))` ⇒ True.
- `isNothing (sat (bot :: SymPred '[] ()))` ⇒ True.
- `isJust (sat (SymPred (PEq (TLit 5) (TLit 5)) :: SymPred '[] ()))` ⇒
  True; `isNothing (sat (SymPred (PEq (TLit 5) (TLit 6))))` ⇒ True.
- `isBot (bot :: SymPred '[] ())` ⇒ True; `isBot (top :: SymPred '[]
  ())` ⇒ False; `isBot (SymPred (PEq (TLit 5) (TLit 6))) ⇒ True`.

### Symbolic isSingleValued tests (M6)

A synthetic 2-edge transducer with mutually exclusive guards (e.g. two
`PInCtor`s for distinct constructors) ⇒ `isSingleValuedSym ==
True`. A synthetic 2-edge transducer with overlapping guards (`top`
and `top`) ⇒ `isSingleValuedSym == False`.

### User Registration tests (M7)

- `isSingleValuedSym (withSymPred userReg) == True`.
- `symSatExt (PEq (inpConfirm #confirmCode) (lit "abc123"))` returns
  `Just (regs, ConfirmAccount d)` where `d.confirmCode == "abc123"`.

The existing User Registration tests (5 events, reconstitute,
checkHiddenInputs) must continue to pass after the helpers migrate to
`matchInCtor`.


## Failure modes and recovery

- **z3 not in PATH.** SBV raises `Couldn't find solver "z3" in PATH or
  configured location`. The user installs z3 (`brew install z3` on
  macOS; `apt install z3` on Debian) and re-runs.
- **Solver returns `Unknown`.** SBV's `sat`/`prove` may return
  `Unknown` for theories outside z3's decidable fragment. Conservative
  treatment: `isBot` returns `False` (don't claim emptiness without a
  proof); `sat` returns `Nothing`. Document as a known limitation.
  None of the User Registration translations hit this; the path is
  reserved for future predicates.
- **Solver timeout.** SBV's default has no timeout. M2 sets a
  conservative 5-second timeout via `SBV.SatConfig`'s `timeOut` field.
  Timeouts are treated as `Unknown`.
- **Translation refuses (opaque TApp1/TApp2).** The translation
  emits a fresh `SBool` and the test loses precision. Not a runtime
  failure; documented as a known limitation. (`PMatchC` was the
  other historical refusal site; retired by EP-17 of MP-6 on
  2026-05-02.)
- **Unsupported slot type (no `Sym` instance).** Compile-time error
  pointing at the missing instance. The user adds a `Sym` instance or
  reshapes the slot.


## Out of scope (deferred to later MasterPlans)

- Static check on `unsafeCombine` — separate cleanup, owned by EP-18
  of MP-6.
- Curated `TApp1`/`TApp2` whitelist (integer arithmetic, string ops) —
  the User Registration aggregate doesn't need it.
- Parallel solver backends (CVC4, Boolector) — z3 is enough for v2.
- A constraint-aware `TInpCtorField` translation that conditionally
  asserts `seInputCtor == icName ic` — out of scope; the simpler
  unconditional fresh-var translation suffices for the User
  Registration smoke test, and the cost of getting it wrong is loss of
  precision (some `isBot` queries return `False` when they should
  return `True`), not unsoundness.


## Open questions for future work

- Witness extraction for arbitrary `(rs, ci)` pairs requires a
  hand-written `WitnessExtract` instance. A `Generic`-derived default
  would mechanize this; out of scope for v2.
- The `Symbolic` monad and `SymEnv` design uses an `IORef` cache; a
  monad-transformer approach (`StateT (Map ...) Symbolic`) might be
  cleaner. Defer until the API stabilizes.
- The `withSymPred` adapter is a stop-gap; a future API might
  parameterize the example aggregates over the predicate carrier.


## Implementation checklist (M2-M7)

This is the bridge to the EP-2 plan's milestones. Each milestone
corresponds to one section above.

**M2 — cabal dep.**

- Add `sbv ^>=11.7` to `keiki.cabal`'s `library` and test-suite
  `build-depends`.
- Document the runtime z3 requirement in a synopsis comment.
- Run `cabal build` to confirm resolution.

**M3 — translation.**

- Create `src/Keiki/Symbolic.hs` with `Sym` typeclass, instances for
  Bool/Int/Integer/Text/UTCTime, the `SymEnv` data, `translateTerm`,
  `translatePred`.
- Create `test/Keiki/SymbolicSpec.hs` with translation tests.
- Add `Keiki.Symbolic` to `keiki.cabal`'s `exposed-modules` and the
  spec to test-suite `other-modules`.

**M4 — SymPred + structural ops.**

- Define `newtype SymPred rs ci = SymPred (HsPred rs ci)`.
- Implement `top`/`bot`/`conj`/`disj`/`neg` and `models` on `SymPred`.
- Add `BoolAlg ops` tests in the spec file.

**M5 — symbolic sat / isBot.**

- Implement `symSat` and `symIsBot` with `unsafePerformIO`+`NOINLINE`.
- Tie into `SymPred`'s `BoolAlg` instance.
- Add sat/isBot tests in the spec file. Document z3-required behavior.

**M5b — `PInCtor` / `matchInCtor` cross-cut.**

- Add `PInCtor :: InCtor ci ifs -> HsPred rs ci` to `Keiki.Core`.
- Add `matchInCtor :: InCtor ci ifs -> HsPred rs ci` helper.
- Update `evalPred` for `PInCtor`.
- Migrate `Jitsurei.UserRegistration` `isStart`/`isConfirm`/...
  helpers to use `matchInCtor`. Existing tests must continue to pass.
- Document the cross-cut in the EP-2 Decision Log + MasterPlan
  Surprises & Discoveries.

**M6 — symbolic isSingleValued.**

- Define `isSingleValuedSym` and `withSymPred` in `Keiki.Symbolic`.
- Add a synthetic 2-edge isSingleValued test.

**M7 — User Registration symbolic spec.**

- Create `jitsurei/test/Jitsurei/UserRegistrationSymbolicSpec.hs`.
- Assert `isSingleValuedSym (withSymPred userReg) == True`.
- Assert a `symSatExt` round-trip on a register-read predicate.

**M8 — note updates + verdict.**

- Update `docs/research/dsl-shape-for-symbolic-register.md`'s
  predicate-carrier section to reflect the v2 BoolAlg upgrade.
- Update `docs/research/effects-boundary.md` §5
  ("isSingleValued") to reflect the upgrade.
- Write the EP-2 verdict in
  `docs/plans/6-sbv-backed-boolalg-instance-for-symbolic-emptiness.md`'s
  Outcomes & Retrospective.
- Mark MasterPlan EP-2 Complete; check off Progress.


## Closing summary

EP-2 lands four artifacts: a `Keiki.Symbolic` module, an SBV cabal
dep, a `PInCtor`/`matchInCtor` extension to `HsPred` (acknowledged
cross-cut into `Keiki.Core`), and a precise `isSingleValuedSym`. The
load-bearing test `isSingleValuedSym (withSymPred userReg) == True` is
the v2 retrospective's gate. The v1 best-effort `BoolAlg HsPred` stays
unchanged for back-compat; the v2 `BoolAlg SymPred` is the new
default for analyses.
