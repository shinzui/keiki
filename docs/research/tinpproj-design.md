# TInpProj design — structural input projection (EP-1 of MasterPlan 2)

This note pins the v2 retirement of the v1 `TInpField` escape hatch and
the v1 hand-written `OPack` inverse field. It is the hand-off contract
for `docs/plans/5-replace-tinpfield-with-structural-input-projection-tinpproj.md`'s
M2-M7 milestones.

The goal: `solveOutput` walks an `OPack`'s `OutFields` mechanically and
recovers the input `ci` from the observed output `co`, with no per-edge
user-supplied inverse function. Achieving that goal requires changing
the `Term` constructor that reads the input symbol from one that wraps
an opaque Haskell function (`TInpField :: (ci -> r) -> Term rs ci r`) to
one that carries enough syntactic information for `solveOutput` to
identify which constructor of `ci` it expects and which field of that
constructor it projects. This note picks the shape that change takes.


## Goal in one paragraph

The synthesis claim of *mechanical apply derivation* (synthesis §4 plus
the direction-C note §5) holds when every input read in an edge's output
expression carries enough syntactic information that the inverse can be
walked structurally. The v1 prototype's `TInpField (ci -> r)` does not;
the function is opaque. The v1 fix added a third field to `OPack`
carrying a user-supplied `RegFile rs -> co -> Maybe ci`. This works but
exists outside the type system: nothing forces consistency between the
`OutFields` (forward direction) and the inverse (backward direction).
EP-1 retires the escape hatch so the synthesis claim holds at v1's
typechecking level.


## Survey: four candidate shapes

Four candidates fell out of the v1 DSL note's "v2 retirement" hint. The
note recommended hand-rolled `InCtor` mirroring `WireCtor`; this survey
confirms.

### Candidate 1 — Lens-based: `TInpProj :: Lens' ci r -> Term rs ci r`

`Lens'` (from `ekmett/lens`) is `(Functor f) => (r -> f r) -> ci -> f
ci`. It requires totality: every `ci` value has a `r`-typed focus. The
`ci` in keiki is typically a sum type (`UserCmd` has five
constructors) and per-field projections are defined only on a single
constructor — necessarily partial. `Prism' ci r` and `AffineTraversal' ci
r` capture partiality, but they do not give a *unique* field; a prism on
a constructor yields the whole constructor payload, not a single field.
Composing prism-then-lens (constructor + field) typechecks but loses the
constructor identity at the `solveOutput` walk site.

**Rejected.** A lens can express "this field of this constructor" only
by composition, and the composition is a function — opaque, like
`TInpField`. The retirement target is opacity itself; replacing one
opaque function with another would not advance the synthesis claim.


### Candidate 2 — `HasField` / `GHC.Records.HasField`

`HasField "field" ci r` (from `GHC.Records`) is a record-projection
typeclass. GHC derives instances for every named record field. For
record types this gives `getField :: ci -> r` cleanly.

**Rejected.** Same constructor-vs-record problem as candidate 1.
`UserCmd` is a sum-of-records, not a record itself; `HasField "email"
UserCmd Email` has no instance because `email` belongs to
`StartRegistrationData` (a payload of one constructor of `UserCmd`),
not to `UserCmd` directly. Working around this with newtype wrappers or
constructor-tagged fields is the work the user already does in v1's
`inpStart`-style helpers; making the structural shape do that work
defeats the whole point of mechanizing it.


### Candidate 3 — Hand-rolled `InCtor` mirroring `WireCtor` (recommended)

The `WireCtor` type already exists on the output side
(`src/Keiki/Core.hs:200-204`):

    data WireCtor co fields = WireCtor
      { wcName  :: String
      , wcMatch :: co -> Maybe fields
      , wcBuild :: fields -> co
      }

The symmetric input-side type:

    data InCtor ci (ifs :: [Slot]) = InCtor
      { icName  :: String
      , icMatch :: ci -> Maybe (RegFile ifs)
      , icBuild :: RegFile ifs -> ci
      }

The `Term` constructor:

    TInpCtorField :: InCtor ci ifs -> Index ifs r -> Term rs ci r

The user's per-constructor input helpers become:

    inpStart   :: Index '[ '("email", Email), '("confirmCode", ConfirmationCode), '("at", UTCTime) ] r
               -> Term UserRegRegs UserCmd r
    inpStart   = TInpCtorField inCtorStart

with the `inCtorStart` value defined once near the wire constructors:

    inCtorStart :: InCtor UserCmd '[ '("email", Email)
                                   , '("confirmCode", ConfirmationCode)
                                   , '("at", UTCTime)
                                   ]
    inCtorStart = InCtor
      { icName  = "StartRegistration"
      , icMatch = \case
          StartRegistration d -> Just (RCons (Proxy @"email") d.email
                                      $ RCons (Proxy @"confirmCode") d.confirmCode
                                      $ RCons (Proxy @"at") d.at
                                      $ RNil)
          _ -> Nothing
      , icBuild = \(RCons _ e (RCons _ cc (RCons _ a RNil))) ->
                    StartRegistration (StartRegistrationData e cc a)
      }

**Pros.** Symmetric with the existing output side (a contributor who
already understands `WireCtor` understands `InCtor` instantly). Reuses
`RegFile`/`Index`/`IsLabel` so `OverloadedLabels` syntax (`#email`,
`#confirmCode`, `#at`) works unchanged. Zero new dependencies. The
mechanical inversion algorithm (§next) is short and structural.

**Cons.** One `InCtor` per command constructor is more user-facing
boilerplate than `inpFoo (.field)`. This is the same tradeoff
`WireCtor` already made on the output side; the v1 verdict was that
the symmetric boilerplate is tolerable.

**Recommended.** This is the shape the rest of the note assumes.


### Candidate 4 — `GHC.Generics`-derived

`GHC.Generics` enumerates constructors and fields automatically; a
suitably-typed combinator could derive the per-constructor `InCtor`
values without user-written `icMatch`/`icBuild`. The user writes only
`deriving Generic` on `UserCmd` plus its constructor payloads.

**Rejected (for now).** Heavier machinery; harder error messages on
malformed payloads (the GHC.Generics `Rep` type errors are
notoriously cryptic). The savings (one `InCtor` value per command
constructor) is small in absolute terms (four values for the User
Registration aggregate). The same one-`WireCtor`-per-event boilerplate
already exists on the output side and was judged tolerable; the
symmetric input boilerplate is also tolerable. A future plan can add a
Generic-derived `InCtor` constructor as an opt-in convenience without
disturbing the structural shape we adopt here.


## Chosen shape

The chosen shape, formally:

    -- The slot-list of an InCtor's fields. Same kind as RegFile's slot
    -- list, so the same Index/IsLabel/HasIndex machinery applies.
    --   ifs :: [Slot]   where Slot = (Symbol, Type)

    data InCtor ci (ifs :: [Slot]) = InCtor
      { icName  :: String
      , icMatch :: ci -> Maybe (RegFile ifs)
      , icBuild :: RegFile ifs -> ci
      }

    data Term (rs :: [Slot]) (ci :: Type) (r :: Type) where
      TLit          :: r -> Term rs ci r
      TReg          :: Index rs r -> Term rs ci r
      TInpCtorField :: InCtor ci ifs -> Index ifs r -> Term rs ci r
      TApp1         :: (a -> r) -> Term rs ci a -> Term rs ci r
      TApp2         :: (a -> b -> r)
                    -> Term rs ci a -> Term rs ci b -> Term rs ci r

    inpCtor :: InCtor ci ifs -> Index ifs r -> Term rs ci r
    inpCtor = TInpCtorField

`TInpField` and the `inp` helper are removed in M7 once every use site is
migrated. (M2-M3 keep them in parallel so the build does not break in
the middle of the migration.)

The `OPack` constructor loses its third field in M4:

    data OutTerm rs ci co where
      OPack :: WireCtor co fields
            -> OutFields rs ci fields
            -> OutTerm rs ci co
      OFn   :: (RegFile rs -> ci -> co) -> OutTerm rs ci co

`pack` matches:

    pack :: WireCtor co fields
         -> OutFields rs ci fields
         -> OutTerm rs ci co


## Mechanical inversion algorithm

`solveOutput :: OutTerm rs ci co -> RegFile rs -> co -> Maybe ci` walks
an `OPack` structurally. The `OFn` clause stays as `Nothing` (opaque
output is still out of scope; v3 retires `OFn`).

For an `OPack ctor fields` and observed `co_obs`:

1. **Match the wire constructor.** `wcMatch ctor co_obs` either returns
   `Nothing` (the observed output is not from this constructor; this
   edge does not apply) or `Just fs_obs :: fields`.

2. **Walk `fields :: OutFields rs ci fields` and `fs_obs :: fields` in
   lockstep.** `OutFields` has constructor `OFCons :: Term rs ci f ->
   OutFields rs ci fs -> OutFields rs ci (f, fs)`, so the walk is a
   simple structural recursion on the HList. At each step:

   - `TLit _` paired with an observed value: skip. (See §"Why we don't
     check `TLit`/`TReg` equalities" below.)
   - `TReg _` paired with an observed value: skip.
   - `TInpCtorField ic ix` paired with observed value `v`: record an
     entry `(SomeIc ic, ix-as-int, v-as-Any)`. The `SomeIc` existential
     wrapper is needed because the walk can record `InCtor ci ifs` for
     several different `ifs` indices, but a well-formed edge will
     ultimately use only one.
   - `TApp1 _ _` or `TApp2 _ _ _`: cannot mechanically invert. Return
     `Nothing` from `solveOutput`. (`checkHiddenInputs` warns about
     these edges at build time.)

3. **Verify all `TInpCtorField` entries share one `InCtor`.** Compare
   `icName` strings across the gathered entries. If the names disagree,
   the edge is malformed (one edge cannot read fields from two different
   command constructors and still expect the guard to typecheck the
   joint, but the structural type system does not enforce this and the
   guard is not consulted here); return `Nothing` and let
   `checkHiddenInputs` flag the inconsistency at build time.

4. **Verify the gathered entries cover all fields of the chosen
   `InCtor`.** Each `Index ifs r` has an integer position
   (`indexInt :: Index ifs r -> Int`, already in `Keiki.Core`); the
   gathered set should contain every position from `0` to `length ifs -
   1`. Missing positions ⇒ this edge's `OutFields` does not project
   every field of the input constructor; return `Nothing` (the V0
   hidden-input case lands here). `checkHiddenInputs` reports the
   missing field names.

5. **Assemble the `RegFile ifs` from the gathered entries** in slot
   order (zero-indexed) and call `icBuild ic rf :: ci`.

The assembly in step 5 is the only fiddly part; the next subsection
sketches the type-safe implementation.


### Assembling the `RegFile ifs`

The walk gathers a list `[ByIndex ifs]` where

    data ByIndex ifs where
      ByIndex :: Index ifs r -> r -> ByIndex ifs

(`r` is existentially packed; only the slot's type can be retrieved by
matching against the same `Index`.) Assembly is a recursive class:

    class AssembleRegFile (ifs :: [Slot]) where
      assemble :: [ByIndex ifs] -> Maybe (RegFile ifs)

    instance AssembleRegFile '[] where
      assemble [] = Just RNil
      assemble _  = Nothing  -- extra entries; malformed

    instance (KnownSymbol s, AssembleRegFile rs)
          => AssembleRegFile ('(s, r) ': rs) where
      assemble entries = do
        v    <- findHead entries
        rest <- assemble (popHead entries)
        pure (RCons (Proxy @s) v rest)
        where
          findHead :: [ByIndex ('(s, r) ': rs)] -> Maybe r
          findHead [] = Nothing
          findHead (ByIndex ZIdx v : _)    = Just v
          findHead (_ : rest)              = findHead rest

          popHead :: [ByIndex ('(s, r) ': rs)] -> [ByIndex rs]
          popHead [] = []
          popHead (ByIndex ZIdx _ : rest)  = popHead rest
          popHead (ByIndex (SIdx i) v : rest) = ByIndex i v : popHead rest

Pattern-matching on `Index ('(s, r) ': rs) r0` with `ZIdx` refines
`r0 ~ r`, so `findHead`'s `Just v` returns a value of type `r` without
`unsafeCoerce`. The assembly is type-safe end-to-end.

The Term walk packs a `ByIndex ifs` for an existential `ifs` (the
`InCtor`'s `ifs`); we recover that `ifs` after the consistency check in
step 3 by pattern-matching the `SomeIc`:

    data SomeIcWithEntries ci where
      SomeIcWithEntries
        :: InCtor ci ifs
        -> [ByIndex ifs]
        -> SomeIcWithEntries ci

The walk produces a `Maybe (SomeIcWithEntries ci)` (or `Maybe ()` if no
`TInpCtorField` appeared, in which case the edge's output does not
depend on the input symbol and the recovered `ci` is unconstrained ⇒
return `Nothing` for `solveOutput` and let `checkHiddenInputs` flag the
edge if its guard reads `ci`).

After consistency, call `assemble entries` (with `AssembleRegFile ifs`
in scope, which the `SomeIcWithEntries` existential supplies via a
`Dict` or an inline class constraint) and finish with `icBuild ic`.


### Why we don't check `TLit`/`TReg` equalities in `solveOutput`

The plan's M3 sketch suggested checking `TLit r == observed v` and
`regs ! ix == observed v` during the walk. Doing so requires `Eq r`,
which the v1 `Term` constructors do not carry (`TLit`'s signature is
`r -> Term rs ci r`, no class context). Adding `Eq r` constraints to
`TLit` and `TReg` would constrain user code (every literal slot must
have an `Eq` instance — true for User Registration's slot types but
not a free lunch in general).

The chosen tradeoff: skip the `TLit`/`TReg` equality checks in
`solveOutput`. Soundness comes from `applyEvent`'s post-step guard
check (`models (guard e) (regs, ci)` runs after `solveOutput` returns a
`Just ci`); a wrong-edge attribution survives `solveOutput` only if the
guard *also* fails to rule it out. In practice the guard's
constructor-mutual-exclusion (the `isStart`/`isConfirm`/... family)
catches wrong-edge attributions before the literal/register check would
have. If a future use case surfaces an example where the guard does
*not* discriminate adequately, the design can revisit by adding `Eq r`
to `TLit`/`TReg`; until then, simpler is better.

This deviation from the plan's M3 sketch is the only design-time
deviation; it is documented in the EP-1 plan's Decision Log at M3
landing time.


## Equality of `InCtor` values

Step 3 of the algorithm compares two `InCtor` values for equality. The
practical implementation:

    sameInCtor :: InCtor ci ifs1 -> InCtor ci ifs2 -> Bool
    sameInCtor a b = icName a == icName b

The `icName` is a free-form string; the user picks names matching the
constructor name (`"StartRegistration"`, `"ConfirmAccount"`, ...). The
comparison is a heuristic — two `InCtor` values with the same name and
different `ifs` are an authoring error that the structural walk does
not catch with full precision. The trade-off: `InCtor` values are
top-level and stable; the user writes them once near the wire
constructors. Name collisions in practice are author errors caught by
testing, not by the type system.

A stricter alternative is to use `StableName` (`System.Mem.StableName`)
to compare pointer equality, but that requires `IO`. Rejected; name
equality is enough.


## v1 surfaces that stay

- `TLit`, `TReg`, `TApp1`, `TApp2` — unchanged.
- `OutFields` (`OFNil`, `OFCons`) — unchanged shape.
- `WireCtor` — unchanged.
- `OFn` — stays as v2's "opaque output" escape hatch (out of scope per
  MasterPlan).
- `HsPred` constructors `PTop`/`PBot`/`PAnd`/`POr`/`PNot`/`PEq`
  /`PMatchC` — unchanged. (`PMatchC` is v2 escape hatch, out of scope.)
- `BoolAlg` class — unchanged. (EP-2 upgrades the instance, not the
  class.)
- `unsafeCombine` — unchanged. (Out of scope for this MasterPlan.)
- All helpers except `inp`: `matchCmd`, `mkOut`, `proj`, `lit`, `(.==)`,
  `pack` (signature change in M4).


## v1 surfaces that go

- `TInpField :: (ci -> r) -> Term rs ci r` constructor — deleted in M7.
- `inp :: (ci -> r) -> Term rs ci r` helper — deleted in M7.
- `OPack`'s third field `(RegFile rs -> co -> Maybe ci)` — deleted in
  M4.
- `outFieldsHaveInpField :: OutFields rs ci fs -> Bool` — replaced (or
  renamed) by `outFieldsHaveInpCtorField` plus structural-completeness
  predicates in M3.
- `termReadsInput`'s `TInpField` clause — deleted in M7; the
  `TInpCtorField` clause stays.

The `Keiki.Core` module export list shrinks by `inp` and grows by
`InCtor (..)`, `inpCtor`, `TInpCtorField` (re-exported via the
constructor list of `Term`).


## User Registration migration plan

The V5 aggregate (`src/Keiki/Examples/UserRegistration.hs`) defines four
input-reading helpers in v1:

    inpStart, inpConfirm, inpResend, inpGdpr

each via `TInpField` plus a `\case` with `error "guard"` stubs. The v2
form replaces them with one `InCtor` value per command constructor and
re-uses the helper names with new types:

    -- M5 additions, near the wire constructors.
    inCtorStart   :: InCtor UserCmd
                     '[ '("email", Email)
                      , '("confirmCode", ConfirmationCode)
                      , '("at", UTCTime)
                      ]
    inCtorConfirm :: InCtor UserCmd
                     '[ '("confirmCode", ConfirmationCode)
                      , '("at", UTCTime)
                      ]
    inCtorResend  :: InCtor UserCmd
                     '[ '("code", ConfirmationCode)
                      , '("at", UTCTime)
                      ]
    inCtorGdpr    :: InCtor UserCmd
                     '[ '("at", UTCTime) ]

The helper names stay the same; the types change:

    inpStart   :: Index '[ '("email", Email), '("confirmCode", ConfirmationCode), '("at", UTCTime) ] r
               -> Term UserRegRegs UserCmd r
    inpStart   = TInpCtorField inCtorStart

    inpConfirm :: Index '[ '("confirmCode", ConfirmationCode), '("at", UTCTime) ] r
               -> Term UserRegRegs UserCmd r
    inpConfirm = TInpCtorField inCtorConfirm

    -- ... etc.

Every call site changes from the v1 form `inpStart (.email)` (a
record-projection function) to the v2 form `inpStart #email` (an
`OverloadedLabels` `Index`). The two forms are pleasingly close; the
diff is mechanical.

Every `pack ctor fields handWrittenInverse` becomes `pack ctor fields`
(one fewer argument).

The `error "inpStart: guard rules out non-StartRegistration"` stubs in
the v1 helpers are gone: the new `evalTerm` clause for `TInpCtorField`
emits a "guard violation" error (via `icMatch`'s `Nothing` branch) when
the input constructor does not match. The error message is more
specific because it names the `icName`.

For the V0 aggregate (`src/Keiki/Examples/UserRegistrationV0.hs`):

- The same `inCtorStart`/`inCtorConfirm`/... values apply; the V0 bug
  is in the *event* schema, not the *command* schema.
- The Confirm edge's `OutFields` becomes
  `OFCons (proj #email) (OFCons (inpConfirm #at) OFNil)` (no
  `inpConfirm #confirmCode` because `wireAccountConfirmedV0`'s tuple
  shape no longer includes that slot).
- `solveOutput` returns `Nothing` because the assembly step finds the
  `confirmCode` slot of `inCtorConfirm`'s slot list missing.
- The hand-written `\_regs _co -> Nothing` inverse is gone.
- `checkHiddenInputs` produces a warning shaped roughly:

      "RequiresConfirmation edge #0: OPack walk for InCtor
       \"ConfirmAccount\" leaves field \"confirmCode\" unrecovered"

  The exact text is the M3 implementation's call.


## Implementation checklist for M2-M7

The plan file's Progress section is the source of truth; this checklist
is a re-statement scoped to the design's deliverables.

**M2 — add the new constructor.** Edit `src/Keiki/Core.hs`:

- Add `data InCtor ci (ifs :: [Slot]) = InCtor { icName, icMatch,
  icBuild }` after `WireCtor`.
- Add `TInpCtorField :: InCtor ci ifs -> Index ifs r -> Term rs ci r`
  to `Term`. Keep `TInpField` for now.
- Add `inpCtor :: InCtor ci ifs -> Index ifs r -> Term rs ci r` helper.
- Update `evalTerm`'s pattern-match to handle `TInpCtorField` (call
  `icMatch`; on `Just rf`, look up via `(!)`; on `Nothing`, `error`
  with `icName` in the message).
- Update `termReadsInput` to count `TInpCtorField` as input-reading.
- Update the module export list to include `InCtor (..)`, `inpCtor`.

Add tests in `test/Keiki/CoreSpec.hs`:

- `evalTerm (TInpCtorField inCtorTiny #foo) RNil tinyValue`
  succeeds for matching constructor.
- `evaluate (evalTerm (TInpCtorField inCtorTiny #foo) RNil
  otherValue) \`shouldThrow\` anyErrorCall` for non-matching.
- `termReadsInput` returns `True` for a term containing
  `TInpCtorField`.

**M3 — structural inversion.** Edit `src/Keiki/Core.hs`:

- Add `data ByIndex ifs where ByIndex :: Index ifs r -> r -> ByIndex
  ifs`.
- Add `data SomeIcWithEntries ci where SomeIcWithEntries :: InCtor ci
  ifs -> [ByIndex ifs] -> SomeIcWithEntries ci` plus the
  `AssembleRegFile ifs` constraint as a `Dict` carried inside or as a
  classes context on `SomeIcWithEntries`.
- Add `class AssembleRegFile (ifs :: [Slot])` with the two instances
  shown above.
- Add a private `gatherInpEntries :: OutFields rs ci fs -> fs -> Maybe
  (Maybe (SomeIcWithEntries ci))` (outer Maybe for `TApp*`-bail; inner
  Maybe for "no input reads in this OutFields").
- Rewrite `solveOutput` for `OPack`. Keep the legacy inverse parameter
  bound as `_legacyInv` to silence warnings; M4 removes the field
  entirely.
- Add `outFieldsMissingInCtorFields :: OutFields rs ci fs -> Maybe
  (String, [String])` (the `InCtor`'s name + the missing field names).
- Rewrite `checkHiddenInputs`'s `OPack` clause to emit a warning shaped
  `"OPack walk for InCtor \"<name>\" leaves field
  \"<field>\" unrecovered"` when the analyzer detects missing fields.
  Keep the v1 `outFieldsHaveInpField` predicate available for the
  duration of M3 so the build is green; M7 retires it.

Add tests in `test/Keiki/CoreSpec.hs`:

- A tiny `OPack` over a synthetic `TinyCmd` with `inCtorTiny`. Forward:
  `evalOut` produces the expected `co`. Inversion: `solveOutput`
  recovers the original `ci` mechanically.
- A second tiny `OPack` whose `OutFields` omits one slot of
  `inCtorTiny`. `solveOutput` returns `Nothing`; `checkHiddenInputs`
  produces the expected warning text.

**M4 — drop the `OPack` inverse field.** Edit `src/Keiki/Core.hs`:

- Change `OPack`'s constructor signature to two arguments.
- Change `pack`'s helper signature to two arguments.
- Remove the `_legacyInv` binding from `solveOutput`'s `OPack` clause.
- Remove the unused parameter bindings from `evalOut` and
  `checkHiddenInputs`.

Edit `test/Keiki/CoreSpec.hs`:

- The single `OPack` use site (`outFoo` in the tiny-OPack describe)
  loses its third argument.

The two example modules are intentionally left broken until M5/M6.

**M5 — migrate V5.** Edit `src/Keiki/Examples/UserRegistration.hs`:

- Add four `inCtor*` definitions after the wire constructors.
- Replace four `inpFoo` helpers' types and bodies per §"Migration plan"
  above.
- Walk every `Edge` in `userRegEdges`. Replace `inpFoo (.field)` with
  `inpFoo #field` and drop the third argument from every `pack`.

Run `cabal test --test-options="--match
Keiki.Examples.UserRegistrationSpec"`; expect 7 examples, 0 failures.

**M6 — migrate V0.** Edit `src/Keiki/Examples/UserRegistrationV0.hs`:

- Mirror M5; remove the local `inpStart`/etc. wrappers (the V0 source
  currently re-defines them; after M5 they are imported from V5).
- Drop the hand-written `\_regs _co -> Nothing` from the Confirm edge's
  `pack`.

Edit `test/Keiki/Examples/UserRegistrationV0Spec.hs`:

- Update the warning-text assertion to match the new message
  (`"InCtor \"ConfirmAccount\" leaves field \"confirmCode\""` or
  whatever the M3 implementation produces). Verify the assertion text
  is the actual emitted text by running `cabal test` and reading the
  diff in the failure message; iterate until matched.

**M7 — remove `TInpField` and `inp`.** Edit `src/Keiki/Core.hs`:

- Delete the `TInpField` constructor.
- Delete the `inp` helper.
- Delete `inp` and `TInpField` from the module export list.
- Drop the `TInpField` clauses from `evalTerm`, `termReadsInput`.
- Rename `outFieldsHaveInpField` to `outFieldsHaveInpCtorField`
  (or delete and replace by the M3 helpers).
- Remove the haddock paragraph in the module header that mentions
  `TInpField` as a v1 escape hatch.

Edit `test/Keiki/CoreSpec.hs`:

- Replace any `TInpField`-using test (`evaluates TInpField`,
  `evaluates TApp1`, `evaluates TApp2`, `solveOutput on a tiny
  OPack`) with `TInpCtorField` analogues.

Verify with `git grep TInpField src/ test/` — expect zero hits.

**M8 — design notes + verdict.** Edit
`docs/research/dsl-shape-for-symbolic-register.md` per the EP-1 plan's
M8 milestone. Write the EP-1 verdict in this plan's Outcomes &
Retrospective. Mark EP-1 Complete in the MasterPlan.


## Risks and mitigations

- *The `AssembleRegFile` class introduces an `INCOHERENT` or
  overlapping-instances warning.* Both instances differ in head shape
  (`'[]` vs. `':`); GHC should resolve them deterministically. If a
  warning surfaces, document it in Surprises & Discoveries.
- *The `SomeIcWithEntries`-with-existential-`AssembleRegFile`-dict
  pattern is unfamiliar to the contributor.* Read `Data.Constraint`'s
  `Dict` newtype documentation if the inline-context-on-an-existential
  syntax does not typecheck cleanly. The fallback is to keep the
  `AssembleRegFile` constraint as a class context on `InCtor` itself,
  which makes `SomeIcWithEntries` simpler at the cost of constraining
  every `InCtor` value.
- *The `error "guard"` migration changes test output.* The v1 helpers
  produced messages like `"inpStart: guard rules out
  non-StartRegistration"`; the v2 form produces `"evalTerm:
  TInpCtorField guard violation: StartRegistration"`. Any test that
  asserted the v1 text (none currently do per a grep) needs updating.


## Open questions for the implementer

None. The design above pins every decision the milestones need. M2-M7
implement what M1 specifies; if a milestone surfaces a contradiction
between this note and the code, raise it in the EP-1 plan's Surprises &
Discoveries and update the note before continuing.


## Post-implementation update (2026-05-01)

The implementation surfaced one shape change against the design above.
The original design carried `OPack :: WireCtor co fields -> OutFields
rs ci fields -> OutTerm rs ci co` and expected `solveOutput` to
discover the `InCtor` from `TInpCtorField` reads inside `OutFields`.
This breaks for input constructors with no payload (specifically
`Continue` in the User Registration aggregate): `Index '[] r` is
uninhabited so an empty-payload `InCtor` cannot appear in any
`OutFields`, and the walk has no way to recover the constructor
identity.

The shipped form of `OPack` carries the `InCtor` explicitly:

    data OutTerm (rs :: [Slot]) (ci :: Type) (co :: Type) where
      OPack :: InCtor ci ifs
            -> WireCtor co fields
            -> OutFields rs ci fields
            -> OutTerm rs ci co
      OFn   :: (RegFile rs -> ci -> co) -> OutTerm rs ci co

    pack :: InCtor ci ifs
         -> WireCtor co fields
         -> OutFields rs ci fields
         -> OutTerm rs ci co
    pack = OPack

`solveOutput` walks the `OutFields` against the named `InCtor`,
gathering only entries whose `TInpCtorField`'s `InCtor` matches by
`icName` and bailing on any opaque term. Empty-payload constructors
recover trivially: `gatherInpEntries` yields `Just []`, `assemble []
= Just RNil`, and `icBuild ic RNil` returns the singleton constructor.
The result is a strictly cleaner design than the M1 shape — no
`SomeIcWithEntries` existential is needed, and the icName-based
combine step is gone.

The EP-1 plan's Surprises & Discoveries and Decision Log record the
deviation and the date.
