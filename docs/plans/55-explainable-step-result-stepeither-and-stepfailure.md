---
id: 55
slug: explainable-step-result-stepeither-and-stepfailure
title: "Explainable step result: stepEither and StepFailure"
kind: exec-plan
created_at: 2026-06-06T14:41:11Z
intention: "intention_01ktensqv9ecmv5cd5jrbcfej7"
master_plan: "docs/masterplans/14-keiki-and-keiki-codec-json-dsl-improvements-surfaced-by-the-seihou-consumer-audit.md"
---

# Explainable step result: stepEither and StepFailure

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

The keiki library models a workflow or event-sourced process as a *symbolic-register
transducer*: a finite graph of vertices (control states), where each outgoing edge from a
vertex carries a *guard* (a boolean condition over the current register file and the
incoming command), an *update* (how the registers change), and an *output* (the events
emitted). The pure-core entry point that advances such a machine by one input is
`step`, defined in `src/Keiki/Core.hs`. Today `step` has the signature

```haskell
step
  :: BoolAlg phi (RegFile rs, ci)
  => SymTransducer phi rs s ci co
  -> (s, RegFile rs)
  -> ci
  -> Maybe (s, RegFile rs, [co])
```

and returns `Nothing` whenever the machine cannot advance. The problem is that `Nothing`
is overloaded: it conflates three *structurally different* situations that a consumer
needs to tell apart. First, the current vertex may simply have *no outgoing edges at all*
(the process is stuck or has reached a dead end). Second, the vertex may have edges but
*none of their guards match* the given command (the command was rejected — a "wrong input
here" error). Third — and most insidiously — *two or more guards may match the same
command at once*. That last case is a latent correctness bug in the transducer's design:
keiki transducers are meant to be deterministic (single-valued), so two simultaneously
satisfied guards mean the author wrote overlapping conditions, yet `step` silently
swallows this as `Nothing`, indistinguishable from an ordinary rejection.

After this change, a consumer can call a new function `stepEither` and receive a precise,
human-readable explanation of why a step failed, while a successful step returns exactly
the same result `step` would have. The new signature is

```haskell
stepEither
  :: BoolAlg phi (RegFile rs, ci)
  => SymTransducer phi rs s ci co
  -> (s, RegFile rs)
  -> ci
  -> Either (StepFailure s) (s, RegFile rs, [co])
```

where `Left` carries one of three constructors — `NoOutgoingEdges`, `NoMatchingEdge`
(with a per-rejected-edge summary), and `AmbiguousEdges` (with a per-matched-edge summary
listing every edge that fired) — and `Right` carries the identical
`(s, RegFile rs, [co])` triple that `step` returns on success. You can see it working by
building a tiny three-scenario transducer (a vertex with no edges, a vertex where no guard
matches, and a vertex with two overlapping guards) and observing that `stepEither` returns
the correct `Left` for each, and a `Right` byte-identical to `step`'s output on a normal
edge. The existing `step` function is left completely unchanged so that no current caller
breaks; `stepEither` is purely additive.

A secondary, deliberate goal: this plan *owns* the canonical "how do I refer to one
specific edge" vocabulary for the whole codebase. A sibling plan, EP-56 (build-time
validation, `docs/plans/56-build-time-validation-and-diagnostics-validatetransducer-determinism-and-dead-edge-analysis.md`),
needs to name edges for static diagnostics in exactly the same way `stepEither` names them
at runtime. To prevent two parallel, drifting vocabularies, this plan introduces a small
shared record `EdgeRef s` (a vertex plus an edge index) that EP-56 will reuse rather than
reinvent.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] Re-verify the cited code facts by reading `src/Keiki/Core.hs` (2026-06-06: `data Edge` @590, `SymTransducer` @602, `applyEdgeUpdate` @625, `evalOut` @775, `delta` @837, `omega` @856, `step` @875 — all confirmed).
- [x] Add `EdgeRef`, `RejectedEdgeSummary`, `MatchedEdgeSummary`, and `StepFailure` data types in `src/Keiki/Core.hs` near `step` (2026-06-06).
- [x] Add `stepEither` in `src/Keiki/Core.hs`, reusing `applyEdgeUpdate` and `evalOut` so the success payload is identical to `step`'s (2026-06-06).
- [x] Export the four new types (and their fields/constructors) plus `stepEither` from the `Keiki.Core` module header (2026-06-06).
- [x] Build with `cabal build keiki` — clean build (2026-06-06).
- [x] Create `test/Keiki/StepEitherSpec.hs` with finite-enumeration behavioral tests for all four outcomes (2026-06-06; assertions adapted to pattern-match because `RegFile` has no `Eq`/`Show` — see Surprises).
- [x] Register the new spec module in `keiki.cabal` (test stanza `other-modules`) and in `test/Spec.hs` (import + `describe`) (2026-06-06).
- [x] Run `cabal test keiki-test` — `Keiki.Core.stepEither (EP-55)` reports 5/5 passing; full suite 284 examples, 0 failures (2026-06-06).
- [x] Fill in Surprises & Discoveries, Outcomes & Retrospective, and the final Decision Log entries (2026-06-06).


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- `RegFile` has **no** `Eq` or `Show` instance — not even for the empty slot list `'[]`.
  Evidence: `grep -rn "instance .*(Eq|Show) (RegFile" src/Keiki/*.hs` returns nothing, and
  `test/Keiki/CoreSpec.hs` never `shouldBe`-compares a whole `RegFile`; it uses
  `fmap fst (delta ...)` and `case step ... of Just (s', _, [co]) -> ...` to inspect results
  while ignoring the register component. The plan's Context section assumed "`RNil` has an
  `Eq` instance for the empty slot list" — that assumption was wrong. Consequence: `shouldBe`
  on the full `Either (StepFailure V) (V, RegFile '[], [String])` fails to typecheck
  (`No instance for Show (RegFile '[])`), because `shouldBe` needs `Show`/`Eq` for the entire
  `Either`, including the `Right` triple's `RegFile`. The plan anticipated this exact risk
  ("If your `RegFile rs` ... lacks `Eq`, restrict the equality assertions"). Fix: the spec
  pattern-matches the result and `shouldBe`-compares only the `Show`/`Eq`-able parts — the
  `Left` failure value (which carries no register data by design) and, on `Right`, the target
  vertex and the event list. Since `RegFile '[]` has exactly one inhabitant (`RNil`), register
  equality on the success path is trivially preserved, so the `Right`-equals-`step` invariant
  is still meaningfully asserted (target + events identical between `step` and `stepEither`).
- The four new `deriving stock (Eq, Show)` types compiled without any standalone-deriving or
  added head constraints, exactly as the plan predicted — GHC threads the `(Eq s)`/`(Show s)`
  context onto the derived instances automatically.


## Decision Log

Record every decision made while working on the plan.

- Decision: Leave `step` unchanged; add `stepEither` as a new, purely additive function.
  Rationale: Every existing caller relies on the `Maybe` shape. The minimal-API principle
  for this plan is to add explanatory power without forcing a migration. `step` and
  `stepEither` will share the same low-level helpers (`applyEdgeUpdate`, `evalOut`) so the
  success path cannot drift between them.
  Date: 2026-06-06

- Decision: Do not expose private register values in any failure summary.
  Rationale: The consumer audit flagged that diagnostics must summarize, not dump, the
  `RegFile`. A `RejectedEdgeSummary`/`MatchedEdgeSummary` therefore carries an edge
  locator and a guard-outcome note, never raw register contents. This keeps diagnostics
  safe to log and avoids leaking domain data through error channels.
  Date: 2026-06-06

- Decision: Identify edges by `EdgeRef s = EdgeRef { edgeSource :: s, edgeIndex :: Int }`,
  carrying the source vertex as `s` (not a `String`) and the zero-based position in
  `edgesOut t s`.
  Rationale: Carrying `s` directly is more useful to consumers than a pre-stringified
  vertex; the type already flows through `StepFailure s`, so no extra type parameter is
  needed. Stringification (via `Show s`) is left to the *display* layer, not baked into the
  data. The edge index is the only stable, always-available structural handle, since edges
  are an ordered list with no intrinsic identifier.
  Date: 2026-06-06

- Decision: This plan owns the shared edge-locator vocabulary (`EdgeRef`,
  `RejectedEdgeSummary`, `MatchedEdgeSummary`); EP-56 reuses them.
  Rationale: Both the runtime explainer (this plan) and the build-time validator (EP-56)
  must refer to "one specific edge of one specific vertex" identically. Defining the type
  once here prevents two divergent vocabularies. See Interfaces and Dependencies.
  Date: 2026-06-06

- Decision: Do not invent an input-constructor (`InCtor`) accessor for the summaries.
  Rationale: Not every edge carries a `PInCtor` guard, and there is no existing accessor
  that extracts a constructor name from an arbitrary guard. Summaries report only what is
  structurally guaranteed: the source vertex, the edge index, the edge target, and whether
  the guard matched. A best-effort constructor name is explicitly out of scope.
  Date: 2026-06-06

- Decision: Adapt the spec's assertions to pattern-match the `Either` and `shouldBe`-compare
  only the `Show`/`Eq`-able parts, rather than `shouldBe` the whole `Either` as the plan's
  sample code showed.
  Rationale: `RegFile` has no `Eq`/`Show` instance (see Surprises & Discoveries), so the whole
  `Either ... (V, RegFile '[], [String])` is not comparable with `shouldBe`. Adapting the
  assertions — `Left` failures compared in full, `Right` compared on target+events — keeps
  every outcome and the `Right`-equals-`step` invariant behaviorally asserted without
  introducing an out-of-scope `Eq`/`Show (RegFile rs)` instance to keiki core. `RegFile '[]`
  has a single inhabitant, so register equality on the success path is trivially preserved.
  Date: 2026-06-06


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

Delivered exactly the purpose: `Keiki.Core` now exports `stepEither` returning
`Either (StepFailure s) (s, RegFile rs, [co])`, with `StepFailure s` distinguishing
`NoOutgoingEdges`, `NoMatchingEdge [RejectedEdgeSummary s]`, and
`AmbiguousEdges [MatchedEdgeSummary s]`. The shared edge-locator vocabulary — `EdgeRef s`,
`RejectedEdgeSummary s`, `MatchedEdgeSummary s` — is defined and exported here for EP-56 to
reuse. `step` is untouched and the `Right` payload equals `step`'s `Just` payload (verified
by the "matches step exactly" test). `cabal build keiki` is clean and `cabal test keiki-test`
is green (284 examples, 0 failures), with the `Keiki.Core.stepEither (EP-55)` group reporting
5/5.

Gaps / notes for downstream:
- No `Eq`/`Show` instance was added for `RegFile`; the success-path register equality is
  asserted only structurally (single inhabitant of `'[]`). A future plan that wants full
  `Right`-triple equality across non-empty register files would need to add those instances
  (out of scope here).
- EP-56 should import `EdgeRef`/`RejectedEdgeSummary`/`MatchedEdgeSummary` from `Keiki.Core`
  rather than defining parallel types, per the Interfaces section. If it needs a richer
  summary, extend these types here so runtime and build-time diagnostics stay in sync.


## Context and Orientation

This section assumes no prior knowledge of keiki. Read it fully before editing.

keiki is a single-package Haskell library. Its pure core lives in
`src/Keiki/Core.hs`. The build is driven by `keiki.cabal` at the repository root
(`/Users/shinzui/Keikaku/bokuno/keiki`). The test suite is a separate cabal stanza named
`keiki-test` whose entry module is `test/Spec.hs`. There is a Nix dev shell defined in
`flake.nix`, but you may assume plain `cabal` commands work inside the configured shell.

The central data types you will work with, all in `src/Keiki/Core.hs`, are as follows.
Re-read them before editing — line numbers below are approximate as of 2026-06-06.

An **edge** (around line 590) is one transition out of a vertex:

```haskell
data Edge phi rs ci co s where
  Edge
    :: { guard  :: phi
       , update :: Update rs w ci
       , output :: [OutTerm rs ci co]
       , target :: s
       }
    -> Edge phi rs ci co s
```

Here `phi` is the guard carrier (the predicate type), `rs` is the register-slot list, `ci`
is the input/command type, `co` is the output/event type, and `s` is the vertex type. There
is a subtle trap: the `w` type variable on the `update` field (the set of slot names that
update writes) is *existentially quantified* — it appears in `update`'s type but nowhere in
`Edge`'s head. Because of GHC's restriction on record selectors over existential fields
(GHC issue 55876), **you cannot use `update` as a function** (e.g. `update e`). The other
three selectors — `guard`, `output`, `target` — are over non-existential fields and *are*
usable as functions. When you need an edge's fields, prefer a record pattern match such as
`e@Edge{ guard = g, output = outs, target = tgt }`, and route the update through the
existing helper `applyEdgeUpdate` (below) rather than touching `update` directly.

A **transducer** (around line 600) bundles the control graph:

```haskell
data SymTransducer phi rs s ci co = SymTransducer
  { edgesOut    :: s -> [Edge phi rs ci co s]
  , initial     :: s
  , initialRegs :: RegFile rs
  , isFinal     :: s -> Bool
  }
```

`edgesOut t s` returns the ordered list of outgoing edges from vertex `s`. The position of
an edge in that list is the only stable handle we have on it — this is what `EdgeRef`'s
`edgeIndex` records.

The **guard algebra** (around line 527) is the class `BoolAlg phi a` with method
`models :: phi -> a -> Bool`. For the default predicate carrier `HsPred rs ci`, the witness
type `a` is `(RegFile rs, ci)`, so you test whether an edge's guard matches a command by
calling `models (guard e) (regs, ci)`. This is exactly how the existing `delta` and `omega`
decide which edges are active.

The two **field helpers** you must reuse so the success payload matches `step`'s byte for
byte are: `applyEdgeUpdate :: Edge phi rs ci co s -> RegFile rs -> ci -> RegFile rs`
(around line 625; it internally runs the edge's existential `update`), and
`evalOut :: OutTerm rs ci co -> RegFile rs -> ci -> co` (around line 775; it evaluates one
output term against the registers and command). The output of an edge is a *list* of output
terms, so the events an active edge emits are `[ evalOut o regs ci | o <- output e ]`.

The functions this plan sits beside (around lines 835–883):

```haskell
delta
  :: BoolAlg phi (RegFile rs, ci)
  => SymTransducer phi rs s ci co
  -> s -> RegFile rs -> ci -> Maybe (s, RegFile rs)
delta t s regs ci =
  case [ (target e, applyEdgeUpdate e regs ci)
       | e <- edgesOut t s
       , models (guard e) (regs, ci)
       ] of
    [single] -> Just single
    _        -> Nothing

omega
  :: BoolAlg phi (RegFile rs, ci)
  => SymTransducer phi rs s ci co
  -> s -> RegFile rs -> ci -> [co]
omega t s regs ci =
  case [ [ evalOut o regs ci | o <- output e ]
       | e <- edgesOut t s
       , models (guard e) (regs, ci)
       ] of
    [evaluatedOuts] -> evaluatedOuts
    _               -> []

step
  :: BoolAlg phi (RegFile rs, ci)
  => SymTransducer phi rs s ci co
  -> (s, RegFile rs)
  -> ci
  -> Maybe (s, RegFile rs, [co])
step t (s, regs) ci = case delta t s regs ci of
  Nothing          -> Nothing
  Just (s', regs') -> Just (s', regs', omega t s regs ci)
```

Notice both `delta` and `omega` use the *same* filter — "edges whose guard models the
input" — and both collapse the empty list and the 2+ list into a single failure branch.
`stepEither` is essentially this filter, but it inspects the list's length and the original
`edgesOut` list to produce a precise `Left` instead of a collapsed failure.

The term **single-valued** (used below) means: from any vertex, at most one outgoing guard
is satisfiable for any given input. A transducer that is single-valued can never hit the
`AmbiguousEdges` case at runtime. The static checker that proves single-valuedness is
`isSingleValuedSym` in `src/Keiki/Symbolic.hs` (around line 620), which EP-56 builds on.
`AmbiguousEdges` is therefore the *runtime witness* of a single-valuedness violation that
EP-56's static check is meant to catch ahead of time.


## Plan of Work

The work is one milestone with two coherent parts (library code, then tests). It is small
enough not to warrant separate milestones, but the two parts are described in order so a
reader can stop after the first and have a compiling, exported API.

The first part adds the data types and `stepEither` to `src/Keiki/Core.hs`, placed
immediately after `step` (after the existing definition ending around line 883) so the new
code sits with its sibling entry points. We introduce four types. `EdgeRef s` is the
minimal locator: the source vertex and the zero-based edge index. `RejectedEdgeSummary s`
wraps an `EdgeRef s`, the edge's target vertex, and the fact that its guard did not match
(carried explicitly as a `Bool` set to `False`, so the summary type is uniform with the
matched case and a future "rejected because the guard threw" nuance has somewhere to live).
`MatchedEdgeSummary s` wraps an `EdgeRef s` and the target vertex of an edge whose guard
*did* match. `StepFailure s` is the three-way sum:

```haskell
-- | A locator for one outgoing edge: the vertex it leaves from and its
-- zero-based position in @'edgesOut' t source@. This is the canonical
-- edge-identity vocabulary shared with build-time diagnostics (EP-56).
data EdgeRef s = EdgeRef
  { edgeSource :: s
  , edgeIndex  :: Int
  }
  deriving stock (Eq, Show)

-- | Why one outgoing edge was rejected during a step: its locator, its
-- declared target, and whether its guard matched (always 'False' here;
-- the field keeps the shape uniform with 'MatchedEdgeSummary' and leaves
-- room for richer rejection reasons later). Deliberately carries NO
-- register values — diagnostics summarize, they do not dump state.
data RejectedEdgeSummary s = RejectedEdgeSummary
  { rejectedEdge   :: EdgeRef s
  , rejectedTarget :: s
  , rejectedGuard  :: Bool
  }
  deriving stock (Eq, Show)

-- | One outgoing edge whose guard matched during a step: its locator and
-- its declared target. Carries NO register values.
data MatchedEdgeSummary s = MatchedEdgeSummary
  { matchedEdge   :: EdgeRef s
  , matchedTarget :: s
  }
  deriving stock (Eq, Show)

-- | A precise explanation of why a step could not advance.
--
--   * 'NoOutgoingEdges' — the source vertex has no outgoing edges at all.
--   * 'NoMatchingEdge'   — there are outgoing edges, but none matched the
--     command; carries one 'RejectedEdgeSummary' per edge, in declaration
--     order.
--   * 'AmbiguousEdges'   — two or more guards matched the same command, a
--     runtime witness of a single-valuedness violation (the property
--     EP-56's 'checkTransitionDeterminism' proves statically); carries one
--     'MatchedEdgeSummary' per matched edge.
data StepFailure s
  = NoOutgoingEdges s
  | NoMatchingEdge s [RejectedEdgeSummary s]
  | AmbiguousEdges s [MatchedEdgeSummary s]
  deriving stock (Eq, Show)
```

The `Show s` and `Eq s` constraints required by the `deriving stock` clauses are *not*
placed on the data declarations themselves (standalone-deriving would otherwise demand
them at every use site even where unneeded). The `deriving stock (Eq, Show)` on each type
is fine because GHC only requires the instances for `s` at the point an `Eq`/`Show` method
is actually *called*; the derived instance carries the `(Eq s) =>` / `(Show s) =>`
constraint automatically. If GHC complains, this is the place to look — but the standard
`deriving stock` form is expected to work without standalone deriving.

Then `stepEither` itself. It must walk `edgesOut t s` *with positions* so it can build
`EdgeRef`s, partition into matched and unmatched, and branch on the matched count:

```haskell
-- | Like 'step', but returns a precise 'StepFailure' explanation on the
-- 'Left' instead of collapsing every failure into 'Nothing'. On the
-- 'Right' it returns EXACTLY the triple 'step' returns. 'step' is left
-- unchanged; this is purely additive.
stepEither
  :: BoolAlg phi (RegFile rs, ci)
  => SymTransducer phi rs s ci co
  -> (s, RegFile rs)
  -> ci
  -> Either (StepFailure s) (s, RegFile rs, [co])
stepEither t (s, regs) ci =
  case zip [0 ..] (edgesOut t s) of
    [] -> Left (NoOutgoingEdges s)
    indexed ->
      let matched =
            [ (i, e)
            | (i, e) <- indexed
            , models (guard e) (regs, ci)
            ]
      in case matched of
           [] ->
             Left $ NoMatchingEdge s
               [ RejectedEdgeSummary
                   { rejectedEdge   = EdgeRef { edgeSource = s, edgeIndex = i }
                   , rejectedTarget = target e
                   , rejectedGuard  = False
                   }
               | (i, e) <- indexed
               ]
           [(_, e)] ->
             let !regs' = applyEdgeUpdate e regs ci
                 outs   = [ evalOut o regs ci | o <- output e ]
             in Right (target e, regs', outs)
           _ ->
             Left $ AmbiguousEdges s
               [ MatchedEdgeSummary
                   { matchedEdge   = EdgeRef { edgeSource = s, edgeIndex = i }
                   , matchedTarget = target e
                   }
               | (i, e) <- matched
               ]
```

Note three correctness points. The success branch computes `regs'` and `outs` using the
*same* helpers and the *same* pre-update `regs`/`ci` arguments that `delta` and `omega`
use, which guarantees the `Right` payload equals `step`'s `Just` payload exactly (the
existing `step` evaluates outputs against the pre-update `regs`, and so do we). The output
list is `[ evalOut o regs ci | o <- output e ]`, mirroring `omega` precisely. We never read
`update` as a selector; the existential update flows only through `applyEdgeUpdate`, which
sidesteps GHC-55876.

The second part exports the new names and adds tests. In the module header of
`src/Keiki/Core.hs`, add a new export group next to the existing
`step`/`reconstitute`/`applyEvent` group (around lines 116–121). Export `stepEither`, the
`StepFailure (..)` type with all constructors, and the three summary record types with
their fields: `EdgeRef (..)`, `RejectedEdgeSummary (..)`, `MatchedEdgeSummary (..)`.

The tests go in a new module `test/Keiki/StepEitherSpec.hs`, modeled on the fixture style
already used in `test/Keiki/CoreSpec.hs`. That existing spec constructs a minimal
`Bool`-input transducer; we will construct a slightly richer one with three relevant
vertices to exercise all four outcomes (see Concrete Steps for the exact fixture). The new
module must be registered in two places: the `other-modules` list of the `keiki-test`
stanza in `keiki.cabal`, and both the `import qualified` line and a `describe ...` call in
`test/Spec.hs`. The repo's test suite is a *manual aggregator* — there is no
`hspec-discover`, and the only test dependency is `hspec` (no QuickCheck or Hedgehog), so
all "property" assertions must be written as *finite enumerations* of concrete inputs, not
randomized generators.

At the end of this milestone, `cabal build keiki` and `cabal test keiki-test` both succeed,
and the new spec demonstrates each `StepFailure` constructor plus the `Right`-equals-`step`
invariant.


## Concrete Steps

All commands run from the repository root `/Users/shinzui/Keikaku/bokuno/keiki`.

First, re-verify the cited facts so the code you write matches the current tree:

```bash
grep -n "data Edge\|data SymTransducer\|^delta\|^omega\|^step\|applyEdgeUpdate\|^evalOut\|class BoolAlg" src/Keiki/Core.hs
```

You should see the `Edge`/`SymTransducer` declarations, the `delta`/`omega`/`step`
definitions, and the helper signatures, near the line numbers cited in Context and
Orientation. If they have moved substantially, adjust your insertion points accordingly but
keep the logic identical.

Next, edit `src/Keiki/Core.hs`: add the four data types and `stepEither` immediately after
the existing `step` definition (the block ending around line 883), using the code shown in
Plan of Work verbatim. Then add the exports to the module header next to the existing
`step` export group:

```haskell
    -- * Pure-layer entry points (effects-boundary note)
  , step
  , stepEither
  , StepFailure (..)
  , EdgeRef (..)
  , RejectedEdgeSummary (..)
  , MatchedEdgeSummary (..)
  , reconstitute
```

Build the library:

```bash
cabal build keiki
```

Expected: a clean build. If GHC reports that `update` is "not in scope as a record
selector" or references GHC-55876, you accidentally used `update e` somewhere — replace it
with `applyEdgeUpdate`. If it complains about missing `Eq`/`Show` for `s`, confirm you used
`deriving stock (Eq, Show)` on each new type and did not add unnecessary constraints to the
data heads.

Now create the test module. Write `test/Keiki/StepEitherSpec.hs` with a fixture that has
three relevant vertices. Use an `Int`-keyed vertex type and a `Bool` command so guards are
trivial to write with `PTop`/`PBot`. The fixture below uses no registers (`'[]`) and a
`String` output, mirroring `CoreSpec`'s `synthetic`:

```haskell
module Keiki.StepEitherSpec (spec) where

import Test.Hspec
import Keiki.Core

-- Vertices: 0 has two always-true edges (ambiguous); 1 has one
-- always-false edge (no match); 2 has no edges; 3 has one always-true
-- edge (the normal accepting case).
data V = V0 | V1 | V2 | V3 | VEnd
  deriving stock (Eq, Show)

-- A no-op output term is awkward to build generically; instead each
-- edge below uses an empty output list ([]), so a successful step emits
-- no events. That keeps the fixture free of WireCtor/InCtor plumbing
-- while still exercising the Right path.
fixture :: SymTransducer (HsPred '[] Bool) '[] V Bool String
fixture = SymTransducer
  { edgesOut = \case
      V0 -> [ Edge { guard = PTop, update = UKeep, output = [], target = VEnd }
            , Edge { guard = PTop, update = UKeep, output = [], target = V3   }
            ]
      V1 -> [ Edge { guard = PBot, update = UKeep, output = [], target = VEnd } ]
      V2 -> []
      V3 -> [ Edge { guard = PTop, update = UKeep, output = [], target = VEnd } ]
      VEnd -> []
  , initial     = V0
  , initialRegs = RNil
  , isFinal     = (== VEnd)
  }

spec :: Spec
spec = do
  describe "stepEither" $ do
    it "reports NoOutgoingEdges for a vertex with no edges" $
      stepEither fixture (V2, RNil) True
        `shouldBe` Left (NoOutgoingEdges V2 :: StepFailure V)

    it "reports NoMatchingEdge with one rejected summary per edge" $
      stepEither fixture (V1, RNil) True
        `shouldBe`
          Left (NoMatchingEdge V1
                  [ RejectedEdgeSummary
                      { rejectedEdge   = EdgeRef { edgeSource = V1, edgeIndex = 0 }
                      , rejectedTarget = VEnd
                      , rejectedGuard  = False
                      }
                  ])

    it "reports AmbiguousEdges listing every matched edge" $
      stepEither fixture (V0, RNil) True
        `shouldBe`
          Left (AmbiguousEdges V0
                  [ MatchedEdgeSummary
                      { matchedEdge   = EdgeRef { edgeSource = V0, edgeIndex = 0 }
                      , matchedTarget = VEnd
                      }
                  , MatchedEdgeSummary
                      { matchedEdge   = EdgeRef { edgeSource = V0, edgeIndex = 1 }
                      , matchedTarget = V3
                      }
                  ])

    it "returns Right with the same target/regs/events as a normal edge" $
      stepEither fixture (V3, RNil) True
        `shouldBe` Right (VEnd, RNil, [])

    it "Right payload matches step exactly on the accepting edge" $
      (stepEither fixture (V3, RNil) True)
        `shouldBe`
          maybe (error "step returned Nothing") Right
                (step fixture (V3, RNil) True)
```

The last assertion encodes the key invariant behaviorally: on an edge where `step` succeeds,
`stepEither` returns `Right` wrapping the *identical* triple. Because `RegFile '[]` is
`RNil` (it has an `Eq` instance for the empty slot list) and the output type is `String`,
`shouldBe` can compare the whole triple directly. If your `RegFile rs` for a non-empty `rs`
lacks `Eq`, restrict the equality assertions to the empty-register fixture as done here.

Register the module in `keiki.cabal` by adding `Keiki.StepEitherSpec` to the
`other-modules` list of the `keiki-test` stanza (alongside `Keiki.CoreSpec` near line 100):

```diff
                         Keiki.CoreSpec
+                        Keiki.StepEitherSpec
                         Keiki.DeciderSpec
```

Register it in `test/Spec.hs` with an import and a `describe` call:

```diff
 import qualified Keiki.CoreSpec
+import qualified Keiki.StepEitherSpec
```

```diff
   describe "Keiki.Core"                                   Keiki.CoreSpec.spec
+  describe "Keiki.Core.stepEither (EP-55)"                Keiki.StepEitherSpec.spec
```

Run the tests:

```bash
cabal test keiki-test
```

Expected transcript (abridged):

```text
Keiki.Core.stepEither (EP-55)
  stepEither
    reports NoOutgoingEdges for a vertex with no edges
    reports NoMatchingEdge with one rejected summary per edge
    reports AmbiguousEdges listing every matched edge
    returns Right with the same target/regs/events as a normal edge
    Right payload matches step exactly on the accepting edge

Finished in N.NNNN seconds
NNN examples, 0 failures
```


## Validation and Acceptance

Acceptance is behavioral and is fully encoded by `test/Keiki/StepEitherSpec.hs`. After the
edits, running `cabal test keiki-test` from `/Users/shinzui/Keikaku/bokuno/keiki` must show
zero failures, and the `Keiki.Core.stepEither (EP-55)` group must report all five examples
passing.

The four distinct outcomes that must be observed are: calling `stepEither` on a vertex with
no outgoing edges returns `Left (NoOutgoingEdges <vertex>)`; calling it on a vertex whose
single edge has a never-satisfied guard returns `Left (NoMatchingEdge <vertex> [<one
rejected summary>])` with the rejected summary's `edgeIndex` equal to `0`; calling it on a
vertex with two always-satisfied guards returns `Left (AmbiguousEdges <vertex> [<two
matched summaries>])` with `edgeIndex` `0` and `1` in declaration order; and calling it on
a vertex with exactly one satisfied guard returns `Right (<target>, <regs>, <events>)`.

The single most important acceptance property is the `Right`-equals-`step` invariant: on
any input where the original `step` returns `Just triple`, `stepEither` must return
`Right triple` with the identical triple. The final test in the spec asserts this directly
by comparing `stepEither`'s result against `Right`-wrapping `step`'s result on the same
input. This proves the change is effective beyond compilation: the new function preserves
the old behavior on the success path while adding explanatory power on the failure path.

To prove the tests are meaningful rather than vacuous, you may temporarily break the
implementation (for example, swap `NoOutgoingEdges` and `NoMatchingEdge`, or evaluate
outputs against `regs'` instead of `regs`) and confirm a specific example fails; then
revert. Do not commit the deliberately broken state.


## Idempotence and Recovery

All steps are additive and safe to repeat. The library edit adds new declarations and new
export entries; re-running it is a no-op if the names already exist (GHC will report
"duplicate definition" or "duplicate export", which tells you the step was already applied —
remove the duplicate, do not re-add). The test edits add one new module and two registration
lines; if `cabal` reports the module is already listed, the registration is already done.

If `cabal build keiki` fails midway, no source is left half-written as long as you applied
the `stepEither` block and the export additions as single edits; re-read
`src/Keiki/Core.hs` around `step` and around the export list to confirm both halves landed.
If `cabal test keiki-test` fails to find `Keiki.StepEitherSpec`, the cause is almost always
a missing entry in `keiki.cabal`'s `other-modules` — add it and re-run. Nothing in this
plan is destructive; there are no migrations, no file deletions, and no changes to existing
behavior, so recovery is simply re-applying the missing edit.


## Interfaces and Dependencies

This plan touches only the `keiki` package; it adds no new library dependencies. The test
stanza continues to depend solely on `hspec` (no QuickCheck, no Hedgehog), and all
assertions are finite enumerations.

At the end of the milestone, the following must exist and be exported from `Keiki.Core`
(module `src/Keiki/Core.hs`):

```haskell
data EdgeRef s = EdgeRef { edgeSource :: s, edgeIndex :: Int }
  deriving stock (Eq, Show)

data RejectedEdgeSummary s = RejectedEdgeSummary
  { rejectedEdge :: EdgeRef s, rejectedTarget :: s, rejectedGuard :: Bool }
  deriving stock (Eq, Show)

data MatchedEdgeSummary s = MatchedEdgeSummary
  { matchedEdge :: EdgeRef s, matchedTarget :: s }
  deriving stock (Eq, Show)

data StepFailure s
  = NoOutgoingEdges s
  | NoMatchingEdge s [RejectedEdgeSummary s]
  | AmbiguousEdges s [MatchedEdgeSummary s]
  deriving stock (Eq, Show)

stepEither
  :: BoolAlg phi (RegFile rs, ci)
  => SymTransducer phi rs s ci co
  -> (s, RegFile rs)
  -> ci
  -> Either (StepFailure s) (s, RegFile rs, [co])
```

These types reuse the existing `Keiki.Core` machinery only: `SymTransducer`, `Edge`,
`BoolAlg`/`models`, and the helpers `applyEdgeUpdate` and `evalOut`. No part of
`Keiki.Symbolic` or any other module is modified.

Integration with EP-56 (build-time validation,
`docs/plans/56-build-time-validation-and-diagnostics-validatetransducer-determinism-and-dead-edge-analysis.md`):
**this plan (EP-55) owns the canonical edge-locator and edge-summary vocabulary.** EP-56's
build-time diagnostics also need to identify a specific edge (source vertex plus edge index
plus a short guard/target summary), and it **must reuse `EdgeRef s`** (and, where it needs a
per-edge summary, `RejectedEdgeSummary s` / `MatchedEdgeSummary s`) rather than defining a
parallel `EdgeRef`/`EdgeSummary` type. `EdgeRef s = EdgeRef { edgeSource :: s, edgeIndex ::
Int }` is the concrete integration artifact EP-56 consumes. If EP-56 finds it needs a
richer summary, it should extend the types here (in `Keiki.Core`) so both the runtime and
build-time paths stay in sync.

There is a deeper correspondence worth stating for the next contributor: the
`AmbiguousEdges` case that `stepEither` detects at *runtime* is the exact same property that
EP-56's determinism check proves *statically*. EP-56's `checkTransitionDeterminism` is built
on `isSingleValuedSym` in `src/Keiki/Symbolic.hs` (around line 620), which establishes that
no two outgoing guards from any vertex can be simultaneously satisfiable. A transducer that
passes EP-56's static determinism check can therefore *never* produce a `Left
(AmbiguousEdges ...)` from `stepEither`. The two are dual: EP-55 is the runtime witness, EP-56
is the static proof of the same single-valuedness invariant.
