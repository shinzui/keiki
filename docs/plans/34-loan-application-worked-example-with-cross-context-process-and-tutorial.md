---
id: 34
slug: loan-application-worked-example-with-cross-context-process-and-tutorial
title: "Loan Application worked example with cross-context Process and tutorial"
kind: exec-plan
created_at: 2026-05-03T19:18:15Z
intention: "intention_01kqqm4xexe9ps81r0kz3fz76z"
---

# Loan Application worked example with cross-context Process and tutorial

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this change the keiki repository contains:

1. A new sibling Haskell package, **`jitsurei`** (実例 = "concrete
   example, real-world case"), at `jitsurei/` next to the existing
   `keiki` package, that owns *all* worked examples — both the
   pre-existing aggregates (`UserRegistration`,
   `UserRegistrationV0`, `OrderCart`, `EmailDelivery`) and the new
   loan-underwriting workflow (`LoanApplication`, `Loan`,
   `CoreBankingSync`, `LoanWorkflow`). The core `keiki` library
   stops shipping `Keiki.Examples.*` modules in its public surface,
   so a downstream user gains a smaller, focused dependency.
2. A new worked example — the loan-underwriting trio plus their
   composition — that mirrors the production
   `AgentQualification → QualifiedAgent → LegacyQaCreator Process`
   pattern at
   `/Users/shinzui/Keikaku/work/microtan/mls-service-v2-master/`,
   in a domain familiar to every reader. The example *naturally*
   exercises keiki features that no current example covers: multi-
   field threshold guards, ε-edges for silent progress, per-vertex
   `View` variance, sequential `compose` of three aggregates with
   forward-only `lmapMaybeCi` adapters, and the `MultiDecider`
   chain.
3. A new tutorial at `docs/guide/loan-application-tutorial.md`
   that walks the reader through the loan workflow end-to-end,
   introducing each new keiki construct *as the loan story makes
   it necessary* — not as a feature dump.

Reading the tutorial together with the new modules under
`jitsurei/src/Jitsurei/` should leave the reader able to:

- Author an aggregate that *accumulates evidence* across many
  commands (document submissions, credit checks, employment
  verifications) and advances vertices on multi-field threshold
  guards like `creditScore >= 650 ∧ employmentVerified ∧
  requestedAmount <= maxApproval(creditScore)`.
- Use ε-edges (silent transitions) for "internal progress that
  does not need a public event" — for example, a sufficient
  document set tipping the application from
  `CollectingDocuments` to `UnderReview`.
- Use the per-vertex B-view (`deriveView`) when the live data
  genuinely differs by control state — `Approved` exposes
  `principal/term/rate/decidedAt` while `Drafting` only exposes
  `applicantId`.
- Use the `MultiDecider` façade (`toMultiDecider` +
  `DriverConfig`) together with `B.chainTo` to express commands
  that legitimately produce multiple events in one step.
- Use `Keiki.Composition.compose` (with `lmapMaybeCi` adapters
  from `Keiki.Profunctor`) to wire three aggregates into one
  pipeline — the keiki analogue of the production
  "Aggregate → Subscription/Queue → Process → Aggregate"
  choreography.
- Render single and composite Mermaid diagrams of the workflow
  so the tutorial has visual aids and the test suite has golden-
  output regressions.

Observable acceptance: after implementation, running

    cabal build all
    cabal test all --test-show-details=direct

at the repository root succeeds; the test summary prints two test
suites — `keiki:keiki-test` (smaller than today, no
`Keiki.Examples.*Spec` modules) and `jitsurei:jitsurei-test` — both
green. A reader opening
`docs/guide/loan-application-tutorial.md` finds an incremental walk-
through that ends with a working composed pipeline they can
reproduce by following the steps verbatim.


## Progress

Use a checklist to summarize granular steps. Every stopping point
must be documented here, even if it requires splitting a partially
completed task into two ("done" vs. "remaining"). This section
must always reflect the actual current state of the work.

- [x] M1 — Split out the `jitsurei` package and migrate all
      existing examples + their specs + the `tasty-bench` benchmark
      into it. (2026-05-03)
  - [x] Create `jitsurei/` directory layout (`src/Jitsurei/`,
        `test/Jitsurei/`, `bench/`, `jitsurei.cabal`,
        `jitsurei/test/Spec.hs`).
  - [x] Update root `cabal.project` to `packages: ., jitsurei`.
  - [x] Move and rename example modules:
        `src/Keiki/Examples/EmailDelivery.hs` →
        `jitsurei/src/Jitsurei/EmailDelivery.hs`;
        `…/UserRegistration.hs` → `jitsurei/src/Jitsurei/UserRegistration.hs`;
        `…/UserRegistrationV0.hs` → `jitsurei/src/Jitsurei/UserRegistrationV0.hs`;
        `…/OrderCart.hs` → `jitsurei/src/Jitsurei/OrderCart.hs`.
  - [x] Move and rename test specs:
        `test/Keiki/Examples/*.hs` (11 files) →
        `jitsurei/test/Jitsurei/*Spec.hs`.
  - [x] Move `bench/` (`Bench.hs`, `README.md`) →
        `jitsurei/bench/`.
  - [x] Strip `Keiki.Examples.*` from
        `keiki.cabal` `library.exposed-modules` and remove the
        benchmark stanza.
  - [x] Strip `Keiki.Examples.*Spec` from `keiki.cabal`
        `keiki-test.other-modules`; remove the matching
        `describe` blocks from `test/Spec.hs`.
  - [x] Inline test-only fixtures `Keiki.Fixtures.EmailDelivery`
        and `Keiki.Fixtures.UserRegistration` under
        `test/Keiki/Fixtures/` (forced by the
        `keiki:test ↔ jitsurei` cabal cycle — see Surprises &
        Discoveries 2026-05-03). Route the nine affected
        keiki-test specs (`Acceptor`, `Composition`,
        `CompositionAlternative`, `CompositionFeedback1`,
        `CoreApplyEvents`, `Decider`, `DeciderMulti`, `NoThunks`,
        `Profunctor`) at the fixture modules.
  - [x] Keep the existing `test/Keiki/Render/MermaidSpec.hs` —
        it now imports `Keiki.Fixtures.{EmailDelivery,
        UserRegistration}` so it remains self-contained without a
        synthetic toy. (Deferred the synthetic-toy refactor; the
        plan's stated rationale was self-containment, which the
        fixture rename already achieves.)
  - [x] Update `flake.nix` to expose
        `haskellPackages.jitsurei` alongside
        `haskellPackages.keiki`.
  - [x] Update doc cross-references in live docs
        (`docs/foundations/06-where-to-go-next.md`,
        `docs/guide/{user-guide,ast-drop-down,profunctor,
        b-views}.md`, every relevant `docs/guide/diagrams/*.md`
        page, and the listed research notes) from
        `Keiki.Examples.X` to `Jitsurei.X`. Historical plans /
        masterplans / older research-design notes remain
        unchanged because they record the codebase state at the
        time they were authored.
  - [x] Update the haddock cross-reference in
        `src/Keiki/Generics/TH.hs:116`.
- [x] M2 — `Jitsurei.LoanApplication` aggregate (vertices,
      register file, commands/events, builder + AST forms,
      ε-edges, multi-field guards, B-view). (2026-05-03)
  - [x] Module skeleton with `jitsurei.cabal` entry.
  - [x] Domain types (commands, events, payloads).
  - [x] Register file and `LoanAppVertex` enum (vertex
        @Drafting@ renamed @Intake@ to satisfy
        `deriveView`'s prefix-uniqueness rule — see
        Decision Log).
  - [x] TH splices (`deriveAggregateCtors`, `deriveWireCtors`,
        `deriveView`).
  - [x] Builder-form `loanApplication` transducer (the
        @CollectingDocuments → UnderReview@ "ε-edge" is
        @onCmd inCtorContinue + noEmit@ rather than
        @onEpsilon@; see Decision Log).
  - [x] AST-form `loanApplicationAST` transducer (for
        builder/AST equivalence).
  - [x] `Jitsurei.LoanApplicationSpec` (round-trip + 'delta'
        coverage of the silent advance and approval/decline
        edges).
  - [x] `Jitsurei.LoanApplicationBuilderSpec`
        (builder/AST equivalence over every prefix).
  - [x] `Jitsurei.LoanApplicationViewSpec` (B-view projection).
  - [x] `Jitsurei.LoanApplicationSymbolicSpec`
        (`isSingleValuedSym`) — currently pending; documented
        SBV limitation around `TApp1` / `TApp2` (see
        Surprises & Discoveries 2026-05-03).
- [x] M3 — MultiDecider chain for `Jitsurei.LoanApplication`. (2026-05-03)
  - [x] `loanApplicationDriverConfig` and
        `loanApplicationChained` with `B.chainTo` (only the
        silent advance is chained from `StartApplication`; the
        Continue-driven approval/decline branches stay in an
        explicit `from UnderReview` block because chainTo can
        carry only one branch).
  - [x] `KnownInCtors LoanCmd` instance (was already added in
        M2 for the symbolic spec).
  - [x] `Jitsurei.LoanApplicationChainedSpec` (chained-form /
        letter-form equivalence on the canonical evidence log).
  - [x] `Jitsurei.LoanApplicationMultiSpec` (multi-event
        command produces a 2-event chain
        `[EmploymentChecked, ApplicationApproved]` from a single
        `RecordEmploymentCheck` on threshold-poised regs).
- [x] M4 — `Jitsurei.Loan` aggregate (target of cross-context
      creation) and `Jitsurei.CoreBankingSync` Process (legacy
      idempotency). (2026-05-03)
  - [x] `Jitsurei.Loan` module + spec.
  - [x] `Jitsurei.CoreBankingSync` module + spec (happy path /
        idempotency / mismatched-callback). The output's
        `LegacyAssignmentCommanded` is wrapped in a single-field
        record `LegacyAssignmentCommandedData { assignment ::
        LoanCmd' }` because `deriveWireCtors` requires payloads
        to be record-syntax constructors.
- [x] M5 — Sequential composition `LoanApplication ⨾
      CoreBankingSync ⨾ Loan`. (2026-05-03)
  - [x] `Jitsurei.LoanWorkflow` composes all three with
        `Keiki.Composition.compose` + two `lmapMaybeCi`
        adapters. The composite is type-correct but largely
        unfireable end-to-end because compose is lockstep and
        the cross-context creation flow is async (see
        Surprises & Discoveries 2026-05-03).
  - [x] `Jitsurei.LoanWorkflowSpec` exercises each cross-
        context jump (LoanApplication → CoreBankingSync,
        CoreBankingSync → Loan) via the adapter functions and
        direct driver calls, mirroring what the runtime
        adapter would do. End-to-end:
        `LoanCmd → ApplicationApproved → SyncToLegacyRequested
        → (legacy callback) → LegacyAssignmentCommanded →
        AssignLegacyLoanId → LegacyLoanIdAssigned`.
- [x] M6 — Mermaid render + golden tests. (2026-05-03;
      composite goldens added 2026-05-04 by EP-35)
  - [x] `Jitsurei.Render.MermaidLoanSpec` pins single-aggregate
        renders for `loanApplication`, `loan`, and
        `coreBankingSync`. The three-deep `loanWorkflow`
        composite was deferred at M6 because no shipped
        renderer (EP-30..EP-33) targets the right-associative
        3-deep `Composite LoanAppVertex (Composite SyncVertex
        LoanVertex)` shape with three distinct types. EP-35
        (`docs/plans/35-mermaid-renderer-for-right-associative-3-deep-compose-composites.md`)
        subsequently shipped `toMermaidCompose3` (flat) and
        `toMermaidCompose3Nested` (one-level nested) and pinned
        the loanWorkflow composite via both renderers; the
        Outcomes → Follow-ups item is now closed.
  - [x] Golden Mermaid files under
        `docs/guide/diagrams/loan-application.mmd`,
        `…/loan.mmd`, `…/core-banking-sync.mmd`, and (EP-35
        addition) `…/loan-workflow.mmd` and
        `…/loan-workflow-nested.mmd`.
- [x] M7 — Tutorial walkthrough at
      `docs/guide/loan-application-tutorial.md`. (2026-05-03)
  - [x] Eleven-section incremental narrative covering M2..M6:
        what we are building → modelling the application
        aggregate → accumulating evidence → ε-edges → multi-
        field threshold guards → per-vertex View variance →
        multi-event commands via MultiDecider → the downstream
        Loan aggregate → the CoreBankingSync Process → wiring
        with `compose` (including the lockstep variance
        caveat) → where to go from here.
  - [x] Cross-reference from `docs/guide/user-guide.md` §11
        ("Where to go from here") added as a new bullet
        pointing at the tutorial.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights
discovered during implementation. Provide concise evidence.

- 2026-05-03 — `keiki-test`'s self-containment is broader than M1
  step 10 articulated. Beyond `Render/MermaidSpec`, *nine other*
  keiki-test specs import `Keiki.Examples.*` as test fixtures:
  `AcceptorSpec`, `CompositionSpec`, `CompositionAlternativeSpec`,
  `CompositionFeedback1Spec`, `CoreApplyEventsSpec`,
  `DeciderSpec`, `DeciderMultiSpec`, `NoThunksSpec`, and
  `ProfunctorSpec`. Evidence: `git grep -l 'import
  Keiki\.Examples' test/`. Removing the example modules from the
  `keiki` library's surface therefore breaks every one of these
  specs unless their imports are rewritten. Keeping them as-is
  but pointing at `Jitsurei.X` makes `keiki-test` build-depend on
  `jitsurei`, which contradicts M1 step 10's "layering"
  rationale. See the corresponding Decision Log entry for the
  resolution chosen.

- 2026-05-03 — `Keiki.Composition.compose` is lockstep, while
  cross-context creation flows are async. `compose t1 t2`
  produces a transducer whose every non-ε composite edge fires
  *both* t1 *and* t2 simultaneously. For the LoanWorkflow this
  means: a `StartApplication` LoanCmd makes t1 emit
  `ApplicationStarted`; the lmapMaybeCi'd t2 (CoreBankingSync)
  adapter returns 'Nothing' for `ApplicationStarted`, so t2 has
  no firing edge from `SyncIdle` for that input. Composite
  step ⇒ 'Nothing'. The composite is therefore empty for every
  LoanCmd that advances t1. Even the one cross-context-relevant
  edge (LoanApplication's `ApplicationApproved` mapping to
  CoreBankingSync's `LoanCreatedIn`) is downstream — only if
  the runtime issues `Continue` AT the moment t1 reaches
  Approved AND t2 happens to be at SyncIdle does the composite
  fire. And t3's adapter returns 'Nothing' for t2's
  `SyncToLegacyRequested` audit emit, so the three-way compose
  has no firing chain at all. Resolution: the M5 module
  defines `loanWorkflow` as the three-way compose for type-
  level demonstration; the spec exercises each cross-context
  jump (LoanApplication → CoreBankingSync,
  CoreBankingSync → Loan) via separate driver calls that
  mimic the runtime adapter, since `compose`'s lockstep
  semantics don't match the natural async-creation
  architecture. This is the documented variance caveat in
  `docs/guide/profunctor.md` made concrete.

- 2026-05-03 — `isSingleValuedSym (withSymPred loanApplication)`
  answers @False@ rather than @True@. Root cause: the multi-field
  threshold guards (`approvalGuard`, `readyForReviewGuard`) use
  `TApp1` / `TApp2` to lift Haskell-level `(>=)` and `(<=)` over
  registers (there is no `PCompare` constructor on 'HsPred'), and
  'Keiki.Symbolic' translates each occurrence of `TApp1` / `TApp2`
  to a fresh anonymous SBV variable — it cannot symbolically
  evaluate arbitrary Haskell functions. The approval and decline
  edges out of `UnderReview` share `PAnd isContinue approvalGuard`
  vs `PAnd isContinue (PNot approvalGuard)`. Each translation of
  `approvalGuard` yields a *new* SBV variable, so SBV cannot
  identify the two as the same expression and the conjunction
  `approvalGuard ∧ ¬approvalGuard` is reported as satisfiable.
  This is a documented limitation of the v2 SBV backend (see
  `Keiki.Symbolic`'s module haddock around `TApp1` / `TApp2`).
  Resolution adopted: mark the M2 symbolic spec as
  `pendingWith` a precise reason. Un-pending requires either a
  memoising translator that recognises identical `TApp1`
  sub-terms or a richer `HsPred` with a comparison constructor;
  both are out of EP-34's scope.

- 2026-05-03 — adding `jitsurei` to `keiki:test`'s `build-depends`
  produces a *cabal* dependency cycle: `cabal build all` reports
  `[__2] rejecting: keiki:*test (cyclic dependencies; conflict
  set: jitsurei, keiki)`. Cabal sees `keiki:test` as part of
  package `keiki`, and `jitsurei`'s library already
  `build-depend`s on `keiki`. Adding `jitsurei` to `keiki:test`
  would require `keiki` to depend on `jitsurei` to satisfy
  `keiki:test`, while `jitsurei` already depends on `keiki` —
  hence the cycle. The structural conclusion: there is no way to
  make `keiki:test` and `jitsurei:lib` co-exist as a chain. The
  fixture-inline approach (test-only copies of EmailDelivery /
  UserRegistration under `test/Keiki/Fixtures/`) is the only
  workable path. Recorded the choice in the Decision Log; a
  later refactor could move the integration-style specs into a
  third package to deduplicate, but that is out of scope for
  EP-34.


## Decision Log

Record every decision made while working on the plan.

- Decision: Pick the loan-underwriting domain over customer-
  loyalty for the worked example.
  Rationale: the loan-underwriting state machine *naturally*
  exercises multi-field threshold guards (credit score ∧
  employment verified ∧ amount ≤ creditworthiness), ε-edges (a
  doc submission that internally trips the "ready for review"
  threshold without surfacing a public event), and per-vertex
  View variance (Drafting vs. Approved expose different live
  slots) — each of which is currently *not* exercised by any
  existing example. Loyalty would force these features rather
  than discover them from the domain. Evidence is the feature-
  fit comparison done in the conversation that initiated this
  plan.
  Date: 2026-05-03

- Decision: Model the workflow as three aggregates composed
  sequentially via `Keiki.Composition.compose`, mirroring the
  microtan AgentQualification → QualifiedAgent → LegacyQaCreator
  Process pattern.
  Rationale: the user's stated motivation is to provide a
  migration reference for moving Decider/Process code to keiki.
  The shape that matters is "an aggregate emits a state-change
  event → a process manager subscribes and emits a creation
  command → a downstream aggregate is created → a Process drives
  an external/legacy sync". `compose` is the only combinator
  whose shape (t1's output type = t2's input type) matches a
  process-manager pipeline; the production code at
  `/Users/shinzui/Keikaku/work/microtan/mls-service-v2-master/mls-service-v2-core/src/MlsService/LegacyQaCreator/Process.hs`
  pairs request/completion events with a list-of-actions
  register, an idempotency mechanism that maps onto a keiki
  register-file slot updated under copyless discipline.
  Date: 2026-05-03

- Decision: Author both a builder-form and an AST-form of the
  `LoanApplication` transducer, asserting byte-identical replay
  agreement in a dedicated spec.
  Rationale: this is the convention established by
  `UserRegistration` and `OrderCart`; deviating from it without
  cause would weaken the AST-drop-down guarantee documented in
  `docs/guide/ast-drop-down.md`. The smaller `Loan` and
  `CoreBankingSync` modules will not need an AST form.
  Date: 2026-05-03

- Decision: Disjoint slot names across all three aggregates by
  prefixing each register file with the aggregate name (e.g.
  `appApplicantId`, `loanPrincipal`, `syncPendingLoanId`).
  Rationale: `Keiki.Composition.compose` requires
  `Disjoint (Names rs1) (Names rs2)` at the type level. A name
  collision is a compile error; the prefix convention is the
  cheapest way to satisfy it for a three-way `Append`.
  Date: 2026-05-03

- Decision: Use plain `Int` for the loan's monetary, basis-
  points, and credit-score slots rather than introducing
  newtypes.
  Rationale: keeps `Keiki.Symbolic`'s `Sym` instance happy
  (curated set is `Bool`, `Int`, `Integer`, `Text`, `UTCTime`)
  so `isSingleValuedSym` works without adding a `Sym` instance
  for each newtype wrapper. Newtypes can be added later if a
  follow-up plan demands them; the tutorial's pedagogical value
  is unaffected.
  Date: 2026-05-03

- Decision: Split out a separate `jitsurei` package for *all*
  examples (existing + new) instead of adding the new example to
  `keiki`'s `Keiki.Examples.*` namespace.
  Rationale: the existing `keiki.cabal` exposes ~1700 lines of
  example modules in the library's public surface
  (`UserRegistration`, `UserRegistrationV0`, `OrderCart`,
  `EmailDelivery`), which means every downstream consumer pays
  for them in compilation and pollutes its module namespace.
  The standard Haskell pattern for libraries with substantial
  cookbook code is a sibling package (`lens-examples`,
  `servant-examples`); adopting it now (rather than only for the
  new example) avoids permanent inconsistency between "old
  examples in keiki, new examples in jitsurei" and surfaces the
  multi-package layout's friction *now* rather than during a
  later follow-up. The user's motivation also includes giving
  Decider/Process migrants something they can `cabal get` and
  fork from; a focused `jitsurei` package serves that better
  than a buried library subdirectory.
  Date: 2026-05-03

- Decision: Name the new package `jitsurei` (実例).
  Rationale: 実例 = "concrete example, real-world case" — the
  exact thing the package contains. Parallels the
  Japanese-noun naming aesthetic of `keiki` itself (継起 =
  "successive occurrence"), which the project's README
  explicitly establishes.
  Date: 2026-05-03

- Decision: Split `test/Keiki/Render/MermaidSpec.hs` between the
  two test suites: keep a small synthetic-fixture renderer test
  in `keiki-test` (so `keiki-test` does not depend on
  `jitsurei`) and move the example-driven golden tests to
  `jitsurei-test` as `Jitsurei.Render.MermaidExamplesSpec`.
  Rationale: avoiding a `keiki-test → jitsurei` build dependency
  preserves the layering (the core's tests do not depend on the
  examples package) and keeps `cabal test keiki-test` runnable
  in isolation.
  Date: 2026-05-03

- Decision: Move the `tasty-bench` benchmark wholesale into
  `jitsurei` rather than keeping a benchmark stanza in `keiki`.
  Rationale: the bench file imports `OrderCart` and
  `UserRegistration` directly. Moving it into `jitsurei`
  preserves the import chain without requiring a `keiki`-side
  benchmark to depend on `jitsurei`.
  Date: 2026-05-03

- Decision: Rename the @Drafting@ vertex to @Intake@.
  Rationale: 'deriveView' rejects vertex spec lists in which two
  constructor names produce the same field-name prefix
  (@map toLower . filter isUpper@), and both @Drafting@ and
  @Declined@ produce @"d"@. The compile error is
  @"deriveView: vertices { \"Drafting\", \"Declined\" } produce
  the same field-name prefix \"d\"; rename one"@. @Intake@ has
  prefix @"i"@, is a domain-correct loan-ops term for the start-
  of-flow vertex, and is single-syllable. The plan's Purpose
  / Big Picture section's vertex list still reads correctly
  because @Intake@ is the natural rename target. All
  references to @Drafting@ in this plan and its tutorial
  outline are read as referring to @Intake@.
  Date: 2026-05-03

- Decision: Implement the "ready for review" transition as
  @onCmd inCtorContinue@ + @noEmit@ rather than as @onEpsilon@.
  Rationale: a true 'onEpsilon' edge in 'CollectingDocuments'
  has no input-ctor match, so its register-only guard
  ('readyForReviewGuard') is satisfied by any input whenever
  the regs meet the threshold. That overlaps with the five
  evidence-collection edges (each gated by an 'inCtor' match)
  whenever the threshold-met regs are reached during a non-
  Continue command. 'delta' returns 'Nothing' on the
  ambiguity, and 'isSingleValuedSym' reports the transducer as
  not single-valued. Modelling the transition as @onCmd
  inCtorContinue@ + @noEmit@ keeps the *intent* (no public
  event, fires when thresholds are met, mirrors the production
  AgentQualification @AgentQualified@ silent advance) while
  the inCtor guard keeps it disjoint from the evidence-
  collection edges. This is the same pattern
  'Jitsurei.UserRegistration' uses for its GDPR-from-
  'RequiresConfirmation' silent deletion edge — @onCmd
  inCtorGdpr@ with @noEmit@. The tutorial calls the result an
  "ε-edge in the keiki sense (output is 'Nothing')" rather
  than "ε-edge in the FST sense (no input symbol)".
  Date: 2026-05-03

- Decision: Use @lit (read \"1970-01-01 00:00:00 UTC\" :: UTCTime)@
  as the @appDecidedAt@ literal on the Continue-driven approval
  / decline edges.
  Rationale: 'Continue' is a nullary command (its 'inpContinue'
  projection has type @Index '[] a@, which is uninhabited), so
  the edge cannot read a timestamp from the command payload. The
  pure transducer must therefore stamp the decision time from
  somewhere — either a register slot (which would require an
  extra command to seed) or a fixed sentinel literal. Choosing
  the epoch-zero literal keeps the pure layer total without
  inventing a slot whose only purpose is to feed Continue. The
  runtime adapter overrides the decided-at sentinel before
  emitting the public event downstream; the pure layer simply
  records that a decision was made. The tutorial calls this out
  in the Continue / MultiDecider section.
  Date: 2026-05-03

- Decision: Inline `EmailDelivery` and `UserRegistration` as
  test-only fixtures under `test/Keiki/Fixtures/` (modules
  `Keiki.Fixtures.EmailDelivery` and
  `Keiki.Fixtures.UserRegistration`) and rewrite the nine
  affected keiki-test specs to import the fixture modules.
  Rationale: cabal rejects a cyclic dependency between
  `keiki:test` and `jitsurei:lib` (see Surprises & Discoveries
  2026-05-03); the cycle is structural and not solvable by cabal
  config. The first-attempted fix — adding `jitsurei` to
  `keiki:test`'s `build-depends` — failed with `Cabal-7107`. The
  fallback is to duplicate the two example modules into
  test-scope and route the keiki-test specs at the duplicates.
  Cost: ~800 lines of one-time copy (UserRegistration 578 lines
  + EmailDelivery 223 lines) under `test/Keiki/Fixtures/`.
  Benefit: `keiki:test` is genuinely self-contained as M1's
  acceptance #11 demanded, and `git grep Keiki.Examples.`
  returns zero hits in live source / live docs (the only
  remaining matches are historical entries inside
  `docs/plans/*`, `docs/masterplans/*`, and a few research
  design notes that record the codebase state at the time they
  were written; those are frozen history).
  Date: 2026-05-03

- Decision: Defer pinning a `loanWorkflow` Mermaid golden until
  a 3-deep compose renderer ships; do not attempt to coerce one
  of the existing renderers.
  Rationale: re-checked the EP-30..EP-33 renderer landscape
  against `loanWorkflow`'s vertex type
  `Composite LoanAppVertex (Composite SyncVertex LoanVertex)`.
  None fits: `toMermaidComposite` and `toMermaidCompositeNested`
  share a `compositeLabel` that calls `show` on each component
  and so emits whitespace inside the inner `Composite`'s
  identifier (e.g. `"Drafting_Composite SyncIdle LoanInitial"`),
  which Mermaid backends reject; `toMermaidFeedback1`'s
  destructuring shape (`Composite a (Composite b c)`) is right
  but its type signature forces outer s1 = inner-inner s1, the
  feedback-cascade invariant, which the loanWorkflow's three
  distinct vertex types do not satisfy. The smallest closing
  move is a sister to `feedback1Label` typed
  `Composite s1 (Composite s2 s3) -> Text` plus a
  `toMermaidCompose3` renderer; that is a renderer-package
  feature and belongs in a separate ExecPlan, not under EP-34.
  An interim partial visualisation — `toMermaid loanApplication`
  + `toMermaidCompositeNested (coreBankingSync \`compose\` loan)`
  — is technically achievable today but pinning it in M6 would
  ship two diagrams that the tutorial would have to stitch
  together verbally; the pedagogical cost outweighs the gain
  for a plan whose primary deliverables (M2..M5 modules + M7
  tutorial) already shipped.
  Date: 2026-05-03

- Decision: Keep the `docs/guide/diagrams/loan-*.mmd` golden
  Mermaid files at the repository-root `docs/guide/diagrams/`
  path rather than under `jitsurei/docs/`.
  Rationale: the tutorial at
  `docs/guide/loan-application-tutorial.md` is also at the
  repository-root `docs/guide/`; co-locating the diagrams it
  embeds with the rest of the guide's diagrams (which already
  include `email-delivery.md` and `user-registration.md`) keeps
  the docs tree single-rooted and the tutorial's relative
  links flat.
  Date: 2026-05-03


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones
or at completion. Compare the result against the original purpose.

### Final state vs. Purpose

The Purpose section listed three deliverables. All three exist:

1. **Sibling `jitsurei` package.** `jitsurei/` has its own
   cabal file, exposes the four migrated examples plus the four
   new modules (`LoanApplication`, `Loan`, `CoreBankingSync`,
   `LoanWorkflow`), houses every spec for them, and ships the
   `tasty-bench` benchmark. `keiki.cabal` is correspondingly
   slimmer. `cabal build all` and `cabal test all` are green;
   the test summary prints two suites (`keiki-test` 144
   examples / 0 failures, `jitsurei-test` 102 examples / 0
   failures / 1 pending).
2. **The loan-underwriting trio.** `Jitsurei.LoanApplication`,
   `Jitsurei.Loan`, `Jitsurei.CoreBankingSync`, and
   `Jitsurei.LoanWorkflow` exist and exercise every feature the
   plan called out: multi-field threshold guards via
   `TApp1` / `TApp2`, ε-edges (`onCmd inCtorContinue` +
   `noEmit`), per-vertex View variance via `deriveView`,
   `MultiDecider` chains via `chainTo` and `DriverConfig`, and
   sequential `compose` of three aggregates.
3. **Tutorial walkthrough.** `docs/guide/loan-application-tutorial.md`
   walks the loan-application story end-to-end in eleven
   sections, introducing each new keiki construct as the
   domain demands it. `docs/guide/user-guide.md` §11 has a
   pointer to it.

### What changed during implementation

Three notable design adjustments emerged from running the
implementation against the formalism:

- **Vertex rename `Drafting → Intake`.** `deriveView`'s
  per-vertex prefix-uniqueness check rejects two constructors
  whose `filter isUpper >>> map toLower` share a prefix.
  `Drafting` and `Declined` collide on `"d"`. Renaming
  `Drafting → Intake` was the smallest fix; loan-ops
  terminology supports either name.
- **ε-edge keyed on `Continue` rather than `onEpsilon`.** A
  true `onEpsilon` edge in `CollectingDocuments` makes the
  vertex's outgoing-edge guards non-disjoint (the ε-edge
  fires on any input when the threshold guard happens to
  hold), so `delta` returns `Nothing` on every command at the
  threshold. Keying the silent transition on `Continue` (the
  internal-advancer command) restores disjointness while
  preserving the "no public event" pedagogy. The same
  pattern appears in
  `Jitsurei.UserRegistration`'s GDPR-from-`RequiresConfirmation`
  edge.
- **`compose`'s lockstep semantics vs. async cross-context
  flows.** `Keiki.Composition.compose t1 t2` produces a
  transducer whose every non-ε edge fires *both* legs
  simultaneously, but cross-context creation flows are
  inherently async (the legacy callback channel arrives on
  its own timeline). The composite definition in
  `Jitsurei.LoanWorkflow` is therefore type-correct but
  largely unfireable as a single-step driver; the M5 spec
  exercises each cross-context jump separately, mirroring
  what the runtime adapter does. The variance caveat is
  documented in the module haddock and in the tutorial.

### One known-pending item

`Jitsurei.LoanApplicationSymbolicSpec` is `pendingWith` a
documented reason: `TApp1` / `TApp2` over arbitrary Haskell
functions translate to fresh anonymous SBV variables, so
identical sub-predicates (`approvalGuard ∧ PNot approvalGuard`)
look distinct symbolically. Un-pending requires either a
memoising translator that recognises identical `TApp1`
sub-terms or extending `HsPred` with a comparison constructor;
both are out of EP-34's scope. `Jitsurei.UserRegistration`'s
symbolic spec remains green, so the gate is still meaningful
where guards do not need `TApp1`.

### Lessons for future plans

1. **Survey the test surface, not just the source surface,
   when splitting packages.** M1's "keiki-test self-contained"
   acceptance assumed only the example specs touched the
   examples. In fact nine more keiki-test specs use
   `Keiki.Examples.*` as fixtures. The mitigation (inlining
   `test/Keiki/Fixtures/EmailDelivery.hs` and
   `test/Keiki/Fixtures/UserRegistration.hs`) duplicates ~800
   lines but preserves the layering. A future package split
   should grep for fixture imports across the entire test
   tree before declaring scope.
2. **Lockstep `compose` is not the right combinator for
   async cross-context flows.** The plan envisaged
   `LoanApplication ⨾ CoreBankingSync ⨾ Loan` as a meaningful
   single-step composite. In practice, the natural runtime
   choreography is "observe upstream event, then issue
   downstream command in a separate transactional step,"
   which `compose`'s lockstep semantics cannot express. The
   composite is still useful as a type-level wiring diagram;
   the spec's responsibility is to drive each stage
   separately and verify the adapter functions agree at the
   boundaries.
3. **`HsPred` lacks comparison constructors.** Multi-field
   threshold guards (`x >= 650`) compile via `TApp1` lifts,
   but the SBV backend then loses track of identity across
   call sites. Adding `PCompare` to `HsPred` would unlock
   `isSingleValuedSym` for arbitrary numerical guards. A
   tracked follow-up after EP-34.

4. **Mermaid renderer suite is shaped for 1- and 2-deep
   composites only.** EP-30..EP-33 cover single transducers,
   2-deep flat / nested composites, the parallel `alternative`
   layout, and the feedback-typed 3-deep
   `Composite s1 (Composite s2 s1)`. None fits a right-
   associative 3-deep `compose` over three *distinct* vertex
   types, which is exactly the `loanWorkflow` shape and —
   plausibly — the shape of any future "aggregate ⨾ process ⨾
   downstream-aggregate" worked example modelled on the
   microtan production pattern. Closing the gap is a small
   addition (sister label to `feedback1Label`, sister renderer
   to `toMermaidFeedback1`) but it is a renderer-package
   feature and is tracked as a follow-up plan rather than
   tacked onto EP-34.

### Follow-ups

Tracked work that EP-34 surfaced but explicitly defers:

- ~~**3-deep compose renderer.** Add a
  `toMermaidCompose3 :: SymTransducer … (Composite s1
  (Composite s2 s3)) ci co -> Text` (with a sister
  `compose3Label`) to `Keiki.Render.Mermaid` and pin a
  `loan-workflow.mmd` golden in `Jitsurei.Render.MermaidLoanSpec`.
  Source of truth: the 2026-05-03 Decision Log entry on the
  renderer landscape. Likely a single-milestone EP that lands
  alongside other renderer additions in MasterPlan-10's
  follow-up phase.~~ — **Closed 2026-05-04 by EP-35**
  (`docs/plans/35-mermaid-renderer-for-right-associative-3-deep-compose-composites.md`).
  EP-35 shipped both `toMermaidCompose3` (flat) and
  `toMermaidCompose3Nested` (one-level nested), pinned the
  loanWorkflow composite via both renderers in
  `Jitsurei.Render.MermaidLoanSpec`, and added
  `loan-workflow.mmd` / `loan-workflow-nested.mmd` under
  `docs/guide/diagrams/`.
- **Symbolic single-valuedness for `loanApplication`.**
  Un-pend `Jitsurei.LoanApplicationSymbolicSpec` once `HsPred`
  gains comparison constructors or `Keiki.Symbolic` learns to
  memoise `TApp1` / `TApp2` translations. See "Lessons for
  future plans" point 3.


## Context and Orientation

This plan adds new content to a Haskell library that already
contains substantial code. A novice picking up this plan should
read the files named below before editing anything. Every term-of-
art used later in the plan is defined here.

### What the keiki library is

`keiki` is a Haskell library at the repository root
(`/Users/shinzui/Keikaku/bokuno/keiki/`) that supplies the *pure*
core of an event-sourcing / workflow / durable-execution system.
Its distinguishing claim is that one mathematical object — a
**symbolic-register transducer** — is the source of truth, and the
event-sourcing surface (the `decide` / `evolve` / `initialState` /
`isTerminal` four-field record introduced by Jérémie Chassaing as
the Decider) is *derived* from it. Throughout this plan:

- A **transducer** is an automaton with both an input alphabet
  and an output alphabet. Each transition has a label of the
  form `(input → output)` rather than just `input`. In keiki the
  input alphabet is a sum type of *commands* (`ci`) and the
  output alphabet is a sum type of *events* (`co`).
- A **vertex** is a control state. Vertices form a finite graph
  (`Bounded`, `Enum`).
- The **register file** (type `RegFile rs`) is a typed
  heterogeneous tuple indexed by a slot list `rs ::
  [(Symbol, Type)]`. It is the data the transducer remembers
  between transitions; the *full* state at any moment is the
  pair `(vertex, RegFile)`.
- An **edge** has four fields: a guard (a predicate over
  registers and the current command), an update (writes to
  register slots), an output (an event, or `Nothing` for a
  silent transition), and a target vertex.
- An **ε-edge** (epsilon edge / silent transition) is an edge
  whose output is `Nothing`. Through the Decider façade
  (`decide`) it returns `[]` instead of a singleton event list.
- The library types its predicates by a *carrier* parameter
  `phi`. v1 ships two carriers: `HsPred` (concrete-evaluated by
  `evalPred`, no solver) and `SymPred` (SBV-backed; routes
  `sat`/`isBot` through z3 for symbolic analyses). The
  transducer type is `SymTransducer phi rs s ci co`.
- A **process manager** in this library is a transducer whose
  input alphabet is *events* from one bounded context and whose
  output is *commands* to another. The same formalism as a
  single aggregate; what changes is the alphabet semantics.

### Current package layout (before M1)

The repository today is a single Haskell package:

- Root `cabal.project` with `packages: .`.
- `keiki.cabal` with three stanzas: `library` (the core +
  examples), `test-suite keiki-test` (one hspec entry-point at
  `test/Spec.hs`), and a `tasty-bench` benchmark stanza
  pointing at `bench/Bench.hs`.
- `flake.nix` exposing `haskellPackages.keiki` as
  `packages.default` and a devShell with z3 and
  cabal-install.

The `library` stanza's `exposed-modules` list ends with four
example modules — `Keiki.Examples.EmailDelivery`,
`Keiki.Examples.UserRegistration`,
`Keiki.Examples.UserRegistrationV0`, and
`Keiki.Examples.OrderCart` — totalling ~1700 lines. Removing
them is part of M1.

### Current package layout (after M1)

After M1 the repository becomes a two-package cabal project:

- Root `cabal.project` with `packages: ., jitsurei`.
- `keiki/` (the existing root, minus the moved example modules
  and the benchmark stanza) — the focused core library plus its
  own self-contained test suite.
- `jitsurei/` (new sibling package) — owns *all* worked
  examples and the `tasty-bench` benchmark.

The `jitsurei` package layout is:

    jitsurei/
    ├── jitsurei.cabal
    ├── src/Jitsurei/
    │   ├── EmailDelivery.hs            (migrated)
    │   ├── UserRegistration.hs         (migrated)
    │   ├── UserRegistrationV0.hs       (migrated)
    │   ├── OrderCart.hs                (migrated)
    │   ├── LoanApplication.hs          (M2)
    │   ├── Loan.hs                     (M4)
    │   ├── CoreBankingSync.hs          (M4)
    │   └── LoanWorkflow.hs             (M5)
    ├── test/
    │   ├── Spec.hs                     (hspec entry-point)
    │   └── Jitsurei/
    │       ├── EmailDeliveryBuilderSpec.hs   (migrated)
    │       ├── EmailDeliveryViewSpec.hs      (migrated)
    │       ├── OrderCartBuilderSpec.hs       (migrated)
    │       ├── OrderCartSpec.hs              (migrated)
    │       ├── UserRegistrationBuilderSpec.hs (migrated)
    │       ├── UserRegistrationChainedSpec.hs (migrated)
    │       ├── UserRegistrationMultiSpec.hs   (migrated)
    │       ├── UserRegistrationSpec.hs        (migrated)
    │       ├── UserRegistrationSymbolicSpec.hs(migrated)
    │       ├── UserRegistrationV0Spec.hs      (migrated)
    │       ├── UserRegistrationViewSpec.hs    (migrated)
    │       ├── LoanApplicationSpec.hs         (M2)
    │       ├── LoanApplicationBuilderSpec.hs  (M2)
    │       ├── LoanApplicationViewSpec.hs     (M2)
    │       ├── LoanApplicationSymbolicSpec.hs (M2/M3)
    │       ├── LoanApplicationChainedSpec.hs  (M3)
    │       ├── LoanApplicationMultiSpec.hs    (M3)
    │       ├── LoanSpec.hs                    (M4)
    │       ├── CoreBankingSyncSpec.hs         (M4)
    │       ├── LoanWorkflowSpec.hs            (M5)
    │       └── Render/
    │           ├── MermaidExamplesSpec.hs     (split out from
    │           │                              keiki-test M1)
    │           └── MermaidLoanSpec.hs         (M6)
    └── bench/                                  (migrated whole)
        ├── Bench.hs
        └── README.md

### `jitsurei.cabal` shape

The new `jitsurei.cabal` declares:

- `library` exposing `Jitsurei.EmailDelivery`,
  `Jitsurei.UserRegistration`, `Jitsurei.UserRegistrationV0`,
  `Jitsurei.OrderCart` (after M1) plus `Jitsurei.LoanApplication`,
  `Jitsurei.Loan`, `Jitsurei.CoreBankingSync`,
  `Jitsurei.LoanWorkflow` (added across M2..M5).
  `build-depends: base, keiki, text, time, sbv` (sbv is needed
  by aggregates that derive `KnownInCtors` and use the symbolic
  surface).
- `test-suite jitsurei-test` (hspec, exitcode-stdio-1.0) at
  `jitsurei/test/Spec.hs` listing all per-module specs in
  `other-modules`. `build-depends: base, hspec, keiki,
  jitsurei`.
- `benchmark keiki-bench` (tasty-bench) at
  `jitsurei/bench/Bench.hs`. `build-depends: base, tasty-bench,
  text, time, keiki, jitsurei`.

`shared-extensions` and `warnings` blocks are duplicated from
`keiki.cabal` to keep both packages on the same default
extensions set.

### `keiki.cabal` after M1

After M1, `keiki.cabal` shrinks:

- `library.exposed-modules` no longer includes any
  `Keiki.Examples.*` entry.
- `keiki-test.other-modules` no longer includes any
  `Keiki.Examples.*Spec` entry; the renderer spec is replaced
  by a small synthetic-toy version that does not depend on
  example aggregates.
- The `benchmark keiki-bench` stanza is removed.

### Existing examples to study before authoring

These are the *current* file paths (before M1). After M1 they
move under `jitsurei/src/Jitsurei/` with the same module
contents and renamed top-line `module` declaration.

- `src/Keiki/Examples/UserRegistration.hs` (578 lines) — the
  canonical five-vertex / four-command example. Demonstrates
  builder + AST forms, ε-edges (the GDPR-before-confirmation
  silent transition), `B.chainTo`, MultiDecider configuration,
  and `deriveView`. The tutorial-side reference inside this
  plan borrows its module structure verbatim.
- `src/Keiki/Examples/OrderCart.hs` (673 lines) — eight
  vertices, ten commands, demonstrates register arithmetic
  (`TApp1 (+1)`), multi-edge dispatch, and explicitly *opts
  out* of SBV-backed symbolic analysis because its slots use
  uncurated `Word*` types. Worth reading for the lifecycle-
  shaped state machine.
- `src/Keiki/Examples/EmailDelivery.hs` (223 lines) — the
  smallest useful aggregate. Two vertices, one command, one
  event. Referenced by the existing
  `docs/guide/user-guide.md` §2 ("Quick start") as the warm-up.
- `src/Keiki/Examples/UserRegistrationV0.hs` (252 lines) — the
  "unfixed" hidden-input demo for the schema-evolution story.

### Library modules that the new code will reach for

These remain in the `keiki` package after M1; `jitsurei` simply
imports them.

- `src/Keiki/Core.hs` (901 lines) — `SymTransducer`, `Edge`,
  `RegFile`, `Term`, `HsPred`, `Update`, `OPack`, `OutFields`,
  `delta`, `omega`, `step`, `applyEvent`, `reconstitute`,
  `solveOutput`, `checkHiddenInputs`. Read the haddock once
  before M2.
- `src/Keiki/Builder.hs` (880 lines) — the indexed-monad DSL
  (`buildTransducer`, `from`, `onCmd`, `onEpsilon`, `slot`,
  `(.=)`, `requireEq`, `requireGuard`, `emit`, `emitWith`,
  `noEmit`, `goto`, `chainTo`). Imported as `import qualified
  Keiki.Builder as B` and `import Keiki.Builder ((.=))`.
- `src/Keiki/Decider.hs` (211 lines) — `Decider`, `toDecider`,
  `MultiDecider`, `toMultiDecider`, `DriverConfig`. The
  `DriverConfig` newtype has the single field
  `isInternal :: s -> Maybe ci` that names the command used to
  auto-advance an internal vertex.
- `src/Keiki/Acceptor.hs` (159 lines) — `inputAcceptor`,
  `outputAcceptor`, `Acceptor`, `accepts`, `runAcceptor`.
- `src/Keiki/Composition.hs` (949 lines) — `compose`,
  `alternative`, `feedback1`, `Composite`. The signature
  relevant here is

      compose
        :: ( WeakenR rs1
           , Disjoint (Names rs1) (Names rs2)
           )
        => SymTransducer (HsPred rs1 ci1) rs1 s1 ci1 mid
        -> SymTransducer (HsPred rs2 mid) rs2 s2 mid co
        -> SymTransducer (HsPred (Append rs1 rs2) ci1)
                         (Append rs1 rs2)
                         (Composite s1 s2)
                         ci1
                         co

  where `mid` is the *shared* alphabet — t1's output type must
  equal t2's input type. Two left-associative `compose` calls
  yield the three-way pipeline of M5.
- `src/Keiki/Profunctor.hs` (350 lines) — `lmapMaybeCi`,
  `rmapCo`, `dimapTransducer`, `SomeSymTransducer`. The
  `lmapMaybeCi` adapter is the bridge used in M5 to translate
  upstream events into downstream commands. Per
  `docs/guide/profunctor.md` it is forward-only — replay through
  the rewritten edges is lossy by documented contract.
- `src/Keiki/Generics.hs` and `src/Keiki/Generics/TH.hs` — the
  Template-Haskell splices `deriveAggregateCtors`,
  `deriveWireCtors`, `deriveView`. Each emits ~3–6
  declarations per constructor; without them every aggregate
  would carry ~14 hand-written `InCtor` / `WireCtor`
  definitions.
- `src/Keiki/Symbolic.hs` (584 lines) — `withSymPred`,
  `isSingleValuedSym`, `KnownInCtors`, `Sym`. The curated `Sym`
  registry is `Bool`, `Int`, `Integer`, `Text`, `UTCTime`. Slot
  types outside this registry break the SBV-backed analyses;
  `OrderCart` documents this in its module header.
- `src/Keiki/Render/Mermaid.hs` — `toMermaid`,
  `toMermaidComposite`, `toMermaidCompositeNested`,
  `toMermaidAlternative`, `toMermaidFeedback1`. All renderers
  require the vertex type to derive `Enum`, `Bounded`, `Show`.

### The pattern this plan mirrors

The production system at
`/Users/shinzui/Keikaku/work/microtan/mls-service-v2-master/`
runs a real-estate workflow that the user wants to migrate to
keiki:

- `mls-service-v2-core/src/MlsService/Domain/AgentQualification/`
  — the AgentQualification aggregate. An agent accumulates
  real-estate transactions per chapter; when volume × sides
  crosses a chapter-configured threshold the aggregate emits an
  `AgentQualified` event.
- `mls-service-v2-core/src/MlsService/Domain/QualifiedAgent/` —
  the downstream QualifiedAgent aggregate created on a *new*
  stream once the agent qualifies. Has its own immutable
  lifecycle; carries a `legacyQualifiedAgentId` slot that is
  unset at creation and later populated via
  `AssignLegacyQualifiedAgentIdV1`.
- `mls-service-v2-core/src/MlsService/Subscription/QualifiedAgentCreator/`
  — the subscription on `AgentQualified` that enqueues a
  creation message into the `qualified_agent_creation` PGMQ
  queue.
- `mls-service-v2-core/src/MlsService/Subscription/LegacyQaCreatorProcess.hs`
  (438 lines) — the subscription/handler wiring the legacy
  sync.
- `mls-service-v2-core/src/MlsService/LegacyQaCreator/Process.hs`
  (81 lines) — the *pure* `Process` data structure that drives
  the legacy sync side-effect lifecycle. Its shape is exactly
  four fields (`evolve`, `react`, `resume`, plus
  `initialState`/`isTerminal`):

      evolve s evt@(LegacyQaCreationRequestedV1 _) =
        s { actions = s.actions ++ [(evt, CreateLegacyQa …)] }
      evolve s (LegacyQaCreatedV1 d) =
        let isOursForQid (_, CreateLegacyQa p) =
              p.request.qualifiedAgentId == d.qualifiedAgentId
         in s { actions = filter (not . isOursForQid) s.actions }

  The idempotency mechanism is the *event-pair*: a request
  event appends an action to the pending list, and the matching
  completion event removes it. Replays are idempotent for free
  because each pending action has exactly one resolving event
  with a matching identifier. The natural-key the legacy
  service deduplicates on is the `qualifiedAgentId` typeid
  string.

The LoanApplication / Loan / CoreBankingSync trio added in
M2..M5 is the keiki-shaped equivalent. Names map as follows:

- AgentQualification → `Jitsurei.LoanApplication` (accumulates
  evidence until threshold met).
- `AgentQualified` event → `ApplicationApproved` event.
- QualifiedAgent → `Jitsurei.Loan` (downstream aggregate
  created on its own stream, carries an initially-unset legacy
  ID slot).
- LegacyQaCreator process → `Jitsurei.CoreBankingSync` (the
  Process that drives the legacy core-banking call and then
  issues `AssignLegacyLoanId` against the Loan aggregate).
- `legacyQualifiedAgentId` → `legacyLoanId`.
- `AssignLegacyQualifiedAgentIdV1` → `AssignLegacyLoanId`.

### The docs/guide convention

The existing tutorials live at:

- `docs/guide/user-guide.md` (~849 lines) — the action-
  oriented main guide. Walks `EmailDelivery` end-to-end in §2
  ("Quick start") in ~50 lines, then layers detail across
  §§3–10. Glossary at §10 defines every term used in the guide
  and in the haddocks. After M1 its `Keiki.Examples.X`
  references must become `Jitsurei.X`.
- `docs/guide/composition.md` — combinator-by-combinator
  reference; worked examples live in test specs, not in the
  guide.
- `docs/guide/symbolic-ci.md`, `docs/guide/profunctor.md`,
  `docs/guide/b-views.md`, `docs/guide/ast-drop-down.md`,
  `docs/guide/why-smt.md` — each a focused topic guide.
- `docs/guide/diagrams/` — short `.md` files that embed
  rendered Mermaid diagrams plus the `ghci` snippet to
  regenerate. After M1 the import lines in
  `email-delivery.md` and `user-registration.md` must
  reference `Jitsurei.X` instead of `Keiki.Examples.X`.

The new tutorial slots in alongside `composition.md` and
`b-views.md` as a topic guide, but its function is different
— it is a *narrative walkthrough of one extended example*
rather than a reference of one feature. The closest precedent
is `user-guide.md`'s §2 "Quick start", scaled up to a multi-
aggregate workflow. The tutorial should cross-reference
`user-guide.md` for primitives the reader already knows and
only re-explain things the new domain introduces.


## Plan of Work

The work is organised as seven milestones. Each is independently
verifiable; each leaves the codebase in a state where
`cabal build all` and `cabal test all` succeed. M1 restructures
the package layout *without* changing module behaviour
(everything moves but every test still passes). M2..M6 produce
production code under `jitsurei/src/Jitsurei/` plus the
corresponding test specs; M7 produces the tutorial document. The
order is forced by data dependencies.

### Milestone M1 — Split out `jitsurei` package; migrate all examples

Scope: introduce the second package, move every existing example
module + its tests + the benchmark into it, slim `keiki.cabal`
correspondingly, and update every cross-reference (haddock
comments, doc tree, flake) so the rename propagates fully. No
behaviour changes — every existing test still passes, every
existing benchmark still runs, every existing renderer golden
still matches.

Sub-steps:

1. **Create the directory layout.**

       mkdir -p jitsurei/src/Jitsurei
       mkdir -p jitsurei/test/Jitsurei/Render
       mkdir -p jitsurei/bench

2. **Author `jitsurei/jitsurei.cabal`.** Mirror `keiki.cabal`'s
   warnings/extensions blocks. Three stanzas: `library`,
   `test-suite jitsurei-test`, `benchmark keiki-bench` (keep
   the existing benchmark name so any external dashboards keep
   matching). The `library` stanza exposes the four migrated
   modules; M2..M5 will append four more. `build-depends`
   includes `keiki` (path-relative via the cabal.project).

3. **Update root `cabal.project`** from `packages: .` to:

       packages: .
                 jitsurei

       with-compiler: ghc-9.12.3

4. **Move and rename example modules** (one `git mv` per file
   plus a single-line module-declaration edit at the top):

       git mv src/Keiki/Examples/EmailDelivery.hs       jitsurei/src/Jitsurei/EmailDelivery.hs
       git mv src/Keiki/Examples/UserRegistration.hs    jitsurei/src/Jitsurei/UserRegistration.hs
       git mv src/Keiki/Examples/UserRegistrationV0.hs  jitsurei/src/Jitsurei/UserRegistrationV0.hs
       git mv src/Keiki/Examples/OrderCart.hs           jitsurei/src/Jitsurei/OrderCart.hs

   In each moved file replace `module Keiki.Examples.X` with
   `module Jitsurei.X` and remove `src/Keiki/Examples/` if
   empty.

5. **Move and rename test specs** (eleven files):

       git mv test/Keiki/Examples/EmailDeliveryBuilderSpec.hs       jitsurei/test/Jitsurei/EmailDeliveryBuilderSpec.hs
       git mv test/Keiki/Examples/EmailDeliveryViewSpec.hs          jitsurei/test/Jitsurei/EmailDeliveryViewSpec.hs
       git mv test/Keiki/Examples/OrderCartBuilderSpec.hs           jitsurei/test/Jitsurei/OrderCartBuilderSpec.hs
       git mv test/Keiki/Examples/OrderCartSpec.hs                  jitsurei/test/Jitsurei/OrderCartSpec.hs
       git mv test/Keiki/Examples/UserRegistrationBuilderSpec.hs    jitsurei/test/Jitsurei/UserRegistrationBuilderSpec.hs
       git mv test/Keiki/Examples/UserRegistrationChainedSpec.hs    jitsurei/test/Jitsurei/UserRegistrationChainedSpec.hs
       git mv test/Keiki/Examples/UserRegistrationMultiSpec.hs      jitsurei/test/Jitsurei/UserRegistrationMultiSpec.hs
       git mv test/Keiki/Examples/UserRegistrationSpec.hs           jitsurei/test/Jitsurei/UserRegistrationSpec.hs
       git mv test/Keiki/Examples/UserRegistrationSymbolicSpec.hs   jitsurei/test/Jitsurei/UserRegistrationSymbolicSpec.hs
       git mv test/Keiki/Examples/UserRegistrationV0Spec.hs         jitsurei/test/Jitsurei/UserRegistrationV0Spec.hs
       git mv test/Keiki/Examples/UserRegistrationViewSpec.hs       jitsurei/test/Jitsurei/UserRegistrationViewSpec.hs

   In each moved spec:
   - Replace the top-line `module Keiki.Examples.XSpec` with
     `module Jitsurei.XSpec`.
   - Replace `import Keiki.Examples.X` with `import
     Jitsurei.X`.
   - Replace any `import Keiki.Examples.OtherSpec` (cross-
     spec imports — see UserRegistrationChainedSpec /
     OrderCartBuilderSpec for examples) with the new
     `import Jitsurei.OtherSpec`.

6. **Move the benchmark** wholesale:

       git mv bench/Bench.hs   jitsurei/bench/Bench.hs
       git mv bench/README.md  jitsurei/bench/README.md
       rmdir bench   # only if empty

   In `jitsurei/bench/Bench.hs` replace
   `import qualified Keiki.Examples.OrderCart as OC` and
   `import qualified Keiki.Examples.UserRegistration as UR`
   with the `Jitsurei.*` paths.

7. **Author `jitsurei/test/Spec.hs`.** Pattern the file after
   `keiki`'s current `test/Spec.hs`: import every per-module
   `Spec` and call `hspec . sequence_ . map describe` over
   them, one `describe` block per spec. Names exactly match the
   `other-modules` list in `jitsurei.cabal`'s `test-suite
   jitsurei-test`.

8. **Slim `keiki.cabal`.**

   - Remove the four `Keiki.Examples.*` entries from
     `library.exposed-modules`.
   - Remove every `Keiki.Examples.*Spec` entry from
     `keiki-test.other-modules`.
   - Remove the entire `benchmark keiki-bench` stanza.

9. **Slim `test/Spec.hs`.** Remove the `import` and `describe`
   call for each moved spec.

10. **Split `test/Keiki/Render/MermaidSpec.hs`.**

    The existing renderer spec depends on
    `Keiki.Examples.UserRegistration.userReg`,
    `Keiki.Examples.EmailDelivery.emailDelivery`, and the
    `alertSource` / `pinger` / `toggleAgg` / `togglePolicy`
    fixtures from `test/Keiki/CompositionSpec.hs`,
    `test/Keiki/CompositionAlternativeSpec.hs`,
    `test/Keiki/CompositionFeedback1Spec.hs`. The
    composition-spec fixtures are genuinely renderer-internal
    test fixtures — they stay in `keiki-test`. The example-
    aggregate fixtures are not, so:

    - Create `jitsurei/test/Jitsurei/Render/MermaidExamplesSpec.hs`.
      It owns the two `it` blocks that consume `userReg` and
      `emailDelivery` (the EP-30 single-aggregate test, and the
      EP-31/EP-32 composite test that composes
      `Keiki.CompositionSpec.alertSource` with
      `emailDelivery`). The composition fixtures must be
      lifted out of `keiki-test` into a sharable place; the
      cleanest is to add a tiny `Jitsurei.Render.Fixtures`
      module under `jitsurei/src/Jitsurei/Render/Fixtures.hs`
      that re-defines `alertSource` (it's only ~100 lines and
      uses `EmailDelivery`'s alphabet, so it belongs near the
      examples package anyway). Then the new spec imports
      `Jitsurei.Render.Fixtures (alertSource)`.

    - Replace `test/Keiki/Render/MermaidSpec.hs`'s body with a
      *synthetic* 2-vertex toy fixture (call it `tinyToy`)
      defined inline. The toy's role is to assert the renderer
      produces the expected `stateDiagram-v2` envelope — not to
      validate a real aggregate's diagram. Two tests are
      enough: a single-transducer render and a composite
      render via `compose tinyToy tinyToy2`. Remove the
      example-driven `it` blocks; leave the alternative /
      feedback1 / nested-composite tests in place if they only
      use the composition-spec fixtures (they do).

11. **Update `flake.nix`.** Add `jitsurei` to the `packages`
    block:

        packages = {
          default  = haskellPackages.keiki;
          jitsurei = haskellPackages.jitsurei;
        };

    The devShell does not need changes — `cabal build all`
    handles both packages.

12. **Update doc cross-references.** Search and replace
    `Keiki.Examples.X` → `Jitsurei.X` in:

    - `docs/research/effects-boundary.md`
    - `docs/research/multi-decider-via-state-refinement.md`
    - `docs/research/dsl-shape-for-symbolic-register.md`
    - `docs/research/edge-builder-dsl-shape.md`
    - `docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`
    - `docs/research/sbv-boolalg-design.md`
    - `docs/research/keiki-generics-design.md`
    - `docs/guide/user-guide.md`
    - `docs/guide/ast-drop-down.md`
    - `docs/guide/diagrams/email-delivery.md`
    - `docs/guide/diagrams/user-registration.md`

    The `ghci` snippets in the diagram pages must also have
    their `import` lines updated.

13. **Update the haddock cross-reference** in
    `src/Keiki/Generics/TH.hs:116` from `'Keiki.Examples.UserRegistration'`
    to `'Jitsurei.UserRegistration'`.

14. **Run the verification commands** below in the
    "Concrete Steps" section: `cabal build all` succeeds,
    `cabal test all` is green, `cabal bench
    jitsurei:keiki-bench --benchmark-options "--help"` shows
    the benchmark group list (we are not running benchmarks for
    timing in CI; just checking the binary builds and lists
    its groups).

Acceptance for M1: every previously-green test is still green;
the test summary shows two suites; the benchmark stanza builds;
the doc tree no longer mentions `Keiki.Examples.X`; `git grep
Keiki.Examples.` returns zero results across the whole
repository.

### Milestone M2 — `Jitsurei.LoanApplication` aggregate

Scope: build the rich LoanApplication aggregate end-to-end in
both builder and AST forms. By the end of M2 the file
`jitsurei/src/Jitsurei/LoanApplication.hs` exists,
`jitsurei.cabal` exposes it, and the test suite contains four
new specs that all pass.

Sub-steps (mirror the file structure of the migrated
`jitsurei/src/Jitsurei/UserRegistration.hs`):

1. **Module skeleton.** Create
   `jitsurei/src/Jitsurei/LoanApplication.hs` with a header
   comment that links to this plan, lists the *exposed* names,
   and explains the design choices (multi-field threshold
   guards, ε-edges for "ready for review" promotion, per-
   vertex View variance). Append the module to
   `jitsurei.cabal`'s `library.exposed-modules` list
   immediately after `Jitsurei.UserRegistrationV0`.

2. **Domain types.** Define `LoanCmd` with the following
   constructors and per-constructor record payloads:

   - `StartApplication { applicantId :: Text, requestedAmount
     :: Int, purpose :: Text, at :: UTCTime }`
   - `SubmitIncomeDocument { docRef :: Text, at :: UTCTime }`
   - `SubmitIdDocument { docRef :: Text, at :: UTCTime }`
   - `RecordCreditScore { score :: Int, at :: UTCTime }`
   - `RecordEmploymentCheck { verified :: Bool, at :: UTCTime }`
   - `WithdrawApplication { reason :: Text, at :: UTCTime }`
   - `Continue` (nullary; the internal advancer used by
     `chainTo` and `MultiDecider`).

   Define `LoanEvent` with one constructor per event:

   - `ApplicationStarted { applicantId, requestedAmount,
     purpose, at }`
   - `IncomeDocumentReceived { docRef, at }`
   - `IdDocumentReceived { docRef, at }`
   - `CreditScoreRecorded { score, at }`
   - `EmploymentChecked { verified, at }`
   - `ReadyForReview { at }` (emitted by the multi-event chain
     when thresholds are first met)
   - `ApplicationApproved { applicantId, requestedAmount,
     creditScore :: Int, at }`
   - `ApplicationDeclined { applicantId, reason :: Text, at }`
   - `ApplicationWithdrawn { applicantId, reason, at }`

   Each payload record gets `Generic`, `Eq`, `Show`. Type
   aliases `Money = Int` and `BasisPoints = Int` may be
   introduced for readability — keep the underlying `Int` so
   the curated `Sym` instance remains valid.

3. **Register file.**

       type LoanAppRegs =
         '[ '("appApplicantId",        Text)
          , '("appRequestedAmount",    Int)
          , '("appPurpose",            Text)
          , '("appIncomeDocCount",     Int)
          , '("appIdDocCount",         Int)
          , '("appCreditScore",        Int)
          , '("appEmploymentVerified", Bool)
          , '("appDecidedAt",          UTCTime)
          , '("appWithdrawnAt",        UTCTime)
          , '("appDeclineReason",      Text)
          ]

   The `app` prefix prevents slot-name collisions with `Loan`'s
   `loan` prefix and `CoreBankingSync`'s `sync` prefix when the
   three are composed in M5.

4. **Vertex enum.**

       data LoanAppVertex
         = Drafting
         | CollectingDocuments
         | UnderReview
         | Approved
         | Declined
         | Withdrawn
         deriving (Eq, Show, Enum, Bounded)

5. **TH splices.** Splice `deriveAggregateCtors` for every
   `LoanCmd` constructor and `deriveWireCtors` for every
   `LoanEvent` constructor, using the same shorthand
   convention as UserRegistration (e.g. `("StartApplication",
   "Start")`).

6. **B-view splice.** Splice `deriveView` for `LoanAppVertex` /
   `LoanAppRegs` with per-vertex slot lists that genuinely
   vary:

       $(deriveView ''LoanAppVertex ''LoanAppRegs
           "SLoanAppVertex" "LoanAppView" "loanAppView"
           [ ("Drafting",            ["appApplicantId"])
           , ("CollectingDocuments",
                [ "appApplicantId", "appRequestedAmount", "appPurpose"
                , "appIncomeDocCount", "appIdDocCount" ])
           , ("UnderReview",
                [ "appApplicantId", "appRequestedAmount", "appPurpose"
                , "appCreditScore", "appEmploymentVerified" ])
           , ("Approved",
                [ "appApplicantId", "appRequestedAmount"
                , "appCreditScore", "appDecidedAt" ])
           , ("Declined",
                [ "appApplicantId", "appDeclineReason", "appDecidedAt" ])
           , ("Withdrawn",
                [ "appApplicantId", "appWithdrawnAt" ])
           ])

7. **Builder-form transducer `loanApplication`.** The body
   uses `Keiki.Builder` and follows this control flow:

   - `from Drafting`: `onCmd inCtorStart` writes
     `appApplicantId`, `appRequestedAmount`, `appPurpose`,
     emits `ApplicationStarted`, `goto CollectingDocuments`.
     Also `onCmd inCtorWithdraw` writes `appWithdrawnAt`,
     emits `ApplicationWithdrawn`, `goto Withdrawn`.

   - `from CollectingDocuments`: `onCmd
     inCtorSubmitIncomeDocument` bumps `appIncomeDocCount` via
     `TApp1 (+1) #appIncomeDocCount`, emits
     `IncomeDocumentReceived`, `goto CollectingDocuments`.
     Symmetric `onCmd inCtorSubmitIdDocument`. `onCmd
     inCtorRecordCreditScore` writes `appCreditScore`, emits
     `CreditScoreRecorded`, `goto CollectingDocuments`.
     Symmetric `onCmd inCtorRecordEmploymentCheck`. `onCmd
     inCtorWithdraw` identical to Drafting's withdrawal. **One
     ε-edge**: `onEpsilon`, `requireGuard` for
     `appIncomeDocCount >= 2 ∧ appIdDocCount >= 1 ∧
     creditScoreSet ∧ employmentVerifiedSet`, `noEmit`,
     `goto UnderReview`. The "set" predicates can be
     expressed as `requireGuard` calls over `HsPred`
     constructed by hand or via `TApp1 (/= 0)` on the count
     slots; resolve the exact form during implementation and
     record in the Decision Log.

   - `from UnderReview`: `onCmd inCtorWithdraw` (terminal).
     The approval/decline transition is driven by an explicit
     `Continue` command carrying `at` — two `onCmd
     inCtorContinue` edges with disjoint multi-field guards:
     - Approval: `appCreditScore >= 650 ∧
       appEmploymentVerified ∧
       appRequestedAmount <= maxApprovalForScore appCreditScore`.
       Writes `appDecidedAt`. Emits `ApplicationApproved`.
       `goto Approved`.
     - Decline: negation. Writes `appDeclineReason` and
       `appDecidedAt`. Emits `ApplicationDeclined`. `goto
       Declined`.

   - `from Approved`, `from Declined`, `from Withdrawn`:
     terminal, no `from` block needed (default to `[]`).

8. **AST-form transducer `loanApplicationAST`.** Hand-author
   the same edges against `Keiki.Core`'s AST. Keep the
   structure parallel to the builder form so the M2
   builder/AST equivalence spec is a one-shot replay over a
   canonical event log.

9. **Test specs.** Create the following four files under
   `jitsurei/test/Jitsurei/`. Each is appended to
   `jitsurei-test`'s `other-modules` list and pulled into
   `jitsurei/test/Spec.hs` with a `describe` block.

   - **`LoanApplicationSpec.hs`** — pure-core round-trips.
     Construct a canonical command log from `Drafting` to
     `Approved`. For each prefix, assert that
     `reconstitute loanApplication initialRegs (eventsFromPrefix)`
     ends in the expected vertex with the expected register
     contents.

   - **`LoanApplicationBuilderSpec.hs`** — builder/AST
     equivalence. For the canonical event log, assert
     `reconstitute loanApplication initialRegs evs ==
     reconstitute loanApplicationAST initialRegs evs` (both
     sides `Just` and equal). Pattern from
     `jitsurei/test/Jitsurei/UserRegistrationBuilderSpec.hs`.

   - **`LoanApplicationViewSpec.hs`** — B-view projection. For
     each vertex on the happy path, run the canonical prefix
     and assert `loanAppView SApproved regs` (etc.) returns a
     record with the correct selectors live. Pattern from
     `jitsurei/test/Jitsurei/UserRegistrationViewSpec.hs`.

   - **`LoanApplicationSymbolicSpec.hs`** —
     `isSingleValuedSym (withSymPred loanApplication)` is
     `True`. Requires the `KnownInCtors LoanCmd` instance from
     M3; until then, gate this spec with a `pendingWith
     "needs M3"`. Pattern from
     `jitsurei/test/Jitsurei/UserRegistrationSymbolicSpec.hs`.

10. **`KnownInCtors LoanCmd` instance.** Required by
    `isSingleValuedSym`'s witness reconstruction. Define inline
    in `LoanApplication.hs` after the TH splices, listing every
    `InCtor` value (one entry per `LoanCmd` constructor
    including `Continue`). Pattern from the migrated
    `Jitsurei.UserRegistration` (the original lives at
    `src/Keiki/Examples/UserRegistration.hs:231-238` before
    M1).

Acceptance for M2: `cabal build all` succeeds; `cabal test
all` prints the four new spec headings with all examples
passing; the four spec files are wired into
`jitsurei/test/Spec.hs` and `jitsurei.cabal`'s `other-modules`
list.

### Milestone M3 — MultiDecider chain for `Jitsurei.LoanApplication`

Scope: add the `loanApplicationDriverConfig` and a
`chainTo`-based form of the transducer that lets a single
command (e.g. `StartApplication`, when followed by an internal
`Continue`) produce multiple events end-to-end. Two new test
specs assert chained-form/letter-form equivalence and multi-
event behaviour.

Sub-steps:

1. **`loanApplicationDriverConfig :: DriverConfig
   LoanAppVertex LoanCmd`.** Mark `CollectingDocuments` and
   `UnderReview` as internal whenever their guards are about
   to fire; for the simpler MVP, mark them as internal
   unconditionally and have the driver use `Continue` to
   attempt the ε-edge transition. The ε-edge fires only when
   its guard holds, which is the natural "should we advance
   now" gate.

2. **`loanApplicationChained` builder-form** that uses
   `B.chainTo` for the multi-event chain
   `StartApplication`-then-`Continue`-then-`Continue` (the
   second `Continue` corresponds to the auto-advance at
   `UnderReview`). Mirrors `userRegChained` in the migrated
   `Jitsurei.UserRegistration`.

3. **`LoanApplicationChainedSpec`** asserts
   `reconstitute loanApplication initialRegs evs ==
   reconstitute loanApplicationChained initialRegs evs` for
   the canonical event log. Pattern from
   `jitsurei/test/Jitsurei/UserRegistrationChainedSpec.hs`.

4. **`LoanApplicationMultiSpec`** asserts that the multi-event
   façade produces the expected event sequence in one
   `decide` call when given a single `StartApplication`
   command on a fully-prepared register state. Pattern from
   `jitsurei/test/Jitsurei/UserRegistrationMultiSpec.hs`.

5. **Un-pend `LoanApplicationSymbolicSpec`** now that
   `KnownInCtors LoanCmd` is in scope.

Acceptance for M3: all M1+M2 specs still pass; the two new
chained / multi specs pass; the symbolic spec is no longer
pending.

### Milestone M4 — `Jitsurei.Loan` and `Jitsurei.CoreBankingSync`

Scope: introduce the downstream Loan aggregate (small, two-
state) and the CoreBankingSync Process (the cross-context
idempotent legacy-sync analogue). Each gets a dedicated spec.

Sub-steps:

1. **`jitsurei/src/Jitsurei/Loan.hs`.** Add to `jitsurei.cabal`
   `exposed-modules`.

   - Domain types `LoanCmd' = CreateLoan { … } |
     AssignLegacyLoanId { … }` and `LoanEvent' = LoanCreated
     { … } | LegacyLoanIdAssigned { … }`. Use a primed name
     so it does not clash with `LoanApplication`'s `LoanCmd` /
     `LoanEvent` if the reader imports both at once.

   - `type LoanRegs = '[ '("loanLoanId", Text),
     '("loanApplicantId", Text), '("loanPrincipal", Int),
     '("loanLegacyLoanId", Text) ]`.

   - `data LoanVertex = LoanInitial | LoanAwaiting |
     LoanLinked deriving (…, Enum, Bounded, Show)`.

   - Builder-form transducer `loan` with two transitions:
     `LoanInitial` → `LoanAwaiting` on `CreateLoan` (writes
     loan identity slots; emits `LoanCreated`); `LoanAwaiting`
     → `LoanLinked` on `AssignLegacyLoanId` (writes
     `loanLegacyLoanId`; emits `LegacyLoanIdAssigned`).

   - **No AST form**, **no B-view** (the lifecycle is too
     small to justify the boilerplate; explained in a header
     comment).

   - `KnownInCtors LoanCmd'` instance.

2. **`jitsurei/src/Jitsurei/CoreBankingSync.hs`.** Add to
   cabal.

   The Process aggregate's input alphabet is *events*.
   Specifically, it consumes `LoanEvent'` from the Loan stream
   and one synthetic event `LegacyCallbackReceived { loanId,
   legacyLoanId, at }` representing the asynchronous callback
   from the legacy core-banking system. Its output alphabet is
   `LoanCmd'` — when a callback arrives, the Process emits
   `AssignLegacyLoanId` to close the loop on the Loan
   aggregate.

   - Domain types `SyncInput = LoanCreatedIn { … } |
     LegacyCallbackReceivedIn { … }` and `SyncOutput =
     SyncToLegacyRequested { … } | LegacyAssignmentCommanded
     LoanCmd'`. The `LegacyAssignmentCommanded` constructor
     wraps a `LoanCmd'` so the Process's output type is
     composable with the Loan aggregate's input alphabet (for
     the M5 composition step).

   - `type SyncRegs = '[ '("syncPendingLoanId", Text),
     '("syncPendingApplicantId", Text), '("syncPendingPrincipal",
     Int) ]`.

   - `data SyncVertex = SyncIdle | SyncRequested | SyncSettled
     deriving (…, Enum, Bounded, Show)`. `SyncSettled` is
     terminal.

   - Builder-form transducer `coreBankingSync`:
     - `SyncIdle` `onCmd inCtorLoanCreatedIn`: writes the
       three pending slots, emits `SyncToLegacyRequested`,
       `goto SyncRequested`.
     - `SyncRequested` `onCmd inCtorLegacyCallbackReceivedIn`:
       requires `loanId == #syncPendingLoanId` (the natural
       idempotency key), emits `LegacyAssignmentCommanded`
       carrying an `AssignLegacyLoanId` command, `goto
       SyncSettled`.

   The pattern echoes the production `Process.evolve` shape:
   an inbound request event sets pending state; an inbound
   completion event (matching by ID) clears it. Replays are
   idempotent: any second `LegacyCallbackReceivedIn` for the
   same loan finds no matching pending state and is rejected
   by `delta` (returns `Nothing`).

3. **Test specs.**

   - **`LoanSpec.hs`** — round-trip on the two-event canonical
     log.

   - **`CoreBankingSyncSpec.hs`** — three scenarios:
     1. Happy path: `LoanCreatedIn` →
        `LegacyCallbackReceivedIn` produces the expected
        output sequence and ends in `SyncSettled`.
     2. Idempotent replay: appending a second
        `LegacyCallbackReceivedIn` returns `Nothing` from
        `delta` (the terminal vertex has no outgoing edges).
     3. Mismatched callback: a `LegacyCallbackReceivedIn`
        with a different loan ID returns `Nothing` from
        `delta` because the `requireEq` guard fails.

Acceptance for M4: `cabal test all` passes all M1..M3 specs
plus the two new ones.

### Milestone M5 — `Jitsurei.LoanWorkflow` (sequential composition)

Scope: wire `LoanApplication ⨾ CoreBankingSync ⨾ Loan` into
one composite aggregate using `Keiki.Composition.compose`.
Demonstrate that the composite's input is `LoanCmd` and its
output is `LoanEvent'` — i.e. a `StartApplication` command
flowing into the composite eventually produces a `LoanCreated`
(or `LegacyLoanIdAssigned`) event.

The composition must bridge type alphabets between adjacent
aggregates. `compose t1 t2` requires `t1`'s output type to
equal `t2`'s input type (the `mid` in the signature). Two
adapters are needed:

- LoanApplication outputs `LoanEvent`; CoreBankingSync inputs
  `SyncInput`. Use `Keiki.Profunctor.lmapMaybeCi` (forward-
  only, per `docs/guide/profunctor.md`) on `coreBankingSync`
  to translate `LoanEvent` into `SyncInput` (mapping
  `ApplicationApproved` → `LoanCreatedIn`, others → `Nothing`
  so unrelated upstream events do not advance the Process).

- CoreBankingSync outputs `SyncOutput`; Loan inputs `LoanCmd'`.
  Use `Keiki.Profunctor.lmapMaybeCi` on `loan` to extract the
  embedded `LoanCmd'` from `LegacyAssignmentCommanded` and
  ignore `SyncToLegacyRequested` (an audit event that does not
  directly drive Loan).

Sub-steps:

1. **`jitsurei/src/Jitsurei/LoanWorkflow.hs`.** Add to cabal.

   - `loanWorkflow :: SymTransducer …` defined as

         loanWorkflow =
           loanApplication
             `compose` lmapMaybeCi loanEventToSyncInput
                                   coreBankingSync
             `compose` lmapMaybeCi syncOutputToLoanCmd
                                   loan

     with the left-associativity made explicit by `let`
     bindings if readability suffers.

   - The two adapter functions are pure pattern matches over
     the event/command sums, returning `Maybe`.

2. **`LoanWorkflowSpec.hs`.** End-to-end smoke test: feed a
   sequence of `LoanCmd` commands that drive a successful
   loan application to `Approved`, observe the chain of
   outputs (one `SyncToLegacyRequested` after
   `ApplicationApproved`); then feed a synthesised
   `LegacyCallbackReceivedIn` (translated through the
   adapters) and observe the final `LegacyLoanIdAssigned`
   event. Keep the composite-vertex assertions narrow — we are
   testing the *pipeline*, not re-testing each aggregate.

3. **Note in module haddock**: the `lmapMaybeCi` adapters are
   forward-only; replay through the composite is not
   exercised by M5 (`docs/guide/profunctor.md` documents the
   variance caveat).

Acceptance for M5: `cabal test all` adds `LoanWorkflowSpec` to
the green list; the spec exercises a full happy-path
composition.

### Milestone M6 — Mermaid render + golden tests

Scope: render single-aggregate Mermaid diagrams for
`loanApplication`, `loan`, and `coreBankingSync`, and a
composite diagram for `loanWorkflow`. Pin the outputs as
golden tests in a new spec module; place the golden Mermaid
files under `docs/guide/diagrams/loan-*.mmd` for the tutorial
to embed.

Sub-steps:

1. **`jitsurei/test/Jitsurei/Render/MermaidLoanSpec.hs`.**
   Append to `jitsurei-test.other-modules`. Four `it` blocks:
   one per single aggregate calling `toMermaid`, and one for
   `loanWorkflow` calling `toMermaidComposite` (or
   `toMermaidCompositeNested` for the larger 6×3×3 product if
   `toMermaidComposite` produces an unreadable diagram).

2. **Golden files.** Write the expected Mermaid blocks as
   `Text` in `MermaidLoanSpec.hs` and *also* mirror them as
   `docs/guide/diagrams/loan-application.mmd`,
   `docs/guide/diagrams/loan.mmd`,
   `docs/guide/diagrams/core-banking-sync.mmd`,
   `docs/guide/diagrams/loan-workflow.mmd`. The tutorial in
   M7 embeds these via the standard Mermaid fenced-block
   convention.

Acceptance for M6: `cabal test all` adds four green tests;
the four `.mmd` files exist and contain valid
`stateDiagram-v2` blocks.

### Milestone M7 — Tutorial walkthrough

Scope: write `docs/guide/loan-application-tutorial.md` as an
incremental narrative walkthrough of the M2..M6 modules.

The tutorial follows a *motivated* structure — each new keiki
construct enters when the loan story has just made it
necessary. The chapter outline:

1. **What we are building.** A picture (the Mermaid diagram
   from M6) of the three-aggregate pipeline. One paragraph
   per aggregate describing what it does. A note on the
   production pattern this mirrors and why we are
   demonstrating it.

2. **Modelling the application aggregate.** Walk through the
   register file, vertex enum, and one straightforward edge
   (`StartApplication`). Reuses the four-layer authoring
   model from `user-guide.md` §3.

3. **Accumulating evidence.** Add the document-submission
   edges. Introduces register arithmetic via `TApp1 (+1)`.
   Cross-references `user-guide.md` §3.4 for `Term` syntax.

4. **An ε-edge for "ready for review".** Introduces ε-edges
   as the solution to "the doc count just crossed the
   threshold and the transition should fire silently".
   Cross-references `user-guide.md`'s §3.3 / §10.1 ε-edge
   entries.

5. **Multi-field threshold guards.** Introduces `requireGuard`
   over predicates compounding multiple register comparisons.
   The credit-score / employment / amount triple is the
   motivating example.

6. **Per-vertex View variance.** Introduces `deriveView`
   because Drafting and Approved expose genuinely different
   live data; pattern-matches on `loanAppView SApproved regs`
   to underline how the type system blocks reading slots that
   aren't live in that vertex. Cross-references
   `b-views.md`.

7. **Multi-event commands.** Introduces `chainTo`, the
   `MultiDecider` façade, and `DriverConfig` because a caller
   who issues `RecordEmploymentCheck` last reasonably expects
   "you have enough now, please advance" to happen in the
   same step.

8. **The downstream Loan aggregate.** Tiny by design.
   Establishes why we keep it as its own aggregate (different
   lifecycle, different consistency boundary, will eventually
   carry the legacy ID).

9. **The CoreBankingSync Process.** Introduces the process-
   manager shape (input alphabet = events, output alphabet =
   commands). Walks the legacy-call idempotency mechanism:
   pending state on request, cleared on matching callback.
   Cites the production pattern at the microtan path.

10. **Wiring it together with `compose`.** Introduces the
    composition combinator and the adapter functions. Shows
    the rendered composite diagram from M6 alongside the code.

11. **Where to go from here.** Pointers to `composition.md`
    for the alternative and feedback combinators,
    `symbolic-ci.md` for adding `isSingleValuedSym` to CI,
    and the synthesis doc for the formal foundation.

Sub-steps:

1. **Create the file** `docs/guide/loan-application-tutorial.md`.
   Open with a one-paragraph blurb mirroring `user-guide.md`'s
   opening; link to the foundations.

2. **Write each section.** Embed code excerpts from the actual
   M2..M6 modules using the fenced-code style of the existing
   guides. Embed the rendered diagrams as fenced ` ```mermaid `
   blocks referencing the `.mmd` golden files from M6 (or
   inlining their contents).

3. **Cross-reference from `docs/guide/user-guide.md` §11**
   ("Where to go from here"), adding a new bullet for the
   tutorial.

4. **Sanity-link check.** All cross-references — to other
   guides, to source files, to the synthesis doc — resolve to
   existing paths.

Acceptance for M7: the tutorial file exists, references valid
paths, and embeds working code excerpts that match the M2..M6
modules; the new bullet appears in `user-guide.md` §11.


## Concrete Steps

All commands run from `/Users/shinzui/Keikaku/bokuno/keiki/`.

### Build everything

    cabal build all

Expected tail of output on success (after M1, before M2):

    Resolving dependencies...
    Build profile: -w ghc-9.12.3 -O1
    In order, the following will be built (use -v for more details):
     - keiki-0.1.0.0 (lib) (configuration changed)
     - jitsurei-0.1.0.0 (lib) (first run)
     - keiki-0.1.0.0 (test:keiki-test) (configuration changed)
     - jitsurei-0.1.0.0 (test:jitsurei-test) (first run)
     - jitsurei-0.1.0.0 (bench:keiki-bench) (first run)
    [...]

### Run all test suites

    cabal test all --test-show-details=direct

Expected tail of output on success (after M7):

    Test suite keiki-test:           PASS  (smaller surface; renderer
                                            tests use synthetic toy
                                            fixtures; no Examples specs)
    Test suite jitsurei-test:        PASS
      Jitsurei.UserRegistration         (migrated)
      Jitsurei.UserRegistrationBuilder  (migrated)
      [... all 11 migrated specs ...]
      Jitsurei.LoanApplication
        reconstitute happy-path canonical log lands at Approved [✔]
        [...]
      Jitsurei.LoanApplicationBuilder   [...]
      Jitsurei.LoanApplicationView      [...]
      Jitsurei.LoanApplicationChained   [...]
      Jitsurei.LoanApplicationMulti     [...]
      Jitsurei.LoanApplicationSymbolic  [...]
      Jitsurei.Loan                     [...]
      Jitsurei.CoreBankingSync          duplicate callback rejected
                                        mismatched callback id rejected
      Jitsurei.LoanWorkflow             end-to-end LoanCmd → LegacyLoanIdAssigned
      Jitsurei.Render.MermaidExamples   (migrated golden tests)
      Jitsurei.Render.MermaidLoan       loan-* goldens

    Finished in <N>s
    NN examples, 0 failures

### Confirm the bench builds

    cabal bench jitsurei:keiki-bench --benchmark-options "--help"

Expected: prints the tasty-bench options and exits 0. We are
not measuring timings in this acceptance step; just confirming
the binary builds and links against the migrated example
modules.

### Render diagrams

The Mermaid golden files live under
`docs/guide/diagrams/loan-*.mmd`. View them with any Mermaid
renderer (e.g. the GitHub markdown preview, or `mmdc -i ... -o
...png` from the `@mermaid-js/mermaid-cli` package).

### Read the tutorial

Open `docs/guide/loan-application-tutorial.md` in any Markdown
viewer; cross-references to other guides resolve to relative
paths under `docs/guide/`.


## Validation and Acceptance

Acceptance is a green `cabal test all` plus visual inspection
of the tutorial document. Concretely:

1. **No leftover `Keiki.Examples.*` references after M1.**
   `git grep 'Keiki\.Examples\.'` returns zero hits across
   the whole repository tree.

2. **Two-package layout works.** `cabal build all` produces
   one library per package. `cabal repl jitsurei` gives a
   GHCi session with `Jitsurei.LoanApplication` (after M2) in
   scope.

3. **Compile-time disjointness check.** Removing the `app` /
   `loan` / `sync` slot prefixes (introducing a name clash)
   must produce a `TypeError` at the `compose` call site in
   `LoanWorkflow.hs`. The reader can verify this by
   temporarily renaming a slot and re-running `cabal build
   all`; the error message names the duplicated slot.

4. **Builder/AST agreement.** `cabal test jitsurei-test
   --test-options="--match \"LoanApplicationBuilder\""` must
   pass without examples being skipped. Failure here means
   the builder form and AST form have diverged, which usually
   points at a missed register write or a mis-ordered
   `OutFields` cons.

5. **Replay round-trip.** `cabal test jitsurei-test
   --test-options="--match \"LoanApplication \""` passes;
   this exercises `reconstitute` over every canonical prefix.

6. **Symbolic single-valuedness.** `cabal test jitsurei-test
   --test-options="--match \"LoanApplicationSymbolic\""`
   reports the assertion `isSingleValuedSym (withSymPred
   loanApplication) == True`. Requires the `z3` solver in
   `PATH`.

7. **Process idempotency.** `cabal test jitsurei-test
   --test-options="--match \"CoreBankingSync\""` exercises
   duplicate-callback and mismatched-id scenarios.

8. **End-to-end pipeline.** `cabal test jitsurei-test
   --test-options="--match \"LoanWorkflow\""` runs the
   composed pipeline on a representative `LoanCmd` sequence
   and asserts the final `LegacyLoanIdAssigned` event is
   produced.

9. **Mermaid golden tests.** `cabal test jitsurei-test
   --test-options="--match \"MermaidLoan\""` enforces that
   the rendered Mermaid blocks match the inline goldens; if
   the renderer changes, the goldens need to be updated
   together with the `.mmd` files referenced by the tutorial.

10. **Tutorial sanity.** Every link in
    `docs/guide/loan-application-tutorial.md` resolves to an
    existing path. Every code excerpt is a verbatim slice of
    the committed source. Reading the tutorial top-to-bottom
    should be coherent for someone who has read
    `docs/foundations/00..06` and `docs/guide/user-guide.md`.

11. **`keiki-test` self-contained.** `cabal build keiki-test`
    succeeds *without* `jitsurei` in the project (mental
    test: the keiki package's tests must not import any
    `Jitsurei.*` module).


## Idempotence and Recovery

Every step in this plan is additive — new files, new cabal
entries, new test specs, plus the M1 *renames* (which use
`git mv` so history is preserved). There are no destructive
operations, schema migrations, or data deletions. Re-running
the build and test commands at any point is safe and produces
the same result.

If a milestone fails halfway:

- **Build error in a new module.** Comment out the
  `exposed-modules` entry for the partially-written module
  and re-run `cabal build all` to confirm the rest of the
  tree still builds. Restore the entry once the module
  compiles.

- **Test failure in a new spec.** Run the failing spec in
  isolation with `cabal test jitsurei-test --test-options=
  "--match \"<spec prefix>\""`. The hspec output points at
  the failing example; consult the corresponding source file
  under `jitsurei/src/Jitsurei/`.

- **TH splice failure.** `deriveAggregateCtors`,
  `deriveWireCtors`, and `deriveView` raise compile-time
  errors with the constructor name in the message. Verify
  that the spec list's first column matches the constructor
  name verbatim and that every payload record has `Generic`,
  `Eq`, `Show` derived.

- **`compose` type mismatch.** The error names the mismatched
  `mid` types. Add or correct the `lmapMaybeCi` adapter in
  `LoanWorkflow.hs`.

- **z3 missing on test machine.** The
  `LoanApplicationSymbolic` spec fails loudly when z3 is
  absent; install with `brew install z3` (macOS) or
  `apt install z3` (Debian). `cabal test jitsurei-test
  --test-options="--skip \"Symbolic\""` skips that spec.

- **M1 partial migration.** If only some modules have been
  moved and the build is broken, the recovery path is either
  forward (finish the moves and the cabal/file edits) or
  backward (`git checkout -- src/Keiki/Examples/
  test/Keiki/Examples/ bench/` to restore the originals,
  then `git rm jitsurei/jitsurei.cabal` and the new
  directory tree). Prefer forward recovery — the M1 sub-
  steps are listed in order and the failure mode (a broken
  import or a missing cabal entry) is named in the
  compiler's first error.

The git workflow follows the repository convention
(Conventional Commits, no feature branches by default per
`/Users/shinzui/.claude/CLAUDE.md`). Each milestone's commits
include the trailers:

    ExecPlan: docs/plans/34-loan-application-worked-example-with-cross-context-process-and-tutorial.md
    Intention: intention_01kqqm4xexe9ps81r0kz3fz76z


## Interfaces and Dependencies

This plan introduces one new package (`jitsurei`) but no new
external library dependencies. The modules and types that must
exist at the end of each milestone:

### After M1

- `cabal.project` lists two packages.
- `jitsurei/jitsurei.cabal` exists with `library`,
  `test-suite jitsurei-test`, `benchmark keiki-bench`
  stanzas.
- `jitsurei/src/Jitsurei/` contains the four migrated example
  modules.
- `jitsurei/test/Spec.hs` and `jitsurei/test/Jitsurei/`
  contain the eleven migrated specs plus
  `Jitsurei/Render/MermaidExamplesSpec.hs` and
  `Jitsurei/Render/Fixtures.hs` (the `alertSource` re-home).
- `jitsurei/bench/Bench.hs` exists with `Jitsurei.*` imports.
- `keiki.cabal` library `exposed-modules` no longer includes
  any `Keiki.Examples.*`; the `benchmark` stanza is gone;
  `keiki-test`'s `other-modules` no longer includes any
  `Keiki.Examples.*Spec`.
- `test/Keiki/Render/MermaidSpec.hs` uses synthetic toy
  fixtures and does not depend on the example aggregates.
- `flake.nix` exposes both `haskellPackages.keiki` and
  `haskellPackages.jitsurei`.
- `cabal test all` is green; `git grep Keiki.Examples.`
  returns zero results.

### After M2

- `jitsurei/src/Jitsurei/LoanApplication.hs` exposing:
  - `LoanCmd`, `LoanEvent`, `LoanAppRegs`, `LoanAppVertex`.
  - All command/event payload records, the per-record
    `Generic`/`Eq`/`Show` instances, and the TH-derived
    `inCtor*` / `inp*` / `is*` / `wire*` / `*TermFields` /
    `loanAppView` / `SLoanAppVertex` / `LoanAppView` family.
  - `loanApplication :: SymTransducer (HsPred LoanAppRegs
    LoanCmd) LoanAppRegs LoanAppVertex LoanCmd LoanEvent`.
  - `loanApplicationAST :: <same shape>`.
  - `KnownInCtors LoanCmd` instance.
- `jitsurei.cabal` library `exposed-modules` lists the
  module.
- `jitsurei.cabal` `jitsurei-test` `other-modules` lists
  `Jitsurei.LoanApplicationSpec`,
  `Jitsurei.LoanApplicationBuilderSpec`,
  `Jitsurei.LoanApplicationViewSpec`,
  `Jitsurei.LoanApplicationSymbolicSpec`.
- `jitsurei/test/Spec.hs` invokes the four `Spec` modules'
  top-level `spec` values inside `describe` blocks.

### After M3

- `loanApplicationDriverConfig :: DriverConfig LoanAppVertex
  LoanCmd` and `loanApplicationChained :: <same shape as
  loanApplication>` exposed from
  `jitsurei/src/Jitsurei/LoanApplication.hs`.
- `jitsurei/test/Jitsurei/LoanApplicationChainedSpec.hs` and
  `jitsurei/test/Jitsurei/LoanApplicationMultiSpec.hs` added
  to cabal + `jitsurei/test/Spec.hs`.

### After M4

- `jitsurei/src/Jitsurei/Loan.hs` exposing `loan`, `LoanCmd'`,
  `LoanEvent'`, `LoanRegs`, `LoanVertex`, plus its TH-derived
  helpers and `KnownInCtors LoanCmd'` instance.
- `jitsurei/src/Jitsurei/CoreBankingSync.hs` exposing
  `coreBankingSync`, `SyncInput`, `SyncOutput`, `SyncRegs`,
  `SyncVertex`, plus TH helpers and `KnownInCtors SyncInput`.
- `jitsurei/test/Jitsurei/LoanSpec.hs` and
  `jitsurei/test/Jitsurei/CoreBankingSyncSpec.hs` wired in.

### After M5

- `jitsurei/src/Jitsurei/LoanWorkflow.hs` exposing
  `loanWorkflow :: SymTransducer (HsPred (Append LoanAppRegs
  (Append SyncRegs LoanRegs)) LoanCmd) … LoanCmd LoanEvent'`
  and the two adapter functions `loanEventToSyncInput ::
  LoanEvent -> Maybe SyncInput` and `syncOutputToLoanCmd ::
  SyncOutput -> Maybe LoanCmd'`.
- `jitsurei/test/Jitsurei/LoanWorkflowSpec.hs` wired in.

### After M6

- `jitsurei/test/Jitsurei/Render/MermaidLoanSpec.hs` wired in.
- Files `docs/guide/diagrams/loan-application.mmd`,
  `docs/guide/diagrams/loan.mmd`,
  `docs/guide/diagrams/core-banking-sync.mmd`,
  `docs/guide/diagrams/loan-workflow.mmd` exist.

### After M7

- `docs/guide/loan-application-tutorial.md` exists with the
  chapters listed above.
- `docs/guide/user-guide.md` §11 lists the new tutorial as a
  "where to go from here" pointer.

### External tools

- `cabal-install` ≥ 3.0 and GHC 9.12 (per `keiki.cabal`'s
  `tested-with` field; `jitsurei.cabal` matches).
- `z3` SMT solver in `PATH` for the symbolic specs.
  Install with `brew install z3` (macOS) or `apt install z3`
  (Debian).
- A Mermaid renderer (browser, GitHub preview, or `mmdc`) to
  visualise the `.mmd` files added in M6. Not required for
  `cabal test all` itself.


## Revision Notes

- 2026-05-03 (post-creation revision): expanded scope to include
  splitting out a new sibling `jitsurei` package and migrating
  *all* existing examples (`UserRegistration`,
  `UserRegistrationV0`, `OrderCart`, `EmailDelivery`) plus the
  `tasty-bench` benchmark and the example-driven Mermaid
  goldens into it, *before* layering the new LoanApplication
  example on top. The original plan placed the LoanApplication
  example under `Keiki.Examples.*` like the existing examples.
  Reason for the change: putting the new example in a separate
  package while leaving the older ones in the core library
  would create a permanent inconsistency that the user
  judged worse than the one-time migration cost. Migration
  bundled into the new plan as M1 (was originally six
  milestones; now seven). All subsequent milestones'
  module/file paths updated from `src/Keiki/Examples/X.hs`
  /  `Keiki.Examples.X` to `jitsurei/src/Jitsurei/X.hs` /
  `Jitsurei.X`. Decision Log gained four new entries
  (package split, package name choice, MermaidSpec split,
  benchmark relocation). Context and Orientation gained
  before/after package-layout sections plus the
  `jitsurei.cabal` shape sketch. Validation and Acceptance
  gained two new acceptance items (no leftover
  `Keiki.Examples.*` references; `keiki-test` self-
  contained). Idempotence section gained an M1 partial-
  migration recovery note.

- 2026-05-03 (post-completion review): re-checked whether the
  Mermaid renderer additions shipped before EP-34 (EP-30..EP-33)
  enable visualising the full `loanWorkflow` flow. Conclusion:
  no — the shipped renderers cover single transducers, 2-deep
  flat / nested composites, parallel `alternative`, and the
  feedback-typed 3-deep `Composite s1 (Composite s2 s1)`. The
  loanWorkflow's vertex shape `Composite LoanAppVertex (Composite
  SyncVertex LoanVertex)` is right-associative 3-deep with three
  *distinct* types, which falls outside every existing renderer's
  type signature, and the 2-deep renderers' `compositeLabel`
  produces whitespace-laden identifiers when composed twice.
  Updates: tightened M6's Progress note to name the gap precisely;
  added a Decision Log entry recording the analysis and the
  decision to defer rather than ship a partial-coverage golden;
  added a "Follow-ups" subsection in Outcomes & Retrospective
  tracking the missing renderer; added a fourth bullet to
  "Lessons for future plans" generalising the observation. No
  shipped code changed — this revision is documentation-only
  and preserves M1..M7 acceptance.

- 2026-05-04 (EP-35 closure): EP-35 shipped the deferred 3-deep
  composite renderer. Updates: M6 Progress sub-bullet rewritten to
  point at EP-35 and to list `loan-workflow.mmd` /
  `loan-workflow-nested.mmd` alongside the original three
  single-aggregate goldens; the "Follow-ups" subsection's
  "3-deep compose renderer" bullet struck through with a closure
  pointer to EP-35; tutorial §10 ("Wiring it together with
  `compose`") now embeds the rendered nested composite. No
  shipped code under `docs/plans/34-…md`'s milestones changed —
  the renderer addition lives under EP-35, the goldens under
  `jitsurei-test`'s existing spec module, and the tutorial edit
  is a purely additive `docs/guide/` change.
