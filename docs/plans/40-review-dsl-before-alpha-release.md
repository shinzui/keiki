---
id: 40
slug: review-dsl-before-alpha-release
title: "Review DSL before alpha release"
kind: exec-plan
created_at: 2026-05-17T18:16:13Z
intention: "intention_01krvj722jevh8evypepr3b06b"
---

# Review DSL before alpha release

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

Before keiki and keiro ship their first alpha versions, review the public domain-specific language, or DSL, that aggregate authors will copy into real applications. In this repository, "DSL" means the Haskell authoring surface around `Keiki.Builder`, `Keiki.Generics.TH`, `Keiki.Core`, `Keiki.Composition`, `Keiki.Profunctor`, and the examples under `jitsurei/src/Jitsurei/`. In the sibling repository `/Users/shinzui/Keikaku/bokuno/keiro`, it also means the runtime-facing API that authors use around `EventStream`, `runCommand`, streams, projections, snapshots, process managers, and timers.

After this plan is implemented, maintainers will have a checked-in alpha DSL review document that identifies which names are acceptable for alpha, which names should change before alpha because changing them later would be painful, and which rough edges can remain as documented limitations. If the review finds alpha-blocking changes, this plan also guides the implementation of those changes across source, examples, docs, and tests. The result is visible by reading the review document, compiling both repositories, and running example-backed tests that demonstrate the final spelling of the DSL.


## Progress

- [x] M0 (2026-05-17): Reconfirmed repository metadata with `mori show --full`, `mori registry list`, `mori registry show shinzui/keiro --full`, and `mori registry docs shinzui/keiro`; inventoried keiki and keiro DSL call sites with `rg`; read the source and example files named in Concrete Steps.
- [x] M1 (2026-05-17): Added `docs/research/dsl-alpha-review.md` with keep, rename-before-alpha, document-for-alpha, and defer-post-alpha recommendations grounded in current source, examples, and docs.
- [ ] M2: Discuss the review and record final alpha decisions in this plan's Decision Log. Current proposed alpha changes are `EventStream.streamName` -> `resolveStreamName`, `StateCodec.schemaVersion` -> `stateCodecVersion`, and friendlier aliases for profunctor variance helpers.
- [ ] M3: Implement accepted alpha-blocking DSL changes in keiki, including source exports, examples, user guide, and tests.
- [ ] M4: Implement accepted alpha-blocking keiro facade changes in `/Users/shinzui/Keikaku/bokuno/keiro`, including docs and examples.
- [ ] M5: Run validation for both repositories and update the review memo plus Outcomes & Retrospective with the final alpha DSL surface.


## Surprises & Discoveries

- Discovery: The current keiki authoring surface is not only the builder. A realistic user sees `deriveAggregateCtors`, `deriveWireCtors`, `deriveView`, `SymTransducer`, `InCtor`, `WireCtor`, `HsPred`, `RegFile`, `SomeSymTransducer`, `compose`, `alternative`, `feedback1`, `runCommand` through keiro, and codec/snapshot helpers.
  Evidence: `README.md`, `docs/guide/user-guide.md`, `src/Keiki/Builder.hs`, `src/Keiki/Generics/TH.hs`, `src/Keiki/Composition.hs`, `src/Keiki/Profunctor.hs`, and `/Users/shinzui/Keikaku/bokuno/keiro/src/Keiro/EventStream.hs`.

- Discovery: Keiro's alpha surface deliberately consumes `SymTransducer` directly, not the older `Decider` facade.
  Evidence: `/Users/shinzui/Keikaku/bokuno/keiro/docs/research/00-overview.md` says the keiro contract is `SymTransducer`, and `/Users/shinzui/Keikaku/bokuno/keiro/src/Keiro/EventStream.hs` stores `transducer :: SymTransducer phi rs s ci co`.

- Discovery: The strongest alpha rename candidate is in keiro, not the keiki builder. `EventStream.streamName = Stream.streamName` is valid code in `/Users/shinzui/Keikaku/bokuno/keiro/jitsurei/src/Jitsurei/OrderStream.hs`, but the repeated name makes the docs distinguish a record resolver field from the standalone typed-stream accessor.
  Evidence: `/Users/shinzui/Keikaku/bokuno/keiro/src/Keiro/EventStream.hs` declares `streamName :: Stream ... -> StreamName`; `/Users/shinzui/Keikaku/bokuno/keiro/src/Keiro/Stream.hs` also exports `streamName :: Stream a -> StreamName`; the example assigns one to the other.

- Discovery: `StateCodec.schemaVersion` shares a field name with event `Codec.schemaVersion`, even though the snapshot database and research docs call the field `state_codec_version`.
  Evidence: `/Users/shinzui/Keikaku/bokuno/keiro/src/Keiro/EventStream.hs` declares `schemaVersion` on `StateCodec`; `/Users/shinzui/Keikaku/bokuno/keiro/src/Keiro/Snapshot.hs` reads that field for snapshot lookup; `/Users/shinzui/Keikaku/bokuno/keiro/docs/research/09-snapshot-strategy.md` uses the operational `state_codec_version` name.


## Decision Log

Record every decision made while working on the plan.

- Decision: Treat this as an alpha API review with optional implementation, not as an open-ended redesign of the transducer formalism.
  Rationale: The user asked whether naming or other DSL improvements are needed before shipping alpha. The highest-value outcome is to find alpha-breaking changes while they are still cheap, then implement only accepted alpha blockers. Larger research questions should be recorded as post-alpha follow-ups.
  Date: 2026-05-17

- Decision: Put the main review artifact in `docs/research/dsl-alpha-review.md` in the keiki repository.
  Rationale: The review spans keiki and keiro, but keiki owns the core DSL and already keeps design-level material under `docs/research/`. A single checked-in memo gives future release work one source of truth; keiro-specific findings can reference files in `/Users/shinzui/Keikaku/bokuno/keiro`.
  Date: 2026-05-17

- Decision: Review examples in both repositories before proposing names.
  Rationale: Names that look tolerable in isolation can become noisy in realistic aggregates. The examples in `jitsurei/src/Jitsurei/` and `/Users/shinzui/Keikaku/bokuno/keiro/jitsurei/src/Jitsurei/` expose the copy-paste surface better than source signatures alone.
  Date: 2026-05-17

- Decision: Keep the core keiki builder vocabulary as the proposed alpha surface.
  Rationale: `buildTransducer`, `from`, `onCmd`, `slot`, `(.=)`, `emit`, `noEmit`, `requireEq`, `requireGuard`, and `goto` read cleanly in `UserRegistration`, `LoanApplication`, and the keiro `OrderStream` example. The noisier pieces, especially `slot @"name"` and `B.do`, are tied to better type inference and duplicate-slot errors.
  Date: 2026-05-17

- Decision: Make the review memo propose keiro field renames before code changes.
  Rationale: The plan's M2 decision gate requires maintainer confirmation before alpha-blocking renames are implemented. The recommended renames touch every downstream `EventStream` or snapshot codec literal, so they should be accepted explicitly before M3/M4 edits.
  Date: 2026-05-17


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

M0 and M1 produced the checked-in review artifact at `docs/research/dsl-alpha-review.md`. The memo recommends keeping keiki's builder names, documenting `onEpsilon` / `noEmit` / `feedback1`, deferring saga compensation and higher-level facades, and considering three alpha changes before shipping: rename keiro `EventStream.streamName` to `resolveStreamName`, rename keiro `StateCodec.schemaVersion` to `stateCodecVersion`, and add friendlier keiki aliases for profunctor variance helpers.

Implementation is paused at M2 because the plan requires a decision gate before code renames.


## Context and Orientation

Keiki is a Haskell library for the pure core of event sourcing and workflow modeling. Its central type is `SymTransducer phi rs s ci co`, declared in `src/Keiki/Core.hs`. A transducer is a state machine with registers. Here `rs` is the type-level register file shape, `s` is the control vertex type, `ci` is the command or input type, and `co` is the event or output type. A "register file" is a typed collection of named slots such as `'[ '("email", Text), '("confirmedAt", UTCTime) ]`; aggregate authors use it to remember data across commands.

The low-level AST lives in `src/Keiki/Core.hs`. Its user-visible names include `RegFile`, `Index`, `Term`, `InCtor`, `WireCtor`, `OutFields`, `HsPred`, `Edge`, `SymTransducer`, `matchInCtor`, `inpCtor`, `lit`, `(.==)`, `pack`, `step`, `reconstitute`, `applyEvent`, and `applyEvents`. An AST is a direct Haskell value describing edges, guards, updates, outputs, and target vertices.

The recommended aggregate authoring DSL lives in `src/Keiki/Builder.hs`. The main surface is `buildTransducer`, `from`, `onCmd`, `onEpsilon`, `slot`, `(.=)`, `emit`, `emitWith`, `noEmit`, `requireEq`, `requireGuard`, and `goto`. The builder uses `QualifiedDo`, so the inner edge body is written as `B.do`. The expression `B.onCmd inCtorConfirm $ \d -> B.do` starts an edge for a specific command constructor and exposes the command payload as `d`, where `d.email` or `d.confirmCode` becomes a typed input projection.

Template Haskell helpers live in `src/Keiki/Generics/TH.hs`. `deriveAggregateCtors` generates input-constructor helpers such as `inCtorStart`, while `deriveWireCtors` generates output-constructor helpers such as `wireAccountConfirmed` and record types such as `AccountConfirmedTermFields`. `deriveView` generates per-vertex "B-presentation" view helpers that expose only the register slots valid at a given vertex. Template Haskell, abbreviated TH, means Haskell code that generates Haskell declarations at compile time.

Composition and wrapper APIs live in `src/Keiki/Composition.hs` and `src/Keiki/Profunctor.hs`. They include `compose`, `alternative`, `feedback1`, `identityTransducer`, `SomeSymTransducer`, `someSymTransducer`, and profunctor/category/arrow instances. They matter for alpha because names such as `feedback1`, `SomeSymTransducer`, and `identityTransducer` become public vocabulary once users start composing workflow pieces.

Keiki's realistic examples live under `jitsurei/src/Jitsurei/` and tests under `test/Keiki/`. Important examples for this review are `jitsurei/src/Jitsurei/UserRegistration.hs`, `jitsurei/src/Jitsurei/OrderCart.hs`, `jitsurei/src/Jitsurei/EmailDelivery.hs`, `jitsurei/src/Jitsurei/LoanApplication.hs`, and `jitsurei/src/Jitsurei/LoanWorkflow.hs`. The current user-facing guide is `docs/guide/user-guide.md`; `README.md` has the shortest public "taste" snippet.

Keiro is the sibling runtime repository at `/Users/shinzui/Keikaku/bokuno/keiro`. It uses keiki's `SymTransducer` in `src/Keiro/EventStream.hs`, executes commands in `src/Keiro/Command.hs`, exposes typed stream names in `src/Keiro/Stream.hs`, projections in `src/Keiro/Projection.hs`, read models in `src/Keiro/ReadModel.hs`, snapshots in `src/Keiro/Snapshot.hs`, process managers in `src/Keiro/ProcessManager.hs`, and timers in `src/Keiro/Timer.hs`. Keiro examples live under `/Users/shinzui/Keikaku/bokuno/keiro/jitsurei/src/Jitsurei/`, and user docs live under `/Users/shinzui/Keikaku/bokuno/keiro/docs/user/` and `/Users/shinzui/Keikaku/bokuno/keiro/docs/guides/`.

This repository has `mori.dhall`, so dependency and sibling project lookup must use `mori` before relying on memory. Do not search, read, or traverse `/nix/store`. Useful initial commands are `mori show --full`, `mori registry list`, `mori registry show shinzui/keiro --full`, and `mori registry docs shinzui/keiro`.


## Plan of Work

Milestone M0 inventories the current DSL from source and examples. Read the files named in Context and Orientation, and use `rg` to locate current public names in both repositories. The output of this milestone is not a code change; it is a working note that lists the concrete call sites to evaluate. Acceptance for M0 is that the reviewer can point to at least one source declaration, one keiki example, one keiki guide snippet, one keiro source declaration, and one keiro guide or example for each surface being judged.

Milestone M1 writes the review memo at `docs/research/dsl-alpha-review.md`. The memo must define the evaluation criteria before making recommendations. Use these criteria: readability in realistic examples, consistency between keiki and keiro, Haskell idiom, error-message quality, future compatibility, and migration cost after alpha. Categorize findings as "Keep for alpha", "Rename or reshape before alpha", "Document for alpha", or "Defer post-alpha". For every proposed rename, include the old spelling, proposed spelling, affected files, reason, expected migration effort, and one before/after snippet copied in short form from a real example. Acceptance for M1 is that the memo is understandable without reading this plan and names exact files for every recommendation.

Milestone M2 is the decision gate. Read the memo, discuss the recommendations with the maintainer, and update this plan's Decision Log with each accepted or rejected alpha decision. If no alpha-blocking changes are accepted, skip M3 and M4 and proceed to M5 with documentation-only validation. If changes are accepted, scope them tightly: only names or small ergonomic reshapes that would be meaningfully harder to change after alpha should be implemented here.

Milestone M3 implements accepted keiki-side changes. Edit the smallest set of files needed, usually `src/Keiki/Builder.hs`, `src/Keiki/Core.hs`, `src/Keiki/Generics/TH.hs`, `src/Keiki/Composition.hs`, `src/Keiki/Profunctor.hs`, examples under `jitsurei/src/Jitsurei/`, tests under `test/Keiki/`, `README.md`, and `docs/guide/user-guide.md`. Preserve old names only if the Decision Log says to keep aliases for alpha migration; otherwise remove them before alpha to avoid promising compatibility. Acceptance for M3 is that `cabal build all` and the keiki test suite pass, and the public examples use the accepted spellings.

Milestone M4 implements accepted keiro-side changes in `/Users/shinzui/Keikaku/bokuno/keiro`. Edit the smallest set of files needed, usually `src/Keiro/EventStream.hs`, `src/Keiro/Command.hs`, `src/Keiro/Stream.hs`, `src/Keiro/Projection.hs`, `src/Keiro/ProcessManager.hs`, `src/Keiro/Timer.hs`, examples under `jitsurei/src/Jitsurei/`, `README.md`, and docs under `docs/user/` and `docs/guides/`. Acceptance for M4 is that keiro builds, tests pass, and the guide-backed `jitsurei` examples use the accepted facade names.

Milestone M5 performs final validation and closes the loop. Update `docs/research/dsl-alpha-review.md` with a final "Accepted alpha surface" section. Update this plan's Progress, Surprises & Discoveries, Decision Log, and Outcomes & Retrospective. Acceptance for M5 is that a new contributor can read the memo, copy the alpha example snippets, and find those same names in compiling source and docs.


## Concrete Steps

Start in the keiki repository:

    cd /Users/shinzui/Keikaku/bokuno/keiki
    mori show --full
    mori registry list
    mori registry show shinzui/keiro --full
    mori registry docs shinzui/keiro

Expected evidence includes keiki's identity as `shinzui/keiki`, zero declared dependencies in keiki's local `mori.dhall`, and keiro's path as `/Users/shinzui/Keikaku/bokuno/keiro`.

Inventory keiki DSL declarations and examples:

    cd /Users/shinzui/Keikaku/bokuno/keiki
    rg "buildTransducer|onCmd|onEpsilon|slot @|emit |emitWith|noEmit|requireEq|requireGuard|goto|deriveAggregateCtors|deriveWireCtors|deriveView|SymTransducer|SomeSymTransducer|compose|alternative|feedback1|runCommand" -n README.md src jitsurei test docs/guide docs/foundations docs/research

Read these files in particular:

    sed -n '1,260p' src/Keiki/Builder.hs
    sed -n '1,260p' src/Keiki/Core.hs
    sed -n '1,240p' docs/guide/user-guide.md
    sed -n '260,380p' jitsurei/src/Jitsurei/UserRegistration.hs
    sed -n '1,260p' jitsurei/src/Jitsurei/OrderCart.hs

Inventory keiro facade declarations and examples:

    cd /Users/shinzui/Keikaku/bokuno/keiro
    rg "EventStream|runCommand|runCommandWithSql|runCommandWithSqlEvents|Stream|streamName|mapStreamName|InlineProjection|AsyncProjection|ProcessManager|ProcessManagerAction|TimerRequest|SnapshotPolicy|StateCodec|SymTransducer" -n README.md src jitsurei test docs/user docs/guides docs/research

Read these files in particular:

    sed -n '1,260p' src/Keiro/EventStream.hs
    sed -n '1,560p' src/Keiro/Command.hs
    sed -n '1,260p' src/Keiro/Projection.hs
    sed -n '1,260p' src/Keiro/ProcessManager.hs
    sed -n '1,220p' src/Keiro/Stream.hs
    sed -n '60,180p' docs/guides/build-the-command-side.md

Create or update the review memo in keiki:

    cd /Users/shinzui/Keikaku/bokuno/keiki
    $EDITOR docs/research/dsl-alpha-review.md

The memo should have these sections: "Purpose", "Evaluation criteria", "Current keiki DSL", "Current keiro facade", "Recommendations", "Accepted alpha surface", and "Post-alpha follow-ups". Use ordinary Markdown. Keep code excerpts short and drawn from real examples.

If the decision gate accepts code changes, implement them in keiki first, then keiro. After each coherent change, run focused search to catch stale names:

    cd /Users/shinzui/Keikaku/bokuno/keiki
    rg "OLD_NAME|OLD_SPELLING" README.md src jitsurei test docs

    cd /Users/shinzui/Keikaku/bokuno/keiro
    rg "OLD_NAME|OLD_SPELLING" README.md src jitsurei test docs

Replace `OLD_NAME|OLD_SPELLING` with the actual names being retired. If an alias is intentionally retained, the review memo and this plan's Decision Log must say why.


## Validation and Acceptance

For documentation-only review completion, validate that the memo exists and links back to concrete files:

    cd /Users/shinzui/Keikaku/bokuno/keiki
    test -f docs/research/dsl-alpha-review.md
    rg "Rename or reshape before alpha|Keep for alpha|Document for alpha|Defer post-alpha|Accepted alpha surface" docs/research/dsl-alpha-review.md

Expected result: `test -f` exits with status 0, and `rg` prints headings or recommendation lines from the memo.

For keiki code or example changes, run:

    cd /Users/shinzui/Keikaku/bokuno/keiki
    cabal build all
    cabal test all

Expected result: Cabal reports a successful build and all tests pass. If this repository's current test command is known to be `cabal test keiki-test --test-show-details=direct`, run that focused command as well and record the example count and failure count in Outcomes & Retrospective.

For keiro code or example changes, run:

    cd /Users/shinzui/Keikaku/bokuno/keiro
    cabal build all
    cabal test all
    cabal test jitsurei-test

Expected result: Cabal reports a successful build, the library tests pass, and the guide-backed `jitsurei` tests pass. If `just haskell-verify` is available and fast enough for the local machine, run it as the final keiro verification and record the result.

The plan is complete when `docs/research/dsl-alpha-review.md` identifies the final accepted alpha DSL surface, all accepted alpha-blocking changes are implemented or explicitly rejected in the Decision Log, stale retired names are absent except for documented aliases, and both repositories pass the relevant validation commands.


## Idempotence and Recovery

The inventory commands are read-only and can be repeated safely. Creating or updating `docs/research/dsl-alpha-review.md` is additive until the decision gate. Code changes should be made in small patches and validated after each coherent group.

If a rename causes widespread compile failures, do not partially revert unrelated user edits. Use `rg` to find every old spelling, update examples and docs alongside source exports, and rerun the focused test command. If two names are debated and the final decision is not clear, keep the current alpha surface and record the rejected rename in the memo rather than adding a compatibility alias by default.

Because this is pre-alpha API work, removing an old spelling is acceptable only when the Decision Log says the old name is not part of the alpha contract. If the old name has already appeared in public docs that are intended for alpha, either update those docs in the same patch or keep a deprecated alias with an explicit plan to remove it before `1.0`.


## Interfaces and Dependencies

Use `mori` for dependency and sibling project lookup. This plan has already identified keiro through `mori registry show shinzui/keiro --full`; repeat that command if the path or dependency graph is uncertain. Do not inspect `/nix/store`.

Keiki interfaces under review:

- `src/Keiki/Builder.hs`: `buildTransducer`, `from`, `onCmd`, `onEpsilon`, `EdgeBuilder`, `slot`, `(.=)`, `emit`, `emitWith`, `noEmit`, `requireEq`, `requireGuard`, `goto`, `PayloadProj`, `ToOutFields`.
- `src/Keiki/Core.hs`: `Slot`, `RegFile`, `Index`, `Term`, `InCtor`, `WireCtor`, `OutFields`, `OutTerm`, `HsPred`, `BoolAlg`, `Edge`, `SymTransducer`, `matchInCtor`, `proj`, `inpCtor`, `lit`, `(.==)`, `pack`, `step`, `reconstitute`, `applyEvent`, `applyEvents`, `InFlight`.
- `src/Keiki/Generics/TH.hs`: `deriveAggregateCtors`, `deriveWireCtors`, `deriveView`.
- `src/Keiki/Composition.hs`: `compose`, `alternative`, `feedback1`, `identityTransducer`, and related composition helpers.
- `src/Keiki/Profunctor.hs`: `SomeSymTransducer`, `someSymTransducer`, profunctor/category/arrow wrappers.

Keiro interfaces under review:

- `/Users/shinzui/Keikaku/bokuno/keiro/src/Keiro/EventStream.hs`: `EventStream`, `SnapshotPolicy`, `StateCodec`.
- `/Users/shinzui/Keikaku/bokuno/keiro/src/Keiro/Command.hs`: `CommandResult`, `CommandError`, `RunCommandOptions`, `defaultRunCommandOptions`, `runCommand`, `runCommandWithSql`, `runCommandWithSqlEvents`.
- `/Users/shinzui/Keikaku/bokuno/keiro/src/Keiro/Stream.hs`: `Stream`, `stream`, `streamName`, `mapStreamName`.
- `/Users/shinzui/Keikaku/bokuno/keiro/src/Keiro/Projection.hs`: `InlineProjection`, `AsyncProjection`, `runCommandWithProjections`, `applyAsyncProjection`.
- `/Users/shinzui/Keikaku/bokuno/keiro/src/Keiro/ProcessManager.hs`: `ProcessManager`, `ProcessManagerAction`, `PMCommand`, `runProcessManagerOnce`, `runProcessManagerWorker`.
- `/Users/shinzui/Keikaku/bokuno/keiro/src/Keiro/Timer.hs` and `/Users/shinzui/Keikaku/bokuno/keiro/src/Keiro/Timer/Types.hs`: timer request, schedule, claim, and worker-facing names.

At the end of this plan, these interfaces must either retain their current alpha names or have replacement names reflected consistently in source exports, examples, docs, tests, and the alpha review memo.
