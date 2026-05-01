---
id: 2
slug: sharpen-schema-evolution-for-events-and-registers
title: "Sharpen schema evolution for events and registers"
kind: exec-plan
created_at: 2026-05-01T05:20:18Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
master_plan: "docs/masterplans/1-validate-symbolic-register-direction-via-haskell-prototype.md"
---

# Sharpen schema evolution for events and registers

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

The keiki library is being designed (no code yet) to handle the pure part of event
sourcing, workflow engines, and durable execution. Its core type is the
**symbolic-register transducer**, defined in
`docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`. The
formalism's headline guarantee is that `apply` (the function that replays events to
recover state) is **mechanically derived** from the transducer's edges by walking each
edge's `output` term and inverting it via `solveOutput`.

This guarantee assumes the events being replayed were produced by *the current code*.
Real systems break that assumption: events accumulate over years, code changes, fields
are added, removed, or renamed. Without a deliberate story for how the transducer's
register file, command alphabet, and event alphabet evolve over time, the entire
synthesis is brittle in production.

Before the prototype is built, this plan must settle the **schema-evolution model** the
library commits to. Concretely:

- How are events versioned (or not) on the wire?
- How does a register file change shape over time, and what does that mean for replay?
- Does `solveOutput` need a version-aware variant, or does each historical version get
  its own transducer module?
- How does the build-time **hidden-input check** behave across versions of an event
  schema?
- What is the migration story when a register slot is added, removed, renamed, or
  changes type?

After this plan is complete, a new design note exists at
`docs/research/schema-evolution.md` that pins down the model with rationale, walks
through at least three concrete evolution scenarios on the User Registration aggregate
(field addition, field removal, type change), and lists the precise prototype
implications — what plan 4
(`docs/plans/4-prototype-symbolic-register-core-with-user-registration-smoke-test.md`)
must do or explicitly defer.

The user-visible win: a future contributor knows whether they can safely add a field to
an event without breaking historical replay, what the upgrade path looks like, and
where the library's responsibility ends versus where the application's begins. The
prototype contributor knows whether the v1 prototype must include any
versioning/migration scaffolding or whether all of that can be deferred to v2.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] Re-read the synthesis note (especially §4's "Same hidden-input lesson, again" and
      the "Three clean fixes" passages) and the multi-event commands note, capturing the
      assumptions about event self-sufficiency. (2026-05-01)
- [x] Survey how comparable event-sourcing libraries handle schema evolution: read the
      `crem` source, the `tan-event-source` source, and Greg Young's CQRS/ES essay (via
      `mori`). Note their position on event versioning and replay across versions.
      (2026-05-01 — `crem` and `tan-event-source` not in the local registry; surveyed
      `message-db` and `tan/message-db-hs` in detail and fell back to documentation
      knowledge for the others. Finding noted in the design note's "Comparable
      libraries" section.)
- [x] Enumerate the kinds of schema change a real event-sourced system experiences
      (additive, deletive, rename, type change, semantic change, splitting an event,
      merging events) and rank by frequency. (2026-05-01)
- [x] For each change kind, walk through what happens with the current synthesis design
      (transducer with `output` term and `solveOutput`-derived `apply`) — does replay
      still work? Where does it break? (2026-05-01)
- [x] Survey three model options for handling evolution: (a) **upcasting** (transform
      old events to new shape on read); (b) **versioned transducers** (one transducer
      per historical schema, runtime picks by event version tag); (c) **additive-only
      with optional fields** (events never change shape, only grow). Decide which of
      these the library supports natively and which the library leaves to the
      application. (2026-05-01 — expanded to four options to also cover constructor-name
      versioning.)
- [x] Pin the v1 model with rationale. (2026-05-01 — chose (d) explicit upcaster at the
      boundary combined with (c) additive-only as the default convention.)
- [x] Walk through three User Registration evolution scenarios end-to-end (a field
      added, a field removed, a field's type changed) under the chosen v1 model.
      (2026-05-01 — substituted "register-slot removed" for "field type changed" as
      Scenario B because it exercises snapshot invalidation, which type changes do not
      uniquely expose; added Scenario C for constructor split, the hardest case.)
- [x] Decide how the **hidden-input check** interacts with versioning. If a user has
      both v1 and v2 of an event in their store, does the check run on the union of
      schemas? Per version? (2026-05-01 — runs only against the current schema; the
      upcaster guarantees events arriving at `solveOutput` are current.)
- [x] Decide the `solveOutput` story across versions: is it polymorphic in event
      version, or does each versioned transducer have its own `solveOutput`?
      (2026-05-01 — `solveOutput` is monomorphic in the current `OutTerm`. There is no
      versioned variant because the upcaster runs first.)
- [x] State the prototype implications: what does plan 4 implement, what does it
      explicitly stub, what does it explicitly defer. (2026-05-01 — written as a single
      paragraph plan 4 can copy verbatim.)
- [x] Write the design note at `docs/research/schema-evolution.md`. (2026-05-01)
- [ ] Commit (with `MasterPlan:`, `ExecPlan:`, `Intention:` trailers) and update this
      plan's living sections. (Orchestrator commits serially across all three sibling
      plans; living sections updated 2026-05-01.)


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- **`crem` and `tan-event-source` are not in the local mori registry.** Searched via
  `mori registry search crem` and `mori registry search tan-event-source`; both
  returned "no projects matching". Survey of those libraries proceeded from
  documentation knowledge (noted as such in the design note). The local registry
  *did* yield rich detail on `message-db` (Postgres) and `tan/message-db-hs`,
  which both treat events as opaque JSON with a string `messageType` discriminator
  and ship no upcaster machinery — confirming the industry pattern.

- **The hidden-input check has a second job under evolution.** Originally framed
  as "did you forget to put a field in the event when you wrote the edge?", the
  same check fires under evolution as "did you remove a field from the event but
  forget to remove the edge that read it?". Wording stays the same; the trigger
  context generalises. Cross-cuts plan 1 (DSL shape — the check belongs in the
  DSL surface) and plan 4 (prototype must demonstrate the check firing on the
  unfixed `AccountConfirmed` schema, which already serves as both an
  edge-correctness demo and an evolution-correctness demo).

- **The upcaster must be allowed to be 1-to-many.** Constructor splits (Scenario C)
  cannot be handled by a `WireEvent -> CurrentEvent` upcaster; the contract has
  to be `WireEvent -> Either Error [CurrentEvent]`, with the list ordering
  determining replay order. This affects plan 3 (effects boundary): the
  event-store-read effect must be defined to allow the upcaster to expand a
  single read into multiple events, *transparently* to the runtime loop.

- **Snapshot invalidation is the only evolution mechanism that ever forces full
  replay.** The upcaster covers everything event-shaped; it does not cover
  register-shaped changes (Scenario B). The library's responsibility for
  evolution thus reduces to a single mechanism — snapshot shape-tag mismatch
  triggers full replay — plus a contract — the upcaster contract — that the
  application implements. Cross-cuts plan 4 (prototype): even though the
  prototype assumes a single static schema, computing and storing a
  shape-tag value on snapshots is a one-line addition that future-proofs the
  on-disk format. Worth doing in v1 even though comparison is deferred.

- **Pure semantic change (kind 9 in the change catalog) is fundamentally
  outside the library's reach.** No type-system mechanism, no formalism check,
  no upcaster signature can detect "same fields, different meaning". The only
  defence is a domain-level versioning convention adopted by the application.
  Worth flagging because a future contributor may expect keiki to "handle
  versioning" and discover, when they need it most, that this one case is
  permanently their problem.


## Decision Log

Record every decision made while working on the plan.

- Decision: This plan produces a design note, not Haskell code.
  Rationale: The prototype lives in plan 4
  (`docs/plans/4-prototype-symbolic-register-core-with-user-registration-smoke-test.md`).
  The schema-evolution model is a *direction* the prototype reflects (or explicitly
  stubs) but not the prototype's primary deliverable. Settling it in prose first lets
  the prototype focus on the synthesis-validation question.
  Date: 2026-04-30

- Decision: v1 evolution model is **(d) explicit upcaster at the event-store
  boundary, with (c) additive-only as the default convention**.
  Rationale: keeps the formalism (`SymTransducer`, `Edge`, `OutTerm`,
  `solveOutput`, hidden-input check) version-agnostic; matches the practice of
  every event-sourcing library surveyed (message-db, tan/message-db-hs, and per
  documentation `crem` and `tan-event-source`); keeps the library's
  responsibility small and unambiguous. (a) wire-version tags would force a
  versioned `solveOutput`; (b) constructor-name versioning would grow the
  alphabet forever; (c) alone is too narrow (cannot handle splits, merges, type
  narrowings, register-slot removals). Combining (d) as the mechanism with (c)
  as the convention covers trivial changes for free and gives a single explicit
  hook for hard changes.
  Date: 2026-05-01

- Decision: The upcaster contract is `WireEvent -> Either Error [CurrentEvent]`
  (1-to-many, ordered).
  Rationale: Constructor splits (Scenario C) cannot be handled by a
  `WireEvent -> CurrentEvent` upcaster. The list result allows splits and
  merges (length 1 for every other case). Order in the list determines replay
  order, since the register-file updates from earlier list elements may be read
  by later ones.
  Date: 2026-05-01

- Decision: Hidden-input check runs only against the current schema.
  Rationale: The upcaster guarantees events arriving at `solveOutput` are
  current. There is no notion of "old version" inside the formalism. The check
  gains a new use case under evolution (refactorings that drop a field but
  leave a writer for it) but its definition does not change. A
  compatibility-mode check that audits upcaster targets against historical
  snapshots is a v2 nice-to-have, deferred.
  Date: 2026-05-01

- Decision: `solveOutput` is monomorphic in the current `OutTerm`.
  Rationale: Direct consequence of the upcaster-at-the-boundary decision. No
  versioned variant is needed because the upcaster runs first. Keeps the
  formalism single-version and keeps Veanes-style symbolic equivalence
  decidable on the fragment we live in.
  Date: 2026-05-01

- Decision: Snapshot invalidation rule — snapshots tag the register-file shape
  with a hash (slot labels, slot types, vertex set). On read, mismatched hash
  discards the snapshot and forces full replay through the upcaster.
  Rationale: This is the *only* evolution mechanism the library owns
  outright; it is the only response to register-shape changes (Scenario B),
  which the upcaster cannot fix because the upcaster operates on events, not
  on register files. The application is responsible for snapshot pruning and
  for re-snapshotting after a breaking change to amortise future reads.
  Date: 2026-05-01

- Decision: Library/application split.
  Library owns: `SymTransducer` and friends; the hidden-input check on the
  current schema; the snapshot envelope and shape-hash; the upcaster
  registration hook; the upcaster contract.
  Application owns: the wire event type, the current event type and their
  serialisers; the choice of versioning scheme (wire tag, constructor name,
  none); the upcaster body; the decision to backfill historical events when
  the upcaster cannot disambiguate; the cadence of re-snapshotting; semantic
  versioning entirely (since same-shape, different-meaning changes are
  invisible to the formalism).
  Date: 2026-05-01

- Decision: The v1 prototype scope is a single static schema, no upcasting,
  hidden-input check on current schema only.
  Rationale: Plan 4's job is to validate the *synthesis* (mechanical `apply`
  from edges, the hidden-input check firing). Schema evolution is orthogonal
  and is best validated separately, post-prototype. The single-paragraph
  scoping statement at the end of the design note is what plan 4 copies
  verbatim.
  Date: 2026-05-01

- Decision: Substituted scenarios B and C for the originally-listed "field
  removed / field type changed" pair.
  Rationale: "Field type change" is similar enough to "field addition" under
  the chosen model (both reduce to upcaster work) that walking it separately
  would not exercise a distinct mechanism. "Register-slot removed" (Scenario
  B) is the canonical exercise of the snapshot-invalidation rule; "constructor
  split" (Scenario C) is the canonical exercise of the 1-to-many upcaster.
  Together with Scenario A (field addition with default), the three cover
  every mechanism the model offers. Type narrowing/widening is treated in the
  change-kind catalog (kinds 6 and 7) without a dedicated walkthrough.
  Date: 2026-05-01


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

The plan's purpose was to settle the schema-evolution model before the prototype
is written. It is settled. The chosen model — explicit upcaster at the
event-store boundary, additive-only as the default convention, hidden-input
check on the current schema only, snapshots tagged with a register-file shape
hash — keeps the library formalism single-version (`solveOutput` monomorphic in
the current `OutTerm`) and matches the prevailing pattern in the Haskell
event-sourcing ecosystem (every library surveyed delegates evolution to the
application). The library's surface for evolution is small: a registration hook
for the upcaster, a stated contract on its output, and a shape-hash on
snapshots. The application owns the upcaster body, the choice of versioning
scheme, the deserialisers, and any backfill or re-snapshotting cadence.

The three User Registration scenarios (add `confirmCode`, remove
`registeredAt`, split `ConfirmationResent`) cover every mechanism the model
offers — including the snapshot-invalidation rule and the 1-to-many upcaster
case. The unanswered residual is the "pure semantic change" case (kind 9), for
which no formalism check can help; that limit is documented and is now an
explicit feature of the model rather than an implicit gap.

The v1 prototype scope is stated as a single paragraph that plan 4 copies
verbatim: "v1 prototype assumes a single static schema, implements no upcasting
or versioning machinery, and runs the hidden-input check on the current schema
only." This unblocks plan 4 from any ambiguity about whether evolution
machinery is in scope.

Cross-cutting findings handed to the orchestrator: the upcaster being 1-to-many
affects plan 3's effects-boundary design (the read effect must allow a single
read to expand into multiple events); the hidden-input check's evolution use
case affects plan 1's DSL surface (the check belongs in the DSL); plan 4
should compute and store a snapshot shape-hash even though it does not
compare it (one-line cost, future-proofs the on-disk format).


## Context and Orientation

The keiki repository currently contains no Haskell code. The directory layout is:

    docs/
      foundations/    team onboarding
      research/       design notes for the library itself
    docs/masterplans/   coordination plans
    docs/plans/         execution plans (this is one)

Essential reads before starting, in order:

1. `docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md` —
   the working baseline. **Pay particular attention to §4's User Registration walkthrough
   and the "Three clean fixes" passage**: the lesson "make the event self-contained for
   replay" is exactly the schema-evolution question viewed from one angle. §5's Order
   Fulfillment example surfaces the same lesson again with a process manager. §8 lists
   sequenced next steps but does **not** mention schema evolution explicitly — this plan
   exists to make sure that gap is closed before the prototype.
2. `docs/research/multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md`
   — defines the User Registration aggregate the synthesis builds on. Its event shapes
   are the canonical example for evolution scenarios.
3. `docs/research/fst-as-workflow-runtime.md` — describes the runtime architecture
   (event store + queue + subscriptions). Schema evolution touches the event store
   directly.

### Terms used in this plan

- **Event sourcing**: persistence model in which the source of truth is an append-only
  log of *events* (facts about what happened); state is recovered by replaying events
  through an `apply` function. See `docs/foundations/00-reading-guide.md` if unfamiliar.
- **Replay**: the act of running every event in the log through `apply` from the
  initial state to recover the current state. May happen on every read (no snapshot) or
  from the latest snapshot (snapshot-based).
- **Schema evolution**: the discipline of changing the shape of events, commands, or
  state over time without losing the ability to replay historical events.
- **Upcasting**: a strategy where, on read, an old event is transformed (in code) into
  the new event shape before being passed to `apply`. The upcasting function lives at
  the event-store boundary.
- **Versioning**: tagging each event with a version number so consumers can dispatch
  to the right code path.
- **Additive-only**: a discipline where new fields are added to events as `Maybe` (or
  with defaults), old fields are never removed, and events never change shape.
- **Symbolic-register transducer**: keiki's core type. See plan 1
  (`docs/plans/1-sharpen-dsl-shape-for-symbolic-register-transducer.md`) for the
  per-constructor breakdown. For this plan it suffices to know that an `Edge` carries
  `(guard, update, output, target)` and that `output` is an `OutTerm rs ci co` whose
  inverse is `solveOutput`.
- **Hidden-input check**: a static analysis the library will offer — flagging edges
  whose `update` or `guard` reads input fields not present in `output`, since such an
  edge cannot have its input recovered on replay. Synthesis §4 walks through a real
  instance.
- **Wire types**: the on-the-wire encoding of commands and events (typically JSON).
  Per the synthesis these are ordinary sum types with payloads.

### What the synthesis note already settles (do not re-litigate)

- Events are wire types: ordinary sum types with payloads, no GADT indexing.
- Events should be "self-contained for replay" — where data flows into the register
  file from the input, the event must carry that data so `solveOutput` can recover it.
  The User Registration `AccountConfirmed` example (synthesis §4 step 4) is the
  canonical demonstration.
- Composition lives at the runtime layer (event store + queue + subscriptions), not
  inside the transducer itself.

### What this plan must settle

- **Versioning model.** Pick one of: (a) wire-level version tag on every event; (b)
  schema as part of the event constructor name (e.g., `AccountConfirmedV2`); (c)
  additive-only by convention; (d) explicit upcaster functions at the event-store
  boundary. Justify against the User Registration scenarios.
- **`solveOutput` and versioning.** Does `solveOutput` need to know about versions, or
  does the upcaster (or version-tag dispatcher) feed `solveOutput` a uniformly current
  event? Strongly prefer the latter — keep the formalism clean — but document the
  trade-off.
- **Hidden-input check across versions.** When the user has multiple `OutTerm`s for
  the "same logical event" across versions, does the check run on each independently?
  Does the check warn when a v1 event lacks fields a v2 edge depends on?
- **Register file evolution.** When a register slot is added or removed, what does
  replay of historical events do? In particular: if v1 of a transducer wrote
  `#paymentRef`, and v2 removes that slot, is replay still defined? Two options:
  (a) replay always uses the *historical* transducer for events written under it, so
  a v2 deployment must keep v1 transducer code available; (b) registers are always
  open, missing fields default to `Nothing`, replay always uses the latest
  transducer.
- **Snapshot interaction.** Snapshots store the register file. When the register file
  shape changes, can old snapshots still be loaded? At minimum, document the
  invalidation rule.
- **What the library owns vs. what the application owns.** Keiki should not become a
  schema-migration framework. State precisely the contract: keiki provides X (e.g.,
  the hidden-input check, support for upcaster registration); the application
  provides Y (the upcaster bodies, the version tags in stored events).
- **Prototype implications.** What does the v1 prototype need to handle? Likely
  nothing beyond stating "schemas don't evolve in v1" — but document that explicitly
  so the prototype scope stays focused.

### Tooling

Use `mori` for dependency surveys per the user's global instructions. Specifically:

    mori registry list
    mori registry search crem
    mori registry show crem --full
    mori registry search tan-event-source
    mori registry show tan-event-source --full

If those packages are present, follow `source-paths` and read their replay /
versioning code on disk. **Never search `/nix/store`.**


## Plan of Work

Single milestone — produce a design note. Within the milestone, work bottom-up: catalog
the kinds of evolution change first, then study how each kind interacts with the
synthesis design, then pick a model that handles the common cases cleanly and defers
or rejects the rest.

### Milestone 1 — Author the schema-evolution design note

**Scope:** produce a single Markdown document at `docs/research/schema-evolution.md`
that fully specifies the schema-evolution model, walks through three concrete User
Registration scenarios under the chosen model, and lists the prototype implications.

**What will exist at the end:** a design note that the prototype plan
(`docs/plans/4-prototype-symbolic-register-core-with-user-registration-smoke-test.md`)
treats as a directional input, and that future plans (post-v1) build on for actual
versioning/migration features.

**Sub-steps in order:**

1. **Catalog change kinds.** List every kind of schema change a real event-sourced
   system experiences. Cover at minimum: field addition (with default vs without),
   field removal, field rename, field type narrowing/widening, splitting one event
   constructor into two, merging two into one, semantic change (same fields, different
   meaning). For each, note the typical frequency in production systems (most are
   additive; rename and split are common in early development; semantic changes are
   the dangerous tail).

2. **Walk each change kind through the current synthesis design.** For each kind from
   step 1, answer:
   - Does the existing event in the store still pass `solveOutput` against the
     post-change `OutTerm`? Why or why not?
   - Does the post-change `update` still produce a sensible register file when fed an
     old event? What goes wrong?
   - Does the hidden-input check fire? Should it?
   - Is the register file shape compatible with snapshots taken before the change?

   This is the diagnostic phase; do not propose solutions yet.

3. **Survey comparable libraries.** Read the actual source of `crem` and
   `tan-event-source` (via `mori`). Note specifically: do they have a versioning
   primitive? An upcaster registration? Or do they punt to the application? Greg
   Young's CQRS/ES essay (search via `mori registry docs` or, failing that, read the
   essay if it's in the local corpus) is the canonical reference for the upcaster
   pattern. Do not link to external URLs in the design note — embed the relevant
   approach in your own words.

4. **Enumerate evolution model options.** Capture each as a short paragraph with
   pros and cons:
   - **(a) Wire-level version tag.** Every stored event carries `version :: Int`.
     `solveOutput` is parametric in version; the runtime dispatches to the right
     transducer. Pros: explicit, debuggable. Cons: every event grows by a few bytes;
     migrations require shipping multiple transducer versions.
   - **(b) Constructor-name versioning.** `AccountConfirmedV2` is a different
     constructor from `AccountConfirmed`. The transducer has edges for both. Pros:
     no special machinery; type system enforces handling. Cons: the alphabet grows
     unboundedly; comparing across versions is awkward.
   - **(c) Additive-only by convention.** Fields can only be added, must be `Maybe`
     or have defaults. Pros: no upcaster ever needed. Cons: no clean way to remove
     a deprecated field; encourages clutter.
   - **(d) Explicit upcaster at the boundary.** The event store is responsible for
     upcasting old events to the current shape before they reach `solveOutput`. The
     library provides an upcaster registration but does not own the upcaster bodies.
     Pros: keeps the formalism clean; matches industry practice. Cons: the upcaster
     is application code, not library code, so the library can't audit it.

5. **Pick the v1 model.** Strongly prefer **(d) explicit upcaster at the boundary**
   combined with **(c) additive-only as the default convention**. Justify this against:
   - the User Registration evolution scenarios from step 6 below;
   - the desire to keep the formalism (`SymTransducer`, `Edge`, `OutTerm`,
     `solveOutput`) version-agnostic — an upcaster runs *before* `solveOutput` ever
     sees the event;
   - the prototype scope ("v1 prototype assumes no schema changes").

   If a different option turns out cleaner during step 6, pick that and note the
   reversal in the Decision Log.

6. **Walk three concrete User Registration scenarios.** Pick the scenarios from the
   change-kind catalog that exercise the model:

   - **Scenario A: add `confirmCode` to `AccountConfirmedData`.** This is the exact
     fix-1 from synthesis §4 ("Include the code in the event"). Walk through:
     existing events in the store lack `confirmCode`; an upcaster sets it to a
     sentinel; the post-fix `solveOutput` recovers `ci.confirmCode`; the hidden-input
     check now passes for new events. Document each step.
   - **Scenario B: remove `registeredAt` from the register file.** A breaking change.
     Walk through what the upcaster cannot fix (the slot itself is gone, so old
     edges that wrote it have nowhere to write); show that this requires shipping a
     migration of stored snapshots, not just an upcaster.
   - **Scenario C: split `ConfirmationResent` into `ConfirmationResent` (no code
     change) and `ConfirmationCodeRotated` (separate event for code change).** A
     restructuring. Show how the upcaster reads an old `ConfirmationResent` and emits
     two events to feed into the new transducer's `solveOutput`. This is the hardest
     case; document whether the upcaster is allowed to be 1-to-many.

7. **Hidden-input check across versions.** Decide: does the check run only against
   the *current* transducer's edges (the upcaster ensures events arriving at
   `solveOutput` match the current schema), or does it have a "compatibility mode"
   that warns about changes that would break old events? **Recommend the former for
   v1.** The latter is a v2 nice-to-have.

8. **Snapshot invalidation rule.** State the rule explicitly. Recommended: snapshots
   tag the register file shape (e.g., a hash of the slot list and types). On read, if
   the hash doesn't match the current shape, the snapshot is discarded and replay
   from the start runs. The application is responsible for snapshot pruning.

9. **State the library/application responsibility split.** Write a short table or
   list. Library: provides `OutTerm`/`solveOutput`, runs hidden-input check on
   current schema, exposes upcaster registration API (if any), defines snapshot
   shape-tag. Application: writes upcaster bodies, decides which schema is current,
   handles deprecated fields.

10. **State prototype implications.** The v1 prototype:
    - Does **not** implement upcasting.
    - Assumes a single static schema.
    - Demonstrates the hidden-input check on the current schema only.
    - Documents in its own README/note (if any) that schema evolution is deferred.

    This is the directional input plan 4 needs. It should be a one-paragraph summary at
    the end of the design note.

11. **Write the design note.**

12. **Cross-check.** A reader of the note should be able to answer: (i) what happens
    to an old event when I deploy a new transducer? (ii) where is the upcaster code,
    library or application? (iii) when does my snapshot become invalid? (iv) does the
    v1 prototype need to handle any of this?

**Acceptance:** the design note exists at the path above; the three User Registration
scenarios are walked through end-to-end; the v1 prototype implication is stated as a
single explicit paragraph; the responsibility split is documented.

**Commands to verify:**

    test -f docs/research/schema-evolution.md && echo "design note present"

    grep -c '^## ' docs/research/schema-evolution.md
    # expect at least 6 sections

    grep -E '(upcaster|hidden-input|snapshot|AccountConfirmed)' docs/research/schema-evolution.md | head
    # expect to see all the named concepts and the canonical scenario


## Concrete Steps

All work happens at the repository root: `/Users/shinzui/Keikaku/bokuno/keiki`.

1. Read the inputs:

       cat docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md
       cat docs/research/multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md
       cat docs/research/fst-as-workflow-runtime.md

2. Survey comparable libraries:

       mori registry search crem
       mori registry show crem --full
       mori registry search tan-event-source
       mori registry show tan-event-source --full

   Read source paths printed by `mori registry show`. Skim for files named like
   `Upcast*`, `Version*`, `Migration*`, `Apply*`.

3. Draft the design note structure:

       # Schema evolution for events and registers

       ## Inputs and prerequisites

       ## What changes in real systems
       (the change-kind catalog)

       ## Walking each change kind through the synthesis design
       (diagnostic phase)

       ## Models considered
       (a/b/c/d with pros/cons)

       ## Chosen model for v1
       (with rationale)

       ## Worked scenarios
       ### Scenario A — add confirmCode to AccountConfirmed
       ### Scenario B — remove registeredAt from the register file
       ### Scenario C — split ConfirmationResent

       ## Hidden-input check across versions

       ## Snapshot invalidation rule

       ## Library vs application responsibilities

       ## Prototype implications (v1)

4. Write the note section by section. Iterate on Scenario C — it is the hardest and
   most likely to expose a model weakness. If the chosen model can't handle it
   cleanly, revisit step 4 of the Plan of Work.

5. Run the verification commands.

6. Commit:

       git add docs/research/schema-evolution.md \
               docs/plans/2-sharpen-schema-evolution-for-events-and-registers.md \
               docs/masterplans/1-validate-symbolic-register-direction-via-haskell-prototype.md
       git commit -m "$(cat <<'EOF'
       docs(research): sharpen schema evolution model for events and registers

       Pick the v1 evolution model (additive-only with explicit upcaster at
       the event-store boundary), walk through three User Registration
       evolution scenarios, and pin the v1 prototype scope to a single
       static schema.

       MasterPlan: docs/masterplans/1-validate-symbolic-register-direction-via-haskell-prototype.md
       ExecPlan: docs/plans/2-sharpen-schema-evolution-for-events-and-registers.md
       Intention: intention_01knjzws4qezz9w8b0743zfqv8
       EOF
       )"

7. Update this plan's living sections and the master plan's registry/progress.


## Validation and Acceptance

Validation is by reading the design note against this checklist:

1. **Self-containment.** A reader who has read only the synthesis note can implement
   schema evolution from this design note (or know explicitly that v1 doesn't
   implement it).
2. **The three scenarios are walked through end-to-end.** No "left as exercise."
3. **The v1 prototype scope is stated explicitly.** Plan 4 should be able to copy
   that paragraph verbatim into its own scoping.
4. **The library vs application split is unambiguous.** A reviewer should not be
   able to ask "who writes the upcaster?" without finding a clear answer.

A non-author reviewer should be able to use the design note to predict what happens
when they add or remove a field in the User Registration aggregate, without consulting
the synthesis note again.


## Idempotence and Recovery

This plan produces a single Markdown file. All steps are repeatable. If the design
note already exists when work resumes, read it, find the first incomplete section, and
continue. The model choice in step 5 is the one decision that, if revised, requires
re-walking the three scenarios from step 6 — record any such reversal in the Decision
Log.


## Interfaces and Dependencies

Inputs (read-only):

- `docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`
- `docs/research/multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md`
- `docs/research/fst-as-workflow-runtime.md`
- (optional) `docs/research/data-direction-c-symbolic-and-register-automata.md`

Outputs:

- `docs/research/schema-evolution.md` — new design note.
- This plan's living sections, kept current.
- The master plan's Exec-Plan Registry and Progress section, updated on completion.

Tooling:

- `mori` for surveying comparable libraries. **Never search `/nix/store`.**
- `git` for commits with the required trailers.

This plan does not depend on plan 1 (DSL shape) — schema evolution is largely
orthogonal to the AST surface. Plan 4 (prototype) is the consumer of the directional
guidance produced here, but plan 4 only requires "v1 assumes a single static schema"
which can be stated independently of the rest of this note.
