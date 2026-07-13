# Schema evolution for events and registers

This note pins down keiki's schema-evolution model: how events, commands, and
register files change shape over time, and how the symbolic-register
transducer keeps replay correct across those changes. It complements the
synthesis note (`synthesis-c-foundation-b-presentation-with-worked-examples.md`).

The headline:

> **v1 keiki commits to a single static schema. Schema evolution is an
> *application* concern handled by an explicit upcaster at the event-store
> boundary, with additive-only as the default convention. The library
> formalism — `SymTransducer`, `Edge`, `OutTerm`, `solveOutput`, the
> hidden-input check — stays version-agnostic.**

The library never sees a "v1 event"; the event store hands it events that are
already current, because the application has run them through an upcaster. The
hidden-input check therefore runs against the current schema only. Snapshots
carry a register-file shape hash; mismatched hashes invalidate the snapshot
and force a replay from the start. The shape-hash primitive is shipped in
[`Keiki.Shape`](../../src/Keiki/Shape.hs) and consumed by the JSON codec in
the sibling package [`keiki-codec-json`](https://github.com/shinzui/keiki/tree/master/keiki-codec-json); see
[`regfile-codec-design.md`](regfile-codec-design.md) for the worked
example.

---

## Inputs and prerequisites

Read these in order:

1. `synthesis-c-foundation-b-presentation-with-worked-examples.md`, especially
   §4's User Registration walkthrough and the "Three clean fixes" passage.
   That passage is the schema-evolution question viewed from one angle (the
   event must carry every field the edge's update or guard reads).
2. `multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md`
   for the User Registration aggregate the scenarios below modify.
3. `effects-boundary.md` for the runtime architecture (event store +
   queue + subscriptions); schema evolution touches the event store
   directly.

Definitions used below:

- **Wire event.** The on-the-wire payload (typically JSON) the event store
  persisted at some past time.
- **Current event.** An event in the shape the *current* transducer's
  `OutTerm` produces.
- **Upcaster.** An application-supplied function `wire -> current` (or, for
  Scenario C, `wire -> [current]`) that runs at the event-store boundary
  before any event reaches `solveOutput`.
- **Register-file shape.** The list-of-types `rs` parameter of `RegFile rs`.
  The shape changes whenever a slot is added, removed, renamed, or
  re-typed. The `Vertex` set may also change; both belong to the "shape"
  for snapshot purposes.

---

## What changes in real systems

Production event-sourced systems experience the following kinds of change.
The order is roughly by frequency in the early life of an aggregate.

1. **Field addition (with a sensible default).** A new piece of data needs
   to flow through an event. Most common change. Examples: add `confirmCode`
   to `AccountConfirmedData` so replay can recover it (synthesis §4); add a
   `correlationId` for tracing.

2. **Field addition (without a sensible default).** Rarer; usually means the
   change isn't actually compatible — old events genuinely lack information
   the new code wants. Forces either a sentinel, a snapshot migration, or a
   deferred capability ("for events written before T, feature X is
   unavailable").

3. **Field rename.** `at` becomes `occurredAt`; `userId` becomes `actorId`.
   Common in early development before a domain stabilises. From the
   transducer's view: the `OutTerm` projects out a different field name; an
   upcaster that just renames the JSON key reconciles old events.

4. **Splitting one event constructor into two.** What used to be a single
   `ConfirmationResent` now distinguishes "user pressed resend (no code
   change)" from "code rotated for security reasons". The output alphabet
   grows; the upcaster must decide *which* of the new constructors the old
   event maps to (or whether it must produce both).

5. **Merging two events into one.** The inverse: the domain stops caring
   about the distinction between two old events; new code emits one. Old
   events from either of the two old constructors map to the single new one.
   Trivial upcaster.

6. **Field type change (narrowing or widening).** `Int -> Word32`,
   `Text -> NonEmptyText`, an enum gains or loses a constructor. Narrowing
   can fail (an old event's value may not fit the new type); widening is
   safe.

7. **Field removal.** A field that was used in some old edge's update is
   removed from the event. If the field was *also* removed from the register
   file, no problem — the slot doesn't exist any more either. If it's
   removed from the event but the register slot still exists and some edge
   still wants to write it, replay of old events leaves that slot at its
   default and any subsequent edge that reads it sees stale or missing
   data — a hidden-input bug introduced by evolution.

8. **Register-file shape change.** A slot is added, removed, renamed, or
   re-typed. Distinct from event-shape changes: the register file is the
   transducer's internal state, not a wire format. The change affects
   snapshots (existing snapshots no longer match the current shape) and may
   affect replay (an edge that wrote the old slot now has nowhere to write).

9. **Semantic change with no shape change.** Same field, same type, different
   meaning. `priority :: Int` used to be 1-3 with 3 highest; now it's 1-5
   with 1 highest. The dangerous tail of evolution: nothing in the type
   system fires. The only defence is a domain-level versioning convention
   (e.g., bump a wire-level version tag and force the application to write
   a deliberate upcaster).

In keiki's design, kinds 1–6 are addressed by the upcaster at the boundary;
kind 7 is partially addressed by the upcaster (it can fabricate a sentinel)
but the hidden-input check should fire on the *new* schema if the field is
still needed; kind 8 is a snapshot-invalidation issue plus a forced
re-deployment of the transducer code; kind 9 keiki cannot detect — it is on
the application to declare a new version when meaning changes.

---

## Walking each change kind through the synthesis design

For each change kind, the question is fourfold:

- Does the existing event in the store still pass `solveOutput` against the
  post-change `OutTerm`?
- Does the post-change `update` still produce a sensible register file when
  fed an old event?
- Does the hidden-input check fire? Should it?
- Is the register-file shape compatible with snapshots taken before the
  change?

This section is diagnostic only; it does not propose solutions. Solutions
arrive in the "Chosen model" and "Worked scenarios" sections.

### Field addition with default

The new `OutTerm` projects out a field absent from the old wire event.
`solveOutput` cannot decode the old wire bytes against the new term — JSON
deserialisation either fails or produces a default. If the application
*upcasts before deserialising into the current event type*, the upcaster
inserts the sentinel and `solveOutput` succeeds. The hidden-input check on
the post-change schema does not fire (the new field is in the event). The
post-change `update`, fed the upcasted event, recovers the sentinel — which
may or may not produce sensible state depending on whether the sentinel was
chosen well. Snapshots of register files taken before the addition are
compatible with the new shape only if the new register slot (if any) also
admits a default; otherwise the snapshot must be invalidated.

### Field addition without default

Same as above but the sentinel is wrong. The application must either
declare the change a breaking one (snapshot migration plus event-store
backfill) or accept that some operations are unavailable for entities whose
streams started before the addition. The library cannot do either of these
for the application; it can only fail loudly when the upcaster is missing.

### Field rename

A pure rename of a wire field. The upcaster reads from the old key, writes
to the new key, hands the result to `solveOutput`. Everything downstream is
indistinguishable from the case where the rename never happened. The
hidden-input check is unaffected. Snapshots of register files are
unaffected unless the register-slot was also renamed (a separate change).

### Constructor split (1-to-many on the upcaster)

The output alphabet now has two constructors where there was one. An old
wire `ConfirmationResent` maps to *either* the new `ConfirmationResent`
(now narrower in meaning) *or* the new `ConfirmationCodeRotated`, depending
on whether the old payload actually rotated the code. The upcaster either
inspects the old payload and chooses, or — when old payloads cannot be
distinguished after the fact — emits both events in sequence so the
transducer's edges fire as if the system had always treated them as
separate. **This is the only case where the upcaster is allowed to be
1-to-many.** Scenario C below works it through.

### Constructor merge (many-to-one)

Trivial: every old constructor maps to the single new one. The post-change
`update` may need to know "which old kind was this" if the merged event
loses information. If it does, the merge is unsafe and should be reverted
to a constructor-rename-of-one with a deprecation of the other. Otherwise
proceed.

### Type narrowing

`Int -> Word32` may fail on a real old event (negative integers stored).
The upcaster must decide: error, clamp, or produce a sentinel. This is an
application policy choice; the library exposes the upcaster's `Either Error`
return type as the contract.

### Type widening

Always safe. The upcaster is `id` (modulo the JSON key shape).

### Field removal from event but not from register

The post-change `OutTerm` no longer mentions the field. The old wire event
still has it. The upcaster *drops* the field. Replay produces the same
register state as before — *if the only writer of the slot was the same
edge*. If the slot was written from this event's input field and no other
edge writes it, the slot now stays at its default forever after this
event — silently wrong. The hidden-input check on the post-change schema
*should* fire here: an edge writes a register slot from an input field, the
output `OutTerm` no longer carries that field, so `solveOutput` cannot
recover it on replay. **The check is the same one synthesis §4 demonstrates;
schema evolution gives it a second job.**

### Register slot added

The new slot defaults to its `Maybe`-Nothing or zero value. Old events
replay into the larger register file with the new slot at default; nothing
breaks. Snapshots taken before the change have the smaller shape and are
*not* directly loadable — see the snapshot rule below.

### Register slot removed

The old transducer code wrote to a slot that no longer exists. If the
removed slot was *only* used by edges that have also been removed, the new
transducer never tries to write it on new events and never reads it on old
events. No problem at the formalism level. But existing snapshots have the
old shape. The library must invalidate them. *Application code that read
the slot via `regs ! #removed` is a separate concern — that code wouldn't
typecheck against the new register file in any case.* Scenario B works
through this.

### Register slot type change

A slot's type changes (e.g., `Email -> NonEmptyText`). Replay of old events
runs the new `update` against a recovered command; if the recovered command
fits the new type, fine. If not, the upcaster on the *event* side has to do
the conversion before it reaches `update`. Snapshots are invalidated
because the in-memory representation differs.

### Semantic change

No shape change, no signature change, no compiler error. `solveOutput`
succeeds. `update` runs. The recovered state is wrong by the new
interpretation. Keiki cannot catch this. The application must declare a
new event constructor (or bump a wire version tag) when it wants the
library's help.

---

## Comparable libraries

### message-db (Postgres) and tan/message-db-hs

Surveyed locally via `mori`. Both packages live under
`/Users/shinzui/Keikaku/hub/event-sourcing/message-db-project` and
`/Users/shinzui/Keikaku/work/libraries/haskell/message-db-hs-master`
respectively.

The PostgreSQL message-db database is an *infrastructure* layer: an
append-only log of `Message` records, where each record carries a
`message_type` string, a JSON `data` payload, and a JSON `metadata`
payload. There is no library-level concept of an event version, no
upcaster registration, no schema-of-payload check. The string
`message_type` is the discriminator the application uses to dispatch
serialisers; everything else is opaque JSON. The *only* "version" the
library defines (`stream-version`, in `database/v1.3.0/database/functions/`)
is the optimistic-concurrency stream length — the position of the last
event written — used to detect concurrent writers, not to evolve event
shapes.

`tan/message-db-hs` is a thin Haskell wrapper around the same record. Its
`MessageDb.Message.Message` type carries `messageType :: !MessageType`
plus `messageData :: !MessageData` (a JSON value). Application code
chooses how to deserialise based on `messageType`; there is no upcaster
hook in the library, no `Migration` module for events (the only `Migration`
modules are for the *database schema*, not the events). The rest of the
package set (`message-db-effectful`, `message-db-subscription`,
`message-db-checkpoint-store`) uniformly treats events as opaque JSON.

The pattern: **infrastructure libraries push event evolution entirely to
the application.** The application owns the upcaster, the version tag (if
any), and the deserialiser dispatch table. This matches Greg Young's
classic CQRS/ES guidance and is the design keiki adopts at the boundary.

### crem (documentation-based)

`crem` is not in the local registry; survey is from published documentation
knowledge. `crem` models aggregates as Mealy machines with explicit `apply`
in the application layer, takes the position that events are the user's
concern, and offers no upcaster primitive. Schema evolution is delegated to
whatever serialisation library the user picks and whatever discipline they
adopt. This aligns with the position taken here.

### tan-event-source (documentation-based)

`tan-event-source` is also not in the local registry; survey is from
documentation knowledge. Its `Decider`/`MultiDecider` API takes events as
a user-defined sum type with no notion of versioning. The library is
agnostic to wire format; the application chooses serialisation and is on
the hook for evolution. Same shape as the above.

### Conclusion of survey

Every library surveyed — local infrastructure (message-db) and the two
referenced application-level libraries — leaves event evolution to the
application. None of them ship an upcaster registration API; none ship a
versioning primitive. Keiki adopting the same posture is consistent with
the Haskell event-sourcing ecosystem and with broader CQRS/ES practice.
The novelty in keiki is not the policy ("application owns evolution") but
the precise statement of what *the formalism* requires from the
application's upcaster: the upcaster's output must be a current event the
hidden-input check would accept.

---

## Models considered

Four candidate models for how the library handles event evolution.

### (a) Wire-level version tag on every event

Every stored event carries a `version :: Int`. The library defines a
`SymTransducer` per version; on read, the runtime dispatches by version
tag. `solveOutput` is parametric in the version.

Pros: explicit; the version is part of the persisted record; the
dispatcher is mechanical.

Cons: Every event grows by a few bytes forever. *Every* schema change
requires bumping the version, even trivial additions where an upcaster
would be `id`. The library has to ship multiple transducer versions
side-by-side, which doubles the surface area of guards, updates, and
output terms; the hidden-input check must run on each version
independently and must be silent across versions (a v2 edge requiring a
field a v1 event lacks is correct, not a bug). Keeping old transducer
versions in the codebase contradicts the goal of keeping the formalism
small.

### (b) Constructor-name versioning

`AccountConfirmedV2` is a *different* constructor from `AccountConfirmed`.
The transducer has edges for both; the alphabet grows.

Pros: No special machinery — the type system enforces that every version
is handled. The version is implicit in the constructor name, so no extra
wire bytes.

Cons: The alphabet grows unboundedly with the age of the system.
Cross-version refactors ("rename `email` to `accountEmail` in every
version") are painful. Comparing aggregates across versions is awkward
(language equality is over an alphabet that includes obsolete
constructors). For long-lived aggregates this becomes the dominant cost
of the library.

### (c) Additive-only by convention

Fields can only be added, must be `Maybe` or carry defaults. Old fields
are never removed; they just stop being read. Events never genuinely
change shape.

Pros: No upcaster ever needed for the changes it allows. The wire format
is stable.

Cons: Doesn't permit deprecating clutter; events accumulate dead fields
forever. Cannot handle constructor splits, merges, type narrowings, or
register-slot removals at all. As a *complete* model it is too narrow; as
a *default convention* it is excellent and avoids most upcasting work.

### (d) Explicit upcaster at the event-store boundary

The application defines an upcaster `WireEvent -> Either Error
[CurrentEvent]` (the `[]` allows the 1-to-many case from constructor
split). The event store runs the upcaster on every event read; the
library never sees a non-current event. The library provides no upcaster
*body* and no version tag — those are application decisions — but it
documents the contract and exposes the registration point.

Pros: Keeps the formalism (`SymTransducer`, `Edge`, `OutTerm`,
`solveOutput`, the hidden-input check) version-agnostic. Matches industry
practice. Composes with (c): when changes are additive, the upcaster is
trivial; the upcaster is only non-trivial for the harder changes.

Cons: The upcaster is application code; the library cannot inspect or
verify it. A buggy upcaster is silently wrong. The application owns the
choice of versioning scheme (wire tag, constructor name, or none) — the
library does not opine.

### Why (d) + (c) wins

Option (a) makes every change a versioned change, including trivial
additions; (b) bloats the alphabet forever; (c) alone cannot handle the
harder changes. Combining (d) as the mechanism with (c) as the default
convention gives:

- Trivial additive changes need no upcaster: the application bumps the
  field as `Maybe` or with a default and ships.
- Non-trivial changes (rename, split, merge, type narrowing, removal)
  are handled by an upcaster that the application writes once at the
  event-store boundary. The library never has to know.
- The formalism keeps its single-version shape. `solveOutput` is
  monomorphic in the current `OutTerm`. The hidden-input check runs once
  against the current schema. Snapshots are validated against the
  current register-file shape.
- The library's responsibility is bounded: it states the contract the
  upcaster must satisfy, exposes a registration hook, and otherwise
  stays out of the way.

This is the chosen v1 model.

---

## Chosen model for v1

**(d) Explicit upcaster at the event-store boundary, with (c) additive-only
as the default convention.** Concretely:

- Events arrive at the event-store boundary as raw bytes (typically JSON).
  The application's *deserialiser* turns them into a wire event type.
- The application's *upcaster* turns the wire event into one or more
  current events. For trivial additive changes, the upcaster is `pure
  . id` and the wire event already deserialises into the current event
  type with default fields filled in.
- The library's `solveOutput` consumes only current events. It is
  monomorphic in the current `OutTerm`.
- The hidden-input check runs against the current schema only. By the time
  events reach the check, the upcaster has already normalised them.
- Snapshots are tagged with a register-file shape hash; on read, a
  mismatch invalidates the snapshot and forces full replay through the
  upcaster.
- The library does *not* prescribe a wire-version-tag scheme. Some
  applications will adopt one (helpful for upcaster dispatch); others
  will dispatch by constructor name on the wire (`messageType` in
  message-db). Keiki accepts both.

The library exposes one piece of evolution-related API surface: a typed
contract describing what the upcaster must produce. Stated in prose: *for
every persisted event in the store, the application's upcaster must
produce a non-empty list of current events such that running the current
transducer over those events yields a valid `(s, RegFile rs)` state.*
The library does not check this; it states it. v2 may add property tests
or runtime audit hooks; v1 does not.

The combinator language does not change. The synthesis note's
`SymTransducer phi rs s ci co` is the v1 type. There is no
`SymTransducerV1`/`SymTransducerV2` distinction in the library. There is
no `version` field on `Edge`. There is no version-aware `solveOutput`.

---

## Worked scenarios

Three concrete evolutions of the User Registration aggregate, walked end
to end under the chosen model.

### Scenario A — add `confirmCode` to `AccountConfirmedData`

This is exactly fix-1 from synthesis §4. The unfixed schema had:

    data AccountConfirmedData = AccountConfirmedData
      { email :: Email
      , at    :: UTCTime
      }

and an edge in `RequiresConfirmation` whose guard reads
`d.confirmCode == regs ! #confirmCode`. The hidden-input check at build
time fires: the guard reads an input field (`confirmCode`) not present in
the output event. The fix is to add the field to the event:

    data AccountConfirmedData = AccountConfirmedData
      { email       :: Email
      , at          :: UTCTime
      , confirmCode :: ConfirmationCode
      }

#### Existing events in the store

Suppose Alice's stream contains, written by the unfixed version of the
code,

    AccountConfirmed { email = "alice@x", at = t₂ }

and the new code is now deployed.

#### The upcaster

A trivial upcaster runs at the boundary:

    upcastAccountConfirmed
      :: WireAccountConfirmed -> CurrentAccountConfirmed
    upcastAccountConfirmed w =
      AccountConfirmedData
        { email       = w.email
        , at          = w.at
        , confirmCode = sentinelMissingCode
        }

The sentinel is a domain choice. For User Registration, a reasonable
sentinel is whatever code the register file currently holds — except the
upcaster has no access to the register file (it runs per-event before
replay starts). The defensible sentinel for v1 is a fixed
`"<unknown-code>"` value the rest of the system treats as "this event
predates the field". The application is responsible for choosing.

For events written *after* the deployment, no upcaster is needed; the
serialiser writes `confirmCode` directly.

#### Replay path

1. Event store reads the wire bytes.
2. Deserialiser produces a `WireAccountConfirmed` (the field may be
   missing; deserialiser tolerates this).
3. Upcaster fills `confirmCode` with the sentinel.
4. Library's `solveOutput` recovers `ci = ConfirmAccount
   (ConfirmAccountData sentinel t₂)`.
5. Edge guard checks `sentinel == regs ! #confirmCode`. Now: the register
   file's `confirmCode` was set by an earlier `RegistrationStarted` (or
   `ConfirmationResent`) — those events *did* carry `confirmCode`, so
   replay populated the slot with the real code. The guard fails.
6. Replay halts with an error: "this aggregate's history contains an
   `AccountConfirmed` event that the current schema cannot validate".

This is the right outcome. The application has two choices: backfill the
old events with the real `confirmCode` (a one-time event-store rewrite)
or relax the guard for events bearing the sentinel.

#### Hidden-input check

Against the post-change schema the check passes: every input field the
edge's update or guard reads (`d.confirmCode`, `d.at`) appears in
`AccountConfirmedData`. The check did its job at build time, exactly as
synthesis §4 advertises.

#### Snapshot interaction

Adding a field to an event does not change the register-file shape; the
register slot `#confirmCode` already exists. Snapshots taken before the
deployment remain valid. (If the change had also added a register slot —
say `#confirmedFromIp` — snapshots would be invalidated; see the
snapshot rule.)

### Scenario B — remove `registeredAt` from the register file

A breaking change. The aggregate decides `registeredAt` is unnecessary —
the timestamp is reconstructible from the first event in the stream and
therefore should not pollute the register file. The pre-change shape:

    type UserRegRegs =
      '[ "email"         ':-> Email
       , "confirmCode"   ':-> ConfirmationCode
       , "registeredAt"  ':-> UTCTime
       , "confirmedAt"   ':-> UTCTime
       , "deletedAt"     ':-> UTCTime
       ]

After:

    type UserRegRegs =
      '[ "email"         ':-> Email
       , "confirmCode"   ':-> ConfirmationCode
       , "confirmedAt"   ':-> UTCTime
       , "deletedAt"     ':-> UTCTime
       ]

#### What the upcaster cannot fix

The upcaster operates on events. Removing a register slot affects the
*update* terms of edges, not the events themselves. The `StartRegistration`
edge's update used to be:

    Combine (Set #email …)
    $ Combine (Set #confirmCode …)
              (Set #registeredAt (\(StartRegistration d) -> d.at))

After the change, the third `Set` has nowhere to go. The new `update` is:

    Combine (Set #email …)
            (Set #confirmCode …)

The `RegistrationStarted` event still carries `at` — that does not change.
Replay of a stream containing this event:

1. Event store reads bytes; deserialiser produces `RegistrationStarted`.
2. Upcaster is `id` (no event-shape change).
3. Library's `solveOutput` recovers `ci = StartRegistration
   (StartRegistrationData …)` including `d.at`.
4. New `update` writes `email` and `confirmCode` only. `d.at` is
   discarded.
5. Replay continues. The register file no longer has `registeredAt`.

The replay itself is correct: the new transducer is well-defined on old
events, the new update simply ignores a field. The hidden-input check on
the new schema fires *only* if some other edge still reads
`regs ! #registeredAt` — which it cannot, because the slot is gone and
the code wouldn't compile. So the check is unaffected by this kind of
change.

#### What the snapshot rule must do

Existing snapshots store the *old* register file:

    RegFile { email = …, confirmCode = …, registeredAt = …,
              confirmedAt = …, deletedAt = … }

The new code expects:

    RegFile { email = …, confirmCode = …,
              confirmedAt = …, deletedAt = … }

These are different types. A snapshot loaded against the new code is at
best ill-typed, at worst silently misaligned (if both shapes happen to
serialise to the same JSON, which `vinyl`-style records do not but raw
records might). **This is precisely what the snapshot shape-tag is for.**

The library writes a hash of the register-file shape into every
snapshot. On read, the runtime compares the snapshot's tag to the
current shape's hash:

- Match: load the snapshot, replay any events written after it.
- Mismatch: discard the snapshot, replay from the beginning of the
  stream through the upcaster.

For a long-lived aggregate, "replay from the beginning" can be expensive
— hours of replay for years of events. The application is responsible
for re-snapshotting after any breaking change so subsequent reads are
fast again. Keiki provides the tag and the invalidation; the
re-snapshotting cadence is application policy.

#### Pure event re-derivation: not enough

Naively: "if `registeredAt` is reconstructible from the first event,
why not just re-derive it on each read instead of storing it?" Two
problems. First, the new code has decided not to need it at all, so
there's no slot to derive into. Second, even if the application wants
it elsewhere (e.g., in a read model), that's a projection separate from
the aggregate. The aggregate evolution is independent of any external
projection's needs.

#### Summary

A pure register-shape change requires:

1. New transducer code (compiles against the new shape).
2. Snapshot invalidation by shape-tag mismatch.
3. Full replay from event 0 through the upcaster (which is `id` for
   this scenario because no event shape changed).
4. (Application policy) Re-snapshot to amortise future reads.

The upcaster did not solve this; the *snapshot-tag rule* did.

### Scenario C — split `ConfirmationResent` into `ConfirmationResent` + `ConfirmationCodeRotated`

The hardest case. The original event:

    data ConfirmationResentData = ConfirmationResentData
      { email       :: Email
      , confirmCode :: ConfirmationCode
      , at          :: UTCTime
      }

served two purposes: "the user pressed resend, no actual code change" and
"a security event rotated the confirmation code". The team decides to
distinguish them in the new model:

    data ConfirmationResentData = ConfirmationResentData
      { email :: Email
      , at    :: UTCTime
      }                                          -- email re-sent only

    data ConfirmationCodeRotatedData = ConfirmationCodeRotatedData
      { email       :: Email
      , confirmCode :: ConfirmationCode
      , at          :: UTCTime
      }                                          -- code changed

The new transducer's `RequiresConfirmation` vertex now has two edges
where there was one: one for the resend path (`Keep` update on the code)
and one for the rotate path (`Set #confirmCode …`).

#### Old wire data

A historical event from Alice's stream:

    ConfirmationResent { email = "alice@x", confirmCode = "K2P7", at = t₁ }

In the old code, this both rotated the code (the update wrote `#confirmCode
:= regs ! #confirmCode`, but the `ConfirmationResent` edge always re-set
`#confirmCode` to `freshCode` first — so in practice the code did rotate)
and re-sent the email.

#### Is the upcaster allowed to be 1-to-many?

**Yes.** The library's upcaster contract is `WireEvent -> Either Error
[CurrentEvent]`. A 1-to-many upcaster is the formal solution for
constructor splits. The library treats the upcaster's output list as a
mini-stream that gets folded into replay in order, exactly as if those
events had been written separately.

For Scenario C, the upcaster is:

    upcastConfirmationResent
      :: WireConfirmationResent -> [CurrentEvent]
    upcastConfirmationResent w =
      [ ConfirmationCodeRotated  -- old version always rotated
          (ConfirmationCodeRotatedData
             { email = w.email, confirmCode = w.confirmCode, at = w.at })
      , ConfirmationResent
          (ConfirmationResentData { email = w.email, at = w.at })
      ]

The order matters: rotate first (writes `#confirmCode`), then re-send
(no register change). After the upcaster, the new transducer fires two
edges: the rotate edge (target stays `RequiresConfirmation`, register
update sets `#confirmCode`) and the resend edge (target stays
`RequiresConfirmation`, no register update).

#### Replay path

1. Event store reads bytes.
2. Deserialiser produces a `WireConfirmationResent`.
3. Upcaster produces `[ConfirmationCodeRotated …, ConfirmationResent …]`.
4. Library's `solveOutput` runs against the first emitted event:
   recovers `ci = RotateConfirmationCode (RotateConfirmationCodeData …)`,
   the register update writes the new `#confirmCode`.
5. Library's `solveOutput` runs against the second emitted event:
   recovers `ci = ResendConfirmation (ResendConfirmationData …)`, no
   update, edge target stays `RequiresConfirmation`.
6. Replay continues with subsequent events.

The hidden-input check on the new schema must pass for both edges
independently. For `ConfirmationCodeRotated`, the event carries
`confirmCode`, so any update reading the input's `confirmCode` is
recoverable. For `ConfirmationResent` (the narrower new version), the
edge presumably does not write `#confirmCode` and does not read it from
the input — if it did, the check fires and the new model is malformed.

#### Why the order of upcaster output matters

The library cannot reorder. The upcaster must emit events in the order
they should be replayed, which is the order whose effect on the register
file matches the *historical* effect of the single old event. For the
ConfirmationResent split, rotate must come before resend because the old
behaviour rotated the code as part of resending.

If the historical interpretation were ambiguous — if some old
`ConfirmationResent` events should map to rotate-only and others to
resend-only — the upcaster needs more information than the wire event
carries (e.g., a database lookup, a metadata field). At that point the
application has a *true* breaking change on its hands, equivalent to
Scenario B, and must do a one-time backfill of historical events.

#### What the upcaster can't do

The upcaster cannot insert events that didn't logically happen. If the
new model requires every code rotation to be preceded by some
`SecurityChallenge` event, and old streams have no such event, the
upcaster cannot fabricate it without lying to the audit log. That's an
honest compatibility break and must be handled at a higher level
(historical streams are read-only against the *old* model; only new
streams use the *new* model).

#### Summary

Constructor splits work cleanly under the chosen model *because* the
upcaster is allowed to be 1-to-many. Constructor merges work under the
same mechanism with a list of length one. Only when the historical
record is genuinely ambiguous does the model break, and then no model
saves you — only event-store backfill does.

---

## Hidden-input check across versions

Decision: **the hidden-input check runs only against the current
schema.**

Rationale: the upcaster guarantees every event reaching `solveOutput` is
a current event. By the time the check has anything to chew on, there
is no notion of "old version". The check's job is to ensure the current
transducer's edges are well-formed in isolation — that every input
field the update or guard reads is recoverable from the corresponding
output event. Schema evolution adds no new responsibility to the check
itself.

The check *does* gain a new use case: when the application removes a
field from an event but leaves a register slot writer in some edge that
references it, the check will fire on the new schema. Before evolution,
the check caught design errors at the time of the original write.
After evolution, it also catches *evolution errors* — refactorings that
inadvertently break replay. The wording does not change; only the
context in which it fires.

What the v1 check does *not* do:

- It does not run against historical schemas. Old transducer versions
  are not retained. The check on the current schema is the only check.
- It does not cross-validate the upcaster. The upcaster's output type is
  a current event; the type system enforces that. Whether the upcaster
  body produces sensible *values* is application correctness, not a
  formalism question.

A v2 nice-to-have is a *compatibility-mode check* that, given a stored
snapshot's shape-tag, audits whether the upcaster's targets are
reachable from any historical state recorded in any snapshot. Out of
scope for v1.

---

## Snapshot invalidation rule

Snapshots are tagged with a hash of the *current register-file shape*.
The shape comprises the ordered list of slot labels and each slot's
`CanonicalTypeName`. Vertex/schema semantics need a separate
application-owned version. Pseudocode:

    shapeHash :: KnownRegFileShape rs => Proxy rs -> Text
    shapeHash = regFileShapeHash

On snapshot read:

1. Deserialise the snapshot envelope; extract its `shapeHash`.
2. Compare to the current transducer's `shapeHash`.
3. Match: load the snapshot's `(s, RegFile rs)`; replay any events
   written after the snapshot through the upcaster.
4. Mismatch: discard the snapshot. Replay from event 0 through the
   upcaster. Optionally write a fresh snapshot at the end.

Two notes on the rule:

- The hash is over *type identity*, not *encoded shape*. Two slots
  named the same but with different types must hash differently. keiki
  pins built-in canonical names and lets applications override names for
  their own types; changing that canonical encoding is a wire-format
  change, guarded by golden fixtures.
- The application is responsible for snapshot-pruning. Keiki does not
  garbage-collect old snapshots. If shape changes are frequent, the
  event store will accumulate stale snapshots; the application either
  ignores them (they are simply unused on read) or runs a periodic
  cleanup.

A consequence: the first read after a deployment that changes register
shape may take much longer than usual. The application should plan for
this (re-snapshot after deploy, or accept the one-time cost).

---

## Library vs application responsibilities

The boundary between keiki and the application around schema evolution.

### Library

- Defines `SymTransducer phi rs s ci co`, `Edge`, `OutTerm`,
  `solveOutput`, the runtime loop, and the snapshot envelope.
- Runs the hidden-input check on the current schema at build time.
- Computes and stores the register-file shape hash on every snapshot
  write.
- Compares the shape hash on every snapshot read; invalidates on
  mismatch.
- Documents the upcaster contract: input is the application's wire event
  type, output is `Either Error [CurrentEvent]`, ordering of the output
  list is the replay order.
- Provides a registration point for the upcaster (a function the runtime
  calls before `solveOutput`).
- Does *not* ship upcaster bodies, version-tag schemes, deserialisers,
  or migration tooling.

### Application

- Defines the wire event type, the current event type, and the
  serialisers/deserialisers.
- Decides whether to use a wire-version tag, constructor-name
  versioning, or no version at all.
- Writes the upcaster body. Tests it.
- Decides what each constructor split, merge, or rename means
  semantically.
- Decides when to re-snapshot after a breaking register-shape change.
- Decides whether to backfill historical events (a one-time
  event-store rewrite) when the upcaster cannot disambiguate.
- Owns semantic-change versioning entirely. Keiki cannot detect
  same-shape, different-meaning changes.

The split is unambiguous. If a reviewer asks "who writes the upcaster?",
the answer is "the application, always". If they ask "who validates the
upcaster's *output* against the current schema?", the answer is "the
library, via the hidden-input check on the current schema and the
typechecker on the current event type". If they ask "who decides when a
snapshot is stale?", the answer is "the library, via the shape-hash
comparison". If they ask "who cleans up stale snapshots?", the answer
is "the application, on its own cadence".

---

## The derived codec's realization of this contract (EP-77)

Addendum, 2026-07-12. The chosen model remains **(d) an explicit upcaster at
the event-store boundary, with (c) additive-only as the default convention**.
EP-77 does not make the pure `keiki` core version-aware: `SymTransducer`,
`solveOutput`, validation, and register replay still consume only the current
typed event schema.

What changed after the original note was written is the optional JSON boundary.
`keiki-codec-json`'s derived event codec now offers an opt-in in-band realization
for applications that want the sibling package to own that part of the boundary:

- an integer envelope version, with an absent version interpreted as version 1;
- pinned wire kinds so Haskell constructor renames need not rename persisted data;
- a compile-time-complete chain of one-envelope-to-one-envelope upcasters; and
- default-on-missing field decoding for additive evolution.

The application still supplies every default and upcaster body and owns their
semantics. In particular, the derived codec cannot represent the model's
one-historical-event-to-many-current-events split. That case remains in the
application's event-store adapter, exactly as the contract above specifies. An
application with its own outer versioned envelope may also leave the derived codec
at version 1 and implement the whole policy at that outer layer.

Thus the earlier statements that the library does not prescribe version tags or
ship migration machinery should be read as statements about the pure core and the
application-owned default. EP-77 adds a convenience realization in an explicitly
opt-in codec package; it does not change the core model or transfer semantic
evolution responsibility away from the application.

---

## Release implications

The pure `keiki` core still sees one current typed event alphabet and
runs replay validation against that schema only. Evolution happens
before typed replay. The optional `keiki-codec-json` boundary now
implements the one-envelope-to-one-envelope portion of this note:
pinned wire kinds, an in-band version, additive missing-field defaults,
and a compile-time-complete upcaster chain. Applications still own
semantic migrations and every one-to-many split.

Snapshots use `regFileShapeHash` as a structural discriminator. A hash
mismatch is a cache miss: discard the snapshot and replay the migrated
event log. The hash identifies the register shape, not event semantics,
so applications retain their own codec/schema version whenever a
same-shape encoding or meaning changes.

---

## Cross-check

A reader who has worked through this note should be able to answer
without consulting the synthesis note again:

- **What happens to an old event when I deploy a new transducer?** It
  passes through the application's upcaster at the event-store boundary,
  becomes a current event (or a list of current events for a split),
  and feeds into the unchanged library `solveOutput`.

- **Where is the upcaster code, library or application?** Application,
  always. Keiki provides only the registration hook and the contract.

- **When does my snapshot become invalid?** When the register-file
  shape (slot labels, slot types, vertex set) changes. The shape-tag
  hash on the snapshot fails to match the current transducer's hash, the
  snapshot is discarded, and replay from event 0 runs through the
  upcaster.

- **Does keiki itself need to handle any of this?** No. The library
  is schema-evolution-agnostic; the upcaster lives in the
  application's event-store adapter.
