---
id: 1
slug: validate-symbolic-register-direction-via-haskell-prototype
title: "Validate symbolic-register direction via Haskell prototype"
kind: master-plan
created_at: 2026-05-01T05:19:54Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
---

# Validate symbolic-register direction via Haskell prototype

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Vision & Scope

The keiki library is being designed (no Haskell code exists yet) to handle the **pure
part** of event sourcing, workflow engines, and durable execution as a single
formalism. The working baseline lives at
`docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`. Its
headline:

> C is the formalism. B is an optional presentation layer on top.

C is the **symbolic-register transducer**: state is `(s, RegFile rs)` where `s` is a
finite control vertex and `rs` is a typed heterogeneous register file. Edges unify
guard, update, output, and target. `apply` (the function that recovers state by
replaying events) is **mechanically derived** by walking each edge's `output` term and
inverting it via `solveOutput`. The synthesis claims this derivation works for all
well-formed schemas and **fails detectably at build time** when an event schema is
malformed (the "hidden-input check"). The User Registration aggregate from synthesis §4
walks through both cases.

This initiative validates that synthesis with a working prototype. After every child
plan in this MasterPlan is complete, the repository contains:

- Three new design notes in `docs/research/` that pin down the DSL shape, the schema
  evolution model, and the effects boundary.
- A working Haskell project at the repo root (cabal-based, GHC pinned).
- A pure module `Keiki.Core` implementing the symbolic-register transducer types,
  `step`, `reconstitute`, and `solveOutput`.
- A worked `Keiki.Examples.UserRegistration` aggregate that compiles using only
  `Keiki.Core` constructors and reads as a faithful translation of synthesis §4's
  `userReg` block.
- A test suite that demonstrates two things:
  1. `reconstitute userReg events == Just (Deleted, expectedRegs)` on the canonical
     five-event log from synthesis §4 (with the §4 fix-1 `confirmCode` field added to
     `AccountConfirmed`).
  2. The hidden-input check fires on the **unfixed** schema (where
     `AccountConfirmed` lacks `confirmCode`), demonstrating that the build-time
     guarantee has bite.
- An explicit **ergonomic verdict** captured in the prototype plan's Outcomes &
  Retrospective: tolerable, painful but workable, or blocking.

The master-plan-level acceptance criterion comes directly from the user's brief:

> If the AST surface ergonomics are tolerable and `solveOutput` works on that example,
> the synthesis holds.

In scope:

- Pure Haskell module (`Keiki.Core`).
- The User Registration aggregate as the smoke test.
- Three sharpening design notes (DSL shape, schema evolution, effects boundary).
- The hidden-input check exercised in tests.

Out of scope:

- Any runtime layer (`Keiki.Runtime`): no event store, no message queue, no
  subscriptions, no timer service, no `IO`.
- The Order Fulfillment process manager (a second worked example in synthesis §5).
  It is referenced for context but not implemented.
- The optional B-view (per-vertex GADTs from `data-direction-b-indexed-state-per-vertex.md`).
- SBV-backed `BoolAlg` (synthesis §7 names this as v2).
- Composition operators (`compose`, `lmapMaybeC`).
- Schema upcasting / versioning machinery (the schema-evolution note settles the model
  and confirms v1 implements none of it).
- Performance work, concurrency, persistence.


## Decomposition Strategy

The initiative decomposes into **two phases** of work — sharpening followed by
prototyping.

The user's brief named three unresolved areas — DSL shape, schema evolution, effects
boundary — and asked that all three be sharpened *before* prototyping starts. The
prototype plan's acceptance ("AST ergonomics tolerable AND `solveOutput` works") is a
binary judgment; if any of the three open areas is unresolved when the prototype
begins, the prototype's authors must invent an answer mid-implementation, which
defeats the validation gate. Sharpening first, in writing, lets each open question be
answered against the synthesis baseline rather than against a half-built prototype.

The sharpening work splits into three independent design notes because the three
areas are mostly orthogonal:

- **DSL shape** is about the AST surface — how `Term`, `OutTerm`, `Update`, `Edge`
  look as concrete Haskell datatypes, how the User Registration aggregate reads when
  written using them.
- **Schema evolution** is about how event payloads, register files, and command
  alphabets change over time and how `solveOutput` and the hidden-input check behave
  across versions.
- **Effects boundary** is about what is pure (the transducer, `step`, `reconstitute`,
  `solveOutput`) and what is runtime (event store, queue, subscriptions, timers,
  clock).

Each design note is independently verifiable (the deliverable is a written note with
a clear scope) and can proceed in parallel with the other two. None of the three
design plans need to read the others' outputs to do their own work.

The prototype is a single ExecPlan rather than two for cohesion: the master-plan
acceptance is "the synthesis holds, end to end" and that is one logical question
answered by one passing test suite. Splitting the prototype into "types" and "smoke
test" plans would force one of them to halt without proving anything. Eight
milestones inside the prototype plan keep the work granular enough to track and
commit incrementally.

**Alternatives considered:**

- *Single ExecPlan for everything (no MasterPlan).* Rejected: the user explicitly
  asked to sharpen three open areas first, and lumping the design and prototype work
  into one plan would obscure the gating relationship.
- *Sharpen only one area, prototype against working assumptions for the other two.*
  Considered when the user picked "DSL shape" as the recommended option, but the user
  then chose "all of the above," so all three sharpenings are mandatory.
- *Skip sharpening entirely and let the prototype surface the open questions.*
  Rejected for the same reason as the first alternative.
- *Split the prototype into two plans (foundation + smoke test).* Rejected because
  the validation gate is "the synthesis holds end-to-end" — that question is only
  answered by the smoke test passing, so splitting would mean one plan completes
  without answering the gating question.
- *Implement the Order Fulfillment example (synthesis §5) as a second smoke test.*
  Rejected for v1: synthesis §4 is sufficient evidence that the formalism works on
  an aggregate, and §5's process-manager-specific concerns (subscriptions, dispatch,
  timers) are runtime concerns explicitly out of scope.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| 1 | Sharpen DSL shape for symbolic-register transducer | docs/plans/1-sharpen-dsl-shape-for-symbolic-register-transducer.md | None | None | Complete |
| 2 | Sharpen schema evolution for events and registers | docs/plans/2-sharpen-schema-evolution-for-events-and-registers.md | None | None | Complete |
| 3 | Sharpen effects boundary between pure transducer and runtime | docs/plans/3-sharpen-effects-boundary-between-pure-transducer-and-runtime.md | None | None | Complete |
| 4 | Prototype symbolic-register core with User Registration smoke test | docs/plans/4-prototype-symbolic-register-core-with-user-registration-smoke-test.md | EP-1, EP-2, EP-3 | None | Not Started |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix (e.g., EP-1, EP-3).


## Dependency Graph

```
        ┌──────────┐    ┌──────────┐    ┌──────────┐
        │  EP-1    │    │  EP-2    │    │  EP-3    │
        │  DSL     │    │  Schema  │    │  Effects │
        │  shape   │    │  evol.   │    │  bound.  │
        └────┬─────┘    └────┬─────┘    └────┬─────┘
             │               │               │
             └───────┬───────┴───────────────┘
                     │   (all hard deps)
                     ▼
                 ┌────────────────┐
                 │      EP-4      │
                 │   Prototype    │
                 │  Keiki.Core +  │
                 │  smoke test    │
                 └────────────────┘
```

**EP-1 (DSL shape) → EP-4 hard.** The prototype defines `Term`, `OutTerm`, `Update`,
`Edge`, `RegFile`, `HsPred` as concrete datatypes. Their constructors come from the
DSL note's "Prototype Implementation Checklist." Without that checklist, the
prototype must invent its own DSL mid-implementation, which contaminates the
ergonomic verdict (the prototype author would judge their own design).

**EP-2 (schema evolution) → EP-4 hard.** The prototype's scope is "v1 prototype
assumes a single static schema." That scoping decision lives in the schema-evolution
note. Without it, the prototype's authors must decide on the spot whether to include
upcasting, versioning, or migration — all of which would balloon the prototype scope
and risk masking the synthesis-validation question.

**EP-3 (effects boundary) → EP-4 hard.** The prototype's pure-layer entry points
(`step :: SymTransducer phi rs s ci co -> (s, RegFile rs) -> ci -> Maybe (s, RegFile rs, Maybe co)`,
`reconstitute :: SymTransducer phi rs s ci co -> [co] -> Maybe (s, RegFile rs)`)
are pinned in the boundary note. So is the discipline that times and confirmation
codes arrive in command payloads (the runtime adapter generates them, the pure layer
never calls `getCurrentTime` or random-IO). Without this, the prototype risks leaking
`IO` into `Keiki.Core` or building a runtime layer the master plan explicitly excludes.

**EP-1, EP-2, EP-3 are mutually independent.** No design note reads another design
note's output to do its own work. They share inputs (the synthesis note, the existing
research notes) but produce orthogonal outputs. This means **all three can proceed in
parallel** in Phase 1 — by separate sessions, separate contributors, or one
contributor in any order — and then EP-4 begins in Phase 2 once all three are
complete.

**Phasing:**

- *Phase 1 — Sharpening (parallel):* EP-1, EP-2, EP-3.
- *Phase 2 — Prototype (sequential after Phase 1):* EP-4.

EP-4 has eight milestones internally; see its plan file for the milestone-level
ordering.


## Integration Points

The four plans share several artifacts that this section names explicitly so later
plans don't make conflicting assumptions.

### IP-1: The User Registration aggregate (synthesis §4)

**Plans involved:** EP-1, EP-2, EP-4 (also referenced incidentally by EP-3).

**Shared artifact:** the canonical worked example. Synthesis §4 defines its domain
types, command and event payloads, register-file shape, vertex enumeration, and the
`userReg` transducer. The five-event canonical log
(`RegistrationStarted`, `ConfirmationEmailSent`, `ConfirmationResent`,
`AccountConfirmed`, `AccountDeleted`) is the test fixture for `reconstitute`. The
fix-1 / fix-2 alternatives (synthesis §4 step 4) are the canonical hidden-input bug
demonstration.

**Owner:** the synthesis note itself owns the source of truth. Plan EP-1 owns the
*re-transcription* of `userReg` into the chosen DSL (in the DSL design note's
"Worked Example" section). Plan EP-4 owns the *Haskell implementation* (in
`src/Keiki/Examples/UserRegistration.hs`).

**Consumers:**

- EP-1 transcribes `userReg` to validate the DSL is tolerable. The transcription
  uses concrete DSL constructors only (no pseudosyntax).
- EP-2 walks at least three User Registration *evolution scenarios* (add field,
  remove field, restructure event) under the chosen evolution model. The scenarios
  build on synthesis §4's domain.
- EP-4 implements `userReg` in `src/Keiki/Examples/UserRegistration.hs` matching
  EP-1's transcription, and tests `reconstitute userReg events` end-to-end.

**Coordination rule:** if EP-1's transcription differs structurally from synthesis §4
(e.g., needs an extra register slot to cope with the chosen DSL's limitations), EP-4's
implementation must follow EP-1's transcription, not synthesis §4. Document any such
divergence in EP-1's Decision Log and EP-4's Decision Log.

### IP-2: The hidden-input check

**Plans involved:** EP-1, EP-2, EP-4.

**Shared artifact:** the build-time analysis that flags edges whose `update` or
`guard` reads input fields not present in `output`. Synthesis §4 step 4 names it;
direction-C §5 elaborates.

**Owner:** EP-4 implements `checkHiddenInputs :: SymTransducer phi rs s ci co -> [HiddenInputWarning]`.

**Consumers:**

- EP-1 specifies the precise inversion contract on `OutTerm` that the check needs to
  function. If `OutTerm` is opaque (just a `RegFile rs -> ci -> co` function), the
  check has no purchase. The DSL note must commit to a structural enough `OutTerm`
  for the check to inspect — or explicitly accept that v1's check is a best-effort
  that warns "edge uses opaque mkOut" instead.
- EP-2 specifies whether the check runs across schema versions (recommended: only
  against the current schema, with the upcaster handling old events).
- EP-4 implements the check and tests it firing on the unfixed `AccountConfirmedData`
  (Milestone 7).

**Coordination rule:** EP-1's `OutTerm` design and EP-4's `checkHiddenInputs`
implementation must agree on the inversion shape. If EP-1 picks an opaque `mkOut`,
EP-4's check is necessarily best-effort — document this trade-off in EP-1.

### IP-3: Pure-layer entry-point signatures (`step`, `reconstitute`)

**Plans involved:** EP-3, EP-4.

**Shared artifact:** the type signatures of `step` and `reconstitute`.

**Owner:** EP-3 (the boundary note) names the canonical signatures.

**Consumer:** EP-4 implements them. The implementation must match the names and
signatures in the boundary note exactly. If EP-4 needs to deviate (e.g., the chosen
`OutTerm` shape forces `reconstitute` to return a richer error type than `Maybe`),
update EP-3's note via the exec-plan skill's `update` mode and reflect the change
here.

### IP-4: Module layout (`Keiki.Core`)

**Plans involved:** EP-3, EP-4.

**Shared artifact:** the module name `Keiki.Core` (and the future `Keiki.Runtime`,
`Keiki.Examples.UserRegistration`).

**Owner:** EP-3 (the boundary note) proposes the module layout.

**Consumer:** EP-4 implements `Keiki.Core` and `Keiki.Examples.UserRegistration`.
EP-4 does **not** create `Keiki.Runtime` (out of scope per the boundary note).

### IP-5: The `RegFile` representation choice

**Plans involved:** EP-1, EP-4.

**Shared artifact:** the runtime representation of `RegFile rs` — hand-rolled GADT,
`vinyl`, `large-records`, etc.

**Owner:** EP-1 picks it (with rationale, after a survey of alternatives).

**Consumer:** EP-4 imports the chosen library (or hand-rolls per EP-1's sketch) and
adds it to `keiki.cabal`'s dependency list.

**Coordination rule:** if EP-4 discovers the chosen representation doesn't support
something the User Registration aggregate needs (e.g., `OverloadedLabels` doesn't
work cleanly with the type list shape), update EP-1's note via the exec-plan skill's
`update` mode rather than silently swapping representations. The DSL note is the
source of truth for the chosen representation.

### IP-6: Time and randomness discipline

**Plans involved:** EP-3, EP-4.

**Shared artifact:** the rule that time and randomness arrive in command payloads
(`StartRegistrationData.at`, `ResendConfirmationData.code`), generated by an adapter
outside the pure layer.

**Owner:** EP-3 (the boundary note) pins the rule.

**Consumer:** EP-4 implements `Keiki.Examples.UserRegistration` accordingly. In
particular, `freshCode` (used pseudosyntactically in synthesis §4) becomes a field
of `ResendConfirmationData`, populated by the test fixture in
`test/Keiki/Examples/UserRegistrationSpec.hs`.


## Progress

This section aggregates milestone-level progress across all child plans for an
at-a-glance view.

- [x] EP-1: Author DSL design note at `docs/research/dsl-shape-for-symbolic-register.md` (2026-05-01)
- [x] EP-2: Author schema-evolution design note at `docs/research/schema-evolution.md` (2026-05-01)
- [x] EP-3: Author effects-boundary design note at `docs/research/effects-boundary.md` (2026-05-01)
- [ ] EP-4: Verify prerequisites (Milestone 0)
- [ ] EP-4: Project scaffolding and types compile (Milestone 1)
- [ ] EP-4: Bare-minimum evaluator (Milestone 2)
- [ ] EP-4: `step` and `reconstitute` skeletons (Milestone 3)
- [ ] EP-4: `solveOutput` for `OutTerm` (Milestone 4)
- [ ] EP-4: User Registration aggregate compiles (Milestone 5)
- [ ] EP-4: End-to-end test passes on fixed schema (Milestone 6)
- [ ] EP-4: Hidden-input check fires on unfixed schema (Milestone 7)
- [ ] EP-4: Ergonomic verdict in Outcomes & Retrospective (Milestone 8)


## Surprises & Discoveries

Document cross-plan insights, dependency changes, scope adjustments, or unexpected
interactions between child plans. Provide concise evidence.

### From EP-1 (DSL shape; 2026-05-01)

- **IP-1 (User Registration transcription):** v1's `inp` is opaque (`(ci -> r)`),
  so transcribing synthesis §4 in the chosen DSL forces *total* callbacks — every
  `inp` lambda must handle every command constructor, with non-applicable branches
  written as `_ -> error "guard rules this out"`. The synthesis §4 pseudosyntax
  (`\(StartRegistration d) -> d.email`) hides this. Concrete consequence: the
  transcription is more verbose than §4. v2's structural `TInpProj` constructor
  retires the pain.
- **IP-2 (hidden-input check):** if every edge uses the v1 `OFn` opaque escape
  hatch for its output, the hidden-input analysis would warn on every edge and
  the master-plan acceptance criterion ("`solveOutput` works on the example")
  becomes unobservable. **EP-4 must include at least one structural `OPack`
  output** — `RegistrationStarted` is the recommended choice — so the check has
  a real edge to inspect and so synthesis §4's step-4 hidden-input bug is
  actually demonstrable on the unfixed schema.
- **IP-5 (RegFile representation):** `vinyl`, `large-records`, `extensible`, and
  `superrecord` are not in the local `mori` registry. The survey relied on
  published API docs. The chosen hand-rolled GADT depends on none of those four,
  so the representation choice is robust against the limitation. EP-4 should
  not need to introduce a new dependency for the register file.
- **Ergonomic verdict:** *painful but workable*. Pain concentrates in three v1
  escape hatches (`TInpField`, `OFn`, `PMatchC`); v2 retirements are listed in
  the DSL note's checklist. Verdict is non-blocking for the master-plan gate.

### From EP-2 (schema evolution; 2026-05-01)

- **Upcaster shape is 1-to-many.** The chosen v1 model is an explicit upcaster
  at the event-store boundary with signature
  `WireEvent -> Either Error [CurrentEvent]`. The list return is required to
  handle constructor-split refactorings (Scenario C in the schema-evolution
  note). This affects EP-3's effects boundary: the event-store-read port must
  allow a single wire-read to expand into multiple events transparently to the
  runtime loop.
- **Hidden-input check role broadens.** The same `checkHiddenInputs` analysis
  also fires on schema refactorings that drop a field while leaving a writer
  for it. EP-1's check belongs to the DSL surface as designed; EP-4's tests
  for the check should also cover an evolution case in addition to the
  synthesis-§4 instance.
- **Snapshot shape-hash is cheap and forward-compatible.** EP-4 should compute
  and store a register-file shape hash on every snapshot even though v1 never
  compares it. One line of code; future-proofs the on-disk format so v2
  evolution work does not require a snapshot-format migration.
- **Pure semantic change is permanently outside the library's reach.** Same
  shape, different meaning is undetectable by any formalism mechanism. The
  application must adopt a domain-level versioning convention. Worth recording
  here so future contributors do not expect keiki to "handle versioning"
  universally.
- **`crem` and `tan-event-source` not in `mori` registry.** Schema-evolution
  survey of those two relied on published documentation; `message-db` and
  `tan/message-db-hs` were inspected locally. All four delegate evolution to
  the application — no library does it natively.

### From EP-3 (effects boundary; 2026-05-01)

- **IP-6 (time/randomness) forces a small divergence from synthesis pseudosyntax.**
  Synthesis §4's `Set #confirmCode freshCode` is not directly representable in
  the chosen DSL because the pure layer cannot pull randomness. EP-4's User
  Registration translation must add `code :: ConfirmationCode` as a field of
  `ResendConfirmationData`, populated by the test fixture (the hypothetical
  adapter generates the code before constructing the input). The edge becomes
  `Set #confirmCode (\(ResendConfirmation d) -> d.code)`. Document the
  divergence in EP-4's Decision Log when the User Registration aggregate is
  written.
- **`checkHiddenInputs` returns `[HiddenInputWarning]`, not `Bool`.** The
  warning shape is structural — it names the bad edge, the input field that
  is hidden, and the output term that fails to mention it. This cross-cuts
  EP-1 (the shape of `HiddenInputWarning` depends on `OutTerm`'s structural
  encoding — IP-2) and EP-4 (which implements the analysis).
- **No `Keiki.Runtime` module in v1, even an empty one (IP-4).** Adding it
  invites a contributor to put `IO` in it before the runtime design is ready.
  EP-4 adds only `Keiki.Core` and `Keiki.Examples.UserRegistration`.
- **`isSingleValued` is exposed but best-effort in v1.** Syntactic
  conservative approximation; not exercised by the smoke test. May be
  re-precision'd in v2 once the SBV-backed `BoolAlg` instance lands.
- **`crem` and `tan-event-source` not in the `mori` registry.** Effects-boundary
  survey of those two relied on published-docs knowledge. `effectful` and
  `tan/message-db-hs` were inspected locally; `tan/message-db-hs`'s
  `MessageDb` effect surface is the shape `Keiki.Runtime`'s eventual
  event-store port should mirror.

### Phase 1 complete

All three sharpening plans (EP-1, EP-2, EP-3) are Complete as of 2026-05-01.
EP-4 (the prototype) is unblocked.


## Decision Log

- Decision: Decompose into three sharpening plans (DSL shape, schema evolution,
  effects boundary) plus one prototype plan, in two phases.
  Rationale: The user's brief named three unresolved areas and asked that all three
  be sharpened before prototyping. The three areas are mutually independent and can
  proceed in parallel; the prototype is a single cohesive validation gate that must
  consume all three.
  Date: 2026-04-30

- Decision: Each sharpening plan produces a Markdown design note in `docs/research/`,
  not Haskell code.
  Rationale: The prototype is the place for code; producing partial code in the
  sharpening plans would conflate "is the design tolerable on paper" with "does the
  prototype compile" — each is a separate validation. Writing the design down in
  prose first lets the prototype focus on implementing a known target.
  Date: 2026-04-30

- Decision: Single prototype plan, not split.
  Rationale: The master-plan acceptance is "the synthesis holds end-to-end" — that
  question is only answered by the smoke test passing. Splitting the prototype would
  mean one plan completes without answering the gating question.
  Date: 2026-04-30

- Decision: User Registration only; Order Fulfillment (synthesis §5) deferred.
  Rationale: synthesis §4 is sufficient evidence for the validation gate. §5's
  process-manager-specific concerns (subscriptions, dispatch, timers) are runtime
  concerns explicitly out of scope for the v1 prototype per the planned effects-boundary
  note.
  Date: 2026-04-30

- Decision: Pure module only — no `Keiki.Runtime`, no `IO`, no event store, no queue.
  Rationale: The synthesis names keiki as the *pure* part of the broader system. The
  master-plan acceptance ("AST ergonomics tolerable AND `solveOutput` works") is
  about the formalism, not the runtime. Bringing in any runtime concern dilutes the
  validation gate.
  Date: 2026-04-30

- Decision: Capture the verdict explicitly in EP-4's Outcomes & Retrospective and
  cascade it to this MasterPlan's Outcomes & Retrospective.
  Rationale: "Tolerable / painful but workable / blocking" is the master-plan-level
  result. Without an explicit verdict, the gate question (does the synthesis hold?)
  has no recorded answer.
  Date: 2026-04-30


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original vision.

(To be filled during and after implementation. The final entry must answer:
**Does the synthesis hold?** with a one-sentence verdict and a pointer to the
prototype plan's Outcomes & Retrospective.)
