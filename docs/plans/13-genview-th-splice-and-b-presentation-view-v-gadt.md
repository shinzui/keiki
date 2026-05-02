---
id: 13
slug: genview-th-splice-and-b-presentation-view-v-gadt
title: "genView TH splice and B-presentation View v GADT"
kind: exec-plan
created_at: 2026-05-02T12:33:53Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
master_plan: "docs/masterplans/5-acceptor-projections-and-genview-th-splice-for-b-presentation.md"
---

# genView TH splice and B-presentation View v GADT

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

The keiki library represents an aggregate's state as the pair
`(s, RegFile rs)` — a control vertex plus a uniform register
file containing every slot the aggregate ever uses. The register
file is the same in every vertex; slots that aren't relevant in
the current vertex are simply ignored.

The synthesis note
(`docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`,
§3 "Where indexed state (B) fits") proposes a *typed
projection* on top: for each control vertex `v`, define a per-
vertex GADT constructor that exposes only the registers
meaningful in that vertex, then write
`viewFor :: SVertex v -> RegFile rs -> View v` that materializes
it. The chapter shows the worked example for a multi-approval
aggregate: `PendingV` carries `(docId, required)`, `ApprovedV`
carries `(docId, approvers, completedAt)`, and so on. The user
then pattern-matches on `View v` and gets only the fields the
type system says are live.

The synthesis note flagged this as opt-in and noted: *"A
`genView` TH helper is a nice-to-have, not a v1 requirement."*
Today no aggregate in `src/Keiki/Examples/` has a B-view, no
`SVertex` machinery exists, and the user who wants the typed
projection has to hand-write the GADT and the projection.

This ExecPlan ships the `genView` helper and demonstrates it on
`Keiki.Examples.UserRegistration`. After completion the
repository contains:

- A new TH splice `deriveView` in
  `src/Keiki/Generics/TH.hs`. Given a vertex enum, a register-
  file slot-list type, the user-chosen names for the singletons
  GADT and the View GADT, the projection-function name, and a
  per-vertex spec listing which slots are live in each vertex,
  the splice generates:
  1. A per-aggregate singletons GADT
     (`data SUserVertex (v :: Vertex) where SPotentialCustomer
     :: SUserVertex 'PotentialCustomer; …`).
  2. A per-aggregate View GADT
     (`data UserView (v :: Vertex) where PotentialCustomerV ::
     UserView 'PotentialCustomer; ConfirmedV :: { cfEmail ::
     Email, cfConfirmedAt :: UTCTime } -> UserView 'Confirmed;
     …`).
  3. The projection
     `userView :: SUserVertex v -> RegFile UserRegRegs ->
     UserView v`, with one clause per vertex reading the named
     slots via `(!)` and the `OverloadedLabels` machinery.

- A new design note
  `docs/research/genview-th-splice-design.md` (~150-200 lines)
  capturing the splice's user-facing API, the spec format,
  validation rules, and a worked expansion against
  `UserRegistration`.

- An updated `Keiki.Examples.UserRegistration` exporting
  `UserView` and `SUserVertex` derived via the splice.

- A new test module
  `test/Keiki/Examples/UserRegistrationViewSpec.hs` exercising
  the projection on hand-constructed register files.

- Updates to `docs/research/keiki-generics-design.md` retiring
  the entry that flagged `genView` as a future improvement
  (mirroring the way EP-11 retired item F).

How a future contributor sees this work:

    nix-shell -p z3 --run "cabal test all"
    # 95 → ~100 examples (depending on the test count), 0 failures.
    # Includes "userView SConfirmed regs == ConfirmedV ..." tests.

The user-visible win:

    > userView SConfirmed regsAtConfirmed
    ConfirmedV { cfEmail = "alice@x.io"
               , cfConfirmedAt = 2026-05-02 09:31:00 UTC }

Pattern-matching on `View v` lets readers see exactly which
fields are live in each vertex without reading the transducer's
edge list. The TH splice makes opting in cheap (one invocation
per aggregate, ~5-10 lines of spec).


## Progress

Use a checklist to summarize granular steps. Every stopping point
must be documented here, even if it requires splitting a
partially completed task into two ("done" vs. "remaining"). This
section must always reflect the actual current state of the work.

- [x] **Milestone 0 — Verify prerequisites.** Run `cabal build
      all` and `nix-shell -p z3 --run "cabal test all"`. Record
      test count (expected 95 examples) and GHC version. Confirm
      `Keiki.Generics.TH.deriveAggregateCtors` and
      `deriveWireCtors` work — if either splice has bit-rotted,
      EP-13 needs to fix it first.
      *(2026-05-02; GHC 9.12.3, cabal 3.16.1.0; baseline = 101
      examples, 0 failures — 95 from MP-2/3/4 plus 6 from EP-12's
      Keiki.Acceptor. The two existing splices compile and run
      transitively via `UserRegistration` whose tests pass.)*
- [x] **Milestone 1 — Design note.** Write
      `docs/research/genview-th-splice-design.md` (~150-200
      lines). Cover: the splice signature, the spec format, the
      generated code shape, the validation rules and error
      messages, the worked expansion against
      `UserRegistration`, and what's deferred (default
      `View v = RegFile rs` for non-opted-in aggregates;
      lifting `viewFor` into the transducer).
      *(2026-05-02; design note created. Two surprises landed
      during writing — see Surprises & Discoveries below: the
      keiki-generics-design `genView` entry the plan claimed to
      retire doesn't actually exist, and the original
      `<initials><Slot>` field-name rule was revised to a
      mechanical `filter isUpper >>> map toLower` rule because
      no uniform derivation produced both `cf` for `Confirmed`
      and `d` for `Deleted`.)*
- [x] **Milestone 2 — Splice scaffolding.** Add `deriveView` to
      `src/Keiki/Generics/TH.hs` (signature + validation +
      error-message plumbing) but leave the code-gen body as a
      `fail` placeholder. Add the new top-level export. Verify
      `cabal build all` still succeeds. This milestone exists
      so M3's code-gen edits are isolated to one function.
      *(2026-05-02; signature + reifySlotList +
      validateSpecCoverage + validateSpecSlots +
      validatePrefixUniqueness + vertexFieldPrefix + showList'
      added; `cabal build all` clean.)*
- [x] **Milestone 3 — Splice code-gen.** Implement the body of
      `deriveView` to emit the singletons GADT, the View GADT,
      and the projection function. Cover empty-payload
      vertices (nullary GADT constructors), single-slot
      vertices, multi-slot vertices. Verify `cabal build all`
      still succeeds.
      *(2026-05-02; code-gen produces 8 declarations per
      invocation: SDataD + 2 standalone deriving for the
      singletons GADT; ViewDataD + 2 standalone deriving for
      the View GADT; SigD + FunD for the projection. Empty
      slots use `GadtC` + `WildP` patterns; non-empty use
      `RecGadtC` + `VarP` + `(!)`/`LabelE` reads. Two name-
      shadowing warnings on `bang`/`sigT` were renamed to
      `lazyBang`/`funTy`.)*
- [x] **Milestone 4 — Wire splice into UserRegistration.** Add
      the splice invocation to
      `src/Keiki/Examples/UserRegistration.hs`. Extend the
      module's exports list to include `UserView (..)` and
      `SUserVertex (..)`. Verify `cabal build all` still
      succeeds.
      *(2026-05-02; splice invocation placed after
      deriveWireCtors with a haddock paragraph pointing at the
      design note; export block extended with a "B-presentation
      views (TH-derived; see EP-13 / MP-5)" subsection.)*
- [x] **Milestone 5 — Test module.** Create
      `test/Keiki/Examples/UserRegistrationViewSpec.hs` with
      tests asserting per-vertex projection results. Wire into
      `test/Spec.hs` and `keiki.cabal`. Run `nix-shell -p z3
      --run "cabal test all"`.
      *(2026-05-02; six tests — one per vertex plus an
      "ignores slots not named in the spec" test that binds
      irrelevant slots to bottom and confirms the projection
      doesn't read them. Test count 101 → 107, 0 failures.)*
- [ ] **Milestone 6 — Docs update + commit.** Update
      `docs/research/keiki-generics-design.md` to mark the
      `genView` entry Implemented (with a pointer to MP-5 /
      EP-13). Update `docs/research/synthesis-c-foundation-b-
      presentation-with-worked-examples.md`'s §3 to add a
      sentence noting the helper now exists. Stage and commit.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights
discovered during implementation. Provide concise evidence.

- **2026-05-02 (M1)** — The plan's M6 step claims that
  `docs/research/keiki-generics-design.md` carries a `genView`
  "Future improvements" entry that needs to be retired. There
  is no such entry. Items A–G of that document's Future
  Improvements section cover TH for `deriveAggregateCtors`,
  `RegFieldsOf`, generic `Term` projection helpers, symbolic
  `WitnessExtract`, the Decider façade, composition combinators,
  and compile-time topology — none of them mention the B-view
  GADT. The synthesis note is the only research note that
  references `genView` (lines 155 and 936). M6 is adjusted to
  *add* a fresh `### H. genView TH splice for B-presentation
  View v GADT` entry to keiki-generics-design.md (marked
  Implemented from the start, mirroring the shape of items A,
  B, D, E, F's Implemented additions) plus update the synthesis
  note's two pointers.

- **2026-05-02 (M1)** — The plan's draft Decision Log committed
  to field-name examples `cfEmail` (Confirmed) and `rcEmail`
  (RequiresConfirmation). No mechanical rule produces both
  `cf` for `Confirmed` *and* `d` for `Deleted` (the worked
  expansion's existing convention). The implementation switched
  to `filter isUpper >>> map toLower` — `Confirmed` → `c`,
  `Deleted` → `d`, `RequiresConfirmation` → `rc`. All five
  vertices of `UserRegistration` produce distinct prefixes; the
  splice now validates prefix uniqueness as a fifth check.


## Decision Log

Record every decision made while working on the plan.

- Decision: spec format is a list of pairs
  `(constructorName :: String, liveSlotNames :: [String])`,
  not a value of a custom data type.
  Rationale: matches the style of `deriveAggregateCtors` (TH
  splice in the same module). Strings are easy to type at the
  splice site and produce precise validation errors when
  misspelled.
  Date: 2026-05-02

- Decision: the splice takes user-chosen *names* for the
  singletons GADT, the View GADT, and the projection function
  (`"SUserVertex"`, `"UserView"`, `"userView"`). It does *not*
  default to `"S<Vertex>"` / `"<Vertex>View"` /
  `"<lowercase>view"`.
  Rationale: explicit names are clearer at the call site;
  derivation rules from another type's name are surprising.
  Cost: three extra string arguments per invocation.
  Date: 2026-05-02

- Decision: each vertex's View constructor is named
  `<VertexName>V` (e.g. `PotentialCustomerV`,
  `ConfirmedV`), with field names `<prefix><Slot>` where
  `<prefix>` is the lower-cased concatenation of the vertex
  name's upper-case letters (`filter isUpper >>> map toLower`)
  and `<Slot>` is the slot name with its first letter
  upper-cased.
  Rationale: avoids name collisions across vertices that
  contain the same slot. The rule is one line of code,
  predictable, and yields distinct prefixes for every vertex
  of `UserRegistration` (`pc`, `r`, `rc`, `c`, `d`). The splice
  validates that the prefixes are pairwise distinct.
  Note: the original draft of this Decision Log committed to
  the example field name `cfEmail` for `Confirmed.email`. The
  implementation took `cEmail` instead because `Confirmed` has
  only one upper-case letter under the chosen rule. The
  synthesis-doc worked example (§4.4) uses non-mechanical
  abbreviations (`Conf`, `Del`) that don't follow any uniform
  derivation; the in-tree `cEmail`/`dEmail` shape is one notch
  more verbose at the field level but mechanically derivable
  from the spec, which the splice needs.
  Date: 2026-05-02 (revised during M1)

- Decision: empty-slot-list vertices (e.g.
  `PotentialCustomerV`) generate nullary GADT constructors with
  no field block.
  Rationale: keeps the generated code simple; matches the
  synthesis-doc shape.
  Date: 2026-05-02

- Decision: the splice validates (a) every named vertex
  constructor exists in the supplied vertex enum, (b) the spec
  enumerates *every* vertex (no missing entries; no extras),
  (c) every named slot exists in the supplied register-file
  type. Validation failures `fail` with a precise message.
  Rationale: covers the high-frequency typo failure mode the
  EP-8 splices already protect against. Total-coverage
  enforcement (b) makes the projection total — `viewFor` is a
  pattern-matching function over `SVertex v` and must have a
  clause for every `v`.
  Date: 2026-05-02

- Decision: the generated GADTs derive `Show` and `Eq` via
  `StandaloneDeriving`. (GHC2024 includes
  `StandaloneDeriving`; the existing `keiki.cabal` shared-
  extensions block doesn't list it explicitly, but the
  language standard pulls it in.)
  Rationale: testing requires `Eq` for `shouldBe` and `Show`
  for diagnostic output. Without these, every test would have
  to deconstruct the `View` manually.
  Date: 2026-05-02


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones
or at completion. Compare the result against the original purpose.

**Outcome (2026-05-02).** EP-13 ships `Keiki.Generics.TH.deriveView`
and a worked example on `Keiki.Examples.UserRegistration`.
`SUserVertex`, `UserView`, and `userView` are exported and exercised
by six tests in `test/Keiki/Examples/UserRegistrationViewSpec.hs`.
Test suite: 101 → 107 examples, 0 failures.

Against the original purpose:

- **The user-visible win lands.** `userView SConfirmed regs`
  returns `ConfirmedV "alice@x" t100` with field selectors
  `cEmail`/`cConfirmedAt`. Pattern-matching on `UserView v` makes
  the live slots per vertex statically visible.

- **Validation diagnostics are precise.** The five splice-time
  checks named in the design note are all in place
  (`validateSpecCoverage` covers vertex coverage + duplicates;
  `validateSpecSlots` covers slot membership + per-entry slot
  duplicates; `validatePrefixUniqueness` covers prefix
  collisions). Each `fail`s with a message naming the offending
  symbol(s).

- **The transducer stays unchanged.** `userReg` does not
  reference `userView`; the projection is downstream of `step` /
  `applyEvent` exactly as the synthesis note prescribes.

Lessons:

1. *The plan's "retire the genView entry in keiki-generics-design"
   step rested on a wrong premise.* No such entry existed;
   `genView` was only ever mentioned in the synthesis note. M6
   added a fresh `### H` entry to keiki-generics-design.md
   instead. Worth checking referenced documents exist before
   committing the plan to a "retire X" step.

2. *Field-name derivation rules deserve more scrutiny than they
   got in the design phase.* The plan committed to `cfEmail`
   (Confirmed) and `dEmail` (Deleted) as illustrative examples in
   the Decision Log, but no uniform mechanical rule produces both
   `cf` and `d`. The implementation switched to a one-liner
   (`filter isUpper >>> map toLower`) that yields `cEmail` and
   `dEmail`. Distinct prefixes for the worked aggregate are
   guaranteed by the `validatePrefixUniqueness` check.

3. *`-ddump-splices` was useful conceptually but `cabal build`
   wouldn't recompile to surface the dump even after `touch`-ing
   the file.* Skipping the dump in favour of letting the test
   module's compile catch any code-gen mistake worked fine; the
   tests passed first try. Future TH-splice work might prefer a
   thin `runQ` smoke test in GHCi.

Gaps left open (intentional, per the design note's "What is
deliberately deferred" section):

- No default `View v = RegFile rs` for non-opted-in aggregates.
- No shared `Keiki.View` module exposing a kind-generic
  `Singleton` class.
- No edge-driven cross-validation of the spec (slots written by
  incoming edges vs. slots named live in the spec).
- `viewFor` is not lifted into the transducer's evolution loop.

A future EP can pick any of these up if a real authoring need
surfaces.


## Context and Orientation

Describe the current state relevant to this task as if the reader
knows nothing.

The keiki library lives at `/Users/shinzui/Keikaku/bokuno/keiki/`.
Its layout (only the parts EP-13 touches):

    src/
      Keiki/
        Core.hs                   -- the SymTransducer formalism
                                  --   defines RegFile, Index, (!), Slot
        Generics/
          TH.hs                   -- existing splices: deriveAggregateCtors,
                                  --   deriveWireCtors. EP-13 adds deriveView.
        Examples/
          UserRegistration.hs     -- canonical worked example;
                                  --   EP-13 adds the splice invocation here
    test/
      Spec.hs                     -- main entry; EP-13 registers a new module
      Keiki/
        Examples/
          UserRegistrationViewSpec.hs   -- new in EP-13
    docs/
      research/
        synthesis-c-foundation-b-presentation-with-worked-examples.md
                                  -- §3 motivates the B-view; EP-13 references
        keiki-generics-design.md  -- "Future improvements" entry to retire
        genview-th-splice-design.md      -- new in EP-13

**Existing TH splice pattern** (the model EP-13's `deriveView`
follows): `src/Keiki/Generics/TH.hs:67-91` define
`deriveAggregateCtors` and `deriveWireCtors`. Both:

1. Take a target type `Name` plus a spec list of
   `(constructorName, shortName)` strings.
2. Call `reify` on the target type to get its constructor
   list.
3. For each spec entry, look up the constructor, dispatch on
   its payload shape (`NormalC` zero-arg, `NormalC` one-arg
   record, etc.), and emit a fixed set of declarations.
4. `fail` with a precise message on lookup or shape errors.

EP-13's `deriveView` is structurally similar but emits a
*single* combined declaration set (one GADT for SVertex, one
GADT for View, one function for viewFor) rather than per-
constructor declarations. The dispatch is over the spec
entries, not the target type's constructors directly.

**Key shapes from `src/Keiki/Core.hs`:**

    type Slot = (Symbol, Type)

    data RegFile (rs :: [Slot]) where
      RNil  :: RegFile '[]
      RCons :: KnownSymbol s
            => Proxy s -> r -> RegFile rs -> RegFile ('(s, r) ': rs)

    data Index (rs :: [Slot]) (r :: Type) where
      ZIdx :: KnownSymbol s => Index ('(s, r) ': rs) r
      SIdx :: Index rs r -> Index ('(s', r') ': rs) r

    (!) :: RegFile rs -> Index rs r -> r

The `OverloadedLabels` instance
(`src/Keiki/Core.hs:148-151`) lets users write `regs ! #email`
to read the `"email"` slot; that desugars to `regs !
(indexOf @"email" @rs)`.

**The vertex enum and register file the worked example uses,**
from `src/Keiki/Examples/UserRegistration.hs:159-174`:

    type UserRegRegs =
      '[ '("email",        Email)
       , '("confirmCode",  ConfirmationCode)
       , '("registeredAt", UTCTime)
       , '("confirmedAt",  UTCTime)
       , '("deletedAt",    UTCTime)
       ]

    data Vertex
      = PotentialCustomer
      | Registering
      | RequiresConfirmation
      | Confirmed
      | Deleted
      deriving (Eq, Show, Enum, Bounded)

The vertex enum is a plain Haskell data type. With `DataKinds`
(in GHC2024), each constructor is automatically also a type
constructor of kind `Vertex`. EP-13's splice exploits this:
`SUserVertex (v :: Vertex)` indexes on the promoted vertex
type; constructor `SConfirmed` pattern-matches on
`'Confirmed`.

**The user-facing splice signature EP-13 ships:**

    deriveView
      :: Name              -- ^ vertex enum, e.g. ''Vertex
      -> Name              -- ^ register-file slot list, e.g. ''UserRegRegs
      -> String            -- ^ name of the singletons GADT
                           --   to generate, e.g. "SUserVertex"
      -> String            -- ^ name of the View GADT, e.g. "UserView"
      -> String            -- ^ name of the projection function,
                           --   e.g. "userView"
      -> [(String, [String])]
                           -- ^ per-vertex spec: pairs of
                           --   (vertex constructor name,
                           --    list of slot names live in that vertex)
      -> Q [Dec]

**Worked invocation** EP-13 lands in
`src/Keiki/Examples/UserRegistration.hs`:

    $(deriveView ''Vertex ''UserRegRegs
        "SUserVertex" "UserView" "userView"
        [ ("PotentialCustomer",    [])
        , ("Registering",          [])
        , ("RequiresConfirmation", ["email", "confirmCode"])
        , ("Confirmed",            ["email", "confirmedAt"])
        , ("Deleted",              ["email", "deletedAt"])
        ])

**Worked expansion** the splice produces:

    data SUserVertex (v :: Vertex) where
      SPotentialCustomer    :: SUserVertex 'PotentialCustomer
      SRegistering          :: SUserVertex 'Registering
      SRequiresConfirmation :: SUserVertex 'RequiresConfirmation
      SConfirmed            :: SUserVertex 'Confirmed
      SDeleted              :: SUserVertex 'Deleted

    data UserView (v :: Vertex) where
      PotentialCustomerV    :: UserView 'PotentialCustomer
      RegisteringV          :: UserView 'Registering
      RequiresConfirmationV
        :: { rcEmail       :: Email
           , rcConfirmCode :: ConfirmationCode
           } -> UserView 'RequiresConfirmation
      ConfirmedV
        :: { cfEmail       :: Email
           , cfConfirmedAt :: UTCTime
           } -> UserView 'Confirmed
      DeletedV
        :: { dEmail     :: Email
           , dDeletedAt :: UTCTime
           } -> UserView 'Deleted

    deriving instance Show (SUserVertex v)
    deriving instance Eq   (SUserVertex v)
    deriving instance Show (UserView v)
    deriving instance Eq   (UserView v)

    userView :: SUserVertex v -> RegFile UserRegRegs -> UserView v
    userView SPotentialCustomer    _    = PotentialCustomerV
    userView SRegistering          _    = RegisteringV
    userView SRequiresConfirmation regs =
      RequiresConfirmationV (regs ! #email) (regs ! #confirmCode)
    userView SConfirmed            regs =
      ConfirmedV (regs ! #email) (regs ! #confirmedAt)
    userView SDeleted              regs =
      DeletedV (regs ! #email) (regs ! #deletedAt)

**Field-name derivation rule.** For each vertex constructor,
take the camelCase initials (e.g. `PotentialCustomer` → `pc`,
`RequiresConfirmation` → `rc`, `Confirmed` → `cf`). Prefix each
slot-name with the initials, capitalize the slot's first
letter. So `RequiresConfirmation` × `email` → `rcEmail`. This
keeps field names unique across constructors (the
`DuplicateRecordFields` extension is enabled, but distinct
field names produce clearer pattern-matches).

**Validation rules.** Before generating any code, the splice
checks:

1. *Vertex enum is a data type.* `reify` returns
   `TyConI (DataD …)`; otherwise `fail` with "expected a data
   declaration."
2. *Spec covers every vertex.* The set of constructor names in
   the vertex enum equals the set of names in the spec.
   Mismatch → `fail` with the missing/extra names listed.
3. *Each named slot exists in the register-file slot list.*
   Walk `Append` / `':' / `'(s, r)` structure of the slot-list
   type; collect the symbol names; check every spec-entry slot
   is in the set. Mismatch → `fail` with the offending slot
   name and the available slot list.
4. *No duplicate slots in a single vertex's spec.* (e.g.
   `("Confirmed", ["email", "email"])` is rejected.)

The "walk the slot-list type" subroutine: a TH `Type` value
of shape `'[ '("email", Email), '("confirmCode",
ConfirmationCode), … ]`. The walk pattern-matches the type
constructor `':` (cons) and `'[]` (nil), and for each cons cell
extracts the `Symbol` literal from the slot pair via
`PromotedTupleT 2 :@ LitT (StrTyLit name) :@ slotType`. See
`Language.Haskell.TH.Datatype` if a higher-level traversal
helper is preferable; otherwise hand-walk.

**The cabal file's relevant blocks**, for reference:

`keiki.cabal:38-46` — `library:exposed-modules` (no addition
needed; `Keiki.Generics.TH` already lists; `deriveView` extends
the module).

`keiki.cabal:53-60` — `keiki-test:other-modules` (EP-13 adds
`Keiki.Examples.UserRegistrationViewSpec`).

**The test runner.** `test/Spec.hs` is a hand-written entry
point that imports each spec module qualified and registers it
under hspec's `describe`. EP-13 adds an import + a `describe`
line.

**Test runner needs `z3`.** The full suite uses `z3` even
though EP-13's own spec doesn't. Run with
`nix-shell -p z3 --run "cabal test all"`.


## Plan of Work

Six milestones. Effort estimate: ~6-10 hours total. The TH
splice work is the bulk of it; the rest is mechanical wiring.

**Milestone 0 — Baseline.** Confirm the working tree builds and
the test suite passes:

    cabal build all
    nix-shell -p z3 --run "cabal test all" 2>&1 | tail -3

Expected: 95 examples, 0 failures. Record the actual number in
the Progress section. Skim `src/Keiki/Generics/TH.hs` to confirm
`deriveAggregateCtors` and `deriveWireCtors` still work as the
worked-example aggregates expect.

**Milestone 1 — Design note.** Create
`docs/research/genview-th-splice-design.md`. Sections:

1. *Problem statement.* The synthesis note motivates the
   B-view but flagged `genView` as a deferred nice-to-have.
   Today no aggregate has one; users would hand-roll the GADT
   and projection.

2. *The splice.* Signature, spec format, validation rules,
   the EP-8-pattern justification (consistency with existing
   TH surface).

3. *Generated code.* Show the worked expansion for
   `UserRegistration` (the same expansion shown in Context
   and Orientation above; the design note can include it
   verbatim).

4. *Validation rules.* The four checks listed in Context and
   Orientation. Show example error messages.

5. *Field-name derivation rule.* The `<initials><Slot>`
   convention, with the rationale that
   `DuplicateRecordFields` is enabled so collisions wouldn't
   error but would obscure pattern-matches.

6. *What's deferred.* (a) A default `View v = RegFile rs` for
   aggregates that don't opt in — the current splice is
   opt-in; aggregates without an invocation simply have no
   `View`. (b) Lifting `viewFor` into the transducer's
   evolution loop — the synthesis note explicitly says the
   transducer doesn't know about it. (c) Generic `Singleton`
   class shared across aggregates — each invocation
   generates its own SVertex GADT.

7. *Worked expansion.* The full `UserView` / `SUserVertex` /
   `userView` listing.

Acceptance: the file exists, ~150-200 lines.

**Milestone 2 — Splice scaffolding.** Add the new top-level
splice to `src/Keiki/Generics/TH.hs` as a stub. Two edits:

(a) Extend the module's export list (currently `(
deriveAggregateCtors , deriveWireCtors )`) to include
`deriveView`.

(b) Add the body. Initially:

    deriveView
      :: Name -> Name -> String -> String -> String
      -> [(String, [String])] -> Q [Dec]
    deriveView vertexName regsName sVertexNameStr viewNameStr
               viewFunNameStr spec = do
      -- Step 1: validation
      ctors <- reifyCtors vertexName "deriveView"
      let vertexCtorNames = concatMap conNames ctors
          specNames       = map fst spec
      validateSpecCoverage vertexCtorNames specNames
      slotNames <- reifySlotNames regsName
      mapM_ (validateSpecSlots slotNames) spec
      -- Step 2: code-gen (M3 stub)
      fail "deriveView: code-gen not yet implemented"

(c) Add the validation helpers (`validateSpecCoverage`,
`validateSpecSlots`, `reifySlotNames`) and tests for them by
trial: invoke the splice in a throw-away `.hs` file under
`test/` (or in GHCi) and confirm the validation errors fire.

`cabal build all` succeeds. The splice is exported but not yet
invoked; the build is unaffected.

Acceptance: `cabal build all` succeeds. The new export is
visible (`grep deriveView src/Keiki/Generics/TH.hs` matches the
export and the body).

**Milestone 3 — Splice code-gen.** Replace the `fail "…"` body
with the actual code-gen. The body builds three declaration
groups:

(a) *Singletons GADT.* Build a `DataD` declaration with a
GADT-style constructor for each vertex:

    data SUserVertex (v :: Vertex) where
      SPotentialCustomer :: SUserVertex 'PotentialCustomer
      ...

In TH this is `DataD [] sVertexName [KindedTV v BndrReq
(ConT vertexName)] Nothing [GadtC [sCtorName] [] (AppT
(ConT sVertexName) (PromotedT vertexCtorName))] []` (one
`GadtC` per vertex). Append `StandaloneDerivD` for `Show` and
`Eq`.

(b) *View GADT.* Build a `DataD` declaration with a constructor
per vertex carrying the live slots as record fields. Each
constructor is a `RecGadtC`:

    data UserView (v :: Vertex) where
      PotentialCustomerV :: UserView 'PotentialCustomer
      ConfirmedV :: { cfEmail :: Email, cfConfirmedAt :: UTCTime }
                 -> UserView 'Confirmed
      ...

Empty-slot vertices use `GadtC` (no fields). Non-empty use
`RecGadtC` with `(fieldName, Bang NoSourceUnpackedness
NoSourceStrictness, fieldType)` for each slot. Field names are
the `<initials><Slot>` convention.

(c) *Projection function.* Build a `FunD` declaration with one
clause per vertex:

    userView :: SUserVertex v -> RegFile UserRegRegs -> UserView v
    userView SPotentialCustomer _ = PotentialCustomerV
    userView SConfirmed regs = ConfirmedV (regs ! #email)
                                          (regs ! #confirmedAt)
    ...

Each clause's pattern is `[ConP sCtorName [] [], regsPat]`
where `regsPat` is `WildP` for empty-slot vertices or `VarP
regsName` for non-empty. The body is `ConE viewCtorName`
applied to a `(!)` invocation per slot. Read the slot via
`(VarE regsName) (!) (LabelE slotName)` (i.e. the
`OverloadedLabels` desugaring; in TH this is `VarE '(!)`
applied to `regsName` and `LabelE slotName`).

Pulling the slot type from the slot list (needed for the
field-type position in `RecGadtC`) requires walking the slot-
list `Type` value the splice already extracts in M2's
`reifySlotNames`. Generalize that helper to return
`[(String, Type)]` so the type is available alongside the
name.

`cabal build all` still succeeds (no invocation site yet).

Acceptance: a smoke-test invocation in a throw-away module
(e.g. drop the `UserRegistration` invocation into a temporary
file) compiles and the generated code can be inspected via
`-ddump-splices`.

**Milestone 4 — Wire splice into UserRegistration.** Edit
`src/Keiki/Examples/UserRegistration.hs`:

(a) Add the splice invocation. Place it immediately after the
existing `$(deriveWireCtors …)` block (around line 240):

    $(deriveView ''Vertex ''UserRegRegs
        "SUserVertex" "UserView" "userView"
        [ ("PotentialCustomer",    [])
        , ("Registering",          [])
        , ("RequiresConfirmation", ["email", "confirmCode"])
        , ("Confirmed",            ["email", "confirmedAt"])
        , ("Deleted",              ["email", "deletedAt"])
        ])

(b) Extend the module's exports list (`src/Keiki/Examples/
UserRegistration.hs:30-69`) to include the generated names:

      , -- * B-presentation views (TH-derived)
        SUserVertex (..)
      , UserView (..)
      , userView

(c) Add a brief haddock paragraph above the splice invocation
explaining what the B-view does and pointing at
`docs/research/genview-th-splice-design.md` and the synthesis
note's §3.

`cabal build all` succeeds.

Acceptance: `cabal build all` succeeds. The exports
`UserView` and `SUserVertex` are visible from
`Keiki.Examples.UserRegistration` (verify via `:browse
Keiki.Examples.UserRegistration` in GHCi).

**Milestone 5 — Test module.** Create
`test/Keiki/Examples/UserRegistrationViewSpec.hs`:

    module Keiki.Examples.UserRegistrationViewSpec (spec) where

    import Test.Hspec
    import Data.Time (UTCTime, parseTimeOrError, defaultTimeLocale)

    import Keiki.Core (RCons, RNil, RegFile)
    import Data.Proxy (Proxy (..))
    import Keiki.Examples.UserRegistration

    spec :: Spec
    spec = describe "UserView projection" $ do
      it "projects PotentialCustomer to PotentialCustomerV" $
        userView SPotentialCustomer emptyRegs
          `shouldBe` PotentialCustomerV

      it "projects Registering to RegisteringV" $
        userView SRegistering emptyRegs
          `shouldBe` RegisteringV

      it "projects Confirmed to ConfirmedV with email + confirmedAt" $ do
        let regs = -- construct a UserRegRegs with the slots set
              -- Use unsafeCombine + USet semantics or a hand-built
              -- RCons tower.
              hsRegs "alice@x.io" "Z9F4" t0 t1 t2
        userView SConfirmed regs
          `shouldBe` ConfirmedV "alice@x.io" t1

      it "projects RequiresConfirmation to RCV with email + confirmCode" $ do
        let regs = hsRegs "alice@x.io" "Z9F4" t0 t1 t2
        userView SRequiresConfirmation regs
          `shouldBe` RequiresConfirmationV "alice@x.io" "Z9F4"

      it "projects Deleted to DeletedV with email + deletedAt" $ do
        let regs = hsRegs "alice@x.io" "Z9F4" t0 t1 t2
        userView SDeleted regs
          `shouldBe` DeletedV "alice@x.io" t2

    -- Hand-build a UserRegRegs with the five slots set.
    hsRegs
      :: Email -> ConfirmationCode -> UTCTime -> UTCTime -> UTCTime
      -> RegFile UserRegRegs
    hsRegs email code regAt confAt delAt =
      RCons (Proxy @"email") email
      $ RCons (Proxy @"confirmCode") code
      $ RCons (Proxy @"registeredAt") regAt
      $ RCons (Proxy @"confirmedAt") confAt
      $ RCons (Proxy @"deletedAt") delAt
      $ RNil

    t0, t1, t2 :: UTCTime
    t0 = parseTimeOrError True defaultTimeLocale "%Y-%m-%d %H:%M:%S %Z"
                          "2026-05-02 09:00:00 UTC"
    t1 = parseTimeOrError True defaultTimeLocale "%Y-%m-%d %H:%M:%S %Z"
                          "2026-05-02 09:31:00 UTC"
    t2 = parseTimeOrError True defaultTimeLocale "%Y-%m-%d %H:%M:%S %Z"
                          "2026-05-02 10:00:00 UTC"

(Note: `RCons`/`RNil` and `Proxy` may need to be re-exported from
`Keiki.Core` if not already; if necessary, add
`Keiki.Core.RegFile (..)` to the export — but `Core.hs:32-33`
already exports `RegFile (..)`, so the constructors are
available.)

Wire into `test/Spec.hs`:

    import qualified Keiki.Examples.UserRegistrationViewSpec
    -- in main:
    describe "Keiki.Examples.UserRegistration (view)"
             Keiki.Examples.UserRegistrationViewSpec.spec

Add to `keiki.cabal`'s `keiki-test:other-modules`:

    Keiki.Examples.UserRegistrationViewSpec

    nix-shell -p z3 --run "cabal test all" 2>&1 | tail -3

Acceptance: 95 baseline + 5 new (or however many tests land), 0
failures. Hspec reports a `Keiki.Examples.UserRegistration
(view)` describe block.

**Milestone 6 — Docs update + commit.** Edit
`docs/research/keiki-generics-design.md` to mark the `genView`
entry Implemented (search for "genView" in the file; the
"Future improvements" list is the section to update). Append a
sentence: *"**Implemented (see EP-13 / MP-5)** — `deriveView`
splice in `Keiki.Generics.TH`; worked example
`UserView` / `SUserVertex` / `userView` in
`Keiki.Examples.UserRegistration`."*

Edit
`docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`,
§3 (around line 155 — the line that reads "A `genView` TH
helper is a nice-to-have, not a v1 requirement"). Replace with:
*"A `genView` TH helper now exists as
`Keiki.Generics.TH.deriveView` (see EP-13 / MP-5 and
`docs/research/genview-th-splice-design.md`)."*

Stage and commit:

    git add src/Keiki/Generics/TH.hs \
            src/Keiki/Examples/UserRegistration.hs \
            test/Keiki/Examples/UserRegistrationViewSpec.hs \
            test/Spec.hs \
            keiki.cabal \
            docs/research/genview-th-splice-design.md \
            docs/research/keiki-generics-design.md \
            docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md \
            docs/masterplans/5-...md \
            docs/plans/13-...md
    git commit -m "$(cat <<'EOF'
    feat(generics): EP-13 — deriveView TH splice for B-presentation View v GADT

    Add Keiki.Generics.TH.deriveView splice that generates a per-
    aggregate singletons GADT (S<Vertex>), a per-aggregate View v
    GADT with one constructor per vertex carrying live slots as
    typed fields, and the viewFor projection from singletons +
    register file to the View GADT. Wired into
    UserRegistration as UserView / SUserVertex / userView.

    First materializes the B-presentation per-vertex projection
    that synthesis §3 motivated as opt-in.

    MasterPlan: docs/masterplans/5-acceptor-projections-and-genview-th-splice-for-b-presentation.md
    ExecPlan: docs/plans/13-genview-th-splice-and-b-presentation-view-v-gadt.md
    Intention: intention_01knjzws4qezz9w8b0743zfqv8
    EOF
    )"

Acceptance: `git log -1 --format='%B'` shows all three trailers
and a Conventional Commits header. The keiki-generics-design
note's `genView` entry is marked Implemented.


## Concrete Steps

All commands run from `/Users/shinzui/Keikaku/bokuno/keiki/`.

**M0 baseline:**

    cabal build all
    nix-shell -p z3 --run "cabal test all" 2>&1 | tail -3

**M1 design note.** Create the file with the section structure
in Plan of Work / M1.

**M2 splice scaffolding.** Edit `src/Keiki/Generics/TH.hs`:

- Extend the module export list to include `deriveView`.
- Add the splice signature, validation helpers, and a `fail`
  body.

    cabal build all

**M3 splice code-gen.** Replace the `fail` body with the actual
code-gen per Plan of Work / M3.

    cabal build all

You can validate the generated code shape with
`-ddump-splices` by adding `ghc-options: -ddump-splices` to a
throw-away executable that imports the splice. Don't commit
that.

**M4 wire into UserRegistration.** Edit
`src/Keiki/Examples/UserRegistration.hs` per Plan of Work / M4.

    cabal build all

**M5 test module.** Create
`test/Keiki/Examples/UserRegistrationViewSpec.hs`. Edit
`test/Spec.hs` to register the spec. Edit `keiki.cabal` to add
the new `other-modules` entry.

    nix-shell -p z3 --run "cabal test all" 2>&1 | tail -3

**M6 docs + commit.** Edit `keiki-generics-design.md` and the
synthesis note. Stage and commit per Plan of Work / M6.


## Validation and Acceptance

After all six milestones:

- `cabal build all` succeeds with no warnings.
- `nix-shell -p z3 --run "cabal test all"` reports baseline + 5
  examples, 0 failures.
- `docs/research/genview-th-splice-design.md` exists and
  documents the splice.
- `Keiki.Generics.TH` exports `deriveView`.
- `Keiki.Examples.UserRegistration` exports `UserView (..)`,
  `SUserVertex (..)`, `userView`.
- `docs/research/keiki-generics-design.md`'s `genView` entry is
  marked Implemented.

Behavioral acceptance (the load-bearing tests):

1. **Empty-slot projection.** `userView SPotentialCustomer
   emptyRegs == PotentialCustomerV`. The nullary constructor
   case works.

2. **Single-vertex projection.** `userView
   SRequiresConfirmation regs == RequiresConfirmationV email
   confirmCode` for hand-constructed `regs` with the named
   slots set.

3. **Two-slot projection.** `userView SConfirmed regs ==
   ConfirmedV email confirmedAt`.

4. **Pattern-match exhaustiveness.** The generated `userView`
   covers every `SUserVertex` constructor. (Verified by GHC's
   pattern checker; if the spec list misses a vertex, M3's
   `validateSpecCoverage` rejects at splice time.)

5. **Validation diagnostics.** A spec entry naming a
   non-existent vertex (`("BadVertex", [])`) fails at splice
   time with the message
   `deriveView: spec entry "BadVertex" is not a constructor of Vertex`.
   A spec entry naming a non-existent slot
   (`("Confirmed", ["badSlot"])`) fails with
   `deriveView: spec entry "Confirmed" names slot "badSlot" which is not in UserRegRegs`.

   (M2's validation tests cover these — they don't have to be
   in the test suite if validating-via-fail-at-splice-time
   isn't easily testable; document the manual check in M2's
   acceptance instead.)


## Idempotence and Recovery

The plan's milestones are mostly additive:

- M1 creates a new file.
- M2 adds an export and a splice body to an existing module.
- M3 changes the splice body in place.
- M4 adds a splice invocation and exports to an existing
  module.
- M5 creates new test files and adds one-line entries to
  `test/Spec.hs` and `keiki.cabal`.
- M6 edits two existing docs and creates a commit.

Recovery from a failing TH splice:

- *`-ddump-splices` is your friend.* Add `ghc-options:
  -ddump-splices` to the `library` stanza temporarily; rebuild;
  inspect the generated code. Look for shape mismatches between
  what M3 emits and what GHC accepts.
- *`fail` messages bubble up as compile-time errors.* If
  validation is firing, the message at the user's invocation
  site names the failing spec entry.
- *GADT field types.* Slot types must be available at the
  splice site. The walk over the slot-list `Type` returns
  `[(String, Type)]`; the `Type` is plumbed into `RecGadtC`
  field bangs directly. If types come out wrong, inspect with
  `runQ [t| <slot type> |]` in GHCi.

Recovery from a failing test:

- *`shouldBe` mismatch on field values.* The `RegFile`'s `(!)`
  reads slot-by-slot; mismatches usually mean the hand-
  constructed test fixture put values in the wrong slots.
  Re-derive the fixture from `emptyRegs` plus a sequence of
  `runUpdate` calls if hand-RCons gets fiddly.

Recovery from a bad design milestone (M1):

- The design note is a Markdown file; rewrite freely.

Recovery from a bad commit:

- `git revert` and reopen the splice work.


## Interfaces and Dependencies

New types and functions:

    -- src/Keiki/Generics/TH.hs (extends existing module)
    deriveView
      :: Name -> Name -> String -> String -> String
      -> [(String, [String])] -> Q [Dec]

Generated by the splice (per invocation; example shapes for
the `UserRegistration` invocation):

    data SUserVertex (v :: Vertex) where
      SPotentialCustomer    :: SUserVertex 'PotentialCustomer
      SRegistering          :: SUserVertex 'Registering
      SRequiresConfirmation :: SUserVertex 'RequiresConfirmation
      SConfirmed            :: SUserVertex 'Confirmed
      SDeleted              :: SUserVertex 'Deleted

    data UserView (v :: Vertex) where
      PotentialCustomerV    :: UserView 'PotentialCustomer
      RegisteringV          :: UserView 'Registering
      RequiresConfirmationV :: { rcEmail :: Email, rcConfirmCode :: ConfirmationCode }
                            -> UserView 'RequiresConfirmation
      ConfirmedV            :: { cfEmail :: Email, cfConfirmedAt :: UTCTime }
                            -> UserView 'Confirmed
      DeletedV              :: { dEmail  :: Email, dDeletedAt    :: UTCTime }
                            -> UserView 'Deleted

    deriving instance Show (SUserVertex v)
    deriving instance Eq   (SUserVertex v)
    deriving instance Show (UserView v)
    deriving instance Eq   (UserView v)

    userView :: SUserVertex v -> RegFile UserRegRegs -> UserView v

New / modified modules:

- `Keiki.Generics.TH` (modified) — exports `deriveView`.
- `Keiki.Examples.UserRegistration` (modified) — invokes
  `deriveView`; exports the generated `UserView (..)`,
  `SUserVertex (..)`, `userView`.
- `Keiki.Examples.UserRegistrationViewSpec` (new) — exercises
  the projection.

Existing functions consumed:

- `Language.Haskell.TH` for the splice (`Name`, `Q`, `Dec`,
  `reify`, `DataD`, `GadtC`, `RecGadtC`, `FunD`, etc.).
- `Keiki.Core.RegFile`, `(!)` and the `OverloadedLabels` /
  `IsLabel` machinery already in `Keiki.Core`.

No new external dependencies. `template-haskell` is already a
build-dependency (see `keiki.cabal` line 47).

The MasterPlan parent
(`docs/masterplans/5-acceptor-projections-and-genview-th-splice-for-b-presentation.md`)
governs coordination with EP-12 (the Acceptor projections plan).
EP-12 and EP-13 are independent — they can run in either order.
The one possible edit collision is in
`Keiki.Examples.UserRegistration` (per IP-2 of the MasterPlan):
EP-12 only reads the module; EP-13 adds exports. If both are in
flight, sequence the exports edit after EP-12 lands or rebase.
