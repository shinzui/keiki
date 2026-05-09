# DSL shape for the symbolic-register transducer

> **Status: largely historical.** This note settled the *v1 prototype*
> DSL — the AST shapes (`Term`, `OutTerm`, `Update`, `HsPred`) plus
> several intentionally-temporary "escape hatch" helpers that have
> since been retired. The retired helpers (`matchCmd`, `mkOut`,
> `OFn`/`InpFn`, `PMatchC`, `TInpField`, `unsafeCombine`) appear
> throughout the body below as if they were the live API; they are
> not. The retirements are recorded in
> `v1-escape-hatch-retirements-design.md` — the table at the top of
> that note maps each retired helper to its structural successor
> (`InCtor`, `WireCtor` + `OPack`, `PInCtor` / `matchInCtor`,
> `combine` with static `Disjoint`).
>
> For the **current** DSL surface, read in this order:
> 1. `docs/research/edge-builder-dsl-shape.md` — design of the
>    QualifiedDo `Keiki.Builder` DSL that authors actually use.
> 2. The haddock for `Keiki.Builder` and `Keiki.Core` modules.
> 3. The worked examples in `jitsurei/src/Jitsurei/UserRegistration.hs`
>    and `jitsurei/src/Jitsurei/EmailDelivery.hs` — each ships the
>    same transducer authored in both the AST and the Builder forms,
>    side by side.
>
> The AST shapes (`Term`, `OutTerm`, `Update`, `HsPred`) and the
> `RegFile` survey survived essentially unchanged into the shipped
> `Keiki.Core`; those parts of this note are still accurate. The
> User Registration transcription in the body uses the v1 escape
> hatches and would not compile against current `Keiki.Core`.

This note settled the embedded-DSL surface that keiki users will write to
declare a `SymTransducer`. It picks concrete Haskell datatype shapes for
`Term`, `OutTerm`, `Update`, `Edge`, `SymTransducer`, `RegFile`, `Index`,
and the predicate carrier `HsPred`; defines the ergonomic helpers
(`matchCmd`, `mkOut`, `proj`, `inp`, `(!)`); transcribes the
User Registration aggregate from the synthesis note in the chosen DSL with
no pseudosyntax; and produces a Prototype Implementation Checklist that
the v1 prototype (ExecPlan 4) consumes as a hand-off contract.

The companion documents are
`docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`
(the working baseline; its §4 User Registration aggregate is the
ergonomic stress-test transcribed below) and
`docs/research/data-direction-c-symbolic-and-register-automata.md` (the
rationale for copyless updates, single-valuedness, and the hidden-input
check). This note is self-contained against those two; familiarity with
the synthesis is assumed only for cross-references.


## Inputs and prerequisites

The synthesis note settled four foundational decisions that this note
does not re-litigate:

- **C is the formalism, B is opt-in presentation.** The core type is the
  symbolic-register transducer `SymTransducer phi rs s ci co`. The
  per-vertex GADT view (`View v`) is a derived projection users may
  define; this note does not define it.
- **Predicate carrier in v1 is a first-class AST.** Synthesis §7,
  option (b). v2 may swap in an SBV-backed instance; the carrier this
  note defines is the v1 AST.
- **Single-valuedness is a Hedgehog property test in v1; symbolic
  decision via SBV in v2 (MasterPlan 2 EP-2 `isSingleValuedSym`).**
  Synthesis §7. This note assumes runtime checks on `Combine`'s
  "distinct targets" invariant rather than type-level proofs; static
  enforcement of that invariant is deferred to a future MasterPlan
  (no successor drafted yet — see MP-2's decision log entry dated
  2026-05-01).
- **v1 ships with no SMT.** Updates and outputs are evaluated by a pure
  Haskell evaluator (synthesis §6). `solveOutput` is purely structural
  walking of the `OutTerm` AST.

What the synthesis explicitly defers to this note (synthesis §8 step 1):

- The concrete representation of `RegFile rs` (hand-rolled GADT vs
  `vinyl` vs alternatives).
- The constructor set of `Term`, `OutTerm`, `Update`, and the predicate
  carrier `HsPred`.
- The ergonomic helpers (`matchCmd`, `mkOut`, `proj`, `(!)`,
  `OverloadedLabels` for `Index`).
- A transcription of synthesis §4's `userReg` aggregate using only those
  concrete constructors, judged for ergonomic acceptability.


## Open questions this note resolves

Restated from synthesis §8 step 1 and from the parent ExecPlan's "What
this plan must settle":

1. Is `RegFile rs` hand-rolled or a dependency import? On what type-level
   carrier (`[Type]` vs `[(Symbol, Type)]`)?
2. What are the constructors of `Term rs ci r`? Is `inp` a structural
   field projection or an opaque `ci -> r` function?
3. What are the constructors of `OutTerm rs ci co`? Structural-AST or
   `Generic`-driven? How does `solveOutput` walk it?
4. What are the constructors of `Update rs ci`? How is the "distinct
   targets" invariant on `Combine` enforced?
5. What are the constructors of the predicate carrier `HsPred rs ci`?
   What does the `BoolAlg HsPred` instance look like?
6. What ergonomic helpers exist on top of the AST, with what types, and
   which of them are v1-only (because they leak opaque Haskell into the
   AST and so block the v2 hidden-input check)?
7. Does the User Registration aggregate transcribe cleanly in this DSL,
   or does the surface need iteration before EP-4 begins?

The answers, in order: hand-rolled GADT on `[(Symbol, Type)]`;
structural constructors with `InpField` plus a v1 `InpFn` escape hatch;
structural `Pack`-based `OutTerm` plus a v1 `OutFn` escape hatch; runtime
"distinct targets" check in a `combine` smart constructor; a small
Boolean-algebra AST with `PEq` and a v1 `PMatchC` escape hatch; helpers
defined below; and yes, the transcription is workable with two structural
divergences from synthesis §4 (documented as IP-1 and IP-2 in the
Surprises & Discoveries section of the parent ExecPlan).


## Survey of RegFile representations

The synthesis note's User Registration aggregate uses `OverloadedLabels`
syntax (`#email`, `#confirmCode`, ...) over a type-level list of
`'(Symbol, Type)` pairs. Any candidate must support that surface.

Note on methodology: `vinyl`, `large-records`, `extensible`, and
`superrecord` are not present in the local `mori` registry, which was
verified at the start of this work (see Decision Log entry for the
attempt). The survey below therefore draws on **published API
documentation and well-known design properties of these libraries**
rather than reading their source on disk. Where the survey makes a claim
about a library's API surface, it reflects the public Hackage docs as of
the libraries' current major releases. This is a known limitation of
this particular ergonomic survey; the conclusion is robust because the
chosen representation (hand-rolled GADT) deliberately depends on none of
them.

Four candidates were considered.

**`vinyl` (`Data.Vinyl.Core`, `Data.Vinyl.Lens`).** Records as
heterogeneous lists indexed by a type-level list of any kind, with
field-functor combinators (`Rec`, `FieldRec`, `ARec`). Supports named
fields via `Data.Vinyl.Derived.Field` (`'(Symbol, Type)` pairs
re-presented as a singleton-tagged value). `OverloadedLabels` works via
`Data.Vinyl.Lens`'s `rlens` and the `RElem` typeclass. Construction is
record-builder-like: `(Field "email" ::: email) :& (Field "confirmCode"
::: code) :& RNil`. Lookup is `view (rlens @"email")`.

Pros: substantial ecosystem, well-tested, supports type-level operations
on records (concat, project, restrict).
Cons: dependency footprint pulls in `vinyl` itself plus its requirement
on `singletons`-adjacent machinery for some operations; record-builder
syntax is workable but not pretty; type-level operations sometimes
produce confusing error messages on mismatched labels. Also, `vinyl`'s
"any kind" type-level carrier means we'd want a thin adapter to pin it
to `[(Symbol, Type)]`.

**`large-records` (`Data.Record.Generic`).** A TH-driven approach that
generates a record type from a declaration and exposes a `Generic`-style
interface for traversal. Designed primarily to fix the "GHC compile time
quadratic in record size" problem, not for type-level field manipulation.

Pros: zero runtime overhead, fast compile times for big records.
Cons: TH-driven means no type-level list of fields to project against.
The synthesis's "type-level list of slots" is not how `large-records`
thinks about records. Wrong shape.

**`extensible` (`Data.Extensible.Record`).** Type-level
`[Assoc Symbol Type]` (essentially `[(Symbol, Type)]`) with a record
type `Record xs` indexed by it. `OverloadedLabels` is a first-class
citizen; `record ^. #email` is the canonical lookup.

Pros: ergonomic `OverloadedLabels` story is the cleanest of the four;
type-level list shape matches the synthesis exactly; record construction
via `(<:)` and an empty `nil` is light syntax.
Cons: dependency footprint is non-trivial (lens, MTL adjacent
machinery); the library has been less actively maintained than `vinyl`
in recent years; sum-type machinery on `Variant xs` we don't need adds
build cost.

**`superrecord` (`SuperRecord.Field`).** Anonymous records with
`OverloadedLabels` and `IsLabel` instances; `(.=) :: l := v -> Rec rs ->
Rec ((l := v) ': rs)`-style construction.

Pros: ergonomic at the call site; very small dependency.
Cons: design centred on anonymous-record use cases; ordering of fields
is significant in some places; type-level list manipulation API is less
developed than `vinyl`'s. Library has had less polish in recent
maintenance cycles.

**Hand-rolled GADT on `[(Symbol, Type)]`.** A two-constructor GADT —
`RNil :: RegFile '[]` and `RCons :: Proxy s -> r -> RegFile rs ->
RegFile ('(s,r) ': rs)` — with an `Index` GADT type-safely pointing into
it. `OverloadedLabels` via a hand-written `IsLabel s (Index rs r)`
instance.

Pros: zero dependency footprint (only `base`); minimal surface area we
have to understand and explain in error messages; full control over the
shape of the type-level list (we can put `'(Symbol, Type)` pairs there
unambiguously); the synthesis already gestures at this shape and the
direction-C note explicitly recommends it ("hand-rolled GADT-indexed
tuple for v1. `vinyl` is fine if the boilerplate gets bad; not worth
the dependency up front.")
Cons: no existing tooling for record-level operations (concat, project)
— if we need them later, we write them; some construction syntax
boilerplate without TH or quasi-quoter sugar.

| Candidate | Type-level carrier | OverloadedLabels | Dep weight | v1 fit |
|---|---|---|---|---|
| `vinyl` | any kind, our adapter to `[(Symbol, Type)]` | via `rlens` | medium | reasonable alternative |
| `large-records` | record TH | n/a | medium-heavy | wrong shape |
| `extensible` | `[Assoc Symbol Type]` | first-class | medium | reasonable but heavy |
| `superrecord` | `[Symbol := Type]` | first-class | small | acceptable, less polish |
| **hand-rolled GADT** | `[(Symbol, Type)]` | hand-written `IsLabel` | **zero** | **chosen** |


## RegFile and Index — the chosen representation

The choice is the **hand-rolled GADT on `[(Symbol, Type)]`**. Rationale:

- The synthesis already implies this shape; the direction-C note
  explicitly recommends it.
- Zero dependency footprint matters because keiki is a foundation
  library whose first commitment to a record library is hard to retract.
  Picking `vinyl` here would force every downstream user to live inside
  `vinyl`'s naming and tooling ecosystem.
- The User Registration example is **five slots**. The argument for a
  third-party record library is "the boilerplate has gotten bad". With
  five slots, the boilerplate is tolerable.
- A v2 swap to `vinyl` (or `extensible`) is mechanical if the
  ergonomics turn out to bite at scale: `RegFile`, `Index`, `IsLabel`,
  and the `(!)` operator are the only surfaces that depend on the
  representation. Everything else (`Term`, `OutTerm`, `Update`) is
  parametric over `rs :: [(Symbol, Type)]`.

Sketch:

    {-# LANGUAGE DataKinds, GADTs, KindSignatures, PolyKinds, TypeFamilies #-}
    {-# LANGUAGE OverloadedLabels, FlexibleInstances, MultiParamTypeClasses #-}
    {-# LANGUAGE UndecidableInstances, ScopedTypeVariables, TypeApplications #-}

    import Data.Kind (Type)
    import Data.Proxy (Proxy(..))
    import GHC.OverloadedLabels (IsLabel(..))
    import GHC.TypeLits (Symbol, KnownSymbol, sameSymbol)

    -- Slot kind: a label paired with its value type.
    type Slot = (Symbol, Type)

    data RegFile (rs :: [Slot]) where
      RNil  :: RegFile '[]
      RCons :: KnownSymbol s
            => Proxy s -> r -> RegFile rs -> RegFile ('(s, r) ': rs)

    data Index (rs :: [Slot]) (r :: Type) where
      ZIdx :: KnownSymbol s => Index ('(s, r) ': rs) r
      SIdx :: Index rs r -> Index ('(s', r') ': rs) r

The `Index` GADT is the canonical type-safe pointer: `ZIdx` picks the
head, `SIdx` skips. The label is recorded at `ZIdx` so that a future
helper can extract it for error messages, and `KnownSymbol` is required
on the head so the representation is fully reflective.

`OverloadedLabels` is supported by a `HasField`-style typeclass that
walks the type-level list at the type level:

    class HasIndex (s :: Symbol) (rs :: [Slot]) (r :: Type)
                   | s rs -> r where
      indexOf :: Index rs r

    instance {-# OVERLAPPING #-} (KnownSymbol s)
          => HasIndex s ('(s, r) ': rs) r where
      indexOf = ZIdx

    instance {-# OVERLAPPABLE #-} HasIndex s rs r
          => HasIndex s ('(s', r') ': rs) r where
      indexOf = SIdx (indexOf @s @rs @r)

    instance HasIndex s rs r => IsLabel s (Index rs r) where
      fromLabel = indexOf @s @rs @r

The user writes `#email :: Index UserRegRegs Email` and GHC resolves the
`HasIndex "email" UserRegRegs Email` constraint by walking the slot
list. A typo gives an unmistakable
`No instance for HasIndex "emial" UserRegRegs r` error.

Runtime lookup:

    (!) :: RegFile rs -> Index rs r -> r
    RCons _ x _   ! ZIdx     = x
    RCons _ _ rs' ! SIdx i   = rs' ! i

Worked example. A two-slot register file:

    type Demo = '[ '("count", Int), '("name", String) ]

    demo :: RegFile Demo
    demo = RCons (Proxy @"count") 3
         $ RCons (Proxy @"name") "alice"
         $ RNil

    demo ! #count  -- 3 :: Int
    demo ! #name   -- "alice" :: String

If we ever need a friendlier constructor — `r # (count =: 3) # (name =:
"alice")` — that is a pure-syntax helper layered on top; the GADT shape
is what `Term`/`Update` depend on.


## Term, Update, Edge, SymTransducer

`Term rs ci r` is the closed expression language for register reads,
input field reads, literals, and pure combinators. The User Registration
aggregate uses it for things like
`\(StartRegistration d) -> d.email` (read input field) and
`regs ! #email` (read register).

    data Term (rs :: [Slot]) (ci :: Type) (r :: Type) where
      TLit          :: r -> Term rs ci r
      TReg          :: Index rs r -> Term rs ci r
      TInpCtorField :: InCtor ci ifs -> Index ifs r -> Term rs ci r  -- v2 (EP-1)
      TApp1         :: (a -> r)
                    -> Term rs ci a
                    -> Term rs ci r
      TApp2         :: (a -> b -> r)
                    -> Term rs ci a
                    -> Term rs ci b
                    -> Term rs ci r

**EP-1 update (2026-05-01).** The v1 prototype carried a `TInpField ::
(ci -> r) -> Term rs ci r` constructor wrapping an opaque Haskell
function. EP-1 of MasterPlan 2 retired it in favour of
`TInpCtorField`, which reads field `ix` of the input constructor
described by an `InCtor ci ifs` value. The slot list `ifs :: [Slot]`
mirrors `RegFile`'s shape so call sites read `inpStart #email` (an
`OverloadedLabels` `Index`) instead of `inpStart (.email)` (a record
projection). See `docs/research/tinpproj-design.md` for the design
note. With `TInpField` gone, `solveOutput` is purely structural — no
per-edge user-supplied inverse code is needed. The
`Jitsurei.UserRegistration` worked example below is in its v1
form throughout this section; the post-EP-1 source is the
authoritative reference.

`InCtor` is the symmetric input-side analogue of `WireCtor`:

    data InCtor ci (ifs :: [Slot]) where
      InCtor :: (AssembleRegFile ifs, KnownSlotNames ifs)
             => { icName  :: String
                , icMatch :: ci -> Maybe (RegFile ifs)
                , icBuild :: RegFile ifs -> ci
                }
             -> InCtor ci ifs

`Update rs ci` is the copyless update language from synthesis §2:

    data Update (rs :: [Slot]) (ci :: Type) where
      UKeep    :: Update rs ci
      USet     :: Index rs r -> Term rs ci r -> Update rs ci
      UCombine :: Update rs ci -> Update rs ci -> Update rs ci
        -- precondition: distinct targets — enforced by `combine` smart ctor

The "distinct targets" precondition is enforced by a smart constructor:

    -- A list of register slots written to (as their type-erased label
    -- string and slot offset). Used only to reject non-distinct
    -- combines at construction time.
    targets :: Update rs ci -> [Int]
    targets UKeep            = []
    targets (USet ix _)      = [indexInt ix]
    targets (UCombine a b)   = targets a ++ targets b

    combine :: Update rs ci -> Update rs ci
            -> Either String (Update rs ci)
    combine a b
      | not (null overlap) =
          Left ("combine: overlapping targets at indices " ++ show overlap)
      | otherwise          = Right (UCombine a b)
      where
        overlap = [t | t <- targets a, t `elem` targets b]

    indexInt :: Index rs r -> Int
    indexInt ZIdx     = 0
    indexInt (SIdx i) = 1 + indexInt i

The `Either` return is intentional. v1 may also expose a
`combineUnsafe :: Update rs ci -> Update rs ci -> Update rs ci` that
calls `error` on overlap, for convenience inside `userReg` definitions
that the model author is confident about; the prototype's smoke test
property-checks that no built `userReg` triggers it.

Edges and the transducer are reproduced verbatim from synthesis §2:

    data Edge phi rs ci co s = Edge
      { guard  :: phi
      , update :: Update rs ci
      , output :: Maybe (OutTerm rs ci co)
      , target :: s
      }

    data SymTransducer phi rs s ci co = SymTransducer
      { edgesOut    :: s -> [Edge phi rs ci co s]
      , initial     :: s
      , initialRegs :: RegFile rs
      , isFinal     :: s -> Bool
      }

The projection signatures the prototype must implement:

    delta :: BoolAlg phi (RegFile rs, ci)
          => SymTransducer phi rs s ci co
          -> s -> RegFile rs -> ci -> Maybe (s, RegFile rs)

    omega :: BoolAlg phi (RegFile rs, ci)
          => SymTransducer phi rs s ci co
          -> s -> RegFile rs -> ci -> Maybe co

    runUpdate :: Update rs ci -> RegFile rs -> ci -> RegFile rs

    evalTerm :: Term rs ci r -> RegFile rs -> ci -> r

    evalOut  :: OutTerm rs ci co -> RegFile rs -> ci -> co

    models   :: BoolAlg phi a => phi -> a -> Bool


## OutTerm and the inversion contract

`OutTerm rs ci co` is the hard one because `solveOutput` must invert
it. The synthesis note's User Registration aggregate uses `OutTerm` to
produce events like
`RegistrationStarted (RegistrationStartedData email confirmCode at)`
where each field of the payload is a `Term` over `(rs, ci)`.

Two leading shapes were considered:

**(a) Structural `Pack`-based.** An `OutTerm` is built by tagging a
wire-type constructor and supplying a list of `Term`s for each payload
field. `solveOutput` walks the AST: pattern-match on the wire-type tag
to find the matching edge, then for each field whose `Term` is `TInp`
or `TInpField`, read the corresponding field out of the observed `co`
value to recover the input. The shape is essentially a typed
dictionary-pass.

**(b) Generic-driven.** Use `GHC.Generics` to derive the field structure
of the output sum type and require the user to declare the output as a
`Generic` type plus a `keiki`-specific class instance (think
`OutTermable co`) that maps each field to a `Term`.

For v1, **shape (a) — structural Pack — is chosen**. Rationale:

- Shape (a) gives `solveOutput` a concrete AST node to walk: it sees
  `OPack ConstructorTag [field0Term, field1Term, ...]`, can pattern-match
  the observed value `co` against the same constructor tag, can extract
  field values, and can recurse into each field's `Term` to recover the
  parts of `ci` (and verify constants and register reads).
- Shape (a) has no `Generic` machinery to debug. The User Registration
  example fits in five constructors; manually written `Pack` calls are
  fine.
- Shape (b) is a v2 nice-to-have: once we have an SBV-backed `BoolAlg`,
  having `Generic` derive the output structure is a small win at the
  cost of a heavier dependency surface and harder error messages.

Sketch:

    -- A wire-type tag identifies one constructor of the user's `co` sum.
    -- The user supplies it as a Haskell value with field-extracting
    -- accessors so the prototype can pattern-match observed `co` values.
    data WireCtor co fields = WireCtor
      { wcName     :: String                   -- for diagnostics
      , wcMatch    :: co -> Maybe fields       -- pattern-match
      , wcBuild    :: fields -> co             -- inverse: build the co
      }

    -- HList of Terms for the constructor's fields.
    data OutFields rs ci fs where
      OFNil  :: OutFields rs ci ()
      OFCons :: Term rs ci f
             -> OutFields rs ci fs
             -> OutFields rs ci (f, fs)

    data OutTerm (rs :: [Slot]) (ci :: Type) (co :: Type) where
      OPack  :: WireCtor co fields
             -> OutFields rs ci fields
             -> OutTerm rs ci co
      OFn    :: (RegFile rs -> ci -> co)        -- v1 escape hatch
             -> OutTerm rs ci co

`OFn` is the v1 escape hatch corresponding to the synthesis note's
pseudosyntactic `mkOut`. v2 replaces it: every `OutTerm` constructed
through `mkOut` becomes a structural `OPack`. `solveOutput` cannot
invert `OFn`, so an edge whose `output` is `OFn`-constructed is
automatically flagged by the hidden-input check as opaque-output. This
is the same trade-off as `TInpField`: v1 gets a working escape hatch, v2
removes it.

How `solveOutput` walks `OPack`. Given an `OPack ctor fields` and an
observed value `co_obs`:

1. Run `wcMatch ctor co_obs`. If `Nothing`, this edge does not match;
   move on.
2. If `Just fields_obs`, walk `fields` and `fields_obs` together. For
   each `Term`/observed-value pair:
   - `TLit l` against observed `v`: check `l == v`. If not, this edge is
     not the right match; back off.
   - `TReg ix` against observed `v`: check `regs ! ix == v`. If not,
     back off.
   - `TInpField f` against observed `v`: cannot invert (opaque function);
     register the edge as hidden-input-compromised at build time.
   - `TApp1 f t` / `TApp2 f a b`: cannot invert in general; same
     hidden-input flag at build time.
3. If every field walk records a determined-input contribution, assemble
   the recovered `ci` from those contributions and return `Just ci`.

The build-time hidden-input check therefore reduces to: *"does the
`OutTerm`'s field walk leave any part of `ci` unrecovered, when `ci` is
read by the same edge's `update` or `guard`?"* If yes, warn or refuse
to derive `apply`. This is the synthesis §4 walkthrough's discovery,
made operational.

For v1, the user constructs `WireCtor`s by hand. We can ship a small
`mkWireCtor` helper that takes the constructor name and three
hand-written functions; or, layered on top, a TH or `Generic` helper
that generates them from a sum-type declaration. The TH helper is a
v1.5 nice-to-have; for the smoke test, hand-written `WireCtor`s for
each `UserEvent` constructor are tolerable.


## Predicate carrier (HsPred)

The v1 predicate carrier is a first-class AST. The decision-driver is
the User Registration aggregate's actual edges:

- `matchCmd \(StartRegistration _) -> True` — pattern-match on the
  command constructor.
- `\(regs, ConfirmAccount d) -> d.confirmCode == regs ! #confirmCode` —
  equality of an input field and a register read.
- Some edges use trivial `top` guards (the `Continue` edge in
  `Registering`).

The constructor set:

    data HsPred (rs :: [Slot]) (ci :: Type) where
      PTop    :: HsPred rs ci
      PBot    :: HsPred rs ci
      PAnd    :: HsPred rs ci -> HsPred rs ci -> HsPred rs ci
      POr     :: HsPred rs ci -> HsPred rs ci -> HsPred rs ci
      PNot    :: HsPred rs ci -> HsPred rs ci
      PEq     :: Eq r
              => Term rs ci r -> Term rs ci r -> HsPred rs ci
      PMatchC :: (ci -> Bool) -> HsPred rs ci   -- v1 escape hatch

`PEq` covers `d.confirmCode == regs ! #confirmCode` cleanly: build a
`PEq (TInpField (\(ConfirmAccount d) -> d.confirmCode))
     (TReg #confirmCode)`. Both sides are `Term rs ci r`.

`PMatchC` is the escape hatch for `matchCmd \(StartRegistration _) ->
True`-style guards. v2 replaces it with a structural pattern AST
(`PCtor :: ConstructorName -> HsPred rs ci`), but for v1 the opaque
function is the pragmatic choice.

`BoolAlg HsPred` instance signature:

    instance BoolAlg (HsPred rs ci) (RegFile rs, ci) where
      top                = PTop
      bot                = PBot
      conj p q           = PAnd p q
      disj p q           = POr p q
      neg p              = PNot p
      models p (regs,ci) = evalPred p regs ci
      sat _              = Nothing   -- v1: no symbolic sat
      isBot PBot         = True
      isBot _            = False

    evalPred :: HsPred rs ci -> RegFile rs -> ci -> Bool
    evalPred PTop          _    _  = True
    evalPred PBot          _    _  = False
    evalPred (PAnd p q)    r    c  = evalPred p r c && evalPred q r c
    evalPred (POr  p q)    r    c  = evalPred p r c || evalPred q r c
    evalPred (PNot p)      r    c  = not (evalPred p r c)
    evalPred (PEq a b)     r    c  = evalTerm a r c == evalTerm b r c
    evalPred (PMatchC f)   _    c  = f c

`sat` is `Nothing` in v1 because there is no symbolic solver; the v1
single-valuedness check uses Hedgehog generators to produce witnesses.
This matches synthesis §7's stated v1 plan and is documented as a known
limitation.

**v2 update (EP-2 of MasterPlan 2; landed 2026-05-01).** The
v1 `BoolAlg HsPred` instance shown above stays as-is for back-compat,
but `Keiki.Symbolic` now exports a `newtype SymPred rs ci = SymPred
(HsPred rs ci)` whose `BoolAlg (SymPred rs ci) (RegFile rs, ci)`
instance routes `sat` and `isBot` to z3 via SBV. Calling `isBot
(SymPred (PEq (TLit 5) (TLit 6)))` returns `True` (proved
unsatisfiable); calling `isBot (SymPred (PAnd (PInCtor inCtorConfirm)
(PInCtor inCtorResend)))` returns `True` (constructor mutual
exclusion, proved). The class-`sat` returns
`Just (placeholder, placeholder)` on satisfiable predicates — the
placeholder lets the typeclass shape stay unchanged; concrete witness
extraction is a future `symSatExt` paired with hand-written extractors.
A new `PInCtor :: InCtor ci ifs -> HsPred rs ci` constructor (and
`matchInCtor` helper) was added to make constructor-mutex queries
decidable; the v1 `PMatchC` escape hatch stays for back-compat. See
`docs/research/sbv-boolalg-design.md` for the full v2 design record.


## Ergonomic helpers

Each helper has a precise type signature so that a reader of the User
Registration transcription below sees only constructors and helpers
defined in this note.

    -- v1 escape-hatch guard: opaque function on `ci`.
    matchCmd :: (ci -> Bool) -> HsPred rs ci
    matchCmd = PMatchC

    -- v1 escape-hatch output: opaque function on `(regs, ci)`.
    -- v2 fixes this with structural Pack.
    mkOut    :: (RegFile rs -> ci -> co) -> OutTerm rs ci co
    mkOut    = OFn

    -- Read a register slot into a Term.
    proj     :: Index rs r -> Term rs ci r
    proj     = TReg

    -- Structural input projection (v2; EP-1). Replaces the v1
    -- `inp :: (ci -> r) -> Term rs ci r` opaque helper.
    inpCtor  :: InCtor ci ifs -> Index ifs r -> Term rs ci r
    inpCtor  = TInpCtorField

    -- Lit a constant Term.
    lit      :: r -> Term rs ci r
    lit      = TLit

    -- Runtime register lookup. Already defined above.
    (!)      :: RegFile rs -> Index rs r -> r

    -- Smart constructor for combine; returns `Either String` so that
    -- overlapping-target errors are surfaced explicitly. There is also
    -- an `unsafeCombine` infix helper for cases where the author is
    -- confident, used inside the User Registration transcription.
    combine  :: Update rs ci -> Update rs ci
             -> Either String (Update rs ci)

    unsafeCombine :: Update rs ci -> Update rs ci -> Update rs ci

    -- Equality predicate sugar.
    (.==) :: Eq r => Term rs ci r -> Term rs ci r -> HsPred rs ci
    (.==) = PEq

    -- Pack-output construction (structural form).
    pack :: WireCtor co fields
         -> OutFields rs ci fields
         -> OutTerm rs ci co
    pack = OPack

The helpers in v1 vs stable (post-EP-1):

- **v1-only / pending retirement:** `matchCmd` (collapses to
  `PMatchC`), `mkOut` (collapses to `OFn`).
- **Retired in EP-1:** `inp` is gone — replaced by `inpCtor` plus the
  per-constructor `InCtor` values that the user defines once. The
  `OPack` hand-written inverse field is gone — `solveOutput` walks
  structurally.
- **Stable across v1 and v2:** `proj`, `lit`, `(!)`, `combine`,
  `unsafeCombine`, `(.==)`, `pack` (signature now takes an `InCtor`
  first argument).

Every use of `matchCmd` or `mkOut` in a `userReg`-style declaration
remains a place a future MasterPlan will ask the user to rewrite.


## Worked example: User Registration

The User Registration aggregate from synthesis §4, transcribed in the
DSL defined above. **No pseudosyntax.** Every constructor and helper is
defined in this note.

The domain types (`Vertex`, `UserRegRegs`, `UserCmd`, `UserEvent`) are
copied verbatim from synthesis §4 with the addition of the `Continue`
constructor in `UserCmd` (an internal command for the
`Registering -> RequiresConfirmation` ε-edge — synthesis §4 mentions it
in pseudosyntax as `\Continue -> True`).

    data Vertex
      = PotentialCustomer
      | Registering
      | RequiresConfirmation
      | Confirmed
      | Deleted
      deriving (Eq, Show, Enum, Bounded)

    type UserRegRegs =
      '[ '("email",        Email)
       , '("confirmCode",  ConfirmationCode)
       , '("registeredAt", UTCTime)
       , '("confirmedAt",  UTCTime)
       , '("deletedAt",    UTCTime)
       ]

    -- Synthesis §4's UserCmd plus the internal Continue command used for
    -- the Registering ε-edge.
    data UserCmd
      = StartRegistration  StartRegistrationData
      | ConfirmAccount     ConfirmAccountData
      | ResendConfirmation ResendConfirmationData
      | FulfillGDPRRequest FulfillGDPRRequestData
      | Continue

    -- (Command and event payload records identical to synthesis §4;
    -- not repeated here.)

The transducer:

    userReg :: SymTransducer
                 (HsPred UserRegRegs UserCmd)
                 UserRegRegs
                 Vertex
                 UserCmd
                 UserEvent
    userReg = SymTransducer
      { edgesOut = \case

          PotentialCustomer ->
            [ Edge
                { guard  = matchCmd (\case StartRegistration{} -> True
                                           _                   -> False)
                , update =
                    USet (#email :: Index UserRegRegs Email)
                         (inp (\case StartRegistration d -> email d
                                     _                   -> error "guard"))
                    `unsafeCombine`
                    USet (#confirmCode :: Index UserRegRegs ConfirmationCode)
                         (inp (\case StartRegistration d -> confirmCode d
                                     _                   -> error "guard"))
                    `unsafeCombine`
                    USet (#registeredAt :: Index UserRegRegs UTCTime)
                         (inp (\case StartRegistration d -> at d
                                     _                   -> error "guard"))
                , output = Just (mkOut (\_regs ci ->
                    case ci of
                      StartRegistration d ->
                        RegistrationStarted (RegistrationStartedData
                          { email       = email d
                          , confirmCode = confirmCode d
                          , at          = at d })
                      _ -> error "guard"))
                , target = Registering
                }
            ]

          Registering ->
            [ Edge
                { guard  = matchCmd (\case Continue -> True; _ -> False)
                , update = UKeep
                , output = Just (mkOut (\regs _ ->
                    ConfirmationEmailSent (ConfirmationEmailSentData
                      { email = regs ! #email })))
                , target = RequiresConfirmation
                }
            ]

          RequiresConfirmation ->
            [ -- right code: confirm
              Edge
                { guard  =
                    inp (\case ConfirmAccount d -> confirmCode d
                               _                -> error "guard")
                    .== proj (#confirmCode :: Index UserRegRegs ConfirmationCode)
                , update =
                    USet (#confirmedAt :: Index UserRegRegs UTCTime)
                         (inp (\case ConfirmAccount d -> at d
                                     _                -> error "guard"))
                , output = Just (mkOut (\regs ci ->
                    case ci of
                      ConfirmAccount d ->
                        AccountConfirmed (AccountConfirmedData
                          { email = regs ! #email
                          , at    = at d })
                      _ -> error "guard"))
                , target = Confirmed
                }
              -- resend: rotate the code (uses an external freshCode IO,
              -- modelled here as a literal generated by the boundary).
            , Edge
                { guard  = matchCmd (\case ResendConfirmation{} -> True
                                           _                    -> False)
                , update =
                    USet (#confirmCode :: Index UserRegRegs ConfirmationCode)
                         (inp (\case ResendConfirmation _ -> freshCodePure
                                     _                    -> error "guard"))
                    `unsafeCombine`
                    USet (#registeredAt :: Index UserRegRegs UTCTime)
                         (inp (\case ResendConfirmation d -> at d
                                     _                    -> error "guard"))
                , output = Just (mkOut (\regs ci ->
                    case ci of
                      ResendConfirmation _ ->
                        ConfirmationResent (ConfirmationResentData
                          { email       = regs ! #email
                          , confirmCode = regs ! #confirmCode
                          , at          = regs ! #registeredAt })
                      _ -> error "guard"))
                , target = RequiresConfirmation
                }
              -- GDPR before confirmation: silent ε-edge.
            , Edge
                { guard  = matchCmd (\case FulfillGDPRRequest{} -> True
                                           _                    -> False)
                , update =
                    USet (#deletedAt :: Index UserRegRegs UTCTime)
                         (inp (\case FulfillGDPRRequest d -> at d
                                     _                    -> error "guard"))
                , output = Nothing
                , target = Deleted
                }
            ]

          Confirmed ->
            [ Edge
                { guard  = matchCmd (\case FulfillGDPRRequest{} -> True
                                           _                    -> False)
                , update =
                    USet (#deletedAt :: Index UserRegRegs UTCTime)
                         (inp (\case FulfillGDPRRequest d -> at d
                                     _                    -> error "guard"))
                , output = Just (mkOut (\regs ci ->
                    case ci of
                      FulfillGDPRRequest d ->
                        AccountDeleted (AccountDeletedData
                          { email = regs ! #email
                          , at    = at d })
                      _ -> error "guard"))
                , target = Deleted
                }
            ]

          Deleted -> []

      , initial     = PotentialCustomer
      , initialRegs = emptyRegs
      , isFinal     = \case Deleted -> True
                            _       -> False
      }

    emptyRegs :: RegFile UserRegRegs
    emptyRegs =
      RCons (Proxy @"email")        (error "uninit: email")
      $ RCons (Proxy @"confirmCode")  (error "uninit: confirmCode")
      $ RCons (Proxy @"registeredAt") (error "uninit: registeredAt")
      $ RCons (Proxy @"confirmedAt")  (error "uninit: confirmedAt")
      $ RCons (Proxy @"deletedAt")    (error "uninit: deletedAt")
      $ RNil

    freshCodePure :: ConfirmationCode
    freshCodePure = error "boundary supplies the fresh code; this is a stub"

Two structural divergences from synthesis §4 are visible in the
transcription:

- **Total `inp` projections.** The synthesis writes
  `\(StartRegistration d) -> d.email` as a partial pattern-match. In v1
  the `inp` callback must be total over `ci :: UserCmd`, so the
  transcription pads with `_ -> error "guard"`. The runtime guarantee
  that those branches are unreachable comes from the edge's `guard`,
  not the `Term`. v2's structural input projection (`TInpProj`) makes
  this honest. **This is IP-1.**
- **Structural `mkOut` is opaque in v1.** Every `output` in the
  transcription is `mkOut` (i.e. `OFn`), so `solveOutput` cannot invert
  any of them. The hidden-input check therefore flags **all** of them
  as opaque. The smoke test in EP-4 must demonstrate the warning fires
  on the existing schema; switching to structural `OPack` for one
  representative edge (probably `RegistrationStarted`) should remove
  the warning for that edge and prove the check has bite. **This is
  IP-2.**


## Ergonomic verdict

The transcription compiles in the writer's head, fits within the
synthesis note's intended shape, and uses only constructors defined in
this note. **The verdict is "painful but workable" for v1.**

What is tolerable:

- The slot-list type alias (`UserRegRegs`) reads cleanly and matches
  the synthesis §4 declaration verbatim.
- `OverloadedLabels` syntax `#email` / `#confirmCode` works at the
  call site as long as the type annotation `:: Index UserRegRegs T` is
  spelled at one of the use sites per slot. (Bidirectional inference
  resolves it for `proj`, `(!)`, and `USet`.)
- The Boolean-algebra constructors (`PEq` via `(.==)`, `PMatchC` via
  `matchCmd`) cover every guard in the synthesis aggregate.
- `unsafeCombine` chains for multi-slot updates read like a small
  pipeline, no worse than the synthesis pseudosyntax.

What is painful:

- **The total-callback boilerplate in `inp`.** Every `inp (\case
  StartRegistration d -> field d; _ -> error "guard")` is six lines
  where the synthesis used a one-liner. Five of those lines are
  noise. The v2 fix is structural input projection (`TInpProj :: Lens'
  ci field -> Term rs ci field` or a `Generic`-derived selector); it
  also makes the hidden-input check work properly. This is the single
  largest ergonomic pain point and v2's highest-priority cleanup.
- **`mkOut` is opaque, so the hidden-input check will report every
  edge in the example.** The check is operational only after at least
  one structural `OPack` is shipped. EP-4's smoke test must include a
  structural `OPack` for at least one event (recommendation:
  `RegistrationStarted`) so that the check fires on the unfixed
  `AccountConfirmed` schema (synthesis §4's "step 4 — ⚠"). Without
  that, the synthesis note's headline win — "the check has bite" —
  cannot be demonstrated.
- **Unreachable-branch error stubs.** Every `\case ... _ -> error
  "guard"` is correct (the guard guarantees the branch is unreachable)
  but feels hostile to a reader new to the formalism. v2's structural
  input projection eliminates this entirely.

What is not blocking:

- The lack of pretty record-construction syntax for `RegFile`. Five
  `RCons (Proxy @"...") ...` lines in `emptyRegs` is fine; if it grew
  past ten slots a TH helper would pay for itself, but at five we ship.
- The hand-written `WireCtor` boilerplate for v2's structural `OPack`.
  EP-4 only needs one `WireCtor`; subsequent events can be added
  incrementally as v1.5 work.

The verdict is **"painful but workable"**, not "blocking". The pain is
concentrated in the v1 escape hatches (`mkOut`, `inp`, `matchCmd`),
which is the expected price of shipping without SMT or `Generics`
plumbing. The v2 path that retires those three escape hatches in
sequence is the natural next deliverable after the EP-4 smoke test.


## Prototype Implementation Checklist

This is the hand-off contract for ExecPlan 4. Every item below must
exist in the prototype before the User Registration smoke test can run.

**Types and kinds**

- `type Slot = (Symbol, Type)`
- `data RegFile (rs :: [Slot])` — constructors: `RNil`, `RCons`
- `data Index (rs :: [Slot]) (r :: Type)` — constructors: `ZIdx`, `SIdx`
- `data Term (rs :: [Slot]) (ci :: Type) (r :: Type)` — constructors:
  `TLit`, `TReg`, `TInpCtorField` (v2; EP-1), `TApp1`, `TApp2`
- `data InCtor ci (ifs :: [Slot])` (v2; EP-1) — record `InCtor` with
  fields `icName`, `icMatch`, `icBuild`; data constructor carries
  `(AssembleRegFile ifs, KnownSlotNames ifs)` constraints
- `data Update (rs :: [Slot]) (ci :: Type)` — constructors: `UKeep`,
  `USet`, `UCombine`
- `data WireCtor co fields` — record with `wcName`, `wcMatch`, `wcBuild`
- `data OutFields (rs :: [Slot]) (ci :: Type) fs` — constructors:
  `OFNil`, `OFCons`
- `data OutTerm (rs :: [Slot]) (ci :: Type) (co :: Type)` —
  constructors: `OPack`, `OFn`
- `data HsPred (rs :: [Slot]) (ci :: Type)` — constructors: `PTop`,
  `PBot`, `PAnd`, `POr`, `PNot`, `PEq`, `PMatchC`
- `data Edge phi rs ci co s` — record with `guard`, `update`, `output`,
  `target`
- `data SymTransducer phi rs s ci co` — record with `edgesOut`,
  `initial`, `initialRegs`, `isFinal`

**Type classes and instances**

- `class BoolAlg phi a | phi -> a` — methods `top`, `bot`, `conj`,
  `disj`, `neg`, `models`, `sat`, `isBot`
- `instance BoolAlg (HsPred rs ci) (RegFile rs, ci)` — `sat` returns
  `Nothing` in v1
- `class HasIndex (s :: Symbol) (rs :: [Slot]) (r :: Type) | s rs -> r`
  with method `indexOf`, plus the two recursive instances
- `instance HasIndex s rs r => IsLabel s (Index rs r)`

**Helpers (all top-level, exported)**

- `matchCmd :: (ci -> Bool) -> HsPred rs ci`
- `mkOut    :: (RegFile rs -> ci -> co) -> OutTerm rs ci co`
- `proj     :: Index rs r -> Term rs ci r`
- `inpCtor  :: InCtor ci ifs -> Index ifs r -> Term rs ci r` (v2; EP-1)
- `lit      :: r -> Term rs ci r`
- `(!)      :: RegFile rs -> Index rs r -> r`
- `(.==)    :: Eq r => Term rs ci r -> Term rs ci r -> HsPred rs ci`
- `combine  :: Update rs ci -> Update rs ci -> Either String (Update rs ci)`
- `unsafeCombine :: Update rs ci -> Update rs ci -> Update rs ci`
- `pack     :: InCtor ci ifs -> WireCtor co fields -> OutFields rs ci fields -> OutTerm rs ci co` (v2 signature; EP-1)

**Evaluators**

- `evalTerm :: Term rs ci r -> RegFile rs -> ci -> r`
- `evalOut  :: OutTerm rs ci co -> RegFile rs -> ci -> co`
- `evalPred :: HsPred rs ci -> RegFile rs -> ci -> Bool`
- `runUpdate :: Update rs ci -> RegFile rs -> ci -> RegFile rs`
- `delta    :: BoolAlg phi (RegFile rs, ci) => SymTransducer phi rs s ci co -> s -> RegFile rs -> ci -> Maybe (s, RegFile rs)`
- `omega    :: BoolAlg phi (RegFile rs, ci) => SymTransducer phi rs s ci co -> s -> RegFile rs -> ci -> Maybe co`

**Build-time analyses**

- `solveOutput :: OutTerm rs ci co -> RegFile rs -> co -> Maybe ci` —
  walks `OPack`'s `OutFields` against the `InCtor` named on it,
  gathering `(Index, value)` pairs and assembling them into a
  `RegFile ifs` that is passed to `icBuild`. Returns `Nothing` for
  `OFn`, for unmatched wire constructors, for opaque `TApp` reads
  inside `OutFields`, and for `OutFields` walks that leave any slot
  of the `InCtor` unvisited.
- The hidden-input check (`checkHiddenInputs`) traverses every edge
  and reports:
  - `OFn` outputs as "opaque (no inverse)".
  - ε-edges whose `update` reaches into `ci` (silent on the wire).
  - `OPack` outputs whose `OutFields` does not visit every slot of
    the `InCtor` named on the `OPack`. The warning names the
    `InCtor` and the missing slot.

**Smoke-test scaffolding (EP-4 owns the implementation; this note
defines the contract)**

- The User Registration aggregate, written in the DSL exactly as
  transcribed above.
- `reconstitute :: SymTransducer (HsPred UserRegRegs UserCmd) UserRegRegs Vertex UserCmd UserEvent -> [UserEvent] -> Maybe (Vertex, RegFile UserRegRegs)`.
- A property test (Hedgehog) generating event streams and checking that
  `reconstitute` produces the same `(Vertex, RegFile)` as folding
  `delta` over a synthesised command stream.
- A demonstration that the hidden-input check fires on at least one
  structurally-complete edge (i.e., one whose `output` is `OPack` rather
  than `OFn`) when the schema has the synthesis §4 step-4
  `confirmCode`-not-in-event problem.

**v1 surfaces — retired in EP-1 of MasterPlan 2 (2026-05-01)**

- ~~`TInpField`~~ — replaced by `TInpCtorField` + `InCtor`. See
  `docs/research/tinpproj-design.md`.
- ~~`OPack`'s hand-written inverse field~~ — replaced by mechanical
  inversion against `OPack`'s `InCtor`.
- ~~`OFn` / `mkOut`~~ — retired by MP-6 EP-16; `OPack` is the only
  output-term constructor.
- ~~`PMatchC` / `matchCmd`~~ — retired by MP-6 EP-17; structural
  guards (`PInCtor` / `matchInCtor`) cover every aggregate.
- ~~`unsafeCombine`~~ — retired by MP-6 EP-18; `Update` carries a
  type-level `(w :: [Symbol])` index of written slot names, and the
  smart `combine` demands `Disjoint w1 w2`. See MP-6's Outcomes
  section
  (`docs/masterplans/6-retire-remaining-v1-escape-hatches-in-pure-core-ofn-pmatchc-unsafecombine-static-check.md`)
  for the full retirement record.

The prototype is judged complete (against this design note) when every
item above exists, the User Registration smoke test runs end-to-end,
and the hidden-input check produces an actionable warning on at least
one structural-output edge in the User Registration aggregate.


## Authoring DSL on top of the AST

The shapes settled in this note describe the *AST* of a
`SymTransducer`. A separate authoring DSL — `Keiki.Builder`,
designed in `docs/research/edge-builder-dsl-shape.md` (EP-15 M1)
and shipped in `src/Keiki/Builder.hs` (EP-15 M3) — sits on top
of that AST and is the recommended way for users to write
transducers. The builder is purely additive: it consumes the AST
constructors declared here and produces values of the same
`SymTransducer` type, so every downstream module
(`Keiki.Acceptor`, `Keiki.Composition`, `Keiki.Decider`,
`Keiki.Symbolic`, the example specs) keeps working unchanged. The
AST remains the load-bearing source of truth for the formalism;
users who need full expressive control drop down to it.

The builder note settles seven shape questions (carrier monad,
`(.=)` shape, `emit` shape, vertex grouping, distinct-targets
enforcement, `goto` and termination, module placement) and
contains a side-by-side comparison of `EmailDelivery` in the AST
form and the builder form. See that note for the operator surface;
this note remains the contract for the underlying AST.

A six-line excerpt of the builder surface, drawn from
`jitsurei/src/Jitsurei/EmailDelivery.hs` post-EP-15 M4 migration:

    B.from EmailPending do
      B.onCmd inCtorSendEmail $ \d -> B.do
        B.slot @"emailRecipient" .= d.recipient
        B.slot @"emailSubject"   .= d.subject
        B.slot @"emailSentAt"    .= d.at
        B.emit inCtorSendEmail wireEmailSent
          (OFCons d.recipient (OFCons d.subject (OFCons d.at OFNil)))
        B.goto EmailSentVertex

The same edge written against the bare AST is 19 lines of nested
`Edge { … }` record literal, infix `combine` chain, slot-name-tagged
`USet` annotations, and `pack`/`OFCons` boilerplate (see the AST-form
sibling `emailDeliveryAST` in the same module for the side-by-side).
See the `Keiki.Builder` haddock for the full operator surface and
the misuse-diagnostic catalog (duplicate `(.=)`, missing/duplicate
`goto`, unrecoverable input fields).
