# `deriveView` TH splice for B-presentation views — design

This note is the design record for the `deriveView` Template Haskell
splice added to `Keiki.Generics.TH` under MasterPlan 5 / ExecPlan 13.
The splice materializes the per-vertex projection
`viewFor :: SVertex v -> RegFile rs -> View v` that the synthesis note
introduces as the **B-presentation** of an aggregate's state.

The companion files referenced throughout this note are:

- `docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`
  — §3 "Where indexed state (B) fits" motivates the per-vertex
  projection and §4.4 "Optional B-view" works it out by hand for
  `UserRegistration`.
- `docs/research/keiki-generics-design.md` — the `Keiki.Generics`
  family that the EP-8 splices `deriveAggregateCtors` and
  `deriveWireCtors` belong to. `deriveView` is the third splice in
  that family.
- `src/Keiki/Generics/TH.hs` — the existing TH module that
  `deriveView` extends; the validation-and-codegen pattern modelled
  after `deriveAggregateCtors`.
- `src/Keiki/Examples/UserRegistration.hs` — the canonical aggregate
  the splice is exercised on.


## Problem statement

A `SymTransducer phi rs s ci co`'s state is the pair
`(s, RegFile rs)`. The register file is shared across all vertices —
that is the property that lets composition and the mechanical
`applyEvent` inverse work uniformly. But human readers benefit when
each vertex's *meaningful* slice of registers is named.

The synthesis note's §3 proposes a typed projection on top of the
shared register file: for each vertex `v` define a per-vertex GADT
constructor that exposes only the slots live in that vertex, then
write `viewFor :: SVertex v -> RegFile rs -> View v` that materializes
it. After the projection a reader pattern-matches on `View v` and the
type system blocks them from asking `Pending` for `approvedBy`.

The synthesis note flagged the codegen for this shape as opt-in:

> A `genView` TH helper is a nice-to-have, not a v1 requirement.

Today no aggregate in `src/Keiki/Examples/` ships a B-view. A user
who wants the typed projection has to hand-write three things per
aggregate: the per-aggregate `S<Vertex>` singletons GADT (mapping
each `Vertex` constructor to a singleton tag indexed by the promoted
type), the per-aggregate `<Aggregate>View` GADT (one constructor per
vertex carrying the live slots as record fields), and the projection
function (one clause per vertex reading the named slots via `(!)`).

For the five-vertex `UserRegistration` aggregate that's roughly 40
lines of mechanical declaration — boilerplate that's easy to get
wrong (a missed vertex turns into a non-exhaustive pattern; a
mistyped slot name turns into a type error pages away from the
authoring site).

This EP closes the omission with the smallest possible TH splice that
generates all three from a per-vertex spec list.


## The splice

The user-facing surface is one Q-action with four `Name`/`String`
arguments and one spec list:

    deriveView
      :: Name              -- ^ vertex enum, e.g. ''Vertex
      -> Name              -- ^ register-file slot list, e.g. ''UserRegRegs
      -> String            -- ^ name of the singletons GADT to
                           --   generate, e.g. "SUserVertex"
      -> String            -- ^ name of the View GADT, e.g. "UserView"
      -> String            -- ^ name of the projection function,
                           --   e.g. "userView"
      -> [(String, [String])]
                           -- ^ per-vertex spec: pairs of
                           --   (vertex constructor name,
                           --    list of slot names live in that vertex)
      -> Q [Dec]

The two `Name` arguments are reified at splice time. `vertexName`
must be a plain Haskell `data` declaration (the aggregate's vertex
enum); `regsName` must be a `type` synonym whose right-hand side is a
promoted `[Slot]` list of the form
`'[ '("name1", t1), '("name2", t2), … ]`.

The three `String` arguments name the generated bindings. The splice
does *not* derive these from the input names. Explicit names keep the
call site self-explanatory and avoid a "where did this binding come
from?" hop. The cost is three extra strings per invocation.

The spec list is a `[(constructorName, liveSlotNames)]`. Each entry
declares one vertex's projection. Empty `liveSlotNames` is a nullary
View constructor (the vertex has no live data the projection
exposes).


## Spec format and field-name derivation

Slot names are strings, not `Index` values or promoted symbols.
Strings match the style of `deriveAggregateCtors` (the splice in the
same module that takes `[(constructorName, shortName)]` pairs) and
they read cleanly at the call site. Misspellings are caught by
validation (see "Validation rules" below) with a precise
splice-time error message.

For each `(vertexName, liveSlots)` entry the splice generates one
View constructor named `<VertexName>V` (e.g. `PotentialCustomerV`,
`ConfirmedV`). Each live slot becomes a record field on that
constructor. Field names are derived as `<prefix><Slot>` where
`<prefix>` is the **lower-cased concatenation of the vertex name's
upper-case letters** and `<Slot>` is the slot name with its first
letter upper-cased. So:

- `RequiresConfirmation` (upper-cases `R`, `C`) × `email` → `rcEmail`
- `RequiresConfirmation` × `confirmCode` → `rcConfirmCode`
- `Confirmed` (upper-cases `C`) × `email` → `cEmail`
- `Confirmed` × `confirmedAt` → `cConfirmedAt`
- `Deleted` (upper-cases `D`) × `email` → `dEmail`
- `Deleted` × `deletedAt` → `dDeletedAt`

The rule is one line of code: `filter isUpper >>> map toLower`. It
yields distinct prefixes for every vertex of `UserRegistration`
(`pc`, `r`, `rc`, `c`, `d`); the splice validates that the
generated field names within a single constructor are distinct
(see "Validation rules" below) and rejects collisions with a
precise message.

Per-vertex prefixing keeps field names unique across the View
GADT. That matters because `DuplicateRecordFields` is enabled
(`keiki.cabal:24`) but `HasField`/`OverloadedRecordDot` resolution
through GADT-record selectors when a field name is shared across
constructors of one GADT is a sharp edge — distinct names sidestep
the question entirely and yield clearer pattern matches.

(The plan's original Decision Log committed to the example field
name `cfEmail` for `Confirmed.email`. The implementation took
`cEmail` instead because the underlying rule "lower-case the
upper-case letters" is a one-liner and `Confirmed` has only one
upper-case letter. The change is recorded in the EP-13 plan's
Decision Log.)


## Generated code

Given the worked-example invocation:

    $(deriveView ''Vertex ''UserRegRegs
        "SUserVertex" "UserView" "userView"
        [ ("PotentialCustomer",    [])
        , ("Registering",          [])
        , ("RequiresConfirmation", ["email", "confirmCode"])
        , ("Confirmed",            ["email", "confirmedAt"])
        , ("Deleted",              ["email", "deletedAt"])
        ])

the splice expands to (modulo TH name uniquification):

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
        :: { cEmail       :: Email
           , cConfirmedAt :: UTCTime
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

The slot reads use `Keiki.Core.(!)` and the `OverloadedLabels`
machinery already in `Keiki.Core`. Empty-payload vertices use a
nullary GADT constructor (no field block); their projection clause
binds the register file to a wildcard.

`StandaloneDeriving` (part of GHC2024, the default in `keiki.cabal`)
gives `Show` and `Eq` for both GADTs. Without these, every test
would have to deconstruct `View` values manually instead of using
`shouldBe`.


## Validation rules

The splice runs five checks before generating any code. Each
validation failure raises `fail` with a precise message at the
splice site so the user sees the diagnostic at the call site, not
pages away from the authoring point.

1. **Vertex enum is a data declaration.** `reify vertexName` must
   return `TyConI (DataD …)`. Otherwise the splice fails with
   `deriveView: expected a data declaration for <Name>, got
   <Info>`. (Same shape `deriveAggregateCtors` already enforces.)

2. **Spec covers every vertex exactly once.** The set of
   constructor names in the vertex enum equals the set of names in
   the spec. Missing entries → `deriveView: spec is missing
   constructors of <VertexName>: { "Foo", "Bar" }`. Extra entries
   → `deriveView: spec names constructors not in <VertexName>:
   { "Baz" }`. Duplicate spec entries → `deriveView: spec lists
   constructor "Foo" more than once`.

   Coverage enforcement makes the projection total: `viewFor` is a
   pattern match over `SVertex v`; without coverage GHC would emit
   an incomplete-pattern warning at every call site. The splice
   prevents the warning at its source.

3. **Slot list is a promoted `[Slot]` literal.** `reify regsName`
   must return a `TyConI (TySynD _ _ rhs)` whose `rhs` is a
   promoted-list of promoted-tuple cells of shape
   `'(LitT (StrTyLit name), slotType)`. Other shapes → `deriveView:
   expected a type synonym for a promoted [Slot] list, got <RHS>`.

4. **Each named slot exists in the slot list.** For every spec
   entry, every slot name must appear in the slot list extracted
   in step 3. Missing slot → `deriveView: spec entry "Confirmed"
   names slot "badSlot", which is not a slot of <RegsName>; known
   slots: { "email", "confirmCode", … }`. Duplicate slot names
   within one spec entry → `deriveView: spec entry "Confirmed"
   lists slot "email" more than once`.

5. **Vertex names produce distinct prefixes.** The
   `filter isUpper >>> map toLower` rule yields one prefix per
   vertex; if two vertices share a prefix (e.g. `Confirmed` and
   `Cancelled` both producing `c`) the splice fails with
   `deriveView: vertices "Confirmed" and "Cancelled" produce the
   same field-name prefix "c"; rename one or change the spec to
   not share live slots`. The check is conservative: it always
   fires on prefix collision even if the colliding vertices share
   no live slots, because the future-proof shape is to keep all
   field names distinct across the GADT.


## Implementation sketch

The splice is built as four phases. The first three reify and
validate; the fourth generates declarations.

### Phase 1: Reify the vertex enum

`reify vertexName` returns `Info`; matching on `TyConI (DataD _ _
_ _ ctors _)` extracts the constructor list. Each `Con` is matched
against `NormalC ctorName []` (every `Vertex` constructor is
nullary). The output is a `[Name]` of vertex constructors in
declaration order.

### Phase 2: Reify the slot list

`reify regsName` returns `TyConI (TySynD _ _ rhs)`. The `rhs` is a
promoted-list type. Walking it is a small recursive helper:

    parseSlotList :: Type -> Q [(String, Type)]

The walk pattern-matches the promoted-cons type constructor
(`PromotedConsT` applied to two arguments — the head pair and the
tail list), unpacks the head pair (`PromotedTupleT 2` applied to a
`LitT (StrTyLit name)` and a slot type), and recurses on the tail.
The base case is `PromotedNilT`.

`Language.Haskell.TH.Datatype` was considered but the slot list is
small and the bespoke walk is ~15 lines. No dependency on the
`th-abstraction` package is taken.

### Phase 3: Validate

Five checks on the lists from phases 1–2: constructor coverage,
spec dedup, slot membership, slot dedup within an entry, and
prefix uniqueness. Each check returns `()` or `fail`s with the
precise message described in "Validation rules".

### Phase 4: Generate declarations

Three groups of declarations are built:

(a) The singletons GADT. One `DataD` whose constructors are
`GadtC [SCtorName] [] resultType`, where `resultType` is `AppT (ConT
sVertexName) (PromotedT vertexCtorName)`. A `KindedTV v BndrReq
(ConT vertexName)` ties the GADT's type parameter `v` to the vertex
kind. Two `StandaloneDerivD` declarations follow for `Show` and
`Eq` instances.

(b) The View GADT. One `DataD` whose constructors are either
`GadtC [viewCtorName] [] resultType` (empty-slot vertices) or
`RecGadtC [viewCtorName] [(fieldName, defaultBang, fieldType)] resultType`
(non-empty). The slot type comes from the `(String, Type)` map
parsed in phase 2. Two `StandaloneDerivD` declarations follow.

(c) The projection function. One `FunD viewFunName clauses` where
each clause is `Clause [ConP sCtorName [] [], regsPat] (NormalB
body) []`. For empty-slot vertices `regsPat` is `WildP` and `body`
is `ConE viewCtorName`. For non-empty vertices `regsPat` is `VarP
regs'` and `body` is `ConE viewCtorName` applied left-to-right to
one `(VarE regs') ! (LabelE slotName)` per live slot, where the
`(!)` is the `Keiki.Core` lookup operator and `LabelE` desugars
through `OverloadedLabels` to `Keiki.Core.indexOf`.

The full output is a single `Q [Dec]` of length 2 + 2 + 2 + 1 = 7
top-level declarations: two `DataD`s, four `StandaloneDerivD`s, one
`FunD`. (Plus a leading `SigD` for the projection function.)


## What is deliberately deferred

This EP names what's already implicit in the synthesis-doc design.
It does not extend the formalism:

- **A default `View v = RegFile rs` for non-opted-in aggregates.**
  Aggregates that don't invoke `deriveView` simply have no `View`
  type. The synthesis note's "library can ship a default" phrasing
  was already labelled optional. Writing the default would require a
  shared `Keiki.View` module and a kind-generic `Singleton` class —
  significant infrastructure for a fallback no aggregate is asking
  for. Defer until a real authoring need surfaces.

- **A shared `Singleton` class.** Each `deriveView` invocation
  generates a fresh `S<Vertex>` GADT specific to that aggregate's
  vertex enum. A library-wide `Singleton (kind :: Type -> Type)`
  abstraction would let downstream code be polymorphic over "any
  aggregate's singleton GADT," at the cost of kind-polymorphic
  plumbing through every consumer. The synthesis-doc shape worked
  per-aggregate; we follow it.

- **Lifting `viewFor` into the transducer's evolution loop.** The
  synthesis note states explicitly: *"The view is a pure projection.
  The transducer doesn't know about it."* The projection stays
  opt-in and downstream of `step` / `applyEvent`. No `step`-level
  rewrite goes through `View`.

- **Read-model / query-side projections.** Those are runtime
  concerns living outside the pure core (per `effects-boundary.md`).
  `View` is a pure per-vertex slice of the in-flight register file,
  not a denormalized read model.

- **Validation that the chosen `liveSlotNames` for each vertex are
  the slots actually written/read by edges leaving that vertex.**
  Cross-checking the spec against the transducer's edges would catch
  "live slot named, but never set on any incoming edge" and "slot
  written by an incoming edge, but not named in the spec." Both are
  valuable but require `deriveView` to take the transducer name as
  an additional argument and walk the edge list — significant scope.
  Defer until the splice has been used on more than one aggregate
  and the right shape of the cross-check is clearer.


## Why this lives in `Keiki.Generics.TH`, not a new module

`Keiki.Generics.TH` already exposes `deriveAggregateCtors` and
`deriveWireCtors`. Users who want all of keiki's TH surface import
one module. A new `Keiki.Generics.TH.View` would be a separate
import for what's structurally a third entry in the same family
(reify, validate, generate). This matches the rationale that
co-located `deriveAggregateCtors` and `deriveWireCtors` in EP-8
(see `keiki-generics-design.md` item A's Implemented note).


## Why per-aggregate names, not derived

`deriveView` takes user-chosen names for the singletons GADT, the
View GADT, and the projection function (`"SUserVertex"`,
`"UserView"`, `"userView"`). It does *not* default to a
`"S<Vertex>"` / `"<Vertex>View"` / `"<lowercase>view"` derivation.

Two reasons. First, derivation rules from another type's name are
surprising — readers seeing `SUserVertex` in a stack trace or hover
should be able to grep for the binding without computing what
template it came from. Second, the vertex enum in
`UserRegistration` is just `Vertex` (not `UserVertex`); a
mechanical rule would have to either know the aggregate name or
produce a `SVertex` that collides with other aggregates. Explicit
strings dodge both questions for three keystrokes per name.


## Relationship to the foundations chapters

Foundations chapter 04 is about projections from a single
transducer. The acceptor projections (EP-12) and `Keiki.Decider`
(EP-10) live there: they project `(s, RegFile rs)` to other
*formalism-shaped* objects (acceptors over an alphabet, a
Chassaing-shape four-field record).

The B-view projection lives one step further out — it's a
*presentation* layer on top of `(s, RegFile rs)`. The synthesis
note groups it as B (indexed-state per-vertex) presentation of the
C (symbolic-register transducer) foundation. `View v` is for
human/UI consumption; `Acceptor`/`Decider` are for downstream
formalism consumption.

Both layers coexist with the transducer unmodified. `userView` does
not appear in `step`; `accepts` does not appear in `evolve`.
