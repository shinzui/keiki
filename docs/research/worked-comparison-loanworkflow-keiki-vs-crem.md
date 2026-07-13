# Worked comparison: the LoanWorkflow in keiki vs. crem

> Historical API note (2026-07-12): references below to the Decider facade
> describe a pre-0.1 design that has been removed. Use `Keiki.Core.stepEither`
> for forward decisions and the structured Core replay functions for hydration.

`architecture-comparison-keiki-vs-crem.md` compares the libraries
abstractly. This doc walks the same comparison through a concrete,
medium-sized example — the **LoanWorkflow** from EP-34
(`jitsurei/src/Jitsurei/{LoanApplication,Loan,CoreBankingSync,LoanWorkflow}.hs`)
— so the trade-offs land in code, not just in tables.

The worked example was chosen because it exercises features that the
small examples don't: a multi-aggregate cross-context flow with
asynchronous wiring, multi-field threshold guards, ε-edges, multi-
event commands, per-vertex view variance, and slot-name-disjoint
register-file composition.

---

## What the LoanWorkflow does

Three aggregates, one process manager, two transactional boundaries.

**LoanApplication** is the intake aggregate. It accepts evidence
(income docs, ID docs, credit-score recordings, employment checks),
silently tips into `UnderReview` once enough evidence is on file,
then approves or declines based on a multi-field threshold:

```
creditScore  >= 650
  ∧  employmentVerified == True
  ∧  requestedAmount    <= maxApprovalForScore creditScore
```

`ApplicationApproved` is the public event the next stage subscribes
to.

**Loan** is the downstream aggregate created on its own stream once
the application is approved. It holds an initially-unset
`legacyLoanId` slot that the process manager fills in later.

**CoreBankingSync** is the process manager. On `LoanCreated` it emits
an audit event (`SyncToLegacyRequested`) the runtime adapter consumes
to call the legacy core-banking system; on the legacy callback it
emits the `AssignLegacyLoanId` command targeted at the Loan
aggregate.

**LoanWorkflow** wires the three together via two `compose`
applications, with `lmapMaybeCi` adapters bridging the alphabet gaps
(LoanApplication's events → CoreBankingSync's inputs;
CoreBankingSync's outputs → Loan's commands). The resulting
`SymTransducer` is a type-level wiring diagram — see the variance
caveat in §"Composition" below.

The shape mirrors the production
`AgentQualification → QualifiedAgent → LegacyQaCreator Process` flow
in `mls-service-v2-master`.

---

## The keiki implementation

### LoanApplication — the intake aggregate

The transducer type:

```haskell
loanApplication
  :: SymTransducer (HsPred LoanAppRegs LoanCmd)
                   LoanAppRegs
                   LoanAppVertex
                   LoanCmd
                   LoanEvent
```

Six vertices (`Intake`, `CollectingDocuments`, `UnderReview`,
`Approved`, `Declined`, `Withdrawn`); seven command constructors
(six external + one internal `Continue` for the multi-event driver);
nine event constructors; ten register slots.

The threshold guard is expressed on the AST:

```haskell
approvalGuard :: HsPred LoanAppRegs LoanCmd
approvalGuard =
  PEq (TApp1 (>= approvalThresholdScore)
        (proj (#appCreditScore :: Index LoanAppRegs Int)))
      (lit True)
    `PAnd`
  PEq (proj (#appEmploymentVerified :: Index LoanAppRegs Bool))
      (lit True)
    `PAnd`
  PEq (TApp2 (<=)
        (proj (#appRequestedAmount :: Index LoanAppRegs Money))
        (TApp1 maxApprovalForScore
          (proj (#appCreditScore :: Index LoanAppRegs Int))))
      (lit True)
```

(*This is the original opaque-operand snapshot, kept for the AST-as-data
comparison. The shipped guard is now fully structural: the comparisons
are `PCmp` (EP-41) and the cap is `tmul (proj #appCreditScore) (lit
1000)` (EP-43), so the whole guard is solver-visible. See
`docs/guide/loan-application-tutorial.md`.*)

Builder-form authoring of the approval/decline branches:

```haskell
B.from UnderReview do
  -- Approval branch.
  B.onCmd inCtorContinue $ \d -> B.do
    B.requireGuard approvalGuard
    B.slot @"appDecidedAt" .= continueAt d
    B.emit wireApplicationApproved ApplicationApprovedTermFields
      { applicantId     = #appApplicantId
      , requestedAmount = #appRequestedAmount
      , creditScore     = #appCreditScore
      , at              = continueAt d
      }
    B.goto Approved

  -- Decline branch — the negation of approvalGuard.
  B.onCmd inCtorContinue $ \d -> B.do
    B.requireGuard (PNot approvalGuard)
    B.slot @"appDecidedAt"     .= continueAt d
    B.slot @"appDeclineReason" .= lit "Below threshold"
    B.emit wireApplicationDeclined ApplicationDeclinedTermFields
      { applicantId = #appApplicantId
      , reason      = #appDeclineReason
      , at          = continueAt d
      }
    B.goto Declined
```

The two edges share a vertex and a command constructor; the symbolic
layer (next §) proves they're mutually exclusive.

The ε-edge from `CollectingDocuments → UnderReview` is modelled as
an `inCtorContinue`-keyed edge with `B.noEmit`, so
`isSingleValuedSym` can reason about it through the constructor-mutex
translation of `PInCtor`.

### Loan — the downstream aggregate

```haskell
loan :: SymTransducer (HsPred LoanRegs LoanCmd')
                      LoanRegs
                      LoanVertex
                      LoanCmd'
                      LoanEvent'
loan = B.buildTransducer LoanInitial emptyLoanRegs
         (\case LoanLinked -> True; _ -> False) do
  B.from LoanInitial do
    B.onCmd inCtorCreateLoan $ \d -> B.do
      B.slot @"loanLoanId"      .= d.loanId
      B.slot @"loanApplicantId" .= d.applicantId
      B.slot @"loanPrincipal"   .= d.principal
      B.emit wireLoanCreated LoanCreatedTermFields { … }
      B.goto LoanAwaiting

  B.from LoanAwaiting do
    B.onCmd inCtorAssignLegacyLoanId $ \d -> B.do
      B.requireEq d.loanId #loanLoanId
      B.slot @"loanLegacyLoanId" .= d.legacyLoanId
      B.emit wireLegacyLoanIdAssigned LegacyLoanIdAssignedTermFields { … }
      B.goto LoanLinked
```

Three vertices, two transitions, four register slots. The
`B.requireEq d.loanId #loanLoanId` is the idempotency anchor: a
duplicate or mis-routed `AssignLegacyLoanId` fails the guard and
`delta` returns `Nothing`.

Slot names are deliberately prefixed (`loanLoanId`, `loanApplicantId`,
…) so the M5 `compose` with the other two aggregates satisfies
`Disjoint (Names rs1) (Names rs2)` at compile time.

### CoreBankingSync — the process manager

```haskell
coreBankingSync :: SymTransducer (HsPred SyncRegs SyncInput)
                                 SyncRegs
                                 SyncVertex
                                 SyncInput
                                 SyncOutput
```

Three vertices (`SyncIdle`, `SyncRequested`, `SyncSettled`); two
input event constructors (`LoanCreatedIn`, `LegacyCallbackReceivedIn`)
and two output constructors (`SyncToLegacyRequested` for the audit
trail, `LegacyAssignmentCommanded` wrapping the downstream
`AssignLegacyLoanId` command).

The `LegacyAssignmentCommanded` output carries an embedded `LoanCmd'`
constructed structurally from the input fields:

```haskell
B.from SyncRequested do
  B.onCmd inCtorLegacyCallbackReceivedIn $ \d -> B.do
    B.requireEq d.loanId #syncPendingLoanId
    B.emit wireLegacyAssignmentCommanded
      LegacyAssignmentCommandedTermFields
        { assignment = TApp2 buildAssign d.loanId d.legacyLoanId
        }
    B.goto SyncSettled
  where
    buildAssign lid llid = AssignLegacyLoanId
      (AssignLegacyLoanIdData { loanId = lid, legacyLoanId = llid })
```

### Composition

The full workflow is two nested `compose` applications with
`lmapMaybeCi` adapters between them:

```haskell
loanWorkflow
  :: SymTransducer
       (HsPred (Append LoanAppRegs (Append SyncRegs LoanRegs)) LoanCmd)
       (Append LoanAppRegs (Append SyncRegs LoanRegs))
       (Composite LoanAppVertex (Composite SyncVertex LoanVertex))
       LoanCmd
       LoanEvent'
loanWorkflow =
  loanApplication
    `compose`
  lmapMaybeCi loanEventToSyncInput
    (coreBankingSync `compose` lmapMaybeCi syncOutputToLoanCmd loan)
```

with two adapter functions doing the alphabet bridging:

```haskell
loanEventToSyncInput :: LoanEvent -> Maybe SyncInput
loanEventToSyncInput (ApplicationApproved a) =
  Just (LoanCreatedIn (LoanCreatedInData
    { loanId = "loan-" <> a.applicantId, … }))
loanEventToSyncInput _ = Nothing

syncOutputToLoanCmd :: SyncOutput -> Maybe LoanCmd'
syncOutputToLoanCmd (LegacyAssignmentCommanded d) = Just d.assignment
syncOutputToLoanCmd (SyncToLegacyRequested  _)    = Nothing
```

**The variance caveat.** `compose` is *lockstep* — every non-ε
composite edge fires both legs simultaneously. The cross-context
creation flow is async (the runtime observes `ApplicationApproved`,
then in a separate transactional step issues `LoanCreated`,
then later the legacy callback delivers `LegacyCallbackReceived`).
There's no single `LoanCmd` input that fires the entire chain in
one composite step, so the composite is largely a *type-level wiring
diagram*; the runtime drives each aggregate directly through the
adapter functions. `Jitsurei.LoanWorkflowSpec` exercises the
cross-context jumps that way. (See EP-34's Surprises & Discoveries
entry for the full discussion.)

This is the single sharpest place where keiki's composition story
trails crem's — see §"Cross-context routing" below for the contrast.

---

## The crem implementation (sketch)

The same workflow expressed in crem. Code is sketched for
illustration; the keiki repo doesn't depend on crem.

### LoanApplication

The vertices become a vertex kind, the topology is declared at the
type level, and per-vertex state is a vertex-indexed GADT:

```haskell
$( singletons [d|
   data LoanAppVertex
     = Intake
     | CollectingDocuments
     | UnderReview
     | Approved
     | Declined
     | Withdrawn

   loanAppTopology :: Topology LoanAppVertex
   loanAppTopology = Topology
     [ (Intake,             [CollectingDocuments, Withdrawn])
     , (CollectingDocuments,[CollectingDocuments, UnderReview, Withdrawn])
     , (UnderReview,        [Approved, Declined, Withdrawn])
     , (Approved,           [])
     , (Declined,           [])
     , (Withdrawn,          [])
     ]
   |] )

data LoanAppState (v :: LoanAppVertex) where
  StIntake :: LoanAppState 'Intake
  StCollecting :: ApplicantId -> Money -> Text
               -> Int -> Int -> Maybe Int -> Bool
               -> LoanAppState 'CollectingDocuments
  StUnderReview :: ApplicantId -> Money -> Int -> Bool
                -> LoanAppState 'UnderReview
  StApproved   :: ApplicantId -> Money -> Int -> UTCTime
               -> LoanAppState 'Approved
  StDeclined   :: ApplicantId -> Text -> UTCTime -> LoanAppState 'Declined
  StWithdrawn  :: ApplicantId -> UTCTime -> LoanAppState 'Withdrawn
```

`LoanCmd` and `LoanEvent` are plain ADTs (same as keiki).

crem has two ways to encode an aggregate, and the choice constrains
the multi-event story (see §"Multi-event commands" for the trade-
off). The most natural shape is `BaseMachine` directly with one
event per step:

```haskell
loanAppBasic :: BaseMachine LoanAppTopology LoanCmd (Maybe LoanEvent)
loanAppBasic = BaseMachineT
  { initialState = InitialState StIntake
  , action = \case
      StIntake -> \case
        StartApplication d ->
          pureResult (Just (ApplicationStarted d))
                     (StCollecting d.applicantId d.requestedAmount
                                   d.purpose 0 0 Nothing False)
        WithdrawApplication d ->
          pureResult (Just (ApplicationWithdrawn d))
                     (StWithdrawn d.applicantId d.at)
        _ -> pureResult Nothing StIntake  -- reject other commands
      StCollecting app amt purp inc id mScore vrf -> \case
        SubmitIncomeDocument d ->
          pureResult (Just (IncomeDocumentReceived d))
                     (StCollecting app amt purp (inc + 1) id mScore vrf)
        … -- one arm per (state, command) pair
  }

loanApp :: StateMachine LoanCmd [LoanEvent]
loanApp = rmap maybeToList (Basic loanAppBasic)
```

Note `output = Maybe LoanEvent` and the list shape comes from
`rmap maybeToList`. This matches the standard crem pattern (see the
RiskManager example). Each command produces at most one event per
step.

The threshold guard lives inside `action`, as ordinary Haskell:

```haskell
StUnderReview app amt score True -> \case
  Continue
    | score >= 650, amt <= maxApprovalForScore score ->
        pureResult (Just (ApplicationApproved (ApplicationApprovedData …)))
                   (StApproved app amt score now)
    | otherwise ->
        pureResult (Just (ApplicationDeclined (ApplicationDeclinedData …)))
                   (StDeclined app "Below threshold" now)
  _ -> pureResult Nothing (StUnderReview app amt score True)
```

The ε-edge from `CollectingDocuments → UnderReview` becomes a
`Continue`-handling arm that returns `Nothing` (silent emission)
while still advancing state.

### Loan and CoreBankingSync

Symmetric. Each becomes a `BaseMachine topology cmd (Maybe event)`
with a hand-written topology and a vertex-indexed state GADT, then
`rmap maybeToList` into `StateMachine cmd [event]` for composition.

### Composition

Cross-context wiring uses `rmap` for routing functions and `Kleisli`
to chain across the alphabet boundaries:

```haskell
-- Each base machine, lifted to a [event] output via rmap maybeToList.
loanApp :: StateMachine LoanCmd [LoanEvent]
loanApp = rmap maybeToList (Basic loanAppBasic)

sync    :: StateMachine SyncInput [SyncOutput]
sync    = rmap maybeToList (Basic syncBasic)

loan    :: StateMachine LoanCmd' [LoanEvent']
loan    = rmap maybeToList (Basic loanBasic)

-- LoanApplication's [LoanEvent] becomes [SyncInput], with non-
-- approved events filtered out.
appToSync :: StateMachine LoanCmd [SyncInput]
appToSync = rmap (mapMaybe loanEventToSyncInput) loanApp

-- SyncOutput → LoanCmd' (with the audit branch dropped).
syncToLoan :: StateMachine SyncInput [LoanCmd']
syncToLoan = rmap (mapMaybe syncOutputToLoanCmd) sync

-- The full pipeline.
loanWorkflow :: StateMachine LoanCmd [LoanEvent']
loanWorkflow = appToSync `Kleisli` syncToLoan `Kleisli` loan
```

`Kleisli` (crem) does what we want here that keiki's `compose` does
not: it traverses the upstream output list and runs the downstream
machine per element. A `LoanCmd` that produces `[ApplicationStarted]`
(no `ApplicationApproved`) flows through `appToSync` to `[]`, and
`Kleisli` short-circuits — the `sync` and `loan` machines don't
step. The lockstep variance caveat that bites keiki's composite
doesn't bite here.

The `Feedback` combinator is what crem uses for aggregate ↔ policy
loops; it's not the right shape for this pipeline-style flow but
would be the right shape for a Cart aggregate emitting events that
feed back as commands via a payment policy.

---

## Side-by-side comparison

The honest framing: keiki was built because crem could not express
several of the use cases the LoanWorkflow stresses. The comparison
below is grouped to make that asymmetry visible — capabilities one
library has that the other lacks, then trade-offs where both have
a story.

The architectural reason for the asymmetry: a keiki transducer is a
*value* (an AST of edges, guards, updates, output terms) that the
framework can introspect, transform, render, analyse. A crem
machine is largely an *opaque function* (`action`/`decide` are
lambdas; state is existentially quantified). Most of the keiki-only
items below trace back to that distinction.

### Capabilities keiki has that crem does not

#### Multi-event commands with a flat event log

A `RecordEmploymentCheck` that tips the threshold should produce
*two* events end to end: `EmploymentChecked` then
`ApplicationApproved`.

**keiki** uses state refinement plus `Keiki.Decider.toMultiDecider`
with a `DriverConfig`:

```haskell
loanApplicationDriverConfig :: DriverConfig LoanAppVertex LoanCmd
loanApplicationDriverConfig = DriverConfig
  { isInternal = \v -> case v of
      CollectingDocuments -> Just Continue
      UnderReview         -> Just Continue
      _                   -> Nothing
  }

-- decide mdec (RecordEmploymentCheck …) regs
--   ⇒ [EmploymentChecked …, ApplicationApproved …]
```

The driver issues `Continue` automatically at internal vertices,
walking a chain of letter edges end-to-end. The event log stays
flat (one event per entry); replay walks intermediate states
naturally via `applyEvent` event-by-event.

**crem cannot do this naturally.** The `Decider` type has
`decide :: input -> state v -> output` — *one output per call*,
diverging from Chassaing's `decide :: c -> s -> [e]`. The only ways
to get multi-event-per-command are:

1. Set `output = [Event]` in your `BaseMachine` directly (bypassing
   `Decider`). Then `evolve :: state v -> [Event] -> EvolutionResult`
   consumes the whole list at once and produces *one*
   `EvolutionResult`. You cannot fold `EvolutionResult`s — each
   step's `AllowedTransition` proof depends on the previous step's
   existentially-hidden final vertex. So `evolve` sees a list but
   can only express one cumulative state transition. Replay via
   `rebuildDecider :: [output] -> Decider` becomes
   `[[Event]] -> Decider` — your event log has to be chunked by
   command boundary, or you replay one giant list per command and
   lose event-level granularity.

2. Use `Sequential` or `Kleisli` composition to spread the work
   across multiple machines. This is awkward for "the same
   aggregate emits two events from one command in two intermediate
   states" — you'd need to factor the aggregate into separately-
   composable pieces.

This is one of the use cases that motivated keiki's existence.

#### Mechanical event → command inversion (replay correctness)

```haskell
-- keiki: solveOutput inverts an OPack output back to its producing input
solveOutput :: OutTerm rs ci co -> RegFile rs -> co -> Maybe ci

-- applyEvent uses it to walk an event log without ever storing commands
applyEvent :: SymTransducer phi rs s ci co
           -> s -> RegFile rs -> co -> Maybe (s, RegFile rs)
```

`applyEvent` finds the producing edge by inverting its `OPack`
output, recovers the implied command via `solveOutput`, verifies the
guard on the recovered command, and applies the update. The forward
direction (`omega`) and the backward direction (`applyEvent`) are
derived from the same `Edge` value — they cannot drift apart.

**crem requires the user to maintain `decide` and `evolve` in
agreement.** `decide` and `evolve` are independent functions inside
the `Decider` record; nothing in the framework checks they agree.
If the user updates one and forgets the other, replay silently
produces the wrong state. There is no `solveOutput` analogue.

For an event-sourced system this is the kind of bug class that
costs weeks in production. keiki's design makes it impossible.

#### Hidden-input detection

```haskell
checkHiddenInputs :: SymTransducer phi rs s ci co -> [HiddenInputWarning]
```

For every edge, keiki statically checks whether the edge's `update`
or `guard` reads a command field that the edge's `output` does not
carry. If the answer is yes, replay cannot reconstruct the command
on that edge — the field is *hidden* on the wire. The check returns
a list of warnings naming the offending edge and field.

**crem has no analogue.** A crem aggregate that drops a command
field on the way to events will pass type-checking, run, and
silently corrupt replayed state.

#### Symbolic guard analysis (SBV/Z3)

```haskell
-- All in Keiki.Symbolic; backed by SBV + Z3.
sat               :: SymPred rs ci -> Maybe (RegFile rs, ci)
isBot             :: SymPred rs ci -> Bool
isSingleValuedSym :: SymTransducer (SymPred …) rs s ci co -> Bool
symSatExt         :: SymPred rs ci -> SomeInCtor ci -> Maybe (RegFile rs, ci)
```

For the LoanWorkflow's `approvalGuard` and `PNot approvalGuard`
branches at `UnderReview`, `isSingleValuedSym` proves they're
mutually exclusive by asking Z3 whether their conjunction is
unsatisfiable. `isBot` catches a typo'd guard that can never fire.
`symSatExt` extracts a concrete `(RegFile, Command)` witness — useful
for property-based test generation, debugging, and counterexample
finding.

**crem has no symbolic layer.** Mutual exclusion of `decide` arms is
only checked by tests, and only on the inputs the tests exercise.

#### Compile-time slot-disjoint composition

```haskell
compose :: (Disjoint (Names rs1) (Names rs2), …)
        => SymTransducer phi rs1 s1 ci mid
        -> SymTransducer phi rs2 s2 mid co
        -> SymTransducer phi (Append rs1 rs2) (Composite s1 s2) ci co
```

The `Disjoint (Names rs1) (Names rs2)` constraint statically rejects
slot-name collisions. Two composed aggregates that both happen to
use a slot called `"id"` produce a `TypeError` at the `compose` call
site, naming the offending slot. This is why `LoanApplication`,
`Loan`, and `CoreBankingSync` use prefixed slot names
(`appApplicantId`, `loanApplicantId`, `syncPendingApplicantId`) —
the prefix discipline is enforced by the type system at composition
time.

**crem has no analogous check.** State in crem composition is
isolated by the existential quantification on each `BaseMachineT`,
so the question "did two aggregates accidentally share state"
doesn't even arise — but neither does the converse capability of
*intentionally* threading per-slot state through composed machines
with structural guarantees.

#### Compile-time disjoint-target check on edge updates

```haskell
combine :: Disjoint w1 w2
        => Update rs w1 ci -> Update rs w2 ci -> Update rs (Concat w1 w2) ci
```

Writing the same slot twice in one edge — `B.slot @"x" .= a` then
`B.slot @"x" .= b` — is a compile-time error. The `w :: [Symbol]`
index records the set of written slots; the `Disjoint` constraint
on `combine` rejects collisions.

**crem has no analogue.** Vertex-indexed state limits this somewhat
(state constructors take their data by position, so "writing the
same field twice" doesn't arise the same way), but cross-edge or
sequential update conflicts within one command are user-managed.

#### Generic-derived structural alphabets

```haskell
$(deriveAggregateCtors ''LoanCmd ''LoanAppRegs
    [ ("StartApplication",      "Start")
    , ("SubmitIncomeDocument",  "SubmitIncome")
    , …
    ])
$(deriveWireCtors ''LoanEvent
    [ ("ApplicationStarted",     "ApplicationStarted")
    , …
    ])
$(deriveView ''LoanAppVertex ''LoanAppRegs …)
```

`Keiki.Generics` + `Keiki.Generics.TH` derive `InCtor`, `WireCtor`,
the `RegFile` template, and the per-vertex `View` GADT from the
user's `Generic` instances. The structural payloads of every
command and event constructor are picked up automatically.

**crem has no derivation.** Each per-vertex state constructor and
its data layout is hand-written. For the LoanApplication's six
vertices and seven commands, that's ~100 lines of GADT and state
boilerplate that's free in keiki.

#### Authoring DSL with checked invariants

```haskell
B.from CollectingDocuments do
  B.onCmd inCtorRecordEmployment $ \d -> B.do
    B.slot @"appEmploymentVerified" .= d.verified
    B.emit wireEmploymentChecked EmploymentCheckedTermFields
      { verified = d.verified, at = d.at }
    B.goto CollectingDocuments
```

`Keiki.Builder` is a `QualifiedDo` DSL with compile-time checks for
duplicate slot writes, missing `goto`, and multiple `goto`s per
edge. Field-keyed `(.=)` enforces distinct-target safety via
`TypeApplication` on the slot name. Per-event `<CtorName>TermFields`
records (TH-derived) catch wrong-field-order and missing-field bugs
at compile time.

**crem has no equivalent DSL.** Authoring is hand-written
`BaseMachineT` records with nested `\case`.

### Capabilities crem has that keiki does not

#### Compile-time topology enforcement

```haskell
-- crem
applyOne StConfirmed (StartApplication _) =
  EvolutionResult $ StCollecting …
  -- TYPE ERROR: no AllowedTransition LoanAppTopology 'Approved 'CollectingDocuments
```

A topology violation — say, attempting `Approved → CollectingDocuments` —
is a type error in crem with a clear message. keiki catches the
same violation either at runtime (`delta` returns `Nothing`) or at
build time via `isBot` on the (vacuous) guard, but the latter
requires you to *write* the bad edge first.

For aggregates whose lifecycle topology is small, fixed, and
sacrosanct, crem's encoding is more actionable. For aggregates
whose topology evolves with the domain, the cost cuts the other
way: a topology change in crem cascades through every typeclass
resolution downstream.

#### Effect monad parameterisation in the core

```haskell
-- crem
data BaseMachineT m topology input output = …
hoist :: (forall x. m x -> n x) -> StateMachineT m a b -> StateMachineT n a b
```

crem's machine type carries an effect monad `m`; `hoist` swaps the
effect context (e.g. `Identity` in tests, `IO` in production). For
genuinely effectful aggregates (rare in practice — most aggregates
are pure), this is built in.

keiki keeps the pure-core / runtime split — `Keiki.Core` is
intentionally `IO`-free, and effects live in the runtime layer (yet
to ship a concrete adapter; see `effects-boundary.md`). The pure
core can run in any effect context the runtime monomorphises to,
but there's no `hoist` on the transducer type itself.

#### `Kleisli` and `Parallel` composition combinators

crem ships six composition constructors: `Sequential`, `Parallel`,
`Alternative`, `Feedback`, `Kleisli`. keiki ships three: `compose`,
`alternative`, `feedback1`. `Parallel` and `Kleisli` are re-deferred
(MP-8 EP-24) because the design milestone judged them unjustified
for keiki's typical use cases at the time.

For the LoanWorkflow specifically, this matters less than it
appears (see "Cross-context routing" below) — but for synchronous
event-stream pipelines crem has the better-stocked toolkit today.

#### `machines` ecosystem integration

crem ships an `AutomatonM` instance bridging to the `machines`
library, so a crem `StateMachine` drops directly into existing
streaming pipelines. keiki has no such bridge.

#### Profunctor / Strong / Choice / Arrow tower

crem's `StateMachineT` has the full `profunctors` typeclass tower.
keiki's `SomeSymTransducer` has `Profunctor` and `Functor`; the
rest (`Category`, `Strong`, `Choice`, `Arrow`) are planned (MP-9
EP-28/EP-29) but not shipped.

### Where both have a story but with different trade-offs

#### Multi-field threshold guards

```haskell
-- keiki: structural HsPred AST (original opaque-operand form; the
-- shipped guard now uses PCmp comparisons (EP-41) and a structural
-- cap tmul (proj #appCreditScore) (lit 1000) (EP-43), so it is fully
-- solver-visible — see docs/guide/loan-application-tutorial.md)
approvalGuard =
  PEq (TApp1 (>= 650) (proj #appCreditScore)) (lit True)
    `PAnd` PEq (proj #appEmploymentVerified) (lit True)
    `PAnd` PEq (TApp2 (<=) (proj #appRequestedAmount)
                            (TApp1 maxApprovalForScore (proj #appCreditScore)))
                (lit True)

-- crem: ordinary Haskell guard inside action
StUnderReview app amt score True -> \case
  Continue
    | score >= 650, amt <= maxApprovalForScore score ->
        pureResult (Just (ApplicationApproved …)) (StApproved …)
```

crem reads more naturally — it's just Haskell. keiki's `HsPred` AST
is the *price* of symbolic analysis; the guard exists as data so
SBV can reason about it. For a one-off threshold the AST is more
verbose; for a guard you actually want to *prove* properties about
(mutual exclusion, satisfiability, single-valuedness), the AST pays
back many times over.

#### ε-edges (silent transitions)

```haskell
-- keiki
B.from CollectingDocuments do
  B.onCmd inCtorContinue $ \_ -> B.do
    B.requireGuard readyForReviewGuard
    B.noEmit
    B.goto UnderReview

-- crem (output = Maybe Event)
StCollecting app amt purp inc id (Just s) True -> \case
  Continue
    | inc >= 2, id >= 1 ->
        pureResult Nothing (StUnderReview app amt s True)
```

Both work. crem's is a one-liner using `Nothing`. keiki's `noEmit`
is explicit, and the `Continue`-keyed encoding gives the symbolic
layer a `PInCtor` constructor-mutex handle for free.

#### Per-vertex view variance

```haskell
-- keiki: TH-derived View GADT over the uniform RegFile
$(deriveView ''LoanAppVertex ''LoanAppRegs
    "SLoanAppVertex" "LoanAppView" "loanAppView"
    [ ("Intake",   ["appApplicantId"])
    , ("Approved", ["appApplicantId", "appRequestedAmount",
                    "appCreditScore", "appDecidedAt"])
    , …
    ])

-- crem: per-vertex constructors of the state GADT
data LoanAppState (v :: LoanAppVertex) where
  StIntake   :: ApplicantId -> LoanAppState 'Intake
  StApproved :: ApplicantId -> Money -> Int -> UTCTime
             -> LoanAppState 'Approved
```

Both yield "this vertex exposes exactly these fields." crem's
state-IS-the-view is conceptually cleaner; the cost is that
composition (`Composite s1 s2`) compounds the per-vertex
constructors combinatorially. keiki's separation of plain vertex
from typed register file makes `compose` tractable — slot lists
just `Append`, vertices form the cross product, view definitions
remain per-aggregate.

#### Cross-context routing

This is where I previously gave crem a clear win, and it's worth
being precise about why that was wrong.

The LoanWorkflow's cross-context flow is *asynchronous*:
LoanApplication runs in its own event stream and emits
`ApplicationApproved`; the runtime adapter observes it and, in a
*separate transaction*, issues a `LoanCreated` command on the Loan
aggregate's stream; later, the legacy callback channel delivers a
`LegacyCallbackReceived` event that drives CoreBankingSync, which
emits `LegacyAssignmentCommanded` carrying an `AssignLegacyLoanId`
command for the Loan aggregate.

This is eventually-consistent across event streams, not synchronous
chaining within one step.

**keiki**: `compose` is lockstep — runs both legs together — and
explicitly admits in `Jitsurei.LoanWorkflow`'s module haddock that
the resulting `loanWorkflow :: SymTransducer …` is a *type-level
wiring diagram*. The runtime drives each aggregate directly via the
`loanEventToSyncInput` / `syncOutputToLoanCmd` adapters. This is
honest: the type captures the wiring, the execution is async.

**crem**: `Kleisli` chains synchronously — the upstream's `[event]`
output drives the downstream machine in the same step. For a
genuinely synchronous request/response pipeline this is great. For
an async cross-context flow, `Kleisli` is *modelling the wrong
semantics* — running the chained `loanWorkflow` against a single
`LoanCmd` would attempt to step all three aggregates in one
transaction, which isn't how the runtime works. You'd still need
runtime-mediated wiring across event streams.

So both libraries need a runtime adapter for the actual async flow.
crem's `Kleisli` makes a synchronous in-memory composite available
that keiki lacks (a future `Keiki.Composition.kleisli` would close
that gap), but it doesn't solve the cross-context async problem
either library has.

#### Visualization

Both ship Mermaid renderers. keiki's `Keiki.Render.Mermaid` is
shape-aware (per-combinator renderers for `compose` / `alternative`
/ `feedback1` / nested compositions). crem's renders via graph
products on the topology singletons. Outputs are visually
comparable; canonical keiki diagrams are checked into
`docs/guide/diagrams/`.

---

## Summary

| Dimension                                    | Verdict   |
|----------------------------------------------|-----------|
| Multi-event commands with flat event log     | **keiki only** |
| Mechanical event→command inversion (replay)  | **keiki only** |
| Hidden-input detection                       | **keiki only** |
| Symbolic guard analysis (SBV/Z3)             | **keiki only** |
| Compile-time slot-disjoint composition       | **keiki only** |
| Compile-time disjoint-target on edge updates | **keiki only** |
| Generic-derived structural alphabets         | **keiki only** |
| Authoring DSL with checked invariants        | **keiki only** |
| Compile-time topology (vertex→vertex)        | **crem only**  |
| Effect monad parameterisation in the core    | **crem only**  |
| `Kleisli` / `Parallel` combinators           | **crem only** (re-deferred in keiki) |
| `machines` ecosystem integration             | **crem only**  |
| Full Profunctor/Strong/Choice/Arrow tower    | **crem only** (planned in keiki) |
| Multi-field threshold guards                 | crem (shorter); keiki (provable) |
| ε-edges                                      | crem (more compact); keiki (constructor-mutex handle) |
| Per-vertex view variance                     | crem (state-is-view); keiki (composition-friendly) |
| Cross-context async routing                  | Even (both need runtime-mediated wiring) |
| Visualization                                | Even |

The asymmetry is real: keiki has a substantially larger set of
unique capabilities, several of which (mechanical inversion, hidden-
input detection, symbolic analysis, multi-event with flat logs) are
specifically the use cases that motivated building keiki rather
than continuing with crem.

crem's unique capabilities cluster around ecosystem integration
(profunctor tower, `machines`, `hoist`) and one core architectural
choice (compile-time topology). The first three are planned work in
keiki; the topology question is the only fundamental choice keiki
made differently and traded away.

For the LoanWorkflow specifically, keiki is the better fit because
the example exercises exactly the use cases crem cannot natively
express: multi-event commands with flat event logs, structural
event-to-command inversion for replay, multi-field threshold guards
you want to *prove* properties about, and slot-disjoint composition
across three aggregates.
