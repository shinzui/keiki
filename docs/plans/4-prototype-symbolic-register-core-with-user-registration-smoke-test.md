---
id: 4
slug: prototype-symbolic-register-core-with-user-registration-smoke-test
title: "Prototype symbolic-register core with User Registration smoke test"
kind: exec-plan
created_at: 2026-05-01T05:20:28Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
master_plan: "docs/masterplans/1-validate-symbolic-register-direction-via-haskell-prototype.md"
---

# Prototype symbolic-register core with User Registration smoke test

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

The keiki library is being designed (no Haskell code exists yet) to handle the **pure
part** of event sourcing, workflow engines, and durable execution as a single
formalism: the **symbolic-register transducer**. The synthesis note that names this
direction lives at
`docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`. Its
headline claim:

> C is the formalism. B is an optional presentation layer on top.

C means the symbolic-register transducer: state is `(s, RegFile rs)` where `s` is a
finite control vertex and `rs` is a typed heterogeneous register file; edges unify
guard, update, output, and target into a single value; `apply` (the function that
recovers state by replaying events) is **mechanically derived** by walking each edge's
output term and inverting it via `solveOutput`.

This plan is the **validation gate** for that synthesis. The master plan
(`docs/masterplans/1-validate-symbolic-register-direction-via-haskell-prototype.md`)
states the acceptance criterion plainly: *"if the AST surface ergonomics are
tolerable and `solveOutput` works on that example, the synthesis holds."* The example
is the User Registration aggregate from synthesis §4.

After this plan is complete, the repository contains:

- A working Haskell project (cabal-based, GHC pinned, deps locked).
- A pure module `Keiki.Core` exposing `RegFile`, `Index`, `Term`, `OutTerm`, `Update`,
  `Edge`, `SymTransducer`, and the `BoolAlg` class — all matching the design note
  produced by `docs/plans/1-sharpen-dsl-shape-for-symbolic-register-transducer.md`
  (hereafter "the DSL note").
- A bare-minimum evaluator: `runUpdate`, `evalTerm`, `evalOut`, `models`, and the
  derived `delta` and `omega` projections.
- A `step :: SymTransducer phi rs s ci co -> (s, RegFile rs) -> ci -> Maybe (s, RegFile rs, Maybe co)`
  function, matching the signature pinned by
  `docs/plans/3-sharpen-effects-boundary-between-pure-transducer-and-runtime.md`
  (hereafter "the boundary note").
- A `solveOutput` implementation and a `reconstitute :: SymTransducer phi rs s ci co -> [co] -> Maybe (s, RegFile rs)`
  derived from it.
- A `Keiki.Examples.UserRegistration` module containing the User Registration
  aggregate from synthesis §4, written using only the `Keiki.Core` DSL constructors.
- A test suite (`hspec` or `tasty-hunit`) with at least one end-to-end test that
  consumes the worked event log from synthesis §4 (the five events:
  `RegistrationStarted`, `ConfirmationEmailSent`, `ConfirmationResent`,
  `AccountConfirmed`, `AccountDeleted`) and verifies that `reconstitute` returns
  `Just (Deleted, expectedRegs)`.
- The synthesis-§4 hidden-input bug surfacing visibly: the test should run *both*
  the unfixed event schema (where `AccountConfirmed` lacks `confirmCode`) and
  demonstrate the failure mode (replay produces wrong state or `solveOutput` reports
  a hidden input), then run the fixed schema (per synthesis §4 fix-1) and pass. This
  is the proof point that the build-time check has bite.

The user-visible win: a future contributor can run `cabal test` and observe that the
synthesis works on the canonical example, that `apply` was not user-provided (it fell
out of the transducer), and that the hidden-input check actually fires when the event
schema is malformed. If those tests pass with a tolerable DSL surface, the synthesis
is validated and the library has a foundation to build on. If they fail, the
synthesis needs revision before further work.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] Verify prerequisite design notes exist:
      `docs/research/dsl-shape-for-symbolic-register.md` (from plan 1),
      `docs/research/schema-evolution.md` (from plan 2),
      `docs/research/effects-boundary.md` (from plan 3). (2026-05-01)
- [x] Choose Haskell toolchain and project tool: GHC 9.10.3, cabal-install 3.16.1.0,
      `default-language: GHC2024`. The plan called for GHC 9.8 LTS but the local
      toolchain is 9.10.3 which is newer and supports GHC2024 default-language.
      Recorded in Decision Log. (2026-05-01)
- [x] Scaffold cabal project at the repo root: `keiki.cabal`, `cabal.project`,
      `src/Keiki/Core.hs`. (2026-05-01)
- [x] **Milestone 1 — Types compile.** Translated the DSL note's "Prototype
      Implementation Checklist" into Haskell type declarations in `Keiki.Core`.
      RegFile, Index, Term, OutTerm, Update, Edge, SymTransducer, HsPred,
      `BoolAlg` class with `HsPred` instance, `HasIndex`/`IsLabel` for
      `OverloadedLabels`, `(!)` runtime lookup, `combine`/`unsafeCombine`.
      Evaluator and entry-point bodies are `error "TODO: M2"` / `M3` / `M4`
      stubs. `cabal build` succeeds with redundant-constraint warnings on the
      stubbed signatures (resolved by M2 when bodies use the constraints).
      (2026-05-01)
- [x] **Milestone 2 — Bare-minimum evaluator.** Implemented `evalTerm`,
      `evalOut`, `evalOutFields`, `evalPred`, `runUpdate` (plus the internal
      `setSlot` helper that walks `Index`/`RegFile` together), the `BoolAlg
      HsPred` instance's `models` (delegating to `evalPred`), and the
      projections `delta` and `omega`. Test framework: `hspec ^>= 2.11`,
      added as a `keiki-test` cabal stanza. The synthetic 2-vertex
      transducer over `Bool` input plus targeted `evalTerm`/`evalPred`
      micro-tests run as 11 examples, 0 failures. (2026-05-01)
- [x] **Milestone 3 — `step` and `reconstitute` skeletons.** Implemented
      `step` (combines `delta` and `omega`; outer `Maybe` for "no edge
      fired", inner `Maybe co` for "fired but ε"). Implemented
      `reconstitute` as a fold over an internal `applyEvent` helper — the
      direction-C §5 `applySym` pattern: walk outgoing edges, invert each
      candidate edge's output via `solveOutput`, keep edges whose
      recovered input also satisfies the guard. `solveOutput` is still
      the M4 stub, so `reconstitute` only succeeds on the empty log
      until M4 lands; the empty-log case is covered by a test. 14
      examples, 0 failures. (2026-05-01)
- [x] **Milestone 4 — `solveOutput` for `OutTerm`.** Implemented
      `solveOutput`, `checkHiddenInputs`, and the structural helpers
      `termReadsInput` / `updateReadsInput` / `outFieldsHaveInpField`. v1
      deviation: 'OPack' carries a third field — a hand-written inverse
      `RegFile rs -> co -> Maybe ci` — because the chosen v1 'Term'
      constructor set has 'TInpField' as the only input-reading
      constructor and `TInpField` is opaque. The structural 'OutFields'
      remains the contract for the hidden-input analysis. Recorded in
      Decision Log and propagated to the MasterPlan's Surprises &
      Discoveries section in a follow-up commit. (2026-05-01)
- [x] **Milestone 5 — User Registration aggregate.** Defined
      `Keiki.Examples.UserRegistration` with: domain aliases (Email,
      ConfirmationCode), command and event payload records, `UserCmd`
      with the synthesis §4 four constructors plus a `Continue`
      internal command for the Registering ε-edge, `UserEvent` with the
      synthesis §4 fix-1 schema (`AccountConfirmedData` carries
      `confirmCode`), `UserRegRegs` slot list, the five `Vertex`
      values, hand-written `WireCtor` per event constructor, factored
      per-command-constructor `inpStart`/`inpConfirm`/`inpResend`/
      `inpGdpr` helpers and `isStart`/`isConfirm`/`isResend`/`isGdpr`/
      `isContinue` guard helpers, and the `userReg` transducer value.
      Per the EP-3 effects-boundary cross-cut, `ResendConfirmationData`
      carries a `code` field — fresh codes are generated by the
      adapter, not pulled from `IO` inside the transducer. The right-
      code edge guards `PAnd isConfirm (inpConfirm (.confirmCode) .==
      proj #confirmCode)` so the equality short-circuits on
      non-`ConfirmAccount` inputs. `cabal build` succeeds; the existing
      test suite still passes (18/18). (2026-05-01)
- [x] **Milestone 6 — End-to-end test passes (fixed schema).** Constructed
      the synthesis-§4 5-event canonical log (fix-1 schema) plus a
      hand-computed expected register-file snapshot (Email,
      ConfirmationCode, registeredAt rotated by the resend, confirmedAt,
      deletedAt). `reconstitute userReg canonicalLog` returns
      `Just (Deleted, expectedSnapshot)`. Per-step replay assertions
      cover step 1 (PotentialCustomer→Registering on
      RegistrationStarted) and step 5 (Confirmed→Deleted on
      AccountDeleted). 21 examples, 0 failures. **The synthesis holds:
      `solveOutput` walks the canonical log end-to-end.** (2026-05-01)
- [ ] **Milestone 7 — Hidden-input check fires (unfixed schema).** Construct the
      same event log without the `confirmCode` field on `AccountConfirmed`. Either:
      (a) `reconstitute` returns `Nothing` with a `HiddenInput` diagnostic, or
      (b) the `checkHiddenInputs` analysis returns a non-empty list pinpointing the
      bad edge. Test that this happens.
- [ ] **Milestone 8 — Ergonomic verdict.** Read `Keiki.Examples.UserRegistration`
      side-by-side with synthesis §4's pseudosyntax. Write a one-paragraph verdict in
      the Outcomes & Retrospective section: tolerable, painful but workable, or
      blocking. If blocking, file a follow-up plan.
- [ ] Commit at every milestone (with `MasterPlan:`, `ExecPlan:`, `Intention:`
      trailers).
- [ ] Update master plan's Exec-Plan Registry and Progress on each milestone.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

### M4: 'OPack' needs a v1 hand-written inverse (2026-05-01)

The DSL note's 'OPack' constructor was specified as
`OPack :: WireCtor co fields -> OutFields rs ci fields -> OutTerm rs ci co`.
While implementing 'solveOutput' it became clear the chosen v1 'Term'
constructor set cannot be mechanically inverted: the only input-reading
constructor is 'TInpField', which wraps `ci -> r` opaquely. Inversion
requires either a structural input-projection constructor (the v2
'TInpProj') or per-edge user-supplied inverses. The DSL note's
"Ergonomic verdict" already flagged this exact pain point — see IP-1
in the MasterPlan's Surprises & Discoveries — but framed it as
ergonomic (user has to write `\case ... _ -> error "guard"`) rather
than load-bearing for 'solveOutput'.

Resolution in M4: 'OPack' was extended to carry a third field, a
hand-written inverse `RegFile rs -> co -> Maybe ci`. The structural
'OutFields' remains; `checkHiddenInputs` still walks it. 'solveOutput'
on 'OPack' simply calls the inverse. The deviation is documented in
the Decision Log entry above and recorded in the MasterPlan's
Surprises & Discoveries for cross-plan visibility. v2's 'TInpProj' is
the natural retirement path: when input reads are structural, the
inverse can be derived mechanically from the structural 'OutFields'
walk, and the hand-written inverse field on 'OPack' goes away.


## Decision Log

Record every decision made while working on the plan.

- Decision: This plan implements only `Keiki.Core`. No `Keiki.Runtime`, no event store,
  no queue, no IO of any kind in the production module.
  Rationale: The boundary note pins the v1 prototype scope to the pure layer only.
  Mixing in runtime concerns dilutes the validation gate; the master plan's
  acceptance criterion is purely about whether `solveOutput` works and whether the
  DSL is tolerable.
  Date: 2026-04-30

- Decision: GHC 9.8 LTS via cabal-install (not stack, not nix-direct, no GHCJS).
  Rationale: Cabal is the lowest-friction tool for a single-package library. GHC 9.8
  is well-supported by the relevant ecosystem packages (`vinyl`, `hspec`, `tasty`)
  as of the plan date. If the user's environment requires Nix, the cabal project
  works inside a Nix shell without modification.
  Date: 2026-04-30

- Decision: Use GHC 9.10.3 with `default-language: GHC2024` instead of GHC 9.8.
  Rationale: 9.10.3 is what the local toolchain ships. GHC2024 includes
  `LambdaCase`, `GADTs`, `DataKinds`, `KindSignatures`, `ScopedTypeVariables`,
  and `TypeApplications` by default, which removes a chunk of per-file LANGUAGE
  pragma noise. Extensions that are not in GHC2024 (`OverloadedLabels`,
  `UndecidableInstances`, `FunctionalDependencies`, `DuplicateRecordFields`,
  `OverloadedRecordDot`, `AllowAmbiguousTypes`) are declared in the cabal file's
  `default-extensions`. The `vinyl`/`hspec`/`tasty` ecosystem support is
  unchanged from 9.8.
  Date: 2026-05-01

- Decision: `AllowAmbiguousTypes` is required for the `HasIndex` / `IsLabel`
  surface.
  Rationale: `HasIndex s rs r` carries the label `s` only as a type-class
  parameter; the method `indexOf :: Index rs r` does not mention `s` in its
  return type. The user disambiguates by `TypeApplications` (e.g.,
  `indexOf @s @rs @r` inside a recursive instance, or via `IsLabel`'s
  `fromLabel`-from-OverloadedLabels surface, which threads the `s` through
  the surface syntax `#email`). This is the standard pattern for
  label-resolved typeclass machinery and is well-tested in libraries like
  `superrecord` and `extensible`.
  Date: 2026-05-01

- Decision: 'OPack' carries a v1 hand-written inverse alongside the
  structural 'OutFields' (deviation from the DSL note's checklist).
  Rationale: the DSL note's chosen `Term` constructor set has 'TInpField'
  as the only input-reading constructor, and 'TInpField' wraps an opaque
  `ci -> r` function that 'solveOutput' cannot mechanically invert. The
  master-plan acceptance criterion ("'solveOutput' works on that
  example") requires `reconstitute` to actually succeed on the User
  Registration smoke-test event log; that is impossible with a purely
  structural 'solveOutput' as long as input reads are opaque. Two
  options were considered: (a) introduce a structural input projection
  ('TInpProj' or HasField/Generic-driven) now, which the DSL note
  flagged as a v2 priority and which would require non-trivial extra
  GADT machinery (per-constructor `InCtor` mirroring `WireCtor`); (b)
  add a hand-written `RegFile rs -> co -> Maybe ci` inverse field to
  'OPack', so 'solveOutput' delegates to user code while
  'checkHiddenInputs' still walks the structural 'OutFields'. Option
  (b) ships in v1 with minimal divergence from the DSL note; the
  structural 'OutFields' remains the contract for the hidden-input
  analysis, and the inverse field is the documented v1 escape hatch
  that v2 retires. The cost is that the synthesis claim of "mechanical
  apply derivation" is, in v1, "user-supplied per-edge apply" — honest
  about v1's limits while preserving the rest of the formalism
  (transducer composition, register evolution, hidden-input analysis).
  Date: 2026-05-01

- Decision: Stub bodies in M1 use `error "TODO: M<n>"` rather than `undefined`.
  Rationale: An `error` with a message points the maintainer to the specific
  milestone where the body lands, and shows up legibly in test transcripts if
  ever accidentally reached. `undefined` is just `error "Prelude.undefined"`
  with less information. The redundant-constraint warnings for `BoolAlg` on
  `delta`/`omega`/`step`/`reconstitute` are an expected M1 artefact: the
  bodies don't yet use the constraint, so GHC flags it. M2 makes them used.
  Date: 2026-05-01

- Decision: Test framework will be chosen at Milestone 2 between `hspec` and
  `tasty-hunit` based on whichever the eventual DSL note's surveys settle on as the
  least invasive dependency.
  Rationale: Defer to keep this plan independent of plan 1.
  Date: 2026-04-30


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

The keiki repository currently contains no Haskell code. The directory layout is:

    docs/
      foundations/    team onboarding (read 00-reading-guide.md first)
      research/       design notes for the library itself
    docs/masterplans/   coordination plans
    docs/plans/         execution plans (this is one)
    agents/skills/      tooling for plan creation (do not edit)
    .agents/  .seihou/  .claude/  internal tooling, ignore
    .gitignore       (excludes .claude/, .agents/, CLAUDE.local.md)

This plan adds Haskell project files at the repo root. The proposed layout (per the
boundary note's module proposal):

    keiki.cabal              cabal file
    cabal.project            single-package project manifest
    src/
      Keiki/
        Core.hs              pure types, evaluator, step, reconstitute, solveOutput
        Examples/
          UserRegistration.hs   the smoke test aggregate
    test/
      Spec.hs                test entry point (hspec or tasty)
      Keiki/
        CoreSpec.hs          micro-tests on the evaluator
        Examples/
          UserRegistrationSpec.hs  end-to-end smoke test

### Essential reads before starting

In order:

1. `docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md` —
   the working baseline. §2 has the type sketches at high level; §4 is the User
   Registration aggregate this plan must implement; §4 step 4 is the canonical
   demonstration of the hidden-input bug that Milestone 7 must reproduce; §7 settles
   the v1 predicate carrier as a first-class AST; §8 is the sequenced next steps —
   step 1 (type sketch) and step 2 (User Registration smoke test) are this plan.
2. **The DSL note**: `docs/research/dsl-shape-for-symbolic-register.md` (produced by
   plan 1). It contains the concrete constructors of every type in `Keiki.Core` and
   the "Prototype Implementation Checklist" that this plan implements. **If this file
   does not exist when you start, stop and complete plan 1 first.**
3. **The schema-evolution note**: `docs/research/schema-evolution.md` (produced by
   plan 2). The relevant takeaway for this plan is the v1 prototype scope — almost
   certainly "v1 prototype assumes a single static schema." This plan does not
   implement upcasting or versioning.
4. **The boundary note**: `docs/research/effects-boundary.md` (produced by plan 3).
   The relevant takeaways are: the v1 prototype implements only `Keiki.Core`, the
   `step` and `reconstitute` signatures, the time/randomness disciplines (timestamps
   and confirmation codes are command fields, not pulled from `IO`).
5. `docs/research/data-direction-c-symbolic-and-register-automata.md` — direction-C
   note. Read for the rationale behind copyless updates, the hidden-input check, and
   single-valuedness.

### Terms used in this plan

- **Symbolic-register transducer**: keiki's core type. State is `(s, RegFile rs)`.
  Edges combine guard, update, output, and target. Defined in detail in synthesis §2
  and concretized in the DSL note.
- **`RegFile rs`**: typed heterogeneous record indexed by a type-level list `rs`. The
  exact representation (hand-rolled GADT, `vinyl`, etc.) is chosen in the DSL note.
- **`Edge phi rs ci co s`**: a single transition. Carries `guard :: phi`,
  `update :: Update rs ci`, `output :: Maybe (OutTerm rs ci co)`, `target :: s`.
  `Nothing` output is the ε-edge.
- **`Term rs ci r`**, **`OutTerm rs ci co`**, **`Update rs ci`**: pure expression
  languages over the register file and input. Constructors defined in the DSL note.
- **`HsPred rs ci`**: the v1 predicate carrier, a first-class AST per synthesis §7.
  Has a `BoolAlg HsPred` instance.
- **`BoolAlg phi a`**: class making `phi` an effective Boolean algebra over `a` —
  `top`, `bot`, `conj`, `disj`, `neg`, `models`, `sat`, `isBot`. v1 instance:
  `BoolAlg (HsPred rs ci) (RegFile rs, ci)`.
- **`step`**: pure-layer entry point.
  `step t (s, regs) ci = Just (s', regs', maybeOutput)` if exactly one edge from `s`
  has a satisfied guard; `Nothing` otherwise.
- **`solveOutput`**: given an `OutTerm rs ci co` and an observed `co`, return a `ci`
  (and any read-from-register dependencies) such that evaluating the term on that
  input produces the observed output. The mechanism that derives `apply`.
- **`reconstitute`**: fold of `solveOutput` over an event log to recover state.
- **Hidden-input check**: a static analysis flagging edges where `update` or `guard`
  reads input fields not present in `output`. v1: optional, called explicitly via
  `checkHiddenInputs`. Synthesis §4 step 4 is the canonical instance.
- **Single-valuedness**: at most one edge whose guard is satisfied for any
  `(state, regs, input)`. v1: enforced lazily — `step` returns `Nothing` if multiple
  edges match. A property-test helper is a v1 nice-to-have.
- **Wire types**: ordinary Haskell sum types with payloads (commands and events).
  No GADT indexing. Used directly as `ci` and `co` in this plan.

### Tooling

The user's global instructions require using `mori` to find dependency source code:

- `mori registry list`
- `mori registry search <package>`
- `mori registry show <project> --full`
- `mori registry docs <project>`

For this plan, `mori` is needed when picking the test framework, when implementing
the `RegFile` representation chosen by the DSL note (read its source if `vinyl` was
chosen), and any time a dependency's API is unclear. **Never search `/nix/store`.**

### What the synthesis note already settles (do not re-litigate)

- C is the formalism, B is opt-in presentation. **B is out of scope for this plan.**
- Predicate carrier in v1 is a first-class AST.
- Single-valuedness is a property test in v1.
- v1 ships without SBV.
- Wire types are ordinary sum types with payloads.

### What this plan must not do

- Do not implement `Keiki.Runtime`, `InputSource`, `OutputSink`, or any `IO`-driven
  glue. Pure module only.
- Do not implement upcasters, versioning, or schema migration.
- Do not implement the optional B-view (per-vertex GADTs); a v1 user reads
  `regs ! #email` directly.
- Do not implement SBV-backed `BoolAlg`; the v1 instance is `HsPred` evaluated by
  Haskell function.
- Do not implement composition operators (`compose`, `lmapMaybeC`, etc.) — those are
  later plans.


## Plan of Work

Eight milestones, in order. Each one ends with a passing build (cabal builds; tests
pass). Commit at every milestone with the `MasterPlan:`, `ExecPlan:`, `Intention:`
trailers shown in the Concrete Steps section.

### Milestone 0 — Verify prerequisites

**Scope:** confirm the three design notes from plans 1, 2, 3 exist before any code
goes in.

**What will exist at the end:** confidence that this plan's hand-off contracts (the
DSL note, the schema-evolution note, the boundary note) are real.

**Steps:**

1. Confirm each file exists and is not empty:

       test -s docs/research/dsl-shape-for-symbolic-register.md && echo OK
       test -s docs/research/schema-evolution.md && echo OK
       test -s docs/research/effects-boundary.md && echo OK

   If any check fails, stop and complete the relevant plan first. The relevant plans
   are:

   - DSL: `docs/plans/1-sharpen-dsl-shape-for-symbolic-register-transducer.md`
   - Schema evolution: `docs/plans/2-sharpen-schema-evolution-for-events-and-registers.md`
   - Boundary: `docs/plans/3-sharpen-effects-boundary-between-pure-transducer-and-runtime.md`

2. Read the "Prototype Implementation Checklist" in the DSL note. Read the "v1
   prototype scope" paragraph in each of the schema-evolution and boundary notes. If
   any of these is missing, the prerequisite plan is not done — stop and finish it.

**Acceptance:** all three notes exist and contain the expected hand-off paragraphs.

### Milestone 1 — Project scaffolding and types compile

**Scope:** create the cabal project, define every type from the DSL note's checklist,
and have `cabal build` succeed with no implementations (just types and `undefined`
stubs where needed).

**What will exist at the end:**

- `keiki.cabal`, `cabal.project`.
- `src/Keiki/Core.hs` declaring `RegFile`, `Index`, `Term`, `OutTerm`, `Update`,
  `Edge`, `SymTransducer`, `HsPred`, `BoolAlg`. All compile.
- `cabal build` succeeds.

**Steps:**

1. Create `cabal.project`:

       packages: .

2. Create `keiki.cabal`. Use cabal format `3.0`. Library section exposes
   `Keiki.Core`. Set `default-language: GHC2021` (or GHC2024 if the chosen GHC
   supports it). Required GHC extensions per the DSL note (typically `DataKinds`,
   `GADTs`, `KindSignatures`, `TypeFamilies`, `OverloadedLabels`,
   `OverloadedRecordDot`, `DuplicateRecordFields`, `FlexibleContexts`,
   `FunctionalDependencies`, `MultiParamTypeClasses`, `RankNTypes`,
   `ScopedTypeVariables`, `StandaloneDeriving`, `TypeApplications`,
   `TypeOperators`).

   Initial dependency list: `base`, plus whatever `RegFile` representation the DSL
   note picked (e.g., `vinyl` if applicable). Add `text`, `time`, `containers` as
   they will be needed for the User Registration domain.

3. Create `src/Keiki/Core.hs` with the type declarations from the DSL note's
   "Prototype Implementation Checklist." Where a function or instance is required
   for the build to succeed, stub it with `undefined`. Add a documentation comment at
   the top of the module pointing readers to the synthesis note and the DSL note.

4. Run `cabal build`. Iterate on any type errors. Common causes: missing language
   extensions, `RegFile` representation not yet wired, label class instances
   missing.

5. Commit:

       git add keiki.cabal cabal.project src/Keiki/Core.hs \
               docs/plans/4-prototype-symbolic-register-core-with-user-registration-smoke-test.md \
               docs/masterplans/1-validate-symbolic-register-direction-via-haskell-prototype.md
       git commit -m "$(cat <<'EOF'
       feat(core): scaffold Keiki.Core with type declarations only

       Project skeleton (cabal, cabal.project), pure module Keiki.Core with
       RegFile, Index, Term, OutTerm, Update, Edge, SymTransducer, HsPred,
       and the BoolAlg class. No implementations yet; cabal build succeeds.

       MasterPlan: docs/masterplans/1-validate-symbolic-register-direction-via-haskell-prototype.md
       ExecPlan: docs/plans/4-prototype-symbolic-register-core-with-user-registration-smoke-test.md
       Intention: intention_01knjzws4qezz9w8b0743zfqv8
       EOF
       )"

**Acceptance:**

    cabal build
    # exits 0; produces "Linking ... " or equivalent.

### Milestone 2 — Bare-minimum evaluator

**Scope:** implement the evaluator functions on the AST: `evalTerm`, `evalOut`,
`runUpdate`, the `BoolAlg HsPred` instance, and the projections `delta` and `omega`.
Add a synthetic micro-test.

**What will exist at the end:**

- All pure projections in `Keiki.Core` work on a tiny synthetic transducer (no
  register reads, two vertices, one input alphabet `Bool`).
- `cabal test` passes one micro-test.

**Steps:**

1. Implement `evalTerm :: Term rs ci r -> RegFile rs -> ci -> r` by structural
   recursion on the `Term` constructors defined in the DSL note. For the v1 `Inp`
   constructor that wraps a `ci -> r`, just apply the function.

2. Implement `evalOut :: OutTerm rs ci co -> RegFile rs -> ci -> co` similarly.

3. Implement `runUpdate :: Update rs ci -> RegFile rs -> ci -> RegFile rs`. The
   `Combine` constructor must respect distinct targets — for v1, document that the
   user is responsible for distinctness, and apply both updates in sequence.

4. Implement `models` for the `BoolAlg HsPred` instance: structurally evaluate
   `HsPred` to `Bool` using `evalTerm` on the embedded `Term`s and direct evaluation
   for `PEq`, `PMatchC`, etc.

5. Implement `delta` and `omega` per synthesis §2:

       delta :: SymTransducer phi rs s ci co
             -> s -> RegFile rs -> ci -> Maybe (s, RegFile rs)
       delta t s regs ci = case
         [ (target e, runUpdate (update e) regs ci)
         | e <- edgesOut t s, models (guard e) (regs, ci) ] of
           [single] -> Just single
           _        -> Nothing

       omega :: SymTransducer phi rs s ci co
             -> s -> RegFile rs -> ci -> Maybe co
       omega t s regs ci = case
         [ evalOut o regs ci
         | e <- edgesOut t s, models (guard e) (regs, ci), Just o <- [output e] ] of
           [o] -> Just o
           _   -> Nothing

6. Add `test/Spec.hs` and a test module exercising a 2-vertex, no-register
   transducer with a `Bool` alphabet. Pick the test framework (per Decision Log,
   defer to whatever the DSL note's environment chose; if the DSL note didn't
   choose, default to `hspec`). Add it to the cabal `test-suite` stanza.

7. Run `cabal test`. Iterate.

8. Commit:

       git commit -m "$(cat <<'EOF'
       feat(core): bare-minimum evaluator on synthetic transducer

       Implement evalTerm, evalOut, runUpdate, BoolAlg HsPred, and delta/omega
       projections. Add a synthetic 2-vertex test that exercises every
       projection. cabal test passes.

       MasterPlan: docs/masterplans/1-validate-symbolic-register-direction-via-haskell-prototype.md
       ExecPlan: docs/plans/4-prototype-symbolic-register-core-with-user-registration-smoke-test.md
       Intention: intention_01knjzws4qezz9w8b0743zfqv8
       EOF
       )"

**Acceptance:**

    cabal test
    # micro-test passes; synthetic delta/omega behave per construction.

### Milestone 3 — `step` and `reconstitute` skeletons

**Scope:** implement `step` and `reconstitute` so the boundary-note's pure entry
points exist, even though `solveOutput` is still a stub.

**What will exist at the end:**

- `step :: SymTransducer phi rs s ci co -> (s, RegFile rs) -> ci -> Maybe (s, RegFile rs, Maybe co)`
  combining `delta` and `omega`.
- `reconstitute :: SymTransducer phi rs s ci co -> [co] -> Maybe (s, RegFile rs)`
  defined as a left-fold of `solveOutput` followed by `step`. `solveOutput` returns
  `Nothing` for now; the synthetic test calling `step` directly still passes.

**Steps:**

1. Implement `step` by combining the existing `delta` and `omega` projections so
   that a single matching edge produces `(s', regs', Just co)` (or `Nothing` if the
   edge has `output = Nothing`).

2. Stub `solveOutput :: OutTerm rs ci co -> co -> Maybe ci` returning `Nothing`.

3. Implement `reconstitute t evs = foldM consume (initial t, initialRegs t) evs`
   where `consume (s, regs) co = solveOutput edge.output co >>= \ci -> step t (s, regs) ci >>= \(s', regs', _) -> pure (s', regs')`.
   Sketch the logic against the DSL note's `OutTerm` shape; the precise structure
   depends on whether `OutTerm` is structural or Generic-driven.

4. Add a tiny test exercising `step` directly (no `reconstitute`) on the synthetic
   transducer.

5. Run `cabal test`. Commit.

**Acceptance:**

    cabal test
    # step micro-test passes; reconstitute is callable but not exercised yet.

### Milestone 4 — `solveOutput` for `OutTerm`

**Scope:** implement `solveOutput` by walking the `OutTerm` AST. This is the most
research-flavored milestone — the implementation depends entirely on the `OutTerm`
shape chosen by the DSL note.

**What will exist at the end:**

- `solveOutput :: OutTerm rs ci co -> co -> Maybe ci` returns the input that
  produced a given output, when one exists.
- A micro-test: define a single edge whose output is `Pack OutCtor [Inp .field1, Inp .field2]`,
  evaluate it on a known `ci` to get a `co`, then call `solveOutput` on that `co`
  and assert the result equals the original `ci`.

**Steps:**

1. Re-read the DSL note's `OutTerm` definition. The shape determines the algorithm:

   - **Structural `Pack`-style:** walk the `Pack` constructors recursively; for each
     `Inp .field` leaf, read the corresponding field of the observed `co` and bind
     it. Combine bindings into a `ci`.
   - **Generic-driven:** walk the generic representation; for each leaf, do the
     same.

2. Implement the algorithm. Where `OutTerm` allows `Reg` (read register), the
   register value is also recoverable — the algorithm must verify that the
   observed-output field equals the register read, returning `Nothing` if not. (This
   is exactly the synthesis §4 step 4 mechanism.)

3. Where `OutTerm` allows arbitrary Haskell functions (the v1 `Inp` opaque escape
   hatch via `mkOut`), `solveOutput` returns `Nothing`. Document this in the module
   docstring as a known v1 limitation; it's exactly what the v2 structural `OutTerm`
   would fix.

4. Add a micro-test in `test/Keiki/CoreSpec.hs`:
   - Define a tiny `OutCtor` data with two `Int` fields.
   - Define an `OutTerm rs Int OutCtor` of `Pack OutCtor [Inp id, Inp (+1)]` (or
     analogous given the chosen DSL).
   - Evaluate on `5` → `OutCtor 5 6`.
   - Call `solveOutput` on `OutCtor 5 6` and assert `Just 5`.

5. Run `cabal test`. Iterate.

6. Implement `checkHiddenInputs :: SymTransducer phi rs s ci co -> [HiddenInputWarning]`
   as an optional analysis. For each edge, walk `update` and `guard` to collect input
   field accesses, walk `output` to collect input field appearances, and report any
   discrepancy. v1 may approximate by reporting per-edge "uses opaque ci function" if
   the analysis can't see through `Inp .: ci -> r` — that's still useful diagnostic.

7. Commit.

**Acceptance:**

    cabal test
    # solveOutput micro-test passes on a Pack-style OutTerm.

### Milestone 5 — User Registration aggregate

**Scope:** define the User Registration domain and the `userReg` transducer in
`Keiki.Examples.UserRegistration`, using only `Keiki.Core` constructors.

**What will exist at the end:**

- `src/Keiki/Examples/UserRegistration.hs` containing:
  - Domain types: `Email`, `ConfirmationCode`, plus the synthesis-§4 command/event
    payload records (`StartRegistrationData`, `ConfirmAccountData`, etc.).
  - `data UserCmd = StartRegistration … | ConfirmAccount … | …`
  - `data UserEvent = RegistrationStarted … | …`
  - `type UserRegRegs = '[ "email" ':-> Email, … ]` (or whatever shape the DSL note
    settled on).
  - `data Vertex = PotentialCustomer | Registering | RequiresConfirmation | Confirmed | Deleted`
  - `userReg :: SymTransducer (HsPred UserRegRegs UserCmd) UserRegRegs Vertex UserCmd UserEvent`
- The module compiles.

**Steps:**

1. Translate synthesis §4's `userReg` definition into Haskell, replacing every
   pseudosyntactic helper with the concrete DSL constructors from the DSL note. Where
   the DSL note's helpers don't cover something (e.g., `freshCode`), apply the
   randomness-discipline rule from the boundary note: `freshCode` becomes a field of
   `ResendConfirmationData`, generated outside the transducer.

2. Compile. Iterate on type errors. Common issues: register-file slot indexing,
   `OverloadedLabels` syntax, `OverloadedRecordDot` syntax, `DuplicateRecordFields`
   for the `at` and `email` field names that appear in many records.

3. Commit.

**Acceptance:**

    cabal build
    # Keiki.Examples.UserRegistration compiles.

### Milestone 6 — End-to-end test passes (fixed schema)

**Scope:** wire the User Registration aggregate through `reconstitute` with the
fixed event schema (per synthesis §4 fix-1), and assert the test passes.

**What will exist at the end:**

- `test/Keiki/Examples/UserRegistrationSpec.hs` containing:
  - The five-event log from synthesis §4 (with `confirmCode` added to
    `AccountConfirmed`).
  - A test that calls `reconstitute userReg events` and asserts
    `Just (Deleted, expectedRegs)`.
- `cabal test` passes.

**Steps:**

1. Construct the event log:

       events =
         [ RegistrationStarted   (RegistrationStartedData "alice@x" "Z9F4" t0)
         , ConfirmationEmailSent (ConfirmationEmailSentData "alice@x")
         , ConfirmationResent    (ConfirmationResentData "alice@x" "K2P7" t1)
         , AccountConfirmed      (AccountConfirmedData "alice@x" "K2P7" t2)  -- fix-1
         , AccountDeleted        (AccountDeletedData "alice@x" t3)
         ]

   Note `AccountConfirmedData` carries `confirmCode` per synthesis §4 fix-1 — the
   plan's User Registration definition must match this shape.

2. Compute `expectedRegs` by hand from synthesis §4's walkthrough.

3. Write the spec:

       it "reconstitutes the canonical event log to (Deleted, expectedRegs)" $
         reconstitute userReg events `shouldBe` Just (Deleted, expectedRegs)

4. Run `cabal test`. Iterate. If `solveOutput` returns `Nothing` for any event, debug
   by stepping through each event in isolation and comparing against synthesis §4's
   step-by-step trace.

5. Commit.

**Acceptance:**

    cabal test
    # User Registration end-to-end test passes.
    # Output includes a transcript like:
    #   reconstitutes the canonical event log to (Deleted, expectedRegs) [✓]

### Milestone 7 — Hidden-input check fires (unfixed schema)

**Scope:** demonstrate that the synthesis-§4 hidden-input bug is detectable. With
the unfixed `AccountConfirmedData` (no `confirmCode` field), the check reports a
problem.

**What will exist at the end:**

- A second `AccountConfirmedDataV0` (or a separate `userRegV0` transducer with the
  unfixed event shape).
- A test that runs `checkHiddenInputs userRegV0` and asserts the result lists the
  bad edge.
- Optionally, a test that calls `reconstitute userRegV0 events` and asserts the
  failure mode.
- `cabal test` passes both new tests.

**Steps:**

1. Either:
   - Add a second module `Keiki.Examples.UserRegistrationV0` that mirrors V5 but
     omits `confirmCode` from `AccountConfirmedData`, and changes the `Confirm` edge
     accordingly so the type-check still works (the edge's `output` term won't
     mention `d.confirmCode`); or
   - Parameterize the existing module by the schema variant.

   The first option is simpler; pick it unless the DSL note's representation makes
   the second easier.

2. Add tests:

       it "checkHiddenInputs surfaces the AccountConfirmed/confirmCode hole" $
         checkHiddenInputs userRegV0 `shouldNotBe` []

       it "reconstitute userRegV0 fails or returns Nothing" $
         reconstitute userRegV0 v0Events `shouldSatisfy` (\r -> r == Nothing || isWrong r)

   The second test depends on which failure mode the implementation produces; pick
   the matching assertion.

3. Run `cabal test`. Iterate.

4. Commit.

**Acceptance:**

    cabal test
    # All previous tests still pass; the two new tests in this milestone also pass,
    # demonstrating that the build-time check catches the unfixed schema.

### Milestone 8 — Ergonomic verdict

**Scope:** read `Keiki.Examples.UserRegistration` side-by-side with synthesis §4 and
write a paragraph in the Outcomes & Retrospective section judging whether the DSL is
tolerable.

**What will exist at the end:**

- A "Verdict" subsection under Outcomes & Retrospective in this plan, stating:
  tolerable / painful but workable / blocking. If blocking, name the specific pain
  points and propose follow-up plans.
- An updated note in the master plan's Outcomes & Retrospective section reflecting
  the verdict.

**Steps:**

1. Open synthesis §4's `userReg` block.
2. Open `src/Keiki/Examples/UserRegistration.hs`.
3. Read both top to bottom. For each pseudosyntactic helper in §4, find its concrete
   counterpart in the Haskell. Note any place where the Haskell version is
   significantly more verbose, harder to read, or required workarounds (e.g.,
   explicit `@type` applications, type signatures the user wouldn't expect to write).
4. Write the verdict paragraph. Be honest. If the DSL is painful, that's the
   surfaced finding; record it and propose a v1.5 plan to revise.
5. Update the master plan's Outcomes & Retrospective.
6. Commit.

**Acceptance:** the verdict paragraph exists in this plan and in the master plan.
The master plan's Progress section has every milestone checked off.


## Concrete Steps

All work happens at the repository root: `/Users/shinzui/Keikaku/bokuno/keiki`.

For each milestone above, the loop is the same: edit the relevant files, run
`cabal build` then `cabal test`, iterate on errors, commit on green.

Per-milestone commit message template (replace `<short summary>` with milestone
content):

    git commit -m "$(cat <<'EOF'
    feat(core): <short summary>

    <one-paragraph body explaining what changed and why>

    MasterPlan: docs/masterplans/1-validate-symbolic-register-direction-via-haskell-prototype.md
    ExecPlan: docs/plans/4-prototype-symbolic-register-core-with-user-registration-smoke-test.md
    Intention: intention_01knjzws4qezz9w8b0743zfqv8
    EOF
    )"

If the user uses cabal-install via Nix or similar, the cabal commands work
unmodified inside the appropriate shell.


## Validation and Acceptance

The master plan's acceptance criterion: *"if AST surface ergonomics are tolerable
and `solveOutput` works on that example, the synthesis holds."* This plan satisfies
that criterion when:

1. `cabal test` exits 0 with all of:
   - the synthetic evaluator micro-test passing (Milestone 2);
   - the `step` micro-test passing (Milestone 3);
   - the `solveOutput` Pack-style micro-test passing (Milestone 4);
   - the User Registration end-to-end test passing on the fixed schema (Milestone 6);
   - the hidden-input check tests passing on the unfixed schema (Milestone 7).
2. The Outcomes & Retrospective verdict (Milestone 8) is "tolerable" or "painful but
   workable." If "blocking," the synthesis does not hold as currently formulated and
   a follow-up plan is required — the master plan's master verdict reflects this.

Concrete validation commands at completion:

    cabal build
    # exits 0

    cabal test --test-show-details=direct
    # all tests pass; output transcript shows the User Registration end-to-end
    # test by name and the hidden-input check tests by name

A reviewer who has read only the synthesis note and the design notes from plans 1-3
should be able to read `src/Keiki/Examples/UserRegistration.hs` and recognize it as
the synthesis-§4 aggregate.


## Idempotence and Recovery

The cabal build is idempotent: running `cabal build` repeatedly is safe; running
`cabal test` repeatedly is safe. Re-running individual milestones is the expected
workflow when iterating on type errors.

Adding a slot to `RegFile` or a constructor to `Term`/`OutTerm` mid-implementation is
a re-design moment — it means the DSL note's checklist was incomplete. When this
happens: stop, update the DSL note (via plan 1's update mode), then resume here.
Document the round-trip in this plan's Decision Log.

If `solveOutput` fails on a User Registration event that the synthesis walkthrough
says should succeed, the most likely cause is `OutTerm` opacity (the `mkOut`
escape-hatch closed over a Haskell function the AST can't see through). Fix in the
User Registration definition by replacing `mkOut $ \regs ci -> …` with the structural
`Pack` constructor for the relevant event. If the structural form doesn't exist in
the DSL note, file an update to plan 1.


## Interfaces and Dependencies

Inputs (consumed by this plan):

- `docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md` —
  baseline.
- `docs/research/dsl-shape-for-symbolic-register.md` — the DSL constructors and the
  Prototype Implementation Checklist. **Hard prerequisite.**
- `docs/research/schema-evolution.md` — directional input ("v1: single static
  schema"). **Hard prerequisite.**
- `docs/research/effects-boundary.md` — directional input (`step` and
  `reconstitute` signatures, time/randomness disciplines, "v1 implements only
  `Keiki.Core`"). **Hard prerequisite.**

Outputs (produced by this plan):

- `keiki.cabal`, `cabal.project` — project manifest.
- `src/Keiki/Core.hs` — pure types and evaluator.
- `src/Keiki/Examples/UserRegistration.hs` — smoke-test aggregate.
- `test/Spec.hs`, `test/Keiki/CoreSpec.hs`, `test/Keiki/Examples/UserRegistrationSpec.hs`.
- This plan's living sections, kept current.
- The master plan's Exec-Plan Registry, Progress, Outcomes sections, updated on
  completion.

Library dependencies (initial set, expand as the DSL note dictates):

- `base` (the GHC base library; provides `Maybe`, `Either`, etc.).
- `text` (for `Email` and similar string types).
- `time` (for `UTCTime`).
- `containers` (for `Set`, `Map` if needed).
- `vinyl` (only if the DSL note picked it for `RegFile`; otherwise none).
- `hspec` or `tasty` + `tasty-hunit` (for tests; pick at Milestone 2).

Tooling:

- `cabal-install` ≥ 3.10 (for `cabal build` / `cabal test`).
- GHC 9.8 LTS (per Decision Log).
- `mori` for any dependency source-code reading. **Never search `/nix/store`.**
- `git` for commits with the required trailers.
