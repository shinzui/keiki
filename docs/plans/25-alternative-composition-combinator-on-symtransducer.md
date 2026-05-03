---
id: 25
slug: alternative-composition-combinator-on-symtransducer
title: "Alternative composition combinator on SymTransducer"
kind: exec-plan
created_at: 2026-05-03T01:53:04Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
master_plan: "docs/masterplans/8-composition-combinators-beyond-sequential-parallel-alternative-feedback-kleisli.md"
---


# Alternative composition combinator on SymTransducer

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this change, an aggregate author can express **disjoint-input
dispatch** between two sibling aggregates with one library call:

    siblings :: SymTransducer
                  (HsPred (Append rs1 rs2) (Either ci1 ci2))
                  (Append rs1 rs2)
                  (CompositeSum s1 s2)
                  (Either ci1 ci2)
                  (Either co1 co2)
    siblings = alternative leftAggregate rightAggregate

The composite consumes `Either ci1 ci2`. A `Left ci1` advances `t1`
and emits `Left co1`; a `Right ci2` advances `t2` and emits
`Right co2`. The composite preserves all three load-bearing keiki
analyses (`solveOutput`, `checkHiddenInputs`, `isSingleValuedSym`)
end-to-end. Single-valuedness inherits automatically when t1 and t2
are individually single-valued — no new cross-transducer analysis is
required.

The user-visible behavior:

- Sibling bounded contexts in one service are expressible as a
  single composite transducer for the symbolic analyses.
- Round-trip replay (`Keiki.Core.applyEvents`) over a mixed
  `[Either co1 co2]` event log lands at the correct composite final
  state.
- `checkHiddenInputs (alternative t1 t2)` returns the union of
  per-side warnings, so authoring mistakes in either side surface at
  build time.
- `isSingleValuedSym (withSymPred (alternative t1 t2))` returns
  `True` when both sides are individually single-valued.

How a reader sees it working:

    cabal test --test-show-details=streaming \
        --test-options "--match Keiki.CompositionAlternativeSpec"

reports the new spec passing with cases for: routing on `Left` /
`Right`, mixed-arm event-log round trip, `checkHiddenInputs`,
`isSingleValuedSym`.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] **M0 — Confirm starting state.** *(2026-05-03)* `cabal build
  all` is `Up to date`; `cabal test all` reports 169 examples, 0
  failures. GHC 9.12.3 (matches `keiki.cabal`'s `tested-with: GHC
  == 9.12.*`). Green baseline established.
- [x] **M1 — Add `CompositeSum` data type and instances.** *(2026-05-03)*
  *Added then removed (see Surprises & Discoveries entry dated
  2026-05-03).* Initially added `data CompositeSum s1 s2 = InL
  !s1 | InR !s2` to `src/Keiki/Composition.hs` with the full
  instance set. M4's acceptance tests revealed the sum-vertex
  shape was degenerate for `alternative`'s intended semantics
  (sibling aggregates with independent state); the type was
  removed in the same M4 commit and `alternative` was re-targeted
  to the existing product `Composite s1 s2`. The Either lifters
  introduced in M2 remain useful and stay exported.
- [x] **M2 — Add the input-side and output-side Either lifters.** *(2026-05-03)*
  Added `leftInCtor` / `rightInCtor`, `leftWireCtor` / `rightWireCtor`,
  `liftLTermAlt` / `liftRTermAlt`, `liftLPredAlt` / `liftRPredAlt`,
  `liftLUpdateAlt` / `liftRUpdateAlt`, `liftLOutFieldsAlt` /
  `liftROutFieldsAlt`, `liftLOutAlt` / `liftROutAlt` to
  `src/Keiki/Composition.hs`. Also added right-side weakening
  helpers `weakenRTerm`, `weakenRPred`, `weakenRUpdate`,
  `weakenROutFields`, `weakenROut` that mirror the existing
  `weakenL*` family but lift over an rs1 prefix using the
  `WeakenR` class. Output-side weakening helper `weakenLOut` (and
  `weakenLOutFields`) added for symmetry. `cabal build` clean.
- [x] **M3 — Add the `alternative` combinator.** *(2026-05-03)* Added
  `alternative` at the end of `src/Keiki/Composition.hs` with the
  signature
  (`SymTransducer (HsPred rs1 ci1) ... -> SymTransducer (HsPred rs2 ci2) ... -> SymTransducer (HsPred (Append rs1 rs2) (Either ci1 ci2)) ...`).
  Composite vertex is the product `Composite s1 s2` (revised from
  the original sum-vertex per M4's discovery): each composite
  vertex emits both t1's edges (lifted via `weakenL*` /
  `liftL*Alt`) targeting `Composite (target e1) s2` and t2's edges
  (lifted via `weakenR*` / `liftR*Alt`) targeting `Composite s1
  (target e2)`. Initial state `Composite (initial t1) (initial
  t2)`; `isFinal` requires both sub-aggregates final; register
  file `appendRegFile (initialRegs t1) (initialRegs t2)`.
- [x] **M4 — Acceptance test.** *(2026-05-03)* Added
  `test/Keiki/CompositionAlternativeSpec.hs` with nine test cases:
  Left/Right/interleaved step routing, mixed-arm reconstitute
  (both orderings — Left+Right and Right+Left), omega for both
  arms, `checkHiddenInputs` returning `[]`, and
  `isSingleValuedSym (withSymPred siblings)` returning `True`. The
  fixture composes `Keiki.Examples.EmailDelivery` with an inline
  `Pinger` aggregate (single command `Ping`, single event `Pong`,
  one slot `pingNonce` disjoint from EmailDelivery's slot names).
- [x] **M5 — Wire spec into test suite.** *(2026-05-03)* Added
  `Keiki.CompositionAlternativeSpec` to `keiki.cabal`'s
  `keiki-test` `other-modules` and to `test/Spec.hs` with
  describe label `"Keiki.Composition (alternative, EP-25)"`. Full
  suite now 178 examples, 0 failures (was 169/0; +9 alternative
  cases).
- [ ] **M6 — Update design note and MP-8.** Append a "What we
  shipped" subsection under
  `docs/research/composition-combinators-design.md`'s `alternative`
  section. Mark this EP "Complete" in MP-8's Exec-Plan Registry; tick
  the corresponding entry in MP-8's Progress section.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- **2026-05-03 — `alternative`'s vertex shape is product, not sum.**
  EP-24's design record specified `CompositeSum s1 s2 = InL s1 | InR s2`
  for `alternative`'s composite vertex. The M4 acceptance tests
  surfaced that this is degenerate: with `initial = InL (initial
  t1)` there is no edge from any `InL s1` to any `InR s2`, so the
  composite can never reach the right arm. The intended semantics
  per MP-8's Vision ("sibling aggregates that share a runtime
  channel") is **per-arm independent state**: each input
  (`Left ci1` or `Right ci2`) advances exactly one sub-aggregate
  and leaves the other's state unchanged. The correct vertex
  shape is the product `Composite s1 s2` (which `compose` already
  uses). At each step:
   * `Left ci1` → walk t1's edges from `s1`, leave `s2` unchanged
     (target = `Composite (target e1) s2`).
   * `Right ci2` → walk t2's edges from `s2`, leave `s1` unchanged
     (target = `Composite s1 (target e2)`).
  Three test failures (`Right input advances the Pinger arm`, the
  initial-arm dispatch test, and the omega Right test) showed
  `Nothing` from the sum-vertex implementation because the only
  outgoing edges from `InL s1` were t1's lifted edges (which
  reject `Right` inputs). Switching to product-vertex unifies the
  edge construction: at each `Composite s1 s2`, both t1's edges
  (gated on `Left`) and t2's edges (gated on `Right`) are
  outgoing.

  Cross-plan impact: the design record at
  `docs/research/composition-combinators-design.md` has been
  revised to specify `Composite` (product); EP-26's `feedback1`
  is unaffected (it uses `Composite` already). `CompositeSum` is
  removed from `Keiki.Composition` — there is no admitted MP-8
  combinator that uses it. The Either lifters introduced in M2
  remain useful and stay exported.


## Decision Log

Record every decision made while working on the plan.

- Decision: Adopt the design from EP-24's per-combinator design
  record at `docs/research/composition-combinators-design.md`'s
  `alternative` section without revision.
  Rationale: EP-24 ran the design pass with full context; revisiting
  the verdicts here would duplicate effort. Any deviation found
  during implementation gets logged as a new decision in this
  Decision Log and back-propagated to the design note.
  Date: 2026-05-03

- Decision: Initial-state policy is fixed to `InL (initial t1)`
  rather than parameterised.
  Rationale: The single fixed initial keeps the API minimal. An
  `alternativeWith :: Either s1 s2 -> SymTransducer ... ->
  SymTransducer ... -> SymTransducer ...` variant can be added
  later without disturbing this signature.
  Date: 2026-05-03


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

The reader has the working tree at the keiki repository root and
nothing else.

### What keiki is, in one paragraph

`keiki` is a pure-core Haskell library that models a single
event-sourced aggregate as a **symbolic-register transducer**: a
finite control graph, an existentially-typed register file `RegFile
rs` indexed by a type-level slot list `rs :: [Slot]`, and edges that
carry a guard predicate `phi`, a register update term, an optional
output term, and a target vertex. The library lives entirely in
`src/Keiki/` and exposes its types and operations through the
modules listed in `keiki.cabal`'s `exposed-modules`. It has no `IO`.

### What `compose` already does

`src/Keiki/Composition.hs` exports the existing sequential
combinator `compose` (defined at line 383). It walks t2's AST and
substitutes `mid`-reads with structural references to t1's edge
output, building a composite `SymTransducer` whose vertex is
`Composite s1 s2` (a strict-product newtype at line 64) and whose
register file is `Append rs1 rs2`. The substitution machinery —
`WeakenR`, `weakenL`, `weakenLTerm`, `weakenLPred`, `weakenLUpdate`,
`substTerm`, `substPred`, `substUpdate`, `substOut`,
`substOutFields` — is exported for advanced uses and is reused by
`alternative`.

The full design record for `compose` is at
`docs/research/composition-combinators-design.md`. Read its
"`compose` — type signature", "`compose` — semantics", "Substitution
algorithm", and "How the composite preserves the three guarantees"
sections before starting M2.

### What this plan adds

A second combinator, `alternative`, with input alphabet `Either ci1
ci2` and output alphabet `Either co1 co2`. The design record for
`alternative` is at
`docs/research/composition-combinators-design.md` under
"Combinators beyond `compose` — per-combinator design records" →
"`alternative` — admitted". Read the four subsections (Signature,
Semantics, Single-step example, Preservation arguments) before
starting M2.

### The three load-bearing analyses

`keiki` ships three analyses. Each new combinator must preserve all
three on the composite:

1. **`solveOutput`** at `src/Keiki/Core.hs:730`. Mechanical
   inversion of an `OutTerm rs ci co` plus a `RegFile rs` plus an
   observed `co`, producing the `ci` that produced it. Walks the
   structural `OPack` form (post-MP-6 — `OFn` was retired in EP-16
   and is not in the current core).
2. **`checkHiddenInputs`** at `src/Keiki/Core.hs:786`. Walks every
   edge and flags ε-edges whose update reads input, edges whose
   `OutFields` chain doesn't visit every slot of the named
   `InCtor` (a hidden input that breaks event-sourced replay).
3. **`isSingleValuedSym`** at `src/Keiki/Symbolic.hs:384`. For each
   reachable composite vertex, checks that every distinct pair of
   outgoing edges has an `isBot` (unsatisfiable) guard conjunction.
   `BoolAlg phi`-polymorphic; with `SymPred` (lifted via
   `withSymPred` at `src/Keiki/Symbolic.hs:407`) the `isBot` is
   SBV/Z3-backed.

### Composite vertex shape — `CompositeSum s1 s2`

`compose` uses the strict product `Composite s1 s2 = Composite !s1
!s2` (line 64). For `alternative`, the composite vertex is a sum:

    data CompositeSum s1 s2 = InL !s1 | InR !s2
      deriving (Eq, Show)

The strict bangs match `Composite`'s style. The data type lives in
`src/Keiki/Composition.hs` alongside `Composite`. Instances:

- `Bounded`: `minBound = InL minBound`, `maxBound = InR maxBound`.
- `Enum`: range-style enumeration.
   - `toEnum n` distinguishes by range: if
     `n < (fromEnum (maxBound :: s1) - fromEnum (minBound :: s1) + 1)`
     then `InL (toEnum n)`, else
     `InR (toEnum (n - <s1's size>))`.
   - `fromEnum (InL a) = fromEnum a - fromEnum (minBound :: s1)`.
   - `fromEnum (InR b) = <s1's size> + (fromEnum b - fromEnum
     (minBound :: s2))`.
- `NoThunks`: walks both arms.

The instances mirror the precedent at
`src/Keiki/Composition.hs:68-100`.

### `Either`-side lifters

The lifters convert references from one side's frame to the
composite's `Either`-typed input/output:

- `liftLPredAlt :: HsPred rs ci1 -> HsPred rs (Either ci1 ci2)`
  walks the AST and adjusts every `PInCtor (ic1 :: InCtor ci1 ifs)`
  to `PInCtor (leftInCtor ic1 :: InCtor (Either ci1 ci2) ifs)`,
  every `TInpCtorField ic1 ix` similarly. `PEq`, `PAnd`, `POr`,
  `PNot`, `PTop`, `PBot` recurse / pass through.
- `liftLUpdateAlt :: Update rs w ci1 -> Update rs w (Either ci1 ci2)`
  walks the update and adjusts every `Term` inside.
- `liftLOutAlt :: OutTerm rs ci1 co1 -> OutTerm rs (Either ci1
  ci2) (Either co1 co2)` adjusts the `OPack` `InCtor` (using
  `leftInCtor`), the `WireCtor` (using `leftWireCtor`), and walks
  every field term.
- `leftInCtor :: InCtor ci1 ifs -> InCtor (Either ci1 ci2) ifs`
  builds an `InCtor` whose `icMatch (Left c1) = ic1.icMatch c1` and
  `icMatch (Right _) = Nothing`; whose `icBuild rf = Left
  (ic1.icBuild rf)`.
- `leftWireCtor :: WireCtor co1 fs -> WireCtor (Either co1 co2) fs`
  builds a `WireCtor` whose `wcMatch (Left co1) = wc1.wcMatch co1`
  and `wcMatch (Right _) = Nothing`; whose `wcBuild fs = Left
  (wc1.wcBuild fs)`.

`R`-side siblings (`liftRPredAlt`, etc.) handle `t2`'s side
symmetrically.

The lifters compose with `weakenL` / `weakenR` from the existing
machinery: t1's references are first lifted into the appended
register file (`weakenL`), then into the `Either` input
(`liftLPredAlt`).

### `alternative`'s edges

For each composite vertex `InL s1`, the outgoing edges are exactly
t1's edges from `s1` after applying:

1. `weakenLPred @rs1 @rs2 (guard e1)` (lift across rs2 suffix).
2. `liftLPredAlt @ci2 (...)` (lift into `Either` arm).

producing `HsPred (Append rs1 rs2) (Either ci1 ci2)`. Similarly for
`update`, `output`, and the target (`InL (target e1)`). The `InR
s2` side mirrors with `weakenR` + `liftRPredAlt`.


## Plan of Work

Six milestones. Each is independently verifiable.

### M0 — Confirm starting state

**Scope.** Establish the green baseline. No code changes.

**Commands (working directory: repository root).**

    cabal build all
    cabal test all
    ghc --version

**Acceptance.** Both `cabal` commands succeed (exit 0). Test
summary: 169 examples, 0 failures (or higher). GHC version matches
`keiki.cabal`'s `tested-with: GHC == 9.12.*` (currently 9.12.3).

### M1 — Add `CompositeSum` data type and instances

**Scope.** Add the sum vertex type to `src/Keiki/Composition.hs`,
exported alongside `Composite`. Mirror the existing `Composite`
implementation (lines 64–100).

**Edit target.** `src/Keiki/Composition.hs`. Add a "* The
alternative composite vertex" section after the existing "* The
composite vertex" section (line 58). Add `CompositeSum (..)` to
the export list at line 33.

**What will exist at the end.** A new `data CompositeSum s1 s2`
with `Eq`, `Show`, `Bounded`, `Enum`, `NoThunks` instances. The
existing tests still pass (the new type is unused so far).

**Commands.**

    cabal build all
    cabal test all

**Acceptance.** Same green baseline as M0; `Keiki.Composition`
exports the new type.

### M2 — Add the Either lifters

**Scope.** Add the input-side and output-side `Either` lifters
described in Context above. Reuse the existing `weakenL` / `weakenR`
machinery without duplication.

**Edit target.** `src/Keiki/Composition.hs`. Add a "* Either
lifters (alternative-side)" section after the existing "*
Substitution algorithm" section. Export the lifters under the
existing "-- * Substitution (exposed for advanced uses)" haddock
header (rename to "-- * Substitution and lifters (exposed for
advanced uses)") so they are discoverable by future combinator
authors.

**What will exist at the end.** Six new top-level functions:
`leftInCtor`, `leftWireCtor`, `liftLPredAlt`, `liftLUpdateAlt`,
`liftLOutAlt`, plus their `R` siblings.

**Acceptance.** `cabal build all` clean. The lifters have unit
tests under M4 (the per-combinator acceptance test); M2 itself only
verifies they compile.

### M3 — Add the `alternative` combinator

**Scope.** Compose the lifters from M2 and the `weakenL` / `weakenR`
machinery into the user-facing `alternative` combinator.

**Edit target.** `src/Keiki/Composition.hs`. Add a "* alternative"
section after the existing "* compose" section (line 354). Add
`alternative` to the export list.

**What will exist at the end.** The `alternative` function with
the signature in the design record. The composite's edges are the
union of (lifted-t1-edges from `InL s1`) and (lifted-t2-edges from
`InR s2`). `isFinal` dispatches on the arm. Initial state is `InL
(initial t1)`.

**Implementation sketch.** The body parallels `compose`:

    alternative t1 t2 = SymTransducer
      { edgesOut    = altEdges
      , initial     = InL (initial t1)
      , initialRegs = appendRegFile (initialRegs t1) (initialRegs t2)
      , isFinal     = \case
          InL s1 -> isFinal t1 s1
          InR s2 -> isFinal t2 s2
      }
      where
        altEdges (InL s1) = map liftL (edgesOut t1 s1)
        altEdges (InR s2) = map liftR (edgesOut t2 s2)

        liftL e1 = Edge
          { guard  = liftLPredAlt   @ci2 (weakenLPred   @rs1 @rs2 (guard  e1))
          , update = liftLUpdateAlt @ci2 (weakenLUpdate @rs1 @rs2 (update e1))
          , output = fmap (liftLOutAlt @ci2 @co2 . weakenLOut @rs1 @rs2)
                          (output e1)
          , target = InL (target e1)
          }
        liftR e2 = Edge
          { guard  = liftRPredAlt   @ci1 (weakenRPred   @rs1     (guard  e2))
          , update = liftRUpdateAlt @ci1 (weakenRUpdate @rs1     (update e2))
          , output = fmap (liftROutAlt @ci1 @co1 . weakenROut @rs1)
                          (output e2)
          , target = InR (target e2)
          }

`weakenLOut` / `weakenROut` are output-side counterparts to the
existing `weakenLTerm` / `weakenLPred` lifters; if they don't exist
yet, M2 adds them.

**Acceptance.** `cabal build all` clean. Unit acceptance is via M4.

### M4 — Acceptance test

**Scope.** A new spec module that exercises every preservation
property the design record promises.

**Edit target.** New file
`test/Keiki/CompositionAlternativeSpec.hs`. Pattern matches
`test/Keiki/CompositionSpec.hs` (the existing `compose` spec).
Compose two aggregates — pick `Keiki.Examples.UserRegistration`
(complex enough to exercise `solveOutput`'s gather logic) and a
small local fixture (likely a simplified email-side aggregate
similar to the `AlertSource` fixture defined inline in
`test/Keiki/CompositionSpec.hs:42`).

**Tests to author** (from the design record's "Acceptance criteria
for the implementation EP"):

- `step` routes correctly on `Left` and `Right` inputs.
- `omega` produces `Left` and `Right` outputs.
- `reconstitute` round-trips a canonical mixed-arm event log.
- `checkHiddenInputs (alternative t1 t2)` returns `[]`.
- `isSingleValuedSym (withSymPred (alternative t1 t2))` returns
  `True`.

**Commands.**

    cabal test --test-show-details=streaming \
        --test-options "--match Keiki.CompositionAlternativeSpec"

**Acceptance.** All five test cases pass.

### M5 — Wire spec into test suite

**Scope.** Make the spec discoverable by hspec.

**Edit targets.** `keiki.cabal` (`keiki-test`'s `other-modules`)
and `test/Spec.hs` (the hspec auto-discovery file or the
hand-listed spec runner).

Inspect `test/Spec.hs` first to determine the discovery style; the
existing `Keiki.CompositionSpec` precedent shows the pattern.

**Commands.**

    cabal test all

**Acceptance.** The full suite (170+ examples now) passes with no
regressions.

### M6 — Update design note and MP-8

**Scope.** Append a "What we shipped" subsection under
`docs/research/composition-combinators-design.md`'s `alternative`
section noting any divergence from the design record. Mark this
EP "Complete" in MP-8's Exec-Plan Registry. Tick the corresponding
entry in MP-8's Progress section.

**Edit targets.**

- `docs/research/composition-combinators-design.md` — under
  "`alternative` — admitted", add a "What we shipped" subsection.
- `docs/masterplans/8-composition-combinators-beyond-sequential-parallel-alternative-feedback-kleisli.md`
  — registry status update for this EP; Progress checkbox tick.
- `docs/research/keiki-generics-design.md` — extend item F's "In
  progress (see EP-24 / MP-8)" paragraph to note the `alternative`
  shipped.

**Acceptance.** A reader can locate every artefact this EP
produced from the registry and the design note.


## Concrete Steps

The implementation EPs share the same outer-shell commands. Run
each from the repository root.

Build and run all tests:

    cabal build all
    cabal test all

Run only the new spec while iterating:

    cabal test --test-show-details=streaming \
        --test-options "--match Keiki.CompositionAlternativeSpec"

Re-export the lifters under a renamed haddock section: edit the
relevant `-- * Substitution (exposed for advanced uses)` comment in
`src/Keiki/Composition.hs:42` (verify the line number with
`grep -n "exposed for advanced" src/Keiki/Composition.hs`).


## Validation and Acceptance

Acceptance is observable via `cabal test all`:

1. The full suite passes with no regressions vs M0's baseline.
2. The new `Keiki.CompositionAlternativeSpec` reports its five
   test cases all green:

       Keiki.CompositionAlternativeSpec
         alternative routing
           Left input advances t1, emits Left output [✔]
           Right input advances t2, emits Right output [✔]
         alternative round-trip
           reconstitute on a mixed-arm log lands at the expected state [✔]
         alternative analyses
           checkHiddenInputs returns [] [✔]
           isSingleValuedSym (withSymPred composite) returns True [✔]

3. `git diff src/Keiki/Composition.hs` shows additive changes only
   (no rewrites of `compose` or its substitution machinery). The
   existing `compose` tests still pass.

4. `git diff docs/research/composition-combinators-design.md`
   shows only the "What we shipped" subsection added.

Beyond compilation and tests, a peer reading the new spec can see
the routing behavior on a concrete event log without consulting any
other file.


## Idempotence and Recovery

The implementation steps are additive to `src/Keiki/Composition.hs`
and additive in `test/`. Reverting any one milestone is safe via
`git revert`. If M3 reveals that the lifters' types don't
mechanically resolve to the design record's signature, this EP's
Decision Log records the discrepancy and revises M2 / M3 in place
(per `agents/skills/exec-plan/PLANS.md`'s revision protocol — log
the revision rationale at the bottom of this file).

If the new spec module's hspec discovery doesn't pick it up
automatically, the manual fix is to add it to `test/Spec.hs`'s
explicit spec list (whatever style the existing `CompositionSpec`
uses).

If `cabal test all` reveals `isSingleValuedSym` returning `False`
on the composite when both halves are individually `True`, the
likely cause is an Either-arm type mismatch in the symbolic
translation; investigate by running `isSingleValuedSym` on the
lifted t1 alone (just the `InL`-arm portion of the composite) to
isolate the failing side.


## Interfaces and Dependencies

This plan introduces no new package dependencies. It edits the
following:

**Read:**

- `src/Keiki/Composition.hs` — for the `compose` precedent and the
  substitution machinery.
- `src/Keiki/Core.hs` — for `Edge`, `SymTransducer`, `OutTerm`,
  `Update`, `HsPred`, `solveOutput`, `checkHiddenInputs`.
- `src/Keiki/Symbolic.hs` — for `isSingleValuedSym`, `withSymPred`.
- `src/Keiki/Generics.hs` — for `Append`, `appendRegFile`, `Names`,
  `Disjoint`.
- `test/Keiki/CompositionSpec.hs` — for the `AlertSource` fixture
  pattern and the spec style.
- `docs/research/composition-combinators-design.md` — the
  authoritative design record for `alternative`.

**Write:**

- `src/Keiki/Composition.hs` — add `CompositeSum`, the lifters, and
  `alternative`.
- `test/Keiki/CompositionAlternativeSpec.hs` — the new spec module.
- `keiki.cabal` and `test/Spec.hs` — wire the spec into the suite.
- `docs/research/composition-combinators-design.md` — append "What
  we shipped" subsection.
- `docs/research/keiki-generics-design.md` — extend item F's MP-8
  paragraph.
- `docs/masterplans/8-composition-combinators-beyond-sequential-parallel-alternative-feedback-kleisli.md`
  — registry status + Progress tick.

**Required signatures at the end of M3:**

    data CompositeSum s1 s2 = InL !s1 | InR !s2

    alternative
      :: forall rs1 rs2 s1 s2 ci1 ci2 co1 co2.
         ( WeakenR rs1
         , Disjoint (Names rs1) (Names rs2)
         )
      => SymTransducer (HsPred rs1 ci1) rs1 s1 ci1 co1
      -> SymTransducer (HsPred rs2 ci2) rs2 s2 ci2 co2
      -> SymTransducer
           (HsPred (Append rs1 rs2) (Either ci1 ci2))
           (Append rs1 rs2)
           (CompositeSum s1 s2)
           (Either ci1 ci2)
           (Either co1 co2)

**Git trailers.** Every commit must include:

    MasterPlan: docs/masterplans/8-composition-combinators-beyond-sequential-parallel-alternative-feedback-kleisli.md
    ExecPlan: docs/plans/25-alternative-composition-combinator-on-symtransducer.md
    Intention: intention_01knjzws4qezz9w8b0743zfqv8
