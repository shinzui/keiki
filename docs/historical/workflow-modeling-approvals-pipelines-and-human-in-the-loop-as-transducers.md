# Transducers for Workflow Modeling

A workflow is a transducer. The inputs are actions (human decisions,
system triggers, timer expirations), the outputs are effects
(notifications, state changes, side effects), and the states track
progress through the process.

What distinguishes a workflow from a saga or process manager is not the
formalism — it's the **routing complexity** and the **human-in-the-loop
nature** of the inputs. Workflows have parallel branches, conditional
splits, loops, and join points. All of these map to specific FST
constructions.

---

## A Workflow Is a Transducer

```
T_workflow = ⟨S, A, E, δ, ω, s₀, F⟩

S  = workflow states (steps, milestones, decision points)
A  = actions (approve, reject, submit, escalate, timeout)
E  = effects (send notification, update status, assign task)
δ  = routing logic (which step follows which action)
ω  = effect logic (what happens at each transition)
s₀ = initial state (e.g., Draft, Submitted)
F  = terminal states (Approved, Rejected, Cancelled)
```

**Example: Document Approval Workflow**

```haskell
data WfState
  = Draft
  | AwaitingReview
  | UnderReview
  | RevisionRequested
  | AwaitingApproval
  | Approved
  | Rejected
  deriving (Eq, Show, Enum, Bounded)

data WfAction
  = Submit
  | ClaimReview
  | RequestRevision
  | PassReview
  | Revise
  | Approve
  | Reject
  | Withdraw
  deriving (Eq, Show, Enum, Bounded)

data WfEffect
  = NotifyReviewers
  | AssignReviewer
  | NotifyAuthorRevision
  | NotifyApprover
  | NotifyAuthorApproved
  | NotifyAuthorRejected
  | NotifyAllWithdrawn
  deriving (Eq, Show, Enum, Bounded)

documentApproval :: Transducer WfState WfAction WfEffect
documentApproval = Transducer
  { delta = \s a -> case (s, a) of
      (Draft,              Submit)          -> Just AwaitingReview
      (AwaitingReview,     ClaimReview)     -> Just UnderReview
      (AwaitingReview,     Withdraw)        -> Just Rejected
      (UnderReview,        RequestRevision) -> Just RevisionRequested
      (UnderReview,        PassReview)      -> Just AwaitingApproval
      (RevisionRequested,  Revise)          -> Just AwaitingReview
      (AwaitingApproval,   Approve)         -> Just Approved
      (AwaitingApproval,   Reject)          -> Just Rejected
      _                                     -> Nothing

  , omega = \s a -> case (s, a) of
      (Draft,              Submit)          -> Just NotifyReviewers
      (AwaitingReview,     ClaimReview)     -> Just AssignReviewer
      (AwaitingReview,     Withdraw)        -> Just NotifyAllWithdrawn
      (UnderReview,        RequestRevision) -> Just NotifyAuthorRevision
      (UnderReview,        PassReview)      -> Just NotifyApprover
      (RevisionRequested,  Revise)          -> Just NotifyReviewers
      (AwaitingApproval,   Approve)         -> Just NotifyAuthorApproved
      (AwaitingApproval,   Reject)          -> Just NotifyAuthorRejected
      _                                     -> Nothing

  , initial = Draft
  , isFinal = \case { Approved -> True; Rejected -> True; _ -> False }
  }
```

---

## Workflow Patterns as FST Constructions

The [Workflow Patterns](http://www.workflowpatterns.com/) taxonomy
(van der Aalst et al.) describes routing constructs found in workflow
systems. Each maps to an FST construction:

### Sequential (Concatenation)

Steps execute one after another. This is **concatenation** of
sub-transducers:

```
T_draft · T_review · T_approval
```

Each sub-transducer handles one phase. When a phase reaches a final
state, the next phase begins.

```
Draft → AwaitingReview → UnderReview → AwaitingApproval → Approved
           T_draft            T_review          T_approval
```

### Exclusive Choice (XOR-Split)

One of several paths is taken based on the action. This is a
**branching delta** — different actions in the same state lead to
different next states:

```haskell
delta UnderReview RequestRevision = Just RevisionRequested  -- path A
delta UnderReview PassReview      = Just AwaitingApproval   -- path B
```

No special construction needed — branching is native to the transducer.
The Acceptor's transition function captures all valid branches.

### Simple Merge (XOR-Join)

Multiple paths converge to a single state. This is a **shared target
state** — different transitions from different source states lead to
the same next state:

```haskell
delta AwaitingApproval Reject  = Just Rejected
delta AwaitingReview   Withdraw = Just Rejected
-- Both paths merge at Rejected
```

### Loop / Iteration

A sequence of steps repeats until a condition is met. This is a
**cycle in the state graph**:

```
                    Revise
Draft → AwaitingReview → UnderReview → RevisionRequested
              ↑                              │
              └──────────────────────────────┘
                         (loop)
```

```haskell
delta RevisionRequested Revise = Just AwaitingReview  -- back to review
```

The Acceptor accepts arbitrarily long sequences with repeated loops:

```
[Submit, ClaimReview, RequestRevision, Revise,      -- first cycle
 ClaimReview, RequestRevision, Revise,               -- second cycle
 ClaimReview, PassReview, Approve]                   -- exit loop
```

### Parallel Split (AND-Split)

Multiple branches execute concurrently. This is the **product
construction** — the state space is the Cartesian product of the
branch state spaces:

```haskell
-- Two independent review tracks running in parallel
data ParallelState = ParallelState
  { technicalReview :: TechReviewState
  , legalReview     :: LegalReviewState
  }

-- Product transducer: both branches advance independently
parallelReview :: Transducer ParallelState (Either TechAction LegalAction) (Either TechEffect LegalEffect)
parallelReview = ...
```

This is equivalent to `union` on the two branch Acceptors — the product
state tracks both branches simultaneously.

### Synchronization (AND-Join)

Wait for all parallel branches to complete before proceeding. This is a
**final state condition on the product state** — the joined state is
final only when ALL branches have reached their final states:

```haskell
isFinal (ParallelState tech legal) =
  isFinalTech tech && isFinalLegal legal
```

Concatenating the parallel transducer with the next phase gives the
full pattern:

```
T_parallel · T_afterJoin
```

The concatenation's ε-transition fires only when `T_parallel` reaches
a final state — i.e., when all branches are done.

### Deferred Choice

The workflow offers multiple options and waits for the environment to
pick one. This is just **multiple valid transitions from the same
state** — whichever action arrives first determines the path:

```haskell
delta AwaitingDecision Approve  = Just Approved     -- option A
delta AwaitingDecision Reject   = Just Rejected     -- option B
delta AwaitingDecision Escalate = Just Escalated    -- option C
```

The transducer doesn't choose — it waits for the external action.

### Milestone

A state that must be reached before certain transitions become
available. This is encoded naturally in the state space — the
milestone state is a prerequisite for downstream transitions:

```haskell
-- SecurityReview must be passed before FinalApproval is possible
delta SecurityCleared  RequestFinalApproval = Just AwaitingFinalApproval
delta UnderReview      RequestFinalApproval = Nothing  -- blocked: milestone not reached
```

---

## Workflow vs. Saga: What's Different?

Structurally, nothing — both are transducers. The differences are in
the domain:

| Aspect | Saga / Process Manager | Workflow |
|--------|----------------------|----------|
| Input source | Events from aggregates (automated) | Human actions + timers (manual) |
| Latency | Milliseconds to seconds | Hours to weeks |
| Routing | Usually linear or branching | Parallel branches, loops, joins |
| State complexity | Moderate (tracking steps) | High (tracking multiple branches + history) |
| Compensation | Central concern (undo on failure) | Less common (revisions instead) |
| Visibility | Internal (system coordination) | External (user-facing status) |

The transducer formalism handles both identically. The difference is
what you DO with the formal operations:

- **Sagas**: Use output projection to verify compensating commands cover
  all failure paths
- **Workflows**: Use input projection to verify all user-facing actions
  are reachable; use Acceptor to validate action sequences

---

## Formal Guarantees for Workflows

### Deadlock Detection

A workflow deadlocks when it reaches a non-final state with no valid
transitions. Given `(Enum s, Bounded s, Enum a, Bounded a)`, enumerate:

```haskell
-- States with no outgoing transitions that aren't final
deadlocks :: (Enum s, Bounded s, Enum a, Bounded a)
          => Transducer s a e -> [s]
deadlocks t =
  [ s | s <- [minBound..maxBound]
      , not (isFinal t s)
      , all (\a -> isNothing (delta t s a)) [minBound..maxBound]
  ]

-- For documentApproval: deadlocks = []  (no deadlocks)
```

### Reachability

Can every state be reached from the initial state?

```haskell
unreachable :: (Enum s, Bounded s, Enum a, Bounded a, Eq s)
            => Transducer s a e -> [s]
unreachable t =
  let reachable = bfsReachable (initial t) (\s -> catMaybes [delta t s a | a <- [minBound..maxBound]])
  in  filter (`notElem` reachable) [minBound..maxBound]
```

### Soundness

A workflow is **sound** (van der Aalst) if:
1. Every state is reachable from the initial state
2. From every reachable state, a final state is reachable
3. No dead transitions (every transition is on some path from initial
   to final)

All three are checkable by graph traversal over the Acceptor:

```haskell
isSound :: (Enum s, Bounded s, Enum a, Bounded a, Eq s)
        => Transducer s a e -> Bool
isSound t =
  null (unreachable t) &&                    -- (1)
  all (canReachFinal t) (reachable t) &&     -- (2)
  all (isOnSomePath t) (allTransitions t)    -- (3)
```

### Path Enumeration

Generate all valid paths through the workflow:

```haskell
-- All paths from initial state to any final state
allPaths :: (Enum s, Bounded s, Enum a, Bounded a, Eq s)
         => Transducer s a e -> [[a]]
allPaths t = dfs (initial t) []
  where
    dfs s path
      | isFinal t s = [reverse path]
      | otherwise   = concat
          [ dfs s' (a : path)
          | a <- [minBound..maxBound]
          , Just s' <- [delta t s a]
          ]
```

For the document approval workflow, this reveals all valid sequences:

```
[Submit, ClaimReview, PassReview, Approve]                      -- happy path
[Submit, ClaimReview, PassReview, Reject]                       -- rejected
[Submit, Withdraw]                                              -- withdrawn
[Submit, ClaimReview, RequestRevision, Revise,
 ClaimReview, PassReview, Approve]                              -- one revision cycle
...                                                             -- more cycles
```

### Workflow Equivalence

Two workflow definitions are **equivalent** if they accept the same
action language and produce the same effect language:

```haskell
equivalent :: (...) => Transducer s1 a e -> Transducer s2 a e -> Bool
equivalent t1 t2 =
  languageEquals (inputProjection t1) (inputProjection t2) &&
  languageEquals (outputProjection t1) (outputProjection t2)
```

This is useful for workflow refactoring — verify that a simplified
workflow accepts exactly the same interactions as the original.

---

## Event-Sourced Workflows

Because a workflow is a transducer, it gets event sourcing for free:

```haskell
workflowDecider = toDecider documentApproval

-- Reconstitute workflow state from its effect history
currentStep = reconstitute workflowDecider
  [NotifyReviewers, AssignReviewer, NotifyAuthorRevision]
-- Just RevisionRequested

-- Full audit trail: the event store IS the workflow history
-- Every transition is recorded as its effect
```

This gives you:
- **Audit trail**: Every action and its effect is in the event store
- **Resumability**: Reconstruct workflow state from history on restart
- **Time travel**: See the workflow state at any point in its history
- **Replay**: Re-process the workflow through a new version of the
  transducer to see how outcomes would differ

---

## Parallel Workflows as Product Transducers

The most common workflow pattern that goes beyond simple sagas is
**parallel branches with a synchronization join**. The transducer
formalism handles this with the product construction.

### Example: Hire Approval (parallel reviews)

A hiring workflow requires both HR approval and budget approval before
an offer can be made. The two approvals happen in parallel.

```haskell
data HRState = HRPending | HRApproved | HRRejected
  deriving (Eq, Show, Enum, Bounded)

data BudgetState = BudgetPending | BudgetApproved | BudgetRejected
  deriving (Eq, Show, Enum, Bounded)

-- Parallel state = product of branch states
type HireState = (HRState, BudgetState)

data HireAction
  = ApproveHR | RejectHR
  | ApproveBudget | RejectBudget
  deriving (Eq, Show, Enum, Bounded)

data HireEffect
  = HRApprovalRecorded | HRRejectionRecorded
  | BudgetApprovalRecorded | BudgetRejectionRecorded
  deriving (Eq, Show, Enum, Bounded)

hireApproval :: Transducer HireState HireAction HireEffect
hireApproval = Transducer
  { delta = \(hr, budget) action -> case action of
      ApproveHR     | hr == HRPending     -> Just (HRApproved, budget)
      RejectHR      | hr == HRPending     -> Just (HRRejected, budget)
      ApproveBudget | budget == BudgetPending -> Just (hr, BudgetApproved)
      RejectBudget  | budget == BudgetPending -> Just (hr, BudgetRejected)
      _                                       -> Nothing

  , omega = \(hr, budget) action -> case action of
      ApproveHR     | hr == HRPending         -> Just HRApprovalRecorded
      RejectHR      | hr == HRPending         -> Just HRRejectionRecorded
      ApproveBudget | budget == BudgetPending  -> Just BudgetApprovalRecorded
      RejectBudget  | budget == BudgetPending  -> Just BudgetRejectionRecorded
      _                                        -> Nothing

  , initial = (HRPending, BudgetPending)
  , isFinal = \case
      (HRApproved,  BudgetApproved) -> True   -- AND-join: both approved
      (HRRejected,  _)              -> True   -- either rejection is final
      (_,           BudgetRejected) -> True
      _                             -> False
  }
```

The AND-join is encoded in `isFinal`: the workflow is complete when
both branches have reached their final states. The product state
naturally tracks progress of both branches independently.

**The input projection reveals all valid action orderings:**

```
[ApproveHR, ApproveBudget]          -- HR first
[ApproveBudget, ApproveHR]          -- Budget first
[ApproveHR, RejectBudget]           -- mixed outcome
[RejectHR]                          -- HR rejects, budget doesn't matter
...
```

The order of parallel actions doesn't matter — the Acceptor accepts
both orderings. This is a formal proof that the parallel branches are
truly independent.

---

## Summary

| Workflow Concept | FST Construction | FST Operation |
|-----------------|-----------------|---------------|
| Sequential steps | Concatenation `T₁ · T₂` | `concatenate` |
| Exclusive choice (XOR-split) | Branching in δ | Native |
| Simple merge (XOR-join) | Shared target state | Native |
| Loop / iteration | Cycle in state graph | Native |
| Parallel split (AND-split) | Product state `(s₁, s₂)` | `union` / product construction |
| Synchronization (AND-join) | `isFinal = f₁ ∧ f₂` | Final state predicate on product |
| Deferred choice | Multiple transitions from one state | Native |
| Milestone | Prerequisite state in δ | Native |
| Deadlock detection | States with no transitions, not final | Graph analysis on Acceptor |
| Soundness verification | Reachability + liveness | Graph traversal |
| Path enumeration | DFS over Acceptor | Generator / exhaustive search |
| Equivalence checking | Language equality of projections | Acceptor comparison |
| Event sourcing | Output projection → Decider | `toDecider` |
| Audit trail | Event store of effects | `reconstitute` |

Workflows are transducers. The routing patterns (parallel, loop,
conditional) are specific FST constructions. The formal operations
(projection, product, concatenation) give you deadlock detection,
soundness verification, and path analysis — guarantees that are
typically the domain of specialized workflow engines like BPMN
validators, delivered here by the same automata theory that gives
us event sourcing.
