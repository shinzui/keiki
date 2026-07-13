---
id: 77
slug: event-codec-schema-evolution-version-tags-wire-kind-pinning-and-default-on-missing-decoding
title: "Event codec schema evolution: version tags, wire-kind pinning, and default-on-missing decoding"
kind: exec-plan
created_at: 2026-07-12T04:16:45Z
intention: "intention_01kxc5whw1en3ra4nh728m53ka"
master_plan: "docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md"
---

# Event codec schema evolution: version tags, wire-kind pinning, and default-on-missing decoding

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

In an event-sourced system the stored events are the source of truth and they outlive
the code that wrote them: the wire format IS the database. Today the TH-derived event
codec in `keiki-codec-json/src/Keiki/Codec/JSON/Event.hs` cannot survive any of the
three most ordinary schema changes. Adding a field to a payload record — even a
`Maybe` field that should just default to `Nothing` — makes every previously stored
event fail to decode with `Left "missing field: X"`. Renaming a Haskell constructor
(`Placed` becomes `OrderPlaced`) bricks decoding of the entire store, because the wire
discriminator is literally the constructor's name and there is no way to pin it.
And nothing in the emitted object says which version of the schema wrote it, so no
migration hook can ever be dispatched.

After this plan, the derived codec emits a versioned envelope — every encoded event
carries a schema-version field (`"v": 1` by default) next to the existing `"kind"`
discriminator — and the deriving options let the author (a) pin each constructor's
wire kind independently of its Haskell name, (b) give any field a decode-time default
so additive changes need no version bump, and (c) register an upcaster chain (pure
JSON-to-JSON migrations, one per historical version) that the decoder replays before
constructor dispatch, so structural changes work too. The Template Haskell splice
rejects, at compile time, the misconfigurations that would corrupt a store: a payload
field that collides with the discriminator or version key, duplicate wire kinds, and
an upcaster chain with gaps.

You can see it working by running the test suite: literal JSON strings that predate a
field addition or a constructor rename (written into the tests as fixed bytes, exactly
as they would sit in a database) decode successfully through defaults and through an
upcaster, and the compile-time rejections are documented as manual compile-fail
checks following the package's existing convention.

This is Phase 5 of the master plan
`docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md`
and it gates the `0.1.0.0` Hackage release. Current keiro uses its own
`Keiro.Codec`, not this package. The keiki event-codec format is still pre-release,
so the wire format and options API may be corrected now. After Hackage users persist events, every
one of these fixes becomes a data migration.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented
here, even if it requires splitting a partially completed task into two ("done" vs.
"remaining"). This section must always reflect the actual current state of the work.

- [x] Milestone 1: `kindOverrides` wire-kind pinning; `eventTypes`/`kindMap` emit wire
      kinds; compile-time rejection of unknown override keys, duplicate wire kinds,
      and payload fields colliding with `kindFieldName`; unknown-kind decode error
      lists the allowed kinds. 2026-07-12.
- [x] Milestone 1: rename-via-pinning round-trip test and updated `THEventSpec`
      assertions green; manual compile-fail protocol extended in the
      `THEventSpec` module header. The targeted suite passed 50 examples and all
      three temporary misconfiguration builds failed with their expected messages.
      2026-07-12.
- [x] Milestone 2: versioned envelope — `versionFieldName`, `currentVersion`,
      `<prefix>SchemaVersion` binding; encode stamps the version; decode reads it
      (absent means version 1) and rejects ahead/invalid versions. 2026-07-12.
- [x] Milestone 2: envelope shape and version-error tests green, including decoding
      version-absent bytes. The targeted suite passed 55 examples. Temporary builds
      also reproduced the splice-time `currentVersion = 0` and colliding envelope-key
      failures. 2026-07-12.
- [x] Milestone 3: default-on-missing — `FieldCodec` gains `fcOnMissing`; `fieldCodec`
      smart constructor added; `Maybe`-typed passthrough fields decode a missing key
      as `Nothing`. 2026-07-12.
- [x] Milestone 3: decode-old-bytes fixture (pre-field-addition literal JSON) and
      property round-trips including `Maybe` fields green. The new evolution module
      also pins present-null behavior and required-field strictness; the targeted
      suite passed 61 examples. 2026-07-12.
- [ ] Milestone 4: upcaster chain — `upcasters :: [(Int, Name)]` option, splice-time
      completeness validation, migration applied before constructor dispatch,
      `migrateEnvelope` runtime helper.
- [ ] Milestone 4: v1-bytes-through-upcaster fixture, upcaster-error surface test,
      and manual compile-fail check for a chain gap.
- [ ] Milestone 5: documentation — `Event.hs` module haddock, `keiki-codec-json/README.md`,
      `docs/research/schema-evolution.md` finalized-contract section, `ROADMAP.md`
      sharpened-contract bullet, `keiki-codec-json/CHANGELOG.md`, asymmetric-strictness
      note; master plan 16 progress row ticked.
- [ ] Full gate: `cabal build all`, `cabal test all`, `nix fmt -- --no-cache` all clean.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- **Splice-time validation gives exact diagnostics without a runtime surface.**
  Temporary test edits reproduced all three Milestone 1 rejection paths: unknown
  override key `"Plcaed"`, duplicate wire kind `"order.event"`, and payload field
  `Placed.kind`. Restoring the valid pinned fixture produced 50 green codec examples;
  the resolved `eventTypes`, `kindMap`, encoder, decoder, and allowed-kind error all
  agree on `"order.placed"`.
- **The exact integer-version parser needs a direct dependency.** Aeson exposes
  `Number` values but not `Scientific.toBoundedInteger`; the existing transitive
  package was not directly visible to the library. Adding `scientific ^>=0.3` made
  the import explicit and preserved keiro's checked conversion semantics. The
  targeted suite passed 55 examples, including version-absent, ahead, below-one,
  and malformed stamps; temporary builds pinned the two envelope-option validation
  errors before code generation.
- **Defaulting can stay local without weakening anti-drift checks.** The literal
  pre-addition bytes omit the version, explicit-default, and `Maybe` fields yet
  decode to the declared constant and `Nothing`. A required passthrough field still
  fails with `missing field: orderId`, and 100 generated `Nothing`/`Just` values
  round-trip. Because classification still requires every field to be listed as an
  override or passthrough, the new read compatibility does not reintroduce a generic
  fallback.


## Decision Log

Record every decision made while working on the plan.

- Decision: The envelope's version field is emitted starting at version 1, and a
  missing version field on decode is treated as version 1. There is no "version 0".
  Rationale: this is a pre-release wire format and current keiro does not use it;
  treating "absent" as 1 makes hand-written or
  pre-plan JSON (which has no version field) decode against a `currentVersion = 1`
  codec with no ceremony, and it matches keiro's convention
  (`extractSchemaVersion` in `/Users/shinzui/Keikaku/bokuno/keiro/keiro-core/src/Keiro/Codec.hs`
  defaults to 1 when the stamp is absent). A dead version 0 would complicate the
  chain-coverage arithmetic for no benefit.
  Date: 2026-07-11

- Decision: The version is stored in-band, inside the payload object, under a
  configurable key defaulting to `"v"`. Keiro-style out-of-band versioning (a
  `schemaVersion` stamped into event-store metadata) remains a valid pattern and the
  two layers must not fight: a consumer that owns an envelope of its own (as keiro
  does) should keep this codec's `currentVersion` pinned at 1 and version at the
  envelope level; the in-band mechanism exists for consumers who have no envelope of
  their own. This is documented in the README and the research note (Milestone 5).
  Rationale: keiki-codec-json produces bare `Aeson.Value`s and has no metadata channel
  to stamp; in-band is the only place the derived codec can put a version. Making the
  key configurable (`versionFieldName`) lets an application align it with house style.
  Date: 2026-07-11

- Decision: Ship BOTH default-on-missing decoding and an upcaster chain, and keep
  each surface minimal. Defaults (`fcOnMissing`, plus `Maybe`-passthrough missing
  means `Nothing`) make the overwhelmingly-common additive change zero-ceremony with
  no version bump; upcasters handle structural changes (renames inside the payload,
  type reshaping, moved fields) that defaults cannot express. This mirrors the chosen
  model in `docs/research/schema-evolution.md` ("Chosen model for v1"): additive-only
  as the default convention (model c) with an explicit upcaster for everything else
  (model d).
  Rationale: either mechanism alone forces the other's use cases into awkward shapes —
  defaults cannot rename, and requiring a version bump plus an upcaster for every
  added `Maybe` field would train users to resent and skip the machinery.
  Date: 2026-07-11

- Decision: Upcasters are declared in the options as `upcasters :: [(Int, Name)]` —
  a list of (from-version, name of a top-level `Aeson.Value -> Either String
  Aeson.Value` function) — rather than as a single runtime list value. The splice
  validates at compile time that the from-versions are exactly `[1 .. currentVersion - 1]`
  with no gaps, duplicates, or out-of-range entries.
  Rationale: keiro validates its chain at construction time (`mkCodec`,
  `CodecUpcasterChainIncomplete` / `CodecDuplicateUpcasterSources` in
  `keiro-core/src/Keiro/Codec.hs`) because its codec is a runtime record; a TH splice
  can see the (version, Name) pairs at splice time and therefore reject a broken
  chain before the program even compiles, which is strictly stronger. The task brief
  allowed "at splice time where possible, else at first decode"; with this
  representation, splice time is always possible.
  Date: 2026-07-11

- Decision: Upcaster rungs are 1-to-1 (`Value -> Either String Value`) and receive
  the whole envelope object, including the kind and version keys, running BEFORE
  constructor dispatch. A rung may rewrite the kind (so an old wire kind can be
  re-pointed at a new constructor's wire kind), but a rung cannot split one stored
  event into several. The 1-to-many constructor-split case stays where
  `docs/research/schema-evolution.md` puts it: an application-level upcaster at the
  event-store boundary. The codec documentation states this limit explicitly.
  Rationale: `<prefix>FromJSON :: Aeson.Value -> Either String E` decodes one value
  to one event; widening it to lists would change the signature every consumer calls
  for a case the research note already assigns to the application layer.
  Date: 2026-07-11

- Decision: `FieldCodec` gains a third field `fcOnMissing :: Maybe Name` (naming a
  top-level constant of the field's type used when the key is absent), which breaks
  positional construction like `FieldCodec 'enc 'dec`. A smart constructor
  `fieldCodec :: Name -> Name -> FieldCodec` (with `fcOnMissing = Nothing`) is added
  so migration of existing call sites is mechanical.
  Rationale: the API is pre-release and is not used by current keiro; an
  optional-default record field is the smallest surface that lets an
  override observe "key absent" without changing `fcDecode`'s shape for everyone.
  Date: 2026-07-11

- Decision: A passthrough field whose reified type is literally `Maybe t` decodes a
  missing key as `Nothing` (the semantics of aeson's `.:?`), unconditionally and
  without a version bump. The encoder still always writes the key (`Nothing`
  encodes as JSON `null`). Type synonyms that expand to `Maybe` are NOT detected —
  only a syntactic `AppT (ConT ''Maybe) _` head (after unwrapping `SigT`) — and this
  is documented.
  Rationale: this is what "additive `Maybe` field" means in every JSON codec users
  know; the field is already explicitly listed in `passthroughFields`, so the
  anti-drift property ("adding a field forces a compile-time decision") is preserved —
  the decision was made when the field was listed. Chasing synonyms through `reify`
  adds splice cost and edge cases for little gain; a synonym user can use an
  override with `fcOnMissing` instead.
  Date: 2026-07-11

- Decision: The decoder's tolerance of unknown object keys (it simply never looks at
  keys it does not know) is KEPT and documented as intentional, even though the
  RegFile codec in `keiki-codec-json/src/Keiki/Codec/JSON.hs` rejects extras.
  Rationale: events are write-once history read by many code versions; tolerating
  unknown keys is what lets a NEWER writer's events (which carry extra fields) be
  read by an older decoder, and lets upcasters leave superseded fields in place
  rather than carefully deleting them. A snapshot (RegFile) is a checkpoint the
  current code wrote for itself, where an unknown key means corruption. The asymmetry
  is correct; the defect was only that it was undocumented (review defect 4).
  Date: 2026-07-11

- Decision: `<prefix>EventTypes` and `<prefix>KindMap` change meaning: `EventTypes`
  now lists the resolved WIRE kinds (pinned names where overridden) in declaration
  order, and `KindMap` maps constructor base name to wire kind (previously both sides
  were the constructor name). This is a behavior break for those bindings.
  Rationale: their documented purpose is to feed an event-store allow-list (keiro's
  `Codec.eventTypes` matches stored tags, i.e. wire strings); after pinning, the wire
  string is the only value an allow-list can correctly hold. Zero consumers exist,
  so the break is free now and wrong to defer.
  Date: 2026-07-11

- Decision: plan 78
  (`docs/plans/78-persistence-wire-format-hardening-golden-byte-fixtures-maybe-slot-coverage-and-stable-shape-hash-names.md`)
  owns golden BYTE fixtures and pins the envelope THIS plan ships (master plan 16,
  integration point 5). This plan's decode-old-bytes fixtures are literal JSON
  strings inline in test source — they assert semantic decoding of historical shapes,
  not byte stability. This plan must land before EP-78 records its event-envelope
  goldens.
  Rationale: recording goldens against the pre-versioning format would immediately
  invalidate them; the master plan sequences EP-78 after EP-77 for exactly this
  reason (EP-78's soft dependency on EP-77).
  Date: 2026-07-11


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

This repository is a Cabal multi-package project (GHC 9.12). The root package `keiki`
(sources under `src/`) is the pure event-sourcing core and is deliberately aeson-free.
The sibling package `keiki-codec-json/` provides opt-in JSON codecs; everything this
plan touches lives there, plus documentation files at the repository root. Enter the
development shell with `nix develop` from the repository root before building.

Two Template Haskell modules matter:

- `keiki-codec-json/src/Keiki/Codec/JSON/TH.hs` — derives snapshot (RegFile) codecs
  for single records. Not changed by this plan; cited for contrast.
- `keiki-codec-json/src/Keiki/Codec/JSON/Event.hs` — derives an event codec for a sum
  type. This is the file this plan rewrites the guts of.

"TH splice" means a Template Haskell macro: `$(deriveEventCodecSkeleton opts
''OrderEvent)` runs at compile time, inspects the `OrderEvent` type, and generates
ordinary top-level Haskell functions into the calling module. "Wire format" means the
exact JSON bytes written to the event store. A "discriminator" is the JSON key whose
value says which constructor an object encodes (here the `"kind"` key). An "upcaster"
is a pure function that rewrites a JSON payload written under an old schema version
into the shape the next version expects; a chain of them, applied in sequence, brings
any historical payload up to current.

The splice currently takes an options record:

```haskell
-- keiki-codec-json/src/Keiki/Codec/JSON/Event.hs, lines 118-128 (current tree)
data EventCodecOptions = EventCodecOptions
  { fieldCodecOverrides :: Map String FieldCodec,
    passthroughFields :: Set String,
    kindFieldName :: String,
    onMissingCodec :: OnMissingCodec
  }
```

and, for `data OrderEvent = Placed PlacedData | Shipped ShippedData | Cancelled`,
emits `orderEventToJSON`, `orderEventFromJSON`, `orderEventEventTypes`, and
`orderEventKindMap`. Each payload field is encoded by name via either an author-
supplied `FieldCodec` (a pair of `Name`s of top-level encode/decode functions), a
passthrough using the field type's aeson instances, or — if listed in neither — the
splice fails at compile time (the "no silent generic fallback" property, which this
plan preserves).

The existing test for this splice is
`keiki-codec-json/test/Keiki/Codec/JSON/THEventSpec.hs`. Its module header documents
the package's manual compile-fail protocol: behaviors that manifest as compile
failures cannot be passing unit tests, so the header spells out the exact edit to
make, the exact command to run, the exact error text to expect, and says "revert
afterwards", with a dated note that the check was performed by hand. This plan adds
new manual checks following that exact convention. The test binary is wired through
`keiki-codec-json/test/Spec.hs` (an explicit `main`, not hspec-discover) and the
`other-modules` list of the `keiki-codec-json-test` stanza in
`keiki-codec-json/keiki-codec-json.cabal` — any new test module must be added to both.

### The four verified defects (2026-07 architecture review)

Line numbers cite the current working tree.

Defect 1 — no evolution path (HIGH). `decodeFieldExpr`
(`keiki-codec-json/src/Keiki/Codec/JSON/Event.hs:371-377`) always runs `lookupField`
first; the `FieldCodec` override only ever receives a `Value` after the key was
found:

```haskell
-- Event.hs:371-377 (current tree)
decodeFieldExpr :: EventCodecOptions -> Name -> Name -> (String, Name, Type) -> Q Exp
decodeFieldExpr opts oVar ctorName (fn, _sel, _ft) =
  let getV = [|lookupField $(keyE fn) $(varE oVar)|]
   in case classify opts fn of
        Override fc -> [|$(varE (fcDecode fc)) =<< $getV|]
        Passthrough -> [|(aesonResultToEither . Aeson.fromJSON) =<< $getV|]
        Unhandled -> [|$(varE (todoName ctorName fn)) =<< $getV|]
```

`lookupField` (Event.hs:144-147) returns `Left ("missing field: " <> key)` on an
absent key, so adding ANY field to a payload record — even `Maybe t` meant to default
to `Nothing` — makes every previously stored event fail to decode, and no hook can
supply a default. No version discriminator is emitted (only the `kind` tag), so no
migration can ever be dispatched either.

Defect 2 — wire kind hard-wired to the constructor name (HIGH). The `kind` value is
`nameBase` of the Haskell constructor at encode (Event.hs:296-301, the `kindPair`
in `encodeClause`) and at decode dispatch (Event.hs:343-353, `dispatch` compares
`kind == T.pack (nameBase ctor)`). No `EventCodecOptions` field pins a wire name
independent of the constructor, so renaming `Placed` to `OrderPlaced` silently
changes the wire format and bricks decoding of every stored `{"kind":"Placed",...}`.

Defect 3 — kind collision (MEDIUM). In the payload `encodeClause` (Event.hs:289-294)
the pair list is `kindPair : map (fieldPair ...) fields` and is passed to
`Aeson.object`, whose underlying `KeyMap.fromList` is last-wins: a payload field
named `kind` (or whatever `kindFieldName` is set to) silently OVERWRITES the
discriminator at encode, and on decode the dispatcher then reads the field's value as
the kind — corrupted dispatch. The splice's validation never checks payload field
names against `kindFieldName`. This should be a compile-time `fail`.

Defect 4 — asymmetric strictness (LOW, document only). The event decoder never
inspects keys it does not know (`buildCtorDecode`, Event.hs:356-368, only looks up
declared fields), while the RegFile codec rejects unknown extras
(`regFileFromJSON` in `keiki-codec-json/src/Keiki/Codec/JSON.hs:152-162` returns
`Left "regfile: unknown extra fields: ..."`). The asymmetry is arguably right for
forward compatibility — see the Decision Log — but it is documented nowhere.

### Prior art to study

`/Users/shinzui/Keikaku/bokuno/keiro/keiro-core/src/Keiro/Codec.hs` (a sibling
project outside this repository) is the reference implementation of the whole story:
a per-stream `Codec e` record with an `eventTypes` allow-list, the wire tag stored
out-of-band (in the store's `eventType` column, not the payload), a `schemaVersion`
stamped into event metadata on append (`encodeForAppendWithMetadata`, with the stamp
authoritative over caller metadata), a read path that extracts the stamp (absent
means 1), and an upcaster chain replayed by `migrateToCurrent` (around line 266) with
typed errors for every failure mode (`GapInUpcasterChain`, `VersionAhead`,
`UpcasterError`, ...). Chain well-formedness is validated at construction by
`mkCodec`. This plan adapts those ideas to a TH splice: the allow-list becomes the
generated `EventTypes` binding, the version stamp moves in-band (this codec has no
metadata channel), and chain validation moves to compile time.

`docs/research/schema-evolution.md` is this repository's design note. It committed
keiki's pure core to being version-agnostic and put evolution at the boundary:
"explicit upcaster at the event-store boundary (model d), with additive-only as the
default convention (model c)". Per `ROADMAP.md` (the "Schema evolution" bullet around
lines 185-187), that contract was "still being sharpened against real consumers" —
this plan is the sharpening, for the codec package specifically. Nothing here touches
the `keiki` core; the note's commitment stands, and the codec's in-band mechanism is
one concrete realization of the boundary upcaster for consumers who want it derived.

The options-record idiom to mirror: `src/Keiki/Generics/TH.hs` defines
`DeriveCtorOptions { suffixOverrides :: Map String String, excludeCtors :: Set String }`
where every override key must name a real constructor (unknown keys and duplicate
resolved names abort the splice via `resolveCtorSpecs`, around lines 571-609). The new
`kindOverrides` field follows this shape and these validation manners exactly.

### The wire contract after this plan

For orientation, the complete target contract in one place. Encoding a payload
constructor produces one JSON object holding the discriminator, the version, and one
key per payload field; a singleton constructor produces just discriminator plus
version:

```json
{"kind": "order.placed", "v": 1, "orderId": "ord-7", "qty": 3}
```

with `"kind"` replaceable via `kindFieldName`, its value the pinned wire kind (from
`kindOverrides`) or the constructor name if unpinned, `"v"` replaceable via
`versionFieldName`, and its value always `currentVersion`.

Decoding proceeds: (1) require a JSON object, else
`Left "<prefix>: expected a JSON object"`; (2) read the version key — absent means 1,
a non-integer value is `Left "field v: expected an integer schema version"`, a value
below 1 is `Left "invalid event schema version: N"`, a value above `currentVersion`
is `Left "event schema version N is ahead of codec version M"`; (3) replay upcaster
rungs from the stored version up to `currentVersion`, each receiving the whole object
(a rung may rewrite anything, including the kind; the codec tracks the version
counter itself and ignores any version-key edits a rung makes), a rung failure
surfacing as `Left "upcaster from version N: <msg>"`; (4) read the kind key from the
migrated object and dispatch against the resolved wire kinds, unknown kinds failing
with `Left "unknown event kind: X (expected one of: k1, k2, ...)"`; (5) decode each
declared field — a present key goes through the override's `fcDecode` or the
passthrough `FromJSON`; an absent key uses the override's `fcOnMissing` constant if
given, decodes to `Nothing` if the field is a `Maybe`-typed passthrough, and
otherwise remains `Left "missing field: X"`. Unknown extra keys are ignored by
design (Decision Log).

Compile-time (splice) rejections, each a `fail` with a precise message: a payload
field named `kindFieldName` or `versionFieldName`; `kindFieldName` equal to
`versionFieldName`; a `kindOverrides` key that is not a constructor of the type;
two constructors resolving to the same wire kind; `currentVersion < 1`; an
`upcasters` list whose from-versions are not exactly `[1 .. currentVersion - 1]`
(gap, duplicate, or out-of-range); plus the pre-existing unhandled-field check,
unchanged.


## Plan of Work

All production edits land in `keiki-codec-json/src/Keiki/Codec/JSON/Event.hs`. Tests
land in `keiki-codec-json/test/Keiki/Codec/JSON/THEventSpec.hs` and a new module
`keiki-codec-json/test/Keiki/Codec/JSON/THEventEvolutionSpec.hs` (registered in
`keiki-codec-json/test/Spec.hs` and in the `other-modules` of the test stanza in
`keiki-codec-json/keiki-codec-json.cabal`). Documentation edits land in
`keiki-codec-json/README.md`, `keiki-codec-json/CHANGELOG.md`,
`docs/research/schema-evolution.md`, `ROADMAP.md`, and the master plan's progress
list. The milestones are ordered so the codebase compiles and the full suite passes
at the end of each one; each milestone's option additions default to today's
behavior wherever that behavior is not itself the defect.

### Milestone 1 — wire-kind pinning and collision rejection

Scope: sever the wire discriminator from the Haskell constructor name, and make the
splice reject the configurations that corrupt dispatch. At the end of this milestone
an author can write `kindOverrides = Map.fromList [("Placed", "order.placed")]`,
rename the `Placed` constructor to anything at all later, re-pin, and old bytes still
dispatch; and a payload record with a field named `kind` no longer compiles against
the default options.

In `keiki-codec-json/src/Keiki/Codec/JSON/Event.hs`:

Add `kindOverrides :: Map String String` to `EventCodecOptions` (constructor base
name to wire string), defaulting to `Map.empty` in `defaultEventCodecOptions`.
Introduce a helper `wireKindOf :: EventCodecOptions -> Name -> String` used by every
site that currently calls `nameBase` for wire purposes: the `kindPair` in
`encodeClause` (currently Event.hs:296-301), the comparison in `dispatch` (currently
Event.hs:343-353), and the `eventTypes`/`kindMap` binding generators (currently
Event.hs:234-265). `EventTypes` now lists resolved wire kinds in declaration order;
`KindMap` pairs constructor base name with resolved wire kind (Decision Log entry on
the meaning change).

Add a validation block early in `deriveEventCodecSkeletonAs` (next to the existing
unhandled-field check at Event.hs:183-208), executed against the reified constructor
list:

- every `kindOverrides` key must be a constructor base name of the type, else
  `fail "deriveEventCodecSkeleton: kindOverrides key \"Plcaed\" is not a constructor of <Type>."`
  (mirroring `resolveCtorSpecs` manners from `src/Keiki/Generics/TH.hs`);
- the resolved wire kinds must be pairwise distinct, else
  `fail "deriveEventCodecSkeleton: wire kind \"OrderPlaced\" is claimed by more than one constructor: Placed, PlacedLegacy. Wire kinds must be unique per event type."`;
- no payload field of any constructor may equal `kindFieldName opts`, else
  `fail "deriveEventCodecSkeleton: payload field Placed.kind collides with kindFieldName \"kind\"; rename the field or choose a kindFieldName no payload uses."`
  — this is the defect-3 fix; the check runs per-constructor over the reified
  `(fieldName, selector, type)` lists and reports every collision, not just the first.

Improve the unknown-kind decode error (currently
`Left ("unknown event kind: " <> T.unpack kind)` at Event.hs:353) to append the
allowed set: `unknown event kind: Nope (expected one of: Placed, Shipped, Cancelled)`
— with the resolved wire kinds spliced in as a literal. The existing
`THEventSpec` assertion on this message must be updated to match.

In `keiki-codec-json/test/Keiki/Codec/JSON/THEventSpec.hs`: pin one constructor in
the existing `OrderEvent` fixture's options (e.g. `("Placed", "order.placed")`),
update the exact-object and `KindMap`/`EventTypes` assertions accordingly, and add a
test that decodes a literal object carrying `"kind": "order.placed"` — this is the
rename-via-pinning round-trip (the wire string no longer matches any constructor
name, proving dispatch is by pinned kind). Extend the module-header manual protocol
with two new documented compile-fail checks, following the existing numbered style
verbatim: (3) duplicate wire kinds — pin two constructors to the same string, run
`cabal build keiki-codec-json:keiki-codec-json-test`, expect the duplicate-kind
message, revert; (4) kind collision — add a `kind :: Text` field to `PlacedData`
(listed in `passthroughFields` so the unhandled-field check does not mask it), expect
the collision message, revert. Perform both by hand and record the date and observed
text in the header, as the 2026-06-06 entries do.

Acceptance: `cabal test keiki-codec-json:keiki-codec-json-test` passes; the two
manual compile-fail checks reproduce their documented messages by hand.

### Milestone 2 — the versioned envelope

Scope: every encoded event carries a schema version; the decoder reads and bounds it.
At the end of this milestone `orderEventToJSON placed` contains `"v": 1`, a
version-absent object still decodes (as version 1), and a version-ahead object fails
with a precise error. No migration happens yet (that is Milestone 4); with
`currentVersion = 1` the version check is pass-through.

In `keiki-codec-json/src/Keiki/Codec/JSON/Event.hs`:

Add `versionFieldName :: String` (default `"v"`) and `currentVersion :: Int` (default
`1`) to `EventCodecOptions` and `defaultEventCodecOptions`. Extend the Milestone 1
validation block: `currentVersion >= 1` or
`fail "deriveEventCodecSkeleton: currentVersion must be >= 1, got 0."`;
`kindFieldName /= versionFieldName` or a fail naming both; no payload field may equal
`versionFieldName` (same message shape as the kind collision).

Encoder: in `encodeClause`, add a `versionPair` next to `kindPair` —
`$(keyE (versionFieldName opts)) Aeson..= (currentVersion opts :: Int)` spliced as a
literal — emitted for payload and singleton constructors alike.

Decoder: add a runtime helper to the module's "Runtime helpers" section (exported,
like `lookupField`):

```haskell
-- | Read the schema-version key: absent means version 1; present must be
-- an integral JSON number.
lookupVersion :: Key.Key -> Aeson.Object -> Either String Int
```

using `Scientific.toBoundedInteger` semantics as keiro's `extractSchemaVersion` does
(a non-number or fractional value is `Left ("field " <> key <> ": expected an integer schema version")`).
In `decoderBody`, after matching the object, bind the version, then guard: below 1
fails `invalid event schema version: N`; above the spliced `currentVersion` fails
`event schema version N is ahead of codec version M`; otherwise proceed to the kind
lookup and dispatch exactly as before (the migration hook lands here in Milestone 4).

Generate one new binding per splice: `<prefix>SchemaVersion :: Int`, the spliced
`currentVersion`, so tests, stores, and plan-78 goldens can reference the version
without repeating the literal.

In `keiki-codec-json/test/Keiki/Codec/JSON/THEventSpec.hs`: update the exact-object
assertions to include `"v": 1` (including the singleton case, which becomes
`{"kind":"Cancelled","v":1}`); add tests that (a) a literal object WITHOUT the
version key decodes successfully (version-absent-means-1), (b) `"v": 2` against the
version-1 codec yields
`Left "event schema version 2 is ahead of codec version 1"`, (c) `"v": 0` yields the
invalid-version error, (d) `"v": "one"` yields the expected-integer error, and (e)
`orderEventSchemaVersion == 1`.

Acceptance: suite green; the version-absent test is the first decode-old-bytes
fixture (bytes shaped exactly like everything the codec emitted before this plan).

### Milestone 3 — default-on-missing decoding

Scope: the additive change becomes zero-ceremony. At the end of this milestone, a
field added to a payload record decodes from old bytes either via an explicit
default (`fcOnMissing`) or, for `Maybe`-typed passthrough fields, as `Nothing` —
with no version bump and no upcaster.

In `keiki-codec-json/src/Keiki/Codec/JSON/Event.hs`:

Extend `FieldCodec` with `fcOnMissing :: Maybe Name` and add the smart constructor
`fieldCodec :: Name -> Name -> FieldCodec` (both exported; haddock on `fcOnMissing`
states it names a top-level CONSTANT of the field's type, e.g.
`missingOrderId :: OrderId`, used only when the key is absent). Update the module
haddock's field-classification story.

Rework `decodeFieldExpr` (the defect-1 site, Event.hs:371-377) so the absent-key case
is observable. Add a runtime helper:

```haskell
-- | Total lookup: 'Nothing' when the key is absent.
lookupFieldMaybe :: Key.Key -> Aeson.Object -> Maybe Aeson.Value
```

and generate, per field: for an `Override fc` with `fcOnMissing = Just def`, a case
on `lookupFieldMaybe` — `Just v` runs `fcDecode =<<`-style decoding as today,
`Nothing` yields `Right def`; for an override without a default, exactly today's
code; for a `Passthrough` field whose reified type is syntactically `Maybe t`
(unwrap `SigT`, match `AppT (ConT m) _` with `m == ''Maybe`), `Nothing` yields
`Right Nothing` and `Just v` runs the aeson decode (note `FromJSON (Maybe t)` maps
JSON `null` to `Nothing` too, so present-null and absent agree); for every other
passthrough, today's strict code. The `Unhandled` branch is unreachable in practice
(the compile-time check fires first) and stays as-is.

In `keiki-codec-json/test/Keiki/Codec/JSON/THEventEvolutionSpec.hs` (new module; add
to `keiki-codec-json/test/Spec.hs` and the cabal `other-modules`): define an event
fixture whose payload has (a) an override field with `fcOnMissing` and (b) a
`note :: Maybe Text` passthrough field. Tests: a LITERAL pre-addition JSON string
(no `note`, no defaulted field, no `"v"`) — written as fixed bytes with a comment
saying "these bytes predate the note/discount fields; do not regenerate them" —
decodes to the expected value with the default and `Nothing` filled in; a
present-`null` `note` decodes to `Nothing`; round-trip still exact for fully
populated values. Add QuickCheck property round-trips over the fixture event
(generator covering `Nothing` and `Just` for the `Maybe` field):
`fromJSON (toJSON e) === Right e`, following the `forAllShow` style of
`keiki-codec-json/test/Keiki/Codec/JSON/PropSpec.hs`. Also assert the preserved
strictness: removing a REQUIRED (no-default, non-`Maybe`) field from a literal object
still yields `Left "missing field: ..."`.

Update the one existing `FieldCodec 'orderIdToJSON 'orderIdFromJSON` call site in
`THEventSpec.hs` to the `fieldCodec` smart constructor.

Acceptance: suite green, including the literal old-bytes decode and the properties.

### Milestone 4 — the upcaster chain

Scope: structural changes get a migration path. At the end of this milestone a codec
declared at `currentVersion = 2` with one upcaster decodes v1 bytes (and
version-absent bytes) by rewriting the JSON before dispatch, and a chain with a gap
does not compile.

In `keiki-codec-json/src/Keiki/Codec/JSON/Event.hs`:

Add `upcasters :: [(Int, Name)]` to `EventCodecOptions` (default `[]`); each `Name`
must refer to a top-level `Aeson.Value -> Either String Aeson.Value`. Extend the
validation block: the sorted from-versions must equal `[1 .. currentVersion - 1]`
exactly — report duplicates
(`fail "deriveEventCodecSkeleton: duplicate upcaster from-versions: [1]"`), gaps or
missing rungs
(`fail "deriveEventCodecSkeleton: upcasters must cover from-versions [1..2] exactly; missing: [2]"`),
and out-of-range entries (a from-version below 1 or at/above `currentVersion`). With
`currentVersion = 1` the only valid list is empty, so existing splices stay valid.

Add the runtime migration helper (exported, mirroring keiro's `migrateToCurrent` at
`keiro-core/src/Keiro/Codec.hs` ~line 266, minus the gap errors that compile-time
completeness has already excluded):

```haskell
-- | Replay upcaster rungs from the stored version up to the current
-- version. The chain is compile-time-complete, so the only runtime
-- failure is a rung rejecting its input.
migrateEnvelope ::
  Int ->                                            -- current version
  [(Int, Aeson.Value -> Either String Aeson.Value)] -> -- complete chain
  Int ->                                            -- stored version
  Aeson.Value ->
  Either String Aeson.Value
```

which drops rungs below the stored version, applies the rest in ascending order, and
wraps a rung's `Left msg` as `Left ("upcaster from version N: " <> msg)`. In
`decoderBody`, between the Milestone 2 version guard and the kind lookup, splice
`migrateEnvelope <currentVersion> [(1, up1), ...] version (Aeson.Object o)` (the
chain as a literal list of `varE`-spliced names) and re-match the migrated `Value`
as an object before dispatch (a rung returning a non-object fails with the existing
expected-a-JSON-object message). Dispatch and field decoding then run on the
MIGRATED object — upcasting happens strictly before constructor dispatch, so a rung
may rewrite the kind key.

In `keiki-codec-json/test/Keiki/Codec/JSON/THEventEvolutionSpec.hs`: add a second
fixture event type spliced at `currentVersion = 2` with
`upcasters = [(1, 'upcastV1)]` where `upcastV1` renames a payload key (say `qty` to
`quantity`) inside the JSON object — a rename is the canonical structural change
defaults cannot express. Tests: a literal v1 object (`"v": 1`, old key) decodes to
the current-shape value; a literal VERSION-ABSENT object with the old key also
decodes (absent means 1, so it rides the same rung); a literal `"v": 2` object with
the new key decodes without invoking the rung; a rung failure (feed an object the
upcaster rejects) surfaces as `Left "upcaster from version 1: ..."`; and
`<prefix>SchemaVersion == 2`. Extend the manual compile-fail protocol in the
`THEventSpec` header (keeping all such documentation in one place) with check (5):
set `currentVersion = 3` while supplying only the from-version-1 rung, build, expect
the missing-rung message, revert. Perform it by hand and record the date.

Acceptance: suite green; the v1-bytes fixtures prove bytes written before a
structural change decode after it.

### Milestone 5 — documentation and contract finalization

Scope: state the finalized contract everywhere a consumer will look, and close the
review's documentation defect. No code changes.

Rewrite the module haddock of `keiki-codec-json/src/Keiki/Codec/JSON/Event.hs` to
present the envelope (`kind` + `v` + fields), the decode pipeline order
(version guard, migrate, dispatch, fields-with-defaults), the evolution guidance
(additive changes: `Maybe` passthrough or `fcOnMissing`, no version bump; structural
changes: bump `currentVersion` and add a rung; constructor renames: pin the old wire
kind), the 1-to-1 rung limit with a pointer to `docs/research/schema-evolution.md`
for the application-level 1-to-many case, and — closing defect 4 — an explicit
"unknown keys are ignored" paragraph contrasting the RegFile codec's strictness and
giving the forward-compatibility rationale from the Decision Log.

Update `keiki-codec-json/README.md`'s "Deriving an event codec skeleton" section: the
example gains `"v":1` in its shown output, and a new "Evolving an event schema"
subsection walks the three moves (add a field, rename a constructor, restructure a
payload) with the exact options to set for each, plus the two-layer versioning note:
keiro-style out-of-band metadata versioning remains valid — a consumer that owns an
envelope (as keiro does with `schemaVersion` in event metadata) should pin
`currentVersion = 1` here and version at its own layer; the in-band `"v"` field is
for consumers without an envelope of their own; running both layers with different
numbers is a configuration error, not something either layer detects.

Update `docs/research/schema-evolution.md` with a dated addendum section, "The
derived codec's realization of this contract (EP-77)", stating: the chosen model
(d + c) is unchanged; `keiki-codec-json`'s derived codec now ships an OPT-IN in-band
realization (version field, pinned wire kinds, compile-time-complete 1-to-1 upcaster
chain, default-on-missing); the 1-to-many split case remains at the application
boundary exactly as this note specifies; and the keiki core remains version-agnostic.
Update `ROADMAP.md`'s "Schema evolution" bullet (around lines 185-187) from "the
contract is still being sharpened against real consumers" to a statement that the
codec-level contract is finalized by this plan, with a link to this plan file. Add a
`keiki-codec-json/CHANGELOG.md` entry under the unreleased heading enumerating the
breaking option/API changes (new `EventCodecOptions` fields, `FieldCodec.fcOnMissing`
+ `fieldCodec`, `EventTypes`/`KindMap` now wire-kind-valued, envelope gains `"v"`).
Tick the EP-77 progress row in
`docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md`
and set the registry row's status.

Acceptance: `nix fmt -- --no-cache` clean; a reader of the README alone can perform
each of the three evolution moves without opening `Event.hs`.


## Concrete Steps

All commands run from the repository root, `/Users/shinzui/Keikaku/bokuno/keiki`,
inside the dev shell. Enter it once per session:

```sh
cd /Users/shinzui/Keikaku/bokuno/keiki
nix develop
```

Before writing any code, read in full: `keiki-codec-json/src/Keiki/Codec/JSON/Event.hs`,
`keiki-codec-json/test/Keiki/Codec/JSON/THEventSpec.hs`,
`/Users/shinzui/Keikaku/bokuno/keiro/keiro-core/src/Keiro/Codec.hs`,
`docs/research/schema-evolution.md`, and the `DeriveCtorOptions`/`resolveCtorSpecs`
region of `src/Keiki/Generics/TH.hs`.

Per milestone, the loop is:

```sh
cabal build keiki-codec-json
cabal test keiki-codec-json:keiki-codec-json-test
```

A passing test run ends like:

```text
Finished in 0.XXXX seconds
NN examples, 0 failures
Test suite keiki-codec-json-test: PASS
```

For each documented manual compile-fail check (Milestones 1 and 4): make the
described temporary edit, run
`cabal build keiki-codec-json:keiki-codec-json-test`, confirm the build FAILS with
the documented message (for example, for the duplicate-kind check):

```text
test/Keiki/Codec/JSON/THEventSpec.hs: error:
    deriveEventCodecSkeleton: wire kind "order.placed" is claimed by more
    than one constructor: Placed, Shipped. Wire kinds must be unique per
    event type.
```

then `git checkout -- keiki-codec-json/test` to revert, rebuild, and record the date
and observed text in the `THEventSpec` module header.

Before each commit, run the full gate:

```sh
cabal build all
cabal test all
nix fmt -- --no-cache
```

Commit per milestone with conventional-commit messages on the current branch, e.g.:

```text
feat(codec-json): pin event wire kinds and reject kind collisions at splice time
feat(codec-json): stamp and check an in-band schema version on event envelopes
feat(codec-json): default-on-missing decoding for additive event fields
feat(codec-json): compile-time-validated upcaster chain before event dispatch
docs(codec-json): finalize the event schema-evolution contract
```

Keep the Progress checklist and Decision Log in this file current at every stopping
point; that is part of each milestone, not an afterthought.


## Validation and Acceptance

The change is proven by behavior, not compilation. The headline acceptance scenarios,
all of which are tests added by this plan (module names per the Plan of Work):

1. Old bytes survive a field addition. A literal JSON string containing neither the
   `note` field, the defaulted field, nor a `"v"` key — byte-identical to what the
   pre-plan codec emitted — decodes to `Right` with `Nothing` and the declared
   default filled in (`THEventEvolutionSpec`, Milestone 3). Before this plan the
   same input fails with `Left "missing field: note"`; the review verified that
   failure against `decodeFieldExpr` (Event.hs:371-377).

2. Old bytes survive a constructor rename. An object whose `"kind"` is a pinned wire
   string matching no constructor name decodes correctly, and encoding produces that
   pinned string (`THEventSpec`, Milestone 1).

3. Old bytes survive a structural change. A literal `"v": 1` object (and a
   version-absent twin) decodes through the from-version-1 rung against a
   `currentVersion = 2` codec; the rung demonstrably ran (the payload key it renames
   is only correct post-rung) (`THEventEvolutionSpec`, Milestone 4).

4. Misconfiguration cannot compile. The manual compile-fail protocol in the
   `THEventSpec` header reproduces, by hand: duplicate wire kinds; a payload field
   named `kind`; an upcaster chain with a missing rung. Each check's observed error
   text and date are recorded in the header, matching the package's 2026-06-06
   precedent.

5. Bounds are enforced at decode. `"v"` ahead of the codec, below 1, or non-integral
   each produce their exact documented `Left` (`THEventSpec`, Milestone 2).

6. Nothing regressed. Property round-trips (including `Maybe`-field generators
   covering `Nothing` and `Just`) pass; required fields without defaults still fail
   on absence with `missing field: X`; the full pre-existing suite passes unchanged
   except for assertions this plan deliberately updates (envelope now contains
   `"v"`, `EventTypes`/`KindMap` now wire-kind-valued, unknown-kind message now
   lists the allowed set).

The exact commands and the expected `0 failures` transcript are in Concrete Steps.
Final gate: `cabal build all`, `cabal test all`, and `nix fmt -- --no-cache` all
succeed from the repository root.


## Idempotence and Recovery

Every step is additive code or documentation in a git working tree; re-running any
build or test command is safe and side-effect-free. The manual compile-fail checks
temporarily break the build by design — perform them on a clean tree and recover
with `git checkout -- keiki-codec-json/test` (or `git stash`) as the protocol
instructs; never commit the temporary edit. If a milestone is interrupted midway,
the Progress checklist entry must be split into done/remaining before stopping, and
the tree left compiling (each milestone is structured so its options default to
current behavior until its tests flip on the new one). No step touches a database,
network, or generated artifact; there is nothing to back up. If `nix fmt` reformats
more than the files you touched, that indicates a stale formatter cache — the
`--no-cache` flag in the gate command exists precisely for this (see the memory note
on the canonical fourmolu config); commit only your intended files.


## Interfaces and Dependencies

No new package dependencies. Everything uses what
`keiki-codec-json/keiki-codec-json.cabal` already depends on: `aeson ^>=2.2`
(`Data.Aeson`, `Data.Aeson.Key`, `Data.Aeson.KeyMap`), `containers`, `text`,
`template-haskell`, and — new imports within existing deps if needed for
`lookupVersion` — `Data.Scientific` via aeson's re-exports or a direct `scientific`
dependency only if aeson's API does not suffice (keiro uses
`Scientific.toBoundedInteger`; `aeson` depends on `scientific`, but if the module is
not re-exported, add `scientific` to the library's `build-depends`). Tests
additionally use the already-present `hspec` and `QuickCheck`.

At the end of Milestone 4, `keiki-codec-json/src/Keiki/Codec/JSON/Event.hs` exports
exactly this public surface (existing items unchanged unless noted):

```haskell
module Keiki.Codec.JSON.Event
  ( -- * Options
    FieldCodec (..),      -- fcEncode, fcDecode :: Name; NEW fcOnMissing :: Maybe Name
    fieldCodec,           -- NEW :: Name -> Name -> FieldCodec (fcOnMissing = Nothing)
    OnMissingCodec (..),
    EventCodecOptions (..),
    defaultEventCodecOptions,

    -- * Splices
    deriveEventCodecSkeleton,
    deriveEventCodecSkeletonAs,

    -- * Runtime helpers (referenced by generated code)
    lookupField,
    lookupFieldMaybe,     -- NEW :: Key.Key -> Aeson.Object -> Maybe Aeson.Value
    lookupText,
    lookupVersion,        -- NEW :: Key.Key -> Aeson.Object -> Either String Int
    migrateEnvelope,      -- NEW :: Int -> [(Int, Aeson.Value -> Either String Aeson.Value)]
                          --        -> Int -> Aeson.Value -> Either String Aeson.Value
    aesonResultToEither,
  )
where
```

with the options record finalized as:

```haskell
data EventCodecOptions = EventCodecOptions
  { fieldCodecOverrides :: Map String FieldCodec,
    passthroughFields :: Set String,
    kindFieldName :: String,        -- default "kind"
    kindOverrides :: Map String String, -- NEW: ctor base name -> wire kind; default empty
    versionFieldName :: String,     -- NEW: default "v"
    currentVersion :: Int,          -- NEW: default 1; must be >= 1
    upcasters :: [(Int, Name)],     -- NEW: from-version -> top-level
                                    --   Aeson.Value -> Either String Aeson.Value;
                                    --   must cover [1 .. currentVersion - 1] exactly
    onMissingCodec :: OnMissingCodec
  }
```

and per splice on an event type `E` with prefix `e`, the generated bindings:

```haskell
eToJSON        :: E -> Aeson.Value               -- envelope: kind + v + fields
eFromJSON      :: Aeson.Value -> Either String E -- version guard, migrate, dispatch
eEventTypes    :: [Data.Text.Text]               -- resolved WIRE kinds, decl order
eKindMap       :: [(Data.Text.Text, Data.Text.Text)] -- (ctor base name, wire kind)
eSchemaVersion :: Int                            -- NEW: the spliced currentVersion
```

Related but explicitly out of scope: the `keiki` core (stays version-agnostic per
`docs/research/schema-evolution.md`), the RegFile codec's strictness (unchanged;
documented contrast only), golden BYTE fixtures (owned by
`docs/plans/78-persistence-wire-format-hardening-golden-byte-fixtures-maybe-slot-coverage-and-stable-shape-hash-names.md`,
which pins the envelope this plan ships), and any 1-to-many upcasting (application
boundary, per the research note).
