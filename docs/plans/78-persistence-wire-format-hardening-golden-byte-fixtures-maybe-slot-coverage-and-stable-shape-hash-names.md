---
id: 78
slug: persistence-wire-format-hardening-golden-byte-fixtures-maybe-slot-coverage-and-stable-shape-hash-names
title: "Persistence wire-format hardening: golden byte fixtures, Maybe slot coverage, and stable shape-hash names"
kind: exec-plan
created_at: 2026-07-12T04:16:45Z
intention: "intention_01kxc5whw1en3ra4nh728m53ka"
master_plan: "docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md"
---

# Persistence wire-format hardening: golden byte fixtures, Maybe slot coverage, and stable shape-hash names

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

keiki is an event-sourcing library. In event sourcing, the serialized bytes ARE the
database: a snapshot written by today's build must still decode under next year's
build, or real production state is lost. Today keiki's JSON codec (`keiki-codec-json`)
and shape hash (`Keiki.Shape`) are tested only by round-trip properties that encode
and decode with the *same* compiled code — a test shape that can never detect the
exact failure it exists to prevent, namely the current build drifting away from bytes
a previous build persisted. Worse, the shape hash — advertised as "GHC-upgrade-safe"
in `src/Keiki/Shape.hs:6` — actually renders GHC-internal module names like
`GHC.Internal.Maybe.Maybe` into the hashed string, names that have already moved once
in GHC's history, so every future GHC major upgrade would silently flip every hash in
every deployment.

After this plan, a reader can delete their build products, check out the repo, run
`cabal test all`, and watch tests decode JSON *files that are checked into git* —
proving byte-level backward compatibility rather than self-consistency. They can
render a `Maybe`-typed slot and see the documented wire rule for it. They can read
the canonical shape-hash input for the exemplar slot list and see plain names
(`Int`, `Maybe(Text)`) with no GHC-internal module paths in sight. And they can
encode a half-initialized register file and get a documented, targeted error instead
of an undocumented crash from pure code.

The one existing production consumer is keiro. Its snapshot codec
(`/Users/shinzui/Keikaku/bokuno/keiro/keiro/src/Keiro/Snapshot/Codec.hs:23-41`)
imports exactly `RegFileToJSON`, `regFileFromJSON`, `regFileToJSON`, and
`regFileShapeHash`, so every API change in this plan must be additive to those
surfaces. Shape-hash *value* changes are safe for keiro: a mismatched hash makes
`hydrateWithSnapshot` (`keiro/src/Keiro/Snapshot.hs:50-77`) treat the snapshot as a
benign cache miss and fall back to full event replay. This plan changes hash values
once (Milestone 1) and says so loudly.


## Progress

- [ ] M1: pin stable literal names in every built-in `CanonicalTypeName` instance in `src/Keiki/Shape.hs`
- [ ] M1: make container instances (`Maybe`, `[]`, `Either`, tuples) recurse through `canonicalTypeName` so user overrides compose
- [ ] M1: update pinned values in `test/Keiki/ShapeSpec.hs` and `keiki-codec-json/test/Keiki/Codec/JSON/GoldenSpec.hs`
- [ ] M1: add the no-`GHC.Internal` sensitivity test and full pinned canonical string for `ExemplarSlots`
- [ ] M1: document the one-time hash migration (Haddock + both CHANGELOGs, keiro impact statement)
- [ ] M2: create `keiki-codec-json/test/golden/` fixture files (exemplar Value path, exemplar Encoding path, shape canonical+hash)
- [ ] M2: new spec `keiki-codec-json/test/Keiki/Codec/JSON/GoldenFileSpec.hs` with both test directions and `KEIKI_UPDATE_GOLDENS` regeneration mode
- [ ] M2: wire GoldenFileSpec into `keiki-codec-json/test/Spec.hs` and the cabal file (`other-modules`, `extra-source-files`)
- [ ] M2: additive downstream helper `Keiki.Codec.JSON.Test.GoldenFile` in `keiki-codec-json-test` with demo usage and demo golden file
- [ ] M3: add `MaybeSlots` and `NestedMaybeSlots` to `keiki-codec-json/test/Keiki/Codec/JSON/Fixtures.hs`
- [ ] M3: add inductive `EqRegFile` and strengthen in-tree round-trip properties to value-level comparison
- [ ] M3: golden files for `MaybeSlots` (all-`Just` and all-`Nothing` variants) plus absent-key negative test
- [ ] M3: targeted `Just Nothing` collapse unit tests and the "nested Maybe" wire-rule documentation
- [ ] M3: additive `regFileCodecPropsEq` + `EqRegFile` export in `keiki-codec-json-test`, with the byte-idempotence limitation documented on the old `regFileCodecProps`
- [ ] M4: sharpen the uninit-slot error message in `src/Keiki/Generics.hs`
- [ ] M4: document the fully-initialized precondition on `RegFileToJSON` methods, module header, and `keiki-codec-json/README.md`
- [ ] M4: pin the throwing behavior with a `shouldThrow` test
- [ ] M5: reuse EP-70's duplicate-slot-name guard (`DistinctNames (Names rs)`) on the `RegFileToJSON` instance, with documented manual negative test
- [ ] M5: early record-payload validation on the TH command side (`src/Keiki/Generics/TH.hs`)
- [ ] M5: `reportWarning` for constructors silently skipped by the `*All` TH variants
- [ ] M5: repair mangled Haddock in `src/Keiki/Generics/TH.hs` and `keiki-codec-json/src/Keiki/Codec/JSON/TH.hs`; verify rendered HTML
- [ ] M6 (gated on EP-77): golden fixture files for the versioned event envelope under `keiki-codec-json/test/golden/event/`
- [ ] Final: `cabal build all`, `cabal test all`, `cabal haddock all`, `nix fmt -- --no-cache` all clean; master plan registry row and progress checkbox updated


## Surprises & Discoveries

Findings verified while authoring this plan (2026-07-11). Move or append new entries
here as implementation proceeds.

- The round-trip properties compare re-encoded bytes, not values:
  `Aeson.encode (regFileToJSON rf') === bytes` at
  `keiki-codec-json/test/Keiki/Codec/JSON/PropSpec.hs:53` and the library-ised copy at
  `keiki-codec-json-test/src/Keiki/Codec/JSON/Test.hs:161`. This passes even when
  decode-after-encode changed the value, because a changed value can re-encode to the
  same bytes (exactly what happens with `Just Nothing` → `null` → `Nothing`).
- `ExemplarSlots` (`keiki-codec-json/test/Keiki/Codec/JSON/Fixtures.hs:50-54`) is
  `Int`/`UTCTime`/`Text` only. No `Maybe` appears in any codec test fixture in the
  repository.
- The `CanonicalTypeName` escape hatch does not compose: a user override for `Foo` is
  ignored inside `Maybe Foo`, because `instance (Typeable a) => CanonicalTypeName
  (Maybe a)` (`src/Keiki/Shape.hs:122`) falls through to the `Typeable` default for
  the whole application instead of recursing through `canonicalTypeName @a`. M1's fix
  repairs this as a side effect.
- Duplicate slot names already fail on the *decode* path: `regFileReadObject` deletes
  each consumed key (`keiki-codec-json/src/Keiki/Codec/JSON.hs:114`), so the second
  slot with the same name reports "missing slot". Only the encode direction corrupts
  silently (Value path last-wins via `Aeson.object`; Encoding path emits a duplicate
  key, which is legal JSON but ambiguous to consumers).
- The Value path and the Encoding path deliberately emit different key orders
  (alphabetical KeyMap order vs slot-list order — pinned by the test at
  `keiki-codec-json/test/Spec.hs:135-149`), so golden files must exist for both
  paths separately.
- A `Nothing` slot encodes as an explicit JSON `null` (the codec uses `.=`, which
  never omits keys), and the strict decoder rejects an *absent* key with "missing
  slot" (`keiki-codec-json/src/Keiki/Codec/JSON.hs:109-110`). This is a real wire
  rule that nothing currently documents or pins.


## Decision Log

- Decision: Do the shape-hash name migration (M1) before pinning any golden files (M2).
  Rationale: M1 changes hash values; pinning goldens first would mean regenerating
  them one milestone later. Ordering the value-changing work first means every golden
  in this plan is written exactly once.
  Date: 2026-07-11 (authoring).

- Decision: Pin built-in canonical names as bare literals (`"Int"`, `"Text"`,
  `"UTCTime"`, ...) and make container instances recurse via `canonicalTypeName`,
  changing their constraint from `Typeable a` to `CanonicalTypeName a`.
  Rationale: literals are immune to GHC module reshuffles by construction (the
  `GHC.Maybe` → `GHC.Internal.Maybe` move at GHC 9.10 proves the Typeable route is
  not upgrade-safe, contradicting `src/Keiki/Shape.hs:6-12`). Recursing through the
  class fixes the non-composing escape hatch. The constraint change is a compile-time
  strengthening: a consumer with a slot `Maybe Foo` now needs `CanonicalTypeName Foo`
  (one `deriving anyclass` line). This is technically a PVP-major change; keiro's
  slot types are covered built-ins and records that derive `CanonicalTypeName`, so
  keiro compiles unchanged. The hash VALUE change is benign for keiro: stale hashes
  are a cache miss falling back to full replay (`keiro/src/Keiro/Snapshot.hs:50-77`).
  Both facts must be stated in the CHANGELOG.
  Date: 2026-07-11 (authoring).

- Decision: Accept aeson's `Just Nothing` collapse as the wire semantics; document
  "nested `Maybe` is not faithfully representable; avoid `Maybe (Maybe _)` slots" as
  a wire-format rule; do NOT add a compile-time rejection of nested `Maybe`.
  Rationale: aeson's `ToJSON (Maybe a)` maps both `Nothing` and `Just Nothing` to
  `null`; the decoder cannot distinguish them. Rejecting `Maybe (Maybe _)` at the
  instance level would require a custom `TypeError`, which is an error, not a
  warning — a breaking API change disproportionate to the risk (GHC has no
  warning-level constraint mechanism to attach to an instance). Documentation plus a
  pinned unit test showing the collapse is honest and additive. Revisit if a consumer
  actually ships a nested-Maybe slot.
  Date: 2026-07-11 (authoring).

- Decision: For uninitialized-slot encoding, choose option (b): document loudly that
  snapshot encoding requires a fully-written register file, sharpen the error thunk's
  message, and pin the throwing behavior with a test. Do not ship a spoon-style total
  `regFileToJSONEither` in this plan.
  Rationale: a `try`/`evaluate` probe under `unsafePerformIO` would be honest for
  `error` thunks specifically, but it only detects WHNF errors — a slot holding a
  non-error thunk that throws deeper in would still escape, giving false confidence;
  an initialized-slot bitmap threads new state through `RegFile` and is too invasive
  for a v0.1 patch. keiro is not exposed: it builds register files from fully
  populated records via the generics bridge, never from `emptyRegFile`. A total
  `regFileToJSONEither` remains possible later as a purely additive API.
  Date: 2026-07-11 (authoring).

- Decision: Guard duplicate slot names at compile time by reusing EP-70's canonical
  `DistinctNames (Names rs)` constraint from `Keiki.Internal.Slots` on the catch-all
  `RegFileToJSON` instance, plus Haddock documenting the
  runtime behavior for anyone on an older version.
  Rationale: duplicate names silently lose data on the Value encode path and can
  never round-trip (decode already fails), so no working program is rejected by the
  guard. keiro derives its slot lists from record fields (`RegFieldsOf`), which are
  necessarily distinct, so keiro compiles unchanged; the implementation must confirm
  this by building keiro against the modified keiki (see Validation). Fallback if the
  guard proves troublesome (compile-time blowup on long lists, or a legitimate
  duplicate emerges): drop the constraint, keep the documentation, and record the
  reversal here.
  Date: 2026-07-11 (authoring).

- Decision: Make the `*All` TH variants report skipped constructors via TH's
  `reportWarning` rather than failing.
  Rationale: `conNames` returns `[]` for `GadtC`/`ForallC`
  (`src/Keiki/Generics/TH.hs:534-538`), so today such constructors silently vanish
  from the enumeration. Failing outright would break any hypothetical consumer that
  relies on the skip; a compile-time warning surfaces the gap without breaking.
  Date: 2026-07-11 (authoring).

- Decision: Golden regeneration is a deliberate two-step manual protocol driven by
  the `KEIKI_UPDATE_GOLDENS` environment variable, and the regenerating run always
  FAILS the suite.
  Rationale: regeneration must never be something CI can do implicitly (that would
  reduce the goldens back to self-consistency checks). Failing the regenerating run
  forces a second, clean run plus a human `git diff` review before commit.
  Date: 2026-07-11 (authoring).

- Decision: Event-envelope goldens (M6) are sequenced after EP-77
  (`docs/plans/77-event-codec-schema-evolution-version-tags-wire-kind-pinning-and-default-on-missing-decoding.md`)
  and pin whatever envelope EP-77 ships; every other milestone here is independent
  of EP-77 and must not wait for it.
  Rationale: master plan integration point 5 (`docs/masterplans/16-...md`): EP-77 may
  correct its pre-release event format (which current keiro does not use); pinning the
  pre-EP-77 envelope would freeze bytes EP-77 is about to discard.
  Date: 2026-07-11 (authoring).


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

This repository (`/Users/shinzui/Keikaku/bokuno/keiki`) is a cabal multi-package
Haskell project (GHC 9.12, entered via `nix develop`). Three packages matter here:

- `keiki` (root package, sources under `src/`): the aeson-free core. Two files are
  touched: `src/Keiki/Shape.hs` (the shape hash) and `src/Keiki/Generics.hs`
  (`emptyRegFile`), plus `src/Keiki/Generics/TH.hs` (Template Haskell splices).
  Its test suite is `keiki-test` with driver `test/Spec.hs` and the shape tests in
  `test/Keiki/ShapeSpec.hs`.
- `keiki-codec-json`: the JSON codec for register files. Library modules:
  `keiki-codec-json/src/Keiki/Codec/JSON.hs` (the `RegFileToJSON` class),
  `keiki-codec-json/src/Keiki/Codec/JSON/TH.hs` (record-to-codec splice),
  `keiki-codec-json/src/Keiki/Codec/JSON/Event.hs` (event-sum codec splice, being
  redesigned by EP-77). Test suite `keiki-codec-json-test` (a *test-suite component*,
  not the package of the same name) with driver `keiki-codec-json/test/Spec.hs` and
  spec modules under `keiki-codec-json/test/Keiki/Codec/JSON/` (`Fixtures.hs`,
  `PropSpec.hs`, `GoldenSpec.hs`, `SensitivitySpec.hs`, `THSpec.hs`,
  `THEventSpec.hs`).
- `keiki-codec-json-test` (a separate *package*): a published toolkit downstream
  consumers wire into their own test suites. Library modules
  `keiki-codec-json-test/src/Keiki/Codec/JSON/Test.hs` and
  `keiki-codec-json-test/src/Keiki/Codec/JSON/Test/Golden.hs`; self-test driver
  `keiki-codec-json-test/test/Spec.hs` with fixtures in
  `keiki-codec-json-test/test/Keiki/Codec/JSON/Test/Demo.hs`.

Terms used below:

A *register file* (`RegFile rs` in `src/Keiki/Core.hs`) is a heterogeneous record
indexed by a type-level list of *slots*, where a slot is a pair of a name (a
type-level string, `Symbol`) and a value type — e.g.
`'[ '("retryCount", Int), '("note", Text) ]`. It is the mutable-state half of a
keiki workflow; snapshotting a workflow means serializing its register file.

The *shape hash* (`regFileShapeHash`, `src/Keiki/Shape.hs:177-178`) is a SHA-256
over a canonical text rendering of the slot list — each slot contributes
`<name>:<canonical type name>;`, the empty list contributes `regfile:0`. Snapshot
stores key persisted snapshots by this hash; if the register layout changes, the
hash changes, and old snapshots are ignored rather than mis-decoded. The canonical
name of each type currently comes from `CanonicalTypeName`
(`src/Keiki/Shape.hs:71-74`), whose default renders the `Typeable` representation
via `renderStableTypeRep` — producing module-qualified names such as
`GHC.Internal.Maybe.Maybe(GHC.Types.Int)`. All twenty-odd built-in instances at
`src/Keiki/Shape.hs:84-130` are empty-bodied, i.e. they all use that default.

A *golden test* pins an expected artifact (bytes, a string, a hash) and fails when
the code's current output diverges. A *golden file* stores those bytes in a
checked-in file so that the expectation physically survives recompilation — the
current build decodes bytes it did not produce. The repo already has in-source
golden values (`test/Keiki/ShapeSpec.hs:49-61`,
`keiki-codec-json/test/Keiki/Codec/JSON/GoldenSpec.hs:22-24`, and the downstream
`slotGoldenSpec` helper at
`keiki-codec-json-test/src/Keiki/Codec/JSON/Test/Golden.hs:70-81`) but zero golden
*files*: nothing anywhere decodes bytes from disk.

The consumer contract (master plan integration point 6): keiro's load-bearing
imports from these packages are `RegFileToJSON`, `regFileToJSON`,
`regFileFromJSON` (`keiro/src/Keiro/Snapshot/Codec.hs:23`, used at lines 41-45 and
66) and `regFileShapeHash` (line 41). Changes to those must be additive — new
functions and new modules are fine; changed signatures or removed exports are not.
Shape-hash value changes are explicitly tolerated by keiro's design and must be
called out in the CHANGELOG, not silently shipped.

Build and check commands, all run from the repository root inside `nix develop`:

```bash
cabal build all
cabal test all
cabal haddock all
nix fmt -- --no-cache
```


## Plan of Work

### Milestone 1 — GHC-stable canonical names in the shape hash

Scope: `src/Keiki/Shape.hs`, `test/Keiki/ShapeSpec.hs`,
`keiki-codec-json/test/Keiki/Codec/JSON/GoldenSpec.hs`, `CHANGELOG.md` (root
package) and `keiki-codec-json/CHANGELOG.md`. At the end, no built-in slot type
contributes a GHC module path to the hash input, and the one-time hash migration is
documented. This milestone changes hash values fleet-wide, which is why it runs
before any golden file is pinned.

The problem, concretely: `regFileShapeCanonical` for
`'[ '("retryCount", Int) ]` currently renders `retryCount:GHC.Types.Int;regfile:0`,
and a `Maybe Int` slot renders `GHC.Internal.Maybe.Maybe(GHC.Types.Int)` — the test
at `test/Keiki/ShapeSpec.hs:33-34` pins exactly that internal name. `GHC.Maybe`
became `GHC.Internal.Maybe` at GHC 9.10, so this exact name has already moved once;
when it moves again, every persisted snapshot hash in every keiro deployment goes
stale simultaneously (benign — full replay — but fleet-wide and pointless).

Edit `src/Keiki/Shape.hs` as follows. Give every nullary built-in instance
(`src/Keiki/Shape.hs:84-120`) an explicit body pinning the bare Haskell-source name
as a literal, for example:

```haskell
instance CanonicalTypeName Int where
  canonicalTypeName _ = T.pack "Int"
```

and likewise `"()"`, `"Bool"`, `"Char"`, `"Int8"`, `"Int16"`, `"Int32"`, `"Int64"`,
`"Integer"`, `"Word"`, `"Word8"`, `"Word16"`, `"Word32"`, `"Word64"`, `"Double"`,
`"Float"`, `"Text"`, `"UTCTime"`, `"Day"`. Rewrite the five parameterized instances
(`src/Keiki/Shape.hs:122-130`) to recurse through the class, preserving the existing
application-tree rendering shape (`Base(arg1,arg2)`):

```haskell
instance (CanonicalTypeName a) => CanonicalTypeName (Maybe a) where
  canonicalTypeName _ =
    T.pack "Maybe(" <> canonicalTypeName (Proxy @a) <> T.pack ")"
```

and analogously `[]` rendering as `[](a)`, `Either` as `Either(a,b)`, pairs as
`(,)(a,b)`, triples as `(,,)(a,b,c)`. Note the constraint changes from `Typeable a`
to `CanonicalTypeName a` — this is deliberate (see Decision Log): it makes a user's
`CanonicalTypeName` override for their own type take effect inside containers, which
the Typeable route silently ignored. `renderStableTypeRep` itself is unchanged — it
remains the default for user-defined types that derive `CanonicalTypeName` without a
body, and its own unit tests keep pinning the raw GHC-9.12 rendering.

Update the module header (`src/Keiki/Shape.hs:3-20`): the "GHC-upgrade-safe" claim
is now true for built-ins by construction; add a paragraph stating that user types
relying on the `Typeable` default are stable only as long as their defining module
path is, and that overriding `canonicalTypeName` is the pinning mechanism. Also
document, in the `CanonicalTypeName` class Haddock, that container arguments now
resolve through the class (override propagation).

Update the pinned expectations. In `test/Keiki/ShapeSpec.hs`, the
`regFileShapeCanonical` one-slot test (line 45-47) becomes
`retryCount:Int;regfile:0`; the empty-list anchor and its hash are unchanged. The
new hash values (computed with `printf '<canonical>' | shasum -a 256`, and
double-checked by running the failing test and reading the actual):

```text
"regfile:0"                                                        -> 0b262a9e301796f7a5b36bb6ea874e9ffccf7d1b4aff78a8d4b5436bd23914a6  (unchanged)
"retryCount:Int;regfile:0"                                         -> de03289268ae222f84d8a1b9af8f4f78bc9d23a747c97c12f4974e2504485978
"retryCount:Int;cooldownUntil:UTCTime;regfile:0"                   -> 22a08cf2b847545bf0ce24f505de379ee49c2edb8c2236b6f6bcfadba984b1ea
"retryCount:Int;cooldownUntil:UTCTime;correlationId:Text;regfile:0" -> d920c3660d5b2a7bda082cdedb08fa493acd3f74a663434a4cead475096866f9
```

The last line is `ExemplarSlots`, so
`keiki-codec-json/test/Keiki/Codec/JSON/GoldenSpec.hs:24` gets the `d920c366...`
value; extend that spec to also pin the full canonical *string* for `ExemplarSlots`
(the pre-hash text is more diagnosable than the hash when it drifts). Add a new
sensitivity test — in `test/Keiki/ShapeSpec.hs` — that renders
`regFileShapeCanonical` for a slot list exercising every built-in instance
(including `Maybe Int`, `[Text]`, `Either Int Text`, a pair, a triple) and asserts
the result contains neither `GHC.Internal` nor `GHC.Types` as a substring
(`T.isInfixOf`). This is the test that fails first if someone reintroduces a
Typeable-default built-in.

Finally document the migration: add entries to `CHANGELOG.md` and
`keiki-codec-json/CHANGELOG.md` stating (1) all shape-hash values change once in
this release, (2) for keiro-style snapshot stores this is a benign cache miss —
snapshots keyed by the old hash are ignored and the aggregate replays from the
event log in full, (3) the `Maybe`/`[]`/`Either`/tuple `CanonicalTypeName`
instances now require `CanonicalTypeName` (not just `Typeable`) on their
arguments, so a consumer with `Maybe UserType` slots may need to add
`deriving anyclass (CanonicalTypeName)` to `UserType` — a compile-time, not
silent, migration.

Acceptance: `cabal test all` is green after updating the pinned values; the
sensitivity test fails if any built-in instance body is deleted (verify once by
deleting the `Int` body, observing the failure, restoring it).

### Milestone 2 — checked-in golden byte files for the snapshot wire format

Scope: new directory `keiki-codec-json/test/golden/`, new spec module
`keiki-codec-json/test/Keiki/Codec/JSON/GoldenFileSpec.hs`, edits to
`keiki-codec-json/test/Spec.hs` and `keiki-codec-json/keiki-codec-json.cabal`, and
a new additive module in the `keiki-codec-json-test` package. At the end, the test
suite decodes snapshot bytes from files under version control, in both directions.

Define one fixed (not QuickCheck-generated) exemplar register file in
`GoldenFileSpec.hs`, using the existing `ExemplarSlots` from
`keiki-codec-json/test/Keiki/Codec/JSON/Fixtures.hs:50-54`:

```haskell
exemplarRegFile :: RegFile ExemplarSlots
exemplarRegFile =
  RCons (Proxy @"retryCount") (3 :: Int) $
    RCons (Proxy @"cooldownUntil") (read "2026-01-02 03:04:05 UTC" :: UTCTime) $
      RCons (Proxy @"correlationId") ("order-123" :: Text) RNil
```

Pin four fixture files (exact bytes to be captured via the regeneration mode below,
then eyeballed against these expectations — aeson renders the timestamp as
`"2026-01-02T03:04:05Z"`):

- `keiki-codec-json/test/golden/exemplar-regfile.value.json` — the Value-path bytes
  (`Aeson.encode (regFileToJSON exemplarRegFile)`; keys in alphabetical KeyMap
  order): `{"cooldownUntil":"2026-01-02T03:04:05Z","correlationId":"order-123","retryCount":3}`
- `keiki-codec-json/test/golden/exemplar-regfile.encoding.json` — the
  Encoding-path bytes (`encodingToLazyByteString (regFileToEncoding ...)`; keys in
  slot-list order): `{"retryCount":3,"cooldownUntil":"2026-01-02T03:04:05Z","correlationId":"order-123"}`
- `keiki-codec-json/test/golden/exemplar-shape.json` — a two-field JSON object
  `{"canonical": "retryCount:Int;cooldownUntil:UTCTime;correlationId:Text;regfile:0",
  "hash": "d920c3660d5b2a7bda082cdedb08fa493acd3f74a663434a4cead475096866f9"}`
  pinning the shape-hash input and output on disk.
- (Milestone 3 adds the `Maybe` fixtures to the same directory; Milestone 6 adds
  `keiki-codec-json/test/golden/event/`.)

`GoldenFileSpec.hs` runs, for each RegFile golden, both directions:

1. *Backward compatibility* (the direction that catches drift): read the file with
   `Data.ByteString.Lazy.readFile`, `Aeson.decode` it, run
   `regFileFromJSON @ExemplarSlots`, and assert the decoded slot values equal the
   fixed exemplar values (pattern-match the `RCons` spine; slot types all have
   `Eq`). This decodes bytes the current build did not produce.
2. *Format freeze*: encode `exemplarRegFile` on the corresponding path and assert
   byte equality with the file contents.

For the shape golden: parse the JSON, assert the `canonical` field equals
`regFileShapeCanonical (Proxy @ExemplarSlots)` and the `hash` field equals
`regFileShapeHash (Proxy @ExemplarSlots)`.

Regeneration protocol, implemented in the same module: when the environment
variable `KEIKI_UPDATE_GOLDENS` is set (checked via
`System.Environment.lookupEnv`), each golden test *writes* the current encoding to
the fixture path and then fails with the message
`"golden regenerated; unset KEIKI_UPDATE_GOLDENS, re-run, and review git diff"`.
The failure is deliberate: a regenerating run must never be green (see Decision
Log). Document the intended-format-change workflow in the module Haddock:

```bash
# From the repository root, only when a wire-format change is intended:
KEIKI_UPDATE_GOLDENS=1 cabal test keiki-codec-json:keiki-codec-json-test   # fails, rewrites files
cabal test keiki-codec-json:keiki-codec-json-test                          # must be green
git diff keiki-codec-json/test/golden/    # review: is every byte change intended?
# Commit the fixture change in the same commit as the code change, with a
# CHANGELOG entry explaining the migration story for persisted data.
```

Working-directory note for the plan's reader: `cabal test` runs each test binary
with the package directory as its working directory, so the relative path
`test/golden/...` resolves correctly; if you ever run the built test binary by
hand, run it from `keiki-codec-json/`.

Wire-up: import and describe `GoldenFileSpec` in the `main` of
`keiki-codec-json/test/Spec.hs:35-41`; add `Keiki.Codec.JSON.GoldenFileSpec` to the
test-suite `other-modules` in `keiki-codec-json/keiki-codec-json.cabal`; add
`test/golden/*.json` (and later `test/golden/event/*.json`) to that package's
`extra-source-files` so `cabal sdist` ships the fixtures and Hackage-side test runs
work; the test suite needs no new dependencies beyond `directory`-free file IO
(`bytestring` is already a dependency; add `filepath` only if actually used).

Downstream mirror (extend, don't duplicate, the `slotGoldenSpec` pattern at
`keiki-codec-json-test/src/Keiki/Codec/JSON/Test/Golden.hs:70-81`): add a new
module `keiki-codec-json-test/src/Keiki/Codec/JSON/Test/GoldenFile.hs` exporting

```haskell
regFileGoldenFileSpec ::
  forall rs.
  (RegFileToJSON rs, EqRegFile rs) =>
  String ->      -- describe label
  FilePath ->    -- golden file, relative to the consumer's package root
  RegFile rs ->  -- the fixed fixture value the file pins
  Spec
```

with the same two directions and the same `KEIKI_UPDATE_GOLDENS` behavior, so keiro
can pin its own snapshot files with one call. (`EqRegFile` arrives in Milestone 3;
within this milestone stub the module against the in-tree definition or sequence
the export after M3 — either order is fine as long as both land before release.)
Add the module to the library `exposed-modules` in
`keiki-codec-json-test/keiki-codec-json-test.cabal`, demonstrate it in the
self-test (`keiki-codec-json-test/test/Spec.hs`) against a new demo golden
`keiki-codec-json-test/test/golden/demo-regfile.value.json`, and list that file in
this package's `extra-source-files`. This is purely additive; `slotGoldenSpec` and
`regFileCodecProps` are untouched.

Acceptance: `cabal test all` green; then a mutation check — change
`exemplarRegFile`'s `retryCount` to `4` (or temporarily alter a byte in the fixture
file) and observe both directions fail with a byte-level diff; revert.

### Milestone 3 — Maybe slot coverage and value-level round-trip

Scope: `keiki-codec-json/test/Keiki/Codec/JSON/Fixtures.hs`, `PropSpec.hs`,
`GoldenFileSpec.hs` (extend), `keiki-codec-json/src/Keiki/Codec/JSON.hs` (docs
only), and `keiki-codec-json-test/src/Keiki/Codec/JSON/Test.hs` (additive export).
At the end, `Maybe` slots are covered by properties, unit tests, and golden files,
the byte-idempotence blind spot is closed where an `Eq` route exists and documented
where it does not, and the nested-`Maybe` rule is written down.

Add to `Fixtures.hs` (do NOT modify `ExemplarSlots` — it anchors the nine EP-36 §4
mutations and the M1/M2 pinned values):

```haskell
type MaybeSlots =
  '[ '("lastError", Maybe Text),
     '("approvedAt", Maybe UTCTime),
     '("shippingAddress", Maybe Address)
   ]

type NestedMaybeSlots = '[ '("nested", Maybe (Maybe Int)) ]
```

and an inductive value-equality walker, mirroring how `ArbitraryRegFile` is defined
twice by precedent (once in `Fixtures.hs:175-188`, once in the downstream package):

```haskell
class EqRegFile (rs :: [Slot]) where
  eqRegFile :: RegFile rs -> RegFile rs -> Bool

instance EqRegFile '[] where
  eqRegFile _ _ = True

instance (Eq t, EqRegFile rs) => EqRegFile ('(s, t) ': rs) where
  eqRegFile (RCons _ x xs) (RCons _ y ys) = x == y && eqRegFile xs ys
```

Strengthen `PropSpec.hs`: in `valueRoundTrip` (lines 43-53) and
`encodingRoundTrip` (lines 57-67), replace the final byte-comparison
`Aeson.encode (regFileToJSON rf') === bytes` with a value-level assertion
`eqRegFile rf' rf` (keep the byte determinism properties as they are — they test a
different thing). Run all four properties over `MaybeSlots` in addition to
`ExemplarSlots` (a second `describe` block; `Maybe` types already have `Arbitrary`
via `quickcheck-instances`). Do NOT run the value-level property over
`NestedMaybeSlots` — it would fail by design; that list gets targeted unit tests
instead.

Targeted nested-Maybe unit tests (in `PropSpec.hs` or a small new block in
`keiki-codec-json/test/Spec.hs`): encode a `NestedMaybeSlots` register file holding
`Just Nothing`; assert the encoded slot is JSON `null`; decode it back and assert
the slot is `Nothing` (outer), i.e. `Just Nothing` is NOT recovered. Also assert
`Just (Just 42)` and `Nothing` round-trip faithfully. These tests pin the accepted
collapse so any future aeson behavior change is caught.

Maybe golden files, added to `GoldenFileSpec.hs` under the M2 discipline, with
fixed fixtures:

- `keiki-codec-json/test/golden/maybe-regfile-just.value.json` and
  `.../maybe-regfile-just.encoding.json` — all three slots `Just ...`.
- `keiki-codec-json/test/golden/maybe-regfile-nothing.value.json` and
  `.../maybe-regfile-nothing.encoding.json` — all three slots `Nothing`; the files
  visibly contain explicit `null`s.
- One negative test with no file: `regFileFromJSON @MaybeSlots` on an object
  *omitting* the `lastError` key must return `Left "lastError: missing slot"` —
  pinning the rule that absent-key is not an encoding of `Nothing`.

Documentation: add a "Wire-format rules" section to the module Haddock of
`keiki-codec-json/src/Keiki/Codec/JSON.hs` stating, in this order: `Nothing`
encodes as an explicit `null` and an absent key is rejected; nested `Maybe` is not
faithfully representable (`Just Nothing` collapses to `null`, decoding as
`Nothing`) — avoid `Maybe (Maybe _)` slots, wrap the inner `Maybe` in a newtype
with explicit instances if the distinction matters; Value path emits alphabetical
key order, Encoding path emits slot-list order, both decode identically. Mirror the
nested-Maybe rule in `keiki-codec-json/README.md`.

Downstream additive API in `keiki-codec-json-test/src/Keiki/Codec/JSON/Test.hs`:
export the `EqRegFile` class (same definition) and a new
`regFileCodecPropsEq :: forall rs. (RegFileToJSON rs, ArbitraryRegFile rs, EqRegFile rs) => Spec`
that runs the round-trip properties with value-level comparison. Leave
`regFileCodecProps` (lines 127-186) untouched for compatibility, but extend its
Haddock "Implementation note" (lines 110-115) to state the limitation plainly: the
byte-comparison form cannot detect decode-changes that re-encode to identical bytes
(nested `Maybe` being the known case), and consumers whose slot types have `Eq`
should prefer `regFileCodecPropsEq`. Exercise the new helper in the package
self-test (`keiki-codec-json-test/test/Spec.hs`) against `DemoSlots`.

Acceptance: `cabal test all` green; the nested-Maybe collapse test documents the
exact observed behavior; temporarily reverting the `PropSpec.hs` strengthening and
adding a deliberate value-mangling decoder shim is not required — instead verify
the strengthened property is live by mutating one generator (e.g. make
`arbRegFile` for `MaybeSlots` always produce `Nothing` on decode — skip if
impractical; the collapse unit test is the primary evidence).

### Milestone 4 — uninitialized-slot encoding: documented precondition

Scope: `src/Keiki/Generics.hs`, `keiki-codec-json/src/Keiki/Codec/JSON.hs`
(Haddock), `keiki-codec-json/README.md`, one new test. Decision (b) from the
Decision Log: document, sharpen, and pin — no new total encoder in this plan.

Background for the reader: `emptyRegFile` (`src/Keiki/Generics.hs:318-332`) seeds
every slot with `error ("uninit: " ++ slotName)` so that reading an unwritten slot
crashes with the slot's name instead of an anonymous bottom. The codec's walkers
`regFilePairs`/`regFileSeries` (`keiki-codec-json/src/Keiki/Codec/JSON.hs:98-104`)
force every slot value, so encoding a partially-initialized register file throws
that `ErrorCall` from pure code — on the streaming path potentially after bytes
have already been emitted downstream.

Edits: in `src/Keiki/Generics.hs:331`, extend the message to
`"uninit: " ++ symbolVal (Proxy @s) ++ " (slot read before first write; a RegFile must be fully initialized before it is read or encoded)"`
and note the encoding precondition in the `EmptyRegFile` Haddock. In
`keiki-codec-json/src/Keiki/Codec/JSON.hs`, add an explicit precondition paragraph
to the Haddock of `regFileToJSON`, `regFileToEncoding`, and the module's new
"Wire-format rules" section (from M3): every slot must have been written; encoding
a register file seeded by `emptyRegFile` and not fully written throws an
`ErrorCall` whose message starts with `uninit:`, and on the streaming path this can
surface mid-stream — snapshot only fully-hydrated aggregates. Mirror the
precondition in `keiki-codec-json/README.md` (this is the keiro-facing statement;
keiro itself always encodes fully-populated records, so no keiro change is needed —
say so in the CHANGELOG entry).

Pin the behavior with a test (in `keiki-codec-json/test/Spec.hs` or a new
`UninitSpec` block): build
`emptyRegFile :: RegFile '[ '("retryCount", Int) ]`, force
`Aeson.encode (regFileToJSON rf)` with `Control.Exception.evaluate` (force the
lazy ByteString, e.g. its length), and assert via `shouldThrow` a predicate:

```haskell
\(ErrorCall msg) -> "uninit: retryCount" `isPrefixOf` msg
```

This test is the regression tripwire for both the message format and the
documented behavior.

Acceptance: `cabal test all` green; `cabal haddock keiki-codec-json` renders the
precondition; the Decision Log entry above records why option (a) was rejected.

### Milestone 5 — codec and TH polish bundle

Scope: `keiki-codec-json/src/Keiki/Codec/JSON.hs`, `src/Keiki/Generics/TH.hs`,
`keiki-codec-json/src/Keiki/Codec/JSON/TH.hs`. Four small, independent fixes; each
is separately committable.

(1) Duplicate slot names. On the Value path, `Aeson.object . regFilePairs`
(`keiki-codec-json/src/Keiki/Codec/JSON.hs:98-100,138`) builds a KeyMap where a
duplicated slot name keeps only one entry — silent data loss; on the Encoding path
a duplicate key is emitted twice; on decode, the second same-named slot always
fails with "missing slot" (line 114 deletes consumed keys). Import `Names` and
EP-70's `DistinctNames` from the canonical slot-invariant module. Attach
`DistinctNames (Names rs)` to the catch-all instance:
`instance (RegFileWalk rs, DistinctNames (Names rs)) => RegFileToJSON rs` (line 169).
Do not define a codec-local duplicate-name family. If EP-70's `TypeError` wording is
builder-specific, generalize that canonical message once in `Keiki.Internal.Slots`
so both Builder and JSON users receive an accurate slot-list diagnostic.
Document the guard and the underlying behavior in the module Haddock. Compile-fail
behavior cannot live in the hspec suite; follow the repo's existing precedent for
manual negative tests (`keiki-codec-json/src/Keiki/Codec/JSON/Event.hs` documents a
"Negative-test procedure (manual)") — add a short comment block in
`GoldenFileSpec.hs` or the module itself showing the two-line duplicate list to
paste into GHCi and the expected error. Keiro impact: its slot lists derive from
record fields and are necessarily distinct; confirm by compiling keiro (see
Validation). If the guard misbehaves, fall back per the Decision Log.

(2) Early command-side payload validation. `conPayload`
(`src/Keiki/Generics/TH.hs:545-548`) classifies any single-argument `NormalC` as a
record payload; `recordDecls` (line 682 onward) then generates field projections
that assume the payload type is a single-record-constructor data type, failing
later with inscrutable errors when it is not (e.g. `Placed Int`). The wire side
already validates properly in `genTermFieldsRecord` (lines 849-858). Extract that
check into a shared helper (e.g. `requireSingleRecordCtor :: String -> Type -> Q
[VarBangType]` next to `typeConstructorName` at line 916) and call it at the top of
`recordDecls` so the command side fails immediately with the same precise message
(`deriveAggregateCtors: ... requires a single record-syntax constructor on payload
<Name>, got ...`). Add a manual negative-test note mirroring the existing style.

(3) `*All` variants silently skip GADT/existential constructors: `conNames`
(`src/Keiki/Generics/TH.hs:534-538`) returns `[]` for `GadtC`/`ForallC`, so
`deriveAggregateCtorsAll`/`deriveWireCtorsAll` enumerate right past them. In the
enumeration paths (around lines 270-278 and the command-side equivalent), detect
constructors whose `conNames` is empty and emit
`Language.Haskell.TH.reportWarning` naming each skipped constructor and the splice
that skipped it; state the behavior in the module Haddock (it is currently
documented nowhere).

(4) Mangled Haddock. Both TH modules have broken comment structure that renders
incorrectly on Hackage: `src/Keiki/Generics/TH.hs:1-13` is an orphaned comment
fragment *above* the module Haddock (the tail of a worked example that got
separated), the module Haddock's worked example opens an `@` code block at line 49
that never closes before `module` at line 57, and the splice examples at lines
285-290 and 316-327 contain lines beginning `-- $(...)` — Haddock parses a leading
`-- $name` as named-chunk syntax, destroying the block. Same disease at
`keiki-codec-json/src/Keiki/Codec/JSON/TH.hs:1-52` (orphaned fragment lines 3-31
above the real module header, example split across the boundary). Repair by moving
the example content inside the `-- |` module Haddock with properly opened/closed
`@ ... @` blocks and `\$` escaping for every dollar sign (the existing line 3 of
each file shows the escaped form `-- \$(...)` — use that inside the doc comment,
never at column-start of its own comment line). Verification is part of the fix:
run `cabal haddock keiki` and `cabal haddock keiki-codec-json`, open the generated
HTML for `Keiki.Generics.TH` and `Keiki.Codec.JSON.TH` (paths are printed at the
end of the haddock run, under `dist-newstyle/.../doc/html/...`), and confirm each
worked example renders as a single code block with the splice lines intact.

Acceptance: `cabal build all` warning-clean except the deliberate `reportWarning`
cases (none fire in-tree), `cabal test all` green, haddock HTML visually correct.

### Milestone 6 — event-envelope golden files (gated on EP-77)

Scope: `keiki-codec-json/test/golden/event/`, extension of `GoldenFileSpec.hs`.
This milestone is sequenced after
`docs/plans/77-event-codec-schema-evolution-version-tags-wire-kind-pinning-and-default-on-missing-decoding.md`
per master plan integration point 5; everything above is independent of it.

Before starting, open EP-77's plan file and check its Progress/Outcomes sections.
If EP-77 has not shipped its versioned envelope, STOP: leave this milestone's boxes
unchecked, note the gate in this plan's Progress section, and treat the plan as
releasable-except-M6. Do not pin the current pre-EP-77 envelope (the
kind-discriminated object emitted by `deriveEventCodecSkeleton` in
`keiki-codec-json/src/Keiki/Codec/JSON/Event.hs`) — EP-77 is free to correct it
before release, and goldens would freeze bytes about to be
discarded.

Once EP-77 is in: reuse the event fixture sum type from
`keiki-codec-json/test/Keiki/Codec/JSON/THEventSpec.hs` (or define an equivalent
small sum in the golden spec if the fixture is unsuitable), pin one golden file per
constructor shape (record payload, no-payload singleton) plus one per versioning
feature EP-77 ships (at minimum: an envelope carrying the version tag; a
missing-field document exercising default-on-missing decoding), under
`keiki-codec-json/test/golden/event/`. Apply the identical two-direction discipline
and `KEIKI_UPDATE_GOLDENS` protocol from Milestone 2, add the files to
`extra-source-files`, and cross-reference the fixtures from EP-77's plan if it is
still open. Acceptance mirrors M2: decode-from-file with current code, byte-freeze
of current encoding, mutation check.


## Concrete Steps

All commands run from the repository root `/Users/shinzui/Keikaku/bokuno/keiki`
inside `nix develop`.

```bash
nix develop           # enter the dev shell (GHC 9.12 toolchain)
cabal build all       # baseline: must be green before starting
cabal test all        # baseline: must be green before starting
```

Per milestone, the loop is: edit the files named in Plan of Work, then

```bash
cabal build all
cabal test all
```

For M1, after editing `src/Keiki/Shape.hs`, first run only the affected suites to
read the actual new hash values off the failure output before pinning them
(expected to match the `shasum` values listed in M1):

```bash
cabal test keiki:keiki-test
cabal test keiki-codec-json:keiki-codec-json-test
```

A failing pinned-hash test prints the actual and expected values, e.g.:

```text
  test/Keiki/ShapeSpec.hs:56:
  1) Keiki.Shape (EP-36 M1), regFileShapeHash, produces the pinned hash for a one-slot list (retryCount :: Int)
       expected: "e2c8839d9ae8e89baebbc1adf6dfd5a35608712d9bf994c7cef4ea774e739700"
        but got: "de03289268ae222f84d8a1b9af8f4f78bc9d23a747c97c12f4974e2504485978"
```

The "but got" value must equal the corresponding `shasum` value from M1; if it does
not, the canonical rendering is wrong — fix the instance, do not pin the surprise.

For M2/M3/M6 golden creation, generate the fixture files with the regeneration
mode, then verify a clean pass:

```bash
mkdir -p keiki-codec-json/test/golden
KEIKI_UPDATE_GOLDENS=1 cabal test keiki-codec-json:keiki-codec-json-test  # writes files, then FAILS by design
cabal test keiki-codec-json:keiki-codec-json-test                         # must be green
git status keiki-codec-json/test/golden/                                  # confirm the new files, inspect contents
```

For M5's haddock verification:

```bash
cabal haddock keiki keiki-codec-json
# open the printed dist-newstyle/.../doc/html/keiki/Keiki-Generics-TH.html and
# .../keiki-codec-json/Keiki-Codec-JSON-TH.html in a browser; check the worked examples
```

Before each commit:

```bash
nix fmt -- --no-cache
cabal build all && cabal test all && cabal haddock all
```

Commit per milestone with conventional-commit messages, e.g.:

```text
feat(shape)!: pin GHC-stable canonical names for built-in slot types

One-time shape-hash value migration; keiro impact: benign snapshot
invalidation (full replay). Container CanonicalTypeName instances now
require CanonicalTypeName on their arguments.
```

At plan completion, update
`docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md`:
set EP-78's registry row Status (Complete, or In Progress with an M6-gated note)
and tick its progress checkbox.


## Validation and Acceptance

The plan is complete when all of the following hold, each observable by running a
command and reading its output:

- Golden-file proof (M2/M3): `git ls-files keiki-codec-json/test/golden/` lists the
  fixture files; `cabal test keiki-codec-json:keiki-codec-json-test` is green; and
  the mutation check works — flip one byte in
  `keiki-codec-json/test/golden/exemplar-regfile.value.json` (e.g. change `3` to
  `4`), rerun, observe BOTH a decode-direction failure (wrong decoded value) and a
  freeze-direction failure (byte mismatch), then `git checkout` the file. This
  proves the tests actually read the file rather than a compiled-in copy.
- Shape stability proof (M1): `test/Keiki/ShapeSpec.hs` asserts the exemplar
  canonical string equals
  `retryCount:Int;cooldownUntil:UTCTime;correlationId:Text;regfile:0` and that a
  slot list covering every built-in renders with no `GHC.Internal`/`GHC.Types`
  substring; deleting any one built-in instance body makes that test fail.
- Maybe semantics proof (M3): the unit test encoding `Just Nothing` observably
  yields `null` and decodes to `Nothing`; the all-`Nothing` golden file visibly
  contains `null` values; the absent-key negative test yields
  `Left "lastError: missing slot"`.
- Uninit proof (M4): the `shouldThrow` test passes, and running
  `Aeson.encode (regFileToJSON (emptyRegFile :: RegFile '[ '("x", Int)]))` in
  `cabal repl keiki-codec-json --build-depends keiki` throws
  `uninit: x (slot read before first write; ...)`.
- TH polish proof (M5): pasting the documented duplicate-slot-name list into GHCi
  produces the custom type error; the documented non-record payload example fails
  the splice with the precise early message; the haddock HTML for both TH modules
  renders the worked examples as intact code blocks.
- Consumer compatibility (required, per master plan integration point 6): keiro
  compiles against the modified keiki without source changes. From
  `/Users/shinzui/Keikaku/bokuno/keiro`, point its build at the local keiki
  checkout (the project's `cabal.project`/mori setup already references local
  paths — run `mori show --full` there if unsure) and `cabal build keiro`. Any
  breakage other than the documented `CanonicalTypeName` constraint case is a plan
  bug; fix keiki, not keiro.
- Hygiene: `cabal build all`, `cabal test all`, `cabal haddock all`, and
  `nix fmt -- --no-cache` (followed by `git diff --exit-code` to confirm no
  reformat) all succeed at HEAD.


## Idempotence and Recovery

Every step is safe to repeat. Test runs are read-only except under
`KEIKI_UPDATE_GOLDENS=1`, which overwrites only files under `test/golden/` — all
version-controlled, so `git checkout -- keiki-codec-json/test/golden/` recovers any
accidental regeneration, and the deliberate suite failure under that variable
prevents an accidental green regeneration from slipping through CI. The pinned-hash
updates in M1 are plain string edits; if a pinned value is wrong the very next test
run says so with the correct value in the failure output. Milestones land in order
M1 → M2 → M3 → M4 → M5 (→ M6), but M4 and M5 touch disjoint files from M2/M3 and
can be reordered or committed independently if needed; the only hard ordering is M1
before any golden pinning (hash values), EP-70 before M5, and EP-77 before M6
(envelope bytes). If M5's distinct-name guard causes unexpected downstream breakage, revert just that
constraint (keep the documentation) and record the reversal in the Decision Log.


## Interfaces and Dependencies

No new package dependencies are required: `aeson ^>=2.2`, `bytestring ^>=0.12`,
`hspec ^>=2.11`, `QuickCheck ^>=2.15`, and `quickcheck-instances ^>=0.3` are
already in the relevant stanzas of `keiki-codec-json/keiki-codec-json.cabal` and
`keiki-codec-json-test/keiki-codec-json-test.cabal`; `base`'s
`System.Environment.lookupEnv` and `Control.Exception` cover the regeneration flag
and the uninit test.

Surfaces that must exist, unchanged, at the end (keiro's load-bearing imports,
`keiro/src/Keiro/Snapshot/Codec.hs:23-41`):

```haskell
-- keiki-codec-json, Keiki.Codec.JSON
class (RegFileWalk rs) => RegFileToJSON (rs :: [Slot])   -- instance uses DistinctNames (Names rs) (M5)
regFileToJSON     :: (RegFileToJSON rs) => RegFile rs -> Aeson.Value
regFileToEncoding :: (RegFileToJSON rs) => RegFile rs -> Aeson.Encoding
regFileFromJSON   :: (RegFileToJSON rs) => Aeson.Value -> Either String (RegFile rs)

-- keiki, Keiki.Shape
regFileShapeHash      :: (KnownRegFileShape rs) => Proxy rs -> Text
regFileShapeCanonical :: (KnownRegFileShape rs) => Proxy rs -> Text
class CanonicalTypeName a where canonicalTypeName :: Proxy a -> Text
```

New surfaces introduced by this plan (all additive):

```haskell
-- keiki-codec-json-test, Keiki.Codec.JSON.Test (M3)
class EqRegFile (rs :: [Slot]) where
  eqRegFile :: RegFile rs -> RegFile rs -> Bool
regFileCodecPropsEq ::
  forall rs. (RegFileToJSON rs, ArbitraryRegFile rs, EqRegFile rs) => Spec

-- keiki-codec-json-test, Keiki.Codec.JSON.Test.GoldenFile (M2)
regFileGoldenFileSpec ::
  forall rs. (RegFileToJSON rs, EqRegFile rs) =>
  String -> FilePath -> RegFile rs -> Spec

-- keiki, Keiki.Internal.Slots (owned by EP-70; reused here)
type family DistinctNames (names :: [Symbol]) :: Constraint
```

Plan-level dependencies: EP-70
(`docs/plans/70-builder-correctness-hardening-eager-finalize-validation-closing-the-emit-unsafecoerce-schema-hole-and-declaration-order-edge-merging.md`)
is a hard dependency for the canonical distinct-name constraint. EP-77
(`docs/plans/77-event-codec-schema-evolution-version-tags-wire-kind-pinning-and-default-on-missing-decoding.md`)
is a soft dependency gating Milestone 6 only. The master plan
(`docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md`)
tracks this plan as EP-78 in its registry and progress checklist; keep both in sync
at completion. keiro (`/Users/shinzui/Keikaku/bokuno/keiro`) is a validation-time
dependency only — nothing in keiro is edited by this plan.

---

Revision note (2026-07-11): replaced the generated skeleton with the full plan.
Verified every architecture-review finding against current sources (citations
inline), pre-computed the post-migration shape hashes, chose and logged decisions
for the nested-Maybe semantics, the uninit-encoding posture, the duplicate-name
guard, and the EP-77 gating, and sequenced the hash-value migration ahead of all
golden pinning so fixtures are written exactly once.

Revision note (2026-07-12): removed the duplicate codec-local `DistinctSlotNames`
design. EP-78 now hard-depends on EP-70 and reuses the canonical
`DistinctNames (Names rs)` constraint from the slot-invariant module.
