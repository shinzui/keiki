---
id: 57
slug: aggregate-ctor-derivation-with-per-constructor-suffix-overrides-and-excludes
title: "Aggregate ctor derivation with per-constructor suffix overrides and excludes"
kind: exec-plan
created_at: 2026-06-06T14:41:11Z
intention: "intention_01ktensqv9ecmv5cd5jrbcfej7"
master_plan: "docs/masterplans/14-keiki-and-keiki-codec-json-dsl-improvements-surfaced-by-the-seihou-consumer-audit.md"
---

# Aggregate ctor derivation with per-constructor suffix overrides and excludes

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

The keiki library ships Template Haskell ("TH" — Haskell code that runs at compile
time to generate more Haskell code) splices that write the per-command and per-event
boilerplate an event-sourced aggregate needs. Those splices live in
`src/Keiki/Generics/TH.hs`. Today a consumer has exactly two choices when deriving the
command-side helpers, and both are uncomfortable:

1. `deriveAggregateCtorsAll ''Cmd ''Regs` — enumerates every constructor and uses each
   constructor's own name as the helper-name suffix. Zero typing, but you get no say
   over any name.
2. `deriveAggregateCtors ''Cmd ''Regs [(ctor, short), ...]` — you hand-list a
   `(constructorName, shortName)` pair for *every* constructor. Total control, but you
   must repeat all of them even if you only wanted to shorten one.

There is no middle ground. A real consumer hit this. In the keiro-runtime-jitsurei
incident-command service
(`keiro-runtime-jitsurei/services/incident-command/src/IncidentCommand/Domain/Incident.hs`,
around line 267) the team wrote nine explicit pairs:

```haskell
$(deriveAggregateCtors ''IncidentCommand ''IncidentRegs
  [ ("DeclareIncident", "Declare")
  , ("AssignCommander", "AssignCommander")
  , ("EstablishSafetyPerimeter", "EstablishSafetyPerimeter")
  , ("DispatchResource", "DispatchResource")
  , ("OrderEvacuation", "OrderEvacuation")
  , ("RecordTriage", "RecordTriage")
  , ("CompleteEvacuation", "CompleteEvacuation")
  , ("ReconsiderTransferPlan", "ReconsiderTransferPlan")
  , ("CloseIncident", "CloseIncident")
  ])
```

Eight of those nine pairs are pure noise: their short name equals their constructor
name. Only `DeclareIncident -> "Declare"` carries information. The author paid for the
other eight only because the all-or-nothing API forced it.

After this change, that same consumer will be able to write:

```haskell
$(deriveAggregateCtorsWith ''IncidentCommand ''IncidentRegs
    defaultDeriveCtorOptions
      { suffixOverrides = Map.fromList [("DeclareIncident", "Declare")] })
```

and get byte-for-byte the same generated declarations. The new splice enumerates every
constructor automatically (like `deriveAggregateCtorsAll`), uses the override map when a
constructor appears in it, defaults to the constructor's own name otherwise, and can
skip constructors named in an exclude set. We add the dual on the event side,
`deriveWireCtorsWith`.

What someone can do after this change that they could not before: shorten or rename a
*subset* of an aggregate's generated helpers — or omit a subset entirely — without
hand-listing the constructors they were happy with. You can see it working by building
the library and running the test suite: a new fixture aggregate exercises an override
and an exclude at compile time, and runtime assertions prove the overridden helper got
the abbreviated name, the non-overridden helpers kept their constructor names, and the
excluded constructor generated *no* helper at all.

This plan also makes two classes of mistake fail loudly at compile time, which the
all-or-nothing API never had to worry about: (a) two constructors resolving to the
*same* short name (which would generate two clashing top-level `inCtor<Short>`
definitions), and (b) an override or exclude key that is not actually a constructor of
the named sum type (a typo). Both must abort the splice with a precise, named error
message rather than producing a confusing downstream type error or silently ignoring
the typo.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented
here, even if it requires splitting a partially completed task into two ("done" vs.
"remaining"). This section must always reflect the actual current state of the work.

- [x] M1: Add `DeriveCtorOptions` record + `defaultDeriveCtorOptions` to
      `src/Keiki/Generics/TH.hs`. (2026-06-06)
- [x] M1: Refactor `deriveAggregateCtors` / `deriveAggregateCtorsAll` to route through a
      shared internal helper (`genAggregateCtors`) that takes a resolved
      `[(String, String)]` plus the reified constructor list (no codegen duplication).
      (2026-06-06)
- [x] M1: Add the resolution helper (`resolveCtorSpecs`) that turns options + the reified
      constructor set into a resolved spec list, applying excludes and overrides.
      (2026-06-06)
- [x] M1: Add the two compile-time validations: unknown override/exclude keys, and
      duplicate resolved short names. Both `fail` in `Q` with named offenders.
      (2026-06-06)
- [x] M1: Implement and export `deriveAggregateCtorsWith`. (2026-06-06)
- [x] M1: Add the `Map`/`Set` imports and update the module export list + Haddock.
      (2026-06-06)
- [x] M1: Add a fixture aggregate to `test/Keiki/Generics/THSpec.hs` that uses
      `deriveAggregateCtorsWith` with one override and one exclude; add runtime
      assertions; build and run the suite green (297 examples, 0 failures). (2026-06-06)
- [x] M2: Add `DeriveWireOptions` + `defaultDeriveWireOptions` and
      `deriveWireCtorsWith` on the event side, mirroring M1 (shared codegen path via
      `genWireCtors`, same `resolveCtorSpecs` validations). (2026-06-06)
- [x] M2: Extend the THSpec fixture with an event sum type (`OverEvent`) derived via
      `deriveWireCtorsWith` (one override, one exclude); add runtime assertions.
      (2026-06-06)
- [x] M2: Document the two negative (compile-fail) cases as a manual verification block
      in this plan, with exact snippets and expected error text; verified the observed
      GHC error text matches both documented messages verbatim. (2026-06-06)
- [~] M2: (Optional, additive) Dogfood skipped — equivalence is already guaranteed
      structurally (all three command entry points route through the same
      `genAggregateCtors`/`genCtor` path; see Decision Log) and the new fixtures prove
      the feature; a redundant migration was not added. (2026-06-06)
- [x] Fill in Outcomes & Retrospective; update Surprises & Decision Log as needed.
      (2026-06-06)


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- The `keiki-test` stanza did **not** transitively expose `containers` to the spec
  modules: with `import qualified Data.Map.Strict as Map` in `THSpec.hs`, the build
  failed with `Could not load module 'Data.Map.Strict' … member of the hidden package
  'containers-0.7' … add 'containers' to the build-depends`. The plan's
  Interfaces & Dependencies section anticipated this as a conditional; it was required.
  Fix: added `containers >=0.6 && <0.9` to the `test-suite keiki-test` `build-depends`
  (matching the library's existing bound). (2026-06-06)


## Decision Log

Record every decision made while working on the plan.

- Decision: Refactor the existing codegen into a single shared internal helper that
  takes an already-resolved `[(String, String)]` spec list and the reified
  constructors, then route `deriveAggregateCtors`, `deriveAggregateCtorsAll`, and the
  new `deriveAggregateCtorsWith` through it.
  Rationale: The plan requires that overridden entries produce byte-for-byte identical
  declarations to today's `deriveAggregateCtors`. Sharing the exact same `genCtor`
  path is the cleanest way to guarantee that and avoid drift between three call sites.
  Date: 2026-06-06

- Decision: Model the options as a record carrying `Map String String` (overrides) and
  `Set String` (excludes), with a `defaultDeriveCtorOptions` value (both empty).
  Rationale: Matches the audit's proposed signature; `containers` is already a
  dependency (see `keiki.cabal`), so `Data.Map`/`Data.Set` cost nothing. A record with
  a default supports record-update syntax at the call site, which reads well for the
  common "override exactly one" case.
  Date: 2026-06-06

- Decision: Detect duplicate resolved short names and unknown override/exclude keys at
  compile time and abort with `fail` in the `Q` monad, naming the offenders (and, for
  unknown keys, listing the valid constructor names).
  Rationale: These are the type-safety acceptance criteria. `fail` in `Q` is exactly
  how the existing `deriveView` validations report problems (see
  `validateSpecCoverage` in `src/Keiki/Generics/TH.hs`), so we follow that precedent.
  Date: 2026-06-06

- Decision: Document the negative (must-fail-to-compile) cases as a manual verification
  block in this plan rather than adding a failing splice to the always-built suite.
  Rationale: The keiki test suite (`test/Spec.hs`) is a manual aggregator with no
  compile-fail harness; a permanently failing splice would break every `cabal build`.
  Documenting the snippet-to-paste and the expected error is the standard approach for
  TH error-path testing here.
  Date: 2026-06-06

- Decision: This plan is fully independent of the other ExecPlans in MasterPlan 14
  (EP-55/56/58/59/60). The only file it changes in the library is
  `src/Keiki/Generics/TH.hs` (and its export list); no other plan in MasterPlan 14
  touches that module. It can run fully in parallel with them.
  Rationale: Stated explicitly so a contributor need not coordinate with sibling plans.
  Date: 2026-06-06

- Decision: Skip the optional M2 dogfood (migrating an existing `*All` fixture to
  `deriveAggregateCtorsWith defaultDeriveCtorOptions`).
  Rationale: Drop-in equivalence is already guaranteed structurally — all three
  command-side entry points (`deriveAggregateCtors`, `deriveAggregateCtorsAll`,
  `deriveAggregateCtorsWith`) route through the single `genAggregateCtors`/`genCtor`
  path, so identical resolved specs produce identical declarations. The new `OverCmd`
  fixture already exercises override + default + exclude. A redundant migration would
  add churn without new coverage, and migrating `AutoCmd` would erode the dedicated
  `deriveAggregateCtorsAll` describe block. Equivalence remains asserted by the suite
  (the override fixture's default-named helper `inCtorPlain` is generated exactly as the
  `*All` path would).
  Date: 2026-06-06


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

Outcome: delivered in full against the original purpose. `Keiki.Generics.TH` now
exports `deriveAggregateCtorsWith` / `DeriveCtorOptions` / `defaultDeriveCtorOptions`
(command side) and `deriveWireCtorsWith` / `DeriveWireOptions` /
`defaultDeriveWireOptions` (event side). A consumer can enumerate every constructor
automatically while overriding the short name of a *subset* (e.g. Seihou's
`DeclareIncident -> "Declare"`) and/or excluding a subset — no more hand-listing the
constructors it was happy with. The exact ergonomics promised in Purpose now compile:

```haskell
$(deriveAggregateCtorsWith ''IncidentCommand ''IncidentRegs
    defaultDeriveCtorOptions
      { suffixOverrides = Map.fromList [("DeclareIncident", "Declare")] })
```

Both mistake classes fail loudly at compile time with precise, named messages
(duplicate resolved short name; unknown override/exclude key — the latter also lists the
valid constructors), verified verbatim against GHC output (see the negative-case
section).

Drop-in equivalence is structural: all three command entry points share
`genAggregateCtors`/`genCtor`, and both event entry points share `genWireCtors`/
`genWire`. The single sum-type-agnostic `resolveCtorSpecs` validator backs both sides,
so the command and event paths cannot drift in their validation behaviour.

Acceptance: `cabal build keiki` succeeds; `cabal test keiki-test` reports 300 examples,
0 failures, including the four `deriveAggregateCtorsWith` and three `deriveWireCtorsWith`
examples.

Gaps / deltas from the plan:

- The `keiki-test` stanza needed `containers` added explicitly (the plan flagged this as
  conditional; it was required). Recorded in Surprises & Discoveries.
- The optional dogfood was skipped as redundant (see Decision Log); equivalence is
  guaranteed by the shared codegen path rather than demonstrated by migration.

Lesson: routing every entry point (old and new) through one resolved-spec codegen helper
made the "byte-for-byte identical output" guarantee fall out for free and kept the two
new validations in a single place reused by both the command and event sides.


## Context and Orientation

This task lives entirely in the `keiki` Haskell package at the repository root
(`/Users/shinzui/Keikaku/bokuno/keiki`). The library is a "pure core" for event
sourcing built on a symbolic-register transducer formalism; for this plan you do not
need to understand the formalism, only the TH splices that generate per-constructor
helper bindings.

Terms used in this plan, in plain language:

- "Sum type" — a Haskell `data` type with several constructors, like
  `data Cmd = A AData | B BData | C` where `A`, `B`, `C` are the constructors. The
  command type and event type of an aggregate are both sum types.
- "Constructor name" — the capitalized name of one alternative of a sum type, e.g.
  `DeclareIncident`.
- "Short name" / "suffix" — the string appended to a fixed prefix to form a generated
  helper's identifier. With short name `Declare`, the command-side splice generates
  helpers named `inCtorDeclare`, `inpDeclare`, and `isDeclare`.
- "Splice" — a `$(...)` expression that runs TH code at compile time to inject
  generated declarations into the surrounding module.
- "`reify`" — a TH operation that, given a type's `Name`, returns its definition
  (including its constructor list). The splices use it to discover constructors
  automatically; this is what lets `deriveAggregateCtorsAll` enumerate everything and
  what lets the new code validate override/exclude keys against the *actual*
  constructor set.
- "`Q` monad" — the TH computation context. `fail "msg"` inside `Q` aborts the splice
  and surfaces `msg` as a compile error.
- "Record payload constructor" vs "singleton constructor" — a constructor with one
  argument that is a record type (e.g. `DoIt ToyData`) versus a zero-argument
  constructor (e.g. `NoArgs`). The command-side splice emits three declarations for a
  record-payload constructor (`inCtor<Short>`, `inp<Short>`, `is<Short>`) and only two
  for a singleton (`inCtor<Short>`, `is<Short>`) because the input projection is
  meaningless without a payload.

The file you will edit is `src/Keiki/Generics/TH.hs`. Read it before starting. The
functions that matter:

- `deriveAggregateCtors :: Name -> Name -> [(String, String)] -> Q [Dec]` (around line
  98). First `Name` is the command sum type, second is the register-file slot-list
  type, the list is `(constructorName, shortName)` pairs. Its body reifies the
  constructors into `ctorMap :: [(String, Con)]` and maps `genCtor` over the spec list.
- `deriveAggregateCtorsAll :: Name -> Name -> Q [Dec]` (around line 118). Identical,
  except it builds `specs = [(nameBase n, nameBase n) | c <- ctors, n <- conNames c]`
  instead of taking the spec list as an argument.
- `deriveWireCtors :: Name -> [(String, String)] -> Q [Dec]` (around line 134) and
  `deriveWireCtorsAll :: Name -> Q [Dec]` (around line 152) are the event-side
  equivalents; they map `genWire` instead of `genCtor`.
- `deriveAggregate :: Name -> Name -> Name -> Q [Dec]` (around line 171) fuses
  `deriveAggregateCtorsAll` and `deriveWireCtorsAll`.
- Internal helpers near the bottom: `reifyCtors`, `conNames`, `conPayload`, `genCtor`,
  `singletonDecls`, `recordDecls`, `genWire`. Name generation is *literal string
  concatenation* on the short name — e.g. `mkName ("inCtor" <> shortStr)`,
  `mkName ("inp" <> shortStr)`, `mkName ("is" <> shortStr)`, `mkName ("wire" <>
  shortStr)`, and `mkName (shortStr <> "TermFields")`. There is no computed suffix
  logic; the short string comes straight from the spec pairs (or from `nameBase` in the
  `*All` forms). This is exactly why routing the new splice through the *same* `genCtor`
  / `genWire` path guarantees byte-for-byte identical output for the same `(ctor,
  short)` pair.

Note the `deriveView` block already in this module is a fully worked example of
compile-time validation with named errors: `validateSpecCoverage`,
`validateSpecSlots`, and `validatePrefixUniqueness` each `fail` in `Q` with a message
built via the `showList'` helper (renders a `[String]` as `{ "a", "b" }`). Reuse
`showList'` for the new error messages.

`keiki.cabal` already lists `containers` and `template-haskell` among the library
dependencies (verify with `grep -n containers keiki.cabal` and `grep -n
template-haskell keiki.cabal`), so `Data.Map` and `Data.Set` are importable without
touching the cabal `build-depends`.

The test suite is `test/Spec.hs`, a manual aggregator: every spec module is
`import qualified`-ed and wired into `main` by hand (there is no `hspec-discover`). The
TH splices already have a spec at `test/Keiki/Generics/THSpec.hs` that defines toy
aggregates inline and asserts the generated helpers behave; you will extend that file.
Every test module must be listed in the `other-modules` of the `keiki-test` stanza in
`keiki.cabal` — `THSpec` already is, so extending the existing file needs no cabal
edit. If you instead create a *new* fixture module, you must add it to both
`keiki.cabal` `other-modules` and `test/Spec.hs`; this plan recommends extending the
existing `THSpec.hs` to avoid that.


## Plan of Work

The work splits into two milestones. M1 delivers the command side end-to-end (the
options record, the shared-codegen refactor, both validations, the new splice, and a
green test). M2 mirrors it on the event side and records the negative-case manual
verification. Each milestone is independently buildable and testable.


### Milestone 1 — command-side `deriveAggregateCtorsWith` with validation

Scope: introduce the options record and the new command-side splice; refactor so the
new splice, the explicit `deriveAggregateCtors`, and `deriveAggregateCtorsAll` all
share one codegen path; add the two compile-time validations; prove it with a fixture.

At the end of M1, `src/Keiki/Generics/TH.hs` exports `DeriveCtorOptions` (with its two
fields), `defaultDeriveCtorOptions`, and `deriveAggregateCtorsWith`, and the test suite
contains a fixture aggregate derived through the new splice with one override and one
exclude, with passing runtime assertions.

Step 1 — imports and exports. At the top of `src/Keiki/Generics/TH.hs`, add qualified
imports for the containers maps and sets, and (for the field accessors) the types
themselves:

```haskell
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
```

Extend the module export list to add the new public names:

```haskell
module Keiki.Generics.TH
  ( deriveAggregateCtors
  , deriveAggregateCtorsAll
  , deriveAggregateCtorsWith
  , DeriveCtorOptions (..)
  , defaultDeriveCtorOptions
  , deriveWireCtors
  , deriveWireCtorsAll
  , deriveWireCtorsWith        -- added in M2
  , DeriveWireOptions (..)     -- added in M2
  , defaultDeriveWireOptions   -- added in M2
  , deriveAggregate
  , deriveView
  ) where
```

(You may add the M2 names now or in M2; if you add them now, do not export names that
do not yet exist or the module will not compile. Prefer adding each export in the
milestone that defines it.)

Step 2 — the options record. Near the command-side splices (just above
`deriveAggregateCtors`), add:

```haskell
-- | Options for 'deriveAggregateCtorsWith'.
--
-- 'suffixOverrides' maps a constructor name to the short-name suffix to
-- use for its generated helpers (e.g. @"DeclareIncident" -> "Declare"@
-- yields @inCtorDeclare@ \/ @inpDeclare@ \/ @isDeclare@). Constructors
-- absent from the map default to their own name as the suffix.
--
-- 'excludeCtors' names constructors to skip entirely: no helpers are
-- generated for them.
--
-- Every key in either field must be an actual constructor of the named
-- sum type; an unknown key aborts the splice at compile time.
data DeriveCtorOptions = DeriveCtorOptions
  { suffixOverrides :: Map String String
  , excludeCtors    :: Set String
  }

-- | Default options: no overrides, no exclusions. With this, behaviour
-- is identical to 'deriveAggregateCtorsAll'.
defaultDeriveCtorOptions :: DeriveCtorOptions
defaultDeriveCtorOptions = DeriveCtorOptions
  { suffixOverrides = Map.empty
  , excludeCtors    = Set.empty
  }
```

Step 3 — shared codegen helper. The existing `deriveAggregateCtors` and
`deriveAggregateCtorsAll` both end with
`fmap concat . mapM (genCtor cmdName regsName ctorMap) $ specs`. Extract that into a
single helper so all three entry points share it. Add:

```haskell
-- | Shared command-side codegen: given the reified constructor map and a
-- resolved @(constructorName, shortName)@ spec list, emit the helper
-- declarations. All command-side entry points route through this so the
-- generated output is identical for identical resolved specs.
genAggregateCtors
  :: Name -> Name -> [(String, Con)] -> [(String, String)] -> Q [Dec]
genAggregateCtors cmdName regsName ctorMap specs =
  fmap concat . mapM (genCtor cmdName regsName ctorMap) $ specs
```

Then rewrite the two existing functions to call it (their `reifyCtors` / `ctorMap`
preamble is unchanged):

```haskell
deriveAggregateCtors cmdName regsName specs = do
  ctors <- reifyCtors cmdName "deriveAggregateCtors"
  let ctorMap = [ (nameBase n, c) | c <- ctors, n <- conNames c ]
  genAggregateCtors cmdName regsName ctorMap specs

deriveAggregateCtorsAll cmdName regsName = do
  ctors <- reifyCtors cmdName "deriveAggregateCtorsAll"
  let ctorMap = [ (nameBase n, c)          | c <- ctors, n <- conNames c ]
      specs   = [ (nameBase n, nameBase n) | c <- ctors, n <- conNames c ]
  genAggregateCtors cmdName regsName ctorMap specs
```

Step 4 — the resolution + validation helper. Add a helper that turns the reified
constructor base-names plus the options into a validated, resolved spec list. This is
where the two compile-time checks live. It is written generically (parameterized by the
caller name and whether overrides are allowed) so M2's event side can reuse it:

```haskell
-- | Resolve options against the reified constructor base-names into a
-- @(constructorName, shortName)@ spec list, validating override\/exclude
-- keys and rejecting duplicate resolved short names. @caller@ is the
-- splice name used in error messages.
resolveCtorSpecs
  :: String            -- ^ caller name, e.g. "deriveAggregateCtorsWith"
  -> [String]          -- ^ all constructor base-names of the sum type
  -> Map String String -- ^ suffix overrides (constructor -> short)
  -> Set String        -- ^ constructors to exclude
  -> Q [(String, String)]
resolveCtorSpecs caller allCtors overrides excludes = do
  -- (a) every override/exclude key must be a real constructor.
  let known      = Set.fromList allCtors
      overKeys   = Map.keysSet overrides
      badKeys    = Set.toList ((overKeys `Set.union` excludes)
                                 `Set.difference` known)
  case badKeys of
    [] -> pure ()
    _  -> fail $ caller <> ": option(s) name " <> showList' badKeys
              <> " which are not constructors of this type; "
              <> "valid constructors: " <> showList' allCtors
  -- (b) build the resolved spec, dropping excluded constructors and
  -- applying overrides (default short name = constructor name).
  let kept  = [ c | c <- allCtors, not (c `Set.member` excludes) ]
      specs = [ (c, Map.findWithDefault c c overrides) | c <- kept ]
  -- (c) reject duplicate resolved short names (would clash at codegen).
  let shorts = map snd specs
      dups   = [ s | (s : _ : _) <- group (sort shorts) ]
  case dups of
    [] -> pure ()
    _  -> fail $ caller <> ": short name(s) " <> showList' dups
              <> " are produced by more than one constructor; "
              <> "rename via suffixOverrides or exclude one"
  pure specs
```

Note `group` and `sort` are already imported from `Data.List` at the top of the
module, and `showList'` is the existing error-formatting helper at the bottom of the
file. Reuse both.

Step 5 — the new splice. Add `deriveAggregateCtorsWith`, which reifies, computes the
constructor base-names, resolves+validates, then routes through the shared codegen:

```haskell
-- | Derive command-constructor helpers for every constructor of the
-- command sum type, like 'deriveAggregateCtorsAll', but honouring
-- per-constructor short-name overrides and an exclude set carried in
-- 'DeriveCtorOptions'. A constructor in 'suffixOverrides' uses the
-- mapped short name; otherwise it defaults to its own name; a
-- constructor in 'excludeCtors' is skipped entirely.
--
-- Unknown override\/exclude keys and duplicate resolved short names both
-- abort the splice at compile time with a precise message. For a
-- constructor present in 'suffixOverrides', the generated declarations
-- are byte-for-byte identical to what 'deriveAggregateCtors' produces
-- for the same @(constructor, short)@ pair.
deriveAggregateCtorsWith
  :: Name              -- ^ command sum type, e.g. @\'\'IncidentCommand@
  -> Name              -- ^ register-file slot list, e.g. @\'\'IncidentRegs@
  -> DeriveCtorOptions
  -> Q [Dec]
deriveAggregateCtorsWith cmdName regsName opts = do
  ctors <- reifyCtors cmdName "deriveAggregateCtorsWith"
  let ctorMap  = [ (nameBase n, c) | c <- ctors, n <- conNames c ]
      allCtors = map fst ctorMap
  specs <- resolveCtorSpecs "deriveAggregateCtorsWith" allCtors
             (suffixOverrides opts) (excludeCtors opts)
  genAggregateCtors cmdName regsName ctorMap specs
```

Step 6 — fixture and assertions. Extend `test/Keiki/Generics/THSpec.hs`. Add (near the
other toy aggregates) a small command sum type with three constructors so we can show
one override, one default, and one exclude. Add the imports
`import qualified Data.Map.Strict as Map` and `import qualified Data.Set as Set` at the
top of the spec module if not present. For example:

```haskell
data OverData = OverData { oa :: Int }
  deriving (Eq, Show, Generic)

data OverCmd
  = LongCommandName OverData   -- overridden to short "Brief"
  | Plain OverData             -- default short "Plain"
  | Skipped                    -- excluded entirely
  deriving (Eq, Show, Generic)

type OverRegs = '[ '("oa", Int) ]

$(deriveAggregateCtorsWith ''OverCmd ''OverRegs
    defaultDeriveCtorOptions
      { suffixOverrides = Map.fromList [("LongCommandName", "Brief")]
      , excludeCtors    = Set.fromList ["Skipped"]
      })

overRegs :: RegFile OverRegs
overRegs = RCons (Proxy @"oa") 0 RNil
```

Then add assertions in `spec` proving: the overridden constructor produced
`inCtorBrief` whose `icName` is the *constructor* name `"LongCommandName"` (the splice
records the real constructor name internally; the short name only affects the
identifier), and that `inpBrief` / `isBrief` exist and behave; that the default
constructor produced `inCtorPlain`; and that the excluded constructor produced no helper
(this is verified by the fact that referencing `inCtorSkipped` would not compile —
state that as a comment, and assert positively that `isPlain` distinguishes `Plain`
from `LongCommandName`). For example:

```haskell
  describe "deriveAggregateCtorsWith (overrides + excludes)" $ do
    it "uses the override short name for the identifier" $
      icName inCtorBrief `shouldBe` "LongCommandName"

    it "matches and reads through the overridden helper" $
      evalTerm (inpBrief #oa) overRegs (LongCommandName (OverData 7))
        `shouldBe` 7

    it "defaults the non-overridden constructor to its own name" $
      icName inCtorPlain `shouldBe` "Plain"

    it "the override guard distinguishes the two record ctors" $ do
      evalPred isBrief overRegs (LongCommandName (OverData 0)) `shouldBe` True
      evalPred isBrief overRegs (Plain (OverData 0))           `shouldBe` False

    -- The excluded constructor 'Skipped' generates no helpers: there is
    -- no inCtorSkipped / isSkipped in scope. Referencing one would fail
    -- to compile, which is the intended behaviour.
```

Build and run (see Concrete Steps). Acceptance: `cabal build keiki` succeeds and
`cabal test keiki-test` reports the new `deriveAggregateCtorsWith` examples passing.


### Milestone 2 — event-side `deriveWireCtorsWith`, negative-case docs, optional dogfood

Scope: mirror M1 on the event side, record the compile-fail manual verification, and
optionally dogfood the new command splice in a worked example.

At the end of M2, `src/Keiki/Generics/TH.hs` also exports `DeriveWireOptions`,
`defaultDeriveWireOptions`, and `deriveWireCtorsWith`; the test suite exercises an event
aggregate through the new event splice; and this plan documents exactly how a
contributor can reproduce the two compile-time failures.

Step 1 — event options + shared codegen. Mirror M1 for the event side. The event side
has no register-file argument, so the options record can be a distinct type (to keep the
field names meaningful and the public API symmetrical):

```haskell
-- | Options for 'deriveWireCtorsWith'. Same semantics as
-- 'DeriveCtorOptions' but for the event side: 'suffixOverridesW' maps an
-- event constructor name to its short-name suffix (used for @wire<Short>@
-- and, for record-payload events, the @<Short>TermFields@ record);
-- 'excludeCtorsW' names event constructors to skip.
data DeriveWireOptions = DeriveWireOptions
  { suffixOverridesW :: Map String String
  , excludeCtorsW    :: Set String
  }

defaultDeriveWireOptions :: DeriveWireOptions
defaultDeriveWireOptions = DeriveWireOptions
  { suffixOverridesW = Map.empty
  , excludeCtorsW    = Set.empty
  }
```

Extract the shared event codegen exactly as in M1:

```haskell
genWireCtors :: Name -> [(String, Con)] -> [(String, String)] -> Q [Dec]
genWireCtors evtName ctorMap specs =
  fmap concat . mapM (genWire evtName ctorMap) $ specs
```

and rewrite `deriveWireCtors` and `deriveWireCtorsAll` to call it (preserving their
`reifyCtors` preamble). Then add the splice, reusing the *same* `resolveCtorSpecs`
helper from M1 (it is sum-type-agnostic):

```haskell
deriveWireCtorsWith :: Name -> DeriveWireOptions -> Q [Dec]
deriveWireCtorsWith evtName opts = do
  ctors <- reifyCtors evtName "deriveWireCtorsWith"
  let ctorMap  = [ (nameBase n, c) | c <- ctors, n <- conNames c ]
      allCtors = map fst ctorMap
  specs <- resolveCtorSpecs "deriveWireCtorsWith" allCtors
             (suffixOverridesW opts) (excludeCtorsW opts)
  genWireCtors evtName ctorMap specs
```

Add the three event-side names to the module export list.

Step 2 — event fixture + assertions. Extend `test/Keiki/Generics/THSpec.hs` with an
event sum type derived via `deriveWireCtorsWith` using one override and one exclude,
e.g.:

```haskell
data EvtData = EvtData { ea :: Int }
  deriving (Eq, Show, Generic)

data OverEvent
  = SomethingHappenedAtLength EvtData  -- override -> "Happened"
  | Routine EvtData                    -- default  -> "Routine"
  | Ignored                            -- excluded
  deriving (Eq, Show, Generic)

$(deriveWireCtorsWith ''OverEvent
    defaultDeriveWireOptions
      { suffixOverridesW = Map.fromList [("SomethingHappenedAtLength", "Happened")]
      , excludeCtorsW    = Set.fromList ["Ignored"]
      })
```

Assertions: `wcName wireHappened` is `"SomethingHappenedAtLength"`,
`wcBuild wireHappened (5, ())` rebuilds `SomethingHappenedAtLength (EvtData 5)`,
`wcName wireRoutine` is `"Routine"`, and (comment) `wireIgnored` does not exist.

Step 3 — negative-case manual verification (documentation only). See the dedicated
section "Negative cases (compile-fail) — manual verification" below. This step is to
write that section's snippets and confirm, by temporarily pasting each into the spec
module locally and running `cabal build keiki-test`, that the error text matches; then
remove the temporary splice so the suite stays green. Record the observed error text in
that section (and in Surprises & Discoveries if it differs from what is written here).

Step 4 — optional dogfood. Optionally, find an existing worked-example aggregate that
uses `deriveAggregateCtorsAll` or the explicit `deriveAggregateCtors` and migrate it to
`deriveAggregateCtorsWith` to demonstrate the drop-in. In this repository the
worked-example aggregates live in the test fixtures inside
`test/Keiki/Generics/THSpec.hs` (e.g. `AutoCmd` derived via `deriveAggregateCtorsAll`);
migrating one of those to `deriveAggregateCtorsWith defaultDeriveCtorOptions` and
confirming the suite still passes is sufficient to prove equivalence. Keep this change
additive and green; do not delete the existing `*All` coverage.


## Concrete Steps

All commands run from the repository root `/Users/shinzui/Keikaku/bokuno/keiki`.

Confirm the dependencies are already present (no cabal edit needed for `containers`):

```bash
grep -n containers keiki.cabal
grep -n template-haskell keiki.cabal
```

Expected: both appear in the library `build-depends`.

After M1 edits, build and test:

```bash
cabal build keiki
cabal test keiki-test
```

Expected (abbreviated): the build succeeds with no errors, and the test transcript
includes the new examples, e.g.:

```text
  deriveAggregateCtorsWith (overrides + excludes)
    uses the override short name for the identifier
    matches and reads through the overridden helper
    defaults the non-overridden constructor to its own name
    the override guard distinguishes the two record ctors
```

with the final summary line reporting `0 failures`.

After M2 edits, re-run the same two commands; the transcript additionally includes the
`deriveWireCtorsWith` examples and the suite still reports `0 failures`.


## Validation and Acceptance

Acceptance is behavioral and observable through the test suite. Concretely:

1. Build proves the new splices type-check and run at compile time:
   `cabal build keiki` succeeds. This alone demonstrates that
   `deriveAggregateCtorsWith` and `deriveWireCtorsWith` successfully generate
   declarations for the fixture aggregates (a splice that produced ill-typed code would
   fail the build).

2. Runtime assertions prove the *semantics* of overrides and excludes:
   `cabal test keiki-test` reports the new `deriveAggregateCtorsWith` and
   `deriveWireCtorsWith` examples passing. Specifically, the overridden constructor's
   helper is reachable under the abbreviated identifier (`inCtorBrief`,
   `wireHappened`), the non-overridden constructor keeps its own name (`inCtorPlain`,
   `wireRoutine`), and the excluded constructor produced no helper (asserted negatively:
   the spec module compiles only because it does not reference `inCtorSkipped` /
   `wireIgnored`; a comment records this).

3. Drop-in equivalence: for an overridden `(ctor, short)` pair, the generated
   declarations are identical to those `deriveAggregateCtors ''Cmd ''Regs
   [(ctor, short)]` would produce, because both route through the same `genCtor` path
   (Decision Log). The optional dogfood in M2 demonstrates this by migrating an
   existing `*All` fixture to `deriveAggregateCtorsWith defaultDeriveCtorOptions` with
   no behavioral change.

4. Negative acceptance is verified manually (see next section): each of the two error
   conditions aborts the splice at compile time with the documented message.


### Negative cases (compile-fail) — manual verification

These two cases must *fail to compile*. Because the keiki suite has no compile-fail
harness and is built on every `cabal build`, a permanently-failing splice cannot live
in the tree. To verify, a contributor temporarily pastes the snippet into
`test/Keiki/Generics/THSpec.hs`, runs `cabal build keiki-test`, observes the error,
then removes the snippet.

Case A — duplicate resolved short name. Two constructors resolve to the same short
name, which would generate two clashing `inCtor<Short>` top-level definitions. Paste:

```haskell
data DupData = DupData { da :: Int } deriving (Eq, Show, Generic)
data DupCmd = AlphaThing DupData | BetaThing DupData
  deriving (Eq, Show, Generic)
type DupRegs = '[ '("da", Int) ]

$(deriveAggregateCtorsWith ''DupCmd ''DupRegs
    defaultDeriveCtorOptions
      { suffixOverrides =
          Map.fromList [("AlphaThing", "Same"), ("BetaThing", "Same")] })
```

Expected compile error (text; the exact wording comes from `resolveCtorSpecs`):

```text
deriveAggregateCtorsWith: short name(s) { "Same" } are produced by more than one
constructor; rename via suffixOverrides or exclude one
```

Case B — unknown override/exclude key. An override (or exclude) names a constructor that
does not exist on the sum type (a typo). Paste:

```haskell
$(deriveAggregateCtorsWith ''DupCmd ''DupRegs
    defaultDeriveCtorOptions
      { suffixOverrides = Map.fromList [("Alfa Thing", "X")] })  -- typo
```

Expected compile error (text):

```text
deriveAggregateCtorsWith: option(s) name { "Alfa Thing" } which are not constructors
of this type; valid constructors: { "AlphaThing", "BetaThing" }
```

After confirming each message, delete the temporary snippet and re-run
`cabal build keiki-test` to confirm the suite is green again. Record the exact observed
text in Surprises & Discoveries if it differs from the above (GHC may wrap or prefix the
message with source location; the substring shown here must appear).

Verified 2026-06-06: both snippets were pasted into `test/Keiki/Generics/THSpec.hs`
one at a time and `cabal build keiki-test` was run. The observed GHC error text matched
the documented messages verbatim:

```text
deriveAggregateCtorsWith: short name(s) { "Same" } are produced by more than one constructor; rename via suffixOverrides or exclude one
```

```text
deriveAggregateCtorsWith: option(s) name { "Alfa Thing" } which are not constructors of this type; valid constructors: { "AlphaThing", "BetaThing" }
```

Both snippets were then removed; `cabal test keiki-test` reports 300 examples, 0
failures.


## Idempotence and Recovery

All edits are additive and safe to repeat. The shared-codegen refactor only moves an
expression into a named helper; if the build breaks after it, revert that single hunk
and re-apply. The fixture additions in `test/Keiki/Generics/THSpec.hs` are self-
contained new declarations and `it`-blocks; if a fixture name collides with an existing
one, rename the new fixture (the toy types in that file are deliberately uniquely
named). The negative-case snippets are temporary and must be removed before committing;
if one is accidentally left in, `cabal build keiki-test` will fail loudly and point at
the offending splice line, making recovery obvious. No data migrations, no destructive
operations, no state outside the working tree.


## Interfaces and Dependencies

Libraries: `template-haskell` (the `Q` monad, `reify`, `Name`, `Dec`, `Con`,
`nameBase`, `mkName`) and `containers` (`Data.Map.Strict`, `Data.Set`) — both already in
`keiki.cabal` library `build-depends`. No new dependency is added. The test suite
already depends on `hspec`; the fixtures need `containers` at the *spec* site too, but
the `keiki-test` stanza transitively has it through `keiki`; if `cabal build keiki-test`
reports `Data.Map.Strict` as not found, add `containers` to the `keiki-test`
`build-depends` (verify first with `grep -n 'build-depends' -A12 keiki.cabal` under the
`test-suite keiki-test` stanza).

Module touched: `src/Keiki/Generics/TH.hs` only (plus the test file
`test/Keiki/Generics/THSpec.hs`). This is the sole shared surface with MasterPlan 14;
no sibling ExecPlan (EP-55/56/58/59/60) edits this module, so this plan runs fully in
parallel.

Public interface that must exist at the end of each milestone (full module path
`Keiki.Generics.TH`):

End of M1:

```haskell
data DeriveCtorOptions = DeriveCtorOptions
  { suffixOverrides :: Data.Map.Strict.Map String String
  , excludeCtors    :: Data.Set.Set String
  }

defaultDeriveCtorOptions :: DeriveCtorOptions

deriveAggregateCtorsWith
  :: Language.Haskell.TH.Name      -- command sum type
  -> Language.Haskell.TH.Name      -- register-file slot list
  -> DeriveCtorOptions
  -> Language.Haskell.TH.Q [Language.Haskell.TH.Dec]
```

End of M2 (additionally):

```haskell
data DeriveWireOptions = DeriveWireOptions
  { suffixOverridesW :: Data.Map.Strict.Map String String
  , excludeCtorsW    :: Data.Set.Set String
  }

defaultDeriveWireOptions :: DeriveWireOptions

deriveWireCtorsWith
  :: Language.Haskell.TH.Name      -- event sum type
  -> DeriveWireOptions
  -> Language.Haskell.TH.Q [Language.Haskell.TH.Dec]
```

Shared internal helpers introduced (not exported): `genAggregateCtors`,
`genWireCtors`, `resolveCtorSpecs`.


## Git / Process

Use Conventional Commits and commit directly to the current branch (`master`); do not
create a feature branch. Suggested commits: one for M1 (e.g.
`feat(generics-th): add deriveAggregateCtorsWith with overrides and excludes`) and one
for M2 (e.g. `feat(generics-th): add deriveWireCtorsWith; document negative cases`).
Every commit must carry these trailers verbatim:

```text
MasterPlan: docs/masterplans/14-keiki-and-keiki-codec-json-dsl-improvements-surfaced-by-the-seihou-consumer-audit.md
ExecPlan: docs/plans/57-aggregate-ctor-derivation-with-per-constructor-suffix-overrides-and-excludes.md
Intention: intention_01ktensqv9ecmv5cd5jrbcfej7
```
