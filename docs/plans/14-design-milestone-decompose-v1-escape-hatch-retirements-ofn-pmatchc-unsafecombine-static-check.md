---
id: 14
slug: design-milestone-decompose-v1-escape-hatch-retirements-ofn-pmatchc-unsafecombine-static-check
title: "Design milestone — decompose v1 escape hatch retirements (OFn, PMatchC, unsafeCombine static check)"
kind: exec-plan
created_at: 2026-05-02T13:04:12Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
master_plan: "docs/masterplans/6-retire-remaining-v1-escape-hatches-in-pure-core-ofn-pmatchc-unsafecombine-static-check.md"
---

# Design milestone — decompose v1 escape hatch retirements (OFn, PMatchC, unsafeCombine static check)

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

Three v1 escape hatches in keiki's pure-core DSL — `OFn`, `PMatchC`,
and `unsafeCombine` — were deferred by MasterPlan 2's 2026-05-01
decision log entry to "a future MasterPlan once v2 lands." That
MasterPlan is `docs/masterplans/6-retire-remaining-v1-escape-hatches-in-pure-core-ofn-pmatchc-unsafecombine-static-check.md`
(MP-6). MP-6 starts with a single design-milestone child plan — this
plan — whose terminal output is a recommendation that decomposes the
retirement work into one or more per-retirement implementation plans.
At the end of this plan there is **no behavioural change to the
library**: the value delivered is a design note (or a small set of
notes) plus an updated MP-6 Exec-Plan Registry that names the
implementation work clearly enough for any contributor to pick up.

The three escape hatches and what they currently look like:

- **`OFn :: (RegFile rs -> ci -> co) -> OutTerm rs ci co`** in
  `src/Keiki/Core.hs`. Authored through `mkOut`. `solveOutput` returns
  `Nothing` on `OFn`-shaped edges and `checkHiddenInputs` flags them.
  Used by `Keiki.Examples.UserRegistration` for outputs whose shape
  doesn't fit the structural `OPack` form.

- **`PMatchC :: (ci -> Bool) -> HsPred rs ci`** in `src/Keiki/Core.hs`.
  Authored through `matchCmd`. The SBV-backed `BoolAlg` instance in
  `src/Keiki/Symbolic.hs` cannot translate `PMatchC` and falls back to
  a syntactic over-approximation. EP-2 of MP-2 added
  `PInCtor :: InCtor ci ifs -> HsPred rs ci` and `matchInCtor` as a
  structural alternative for the constructor-equality case, but kept
  `PMatchC` for back-compat.

- **`unsafeCombine :: Update rs ci -> Update rs ci -> Update rs ci`**
  in `src/Keiki/Core.hs`. Bypasses the runtime "distinct targets"
  check that the smart constructor `combine :: Update rs ci -> Update
  rs ci -> Either String (Update rs ci)` enforces. Used inside
  `Keiki.Examples.UserRegistration` for ergonomic chaining of
  multi-slot updates and inside `src/Keiki/Composition.hs:416` where
  the two halves are disjoint by construction (left writes into
  `rs1`'s prefix via `weakenLUpdate`; right writes into `rs2`'s suffix
  via `substUpdate`).

What this plan must settle:

1. **Successor surface for each escape hatch.** For `OFn`: is there a
   structural form that covers all current uses, or do some edges
   keep an opaque escape hatch (renamed/deprecated)? For `PMatchC`: is
   `PInCtor` plus the existing `PEq`/`PAnd`/`POr`/`PNot` algebra
   sufficient, or is a richer pattern AST needed? For `unsafeCombine`:
   what is the type-level encoding (likely `Update (rs :: [Slot])
   (written :: [Slot]) ci` with `Disjoint w1 w2` on `UCombine`), and
   how does the Composition use site at
   `src/Keiki/Composition.hs:416` adopt it without per-call-site
   proof obligations?

2. **Decomposition.** Are these three retirements one EP, two EPs,
   or three EPs? Bundling depends on whether the successor surfaces
   share design machinery (e.g. if `OFn` and `PMatchC` both end up
   needing a constrained-Generics pass).

3. **Migration story.** For each retirement, name the call sites in
   `Keiki.Examples.UserRegistration`, `UserRegistrationV0`,
   `EmailDelivery`, and `Keiki.Composition` that change, and whether
   the change is mechanical or requires hand-editing.

4. **MasterPlan revision.** Apply the chosen decomposition by editing
   `docs/masterplans/6-retire-remaining-v1-escape-hatches-in-pure-core-ofn-pmatchc-unsafecombine-static-check.md`:
   add per-retirement EP rows to the Exec-Plan Registry, update the
   Dependency Graph and Integration Points to match, and append a
   revision note at the bottom of MP-6 per the MasterPlan revision
   protocol.

The design milestone is judged complete when the design note(s) exist
in `docs/research/`, MP-6's Exec-Plan Registry names the
implementation EPs (or is updated to say "design milestone bundled
all impl into EP-15 directly" if that turns out to be the right
call), and `cabal build` still succeeds with no source changes from
this plan.


## Progress

Use a checklist to summarize granular steps. Every stopping point
must be documented here, even if it requires splitting a partially
completed task into two ("done" vs. "remaining"). This section must
always reflect the actual current state of the work.

- [x] M0: Verify prerequisites — `cabal build` and `cabal test all` are green on master (107 examples, 0 failures, GHC 9.12.3, cabal 3.16.1.0). Done 2026-05-02.
- [x] M1: Survey the three escape hatches against the current Keiki.Core/Keiki.Symbolic/Keiki.Composition surface. Design note written at `docs/research/v1-escape-hatch-retirements-design.md` (single combined note — see Decision Log). Done 2026-05-02.
- [x] M2: Decide decomposition. **Three EPs**: EP-16 (OFn), EP-17 (PMatchC), EP-18 (unsafeCombine static check). See Decision Log entry dated 2026-05-02. Done 2026-05-02.
- [x] M3: Applied MasterPlan revision — MP-6's Exec-Plan Registry now lists EP-16, EP-17, EP-18; Dependency Graph redrawn to show post-fan-out shape; IP-1 through IP-5 rewritten to name the per-retirement EPs and assign owners; Progress section gained per-EP checklists; revision note appended at the bottom of MP-6. Per-retirement child ExecPlans created via `bun .claude/skills/exec-plan/init-plan.ts`: `docs/plans/16-retire-ofn-and-mkout-from-keiki-core.md`, `docs/plans/17-retire-pmatchc-and-matchcmd-from-keiki-core.md`, `docs/plans/18-static-disjoint-check-on-update-retire-unsafecombine.md`. Each populated per `agents/skills/exec-plan/PLANS.md` (self-contained, novice-readable, with milestone-based Plan of Work, Concrete Steps, Validation, Idempotence, Interfaces). Done 2026-05-02.
- [x] M4: Verdict — `cabal build && cabal test all` confirmed green (107/107) post-revision; no source drift. Outcomes & Retrospective entry written below. EP-15 marked Complete in MP-6's Exec-Plan Registry. Done 2026-05-02.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights
discovered during implementation. Provide concise evidence.

- **OFn and PMatchC are dead in user code.** MP-6's Vision & Scope
  assumed both were "currently used" by example aggregates. The M1
  survey shows zero occurrences in `src/Keiki/Examples/*`:

      $ grep -rn "OFn\|mkOut\|PMatchC\|matchCmd" src/Keiki/Examples/
      src/Keiki/Examples/UserRegistrationV0.hs:89:-- | Per-constructor guards. Migrated from v1 'matchCmd' to v2

  The only match is a *historical* comment about the V0 aggregate's
  prior migration. PInCtor / matchInCtor (added in EP-2 of MP-2) had
  already absorbed every aggregate use of `matchCmd`; no aggregate ever
  needed `mkOut`. Consequence: the OFn and PMatchC retirements are
  mechanical (drop the constructors and helpers; rewrite test
  fixtures); no structural successor surface needs to be designed for
  either. This makes EP-16 and EP-17 small enough to land in a single
  PR each. The substantive engineering of MP-6 lives entirely in
  EP-18 (`unsafeCombine` static check). 2026-05-02.

- **Toolchain baseline.** GHC 9.12.3, cabal-install 3.16.1.0, all 107
  test examples passing on master at the start of this design pass.
  No drift from MP-3 / MP-4 baselines. 2026-05-02.


## Decision Log

Record every decision made while working on the plan.

- Decision: This plan is a design-only milestone (no source changes
  to library code). Implementation lives in per-retirement EPs added
  to MP-6 by this plan's M3 revision step.
  Rationale: The encoding question for the `unsafeCombine` static
  check (likely a type-level set of written slots) and the question
  of whether `OFn` and `PMatchC` share design machinery both warrant
  a single design pass before fan-out. Mirrors MP-4's EP-11 pattern,
  except that MP-4's design milestone could fold into a single
  combinator impl (`compose` only); MP-6's three retirements are more
  likely to need genuine fan-out.
  Date: 2026-05-02

- Decision (M1 sub-decision): Single combined design note
  (`docs/research/v1-escape-hatch-retirements-design.md`) rather than
  three per-retirement notes.
  Rationale: The three retirements share the thematic question "what
  does the structural successor look like?" and a combined note keeps
  the cross-references local. The note is sectioned by retirement so
  per-retirement EPs can amend their own subsection without touching
  others'.
  Date: 2026-05-02

- Decision (M2): **Three EPs** — EP-16 (OFn), EP-17 (PMatchC), EP-18
  (unsafeCombine static check).
  Rationale: OFn and PMatchC retirements are mechanical and small
  (zero aggregate uses; just drop constructors, helpers, evaluator
  clauses, and test fixtures). The unsafeCombine retirement is
  substantive (type-level slot-name set, `Disjoint` constraint,
  composition refactor). Bundling OFn + PMatchC into one EP would
  conflate two distinct validation gates (PMatchC touches
  `Keiki.Symbolic`'s SBV translation; OFn does not) without saving
  meaningful coordination. Bundling all three would gate two trivial
  retirements on the substantive one's encoding pass.
  Alternatives considered and rejected: two EPs (bundle OFn + PMatchC)
  — clarity loss outweighs marginal coordination gain; one EP — too
  large per EP-15's M2 criteria.
  Date: 2026-05-02

- Decision: Successor surfaces — **no structural successor for OFn or
  PMatchC**; remove outright. **Type-level slot-name set encoding**
  for unsafeCombine.
  Rationale: M1's survey found OFn and PMatchC have zero aggregate
  use; speculatively keeping a renamed escape hatch for OFn (per
  MP-6's Vision & Scope option B) is dead weight. The PInCtor / PEq /
  PAnd / POr / PNot algebra is sufficient for every aggregate guard;
  no richer pattern AST is needed. For unsafeCombine, the
  slot-name-indexed `Update (rs :: [Slot]) (w :: [Symbol]) (ci :: Type)`
  with a closed `Disjoint` type family on `[Symbol]` is the cleanest
  encoding and maps mechanically to `compose`'s use site (a
  `Disjoint (Names rs1) (Names rs2)` constraint on `compose` discharges
  the per-call-site obligation at line 416).
  Date: 2026-05-02


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or
at completion. Compare the result against the original purpose.

### Outcome (2026-05-02)

The design milestone produced what the Purpose / Big Picture asked
for: a recommendation that decomposes MP-6 into per-retirement
implementation plans and a written rationale at
`docs/research/v1-escape-hatch-retirements-design.md`.

The four questions set out in Purpose / Big Picture were settled:

1. **Successor surfaces.** *No successor* for `OFn` or `PMatchC`
   (zero aggregate uses; the structural-successor obligations
   assumed by MP-6's Vision & Scope dissolved on contact with the
   actual call-site survey). For `unsafeCombine`: a slot-name-set
   index `(w :: [Symbol])` on `Update`, with a closed `Disjoint`
   type family producing readable type errors on overlap.
2. **Decomposition.** Three EPs — EP-16, EP-17, EP-18 — created.
3. **Migration story.** EP-16 and EP-17 touch only Core, Symbolic
   (PMatchC only), Composition (constructor-narrowing cleanup), and
   `test/Keiki/CoreSpec.hs`. Aggregates are unaffected. EP-18
   migrates aggregates and the composition use site at line 416 to
   the static `combine`.
4. **MasterPlan revision.** Applied: registry, dependency graph,
   integration points, progress section, surprises, and a revision
   note at the bottom of MP-6.

Acceptance gates (from Validation and Acceptance):

- The design note exists at
  `docs/research/v1-escape-hatch-retirements-design.md` and answers
  all four questions. ✓
- MP-6's Exec-Plan Registry names the implementation EPs by path. ✓
- MP-6 has a revision note appended describing the decomposition. ✓
- `cabal build && cabal test all` is still green. ✓ (107 examples,
  0 failures)

### Lessons / surprises

- **Always survey before designing.** MP-6's Vision & Scope was
  written based on memory of MP-2's deferral list, which was written
  before EP-2 of MP-2 added `PInCtor` / `matchInCtor`. The actual
  state of master had two of the three retirements already
  effectively done at the call-site level, with only the
  constructor-and-helper exhaust remaining. The design milestone
  exists in part to perform exactly this kind of "test the assumed
  premise against reality" pass; doing so saved EP-16 and EP-17
  from over-engineering speculative successor surfaces.
- **Three EPs vs. bundling.** The temptation to bundle OFn + PMatchC
  was real (both are mechanical deletions). The clarity of one EP
  per concern won; PMatchC's PR will touch `Keiki.Symbolic` and the
  SBV design note, which OFn's PR has no business touching.
- **The substantive work is all in EP-18.** The slot-name set
  encoding, the auxiliary `WrittenSubset` lemma, the `compose`
  constraint addition — these are real type-level engineering. EP-18
  is the load-bearing milestone of MP-6.

### Gaps / what remains

- Per-retirement implementation (EP-16, EP-17, EP-18) is the
  remaining work in MP-6. The next contributor picks any of the
  three (no hard deps between them) and follows the EP's
  self-contained instructions.
- The `IP-5` block-removal sweep is assigned to whichever EP lands
  last; the conventional order EP-16 → EP-17 → EP-18 puts it on
  EP-18, but the assignment is mechanical and moves with the actual
  landing order.


## Context and Orientation

A reader picking up this plan needs:

- **The keiki pure core**, defined in `src/Keiki/Core.hs`. Two
  exported types matter most:
  - `OutTerm (rs :: [Slot]) (ci :: Type) (co :: Type)` — pure
    expressions yielding output values. Constructors: `OPack`
    (structural; carries `InCtor ci ifs`, `WireCtor co fields`, and
    `OutFields rs ci fields`) and `OFn` (the v1 escape hatch this
    plan retires).
  - `HsPred (rs :: [Slot]) (ci :: Type)` — the predicate AST.
    Constructors: `PTop`, `PBot`, `PAnd`, `POr`, `PNot`, `PEq`,
    `PInCtor` (structural constructor-equality, added in EP-2 of
    MP-2), and `PMatchC` (the v1 escape hatch this plan retires).
  - `Update (rs :: [Slot]) (ci :: Type)` — the copyless update
    language. Constructors: `UKeep`, `USet`, `UCombine`. Smart
    constructor `combine` returns `Either String` to reject
    overlapping targets at runtime; `unsafeCombine` skips the check
    and is the v1 escape hatch this plan retires.

- **The symbolic layer**, defined in `src/Keiki/Symbolic.hs`. The
  SBV-backed `BoolAlg SymPred` instance translates `HsPred` to SBV
  and decides `sat`/`isBot`/`isSingleValuedSym` symbolically. It
  cannot translate `PMatchC` (which is an opaque Haskell function);
  whether a successor surface for `PMatchC` requires a richer
  pattern AST or is fully covered by `PInCtor` is one of the design
  questions this plan settles.

- **The composition layer**, defined in `src/Keiki/Composition.hs`.
  Exports `compose` (sequential composition; built in EP-11 of
  MP-4). The composite edge's `update` field is built using
  `unsafeCombine` at line 416:

      , update = unsafeCombine
                   (weakenLUpdate @rs1 @rs2 (update e1))
                   (substUpdate   @rs1 @rs2 (update e2) o1)

  The two halves are disjoint by construction: `weakenLUpdate`
  weakens an `Update rs1 ci1` to `Update (rs1 ++ rs2) ci1`, writing
  only into the `rs1` prefix; `substUpdate` substitutes a mid-output
  into an `Update rs2 mid` and produces an `Update (rs1 ++ rs2) ci1`,
  writing only into the `rs2` suffix. Any chosen static encoding of
  "distinct targets" must let this composite type-check
  ergonomically.

- **The example aggregates**:
  - `src/Keiki/Examples/UserRegistration.hs` (V5) — the canonical
    smoke-test aggregate. Uses `mkOut` (`OFn`) for outputs whose
    shape doesn't fit `OPack`; uses `matchInCtor` (`PInCtor`)
    where possible and `matchCmd` (`PMatchC`) where not (post-MP-2
    EP-2 the helpers were migrated to `matchInCtor` for the
    common cases — verify the current state in M1's survey);
    chains `unsafeCombine` for multi-slot updates.
  - `src/Keiki/Examples/UserRegistrationV0.hs` — the unfixed-schema
    aggregate that demonstrates the hidden-input check firing.
  - `src/Keiki/Examples/EmailDelivery.hs` — added in EP-11 of MP-4
    as the second aggregate for the composition smoke test.

- **The reference design notes**:
  - `docs/research/dsl-shape-for-symbolic-register.md` — defines the
    DSL constructor sets. Lists `OFn`, `PMatchC`, `unsafeCombine`
    in its closing "v1 surfaces still pending retirement" block at
    lines 997-1006.
  - `docs/research/sbv-boolalg-design.md` — documents EP-2 of MP-2.
    Records how the SBV instance falls back on `PMatchC` ("unknown
    / give up"). Read this before deciding the `PMatchC` successor.
  - `docs/research/composition-combinators-design.md` — produced by
    EP-11 of MP-4. Documents the structural decisions behind
    `compose`. Read this before deciding the `unsafeCombine` static
    encoding (the composition use site is the load-bearing
    constraint).
  - `docs/research/keiki-generics-design.md` — produced by MP-3.
    Item G (compile-time topology safety) is explicitly out of
    scope here; read its statement so it's clear why it's deferred.

Terms of art used in this plan:

- **Escape hatch.** A constructor in the pure-core DSL that holds
  an opaque Haskell value (a function or a closure). Escape hatches
  evaluate correctly but defeat structural analyses (mechanical
  inversion, hidden-input check, symbolic SBV translation).

- **Static check.** Enforcement of an invariant at the type level
  rather than at runtime. The current `combine` smart constructor
  enforces "distinct targets" by walking the runtime structure and
  returning `Left`; a static check makes the corresponding
  ill-formed program fail to type-check.

- **Disjoint slot witness.** A constraint or evidence value that
  witnesses two type-level sets of register slots are disjoint. The
  likely encoding is a type family on `[Slot]` that produces a type
  error when slots overlap.


## Plan of Work

### M0 — Prerequisites

Verify `cabal build && cabal test all` is green on master before
starting. Record the GHC version and the SBV/z3 versions in the
Surprises & Discoveries section if they differ from the
2026-05-01/2026-05-02 baselines (GHC 9.12.3, SBV 14.0, z3 from
nix-shell).

This milestone produces no source-tree changes.

### M1 — Survey and design note(s)

For each of the three escape hatches:

- Count and list the current call sites in
  `src/Keiki/Examples/UserRegistration.hs`,
  `src/Keiki/Examples/UserRegistrationV0.hs`,
  `src/Keiki/Examples/EmailDelivery.hs`, and
  `src/Keiki/Composition.hs`. Use `grep` with the constructor name
  (`OFn`, `PMatchC`, `unsafeCombine`) and the helper name (`mkOut`,
  `matchCmd`).
- Sketch the structural successor surface. For `OFn`: can `OPack`
  cover every current use, or are there shapes (e.g.
  register-derived outputs not tied to a single input constructor)
  that need a new constructor? For `PMatchC`: does the existing
  `PInCtor` + `PEq` algebra subsume every guard, or is a richer
  pattern AST needed? For `unsafeCombine`: pick the type-level
  encoding (candidates: a type-level set of written slots indexed
  on `Update`, a phantom written-slot list, a class-based
  `Disjoint` witness) and verify it lets the composition use site
  type-check.
- Verify the `Keiki.Composition` constraint. Specifically: under
  the chosen encoding, can `weakenLUpdate (update e1) \`combine\`
  substUpdate (update e2) o1` type-check without `e1` and `e2`
  contributing per-call-site `Disjoint` evidence? The expected
  answer is yes (the disjointness should be mechanical from the
  weakening + substitution lemmas), but this milestone must
  confirm by sketching the relevant types.

Write a design note in `docs/research/`. The decision of whether
this is one combined note (e.g. `docs/research/v1-escape-hatch-retirements-design.md`)
or three separate notes (one per retirement) is an M1 sub-decision
recorded in the Decision Log. Default: one combined note, because
the three retirements share a thematic "what does the structural
successor look like" question and a combined note keeps the
cross-references local.

The note(s) must answer the four questions from "What this plan
must settle" in Purpose / Big Picture above.

### M2 — Decomposition decision

Decide whether the implementation work is one EP, two EPs, or three
EPs. Decision criteria:

- *Three EPs* (default). The retirements affect three different
  datatypes (`OutTerm`, `HsPred`, `Update`); each has its own
  validation gate. Mirrors MP-2's two-EP shape (one per concern).
- *Two EPs* (bundle `OFn` and `PMatchC`). Justified only if the
  M1 design note finds that they share design machinery (e.g. both
  end up needing the same Generics pass for structural conversion).
  No prior design work suggests this; M1's survey confirms or
  denies.
- *One EP* (everything in this plan, no fan-out). Justified only
  if M1 finds the implementation work is small enough to fit
  alongside the design note. Unlikely given that
  `unsafeCombine`'s static check involves type-level set
  manipulation.

Record the decision and rationale in the Decision Log.

### M3 — MasterPlan revision

Apply the M2 decision by editing
`docs/masterplans/6-retire-remaining-v1-escape-hatches-in-pure-core-ofn-pmatchc-unsafecombine-static-check.md`:

- Add per-retirement rows to the Exec-Plan Registry. Use placeholder
  paths until the per-retirement EPs are created in the next step.
- Update the Dependency Graph section to show the per-retirement
  EPs after EP-15.
- Update the Integration Points section if any new shared artifacts
  are identified by M1's survey.
- Append a revision note at the bottom of MP-6 describing the
  decomposition decision and the M1 design note's location.

Then create the per-retirement child ExecPlans:

    bun .claude/skills/exec-plan/init-plan.ts \
      --title "<title>" \
      --master-plan docs/masterplans/6-retire-remaining-v1-escape-hatches-in-pure-core-ofn-pmatchc-unsafecombine-static-check.md \
      --intention intention_01knjzws4qezz9w8b0743zfqv8

Read each file back, populate it per `agents/skills/exec-plan/PLANS.md`,
and update MP-6's registry with the real paths.

### M4 — Verdict

Write the Outcomes & Retrospective entry on this plan. Mark this
plan Complete in MP-6's registry. The next contributor picks up the
first per-retirement EP whose hard dependencies are satisfied.


## Concrete Steps

The exact commands for each milestone are:

M0 — prerequisites:

    cabal build
    cabal test all
    ghc --version

M1 — surveys (run from the repo root):

    grep -rn "OFn\|mkOut" src/ test/
    grep -rn "PMatchC\|matchCmd" src/ test/
    grep -rn "unsafeCombine" src/ test/

Read each call site in context. Tabulate the count and shape (which
edge in which aggregate, what `OFn`/`PMatchC`/`unsafeCombine` is
holding).

M3 — MasterPlan revision (after M2's decision is made):

    bun .claude/skills/exec-plan/init-plan.ts \
      --title "<retirement title>" \
      --master-plan docs/masterplans/6-retire-remaining-v1-escape-hatches-in-pure-core-ofn-pmatchc-unsafecombine-static-check.md \
      --intention intention_01knjzws4qezz9w8b0743zfqv8

Repeat per retirement (likely three times — once each for `OFn`,
`PMatchC`, `unsafeCombine`).


## Validation and Acceptance

Acceptance for the plan as a whole:

- The design note(s) exist in `docs/research/` and answer the four
  questions in Purpose / Big Picture.
- MP-6's Exec-Plan Registry names the implementation EPs by path.
- MP-6 has a revision note appended describing the decomposition.
- `cabal build && cabal test all` is still green (this plan does
  not change source code, so this is a regression check that
  nothing on master has drifted while the design pass was in
  flight).

This plan is design-only; there is no behavioural-change acceptance
to demonstrate.


## Idempotence and Recovery

All M0–M4 steps are idempotent. M1 produces a markdown file (or
files); rerunning M1 overwrites the file in place. M3's MasterPlan
edits are idempotent under markdown editing tools. M3's
`init-plan.ts` invocation refuses to overwrite existing files; if a
per-retirement EP file already exists, the M3 step proceeds with
the existing file rather than creating a new one.

If the M2 decomposition decision is later revised (e.g. an EP needs
to be split or merged), follow the MasterPlan revision protocol per
`agents/skills/master-plan/MASTERPLAN.md` and append a fresh
revision note to MP-6.


## Interfaces and Dependencies

This plan modifies:

- `docs/research/v1-escape-hatch-retirements-design.md` (or three
  per-retirement notes; M1 decides).
- `docs/masterplans/6-retire-remaining-v1-escape-hatches-in-pure-core-ofn-pmatchc-unsafecombine-static-check.md`
  (M3 revision).
- `docs/plans/<N>-...md` for each per-retirement EP (M3 creates).

This plan reads (does not modify):

- `src/Keiki/Core.hs`
- `src/Keiki/Symbolic.hs`
- `src/Keiki/Composition.hs`
- `src/Keiki/Examples/UserRegistration.hs`
- `src/Keiki/Examples/UserRegistrationV0.hs`
- `src/Keiki/Examples/EmailDelivery.hs`
- `docs/research/dsl-shape-for-symbolic-register.md`
- `docs/research/sbv-boolalg-design.md`
- `docs/research/composition-combinators-design.md`
- `docs/research/keiki-generics-design.md`

Soft external dependencies (recorded on MP-6's Dependency Graph):

- EP-7 (`docs/plans/7-upgrade-keiki-to-ghc-9-12.md`) — the GHC 9.12
  upgrade. The `unsafeCombine` static check will likely use
  type-level set machinery that benefits from boot-library bumps.
  Record the GHC version this plan ran under in M0's Surprises &
  Discoveries entry.
- MP-4's children (`docs/masterplans/4-composition-combinators-on-symtransducer.md`)
  — the composition layer's use of `unsafeCombine` is the
  load-bearing constraint on the static encoding. If MP-4
  introduces further combinators after EP-11 that use
  `unsafeCombine` internally, M1's survey must include them.
