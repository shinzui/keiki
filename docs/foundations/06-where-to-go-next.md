# 06 — Where to Go Next

You've built up the vocabulary. The library's design notes live in
`docs/research/`. Here's a recommended path through them.

## Required reading

These four cover the design as it stands today.

1. **`synthesis-c-foundation-b-presentation-with-worked-examples.md`** (~30 min)
   The current direction for handling data, with two fully worked
   examples (an event-sourced aggregate and a process manager). Maps
   directly onto foundations `05`. This is the load-bearing design
   synthesis — start here.

2. **`formalism-choice-mealy-machines-vs-finite-state-transducers.md`** (~20 min)
   Sharper take on why the FST is the right choice for keiki versus
   the Mealy-machine encoding used by `crem`. Reinforces foundations
   `03`. Skip on first pass if you trust the choice.

3. **`effects-boundary.md`** (~25 min)
   The contract between the pure core (`Keiki.Core`) and the runtime
   layer that gives it durability, time, and an outside world.
   Specifies what is pure, what is not, and what types cross the
   boundary in each direction.

4. **`keiki-generics-design.md`** (~20 min)
   How `Keiki.Generics` and `Keiki.Generics.TH` derive `InCtor`,
   `WireCtor`, and `RegFile` shapes from your record types so you
   don't write the structural alphabet boilerplate by hand.

## Depth on specific topics

Read these when you hit the topic, not in order.

- **`composition-combinators-design.md`**
  How `compose`, `alternative`, and `feedback1` are derived; the
  substitution algorithm and slot-name disjointness machinery.
  Read when you start composing transducers across bounded contexts.

- **`acceptor-projections-design.md`**
  How `Keiki.Acceptor.inputAcceptor` and `outputAcceptor` recover the
  underlying letter automata from a `SymTransducer`. Useful when you
  want to validate a command sequence or an event log independently
  of the full transducer.

- **`multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md`**
  When one command needs to produce multiple events, how to model
  it. Three approaches with trade-offs; the chosen one
  (state refinement + `toMultiDecider`) is what `Keiki.Decider` ships.

- **`schema-evolution.md`**
  How to evolve event and register-file schemas across versions
  without breaking replay. Forward-looking application-layer
  guidance.

- **`symbolic-analysis-and-runtime-implications.md`**
  What "symbolic analysis" means in keiki, what `Keiki.Symbolic`
  buys you over `Keiki.Core`, and what it costs (SBV cabal dep, z3
  in `PATH`, ~10ms per solver call). Read before deciding whether
  to import `Keiki.Symbolic` or whether to install z3 in CI.

- **`sbv-boolalg-design.md`**
  The design rationale for the SBV-backed `BoolAlg` instance —
  how `HsPred` is translated to SMT, how constructor mutex is
  encoded, what the witness-extraction story looks like.

- **`architecture-comparison-keiki-vs-crem.md`**
  How keiki differs from `crem`, the other Haskell FST-shaped
  library. Useful for sanity-checking design choices.

## Historical and exploratory

These document decisions and explorations rather than the current
design. They predate the symbolic-register direction and use the toy
`Transducer s c e` formalism rather than the shipped
`SymTransducer phi rs s ci co`. Read when you want to understand
*why* the design landed where it did, not as references for the
current API.

- **`data-direction-b-indexed-state-per-vertex.md`** and
  **`data-direction-c-symbolic-and-register-automata.md`**
  The parallel exploration that produced the synthesis. Read these
  if you want to understand the trade-offs the synthesis makes.
- **`core-design-transducer-as-source-of-truth.md`** — early kernel
  sketch. Superseded by the synthesis doc.
- **`efsm-based-workflow-engine-technical-analysis.md`** — earlier
  analysis of the EFSM extension; the rejected alternative to
  symbolic-register.
- **`fst-as-workflow-runtime.md`** — runtime architecture sketch
  built on the toy `ExtTransducer` formalism. The architectural
  ideas (event store, queue, subscriptions, timers) survived into
  `effects-boundary.md`; the encoding did not.
- **`future-directions-profunctors-effects-and-composition.md`** —
  pre-keiki "what we should build" doc. Most of the listed items
  have shipped under different names (see
  `architecture-comparison-keiki-vs-crem.md` for the mapping).
- **`orchestration-sagas-choreography-and-feedback-loops-as-transducers.md`** —
  saga / choreography / feedback patterns expressed in the toy
  formalism. Conceptually still valid; the encoding is stale.
- **`performance-analysis-projection-costs-and-production-architecture.md`** —
  the central perf concern (linear scan in `outputProjection` over
  enumerated commands) is for the toy `Transducer s c e`; keiki's
  `applyEvent` uses structural `solveOutput` and doesn't enumerate.
  See `symbolic-analysis-and-runtime-implications.md` for the
  current perf-relevant data (SBV solver-call cost).
- **`workflow-modeling-approvals-pipelines-and-human-in-the-loop-as-transducers.md`** —
  workflow patterns catalogue. Patterns are sound; encoding is the
  toy formalism.
- **`v1-escape-hatch-retirements-design.md`** — record of which
  prototype-era escape hatches were retired and what replaced them.
  Useful when reading older design notes that mention
  `OFn`/`PMatchC`/`unsafeCombine`/`TInpField`.

## Benchmarking

`cabal bench` runs the `keiki-bench` benchmark suite (EP-22), which
exercises the five pure-core operations (`delta`, `omega`, `step`,
`applyEvent`, `reconstitute`) on the `UserRegistration` and
`OrderCart` example aggregates in both authoring forms (builder
and AST). See **`bench/README.md`** for how to capture a baseline,
diff against a previous run, and read the `bcompare` ratios in
the `head-to-head` group.

## Authoring a transducer

For the action-oriented walkthrough, read **`docs/guide/user-guide.md`**.
It covers the four-layer authoring model (`buildTransducer` →
`from` → `onCmd`/`onEpsilon` → edge body), the TH derivations,
running a transducer, the `Decider`/`Acceptor` façades,
composition, the symbolic analyses, common errors, and an
extensive glossary. It's the right starting point if you're about
to write a new aggregate.

The recommended entry point in code is the **`Keiki.Builder`**
module — a monadic DSL that compiles down to the `Keiki.Core`
AST. Read its haddock alongside the user guide; the worked
`EmailDelivery` example at the top is a complete tutorial. The
builder removes the per-edge boilerplate of the AST (record
literals, infix `combine`, slot-name-tagged `USet` annotations,
`OFCons` chains) without changing the formalism. Two pieces of
sugar make day-to-day authoring read like a state-machine
description:

- **`slot @"name" .= term`** for register writes — the slot
  name is supplied as a TypeApplication so `(.=)` can enforce
  distinct-target safety at compile time.
- **Per-event `<CtorName>TermFields` records for `emit`** —
  generated by `Keiki.Generics.TH.deriveWireCtors` alongside
  the wire-ctor value. Call sites read top-to-bottom keyed by
  the event's payload field names, with wrong-field-order or
  missing-field bugs caught at compile time.

Drop down to `Keiki.Core` directly only when the builder cannot
express what you need. The two example aggregates
(`Jitsurei.EmailDelivery`, `Jitsurei.UserRegistration`)
each ship the same transducer authored in both forms, side by
side, as a reference.

## Asking questions

If something in the foundations doesn't land, the right move is to
file an issue against the foundations doc rather than re-deriving the
mental model on your own. The same goes for the research notes — the
docs should explain themselves, and gaps are bugs.
