# DSL alpha review

## Purpose

This memo reviews the public keiki DSL and the keiro facade before the first alpha release. The goal is to find names or shapes that should change while compatibility is still cheap, and to separate those from rough edges that can be documented or deferred.

The review covers keiki source and examples in this repository, plus the sibling keiro repository at `/Users/shinzui/Keikaku/bokuno/keiro`. The main implementation plan is `docs/plans/40-review-dsl-before-alpha-release.md`.

## Evaluation criteria

Readability in realistic examples matters more than isolated type signatures. The strongest evidence comes from `jitsurei/src/Jitsurei/UserRegistration.hs`, `jitsurei/src/Jitsurei/LoanApplication.hs`, and `/Users/shinzui/Keikaku/bokuno/keiro/jitsurei/src/Jitsurei/OrderStream.hs`, because those are the snippets downstream users are likely to copy.

Consistency between keiki and keiro matters. Keiki should describe the pure transducer, while keiro should describe runtime execution. A name that means "stream definition" should not compete with a name that means "stream identity".

Haskell idiom matters, but only where it helps users. Names like `SomeSymTransducer` are idiomatic for existential wrappers. Names like `ci` and `co` are fine in type variables and research notes, but less helpful as exported function suffixes.

Error-message quality matters. Names that already produce local, precise type errors should not be changed for taste alone.

Future compatibility matters. Anything that will appear in every aggregate module, every `EventStream` record, or every guide-backed example should be settled before alpha. Niche or advanced APIs can tolerate aliases and later refinement.

Migration cost after alpha matters. A rename of `B.emit` would touch every aggregate. A rename of a low-level helper used only in advanced composition code has lower migration cost, unless it appears in public tutorials.

## Current keiki DSL

The primary authoring surface is `Keiki.Builder` in `src/Keiki/Builder.hs`. A realistic aggregate uses:

```haskell
userReg = B.buildTransducer PotentialCustomer emptyRegs
            (\case Deleted -> True; _ -> False) do
  B.from PotentialCustomer do
    B.onCmd inCtorStart $ \d -> B.do
      B.slot @"email"        .= d.email
      B.slot @"confirmCode"  .= d.confirmCode
      B.emit wireRegistrationStarted RegistrationStartedTermFields
        { email       = d.email
        , confirmCode = d.confirmCode
        , at          = d.at
        }
      B.goto RequiresConfirmation
```

This shape appears in `jitsurei/src/Jitsurei/UserRegistration.hs` and in the README. The same shape scales to larger examples such as `jitsurei/src/Jitsurei/LoanApplication.hs`, where literal writes use `lit 0`, register reads use `#appIncomeDocCount`, and custom predicates use `B.requireGuard readyForReviewGuard`.

Template Haskell helpers in `src/Keiki/Generics/TH.hs` generate the constructor vocabulary:

- `deriveAggregateCtors` emits `inCtor<Short>`, `inp<Short>`, and `is<Short>` declarations for command constructors.
- `deriveWireCtors` emits `wire<Short>` and `<Short>TermFields` declarations for event constructors.
- `deriveView` emits the B-presentation singleton, view GADT, and projection function.

The low-level AST surface in `src/Keiki/Core.hs` remains public for escape hatches and advanced tooling. The important names are `SymTransducer`, `RegFile`, `InCtor`, `WireCtor`, `Term`, `HsPred`, `Edge`, `step`, `reconstitute`, `applyEvent`, and `applyEvents`.

Composition lives in `src/Keiki/Composition.hs` and `src/Keiki/Profunctor.hs`. The user-facing names are `compose`, `alternative`, `feedback1`, `SomeSymTransducer`, `someSymTransducer`, `lmapCi`, `rmapCo`, `dimapTransducer`, `lmapMaybeCi`, `identityTransducer`, and `arrTransducer`.

## Current keiro facade

Keiro wraps a keiki transducer in `EventStream`, then executes commands with `runCommand`:

```haskell
orderEventStream = EventStream
  { transducer = orderTransducer
  , initialState = NotStarted
  , initialRegisters = RNil
  , eventCodec = orderCodec
  , streamName = Stream.streamName
  , snapshotPolicy = Never
  , stateCodec = Nothing
  }
```

This is from `/Users/shinzui/Keikaku/bokuno/keiro/jitsurei/src/Jitsurei/OrderStream.hs`. It is the right conceptual boundary: keiro consumes `SymTransducer` directly rather than the older `Decider` facade.

The command facade in `/Users/shinzui/Keikaku/bokuno/keiro/src/Keiro/Command.hs` exposes `runCommand`, `runCommandWithSql`, and `runCommandWithSqlEvents`. The stream facade in `/Users/shinzui/Keikaku/bokuno/keiro/src/Keiro/Stream.hs` exposes `Stream`, `stream`, `streamName`, and `mapStreamName`. Projections, read models, process managers, snapshots, and timers are exposed from their own modules.

## Recommendations

### Keep for alpha

Keep the core builder vocabulary: `buildTransducer`, `from`, `onCmd`, `slot`, `(.=)`, `emit`, `emitWith`, `noEmit`, `requireEq`, `requireGuard`, and `goto`.

Rationale: the realistic examples read as domain workflow rather than AST assembly. `slot @"name" .= ...` is noisier than `#name .= ...`, but `docs/research/edge-builder-dsl-shape.md` records the GHC inference reason, and changing this before alpha would risk worse type errors for a small visual win. The `goto` name is also worth keeping because it is short and makes target-state intent explicit at the end of each edge body.

Keep `deriveAggregateCtors`, `deriveWireCtors`, and `deriveView`.

Rationale: the names are longer than the generated names, but they are accurate and discoverable. The split between aggregate input constructors and wire output constructors mirrors `InCtor` and `WireCtor`.

Keep `SymTransducer`, `RegFile`, `InCtor`, `WireCtor`, `HsPred`, and `SomeSymTransducer`.

Rationale: these names are already tied to the formalism and appear in design docs. `SomeSymTransducer` is idiomatic Haskell for an existential wrapper; replacing it with `AnyTransducer` or `PackedTransducer` would be taste churn.

Keep `compose`, `alternative`, and `feedback1` for alpha.

Rationale: `compose` and `alternative` match familiar category/parser vocabulary. `feedback1` is slightly technical, but it accurately communicates a bounded one-round feedback operator and avoids implying unbounded workflow iteration.

Keep keiro's `runCommand`.

Rationale: the guide text describes the whole load, replay, decide, encode, append cycle, but the call site benefits from the short verb. Longer names such as `executeCommand` or `appendCommandEvents` do not materially improve the primary path.

Keep keiro's `ProcessManager`, `ProcessManagerAction`, `PMCommand`, and timer vocabulary for alpha.

Rationale: the names match established event-sourcing vocabulary. `TimerRequest` is a clear value object for durable timers, and the guide-backed examples already read cleanly.

### Rename or reshape before alpha

#### R1: Rename the `EventStream.streamName` record field before alpha

Current spelling:

```haskell
data EventStream phi rs s ci co = EventStream
  { ...
  , streamName :: Stream (EventStream phi rs s ci co) -> StreamName
  }
```

Proposed spelling: `resolveStreamName`.

Affected files:

- `/Users/shinzui/Keikaku/bokuno/keiro/src/Keiro/EventStream.hs`
- `/Users/shinzui/Keikaku/bokuno/keiro/src/Keiro/Command.hs`
- `/Users/shinzui/Keikaku/bokuno/keiro/jitsurei/src/Jitsurei/OrderStream.hs`
- `/Users/shinzui/Keikaku/bokuno/keiro/docs/user/getting-started.md`
- `/Users/shinzui/Keikaku/bokuno/keiro/docs/user/core-concepts.md`
- `/Users/shinzui/Keikaku/bokuno/keiro/docs/user/api-reference.md`
- `/Users/shinzui/Keikaku/bokuno/keiro/docs/guides/snapshots-and-hydration.md`

Reason: keiro also exports `Keiro.Stream.streamName :: Stream a -> StreamName`. In real code, `EventStream.streamName = Stream.streamName` is legal but reads like a tautology and makes docs harder to explain. `resolveStreamName` says the field adapts the typed stream wrapper to the event-store stream name.

Before:

```haskell
orderEventStream = EventStream
  { streamName = Stream.streamName
  , ...
  }
```

After:

```haskell
orderEventStream = EventStream
  { resolveStreamName = Stream.streamName
  , ...
  }
```

Expected migration effort: mechanical field rename plus record-dot call sites in `Keiro.Command` and `Keiro.Snapshot` integration paths. This is a good alpha change because every downstream `EventStream` literal will copy this field.

#### R2: Rename `StateCodec.schemaVersion` before alpha

Current spelling:

```haskell
data StateCodec state = StateCodec
  { schemaVersion :: Int
  , shapeHash :: Text
  , encode :: state -> Value
  , decode :: Value -> Either Text state
  }
```

Proposed spelling: `stateCodecVersion`.

Affected files:

- `/Users/shinzui/Keikaku/bokuno/keiro/src/Keiro/EventStream.hs`
- `/Users/shinzui/Keikaku/bokuno/keiro/src/Keiro/Snapshot.hs`
- `/Users/shinzui/Keikaku/bokuno/keiro/src/Keiro/Snapshot/Codec.hs`
- `/Users/shinzui/Keikaku/bokuno/keiro/docs/user/snapshots.md`
- `/Users/shinzui/Keikaku/bokuno/keiro/docs/user/api-reference.md`
- `/Users/shinzui/Keikaku/bokuno/keiro/docs/guides/snapshots-and-hydration.md`

Reason: `Codec` already has `schemaVersion` for event payload schemas. `StateCodec` is an aggregate snapshot codec, not an event codec. The database column is `state_codec_version`, and the docs already use that term. The field should match the operational term to avoid event-version versus snapshot-version confusion.

Before:

```haskell
lookupSnapshot foundStreamId (codec ^. #schemaVersion) (codec ^. #shapeHash)
```

After:

```haskell
lookupSnapshot foundStreamId (codec ^. #stateCodecVersion) (codec ^. #shapeHash)
```

Expected migration effort: small field rename. This is alpha-worthy because snapshot compatibility errors are operationally sensitive.

#### R3: Add friendlier aliases for profunctor variance helpers later

Current spelling:

```haskell
lmapCi
rmapCo
dimapTransducer
lmapMaybeCi
```

Possible future surface:

```haskell
contramapInput
mapOutput
dimapIO
filterMapInput
```

Decision for alpha: defer. The current names follow Haskell profunctor conventions and are acceptable for alpha. Revisit friendlier aliases after the alpha release, preferably with examples showing whether users who are not already profunctor-literate benefit enough to justify another spelling.

Affected files:

- `src/Keiki/Profunctor.hs`
- `docs/guide/profunctor.md`
- `docs/guide/composition.md`
- tests under `test/Keiki/ProfunctorSpec.hs` and related category/arrow specs if they cite names directly

Reason: `ci` and `co` are useful type-variable names, but they are not user vocabulary. The friendlier names make the lossy variance caveat easier to explain: input is transformed before matching, output is transformed after emission, and `filterMapInput` drops inputs that cannot be routed.

Before:

```haskell
lmapCi wrap commandTransducer
rmapCo unwrap eventTransducer
```

After:

```haskell
contramapInput wrap commandTransducer
mapOutput unwrap eventTransducer
```

Expected migration effort if revisited later: low. These helpers are advanced, and aliases can be added without breaking current users.

### Document for alpha

Document that `B.onEpsilon` is advanced and usually not the right spelling for command-cycle aggregate authors.

Reason: in real examples, silent command-triggered transitions use `B.onCmd inCtorContinue` plus `B.noEmit`, not `B.onEpsilon`. That is visible in `jitsurei/src/Jitsurei/LoanApplication.hs`. The name `onEpsilon` is formally correct, but it is a term of art. Keep it, and explain that most user-authored silent transitions should still be keyed by a command constructor.

Document that `B.noEmit` is optional but recommended when silence is intentional.

Reason: an edge with no `emit` is already silent, but `B.noEmit` makes intent obvious in review and examples. This is documentation, not a rename.

Document that `feedback1` is one round only.

Reason: the name already carries the `1`, but users coming from workflow engines may expect feedback to mean iteration. The composition guide already says "one round"; keep that wording prominent.

Document `EventStream` as the aggregate contract, not the event-store stream.

Reason: `EventStream` is accurate in keiro's design, but it can be confused with the runtime stream name. The docs should consistently call it the "aggregate stream contract" or "event stream contract" and call `Stream a` the "typed stream identity".

### Defer post-alpha

Do not rename `SymTransducer` before alpha.

Reason: names such as `Machine`, `Workflow`, or `AggregateMachine` would hide the formalism that distinguishes keiki from a generic event-sourcing library. `SymTransducer` is technical, but keiro guides can shield most runtime users from it.

Do not replace `QualifiedDo` or `B.do` before alpha.

Reason: `B.do` is the cost of the indexed edge builder and gives precise duplicate-slot errors. The alternatives require either `RebindableSyntax` or worse type inference.

Do not add a saga/compensation direction before alpha.

Reason: keiro's workflow roadmap already treats that as a v2 question. It should not block the alpha DSL.

Do not redesign `runCommandWithSql` and `runCommandWithSqlEvents` before alpha unless another review finds a concrete transactional bug.

Reason: the names are a little literal, but they describe the escape hatch: run the command and a user SQL transaction after append. A larger naming pass around transactional outbox semantics can wait until the next runtime milestone.

## Accepted alpha surface

Decision recorded on 2026-05-17:

- keiki builder keeps its current core names.
- keiki TH helpers keep their current names.
- keiki composition keeps `compose`, `alternative`, and `feedback1`.
- keiro renames `EventStream.streamName` to `resolveStreamName`.
- keiro renames `StateCodec.schemaVersion` to `stateCodecVersion`.
- keiki keeps `lmapCi`, `rmapCo`, `dimapTransducer`, and `lmapMaybeCi` for alpha; friendlier aliases are deferred for later discussion because the current names follow Haskell profunctor conventions.

## Post-alpha follow-ups

Add a "naming glossary" section to the keiki user guide that maps formal terms to runtime terms: command/input, event/output, vertex/state, register file/memory, wire constructor/event constructor, and event stream contract.

Add a short keiro page that shows the complete relationship between `Stream a`, `EventStream`, `Codec`, `StateCodec`, and `runCommand`.

Consider a later higher-level keiki facade for ordinary aggregates that hides `SymTransducer` from the type signature. This should be additive and should not replace the current formal core.
