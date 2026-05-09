---
id: 23
slug: nothunks-instances-for-regfile-and-symtransducer-state
title: "NoThunks instances for RegFile and SymTransducer state"
kind: exec-plan
created_at: 2026-05-02T23:44:08Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
---

# NoThunks instances for RegFile and SymTransducer state

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

A long-running embedder (a service that holds a keiki aggregate
in memory across many command-handling cycles) accumulates state
in two places:

- The `RegFile rs` value carried inside `(s, RegFile rs)` — the
  "data" half of the transducer state.
- The control vertex `s` itself — usually a small enum, but
  potentially a `Composite s1 s2` produced by `Keiki.Composition.compose`
  for composite topologies.

If any field of `RegFile` or any `Composite` constructor accumulates
unevaluated thunks across `step` invocations, memory grows
without bound and `reconstitute` slows down — a classic
long-running-Haskell-service failure mode. crem ships `NoThunks`
instances for the same reason
(`docs/research/architecture-comparison-keiki-vs-crem.md`
lists this as a crem-vs-keiki gap under §"Production Readiness").

After this change, a keiki user embedding the library in a
long-running service can:

1. Add `nothunks` to their own dependency closure.
2. Wrap each `step` call's resulting state in
   `noThunks ["regfile", "vertex"] (s, regs)`.
3. Receive a structured `ThunkInfo` whenever a thunk leaks into
   the state — pinpointing the slot or constructor that needs
   a strict update.

This ExecPlan adds:

- `NoThunks` instances for `RegFile rs` (recursive on the slot
  spine, requiring `NoThunks r` for each slot value),
  `Composite s1 s2` (requiring `NoThunks s1` and `NoThunks s2`),
  and the small leaf types in `Keiki.Internal.Slots` /
  `Keiki.Core` that hold runtime data.
- A test (`test/Keiki/NoThunksSpec.hs`) that runs `noThunks`
  against `reconstitute`'s output for the canonical
  `UserRegistration` event log and asserts no thunks are
  reported.
- A new `NoThunks` build-dependency on `keiki.cabal`.

The user can verify this works by running `cabal test` — the
new spec passes only if every register-file slot and composite
vertex is forced before being returned by `reconstitute`. A
regression that accidentally introduces laziness in
`applyEdgeUpdate` (in `src/Keiki/Core.hs`) or in `compose`'s
substitution (in `src/Keiki/Composition.hs`) flips the spec to
red.

Excluded from scope: `NoThunks` on function-bearing types
(`Edge`, `SymTransducer`, `HsPred`, `Term`, `OutTerm`, `Update`).
These contain Haskell closures by construction; `nothunks`
cannot meaningfully inspect a function value, so adding
instances would either be vacuous or rely on the `OnlyCheckWhnf`
escape hatch — both add noise without value. The state types
are where the leak risk actually lives.


## Progress

- [x] M0 (2026-05-02): Verify prerequisites — `cabal build all`
      "Up to date"; `cabal test` "166 examples, 0 failures";
      GHC 9.12.3, cabal 3.16.1.0.
- [x] M1 (2026-05-02): Added `nothunks >= 0.3 && < 0.4` to
      `keiki.cabal`'s `library` and `test-suite keiki-test`
      `build-depends`. `nothunks-0.3.1` resolved cleanly; library
      rebuilt without errors.
- [x] M2 (2026-05-02): Added `NoThunks` instances for
      `RegFile '[]` and `RegFile ('(s, r) ': rs)` in a new
      module `src/Keiki/NoThunks.hs` (exported via
      `keiki.cabal`'s `exposed-modules`); added the
      `Composite` instance next to the type in
      `src/Keiki/Composition.hs`. Suppressed the expected
      orphan-instance warnings on `Keiki.NoThunks` with
      `-Wno-orphans` and a haddock comment pointing to the
      Decision Log.
- [x] M3 (2026-05-02): Created `test/Keiki/NoThunksSpec.hs`
      with the three required cases, plus a deepseq-forced
      `t` fixture (see Surprise §3) and a NOINLINE
      `leakySlotValue` (see Surprise §4). Added a test-side
      orphan `NoThunks Vertex` via `OnlyCheckWhnf`.
- [x] M4 (2026-05-02): Imported `Keiki.NoThunksSpec` in
      `test/Spec.hs` (alphabetically between
      `Keiki.Generics.THSpec` and `Keiki.SymbolicSpec`),
      added the matching `describe` line in `main`, and added
      `Keiki.NoThunksSpec` to `keiki.cabal`'s test-suite
      `other-modules`.
- [x] M5 (2026-05-02): `cabal test --test-show-details=streaming`
      reports `169 examples, 0 failures`; the new
      `Keiki.NoThunks` describe block has the three expected
      passing examples.


## Surprises & Discoveries

1. **`setSlotN` was lazy on both the value and the spine.**
   The plan asserted that "the new spec passes only if every
   register-file slot ... is forced before being returned by
   `reconstitute`", implying the existing pipeline already
   produced thunk-free state. It did not: the canonical-log
   replay at M5 reported a thunk at
   `["RegFile (s ': rs)","RCons.tail","RegFile (s ': rs)","regfile"]`,
   then `["UTCTime","RCons.value","RegFile (s ': rs)","RCons.tail",…]`
   after the first fix. Diagnosis: `setSlotN`'s value argument
   and recursive call were both lazy, and `RCons` stores its
   value field lazily by construction. The Decision Log entry
   "Strictness on the write path, not the constructor" describes
   the surgical fix.

2. **Bang-banging `RCons`'s value field broke 28 unrelated tests.**
   First attempt at fixing §1 was to add `!r` to the `RCons`
   constructor. That made `Keiki.Generics.emptyRegFile`'s
   sentinel pattern (`RCons (Proxy @s) (error "uninit: …") rest`)
   eagerly throw at construction time, bombing every spec that
   exercises an aggregate's initial state. Reverted, scoped the
   strictness to `setSlotN` only.

3. **`UTCTime`'s fields are lazy; `nothunks`'s `InspectHeap UTCTime`
   exposes that.** With the spine fixed, the canonical-log spec
   still reported a thunk inside the `registeredAt` slot's
   `UTCTime`. The bundled
   `deriving via InspectHeap UTCTime instance NoThunks UTCTime`
   walks the entire heap closure of the value, and `time-1.12`
   defines `data UTCTime = UTCTime { utctDay :: Day, utctDayTime :: DiffTime }`
   without bang-patterns — so even forcing the outer
   constructor to WHNF leaves the two fields as thunks. This is
   not a bug in keiki's pipeline; it is a property of `time`'s
   representation. Resolution: deep-force the test fixture's
   `t` helper via `Control.DeepSeq.force` (which uses `time`'s
   shipped `NFData UTCTime` instance), and add `deepseq` to the
   test-suite's `build-depends`. The library itself does not
   depend on `deepseq` — only the spec does.

4. **The plan's `(1 + 1) :: Int` thunk fixture is unreliable
   at -O1.** GHC's constant folder may evaluate it before the
   thunk is ever stored, leaving the sanity check unable to
   detect anything. Replaced with a top-level NOINLINE binding
   that returns `error "…"`; `nothunks` uses `ghc-heap`
   reflection (no force), so the thunk is detected without the
   error firing.

5. **`UserRegistration.Vertex` has no `NoThunks` instance and
   was never going to.** It is a user-defined nullary enum;
   the keiki library itself cannot ship instances for the
   user's domain types. Added a test-side orphan
   `deriving via OnlyCheckWhnf Vertex instance NoThunks Vertex`
   in `Keiki.NoThunksSpec` to demonstrate the canonical
   embedder pattern.

6. **`nothunks`'s license is Apache-2.0, not MIT.** Minor
   correction to the plan's "Interfaces and Dependencies"
   section.


## Decision Log

- Decision: Scope `NoThunks` to data-bearing state types
  (`RegFile`, `Composite`) only; skip function-bearing types
  (`Edge`, `SymTransducer`, `HsPred`, `Term`, `OutTerm`,
  `Update`).
  Rationale: `nothunks` cannot meaningfully inspect a Haskell
  closure. The state types are where leaks actually accumulate
  in long-running embedders; instances on the function-bearing
  types would either be vacuous or use `OnlyCheckWhnf`, both
  adding noise without value.
  Date: 2026-05-02

- Decision: Place the `RegFile` instance in a new module
  (`Keiki.NoThunks`) rather than inlining it next to the
  `RegFile` definition in `Keiki.Core`.
  Rationale: Adds the `nothunks` dependency to the library's
  closure, but keeps `Keiki.Core` focused on the transducer
  formalism without observability tooling. The `Composite`
  instance, by contrast, lives next to the type in
  `Keiki.Composition` because `Composite` is small and the
  instance is a one-liner.
  Date: 2026-05-02

- Decision: Strictness on the write path, not the constructor.
  Force the new value (`!v`) and the recursive spine call
  (`let !rest' = setSlotN i v rest in …`) inside `setSlotN`,
  rather than annotating `RCons`'s value field as `!r`.
  Rationale: A bang on the constructor field would force every
  `RCons` construction, including
  `Keiki.Generics.emptyRegFile`'s targeted sentinel pattern
  `RCons (Proxy @s) (error "uninit: …") rest`. That sentinel
  is the library's loud-failure mechanism for unread slots and
  is exercised by 28 existing tests; making it strict broke
  every one. Forcing on `setSlotN` instead achieves the
  long-running-service guarantee for all *written* slots while
  preserving the sentinel for unwritten slots. See Surprise §2.
  Date: 2026-05-02

- Decision: Add `deepseq` to the test-suite stanza only.
  Rationale: The `t` UTCTime fixture must be deep-forced before
  reconstitute so that `nothunks`'s `InspectHeap UTCTime` does
  not report (false-positive) thunks left by `time`'s lazy
  `UTCTime` fields. `Control.DeepSeq.force` is the cleanest
  realisation of that. The library itself does not need
  `deepseq` — slot values are forced to WHNF on the write path
  (sufficient for the keiki-internal regression-detection goal);
  deep-NF is only needed to dispel third-party-type false
  positives in the test. See Surprise §3.
  Date: 2026-05-02

- Decision: Add an orphan `NoThunks Vertex` via
  `OnlyCheckWhnf` in the test module rather than asking users
  to add a deriving in the example aggregate.
  Rationale: `Vertex` is a user-defined nullary enum in
  `Keiki.Examples.UserRegistration`; the keiki library cannot
  meaningfully ship instances for arbitrary user vertex types.
  The orphan in `Keiki.NoThunksSpec` is exactly the pattern a
  long-running embedder would use in their own module — small,
  scoped, and demonstrates the user-facing recipe.
  Date: 2026-05-02

- Decision: Reproduce the canonical event log inline in
  `Keiki.NoThunksSpec` rather than importing it from
  `Keiki.Examples.UserRegistrationSpec`.
  Rationale: The upstream `canonicalLog` is a private
  let-binding in another spec module's local scope. Coupling
  test modules to share a five-line literal would cost more
  than it saves; copying the literal is order-stable and
  trivially keeps both specs in sync.
  Date: 2026-05-02


## Outcomes & Retrospective

**What was delivered**

- New library module `src/Keiki/NoThunks.hs` exposing
  `NoThunks (RegFile '[])` and the inductive
  `NoThunks (RegFile ('(s, r) ': rs))` instances.
- New `NoThunks (Composite s1 s2)` instance next to the type
  in `src/Keiki/Composition.hs`.
- New test module `test/Keiki/NoThunksSpec.hs` (3 examples,
  all green).
- A surgical strictness fix in
  `src/Keiki/Core.hs:setSlotN`: bang the new value and the
  recursive spine. This is the change that makes the canonical
  log assertion live; without it, every `runUpdate` cycle
  accumulates thunks at the written slot.
- A new test-only dep on `deepseq ^>= 1.5` (no library impact).

**Acceptance verification** (M5)

`cabal test --test-show-details=streaming` reports
`169 examples, 0 failures`. The new `Keiki.NoThunks` describe
block has 3 passing examples (RNil, canonical-log replay,
deliberately-lazy sanity check). The 166 pre-existing examples
still pass.

**Regression detection is live.** Reverting either of:

- the bang-pattern on `setSlotN`'s value (`!v`), or
- the bang on the recursive call (`let !rest' = …`),

flips the canonical-log assertion to red, with a
diagnostic context pinpointing whether the leak is at
`RCons.value` (slot value) or `RCons.tail` (spine). The
sanity-check assertion always passes regardless, confirming
the detector itself is wired correctly.

**Three things were learned that the plan did not anticipate**

- The plan's framing assumed the existing pipeline already
  produced thunk-free state. It did not (Surprise §1). The
  test had to drive a real strictness fix, not just observe an
  existing invariant. This is a strictly *better* outcome —
  the plan delivered both the detector and the underlying fix.
- The same fix nearly broke the library by going too far
  (Surprise §2). Choosing where to put strictness — on the
  constructor vs. on the write path — was the substantive
  design decision. The Decision Log captures it.
- `nothunks`'s deep `InspectHeap` walk produces false
  positives for any user-defined slot type whose representation
  has lazy fields (Surprise §3). Long-running embedders will
  need `Control.DeepSeq.force` (or equivalent) on their state
  before the `noThunks` check, *or* they will need to use
  `OnlyCheckWhnf`-derived `NoThunks` instances on their own
  types. The test demonstrates both patterns.

**What an embedder should do**

After this plan, a service that holds a keiki aggregate in
memory across many command-handling cycles can:

1. Add `nothunks` (and optionally `deepseq`) to their own
   dependency closure.
2. Add a `NoThunks` instance for their vertex type — for a
   small enum, `deriving via OnlyCheckWhnf <Vertex> instance
   NoThunks <Vertex>` is the canonical one-liner.
3. Wrap each `step` call's result in
   `noThunks ["state"] (s', regs')`. If the slot types are
   third-party with lazy interiors (`UTCTime`, etc.),
   `evaluate (force regs')` first.
4. Receive `Just ThunkInfo` whenever a thunk leaks, with a
   structured context that names the offending slot or
   constructor.


## Context and Orientation

The keiki repository is a Haskell library at
`/Users/shinzui/Keikaku/bokuno/keiki`. The relevant files are:

- `src/Keiki/Core.hs` — defines `RegFile`,
  `SymTransducer`, `Edge`, `HsPred`, `Term`, `Update`,
  `applyEdgeUpdate`, `step`, `reconstitute`.
- `src/Keiki/Composition.hs` — defines `Composite s1 s2`
  (the composite-vertex newtype produced by `compose`).
- `src/Keiki/Internal/Slots.hs` — defines `IndexN`, `Names`,
  `Disjoint` (mostly type-level; runtime values are simple
  GADTs).
- `src/Keiki/Examples/UserRegistration.hs` — the canonical
  example aggregate used as a smoke test throughout the
  test suite. Defines `userReg :: SymTransducer (HsPred
  UserRegRegs UserCmd) UserRegRegs UserVertex UserCmd
  UserEvent` and a small canonical event log we can replay
  through `reconstitute`.
- `test/Spec.hs` — the test entry point. Each spec module
  is imported and dispatched in `main`.
- `keiki.cabal` — cabal file. Library deps live under the
  `library` stanza's `build-depends`; test deps under
  `test-suite keiki-test`'s `build-depends`.

`RegFile rs` is defined in `src/Keiki/Core.hs` (lines
118–122) as:

    data RegFile (rs :: [Slot]) where
      RNil  :: RegFile '[]
      RCons :: KnownSymbol s
            => Proxy s -> r -> RegFile rs -> RegFile ('(s, r) ': rs)

The `r` field on `RCons` is currently lazy. `applyEdgeUpdate`
(in `src/Keiki/Core.hs` near line 90+; see the export list)
uses pattern-matching to thread a new value through, but Haskell
will not force the `r` until something projects it via `(!)`.
A long-running service that updates a slot N times before ever
reading it accumulates N thunks in that slot. That is exactly
the failure mode `NoThunks` exists to detect.

`Composite s1 s2` is defined in `src/Keiki/Composition.hs`
(lines 62–63) as a strict pair:

    data Composite s1 s2 = Composite !s1 !s2

The constructor uses bang patterns, so the components are
WHNF-strict by construction. The `NoThunks` instance is
therefore a one-liner that delegates to the underlying
instances of `s1` and `s2`.

`nothunks` is the Hackage package that ships the `NoThunks`
typeclass. The class signature is:

    class NoThunks a where
      noThunks       :: Context -> a -> IO (Maybe ThunkInfo)
      wNoThunks      :: Context -> a -> IO (Maybe ThunkInfo)
      showTypeOf     :: Proxy a -> String

`noThunks` walks the data structure and returns `Nothing` if
no thunks are found, or `Just ThunkInfo` describing the first
thunk encountered. The walk is in `IO` because it uses
`Heap`-level reflection; the action is otherwise pure (no
state, no exceptions in the happy path).

The package has been on Hackage since 2020 and is a transitive
dependency of `cardano-base` and other long-running-service
Haskell stacks. Version `0.3.x` is current.


## Plan of Work

### M0: Verify prerequisites

Confirm the working tree is in a known-good state. The expected
test count is 166 examples; the expected GHC version is 9.12.x
(per `keiki.cabal`'s `tested-with` field).

### M1: Add `nothunks` to `keiki.cabal`

Edit `keiki.cabal`. Add `nothunks` to the `library` stanza's
`build-depends` and to the `test-suite keiki-test` stanza's
`build-depends`. The version range to pin is `>= 0.3 && < 0.4`
(matches the current Hackage release line).

After the edit, the relevant lines under `library` should
look like:

    build-depends:      base ^>= 4.21,
                        nothunks >= 0.3 && < 0.4,
                        sbv >= 11.7 && < 15,
                        template-haskell ^>= 2.23,
                        text ^>= 2.1,
                        time ^>= 1.12

and analogously for `test-suite keiki-test`.

Run `cabal build all`. If `nothunks` is not yet in the
`mori`-managed dependency set, the build will fail at the
plan-resolution step with a "no plan" error; in that case run
`cabal update` first and re-attempt.

### M2: Add `NoThunks` instances

Create `src/Keiki/NoThunks.hs`:

    {-# LANGUAGE FlexibleInstances #-}
    {-# LANGUAGE GADTs             #-}
    -- | NoThunks instances for keiki state types.
    --
    -- Long-running embedders that keep aggregate state in
    -- memory across many @step@ calls can wrap each step's
    -- resulting state in @noThunks ["regfile", "vertex"] (s,
    -- regs)@ to detect leaked thunks before they accumulate.
    --
    -- Scope is intentionally narrow: data-bearing state types
    -- only ('RegFile', 'Composite'). Function-bearing types
    -- ('Edge', 'SymTransducer', 'HsPred', 'Term', 'OutTerm',
    -- 'Update') are excluded — 'NoThunks' cannot meaningfully
    -- inspect Haskell closures, so instances would be vacuous.
    module Keiki.NoThunks () where

    import NoThunks.Class (NoThunks (..), allNoThunks)
    import Keiki.Core (RegFile (..))

    instance NoThunks (RegFile '[]) where
      showTypeOf _ = "RegFile '[]"
      wNoThunks _   RNil = pure Nothing

    instance (NoThunks r, NoThunks (RegFile rs))
          => NoThunks (RegFile ('(s, r) ': rs)) where
      showTypeOf _ = "RegFile (s ': rs)"
      wNoThunks ctx (RCons _proxy r rest) = allNoThunks
        [ noThunks ("RCons.value" : ctx) r
        , noThunks ("RCons.tail"  : ctx) rest
        ]

The `_proxy` argument of `RCons` is a `Proxy s` (a phantom
witness of the slot symbol). It carries no runtime data; we
ignore it in the thunk check.

Add the matching instance for `Composite` next to its
definition in `src/Keiki/Composition.hs` (right after the
`Bounded` and `Enum` instances near line 87):

    instance (NoThunks s1, NoThunks s2) => NoThunks (Composite s1 s2) where
      showTypeOf _ = "Composite"
      wNoThunks ctx (Composite a b) = allNoThunks
        [ noThunks ("Composite.left"  : ctx) a
        , noThunks ("Composite.right" : ctx) b
        ]

Add `import NoThunks.Class (NoThunks (..), allNoThunks)` to the
top of `src/Keiki/Composition.hs`.

Add the new `Keiki.NoThunks` module to the `exposed-modules`
list in `keiki.cabal`'s `library` stanza, in alphabetical
order (it lands between `Keiki.Internal.Slots` and
`Keiki.Symbolic`).

### M3: Create the spec module

Create `test/Keiki/NoThunksSpec.hs`:

    {-# LANGUAGE OverloadedStrings #-}
    module Keiki.NoThunksSpec (spec) where

    import Test.Hspec
    import NoThunks.Class (noThunks)
    import Keiki.NoThunks ()
    import Keiki.Core (RegFile (..), reconstitute)
    import Keiki.Examples.UserRegistration
      ( userReg
      , canonicalLog       -- the example log used by other tests
      )
    import Data.Proxy (Proxy (..))

    spec :: Spec
    spec = describe "NoThunks instances" $ do

      it "RNil contains no thunks" $ do
        result <- noThunks [] RNil
        result `shouldBe` Nothing

      it "reconstitute on the canonical UserRegistration log returns thunk-free state" $ do
        let Just (s, regs) = reconstitute userReg canonicalLog
        sResult    <- noThunks ["vertex"]  s
        regsResult <- noThunks ["regfile"] regs
        (sResult, regsResult) `shouldBe` (Nothing, Nothing)

      it "a deliberately-lazy RegFile reports a thunk (sanity check)" $ do
        let leaky :: RegFile '[ '("x", Int) ]
            leaky = RCons (Proxy @"x") (1 + 1) RNil   -- unevaluated thunk
        result <- noThunks ["leaky"] leaky
        case result of
          Just _  -> pure ()                          -- thunk detected — good
          Nothing -> expectationFailure "expected NoThunks to detect the unevaluated (1 + 1)"

If `Keiki.Examples.UserRegistration` does not export a
`canonicalLog` value with the right shape, name the actual log
used by `Keiki.Examples.UserRegistrationSpec` and import it
the same way that file does. The point is to use any
already-validated event sequence from the existing test suite,
not to author a new one in this plan.

### M4: Wire into the test runner

Edit `test/Spec.hs`. Add the import:

    import qualified Keiki.NoThunksSpec

near the other `Keiki.*Spec` imports, and add the dispatch:

    describe "Keiki.NoThunks"                            Keiki.NoThunksSpec.spec

inside `main`'s `hspec $ do` block, in the same alphabetical
position the other `Keiki.*` (non-`Examples`) specs occupy.

Add `Keiki.NoThunksSpec` to `keiki.cabal`'s `test-suite
keiki-test` `other-modules` list, in alphabetical order
(between `Keiki.Generics.THSpec` and `Keiki.SymbolicSpec`).

### M5: Run the full test suite

Run `cabal test --test-show-details=streaming` and confirm:

- The new `Keiki.NoThunks` spec passes (3 examples).
- The pre-existing 166 examples still pass.
- Total: 169 examples, 0 failures.

If z3 is not in `PATH`, the symbolic specs will fail with a
"z3 binary not found" error; in that case rerun under
`nix-shell -p z3 --run "cabal test"` per the convention
documented in MP-3 / MP-4 / MP-6's Surprises sections.


## Concrete Steps

The exact commands, run from `/Users/shinzui/Keikaku/bokuno/keiki`:

    cabal build all                           # M0 baseline; expect "Up to date" or successful build
    # edit keiki.cabal per M1
    cabal build all                           # M1 verification
    # create src/Keiki/NoThunks.hs per M2
    # edit src/Keiki/Composition.hs per M2
    # edit keiki.cabal exposed-modules per M2
    cabal build all                           # M2 verification
    # create test/Keiki/NoThunksSpec.hs per M3
    # edit test/Spec.hs and keiki.cabal per M4
    cabal test --test-show-details=streaming  # M5 verification

Expected output at M5:

    Finished in <T> seconds
    169 examples, 0 failures
    Test suite keiki-test: PASS


## Validation and Acceptance

The plan is complete when, run from
`/Users/shinzui/Keikaku/bokuno/keiki`:

    cabal test --test-show-details=streaming

reports "169 examples, 0 failures" and the new
`Keiki.NoThunks` describe block contains exactly three
passing examples: the `RNil` case, the canonical-log
reconstitution case, and the deliberately-lazy sanity check.

Beyond test counts: a regression that accidentally introduces
laziness in `applyEdgeUpdate` (e.g. by replacing a strict
field update with a non-strict one) must flip the canonical-log
spec to red. A reviewer can confirm this by editing
`src/Keiki/Core.hs`'s `applyEdgeUpdate` to deliberately
introduce a `let leaky = ... in ...` instead of a strict
binding, re-running the test, and observing the spec fail.


## Idempotence and Recovery

Every step in this plan is safe to repeat:

- The cabal-file edits are idempotent (re-running `cabal
  build all` after the same edit succeeds).
- The new module / spec files are created once; subsequent
  runs of M2 / M3 are safe re-edits.
- The test-runner wiring in M4 is order-stable; re-applying
  the same edit produces the same `test/Spec.hs`.

If `cabal build all` fails at M1 with "no plan", run
`cabal update` and retry. Do not pin `nothunks` to a specific
release older than `0.3` without first checking that the
`NoThunks` typeclass shape (`wNoThunks`, `allNoThunks`,
`showTypeOf`) matches what M2's instances assume.

If the M5 `cabal test` run reports a pre-existing test
failure (i.e. one of the 166 prior tests fails) rather than a
new-spec failure, that is a separate bug — do not amend this
plan to "fix" it. Open a follow-up; this plan's acceptance
criterion is "the new spec passes and the prior 166 still
pass". A pre-existing flake (likely `Keiki.SymbolicSpec`
without z3 in `PATH`) is the most common cause; rerun under
the `nix-shell -p z3` workaround.


## Interfaces and Dependencies

**New library dependency:** `nothunks >= 0.3 && < 0.4`. Hackage
package, MIT-licensed. Maintained by IOG / Cardano team. Used
by `cardano-base`, `cardano-ledger`, and several other
long-running-service Haskell stacks.

**New library module:** `Keiki.NoThunks`. Imports
`NoThunks.Class` and `Keiki.Core`. Exports nothing (the
instances themselves are the API). Adds the `nothunks`
dependency to anyone importing `Keiki.NoThunks`.

**Modified library module:** `Keiki.Composition`. New import
of `NoThunks.Class`. New `NoThunks` instance for
`Composite s1 s2`.

**New test module:** `Keiki.NoThunksSpec`. Imports
`NoThunks.Class`, `Keiki.NoThunks` (for the instances),
`Keiki.Core`, and `Keiki.Examples.UserRegistration`.

**Function signatures introduced:** none beyond the typeclass
instances themselves. The `NoThunks` typeclass is:

    class NoThunks a where
      noThunks   :: Context -> a -> IO (Maybe ThunkInfo)
      wNoThunks  :: Context -> a -> IO (Maybe ThunkInfo)
      showTypeOf :: Proxy a -> String

The instances added by this plan are:

    instance NoThunks (RegFile '[])
    instance (NoThunks r, NoThunks (RegFile rs))
          => NoThunks (RegFile ('(s, r) ': rs))
    instance (NoThunks s1, NoThunks s2)
          => NoThunks (Composite s1 s2)
