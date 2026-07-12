---
id: 16
slug: harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review
title: "Harden keiki correctness and API surfaces surfaced by the 2026-07 architecture review"
kind: master-plan
created_at: 2026-07-12T04:16:16Z
intention: intention_01kxc5whw1en3ra4nh728m53ka
---

# Harden keiki correctness and API surfaces surfaced by the 2026-07 architecture review

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Vision & Scope

In July 2026 a full architecture and design review of keiki (all 18 library modules,
the two codec packages, and the test suite) surfaced roughly twenty-five findings,
ranging from genuine type-unsoundness (a fabricated typeclass dictionary that
mis-indexes registers under nested `Category` composition) to API-design hazards (a
build-time validator that blesses transducers unable to replay their own logs; replay
entry points that collapse every failure into `Nothing`). Validation against current
keiro — the event-sourcing framework and workflow engine that mounts keiki
transducers as durable aggregate and process-manager streams — established which
surfaces are load-bearing at that integration boundary. Stale or unrelated consumers
are not evidence for this initiative.

When this initiative is complete: no `unsafeCoerce` in keiki rests on an invariant the
types do not enforce; a transducer that passes default `validateTransducer` can replay
every log it can produce, subject to the documented honesty laws of its opaque
`InCtor`/`WireCtor` match/build functions, and that law is enforced by a property test
over every fixture; replay failures carry a structured reason (which event, which vertex, why)
instead of `Nothing`; the builder rejects malformed edges eagerly at `buildTransducer`
time instead of via lazy `error` thunks; the symbolic determinism gate is conservative
in the correct direction on solver `Unknown`; composition of stateful transducers
agrees with sequential semantics or loudly documents where it cannot; and the JSON
event codec has a versioning and upcasting story so stored events survive schema
change. The documentation is corrected wherever the review found it describing
behavior the code does not have (builder finalize timing, duplicate-`from` ordering,
`outputAcceptor` equivalence, `symIsBot` conservatism).

This initiative gates the `0.1.0.0` Hackage release. keiki targets critical business
applications where a replay defect silently corrupts state reconstruction — the worst
failure class an event-sourcing core can have — and the public API must be finalized
before the first release because every post-release signature or semantics change is
a breaking change for persisted-data consumers. The ROADMAP's "only release mechanics
remain" status is superseded: `0.1.0.0` ships when every phase here is complete.
Replay safety (Phases 1–2) is the hard core of that gate; if schedule pressure forces
a cut, Phase 3 (not called by current keiro runtime code, but documented as keiki's
in-stream aggregate-composition surface) may instead ship explicitly
marked experimental in the module haddocks, but Phases 1, 2, 4, and 5 admit no cut:
they cover the soundness holes, the replay contract, the direction of the symbolic
gate's conservatism, and the wire formats that become permanent the moment a consumer
persists data.

In scope: the `keiki` library, `keiki-codec-json`, `keiki-codec-json-test`, the
in-tree test suite, and the `jitsurei` worked examples. Out of scope: changes to keiro
itself (though breaking-change sequencing for keiro is planned here), new composition
combinators, the runtime/effects layer, and any non-JSON codec. The review report
itself is the source of truth for finding details; each child plan restates the
findings it addresses in full, so no child depends on the conversation that produced
this document.


## Decomposition Strategy

The findings cluster into five functional themes, and the themes became the phases of
this plan. Within each theme, work was split so that every child plan produces an
independently verifiable behavior change and no two plans must edit the same function
in conflicting ways.

Phase 1, core soundness, contains the two findings where the compiler's guarantees are
actually subverted: the fabricated `WeakenR`/`KnownSlotNames` dictionary in
`Keiki.Profunctor` (EP-69) and the builder's `emit` coercion plus its lazy validation
posture (EP-70). These are first because they are the only findings that can corrupt
memory or crash from `Safe`-looking user code, and because EP-70's eager-validation
mechanism is the foundation the pre-existing plan 68 (explicit emit/noEmit intent)
rides on.

Phase 2, replay and inverse correctness, is the heart of the initiative: the validator
must agree with the evaluator about what "recoverable on replay" means (EP-71), replay
must explain its failures (EP-72), and the fundamental round-trip law — replaying a
log the transducer just produced reproduces the same state — must become a property
test that runs on every fixture (EP-73). These three are separate plans because they
have different blast radii: EP-71 changes validation semantics (and its new warning
constructors break keiro's exhaustive pattern match, so it must be coordinated); EP-72
adds new API without changing existing semantics; EP-73 is pure test infrastructure
that certifies both.

Phase 3, composition semantics, fixes the places where a composed transducer evaluates
differently from the composition of its parts (EP-74) and converts the remaining
composition footguns into diagnostics or loud documentation (EP-75). Current keiro
process managers coordinate separate durable streams and do not call the categorical
wrapper APIs, while keiro's modeling guide intentionally directs same-stream pipelines
to `compose` and `feedback1`. These APIs therefore need correctness work without being
treated as disposable merely because current runtime call sites are absent.

Phase 4, symbolic and validation posture, is one plan (EP-76): the `symIsBot` Unknown
inversion, the encoding gaps (unbounded-Integer widening, UTCTime truncation), and the
near-vacuous pure overlap check. These share one module and one theme — the gates must
be conservative in the right direction — and none is large enough to stand alone.

Phase 5, persistence and codecs, gives the unused-but-published event codec the
versioning story it needs before external consumers adopt it (EP-77) and pins the wire
formats that already have a consumer — keiro snapshots — with golden byte fixtures and
GHC-stable shape-hash names (EP-78).

Alternatives considered: one master plan per theme (rejected: a single registry tracks
the initiative better and the themes share integration points, notably the validation
warning type and the shared test fixtures); folding EP-73 into EP-71/EP-72 (rejected:
the property harness certifies both plans and must outlive them as regression
infrastructure); folding plan 68 into EP-70 (rejected: 68 pre-exists with its own
intention and scope; EP-70 instead builds the eager mechanism 68's error message will
fire through).


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| 69 | Replace the fabricated WeakenR and KnownSlotNames dictionary in Category composition with real induction witnesses | docs/plans/69-replace-the-fabricated-weakenr-and-knownslotnames-dictionary-in-category-composition-with-real-induction-witnesses.md | None | None | Complete |
| 70 | Builder correctness hardening: eager finalize validation, closing the emit unsafeCoerce schema hole, and declaration-order edge merging | docs/plans/70-builder-correctness-hardening-eager-finalize-validation-closing-the-emit-unsafecoerce-schema-hole-and-declaration-order-edge-merging.md | None | None | Complete |
| 68 | Require explicit emit/noEmit intent on every Builder edge (pre-existing, adopted) | docs/plans/68-require-explicit-emit-noemit-intent-on-every-builder-edge.md | EP-70 | None | Complete |
| 71 | Align build-time validation with replay: head-recoverability, cross-edge inversion ambiguity, and guard-implies-input-read checks | docs/plans/71-align-build-time-validation-with-replay-head-recoverability-cross-edge-inversion-ambiguity-and-guard-implies-input-read-checks.md | None | None | Complete |
| 72 | Structured replay diagnostics, Decider removal, and multi-event outputAcceptor | docs/plans/72-structured-replay-diagnostics-reconstituteeither-strict-evolve-policy-and-multi-event-outputacceptor.md | None | None | Not Started |
| 73 | Decide-replay round-trip property harness across all fixtures | docs/plans/73-decide-replay-round-trip-property-harness-across-all-fixtures.md | EP-71 | EP-72 | Not Started |
| 74 | Fix compose update-snapshot semantics and multi-event chain expansion under stateful transducers | docs/plans/74-fix-compose-update-snapshot-semantics-and-multi-event-chain-expansion-under-stateful-transducers.md | None | None | Not Started |
| 75 | Composition alignment validation and forward-fragment law documentation for the categorical instances | docs/plans/75-composition-alignment-validation-and-forward-fragment-law-documentation-for-the-categorical-instances.md | EP-69, EP-74 | None | Not Started |
| 76 | Symbolic soundness: solver Unknown handling, encoding-gap caveats, and a stronger pure overlap check | docs/plans/76-symbolic-soundness-solver-unknown-handling-encoding-gap-caveats-and-a-stronger-pure-overlap-check.md | None | EP-71 | Not Started |
| 77 | Event codec schema evolution: version tags, wire-kind pinning, and default-on-missing decoding | docs/plans/77-event-codec-schema-evolution-version-tags-wire-kind-pinning-and-default-on-missing-decoding.md | None | None | Not Started |
| 78 | Persistence wire-format hardening: golden byte fixtures, Maybe slot coverage, and stable shape-hash names | docs/plans/78-persistence-wire-format-hardening-golden-byte-fixtures-maybe-slot-coverage-and-stable-shape-hash-names.md | EP-70 | EP-77 | Not Started |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix (e.g., EP-69).


## Dependency Graph

Phase 1 (EP-69, EP-70, then plan 68), Phase 2 (EP-71, EP-72 in parallel; EP-73 after),
Phase 3 (EP-74, then EP-75), Phase 4 (EP-76), and Phase 5 (EP-77, EP-78) are largely
independent of one another; the phases express priority, not blocking. Eight plans
(69, 70, 71, 72, 74, 76, 77, 78) can each be started immediately and in parallel,
subject to the integration points below.

The hard dependencies: EP-73 requires EP-71 because the round-trip property "a
validated transducer replays every log it produces" is only a theorem once EP-71 makes
the hidden-input check demand head-recoverability — before that fix, the property
provably fails on any union-covered multi-event fixture, so the harness would land
red. EP-75 requires EP-74 because it documents and validates the composition semantics
EP-74 finalizes; writing law-level documentation against semantics about to change
would be wasted work.

Additional hard dependencies: plan 68 requires EP-70 because its missing-intent
diagnostic must use EP-70's eager `BuilderDefect` mechanism rather than add another
lazy finalize thunk. EP-75 requires EP-69's real wrapper witnesses before its stateful
law tests and provenance changes. EP-78 requires EP-70's canonical
`DistinctNames (Names rs)` constraint rather than defining a second duplicate-slot
family.

The soft dependencies: EP-73 benefits from EP-72 because the property harness
reports failures through `reconstituteEither`'s structured reasons when available.
EP-76 benefits from EP-71 because both extend the validation vocabulary and EP-71
lands the coordinated keiro-breaking change first (see integration point 1). EP-78
benefits from EP-77 because the event-envelope golden fixtures should pin the
versioned wire format EP-77 introduces, not the pre-versioning one (the RegFile
snapshot goldens in EP-78 are independent and can proceed after EP-70).


## Integration Points

1. `TransducerValidationWarning` in `src/Keiki/Core.hs` (EP-71 defines, EP-76 and
   plan 68 consume). EP-71 adds new warning constructors (head-unrecoverable
   multi-event edge; cross-edge inversion ambiguity; unguarded input read). The keiro
   consumer pattern-matches this type exhaustively in
   `keiro-core/src/Keiro/EventStream/Validate.hs:147-155`, so any constructor addition
   is a breaking change downstream: EP-71 owns deciding the final constructor set
   (four new constructors and four new `ValidationOptions` flags defaulting on,
   including state-changing epsilon detection), bumps
   the version note in the changelog, and records the keiro migration steps (exact
   new `renderWarning` arms) in its plan. As authored, EP-76 adds NO constructors and
   NO options field (its strengthened pure check reuses the existing
   `NondeterministicPair`), and EP-75 deliberately returns a separate
   `ComposeAlignmentWarning` type in `Keiki.Composition` rather than extending the
   keiro-matched core type — so EP-71's breaking change is the only one.

2. Eager builder validation pass in `src/Keiki/Builder.hs` (EP-70 defines, plan 68
   consumes). EP-70 introduces a strict validation traversal inside `buildTransducer`
   (or an `Either`-returning variant) that forces every edge and raises structured
   errors eagerly. Plan 68's missing-emit-intent diagnostic must be added as a case of
   that traversal, not as a new lazy `error` in `finalizeEdge`.

3. Replay-failure vocabulary in `src/Keiki/Core.hs` (EP-72 defines, EP-73 consumes).
   EP-72 introduces the structured replay-failure type (by analogy with the existing
   `StepFailure`/`EdgeRef` vocabulary, which it should reuse). EP-73's property harness
   renders these reasons in its counterexample output. The design must also serve
   keiro's hydration loop (`keiro/src/Keiro/Command.hs:201-306`), which today wraps
   every `Nothing` by hand — a streaming-replay fold from an arbitrary seed with error
   reporting would let keiro delete its duplicated `hydrate`/`hydrateFull` folds.

4. Shared stateful and multi-event test fixtures under `test/Keiki/Fixtures/`. As
   authored: EP-71 defines `Keiki.Fixtures.SplitCoverage` (multi-event, command
   coverage split across outputs) and `Keiki.Fixtures.RegisterEmission` (the first
   fixture emitting `TReg` reads); EP-73 consumes them (it enumerates the fixture
   modules at preflight rather than hardcoding names, so EP-71 owns naming); EP-74
   authors its own compose-specific `test/Keiki/Fixtures/ComposeStateful.hs` (with a
   recorded decision: its shapes need compose-specific coupling, and it must not
   hard-block on EP-71 — it checks for reusable EP-71 fixtures first); EP-69 adds the
   composition-pipeline fixture `CounterPipeline`, deliberately orthogonal to EP-74's
   snapshot findings. Compatibility and integration claims are checked against
   keiki's in-tree fixtures and current keiro only.

5. keiki-codec-json event wire format (EP-77 defines, EP-78 consumes). EP-77 decides
   the versioned envelope (version tag, pinned wire kinds, upcaster hook); EP-78's
   event-envelope golden fixtures pin whatever EP-77 ships. Current keiro does not use
   the keiki event codec; it uses its own `Keiro.Codec` with
   metadata `schemaVersion` and an upcaster chain — study it as prior art:
   `keiro-core/src/Keiro/Codec.hs` — so EP-77 may break the format freely; the point
   is to fix it before Hackage users adopt it.

6. Current-keiro breaking-change ledger. The load-bearing surfaces
   are `step`, `applyEventStreaming`, `applyEvents`, `InFlight`, `validateTransducer`
   and its warning type, `Keiki.Builder`, `Keiki.Generics.TH`, `regFileShapeHash`, and
   `RegFileToJSON`. Plans touching these (70, 71, 72, 76, 78) must state the keiro
   impact in their Decision Logs. Current keiro does not import `Keiki.Decider`,
   `SomeSymTransducer`, or the categorical wrapper instances, and it uses its own event
   codec. That absence supports the selected pre-release `Decider` removal but does not
   by itself authorize redesign or removal of keiki's intended composition APIs.

7. Follow-up coordination with current keiro MasterPlan 14
   (`/Users/shinzui/Keikaku/bokuno/keiro/docs/masterplans/14-harden-the-keiro-command-coordination-and-snapshot-paths-surfaced-by-the-2026-07-keiki-path-review.md`).
   That plan assumes this MasterPlan lands first. Its EP-95 consumes EP-71's final
   warning vocabulary and EP-72's structured replay fold for both aggregate and
   process-manager hydration. Agreed division: keiki EP-71 detects state-changing
   epsilon structurally and enables the warning by default; keiro enforces it at the
   `ValidatedEventStream` boundary for durable aggregates and process managers. Keiro
   EP-99 must consume/pin the keiki check rather than duplicate the AST traversal.
   Enforcement is non-negotiable at that boundary: keiro force-enables the
   replay-contract checks (`checkStateChangingEpsilon`, `checkHeadRecoverability`)
   before calling `validateTransducer`, caller-supplied options may only strengthen
   validation, `StateChangingEpsilon` sits in the fail bucket for aggregates and
   process managers alike, and any bypass is a separately named unchecked
   constructor, never an options field. Keiro's runtime divergence witnesses (its
   EP-99 M2) are retained as defense in depth behind the static checks.


## Progress

- [x] EP-69: real induction witnesses replace `unsafeCoerceWrapperDict`; nested stateful `c . b . a` composes correctly
- [x] EP-69: three-transducer stateful associativity test replaces the vacuous `id`-based one
- [x] EP-70: `buildTransducer` validates eagerly; malformed edges fail at construction, matching the documented contract
- [x] EP-70: `emit`'s `unsafeCoerce` eliminated; duplicate-`from` merge order fixed and documented
- [x] EP-68: every builder edge states emit/noEmit intent explicitly (rides EP-70's eager pass)
- [x] EP-71: hidden-input check demands head-recoverability; the GHCi counterexample transducer is rejected
- [x] EP-71: cross-edge inversion-ambiguity, guard-implies-input-read, and state-changing epsilon checks land; keiro warning-type migration documented
- [ ] EP-72: `reconstituteEither`/`applyEventsEither`/streaming fold with structured failure reasons
- [ ] EP-72: `Keiki.Decider` removed; `outputAcceptor` is InFlight-aware
- [ ] EP-73: round-trip property (fold `step`, replay the complete emitted log, states agree) green over every default-validation-clean fixture; invalid state-changing epsilon has an explicit teeth fixture
- [ ] EP-74: composed updates see pre-update registers; multi-event chain expansion consistent for stateful t2; stateful composition fixtures
- [ ] EP-75: checked composition is primary; real Either-arm predicates fix `alternative`; `feedback1` state-sharing contract resolved; forward/replay law results recorded without removing instances
- [ ] EP-76: solver `Unknown` treated as not-bot; encoding caveats documented; pure overlap check catches same-ctor `PAnd` pairs
- [ ] EP-77: versioned event envelope with pinned wire kinds and default-on-missing decoding
- [ ] EP-78: golden byte fixtures for both wire formats; `Maybe` slot coverage; shape hash stable across GHC majors


## Surprises & Discoveries

- Current keiro's command path uses `step`, `applyEventStreaming`, `applyEvents`,
  `InFlight`, and `validateTransducer`; aggregate and process-manager state both pass
  through `ValidatedEventStream` and the same hydration machinery. Current keiro does
  not import `Keiki.Decider` or the categorical wrapper instances. Its process-manager
  runtime coordinates separate streams, while its modeling guide reserves
  `compose`/`feedback1` for one durable stream. This supports removing Decider but not
  treating composition as an unwanted API.
- keiro already built the things EP-72 adds (typed replay errors, a hydration fold)
  and EP-77 needs (an upcaster chain with construction-time validation) — both plans
  should treat keiro's implementations as prior art rather than designing in a vacuum.
- Plan authoring (2026-07-12) surfaced discoveries that shaped the plans:
  - The naive decide/replay round-trip law is FALSE in the presence of ε-edges: the
    existing UserRegistration fixture's silent GDPR edge (`B.noEmit`) advances state
    without emitting, so replay cannot reach post-ε states. The selected correction is
    not to truncate the property: EP-71 emits a default-on warning for state-changing
    epsilon, EP-73 tests complete runs of validation-clean fixtures, and keiro rejects
    the warning at its durable-stream boundary. A deliberately invalid fixture keeps
    the divergence visible as teeth.
  - `TLit` carries no `Eq`/`Typeable` evidence, so EP-71's cross-edge
    inversion-ambiguity check cannot distinguish edges by differing literal fields —
    the criterion is constructor-name-based with documented blind spots.
  - The TH-generated `TermFields` records already carry the input-schema type
    parameter, so EP-70 can eliminate `emit`'s `unsafeCoerce` without changing the
    generated field-schema representation. Current keiki and keiro call sites must be
    rechecked during implementation; stale runtime examples are not evidence.
  - An authoring-time survey found zero update right-hand sides that read a
    sibling-half register, so EP-74's snapshot ("parallel assignment") semantics for
    `UCombine` is adoptable without breaking any existing aggregate — and it makes
    `runUpdate`'s currently-false order-independence haddock true.
  - EP-76's module audit found `symSatExt` is the only other SBV result inspection
    and is already conservative in the correct direction; the Unknown inversion is
    confined to `symIsBot`.
- EP-69's fail-before tests confirmed the fabricated composite dictionary emitted
  `[MsgD 3, MsgD 15, MsgD 25]` instead of `[MsgD 3, MsgD 14, MsgD 19]`, erased
  composite slot names to `[]`, and bypassed nested overlap detection. The analogous
  `left'` path was also corrupt, while `right'` already behaved correctly because
  its `Append '[] rs` shape reduces definitionally. Both coercions were removed;
  the right-side test remains as regression coverage.
- EP-70 established one eager `BuilderDefect` pass for all builder structure and a
  schema pin that removes the builder's `unsafeCoerce` without changing valid keiki
  or keiro authoring. Duplicate `from` blocks now preserve declaration order and
  receive global per-vertex indices. Its `DistinctNames (Names rs)` family is the
  canonical duplicate-slot constraint for EP-78, and its completed handoff rewrites
  EP-68 around `DefectMissingOutputIntent` plus `evaluate tr`.
- GHC 9.12 erases unused deferred type-family constraint evidence, so EP-70's
  duplicate-slot negative regression is compile-only; a non-deferred scratch compile
  verified the exact custom `TypeError`. Term-level deferred type errors remain
  executable and cover the mismatched-schema `emit` case.
- EP-68 made `noEmit` load-bearing through EP-70's eager defect pass. The raw
  silent-edge audit cannot be empty because the regression suite intentionally
  contains two bare-`goto` and three double-`goto` bodies; the durable invariant is
  zero unintended omissions, and every production, example, and positive-test edge
  now declares output intent.
- EP-71 made default validation agree with streaming replay's head-only inversion
  contract and exposed the canonical User Registration pre-confirmation deletion as
  a real persistence defect; it now emits `AccountDeleted`. The Loan Application
  silent promotion remains intentionally process-control-only and is documented as
  invalid for a persist-only stream. Current keiro's default constructors inherit the
  stricter checks, but its caller-options paths pass options through unchanged, so
  keiro EP-99 must force-enable head recoverability and state-changing-epsilon checks
  at the durable boundary as already specified.


## Decision Log

- Decision: one master plan with five themed phases rather than one master plan per
  theme.
  Rationale: user preference confirmed 2026-07-12; a single registry tracks the
  initiative and the themes share integration points (warning type, fixtures,
  replay vocabulary).
  Date: 2026-07-12

- Decision: adopt the pre-existing plan 68 into this master plan (Phase 1, soft-dep
  EP-70) instead of duplicating its scope inside EP-70.
  Rationale: 68 pre-exists with its own intention and a complete spec; but it assumes
  the lazy finalize-`error` mechanism, which the review showed never fires at build
  time. EP-70 supplies the eager mechanism; 68's diagnostic becomes one of its cases.
  Date: 2026-07-12

- Decision: fix the multi-event replay/validation disagreement on the validator side
  (EP-71 rejects head-unrecoverable edges) rather than making replay invert against
  the whole output chain.
  Rationale: replay-side chain inversion would require `solveOutput` across the
  InFlight queue with partially-committed register state — a semantic redesign of
  streaming replay — whereas head-recoverability is exactly the property
  `applyEventStreaming` already assumes; the validator should enforce the evaluator's
  actual contract. Authors who need tail-only fields can restructure the edge
  (documented in EP-71). Revisit only if a real aggregate cannot be expressed.
  Date: 2026-07-12

- Decision: EP-73 is a separate plan rather than test milestones inside EP-71/EP-72.
  Rationale: the round-trip property is the certifying artifact for the whole phase
  and permanent regression infrastructure; it must be implementable and maintainable
  standalone.
  Date: 2026-07-12

- Decision: keiki detects state-changing epsilon edges with a default-on validation
  warning; keiro enforces that warning at `ValidatedEventStream` for durable
  aggregates and process managers.
  Rationale: keiki can inspect the transducer once and preserve opt-out flexibility
  for pure non-persisted uses. Keiro is where events become the sole durable state, so
  its normal validated constructor must reject the shape. A state-preserving `UKeep`
  self-loop remains legal. EP-73 tests complete runs rather than truncating its domain.
  Date: 2026-07-12

- Decision: keiro's durable-stream boundary treats the replay-contract checks as
  non-disableable. Caller-supplied `ValidationOptions` may only strengthen validation
  at `mkEventStream`: keiro force-enables `checkStateChangingEpsilon` and
  `checkHeadRecoverability` before calling `validateTransducer`, for aggregates and
  process managers alike, and its only bypass is a separately named unchecked
  constructor (tests and forensics only), never an options field. keiki keeps the
  `checkStateChangingEpsilon` opt-out for pure non-persisted transducers, with a
  haddock stating it must never be disabled for persisted streams. Keiro's runtime
  divergence witnesses remain in place as defense in depth.
  Rationale: the overriding correctness principle is zero tolerance for silent state
  divergence in event-sourced aggregates and process managers. A config knob that can
  reach the durable boundary is itself a bug vector, and the static checks have
  documented blind spots that the runtime witnesses cover. The non-contract checks
  (`checkInversionAmbiguity`, `checkGuardImpliesInputRead`) stay caller-narrowable —
  they have a documented legitimate-override story.
  Date: 2026-07-12

- Decision: preserve all categorical instances through EP-69/EP-75, but assess laws
  under two named observations: forward execution and replay/inversion. A forward-only
  result is a documented fragment, not an unqualified law claim.
  Rationale: unsafe dictionary repair and algebraic lawfulness are separate concerns.
  Replay is publicly observable and central to keiki, while current keiro does not use
  the wrapper instances. Redesign or removal is deferred until the tests provide
  concrete evidence.
  Date: 2026-07-12

- Decision: make checked concrete composition the primary durable-stream surface;
  fix `alternative` with real `Either`-arm predicates; and gate `feedback1` on a
  shared-state-versus-two-copy contract decision.
  Rationale: name/arity drift must fail before a composite is mounted, synthetic
  constructor arm tags are incompatible with the current symbolic name encoding, and
  alignment validation alone cannot make two independent copies of an aggregate into
  same-state feedback.
  Date: 2026-07-12

- Decision: plan 68 hard-depends on EP-70, and EP-78 reuses EP-70's canonical
  `DistinctNames (Names rs)` constraint.
  Rationale: missing emit intent must participate in the eager structured builder
  defect pass, and duplicate type families for the same slot-name invariant would
  drift.
  Date: 2026-07-12

- Decision: sequence composition fixes (Phase 3) after replay correctness (Phase 2)
  despite EP-74 containing high-severity findings.
  Rationale: Phase 2 defects sit directly on current keiro's aggregate and
  process-manager hydration path. Composition remains an intended same-stream modeling
  surface, but it is not called by current keiro runtime code, so replay correctness
  still has the higher immediate operational priority.
  Date: 2026-07-12

- Decision: this master plan gates the 0.1.0.0 Hackage release; the ROADMAP's
  "only maintainer release steps remain" status is superseded.
  Rationale: user directive 2026-07-12 — keiki targets critical business apps, replay
  bugs there are severe, and the API must be final before the first release because
  post-release changes break persisted-data consumers. Phases 1, 2, 4, 5 admit no
  cut; Phase 3 may ship marked experimental if schedule demands.
  Date: 2026-07-12

- Decision: replay-facing APIs default to strict, structured-failure semantics in
  their release form: `Keiki.Decider` is removed, and the `Either`-returning Core
  replay entry points are the primary documented surface with existing Core `Maybe`
  variants kept as thin wrappers.
  Rationale: user directive 2026-07-12. The facade is letter-only and silently lossy,
  while current keiro already uses the `InFlight`-aware Core surface directly. The
  first release is the right point to remove the duplicate abstraction.
  Date: 2026-07-12


## Outcomes & Retrospective

(To be filled during and after implementation.)

## Revision Notes

- 2026-07-12: Completed EP-71. Added four default-on replay-safety diagnostics,
  shared replay-alignment fixtures, targeted regression coverage, corrected the User
  Registration and Loan Application documentation, verified the keiro migration
  against its registered current source, and passed formatting, all four test suites,
  and library Haddock generation.

- 2026-07-12: Completed EP-68. Required every builder edge to choose
  `emit`/`emitWith` or `noEmit`, added eager located diagnostics and regressions,
  migrated the two deliberate silent test edges, updated documentation and the
  changelog, and recorded that the audit's five remaining hits are intentional
  malformed-edge fixtures.

- 2026-07-12: Completed EP-70. Added eager structured builder validation,
  declaration-ordered merging and stable indices, schema-pinned `emit`, guarded
  `emitWith`, and the canonical `DistinctNames` boundary; updated API documentation,
  changelog, EP-68's implementation handoff, registry, and aggregate progress.

- 2026-07-12: Completed EP-69. Replaced the fabricated `WeakenR` and
  `KnownSlotNames` dictionaries with real `KnownSlots` induction witnesses, added
  stateful nested-composition regressions, updated the registry and aggregate
  progress, and recorded the fail-before corruption evidence.

- 2026-07-12: Associated this MasterPlan and all registered child ExecPlans with
  intention `intention_01kxc5whw1en3ra4nh728m53ka` at the user's request.

- 2026-07-12: Recorded the enforcement posture for the keiki-detects/keiro-enforces
  division (integration point 7 and the new Decision Log entry): replay-contract
  checks are force-enabled and non-disableable at keiro's durable boundary, with a
  named unchecked constructor as the only bypass and keiro's runtime divergence
  witnesses retained as defense in depth. Keiro MP-14, EP-95, and EP-99 were revised
  in the keiro repository to match (they previously recorded a keiro-side scan and a
  three-constructor migration). Also repaired editing artifacts from the previous
  revision (integration point 5's stray parenthesis; garbled sentences in plans 72
  and 75) and stale milestone numbering in plan 71.

- 2026-07-12: Validated the compatibility boundary against current keiro and its
  follow-up MasterPlan 14. Removed stale consumer evidence and the inference that
  absent runtime call sites make composition disposable. Selected removal of the
  entire `Keiki.Decider` interface instead of changing `evolve`; EP-72 otherwise
  retains its structured Core replay and Acceptor scope. State-changing epsilon and
  categorical-law policy remain explicit design discussions rather than silently
  chosen changes.

- 2026-07-12: Recorded the agreed design decisions: default-on keiki detection and
  keiro enforcement of state-changing epsilon; complete-run EP-73 properties;
  checked composition plus real Either-arm predicates; a feedback state-sharing gate;
  separate forward/replay law results with instances preserved; EP-68 hard dependency
  on EP-70; and EP-78 reuse of EP-70's canonical distinct-name constraint.

- 2026-07-12: Initial creation — decomposition into five themed phases with ten new
  child plans (69–78) plus adoption of the pre-existing plan 68. Added the
  release-gate decision (this plan gates 0.1.0.0) and the strict-replay API policy
  per user directive. After all child plans were authored, updated Integration
  Points 1 and 4 to match the decisions actually recorded in the children (EP-76
  adds no warning constructors; EP-75 uses a separate `ComposeAlignmentWarning`;
  EP-74 authors compose-specific fixtures) and recorded six authoring-time
  discoveries in Surprises & Discoveries, most notably the ε-edge falsification of
  the naive round-trip law.
