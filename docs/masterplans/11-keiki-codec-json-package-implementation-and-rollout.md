---
id: 11
slug: keiki-codec-json-package-implementation-and-rollout
title: "keiki-codec-json package — implementation and rollout"
kind: master-plan
created_at: 2026-05-10T15:01:30Z
intention: "intention_01kr96br7gec191n9gqbmhvt42"
---

# keiki-codec-json package — implementation and rollout

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Vision & Scope

`keiki-codec-json` is a new sibling cabal package of `keiki`, introduced to provide
JSON serialization for `RegFile rs` and a stable, GHC-upgrade-safe shape hash for
snapshot persistence — without breaking keiki's deliberate "no built-in codec" stance
(`docs/research/02-keiki-decide-loop.md` §"Effectful Story"). The package executes on
the policy already documented in `docs/research/schema-evolution.md` lines 19–22:
*"Snapshots carry a register-file shape hash; mismatched hashes invalidate the snapshot
and force a replay from the start."*

After this MasterPlan is complete, the package is **production-ready and downstream-
adoptable**:

- Implementation lands in the keiki repository as a sibling cabal package
  `keiki-codec-json/`. The existing `keiki` package never gains a dependency on
  `aeson`; the codec ships in the new package, and the shape hash (which has only
  `Typeable` + SHA-256 deps) ships in `keiki` itself in a new module `Keiki.Shape`.
- Performance baselines exist for representative `RegFile` sizes (cf. EP-36 §10
  reference cases), tracked in CI without gating releases.
- A cross-GHC golden hash test gates every release, so a `cabal build` on a new GHC
  cannot silently invalidate snapshots in production.
- A Hackage release of v0.1 is published with a coherent versioning policy aligned to
  `keiki`'s release cycle, plus a changelog and README polished for first-time
  consumers.
- Ergonomic helpers — TH-based derivation of `RegFileToJSON` instances and a
  property-test toolkit consumers can import — reduce boilerplate for keiki users
  beyond the handwritten record path EP-36 ships.

In scope:

- The four work streams listed below (Decomposition Strategy).
- Coordination between the four — versioning, naming, module layout, doc cross-references.
- The package's relationship to `keiki` proper (no aeson in `keiki` core; the
  shape-hash split between `Keiki.Shape` and `Keiki.Codec.JSON`).

Out of scope:

- **CBOR or other codec formats.** A future sibling package `keiki-codec-cbor` (or
  similar) would land under its own MasterPlan when a real consumer asks. Reusing the
  shape hash from `Keiki.Shape` is straightforward.
- **Schema migration tooling.** Per `docs/research/schema-evolution.md`, schema
  evolution is an *application* concern. The codec ships current-shape encode/decode
  plus the discrimination primitives (the hash); migration is downstream.
- **Changes to `keiki` core's public API** beyond adding `Keiki.Shape`.
- **Symbolic-verification (z3) integration with the codec.** Per the keiki research
  surveys and the keiro 2026-05-09 cost-benefit audit, the symbolic layer and the
  codec layer are independent — z3 sees `Sym a`/`SymRep a`, the codec sees
  `ToJSON a`/`FromJSON a`. Out of scope here.


## Decomposition Strategy

Decomposition is by lifecycle phase plus separation of ergonomics from core. The four
child plans:

1. **Implementation (EP-36).** The core codec + shape hash, with full test discipline
   (correctness properties, sensitivity tests, cross-GHC golden, performance
   baselines), CI gates, and haddock. Already authored and committed before this
   MasterPlan; adopted as the foundation child plan.

2. **Hackage release (EP-37, to be authored).** Publish `keiki-codec-json` v0.1 to
   Hackage with a versioning policy, polished cabal metadata, changelog discipline, a
   first-time-consumer-friendly README, and a release-process runbook for the keiki
   maintainer. Distinct from EP-36's "ship the code in the repo" — this is "ship to
   the world".

3. **TH derivation ergonomics (EP-38, to be authored).** Extend
   `Keiki.Generics.TH` (already in keiki) with a `deriveRegFileToJSON :: TH.Name ->
   TH.Q [TH.Dec]` (and similar) so users can derive `RegFileToJSON` instances on
   record types automatically, parallel to the existing `mkInCtor`-style helpers.
   EP-36 §3 R6 commits to composing with `Keiki.Generics`; this plan operationalises
   that for users who'd rather not hand-roll instances.

4. **Property-test toolkit (EP-39, to be authored).** A reusable test-utilities
   module (or a lightweight `keiki-codec-json-test` package) that consumers import to
   verify their slot-type codec behaviour automatically — round-trip QuickCheck
   generators, sensitivity-test fixtures parametric over slot types, and a "did this
   slot's `ToJSON` change" detector that catches §4 case #10 (the one the shape hash
   cannot detect by design).

Alternatives considered:

- **All-in-one ExecPlan covering the whole package.** Rejected because the work
  streams have genuinely different acceptance shapes — implementation is "code +
  CI", Hackage release is "process + metadata", TH ergonomics is "user-facing API
  surface", test toolkit is "downstream consumer support". Bundling them produces a
  500-line plan that's harder to track than four focused ones.

- **Defer everything beyond EP-36 to "if a real user asks".** Rejected because EP-36
  alone leaves boilerplate visible (no TH derivation), no published artifact (no
  Hackage), and no consumer-side verification toolkit. Shipping EP-36 without these
  would force the first downstream consumer (keiro) to either accept the boilerplate
  or open new ExecPlans before they could integrate. Better to plan the rollout as a
  coherent unit now, even if the later streams are smaller plans.

- **Fold TH ergonomics into EP-36.** Considered; rejected because EP-36 is already at
  six milestones (M0–M6) with substantial test discipline, and TH macro authoring is
  a separate concern from the core class definitions. EP-36 carries the *requirement*
  that the API compose with `Keiki.Generics` (R6); EP-38 *implements* the composition.

The ordering (Phase A: EP-36; Phase B: EP-37, EP-38, EP-39 in parallel) is determined
by dependency: nothing is publishable, derivable, or testable until the package code
exists.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| 1 | RegFile JSON codec and shape hash for snapshot persistence | docs/plans/36-regfile-json-codec-and-shape-hash-for-snapshot-persistence.md | None | None | In Progress |
| 2 | Hackage release of keiki-codec-json v0.1 | docs/plans/37-...  *(to be authored when Phase B begins)* | EP-1 | None | Not Started |
| 3 | TH derivation helpers for RegFileToJSON | docs/plans/38-... *(to be authored when Phase B begins)* | EP-1 | None | Not Started |
| 4 | Property-test toolkit for downstream codec users | docs/plans/39-... *(to be authored when Phase B begins)* | EP-1 | None | Not Started |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their `EP-N` prefix (where `N` is
this MasterPlan's local row number, not keiki's global plan number). EP-1 in this
registry corresponds to plan #36 in keiki's overall numbering.

The Phase B plans (rows 2, 3, 4) will be authored via
`bun agents/skills/exec-plan/init-plan.ts --master-plan docs/masterplans/11-...` once
EP-36 reaches its M5 (cross-GHC CI gate) milestone. Their paths will be filled in
when they're created. Authoring stubs now would commit to a numbering and slug that
might shift if scope is refined; deferring lets Phase B start clean.


## Dependency Graph

The plan order is **Phase A then Phase B**, with Phase B's three plans running in
parallel.

EP-36 is the foundation. It produces the cabal package, the `RegFileToJSON` and
`KnownRegFileShape` classes, the cross-GHC CI gate, the performance baseline, and the
haddock surface. Until that lands, nothing else has anything to publish, derive, or
test against.

The three Phase B plans (EP-37 Hackage release, EP-38 TH ergonomics, EP-39
property-test toolkit) all hard-depend on EP-36 and on each other only soft-style:

- **EP-37 Hackage release** can run as soon as EP-36 ships. It does not need EP-38 or
  EP-39 to be complete; the v0.1 release can ship without TH or test toolkit and add
  them in v0.2/v0.3 minor bumps.
- **EP-38 TH ergonomics** can run independently of EP-37 and EP-39. If EP-37 ships
  v0.1 first, EP-38 lands in v0.2.
- **EP-39 property-test toolkit** can run independently. Same release-bump pattern.

The implication: Phase B is fully parallelisable across the three plans. The
maintainer can pick whichever earns its keep first based on consumer feedback.

The MasterPlan closes when all four plans are Complete, the package is on Hackage at
v0.1+, and at least one downstream consumer (keiro is the known one) has integrated
against the published version.


## Integration Points

Several artifacts span more than one child plan and must be defined once.

**`Keiki.Shape` module.** Defined by EP-36 in the existing `keiki` package. Exports
`class CanonicalTypeName a`, `class KnownRegFileShape (rs :: [Slot])`,
`regFileShapeHash :: Proxy rs -> Text`, `renderStableTypeRep :: SomeTypeRep -> Text`.
EP-37, EP-38, EP-39 all reference these as the stable hash surface. **No
modifications expected from Phase B.** If a Phase B plan needs a change here, it
escalates to a Decision Log entry on this MasterPlan first.

**`Keiki.Codec.JSON` module in `keiki-codec-json`.** Defined by EP-36. Exports
`class RegFileToJSON (rs :: [Slot])`, with `regFileToJSON`, `regFileFromJSON`,
`regFileToEncoding` methods (per EP-36 R1, R2, R10). EP-38 (TH) generates instances
of this class; EP-39 (test toolkit) provides QuickCheck round-trip properties over
it.

**Cabal package `keiki-codec-json.cabal`.** Defined by EP-36 (M0–M2). EP-37 owns
versioning, hackage metadata, and the changelog. EP-38 may add TH-related deps
(`template-haskell`); EP-39 may add `tasty-quickcheck` to the test stanza or split a
sibling test-utility package.

**`Keiki.Generics.TH` module in `keiki`.** Already exists; EP-38 extends it with a
`deriveRegFileToJSON` family of TH splices, parallel to the existing `mkInCtor`
helpers. EP-38 must not break existing `mkInCtor` behaviour.

**Cross-GHC golden hash test fixtures.** Defined by EP-36 (M5). EP-39's property
toolkit re-uses these fixtures so consumers run the same test discipline against
their own slot lists. The fixture format and slot-list shape are EP-36's; EP-39 only
imports.

**§10 reference RegFile-size cases (from EP-36).** EP-36 §10 documents four
representative `RegFile` size scenarios (multi-party signing, batch reconciliation,
ticket aggregate, auction). EP-37 references them in the README; EP-39 may use
condensed variants in its property-test fixtures. Defining new reference cases is
EP-36's prerogative.


## Progress

Track milestone-level progress across all child plans. Each entry names the child
plan and the milestone.

- [ ] EP-36 M0: Cabal-project scaffolding (`cabal.project`, sibling package directory,
      empty stubs).
- [ ] EP-36 M1: `Keiki.Shape` module with `CanonicalTypeName`, `KnownRegFileShape`,
      `regFileShapeHash`, `renderStableTypeRep`. SHA-256 dep added. Unit tests.
- [ ] EP-36 M2: `keiki-codec-json` package with `Keiki.Codec.JSON`. `RegFileToJSON`
      class with three methods (`regFileToJSON`, `regFileFromJSON`,
      `regFileToEncoding`). Unit roundtrip tests.
- [ ] EP-36 M3: Property tests (R5, R9, R10, P7.4) — both Value and Encoding paths,
      determinism, sensitivity.
- [ ] EP-36 M4: Performance baselines via `tasty-bench` against the §10 reference
      fixtures. Tracked, not gated.
- [ ] EP-36 M5: Cross-GHC CI gate (P7.2, release-blocking).
- [ ] EP-36 M6: Documentation — haddock with P11 guidance, design note, README
      updates.
- [ ] EP-37 (placeholder until plan is authored): Hackage release of v0.1.
- [ ] EP-38 (placeholder until plan is authored): TH derivation helpers shipped.
- [ ] EP-39 (placeholder until plan is authored): Property-test toolkit shipped.


## Surprises & Discoveries

Document cross-plan insights, dependency changes, scope adjustments, or unexpected
interactions between child plans. Provide concise evidence.

(None yet.)


## Decision Log

- Decision: Adopt EP-36 (`docs/plans/36-regfile-json-codec-and-shape-hash-for-snapshot-persistence.md`)
  as this MasterPlan's foundation child plan. EP-36 was authored 2026-05-09 as a
  stand-alone ExecPlan; updating its frontmatter now to point at this MasterPlan
  brings it into the registry without redrafting.
  Rationale: EP-36's content is decision-complete and matches Phase A scope exactly.
  Re-authoring under the MasterPlan would discard the committed history and the
  validation work it carries.
  Date: 2026-05-10.

- Decision: Decompose post-EP-36 work into three Phase B plans (Hackage release, TH
  ergonomics, property-test toolkit) rather than one or two larger plans.
  Rationale: The three streams have genuinely different acceptance shapes (process
  vs API surface vs consumer support). Bundling them would produce a less reviewable
  plan; splitting them lets each ship under its own minor-version bump.
  Date: 2026-05-10.

- Decision: Defer authoring the Phase B plan files (EP-37, EP-38, EP-39) until EP-36
  reaches M5 (cross-GHC CI gate).
  Rationale: Authoring stubs now commits to a numbering and slug that may shift if
  EP-36's outcomes (especially M3/M4 measurements) reshape the Phase B priorities.
  The Vision & Scope, Decomposition Strategy, and Integration Points sections of
  this MasterPlan carry enough detail that a future maintainer can author the Phase
  B plans cleanly when the time comes.
  Date: 2026-05-10.

- Decision: `keiki` itself remains aeson-free. The shape hash lands in `keiki`'s new
  `Keiki.Shape` module (Typeable + SHA-256 deps only); the JSON codec lands in the
  sibling `keiki-codec-json` package (aeson dep).
  Rationale: Honours the `02-keiki-decide-loop.md` §"Effectful Story" "no built-in
  JSON or binary" commitment structurally, not just by convention. Sets the
  multi-package precedent for keiki cleanly. EP-36 §3 R8 records this as a hard
  requirement.
  Date: 2026-05-10 (originally settled in EP-36 of 2026-05-09; restated here as the
  MasterPlan-level commitment).


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original vision.

(To be filled during and after implementation.)


## References

- Driving consumer (out of tree): keiro EP-4 snapshot strategy at
  `keiro/docs/research/09-snapshot-strategy.md` §3, §6.
- keiro upstream-roadmap entry that mandates this work: `keiro/docs/research/11-upstream-roadmap.md`
  §7.1 (`keiki: Register-file <-> Aeson.Value helper`) and §7.2 (`keiki: Register-file
  shape hash`).
- keiro integration ExecPlan that consumes this MasterPlan's outputs:
  `keiro/docs/plans/9-integrate-keiki-codec-json-into-keiro-snapshot-path.md`.
- Pre-existing keiki commitment to the policy this implements:
  `docs/research/schema-evolution.md` lines 19–22.
- Codec-free survey passage: `docs/research/02-keiki-decide-loop.md` §"Effectful
  Story" ("no built-in JSON or binary").
- The 2026-05-09 cost-benefit audit on the keiro `SymTransducer`-vs-`Decider`
  contract decision (which confirmed EP-36 is contract-orthogonal and proceeds
  regardless): `keiro/docs/masterplans/1-keiro-research-foundation.md` Surprises &
  Discoveries entry of 2026-05-09.
