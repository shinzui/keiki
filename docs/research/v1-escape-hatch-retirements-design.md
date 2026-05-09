# v1 escape hatch retirements — design note (MP-6 / EP-15)

Status: design milestone produced by EP-15 of MasterPlan 6
(`docs/masterplans/6-retire-remaining-v1-escape-hatches-in-pure-core-ofn-pmatchc-unsafecombine-static-check.md`).
Authored 2026-05-02. The recommendation here drives the fan-out of MP-6 into per-retirement
ExecPlans.

This note answers the four questions EP-15 set out to settle:

1. The successor surface for each of `OFn`, `PMatchC`, and `unsafeCombine`.
2. The decomposition (one EP, two EPs, or three EPs).
3. The migration story for each retirement.
4. The MasterPlan revision that applies the chosen decomposition.

The first three are answered below. The fourth is applied in EP-15's M3 milestone
(see EP-15's Progress section); the per-retirement EPs created in M3 reference back
to this note.


## Toolchain baseline

The survey was performed against:

- GHC 9.12.3 (matches the MP-3 / MP-4 baseline; EP-7's GHC 9.12 upgrade has landed
  on master).
- cabal-install 3.16.1.0.
- `cabal build` and `cabal test all` are green: 107 examples, 0 failures.

No drift from prior MasterPlan baselines.


## Survey — call sites of each escape hatch

The survey ran:

    grep -rn "OFn\|mkOut" src/ test/
    grep -rn "PMatchC\|matchCmd" src/ test/
    grep -rn "unsafeCombine" src/ test/

The findings differ substantially from MP-6's original Vision & Scope. The Vision &
Scope assumed `OFn` was "Currently used by the `Keiki.Examples.UserRegistration`
aggregate's edges whose output shape doesn't fit the structural `OPack` form" and
that `PMatchC` survived in aggregates as the constructor-equality fallback. Neither
is true on master as of 2026-05-02. The actual state:

### `OFn` / `mkOut`

Total non-test, non-Core call sites: **zero in any example aggregate**.

- `src/Keiki/Core.hs`: the constructor declaration (line 342), the `mkOut` helper
  (line 446), the `evalOut` clause (line 504), the `solveOutput` clause that returns
  `Nothing` on `OFn` (line 642), and the `checkHiddenInputs` clause that flags `OFn`
  edges (lines 716-717).
- `src/Keiki/Composition.hs`: four `error` clauses (lines 221, 261, 314-318) in
  `substTerm`, `substPred`, and `substOut` that abort composition when a `t1` edge's
  output is `OFn` or a `t2` edge's output is `OFn`. The compose algorithm refuses to
  thread opaque outputs through substitution.
- `test/Keiki/CoreSpec.hs`: a synthetic transducer using `mkOut (\_ _ -> "true")`
  on line 38, and three test cases at lines 120-123 and 180-183 that exercise
  `solveOutput` returning `Nothing` on `OFn` and `checkHiddenInputs` flagging it.
- `jitsurei/src/Jitsurei/UserRegistration.hs`: **no occurrences**.
- `jitsurei/src/Jitsurei/UserRegistrationV0.hs`: **no occurrences**.
- `jitsurei/src/Jitsurei/EmailDelivery.hs`: **no occurrences**.

`OFn` is dead in user code. The only consumers are (a) the synthetic test cases,
which exist precisely to exercise `OFn` behaviour, and (b) Composition's
defensive error paths.

### `PMatchC` / `matchCmd`

Total non-test, non-Core call sites: **zero in any example aggregate**.

- `src/Keiki/Core.hs`: the constructor declaration (line 367), the `matchCmd`
  helper (line 426), the `evalPred` clause (line 524), and a comment explaining the
  back-compat status (line 363).
- `src/Keiki/Symbolic.hs`: the SBV translation falls back to a fresh `SBool`
  on `PMatchC` (line 287). The over-approximation is documented in
  `docs/research/sbv-boolalg-design.md` (lines 280-289, 315-331).
- `src/Keiki/Composition.hs`: `weakenLPred` passes `PMatchC` through unchanged
  (line 137); `substPred` errors out when `t2`'s guard uses `PMatchC` over the mid
  type (lines 264-269).
- `test/Keiki/CoreSpec.hs`: a synthetic edge guard using `matchCmd id` at line 36
  and a dispatch test at lines 91-92.
- `jitsurei/src/Jitsurei/UserRegistrationV0.hs:89`: a code comment that records the
  *historical* migration from `matchCmd` to `matchInCtor`. No actual usage of
  `matchCmd` or `PMatchC`.
- `jitsurei/src/Jitsurei/UserRegistration.hs`: **no occurrences**.
- `jitsurei/src/Jitsurei/EmailDelivery.hs`: **no occurrences**.

`PMatchC` is dead in user code. The only consumers are (a) the synthetic test
cases, (b) Composition's defensive error paths, and (c) the SBV translation's
fallback clause that exists because the constructor exists. EP-2 of MasterPlan 2
shipped `PInCtor` / `matchInCtor` as the structural alternative, and the example
aggregates have already adopted it (V0's comment at line 89 confirms this).

### `unsafeCombine`

Total call sites: **8 source uses, 2 test uses, plus the load-bearing site at
`src/Keiki/Composition.hs:416`**.

- `src/Keiki/Core.hs`: the export, signature, and body (lines 52, 289-290), plus
  module-level retirement comment (line 32).
- `src/Keiki/Composition.hs:416` — the load-bearing case. The `compose` algorithm
  builds a composite edge whose `update` is the disjoint union of t1's weakened
  update and t2's substituted update:

      , update = unsafeCombine
                   (weakenLUpdate @rs1 @rs2 (update e1))
                   (substUpdate   @rs1 @rs2 (update e2) o1)

  Disjointness here is structural: `weakenLUpdate` writes only into the `rs1`
  prefix of the appended register file; `substUpdate` writes only into the `rs2`
  suffix.
- `jitsurei/src/Jitsurei/UserRegistration.hs`: 3 uses across 2 edges (registration
  start, resend) chaining 2-3 single-slot `USet`s.
- `jitsurei/src/Jitsurei/UserRegistrationV0.hs`: 3 uses, mirroring the V5 aggregate.
- `jitsurei/src/Jitsurei/EmailDelivery.hs`: 2 uses, chaining 3 single-slot `USet`s on
  the email-pending edge.
- `test/Keiki/CompositionSpec.hs`: 2 uses in test fixtures.

`unsafeCombine` is alive and load-bearing.


## Successor surface — per retirement

### `OFn` — REMOVE outright (no successor needed)

Because no aggregate uses `OFn`, there is nothing to migrate to a structural
successor. The retirement is mechanical:

1. Drop the `OFn` constructor from `OutTerm`.
2. Drop the `mkOut` helper and remove it from `Keiki.Core`'s export list.
3. Remove the `evalOut` / `solveOutput` / `checkHiddenInputs` clauses for `OFn`.
4. Remove the four `error` clauses in `src/Keiki/Composition.hs` that refuse `OFn`
   outputs — once the constructor is gone, the code paths are statically
   impossible.
5. Update `test/Keiki/CoreSpec.hs`: replace the `mkOut (\_ _ -> "true")` synthetic
   transducer with a structural `OPack`-based fixture; delete the
   "solveOutput on OFn" and "synthetic transducer's OFn output is flagged"
   describe blocks, since the warning class they exercise (`OFn output is opaque`)
   no longer exists. The `checkHiddenInputs` *behaviour* still applies to genuinely
   structural cases (e.g. V0's missing-confirmCode warning); only the OFn-specific
   warning shape goes away.

This revises MP-6's Vision & Scope, which assumed there would be either (a) a
structural successor covering current `OFn` uses or (b) a renamed escape hatch.
Neither is necessary because there are no current uses to cover. **`mkOut` is
gone.** If a future user ever needs an opaque output, they can re-introduce a
named hatch at that time; speculatively keeping one for "back-compat" against an
unused constructor is dead weight.

### `PMatchC` — REMOVE outright (no successor needed)

Same shape as `OFn`. The aggregates have already migrated to `matchInCtor` /
`PInCtor` (V0's line-89 comment is the receipt). The retirement is mechanical:

1. Drop the `PMatchC` constructor from `HsPred`.
2. Drop the `matchCmd` helper and remove it from `Keiki.Core`'s export list.
3. Remove the `evalPred` clause for `PMatchC`.
4. Remove the `weakenLPred` and `substPred` clauses in
   `src/Keiki/Composition.hs` that handle `PMatchC` (the substPred error path
   becomes statically impossible once the constructor is gone; the weakenLPred
   passthrough disappears for the same reason).
5. Remove the `PMatchC` clause in `translatePred` in `src/Keiki/Symbolic.hs`.
   The SBV-fallback "free pmatchc" case goes away; the `Symbolic.hs` Haddock
   loses a bullet from its translation list.
6. Update `test/Keiki/CoreSpec.hs`: replace the `matchCmd id` guard in the
   synthetic transducer with a structural alternative (e.g. `PInCtor` over a
   one-constructor input type, or `PEq (TLit True) (TLit True)`); delete the
   "PMatchC dispatches to the carried predicate" test.

The `PInCtor` + `PEq` + `PAnd` / `POr` / `PNot` algebra is sufficient for every
guard in the example aggregates — confirmed by the survey: every guard in
`UserRegistration`, `UserRegistrationV0`, and `EmailDelivery` is one of
`matchInCtor` (becomes `PInCtor`), `PEq`, or `PAnd` over those.

A **richer pattern AST is not needed** at this time. If a future aggregate needs
a guard outside this algebra (e.g. payload-pattern matching beyond simple field
equality), the design can extend `HsPred` then. Speculatively designing one now
would be premature.

### `unsafeCombine` — STATIC CHECK via type-level slot-name set

The retirement here is real engineering. The smart-constructor `combine` already
enforces "distinct targets" at runtime by walking `targets :: Update rs ci ->
[Int]` and checking the lists don't overlap. The retirement makes the same
invariant a type-level constraint, so that `unsafeCombine` becomes redundant and
can be removed (and the runtime check in `combine` collapses to a no-op or is
removed alongside).

The proposed encoding indexes `Update` over a type-level set of written-slot
names:

    data Update (rs :: [Slot]) (w :: [Symbol]) (ci :: Type) where
      UKeep    :: Update rs '[] ci
      USet     :: KnownSymbol s
               => IndexN s rs r -> Term rs ci r -> Update rs '[s] ci
      UCombine :: Disjoint w1 w2
               => Update rs w1 ci
               -> Update rs w2 ci
               -> Update rs (Concat w1 w2) ci

where `IndexN (s :: Symbol) rs r` is a slot-name-tagged variant of the existing
`Index rs r`:

    data IndexN (s :: Symbol) (rs :: [Slot]) (r :: Type) where
      IZ :: IndexN s ('(s, r) ': rs) r
      IS :: IndexN s rs r -> IndexN s ('(s', r') ': rs) r

`Disjoint :: [Symbol] -> [Symbol] -> Constraint` is a closed type family using
`CmpSymbol` to decide name disjointness at compile time. `Concat` is the standard
type-level list concatenation. Existing label-driven authoring (`#email :: Index
UserRegRegs Email`) lifts straightforwardly because the `IsLabel` instance for
`Index` already constructs the index from the slot symbol — extending it to
`IndexN` is mechanical.

Variants considered:

- **Phantom written-slot list (no `IndexN`).** Tag `USet` with the slot symbol
  via a `KnownSymbol` constraint and a `Lookup`-style type family. Cleaner at the
  use site but harder to write the `Disjoint` proof from `combine`'s perspective.
  Favour `IndexN` for direct typeability.
- **Boolean type family `IsDisjoint w1 w2 ~ True` instead of a constraint.**
  Equivalent expressive power; constraint form gives better error messages in
  GHC ≥ 9.4 with TypeError support.

The migration from `unsafeCombine` to `combine` (which becomes the only combine —
its runtime check goes away alongside `unsafeCombine`):

- Aggregates: chains like `USet a t1 \`unsafeCombine\` USet b t2` become
  `USet a t1 \`combine\` USet b t2` — same syntax, the static check fires at
  the type level when slot names overlap.
- `src/Keiki/Composition.hs:416`: `weakenLUpdate` and `substUpdate` are extended
  to thread the written-slot index through their type signatures:

      weakenLUpdate
        :: forall rs1 rs2 w ci.
           Update rs1 w ci -> Update (Append rs1 rs2) w ci

      substUpdate
        :: forall rs1 rs2 w ci1 mid.
           WeakenR rs1
        => Update rs2 w mid -> OutTerm rs1 ci1 mid
        -> Update (Append rs1 rs2) w ci1

  The composite `combine` at line 416 needs `Disjoint w1 w2` where `w1` ⊆ rs1's
  slot names and `w2` ⊆ rs2's slot names. The keiki invariant that composed
  transducers have disjoint register-name domains (an existing precondition;
  see the design note at `docs/research/composition-combinators-design.md`)
  promotes mechanically to a `Disjoint (Names rs1) (Names rs2)` constraint on
  `compose`. With that in scope, `Disjoint w1 w2` follows from
  `Disjoint (Names rs1) (Names rs2)` and `w1 ⊆ Names rs1` and `w2 ⊆ Names rs2`
  via a small auxiliary lemma class.

This is the substantive engineering of MP-6.


## Decomposition decision

**Three EPs, one per retirement.**

Rationale:

- The OFn and PMatchC retirements are mechanical (no aggregate uses, no
  successor surface to design) and small (~5 commits each).
- The unsafeCombine retirement is substantive (encoding decisions, broad
  call-site refactor, composition-side proof obligation).
- Bundling OFn+PMatchC into one EP would conflate two independently-verifiable
  gates: OFn's gate is "removed; tests rewritten; checkHiddenInputs no longer
  emits the OFn-specific warning"; PMatchC's gate is "removed; SBV translation
  no longer falls back; tests rewritten." Each can land independently.
- Bundling all three would gate two trivial retirements on the substantive
  one's encoding pass, blocking simple cleanup unnecessarily.

Three EPs preserve the MP-2 pattern (one concern per EP) and give MP-6 a clean
incremental shipping cadence. Each EP retires one constructor; each is
independently mergeable; each has a distinct test-suite gate.

Alternatives rejected:

- **Two EPs (bundle OFn+PMatchC, separate unsafeCombine).** Tempting because
  OFn and PMatchC are nearly identical mechanically. Rejected because their
  validation gates differ (Symbolic.hs touches PMatchC; Symbolic.hs does not
  touch OFn) and a per-constructor EP gives a reviewer one reviewable diff per
  concern. The marginal coordination saved by bundling is small; the clarity
  lost is real.
- **One EP folding all three plus this design milestone.** Rejected up front
  by EP-15's Plan of Work for the same reasons: too large, conflates gates.


## Per-retirement EP outlines

### EP-16: Retire `OFn` and `mkOut`

Scope: remove the `OFn` constructor, `mkOut` helper, and all clauses that depend
on them; rewrite `test/Keiki/CoreSpec.hs` to drop the `mkOut`-based synthetic
transducer and the `OFn`-specific test cases.

Hard deps: none.

Validation gate:

- `cabal build && cabal test all` is green; the test count drops by the OFn
  describe blocks.
- `Keiki.Core` no longer exports `mkOut` or `OFn`.
- `src/Keiki/Composition.hs` no longer contains any `OFn _ -> error` clause;
  the cases are eliminated by the GADT-narrowing once the constructor is gone.
- `src/Keiki/Core.hs:22-33` module-header retirement block has its `OFn` bullet
  marked retired (the cleanup of the whole block is by the last per-retirement
  EP; see IP-5 in MP-6).

### EP-17: Retire `PMatchC` and `matchCmd`

Scope: remove the `PMatchC` constructor, `matchCmd` helper, and all clauses that
depend on them. Update `src/Keiki/Symbolic.hs` to remove the `PMatchC` fallback;
update `test/Keiki/CoreSpec.hs` to drop the `matchCmd`-based synthetic edge and
the `PMatchC` dispatch test.

Hard deps: none. (Soft dep: should land after or with EP-16 to keep the synthetic
test transducer rewrite a single PR — but the two are independent at the source
level; the soft dep is purely about reviewer load.)

Validation gate:

- `cabal build && cabal test all` is green.
- `Keiki.Core` no longer exports `matchCmd` or `PMatchC`.
- `src/Keiki/Symbolic.hs`'s `translatePred` no longer has a `PMatchC` clause.
- The SBV note (`docs/research/sbv-boolalg-design.md`) gets a small update
  noting the PMatchC fallback is gone.
- `src/Keiki/Core.hs:22-33` retirement block has its `PMatchC` bullet marked
  retired.

### EP-18: Static `Disjoint` check on `Update`; retire `unsafeCombine`

Scope: introduce the `(w :: [Symbol])` index on `Update`, the `IndexN` slot-name
tagged index, the `Disjoint` type family, and the `Concat` type family. Lift
`weakenLUpdate` and `substUpdate` to thread the index through. Add the
`Disjoint (Names rs1) (Names rs2)` constraint on `compose`. Migrate every
`unsafeCombine` call site to `combine` (or just the renamed structural
combinator if `combine`'s `Either String` shape is collapsed alongside).
Remove `unsafeCombine` and its export. Migrate the `combine`-uses in tests too.

Hard deps: none. (Soft dep on EP-16/EP-17: the Composition-side cleanup is
cleaner if OFn/PMatchC are already gone, because the substTerm/substPred clauses
no longer carry error paths that interact with the new written-slot index.)

Validation gate:

- `cabal build && cabal test all` is green.
- `Keiki.Core` no longer exports `unsafeCombine`.
- `src/Keiki/Composition.hs:416` (now line shifts) uses `combine` (or the
  renamed structural combinator) without per-call-site proof obligations.
- The User Registration smoke test (`reconstitute userReg canonicalLog ==
  Just (Deleted, expectedSnapshot)`) still passes.
- The symbolic gate (`isSingleValuedSym (withSymPred userReg) == True`) still
  passes.
- `src/Keiki/Core.hs:22-33` retirement block has its `unsafeCombine` bullet
  marked retired; this EP also performs the IP-5 sweep that removes the whole
  "v1 escape hatches still pending retirement" block (in `Keiki.Core` and in
  `docs/research/dsl-shape-for-symbolic-register.md:997-1006`).


## Cross-cutting notes

### IP-1 (Core constructor sets) coordination

The three retirements affect three different datatypes (`OutTerm`, `HsPred`,
`Update`); no cross-EP datatype contention. Each EP owns its constructor.

### IP-2 (Composition's unsafeCombine use)

Owned by EP-18. Once EP-16 and EP-17 land, the Composition module no longer
contains any `OFn _ -> error` or `PMatchC _ -> error` clause; the file becomes
substantially simpler before EP-18 starts. This is a soft preference — EP-18
can land first, keeping the error clauses temporarily, but the natural ordering
is EP-16 → EP-17 → EP-18.

### IP-3 (example aggregates)

Aggregates are unaffected by EP-16 and EP-17 (they don't use those hatches).
Aggregates are migrated by EP-18 only. The smoke tests
(`reconstitute userReg canonicalLog`, `isSingleValuedSym`) reuse the canonical
fixtures unchanged.

### IP-4 (this design note)

Owned by EP-15. Each per-retirement EP may amend its own subsection if
implementation reveals a wrinkle; the EP records the amendment in its Decision
Log per the ExecPlan revision protocol.

### IP-5 (stale-comment cleanup)

`Keiki.Core` and `dsl-shape-for-symbolic-register.md` both carry "v1 escape
hatches still pending retirement" blocks. EP-16 and EP-17 each tick a bullet on
those blocks but leave the block in place because at least one bullet remains.
EP-18 (the last of the three) removes the entire block and replaces it with an
"all retired" pointer to MP-6's Outcomes section.


## What this design note does not settle

Item G of `docs/research/keiki-generics-design.md` — compile-time topology
safety via `SymTransducerStrict` parameterized over a type-level topology — is
explicitly out of scope for MP-6 (per MP-6's Vision & Scope and per the
generics design note's own statement that item G is a separate
MasterPlan-sized initiative). EP-18's `Disjoint`-on-`compose` constraint is a
narrow, mechanical addition; it does not embark on the topology-safety
redesign.
