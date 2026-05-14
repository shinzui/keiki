---
id: 39
slug: property-test-toolkit-for-downstream-codec-users-with-case-10-tojson-change-detector
title: "Property-test toolkit for downstream codec users with case-10 ToJSON change detector"
kind: exec-plan
created_at: 2026-05-14T03:55:31Z
intention: "intention_01kr96br7gec191n9gqbmhvt42"
master_plan: "docs/masterplans/11-keiki-codec-json-package-implementation-and-rollout.md"
---


# Property-test toolkit for downstream codec users with case-10 ToJSON change detector

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this plan completes, a downstream consumer of `keiki-codec-json`
(the primary motivating consumer is `keiro`; see
`keiro/docs/plans/9-integrate-keiki-codec-json-into-keiro-snapshot-path.md`)
can add **two import lines and three `Hspec.Spec` invocations** to
their test suite and pick up the full EP-36 codec-correctness
discipline against *their own* slot types and slot lists:

    import Keiki.Codec.JSON.Test
    import Keiki.Codec.JSON.Test.Golden (SlotGolden (..), slotGoldenSpec)

    spec :: Spec
    spec = do
      -- ** The lede: per-slot-type golden-byte ToJSON-change detector.
      -- Catches EP-36 §4 case #10 — a silent change to a slot type's
      -- ToJSON instance — which the shape hash CANNOT detect by design.
      slotGoldenSpec "Email" (SlotGolden
        { sgInput = Email "alice@example.com"
        , sgBytes = "\"alice@example.com\""
        })
      slotGoldenSpec "OrderId" (SlotGolden
        { sgInput = OrderId (T.pack "ord-42")
        , sgBytes = "\"ord-42\""
        })

      -- ** The library-ised disciplines from EP-36 M3.
      -- Round-trip + within-path determinism on the consumer's actual
      -- snapshot slot list, parameterised by the consumer's
      -- `ArbitraryRegFile` instance.
      regFileCodecProps @MyAppSnapshotSlots

      -- Sensitivity over schema-evolution mutations of the consumer's
      -- slot list. Each mutation is asserted to flip the shape hash.
      regFileShapeSensitivitySpec @MyAppSnapshotSlots
        [ ("add-slot", someKnownShape @MyAppSnapshotSlotsPlusOne)
        , ("rename",   someKnownShape @MyAppSnapshotSlotsRenamed)
        ]

Two distinct value propositions:

1. **The lede (genuinely new test surface): the case-#10 detector.**
   The shape hash `Keiki.Shape.regFileShapeHash` discriminates snapshots
   on *structural* slot-list changes (slot rename / add / remove /
   reorder / type change). It is, by design, **insensitive** to the
   slot type's `Aeson.ToJSON` *instance content*. If a consumer takes a
   slot type `Email` with one `ToJSON` instance, persists snapshots,
   then later edits the same type's `ToJSON` to emit a different shape
   (e.g. wrap the bare string in `{"address": ...}`), the shape hash
   remains identical and old snapshots silently fail to decode. This
   is the schema-evolution case EP-36 §4 #10 calls out. The
   `slotGoldenSpec` test is the contract anchor: it pins a golden bytes
   value for each slot type and fails loudly the moment the bytes
   diverge.

2. **Secondary (library-ised exposure of existing EP-36 disciplines):**
   `regFileCodecProps` and `regFileShapeSensitivitySpec` re-export the
   in-tree property + sensitivity testing patterns that EP-36 M3
   established in `keiki-codec-json/test/`. Today every downstream
   consumer would re-author those tests against their own slot list;
   the toolkit lets them call one function per discipline.

The toolkit ships as a **new sibling cabal package
`keiki-codec-json-test`** so that consumers of `keiki-codec-json`
proper do not transitively pull `QuickCheck`, `hspec`, and
`quickcheck-instances`. The package exposes two modules:
`Keiki.Codec.JSON.Test` (the round-trip + sensitivity props) and
`Keiki.Codec.JSON.Test.Golden` (the per-slot golden-byte detector).
The MP-11 Integration Points entry "EP-39 may add `tasty-quickcheck`
to the test stanza or split a sibling test-utility package"
pre-blesses this split.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] M1 — (2026-05-14) `keiki-codec-json-test/keiki-codec-json-test.cabal`
      ships with library stanza (two exposed modules) + test stanza;
      `cabal.project` lists the new package; `cabal build all` green
      with all packages compiling clean.
- [x] M2 — (2026-05-14) `Keiki.Codec.JSON.Test.Golden` exports
      `SlotGolden (..)` and `slotGoldenSpec`. The detector runs two
      assertions inside a `describe` block: `ToJSON matches golden
      bytes` and `FromJSON parses golden bytes back to the input`.
      Haddock 100% (3/3).
- [x] M3 — (2026-05-14) `Keiki.Codec.JSON.Test` exports
      `ArbitraryRegFile`, `regFileCodecProps`, `SomeKnownRegFileShape`,
      `someKnownShape`, `regFileShapeSensitivitySpec`. Property-suite
      implementation mirrors the in-tree EP-36 M3 spec
      (`keiki-codec-json/test/Keiki/Codec/JSON/PropSpec.hs`)
      parameterised in the slot list. Haddock 100% (9/9).
- [x] M4 — (2026-05-14) `keiki-codec-json-test/test/Spec.hs` plus
      `Demo.hs` exercise every helper against a toy `Email` slot
      type, `DemoSlots` baseline, and `DemoSlotsRenamed` mutation.
      `cabal test keiki-codec-json-test:keiki-codec-json-test-test`
      reports 7 examples, 0 failures.
- [x] M5 — (2026-05-14) `keiki-codec-json-test/README.md` authored
      with three sections (What this is for; Using; When you don't
      need this; Running the self-test). Cross-link from
      `keiki-codec-json/README.md` "Test toolkit for downstream
      consumers" section placed between "Benchmarks" and "Test
      suite".


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Ship the toolkit as a **third sibling cabal package**
  `keiki-codec-json-test`, not as an exposed module of `keiki-codec-json`
  proper.
  Rationale: A consumer of `keiki-codec-json` for production (e.g.
  the snapshot persistence path of a running service) should not
  transitively pick up `QuickCheck`, `hspec`, or
  `quickcheck-instances`. Splitting at the package boundary makes the
  test-only deps a *test-suite-only* concern in the consumer's cabal
  file. The MP-11 Integration Points entry pre-blesses this option.
  Cost: EP-37 (Hackage release) must now coordinate *three* package
  pushes, not two. The EP-37 Decision Log should be updated to
  acknowledge this scope creep before its first execution.
  Date: 2026-05-14.

- Decision: Make `slotGoldenSpec` (the case-#10 detector) the *lede*
  deliverable; treat `regFileCodecProps` /
  `regFileShapeSensitivitySpec` as library-ised re-exposures of
  existing EP-36 M3 disciplines.
  Rationale: EP-36 M3 already ships the round-trip / sensitivity
  testing in-tree (`keiki-codec-json/test/Keiki/Codec/JSON/PropSpec.hs`,
  `SensitivitySpec.hs`). The earlier MP framing of EP-39 had it as a
  "QuickCheck toolkit" — but that framing duplicates work already done.
  The §4 case-#10 detector (silent `ToJSON` instance change) is the
  *only* test surface neither the in-tree property suite nor the
  shape hash can catch by design, because the hash is over the *type*
  not the *encoding*. Foregrounding case #10 makes EP-39 earn its keep.
  MP-11 Decision Log of 2026-05-13 codified this scoping refinement;
  this plan operationalises it.
  Date: 2026-05-14.

- Decision: Lift `ArbitraryRegFile` (currently in
  `keiki-codec-json/test/Keiki/Codec/JSON/Fixtures.hs`) into the new
  toolkit library, *not* into `keiki-codec-json` proper.
  Rationale: `ArbitraryRegFile` is a QuickCheck-bearing class; pulling
  it into `keiki-codec-json` core would force the QuickCheck dep onto
  every consumer. Keeping it in the toolkit package is the right
  layering: production consumers pick up `keiki-codec-json` and never
  touch QuickCheck; test consumers pick up `keiki-codec-json-test` and
  get the class. The existing in-tree definition in `test/Fixtures.hs`
  remains for the in-package self-tests but is re-defined identically
  in the toolkit so external consumers can import it.
  Date: 2026-05-14.


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

**2026-05-14 — Plan complete.** Five milestones landed in one
session. The new sibling package `keiki-codec-json-test` is the
toolkit's home; two modules ship:

* `Keiki.Codec.JSON.Test.Golden` — the lede. `SlotGolden { sgInput,
  sgBytes }` + `slotGoldenSpec :: (ToJSON a, FromJSON a, Eq a, Show
  a) => String -> SlotGolden a -> Spec`. Two assertions per slot type
  (ToJSON-matches-golden and FromJSON-round-trips). Catches EP-36 §4
  case #10 exactly as the plan intended.
* `Keiki.Codec.JSON.Test` — the library-ised round-trip + sensitivity
  helpers. `ArbitraryRegFile` (the class lifted from EP-36's
  in-tree fixtures), `regFileCodecProps @rs` (four QuickCheck
  properties), `SomeKnownRegFileShape` + `someKnownShape` +
  `regFileShapeSensitivitySpec :: Proxy baseline -> [(String,
  SomeKnownRegFileShape)] -> Spec` (asserts each mutation flips the
  hash).

Self-test reports 7 examples, 0 failures
(`cabal test keiki-codec-json-test:keiki-codec-json-test-test`).
Haddock 100% on both modules (3/3 + 9/9). `keiki` and
`keiki-codec-json` build-depends unchanged — the new
`QuickCheck`/`hspec`/`quickcheck-instances` deps are scoped to the
third package only.

The implementation matched the plan very closely. The only mild
surprise was the haddock warning on `'SomeKnownRegFileShape' is
ambiguous` — the data type and its single constructor have the same
name, and haddock disambiguates by defaulting to the type. Not a
correctness issue and the haddock still renders correctly; left as-is.

EP-37 coordination: the addition of a third package is now real.
EP-37's M5 (`cabal sdist all`) and M6 (candidate upload runbook)
already cover "every package in the project" semantics, so the
expansion is operational rather than structural. The Decision Log
entry of 2026-05-14 on this scope creep is the durable record.

Open follow-ups (not blocking close):

* A `tasty-golden`-style helper for *managing* the golden bytes
  files instead of inline literals could reduce the friction of
  re-pinning when the user intentionally evolves a type's `ToJSON`.
  Not a v0.1 priority — inline literals are simpler and produce
  better diff output on failure.
* A "compose multiple slot lists" sensitivity helper could let
  consumers express "any of these mutations must flip the hash"
  without re-pasting `someKnownShape @` per row. Not a v0.1 priority
  either; the current per-row spec is readable and the cost is one
  line per mutation.


## Context and Orientation

The repository at the start of this plan contains the artifacts produced
by EP-36 and (potentially) EP-38. The toolkit reuses but does not modify
any of the following:

* **`/Users/shinzui/Keikaku/bokuno/keiki/keiki-codec-json/src/Keiki/Codec/JSON.hs`**
  — the `RegFileToJSON` class and its three methods. The toolkit's
  `regFileCodecProps` invokes these methods generically.
* **`/Users/shinzui/Keikaku/bokuno/keiki/src/Keiki/Shape.hs`** — exports
  `class KnownRegFileShape`, `regFileShapeHash`, `regFileShapeCanonical`.
  The toolkit's `regFileShapeSensitivitySpec` invokes
  `regFileShapeHash` against a baseline and a list of mutations and
  asserts each mutation produces a different hash.
* **`/Users/shinzui/Keikaku/bokuno/keiki/keiki-codec-json/test/Keiki/Codec/JSON/Fixtures.hs`**
  — defines `class ArbitraryRegFile (rs :: [Slot]) where arbRegFile ::
  Gen (RegFile rs)`, an inductive QuickCheck generator. The toolkit
  copies this class verbatim into its own library (per the Decision
  Log entry on layering).
* **`/Users/shinzui/Keikaku/bokuno/keiki/keiki-codec-json/test/Keiki/Codec/JSON/PropSpec.hs`**
  — the in-tree round-trip and determinism property tests against
  `ExemplarSlots`. The toolkit's `regFileCodecProps` is the same
  discipline parameterised over the consumer's own slot list.
* **`/Users/shinzui/Keikaku/bokuno/keiki/keiki-codec-json/test/Keiki/Codec/JSON/SensitivitySpec.hs`**
  — the in-tree sensitivity test asserting that each EP-36 §4
  mutation #1–9 flips the hash. The toolkit's
  `regFileShapeSensitivitySpec` is the same discipline parameterised
  over a baseline and an arbitrary mutation list.
* **`/Users/shinzui/Keikaku/bokuno/keiki/cabal.project`** — currently
  declares `packages: . jitsurei keiki-codec-json`. The toolkit
  package is added here.

Terms of art the reader needs:

* "**Golden byte test**" — a test where a function's output is
  compared bit-for-bit against a stored "golden" value. Drift in either
  direction (the function changes, or the data changes) trips the
  assertion. The standard pattern in Haskell test suites is the
  `tasty-golden` package or hand-rolled `shouldBe` comparisons against
  a committed bytestring.
* "**§4 case #10**" — the schema-evolution case in EP-36's §4 table
  where a slot type's `Aeson.ToJSON` *instance* silently changes (e.g.
  the user edits the data type's `deriving anyclass (ToJSON)` to a
  hand-written instance with different keys, or modifies a
  `fieldLabelModifier`). The slot type's *TypeRep* is unchanged, so
  `regFileShapeHash` returns the same value; old snapshots persist on
  disk but no longer decode.
* "**Sensitivity test**" — the dual of the golden test. A
  *deliberate* change in input (a slot rename, a slot addition) MUST
  produce a different hash. EP-36 M3 ships nine such mutations.
* "**`hspec`**" — Haskell's most-used test framework. A `Spec` is a
  tree of test descriptions; consumers wire it into their `main` via
  `hspec spec`.
* "**`QuickCheck`**" — Haskell's property-testing library. An
  `Arbitrary a` instance provides a generator `arbitrary :: Gen a`;
  a property like `forAll arbitrary (\x -> p x)` runs `p` against many
  random `x`.
* "**`KnownRegFileShape rs`**" — a constraint indicating that the
  slot list `rs` can be hashed. Every slot list whose slot types
  satisfy `CanonicalTypeName` automatically satisfies this constraint
  (per `Keiki.Shape`'s inductive instance).

The MasterPlan that authors this plan is
`docs/masterplans/11-keiki-codec-json-package-implementation-and-rollout.md`.
Its decomposition section says EP-39 may add a sibling test-utility
package, and its Decision Log of 2026-05-13 names the case-#10
detector as the lede deliverable. This plan executes both.

EP-36 §4 — the schema-evolution case table — is the authoritative
source for what the toolkit must catch. The plan's M2 must validate
that the case-#10 detector trips on at least one engineered "instance
change" scenario in its self-test suite (M4), giving downstream
consumers an end-to-end demonstration of the failure mode.


## Plan of Work

Five milestones, each independently verifiable.

**M1 — Sibling package scaffolding.**

Create the directory tree:

    /Users/shinzui/Keikaku/bokuno/keiki/keiki-codec-json-test/
      keiki-codec-json-test.cabal
      src/
        Keiki/
          Codec/
            JSON/
              Test.hs            -- empty module stub
              Test/
                Golden.hs        -- empty module stub
      test/
        Spec.hs                  -- placeholder; M4 fleshes out
      README.md                  -- M5 authors

Author `keiki-codec-json-test.cabal`. Library stanza:

    library
        exposed-modules:    Keiki.Codec.JSON.Test
                            Keiki.Codec.JSON.Test.Golden
        hs-source-dirs:     src
        build-depends:      base ^>= 4.21,
                            aeson ^>= 2.2,
                            bytestring ^>= 0.12,
                            hspec ^>= 2.11,
                            keiki,
                            keiki-codec-json,
                            QuickCheck ^>= 2.15,
                            quickcheck-instances ^>= 0.3,
                            text ^>= 2.1

Test stanza (M4 fills in `other-modules`):

    test-suite keiki-codec-json-test-test
        type:               exitcode-stdio-1.0
        hs-source-dirs:     test
        main-is:            Spec.hs
        build-depends:      base ^>= 4.21,
                            aeson ^>= 2.2,
                            bytestring ^>= 0.12,
                            hspec ^>= 2.11,
                            keiki,
                            keiki-codec-json,
                            keiki-codec-json-test,
                            QuickCheck ^>= 2.15,
                            quickcheck-instances ^>= 0.3,
                            text ^>= 2.1,
                            time ^>= 1.12

The cabal version pins match the existing `keiki-codec-json.cabal`
exactly (cf. `keiki-codec-json.cabal:36-76`); this is intentional —
the toolkit is shipped in lockstep.

Edit `/Users/shinzui/Keikaku/bokuno/keiki/cabal.project` to add the
new package to the `packages:` list:

    packages: .
              jitsurei
              keiki-codec-json
              keiki-codec-json-test

Acceptance: `cabal build all` succeeds with three empty modules.

**M2 — `Keiki.Codec.JSON.Test.Golden` (the lede).**

The module's public API:

    -- | A single (input, expected-bytes) golden pair for a slot type.
    data SlotGolden a = SlotGolden
      { sgInput :: a
      , sgBytes :: LBS.ByteString
      }

    -- | Run the case-#10 detector for a slot type. Two assertions:
    -- (1) `Aeson.encode (sgInput g) == sgBytes g`
    -- (2) `Aeson.decode (sgBytes g) :: Maybe a == Just (sgInput g)`
    --
    -- A failure on (1) means the slot type's `ToJSON` instance has
    -- silently changed since the golden was pinned — this is EP-36 §4
    -- case #10, the case the shape hash cannot detect by design.
    -- A failure on (2) means the slot type's `FromJSON` instance no
    -- longer parses the golden bytes — either because `FromJSON`
    -- diverged from `ToJSON` or because the golden was authored
    -- against bytes the current decoder rejects.
    slotGoldenSpec
      :: (Aeson.ToJSON a, Aeson.FromJSON a, Eq a, Show a)
      => String          -- ^ slot type name, used as the `Spec` description
      -> SlotGolden a
      -> Hspec.Spec

The implementation is a six-line `describe ... $ do { it ...; it ...
}` block invoking `shouldBe` against `Aeson.encode (sgInput g)` and
`Aeson.decode (sgBytes g)`. The simplicity is the point: the
detector's contract is that drift is loud and obvious. Haddock on
both `SlotGolden` and `slotGoldenSpec` is required; the haddock for
`slotGoldenSpec` must explicitly call out EP-36 §4 case #10 as the
motivating case and link to the EP-36 plan path.

Acceptance: `cabal build all` succeeds; `cabal haddock
keiki-codec-json-test` reports 100 % doc coverage.

**M3 — `Keiki.Codec.JSON.Test` (round-trip + sensitivity helpers).**

The module's public API:

    -- | Inductive QuickCheck generator for `RegFile rs`. A consumer
    -- gets this for free for any slot list whose slot types have
    -- `Arbitrary` instances. Mirror of the in-tree definition at
    -- `keiki-codec-json/test/Keiki/Codec/JSON/Fixtures.hs`.
    class ArbitraryRegFile (rs :: [Slot]) where
      arbRegFile :: Gen (RegFile rs)

    instance ArbitraryRegFile '[]
    instance ( KnownSymbol s, Arbitrary t, ArbitraryRegFile rs )
          => ArbitraryRegFile ('(s, t) ': rs)

    -- | Run the EP-36 M3 codec property suite against an arbitrary
    -- slot list. Four properties:
    --   * Value path round-trip:    `regFileFromJSON . regFileToJSON
    --                                  ≡ Right`.
    --   * Encoding path round-trip: similar via `regFileToEncoding`.
    --   * Value path determinism:   re-encoding produces byte-equal
    --                                  output.
    --   * Encoding path determinism: same.
    --
    -- Default 100 QuickCheck samples per property; override via the
    -- standard `--qc-max-success` test option.
    regFileCodecProps
      :: forall rs.
         ( RegFileToJSON rs
         , ArbitraryRegFile rs
         )
      => Hspec.Spec

    -- | A type-erased witness that a slot list is hashable. The
    -- existential allows the sensitivity helper to take a
    -- heterogeneous list of mutated slot lists in one parameter.
    data SomeKnownRegFileShape where
      SomeKnownRegFileShape :: KnownRegFileShape rs => Proxy rs
                            -> SomeKnownRegFileShape

    -- | Convenience constructor for `SomeKnownRegFileShape` via a
    -- type application.
    someKnownShape
      :: forall rs. KnownRegFileShape rs
      => SomeKnownRegFileShape
    someKnownShape = SomeKnownRegFileShape (Proxy @rs)

    -- | Run the EP-36 M3 sensitivity discipline. For each
    -- `(label, mutation)` pair, assert
    -- `regFileShapeHash mutation /= regFileShapeHash baseline`. A
    -- failure means a structural change (the kind the hash MUST
    -- detect, per EP-36 R5) was silently absorbed.
    regFileShapeSensitivitySpec
      :: forall baseline.
         KnownRegFileShape baseline
      => Proxy baseline
      -> [(String, SomeKnownRegFileShape)]
      -> Hspec.Spec

The implementations are straightforward translations of the in-tree
spec patterns at `keiki-codec-json/test/Keiki/Codec/JSON/PropSpec.hs`
and `SensitivitySpec.hs`. The differences are:

* `regFileCodecProps` is generic in `rs`, where the in-tree version
  hard-codes `ExemplarSlots`. The body is otherwise identical.
* `regFileShapeSensitivitySpec` takes the baseline + mutations as
  parameters, where the in-tree version hard-codes nine specific
  mutation types.

Haddock on every public symbol. The Spec docs must include a one-
sentence pointer to EP-36 M3 for users who want to see the original
in-tree pattern.

Acceptance: `cabal build all` succeeds; `cabal haddock` reports
100 % doc coverage.

**M4 — Self-test suite.**

Author `keiki-codec-json-test/test/Spec.hs` plus a `Demo.hs` helper
module under `test/Keiki/Codec/JSON/Test/`. The Demo defines:

* A toy slot type `data Email = Email Text deriving (Eq, Show,
  Generic) deriving anyclass (ToJSON, FromJSON, CanonicalTypeName)`
  and an `Arbitrary` instance.
* A baseline slot list `type DemoSlots = '[ '("email", Email),
  '("count", Int) ]`.
* A mutation `type DemoSlotsRenamed = '[ '("emailAddress", Email),
  '("count", Int) ]`.

The spec wires all three helpers:

    spec = do
      describe "golden: Email" $
        slotGoldenSpec "Email"
          (SlotGolden { sgInput = Email (T.pack "a@b.c")
                      , sgBytes = "\"a@b.c\""
                      })
      describe "props: DemoSlots" (regFileCodecProps @DemoSlots)
      describe "sensitivity: DemoSlots" $
        regFileShapeSensitivitySpec @DemoSlots
          (Proxy @DemoSlots)
          [ ("rename", someKnownShape @DemoSlotsRenamed) ]

Plus a *deliberately failing* golden case that demonstrates how case
#10 is caught — author the test as a `pendingWith` or `xit` so it
does not break CI, but include it as documentation that the
detector trips when expected:

    xit "DOCUMENTATION: case #10 trip example (intentionally fails)" $
      Aeson.encode (Email (T.pack "x"))
        `shouldBe` "{\"address\":\"x\"}"  -- ToJSON instance was changed

Acceptance: `cabal test keiki-codec-json-test:keiki-codec-json-test-test`
prints

    Test toolkit self-test
      golden: Email
        ToJSON matches golden bytes                  [ok]
        FromJSON . ToJSON round-trips                [ok]
      props: DemoSlots
        Roundtrip
          Value path round-trips                     [ok, 100 tests]
          Encoding path round-trips                  [ok, 100 tests]
        Determinism (within-path)
          Value path is deterministic                [ok, 100 tests]
          Encoding path is deterministic             [ok, 100 tests]
      sensitivity: DemoSlots
        mutation "rename" flips the hash             [ok]
    Finished in N.N seconds — N passed, 1 pending.

**M5 — README + cross-link.**

Author `keiki-codec-json-test/README.md` with three sections:

* "What is this" — two paragraphs explaining the case-#10 motivation
  and the secondary library-isation of EP-36 M3 disciplines.
* "Using" — a copy-pasteable code block showing the three helpers
  wired into a consumer's `Spec`.
* "When you don't need this" — explicit guidance that
  `keiki-codec-json` alone is sufficient for production use; the
  toolkit is opt-in for test suites.

Edit `keiki-codec-json/README.md` to add a new section
"Test toolkit" between the existing "Benchmarks" and "Test suite"
sections, with two sentences pointing to `keiki-codec-json-test`.

Acceptance: `cabal haddock` succeeds across all packages; README
files render correctly.


## Concrete Steps

Working directory throughout: `/Users/shinzui/Keikaku/bokuno/keiki`.

After M1:

    cabal build all
    # expected: four packages compile (keiki, keiki-codec-json,
    # keiki-codec-json-test, jitsurei). The new package has three
    # empty modules.

After M2:

    cabal build all
    cabal haddock keiki-codec-json-test
    # expected: 100 % doc coverage on Keiki.Codec.JSON.Test.Golden.

After M3:

    cabal build all
    cabal haddock keiki-codec-json-test
    # expected: 100 % doc coverage on both new modules.

After M4:

    cabal test keiki-codec-json-test:keiki-codec-json-test-test
    # expected: see Plan of Work M4 acceptance.

After M5:

    cabal haddock all
    # expected: no errors; three new READMEs renderable.

Every commit's body MUST include all three trailers:

    MasterPlan: docs/masterplans/11-keiki-codec-json-package-implementation-and-rollout.md
    ExecPlan: docs/plans/39-property-test-toolkit-for-downstream-codec-users-with-case-10-tojson-change-detector.md
    Intention: intention_01kr96br7gec191n9gqbmhvt42


## Validation and Acceptance

The user-visible behaviour after this plan is the toolkit ready for
import by a downstream test suite. A novice can verify by:

1. `cabal build all` succeeds with the new package in scope.
2. `cabal test keiki-codec-json-test:keiki-codec-json-test-test`
   passes with the output shown in M4 acceptance.
3. Synthetically break the case-#10 detector by changing the test's
   `Email`'s `deriving anyclass (Aeson.ToJSON)` to a hand-written
   instance with a different shape, e.g.

        instance Aeson.ToJSON Email where
          toJSON (Email t) = Aeson.object ["address" .= t]

   Re-run `cabal test`. The `golden: Email > ToJSON matches golden
   bytes` test must now fail with a message reporting the divergence:

        expected: "\"a@b.c\""
         but got: "{\"address\":\"a@b.c\"}"

   This proves the detector catches the case #10 scenario the shape
   hash cannot. Revert the instance change before committing.

4. Synthetically break the sensitivity detector by setting the
   mutation to `someKnownShape @DemoSlots` (same as baseline). The
   sensitivity test fails because the hash does not flip:

        sensitivity: DemoSlots
          mutation "rename" flips the hash
            expected predicate to hold against hash, but hashes match

   Revert before committing.

These two synthetic break-and-revert steps are the proof that the
detectors are real, not theoretical.


## Idempotence and Recovery

Each milestone is purely additive: a new directory, new files, a new
cabal-project entry. `git checkout HEAD -- cabal.project &&
rm -rf keiki-codec-json-test/` rolls the entire plan back. No source
files in `keiki` or `keiki-codec-json` are modified except the
single `keiki-codec-json/README.md` cross-link in M5; rolling back
that edit is `git checkout HEAD -- keiki-codec-json/README.md`.

The toolkit is by construction stateless. There is no persistent
state across test invocations. Property-test seeds default to
non-deterministic; consumers wanting reproducibility set
`--qc-replay` per the standard QuickCheck conventions.


## Interfaces and Dependencies

New package:

* `keiki-codec-json-test` at
  `/Users/shinzui/Keikaku/bokuno/keiki/keiki-codec-json-test/`.
  Two exposed modules.

  `Keiki.Codec.JSON.Test.Golden` public surface:

      data SlotGolden a = SlotGolden { sgInput :: a, sgBytes :: LBS.ByteString }
      slotGoldenSpec
        :: (Aeson.ToJSON a, Aeson.FromJSON a, Eq a, Show a)
        => String -> SlotGolden a -> Hspec.Spec

  `Keiki.Codec.JSON.Test` public surface:

      class ArbitraryRegFile (rs :: [Slot]) where
        arbRegFile :: QC.Gen (RegFile rs)
      regFileCodecProps :: forall rs.
        (RegFileToJSON rs, ArbitraryRegFile rs) => Hspec.Spec
      data SomeKnownRegFileShape
      someKnownShape :: forall rs.
        KnownRegFileShape rs => SomeKnownRegFileShape
      regFileShapeSensitivitySpec
        :: forall baseline. KnownRegFileShape baseline
        => Proxy baseline
        -> [(String, SomeKnownRegFileShape)]
        -> Hspec.Spec

New library dependencies (on the new package, not on
`keiki-codec-json`):

* `hspec ^>= 2.11`
* `QuickCheck ^>= 2.15`
* `quickcheck-instances ^>= 0.3`
* `aeson ^>= 2.2`, `bytestring ^>= 0.12`, `text ^>= 2.1` —
  already in scope across the project.
* `keiki`, `keiki-codec-json` — local packages.

Modules consumed but not modified:

* `Keiki.Codec.JSON` — for `RegFileToJSON` and its three methods.
* `Keiki.Shape` — for `regFileShapeHash` and `KnownRegFileShape`.
* `Keiki.Core` — for `RegFile`, `Slot`, `RCons`, `RNil`.

Files added:

* `keiki-codec-json-test/keiki-codec-json-test.cabal`
* `keiki-codec-json-test/src/Keiki/Codec/JSON/Test.hs`
* `keiki-codec-json-test/src/Keiki/Codec/JSON/Test/Golden.hs`
* `keiki-codec-json-test/test/Spec.hs`
* `keiki-codec-json-test/test/Keiki/Codec/JSON/Test/Demo.hs`
* `keiki-codec-json-test/README.md`

Files modified (single-line edits):

* `cabal.project` — add the new package to `packages:`.
* `keiki-codec-json/README.md` — one cross-link section.

**Structural invariant the plan preserves:** `keiki` core and
`keiki-codec-json` core gain no new build dependencies. The
toolkit's `QuickCheck` / `hspec` / `quickcheck-instances` deps are
scoped to the third package only. Production consumers of
`keiki-codec-json` see no transitive change.

**EP-37 coordination:** the addition of a third package means
EP-37's coordinated Hackage release must push three tarballs, not
two. EP-37's Decision Log should be updated when this plan
completes; if EP-37 has already begun execution, its M5 (`cabal
sdist all`) and M6 (candidate upload) extend to cover the third
package without additional design work.
