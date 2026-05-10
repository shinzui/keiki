# Worked comparison: the LoanWorkflow in keiki vs. crem

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

The aggregate is a `Decider`:

```haskell
loanApplicationDecider :: Decider LoanAppTopology LoanCmd [LoanEvent]
loanApplicationDecider = Decider
  { deciderInitialState = InitialState StIntake
  , decide = \cmd state -> case (cmd, state) of
      (StartApplication d, StIntake) ->
        [ApplicationStarted d]
      (SubmitIncomeDocument d, StCollecting{}) ->
        [IncomeDocumentReceived d]
      … -- one arm per (state, command) pair, ~20 arms total
      _ -> []  -- catch-all rejecting unmatched (state, command)
  , evolve = \state events ->
      foldl' applyOne state events
  }
  where
    applyOne :: LoanAppState v -> LoanEvent
             -> EvolutionResult LoanAppTopology LoanAppState v [LoanEvent]
    applyOne StIntake (ApplicationStarted d) =
      EvolutionResult $ StCollecting d.applicantId d.requestedAmount
                                     d.purpose 0 0 Nothing False
    -- Note the EvolutionResult constructor: GHC discharges
    -- AllowedTransition LoanAppTopology 'Intake 'CollectingDocuments
    -- by typeclass resolution. Trying to evolve to 'Approved here
    -- would be a type error.
    …
```

The threshold guard lives inside `decide`, as ordinary Haskell:

```haskell
(Continue, StUnderReview app amt score True)
  | score >= 650, amt <= maxApprovalForScore score ->
      [ApplicationApproved (ApplicationApprovedData app amt score now)]
  | otherwise ->
      [ApplicationDeclined (ApplicationDeclinedData app "Below threshold" now)]
(Continue, _) -> []
```

The ε-edge from `CollectingDocuments → UnderReview` is handled
similarly: a `Continue` arm in `decide` with a guard, returning
`[]` (no event) but still moving state via `evolve`.

### Loan and CoreBankingSync

Symmetric. Each becomes a `Decider topology cmd [event]` with a
hand-written topology and a vertex-indexed state GADT. CoreBankingSync
is a `Decider topology SyncInput [SyncOutput]` whose `decide` arms
match on `(input, state)` pairs.

### Composition

Wrap each `Decider` in a `Basic BaseMachineT` via `deciderMachine`,
then compose:

```haskell
loanApp :: StateMachine LoanCmd [LoanEvent]
loanApp = Basic (deciderMachine loanApplicationDecider)

sync    :: StateMachine SyncInput [SyncOutput]
sync    = Basic (deciderMachine coreBankingSyncDecider)

loan    :: StateMachine LoanCmd' [LoanEvent']
loan    = Basic (deciderMachine loanDecider)
```

Cross-context wiring uses `lmap` (a partial routing function) and
`Kleisli` to chain across the alphabet boundaries:

```haskell
-- LoanApplication's [LoanEvent] becomes [SyncInput], with non-
-- approved events filtered out via 'mapMaybe loanEventToSyncInput'.
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
not: it allows the composite to *not* fire downstream legs when the
upstream leg's output is the empty list. A `LoanCmd` that produces
`[ApplicationStarted …]` (no `ApplicationApproved`) flows through
`appToSync` to `[]`, which `Kleisli` short-circuits — the `sync` and
`loan` machines don't step. The lockstep variance caveat that bites
keiki's composite doesn't bite here.

The `Feedback` combinator is what crem uses for aggregate ↔ policy
loops; it's not the right shape for this pipeline-style flow but
would be the right shape for, e.g., a Cart aggregate emitting events
that feed back as commands via a payment policy.

---

## Side-by-side comparison, dimension by dimension

### 1. Per-aggregate boilerplate

| Element                | keiki                                         | crem                                                  |
|------------------------|-----------------------------------------------|-------------------------------------------------------|
| Vertices               | Plain `data … deriving (Eq, Show, Enum, Bounded)` | Promoted via `singletons` TH                          |
| Per-vertex state data  | `RegFile rs` (separate, slot-keyed)           | Vertex-indexed GADT (per-vertex constructor)          |
| Topology               | Implicit in `edgesOut`                         | Declared explicitly at the type level (also TH-promoted) |
| Command alphabet       | Plain ADT + `$(deriveAggregateCtors …)` for InCtors | Plain ADT (no derivation)                             |
| Event alphabet         | Plain ADT + `$(deriveWireCtors …)` for WireCtors | Plain ADT (no derivation)                             |
| Per-edge body          | `B.onCmd inCtor $ \d -> B.do …`                | `\case (cmd, state) -> [ev]` arms inside `decide`     |
| Per-vertex `View`      | `$(deriveView …)` produces a TH-derived GADT   | Comes "free" from the vertex-indexed state GADT       |

Both are roughly comparable in line count for the LoanApplication
aggregate; keiki's authoring is more declarative (one `B.onCmd` per
edge), crem's is more pattern-match-heavy (one `decide` arm per
(command, state) pair with explicit catch-all).

The TH derivations (`deriveAggregateCtors`, `deriveWireCtors`,
`deriveView`) are keiki's compensation for not having vertex-indexed
state for free; the crem version saves no boilerplate but doesn't
need any either.

### 2. Multi-field threshold guards

```haskell
-- keiki: structural HsPred AST
approvalGuard =
  PEq (TApp1 (>= 650) (proj #appCreditScore)) (lit True)
    `PAnd` PEq (proj #appEmploymentVerified) (lit True)
    `PAnd` PEq (TApp2 (<=) (proj #appRequestedAmount)
                            (TApp1 maxApprovalForScore (proj #appCreditScore)))
                (lit True)

-- crem: ordinary Haskell guard inside decide
| score >= 650, employmentVerified, amt <= maxApprovalForScore score ->
    [ApplicationApproved …]
```

crem's encoding is shorter and reads more naturally — it's just
Haskell. keiki's `HsPred` AST exists so the symbolic layer
(`Keiki.Symbolic`) can prove guard properties at build time:
`isSingleValuedSym` proves the approval and decline branches are
mutually exclusive (the `PNot` of the conjunction is unsatisfiable
at the satisfying point and vice versa); `isBot` would catch a
typo'd guard that can never fire. crem's guard is an opaque
Haskell `Bool` and gets none of that.

This is the canonical "AST tax" of the keiki design: ergonomic cost
for analytic power.

### 3. ε-edges (silent transitions)

The CollectingDocuments → UnderReview transition emits no public
event.

```haskell
-- keiki: B.noEmit on a Continue-keyed edge
B.from CollectingDocuments do
  B.onCmd inCtorContinue $ \_ -> B.do
    B.requireGuard readyForReviewGuard
    B.noEmit
    B.goto UnderReview

-- crem: a [] return from decide, plus an evolve arm
(Continue, StCollecting … inc id score True)
  | inc >= 2, id >= 1, score `elem` Just _ ->
      []  -- empty event list; no public emission
applyOne (StCollecting app amt purp _ _ (Just s) True) _ =
  EvolutionResult $ StUnderReview app amt s True
```

Both work. crem's is more compact. keiki's is more explicit but
gives the symbolic layer a `PInCtor` constructor-mutex handle that
the Haskell-level guard doesn't expose.

### 4. Multi-event commands

A `RecordEmploymentCheck` that tips the threshold should produce
*two* events end to end: `EmploymentChecked` and
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
walking the chain end-to-end through a single user-issued command.

**crem** sidesteps the question by typing the output as `[Event]`
from the start, and by using `Kleisli` composition when chains span
machines. `decide` returns a list and `evolve` consumes a list (or
folds over it), so a single command naturally produces multiple
events.

The two encodings are equivalent in expressive power; crem's reads
more directly because the multi-event story is baked into the
machine type, while keiki's is a separate facade over a letter
transducer.

### 5. Per-vertex view variance

`Intake` exposes only `applicantId`; `Approved` exposes
`applicantId`, `requestedAmount`, `creditScore`, `decidedAt`.

```haskell
-- keiki: TH-derived GADT View
$(deriveView ''LoanAppVertex ''LoanAppRegs
    "SLoanAppVertex" "LoanAppView" "loanAppView"
    [ ("Intake",   ["appApplicantId"])
    , ("Approved", ["appApplicantId", "appRequestedAmount",
                    "appCreditScore", "appDecidedAt"])
    , …
    ])

-- crem: comes free from the vertex-indexed state GADT
data LoanAppState (v :: LoanAppVertex) where
  StIntake   :: ApplicantId -> LoanAppState 'Intake
  StApproved :: ApplicantId -> Money -> Int -> UTCTime
             -> LoanAppState 'Approved
  …
```

This is the cleanest place where crem's vertex-indexed state pays
off: the per-vertex view is just *the state itself*. keiki recovers
the same shape via TH but at the cost of a separate slot list and
a derivation step.

### 6. Cross-context routing

This is where the two libraries diverge most.

**keiki**: `compose` is lockstep. Every non-ε composite edge fires
both legs simultaneously. The async cross-context flow
(`ApplicationApproved` observed → `CreateLoan` issued in a separate
transaction → legacy callback later) cannot be captured as a single
`LoanCmd` step through `loanWorkflow`. The composite remains a
type-level wiring diagram; the runtime drives each aggregate
directly via the `loanEventToSyncInput` / `syncOutputToLoanCmd`
adapters.

**crem**: `Kleisli` short-circuits on empty event lists, so a
`LoanCmd` that produces `[ApplicationStarted …]` (no
`ApplicationApproved`) flows through `appToSync` to `[]` and the
downstream legs don't step. The pipeline composite *is* runnable
end-to-end as a `StateMachine LoanCmd [LoanEvent']`. `Feedback` would
be the right combinator if the chain looped (aggregate ↔ policy);
`Kleisli` is the right one for this pipeline shape.

The keiki re-deferral of `Kleisli` (MP-8 EP-24) is what costs us
here: the only shipped composition is `compose`, and `compose` is
lockstep. `feedback1` is a single-step round and doesn't help
either. A future `Keiki.Composition.kleisli` would close this gap.

This is the single dimension on which crem does this example
*meaningfully better* end to end. Everything else is roughly even
or favours keiki.

### 7. Compile-time topology safety

```haskell
-- crem
applyOne StConfirmed (StartApplication _) =
  EvolutionResult $ StCollecting …
  -- TYPE ERROR: no AllowedTransition LoanAppTopology 'Approved 'CollectingDocuments

-- keiki
edgesOut Approved = []
-- delta t Approved regs StartApplication = Nothing  (runtime)
-- isBot can prove the guard never holds (build-time, via SBV)
```

crem catches it at compile time with no extra work. keiki catches
it either at runtime (`delta` returns `Nothing`) or at build time
via `isBot` on the (vacuous) guard, but the latter requires you to
*write* an edge to check.

A topology violation in the LoanWorkflow — say, `Approved →
CollectingDocuments` — is a type error in crem and a missing edge
in keiki. crem's report is more actionable.

The flip side: changing the topology in crem cascades through every
typeclass resolution downstream; in keiki you change one branch of
one `edgesOut` case. crem optimises for "topology is sacred"; keiki
optimises for "topology evolves."

### 8. Symbolic analysis

```haskell
-- keiki
isSingleValuedSym (withSymPred loanApplication)
  -- ⇒ True. The two Continue-keyed edges out of UnderReview
  -- (approve / decline) are proven mutually exclusive by Z3.

isBot (PNot (matchInCtor inCtorWithdraw)
        `PAnd` matchInCtor inCtorWithdraw)
  -- ⇒ True. Constructor mutex is recognised symbolically.

symSatExt approvalGuard
  -- ⇒ Just (regs witness, Continue command)
```

crem has no equivalent. Mutual exclusion of the approve/decline
branches in crem is only checked by tests — usually a property test
that runs the aggregate against random inputs and asserts no two
arms agree. keiki delegates to Z3 and gets a proof.

### 9. Snapshot / replay

```haskell
-- keiki
reconstitute loanApplication eventLog
  -- ⇒ Just (LoanAppVertex, RegFile LoanAppRegs)
applyEvents loanApplication (vertex, regs) chunk
  -- ⇒ Just (vertex', regs')

-- crem
rebuildDecider eventLog loanApplicationDecider
  -- ⇒ Decider with state restored
```

Both work. keiki's `applyEvent` inverts the producing edge's `OPack`
mechanically via `solveOutput` — no separate `evolve` to maintain.
crem's `rebuildDecider` folds the user's `evolve`. If the user's
`decide` and `evolve` drift apart, crem replays the wrong state;
keiki cannot drift because the same edge produces both directions.

For the LoanWorkflow specifically, every event carries enough fields
that `solveOutput` works for every edge — `checkHiddenInputs
loanApplication` returns `[]`. crem makes no such guarantee.

### 10. Visualization

```haskell
-- keiki
renderMermaid loanApplication
  -- ⇒ a Mermaid stateDiagram-v2 with all six vertices and edges

renderCompositeMermaid loanWorkflow
  -- ⇒ a composite-shape diagram (see docs/guide/diagrams/loan-workflow.mmd
  -- and loan-workflow-nested.mmd for the canonical outputs)

-- crem
renderStateDiagram (machineAsGraph loanApplicationMachine)
  -- ⇒ Mermaid; composite machines render via graph products
```

Both ship Mermaid renderers. crem's composition rendering composes
graphs; keiki's is shape-aware (per combinator). The end results are
visually similar; the canonical keiki output is checked into
`docs/guide/diagrams/loan-workflow.mmd` and
`loan-workflow-nested.mmd`.

---

## What this exposes about each library

**crem looks better when:**

- The topology is small, fixed, and the per-vertex state varies
  significantly. The vertex-indexed GADT is the cleanest possible
  encoding of "different state per lifecycle position."
- The composition is shaped like a pipeline with optional
  short-circuiting (`Kleisli`) or a feedback loop (`Feedback`). This
  is the LoanWorkflow's case for cross-context flows.
- Compile-time topology enforcement is more important than
  topology agility.

**keiki looks better when:**

- Commands and events have non-trivial structural payloads that need
  to round-trip cleanly (event-replay correctness without a separate
  `evolve` to maintain).
- Guards are non-trivial and you want to *prove* properties about
  them (mutual exclusion, satisfiability, single-valuedness) rather
  than test them.
- Authoring ergonomics matter: `Keiki.Builder` + `Keiki.Generics`
  removes more per-edge boilerplate than crem can.
- The register-file separation matches your domain (slot-keyed,
  generic snapshot codec, named-slot diagnostics).

**Where keiki is currently weaker:**

- `Kleisli`-style cross-context composition is re-deferred (MP-8
  EP-24). For the LoanWorkflow, this means `compose` doesn't run the
  full pipeline as a single `LoanCmd` step; the runtime drives the
  cross-context jumps via the adapter functions instead. crem's
  `Kleisli` does this for free.
- No type-level topology — runtime `Maybe` plus build-time `isBot`
  is the closest equivalent.
- No effect monad in the core type (the runtime layer monomorphises
  the effect context; crem builds it into `BaseMachineT m`).

---

## Summary

The LoanWorkflow exercises the parts of both libraries that the
small examples don't reach. Across ten dimensions:

| Dimension                  | Verdict                                     |
|----------------------------|---------------------------------------------|
| Per-aggregate boilerplate  | Roughly even (different shape, similar weight) |
| Multi-field threshold guards | crem (shorter); keiki (provable)          |
| ε-edges                    | crem (more compact)                          |
| Multi-event commands       | crem (built-in via `[Event]`); keiki (chain + driver) |
| Per-vertex view variance   | crem (free with the GADT)                    |
| Cross-context routing      | **crem** (`Kleisli` short-circuits; keiki's `compose` is lockstep) |
| Compile-time topology      | **crem** (type-level)                        |
| Symbolic analysis          | **keiki** (no crem equivalent)               |
| Snapshot / replay          | keiki (mechanical inversion; no drift)       |
| Visualization              | Even                                         |

crem wins on three dimensions; keiki wins on two; the rest are even
or matter only at the margin. The cross-context routing gap is the
sharpest item on the keiki side — a future
`Keiki.Composition.kleisli` would close it.

For the LoanWorkflow specifically, neither library is strictly
better. The choice in practice is which trade-offs match your
project: type-level topology and ecosystem composition (crem) vs.
structural alphabets, symbolic analysis, and derived event sourcing
(keiki).
