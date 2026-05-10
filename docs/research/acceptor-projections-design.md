# Acceptor projections (input/output) on `SymTransducer` — design

This note is the design record for the `Keiki.Acceptor` module added
to keiki under MasterPlan 5 / ExecPlan 12. It names, at the level of
data and code, the two acceptor projections that
`docs/foundations/04-projections-and-deriving-event-sourcing.md`
spells out as the central insight of the formalism.

The companion files referenced throughout this note are:

- `docs/foundations/04-projections-and-deriving-event-sourcing.md` —
  the foundations chapter that motivates the projections in plain
  English. Defines π₁ (input projection / command acceptor) and π₂
  (output projection / event acceptor).
- `docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`
  — the synthesis the keiki library is built around. The acceptor
  vocabulary lines up with §"Direction C" — symbolic-register
  transducer formalism.


## Problem statement

The keiki single-aggregate formalism is mature: a `SymTransducer phi
rs s ci co` carries a finite control graph plus a symbolic register
file, and `Keiki.Core` exports `delta`, `omega`, `step`, `applyEvent`,
and `reconstitute` over that shape.

Foundations chapter 04 spends most of its prose on the central insight
that any FST has two acceptor projections:

- The **input projection** π₁: drop the events. The remaining
  transition function is an acceptor over the input alphabet
  (commands). Its language is the set of command sequences the
  aggregate accepts.
- The **output projection** π₂: drop the commands by inverting ω. The
  remaining transition function is `evolve` (a.k.a. the event-language
  acceptor). Its language is the set of event sequences the aggregate
  could have produced — the set of replayable logs.

In the current code these projections are *implicit*. π₁ is reachable
by calling `delta` directly. π₂ is reachable by calling `applyEvent`
directly. But there is no `Acceptor` data type, no `inputAcceptor` /
`outputAcceptor` functions are exported, and the relationship the
foundations chapter spells out is invisible at the API surface.

Users who want to ask "is this command sequence accepted?" or "is
this log replayable?" have to plumb `delta` or `applyEvent` by hand
through a state-and-register fold. Downstream code (UI, validation,
generated docs) cannot pattern-match on a known data type because
the projection has no type.

This EP fixes the omission by adding the smallest possible data type
that carries the two projections, plus folding helpers.


## The shape

The `Acceptor` data type is the minimum viable acceptor — a step
function, an initial state, and a final-state predicate:

    data Acceptor a s = Acceptor
      { aStep    :: s -> a -> Maybe s
      , aInitial :: s
      , aIsFinal :: s -> Bool
      }

Three observations on the shape:

- `aStep` returns `Maybe s` — not `Maybe (s, [event])` or
  `Either Reject s`. An acceptor's job is to decide membership;
  rejection is the absence of a transition. The richer return type
  belongs in `delta` / `applyEvent`, not in the projection.
- The type parameter order is *alphabet first, state second*. This
  matches the partial-application intuition "an acceptor over
  commands": the alphabet is the primary visible parameter; the state
  carrier is implementation detail. `Acceptor ci s` reads as "an
  acceptor over `ci`."
- No `Show` / `Eq` instance on `Acceptor`. The data type carries
  closures (`aStep`, `aIsFinal`); it's inherently not showable or
  comparable. Tests assert on `runAcceptor` outputs instead.


## Why the state carrier is `(s, RegFile rs)` and not `s`

Every edge guard depends on both the control vertex and the register
file. `evalPred` (`src/Keiki/Core.hs:514`) reads registers via
`TReg`; the `PEq (TReg ...) (TInpCtorField ...)` predicates that
guard, e.g., `RequiresConfirmation -> Confirmed` on
`UserRegistration` cannot be evaluated without the registers. The
acceptor must therefore thread the register file through each step,
or it cannot evaluate guards on subsequent inputs.

The state carrier is consequently the same pair `(s, RegFile rs)`
that `delta` and `applyEvent` already use as their input/output type.
This matches the choice `toDecider` makes in `src/Keiki/Decider.hs`
and is inherent to the symbolic-register extension of foundations
doc 04 (which presents the simpler register-free case).


## The projections

Each projection is one Haskell binding wrapping the corresponding
`Keiki.Core` step:

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

`inputAcceptor` is `delta` curried into the acceptor record;
`outputAcceptor` is `applyEvent` curried into the acceptor record.
There is no further logic. The projection is just *naming what
already exists*.


## Folding helpers

`runAcceptor` and `accepts` are the two trivial folds users want most:

    runAcceptor :: Acceptor a s -> [a] -> Maybe s
    runAcceptor a = go (aInitial a)
      where
        go s []       = Just s
        go s (x : xs) = aStep a s x >>= \s' -> go s' xs

    accepts :: Acceptor a s -> [a] -> Bool
    accepts a xs = case runAcceptor a xs of
      Just s  -> aIsFinal a s
      Nothing -> False

`runAcceptor` is `foldlM aStep aInitial` written longhand to keep the
signature standalone (no `Control.Monad` import required).
`accepts` extends it with the final-state check.


## What the projections preserve

The acceptor's language is exactly the language foundations chapter
04 describes:

- `inputAcceptor t` accepts the command sequences `t` accepts. By
  construction `aStep (inputAcceptor t) (s, regs) ci = delta t s regs
  ci`, so a command sequence reaches a final state via `inputAcceptor
  t` iff it reaches a final state via successive `delta` calls.

- `outputAcceptor t` accepts the event sequences `t` could have
  produced. By construction `aStep (outputAcceptor t) (s, regs) co =
  applyEvent t s regs co`, so an event sequence is accepted iff it
  replays cleanly through `reconstitute t`. The final-state predicate
  is the same `isFinal t` in both directions.

The mechanical-projection property — the two directions agree — is
inherited from the underlying `SymTransducer`. `delta` and
`applyEvent` are derived from the same edges; nothing in the
projection introduces a fresh contract to verify.


## What is deliberately deferred

This EP names what's already implicit. It does not add automata-
theory machinery beyond that name:

- **Composition over Acceptors.** Intersection of accepted languages
  (the obvious "and" combinator), union, language difference. None
  of these are needed for the acceptor-as-projection use case the
  foundations chapter motivates. A future EP can add them if a real
  workflow asks. Note that `Keiki.Composition.compose` already
  composes *transducers*; a transducer-level composite has its own
  input/output acceptors via the same projections — composition over
  acceptors is a different (smaller) abstraction.

- **Language-equivalence checks.** "Do these two acceptors accept
  the same language?" is decidable for finite-state acceptors but
  requires real machinery (product construction, reachability,
  equivalence relation). Out of scope for v1.

- **Profunctor structure.** `Acceptor a s` is naturally contravariant
  in `a` (preprocess the alphabet via `(b -> a) -> Acceptor a s ->
  Acceptor b s`) and would form a `Profunctor` if extended over its
  state. None of this is needed yet; tests demonstrate `runAcceptor`
  output equality with `reconstitute` instead.

- **Lifting acceptors into the transducer's evolution loop.** The
  acceptor stays a downstream observer; the transducer is unchanged.
  No `step`-level rewrite that goes through `Acceptor`. The synthesis
  note's invariant "the transducer doesn't know about projections"
  applies here too.


## Worked examples

Two examples on the existing canonical aggregates demonstrate the
projection bodies. Tests in `test/Keiki/AcceptorSpec.hs` assert each
of these.

**Input acceptance on `userReg`.** The canonical four-step command
sequence `[StartRegistration …, Continue, ConfirmAccount …,
FulfillGDPRRequest …]` reaches `Deleted`, which is final.

    accepts (inputAcceptor userReg) canonicalCmds  ==  True

**Input rejection on `userReg`.** Sending `ConfirmAccount` from
`PotentialCustomer` has no matching outgoing edge (the only edge
from `PotentialCustomer` guards on `isStart`).

    accepts (inputAcceptor userReg)
            [ConfirmAccount …]                      ==  False

**Output acceptance on `emailDelivery`.** The two-vertex aggregate
has one event (`EmailSent`) which lands at the terminal vertex.

    accepts (outputAcceptor emailDelivery)
            [EmailSent …]                           ==  True

`emailDelivery` is preferred over `userReg` for the output-acceptor
demonstration because every transition produces a wire event;
`userReg`'s ε-edge `RequiresConfirmation -> Deleted` on
`FulfillGDPRRequest` would block `applyEvent` replay through that
edge (per the MP-4 retrospective).

**Round-trip with `reconstitute`.** For any log,
`fmap fst (runAcceptor (outputAcceptor t) log)` and
`fmap fst (reconstitute t log)` agree. This is the load-bearing
property: `outputAcceptor` is just the acceptor view of the same
replay machinery.


## Why this lives in `Keiki.Acceptor`, not `Keiki.Core`

`Keiki.Core` is the single-transducer formalism: edges, the
transducer record, the step functions, the inverse step. `Acceptor` is
a derived view — a four-line wrapper over the existing step
functions. Putting it in its own module keeps the formalism layer
small and makes the projection vocabulary discoverable as a separate
import. This matches the rationale that put `Keiki.Composition` in
its own module (MP-4 / EP-11 Decision Log).


## Relationship to `Keiki.Decider`

`Keiki.Decider.toDecider` projects a `SymTransducer` to a Chassaing-
shape four-field record (`decide`, `evolve`, `initialState`,
`isTerminal`). It's a *different* projection — Decider is shaped for
"naive functional event sourcing" consumers and lifts both directions
at once into a single record.

`Acceptor` is shaped for the foundations-chapter view: one alphabet
at a time, with the membership question (`accepts`) front-and-centre.
Both projections coexist; neither subsumes the other. EP-12 does not
modify `Keiki.Decider`.
