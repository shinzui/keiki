# GSM Widening Design: First-Class Multi-Event Commands

> Historical API note (2026-07-12): references below to the Decider facade
> describe a pre-0.1 design that has been removed. Use `Keiki.Core.stepEither`
> for forward decisions and the structured Core replay functions for hydration.
> The opening `Maybe`-output snippets are the before-state this design widened;
> the shipped `Edge.output` is `[OutTerm ...]`.

**Status:** Design note for [ExecPlan 19](../plans/19-multi-event-commands-via-edge-output-widening-gsm-expansion.md).
**Date:** 2026-05-16.
**Parent research:** [multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md](multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md)
(Approach 2 — GSM Expansion).

This note records the design decisions backing the AST widening that
makes multi-event commands first-class in keiki's pure core.


## 1. Problem statement

keiki's `Keiki.Core` today models the formalism as a *letter Finite
State Transducer* (letter FST): each transition produces zero or
exactly one output event. The AST encodes this directly:

```haskell
data Edge phi rs ci co s where
  Edge
    :: { guard  :: phi
       , update :: Update rs w ci
       , output :: Maybe (OutTerm rs ci co)   -- Nothing = ε; Just o = one event
       , target :: s
       }
    -> Edge phi rs ci co s
```

A command that semantically produces N events (the canonical example
is `StartRegistration` → `[RegistrationStarted, ConfirmationEmailSent]`)
must be expressed by *state refinement* — adding an intermediate
vertex (`Registering`) and a synthetic internal command (`Continue`)
so two letter edges chain through the refinement. This is the
"Approach 1" pattern preserved in
`jitsurei/src/Jitsurei/UserRegistrationV0.hs` for compatibility.

The state refinement is unergonomic: it inflates the user's vertex
enum, inflates the command enum, requires synthetic-command plumbing
through the runtime, and forces the model to expose internal control
states alongside genuine business states. EP-20 (state-refinement
ergonomics, shipped 2026-05-02) papered over the unergonomics with
a `toMultiDecider` façade and a `chainTo` builder verb, but the
internal vertex/command shapes remained in the user's AST.

This document records the design of EP-19's alternative: widen the
AST itself so multi-event commands become first-class. The widened
transducer is a *Generalized Sequential Machine* (GSM) in the
formal-languages sense.


## 2. Formal mapping: letter FST → GSM

The letter FST's output function:

```
ω : S × C → E ∪ {ε}
```

widens to the GSM output function:

```
ω : S × C → E*
```

where `E*` is the Kleene star — the set of finite words (lists, in
Haskell) over `E`. Length 0 is the empty word (ε); length 1 reproduces
letter behaviour; length 2+ admits multi-event commands.

A GSM is strictly more expressive than a letter FST. Any letter FST
embeds into the GSM by mapping `ε` to `[]` and `e` to `[e]`. The
converse is not true — a GSM with a length-2+ output cannot be
collapsed to a letter FST without introducing intermediate vertices
(i.e., re-introducing the state refinement we're trying to retire).

This is the formal substrate of "Approach 2" in the parent research
note. The contribution of EP-19 is committing to it in the AST
itself.


## 3. AST change

The `output` field's type changes:

```haskell
data Edge phi rs ci co s where
  Edge
    :: { guard  :: phi
       , update :: Update rs w ci             -- existential w preserved
       , output :: [OutTerm rs ci co]         -- changed from Maybe
       , target :: s
       }
    -> Edge phi rs ci co s
```

Three semantic regions:

- `output = []` — ε-edge. Behaviour identical to today's
  `output = Nothing`. The transition fires (registers may update,
  target vertex changes) but emits no observable event.
- `output = [o]` — letter edge. Behaviour identical to today's
  `output = Just o`. Emits exactly one event.
- `output = [o1, o2, ..., oN]` — multi-event edge. Emits N events
  in declaration order. Each `OutTerm` evaluates against the same
  pre-transition `(regs, ci)` snapshot; register updates apply *once*
  at the edge level, not per-emitted-event.

The existential `w :: [Symbol]` index on `update :: Update rs w ci`
is preserved unchanged: the per-edge `Disjoint` static check on
slot writes still constrains each `Update` value at its
construction site, and the existential hides `w` from the
`edgesOut :: s -> [Edge phi rs ci co s]` homogeneous list.

Decision: `output :: [OutTerm rs ci co]` — not `Foldable f =>
f (OutTerm rs ci co)`, not a separate sum type for length-0/1/N.
Lists are the simplest shape that admits all three regimes;
SBV translation, `solveOutput`, and `checkHiddenInputs` all walk
lists naturally; pattern-matching stays mechanical.


## 4. The `InFlight` wrapper

A length-2+ edge poses a subtle question for the replay path: what
is the state *between* the emitted events?

```
PotentialCustomer
    →? apply(_, RegistrationStarted)        = ???
    →? apply(???, ConfirmationEmailSent)    = RequiresConfirmation
```

There are two runtime regimes:

- **Chunk replay** — the runtime preserves command boundaries
  (event store with command-id tags, transactional batches,
  deterministic test fixtures). One command's events arrive as
  one list `[e1, ..., eN]` and the replay applies them atomically.
  The state between intermediate events is *unobservable*; the
  function `applyEvents :: ... -> (s, RegFile rs) -> [co] -> Maybe
  (s, RegFile rs)` consumes a chunk and returns the unwrapped
  final state.

- **Streaming replay** — the runtime sees one event at a time
  with no command-boundary marker. The state mid-chain *must* be
  expressible. The `InFlight s co` wrapper exposes it:

  ```haskell
  data InFlight s co = Settled !s | InFlight !s ![co]
    deriving (Eq, Show)
  ```

  Semantically:
  - `Settled s` — at a stable vertex; the next event must be the
    first emission of *some* outgoing edge of `s`.
  - `InFlight s [eN, eN-1, ..., e2]` — mid-chain at vertex `s`'s
    incoming-edge target; the next event must be `eN` (the head
    of the queue); `s` is the *final* target vertex of the
    in-flight chain (registers were already updated at the
    transition into `InFlight`).

The `applyEvent` operator widens:

```haskell
applyEvent
  :: BoolAlg phi (RegFile rs, ci)
  => SymTransducer phi rs s ci co
  -> InFlight s co -> RegFile rs -> co
  -> Maybe (InFlight s co, RegFile rs)
```

Two arms:

1. `Settled s` — walk outgoing edges of `s`; find the unique edge
   whose `output` list's *head* inverts via `solveOutput` to a
   valid `ci` satisfying the guard. Commit to that edge. Run the
   update. If `length (output e) == 1`, return
   `(Settled (target e), regs')`. If `length (output e) >= 2`,
   return `(InFlight (target e) tail, regs')` where `tail` is the
   evaluated tail of `output e`'s `OutTerm`s against the recovered
   `(regs, ci)` snapshot.

2. `InFlight s (q1 : rest) regs` — verify that `q1` matches the
   observed `co` (equality on `co`, since `q1` is already evaluated).
   If yes: if `rest == []`, return `(Settled s, regs)`; else return
   `(InFlight s rest, regs)`. No register update on this step —
   registers were updated at the `Settled → InFlight` transition.
   If `q1 /= co`, return `Nothing` (out-of-order replay).

The chunked `applyEvents`:

```haskell
applyEvents
  :: BoolAlg phi (RegFile rs, ci)
  => SymTransducer phi rs s ci co
  -> (s, RegFile rs) -> [co]
  -> Maybe (s, RegFile rs)
```

lifts the start state to `Settled`, folds `applyEvent` over the
events, and unwraps a `Settled` at the end (returning `Nothing` if
the chunk ends in `InFlight`, which signals a truncated chunk).

The two regimes agree on length-0/1 edges: a `Settled → Settled`
single step in both. They diverge cleanly on length-2+: the
streaming path passes through `InFlight`; the chunked path
collapses the chain atomically.

**Worked example on `StartRegistration`.** With the widened AST,
the `PotentialCustomer → RequiresConfirmation` edge has
`output = [registrationStarted, confirmationEmailSent]` (both
evaluated against the same input snapshot). Starting from
`Settled PotentialCustomer`:

- Observe `RegistrationStarted`: invert to recover the
  `StartRegistration` payload; verify guard; run update;
  evaluate the rest of the output list against the recovered
  `(regs', ci)` to get `[confirmationEmailSent]`; return
  `(InFlight RequiresConfirmation [confirmationEmailSent], regs')`.
- Observe `ConfirmationEmailSent`: equality-check against
  `confirmationEmailSent`; succeed; queue empties; return
  `(Settled RequiresConfirmation, regs')`.

The chunked path collapses both steps to one `applyEvents`
invocation returning `(RequiresConfirmation, regs')` directly.


## 5. Composition under library-side chain expansion

The naïve composition strategy is wrong on multi-event edges.
Given two transducers T1, T2 and an edge `e1` in T1 with
`output = [o1, o2]`, the naïve composite edge from `(s1, s2)`
would have `output = [substOut o1, substOut o2]`. But: T2 *steps*
on `o1` from `s2`, transitioning to some `s2'`, and must then
step on `o2` from `s2'` — not from `s2`. T2's state changes
between mid-symbols.

EP-19 resolves this with **library-side chain expansion**.
`composeEdge` enumerates every length-N path through T2, threading
the T2 vertex from one consumed mid event to the next, then collapses
each complete path into one composite edge. The composite vertex type
is unchanged and no synthetic vertices leak.

The collapsed edge must also preserve T2's register snapshots. Each
partial path therefore carries a typed, newest-first environment of
T2 writes accumulated by earlier mid events. Before adding the next
T2 edge, composition rewrites every register read in its substituted
guard, update, and outputs through that environment. The environment
contains no T1 writes: every T1 mid output is evaluated from T1's
pre-update snapshot. At final evaluation, `runUpdate` evaluates all
right-hand sides from the composite edge's entry snapshot and applies
writes left-to-right, so the environment inlining recreates the
sequential per-event snapshots and the last repeated T2 write wins.

Implementation sketch (in `Keiki.Composition.composeEdge`):

```haskell
stepPath path mid e2 =
  let guard'  = applyEnvPred path.env (substPred (guard e2) mid)
      update' = applyEnvUpdate path.env (substUpdate (update e2) mid)
      output' = map (applyEnvOut path.env . (`substOut` mid)) (output e2)
      env'    = pendingWrites update' ++ path.env
  in path
       { guard = PAnd path.guard guard'
       , update = UCombine path.update update'
       , output = path.output ++ output'
       , env = env'
       , end = target e2
       }
```

The `expandChain` recursion threads T2's state through each
mid-symbol. Length-0 (`output e1 == []`) returns `([], s2)` —
T2 does not step. Length-1 returns `([substOut o1 (...)], s2')`
where `s2'` is T2's target after stepping on `o1`. Length-N
recursively expands both the vertex path and symbolic write
environment.

This strategy keeps `compose` total: no composition fails because
of multi-event-edge shape. The library absorbs the cost of
making composition closed under the GSM property.

Audit also the alternative-composition arms `liftLOutAlt` and
`liftROutAlt` (shipped after EP-19's original draft) — they
need the same expansion treatment.


## 6. Mermaid label rendering

`Keiki.Render.Mermaid` produces diagrams from `SymTransducer`.
The `edgeOutputName` function (line 529-530 on master) needs a
strategy for length-2+ edges. Three candidates were considered:

(a) Inline separator: `cmd / e1; e2` — readable for length-2.
(b) Multi-line via Mermaid `<br/>` syntax: keeps long lists
    readable.
(c) Synthetic anonymous intermediate nodes — diverges from the
    user's `Vertex` enum.

**Decision: length-2 uses `; ` separator; length-3+ uses `<br/>`
multi-line.** Length-0 keeps today's `cmd /` (ε-edge); length-1
keeps today's `cmd / e1`.

```
cmd / e1                    -- length-1 (today)
cmd / e1; e2                -- length-2
cmd / e1<br/>e2<br/>e3      -- length-3+
```

Rationale: keeps the common case (length-1, length-2) compact
without exploding the diagram on rare length-3+ commands;
deterministic switchover (renders are reproducible); avoids the
anonymous-intermediate-node strategy that would diverge from the
user's `Vertex` enum (MasterPlan #7 dimension-2 concern).


## 7. What's preserved

The widening is *additive* in the sense that the existing pure-core
contracts are preserved for length-0/1 edges:

- `solveOutput :: OutTerm rs ci co -> RegFile rs -> co -> Maybe ci`
  is unchanged — it walks one `OutTerm` and is invoked per-element
  by the new `applyEvent`.
- Per-edge guard evaluation is unchanged. The guard fires once per
  edge attempt, before any output emission.
- `(Bounded, Enum, Show)` on the user's vertex enum still drive
  `checkHiddenInputs`'s vertex enumeration.
- The `Composite` machinery in `Keiki.Composition` (the
  pair-of-state encoding) is unchanged at the type level; it
  threads composite states through `expandChain` internally.
- `applyEvents`'s public signature (`(s, RegFile rs) -> [co] ->
  Maybe (s, RegFile rs)`) is unchanged. Only its implementation
  widens to properly handle length-2+ chunks via `InFlight`.


## 8. What's retired

EP-20's shipped surface is removed in the same change, per the
EP-19 plan's Decision Log entry "EP-20 surface — full removal in
the same change". Specifically:

- `Keiki.Decider.toMultiDecider`, `DriverConfig`,
  `chainAdvanceCommand`, and the chain-replay path inside
  `Decider.evolve`. The widened `decide` returns the full `[e]`
  directly; the façade has no remaining job.
- `Keiki.Builder.chainTo`, the `peChain` snoc-list machinery, and
  `EdgeListAcc { elaMain, elaChain }`. With multi-`emit` legal in
  one block, `chainTo`'s motivating use case collapses; the
  builder reverts to a single `[Edge]` accumulator.
- jitsurei's `userRegDriverConfig`, `userRegChained`, and
  `loanAppChained`. Aggregates declare multi-event edges directly
  in their canonical builder form.
- The EP-20-aligned test specs:
  `test/Keiki/DeciderMultiSpec.hs`,
  `jitsurei/test/Jitsurei/UserRegistrationMultiSpec.hs`,
  `UserRegistrationChainedSpec.hs`,
  `LoanApplicationMultiSpec.hs`,
  `LoanApplicationChainedSpec.hs`. Their purpose folds into the
  widened-`decide` assertions in `DeciderSpec` and the new
  `*GSMSpec` files.

The two retirement sections (Decider + Builder) reference each
other in the docstrings: the Builder note explains "use multiple
`emit` calls in one `onCmd` block"; the Decider note explains
"`decide` returns the full event list directly".


## 9. What changes

Operator-by-operator:

- `omega :: ... -> [co]` — returns the evaluated list of events
  in declaration order. The list is `[]` for an ε-edge,
  length-1 for a letter edge, length-N for a multi-event edge.
- `applyEvent :: ... -> InFlight s co -> RegFile rs -> co ->
  Maybe (InFlight s co, RegFile rs)` — operates on the wrapped
  state. See §4 for the two arms.
- `applyEvents :: ... -> (s, RegFile rs) -> [co] -> Maybe (s,
  RegFile rs)` — signature unchanged; implementation widened
  to fold over `InFlight` and assert `Settled` at end.
- `step :: ... -> ci -> Maybe (s, RegFile rs, [co])` — inner
  `Maybe co` becomes `[co]`.
- `checkHiddenInputs` — walks the edge's `output` list as a
  whole. For each `InCtor` referenced by any `OPack` in the
  list, computes the union of slots visited across all `OPack`s
  naming that `InCtor`; flags any unrecovered slots.
- `Keiki.Composition.composeEdge` (and the alternative-arms
  `liftLOutAlt`, `liftROutAlt`) — implements library-side
  chain expansion per §5.
- `Keiki.Decider.decide` — directly returns `omega`'s `[co]`.
- `Keiki.Decider.evolve` — letter case (single-event edges).
- `Keiki.Decider.evolveStreaming` — new field; multi-event
  chunked replay via `InFlight`.
- `Keiki.Builder.peOutput` — widens to a list snoc-accumulator;
  `emit` appends rather than sets; multiple `emit`s in one block
  produce a multi-event edge.
- `Keiki.Profunctor.firstEdge`, `rewriteEdge*` — `fmap` over
  `Maybe` becomes `fmap` over `[]` (same syntax, list semantics).
- `Keiki.Render.Mermaid.edgeOutputName` — length-based label
  switchover per §6.


## 10. What's deferred

**Conditional output lists** — where the list shape depends on
the input value — are out of scope. Aggregates that need
conditional emission (e.g., a `syncImportedProperty` command that
emits a different number of events depending on which fields
changed) express each conditional event as a separate edge with
a disjoint guard, not as a runtime-conditional `[OutTerm]`.

Rationale: keeping `output :: [OutTerm rs ci co]` a *static* list
preserves per-edge `checkHiddenInputs` decidability and keeps
the composition expansion well-defined. Conditional emission via
guards is the existing pattern and remains correct.


---

## References

- ExecPlan: `docs/plans/19-multi-event-commands-via-edge-output-widening-gsm-expansion.md`
- MasterPlan parent: `docs/masterplans/7-multi-event-command-support-gsm-widening-vs-state-refinement-ergonomics.md`
- Parent research (three-approach comparison):
  `docs/research/multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md`
- Predecessor research:
  `docs/research/multi-decider-via-state-refinement.md` (Approach 1
  in detail; basis of EP-20's shipped surface).
- Synthesis baseline:
  `docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`
