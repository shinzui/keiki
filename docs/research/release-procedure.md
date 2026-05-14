---
title: "keiki / keiki-codec-json / keiki-codec-json-test release procedure"
created_at: 2026-05-14
audience: keiki maintainer
status: living document; updated alongside MP-11 Phase B
---

# Release procedure for keiki and its sibling packages

This document is the runbook for cutting a Hackage release of `keiki`,
`keiki-codec-json`, and `keiki-codec-json-test`. The procedure
generalises the EP-37 sequence (one-time first-release work) into the
repeating cycle the maintainer follows on each subsequent release.

The first execution of this procedure is the v0.1.0.0 release; EP-37
(`docs/plans/37-coordinated-hackage-release-of-keiki-and-keiki-codec-json-v0-1.md`)
is the per-milestone narrative for that release. This document is the
condensed, ongoing runbook.


## Coordination invariants

All three packages always ship together in the same release window.
The reason is the dependency chain:

* `keiki-codec-json` depends on `keiki ^>= 0.1` (specifically on the
  `Keiki.Shape` module added in EP-36 M1).
* `keiki-codec-json-test` depends on both `keiki ^>= 0.1` and
  `keiki-codec-json ^>= 0.1`.

A partial release — pushing only one or two of the three — produces
unsatisfiable dependencies for downstream consumers. Always sdist and
upload all three in one session.

The Haskell PVP versioning policy applies:

* New public modules / functions added without breaking existing
  callers ⇒ minor-version bump (e.g. `0.1` → `0.2`).
* Existing public surface modified, removed, or renamed ⇒
  major-version bump (e.g. `0.1` → `1.0`).
* Bug fix only, no API change ⇒ patch bump (`0.1.0.0` → `0.1.0.1`).

When bumping `keiki`'s major or minor, also bump
`keiki-codec-json`'s `build-depends: keiki ^>= X.Y` to match, and the
same for `keiki-codec-json-test`.


## Pre-publish checklist

Before running any `cabal upload`, verify each item.

### 1. The cross-GHC golden-hash gate is green on a real matrix

The `tested-with` field in `keiki.cabal` and `keiki-codec-json.cabal`
must list every GHC version the package is validated against. The
`.github/workflows/ci.yml` `test` job's matrix must match.

The release-blocking gate is the
`keiki-codec-json/test/Keiki/Codec/JSON/GoldenSpec.hs` assertion that
`regFileShapeHash (Proxy @ExemplarSlots)` matches the pinned value
`a37b2b77042a635f394a082765f3410ea23a0b89745b0c77242b925a03aa172b`.
A divergence between GHC versions means the hash discriminator is no
longer cross-version stable.

A one-row `tested-with` matrix has nothing to compare against; the
gate is operationally vacuous in that state. Before publishing,
expand the matrix to **at least two** entries:

    tested-with:        GHC == 9.10.*, GHC == 9.12.*

Update the matching CI matrix in `.github/workflows/ci.yml`:

    matrix:
      ghc: ['9.10.7', '9.12.4']

Install the second GHC locally (if not already present) and run:

    ghcup install ghc 9.10.7
    GHCUP_GHC_VERSION=9.10.7 cabal test \
      keiki-codec-json:keiki-codec-json-test \
      --test-options="--match 'M3 golden hash'"

The test must pass against the pinned value. If it fails, follow the
EP-36 §8 procedure in `keiki-codec-json/CONTRIBUTING.md` —
**do not silently update the golden**.

### 2. Every package's `cabal check` is clean

    cabal check
    (cd keiki-codec-json && cabal check)
    (cd keiki-codec-json-test && cabal check)

Each must report `No errors or warnings could be found in the
package`. The `no-repository` warning on `keiki` is acceptable only
if no GitHub URL is yet decided; otherwise add a `source-repository
head` stanza.

### 3. CHANGELOG entries authored

Each released package has a `CHANGELOG.md`. Add a new section for the
version being released:

    ## [X.Y.Z.W] — YYYY-MM-DD

    ### Added
    - ...

    ### Changed
    - ...

    ### Fixed
    - ...

### 4. Cabal version bumped consistently

Three `.cabal` files (`keiki.cabal`,
`keiki-codec-json/keiki-codec-json.cabal`,
`keiki-codec-json-test/keiki-codec-json-test.cabal`) carry version
numbers. Bump each per PVP. Bump the `build-depends: keiki ^>= X.Y`
lines in the two child packages to match `keiki`'s new minor.

### 5. Clean-room rebuild from extracted sdists passes

The extracted tarballs must build green in an isolated directory:

    cabal sdist all
    rm -rf /tmp/release-check && mkdir /tmp/release-check
    cd /tmp/release-check
    tar xzf /path/to/keiki/dist-newstyle/sdist/keiki-X.Y.Z.0.tar.gz
    tar xzf /path/to/keiki/dist-newstyle/sdist/keiki-codec-json-X.Y.Z.0.tar.gz
    tar xzf /path/to/keiki/dist-newstyle/sdist/keiki-codec-json-test-X.Y.Z.0.tar.gz

    cat > cabal.project <<'EOF'
    packages: keiki-X.Y.Z.0
              keiki-codec-json-X.Y.Z.0
              keiki-codec-json-test-X.Y.Z.0
    with-compiler: ghc-9.12.4
    EOF

    cabal build all
    cabal test all

A failure on the extracted-and-rebuilt copy means a file referenced
by the in-tree build is missing from the sdist (typically an
`extra-source-files:` omission). Fix the relevant `.cabal` field and
re-run.


## The upload sequence

Once the checklist is green, the actual publish is three commands —
two candidate uploads, an inspection, then three publishes. **Each
`--publish` is irreversible** on Hackage; the version number can
never be reused.

### Step 1 — Candidate upload (mutable, inspectable)

    cabal upload dist-newstyle/sdist/keiki-X.Y.Z.0.tar.gz
    cabal upload dist-newstyle/sdist/keiki-codec-json-X.Y.Z.0.tar.gz
    cabal upload dist-newstyle/sdist/keiki-codec-json-test-X.Y.Z.0.tar.gz

The candidate URLs are:

* `https://hackage.haskell.org/package/keiki-X.Y.Z.0/candidate`
* `https://hackage.haskell.org/package/keiki-codec-json-X.Y.Z.0/candidate`
* `https://hackage.haskell.org/package/keiki-codec-json-test-X.Y.Z.0/candidate`

Open each. Verify:

* The rendered `description` from the `.cabal` file reads correctly.
* The auto-generated haddock tree links work; the public modules are
  documented.
* The `source-repository` link (if present) resolves.
* The `CHANGELOG.md` rendering shows the latest entry.
* `build-depends` lines have appropriate upper bounds.

If anything looks wrong, fix it in the working tree, bump the *last*
version component (`X.Y.Z.0` → `X.Y.Z.1`), and re-upload as a new
candidate. *Do not* re-use the same version number; Hackage indexes
candidates by version too, and a stale candidate can confuse the
inspection step.

### Step 2 — Publish (irreversible)

After the candidates look right:

    cabal upload --publish dist-newstyle/sdist/keiki-X.Y.Z.0.tar.gz
    cabal upload --publish dist-newstyle/sdist/keiki-codec-json-X.Y.Z.0.tar.gz
    cabal upload --publish dist-newstyle/sdist/keiki-codec-json-test-X.Y.Z.0.tar.gz

Run them in this order so transient resolver lookups during
`cabal install` from a fresh user have a chance to pick up `keiki`
first.

### Step 3 — Upload haddock (optional but recommended)

Hackage generates haddock automatically from the uploaded tarball,
but the auto-build can take hours or fail on machines without all
transitive deps. The reliable path is to upload pre-built haddock:

    cabal haddock --enable-doc-coverage \
      --haddock-for-hackage --haddock-html
    cabal upload --documentation \
      dist-newstyle/keiki-X.Y.Z.0-docs.tar.gz
    cabal upload --documentation --publish \
      dist-newstyle/keiki-X.Y.Z.0-docs.tar.gz

Repeat for the other two packages.

### Step 4 — Tag the release in git

    git tag -a vX.Y.Z.0 -m "Hackage release X.Y.Z.0"
    git push origin vX.Y.Z.0

Per CLAUDE.md, do not push automatically; the maintainer runs the
tag push.


## Failure recovery

* **`cabal upload` returns 403.** Hackage credentials in
  `~/.cabal/config` (`username` + `password`, or `:hackage` API
  token) are missing or wrong.
* **`cabal upload` returns 400 / "cannot parse cabal file".** The
  `.cabal` file's syntax has drifted; run `cabal check` to confirm
  the issue locally before re-uploading.
* **Candidate looks broken after upload.** Fix in the working tree,
  bump the build component, re-`cabal sdist`, re-upload as a new
  candidate. Hackage candidates are mutable for inspection; the
  cheap path is to iterate on the candidate URL until the page looks
  right before promoting to a real release.
* **Published version has a bug.** Hackage forbids changing a
  published version. The fix is to publish a new patch version
  (`X.Y.Z.0` → `X.Y.Z.1`); the broken release can be marked
  "deprecated" via the Hackage UI but cannot be removed.


## Reference

* MP-11 (the MasterPlan that drove this work):
  `docs/masterplans/11-keiki-codec-json-package-implementation-and-rollout.md`.
* EP-37 (the per-milestone release plan):
  `docs/plans/37-coordinated-hackage-release-of-keiki-and-keiki-codec-json-v0-1.md`.
* EP-36 §8 (the cross-GHC golden hash procedure):
  `docs/plans/36-regfile-json-codec-and-shape-hash-for-snapshot-persistence.md`.
* `keiki-codec-json/CONTRIBUTING.md` — the in-repo per-PR procedure
  the cross-GHC gate enforces.
