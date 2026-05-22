---
id: 47
slug: recompute-and-verify-derived-event-outputs-in-solveoutput-replay
title: "Recompute-and-verify derived event outputs in solveOutput replay"
kind: exec-plan
created_at: 2026-05-21T22:59:23Z
intention: "intention_01ks6ber3jedc8ff6zzma2jr53"
master_plan: "docs/masterplans/13-keiki-api-improvements-surfaced-by-the-rei-migration.md"
---

# Recompute-and-verify derived event outputs in solveOutput replay

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

keiki (the pure event-sourcing core in this repository) never asks the user to hand-write
the function that replays events back into state. Instead it *derives* that replay function
mechanically: every edge of a transducer carries an `output` term describing the event it
emits as a function of the command's fields and the current registers, and at replay time
keiki *inverts* that term to recover the command that must have been issued. The function
that does the inversion is `solveOutput` in `src/Keiki/Core.hs`. This derivation is the
single most important property the library exists to guarantee: the synthesis design note
`docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md` (§1) calls it
"the decisive technical win" — "`apply` derivation comes back for well-formed schemas
(output term invertible in input fields), and fails detectably at build time when a schema
is malformed."

Today that derivation is *over-strict*. `solveOutput` only succeeds when **every** field of
the emitted event is one of three directly-invertible shapes: a literal (`TLit`), a register
read (`TReg`), or a structural projection of a command field (`TInpCtorField`). The failure
mode is harsher than "an event stores a derived value": a **single** non-invertible output
field makes the field walk `gatherInpEntries` return `Nothing` and kills the **whole edge**
on replay — even fields that are not command slots at all. So an aggregate with one
state-resolved `previous*` field (an audit pair recording the old and new value of a
register, say) is dragged into the workaround even though every command field it carries is
perfectly invertible. If even one field of an event stores a **derived value** — a value
computed from registers and/or command fields, such as an order's running total `quantity *
unitPrice`, or that audit pair — that field is built with `TArith` (for arithmetic) or
`TApp1`/`TApp2` (the opaque "apply a Haskell function" escape hatches), and `solveOutput`
returns `Nothing`. The event cannot round-trip. A consumer who needs to store a derived
value in an event is forced into a workaround: introduce a second, redundant "mirror"
command whose only job is to carry the already-computed value, doubling the command
vocabulary. This was the single most painful keiki finding during the Rei migration (Rei
keiki finding #1). Recompute-and-verify removes this "one field poisons the edge" failure
directly: a redundant or state-resolved field stops dragging the whole edge into the mirror
workaround — that is the concrete win.

**The fix belongs in keiki, not the runtime.** Rei reaches keiki through the keiro runtime,
but the constraint is keiki's, and it was confirmed against live source (`../keiro`,
`../rei-project/rei.keiro-migration`). keiro's `Keiro.Command.hydrate`
(`keiro/src/Keiro/Command.hs` ~line 110) stores **only events** — the Kiroku `RecordedEvent`
it folds over carries event type, payload, stream versions, and IDs, but **no command
field** — and its `hydrateFull`/`replayFrom` helpers reconstruct state by calling
`Keiki.applyEventStreaming`, turning that function's `Nothing` into the keiro-owned error
`HydrationReplayFailed` (`Command.hs` ~lines 175 and 244). Every keiki state-reconstruction
primitive — `applyEventStreaming`, `applyEvents`, `reconstitute`, `applyEvent` — recovers
the command via `solveOutput`; keiki exposes **no** forward event→state fold that bypasses
inversion. So keiro cannot fix this without a storage-format change (persisting commands
alongside events): the recompute-and-verify forward consumer **must live in keiki**, in
`solveOutput`.

After this change, an event may store a derived field and still round-trip. We achieve this
with a strategy called **recompute-and-verify**, defined precisely below. In one sentence:
on replay we recover the command from the invertible fields exactly as today, and then for
each derived field we *recompute it forward* (run the same arithmetic or function the edge
would have run when emitting) against the recovered command and registers, and *check* that
the recomputed value equals the value actually observed in the event. If it matches, replay
proceeds; if it does not, replay rejects the event. Crucially, the command is **still
uniquely recovered from the invertible fields alone** — derived fields are a redundant
cross-check, never the sole source of any command information — so keiki's foundational
guarantee that "the event uniquely determines the command, certified at build time" is
preserved, not weakened.

You will be able to see this working concretely. We will build a small order-cart aggregate
(in the test suite) whose `LineItemAdded` event stores a derived `lineTotal = quantity *
unitPrice`. Before this change, replaying that event through keiki's `applyEvents` returns
`Nothing` (the event is unrecoverable). After this change, the same log replays cleanly and
reconstructs the expected `(state, registers)`. Meanwhile a genuinely *malformed* schema —
one where a derived field is the *only* place a command field appears, so the command truly
cannot be recovered — still fails at build time via the static analysis `checkHiddenInputs`.

**M1 is a ratification gate, and it is the most important thing to understand before starting
this plan.** Relaxing `solveOutput` is the only change in this whole initiative that touches
keiki's foundational invariant — that the event uniquely determines the command, certified at
build time. The maintainer is not yet comfortable committing to that relaxation. Therefore M1
builds the prototype and writes the analysis, but then **stops**: it is a deliberate
ratification gate. Unlike the normal ExecPlan protocol — which says do NOT prompt the user for
next steps and proceed straight to the next milestone — M1 explicitly OVERRIDES that protocol.
After delivering the design note, the prototype, and a written analysis with a clear go/no-go
recommendation, the implementing agent MUST pause, present the findings to the maintainer, and
wait for explicit approval before starting M2. Do NOT proceed to M2 automatically. A legitimate
possible outcome of the gate is **no-go**: keep Rei keiki #1 as a docs-only contract (the
sibling `docs/plans/46-document-the-output-invertibility-contract-and-derived-value-modeling-patterns.md`
already documents today's contract and the Direction-A workaround), relax nothing in
`solveOutput`, and close this plan as a docs-only outcome. M2–M4 are executed only if the gate
is approved go.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [~] **M1 (design milestone + ratification gate) — DELIVERABLES COMPLETE; STOPPED AT GATE
  awaiting maintainer go/no-go (2026-05-21).** Research note
  `docs/research/recompute-and-verify-derived-outputs.md` written: relaxed contract (§1);
  proof that "event determines command" is preserved (§2); the `Eq`-mechanism investigation
  (§3) landing on **whole-event `Eq co`** (the documented fallback turned out to be the cleaner
  primary choice — see Surprises); the `checkHiddenInputs` precision refinement (§4); the
  newly-admissible term shapes (§5); the promotion assessment (§6); and the Analysis &
  recommendation (a)–(d). Prototype `test/Keiki/RecomputeVerifySpec.hs` green (5/5:
  `TArith`-output round-trip, tampered-field rejection, forward fixpoint, grid determinism,
  no-collision), written WITHOUT touching `src/Keiki/Core.hs`. Recommendation: **GO** via
  whole-event `Eq co`. **The plan STOPS here per the gate; M2–M4 do not begin until a maintainer
  records a go decision in the Decision Log.** (`[~]` = deliverables done, decision pending.)
- [x] **M2 (2026-05-21).** Implemented recompute-and-verify in `src/Keiki/Core.hs`:
  `gatherInpEntries`/`stepOne` now *skip* derived fields (`TApp1`/`TApp2`/`TArith` → `Just []`)
  instead of failing; `solveOutput` gained `Eq co`, recovers the command from invertible fields,
  then verifies via a new `recomputeDerivedFields` helper (recompute only derived fields, keep
  observed invertible values) and `wcBuild ctor … == co`. `checkHiddenInputs`'s `visitedSlotsOf`
  (and the public twin `detectMissingInCtorFields`) refined to the *invertible-visited* set
  (top-level `TInpCtorField` only; no descent into derived terms), so a slot read only inside a
  derived field is correctly reported missing. `Eq co` propagated to `applyEvent` and
  `outputAcceptor` (`toDecider`/`reconstitute`/`applyEvents`/`applyEventStreaming` already had
  it). Additive: all-invertible fast path byte-identical; `cabal test all` green
  (keiki-test 265, jitsurei 96, codec 40+7, 0 failures). The whole-event `evalOut` form was
  corrected to derived-only recompute — see Surprises.
- [x] **M3 (2026-05-21).** Rewrote `test/Keiki/RecomputeVerifySpec.hs` to exercise the real
  (relaxed) `solveOutput`/`applyEvents` (subsuming the M1 prototype's local function): (i) an
  order-cart aggregate whose `LineItemAdded` event stores a derived `lineTotal = quantity *
  unitPrice` round-trips through `applyEvents` and reconstructs the registers, and a tampered
  total is rejected; (ii) an enumeration over a 6×6 grid where every command round-trips through
  `solveOutput` to itself and distinct commands never collide; (iii) a malformed `badCart` where
  `quantity` is read only inside the derived field is flagged by `checkHiddenInputs` (naming
  `AddLineItem`/`quantity`), while the well-formed `cart` reports `[]`. `cabal test all` green
  (keiki-test 266, jitsurei 96, codec 40+7, 0 failures); no new warnings.
- [ ] **M4.** Amend the shared contract page `docs/guide/output-invertibility.md` and the
  glossary in `docs/guide/user-guide.md` to document the relaxed contract; close the plan.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- **M1 finding: the `Eq` mechanism preference inverts on contact with the live types
  (2026-05-21).** This plan's Decision Log tentatively preferred *field-level* `Eq` (compare each
  recomputed derived field), treating "require `Eq co` on the whole event type" as a fallback.
  Reading the live `Term` constructors (`src/Keiki/Core.hs` ~245–273) shows field-level is the
  *invasive* option: `TArith` carries `Num`+`Typeable` (not `Eq`; `Num` does not imply `Eq`) and
  `TApp1`/`TApp2` carry **nothing** about the result type — not even `Typeable`, so there is no
  dynamic-equality (`Typeable`-cast) fallback for the `TApp` cases. Field-level `Eq` would
  therefore require adding `Eq r` to those constructors, which both breaks call sites and is
  semantically wrong for `TApp` (an escape hatch may produce a value with no `Eq`). The
  **whole-event `Eq co`** mechanism — recover the command from the invertible fields, then
  `evalOut … == co` — needs no `Term`/`OutFields` change, is provably equivalent (the invertible
  fields recompute to their observed values tautologically, so the whole-event check reduces to
  "every derived field verifies"), reuses the existing `applyEventStreaming` tail recompute
  pattern, and is *free* downstream (keiro already requires `Eq co`). So the plan's documented
  fallback is in fact the cleaner primary mechanism. Captured in the research note §3 and folded
  into the go recommendation. This is exactly the kind of correction the M1 gate exists to find.
- **M2 finding: whole-event `evalOut … == co` OVER-verifies invertible `TReg` fields — corrected
  to recompute *only* derived fields (2026-05-21).** The M1 note recommended verifying via
  `evalOut o regs ci == co` (recompute the *whole* output, compare). Implementing that broke two
  existing tests: (1) `DeciderSpec` "Settled Confirmed ⊢ AccountDeleted → Settled Deleted"
  replays from a *synthetic* state with the **initial (empty) register file**; the
  `AccountDeleted` edge emits `email = #email` (a `TReg` audit read), so whole-event recompute
  produced `email = ""` ≠ the observed `"x@y"` and rejected a replay that must succeed; and
  (2) `ProfunctorSpec` "raises a poisoned-icBuild error …" — whole-event `evalOut` *forces* the
  recovered command `ci`, firing `lmapCi`'s deliberately-poisoned `icBuild` *inside* `solveOutput`
  instead of lazily at the call site. Both are real semantic regressions: whole-event verify
  re-checks `TReg`/`TLit`/`TInpCtorField` fields that the contract says are *not* verified
  (EP-46 documents that a `TReg` audit field "already round-trips"), and it eagerly forces `ci`.
  **Fix:** a new helper `recomputeDerivedFields` rebuilds the observed field tuple recomputing
  *only* `TApp1`/`TApp2`/`TArith` fields and keeping invertible fields at their observed values;
  `solveOutput` compares `wcBuild ctor (recomputeDerivedFields …) == co`. This verifies exactly
  the derived fields, never the invertible ones, does not force `ci` for an all-invertible edge,
  and still uses only `Eq co` (the maintainer-approved constraint — unchanged). All suites green
  (keiki-test 265, jitsurei 96, codec 40+7, 0 failures). The research note's §1/§3 mechanism
  description is amended accordingly (see its "M2 refinement" addendum).
- **`solveOutput` already receives the pre-update register file (param `_regs`).** Confirmed: the
  recompute path needs *no* signature change — M2 just starts using the argument already in
  scope, threaded from the `applyEvent`/`applyEventStreaming` call sites that already pass the
  pre-update registers.


## Decision Log

Record every decision made while working on the plan.

- Decision: This plan opens with a design milestone (M1: a research note plus a prototype
  test) before any edit to `src/Keiki/Core.hs`.
  Rationale: `solveOutput` realizes keiki's core invariant — "the event uniquely determines
  the command, certified at build time" (synthesis note §1, the "decisive technical win").
  A change here is the riskiest in the whole MasterPlan
  `docs/masterplans/13-keiki-api-improvements-surfaced-by-the-rei-migration.md`, so it must
  be designed and prototyped before code, exactly as that MasterPlan's Decomposition
  Strategy demands ("implementing EP-47 without a design milestone — rejected").
  Date: 2026-05-21

- Decision: Make M1 an explicit FEEDBACK-AND-RATIFICATION GATE that overrides the normal
  auto-proceed protocol: M1 builds the prototype and writes an analysis with a go/no-go
  recommendation, then STOPS and waits for explicit maintainer approval before M2 begins.
  Rationale: the maintainer is not yet comfortable committing to relaxing `solveOutput` —
  it is the only change in the whole initiative that touches keiki's foundational invariant
  (the event uniquely determines the command, certified at build time). They want the
  prototype and analysis done, but presented for explicit feedback and a go/no-go decision
  before the real core change proceeds. The standard ExecPlan implement protocol ("do not
  prompt for next steps; proceed to the next milestone") is therefore explicitly overridden
  for M1 only. The gate's outcome may legitimately be **no-go**: keep Rei keiki #1 as a
  docs-only contract (EP-46 already documents today's contract and the Direction-A
  workaround), relax nothing in `solveOutput`, and close this plan as "docs-only outcome
  (EP-46 carries #1)". Go criteria: the soundness argument holds, the prototype shows both a
  `TArith`-output edge round-tripping and the recovered command still unique, the field-level
  `Eq` mechanism compiles against the real types without weakening existing constraints, and
  the maintainer judges the blast radius on `solveOutput`/`gatherInpEntries`/`checkHiddenInputs`
  acceptable. No-go criteria: any of those fail, or the maintainer prefers the docs-only
  contract for now. The decision (go or no-go) is recorded here when M1 is presented.
  Date: 2026-05-21

- Decision: Solve "events that store derived values can't round-trip" (Rei keiki #1) with
  **recompute-and-verify**, and explicitly NOT with (a) a user-supplied `backward` closure
  on an output term, nor (b) a "recorder edge" / hand-written forward `apply`.
  Rationale: (a) is unverifiable — the library cannot certify `forward ∘ backward = id`, so
  it would be a trust-me escape that defeats the build-time guarantee. (b) is the
  deliberately-rejected "Approach 3 / Direct MultiDecider"
  (`docs/research/multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md`
  §"Approach 3", and MasterPlan-7 Decision Log), which surrenders mechanical `apply`
  derivation by definition. Recompute-and-verify is neither: there are no user closures and
  no hand-written `apply`, and the command is still recovered by inversion of the invertible
  fields. It only relaxes the over-strong requirement that *every* field be invertible.
  Date: 2026-05-21

- Decision: The replay-time equality check uses **field-level `Eq`** on each recomputed
  derived field, comparing against the corresponding observed field obtained from the wire
  constructor's `wcMatch` — not `Eq` on the whole event type `co`.
  Rationale: `wcMatch` already deconstructs the observed event into its per-field HList on
  every replay (`solveOutput` calls it first). Comparing field-by-field demands `Eq` only on
  the *derived* field types (others need no comparison), is more precise about *which* field
  mismatched (useful for diagnostics), and avoids burdening the whole event type with an `Eq`
  it might not otherwise need. The streaming machinery's separate `Eq co` requirement (used
  by `applyEventStreaming` for multi-event *tail* matching) is unrelated and unchanged.
  Cost note (verified against `../keiro`): the field-level `Eq` adds **no new burden** on the
  keiro runtime, because keiro already requires `Eq co` on *all* its hydration entry points
  (`keiro/src/Keiro/Command.hs` ~line 112 and siblings). A derived field's type is one
  component of `co`, so any `co` keiro can already use satisfies the new per-field constraint.
  Date: 2026-05-21

- Decision: Scope the M3 inversion tests to the `solveOutput` inversion path, and explicitly
  not to the keiro-owned failure signals that resemble it.
  Rationale: validated against live keiro source, three distinct "replay failed" signals
  exist and only one is this plan's concern. The inversion `Nothing` (from `gatherInpEntries`
  hitting a derived field) is what recompute-and-verify removes. The two we must *not*
  conflate are (i) a final `InFlight` wrapper from a mid-chain-truncated multi-event replay,
  which keiro also reports as `HydrationReplayFailed` (`keiro/src/Keiro/Command.hs` ~lines 152
  and 226) but is a streaming-completeness failure, and (ii) a JSON codec failure reported as
  `HydrationDecodeFailed` (`Command.hs` ~lines 166 and 235), which never reaches
  `solveOutput`. M3 fixtures must be well-formed, fully-decoded, single-event, settled
  replays so a pass/fail isolates the inversion behavior. The relaxation also benefits both
  keiro paths through `solveOutput`: replay (`applyEventStreaming` via `hydrate`) and snapshot
  (`applyEvents` via `writeSnapshotIfNeeded`, `Command.hs` ~line 440).
  Date: 2026-05-21

- Decision: **GO — maintainer approved the relaxation, whole-event `Eq co` mechanism
  (2026-05-21).** The maintainer ratified the M1 recommendation: proceed with M2–M4 implementing
  recompute-and-verify via whole-event `Eq co` (recover the command from the invertible fields,
  then `evalOut … == co`). Consequence accepted: `solveOutput` gains an `Eq co` constraint, which
  propagates to its callers (`applyEvent` and any forward of it that lacked it); this is an added
  constraint, not a weakened one, and every event type in the codebase already derives `Eq`
  (keiro requires it). M2 begins now.
  Date: 2026-05-21

- Decision: **M1 ratification gate reached (2026-05-21) — recommendation GO, decision now
  recorded above (GO).** The research note, prototype (5/5 green), and analysis are delivered. The M1
  investigation produced one substantive change to an earlier decision: the equality check should
  use **whole-event `Eq co`** (recover from invertible fields, then `evalOut … == co`), *not*
  field-level `Eq` — because field-level would require an invasive `Eq r` on the `TArith`/`TApp`
  constructors (no `Typeable` fallback for `TApp`), while whole-event `Eq co` is non-invasive,
  provably equivalent, reuses the `applyEventStreaming` tail pattern, and is already required by
  keiro. The go/no-go criteria are met for go (sound proof; prototype shows round-trip + unique
  recovery; the `Eq` mechanism compiles with no constraint weakening; blast radius small and
  additive). **The actual go/no-go decision is the maintainer's and will be recorded here when
  given. M2 does not begin until a go is recorded.** No-go (keep #1 docs-only via EP-46) remains
  legitimate.
  Date: 2026-05-21

- Decision: `checkHiddenInputs` gains *precision*, not laxity. A derived field that is the
  **sole** carrier of some command input (a genuine hidden input — that input appears nowhere
  invertible) remains a build-time error. A derived field every one of whose command inputs
  is **also** recovered by an invertible field elsewhere in the same edge (a *redundant*
  derived field) is admitted, because recompute-and-verify can reconstruct it forward from
  inputs already recovered.
  Rationale: the over-strong rule rejected redundant-derived fields together with genuine
  hidden inputs; this plan distinguishes the two. The check must still flag the unrecoverable
  case so malformed schemas fail loudly, preserving the "fails detectably at build time" half
  of the invariant.
  Date: 2026-05-21


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

This section assumes no prior knowledge of the repository. Read it fully before editing.

**What keiki is.** keiki is a Haskell library for the pure core of event sourcing. The
single source of truth for a domain aggregate is a `SymTransducer` (defined in
`src/Keiki/Core.hs` ~line 581): a finite control graph whose vertices are states (`s`) and
whose edges bundle four things — a `guard` (a predicate that must hold for the edge to
fire), an `update` (how the register file changes), an `output` (the list of events the edge
emits), and a `target` (the next vertex). The data carried alongside the control vertex is a
**register file**, `RegFile rs`, a typed heterogeneous record whose schema `rs` is a
type-level list of `(name, type)` slots. "Command" and "event" are ordinary Haskell sum
types; the type variable `ci` is the command (input) type and `co` is the event (output)
type.

**The Term language.** Edge updates and outputs are not arbitrary Haskell functions; they
are built from a small closed abstract syntax tree (AST) called `Term` (`src/Keiki/Core.hs`
~line 245). A `Term rs ci r` is a pure expression that, given the current register file and
the current command, yields a value of type `r`. Its constructors are:

  - `TLit r` — a constant.
  - `TReg ix` — read register slot `ix` from the register file.
  - `TInpCtorField ic ix` — read field `ix` of the command, where `ic :: InCtor ci ifs`
    names which command constructor is expected and supplies the round-trip between that
    constructor's payload and a typed register file (`icMatch`/`icBuild`). This is the
    *only* term shape that carries fresh command information into an output.
  - `TApp1 (a -> r) t` and `TApp2 (a -> b -> r) a b` — apply an opaque Haskell function to
    one or two sub-terms. "Opaque" means the function is a black box: the SMT translator in
    `src/Keiki/Symbolic.hs` cannot read it (it becomes a fresh free variable), and — relevant
    here — `solveOutput` cannot invert it.
  - `TArith op a b` — structural arithmetic (`OpAdd`/`OpSub`/`OpMul`, i.e. `+`/`-`/`*`) over
    a numeric (`Num`, `Typeable`) operand type. Unlike `TApp`, the SMT translator reads
    `TArith` for real, but `solveOutput` still cannot invert it today.

The forward interpreter for `Term` is `evalTerm` (`src/Keiki/Core.hs` ~line 728); it handles
*all* of the above shapes:

    evalTerm :: Term rs ci r -> RegFile rs -> ci -> r
    evalTerm (TLit r)              _    _  = r
    evalTerm (TReg ix)             regs _  = regs ! ix
    evalTerm (TInpCtorField ic ix) _    ci = case icMatch ic ci of
      Just rf -> rf ! ix
      Nothing -> error ("evalTerm: TInpCtorField guard violation: " ++ icName ic)
    evalTerm (TApp1 f t)           regs ci = f (evalTerm t regs ci)
    evalTerm (TApp2 f a b)         regs ci = f (evalTerm a regs ci) (evalTerm b regs ci)
    evalTerm (TArith op a b)       regs ci =
      applyNumOp op (evalTerm a regs ci) (evalTerm b regs ci)

The crucial observation that makes this whole plan possible: **`evalTerm` already runs every
term shape forward, including `TApp1`/`TApp2`/`TArith`.** Recompute-and-verify needs only the
forward direction for derived fields, so even an *opaque* `TApp` recomputes fine — we never
have to invert it.

**Outputs and the wire constructor.** An event is described by an `OutTerm` (`src/Keiki/
Core.hs` ~line 442). Its only constructor relevant here is:

    OPack :: InCtor ci ifs
          -> WireCtor co fields
          -> OutFields rs ci fields
          -> OutTerm rs ci co

`OPack ic ctor fields` says: this edge consumes the command constructor named by `ic`, and
produces the event wire constructor `ctor`, whose fields are computed by the list of `Term`s
in `fields`. A `WireCtor co fields` (`src/Keiki/Core.hs` ~line 404) is a tag for one
constructor of the event sum `co`:

    data WireCtor co fields = WireCtor
      { wcName  :: String
      , wcMatch :: co -> Maybe fields   -- deconstruct an observed event into its fields
      , wcBuild :: fields -> co         -- rebuild an event from its fields
      }

`OutFields rs ci fs` (`src/Keiki/Core.hs` ~line 414) is a heterogeneous list (an "HList") of
`Term`s, one per wire field, built nested-pair style so the fields' types are tracked
structurally:

    data OutFields rs ci fs where
      OFNil  :: OutFields rs ci ()
      OFCons :: Term rs ci f -> OutFields rs ci fs -> OutFields rs ci (f, fs)

The field-tuple type `fs` is a right-nested tuple like `(f1, (f2, (f3, ())))`. The forward
output evaluator `evalOut` (~line 752) runs each field's `Term` with `evalTerm` and calls
`wcBuild`.

**The inverse direction: `solveOutput`.** On replay we have an observed event value and want
to recover the command. `solveOutput` (`src/Keiki/Core.hs` ~line 1039) does this:

    solveOutput :: OutTerm rs ci co -> RegFile rs -> co -> Maybe ci
    solveOutput (OPack ic@InCtor{} ctor fields) _regs co = do
      fs_obs  <- wcMatch ctor co            -- observed fields as an HList tuple
      entries <- gatherInpEntries fields fs_obs ic
      rf      <- assemble entries           -- build a RegFile covering all of ic's slots
      pure (icBuild ic rf)                  -- rebuild the command

Note that `solveOutput` *ignores* its `RegFile` argument today (the parameter is named
`_regs`). Recompute-and-verify will need it, because recomputing a derived field via
`evalTerm` requires the register file. **This is the one place the live code differs from a
naive reading of the task: the register file is currently threaded into `solveOutput` but
unused; M2 will start using it.**

`gatherInpEntries`/`stepOne` (`src/Keiki/Core.hs` ~lines 1054–1071) is where the rejection
happens. It walks the `OutFields` HList in lockstep with the observed-field tuple, and for
each field decides what command information that field carries:

    gatherInpEntries OFNil           ()        _ic = Just []
    gatherInpEntries (OFCons t rest) (v, fs)   ic  = do
      here <- stepOne t v ic
      more <- gatherInpEntries rest fs ic
      pure (here ++ more)
      where
        stepOne (TLit _)               _val _   = Just []
        stepOne (TReg _)               _val _   = Just []
        stepOne (TInpCtorField ic2 ix) val  ic1
          | icName ic1 == icName ic2 = Just [ByIndex (unsafeCoerce ix) val]
          | otherwise                = Nothing
        stepOne (TApp1 _ _)            _val _   = Nothing   -- <-- the reject site
        stepOne (TApp2 _ _ _)          _val _   = Nothing   -- <-- the reject site
        stepOne (TArith _ _ _)         _val _   = Nothing   -- <-- the reject site

A `ByIndex ifs` (`src/Keiki/Core.hs` ~line 326) is a `(slot-index, value)` pair; `assemble`
(~line 336) collects a bag of these into a complete `RegFile ifs`, succeeding only if every
slot of `ifs` is covered. So `TLit`/`TReg` contribute nothing (`Just []`), `TInpCtorField`
contributes one `(index, observed-value)` pair, and the three derived shapes abort the whole
walk with `Nothing`. **This is the over-strict behavior this plan relaxes.**

**Where `solveOutput` is used on replay.** Two functions consume it:

  - `applyEvent` (~line 882): single-event ("letter") replay. For each outgoing edge it tries
    `solveOutput` on the *head* of the edge's output list; on a unique match whose guard holds
    it commits to that edge, applies the update, and returns the new `(state, registers)`.
  - `applyEventStreaming` (~line 940): the InFlight-aware replay used by `applyEvents` (~line
    1017, the full-log folder) and `reconstitute` (~line 980). Same head-inversion via
    `solveOutput`; additionally, for **multi-event** edges (output list of length ≥ 2) it
    evaluates the *tail* outputs **forward** with `evalOut` and matches them against
    subsequent observed events by `==`:

        evaluatedTail = [ evalOut o regs ci | o <- drop 1 (output e) ]

    **This is the precedent that proves recompute-and-verify is not foreign to keiki.** The
    multi-event tail already recomputes outputs forward and checks them by `Eq`. This plan
    generalizes the same idea *within* a single edge's *head* output, at the granularity of
    individual derived fields, instead of whole tail events.

**The build-time analysis: `checkHiddenInputs`.** `checkHiddenInputs` (`src/Keiki/Core.hs`
~line 1104) is a static lint that, for every edge, checks whether the `output` can
mechanically recover the command. For a non-ε edge it groups the `OPack`s by `InCtor` name,
computes the *union* of command slots "visited" across them, and warns if any of the
`InCtor`'s slots are left unvisited. The visit walk is `visitedSlotsOf`/`goTerm` (~lines
1161–1180), and — importantly — `goTerm` **already descends into `TApp1`/`TApp2`/`TArith`**
looking for nested `TInpCtorField`s:

    goTerm (TInpCtorField ic2 ix)
      | icName ic2 == icName ic = [allSlots !! indexPos ix]
      | otherwise               = []
    goTerm (TApp1 _ tt')  = goTerm tt'
    goTerm (TApp2 _ a b)  = goTerm a ++ goTerm b
    goTerm (TArith _ a b) = goTerm a ++ goTerm b
    goTerm _              = []

So `checkHiddenInputs` already counts a slot as "visited" even when it is read *inside* a
derived term — it does not yet know whether that derived term is `solveOutput`-invertible.
This pre-existing leniency in the *static* check is exactly the precision we want to make
*consistent* with the relaxed *runtime* check (see Plan of Work M2). The genuine
hidden-input case — a command slot that appears in **no** field at all — is still flagged
because it is visited nowhere.

**Terms of art used in this plan (defined once, here):**

  - *Invertible field* — an output field whose `Term` is `TLit`, `TReg`, or `TInpCtorField`;
    `solveOutput` can directly recover any command information it carries (only
    `TInpCtorField` carries any).
  - *Derived field* — an output field whose `Term` is `TArith`, `TApp1`, or `TApp2`; a
    computed value. It may *contain* nested `TInpCtorField` reads of command slots.
  - *Hidden input* — a command slot that appears **only** inside a derived field (or in no
    field at all), so the command cannot be recovered by inversion. This is a malformed
    schema and must fail at build time.
  - *Redundant derived field* — a derived field every nested command-slot read of which is
    **also** recovered by an invertible field elsewhere in the same edge's output. Such a
    field carries no fresh command information; it can be recomputed forward and verified.
  - *Recompute-and-verify* — the replay strategy this plan adds: recover the command from
    invertible fields; then for each derived field run its `Term` forward via `evalTerm`
    against the recovered command and registers, and check the result `==` the observed field
    value.

**How the keiro runtime consumes this (and why the `Eq` cost is already paid).** The
downstream runtime is keiro (`../keiro`); Rei reaches keiki through it. Two facts about keiro,
verified against live source, bear on this plan. First, keiro **already requires `Eq co`**
for *all* hydration: it is a constraint on `Keiro.Command.hydrate`
(`keiro/src/Keiro/Command.hs` ~line 112) and on its siblings `hydrateFull`,
`writeSnapshotIfNeeded`, and the `runCommand` entry points. Therefore the field-level `Eq`
this plan introduces (demanded only on the *derived* field types, per the Decision Log)
imposes **no new burden** on keiro consumers — they already carry `Eq` on the whole event
type. Second, the fix benefits **both** of keiro's `solveOutput`-backed paths: the replay
path (`Keiki.applyEventStreaming` via `hydrate`, `Command.hs` ~lines 170 and 239) and the
snapshot path (`Keiki.applyEvents` via `writeSnapshotIfNeeded`, `Command.hs` ~line 440) both
invert through `solveOutput`, so both stop choking on a single derived field once this lands.

A caution for whoever writes the M3 tests: do **not** conflate the inversion `Nothing` this
plan targets with two *keiro-owned* failure signals that look similar from the outside. (i) A
replay that ends with a final `InFlight` wrapper — a multi-event chain truncated mid-stream —
is also surfaced by keiro as `HydrationReplayFailed` (`Command.hs` ~lines 152 and 226), but
that is a *streaming-completeness* failure, not an inversion failure. (ii) A JSON codec
failure surfaces as the distinct `HydrationDecodeFailed` (`Command.hs` ~lines 166 and 235),
which never reaches `solveOutput` at all. This plan's M3 tests must target the **inversion
path specifically** (a well-formed, fully-decoded, settled single-event replay whose only
obstacle today is a derived field), so a green test proves the relaxation and not an
unrelated keiro code path.

**Where this plan sits in the larger initiative.** The parent MasterPlan is
`docs/masterplans/13-keiki-api-improvements-surfaced-by-the-rei-migration.md`. It records the
decisions cited above (recompute-and-verify chosen over backward-closures and
hand-written-apply) in its Decision Log. Sibling plans are referenced by path only: the
documentation plan that writes down today's contract is
`docs/plans/46-document-the-output-invertibility-contract-and-derived-value-modeling-patterns.md`.
At the time of writing, plan 46 is still a skeleton and the contract page it is meant to
create — `docs/guide/output-invertibility.md` — **does not yet exist** in the working tree
(verified: `docs/guide/` contains no `output-invertibility.md`). Therefore M4 of this plan
must be prepared to *create* that page if it is still absent, rather than amend it. See
Interfaces and Dependencies for the coordination contract.


## Plan of Work

The work proceeds in four milestones. M1 is a design-and-prototype milestone *and a
ratification gate*: it must complete — and be explicitly approved by the maintainer — before
any edit to the core library, because the change touches keiki's foundational invariant. M2
implements the change. M3 proves the behavior with tests. M4 documents the relaxed contract
and closes the plan. M2–M4 are contingent on M1's gate being approved go; if the gate is
no-go, M2–M4 are not executed and the plan is closed as a docs-only outcome (EP-46 carries
Rei keiki #1).


### M1 — Design milestone and ratification gate: formalize, prototype, analyze, then STOP

This milestone is a deliberate ratification gate. Unlike the normal protocol, do NOT proceed
to M2 automatically — stop here, present the analysis, and wait for explicit approval. The
standard ExecPlan implement protocol says "do not prompt the user for next steps; proceed to
the next milestone"; M1 explicitly OVERRIDES that, because relaxing `solveOutput` is the only
change in this initiative that touches keiki's foundational invariant and the maintainer wants
the prototype and analysis presented for explicit feedback and a go/no-go decision before any
core change proceeds. After delivering the design note, the prototype, and the analysis below,
the implementing agent MUST pause, present the findings to the maintainer, and obtain explicit
approval before starting M2.

Scope: produce a research note that formalizes recompute-and-verify and proves it preserves
"the event uniquely determines the command"; a small prototype test that exercises the new
path *before* the production code exists, so the design is validated against the actual types;
and a written analysis with a clear go/no-go recommendation. At the end of M1 there is a new
file `docs/research/recompute-and-verify-derived-outputs.md`, a new green prototype test, and
a recorded go/no-go decision in the Decision Log; no change to `src/Keiki/Core.hs` yet
(regardless of the decision, no core edit happens within M1).

Write `docs/research/recompute-and-verify-derived-outputs.md` covering, in prose:

  1. **The relaxed contract.** State precisely: `solveOutput` succeeds on an `OPack ic ctor
     fields` iff (a) for every slot of `ic`, *some* invertible field (`TInpCtorField ic ·`)
     reads that slot — i.e. the command is fully recoverable from invertible fields alone —
     and (b) every derived field, recomputed forward via `evalTerm` against the recovered
     command and the pre-update registers, equals the observed field value. Contrast with
     today's contract: (a) unchanged in spirit but (b) replaces "every field must be
     invertible" with "every derived field must verify".

  2. **The proof that "event determines command" is preserved.** The argument is short and
     must be written out explicitly: command recovery reads *only* clause (a), which depends
     *only* on invertible fields; derived fields enter *only* in clause (b), which is a
     verification, never a source of command bits. Therefore, if two distinct commands `c1 ≠
     c2` produced the same observed event `o` on the same admitted edge, then because the
     command is a function of the invertible fields' observed values (each `TInpCtorField`
     slot is read out of `o` and fed to `icBuild`), and `o` is the same for both, the
     recovered command is the same — contradiction. Conclude: admitting redundant derived
     fields cannot make two commands collide on one event; the build-time guarantee that the
     event determines the command is intact. (The clause-(b) verification can only *reject*
     more, never *accept* more commands, so it cannot break injectivity either.)

  3. **The field-level `Eq` requirement and where it is demanded.** Recompute-and-verify
     compares each recomputed derived field against the observed field value obtained from
     `wcMatch`. That comparison needs `Eq` on the derived field's *type*. Because `OutFields`
     tracks each field's type structurally (`OFCons :: Term rs ci f -> OutFields rs ci fs ->
     OutFields rs ci (f, fs)`), the constraint can be demanded *per field* at the point the
     comparison happens, not on the whole event type `co`. Specify the exact mechanism:
     either thread an `Eq f` dictionary by adding it to a new term-classifier helper's
     signature for the derived case, or — preferred, because it keeps `Term` and `OutFields`
     unchanged — require `Eq` structurally where the recompute happens by pattern-matching
     the derived `Term` and demanding `Eq f` via a constrained constructor or a `Typeable`+
     dynamic-equality fallback. Decide and record in the note which mechanism M2 will use.
     (Investigate during M1 whether the cleanest path is to add an `Eq r` superclass to the
     `TArith`/`TApp` constructors — note that `TArith` already carries `Num r, Typeable r`,
     and `Num` does not imply `Eq`, so an explicit `Eq r` would be a constructor-level
     constraint addition; weigh that against requiring `Eq` only at the recompute call via a
     separate witness. The note must land on one approach with rationale.) Whichever mechanism
     is chosen, record that the downstream cost is already absorbed: the keiro runtime, the
     only consumer of these replay paths, already demands `Eq co` on every hydration entry
     point (`keiro/src/Keiro/Command.hs` ~line 112), and a derived field's type is a component
     of `co`, so the per-field constraint adds no obligation a keiro user does not already
     meet. This materially lowers the discard risk in criterion (6) below.

  4. **The `checkHiddenInputs` precision refinement.** Specify how the static check
     distinguishes a *redundant* derived field (admit) from a *hidden input* (error). The key
     realization: `visitedSlotsOf`/`goTerm` already descends into derived terms and counts
     their nested `TInpCtorField` slots as visited (`src/Keiki/Core.hs` ~1177–1179). For the
     refinement we must compute *two* visited sets per `InCtor`: the **invertible-visited**
     set (slots read by a top-level `TInpCtorField` field — these are the ones `solveOutput`
     actually recovers) and the **any-visited** set (slots read anywhere, including inside
     derived terms — the current behavior). A schema is well-formed iff every `InCtor` slot
     is in the invertible-visited union. A derived field is *redundant* (and thus admissible)
     iff all its nested slots are in the invertible-visited union; it is a *hidden input* (and
     thus an error) iff it reads a slot not in the invertible-visited union. The note must
     specify the exact warning message change and that the error condition is the
     invertible-visited union failing to cover the slot list (strictly stronger than today's
     any-visited check, which would wrongly pass a hidden-input-only-in-derived schema).

  5. **The newly-admissible term shapes in outputs.** Enumerate: `TArith` (structural
     arithmetic) and both `TApp1`/`TApp2` (opaque function application) become admissible as
     *derived* output fields, *provided* every command slot they read is also read by an
     invertible field. Emphasize that even an opaque `TApp` is fine here, because
     recompute-and-verify only ever runs it **forward** via `evalTerm` (which already handles
     `TApp1`/`TApp2`), never inverts it. Invertibility of the function is never required.

  6. **Promotion/discard criteria.** State: promote the approach to M2 iff (i) the prototype
     test (below) is green, demonstrating a `TArith`-output edge round-tripping; (ii) the
     proof in (2) holds; and (iii) the field-level `Eq` mechanism in (3) compiles against the
     real `OutFields`/`Term` types without weakening any existing constraint. Discard (and
     escalate to the MasterPlan) iff the field-level `Eq` cannot be demanded without an
     invasive change to `Term` that breaks existing call sites — in which case fall back to
     requiring `Eq co` on the whole event type as a documented compromise.

Then write the prototype test. Create `test/Keiki/RecomputeVerifySpec.hs` (added to the
`other-modules` of the `keiki-test` stanza in `keiki.cabal` and imported+invoked in
`test/Spec.hs`). The prototype must, at M1, exercise the recompute-and-verify *logic* in
isolation, before the production `solveOutput` is changed — for example by defining a tiny
local function that mirrors the intended new `solveOutput` arm (recover command from
invertible fields, recompute the derived field with `evalTerm`, compare) over a one-edge,
one-derived-field fixture. It must demonstrate two things: (a) a `TArith`-output edge
round-tripping — a matching event recovers the command, and a tampered event (derived field
altered) is rejected; and (b) a determinism-preservation check that the recovered command is
still **unique** — over a small grid of command-field values, distinct commands always yield
distinct observed events and each round-trips to exactly its originating command, so admitting
the redundant derived field does not let two commands collide on one event. Keep this
prototype clearly labelled "M1 prototype" in a comment; M2 may delete it once the production
path subsumes it, or keep it as a focused unit test.

Then write the analysis. The gate requires more than the note's formalization and a green
prototype — it requires a written analysis the maintainer can read and decide on. Capture it
as a dedicated "Analysis and recommendation" section of
`docs/research/recompute-and-verify-derived-outputs.md` (and summarize its conclusion in this
plan's Decision Log when M1 is presented). The analysis must:

  - (a) **State the soundness argument and where it could fail.** Restate the proof from
    section 2 that command recovery reads only invertible fields and derived fields only
    verify, and then honestly enumerate where it could break down — e.g. a derived field whose
    nested command read is *not* in fact covered by an invertible field (a hidden input that
    the static check must catch), a field-level `Eq` that disagrees with the `Eq` keiro uses
    for tail matching, or an `evalTerm` recompute that reads a register written *after* the
    edge (pre- vs. post-update register-file timing).
  - (b) **Enumerate risks and the blast radius.** Name exactly what M2 would touch —
    `solveOutput`, `gatherInpEntries`/`stepOne` (becoming `classifyFields`), and
    `checkHiddenInputs` — and assess the risk to each: the additive fast path for
    all-invertible edges (should be byte-for-byte unchanged), the new register-file use inside
    `solveOutput` (currently `_regs`), and the strictly-stronger well-formedness condition in
    `checkHiddenInputs` (must not regress any existing fixture). State which existing tests act
    as the regression guard.
  - (c) **Weigh the docs-only alternative as a legitimate outcome.** Explicitly consider
    KEEPING Rei keiki #1 docs-only — i.e. not relaxing `solveOutput` at all. The sibling
    `docs/plans/46-document-the-output-invertibility-contract-and-derived-value-modeling-patterns.md`
    already documents today's contract and the Direction-A mirror-command workaround, so a
    no-go does not leave the finding unaddressed; it leaves it documented rather than fixed in
    the core. Lay out the cost of that path (consumers keep paying the mirror-command tax) vs.
    the benefit (the foundational invariant is not touched at all).
  - (d) **Give a clear recommendation** — go or no-go — with the reasoning that supports it,
    so the maintainer has a concrete proposal to accept or override.

Commands to run (working directory `/Users/shinzui/Keikaku/bokuno/keiki`):

    cabal build keiki
    cabal test keiki-test --test-options='--match "RecomputeVerify"'

Acceptance for M1 is the **gate**, not "tests green" alone. M1 is complete only when: the
research note exists and contains sections 1–6 above plus the analysis (a)–(d); the prototype
test compiles and passes, demonstrating both the `TArith` round-trip and the
determinism-preservation (uniqueness) check (its lines appear under a passing hspec group; see
Validation for how to read hspec output); the analysis and recommendation have been
**presented to the maintainer**; and an explicit go/no-go decision has been **recorded in the
Decision Log**. The go/no-go criteria are concrete. Proceed to M2 (go) iff: the soundness
argument in (a) holds, the prototype shows both the round-trip and the recovered command still
unique, the field-level `Eq` mechanism from section 3 compiles against the real
`OutFields`/`Term` types without weakening any existing constraint, and the maintainer judges
the blast radius from (b) acceptable. Stop at docs-only (no-go) iff: any of those fail, the
field-level `Eq` cannot be demanded without an invasive `Term` change that breaks call sites,
or the maintainer prefers — for now — not to touch the foundational invariant and to keep Rei
keiki #1 as the documented contract carried by EP-46. Do NOT proceed to M2 until the maintainer
has approved go.


### M2 — Implement recompute-and-verify in the core

M2 must not begin until M1's ratification gate is approved go and that approval is recorded in
the Decision Log; if the decision is no-go, M2–M4 are not executed and the plan is closed as a
docs-only outcome (EP-46 carries Rei keiki #1).

Scope: change `solveOutput`/`gatherInpEntries`/`stepOne` so derived fields take a
recompute-verify path instead of returning `Nothing`, and refine `checkHiddenInputs` for
precision. At the end of M2 the library compiles, the M1 prototype still passes, and a
derived-output edge round-trips through `solveOutput`. This plan **owns** all edits to these
four symbols; the sibling plan
`docs/plans/46-document-the-output-invertibility-contract-and-derived-value-modeling-patterns.md`
only documents their behavior and must not modify them.

Edits in `src/Keiki/Core.hs`:

  1. **Thread the register file and the observed value into the field walk.** Today
     `gatherInpEntries`/`stepOne` see the field `Term`, the observed field value `v`, and the
     `InCtor`. For recompute they additionally need the register file (to run `evalTerm`).
     `solveOutput` already receives `regs` (currently `_regs`); rename it to `regs` and pass
     it down. The recovered command, however, is only known *after* the invertible fields are
     gathered. Therefore split the walk into two phases:

       - **Phase 1 (gather):** walk the `OutFields` exactly as today, but where `stepOne`
         currently returns `Nothing` for a derived term, instead classify it as "deferred"
         and *skip* it for command recovery (contributing no `ByIndex` entries). Keep the
         invertible cases unchanged. Collect, alongside the `[ByIndex ifs]`, a list of
         deferred *(derived `Term`, observed value)* pairs. (The nested `TInpCtorField`s
         inside a derived term are intentionally **not** harvested for recovery — recovery
         must come from a top-level invertible field, per the contract; the static check in
         step 3 guarantees they are redundantly covered.)

       - **Phase 2 (recompute-verify):** after `assemble entries` yields the `RegFile ifs`
         and `icBuild ic rf` yields the recovered command `ci`, fold over the deferred pairs:
         for each `(t, observed)` compute `evalTerm t regs ci` and check it `== observed`. If
         all match, return `Just ci`; if any mismatches, return `Nothing`. This is where the
         field-level `Eq` is demanded, via the mechanism chosen in M1.

     Concretely, `solveOutput` becomes (shape, not final text):

        solveOutput (OPack ic@InCtor{} ctor fields) regs co = do
          fs_obs            <- wcMatch ctor co
          (entries, derived) <- classifyFields fields fs_obs ic
          rf                <- assemble entries
          let ci = icBuild ic rf
          if all (\(t, observed) -> evalTerm t regs ci `eqAt` observed) derived
            then Just ci
            else Nothing

     where `classifyFields` is the renamed/extended `gatherInpEntries` returning both the
     invertible `[ByIndex ifs]` and the deferred derived `[(SomeDerived, value)]`, and
     `eqAt` is the field-level equality from M1. The exact representation of the deferred
     list (existential wrapper carrying the `Eq` evidence, vs. a closure already capturing
     the comparison) is fixed by M1's decision; implement that.

  2. **Keep the invertible path as the fast path.** Edges whose every field is invertible
     produce an empty `derived` list, so Phase 2 is a no-op `all (const True) []` and the
     behavior is byte-for-byte identical to today. This makes the change additive: existing
     fixtures (e.g. `Keiki.Fixtures.UserRegistration`, whose every output field is `TReg`/
     `TInpCtorField`) are unaffected.

  3. **Refine `checkHiddenInputs`.** Replace the single `visitedSlotsOf` with the two-set
     computation from M1: an **invertible-visited** set (slots read by a *top-level*
     `TInpCtorField` field of the `OutFields`) and the existing **any-visited** set. Change
     the well-formedness condition (`unionMisses`) so the missing-slot computation uses the
     **invertible-visited** union: `missing = allSlots \\ nub invertibleVisitedUnion`. This
     is strictly stronger than today's any-visited check and correctly *fails* a schema whose
     command slot appears only inside a derived term (a hidden input), while *passing* a
     schema where a derived field is redundant (its slots also appear top-level invertibly).
     Update the haddock on `checkHiddenInputs` and the warning text in `formatMiss` if its
     wording references "visited" in a way the refinement changes.

     Note the subtlety: the current `goTerm` descends into derived terms and counts their
     nested slots as visited. For the *invertible-visited* set we must **not** descend into
     derived terms — only count a slot when the *top-level field's* `Term` is itself a
     `TInpCtorField`. Implement a second walker (e.g. `invertibleVisitedSlotsOf`) that
     inspects only the head constructor of each `OutFields` entry and does not recurse into
     `TApp`/`TArith`. Keep the existing `visitedSlotsOf` (any-visited) if it is still useful
     for diagnostics, or drop it if unused after the change.

  4. **Confirm `applyEvent`/`applyEventStreaming` need no change.** Both call `solveOutput`
     and already pass `regs`; once `solveOutput` uses `regs`, they transparently get the new
     behavior. Verify by reading (~882–966) that no caller relies on `solveOutput` ignoring
     `regs`. (It does not; the parameter was simply unused.)

Commands to run (working directory `/Users/shinzui/Keikaku/bokuno/keiki`):

    cabal build keiki
    cabal test keiki-test

Acceptance for M2: the library builds with no new warnings (the stanza uses `-Wall -Wcompat
-Wredundant-constraints`; an unused-`regs` warning would have appeared before — confirm it is
gone now that `regs` is used); the full existing suite still passes (no regression in the
all-invertible fast path); and the M1 prototype, now able to call the real `solveOutput`,
still passes.


### M3 — Tests proving the behavior

Scope: three behavior tests. At the end of M3 the new behavior is demonstrated end-to-end,
the foundational guarantee is checked by a property/enumeration test, and the build-time
safety net is shown to still catch malformed schemas. Put these in
`test/Keiki/RecomputeVerifySpec.hs` (the module from M1) or a sibling
`test/Keiki/RecomputeVerifyAggregateSpec.hs` if separating the fixture is cleaner; register
whichever modules exist in `keiki.cabal` and `test/Spec.hs`.

Build a small **order-cart fixture** in the test tree (do not pollute `src/`). It has one
command `AddLineItem { quantity :: Int, unitPrice :: Int }` and one event `LineItemAdded {
quantity :: Int, unitPrice :: Int, lineTotal :: Int }` where `lineTotal` is emitted as the
derived term `inpAdd #quantity .* inpAdd #unitPrice` (using the `.*` arithmetic operator
from `src/Keiki/Core.hs` ~line 703, which builds `TArith OpMul`). The `quantity` and
`unitPrice` event fields are plain `TInpCtorField` reads, so they are the invertible fields
that recover the command; `lineTotal` is the redundant derived field. Author it either via
the `Keiki.Builder` DSL (mirroring `Keiki.Fixtures.UserRegistration`) or directly as an AST
`SymTransducer` (mirroring `userRegAST` in the same fixture file). Derive the `WireCtor`/
`InCtor` with the TH helpers `deriveWireCtors`/`deriveAggregateCtors` as that fixture does.

Test (i) — **round-trip.** Assert that before this change `solveOutput` on the
`LineItemAdded` edge would return `Nothing` (you cannot run "before" in the same build, so
document the before/after as a transcript in this plan and in a comment; see Validation), and
that *after* this change `applyEvents cart (initial cart, initialRegs cart) [LineItemAdded
{quantity = 3, unitPrice = 7, lineTotal = 21}]` returns `Just (s, regs)` with the expected
target state and register writes. Add a second case proving the verify half bites: replaying
a *tampered* event `LineItemAdded {quantity = 3, unitPrice = 7, lineTotal = 999}` returns
`Nothing` (the recomputed `3*7 = 21 ≠ 999`).

Test (ii) — **event determines command (determinism preservation).** keiki's test suite
uses `hspec` only (no QuickCheck/Hedgehog is a dependency; see `keiki.cabal` build-depends),
so express this as an *enumeration* property: over a finite grid of `(quantity, unitPrice)`
pairs (e.g. `[0..5] × [0..5]`), for every pair build the event the edge would emit
(`evalOut` of the edge's head output against the command), invert it with `solveOutput`, and
assert the recovered command equals the original. Then assert *injectivity directly*: no two
distinct pairs in the grid produce the same observed event whose `solveOutput` yields a
command different from the originating one. (Because the invertible `quantity`/`unitPrice`
fields alone determine the command, distinct commands always yield distinct observed events;
the test makes this concrete.) If a property-test library is later added, this can be
restated as a generator-driven property, but the enumeration is sufficient and dependency-free.

Test (iii) — **negative: a genuine hidden input still fails the build-time check.** Build a
*malformed* variant of the cart edge where the only field carrying `quantity` is the derived
`lineTotal` term (i.e. drop the top-level `inpAdd #quantity` invertible field, so `quantity`
is read **only** inside `lineTotal`). Assert `checkHiddenInputs` on that transducer returns a
non-empty list naming the `AddLineItem` `InCtor` and the missing `quantity` slot. This proves
the precision refinement still flags real hidden inputs. Mirror the existing
`test/Keiki/CoreHiddenInputsGSMSpec.hs` style for invoking and asserting on `checkHiddenInputs`.

Commands to run (working directory `/Users/shinzui/Keikaku/bokuno/keiki`):

    cabal test keiki-test --test-options='--match "RecomputeVerify"'
    cabal test keiki-test

Acceptance for M3: all three tests pass; the full suite is green; the negative test fails
the build-time check (i.e. `checkHiddenInputs` returns a warning) for the malformed schema
and returns `[]` for the well-formed redundant-derived schema.


### M4 — Document the relaxed contract and close

Scope: bring the consumer-facing documentation in line with the new behavior, and close the
plan. At the end of M4 the contract page describes recompute-and-verify, the user guide's
glossary mentions derived-field round-tripping, and the living sections of this plan are
final.

The shared contract artifact is `docs/guide/output-invertibility.md`, owned jointly with the
sibling documentation plan
`docs/plans/46-document-the-output-invertibility-contract-and-derived-value-modeling-patterns.md`.
That sibling is responsible for *creating* the page describing today's (strict) behavior;
this plan's M4 *amends* it to the relaxed behavior. **Coordination rule:** if, when M4 runs,
`docs/guide/output-invertibility.md` does not yet exist (it currently does not), this plan
must *create* it instead of amending it, writing the relaxed contract directly and noting at
the top that the strict-behavior history lives in EP-46's narrative. If it does exist, edit
it: change the "which term shapes round-trip" section so `TArith`/`TApp1`/`TApp2` are listed
as *admissible as derived fields under recompute-and-verify* (with the redundancy
precondition spelled out), and add a worked "store a computed total" recipe pointing at the
order-cart example.

Also amend `docs/guide/user-guide.md`: locate its glossary/section on output invertibility
(search for `solveOutput`, `invertib`, or `TInpCtorField`) and add a short paragraph stating
that derived output fields now round-trip via recompute-and-verify, with a one-line pointer
to `docs/guide/output-invertibility.md` and to the research note
`docs/research/recompute-and-verify-derived-outputs.md`.

Commands to run (working directory `/Users/shinzui/Keikaku/bokuno/keiki`): none beyond a docs
read-through and a final `cabal test keiki-test` to confirm nothing regressed. Acceptance for
M4: the contract page documents recompute-and-verify; the user guide cross-links it; this
plan's Progress shows M1–M4 complete and the Outcomes & Retrospective is written.


## Concrete Steps

All commands run from the repository root `/Users/shinzui/Keikaku/bokuno/keiki`.

Establish the baseline before any change (so you can compare):

    cabal build keiki
    cabal test keiki-test

Expected: the build succeeds; the suite prints a run ending with a summary line of the form
`Finished in N.NNNN seconds` followed by `K examples, 0 failures`. Record `K` (the example
count) so you can confirm later that you only *added* examples.

M1 — create the design note, the prototype, and the analysis, then:

    cabal test keiki-test --test-options='--match "RecomputeVerify"'

Expected, before any production change, with only the M1 prototype present: a small group
like

    Keiki.RecomputeVerify (M1 prototype)
      recomputes and verifies a TArith-output field against a matching event
      rejects a tampered derived field
      recovers a unique command for every command in the grid (determinism preserved)

with `0 failures` for the matched subset. Then STOP: this is the ratification gate. Present
the design note, the prototype result, and the analysis with its go/no-go recommendation to
the maintainer, and record the maintainer's explicit go/no-go decision in the Decision Log. Do
NOT proceed to M2 automatically — unlike the normal protocol, M1 ends by waiting for explicit
approval. If the decision is no-go, do not run the M2–M4 steps below; close the plan as a
docs-only outcome (EP-46 carries Rei keiki #1).

M2 (only after a recorded go decision) — edit `src/Keiki/Core.hs` (`solveOutput`,
`gatherInpEntries`/`stepOne` →
`classifyFields`, `checkHiddenInputs`), then:

    cabal build keiki
    cabal test keiki-test

Expected: build clean (no unused-`regs` warning, no new warnings under `-Wall`); the suite
shows the *same* example count as the M1 baseline plus the M1 prototype, all passing.

M3 — add the order-cart fixture and the three behavior tests, then:

    cabal test keiki-test --test-options='--match "RecomputeVerify"'
    cabal test keiki-test

Expected, focused run:

    Keiki.RecomputeVerify
      round-trips a derived-total LineItemAdded event through applyEvents
      rejects a tampered lineTotal on replay
      recovers the command for every (quantity, unitPrice) in the grid
      flags a hidden-input schema at build time via checkHiddenInputs

with `0 failures`; the full run ends `… examples, 0 failures`.

M4 — edit/create `docs/guide/output-invertibility.md` and amend
`docs/guide/user-guide.md`, then re-run the suite once to confirm no regression:

    cabal test keiki-test


## Validation and Acceptance

The decisive, observable acceptance is a behavior change visible through `applyEvents`, not a
mere recompilation. State it as a before/after transcript on the order-cart fixture's
`LineItemAdded` event whose `lineTotal` field is the derived term `quantity * unitPrice`.

Before this change (today's strict `solveOutput`), replaying that event returns `Nothing`
because the derived `lineTotal` field hits `stepOne (TArith _ _ _) = Nothing`
(`src/Keiki/Core.hs` ~1071), aborting the whole inversion:

    -- BEFORE (illustrative; cannot be run after the change in the same build)
    > applyEvents cart (initial cart, initialRegs cart)
        [ LineItemAdded { quantity = 3, unitPrice = 7, lineTotal = 21 } ]
    Nothing

After this change, the same call recovers the command from the invertible `quantity`/
`unitPrice` fields, recomputes `lineTotal` as `evalTerm (inpAdd #quantity .* inpAdd
#unitPrice) regs ci = 3 * 7 = 21`, checks `21 == 21`, and replays successfully:

    -- AFTER
    > applyEvents cart (initial cart, initialRegs cart)
        [ LineItemAdded { quantity = 3, unitPrice = 7, lineTotal = 21 } ]
    Just (<target state>, <registers with quantity/unitPrice written>)

And the verify half is observable too — a tampered derived value is rejected:

    -- AFTER (tampered lineTotal)
    > applyEvents cart (initial cart, initialRegs cart)
        [ LineItemAdded { quantity = 3, unitPrice = 7, lineTotal = 999 } ]
    Nothing

Because `RegFile` has no `Show` instance (see the comment in
`test/Keiki/CoreApplyEventsSpec.hs` ~line 66), assert on these by pattern-matching the
`Maybe` and reading specific slots with `(!)`, exactly as `CoreApplyEventsSpec` does:

    case applyEvents cart (initial cart, initialRegs cart)
           [ LineItemAdded { quantity = 3, unitPrice = 7, lineTotal = 21 } ] of
      Just (s, regs) -> (s, regs ! #quantity, regs ! #unitPrice)
                          `shouldBe` (<target>, 3, 7)
      Nothing        -> expectationFailure "expected the derived event to round-trip"

The exact test commands (run from `/Users/shinzui/Keikaku/bokuno/keiki`):

    cabal test keiki-test

runs the entire suite. To run only this plan's tests:

    cabal test keiki-test --test-options='--match "RecomputeVerify"'

The test driver is `hspec` (configured in `test/Spec.hs`; `keiki.cabal` test-suite type is
`exitcode-stdio-1.0`). `--test-options` are passed through to the hspec runner; `--match
"RecomputeVerify"` selects only describe/it nodes whose path contains that substring.
Interpret results by the final summary line: success ends with `N examples, 0 failures` and
`cabal` exits 0; any failure prints the failing example with `expected:`/`got:` (or the
`expectationFailure` message) and `cabal` exits non-zero. The build-time safety net for the
hidden-input case is exercised inside the suite by calling `checkHiddenInputs` on a malformed
fixture and asserting a non-empty warning list — there is no separate compile-failure step,
because `checkHiddenInputs` is a runtime lint returning `[HiddenInputWarning]`, not a type
error (this matches `test/Keiki/CoreHiddenInputsGSMSpec.hs`).

M1 acceptance is the **ratification gate**, and it is distinct from the behavioral acceptance
of M2–M4 below. M1 is accepted when, and only when: the research note exists with sections 1–6
plus the analysis (soundness argument and where it could fail; risks and blast radius on
`solveOutput`/`gatherInpEntries`/`checkHiddenInputs`; the docs-only alternative weighed; a
clear recommendation); the prototype passes, demonstrating both the `TArith` round-trip and
the determinism-preservation (recovered command still unique) check; the analysis and
recommendation have been presented to the maintainer; and an explicit go/no-go decision is
recorded in the Decision Log. M1 acceptance is NOT "tests green" alone — a green prototype
without a recorded decision is not acceptance. If the recorded decision is no-go, the plan is
accepted as a docs-only outcome (EP-46 carries Rei keiki #1) and the M2–M4 behavioral
acceptance below does not apply.

Behavioral acceptance for M2–M4 (applicable only after a recorded go decision), summarized as
behavior: (1) a derived-value event that returns `Nothing` from `solveOutput`/`applyEvents`
*before* this change round-trips *after* it (round-trip test); (2) a tampered derived value is
rejected (verify test); (3) over an enumerated grid, the recovered command always equals the
originating command and distinct commands never collide on one event (determinism test); (4) a
schema with a genuine hidden input still produces a `checkHiddenInputs` warning (negative
test); (5) the entire pre-existing suite remains green (no regression in the all-invertible
fast path).


## Idempotence and Recovery

Every step here is safe to repeat. `cabal build` and `cabal test` are idempotent; re-running
them after a partial edit simply recompiles what changed. The documentation edits (M4) are
ordinary file writes; re-running them overwrites to the same content.

The one risk area is the `src/Keiki/Core.hs` change in M2, because it touches the core
invertibility path. Mitigations: the change is *additive* — the all-invertible path is
preserved byte-for-byte (an empty `derived` list makes Phase 2 a no-op), so existing
behavior is unchanged and the existing suite is the regression guard. If M2 goes wrong,
recover by reverting `src/Keiki/Core.hs` to its committed state with `git checkout --
src/Keiki/Core.hs`; the M1 research note and prototype remain valid and unaffected. Commit
after each milestone (M1, M2, M3, M4 separately) so any milestone can be rolled back
independently with `git revert`. Do not create a feature branch unless asked; commit directly
to the current branch per the repository's branch policy.

If the M1 investigation finds that the field-level `Eq` cannot be demanded without an
invasive `Term` change (the discard criterion), do not force it: fall back to the documented
`Eq co` compromise, record the decision and evidence in the Decision Log and Surprises &
Discoveries, and update M2 accordingly before proceeding. The plan remains restartable from
its text alone in either case.


## Interfaces and Dependencies

Libraries and modules used, and why:

  - `Keiki.Core` (`src/Keiki/Core.hs`) — the module this plan modifies. The owned symbols
    are `solveOutput` (~1039), `gatherInpEntries`/`stepOne` (~1054–1071, becoming a
    `classifyFields`-style helper), and `checkHiddenInputs` (~1104) with its internal
    `visitedSlotsOf`/`goTerm`/`unionMisses`/`groupByInCtorName` helpers (~1132–1184). The
    forward interpreter `evalTerm` (~728) is *used* (for recompute) but not modified; the
    output evaluator `evalOut` (~752) is used in tests. `applyEvent` (~882) and
    `applyEventStreaming`/`applyEvents`/`reconstitute` (~940/1017/980) consume `solveOutput`
    and gain the new behavior transparently.
  - `Keiki.Builder` (`src/Keiki/Builder.hs`) and `Keiki.Generics.TH`
    (`Keiki.Generics.TH.deriveWireCtors`/`deriveAggregateCtors`) — used only in the test
    fixtures to author the order-cart aggregate, exactly as `Keiki.Fixtures.UserRegistration`
    does. Not modified.
  - `hspec` — the test driver (already a test-suite dependency in `keiki.cabal`). New test
    modules are registered in the `other-modules` list of the `keiki-test` stanza in
    `keiki.cabal` and imported+invoked in `test/Spec.hs`.

Types, interfaces, and signatures that must exist at the end of each milestone:

  - End of M1: a new file `docs/research/recompute-and-verify-derived-outputs.md` containing
    the formalization (sections 1–6 of M1). A new test module
    `test/Keiki/RecomputeVerifySpec.hs` exporting `spec :: Spec`, registered in `keiki.cabal`
    and `test/Spec.hs`, containing the M1 prototype. No change to `src/Keiki/Core.hs`.
  - End of M2: `solveOutput :: OutTerm rs ci co -> RegFile rs -> co -> Maybe ci` — *signature
    unchanged*, but the implementation now uses its `RegFile` argument and admits derived
    fields via recompute-and-verify. The field-walk helper returns both the invertible
    `[ByIndex ifs]` and a deferred list of derived `(Term, observed-value)` pairs (exact type
    fixed by M1's `Eq` decision). `checkHiddenInputs :: (Bounded s, Enum s, Show s) =>
    SymTransducer phi rs s ci co -> [HiddenInputWarning]` — *signature unchanged*, but the
    well-formedness condition now uses an *invertible-visited* slot union (a new internal
    walker that does not descend into derived terms), making the check both more precise
    (admits redundant-derived) and still safe (errors on hidden inputs). The field-level `Eq`
    requirement introduced by recompute-and-verify is **this plan's** to define and is
    demanded per derived field, not as `Eq co` (unless the M1 discard fallback applies).
  - End of M3: the test modules under `test/Keiki/` containing the round-trip, determinism,
    and negative tests, all green.
  - End of M4: `docs/guide/output-invertibility.md` documenting the relaxed contract (created
    here if the sibling EP-46 has not yet created it), and an amended `docs/guide/user-guide.md`
    glossary entry cross-linking it.

Cross-plan integration points (stated so neither plan diverges silently):

  1. **This plan owns the code; EP-46 owns the docs of *today's* behavior.** All edits to
     `solveOutput`/`gatherInpEntries`/`stepOne`/`checkHiddenInputs` in `src/Keiki/Core.hs`
     belong to this plan. The sibling
     `docs/plans/46-document-the-output-invertibility-contract-and-derived-value-modeling-patterns.md`
     describes the *strict* current behavior and must not modify those symbols. The handoff:
     EP-46 writes "today: only `TLit`/`TReg`/`TInpCtorField` round-trip"; this plan's M4
     flips that page to "now: derived fields also round-trip via recompute-and-verify".
  2. **The field-level `Eq` requirement is this plan's to define** (per the MasterPlan
     Integration Points). It is demanded per derived field via the M1 mechanism, not on the
     whole event type `co`.
  3. **Soft dependency on EP-46 for the contract page.** EP-46 is expected to create
     `docs/guide/output-invertibility.md`. As verified at authoring time, that page does not
     yet exist; therefore M4 must *create* it if it is still absent when M4 runs, rather than
     assume an amend target. Either way the page must end up describing recompute-and-verify.


## Revision Notes


### 2026-05-21 — Folded in consumer (Rei) and runtime (keiro) validation findings

Reviewed this plan against live source in `../keiro` and `../rei-project/rei.keiro-migration`
and updated four sections to reflect what that validation confirmed. The *why*: this plan
sits in MasterPlan-13, which is driven by the Rei migration; before committing to the riskiest
core edit in that initiative, the plan's premise — that the fix belongs in keiki and not the
runtime — needed checking against the actual consumer and runtime, and the validated facts
materially de-risk the design (the `Eq` cost is already paid downstream) and sharpen the M3
test scope (three lookalike "replay failed" signals must not be conflated).

Changes:

  - **Purpose / Big Picture.** Strengthened the motivation to state the harsher trigger — a
    *single* non-invertible field makes `gatherInpEntries` return `Nothing` and kills the
    whole edge, dragging even an aggregate with one state-resolved field into the mirror
    workaround — and named removing that "one field poisons the edge" failure as the concrete
    win. Added an attribution paragraph proving the fix must live in keiki: keiro's `hydrate`
    stores only events (the Kiroku `RecordedEvent` carries no command field), reconstructs via
    `Keiki.applyEventStreaming`, and turns its `Nothing` into the keiro-owned
    `HydrationReplayFailed`; every keiki state-reconstruction primitive recovers the command
    via `solveOutput` and keiki exposes no inversion-free forward fold, so keiro cannot fix
    this without a storage-format change.
  - **Context and Orientation.** Added a subsection on how keiro consumes this: keiro already
    requires `Eq co` for all hydration (`keiro/src/Keiro/Command.hs` ~line 112), so the new
    field-level `Eq` adds no consumer burden; the fix benefits both keiro's replay path
    (`applyEventStreaming` via `hydrate`) and snapshot path (`applyEvents` via
    `writeSnapshotIfNeeded`, ~line 440). Added a caution not to conflate the inversion
    `Nothing` with two keiro-owned signals — a final `InFlight` wrapper (also surfaced as
    `HydrationReplayFailed`) and a JSON codec failure (`HydrationDecodeFailed`).
  - **Decision Log.** Extended the field-level `Eq` decision with the verified cost note (no
    new keiro burden), and added a new decision scoping the M3 inversion tests to the
    `solveOutput` path and explicitly excluding the two keiro-owned lookalike failures.
  - **M1 design milestone.** In the `Eq`-mechanism investigation (section 3), recorded that
    the downstream cost is already absorbed by keiro's existing `Eq co`, lowering the discard
    risk in the promotion/discard criteria.

No code, no milestone count change (still four), and the Progress checklist is untouched. The
YAML frontmatter was not modified.


### 2026-05-21 — M1 reframed as an explicit feedback-and-ratification gate

Reframed M1 so that the design milestone is now an explicit FEEDBACK-AND-RATIFICATION GATE.
The prototype still gets built, but the plan must stop and request human analysis and approval
BEFORE any change to the core. The *why*: relaxing `solveOutput` is the only change in this
whole initiative that touches keiki's foundational invariant — that the event uniquely
determines the command, certified at build time. The maintainer is not yet comfortable
committing to that relaxation; they want the prototype and analysis done, but presented for
explicit feedback and a go/no-go decision before the real core change proceeds. This overrides
the normal ExecPlan implement protocol (which says do not prompt for next steps and proceed to
the next milestone) for M1 only.

Changes:

  - **Purpose / Big Picture.** Added a paragraph stating up front that M1 is a ratification
    gate that OVERRIDES the auto-proceed protocol: after delivering the design note, prototype,
    and analysis, the agent must pause, present findings, and wait for explicit approval before
    M2; a no-go (keep Rei keiki #1 docs-only, EP-46 carrying it) is a legitimate outcome.
  - **Progress.** Reworded the M1 checklist item to read as a gate: "research note + prototype
    + analysis; STOP for maintainer go/no-go before M2", and noted the prototype now also shows
    the determinism-preservation (recovered command still unique) check. Still four items.
  - **Plan of Work M1.** Renamed the milestone to "Design milestone and ratification gate" and
    led with the hard-stop language ("This milestone is a deliberate ratification gate. Unlike
    the normal protocol, do NOT proceed to M2 automatically — stop here, present the analysis,
    and wait for explicit approval."). Added the determinism-preservation prototype requirement
    and a new "write the analysis" deliverable: (a) soundness argument and where it could fail,
    (b) risks and blast radius on `solveOutput`/`gatherInpEntries`/`checkHiddenInputs`, (c) the
    docs-only alternative weighed as a legitimate outcome, (d) a clear go/no-go recommendation.
    Rewrote M1 acceptance as the gate (note + prototype + analysis delivered, presented,
    decision recorded) with concrete go vs. docs-only criteria.
  - **Plan of Work M2 + Plan-of-Work intro.** Added that M2 must not begin until M1's gate is
    approved go, and that a no-go closes the plan as a docs-only outcome (M2–M4 not executed).
  - **Concrete Steps.** Reframed the M1 step to create note + prototype + analysis, then STOP
    for the gate, and gated the M2–M4 steps on a recorded go decision.
  - **Validation and Acceptance.** Made M1's acceptance the gate (analysis presented + decision
    recorded), distinct from and preceding the M2–M4 behavioral acceptance.
  - **Decision Log.** Added an entry (2026-05-21) recording the maintainer's reservation about
    relaxing the foundational invariant and the decision to make M1 a ratification gate, with
    the concrete go and no-go criteria.

No change to the technical design of recompute-and-verify, no milestone count change (still
four), and the YAML frontmatter was not modified.
