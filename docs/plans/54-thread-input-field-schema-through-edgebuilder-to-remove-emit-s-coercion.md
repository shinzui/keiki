---
id: 54
slug: thread-input-field-schema-through-edgebuilder-to-remove-emit-s-coercion
title: "Thread input field schema through EdgeBuilder to remove emit's coercion"
kind: exec-plan
created_at: 2026-05-23T13:49:41Z
---

# Thread input field schema through EdgeBuilder to remove emit's coercion

> **Status: SUPERSEDED (2026-08-04). Do not implement this plan.**
> It was never executed — every milestone below is unchecked — but its
> objective was achieved by
> `docs/plans/70-builder-correctness-hardening-eager-finalize-validation-closing-the-emit-unsafecoerce-schema-hole-and-declaration-order-edge-merging.md`
> (Milestone 2) on 2026-07-12, in commit `fc4349f`
> (`feat(builder): pin input schemas in EdgeBuilder`). EP-70 reached
> **outcome A** — `src/Keiki/Builder.hs` now contains no `unsafeCoerce`,
> `reIndexPinnedInCtor` and `PeInCtor` are gone, and no aggregate author
> changed a call site. It got there via a *refinement* of the design
> proposed here; see the Decision Log entry dated 2026-08-04 and Outcomes
> & Retrospective. This file is retained as the record of the question and
> the pre-investigation that framed it.

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

EP-53 (`docs/plans/53-harden-inctor-identity-for-structural-replay.md`, see also
`docs/adr/0001-structural-re-indexing-for-sound-replay.md`) made structural replay
type-sound by indexing `Term` and `OutFields` by the input field schema `ifs`. It left
exactly one *new* `unsafeCoerce` behind, in the builder: `Keiki.Builder.emit` calls
`reIndexPinnedInCtor` (`src/Keiki/Builder.hs`) to bridge the existentially-hidden field
schema of the `InCtor` pinned by `onCmd` (stored in the `PeInCtor` existential, which hides
`ifs`) to the schema the per-event record exposes.

This is an **investigate-then-decide** plan. The hypothesis is that indexing the builder's
`EdgeBuilder` (and its `PartialEdge` state) by that same `ifs` lets `emit` recover the
pinned `InCtor` *at the record's schema* directly — deleting `reIndexPinnedInCtor` and the
`PeInCtor` existential — with no change to how aggregates are authored (there are no
explicit `EdgeBuilder` type annotations in `jitsurei/` or `test/`, so the new parameter is
inferred). The work either:

- **(A) lands the threading**: after it, `rg unsafeCoerce src/Keiki/Builder.hs` returns
  nothing, `cabal test all` still passes (notably `BuilderSpec` cases 10 `onEpsilon` and 14
  `emitWith`, plus all four `jitsurei` aggregates), and no aggregate author had to change a
  call site; or
- **(B) records why not**: if threading forces awkward ergonomics (e.g. it cannot keep
  `onEpsilon` + multi-`emitWith` bodies working without its own coercion, or it leaks `ifs`
  into a public signature authors must write), the plan stops, reverts the spike, and
  records a Decision Log entry with the concrete spike evidence concluding that the single
  documented `reIndexPinnedInCtor` is the better tradeoff. That outcome is still a success:
  the question is answered with evidence.

Either way the *replay soundness* established by EP-53 is unchanged — `reIndexPinnedInCtor`
does not weaken it (the `OPack` it builds is well-typed; soundness is carried by the types).
This plan only concerns whether the builder's internal construction can also be made
coercion-free.


## Progress

**None of these milestones were executed under this plan.** They are all
superseded by EP-70 Milestone 2 (commit `fc4349f`, 2026-07-12), which delivered
the same objective — see the status banner above. Left unchecked deliberately, to
record accurately that this plan was never run rather than to imply outstanding work.

- [ ] M1 (spike): add an `ifs :: [Slot]` parameter to `EdgeBuilder` and `PartialEdge`,
      replace the `PeInCtor` existential with a plain `Maybe (InCtor ci ifs)`, and rewrite
      `emit` to read it at the record's schema with no coercion. Compile the library only.
- [ ] M2: thread `ifs` through the indexed-monad instances (`>>=`, `>>`, `pure`, `return`),
      `onCmd`, `onEpsilon`, `emitWith`, `noEmit`, `goto`, `(.=)`/`(=:)`, `require*`,
      `requireGuard`, and `finalizeEdge`. Decide and document how `onEpsilon` (no pinned
      `InCtor`) and `emitWith` (explicit `InCtor`) determine `ifs`.
- [ ] M3: delete `reIndexPinnedInCtor`, its `Unsafe.Coerce` import (if now unused in
      `Builder`), and the `PeInCtor` data type if it is no longer referenced.
- [ ] M4: build `jitsurei` and the test suites; fix any annotations (expected: none —
      authoring is inference-driven). Run `cabal test all`.
- [ ] M5 (decision gate): if everything passes with no authoring-surface change, keep it
      (outcome A). Otherwise revert and record outcome B with spike evidence.
- [ ] M6: update `docs/adr/0001-structural-re-indexing-for-sound-replay.md`'s "Consequences"
      (the builder coercion is now gone, or is retained with a recorded rationale), and fill
      this plan's Outcomes & Retrospective.


## Surprises & Discoveries

- Pre-investigation (2026-05-23): there are **no explicit `EdgeBuilder` type annotations**
  in `jitsurei/` or `test/` (`rg "EdgeBuilder " jitsurei/ test/ | rg ::` is empty), so a new
  `ifs` parameter on `EdgeBuilder` should be transparent to aggregate authors — the
  parameter is inferred from the `onCmd` `InCtor`. This is the main feasibility signal for
  outcome A.
- Pre-investigation (2026-05-23): `onEpsilon` (no pinned `InCtor`) and `emitWith` (explicit
  `InCtor`) are both exercised by the suite — `test/Keiki/BuilderSpec.hs` case 10 (`onEpsilon`
  guard-only edge) and case 14 (`emitWith` record form), and `jitsurei` uses both. These are
  the cases most likely to resist a single-`ifs` `EdgeBuilder`: an `onEpsilon` body that
  calls `emitWith` for two *different* input constructors would force its block `ifs` to two
  types at once. (Semantically an edge consumes one input command, so this should not arise;
  the spike must confirm the suite never relies on it.)


## Decision Log

- Decision: Frame this as investigate-then-decide rather than a committed implementation.
  Rationale: EP-53's retrospective flagged threading `ifs` through `EdgeBuilder` as a
  *correctness-neutral* cleanup whose payoff (deleting one documented coercion) must be
  weighed against possible ergonomic cost. The fully-typed approach is plausible but
  unproven for `onEpsilon`/`emitWith`/multi-event bodies; a spike is the honest first step.
  Date: 2026-05-23

- Decision: Replace the `PeInCtor` existential with a schema-indexed `Maybe (InCtor ci ifs)`
  on `PartialEdge`, rather than keeping `PeInCtor` and coercing.
  Rationale: The coercion exists *only because* `PeInCtor` hides `ifs`. Carrying `ifs` as a
  type parameter of `PartialEdge`/`EdgeBuilder` makes the pinned `InCtor` available at the
  same schema the per-event record exposes, so `emit` ties them by construction. This is the
  whole point of the plan; if it cannot be made to work cleanly, the answer is outcome B.
  Date: 2026-05-23

- Decision: **Supersede this plan; the work was delivered by EP-70, not here.**
  Rationale: A relevance audit of EP-53 on 2026-08-04 found that this plan was never
  executed, yet its objective had already been met. EP-70 Milestone 2 (commit `fc4349f`,
  `feat(builder): pin input schemas in EdgeBuilder`, 2026-07-12) threaded the input-schema
  pin through `EdgeBuilder`, deleted `reIndexPinnedInCtor`, and removed the builder's
  `Unsafe.Coerce` import. Re-running this plan would attempt work already in the tree.
  Marking it superseded rather than deleting it preserves the pre-investigation evidence
  (the "no explicit `EdgeBuilder` annotations" feasibility signal, and the `onEpsilon` +
  multi-`emitWith` risk) that shaped how EP-70 approached the problem.
  Date: 2026-08-04


## Outcomes & Retrospective

**Superseded — this plan produced no code.** Its question was answered, and answered
affirmatively (**outcome A**), by EP-70 Milestone 2 on 2026-07-12.

What EP-70 landed, verified against the working tree at `9ee8de0` on 2026-08-04:

- `EdgeBuilder` and `PartialEdge` carry the input schema as a type parameter
  (`src/Keiki/Builder.hs:322`, `:280`).
- `reIndexPinnedInCtor` and the `PeInCtor` existential no longer exist;
  `rg -n "unsafeCoerce" src/Keiki/Builder.hs` returns nothing — the M1/M3 acceptance
  criterion stated in this plan.
- No aggregate author changed a call site, matching this plan's central feasibility
  hypothesis (there were no explicit `EdgeBuilder` annotations in `jitsurei/` or `test/`).
- `docs/adr/0001-structural-re-indexing-for-sound-replay.md` records the closure under
  "Completed follow-up" in its Consequences — the M6 deliverable.

**Where EP-70's design differed from this plan, and why it is better.** This plan proposed
a plain `ifs :: [Slot]` parameter. EP-70 used `pin :: Maybe [Slot]` instead. The `Maybe`
resolves exactly the hazard this plan's Surprises section had flagged as the main threat to
outcome A: an `onEpsilon` block pins no input constructor, so it has no `ifs` to supply, and
a mandatory `[Slot]` parameter would have forced an awkward answer there. Encoding
"unpinned" in the type was the missing piece. The pre-investigation recorded here correctly
identified the obstacle; EP-70 supplied the refinement that cleared it.

Retrospective note: the gap between this plan being written (2026-05-23) and its objective
being delivered elsewhere (2026-07-12) went unrecorded for roughly seven weeks, during which
the file read as open work. An investigate-then-decide plan whose subject is a small residual
cleanup is prone to this — the cleanup gets absorbed into a larger nearby plan. Worth
cross-checking such plans against the tree before scheduling them.


## Context and Orientation

The builder DSL lives in `src/Keiki/Builder.hs`. An aggregate author writes edges with a
small indexed-monad EDSL:

```haskell
B.onCmd inCtorStart $ \d -> B.do
  slot @"email" .= d.email
  B.emit wireRegistrationStarted (RegistrationStartedTermFields { recipient = d.email, ... })
  B.goto Active
```

Key types and how `ifs` (the *input field schema* — a type-level list of `(name, type)`
slots, EP-53's term) flows today:

- `InCtor ci ifs` (`src/Keiki/Core.hs`) describes one input constructor; `ifs` is its field
  schema. EP-53 added `ifs` to `Term`/`OutFields` and made `OPack :: InCtor ci ifs ->
  WireCtor co fields -> OutFields rs ci ifs fields -> OutTerm rs ci co` tie the two `ifs`.

- `PartialEdge rs ci co v w` (`src/Keiki/Builder.hs`, ~line 239) is the mutable accumulator
  for one edge: guard, update, output list, targets, and `peInCtor :: Maybe (PeInCtor ci)`.

- `PeInCtor ci` (~line 267) is an existential wrapper: `PeInCtor :: InCtor ci ifs ->
  PeInCtor ci`. It hides `ifs`. `onCmd` stores `Just (PeInCtor ic)` here so `emit` can find
  the pinned `InCtor` without the author repeating it.

- `EdgeBuilder rs ci co v (w :: [Symbol]) (w' :: [Symbol]) a` (~line 285) is the indexed
  monad over `PartialEdge`; `w`/`w'` are the input/output slot-write sets (for the
  `Disjoint` write-once check). Its `>>=`/`>>`/`pure`/`return` thread `w` through.

- `onCmd :: Show v => InCtor ci ifs -> (PayloadProj rs ci ifs -> EdgeBuilder rs ci co v '[]
  w ()) -> EdgeListBuilder rs ci co v ()` (~line 645) pins `ic` into `peInCtor` and hands the
  body a `PayloadProj rs ci ifs` so `d.field` projects at `ic`'s schema (EP-53 made
  `HasField name (PayloadProj rs ci ifs) (Term rs ci ifs r)`).

- `onEpsilon` (~line 671) builds an ε-edge with `peInCtor = Nothing` and no `PayloadProj`.

- `emit :: ToOutFields rec rs ci ifs fs => WireCtor co fs -> rec -> EdgeBuilder rs ci co v w
  w ()` (~line 455) reads `peInCtor pe`; on `Just (PeInCtor ic)` it builds `pack
  (reIndexPinnedInCtor ic) wc (toOutFields rec)`. **`reIndexPinnedInCtor :: InCtor ci ifs0
  -> InCtor ci ifs` is `unsafeCoerce`** — the target of this plan. It exists only because
  `PeInCtor` hid `ic`'s schema while the record's schema `ifs` is known from `ToOutFields`.

- `emitWith :: ToOutFields rec rs ci ifs fs => InCtor ci ifs -> WireCtor co fs -> rec ->
  EdgeBuilder rs ci co v w w ()` (~line 476) is the escape hatch (used inside `onEpsilon`,
  or to override the pinned `InCtor`); it takes the `InCtor` explicitly and needs no
  coercion already.

- `ToOutFields rec rs ci ifs fs` (~line 519) converts a per-event record (or a bare `t1 *:
  t2 *: oNil` chain) to `OutFields rs ci ifs fs`; EP-53 added its `ifs`.

The relevant tests: `test/Keiki/BuilderSpec.hs` (notably case 10 `onEpsilon`, case 14
`emitWith`), `test/Keiki/BuilderSpike.hs`, and all four `jitsurei/src/Jitsurei/*.hs`
aggregates (`EmailDelivery`, `LoanApplication`, `OrderCart`, `UserRegistration`) which
authored real edges and are exercised by `jitsurei-test`.

Run everything from `/Users/shinzui/Keikaku/bokuno/keiki`. The toolchain is GHC 9.12.2,
`default-language: GHC2024`.


## Plan of Work

### Milestone 1 — Spike the core type change (library compiles)

Add `ifs :: [Slot]` to `PartialEdge` and `EdgeBuilder`, and replace the `PeInCtor`
existential with a schema-indexed field. Concretely in `src/Keiki/Builder.hs`:

- `data PartialEdge rs ci (ifs :: [Slot]) co v (w :: [Symbol]) = PartialEdge { … ,
  peInCtor :: Maybe (InCtor ci ifs) }` — drop `PeInCtor`; store the `InCtor` at `ifs`
  directly.
- `newtype EdgeBuilder rs ci (ifs :: [Slot]) co v (w :: [Symbol]) (w' :: [Symbol]) a` —
  carry `ifs` through; `runEdgeBuilder` maps `PartialEdge … ifs … w` to `PartialEdge … ifs …
  w'`.
- Rewrite `emit` to `case peInCtor pe of Just ic -> pack ic wc (toOutFields rec)` — `ic ::
  InCtor ci ifs` and `toOutFields rec :: OutFields rs ci ifs fs` now share `ifs` by the
  `EdgeBuilder`'s parameter, so **no coercion**.

Acceptance for M1: `cabal build lib:keiki` compiles. Expect a cascade of signature errors
in M2's surface; that is fine — M1 is the type-shape change plus `emit`'s body.

### Milestone 2 — Thread `ifs` through the rest of the builder

Add `ifs` to every `EdgeBuilder`-typed signature and the indexed-monad instances:

- `(>>=)`, `(>>)`, `pure`, `return` (the `QualifiedDo` surface, ~lines 296–322): thread `ifs`
  unchanged (it is constant within a body).
- `onCmd`: `… InCtor ci ifs -> (PayloadProj rs ci ifs -> EdgeBuilder rs ci ifs co v '[] w
  ()) -> …`; store `peInCtor = Just ic`.
- `onEpsilon`: the body has no pinned `InCtor`, so its `ifs` is unconstrained — leave it a
  free type variable (`EdgeBuilder rs ci ifs co v '[] w ()`), `peInCtor = Nothing`. An
  `emitWith` inside it fixes `ifs` to that call's `InCtor`.
- `emitWith`, `noEmit`, `goto`, `(.=)`/`(=:)`, `requireGuard`, `requireEq`, `requireCmp`,
  `requireLt`/`Le`/`Gt`/`Ge`: add `ifs` to the `EdgeBuilder` result. For `(.=)` and
  `require*`, decide whether the RHS `Term`'s schema must be the block's `ifs` (tying
  `d.field` writes to the pinned ctor) or stay independently existential as today — prefer
  the **least-restrictive** choice that compiles the suite unchanged, and record it.
- `finalizeEdge`, `runEdgeBuilder`, `EdgeListBuilder` glue: thread `ifs` where it appears.

Acceptance for M2: `cabal build lib:keiki` compiles with no `unsafeCoerce` reachable from
`emit`.

### Milestone 3 — Remove the coercion

Delete `reIndexPinnedInCtor`. If `Builder` no longer uses `unsafeCoerce`, remove `import
Unsafe.Coerce (unsafeCoerce)`. Delete the `PeInCtor` data type and its `PeInCtor`
constructor if nothing references them.

Acceptance for M3: `rg -n "unsafeCoerce|reIndexPinnedInCtor|PeInCtor" src/Keiki/Builder.hs`
returns nothing.

### Milestone 4 — Downstream and tests

Build `jitsurei` and the test suites. Expect no authoring changes (no explicit `EdgeBuilder`
annotations exist downstream). Fix any that do appear by adding the inferred `ifs`.

Acceptance for M4: `cabal test all` passes — all four suites, 0 failures.

### Milestone 5 — Decision gate

If M1–M4 succeed with **no change to any aggregate author's call site** and no new
`unsafeCoerce` anywhere, adopt the change (outcome A). If any of the following hold, stop,
`git checkout` the builder, and record outcome B with the concrete failure:

- `onEpsilon` + multiple `emitWith` of different constructors is relied on by the suite and
  cannot share one block `ifs` without its own coercion;
- the threading leaks `ifs` into a signature an author must write by hand;
- the indexed-monad ergonomics (e.g. `QualifiedDo`) break in a way that needs `AllowAmbiguousTypes`-style annotations at call sites.

### Milestone 6 — Documentation

Update `docs/adr/0001-structural-re-indexing-for-sound-replay.md` Consequences (builder is
now coercion-free, or the coercion is retained with the recorded reason) and fill this
plan's Outcomes & Retrospective.


## Concrete Steps

Work from the repository root:

```bash
cd /Users/shinzui/Keikaku/bokuno/keiki
```

Inspect the current builder surface before editing:

```bash
sed -n '239,330p;455,500p;645,715p' src/Keiki/Builder.hs
```

Make the M1–M3 edits, then iterate the compiler:

```bash
cabal build lib:keiki 2>&1 | grep -E "\.hs:[0-9]+:[0-9]+: error" | head -40
```

When the library is clean, build and test everything:

```bash
cabal build all --enable-tests 2>&1 | grep -E "\.hs:[0-9]+:[0-9]+: (error|warning)" | head -40
cabal test all 2>&1 | grep -E "Test suite .*(PASS|FAIL)|examples?, [0-9]+ failures?"
```

Confirm the coercion is gone:

```bash
rg -n "unsafeCoerce|reIndexPinnedInCtor|PeInCtor" src/Keiki/Builder.hs
```

Expected on success: the four suites report `PASS` with 0 failures, and the `rg` above
returns nothing (exit status 1).


## Validation and Acceptance

Acceptance is behavioral and structural:

1. `cabal test all` passes — `keiki-test`, `jitsurei-test`, `keiki-codec-json-test`, and
   `keiki-codec-json-test-test`, 0 failures. In particular `BuilderSpec` cases 10
   (`onEpsilon`) and 14 (`emitWith`) still pass, proving the ε-edge and explicit-`InCtor`
   paths survive the threading.
2. `rg unsafeCoerce src/Keiki/Builder.hs` returns nothing (outcome A) — OR a Decision Log
   entry records, with the specific compile/ergonomics failure, why the coercion is retained
   (outcome B).
3. No file under `jitsurei/` or `test/` needed a new `EdgeBuilder`/`PartialEdge` type
   annotation — i.e. the authoring surface is unchanged. (`git diff --stat` should show no
   `jitsurei/` changes on outcome A.)

This change must not alter the replay guarantee EP-53 established: re-run the EP-53
regression and structural-replay tests (part of `keiki-test`) and confirm they still pass.


## Idempotence and Recovery

The change is confined to `src/Keiki/Builder.hs` (plus possibly downstream annotations). It
is safe to iterate: re-running the build/test commands is idempotent. Because outcome B is a
legitimate result, the rollback path is first-class — `git checkout -- src/Keiki/Builder.hs`
restores the EP-53 state (with `reIndexPinnedInCtor`) at any point, and the plan's value is
preserved in the Decision Log either way. Do not use `git reset --hard`.


## Interfaces and Dependencies

Only `base` and the existing `keiki` modules are involved; no new dependencies. At the end of
outcome A:

- `EdgeBuilder` and `PartialEdge` carry an `ifs :: [Slot]` parameter.
- `peInCtor :: Maybe (InCtor ci ifs)` (no existential wrapper); `PeInCtor` is deleted.
- `emit :: ToOutFields rec rs ci ifs fs => WireCtor co fs -> rec -> EdgeBuilder rs ci ifs co
  v w w ()` builds its `OPack` with no coercion.
- `reIndexPinnedInCtor` no longer exists; `Builder` imports no `Unsafe.Coerce`.

At the end of outcome B: the interfaces are unchanged from EP-53, and the Decision Log
explains why.

> **Superseded note:** outcome A was reached by EP-70, but with `pin :: Maybe [Slot]` on
> `EdgeBuilder`/`PartialEdge` rather than the `ifs :: [Slot]` / `peInCtor :: Maybe (InCtor
> ci ifs)` shape sketched above. Read the tree (`src/Keiki/Builder.hs:280`, `:322`), not
> this section, for the interfaces that actually landed.


## Revision Notes

- 2026-08-04 — **Marked SUPERSEDED.** A relevance audit of EP-53 (its parent, which flagged
  this cleanup as its one residual follow-up) found this plan was never executed while its
  objective had already been delivered by EP-70 Milestone 2 on 2026-07-12 (commit `fc4349f`).
  Verified against the working tree at `9ee8de0`: `src/Keiki/Builder.hs` contains no
  `unsafeCoerce`, and neither `reIndexPinnedInCtor` nor `PeInCtor` exists anywhere in `src/`.
  Added a status banner, a Progress preamble explaining why the milestones remain unchecked,
  a Decision Log entry recording the supersession, a filled-in Outcomes & Retrospective
  crediting EP-70 and explaining why its `Maybe [Slot]` refinement beat this plan's proposed
  `[Slot]` parameter, and a caveat on the Interfaces section. No milestone was retroactively
  checked off — this plan produced no code, and the record should say so.
