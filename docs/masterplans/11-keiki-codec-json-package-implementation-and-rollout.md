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
snapshot persistence — without breaking keiki's deliberate "no built-in codec" stance.
The keiki-side architectural anchor for that stance is
`docs/research/effects-boundary.md` lines 72–73, which lists "Serialization. JSON /
CBOR / Protobuf to and from on-the-wire bytes" as a runtime-layer responsibility and
states "the pure layer talks only typed Haskell values." The same stance is recorded
downstream in `keiro/docs/research/02-keiki-decide-loop.md` §"Effectful Story" ("no
built-in JSON or binary"), which is the survey passage the consumer (keiro) reads
when reasoning about what keiki does and does not ship. The package executes on the
policy already documented in `docs/research/schema-evolution.md` lines 19–22:
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
- A cross-GHC golden hash test infrastructure is in place and *structurally* gates
  every release; it becomes *operationally* meaningful only once keiki's
  `tested-with` field expands beyond the current single row (`GHC == 9.12.*`). A
  one-row matrix has nothing to compare against and so cannot detect drift.
  Expanding the matrix (a second supported GHC) is therefore a Phase B
  prerequisite for the gate to do real work; see Dependency Graph below.
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
  (`docs/research/symbolic-analysis-and-runtime-implications.md`) and the keiro
  2026-05-09 cost-benefit audit
  (`keiro/docs/masterplans/1-keiro-research-foundation.md` Surprises & Discoveries),
  the symbolic layer and the codec layer are independent — z3 sees
  `Sym a`/`SymRep a`, the codec sees `ToJSON a`/`FromJSON a`. Out of scope here.


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

3. **TH derivation ergonomics (EP-38, to be authored).** Add a new module
   `Keiki.Codec.JSON.TH` **inside `keiki-codec-json`** exposing
   `deriveRegFileToJSON :: TH.Name -> TH.Q [TH.Dec]` (and similar) so users can
   derive `RegFileToJSON` instances on record types automatically, parallel to the
   existing `mkInCtor`-style helpers in `keiki`'s `Keiki.Generics.TH`. **The splice
   must not live in `keiki`'s `Keiki.Generics.TH`** because `RegFileToJSON` is
   defined in `keiki-codec-json` (which imports `aeson`), and pulling the splice
   into `keiki` would transitively force an `aeson` dependency on `keiki` core —
   violating EP-36 §3 R8. EP-36 §3 R6 commits to composing with `Keiki.Generics`;
   EP-38 operationalises that composition from the codec-package side by reusing
   `RegFieldsOf`, `GRecord`, and `KnownSlotNames` (all in `keiki`) to do the
   structural walk while keeping the JSON-specific splice next to the JSON class.

4. **Property-test toolkit (EP-39, to be authored).** A reusable test-utilities
   module (or a lightweight `keiki-codec-json-test` package) that consumers import to
   verify their slot-type codec behaviour automatically. The lede deliverable is a
   **"did this slot's `ToJSON` change" detector** — a per-slot-type golden-byte test
   that catches EP-36 §4 case #10, the schema-evolution case the shape hash cannot
   detect by design (because the hash is over the *type*, not the *encoding*).
   Secondary deliverables library-ize the in-tree EP-36 M3 property suite (Value
   roundtrip, Encoding roundtrip, determinism, structural sensitivity over §4 cases
   #1–9) so consumers run the same disciplines against their own slot lists rather
   than re-authoring them. The case-#10 detector is the genuinely new test surface;
   the rest is exposing existing primitives behind a stable consumer-facing API.

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
| 2 | Coordinated Hackage release of keiki and keiki-codec-json | docs/plans/37-...  *(to be authored when Phase B begins)* | EP-1 | None | Not Started |
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
  them in v0.2/v0.3 minor bumps. EP-37 also owns the coordinated `keiki` release
  per the Integration Points "version coordination" entry.
- **EP-38 TH ergonomics** can run independently of EP-37 and EP-39. If EP-37 ships
  v0.1 first, EP-38 lands in v0.2.
- **EP-39 property-test toolkit** can run independently. Same release-bump pattern.

A fourth orthogonal Phase B concern: **expand `keiki.cabal`'s `tested-with`
matrix.** EP-36 M5 builds the cross-GHC golden-hash CI infrastructure, but the
current `tested-with` field carries one row (`GHC == 9.12.*`), so the gate has
nothing to compare against. To make the gate operationally meaningful — i.e., to
actually detect drift across GHC versions — at least one additional GHC must
enter `tested-with`. This work is small enough that it does not warrant its own
ExecPlan, but it is a real Phase B prerequisite for the release-gate language in
Vision & Scope to be honest. Track it on EP-37 (release-readiness) or as a
standalone follow-up; either way, EP-37 cannot truthfully claim "release-blocking
cross-GHC gate" until the matrix has at least two entries.

The implication: Phase B is fully parallelisable across the three plans. The
maintainer can pick whichever earns its keep first based on consumer feedback.

The MasterPlan closes when all four plans are Complete and `keiki-codec-json`
v0.1 (plus the coordinated `keiki` release per Integration Points) is on Hackage.
Downstream consumer adoption — specifically, the keiro-side integration at
`keiro/docs/plans/9-integrate-keiki-codec-json-into-keiro-snapshot-path.md` — is
tracked as out-of-tree validation but is **not** a closure gate for MP-11. A
keiki maintainer cannot close a keiki-side MasterPlan on the strength of work
in another repository they do not own; the integration plan exists to surface
problems back to keiki via Surprises & Discoveries if they appear, which is the
right loop. The standard for MP-11 close is: artifacts shipped, gates green,
docs adoptable by a first-time consumer.


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
versioning, hackage metadata, and the changelog. EP-38 adds the
`template-haskell` dep to `keiki-codec-json`'s library stanza (not to `keiki`)
because the `deriveRegFileToJSON` splice ships there. EP-39 may add
`tasty-quickcheck` to the test stanza or split a sibling test-utility package.

**`Keiki.Codec.JSON.TH` module in `keiki-codec-json`.** New module introduced by
EP-38. Hosts the `deriveRegFileToJSON` family of TH splices. **Lives in
`keiki-codec-json`, not in `keiki`'s `Keiki.Generics.TH`**, to preserve EP-36 §3
R8 (`keiki` MUST NOT gain an `aeson` dependency). The splice reuses keiki's
existing structural primitives (`RegFieldsOf`, `GRecord`, `KnownSlotNames` from
`Keiki.Generics`) to walk the slot list. EP-38 must not modify
`Keiki.Generics.TH`'s existing `mkInCtor`-style API; new code is purely additive
in the new module.

**`keiki` and `keiki-codec-json` version coordination.** EP-36 adds a new
public module (`Keiki.Shape`) to the existing `keiki` package. `keiki-codec-json`
depends on that module. EP-37 owns the joint-release decision:

- If `keiki 0.1.0.0` is *already* on Hackage, EP-37 must coordinate a `keiki`
  minor bump (0.2.0.0) and a simultaneous push of both packages, with
  `keiki-codec-json`'s `build-depends` pinned `keiki ^>= 0.2`.
- If `keiki` is *not yet* on Hackage at the time EP-37 runs, EP-37 is `keiki`'s
  first Hackage push too, and the lower bound is `keiki ^>= 0.1`.

The current `keiki.cabal` declares `version: 0.1.0.0`; EP-37 must verify
Hackage presence as its first action and pick the correct path. **EP-37 is
responsible for the release of `keiki` itself as well as `keiki-codec-json`**,
even though the MasterPlan's nominal subject is the codec package — the two
cannot ship independently in the first cycle.

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

- [x] EP-36 M0: Cabal-project scaffolding (2026-05-13) — `cabal.project` declares
      `keiki-codec-json` alongside `.` and `jitsurei`; sibling package directory
      `keiki-codec-json/` holds an empty `Keiki.Codec.JSON` module and a passing
      scaffold test. `cabal build all` green.
- [x] EP-36 M1: `Keiki.Shape` module shipped (2026-05-13) with `CanonicalTypeName`
      (default + pre-declared base/text/time instances), `KnownRegFileShape`,
      `regFileShapeCanonical`, `regFileShapeHash`, `renderStableTypeRep`, `sha256Hex`.
      `cryptohash-sha256 ^>= 0.11` and `bytestring ^>= 0.12` added to keiki's deps.
      `Keiki.ShapeSpec` (11 golden assertions) green; 186/186 keiki tests pass.
- [x] EP-36 M2: `Keiki.Codec.JSON` ships (2026-05-13) the `RegFileToJSON` class
      with three methods (`regFileToJSON`, `regFileToEncoding`,
      `regFileFromJSON`); 16/16 unit tests pass; cross-path-byte-equality
      assumption relaxed to within-path determinism + cross-path semantic
      round-trip (aeson 2.2's `Aeson.Value`/`KeyMap` emits sorted-order, the
      Encoding path emits slot-list order — both round-trip correctly).
- [x] EP-36 M3: Property tests shipped (2026-05-13). 4 QC properties (100
      samples each, Value+Encoding roundtrip and within-path determinism),
      9 sensitivity assertions (§4 cases #1–9), and a pinned golden hash for
      the GHC-9.12.* exemplar. 30/30 tests pass.
- [x] EP-36 M4: Performance baselines via `tasty-bench` shipped (2026-05-13).
      Four fixtures × four measurements; baseline CSV checked in at
      `keiki-codec-json/bench/baseline.csv`. Encoding path is ~1.5× faster
      than Value path on the streaming-motivating BenchB fixture (5,000-entry
      list, 890 μs vs 1.30 ms, with 33 % less allocation).
- [ ] EP-36 M5: Cross-GHC CI gate (P7.2, release-blocking).
- [ ] EP-36 M6: Documentation — haddock with P11 guidance, design note, README
      updates.
- [ ] EP-37 (placeholder until plan is authored): Hackage release of v0.1.
- [ ] EP-38 (placeholder until plan is authored): TH derivation helpers shipped.
- [ ] EP-39 (placeholder until plan is authored): Property-test toolkit shipped.


## Surprises & Discoveries

Document cross-plan insights, dependency changes, scope adjustments, or unexpected
interactions between child plans. Provide concise evidence.

- 2026-05-13 — Deep validation pass against EP-36 and the keiki / keiro source
  trees surfaced six issues, all corrected in the same revision: (1) the cited
  codec-free-stance file `docs/research/02-keiki-decide-loop.md` lives in keiro,
  not keiki; the keiki-side anchor is `docs/research/effects-boundary.md`
  lines 72–73. (2) The EP-38 TH splice cannot live in keiki's
  `Keiki.Generics.TH` without violating EP-36 R8; it must ship in a new
  `Keiki.Codec.JSON.TH` inside `keiki-codec-json`. (3) EP-37 must own a
  *coordinated* release of `keiki` and `keiki-codec-json` because `Keiki.Shape`
  is added to `keiki` by EP-36. (4) EP-39's scope was largely redundant with
  EP-36 M3; only the §4 case-#10 `ToJSON`-change detector is genuinely additive.
  (5) The cross-GHC gate is structurally ready at M5 but operationally vacuous
  with a one-row `tested-with`; expanding the matrix is a Phase B prerequisite.
  (6) MP-11 closure cannot depend on the keiro-side integration plan
  completing. Each issue is now reflected in Vision & Scope, Decomposition
  Strategy, Integration Points, Dependency Graph, and the Decision Log;
  EP-36's M6 acceptance and citations are cascaded in the same pass.
  Evidence: `keiro/docs/research/02-keiki-decide-loop.md` line 99 contains the
  §"Effectful Story" heading; `keiki/docs/research/02-keiki-decide-loop.md`
  does not exist (`find` returns empty). `keiki/keiki.cabal` line 11 shows
  `tested-with: GHC == 9.12.*` as a single-row matrix.


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
  Rationale: Honours the codec-free commitment structurally, not just by
  convention. The keiki-side architectural anchor is
  `docs/research/effects-boundary.md` lines 72–73 ("Serialization. JSON / CBOR /
  Protobuf … the pure layer talks only typed Haskell values"); the consumer-side
  reiteration of the same stance lives in
  `keiro/docs/research/02-keiki-decide-loop.md` §"Effectful Story". Sets the
  multi-package precedent for keiki cleanly. EP-36 §3 R8 records this as a hard
  requirement.
  Date: 2026-05-10 (originally settled in EP-36 of 2026-05-09; restated here as the
  MasterPlan-level commitment).

- Decision: Re-anchor the "no built-in JSON or binary" citation from
  `docs/research/02-keiki-decide-loop.md` (which does not exist in the keiki
  repository) to `docs/research/effects-boundary.md` lines 72–73 (which does, and
  is the keiki-side authoritative passage). Retain the keiro-side citation as
  consumer-side reinforcement.
  Rationale: Validation pass 2026-05-13 confirmed `02-keiki-decide-loop.md` lives
  in `keiro/docs/research/`, not in `keiki/docs/research/`. MP-11 and EP-36 both
  carried the broken path. The keiki-side anchor was always
  `effects-boundary.md`; the citation just needed to point at the right file. The
  cascade to EP-36 also rewrites M6's "update `02-keiki-decide-loop.md` §'Effectful
  Story'" acceptance criterion to a `keiki`-internal action that the keiki
  maintainer can actually take (update `effects-boundary.md` and the README;
  notify keiro of the published artifact so the keiro-side survey can be updated
  by its maintainer).
  Date: 2026-05-13.

- Decision: The `deriveRegFileToJSON` TH splice (EP-38) lives in a new module
  `Keiki.Codec.JSON.TH` inside `keiki-codec-json`, **not** in `keiki`'s existing
  `Keiki.Generics.TH`.
  Rationale: `RegFileToJSON` is defined in `keiki-codec-json` (which depends on
  `aeson`). A TH splice that generates instances of that class must be in the
  package that knows about it. Putting the splice in `keiki`'s `Keiki.Generics.TH`
  would transitively force `aeson` onto `keiki`, violating EP-36 §3 R8 (the
  load-bearing "keiki MUST NOT gain `aeson`" requirement). The new module reuses
  `RegFieldsOf`, `GRecord`, and `KnownSlotNames` from `keiki`'s `Keiki.Generics`
  for the structural walk, so the composition with existing machinery (R6) is
  preserved without breaking R8.
  Date: 2026-05-13.

- Decision: EP-37 owns a *coordinated* release of both `keiki` and
  `keiki-codec-json`, not just the codec package.
  Rationale: EP-36 adds a new public module (`Keiki.Shape`) to `keiki`.
  `keiki-codec-json` depends on `Keiki.Shape`. The two packages therefore cannot
  ship independently in the first cycle: whichever path EP-37 takes (first-ever
  Hackage push for `keiki`, or coordinated minor bump if `keiki 0.1.0.0` is
  already published), both packages must hit Hackage with compatible
  `build-depends` bounds. The MasterPlan previously framed EP-37 as
  "publish keiki-codec-json v0.1"; the validation pass surfaced that this framing
  underspecified the work. The Integration Points section now carries the
  coordination contract explicitly.
  Date: 2026-05-13.

- Decision: Sharpen EP-39's scope so the EP-36 §4 case-#10 "did this slot's
  `ToJSON` change" detector is the lede deliverable; round-trip / sensitivity
  pieces are framed as library-ized exposure of EP-36's in-tree fixtures, not new
  test surface.
  Rationale: EP-36 M3 already ships round-trip on both Value and Encoding paths,
  determinism (R9), and sensitivity over §4 cases #1–9 (P7.4) as in-tree property
  tests. The earlier EP-39 description duplicated that work. Case #10 — a
  consumer's slot type's `ToJSON` *instance* silently changing under them — is
  uniquely outside what the shape hash and the in-tree sensitivity suite can
  catch (by design: the hash is over the *type*, not the *encoding*). Making
  case #10 the lede ensures EP-39 carries its own weight and is not authored as
  a thin re-export of EP-36 outputs.
  Date: 2026-05-13.

- Decision: The cross-GHC golden-hash gate is "structurally complete" at EP-36
  M5 but "operationally meaningful" only once `keiki.cabal`'s `tested-with`
  matrix has at least two GHC entries. Expanding `tested-with` is a Phase B
  prerequisite tracked on EP-37 (release-readiness).
  Rationale: `keiki.cabal` currently has `tested-with: GHC == 9.12.*` — one row.
  A cross-version test against a one-row matrix has nothing to compare against
  and cannot detect drift. The release-blocking-gate language in Vision & Scope
  is honest only when a second GHC is in the matrix. This is a small task (add
  9.10 or 9.14 to `tested-with`, run CI), so does not warrant its own ExecPlan,
  but it must not be silently skipped. EP-37 cannot truthfully claim
  "release-blocking cross-GHC gate" until the matrix has at least two entries.
  Date: 2026-05-13.

- Decision: MP-11 closure does not depend on the keiro-side integration plan
  (`keiro/docs/plans/9-integrate-keiki-codec-json-into-keiro-snapshot-path.md`)
  completing. That plan is tracked as out-of-tree validation, not a closure
  gate.
  Rationale: A keiki-side MasterPlan cannot honestly close on the strength of
  work in a sibling repository the keiki maintainer does not own. The earlier
  framing made MP-11 closure conditional on keiro EP-9 finishing, which was
  operationally ambiguous. The right loop is: keiro EP-9 surfaces problems back
  to keiki via this MasterPlan's Surprises & Discoveries section if integration
  reveals issues. MP-11's closure standard is: artifacts shipped, gates green,
  docs adoptable by a first-time consumer (which keiro EP-9 will *verify* but
  cannot *block*).
  Date: 2026-05-13.


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
- Codec-free architectural anchor (keiki-side):
  `docs/research/effects-boundary.md` lines 72–73 ("Serialization. JSON / CBOR /
  Protobuf to and from on-the-wire bytes. The pure layer talks only typed
  Haskell values.").
- Codec-free survey passage (consumer-side, in keiro):
  `keiro/docs/research/02-keiki-decide-loop.md` §"Effectful Story" ("no built-in
  JSON or binary"). Lives downstream in keiro because the keiro research
  foundation included a per-upstream-package survey; the keiki-side equivalent
  rationale lives in `effects-boundary.md`.
- The 2026-05-09 cost-benefit audit on the keiro `SymTransducer`-vs-`Decider`
  contract decision (which confirmed EP-36 is contract-orthogonal and proceeds
  regardless): `keiro/docs/masterplans/1-keiro-research-foundation.md` Surprises &
  Discoveries entry of 2026-05-09.


## Revisions

- 2026-05-13 — Deep validation pass against EP-36, the keiki source tree
  (`keiki.cabal`, `src/Keiki/`, `docs/research/`), and the referenced keiro
  plans. Six issues surfaced and were corrected in one revision: the broken
  `02-keiki-decide-loop.md` citation (re-anchored to
  `effects-boundary.md`); EP-38's TH splice location (moved from
  `Keiki.Generics.TH` in `keiki` to a new `Keiki.Codec.JSON.TH` in
  `keiki-codec-json` to preserve EP-36 R8); EP-37's release scope (now owns a
  coordinated release of both `keiki` and `keiki-codec-json`); EP-39's scope
  (the §4 case-#10 `ToJSON`-change detector is now the lede); the cross-GHC
  matrix reality (gate is structurally complete at M5 but operationally
  meaningful only after `tested-with` grows beyond one row); MP-11 closure
  (no longer conditional on the keiro-side EP-9 integration plan, which is
  tracked but does not gate closure). Vision & Scope, Decomposition Strategy,
  Integration Points, Dependency Graph, Decision Log, References, and
  Surprises & Discoveries were all updated in this pass. EP-36 cascade
  applied separately to its citations and M6 acceptance criterion.
  Reason: the previous text carried a broken cross-repo reference and three
  underspecified Phase B integration contracts that would have surfaced as
  blockers when Phase B authoring began.
