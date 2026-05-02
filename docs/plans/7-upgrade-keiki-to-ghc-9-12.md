---
id: 7
slug: upgrade-keiki-to-ghc-9-12
title: "Upgrade keiki to GHC 9.12"
kind: exec-plan
created_at: 2026-05-01T22:06:45Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
---

# Upgrade keiki to GHC 9.12

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

The keiki library currently builds with GHC 9.10.3 (pinned in
`keiki.cabal`'s `tested-with` field). Sibling Haskell projects in
`/Users/shinzui/Keikaku/bokuno/` — including `mori`, `mori-rei-app`,
`notion-hub`, `hw-kafka-streamly`, `hasql-opentelemetry` — have
moved to GHC 9.12.2, declaring `with-compiler: ghc-9.12.2` in their
`cabal.project` files. Keeping keiki on 9.10 means contributors who
work across multiple projects must keep two GHC toolchains hot, and
keiki's `cabal.project` doesn't pin a compiler at all (so `cabal
build` uses whatever's first on `PATH`, which is fragile).

After this plan is complete:

- `cabal.project` declares `with-compiler: ghc-9.12.3`, pinning the
  toolchain alongside sibling projects.
- `keiki.cabal`'s `tested-with: GHC == 9.10.3` field is updated to
  `tested-with: GHC == 9.12.*`.
- `keiki.cabal`'s `build-depends` bounds accommodate the boot
  libraries shipped with GHC 9.12 (notably `base ^>= 4.21` since
  GHC 9.12 ships base 4.21; existing pins of `text ^>= 2.1`, `time
  ^>= 1.12`, `hspec ^>= 2.11`, `sbv >= 11.7 && < 15` already cover
  GHC 9.12-compatible versions).
- Any `allow-newer:` waivers needed for transitive Hackage bounds
  that haven't been bumped are declared in `cabal.project`. The
  shape mirrors `hw-kafka-streamly/cabal.project`'s wildcard
  block:

      allow-newer:
        *:base, *:time, *:containers, *:template-haskell,
        *:text, *:bytestring, *:ghc-prim, *:deepseq, *:filepath

  This list is filed only if `cabal build` reports specific
  upper-bound conflicts; a clean build with no waivers is the
  preferred outcome.
- `cabal build` and `cabal test` succeed under GHC 9.12.2 with no
  warnings introduced by the version change. The existing 70-test
  suite (per MasterPlan 2's retrospective, EP-2 final state) stays
  green; nothing else in the codebase changes.

How a future contributor sees this work:

    cd /Users/shinzui/Keikaku/bokuno/keiki
    ghc --version
    # The Glorious Glasgow Haskell Compilation System, version 9.12.2
    cabal build
    # Resolves base ^>= 4.21, builds Keiki.Core, Keiki.Generics, Keiki.Symbolic, examples.
    cabal test
    # Runs keiki-test:Spec, 70 examples, 0 failures.

The user-visible win: contributor toolchain alignment with sibling
projects. The keiki public API and behavior do not change.


## Progress

Use a checklist to summarize granular steps. Every stopping point
must be documented here, even if it requires splitting a partially
completed task into two ("done" vs. "remaining"). This section must
always reflect the actual current state of the work.

- [x] **Milestone 0 — Verify prerequisites.** [2026-05-01] Baseline
      `cabal build all` succeeds on GHC 9.10.3 (already up-to-date
      from prior work). `cabal test all` reports `70 examples, 25
      failures` — matching the expected count of 70; the 25
      failures are `Unable to locate executable for Z3` from the
      SBV symbolic suite. z3 is missing from the user's PATH; this
      is a pre-existing environment condition unrelated to the
      upgrade and is recorded in Surprises & Discoveries. The
      original M0 task of confirming `ghc-9.12.x` was on PATH via
      ghcup did not apply: ghcup is not installed and the env is
      Nix-managed. Resolution captured in M0b.
- [x] **Milestone 0b — Provision GHC 9.12.x toolchain (Nix).**
      [2026-05-01] User added `flake.nix`, `flake.lock`, `.envrc`,
      and `treefmt.nix` to keiki, mirroring `hw-kafka-streamly`'s
      shape. Inside `nix develop`: `ghc --version` reports `9.12.3`
      (suffixed binary `ghc-9.12.3`); `cabal --version` reports
      `3.16.1.0`. The flake does not include z3; the symbolic test
      suite still requires `nix shell nixpkgs#z3` (or equivalent)
      at test time. The Nix scaffolding is out-of-scope for this
      ExecPlan's commit (Decision Log).
- [x] **Milestone 1 — Pin compiler in `cabal.project`.**
      [2026-05-01] Added `with-compiler: ghc-9.12.3` to
      `cabal.project` (note 9.12.3, not the originally specified
      9.12.2 — see Decision Log). First `cabal build all` failed
      as expected with `rejecting: base-4.21.1.0/installed-…
      (conflict: keiki => base^>=4.20)`, identifying the base
      bound as the next thing to bump. No other resolution
      failures appeared.
- [x] **Milestone 2 — Bump `keiki.cabal` `base` bound to `^>= 4.21`.**
      [2026-05-01] Updated both `library` and `keiki-test`
      `build-depends` to `base ^>= 4.21` via a single replacement.
      `cabal build all` inside `nix develop` resolved cleanly:
      cabal pulled in time-1.12.2, sbv-14.0, libBF-0.6.8, and
      friends; built `Keiki.Core`, `Keiki.Generics`,
      `Keiki.Examples.UserRegistration`,
      `Keiki.Examples.UserRegistrationV0`, and `Keiki.Symbolic`
      against `aarch64-osx/ghc-9.12.3`; built the test suite. Zero
      warnings emitted under the project's `-Wall -Wcompat
      -Widentities -Wincomplete-record-updates
      -Wincomplete-uni-patterns -Wpartial-fields
      -Wredundant-constraints` flag set.
- [x] **Milestone 3 — Resolve any remaining transitive bound
      conflicts.** [2026-05-01] **Skipped: not needed.** The base
      bound bump alone was sufficient. No `allow-newer` waivers
      were required. cabal's solver accepted GHC 9.12.3's boot
      versions of `text`, `time`, `containers`,
      `template-haskell`, `bytestring`, etc. against the existing
      pins (`text ^>= 2.1`, `time ^>= 1.12`, `sbv >= 11.7 && < 15`,
      `hspec ^>= 2.11`). The wildcard `allow-newer` block from
      `hw-kafka-streamly` was therefore not added to
      `cabal.project`.
- [x] **Milestone 4 — Update `tested-with` field.** [2026-05-01]
      Edited `keiki.cabal` line 11: `tested-with: GHC == 9.10.3`
      → `tested-with: GHC == 9.12.*`. Metadata-only change; no
      rebuild needed.
- [x] **Milestone 5 — Verify acceptance.** [2026-05-01]
      `cabal build all` clean (no errors, no warnings; `cabal
      clean && cabal build all` re-grepped for warning/error
      lines reports none). `nix shell nixpkgs#z3 -c cabal test
      all` reports `Finished in 0.6942 seconds, 70 examples, 0
      failures`. Test count matches the M0 baseline (70); failure
      count drops from 25 to 0 because z3 is now in scope (the
      M0 baseline failures were all environmental, per Surprises &
      Discoveries). All behavioral acceptance assertions hold:
      `userReg` type-checks; `isSingleValuedSym (withSymPred
      userReg)` returns True; the V0 hidden-input check produces
      its field-precise warning. Transcript captured in Outcomes.
- [x] **Milestone 6 — Commit and close.** [2026-05-01] Commit
      `11e258f` (`chore(toolchain): upgrade keiki to GHC 9.12`)
      stages only `cabal.project` and `keiki.cabal` (5 insertions,
      3 deletions). The Nix scaffolding (`flake.nix`, `flake.lock`,
      `.envrc`, `treefmt.nix`, the .gitignore additions, and the
      .seihou/manifest.json bump for the `nix-haskell-flake`
      module) was unstaged from the index before commit and is
      left for the user to commit separately, per the Decision Log
      decision to keep this ExecPlan's commit scoped to the two
      cabal files. Commit body carries both the `ExecPlan:
      docs/plans/7-upgrade-keiki-to-ghc-9-12.md` and `Intention:
      intention_01knjzws4qezz9w8b0743zfqv8` trailers; verified via
      `git log -1 --format=%B HEAD`.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights
discovered during implementation. Provide concise evidence.

- **2026-05-01 — Environment is Nix, not ghcup.** The plan's M0
  assumed `ghcup install ghc 9.12.2` was the install path. In this
  environment `ghcup` is not present; sibling projects (mori,
  hw-kafka-streamly, notion-hub) provide GHC via per-project Nix
  flakes. keiki had no `flake.nix` at plan-write time. Resolution:
  user added `flake.nix`, `flake.lock`, `.envrc`, and `treefmt.nix`
  to keiki (mirroring `hw-kafka-streamly`'s shape) before
  proceeding past M0. These four files are out of scope for this
  ExecPlan (it scopes itself to `cabal.project` + `keiki.cabal`)
  but are a hard precondition; they should be committed
  separately, not as part of this plan's commit.

- **2026-05-01 — nixpkgs ships GHC 9.12.3, not 9.12.2.** The
  flake's `pkgs.haskell.packages."ghc912"` attribute on
  `nixpkgs-unstable` (lock pinned to commit `7aaa00e`, 2026-04-30)
  resolves to GHC 9.12.3. Inside `nix develop` the suffixed binary
  is `ghc-9.12.3`; there is no `ghc-9.12.2`. `cabal-install` is
  3.16.1.0. Implication: `with-compiler:` must reference
  `ghc-9.12.3`, not `ghc-9.12.2` as originally specified. The base
  bound (`base ^>= 4.21`) and `tested-with` field
  (`GHC == 9.12.*`) are unaffected — both already cover 9.12.3.
  Evidence:

      $ nix develop --command bash -c 'ghc --version'
      The Glorious Glasgow Haskell Compilation System, version 9.12.3

- **2026-05-01 — M0 baseline has 25 pre-existing test failures.**
  `cabal test all` on the unmodified repo (GHC 9.10.3) reports
  `70 examples, 25 failures` — all SBV symbolic tests aborting
  with `Unable to locate executable for Z3`. z3 is not on `PATH`
  in this user's shell and is not provided by the new flake's
  devShell. This is environmental, not caused by the upgrade.
  Acceptance for M5 is therefore reframed: post-upgrade test
  results must match the baseline (70 examples, same 25 z3
  failures) when run outside a z3-equipped shell, OR (preferred)
  the test run is performed under `nix shell nixpkgs#z3` so the
  symbolic suite actually executes and the count is `70 examples,
  0 failures`. The plan does not extend the flake to include z3 —
  that is a separate cleanup the user can fold into the flake at
  their convenience.


## Decision Log

Record every decision made while working on the plan.

- Decision: Pin GHC via `with-compiler: ghc-9.12.3` in
  `cabal.project` rather than only via `tested-with` in
  `keiki.cabal`.
  Rationale: `tested-with` is metadata; cabal does not consult it
  to pick a compiler. Sibling projects (`mori`, `notion-hub`,
  `hw-kafka-streamly`) all use `with-compiler` in `cabal.project`
  to make the toolchain pin authoritative. Aligning with that
  pattern means `cabal build` works the same way across projects.
  Date: 2026-05-01

- Decision: Use the wildcard `allow-newer` block from
  `hw-kafka-streamly/cabal.project` only if needed.
  Rationale: A clean upgrade with no waivers is preferable; reach
  for waivers only when cabal reports specific upper-bound
  failures. The wildcard form is chosen over named-package waivers
  because GHC boot libraries bump in lockstep — listing them by
  package would invite future drift.
  Date: 2026-05-01

- Decision: Standalone ExecPlan, no MasterPlan parent.
  Rationale: The upgrade has zero shared coordination surface with
  any in-flight MasterPlan. MP-3 (Keiki.Generics DX follow-ups)
  treats this plan as a recommended-soft-dep but is not blocked by
  it. Promoting this work to a child of MP-3 would conflate two
  unrelated themes (tooling vs. authoring DX).
  Date: 2026-05-01

- Decision: Pin `with-compiler: ghc-9.12.3`, not `ghc-9.12.2`.
  Rationale: nixpkgs-unstable's `haskell.packages.ghc912` attribute
  resolves to GHC 9.12.3 at the lock commit chosen by the
  newly-added `flake.nix` (2026-04-30). The suffixed binary
  available inside `nix develop` is `ghc-9.12.3`; there is no
  `ghc-9.12.2`. Pinning to the explicit patch the toolchain
  actually delivers makes mismatches (e.g. a future nixpkgs bump
  to 9.12.4) fail loudly at build time rather than silently
  picking a different patch. The plan's other version-coupled
  fields (base bound `^>= 4.21`, `tested-with: GHC == 9.12.*`)
  remain correct because 4.21 / 9.12.* span the whole 9.12 series.
  Date: 2026-05-01

- Decision: Treat the new `flake.nix`/`flake.lock`/`.envrc`/
  `treefmt.nix` files as out of scope for this ExecPlan's commit.
  Rationale: This plan's "Idempotence and Recovery" section
  explicitly states "No file outside `cabal.project` and
  `keiki.cabal` should be edited by this plan; if `git diff` shows
  changes elsewhere, something has gone wrong." The Nix
  scaffolding is a necessary precondition discovered during M0,
  but conflating it into this plan's commit would muddy the
  history and break that invariant. The user is expected to
  commit the Nix scaffolding separately. The `M6 commit` step
  stages only `cabal.project` and `keiki.cabal`.
  Date: 2026-05-01


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones
or at completion. Compare the result against the original purpose.

**Outcome (2026-05-01):** Upgrade succeeded. keiki now builds and
tests cleanly under GHC 9.12.3 with zero source changes — only
two files in scope for this plan changed:

- `cabal.project`: added `with-compiler: ghc-9.12.3` after
  `packages: .`.
- `keiki.cabal`: bumped `base ^>= 4.20` → `base ^>= 4.21` in both
  the `library` and `keiki-test` `build-depends` blocks; updated
  `tested-with: GHC == 9.10.3` → `tested-with: GHC == 9.12.*`.

No `allow-newer` waivers were needed. No source modules were
edited. The keiki public API is byte-identical pre/post.

Test transcript (relevant tail), captured at
`/tmp/keiki-9.12-test.log`:

    Keiki.Examples.UserRegistration (symbolic)
      isSingleValuedSym (withSymPred userReg)
        answers True (the v2 retrospective gate) [✔]
      symSat over the User Registration aggregate
        satisfiable: PInCtor inCtorConfirm [✔]
        satisfiable: PEq (inpConfirm #confirmCode) (lit "abc123") [✔]
        unsatisfiable: PInCtor inCtorConfirm AND PInCtor inCtorResend [✔]
    Keiki.Examples.UserRegistrationV0
      userRegV0 — synthesis-§4 step-4 unfixed schema
        reconstitute returns Nothing on the V0 canonical log [✔]
        checkHiddenInputs surfaces at least one warning [✔]
        checkHiddenInputs warning includes the RequiresConfirmation source [✔]
        checkHiddenInputs warning names the missing InCtor and field [✔]

    Finished in 0.6942 seconds
    70 examples, 0 failures
    Test suite keiki-test: PASS

**Comparison against the plan's purpose:**

- ✅ `cabal.project` declares a pinned compiler (9.12.3 instead
  of 9.12.2 — see Decision Log).
- ✅ `keiki.cabal`'s `tested-with` field is `GHC == 9.12.*`.
- ✅ `keiki.cabal`'s `base` bound covers GHC 9.12's boot library
  (4.21.1.0).
- ✅ `cabal build` and `cabal test` succeed with no warnings.
- ✅ The 70-test suite remains green; failure count went from 25
  (z3-missing on M0) to 0 once z3 is in scope.

**Gaps & lessons learned:**

1. **Plan assumed ghcup; environment is Nix.** The plan's M0
   required `ghc-9.12.x` on PATH via ghcup. In this environment
   ghcup is not present and per-project Nix flakes are the
   sibling-project convention. The author of the plan had
   read the sibling `cabal.project` files but had not verified
   the developer-toolchain mechanism. Lesson: future
   toolchain-bump plans for projects in this monorepo should
   either (a) check for an existing `flake.nix`/`shell.nix` and
   include flake authoring as a prerequisite milestone, or (b)
   delegate flake authoring to a sibling Plan and treat it as a
   hard dependency. This plan's M0/M0b ended up implicitly doing
   (a) by recording the user's flake addition.

2. **nixpkgs delivers patch-level drift from the plan's pin.**
   The plan specified `with-compiler: ghc-9.12.2`; nixpkgs
   `ghc912` resolved to 9.12.3. The fix was trivial (one-line
   change in `cabal.project`), but the lesson is that pinning a
   specific patch in `with-compiler:` couples the project to
   whatever patch nixpkgs currently resolves to. An alternative
   worth considering: pin only major/minor (e.g. `ghc-9.12`) if
   cabal accepts it, or accept patch-level coupling and re-pin on
   each nixpkgs bump. Sibling projects all pin to 9.12.2 in their
   `cabal.project` files; with the current nixpkgs lock, those
   projects probably also need updating.

3. **z3 is a runtime test dependency not provided by the new
   flake.** The flake added in M0b includes `cabal-install`,
   `pkg-config`, `zlib`, `just`, and an HLS-equipped GHC, but no
   z3. The symbolic test suite requires z3 at run time. Running
   `nix shell nixpkgs#z3 -c cabal test all` works as a one-shot.
   A follow-up ergonomics improvement (out of scope for this
   plan) would be adding `pkgs.z3` to the flake's
   `nativeBuildInputs`, so `nix develop` alone is sufficient for
   the full test suite.

4. **Build wall-clock time:** the cold M2 build (resolving and
   compiling the dep tree under GHC 9.12.3, including a fresh
   sbv-14.0 build) took several minutes. Subsequent incremental
   builds are essentially instant.

The plan's "user-visible win — contributor toolchain alignment
with sibling projects" — is achieved as far as `with-compiler`
in `cabal.project` is concerned. The patch drift (sibling
projects pin 9.12.2; keiki now pins 9.12.3) is a soft
inconsistency — both build under the same nixpkgs `ghc912`
attribute, but the cabal pin diverges. Resolving that drift is a
sibling-side concern, not keiki's.


## Context and Orientation

Describe the current state relevant to this task as if the reader
knows nothing.

The keiki library is a pure-core implementation of symbolic-register
transducers for event sourcing. Its source tree is:

    keiki/
    ├── cabal.project           — currently `packages: .` (no compiler pin)
    ├── keiki.cabal             — cabal-version: 3.0; tested-with: GHC == 9.10.3
    ├── src/
    │   └── Keiki/
    │       ├── Core.hs         — formalism: Term, OutTerm, RegFile, SymTransducer
    │       ├── Generics.hs     — Generic-derived ctor helpers
    │       ├── Symbolic.hs     — SBV-backed BoolAlg instance
    │       └── Examples/
    │           ├── UserRegistration.hs
    │           └── UserRegistrationV0.hs
    └── test/
        └── Keiki/
            ├── CoreSpec.hs, SymbolicSpec.hs
            └── Examples/
                ├── UserRegistrationSpec.hs
                ├── UserRegistrationSymbolicSpec.hs
                └── UserRegistrationV0Spec.hs

Build dependencies declared in `keiki.cabal`:

    library
        build-depends:      base ^>= 4.20,
                            sbv >= 11.7 && < 15,
                            text ^>= 2.1,
                            time ^>= 1.12

    test-suite keiki-test
        build-depends:      base ^>= 4.20, keiki, hspec ^>= 2.11,
                            sbv >= 11.7 && < 15, text ^>= 2.1,
                            time ^>= 1.12

GHC 9.12 ships these boot libraries (relevant subset):

- `base 4.21.0.0`           (was 4.20.0.0 in GHC 9.10)
- `text 2.1.2`              (was 2.1.1; same major)
- `time 1.14`               (was 1.12.x; minor bump)
- `template-haskell 2.22.x` (was 2.22.x; same major)
- `containers 0.7`, `bytestring 0.12.*` (same as 9.10 era)

The base bump is the load-bearing change. `text` and `time` may
need waivers if Hackage upper bounds on transitive deps haven't
caught up (`sbv` 14.x supports GHC 9.12 per its CHANGELOG).

The runtime z3 dep (per `keiki.cabal`'s comment block) is
unaffected by the GHC bump.

**Sibling projects' cabal.project shapes for reference:**

- `mori-project/mori/cabal.project` uses `with-compiler:
  ghc-9.12.2` plus a `constraints` block for crypton and
  http-client-tls and an `allow-newer:` list for "packages not yet
  updated to GHC 9.12."
- `hw-kafka-streamly/cabal.project` uses `with-compiler:
  ghc-9.12.2` plus a wildcard `allow-newer` block listing boot
  libraries (`*:time, *:containers, *:template-haskell, *:text,
  *:bytestring, *:base, *:ghc-prim, *:deepseq, *:filepath`).
- `notion-hub/cabal.project` uses `with-compiler: ghc-9.12.2` plus
  `index-state: 2026-04-16T22:56:24Z` and a `program-options`
  RTS-tuning block.

The simplest of the three (`hw-kafka-streamly`'s wildcard block) is
the template this plan starts from; if that's overkill, it can be
trimmed in M3.


## Plan of Work

The work is six small milestones. Each is independently
verifiable. The expected outcome is a single commit (or two: one
for the cabal changes, one for the `tested-with` metadata bump),
not a multi-week effort.

**Milestone 0 — Baseline.** Confirm `cabal build all && cabal test
all` is green on the repo head (currently `master` at commit
`fc9bf03`). Record the test count (70 expected per MasterPlan 2).
Confirm `ghc-9.12.3` resolves on `PATH` or via `ghcup`. If not
installed, install via `ghcup install ghc 9.12.2`. Estimated time:
5 minutes. Acceptance: baseline transcript captured in this plan.

**Milestone 1 — Pin compiler.** Edit `cabal.project` to add
`with-compiler: ghc-9.12.3` on its own line below `packages: .`.
Run `cabal build all` from the repo root. The first run rebuilds
the entire dep tree under GHC 9.12; expect 1-3 minutes wall time.
Capture any errors. Acceptance: either build succeeds (great, jump
to M4) or specific failure modes are recorded for M2/M3 to address.

**Milestone 2 — Base bound.** Edit `keiki.cabal`. Change `base ^>=
4.20` to `base ^>= 4.21` in both `build-depends` blocks (one in
`library`, one in `test-suite keiki-test`). Re-run `cabal build
all`. Expected: cabal accepts the new bound and resolves base
4.21.0.0 (or whatever 4.21 minor GHC 9.12.2 ships). Acceptance:
either build succeeds or a different bound conflict surfaces.

**Milestone 3 — Allow-newer waivers (only if needed).** If
`cabal build all` after M2 reports upper-bound conflicts on
specific packages (e.g. "rejecting: sbv-14.0.0 (constraint from
keiki requires text >=2.0 && <2.2)"), add a targeted
`allow-newer:` block to `cabal.project`. Start with the wildcard
form mirroring `hw-kafka-streamly`:

    allow-newer:
      *:base, *:time, *:containers, *:template-haskell,
      *:text, *:bytestring, *:ghc-prim, *:deepseq, *:filepath

Re-run `cabal build all`. If a specific package still fails, add
its name to a targeted line (e.g. `sbv:text` if SBV's upper bound
on text excludes 2.1.2). Each waiver is recorded in the Decision
Log with its reason. Acceptance: build succeeds; the smallest
waiver block that works is committed.

**Milestone 4 — `tested-with` metadata.** Edit `keiki.cabal` line
11: change `tested-with: GHC == 9.10.3` to `tested-with: GHC ==
9.12.*`. No rebuild needed (the field is metadata). Acceptance:
the field accurately reflects the supported toolchain.

**Milestone 5 — Test acceptance.** Run `cabal test all` from the
repo root. Expected output:

    keiki> Test suite keiki-test: RUNNING...
    ...
    Finished in <time> seconds
    70 examples, 0 failures

If the count differs from the M0 baseline, investigate before
proceeding (a new test may have been added in a parallel branch;
or a test may now silently pass under new boot library versions).
Acceptance: test count matches baseline; 0 failures.

**Milestone 6 — Commit.** Stage the modified `cabal.project` and
`keiki.cabal`. Create a single commit with the conventional
prefix `chore(toolchain):`. Commit message body cites the
sibling-project alignment rationale. Trailers: `ExecPlan:
docs/plans/7-upgrade-keiki-to-ghc-9-12.md` and `Intention:
intention_01knjzws4qezz9w8b0743zfqv8`. Acceptance: `git log -1
--format=%B HEAD` shows both trailers.


## Concrete Steps

State the exact commands to run and where to run them. Update as
work proceeds.

All commands run from `/Users/shinzui/Keikaku/bokuno/keiki/`.

**M0 baseline:**

    cabal build all
    cabal test all
    ghc --version
    ghcup whereis ghc 9.12.2 || ghcup install ghc 9.12.2

Expected: `cabal test all` reports 70 examples, 0 failures.
`ghcup whereis ghc 9.12.2` either prints a path or returns an
error (in which case `ghcup install ghc 9.12.2` runs).

**M1 pin compiler:**

Edit `cabal.project`. After:

    packages: .

Add:

    with-compiler: ghc-9.12.3

Then:

    cabal build all

**M2 base bump:**

Edit `keiki.cabal` (two occurrences, one in each `build-depends`):

    base ^>= 4.20  →  base ^>= 4.21

Then:

    cabal build all

**M3 allow-newer (conditional):**

If M2 still fails, edit `cabal.project` to add (after
`with-compiler:`):

    allow-newer:
      *:base, *:time, *:containers, *:template-haskell,
      *:text, *:bytestring, *:ghc-prim, *:deepseq, *:filepath

Then:

    cabal build all

If specific named packages still fail with non-boot bounds (e.g.
SBV's bound on a non-boot lib), add a targeted line:

    allow-newer:
      ... (the wildcard list above)
      , <pkg>:<dep>

Re-run `cabal build all`.

**M4 tested-with:**

Edit `keiki.cabal` line 11:

    tested-with:        GHC == 9.10.3  →  tested-with:        GHC == 9.12.*

**M5 test acceptance:**

    cabal test all 2>&1 | tee /tmp/keiki-9.12-test.log
    grep -E '^[0-9]+ examples' /tmp/keiki-9.12-test.log

Expected: matches M0 baseline (70 examples, 0 failures).

**M6 commit:**

    git status
    git diff cabal.project keiki.cabal
    git add cabal.project keiki.cabal
    git commit -m "$(cat <<'EOF'
chore(toolchain): upgrade keiki to GHC 9.12.2

Pin `with-compiler: ghc-9.12.3` in cabal.project and bump base to
^>= 4.21 in keiki.cabal. Aligns the toolchain with sibling projects
(mori, notion-hub, hw-kafka-streamly).

ExecPlan: docs/plans/7-upgrade-keiki-to-ghc-9-12.md
Intention: intention_01knjzws4qezz9w8b0743zfqv8
EOF
)"


## Validation and Acceptance

After M5:

- `cabal build all` produces no errors and no warnings introduced
  by the compiler bump (existing warnings are tolerated only if
  they exist on the M0 baseline; new warnings are diagnosed and
  recorded in Surprises & Discoveries).
- `cabal test all` reports the same example count as M0 (70 at
  the time of writing), 0 failures.
- `ghc --version` invoked indirectly via cabal reports 9.12.2.
- `cat keiki.cabal | grep tested-with` shows `tested-with: GHC ==
  9.12.*`.
- `cat cabal.project | grep with-compiler` shows
  `with-compiler: ghc-9.12.3`.

Behavioral acceptance — the keiki public API does not change:

- `Keiki.Examples.UserRegistration.userReg` still type-checks and
  the canonical-log smoke test still passes.
- `isSingleValuedSym (withSymPred userReg)` still returns `True`
  (proved by z3 via SBV).
- The hidden-input check on `UserRegistrationV0` still produces
  the field-precise warning `OPack walk for InCtor "ConfirmAccount"
  leaves field {"confirmCode"} unrecovered`.

These are all assertions in the existing test suite; if `cabal
test all` is green, they pass.


## Idempotence and Recovery

The plan is idempotent. Each milestone's edits can be re-applied
without harm:

- M1's `with-compiler:` line is a single declaration; a second add
  is a no-op (or a syntax error caught by cabal's parser, easily
  reverted).
- M2's bound bump is an exact-string replacement; if already
  applied, the M2 edit is a no-op.
- M3's `allow-newer` block can be added incrementally; cabal
  parses the union.
- M4's `tested-with` change is metadata-only; safe to apply
  multiple times.

Recovery from a bad upgrade — if `cabal test all` regresses or
shows unexpected failures:

1. `git stash` the working tree.
2. `cabal build all && cabal test all` from the M0 baseline to
   confirm the regression is not pre-existing.
3. `git stash pop` and bisect by milestone — revert M3's
   `allow-newer` first (most likely to introduce a stale
   constraint), then M2's `base` bump (safe to revert; existing
   `^>= 4.20` excludes 4.21 and the build falls back to a 4.20
   resolution if `with-compiler` is also reverted).
4. If irrecoverable, `git checkout cabal.project keiki.cabal` to
   restore the baseline.

No file outside `cabal.project` and `keiki.cabal` should be
edited by this plan; if `git diff` shows changes elsewhere,
something has gone wrong.


## Interfaces and Dependencies

Libraries and modules touched:

- `cabal.project` — the cabal multi-package root.
- `keiki.cabal` — the package descriptor.

No source files in `src/` or `test/` are modified. No new modules
are added. No existing modules are removed or renamed.

Required tools:

- `ghc-9.12.3` available on `PATH` or installable via `ghcup
  install ghc 9.12.2`. The default GHCup install location is
  `~/.ghcup/bin/ghc-9.12.3`; cabal resolves this via
  `with-compiler:` automatically.
- `cabal` (the version doesn't matter — any cabal-install 3.10+
  understands `with-compiler:`).
- `z3` on `PATH` for the symbolic test suite (already required
  per `keiki.cabal`'s comment block; unaffected by this upgrade).

Interfaces preserved:

- All `library` exposed-modules continue to be exposed unchanged.
- All `keiki-test` other-modules continue to be tested unchanged.
- The `keiki` library's public API (every `module Keiki.*`'s
  export list) is byte-identical before and after this plan.
