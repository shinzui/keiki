---
id: 10
slug: keiki-decider-facade-for-naive-decider-migration
title: "Keiki.Decider facade for naive-decider migration"
kind: exec-plan
created_at: 2026-05-01T22:06:49Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
master_plan: "docs/masterplans/3-keiki-generics-dx-follow-ups.md"
---

# Keiki.Decider facade for naive-decider migration

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

The keiki library models event sourcing as a *symbolic-register
transducer*: each edge of a finite-state machine carries a guard
predicate, an update on the register file, an output term that emits
an event, and a target vertex. The forward direction (`omega`)
emits events; the inverse direction (`applyEvent` + `solveOutput`)
replays events to reconstitute state mechanically.

In the wider functional event-sourcing world, the most common
authoring shape is the *Decider* pattern from Jérémie Chassaing's
*Functional Event Sourcing Decider* paper. In Haskell:

    data Decider c e s = Decider
      { decide       :: c -> s -> [e]
      , evolve       :: s -> e -> s
      , initialState :: s
      , isTerminal   :: s -> Bool
      }

`decide` produces zero or more events from a command and the current
state; `evolve` folds events into the state on replay; `isTerminal`
identifies absorbing states. The pattern is portable, well-known,
and has tooling around it (test fixtures, property generators,
projection helpers) that users coming from naive-decider codebases
already understand.

The `keiki-generics-design.md` note catalogues this gap as **item E**
in its Future Improvements list:

> ### E. Generic-derived Decider façade
>
> For users coming from the naive-decider world, exposing a
> `toDecider` projection from a `SymTransducer` to a `Decider`-shaped
> record would smooth the migration. The `decide` function comes from
> `omega`; the `evolve` function comes from a `delta`-with-event
> reformulation built atop `applyEvent`/`solveOutput`. The keiki
> formalism guarantees they agree. This is ~2 hours of plumbing on a
> new module `Keiki.Decider`.

After this plan is complete, the repository contains:

- A new module `src/Keiki/Decider.hs` exporting:
  - A polymorphic record `Decider c e s` matching the Chassaing
    shape verbatim.
  - A function `toDecider :: BoolAlg phi (RegFile rs, ci) =>
    SymTransducer phi rs s ci co -> Decider ci co (s, RegFile rs)`
    that materializes the façade. `decide` calls `omega`; `evolve`
    calls `applyEvent`; `initialState` pairs the transducer's
    `initial` with `initialRegs`; `isTerminal` lifts `isFinal` to
    the `(s, RegFile rs)` carrier.
  - Documentation enumerating the **two semantic gaps** between the
    keiki transducer and the naive Decider that callers must
    understand: ε-edges (state changes without emitted events; the
    naive Decider has no concept of these) and edge non-uniqueness
    (the naive Decider returns a list `[e]`, the keiki transducer
    returns `Maybe co`; the façade lifts to a singleton list).
- A new test module `test/Keiki/DeciderSpec.hs` exporting one
  hspec spec, wired into `test/Spec.hs`.
- Two test cases:
  1. `toDecider userReg` round-trip on the canonical log: feed
     the canonical command sequence through `decide`/`evolve`, get
     back the same `(Deleted, expectedRegs)` snapshot that
     `omega`/`reconstitute` produces.
  2. ε-edge documentation test: the User Registration aggregate's
     GDPR-from-RequiresConfirmation edge has `output = Nothing`.
     Show that `decide` returns `[]` for that command, but
     `evolve` is **not** called (because there is no event to fold)
     — and assert that the state therefore does *not* transition
     in a `decide`-then-`evolve` cycle. Cross-reference: the
     equivalent `delta` call would transition. Document the
     limitation in a Surprises & Discoveries entry of this plan and
     in the new module's haddock.
- An update to `docs/research/keiki-generics-design.md` retiring
  item E with a pointer to this plan and to `Keiki.Decider`.

How a future contributor sees this work:

    cabal test
    # 70 → 72+ examples (depending on intermediate test counts), 0 failures.
    # Includes "toDecider userReg" round-trip on canonical log.

The user-visible win: a user familiar with the naive-decider shape
can adopt keiki's symbolic core via a one-liner adapter, without
rewriting their event-sourcing harness.


## Progress

Use a checklist to summarize granular steps. Every stopping point
must be documented here, even if it requires splitting a partially
completed task into two ("done" vs. "remaining"). This section must
always reflect the actual current state of the work.

- [x] **Milestone 0 — Verify prerequisites** (2026-05-01). `cabal
      build all` and `cabal test all` are green when run inside
      `nix-shell -p z3` — the latter reports **70 examples, 0
      failures**. Toolchain: GHC 9.12.3, cabal-install 3.16.1.0,
      base ^>= 4.21, sbv >= 11.7 && < 15. The canonical fixture is
      not a command list but the **event log** `canonicalLog` in
      `test/Keiki/Examples/UserRegistrationSpec.hs:34-41`; this
      plan's M3 derives a matching command list (see Surprises &
      Discoveries → "Canonical command list").
- [x] **Milestone 1 — Design milestone** (2026-05-01). Design
      choices appended to `docs/research/keiki-generics-design.md`'s
      "### E. Generic-derived Decider façade" subsection: four-field
      Chassaing canonical record (`decide`/`evolve`/`initialState`
      /`isTerminal`); state carrier `(s, RegFile rs)`; signature
      `toDecider :: BoolAlg phi (RegFile rs, ci) => SymTransducer
      phi rs s ci co -> Decider ci co (s, RegFile rs)`; `Maybe co`
      lifted to `[]`/`[co]`; ε-edges documented as a façade
      limitation (decide returns `[]`, state is unchanged) rather
      than re-encoded as synthetic events. See Decision Log entries
      D1–D4 below.
- [x] **Milestone 2 — Add the module** (2026-05-01).
      `src/Keiki/Decider.hs` ships `Decider (..)` and `toDecider`
      with full module + symbol haddock covering the two semantic
      gaps. `keiki.cabal` exposes the module. `cabal build all`
      succeeds. REPL signature check inside `cabal repl keiki`:
      `toDecider :: BoolAlg phi (RegFile rs, ci) => SymTransducer
      phi rs s ci co -> Decider ci co (s, RegFile rs)` — matches
      the design exactly. Side discovery: `Keiki.Core.applyEvent`
      was not in the export list (only `delta`/`omega`/`step`/
      `reconstitute`/`solveOutput` were); added to the
      `Pure-layer entry points` section of the export list. See
      Decision Log D6.
- [x] **Milestone 3 — Round-trip test** (2026-05-01).
      `test/Keiki/DeciderSpec.hs` carries five hspec cases:
      canonical-log round-trip lands `(Deleted, expectedSnapshot)`;
      `isTerminal` agrees; the very-first-command emits exactly
      one event; the ε-edge limitation case (next milestone); and
      a `delta`-cross-check showing the underlying transducer can
      still drive the ε-edge. Wired into `test/Spec.hs` (one
      `import qualified` + one `describe`) and into
      `keiki.cabal`'s `keiki-test:other-modules`. `nix-shell -p z3
      --run 'cabal test all'` reports **75 examples, 0 failures**
      (70 baseline + 5 new).
- [x] **Milestone 4 — ε-edge limitation test + haddock**
      (2026-05-01). The dedicated ε-edge test is in the spec from
      M3: drive the aggregate through `StartRegistration` +
      `Continue` to land at `RequiresConfirmation`, then attempt
      `FulfillGDPRRequest` — `decide` returns `[]`, `evolve` over
      `[]` is a no-op, and the state stays at
      `RequiresConfirmation`. The cross-check test confirms that
      `delta` on the same input transitions to `Deleted`, locating
      the limitation at the façade boundary. The haddock for
      `toDecider` already includes the `Two semantic gaps` and
      `Worked illustration of the two semantic gaps` sections from
      M2; `cabal haddock all` renders them under `Keiki-Decider.html`
      with no new warnings (pre-existing warnings are about generic
      rep types in `Keiki.Core` and `UserRegistration`, unrelated to
      the new module).
- [x] **Milestone 5 — Update design note + commit** (2026-05-01).
      `docs/research/keiki-generics-design.md`'s "### E.
      Generic-derived Decider façade" subsection carries the EP-10
      design paragraph (added during M1) and an "**Implemented
      (see EP-10).**" pointer paragraph back to this plan and to
      `src/Keiki/Decider.hs`. The single commit stages exactly the
      EP-10-specific files:

      - `src/Keiki/Core.hs` (export `applyEvent`)
      - `src/Keiki/Decider.hs` (new)
      - `test/Keiki/DeciderSpec.hs` (new)
      - `test/Spec.hs` (wire DeciderSpec into the runner)
      - `keiki.cabal` (exposed-modules + other-modules)
      - `docs/research/keiki-generics-design.md` (item E retirement)
      - `docs/masterplans/3-keiki-generics-dx-follow-ups.md`
        (the master plan EP-10 implements)
      - `docs/plans/10-keiki-decider-facade-for-naive-decider-migration.md`
        (this plan)

      Sibling files left untracked at session start
      (`docs/masterplans/4`, `docs/plans/{7,8,9,11}`,
      `flake.lock`, `flake.nix`, `treefmt.nix`,
      `.seihou/config.dhall`, plus modifications to `.gitignore`
      and `.seihou/manifest.json`) are *not* part of EP-10 and
      remain untracked for separate commits. `git log -1
      --format=%B HEAD` shows the three trailers (`MasterPlan`,
      `ExecPlan`, `Intention`).


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights
discovered during implementation. Provide concise evidence.

- **z3 is not on PATH in the default environment** (2026-05-01).
  `flake.nix`'s `devShells.default` does not include `pkgs.z3`, and
  the bare shell has no `z3` binary. Running `cabal test all`
  outside a z3-providing shell yields 25 failures from the
  symbolic specs (`Unable to locate executable for Z3`). Workaround
  for this plan's M3/M4 runs: `nix-shell -p z3 --run 'cabal test
  all'`. Adding z3 to the flake's `nativeBuildInputs` is a small
  ergonomic fix orthogonal to EP-10's scope; flagged for a possible
  follow-up but not addressed here.

- **Canonical command list is not in the spec** (2026-05-01). The
  spec at `test/Keiki/Examples/UserRegistrationSpec.hs:34-41`
  fixes a `canonicalLog :: [UserEvent]` (the synthesis §4 fix-1
  schema); it does not record the matching command sequence
  because `reconstitute`'s job is "given the events, recover the
  state". For EP-10's `decide`/`evolve` round-trip we need the
  forward direction, so the spec derives `canonicalCmds ::
  [UserCmd]` by reading each event back to the command that
  produced it on the User Registration edge graph:

      [ StartRegistration  (StartRegistrationData  "alice@x" "Z9F4" (t 0))
      , Continue
      , ResendConfirmation (ResendConfirmationData         "K2P7" (t 100))
      , ConfirmAccount     (ConfirmAccountData             "K2P7" (t 200))
      , FulfillGDPRRequest (FulfillGDPRRequestData                 (t 300))
      ]

  Compared to the EP-10 plan's schematic four-step sketch, the
  real fixture has five steps (an extra `ResendConfirmation`
  between `Continue` and `ConfirmAccount`).


## Decision Log

Record every decision made while working on the plan.

- **D1 (2026-05-01) — Record shape: Chassaing canonical, four
  fields verbatim.** `data Decider c e s = Decider { decide ::
  c -> s -> [e], evolve :: s -> e -> s, initialState :: s,
  isTerminal :: s -> Bool }`. Rationale: the EP-10 plan's purpose is
  *migration ergonomics*, not "a slightly different Decider." Any
  deviation (e.g. an explicit `Maybe e` field, or splitting the
  register file from `s`) defeats the drop-in-adapter goal.

- **D2 (2026-05-01) — State carrier: `(s, RegFile rs)`.** The
  registers must be carried because `omega` evaluates edge guards
  against `(regs, ci)`. Carrying them as the second component of
  the Chassaing `s` keeps the user code pure-functional and avoids
  any "current registers" mutable state on the side.

- **D3 (2026-05-01) — `Maybe co → [e]` lift.** `omega` returns at
  most one event; `Just co` lifts to `[co]`, `Nothing` to `[]`.
  Rationale: the keiki transducer is single-event by construction;
  multi-event commands are the synthesis §5 *MultiDecider*
  extension and explicitly out of scope here.

- **D4 (2026-05-01) — ε-edges are silent in the façade.** When an
  edge's `output = Nothing`, `decide` returns `[]` and a
  subsequent `evolve` on `[]` is a no-op — so the state does not
  transition through the façade. Rationale: the alternatives
  (synthesizing internal events; changing the record shape to
  carry `Maybe e` or `Either NoEvent e`) all break the "Chassaing
  canonical" promise. Documented as a limitation in haddock and
  asserted by an explicit test (M4).

- **D5 (2026-05-01) — Defensive `evolve`-Nothing branch.** When
  `applyEvent` returns `Nothing` (malformed log: an event that no
  outgoing edge from `s` would emit), `evolve` keeps the current
  state rather than throwing. Rationale: Chassaing's `evolve` has
  no `Maybe` in the return type, so the façade must commit to
  one. Returning the input state is the conservative choice; a
  caller who wants strict replay can layer an `applyEvent` check
  themselves.

- **D6 (2026-05-01) — Export `Keiki.Core.applyEvent`.** The
  function existed but was not in `Keiki.Core`'s export list (the
  haddock called it an "Internal helper for `reconstitute`").
  `Keiki.Decider`'s `evolve` is a single-event façade over
  `applyEvent`, so the function had to be either re-exposed or
  duplicated. Re-exposing keeps a single source of truth and is
  consistent with the EP-10 plan's "Interfaces and Dependencies"
  section, which already listed `applyEvent` as a consumed
  function. Updated the haddock to reflect the broader role.


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones
or at completion. Compare the result against the original purpose.

**Result vs. purpose (2026-05-01).** EP-10 shipped the
Chassaing-shape `Decider c e s` record and the
`toDecider :: SymTransducer ... -> Decider ci co (s, RegFile rs)`
projection in `src/Keiki/Decider.hs`. A user familiar with the
naive-decider shape can now adopt keiki's symbolic core via:

    import qualified Keiki.Decider as KD
    let d = KD.toDecider userReg
    -- KD.decide d :: UserCmd -> (Vertex, RegFile UserRegRegs) -> [UserEvent]
    -- KD.evolve d :: (Vertex, RegFile UserRegRegs) -> UserEvent -> (Vertex, RegFile UserRegRegs)

The five hspec cases in `test/Keiki/DeciderSpec.hs` confirm the
canonical-log round-trip lands at `(Deleted, expectedSnapshot)` —
the same end state `Keiki.Examples.UserRegistrationSpec`'s
`reconstitute` proves from the inverse direction.

**Two limitations made explicit, not papered over.**

1. *ε-edges.* The User Registration `FulfillGDPRRequest` edge
   from `RequiresConfirmation` has `output = Nothing`; through
   the façade `decide` returns `[]` and the state therefore
   does not transition. The companion test (case 5) shows
   `Keiki.Core.delta` on the identical input *does* transition
   to `Deleted`, locating the limitation precisely at the
   façade boundary rather than in the underlying transducer.
2. *Single-event lift.* `omega` returns `Maybe co`; the façade
   lifts to a 0-or-1-element list. A future *MultiDecider*
   (synthesis §5) would relax this — out of scope for EP-10.

Both limitations are documented in the module-level haddock and
in `toDecider`'s symbol haddock, with worked code examples that a
reader does not need to consult this plan to understand.

**Scope discipline.** The plan scoped `Keiki.Decider` strictly as
*plumbing*: no new external libraries, no changes to
`build-depends`, no migration of existing examples. The only
non-trivial source change outside the new module was exporting
`Keiki.Core.applyEvent` (Decision D6); every other change was
strictly additive. EP-10 did not touch `Keiki.Examples.UserRegistration.hs`,
the `Keiki.Generics` machinery, or the symbolic SBV layer — those
are EP-8 and EP-9's territory under MP-3.

**Open follow-ups (not blocking).**

- The flake's dev shell does not include `pkgs.z3`, so running
  the full test suite outside `nix-shell -p z3` produces 25
  failures from the SBV-backed specs. Adding z3 to
  `nativeBuildInputs` is a small ergonomic fix orthogonal to
  EP-10 but would make the project bootstrap-friendlier.
- A *MultiDecider* relaxation of the single-event lift is the
  natural extension when synthesis §5's process-manager
  examples come online.

**Lessons.** The two-step structure of "design milestone first,
then code" was high-value here: writing out the ε-edge limitation
as a deliberate-and-documented gap (rather than pretending it
didn't exist) made the `decide`-returns-`[]` test feel like
*confirming a design choice* rather than *encoding a bug*.


## Context and Orientation

Describe the current state relevant to this task as if the reader
knows nothing.

The keiki library is in `/Users/shinzui/Keikaku/bokuno/keiki/`. Its
source tree as of plan-start:

    src/Keiki/
    ├── Core.hs        — formalism: SymTransducer, Term, OutTerm, etc.
    ├── Generics.hs    — Generic-derived ctor helpers
    ├── Symbolic.hs    — SBV-backed BoolAlg instance
    └── Examples/
        ├── UserRegistration.hs    — canonical worked example
        └── UserRegistrationV0.hs  — V0 with hidden-input demo

    test/Keiki/
    ├── CoreSpec.hs, SymbolicSpec.hs
    └── Examples/
        ├── UserRegistrationSpec.hs
        ├── UserRegistrationSymbolicSpec.hs
        └── UserRegistrationV0Spec.hs

**Key shapes from `src/Keiki/Core.hs`:**

The `SymTransducer` record:

    data SymTransducer phi rs s ci co = SymTransducer
      { edgesOut    :: s -> [Edge phi rs ci co s]
      , initial     :: s
      , initialRegs :: RegFile rs
      , isFinal     :: s -> Bool
      }

The forward step `omega`:

    omega :: BoolAlg phi (RegFile rs, ci)
          => SymTransducer phi rs s ci co
          -> s -> RegFile rs -> ci -> Maybe co

`omega` returns `Just co` for the unique edge whose guard is
satisfied and whose `output` is non-ε; `Nothing` otherwise (no edge,
multiple edges, or unique edge is ε).

The state-only step `delta`:

    delta :: BoolAlg phi (RegFile rs, ci)
          => SymTransducer phi rs s ci co
          -> s -> RegFile rs -> ci -> Maybe (s, RegFile rs)

`delta` returns the post-step `(target, regs')` pair for the unique
active edge regardless of whether it emits an event.

The replay helper `applyEvent`:

    applyEvent :: BoolAlg phi (RegFile rs, ci)
               => SymTransducer phi rs s ci co
               -> s -> RegFile rs -> co -> Maybe (s, RegFile rs)

`applyEvent` recovers the input that produced an observed event via
`solveOutput`, verifies the guard, and applies the update.

**The Chassaing Decider shape (target):**

    data Decider c e s = Decider
      { decide       :: c -> s -> [e]
      , evolve       :: s -> e -> s
      , initialState :: s
      , isTerminal   :: s -> Bool
      }

The implementation maps to keiki:

    decide cmd (s, regs)
      = case omega t s regs cmd of
          Just co -> [co]
          Nothing -> []

    evolve (s, regs) ev
      = case applyEvent t s regs ev of
          Just (s', regs') -> (s', regs')
          Nothing          -> (s, regs)   -- defensive; replay of
                                          -- a malformed log

    initialState = (initial t, initialRegs t)
    isTerminal (s, _regs) = isFinal t s

**Key fixture in `src/Keiki/Examples/UserRegistration.hs`:**

The transducer:

    userReg :: SymTransducer (HsPred UserRegRegs UserCmd)
                             UserRegRegs Vertex UserCmd UserEvent

The canonical command sequence (per
`src/Keiki/Examples/UserRegistrationSpec.hs`'s reconstitution test)
is something like:

    [ StartRegistration  (StartRegistrationData "alice@example.com" "abc123" t0)
    , Continue
    , ConfirmAccount     (ConfirmAccountData    "abc123" t1)
    , FulfillGDPRRequest (FulfillGDPRRequestData t2)
    ]

…producing the event sequence:

    [ RegistrationStarted   ...
    , ConfirmationEmailSent ...
    , AccountConfirmed      ...
    , AccountDeleted        ...
    ]

…ending in the `Deleted` vertex with the expected `RegFile`
snapshot. Read the existing spec to confirm the exact fixture before
copying it.

**Two semantic gaps the façade must address:**

1. **ε-edges.** The User Registration aggregate has one — the
   `FulfillGDPRRequest` edge from `RequiresConfirmation` has
   `output = Nothing` (silent deletion before confirmation; no
   `AccountDeleted` event because the user never had a confirmed
   account). The keiki `delta` for that edge transitions the state
   to `Deleted`, but `omega` returns `Nothing`. In the Chassaing
   model, an empty `decide` result means the state does not change.
   So `(toDecider userReg).decide (FulfillGDPRRequest d)
   (RequiresConfirmation, regs) == []`, and a subsequent `evolve`
   on `[]` is a no-op. The state does *not* reach `Deleted`.

   This is a documented limitation of the façade. Users who need
   ε-edges to drive state must use `delta` directly or use
   `(toDecider userReg).decide` paired with their own logic for the
   no-event case. The new module's haddock and this plan's
   Surprises & Discoveries call this out explicitly. The naive
   Decider model has no concept of ε-edges; bridging the gap would
   require either changing the Decider record's shape (no longer
   "Chassaing canonical") or synthesizing internal events (which
   defeats the point of the façade — keiki's edges are events on
   the wire, ε-edges are intentionally silent).

2. **`Maybe co` vs. `[e]`.** The keiki `omega` returns `Maybe co`
   (zero-or-one event); the Chassaing `decide` returns `[e]` (zero,
   one, or many events). The façade lifts `Maybe co` to a list:
   `Just co → [co]`, `Nothing → []`. A future EP that introduces
   multi-event commands (synthesis §5's *MultiDecider*; out of
   scope here) would relax this.


## Plan of Work

The work is six small milestones, each independently verifiable.
Total effort estimate: ~2 hours per `keiki-generics-design.md` item
E entry. Allow for an extra hour to write good haddock for the two
semantic gaps.

**Milestone 0 — Baseline.** Run `cabal build all && cabal test all`.
Record the test count for delta-checking after M3 and M4. Confirm
the canonical-log fixture in
`src/Keiki/Examples/UserRegistration.hs` is the one this plan will
reuse (spot-check the names of the four commands and the four
events).

**Milestone 1 — Design milestone.** In a single design pass, decide:

- *Record shape.* The four-field Chassaing canonical
  (`decide`/`evolve`/`initialState`/`isTerminal`). Rejected:
  alternative shapes that fold register file separately (defeats the
  "drop-in adapter" point) or carry a richer `decide` signature
  (departs from Chassaing).
- *State carrier.* `(s, RegFile rs)` — the same pair `delta` and
  `applyEvent` operate on. Alternative ("just `s`" with the
  registers carried implicitly) rejected because keiki's `omega`
  needs the registers to evaluate edge guards.
- *Polymorphism.* `toDecider` is polymorphic over `phi`, `rs`, `s`,
  `ci`, `co` and constrains `BoolAlg phi (RegFile rs, ci)` so it
  works equally well over the v1 `HsPred` instance and the v2
  `SymPred` instance.
- *ε-edge handling.* Document the limitation in haddock. Do not
  attempt to encode ε-edges as synthetic events.
- *`Maybe co` vs. `[e]`.* `Just → [co]`, `Nothing → []`.

Write a paragraph appending to `docs/research/keiki-generics-design.md`'s
"### E. Generic-derived Decider façade" entry that records the
chosen shape and the two limitations with their rationale. This
paragraph becomes the design note for EP-10.

Acceptance: the design paragraph is in the design note. No code yet.

**Milestone 2 — Module skeleton.** Create
`src/Keiki/Decider.hs`. Module shape:

    {-# LANGUAGE GADTs #-}

    module Keiki.Decider
      ( Decider (..)
      , toDecider
      ) where

    import Keiki.Core

    -- | Chassaing-shape Decider record. The keiki SymTransducer
    -- can be projected to this shape via 'toDecider' as a
    -- migration aid for users coming from the naive-decider world.
    --
    -- Two semantic gaps are documented at 'toDecider'.
    data Decider c e s = Decider
      { decide       :: c -> s -> [e]
      , evolve       :: s -> e -> s
      , initialState :: s
      , isTerminal   :: s -> Bool
      }

    -- | Project a 'SymTransducer' to a Chassaing-shape 'Decider'.
    -- ... (extensive haddock; see Concrete Steps for full text)
    toDecider
      :: BoolAlg phi (RegFile rs, ci)
      => SymTransducer phi rs s ci co
      -> Decider ci co (s, RegFile rs)
    toDecider t = Decider
      { decide = \cmd (s, regs) -> case omega t s regs cmd of
          Just co -> [co]
          Nothing -> []
      , evolve = \(s, regs) ev -> case applyEvent t s regs ev of
          Just (s', regs') -> (s', regs')
          Nothing          -> (s, regs)
      , initialState = (initial t, initialRegs t)
      , isTerminal   = \(s, _regs) -> isFinal t s
      }

Wire it into `keiki.cabal`:

    library
        ...
        exposed-modules:    Keiki.Core
                            Keiki.Decider     -- new
                            Keiki.Generics
                            Keiki.Symbolic
                            Keiki.Examples.UserRegistration
                            Keiki.Examples.UserRegistrationV0

`cabal build` succeeds.

Acceptance: `cabal repl keiki` loads the new module; `:t toDecider`
shows the expected signature.

**Milestone 3 — Round-trip test.** Create
`test/Keiki/DeciderSpec.hs`:

    {-# LANGUAGE OverloadedStrings #-}

    module Keiki.DeciderSpec (spec) where

    import Test.Hspec
    import Data.Time (UTCTime, secondsToNominalDiffTime)
    import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
    import Keiki.Core
    import Keiki.Decider
    import Keiki.Examples.UserRegistration

    spec :: Spec
    spec = describe "toDecider userReg" $ do
      it "round-trips the canonical command sequence" $ do
        let d        = toDecider userReg
            cmds     = canonicalCmds  -- copy from UserRegistrationSpec
            (s, _)   = foldl step (initialState d) cmds
            step (st, regs) cmd =
              let evs       = decide d cmd (st, regs)
                  (st', r') = foldl (evolve d) (st, regs) evs
              in (st', r')
        s `shouldBe` Deleted

      it "decide returns [] for an ε-edge command" $ do
        let d = toDecider userReg
            -- Drive userReg into RequiresConfirmation first
            ...
            -- Then GDPR from RequiresConfirmation is the ε-edge
            evs = decide d (FulfillGDPRRequest (FulfillGDPRRequestData t)) preGdpr
        evs `shouldBe` []

Wire into `test/Spec.hs`:

    import qualified Keiki.DeciderSpec as DS
    ...
    main = hspec $ do
      ...
      DS.spec

Wire into `keiki.cabal`'s `keiki-test:other-modules`:

    other-modules:      Keiki.CoreSpec
                        Keiki.DeciderSpec   -- new
                        Keiki.SymbolicSpec
                        Keiki.Examples.UserRegistrationSpec
                        ...

`cabal test all` reports the M0 baseline count plus the new tests, 0
failures.

Acceptance: round-trip lands `(Deleted, expectedRegs)`; ε-edge case
returns `[]` from `decide`.

**Milestone 4 — ε-edge limitation in haddock.** In the new module,
expand `toDecider`'s haddock with a `## Semantic gaps` section that
spells out:

- The Chassaing model assumes events drive state; the keiki model
  also has ε-edges (state changes without events). When `decide`
  returns `[]`, callers should not assume "no state change" — they
  may need `delta` directly for ε-driven workflows.
- `Maybe co` vs. `[e]`: keiki emits at most one event per command;
  the lifted list is always `[]` or singleton.

Both points are illustrated by short Haskell snippets in the
haddock so a reader doesn't have to consult this plan.

Acceptance: `cabal haddock all` builds the module's haddock with
the new sections rendered.

**Milestone 5 — Retire item E in the design note + commit.** Edit
`docs/research/keiki-generics-design.md` "### E. Generic-derived
Decider façade" entry. Append a paragraph beginning with
"**Implemented (see EP-10).**" linking to
`src/Keiki/Decider.hs` and summarizing the two semantic gaps. Stage
the changes:

- `src/Keiki/Decider.hs` (new)
- `test/Keiki/DeciderSpec.hs` (new)
- `test/Spec.hs` (one-line addition)
- `keiki.cabal` (two additions: `exposed-modules`, `other-modules`)
- `docs/research/keiki-generics-design.md` (item E retirement)

Single commit:

    feat(decider): Keiki.Decider façade for naive-decider migration

    New module Keiki.Decider exporting a Chassaing-shape Decider record
    and toDecider :: SymTransducer ... -> Decider ci co (s, RegFile rs).
    Round-trip test on userReg's canonical log lands (Deleted, ...);
    haddock documents the two semantic gaps (ε-edges and Maybe co
    vs. [e]).

    Retires item E from docs/research/keiki-generics-design.md's
    Future Improvements list.

    MasterPlan: docs/masterplans/3-keiki-generics-dx-follow-ups.md
    ExecPlan: docs/plans/10-keiki-decider-facade-for-naive-decider-migration.md
    Intention: intention_01knjzws4qezz9w8b0743zfqv8

Acceptance: `git log -1 --format=%B HEAD` shows all three trailers.


## Concrete Steps

All commands run from `/Users/shinzui/Keikaku/bokuno/keiki/`.

**M0 baseline:**

    cabal build all
    cabal test all 2>&1 | grep -E '^[0-9]+ examples'
    grep -E "^canonicalLog|^canonicalCmds" -r test/Keiki/Examples/

**M1 design pass — see Plan of Work.** Edit
`docs/research/keiki-generics-design.md` to amend item E.

**M2 module skeleton.**

Create `src/Keiki/Decider.hs` with the content sketched in Plan of
Work M2.

Edit `keiki.cabal`. Add `Keiki.Decider` between `Keiki.Core` and
`Keiki.Generics` in `library:exposed-modules`:

    exposed-modules:    Keiki.Core
                        Keiki.Decider
                        Keiki.Generics
                        Keiki.Symbolic
                        ...

Run:

    cabal build all
    cabal repl keiki
    -- inside repl:
    :t toDecider
    :q

**M3 round-trip test.**

First, identify the canonical-log fixture in
`src/Keiki/Examples/UserRegistrationSpec.hs` (or wherever it
lives). Copy the fixture verbatim into `Keiki.DeciderSpec` to keep
the spec self-contained.

Create `test/Keiki/DeciderSpec.hs` per the Plan of Work M3 sketch.
Wire into `test/Spec.hs`:

    import qualified Keiki.DeciderSpec as DS
    ...
    main = hspec $ do
      ...
      describe "Keiki.Decider" DS.spec

Wire into `keiki.cabal`:

    test-suite keiki-test
        ...
        other-modules:      Keiki.CoreSpec
                            Keiki.DeciderSpec
                            ...

Run:

    cabal test all 2>&1 | grep -E '^[0-9]+ examples'

Expected count: M0 baseline + 2 (round-trip + ε-edge).

**M4 haddock.**

Edit `src/Keiki/Decider.hs` to add the `## Semantic gaps` haddock
section to `toDecider`. Run:

    cabal haddock all

Expected: builds without warnings; the rendered HTML includes the
new section.

**M5 design note + commit.**

Edit `docs/research/keiki-generics-design.md`. In the "### E.
Generic-derived Decider façade" section, append:

    **Implemented (see EP-10).** `Keiki.Decider` ships the Chassaing-
    shape `Decider c e s` record and `toDecider :: SymTransducer ...
    -> Decider ci co (s, RegFile rs)`. Two semantic gaps are
    documented in the module haddock: ε-edges (where `decide` returns
    `[]` because no event is emitted, but the keiki transducer would
    transition state via `delta`) and the `Maybe co → [e]` lift
    (keiki emits at most one event per command). See
    `docs/plans/10-keiki-decider-facade-for-naive-decider-migration.md`.

Stage and commit:

    git add src/Keiki/Decider.hs \
            test/Keiki/DeciderSpec.hs \
            test/Spec.hs \
            keiki.cabal \
            docs/research/keiki-generics-design.md

    git commit -m "$(cat <<'EOF'
    feat(decider): Keiki.Decider façade for naive-decider migration

    New module Keiki.Decider exporting a Chassaing-shape Decider record
    and toDecider :: SymTransducer ... -> Decider ci co (s, RegFile rs).
    Round-trip test on userReg's canonical log lands (Deleted, ...);
    haddock documents the two semantic gaps (ε-edges and Maybe co
    vs. [e]).

    Retires item E from docs/research/keiki-generics-design.md's
    Future Improvements list.

    MasterPlan: docs/masterplans/3-keiki-generics-dx-follow-ups.md
    ExecPlan: docs/plans/10-keiki-decider-facade-for-naive-decider-migration.md
    Intention: intention_01knjzws4qezz9w8b0743zfqv8
    EOF
    )"


## Validation and Acceptance

After all five milestones:

- `cabal build all` succeeds with no warnings.
- `cabal test all` reports M0 baseline + 2 examples, 0 failures.
- `cabal haddock all` builds clean for the new module.
- `git log -1 --format=%B HEAD` shows the three trailers.

Behavioral acceptance:

1. **Round-trip on the canonical command sequence.** Driving
   `(toDecider userReg)` through `cmds` via the `decide`/`evolve`
   loop reaches the `(Deleted, expectedRegs)` snapshot — the same
   snapshot `omega` + `applyEvent` produce.
2. **ε-edge case.** From `(RequiresConfirmation, regsAtRC)`, calling
   `decide d (FulfillGDPRRequest (FulfillGDPRRequestData t))` returns
   `[]`. State remains at `RequiresConfirmation` after a
   `decide`/`evolve` round-trip on `[]` (because `evolve` is not
   called). The haddock makes this explicit and points to `delta`
   for callers who need ε-driven transitions.

Both assertions are in `test/Keiki/DeciderSpec.hs`.


## Idempotence and Recovery

The plan is additive. Each milestone's edits can be re-applied
without harm:

- M2's new module is self-contained; deleting and recreating it has
  no side effects elsewhere.
- M3's spec module imports from existing `Keiki.Examples.UserRegistration`
  exports — no source changes are needed there.
- M5's design note edit targets a specific subsection that is not
  edited by other in-flight EPs (per MP-3's IP-3 coordination rule:
  EP-8 amends item A + B; EP-9 amends item D; EP-10 amends item E).

Recovery — if a milestone fails:

- M2 build failure: revert `src/Keiki/Decider.hs` and the
  `keiki.cabal` `exposed-modules` line. `cabal build` returns to
  baseline.
- M3 test failure: revert `test/Keiki/DeciderSpec.hs`, `test/Spec.hs`,
  and the `keiki.cabal` `other-modules` line. Investigate the
  failing assertion before re-attempting; the most likely cause is
  a fixture mismatch (canonical-log copy diverged from
  `UserRegistrationSpec`'s).
- M5 commit can be undone with `git reset --soft HEAD^` if the
  trailers are wrong; recommit with the corrected message.

No source files outside `src/Keiki/Decider.hs`, `test/Keiki/DeciderSpec.hs`,
`test/Spec.hs`, `keiki.cabal`, and the design note should be
modified by this plan.


## Interfaces and Dependencies

New types and functions:

    -- src/Keiki/Decider.hs
    data Decider c e s = Decider
      { decide       :: c -> s -> [e]
      , evolve       :: s -> e -> s
      , initialState :: s
      , isTerminal   :: s -> Bool
      }

    toDecider
      :: BoolAlg phi (RegFile rs, ci)
      => SymTransducer phi rs s ci co
      -> Decider ci co (s, RegFile rs)

Existing functions consumed:

- `Keiki.Core.omega` — forward step, returns `Maybe co`.
- `Keiki.Core.applyEvent` — replay step, returns `Maybe (s, RegFile rs)`.
- `Keiki.Core.initial`, `Keiki.Core.initialRegs`, `Keiki.Core.isFinal` —
  transducer accessors.

No new external libraries. No changes to `keiki.cabal`'s
`build-depends`.

The plan does not modify any existing module. It adds one new
library module (`Keiki.Decider`) and one new test module
(`Keiki.DeciderSpec`).
