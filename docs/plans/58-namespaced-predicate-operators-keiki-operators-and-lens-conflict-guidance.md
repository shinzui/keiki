---
id: 58
slug: namespaced-predicate-operators-keiki-operators-and-lens-conflict-guidance
title: "Namespaced predicate operators (Keiki.Operators) and lens-conflict guidance"
kind: exec-plan
created_at: 2026-06-06T14:41:11Z
intention: "intention_01ktensqv9ecmv5cd5jrbcfej7"
master_plan: "docs/masterplans/14-keiki-and-keiki-codec-json-dsl-improvements-surfaced-by-the-seihou-consumer-audit.md"
---

# Namespaced predicate operators (Keiki.Operators) and lens-conflict guidance

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

keiki gives transducer authors a small family of infix operators for writing guard
predicates — most importantly the four comparison operators `(.<)`, `(.<=)`, `(.>)`,
`(.>=)`, plus equality `(.==)`/`(./=)`, the logical `(.&&)`/`(.||)`, and the structural
arithmetic `(.+)`/`(.-)`/`(.*)`. These read nicely: a guard like `#onHand .>= lit 1` is
self-explanatory. The problem this plan fixes is a *name collision*. Projects that build on
the `lens` and `generic-lens` libraries — and especially projects whose shared "prelude"
module re-exports those libraries to every module — already bind some of these very names.
The sharpest clash is `(.>)`: in `lens`, `(.>)` is *focus composition* (compose two optics,
keeping the right one's focus); in keiki, `(.>)` is the *greater-than* comparison that builds
a predicate. When both are in scope, the bare `(.>)` is ambiguous and the module will not
compile.

Today a consumer works around this by *hiding* keiki's operator out of the lens side (or vice
versa) and re-importing it explicitly. We verified this in a real downstream service: the file
`/Users/shinzui/Keikaku/bokuno/keiro-runtime-jitsurei/services/hospital-capacity/src/HospitalCapacity/Domain/Capacity.hs`
opens (around line 27) with `import HospitalCapacity.Prelude hiding (Index, (.>))` and then
explicitly re-imports keiki's `(.>)`, `(.>=)`, `(.+)`, `(.-)` from `Keiki.Core`. That
`hiding ((.>))` dance works, but it is easy to get wrong, easy to forget, and undiscoverable —
a new author hits a confusing ambiguity error with no signposted fix.

After this change, two things exist that did not before. First, a new module
`Keiki.Operators` that re-exports exactly the keiki predicate/term operators (with their
original fixities) and nothing else, designed to be imported *qualified* — for example
`import qualified Keiki.Operators as K`, after which the author writes `x K..> y` and the bare
unqualified `(.>)` can belong entirely to `lens`. No `hiding` needed. Second, an explicit,
copy-pasteable recipe in the user guide that shows three ways to resolve the clash — the
`hiding ((.>))` approach, the qualified-`Keiki.Operators` approach, and (for guards authored
inside a builder block) the function-style guard verbs `B.requireGt`/`B.requireGe`/etc. that
never clash at all — and explains *when to reach for which*. Crucially, this plan is purely
additive: it does not touch or remove keiki's existing operators, so nothing that compiles
today stops compiling.

You can see it working two ways. (1) `cabal build keiki` succeeds with the new
`Keiki.Operators` module exposed. (2) `cabal test keiki-test` runs a new spec that imports
`Keiki.Operators` *qualified*, while a clashing unqualified `(.>)` is also in scope, builds a
predicate with `K..>`, and asserts it evaluates correctly — proving an author can keep
structural predicates without giving up the lens operator and without any `hiding` clause.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] M1: Create `src/Keiki/Operators.hs` re-exporting the operator set from `Keiki.Core` (fixities NOT restated — see Surprises). (2026-06-06)
- [x] M1: Add `Keiki.Operators` to `keiki.cabal` library `exposed-modules`. (2026-06-06)
- [x] M1: Create `test/Keiki/OperatorsQualifiedSpec.hs` (qualified-import + simulated-clash spec). (2026-06-06)
- [x] M1: Register `Keiki.OperatorsQualifiedSpec` in `keiki.cabal` test `other-modules` and in `test/Spec.hs` (import + `describe`). (2026-06-06)
- [x] M1: `cabal build keiki` and `cabal test keiki-test` both pass (304 examples, 0 failures; the 4 EP-58 examples pass). (2026-06-06)
- [ ] M2: Extend `docs/guide/generic-lens-and-label-reads.md` with a new operator-collision section (hiding recipe, qualified recipe, `requireGt` vs `requireGuard (x .> y)` guidance).
- [ ] M2: Cross-link the new section from `docs/guide/user-guide.md`.
- [ ] Final: Update Surprises/Decision Log/Outcomes; verify all acceptance criteria.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- **Restating fixities in a re-export module fails on GHC 9.12 / GHC2024.** The plan's M1
  text said to replicate the `infix` declarations and called it "harmless"; that is wrong on
  this toolchain. A fixity signature requires an *accompanying binding in the same module*
  — `cabal build` failed with `GHC-44432: The fixity signature for ‘.<’ lacks an accompanying
  binding` for every restated operator, because `Keiki.Operators` only re-exports the names,
  it does not bind them. The fix is to **omit** the fixity block entirely: a re-exported
  operator already carries its fixity from the defining module, so a qualified user
  (`x K..> y`) still gets `infix 4` from `Keiki.Core`. The module now carries an explanatory
  comment in place of the fixity lines. Verified: `cabal build keiki` succeeds and the
  qualified `K..>`/`K..<=`/`K..*`/`K..&&` examples parse and evaluate correctly. (2026-06-06)
- The spec did not need `evalTerm`, `Term`, or `lit`'s `Term` import beyond `lit` itself;
  `import Keiki.Core (HsPred, RegFile(..), evalPred, lit)` is the minimal set (the plan's
  draft import list also named `Term`/`evalTerm`, which `-Wall` would flag as unused). (2026-06-06)
- A test module named `Keiki.OperatorsSpec` **already exists** at
  `test/Keiki/OperatorsSpec.hs` (introduced by an earlier plan, EP-45) and is already
  registered in both `keiki.cabal` (test `other-modules`) and `test/Spec.hs`. It tests the
  *Core* operators directly (unqualified). To avoid collision and confusion, this plan's new
  spec is named `Keiki.OperatorsQualifiedSpec`. Do **not** reuse the `OperatorsSpec` name.
- `Keiki.Symbolic` already re-exports `module Keiki.Core` (see
  `src/Keiki/Symbolic.hs` line 76), so the operators are already reachable through
  `Keiki.Symbolic` as well as `Keiki.Core`. The new `Keiki.Operators` module deliberately
  re-exports from `Keiki.Core` directly (the canonical definition site) and exposes *only* the
  operators — that focused export list is the whole point.


## Decision Log

Record every decision made while working on the plan.

- Decision: Keep all existing keiki operators in `Keiki.Core` exactly as they are; this plan
  adds a re-export module and documentation only.
  Rationale: Removing or renaming `(.>)` etc. would break every current consumer (including the
  jitsurei service that imports them explicitly). The collision is resolvable additively, so
  there is no reason to take a breaking path.
  Date: 2026-06-06

- Decision: Add a `Keiki.Operators` module designed for *qualified* import, re-exporting the
  operator set (`(.<)`, `(.<=)`, `(.>)`, `(.>=)`, `(.==)`, `(./=)`, `(.&&)`, `(.||)`, `pnot`,
  `(.+)`, `(.-)`, `(.*)`, and the function-style term aliases `tadd`/`tsub`/`tmul`) from
  `Keiki.Core` with their original fixities replicated, and nothing else.
  Rationale: A focused module lets a consumer write `import qualified Keiki.Operators as K`
  and reach the predicate operators as `K..>` while leaving the unqualified `(.>)` to `lens`.
  No `hiding` clause is required. Re-exporting *only* the operators (not the entire Core API)
  keeps the qualified namespace small and predictable.
  Date: 2026-06-06

- Decision: Acknowledge that qualified use of a dot-prefixed operator is visually noisy
  (`x K..> y` reads as "K dot dot greater") and document it honestly, but ship the qualified
  module anyway as the primary programmatic escape.
  Rationale: It is the only mechanism that needs *zero* changes to the unqualified import list
  (no `hiding`), which is the most robust and least error-prone for the author. The noise is a
  cosmetic cost, not a correctness one.
  Date: 2026-06-06

- Decision: Do **not** add new function-style aliases for the *comparison* operators (e.g. a
  hypothetical `greaterThan`/`lessOrEqual`).
  Rationale: For the overwhelmingly common case — authoring a guard inside a builder
  `B.do`-block — the builder already provides clash-free function-style verbs
  (`requireLt`/`requireLe`/`requireGt`/`requireGe`/`requireEq`, plus the general `requireCmp`
  and `requireGuard`) in `src/Keiki/Builder.hs` (around lines 562–594). New comparison-name
  aliases would be almost entirely redundant with those verbs and would expand the API surface
  for little gain. The residual case (building a raw `HsPred` *value* with the operators —
  e.g. composing a sub-expression before handing it to `requireGuard`) is served by the
  qualified `Keiki.Operators` import. The documentation, not new aliases, is the primary
  deliverable here. If a future consumer demonstrates a concrete need for function-style
  comparison aliases, revisit this and record the new evidence.
  Date: 2026-06-06

- Decision: Name the new test spec `Keiki.OperatorsQualifiedSpec` (not `OperatorsSpec`).
  Rationale: `Keiki.OperatorsSpec` already exists for EP-45's Core-operator tests; reusing the
  name would collide. See Surprises & Discoveries.
  Date: 2026-06-06

- Decision: Put the new prose in the existing guide page
  `docs/guide/generic-lens-and-label-reads.md` (extending it) rather than creating a new page.
  Rationale: That page already covers the *parallel* `generic-lens`/`lens` interop story for
  label reads (`#slot`) and the `.=` write-operator clash (it was authored by an earlier plan,
  EP-49). The operator-name collision is the same family of problem, so it belongs alongside
  the existing material and should cross-reference it rather than duplicate it.
  Date: 2026-06-06


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

This plan touches the keiki library at `/Users/shinzui/Keikaku/bokuno/keiki`. You need only
this file and the repository to do the work. Read the files named below before editing; every
fact in this plan was verified against them on 2026-06-06.

Definitions of terms used here, in plain language:

- **Transducer / guard.** keiki models a state machine whose edges fire only when a *guard*
  (a boolean predicate over the machine's registers and the incoming command) is true. A guard
  is a value of type `HsPred rs ci` ("Haskell predicate over register-schema `rs` and command
  type `ci`"). The type alias `Pred rs ci` is the same type.
- **Term.** A `Term rs ci ifs r` is an expression that evaluates to a value of type `r` — for
  example a literal (`lit 1`), a register read (`#onHand`, or `reg @"onHand"`), or an
  arithmetic combination. Comparison operators take two `Term`s and produce an `HsPred`.
- **Operator vs. function-style.** keiki offers both. `a .>= b` (operator) and
  `B.requireGe a b` (function-style guard verb, used inside a builder block) express the same
  intent. Operators read better in raw predicates; function-style verbs never collide with
  other libraries' operator names.
- **`lens` / `generic-lens`.** Widely used Haskell libraries for "optics" (composable getters
  and setters for nested data). They define their own infix operators. `lens` defines `(.>)`
  as optic composition; that is the name that clashes with keiki's greater-than.
- **Service prelude.** A project-local module (e.g. `HospitalCapacity.Prelude`) that re-exports
  a batch of common imports — often including `lens`/`generic-lens` — so every module gets them
  with one `import`. This is what makes the clash *pervasive*: the lens `(.>)` is in scope in
  every module, including transducer modules that want keiki's `(.>)`.

Key files and exact facts (verified):

- `src/Keiki/Core.hs` is where every keiki operator is **defined and exported**. There is no
  `Keiki.Operators` module today. The relevant definitions:
  - Comparison (around line 691): `(.<), (.<=), (.>), (.>=) :: (Ord r, Typeable r) => Term rs ci ifs1 r -> Term rs ci ifs2 r -> HsPred rs ci`, each an alias for `PCmp` at a fixed `Cmp` (`CmpLt`/`CmpLe`/`CmpGt`/`CmpGe`). Fixity: `infix 4 .<, .<=, .>, .>=` (line 697).
  - Equality (line 679): `(.==) = PEq`, fixity `infix 4 .==` (line 681). Inequality (line 702): `a ./= b = PNot (PEq a b)`, fixity `infix 4 ./=` (line 704).
  - Logical (lines 709–713): `(.&&) = PAnd` with `infixr 3 .&&`; `(.||) = POr` with `infixr 2 .||`; and `pnot = PNot` (line 718, no fixity).
  - Arithmetic (lines 726–732): `(.+), (.-), (.*) :: (Num r, Typeable r) => Term rs ci ifs r -> Term rs ci ifs r -> Term rs ci ifs r`, aliases for `tadd`/`tsub`/`tmul`. Fixity: `infixl 6 .+, .-` (line 731) and `infixl 7 .*` (line 732).
  - Function-style term aliases `tadd, tsub, tmul` already exist (lines 670–675).
  - All of the above are listed in the module's export list (`module Keiki.Core (… , tadd, tsub, tmul, (.==), (.<), (.<=), (.>), (.>=), (./=), (.&&), (.||), pnot, (.+), (.-), (.*) , …)`, around lines 93–107).
- `src/Keiki/Builder.hs` provides the function-style **guard verbs** used inside a builder
  block (around lines 562–594): `requireEq`, `requireCmp`, and the four direction-specific
  `requireLt`/`requireLe`/`requireGt`/`requireGe`, all of type
  `… => Term … -> Term … -> EdgeBuilder rs ci co v w w ()`. There is also the general
  `requireGuard :: HsPred rs ci -> EdgeBuilder …` (used by all of the above). These verbs are
  the clash-free way to author comparisons *inside a builder block*: `B.requireGt x y` instead
  of `B.requireGuard (x .> y)`.
- `src/Keiki/Symbolic.hs` re-exports `module Keiki.Core` (line 76), so the operators are also
  reachable via `Keiki.Symbolic`.
- `keiki.cabal` lists the library's `exposed-modules` (around lines 56–68) and the test
  suite's `other-modules` (around lines 86–112). The test suite is `keiki-test`; it depends on
  `hspec`. `test/Spec.hs` is a **manual aggregator**: it `import qualified`s each spec module
  and calls each module's `spec` inside one `hspec $ do` block with a `describe` label.
- `docs/guide/generic-lens-and-label-reads.md` already documents the sibling interop problems
  (the `#slot` label-read shadowing and the `.=` write-operator clash) and gives the
  scope-your-imports discipline plus the `reg @"name"` / `=:` escapes. The new operator section
  extends this page. `docs/guide/user-guide.md` is the main guide and should gain a one-line
  cross-link.
- Verified downstream evidence of the problem:
  `/Users/shinzui/Keikaku/bokuno/keiro-runtime-jitsurei/services/hospital-capacity/src/HospitalCapacity/Domain/Capacity.hs`
  line 27: `import HospitalCapacity.Prelude hiding (Index, (.>))`, followed by an explicit
  import of `(.>)`, `(.>=)`, `(.+)`, `(.-)` from `Keiki.Core`.

Independence: this plan is fully self-contained and touches only new/peripheral files —
`src/Keiki/Operators.hs` (new), `keiki.cabal` (`exposed-modules` plus test `other-modules`),
`test/Keiki/OperatorsQualifiedSpec.hs` (new), `test/Spec.hs` (one import + one `describe`),
and two files under `docs/guide/`. It does **not** modify the operator definitions in
`Keiki.Core` (those stay; the new module only re-exports them), so it cannot conflict with any
other plan in the master plan and can run in parallel with EP-55/56/57/59/60.


## Plan of Work

The work splits into two independent, individually verifiable milestones. M1 delivers the
programmatic escape (the module + a proving test). M2 delivers the documentation, which the
audit names as the primary deliverable. Either milestone can be implemented first, but M1 is
described first because M2's prose references the module M1 creates.


### Milestone M1 — `Keiki.Operators` module, cabal wiring, and a proving spec

Scope: add the new re-export module, expose it in the cabal library, and add a test that
imports it *qualified* while a clashing unqualified `(.>)` is also in scope — proving the
collision is resolved without `hiding`. At the end of M1, `cabal build keiki` exposes
`Keiki.Operators` and `cabal test keiki-test` runs and passes the new spec.

Create `src/Keiki/Operators.hs`. It re-exports the operator set from `Keiki.Core` and replicates
the fixities verbatim (a re-export does **not** carry the original fixity declarations across
module boundaries automatically for the re-exported names in *this* module's namespace — but
qualified users get fixity from the defining module, so to be safe and explicit we restate them
here; restating identical fixities is harmless). The module body is just `import Keiki.Core (...)`
with the same names in the export list, plus the fixity lines. Write it as:

```haskell
-- | Re-exports of keiki's predicate and term operators, intended to be
-- imported __qualified__ so they cannot clash with the operators that
-- the @lens@ / @generic-lens@ libraries (or a service prelude that
-- re-exports them) bring into scope unqualified.
--
-- The sharpest clash is @(.>)@: in @lens@ it is optic composition, in
-- keiki it is the greater-than comparison that builds an 'HsPred'. With
--
-- @
-- import qualified Keiki.Operators as K
-- @
--
-- you write @x K..\> y@ for the keiki comparison and leave the bare
-- @(.>)@ to @lens@ — no @hiding@ clause required.
--
-- This module adds nothing new: every export here is defined in and
-- re-exported from "Keiki.Core". See @docs\/guide\/generic-lens-and-label-reads.md@
-- for the full import recipe and the @B.requireGt@-vs-@(.>)@ guidance.
module Keiki.Operators
  ( -- * Comparison (build an 'Keiki.Core.HsPred')
    (.<)
  , (.<=)
  , (.>)
  , (.>=)
  , (.==)
  , (./=)
    -- * Logical
  , (.&&)
  , (.||)
  , pnot
    -- * Structural arithmetic on 'Keiki.Core.Term's
  , (.+)
  , (.-)
  , (.*)
    -- * Function-style arithmetic aliases (clash-free already)
  , tadd
  , tsub
  , tmul
  ) where

import Keiki.Core
  ( (.<), (.<=), (.>), (.>=), (.==), (./=)
  , (.&&), (.||), pnot
  , (.+), (.-), (.*)
  , tadd, tsub, tmul
  )

-- Replicated fixities (must match src/Keiki/Core.hs exactly).
infix  4 .<, .<=, .>, .>=, .==, ./=
infixr 3 .&&
infixr 2 .||
infixl 6 .+, .-
infixl 7 .*
```

Note: do **not** add a module header language-pragma block unless the build complains — the
cabal `shared-extensions` import (see `keiki.cabal` around line 55) already turns on the
project's default extensions for every module, and this module needs no special ones.

Then expose the module: in `keiki.cabal`, add `Keiki.Operators` to the library's
`exposed-modules` list (alphabetical placement is between `Keiki.NoThunks` and
`Keiki.Profunctor`, around line 65).

Next, create the proving spec at `test/Keiki/OperatorsQualifiedSpec.hs`. The crucial design
point: the module imports `Keiki.Operators` **qualified as `K`**, and *also* brings a
clashing unqualified `(.>)` into scope (we simulate the `lens` clash with a tiny local
operator), then builds a predicate with `K..>` and asserts it evaluates correctly. The local
`(.>)` is deliberately a *different* operation (here, integer addition) so that if the
qualified path silently resolved to the wrong `(.>)` the test would compute the wrong value
and fail. Write it as:

```haskell
module Keiki.OperatorsQualifiedSpec (spec) where

import Test.Hspec
import Keiki.Core (HsPred, Term, RegFile(..), evalPred, evalTerm, lit)
import qualified Keiki.Operators as K

-- Simulate the lens clash: a local, unqualified (.>) that is NOT keiki's
-- greater-than. If the qualified K..> below accidentally resolved to this
-- one, the predicate would be ill-typed (Int, not HsPred) and would not
-- compile; if a plain (.>) were used it would shadow keiki's. The point is
-- that K..> reaches keiki's operator while (.>) stays free for other uses.
(.>) :: Int -> Int -> Int
a .> b = a + b
infixl 6 .>

-- A trivial command type; the operators here never read it.
data NoCmd = NoCmd deriving (Eq, Show)

-- Evaluate a predicate over the empty register file / NoCmd input.
runP :: HsPred '[] NoCmd -> Bool
runP pr = evalPred pr RNil NoCmd

-- A guard built entirely through the qualified import.
sampleGuard :: HsPred '[] NoCmd
sampleGuard = (lit (5 :: Int) K..> lit 3) K..&& (lit (2 :: Int) K..>= lit 2)

spec :: Spec
spec = do
  describe "qualified Keiki.Operators resolves the (.>) clash" $ do
    it "K..> builds keiki's greater-than predicate" $ do
      runP (lit (5 :: Int) K..> lit 3) `shouldBe` True
      runP (lit (3 :: Int) K..> lit 3) `shouldBe` False
    it "the local unqualified (.>) is still usable and is NOT keiki's" $
      (2 .> 3) `shouldBe` 5            -- our local addition, untouched
    it "a compound guard via qualified ops evaluates correctly" $
      runP sampleGuard `shouldBe` True
    it "arithmetic via qualified ops feeds a comparison" $
      runP (lit (10 :: Int) K..<= lit 3 K..* lit 4) `shouldBe` True
```

Then register the spec in two places. In `keiki.cabal`, add
`Keiki.OperatorsQualifiedSpec` to the test suite's `other-modules` (alphabetically right after
the existing `Keiki.OperatorsSpec`, around line 106). In `test/Spec.hs`, add
`import qualified Keiki.OperatorsQualifiedSpec` next to the other imports, and add a `describe`
line inside `main`, for example:

```haskell
  describe "Keiki.Operators (qualified import, EP-58)"   Keiki.OperatorsQualifiedSpec.spec
```

Acceptance for M1: from `/Users/shinzui/Keikaku/bokuno/keiki`, `cabal build keiki` succeeds
and `cabal test keiki-test` runs with the new spec's four examples passing.


### Milestone M2 — User-guide recipe and cross-link

Scope: document the collision and its three resolutions in
`docs/guide/generic-lens-and-label-reads.md`, and add a cross-link from
`docs/guide/user-guide.md`. At the end of M2 the guide contains an explicit
`hiding ((.>))` example, the qualified-`Keiki.Operators` alternative, and clear guidance on
when to use `B.requireGt` versus `B.requireGuard (x .> y)`.

Add a new section to `docs/guide/generic-lens-and-label-reads.md` (the page already covers the
parallel `#slot` and `.=` clashes; this new section sits alongside them — pick the next free
section number, currently §7, and update the "Pointers" section if it enumerates sections).
The section's prose must cover, in order:

1. **What clashes and why.** `lens` defines `(.>)` as optic composition; keiki defines `(.>)`
   as the greater-than comparison that builds a guard. A service prelude that re-exports `lens`
   puts the lens `(.>)` in scope everywhere, so a transducer module that also wants keiki's
   `(.>)` sees an ambiguous operator and fails to compile. The same shape can affect any other
   shared name, but `(.>)` is the one that bites in practice.

2. **Recipe A — hide and re-import (the existing workaround, shown honestly).** A code block
   showing the pattern verified in the hospital-capacity service:

   ```haskell
   -- Hide the clashing name out of the service prelude (or out of Prelude),
   -- then re-import keiki's operators explicitly.
   import MyApp.Prelude hiding ((.>))
   import Keiki.Core (lit, (.>), (.>=), (.+), (.-))
   ```

   Explain that this works and is fine for a module that uses only a handful of keiki
   operators, but is easy to forget (you must remember to extend the `hiding` list every time
   you reach for another clashing operator) and produces a confusing error if you don't.

3. **Recipe B — qualified `Keiki.Operators` (the no-`hiding` path).** A code block:

   ```haskell
   -- No hiding clause: the bare (.>) belongs to lens; keiki's lives under K.
   import MyApp.Prelude               -- lens (.>) etc. in scope, untouched
   import Keiki.Core (lit)
   import qualified Keiki.Operators as K

   guard = lit threshold K..< someTerm K..&& lit 0 K..<= otherTerm
   ```

   Be honest that `K..>` is visually noisy ("K dot dot greater"), but note it needs *zero*
   changes to the unqualified import list, which makes it the most robust choice when a module
   uses many keiki operators or when the author would rather not maintain a `hiding` list.

4. **Recipe C — function-style guard verbs (the best choice *inside a builder block*).** This
   is the key guidance the audit asks for. When the predicate is being conjoined into an edge's
   guard inside a `B.do` block, you do not need the operator at all: the builder already
   exposes clash-free verbs. A code block contrasting the two spellings:

   ```haskell
   import qualified Keiki.Builder as B

   -- Operator form (needs Recipe A or B to dodge the (.>) clash):
   --   B.requireGuard (someTerm .> lit 0)
   -- Function-style verb (no operator, so no clash, ever):
   edge = B.do
     B.requireGt someTerm (lit 0)     -- a > 0
     B.requireGe other    (lit 1)     -- other >= 1
   ```

   State the rule plainly: **prefer `B.requireGt` / `B.requireGe` / `B.requireLt` /
   `B.requireLe` / `B.requireEq` when you are authoring a guard inside a builder block** — they
   read well, never clash, and need no import gymnastics. Reach for `B.requireGuard (x .> y)`
   (with Recipe A or B) only when you must build a *compound* predicate value first — for
   example combining several comparisons with `.&&`/`.||` into one `HsPred` before handing it
   to `requireGuard`, or when constructing an `HsPred` value outside any builder block. In that
   raw-predicate case the qualified `Keiki.Operators` import (Recipe B) is the cleanest.

5. **Why we did not add `greaterThan`-style aliases.** A short paragraph recording that
   function-style *comparison* aliases were considered and rejected as redundant with the
   builder verbs for the common case; the qualified module covers the raw-predicate case.

Then add a cross-link in `docs/guide/user-guide.md`: wherever the guide first introduces the
comparison operators (or in its interop/pointers area), add a sentence pointing to the new
section, e.g. "If your project re-exports `lens`/`generic-lens` and the bare `(.>)` clashes,
see `docs/guide/generic-lens-and-label-reads.md` for the import recipe and the
`requireGt`-vs-`requireGuard` guidance."

Acceptance for M2: the guide file contains an explicit `hiding ((.>))` example, a qualified
`Keiki.Operators` example, and the `B.requireGt` vs `B.requireGuard (x .> y)` guidance; and
`user-guide.md` links to it. (These are documentation outcomes; verify by reading the rendered
sections.)


## Concrete Steps

All commands run from `/Users/shinzui/Keikaku/bokuno/keiki`.

1. Create the module file `src/Keiki/Operators.hs` with the contents shown in M1.

2. Edit `keiki.cabal`: add `Keiki.Operators` to the library `exposed-modules` (between
   `Keiki.NoThunks` and `Keiki.Profunctor`).

3. Create `test/Keiki/OperatorsQualifiedSpec.hs` with the contents shown in M1.

4. Edit `keiki.cabal`: add `Keiki.OperatorsQualifiedSpec` to the test suite `other-modules`
   (right after `Keiki.OperatorsSpec`).

5. Edit `test/Spec.hs`: add `import qualified Keiki.OperatorsQualifiedSpec` and a matching
   `describe "Keiki.Operators (qualified import, EP-58)" Keiki.OperatorsQualifiedSpec.spec`
   line in `main`.

6. Build and test:

   ```bash
   cabal build keiki
   cabal test keiki-test
   ```

   Expected: the build reports `Keiki.Operators` compiling, and the test run ends with all
   examples passing, including a group labelled
   `Keiki.Operators (qualified import, EP-58)` whose four examples read like:

   ```text
   Keiki.Operators (qualified import, EP-58)
     qualified Keiki.Operators resolves the (.>) clash
       K..> builds keiki's greater-than predicate
       the local unqualified (.>) is still usable and is NOT keiki's
       a compound guard via qualified ops evaluates correctly
       arithmetic via qualified ops feeds a comparison
   ```

7. Edit `docs/guide/generic-lens-and-label-reads.md` per M2 (new operator-collision section +
   pointers update).

8. Edit `docs/guide/user-guide.md` to add the cross-link.

9. Re-run `cabal test keiki-test` to confirm nothing regressed.


## Validation and Acceptance

The plan is complete when all of the following hold:

- `cabal build keiki` succeeds and `Keiki.Operators` appears as a compiled exposed module.
- `cabal test keiki-test` passes, including the new
  `Keiki.OperatorsQualifiedSpec` group. The `the local unqualified (.>) is still usable and is
  NOT keiki's` example is the load-bearing proof: it shows an unqualified clashing `(.>)`
  coexisting in the same module with keiki's operators reached via `K..>`, with **no** `hiding`
  clause anywhere in that module. This directly demonstrates the audit's third acceptance
  criterion — "a user can avoid infix conflicts without giving up structural predicates".
- `docs/guide/generic-lens-and-label-reads.md` contains an explicit `import … hiding ((.>))`
  example (audit criterion 1), the qualified-`Keiki.Operators` alternative, and prose that
  explains when to use `B.requireGt` versus `B.requireGuard (x .> y)` (audit criterion 2).
- `docs/guide/user-guide.md` links to the new section.

Beyond-compilation evidence: the spec does not merely typecheck — it evaluates the predicates
with `evalPred` and asserts concrete boolean results, and it asserts the local `(.>)` still
computes its own (different) value. That combination proves both that the qualified path
reaches keiki's real operator and that the unqualified name remains free for `lens`.


## Idempotence and Recovery

Every step is additive and safe to repeat. Re-running the edits is harmless: adding a module
name that is already present in `keiki.cabal` would be a duplicate the build flags, so if a
step seems already done, read the file first and skip it. If `cabal build` fails on a missing
module, confirm the file path matches the module name exactly (`src/Keiki/Operators.hs` ↔
`module Keiki.Operators`) and that the cabal `exposed-modules` entry is spelled identically.
If `cabal test` fails to find `Keiki.OperatorsQualifiedSpec`, confirm it is listed in both the
test `other-modules` and imported in `test/Spec.hs`. None of these changes is destructive;
to roll back, delete the two new files and revert the four small edits (`keiki.cabal` twice,
`test/Spec.hs`, and the two guide files).


## Interfaces and Dependencies

Libraries/modules used and why:

- `Keiki.Core` (`src/Keiki/Core.hs`) — the definition site of every operator; `Keiki.Operators`
  re-exports from it. Unchanged by this plan.
- `Keiki.Builder` (`src/Keiki/Builder.hs`) — provides the function-style guard verbs
  (`requireGt`/`requireGe`/`requireLt`/`requireLe`/`requireEq`/`requireCmp`/`requireGuard`)
  that the guide recommends for in-builder guards. Unchanged by this plan; referenced in docs.
- `hspec` — the test framework the `keiki-test` suite already uses.

What must exist at the end of each milestone:

- End of M1: a module `Keiki.Operators` exposing exactly
  `(.<)`, `(.<=)`, `(.>)`, `(.>=)`, `(.==)`, `(./=)`, `(.&&)`, `(.||)`, `pnot`,
  `(.+)`, `(.-)`, `(.*)`, `tadd`, `tsub`, `tmul`, with fixities matching `Keiki.Core`
  (`infix 4` for the comparisons/equality, `infixr 3`/`infixr 2` for `(.&&)`/`(.||)`,
  `infixl 6`/`infixl 7` for `(.+)`,`(.-)`/`(.*)`); the cabal library exposing it; and the test
  module `Keiki.OperatorsQualifiedSpec` exporting `spec :: Spec`, registered in `keiki.cabal`
  and `test/Spec.hs`.
- End of M2: `docs/guide/generic-lens-and-label-reads.md` containing the operator-collision
  section, and `docs/guide/user-guide.md` cross-linking it.


## Git / Process

Commit to the current branch (`master`); do **not** create a feature branch. Use Conventional
Commits. Two commits are natural — one per milestone. Every commit must carry these trailers:

```text
MasterPlan: docs/masterplans/14-keiki-and-keiki-codec-json-dsl-improvements-surfaced-by-the-seihou-consumer-audit.md
ExecPlan: docs/plans/58-namespaced-predicate-operators-keiki-operators-and-lens-conflict-guidance.md
Intention: intention_01ktensqv9ecmv5cd5jrbcfej7
```

Suggested commit subjects:

```text
feat(operators): add Keiki.Operators re-export module for qualified import
docs(guide): document lens/(.>) operator clash recipe and requireGt guidance
```
