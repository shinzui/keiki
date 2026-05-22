# Output invertibility — which events round-trip on replay

keiki reconstitutes an aggregate from its event log without any hand-written inverse
code: it *inverts* each edge's output expression to recover the command that must have
produced the observed event, then re-runs the edge forward. That inversion is mechanical,
and it is **not total** — only certain shapes of output expression can be inverted.

The contract a reader can apply immediately:

> An event round-trips on replay **if and only if** every field of its payload is a
> literal, a register read, or a copy of a field from the *same* command constructor. If
> any payload field applies a Haskell function (`TApp1`/`TApp2`) or does structural
> arithmetic (`TArith`), `solveOutput` returns `Nothing` and that event cannot be replayed
> from the log alone.

This page states the rule, names the symbols that implement it (all in `src/Keiki/Core.hs`),
and gives worked recipes for the "this event stores a derived value" situations that motivate
it. The contract already governs the code today; nothing here asks you to change an aggregate.

---

## 1. The contract, in one sentence

The inverter is `solveOutput` (`src/Keiki/Core.hs`, around line 1039):

```haskell
solveOutput :: OutTerm rs ci co -> RegFile rs -> co -> Maybe ci
```

Given an edge's output expression, the register file *as it was before the edge's update
ran*, and an observed event, it returns `Just command` when it can mechanically recover the
command that produced the event, and `Nothing` when it cannot. The recovery is purely
structural: it walks the event's payload fields in lockstep with the edge's `OutFields`, and
for each field's `Term` it asks "what does this field tell me about the original command?"

`solveOutput` is called on the replay path by `applyEvent` and `applyEventStreaming`
(`src/Keiki/Core.hs`, around lines 882–966), which `reconstitute` folds over an event log. It
is the runtime inverter — *not* a build-time analysis (that is `checkHiddenInputs`, §6).

### How to predict it

Look at each `Term` on the right of a field in the edge's `B.emit`:

- If they are **all** `lit …`, `#slot` / `proj …` register reads, or `d.field` reads of the
  command this `onCmd` matches — the event round-trips.
- If **any** is an opaque application (`TApp1`/`TApp2`) or uses structural arithmetic
  (`.+` / `.-` / `.*`, i.e. `TArith`) — it does not round-trip today.

---

## 2. What inverts today

> This section describes keiki's behavior as of this writing. The sibling plan
> `docs/plans/47-recompute-and-verify-derived-event-outputs-in-solveoutput-replay.md` will
> *relax* it so derived output fields round-trip by being recomputed and verified on replay.
> Until that lands, the rule below is exact.

The per-field accept/reject decision is made by the helper `gatherInpEntries` and its inner
`stepOne` (`src/Keiki/Core.hs`, around lines 1054–1071). The accept/reject list on this page
mirrors `stepOne` verbatim, so a reviewer can diff the two:

```haskell
stepOne (TLit _)                  _val _   = Just []        -- literal: nothing to recover
stepOne (TReg _)                  _val _   = Just []        -- register read: recovered from replayed regs
stepOne (TInpCtorField ic2 ix)    val  ic1
  | icName ic1 == icName ic2 = Just [ByIndex (unsafeCoerce ix) val]  -- field of THIS command ctor
  | otherwise                = Nothing                              -- field of a DIFFERENT ctor
stepOne (TApp1 _ _)               _val _   = Nothing        -- opaque application
stepOne (TApp2 _ _ _)             _val _   = Nothing        -- opaque application
stepOne (TArith _ _ _)            _val _   = Nothing        -- structural arithmetic in an OUTPUT
```

Read in plain language:

| Output field shape | Smart-constructor / surface form | Inverts? | Why |
|---|---|---|---|
| `TLit r` | `lit r` | ✅ | A literal carries no command data, so there is nothing to recover. |
| `TReg ix` | `#slot` / `proj ix` | ✅ | The value is recovered from the register file replay has already rebuilt. |
| `TInpCtorField ic ix`, matching ctor | `d.field` | ✅ | The event field *is* a copy of a command field, so the observed value is the recovered value. |
| `TInpCtorField`, non-matching ctor | — | ❌ | The field belongs to a different command constructor; `solveOutput` returns `Nothing`. |
| `TApp1 f t` / `TApp2 f a b` | (no helper; escape hatch) | ❌ | An opaque Haskell function has no inverse keiki can compute. |
| `TArith op a b` | `tadd`/`tsub`/`tmul`, `.+`/`.-`/`.*` | ❌ | Arithmetic is not uniquely reversible from the result alone. |

So a literal, a register read, and a command-field copy from the *same* constructor all
round-trip. Any opaque application or structural-arithmetic term in an output field makes
`solveOutput` return `Nothing`.

---

## 3. The failure is a plain `Nothing`, not an exception

`solveOutput` returns `Maybe ci`. The failure is an ordinary `Nothing`. There is no named
error type in keiki, and no exception is thrown. A repo-wide search for `HydrationReplayFailed`
finds **zero** hits in keiki's Haskell source — that named error is the **keiro/Rei runtime's**
translation of keiki's `Nothing`, not a keiki symbol. If you are searching keiki for
`HydrationReplayFailed`, you are looking in the wrong library.

If you reach keiki *through the keiro runtime*, disambiguate keiro's three hydration failures
before you debug — they are easy to confuse, and chasing one will send you looking in the wrong
place for the others. All three live in keiro's `src/Keiro/Command.hs`:

- **`HydrationReplayFailed` from an inversion `Nothing`** — keiro's `applyEvent` maps a
  `Nothing` from `Keiki.applyEventStreaming` straight to this error. This is the case this page
  governs: an output field that does not invert.
- **`HydrationReplayFailed` from a final `InFlight` state** — replay finished mid-chain (a
  multi-event edge was truncated). `finishReplay` rejects a non-final `InFlight`. *Same named
  error, different cause* — nothing to do with output invertibility.
- **`HydrationDecodeFailed`** — the recorded JSON bytes failed to decode. A codec failure,
  separate from inversion entirely.

When you see a replay failure, confirm you are in the first case (the inversion `Nothing`
documented here) before applying any of the recipes below.

---

## 4. One non-invertible field poisons the whole edge

The inversion is **all-or-nothing per edge**. `gatherInpEntries` folds `stepOne` across
*every* output field; if a *single* field returns `Nothing`, the whole fold collapses to
`Nothing` and `solveOutput` fails for the **entire** edge — including the fields that *do*
invert, and even fields that are not command slots at all. There is no partial recovery.

The practical consequence is severe. An aggregate with even one state-resolved `previous*`
field — an event field carrying a register's prior value, resolved on the write path rather
than copied from the user command — is dragged *wholesale* into the mirror-command workaround
(§7.2), because that one field cannot be inverted from the command. Rei's Reminder aggregate
(whose `ReminderRescheduled` event carries `previousScheduledFor`) and Disruption aggregate
(whose `DisruptionDescriptionUpdated` event carries `previousDescription`) are exactly this
case: each is event-mirrored through a dedicated stream command *precisely because one
`previous*` field cannot round-trip*.

The sibling plan
`docs/plans/47-recompute-and-verify-derived-event-outputs-in-solveoutput-replay.md` removes
this penalty: it recomputes and verifies derived output fields on replay, so a single derived
field no longer kills the edge.

---

## 5. The restriction is output-only

The rejection above applies **only to output expressions**. Replay re-runs each edge's guard
and update *forward* with `evalTerm` (`src/Keiki/Core.hs`, around lines 728–737), which handles
*every* `Term` shape — including `TApp1`, `TApp2`, and `TArith`. Only the *output* is inverted,
and only the inverse direction (`stepOne`) rejects the opaque shapes.

So a `TApp` or an arithmetic term in a **guard** or a **register update** replays without any
trouble; round-tripping breaks only when such a term appears in an event's payload field. The
natural fear — "I can never use a function or arithmetic in my aggregate" — is wrong.

A worked example of arithmetic living happily in a guard:
`jitsurei/src/Jitsurei/LoanApplication.hs`'s `approvalGuard` (around lines 431–436) reads

```haskell
proj (#appRequestedAmount :: …) .<= proj (#appCreditScore :: …) .* lit 1000
```

That `.*` is structural `TArith` *inside a guard*. It replays via `evalTerm` and is visible to
the SMT solver — arithmetic belongs in guards and updates freely. Only outputs are restricted.

---

## 6. The build-time safety net: `checkHiddenInputs`

You do not have to discover an invertibility problem at replay time. Beside `solveOutput` sits
the static check `checkHiddenInputs` (`src/Keiki/Core.hs`, around lines 1104–1197). It walks
every edge of a transducer and reports a `HiddenInputWarning` when the output cannot
mechanically recover the command — for example when an output leaves a command-constructor slot
unvisited, or when an ε-edge (one that emits no event) reads the command in its update.

"Build-time" here means it runs when you *evaluate* the transducer in a test or build step, not
on the per-event runtime path. `docs/guide/symbolic-ci.md` shows how teams wire such checks into
CI. Treat `checkHiddenInputs` as the net that catches the mistake before any event is replayed
in production.

---

## 7. Recipes

You have an event that needs to record a value. Find the matching recipe.

### 7.1 An audit / `previous*` field → use a register read (round-trips today)

An event field that records a register's *prior* value — a `previousStatus`, a
`previousBalance`, a `previousScheduledFor` — round-trips **today, with no special handling**,
*provided you write it as a plain register read*. Two facts make this work:

1. `solveOutput` is handed the register file *as it was before the edge's update ran*. You can
   see this at the `applyEvent` call site (`src/Keiki/Core.hs`, around line 886): it calls
   `solveOutput o regs co` and only *afterwards* applies the edge's update to `regs`. So a
   register read in the output resolves to the pre-update value — exactly what an audit field
   wants.
2. A register read is an accepting term: `stepOne (TReg _) = Just []`.

The real example is `jitsurei/src/Jitsurei/UserRegistration.hs`'s `AccountConfirmed` edge
(around line 309):

```haskell
B.emit wireAccountConfirmed AccountConfirmedTermFields
  { email       = #email
  , confirmCode = d.confirmCode
  , at          = d.at
  }
```

`email = #email` is a `TReg` read (the registered email, recovered from the register file on
replay); `confirmCode = d.confirmCode` and `at = d.at` are command-field copies. All three
invert, so the event round-trips.

> Reach for a register read (`#slot` / `proj`) first for audit fields — do **not** wrap it in a
> function. Rei hit the invertibility wall only because it wrote such fields as *derived*
> expressions (a `TApp` over the register) instead of a plain read.

### 7.2 A genuinely derived value → the Direction-A mirror command (today's escape)

First, the wall. An event whose payload field is a *derived* value does **not** round-trip
today, and — because the failure is all-or-nothing per edge (§4) — that one field poisons the
whole edge. Two real shapes:

- An opaque application, as in `jitsurei/src/Jitsurei/CoreBankingSync.hs`'s
  `LegacyAssignmentCommanded` edge (around line 208):

  ```haskell
  B.emit wireLegacyAssignmentCommanded LegacyAssignmentCommandedTermFields
    { assignment = TApp2 buildAssign d.loanId d.legacyLoanId }
  ```

  `TApp2` is opaque → `stepOne (TApp2 _ _ _) = Nothing`.

- Arithmetic, as in the `ReorderTriggered` event of
  `docs/guide/deriving-lifecycle-transitions.md` §4, whose payload is
  `onHand = #onHand .- d.quantity` — a `TArith` (`tsub`) → `stepOne (TArith _ _ _) = Nothing`.

Because the inversion is per-edge, an aggregate with even a *single* state-resolved `previous*`
field is dragged into this workaround wholesale — which is exactly what Rei's Reminder
(`previousScheduledFor`) and Disruption (`previousDescription`) aggregates do: each mirrors the
*entire* event through a dedicated stream command because one field cannot invert.

The portable workaround today is what the master plan calls **Direction A**: introduce a
command that *mirrors the event's payload verbatim*, so the edge emits a plain `d.field` copy (a
`TInpCtorField`) that inverts. The value is computed before the command is issued and carried in
the command. The cost is a **doubled command vocabulary** — you add a carry-only command whose
only job is to ferry the already-computed value.

> This is *today's* escape. The sibling plan
> `docs/plans/47-recompute-and-verify-derived-event-outputs-in-solveoutput-replay.md` will let
> derived fields round-trip by *recomputing and verifying* them on replay — removing the need
> for the mirror command, and with it the all-or-nothing penalty (a single derived field would
> no longer kill the edge).

### 7.3 What fails, and why

The inversion is structural and per-field. An opaque application (`TApp1`/`TApp2`) has no
inverse keiki can compute — the wrapped function is a black box. An arithmetic output term
(`TArith`) is not inverted either: subtraction or multiplication is not uniquely reversible from
the result alone (`a - b = r` does not determine `a` and `b`). So `stepOne` rejects both
outright, and — per §4 — that aborts the whole edge's inversion, not just the one field.
