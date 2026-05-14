# Contributing to keiki-codec-json

## GHC upgrade procedure (release-blocking)

The shape hash that powers snapshot discrimination
(`Keiki.Shape.regFileShapeHash`) uses `tyConModule + tyConName +
splitApps` from `Type.Reflection`. These accessors are stable across
GHC patch and minor versions historically, but the contract is not
covenanted forever. When bumping `tested-with` in `keiki.cabal`:

1. Add the new GHC to CI (`.github/workflows/ci.yml`'s `ghc` matrix
   entry).
2. Run the cross-GHC golden hash test:

       cabal test keiki-codec-json:keiki-codec-json-test \
         --test-options="--match 'M3 golden hash'"

   This asserts `regFileShapeHash (Proxy @ExemplarSlots)` matches the
   pinned value
   `a37b2b77042a635f394a082765f3410ea23a0b89745b0c77242b925a03aa172b`.

3. **If the test fails: stop. Block the release.** The cause is one of:
   - The new GHC changed `tyConModule` / `tyConName` semantics for one
     of the slot types (`Int` / `UTCTime` / `Text`). File an upstream
     GHC bug AND ship a `CanonicalTypeName` migration path for affected
     users (override the canonical name to the old value via
     `instance CanonicalTypeName Int where canonicalTypeName _ = "GHC.Types.Int"`,
     and bump the package's major version because the hash that
     in-flight snapshots carry is no longer derivable).
   - `renderStableTypeRep` has acquired an unintentional dependency on
     a non-stable accessor. Fix the keiki-side code; the hash for any
     stably-named type must continue to match the pinned golden.

4. Update `tested-with` in `keiki.cabal` (and `keiki-codec-json.cabal`
   for symmetry).

5. Add a release note explicitly flagging GHC X.Y.Z as validated
   against the golden hash.

The cross-GHC golden hash test is a **release-blocking gate**, not a
guideline. The whole point of the design is that drift cannot occur
silently; treating the test as advisory defeats the design (see EP-36
§8 in `docs/plans/36-regfile-json-codec-and-shape-hash-for-snapshot-persistence.md`).

## Performance bench drift

`bench/baseline.csv` is committed alongside the source. CI runs the
bench on every PR but does NOT block merges on drift. Reviewers should
look at the bench job output for unexpected slowdowns; > 20 % drift on
any single fixture × path pair is worth a comment. The cross-GHC hash
gate is the release blocker, not the bench, because (a) bench numbers
are noisier than hash determinism, and (b) the meaningful unit of
latency budget belongs to the consumer (keiro), not to keiki itself.

## Releasing

The full release procedure lives at
[`../docs/research/release-procedure.md`](../docs/research/release-procedure.md).
That document covers the coordinated push of `keiki`,
`keiki-codec-json`, and `keiki-codec-json-test`, the pre-publish
checklist, and the candidate-upload runbook. The EP-37 ExecPlan at
[`../docs/plans/37-coordinated-hackage-release-of-keiki-and-keiki-codec-json-v0-1.md`](../docs/plans/37-coordinated-hackage-release-of-keiki-and-keiki-codec-json-v0-1.md)
is the per-milestone narrative for the v0.1 first release.

## Adding a slot type to the test fixtures

If you add a new slot type to `Keiki.Codec.JSON.Fixtures.ExemplarSlots`,
the golden hash will change. Steps:

1. Update the fixture in `keiki-codec-json/test/Keiki/Codec/JSON/Fixtures.hs`.
2. Run `cabal test keiki-codec-json:keiki-codec-json-test`; capture the
   reported new hash from `GoldenSpec.hs`.
3. Update `keiki-codec-json/test/Keiki/Codec/JSON/GoldenSpec.hs` with the
   new pinned value.
4. Note the fixture change in the commit message; the cross-GHC gate's
   new baseline is implicitly established.
