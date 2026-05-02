---
id: 18
slug: static-disjoint-check-on-update-retire-unsafecombine
title: "Static Disjoint check on Update; retire unsafeCombine"
kind: exec-plan
created_at: 2026-05-02T13:37:07Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
master_plan: "docs/masterplans/6-retire-remaining-v1-escape-hatches-in-pure-core-ofn-pmatchc-unsafecombine-static-check.md"
---

# Static Disjoint check on Update; retire unsafeCombine

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

`Keiki.Core` exports two combine functions on the copyless update
language `Update rs ci`:

- `combine :: Update rs ci -> Update rs ci -> Either String (Update
  rs ci)` — the smart constructor. Walks the runtime structure of
  both updates, computes the integer slot positions written by each,
  and returns `Left` if they overlap.
- `unsafeCombine :: Update rs ci -> Update rs ci -> Update rs ci` —
  the v1 escape hatch. Bypasses the runtime check.

`unsafeCombine` is the v1 escape hatch this plan retires. It is
load-bearing in two places:

- **Aggregates**: every multi-slot edge update in
  `src/Keiki/Examples/UserRegistration.hs`,
  `src/Keiki/Examples/UserRegistrationV0.hs`, and
  `src/Keiki/Examples/EmailDelivery.hs` chains 2-3 single-slot
  `USet`s together with `\`unsafeCombine\``. The disjointness is
  obvious to a human (each `USet` writes a different `#name`-labelled
  slot) but currently checked only at the type of `combine` (which
  the aggregates do not use to avoid the `Either String` plumbing in
  edge construction).

- **Composition**: `src/Keiki/Composition.hs:416` (inside `compose`)
  builds the composite edge's `update` field as

      , update = unsafeCombine
                   (weakenLUpdate @rs1 @rs2 (update e1))
                   (substUpdate   @rs1 @rs2 (update e2) o1)

  Disjointness here is structural (left writes only into the `rs1`
  prefix; right writes only into the `rs2` suffix), but
  `weakenLUpdate` / `substUpdate` do not currently expose that
  invariant in their types, so the composite cannot use the smart
  `combine` without dropping into `Either String` for what is
  provably a `Right`.

This plan makes "distinct targets" a **type-level invariant** rather
than a runtime check, and removes `unsafeCombine`. Concretely, after
this plan:

- `Update` carries an extra type index `(w :: [Symbol])` recording
  the slot names it writes. `UKeep` writes nothing (`'[]`); `USet`
  writes one slot name (`'[s]`); `UCombine` requires a type-level
  `Disjoint w1 w2` constraint and produces an `Update rs (Concat w1
  w2) ci`.

- `Index rs r` is augmented (or replaced at the `USet` use-site) by
  a slot-name-tagged variant `IndexN (s :: Symbol) rs r` so `USet`
  can recover the slot symbol from the index it carries. The
  existing `IsLabel` instance is updated to construct `IndexN`
  values with the slot symbol as a phantom.

- `combine` becomes the single combine entrypoint. Its signature is

      combine :: Disjoint w1 w2
              => Update rs w1 ci
              -> Update rs w2 ci
              -> Update rs (Concat w1 w2) ci

  It becomes infallible at the type level. The runtime check
  function (`targets`) is removed because the invariant is enforced
  statically.

- `unsafeCombine` is removed from `Keiki.Core`'s exports.

- `weakenLUpdate` and `substUpdate` thread the slot-name index
  through their type signatures so the composite at
  `src/Keiki/Composition.hs:416` can use `combine` directly with no
  per-call-site proof obligation. A new constraint
  `Disjoint (Names rs1) (Names rs2)` is added to `compose` to
  discharge the structural disjointness between the two halves; this
  constraint formalizes a precondition the composition design note
  (`docs/research/composition-combinators-design.md`) already
  documents prose-form.

- The example aggregates' `\`unsafeCombine\`` chains become
  `\`combine\`` chains. No prose-level change for the aggregate
  author; the syntax is identical.

After this plan, the user gets:

- A type error at compile time when they try to combine two updates
  that write to the same slot (e.g. `USet #email t1 \`combine\` USet
  #email t2`). The error message names the overlapping slot symbol.
- A guarantee that the composition algorithm never relies on
  `unsafeCombine` — every composite update is structurally disjoint
  by construction, witnessed at the type level.
- A smaller surface: `unsafeCombine` is gone; `combine`'s `Either
  String` is gone (it cannot fail).

The user verifies the change by:

- Running `cabal build && cabal test all` and observing the User
  Registration smoke test
  (`reconstitute userReg canonicalLog == Just (Deleted,
  expectedSnapshot)`) and the symbolic gate
  (`isSingleValuedSym (withSymPred userReg) == True`) still pass.
- Editing one aggregate to write to a duplicate slot deliberately
  and observing GHC reject it with a `Disjoint` constraint failure.

This plan is the substantive engineering of MP-6. EP-15's design
note at `docs/research/v1-escape-hatch-retirements-design.md`
records the encoding rationale; this plan implements it.


## Progress

Use a checklist to summarize granular steps. Every stopping point
must be documented here, even if it requires splitting a partially
completed task into two ("done" vs. "remaining"). This section must
always reflect the actual current state of the work.

- [x] M0: Verify prerequisites — `cabal build && cabal test all` is
  green; record GHC version (GHC 9.12.3, EP-7 baseline). Record the
  starting test count. **Done 2026-05-02:** GHC 9.12.3; 107 examples,
  0 failures (matches EP-15's M0 baseline; EP-16/EP-17's synthetic
  fixture removals netted out). Working tree dirty with the MP-6
  registry edit and pre-existing untracked plan files; no source
  changes outstanding.
- [x] M1: Spike — implement `Disjoint :: [Symbol] -> [Symbol] ->
  Constraint`, `Concat :: [Symbol] -> [Symbol] -> [Symbol]`, and
  `IndexN (s :: Symbol) rs r` in a small standalone module
  (`src/Keiki/Internal/Slots.hs` is the natural home, or inline in
  `Keiki.Core` if the surface is small). Confirm GHC produces a
  legible error message on a deliberate overlap. Recover from the
  spike by either keeping the module or folding it into Core.
  **Done 2026-05-02.** Module created at `src/Keiki/Internal/Slots.hs`
  exporting `Concat`, `Member`, `Disjoint`, `Names`, `IndexN`,
  `HasIndexN`, `indexNToInt`, `indexNName`. Negative spike on
  `Disjoint '["foo","bar"] '["baz","foo"]` (forced via a top-level
  `print bad`) compiled to the designed `TypeError`:
  *"Keiki.Internal.Slots.Disjoint: slot \"foo\" is written by both
  halves of \`combine\`. Each register slot may be written at most
  once per edge update."* Module added to `keiki.cabal`.
- [ ] M2: Refactor `Update` to carry the `(w :: [Symbol])` index.
  Update `UKeep`, `USet`, `UCombine` constructors. Provide a
  migration shim — the smart `combine` exposes the new signature,
  and a temporary `combineE :: Either String (Update rs (Concat w1
  w2) ci)` wrapper for any caller that still needs `Either` (delete
  before M-final).
- [ ] M3: Update `IsLabel` for `Index` (or expose `IndexN` directly)
  so `#email :: Index UserRegRegs Email` continues to compile, but
  resolved against the new `IndexN` shape. The label-driven syntax
  in aggregates must not require a rewrite.
- [ ] M4: Update `evalOut` / `evalPred` / `runUpdate` / `delta` /
  `omega` and the `targets` debug helper as needed. The runtime check
  in `combine` collapses (the invariant is now type-level).
- [ ] M5: Lift `weakenLUpdate` and `substUpdate` in
  `src/Keiki/Composition.hs` to thread the slot-name index. Add the
  `Disjoint (Names rs1) (Names rs2)` constraint to `compose`.
  Replace the line-416 `unsafeCombine` with `combine` (or the
  renamed structural combinator) and confirm it type-checks.
- [ ] M6: Migrate `src/Keiki/Examples/UserRegistration.hs`,
  `src/Keiki/Examples/UserRegistrationV0.hs`, and
  `src/Keiki/Examples/EmailDelivery.hs` from `\`unsafeCombine\`` to
  `\`combine\``.
- [ ] M7: Migrate `test/Keiki/CompositionSpec.hs` from
  `\`unsafeCombine\`` to `\`combine\``.
- [ ] M8: Remove `unsafeCombine` from `Keiki.Core`'s exports and the
  helper itself. If `combineE` was introduced in M2, remove it too.
- [ ] M9: Remove the v1-escape-hatch retirement-block comments
  entirely (the IP-5 sweep) — both in `src/Keiki/Core.hs:22-33` and
  `docs/research/dsl-shape-for-symbolic-register.md:1001-1015`.
  Replace each with a one-line "all retired" pointer to MP-6's
  Outcomes section.
- [ ] M10: Verdict — `cabal build && cabal test all` green,
  symbolic gate green, smoke test green; commit; update MP-6
  registry; write Outcomes & Retrospective entry.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights
discovered during implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Encode written-slot set as `(w :: [Symbol])` (slot
  names) rather than `(w :: [Slot])` (full slot type) or `(w ::
  [Nat])` (slot positions).
  Rationale: Slot names are unique within a `RegFile rs` (the keiki
  invariant) and are decidable for disjointness via `CmpSymbol`.
  Carrying full `[Slot]` adds the value type, which is irrelevant to
  the disjointness check and makes type-level computation noisier.
  Carrying positions is fragile under composition (`weakenLUpdate`
  shifts positions; the equivalence under shifting needs lemmas
  that names don't).
  Date: 2026-05-02

- Decision: `IndexN (s :: Symbol) rs r` as a slot-name-tagged
  variant of `Index rs r` (separate type, mechanically convertible).
  Rationale: The existing `Index rs r` does not carry the slot
  symbol it points at. Adding a phantom `s` requires either changing
  every `Index`-using API or introducing a parallel typed index. The
  parallel index is local to the `USet` constructor and the
  `IsLabel` instance; everything else still uses `Index rs r` (the
  weakening, the existential `Term` reads, etc.). Keeps the diff
  small.
  Alternative considered: a closed type family `SymOf (rs :: [Slot])
  (i :: Nat) :: Symbol` that recovers the slot name from a position.
  Rejected because positions are not stable under composition's
  weakening.
  Date: 2026-05-02

- Decision: Add a `Disjoint (Names rs1) (Names rs2)` constraint to
  `compose` rather than try to derive disjointness from a structural
  Append-of-disjoint lemma.
  Rationale: The composition design note at
  `docs/research/composition-combinators-design.md` already
  documents that `rs1` and `rs2` must have disjoint slot-name domains
  (otherwise label-driven `IsLabel` resolution is ambiguous in the
  appended register file). Promoting this prose precondition to a
  constraint is a one-line change in `compose`'s type and discharges
  the per-edge `Disjoint w1 w2` obligation mechanically.
  Date: 2026-05-02

- Decision: Collapse `combine`'s `Either String` shape; the static
  check makes runtime failure unreachable.
  Rationale: The `Left "combine: overlapping targets at indices..."`
  case becomes statically impossible. Keeping the `Either` for
  back-compat would force every caller to thread the never-fired
  failure through their code. Cleaner to drop it.
  Date: 2026-05-02


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or
at completion. Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

A reader picking up this plan needs:

- **The keiki pure core** lives in `src/Keiki/Core.hs`. The types
  directly affected:

  - `Slot = (Symbol, Type)` at line 106 — a label paired with a
    value type. Slot lists `[Slot]` index `RegFile`s, `Term`s,
    `Update`s, etc.
  - `RegFile (rs :: [Slot])` at lines 112-115 — a heterogeneous tuple
    indexed by `[Slot]`. `RNil` for empty; `RCons (Proxy s) v rest`
    cons.
  - `Index (rs :: [Slot]) (r :: Type)` at lines 119-... — a typed
    pointer into a `RegFile`. `ZIdx` head; `SIdx i` skip.
  - `Update (rs :: [Slot]) (ci :: Type)` at lines 269-272 — the
    copyless update language. After this plan: `Update (rs :: [Slot])
    (w :: [Symbol]) (ci :: Type)`.

  Existing constructors:

      data Update (rs :: [Slot]) (ci :: Type) where
        UKeep    :: Update rs ci
        USet     :: Index rs r -> Term rs ci r -> Update rs ci
        UCombine :: Update rs ci -> Update rs ci -> Update rs ci

  After this plan:

      data Update (rs :: [Slot]) (w :: [Symbol]) (ci :: Type) where
        UKeep    :: Update rs '[] ci
        USet     :: KnownSymbol s
                 => IndexN s rs r -> Term rs ci r -> Update rs '[s] ci
        UCombine :: Disjoint w1 w2
                 => Update rs w1 ci
                 -> Update rs w2 ci
                 -> Update rs (Concat w1 w2) ci

- **The combine functions**:

  - `combine :: Update rs ci -> Update rs ci -> Either String
    (Update rs ci)` at lines 277-283 — runtime check. After this
    plan its signature becomes the constraint-based static form
    above; the body becomes `combine = UCombine` (the constraint
    discharge happens at the type level).
  - `unsafeCombine :: Update rs ci -> Update rs ci -> Update rs ci`
    at lines 289-290. Removed by this plan.
  - `targets :: Update rs ci -> [Int]` at lines 293-296. The
    runtime helper used by `combine` for overlap detection. Removed
    by this plan (or kept as `targetsN :: Update rs w ci -> [Symbol]`
    if any debug consumer needs it; check before removal).

- **`IsLabel` for `Index`**. The `IsLabel` instance for `Index` is
  declared at... TBD; search `instance IsLabel s (Index rs r)` in
  `Keiki.Core`. After this plan there is also (or instead) an
  `IsLabel s (IndexN s rs r)` instance so the existing label syntax
  `#email :: IndexN "email" UserRegRegs Email` resolves through the
  new shape. The aggregate authoring syntax does not change at the
  use site.

- **The composition module** at `src/Keiki/Composition.hs`. The
  affected functions:

  - `weakenLUpdate :: Update rs1 ci -> Update (Append rs1 rs2) ci`
    at lines 142-149. After this plan:

        weakenLUpdate
          :: forall rs1 rs2 w ci.
             Update rs1 w ci -> Update (Append rs1 rs2) w ci

    The slot-name index passes through unchanged because weakening
    adds slots but does not change the names of the slots written.

  - `substUpdate :: Update rs2 mid -> OutTerm rs1 ci1 mid -> Update
    (Append rs1 rs2) ci1` at lines 273-283. After this plan:

        substUpdate
          :: forall rs1 rs2 w ci1 mid.
             WeakenR rs1
          => Update rs2 w mid
          -> OutTerm rs1 ci1 mid
          -> Update (Append rs1 rs2) w ci1

  - `compose` at lines 362-... gains the constraint `Disjoint (Names
    rs1) (Names rs2)` where `Names :: [Slot] -> [Symbol]` is a closed
    type family that projects the slot names from a `[Slot]` list.

  - The line-416 `unsafeCombine` is replaced with `combine`. Because
    `update e1`'s written-slot set `w1 ⊆ Names rs1`, `update e2`'s
    written-slot set `w2 ⊆ Names rs2`, and `Disjoint (Names rs1)
    (Names rs2)`, GHC discharges the `Disjoint w1 w2` constraint on
    `combine` mechanically via a small auxiliary lemma class.

  An auxiliary lemma class is needed:

      class SubsetOf (sub :: [Symbol]) (super :: [Symbol])

  with instances showing each constructor of `Update rs w ci`
  produces a `w ⊆ Names rs`. Then `Disjoint a b` plus `SubsetOf x a`
  plus `SubsetOf y b` yields `Disjoint x y`. The exact shape of the
  lemma class is a small type-level engineering task; M5 of this
  plan owns it.

- **The example aggregates** at:

  - `src/Keiki/Examples/UserRegistration.hs` — three uses across two
    edges. Lines 296-303 (PotentialCustomer → Registering): three
    `USet`s combined; lines 348-352 (RequiresConfirmation → resend):
    two `USet`s combined.
  - `src/Keiki/Examples/UserRegistrationV0.hs` — three uses, mirror
    of V5.
  - `src/Keiki/Examples/EmailDelivery.hs` — two uses, three `USet`s
    combined on the email-pending edge.

  All chains are between `USet`s with distinct labels (`#email`,
  `#confirmCode`, `#registeredAt` etc.) — the `Disjoint` constraint
  is satisfied trivially at the type level. The migration is a
  search-and-replace of `\`unsafeCombine\`` to `\`combine\`` (no
  other syntax changes).

- **The composition tests** at `test/Keiki/CompositionSpec.hs` lines
  ~123-126 use `\`unsafeCombine\`` in a fixture. Same migration.

- **The retirement-block comments** in `src/Keiki/Core.hs:22-33`
  and `docs/research/dsl-shape-for-symbolic-register.md:1001-1015`.
  After EP-16 and EP-17 land before this plan, those blocks contain
  only the `unsafeCombine` bullet. This plan removes the entire
  block (per MP-6's IP-5: the *last* per-retirement EP performs the
  IP-5 sweep). Replace with a one-line "all v1 escape hatches
  retired by MP-6 (see `docs/masterplans/6-...md` Outcomes
  section)".

Terms of art used in this plan:

- **Slot-name set.** A `[Symbol]` type-level list recording the
  unique slot names a value writes. The keiki invariant is that
  `RegFile rs` slot names are pairwise distinct (the `Symbol`
  identity), so a `[Symbol]` set is a faithful disjointness witness.
- **`Disjoint` constraint.** A closed type family on two `[Symbol]`
  lists that produces a `Constraint`. Implementation uses
  `CmpSymbol` (GHC's built-in) to decide pairwise inequality at
  compile time. On overlap, the constraint cannot be discharged and
  GHC produces an error naming the offending symbol.
- **`Concat`.** Standard type-level list concatenation, equivalent
  to `Data.Type.List.++`. Used to compute the written-slot set of
  `UCombine` from its operands.
- **`IndexN s rs r`.** A slot-name-tagged variant of `Index rs r`.
  The phantom `s :: Symbol` lets `USet`'s GADT signature recover the
  slot name from the index value at the type level.
- **`Names`.** A closed type family `[Slot] -> [Symbol]` that
  projects slot names from a slot list. Used in the `Disjoint (Names
  rs1) (Names rs2)` constraint on `compose`.
- **`SubsetOf`.** An auxiliary class that witnesses one `[Symbol]`
  set is a subset of another. Used as a lemma between an `Update`'s
  written-slot set and the slot-name domain of its register file.


## Plan of Work

The work spans ten milestones because each phase has its own
verification step and the encoding decisions cascade.

### M0 — Prerequisites

Verify the working tree builds and tests pass:

    cabal build
    cabal test all

Acceptance: green; record the test count (which will be M0's
baseline minus EP-16's removed cases minus EP-17's removed case if
those landed first).

### M1 — Spike: Disjoint, Concat, IndexN

Implement the type-level machinery in isolation. A natural home is a
new module `src/Keiki/Internal/Slots.hs` that exports:

    type family Concat (xs :: [Symbol]) (ys :: [Symbol]) :: [Symbol]
    type family Member  (x  :: Symbol)   (ys :: [Symbol]) :: Bool
    type family Disjoint (xs :: [Symbol]) (ys :: [Symbol]) :: Constraint
    type family Names   (rs :: [Slot])   :: [Symbol]

    data IndexN (s :: Symbol) (rs :: [Slot]) (r :: Type) where
      IZ :: IndexN s ('(s, r) ': rs) r
      IS :: IndexN s rs r -> IndexN s ('(s', r') ': rs) r

`Disjoint` should be a closed type family that pattern-matches on
the first list, recursing while asserting `Member x ys ~ 'False`
via constraint reduction. Use GHC's `TypeError` to produce a
readable message on overlap.

Test the spike with a small standalone GHC `:type` session or a
throwaway test file: deliberately combine `Update rs '["foo"] ci`
and `Update rs '["foo"] ci` and confirm GHC rejects it.

This milestone produces source code in
`src/Keiki/Internal/Slots.hs`. Subsequent milestones consume it.

Acceptance: `cabal build keiki:lib` succeeds with the new module;
the spike test snippet (paste-into-`ghci`) demonstrates the
disjointness check fires at compile time.

### M2 — Refactor `Update` to carry the `(w :: [Symbol])` index

Edit `src/Keiki/Core.hs`:

1. Replace the `Update (rs :: [Slot]) (ci :: Type)` declaration
   with the indexed form:

       data Update (rs :: [Slot]) (w :: [Symbol]) (ci :: Type) where
         UKeep    :: Update rs '[] ci
         USet     :: KnownSymbol s
                  => IndexN s rs r -> Term rs ci r -> Update rs '[s] ci
         UCombine :: Disjoint w1 w2
                  => Update rs w1 ci
                  -> Update rs w2 ci
                  -> Update rs (Concat w1 w2) ci

2. Update the smart `combine`:

       combine :: Disjoint w1 w2
               => Update rs w1 ci
               -> Update rs w2 ci
               -> Update rs (Concat w1 w2) ci
       combine = UCombine

   The `Either String` shape and the `targets` overlap-check are
   gone.

3. Mark `unsafeCombine` for removal (by M8). For now leave it but
   note in a Haddock that it will be gone — alternatively, remove it
   immediately in this milestone if the call sites can absorb the
   migration in M5–M7. The conservative path is to leave it and
   delete in M8; the aggressive path leaves an intermediate state
   that does not compile until M5–M7 land. Pick the conservative
   path: keep `unsafeCombine` available as `unsafeCombine :: Update
   rs w1 ci -> Update rs w2 ci -> Update rs (Concat w1 w2) ci`
   without the `Disjoint` constraint (still unsound; still flagged
   as the v1 escape hatch).

4. Update `runUpdate` (the evaluator) to handle the new `Update rs w
   ci` shape. The runtime semantics is unchanged (the `w` index is
   phantom for evaluation purposes); only the type signature
   changes.

5. Update the Haddock at the `Update` declaration to explain the new
   `w` index.

After this milestone:

    cabal build keiki:lib

Will fail in `Keiki.Composition` and the example aggregates because
the `IsLabel` resolution and the `weakenLUpdate` / `substUpdate`
signatures need updates (M3 / M5). That's expected; M2 is a
mid-migration state. Use `--keep-going` if you want to see all
errors at once.

### M3 — `IsLabel` for `IndexN`

Edit `src/Keiki/Core.hs` (or wherever the existing `IsLabel
(Index rs r)` instance lives) to add an `IsLabel` instance for
`IndexN s rs r` so label-driven authoring continues to work:

    instance (HasIndexN s rs r, KnownSymbol s)
          => IsLabel s (IndexN s rs r) where
      fromLabel = indexN @s @rs @r

where `HasIndexN` is the slot-name-driven analogue of the existing
`HasIndex` class. The exact class shape mirrors `HasIndex` with the
slot symbol baked in as a class parameter.

The existing `instance IsLabel s (Index rs r)` should keep
working for code that still uses positional indices (e.g.
field-level `Index ifs r` reads from an `InCtor`'s slot list).

After this milestone:

    cabal build keiki:lib

Should compile through `Keiki.Core`. The aggregates and
`Keiki.Composition` may still fail.

### M4 — Update evaluator / analyses

Edit `src/Keiki/Core.hs` for any function that case-matches on
`Update`:

- `runUpdate` evaluates the update against a register file and
  input. Match against the new constructor shapes; the runtime
  semantics is unchanged.
- `delta` (the transition relation) consumes `Update` via
  `runUpdate`; its type signature gains the `w` index implicitly via
  the `Edge` type.

Edit `src/Keiki/Core.hs`'s `Edge` type:

    data Edge phi rs ci co s = Edge
      { guard  :: phi
      , update :: Update rs w ci   -- NEW: existential w
      , output :: Maybe (OutTerm rs ci co)
      , target :: s
      }

Wait — this is the load-bearing decision. If `Edge` carries the
`w` index, every `[Edge ...]` list in `edgesOut` must agree on `w`,
which is impossible because each edge writes a different set of
slots. The right shape is to **existentially quantify `w` in the
`Edge` record**:

    data Edge phi rs ci co s where
      Edge :: { guard  :: phi
              , update :: Update rs w ci
              , output :: Maybe (OutTerm rs ci co)
              , target :: s
              } -> Edge phi rs ci co s

(GADT record syntax). The `w` index disappears at the `Edge`
boundary; it is observable only to the constructor of an `Update`
value, which is exactly where the disjointness check is needed.

The `runUpdate` and `delta` consumers see `update :: Update rs w
ci` for some `w`; they don't read `w`, so the existential is fine.
`combine` and the constructors see `w` because they are the only
producers.

The `targets :: Update rs ci -> [Int]` debug helper either:

(a) becomes `targets :: forall rs w ci. KnownSlotNames w => Update
rs w ci -> [Symbol]` (returning slot names rather than positions) —
or
(b) is removed because it was only used by the runtime `combine`
check (now gone).

Pick (b) unless a downstream consumer (`checkHiddenInputs`?) uses
it. Audit for callers; remove if unused.

After this milestone:

    cabal build keiki:lib

Should succeed for `Keiki.Core`. The aggregates and
`Keiki.Composition` are still WIP.

### M5 — Lift `weakenLUpdate` / `substUpdate`; add `Disjoint` to `compose`

Edit `src/Keiki/Composition.hs`:

1. Update `weakenLUpdate`:

       weakenLUpdate
         :: forall rs1 rs2 w ci.
            Update rs1 w ci -> Update (Append rs1 rs2) w ci
       weakenLUpdate UKeep          = UKeep
       weakenLUpdate (USet ix t)    = USet (weakenIndexN @rs1 @rs2 ix)
                                            (weakenLTerm @rs1 @rs2 t)
       weakenLUpdate (UCombine a b) = UCombine (weakenLUpdate @rs1 @rs2 a)
                                                (weakenLUpdate @rs1 @rs2 b)

   `weakenIndexN` is the slot-name-tagged analogue of the existing
   `weakenL` helper; it preserves the slot symbol while extending
   the slot list. The `Disjoint`-witnessing constraint on `UCombine`
   is preserved by GHC (the `w1` / `w2` instances of `weakenLUpdate`
   carry the same slot names as their inputs).

2. Update `substUpdate`:

       substUpdate
         :: forall rs1 rs2 w ci1 mid.
            WeakenR rs1
         => Update rs2 w mid
         -> OutTerm rs1 ci1 mid
         -> Update (Append rs1 rs2) w ci1
       substUpdate UKeep            _o1 = UKeep
       substUpdate (USet ix2 t)      o1 = USet (weakenRIndexN @rs1 ix2)
                                                (substTerm @rs1 @rs2 t o1)
       substUpdate (UCombine a b)    o1 = UCombine (substUpdate @rs1 @rs2 a o1)
                                                    (substUpdate @rs1 @rs2 b o1)

3. Update `compose`'s constraint set:

       compose
         :: forall rs1 rs2 s1 s2 ci1 mid co.
            ( WeakenR rs1
            , Disjoint (Names rs1) (Names rs2)
            )
         => SymTransducer (HsPred rs1 ci1) rs1 s1 ci1 mid
         -> SymTransducer (HsPred rs2 mid) rs2 s2 mid co
         -> SymTransducer (HsPred (Append rs1 rs2) ci1)
                          (Append rs1 rs2)
                          (Composite s1 s2)
                          ci1
                          co

4. Update line-416 in `productEdge`:

       , update = combine
                    (weakenLUpdate @rs1 @rs2 (update e1))
                    (substUpdate   @rs1 @rs2 (update e2) o1)

   GHC needs to discharge `Disjoint w1 w2` where `w1` is the
   written-slot set of `weakenLUpdate (update e1)` and `w2` is that
   of `substUpdate (update e2) o1`. The auxiliary lemma:

       class WrittenSubset (rs :: [Slot]) (w :: [Symbol]) | w -> rs
       instance WrittenSubset rs '[]
       instance ... -- one per Update constructor

   gives `w1 ⊆ Names rs1` and `w2 ⊆ Names rs2`, and `Disjoint
   (Names rs1) (Names rs2)` (from `compose`'s constraint) implies
   `Disjoint w1 w2`. If the auxiliary class is too painful to wire
   up, the alternative is to expose `Disjoint w1 w2` as a constraint
   on the `productEdge` helper directly and let `compose` carry it
   transitively. M5 owns the precise shape.

After this milestone:

    cabal build keiki:lib

Expected: success.

### M6 — Migrate the example aggregates

For each of `src/Keiki/Examples/UserRegistration.hs`,
`src/Keiki/Examples/UserRegistrationV0.hs`, and
`src/Keiki/Examples/EmailDelivery.hs`:

1. Replace every `\`unsafeCombine\`` with `\`combine\``.
2. The label-driven `USet (#name :: Index UserRegRegs Type) ...`
   syntax should continue to work because of M3's `IsLabel` for
   `IndexN`. If the type annotation needs to become `IndexN
   "name" UserRegRegs Type` rather than `Index UserRegRegs Type`,
   update the explicit annotation. The shorthand `#name` (without
   annotation) should resolve through the new instance directly.

After this milestone:

    cabal build keiki:lib
    cabal test keiki:keiki-test 2>&1 | tail -30

Expected: green. The User Registration smoke test
(`reconstitute userReg canonicalLog == Just (Deleted,
expectedSnapshot)`) and the symbolic gate
(`isSingleValuedSym (withSymPred userReg) == True`) both pass.

### M7 — Migrate composition tests

Edit `test/Keiki/CompositionSpec.hs`. Lines ~123-126 use
`\`unsafeCombine\``; replace with `\`combine\``.

After this milestone:

    cabal test keiki:keiki-test

Expected: green.

### M8 — Remove `unsafeCombine`

Edit `src/Keiki/Core.hs`:

1. Remove `unsafeCombine` from the export list (line 52).
2. Remove the `unsafeCombine :: ...` signature and body (lines
   289-290).
3. If any test code or internal helper still refers to it, audit and
   migrate (`grep -rn "unsafeCombine"` should now return zero hits in
   `src/` and `test/`).

After this milestone:

    cabal build
    cabal test all

Expected: green.

### M9 — Sweep the v1-escape-hatch retirement-block comments

This is MP-6's IP-5 sweep, owned by the last per-retirement EP.
After EP-16 and EP-17 land (which trim their own bullets), and
after this plan removes the `unsafeCombine` bullet, the block in
`src/Keiki/Core.hs:22-33` reads as a header with one (or zero, by
this point) bullets. Remove the entire block; replace with a single
Haddock line:

    -- All v1 escape hatches were retired by MasterPlan 6 (see the
    -- Outcomes section of
    -- @docs/masterplans/6-retire-remaining-v1-escape-hatches-in-pure-core-ofn-pmatchc-unsafecombine-static-check.md@).

Same treatment for the closing block in
`docs/research/dsl-shape-for-symbolic-register.md:1001-1015`:
replace with one short paragraph saying the retirement is complete
and pointing at MP-6's Outcomes section.

This is documentation only. No behavioural change.

### M10 — Verdict

Run the full suite:

    cabal build
    cabal test all

Acceptance:

- All examples pass.
- The User Registration smoke test passes.
- The symbolic gate `isSingleValuedSym (withSymPred userReg) ==
  True` passes.
- `Keiki.Core` no longer exports `unsafeCombine`.
- `grep -rn "unsafeCombine" src/ test/` returns nothing.
- Deliberate negative test: introduce a temporary edge writing
  `USet #email t1 \`combine\` USet #email t2`; verify GHC rejects it
  with a `Disjoint` error mentioning `"email"`. Roll back the
  negative-test edit before committing.

Commit. Update MP-6's Exec-Plan Registry to mark this plan
**Complete**. Mark MP-6 itself complete (since EP-18 is the last
child plan in the registry as of 2026-05-02; if other EPs are
added later, MP-6 stays In Progress). Write the Outcomes &
Retrospective entry for both EP-18 and MP-6.


## Concrete Steps

Run from the repository root.

M0:

    cabal build
    cabal test all

M1 — spike test (after writing `Keiki.Internal.Slots`):

    cabal build keiki:lib
    # Optional: paste a deliberate-overlap snippet into ghci:
    #   :type combine (USet @"foo" ...) (USet @"foo" ...)
    # Expect: GHC rejects with a Disjoint constraint failure.

M2-M9 — incremental compilation checks:

    cabal build keiki:lib

After M6 and M7:

    cabal test keiki:keiki-test 2>&1 | tail -30

After M10:

    cabal build
    cabal test all
    grep -rn "unsafeCombine" src/ test/
    # expect: empty

Commit (with `MasterPlan:`, `ExecPlan:`, and `Intention:` trailers
per the master-plan / exec-plan skill protocols).


## Validation and Acceptance

After M10, the user should observe:

- `cabal build` produces no warnings related to `unsafeCombine`.
- `cabal test all` is green; all 100+ examples pass (count is M0's
  baseline; this plan does not add or remove tests, only migrates
  fixtures).
- The User Registration smoke-test transcript is unchanged:

      reconstitute userReg canonicalLog == Just (Deleted, expectedSnapshot)

- The symbolic-gate transcript is unchanged:

      isSingleValuedSym (withSymPred userReg) == True

- A user attempting to write `USet #email t1 \`combine\` USet #email
  t2` gets a compile error of the form (exact wording depends on the
  `TypeError` text chosen in M1):

      Cannot satisfy: Disjoint '["email"] '["email"]
      • In an expression: combine (USet #email t1) (USet #email t2)
      • The slot "email" is written by both halves.

- A user attempting to import `unsafeCombine` from `Keiki.Core`
  gets *"Module 'Keiki.Core' does not export 'unsafeCombine'"*.

- The `Keiki.Composition.compose` algorithm at line 416 (or its new
  line number after the refactor) uses the smart `combine` and
  type-checks without per-call-site proof obligations.


## Idempotence and Recovery

This plan is the largest of MP-6's three retirements; some
milestones touch broad swaths of code. Recovery strategies:

- **M1 (spike).** Local to a new file. `git checkout --
  src/Keiki/Internal/Slots.hs` resets fully.
- **M2 (Update refactor).** The change is to one datatype and its
  evaluator. If GHC's error messages become unmanageable, revert the
  GADT change and reintroduce the `w` index incrementally (e.g.
  start with `Update rs '[] ci` everywhere and add real instances
  for `USet` / `UCombine` after).
- **M5 (composition lift).** The auxiliary `WrittenSubset` lemma
  class is the trickiest piece. If it cannot be made to discharge
  the `Disjoint w1 w2` constraint mechanically, fall back to a more
  explicit shape: have `productEdge` carry an explicit `Disjoint w1
  w2` constraint and let `compose`'s constraint set propagate it.
- **M6 / M7 (aggregate / test migration).** Pure
  search-and-replace; trivially redoable.
- **M8 (delete `unsafeCombine`).** If a hidden caller surfaces, add
  it to M6 / M7 and retry.

There is no destructive-operation hazard. All changes are local
source edits. The User Registration smoke test and the symbolic gate
are the load-bearing acceptance gates; if either regresses, bisect
between milestones.


## Interfaces and Dependencies

After this plan, the following must hold:

- `src/Keiki/Internal/Slots.hs` (new) exports:
  - `type family Concat (xs :: [Symbol]) (ys :: [Symbol]) :: [Symbol]`
  - `type family Member (x :: Symbol) (ys :: [Symbol]) :: Bool`
  - `type family Disjoint (xs :: [Symbol]) (ys :: [Symbol]) :: Constraint`
  - `type family Names (rs :: [Slot]) :: [Symbol]`
  - `data IndexN (s :: Symbol) (rs :: [Slot]) (r :: Type)`
  - The auxiliary `HasIndexN s rs r` class for label-driven authoring.

- `Keiki.Core` exports:
  - `Update (rs :: [Slot]) (w :: [Symbol]) (ci :: Type)` with
    constructors `UKeep`, `USet`, `UCombine` per the Plan of Work.
  - `combine :: Disjoint w1 w2 => Update rs w1 ci -> Update rs w2
    ci -> Update rs (Concat w1 w2) ci`.
  - **No** `unsafeCombine`.
  - **No** `targets` runtime helper (unless retained for an
    audited debug consumer).

- `Keiki.Composition`:
  - `weakenLUpdate` and `substUpdate` thread the `(w :: [Symbol])`
    index per the Plan of Work.
  - `compose` carries the constraint `Disjoint (Names rs1) (Names
    rs2)` in addition to its existing `WeakenR rs1`.
  - The composite `update` field at line 416 (or new equivalent)
    uses `combine`, not `unsafeCombine`.

- `src/Keiki/Examples/UserRegistration.hs`,
  `src/Keiki/Examples/UserRegistrationV0.hs`, and
  `src/Keiki/Examples/EmailDelivery.hs` use `\`combine\``, not
  `\`unsafeCombine\``.

- `test/Keiki/CompositionSpec.hs` uses `\`combine\``.

Hard dependencies:

- **None at the source level.** EP-18 can land before or after
  EP-16 and EP-17; the only sequencing constraint is M9 (the
  retirement-block sweep), which assumes all three retirements have
  landed before the block becomes empty. If EP-18 lands first, M9
  trims the `unsafeCombine` bullet and leaves `OFn` / `PMatchC`
  bullets for EP-16 / EP-17 to remove (re-coordinating IP-5 owners
  via a small note in MP-6's Decision Log).

Soft dependencies:

- **EP-15** — its design note at
  `docs/research/v1-escape-hatch-retirements-design.md` is the
  encoding rationale.
- **EP-7** (`docs/plans/7-upgrade-keiki-to-ghc-9-12.md`) — GHC
  9.12.3 is on master; the type-level set machinery this plan
  introduces relies on GHC 9.12's `CmpSymbol` and `TypeError`
  features, which are stable from much earlier GHC versions but
  benefit from 9.12's improved error messages.
- **MP-4 children** — MP-4 owns composition combinators. EP-11
  (already complete) introduced the line-416 `unsafeCombine` use.
  Future MP-4 combinators (`feedback`, `alternative`, ...) that use
  `unsafeCombine` internally must be migrated alongside this plan
  if they land before M5.

Out of scope:

- Item G of `docs/research/keiki-generics-design.md` —
  compile-time topology safety via a `SymTransducerStrict`
  parameterized over a type-level topology. The `Disjoint`-on-
  `compose` constraint is a narrow, mechanical addition; it does
  not embark on the topology-safety redesign.
