---
id: 59
slug: event-codec-skeleton-derivation-in-keiki-codec-json
title: "Event codec skeleton derivation in keiki-codec-json"
kind: exec-plan
created_at: 2026-06-06T14:41:11Z
intention: "intention_01ktensqv9ecmv5cd5jrbcfej7"
master_plan: "docs/masterplans/14-keiki-and-keiki-codec-json-dsl-improvements-surfaced-by-the-seihou-consumer-audit.md"
---

# Event codec skeleton derivation in keiki-codec-json

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

Today, a service that stores its private events as JSON hand-writes a pair of
functions per event sum type: an encoder that emits a JSON object carrying a
`"kind"` discriminator string plus one key-value entry per payload field, and a
decoder that reads `"kind"`, branches on its value, and reassembles the payload
field by field. This is real, verified boilerplate. In the consumer repository
`keiro-runtime-jitsurei`, the file
`/Users/shinzui/Keikaku/bokuno/keiro-runtime-jitsurei/services/hospital-capacity/src/HospitalCapacity/Domain/Streams.hs`
(around line 281) defines `encodeReservationEvent :: ReservationEvent -> Value`
as a large `\case` — `"kind" .= ("TransferReservationCreated" :: Text)` followed
by one `.=` per field — and a matching `parseReservationEvent` that reads the
`kind` key and dispatches with `<$> ... <*> ...`. There are roughly 22 such
events across the audited services, each costing 10–20 lines of encode plus
decode. Because the encoder and decoder are written by hand and separately from
the event payload type, the JSON shape and the Haskell payload shape can drift
apart silently: add a field to the payload record, forget to update the encoder,
and the stored JSON quietly loses a field with no compile error.

After this plan, a service author writes a single Template Haskell splice —
`$(deriveEventCodecSkeleton opts ''ReservationEvent)` — and gets a generated
`kind`-discriminated encoder and decoder for the whole event sum type, derived
directly from the sum type's constructors and each constructor's payload record
fields. The author no longer hand-writes the `\case`. The derivation reads the
true field set from the payload type, so adding a field to the payload forces the
author to make a corresponding decision at compile time rather than silently
dropping it. This is the anti-drift property: there is **no silent generic
`ToJSON`/`FromJSON` fallback**. For any payload field whose type does not have a
codec the author has explicitly provided, the splice either fails compilation
with a precise message listing the unhandled field, or (when the author opts in)
emits a clearly-named `_todo_<Event>_<field>` placeholder binding that compiles
but is obviously unfinished — never a quiet guess.

You can see it working by defining a small event sum type in the test suite,
splicing the codec, and observing in a passing test that `decode (encode e)`
round-trips, that the JSON carries the `"kind"` key with the constructor's name,
and that a field whose type the author overrode (for example a TypeID newtype
encoded as text) appears in the JSON in its overridden form rather than its
generic form.

This plan touches **only** the sibling package `keiki-codec-json` (and its
in-tree test suite). It does **not** touch `keiki` core under `src/Keiki/`.
The reason is a load-bearing project constraint stated below.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] M1.1 — Add `containers ^>= 0.7` to the `keiki-codec-json` library
      `build-depends` (needed for `Data.Map`/`Data.Set` in `EventCodecOptions`).
      (2026-06-06)
- [x] M1.2 — Defined `EventCodecOptions`, `FieldCodec`, `OnMissingCodec` in a new
      `Keiki.Codec.JSON.Event` module; exported them and `defaultEventCodecOptions`.
      (2026-06-06)
- [x] M1.3 — Event sum-type reflection (`reifyEventCtors`/`toEvCtor`/
      `reifyPayloadFields`): reify the sum, classify each constructor as
      single-arg `NormalC` payload or no-arg singleton, reject record/multi-arg/
      GADT with precise messages, extract per-constructor payload field
      name/selector/type lists. (2026-06-06)
- [x] M1.4 — `kind`-discriminated encoder generation (one `Aeson.object` per
      constructor with the `kind` entry plus one per payload field, via the
      per-field override hook where present). (2026-06-06)
- [x] M1.5 — `kind`-discriminated decoder generation (read the kind string,
      nested-`if` dispatch, reassemble the payload record field by field in the
      `Either String` applicative). (2026-06-06)
- [x] M2.1 — No-silent-fallback safety mechanism: classify each field as
      overridden / passthrough / unhandled; per `OnMissingCodec`, either `fail`
      in `Q` listing every unhandled `<Event>.<field> :: <Type>`, or emit named
      `_todo_<Event>_<field>` bindings and route those fields through them.
      (2026-06-06)
- [x] M2.2 — Emit `<prefix>EventTypes :: [Text]` and
      `<prefix>KindMap :: [(Text, Text)]` (constructor order); plain `Text`, no
      Keiro import. (2026-06-06)
- [x] M3.1 — Added `THEventSpec.hs` with a 3-constructor `OrderEvent` fixture
      (overridden newtype field, all-passthrough payload, singleton); wired into
      `keiki-codec-json/test/Spec.hs` and the cabal `other-modules`. (2026-06-06)
- [x] M3.2 — Round-trip, kind-discriminator, override-used, error-path, and
      EventTypes/KindMap assertions pass (50 examples, 0 failures); JSON
      transcript captured in the spec haddock. (2026-06-06)
- [x] M3.3 — Documented the missing-override manual negative checks (both
      `FailAtCompileTime` and `EmitTodoBindings`) in the spec's top comment with
      verified observed text. (2026-06-06)
- [x] M3.4 — README "Deriving an event codec skeleton" section with the worked
      splice; `cabal haddock keiki-codec-json` clean (100% coverage on the new
      module). (2026-06-06)


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- `Language.Haskell.TH` already exports `stringE :: String -> Q Exp` (= `litE .
  stringL`). A locally-defined `stringE` helper caused an "Ambiguous occurrence"
  error; removed it and used the built-in. (2026-06-06)
- The generated `error` message and the `FailAtCompileTime` listing print
  fully-qualified names: the sum type via `show tyName`
  (`Keiki.Codec.JSON.THEventSpec.OrderEvent`) and the field type via `pprint ft`
  (`GHC.Types.Int`, not `Int`). The substring `Placed.discount` and the
  surrounding sentence are stable; the qualification is cosmetic. The spec's
  doc-comment expected text was updated to match the observed output. (2026-06-06)
- A TODO placeholder used on the encode side needs an explicit `:: Aeson.Value`
  annotation. `_todo_C_field :: a` applied as `(_todo (sel p))` leaves the result
  type ambiguous (only a `ToJSON` constraint), so the encode expression is
  `(_todo (sel p) :: Aeson.Value)`. The decode side
  (`_todo =<< lookupField ...`) is unambiguous because the applicative chain
  fixes the field type. (2026-06-06)
- The `keiki-codec-json-test` test stanza also got `containers ^>= 0.7` added
  (the spec fixture imports `Data.Map.Strict`/`Data.Set` directly), mirroring the
  lesson from EP-57 that the library-stanza dependency is not transitively visible
  to a test module's own imports. (2026-06-06)
- Using TH quotation (`[| ... |]`) for the generated bodies means every
  referenced name (`Aeson.object`, `Aeson..=`, `T.pack`, the runtime helpers, the
  sum's constructors and selectors) resolves to its origin module hygienically —
  the *consumer* module needs only `TemplateHaskell` and the splice; it does not
  need to import `aeson` or this module's helpers. (verified: `THEventSpec`
  imports only `Keiki.Codec.JSON.Event` symbols + `Data.Aeson`/`Data.Text` for
  its own assertions, not for the generated code.) (2026-06-06)


## Decision Log

Record every decision made while working on the plan.

- Decision: Keep all JSON work in the sibling package `keiki-codec-json`; do not
  add any `aeson` dependency to `keiki` core.
  Rationale: A load-bearing project constraint (EP-36 §3 R8; MasterPlan 11
  Decision Log entry of 2026-05-10, recorded in
  `docs/masterplans/11-keiki-codec-json-package-implementation-and-rollout.md`)
  requires `keiki` core to remain aeson-free so downstreams that never touch JSON
  do not pay for aeson. The generated codec references `aeson` symbols, so it must
  live where `aeson` is in scope — `keiki-codec-json`. This mirrors the same
  decision made for `deriveRegFileCodec` in EP-38
  (`docs/plans/38-th-derivation-helpers-for-regfiletojson-in-keiki-codec-json.md`).
  Date: 2026-06-06.
- Decision: No silent `Generic`/`ToJSON`/`FromJSON` fallback for fields whose
  codec the author did not provide. Instead, make the behavior an option
  (`onMissingCodec`): `FailAtCompileTime` (the default) calls `fail` in `Q`
  listing every unhandled `<Event>.<field> :: <Type>`, or `EmitTodoBindings`
  emits a top-level `_todo_<Event>_<field>` binding that compiles but is
  `error "TODO: ..."`-bodied.
  Rationale: The whole point of the audit's Req 6 is to eliminate drift. A silent
  generic fallback would re-introduce exactly the drift this plan removes: a new
  field would quietly acquire some default encoding nobody reviewed. The audit
  explicitly permits named TODO bindings as an alternative to compile failure;
  exposing both as an option lets a service stub out a large sum incrementally
  (TODO mode) and then tighten to fail-at-compile mode for CI.
  Date: 2026-06-06.
- Decision: Reuse the `deriveRegFileCodecAs` / `deriveWireCtorsAll` patterns —
  `reify` the type, validate constructor shapes with precise `fail` messages,
  derive a name prefix by lower-casing the first letter, build bodies with
  `[| ... |]` / `[t| ... |]` quotation where possible.
  Rationale: Consistency with the package's existing TH style
  (`keiki-codec-json/src/Keiki/Codec/JSON/TH.hs`) and with keiki core's
  `src/Keiki/Generics/TH.hs`, both of which a novice can read as templates.
  Date: 2026-06-06.
- Decision: Expose a compile-time event-type list (the constructor names as
  `[Text]`) and a kind-to-constructor mapping, but do not import Keiro.
  Rationale: The audit notes the generated list can populate Keiro
  `Codec.eventTypes`, but that wiring is a Keiro concern. Exposing the list as a
  plain `[Text]` binding lets a downstream feed Keiro without `keiki-codec-json`
  taking a Keiro dependency, keeping the package's dependency surface minimal and
  the skeleton bounded-context local.
  Date: 2026-06-06.
- Decision: Model an event constructor as a single-argument constructor wrapping
  a record payload type (e.g. `TransferReservationCreated TransferReservationCreatedData`),
  plus the no-arg singleton case. Reject record-syntax and multi-arg constructors.
  Rationale: This is exactly the shape the verified jitsurei events use and the
  shape keiki's own `deriveWireCtorsAll` already enumerates
  (`src/Keiki/Generics/TH.hs`, `conPayload`). Reusing that classification keeps
  this codec aligned with how the same events are already wired into the keiki
  DSL.
  Date: 2026-06-06.


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

Outcome: delivered in full against the original purpose. The new module
`keiki-codec-json/src/Keiki/Codec/JSON/Event.hs` exports
`deriveEventCodecSkeleton` / `deriveEventCodecSkeletonAs` plus
`EventCodecOptions` / `FieldCodec` / `OnMissingCodec` / `defaultEventCodecOptions`.
A service author replaces a hand-written per-event `\case` encoder + parser with
one splice and gets `<prefix>ToJSON`, `<prefix>FromJSON`,
`<prefix>EventTypes :: [Text]`, and `<prefix>KindMap :: [(Text, Text)]`, derived
directly from the sum's constructors and each payload record's fields.

The anti-drift property is realized exactly as specified: there is **no silent
generic fallback**. Each payload field is encoded by name as an override, a
passthrough, or — if neither — per `onMissingCodec`: `FailAtCompileTime` (default)
aborts the splice listing every unhandled `<Event>.<field> :: <Type>`, and
`EmitTodoBindings` emits a named `_todo_<Event>_<field>` placeholder. Both
negative behaviours were verified by hand (the compile-fail text captured
verbatim; the TODO binding confirmed to compile and be referenceable).

The aeson-free-core invariant is preserved: every line of JSON lives in
`keiki-codec-json`; `src/Keiki/` was never touched; `keiki.cabal` gained no aeson.
Because the generated bodies are built with TH quotation, the consumer module
needs only `TemplateHaskell` and the splice — it imports neither `aeson` nor this
module's runtime helpers for the generated code.

Acceptance: `cabal build keiki-codec-json` succeeds; `cabal test
keiki-codec-json:keiki-codec-json-test` reports 50 examples / 0 failures
(11 new EP-59 examples: round-trip ×3, kind+override ×3, error paths ×2,
EventTypes/KindMap ×2 — and one override-used assertion proving `"ord-7"` rather
than the integer `7`); `cabal haddock keiki-codec-json` is clean at 100% coverage
on the new module.

Gaps / deltas from the plan:

- The plan staged M1 with "unhandled = passthrough" then flipped to fail/TODO in
  M2. The implementation went straight to the final M2 behaviour in one module
  write (the no-fallback net is the headline property; an intermediate
  silently-passthrough state had no acceptance value and would have been thrown
  away).
- The plan suggested either extending `Keiki.Codec.JSON.TH` or a new module; the
  new `Keiki.Codec.JSON.Event` module was chosen (the plan's preferred option) to
  keep the record-codec and event-codec splices independently readable.
- The dogfood into `keiro-runtime-jitsurei` is out of this repo's scope (that
  consumer lives in a sibling repository) and was not performed here; the README
  worked example + the test fixture stand in as the in-repo demonstration.

Lesson: TH quotation plus a few exported runtime helpers (`lookupField`,
`lookupText`, `aesonResultToEither`) keeps the generated `[Dec]` compact and fully
hygienic, so the consumer's import surface stays minimal and the aeson-free
boundary is structurally guaranteed rather than merely conventional.


## Context and Orientation

This section assumes you know nothing about this repository. Read it fully before
editing anything.

### What this repository is

`keiki` is a pure-core Haskell library for event sourcing and workflow engines.
The repository root is `/Users/shinzui/Keikaku/bokuno/keiki`. The build tool is
`cabal`. The set of packages built together is listed in
`/Users/shinzui/Keikaku/bokuno/keiki/cabal.project`, which currently reads:

```text
packages: .
          jitsurei
          keiki-codec-json
          keiki-codec-json-test
```

The `.` package is `keiki` core (sources under `src/Keiki/`). `keiki-codec-json`
is the optional JSON codec sibling. `keiki-codec-json-test` is a separate package
shipping a property-test *toolkit* for downstream consumers. `jitsurei` is an
in-repo worked-example package. **This plan adds nothing to `cabal.project`** —
all three relevant packages already appear there.

### The load-bearing constraint (do not violate)

`keiki` core MUST NOT gain an `aeson` dependency. This is recorded in EP-36 §3 R8
and in the MasterPlan 11 decision log
(`docs/masterplans/11-keiki-codec-json-package-implementation-and-rollout.md`).
Every line of JSON work in this plan lives in `keiki-codec-json` (and its test
suite). You will never edit a file under `src/Keiki/`. If you find yourself
wanting to, stop and reconsider — the reflection helpers you need from core are
already exported and consumed read-only.

### Terms of art (defined here, used throughout)

- **Template Haskell (TH)**: GHC's compile-time metaprogramming. A *splice* is a
  Haskell expression of type `Q [Dec]` that runs during compilation and emits
  declarations the compiler then processes as though you had typed them. You
  invoke a splice at a top-level declaration position with `$(...)`. In this
  repo, `{-# LANGUAGE TemplateHaskell #-}` is at the top of every module that
  uses one.
- **`reify`**: `reify :: Name -> Q Info` inspects a named declaration at compile
  time. For `data Foo = A FooA | B FooB`, reifying `''Foo` yields the
  constructor list `[Con]`, which you walk to find each constructor and its
  payload type.
- **Sum type / event sum**: a Haskell `data` type with multiple constructors,
  each representing one kind of event, e.g.
  `data ReservationEvent = TransferReservationCreated TransferReservationCreatedData | PatientAdmitted PatientAdmittedData | ...`.
- **Payload record**: the single record type a constructor wraps, e.g.
  `TransferReservationCreatedData { reservationId :: ..., hospitalId :: ..., ... }`.
  Its fields are the JSON keys for that event kind.
- **Discriminator / `kind` field**: a JSON object key (conventionally `"kind"`)
  whose string value names which constructor a JSON object represents, so the
  decoder knows which payload to parse.
- **`Aeson.ToJSON` / `Aeson.FromJSON`**: aeson's standard typeclasses converting
  between Haskell values and `Aeson.Value` (the in-memory JSON tree). The whole
  point of this plan is to NOT silently rely on these for payload fields whose
  encoding the author has not reviewed.
- **Field codec override / hook**: an author-supplied pair of functions
  `(field-value -> Aeson.Value, Aeson.Value -> Either String field-value)` that
  this plan uses for a specific field instead of any generic instance — for
  example, a `DivertStatus` enum encoded via the domain function
  `divertStatusText`, or a TypeID newtype encoded via `idText`.

### The verified problem, concretely

In `keiro-runtime-jitsurei`, the file
`/Users/shinzui/Keikaku/bokuno/keiro-runtime-jitsurei/services/hospital-capacity/src/HospitalCapacity/Domain/Streams.hs`
hand-writes the encoder around line 281. The verified excerpt (read it yourself
to confirm) is:

```haskell
encodeReservationEvent :: ReservationEvent -> Value
encodeReservationEvent = \case
  TransferReservationCreated payload ->
    object
      [ "kind" Aeson..= ("TransferReservationCreated" :: Text)
      , "reservationId" Aeson..= idText payload.reservationId
      , "hospitalId" Aeson..= idText payload.hospitalId
      , "commandId" Aeson..= idText payload.commandId
      , "patientAcuity" Aeson..= patientAcuityText payload.patientAcuity
      , "requiredBedType" Aeson..= bedTypeText payload.requiredBedType
      , "sourceMessageId" Aeson..= payload.sourceMessageId
      , "expirationDeadline" Aeson..= payload.expirationDeadline
      , "divertStatus" Aeson..= divertStatusText payload.divertStatus
      , "lifeCriticalOverride" Aeson..= payload.lifeCriticalOverride
      ]
  PatientAdmitted payload -> object [ {- "kind" + per-field -} ]
  -- ... and so on for every constructor
```

with a matching `parseReservationEvent` that reads `kind` and dispatches. Note
the two flavors of field: some fields use a domain override function
(`idText`, `patientAcuityText`, `bedTypeText`, `divertStatusText`) and some are
passed straight through (`sourceMessageId`, `expirationDeadline`,
`lifeCriticalOverride`) because their types already have aeson instances. The
override hook design below must serve both.

### What already exists in `keiki-codec-json` (re-verify by reading the files)

- Package directory: `keiki-codec-json/`. Cabal file:
  `keiki-codec-json/keiki-codec-json.cabal`. The library stanza's
  `exposed-modules` are `Keiki.Codec.JSON` and `Keiki.Codec.JSON.TH`, and its
  `build-depends` are `base ^>= 4.21`, `aeson ^>= 2.2`, `keiki ^>= 0.1`,
  `template-haskell ^>= 2.23`, `text ^>= 2.1`. **`containers` is not yet a
  dependency** — M1.1 adds it because `EventCodecOptions` carries a `Data.Map`.
- `keiki-codec-json/src/Keiki/Codec/JSON/TH.hs` today exposes only
  `deriveRegFileCodec :: Name -> Q [Dec]` and
  `deriveRegFileCodecAs :: String -> Name -> Q [Dec]`. These emit
  `<prefix>ToJSON`, `<prefix>ToEncoding`, and `<prefix>FromJSON` for a
  **single-constructor record** (a snapshot / register-file record) and route
  through `regFileToJSON` / `regFileToEncoding` / `regFileFromJSON` from
  `Keiki.Codec.JSON` and `RegFieldsOf` / `gToRegFile` / `gFromRegFile` from
  `Keiki.Generics`. They explicitly **reject multi-constructor (sum) types**
  ("a single slot list cannot represent a sum"), type synonyms, and positional
  constructors. Read this file end-to-end: it is the template for the new splice
  (the `reify` → `validate*` → quote-and-emit shape, the `defaultPrefix`
  first-letter-lowercasing, the precise `fail` messages).
- There is **no event-sum codec today.** Event sums are exactly what Req 6 needs.
  The new splice is genuinely new code in this sibling package.

### Where the existing TH tests live (important)

There are two places named "test" — do not confuse them:

- `keiki-codec-json/test/` is the **in-tree test suite of the `keiki-codec-json`
  package itself** (test-suite stanza `keiki-codec-json-test` declared inside
  `keiki-codec-json/keiki-codec-json.cabal`). It already contains
  `keiki-codec-json/test/Keiki/Codec/JSON/THSpec.hs`, the spec for the existing
  `deriveRegFileCodec`. **The new event-codec tests go here**, alongside
  `THSpec.hs`, because the new splice is part of this package. The aggregator is
  `keiki-codec-json/test/Spec.hs`.
- `keiki-codec-json-test/` is a **separate toolkit package** that ships reusable
  property-test helpers for downstream consumers. It is not where this plan's
  unit tests go. (Its cabal file `keiki-codec-json-test/keiki-codec-json-test.cabal`
  declares the toolkit library plus its own `keiki-codec-json-test-test`
  test-suite for the toolkit itself.)

Read `keiki-codec-json/test/Keiki/Codec/JSON/THSpec.hs` before writing the new
spec: it shows the exact hspec harness, the round-trip pattern, and how a
compile-time negative test is documented as a manual procedure in the module's
top comment.

### What keiki core already gives you to build on (read, do not modify)

- `src/Keiki/Generics/TH.hs` already enumerates event constructors via
  `deriveWireCtors` / `deriveWireCtorsAll`. Its internal helpers `reifyCtors`,
  `conNames`, and especially `conPayload` (which classifies a constructor as
  singleton / single-arg-with-payload-type / unsupported) encode exactly the
  constructor-shape logic this plan needs. You cannot call these private helpers
  across packages, but you should mirror their classification logic verbatim in
  the new splice so the two stay aligned. `genTermFieldsRecord` in that file
  also shows how to reify a payload record's fields
  (`TyConI (DataD _ _ _ _ [RecC _ fs] _)` → `fs`), which is exactly how you read
  the per-event field name/type list.
- `src/Keiki/Generics.hs` exposes the `RegFieldsOf` type family (around line 238)
  computing a `[Slot]` (a `[(Symbol, Type)]`) from a record's Generic rep, and
  `src/Keiki/Core.hs` (around line 322) exposes `KnownSlotNames` / `slotNames`
  for run-time slot-name recovery. You may reuse these for field enumeration
  where convenient. In practice, reifying the payload record's `RecC` field list
  directly (as `genTermFieldsRecord` does) gives you both the field name and its
  `Type`, which is what you need to look up overrides — so direct reification is
  the primary mechanism and `RegFieldsOf` is a fallback only if you prefer the
  type-level slot list.

### Prior related plans (read both, align style)

- `docs/plans/38-th-derivation-helpers-for-regfiletojson-in-keiki-codec-json.md`
  — the existing RegFile codec TH plan. Its Decision Log explains the splice
  location reasoning (aeson must be in scope, hence the sibling package) and the
  free-functions-not-instances choice. This plan adopts both decisions.
- `docs/masterplans/11-keiki-codec-json-package-implementation-and-rollout.md`
  — the MasterPlan that birthed the package and recorded the aeson-free
  invariant. Reference it; do not contradict it.

This plan's own MasterPlan is
`docs/masterplans/14-keiki-and-keiki-codec-json-dsl-improvements-surfaced-by-the-seihou-consumer-audit.md`.


## Plan of Work

The work is one new public splice plus supporting types, in the sibling package,
delivered in three milestones. Each milestone ends in a buildable, testable
state. The splice's design mirrors the existing `deriveRegFileCodecAs` so a
reader fluent in that function can follow this one.

### Where the new code lives

Add a new module `Keiki.Codec.JSON.Event` at
`keiki-codec-json/src/Keiki/Codec/JSON/Event.hs`, and add it to
`exposed-modules` in `keiki-codec-json/keiki-codec-json.cabal`. Keeping the
event splice in its own module (rather than swelling `Keiki.Codec.JSON.TH`)
keeps the record-codec splice and the event-codec splice independently readable;
both are TH and both live in the same package, so the aeson-free invariant is
unaffected either way. If you prefer to extend `Keiki.Codec.JSON.TH` instead,
that is acceptable — but the plan's running examples assume the new module name.

### The public surface (final shape)

The splice and its options are:

```haskell
-- | A per-field encode/decode hook. The encoder turns a field value into
-- an 'Aeson.Value'; the decoder reads an 'Aeson.Value' back, with a
-- per-field error message on failure. The hook is untyped at the TH
-- boundary (it names the functions to splice in); see 'FieldCodec'.
data FieldCodec = FieldCodec
  { fcEncode :: Name   -- ^ a top-level function name, e.g. 'idText'
  , fcDecode :: Name   -- ^ a top-level function name, e.g. 'parseIdText'
  }

-- | What to do for a payload field whose type has no provided override.
data OnMissingCodec
  = FailAtCompileTime          -- ^ default: 'fail' the splice, listing fields
  | EmitTodoBindings           -- ^ emit named '_todo_<Event>_<field>' stubs

data EventCodecOptions = EventCodecOptions
  { fieldCodecOverrides :: Map String FieldCodec
      -- ^ keyed by payload field name (e.g. "reservationId", "divertStatus")
  , passthroughFields   :: Set String
      -- ^ field names whose type already has aeson instances and may use them
      --   directly (e.g. "sourceMessageId", "lifeCriticalOverride")
  , kindFieldName       :: String        -- ^ default "kind"
  , onMissingCodec      :: OnMissingCodec -- ^ default 'FailAtCompileTime'
  }

defaultEventCodecOptions :: EventCodecOptions
-- ^ empty overrides, empty passthrough, kindFieldName = "kind",
--   onMissingCodec = FailAtCompileTime.

deriveEventCodecSkeleton :: EventCodecOptions -> Name -> Q [Dec]
-- ^ like 'deriveEventCodecSkeletonAs' with the prefix derived from the
--   sum type name by lower-casing its first letter.

deriveEventCodecSkeletonAs :: String -> EventCodecOptions -> Name -> Q [Dec]
-- ^ explicit prefix variant, mirroring 'deriveRegFileCodecAs'.
```

For a sum type `ReservationEvent` with prefix `reservationEvent`, the splice
emits these top-level bindings:

```haskell
reservationEventToJSON   :: ReservationEvent -> Aeson.Value
reservationEventFromJSON :: Aeson.Value -> Either String ReservationEvent
reservationEventEventTypes :: [Data.Text.Text]   -- constructor names, in order
reservationEventKindMap    :: [(Data.Text.Text, Data.Text.Text)]
                                                 -- (constructorName, kindString)
```

The `EventTypes` and `KindMap` bindings are the Keiro-feeding surface (the
constructor names a downstream can hand to `Codec.eventTypes`); they carry no
Keiro types, only `Text`. The to/from functions are free functions, not aeson
instances, matching EP-38's decision (the author can wrap them in an instance if
they want).

### Why a field "override" is keyed by name, not type

The jitsurei encoder overrides `reservationId`, `hospitalId`, and `commandId`
all of which may share the same TypeID-ish encoding but appear under different
field names, while `sourceMessageId` of a plain type is passed through. Keying
the override by *field name* (a `String`) matches how the author thinks ("encode
the `divertStatus` field via `divertStatusText`") and matches the JSON key
directly. The splice still reads each field's `Type` from the reified record so
its error messages can name the type, but selection of the hook is by name.

### Milestone M1 — sum reflection + kind-discriminated encode/decode skeleton

Scope: after M1, `deriveEventCodecSkeleton` reifies an event sum, validates its
constructor shapes, reads each payload record's fields, and emits a working
`<prefix>ToJSON` / `<prefix>FromJSON` pair that round-trips for a sum all of
whose fields are either overridden or in `passthroughFields`. The
no-fallback safety net (M2) is not yet wired; in M1 an unhandled field is treated
as passthrough so you can get an end-to-end skeleton compiling first. (M2 flips
the default to fail/TODO.)

Work:

1. Add `containers ^>= 0.7` to the `keiki-codec-json` library `build-depends`
   (M1.1). This is needed for `Data.Map`/`Data.Set` in `EventCodecOptions`.
2. Create `keiki-codec-json/src/Keiki/Codec/JSON/Event.hs` with the module
   header, `{-# LANGUAGE TemplateHaskell #-}`, the `EventCodecOptions` /
   `FieldCodec` / `OnMissingCodec` types, and `defaultEventCodecOptions`
   (M1.2). Add the module to `exposed-modules`.
3. Reflection (M1.3). Reify the sum type name. Following `reifyCtors` /
   `conPayload` from `src/Keiki/Generics/TH.hs`:
   - Accept `TyConI (DataD _ _ _ _ ctors _)`; reject anything else with a
     precise message ("expected a data declaration for ..., got ...").
   - For each constructor, classify via the `conPayload` logic: a single-arg
     `NormalC ctorName [(_, payTy)]` is an event with payload type `payTy`; a
     zero-arg `NormalC ctorName []` is a singleton (no fields); a record-syntax
     `RecC` or multi-arg `NormalC` is rejected with a message naming the
     offending constructor and instructing the author to wrap a single record
     payload type.
   - For a payload type, reify it and read its single `RecC` field list exactly
     as `genTermFieldsRecord` does:
     `TyConI (DataD _ _ _ _ [RecC _ fs] _)` (or the `NewtypeD` form) → `fs`,
     each `fs` element being `(selectorName, _bang, fieldType)`. The
     `nameBase selectorName` is the JSON key; `fieldType` is for error messages.
     Reject a non-record payload with a precise message.
4. Encoder generation (M1.4). Emit `<prefix>ToJSON` as a function over the sum:

   ```haskell
   reservationEventToJSON :: ReservationEvent -> Aeson.Value
   reservationEventToJSON e = case e of
     TransferReservationCreated p -> Aeson.object
       [ "kind" Aeson..= ("TransferReservationCreated" :: Data.Text.Text)
       , "reservationId" Aeson..= idText (reservationId p)
       , ...
       , "sourceMessageId" Aeson..= Aeson.toJSON (sourceMessageId p)
       ]
     ...
   ```

   For each constructor, build one `Aeson.object` whose first pair is
   `kindFieldName Aeson..= (<ctorNameString> :: Text)`, then one pair per
   payload field: `"<fieldName>" Aeson..= <enc> (<fieldSelector> p)` where
   `<enc>` is the override's `fcEncode` function if the field name is in
   `fieldCodecOverrides`, else `Aeson.toJSON` (M1 passthrough). A singleton
   constructor emits just the `kind` pair. Build the field-selector application
   by `VarE selectorName` applied to the payload-binder variable.
5. Decoder generation (M1.5). Emit `<prefix>FromJSON`:

   ```haskell
   reservationEventFromJSON :: Aeson.Value -> Either String ReservationEvent
   reservationEventFromJSON v = case v of
     Aeson.Object o -> do
       kind <- lookupText "kind" o
       case kind of
         "TransferReservationCreated" ->
           TransferReservationCreated <$> (TransferReservationCreatedData
             <$> (idDecode =<< lookupField "reservationId" o)
             <*> ...)
         ...
         other -> Left ("unknown event kind: " <> Data.Text.unpack other)
     _ -> Left "event: expected a JSON object"
   ```

   The body reads the `kind` key, branches on its text value, and for each
   constructor reassembles the payload by applying the payload record's data
   constructor to the field decodes in field order. The per-field decode uses the
   override's `fcDecode` if present, else `Aeson.fromJSON` adapted to
   `Either String`. Provide small private helper functions in the module
   (`lookupField :: Text -> Aeson.Object -> Either String Aeson.Value`,
   `lookupText`, and an `aesonResultToEither` adapter) so the generated body
   stays compact; emit references to them by name.

Commands to run at the end of M1:

```bash
cd /Users/shinzui/Keikaku/bokuno/keiki
cabal build keiki-codec-json
```

Acceptance for M1: the package builds. Because the splice has no use site yet,
you validate it manually by adding a temporary fixture (a 2-constructor sum with
all-passthrough fields) under the test suite and confirming `cabal build
keiki-codec-json:keiki-codec-json-test` compiles. Remove or keep the fixture for
M3.

### Milestone M2 — the no-silent-fallback safety net + event-type list

Scope: after M2, an unhandled field (a field name that is neither in
`fieldCodecOverrides` nor in `passthroughFields`) is never silently encoded with
a generic instance. The default `onMissingCodec = FailAtCompileTime` calls
`fail` in `Q` with a message listing every unhandled `<Event>.<field> :: <Type>`,
so the build stops with an actionable list. The alternative `EmitTodoBindings`
emits, per unhandled field, a top-level binding

```haskell
_todo_TransferReservationCreated_divertStatus :: a
_todo_TransferReservationCreated_divertStatus =
  error "TODO: provide a FieldCodec for TransferReservationCreated.divertStatus :: DivertStatus"
```

and routes that field's encode/decode through the placeholder so the module
compiles but any actual use of the codec on that field throws an obviously-named
error. Both behaviors are anti-drift: neither one quietly invents an encoding.

Work:

1. Classification (M2.1). For each constructor's fields, partition into
   overridden (name in `fieldCodecOverrides`), passthrough (name in
   `passthroughFields`), and unhandled (neither). In M1 unhandled was treated as
   passthrough; M2 changes this: in `FailAtCompileTime` mode, accumulate all
   unhandled `(ctorName, fieldName, fieldType)` triples and, if non-empty, `fail`
   the splice with a multi-line message. In `EmitTodoBindings` mode, emit the
   `_todo_*` bindings and use them in the generated bodies for those fields.
   Choose the placeholder's encode to be `(\_ -> Aeson.Null)`-typed-through the
   error binding and its decode to be the error binding, whichever keeps the
   types simplest; the key property is the name and the `error` body.
2. Event-type list and kind map (M2.2). Emit:

   ```haskell
   reservationEventEventTypes :: [Data.Text.Text]
   reservationEventEventTypes =
     ["TransferReservationCreated", "PatientAdmitted", ...]

   reservationEventKindMap :: [(Data.Text.Text, Data.Text.Text)]
   reservationEventKindMap =
     [("TransferReservationCreated","TransferReservationCreated"), ...]
   ```

   The list order follows the reified constructor order. The kind map maps the
   Haskell constructor name to the kind string written to JSON (identical here,
   but a future option could let them differ — keep the mapping explicit so that
   change is non-breaking). These are plain `Text` bindings: no Keiro import.

Commands at the end of M2:

```bash
cd /Users/shinzui/Keikaku/bokuno/keiki
cabal build keiki-codec-json
```

Acceptance for M2: the package builds. A temporary fixture with one unhandled
field, spliced with `defaultEventCodecOptions` (fail mode), must make
`cabal build keiki-codec-json:keiki-codec-json-test` fail with a message naming
the unhandled field; switching that fixture's options to `EmitTodoBindings` must
make it build and produce a `_todo_*` binding (verify with `cabal repl` and
`:browse` or by referencing the binding). Capture both transcripts in the spec
comment in M3.

### Milestone M3 — tests + dogfood

Scope: after M3, the new splice has an automated hspec spec proving round-trip,
the `kind` discriminator, and override usage, plus a documented manual negative
check, plus a README worked example. This is the "demonstrably working behavior"
the spec demands.

Work:

1. Fixtures + spec (M3.1). Create
   `keiki-codec-json/test/Keiki/Codec/JSON/THEventSpec.hs`. Define a small event
   sum with three constructors: one whose payload has a newtype field needing an
   override, one with all-passthrough fields, and one singleton. For example:

   ```haskell
   newtype OrderId = OrderId Int
     deriving stock (Eq, Show)

   orderIdToJSON :: OrderId -> Aeson.Value
   orderIdToJSON (OrderId n) = Aeson.toJSON ("ord-" <> show n)

   orderIdFromJSON :: Aeson.Value -> Either String OrderId
   orderIdFromJSON = ...  -- parse "ord-<n>" back to OrderId n

   data PlacedData = PlacedData { orderId :: OrderId, qty :: Int }
     deriving stock (Eq, Show)
   data ShippedData = ShippedData { trackingNo :: Text }
     deriving stock (Eq, Show)

   data OrderEvent
     = Placed PlacedData
     | Shipped ShippedData
     | Cancelled            -- singleton
     deriving stock (Eq, Show)

   $(deriveEventCodecSkeleton
       defaultEventCodecOptions
         { fieldCodecOverrides =
             Map.fromList [("orderId", FieldCodec 'orderIdToJSON 'orderIdFromJSON)]
         , passthroughFields = Set.fromList ["qty", "trackingNo"]
         }
       ''OrderEvent)
   ```

2. Assertions (M3.2). In the spec:
   - Round-trip: for each sample event `e`,
     `orderEventFromJSON (orderEventToJSON e) `shouldBe` Right e`.
   - Discriminator: `orderEventToJSON (Placed (PlacedData (OrderId 7) 3))`
     contains the pair `"kind" .= ("Placed" :: Text)`; assert by extracting the
     `kind` key from the resulting `Aeson.Object`.
   - Override used: the same value's JSON has `"orderId"` equal to the string
     `"ord-7"`, proving the override ran rather than a generic `Int` encoding.
   - Event-type list: `orderEventEventTypes `shouldBe` ["Placed","Shipped","Cancelled"]`.
   Capture the JSON transcript in the spec's haddock as a `text` block, e.g.:

   ```text
   orderEventToJSON (Placed (PlacedData (OrderId 7) 3))
   == {"kind":"Placed","orderId":"ord-7","qty":3}
   ```

3. Manual negative check (M3.3). In the module's top comment, document the
   missing-override behavior exactly as `THSpec.hs` documents its negative case:
   add an unhandled field to a payload, splice with `defaultEventCodecOptions`
   (fail mode), run `cabal build keiki-codec-json:keiki-codec-json-test`, and
   observe the `Q`-fail message listing the unhandled field; then show that
   switching to `EmitTodoBindings` produces a `_todo_*` binding. Paste both
   expected outputs as `text` blocks.
4. Wire-up and README (M3.4). Add `Keiki.Codec.JSON.THEventSpec` to the test
   suite's `other-modules` in `keiki-codec-json/keiki-codec-json.cabal`, and
   import + run it from `keiki-codec-json/test/Spec.hs` (it already imports the
   other spec modules; follow that pattern). Add a "Deriving an event codec
   skeleton" section to `keiki-codec-json/README.md` with the worked splice.

Commands at the end of M3:

```bash
cd /Users/shinzui/Keikaku/bokuno/keiki
cabal test keiki-codec-json:keiki-codec-json-test
cabal haddock keiki-codec-json
```

Acceptance for M3: the test suite reports the existing specs plus the new
`THEventSpec` examples, all green; haddock is clean.


## Concrete Steps

Working directory throughout: `/Users/shinzui/Keikaku/bokuno/keiki`.

First, re-verify the current state so you are not surprised:

```bash
cd /Users/shinzui/Keikaku/bokuno/keiki
cat keiki-codec-json/keiki-codec-json.cabal | grep -n -A2 'build-depends'
ls keiki-codec-json/src/Keiki/Codec/JSON/
ls keiki-codec-json/test/Keiki/Codec/JSON/
```

You should see `Keiki/Codec/JSON.hs` and `Keiki/Codec/JSON/TH.hs` in `src`, and
`THSpec.hs` (among others) in `test`, and a `build-depends` list without
`containers`.

M1.1 — edit `keiki-codec-json/keiki-codec-json.cabal`, library stanza, adding
`containers ^>= 0.7,` to `build-depends`. Then add
`Keiki.Codec.JSON.Event` to `exposed-modules`.

M1.2–M1.5 — create `keiki-codec-json/src/Keiki/Codec/JSON/Event.hs`. Use
`keiki-codec-json/src/Keiki/Codec/JSON/TH.hs` as the structural template for the
`reify` → validate → quote-and-emit flow, and `src/Keiki/Generics/TH.hs`
(`conPayload`, `genTermFieldsRecord`) for the constructor/field reflection.
Build:

```bash
cd /Users/shinzui/Keikaku/bokuno/keiki
cabal build keiki-codec-json
```

Expected: `keiki-codec-json` compiles; a log line `[n of m] Compiling
Keiki.Codec.JSON.Event`.

M2 — extend the splice with classification and the event-type/kind bindings.
Re-run `cabal build keiki-codec-json`.

M3 — create `keiki-codec-json/test/Keiki/Codec/JSON/THEventSpec.hs`, wire it
into `keiki-codec-json/keiki-codec-json.cabal` (`other-modules`) and
`keiki-codec-json/test/Spec.hs`. Then:

```bash
cd /Users/shinzui/Keikaku/bokuno/keiki
cabal test keiki-codec-json:keiki-codec-json-test
```

Expected output prefix (illustrative):

```text
Keiki.Codec.JSON.THEventSpec
  deriveEventCodecSkeleton
    Placed round-trips                       [ok]
    Shipped round-trips                      [ok]
    Cancelled (singleton) round-trips        [ok]
    JSON carries the kind discriminator      [ok]
    orderId field uses the override          [ok]
    orderEventEventTypes lists ctors in order[ok]
Finished in N.Ns — all NN examples passed.
```

Every commit's body MUST include all three trailers verbatim:

```text
MasterPlan: docs/masterplans/14-keiki-and-keiki-codec-json-dsl-improvements-surfaced-by-the-seihou-consumer-audit.md
ExecPlan: docs/plans/59-event-codec-skeleton-derivation-in-keiki-codec-json.md
Intention: intention_01ktensqv9ecmv5cd5jrbcfej7
```

Commit directly to the current branch (`master`); do not create a feature
branch. Use Conventional Commits (e.g.
`feat(codec-json): derive kind-discriminated event codec skeleton`). Commit
after each milestone, not in one lump.


## Validation and Acceptance

The user-visible outcome is: an author can replace a hand-written per-event
`encode`/`parse` pair with one splice and get a `kind`-discriminated codec whose
fields they control via overrides, with no silent generic fallback.

A novice validates end-to-end as follows:

1. From the repo root, `cabal build keiki-codec-json` succeeds.
2. `cabal test keiki-codec-json:keiki-codec-json-test` runs the new
   `THEventSpec` and reports all examples green, including the round-trip, the
   `kind`-discriminator presence, the override-used assertion, and the
   event-type-list ordering.
3. The override-used assertion proves the anti-generic property concretely:
   `orderEventToJSON (Placed (PlacedData (OrderId 7) 3))` produces a JSON object
   in which `"orderId"` is the string `"ord-7"` (the override's output), not the
   integer `7` (the generic output). If the splice had silently used a generic
   `Int` codec, this assertion would fail — so a passing test is positive
   evidence the override hook is wired.
4. The missing-override behavior is proven by the documented manual procedure:
   adding an unhandled field and building either fails the compile with a message
   listing `<Event>.<field> :: <Type>` (fail mode) or yields a visible
   `_todo_<Event>_<field>` binding (TODO mode). Paste both transcripts into the
   spec comment so the next reader can reproduce them.

Acceptance is behavioral, not structural: the test command above must pass, and
the manual negative procedure must produce the stated message/binding. Do not
declare the plan complete merely because a `deriveEventCodecSkeleton` symbol
exists.


## Idempotence and Recovery

Every step is additive and re-runnable.

- M1.1 (cabal edit) and the new module are additive; `git checkout HEAD --
  keiki-codec-json/keiki-codec-json.cabal keiki-codec-json/src/Keiki/Codec/JSON/Event.hs`
  rolls them back.
- The splice is deterministic by Template Haskell semantics: running it twice on
  the same `Name` and the same `EventCodecOptions` produces the same `[Dec]`.
  There is no state to corrupt.
- If the splice has a bug, `cabal build` reports it at compile time; iterate on
  `Keiki/Codec/JSON/Event.hs` until the M3 tests pass. A half-finished splice
  cannot damage anything outside its own module and the test fixture.
- The test module and its cabal/`Spec.hs` wiring are additive; reverting the
  three edits restores the prior green suite.

This plan never edits `src/Keiki/` and never edits `cabal.project`, so it cannot
regress keiki core or the package set.


## Interfaces and Dependencies

New module (defined by this plan):

- `Keiki.Codec.JSON.Event` at
  `/Users/shinzui/Keikaku/bokuno/keiki/keiki-codec-json/src/Keiki/Codec/JSON/Event.hs`.
  Public surface at the end of M2:

  ```haskell
  data FieldCodec          = FieldCodec { fcEncode :: Name, fcDecode :: Name }
  data OnMissingCodec      = FailAtCompileTime | EmitTodoBindings
  data EventCodecOptions   = EventCodecOptions
    { fieldCodecOverrides  :: Data.Map.Map String FieldCodec
    , passthroughFields    :: Data.Set.Set String
    , kindFieldName        :: String
    , onMissingCodec       :: OnMissingCodec
    }
  defaultEventCodecOptions :: EventCodecOptions
  deriveEventCodecSkeleton   :: EventCodecOptions -> Language.Haskell.TH.Name
                             -> Language.Haskell.TH.Q [Language.Haskell.TH.Dec]
  deriveEventCodecSkeletonAs :: String -> EventCodecOptions
                             -> Language.Haskell.TH.Name
                             -> Language.Haskell.TH.Q [Language.Haskell.TH.Dec]
  ```

  For a sum type with prefix `<p>` the splice emits `<p>ToJSON`,
  `<p>FromJSON`, `<p>EventTypes :: [Data.Text.Text]`, and
  `<p>KindMap :: [(Data.Text.Text, Data.Text.Text)]`, plus, in
  `EmitTodoBindings` mode, one `_todo_<Event>_<field>` binding per unhandled
  field.

New library dependency (added by this plan):

- `containers ^>= 0.7` on the `keiki-codec-json` library stanza, for
  `Data.Map` / `Data.Set` in `EventCodecOptions`.

Existing dependencies relied on, unchanged: `aeson ^>= 2.2`,
`template-haskell ^>= 2.23`, `text ^>= 2.1`, `base ^>= 4.21`, `keiki ^>= 0.1`.

Modules consumed read-only (do not modify):

- `Keiki.Generics.TH` (`keiki` core,
  `/Users/shinzui/Keikaku/bokuno/keiki/src/Keiki/Generics/TH.hs`) — the
  reference for constructor classification (`conPayload`, `reifyCtors`) and
  payload-field reflection (`genTermFieldsRecord`). You cannot call its private
  helpers across the package boundary; mirror their logic.
- `Keiki.Generics` (`keiki` core, `src/Keiki/Generics.hs`) — `RegFieldsOf` is
  available as an alternative field-enumeration route.
- `Keiki.Core` (`keiki` core, `src/Keiki/Core.hs`) — `KnownSlotNames`/`slotNames`
  available for run-time slot-name recovery if needed.
- `Keiki.Codec.JSON.TH` (`keiki-codec-json`,
  `keiki-codec-json/src/Keiki/Codec/JSON/TH.hs`) — the structural template for
  the new splice's `reify` → validate → emit shape and prefix derivation.

New test module (defined by this plan):

- `Keiki.Codec.JSON.THEventSpec` at
  `/Users/shinzui/Keikaku/bokuno/keiki/keiki-codec-json/test/Keiki/Codec/JSON/THEventSpec.hs`,
  added to `other-modules` of the `keiki-codec-json-test` test-suite stanza in
  `keiki-codec-json/keiki-codec-json.cabal`, and aggregated from
  `keiki-codec-json/test/Spec.hs`.

Independence from the rest of the initiative: this plan lives entirely in the
sibling package `keiki-codec-json` and its in-tree test suite. It consumes the
keiki reflection helpers read-only and depends on no other ExecPlan in
MasterPlan 14. It can run in parallel with every keiki-core plan (EP-55/56/57/58/60)
and with anything else, because it shares no mutable surface with them. The only
external surface it produces — the `<p>EventTypes` `[Text]` list — is consumed by
a downstream (Keiro) outside this repository and does not create a build-time
dependency in either direction.
