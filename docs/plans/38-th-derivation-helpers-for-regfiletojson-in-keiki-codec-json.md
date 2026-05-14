---
id: 38
slug: th-derivation-helpers-for-regfiletojson-in-keiki-codec-json
title: "TH derivation helpers for RegFileToJSON in keiki-codec-json"
kind: exec-plan
created_at: 2026-05-14T03:50:49Z
intention: "intention_01kr96br7gec191n9gqbmhvt42"
master_plan: "docs/masterplans/11-keiki-codec-json-package-implementation-and-rollout.md"
---


# TH derivation helpers for RegFileToJSON in keiki-codec-json

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this plan completes, a user of `keiki-codec-json` can take a plain
Haskell record type with `deriving (Generic)` and turn its snapshot path
into one line of Template Haskell. Concretely, given

    data MySnapshot = MySnapshot
      { retryCount    :: Int
      , correlationId :: Text
      , dispatchedAt  :: UTCTime
      }
      deriving stock (Eq, Show, Generic)

a single splice

    $(deriveRegFileCodec ''MySnapshot)

emits three top-level functions

    mySnapshotToJSON     :: MySnapshot -> Aeson.Value
    mySnapshotToEncoding :: MySnapshot -> Aeson.Encoding
    mySnapshotFromJSON   :: Aeson.Value -> Either String MySnapshot

each routed through the existing
`Keiki.Codec.JSON.RegFileToJSON` class against the slot list
`Keiki.Generics.RegFieldsOf MySnapshot`. The user retains direct
control over the slot symbol names (they are the record's field names),
keeps the strict missing-field / extra-field decoding discipline of
`regFileFromJSON`, and avoids hand-writing three boilerplate functions
per record. Compilation fails with a precise per-field error if any
field type lacks an `Aeson.ToJSON` or `Aeson.FromJSON` instance.

The splice lives in a new module **`Keiki.Codec.JSON.TH`** inside the
**`keiki-codec-json`** package. It must not live in `keiki`'s
`Keiki.Generics.TH` module — putting it there would transitively force
`aeson` onto `keiki` core, violating the load-bearing
"keiki MUST NOT gain `aeson`" requirement recorded in EP-36 §3 R8 and
in the MP-11 Decision Log entry of 2026-05-10 (`keiki itself remains
aeson-free`). The splice does, however, reuse keiki-side structural
machinery — `RegFieldsOf`, `GRecord`, and `KnownSlotNames` from
`Keiki.Generics` — so the composition with the existing TH ergonomics
is preserved.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] M1 — Add `template-haskell` dep to `keiki-codec-json.cabal`; create empty `Keiki.Codec.JSON.TH` module; `cabal build all` green.
- [ ] M2 — Implement `deriveRegFileCodec :: Name -> Q [Dec]` with the three-function emission described in Plan of Work; haddock on every public symbol.
- [ ] M3 — Test suite: a new `Keiki.Codec.JSON.THSpec` module exercising round-trip, encoding-path / value-path semantic agreement, missing/extra-field rejection, and a TH-time error case for a record with a non-ToJSON field type. `cabal test keiki-codec-json:keiki-codec-json-test` green.
- [ ] M4 — Update `keiki-codec-json/README.md` with the splice and a worked example; update `keiki-codec-json.cabal`'s `exposed-modules` to list the new module.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Place the splice in a new module `Keiki.Codec.JSON.TH` inside
  the `keiki-codec-json` package, **not** in `keiki`'s `Keiki.Generics.TH`.
  Rationale: `RegFileToJSON` and the `regFileToJSON` /
  `regFileFromJSON` / `regFileToEncoding` symbols the splice references
  live in `keiki-codec-json` (which imports `aeson`). A TH splice that
  emits calls to those symbols must be in the same package, otherwise
  the symbols are not in scope at splice-construction time. Putting the
  splice in `keiki`'s `Keiki.Generics.TH` would also force `aeson` onto
  `keiki` transitively (the splice would need `aeson` in scope to
  build its body), violating EP-36 §3 R8. The MP-11 Decision Log entry
  of 2026-05-13 made the same decision at the MasterPlan level; this
  plan operationalises it.
  Date: 2026-05-14.

- Decision: Name the splice `deriveRegFileCodec`, not
  `deriveRegFileToJSON` as the MasterPlan tentatively suggested.
  Rationale: `RegFileToJSON` is a *class name*; deriving "a
  `RegFileToJSON` instance" is a misnomer because the class has an
  auto-derived generic instance (`instance RegFileWalk rs =>
  RegFileToJSON rs`) and users never write an instance directly.
  The splice's actual deliverable is a triple of top-level *functions*
  that codec a single record; calling it "codec" matches what it emits.
  The MasterPlan's tentative name is updated by this Decision Log entry;
  MP-11 should be revised on first read to reflect the rename, or the
  MP-11 Integration Points entry should be touched up to say
  "deriveRegFileCodec" rather than "deriveRegFileToJSON".
  Date: 2026-05-14.

- Decision: Emit three top-level functions, *not* an instance of
  `Aeson.ToJSON` / `Aeson.FromJSON` for the record type.
  Rationale: An instance commits the record to a single JSON
  representation forever, which is the kind of decision the user should
  make explicitly (and may not want — they may want a different JSON
  shape when the record appears as a field of another record). Emitting
  free functions leaves the user in control: they can `deriving
  anyclass (ToJSON, FromJSON)` if they want the generic-derived shape
  too, or wrap the splice-emitted functions in a custom `ToJSON` /
  `FromJSON` instance manually. Free functions also make the round-trip
  property simpler to test because the codec is reachable by name
  rather than via dictionary resolution.
  Date: 2026-05-14.


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

The starting state of the repository contains the artifacts produced by
EP-36 (`docs/plans/36-regfile-json-codec-and-shape-hash-for-snapshot-persistence.md`).
Specifically, the modules and types this plan references are:

* **`/Users/shinzui/Keikaku/bokuno/keiki/keiki-codec-json/src/Keiki/Codec/JSON.hs`**
  — defines `class RegFileToJSON (rs :: [Slot])` with three methods
  `regFileToJSON :: RegFile rs -> Aeson.Value`,
  `regFileToEncoding :: RegFile rs -> Aeson.Encoding`,
  `regFileFromJSON :: Aeson.Value -> Either String (RegFile rs)`. The
  class has a *single generic instance*
  `instance RegFileWalk rs => RegFileToJSON rs`, where `RegFileWalk`
  has two inductive instances (`'[]` and `'(s, t) ': rs`). The
  inductive instance demands `KnownSymbol s`, `Aeson.ToJSON t`, and
  `Aeson.FromJSON t` for every slot. So *every* slot list whose
  component types satisfy ToJSON+FromJSON is automatically a
  `RegFileToJSON`.
* **`/Users/shinzui/Keikaku/bokuno/keiki/src/Keiki/Generics.hs`** —
  defines `type RegFieldsOf d = RegFieldsOfRep (Rep d)` (a type
  family that walks a `Generic` Rep and produces a `[Slot]` slot list
  whose names are the record's field names), `class GRecord (rep ::
  Type -> Type) (ifs :: [Slot]) | rep -> ifs` with methods
  `gToRegFile :: rep a -> RegFile ifs` and
  `gFromRegFile :: RegFile ifs -> rep a`, and the auxiliary
  `class EmptyRegFile`, `class KnownSlotNames`. These are the building
  blocks the splice reuses.
* **`/Users/shinzui/Keikaku/bokuno/keiki/src/Keiki/Generics/TH.hs`** —
  the existing TH module in `keiki` core. Its splices
  (`deriveAggregateCtors`, `deriveWireCtors`, `deriveView`) follow a
  consistent pattern: take a `Name`, call `reify` to inspect the
  declaration, build a `[Dec]` via the `quote` syntax (`[| ... |]` and
  `[d| ... |]`) or by hand-constructing `Dec`/`Exp` values. This plan
  follows the same patterns. **This module is not modified by EP-38**
  — see the Decision Log entry on splice location.
* **`/Users/shinzui/Keikaku/bokuno/keiki/keiki-codec-json/keiki-codec-json.cabal`**
  — currently declares `exposed-modules: Keiki.Codec.JSON` and
  `build-depends: aeson ^>= 2.2, keiki, text ^>= 2.1, base ^>= 4.21`.
  M1 adds `Keiki.Codec.JSON.TH` to `exposed-modules` and
  `template-haskell ^>= 2.23` to `build-depends`.

Terms of art the reader needs:

* "**Template Haskell**" (TH) — a GHC-provided compile-time
  metaprogramming system. A TH splice is a Haskell expression of type
  `Q [Dec]` (or `Q Exp`, etc.) that runs *during compilation*, emitting
  Haskell declarations that the compiler then processes as if the user
  had typed them. Invoked at use-site with `$(...)`.
* "**Reify**" — `reify :: Name -> Q Info` is the TH operation that
  inspects a declaration. For a record type `data Foo = Foo { x :: Int
  }`, reifying `''Foo` returns an `Info` value containing the data
  declaration's `[Con]` (constructors), which the splice walks to
  extract field names and types.
* "**Slot symbol**" — a `Symbol` (kind-level `String`) carried by a
  `Slot = (Symbol, Type)`. For a `RegFile`, every slot is keyed by a
  symbol; this codec uses those symbols verbatim as JSON object keys.
* "**`Aeson.ToJSON` / `Aeson.FromJSON`**" — the standard `aeson`
  package's typeclasses for converting between Haskell values and
  `Aeson.Value` (a sum type representing arbitrary JSON). Every slot
  type in a slot list that goes through the codec must instance both.
* "**Strict decoder**" — `regFileFromJSON` rejects a JSON Object that
  has a missing key (named slot has no entry), an extra key (an entry
  not present in the slot list), or a type-mismatched value (e.g. the
  JSON has a string where the slot type expects an `Int`). Each
  failure is `Left "<slotName>: <reason>"`.

The MasterPlan that authors this plan is
`docs/masterplans/11-keiki-codec-json-package-implementation-and-rollout.md`.
Its Integration Points entry "`Keiki.Codec.JSON.TH` module in
`keiki-codec-json`" is the contract for this plan: the splice lives
there, reuses keiki's `Keiki.Generics` for the structural walk, and
must not modify `Keiki.Generics.TH`'s existing API.


## Plan of Work

Four milestones, each independently verifiable.

**M1 — Scaffold the new module and add the `template-haskell` dep.**

Edit `keiki-codec-json/keiki-codec-json.cabal`:

* Add `Keiki.Codec.JSON.TH` to the library's `exposed-modules` list.
* Add `template-haskell ^>= 2.23` to the library's `build-depends`.
  (`keiki` core already depends on `template-haskell ^>= 2.23`; matching
  the version bound here is consistent.)

Create `keiki-codec-json/src/Keiki/Codec/JSON/TH.hs` with the bare
module header, a haddock module synopsis, and an empty
`deriveRegFileCodec :: Name -> Q [Dec]` stub returning `pure []`. The
stub's existence is the M1 deliverable.

Acceptance: `cabal build all` succeeds from the keiki repository root.

**M2 — Implement `deriveRegFileCodec`.**

The splice takes a `Name` (a record type name like `''MySnapshot`) and
emits a list of three top-level declarations. The work splits into:

1. *Reify the type and validate it is a single-record-syntax data type.*
   `reify ''MySnapshot` returns `TyConI (DataD _ _ _ _ ctors _)`. The
   splice must:

   * Reject if the declaration is anything other than `DataD` or
     `NewtypeD` (e.g. a type synonym, a class, a value binding) with a
     precise error message.
   * Reject if there are zero or more than one constructors — `data
     Foo = ... | ...` cannot map to a single slot list. Singleton
     constructors with no fields are accepted (the slot list is `'[]`
     and the splice still emits the three functions for symmetry; the
     resulting JSON is the empty object).
   * Reject if the single constructor is `NormalC` with positional
     (non-record) fields — `data Foo = Foo Int Text` produces no field
     names and so cannot map to a named slot list. Error message names
     `Foo` and instructs the user to switch to record syntax.
   * Accept `RecC name [(fieldName, _bang, fieldType), ...]`. The
     field list is the slot-list source.

2. *Derive the name prefix.* The convention is the record name with
   its first letter lower-cased: `MySnapshot → mySnapshot`. The three
   emitted names are `<prefix>ToJSON`, `<prefix>ToEncoding`,
   `<prefix>FromJSON`. The user can override by passing the prefix
   directly via a second splice `deriveRegFileCodecAs :: String -> Name
   -> Q [Dec]` (M2 ships both; the unprefixed form delegates to the
   prefixed form).

3. *Emit the three functions* by Template Haskell quotes. The bodies
   route through `regFileToJSON`, `regFileToEncoding`, and
   `regFileFromJSON` against `RegFile (RegFieldsOf RecordType)`,
   composing with `gToRegFile . from` (for encoding) and
   `to . gFromRegFile` (for decoding). The Generic instance is *not*
   emitted by the splice; the splice requires the user already wrote
   `deriving (Generic)` on the record. If the user did not,
   `reify` will still succeed but the splice-generated code will fail
   to compile with a missing-instance error; M2 emits a guard for this
   case by reifying the `Generic` instance for the record and
   `fail`-ing the splice with a helpful message if the instance is
   absent.

The emitted code, conceptually, for the worked example
`data MySnapshot = MySnapshot { retryCount :: Int, ... } deriving stock
Generic`, is:

    mySnapshotToJSON :: MySnapshot -> Aeson.Value
    mySnapshotToJSON =
      Keiki.Codec.JSON.regFileToJSON
        @(Keiki.Generics.RegFieldsOf MySnapshot)
        . Keiki.Generics.gToRegFile . GHC.Generics.from

    mySnapshotToEncoding :: MySnapshot -> Aeson.Encoding
    mySnapshotToEncoding =
      Keiki.Codec.JSON.regFileToEncoding
        @(Keiki.Generics.RegFieldsOf MySnapshot)
        . Keiki.Generics.gToRegFile . GHC.Generics.from

    mySnapshotFromJSON :: Aeson.Value -> Either String MySnapshot
    mySnapshotFromJSON v =
      fmap (GHC.Generics.to . Keiki.Generics.gFromRegFile)
           (Keiki.Codec.JSON.regFileFromJSON
              @(Keiki.Generics.RegFieldsOf MySnapshot) v)

Use the quote `[d| ... |]` for the implementation bodies and
substitute the record name and the emitted function names via TH's
`mkName` / `varE` / `conT` plumbing. The type annotations on the
three emitted bindings are explicit (a `SigD` decl per binding)
because relying on inference would force every call site to type-
annotate.

The constraints required for the emitted functions to compile —
`Generic MySnapshot`, `GRecord (Rep MySnapshot) (RegFieldsOf
MySnapshot)`, `RegFileToJSON (RegFieldsOf MySnapshot)` — are satisfied
automatically when the record has `deriving Generic` and each field
type has aeson instances. The splice does not need to emit constraint
contexts because the elaborated function bodies are concrete (the
slot-list type is `RegFieldsOf RecordType`, fully ground at the call
site).

Document each emitted function and the splice itself with haddock.
The splice's haddock must call out:

* The record must have `deriving (Generic)`.
* Every field's type must have `Aeson.ToJSON` and `Aeson.FromJSON`.
* The naming convention for the three emitted functions.
* The override variant `deriveRegFileCodecAs`.

Acceptance: `cabal build all` succeeds with the new module compiling;
`cabal haddock keiki-codec-json` reports 100 % doc coverage on the
new module.

**M3 — Test suite.**

Create `keiki-codec-json/test/Keiki/Codec/JSON/THSpec.hs` and add it
to the test suite's `other-modules` list in
`keiki-codec-json.cabal`. The spec exercises four behaviours:

1. *Round-trip on a small record.* Define a test record

       data TestRec = TestRec
         { trCount :: Int
         , trNote  :: Text
         }
         deriving stock (Eq, Show, GHC.Generics.Generic)

   Apply `$(deriveRegFileCodec ''TestRec)` and assert
   `testRecFromJSON (testRecToJSON (TestRec 7 (T.pack "hi"))) ==
   Right (TestRec 7 (T.pack "hi"))`.

2. *Encoding path agrees with Value path on parse.* Decode the bytes
   produced by `Aeson.encodingToLazyByteString . testRecToEncoding`
   via `testRecFromJSON . fromJust . Aeson.decode`; the resulting
   `TestRec` is equal to the original.

3. *Strict decoding behaviour preserved.* Feed
   `testRecFromJSON` a JSON object missing a field; assert the
   result is `Left "trCount: missing slot"` (or whatever the slot-
   missing message is for the omitted field). Feed it a JSON object
   with an extra field; assert the result is `Left "regfile:
   unknown extra fields: [\"bogus\"]"`. Feed it a JSON object with a
   string where `trCount :: Int` is expected; assert `Left "trCount:
   ..."` with a substring match on `"expected"`.

4. *Empty-record edge case.* Define

       data Empty = Empty deriving stock (Eq, Show, GHC.Generics.Generic)

   Apply `$(deriveRegFileCodec ''Empty)`. Assert `emptyToJSON Empty ==
   Aeson.Object mempty` and `emptyFromJSON (Aeson.Object mempty) ==
   Right Empty`.

Wire the new spec into `keiki-codec-json/test/Spec.hs`'s spec
discovery (the `main` function calls `hspec spec` where `spec`
aggregates the existing spec modules — add the new one alongside).

A *negative* test (compile-time failure when a field type lacks
`Aeson.ToJSON`) cannot live in the regular test suite because the
expected outcome is a compile error. Document the negative test
manually in a comment block at the top of `THSpec.hs`:

    -- Negative test: replacing `trNote :: Text` with `trNote ::
    -- (Int -> Int)` and re-running `cabal build` produces a
    -- compile error of the form
    --     No instance for ‘Aeson.ToJSON (Int -> Int)’
    --       arising from a use of ‘testRecToJSON’
    -- This is the expected behaviour. A future EP may move this
    -- into a tasty-managed `should-not-compile` test, but for v0.2
    -- the manual procedure is documented here.

Acceptance: `cabal test keiki-codec-json:keiki-codec-json-test`
reports the existing spec suite + the new THSpec, all green.

**M4 — README + cabal `exposed-modules` polish.**

Update `keiki-codec-json/README.md` to add a "Using the TH splice"
section between the existing "Using" and "When to use the streaming
encoder" sections. The new section is a six-line code block: the
record declaration, the splice, and a one-line `testRecToJSON
(TestRec 7 "hi")` invocation showing the resulting `Aeson.Value`.

Verify `keiki-codec-json/keiki-codec-json.cabal`'s `exposed-modules`
list contains `Keiki.Codec.JSON.TH` (added in M1) and that the
`build-depends` line carries `template-haskell ^>= 2.23` (added in M1).

Acceptance: `cabal haddock keiki-codec-json` runs clean and the new
README section renders correctly when previewed locally (e.g. via
`bun x markserv keiki-codec-json/README.md` or any Markdown
previewer).


## Concrete Steps

Working directory throughout: `/Users/shinzui/Keikaku/bokuno/keiki`.

After M1:

    cabal build all
    # expected: every package compiles; the new module is empty so the
    # only diff is a one-line "compiling Keiki.Codec.JSON.TH" log line.

After M2:

    cabal build all
    cabal haddock keiki-codec-json
    # expected: 100 % doc coverage on Keiki.Codec.JSON.TH.

After M3:

    cabal test keiki-codec-json:keiki-codec-json-test
    # expected output prefix:
    #   Keiki.Codec.JSON.PropSpec
    #     Roundtrip
    #       Value path round-trips                   [ok, 100 tests]
    #     ... (existing tests)
    #   Keiki.Codec.JSON.THSpec
    #     deriveRegFileCodec
    #       TestRec round-trip                       [ok]
    #       TestRec encoding-path semantic agreement [ok]
    #       TestRec strict decoder rejects missing   [ok]
    #       TestRec strict decoder rejects extra     [ok]
    #       TestRec strict decoder rejects mismatch  [ok]
    #       Empty round-trip                         [ok]
    #   Finished in N.N seconds — all NN tests passed.

After M4: spot-check `keiki-codec-json/README.md` renders correctly
and `cabal haddock keiki-codec-json` runs clean.

Every commit's body MUST include all three trailers:

    MasterPlan: docs/masterplans/11-keiki-codec-json-package-implementation-and-rollout.md
    ExecPlan: docs/plans/38-th-derivation-helpers-for-regfiletojson-in-keiki-codec-json.md
    Intention: intention_01kr96br7gec191n9gqbmhvt42


## Validation and Acceptance

The user-visible behaviour after this plan is exactly the splice
expansion described in Purpose / Big Picture. A novice can verify by:

1. Clone the repository, run `cabal build all`. Build succeeds.
2. Create a small test file at any path, e.g.
   `/tmp/codec-th-smoketest.hs`:

       {-# LANGUAGE DeriveGeneric #-}
       {-# LANGUAGE TemplateHaskell #-}
       module Main where
       import qualified Data.Aeson as Aeson
       import qualified Data.ByteString.Lazy.Char8 as LBS
       import Data.Text (Text)
       import qualified Data.Text as T
       import GHC.Generics (Generic)
       import Keiki.Codec.JSON.TH (deriveRegFileCodec)

       data Demo = Demo { name :: Text, count :: Int }
         deriving stock (Eq, Show, Generic)

       $(deriveRegFileCodec ''Demo)

       main :: IO ()
       main = do
         LBS.putStrLn (Aeson.encode (demoToJSON (Demo (T.pack "alice") 3)))
         print (demoFromJSON (Aeson.Object mempty))

3. Build & run as a `ghc --make`-style script (or as a `cabal repl
   keiki-codec-json --build-depends=...` session). Expected output:

       {"name":"alice","count":3}
       Left "name: missing slot"

3. Run the full test suite: `cabal test keiki-codec-json`. All specs
   including the new `THSpec` are green.


## Idempotence and Recovery

Each milestone is re-runnable from any state.

* M1 (scaffolding) is purely additive — `git checkout HEAD --
  keiki-codec-json/keiki-codec-json.cabal
  keiki-codec-json/src/Keiki/Codec/JSON/TH.hs` rolls back.
* M2 (splice body) edits one file
  `keiki-codec-json/src/Keiki/Codec/JSON/TH.hs`. If the splice has a
  bug, `cabal build` will report it at compile-time; iterate on the
  source until the smoke test in Validation passes.
* M3 (tests) is purely additive — new test module plus one cabal
  `other-modules` line.
* M4 (README + cabal verification) is documentation-only.

The splice itself is, by Template Haskell semantics, deterministic:
running it twice on the same `Name` produces the same `[Dec]`. There
is no state to corrupt and no recovery procedure beyond `git
checkout`.

If a user runs the splice on a record whose field types lack the
required aeson instances, GHC will report the missing instances at
compile-time. This is a feature, not a failure mode: the splice is
intentionally not "smart" about pretending the instances are derived
— it would lead to surprising silent behaviour. The error message
GHC produces names the field type and points at the use site of the
emitted `<prefix>ToJSON` function, giving the user a precise lead.


## Interfaces and Dependencies

New module:

* `Keiki.Codec.JSON.TH` in
  `/Users/shinzui/Keikaku/bokuno/keiki/keiki-codec-json/src/Keiki/Codec/JSON/TH.hs`.
  Exposed-modules entry in `keiki-codec-json.cabal`.

  Public surface:

      deriveRegFileCodec   :: TH.Name -> TH.Q [TH.Dec]
      deriveRegFileCodecAs :: String -> TH.Name -> TH.Q [TH.Dec]

  Both are TH splices (callable as `$(...)` at a top-level
  declaration position).

New library dependencies:

* `template-haskell ^>= 2.23` on `keiki-codec-json`'s library stanza.
  Pinned to match keiki core's existing pin.

New test module:

* `Keiki.Codec.JSON.THSpec` in
  `/Users/shinzui/Keikaku/bokuno/keiki/keiki-codec-json/test/Keiki/Codec/JSON/THSpec.hs`.
  `other-modules` entry in `keiki-codec-json.cabal`'s test-suite
  stanza.

Modules consumed but not modified:

* `Keiki.Codec.JSON` (`keiki-codec-json`) — referenced by the splice
  bodies (`regFileToJSON`, `regFileToEncoding`, `regFileFromJSON`).
* `Keiki.Generics` (`keiki`) — referenced for `RegFieldsOf`,
  `gToRegFile`, `gFromRegFile`. The splice bodies route through these
  exactly as the existing `mkInCtorVia` / `mkWireCtorVia` helpers do.
* `Keiki.Core` (`keiki`) — referenced indirectly via `RegFile` /
  `Slot`. No new imports beyond what the existing test suite uses.
* `GHC.Generics` — for `from` / `to`. The splice bodies use these
  via their fully qualified names so the user's call-site does not
  need to import `GHC.Generics` themselves.

External libraries unchanged:

* `aeson ^>= 2.2` — already a `keiki-codec-json` dep.
* `text ^>= 2.1` — already a dep.

The structural invariant the plan must preserve: **`keiki` core
gains no new dependency.** No edit to `keiki/keiki.cabal`'s
`build-depends`. The Template Haskell splice runs at *compile-time
of code that uses `keiki-codec-json`*; the user's own package picks
up `template-haskell` as a transitive dep when they import
`Keiki.Codec.JSON.TH`. `keiki`'s build is unaffected.
