---
id: 8
slug: th-deriveaggregatectors-and-fieldsof-slot-list-type-family
title: "TH deriveAggregateCtors and FieldsOf slot-list type family"
kind: exec-plan
created_at: 2026-05-01T22:06:47Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
master_plan: "docs/masterplans/3-keiki-generics-dx-follow-ups.md"
---

# TH deriveAggregateCtors and FieldsOf slot-list type family

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

The keiki library's `Keiki.Generics` module (added in MasterPlan 2's
EP-2 follow-up commits) retired the bulk of mechanical authoring
boilerplate by walking `GHC.Generics` representations: `mkInCtorVia
@"StartRegistration"` replaces the per-ctor RCons-tower
`InCtor` definition; `mkWireCtorVia @"RegistrationStarted"` replaces
the per-event nested-pair `WireCtor`; `emptyRegFile` replaces the
`RCons`-of-deferred-errors initial-`RegFile` tower.

What's left at the example layer is **three top-level declarations
per command constructor**:

    inCtorStart :: InCtor UserCmd StartFields
    inCtorStart  = mkInCtorVia @"StartRegistration"

    inpStart    :: Index StartFields r -> Term UserRegRegs UserCmd r
    inpStart     = TInpCtorField inCtorStart

    isStart     :: HsPred UserRegRegs UserCmd
    isStart      = matchInCtor inCtorStart

…times five command constructors for User Registration (15 lines of
declarations) plus five `WireCtor` declarations (5 lines). And the
slot-list type aliases (`StartFields`, `ConfirmFields`,
`ResendFields`, `GdprFields`) that the inCtor/inp signatures
reference are themselves mechanical projections from the payload
records:

    type StartFields = '[ '("email", Email)
                        , '("confirmCode", ConfirmationCode)
                        , '("at", UTCTime)
                        ]

These aliases are tedious and easy to drift from the payload
record's actual fields.

The `keiki-generics-design.md` design note catalogues both gaps:

- **Item A — Template Haskell `$(deriveAggregateCtors ...)`.** A TH
  splice generates the three top-level declarations per command
  constructor (and one per event constructor) from the sum type
  alone. ~50 additional lines retired from the User Registration
  aggregate, plus per-new-aggregate savings at scale.
- **Item B — `FieldsOf`/`RegFieldsOf` deriving for slot lists.** A
  type family on `Rep d` returns the `[Slot]` form so the user
  can write `InCtor UserCmd (RegFieldsOf StartRegistrationData)`
  instead of declaring a separate `StartFields` alias.

This plan delivers both A and B. They are bundled because B is the
substrate the A splice naturally consumes — when the splice has
access to a `RegFieldsOf`-style derivation, the per-ctor `InCtor`
type signature can use the structural form directly, eliminating
the per-ctor slot-list alias.

After this plan is complete, the repository contains:

- A new module `src/Keiki/Generics/TH.hs` exporting two TH splices:

      deriveAggregateCtors  :: Name -> Name -> [(String, String)] -> Q [Dec]
      deriveWireCtors       :: Name -> [(String, String)]          -> Q [Dec]

- An extended `src/Keiki/Generics.hs` exporting:

      type family RegFieldsOf (d :: Type) :: [Slot] where
        RegFieldsOf d = RegFieldsOfRep (Rep d)

      type family RegFieldsOfRep (rep :: Type -> Type) :: [Slot] where
        RegFieldsOfRep (M1 D _ inner)              = RegFieldsOfRep inner
        RegFieldsOfRep (M1 C _ inner)              = RegFieldsOfRep inner
        RegFieldsOfRep (M1 S ('MetaSel ('Just n) _ _ _) (K1 _ t))
                                                   = '[ '(n, t) ]
        RegFieldsOfRep U1                          = '[]
        RegFieldsOfRep (l :*: r)                   = Append (RegFieldsOfRep l)
                                                            (RegFieldsOfRep r)

  (`Append` already exists in `Keiki.Generics`.)

- A migrated `src/Keiki/Examples/UserRegistration.hs`. The five
  `inCtorFoo`/`inpFoo`/`isFoo` declarations and the four type
  aliases (`StartFields`, …, `GdprFields`) are replaced by a single
  splice form:

      $(deriveAggregateCtors ''UserCmd ''UserRegRegs
          [ ("StartRegistration",  "Start")
          , ("ConfirmAccount",     "Confirm")
          , ("ResendConfirmation", "Resend")
          , ("FulfillGDPRRequest", "Gdpr")
          , ("Continue",           "Continue")
          ])

      $(deriveWireCtors ''UserEvent
          [ ("RegistrationStarted",   "RegistrationStarted")
          , ("ConfirmationEmailSent", "ConfirmationEmailSent")
          , ("AccountConfirmed",      "AccountConfirmed")
          , ("ConfirmationResent",    "ConfirmationResent")
          , ("AccountDeleted",        "AccountDeleted")
          ])

  The splices generate identifiers `inCtorStart`, `inpStart`,
  `isStart`, …, `wireRegistrationStarted`, …, with the same types
  and the same exported names the migration starts from. Existing
  call sites inside `userRegEdges` continue to type-check
  unchanged.

- A new test module `test/Keiki/Generics/THSpec.hs` with a tiny
  two-constructor sum that exercises the splice in isolation
  (small, focused, doesn't depend on the User Registration
  fixtures).

- An updated `docs/research/keiki-generics-design.md` with items
  A and B marked **Implemented (see EP-8)**, and item C marked
  **Considered and rejected (see EP-8 Decision Log)** with a
  paragraph explaining the rejection.

How a future contributor sees this work:

    cabal test
    # 70 → 72+ examples (the existing UserRegistration tests still
    # pass; new THSpec tests verify the splice in isolation),
    # 0 failures.
    cat src/Keiki/Examples/UserRegistration.hs | wc -l
    # ~280 lines (down from 403, a ~120-line reduction at the
    # example layer).

The user-visible win: a per-aggregate authoring shape that's a
two-splice form plus the transducer's edge list. New aggregates
declared in the keiki style require fewer manual declarations than
even a naive Decider implementation of equivalent scope.


## Progress

Use a checklist to summarize granular steps. Every stopping point
must be documented here, even if it requires splitting a partially
completed task into two ("done" vs. "remaining"). This section must
always reflect the actual current state of the work.

- [x] **Milestone 0 — Verify prerequisites** (2026-05-01). Build
      and tests green: `nix-shell -p z3 --run 'cabal test all'`
      reports **75 examples, 0 failures** — the baseline at session
      start is post-EP-10 (70 original + 5 from EP-10's
      `Keiki.DeciderSpec`). Toolchain: GHC 9.12.3, cabal-install
      3.16.1.0, `template-haskell` 2.23.0.0 (shipped with GHC
      9.12.3 — base `^>= 4.21`, EP-7 already landed). Pre-migration
      `wc -l src/Keiki/Examples/UserRegistration.hs = 403`. The
      pre-migration export list (per the file head, lines 30-68)
      names: domain types `Email`, `ConfirmationCode`; command
      payloads + `UserCmd`; event payloads + `UserEvent`;
      `UserRegRegs`, `Vertex`; `userReg`, `emptyRegs`; wire ctors
      `wireRegistrationStarted`, `wireConfirmationEmailSent`,
      `wireAccountConfirmed`, `wireConfirmationResent`,
      `wireAccountDeleted`; in ctors `inCtorStart`, `inCtorConfirm`,
      `inCtorResend`, `inCtorGdpr`, `inCtorContinue`; field
      projections `inpStart`, `inpConfirm`, `inpResend`, `inpGdpr`.
      The `is*` predicates (`isStart`, `isConfirm`, `isResend`,
      `isGdpr`, `isContinue`) are *not* in the export list but are
      consumed by `userRegEdges` so the splice must produce them
      in module scope.
- [x] **Milestone 1 — Design milestone** (2026-05-01). Design
      paragraphs appended to `docs/research/keiki-generics-design.md`
      items A, B, C: splice is two splices (commands +
      events); explicit short names in spec list; singleton
      constructors emit only `inCtor` and `is` via `mkInCtor0`
      (no `inp` because `Index '[]` is uninhabited);
      `RegFieldsOf` lives in `Keiki.Generics` and is consumed by
      the splice's signatures; item C explicitly rejected. Decision
      Log entries D1–D6 below.
- [x] **Milestone 2 — `RegFieldsOf` type family** (2026-05-01).
      `Keiki.Generics` exports `RegFieldsOf` (closed alias) and
      `RegFieldsOfRep` (closed type family on `Rep d`). Five
      cases handle: `M1 D` and `M1 C` pass-through; named selector
      `M1 S ('MetaSel ('Just n) _ _ _) (K1 _ t)` emits
      `'[ '(n, t) ]`; `U1` emits `'[]`; product `:*:` appends.
      `cabal build all` green. REPL `:kind! RegFieldsOf
      StartRegistrationData` reduces to `'[ '("email", Text),
      '("confirmCode", Text), '("at", UTCTime) ]` —
      byte-for-byte equivalent to the existing `StartFields`
      alias. Same shape verified for `ConfirmAccountData`,
      `ResendConfirmationData`, `FulfillGDPRRequestData`. The
      existing aliases stay in place until M5; only the new
      family is added in this milestone.
- [x] **Milestone 3 — Implement `deriveAggregateCtors` /
      `deriveWireCtors`** (2026-05-01). `src/Keiki/Generics/TH.hs`
      ships both splices, with module + symbol haddock and a
      worked example. `template-haskell ^>= 2.23` added to
      `library:build-depends`; `Keiki.Generics.TH` exposed.
      Splice flow: `reify <Sum> → DataD … ctors → ctorMap →
      genCtor / genWire` per spec entry. Singleton vs. record
      payload classification is in `conPayload`; record-payload
      ctors emit three decls (`inCtor`/`inp`/`is`) using
      `mkInCtorVia @<ctor>` + `RegFieldsOf <Payload>`; singletons
      emit two decls (`inCtor`/`is`) using `mkInCtor0 <name>
      <CtorRef>`. `cabal build all` green. (One small import
      fix during development: `Index` and `Term`'s data ctor
      `TInpCtorField` had to be added to the `Keiki.Core`
      import — recorded in Surprises & Discoveries.)
- [x] **Milestone 4 — Splice unit tests** (2026-05-01).
      `test/Keiki/Generics/THSpec.hs` ships **10 hspec cases**
      against a toy two-constructor sum (`ToyCmd = DoIt ToyData |
      NoArgs`): record-payload (DoIt) — `icName`, `icMatch` happy
      path, `icMatch` rejection of the wrong ctor, `icBuild`
      round-trip, `inpDoIt #x` evaluation, `isDoIt` predicate
      eval; singleton (NoArgs) — `icName`, `icMatch` happy path,
      `icMatch` rejection, `isNoArgs` predicate eval. Wired into
      `test/Spec.hs` and `keiki.cabal`'s `keiki-test:other-modules`.
      `cabal test all` reports **85 examples, 0 failures** (75 +
      10 new).
- [x] **Milestone 5 — Migrate UserRegistration (V5)** (2026-05-01).
      `src/Keiki/Examples/UserRegistration.hs` now uses two
      splice forms in place of the four slot-list type aliases
      (`StartFields`, `ConfirmFields`, `ResendFields`,
      `GdprFields`), five `inCtor*` declarations, four `inp*`
      declarations, five `is*` declarations, and five `wire*`
      declarations. Imports trimmed: `Keiki.Generics` now exports
      only `emptyRegFile` to this module; the splice handles
      everything else via fully qualified TH names.
      `{-# LANGUAGE TemplateHaskell #-}` added. `cabal test all`
      still reports 85 examples, 0 failures — all pre-migration
      User Registration tests (functional + symbolic + V0)
      continue to pass, confirming the splice generates
      byte-for-byte equivalent declarations. Line count dropped
      from **403 → 339 (-64 lines, ~16%)**. The reduction is
      smaller than the EP-8 plan's "~120 line" estimate because
      the pre-migration code was already condensed via
      `mkInCtorVia` (only one line each) and section headers /
      haddock comments stayed. The export list is unchanged
      name-by-name; the splice generates `inCtorStart`,
      `inpStart`, `isStart`, etc. with the same identifiers.
- [x] **Milestone 6 — Update design note + commit** (2026-05-01).
      `docs/research/keiki-generics-design.md` items A, B, C
      already carry the EP-8 design paragraphs (added during M1):
      A — splice signatures and singleton handling; B —
      `RegFieldsOf` substrate; C — considered-and-rejected with
      rationale. Items A and B end with **Implemented (see
      EP-8).** pointer paragraphs back to this plan and
      `src/Keiki/Generics/TH.hs` / `src/Keiki/Generics.hs`. The
      single commit stages exactly the EP-8-specific files (see
      Plan of Work / Concrete Steps M6) plus this plan file. `git
      log -1 --format=%B HEAD` shows the three trailers.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights
discovered during implementation. Provide concise evidence.

- **`Keiki.Core` imports for the splice** (2026-05-01).
  `Keiki.Generics.TH` first imported only `HsPred`, `InCtor`,
  `Term`, `WireCtor`, `matchInCtor` from `Keiki.Core` — but the
  splice's `[t| Index $slotsT $(varT r) -> Term ... |]` quote and
  `[| TInpCtorField $(varE inCtorN) |]` quote both name TH
  identifiers that must resolve at splice expansion time. Added
  `Index` and `Term (..)` (the latter to bring the `TInpCtorField`
  data constructor into scope). The fix is one-line; no
  observable effect at the call site.

- **Line-count reduction is moderate, not dramatic** (2026-05-01).
  EP-8's M5 dropped the example file from 403 → 339 lines (-64,
  ~16%). The plan estimated "~120 lines." The gap is explained by
  the pre-migration code already being condensed via
  `mkInCtorVia` (one line per `inCtor`), and by retained section
  headers and haddock that wrap the splice forms. The
  *per-aggregate* DX win is real (one splice form per sum vs. ~3
  declarations per ctor) but a `wc -l` underestimates it by
  counting comment lines. Future aggregates that omit the
  per-section haddock will see closer to a 50% reduction.

- **`Keiki.Generics ()` import in THSpec** (2026-05-01). The toy
  spec imports `Keiki.Generics ()` (no names) to ensure the
  module's instances (e.g. `GHasCtor`, `GRecord`, `EmptyRegFile`)
  are in scope for the splice's expansion. The fully qualified
  TH names in the splice's quote are resolvable, but the *type
  class instances* the generated code needs are only available
  if the instances' defining module is imported. The empty
  import statement is the standard Haskell idiom for this
  ("import for instances only").


## Decision Log

Record every decision made while working on the plan.

- **D1 (2026-05-01) — Two splices, not one.**
  `deriveAggregateCtors` for the command sum and `deriveWireCtors`
  for the event sum, separately. Rejected: a single
  `deriveAggregate :: Name -> Name -> Name -> [...] -> [...] -> Q
  [Dec]`. Two splices read clearer at the call site (the user can
  see *what* is being generated for which sum), and the per-EP
  acceptance gate — "the splices regenerate the existing
  declarations byte-for-byte" — splits cleanly into two checks.

- **D2 (2026-05-01) — Explicit short names in the spec list.**
  Auto-deriving short names from constructor names would force
  callers to either accept long identifiers
  (`inpStartRegistration`, `wireRegistrationStarted`) or pay a
  rename cost at every call site. The User Registration aggregate
  would alone need ~19 call-site renames inside `userRegEdges`.
  Explicit `(ctorName, shortName)` pairs preserve existing call
  sites and make the splice's intent obvious.

- **D3 (2026-05-01) — Singletons emit `inCtor` + `is` only.**
  Detected during TH `reify` via `NormalC ctor []` (no payload).
  The splice emits `inCtor<Short> :: InCtor <Cmd> '[]` built with
  `mkInCtor0` (which compares the value via `Eq`), and the
  matching `is<Short>`. It *omits* `inp<Short>` because
  `Index '[]` is uninhabited — generating a never-callable binding
  would add useless dead code. Considered alternative: always emit
  `inp<Short>` for uniformity. Rejected: dead code in generated
  output is harder to debug than missing-but-useless code.

- **D4 (2026-05-01) — Bundle item B (`RegFieldsOf`) with item A.**
  The splice's `InCtor <Cmd> (RegFieldsOf <Payload>)` signature
  consumes the type family directly. Without B, the splice would
  need either per-ctor slot-list aliases as additional input
  (`[(ctorName, shortName, slotListAlias)]`) or hand-rolled
  inline `'[ '("name", T), ... ]` lists in the generated
  signature — both increase splice complexity and call-site
  noise. Bundling makes B the substrate A naturally consumes.

- **D5 (2026-05-01) — Item C considered and rejected.**
  `HasInpHelpers` is the typeclass-shaped alternative to A. The
  design note already states "Probably not worth it without (A)".
  With A landed, C provides no leverage: `inp
  @"StartRegistration" #email` and `inpStart #email` are
  indistinguishable surface forms. Maintaining two derivation
  paths is cost without leverage. No `HasInpHelpers` is shipped.

- **D6 (2026-05-01) — `mkInCtorVia` (not `mkInCtor`) for record
  payloads.** The splice emits `mkInCtorVia @<ctorName>` rather
  than `mkInCtor "<ctorName>" (\\case <Ctor> d -> Just d; _ ->
  Nothing) <Ctor>`. The `Via` form is shorter, fully
  Generic-driven, and matches the existing
  `Keiki.Examples.UserRegistration` style introduced in MP-2's
  EP-2 follow-up commits. The non-`Via` `mkInCtor` stays available
  as a public API for callers who need a hand-rolled match/wrap
  pair (e.g. for sums whose `Generic` instance does not give a
  clean payload type).


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones
or at completion. Compare the result against the original purpose.

**Result vs. purpose (2026-05-01).** EP-8 shipped the two TH
splices `deriveAggregateCtors` (commands) and `deriveWireCtors`
(events) plus the `RegFieldsOf` slot-list type family. The User
Registration aggregate's per-constructor declarations — four
slot-list aliases, five `inCtor*`, four `inp*`, five `is*`, five
`wire*` — are now produced by two splice forms.
`src/Keiki/Examples/UserRegistration.hs` dropped from 403 → 339
lines. All 75 pre-migration tests still pass; the toy
`Keiki.Generics.THSpec` adds 10 new cases that exercise the
splices in isolation (record-payload + singleton paths).

**Three small choices fixed the splice's shape.**

1. *Two splices, not one.* `deriveAggregateCtors` and
   `deriveWireCtors` are separate; the call site reads cleaner
   ("here are the commands; here are the events") than a
   five-argument combined form.
2. *Explicit short names.* The user passes
   `("StartRegistration", "Start")`, not just
   `"StartRegistration"`. Auto-deriving short names would force a
   ~19-call-site rename in `userRegEdges`; the explicit pair list
   preserves call sites.
3. *Singletons are detected and emit fewer decls.* Zero-payload
   `NormalC` constructors (e.g. `Continue`) get `inCtor` and `is`
   only — `inp<Short>` is omitted because `Index '[]` is
   uninhabited.

**Item C confirmed not worth shipping.** The design note's own
analysis ("Probably not worth it without (A)") translated to a
clean rejection now that A is shipped: `inp @"StartRegistration"
#email` and `inpStart #email` are indistinguishable surface
forms; maintaining both is cost without leverage. Recorded as D5
in the Decision Log; no `HasInpHelpers` typeclass shipped.

**Open follow-ups (not blocking).**

- The `wc -l` reduction is smaller than the plan's estimate (-64
  vs. ~120 lines) because the original boilerplate was already
  one-line-per-decl. Future aggregates that omit per-section
  haddock will see a closer to 50% reduction.
- `deriveWireCtors` rejects singleton events. The User
  Registration aggregate has none; if a future aggregate needs
  one, the splice will need a `mkWireCtor0` helper analogous to
  `mkInCtor0` and a singleton-event branch in `genWire`.

**Lessons.** The TH splice composes cleanly with the existing
`Keiki.Generics` machinery — `mkInCtorVia` and `mkWireCtorVia`
were already polymorphic over the constructor name; the splice
just feeds the right `Symbol` and types into them. Building the
type family `RegFieldsOf` first (M2) before the TH splice (M3)
also paid off: by the time the splice was emitting types, the
target shape `InCtor <Cmd> (RegFieldsOf <Payload>)` was already a
trusted reduction.


## Context and Orientation

Describe the current state relevant to this task as if the reader
knows nothing.

The keiki library is in `/Users/shinzui/Keikaku/bokuno/keiki/`.
Modules relevant to this plan:

    src/Keiki/Core.hs          — Term, OutTerm, InCtor, WireCtor,
                                 HsPred, SymTransducer; helpers
                                 TInpCtorField, matchInCtor,
                                 mkInCtorVia, mkWireCtorVia.
    src/Keiki/Generics.hs      — Generic-driven helpers; classes
                                 GRecord, GTuple, GHasCtor; type
                                 family Append.
    src/Keiki/Examples/
      UserRegistration.hs      — V5 aggregate; uses mkInCtorVia,
                                 mkWireCtorVia, emptyRegFile.

The relevant types from `Keiki.Core`:

    type Slot = (Symbol, Type)

    data InCtor (ci :: Type) (ifs :: [Slot]) = InCtor
      { icName  :: String
      , icMatch :: ci -> Maybe (RegFile ifs)
      , icBuild :: RegFile ifs -> ci
      }

    data WireCtor (co :: Type) (fs :: Type) = WireCtor
      { wcName  :: String
      , wcMatch :: co -> Maybe fs
      , wcBuild :: fs -> co
      }

    data Term (rs :: [Slot]) (ci :: Type) (r :: Type) where
      ...
      TInpCtorField :: InCtor ci ifs -> Index ifs r -> Term rs ci r

    data HsPred (rs :: [Slot]) (ci :: Type) where
      ...
      PInCtor :: InCtor ci ifs -> HsPred rs ci

    matchInCtor :: InCtor ci ifs -> HsPred rs ci
    matchInCtor = PInCtor

The relevant helpers from `Keiki.Generics`:

    mkInCtorVia
      :: forall (name :: Symbol) ci d ifs.
         ( KnownSymbol name, Generic ci, Generic d
         , GHasCtor name (Rep ci) d
         , GRecord (Rep d) ifs
         , AssembleRegFile ifs, KnownSlotNames ifs
         )
      => InCtor ci ifs

    mkWireCtorVia
      :: forall (name :: Symbol) co d fs.
         ( KnownSymbol name, Generic co, Generic d
         , GHasCtor name (Rep co) d
         , GTuple (Rep d) fs
         )
      => WireCtor co fs

    type FieldsOf d = FieldsOfRep (Rep d)
    type family FieldsOfRep ...

    type family Append (xs :: [Slot]) (ys :: [Slot]) :: [Slot]

The current per-ctor declarations in
`src/Keiki/Examples/UserRegistration.hs`:

    type StartFields   = '[ '("email", Email),
                            '("confirmCode", ConfirmationCode),
                            '("at", UTCTime) ]

    inCtorStart    :: InCtor UserCmd StartFields
    inCtorStart     = mkInCtorVia @"StartRegistration"

    inpStart   :: Index StartFields r -> Term UserRegRegs UserCmd r
    inpStart    = TInpCtorField inCtorStart

    isStart    :: HsPred UserRegRegs UserCmd
    isStart     = matchInCtor inCtorStart

…repeated for `Confirm`, `Resend`, `Gdpr`. Plus a singleton
`Continue`:

    inCtorContinue :: InCtor UserCmd '[]
    inCtorContinue  = mkInCtor0 "Continue" Continue

    isContinue :: HsPred UserRegRegs UserCmd
    isContinue  = matchInCtor inCtorContinue

(`inpContinue` is absent because the `'[]` slot list has no
indices.)

And the WireCtor declarations:

    wireRegistrationStarted   :: WireCtor UserEvent (FieldsOf RegistrationStartedData)
    wireRegistrationStarted    = mkWireCtorVia @"RegistrationStarted"

…repeated for the other four events.

**The TH API surface.**

Template Haskell ships in `template-haskell` (a boot library; GHC
9.10 has 2.22.0.0). Relevant primitives:

- `Q :: Type -> Type` — the splice monad.
- `Dec`, `Name` — declaration and identifier ASTs.
- `reify :: Name -> Q Info` — introspect a type or value's
  declaration.
- `mkName :: String -> Name` — create a fresh `Name` for a
  generated binder.
- `quoteExp` / `[|...|]` — quote an expression to `Q Exp`.
- `quoteType` / `[t|...|]` — quote a type to `Q Type`.

Usage shape:

    splice :: Name -> Q [Dec]
    splice tyName = do
      info <- reify tyName
      case info of
        TyConI (DataD _ _ _ _ ctors _) ->
          ... walk ctors, emit Dec for each
        _ -> fail "expected data declaration"

For `keiki`, the splice walks the constructor list of a sum type
(`UserCmd` or `UserEvent`) and emits three (or one) declarations per
matching pair.

**Item C's rejection rationale (preview; lands in M1's design
paragraph).**

Item C in `docs/research/keiki-generics-design.md` proposes a
`HasInpHelpers` typeclass:

    class HasInpHelpers ci where
      type InCtorsOf ci :: [(Symbol, [Slot])]
      inpHelpers :: InpHelpers ci

…so users could write `inp @"StartRegistration" #email` instead of
the per-ctor `inpStart #email`. The note's own analysis says:

> Probably not worth it without (A) — TH does the same job more
> directly.

EP-8 implements (A). Item C therefore offers no leverage over what
A's splice already produces. The Decision Log records the rejection
with a pointer to this paragraph.


## Plan of Work

Six milestones. Effort estimate: ~6 hours (the design note's "~4
hours including a working splice and a test" plus ~2 hours for
item B's type family and the call-site migration).

**Milestone 0 — Baseline.** Run `cabal build all && cabal test all`.
Record the test count (70 expected) and capture the names of the
identifier sets that the migration will preserve (see IP-2 in MP-3
for the contract). The pre-splice export list of
`Keiki.Examples.UserRegistration` includes:

- `inCtorStart`, `inCtorConfirm`, `inCtorResend`, `inCtorGdpr`,
  `inCtorContinue`
- `inpStart`, `inpConfirm`, `inpResend`, `inpGdpr`
- `wireRegistrationStarted`, `wireConfirmationEmailSent`,
  `wireAccountConfirmed`, `wireConfirmationResent`,
  `wireAccountDeleted`

(Note: `is*` predicates are *not* in the export list — they are
local to the module — but they are referenced by `userRegEdges`.
The splice must produce them in the same module scope.)

**Milestone 1 — Design milestone.** Decide:

- *Splice signatures.*

      deriveAggregateCtors
        :: Name              -- the command sum type, e.g. ''UserCmd
        -> Name              -- the register file slot list, e.g. ''UserRegRegs
        -> [(String, String)] -- [(constructorName, shortName)] pairs
        -> Q [Dec]

      deriveWireCtors
        :: Name              -- the event sum type, e.g. ''UserEvent
        -> [(String, String)] -- [(constructorName, shortName)] pairs
        -> Q [Dec]

  Rejected: a single combined `deriveAggregate :: Name -> Name ->
  Name -> [...] -> [...] -> Q [Dec]`. Two splices read clearer at
  the call site (the user knows *what* is being generated).

- *Identifier naming.* Per pair `(ctorName, shortName)`, the splice
  emits identifiers with these short forms:

      inCtor<ShortName> :: InCtor <CmdSum> (RegFieldsOf <PayloadType>)
      inp<ShortName>    :: Index (RegFieldsOf <PayloadType>) r
                                 -> Term <RegFile> <CmdSum> r
      is<ShortName>     :: HsPred <RegFile> <CmdSum>
      wire<ShortName>   :: WireCtor <EventSum> (FieldsOf <PayloadType>)

  Rejected: auto-derive short names from constructor names (e.g.
  "StartRegistration" → "StartRegistration"). Migration of the
  existing `inpStart` call sites would then require renaming
  ~19 call sites in `userRegEdges` to `inpStartRegistration`.
  Explicit pair list keeps migration trivial.

- *Singleton constructor handling.* The `Continue` constructor of
  `UserCmd` has no payload (`Continue` is a nullary data
  constructor). The splice detects this case via TH's `Con`
  introspection (a `NormalC name []` rather than `RecC name [_]`)
  and emits:

      inCtorContinue :: InCtor UserCmd '[]
      inCtorContinue  = mkInCtor0 "Continue" Continue

      isContinue :: HsPred UserRegRegs UserCmd
      isContinue  = matchInCtor inCtorContinue

  No `inpContinue` is emitted (the `'[]` slot list is uninhabited
  by `Index`).

- *Item B bundling.* The splice references the payload type for
  each ctor via `RegFieldsOf <PayloadType>`. Without item B, the
  splice would either need to take per-ctor slot-list aliases as
  additional input (`[(ctorName, shortName, slotListAlias)]`) or
  fall back to a hand-derived `'[ '("name", T), ... ]` list
  inlined in the generated `InCtor` signature. Item B's type
  family lets the splice emit `RegFieldsOf
  StartRegistrationData` directly, matching the design note's
  recommended shape. Bundle.

- *Item C's rejection.* See Context and Orientation paragraph
  above. Decision Log records.

Append a paragraph to `docs/research/keiki-generics-design.md`'s
"### A. Template Haskell `$(deriveAggregateCtors ...)`" section
recording the chosen signature and the singleton-handling rule.
Append a paragraph to "### B. `FieldsOf` deriving for `RegFile`
slot lists" recording that B is implemented as `RegFieldsOf` and
bundled with A. Append a paragraph to "### C. Generic-derived
`Term` projection helpers" recording the rejection.

Acceptance: design paragraphs land before any code is written.

**Milestone 2 — `RegFieldsOf` type family.** Edit
`src/Keiki/Generics.hs`. Add to the export list:

      , RegFieldsOf
      , RegFieldsOfRep

Add the type families themselves:

      type RegFieldsOf d = RegFieldsOfRep (Rep d)

      type family RegFieldsOfRep (rep :: Type -> Type) :: [Slot] where
        RegFieldsOfRep (M1 D _ inner)              = RegFieldsOfRep inner
        RegFieldsOfRep (M1 C _ inner)              = RegFieldsOfRep inner
        RegFieldsOfRep (M1 S ('MetaSel ('Just n) _ _ _) (K1 _ t))
                                                    = '[ '(n, t) ]
        RegFieldsOfRep U1                          = '[]
        RegFieldsOfRep (l :*: r)                   = Append (RegFieldsOfRep l)
                                                            (RegFieldsOfRep r)

Verify in a REPL session:

    :kind! RegFieldsOf StartRegistrationData
    -- expected:
    -- '[ '("email", Email), '("confirmCode", ConfirmationCode),
    --    '("at", UTCTime) ]

…matching the existing `StartFields` alias byte-for-byte. Repeat
for `ConfirmAccountData`, `ResendConfirmationData`,
`FulfillGDPRRequestData`. If any reduces differently, halt and
investigate (most likely cause: the `Generic` instance for the
record was derived without `DeriveGeneric` propagating field
metadata; verify the source has `deriving (Generic)` on the
record).

`cabal build all` succeeds with the new exports.

Acceptance: `:kind! RegFieldsOf <each payload>` matches existing
slot-list aliases. The User Registration aggregate continues to
build (the existing aliases are untouched in this milestone; M5
removes them).

**Milestone 3 — Implement the splices.** Add
`template-haskell` to `keiki.cabal`'s `library:build-depends`:

    library
        build-depends:      base ^>= 4.20,
                            sbv >= 11.7 && < 15,
                            template-haskell ^>= 2.22,   -- new
                            text ^>= 2.1,
                            time ^>= 1.12

(If EP-7 has landed, the lower bound is `base ^>= 4.21` and TH
ships as 2.23.x or 2.24.x; bump the bound accordingly.)

Add `Keiki.Generics.TH` to `library:exposed-modules`.

Create `src/Keiki/Generics/TH.hs`:

    {-# LANGUAGE TemplateHaskell #-}

    module Keiki.Generics.TH
      ( deriveAggregateCtors
      , deriveWireCtors
      ) where

    import Language.Haskell.TH
    import Keiki.Core
    import Keiki.Generics  -- mkInCtorVia, mkInCtor0, mkWireCtorVia, RegFieldsOf, FieldsOf

    -- | TH splice: emit per-ctor inCtor/inp/is declarations for a
    -- command sum type. ... (haddock continues, naming the spec list
    -- shape and the singleton handling rule).
    deriveAggregateCtors :: Name -> Name -> [(String, String)] -> Q [Dec]
    deriveAggregateCtors cmdName regsName specs = do
      info <- reify cmdName
      case info of
        TyConI (DataD _ _ _ _ ctors _) -> do
          let ctorMap = makeCtorMap ctors
          fmap concat . mapM (oneCtor cmdName regsName ctorMap) $ specs
        _ -> fail $ "deriveAggregateCtors: expected a data type, got "
                 <> show info
      where
        ...

    deriveWireCtors :: Name -> [(String, String)] -> Q [Dec]
    deriveWireCtors evtName specs = do
      info <- reify evtName
      case info of
        TyConI (DataD _ _ _ _ ctors _) -> do
          let ctorMap = makeCtorMap ctors
          fmap concat . mapM (oneWire evtName ctorMap) $ specs
        _ -> fail "deriveWireCtors: expected a data type"
      where
        ...

The per-ctor helper `oneCtor` walks the spec entry to:

1. Look up the ctor in the introspected sum.
2. Determine the payload type:
   - `NormalC ctor [] _` → singleton; emit `mkInCtor0`-form decls.
   - `NormalC ctor [(_, payloadTy)] _` → record-payload via newtype-
     style; payload is `payloadTy`.
   - `RecC ctor [(_, _, payloadTy)]` → record-payload; payload is
     `payloadTy`. (Wait — User Registration's `UserCmd
     StartRegistration StartRegistrationData` is a `NormalC`, not
     `RecC`; the *payload* `StartRegistrationData` is a `RecC`.
     Care.)

3. Emit:

      [d|
        inCtor<Short> :: InCtor $cmd (RegFieldsOf $payloadTy)
        inCtor<Short>  = mkInCtorVia @<ctorName>

        inp<Short>    :: Index (RegFieldsOf $payloadTy) r
                              -> Term $regs $cmd r
        inp<Short>     = TInpCtorField inCtor<Short>

        is<Short>     :: HsPred $regs $cmd
        is<Short>      = matchInCtor inCtor<Short>
      |]

   For singletons:

      [d|
        inCtor<Short> :: InCtor $cmd '[]
        inCtor<Short>  = mkInCtor0 <ctorName> $ctor

        is<Short>     :: HsPred $regs $cmd
        is<Short>      = matchInCtor inCtor<Short>
      |]

   (`$ctor` is the bare data constructor reference, which is
   why singletons need it.)

The full implementation is roughly 100-150 lines; see Concrete
Steps for a worked sketch.

`cabal build all` succeeds with the new module loaded.

Acceptance: `cabal build` of an empty test that imports
`Keiki.Generics.TH` succeeds. The full splice exercise is M4.

**Milestone 4 — Splice unit tests.** Create
`test/Keiki/Generics/THSpec.hs`:

    {-# LANGUAGE DeriveGeneric #-}
    {-# LANGUAGE OverloadedLabels #-}
    {-# LANGUAGE TemplateHaskell #-}

    module Keiki.Generics.THSpec (spec) where

    import GHC.Generics (Generic)
    import Test.Hspec
    import Keiki.Core
    import Keiki.Generics
    import Keiki.Generics.TH

    -- A toy aggregate: two commands, one record, one singleton.

    data ToyData = ToyData { x :: Int, y :: Int }
      deriving (Eq, Show, Generic)

    data ToyCmd
      = DoIt   ToyData
      | NoArgs
      deriving (Eq, Show, Generic)

    type ToyRegs =
      '[ '("x", Int), '("y", Int) ]

    $(deriveAggregateCtors ''ToyCmd ''ToyRegs
        [ ("DoIt",   "DoIt")
        , ("NoArgs", "NoArgs")
        ])

    spec :: Spec
    spec = describe "deriveAggregateCtors" $ do
      it "derives inCtorDoIt with the expected name" $
        icName inCtorDoIt `shouldBe` "DoIt"

      it "derives inCtorDoIt that matches DoIt" $
        let payload = ToyData 1 2
        in case icMatch inCtorDoIt (DoIt payload) of
             Just _  -> pure ()
             Nothing -> expectationFailure "icMatch returned Nothing"

      it "derives a singleton inCtorNoArgs" $
        icName inCtorNoArgs `shouldBe` "NoArgs"

      it "derives inpDoIt that projects the x field" $
        -- ... a small Term-eval test using inpDoIt #x
        pure ()

Wire into `test/Spec.hs`:

    import qualified Keiki.Generics.THSpec as THS
    ...
    main = hspec $ do
      ...
      describe "Keiki.Generics.TH" THS.spec

Wire into `keiki.cabal`'s `keiki-test:other-modules`:

    other-modules:      Keiki.CoreSpec
                        Keiki.Generics.THSpec        -- new
                        Keiki.SymbolicSpec
                        ...

`cabal test all` reports baseline + N (3-4) new tests, 0 failures.

Acceptance: the toy spec verifies the splice's behavior in
isolation; the failure modes (wrong identifier name, missing
declaration, type mismatch) all surface as compile or test errors.

**Milestone 5 — Migrate UserRegistration (V5).** Edit
`src/Keiki/Examples/UserRegistration.hs`:

1. Add the splice forms after the data declarations:

       $(deriveAggregateCtors ''UserCmd ''UserRegRegs
           [ ("StartRegistration",  "Start")
           , ("ConfirmAccount",     "Confirm")
           , ("ResendConfirmation", "Resend")
           , ("FulfillGDPRRequest", "Gdpr")
           , ("Continue",           "Continue")
           ])

       $(deriveWireCtors ''UserEvent
           [ ("RegistrationStarted",   "RegistrationStarted")
           , ("ConfirmationEmailSent", "ConfirmationEmailSent")
           , ("AccountConfirmed",      "AccountConfirmed")
           , ("ConfirmationResent",    "ConfirmationResent")
           , ("AccountDeleted",        "AccountDeleted")
           ])

2. Delete the four `type StartFields`, `type ConfirmFields`, `type
   ResendFields`, `type GdprFields` aliases.
3. Delete the five hand-written `inCtor*`, four `inp*`, five
   `is*`, and five `wire*` declarations.
4. Delete the singleton `inCtorContinue` declaration; it is now
   produced by the splice.
5. Verify the `userRegEdges` function continues to type-check
   without changes.
6. Verify the export list at the top of the module still names
   the same identifiers (the splice generates them with the same
   names; nothing in the export list needs to change).

Add `{-# LANGUAGE TemplateHaskell #-}` to the module's pragma list
if not already present.

Run:

    cabal build all
    cabal test all

Expected: M0 baseline test count (70) + new TH spec tests; 0
failures. The
`UserRegistrationSpec`, `UserRegistrationSymbolicSpec`, and
`UserRegistrationV0Spec` suites pass unchanged because the splice
generates byte-for-byte equivalent declarations.

Acceptance: pre-splice and post-splice exports match name-by-name;
all existing tests pass; the file `wc -l` drops from ~403 to
~280 lines.

**Milestone 6 — Update design note + commit.** Edit
`docs/research/keiki-generics-design.md`:

- "### A. Template Haskell `$(deriveAggregateCtors ...)`" — append
  a paragraph beginning **Implemented (see EP-8).** with the
  splice signature and a one-line example referencing
  `src/Keiki/Examples/UserRegistration.hs`.
- "### B. `FieldsOf` deriving for `RegFile` slot lists" — append a
  paragraph beginning **Implemented (see EP-8) as `RegFieldsOf`.**
  The non-`Reg` `FieldsOf` (already shipped for `WireCtor`'s
  nested-pair tuples) stays unchanged.
- "### C. Generic-derived `Term` projection helpers" — append a
  paragraph beginning **Considered and rejected (see EP-8).**
  with the rationale paragraph from M1.

Stage and commit:

    git add src/Keiki/Generics.hs \
            src/Keiki/Generics/TH.hs \
            src/Keiki/Examples/UserRegistration.hs \
            test/Keiki/Generics/THSpec.hs \
            test/Spec.hs \
            keiki.cabal \
            docs/research/keiki-generics-design.md

    git commit -m "$(cat <<'EOF'
    feat(generics): TH deriveAggregateCtors / deriveWireCtors + RegFieldsOf

    New module Keiki.Generics.TH ships two splices that retire the
    per-ctor inCtor/inp/is and per-event wire declarations. New
    type family RegFieldsOf derives the slot list from a payload
    record's Generic representation, replacing hand-written
    StartFields / ConfirmFields / ResendFields / GdprFields aliases.

    UserRegistration migration drops ~120 lines: the four slot-list
    aliases, five inCtor*, four inp*, five is*, five wire*, and one
    singleton inCtor disappear behind two splice forms.

    Retires items A and B from docs/research/keiki-generics-design.md's
    Future Improvements list. Records item C as considered-and-
    rejected (TH supersedes the Generic-derived typeclass).

    MasterPlan: docs/masterplans/3-keiki-generics-dx-follow-ups.md
    ExecPlan: docs/plans/8-th-deriveaggregatectors-and-fieldsof-slot-list-type-family.md
    Intention: intention_01knjzws4qezz9w8b0743zfqv8
    EOF
    )"

Acceptance: `git log -1 --format=%B HEAD` shows all three trailers.


## Concrete Steps

All commands run from `/Users/shinzui/Keikaku/bokuno/keiki/`.

**M0 baseline:**

    cabal build all
    cabal test all 2>&1 | grep -E '^[0-9]+ examples'

**M1 design pass.** Edit
`docs/research/keiki-generics-design.md` to amend items A, B, C
per Plan of Work M1.

**M2 RegFieldsOf:**

Edit `src/Keiki/Generics.hs`. Add to the export list (around line
20):

      , RegFieldsOf
      , RegFieldsOfRep

Add the type families after the existing `Append` definition:

    type RegFieldsOf d = RegFieldsOfRep (Rep d)

    type family RegFieldsOfRep (rep :: Type -> Type) :: [Slot] where
      RegFieldsOfRep (M1 D _ inner) = RegFieldsOfRep inner
      RegFieldsOfRep (M1 C _ inner) = RegFieldsOfRep inner
      RegFieldsOfRep (M1 S ('MetaSel ('Just n) _ _ _) (K1 _ t))
                                    = '[ '(n, t) ]
      RegFieldsOfRep U1             = '[]
      RegFieldsOfRep (l :*: r)      = Append (RegFieldsOfRep l)
                                             (RegFieldsOfRep r)

REPL check:

    cabal repl keiki
    -- inside repl:
    :set -XDataKinds
    import Keiki.Generics
    import Keiki.Examples.UserRegistration
    :kind! RegFieldsOf StartRegistrationData
    -- expected:
    -- RegFieldsOf StartRegistrationData :: [Slot]
    -- = '[ '("email", Email), '("confirmCode", ConfirmationCode),
    --      '("at", UTCTime) ]

If the result differs from `StartFields`, halt and investigate.
The most likely cause is a missing `deriving (Generic)` on the
payload record (which the existing code already has, so this
should not arise).

    cabal build all   # green

**M3 implement the splices:**

Edit `keiki.cabal`. Add to `library:build-depends`:

    template-haskell ^>= 2.22

(Pin to whatever version GHC 9.10 ships; check via
`ghc-pkg list template-haskell`.)

Add `Keiki.Generics.TH` to `library:exposed-modules`:

    exposed-modules:    Keiki.Core
                        Keiki.Generics
                        Keiki.Generics.TH    -- new
                        Keiki.Symbolic
                        Keiki.Examples.UserRegistration
                        Keiki.Examples.UserRegistrationV0

Create `src/Keiki/Generics/TH.hs`. Sketch:

    {-# LANGUAGE TemplateHaskell #-}

    module Keiki.Generics.TH
      ( deriveAggregateCtors
      , deriveWireCtors
      ) where

    import Language.Haskell.TH
    import Language.Haskell.TH.Syntax (Quasi)
    import qualified Data.Map.Strict as Map  -- if needed

    deriveAggregateCtors
      :: Name -> Name -> [(String, String)] -> Q [Dec]
    deriveAggregateCtors cmdName regsName specs = do
      info <- reify cmdName
      ctors <- case info of
        TyConI (DataD _ _ _ _ cs _) -> pure cs
        _ -> fail "deriveAggregateCtors: expected a data declaration"
      let ctorMap = [ (nameBase n, c) | c <- ctors, n <- conName c ]
      fmap concat . mapM (genCtor cmdName regsName ctorMap) $ specs

    -- Helper: extract the Name(s) of a constructor.
    conName :: Con -> [Name]
    conName (NormalC n _)   = [n]
    conName (RecC n _)      = [n]
    conName (InfixC _ n _)  = [n]
    conName _               = []

    -- Helper: payload type and singleton flag.
    conPayload :: Con -> Maybe (Maybe Type)
    --   Just Nothing    => singleton (no payload)
    --   Just (Just t)   => single-arg payload type t
    --   Nothing         => unsupported shape (record/multi-arg)
    conPayload (NormalC _ [])           = Just Nothing
    conPayload (NormalC _ [(_, t)])     = Just (Just t)
    conPayload _                        = Nothing

    -- Generate three (or two) declarations per ctor.
    genCtor
      :: Name -> Name -> [(String, Con)] -> (String, String) -> Q [Dec]
    genCtor cmdName regsName ctorMap (ctorStr, shortStr) =
      case lookup ctorStr ctorMap of
        Nothing -> fail $ "deriveAggregateCtors: ctor "
                       <> show ctorStr <> " not in "
                       <> show cmdName
        Just con -> case conPayload con of
          Nothing -> fail $ "deriveAggregateCtors: ctor "
                         <> show ctorStr
                         <> " has unsupported shape (multi-arg or record)"
          Just Nothing -> singletonDecls cmdName regsName ctorStr shortStr (head (conName con))
          Just (Just payloadTy) ->
            recordDecls cmdName regsName ctorStr shortStr payloadTy

    singletonDecls :: Name -> Name -> String -> String -> Name -> Q [Dec]
    singletonDecls cmdName regsName ctorStr shortStr ctorN = do
      let inCtorN = mkName ("inCtor" <> shortStr)
          isN     = mkName ("is"     <> shortStr)
      sequence
        [ sigD inCtorN [t| InCtor $(conT cmdName) '[] |]
        , funD inCtorN [clause [] (normalB
            [| mkInCtor0 $(litE (stringL ctorStr)) $(conE ctorN) |]) []]
        , sigD isN [t| HsPred $(conT regsName) $(conT cmdName) |]
        , funD isN [clause [] (normalB
            [| matchInCtor $(varE inCtorN) |]) []]
        ]

    recordDecls :: Name -> Name -> String -> String -> Type -> Q [Dec]
    recordDecls cmdName regsName ctorStr shortStr payloadTy = do
      let inCtorN = mkName ("inCtor" <> shortStr)
          inpN    = mkName ("inp"    <> shortStr)
          isN     = mkName ("is"     <> shortStr)
          slotsT  = [t| RegFieldsOf $(pure payloadTy) |]
      r <- newName "r"
      sequence
        [ sigD inCtorN [t| InCtor $(conT cmdName) $slotsT |]
        , funD inCtorN [clause [] (normalB
            [| mkInCtorVia @($(litT (strTyLit ctorStr))) |]) []]
        , sigD inpN
            [t| forall $(plainTV r) . Index $slotsT $(varT r)
                 -> Term $(conT regsName) $(conT cmdName) $(varT r) |]
        , funD inpN [clause [] (normalB
            [| TInpCtorField $(varE inCtorN) |]) []]
        , sigD isN [t| HsPred $(conT regsName) $(conT cmdName) |]
        , funD isN [clause [] (normalB
            [| matchInCtor $(varE inCtorN) |]) []]
        ]

    deriveWireCtors :: Name -> [(String, String)] -> Q [Dec]
    deriveWireCtors evtName specs = do
      info <- reify evtName
      ctors <- case info of
        TyConI (DataD _ _ _ _ cs _) -> pure cs
        _ -> fail "deriveWireCtors: expected a data declaration"
      let ctorMap = [ (nameBase n, c) | c <- ctors, n <- conName c ]
      fmap concat . mapM (genWire evtName ctorMap) $ specs

    genWire
      :: Name -> [(String, Con)] -> (String, String) -> Q [Dec]
    genWire evtName ctorMap (ctorStr, shortStr) =
      case lookup ctorStr ctorMap of
        Nothing -> fail $ "deriveWireCtors: " <> show ctorStr
                       <> " not in " <> show evtName
        Just con -> case conPayload con of
          Just (Just payloadTy) -> do
            let wireN = mkName ("wire" <> shortStr)
            sequence
              [ sigD wireN
                  [t| WireCtor $(conT evtName)
                               (FieldsOf $(pure payloadTy)) |]
              , funD wireN [clause [] (normalB
                  [| mkWireCtorVia @($(litT (strTyLit ctorStr))) |]) []]
              ]
          _ -> fail $ "deriveWireCtors: " <> show ctorStr
                   <> " has unsupported payload shape"

This sketch is the substantial core; expect ~30-50 lines of
debugging on top (pretty-printer differences in error messages,
quote-splice corner cases for ambiguous types, etc.).

Run:

    cabal build all   # green

**M4 splice unit tests.**

Create `test/Keiki/Generics/THSpec.hs` per Plan of Work M4. Wire
into `test/Spec.hs` and `keiki.cabal`'s
`keiki-test:other-modules`.

    cabal test all 2>&1 | grep -E '^[0-9]+ examples'

Expected: M0 baseline + 3-4 new examples; 0 failures.

**M5 UserRegistration migration:**

Edit `src/Keiki/Examples/UserRegistration.hs`:

1. Add `{-# LANGUAGE TemplateHaskell #-}` to the existing pragma
   list at the top.
2. Add `Keiki.Generics.TH (deriveAggregateCtors,
   deriveWireCtors)` to the imports.
3. After the `data UserEvent = ...` declaration, insert the two
   splice forms (per Plan of Work M5).
4. Delete the four `type StartFields = ...`, `type ConfirmFields =
   ...`, `type ResendFields = ...`, `type GdprFields = ...`
   aliases.
5. Delete the per-ctor `inCtor*`, `inp*`, `is*` declarations
   (~30 lines spanning the section "Per-constructor input
   projections" and "Per-constructor guards").
6. Delete the per-event `wire*` declarations (~10 lines).

Run:

    cabal build all
    cabal test all 2>&1 | grep -E '^[0-9]+ examples'

Expected: same count as M4. The `Keiki.Examples.UserRegistration`
module is now ~280 lines (down from 403).

Spot-check the export list at the top of the module — the listed
identifiers should be unchanged (the splice generates the same
names).

**M6 commit:**

    git diff --stat   # confirm the file set is correct
    git add ...        # see Plan of Work M6 for the file list
    git commit -m "..." # see Plan of Work M6 for the message


## Validation and Acceptance

After all six milestones:

- `cabal build all` succeeds with no warnings.
- `cabal test all` reports M0 baseline + 3-4 new examples (the toy
  splice tests), 0 failures. The User Registration tests
  (`UserRegistrationSpec`, `UserRegistrationSymbolicSpec`,
  `UserRegistrationV0Spec`) all still pass.
- `wc -l src/Keiki/Examples/UserRegistration.hs` reports
  approximately 280 lines (down from 403).
- The pre-migration export list and the post-migration export
  list of `Keiki.Examples.UserRegistration` are identical
  name-for-name (verified via `diff <(git show
  HEAD:src/Keiki/Examples/UserRegistration.hs | sed -n
  '/module/,/^  )/p' | sed -n '/^  /p') <(sed -n
  '/module/,/^  )/p' src/Keiki/Examples/UserRegistration.hs | sed
  -n '/^  /p')`).

Behavioral acceptance:

1. **The splice produces the expected identifiers.** A REPL
   session (`cabal repl keiki`) can print:

       :t inCtorStart
       -- inCtorStart :: InCtor UserCmd (RegFieldsOf StartRegistrationData)

       :t inpStart
       -- inpStart :: forall r. Index (RegFieldsOf StartRegistrationData) r
       --             -> Term UserRegRegs UserCmd r

       :t isStart
       -- isStart :: HsPred UserRegRegs UserCmd

   …all matching the pre-migration types (modulo `RegFieldsOf` vs.
   `StartFields`, which are equivalent at the type-family level).

2. **The User Registration aggregate's existing tests pass.**
   `cabal test all` reports the same `userReg`-driven assertions
   green: canonical-log reconstitution lands in `Deleted`,
   `isSingleValuedSym (withSymPred userReg) == True`, V0
   hidden-input warning fires, etc.

3. **The toy `THSpec` exercises the splice in isolation.** A
   2-ctor `ToyCmd` produces correct `inCtorDoIt`, `inCtorNoArgs`,
   `inpDoIt`, `isDoIt`, `isNoArgs` declarations; the toy spec
   verifies their behavior independently of the User Registration
   fixtures.


## Idempotence and Recovery

The plan is largely additive (M0–M4) followed by a single
substantial deletion in M5. Each milestone's edits can be
re-applied without harm:

- M2's type family additions are exact-string declarations; a
  second add is a syntax error easily caught.
- M3's TH module is self-contained; deleting and recreating it has
  no side effects elsewhere.
- M4's spec module imports only from `Keiki.*` modules; safe to
  re-create.
- M5's deletions are all in one file. If the migration fails (a
  generated name doesn't match a call site, or a type signature
  diverges), revert the file:

      git checkout src/Keiki/Examples/UserRegistration.hs

  …and re-apply the deletions one declaration at a time, building
  after each.

Recovery from a bad TH splice — if M3's splice produces something
unexpected:

1. Add `-ddump-splices` to the `keiki.cabal` `library`'s
   `ghc-options` (or pass `--ghc-options=-ddump-splices` to
   `cabal build`) and re-run.
2. The splice expansion appears in the build output verbatim;
   compare against the hand-written form to identify the
   divergence.
3. Common failure modes:
   - Wrong identifier capitalization → adjust `mkName`'s argument.
   - Type mismatch on `Index` (e.g. `Index '[]` for a non-singleton)
     → check the singleton detection in `conPayload`.
   - Missing `Generic` instance → check the source has `deriving
     (Generic)` on the relevant payload record.

Recovery from a non-matching pre/post export list (M5):

1. The splice produces *identifiers* but does not modify the
   module's export list. The pre-migration export list still names
   the same identifiers; if any are missing post-migration, the
   splice short-name spec list is wrong.
2. Edit the spec list in the splice form to match the missing
   names. For example, if `inpStart` is missing, the spec entry
   for `StartRegistration` must be `("StartRegistration",
   "Start")`.

No file outside the listed paths in M6's `git add` should be
modified by this plan. If `git diff` shows changes elsewhere,
investigate before committing.


## Interfaces and Dependencies

New types:

    -- src/Keiki/Generics.hs (extension)
    type RegFieldsOf d :: [Slot]
    type family RegFieldsOfRep (rep :: Type -> Type) :: [Slot]

New TH splices (in `src/Keiki/Generics/TH.hs`):

    deriveAggregateCtors :: Name -> Name -> [(String, String)] -> Q [Dec]
    deriveWireCtors      :: Name -> [(String, String)]          -> Q [Dec]

New cabal dep:

    library
        build-depends:  template-haskell ^>= 2.22  -- (or 2.24 on GHC 9.12)

Existing helpers consumed:

- `Keiki.Generics.mkInCtorVia`, `mkInCtor0`, `mkWireCtorVia` — the
  splice expands to these.
- `Keiki.Core.TInpCtorField`, `matchInCtor` — the splice's `inp*`
  and `is*` declarations expand to these.
- `Keiki.Generics.Append`, `RegFieldsOf` — the splice's signatures
  reference `RegFieldsOf`.

No interfaces are removed. The `mkInCtorVia` helper continues to
exist as a public API for callers who want the per-ctor declarations
hand-written (e.g. for one-off ctors whose short-name choice
doesn't fit the splice's spec list).
