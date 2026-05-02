---
id: 22
slug: performance-benchmarks-via-tasty-bench-with-a-realistic-order-cart-aggregate
title: "Performance benchmarks via tasty-bench with a realistic Order/Cart aggregate"
kind: exec-plan
created_at: 2026-05-02T18:40:44Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
---

# Performance benchmarks via tasty-bench with a realistic Order/Cart aggregate

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

`keiki`'s pure core (`Keiki.Core.delta`, `omega`, `step`,
`reconstitute`, `applyEvent`) has no measured baseline. The two
existing example aggregates — `Keiki.Examples.EmailDelivery` (1
command, 1 event, 2 vertices) and `Keiki.Examples.UserRegistration`
(5 commands, 5 events, 5 vertices) — are sized for tutorial
comprehension, not for stressing the interpreter. As a result:

1. We cannot answer "what does a single `step` cost?" or "how
   does replay scale with log length?" with numbers.
2. We cannot tell whether `Keiki.Builder` introduces measurable
   *runtime* overhead vs. the hand-written AST form. (The builder
   assembles `edgesOut` via a `Prelude.lookup` alist
   (`src/Keiki/Builder.hs:677`); the AST form uses a `\case`
   (`src/Keiki/Examples/UserRegistration.hs:377`). Whether this
   difference matters at realistic vertex counts is an open
   question.)
3. There is no fixture realistic enough to drive a meaningful
   benchmark. The existing aggregates' canonical event logs are
   3–5 events long.

This plan delivers three things:

1. A `bench` cabal stanza wired with `tasty-bench`, runnable via
   `cabal bench`.
2. A new realistic example aggregate
   `Keiki.Examples.OrderCart` (≈10 commands, ≈10 events, ≈8
   vertices, ≈11 registers) that doubles as a richer authoring
   showcase alongside `UserRegistration`. Builder-authored *and*
   AST-authored forms are both shipped, mirroring the existing
   `userReg` / `userRegAST` pair, and verified byte-identical by
   an `OrderCartBuilderSpec`.
3. A `bench/Bench.hs` benchmark module that exercises the five
   pure-core operations (`delta`, `omega`, `step`, `reconstitute`,
   `applyEvent`) over a generated event log of configurable
   length (default ≥256 events) on the OrderCart aggregate, with
   a head-to-head group comparing the builder-form `orderCart`
   transducer against the AST-form `orderCartAST` on identical
   workloads. UserRegistration is also benched for cross-aggregate
   reference.

After this plan, a contributor runs:

    cabal bench

…and gets a printed table of allocation- and time-anchored
measurements per operation per aggregate per form
(builder/AST), with `tasty-bench`'s built-in baseline-comparison
feature usable across runs. The `bench/README.md` (small, one
page) records how to read the table and reproduce a baseline.

The user-visible improvement is verified by:

1. `cabal build` clean under GHC 9.12.x.
2. `cabal test` still green at 141 examples (post-EP-21 baseline)
   plus N new examples added by `OrderCartBuilderSpec` and
   `OrderCartSpec` (≈4–6 cases — the count is an outcome, not a
   target).
3. `cabal bench` runs to completion in under ~60 seconds on the
   development host, printing `OK` for every benchmark and a
   table of timings.
4. Every benchmark group has at least one entry per pure-core
   operation; the head-to-head group reports a relative ratio
   (`tasty-bench`'s `bcompare`) between builder and AST forms on
   `step` and `reconstitute`.
5. The `OrderCart` aggregate is at least 8× the size of
   `EmailDelivery` measured in command-ctor count (≥ 8 vs 1) and
   at least 2× `UserRegistration` (≥ 10 vs 5), and ships with a
   canonical event log of ≥ 32 events for benchmark replay.


## Progress

This section tracks granular progress. Update at every stopping point: tick
completed items with a date, split partial items into "done" and "remaining"
entries, add new items as discovered.

- [x] M0 — Prerequisites: `cabal build` and `cabal test` clean
  on the post-EP-21 baseline (141 tests). Record the Decision
  Log entry "M0 baseline". (2026-05-02)
- [x] M1 — `tasty-bench` dependency + bench stanza scaffold.
  Added `benchmark keiki-bench` stanza in `keiki.cabal` with
  `tasty-bench >= 0.4 && < 0.6` (corpus is 0.5; widened the
  caret bound the plan suggested to admit both 0.4.x and 0.5.x).
  Created `bench/Bench.hs` with a smoke benchmark; `cabal bench`
  runs `OK` in 2.38s. (2026-05-02)
- [x] M2 — `Keiki.Examples.OrderCart` aggregate (builder form +
  AST form, mirroring the `userReg`/`userRegAST` shape). Ships
  with `Keiki.Examples.OrderCartBuilderSpec` (byte-identical
  equivalence) and `Keiki.Examples.OrderCartSpec` (one
  end-to-end replay through the canonical event log). Test
  count rose from 141 to 149 (+8 new cases). 10 commands,
  10 events, 8 vertices, 11 registers, 12 edges. (2026-05-02)
- [x] M3 — Real benchmark module: replaced the M1 smoke bench
  with grouped benches for `delta`, `omega`, `step`,
  `reconstitute`, `applyEvent`, exercised across both example
  aggregates and both forms (UserReg / OrderCart × builder /
  AST). Added a head-to-head `bcompare` group on builder vs AST
  for `step` and `reconstitute`. 24 benches, ≈48s wall-clock.
  (2026-05-02)
- [ ] M4 — Documentation closure: a one-page `bench/README.md`
  on how to run, interpret, and capture a baseline (referencing
  `tasty-bench`'s `--baseline` and `--csv` flags). Update
  `docs/foundations/06-where-to-go-next.md` with a one-liner
  pointer at "Benchmarking" if such a section is appropriate;
  otherwise add a brief mention to the top-level `README.md` /
  `CLAUDE.md` if those exist.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- M3: builder-form `step` is roughly 2× slower than the AST
  form. Concretely, on the development host (macOS arm64,
  GHC 9.12.3, `-O1`):

      UserReg/builder/step   ≈ 50.6 ns
      UserReg/ast/step       ≈ 28.9 ns   (0.57× builder)
      OrderCart/builder/step ≈ 57.9 ns
      OrderCart/ast/step     ≈ 30.5 ns   (0.52× builder)

  Most of the gap is in 'delta' (the underlying transition
  step): builder ≈ 48–56 ns vs AST ≈ 27–28 ns. The likely
  cause is the `Prelude.lookup` over an alist that
  `Keiki.Builder.buildTransducer` uses to materialise
  `edgesOut` (`src/Keiki/Builder.hs:677`), versus the
  hand-written `\case` in the AST forms. The plan flagged this
  as an open question in the Purpose section; the bench now
  *measures* it. The `reconstitute` overhead amortises away —
  builder/AST gap on the 32-event log shrinks to 0.87–0.94×.

- The performance gap is *only* visible on the per-step path
  (`delta`/`omega`/`step`/`applyEvent`). On the full-replay
  path (`reconstitute`), per-step setup dominates the
  alist-lookup overhead enough that the two forms run within
  ~10% of each other. This argues that the alist lookup is the
  hot spot worth chasing if a future plan optimises the
  builder.


## Decision Log

The seed entries below capture decisions reached while drafting this plan.
Subsequent decisions made during implementation append below them with a date.

- Decision: Domain for the realistic aggregate is **Order/Cart**
  (shopping-cart / e-commerce order lifecycle), not banking or
  hotel-booking.
  Rationale: shopping-cart is the conventional textbook example
  for event-sourced aggregates (cited across DDD/CQRS literature
  and most event-store tutorials), so the resulting fixture
  doubles as didactic material that future readers recognise.
  The lifecycle (Empty → OpenWithItems → Reserved → Paid →
  Shipped → Delivered, plus Cancelled / Refunded branches) maps
  cleanly to ≈8 vertices and gives natural shape to ≈10 commands
  / events without being contrived.
  Date: 2026-05-02

- Decision: Ship both a builder-form (`orderCart`) and an
  AST-form (`orderCartAST`) of the new aggregate, with a
  byte-identical equivalence spec, mirroring the existing
  `userReg`/`userRegAST` pair.
  Rationale: the builder vs AST head-to-head benchmark
  (Validation #4 in Purpose) requires both forms to exist for
  the same aggregate. Repeating the pattern from
  `UserRegistrationBuilderSpec` keeps the equivalence-test
  contract uniform and gives the bench module two independent
  inputs that produce the same `SymTransducer` shape.
  Date: 2026-05-02

- Decision: The benchmark stanza is `benchmark keiki-bench`
  (cabal stanza type), separate from the test suite.
  Rationale: `cabal bench` is the conventional invocation;
  combining bench + test into one stanza forces every CI run
  to pay for benchmark execution. `tasty-bench`'s docs
  (`/Users/shinzui/Keikaku/hub/haskell/tasty-bench-project/tasty-bench/README.md:88-101`)
  show the canonical `benchmark`-stanza shape and we follow it.
  Date: 2026-05-02

- Decision: Use `whnf` (or `nf` where the result is a small
  Showable record) rather than introduce `NFData` instances
  across `Keiki.Core` data types just for benchmarking.
  Rationale: `RegFile`, `SymTransducer`, `OutTerm`, `Update`,
  and `Edge` have no `NFData` instances today (verified —
  `grep -rn "NFData\|deepseq" src test` returns no hits in
  the library). Adding instances is a wide diff that would
  pollute the AST with a `deepseq` dep; `whnf` on `Just (s',
  regs')` (where `regs'` is itself a tuple-shaped `RegFile`)
  exercises the spine sufficiently for the operations we
  benchmark, and `nf` on `Snapshot` tuples (already used by
  `Keiki.Examples.UserRegistrationSpec`) is a fine way to
  fully evaluate a register file when needed. If a future
  benchmark needs deeper forcing, an `NFData` derivation can
  be added then.
  Date: 2026-05-02

- Decision: The benchmark exercises the *post-build*
  transducer's per-step cost, not the build-time cost of
  `B.buildTransducer` itself.
  Rationale: `buildTransducer` runs once at module load (CAF
  evaluation) per program lifetime. Its cost is amortised to
  zero in any realistic event-sourced system. The interesting
  question is per-event cost, which is what `delta` /
  `omega` / `step` / `applyEvent` measure. A separate
  `bgroup "construction"` benching `B.buildTransducer …` could
  be added later if there is a reason to care; not in scope
  here.
  Date: 2026-05-02

- Decision: SBV-backed analyses (`Keiki.Symbolic.solveOutput`,
  `checkHiddenInputs` over symbolic inputs, `KnownInCtors`-driven
  witness extraction) are out of scope for the M3 benchmark
  module.
  Rationale: solver invocations are dominated by z3 and
  introduce wall-clock noise that swamps the in-process per-step
  cost we want to measure. Solver-bound benchmarks belong in a
  separate plan focused on symbolic-analysis perf
  characterisation.
  Date: 2026-05-02

- Decision: The OrderCart canonical event log is hand-authored
  (deterministic, ≥32 events) rather than property-generated.
  Rationale: a fixed log makes the bench output stable across
  runs and easy to explain; a property-generated log adds noise
  (different shapes per run) and a hidden dependency on a
  generator implementation. Length 32 is a balance: large enough
  for `reconstitute` to amortise per-step setup, small enough
  to fit in one screenful for review. The exact length is an
  outcome, not a hard target — M3 settles it.
  Date: 2026-05-02

- Decision: No new build-time `mori` dependencies beyond
  `tasty-bench`. `tasty` is pulled transitively by `tasty-bench`;
  no need to depend on it explicitly.
  Rationale: minimum-surface principle. Adding `tasty` directly
  is harmless but signals an intent to use other `tasty`
  ingredients; we use only `tasty-bench`'s `defaultMain` /
  `bgroup` / `bench` / `bcompare`, which are all re-exported.
  Date: 2026-05-02

- Decision: M0 baseline recorded. `cabal build` is up to date;
  `cabal test` reports `141 examples, 0 failures` in 0.3166s.
  Line counts: `src/Keiki/Examples/UserRegistration.hs` is 471
  lines; `src/Keiki/Examples/EmailDelivery.hs` is 223 lines.
  These anchor the post-EP-21 starting point against which M2's
  test-count rise (≥145) will be measured.
  Date: 2026-05-02

- Decision: event renaming. Five OrderCart event constructors
  (`Reserved`, `Shipped`, `Delivered`, `Cancelled`, `Refunded`)
  collide with same-named vertex constructors of `OrderVertex`;
  GHC rejects duplicate data-constructor names within a module
  even when the constructors live in distinct sum types. Renamed
  the conflicting events with an `Order` prefix:
  `OrderReserved`, `OrderShipped`, `OrderDelivered`,
  `OrderCancelled`, `OrderRefunded`. Vertex names match the
  plan literally (`Empty`, `OpenWithItems`, `Reserved`, `Paid`,
  `Shipped`, `Delivered`, `Cancelled`, `Refunded`). The plan's
  narrative event names (without prefix) are deviated; the
  prefix encodes "this is an event about the Order, not the
  vertex it lands in".
  Date: 2026-05-02

- Decision: register simplification — `cartItems :: [CartItem]`
  collapsed to `itemCount :: Word32`. The plan called for a list
  register; encoding "append" as a `Term` requires `TApp2 (:)`
  with a constructed `CartItem`, and "remove by sku" requires a
  filter helper that adds noise without exercising any new
  interpreter path the bench cares about. A `Word32` counter
  evolved by `TApp1 (+ 1)` / `TApp1 (subtract 1)` exercises the
  same `Update` shape (a register write whose RHS reads the
  register itself) at materially less authoring overhead. The
  register count is 11, matching the plan's "≈11 registers".
  Date: 2026-05-02

- Decision: no `KnownInCtors OrderCmd` instance. The `SomeInCtor`
  data constructor demands `ExtractRegFile ifs`, which transitively
  requires `Sym t` for every slot type `t`. The curated `Sym`
  registry covers `Bool`, `Int`, `Integer`, `Text`, `UTCTime` —
  not `Word16`, `Word32`, or `Word64`, three types `OrderCartRegs`
  uses (basis-point discount, item count, fixed-point currency).
  Two paths considered: (a) widen `Keiki.Symbolic` with new `Sym`
  instances, (b) skip the `KnownInCtors` instance for OrderCmd.
  Chose (b) because: M3 declares SBV-bound analyses out of scope
  for the bench, the `Sym` instances would be a public-surface
  widening that belongs in its own plan, and the pure-core
  operations the bench measures (`delta`, `omega`, `step`,
  `applyEvent`, `reconstitute`) are unaffected. The OrderCart
  module's Haddock records the omission and points at this entry.
  Date: 2026-05-02

- Decision: nine vertices considered, eight chosen. An earlier
  draft inserted a `RefundPending` vertex between `Paid` and
  `Refunded` so that `RequestRefund` and `ProcessRefund` would
  both contribute non-trivial transitions. Collapsed to
  `RequestRefund` self-looping on `Paid` (emit-only, no register
  write) so the vertex count lands at exactly 8 per the plan.
  `ProcessRefund` remains the actual refund step (Paid →
  Refunded with `refundedAt` set).
  Date: 2026-05-02

- Decision: per-scenario logs in `OrderCartBuilderSpec`. The
  aggregate has three terminal vertices (`Delivered`,
  `Cancelled`, `Refunded`); a single canonical log walks one of
  them. The equivalence spec ships three deterministic logs —
  happy-path (9 events ending in `Delivered`), cancel-path (2
  events), refund-path (5 events) — so all three terminal
  branches are exercised. The bench-side `canonicalLog` (M3) is
  inflated to ≥32 events on the happy path only; that's where
  per-step amortisation matters.
  Date: 2026-05-02


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

This section gives a complete novice everything they need to follow the plan
without prior context.

### What `tasty-bench` is

`tasty-bench` (homepage:
`https://hackage.haskell.org/package/tasty-bench`; corpus
checkout on this host:
`/Users/shinzui/Keikaku/hub/haskell/tasty-bench-project/tasty-bench/`)
is a single-file, criterion-API-compatible benchmark framework
with one upstream dep (`tasty`). The benchmark surface used here
is the four functions in `Test.Tasty.Bench`:

- `defaultMain :: [Benchmark] -> IO ()` — entry point.
- `bgroup :: String -> [Benchmark] -> Benchmark` — labelled
  grouping.
- `bench :: String -> Benchmarkable -> Benchmark` — one
  measurement.
- `nf :: NFData b => (a -> b) -> a -> Benchmarkable` and
  `whnf :: (a -> b) -> a -> Benchmarkable` — the two ways to
  force a function-of-one-argument under measurement.

`bcompare`, used in M3's head-to-head group, takes a tasty
pattern that names a baseline benchmark and a new benchmark; the
output table prints a relative ratio.

The reference for benchmarks-stanza wiring is the package's
own README at lines 88–101 of the path above.

### What `keiki`'s pure core looks like (the things we benchmark)

`src/Keiki/Core.hs` is the AST + interpreter. The five user-facing
pure operations:

- `delta :: SymTransducer p rs v ci co -> v -> RegFile rs -> ci ->
   Maybe (v, RegFile rs)` — single-step transition.
  (`src/Keiki/Core.hs:590`)
- `omega :: SymTransducer p rs v ci co -> v -> RegFile rs -> ci ->
   Maybe co` — single-step output extraction.
  (`src/Keiki/Core.hs:606`)
- `step :: SymTransducer p rs v ci co -> (v, RegFile rs) -> ci ->
   Maybe (v, RegFile rs, Maybe co)` — combined transition + output.
  (`src/Keiki/Core.hs:625`)
- `applyEvent :: SymTransducer p rs v ci co -> v -> RegFile rs ->
   co -> Maybe (v, RegFile rs)` — replay one event (inverts
   `omega` by walking `OutFields` against the carried `InCtor`).
  (`src/Keiki/Core.hs:642`)
- `reconstitute :: SymTransducer p rs v ci co -> [co] ->
   Maybe (v, RegFile rs)` — full-log replay via `applyEvent`.
  (`src/Keiki/Core.hs:660`)

The benchmark module exercises each with realistic inputs.

### What the example aggregates look like today

`Keiki.Examples.EmailDelivery` (`src/Keiki/Examples/EmailDelivery.hs`):

- 1 command (`SendEmail`), 1 event (`EmailSent`), 2 vertices
  (`EmailPending`, `EmailSentVertex`), 3 registers
  (`emailRecipient`, `emailSubject`, `emailSentAt`).
- Both `emailDelivery` (builder) and `emailDeliveryAST` (AST)
  forms exist; equivalence asserted by
  `test/Keiki/Examples/EmailDeliveryBuilderSpec.hs`.

`Keiki.Examples.UserRegistration` (`src/Keiki/Examples/UserRegistration.hs`):

- 5 commands (`StartRegistration`, `ConfirmAccount`,
  `ResendConfirmation`, `FulfillGDPRRequest`, `Continue`), 5
  events (`RegistrationStarted`, `ConfirmationEmailSent`,
  `AccountConfirmed`, `ConfirmationResent`, `AccountDeleted`),
  5 vertices (`PotentialCustomer`, `Registering`,
  `RequiresConfirmation`, `Confirmed`, `Deleted`), 5 registers.
- Canonical event log: 5 events
  (`test/Keiki/Examples/UserRegistrationSpec.hs:34-41`).
- Both `userReg` (builder) and `userRegAST` (AST) forms exist;
  equivalence asserted by
  `test/Keiki/Examples/UserRegistrationBuilderSpec.hs`.

The new `Keiki.Examples.OrderCart` follows the same template: a
section per command/event/vertex/register, plus
`deriveAggregateCtors` and `deriveWireCtors` splices, plus
`orderCart` (builder) and `orderCartAST` (AST) values.

### The Order/Cart aggregate (M2's design target)

Domain: a single online order's lifecycle. Vertices, commands,
events, and registers are designed so that each command exercises
at least one register write and at least one vertex transition,
the canonical log walks every vertex at least once, and the
"happy path" + "cancellation path" + "refund path" all appear.

Vertices (8):

- `Empty`              — nothing in cart yet.
- `OpenWithItems`      — items added, no checkout yet.
- `Reserved`           — inventory reserved, awaiting payment.
- `Paid`               — payment confirmed, awaiting fulfilment.
- `Shipped`            — shipment dispatched.
- `Delivered`          — terminal happy-path state.
- `Cancelled`          — terminal abort state.
- `Refunded`           — terminal refund state (post-Paid).

Commands (10):

- `AddItem`           (sku, quantity, price, at)
- `RemoveItem`        (sku, at)
- `ApplyDiscount`     (code, percentBp, at) — bp = basis points.
- `Reserve`           (reservationId, at)
- `ConfirmPayment`    (paymentRef, amountPaid, at)
- `Ship`              (carrier, trackingId, at)
- `Deliver`           (at)
- `Cancel`            (reason, at)
- `RequestRefund`     (reason, at) — only valid post-`Paid`.
- `ProcessRefund`     (refundRef, amountRefunded, at)

Events (10): one per command, with payload mirroring the
command's payload (with the customary "verbed" past-tense
naming: `ItemAdded`, `ItemRemoved`, `DiscountApplied`,
`Reserved`, `PaymentConfirmed`, `Shipped`, `Delivered`,
`Cancelled`, `RefundRequested`, `Refunded`).

Registers (11):

- `cartItems`     :: [CartItem] — persistent list, mutated by
  `AddItem` / `RemoveItem`. (`CartItem` is a small product type
  internal to the module.)
- `discountBp`    :: Word16 — discount in basis points.
- `reservationId` :: Text
- `paymentRef`    :: Text
- `amountPaid`    :: Word64 — fixed-point currency.
- `shippingCarrier` :: Text
- `trackingId`    :: Text
- `shippedAt`     :: UTCTime
- `deliveredAt`   :: UTCTime
- `cancelledAt`   :: UTCTime
- `refundedAt`    :: UTCTime

Note: not every command writes to every register; many writes
are slot-disjoint per edge so the static `Disjoint` check is
naturally satisfied. The canonical event log walks the happy
path (Empty → OpenWithItems → Reserved → Paid → Shipped →
Delivered) plus a side-trip through Cancelled and Refunded by
forking the log into a sequence per scenario.

### How the benchmark stanza is wired

`tasty-bench`'s README example
(`/Users/shinzui/Keikaku/hub/haskell/tasty-bench-project/tasty-bench/README.md:88-101`):

    benchmark bench-fibo
      main-is:       BenchFibo.hs
      type:          exitcode-stdio-1.0
      build-depends: base, tasty-bench
      ghc-options:   "-with-rtsopts=-A32m"
      if impl(ghc >= 8.6)
        ghc-options: -fproc-alignment=64

In `keiki.cabal` we add a `benchmark keiki-bench` stanza with
the same shape, plus `keiki` as a build-dep so we can `import
Keiki.Core`, `import Keiki.Examples.OrderCart`, etc.

### Build and test commands (post-EP-21)

    cd /Users/shinzui/Keikaku/bokuno/keiki
    cabal build
    cabal test
    cabal bench           -- new entry-point added by this plan

Expected baseline (verified at M0):

    Tests passed: 141 (post-EP-21)


## Plan of Work

The work splits into **five milestones** (M0–M4). Each milestone is
independently verifiable; each ends with a build-and-test green and
a specific observable artefact.

### M0 — Prerequisites

A baseline run: confirm the repo builds and tests pass after
EP-21 closed. Record the figures in the Decision Log under
"M0 baseline".

End state: a Decision Log entry with the test count and any
line-count anchors we want.

Acceptance: `cabal test` is green at 141 examples.

### M1 — tasty-bench dependency + bench stanza scaffold

Wire the new dependency and a bench stanza that runs end-to-end
on a trivial smoke benchmark before any aggregate work.

Steps:

1. Edit `keiki.cabal`: append a `benchmark keiki-bench` stanza
   with `type: exitcode-stdio-1.0`, `hs-source-dirs: bench`,
   `main-is: Bench.hs`, `build-depends: base, keiki,
   tasty-bench`. Inherit the `warnings` and `shared-extensions`
   common stanzas. Set
   `ghc-options: "-with-rtsopts=-A32m" -fproc-alignment=64`
   per `tasty-bench`'s recommendation.
2. Create `bench/Bench.hs` with a smoke benchmark:

        import Test.Tasty.Bench

        main :: IO ()
        main = defaultMain
          [ bgroup "smoke"
              [ bench "id-noop" $ nf id ()
              ]
          ]

3. Run `cabal bench` and verify it prints an `OK` line.

End state: `cabal bench` runs to completion against the trivial
benchmark.

Acceptance: `cabal bench` prints at least one `OK` line and exits
zero. `cabal build` and `cabal test` are still green.

### M2 — `Keiki.Examples.OrderCart` aggregate

Add the new aggregate following the conventions of
`Keiki.Examples.UserRegistration` (the closer template, since
OrderCart has multiple commands and a lifecycle). Steps:

1. Create `src/Keiki/Examples/OrderCart.hs` with sections for
   domain types (`Sku`, `CartItem`, `DiscountBp`, etc.), command
   payloads, event payloads, register file
   (`OrderCartRegs`), control vertices (`OrderVertex`),
   `deriveAggregateCtors` splice, `deriveWireCtors` splice, the
   `orderCart` builder-form transducer, and the `orderCartAST`
   AST-form transducer.
2. Expose the aggregate from `keiki.cabal`'s `library` stanza
   under `exposed-modules`.
3. Add `Keiki.Examples.OrderCartBuilderSpec` (mirrors
   `UserRegistrationBuilderSpec` — asserts byte-identical agreement
   between `orderCart` and `orderCartAST` on every step of the
   canonical event log).
4. Add `Keiki.Examples.OrderCartSpec` — one end-to-end
   `reconstitute` call on the canonical log, asserting the
   resulting `(vertex, snapshot)` matches a hand-computed
   expected value.
5. Wire the two new test modules into `keiki.cabal`'s
   `test-suite keiki-test` `other-modules` and into
   `test/Spec.hs`.

End state: `cabal test` is green at ≈145 examples (3–6 added by
the two new specs); `orderCart` and `orderCartAST` are exported
and have agreed-upon behaviour.

Acceptance: `cabal test` is green; `OrderCartBuilderSpec`'s
equivalence assertion passes.

### M3 — Real benchmark module

Replace the M1 smoke benchmark with the real workload. Steps:

1. Remove the `smoke` group from `bench/Bench.hs`.
2. Add a `Workload` record (or a small named tuple) capturing
   the inputs each operation needs: the transducer, the initial
   state, a single command for `delta`/`omega`/`step`, a single
   event for `applyEvent`, the canonical event log for
   `reconstitute`.
3. Build two `Workload` values per aggregate: one anchored on
   the builder-form transducer, one on the AST-form. For
   UserRegistration this is `userReg` / `userRegAST`; for
   OrderCart it is `orderCart` / `orderCartAST`.
4. For each operation × aggregate × form, register one `bench`
   under a `bgroup "<aggregate>/<form>"`. Use `whnf` for
   operations that return `Maybe (vertex, regs)` (the spine is
   what we care about); use `nf` on a snapshot tuple where we
   want full forcing.
5. Add a top-level `bgroup "head-to-head"` with `bcompare`
   entries comparing `step` and `reconstitute` between
   builder and AST forms, on each aggregate. Pattern reference:
   `tasty-bench` README's "Comparison between benchmarks"
   section.
6. Run `cabal bench` and confirm the printed table has every
   entry, every entry reports `OK`, and `bcompare` rows show
   a sensible ratio (close to 1.0 unless there is a real perf
   gap to investigate).

Operation matrix per aggregate × form (8 columns):

    delta:          whnf (delta t v0 r0) ci0
    omega:          whnf (omega t v0 r0) ci0
    step:           whnf (step  t (v0, r0)) ci0
    applyEvent:     whnf (applyEvent t v0 r0) co0
    reconstitute:   whnf (reconstitute t) canonicalLog

End state: `cabal bench` prints a multi-row table covering the
full operation matrix on both example aggregates in both forms,
plus the `bcompare` head-to-head group. Wall-clock under ~60 s
on the development host.

Acceptance: every benchmark prints `OK`; the head-to-head ratios
print without `tasty-bench` warnings about insufficient
measurement.

### M4 — Documentation closure

1. Add `bench/README.md` (one screenful) covering: how to run
   (`cabal bench` and `cabal bench -- --csv out.csv`); how to
   establish a baseline
   (`cabal bench -- --baseline baseline.csv`); how to interpret
   a `bcompare` row; what the matrix means.
2. If `docs/foundations/06-where-to-go-next.md` mentions test
   commands or comparable contributor onboarding hooks, add a
   one-line pointer at "Benchmarking" with a link to
   `bench/README.md`. If no such section exists or is
   appropriate, skip — this is documentation polish, not a
   structural addition.
3. Update the top-level `README.md` (if one exists) similarly.

End state: a contributor can run `cabal bench`, capture a
baseline, and re-run on a future commit to see a comparison
table.

Acceptance: `bench/README.md` exists, is one page or less,
and accurately describes the M3 benchmark module's output.


## Concrete Steps

The exact commands to run, in order. Working directory is
`/Users/shinzui/Keikaku/bokuno/keiki` throughout unless stated
otherwise.

### M0 — baseline

    cabal build
    cabal test
    wc -l src/Keiki/Examples/UserRegistration.hs
    wc -l src/Keiki/Examples/EmailDelivery.hs

Record the numbers in the Decision Log under "M0 baseline (date)".

### M1 — bench stanza + smoke

Edit `keiki.cabal`: add a `benchmark keiki-bench` stanza after
the existing `test-suite keiki-test` block, importing the same
common stanzas (`warnings`, `shared-extensions`). Build deps:
`base`, `keiki`, `tasty-bench`.

Create `bench/Bench.hs` with the smoke benchmark from M1.

Run:

    cabal bench

Expected: a single `OK` line for `smoke.id-noop`. Commit at
green.

### M2 — OrderCart aggregate

Create `src/Keiki/Examples/OrderCart.hs`. Use
`src/Keiki/Examples/UserRegistration.hs` as the structural
template — the section ordering, the splices, the
builder-then-AST pair, and the `KnownInCtors` instance are all
patterns we copy. Where `UserRegistration` reads the synthesis
note, `OrderCart` reads the canonical-event-log section we
write here.

Edit `keiki.cabal`: add `Keiki.Examples.OrderCart` to the
library's `exposed-modules`. Add
`Keiki.Examples.OrderCartBuilderSpec` and
`Keiki.Examples.OrderCartSpec` to `keiki-test`'s
`other-modules`.

Create `test/Keiki/Examples/OrderCartBuilderSpec.hs` and
`test/Keiki/Examples/OrderCartSpec.hs` mirroring the existing
patterns.

Edit `test/Spec.hs` to register the two new specs.

Run:

    cabal build
    cabal test

Expected: ≈145 examples pass. Commit at green.

### M3 — real benchmark

Replace `bench/Bench.hs` with the workload-driven version
described in the Plan of Work. Imports needed:

    import Test.Tasty.Bench (defaultMain, bgroup, bench, bcompare,
                             whnf, nf)
    import Keiki.Core (delta, omega, step, applyEvent, reconstitute)
    import Keiki.Examples.UserRegistration
    import Keiki.Examples.OrderCart

For each aggregate, define the bench-side fixtures locally in
`bench/Bench.hs` (a `userRegLog :: [UserEvent]` of length ≥32
and an `orderCartLog :: [OrderEvent]` of length ≥32). The
existing test-side `canonicalLog`s are 5 events each — too
short to amortise per-step setup. Inline the longer logs in
the bench module so the test side is unaffected.

Run:

    cabal bench

Expected: a printed table with rows for each aggregate × form
× operation, plus the head-to-head `bcompare` rows. Every row
ends `OK`. Commit at green.

### M4 — docs

Create `bench/README.md`. Optionally edit
`docs/foundations/06-where-to-go-next.md` and the top-level
`README.md` per Plan of Work step M4.

Commit at writing-complete.


## Validation and Acceptance

The plan is complete when:

1. `cabal build` is clean under GHC 9.12.x.
2. `cabal test` is green at ≥145 examples (141 baseline + ≥4
   from M2's two new specs).
3. `cabal bench` runs end-to-end in ≤60 seconds, exits zero,
   and every benchmark prints `OK`.
4. The bench output covers, for each aggregate × form
   (UserRegistration/OrderCart × builder/AST), all five
   operations (`delta`, `omega`, `step`, `applyEvent`,
   `reconstitute`), and a head-to-head `bcompare` group
   reports relative ratios on `step` and `reconstitute`.
5. `Keiki.Examples.OrderCart` exposes both `orderCart` and
   `orderCartAST`, byte-identically agreeing on the canonical
   event log per `OrderCartBuilderSpec`.
6. `bench/README.md` exists and accurately describes how to
   run, capture a baseline, and interpret the output.

A skeptical reviewer can verify the benchmark matters by
running `cabal bench` before and after a hot-path edit (e.g.
inlining `Keiki.Core.delta`'s case match) and observing the
table change.


## Idempotence and Recovery

Every milestone is additive on top of the post-EP-21 baseline.
M0 reads only; M1 adds a stanza and a smoke file; M2 adds new
modules and specs without modifying existing modules; M3
rewrites only `bench/Bench.hs`; M4 writes new docs.

If a milestone breaks:

- M1: bench stanza syntax error or `tasty-bench` resolution
  failure — revert the cabal edit; investigate via `cabal
  v2-update` or the `mori` corpus.
- M2: TH splice fails on the OrderCart module — `cabal clean`
  is safe; the most likely cause is a typo in the
  `deriveAggregateCtors` spec list. Compare to the
  `UserRegistration` invocation.
- M3: bench module fails to compile — likely an import-path
  mistake or a missing `whnf`/`nf` argument; the smoke version
  from M1 is a safe fallback.
- M4: docs are reversible.

Re-running steps:

- `cabal build`, `cabal test`, `cabal bench` are deterministic.
- `cabal clean` is safe at any point.
- The plan introduces no migrations of on-disk state, no
  destructive database changes, no shared-resource
  modifications.

Recovery from an unintended commit: `git revert <sha>`. The plan
is implemented on the current branch (`master`).


## Interfaces and Dependencies

### Modules consumed (no surface change)

- `Keiki.Core` (`src/Keiki/Core.hs`): `delta`, `omega`, `step`,
  `applyEvent`, `reconstitute`, `RegFile`, `SymTransducer`,
  `Edge`, `OutFields`, `OPack` — the benchmark module imports
  these and exercises them. No surface change.
- `Keiki.Builder` (`src/Keiki/Builder.hs`): used at M2 to author
  `orderCart`. No surface change.
- `Keiki.Generics` and `Keiki.Generics.TH`: used at M2 via
  `deriveAggregateCtors` and `deriveWireCtors` splices. No
  surface change.

### Modules produced

- **New** `Keiki.Examples.OrderCart` (`src/Keiki/Examples/OrderCart.hs`).
  Exports the same shape as `UserRegistration`: domain types,
  command/event payload types, `OrderCartRegs`, `OrderVertex`,
  `orderCart`, `orderCartAST`, plus all the TH-emitted
  `inCtor*`/`inp*`/`wire*`/`OrderTermFields` declarations.
- **New** test modules `Keiki.Examples.OrderCartBuilderSpec`
  and `Keiki.Examples.OrderCartSpec` under `test/Keiki/Examples/`.
- **New** benchmark module `Bench` at `bench/Bench.hs`.
- **New** documentation `bench/README.md`.

### New build-time dependencies

- `tasty-bench` (mori entry: `Bodigrim/tasty-bench`,
  corpus path:
  `/Users/shinzui/Keikaku/hub/haskell/tasty-bench-project/`).
  Cabal range: `^>= 0.4` (current Hackage major; resolved by
  `cabal solve` against the project's index).
- `tasty` (transitive — pulled by `tasty-bench`; not added
  explicitly per Decision Log).

`keiki.cabal` `build-depends` of the existing `library` and
`test-suite keiki-test` stanzas are unchanged.

### Test suite

- **New** test cases (M2): ≈4 examples added by
  `OrderCartBuilderSpec` + `OrderCartSpec`. Exact count is an
  outcome of M2.
- **Unchanged**: every other spec.

### Out of scope

- **Solver-bound benchmarks** (`Keiki.Symbolic` analyses). See
  Decision Log.
- **Build-time `buildTransducer` benchmark.** See Decision Log.
- **NFData instances across `Keiki.Core`.** See Decision Log.
- **Property-generated event logs** for benchmarks. See Decision
  Log; canonical hand-authored logs only.
- **Comparison vs. other event-sourcing libraries.** Out of
  scope; this plan establishes a self-baseline only.

### Soft external dependencies (all Complete)

- *EP-15.* `Keiki.Builder` shape is the post-EP-15 surface +
  EP-21 amendments.
- *EP-21.* Field-keyed record sugar for `B.emit`. The OrderCart
  aggregate uses the post-EP-21 record-syntax `B.emit` and the
  `(*:)`/`oNil` synonyms (now in `Keiki.Core`).
