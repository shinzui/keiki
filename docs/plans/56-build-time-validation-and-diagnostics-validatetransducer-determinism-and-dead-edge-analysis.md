---
id: 56
slug: build-time-validation-and-diagnostics-validatetransducer-determinism-and-dead-edge-analysis
title: "Build-time validation and diagnostics: validateTransducer, determinism, and dead-edge analysis"
kind: exec-plan
created_at: 2026-06-06T14:41:11Z
intention: "intention_01ktensqv9ecmv5cd5jrbcfej7"
master_plan: "docs/masterplans/14-keiki-and-keiki-codec-json-dsl-improvements-surfaced-by-the-seihou-consumer-audit.md"
---

# Build-time validation and diagnostics: validateTransducer, determinism, and dead-edge analysis

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

Today, a person modelling a workflow in keiki can build a transducer (a finite control
graph of states and guarded transitions, plus a register file evolved by each transition)
that has subtle authoring mistakes, and nothing tells them until the mistake bites at
runtime. Three classes of mistake matter to consumers of this library:

1. **Hidden inputs** — a transition consumes information from the command on the wire but
   does not emit it into the output event, so the information cannot be reconstructed on
   replay. keiki already has a checker for this (`checkHiddenInputs` in
   `src/Keiki/Core.hs`), but its warnings are stringly-typed: a source-vertex string and a
   free-text reason. A consumer cannot programmatically inspect *which* command constructor
   or *which* field is missing.

2. **Nondeterminism (ambiguity)** — two transitions leave the *same* state with guards
   that can both be true for the same command. At runtime the engine must pick one; this is
   usually an authoring bug. keiki can already *decide* whether a whole transducer is free
   of this (the `isSingleValuedSym` predicate in `src/Keiki/Symbolic.hs` returns a single
   `Bool`), but a `Bool` does not tell the author *which* pair of edges, leaving *which*
   vertex, with *which* command, overlap.

3. **Dead edges** — a transition that can never fire, most simply because it leaves a state
   the workflow can never reach from its start state. There is no checker for this at all
   today.

After this change, a person can call a single pure function,
`validateTransducer defaultValidationOptions t`, and get back a list of *structured*
warnings covering all three classes. Each warning is a Haskell value with named fields
(source vertex, edge index, kind, detail) that a downstream project can pattern-match on,
print, or assert against. The default path is **pure and cheap** — it runs without the z3
SMT solver — so a project can put `validateTransducer defaultValidationOptions t == []`
directly in a unit test and have it pass or fail in microseconds with no external process.
Symbolic (z3-backed) variants are offered separately for callers who want the precise
answer and are willing to pay for the solver.

You can see it working by building a tiny transducer with (a) a deliberately overlapping
guard pair, (b) an edge leaving an unreachable state, and (c) a clean transducer, then
observing that the first yields a `NondeterministicPair` warning naming both edge indices,
the second yields a `PossiblyDeadEdge` warning, and the third yields the empty list. A test
suite (`test/Keiki/ValidationSpec.hs`) encodes exactly this.

"Term of art" reminders used throughout this plan:

- **Transducer** here means a `SymTransducer` value (defined in `src/Keiki/Core.hs` around
  line 602): a record with `edgesOut :: s -> [Edge phi rs ci co s]` (the outgoing edges of
  each state `s`), `initial :: s` (the start state), `initialRegs :: RegFile rs` (the
  starting register values), and `isFinal :: s -> Bool`. The state type `s` is required to
  be `Bounded` and `Enum` so analyses can enumerate every state via `[minBound .. maxBound]`.
- **Edge** (defined in `src/Keiki/Core.hs` around line 590) is one guarded transition with
  fields `guard :: phi` (the condition, a value in a Boolean-algebra carrier `phi`),
  `update` (how the register file changes — see the warning about its existential type
  below), `output :: [OutTerm rs ci co]` (the list of events emitted; `[]` is an "ε-edge",
  i.e. an edge that emits nothing), and `target :: s` (the destination state).
- **Guard / BoolAlg** — guards are values in a class `BoolAlg phi a` (defined in
  `src/Keiki/Core.hs` around line 527) providing `top`, `bot`, `conj` (conjunction/AND),
  `disj`, `neg`, `models`, and `isBot` (does this guard denote the empty set, i.e. is it
  unsatisfiable?). There are two carriers: the *syntactic* `HsPred rs ci` (its `isBot` only
  recognises the literal `PBot` constructor — an over-approximation, no solver) and the
  *symbolic* `SymPred rs ci` (its `isBot` calls z3 via SBV for an exact answer). The helper
  `withSymPred` (`src/Keiki/Symbolic.hs` ~643) lifts a transducer from the `HsPred` carrier
  to the `SymPred` carrier so the same polymorphic analysis runs symbolically.
- **ε-edge** — an edge whose `output` is `[]`; it changes state and possibly registers but
  emits no event. If such an edge *reads the command* (its `update` references the input),
  the read information is lost, which is the hidden-input case `checkHiddenInputs` already
  flags.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] M1: Add the structured warning vocabulary to `src/Keiki/Core.hs`: `EdgeRef`,
      `ValidationKind`, `TransducerValidationWarning`, `ValidationOptions`,
      `defaultValidationOptions`.
- [ ] M1: Add a structured hidden-input adapter that turns each `HiddenInputWarning` into a
      `TransducerValidationWarning` (carrying the input-constructor name and missing field
      names as structured data, not just a string).
- [ ] M1: Add the `validateTransducer` umbrella that runs the enabled checks and returns the
      unified list; wire the hidden-input component in first.
- [ ] M1: Export the new names from `Keiki.Core`; confirm `checkHiddenInputs` is unchanged
      and still exported.
- [ ] M1: Create `test/Keiki/ValidationSpec.hs`, register it in `keiki.cabal` and
      `test/Spec.hs`; prove the clean transducer yields `[]` and the hidden-input case
      yields a structured warning.
- [ ] M2: Add `checkTransitionDeterminism` (pure, `BoolAlg`-polymorphic) to
      `src/Keiki/Core.hs`, reusing the exact pairing structure of `isSingleValuedSym`.
- [ ] M2: Wire the determinism component into `validateTransducer` (pure `HsPred` path by
      default).
- [ ] M2: Add `checkTransitionDeterminismSym` to `src/Keiki/Symbolic.hs` (lift via
      `withSymPred`).
- [ ] M2: Extend `ValidationSpec` to prove the overlapping pair yields a
      `NondeterministicPair` naming both edge indices and the source vertex; prove the
      mutually-exclusive pair yields nothing under the symbolic path.
- [ ] M3: Add `DeadEdgeOptions`, `checkDeadEdges` (structural reachability via `containers`
      Set) to `src/Keiki/Core.hs`; wire into `validateTransducer`.
- [ ] M3: Extend `ValidationSpec` to prove an edge leaving an unreachable vertex yields a
      `PossiblyDeadEdge`, and a literal-`PBot` guard yields a `PossiblyDeadEdge`.
- [ ] M3: Sketch and (optionally) implement `checkDeadEdgesSym` in `src/Keiki/Symbolic.hs`;
      document the FieldResource-style limit of the structural variant.
- [ ] Final: run `cabal build keiki` and `cabal test keiki-test`; capture transcripts; fill
      Outcomes & Retrospective.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Merge consumer-audit Requirement 1 (richer hidden-input warnings) and
  Requirement 2 (determinism + dead-edge diagnostics) into this single ExecPlan rather than
  two.
  Rationale: `validateTransducer` is the natural umbrella that *runs* the determinism and
  dead-edge checks alongside the (refined) hidden-input check and returns one unified
  warning list. Splitting would force the warning type and the umbrella to be co-designed
  across two plans, which is exactly the coupling self-contained ExecPlans try to avoid.
  Date: 2026-06-06

- Decision: Build `checkTransitionDeterminism` *on top of* the existing pairing structure in
  `isSingleValuedSym` (`src/Keiki/Symbolic.hs` ~620) rather than inventing new pairing
  logic.
  Rationale: `isSingleValuedSym` already enumerates exactly the pairs `(i,e1),(j,e2)` with
  `i<j` per vertex and checks `isBot (guard e1 \`conj\` guard e2)`. The determinism
  diagnostic is the same loop but emitting a warning per overlapping pair instead of folding
  to a single `Bool`. Reusing the structure keeps the two in lockstep: a transducer is
  single-valued iff `checkTransitionDeterminism` returns `[]` under the same carrier.
  Date: 2026-06-06

- Decision: Make the *default* `validateTransducer` path pure (the `HsPred` carrier, no
  solver) and offer separate `…Sym` variants for the z3-backed precision.
  Rationale: The audit's Req 1 explicitly asks for a check that is "cheap and pure so
  projects assert `validateTransducer defaultValidationOptions t == []` in unit tests with
  no z3". A test suite that shells out to z3 on every assertion is slow and adds an external
  dependency to consumers' CI; the pure path keeps the common case free.
  Date: 2026-06-06

- Decision: The pure determinism check is *sound for non-overlap but incomplete for overlap*
  — under `HsPred`, `isBot` only recognises the literal `PBot`, so two non-`PBot` guards are
  conservatively treated as *possibly overlapping*. To avoid drowning authors in false
  positives, the pure check flags a pair **only when it can structurally prove overlap**:
  specifically when the two guards are *the same structural top* (`PTop`) or one of them is
  `PTop`, or they are syntactically identical constructor guards. All other pairs are left to
  the symbolic variant.
  Rationale: Over-approximating "everything not provably disjoint is ambiguous" would flag
  almost every multi-edge vertex and make the warning useless in the pure path. Choosing the
  *under-approximating* direction (only flag provable overlaps) keeps the pure path's
  warnings trustworthy: a `NondeterministicPair` from the pure path is always a real
  problem, while the absence of one does not prove determinism (run the `…Sym` variant for
  that). This direction is documented at the function and in the warning's detail text.
  Date: 2026-06-06

- Decision: `checkDeadEdges` is *structural and conservative*; uncertain results are labelled
  `PossiblyDeadEdge`, never "dead".
  Rationale: Pure structural reachability can prove a vertex is unreachable from `initial`
  (so all its outgoing edges can never fire) and can recognise a literally-`PBot` guard, but
  it cannot reason about register values. The audit's FieldResource scenario — a self-loop
  guarded `available == True` where `available` is set `False` on entry — is *not* catchable
  structurally; only the symbolic variant could prove that guard unsatisfiable in context.
  Labelling everything the structural pass flags as "possibly dead" keeps the diagnostic
  honest.
  Date: 2026-06-06

- Decision: Define a minimal `EdgeRef` (source vertex rendered via `Show`, plus edge index)
  in `Keiki.Core` as the edge-locator for warnings, and note that EP-55 must converge on it.
  Rationale: EP-55 (`docs/plans/55-explainable-step-result-stepeither-and-stepfailure.md`)
  owns the canonical runtime edge-locator/summary record, but as of this writing EP-55 is
  still a skeleton (no `EdgeRef`/`RejectedEdgeSummary` types exist yet). Rather than block on
  it, this plan defines the minimal locator it needs and records the convergence obligation
  in Interfaces and Dependencies, so whichever plan lands second adopts the other's type.
  Date: 2026-06-06


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

You are working in the keiki Haskell library at the repository root
`/Users/shinzui/Keikaku/bokuno/keiki`. The library models event-sourced workflows as
*symbolic-register transducers*. Everything you need lives in two source modules and the
test harness; read them before editing.

`src/Keiki/Core.hs` is the pure core. It defines:

- The Boolean-algebra class `BoolAlg phi a` (~line 527) with `top`, `bot`, `conj`, `disj`,
  `neg`, `models`, and `isBot`. The syntactic carrier instance
  `BoolAlg (HsPred rs ci) (RegFile rs, ci)` (~line 556) defines `conj p q = PAnd p q` and
  `isBot PBot = True; isBot _ = False` — i.e. the pure `isBot` is a *syntactic
  over-approximation* that only recognises the literal `PBot`.
- `Edge` (~line 590), a GADT-style record with `guard`, `update`, `output`, `target`.
  **Important gotcha:** the `update` field is *existentially quantified* over the slot-name
  set it writes, so you cannot use the `update` selector as a function — GHC rejects it with
  "escaped type variables". When you need to inspect an update, pattern-match on the `Edge`
  inside a helper (see the existing `applyEdgeUpdate` ~line 625 and `edgeReadsInput` ~line
  632 for the pattern). Your new code does **not** need to touch `update` except via the
  existing `edgeReadsInput` helper.
- `SymTransducer` (~line 602) with `edgesOut`, `initial`, `initialRegs`, `isFinal`.
- `HiddenInputWarning` (~line 1180): `data HiddenInputWarning = HiddenInputWarning { hiwEdgeSource :: String, hiwReason :: String } deriving (Eq, Show)`.
- `checkHiddenInputs` (~line 1209):
  `checkHiddenInputs :: (Bounded s, Enum s, Show s) => SymTransducer phi rs s ci co -> [HiddenInputWarning]`.
  It enumerates `[minBound .. maxBound]` for the state type, `zip [0..] (edgesOut t s)` for
  the edges, and per edge: for an ε-edge (`output == []`) that reads the input it emits a
  reason `"edge #N: ε-edge with input read in update"`; for a non-empty-output edge it
  groups the output's `OPack`s by input-constructor name and flags any constructor whose
  declared slots are not fully covered by the union of recovered slots. The reason strings it
  emits include the edge index and (for the union-miss case) the constructor name and missing
  slot names. **You must keep this function and its `HiddenInputWarning` type exactly as they
  are and still exported** — the change is additive.

`src/Keiki/Symbolic.hs` is the solver-backed module. It defines:

- `symIsBot :: HsPred rs ci -> Bool` (~line 601): translates a predicate to SBV and asks z3
  whether any model exists; `True` when none does. Wrapped in `unsafePerformIO`.
- `isSingleValuedSym` (~line 620):
  `isSingleValuedSym :: (BoolAlg phi (RegFile rs, ci), Bounded s, Enum s) => SymTransducer phi rs s ci co -> Bool`.
  Its body, which you will mirror in `checkTransitionDeterminism`, is:

  ```haskell
  isSingleValuedSym t = all vertexSV [minBound .. maxBound]
    where
      vertexSV s =
        let es    = edgesOut t s
            ies   = zip [(0 :: Int) ..] es
            pairs = [ (e1, e2)
                    | (i, e1) <- ies
                    , (j, e2) <- ies
                    , i < j
                    ]
        in all (\(e1, e2) -> isBot (guard e1 `conj` guard e2)) pairs
  ```

  It is `BoolAlg`-polymorphic: with the `HsPred` instance `isBot` is the syntactic
  over-approximation; with `SymPred` (reached by lifting the transducer with `withSymPred`)
  it is the z3 decision.
- `withSymPred` (~line 643):
  `withSymPred :: SymTransducer (HsPred rs ci) rs s ci co -> SymTransducer (SymPred rs ci) rs s ci co`.
  It re-wraps every edge's `HsPred` guard as a `SymPred` and leaves the control graph,
  updates, and outputs unchanged.

The build is Cabal-based. `keiki.cabal` declares the `library` stanza (exposed modules
include `Keiki.Core` and `Keiki.Symbolic`; dependencies already include `containers` and
`sbv`) and the `keiki-test` test suite. **keiki core must not gain new heavy dependencies**;
structural reachability uses `Data.Set`/`Data.Map` from the already-present `containers`.

The test harness is `test/Spec.hs`, a **manual aggregator**: there is no `hspec-discover`.
Every spec module is `import qualified`-ed and invoked under an explicit `describe` in
`main`. The test stanza depends on `hspec` only (no QuickCheck or Hedgehog), so all tests are
finite, hand-written enumerations. To add a spec you must (1) create the file under `test/`,
(2) add it to `other-modules` in the `keiki-test` stanza of `keiki.cabal`, and (3) add an
`import qualified` and a `describe …` line in `test/Spec.hs`. The pattern to copy for a
small synthetic transducer is in `test/Keiki/SymbolicSpec.hs` (`synth2Mutex` and
`synth2Overlap` near line 526), which build two-edge transducers over an empty register file
`'[]`, a `Bool` state, and a tiny two-constructor command type `TinyCmd`.

The jitsurei example workspace (`jitsurei/src/Jitsurei/LoanApplication.hs`) is a worked loan
application transducer; it is referenced here as the *kind* of real workflow these checks
protect. The audit's "FieldResource" scenario (a self-loop guarded `available == True` where
`available` is set `False` on entry) is a hypothetical from the consumer audit, not a file in
this repo; it is cited only to illustrate the limit of structural dead-edge analysis.


## Plan of Work

The work is three milestones, each independently buildable and testable. Throughout, every
addition is *additive*: no existing function changes behaviour, and `checkHiddenInputs`,
`isSingleValuedSym`, and `withSymPred` keep their current signatures.

### Milestone M1 — the umbrella and structured hidden-input warnings

Scope: introduce the shared warning vocabulary and the `validateTransducer` entry point,
with only the hidden-input component wired in. At the end of M1 a caller can run
`validateTransducer defaultValidationOptions t` and get a structured list that, for a
transducer with a hidden input, contains a `HiddenInput` warning carrying the source vertex,
edge index, the input-constructor name, and the missing field names — not just a string.

Add to `src/Keiki/Core.hs`, in a new section near the existing `checkHiddenInputs` (after
line ~1300, end of the hidden-input section), the following types. Define `EdgeRef` first; it
is the locator reused by every warning kind.

```haskell
-- | A locator for a single edge: the source vertex (rendered with
-- 'Show', so warnings are carrier-agnostic) and the 0-based index of
-- the edge within @edgesOut t source@. EP-55 owns the canonical
-- runtime edge locator; until it lands, this is the minimal shared
-- type and EP-55 must converge on it (see Interfaces and Dependencies).
data EdgeRef = EdgeRef
  { erSource    :: String   -- ^ @show s@ of the edge's source vertex.
  , erEdgeIndex :: Int      -- ^ 0-based position in @edgesOut t s@.
  } deriving (Eq, Show)

-- | The discriminator carried by every validation warning, with the
-- structured detail each kind needs.
data TransducerValidationWarning
  = HiddenInput
      { tvwEdge        :: EdgeRef
      , tvwInCtor      :: Maybe String   -- ^ input constructor name, if known
      , tvwMissingSlots :: [String]      -- ^ slot/field names left off the wire
      , tvwDetail      :: String         -- ^ human-readable summary
      }
  | NondeterministicPair
      { tvwSource   :: String   -- ^ @show s@ of the common source vertex
      , tvwEdgeA    :: Int      -- ^ first edge index
      , tvwEdgeB    :: Int      -- ^ second edge index
      , tvwInCtor   :: Maybe String  -- ^ overlapping command ctor, if known
      , tvwDetail   :: String
      }
  | PossiblyDeadEdge
      { tvwEdge   :: EdgeRef
      , tvwDetail :: String     -- ^ why it is *possibly* (not certainly) dead
      }
  deriving (Eq, Show)
```

Then the options record and its default:

```haskell
-- | Which checks 'validateTransducer' runs. All default to 'True'.
data ValidationOptions = ValidationOptions
  { failOnEpsilonReadsInput :: Bool  -- ^ run the hidden-input check
  , checkDeterminism        :: Bool  -- ^ run the determinism check
  , checkReachability       :: Bool  -- ^ run the dead-edge check
  } deriving (Eq, Show)

defaultValidationOptions :: ValidationOptions
defaultValidationOptions = ValidationOptions
  { failOnEpsilonReadsInput = True
  , checkDeterminism        = True
  , checkReachability       = True
  }
```

The umbrella runs the enabled components and concatenates their warnings. In M1 only the
hidden-input component is wired; the determinism and dead-edge calls land in M2 and M3.
Define the umbrella so adding components later is a one-line change:

```haskell
validateTransducer
  :: (Bounded s, Enum s, Show s)
  => ValidationOptions
  -> SymTransducer phi rs s ci co
  -> [TransducerValidationWarning]
validateTransducer opts t = concat
  [ if failOnEpsilonReadsInput opts then hiddenInputWarnings t else []
  -- M2: , if checkDeterminism opts then map fromDetWarning (checkTransitionDeterminism t) else []
  -- M3: , if checkReachability opts then map fromDeadWarning (checkDeadEdges defaultDeadEdgeOptions t) else []
  ]
```

Note: `validateTransducer`'s signature does **not** carry a `BoolAlg` constraint, because
the hidden-input and dead-edge components do not need one. The determinism component does
need `BoolAlg`; resolve this in M2 by having `validateTransducer` call the *pure* determinism
check specialised to the `HsPred` carrier. Because the only way `validateTransducer`'s `phi`
can satisfy `conj`/`isBot` is if it is concretely `HsPred`, give `validateTransducer` the
concrete guard type for the determinism/reachability default path:

```haskell
validateTransducer
  :: (Bounded s, Enum s, Show s)
  => ValidationOptions
  -> SymTransducer (HsPred rs ci) rs s ci co
  -> [TransducerValidationWarning]
```

Specialising to `HsPred rs ci` is correct and matches the audit's "cheap and pure, no
solver" requirement: the default umbrella never touches z3. A caller who wants the symbolic
determinism answer calls `checkTransitionDeterminismSym` (M2) directly on
`withSymPred t`. Record this signature choice in the Decision Log when you make the edit.

The structured hidden-input adapter bridges the old stringly warning to the new structured
one. Because `checkHiddenInputs` already produces `[HiddenInputWarning]` (source string +
reason string), the cleanest additive route is a new internal producer that walks the same
data but builds the structured value directly. Implement `hiddenInputWarnings` by factoring
out the *parsing* from the existing reason strings, **or** preferably by adding a small
structured sibling next to `checkHiddenInputs` that returns `EdgeRef`/ctor/slot data without
re-deriving the analysis. The minimal, lowest-risk implementation reuses `checkHiddenInputs`
and parses its reason text:

```haskell
-- | Structured form of the hidden-input check, additive over
-- 'checkHiddenInputs'. Reuses the existing analysis verbatim and lifts
-- each 'HiddenInputWarning' into a 'TransducerValidationWarning',
-- recovering the edge index, input-constructor name, and missing slot
-- names from the existing reason text where present.
hiddenInputWarnings
  :: (Bounded s, Enum s, Show s)
  => SymTransducer phi rs s ci co
  -> [TransducerValidationWarning]
hiddenInputWarnings t =
  [ HiddenInput
      { tvwEdge        = EdgeRef (hiwEdgeSource w) (parseEdgeIndex (hiwReason w))
      , tvwInCtor      = parseInCtor (hiwReason w)
      , tvwMissingSlots = parseMissingSlots (hiwReason w)
      , tvwDetail      = hiwReason w
      }
  | w <- checkHiddenInputs t
  ]
```

Parsing the reason text is brittle, so prefer the stronger alternative if you have the
appetite: lift the *body* of `checkHiddenInputs` into a shared helper that yields structured
fields, and define both `checkHiddenInputs` (formatting to strings, unchanged output) and
`hiddenInputWarnings` (structured) on top of it. Either way, the M1 acceptance is that the
structured warning for a hidden-input edge has the right `erEdgeIndex`, and a non-empty
`tvwMissingSlots` for the union-miss case. Decide which route you take and record it in the
Decision Log.

Export from `Keiki.Core` (add to the module's export list near the existing
`checkHiddenInputs` and `HiddenInputWarning` exports): `EdgeRef(..)`,
`TransducerValidationWarning(..)`, `ValidationOptions(..)`, `defaultValidationOptions`,
`validateTransducer`, and `hiddenInputWarnings`.

Acceptance for M1: `cabal build keiki` succeeds; a new `test/Keiki/ValidationSpec.hs`
asserts that a clean transducer yields `[]` and a hidden-input transducer yields a
`HiddenInput` warning with the expected edge index and missing slots.

### Milestone M2 — determinism diagnostics on the BoolAlg pairing

Scope: add `checkTransitionDeterminism`, the diagnostic-rich, per-vertex presentation of the
property `isSingleValuedSym` decides as a single `Bool`. At the end of M2,
`validateTransducer` includes determinism warnings on its default pure path, and a
solver-backed `checkTransitionDeterminismSym` is available for the exact answer.

Add to `src/Keiki/Core.hs`, near the new validation section, a determinism-specific warning
and the pure check. The check mirrors `isSingleValuedSym`'s pairing exactly but emits a
warning per overlapping pair instead of folding to `Bool`:

```haskell
-- | A determinism warning: two outgoing edges of the same vertex whose
-- guards can both hold. Carries both edge indices and the source vertex.
data DeterminismWarning = DeterminismWarning
  { dwSource :: String  -- ^ @show s@ of the common source vertex
  , dwEdgeA  :: Int     -- ^ first overlapping edge index
  , dwEdgeB  :: Int     -- ^ second overlapping edge index
  , dwDetail :: String
  } deriving (Eq, Show)

-- | Per-vertex, per-pair determinism diagnostic. Reuses the exact
-- pairing structure of 'Keiki.Symbolic.isSingleValuedSym': for every
-- vertex, for every pair @(i,e1),(j,e2)@ with @i<j@, the pair is
-- ambiguous when @guard e1 \`conj\` guard e2@ is *not* 'isBot'.
--
-- Soundness direction: with the pure 'HsPred' carrier, 'isBot' only
-- recognises the literal 'PBot', so this check is under-approximating
-- for overlap — it flags a pair only when it can *prove* overlap (one
-- guard is 'PTop', or the two are syntactically identical). It may MISS
-- real overlaps it cannot prove syntactically; for the exact answer use
-- 'Keiki.Symbolic.checkTransitionDeterminismSym'. Every warning emitted
-- by the pure path is a true positive.
checkTransitionDeterminism
  :: forall phi rs s ci co.
     (BoolAlg phi (RegFile rs, ci), Bounded s, Enum s, Show s)
  => SymTransducer phi rs s ci co
  -> [DeterminismWarning]
checkTransitionDeterminism t =
  [ DeterminismWarning
      { dwSource = show s
      , dwEdgeA  = i
      , dwEdgeB  = j
      , dwDetail = "edges #" <> show i <> " and #" <> show j
                   <> " out of " <> show s <> " have overlapping guards"
      }
  | s <- [minBound .. maxBound]
  , let ies = zip [(0 :: Int) ..] (edgesOut t s)
  , (i, e1) <- ies
  , (j, e2) <- ies
  , i < j
  , not (isBot (guard e1 `conj` guard e2))
  ]
```

The expression `not (isBot (guard e1 \`conj\` guard e2))` is the exact negation of the
per-pair test in `isSingleValuedSym`, so `checkTransitionDeterminism t == []` iff
`isSingleValuedSym t` is `True` under the same carrier. The "soundness direction" comment is
load-bearing: with `HsPred`, `conj p q = PAnd p q` and `isBot (PAnd _ _) = False`, so the
pure check would flag *every* multi-edge vertex if left as-is. That is the
over-approximation the audit warns against. To make the pure path emit only *true positives*,
gate the pure-path emission behind a structural-overlap proof. The simplest correct gate is
to special-case the guards that the syntactic carrier can actually reason about: if either
guard is `PTop`, the pair certainly overlaps; if the two guards are equal (`==` on `HsPred`,
which derives `Eq`) and not `PBot`, they certainly overlap. Implement this as a small helper
used *only* on the `HsPred` carrier path inside `validateTransducer`:

```haskell
-- | Structural over-approximation-free determinism check for the pure
-- 'HsPred' carrier: emits a warning only when overlap is structurally
-- provable (one guard is 'PTop', or the two guards are identical and
-- not 'PBot'). Used by 'validateTransducer' so the pure path yields no
-- false positives. The full, exact check is the symbolic variant.
checkTransitionDeterminismPure
  :: (Bounded s, Enum s, Show s)
  => SymTransducer (HsPred rs ci) rs s ci co
  -> [DeterminismWarning]
```

Its body is the same comprehension but with `provablyOverlap (guard e1) (guard e2)` in place
of `not (isBot …)`, where `provablyOverlap PTop _ = True; provablyOverlap _ PTop = True;
provablyOverlap g1 g2 = g1 == g2 && g1 /= PBot`. Wire `checkTransitionDeterminismPure` into
`validateTransducer` (it is the determinism component), mapping each `DeterminismWarning`
into a `NondeterministicPair`:

```haskell
  , if checkDeterminism opts
      then [ NondeterministicPair
               { tvwSource = dwSource w
               , tvwEdgeA  = dwEdgeA w
               , tvwEdgeB  = dwEdgeB w
               , tvwInCtor = Nothing
               , tvwDetail = dwDetail w
               }
           | w <- checkTransitionDeterminismPure t ]
      else []
```

Set `tvwInCtor` to the overlapping command constructor when both guards are the *same*
`PInCtor ic` (then the name is `icName ic`); leave it `Nothing` for the `PTop` case where no
single constructor is implicated. The acceptance criterion from the audit ("ambiguity
warnings identify both edge indices and the overlapping command constructor if known") is
met: both indices are always present; the constructor name is present when structurally
known.

Add to `src/Keiki/Symbolic.hs`, next to `isSingleValuedSym`, the solver-backed variant. It is
literally `checkTransitionDeterminism` reused at the `SymPred` carrier via the existing
`BoolAlg` polymorphism — no new logic:

```haskell
-- | Solver-backed determinism diagnostic. Lift the transducer with
-- 'withSymPred' and run 'checkTransitionDeterminism' at the 'SymPred'
-- carrier, whose 'isBot' is the exact z3 decision. Unlike the pure
-- path, this catches register-value-dependent overlaps. Requires z3.
checkTransitionDeterminismSym
  :: (Bounded s, Enum s)
  => SymTransducer (HsPred rs ci) rs s ci co
  -> [DeterminismWarning]
checkTransitionDeterminismSym = checkTransitionDeterminism . withSymPred
```

Note this needs `Show s` too (for the warning strings); add it to the constraint. Re-export
`checkTransitionDeterminism`, `DeterminismWarning(..)` from `Keiki.Core` and
`checkTransitionDeterminismSym` from `Keiki.Symbolic` (it can re-export
`DeterminismWarning` from Core, or callers import it from Core).

Acceptance for M2: `validateTransducer defaultValidationOptions overlapT` contains a
`NondeterministicPair` naming both edge indices and the source vertex; a transducer whose two
edges have mutually exclusive `PInCtor` guards yields no determinism warning from the *sym*
variant (the pure path also yields none, since the guards are neither `PTop` nor identical).

### Milestone M3 — dead-edge analysis (structural, with optional symbolic sketch)

Scope: add `checkDeadEdges`, a structural reachability analysis. At the end of M3,
`validateTransducer` flags edges leaving vertices unreachable from `initial` and edges whose
guard is literally `PBot`, labelling each `PossiblyDeadEdge`. An optional
`checkDeadEdgesSym` is sketched (and may be implemented) for the register-value-dependent
cases structural analysis cannot decide.

Add to `src/Keiki/Core.hs` the options and the structural check. Use `Data.Set` from the
already-present `containers` dependency for the reachable-vertex set (add
`import qualified Data.Set as Set` near the top of the module if not already imported; check
first).

```haskell
-- | Options for 'checkDeadEdges'. 'deoFlagBotGuards' also flags edges
-- whose guard is literally 'PBot' (statically unsatisfiable), in
-- addition to edges leaving unreachable vertices.
data DeadEdgeOptions = DeadEdgeOptions
  { deoFlagBotGuards :: Bool
  } deriving (Eq, Show)

defaultDeadEdgeOptions :: DeadEdgeOptions
defaultDeadEdgeOptions = DeadEdgeOptions { deoFlagBotGuards = True }
```

The structural reachability: start from `initial t`, repeatedly add every `target` of every
outgoing edge of an already-reached vertex until the set stops growing. Because `s` is
`Bounded`/`Enum` the whole vertex set is finite, so a fixpoint is reached in at most
`|states|` rounds. An edge is *possibly dead* if its **source** vertex is unreachable, or
(when `deoFlagBotGuards`) its guard is literally `PBot`.

```haskell
-- | Structural, conservative dead-edge analysis. Flags an edge as
-- 'PossiblyDeadEdge' when its source vertex is unreachable from
-- 'initial' (so the edge can never fire) or, optionally, when its
-- guard is the literal 'PBot' (statically unsatisfiable).
--
-- This is purely structural: it follows 'target' pointers and inspects
-- guards syntactically. It CANNOT reason about register values. A
-- self-loop guarded @available == True@ whose @available@ is set
-- 'False' on entry is NOT catchable here (the guard is not literal
-- 'PBot' and the source vertex is reachable) — only
-- 'Keiki.Symbolic.checkDeadEdgesSym' could prove it dead. Therefore
-- every result is labelled "possibly dead", never "dead".
checkDeadEdges
  :: (Bounded s, Enum s, Ord s, Show s)
  => DeadEdgeOptions
  -> SymTransducer (HsPred rs ci) rs s ci co
  -> [DeadEdgeWarning]
```

Define a `DeadEdgeWarning` carrying an `EdgeRef` and a reason, mirroring the other warnings:

```haskell
data DeadEdgeWarning = DeadEdgeWarning
  { dewEdge   :: EdgeRef
  , dewReason :: String
  } deriving (Eq, Show)
```

Reachability helper (finite fixpoint over the `Set`):

```haskell
reachableVertices
  :: (Bounded s, Enum s, Ord s)
  => SymTransducer (HsPred rs ci) rs s ci co
  -> Set.Set s
reachableVertices t = go (Set.singleton (initial t)) [initial t]
  where
    go seen [] = seen
    go seen (s : rest) =
      let succs = [ target e | e <- edgesOut t s ]
          new   = filter (`Set.notMember` seen) succs
      in go (foldr Set.insert seen new) (new ++ rest)
```

The check then enumerates every edge and flags the dead ones:

```haskell
checkDeadEdges opts t =
  let reach = reachableVertices t
  in [ DeadEdgeWarning (EdgeRef (show s) i) reason
     | s <- [minBound .. maxBound]
     , (i, e) <- zip [(0 :: Int) ..] (edgesOut t s)
     , reason <- deadReasons reach s e
     ]
  where
    deadReasons reach s e
      | s `Set.notMember` reach =
          [ "source vertex " <> show s <> " is unreachable from initial" ]
      | deoFlagBotGuards opts && guard e == PBot =
          [ "guard is statically unsatisfiable (PBot)" ]
      | otherwise = []
```

Note `Ord s` is a new constraint (needed for `Set s`); it is satisfiable for the test
fixtures (`Bool`, small enums) and for the jitsurei `LoanAppVertex`. Wire `checkDeadEdges`
into `validateTransducer`'s reachability component, mapping `DeadEdgeWarning` into
`PossiblyDeadEdge`:

```haskell
  , if checkReachability opts
      then [ PossiblyDeadEdge (dewEdge w) (dewReason w)
           | w <- checkDeadEdges defaultDeadEdgeOptions t ]
      else []
```

Because `validateTransducer` now uses `checkDeadEdges`, add `Ord s` to
`validateTransducer`'s constraints.

Finally, sketch the optional symbolic variant in `src/Keiki/Symbolic.hs`. The structural
analysis cannot decide whether a *reachable* edge with a non-`PBot` guard is in fact
unreachable because of register values — the FieldResource scenario. A symbolic variant
would, for each edge, ask z3 whether the guard is satisfiable in *any* register
configuration reachable at the source vertex; if not, the edge is provably dead. Computing
the reachable register configurations exactly is itself hard (it is a fixpoint over the
update semantics), so the honest minimal symbolic check is weaker: flag an edge whose guard
is unsatisfiable *in isolation* (`symIsBot (guard e)`), which catches guards like
`amount > 0 && amount < 0` that the syntactic `isBot` misses but the structural `PBot` check
does not. Implement at least this much:

```haskell
-- | Symbolic dead-edge sketch. Catches edges whose guard is
-- unsatisfiable in isolation (via 'symIsBot'), which the structural
-- 'checkDeadEdges' misses unless the guard is literally 'PBot'. It does
-- NOT compute reachable register configurations, so it still cannot
-- catch the FieldResource case (a guard that is satisfiable in
-- isolation but never under the registers reachable at that vertex);
-- that needs a full reachable-state fixpoint and is left as future work.
checkDeadEdgesSym
  :: (Bounded s, Enum s, Show s)
  => SymTransducer (HsPred rs ci) rs s ci co
  -> [DeadEdgeWarning]
checkDeadEdgesSym t =
  [ DeadEdgeWarning (EdgeRef (show s) i)
      "guard is unsatisfiable in isolation (symbolic)"
  | s <- [minBound .. maxBound]
  , (i, e) <- zip [(0 :: Int) ..] (edgesOut t s)
  , symIsBot (guard e)
  ]
```

Acceptance for M3: a transducer with an edge leaving an unreachable vertex yields a
`PossiblyDeadEdge` for that edge; a transducer with a literal-`PBot` guard yields a
`PossiblyDeadEdge` with the "statically unsatisfiable" reason; the clean transducer yields
none.


## Concrete Steps

All commands run from the repository root `/Users/shinzui/Keikaku/bokuno/keiki`.

First, confirm the baseline builds and tests pass before any change:

```bash
cabal build keiki
cabal test keiki-test
```

Expected: the build succeeds and the existing test suite is green. Example tail:

```text
Finished in 0.0123 seconds
NNN examples, 0 failures
Test suite keiki-test: PASS
```

Make the M1 edits to `src/Keiki/Core.hs` (warning types, options,
`hiddenInputWarnings`, `validateTransducer`) and add the exports. Then create the test file
`test/Keiki/ValidationSpec.hs`, register it in `keiki.cabal` `other-modules`, and add it to
`test/Spec.hs`. Build and test:

```bash
cabal build keiki
cabal test keiki-test
```

The new spec module skeleton (adapt the fixtures from `test/Keiki/SymbolicSpec.hs`):

```haskell
module Keiki.ValidationSpec (spec) where

import Test.Hspec
import Keiki.Core
import Keiki.Symbolic (checkTransitionDeterminismSym, checkDeadEdgesSym)

-- A tiny two-constructor command for guards.
data Cmd = Foo | Bar deriving (Eq, Show)

inCtorFoo :: InCtor Cmd '[]
inCtorFoo = InCtor { icName = "Foo", icMatch = \case Foo -> Just RNil; _ -> Nothing
                   , icBuild = \RNil -> Foo }

inCtorBar :: InCtor Cmd '[]
inCtorBar = InCtor { icName = "Bar", icMatch = \case Bar -> Just RNil; _ -> Nothing
                   , icBuild = \RNil -> Bar }

-- A three-state enum: Start (reachable), Mid (reachable), Orphan (unreachable).
data V = Start | Mid | Orphan deriving (Eq, Ord, Show, Enum, Bounded)

-- (a) overlapping guards out of Start (both PTop).
overlapT :: SymTransducer (HsPred '[] Cmd) '[] V Cmd ()
overlapT = SymTransducer
  { edgesOut = \case
      Start -> [ Edge { guard = PTop, update = UKeep, output = [], target = Mid }
               , Edge { guard = PTop, update = UKeep, output = [], target = Mid } ]
      _ -> []
  , initial = Start, initialRegs = RNil, isFinal = (== Mid) }

-- (b) an edge leaving the unreachable Orphan vertex.
deadT :: SymTransducer (HsPred '[] Cmd) '[] V Cmd ()
deadT = SymTransducer
  { edgesOut = \case
      Start  -> [ Edge { guard = matchInCtor inCtorFoo, update = UKeep, output = [], target = Mid } ]
      Orphan -> [ Edge { guard = PTop, update = UKeep, output = [], target = Start } ]
      _ -> []
  , initial = Start, initialRegs = RNil, isFinal = (== Mid) }

-- (c) a clean transducer: mutually exclusive guards, all vertices reachable.
cleanT :: SymTransducer (HsPred '[] Cmd) '[] V Cmd ()
cleanT = SymTransducer
  { edgesOut = \case
      Start -> [ Edge { guard = matchInCtor inCtorFoo, update = UKeep, output = [], target = Mid }
               , Edge { guard = matchInCtor inCtorBar, update = UKeep, output = [], target = Orphan } ]
      _ -> []
  , initial = Start, initialRegs = RNil, isFinal = (== Mid) }

spec :: Spec
spec = do
  describe "validateTransducer" $ do
    it "clean transducer yields no warnings" $
      validateTransducer defaultValidationOptions cleanT `shouldBe` []
    it "overlapping pair yields a NondeterministicPair naming both indices" $
      validateTransducer defaultValidationOptions overlapT
        `shouldContain` [ NondeterministicPair
                            { tvwSource = "Start", tvwEdgeA = 0, tvwEdgeB = 1
                            , tvwInCtor = Nothing
                            , tvwDetail = anyDetail } ]
        -- If matching tvwDetail exactly is brittle, instead filter the
        -- result for NondeterministicPair and assert on the indices.
    it "edge from unreachable vertex yields a PossiblyDeadEdge" $
      let isDeadOrphan (PossiblyDeadEdge (EdgeRef "Orphan" 0) _) = True
          isDeadOrphan _ = False
      in any isDeadOrphan (validateTransducer defaultValidationOptions deadT)
           `shouldBe` True
```

Note: `cleanT` references `Orphan` as a target, so in `cleanT` `Orphan` is reachable; for the
"clean" assertion to hold, make `cleanT`'s second edge target a reachable vertex (e.g. `Mid`)
so no vertex is orphaned. Adjust the fixture so `cleanT` truly has no unreachable vertex and
no overlapping guards; the matchInCtor guards are mutually exclusive structurally but the
*pure* path will not flag them (they are neither `PTop` nor identical), so `cleanT` yields
`[]`. Verify the exact constructor field names (`InCtor`, `RNil`, `UKeep`, `matchInCtor`,
`PTop`, `PBot`) against `src/Keiki/Core.hs` before relying on them; `matchInCtor` (~line 643)
builds a `PInCtor` guard, `UKeep` is the identity update.

After M2 and M3 edits, re-run the build and test after each milestone. For the symbolic
variants, ensure z3 is on `PATH` (`which z3`); the sbv dependency drives it.

The cabal registration diff:

```diff
                         Keiki.SymbolicSpec
+                        Keiki.ValidationSpec
```

The `test/Spec.hs` additions:

```diff
 import qualified Keiki.SymbolicSpec
+import qualified Keiki.ValidationSpec
```

```diff
   describe "Keiki.Symbolic"                               Keiki.SymbolicSpec.spec
+  describe "Keiki.Core.validateTransducer (EP-56)"        Keiki.ValidationSpec.spec
```


## Validation and Acceptance

The change is internal (it adds analysis functions), so acceptance is demonstrated through
tests that fail before and pass after, plus a worked scenario showing the structured output.

Run the full suite from the repository root:

```bash
cabal test keiki-test
```

Expected, after all three milestones (example):

```text
  Keiki.Core.validateTransducer (EP-56)
    validateTransducer
      clean transducer yields no warnings
      overlapping pair yields a NondeterministicPair naming both indices
      edge from unreachable vertex yields a PossiblyDeadEdge
      literal-PBot guard yields a PossiblyDeadEdge

Finished in 0.0xyz seconds
NNN examples, 0 failures
```

Behavioral acceptance, restated as observable facts:

- `validateTransducer defaultValidationOptions cleanT == []` — a clean transducer produces
  no warnings, and the default path uses **no solver** (it is `HsPred`-only). You can confirm
  no z3 process is spawned by running the test with z3 removed from `PATH`; the
  `validateTransducer` assertions still pass (only the `…Sym` tests require z3).
- For `overlapT`, the result list contains a `NondeterministicPair` with `tvwSource = "Start"`,
  `tvwEdgeA = 0`, `tvwEdgeB = 1` — both edge indices and the common source are named.
- For `deadT`, the result list contains a `PossiblyDeadEdge` whose `EdgeRef` is
  `EdgeRef "Orphan" 0` — the edge leaving the unreachable vertex is flagged, and the wording
  is "possibly dead", never "dead".

A worked transcript a reader can reproduce in `cabal repl keiki-test` (or a `ghci` session
with the library loaded):

```text
ghci> validateTransducer defaultValidationOptions overlapT
[NondeterministicPair {tvwSource = "Start", tvwEdgeA = 0, tvwEdgeB = 1,
  tvwInCtor = Nothing, tvwDetail = "edges #0 and #1 out of Start have overlapping guards"}]

ghci> validateTransducer defaultValidationOptions deadT
[PossiblyDeadEdge {tvwEdge = EdgeRef {erSource = "Orphan", erEdgeIndex = 0},
  tvwDetail = "source vertex Orphan is unreachable from initial"}]

ghci> validateTransducer defaultValidationOptions cleanT
[]
```

The FieldResource limit, demonstrated honestly: a transducer with a reachable self-loop
guarded `available == True` where `available` is set `False` on entry will **not** be flagged
by `validateTransducer` (the source vertex is reachable and the guard is not literal `PBot`).
This is expected and correct for the structural pass. Only a future full reachable-state
symbolic analysis could prove that edge dead; `checkDeadEdgesSym` as sketched catches only
in-isolation-unsatisfiable guards, not register-context-dependent ones. State this in the
test as a documented non-goal (an `it "documents the structural limit"` with a comment), so a
future reader understands the boundary rather than mistaking it for a bug.


## Idempotence and Recovery

Every step is additive and re-runnable. `cabal build` and `cabal test` can be run any number
of times. If an edit to `src/Keiki/Core.hs` does not compile, the existing functions are
untouched (you only added new top-level definitions and export-list entries), so reverting
the new definitions restores a green build. If the cabal `other-modules` entry or the
`test/Spec.hs` wiring is added before the spec file exists, the build fails with a clear
"module not found" — add the file or remove the entry to recover. No data is migrated and no
existing behaviour changes, so there is no destructive operation to roll back.

If the reason-text parsing route for `hiddenInputWarnings` proves fragile (e.g. a reason
string format you did not anticipate), fall back to the stronger route: factor the body of
`checkHiddenInputs` into a structured helper and define both functions on it. Record the
switch in the Decision Log.


## Interfaces and Dependencies

This plan uses only modules and dependencies already present. No new heavy dependency is
added; structural reachability uses `Data.Set` from the existing `containers` dependency, and
the symbolic variants use the existing `sbv` dependency (z3) already wired through
`src/Keiki/Symbolic.hs`.

Types and signatures that must exist at the end of each milestone, by full module path:

At the end of **M1**, in `Keiki.Core`:

- `data EdgeRef = EdgeRef { erSource :: String, erEdgeIndex :: Int }` deriving `Eq`, `Show`.
- `data TransducerValidationWarning = HiddenInput {…} | NondeterministicPair {…} | PossiblyDeadEdge {…}`
  deriving `Eq`, `Show`.
- `data ValidationOptions = ValidationOptions { failOnEpsilonReadsInput, checkDeterminism, checkReachability :: Bool }`
  and `defaultValidationOptions :: ValidationOptions`.
- `hiddenInputWarnings :: (Bounded s, Enum s, Show s) => SymTransducer phi rs s ci co -> [TransducerValidationWarning]`.
- `validateTransducer :: (Bounded s, Enum s, Ord s, Show s) => ValidationOptions -> SymTransducer (HsPred rs ci) rs s ci co -> [TransducerValidationWarning]`
  (the `Ord s` and `HsPred` specialisation are introduced when M2/M3 wire in the
  determinism/reachability components; in M1 the determinism/reachability branches are stubs).
- `checkHiddenInputs` and `HiddenInputWarning` remain exported and unchanged.

At the end of **M2**, in `Keiki.Core`:

- `data DeterminismWarning = DeterminismWarning { dwSource :: String, dwEdgeA, dwEdgeB :: Int, dwDetail :: String }`.
- `checkTransitionDeterminism :: (BoolAlg phi (RegFile rs, ci), Bounded s, Enum s, Show s) => SymTransducer phi rs s ci co -> [DeterminismWarning]`.
- `checkTransitionDeterminismPure :: (Bounded s, Enum s, Show s) => SymTransducer (HsPred rs ci) rs s ci co -> [DeterminismWarning]`.

In `Keiki.Symbolic`:

- `checkTransitionDeterminismSym :: (Bounded s, Enum s, Show s) => SymTransducer (HsPred rs ci) rs s ci co -> [DeterminismWarning]`.

At the end of **M3**, in `Keiki.Core`:

- `data DeadEdgeOptions = DeadEdgeOptions { deoFlagBotGuards :: Bool }` and `defaultDeadEdgeOptions`.
- `data DeadEdgeWarning = DeadEdgeWarning { dewEdge :: EdgeRef, dewReason :: String }`.
- `checkDeadEdges :: (Bounded s, Enum s, Ord s, Show s) => DeadEdgeOptions -> SymTransducer (HsPred rs ci) rs s ci co -> [DeadEdgeWarning]`.

In `Keiki.Symbolic`:

- `checkDeadEdgesSym :: (Bounded s, Enum s, Show s) => SymTransducer (HsPred rs ci) rs s ci co -> [DeadEdgeWarning]`.

Module split rationale: the *pure, structural* analyses (`validateTransducer`,
`checkTransitionDeterminism`, `checkTransitionDeterminismPure`, `checkDeadEdges`, plus all
warning/option types) live in `src/Keiki/Core.hs` because they depend only on the pure core
(`BoolAlg`, `Edge`, `SymTransducer`, `HsPred`, `Data.Set`) and must be usable without z3. The
*solver-backed* variants (`checkTransitionDeterminismSym`, `checkDeadEdgesSym`) live in
`src/Keiki/Symbolic.hs` because they call `withSymPred`/`symIsBot`, which already live there
and pull in SBV. This mirrors the existing split where `isSingleValuedSym` is in
`Keiki.Symbolic` and `BoolAlg`/`Edge` are in `Keiki.Core`.

**Soft dependency on EP-55** (`docs/plans/55-explainable-step-result-stepeither-and-stepfailure.md`):
EP-55 owns the canonical edge-locator/summary record (`EdgeRef`/`RejectedEdgeSummary` and the
runtime `stepEither`/`StepFailure` types). As of this writing EP-55 is still a skeleton — no
such types exist in the tree. This plan therefore defines a minimal `EdgeRef` (source vertex
+ edge index) in `Keiki.Core`. **Convergence obligation:** whichever of EP-55 and EP-56 lands
second must adopt the other's `EdgeRef` rather than defining a parallel one; if EP-55 lands
first, replace this plan's `EdgeRef` with EP-55's. Note the conceptual link: `stepEither`'s
runtime `AmbiguousEdges` failure (EP-55) is the *dynamic* witness of the very overlap that
`checkTransitionDeterminism` proves *statically* here — the two should agree on a transducer
(if the static check is clean under the symbolic carrier, the runtime should never report
`AmbiguousEdges`).

**Soft dependency relationship with EP-60**
(`docs/plans/60-first-class-collection-registers-design-gated.md`): EP-60's invariant INV3
requires `checkHiddenInputs`/`validateTransducer` to *understand collection updates* — a
silent collection mutation whose element data is not on the wire must be flagged. EP-60 is
currently a skeleton. When collection registers land, `validateTransducer` (and the
hidden-input component specifically) must be extended to cover collection `Update`
constructors. This plan deliberately structures the warning machinery so that extension is
*additive*: a new warning kind or a new clause in the hidden-input producer suffices, with no
change to `EdgeRef`, `ValidationOptions`, or the `validateTransducer` umbrella shape. Record
this obligation in EP-60 when it is fleshed out.
