---
id: 12
slug: acceptor-projections-input-output-for-symtransducer
title: "Acceptor projections (input/output) for SymTransducer"
kind: exec-plan
created_at: 2026-05-02T12:33:51Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
master_plan: "docs/masterplans/5-acceptor-projections-and-genview-th-splice-for-b-presentation.md"
---

# Acceptor projections (input/output) for SymTransducer

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

The keiki library models an aggregate as a *symbolic-register
transducer* (`SymTransducer phi rs s ci co`) whose forward step
(`delta`/`omega`/`step`) consumes commands and produces events,
and whose inverse step (`applyEvent`) reconstructs the next
state from an observed event. The foundations chapter
`docs/foundations/04-projections-and-deriving-event-sourcing.md`
spends most of its prose on the central insight that an FST has
two acceptor projections:

- The **input projection** π₁: drop the events. The remaining
  transition function is an acceptor over commands. Its language
  is the set of command sequences the aggregate accepts.
- The **output projection** π₂: drop the commands by inverting
  ω. The remaining transition function is `evolve` (a.k.a. the
  event-language acceptor). Its language is the set of event
  sequences the aggregate could have produced — the set of
  replayable logs.

In the current code (`src/Keiki/`) these projections are
*implicit*. π₁ is reachable by calling `delta` directly. π₂ is
reachable by calling `applyEvent` directly. But there is no
`Acceptor` data type, no `inputAcceptor` / `outputAcceptor`
functions are exported, and the relationship the foundations
chapter spells out is not visible in the API surface.

This ExecPlan adds the missing surface. After completion the
repository contains:

- A new module `src/Keiki/Acceptor.hs` exporting:

      data Acceptor a s = Acceptor
        { aStep    :: s -> a -> Maybe s
        , aInitial :: s
        , aIsFinal :: s -> Bool
        }

      inputAcceptor
        :: BoolAlg phi (RegFile rs, ci)
        => SymTransducer phi rs s ci co
        -> Acceptor ci (s, RegFile rs)

      outputAcceptor
        :: BoolAlg phi (RegFile rs, ci)
        => SymTransducer phi rs s ci co
        -> Acceptor co (s, RegFile rs)

      runAcceptor :: Acceptor a s -> [a] -> Maybe s
      accepts     :: Acceptor a s -> [a] -> Bool

- A new design note
  `docs/research/acceptor-projections-design.md` capturing the
  formal semantics, the deliberate scope cap (no composition, no
  language equivalence), and the relationship to the foundations
  chapter.

- A new test module `test/Keiki/AcceptorSpec.hs`. Tests:

  1. *Input acceptor accepts the canonical command sequence on
     `userReg`.* The four-step sequence `[StartRegistration …,
     Continue, ConfirmAccount …, FulfillGDPRRequest …]` reaches
     `Deleted`. `accepts (inputAcceptor userReg) cmds == True`.
  2. *Input acceptor rejects an out-of-place command on
     `userReg`.* `[ConfirmAccount …]` from the initial state
     fails because the only edge out of `PotentialCustomer` is
     `StartRegistration`. `accepts (inputAcceptor userReg) cmds
     == False`.
  3. *Output acceptor accepts the canonical event log on
     `emailDelivery`.* `[EmailSent …]` reaches the terminal
     vertex. `accepts (outputAcceptor emailDelivery) events ==
     True`. (We use `emailDelivery` here because every transition
     produces a wire event; `userReg`'s ε-edge from
     `RequiresConfirmation` to `Deleted` would block `applyEvent`
     replay through that edge per the MP-4 retrospective.)
  4. *Output acceptor rejects a malformed event log.* An event
     with a constructor that doesn't match any outgoing edge from
     the current vertex yields `Nothing`.
  5. *Round-trip: `outputAcceptor` agrees with `reconstitute`.*
     For any log `[co]`, `runAcceptor (outputAcceptor t) log ==
     reconstitute t log`. Asserted on the canonical
     `emailDelivery` log.
  6. *Final-state predicate.* `aIsFinal` returns the same
     answers as `isFinal` composed with `fst`.

- An updated `docs/foundations/04-projections-and-deriving-event-sourcing.md`
  with a brief "How this looks in code" section at the bottom,
  pointing at `Keiki.Acceptor`.

How a future contributor sees this work:

    nix-shell -p z3 --run "cabal test all"
    # 95 → ~101 examples (89 baseline + 6 from MP-4 + ~6 new),
    # 0 failures.
    # Includes "input acceptor accepts canonical commands" and
    # "output acceptor matches reconstitute" tests.

The user-visible win: keiki users who want the named "command
acceptor" or "event acceptor" of an aggregate can call
`inputAcceptor t` / `outputAcceptor t` directly, and downstream
code (UI, validation, generated docs) can pattern-match on a
known data type instead of plumbing `delta` and `applyEvent` by
hand.


## Progress

Use a checklist to summarize granular steps. Every stopping point
must be documented here, even if it requires splitting a
partially completed task into two ("done" vs. "remaining"). This
section must always reflect the actual current state of the work.

- [x] **Milestone 0 — Verify prerequisites** (2026-05-02). `cabal
      build all` reports "Up to date"; `nix-shell -p z3 --run
      "cabal test all"` reports 95 examples, 0 failures. GHC
      9.12.3, cabal-install 3.16.1.0. `Keiki.Core` signatures for
      `delta`, `applyEvent`, `reconstitute` confirmed below.
- [x] **Milestone 1 — Design note** (2026-05-02).
      `docs/research/acceptor-projections-design.md` written
      (~210 lines): problem statement, shape, state-carrier
      rationale, projection bodies, folding helpers, language
      preservation, deferred scope (composition/equivalence/
      profunctor), worked examples, module-placement rationale,
      relationship to `Keiki.Decider`.
- [x] **Milestone 2 — `Keiki.Acceptor` module** (2026-05-02).
      `src/Keiki/Acceptor.hs` exports `Acceptor`, `inputAcceptor`,
      `outputAcceptor`, `runAcceptor`, `accepts` per the
      signatures in Purpose / Big Picture. Added to
      `keiki.cabal:library.exposed-modules`. `cabal build all`
      reports "Up to date" with no warnings.
- [x] **Milestone 3 — Test module** (2026-05-02).
      `test/Keiki/AcceptorSpec.hs` written: 6 tests across three
      describe blocks (`inputAcceptor userReg`,
      `outputAcceptor emailDelivery`, `aIsFinal`). Wired into
      `test/Spec.hs` and `keiki.cabal:keiki-test.other-modules`.
      `nix-shell -p z3 --run "cabal test all"` reports 101
      examples (95 baseline + 6 new), 0 failures.
- [x] **Milestone 4 — Foundations doc pointer** (2026-05-02).
      Added "In code: `Keiki.Acceptor`" section to
      `docs/foundations/04-projections-and-deriving-event-sourcing.md`
      immediately before "Vocabulary recap", pointing at
      `inputAcceptor`/`outputAcceptor`/`accepts` and explaining
      that the output acceptor's `aStep` is the chapter's `evolve`.
- [ ] **Milestone 5 — Commit.** A single conventional commit
      `feat(acceptor): EP-12 — Acceptor projections on
      SymTransducer` with the trailers `MasterPlan: ...`,
      `ExecPlan: ...`, `Intention: ...`. (Or one commit per
      milestone if logical splits emerge.)


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights
discovered during implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: `Acceptor a s` is parameterised in the order
  *alphabet first, state second* (`Acceptor ci (s, RegFile rs)`),
  not state-first. Rationale: matches the partial-application
  intuition "an acceptor over commands" — the alphabet is the
  primary visible parameter; the state carrier is implementation
  detail. Date: 2026-05-02.

- Decision: `aStep` returns `Maybe s` (not `Maybe (s, [event])`
  or `Either Reject s`). Rationale: an acceptor's job is to
  decide membership; rejection is the absence of a transition.
  The richer return type belongs in `delta` / `applyEvent`, not
  in the projection. Date: 2026-05-02.

- Decision: no `Show` / `Eq` instance on `Acceptor`. Rationale:
  the data type carries closures (`aStep`, `aIsFinal`); it's
  inherently not showable or comparable. Tests assert on
  `runAcceptor` outputs instead. Date: 2026-05-02.


## Outcomes & Retrospective

**Outcome (2026-05-02).** EP-12 lands as five additive milestones
matching the plan exactly. The `Keiki.Acceptor` module exposes the
four-symbol surface (`Acceptor`, `inputAcceptor`, `outputAcceptor`,
`runAcceptor`, `accepts`) the foundations chapter motivated, with
no changes to existing modules. Test count moves from 95 to 101.

**Against the original purpose.** A keiki user who wants the
"command acceptor" or "event acceptor" of an aggregate can now ask
for it by name:

    accepts (inputAcceptor userReg) cmds        :: Bool
    accepts (outputAcceptor emailDelivery) log  :: Bool

`runAcceptor (outputAcceptor t) log` agrees with `reconstitute t
log` modulo the snd projection, exactly the equivalence the
foundations chapter promises. The acceptor's state carrier is
`(s, RegFile rs)` (necessary for evaluating register-dependent
guards), matching the choice `toDecider` already made.

**Gaps / future work.** Three intentional non-goals from the design
note remain open and were not in scope here:

- Composition over Acceptors (intersection of accepted languages,
  language-equivalence checks).
- Profunctor structure on `Acceptor`.
- A symbolic acceptor — one whose `aStep` returns SBV-encoded
  conditions — for static analysis. None of these are blocked by
  this EP; each warrants its own EP if a real workflow demands it.

**Lessons.** The "name what's already implicit" framing kept the
module small (one data type, four functions, ~70 SLoC including
haddock). A larger surface (e.g. introducing `Profunctor` instances
or a typeclass that abstracts both `delta` and `applyEvent` into
`accept`) would have lengthened the EP without delivering anything
the foundations chapter doesn't already say. Resisting that pressure
is the design contribution.


## Context and Orientation

Describe the current state relevant to this task as if the reader
knows nothing.

The keiki library lives at `/Users/shinzui/Keikaku/bokuno/keiki/`.
Its layout:

    src/
      Keiki/
        Core.hs            -- the SymTransducer formalism (797 lines)
        Composition.hs     -- compose combinator (MP-4 / EP-11)
        Decider.hs         -- Chassaing-shape Decider façade (MP-3 / EP-10)
        Generics.hs        -- Generic-derived InCtor/WireCtor helpers
        Generics/TH.hs     -- TH splices: deriveAggregateCtors, deriveWireCtors
        Symbolic.hs        -- SBV-backed BoolAlg, isSingleValuedSym
        Examples/
          UserRegistration.hs       -- canonical worked example
          UserRegistrationV0.hs     -- "unfixed schema" demo for hidden-input check
          EmailDelivery.hs          -- 2-vertex aggregate (used in MP-4)
    test/
      Spec.hs                       -- main entry, registers all spec modules
      Keiki/
        CompositionSpec.hs
        CoreSpec.hs
        DeciderSpec.hs
        Generics/THSpec.hs
        SymbolicSpec.hs
        Examples/
          UserRegistrationSpec.hs
          UserRegistrationSymbolicSpec.hs
          UserRegistrationV0Spec.hs
    docs/
      foundations/
        04-projections-and-deriving-event-sourcing.md  -- the chapter this EP names in code
      research/
        synthesis-c-foundation-b-presentation-with-worked-examples.md  -- working baseline
        core-design-transducer-as-source-of-truth.md
    docs/masterplans/
      5-acceptor-projections-and-genview-th-splice-for-b-presentation.md  -- this plan's parent

**Key shape from `src/Keiki/Core.hs:405-410`:**

    data SymTransducer phi rs s ci co = SymTransducer
      { edgesOut    :: s -> [Edge phi rs ci co s]
      , initial     :: s
      , initialRegs :: RegFile rs
      , isFinal     :: s -> Bool
      }

**The two projection functions this EP wraps**, both from
`src/Keiki/Core.hs`:

    delta :: BoolAlg phi (RegFile rs, ci)
          => SymTransducer phi rs s ci co
          -> s -> RegFile rs -> ci -> Maybe (s, RegFile rs)
    -- (lines 533-543) returns Just (s', regs') iff exactly one
    -- outgoing edge has a satisfied guard; Nothing otherwise.

    applyEvent :: BoolAlg phi (RegFile rs, ci)
               => SymTransducer phi rs s ci co
               -> s -> RegFile rs -> co -> Maybe (s, RegFile rs)
    -- (lines 585-597) walks outgoing edges, inverts each edge's
    -- output via solveOutput, verifies the guard on the recovered
    -- input, applies the update; returns the unique successful
    -- next state.

The `BoolAlg phi (RegFile rs, ci)` constraint comes from the
`models` method on the `BoolAlg` typeclass
(`src/Keiki/Core.hs:368-378`); both `delta` and `applyEvent`
need it because edge guards are evaluated against `(regs, ci)`
witnesses.

**Two existing reference points the tests will use:**

- `Keiki.Examples.UserRegistration.userReg` — a five-vertex
  aggregate (`PotentialCustomer → Registering → RequiresConfirmation
  → Confirmed → Deleted`) with one ε-edge (`RequiresConfirmation
  → Deleted` on `FulfillGDPRRequest`). Module:
  `src/Keiki/Examples/UserRegistration.hs:245-355`.

- `Keiki.Examples.EmailDelivery.emailDelivery` — a two-vertex
  aggregate (`EmailPending → EmailSentVertex`) with one
  command (`SendEmail`), one event (`EmailSent`). Every
  transition produces a wire event, which makes the output
  acceptor's behaviour easy to test without tripping over
  ε-edges. Module: `src/Keiki/Examples/EmailDelivery.hs`.

**Why the state carrier is `(s, RegFile rs)`.** Every edge
guard depends on both the control vertex and the register file
(see `evalPred` at `src/Keiki/Core.hs:502-512` — `PEq` reads
registers via `TReg`). The acceptor must thread the register
file through each step or it can't evaluate guards on subsequent
inputs. The state carrier therefore is the same pair `(s,
RegFile rs)` that `delta` and `applyEvent` already use as their
input/output type. This matches the choice `toDecider` makes in
`src/Keiki/Decider.hs:109-122`.

**Test runner setup.** `test/Spec.hs` is a hand-written entry
point that imports each spec module qualified and registers it
under `hspec`'s `describe`. The cabal `keiki-test:other-modules`
block (currently 8 entries; see `keiki.cabal` lines 53-60) lists
each spec module so cabal compiles them. The test suite needs
`z3` in PATH because some specs (`SymbolicSpec`,
`UserRegistrationSymbolicSpec`) call `isSingleValuedSym`. Use
`nix-shell -p z3 --run "cabal test all"` to provide it. EP-12's
new spec does *not* itself need `z3` (only `delta` and
`applyEvent`, which are pure), but the suite still needs `z3`
overall.

**Foundations doc 04 vocabulary.** The chapter calls these
"input projection" (π₁) and "output projection" (π₂), explains
the insight that the output projection's transition function
*is* `evolve`, and motivates everything that comes after with
this property. It defines `reconstitute :: [Event] -> Maybe
State` as `foldlM evolve initialState`. EP-12's `Acceptor` and
`runAcceptor` are the named code-level equivalents.


## Plan of Work

Five milestones. Effort estimate: ~2-4 hours total. The work is
small and additive; no existing code is modified.

**Milestone 0 — Baseline.** Confirm the working tree compiles
and the test suite passes. Record the GHC version and the
baseline test count.

    cabal build all
    nix-shell -p z3 --run "cabal test all" 2>&1 | tail -3

Expected: 95 examples, 0 failures. Record the actual number in
the Progress section.

**Milestone 1 — Design note.** Create
`docs/research/acceptor-projections-design.md`. Sections to
include:

1. *Problem statement.* Foundations doc 04 spells out the
   acceptor projections at length; the code base doesn't
   materialize them. Users have to call `delta`/`applyEvent`
   directly.

2. *The shape.* Define `Acceptor a s` as the minimum viable
   data type. Justify the field set (step, initial, isFinal).
   Justify the state carrier `(s, RegFile rs)`.

3. *The projections.* `inputAcceptor t` wraps `delta t`;
   `outputAcceptor t` wraps `applyEvent t`. Show the bodies.

4. *Helpers.* `runAcceptor` is `foldM aStep aInitial`;
   `accepts` is `maybe False aIsFinal . runAcceptor`. Both
   trivial.

5. *What's preserved.* The acceptor's language is the language
   the foundations chapter describes:
   - `inputAcceptor t` accepts the command sequences
     `userReg` accepts.
   - `outputAcceptor t` accepts the event sequences
     `userReg` could have produced. Equivalent to "the log
     replays cleanly through `reconstitute`."

6. *What's deferred.* Composition over Acceptors (intersection,
   union of accepted languages); language-equivalence checks;
   profunctor structure. None of these are needed for the
   acceptor-as-projection use case the foundations chapter
   motivates; each warrants its own EP if a real workflow asks
   for it.

7. *Worked examples.* Two bullet-point examples on `userReg` and
   `emailDelivery` showing what `accepts` returns for canonical
   sequences.

Acceptance: the file exists and is ~100-150 lines.

**Milestone 2 — `Keiki.Acceptor` module.** Create
`src/Keiki/Acceptor.hs`:

    -- | A first-class projection of a 'SymTransducer' onto one
    -- alphabet. See 'docs/research/acceptor-projections-design.md'
    -- and 'docs/foundations/04-projections-and-deriving-event-sourcing.md'.
    module Keiki.Acceptor
      ( Acceptor (..)
      , inputAcceptor
      , outputAcceptor
      , runAcceptor
      , accepts
      ) where

    import Keiki.Core
      ( BoolAlg
      , RegFile
      , SymTransducer (..)
      , applyEvent
      , delta
      )

    data Acceptor a s = Acceptor
      { aStep    :: s -> a -> Maybe s
      , aInitial :: s
      , aIsFinal :: s -> Bool
      }

    inputAcceptor
      :: BoolAlg phi (RegFile rs, ci)
      => SymTransducer phi rs s ci co
      -> Acceptor ci (s, RegFile rs)
    inputAcceptor t = Acceptor
      { aStep    = \(s, regs) ci -> delta t s regs ci
      , aInitial = (initial t, initialRegs t)
      , aIsFinal = \(s, _regs) -> isFinal t s
      }

    outputAcceptor
      :: BoolAlg phi (RegFile rs, ci)
      => SymTransducer phi rs s ci co
      -> Acceptor co (s, RegFile rs)
    outputAcceptor t = Acceptor
      { aStep    = \(s, regs) co -> applyEvent t s regs co
      , aInitial = (initial t, initialRegs t)
      , aIsFinal = \(s, _regs) -> isFinal t s
      }

    runAcceptor :: Acceptor a s -> [a] -> Maybe s
    runAcceptor a = go (aInitial a)
      where
        go s []       = Just s
        go s (x : xs) = aStep a s x >>= \s' -> go s' xs

    accepts :: Acceptor a s -> [a] -> Bool
    accepts a xs = case runAcceptor a xs of
      Just s  -> aIsFinal a s
      Nothing -> False

The haddock should be substantial (each function paragraphed
with the intuition and the tie-back to foundations doc 04). See
`src/Keiki/Decider.hs` for the haddock style this codebase uses.

Add the module to `keiki.cabal`'s `library:exposed-modules`
block (currently lines 38-46). The exposed-modules list is
alphabetical-ish; insert `Keiki.Acceptor` immediately after
`Keiki.Composition`.

    cabal build all

Acceptance: `cabal build all` succeeds with no warnings.

**Milestone 3 — Test module.** Create
`test/Keiki/AcceptorSpec.hs`:

    module Keiki.AcceptorSpec (spec) where

    import Test.Hspec
    import Data.Time (UTCTime)
    -- (other imports as needed)

    import Keiki.Acceptor
    import Keiki.Core (initial, initialRegs, isFinal, reconstitute)
    import Keiki.Examples.UserRegistration
      ( userReg, UserCmd (..)
      , StartRegistrationData (..), ConfirmAccountData (..)
      , FulfillGDPRRequestData (..)
      , …
      )
    import Keiki.Examples.EmailDelivery
      ( emailDelivery, EmailEvent (..), EmailSentData (..) )

    spec :: Spec
    spec = do
      describe "inputAcceptor userReg" $ do
        it "accepts the canonical command sequence" $ do
          accepts (inputAcceptor userReg) canonicalUserCmds
            `shouldBe` True

        it "rejects ConfirmAccount from PotentialCustomer" $ do
          accepts (inputAcceptor userReg)
                  [ConfirmAccount (ConfirmAccountData "code" t0)]
            `shouldBe` False

      describe "outputAcceptor emailDelivery" $ do
        it "accepts the canonical event log" $ do
          accepts (outputAcceptor emailDelivery)
                  [EmailSent (EmailSentData "alice@x.io" t0)]
            `shouldBe` True

        it "rejects an event with no matching outgoing edge" $ do
          -- An event that doesn't correspond to any edge from the
          -- initial vertex. Construct one inline.
          accepts (outputAcceptor emailDelivery)
                  [malformedEvent]
            `shouldBe` False

        it "agrees with reconstitute on the canonical log" $ do
          let log = [EmailSent (EmailSentData "alice@x.io" t0)]
          fmap fst (runAcceptor (outputAcceptor emailDelivery) log)
            `shouldBe`
              fmap fst (reconstitute emailDelivery log)

      describe "aIsFinal" $ do
        it "matches isFinal under fst" $ do
          let a = inputAcceptor userReg
          aIsFinal a (Deleted, initialRegs userReg)  `shouldBe` True
          aIsFinal a (Confirmed, initialRegs userReg) `shouldBe` False

The test fixtures (`canonicalUserCmds`, `t0`, `malformedEvent`)
are defined as local bindings in the spec module. `t0` can be
`read "2026-05-02 00:00:00 UTC"` or similar.

Wire the module into `test/Spec.hs`:

    import qualified Keiki.AcceptorSpec
    -- in main:
    describe "Keiki.Acceptor" Keiki.AcceptorSpec.spec

Add `Keiki.AcceptorSpec` to `keiki.cabal`'s
`keiki-test:other-modules` block (currently lines 53-60).

    nix-shell -p z3 --run "cabal test all" 2>&1 | tail -3

Acceptance: 95 baseline + 6 new (or however many tests land), 0
failures. Hspec reports a `Keiki.Acceptor` describe block.

**Milestone 4 — Foundations doc pointer.** Edit
`docs/foundations/04-projections-and-deriving-event-sourcing.md`.
Append a short section (3-5 sentences) immediately before the
existing "Vocabulary recap" section:

    ## In code: `Keiki.Acceptor`

    The library exports `Keiki.Acceptor.inputAcceptor` and
    `Keiki.Acceptor.outputAcceptor`, each producing an
    `Acceptor a s` from a `SymTransducer`. The state carrier
    is `(s, RegFile rs)` because edge guards depend on the
    register file as well as the control vertex. Use
    `accepts (inputAcceptor t) cmds :: Bool` to ask whether
    a command sequence is in the input language;
    `accepts (outputAcceptor t) events :: Bool` for the event
    language. The output acceptor's `aStep` is exactly the
    `evolve` this chapter derives.

Acceptance: the new section reads cleanly and the
"Vocabulary recap" still flows.

**Milestone 5 — Commit.** Stage and commit the work:

    git add src/Keiki/Acceptor.hs \
            test/Keiki/AcceptorSpec.hs \
            test/Spec.hs \
            keiki.cabal \
            docs/research/acceptor-projections-design.md \
            docs/foundations/04-projections-and-deriving-event-sourcing.md \
            docs/masterplans/5-...md \
            docs/plans/12-...md
    git commit  # uses HEREDOC body — see Concrete Steps for template

Trailers required: `MasterPlan: docs/masterplans/5-...md`,
`ExecPlan: docs/plans/12-...md`,
`Intention: intention_01knjzws4qezz9w8b0743zfqv8`.

Acceptance: `git log -1 --format='%B'` shows all three trailers
and a Conventional Commits header (`feat(acceptor): EP-12 — ...`).


## Concrete Steps

All commands run from `/Users/shinzui/Keikaku/bokuno/keiki/`.

**M0 baseline:**

    cabal build all
    nix-shell -p z3 --run "cabal test all" 2>&1 | tail -3

**M1 design note.** Create the file with the section structure
described in Plan of Work / M1.

**M2 module.** Create `src/Keiki/Acceptor.hs`. Edit
`keiki.cabal` to add `Keiki.Acceptor` to
`library:exposed-modules`.

    cabal build all

**M3 test module.** Create `test/Keiki/AcceptorSpec.hs`. Edit
`test/Spec.hs` to import and register the spec. Edit
`keiki.cabal` to add `Keiki.AcceptorSpec` to
`keiki-test:other-modules`.

    nix-shell -p z3 --run "cabal test all" 2>&1 | tail -3

**M4 foundations doc.** Edit
`docs/foundations/04-projections-and-deriving-event-sourcing.md`.

**M5 commit.**

    git add src/Keiki/Acceptor.hs \
            test/Keiki/AcceptorSpec.hs \
            test/Spec.hs \
            keiki.cabal \
            docs/research/acceptor-projections-design.md \
            docs/foundations/04-projections-and-deriving-event-sourcing.md \
            docs/masterplans/5-acceptor-projections-and-genview-th-splice-for-b-presentation.md \
            docs/plans/12-acceptor-projections-input-output-for-symtransducer.md
    git commit -m "$(cat <<'EOF'
    feat(acceptor): EP-12 — Acceptor projections on SymTransducer

    Add Keiki.Acceptor exporting Acceptor data type plus
    inputAcceptor and outputAcceptor projections from
    SymTransducer. inputAcceptor wraps delta; outputAcceptor
    wraps applyEvent. State carrier is (s, RegFile rs) so guards
    can evaluate. runAcceptor / accepts are convenience folds.

    First materializes the input/output projection vocabulary
    foundations doc 04 has discussed since the start.

    MasterPlan: docs/masterplans/5-acceptor-projections-and-genview-th-splice-for-b-presentation.md
    ExecPlan: docs/plans/12-acceptor-projections-input-output-for-symtransducer.md
    Intention: intention_01knjzws4qezz9w8b0743zfqv8
    EOF
    )"


## Validation and Acceptance

After all five milestones:

- `cabal build all` succeeds with no warnings.
- `nix-shell -p z3 --run "cabal test all"` reports baseline + 6
  examples, 0 failures.
- `docs/research/acceptor-projections-design.md` exists and
  documents the shape, the projection bodies, and the deferred
  scope.
- `src/Keiki/Acceptor.hs` exports `Acceptor`, `inputAcceptor`,
  `outputAcceptor`, `runAcceptor`, `accepts` with the signatures
  in Purpose / Big Picture.
- `docs/foundations/04-...md` has the new "In code" section.

Behavioral acceptance (the load-bearing tests):

1. **Input acceptance.** `accepts (inputAcceptor userReg)
   canonicalUserCmds == True`. The canonical sequence ends at
   `Deleted`, which is final.

2. **Input rejection.** `accepts (inputAcceptor userReg)
   [ConfirmAccount …] == False`. No outgoing edge from
   `PotentialCustomer` matches.

3. **Output acceptance.** `accepts (outputAcceptor
   emailDelivery) [EmailSent …] == True`. The single event lands
   at the terminal vertex.

4. **Output rejection.** `accepts (outputAcceptor
   emailDelivery) [malformedEvent] == False`.

5. **Agreement with `reconstitute`.** For every test log,
   `fmap fst (runAcceptor (outputAcceptor t) log) == fmap fst
   (reconstitute t log)`. This is the mechanical-projection
   property: the acceptor and the round-trip replay agree on
   final state.

6. **Final-state predicate parity.** `aIsFinal (inputAcceptor
   t) (s, regs) == isFinal t s` for every `(s, regs)`.


## Idempotence and Recovery

The plan's milestones are entirely additive. Each milestone's
edits can be re-applied without harm:

- M1's design note is a new file.
- M2's new module is self-contained; no existing module is
  edited.
- M3's test module is a new file; the edits to `test/Spec.hs`
  and `keiki.cabal` are one-line additions.
- M4's foundations doc edit appends a section.
- M5's commit can be re-staged if pre-commit hooks fail.

Recovery from a failing test:

- *`shouldBe True` fires `False` for the canonical command
  sequence.* Most likely cause: the test fixture `t0` doesn't
  satisfy a guard. Print the intermediate state by replacing
  `accepts ...` with `runAcceptor ...` in a REPL and inspect.
- *Round-trip property fails.* Most likely cause: `applyEvent`
  short-circuits on a guard that depends on a register the
  fixture did not initialize. Inspect with `applyEvent t s
  initialRegs co` and read the registers.
- *Cabal can't find the new module.* Confirm the
  `library:exposed-modules` and `keiki-test:other-modules`
  entries are spelled identically to the module name.


## Interfaces and Dependencies

New types and functions:

    -- src/Keiki/Acceptor.hs
    data Acceptor a s = Acceptor
      { aStep    :: s -> a -> Maybe s
      , aInitial :: s
      , aIsFinal :: s -> Bool
      }

    inputAcceptor
      :: BoolAlg phi (RegFile rs, ci)
      => SymTransducer phi rs s ci co
      -> Acceptor ci (s, RegFile rs)

    outputAcceptor
      :: BoolAlg phi (RegFile rs, ci)
      => SymTransducer phi rs s ci co
      -> Acceptor co (s, RegFile rs)

    runAcceptor :: Acceptor a s -> [a] -> Maybe s
    accepts     :: Acceptor a s -> [a] -> Bool

New modules:

- `Keiki.Acceptor` — exports the four functions and the data
  type above.
- `Keiki.AcceptorSpec` (test) — six tests against `userReg` and
  `emailDelivery`.

Existing functions consumed:

- `Keiki.Core.SymTransducer`, `BoolAlg`, `RegFile`, `delta`,
  `applyEvent`, `initial`, `initialRegs`, `isFinal`,
  `reconstitute`.
- `Keiki.Examples.UserRegistration.userReg` and the command
  payload constructors.
- `Keiki.Examples.EmailDelivery.emailDelivery` and the event
  payload constructors.

No new external dependencies.

The MasterPlan parent
(`docs/masterplans/5-acceptor-projections-and-genview-th-splice-for-b-presentation.md`)
governs coordination with EP-13 (the genView TH splice). EP-12
and EP-13 are independent — they can run in either order.
