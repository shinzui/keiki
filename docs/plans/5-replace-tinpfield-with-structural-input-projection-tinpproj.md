---
id: 5
slug: replace-tinpfield-with-structural-input-projection-tinpproj
title: "Replace TInpField with structural input projection (TInpProj)"
kind: exec-plan
created_at: 2026-05-01T16:14:31Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
master_plan: "docs/masterplans/2-retire-v1-escape-hatches-in-pure-core-tinpproj-sbv-boolalg.md"
---

# Replace TInpField with structural input projection (TInpProj)

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

The keiki library's pure core in `src/Keiki/Core.hs` shipped a v1 prototype
under MasterPlan 1 that proved the symbolic-register transducer formalism
works end-to-end. The v1 verdict (`docs/plans/4-prototype-symbolic-register-core-with-user-registration-smoke-test.md`,
"Outcomes & Retrospective") names one explicit deviation from the
synthesis claim of "mechanically derived `apply`": the `OPack` output
constructor in `src/Keiki/Core.hs` carries a hand-written
`RegFile rs -> co -> Maybe ci` inverse field. The reason is that the v1
`Term` constructor set has only one input-reading constructor —
`TInpField :: (ci -> r) -> Term rs ci r` — and `TInpField` wraps an
opaque Haskell function that `solveOutput` cannot inspect. Without
inspectable input reads, `solveOutput` cannot mechanically rebuild a `ci`
from an observed `co` and falls back to user-supplied per-edge inverses.

After this plan is complete, the `Term` constructor set replaces
`TInpField` with a **structural input-projection** constructor that
carries enough information for `solveOutput` to walk the AST and
reconstruct `ci` mechanically. The hand-written inverse field on `OPack`
is gone. Every construction site in `Keiki.Examples.UserRegistration` and
`Keiki.Examples.UserRegistrationV0` is migrated. The end-to-end test
suite still passes (24 examples, 0 failures) but with no per-edge
`OPack`-inverse code anywhere in the User Registration aggregate. The
hidden-input check on the V0 unfixed schema still fires, with a
**narrower and more precise** warning that names the exact field of the
exact input constructor that the event payload fails to recover.

How a future contributor sees this work:

    cabal test
    # 24 examples, 0 failures.
    # The userReg definition contains zero hand-written inverses.
    # The userRegV0 hidden-input warning names "inCtorConfirm.confirmCode"
    # rather than "OPack field uses TInpField".

The user-visible win is a load-bearing one: the synthesis claim of
*mechanical* `apply` derivation now holds for v1. The remaining v2 escape
hatches (`OFn` opaque output and `PMatchC` opaque pattern guard) are out
of scope for this plan; they remain documented as v2 escape hatches.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be
documented here, even if it requires splitting a partially completed task
into two ("done" vs. "remaining"). This section must always reflect the
actual current state of the work.

- [x] **Milestone 0 — Verify prerequisites.** `cabal build` and
      `cabal test` succeed in the repo as-is (24 examples, 0 failures
      expected per EP-4 verdict). Three v1 design notes exist in
      `docs/research/`: `dsl-shape-for-symbolic-register.md`,
      `schema-evolution.md`, `effects-boundary.md`. The MasterPlan
      `docs/masterplans/2-retire-v1-escape-hatches-in-pure-core-tinpproj-sbv-boolalg.md`
      exists. *(2026-05-01 — confirmed: build is up-to-date, test
      suite reports `24 examples, 0 failures`, all four files present.)*
- [ ] **Milestone 1 — Survey + design note.** Survey the four candidate
      shapes for structural input projection (Lens, HasField/Generic,
      hand-rolled `InCtor` mirroring `WireCtor`, GHC.Generics-derived).
      Pick one, with rationale. Write a focused design note at
      `docs/research/tinpproj-design.md` (~300 lines) covering: the
      retirement target, the survey, the chosen shape, the mechanical
      `solveOutput` algorithm, the migration plan for User Registration,
      and the v1 API surface that stays vs. goes.
- [ ] **Milestone 2 — Add new constructor to `Term`.** Introduce
      `data InCtor ci fields` (mirroring `WireCtor co fields`). Add the
      new constructor to `Term` per the design note's name. Add a helper
      function. Update `evalTerm` to handle the new constructor.
      `cabal build` succeeds; `TInpField` and `inp` still exist in
      parallel. Add a unit test (`describe "TInpProj structural
      projection"`) exercising the new constructor in `test/Keiki/CoreSpec.hs`.
- [ ] **Milestone 3 — Update `solveOutput` and analyses for the new
      constructor.** `solveOutput` learns to walk an `OutFields` HList,
      identify all `TInpCtorField` entries, check they share a single
      `InCtor`, gather field values from the observed `co`, and call
      `icBuild` to reconstruct `ci`. Add a structural variant of the
      `outFieldsHaveInpField` analysis. Update `checkHiddenInputs` to
      emit a more precise warning shape. Add unit tests covering the
      mechanical inversion on a tiny `OPack` using the new constructor.
- [ ] **Milestone 4 — Drop the hand-written inverse field from
      `OPack`.** Change the `OPack` constructor signature to
      `OPack :: WireCtor co fields -> OutFields rs ci fields -> OutTerm rs ci co`
      (no third field). Update the `pack` helper. Compilation breaks at
      every `OPack` construction site in
      `src/Keiki/Examples/UserRegistration.hs` and
      `src/Keiki/Examples/UserRegistrationV0.hs`; this is intentional
      and is fixed in M5/M6.
- [ ] **Milestone 5 — Migrate `Keiki.Examples.UserRegistration` (V5).**
      Replace `inpStart`/`inpConfirm`/`inpResend`/`inpGdpr` with new
      helpers that build the new `Term` constructor. Define
      `inCtorStart`, `inCtorConfirm`, `inCtorResend`, `inCtorGdpr` ::
      `InCtor UserCmd ...`. Remove every hand-written inverse from
      `OPack` constructions. `cabal test` passes the V5 spec
      (`UserRegistrationSpec`).
- [ ] **Milestone 6 — Migrate `Keiki.Examples.UserRegistrationV0`.**
      Same migration as M5. Verify the V0 hidden-input demonstration
      still fires: `reconstitute userRegV0 canonicalLogV0 == Nothing`,
      and `checkHiddenInputs userRegV0` produces a warning that names
      the missing field of the missing constructor (more precise than
      the v1 "OPack field uses TInpField" warning). Update
      `test/Keiki/Examples/UserRegistrationV0Spec.hs` assertion text.
- [ ] **Milestone 7 — Remove `TInpField` and `inp` from the public
      API.** Delete the constructor from `Term`. Delete the `inp`
      helper. Delete the `termReadsInput` / `outFieldsHaveInpField`
      helpers (or rename them to track only the new constructor).
      Update `Keiki.Core`'s exports. `cabal build` and `cabal test`
      pass with no warnings about unused or unreachable code.
- [ ] **Milestone 8 — Update DSL design note; capture verdict.** Edit
      `docs/research/dsl-shape-for-symbolic-register.md`: update
      "Ergonomic verdict", "v1-only surfaces (flagged for v2
      retirement)", and "Prototype Implementation Checklist" sections to
      reflect TInpField/OPack-inverse retirement. Write the EP-1
      verdict in this plan's Outcomes & Retrospective. Cross-cut to the
      MasterPlan's Surprises & Discoveries and Outcomes & Retrospective.
- [ ] Commit at every milestone with `MasterPlan:`, `ExecPlan:`,
      `Intention:` git trailers.
- [ ] Update the MasterPlan's Exec-Plan Registry (status) and
      Progress (milestone checkboxes) on each milestone.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights
discovered during implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

(None yet — the M1 design milestone produces the first batch of
decisions.)


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at
completion. Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

This section is the orientation a beginner needs. A reader who finishes
this section knows: what `Keiki.Core` is, what the v1 `Term` constructor
set looks like and why it has an opaque `TInpField`, what the `OPack`
hand-written inverse does, what the User Registration aggregate
exercises, and what tests must keep passing.

### The repository and the build system

The keiki repository is a single-package Haskell library at
`/Users/shinzui/Keikaku/bokuno/keiki`. The cabal file is `keiki.cabal`
(GHC 9.10.3, `default-language: GHC2024`). Build with:

    cabal build

Test with:

    cabal test

The library exposes three modules:

    Keiki.Core
    Keiki.Examples.UserRegistration
    Keiki.Examples.UserRegistrationV0

The test suite (`test/Spec.hs` driven by hspec-discover) has three spec
files:

    test/Keiki/CoreSpec.hs
    test/Keiki/Examples/UserRegistrationSpec.hs
    test/Keiki/Examples/UserRegistrationV0Spec.hs

As of MasterPlan 1's completion the test suite is "24 examples, 0
failures."

### What `Keiki.Core` is

`src/Keiki/Core.hs` defines the pure symbolic-register transducer. The
key types (with their type-list kinds elided):

- `RegFile rs` — a heterogeneous list of typed slots indexed by a
  type-level list of `(Symbol, Type)` pairs. Constructors: `RNil`,
  `RCons`. Looked up via the GADT `Index rs r` (constructors `ZIdx`,
  `SIdx`) and the operator `(!) :: RegFile rs -> Index rs r -> r`.
- `Term rs ci r` — the closed expression language for register reads,
  input reads, literals, and pure combinators. Constructors: `TLit`,
  `TReg`, `TInpField`, `TApp1`, `TApp2`. **The retirement target of
  this plan is `TInpField`.**
- `Update rs ci` — the copyless update language. Constructors:
  `UKeep`, `USet`, `UCombine`. Smart constructor `combine` checks
  distinct targets; `unsafeCombine` skips the check.
- `OutTerm rs ci co` — the output expression language. Constructors:
  `OPack` (structural — but with a v1 hand-written inverse field that
  this plan removes), `OFn` (opaque escape hatch — out of scope; stays).
- `OutFields rs ci fs` — an HList of `Term`s, one per field of the
  wire constructor. Constructors: `OFNil`, `OFCons`.
- `WireCtor co fields` — a per-output-constructor matcher and builder.
  Record: `wcName`, `wcMatch`, `wcBuild`.
- `HsPred rs ci` — the v1 predicate AST. Constructors: `PTop`, `PBot`,
  `PAnd`, `POr`, `PNot`, `PEq`, `PMatchC`. Out of scope; stays for v2.
- `Edge phi rs ci co s` — `{ guard, update, output, target }`.
- `SymTransducer phi rs s ci co` —
  `{ edgesOut, initial, initialRegs, isFinal }`.
- `BoolAlg phi a` — class with methods `top`, `bot`, `conj`, `disj`,
  `neg`, `models`, `sat`, `isBot`. The instance for `HsPred` has
  `sat _ = Nothing` and `isBot PBot = True; _ = False` (the v1
  syntactic placeholders). Out of scope for this plan; EP-2 upgrades.

The functions:

- `step`, `delta`, `omega` — forward stepping.
- `reconstitute` — backward replay via `solveOutput`.
- `solveOutput :: OutTerm rs ci co -> RegFile rs -> co -> Maybe ci` —
  inverts an output. **Currently delegates to `OPack`'s hand-written
  inverse; this plan replaces with mechanical structural inversion.**
- `checkHiddenInputs :: SymTransducer phi rs s ci co -> [HiddenInputWarning]` —
  the build-time analysis. Currently flags any `OFn` output and any
  `OPack` whose `OutFields` contains a `TInpField`. This plan rewrites
  the second case to be more precise.

### Why `TInpField` is opaque

`TInpField :: (ci -> r) -> Term rs ci r` carries a Haskell function. To
read a field of an input constructor, the user writes:

    inpStart :: (StartRegistrationData -> r) -> Term UserRegRegs UserCmd r
    inpStart f = TInpField $ \case
      StartRegistration d -> f d
      _ -> error "inpStart: guard rules out non-StartRegistration"

The `\case` destructures `UserCmd` (a sum type) and projects out a
field. The non-matching branches are unreachable in correct usage
because the edge's guard rules them out, but the compiler does not
know that, so the user writes `error "guard"` stubs.

`solveOutput` cannot inspect this function. To recover the input from
an observed output, `solveOutput` would need to ask the function "what
input would have produced this output value?" — but the function only
goes one way. The v1 fix was to add a third field to `OPack` carrying a
user-supplied inverse `RegFile rs -> co -> Maybe ci`.

### What the User Registration aggregate looks like

`src/Keiki/Examples/UserRegistration.hs` (V5 / fixed schema) defines:

- A five-vertex `Vertex` enum: `PotentialCustomer`, `Registering`,
  `RequiresConfirmation`, `Confirmed`, `Deleted`.
- A five-slot register file `UserRegRegs` keyed by `"email"`,
  `"confirmCode"`, `"registeredAt"`, `"confirmedAt"`, `"deletedAt"`.
- `UserCmd` with five constructors (`StartRegistration`,
  `ConfirmAccount`, `ResendConfirmation`, `FulfillGDPRRequest`,
  `Continue`).
- `UserEvent` with five constructors (`RegistrationStarted`,
  `ConfirmationEmailSent`, `AccountConfirmed`, `ConfirmationResent`,
  `AccountDeleted`).
- Per-constructor input helpers using `TInpField`:

      inpStart   :: (StartRegistrationData -> r) -> Term UserRegRegs UserCmd r
      inpConfirm :: (ConfirmAccountData     -> r) -> Term UserRegRegs UserCmd r
      inpResend  :: (ResendConfirmationData -> r) -> Term UserRegRegs UserCmd r
      inpGdpr    :: (FulfillGDPRRequestData -> r) -> Term UserRegRegs UserCmd r

  Each is a `TInpField` wrapping a `\case` with `error "guard"` stubs
  for the non-matching branches.

- Per-event `WireCtor`:

      wireRegistrationStarted   :: WireCtor UserEvent (Email, (ConfirmationCode, (UTCTime, ())))
      wireConfirmationEmailSent :: WireCtor UserEvent (Email, ())
      wireAccountConfirmed      :: WireCtor UserEvent (Email, (ConfirmationCode, (UTCTime, ())))
      wireConfirmationResent    :: WireCtor UserEvent (Email, (ConfirmationCode, (UTCTime, ())))
      wireAccountDeleted        :: WireCtor UserEvent (Email, (UTCTime, ()))

- `userReg :: SymTransducer (HsPred ...) UserRegRegs Vertex UserCmd UserEvent`
  with five edges, one per command-vertex pair. Each edge whose `output`
  is `Just (...)` calls `pack wire ofields handWrittenInverse`. Read
  the file in full (~400 lines) before starting M5.

V0 mirrors V5 except `AccountConfirmedDataV0` drops the `confirmCode`
field, the corresponding `OutFields` drops it, and the hand-written
inverse on that one edge returns `Nothing`. After EP-1, the V0
demonstration of the hidden-input bug becomes structurally observable
(no hand-written `Nothing` needed; `solveOutput` cannot reconstruct the
missing field).

### What the test suite verifies

`test/Keiki/CoreSpec.hs` has 14 examples covering `evalTerm`,
`evalPred`, `delta`, `omega`, `step`, `reconstitute` (empty log),
`solveOutput` on a tiny `OPack` (uses a hand-written inverse), and
`checkHiddenInputs` on a synthetic transducer.

`test/Keiki/Examples/UserRegistrationSpec.hs` has 7 examples covering
end-to-end replay on the canonical 5-event log, per-step replay
assertions, and snapshot comparison.

`test/Keiki/Examples/UserRegistrationV0Spec.hs` has 3 examples covering
`reconstitute userRegV0 == Nothing` and the hidden-input warnings.

Total: 24 examples, 0 failures.

### Terms used in this plan

- *DSL surface* — the user-facing constructors and helpers exported
  from `Keiki.Core` for writing transducers. The user constructs values
  of type `SymTransducer phi rs s ci co` by combining these.
- *Mechanical inversion* — the property that `solveOutput` recovers the
  input symbol `ci` from an observed output symbol `co` by walking the
  AST of the producing edge's `output` term, with no per-edge user code.
  The v1 prototype falls short of this for any edge whose input reads
  go through `TInpField`.
- *Structural input projection* — the v2 replacement for `TInpField`. A
  `Term` constructor that carries enough syntactic information for
  `solveOutput` to know which constructor of `ci` it expects to see and
  which field of that constructor to project. The exact shape is a
  design choice resolved in this plan's M1.
- *Hidden-input check* — the build-time analysis
  (`checkHiddenInputs`) that reports edges whose `update` or `guard`
  reads input fields not present in `output`. Currently
  conservative (flags many edges that are actually fine); will become
  more precise after this plan.
- *V5 / V0 schemas* — V5 is the fixed schema (synthesis §4 fix-1) used
  by `UserRegistration.hs`. V0 is the unfixed schema used by
  `UserRegistrationV0.hs` to demonstrate the hidden-input bug. "V" is
  for "version", not "vertex".


## Plan of Work

This section is the narrative of the milestones. Each milestone has a
brief opening paragraph (scope, what exists at the end, what to run,
what to observe) followed by concrete instructions.

### Milestone 0 — Verify prerequisites

**Scope.** Confirm that the working tree compiles, the test suite is
green, and the three v1 design notes plus the MasterPlan exist on disk.
This is a five-minute sanity check that prevents wasting M1 effort on a
broken baseline.

**At the end of this milestone:** Nothing has changed in the repo. The
contributor has confidence that the baseline matches the EP-4 verdict.

**Run:**

    cabal build
    cabal test

**Observe:** `cabal build` succeeds with no warnings. `cabal test`
prints "24 examples, 0 failures" (or substantively similar). Verify
these files exist (use `ls` or read each one):

    docs/research/dsl-shape-for-symbolic-register.md
    docs/research/schema-evolution.md
    docs/research/effects-boundary.md
    docs/masterplans/2-retire-v1-escape-hatches-in-pure-core-tinpproj-sbv-boolalg.md

**Acceptance:** Both commands succeed; all four files exist and are
non-empty. Mark M0 complete in Progress with a short note.

If `cabal build` fails or any file is missing, stop and investigate
before proceeding. Do not attempt to fix unrelated breakage in this
plan.

### Milestone 1 — Survey + design note

**Scope.** Choose the structural input-projection shape that replaces
`TInpField`. Capture the survey, the choice, and the rationale in a new
design note at `docs/research/tinpproj-design.md`. The note is the
hand-off contract for the rest of this plan: M2-M7 implement what M1
specifies.

**At the end of this milestone:** A new file
`docs/research/tinpproj-design.md` (~300 lines) exists. It names the
chosen shape (recommended below: hand-rolled `InCtor` mirroring
`WireCtor`), the constructor signature, the `solveOutput` algorithm, the
migration plan for User Registration's per-constructor input helpers,
and the v1 API surface that stays vs. goes.

**Candidate shapes to survey.** Four candidates, derived from the v1
DSL note's "v2 retirement" hints (`docs/research/dsl-shape-for-symbolic-register.md`,
"Ergonomic verdict" and "v1-only surfaces" sections):

1. **Lens-based.** `TInpProj :: Lens' ci r -> Term rs ci r` (where
   `Lens'` is from the `lens` library, registered in `mori` as
   `ekmett/lens`). Status: rejected before survey because `ci` is
   typically a sum type (e.g., `UserCmd`) and lenses to fields of a
   single constructor are necessarily partial — incompatible with
   `Lens'` which requires totality. Document this in the survey for
   completeness.

2. **HasField / `GHC.Records.HasField`.**
   `TInpProj :: HasField "field" ci r => Term rs ci r`. Status:
   same problem as Lens — `HasField` works only on records, not on
   sum constructors. Rejected; documented.

3. **Hand-rolled `InCtor` mirroring `WireCtor`.** Symmetric to the
   existing output side. Sketch:

       data InCtor ci fields = InCtor
         { icName  :: String                       -- diagnostics
         , icMatch :: ci -> Maybe fields           -- pattern-match
         , icBuild :: fields -> ci                 -- inverse: build ci
         }

       data Term rs ci r where
         ...
         TInpCtorField :: InCtor ci fields
                       -> Index fields r
                       -> Term rs ci r

   Rationale: maximally symmetric to `WireCtor` (output side); easy to
   specify; easy to write the mechanical inverse for `solveOutput` (see
   below); zero new dependencies. The user constructs one `InCtor` per
   command constructor, mirroring the existing one-`WireCtor`-per-event
   pattern. **This is the recommended pick.**

4. **`GHC.Generics`-derived.** Use `GHC.Generics` to enumerate
   constructors of `ci` and their fields, generate per-constructor
   projections automatically. Pros: less user boilerplate. Cons: heavier
   machinery; harder error messages; the same one-`WireCtor`-per-event
   boilerplate already exists for the output side and is tolerable, so
   the input side's symmetric boilerplate is also tolerable.

**Mechanical inversion algorithm (for the recommended shape).** Given
an `OPack ctor fields` and an observed `co_obs`:

1. Run `wcMatch ctor co_obs`. If `Nothing`, this edge does not match;
   `solveOutput` returns `Nothing`.
2. If `Just fields_obs`, walk `fields :: OutFields rs ci fs` and
   `fields_obs :: fs` together. For each `Term`/observed-value pair:
   - `TLit r` against observed `v`: check `r == v`. If mismatch,
     return `Nothing`.
   - `TReg ix` against observed `v`: check `regs ! ix == v`. If
     mismatch, return `Nothing`.
   - `TInpCtorField ic ix` against observed `v`: record (a) the
     `InCtor` (must agree across all such entries on the same edge),
     (b) the `Index` and value pair `(ix, v)`. Add to a partial
     fields-tuple builder.
   - `TApp1` / `TApp2`: cannot mechanically invert. Return `Nothing`
     (the build-time check warns about these edges; runtime returns
     `Nothing`).
3. After the walk, if any `TInpCtorField` entries appeared:
   - Verify they all share the same `InCtor` (compare `icName` for
     equality plus a pointer equality check, or define an `InCtor`
     equality contract). Two different `InCtor`s in one edge's output
     is a structural error; return `Nothing`.
   - Verify the gathered `(Index, value)` pairs cover all fields of
     the `InCtor`'s `fields` tuple. Missing fields ⇒ return `Nothing`
     (the V0 hidden-input case lands here).
   - Reconstruct the `fields` tuple in the right order using the
     gathered values. Call `icBuild ic fields_tuple :: ci`.
4. If no `TInpCtorField` entries appeared (the edge's output uses only
   `TLit` and `TReg`), the recovered `ci` is unconstrained. The edge is
   either degenerate (output is independent of input — a literal
   constant) or the input is determined entirely by the edge's guard
   (e.g., a constructor-only check). Either way, `solveOutput` cannot
   produce a `ci` from the output alone; emit a build-time warning if
   the edge's guard reads `ci` (already covered by `checkHiddenInputs`).

The walking algorithm is the heart of M3. Spell it out in the design
note prose-first.

**Migration plan for User Registration helpers.** The V5
`inpStart`/`inpConfirm`/`inpResend`/`inpGdpr` helpers become:

    -- Define one InCtor per UserCmd constructor.
    inCtorStart :: InCtor UserCmd (Email, (ConfirmationCode, (UTCTime, ())))
    inCtorStart = InCtor
      { icName  = "StartRegistration"
      , icMatch = \case
          StartRegistration d -> Just (d.email, (d.confirmCode, (d.at, ())))
          _ -> Nothing
      , icBuild = \(e, (cc, (a, ()))) ->
          StartRegistration (StartRegistrationData e cc a)
      }
    -- ...inCtorConfirm, inCtorResend, inCtorGdpr similarly...

    -- Per-constructor field-read helpers (the new inpStart/inpConfirm/...).
    inpStartEmail :: Term UserRegRegs UserCmd Email
    inpStartEmail = TInpCtorField inCtorStart (#email :: Index ... Email)

    -- Or, more flexibly, one helper per InCtor that takes the index:
    inpStart :: Index (Email, (ConfirmationCode, (UTCTime, ()))) r
             -> Term UserRegRegs UserCmd r
    inpStart = TInpCtorField inCtorStart

The `Index` over a tuple-shaped fields-list works because the existing
`Index rs r` GADT and `IsLabel` instance are parametric over the
type-level list of slot pairs. For tuple fields the user writes
positional indices; for slot-list fields (recommended; see below) the
user writes `OverloadedLabels` `#email`. Decide in the design note
whether `InCtor`'s `fields` parameter is a tuple type (faster, less
work) or a slot-list (`[Slot]`) (uniform with `OutFields`, supports
`OverloadedLabels`).

The recommended shape is the slot-list:

    data InCtor ci (rs :: [Slot]) = InCtor
      { icName  :: String
      , icMatch :: ci -> Maybe (RegFile rs)
      , icBuild :: RegFile rs -> ci
      }

    data Term rs ci r where
      ...
      TInpCtorField :: InCtor ci ifs -> Index ifs r -> Term rs ci r

This re-uses the existing `RegFile`/`Index`/`IsLabel` machinery and lets
the User Registration migration write `inpStart #email` instead of
`inpStart (Index "email")`. Confirm the choice in the design note.

**v1 API surface that stays.** `TLit`, `TReg`, `TApp1`, `TApp2`,
`OPack` (without the third field), `OFn`, `HsPred`, all helpers except
`inp`. `unsafeCombine` stays. The structural `OutFields` shape stays.

**v1 API surface that goes.** `TInpField` constructor, `inp` helper,
`OPack`'s `(RegFile rs -> co -> Maybe ci)` field, the predicate
`outFieldsHaveInpField` (replaced by a structural-version equivalent).

**Concrete steps.** Read these files in full before writing the note:

    docs/research/dsl-shape-for-symbolic-register.md
    docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md
    src/Keiki/Core.hs
    src/Keiki/Examples/UserRegistration.hs
    docs/plans/4-prototype-symbolic-register-core-with-user-registration-smoke-test.md

Then create `docs/research/tinpproj-design.md` with the structure:

1. Goal: retire `TInpField` and the `OPack` hand-written inverse.
2. Survey: four candidates with pros/cons; rejection rationale for
   1, 2, 4; choice rationale for 3.
3. Chosen shape: full constructor signatures and helper function types.
4. Mechanical inversion algorithm: prose-first, then a short pseudocode
   sketch.
5. Migration plan for User Registration: one `InCtor` per `UserCmd`
   constructor; new per-constructor helpers; loss of `error "guard"`
   stubs.
6. v1 surfaces that stay vs. go.
7. Implementation checklist for M2-M7.

**Acceptance.** The note exists and is internally consistent. A reader
who finishes it can implement M2-M7 without further discussion.

### Milestone 2 — Add new constructor to `Term`

**Scope.** Introduce the new types from M1's design note. Make `Term`
carry both `TInpField` (for now) and the new structural constructor.
Update `evalTerm`. The `TInpField` parallel keeps existing code
compiling so we can land M2-M3 without breaking the test suite.

**At the end of this milestone:** `src/Keiki/Core.hs` exports a new
`InCtor` type and a new `Term` constructor (named per the design note;
the placeholder name in this plan is `TInpCtorField`). The `inpCtor`
helper exists. `evalTerm` handles the new constructor. `cabal build`
succeeds. The test suite still passes 24/24 (no test changes yet).
A new test in `test/Keiki/CoreSpec.hs` exercises the new constructor
on a tiny example.

**Edits.** In `src/Keiki/Core.hs`:

- Add the `InCtor` data declaration after `WireCtor` (around line 200).
  Use the `RegFile`-shaped `fields` parameter per the design note.
- Add `TInpCtorField` to `Term`. Keep `TInpField` for now.
- Add `inpCtor :: InCtor ci ifs -> Index ifs r -> Term rs ci r` helper
  alongside `inp`.
- Update the `evalTerm` clause for `TInpCtorField`:

      evalTerm (TInpCtorField ic ix) _regs ci =
        case icMatch ic ci of
          Just rf -> rf ! ix
          Nothing -> error ("evalTerm: TInpCtorField guard violation: "
                            ++ icName ic)

- Update `termReadsInput` to count `TInpCtorField` as input-reading.
- Add the new types to the module export list.

In `test/Keiki/CoreSpec.hs`:

- Add a `describe "TInpCtorField"` block with at least three cases:
  - Evaluation succeeds when `icMatch` returns `Just`.
  - Evaluation throws "guard violation" when `icMatch` returns `Nothing`
    (use `evaluate` + `shouldThrow`).
  - `termReadsInput` returns `True` for a term containing
    `TInpCtorField`.

**Acceptance.** `cabal build` succeeds with no new warnings (the
existing `TInpField` constructor will produce the same warnings as
before; that is fine). `cabal test` reports 27 examples (24 existing +
3 new), 0 failures. Mark M2 complete with a one-line summary.

### Milestone 3 — Update `solveOutput` and analyses

**Scope.** Teach `solveOutput` and the build-time analyses to walk the
new constructor structurally. After this milestone, `solveOutput` works
mechanically on any `OPack` whose `OutFields` reads only `TLit`,
`TReg`, and `TInpCtorField` (no `TInpField`, no `TApp*`). The
`OPack` hand-written inverse field is still required by the type
signature; M4 removes it.

**At the end of this milestone:** `solveOutput` has a structural-walk
implementation alongside the v1 hand-written-inverse delegation (the
delegation stays for now — M4 removes the field). A new private helper
walks an `OutFields` HList to gather field values from an observed `co`
and check `InCtor` consistency. `checkHiddenInputs` emits a more
precise warning shape that names the missing field of the `InCtor` for
edges where the structural walk would not produce a complete `ci`.
Tests cover the structural-walk path on a tiny example built in
`test/Keiki/CoreSpec.hs`.

**Edits.** In `src/Keiki/Core.hs`:

- Introduce a private helper:

      -- | Walk an OutFields HList in lockstep with an observed-fields
      -- HList tuple. Returns Just a partial-fields-tuple-builder if all
      -- TLit/TReg checks pass and all TInpCtorField entries share an
      -- InCtor; Nothing on any mismatch.
      structurallyInvertOutFields
        :: OutFields rs ci fs
        -> fs
        -> RegFile rs
        -> Maybe (Maybe (SomeInCtor ci, [(SomeIndex, Any)]))

  Where `SomeInCtor` and `SomeIndex` are existential wrappers (define
  them privately). The outer `Maybe` is "did the lit/reg checks pass";
  the inner `Maybe` is "did we find any TInpCtorField entries." The
  `[(SomeIndex, Any)]` is the partial fields-builder.

  The exact existential machinery is a design decision; the design note
  may choose to keep `InCtor` opaque-but-equality-comparable instead,
  which is simpler. Pick the simplest approach that correctly enforces
  "all `TInpCtorField` entries share an `InCtor`."

- Rewrite `solveOutput` for `OPack`:

      solveOutput (OPack ctor fields _legacyInv) regs co_obs =
        case wcMatch ctor co_obs of
          Nothing -> Nothing
          Just fs -> case structurallyInvertOutFields fields fs regs of
            Nothing                          -> Nothing
            Just Nothing                     -> Nothing  -- no input source
            Just (Just (someIc, partialFs))  ->
              buildCi someIc partialFs

  Where `buildCi` reconstructs the `RegFile ifs` from the partial
  builder, checks completeness (every `Index` of the `InCtor`'s field
  list appears once), and calls `icBuild someIc rf`.

  Keep the `_legacyInv` parameter binding to silence the warning until
  M4 removes the field.

- Add `outFieldsHaveInpCtorField :: OutFields rs ci fs -> Bool` (or
  rename `outFieldsHaveInpField` to track both for one milestone).

- Rewrite the `OPack` clause of `checkHiddenInputs`. Current shape:

      Just (OPack _ fields _inv)
        | outFieldsHaveInpField fields ->
            [ "edge #" <> show n
              <> ": OPack field uses TInpField; v1 inverse is hand-written"
            ]
        | otherwise -> []

  New shape (more precise): walk the `OutFields`, detect missing
  `InCtor` fields, emit a warning that names the `InCtor` and the
  missing fields. Pseudocode:

      Just (OPack _ fields _inv) ->
        case detectMissingFields fields of
          [] -> []
          missing ->
            [ "edge #" <> show n
              <> ": OPack walk leaves InCtor "
              <> someIcName <> " fields {" <> showMissing missing
              <> "} unrecovered"
            ]

  `detectMissingFields` is the structural analogue of
  `outFieldsHaveInpField`: walk the `OutFields`, gather the (assumed
  unique) `InCtor`'s field-set, compare to the field-set the `OutFields`
  visits, return the difference.

In `test/Keiki/CoreSpec.hs`:

- Add a `describe "solveOutput on a tiny OPack with TInpCtorField"`
  block with at least three cases:
  - Evaluation forward: `evalOut` produces the expected `co`.
  - Inversion: `solveOutput` recovers the original `ci` mechanically
    (no hand-written inverse used).
  - Missing-field detection: build an `OPack` whose `OutFields` is
    structurally complete; flip to one that omits a field; verify
    `solveOutput` returns `Nothing` and `checkHiddenInputs` produces a
    warning naming the missing field.

**Acceptance.** `cabal build` and `cabal test` succeed. The new
solveOutput-structural tests pass. The existing test suite still
passes (the v1 `OPack`-with-hand-written-inverse path still works
through the `_legacyInv` binding, even though the structural walk is
now in place). Mark M3 complete.

### Milestone 4 — Drop the hand-written inverse field from `OPack`

**Scope.** Remove the third field from the `OPack` constructor. After
this milestone, `solveOutput` is purely structural; there is no escape
hatch for opaque per-edge inversion at the type level. Compilation
breaks at every `OPack` construction site in the example modules; this
is intentional and is fixed in M5/M6.

**At the end of this milestone:** `OPack`'s signature is
`OPack :: WireCtor co fields -> OutFields rs ci fields -> OutTerm rs ci co`.
The `pack` helper drops its third argument:
`pack :: WireCtor co fields -> OutFields rs ci fields -> OutTerm rs ci co`.
`solveOutput` no longer references a `_legacyInv` binding.
`src/Keiki/Examples/UserRegistration.hs` and
`src/Keiki/Examples/UserRegistrationV0.hs` fail to compile (every
`pack ... ... (\_regs co -> ...)` is one argument too many). The
core test suite (`test/Keiki/CoreSpec.hs`) still passes after updating
its single `OPack` use site (the `solveOutput on a tiny OPack`
describe added in M2/M3).

**Edits.** In `src/Keiki/Core.hs`:

- Change the `OPack` constructor to drop the third field.
- Change the `pack` helper signature to match.
- Remove the `_legacyInv` binding from `solveOutput`'s `OPack` clause.
- Remove the `_inv` binding from `checkHiddenInputs`'s `OPack`
  clause.
- Remove the `evalOut`'s `_inv` binding from `OPack` clause.

In `test/Keiki/CoreSpec.hs`:

- The single `OPack` use site (`outFoo` in the `solveOutput on a tiny
  OPack` describe) loses its third argument. Adjust.

The example modules are intentionally left broken until M5/M6.

**Acceptance.** `cabal build` of the library *fails* on
`UserRegistration.hs` and `UserRegistrationV0.hs` with errors of the
form "Couldn't match expected type ... with actual type ... too many
arguments to data constructor `OPack`". Build the library with
`cabal build keiki:lib:keiki` to see the failure focused on the library
target, or use `cabal build keiki-test` to confirm the test code
compiles in isolation (it should, after the local fix above).

Run the core-only test in isolation:

    cabal test keiki-test --test-options="--match \"Keiki.Core\""

Expected: the Keiki.Core spec passes (no example-module dependencies).

Mark M4 complete with a note that examples are broken pending M5/M6.

### Milestone 5 — Migrate `Keiki.Examples.UserRegistration` (V5)

**Scope.** Convert the V5 aggregate to use the new structural
constructor. Define one `InCtor` per `UserCmd` constructor. Replace
`inpStart`/`inpConfirm`/`inpResend`/`inpGdpr` with structural helpers.
Remove every hand-written inverse from `OPack` constructions. After
this milestone, V5 compiles and the V5 spec passes; V0 is still broken.

**At the end of this milestone:** `src/Keiki/Examples/UserRegistration.hs`
contains four new `InCtor UserCmd ifs` values:

    inCtorStart   :: InCtor UserCmd '[ '("email", Email), '("confirmCode", ConfirmationCode), '("at", UTCTime) ]
    inCtorConfirm :: InCtor UserCmd '[ '("confirmCode", ConfirmationCode), '("at", UTCTime) ]
    inCtorResend  :: InCtor UserCmd '[ '("code", ConfirmationCode), '("at", UTCTime) ]
    inCtorGdpr    :: InCtor UserCmd '[ '("at", UTCTime) ]

The per-constructor input helpers become:

    inpStart   :: Index '[ '("email", Email), '("confirmCode", ConfirmationCode), '("at", UTCTime) ] r -> Term UserRegRegs UserCmd r
    inpStart   = TInpCtorField inCtorStart
    inpConfirm :: Index '[ '("confirmCode", ConfirmationCode), '("at", UTCTime) ] r -> Term UserRegRegs UserCmd r
    inpConfirm = TInpCtorField inCtorConfirm
    -- ...etc.

Every edge's `update` term that previously read
`inpStart (.email)` becomes `inpStart #email` (the
`OverloadedLabels` syntax sugar provided by `IsLabel`).

Every `OPack` construction loses its third argument.

`cabal test --test-options="--match Keiki.Examples.UserRegistrationSpec"`
passes (7 examples).

**Edits.** In `src/Keiki/Examples/UserRegistration.hs`:

- Add the four `InCtor` definitions after the `wire*` definitions.
- Replace `inpStart`, `inpConfirm`, `inpResend`, `inpGdpr` with the new
  structural helpers.
- Walk every `Edge` in `userRegEdges`. For each:
  - In `update`: replace `inpFoo (.field)` with `inpFoo #field`.
  - In `output = Just $ pack ...`: drop the third argument
    (`(\_regs co -> case co of ... ; _ -> Nothing)`).
- The `inCtorConfirm`'s `icMatch` should return
  `Just (RCons (Proxy @"confirmCode") d.confirmCode (RCons (Proxy @"at") d.at RNil))`
  for `ConfirmAccount d`. Confirm the slot order matches the `Index`
  uses.

In `test/Keiki/Examples/UserRegistrationSpec.hs`:

- No source changes expected. The end-to-end behavior is unchanged: the
  same 5-event canonical log replays to the same final state.

If the spec fails, the most likely cause is a slot-order mismatch in an
`InCtor`'s `RegFile` construction. Read the failure carefully; the
`evalTerm` "guard violation" error message names the `icName`.

**Acceptance.** `cabal build` succeeds for the `Keiki.Examples.UserRegistration`
module. The V5 spec passes (7 examples, 0 failures). The
`Keiki.Examples.UserRegistrationV0` module still fails to compile. Mark
M5 complete.

### Milestone 6 — Migrate `Keiki.Examples.UserRegistrationV0`

**Scope.** Same migration as M5, applied to V0. The V0 demonstrates
the hidden-input bug; after migration, the bug is structurally
observable rather than hand-written.

**At the end of this milestone:** `src/Keiki/Examples/UserRegistrationV0.hs`
mirrors V5's structural surface except `AccountConfirmedDataV0` still
drops `confirmCode` (the deliberate bug). The Confirm edge's
`OutFields` does not include `inpConfirm #confirmCode` (the bug
manifests structurally: `inCtorConfirm` has a `confirmCode` field but
the `OutFields` walk never visits it). `solveOutput` returns `Nothing`
on the V0 canonical log because the partial fields-builder cannot
construct a complete `RegFile '[ '("confirmCode", _), '("at", _) ]`.
`checkHiddenInputs` produces a warning that names
`"inCtorConfirm.confirmCode"` (or substantively similar) instead of the
v1 `"OPack field uses TInpField"`.

**Edits.** In `src/Keiki/Examples/UserRegistrationV0.hs`:

- Mirror the M5 changes for V5.
- `inCtorConfirm` is the same as V5's (it still describes
  `ConfirmAccountData`, which always has `confirmCode`; the bug is in
  the *event* schema, not the *command* schema).
- The Confirm edge's `OutFields` for V0 contains only
  `OFCons (proj #email) (OFCons (inpConfirm #at) OFNil)` — no
  `inpConfirm #confirmCode` because `wireAccountConfirmedV0`'s
  fields tuple no longer has that slot.
- Remove the hand-written-`Nothing` inverse argument that V0 had.

In `test/Keiki/Examples/UserRegistrationV0Spec.hs`:

- The "hidden-input check produces warnings" test should now assert
  the warning text contains the substring `"inCtorConfirm"` and
  `"confirmCode"`. Read the v0 spec and update the assertion.
- The "reconstitute returns Nothing" test should still pass (same
  failure mode, structurally observable now).

**Acceptance.** `cabal build` and `cabal test` succeed. The V0 spec
passes (3 examples, 0 failures). The full test suite reports the
expected count (24 + 3 from M2 = 27 examples, 0 failures; or higher if
M3 added more solveOutput tests). Mark M6 complete.

### Milestone 7 — Remove `TInpField` and `inp` from the public API

**Scope.** Now that no use site references `TInpField`, delete it and
the `inp` helper. Shrink the affected analyses (`termReadsInput`,
`outFieldsHaveInpField` if still present) to mention only the new
structural constructor.

**At the end of this milestone:** `src/Keiki/Core.hs`'s `Term`
constructor list does not include `TInpField`. The `inp` helper does
not exist. The module export list omits both. `cabal build` and
`cabal test` succeed with no warnings. A `git grep TInpField` returns
no hits in `src/` or `test/`.

**Edits.** In `src/Keiki/Core.hs`:

- Remove the `TInpField` constructor.
- Remove the `inp` helper.
- Remove the `inp` and `TInpField` entries from the module exports.
- Update `termReadsInput`, `evalTerm`, and any `outFieldsHave*`
  predicate to drop the `TInpField` clauses. Rename
  `outFieldsHaveInpField` to `outFieldsHaveInpCtorField` (or whatever
  the M3 helper was named) if not already done.
- Update the haddock comments at the top of the module to remove the
  "v1 escape hatch: TInpField" mention.

If `cabal build` reports any "unused"-style warnings on helpers that
only existed to handle `TInpField`, delete those helpers.

**Acceptance.** `cabal build` and `cabal test` succeed with no
warnings (modulo the existing `OFn`/`PMatchC` v1-escape-hatch warnings
that are out of scope). Mark M7 complete.

### Milestone 8 — Update DSL design note; capture verdict

**Scope.** Edit `docs/research/dsl-shape-for-symbolic-register.md` to
reflect that `TInpField` and the `OPack` hand-written inverse are
retired. Edit the "Prototype Implementation Checklist" to remove the
v1 entries. Write the EP-1 verdict in this plan's Outcomes &
Retrospective. Cross-cut to the MasterPlan.

**At the end of this milestone:** The DSL note no longer claims
`TInpField` is the primary input-reading constructor; the M2/M3
structural surface is the primary mention; `TInpField` appears only in
a "Retired in EP-1" historical-notes section. The "v1-only surfaces"
list shrinks. The "Ergonomic verdict" section is updated to note that
the largest pain point named in v1 ("total-callback boilerplate in
`inp`") is now resolved.

**Edits.** In `docs/research/dsl-shape-for-symbolic-register.md`:

- Update the `Term` constructor list (the section "Term, Update, Edge,
  SymTransducer") to mention `TInpCtorField` (or whatever name) and
  remove `TInpField`.
- Update "OutTerm and the inversion contract" to reflect that
  `solveOutput` is now mechanical for the structural subset.
- Update "Ergonomic helpers": `inp` is gone; `inpCtor` is added.
- Update "Worked example: User Registration" to use the new helpers
  (or add a one-paragraph note that the worked example moved to the
  EP-1 v2 form; cite this plan and the migrated source files).
- Update "Ergonomic verdict": the painful-but-workable assessment
  becomes "tolerable" for the input side; pain that remains is
  concentrated in `OFn` and `PMatchC` (out of scope here).
- Update "Prototype Implementation Checklist": remove `TInpField`,
  `inp`. Add `TInpCtorField`, `inpCtor`, `InCtor`.
- Update "v1-only surfaces (flagged for v2 retirement)": move
  `TInpField` and the `OPack` inverse out; keep `OFn`, `PMatchC`,
  `unsafeCombine` as still-pending.

In this plan's Outcomes & Retrospective: write the EP-1 verdict.
Pattern after EP-4's verdict (see
`docs/plans/4-prototype-symbolic-register-core-with-user-registration-smoke-test.md#outcomes--retrospective`).
Two halves:

- *Mechanical inversion holds.* `reconstitute userReg canonicalLog ==
  Just (Deleted, expectedSnapshot)` with no hand-written inverse
  anywhere in the User Registration aggregate. The `OPack` constructor
  no longer carries a third field. `solveOutput` is purely structural.
- *Hidden-input check is more precise.* The V0 warning now names
  `inCtorConfirm.confirmCode` rather than the conservative "OPack
  field uses TInpField". The check has more bite at the v1 + EP-1 level.

In the MasterPlan
(`docs/masterplans/2-retire-v1-escape-hatches-in-pure-core-tinpproj-sbv-boolalg.md`):

- Mark EP-1 as Complete in the Exec-Plan Registry.
- Check off the EP-1 milestones in Progress.
- Add an entry to Surprises & Discoveries summarizing any cross-cuts
  that affect EP-2 (e.g., if the design note's `Term`-shape choice
  pre-determines whether EP-2 builds on the structural surface or
  takes the separate-symbolic-Term fallback).

**Acceptance.** All notes are updated; the MasterPlan reflects EP-1
completion; this plan's Outcomes & Retrospective contains the verdict.
Mark M8 complete.


## Concrete Steps

The exact commands to run, in order. All commands run from the repo
root: `/Users/shinzui/Keikaku/bokuno/keiki`.

**M0:**

    cabal build
    cabal test
    ls docs/research/dsl-shape-for-symbolic-register.md
    ls docs/research/schema-evolution.md
    ls docs/research/effects-boundary.md
    ls docs/masterplans/2-retire-v1-escape-hatches-in-pure-core-tinpproj-sbv-boolalg.md

Expected transcript fragment:

    Test suite keiki-test: RUNNING...

    Keiki.Core
      ... (14 examples)
    Keiki.Examples.UserRegistration
      ... (7 examples)
    Keiki.Examples.UserRegistrationV0
      ... (3 examples)

    Finished in 0.00xx seconds
    24 examples, 0 failures

**M1:** No commands; deliverable is the design note. Verify with:

    wc -l docs/research/tinpproj-design.md

Expect ~300 lines.

**M2-M7:** After each edit batch:

    cabal build
    cabal test

**M4 explicitly:** the library will fail to build until M5 lands. Run:

    cabal build keiki-test --test-options="--match \"Keiki.Core\""

to confirm the core spec passes in isolation.

**M8:** verify the doc edit:

    git diff docs/research/dsl-shape-for-symbolic-register.md

After the M8 commit, also verify:

    cabal build
    cabal test

**Commits:** every milestone gets a commit with the message format:

    feat(core): <one-line summary of the milestone>

    <details paragraph>

    MasterPlan: docs/masterplans/2-retire-v1-escape-hatches-in-pure-core-tinpproj-sbv-boolalg.md
    ExecPlan: docs/plans/5-replace-tinpfield-with-structural-input-projection-tinpproj.md
    Intention: intention_01knjzws4qezz9w8b0743zfqv8

Use Conventional Commits. Type scopes: `feat(core)`, `feat(examples)`,
`docs(research)`, `docs(masterplan)`, `test(core)`, `test(examples)`.


## Validation and Acceptance

The plan is complete when all of the following hold simultaneously:

- `cabal build` succeeds at the repo root with no warnings beyond those
  the v1 baseline already had (the existing `OFn`/`PMatchC`/`unsafeCombine`
  v1-escape-hatch warnings, if any, are out of scope and may stay).
- `cabal test` reports at least 27 examples (24 baseline + 3 from M2 +
  any added in M3), 0 failures.
- A `git grep TInpField src/ test/` returns no hits.
- A `git grep "RegFile rs -> co -> Maybe ci" src/` returns no hits
  (the `OPack` inverse field shape is gone).
- A `git grep "error \"guard\"" src/Keiki/Examples/` returns no hits
  (the `\case ... _ -> error "guard"` boilerplate from the v1 input
  helpers is gone).
- `reconstitute userReg canonicalLog == Just (Deleted, expectedSnapshot)`
  passes, exercised by the V5 spec.
- `reconstitute userRegV0 canonicalLogV0 == Nothing` passes, exercised
  by the V0 spec.
- `checkHiddenInputs userRegV0` produces at least one warning whose
  reason text mentions `inCtorConfirm` and `confirmCode`, exercised by
  the V0 spec.
- `docs/research/tinpproj-design.md` exists and is internally
  consistent.
- `docs/research/dsl-shape-for-symbolic-register.md` is updated to
  reflect the retirement (TInpField is documented as historical;
  TInpCtorField is the primary input-read constructor).
- The MasterPlan's Exec-Plan Registry shows EP-1 = Complete; its
  Progress section's EP-1 entries are checked off.
- This plan's Outcomes & Retrospective contains a written verdict.


## Idempotence and Recovery

Each milestone can be re-run safely. If a milestone partially completes
and is re-attempted, re-read the source files and the design note to
recover state; the Progress checklist is the source of truth for what
landed.

Common issues and recovery paths:

- *M2 introduces a build error in the library.* Most likely a missing
  `evalTerm` clause for the new constructor (GHC will name the missing
  pattern). Add the clause; re-build.
- *M3's `solveOutput` rewrite returns `Nothing` on cases that should
  succeed.* Most likely a slot-order mismatch in the partial
  fields-builder. Print the `(SomeIndex, Any)` list during debugging
  (use `Debug.Trace.traceShow` temporarily) to inspect which fields
  the walk gathered.
- *M4 leaves the example modules broken longer than expected.* This is
  expected for the duration between M4 and M5/M6 commits. Land M4-M6
  in tight sequence.
- *M5/M6's slot-order mismatch produces a runtime "guard violation"
  error during `cabal test`.* The `evalTerm` `error` message names the
  `icName` of the offending `InCtor`. Compare its `icMatch` definition
  against the `Index ifs r` types used in the edge.
- *M7 surfaces unused-import warnings.* Delete the unused imports.

If a milestone is rolled back (the work is undesirable), use
`git restore` for source files and `git checkout` for documents.
Commits should never be force-pushed; if a commit landed prematurely,
land a follow-up commit that reverts it cleanly.


## Interfaces and Dependencies

**No new cabal dependencies.** This plan uses only `base` and the
existing `text`, `time`, `hspec` deps. No `lens`, no `generic-lens`, no
SBV (that is EP-2's territory).

**Module-level interfaces (post-EP-1):**

- `Keiki.Core` exports the new `InCtor ci ifs` type, the new
  `TInpCtorField :: InCtor ci ifs -> Index ifs r -> Term rs ci r`
  constructor, and the new `inpCtor :: InCtor ci ifs -> Index ifs r ->
  Term rs ci r` helper. The exact name of the `Term` constructor is the
  M1 design milestone's call; this plan uses `TInpCtorField` as a
  placeholder.
- `Keiki.Core` no longer exports `TInpField` or `inp`.
- `OPack`'s constructor signature is
  `OPack :: WireCtor co fields -> OutFields rs ci fields -> OutTerm rs ci co`.
- `pack`'s helper signature matches `OPack`'s.
- `solveOutput :: OutTerm rs ci co -> RegFile rs -> co -> Maybe ci`
  is unchanged in signature; its body is now structural.
- `checkHiddenInputs :: SymTransducer phi rs s ci co -> [HiddenInputWarning]`
  is unchanged in signature; its body produces more precise warnings.

**MasterPlan integration points:**

- IP-1 (the `Term` constructor set): EP-1 is the owner. EP-2 will
  read this set during its M1 to decide whether to build SBV
  translation on it.
- IP-2 (the `OPack` constructor signature): EP-1 owns the
  hand-written-inverse retirement. EP-2 does not touch.
- IP-4 (User Registration smoke test): EP-1 owns the DSL migration of
  the V5 and V0 aggregates. EP-2 will add a new `isSingleValued userReg
  == True` test on the EP-1-migrated form.
- IP-5 (new design notes): EP-1 produces
  `docs/research/tinpproj-design.md`.

No changes to the build system are required beyond the source files.

**Reading list before starting M1:**

- `docs/research/dsl-shape-for-symbolic-register.md` — the v1 DSL
  design and the explicit "v2 retirement" hint for `TInpField`.
- `docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`
  — the User Registration aggregate (synthesis §4) and the
  formalism's claim of mechanical apply derivation.
- `src/Keiki/Core.hs` — the v1 implementation; specifically the
  `Term`, `OutTerm`, `OPack`, `solveOutput`, `checkHiddenInputs`
  surfaces.
- `src/Keiki/Examples/UserRegistration.hs` — the V5 aggregate; the
  per-constructor input helpers and the `OPack` construction sites
  that M5 migrates.
- `src/Keiki/Examples/UserRegistrationV0.hs` — the V0 aggregate; the
  hand-written-`Nothing` inverse on the Confirm edge that M6 retires.
- `docs/plans/4-prototype-symbolic-register-core-with-user-registration-smoke-test.md`
  — EP-4's Decision Log entry on the OPack-inverse deviation, and the
  Outcomes & Retrospective verdict that named this plan's retirement
  target.
