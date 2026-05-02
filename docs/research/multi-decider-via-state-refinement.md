# Multi-event commands via state-refinement ergonomics

This note records the design that EP-20 ships in the keiki library to
make multi-event commands ergonomic without changing the AST. It is
the canonical decision under MasterPlan 7
(`docs/masterplans/7-multi-event-command-support-gsm-widening-vs-state-refinement-ergonomics.md`),
which selected Path B (state-refinement ergonomics) over Path A (GSM
widening of `Edge.output`).

The plan ships three pieces of ergonomic support layered above the
existing letter-FST AST: a chunk-replay primitive in `Keiki.Core`,
a multi-decider façade in `Keiki.Decider`, and a builder-DSL verb in
`Keiki.Builder`. The AST and every existing analysis remain
unchanged.


## 1. Problem statement

The keiki pure core models its transducer as a *letter Finite State
Transducer* (letter FST). Every edge of `SymTransducer` has an
output of type `Maybe (OutTerm rs ci co)` — `Nothing` for an ε-edge
and `Just o` for a single-event edge:

    -- src/Keiki/Core.hs
    data Edge phi rs ci co s = Edge
      { guard  :: phi
      , update :: Update rs ci
      , output :: Maybe (OutTerm rs ci co)
      , target :: s
      }

Real aggregates routinely emit *multiple* events for a single
command. The canonical example is `StartRegistration` in
`src/Keiki/Examples/UserRegistration.hs`, which logically produces
both `RegistrationStarted` and `ConfirmationEmailSent`.

Today this is modelled by *state refinement*: the user adds an
intermediate vertex (`Registering`) and a synthetic internal command
(`Continue`); the multi-event behaviour decomposes into two letter
edges through that intermediate. State refinement is mathematically
clean (each transition stays a letter edge, `apply` remains
mechanically derivable, every analysis stays decidable per-edge),
but ergonomically it leaves three rough edges:

1. The user must declare the intermediate vertex in their `Vertex`
   enum and the internal command in their `ci` enum. This is the
   standing cost of the model and it is the right cost — the
   intermediate state is a first-class part of the user's state
   space and shows up in diagrams, projections, and views.

2. Authoring the chain in the AST or the builder requires two `from
   … onCmd …` blocks with `goto` between. Three or more events per
   command compound this.

3. Calling code that wants the chain to look like a single logical
   step has to drive it explicitly: one `decide` for the public
   command, then one or more `decide` calls for the internal
   advancement command, glueing the event lists together.

This plan addresses (2) with a builder verb and (3) with a façade in
`Keiki.Decider`. (1) is preserved as the load-bearing model: the
intermediate vertex is the user's, declared by them, and never
hidden by the library at the AST level.


## 2. Why state refinement is the canonical path

The synthesis foundation note
(`docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`,
line 974) names state refinement as "the cleanest under the
symbolic-register formalism, as the User Registration example
shows." The multi-event note
(`docs/research/multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md`)
catalogues three approaches in detail: Approach 1 (state
refinement), Approach 2 (GSM with library expansion of `output` to
a list), Approach 3 (direct MultiDecider with hand-written
`apply`).

MasterPlan 7's Vision & Scope spells out the standing reasons to
prefer Approach 1, recapped here for self-containment:

- *Theoretical soundness.* The synthesis note's §1 names mechanical
  `apply` derivation as "the decisive technical win" of the
  symbolic-register formalism. That win — together with the
  build-time hidden-input check
  (`Keiki.Core.checkHiddenInputs`) and the symbolic-emptiness story
  over `Keiki.Symbolic.HsPred` — rests on the letter property: one
  `OutTerm` per edge, decidable per-edge. Widening to GSM moves
  these analyses from per-edge to per-edge-list and weakens the
  hidden-input check from "this `OutTerm` recovers its input" to
  "the *union* of `OutTerm`s on this edge recovers the input,"
  which couples the analysis across the list and is harder to
  discharge cleanly under composition.

- *Future-facing alignment.* Two specific future capabilities prefer
  letter FST: diagram generation, where each edge renders as one
  labeled arrow `c / e` (multi-event edges either render as
  visually noisy multi-line labels or synthesize anonymous
  intermediate nodes that diverge from the AST); and a future move
  toward dependent-typing where edges are indexed by the event
  constructor they emit (`Edge from to cmdCtor (eCtor :: Maybe
  Symbol)`) and list-output edges turn this into `[Symbol]` with
  per-edge analyses becoming quantification over the list.

- *Realistic distribution.* 1–2 events per command is the norm;
  three or more is rare, and even those decompose more cleanly into
  multiple disjoint-guarded edges than into one length-N edge. At
  the realistic distribution, the cost of state refinement is one
  intermediate vertex and one internal command per length-2
  command — manageable, and the `chainTo` builder verb (M5)
  compresses authoring further.

Approach 3 (hand-written `apply`) is rejected as theoretically
incompatible with the foundation: the user writes `apply` by hand,
so the library cannot certify the reconstitution-event-determinism
contract at build time. The MasterPlan's Decision Log records the
exclusion in detail.


## 3. The three-piece ergonomics layer

EP-20 ships three additions, each independently testable and each a
pure layer above the existing core.

### 3.1 `Keiki.Core.applyEvents`

A chunk-replay primitive. It folds the existing
`Keiki.Core.applyEvent` over a list of events and returns the
unwrapped final state:

    applyEvents
      :: BoolAlg phi (RegFile rs, ci)
      => SymTransducer phi rs s ci co
      -> (s, RegFile rs) -> [co]
      -> Maybe (s, RegFile rs)

This is structurally identical to `Keiki.Core.reconstitute`, with
one semantic difference: `reconstitute` always starts from
`(initial t, initialRegs t)`; `applyEvents` starts from a
caller-supplied `(s, RegFile rs)`, letting the runtime adapter
chunk-replay events corresponding to one logical command from any
current state. Useful for runtimes that have command boundaries
(event store with command-id tags, transactional batches,
deterministic test fixtures).

The implementation is a six-line fold; the semantic content is
entirely in the chosen start state.

### 3.2 `Keiki.Decider.DriverConfig` + `toMultiDecider`

A façade that drives multi-event letter chains end-to-end so the
caller never sees the user's intermediate vertices.

`DriverConfig s ci` records which vertices in the user's state space
are *internal* (not surfaced as terminal of one `decide` step) and
which `ci` constructor advances them:

    newtype DriverConfig s ci = DriverConfig
      { isInternal :: s -> Maybe ci }

`isInternal v` returns `Just c` when `v` is internal and `c` is the
command to use to advance it; `Nothing` for public vertices.

`toMultiDecider t cfg` produces a `Decider`-shaped record whose
`decide` function drives the chain:

    toMultiDecider
      :: BoolAlg phi (RegFile rs, ci)
      => SymTransducer phi rs s ci co
      -> DriverConfig s ci
      -> Decider ci co (s, RegFile rs)

The driver loop runs the supplied command from the current public
vertex via `Keiki.Core.step`; if the resulting vertex is internal
(per `cfg`), it auto-advances with the configured command, accumulates
the emitted event, and repeats; the loop terminates on a public
vertex or when `step` returns `Nothing`.

The `evolve` field of the returned `Decider` is a single
`applyEvent` step — identical to `toDecider`'s `evolve`. Mid-replay,
the runtime adapter sees intermediate vertices because they are
real states the user declared. Hiding them via auto-driving
`evolve` would make the value-level state of the system invisible
mid-replay, which is the wrong tradeoff for streaming runtimes.
Chunk replay across a command's events is available via
`Keiki.Core.applyEvents`.

`toDecider` is preserved unchanged; users who do not need the
multi-event façade keep using the single-event lift.

### 3.3 `Keiki.Builder.chainTo`

A new builder verb extending Plan 15's monadic DSL
(`src/Keiki/Builder.hs`). The verb compiles a multi-`emit` block
into a chain of letter edges through user-named intermediates. The
user names the intermediate vertex and the advancement command
explicitly; the DSL synthesizes the ε-step edges between them.

    chainTo
      :: v
      -> InCtor ci '[]
      -> EdgeBuilder rs ci co v w w ()

Compilation: a `chainTo Registering inCtorContinue` between two
`emit` calls produces a first edge from the surrounding `from`
scope's vertex emitting the events accumulated *before* `chainTo`
with `target = Registering`, and a second edge from `Registering`
with guard `matchInCtor inCtorContinue`, `update = UKeep`, output
emitting whatever events accumulate *after* `chainTo`, and `target
= <next chainTo's vertex, or the goto target>`.

A multi-`chainTo` block (length ≥ 3 events) is parsed left-to-right
into a chain of letter edges through the named intermediates.
`chainTo` is purely a syntactic compression: the resulting `Edge`
list is identical to what a hand-written builder block (with `goto`
to the intermediate, then a separate `from intermediate $ onCmd …`
block) would produce.

The cross-form equivalence test
(`test/Keiki/Examples/UserRegistrationBuilderSpec.hs` pattern from
Plan 15) re-greens because both author forms describe the same
letter FST.


## 4. What's preserved

Every existing API and every existing analysis. Specifically:

- The `Keiki.Core.Edge` declaration is unchanged. `output ::
  Maybe (OutTerm rs ci co)` retains its meaning; multi-event
  authoring goes through user-declared intermediates, not list
  outputs.
- `Keiki.Core.omega`, `Keiki.Core.applyEvent`, `Keiki.Core.step`,
  `Keiki.Core.reconstitute`, `Keiki.Core.delta` keep their
  signatures and bodies. `applyEvents` is added beside them as a
  fold of `applyEvent`.
- `Keiki.Core.checkHiddenInputs` is unchanged. The per-edge
  hidden-input check remains decidable per-edge because every edge
  is still a letter edge.
- `Keiki.Composition.compose` and the symbolic-emptiness story over
  `Keiki.Symbolic.HsPred` are unchanged.
- `Keiki.Decider.Decider` and `Keiki.Decider.toDecider` are
  unchanged. The new `DriverConfig` and `toMultiDecider` are
  additive.
- `Keiki.Builder` keeps every existing verb. `chainTo` is new and
  optional; existing aggregates that do not use it are unaffected.
- Both example aggregates (`Keiki.Examples.EmailDelivery` and
  `Keiki.Examples.UserRegistration`) keep their builder-form and
  AST-form transducers as shipped by Plan 15. M4 adds
  `userRegDriverConfig` to the latter; M5 adds an alternate
  builder-form `userRegChained` for cross-form testing of
  `chainTo`. The transducer values themselves are unchanged.


## 5. What's not in scope

- *AST widening (`Edge.output` to a list)*. EP-19 specifies this
  alternative and is the Cancelled path under MasterPlan 7.

- *Hand-written `apply` (Approach 3 in the multi-event note)*.
  Excluded as incompatible with the synthesis foundation: it
  surrenders the mechanical-`apply` win.

- *A parallel formalism module for GSM*. Both the canonical and
  Cancelled paths extend the existing single AST; neither
  introduces a parallel core.

- *Conditional output lists*. Aggregates that need conditional
  emission (e.g. a property-sync command emitting up to 12
  conditional events) express each conditional event as a
  separate edge with a disjoint guard. This is the existing
  pattern and remains correct under EP-20.

- *Runtime concerns* — event-store batching, transaction
  boundaries, idempotency keys, retry semantics. keiki is the pure
  core; the runtime adapter handles those. `applyEvents` is the
  primitive a chunk-replaying adapter consumes.


## 6. M5 deferral plan (preserved for posterity)

The plan was originally drafted with M5 (`chainTo` DSL verb)
soft-deferred behind Plan 15
(`docs/plans/15-edge-builder-monadic-dsl-for-authoring-symtransducer-edges.md`).
Plan 15 specified the entire builder DSL (`from`, `onCmd`, `emit`,
`goto`, `(.=)`, etc.); building `chainTo` requires the
`EdgeBuilder` indexed monad to exist.

Plan 15 shipped on 2026-05-02 with all milestones complete (M0–M7)
before any work on EP-20 began. `Keiki.Builder` is in place and
exports the full DSL; both example aggregates are now in builder
form (`userReg`, `emailDelivery`) with AST forms preserved as
`userRegAST`, `emailDeliveryAST` for cross-form equivalence testing.

EP-20's M5 is therefore unconditional: `chainTo` extends the
existing `Keiki.Builder` module directly. The original deferral
path — under which EP-20 would close after M4/M6/M7 and Plan 15's
implementation would absorb `chainTo` per this design note's M5
specification — is no longer needed. It is recorded here as a
"what would have happened if Plan 15 had not landed" note for
readers reconstructing the project history.


## 7. Verification plan

After implementation, the load-bearing acceptance tests are:

1. **Multi-event decide via façade.** Given `mdec = toMultiDecider
   userReg userRegDriverConfig`, `decide mdec (StartRegistration sd)
   (PotentialCustomer, emptyRegs)` returns a 2-element list
   `[RegistrationStarted …, ConfirmationEmailSent …]` ending in
   `RequiresConfirmation`.

2. **Underlying letter FST unchanged.** `decide (toDecider userReg)
   (StartRegistration sd) (PotentialCustomer, emptyRegs)` returns
   `[RegistrationStarted …]` (length 1) ending in `Registering`;
   `decide (toDecider userReg) Continue (Registering, regs)`
   returns `[ConfirmationEmailSent …]` (length 1) ending in
   `RequiresConfirmation`.

3. **Chunk replay.** `applyEvents userReg (PotentialCustomer,
   emptyRegs) [RegistrationStarted …, ConfirmationEmailSent …]`
   returns `Just (RequiresConfirmation, regs)` with registers
   populated.

4. **`isInternal` correctly classifies.**
   `isInternal userRegDriverConfig Registering == Just Continue`;
   for every other vertex, `Nothing`.

5. **Builder cross-form equivalence.** A `chainTo`-authored
   `userRegChained` produces the same `Edge` list as the existing
   builder-form `userReg` on the canonical command sequence.

The full plan and milestone breakdown are in
`docs/plans/20-multi-event-commands-via-state-refinement-ergonomics.md`.
