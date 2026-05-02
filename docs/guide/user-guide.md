# keiki User Guide

This guide is the action-oriented companion to the conceptual
foundations. It walks through authoring an aggregate with
`Keiki.Builder`, running it, deriving the standard façades
(`Decider`, `Acceptor`), composing transducers, and opting in to
the symbolic analyses. The glossary at the end defines every
keiki-specific and automata-theory term used along the way.

If you have not read the foundations yet, the recommended path is:

1. `docs/foundations/02-event-sourcing-and-the-decider.md` — the
   `decide` / `evolve` shape this library is mechanically deriving.
2. `docs/foundations/03-finite-automata-and-transducers.md` — what an
   FST is and why edges look the way they do.
3. `docs/foundations/05-data-carrying-alphabets.md` — predicates
   instead of enumerated symbols, register files, the
   symbolic-register transducer.

Then this guide.

---

## 1. Prerequisites

A keiki aggregate module needs a small set of GHC extensions and
imports. The minimum:

```haskell
{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE DeriveGeneric       #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE QualifiedDo         #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE TypeApplications    #-}

import           Keiki.Core
import qualified Keiki.Builder       as B
import           Keiki.Builder       ((.=))
import           Keiki.Generics      (emptyRegFile)
import           Keiki.Generics.TH   (deriveAggregateCtors, deriveWireCtors, deriveView)
```

Why each extension:

| Extension | What it lets you write |
|---|---|
| `BlockArguments` | `B.from V do … ` without parens around the `do` |
| `DataKinds` | The promoted slot list `'[ '("email", Text), … ]` |
| `DeriveGeneric` | Lets `deriveAggregateCtors` / `deriveWireCtors` reflect on payload records |
| `GADTs` | The B-view singletons emitted by `deriveView` |
| `OverloadedLabels` | `#email` resolves to an `IndexN "email" rs r` |
| `OverloadedRecordDot` | `d.email` resolves to an input projection via `PayloadProj` |
| `QualifiedDo` | `B.do { … }` desugars to `Keiki.Builder.>>=` (the indexed bind) |
| `TemplateHaskell` | The TH splices that generate per-ctor helpers |
| `TypeApplications` | `slot @"email"` pins the slot name |

**Importing the operator unqualified is not optional.** `(B..=)` is
unreadable; `import Keiki.Builder ((.=))` is the canonical form.

---

## 2. Quick start: a one-edge aggregate

The smallest useful aggregate. Two control vertices, one command,
one event. Compiles and runs.

```haskell
-- 1. Domain types.
data SendEmailData = SendEmailData
  { recipient :: Text, subject :: Text, at :: UTCTime }
  deriving (Eq, Show, Generic)
data EmailCmd = SendEmail SendEmailData
  deriving (Eq, Show, Generic)

data EmailSentData = EmailSentData
  { recipient :: Text, subject :: Text, at :: UTCTime }
  deriving (Eq, Show, Generic)
data EmailEvent = EmailSent EmailSentData
  deriving (Eq, Show, Generic)

-- 2. Register file (the data the transducer remembers).
type EmailRegs =
  '[ '("emailRecipient", Text)
   , '("emailSubject",   Text)
   , '("emailSentAt",    UTCTime)
   ]

-- 3. Control vertices.
data EmailVertex = EmailPending | EmailSentVertex
  deriving (Eq, Show, Enum, Bounded)

-- 4. TH-derived helpers.
$(deriveAggregateCtors ''EmailCmd ''EmailRegs
    [ ("SendEmail", "SendEmail") ])

$(deriveWireCtors ''EmailEvent
    [ ("EmailSent", "EmailSent") ])

-- 5. The transducer.
emailDelivery
  :: SymTransducer (HsPred EmailRegs EmailCmd)
                   EmailRegs EmailVertex EmailCmd EmailEvent
emailDelivery = B.buildTransducer EmailPending emptyRegFile
                  (\case EmailSentVertex -> True; _ -> False) do
  B.from EmailPending do
    B.onCmd inCtorSendEmail $ \d -> B.do
      B.slot @"emailRecipient" .= d.recipient
      B.slot @"emailSubject"   .= d.subject
      B.slot @"emailSentAt"    .= d.at
      B.emit wireEmailSent EmailSentTermFields
        { recipient = d.recipient
        , subject   = d.subject
        , at        = d.at
        }
      B.goto EmailSentVertex
```

That's the whole aggregate. Read it top to bottom: domain types,
slot list, vertex enum, two TH splices, and one builder block. The
`onCmd` body reads like a state-machine description.

The next sections walk through every line of the builder block in
detail.

---

## 3. The four-layer authoring model

Each keiki aggregate has four layers, each with its own surface:

```
┌────────────────────────────────────────┐
│ buildTransducer  — top-level entry     │   plain Monad  (Prelude.do)
├────────────────────────────────────────┤
│ from V do …      — group by vertex     │   plain Monad  (Prelude.do)
├────────────────────────────────────────┤
│ onCmd / onEpsilon do …  — one edge     │   plain Monad  (Prelude.do)
├────────────────────────────────────────┤
│ slot @… .= …            — edge body    │   indexed Monad (B.do)
│ emit / requireEq / goto                │
└────────────────────────────────────────┘
```

The innermost layer is *indexed* — the type-level slot-set written
so far is part of every step's type. Everything else is a plain
`Monad`. Practically: use `Prelude.do` for the outer three layers
and `B.do` for the edge body.

### 3.1 `buildTransducer`

The entry point. Takes the initial vertex, the initial register
file, a finality predicate, and a `VertexBuilder` block:

```haskell
buildTransducer
  :: (Bounded v, Enum v, Eq v, Show v)
  => v                            -- initial vertex
  -> RegFile rs                   -- initial register file
  -> (v -> Bool)                  -- isFinal predicate
  -> VertexBuilder rs ci co v ()
  -> SymTransducer (HsPred rs ci) rs v ci co
```

A vertex not mentioned in any `from` block defaults to terminal
(`[]` outgoing edges). To assert "this vertex is intentionally
terminal" without declaring edges, write
`B.from V (Prelude.pure ())`.

`emptyRegFile` (from `Keiki.Generics`) gives an initial register
file where every slot is bound to a deferred `"uninit: <slot>"`
error — reading an uninitialised slot crashes with a targeted
message instead of returning `undefined` silently.

### 3.2 `B.from V do …`

Groups the outgoing edges of one source vertex. The block contains
`onCmd` / `onEpsilon` calls. Each call adds one edge to the
vertex's outgoing list.

```haskell
B.from PotentialCustomer do
  B.onCmd inCtorStart $ \d -> B.do … 
  B.onCmd inCtorContinue $ \_ -> B.do … 
```

### 3.3 `onCmd` and `onEpsilon`

Two flavours of edge:

- **`onCmd`** — the edge fires on a specific input constructor.
  The first argument is an `InCtor` (one of the `inCtor<Short>`
  values produced by `deriveAggregateCtors`); the body receives a
  `PayloadProj` handle so you can write `d.fieldName` to project
  the input's fields. The guard starts as `matchInCtor ic`.
- **`onEpsilon`** — the edge fires without consuming an input
  constructor (the ε-edge). The body receives no payload handle.
  The guard starts as `PTop` and any `requireEq` / `requireGuard`
  conjuncts narrow it.

```haskell
B.onCmd inCtorStart $ \d -> B.do            -- d :: PayloadProj rs ci ifs
  B.slot @"email" .= d.email                -- input field projection
  B.goto Registering

B.onEpsilon $ B.do                          -- no payload handle
  B.requireEq #x #y                         -- conjunct an Eq guard
  B.goto OtherVertex
```

### 3.4 The edge body

Inside `B.do { … }`, the available operations:

| Operation | Effect on the partial edge |
|---|---|
| `slot @"name" .= term` | Append a register write to the update |
| `requireEq a b` | Conjoin `a .== b` to the guard |
| `requireGuard p` | Conjoin an arbitrary `HsPred` to the guard |
| `emit wc rec` | Set the output to a packed event |
| `emitWith ic wc rec` | Same, supplying `InCtor` explicitly |
| `noEmit` | Mark explicit ε-output (default if no `emit`) |
| `goto V` | Set the target vertex (required exactly once) |

The order doesn't matter for correctness — the builder folds them
into one `Edge` value at finalize time — but the conventional
reading order is `requireEq` → register writes → `emit` → `goto`.

#### Slot writes

`slot @"name"` is a `IndexN "name" rs r` value tagged at the type
level with the slot name. `(.=)` writes a `Term` to the indexed
slot, and the slot name is added to a phantom `[Symbol]` index on
the indexed monad. **Writing twice to the same slot fails to
compile** — the `Disjoint` constraint on `(.=)` raises a
`TypeError` naming the duplicated slot.

#### Terms — what goes on the right of `.=` and inside `emit`

A `Term rs ci r` is a small AST, not a Haskell function. The
constructors:

| Term | Smart constructor | Meaning |
|---|---|---|
| `TLit r` | `lit r` | A literal value |
| `TReg ix` | `proj ix` or `#name` | Read register slot |
| `TInpCtorField ic ix` | `inpCtor ic ix`, or `d.fieldName` | Read input ctor's field |
| `TApp1 f t` / `TApp2 f a b` | (no helper) | Apply opaque Haskell fn (escape hatch) |

In an `onCmd` body the `d.fieldName` form is the most readable.
For register reads, `#name` is the OverloadedLabels form (resolves
to `proj` of an `IndexN "name" rs r`).

#### `emit` — two forms

The TH splice `deriveWireCtors` emits, for each event constructor,
a paired `wire<Short>` value and a `<Ctor>TermFields` record. The
record shape mirrors the event payload's field names but its
fields are `Term`-typed. Use the record form by default:

```haskell
B.emit wireRegistrationStarted RegistrationStartedTermFields
  { email       = d.email
  , confirmCode = d.confirmCode
  , at          = d.at
  }
```

The lower-level operator form is also accepted (same overload via
`ToOutFields`), useful for ad-hoc cases:

```haskell
B.emit wireEmailSent (d.recipient *: d.subject *: d.at *: B.oNil)
```

Inside `onEpsilon` (no `InCtor` is bound), `emit` raises a
finalize-time error directing you to `emitWith ic wc rec`.

#### `goto` and termination

Every edge body must call `B.goto V` exactly once. Missing or
duplicated `goto` is caught at finalize time (when
`buildTransducer` evaluates the builder) with a runtime error
naming the source vertex and edge index. **This is one of the few
errors caught at runtime rather than compile time** — if you
forget a `goto` in a deeply nested case, expect to see the message
when the module first evaluates `buildTransducer`.

### 3.5 The `B.do` vs `Prelude.do` distinction

```haskell
emailDelivery = B.buildTransducer … do            -- VertexBuilder    → Prelude.do
  B.from EmailPending do                          -- EdgeListBuilder  → Prelude.do
    B.onCmd inCtorSendEmail $ \d -> B.do          -- EdgeBuilder      → B.do
      B.slot @"emailRecipient" .= d.recipient
      B.emit wireEmailSent …
      B.goto EmailSentVertex
```

If you accidentally use `B.do` at the outer layers, you'll get a
type error about `EdgeBuilder`'s indexed bind not matching the
plain `VertexBuilder` shape. If you use `Prelude.do` inside an
edge body, the slot-write static check disappears (each `(.=)`
typechecks alone but duplicates are no longer flagged).

---

## 4. The TH derivations

Three splices replace what would otherwise be ~14 hand-written
declarations per aggregate.

### 4.1 `deriveAggregateCtors ''Cmd ''Regs [ ("Ctor", "Short"), … ]`

For each entry `(ConstructorName, ShortName)`, emits three
top-level declarations:

| Declaration | Type | Use |
|---|---|---|
| `inCtor<Short>` | `InCtor Cmd ifs` | Pass to `B.onCmd` |
| `inp<Short> :: HasIndexN n ifs r => IndexN n ifs r -> Term rs ci r` | helper | Hand-written `inp<Short> #fieldName` (rare — `d.fieldName` is preferred) |
| `is<Short> :: HsPred rs ci` | predicate | Hand-written guard expression: `requireGuard isStart` etc. |

Singleton (no-payload) constructors get `inCtor<Short>` and
`is<Short>` only — `inp<Short>` is omitted because `Index '[]` is
uninhabited.

### 4.2 `deriveWireCtors ''Event [ ("Ctor", "Short"), … ]`

For each entry, emits:

| Declaration | Type | Use |
|---|---|---|
| `wire<Short>` | `WireCtor Event fs` | First arg of `B.emit` |
| `<Ctor>TermFields rs ci` | record | Second arg of `B.emit` (field-keyed form) |

The record's field names are the event payload's field names; its
field types are `Term rs ci <FieldType>`. So inside an edge body
you can write:

```haskell
B.emit wireRegistrationStarted RegistrationStartedTermFields
  { email       = d.email          -- Term rs ci Text
  , confirmCode = d.confirmCode    -- Term rs ci Text
  , at          = d.at             -- Term rs ci UTCTime
  }
```

A wrong-field-order or missing-field bug becomes a compile error.

### 4.3 `deriveView ''Vertex ''Regs "SVertex" "View" "view" [ … ]`

Emits the **B-presentation view** — a per-vertex projection that
exposes only the slots the vertex actually uses:

| Output | Shape |
|---|---|
| `data SVertex (v :: Vertex) where SV1 :: SVertex 'V1; …` | singletons GADT |
| `data View (v :: Vertex) where V1V :: ... -> View 'V1; …` | per-vertex record (live slots only) |
| `view :: SVertex v -> RegFile rs -> View v` | the projection |

You can then pattern-match on `view SConfirmed regs` and the
record selectors are guaranteed to be live slots. The view is
**opt-in** — the transducer doesn't reference it; consumer code
(serialisers, UI) does.

---

## 5. Running a transducer

Once `buildTransducer` returns a `SymTransducer`, the runtime
operations are in `Keiki.Core`:

| Function | Type | What it does |
|---|---|---|
| `delta t s regs ci` | `Maybe (s, RegFile rs)` | Forward step on a command (control + register update) |
| `omega t s regs ci` | `Maybe co` | The event emitted by the firing edge (or `Nothing` for ε) |
| `step t s regs ci` | `Maybe ((s, RegFile rs), Maybe co)` | `delta` and `omega` paired |
| `applyEvent t s regs co` | `Maybe (s, RegFile rs)` | The inverse: replay an event (used by `evolve`) |
| `reconstitute t events` | `Maybe (s, RegFile rs)` | Fold `applyEvent` over an event log |

`delta`, `omega`, and `applyEvent` use **concrete predicate
evaluation** (`evalPred`) — there is no solver in this path.

### 5.1 The Decider façade

Most users coming from event sourcing want the
Chassaing-shape `Decider` record. `Keiki.Decider.toDecider`
projects a `SymTransducer` onto:

```haskell
data Decider c e s = Decider
  { decide       :: c -> s -> [e]   -- via omega (singleton or [])
  , evolve       :: s -> e -> s     -- via applyEvent (defensive no-op on Nothing)
  , initialState :: s               -- (initial t, initialRegs t)
  , isTerminal   :: s -> Bool       -- isFinal t
  }
```

Two semantic gaps documented at `toDecider`'s haddock:

1. **ε-edges**. `decide` returns `[]` for an input that fires an
   ε-edge, so `evolve` is a no-op and the state doesn't transition
   through the façade. Use `delta` directly when ε matters.
2. **Singleton lift**. `omega` is single-event; `decide` is always
   `[]` or a singleton. Multi-event commands need a future
   `MultiDecider`.

### 5.2 The Acceptor façade

`Keiki.Acceptor` projects a transducer onto a minimal
`Acceptor a s` over either alphabet:

| Function | Alphabet | Step |
|---|---|---|
| `inputAcceptor t` | command (`ci`) | `delta` |
| `outputAcceptor t` | event (`co`) | `applyEvent` |

Useful for "is this event log accepted by the aggregate?" and
"can this command sequence reach a terminal vertex?" questions.

```haskell
accepts (outputAcceptor userReg) [event1, event2, …]   -- :: Bool
runAcceptor (inputAcceptor userReg) [cmd1, cmd2]       -- :: Maybe (Vertex, RegFile)
```

---

## 6. Composition

`Keiki.Composition.compose t1 t2` builds the sequential composite
of two transducers when `t1`'s output alphabet equals `t2`'s input
alphabet. The composite's vertex type is `Composite s1 s2`, its
register file is `Append rs1 rs2`, and the input/output alphabets
are `t1`'s input and `t2`'s output respectively.

Preconditions (enforced or documented):

- `Disjoint (Names rs1) (Names rs2)` — the two register files
  must not share slot names. Compile-time `TypeError` if violated.
- `t1` outputs use `OPack` (the only output constructor at
  present, so this is automatic).
- `t2`'s mid-side guards are structural (no `TApp1`/`TApp2`
  escape hatches over the input). The composition substitutes
  `t1`'s output term into `t2`'s mid-side reads; opaque Haskell
  functions can't be substituted through.

Single-valuedness is preserved by composition (proof sketch in
`docs/research/composition-combinators-design.md` §"Soundness of
single-valuedness preservation").

---

## 7. Symbolic analysis

Importing `Keiki.Symbolic` opts into the SBV-backed `BoolAlg`
instance for guard analysis. The headline use case:

```haskell
import Keiki.Symbolic (withSymPred, isSingleValuedSym)

spec_singleValued :: Bool
spec_singleValued = isSingleValuedSym (withSymPred userReg)
-- True iff no two outgoing edges of any vertex can fire on the
-- same input. Decided by z3 at call time.
```

What this costs at runtime is summarised in
`docs/research/symbolic-analysis-and-runtime-implications.md`:

- A hard cabal dep on `sbv`.
- A z3 binary in `PATH` at the call site (test/CI machine).
- ~10ms per solver call warm.
- **Not** in the per-event hot path. `delta`/`omega`/`applyEvent`
  use concrete `evalPred`. Solver dispatch is for analysis only.

The other exports:

| Export | What it does |
|---|---|
| `symIsBot p` | Is the predicate unsatisfiable? |
| `symSat p` | Is there any satisfying assignment? (placeholder witness) |
| `symSatExt p` | Same, with concrete `(RegFile rs, ci)` witness reconstruction |
| `withSymPred t` | Re-tag a transducer's edge guards from `HsPred` to `SymPred` |
| `isSingleValuedSym t` | All-pairs `isBot (g1 \`conj\` g2)` over each vertex's edges |
| `Sym a` typeclass | Curated set: `Bool`, `Int`, `Integer`, `Text`, `UTCTime` |

---

## 8. Common errors

A non-exhaustive list of the errors a real authoring session hits.

### Compile-time

**Duplicate slot write.**

```
• Slot "email" written twice in the same edge body
```

The `Disjoint '[name] w` constraint on `(.=)` fires. Fix: drop
one of the writes, or chain via `requireEq` if you're asserting
equality rather than writing.

**Slot type mismatch.**

```
• Couldn't match type ‘UTCTime’ with ‘Text’
  arising from a use of ‘.=’
```

The slot's declared type and the term's type disagree. Check the
register-file slot list against the right-hand-side term.

**Missing TH-derived helper.**

```
• Variable not in scope: inCtorStart
```

Usually means `deriveAggregateCtors` was not spliced for that
constructor, or the spec list's first column didn't match the
constructor's name exactly. The splice's spec is
`(ConstructorName, ShortName)` — the suffix
`inCtor<ShortName>` / `inp<ShortName>` / `is<ShortName>` is
emitted.

**`#fieldName` ambiguity inside edge bodies.**

If you see `Ambiguous use of overloaded label 'foo'`, prefer
`slot @"foo"` for register writes and `d.foo` for input
projection. The `#foo` form works for register reads against an
inferable `IndexN` but GHC sometimes can't commit when the
context is a polymorphic builder.

### Build-time (when `buildTransducer` evaluates)

**Missing `goto`.**

```
Keiki.Builder: edge #2 from RequiresConfirmation: goto missing.
Each onCmd/onEpsilon body must end with exactly one goto V.
```

Add a `B.goto V` to the body.

**Multiple `goto`s.**

```
Keiki.Builder: edge #1 from Confirmed: goto called more than once.
```

Each edge body must commit to one target.

**`emit` inside `onEpsilon` without `emitWith`.**

```
Keiki.Builder.emit: no enclosing onCmd pinned an InCtor. …
```

Use `emitWith ic wc rec` or move the `emit` inside an `onCmd`.

### Hidden-input warnings

`Keiki.Core.checkHiddenInputs` walks a transducer and flags edges
where the update or guard reads an input field that doesn't
appear in the output term. Such edges can't be replayed from the
event alone — `applyEvent` will return `Nothing` even on
well-formed events.

The warning is informational at the moment; treat it as a schema
fix-up signal. The User Registration aggregate's
`AccountConfirmedData` schema in `docs/foundations/04` walks
through one such fix.

---

## 9. Authoring loop — what to keep on screen

When writing a new aggregate, the high-traffic references:

1. **An existing aggregate** as a template.
   `src/Keiki/Examples/EmailDelivery.hs` is the smallest;
   `src/Keiki/Examples/UserRegistration.hs` is the canonical
   five-vertex / four-command example.
2. **`Keiki.Builder`'s haddock.** The module header has the
   worked example inline and lists every export with a one-line
   summary.
3. **`Keiki.Core`'s exported helpers** for terms / predicates.
   `proj`, `lit`, `inpCtor`, `(.==)` are the constructors you
   reach for inside `requireEq`/`requireGuard` blocks.
4. **The glossary below** when you hit a term you don't recognise.

---

## 10. Glossary

Every keiki-, automata-, or event-sourcing-specific term used in
this guide and in the haddocks.

### 10.1 Event sourcing and DDD vocabulary

| Term | Definition |
|---|---|
| **Aggregate** | A consistency boundary in DDD; in keiki, one transducer. State changes happen one command at a time and are recorded as an event log. |
| **Command** | An external input requesting a state change. Type: `ci`. May be rejected (no satisfying edge fires). |
| **Event** | A record of a state change that *did* happen. Type: `co`. Append-only; replayable. |
| **Decider** | A four-field record (`decide`/`evolve`/`initialState`/`isTerminal`) introduced by Jérémie Chassaing. The naive functional model of an event-sourced aggregate. keiki derives it via `toDecider`. |
| **Decide** | Function `c -> s -> [e]` mapping a command and current state to the events to emit. In keiki, derived from `omega`. |
| **Evolve / apply** | Function `s -> e -> s` replaying one event onto the state. In keiki, derived from `applyEvent`. |
| **Replay / reconstitute** | Folding `evolve`/`applyEvent` over an event log to recover the current state. |
| **Projection** | A read-side view derived from the event log. Not the same as the per-vertex B-view (which projects the live slots out of the register file). |
| **Saga / process manager** | A long-running coordinator of multiple aggregates. Modelled in keiki as a transducer whose input is an event alphabet and whose output is a command alphabet — an orchestrator. |
| **ε-edge / epsilon edge / silent transition** | A transition that emits no event. Output is `Nothing`. Through the `Decider` façade, fires but produces `[]` events. |

### 10.2 Automata theory

| Term | Definition |
|---|---|
| **Finite-State Transducer (FST)** | An automaton with input *and* output alphabets. Each transition has a label `(input, output)` instead of just `input`. |
| **Mealy machine** | An FST where every transition has exactly one output symbol. Equivalent to a deterministic FST with no ε-output. |
| **Symbolic Finite Transducer (SFT)** | An FST whose transitions are labelled by *predicates* over the input domain (not enumerated symbols). The domain may be infinite. Decidability hinges on the predicate algebra having decidable satisfiability. |
| **Streaming String Transducer (SST)** | A deterministic transducer with a finite set of typed registers updated under a copyless discipline. Captures the MSO-definable string transformations. The structural inspiration for keiki's register file. |
| **Register automaton** | Finite control + a finite tuple of registers holding values from an infinite domain, with equality-only operations. |
| **Symbolic-register transducer** | keiki's hybrid: SFT predicates on guards + SST-style register file. The shape of `SymTransducer`. |
| **Vertex** | A control state. Members of the `s` type parameter. Finite (`Bounded`/`Enum`). |
| **Edge / transition** | One outgoing arrow from a vertex. Carries a guard, an update, an output, and a target vertex. |
| **δ (delta)** | The transition function: `state × input → state`. In keiki, `delta :: s -> RegFile rs -> ci -> Maybe (s, RegFile rs)`. |
| **ω (omega)** | The output function: `state × input → output`. In keiki, `omega :: s -> RegFile rs -> ci -> Maybe co`. |
| **Acceptor** | A specialisation of an FST that ignores output and answers "does this input belong to the language?". |
| **Final / accepting state** | A state in which the run is allowed to terminate. `isFinal` in keiki. |
| **Single-valued** | At every reachable state, at most one outgoing edge fires for any given input. Single-valued SFTs have decidable equivalence (Veanes 2012); keiki targets this regime. |
| **Copyless update** | Restriction that no register's value is duplicated to two registers in a single transition. Keeps SST equivalence decidable. |
| **Single-use register** | Restriction (Bojańczyk) that a register is consumed when read. Recovers decidable equivalence for register automata. Not enforced in keiki at present but a useful sanity rail. |

### 10.3 keiki types and machinery

| Term | Definition |
|---|---|
| **`SymTransducer phi rs s ci co`** | The library's central type. `phi` is the predicate carrier (`HsPred` for v1, `SymPred` for v2); `rs` is the slot list; `s` the vertex; `ci`/`co` the command/event types. |
| **Slot** | A `(Symbol, Type)` pair: a register's name and its value type. |
| **`RegFile rs`** | A typed heterogeneous tuple indexed by a slot list. The data the transducer remembers between transitions. |
| **`Index rs r`** | A position into a register file pointing at a slot of type `r`. `ZIdx` is the head; `SIdx` the recursive constructor. |
| **`IndexN s rs r`** | A slot-name-tagged index. The `s :: Symbol` parameter pins the slot's name in the type, which is what makes the static disjoint-targets check on `(.=)` possible. |
| **`Term rs ci r`** | A small AST for expressions over registers and the input. Constructors: `TLit`, `TReg`, `TInpCtorField`, `TApp1`, `TApp2`. Smart constructors: `lit`, `proj`, `inpCtor`. |
| **`HsPred rs ci`** | The v1 predicate carrier. Constructors: `PTop`, `PBot`, `PAnd`, `POr`, `PNot`, `PEq`, `PInCtor`. Smart constructors: `(.==)`, `matchInCtor`. |
| **`SymPred rs ci`** | The v2 predicate carrier (a newtype over `HsPred`). Same constructors; the difference is the `BoolAlg` instance, which routes `sat`/`isBot` through SBV instead of returning placeholders. |
| **`BoolAlg phi a`** | The effective Boolean algebra typeclass: `top`/`bot`/`conj`/`disj`/`neg`/`models`/`sat`/`isBot`. The interface every predicate carrier implements. |
| **`Update rs w ci`** | The register-update language. `UKeep`, `USet`, `UCombine`. The phantom `w :: [Symbol]` index records the slots written so far for the static distinct-targets check. |
| **`combine`** | Concatenate two `Update`s under a `Disjoint` constraint. The constraint enforces no register is written by both halves. |
| **`InCtor ci ifs`** | Reified evidence that `ci`'s value can be matched against a specific constructor and its payload reassembled as a `RegFile ifs`. Carries the constructor's name (`icName`), a matcher (`icMatch`), and a builder (`icBuild`). Produced by `deriveAggregateCtors`. |
| **`WireCtor co fs`** | Reified evidence for an event constructor — the dual of `InCtor` for the output side. Carries a builder over a nested-pair tuple. Produced by `deriveWireCtors`. |
| **`OutFields rs ci fs`** | A heterogeneous list of `Term`s, one per event-payload field. Built with `(*:)` / `oNil` or via the TH-emitted `<Ctor>TermFields` record. |
| **`OutTerm rs ci co`** | A packaged output: `OPack ic wc fs`. Holds the input-side `InCtor` (so replay can recover the input), the wire-side `WireCtor`, and the field-term list. |
| **`pack`** | Smart constructor for `OPack`. The argument shape `pack ic wc fs` is what `B.emit` produces under the hood. |
| **`Edge phi rs ci co s`** | One outgoing transition. Fields: `guard`, `update`, `output`, `target`. |
| **`step`** | Forward atomic operation: `(s, RegFile, ci) -> Maybe ((s, RegFile), Maybe co)`. `delta` and `omega` paired. |
| **`applyEvent`** | The inverse step: `(s, RegFile, co) -> Maybe (s, RegFile)`. Used by `reconstitute` and `Decider.evolve`. Mechanically derived from `omega` via `solveOutput`; no per-edge inverse function needed. |
| **`reconstitute`** | Fold `applyEvent` over an event log. The replay path. |
| **`solveOutput`** | The build-time analysis that mechanically derives the inverse of `omega` from each edge's `OutTerm`. The reason `applyEvent` exists at all without hand-written inverses. |
| **`checkHiddenInputs`** | Build-time analysis that flags edges whose update or guard reads an input field not present in the output term. Such edges can't be replayed from the event alone. |
| **`isSingleValuedSym`** | Symbolic single-valuedness check. For each vertex, asks `isBot` of every pairwise conjunction of outgoing-edge guards. Lives in `Keiki.Symbolic`. |
| **`withSymPred`** | Adapter that re-tags every edge guard from `HsPred` to `SymPred`. Lets the SBV-backed `BoolAlg` instance fire without rewriting the aggregate. |
| **B-presentation / B-view** | A per-vertex projection that exposes only the slots live in that vertex. Generated by `deriveView`. Opt-in; the transducer doesn't depend on it. |
| **C foundation** | The symbolic-register transducer as the formalism. The current direction (synthesis doc): "C is the formalism, B is an optional presentation layer." |

### 10.4 Builder-specific terms

| Term | Definition |
|---|---|
| **`VertexBuilder`** | Plain-`Monad` builder that accumulates `(vertex, [edge])` entries. One `from` call per vertex. |
| **`EdgeListBuilder`** | Plain-`Monad` builder for one source vertex's outgoing edges. One `onCmd`/`onEpsilon` call per edge. |
| **`EdgeBuilder`** | Indexed-monad builder for one edge body. Two phantom `[Symbol]` parameters track the slots written so far. |
| **`PartialEdge`** | The growing edge state inside an `EdgeBuilder` body. Internal — exposed only as the type `EdgeBuilder` wraps. |
| **`PayloadProj`** | Opaque handle threaded into an `onCmd` body. Its `HasField` instance translates `d.fieldName` into a `TInpCtorField` term. |
| **`ToOutFields`** | Typeclass that lets `B.emit` accept either a `<Ctor>TermFields` record or a bare `OutFields` value via the same call shape. |
| **`<Ctor>TermFields rs ci`** | TH-emitted record companion to a `WireCtor`. Field names mirror the event payload's; field types are `Term rs ci`. The right-hand argument of `B.emit`. |
| **`buildTransducer`** | Top-level entry. Runs the `VertexBuilder` to produce a `SymTransducer`. |
| **`from V do …`** | Group edges out of vertex `V`. |
| **`onCmd ic body`** | Add an edge guarded by `matchInCtor ic`; `body` runs in `EdgeBuilder` with a `PayloadProj` argument. |
| **`onEpsilon body`** | Add an ε-edge (no `InCtor` match in the guard); `body` runs in `EdgeBuilder` with no payload handle. |
| **`slot @"name"`** | Resolve a `IndexN "name" rs r` for use with `(.=)`. The `TypeApplication` pins the slot name unambiguously. |
| **`(.=)`** | Slot write. `slot @"x" .= term` adds a register-write step to the edge body. Static distinct-targets check via `Disjoint`. |
| **`emit wc rec`** | Set the edge's output. `wc` is a `WireCtor`; `rec` is the field-keyed record (or a bare `OutFields`). The input-side `InCtor` is recovered from the enclosing `onCmd`. |
| **`emitWith ic wc rec`** | Same as `emit` but with an explicit `InCtor`. Required inside `onEpsilon`. |
| **`noEmit`** | Mark the edge as ε-output. Idempotent. |
| **`requireEq a b`** | Conjoin `a .== b` to the edge guard. |
| **`requireGuard p`** | Conjoin an arbitrary `HsPred` to the edge guard. |
| **`goto V`** | Set the edge's target vertex. Required exactly once per body; missing/duplicated `goto` raises a finalize-time error. |

### 10.5 GHC features used

| Feature | Where it shows up |
|---|---|
| **`DataKinds`** | The promoted slot list `'[ '("email", Text), … ]` — `'(,)` is the promoted tuple constructor. |
| **`GADTs`** | `Term`, `Update`, `RegFile`, `OutFields`, the B-view singletons. |
| **`KnownSymbol`** | `slot @"name"` requires the symbol to be statically known. |
| **`OverloadedLabels`** | `#email` resolves to an `IsLabel` instance — for keiki this is `IndexN "email" rs r`. |
| **`OverloadedRecordDot`** | `d.email` resolves to `getField @"email" d`. `PayloadProj`'s `HasField` instance turns this into a `TInpCtorField` term. |
| **`QualifiedDo`** | `B.do { … }` desugars to `B.>>= ` and `B.>>` instead of `Prelude.>>=` / `Prelude.>>`. Lets the indexed `EdgeBuilder` reuse `do`-notation. |
| **`BlockArguments`** | `B.from V do …` instead of `B.from V (do …)`. |
| **`TypeApplications`** | `slot @"name"` pins the symbol parameter of `IndexN`. |
| **`TemplateHaskell`** | The three `derive*` splices. |
| **Indexed monad** | The `EdgeBuilder` is not a `Monad` because the `(>>=)` of a step changes the type-level slot-set. The module exports its own `>>=`/`>>`/`pure`/`return` to make `QualifiedDo` work. |
| **Phantom type** | A type parameter that doesn't appear in any constructor's runtime fields. The slot-set `[Symbol]` index on `EdgeBuilder` is a phantom. |

### 10.6 Symbolic-side terms

| Term | Definition |
|---|---|
| **SBV** | "SMT-Based Verification" — Levent Erkok's Haskell library that compiles symbolic-value Haskell to SMT-LIB and dispatches to a back-end solver. |
| **SMT solver** | A decision procedure for satisfiability modulo theories (linear arithmetic, strings, equality, etc.). z3 is the default. |
| **z3** | Microsoft Research's SMT solver. Required at runtime for `Keiki.Symbolic`'s analyses. Install with `brew install z3` or `apt install z3`. |
| **`Sym a`** | Typeclass for types that have an SBV representation. Curated set: `Bool`, `Int`, `Integer`, `Text`, `UTCTime`. |
| **`SymRep a`** | The SBV-side representation of `a`. Associated type on `Sym`. E.g. `SymRep UTCTime = Integer` (POSIX seconds). |
| **`symSat`** | Symbolic satisfiability check. Returns `Just (placeholder, placeholder)` on a hit, `Nothing` on unsat. |
| **`symIsBot`** | Symbolic emptiness check. `True` iff the predicate is unsatisfiable. |
| **`symSatExt`** | Symbolic sat with concrete witness reconstruction. Requires `ExtractRegFile rs` and `KnownInCtors ci` evidence. |
| **`ExtractRegFile rs`** | Typeclass that materialises a `RegFile rs` from a name-keyed reader. The two instances cover `'[]` and `'(s, t) ': rs`. |
| **`KnownInCtors ci`** | Typeclass enumerating a `ci`'s `InCtor` values for the witness extractor. Hand-written per aggregate (one entry per command constructor). |
| **`unsafePerformIO` + `NOINLINE`** | The wrapping that makes `symSat`/`symIsBot`/`symSatExt` pure. Justified because each query is deterministic for the same predicate and side-effect-free outside the solver process. |

### 10.7 Naming origins

A lot of keiki vocabulary is borrowed from formal-language theory,
event-sourcing literature, or earlier design exploration; the
names carry information once you know where they came from.

#### Borrowed from automata theory

| Name | Where it comes from |
|---|---|
| **slot** | Streaming String Transducers (Alur & Černý, POPL 2011) call the named positions of the register file *slots*. Borrowed because "field" was already taken (record fields on payloads). A slot is a fixed, named position into which a value is written — like a pigeonhole. |
| **register / `RegFile`** | Register Automata (Kaminski & Francez 1994) and SST. By analogy to a CPU register: a small, typed, named cell the automaton can read and write between transitions. |
| **vertex** | Graph theory. Used instead of "state" because keiki's *full* state is the pair `(vertex, RegFile)`; calling the control component "the state" would conflict with that. The control graph is literally a directed graph and "vertex" is the graph-theoretic name for its nodes. |
| **edge** | Same — graph-theoretic name for a directed arrow between vertices. Each edge bundles a guard, an update, an output, and a target. |
| **transducer** | Latin *transducere*, "to lead across". An automaton that *translates* one alphabet to another (input → output) instead of merely accepting or rejecting. The contrast term is *acceptor*, which has no output. |
| **acceptor** | Formal-language theory. The simplest automaton: ingests a sequence, says yes or no based on whether it ends in a final state. keiki's `Acceptor` is the projection that drops the output side of a transducer. |
| **decider** | Jérémie Chassaing's *Functional Event Sourcing Decider*. Chosen because it *decides* which events to emit given a command. keiki's `Decider` façade has the same four-field shape Chassaing publishes. |
| **δ (delta)** | Standard automata-theory notation for the transition function. Reused unchanged in keiki's `delta`. |
| **ω (omega)** | Mealy-machine convention for the output function. Reused in keiki's `omega`. The original Mealy paper used different letters; ω became standard later. |
| **ε-edge / epsilon edge / silent transition** | ε is the empty word in formal-language theory. An edge whose output is "no symbol" is conventionally labelled ε. In keiki, an ε-edge is one whose `output` field is `Nothing`. |
| **single-valued** | SFT literature (Veanes 2012). The transducer's relation is *valued* at most once per input — single-valued — instead of multi-valued. The single-valued case is where SFT equivalence is decidable. |
| **single-use** | Bojańczyk's restriction on register automata (arXiv 1907.10504): each register is *used* (read) at most once per transition, after which it's consumed. Recovers decidable equivalence in the deterministic case. |
| **copyless** | SST restriction (Alur & Černý). No register's content is *copied* to two registers in the same transition — what the rule forbids. The name describes the prohibition. |
| **finite-valued** | Generalisation of single-valued: at most *k* outputs per input for some finite *k*. Equivalence is still decidable (Muscholl & Puppis, ICALP 2019). |
| **EFSM** | Extended Finite-State Machine — finite control extended with an opaque data context. The "extended" part is the data side. keiki's earlier exploration used this shape and rejected it in favour of the symbolic-register transducer. |
| **SFT / SST** | *Symbolic Finite Transducer* (predicates instead of enumerated symbols on transitions) and *Streaming String Transducer* (registers updated under a copyless discipline). keiki's transducer is a hybrid of the two. |
| **carrier** (the `phi` parameter on `BoolAlg`, `SymTransducer`) | Universal algebra. The *carrier set* of an algebraic structure is the underlying set of its elements (e.g. the carrier of a group is its element set). `phi` is the type carrying the predicate values; swapping the carrier (`HsPred` → `SymPred`) swaps the algebra without changing the structure. |
| **predicate algebra / `BoolAlg`** | An *effective Boolean algebra* in the SFT literature: a Boolean algebra (top, bot, ∧, ∨, ¬) whose satisfiability is decidable. "Effective" means the decision procedure exists; without it, no analyses are possible. |

#### Borrowed from event-sourcing vocabulary

| Name | Where it comes from |
|---|---|
| **emit** | Standard event-sourcing verb: an aggregate *emits* events as the record of state changes. Chosen over "produce" / "output" / "yield" because it's the term DDD/ES literature uses. |
| **apply / evolve** | Chassaing's Decider names. `evolve` is the public name; `apply` survives in keiki as `applyEvent` because we're naming the event-replay direction explicitly. |
| **reconstitute** | Event-sourcing term for rebuilding an aggregate's state by folding `apply` over its event log. Sometimes called "rehydrate" in other libraries; keiki uses `reconstitute` because it matches the formal "fold over the language" framing. |
| **aggregate** | DDD (Eric Evans). A consistency boundary: a cluster of objects treated as one for state changes. In keiki, exactly one transducer. |
| **wire** (as in `WireCtor`, `wireFoo`) | "On the wire" — the serialised form an event takes when written to the event log or sent over the network. A `WireCtor` is reified evidence about how an event constructor is laid out for serialisation. The companion `InCtor` is the input side; `WireCtor` is the output (wire) side. |
| **saga / process manager** | Garcia-Molina & Salem's *Sagas* (1987) for the transactional pattern; "process manager" is Hohpe & Woolf's *Enterprise Integration Patterns* term for a long-running orchestrator. Both are modelled in keiki as transducers whose input alphabet is one bounded context's events and whose output is another's commands. |

#### Built locally

| Name | Why this name |
|---|---|
| **`InCtor` / `WireCtor`** | "Ctor" is the conventional Haskell shorthand for "constructor". `InCtor` reifies an *input* (command) constructor; `WireCtor` reifies an *output* (event) constructor for serialisation onto the wire. |
| **`OPack`** | "Output Pack" — an output term *packed* together with its input-side `InCtor` so replay can recover the input from the event alone. The `O` prefix matches `OutFields` / `OutTerm`; the "pack" suffix signals that everything needed for both forward emission and inverse replay is bundled in one constructor. |
| **`OutFields`** | A heterogeneous list of `Term`s, one per *field* of the *output* event's payload record. The name says exactly what it is. |
| **`<Ctor>TermFields`** | TH-emitted record companion to a `WireCtor`. Each field is a `Term` (not a value), so the type literally is *fields-of-Terms*. The leading `<Ctor>` distinguishes the per-event records (`EmailSentTermFields`, `RegistrationStartedTermFields`, …). |
| **`PayloadProj`** | "Payload Projection". Opaque handle threaded into an `onCmd` body that lets you *project* (read) fields out of the input command's *payload* via record-dot syntax (`d.fieldName`). |
| **`SymTransducer`** | "Symbolic-register Transducer". The "Sym" prefix flags the SFT predicate-on-guard heritage; the type is also where the SST-style register file lives. (It was renamed from `Transducer` mid-design when the symbolic surface arrived; some research notes still use the old name.) |
| **`HsPred` / `SymPred`** | The two predicate carriers. `HsPred` = "Haskell predicate" — interpreted by concrete `evalPred`. `SymPred` = "Symbolic predicate" — same constructors, but the `BoolAlg` instance routes through SBV. The names mark *which* `BoolAlg` instance fires, not a difference in shape. |
| **B-view / B-presentation / C-foundation** | Alphabetical labels from the data-carrying-state design exploration: direction **A** was sum-types-with-payloads (rejected); direction **B** was indexed state per vertex; direction **C** was symbolic + register automata. The synthesis ratified "C is the formalism, B is an optional presentation layer." `deriveView` and `Keiki.Examples.UserRegistration.userView` deliver the B presentation; everything else (`SymTransducer`, the term language, the predicates) is C. |
| **`goto`** | The edge body is structurally a procedure that ends with a transfer of control. "goto V" is the most universally familiar name for "set the next program counter to V". Each edge body must call `goto` exactly once. |
| **`from`** | Reads as "edges *from* vertex V". The block lists the outgoing edges of one source vertex. |
| **`onCmd` / `onEpsilon`** | Reads as "*on* this command" / "*on* an epsilon transition" — the trigger that fires the edge. The conventional reading-aloud is "*from* PotentialCustomer, *on* StartRegistration command, …". |
| **`requireEq` / `requireGuard`** | "Require this equality (or this predicate) hold for the edge to fire." Conjoined into the edge guard; the edge fires only when every requirement holds. |
| **`emit` (builder)** | Same verb as the event-sourcing meaning: *emit* an event from this edge. |
| **`withSymPred`** | The "with" prefix is the standard Haskell convention for adapter functions: `withFoo x f` runs `f` in a context where `Foo` is available. `withSymPred t` returns a transducer with its guards re-tagged as `SymPred`s — same content, swapped predicate carrier. |
| **`buildTransducer`** | Top-level entry of the *builder*. The Haskell convention for builder-pattern entry points. |
| **slot, in `slot @"name"`** | Same word as the glossary slot, used as a function. `slot @"x"` resolves to the typed `IndexN "x" rs r` value pointing into the register file's "x" slot. |
| **`deriveAggregateCtors` / `deriveWireCtors` / `deriveView`** | Each splice *derives* a family of declarations. The suffix says what side: aggregate (input/command) ctors, wire (output/event) ctors, or the per-vertex B-view. |
| **`solveOutput`** | The build-time analysis that *solves* for the input given an event by inverting the edge's output term. The name describes the operation: solve the equation `output(input) = event` for `input`. |
| **`checkHiddenInputs`** | Flags edges that read input fields *hidden* from the output — i.e. the input field appears in the update or guard but not in the emitted event. Such reads are *hidden* from replay, hence the name. |
| **`SymPred`'s `Sym`-typeclass curated set** | "Sym" everywhere is short for "symbolic". `Sym a` = "type a has a curated symbolic representation"; `SymRep a` = its symbolic representation type; `symLit` / `symFree` = symbolic-side literal/variable. |

---

## 11. Where to go from here

Each of the four topics below has its own dedicated guide in
this folder. Read those when you hit the topic; they cover the
operational side in depth without re-deriving the basics this
guide already established.

- **Compose two aggregates.** `composition.md`. The smoke test
  `AlertSource ⨾ EmailDelivery` in
  `test/Keiki/CompositionSpec.hs` is the worked example. Formal
  semantics in
  `docs/research/composition-combinators-design.md`.
- **Add symbolic CI.** `symbolic-ci.md`. Wires
  `isSingleValuedSym (withSymPred yourAggregate)` into the test
  suite and z3 onto the CI image. Pairs with
  `docs/research/symbolic-analysis-and-runtime-implications.md`
  for the "what does this cost" reference.
- **Drop down to the AST.** `ast-drop-down.md`. When the builder
  can't express what you need, hand-author `Edge` records against
  `Keiki.Core`. Reference templates: `userRegAST` and
  `emailDeliveryAST` in the example modules.
- **Per-vertex views.** `b-views.md`. `deriveView` emits the
  per-vertex B-view (singletons GADT + View GADT + projection
  function). Consumed from serialisers, UI, or read-side
  projections. Design rationale in
  `docs/research/genview-th-splice-design.md`.

When you find a gap in this guide, the right fix is to file an
issue against this file rather than re-deriving the answer from
scratch. The guide is meant to absorb every recurring "how do I
do X" question.
