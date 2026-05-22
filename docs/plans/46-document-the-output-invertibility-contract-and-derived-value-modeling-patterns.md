---
id: 46
slug: document-the-output-invertibility-contract-and-derived-value-modeling-patterns
title: "Document the output-invertibility contract and derived-value modeling patterns"
kind: exec-plan
created_at: 2026-05-21T22:59:23Z
intention: "intention_01ks6ber3jedc8ff6zzma2jr53"
master_plan: "docs/masterplans/13-keiki-api-improvements-surfaced-by-the-rei-migration.md"
---

# Document the output-invertibility contract and derived-value modeling patterns

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

keiki is a Haskell library for building event-sourced aggregates as symbolic-register
transducers — small state machines whose edges carry a guard, a register update, and an
output (the event). One of keiki's load-bearing guarantees is that an aggregate can be
*reconstituted*: given the recorded event log, keiki replays each event back into a state
and register file without any hand-written inverse code. It does this by *inverting* each
edge's output expression to recover the command that must have produced the observed event.
That inversion is mechanical, and it is not total: only certain shapes of output expression
can be inverted. Today that rule lives only in the source code of one function,
`solveOutput` in `src/Keiki/Core.hs`, and in the build-time analysis `checkHiddenInputs`
beside it. Nothing in the consumer-facing guides states it.

Rei — the first real downstream consumer of keiki — reported that the single most
time-consuming problem they hit was discovering this rule the hard way: by reading the
source of `solveOutput`. They spent days because (a) the failure surfaces as a runtime
error their own stack named `HydrationReplayFailed`, which is *not* a keiki symbol and led
them to look in the wrong place, and (b) they wrote audit fields (an event field that
records a register's prior value) as *derived* expressions, not realizing that a plain
register read already round-trips on today's code.

After this change a reader has one consumer-facing page,
`docs/guide/output-invertibility.md`, that states the exact rule in plain language: which
output expression shapes invert and which return "no result"; that the failure is an
ordinary `Maybe`/`Nothing`, not an exception; that a *single* non-invertible field poisons
the *whole* edge (the inversion is all-or-nothing per edge); that the restriction applies
*only* to output expressions and never to guards or register updates; and that the build-time
check `checkHiddenInputs` flags the problem before you ship. The page carries worked
"this event stores a derived value, so do X" recipes, and short modeling redirects that
point readers at the structural answer for the patterns that motivated the request. You can
see it working by following the page's prediction procedure against a real aggregate: pick
any edge in `jitsurei/src/Jitsurei/`, read its `emit`, and the page tells you whether that
event round-trips — a prediction you can confirm against the cited code in
`src/Keiki/Core.hs`.

This plan changes documentation only. It does not modify any Haskell source. It writes down
a contract that *already governs* the code, so that the next consumer reads it instead of
rediscovering it.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] M1 (2026-05-21): Created `docs/guide/output-invertibility.md` stating the exact
  accept/reject term list, the `Nothing`-not-an-exception semantics (with the
  `HydrationReplayFailed` attribution + keiro three-failure disambiguation), the
  all-or-nothing-per-edge semantics, the output-only scoping, and the build-time
  `checkHiddenInputs` safety net. Each claim verified against the cited `src/Keiki/Core.hs`
  symbols (`solveOutput` ~1039, `gatherInpEntries`/`stepOne` ~1054–1071, `evalTerm` ~728–737,
  `applyEvent`/`applyEventStreaming` ~882–966, `checkHiddenInputs` ~1104–1197); `stepOne`
  block on the page is verbatim from source (incl. `unsafeCoerce ix`).
- [ ] M2: Add the worked "derived value → do X" recipes to that page: the audit/`previous*`
  field via a register read (round-trips today), the computed total via the Direction-A
  mirror command (today's escape, with a forward pointer to
  `docs/plans/47-recompute-and-verify-derived-event-outputs-in-solveoutput-replay.md`), and a
  plain statement of what fails and why.
- [ ] M3: Cross-link sweep plus the modeling redirects (a)–(e). Add short notes to
  `docs/guide/user-guide.md`, `docs/guide/why-smt.md`,
  `docs/guide/deriving-lifecycle-transitions.md`, and `docs/guide/symbolic-ci.md`, each
  linking the new page; confirm the new page is reachable from the user guide and the
  redirects point readers at structural answers.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)

Note for the implementer (pre-implementation observation, to be confirmed and moved here as a
proper entry once acted on): the existing `solveOutput` glossary entry in
`docs/guide/user-guide.md` §10.3 describes `solveOutput` as "the build-time analysis that
mechanically derives the inverse of `omega`". That role label is imprecise — `solveOutput` is
the *runtime* inverter on the replay path (called by `applyEvent`/`applyEventStreaming`/
`reconstitute`), while the *build-time* analysis is `checkHiddenInputs`. The same glossary's
`checkHiddenInputs` entry already (correctly) calls itself "build-time analysis". M3 corrects
the `solveOutput` wording while adding the cross-link.


## Decision Log

Record every decision made while working on the plan.

- Decision: Create a new dedicated page `docs/guide/output-invertibility.md` rather than only
  expanding the existing `docs/guide/user-guide.md` glossary.
  Rationale: Consumers need one canonical, linkable source of truth for the invertibility
  contract. The user guide is long and topic-organized; a single named page is easier to cite
  in a downstream issue or a stack trace's "see also". The glossary still gets short entries
  that link to the page, so neither place goes stale silently.
  Date: 2026-05-21

- Decision: Document *today's* behavior — `solveOutput` inverts only `TLit`/`TReg`/
  `TInpCtorField` and returns `Nothing` for `TApp1`/`TApp2`/`TArith` — and add an explicit
  forward pointer to
  `docs/plans/47-recompute-and-verify-derived-event-outputs-in-solveoutput-replay.md`, rather
  than pre-documenting EP-47's relaxed "recompute-and-verify" contract.
  Rationale: EP-47 is a separate plan that has not landed. Documenting an unshipped contract
  would mislead a reader on the current code. EP-47 owns the amendment to this same page; M1
  and M2 mark the "today's behavior" sections so that amendment is a clean, localized edit.
  Date: 2026-05-21

- Decision: Call out two specific consumer confusions verbatim on the page: (i) the named
  error `HydrationReplayFailed` is the keiro/Rei *runtime's* translation of keiki's `Nothing`,
  not a keiki symbol (repo-wide grep finds zero hits in keiki source); and (ii) an audit field
  that stores a register's prior value already round-trips today when written as a plain
  register read, because `stepOne (TReg _) = Just []` and outputs are evaluated against the
  pre-update register file.
  Rationale: Both were the actual time-sinks Rei reported. Naming them directly on the page is
  the cheapest way to stop the next consumer repeating them.
  Date: 2026-05-21

- Decision: State the inversion failure as *all-or-nothing per edge* — a single non-invertible
  output field makes `gatherInpEntries`/`solveOutput` return `Nothing` for the whole edge,
  including fields that do invert and fields that are not command slots, so one derived field
  poisons the entire event — and tie this to the observed consumer cost: an aggregate with even
  one state-resolved `previous*` field is dragged wholesale into the Direction-A mirror-command
  workaround.
  Rationale: Validated against live Rei source. `gatherInpEntries` folds `stepOne` across every
  output field, so any single `Nothing` collapses the fold. Rei's Reminder
  (`ReminderRescheduled.previousScheduledFor`) and Disruption
  (`DisruptionDescriptionUpdated.previousDescription`) aggregates are each event-mirrored
  through a dedicated stream command *precisely because one `previous*` field cannot invert* —
  this is exactly the consumer pain the page must name. EP-47 removes the penalty, so the page
  forward-points to it.
  Date: 2026-05-21

- Decision: Re-anchor modeling redirect (d). Keep the structural-guard guidance (bounds → a
  structural `PCmp` over a curated ordered type; multi-way branching → disjoint guarded edges;
  computed operands → `tadd`/`tsub`/`tmul`) strictly as *forward advice for the next consumer*,
  and add an accurate note that the real residual #3 ergonomic in Rei is a collection-register
  *update* threading a `(map, key, value)` triple via nested `TApp2 (,)` to a `Map.insert`
  helper — routed to the collection-registers roadmap, not a higher-arity `TApp`.
  Rationale: Validation found the master plan's claimed Cycle date-bounds and map-membership
  *guards* and 3-way conditional *do not exist* in Rei's ported transducers; Direction A moved
  them to the deferred application layer. The only residual tuple-nesting in all of Rei is two
  `Map.insert` register updates (`rei-core/src/Rei/Modules/Cycle/Domain/Transducer.hs` and
  `rei-core/src/Rei/Modules/CustomProperty/Domain/PropertyAssignmentTransducer.hs`) — never a
  guard, never an output, never breaking replay. The page must not present non-existent guards
  as shipped.
  Date: 2026-05-21

- Decision: Strengthen modeling redirect (e) with the concrete Rei idiom. A multi-argument
  command like `UpdateFoo !FooId !FooData` is modeled as a *single named-record command*, and
  the dropped id is sourced from a register on emit via a register read.
  Rationale: Pervasive and validated in Rei's Focus aggregate, where
  `UpdateFocus !FocusId !UpdateFocusData` is the single record `UpdateFocus !UpdateFocusData`
  (`rei-core/src/Rei/Modules/Focus/Domain/Command.hs`) and the `FocusUpdated` edge emits
  `focusId = curFocusId` with `curFocusId = proj (indexOf @"focusId" @FocusRegs @FocusId)`
  (`rei-core/src/Rei/Modules/Focus/Domain/Transducer.hs`). Because the symbolic alphabet
  projects fields by name and a register read is an accepting output term, this idiom is the
  faithful answer and round-trips.
  Date: 2026-05-21

- Decision: Add a consumer-facing note disambiguating keiro's three hydration failures. For a
  consumer reaching keiki through the keiro runtime, the inversion `Nothing` surfaces as keiro's
  `HydrationReplayFailed`; this is DISTINCT from `HydrationDecodeFailed` (a JSON codec failure)
  and from a final-`InFlight` replay error (mid-chain truncation, which also raises
  `HydrationReplayFailed`). A consumer debugging replay should confirm the failure is the
  inversion `Nothing` (this contract), not one of those.
  Rationale: Validated in keiro's `src/Keiro/Command.hs`: `applyEvent` maps `solveOutput`'s
  `Nothing` to `HydrationReplayFailed`, `finishReplay` maps a final `InFlight` to the same
  error, and `HydrationDecodeFailed` is a separate codec failure. Surfacing the distinction
  saves the next consumer from looking in the wrong place — the original time-sink Rei reported.
  Date: 2026-05-21


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

This section assumes you know nothing about keiki. Read it once before you write any prose;
every term it defines is one you will need to use accurately on the new page.

keiki is a pure Haskell library. Its core type is the *symbolic-register transducer*: a
finite state machine where each state is called a *vertex*, and each transition (called an
*edge*) carries four things — a *guard* (a boolean condition that decides whether the edge is
active), an *update* (which registers it writes and to what), an *output* (the event it
emits), and a *target* vertex. A *register* is a named, typed cell of remembered state; the
whole bundle of registers is a *register file*. The library lives under `src/Keiki/`; the
file that matters for this plan is `src/Keiki/Core.hs`.

In domain terms a transducer reads *commands* (the requests an aggregate accepts; the type is
written `ci`, "command in") and emits *events* (the facts it records; the type is written
`co`, "event out"). Running the machine *forward* means: given the current vertex, register
file, and an incoming command, find the unique edge whose guard holds, write its update, and
emit its output event. Running it *backward* — called *reconstitution* or *replay* — means:
given the recorded sequence of events, rebuild the vertex and register file that must have
produced them. Replay is what lets an event-sourced system rebuild its current state from
history.

The forward and backward directions are implemented by a small expression language called
`Term`. A `Term rs ci r` is a tiny syntax tree (not a Haskell function) describing how to
compute a value of type `r` from the register file (slot list `rs`) and the incoming command
(`ci`). Its constructors, all defined in `src/Keiki/Core.hs`, are: `TLit` (a constant
literal; smart constructor `lit`), `TReg` (read a register; smart constructor `proj`, or the
overloaded-label form `#slotName`), `TInpCtorField` (read a *field of the command* — the data
the command carries; written `d.fieldName` inside an edge body), and three *opaque* shapes:
`TApp1`/`TApp2` (apply an arbitrary one- or two-argument Haskell function — an "escape
hatch"), and `TArith` (structural arithmetic add/subtract/multiply; smart constructors
`tadd`/`tsub`/`tmul`, also written with the operators `.+`/`.-`/`.*`). The word *opaque* here
means the library cannot see inside the value: a `TApp1`/`TApp2` wraps a plain Haskell
function with no structure keiki can inspect, and `TArith` combines two sub-terms with an
arithmetic operator.

An edge's output is built with `pack` (constructor `OPack`), producing an `OutTerm rs ci co`.
An `OutTerm` bundles three things: an `InCtor` (reified evidence naming which *command
constructor* this edge expects, and how to rebuild a command value from its fields), a
`WireCtor` (the dual for the *event constructor*), and an `OutFields` list — one `Term` per
field of the event payload. In the builder surface you write this as
`B.emit wireFoo FooTermFields { field1 = ..., field2 = ... }`, where each right-hand side is a
`Term`. The forward evaluator `evalOut` (`src/Keiki/Core.hs`, near the `evalTerm` definition
around line 752) just runs each field's `Term` and assembles the event.

The inverse direction is the function this plan documents: `solveOutput` in
`src/Keiki/Core.hs` (around line 1039), with signature
`solveOutput :: OutTerm rs ci co -> RegFile rs -> co -> Maybe ci`. Given the edge's output
expression, the register file *as it was before the edge's update ran*, and an observed event,
it tries to recover the command that produced that event. It returns `Just command` on
success and `Nothing` on failure. The recovery is purely structural: it walks the `OutFields`
in lockstep with the observed event's fields, and for each field's `Term` it asks "what does
this field tell me about the original command?" That per-field decision is made by the helper
`gatherInpEntries` and its inner `stepOne` (around lines 1054–1071). Reading the source, the
accept/reject rule is exactly:

    stepOne (TLit _)               _   _   = Just []                        -- literal: contributes nothing to recover; OK
    stepOne (TReg _)               _   _   = Just []                        -- register read: recovered from replayed regs; OK
    stepOne (TInpCtorField ic2 ix) val ic1
      | icName ic1 == icName ic2 = Just [ByIndex ix val]                    -- command-field projection: this IS the carried data; OK
      | otherwise                = Nothing                                  -- field of a different command ctor: reject
    stepOne (TApp1 _ _)            _   _   = Nothing                        -- opaque application: reject
    stepOne (TApp2 _ _ _)         _   _   = Nothing                        -- opaque application: reject
    stepOne (TArith _ _ _)        _   _   = Nothing                        -- structural arithmetic in an OUTPUT: reject

So a literal output field round-trips (it carries no command data, so there is nothing to
recover). A register read round-trips (its value is recovered from the register file that
replay has already rebuilt). A command-field projection round-trips (it is literally a copy of
a command field, so the observed event field *is* the recovered value). But any opaque
application or structural-arithmetic output field makes `solveOutput` return `Nothing` for the
whole edge — the inversion aborts.

The failure is *all-or-nothing per edge*, and the page must say so in those words because it
is exactly what a consumer hits. `gatherInpEntries` folds `stepOne` across *every* output
field; if a *single* field returns `Nothing`, the whole fold collapses to `Nothing` and
`solveOutput` fails for the entire edge — including the fields that *do* invert and even fields
that are not command slots at all. There is no partial recovery: one derived field poisons the
whole event. The practical consequence for a consumer was severe. An aggregate with even one
state-resolved `previous*` field — an event field carrying a register's prior value resolved on
the write path rather than copied from the user command — drags the *entire* aggregate into the
Direction-A mirror-command workaround described below, because that one field cannot be
inverted from the user command. Rei's Reminder aggregate (whose `ReminderRescheduled` event
carries `previousScheduledFor`) and Disruption aggregate (whose `DisruptionDescriptionUpdated`
event carries `previousDescription`) are exactly this case: each is event-mirrored wholesale
through a dedicated stream command precisely because one `previous*` field cannot round-trip.
The page must state this "one field poisons the whole edge" semantics explicitly, and note
that the sibling plan
`docs/plans/47-recompute-and-verify-derived-event-outputs-in-solveoutput-replay.md` removes it
by recomputing and verifying derived output fields on replay, so a single derived field no
longer kills the edge.

Two facts about scope and failure mode that the page must state, both verifiable in
`src/Keiki/Core.hs`:

First, the failure is a plain `Nothing`. It is not an exception and there is no named error
type. A repo-wide search for the string `HydrationReplayFailed` finds zero hits in keiki's
Haskell source (the only matches are in
`docs/masterplans/13-keiki-api-improvements-surfaced-by-the-rei-migration.md`, which itself
states the symbol is not keiki's). `HydrationReplayFailed` belongs to the keiro/Rei runtime,
which converts keiki's `Nothing` into that named error. The page must attribute it correctly
so the next consumer does not search keiki for a symbol that is not there.

For a consumer reaching keiki *through the keiro runtime*, the page should add a short
debugging note disambiguating the keiro-side errors, because they are easy to confuse and a
consumer chasing one will look in the wrong place for the others. In keiro's
`src/Keiro/Command.hs` the hydration path can fail three distinct ways. The inversion `Nothing`
from `solveOutput` (this contract) surfaces as `HydrationReplayFailed` — keiro's
`applyEvent` maps a `Nothing` from `applyEventStreaming` straight to that error. But the *same*
named error `HydrationReplayFailed` is *also* raised when replay finishes with the aggregate
still in a non-final `InFlight` state (`finishReplay` rejects a final `InFlight` as a
mid-chain truncation, distinct from any inversion failure), and a third, *separate* error
`HydrationDecodeFailed` is raised when the recorded JSON bytes fail to decode (a codec failure,
nothing to do with inversion). So a consumer debugging a replay failure should confirm which
case they are in: the inversion `Nothing` documented here, versus a final-`InFlight`
truncation, versus a `HydrationDecodeFailed` codec error. Only the first is governed by this
page.

Second, the restriction is *output-only*. Replay re-runs each edge's guard and update
*forward* using `evalTerm` (`src/Keiki/Core.hs`, around lines 728–737), which handles every
`Term` shape including `TApp1`, `TApp2`, and `TArith`. Only the *output* expression is
inverted, and only the inverse direction (`stepOne`) rejects the opaque shapes. Therefore a
`TApp` or arithmetic term in a guard or in a register update replays without trouble; it is
only when such a term appears in an event's payload field that round-tripping breaks. The
page must make this scoping explicit, because the natural fear — "I can never use a function
in my aggregate" — is wrong.

Beside `solveOutput` sits the build-time safety net: `checkHiddenInputs` in
`src/Keiki/Core.hs` (around lines 1104–1197). It walks every edge of a transducer and reports
a `HiddenInputWarning` when the output cannot mechanically recover the command — for example,
when an output leaves a command-constructor slot unvisited, or when an ε-edge (an edge that
emits no event) nonetheless reads the command in its update. "Build-time" here means it runs
when you evaluate the transducer in a test or build step, not at runtime on the per-event
path; the existing `docs/guide/symbolic-ci.md` describes how teams wire such checks into CI
(continuous integration). The page should name `checkHiddenInputs` as the static net that
catches the mistake early, before any event is replayed in production.

Why the register-read case matters so much for audit fields: an *audit field* is an event
field that records the value a register held *before* this edge changed it — for example a
`previousStatus` or `previousBalance` field. Because `solveOutput` is handed the register file
*as it was before the update* (you can see this at the call site `applyEvent`, around line
886: it calls `solveOutput o regs co` and only afterwards applies the edge's update to `regs`),
an audit field written as a plain register read (`#someSlot` / `proj`) recovers correctly on
replay — `stepOne (TReg _) = Just []`. Rei hit the invertibility wall only because they wrote
such fields as *derived* expressions (a `TApp` over the register) instead of a plain read. The
page must say, in so many words: reach for a register read first for audit fields.

The currently-portable workaround for an event that genuinely must carry a *derived* value
(say, a computed total) is what the master plan calls "Direction A": define a command that
*mirrors the event verbatim*, so the edge's output is a `TInpCtorField` (a plain command-field
copy) and therefore inverts. The cost is a doubled command vocabulary — you add a command
whose only job is to carry the already-computed value. This is today's escape, and the page
documents it as such while forward-pointing to
`docs/plans/47-recompute-and-verify-derived-event-outputs-in-solveoutput-replay.md`, which
will relax the contract so derived output fields round-trip by being *recomputed and verified*
on replay, removing the need for the mirror command.

Real, compiling examples exist in `jitsurei/src/Jitsurei/` (the worked-examples package; its
sources are listed in `keiki.cabal`). The page's snippets must mirror these, not invent
syntax. The ones this plan cites:

- An audit field fed by a register read that round-trips today:
  `jitsurei/src/Jitsurei/UserRegistration.hs`, the `AccountConfirmed` edge (around line 309),
  whose `emit` sets `email = #email` — the event copies the registered email straight from a
  register. The same file's `ConfirmationResent` and `AccountDeleted` edges (around lines 320
  and 336) do the same with `email = #email`.
  `jitsurei/src/Jitsurei/LoanApplication.hs`'s `ApplicationWithdrawn` edge (around line 466)
  sets `applicantId = #appApplicantId`, again a register read in the payload.
- A command-field copy that round-trips today: nearly every edge in
  `jitsurei/src/Jitsurei/OrderCart.hs` (for example the `ItemAdded` edge around line 385,
  whose payload is `sku = d.sku`, `quantity = d.quantity`, etc. — all `d.field` command
  projections).
- An opaque/derived output field that does *not* round-trip today: the `assignment` field in
  `jitsurei/src/Jitsurei/CoreBankingSync.hs` (around line 209) is built with
  `TApp2 buildAssign d.loanId d.legacyLoanId`; and the `onHand` field of the
  `ReorderTriggered` event in `docs/guide/deriving-lifecycle-transitions.md` §4 is the derived
  arithmetic term `#onHand .- d.quantity` (a `TArith`). Both are exactly the shapes `stepOne`
  rejects.
- A *computed operand inside a guard* — which is fine, because guards are not inverted:
  `jitsurei/src/Jitsurei/LoanApplication.hs`'s `approvalGuard` (around lines 431–436) uses
  `proj #appRequestedAmount .<= proj #appCreditScore .* lit 1000`. That `.*` is structural
  `TArith` inside a guard; it replays via `evalTerm` and is also visible to the solver. It is a
  good illustration that arithmetic belongs in guards and updates freely, and only outputs are
  restricted.

The modeling redirects the page carries — for the requests the parent master plan deliberately
rejected — must be stated as positive guidance pointing at existing guides:

(a) Numeric or date *bounds* belong in a structural ordering guard (a `PCmp` comparison over a
curated ordered type; `UTCTime`, the standard timestamp type, is curated, meaning the solver
understands its ordering). No escape hatch is needed. Point readers at
`docs/guide/why-smt.md` §5 (which lists the curated types and says a bare or computed bound
needs no escape) and `docs/guide/symbolic-ci.md`.

(b) A three-way (or N-way) conditional is *multiple disjoint guarded edges*, not one opaque
application that picks a branch. Point readers at `docs/guide/deriving-lifecycle-transitions.md`,
which works exactly this split-into-disjoint-edges pattern.

(c) A *computed operand* (a weighted sum, a derived cap) is structural arithmetic — `tadd`/
`tsub`/`tmul`, written `.+`/`.-`/`.*` — which has been solver-visible since the EP-43 work
recorded in `docs/masterplans/12-symbolic-arithmetic-terms-translator-memoization-and-real-boolalg-sat-witnesses.md`.
Point readers at `docs/guide/user-guide.md` §3.4, which documents these operators.

(d) Map or collection *membership* is the one genuine gap. The faithful direction is the
on-roadmap *structural collection-content guards* (`PMember` / `PAll`), described in
`docs/masterplans/12-symbolic-arithmetic-terms-translator-memoization-and-real-boolalg-sat-witnesses.md`
and `docs/research/collection-registers-design.md` — *not* a higher-arity `TApp`, which would
re-introduce an opaque, non-invertible, solver-blind term. This guidance is forward advice for
the next consumer, not a description of something Rei shipped: validation against Rei's ported
transducers found that the date-bounds and map-membership *guards* (and the 3-way conditional)
that the master plan's request item #3 attributed to Cycle *do not exist* in Rei's code —
Direction A moved them to the (deferred) application layer, so the keiki transducers never
carried them. The page must keep the general structural-guard guidance above (bounds → a
structural `PCmp` over a curated ordered type; multi-way branching → disjoint guarded edges;
computed operands → structural arithmetic `tadd`/`tsub`/`tmul`) as forward advice, but must
*not* present those non-existent guards as if Rei had shipped them. The one residual #3
ergonomic that *is* real in Rei is different and milder: it is a collection-register *update*
that threads a `(map, key, value)` triple to a `Map.insert` helper, written as a nested
`TApp2 (,)` because `TApp` is capped at two arguments. The only two occurrences in all of Rei
are `B.slot @"dailyFocuses" .= TApp2 insertFocus curDailyFocuses (TApp2 (,) … d.focusId)` in
`rei-core/src/Rei/Modules/Cycle/Domain/Transducer.hs` (around lines 208–228) and
`B.slot @"values" .= TApp2 insertValue curValues (TApp2 (,) d.propertyId d.value)` in
`rei-core/src/Rei/Modules/CustomProperty/Domain/PropertyAssignmentTransducer.hs` (around lines
219 and 232). Both are register *updates*, never guards and never outputs, so they replay
forward via `evalTerm` and never break inversion. The faithful fix for this ergonomic is the
collection-registers roadmap (`docs/research/collection-registers-design.md` and
`docs/masterplans/12-symbolic-arithmetic-terms-translator-memoization-and-real-boolalg-sat-witnesses.md`),
which would let a register hold a collection and accept a structural insert directly — *not* a
higher-arity `TApp`. The page should note this residual tuple-threading accurately and route it
to that roadmap.

(e) A multi-argument command should be modeled as a *single named-record payload*, because
keiki's symbolic alphabet projects command fields *by name*: an `InCtor`'s slots are
`(Symbol, Type)` pairs (a field name paired with its type). Splitting one logical command into
several positional arguments fights that name-based projection. This pattern is pervasive and
validated in Rei, and the page should document the concrete idiom rather than just the
principle. A multi-argument command such as `UpdateFoo !FooId !FooData` is modeled as a
*single named-record command* carrying only `FooData`; the dropped id is *sourced from a
register on emit* — the edge reads it back from state with a register read. Rei's Focus
aggregate does exactly this: the logical `UpdateFocus !FocusId !UpdateFocusData` is the single
record command `UpdateFocus !UpdateFocusData` (`rei-core/src/Rei/Modules/Focus/Domain/Command.hs`),
and the `FocusUpdated` edge emits `focusId = curFocusId`, where `curFocusId` is the register
read `proj (indexOf @"focusId" @FocusRegs @FocusId)` from the `FocusRegs` register file
(`rei-core/src/Rei/Modules/Focus/Domain/Transducer.hs`, around lines 124–125 and 181–197). The
page should present this — single record command plus reading the dropped id back from state
via a register read — as the faithful answer, because the symbolic alphabet projects fields by
name and a register read is an accepting (invertible) output term.

This plan's parent is
`docs/masterplans/13-keiki-api-improvements-surfaced-by-the-rei-migration.md`. Sibling plans
are referenced only by file path:
`docs/plans/47-recompute-and-verify-derived-event-outputs-in-solveoutput-replay.md` (which
will amend the new page to the relaxed contract) and
`docs/plans/50-mermaid-renderer-atlas-entry-point-and-structural-edge-summary-annotations.md`
(which keeps the Mermaid diagram renderer's default edge label guard-free).


## Plan of Work

The work is entirely in `docs/`. It proceeds in three milestones. Each writes prose into
Markdown files using the *guides' house style* — within an actual guide page, fenced code
blocks (triple-backtick) and Markdown tables are fine and match the surrounding files
(`docs/guide/user-guide.md` uses both freely). That house style is separate from the
formatting rules for *this plan file*, which uses four-space-indented blocks. Do not confuse
the two: snippets you paste into the guide pages use the guides' fenced style; snippets in
this plan use four-space indentation.

There is no automated docs tooling in this repository. `keiki.cabal` declares one test suite,
`keiki-test` (sources under `test/`, entry `test/Spec.hs`), and it contains no doctest,
markdown-lint, link-checker, or guide-golden module — the `other-modules` list is all `*Spec`
Haskell modules and fixtures, and no build or CI step reads `docs/`. Therefore docs are
validated by *manual review against the cited source symbols*: a claim on the page is correct
if and only if the named symbol in `src/Keiki/Core.hs` still behaves as the claim says. Any
code snippet that appears on the new page must be copied (or minimally trimmed) from a real,
compiling edge in `jitsurei/src/Jitsurei/`, with the source file and edge named, so a reader
can open that file and confirm it compiles as part of the `jitsurei` package.


### Milestone M1 — the contract page

Scope: create the new file `docs/guide/output-invertibility.md` and write its core contract
sections. At the end of this milestone the page exists and states five things, each matching
the cited code in `src/Keiki/Core.hs`: (1) the exact accept/reject term list — `TLit`, `TReg`,
and a matching-constructor `TInpCtorField` invert; a non-matching `TInpCtorField`, `TApp1`,
`TApp2`, and `TArith` cause `solveOutput` to return `Nothing`; (2) that the failure is an
ordinary `Maybe`/`Nothing` and *not* an exception, with the explicit note that the named error
`HydrationReplayFailed` is the keiro/Rei runtime's, not keiki's, and a short disambiguation of
keiro's three hydration failures (the inversion `Nothing` documented here, a final-`InFlight`
mid-chain truncation, and a `HydrationDecodeFailed` codec error — all in keiro's
`src/Keiro/Command.hs`), so a consumer confirms they are debugging the inversion case; (3) that
the failure is *all-or-nothing per edge* — a single non-invertible field makes
`gatherInpEntries`/`solveOutput` return `Nothing` for the *whole* edge, including fields that
do invert and fields that are not command slots, so one derived field poisons the entire event;
(4) that the restriction is output-only — guards and updates may use any term shape because
replay re-runs them forward via `evalTerm`; and (5) that `checkHiddenInputs` is the build-time
net that flags the problem early.

Write the page so that the parts describing present-day behavior are clearly headed as
"today's behavior" (for example, a section titled "What inverts today" and an admonition line
such as "This section describes keiki's behavior as of this writing; the sibling plan
`docs/plans/47-recompute-and-verify-derived-event-outputs-in-solveoutput-replay.md` will relax
it"). This deliberate marking is what lets EP-47 amend the page with a clean, localized edit
rather than a rewrite.

The page should open with a one-paragraph statement of the contract a reader can apply
immediately: "An event round-trips on replay if and only if every field of its payload is a
literal, a register read, or a copy of a field from the *same* command constructor. If any
payload field applies a Haskell function (`TApp1`/`TApp2`) or does structural arithmetic
(`TArith`), `solveOutput` returns `Nothing` and that event cannot be replayed from the log
alone." Then a short "How to predict it" recipe: look at each `Term` on the right of a field in
the edge's `B.emit`; if they are all `lit …`, `#slot`/`proj …`, or `d.field` reads of the
command this `onCmd` matches, the event round-trips; if any is `TApp1`/`TApp2` or uses
`.+`/`.-`/`.*` (`TArith`), it does not.

The accept/reject list on the page must mirror `stepOne` in `src/Keiki/Core.hs` (around lines
1064–1071) exactly. To keep the page honest, paste the small accept/reject table as a fenced
block on the page and state the function and line it mirrors, so a reviewer can diff the two.

Commands to run for M1: from the repository root,

    cd /Users/shinzui/Keikaku/bokuno/keiki
    ls docs/guide/output-invertibility.md
    grep -n "stepOne" src/Keiki/Core.hs

Acceptance: `ls` shows the file exists; the page's accept/reject statements line up with the
`stepOne` clauses the `grep` points at; the page names `solveOutput`, `gatherInpEntries`/
`stepOne`, `evalTerm`, `checkHiddenInputs`, and `applyEvent` by name and by file
(`src/Keiki/Core.hs`); the page states the `Nothing`-not-exception and `HydrationReplayFailed`
attribution; the page states the all-or-nothing-per-edge semantics (one non-invertible field
poisons the whole edge); and the page disambiguates keiro's three hydration failures so a
consumer can confirm they are debugging the inversion `Nothing` documented here.


### Milestone M2 — the worked recipes

Scope: add a "Recipes" section to `docs/guide/output-invertibility.md` containing three worked
items. At the end of this milestone a reader who has a "this event stores a derived value"
situation can read the matching recipe and act.

The first recipe is the audit / `previous*` field. State that an event field recording a
register's prior value round-trips *today* with no special handling, because `solveOutput`
runs against the pre-update register file and a register read is an accepting term. Show the
real example from `jitsurei/src/Jitsurei/UserRegistration.hs`'s `AccountConfirmed` edge
(around line 309), whose `emit` carries `email = #email`, and explain that `#email` resolves to
a `TReg` read which `stepOne` accepts. Add the one-line guidance: "Reach for a register read
(`#slot` / `proj`) first for audit fields — do not wrap it in a function." Cite that the
pre-update timing is visible at the `applyEvent` call site in `src/Keiki/Core.hs` (around line
886), which calls `solveOutput o regs co` before applying the update.

The second recipe is the computed total via the Direction-A mirror command. State the wall
first: an event whose payload field is a derived value — for instance built with `TApp2`, as in
`jitsurei/src/Jitsurei/CoreBankingSync.hs`'s `assignment = TApp2 buildAssign d.loanId
d.legacyLoanId` (around line 209), or with arithmetic, as in the `ReorderTriggered` event's
`onHand = #onHand .- d.quantity` in `docs/guide/deriving-lifecycle-transitions.md` §4 — makes
`solveOutput` return `Nothing`, so that event cannot be replayed from the log alone today.
State the all-or-nothing cost plainly here too: because the inversion is per-edge, that *one*
derived field poisons the whole edge, so an aggregate with even a single state-resolved
`previous*` field is dragged into this workaround wholesale — exactly what Rei's Reminder
(`previousScheduledFor`) and Disruption (`previousDescription`) aggregates do, mirroring the
entire event through a dedicated stream command because one field cannot invert. Then give the
portable workaround: introduce a command that mirrors the event's payload verbatim, so the edge
emits a plain `d.field` copy (a `TInpCtorField`) that inverts; note the cost is a doubled
command vocabulary (you add a carry-only command). Mark this as today's escape and
forward-point to
`docs/plans/47-recompute-and-verify-derived-event-outputs-in-solveoutput-replay.md`, which will
let derived fields round-trip by recomputing and verifying them on replay, removing the need
for the mirror — and with it the all-or-nothing penalty, since a single derived field would no
longer kill the edge.

The third recipe is a clear, standalone statement of *what fails and why*: the inversion is
structural and per-field; an opaque application has no inverse keiki can compute, and an
arithmetic output term is not inverted (subtraction or multiplication is not uniquely
reversible from the result alone), so both are rejected outright by `stepOne`, aborting the
whole edge's inversion.

Commands to run for M2: from the repository root,

    cd /Users/shinzui/Keikaku/bokuno/keiki
    grep -n "email *= *#email" jitsurei/src/Jitsurei/UserRegistration.hs
    grep -n "TApp2 buildAssign" jitsurei/src/Jitsurei/CoreBankingSync.hs

Acceptance: the page's three recipes are present; each cited `jitsurei` snippet matches the
`grep` output verbatim (so the snippet really compiles as part of `jitsurei`); the audit-field
recipe states it round-trips today and tells the reader to use a register read; and the
computed-total recipe carries the forward pointer to EP-47.


### Milestone M3 — cross-link sweep and modeling redirects

Scope: make the new page reachable and seed the structural redirects. At the end of this
milestone the new page is linked from `docs/guide/user-guide.md`, and the four cited guides
carry short notes that send a reader toward the structural answer and link the new page.

In `docs/guide/user-guide.md`: update the glossary entries in §10.3 ("keiki types and
machinery") for `solveOutput`, `applyEvent`, and `checkHiddenInputs` so each links
`docs/guide/output-invertibility.md`. While there, correct a stale phrasing: the current
`solveOutput` entry calls it "the build-time analysis", but `solveOutput` is the runtime
inverter used by `applyEvent`/`reconstitute`; the *build-time* analysis is `checkHiddenInputs`.
Adjust the `solveOutput` entry to describe it as the mechanical inverse of `omega`/`evalOut`
used on the replay path, and keep "build-time analysis" on the `checkHiddenInputs` entry where
it belongs. Also add a one-line pointer to the new page from §12 ("Where to go from here") or
the §7 ("Symbolic analysis") area so the page is discoverable from the guide's body, not only
the glossary. (See Surprises & Discoveries for the evidence behind the stale-phrasing fix.)

In `docs/guide/why-smt.md`: at the end of §5 ("The catch"), where the existing text already
says a bare or computed bound needs no escape hatch, add a sentence linking
`docs/guide/output-invertibility.md` for the dual concern — that the same opaque `TApp` shapes
that weaken the solver gate also block output inversion — and state redirect (a): numeric/date
bounds belong in a `PCmp` ordering guard over a curated type (`UTCTime` is curated), no escape
needed.

In `docs/guide/deriving-lifecycle-transitions.md`: add a short note (a sensible place is near
§4, where the `ReorderTriggered` event already carries the derived `onHand = #onHand .-
d.quantity` output) stating redirect (b): a multi-way decision is multiple disjoint guarded
edges, and linking `docs/guide/output-invertibility.md` so a reader who notices the derived
output field there learns it does not round-trip today. When you add this link, also note —
per the integration point below — that the Mermaid renderer's default edge label is
deliberately guard-free (the file already says so near its top, around lines 31–32) and that
the sibling plan
`docs/plans/50-mermaid-renderer-atlas-entry-point-and-structural-edge-summary-annotations.md`
keeps that default guard-free; do not imply the diagram should start showing guards.

In `docs/guide/symbolic-ci.md`: add a pointer in its §9 ("Pointers") to
`docs/guide/output-invertibility.md`, framing `checkHiddenInputs` as the build-time net for
the invertibility contract alongside the single-valuedness gate the guide already covers.

The redirects (c), (d), and (e) live primarily on the new page itself (it is the natural home
for "the master plan rejected X; do Y instead"): (c) computed operands are structural
arithmetic, linking `docs/guide/user-guide.md` §3.4; (d) collection membership is the
on-roadmap structural collection-content guards `PMember`/`PAll`, linking
`docs/masterplans/12-symbolic-arithmetic-terms-translator-memoization-and-real-boolalg-sat-witnesses.md`
and `docs/research/collection-registers-design.md`, explicitly *not* a higher-arity `TApp` —
and the page must keep this as forward advice rather than presenting the master plan's claimed
Cycle date-bounds/map-membership guards as shipped, because validation found those guards do
not exist in Rei's transducers (Direction A moved them to the deferred application layer); the
page should instead note the *real* residual #3 ergonomic, the collection-register *update*
that threads a `(map, key, value)` triple via nested `TApp2 (,)` to a `Map.insert` helper (the
two occurrences are in `rei-core/src/Rei/Modules/Cycle/Domain/Transducer.hs` and
`rei-core/src/Rei/Modules/CustomProperty/Domain/PropertyAssignmentTransducer.hs`, both register
updates that never break inversion), and route that ergonomic to the collection-registers
roadmap rather than to a higher-arity `TApp`; and (e) a multi-argument command is one
named-record payload with the dropped id read back from a register on emit, because the
alphabet projects fields by name (`InCtor`'s slots are `(Symbol, Type)` pairs) — citing Rei's
Focus aggregate, where `UpdateFocus !FocusId !UpdateFocusData` becomes the single record
`UpdateFocus !UpdateFocusData` and the edge emits `focusId = curFocusId` from the `FocusRegs`
register.

Commands to run for M3: from the repository root,

    cd /Users/shinzui/Keikaku/bokuno/keiki
    grep -rn "output-invertibility" docs/guide/

Acceptance: the `grep` shows `docs/guide/output-invertibility.md` referenced from
`docs/guide/user-guide.md`, `docs/guide/why-smt.md`,
`docs/guide/deriving-lifecycle-transitions.md`, and `docs/guide/symbolic-ci.md`; the new page
itself carries redirects (a)–(e), each pointing at a structural answer in an existing guide,
master plan, or research note; and the user-guide glossary entries for `solveOutput`,
`applyEvent`, and `checkHiddenInputs` link the new page (with the `solveOutput`/`checkHiddenInputs`
roles stated correctly).


## Concrete Steps

All commands run from the repository root, `/Users/shinzui/Keikaku/bokuno/keiki`. Because the
shell's working directory resets between invocations in some environments, each command line
below `cd`s first.

Before writing anything, re-verify the ground truth so the page is accurate (line numbers may
have drifted; trust the symbol names, not the numbers):

    cd /Users/shinzui/Keikaku/bokuno/keiki
    grep -n "solveOutput\|gatherInpEntries\|stepOne\|checkHiddenInputs\|evalTerm" src/Keiki/Core.hs

Expected (abridged) — the function signatures and the accept/reject clauses appear; the
exact lines may differ:

    solveOutput :: OutTerm rs ci co -> RegFile rs -> co -> Maybe ci
    stepOne (TLit _)               _val _   = Just []
    stepOne (TReg _)               _val _   = Just []
    stepOne (TInpCtorField ic2 ix) val  ic1 ...
    stepOne (TApp1 _ _)            _val _   = Nothing
    stepOne (TApp2 _ _ _)          _val _   = Nothing
    stepOne (TArith _ _ _)         _val _   = Nothing

Confirm `HydrationReplayFailed` is not a keiki symbol (expected: matches only in the master
plan doc, none in `src/`):

    cd /Users/shinzui/Keikaku/bokuno/keiki
    grep -rn "HydrationReplayFailed" src/ docs/guide/ ; echo "exit: $?"

M1: create `docs/guide/output-invertibility.md` and write the contract sections described in
the Plan of Work. Then confirm it exists:

    cd /Users/shinzui/Keikaku/bokuno/keiki
    ls -l docs/guide/output-invertibility.md

M2: append the three recipes, citing the real `jitsurei` edges. Re-check those snippets still
exist verbatim:

    cd /Users/shinzui/Keikaku/bokuno/keiki
    grep -n "email *= *#email" jitsurei/src/Jitsurei/UserRegistration.hs
    grep -n "TApp2 buildAssign" jitsurei/src/Jitsurei/CoreBankingSync.hs
    grep -n "onHand = #onHand .- d.quantity" docs/guide/deriving-lifecycle-transitions.md

Expected: each `grep` prints at least one line; if any prints nothing the example has moved
and the page must be updated to a current edge before proceeding.

M3: edit the four guides and confirm the new page is reachable:

    cd /Users/shinzui/Keikaku/bokuno/keiki
    grep -rln "output-invertibility" docs/guide/

Expected output (order may vary):

    docs/guide/output-invertibility.md
    docs/guide/user-guide.md
    docs/guide/why-smt.md
    docs/guide/deriving-lifecycle-transitions.md
    docs/guide/symbolic-ci.md

Optional final sanity check — the worked-examples package still compiles, proving the cited
snippets are valid (no docs are compiled, but this guards against citing a snippet from a file
that no longer builds). Use the project's configured toolchain:

    cd /Users/shinzui/Keikaku/bokuno/keiki
    cabal build jitsurei

Expected: the build succeeds (`Up to date` or a successful compile). This is a confidence
check on the citations, not a docs test.


## Validation and Acceptance

This is a documentation change, and this repository has no automated docs tooling: `keiki.cabal`
declares a single test suite (`keiki-test`, sources under `test/`) made entirely of `*Spec`
Haskell modules and fixtures, with no doctest, markdown-lint, link-check, or guide-golden
module, and no build step reads `docs/`. Validation is therefore by *manual review against the
cited source symbols* plus a small reader-simulation. The acceptance test is behavioral in the
sense that matters for docs: a reader following the page can correctly *predict* round-trip
outcomes, and the cited symbols still behave as the page says.

The decisive end-to-end check is the prediction exercise. Open the page and read its "How to
predict it" recipe. Then open `jitsurei/src/Jitsurei/UserRegistration.hs` and look at the
`AccountConfirmed` edge (around line 309): its payload is `email = #email`, `confirmCode =
d.confirmCode`, `at = d.at` — a register read and two command-field copies. The page must
predict: round-trips. Confirm against the code that `stepOne` accepts `TReg` and a matching
`TInpCtorField` (`src/Keiki/Core.hs`, the `stepOne` clauses around lines 1064–1071), so the
prediction is correct. Next open `jitsurei/src/Jitsurei/CoreBankingSync.hs` and look at the
`LegacyAssignmentCommanded` edge (around line 208): its `assignment` field is `TApp2
buildAssign d.loanId d.legacyLoanId`. The page must predict: does *not* round-trip today.
Confirm against `stepOne (TApp2 _ _ _) = Nothing`. If both predictions match what the code
does, the page is sound.

Concrete acceptance, per milestone:

M1 acceptance — `ls docs/guide/output-invertibility.md` succeeds; the page's accept/reject
statements correspond clause-for-clause with `stepOne` in `src/Keiki/Core.hs`; the page states
the failure is `Nothing` (not an exception) and that `HydrationReplayFailed` is the keiro/Rei
runtime's, not keiki's; the page states the output-only scoping and names `evalTerm` as the
forward evaluator that handles all term shapes in guards/updates; and the page names
`checkHiddenInputs` as the build-time net.

M2 acceptance — the three recipes are present; the audit-field recipe states the field
round-trips today and directs the reader to a register read, with the pre-update timing cited
to the `applyEvent` call site (`src/Keiki/Core.hs` around line 886); the computed-total recipe
shows the Direction-A mirror-command escape and forward-points to
`docs/plans/47-recompute-and-verify-derived-event-outputs-in-solveoutput-replay.md`; and every
pasted `jitsurei` snippet matches the corresponding `grep` output from the Concrete Steps
verbatim.

M3 acceptance — `grep -rln "output-invertibility" docs/guide/` lists the new page plus
`user-guide.md`, `why-smt.md`, `deriving-lifecycle-transitions.md`, and `symbolic-ci.md`; the
new page carries redirects (a)–(e) each pointing at a structural answer; and the user-guide
glossary entries for `solveOutput`, `applyEvent`, and `checkHiddenInputs` link the new page,
with `solveOutput` described as the runtime inverter and `checkHiddenInputs` as the build-time
analysis.

Optional confidence check beyond review: `cabal build jitsurei` (from the repository root)
succeeds, confirming the cited example edges still compile in the `jitsurei` package declared
in `cabal.project`.


## Idempotence and Recovery

Every step here is safe to repeat. Creating `docs/guide/output-invertibility.md` is idempotent:
re-running M1 overwrites the same file with the same content. The guide edits in M3 are
additive — short notes and links appended into existing sections — so re-applying them risks
only a duplicated link, which a reviewer (or a `grep` for the page name showing two hits in one
file) catches immediately; if a duplicate slips in, delete the extra line. No source code,
build artifact, or test fixture is touched, so there is nothing to migrate and no runtime state
to corrupt.

If you need to back out the whole change, it is confined to one new file plus localized edits
in four guides; `git checkout -- docs/guide/` (or deleting the new file and reverting the four
guide edits) restores the prior state. Because the contract being documented already governs
the code, reverting the docs cannot break any build or test.

If an example citation goes stale mid-implementation (a `grep` from Concrete Steps prints
nothing because an edge moved or was renamed), do not invent a snippet: open the cited
`jitsurei` file, find a current edge of the same shape (a register-read payload field for the
audit recipe; a `TApp`/`TArith` payload field for the does-not-round-trip example), cite that
one instead, and record the substitution in the Decision Log.


## Interfaces and Dependencies

This plan adds no Haskell dependencies and changes no module interface. It only describes,
accurately, symbols that already exist in `src/Keiki/Core.hs`. The page must reference these
exactly, and they must keep behaving as documented for the page to remain correct:

- `solveOutput :: OutTerm rs ci co -> RegFile rs -> co -> Maybe ci` — the runtime inverter; the
  contract's center. (`src/Keiki/Core.hs`, around line 1039.)
- `gatherInpEntries` and its inner `stepOne` — the per-field accept/reject site whose clauses
  are the authoritative accept/reject list. (`src/Keiki/Core.hs`, around lines 1054–1071.)
- `evalTerm :: Term rs ci r -> RegFile rs -> ci -> r` — the forward evaluator that handles
  every term shape, establishing that the restriction is output-only (guards/updates replay
  fine). (`src/Keiki/Core.hs`, around lines 728–737.)
- `applyEvent` / `applyEventStreaming` — the replay-step callers of `solveOutput`; the
  `applyEvent` call site (around line 886) is where you can see `solveOutput` runs against the
  pre-update register file. (`src/Keiki/Core.hs`, around lines 882–966.)
- `checkHiddenInputs :: SymTransducer phi rs s ci co -> [HiddenInputWarning]` — the build-time
  static net. (`src/Keiki/Core.hs`, around lines 1104–1197.)

The artifacts this plan produces or touches: the new file
`docs/guide/output-invertibility.md` (created in M1, extended in M2 and M3); and short
additive edits to `docs/guide/user-guide.md`, `docs/guide/why-smt.md`,
`docs/guide/deriving-lifecycle-transitions.md`, and `docs/guide/symbolic-ci.md` (M3). The
worked snippets are sourced from `jitsurei/src/Jitsurei/UserRegistration.hs`,
`jitsurei/src/Jitsurei/LoanApplication.hs`, `jitsurei/src/Jitsurei/OrderCart.hs`, and
`jitsurei/src/Jitsurei/CoreBankingSync.hs`, all in the `jitsurei` package declared in
`cabal.project`.

Two integration points to respect, both with sibling plans referenced by path only:

First, `docs/guide/output-invertibility.md` is a *shared artifact* with
`docs/plans/47-recompute-and-verify-derived-event-outputs-in-solveoutput-replay.md`. EP-47's
final milestone will *amend* this same page to document the relaxed recompute-and-verify
contract (under which derived output fields round-trip by being recomputed and equality-checked
on replay, an idea EP-47 implements in `solveOutput`/`gatherInpEntries` and may introduce an
`Eq co` requirement for). Write M1 and M2 so the "today's behavior" sections are clearly
headed and self-contained, so EP-47's amendment is a localized edit (replace or follow the
marked sections) rather than a rewrite. Neither plan may let this page silently diverge from
the code: EP-46 documents current behavior; EP-47 updates the page in lockstep with its code
change. EP-46 does not modify any `src/` symbol; EP-47 owns all edits to `solveOutput` and its
helpers.

Second, when M3 cross-links `docs/guide/deriving-lifecycle-transitions.md`, respect that this
guide relies on the Mermaid diagram renderer `Keiki.Render.Mermaid` (module
`src/Keiki/Render/Mermaid.hs`) *deliberately omitting the guard from edge labels* — the guide
states this near its top (around lines 31–32), and the default label format is `Command /
Event`. The sibling plan
`docs/plans/50-mermaid-renderer-atlas-entry-point-and-structural-edge-summary-annotations.md`
keeps that guard-free default (any guard summary it adds is opt-in). So the M3 note must not
suggest the diagram should begin showing guards; it should only point a reader who notices a
derived output field in that guide's §4 example toward the invertibility page.


## Revision Note — 2026-05-21 (validation against consumer Rei and runtime keiro)

This revision folds in three corrections validated against live source in
`../rei-project/rei.keiro-migration` (the consumer) and `../keiro` (the runtime), plus a
consumer-facing debugging note. No source code is touched and no `src/` symbol changes; the
plan still documents today's behavior and forward-points to EP-47. The frontmatter, the
milestone count (still three), and the Progress checklist are unchanged.

What changed and why:

First, the failure semantics were strengthened to *all-or-nothing per edge* (Purpose, Context,
M1 scope and acceptance, M2 second recipe, Decision Log). `gatherInpEntries` folds `stepOne`
across every output field, so a *single* non-invertible field makes `solveOutput` return
`Nothing` for the *whole* edge — including fields that do invert and fields that are not command
slots. The consumer consequence is concrete and severe: an aggregate with even one
state-resolved `previous*` field is dragged wholesale into the Direction-A mirror-command
workaround. Rei's Reminder (`ReminderRescheduled.previousScheduledFor`) and Disruption
(`DisruptionDescriptionUpdated.previousDescription`) aggregates are exactly this case and are
each event-mirrored through a dedicated stream command for that reason. EP-47 removes this
penalty, so the page forward-points to it. The original plan implied a per-field outcome; this
corrects it to the wholesale-edge-failure semantics a consumer actually hits.

Second, modeling redirect (d) was re-anchored (Context, M3 redirects summary, Decision Log).
Validation found the master plan's claimed Cycle date-bounds and map-membership *guards* and the
3-way conditional *do not exist* in Rei's ported transducers — Direction A moved them to the
deferred application layer, so the keiki transducers never carried them. The general
structural-guard guidance is kept strictly as forward advice for the next consumer (bounds → a
structural `PCmp` over a curated ordered type; multi-way branching → disjoint guarded edges;
computed operands → `tadd`/`tsub`/`tmul`), but an accurate note now records the *real* residual
#3 ergonomic: a collection-register *update* threading a `(map, key, value)` triple via nested
`TApp2 (,)` to a `Map.insert` helper. Its only two occurrences in all of Rei are in
`rei-core/src/Rei/Modules/Cycle/Domain/Transducer.hs` and
`rei-core/src/Rei/Modules/CustomProperty/Domain/PropertyAssignmentTransducer.hs` — both register
updates, never a guard, never an output, never breaking replay — and it is routed to the
collection-registers roadmap (`docs/research/collection-registers-design.md`,
`docs/masterplans/12-...`), not to a higher-arity `TApp`. The page must not present the
non-existent guards as if Rei shipped them.

Third, modeling redirect (e) was strengthened with the concrete, validated Rei idiom (Context,
M3 redirects summary, Decision Log). A multi-argument command like `UpdateFoo !FooId !FooData`
is modeled as a *single named-record command*, and the dropped id is sourced from a register on
emit via a register read. Rei's Focus aggregate does exactly this:
`UpdateFocus !FocusId !UpdateFocusData` is the single record `UpdateFocus !UpdateFocusData`
(`rei-core/src/Rei/Modules/Focus/Domain/Command.hs`) and the `FocusUpdated` edge emits
`focusId = curFocusId`, where `curFocusId = proj (indexOf @"focusId" @FocusRegs @FocusId)`
reads the id back from the `FocusRegs` register (`rei-core/src/Rei/Modules/Focus/Domain/Transducer.hs`).
Because the symbolic alphabet projects fields by name and a register read is an accepting output
term, this round-trips.

Fourth, a consumer-facing debugging note was added (Context, M1 scope and acceptance, Decision
Log). For a consumer reaching keiki through the keiro runtime, the inversion `Nothing` surfaces
as keiro's `HydrationReplayFailed`; this is distinct from `HydrationDecodeFailed` (a JSON codec
failure) and from a final-`InFlight` replay error (mid-chain truncation, which also raises
`HydrationReplayFailed`). All three live in keiro's `src/Keiro/Command.hs`. A consumer debugging
replay should confirm the failure is the inversion `Nothing` governed by this contract, not one
of the others — the original time-sink Rei reported was looking in the wrong place.
