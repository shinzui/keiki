# Foundations: Reading Guide

This folder contains the conceptual background for the keiki library.
It exists so anyone joining the project — engineer, reviewer, future
contributor — can pick up the design without having to assemble the
mental model from scratch.

The companion folder `docs/research/` contains design notes for the
library itself. Those notes assume you already know the vocabulary that
this folder establishes.

## Who this is for

Engineers who will use, contribute to, or review keiki. We assume:

- Working comfort with Haskell (records, sum types, basic generics).
  Some sections use type-level Haskell (GADTs, `DataKinds`); we'll flag
  those as we go.
- Some familiarity with event sourcing or DDD aggregates is helpful but
  not required — `02-event-sourcing-and-the-decider.md` covers the
  basics.
- No prior background in automata theory.

## Reading order

```
01-problem-space.md                              ~10 min
02-event-sourcing-and-the-decider.md             ~10 min
03-finite-automata-and-transducers.md            ~15 min
04-projections-and-deriving-event-sourcing.md    ~15 min
05-data-carrying-alphabets.md                    ~15 min
06-where-to-go-next.md                           ~5 min
```

Total commitment: about an hour.

## What you can skip

- **01** if you already understand why someone would build a workflow
  engine on top of event sourcing instead of using Temporal/Cadence.
- **02** if you've shipped event-sourced systems and recognize the
  decider pattern (`decide`/`evolve`).
- **05** on a first pass if you're not going to touch the symbolic /
  SMT layer. Come back to it before reading the synthesis design note.

## After the foundations

`06-where-to-go-next.md` lists the design notes in `docs/research/`
in recommended reading order. The shortest path through the library's
own design after the foundations is:

1. `core-design-transducer-as-source-of-truth.md`
2. `synthesis-c-foundation-b-presentation-with-worked-examples.md`

Everything else is depth on specific topics (multi-event commands,
symbolic-vs-indexed alternatives, workflow runtime, profunctor
structure).

## A note on style

These docs build vocabulary, not formalism. We use small concrete
examples instead of formal definitions. Where a formal treatment matters
for the library, we point at the relevant paper or design note rather
than reproducing it here.
