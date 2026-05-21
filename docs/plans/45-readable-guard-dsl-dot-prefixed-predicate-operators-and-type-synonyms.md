---
id: 45
slug: readable-guard-dsl-dot-prefixed-predicate-operators-and-type-synonyms
title: "Readable guard DSL: dot-prefixed predicate operators and type synonyms"
kind: exec-plan
created_at: 2026-05-21T00:54:45Z
intention: "intention_01ks404p49en58h61yh8nc3nct"
---

# Readable guard DSL: dot-prefixed predicate operators and type synonyms

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

A keiki aggregate author writes the rules of a workflow as *guards* — boolean
conditions on an edge of a state machine that decide whether a command is
accepted. Today those guards are written by spelling out the names of the
predicate data constructors directly. A realistic guard reads like this (taken
verbatim from `jitsurei/src/Jitsurei/LoanApplication.hs`):

    approvalGuard :: HsPred LoanAppRegs LoanCmd
    approvalGuard =
      PCmp CmpGe (proj (#appCreditScore :: Index LoanAppRegs Int))
                 (lit approvalThresholdScore)
        `PAnd`
      PEq (proj (#appEmploymentVerified :: Index LoanAppRegs Bool)) (lit True)
        `PAnd`
      PCmp CmpLe (proj (#appRequestedAmount :: Index LoanAppRegs Money))
                 (tmul (proj (#appCreditScore :: Index LoanAppRegs Int))
                       (lit 1000))

The logic — "credit score at least the threshold, employment verified, and the
requested amount no more than score times 1000" — is buried under the
constructor names `PCmp`, `CmpGe`, `PAnd`, `PEq`, `tmul`. The relation being
tested (`>=`, `<=`, `==`) is a *tag argument* (`CmpGe`, `CmpLe`) rather than
something you can see between the two operands. After this change the same guard
reads as the inequality it actually is:

    approvalGuard :: Pred LoanAppRegs LoanCmd
    approvalGuard =
           proj (#appCreditScore :: Index LoanAppRegs Int) .>= lit approvalThresholdScore
      .&&  proj (#appEmploymentVerified :: Index LoanAppRegs Bool) .== lit True
      .&&  proj (#appRequestedAmount :: Index LoanAppRegs Money)
             .<= proj (#appCreditScore :: Index LoanAppRegs Int) .* lit 1000

Concretely, after this change an aggregate author can:

  * Write ordering guards with infix relational operators that read in the same
    direction as the comparison: `a .>= b`, `a .<= b`, `a .< b`, `a .> b`,
    `a ./= b` — mirroring the `(.==)` operator that already exists for equality.
  * Combine predicates with `.&&` (and) / `.||` (or) and negate with `pnot`,
    instead of nesting `PAnd` / `POr` / `PNot` constructors.
  * Build arithmetic operands with `.+` / `.-` / `.*` instead of the prefix
    `tadd` / `tsub` / `tmul` smart constructors.
  * Write the verbose, parameter-repeating type signatures
    `SymTransducer (HsPred rs ci) rs s ci co` as `Guarded rs s ci co`, the
    guard carrier `HsPred rs ci` as `Pred rs ci`, and the SBV-backed
    `SymTransducer (SymPred rs ci) rs s ci co` as `SymGuarded rs s ci co`.

You can *see it working* in two ways. First, a new focused test
(`test/Keiki/OperatorsSpec.hs`) evaluates each operator against concrete inputs
and asserts it computes exactly the relation it names — and asserts each alias is
behaviourally identical to the data constructor it stands for. Second, the
flagship worked example `jitsurei/src/Jitsurei/LoanApplication.hs` is rewritten
to use the new operators and type synonyms, and its entire existing test suite
(behavioural, builder, view, and **symbolic** specs) stays green — proving the
rewrite changed how the guards *read* without changing what they *mean* or how
the SBV solver sees them.

This change is purely additive: the predicate data constructors (`PCmp`,
`CmpGe`, `PEq`, `PAnd`, …) and the smart constructors (`tadd`, …) remain
exported and unchanged. The operators and type synonyms are thin definitional
aliases for them.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] M1: Add comparison operators `.<` `.<=` `.>` `.>=` `./=`, logical `.&&`
      `.||` `pnot`, and arithmetic `.+` `.-` `.*` to `src/Keiki/Core.hs` with
      fixity declarations; extend the module export list. (2026-05-20)
- [x] M1: Add `test/Keiki/OperatorsSpec.hs`; wire it into `test/Spec.hs` and the
      `keiki.cabal` test-suite `other-modules`. Each operator proven to compute
      its named relation and to match its underlying constructor. (2026-05-20)
- [x] M1: `cabal build keiki && cabal test keiki-test` green — 248 examples, 0
      failures; the `Keiki.Core operators (EP-45)` group passes. (2026-05-20)
- [x] M2: Add type synonyms `Pred` and `Guarded` to `src/Keiki/Core.hs` (and
      its export list) and `SymGuarded` to `src/Keiki/Symbolic.hs` (and its
      export list). (2026-05-20)
- [x] M2: Compile-prove the synonyms are interchangeable with their expansions
      (`Pred`-annotated `sampleGuard` round-trips through `evalPred`, which takes
      `HsPred`). `cabal build all` green; `cabal test keiki-test` 249 examples,
      0 failures incl. the `type synonyms` example. (2026-05-20)
- [x] M3: Rewrite the guards and signatures in
      `jitsurei/src/Jitsurei/LoanApplication.hs` to use the new operators and
      `Pred` / `Guarded`. `cabal test jitsurei-test` green (incl. the symbolic
      spec) — 96 examples, 0 failures; all four `Jitsurei.LoanApplication*`
      groups pass. Only LoanApplication.hs changed. (2026-05-20)
- [x] M3: (Optional sweep) adopt the operators/synonyms in the other jitsurei
      aggregates that hand-write `HsPred` (`UserRegistration.hs`,
      `UserRegistrationV0.hs`) — rewrote each `PAnd isConfirm (… .== …)` guard
      to `isConfirm .&& (… .== …)`. `cabal test jitsurei-test` 96 examples, 0
      failures. Separate commit from the flagship. (2026-05-20)
- [x] M4: Document the operator set and type synonyms — module haddock in
      `src/Keiki/Core.hs`, the authoring guide (`docs/guide/user-guide.md` §3.4
      + glossary), and a foundations pointer (`docs/foundations/05-…md`); SBV
      qualified-import caveat recorded. `cabal haddock keiki` exit 0. (2026-05-20)
- [x] M4: Final `cabal test all` green — jitsurei 96, keiki 249,
      keiki-codec-json 40, keiki-codec-json-test 7; all 0 failures. Outcomes &
      Retrospective filled. (2026-05-20)
- [x] M5 (user-requested, mid-flight): sweep **all** jitsurei aggregates and the
      user-facing guides to the operator/synonym surface, not just the flagship.
      All `SymTransducer (HsPred …)` aggregate signatures → `Guarded`; remaining
      `PAnd`/`PNot` guards → `.&&`/`pnot`; tutorial/guide guard examples and
      concrete aggregate signatures rewritten. `cabal test all` green. (2026-05-20)


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- The whole change was zero-friction precisely because every alias is
  definitional. No pre-existing test needed editing across all four suites
  (`cabal test all`: jitsurei 96, keiki 249, keiki-codec-json 40,
  keiki-codec-json-test 7 — all 0 failures), which is the strongest evidence the
  aliases are faithful synonyms (the Validation section flagged any test edit as
  a bug-in-the-plan signal; none was needed).

- The `LoanApplication.hs` AST was byte-for-byte preserved through the rewrite,
  so the SBV-backed `Jitsurei.LoanApplication (symbolic)` spec passed unchanged
  — direct evidence the solver still sees the same structure after the surface
  swap.

- `git status` after the M3 flagship edit showed *only*
  `jitsurei/src/Jitsurei/LoanApplication.hs` modified, confirming the flagship
  diff is reviewable in isolation (per the Validation section's
  `git show --stat HEAD` check).

- The doc/jitsurei full sweep (M5) surfaced a useful distinction: aggregate
  *definition* signatures collapse cleanly to `Guarded` (readability win), but
  the *combinator/class* signatures in `composition.md`/`profunctor.md` are
  better left spelled out — they teach how `rs`/`ci` move under composition, and
  `Guarded` would hide that. Recorded in the Decision Log.


## Decision Log

Record every decision made while working on the plan.

- Decision: Operators are dot-*prefixed* (`.>=`, `.&&`, `.+`), mirroring the
  existing `(.==)`.
  Rationale: The user chose this style over suffix-dot (`>=.`) and over word
  aliases (`pGe`). It keeps the predicate DSL visually consistent with the
  `(.==)` operator and the builder's `(.=)` slot-assignment operator already in
  the codebase (`src/Keiki/Core.hs:610`, `src/Keiki/Builder.hs:359`).
  Date: 2026-05-21

- Decision: Deliver **both** value-level operators and type synonyms in one
  plan.
  Rationale: The user picked "Both layers" — a single coherent readability pass.
  The two are independent (separate milestones) but share one purpose and one
  demonstration target (LoanApplication), so they belong together.
  Date: 2026-05-21

- Decision: Aliases are purely additive; the data constructors (`PCmp`, `PEq`,
  `PAnd`, `PNot`, `CmpGe`, …) and smart constructors (`tadd`/`tsub`/`tmul`) stay
  exported and unchanged.
  Rationale: Existing code, tests, and the SBV translator pattern-match on the
  constructors. A definitional alias (`(.>=) = PCmp CmpGe`) produces the
  identical AST, so nothing downstream needs to change to keep working; the
  rewrite of LoanApplication is a *demonstration*, not a forced migration.
  Date: 2026-05-21

- Decision: Fixities follow the standard Haskell numeric/relational/boolean
  scheme: arithmetic `.* ` at `infixl 7`, `.+`/`.-` at `infixl 6`; relational
  `.<` `.<=` `.>` `.>=` `./=` at `infix 4` (same as the existing `.==`);
  logical `.&&` at `infixr 3` and `.||` at `infixr 2`.
  Rationale: Matches `Prelude`'s `(*)`/`(+)`/`(<)`/`(&&)`/`(||)` so an author's
  intuition about precedence transfers directly. It makes
  `a .<= b .* c` parse as `a .<= (b .* c)` and
  `p .&& q .|| r` parse as `(p .&& q) .|| r`, which is what a reader expects.
  Date: 2026-05-21

- Decision: Type-synonym names are `Pred rs ci`, `Guarded rs s ci co`
  (in `Keiki.Core`), and `SymGuarded rs s ci co` (in `Keiki.Symbolic`).
  Rationale: `Pred` is the obvious short form of `HsPred`; `Guarded` names "a
  transducer whose edges carry guards" and collapses the
  `rs`/`ci`-repeating `SymTransducer (HsPred rs ci) rs s ci co`. `SymGuarded`
  is the SBV-carrier analogue. None of these names is currently bound anywhere
  in the library (verified by grep), so they introduce no clash.
  Date: 2026-05-21

- Decision: Expand the demonstration scope (mid-flight, at the user's explicit
  request: "ensure to update the docs and jitsurei to use the operators since
  they are easier to read") from the flagship LoanApplication to **every**
  jitsurei aggregate and **every** user-facing guide.
  Rationale: The synonyms/operators are definitional aliases (same AST, same
  types), so the sweep is risk-free and `cabal test all` stays green. Concretely:
  (a) every `SymTransducer (HsPred …)` aggregate signature in
  `jitsurei/src/Jitsurei/{LoanApplication,Loan,EmailDelivery,UserRegistration,
  UserRegistrationV0,CoreBankingSync,OrderCart,LoanWorkflow}.hs` → `Guarded`
  (and `[Edge (HsPred …)]` / helper sigs → `Pred`); (b) the remaining
  `PAnd`/`PNot` value-level guards in LoanApplication → `.&&`/`pnot`;
  (c) the guard examples and concrete aggregate signatures in
  `docs/guide/{user-guide,loan-application-tutorial,ast-drop-down,
  multi-event-commands,composition,profunctor,symbolic-ci,why-smt}.md` →
  operators/`Guarded`.
  Rationale for what was *left* explicit: the **combinator and class type
  signatures** in `composition.md`/`profunctor.md` (e.g. `compose`, `lmapCi`,
  the `Profunctor` methods) keep the spelled-out `SymTransducer (HsPred rs ci) …`
  form, because those docs exist to teach how the `rs`/`ci` parameters move
  under composition — collapsing them into `Guarded` would hide the very plumbing
  being taught. Likewise the conceptual "SBV maps `PEq`/`PAnd`/`PCmp`…" prose in
  `why-smt.md`/`symbolic-ci.md` keeps the constructor names (it describes the
  AST/translation), with a one-line pointer added to the operator surface.
  Date: 2026-05-20


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

**Outcome (all milestones complete, 2026-05-20).** The readable guard DSL is
delivered exactly as the Purpose section promised. An aggregate author can now
write ordering guards as the inequalities they are
(`proj #appCreditScore .>= lit approvalThresholdScore`), combine them with
`.&&`/`.||`/`pnot`, build operands with `.+`/`.-`/`.*`, and type guards/transducers
with `Pred`/`Guarded`/`SymGuarded` instead of the parameter-repeating
`SymTransducer (HsPred rs ci) rs s ci co`.

Against the two "see it working" criteria from the Purpose:

  1. *Focused operator test* — `test/Keiki/OperatorsSpec.hs` proves each operator
     computes its named relation and is behaviourally identical to the data
     constructor it aliases (grid checks against `PCmp CmpGe`, `PEq`,
     `PNot . PEq`), plus fixity (`lit 2 .+ lit 3 .* lit 4 == 14`) and a
     type-synonym round-trip. Visible as the `Keiki.Core operators (EP-45)` group
     in `cabal test keiki-test` (249 examples, 0 failures).

  2. *Flagship semantic preservation* — `jitsurei/src/Jitsurei/LoanApplication.hs`
     reads through the operators while its entire pre-existing suite — behavioural,
     builder, view, **and symbolic** — stays green unchanged (96 examples), proving
     the rewrite changed how guards *read*, not what they *mean* or how the SBV
     solver sees them.

**Beyond the original plan (M5, user-requested mid-flight).** At the user's
explicit request, the adoption was extended from the flagship to *every* jitsurei
aggregate (all eight modules now use `Guarded`/`Pred`; remaining `PAnd`/`PNot`
guards now use `.&&`/`pnot`) and *every* user-facing guide (guard examples and
concrete aggregate signatures rewritten to the operator/synonym surface). The
combinator/class type signatures in `composition.md`/`profunctor.md` and the
conceptual "SBV maps `PEq`/`PAnd`/`PCmp`…" prose were deliberately left in
constructor form (with operator pointers added) — see the Decision Log for the
rationale.

**Gaps / non-goals.** The change is purely additive: the data constructors
(`PCmp`, `PEq`, `PAnd`, …) and smart constructors (`tadd`/`tsub`/`tmul`) remain
exported and unchanged, so no downstream consumer is forced to migrate. `PInCtor`
keeps its `matchInCtor` helper (no operator — it is a constructor-match, not a
relation). The escape-hatch terms `TApp1`/`TApp2` intentionally have no operator.

**Lesson.** Definitional aliasing is the cheapest possible readability win: because
`(.>=) = PCmp CmpGe` (etc.) produce the identical AST, the entire surface change —
library, eight aggregates, and the docs — landed without editing a single
pre-existing test assertion, and `cabal test all` is green end-to-end.


## Context and Orientation

This section assumes no prior knowledge of the repository. Read it before editing.

**What keiki is.** keiki is a Haskell library for the pure core of event
sourcing and workflow engines. Its central data type is a *symbolic-register
transducer*: a finite control graph (vertices and edges) augmented with a
typed *register file* (named, typed mutable cells) that edges read and update.
An *edge* fires when its *guard* (a boolean predicate over the registers and
the current input command) is satisfied; on firing it updates registers and
emits zero or more output events. The whole thing is `SymTransducer` in
`src/Keiki/Core.hs`.

**The terms of art used in this plan.**

  * *Register file* — a heterogeneous, type-indexed tuple of named cells. Its
    type is `RegFile (rs :: [Slot])` where `Slot = (Symbol, Type)` — a list of
    `(name, value-type)` pairs. Defined at `src/Keiki/Core.hs:132`.
  * *Term* — a pure expression that reads registers and the input command and
    produces a value: `Term rs ci r` (registers `rs`, input/command type `ci`,
    result `r`). Built with `lit` (a constant), `proj` (read a register),
    `inpCtor` (read a field of the input command), and the arithmetic smart
    constructors `tadd`/`tsub`/`tmul`. Defined at `src/Keiki/Core.hs:210`.
  * *Predicate* — the guard AST `HsPred rs ci`, a tree of boolean combinators
    over `Term`s. Its constructors (defined at `src/Keiki/Core.hs:427`) are:
    `PTop` (always true), `PBot` (always false), `PAnd`, `POr`, `PNot`,
    `PEq` (equality of two terms), `PInCtor` (the input is a named
    constructor), and `PCmp` (an ordering comparison).
  * *Cmp* — the four-way ordering tag carried by `PCmp`:
    `data Cmp = CmpLt | CmpLe | CmpGt | CmpGe`, meaning `<` / `<=` / `>` / `>=`.
    Defined at `src/Keiki/Core.hs:462`. `PCmp CmpGe a b` means "`a >= b`".
    Note there is intentionally no "equal" `Cmp`; equality lives in `PEq`.
  * *Smart constructor* — a plain function that builds an AST node, used so the
    raw constructor need not be written by hand. `tadd = TArith OpAdd`
    (`src/Keiki/Core.hs:604`); `(.==) = PEq` with `infix 4`
    (`src/Keiki/Core.hs:610`). The operators this plan adds are exactly more
    smart constructors of this kind.
  * *BoolAlg / SymPred* — `HsPred` is a syntactic guard carrier. For symbolic
    analysis (deciding whether two guards can both fire, extracting a
    satisfying input) the library wraps it as
    `SymPred (rs :: [Slot]) (ci :: Type)`
    (`newtype SymPred … = SymPred { unSymPred :: HsPred rs ci }`, defined at
    `src/Keiki/Symbolic.hs:554`), and translates it to the SBV SMT library.
    Edges of a transducer can carry either carrier; the type parameter `phi`
    of `SymTransducer phi rs s ci co` is the guard carrier.

**Where things live.**

  * `src/Keiki/Core.hs` — the pure core: `RegFile`, `Term`, `HsPred`, `Cmp`,
    `Update`, `OutTerm`, `SymTransducer`, the smart constructors (`lit`,
    `proj`, `inpCtor`, `tadd`/`tsub`/`tmul`, `(.==)`), and the evaluators
    (`evalTerm`, `evalPred`, `evalOut`). **All new operators and the `Pred` /
    `Guarded` type synonyms go here.** The export list is the literal list at
    the top of the module, `src/Keiki/Core.hs:23`–`99`.
  * `src/Keiki/Symbolic.hs` — the SBV-backed symbolic surface; defines
    `SymPred` and re-exports all of `Keiki.Core` (so the new operators are
    automatically available to anyone importing `Keiki.Symbolic`). **The
    `SymGuarded` synonym goes here.** Its export list is at
    `src/Keiki/Symbolic.hs:46`–`76`; note it imports `Data.SBV` *qualified* as
    `SBV` (`src/Keiki/Symbolic.hs:86`).
  * `src/Keiki/Builder.hs` — the monadic edge-builder. It already offers guard
    conveniences `requireEq`, `requireGuard`, `requireCmp`, and
    `requireLt`/`requireLe`/`requireGt`/`requireGe`
    (`src/Keiki/Builder.hs:490`–`522`). These keep working unchanged; an author
    using the builder can pass a whole operator-built predicate to
    `requireGuard`, e.g. `B.requireGuard (proj #x .>= lit 100 .&& …)`. No
    builder edits are required by this plan.
  * `jitsurei/src/Jitsurei/LoanApplication.hs` — the worked example with the
    most realistic hand-written guards (`readyForReviewGuard` at line 416,
    `approvalGuard` at line 430, the `loanApplication` transducer at line 444).
    This is the migration/demonstration target.
  * `test/Spec.hs` — the library's hspec entry point. It does **not** use
    auto-discovery; each spec module is imported and listed explicitly
    (`import qualified Keiki.…Spec` plus a `describe … .spec` line). A new
    spec module must be added in both places **and** in the `keiki.cabal`
    test-suite `other-modules` list.
  * `keiki.cabal` — the package file. The library stanza begins at line 54
    (`exposed-modules`), the test-suite stanza at line 81
    (`test-suite keiki-test`, with `other-modules` listing every spec). The
    shared GHC extensions (line 37, `common shared-extensions`) include
    `OverloadedLabels`, `OverloadedRecordDot`, and `GHC2024` as the language.
  * `cabal.project` lists the packages: `.` (the `keiki` library + its test
    suite), `jitsurei` (the worked examples + their test suite
    `jitsurei-test`), and the two `keiki-codec-json*` packages.

**Why dot-prefixed operators are safe here (three potential clashes, each
checked).**

  1. *`Prelude`.* None of `.<` `.<=` `.>` `.>=` `./=` `.&&` `.||` `.+` `.-`
     `.*` is exported by `Prelude`. No clash.
  2. *SBV.* `Data.SBV` *does* export `.==`, `./=`, `.<`, `.<=`, `.>`, `.>=`,
     `.&&`, `.||` (its symbolic operators). But `Keiki.Symbolic` imports SBV
     **qualified** (`import qualified Data.SBV as SBV`), so inside the library
     these are written `SBV..<` etc. and never collide with the unqualified
     `Keiki.Core` operators. This is already true today for `(.==)`: Core
     exports it unqualified and the SBV translator uses `SBV..==`. Adding more
     dot-operators changes nothing about this arrangement.
  3. *`OverloadedRecordDot`.* This extension makes `expr.field` (no surrounding
     spaces) parse as record-field access. A dot-*prefixed operator written
     with spaces*, `a .>= b`, is a distinct lexical token and is unaffected.
     Proof it coexists: `jitsurei/src/Jitsurei/UserRegistration.hs` already
     uses `… .== proj (…)` (the `.==` operator) in the same modules that use
     `d.fieldName` record-dot projection. The new operators behave identically.
     The one caution — which the docs in M4 will state — is to keep spaces
     around the operators (`lit price .* lit x`, not `lit price.*lit x`), which
     is already the house style.


## Plan of Work

The work is four milestones. M1 (operators) and M2 (synonyms) are independent
and could be done in either order; M1 first is natural because the operators
carry most of the readability win. M3 demonstrates both on a real aggregate.
M4 documents. Each milestone leaves the tree compiling and the test suite green.


### Milestone 1 — Value-level predicate & term operators

Scope: add the operator aliases to `src/Keiki/Core.hs`, export them, and prove
each one with a focused test. At the end of this milestone an author can write
guards with infix relational/logical/arithmetic operators, and the new
`test/Keiki/OperatorsSpec.hs` demonstrates that each operator computes the
relation it names and is behaviourally identical to the constructor it aliases.

Add the following definitions to `src/Keiki/Core.hs`, in the
"Helpers (the user-facing DSL surface)" region immediately after the existing
`(.==)` definition (`src/Keiki/Core.hs:609`–`612`). Keep the same indentation
and comment density as the surrounding smart constructors.

    -- * Predicate & term operators (readable guard DSL) ----------------------

    -- | Ordering-guard operators. Each is an alias for 'PCmp' at a fixed
    -- 'Cmp': @a .>= b@ is @'PCmp' 'CmpGe' a b@ (i.e. @a >= b@); @a .< b@ is
    -- @'PCmp' 'CmpLt' a b@; and so on. Same fixity as '(.==)' (@infix 4@):
    -- relational operators do not chain, sit below the arithmetic operators
    -- ('.+'/'.-'/'.*'), and above the logical ones ('.&&'/'.||').
    (.<), (.<=), (.>), (.>=)
      :: (Ord r, Typeable r) => Term rs ci r -> Term rs ci r -> HsPred rs ci
    (.<)  = PCmp CmpLt
    (.<=) = PCmp CmpLe
    (.>)  = PCmp CmpGt
    (.>=) = PCmp CmpGe
    infix 4 .<, .<=, .>, .>=

    -- | Inequality guard. @a ./= b@ is @'pnot' (a '.==' b)@, i.e.
    -- @'PNot' ('PEq' a b)@. Mirrors 'Prelude.(/=)' against the existing
    -- '(.==)'.
    (./=) :: (Eq r, Typeable r) => Term rs ci r -> Term rs ci r -> HsPred rs ci
    a ./= b = PNot (PEq a b)
    infix 4 ./=

    -- | Conjunction / disjunction of predicates. Aliases for 'PAnd' / 'POr',
    -- mirroring 'Prelude.(&&)' / 'Prelude.(||)' in fixity (@infixr 3@ /
    -- @infixr 2@), so @p .&& q .|| r@ parses as @(p .&& q) .|| r@.
    (.&&), (.||) :: HsPred rs ci -> HsPred rs ci -> HsPred rs ci
    (.&&) = PAnd
    (.||) = POr
    infixr 3 .&&
    infixr 2 .||

    -- | Predicate negation. Alias for 'PNot'. ('Keiki.Core.BoolAlg' also
    -- exposes 'neg', which is this same operation lifted through the class;
    -- 'pnot' is the direct AST alias for hand-written guards.)
    pnot :: HsPred rs ci -> HsPred rs ci
    pnot = PNot

    -- | Structural arithmetic operators on 'Term's. Aliases for
    -- 'tadd' / 'tsub' / 'tmul', mirroring 'Prelude.(+)' / '(-)' / '(*)' in
    -- fixity (@infixl 6@ / @infixl 6@ / @infixl 7@). Because they build the
    -- structural 'TArith' node (not an opaque 'TApp'), arithmetic written
    -- with them is visible to the SBV translator in "Keiki.Symbolic".
    (.+), (.-), (.*)
      :: (Num r, Typeable r) => Term rs ci r -> Term rs ci r -> Term rs ci r
    (.+) = tadd
    (.-) = tsub
    (.*) = tmul
    infixl 6 .+, .-
    infixl 7 .*

Then extend the module export list. In the section comment block at the top of
`src/Keiki/Core.hs`, add a new bullet group after the existing
`-- * Predicate carrier (v1 first-class AST)` exports (`HsPred (..)`, `Cmp (..)`
at `src/Keiki/Core.hs:53`–`55`) and after the existing helper exports that
include `(.==)` (`src/Keiki/Core.hs:71`–`73`). Add these names to the export
list (placement is cosmetic; the simplest is to extend the "Helpers" group):

    , (.<)
    , (.<=)
    , (.>)
    , (.>=)
    , (./=)
    , (.&&)
    , (.||)
    , pnot
    , (.+)
    , (.-)
    , (.*)

Create the test module `test/Keiki/OperatorsSpec.hs`. It needs no SBV/z3 — it
exercises only `evalTerm` / `evalPred`, the pure evaluators. Structure it like
the existing `test/Keiki/CoreSpec.hs` (a `module Keiki.OperatorsSpec (spec)
where`, `import Test.Hspec`, `import Keiki.Core`). Use an empty register file
and a trivial command type so the only thing under test is the operator. A
concrete, complete starting point:

    module Keiki.OperatorsSpec (spec) where

    import Test.Hspec
    import Keiki.Core

    -- A trivial command type; the operators here never read it.
    data NoCmd = NoCmd deriving (Eq, Show)

    -- Evaluate a predicate over the empty register file / NoCmd input.
    p :: HsPred '[] NoCmd -> Bool
    p pr = evalPred pr RNil NoCmd

    -- Evaluate an Int term the same way.
    n :: Term '[] NoCmd Int -> Int
    n t = evalTerm t RNil NoCmd

    spec :: Spec
    spec = do
      describe "comparison operators" $ do
        it ".>= computes >=" $ do
          p (lit (5 :: Int) .>= lit 3) `shouldBe` True
          p (lit (3 :: Int) .>= lit 3) `shouldBe` True
          p (lit (2 :: Int) .>= lit 3) `shouldBe` False
        it ".<= computes <=" $ do
          p (lit (2 :: Int) .<= lit 3) `shouldBe` True
          p (lit (4 :: Int) .<= lit 3) `shouldBe` False
        it ".> computes >" $ do
          p (lit (4 :: Int) .> lit 3) `shouldBe` True
          p (lit (3 :: Int) .> lit 3) `shouldBe` False
        it ".< computes <" $ do
          p (lit (2 :: Int) .< lit 3) `shouldBe` True
          p (lit (3 :: Int) .< lit 3) `shouldBe` False
        it "./= computes /=" $ do
          p (lit (2 :: Int) ./= lit 3) `shouldBe` True
          p (lit (3 :: Int) ./= lit 3) `shouldBe` False

      describe "operator equals its constructor (behavioural identity)" $ do
        it ".>= matches PCmp CmpGe on a grid" $
          [ p (lit a .>= lit b) | a <- g, b <- g ]
            `shouldBe` [ p (PCmp CmpGe (lit a) (lit b)) | a <- g, b <- g ]
        it ".== matches PEq on a grid" $
          [ p (lit a .== lit b) | a <- g, b <- g ]
            `shouldBe` [ p (PEq (lit a) (lit b)) | a <- g, b <- g ]
        it "./= matches PNot . PEq on a grid" $
          [ p (lit a ./= lit b) | a <- g, b <- g ]
            `shouldBe` [ p (PNot (PEq (lit a) (lit b))) | a <- g, b <- g ]

      describe "logical operators" $ do
        it ".&& is conjunction" $ do
          p (lit (1 :: Int) .== lit 1 .&& lit (2 :: Int) .== lit 2) `shouldBe` True
          p (lit (1 :: Int) .== lit 1 .&& lit (2 :: Int) .== lit 3) `shouldBe` False
        it ".|| is disjunction" $ do
          p (lit (1 :: Int) .== lit 9 .|| lit (2 :: Int) .== lit 2) `shouldBe` True
          p (lit (1 :: Int) .== lit 9 .|| lit (2 :: Int) .== lit 8) `shouldBe` False
        it "pnot is negation" $ do
          p (pnot (lit (1 :: Int) .== lit 1)) `shouldBe` False
          p (pnot (lit (1 :: Int) .== lit 2)) `shouldBe` True

      describe "arithmetic operators (and fixity)" $ do
        it ".+ .- .* compute the arithmetic" $ do
          n (lit 2 .+ lit 3)       `shouldBe` 5
          n (lit 7 .- lit 4)       `shouldBe` 3
          n (lit 6 .* lit 7)       `shouldBe` 42
        it ".* binds tighter than .+ (infixl 7 vs 6)" $
          n (lit 2 .+ lit 3 .* lit 4) `shouldBe` 14
        it "arithmetic feeds a comparison without parens" $
          p (lit (10 :: Int) .<= lit 3 .* lit 4) `shouldBe` True
      where
        g = [1, 2, 3] :: [Int]

Wire the new module into the test runner in two files:

  * `test/Spec.hs` — add `import qualified Keiki.OperatorsSpec` to the import
    block and `describe "Keiki.Core operators (EP-45)" Keiki.OperatorsSpec.spec`
    to the `main` body (place it next to the other `Keiki.Core…` describes).
  * `keiki.cabal` — add `Keiki.OperatorsSpec` to the `other-modules` list of the
    `test-suite keiki-test` stanza (alphabetically near the other `Keiki.…`
    entries, e.g. after `Keiki.NoThunksSpec`).

Acceptance for M1: from the repository root,

    cabal build keiki
    cabal test keiki-test

both succeed; the `keiki-test` output includes a `Keiki.Core operators (EP-45)`
group with all examples passing and the pre-existing groups still passing.


### Milestone 2 — Type synonyms for the verbose signatures

Scope: introduce `Pred`, `Guarded`, and `SymGuarded`, export them, and prove
they are interchangeable with their expansions. At the end of this milestone an
author can write `Pred rs ci` for a guard, `Guarded rs s ci co` for an
`HsPred`-carried transducer, and `SymGuarded rs s ci co` for a
`SymPred`-carried one.

In `src/Keiki/Core.hs`, add the two synonyms near the `SymTransducer`
definition (after `src/Keiki/Core.hs:551`):

    -- | Readable alias for the v1 predicate carrier:
    -- @'Pred' rs ci@ is exactly @'HsPred' rs ci@.
    type Pred rs ci = HsPred rs ci

    -- | A 'SymTransducer' whose guard carrier is the v1 'HsPred'. Collapses
    -- the @'SymTransducer' ('HsPred' rs ci) rs s ci co@ signature — which
    -- otherwise repeats @rs@ and @ci@ — into @'Guarded' rs s ci co@.
    type Guarded rs s ci co = SymTransducer (HsPred rs ci) rs s ci co

Export both from `src/Keiki/Core.hs` (add `Pred` to the predicate-carrier
export group, `src/Keiki/Core.hs:53`; add `Guarded` to the transducer export
group near `SymTransducer (..)`, `src/Keiki/Core.hs:60`–`61`).

In `src/Keiki/Symbolic.hs`, add the SBV-carrier analogue after the `SymPred`
definition (`src/Keiki/Symbolic.hs:554`):

    -- | A 'SymTransducer' whose guard carrier is the SBV-backed 'SymPred'.
    -- The symbolic analogue of 'Keiki.Core.Guarded'.
    type SymGuarded rs s ci co = SymTransducer (SymPred rs ci) rs s ci co

Export `SymGuarded` from `src/Keiki/Symbolic.hs` (add it to the
`-- * Symbolic predicate wrapper` export group next to `SymPred (..)`,
`src/Keiki/Symbolic.hs:62`–`63`). `Pred` and `Guarded` reach `Keiki.Symbolic`
callers automatically through its existing `module Keiki.Core` re-export
(`src/Keiki/Symbolic.hs:75`).

To prove interchangeability *as part of the test suite* (not merely by the
later LoanApplication rewrite), add one type-synonym smoke check to
`test/Keiki/OperatorsSpec.hs`. Because a `type` synonym is by definition
interchangeable with its expansion, the proof is simply that a value built
through the un-aliased API type-checks at the aliased signature and round-trips
through a function written against the un-aliased type. Append to the spec:

    -- A guard written at the aliased type Pred…
    sampleGuard :: Pred '[] NoCmd
    sampleGuard = lit (1 :: Int) .>= lit 0 .&& lit (2 :: Int) ./= lit 5

    -- …is accepted where an HsPred is expected (evalPred takes HsPred).
    -- If `Pred` were not a true synonym for `HsPred`, this would not compile.

and add an example:

      describe "type synonyms" $
        it "Pred is interchangeable with HsPred" $
          evalPred sampleGuard RNil NoCmd `shouldBe` True

(`Guarded` and `SymGuarded` are exercised for real by the M3 LoanApplication
rewrite, whose existing suite is the strongest possible proof; M2's compile of
`cabal build all` already confirms the synonyms expand correctly.)

Acceptance for M2:

    cabal build all
    cabal test keiki-test

both succeed; the `type synonyms` example passes.


### Milestone 3 — Demonstrate on the LoanApplication worked example

Scope: rewrite the hand-written guards and the transducer signature in
`jitsurei/src/Jitsurei/LoanApplication.hs` to use the new operators and the
`Pred` / `Guarded` synonyms, and keep the entire `jitsurei-test` suite green.
This is the plan's "demonstrably working behaviour": the diff makes the guards
read as the inequalities they are, and the unchanged behavioural **and
symbolic** specs prove the meaning (and the SBV-visible structure) did not
change.

Edit `readyForReviewGuard` (currently `jitsurei/src/Jitsurei/LoanApplication.hs:416`):

    -- before
    readyForReviewGuard :: HsPred LoanAppRegs LoanCmd
    readyForReviewGuard =
      PCmp CmpGe (proj (#appIncomeDocCount :: Index LoanAppRegs Int))
                 (lit minimumIncomeDocs)
        `PAnd`
      PCmp CmpGe (proj (#appIdDocCount :: Index LoanAppRegs Int))
                 (lit minimumIdDocs)
        `PAnd`
      PCmp CmpGe (proj (#appCreditScore :: Index LoanAppRegs Int))
                 (lit 1)
        `PAnd`
      PEq (proj (#appEmploymentVerified :: Index LoanAppRegs Bool)) (lit True)

    -- after
    readyForReviewGuard :: Pred LoanAppRegs LoanCmd
    readyForReviewGuard =
           proj (#appIncomeDocCount :: Index LoanAppRegs Int) .>= lit minimumIncomeDocs
      .&&  proj (#appIdDocCount     :: Index LoanAppRegs Int) .>= lit minimumIdDocs
      .&&  proj (#appCreditScore    :: Index LoanAppRegs Int) .>= lit 1
      .&&  proj (#appEmploymentVerified :: Index LoanAppRegs Bool) .== lit True

Edit `approvalGuard` (currently `jitsurei/src/Jitsurei/LoanApplication.hs:430`):

    -- before
    approvalGuard :: HsPred LoanAppRegs LoanCmd
    approvalGuard =
      PCmp CmpGe (proj (#appCreditScore :: Index LoanAppRegs Int))
                 (lit approvalThresholdScore)
        `PAnd`
      PEq (proj (#appEmploymentVerified :: Index LoanAppRegs Bool)) (lit True)
        `PAnd`
      PCmp CmpLe (proj (#appRequestedAmount :: Index LoanAppRegs Money))
                 (tmul (proj (#appCreditScore :: Index LoanAppRegs Int))
                       (lit 1000))

    -- after
    approvalGuard :: Pred LoanAppRegs LoanCmd
    approvalGuard =
           proj (#appCreditScore :: Index LoanAppRegs Int) .>= lit approvalThresholdScore
      .&&  proj (#appEmploymentVerified :: Index LoanAppRegs Bool) .== lit True
      .&&  proj (#appRequestedAmount :: Index LoanAppRegs Money)
             .<= proj (#appCreditScore :: Index LoanAppRegs Int) .* lit 1000

Note the cap conjunct: `tmul (proj #appCreditScore) (lit 1000)` becomes
`proj #appCreditScore .* lit 1000`, and because `.*` (infixl 7) binds tighter
than `.<=` (infix 4), no parentheses are needed around the right operand. The
resulting `HsPred` is byte-for-byte the same AST as before
(`(.<=) = PCmp CmpLe`, `(.*) = tmul`, `(.&&) = PAnd`, `(.==) = PEq`), so the
SBV translation and `evalPred` results are unchanged by construction.

Update the transducer signature (currently
`jitsurei/src/Jitsurei/LoanApplication.hs:444`):

    -- before
    loanApplication :: SymTransducer (HsPred LoanAppRegs LoanCmd)
                                     LoanAppRegs
                                     LoanAppVertex
                                     LoanCmd
                                     LoanEvent
    -- after
    loanApplication :: Guarded LoanAppRegs LoanAppVertex LoanCmd LoanEvent

If the module's import of `Keiki.Core` (or `Keiki.Symbolic`) uses an explicit
import list rather than an open import, add `Pred`, `Guarded`, and the operator
names (`(.<=)`, `(.>=)`, `(.&&)`, `(.*)`, and any others now used) to it. Check
the import head of the file first (`grep -n "import .*Keiki" jitsurei/src/Jitsurei/LoanApplication.hs`);
if it is an open `import Keiki.Symbolic` / `import Keiki.Core`, nothing to add.

The accompanying narrative comments in the file (e.g. the block at
`jitsurei/src/Jitsurei/LoanApplication.hs:404`–`415` describing the EP-41/EP-43
migration in terms of `PCmp CmpGe`/`tmul`) remain accurate — they describe the
AST, which is unchanged — but add a short sentence noting the surface now reads
through the EP-45 operators. Do not delete the existing rationale.

Optional sweep (same milestone, separate commit): the other two hand-written
`HsPred` guards in the examples are `jitsurei/src/Jitsurei/UserRegistration.hs`
(line ~406) and `jitsurei/src/Jitsurei/UserRegistrationV0.hs` (line ~178),
each a `PAnd isConfirm (… .== proj …)`. These already use `.==`; rewrite the
`PAnd` to `.&&` for consistency. Keep these in a clearly separated commit so
the flagship LoanApplication change is reviewable on its own.

Acceptance for M3:

    cabal build jitsurei
    cabal test jitsurei-test

both succeed. In particular the groups
`Jitsurei.LoanApplication`, `Jitsurei.LoanApplication (builder)`,
`Jitsurei.LoanApplication (view)`, and crucially
`Jitsurei.LoanApplication (symbolic)` all stay green — the symbolic spec
re-checks guard mutual-exclusion / satisfiability through SBV, so its passing is
direct evidence the rewrite preserved the solver-visible structure.


### Milestone 4 — Documentation

Scope: document the operator set and the type synonyms so a novice discovers
them, and record the SBV caveat. Nothing in this milestone changes behaviour;
the proof is that the docs build/read and the examples in them compile.

In `src/Keiki/Core.hs`, ensure the haddocks added in M1/M2 are complete (they
are reproduced above) and add a compact reference table to the module-level
haddock comment near the top (after the existing escape-hatch note,
`src/Keiki/Core.hs:16`–`22`). Use prose plus an inline list, for example:

    -- == Guard-authoring operators (EP-45)
    --
    -- Predicates and term arithmetic can be written with infix operators
    -- that mirror their Prelude counterparts:
    --
    --   * Relational (build 'HsPred', @infix 4@): '.<' '.<=' '.>' '.>='
    --     '.==' './=' — each an alias for 'PCmp'/'PEq' at a fixed relation.
    --   * Logical (combine 'HsPred'): '.&&' (@infixr 3@, 'PAnd'),
    --     '.||' (@infixr 2@, 'POr'), 'pnot' ('PNot').
    --   * Arithmetic (build 'Term', mirror @+@/@-@/@*@): '.+' '.-' '.*' —
    --     aliases for 'tadd'/'tsub'/'tmul'.
    --
    -- Keep spaces around the operators ('lit a .* lit b'); a dot touching an
    -- identifier ('x.y') is OverloadedRecordDot field access. If you import
    -- "Data.SBV" alongside this module, import it qualified — SBV exports
    -- the same operator names.

Update the authoring guide. Find the guard section in `docs/guide/user-guide.md`
(grep for `PCmp`, `requireGe`, or `HsPred`); add a short subsection showing the
before/after of a guard and listing the operator set, mirroring the Purpose
section above. If a guard section does not exist, add one titled "Writing
guards" near where commands/edges are introduced.

Update the foundations docs if they describe the predicate language: grep
`docs/foundations/` for `HsPred` / `PCmp` and, where the constructors are
introduced, add a one-line pointer that the operators `.>=`/`.&&`/etc. are the
preferred surface and the constructors are the underlying AST.

Acceptance for M4: `cabal haddock keiki` succeeds (the haddock examples are
plain prose, so this mainly checks the comments are well-formed), and a final
full-suite run is green:

    cabal test all

Then fill in Outcomes & Retrospective.


## Concrete Steps

All commands run from the repository root `/Users/shinzui/Keikaku/bokuno/keiki`.

1. Confirm the toolchain and solver are present (the symbolic specs in M3 need
   z3 on `PATH`):

        cabal --version
        z3 --version        # expect: Z3 version 4.x

2. M1 — edit `src/Keiki/Core.hs` (operators + exports), create
   `test/Keiki/OperatorsSpec.hs`, edit `test/Spec.hs` and `keiki.cabal`. Then:

        cabal build keiki
        cabal test keiki-test

   Expected tail of the test output (the new group appears alongside the
   existing ones):

        Keiki.Core operators (EP-45)
          comparison operators
            .>= computes >= [✔]
            .<= computes <= [✔]
            ...
          arithmetic operators (and fixity)
            .* binds tighter than .+ (infixl 7 vs 6) [✔]
        Finished in 0.0XXX seconds
        NNN examples, 0 failures

   Commit (note the required trailers):

        git add -A && git commit -m "feat(core): EP-45 M1 — dot-prefixed predicate & term operators

        Add .< .<= .> .>= ./= (relational), .&& .|| pnot (logical), and
        .+ .- .* (arithmetic) as definitional aliases for the HsPred/Term
        constructors, with Prelude-matching fixities. Prove each with
        test/Keiki/OperatorsSpec.hs.

        ExecPlan: docs/plans/45-readable-guard-dsl-dot-prefixed-predicate-operators-and-type-synonyms.md
        Intention: intention_01ks404p49en58h61yh8nc3nct"

3. M2 — add `Pred` + `Guarded` to `src/Keiki/Core.hs`, `SymGuarded` to
   `src/Keiki/Symbolic.hs`, exports in both; append the type-synonym example to
   `test/Keiki/OperatorsSpec.hs`. Then:

        cabal build all
        cabal test keiki-test

   Commit:

        git commit -am "feat(core,symbolic): EP-45 M2 — Pred/Guarded/SymGuarded type synonyms

        ExecPlan: docs/plans/45-readable-guard-dsl-dot-prefixed-predicate-operators-and-type-synonyms.md
        Intention: intention_01ks404p49en58h61yh8nc3nct"

4. M3 — rewrite the guards/signature in
   `jitsurei/src/Jitsurei/LoanApplication.hs`. Then:

        cabal build jitsurei
        cabal test jitsurei-test

   Expect every `Jitsurei.LoanApplication*` group green (including
   `(symbolic)`). Commit the flagship change, then the optional sweep
   separately:

        git commit -am "refactor(jitsurei): EP-45 M3 — LoanApplication guards via the new operators

        ExecPlan: docs/plans/45-readable-guard-dsl-dot-prefixed-predicate-operators-and-type-synonyms.md
        Intention: intention_01ks404p49en58h61yh8nc3nct"

5. M4 — documentation edits; then the full sweep:

        cabal haddock keiki
        cabal test all

   Commit:

        git commit -am "docs(core): EP-45 M4 — document the guard-authoring operators and synonyms

        ExecPlan: docs/plans/45-readable-guard-dsl-dot-prefixed-predicate-operators-and-type-synonyms.md
        Intention: intention_01ks404p49en58h61yh8nc3nct"

At each commit, also check off the corresponding Progress items and add a
timestamped note; record any deviation in the Decision Log.


## Validation and Acceptance

The change is observable in two complementary ways.

First, *direct behaviour of the operators*. After M1, run
`cabal test keiki-test`. The `Keiki.Core operators (EP-45)` group asserts, with
concrete numbers, that `.>=` computes `>=` (e.g. `lit 5 .>= lit 3` is `True`,
`lit 2 .>= lit 3` is `False`), that the logical operators conjoin/disjoin/negate
correctly, that the arithmetic operators compute and that `.*` binds tighter
than `.+` (`lit 2 .+ lit 3 .* lit 4` evaluates to `14`, not `20`), and — most
importantly — that each operator is *behaviourally identical* to the constructor
it aliases across a small input grid (e.g. `lit a .>= lit b` and
`PCmp CmpGe (lit a) (lit b)` agree for every `a,b` in `[1,2,3]`). A failure
prints the differing case.

Second, *semantic preservation on a real aggregate*. After M3, run
`cabal test jitsurei-test`. The pre-existing LoanApplication specs were written
against the old constructor-based guards; they pass unchanged against the
operator-based rewrite. This is the acceptance that matters most: the guards now
*read* as inequalities (`proj #appCreditScore .>= lit approvalThresholdScore`)
yet *mean* exactly what they did, and the SBV-backed
`Jitsurei.LoanApplication (symbolic)` spec confirms the solver still sees the
same structure. To make the equivalence vivid, you can view the diff and
confirm only the surface changed:

        git show --stat HEAD          # only LoanApplication.hs touched in M3
        git log --oneline -5

Whole-project gate: `cabal test all` must be green at the end. No existing test
is expected to change, because every alias is definitionally equal to the AST
node it stands for; if any pre-existing test needs editing to keep passing,
stop and record why in Surprises & Discoveries — that would indicate an alias is
*not* a faithful synonym, which is a bug in this plan, not in the test.


## Idempotence and Recovery

Every step is additive and re-runnable. The operator and synonym definitions can
be re-applied harmlessly — if a definition already exists, GHC will report a
duplicate and the edit can be skipped. Build and test commands are pure reads of
the source tree and can be run any number of times. If a milestone's build
fails, the working tree is left untouched by the build itself; revert the
in-progress edit (`git checkout -- <file>`) or fix it forward — no partial
state is persisted outside the source files you are editing.

If the LoanApplication rewrite (M3) fails to type-check, the most likely cause
is a missing operator/synonym in an explicit import list at the top of the file
(see the M3 import note) or an unexpected fixity interaction; recover by
restoring the original guard from git (`git checkout -- jitsurei/src/Jitsurei/LoanApplication.hs`)
and re-applying one conjunct at a time. Because M1/M2 land first and are proven
in isolation, an M3 failure never implicates the operators themselves.

The plan creates exactly one new file (`test/Keiki/OperatorsSpec.hs`) and
touches `src/Keiki/Core.hs`, `src/Keiki/Symbolic.hs`, `test/Spec.hs`,
`keiki.cabal`, `jitsurei/src/Jitsurei/LoanApplication.hs`, and documentation.
Nothing is deleted; rollback of the whole plan is `git revert` of its commits.


## Interfaces and Dependencies

No new library dependencies. The work uses only what `keiki` and `jitsurei`
already depend on: `base`, `sbv` (already a dependency; unaffected — its
operators stay qualified behind `SBV`), `hspec` (test), and the in-repo modules.

Signatures that must exist at the end of each milestone (full module paths):

End of M1 — in `Keiki.Core` (exported):

    (.<), (.<=), (.>), (.>=)
      :: (Ord r, Typeable r) => Term rs ci r -> Term rs ci r -> HsPred rs ci
    (./=)
      :: (Eq r, Typeable r)  => Term rs ci r -> Term rs ci r -> HsPred rs ci
    (.&&), (.||) :: HsPred rs ci -> HsPred rs ci -> HsPred rs ci
    pnot         :: HsPred rs ci -> HsPred rs ci
    (.+), (.-), (.*)
      :: (Num r, Typeable r) => Term rs ci r -> Term rs ci r -> Term rs ci r

  with fixities `infix 4 .<, .<=, .>, .>=, ./=`, `infixr 3 .&&`,
  `infixr 2 .||`, `infixl 6 .+, .-`, `infixl 7 .*`. And the test entry point
  `Keiki.OperatorsSpec.spec :: Spec`.

End of M2 — in `Keiki.Core` (exported):

    type Pred rs ci          = HsPred rs ci
    type Guarded rs s ci co  = SymTransducer (HsPred rs ci) rs s ci co

  in `Keiki.Symbolic` (exported):

    type SymGuarded rs s ci co = SymTransducer (SymPred rs ci) rs s ci co

End of M3 — `jitsurei/src/Jitsurei/LoanApplication.hs` exposes the same public
values as before (`readyForReviewGuard`, `approvalGuard`, `loanApplication`),
with the guard helpers retyped to `Pred LoanAppRegs LoanCmd` and
`loanApplication` retyped to `Guarded LoanAppRegs LoanAppVertex LoanCmd LoanEvent`.
The values are observationally identical to the pre-rewrite ones (same `HsPred`
AST, same transducer).

End of M4 — no new interfaces; documentation only.
