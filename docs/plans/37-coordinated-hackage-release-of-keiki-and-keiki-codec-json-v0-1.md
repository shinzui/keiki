---
id: 37
slug: coordinated-hackage-release-of-keiki-and-keiki-codec-json-v0-1
title: "Coordinated Hackage release of keiki and keiki-codec-json v0.1"
kind: exec-plan
created_at: 2026-05-14T03:46:16Z
intention: "intention_01kr96br7gec191n9gqbmhvt42"
master_plan: "docs/masterplans/11-keiki-codec-json-package-implementation-and-rollout.md"
---


# Coordinated Hackage release of keiki and keiki-codec-json v0.1

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this plan completes, a fresh Haskell user with `cabal` on PATH and no
clone of this repository can run

    cabal install --lib keiki keiki-codec-json

and immediately use the public API documented on Hackage: the `RegFile` /
`Decider` / `SymTransducer` machinery in `keiki`, the GHC-upgrade-safe shape
hash in `keiki:Keiki.Shape`, and the JSON encoder / decoder / streaming
encoder in `keiki-codec-json:Keiki.Codec.JSON`. The same user can read the
package's Hackage page, follow the worked-example snippet on the README,
and persist + rehydrate a `RegFile` snapshot without referring back to
this repository's `docs/` tree.

The two packages must ship *together*. EP-36 (`docs/plans/36-regfile-json-codec-and-shape-hash-for-snapshot-persistence.md`)
added a new public module `Keiki.Shape` to the existing `keiki` package,
and `keiki-codec-json`'s `build-depends` line names `keiki` directly.
Releasing `keiki-codec-json` against an unreleased `keiki` would break
on `cabal install` because Hackage cannot resolve `keiki ^>= 0.1`. The
release is therefore one logical event: two `cabal upload` invocations
in close succession against a tested pair of `.tar.gz` source
distributions.

The cross-GHC golden-hash CI gate that EP-36 M5 set up
(`.github/workflows/ci.yml` job `test`) becomes operationally meaningful
only once the GHC matrix has at least two entries (today it has one,
`9.12.2`; see MP-11 Decision Log entry of 2026-05-13). Expanding the
matrix to a second supported GHC version is therefore a release-
readiness prerequisite carried by this plan rather than a follow-up.

Out of scope: pushing actual bytes to Hackage. The plan stops one
command short of `cabal upload --publish`. The final push requires the
maintainer's Hackage credentials and is a deliberate human gate; the
plan culminates in `cabal sdist`-ed tarballs and a runbook the
maintainer can follow when they are ready to publish.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] M1 — (2026-05-14) `cabal info keiki` against a refreshed Hackage
      index returns "no package named 'keiki'". **Path 1 applies:**
      this release is the first Hackage push for both packages. The
      `build-depends: keiki ^>= 0.1` lower bound in
      `keiki-codec-json` (and now also `keiki-codec-json-test`) is
      correct without a minor bump.
- [ ] M2 — **Held for maintainer.** `tested-with` matrix expansion to
      ≥ 2 GHC versions requires local installation of a second GHC
      (recommended `9.10.7`) so the golden hash assertion can be
      verified against EP-36's pinned value before the matrix change
      is committed. `ghcup` is not present in the session that
      prepared the v0.1 artifacts; the maintainer must run
      `ghcup install ghc 9.10.7`, then
      `GHCUP_GHC_VERSION=9.10.7 cabal test keiki-codec-json:keiki-codec-json-test
      --test-options="--match 'M3 golden hash'"`, and only commit the
      matrix change if the assertion passes. EP-36 §8 documents the
      failure path.
- [x] M3 — (2026-05-14) Cabal metadata polished:
      `description` (multi-line) and `extra-doc-files`
      (README, CHANGELOG, CONTRIBUTING where applicable) added to
      all three `.cabal` files. `source-repository head` deferred
      until the maintainer commits to a GitHub URL; the `keiki`
      package carries an informational `[no-repository]`
      warning from `cabal check`, which is the only remaining
      warning across all three packages.
      `cabal check` reports zero warnings on
      `keiki-codec-json` and `keiki-codec-json-test`.
- [x] M4 — (2026-05-14) `CHANGELOG.md` authored at the root of all
      three packages, each with a `[Unreleased]` placeholder plus a
      provisional `[0.1.0.0] — TBD` section listing the public
      surface, validation results, and out-of-scope items.
      `keiki/README.md` already exists from an earlier commit and is
      first-time-consumer friendly; `keiki-codec-json/README.md`
      gained a "Test toolkit for downstream consumers" cross-link
      section (added by EP-39 M5). No further README polish needed
      for v0.1.
- [x] M5 — (2026-05-14) `cabal check` on each package is clean
      modulo the `keiki [no-repository]` informational warning.
      `cabal sdist all` produces three release-candidate tarballs at
      `dist-newstyle/sdist/{keiki-0.1.0.0,keiki-codec-json-0.1.0.0,
      keiki-codec-json-test-0.1.0.0}.tar.gz`. Extracted in
      `/tmp/release-check/` with a stand-alone `cabal.project` that
      lists just the three extracted packages and pins
      `with-compiler: ghc-9.12.2`. `cabal build all` green;
      `cabal test all` green (186 + 40 + 7 = 233 examples, 0
      failures from the clean-room copy).
      An `extra-source-files: bench/baseline.csv` line was added to
      `keiki-codec-json.cabal` after the first sdist iteration
      revealed the CSV was missing from the tarball; the second
      sdist iteration includes it.
- [x] M6 — (2026-05-14) `docs/research/release-procedure.md`
      authored as the living maintainer runbook covering the
      coordinated three-package push (pre-publish checklist, upload
      sequence, failure recovery). `keiki-codec-json/CONTRIBUTING.md`
      gained a `## Releasing` section linking to it. The `cabal
      upload` and `cabal upload --publish` commands are documented
      but not executed; the maintainer is the final human gate.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Author this plan as a coordinated release of *both* `keiki` and
  `keiki-codec-json`, not just the codec package.
  Rationale: EP-36 added `Keiki.Shape` (Typeable + SHA-256-only, no aeson)
  to the existing `keiki` package, and `keiki-codec-json` depends on
  that module. Releasing the codec alone would publish a package that
  cannot resolve its `build-depends`. The MP-11 Integration Points
  section's "`keiki` and `keiki-codec-json` version coordination" entry
  carries this commitment.
  Date: 2026-05-14.

- Decision: Stop the plan one command short of `cabal upload --publish`.
  The maintainer holds Hackage credentials; the plan delivers the
  artifacts and the runbook, not the push.
  Rationale: The push is a once-per-release human gate, not an automation
  surface. The MP-11 scope question explicitly excluded
  autonomous Hackage publishing.
  Date: 2026-05-14.

- Decision: Hackage path 1 applies — `keiki` is not yet on Hackage.
  `cabal info keiki` against a refreshed index (2026-05-13T23:24:16Z)
  returned "no package named 'keiki'". The first release is a
  first-time push for all three packages; `keiki-codec-json`'s
  `build-depends: keiki ^>= 0.1` is correct as-is.
  Date: 2026-05-14.

- Decision: Scope-creep absorbed — this plan now ships *three*
  packages (`keiki`, `keiki-codec-json`, `keiki-codec-json-test`),
  not two as originally framed.
  Rationale: EP-39 (Property-test toolkit) lands its toolkit as a
  third sibling cabal package per the EP-39 Decision Log entry of
  2026-05-14. The MP-11 Surprises & Discoveries entry of 2026-05-14
  acknowledges the cascade. Operationally the `cabal sdist all` /
  `cabal upload` workflow already covers "every package"; the
  expansion adds one extra upload command per release, no
  structural change to the runbook.
  Date: 2026-05-14.

- Decision: M2 (cross-GHC matrix expansion) is intentionally held
  for the maintainer rather than executed in the artifact-prep
  session.
  Rationale: Adding a row to `tested-with` claims the package is
  validated against that GHC version. Without local installation of
  the second GHC and execution of the EP-36 §8 golden-hash test,
  the claim cannot be made honestly. `ghcup` was not available in
  the session that prepared the v0.1 artifacts. Silently committing
  a matrix expansion that would only first be exercised on CI
  would risk a release-blocking CI failure surfacing at the wrong
  time. The Progress section and `release-procedure.md`
  pre-publish checklist explicitly call this out.
  Date: 2026-05-14.

- Decision: Expand `tested-with` to two GHC versions (`9.12.*` plus one
  more — the maintainer chooses, but the plan recommends `9.10.*`) as
  part of release readiness, not as a follow-up.
  Rationale: MP-11's Dependency Graph and Decision Log of 2026-05-13
  observe that the cross-GHC golden-hash gate is "structurally complete
  but operationally vacuous" with one row in `tested-with`. The
  release-blocking-gate language in MP-11 Vision & Scope is honest only
  with ≥ 2 rows. The work is small; folding it into release readiness
  is the right scope.
  Date: 2026-05-14.


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

**2026-05-14 — Release artifacts prepared (M1, M3, M4, M5, M6).
M2 held for maintainer.** Five of six milestones landed; the
remaining M2 (GHC matrix expansion) requires a tool (`ghcup`) that
was not available in the session that prepared the artifacts, and
silently expanding `tested-with` without verifying the golden hash
on a second GHC would violate the EP-36 §8 contract.

Concrete deliverables:

* Three `.cabal` files carry `version: 0.1.0.0`, multi-line
  `description`, and `extra-doc-files` pointing at the relevant
  README / CHANGELOG / CONTRIBUTING files.
* Three `CHANGELOG.md` files at each package's root list the v0.1
  public surface against the in-tree validation results.
* `docs/research/release-procedure.md` is the maintainer's living
  runbook: pre-publish checklist (cross-GHC gate, `cabal check`,
  CHANGELOG entries, version coordination, clean-room rebuild),
  upload sequence (candidate inspection → publish), and failure
  recovery.
* `cabal sdist all` produces three release-candidate tarballs whose
  extracted, re-built copies pass 233 / 233 tests in a clean
  /tmp/ directory.

What's still required before the maintainer runs `cabal upload`:

1. **M2 cross-GHC matrix expansion.** Install a second GHC locally
   (`ghcup install ghc 9.10.7`), run the EP-36 §8 golden-hash test,
   commit the matrix expansion in `keiki.cabal`,
   `keiki-codec-json.cabal`, and `.github/workflows/ci.yml`, watch
   CI go green on both rows.
2. **`source-repository head` stanzas.** Once a GitHub URL is
   committed, add the standard stanza to all three `.cabal` files.
   This removes the `keiki [no-repository]` warning from
   `cabal check`.

Once those two items are green, the maintainer follows the upload
sequence in `docs/research/release-procedure.md`.

Surprises:

* `cabal sdist` does not include `extra-source-files: bench/baseline.csv`
  unless explicitly declared. The first iteration of M5 produced a
  tarball that was missing the bench baseline despite the CSV being
  committed in the working tree; declaring `extra-source-files:
  bench/baseline.csv` in `keiki-codec-json.cabal` fixed it. Worth
  remembering on future releases that add non-source data files.
* The `keiki [no-repository]` warning is the only `cabal check`
  finding once upper bounds and `extra-doc-files` are in place. It
  is informational and does not block publish; the warning will be
  removed when the maintainer adds the `source-repository head`
  stanza.


## Context and Orientation

This plan governs the first Hackage release of two packages. The repository
layout at the start of this plan is:

* `/Users/shinzui/Keikaku/bokuno/keiki/keiki.cabal` — the existing `keiki`
  package, declared `version: 0.1.0.0`, `tested-with: GHC == 9.12.*`. As of
  EP-36 it exposes a new public module `Keiki.Shape` alongside the existing
  `Keiki.Core`, `Keiki.Decider`, `Keiki.Symbolic`, `Keiki.Composition`,
  `Keiki.Builder`, etc.
* `/Users/shinzui/Keikaku/bokuno/keiki/keiki-codec-json/` — sibling cabal
  package introduced by EP-36 M0. Its `keiki-codec-json.cabal` declares
  `version: 0.1.0.0`, `tested-with: GHC == 9.12.*`, `build-depends: aeson
  ^>= 2.2, keiki, text ^>= 2.1, base ^>= 4.21`. Exposes one module
  `Keiki.Codec.JSON`.
* `cabal.project` — declares `packages: . jitsurei keiki-codec-json` and pins
  `with-compiler: ghc-9.12.2`. Only `.` (keiki) and `keiki-codec-json` are
  in scope for Hackage; `jitsurei` is a local example aggregate, not a
  published package.
* `.github/workflows/ci.yml` — three jobs from EP-36 M5: `test` (cross-GHC
  matrix, currently one row `9.12.2`), `test-perturbed-deps`
  (`--allow-newer text`), and an advisory `bench` on PRs.
* `keiki-codec-json/CONTRIBUTING.md` — the GHC-upgrade procedure (release
  gate § "GHC upgrade procedure (release-blocking)"). This plan extends it
  with the actual release runbook.

Terms of art the reader needs:

* "**Hackage**" — the central Haskell package repository at
  <https://hackage.haskell.org>. A `cabal upload` of a `package-X.Y.Z.tar.gz`
  creates a *candidate* by default; `cabal upload --publish` finalises it as
  a regular release. Candidates are mutable for inspection; published
  versions are immutable.
* "**shape hash**" — `Keiki.Shape.regFileShapeHash :: Proxy rs -> Text` from
  `src/Keiki/Shape.hs`. SHA-256 over a canonical, deterministic rendering
  of the slot list. Used by snapshot persisters to discriminate eligible
  snapshots.
* "**golden hash**" — the pinned value
  `a37b2b77042a635f394a082765f3410ea23a0b89745b0c77242b925a03aa172b` in
  `keiki-codec-json/test/Keiki/Codec/JSON/GoldenSpec.hs`. The hash of
  `regFileShapeHash (Proxy @ExemplarSlots)` against the three-slot
  baseline list `'[ '("retryCount", Int), '("cooldownUntil", UTCTime),
  '("correlationId", Text) ]`.
* "**release-blocking gate**" — the CI workflow's `test` job
  (`.github/workflows/ci.yml` lines 16–57) and `test-perturbed-deps` job
  (lines 64–81). A failure on any GHC in the matrix or under the
  perturbed-deps configuration blocks merge to `master` and therefore
  blocks the next release.

The MasterPlan that authors this plan is
`docs/masterplans/11-keiki-codec-json-package-implementation-and-rollout.md`.
Its Integration Points "version coordination" entry and its Dependency
Graph "fourth orthogonal Phase B concern" entry are the contractual
basis for this plan's M2 (matrix expansion) and the joint-release
discipline as a whole. The MP-11 Decision Log entry of 2026-05-13
("`keiki` itself remains aeson-free") is the structural invariant the
release must not break: nothing in this plan introduces an `aeson`
dep on `keiki`.

EP-36 (`docs/plans/36-regfile-json-codec-and-shape-hash-for-snapshot-persistence.md`)
is the foundation child plan. It owns the codec, the shape hash, the
cross-GHC CI workflow, the bench baseline, and the in-tree haddock /
README / CONTRIBUTING.md surfaces. This plan does not re-author any of
that; it consumes the artifacts EP-36 produced and ships them to
Hackage. The §8 "GHC upgrade procedure" in EP-36 is the operational
runbook for the gate; this plan's M2 is the first execution of that
procedure.


## Plan of Work

Six milestones, ordered so each is independently verifiable.

**M1 — Hackage presence check + version-coordination decision.**

Before authoring metadata or pushing tarballs, determine whether `keiki`
is *already* on Hackage. Two cases:

1. `keiki` is not on Hackage. This is the first push for both packages.
   `keiki-codec-json`'s `build-depends` line in
   `keiki-codec-json/keiki-codec-json.cabal` carries `keiki` with no
   version bound; the first-Hackage path adds `^>= 0.1`. Both packages
   ship at `0.1.0.0`.
2. `keiki 0.1.0.0` is already on Hackage. The introduction of
   `Keiki.Shape` is a non-breaking *addition* to the public API; the
   PVP-correct bump is to `0.2.0.0` (a minor-version bump per the
   Haskell PVP — *not* the Semantic Versioning interpretation; see
   <https://pvp.haskell.org>). Both packages ship in a coordinated
   push: `keiki-0.2.0.0` and `keiki-codec-json-0.1.0.0` with the latter
   pinned to `keiki ^>= 0.2`.

Verification: run

    cabal info keiki 2>&1 | head -20

against a stock `~/.cabal/config` (or any current cabal install). If the
output reports "package not found", path 1 applies; otherwise the
existing versions are listed and path 2 applies.

Acceptance: a one-line entry in this plan's Decision Log naming the
chosen path with the `cabal info` evidence captured. No code changes
yet.

**M2 — Expand `tested-with` and CI matrix to two GHC versions.**

Today both `.cabal` files declare `tested-with: GHC == 9.12.*` and CI's
`test` job's `matrix.ghc` has one row `'9.12.2'`. The cross-GHC golden
hash gate has nothing to compare against in this state. Pick a second
GHC version — recommended is `9.10.*` (one minor below 9.12, well-
supported by `haskell-actions/setup@v2`, and the version most likely to
be on a fresh user's machine if they have not upgraded). Confirm
choice with the maintainer if uncertain; record in Decision Log.

Edit three files:

1. `keiki.cabal` line 11: `tested-with: GHC == 9.10.*, GHC == 9.12.*`
   (PVP format: comma-separated `GHC == X.Y.*` entries).
2. `keiki-codec-json/keiki-codec-json.cabal` line 16: same change, for
   symmetry.
3. `.github/workflows/ci.yml`, the `test` job's `matrix.ghc` field
   (line 26): add a second entry, e.g. `ghc: ['9.10.7', '9.12.2']`. Pin
   the patch version explicitly so CI does not silently float; if a new
   patch version comes out and we want to validate against it, that is
   a separate intentional bump.

Run the cross-GHC test locally first if a `9.10.7` ghcup install is
already available:

    GHCUP_GHC_VERSION=9.10.7 cabal test keiki-codec-json:keiki-codec-json-test \
      --test-options="--match 'M3 golden hash'"

If `9.10.7` is not locally available, install via

    ghcup install ghc 9.10.7

and then re-run. Either way, the assertion is that
`regFileShapeHash (Proxy @ExemplarSlots)` matches
`a37b2b77042a635f394a082765f3410ea23a0b89745b0c77242b925a03aa172b` on
both GHC versions. If it does not, the EP-36 §8 release-blocking
procedure kicks in: the cause is a divergence in `tyConModule` or
`tyConName` semantics for `Int`, `UTCTime`, or `Text`. The fix is a
`CanonicalTypeName` override in `Keiki.Shape` for the affected type
plus a major-version bump because in-flight snapshots' hashes are no
longer derivable. *Do not silently update the pinned golden* — the
golden is a contract anchor, not a moving target.

After the assertion passes locally, push the branch and watch the CI
`test` job run both rows. Both must be green.

Acceptance: `git diff HEAD~1 keiki.cabal keiki-codec-json/keiki-codec-json.cabal
.github/workflows/ci.yml` shows the matrix expansion; CI's most recent
`test` job has two completed matrix entries, both green; the local
test command above passes against both GHC versions.

**M3 — Cabal metadata polish.**

The `.cabal` files today carry the minimum: name, version, synopsis,
license, author, maintainer, copyright, category, build-type, tested-
with, build-depends. Hackage rendering needs more: a multi-line
`description` field, `homepage` URL, `bug-reports` URL, and a
`source-repository head` stanza so Hackage can link the package back
to its source.

Edit `keiki.cabal` to add (between the existing `category:` and the
first `common warnings`):

    description:
        Pure core for symbolic-register transducer event sourcing.
        Provides a typed register-file (@RegFile rs@), a deterministic
        symbolic transducer DSL, composition combinators (sequential,
        alternative, feedback), and a generic Aeson-free shape hash for
        snapshot discrimination (@Keiki.Shape@).
        .
        The optional JSON codec lives in the sibling package
        @keiki-codec-json@; this package never gains an aeson dependency.
    homepage:        https://github.com/<owner>/keiki
    bug-reports:     https://github.com/<owner>/keiki/issues
    extra-doc-files: README.md
                     CHANGELOG.md

    source-repository head
        type:     git
        location: https://github.com/<owner>/keiki

Edit `keiki-codec-json/keiki-codec-json.cabal` similarly. Its
`description` is already authored (lines 5–9); promote the existing
short text to a longer one matching the README's opening paragraphs.

The placeholder `<owner>` must be replaced with the actual GitHub owner
under which the keiki repository is published. If the repository is not
yet on GitHub, this milestone branches: either skip the `homepage` /
`bug-reports` / `source-repository` fields (Hackage accepts the omission)
or publish the repository first. Capture the choice in Decision Log.

Acceptance: `cabal check` on both packages (from the relevant working
directories) reports no errors. `cabal haddock` produces a haddock tree
that renders the new `description` field in the package header.

**M4 — CHANGELOG.md authored; README polish.**

`keiki` and `keiki-codec-json` both need a `CHANGELOG.md` file at the
package root. Create `keiki/CHANGELOG.md` and
`keiki-codec-json/CHANGELOG.md`. Suggested initial content (substitute
the version chosen in M1):

    # Changelog

    All notable changes to this package will be documented in this file.
    The format is based on [Keep a Changelog](https://keepachangelog.com/),
    and this project adheres to the Haskell PVP (https://pvp.haskell.org).

    ## [0.1.0.0] — 2026-MM-DD

    ### Added

    - Initial public release.
    - <package-specific summary of v0.1 surface>

If path 2 was chosen in M1 (`keiki` bump to 0.2.0.0), insert an
additional entry naming the new `Keiki.Shape` module as the added
surface.

`README.md` for both packages already exists (the codec's at
`keiki-codec-json/README.md`; the keiki core has none currently — verify
with `ls /Users/shinzui/Keikaku/bokuno/keiki/README.md` and create one
if missing). The first-time consumer needs:

* A two-paragraph "what is this" framing.
* A `cabal install --lib` line.
* A copy-pasteable worked example. For `keiki`, a minimal
  symbolic-register transducer + decider snippet from `Keiki.Decider`'s
  haddock or from `docs/foundations/01-keiki-introduction.md`. For
  `keiki-codec-json`, the snapshot persistence snippet already in
  `keiki-codec-json/README.md` lines 22–37.
* A pointer to the package's Hackage haddock as the authoritative API
  reference.

Acceptance: `cabal haddock --enable-doc-coverage` reports 100 % doc
coverage on both packages' exposed modules (EP-36 M6 already established
this for keiki-codec-json; check the same for keiki's `Keiki.Shape`,
which is the only module newly added since the last haddock pass).
`README.md` and `CHANGELOG.md` exist at both package roots with the
content described.

**M5 — `cabal check` + `cabal sdist` + clean rebuild.**

`cabal check` warns about anything Hackage's automated validation will
reject. Run, from the keiki repository root, two separate invocations
(one per package):

    cabal check
    (cd keiki-codec-json && cabal check)

Both must report `No errors found` (warnings about `synopsis` length or
`description` formatting are acceptable but should be addressed if the
fix is trivial).

Build the source distributions:

    cabal sdist all

The output `dist-newstyle/sdist/keiki-X.Y.Z.0.tar.gz` and
`dist-newstyle/sdist/keiki-codec-json-0.1.0.0.tar.gz` are the exact
bytes that will be uploaded to Hackage. Validate them by extracting
each to a clean directory and running `cabal build` *from there*, not
from this repository (so the build cannot accidentally pick up
non-sdisted files):

    mkdir /tmp/release-check && cd /tmp/release-check
    tar xzf /path/to/keiki/dist-newstyle/sdist/keiki-*.tar.gz
    tar xzf /path/to/keiki/dist-newstyle/sdist/keiki-codec-json-*.tar.gz
    cd keiki-* && cabal build && cabal test && cd ..
    cd keiki-codec-json-* && cabal build && cabal test

Both should succeed. Failure on the extracted-and-rebuilt copy means
the `.cabal` `exposed-modules` / `other-modules` / `hs-source-dirs` /
`extra-source-files` / `extra-doc-files` set is missing a file that
the in-tree build picks up implicitly. Add the missing entry to the
relevant `.cabal` field and re-run.

Acceptance: the two extracted directories build and test green from
scratch.

**M6 — Candidate upload runbook + release procedure docs.**

Author `docs/research/release-procedure.md` capturing the runbook for
this and future releases. The content is exactly the sequence M1–M5
above, generalised to "for the next release, bump the version, repeat
the M2 cross-GHC matrix exercise, update CHANGELOG, run M5
validation, then run M6". The runbook ends at the candidate-upload
step:

    # Inspect the candidate before publishing — Hackage candidates are
    # mutable for inspection; published versions are immutable.
    cabal upload dist-newstyle/sdist/keiki-X.Y.Z.0.tar.gz
    cabal upload dist-newstyle/sdist/keiki-codec-json-X.Y.Z.0.tar.gz

    # Open https://hackage.haskell.org/package/keiki-X.Y.Z.0/candidate
    # and https://hackage.haskell.org/package/keiki-codec-json-X.Y.Z.0/candidate
    # Verify the rendered description, the doc tree, and the
    # source-repository link. If anything looks wrong, fix and
    # re-upload as a new candidate.

    # Publish — irreversible.
    cabal upload --publish dist-newstyle/sdist/keiki-X.Y.Z.0.tar.gz
    cabal upload --publish dist-newstyle/sdist/keiki-codec-json-X.Y.Z.0.tar.gz

The plan deliberately stops one command short of `--publish`. The
maintainer reviews the candidate page, then runs the final two
commands manually.

Cross-reference the runbook from
`keiki-codec-json/CONTRIBUTING.md` "## Releasing" (new section) and
from `docs/research/effects-boundary.md` if a cross-reference fits the
narrative.

Dry-run the candidate-upload step *without* `--publish`:

    cabal upload --dry-run dist-newstyle/sdist/keiki-*.tar.gz
    cabal upload --dry-run dist-newstyle/sdist/keiki-codec-json-*.tar.gz

`--dry-run` validates the upload without sending bytes. Both must
succeed.

Acceptance: `docs/research/release-procedure.md` exists; the dry-run
upload reports success for both tarballs; `CONTRIBUTING.md` "Releasing"
section is present.


## Concrete Steps

The exact commands per milestone are inlined in "Plan of Work" above
because each milestone is a small, ordered sequence. The reader runs
them sequentially from the keiki repository root unless a `cd` is
specified.

Working directory throughout: `/Users/shinzui/Keikaku/bokuno/keiki`.

After each milestone, commit. Every commit's body MUST include both
trailers:

    MasterPlan: docs/masterplans/11-keiki-codec-json-package-implementation-and-rollout.md
    ExecPlan: docs/plans/37-coordinated-hackage-release-of-keiki-and-keiki-codec-json-v0-1.md
    Intention: intention_01kr96br7gec191n9gqbmhvt42


## Validation and Acceptance

The final acceptance is twofold.

1. **CI is green on the expanded matrix.** The `test` job in
   `.github/workflows/ci.yml` has two matrix rows after M2; both have
   the golden hash assertion passing. The `test-perturbed-deps` job is
   green. The advisory `bench` job posts its summary; drift > 20 %
   merits a Surprises & Discoveries note but does not gate the
   release.

2. **The release tarballs build from scratch in a clean directory.**
   M5's `tar xzf` + `cabal build` + `cabal test` workflow against the
   extracted copies succeeds, proving the `.cabal` file's manifest is
   complete.

The dry-run candidate upload in M6 is *not* the acceptance gate — it is
a sanity check for the maintainer. The real gate is M5. Once M5 is
green, the maintainer can run the candidate upload at any later point
without re-validating; once the candidate looks right on Hackage they
flip to `--publish`.


## Idempotence and Recovery

Every milestone is re-runnable.

* M1 (`cabal info`) is read-only.
* M2 (matrix expansion) is a file edit + CI run; if the second-GHC
  test fails, rollback is `git checkout HEAD -- keiki.cabal
  keiki-codec-json/keiki-codec-json.cabal .github/workflows/ci.yml`.
  The EP-36 §8 procedure kicks in for the failure path.
* M3, M4 (metadata + CHANGELOG + README) are file additions / edits;
  no destructive operations.
* M5 (`cabal sdist`) writes to `dist-newstyle/sdist/`; safe to re-run.
  The clean-directory rebuild step uses `/tmp/release-check` so it
  cannot pollute the working tree.
* M6 (`cabal upload --dry-run`) is, by construction, dry; safe to
  re-run.

There is no milestone that performs a `cabal upload --publish`. The
publish step is performed by the maintainer outside this plan.

Failure on any milestone is recoverable by `git checkout` of the
relevant files. The matrix expansion in M2 is the only step that
could in principle expose a real defect (a divergence in the golden
hash on the second GHC); the recovery there is to file the issue,
ship a `CanonicalTypeName` migration per EP-36 §8, and *not* update
the golden silently.


## Interfaces and Dependencies

This plan does not introduce new module surface or new dependencies
on the source side. It modifies, in order:

* `keiki.cabal` — `tested-with`, `description`, `homepage`,
  `bug-reports`, `extra-doc-files`, `source-repository head`.
* `keiki-codec-json/keiki-codec-json.cabal` — same fields.
* `.github/workflows/ci.yml` — `test` job's `matrix.ghc`.

It creates:

* `keiki/README.md` (if not already present).
* `keiki/CHANGELOG.md`.
* `keiki-codec-json/CHANGELOG.md`.
* `docs/research/release-procedure.md`.
* New `## Releasing` section in `keiki-codec-json/CONTRIBUTING.md`.

It does not modify, and must not modify:

* Any module under `src/Keiki/` or `keiki-codec-json/src/Keiki/Codec/`.
  The release is over the artifacts EP-36 produced; the source code is
  not part of the release-readiness work.
* The `build-depends` lines of either `.cabal`, except for the
  optional version bound on `keiki` that `keiki-codec-json` carries
  (which is set in M1 based on the path chosen).

External dependencies the plan relies on:

* `cabal` ≥ 3.10 (any version that ships with GHC 9.12 is fine).
* `ghcup` for installing the second GHC version named in M2.
* GitHub Actions runners with `haskell-actions/setup@v2`. The CI
  configuration already uses this.
* Hackage account credentials in `~/.cabal/config` (`username` +
  `password`, or a Hackage upload token). The plan does not actually
  use the credentials; M6 stops before the publish step.

The cross-GHC golden hash is a *contract surface* with downstream
consumers: a consumer of `keiki-codec-json` is entitled to assume that
`regFileShapeHash (Proxy @rs)` produces the same `Text` on every GHC
in the `tested-with` matrix. M2 is the first execution of the EP-36
§8 GHC upgrade procedure; the runbook in M6 generalises it to every
future GHC bump.
