# keiki-bench

`tasty-bench` measurements for `keiki`'s pure core. The benchmarks cover
the shipped pure operations — `delta`, `omega`, `step`, `applyEvent`,
and `reconstitute` — on two example aggregates, in both builder and AST
authoring forms.

## Run

From the repository root:

```sh
cabal bench
```

Total wall-clock is ~50 seconds on a development laptop. Every row
ends `OK`; rows in `head-to-head` print a relative ratio (`Nx`)
against their builder-form baseline. Allocation columns appear if
the bench is invoked with GHC's `-T` RTS flag (see "Memory" below).

## What's measured

```
All
  UserReg
    builder         { delta, omega, step, applyEvent, reconstitute }
    ast             { delta, omega, step, applyEvent, reconstitute }
  OrderCart
    builder         { delta, omega, step, applyEvent, reconstitute }
    ast             { delta, omega, step, applyEvent, reconstitute }
  attribution
    compat
      builder       { stepEither, applyEventsEither-32, applyEventsEither-1024 }
      ast           { stepEither, applyEventsEither-32, applyEventsEither-1024 }
    detailed
      builder       { stepDetailedEither, applyEventsDetailedEither-32, applyEventsDetailedEither-1024 }
      ast           { stepDetailedEither, applyEventsDetailedEither-32, applyEventsDetailedEither-1024 }
  head-to-head
    UserReg/ast vs builder/step
    UserReg/ast vs builder/reconstitute
    OrderCart/ast vs builder/step
    OrderCart/ast vs builder/reconstitute
```

There are 20 original operation rows, 12 attribution rows, and 4 head-to-head
rows: 36 leaf benchmarks in total.
The two head-to-head operations (`step`, `reconstitute`) are the
ones with the most signal: `step` exposes the per-transition cost
where `Keiki.Builder`'s `Prelude.lookup` over the `(vertex, edges)`
alist is most visible; `reconstitute` tests whether that overhead
amortises away over a 32-event log.

Single-step fixtures (`urCmd`/`urEvt`/`ocCmd`/`ocEvt`) sit on the
canonical first edge of each log. The replay logs (`urLog`,
`ocLog`) are length 32 each; UserRegistration loops `Resend` 28
times to inflate the trajectory, OrderCart adds 27 `ItemAdded`
events on the happy path.

The `attribution/compat` rows are the pre-change compatibility probes for
ExecPlan 81. They reduce successful `stepEither` and `applyEventsEither`
results to strict scalar values, measure both builder and AST forms, and replay
UserRegistration logs of 32 and 1,024 events. Keep their complete benchmark
paths stable when comparing a post-change run with the captured CSV.

The adjacent `attribution/detailed` rows measure the explicit cost of asking
for edge evidence. The forward digest consumes the selected edge index, mode,
and output-list length. The replay digest uses a strict left fold over every
attribution entry and consumes its edge index, mode, span endpoints, and event
count. Because each benchmark reduces the result to an `Int` under `nf`, the
measurement cannot stop after constructing an outer `Right` or leave the trace
unevaluated.

## Capture and diff a baseline

Capture the current numbers as a CSV:

```sh
cabal bench --benchmark-options "--csv baseline.csv"
```

Make a change, then re-run with the baseline as a comparison
target:

```sh
cabal bench --benchmark-options "--baseline baseline.csv"
```

Each row prints both the new measurement and a multiplicative ratio
against the baseline.

ExecPlan 81's matched allocation run uses a disposable pre-change CSV and
keeps the compatibility paths unchanged:

```sh
cabal bench jitsurei:keiki-bench \
  --benchmark-options='--csv /tmp/keiki-ep81-before.csv +RTS -T -RTS'

cabal bench jitsurei:keiki-bench \
  --benchmark-options='-p /attribution/ --baseline /tmp/keiki-ep81-before.csv --csv /tmp/keiki-ep81-after.csv --fail-if-slower 20 +RTS -T -RTS'
```

The pattern on the second command avoids treating unrelated legacy benchmark
noise as an attribution compatibility failure. The six `compat` names match
the pre-change CSV; the six new `detailed` names have no historical baseline.

## Reading a `bcompare` row

Within `head-to-head`, the comparison is AST-form vs builder-form
of the same operation. A ratio less than 1 means the AST form is
faster; greater than 1 means the builder form is faster. In the
initial baseline, `step` ratios are ≈ 0.55 (AST is ~2× faster on the
per-step path); `reconstitute` ratios are ≈ 0.90 (the gap nearly
vanishes once per-step setup amortises over the 32-event log).

Within `attribution/detailed`, each `bcompare` ratio is detailed operation vs
its compatibility row in the same run. This is the opt-in cost of producing
and strictly consuming attribution, not an erasure-law proof or pass/fail
threshold.

## Memory

To enable allocation reporting, pass `-T` through to the RTS:

```sh
cabal bench --benchmark-options "+RTS -T -RTS"
```

Each row gains "X B allocated, Y B copied, Z MB peak memory"
columns.

For a compatibility regression check, compare the before/after `Allocated`
values at both 32 and 1,024 events. A positive delta that grows with log length
requires inspection of the Core call graph: compatibility replay must seed the
nullary `DiscardTrace` policy and must never construct pending attribution,
public attribution records, or trace list cells. Detailed replay is expected
to show an O(number of completed edges) allocation increase; that is the
documented cost of the trace.

## What's *not* measured

- **`Keiki.Builder.buildTransducer`** itself — the build cost is
  amortised to zero in any production system (it runs once at
  module load), so the benches measure only the *post-build*
  transducer.
- **SBV-backed analyses** (`solveOutput`, `symIsBot`,
  `symSatExt`) — solver wall-clock dominates everything else and
  belongs in separate work focused on symbolic-performance
  characterisation.
- **`Keiki.Composition.compose`** — not covered by this benchmark suite.

## Adding a new aggregate

Follow the shape of `urOps` / `ocOps` in `bench/Bench.hs`: define
a single command and a single event matching the canonical first
edge, define a length-≥32 replay log on the happy path, and call
the helper with the aggregate's transducer. The helper produces
the standard 5-operation matrix in one `bgroup` per form.

The `head-to-head` group's `bcompare` patterns are AWK
expressions over the benchmark's reverse-path; copy one of the
existing entries, swap the path segments, and the new aggregate
will get its own ratio columns.
