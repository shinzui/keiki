---
id: 48
slug: n-ary-event-family-codec-composition-and-singleton-event-support
title: "N-ary event-family codec composition and singleton-event support"
kind: exec-plan
created_at: 2026-05-21T22:59:23Z
intention: "intention_01ks6ber3jedc8ff6zzma2jr53"
master_plan: "docs/masterplans/13-keiki-api-improvements-surfaced-by-the-rei-migration.md"
---

# N-ary event-family codec composition and singleton-event support

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

This plan removes two papercuts that the Rei migration hit when it tried to model a single
event stream that legitimately carries several *event families*, and when one of those
families had a payload-free (singleton) event.

A bit of vocabulary first, because the rest of the plan leans on it.

An *event family* here means one closed Haskell sum type of events that already has its
codec derived — for example a type `OrderEvent = OrderPlaced OrderPlacedData | OrderShipped
OrderShippedData` together with the `wireOrderPlaced`, `wireOrderShipped` values that
`deriveWireCtors` (in `src/Keiki/Generics/TH.hs`) produced for it. A *codec* in keiki is the
pair of total functions that pack a value into a wire constructor and match it back out; it
lives in the record type `WireCtor co fields` in `src/Keiki/Core.hs` (field `wcName ::
String`, `wcMatch :: co -> Maybe fields`, `wcBuild :: fields -> co`). "Wire" is keiki's word
for the on-stream event representation: the `co` type parameter is the user's *output*
alphabet (the events a transducer emits), and a `WireCtor co fields` is a tag for one
constructor of that `co` sum, knowing how to recognise it (`wcMatch`) and how to rebuild it
(`wcBuild`).

Today, if a stream must carry *two* families, you can sum them with keiki's existing binary
machinery: `alternative` (in `src/Keiki/Composition.hs`) builds a transducer whose output is
`Either co1 co2`, and the helpers `leftWireCtor`/`rightWireCtor` lift a `WireCtor co1 fs` or
`WireCtor co2 fs` into a `WireCtor (Either co1 co2) fs`. But there is no documented way to do
this for *N* families at once, and nesting `Either`s by hand is fiddly and undocumented. Rei
faced exactly this with roughly 48 event constructors spread across many families, and
because it could not find a clean N-way sum, it hand-unified everything into one giant flat
`IntentionRootEvent` sum — losing the per-family modularity that `deriveWireCtors` was meant
to give it.

Separately, `deriveWireCtors` outright rejects a zero-argument event constructor (a
*singleton* event — one with no payload, e.g. `data DoorEvent = Opened | Closed`). The
command side already supports this through `mkInCtor0` (in `src/Keiki/Generics.hs`) and the
`Just Nothing` arm of `genCtor`, but the event side has no equivalent, so a perfectly normal
payload-free event cannot be derived.

After this change, a keiki user can:

1. Take N already-derived event families and obtain, with a small documented combinator, the
   injectors that re-home each family's `WireCtor`/`InCtor`/output-term machinery into one
   summed output alphabet — without writing a flat union by hand and without losing the
   per-family derivation. A transducer whose output type is that sum can build an event
   belonging to family *k*, and `solveOutput` (in `src/Keiki/Core.hs`) can invert that event
   straight back to the command that produced it, family by family.

2. Run `deriveWireCtors` over an event sum that contains a zero-argument constructor and get
   a working `WireCtor` for it, exactly as a singleton command already works.

You will be able to *see* this working: a new test assembles a multi-family output alphabet
from two independently-derived families, builds an event in each family, inverts it with
`solveOutput`, and asserts the original command comes back; a second test derives a singleton
event and round-trips it; a third asserts the name-uniqueness obligation (defined below) is
honoured. The acceptance commands are in Validation and Acceptance.

What is explicitly **not** in this plan: auto-deriving positional multi-argument command
constructors. That was the other half of the same Rei finding and was rejected at the
MasterPlan level (`docs/masterplans/13-keiki-api-improvements-surfaced-by-the-rei-migration.md`,
Decision Log entry dated 2026-05-21 for "Rei keiki #2") because keiki's symbolic alphabet
projects fields *by name* and positional arguments have no names. Do not plan or implement
it here.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] M1 (2026-05-21): Confirmed the **right-nested `Either`** representation via a ghci
  prototype (`cabal repl keiki`): for a 3-family sum `Either co1 (Either co2 co3)`, family
  *k* injects via `rightWireCtor^(k-1) . leftWireCtor` (last family `rightWireCtor^(N-1)`).
  Verified `wcBuild inj_k () == {Left "A", Right (Left "B"), Right (Right "C")}`, that
  `wcMatch inj2` accepts only `Right (Left "B")` and rejects the other arms, and that names are
  preserved. All six binary lifts (`leftInCtor`/`rightInCtor`/`leftWireCtor`/`rightWireCtor`/
  `liftLOutAlt`/`liftROutAlt`) are already exported from `Keiki.Composition` — no new exports
  needed for the primitives. Decision: ship fixed-arity-3 convenience injectors composed from
  the exported binary lifts + document the general N recipe; no type-indexed witness (see
  Decision Log).
- [x] M2 (2026-05-21): Added a new `-- * N-ary coproduct injectors (EP-48)` section to
  `src/Keiki/Composition.hs` with the arity-3 injectors `wireCtor3At{1,2,3}`,
  `inCtor3At{1,2,3}`, `outTerm3At{1,2,3}` — each a composition of the already-exported binary
  lifts (`leftWireCtor`/`rightWireCtor`, `leftInCtor`/`rightInCtor`, `liftLOutAlt`/`liftROutAlt`),
  with haddock stating the general N recipe and the name-uniqueness obligation. `alternative`
  and the binary lifts untouched; no new `unsafeCoerce`; `Keiki.Core` untouched. `cabal build
  keiki` clean.
- [x] M3 (2026-05-21): Singleton-event support — added `mkWireCtor0 :: Eq co => String -> co ->
  WireCtor co ()` in `src/Keiki/Generics.hs` (exported, mirroring `mkInCtor0`) and a `Just
  Nothing` arm in `genWire` (`src/Keiki/Generics/TH.hs`) emitting `wire<Short> = mkWireCtor0
  "<Ctor>" <Ctor>` with NO `<Short>TermFields` record; narrowed the catch-all `fail` to the
  `Nothing` (multi-arg/record) case so it no longer claims singletons are unsupported. Existing
  single-record events unchanged. `cabal build keiki` clean.
- [x] M4 (2026-05-21): Added `test/Keiki/CompositionNarySpec.hs` (registered in `keiki.cabal`
  `other-modules` and `test/Spec.hs`) with three groups: multi-family round-trip through
  `solveOutput` (family 1 and family 2, plus a wrong-arm rejection); `icName`/`wcName`
  uniqueness (injected names pairwise-distinct + a colliding-alphabet caught by the nub check);
  and singleton-event round-trip (`deriveWireCtors` over zero-arg ctors + `solveOutput` inverts
  the singleton event to its command). Added §8.7 "Summing N event families (EP-48)" to
  `docs/guide/composition.md`. `cabal test all` green (keiki-test 253→260, 0 failures).


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- **The implementation matched the plan with no surprises (2026-05-21).** All six binary lifts
  were already exported, so the N-ary injectors are pure point-free compositions
  (`outTerm3At2 = liftROutAlt . liftLOutAlt`, etc.); GHC inferred the intermediate `Either`
  nests from each helper's top-level signature with no ambiguity and no `unsafeCoerce`. The
  ghci M1 prototype's prediction (family *k* = `rightX^(k-1) . leftX`) held verbatim.
- **The name-collision obligation is hard to trigger as a *silent* mis-inversion in a unit
  test, so it was made executable via the uniqueness check itself.** Rather than fabricate a
  mis-inverting `unsafeCoerce` scenario, the test asserts that a colliding-name alphabet
  (two families both naming a ctor `"Dup"`) is *caught* by the `nub`-based uniqueness check
  (`length names /= length (nub names)`), which is the practical guard a consumer would run.
  This documents the obligation without depending on undefined-behaviour specifics.


## Decision Log

Record every decision made while working on the plan.

- Decision: Generalize keiki's existing binary `Either`-coproduct codec machinery rather
  than teach `deriveWireCtors` (in `src/Keiki/Generics/TH.hs`) to accept nested (two-level)
  sum types directly.
  Rationale: a `WireCtor co fields` is a product of total functions over the sum `co`, and
  lifting one across a coproduct is *exactly* what `leftWireCtor`/`rightWireCtor` (in
  `src/Keiki/Composition.hs`, ~510–529) already do. Adding nested-sum handling to the TH
  reifier would re-implement, in `Q`-monad metaprogramming, what is already a handful of
  pure value-level functions — and it would couple the codec story to the shape of the
  user's Haskell sum, whereas the coproduct lifts are agnostic to it. This is design-aligned
  with `docs/masterplans/13-keiki-api-improvements-surfaced-by-the-rei-migration.md`
  (Decision Log, "Rei keiki #2", 2026-05-21: "The multi-family ask is design-aligned: it
  generalizes the existing `leftWireCtor`/`rightWireCtor`/`alternative` coproduct
  machinery") and with the design discussion in `docs/research/keiki-generics-design.md`.
  Date: 2026-05-21

- Decision: Recommend the *balanced-`Either`* representation for the N-ary sum (a
  right-nested or balanced chain of `Either`s, with the per-arm injector built by composing
  the shipped `leftWireCtor`/`rightWireCtor` lifts the right number of times) over emitting
  a fresh generated N-ary sum type. The final, recorded choice is made at M1.
  Rationale: the balanced-`Either` path reuses functions that are already shipped, tested,
  and exercised by `alternative` and `CompositionAlternativeSpec`. A generated N-ary sum
  would need its own `Generic`-style match/build, its own AST re-tag lifts, and its own
  test surface — strictly more new code for no semantic gain. The only cost of the
  `Either` chain is that the user's output type becomes a nest of `Either`s; that is a
  documentation concern, not a correctness one, and is addressed by the type aliases the
  combinator helper produces. M1 confirms this against a concrete two- and three-family
  prototype before M2 commits to it.
  Date: 2026-05-21

- Decision: Singleton-event support is purely additive: a new `mkWireCtor0` helper in
  `src/Keiki/Generics.hs` (mirroring `mkInCtor0`, ~156–161) plus a new arm in `genWire` (in
  `src/Keiki/Generics/TH.hs`, ~372–392) handling the `Just Nothing` payload classification.
  Existing single-record events go through the unchanged `Just (Just payTy)` arm.
  Rationale: the command side already solved this exact problem the same way
  (`genCtor`'s `Just Nothing` arm calls `singletonDecls`, which emits `mkInCtor0`); copying
  that structure on the event side keeps the two splices symmetric and touches nothing that
  works today.
  Date: 2026-05-21

- Decision (M1, 2026-05-21): The N-ary sum is the **right-nested `Either`** chain, and the
  injectors are **compositions of the already-exported binary lifts** — confirmed by ghci
  prototype. Ship fixed-arity-**3** convenience wrappers (`wireCtor3At{1,2,3}`,
  `inCtor3At{1,2,3}`, `outTerm3At{1,2,3}`) as the worked common case beyond the binary
  `alternative`, plus haddock stating the general recipe (family *k* of *N* =
  `rightX^(k-1) . leftX`, last family `rightX^(N-1)`). Do **not** introduce a type-indexed
  `Nat`/selector witness.
  Rationale: the binary lifts already do all the work and are exported and tested; a generic
  type-indexed injector would need a type family for the sum, a Peano fold, and its own proof
  surface — strictly more code for no semantic gain, which the plan's own M2 guidance flagged
  as the fallback only "if the manual composition [is] too error-prone." The prototype showed
  the composition is neither error-prone nor type-ambiguous. Arity-3 wrappers cover the
  realistic case (Rei's families) and the recipe covers higher N by one more `rightX`. No new
  `unsafeCoerce`; `src/Keiki/Core.hs` untouched.
  Date: 2026-05-21

- Decision: Auto-derivation of positional multi-argument command constructors is explicitly
  out of scope.
  Rationale: rejected upstream in
  `docs/masterplans/13-keiki-api-improvements-surfaced-by-the-rei-migration.md` (Decision
  Log, 2026-05-21) — the symbolic alphabet projects fields by name (`InCtor`'s `ifs ::
  [Slot]` are `(Symbol, Type)` pairs) and positional arguments have no names.
  Date: 2026-05-21


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

**Outcome (2026-05-21): complete, all four milestones landed.** Against the original purpose —
sum N already-derived event families into one alphabet without a hand-written flat union, and
derive singleton events — the result is:

- `Keiki.Composition` exports arity-3 coproduct injectors (`wireCtor3At{1,2,3}`,
  `inCtor3At{1,2,3}`, `outTerm3At{1,2,3}`) composed from the existing binary lifts, with
  haddock giving the general N recipe; `solveOutput` inverts a summed event in any family back
  to its command (tested for families 1 and 2).
- `deriveWireCtors` now derives zero-arg (singleton) events via the new `mkWireCtor0` +
  `genWire` arm, mirroring the command side's `mkInCtor0`; round-trip tested.
- The name-uniqueness obligation is stated in haddock and docs and made executable in the test.
- `docs/guide/composition.md` §8.7 documents the feature.

**Validation:** `cabal test all` green; keiki-test grew 253→260 (the 7 new examples), 0 failures.
The binary `alternative` and all existing lifts/derivations are untouched; `Keiki.Core` is
untouched; no new `unsafeCoerce`.

**Gaps / lessons:**
- The deliverable is fixed-arity-3 convenience wrappers + a documented general recipe, not a
  type-indexed N-ary witness (recorded decision). This covers the realistic consumer case
  (Rei's families) cheaply; a consumer with N>3 composes one more `right…` per the documented
  recipe. If a future consumer repeatedly needs large N, a type-level `Nat`-indexed injector is
  the natural follow-up — but it was correctly judged more code for no semantic gain here.
- The string-equality name match in `solveOutput`/`stepOne` remains the one real correctness
  obligation; this plan enforces it by contract + test, and EP-47 (which reasons about the same
  site) does not change it — so the two stayed independent as designed.


## Context and Orientation

This section assumes you have never seen this repository. Read it fully before editing
anything. Every file is named by its full path from the repository root,
`/Users/shinzui/Keikaku/bokuno/keiki`.

keiki is a pure-Haskell library for *symbolic-register transducers* — a formalism for
event-sourced aggregates. The one fact you must internalise is keiki's central guarantee:
the user never writes the event→state replay function (`apply`). keiki *derives* it by
*inverting* each transducer edge's output term — recovering the command that produced an
observed event. The function that does the inversion is `solveOutput`, in
`src/Keiki/Core.hs`. Everything in this plan exists so that inversion keeps working when
the output alphabet is a sum of many event families and when an event has no payload.

### The codec types you will touch (`src/Keiki/Core.hs`)

The library models the *output alphabet* (the events a transducer emits) as a Haskell sum
type, conventionally called `co`. For each constructor of `co` there is a `WireCtor`:

    data WireCtor co fields = WireCtor
      { wcName  :: String
      , wcMatch :: co -> Maybe fields
      , wcBuild :: fields -> co
      }

(declared around line 404). `wcName` is the constructor's name as a string; `wcMatch`
returns `Just` the constructor's fields iff the observed `co` value is *that* constructor;
`wcBuild` is its inverse, building the `co` value from a field tuple. The `fields` type is a
right-nested pair tuple, e.g. a three-field record becomes `(f1, (f2, (f3, ())))`; the type
family `FieldsOf` in `src/Keiki/Generics.hs` computes it from the record type.

The dual on the *input* side is `InCtor`:

    data InCtor ci (ifs :: [Slot]) where
      InCtor
        :: (AssembleRegFile ifs, KnownSlotNames ifs)
        => { icName  :: String
           , icMatch :: ci -> Maybe (RegFile ifs)
           , icBuild :: RegFile ifs -> ci
           }
        -> InCtor ci ifs

(declared around line 297). `ci` is the *input* alphabet (the commands a transducer
consumes); `ifs :: [Slot]` is the constructor's named field list, where a `Slot` is a
`(Symbol, Type)` pair — that is, fields are projected *by name*. `icMatch` recognises the
named command and projects its fields into a `RegFile` (a typed, slot-keyed record);
`icBuild` is the left inverse.

An edge's output is built from `OutTerm`/`OPack`:

    data OutTerm (rs :: [Slot]) (ci :: Type) (co :: Type) where
      OPack :: InCtor ci ifs
            -> WireCtor co fields
            -> OutFields rs ci fields
            -> OutTerm rs ci co

(declared around line 442–454). An `OPack` ties together: the input constructor the edge
consumes (`InCtor ci ifs`), the output wire constructor it produces (`WireCtor co fields`),
and one `Term` per field of that wire constructor (`OutFields rs ci fields`). A `Term rs ci
r` is the small pure expression language for field values; the constructor that matters for
inversion is `TInpCtorField :: InCtor ci ifs -> Index ifs r -> Term rs ci r`, which reads
field `r` of the input command. `OutFields` is just an HList of `Term`s
(`OFNil`/`OFCons`, ~414–418).

### The inversion site and the one real correctness obligation

`solveOutput` (around line 1039) inverts an `OPack`:

    solveOutput :: OutTerm rs ci co -> RegFile rs -> co -> Maybe ci
    solveOutput (OPack ic@InCtor{} ctor fields) _regs co = do
      fs_obs  <- wcMatch ctor co
      entries <- gatherInpEntries fields fs_obs ic
      rf      <- assemble entries
      pure (icBuild ic rf)

It calls `wcMatch ctor co` to peel the observed event back to its field tuple, then walks the
`OutFields` against that tuple gathering `(Index, value)` pairs (`gatherInpEntries`,
~1054–1071), assembles a `RegFile`, and rebuilds the command via `icBuild`.

The single subtle thing — and the *one real correctness obligation this plan must design
and test* — lives in `gatherInpEntries`'s helper `stepOne` (~1063–1071):

    stepOne (TInpCtorField ic2 ix) val ic1
      | icName ic1 == icName ic2 = Just [ByIndex (unsafeCoerce ix) val]
      | otherwise                = Nothing

The match is by **`icName` string equality**, and the index is then `unsafeCoerce`d into the
ambient slot-list type. The same string-keyed grouping happens in `checkHiddenInputs` (the
build-time analysis, ~1084–1100, "groups the `OPack`s by `InCtor` name (via `icName`)"). The
implication for *this* plan: when you sum N event families into one output alphabet, every
`icName` and every `wcName` across the summed families **must be unambiguous** — two distinct
constructors in two distinct families that happen to share a constructor-name string would
collide under this string equality and silently mis-invert (the `unsafeCoerce` makes it a
correctness bug, not a type error). This precondition is *vacuously* satisfied today by
`alternative` because each binary arm keeps its own `ci`/`co` type and the `Either` wrapper
disambiguates structurally at the match step (`leftWireCtor`'s `wcMatch` only fires on `Left
_`). The N-ary generalization preserves that structural disambiguation — but the plan must
still *state and test* the name-uniqueness obligation, because the moment a user reaches past
the combinator and hand-builds `OPack`s over a summed alphabet, the `icName`/`wcName`
strings are the only thing keeping families apart. EP-47 (a sibling plan,
`docs/plans/47-recompute-and-verify-derived-event-outputs-in-solveoutput-replay.md`) reasons
about this same string-equality site but does not change it; this plan owns enforcing and
testing the uniqueness across summed families.

### The binary coproduct machinery you will generalize (`src/Keiki/Composition.hs`)

This file already contains the complete binary version of what M1/M2 generalize. The
relevant symbols, by line:

- `leftInCtor :: InCtor ci1 ifs -> InCtor (Either ci1 ci2) ifs` and `rightInCtor` (~485–504):
  re-home an input constructor into an `Either` input alphabet. `leftInCtor`'s `icMatch`
  fires only on `Left _`; its `icBuild` wraps in `Left`.
- `leftWireCtor :: WireCtor co1 fs -> WireCtor (Either co1 co2) fs` and `rightWireCtor`
  (~510–529): the exact event-side analogues. `leftWireCtor`'s `wcMatch` fires only on `Left
  _`; its `wcBuild` is `Left . wcBuild`.
- The AST re-taggers that walk a `Term`/`HsPred`/`Update`/`OutFields`/`OutTerm` and adjust
  every embedded `InCtor`/`WireCtor`: `liftLTermAlt`/`liftRTermAlt` (~536–561),
  `liftLPredAlt`/`liftRPredAlt` (~564–600), `liftLUpdateAlt`/`liftRUpdateAlt` (~603–621),
  `liftLOutFieldsAlt`/`liftROutFieldsAlt` (~624–643), and the top-level
  `liftLOutAlt`/`liftROutAlt` (~646–671), which re-tag an `OPack` by re-homing its `InCtor`
  (via `leftInCtor`/`rightInCtor`), its `WireCtor` (via `leftWireCtor`/`rightWireCtor`), and
  its `OutFields` (via `liftLOutFieldsAlt`/`liftROutFieldsAlt`).
- The user-facing `alternative` combinator (~923–949) sums *two transducers* into `Either ci`
  input / `Either co` output, using exactly the lifts above per edge.

The key structural insight: each binary lift is parameterized over which arm it lifts from
(`L` vs `R`), and `leftWireCtor`/`rightWireCtor` (etc.) are just `leftInCtor`/`rightInCtor`'s
event-side twins. A balanced-`Either` chain is therefore obtained by *composing* these binary
lifts: to inject family `k` of `N` into a right-nested chain `Either f1 (Either f2 (...))`,
you apply `rightWireCtor` `k` times then `leftWireCtor` once (and `rightInCtor`/`leftInCtor`
symmetrically on the input side, and the corresponding `Term`/`Pred`/`Update`/`OutTerm`
re-tag lifts in lockstep). That composition is the whole content of M1/M2.

### The TH splices you will touch (`src/Keiki/Generics/TH.hs` and `src/Keiki/Generics.hs`)

`deriveWireCtors` (~97–105) takes an event sum type name and a list of `(constructorName,
shortName)` pairs and, per pair, calls `genWire` (~372–392). `genWire` classifies the
constructor's payload via `conPayload` (~282–285), the three-state classifier:

    conPayload :: Con -> Maybe (Maybe Type)
    conPayload (NormalC _ [])         = Just Nothing      -- zero-arg (singleton)
    conPayload (NormalC _ [(_, t)])   = Just (Just t)     -- single-arg payload t
    conPayload _                      = Nothing            -- multi-arg / record (unsupported)

Today `genWire` accepts **only** `Just (Just payTy)` and `fail`s for both `Just Nothing`
(singleton) and `Nothing` (multi-arg/record). So a singleton event is rejected with the
message "has unsupported payload shape (singleton or multi-arg/record-syntax)". For the
`Just (Just payTy)` case it emits `wire<Short> = mkWireCtorVia @<ctorName>` (a `WireCtor`
built from `Generic` metadata) and a `<Short>TermFields` record (via `genTermFieldsRecord`,
~416–425, which additionally requires the payload type to itself be a single record-syntax
constructor).

The command side already handles the singleton case: `genCtor` (~288–307) has a `Just
Nothing` arm calling `singletonDecls` (~310–330), which emits `inCtor<Short> = mkInCtor0
"<Ctor>" <Ctor>`. `mkInCtor0` lives in `src/Keiki/Generics.hs` (~156–161):

    mkInCtor0 :: forall ci. Eq ci => String -> ci -> InCtor ci '[]
    mkInCtor0 name singleton = InCtor
      { icName  = name
      , icMatch = \ci -> if ci == singleton then Just RNil else Nothing
      , icBuild = \RNil -> singleton
      }

M3 adds the wire-side twin of this (`mkWireCtor0`) and the matching `genWire` arm.

### Where the tests and docs live

The test suite is `test-suite keiki-test` in `keiki.cabal` (a single `exitcode-stdio-1.0`
suite with `main-is: Spec.hs`, modules listed under `other-modules`, ~81–119). It uses
`hspec`. Existing models you will mirror: `test/Keiki/CompositionAlternativeSpec.hs` (builds
two small aggregates, sums them via `alternative`, asserts step-routing and `omega`/inversion
behavior), and `test/Keiki/Generics/THSpec.hs` (a toy aggregate exercising the TH splices in
isolation, including the *command-side* singleton `NoArgs`). The user-facing guide is
`docs/guide/composition.md`. The cabal package targets `GHC == 9.12.*`, `default-language:
GHC2024` (~28, 37–39).


## Plan of Work

The work is four milestones. Each is independently verifiable and builds toward the two
user-visible wins (N-ary codec composition and singleton events). Throughout, *additive*
means: do not modify or remove `alternative`, `leftWireCtor`/`rightWireCtor`, the binary
lifts, or any existing `genWire`/`genCtor` arm — only add new declarations alongside them so
that everything that compiles today still compiles unchanged.

### M1 — Design and types for the N-ary `WireCtor`-sum combinator

Scope: settle, on paper and with a tiny throwaway prototype compiled in `ghci`, the exact
representation and the exact set of new functions M2 will implement. At the end of M1, the
Decision Log records the final representation choice (balanced-`Either` vs. generated N-ary
sum) with the prototype as evidence, and this plan's Interfaces and Dependencies section
lists the precise signatures to be implemented in M2. No production file is edited in M1.

The recommended representation (to confirm, not assume) is the *balanced-`Either` chain*:
the summed output alphabet of families `co_1 … co_N` is `Either co_1 (Either co_2 (… co_N))`
(right-nested) and the summed input alphabet is the analogous nest of `Either ci_k`. The
per-arm injector for family `k` is built by composing the shipped binary lifts:

    -- conceptually, for a right-nested chain:
    injectWireK 1 = leftWireCtor
    injectWireK k = rightWireCtor . injectWireK (k - 1)

and symmetrically `injectInCtorK` from `leftInCtor`/`rightInCtor`, and `injectOutTermK` from
`liftLOutAlt`/`liftROutAlt`. Because `liftLOutAlt`/`liftROutAlt` already re-tag the whole
`OPack` (InCtor + WireCtor + OutFields) in one shot, the `OutTerm` injector is just the
composed chain of those two; you do *not* need to re-derive the `Term`/`HsPred`/`Update`
lifts from scratch — they are reached transitively through `liftLOutAlt`/`liftROutAlt` and
`liftLPredAlt`/`liftRPredAlt`/`liftLUpdateAlt`/`liftRUpdateAlt`. Confirm this transitivity in
the prototype.

The deliverable artifacts of M1 are: (a) a confirmed list of new function signatures (named
in Interfaces and Dependencies); (b) a recorded statement of the `icName`/`wcName`
cross-family uniqueness *precondition* — that the combinator's contract requires the N
families' constructor-name strings to be pairwise disjoint, and that violating it produces
the silent mis-inversion described in Context; (c) a Decision Log entry confirming or
revising the balanced-`Either` recommendation, with a one-paragraph note on the prototype
(what was summed, that an event in family `k` round-tripped through `solveOutput`).

Prototype acceptance: in `ghci` (`cabal repl keiki`), define two trivial event families and
their hand-written `WireCtor`s, build the right-nested injectors by composing
`leftWireCtor`/`rightWireCtor`, and check by hand that `wcMatch (injectWireK 2 wireB) (Right
(Left b)) == Just …` and that the injector for family 1 rejects a family-2 value. This is a
paper/`ghci` milestone; nothing is committed except this plan's updated Decision Log and
Interfaces sections.

### M2 — Implement the combinator and re-tag lifts (additive)

Scope: add the N-ary injectors to `src/Keiki/Composition.hs`, additively, in a clearly
labelled new section (e.g. `-- * N-ary coproduct injectors (EP-48) ----`). At the end of M2,
the library exposes value-level helpers that, given a `WireCtor co_k fs` (resp. `InCtor`,
`OutTerm`) for family `k` and a description of the summed shape, return the corresponding
value over the summed alphabet — and `cabal build keiki` succeeds with the binary
`alternative` and all existing lifts untouched.

Concretely, implement (final names confirmed at M1; these are the working names):

- `injectWireCtorAt :: <position-witness> -> WireCtor co_k fs -> WireCtor BigSum fs` — the
  N-ary generalization of `leftWireCtor`/`rightWireCtor`. It is the composition of the
  shipped binary `WireCtor` lifts down to the family's slot in the `Either` chain.
- `injectInCtorAt :: <position-witness> -> InCtor ci_k ifs -> InCtor BigCi ifs` — the input
  analogue, composing `leftInCtor`/`rightInCtor`.
- `injectOutTermAt :: <position-witness> -> OutTerm rs ci_k co_k -> OutTerm rs BigCi BigSum`
  — re-homes a whole derived edge's output term into the summed alphabet by composing
  `liftLOutAlt`/`liftROutAlt`. This is the function that lets an edge authored against family
  `k` participate in a transducer over the summed alphabet.

The `<position-witness>` is whatever M1 settles on to name family `k` of `N`. The simplest
option (recommended) is to *not* introduce a new witness type at all and instead expose the
helpers as ordinary compositions — i.e. the library re-exports `leftWireCtor`/`rightWireCtor`
(already there) and ships a thin documented helper plus worked examples showing that `family
k = rightWireCtor . rightWireCtor . … . leftWireCtor`. If M1's prototype shows this is
ergonomic enough, M2 may be as small as a documentation block plus one or two convenience
wrappers; if M1 finds the manual composition too error-prone, M2 introduces a small
type-indexed witness (e.g. a `Peano`-style `Nat` or a length-indexed selector) to compute the
composition. Either way, the implementation is pure value-level code reusing the shipped
binary lifts; M2 adds *no* new `unsafeCoerce` and changes nothing in `src/Keiki/Core.hs`.

Commands to run at the end of M2:

    cabal build keiki

Acceptance: the package compiles; the new section exists; `git diff` shows no edit to
`alternative` or the binary lifts.

### M3 — Singleton-event support (additive)

Scope: add the wire-side singleton helper and a new `genWire` arm. At the end of M3,
`deriveWireCtors` accepts a zero-argument event constructor and produces a working
`WireCtor`, while every existing single-record event derivation is byte-for-byte unchanged.

Two edits:

1. In `src/Keiki/Generics.hs`, add `mkWireCtor0`, the event-side twin of `mkInCtor0`. Its
   `fields` type is `()` (a singleton event has no payload, so the wire field tuple is the
   empty tuple, matching `OutFields rs ci ()` / `OFNil`):

       mkWireCtor0 :: forall co. Eq co => String -> co -> WireCtor co ()
       mkWireCtor0 name singleton = WireCtor
         { wcName  = name
         , wcMatch = \co -> if co == singleton then Just () else Nothing
         , wcBuild = \() -> singleton
         }

   Add it to the module's export list alongside `mkInCtor0`/`mkWireCtorVia`.

2. In `src/Keiki/Generics/TH.hs`, extend `genWire` (~372–392) to handle `conPayload con ==
   Just Nothing` (the zero-arg case). The new arm emits, for spec entry `(ctorStr,
   shortStr)`:

       wire<Short> :: WireCtor <EventSum> ()
       wire<Short> = mkWireCtor0 "<ctorStr>" <Ctor>

   mirroring how `singletonDecls` (in the same file, ~310–330) emits `mkInCtor0` on the
   command side. A singleton event has no record payload, so the new arm must **not** call
   `genTermFieldsRecord` (which requires a single record-syntax payload, ~416–425); it emits
   only the `wire<Short>` signature and definition. Keep the existing `Just (Just payTy)` arm
   exactly as is; keep the final `_ -> fail …` clause for the genuinely unsupported `Nothing`
   (multi-arg/record) case, but narrow its message so it no longer claims singletons are
   unsupported.

Commands to run at the end of M3:

    cabal build keiki

Acceptance: the package compiles; a singleton event in a toy sum derives (proven by M4's
test). Note for the implementer: `mkWireCtor0` needs `Eq co` on the event sum (to compare
the observed value against the named singleton), exactly as `mkInCtor0` needs `Eq ci`. Event
sums in this codebase already derive `Eq` (see `UserEvent` in
`test/Keiki/Fixtures/UserRegistration.hs`), so this is not a new burden in practice; state it
in the haddock.

### M4 — Tests and docs

Scope: prove all three behaviors and document the combinator. At the end of M4 there are new
hspec tests (registered in `keiki.cabal` under the `keiki-test` suite's `other-modules`) and
a new short section in `docs/guide/composition.md`.

Three test groups, in a new module `test/Keiki/CompositionNarySpec.hs`. The suite is a
*manual* aggregator: `test/Spec.hs` lists every spec with an explicit `import qualified
Keiki.<Name>Spec` and calls each module's `spec` from its `main` (it is not
hspec-discover-driven). So registering the new module takes **two** edits: add
`Keiki.CompositionNarySpec` to `other-modules` in `keiki.cabal`'s `keiki-test` stanza, and
add the matching `import qualified` plus a `describe "…" Keiki.CompositionNarySpec.spec`
invocation in `test/Spec.hs`, mirroring how `Keiki.CompositionAlternativeSpec` is wired
there.

1. **Multi-family round-trip through `solveOutput`.** Define two small, independent event
   families (and their command alphabets) with `deriveWireCtors`/`deriveAggregateCtors` — or
   reuse the existing fixtures `Keiki.Fixtures.EmailDelivery` and
   `Keiki.Fixtures.UserRegistration` if their families are convenient. Build the summed
   output alphabet via the M2 injectors. For an event constructed in family *k*, build an
   `OPack`/`OutTerm` over the summed alphabet using `injectOutTermAt`/`injectWireCtorAt`/
   `injectInCtorAt`, then assert `solveOutput thatOutTerm someRegs (injectFamilyK event) ==
   Just (injectFamilyKCommand command)`. Do this for at least two distinct families so the
   test exercises a non-trivial position in the chain (family 2, not just family 1). This is
   the headline acceptance: an event in family *k* inverts back to its command through the
   summed alphabet.

2. **`icName`/`wcName` cross-family uniqueness.** Add a positive and a negative assertion.
   Positive: for the well-formed summed alphabet from group 1, collect the `wcName`s (and
   `icName`s) of every injected constructor and assert they are pairwise distinct (e.g.
   `length names == length (nub names)`), documenting in a comment that this is the
   precondition `solveOutput`/`stepOne` rely on (string-equality match at
   `src/Keiki/Core.hs` ~1067). Negative/expected-failure demonstration: construct two
   *deliberately name-colliding* `WireCtor`s for distinct families (two families that both
   contain a constructor named, say, `"Done"`), inject both, and assert that inverting an
   event of one family against the *other* family's `OPack` mis-behaves — i.e. show the
   failure mode (either `solveOutput` returns the wrong command or the uniqueness check
   flags it). The point is to make the obligation executable and visible, so a future reader
   sees exactly what breaks when names collide. If demonstrating the silent mis-inversion is
   awkward, at minimum assert that the uniqueness check *would have rejected* the colliding
   alphabet, and document that the combinator's contract requires unique names.

3. **Singleton-event round-trip.** In a toy module (or extend `test/Keiki/Generics/THSpec.hs`,
   which already has the command-side singleton `NoArgs`), define an event sum with a
   zero-argument constructor, run `deriveWireCtors` over it, and assert: `wcName wire<Short>
   == "<Ctor>"`; `wcMatch wire<Short> <Ctor> == Just ()`; `wcMatch wire<Short> <OtherCtor>
   == Nothing`; `wcBuild wire<Short> () == <Ctor>`. Then assemble an `OPack` pairing a
   singleton *command* `InCtor` (via `mkInCtor0`) with the singleton *event* `WireCtor` and
   `OFNil`, and assert `solveOutput` inverts the singleton event back to the singleton
   command (`assemble []` for the empty `ifs` is `Just RNil`, so the empty-payload case
   recovers trivially — this is exactly the path `solveOutput`'s haddock at
   `src/Keiki/Core.hs` ~449 mentions).

Docs: add a section to `docs/guide/composition.md` (after the existing `alternative`
material) titled e.g. "Summing N event families" that: (a) states the problem (a stream
carrying several already-derived families); (b) shows the balanced-`Either` shape of the
summed alphabet and the injector composition with a worked two- or three-family snippet; (c)
states the name-uniqueness obligation in plain words ("the families' constructor names must be
pairwise distinct, because `solveOutput` matches by name"); (d) points to
`docs/guide/multi-event-commands.md`/`docs/research/composition-combinators-design.md` for
deeper background. Keep snippets as four-space-indented blocks consistent with that file's
existing style (note `composition.md` currently uses fenced blocks and tables — match the
*surrounding* file's style there; the four-space rule is for *this plan*, not for the guide
it edits).

Commands to run at the end of M4 are in Concrete Steps and Validation and Acceptance.


## Concrete Steps

All commands run from the repository root, `/Users/shinzui/Keikaku/bokuno/keiki`.

M1 (design/prototype; nothing committed but this plan):

    cabal repl keiki
    -- in ghci, paste the two-family prototype from M1 and check the
    -- injector compositions by hand, then :quit

M2 (implement injectors):

    cabal build keiki

Expected tail of a successful build (versions/paths will differ slightly):

    [n of m] Compiling Keiki.Composition  ( src/Keiki/Composition.hs, ... )
    ...
    Linking ...   (or just a clean exit with no errors)

M3 (singleton support):

    cabal build keiki

Same expected clean build; additionally `Keiki.Generics` and `Keiki.Generics.TH` recompile.

M4 (tests + docs): after adding `Keiki.CompositionNarySpec` to `other-modules` in
`keiki.cabal`, run the whole suite:

    cabal test keiki-test

If you want to iterate on just the new specs, hspec supports a match filter via the
test-suite's argument passthrough:

    cabal test keiki-test --test-options='--match "/Composition.N-ary/"'

(Adjust the `--match` string to the `describe` label you choose, e.g. `"summing N event
families"`.)


## Validation and Acceptance

The exact test command for the whole suite is:

    cabal test keiki-test

Run from `/Users/shinzui/Keikaku/bokuno/keiki`. Expected output ends with hspec's summary
showing zero failures, for example:

    Keiki.CompositionNarySpec
      summing N event families
        round-trips a family-1 event through solveOutput [✔]
        round-trips a family-2 event through solveOutput [✔]
      icName/wcName uniqueness
        injected family names are pairwise distinct [✔]
        colliding family names mis-invert (expected failure demo) [✔]
      singleton events
        deriveWireCtors derives a zero-arg event WireCtor [✔]
        solveOutput inverts a singleton event to its command [✔]

    Finished in 0.0xxx seconds
    NNN examples, 0 failures

Acceptance is *behavioral*, beyond compilation, in three concrete forms:

1. **N-ary round-trip.** A transducer (or, minimally, a hand-built `OutTerm`) whose output
   type is the sum of N derived families builds an event in family *k* and `solveOutput`
   inverts it back to the command that produced it — proven by the family-1 and family-2
   round-trip examples above returning `Just <originalCommand>`. Before this plan, there is
   no documented way to construct that summed `OutTerm` from independently-derived families;
   after it, the injector examples do.

2. **Name-uniqueness obligation is executable.** The uniqueness assertion passes for a
   well-formed summed alphabet, and the deliberate-collision demonstration shows the failure
   mode (wrong command recovered, or the uniqueness check rejecting the alphabet). This makes
   the one real correctness obligation visible and regression-protected.

3. **Singleton event derives and round-trips.** A previously-rejected zero-argument event
   constructor now produces a `WireCtor` via `deriveWireCtors`, and `solveOutput` inverts the
   singleton event to its singleton command. To see the *before* state, you can temporarily
   point a singleton event at the old `genWire` (or recall its `fail` message "has
   unsupported payload shape (singleton or multi-arg/record-syntax)") — after the change the
   same input compiles and the round-trip test passes.

The expected collision *failure mode*, stated precisely so a reader can recognise it: if two
families both contain a constructor whose name string is, e.g., `"Done"`, then `solveOutput`,
matching `TInpCtorField` by `icName` string equality at `src/Keiki/Core.hs` ~1067, may match
the *wrong* family's input constructor and `unsafeCoerce` the index, yielding either a
`Nothing` (if the fields don't line up) or — worse — a `Just <wrong command>` with no type
error. The combinator's contract therefore *requires* pairwise-distinct constructor names
across summed families; the uniqueness test enforces it.


## Idempotence and Recovery

Every step is additive and safe to repeat. M2 adds a new section to
`src/Keiki/Composition.hs` without touching `alternative` or the binary lifts; re-running
`cabal build keiki` is idempotent. M3 adds one function to `src/Keiki/Generics.hs` and one
arm to `genWire`; if the build fails, the failure is local to those two files and the old
behavior is restored by reverting them (the existing `Just (Just payTy)` arm is unchanged, so
all current derivations keep working even mid-edit, as long as the new arm type-checks). M4
only adds a test module and a docs section; re-running `cabal test keiki-test` is idempotent.

Rollback: because nothing existing is modified destructively, `git checkout --
src/Keiki/Composition.hs src/Keiki/Generics.hs src/Keiki/Generics/TH.hs` returns the library
to its pre-plan state, and removing the new test module from `keiki.cabal`'s `other-modules`
and from disk returns the suite to its prior shape. There are no migrations, no data changes,
and no on-disk artifacts beyond source files.


## Interfaces and Dependencies

Libraries and modules used, and why:

- `src/Keiki/Core.hs` — owns `WireCtor` (~404), `InCtor` (~297), `OutTerm`/`OPack`
  (~442–454), `OutFields` (~414–418), and `solveOutput`/`gatherInpEntries`/`stepOne`
  (~1039–1071, the inversion site). This plan *reads and reuses* these types and *must not
  modify them*. The string-equality match in `stepOne` (~1067) is the correctness obligation
  this plan enforces by name-uniqueness.
- `src/Keiki/Composition.hs` — this plan **owns** the N-ary generalization added here. It
  reuses the shipped binary lifts `leftInCtor`/`rightInCtor` (~485–504),
  `leftWireCtor`/`rightWireCtor` (~510–529), and `liftLOutAlt`/`liftROutAlt` (~646–671), and
  leaves the binary `alternative` (~923–949) untouched.
- `src/Keiki/Generics.hs` — owns `mkInCtor0` (~156–161), `mkWireCtorVia` (~423–438),
  `FieldsOf`/`FieldsOfRep` (~225–234). This plan adds `mkWireCtor0` next to `mkInCtor0`.
- `src/Keiki/Generics/TH.hs` — owns `deriveWireCtors` (~97–105), `genWire` (~372–392),
  `conPayload` (~282–285), `singletonDecls` (~310–330), `genTermFieldsRecord` (~416–425).
  This plan adds the `Just Nothing` arm to `genWire`.
- `hspec` (test framework), already a `keiki-test` dependency in `keiki.cabal` (~114).

Integration points (shared artifacts, stated for coordination):

1. This plan **owns** the N-ary generalization in `src/Keiki/Composition.hs`. It **shares**
   the types `WireCtor`/`OutTerm`/`OPack` (`src/Keiki/Core.hs`) with the sibling plan
   `docs/plans/47-recompute-and-verify-derived-event-outputs-in-solveoutput-replay.md` (EP-47),
   which only *reasons about* those types and does not extend them. There is no hard
   dependency between this plan and any sibling; both can land independently.
2. The correctness obligation shared with EP-47 is that `solveOutput`/`stepOne` match
   `OPack`s by `icName`/`wcName` *string equality* (`src/Keiki/Core.hs` ~1067). EP-47 reasons
   about that site (it relaxes which field *terms* are invertible) but does not change the
   string-equality grouping. **This plan is responsible for enforcing and testing that
   `icName`/`wcName` are unambiguous across the summed families** (M4, test group 2).

Signatures that must exist at the end of each milestone:

- End of M1: a Decision Log entry fixing the representation, and this section updated with the
  final names/signatures of the injectors (working names below). No code yet.
- End of M2 (in `src/Keiki/Composition.hs`), final names confirmed at M1; working names:

      injectWireCtorAt :: <pos> -> WireCtor co_k fs   -> WireCtor BigSum fs
      injectInCtorAt   :: <pos> -> InCtor   ci_k ifs  -> InCtor   BigCi  ifs
      injectOutTermAt  :: <pos> -> OutTerm rs ci_k co_k -> OutTerm rs BigCi BigSum

  where `<pos>` names family `k` of `N` (a small `Nat`/selector witness, or — if M1 finds the
  manual composition ergonomic — no witness at all, with the helpers documented as
  compositions of `leftWireCtor`/`rightWireCtor` etc.), and `BigSum`/`BigCi` are the
  balanced-`Either` nests over the families' `co`/`ci` types.
- End of M3 (in `src/Keiki/Generics.hs`):

      mkWireCtor0 :: forall co. Eq co => String -> co -> WireCtor co ()

  exported; and `genWire` in `src/Keiki/Generics/TH.hs` emits `wire<Short> :: WireCtor
  <EventSum> ()` / `wire<Short> = mkWireCtor0 "<Ctor>" <Ctor>` for zero-arg constructors.
- End of M4: a new module `test/Keiki/CompositionNarySpec.hs` registered in `keiki.cabal`'s
  `keiki-test` `other-modules`, with the three test groups described in M4; and a "Summing N
  event families" section in `docs/guide/composition.md`.
