---
type: Improvement Request
title: Prove inverse-candidate disjointness over finite enumerated register carriers
description: >-
  Extend IR-5's inverse-candidate disjointness proof past the integral fragment so a guard pair
  over a finite enumerated register carrier — `Bool` first — can discharge a same-head inversion
  ambiguity instead of blocking on an unsupported carrier.
timestamp: 2026-08-20T00:00:00Z
requestId: IR-9
status: proposed
origin: mori://shinzui/rei
---

# Improvement Request: Prove Inverse-Candidate Disjointness Over Finite Enumerated Register Carriers

## Status

Proposed. IR-5 shipped the disjointness proof and its actionable retained-warning diagnostics, and
both work exactly as specified — this request was found by *reading* one of those diagnostics. What
is missing is coverage: the proof's supported fragment is the integral domain, so the smallest and
most common disjoint guard pair a consumer can write is the one it cannot prove.

## Context

IR-5 refined `inversionAmbiguityWarnings` so a same-head, same-mode edge pair is reported only when
Keiki cannot prove the reconstructed candidates' guards mutually unsatisfiable. The proof is
carried by `knownRegisterComparison`, which admits a register comparison only when
`discoverIntegralDomain` recognises the carrier (`src/Keiki/Core.hs:4129`):

```haskell
discoverIntegralDomain :: forall r. (Typeable r) => Maybe (IntegralDomain r)
discoverIntegralDomain
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Integer) = …
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Natural) = …
  | Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Int)     = …
  | …  -- Word8/16/32/64, Int32, Int64
  | otherwise = Nothing
```

Anything else lands in the `Nothing` branch and yields:

```text
unsupported register carrier <Type> at position <n>
```

which `blockedRegisterConstraintExtraction` turns into a conservatively retained warning.

`Bool` is not in that list, so the *simplest possible* disjoint guard pair — `x == True` against
`x == False` — is unprovable. That is not an edge case in the two-element domain; it is the whole
domain.

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
  B.emit wireActionRecorded    …
  B.emit wireIntentionAwakened …
  B.goto vtx

-- Recording activity on an awake intention emits only the activity.
B.onCmd inCtorApplyActionRecorded $ \d -> B.do
  B.requireEq #isDormant (lit False)
  B.emit wireActionRecorded …
  B.goto vtx
```

Enabling `checkInversionAmbiguity` reports three warnings and every one of them names the reason:

```text
inversion-ambiguity @IntentionActive: edges #4 and #5 out of IntentionActive both emit
"ActionRecorded" as their first event; replay may not be able to attribute an observed
"ActionRecorded" to a unique edge; register proof blocked by unsupported register carrier Bool
at position 0

inversion-ambiguity @IntentionActive: edges #44 and #45 … both emit "OutcomeRecorded" …
register proof blocked by unsupported register carrier Bool at position 0

inversion-ambiguity @IntentionCompleted: edges #1 and #2 … both emit "OutcomeRecorded" …
register proof blocked by unsupported register carrier Bool at position 0
```

The guards are complementary on one register. The two edges can never both fire, and replay always
has exactly one candidate. Keiki is not wrong to warn — it is being conservative exactly as
designed — but the fragment it can prove over stops one type short of the case.

### Why the consumer cannot route around it

Rei has been carrying `checkInversionAmbiguity = False` on this one stream since the keiro 0.3
upgrade, which trades away real coverage on every other edge pair in a 48-constructor aggregate.
That was tolerable while the stream was hand-assembled. It stops being available at language 5:
a generated event stream is built with `mkEventStreamOrThrow` under *default* validation options,
there is no spec clause that reproduces the opt-out, and the brownfield-adoption ladder forbids
substituting `mkEventStreamUnchecked`. So the aggregate cannot be declared at all while this
warning stands.

The two local workarounds are both worse than the problem:

- **Retype the register.** `isDormant :: Natural` with `0`/`1` would be provable today, and Rei's
  registers are not persisted, so nothing stored would move. But `Bool` is one of `keiro-dsl`'s six
  direct scalars, so the declaration would then read `isDormant Natural = 0` — misdescribing the
  domain in a file whose entire purpose is to describe it. Every other consumer with a boolean flag
  faces the same trade.
- **Reshape the edges.** Making each pair's head event distinguishable means adding a field to
  `ActionRecorded` and `OutcomeRecorded`, which are 3,095 and 16 stored events respectively. That is
  a wire change, a schema-version bump, and an upcaster rung — to work around a checker fragment.

Neither is a fix; both are a consumer paying for a producer-side gap.

## Requested Change

Extend the register-constraint fragment past `discoverIntegralDomain` so that a carrier with a
finite, enumerable set of inhabitants can participate in the disjointness proof, and admit `Bool`
as the first such carrier.

The minimum that unblocks the reproducer is equality and inequality over `Bool`. A natural
generalisation, if it costs little more, is any carrier the producer can enumerate soundly —
`Bounded`+`Enum` types reachable through `Typeable`, evaluated by exhaustion over the (small)
inhabitant set rather than by the interval arithmetic the integral fragment uses.

Constraints this must keep, all inherited from IR-5 and
[ADR-0003](../adr/0003-proof-gates-fail-conservatively.md):

- **No unsound suppression.** A pair is suppressed only when overlap is impossible for every
  register file and observed head event. Unknown, opaque, and unenumerable carriers stay warnings.
- **No solver.** Default validation stays pure, z3-free, and microsecond-scale. A two-element
  domain is decided by exhaustion, not by SMT.
- **No bound explosion.** Exhaustive evaluation must be capped, and a carrier whose inhabitant set
  exceeds the cap must fall back to the existing blocked outcome with a diagnostic that says so
  rather than silently timing out.
- **The diagnostic stays actionable.** A retained warning still names the blocking construct. This
  request exists *because* that diagnostic named `Bool` precisely enough to diagnose from the
  outside; do not regress it.
- **API source compatibility.** `validateTransducer`, the `InversionAmbiguity` warning
  constructor's shape, the live/replay phase distinction, the literal-bottom exemption, and the
  head-only streaming inversion rule all stay as they are. No new validation option.

## Acceptance

1. A fixture matching Rei's shape — same source vertex, same mode, same head wire constructor,
   register guards `flag == True` versus `flag == False` — produces no `InversionAmbiguity`
   warning.
2. Replacing the second guard with `PTop` restores the warning, because the candidates overlap when
   `flag == True`.
3. A guard pair over a three-or-more-inhabitant `Bounded`/`Enum` carrier is proved disjoint when it
   is disjoint and retained when it is not, or — if enumerated support is deliberately limited to
   `Bool` in this change — the wider carrier retains its warning with a diagnostic naming the
   limitation, and that limitation is stated in the Haddocks.
4. A carrier with no finite enumeration retains the existing `unsupported register carrier`
   warning, unchanged in wording and shape.
5. Default validation performs no solver call and stays within its existing latency budget;
   the exhaustion cap is documented and has a test at the boundary.
6. Property tests compare every newly-suppressed pair against concrete candidate evaluation over
   the carrier's full inhabitant set and find no state/event with two candidates.
7. Haddocks explain that the enumerated fragment is a proof by exhaustion over a finite domain, and
   that suppression remains a proof of candidate disjointness rather than a claim about equal head
   names.
8. The change is released on Hackage and tagged upstream so Keiro, `keiro-dsl`, and Rei can adopt
   it from an authoritative version.

## Out of Scope

- Any change to live-first replay semantics or to what replay attributes.
- Multi-event tails as inversion keys; streaming replay still inverts only the head. (Rei's pair
  *is* distinguishable by its tail — one emits a trailing `IntentionAwakened` — and that is
  deliberately not the argument this request makes.)
- Solver-backed proof in default validation. `checkInversionAmbiguitySym` remains the opt-in path
  for anything this fragment cannot decide.
- Suppressing warnings from reachability evidence alone.
- `keiro-dsl` syntax, generated validation-policy configuration, or any spec clause that would
  reproduce a per-stream opt-out. Making the opt-out expressible is the wrong fix for this and is
  not requested here.

## Compatibility Baseline

Verified against Keiki 0.9.0.0, which is what
[Rei's `rei-core`](mori://shinzui/rei/packages/rei-core) resolves (`keiki ^>=0.9`). At that
version `knownRegisterComparison` gates every register comparison on `discoverIntegralDomain`, and
`Bool` is absent from it. The requested behaviour is an additive validation-precision change:
strictly fewer warnings, no new ones, and no change to runtime stepping or replay.

## References

- Requesting initiative:
  `mori://shinzui/rei/masterplans/25-rebase-rei-on-the-keiro-0-13-runtime-and-the-keiro-dsl-language-5-authoring-contract`.
- Reproducer and consumer acceptance:
  `mori://shinzui/rei/plans/206-author-the-rei-service-workspace-at-keiro-dsl-language-5`
  (Milestone 6, finding S30).
- The proof this extends: IR-5,
  `prove-inverse-candidates-disjoint-before-reporting-ambiguity.md`.
- Keiki implementation: `src/Keiki/Core.hs` — `discoverIntegralDomain`,
  `knownRegisterComparison`, `blockedRegisterConstraintExtraction`, `inversionAmbiguityWarnings`.
- Keiki tests: `test/Keiki/ValidationReplayAlignmentSpec.hs` (which already asserts the
  `unsupported register carrier` message this request narrows).
- Conservative-failure policy: [ADR-0003](../adr/0003-proof-gates-fail-conservatively.md).
