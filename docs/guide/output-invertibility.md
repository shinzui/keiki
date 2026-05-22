# Output invertibility — which events round-trip on replay

keiki reconstitutes an aggregate from its event log without any hand-written inverse
code: it *inverts* each edge's output expression to recover the command that must have
produced the observed event, then re-runs the edge forward. That inversion is mechanical,
and it is **not total** — only certain shapes of output expression can be inverted.

The contract a reader can apply immediately:

> An event round-trips on replay **if and only if** the command can be recovered from its
> *invertible* payload fields — literals, register reads, and copies of fields from the *same*
> command constructor. A payload field that applies a Haskell function (`TApp1`/`TApp2`) or does
> structural arithmetic (`TArith`) is a **derived** field: since EP-47 it round-trips too, by
> being *recomputed and verified* on replay — as long as every command field it reads is also
> read by an invertible field (so the command is recoverable without it). An event fails to
> round-trip only when a command field is read **only** inside a derived field (a *hidden
> input*); `solveOutput` then returns `Nothing`, and `checkHiddenInputs` flags it at build time.

This page states the rule, names the symbols that implement it (all in `src/Keiki/Core.hs`),
and gives worked recipes for the "this event stores a derived value" situations that motivate
it. The contract governs the code as of EP-47 (the relaxation is recorded in
`docs/research/recompute-and-verify-derived-outputs.md`); nothing here asks you to change an
aggregate.

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
- A **derived** field (an opaque application `TApp1`/`TApp2`, or structural arithmetic
  `.+` / `.-` / `.*` i.e. `TArith`) also round-trips **as long as every command field it reads
  is *also* read by an invertible field elsewhere in the same edge** (a *redundant* derived
  field). The derived value is recomputed and verified on replay (see §2).
- It only **fails** to round-trip if a command field is read **only** inside a derived field
  (a *hidden input*) — then the command cannot be recovered, and the build-time check
  `checkHiddenInputs` flags it (§6).

> **Since EP-47** (`docs/plans/47-recompute-and-verify-derived-event-outputs-in-solveoutput-replay.md`),
> derived output fields round-trip via *recompute-and-verify*. Before EP-47 a derived field of
> any kind aborted replay for the whole edge; that earlier, stricter rule is described as
> historical context where relevant below.

---

## 2. What inverts — recover, then recompute-and-verify

`solveOutput` works in two phases. **Phase 1 (recover)** rebuilds the command from the
*invertible* fields alone. `gatherInpEntries`/`stepOne` (`src/Keiki/Core.hs`, around lines
1054–1071) walk the output fields; a derived field is *skipped* (it contributes no command
information):

```haskell
stepOne (TLit _)                  _val _   = Just []        -- literal: nothing to recover
stepOne (TReg _)                  _val _   = Just []        -- register read: nothing to recover
stepOne (TInpCtorField ic2 ix)    val  ic1
  | icName ic1 == icName ic2 = Just [ByIndex (unsafeCoerce ix) val]  -- field of THIS command ctor
  | otherwise                = Nothing                              -- field of a DIFFERENT ctor
stepOne (TApp1 _ _)               _val _   = Just []        -- derived: skipped, verified in Phase 2
stepOne (TApp2 _ _ _)             _val _   = Just []        -- derived: skipped, verified in Phase 2
stepOne (TArith _ _ _)            _val _   = Just []        -- derived: skipped, verified in Phase 2
```

**Phase 2 (recompute-and-verify)** then recomputes each *derived* field forward against the
recovered command and the pre-update registers and checks it equals the observed value; an
all-invertible edge has nothing to recompute and behaves exactly as before. Read in plain
language:

| Output field shape | Smart-constructor / surface form | Round-trips? | How |
|---|---|---|---|
| `TLit r` | `lit r` | ✅ | A literal carries no command data; recovered trivially, not verified. |
| `TReg ix` | `#slot` / `proj ix` | ✅ | Recovered from the register file; the observed value is kept, not re-verified (so an audit field round-trips even if the register is not yet populated on a partial replay). |
| `TInpCtorField ic ix`, matching ctor | `d.field` | ✅ | The event field *is* a copy of a command field — Phase 1 recovers the command from it. |
| `TInpCtorField`, non-matching ctor | — | ❌ | The field belongs to a different command constructor; `solveOutput` returns `Nothing` (a malformed edge). |
| `TApp1 f t` / `TApp2 f a b` (**redundant**) | (no helper; escape hatch) | ✅ | Skipped in Phase 1; **recomputed forward and verified** in Phase 2. Requires every command field it reads to be read by an invertible field too. Even an *opaque* function is fine — it is only run forward, never inverted. |
| `TArith op a b` (**redundant**) | `tadd`/`tsub`/`tmul`, `.+`/`.-`/`.*` | ✅ | Skipped in Phase 1; recomputed and verified in Phase 2. |
| any derived field that **hides** a command input | — | ❌ | If a command field is read *only* inside a derived field, Phase 1 cannot recover it → `solveOutput` returns `Nothing`. `checkHiddenInputs` flags this at build time (§6). |

So literals, register reads, and same-constructor command-field copies round-trip by recovery;
derived fields round-trip by recompute-and-verify **provided they are redundant** (every command
field they read is also read invertibly). The command is therefore *always* recovered from the
invertible fields alone — derived fields are a cross-check, never a source of command bits — so
"the event uniquely determines the command, certified at build time" is preserved. The full
argument is in `docs/research/recompute-and-verify-derived-outputs.md`.

> **Tampering is rejected.** Because Phase 2 recomputes each derived field and compares it to
> the observed value, an event whose derived field has been altered (a `lineTotal` that is not
> `quantity * unitPrice`) fails to replay — `solveOutput` returns `Nothing`.

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

## 4. A redundant derived field no longer poisons the edge

**Historical note (pre-EP-47):** the inversion used to be *all-or-nothing per edge* — a single
derived (`TApp`/`TArith`) field made `gatherInpEntries` return `Nothing` and killed the whole
edge on replay, even fields that did invert. An aggregate with one state-resolved derived
field (an audit value computed on the write path) was dragged *wholesale* into a
mirror-command workaround. Rei's Reminder (`ReminderRescheduled`) and Disruption
(`DisruptionDescriptionUpdated`) aggregates hit exactly this.

**Since EP-47**, that penalty is gone for *redundant* derived fields. A derived field is
skipped during command recovery and then recomputed-and-verified, so it no longer poisons the
edge — provided every command field it reads is also read by an invertible field (so the
command is still recoverable). The only remaining all-or-nothing failure is a **hidden input**:
a command field read *only* inside a derived field. Then Phase 1 cannot recover that field, so
`solveOutput` returns `Nothing` for the edge — and `checkHiddenInputs` flags it at build time
(§6). In short: a derived field that *adds* a computed value round-trips; a derived field that
*hides* a command input still fails (loudly, and early).

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

### 7.1 An audit / `previous*` field → use a register read (round-trips with no verification)

An event field that records a register's *prior* value — a `previousStatus`, a
`previousBalance`, a `previousScheduledFor` — round-trips **with no special handling**,
*provided you write it as a plain register read*. (A register read is an invertible field: its
observed value is kept as-is and is *not* re-verified against state, so the field round-trips
even on a partial replay where the register is not yet populated.) Two facts make this work:

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

### 7.2 A computed value → store it directly (recompute-and-verify)

Since EP-47, an event field that stores a *derived* value round-trips on its own, **provided
the command is still recoverable from the other (invertible) fields**. You no longer need a
mirror command. Two real shapes:

- An opaque application, as in `jitsurei/src/Jitsurei/CoreBankingSync.hs`'s
  `LegacyAssignmentCommanded` edge (around line 208):

  ```haskell
  B.emit wireLegacyAssignmentCommanded LegacyAssignmentCommandedTermFields
    { assignment = TApp2 buildAssign d.loanId d.legacyLoanId }
  ```

- Arithmetic, as in the `ReorderTriggered` event of
  `docs/guide/deriving-lifecycle-transitions.md` §4, whose payload is
  `onHand = #onHand .- d.quantity` — a `TArith` (`tsub`).

On replay, `solveOutput` recovers the command from the invertible fields, then recomputes the
derived field forward (running the same `TApp2`/`TArith` it would have run on emit) and checks
it equals the observed value. A worked example: an order-cart `LineItemAdded` event with
`lineTotal = d.quantity .* d.unitPrice` round-trips through `applyEvents`, and a tampered
`lineTotal` is rejected (see `test/Keiki/RecomputeVerifySpec.hs`).

**The one caveat** is redundancy: every command field the derived term reads must *also* be
read by an invertible field, so Phase 1 can still recover the command. The
`CoreBankingSync` example above is the counter-case — `loanId`/`legacyLoanId` are read **only**
inside the `TApp2`, so they are *hidden inputs* and the edge still does **not** round-trip;
`checkHiddenInputs` flags it (§6). The fix there is to also emit those ids as plain `d.field`
copies (or read them from registers), making the derived `assignment` redundant.

> **Historical (pre-EP-47):** a derived field of any kind aborted replay for the whole edge
> (the "all-or-nothing per edge" rule, §4). The portable workaround was *Direction A* — a
> mirror command carrying the already-computed value verbatim, at the cost of a doubled command
> vocabulary. Recompute-and-verify removes that need for *redundant* derived fields; a mirror
> command is now only relevant if you genuinely cannot make the derived field redundant.

### 7.3 What still fails, and why

After EP-47 two cases still make `solveOutput` return `Nothing`:

- **A hidden input** — a command field read *only* inside a derived (`TApp`/`TArith`) field.
  Phase 1 recovers the command from invertible fields alone, so a field that appears nowhere
  invertible cannot be recovered. `checkHiddenInputs` flags this at build time (§6).
- **A non-matching `TInpCtorField`** — an output field projecting a *different* command
  constructor than the edge consumes (a malformed edge).

A *redundant* derived field does **not** fail: it is recomputed forward and verified. Note that
the recompute only ever runs the term *forward* (via `evalTerm`), so even an opaque `TApp` works
— invertibility of the wrapped function is never required; only that recomputing it reproduces
the observed value.

---

## 8. Modeling redirects — patterns that look like they need an escape hatch

These are the patterns that motivate reaching for an opaque `TApp` in an output (or for a
variadic apply, or a positional multi-argument command). Each has a *structural* answer that
keeps the output invertible and the guard solver-visible. Reach for these before any escape
hatch.

**(a) Numeric or date bounds belong in an ordering guard, not a function.** A bound like
"amount ≤ 1000" or "before this deadline" is a structural `PCmp` comparison over a curated
ordered type — and `UTCTime` (the standard timestamp) *is* curated, so the solver understands
its ordering. No escape hatch is needed; a bare or computed bound is structural. See
`docs/guide/why-smt.md` §5 (the curated types and "no escape needed" note) and
`docs/guide/symbolic-ci.md`.

**(b) A multi-way (3-way, N-way) decision is multiple disjoint guarded edges,** not one opaque
application that picks a branch. Author one edge per branch, keyed on the same input
constructor, disambiguated by independent comparison guards; the single-valuedness gate then
proves they never co-fire. See `docs/guide/deriving-lifecycle-transitions.md`, which works this
split-into-disjoint-edges pattern in full.

**(c) A computed operand (a weighted sum, a derived cap) is structural arithmetic** —
`tadd`/`tsub`/`tmul`, written `.+`/`.-`/`.*` — which has been solver-visible since the EP-43
work. In a *guard or update* it round-trips and the solver reads it; only in an *output* does
arithmetic block inversion (§7.3). See `docs/guide/user-guide.md` §3.4.

**(d) Collection membership is the on-roadmap structural collection-content guards, not a
higher-arity `TApp`.** Membership and bounded-quantifier guards (`PMember` / `PAll`) are the
faithful direction — *not* a `TApp3`/`TAppN`, which would re-introduce an opaque,
non-invertible, solver-blind term. These guards are described in
`docs/masterplans/12-symbolic-arithmetic-terms-translator-memoization-and-real-boolalg-sat-witnesses.md`
and `docs/research/collection-registers-design.md`.

> This is forward advice for the next consumer, not a description of something a consumer
> shipped. Validation against Rei's ported transducers found that the date-bounds and
> map-membership *guards* (and the 3-way conditional) once attributed to its Cycle aggregate
> **do not exist** in the keiki transducers — Direction A moved them to a deferred application
> layer. The one *real* residual ergonomic in this family is milder and different: a
> **collection-register update** that threads a `(map, key, value)` triple via a nested
> `TApp2 (,)` to a `Map.insert` helper. Its only two occurrences in Rei are register *updates*
> (`B.slot @"dailyFocuses" .= TApp2 insertFocus … (TApp2 (,) …)` and
> `B.slot @"values" .= TApp2 insertValue … (TApp2 (,) …)`), never a guard and never an output,
> so they replay forward via `evalTerm` and never break inversion. The faithful fix for *that*
> ergonomic is the collection-registers roadmap (a register that holds a collection and accepts
> a structural insert), not a higher-arity `TApp`.

**(e) A multi-argument command is one named-record payload, with the dropped id read back from
a register.** keiki's symbolic alphabet projects command fields *by name* — an `InCtor`'s slots
are `(Symbol, Type)` pairs — so splitting one logical command into several positional arguments
fights that name-based projection. Model `UpdateFoo !FooId !FooData` as the single record
command `UpdateFoo !FooData`, and *source the dropped id from a register on emit* via a register
read. Rei's Focus aggregate does exactly this: the logical `UpdateFocus !FocusId !UpdateFocusData`
is the single record `UpdateFocus !UpdateFocusData`
(`rei-core/src/Rei/Modules/Focus/Domain/Command.hs`), and the `FocusUpdated` edge emits
`focusId = curFocusId`, where `curFocusId = proj (indexOf @"focusId" @FocusRegs @FocusId)` reads
the id back from the `FocusRegs` register
(`rei-core/src/Rei/Modules/Focus/Domain/Transducer.hs`). Because the alphabet projects fields by
name and a register read is an accepting output term, this round-trips.

---

## 9. See also

- `src/Keiki/Core.hs` — the symbols this contract describes: `solveOutput` (~1039),
  `gatherInpEntries`/`stepOne` (~1054–1071), `evalTerm` (~728–737),
  `applyEvent`/`applyEventStreaming` (~882–966), `checkHiddenInputs` (~1104–1197).
- `docs/guide/user-guide.md` §10.3 — glossary entries for `solveOutput`, `applyEvent`, and
  `checkHiddenInputs`.
- `docs/guide/why-smt.md` §5 — escape hatches and curated types, the dual concern to this page.
- `docs/guide/symbolic-ci.md` — wiring `checkHiddenInputs` and the single-valuedness gate into
  CI.
- `docs/guide/deriving-lifecycle-transitions.md` — the disjoint-guarded-edges pattern for
  multi-way decisions (and the guard-free Mermaid default).
- `docs/plans/47-recompute-and-verify-derived-event-outputs-in-solveoutput-replay.md` — the
  planned relaxation under which derived output fields round-trip by recompute-and-verify.
- `docs/research/collection-registers-design.md` and
  `docs/masterplans/12-symbolic-arithmetic-terms-translator-memoization-and-real-boolalg-sat-witnesses.md`
  — the structural collection-content guards (`PMember`/`PAll`).
