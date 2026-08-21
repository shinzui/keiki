---
type: Improvement Request
title: Prove inverse-candidate disjointness over the exact Bool register domain
description: >-
  Extend IR-5's inverse-candidate disjointness proof with a producer-owned exact Bool domain so
  complementary Bool register guards can discharge a same-head inversion ambiguity without
  trusting arbitrary Enum or Eq laws.
timestamp: 2026-08-21T03:52:41Z
requestId: IR-9
status: planned
origin: mori://shinzui/rei
reviews:
  - kind: model
    reviewer: codex
    reviewed_at: 2026-08-21T03:52:41Z
    document_timestamp: 2026-08-21T03:52:41Z
    scope: technical-accuracy
    outcome: approved
    provider: openai
    model: gpt-5
    effort: unspecified
    context: >-
      Validated against Keiki 0.9.0.0, concrete replay candidate selection, Keiro's generated
      default-validation path, and Rei's real three-warning Intention reproducer; approval is for
      the corrected producer-owned Bool domain, not the superseded generic Enum proposal.
---

# Improvement Request: Prove Inverse-Candidate Disjointness Over the Exact Bool Register Domain

## Status

Planned by
[ExecPlan 90](../plans/90-prove-inverse-candidate-disjointness-from-equality-anchors.md).
IR-5 shipped the shared-register disjointness proof and its actionable retained-warning
diagnostics. This request extends that proof only with a closed, producer-owned description of
the standard `Bool` carrier.

The request was initially filed as generic support for finite `Bounded`/`Enum` carriers. Technical
validation rejected that generalisation as a proof boundary. `Typeable` can establish that a
hidden carrier is one particular known type, but it cannot recover arbitrary `Bounded` and `Enum`
dictionaries. Even if those dictionaries were carried, Haskell does not enforce that a consumer's
`Enum` instance visits every inhabitant. Similarly, treating `x == a` as a universal equality
anchor would add an implicit trust in consumer-defined `Eq` laws. Neither is necessary for Rei's
case. Keiki can recognise the standard `Bool` type by `TypeRep` and exhaust the complete list
`[False, True]` while evaluating the exact comparison closures already captured from the guard.

## Context

IR-5 refined `inversionAmbiguityWarnings` so a same-head, same-mode edge pair is reported only when
Keiki cannot prove the reconstructed candidates' guards mutually unsatisfiable. The proof is
carried by `knownRegisterComparison`, which currently admits a register comparison only when
`discoverIntegralDomain` recognises the carrier (`src/Keiki/Core.hs`):

```haskell
discoverIntegralDomain :: forall r. (Typeable r) => Maybe (IntegralDomain r)
discoverIntegralDomain
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Integer) = ...
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Natural) = ...
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Int)     = ...
  | ...  -- Word8/16/32/64, Int32, Int64
  | otherwise = Nothing
```

Anything else lands in the `Nothing` branch and yields:

```text
unsupported register carrier <Type> at position <n>
```

`blockedRegisterConstraintExtraction` turns that outcome into a conservatively retained warning.
`Bool` is not in the integral registry, so the complete two-value domain is unavailable to the
proof.

### The reproducer

Rei's Intention root aggregate is a
[MasterPlan 25](mori://shinzui/rei/masterplans/25-rebase-rei-on-the-keiro-0-13-runtime-and-the-keiro-dsl-language-5-authoring-contract)
consumer being declared at `keiro-dsl` language 5. Its transducer carries a `Bool` register
`isDormant` and three pairs of edges of exactly this shape:

```haskell
-- Auto-wake: recording activity on a dormant intention also wakes it.
B.onCmd inCtorApplyActionRecorded $ \d -> B.do
  B.requireEq #isDormant (lit True)
  B.slot @"isDormant" =: lit False
  B.emit wireActionRecorded    ...
  B.emit wireIntentionAwakened ...
  B.goto vtx

-- Recording activity on an awake intention emits only the activity.
B.onCmd inCtorApplyActionRecorded $ \d -> B.do
  B.requireEq #isDormant (lit False)
  B.emit wireActionRecorded ...
  B.goto vtx
```

Enabling `checkInversionAmbiguity` reports three warnings:

```text
inversion-ambiguity @IntentionActive: edges #4 and #5 out of IntentionActive both emit
"ActionRecorded" as their first event; replay may not be able to attribute an observed
"ActionRecorded" to a unique edge; register proof blocked by unsupported register carrier Bool
at position 0

inversion-ambiguity @IntentionActive: edges #44 and #45 ... both emit "OutcomeRecorded" ...
register proof blocked by unsupported register carrier Bool at position 0

inversion-ambiguity @IntentionCompleted: edges #1 and #2 ... both emit "OutcomeRecorded" ...
register proof blocked by unsupported register carrier Bool at position 0
```

Replay evaluates both candidates' guards against the same pre-event register file before applying
either edge's update. For `False`, only the awake edge can match; for `True`, only the dormant edge
can match. Those are all `Bool` values, so the candidates are disjoint for every concrete register
file. The trailing `IntentionAwakened` remains irrelevant because streaming replay intentionally
inverts only the head event.

### Why the consumer cannot route around it

Rei has carried `checkInversionAmbiguity = False` on this one stream since the keiro 0.3 upgrade,
which trades away real coverage on every other edge pair in a 48-constructor aggregate. A generated
language-5 event stream is built with `mkEventStreamOrThrow` under default validation options;
there is no spec clause that reproduces the opt-out, and the brownfield-adoption ladder forbids
substituting `mkEventStreamUnchecked`.

Retyping `isDormant` as `Natural` would make the proof succeed while misdescribing the domain.
Changing `ActionRecorded` or `OutcomeRecorded` to distinguish the two heads would impose a wire
change, schema-version bump, and upcaster work on stored history to compensate for a producer-side
proof gap. Neither workaround is acceptable.

## Requested Change

Add a small internal exact-finite-domain abstraction beside `IntegralDomain`, and recognise only
the standard `Bool` carrier in this change. The domain must contain the explicit complete list
`[False, True]`; it must not call a consumer-supplied `Enum` instance or infer finiteness from
`Bounded`.

Admit register-versus-literal `PEq` and `PCmp` comparisons when either
`discoverIntegralDomain` or the new exact finite-domain discovery recognises the carrier. For an
exact finite group, decide satisfiability by evaluating the existing typed comparison closures on
every listed inhabitant. Return `RegisterConstraintsUnsatisfiable` only when no inhabitant
satisfies every comparison. A non-empty witness set is satisfiable. Missing domain evidence,
type-alignment failure, and every unsupported guard shape remain unknown.

This closed representation eliminates bound explosion rather than managing it dynamically: the
only newly registered domain has exactly two producer-owned values. Any future carrier addition
must be reviewed as a separate exact-domain extension with a complete producer-owned inhabitant
list and explicit size policy; this request does not establish a generic `Bounded`/`Enum`
mechanism.

The change must preserve all IR-5 and
[ADR-0003](../adr/0003-proof-gates-fail-conservatively.md) constraints:

- A pair is suppressed only when overlap is impossible for every register file and observed head
  event. Unknown, opaque, and unregistered carriers stay warnings.
- Default validation remains pure, solver-free, and microsecond-scale.
- Retained warnings continue naming the first blocking construct. An unregistered carrier keeps
  the existing `unsupported register carrier <Type> at position <n>` wording.
- `validateTransducer`, the `InversionAmbiguity` constructor, the live/replay phase distinction,
  the literal-bottom exemption, and the head-only streaming rule remain source- and
  behavior-compatible. No validation option is added.

## Acceptance

1. A fixture matching Rei's shape -- same source vertex, same mode, same reconstructed command
   constructor, same head wire constructor, and register guards `flag == True` versus
   `flag == False` -- produces no
   `InversionAmbiguity` warning.
2. Replacing the second guard with `PTop` retains the warning and a concrete register file with
   `flag == True` exhibits two replay candidates.
3. Bool ordering uses the same exact domain: a disjoint pair such as `flag < True` versus
   `flag == True` is suppressed, while an overlapping pair such as `flag <= True` versus
   `flag == True` retains its warning.
4. An unregistered carrier retains the existing `unsupported register carrier` wording and
   warning shape. A test must use a non-integral carrier outside the exact registry rather than
   reusing the Bool fixture this change narrows.
5. `PNot (PEq ...)`, including the public `./=` spelling, remains unsupported and retains a
   diagnostic naming `PNot`. This request supports equality and the existing four structural
   `PCmp` relations over Bool; it does not extend negation extraction.
6. Exhaustive property coverage enumerates both Bool register values for every newly suppressed
   relation pair and finds no register/event/mode combination with two concrete candidates.
7. Default validation performs no solver call. Focused latency remains in the existing budget;
   domain evaluation is bounded by exactly two inhabitants times the comparisons in one register
   group.
8. Haddocks explain that Bool suppression is a proof by exhaustion over a producer-owned exact
   domain, not a consequence of equal head names, arbitrary `Enum`, or assumed consumer `Eq` laws.
9. Against a released Keiki containing the change, Rei's real Intention root reports none of the
   three Bool-blocked warnings under default validation, allowing its one-stream opt-out to be
   removed without reshaping events.
10. The change is released on Hackage and tagged upstream so Keiro, `keiro-dsl`, and Rei can adopt
    it from an authoritative version.

## Out of Scope

- Generic discovery of arbitrary `Bounded`/`Enum` carriers through `Typeable`.
- Treating equality literals as universal anchors for unregistered consumer-defined `Eq` types.
- Adding a public finite-domain declaration API or changing the register schema to carry domain
  evidence.
- Extracting constraints through `PNot`, including `./=`.
- Any change to live-first replay semantics, command reconstruction, or runtime stepping.
- Multi-event tails as inversion keys; streaming replay continues to invert only the head.
- Solver-backed proof in default validation. `checkInversionAmbiguitySym` remains the opt-in path
  for anything outside the pure fragment.
- Suppressing warnings from reachability evidence alone.
- `keiro-dsl` syntax or generated validation-policy configuration.

## Compatibility Baseline

Verified against Hackage Keiki 0.9.0.0 and the matching public `v0.9.0.0` upstream tag, which are
the latest authoritative release and tag at validation time. Rei's
[`rei-core`](mori://shinzui/rei/packages/rei-core) resolves `keiki ^>=0.9`. In 0.9.0.0,
`knownRegisterComparison` gates every extracted comparison on `discoverIntegralDomain`, so Bool
falls back to the unsupported-carrier warning.

The requested behavior is an additive validation-precision change: strictly fewer false-positive
warnings inside the newly exact Bool fragment, no new warnings, and no change to forward stepping
or replay. Publication and consumer adoption remain separate authorized release work after the
implementation plan passes.

## References

- Implementation plan:
  [ExecPlan 90](../plans/90-prove-inverse-candidate-disjointness-from-equality-anchors.md).
- Requesting initiative:
  `mori://shinzui/rei/masterplans/25-rebase-rei-on-the-keiro-0-13-runtime-and-the-keiro-dsl-language-5-authoring-contract`.
- Reproducer and consumer acceptance:
  `mori://shinzui/rei/plans/206-author-the-rei-service-workspace-at-keiro-dsl-language-5`
  (Milestone 6, finding S30).
- The proof this extends: [IR-5](prove-inverse-candidates-disjoint-before-reporting-ambiguity.md)
  and [ExecPlan 85](../plans/85-prove-replay-inverse-candidates-disjoint-from-shared-register-conjuncts.md).
- Keiki implementation: `src/Keiki/Core.hs` -- `discoverIntegralDomain`,
  `knownRegisterComparison`, `registerComparisonGroupVerdict`,
  `analyzeCandidateRegisterConstraints`, and `inversionAmbiguityWarnings`.
- Keiki tests: `test/Keiki/ValidationReplayAlignmentSpec.hs` and
  `test/Keiki/ReplayOnlySpec.hs`.
- Conservative proof policy: [ADR-0003](../adr/0003-proof-gates-fail-conservatively.md).
