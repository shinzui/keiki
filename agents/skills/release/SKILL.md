---
name: release
description: Release keiki and its sibling packages to Hackage following the Haskell PVP. Bumps versions, updates changelogs, runs the project's check gates, and publishes keiki, keiki-codec-json, and keiki-codec-json-test in dependency order.
argument-hint: "[major|minor|patch]"
disable-model-invocation: true
allowed-tools: Read, Bash, Edit, Glob, Grep, Write, AskUserQuestion
---

# keiki Hackage release skill

Release this repository's published packages to
[Hackage](https://hackage.haskell.org/) using a single shared version,
following the Haskell **PVP** (`A.B.C.D`).

This skill is the operator-driven companion to the maintainer runbook in
`docs/research/release-procedure.md` (authored by EP-37). When the two
disagree, the runbook is the source of truth — update it and this skill
together.

## Versioning Strategy

All published packages share the **same version number** and ship together
in one release window. A single annotated git tag `v<version>` marks each
release.

The Haskell PVP version format is `A.B.C.D`:

- `A.B` — **major**: bump for breaking API changes (removed/renamed exports,
  changed types, changed semantics).
- `C` — **minor**: bump for backwards-compatible API additions (new exports,
  new modules, new instances).
- `D` — **patch**: bump for bug fixes, docs, internal-only changes,
  performance improvements.

> **Note (PVP, not SemVer):** under PVP a backwards-compatible API addition
> is a *minor* bump of `C` — e.g. `0.1.0.0` → `0.1.1.0`, **not** `0.2.0.0`.

## Packages (in dependency order)

The packages MUST be published in this order due to their inter-package
`build-depends`:

1. **keiki** — `.` (repository root, `keiki.cabal`) — pure core; no internal
   deps.
2. **keiki-codec-json** — `keiki-codec-json/` — depends on `keiki ^>=0.1`.
3. **keiki-codec-json-test** — `keiki-codec-json-test/` — depends on
   `keiki ^>=0.1` and `keiki-codec-json ^>=0.1`.

`keiki-codec-json` and `keiki-codec-json-test` are unsatisfiable on Hackage
until `keiki` is published, so a partial release is never acceptable: sdist
and upload all three in one session.

The following package is **NOT released** to Hackage:

- **jitsurei** (`jitsurei/`) — worked examples (実例) for the keiki library.
  A local example aggregate, not a library consumers depend on.

## Arguments

`$ARGUMENTS` is optional:

- `major`, `minor`, or `patch` — specifies the bump level.
- If omitted, determine the bump level from the changes (see step 2).

## Steps

### 1. Determine what changed since the last release

- Read the current version from `keiki.cabal` (`version:` field). All three
  published packages share this version — confirm
  `keiki-codec-json/keiki-codec-json.cabal` and
  `keiki-codec-json-test/keiki-codec-json-test.cabal` match it.
- Find the latest release tag: `git tag --list 'v*' | sort -V | tail -1`.
  There may be **no tags yet** — the first release is `v0.1.0.0`.
- List commits since the last release:
  - If a tag exists: `git log --oneline <last-tag>..HEAD`.
  - If no tag exists: `git log --oneline` (the whole history is the release).
- If a tag exists and there are no commits since it, tell the user there is
  nothing to release and stop.

Present a summary:

- Current version
- Last release tag (or "none — first release")
- Number of commits since the last release
- Which of the three published package directories (`.`,
  `keiki-codec-json/`, `keiki-codec-json-test/`) have changes

### 2. Determine the next version using PVP

- If `$ARGUMENTS` is `major`, `minor`, or `patch`, use that bump level.
- Otherwise analyze the commits to propose a bump:
  - "breaking", "remove", "rename", "change type", a `!`/`BREAKING CHANGE`
    footer → **major**
  - "add", "new", "feat", "export", "module" → **minor**
  - "fix", "docs", "refactor", "internal", "perf", "chore" → **patch**
- For the **first release** there is no prior published version; ship the
  current cabal version as-is (today `0.1.0.0`) unless the user asks
  otherwise.

Increment the version:

- **major**: increment `B`, reset `C` and `D` to 0 (`0.1.2.3` → `0.2.0.0`).
- **minor**: increment `C`, reset `D` to 0 (`0.1.2.3` → `0.1.3.0`).
- **patch**: increment `D` (`0.1.2.3` → `0.1.2.4`).

Present the proposed bump and the resulting version, and **ask the user to
confirm** before making any edits.

### 3. Update versions, dependency bounds, and changelogs

#### Version update

Set the new version in all three cabal files:

- `keiki.cabal`
- `keiki-codec-json/keiki-codec-json.cabal`
- `keiki-codec-json-test/keiki-codec-json-test.cabal`

#### Internal dependency bounds

When the **`A.B`** (major.minor) of `keiki` changes, bump the matching
`^>=` bounds so dependents resolve against the new release:

- In `keiki-codec-json/keiki-codec-json.cabal`: the `keiki ^>=A.B` bound
  (library, benchmark, and test-suite stanzas).
- In `keiki-codec-json-test/keiki-codec-json-test.cabal`: the `keiki ^>=A.B`
  and `keiki-codec-json ^>=A.B` bounds (library and test-suite stanzas).

A patch-only bump (`D`) does not require touching the `^>=A.B` bounds, but
verify they still match the released `A.B`.

#### Changelogs

Each published package has a `CHANGELOG.md` (root `CHANGELOG.md`,
`keiki-codec-json/CHANGELOG.md`, `keiki-codec-json-test/CHANGELOG.md`),
following [Keep a Changelog](https://keepachangelog.com/) + PVP with an
`[Unreleased]` section convention.

For each:

- Add a new `## [X.Y.Z.W] — YYYY-MM-DD` section (today's date, ISO format)
  above previous entries.
- Move content out of the `[Unreleased]` section into the new version
  section, and leave a fresh empty `[Unreleased]` placeholder.
- Group entries under `### Added` / `### Changed` / `### Fixed` (only include
  categories that have entries), summarizing the commits since the last
  release for that package.

Show the user **all** changes (version bumps, dependency bounds, changelog
entries) for review before committing.

### 4. Run the project check gates

Run from the repository root, in order. Stop and fix on any failure.

1. **Format:** `nix fmt` (treefmt — fourmolu, nixpkgs-fmt, cabal-fmt).
2. **Build:** `cabal build all`.
3. **Test:** `cabal test all`. This includes the release-blocking
   **golden-hash gate** in
   `keiki-codec-json/test/Keiki/Codec/JSON/GoldenSpec.hs`
   (`regFileShapeHash (Proxy @ExemplarSlots)` must match the pinned value).
   keiki supports **GHC 9.12 only**; if the golden hash fails, follow the
   EP-36 §8 procedure in `keiki-codec-json/CONTRIBUTING.md` — **do not
   silently update the golden.**
4. **Per-package packaging check:**
   - `cabal check`
   - `(cd keiki-codec-json && cabal check)`
   - `(cd keiki-codec-json-test && cabal check)`
   Each must be clean. (`keiki` may emit an informational `[no-repository]`
   warning if no `source-repository head` stanza is present yet; that is
   acceptable and does not block publish.)
5. **Flake check:** `nix flake check` (treefmt + pre-commit gates).
   - Newly created/edited files must be `git add`-ed first — Nix evaluates
     the git tree, so untracked files are invisible to the check.

#### Clean-room sdist rebuild

Verify the tarballs build in isolation (catches missing
`extra-source-files:` / `extra-doc-files:` entries):

```bash
cabal sdist all
rm -rf /tmp/release-check && mkdir /tmp/release-check && cd /tmp/release-check
tar xzf <repo>/dist-newstyle/sdist/keiki-X.Y.Z.W.tar.gz
tar xzf <repo>/dist-newstyle/sdist/keiki-codec-json-X.Y.Z.W.tar.gz
tar xzf <repo>/dist-newstyle/sdist/keiki-codec-json-test-X.Y.Z.W.tar.gz
cat > cabal.project <<'EOF'
packages: keiki-X.Y.Z.W
          keiki-codec-json-X.Y.Z.W
          keiki-codec-json-test-X.Y.Z.W
with-compiler: ghc-9.12.2
EOF
cabal build all && cabal test all
```

Both must pass. A failure means a file the in-tree build picks up implicitly
is missing from the sdist — add it to the relevant `.cabal` field and re-run.

### 5. Commit, tag, and push

- Stage the modified `.cabal` and `CHANGELOG.md` files.
- Commit with a Conventional Commits message: `chore(release): <version>`.
  The body summarizes what's in the release and why this bump was chosen.
- Create an annotated tag:
  `git tag -a v<version> -m "Hackage release <version>"`.
- Push: `git push && git push origin v<version>`.

Per CLAUDE.md, confirm before pushing — do not push automatically.

### 6. Publish to Hackage (in dependency order)

Hackage treats a bare `cabal upload` as a **candidate** (mutable,
inspectable); `--publish` finalizes it (**irreversible** — the version
number can never be reused).

#### Candidate upload + inspection (recommended)

```bash
cabal upload dist-newstyle/sdist/keiki-X.Y.Z.W.tar.gz
cabal upload dist-newstyle/sdist/keiki-codec-json-X.Y.Z.W.tar.gz
cabal upload dist-newstyle/sdist/keiki-codec-json-test-X.Y.Z.W.tar.gz
```

Open each candidate page and verify the rendered `description`, the haddock
tree, the CHANGELOG rendering, and the `build-depends` upper bounds:

- `https://hackage.haskell.org/package/keiki-X.Y.Z.W/candidate`
- `https://hackage.haskell.org/package/keiki-codec-json-X.Y.Z.W/candidate`
- `https://hackage.haskell.org/package/keiki-codec-json-test-X.Y.Z.W/candidate`

If anything looks wrong, fix it in the working tree, bump the **last**
component (`X.Y.Z.W` → `X.Y.Z.(W+1)`), re-`cabal sdist`, and re-upload as a
new candidate (never reuse a version number).

#### Publish (irreversible), in dependency order

```bash
cabal upload --publish dist-newstyle/sdist/keiki-X.Y.Z.W.tar.gz
cabal upload --publish dist-newstyle/sdist/keiki-codec-json-X.Y.Z.W.tar.gz
cabal upload --publish dist-newstyle/sdist/keiki-codec-json-test-X.Y.Z.W.tar.gz
```

Publish `keiki` first so a downstream `cabal install` can resolve it before
the dependents land.

#### Upload pre-built haddock (recommended)

Hackage's auto-build of docs can lag or fail; upload pre-built docs for each
package:

```bash
cabal haddock --haddock-for-hackage --haddock-hyperlink-source --haddock-quickjump
cabal upload --documentation --publish dist-newstyle/<pkg>-X.Y.Z.W-docs.tar.gz
```

Report each Hackage URL: `https://hackage.haskell.org/package/<pkg>-X.Y.Z.W`.

Present a summary:

| Package | Version | Hackage URL |
|---------|---------|-------------|
| keiki | X.Y.Z.W | https://hackage.haskell.org/package/keiki-X.Y.Z.W |
| keiki-codec-json | X.Y.Z.W | https://hackage.haskell.org/package/keiki-codec-json-X.Y.Z.W |
| keiki-codec-json-test | X.Y.Z.W | https://hackage.haskell.org/package/keiki-codec-json-test-X.Y.Z.W |

### 7. Create the GitHub release

After all Hackage uploads succeed, create a GitHub release for the tag
(origin is `github.com/shinzui/keiki`; `gh` is installed):

```bash
gh release create v<version> --title "v<version>" --notes "$(cat <<'EOF'
## Packages

| Package | Hackage |
|---------|---------|
| keiki | https://hackage.haskell.org/package/keiki-X.Y.Z.W |
| keiki-codec-json | https://hackage.haskell.org/package/keiki-codec-json-X.Y.Z.W |
| keiki-codec-json-test | https://hackage.haskell.org/package/keiki-codec-json-test-X.Y.Z.W |

## What's Changed

<changelog entries for this version from the root CHANGELOG.md>
EOF
)"
```

Use the root `CHANGELOG.md` entries for the release-notes body. Report the
GitHub release URL when done.

## Important

- Always ask the user to confirm the **version bump** and the **changelog
  entries** before committing.
- Always publish in dependency order: **keiki → keiki-codec-json →
  keiki-codec-json-test**. All three ship together; never publish a partial
  release.
- Never skip the check gates: `nix fmt`, `cabal build all`, `cabal test all`
  (golden-hash gate), per-package `cabal check`, `nix flake check`, and the
  clean-room sdist rebuild.
- If any step fails, **stop and report** — do not continue.
- If a Hackage upload fails for a package, do **not** continue uploading the
  packages that depend on it.
- `cabal upload --publish` is irreversible; a published version number can
  never be reused. Inspect the candidate first.
- The commit, tag, and push happen only **after** the user approves all
  changes; do not push automatically.
