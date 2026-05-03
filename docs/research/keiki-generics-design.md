# Keiki.Generics design — DX evaluation of Generic-derived aggregate helpers

This note is the design record for the `Keiki.Generics` module added as
a follow-up to MasterPlan 2's EP-2. It captures the boilerplate
problem the module solves, the tools used (typeclass-driven traversal
of `GHC.Generics` representations), how far they go before the
ergonomics break down, and how the resulting DX compares to two
reference points: a *naive decider* (the canonical functional
event-sourcing pattern) and `crem` (the production-grade Haskell
Mealy-machine library compared in
`docs/research/architecture-comparison-fst-aggregate-vs-crem.md`).

The comparison is specifically about **authoring DX** — how much code
the user writes to declare an aggregate. Functional comparisons (what
each architecture *does*) live in the crem note above; this note
points at it instead of rehashing.


## The problem

The pure core's data model — symbolic-register transducers with
structural input projection (`TInpCtorField`/`InCtor`) and structural
output construction (`OPack`/`WireCtor`) — is mechanically verifiable
and gives `solveOutput` a precise inverse. The cost is **shape
boilerplate at the example layer**:

- Per command constructor: an `InCtor` value carrying the
  constructor's name, an `icMatch` walking the sum and projecting the
  payload into a typed `RegFile`, and an `icBuild` reconstructing the
  payload from a `RegFile` and re-wrapping it in the constructor.
- Per event constructor: a `WireCtor` carrying the constructor's
  name, a `wcMatch` walking the sum and projecting the payload into a
  nested-pair tuple, and a `wcBuild` doing the inverse.
- Per register file: an `emptyRegs` tower of `RCons` calls binding
  each slot to a deferred `error "uninit: <name>"`.

Each of these is *mechanical*: the code is fully determined by the
shape of the user's data types. Pre-`Keiki.Generics` the User
Registration aggregate spent **roughly 110 lines** on these towers,
plus another ~30 lines of inverse-related constructions. Reading the
example required scanning past dozens of lines of structural pattern
match before reaching the actual transition logic.

The `Keiki.Generics` module retires the towers by walking
`GHC.Generics.Rep` representations at the type level and at the value
level. The user adds `deriving (Generic)` to the relevant data types
and writes one or two lines per declaration; the module does the
rest.


## What the module ships

After the four DX commits (`b8f1053`, `5deb476`, `dde5cc8`), the
exported surface is:

    -- Generic-derived InCtor
    mkInCtor      :: (Generic d, GRecord (Rep d) ifs, ...)
                  => String -> (ci -> Maybe d) -> (d -> ci) -> InCtor ci ifs
    mkInCtor0     :: Eq ci => String -> ci -> InCtor ci '[]
    mkInCtorVia   :: forall (name :: Symbol) ci d ifs.
                     ( KnownSymbol name, Generic ci, Generic d
                     , GHasCtor name (Rep ci) d
                     , GRecord (Rep d) ifs
                     , AssembleRegFile ifs, KnownSlotNames ifs
                     ) => InCtor ci ifs

    -- Generic-derived WireCtor
    mkWireCtor    :: (Generic d, GTuple (Rep d) fs)
                  => String -> (co -> Maybe d) -> (d -> co) -> WireCtor co fs
    mkWireCtorVia :: forall (name :: Symbol) co d fs.
                     ( KnownSymbol name, Generic co, Generic d
                     , GHasCtor name (Rep co) d
                     , GTuple (Rep d) fs
                     ) => WireCtor co fs
    type FieldsOf d = FieldsOfRep (Rep d)

    -- Empty register file
    class EmptyRegFile rs where emptyRegFile :: RegFile rs

    -- Sum-walking machinery (exposed for advanced users)
    class GHasCtor (name :: Symbol) (rep :: Type -> Type) (d :: Type)
                  | name rep -> d where ...
    type family NameInRep n rep :: Bool

The user-facing layer is `mkInCtorVia`, `mkWireCtorVia`, and
`emptyRegFile`. The non-`Via` builders (`mkInCtor`, `mkWireCtor`) are
kept as escape hatches — they accept an explicit match/wrap pair so
the user can opt out of the type-level constructor lookup if their
sum types don't fit the standard shape.


## Per-construct delta (User Registration)

The User Registration V5 module is the canonical worked example. The
table below shows lines per construct before and after the `Via`
migration:

    Construct                Before    After    Delta
    ──────────────────────── ──────── ──────── ──────
    InCtor (record-payload)  10-12    1        −10
    InCtor (singleton)        7        1        −6
    WireCtor                 10       1        −9
    emptyRegs                 6        1        −5

Five record-payload `InCtor`s + one singleton `InCtor` + ten
`WireCtor`s (V5 + V0) + two `emptyRegs` towers gives a total of:

    5 × 10  +  1 × 6  +  10 × 9  +  2 × 5  =  156 lines retired

The example modules now read as a clean catalog of names + records +
the transducer's edge list. The boilerplate is gone.


## How the typeclass machinery works

The user adds `deriving (Generic)` to two layers:

1. The **payload records** (`StartRegistrationData`, `AccountConfirmedData`,
   etc). `Keiki.Generics`' `GRecord` and `GTuple` classes walk the
   record's `Rep` to extract the slot list (for `RegFile`) or the
   nested-pair tuple shape (for `WireCtor`).
2. The **sum types** (`UserCmd`, `UserEvent`, `UserEventV0`).
   `GHasCtor` walks the sum looking for the constructor named at the
   call site, dispatches to the correct branch via a type-level
   `NameInRep` Bool, and returns the matching payload type via the
   functional dependency `name rep -> d`.

The `mkInCtorVia` call at use site:

    inCtorStart :: InCtor UserCmd StartFields
    inCtorStart  = mkInCtorVia @"StartRegistration"

triggers the chain:

    1.  KnownSymbol "StartRegistration"  →  the icName.
    2.  Generic UserCmd  →  Rep UserCmd.
    3.  GHasCtor "StartRegistration" (Rep UserCmd) d  →  d ~ StartRegistrationData.
        (resolved by walking the sum's :+: structure with NameInRep
         dispatching to the side that contains the named constructor).
    4.  Generic d, GRecord (Rep d) ifs  →  ifs ~ StartFields.
        (resolved by walking the record's :*: structure, selecting on
         M1 S 'MetaSel selector names).
    5.  AssembleRegFile ifs, KnownSlotNames ifs  →  satisfied by
        StartFields' shape (auto-derivable for any concrete slot list).

GHC type-checks the chain at compile time. The user writes one
type-app; everything else is structural.


## DX comparison against the naive decider

The "naive decider" is the canonical pattern for functional event
sourcing — Jérémie Chassaing's *Decider* shape, in Haskell:

    data Decider c e s = Decider
      { decide       :: c -> s -> [e]
      , evolve       :: s -> e -> s
      , initialState :: s
      , isTerminal   :: s -> Bool
      }

For the User Registration aggregate, a naive Haskell implementation
typically looks like:

    userRegDecider :: Decider UserCmd UserEvent (Vertex, RegFile UserRegRegs)
    userRegDecider = Decider
      { decide = \cmd (v, regs) -> case (v, cmd) of
          (PotentialCustomer, StartRegistration d) ->
            [RegistrationStarted (RegistrationStartedData
                d.email d.confirmCode d.at)]
          (Registering, Continue) ->
            [ConfirmationEmailSent (ConfirmationEmailSentData
                (regs ! #email))]
          (RequiresConfirmation, ConfirmAccount d)
            | d.confirmCode == regs ! #confirmCode ->
                [AccountConfirmed (AccountConfirmedData
                    (regs ! #email) d.confirmCode d.at)]
          ...  -- 7 transition cases
          _ -> []   -- catch-all rejecting unmapped (vertex, command)
      , evolve = \(v, regs) ev -> case (v, ev) of
          (PotentialCustomer, RegistrationStarted d) ->
            (Registering, regs `set` ...)
          (Registering, ConfirmationEmailSent _) ->
            (RequiresConfirmation, regs)
          ...  -- 7 evolve cases mirroring decide
          _ -> (v, regs)  -- ignore unrecognized event
      , initialState = (PotentialCustomer, emptyRegs)
      , isTerminal = \(v, _) -> v == Deleted
      }

The shape works, ships, and is well-understood. But it has structural
weaknesses that `Keiki.Generics` + the keiki core retire:

### 1. Forward / inverse drift

`decide` and `evolve` are independent functions. There is no
mechanical guarantee they agree. A user can:

- Add a field to a command without adding it to the corresponding
  event (or vice versa).
- Read a field in `evolve` that `decide` never put on the wire (the
  hidden-input bug from synthesis §4 step 4).
- Emit an event whose payload `evolve` doesn't pattern-match.

These divergences typically surface in production as missing data on
replay. They are caught by hand-written tests if at all; the type
system does not help.

**keiki**: `decide` is encoded by `edge.guard` + `edge.update` +
`edge.output` (the `OPack`). `evolve` (the inverse, used for replay)
is *derived mechanically* by `solveOutput` walking the `OPack`'s
`OutFields` against the named `InCtor`. Drift is impossible by
construction — there is only one piece of code (the `OPack`), and
both directions read off it. Adding a field to a command's payload
forces the user to either:

  (a) include it in the event's `OutFields` (where `solveOutput` can
      recover it), or
  (b) accept that `solveOutput` returns `Nothing` and `checkHiddenInputs`
      flags the edge by name at build time.

### 2. Hidden-input detection

The naive decider has no concept of *hidden input*. If `decide` reads
`d.confirmCode` from a command and the corresponding event omits it,
`evolve` cannot recover the field on replay — but nothing in the
naive decider's types catches this. The user discovers the bug when
replay produces wrong state.

**keiki**: `checkHiddenInputs` walks every edge, identifies edges
whose `OPack` `OutFields` don't visit every slot of the named
`InCtor`, and produces a precise warning naming the missing field.
This is a *build-time* analysis on the transducer; the canonical V0
demonstration prints `OPack walk for InCtor "ConfirmAccount" leaves
field {"confirmCode"} unrecovered`. (See
`docs/plans/5-replace-tinpfield-with-structural-input-projection-tinpproj.md`
for EP-1's design and demonstration.)

### 3. Single-valuedness

A transducer is single-valued when at most one outgoing edge is
satisfied for any given input at any reachable state. The naive
decider has no notion of this property — it is implicit in the
`decide` function's structure. To check that two command branches are
mutually exclusive, the user runs property tests with a generator.

**keiki**: `isSingleValuedSym (withSymPred userReg) == True` is a
precise symbolic check, dispatched to z3 via SBV. The conjunction of
two edge guards is an SMT problem; if z3 says unsat, the edges are
provably disjoint. `userReg`'s constructor-mutex branches at
`RequiresConfirmation` (Confirm vs. Resend vs. GDPR) are decided in
microseconds. (See `docs/research/sbv-boolalg-design.md` for EP-2's
design.)

### 4. Authoring DX

This is the comparison the rest of this note focuses on. The naive
decider's `decide`/`evolve` functions are typically multi-line `case`
expressions: 7 transitions × 2 directions × ~3 lines per branch =
~42 lines of case logic. The user is responsible for the syntactic
shape of every branch.

**keiki + Keiki.Generics**: 5 `InCtor` declarations (one line each) +
5 `WireCtor` declarations (one line each) + a 5-edge `userRegEdges`
function where each edge declares `guard`, `update`, `output`,
`target` structurally. Each branch of `decide` is replaced by an
`Edge` record; each branch of `evolve` is *gone* (derived
mechanically). The total surface for the transition logic is
~60-80 lines for User Registration, comparable to a naive decider's
**single direction**, with the inverse direction free.

### Summary

    Concern              Naive decider          keiki + Keiki.Generics
    ──────────────────── ────────────────────── ──────────────────────
    Forward direction    decide :: c -> s -> [e]  edge.guard / .update / .output
    Inverse direction    evolve :: s -> e -> s    derived (solveOutput)
    Drift                Possible                 Impossible
    Hidden input         Production bug           Build-time warning
    Single-valuedness    Property test            Symbolic decision (z3)
    Lines per ctor       ~6 (decide+evolve)       1 (mkInCtorVia / mkWireCtorVia)
    Compile-time deps    base                     base, sbv, GHC.Generics

The naive decider is simpler in dependencies and conceptual
machinery. keiki's symbolic core trades that simplicity for
mechanical inverses, build-time analyses, and decidable
single-valuedness — and `Keiki.Generics` reclaims the per-ctor line
count so the surface is comparable to the naive form despite the
deeper guarantees.


## DX comparison against `crem`

`crem` (Compositional Representable Executable Machines) is the
production-grade Haskell Mealy-machine library compared functionally
in `docs/research/architecture-comparison-fst-aggregate-vs-crem.md`.
This section adds the **authoring DX** angle that note doesn't
cover.

### The crem authoring shape

For the same User Registration aggregate, a crem implementation
declares:

1. A type-level `Topology`:

       type RegTopology = 'Topology
         '[ '( 'PotentialCustomer, '[ 'Registering, 'RequiresConfirmation, 'Deleted ])
          , '( 'Registering, '[ 'RequiresConfirmation ])
          , '( 'RequiresConfirmation, '[ 'RequiresConfirmation, 'Confirmed, 'Deleted ])
          , '( 'Confirmed, '[ 'Deleted ])
          ]

2. A vertex-indexed state GADT:

       data RegState (v :: RegVertex) where
         SPotentialCustomer    :: RegState 'PotentialCustomer
         SRegistering          :: Email -> ConfirmationCode -> RegState 'Registering
         SRequiresConfirmation :: Email -> ConfirmationCode -> RegState 'RequiresConfirmation
         SConfirmed            :: Email -> RegState 'Confirmed
         SDeleted              :: RegState 'Deleted

3. An `action` function with `AllowedTransition` proofs implicit at
   each branch:

       action :: RegState v -> RegCommand
              -> ActionResult m RegTopology RegState v RegEvent
       action SPotentialCustomer (StartRegistration email cc at) =
         ActionResult $ pure (RegistrationStarted email cc at,
                              SRegistering email cc)
       action SRegistering Continue =
         ActionResult $ pure (ConfirmationEmailSent email,
                              SRequiresConfirmation email cc)
       ...

4. A separate `Decider` if event sourcing is wanted, with
   `decide`/`evolve` doubling much of the action logic.

5. `singletons-base` and friends as transitive deps to support the
   type-level topology.

The DX is roughly comparable to keiki's per-edge layout — both ship a
case-style transition table. crem buys compile-time topology
enforcement (illegal transitions are type errors); keiki buys
mechanical inverses and symbolic single-valuedness. The line counts
are within ~20% of each other.

### Where keiki + Keiki.Generics wins on DX

1. **No singletons**. crem requires `singletons-base` and
   `singletons-th` to demote the type-level topology. These are heavy
   dependencies (`singletons-base` pulls a TH stage, complicates
   error messages, and adds compile time). keiki uses `GHC.Generics`
   only.

2. **No vertex-indexed state GADT per aggregate**. crem's
   `RegState v` requires a constructor per vertex. keiki uses a
   plain `Vertex` enum plus a uniform `RegFile UserRegRegs`. The
   trade-off: keiki can't say "this slot only exists at `Confirmed`";
   crem can. For aggregates whose register file is uniform across
   vertices (which is the dominant case in event sourcing), keiki is
   simpler.

3. **No separate `decide` and `evolve`**. crem's `Decider` pattern
   has the user write both functions — the same drift problem as the
   naive decider. keiki derives the inverse from the structural
   `OPack`.

4. **One-liner ctor declarations**. crem has no equivalent of
   `mkInCtorVia` / `mkWireCtorVia` because crem has no `InCtor` /
   `WireCtor` concept — events flow through `action`'s tuple return
   directly, with no explicit on-the-wire shape. The authoring saving
   doesn't transfer; the comparison is "keiki's compact ctor surface
   + structural inversion" vs. "crem's compact action function +
   compile-time topology". Different trades.

### Where crem wins on DX

1. **Compile-time transition safety**. Writing `action SConfirmed
   StartRegistration` in crem is a type error. In keiki, the same
   mistake produces an edge that `delta` rejects at runtime via
   returning `Nothing`. Both fail loudly; crem fails earlier.

2. **Composition primitives**. crem ships `Sequential`, `Parallel`,
   `Alternative`, `Feedback`, `Kleisli` plus the full Profunctor
   hierarchy. keiki ships `union` and (proposed) `compose`. For
   aggregates that compose into larger workflows (process managers,
   sagas), crem's surface is richer at the authoring layer.

3. **Built-in visualization**. crem renders Mermaid diagrams of the
   topology and composition tree out of the box. keiki has nothing.

### Verdict

`Keiki.Generics` brings keiki's authoring DX to roughly the same
character count as crem on a per-construct basis, while keiki keeps
its existing strengths (mechanical inversion, build-time hidden-input
check, symbolic single-valuedness via SBV) and shed the
`singletons-base` overhead crem inherits.

Authors who want compile-time topology enforcement and rich
composition pick crem. Authors who want correctness-by-construction
on the event-sourcing inverse and decidable single-valuedness pick
keiki. The DX cost is no longer a differentiator.


## The Cmd / Wire bundle experiment (rejected)

A natural extension of the `Via` builders is a record-bundle that
pairs an `InCtor` with the helpers that almost always travel with it
(an `inp` projection function, an `is` constructor guard):

    data Cmd ci ifs = Cmd
      { inCtor :: InCtor ci ifs
      , inp    :: forall rs r. Index ifs r -> Term rs ci r
      , is     :: forall rs.   HsPred rs ci
      }

    cmdStart :: Cmd UserCmd StartFields
    cmdStart = mkCmd @"StartRegistration"

The user would then write `cmdStart.inp #email`, `cmdStart.is`,
`cmdStart.inCtor` at edge sites instead of the three top-level
binders.

### Why the bundle doesn't work

`OverloadedRecordDot` desugars `cmdStart.inp` to `getField @"inp"
cmdStart`. GHC requires a `HasField "inp" (Cmd ci ifs) (...)`
instance to resolve this. Auto-derived `HasField` instances are
generated by GHC for every monomorphic record field, but **not for
fields whose type is rank-N polymorphic**. The `inp` and `is` fields
above quantify over `rs` (and `inp` over `r` as well), making them
rank-N. No `HasField` instance is generated, and `cmdStart.inp`
fails to type-check.

The polymorphism is not a design choice — it is *necessary*. A
single `Cmd UserCmd StartFields` value must work in any aggregate
whose register file admits the `StartFields` projection (i.e. any
`UserRegRegs`-shaped slot list). Pinning `rs` at construction time
would mean a different `cmdStart` per aggregate, defeating reuse.

### The two ways out (both worse)

- **Function-call accessors.** Define `inp :: Cmd ci ifs -> Index ifs
  r -> Term rs ci r` as a top-level helper. Then `inp cmdStart
  #email` works. But that is **longer** than the flat form
  `inpStart #email` by 4 characters per call site, and the User
  Registration aggregate has 19 input-projection call sites in
  `userRegEdges` alone. The bundle imposes a per-callsite tax for
  no saving at the declaration site.

- **Pin `rs` at construction time.** `Cmd UserRegRegs UserCmd
  StartFields`. The dot syntax works (`is` is now monomorphic); the
  call sites read `cmdStart.is`. But the bundle is no longer
  reusable across aggregates with different register files, the
  type signature is one parameter heavier, and the "save lines at
  call site" promise (`cmdStart.is` is 11 chars vs `isStart` at 7
  chars) is reversed.

### Verdict

Bundling rank-N helpers behind a record-and-dot interface is a known
GHC limitation; the keiki use case hits it head-on. The flat
top-level binders (`inpStart`, `isStart`, `inCtorStart`) are
already minimal — three short binders, one line each, derivable from
the `InCtor` value via the existing helper functions. Bundling adds
no leverage. The experiment is documented here so a future reader
doesn't repeat it.

The `Cmd` / `Wire` types are not exported from `Keiki.Generics` for
this reason. The flat form is the recommended authoring style.


## Future improvements

The current `Keiki.Generics` is a pragmatic stop. Several extensions
are tractable and would push the DX further; each is sized roughly
in terms of effort, listed in approximate order of leverage.

### A. Template Haskell `$(deriveAggregateCtors ''UserCmd)`

The `Via` builders still require the user to write three top-level
declarations per command constructor:

    inCtorStart :: InCtor UserCmd StartFields
    inCtorStart  = mkInCtorVia @"StartRegistration"

    inpStart    :: Index StartFields r -> Term UserRegRegs UserCmd r
    inpStart     = TInpCtorField inCtorStart

    isStart     :: HsPred UserRegRegs UserCmd
    isStart      = matchInCtor inCtorStart

A TH splice could generate all three from the constructor name plus
the sum type and the register file slot list:

    $(deriveAggregateCtors
        ''UserCmd
        ''UserRegRegs
        [ ("StartRegistration",  "Start")
        , ("ConfirmAccount",     "Confirm")
        , ("ResendConfirmation", "Resend")
        , ("FulfillGDPRRequest", "Gdpr")
        ])

— or with a name mapping derived from the constructor itself. The
splice expands to the 15 declarations User Registration currently
ships in 15 lines; the user writes one form. Cost: a TH dependency
and the indirection it introduces. Effort: ~4 hours including a
working splice and a test. Net leverage: another ~50 lines saved at
the example layer, plus per-new-aggregate savings at scale.

**EP-8 design choices (2026-05-01).** The splice is *two* splices,
not one: `deriveAggregateCtors` for the command sum and
`deriveWireCtors` for the event sum. Two splices read clearer at
the call site than a single splice with five arguments — the user
sees what's being generated.

    deriveAggregateCtors
      :: Name              -- ''UserCmd
      -> Name              -- ''UserRegRegs (the slot-list type alias)
      -> [(String, String)]
      -> Q [Dec]

    deriveWireCtors
      :: Name              -- ''UserEvent
      -> [(String, String)]
      -> Q [Dec]

The `(String, String)` pair is `(constructorName, shortName)`. The
short name is *explicit* (rather than auto-derived from the
constructor) for one reason: existing call sites use short names
like `inpStart`, `inpConfirm`, etc., not `inpStartRegistration`.
Auto-deriving short names from constructor names would force a
~19-call-site rename in `userRegEdges` for no leverage.

For each spec entry the splice emits, in module scope:

    inCtor<Short>  :: InCtor <CmdSum> (RegFieldsOf <PayloadType>)
    inCtor<Short>   = mkInCtorVia @<ctorName>

    inp<Short>     :: Index (RegFieldsOf <PayloadType>) r
                            -> Term <Regs> <CmdSum> r
    inp<Short>      = TInpCtorField inCtor<Short>

    is<Short>      :: HsPred <Regs> <CmdSum>
    is<Short>       = matchInCtor inCtor<Short>

Singleton constructors (zero-payload `NormalC`, e.g. `Continue`) are
detected during TH introspection. The splice emits only `inCtor` and
`is` for them, using `mkInCtor0` (which compares the value via `Eq`):

    inCtor<Short>  :: InCtor <CmdSum> '[]
    inCtor<Short>   = mkInCtor0 <ctorName> <CtorRef>

    is<Short>      :: HsPred <Regs> <CmdSum>
    is<Short>       = matchInCtor inCtor<Short>

`inp<Short>` is omitted because `Index '[]` is uninhabited; emitting
it would add useless boilerplate.

`deriveWireCtors` is the dual on the event side, emitting:

    wire<Short>    :: WireCtor <EventSum> (FieldsOf <PayloadType>)
    wire<Short>     = mkWireCtorVia @<ctorName>

per spec entry. Singleton events are not currently supported (they
would require a different `mkWireCtor`-shape variant; out of scope
because no existing example uses one).

**Implemented (see EP-8).** `Keiki.Generics.TH` ships both splices;
`Keiki.Examples.UserRegistration` uses them in place of the four
slot-list aliases, five `inCtor*`, four `inp*`, five `is*`, one
singleton `inCtorContinue`, and five `wire*` declarations. See
`docs/plans/8-th-deriveaggregatectors-and-fieldsof-slot-list-type-family.md`
and `src/Keiki/Generics/TH.hs`.

### B. `FieldsOf` deriving for `RegFile` slot lists

Currently the user writes the slot-list type alias by hand:

    type StartFields =
      '[ '("email", Email)
       , '("confirmCode", ConfirmationCode)
       , '("at", UTCTime)
       ]

This is mechanical: the slot list is the same as `FieldsOf
StartRegistrationData` viewed as a `[Slot]` instead of a
nested-pair tuple. A `RegFieldsOf` type family on `Rep d` would
derive the slot list, so the user could write:

    inCtorStart :: InCtor UserCmd (RegFieldsOf StartRegistrationData)
    inCtorStart  = mkInCtorVia @"StartRegistration"

— or, paired with (A), drop the type alias entirely. Cost: another
type family and `GRecord`-like instance walks, ~1 hour. The trade-off:
type-family-derived slot lists are less readable in error messages
than hand-written aliases. Currently neutral.

**Implemented (see EP-8) as `RegFieldsOf`.** The type family lives
in `Keiki.Generics`:

    type RegFieldsOf d = RegFieldsOfRep (Rep d)

    type family RegFieldsOfRep (rep :: Type -> Type) :: [Slot] where
      RegFieldsOfRep (M1 D _ inner) = RegFieldsOfRep inner
      RegFieldsOfRep (M1 C _ inner) = RegFieldsOfRep inner
      RegFieldsOfRep (M1 S ('MetaSel ('Just n) _ _ _) (K1 _ t))
                                    = '[ '(n, t) ]
      RegFieldsOfRep U1             = '[]
      RegFieldsOfRep (l :*: r)      = Append (RegFieldsOfRep l)
                                             (RegFieldsOfRep r)

It is bundled with item A because the EP-8 splice's
`InCtor <Cmd> (RegFieldsOf <Payload>)` signature consumes it
directly — without `RegFieldsOf`, the splice would need either
per-ctor slot-list aliases as additional input or hand-derived
inline `'[ '("name", T), ... ]` lists. The non-`Reg` `FieldsOf`
(already shipped for `WireCtor`'s nested-pair tuples) is
unchanged. See `src/Keiki/Generics.hs`.

### C. Generic-derived `Term` projection helpers

The `inpStart` / `inpConfirm` / ... helpers boil down to
`TInpCtorField inCtor*`. They could be generated by a typeclass:

    class HasInpHelpers ci where
      type InCtorsOf ci :: [(Symbol, [Slot])]
      inpHelpers :: InpHelpers ci

so `inpStart` becomes `inp @"StartRegistration"` everywhere. Cost:
medium; the typeclass interaction with the slot lookup is fiddly.
Probably not worth it without (A) — TH does the same job more
directly.

**Considered and rejected (see EP-8).** Item A's splice generates
the same three declarations item C's typeclass would expose at use
sites: `inp @"StartRegistration" #email` and `inpStart #email` are
indistinguishable surface forms. With A landed, C would mean
maintaining a second derivation path for one extra typeclass-level
indirection — at the call site no measurably different.
Maintaining two paths is the cost without a leverage gain. EP-8's
Decision Log records the rejection. No `HasInpHelpers` typeclass is
shipped.

### D. Symbolic `WitnessExtract` instances via Generics

EP-2's M5 punted on full witness extraction in `symSat`. A future
`symSatExt` requires hand-written `WitnessExtract rs ci` instances:
given an SBV model lookup, build a `RegFile rs` and a `ci` value.
This is mechanical for any (rs, ci) whose underlying types have
`Sym` instances; a `Generic`-driven derivation would write the
instances automatically. Effort: ~6-8 hours including the SBV model
plumbing. Net win: the User Registration symbolic spec gains a
"build a concrete `(regs, cmd)` witness from a `sat` query and
verify `models` agrees" round-trip test.

**EP-9 design choices (2026-05-01).** The witness-extract surface
ships as two typeclasses plus an existential wrapper:

    class ExtractRegFile (rs :: [Slot]) where
      extractRegFile :: (forall r. Sym r => String -> r) -> RegFile rs

    data SomeInCtor (ci :: Type) where
      SomeInCtor :: ExtractRegFile ifs => InCtor ci ifs -> SomeInCtor ci

    class KnownInCtors ci where
      allInCtors :: [SomeInCtor ci]

Five small choices fix the shape:

1. *Module placement: `Keiki.Symbolic`, not `Keiki.Generics`.* The
   plan's default was Generics. Override: the classes depend on
   `Sym` (which lives in `Keiki.Symbolic`). Putting them in
   `Keiki.Generics` would force a `Generics → Symbolic` dependency
   that pulls SBV into `Keiki.Generics.TH`'s transitive imports
   (every TH-using example module would then compile-depend on
   SBV). `Keiki.Symbolic` is the natural home for "extract concrete
   witnesses from SBV models". `Keiki.Generics` stays
   SBV-independent.

2. *SBV variable naming scheme.* `TReg ix` allocates with the name
   `"reg/" <> indexName ix`; `TInpCtorField ic ix` with
   `"inp/" <> icName ic <> "/" <> indexName ix`. The shared input
   constructor tag stays `"inputCtor"`. Escape-hatch terms
   (`TApp1`, `TApp2`, `PMatchC`, the `neq` fallback in `goEq`) keep
   their existing anonymous names — their values are not extracted
   (the witness extractor walks `rs` and `ifs`, not opaque function
   results). The slot/field name comes from the existing
   `KnownSymbol` evidence on `Index`'s `ZIdx` constructor; a small
   helper `indexName :: Index rs r -> String` walks the index.

3. *No memoization in v1.* SBV's `free name` uniquifies repeated
   names by appending `_N` — two calls to `free "x"` produce `x`
   and `x_0`, both with their own model value. For predicates with
   repeated reads of the same slot or input field
   (e.g. `proj #x .== proj #x`), the two allocations are independent
   SBV variables; the solver may pick distinct values and the
   witness extractor's name lookup returns only the first
   allocation. The reconstructed witness then *might not* satisfy
   the original predicate's structural-equality reads. The User
   Registration test target — the `RequiresConfirmation`
   ConfirmAccount edge guard — has no repeated reads, so the
   round-trip is sound. Memoization (via an `IORef`-cached
   `Map String SomeSBV` in `SymEnv`) is a documented follow-up;
   `symSatExt`'s haddock states the limitation and the workaround
   (split a repeated-read predicate into a fresh-variable form).

4. *`Sym` typeclass extension.* Add a `symDefault :: a` method.
   Defaults: `Bool→False`, `Int→0`, `Integer→0`, `Text→""`,
   `UTCTime→epoch (1970-01-01T00:00:00Z)`. Unconstrained slots —
   slots not referenced by the predicate — have no value in the
   SBV model; the extractor falls back to `symDefault`. This is
   sound because the predicate doesn't constrain those slots, so
   any value satisfies it. Without `symDefault`, extraction would
   fail (return `Nothing`) for any predicate that doesn't mention
   every slot — a strict sub-set of the test surface.

5. *Keep `symSat` alongside `symSatExt`.* The plan considered
   merging them. Override: `BoolAlg.sat`'s typeclass signature
   (`phi -> Maybe a`) cannot carry the extra
   `ExtractRegFile`/`KnownInCtors` constraints. `symSat` stays the
   `BoolAlg`-routed entry point with the `unsafeWitness`
   placeholder; `symSatExt` is the new constraint-carrying variant
   for callers that have the constraints in scope. The translation
   is shared — both functions call `translatePred` over an env
   built by `mkSymEnv`.

**Implemented (see EP-9).** `Keiki.Symbolic` ships
`symSatExt :: (ExtractRegFile rs, KnownInCtors ci) =>
HsPred rs ci -> Maybe (RegFile rs, ci)` plus the
`ExtractRegFile`/`SomeInCtor`/`KnownInCtors` typeclasses.
The `Sym` typeclass gained a `symDefault :: a` method; the five
curated instances (`Bool`, `Int`, `Integer`, `Text`, `UTCTime`)
return `False`/`0`/`""`/epoch. `Keiki.Examples.UserRegistration`
ships a `KnownInCtors UserCmd` instance bagging its five
`InCtor` values. Round-trip tests in
`UserRegistrationSymbolicSpec` cover the
`RequiresConfirmation`/`ConfirmAccount` edge guard, a literal-
backed `PEq`, the constructor-mutex unsat case, and the
singleton-`Continue` reconstruction. See
`docs/plans/9-generic-derived-witnessextract-for-symsatext-round-trip.md`
and `src/Keiki/Symbolic.hs`.

### E. Generic-derived Decider façade

For users coming from the naive-decider world, exposing a
`toDecider` projection from a `SymTransducer` to a `Decider`-shaped
record would smooth the migration. The `decide` function comes from
`omega`; the `evolve` function comes from a `delta`-with-event
reformulation built atop `applyEvent`/`solveOutput`. The keiki
formalism guarantees they agree. This is ~2 hours of plumbing on a
new module `Keiki.Decider`.

**EP-10 design choices (2026-05-01).** `Keiki.Decider` ships the
four-field Chassaing canonical record verbatim:

    data Decider c e s = Decider
      { decide       :: c -> s -> [e]
      , evolve       :: s -> e -> s
      , initialState :: s
      , isTerminal   :: s -> Bool
      }

with the projection

    toDecider
      :: BoolAlg phi (RegFile rs, ci)
      => SymTransducer phi rs s ci co
      -> Decider ci co (s, RegFile rs)

Three small choices fix the shape:

1. *State carrier `(s, RegFile rs)`.* The same pair `delta` and
   `applyEvent` operate on. Alternative shapes that fold the
   register file into `s` were rejected because keiki's `omega`
   needs the registers to evaluate edge guards; carrying the pair
   keeps the façade's `decide` a pure function of its arguments.

2. *`Maybe co` lifts to `[e]`.* `Just co → [co]`, `Nothing → []`.
   The Chassaing `decide` returns a list because some aggregates
   emit zero-or-many events per command; the keiki transducer
   emits at most one. A future *MultiDecider* (synthesis §5) is
   the relaxation point, but it is out of scope for EP-10.

3. *ε-edges are silent for the façade.* When an edge has
   `output = Nothing`, `omega` returns `Nothing`, and the façade's
   `decide` returns `[]`. A subsequent `evolve` over `[]` is a
   no-op, so the state does **not** transition — even though the
   keiki `delta` for the same edge would. This is documented in
   the module haddock and reproduced as an explicit test in
   `test/Keiki/DeciderSpec.hs`. The User Registration aggregate's
   `FulfillGDPRRequest` edge from `RequiresConfirmation` is the
   worked instance: ε-deletion before confirmation. Callers who
   need ε-driven state must call `delta` directly, or pair
   `decide` with their own no-event-case logic. Encoding ε-edges
   as synthetic events was rejected because it would either
   change the `Decider` record's shape (no longer "Chassaing
   canonical") or place internal events on the wire (defeats the
   point of the façade — keiki's events are wire events).

**Implemented (see EP-10).** `Keiki.Decider` exports the record
and `toDecider` per the design above; the round-trip on
`userReg`'s canonical log lands in `(Deleted, expectedSnapshot)`,
matching `reconstitute`. See
`docs/plans/10-keiki-decider-facade-for-naive-decider-migration.md`
and `src/Keiki/Decider.hs`.

### F. crem-style composition combinators on `SymTransducer`

The crem comparison note proposes `compose`, `feedback`,
`alternative` operations on transducers. None affect the per-ctor DX
but each opens authoring patterns that today require manual
plumbing (e.g. process managers spanning two aggregates). Effort:
significant (each combinator needs a careful semantics worked out
against the formal projection); independent of `Keiki.Generics`'
DX scope.

**Implemented (see EP-11 / MP-4).** `Keiki.Composition` ships
sequential `compose` as the minimum viable combinator. The
implementation walks t2's `HsPred` / `Term` / `Update` / `OutTerm`
ASTs and substitutes `mid`-reads with structural references to
t1's edge output, preserving the keiki guarantees end-to-end:
mechanical inversion via `solveOutput` chained through the
composite's `OPack`, hidden-input check on transitively-hidden
fields, and symbolic single-valuedness when both underlying
transducers are individually single-valued. The substitution
restricts t1 outputs to `OPack` and t2 mid-side guards to
structural patterns (`PInCtor` / `PEq` / `TInpCtorField`); v1
escape hatches (`OFn`, `PMatchC` over `mid`) used to raise a
runtime error naming the offending edge — moot post-MP-6, since
EP-16 retired `OFn` and EP-17 retired `PMatchC`. The worked
example at `test/Keiki/CompositionSpec.hs` composes a tiny
`AlertSource` fixture with `Keiki.Examples.EmailDelivery`; six
tests verify `step`, `omega`, `reconstitute`,
`checkHiddenInputs`, and `isSingleValuedSym` on the composite.
See `docs/plans/11-composition-combinators-on-symtransducer.md`,
`docs/research/composition-combinators-design.md`, and
`src/Keiki/Composition.hs`.

**In progress (see EP-24 / MP-8).** `MasterPlan 8`
(`docs/masterplans/8-composition-combinators-beyond-sequential-parallel-alternative-feedback-kleisli.md`)
extends `Keiki.Composition` with two further combinators decided
by EP-24's design milestone
(`docs/plans/24-composition-combinators-beyond-sequential-design-milestone.md`):
`alternative` (sum-input dispatch on `Either ci1 ci2`, reusing
the existing product vertex `Composite s1 s2` so each composite
vertex emits both t1's `Left`-gated edges and t2's `Right`-gated
edges with the appropriate frozen sub-vertex) and `feedback1`
(single-step aggregate ↔ stateless-policy round, expressed as
nested `compose` applications). `parallel` and `Kleisli` are
re-deferred — the former because keiki's queue-driven runtime
delivers one command at a time and the strict-tuple shape doesn't
fit, the latter because the multi-event edge form (Approach 3 in
`docs/research/multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md`)
is out of MP-8's scope and MP-7's state refinement covers the
in-aggregate case. The full per-combinator design records (full
signatures, semantics, preservation arguments, acceptance
criteria, and limitations) live in
`docs/research/composition-combinators-design.md` under the
"Combinators beyond `compose`" section.

**Shipped (EP-25, 2026-05-03).** `alternative` is in the
`Keiki.Composition` module; the acceptance test at
`test/Keiki/CompositionAlternativeSpec.hs` exercises Left/Right
routing, interleaved updates that preserve the other arm's
state, mixed-arm reconstitute (both orderings),
`checkHiddenInputs`, and `isSingleValuedSym`. Full test suite is
178 examples, 0 failures. EP-25 surfaced a design discovery —
the sum vertex `CompositeSum` originally proposed by EP-24 is
degenerate; the product `Composite` is the right shape. The
design record under
`docs/research/composition-combinators-design.md` records both
the finding and the revised semantics.

**Shipped (EP-26, 2026-05-03).** `feedback1` is in the
`Keiki.Composition` module as the literal
`feedback1 t f = compose t (compose f t)`; the acceptance test at
`test/Keiki/CompositionFeedback1Spec.hs` exercises single-step
cascade, two-step round-trip, `reconstitute`,
`checkHiddenInputs`, `isSingleValuedSym`, and `omega` against a
toggle aggregate cascaded through a stateless echo policy. The
composite vertex is `Composite s1 (Composite s2 s1)` — implicit
by structure, so no new types were added. Full test suite is 185
examples, 0 failures. EP-26 surfaced one limitation: the call
site only typechecks for stateless aggregates (`rs1 = '[]`)
because the
`Disjoint (Names rs1) (Names (Append rs2 rs1))` constraint forces
`rs1` to be disjoint from itself. The design record under
`docs/research/composition-combinators-design.md` records the
constraint deviation and the future "shared-state" variant that
would relax this restriction.

### G. Compile-time transition safety (singletons-style)

The biggest crem advantage that DX can't reclaim without invasive
changes. A future v3 could introduce an opt-in
`SymTransducerStrict` parameterized over a type-level topology,
making invalid transitions type errors. This is a separate
MasterPlan-sized initiative; out of scope for the authoring DX
discussion.


### H. `genView` TH splice for B-presentation `View v` GADT

The synthesis note's §3 ("Where indexed state (B) fits") proposes
a per-vertex projection on top of the shared register file: for
each control vertex `v` define a GADT constructor that exposes
only the slots live in that vertex, then write `viewFor :: SVertex
v -> RegFile rs -> View v`. The synthesis note flagged the
codegen for this shape as opt-in: *"A `genView` TH helper is a
nice-to-have, not a v1 requirement."* Until EP-13, no aggregate in
`src/Keiki/Examples/` had a B-view; users would hand-write the
singletons GADT, the View GADT, and the projection function (~40
lines for a five-vertex aggregate, easy to get wrong — a missed
vertex turns into a non-exhaustive pattern; a typoed slot name
turns into a type error pages from the authoring site).

**Implemented (see EP-13 / MP-5).** `Keiki.Generics.TH` ships
`deriveView`, the third splice in the family alongside
`deriveAggregateCtors` (item A) and `deriveWireCtors` (item A).
The user-facing surface is one Q-action with three `String`
name arguments and a `[(vertexCtor, [slot])]` spec list:

    $(deriveView ''Vertex ''UserRegRegs
        "SUserVertex" "UserView" "userView"
        [ ("PotentialCustomer",    [])
        , ("Registering",          [])
        , ("RequiresConfirmation", ["email", "confirmCode"])
        , ("Confirmed",            ["email", "confirmedAt"])
        , ("Deleted",              ["email", "deletedAt"])
        ])

The splice runs five splice-time validation checks (vertex enum
shape, total-coverage spec dedup, slot-list shape, slot membership
+ dedup, prefix uniqueness) and emits a per-aggregate singletons
GADT (`SUserVertex`), a per-aggregate View GADT (`UserView`) with
one constructor per vertex carrying the live slots as record
fields named `<prefix><Slot>` (where `<prefix>` is the
lower-cased upper-case letters of the vertex name), and the
projection function (`userView`). Worked example:
`Keiki.Examples.UserRegistration` exports `UserView (..)`,
`SUserVertex (..)`, and `userView`; six tests in
`test/Keiki/Examples/UserRegistrationViewSpec.hs` exercise the
projection on hand-constructed register files. See
`docs/research/genview-th-splice-design.md` for the full design,
`docs/plans/13-genview-th-splice-and-b-presentation-view-v-gadt.md`
for the implementation plan, and the synthesis note's §3 + §4.4
for the motivating shape. Default `View v = RegFile rs` for
non-opted-in aggregates, a shared `Singleton` class, and
edge-driven cross-validation of the spec are deferred until a real
need surfaces.


## Summary table

    Dimension                    Naive decider   crem            keiki + Keiki.Generics
    ──────────────────────────── ─────────────── ─────────────── ───────────────────────
    Lines per ctor               ~6 (per dir)    ~6 per branch   1 (Via)
    Forward / inverse drift      Possible        Possible        Impossible (derived)
    Hidden-input detection       —               —               Build-time check
    Single-valuedness            Property test   —               Symbolic (z3)
    Compile-time topology        —               Yes (heavy)     —
    Composition combinators      —               Six             One (compose; more proposed)
    Built-in visualization       —               Mermaid         —
    Vertex-indexed state         —               GADT per vtx    Plain enum
    Dependency surface           base            singletons-base, base, sbv, generics
                                                  profunctors,
                                                  machines,
                                                  nothunks
    Effects                      User responsibility  Monad param  Pure (proposed)


## Closing

The `Keiki.Generics` rollout retired ~156 lines of mechanical
boilerplate from the User Registration aggregate (V5 + V0) without
loss of semantic information. The Generic-derived `Via` builders
bring the per-ctor authoring cost down to a single type-app, putting
keiki on equal DX footing with crem on the per-construct dimension
while preserving the keiki-specific guarantees (mechanical inversion,
hidden-input warnings, symbolic single-valuedness) that the naive
decider lacks.

The bundle experiment (Cmd / Wire records with dot accessors) failed
on a fundamental GHC constraint — `HasField` doesn't auto-derive for
rank-N record fields — and is documented here as a learned negative.
The flat top-level form is the recommended authoring style.

The future-improvement list above describes a TH-driven path that
could push the per-ctor cost further (down to a single splice form
declaring all five InCtors + helpers + WireCtors of an aggregate),
but the leverage diminishes from here. The current state is a stable
floor; further DX work waits on either a real second example
aggregate (which exposes new patterns) or a TH commitment.
