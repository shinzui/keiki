# 05 — Data-Carrying Alphabets

The FST machinery from `03` and `04` assumes finite alphabets — a
fixed enumerable set of commands and events. Real systems have
commands like `StartRegistration "alice@x.io" "Z9F4" 2026-04-30T10:00Z`
where the email, code, and timestamp are arbitrary values from
infinite sets. This chapter explains why that's a problem and how the
library handles it.

## What breaks when alphabets are infinite

Recap from `04`: deriving `evolve` from the FST works by enumerating
all commands and finding the one that produces the observed event:

```
evolve s e = the unique s' such that
             ∃ c. δ(s, c) = Just s' AND ω(s, c) = Just e
```

If commands are `Enum, Bounded`, "enumerate all commands" is concrete —
there are finitely many. If a command is `StartRegistration Email
ConfirmationCode UTCTime`, there are infinitely many — one for every
combination of email, code, and timestamp. We cannot enumerate.

Every analytical operation that depends on enumeration breaks the same
way: deadlock detection, language equivalence, contract checking,
mechanical `evolve` derivation. None of them survive a naive move to
infinite alphabets.

## First attempt: opaque context (the EFSM extension)

The most obvious workaround is to keep the FST's control flow finite
and stash the data on the side. This is an **Extended Finite-State
Machine** (EFSM):

```haskell
data EFSM s ctx c e = EFSM
  { delta :: s -> ctx -> c -> Maybe s    -- transitions over (state, ctx, command)
  , omega :: s -> ctx -> c -> Maybe e
  , rho   :: s -> ctx -> c -> ctx        -- update the context
  , initial    :: s
  , initialCtx :: ctx
  , isFinal    :: s -> Bool
  }
```

The control state `s` is finite (still enumerable). The data context
`ctx` is arbitrary — counters, sets, maps, whatever the workflow
needs.

**This works for many things.** The control flow stays finite, so
deadlock detection and reachability still operate on the control graph.
You can express "approve when N approvers have signed off" by counting
in `ctx`.

**But `evolve` derivation falls over.** `ctx` is opaque to the
formalism. The library has no way to mechanically invert ω when the
output depends on a `ctx` value the formalism can't see into. The user
has to write `evolve` (called `apply` in keiki) by hand and verify it
matches via tests. We're back to the original event-determinism
contract.

The keiki research notes explored this EFSM-with-opaque-context
option early on. It would buy workflow support but at the cost of
the central derivation property from `04`, which is why keiki picked
the symbolic-register direction instead (see
`docs/research/data-direction-c-symbolic-and-register-automata.md`).

## Better idea: predicates instead of symbols

The trick is to stop enumerating the alphabet symbol by symbol and
start describing it with **predicates**.

Concretely: instead of writing one transition per command value,
label edges with a *predicate* over inputs. "Any
`StartRegistration` command, for any email and code." A single edge
covers infinitely many concrete inputs.

This is the **Symbolic Finite Transducer** (SFT). The alphabet is
described, not enumerated.

```
Plain FST:                                Symbolic FST:
─────────────────────────                ─────────────────────────────────
each transition labeled                  each transition labeled by a
by one symbol from a                     predicate ψ over the input
finite alphabet                          domain (which is allowed to
                                         be infinite)

(PC, StartRegistration                   (PC, ψ: matches StartRegistration)
     "alice@x.io" "Z9F4" t0)             — one edge, infinitely many
→ RC                                       concrete inputs covered
                                         → RC
```

The output side gets the same treatment: instead of an output
*symbol*, the edge carries an output *term* — a small expression that
computes the output from the input. "Emit `RegistrationStarted` with
the email and code copied from the input command."

For analysis to work, the predicate language needs **decidable
satisfiability**: given a predicate, we can ask "is there any input
that satisfies it?" and get a yes/no answer. Linear arithmetic,
boolean combinations of equalities, and many other useful theories
qualify. SMT solvers (z3, cvc5) provide the engine.

For keiki v1, predicates are just Haskell functions and
"satisfiability" is checked by user-supplied generators (Hedgehog
witnesses). v2 swaps in an SBV-backed predicate AST so the analysis
becomes symbolic.

Concretely you write a guard as an `HsPred` AST. The underlying
constructors are `PEq`, `PCmp`, `PAnd`, `POr`, `PNot`, `PInCtor`, but
the preferred authoring surface is the dot-prefixed operators
(`.>=`, `.<=`, `.==`, `./=`, `.&&`, `.||`, `pnot`, and the term
arithmetic `.+`/`.-`/`.*`) — thin aliases for those constructors that
read as the inequalities they are. See "Writing guards with operators"
in `docs/guide/user-guide.md` §3.4 for the full set and fixities.

## Tracking data over time: registers

Predicates handle commands' payloads, but workflows also need to
*remember* values across transitions:

> "Wait for three approvals then proceed."

You can't express that with predicates alone — you need to count.
The library borrows from **Streaming String Transducers** (SST,
Alur & Černý 2011): each transition can update a small typed
**register file**. The state of the machine is `(control vertex,
register file)`.

```haskell
data RegFile (rs :: [Type])
-- e.g.  RegFile '[ "approvers" ':-> Set UserId
--                , "documentId" ':-> DocumentId
--                , "requiredCount" ':-> Int ]
```

Updates are written in a small total combinator language (not
arbitrary Haskell), so the library can analyze them — for example,
prove that no register's contents are duplicated on a single transition
("copyless"), which is the key restriction that keeps SST equivalence
decidable.

```haskell
data Update rs ci where
  Keep    :: Update rs ci
  Set     :: Index rs r -> Term rs ci r -> Update rs ci
  Combine :: Update rs ci -> Update rs ci -> Update rs ci
```

A `Term` is a small expression over registers and the input. It's an
AST, not a Haskell function — that's what lets the library introspect
it.

## The library's actual shape

keiki uses both ideas: SFT predicates on guards, SST-style register
file for accumulated data. Internally:

```haskell
data Edge phi rs ci co s = Edge
  { guard  :: phi                         -- predicate over (regs, input)
  , update :: Update rs ci                -- copyless register update
  , output :: Maybe (OutTerm rs ci co)    -- term producing output
  , target :: s                           -- next control vertex
  }

data SymTransducer phi rs s ci co = SymTransducer
  { edgesOut    :: s -> [Edge phi rs ci co s]
  , initial     :: s
  , initialRegs :: RegFile rs
  , isFinal     :: s -> Bool
  }
```

The plain FST from `03` is the special case where `rs = '[]`, every
update is `Keep`, and every guard is "matches one specific symbol."
The EFSM extension is the special case with one register and an
opaque update function. Symbolic-register transducers subsume both.

## Does `evolve` derivation come back?

Yes, with caveats.

Given an event, the library finds the unique edge whose `output` term
unifies with the observed event, recovers the input from the unified
term, and runs the (deterministic) update. This works mechanically when:

1. The output term is **invertible in the input fields** — given the
   event payload, you can recover the input fields. (Trivial when the
   output just copies fields from the input. Harder when the output is
   a derived value.)
2. The update only reads input fields that appear in the output term.

When either fails, the library detects the problem **at build time**
and either prompts the user to fix the schema or asks for a
hand-written `apply` for that edge.

This is the property the EFSM extension surrendered, and that the
symbolic-register formulation gets back. The two worked examples in
`docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`
both surface this issue concretely.

## What you give up

Honestly: some analytical questions become harder.

- **Language inclusion** ("is every event sequence the saga emits also
  accepted by the downstream aggregate?") is decidable for plain
  finite-alphabet FSTs but undecidable for general symbolic ones. For
  the deterministic, single-valued machines event-sourced systems
  actually write, the practical cases are still tractable.
- **Equivalence** of two symbolic transducers is decidable in the
  single-valued case (Veanes 2012). That's the case keiki targets.
- Some analyses move from "decidable, polynomial" to "decidable,
  needs SMT." They still terminate; they just cost more.

Full table is in
`docs/research/data-direction-c-symbolic-and-register-automata.md` §4.

## Vocabulary recap

- **Symbolic alphabet** — described by predicates instead of
  enumerated. The alphabet itself can be infinite.
- **Symbolic Finite Transducer (SFT)** — FST whose transitions are
  labeled by predicates and output terms instead of symbols.
- **Predicate algebra / `BoolAlg`** — the language predicates are
  written in. Needs decidable satisfiability for analysis. SMT is the
  canonical implementation.
- **Register file** — a typed tuple of values the transducer carries
  alongside its control state.
- **Update language** — small combinator language for modifying
  registers. Closed and analyzable; not arbitrary Haskell.
- **Copyless update** — restriction that no register's contents are
  duplicated on a single transition. Key for keeping equivalence
  decidable.
- **Symbolic-register transducer** — keiki's hybrid: SFT predicates +
  SST-style register file. The actual library type.
- **Hidden-input check** — build-time check that flags edges where
  the update or guard depends on input fields not present in the
  output term. Without this, replay can't recover the value the
  update wrote.
