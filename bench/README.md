# keiki-bench

`tasty-bench`-driven measurements for `keiki`'s pure core. Built by
EP-22 to give us numbers for the three pure operations we ship —
`delta`, `omega`, `step`, `applyEvent`, `reconstitute` — on two
example aggregates, in both authoring forms.

## Run

From the repository root:

    cabal bench

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
  head-to-head
    UserReg/ast vs builder/step
    UserReg/ast vs builder/reconstitute
    OrderCart/ast vs builder/step
    OrderCart/ast vs builder/reconstitute
```

20 leaf benches per per-aggregate group, plus 4 in head-to-head.
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

## Capture and diff a baseline

Capture the current numbers as a CSV:

    cabal bench --benchmark-options "--csv baseline.csv"

Make a change, then re-run with the baseline as a comparison
target:

    cabal bench --benchmark-options "--baseline baseline.csv"

Each row prints both the new measurement and a multiplicative ratio
against the baseline.

## Reading a `bcompare` row

Within `head-to-head`, the comparison is AST-form vs builder-form
of the same operation. A ratio less than 1 means the AST form is
faster; greater than 1 means the builder form is faster. As of
EP-22 close, `step` ratios are ≈ 0.55 (AST is ~2× faster on the
per-step path); `reconstitute` ratios are ≈ 0.90 (the gap nearly
vanishes once per-step setup amortises over the 32-event log).

## Memory

To enable allocation reporting, pass `-T` through to the RTS:

    cabal bench --benchmark-options "+RTS -T -RTS"

Each row gains "X B allocated, Y B copied, Z MB peak memory"
columns.

## What's *not* measured

- **`Keiki.Builder.buildTransducer`** itself — the build cost is
  amortised to zero in any production system (it runs once at
  module load), so the benches measure only the *post-build*
  transducer.
- **SBV-backed analyses** (`solveOutput`, `symSat`,
  `symSatExt`) — solver wall-clock dominates everything else and
  belongs in a separate plan focused on symbolic-perf
  characterisation.
- **`Keiki.Composition.compose`** — out of scope for EP-22.

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
