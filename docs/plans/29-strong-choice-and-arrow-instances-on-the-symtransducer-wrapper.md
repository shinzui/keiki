---
id: 29
slug: strong-choice-and-arrow-instances-on-the-symtransducer-wrapper
title: "Strong, Choice, and Arrow instances on the SymTransducer wrapper"
kind: exec-plan
created_at: 2026-05-03T03:16:29Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
master_plan: "docs/masterplans/9-profunctor-and-category-instances-on-symtransducer.md"
---

# Strong, Choice, and Arrow instances on the SymTransducer wrapper

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

After this plan ships, a keiki user can write the standard `Strong`,
`Choice`, and `Arrow` combinators on `SomeSymTransducer` (the
existential wrapper introduced in
`docs/plans/27-existential-wrapper-for-symtransducer-plus-profunctor-instance-and-variance-combinators.md`):

    -- Strong: thread an unrelated value `c` through a transducer that
    -- only knows about `a -> b`.
    routedFirst :: SomeSymTransducer (EmailCmd, RequestId) (EmailEvent, RequestId)
    routedFirst = first' (someSymTransducer emailDelivery)

    -- Choice: dispatch on Either, picking the appropriate transducer arm.
    routedChoice :: SomeSymTransducer (Either EmailCmd PingCmd) (Either EmailEvent PingEvent)
    routedChoice = someSymTransducer emailDelivery +++ someSymTransducer pinger

    -- Arrow: lift a pure function as a stateless transducer.
    embedded :: SomeSymTransducer Int Text
    embedded = arr (Text.pack . show)

These three classes round out the keiki/crem parity story for the
`profunctors` ecosystem (see
`docs/research/architecture-comparison-keiki-vs-crem.md`'s
named gaps).

The user-visible deliverable is verified by:

    cabal test keiki-test --test-show-details=direct

passing the new `Keiki.Profunctor (Strong/Choice/Arrow)` describe
block, which exercises each instance against the existing example
aggregates.

This is the most speculative of MP-9's three EPs. Two design hazards
to confront up front:

1.  The `Strong` instance was originally meant to delegate to
    `Keiki.Composition.parallel`. **`parallel` was re-deferred by
    MP-8's design milestone** (`docs/plans/24-composition-combinators-beyond-sequential-design-milestone.md`,
    Status: Complete) and is not coming. M2 below implements a
    one-off `firstSym` directly rather than depending on `parallel`.

2.  The `Arrow` typeclass requires `arr :: (b -> c) -> arr b c` —
    lifting an arbitrary Haskell function. This is technically
    feasible (a one-edge transducer whose `WireCtor.wcBuild` calls
    the function) but `arr`-produced transducers cannot be inverted
    by `solveOutput` (no inverse function in general). M3 ships
    `arr` with this caveat documented; the same lossy-`solveOutput`
    contract that EP-27 set for `lmapCi`/`rmapCo` covers `arr` too.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] M0: Verify EP-27 + EP-28 have shipped; confirm `Keiki.Composition.alternative` is exported and Category instance works
- [ ] M0: Record current test count baseline
- [ ] M1: Choice instance — delegate `(+++)` and `(|||)` to `Keiki.Composition.alternative`; add `left'` and `right'` via lifting helpers
- [ ] M1: Spec for Choice (left', right', +++, |||) on EmailDelivery + Pinger fixture
- [ ] M2: Strong instance — implement a one-off `firstSym` on the concrete `SymTransducer` type that threads an unrelated `c` through unchanged
- [ ] M2: Strong instance — define `first'` and `second'` on the wrapper, delegating to `firstSym` (and a symmetric `secondSym = swap . first' . swap` shortcut)
- [ ] M2: Spec for Strong (first', second') on EmailDelivery threading a `RequestId` through
- [ ] M3: Arrow instance — `arr` via a stateless one-edge transducer; `(>>>)` and `first` delegate to Category and Strong
- [ ] M3: Spec for Arrow (arr, >>>, first); ArrowChoice in scope only if MP-8 ships a Kleisli-shaped helper (otherwise out of scope per Decision Log)
- [ ] M3: Update MP-9 Progress section, mark this EP Complete in registry, fill in Outcomes & Retrospective
- [ ] M3: Update `docs/research/architecture-comparison-keiki-vs-crem.md` "DX gaps" section to record the parity is now closed (modulo arr-inversion caveat)


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- 2026-05-03 / authoring: MP-8's design milestone (EP-24, Complete on
  2026-05-03) **declined `parallel`** as a separate combinator —
  the rationale was that `alternative` subsumes `parallel` for
  keiki's runtime model (where commands arrive serially, never in
  pairs). MP-9's vision in `docs/masterplans/9-...` Section 7 of
  Decomposition Strategy assumed `parallel` would ship and that
  `Strong` would delegate to it. Without `parallel`, `Strong`
  must be implemented from primitives. The implementation is
  tractable (one-off `firstSym`) but the EP's M2 is now
  load-bearing rather than a delegation. Documented in Decision Log.

- 2026-05-03 / authoring: `Keiki.Core.Term` has no `TPure :: (a ->
  b) -> Term rs ci a -> Term rs ci b` constructor — i.e. no way
  to apply an arbitrary Haskell function inside a `Term`. This is
  intentional: `Keiki.Symbolic.translateTermSym` walks `Term`'s
  closed AST to compile to SBV, and an opaque function would be
  un-translatable. For the Arrow instance's `arr`, we side-step
  this by putting the Haskell function inside the `WireCtor.wcBuild`
  field instead — `wcBuild` is invoked only at runtime (during
  forward output construction), never by `translateTermSym`. The
  symbolic-analysis path remains intact for `arr`-produced
  transducers' guards (which are all `PTop`), but
  `solveOutput` cannot invert through an opaque function. This is
  the same lossy-`solveOutput` contract EP-27 set for
  `lmapCi`/`rmapCo`; reuse the haddock language.


## Decision Log

Record every decision made while working on the plan.

- Decision: Implement `firstSym` from primitives rather than wait
  for or revive `Keiki.Composition.parallel`.
  Rationale: MP-8's design milestone declined `parallel`. Reviving
  it here would require re-opening MP-8's design decision; that's
  out of MP-9's scope. The one-off `firstSym` is small (~40 LoC)
  and has a narrower surface than full `parallel` (only handles
  the `(a, c) -> (b, c)` pattern, not arbitrary product
  composition).
  Date: 2026-05-03

- Decision: `ArrowChoice` is **out of scope** for this plan.
  Rationale: `ArrowChoice` requires a `+++`-style operator on
  Arrows. We get `+++` for free via the Choice instance (`(+++) =
  arrowChoiceFromChoice`-shape derivation), but the
  `ArrowChoice` typeclass also pulls in `arr (Either b c -> Either
  b c)` requirements that interact with `arr`'s lossy contract in
  ways that complicate the test surface. Defer to a future plan
  that wants both at once.
  Date: 2026-05-03


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

This plan extends `Keiki.Profunctor` with three more typeclass
instances. Read the "Context and Orientation" sections of
`docs/plans/27-existential-wrapper-for-symtransducer-plus-profunctor-instance-and-variance-combinators.md`
*and*
`docs/plans/28-category-instance-on-the-symtransducer-wrapper.md`
first if you do not have keiki context — they cover `SymTransducer`,
the variance story, the wrapper's existential constraints, the
identity transducer, and the disjointness escape hatch. The summary
below names only what this plan adds.

### What's already in `Keiki.Profunctor`

After EP-27 and EP-28 ship:

- `data SomeSymTransducer ci co where
    SomeSymTransducer
      :: ( WeakenR rs, KnownSlotNames rs )
      => SymTransducer (HsPred rs ci) rs s ci co
      -> SomeSymTransducer ci co`
  (the existential wrapper, with the EP-28 amendment to pack
  `KnownSlotNames`).
- `someSymTransducer` smart constructor.
- `lmapCi`, `rmapCo`, `dimapTransducer`, `lmapMaybeCi` standalone
  combinators on the concrete type (lossy on `solveOutput`).
- `Profunctor SomeSymTransducer` and `Functor (SomeSymTransducer ci)`
  instances.
- `IdVertex`, `identityTransducer`, `identityInCtor`,
  `identityWireCtor` (from EP-28; `identityTransducer` is exported,
  the InCtor/WireCtor helpers are private — re-export them in M3
  if `arr` needs them).
- `Control.Category.Category SomeSymTransducer` instance
  (with the runtime overlap check for slot-name disjointness).
- Internal `unsafeCoerceDisjointness` and `CategoryOverlapError`
  (the latter exported; the former private).

### `Keiki.Composition.alternative`

The Choice instance delegates to this combinator. From
`src/Keiki/Composition.hs`:

    alternative
      :: forall rs1 rs2 s1 s2 ci1 ci2 co1 co2.
         ( WeakenR rs1
         , Disjoint (Names rs1) (Names rs2)
         )
      => SymTransducer (HsPred rs1 ci1) rs1 s1 ci1 co1
      -> SymTransducer (HsPred rs2 ci2) rs2 s2 ci2 co2
      -> SymTransducer (HsPred (Append rs1 rs2) (Either ci1 ci2))
                       (Append rs1 rs2)
                       (Composite s1 s2)
                       (Either ci1 ci2)
                       (Either co1 co2)

Same `Disjoint` constraint pattern as `compose` — solved at the
wrapper boundary by the same `unsafeCoerceDisjointness` mechanism
EP-28 introduced.

### What is needed but does not exist

`parallel` (a `(a, c) -> (b, d)` combinator running two transducers
in lockstep on a pair input) is **not** shipped by MP-8 (EP-24
declined it as a separate combinator; see `docs/plans/24-...`'s
Decision Log entry "parallel — re-deferred"). M2 implements a
narrower one-off `firstSym :: SymTransducer ... a b -> SymTransducer
... (a, c) (b, c)` directly.

`Kleisli` (a wrapping enabling effectful monadic composition) is
also not shipped by MP-8 and is out of scope here per MP-9's
"Out of scope" list.

### `Strong`, `Choice`, `Arrow` typeclass shapes

From the `profunctors` package
(`Data.Profunctor.Strong`, `Data.Profunctor.Choice`) and
`Control.Arrow`:

    class Profunctor p => Strong p where
      first'  :: p a b -> p (a, c) (b, c)
      second' :: p a b -> p (c, a) (c, b)

    class Profunctor p => Choice p where
      left'  :: p a b -> p (Either a c) (Either b c)
      right' :: p a b -> p (Either c a) (Either c b)

    class Category arr => Arrow arr where
      arr    :: (b -> c) -> arr b c
      first  :: arr b c -> arr (b, d) (c, d)
      -- second / *** / &&& have default impls

`Choice` has the `(+++)` and `(|||)` operators as defaults via
`first'` / `right'` plumbing; we get those for free once `left'`
and `right'` are defined.


## Plan of Work

The work decomposes into four milestones — M0 (prereqs), M1 (Choice),
M2 (Strong), M3 (Arrow). M1 lands first because it has the cleanest
delegation path; M2 is the most novel work; M3 unlocks once Category
(EP-28) and Strong (M2) are in.

### M0 — Verify prerequisites

Scope: confirm EP-27 and EP-28 have shipped (so the wrapper, the
Category instance, the identity transducer, and the disjointness
escape hatch are all in place); confirm `Keiki.Composition.alternative`
is exported.

Commands from `/Users/shinzui/Keikaku/bokuno/keiki/`:

    cabal build all
    cabal test keiki-test --test-show-details=direct 2>&1 | tail -30
    grep -n "alternative\|^identityTransducer\|instance.*Category SomeSymTransducer" \
         src/Keiki/Composition.hs src/Keiki/Profunctor.hs

Acceptance: build and test pass; the grep returns matches for all
three identifiers. Record the test count in Surprises & Discoveries.

### M1 — Choice instance

Scope: add `Choice SomeSymTransducer` to `Keiki.Profunctor`
delegating to `Keiki.Composition.alternative`. Add a spec
exercising `left'`, `right'`, `(+++)`, and `(|||)`.

What will exist at the end:

1.  In `src/Keiki/Profunctor.hs`:

        import Data.Profunctor (Choice (..))
        import Keiki.Composition (alternative)

        instance Choice SomeSymTransducer where
          left' (SomeSymTransducer t) =
            -- left' :: p a b -> p (Either a c) (Either b c)
            -- For c = an arbitrary type, we need a transducer that
            -- consumes Either a c and emits Either b c, where:
            --   * Left a inputs go through t producing Left b
            --   * Right c inputs pass through unchanged
            -- This is exactly `alternative t (identityTransducer @c)`
            -- modulo the disjointness check.
            case unsafeCoerceDisjointness :: DictDisjoint (Names rs) (Names '[]) of
              DictDisjoint -> SomeSymTransducer (alternative t identityTransducer)

          right' (SomeSymTransducer t) =
            case unsafeCoerceDisjointness :: DictDisjoint (Names '[]) (Names rs) of
              DictDisjoint -> SomeSymTransducer (alternative identityTransducer t)

    The `Disjoint (Names rs) (Names '[])` constraint reduces to `()`
    by the type-family base case (`Disjoint xs '[]` walks `xs` against
    empty membership which is trivially true), so the
    `unsafeCoerceDisjointness` is *technically* unnecessary here —
    GHC should solve the constraint automatically. Try without it
    first; add it back if GHC complains.

2.  `(+++)` and `(|||)` are derived by `Choice`'s default methods
    from `left'`/`right'`; no extra work needed.

3.  In `test/Keiki/ChoiceSpec.hs`:

    a.  Import `Keiki.Profunctor`, `Keiki.Examples.EmailDelivery`,
        and the existing `Pinger` fixture used in
        `test/Keiki/CompositionAlternativeSpec.hs` (copy-paste the
        local `data Pinger`/`pingerTransducer` definitions; they
        are not exported as a library — yet).

    b.  Assert: `right' (someSymTransducer pinger) :: SomeSymTransducer
        (Either EmailCmd PingCmd) (Either EmailCmd PingEvent)`
        typechecks (compile-time check via type signature).

    c.  Assert: a sample input `Left someEmailCmd` fired through
        the `(+++)`-composed pipeline lands on EmailDelivery's
        edges (forward processing) by inspecting
        `edgesOut t (initial t)` of the underlying transducer
        (pull from the wrapper via pattern match).

    d.  Assert: `isSingleValuedSym` survives the `(+++)` (returns
        `True` for the composed transducer when both halves are
        single-valued).

4.  Wire `Keiki.ChoiceSpec` into `keiki.cabal` (test-suite
    `other-modules`) and `test/Spec.hs` (qualified import + describe
    line).

Acceptance for M1: `cabal test keiki-test --test-show-details=direct`
succeeds. The `Keiki.Profunctor (Choice)` describe block shows
green with at least three assertions.

### M2 — Strong instance

Scope: implement `firstSym` on the concrete `SymTransducer` type,
then add the `Strong SomeSymTransducer` instance delegating to it.

What will exist at the end:

1.  In `src/Keiki/Profunctor.hs`, a private function:

        firstSym
          :: forall rs s ci co c.
             ( WeakenR rs, KnownSlotNames rs )
          => SymTransducer (HsPred rs ci) rs s ci co
          -> SymTransducer (HsPred rs (ci, c)) rs s (ci, c) (co, c)

    Implementation strategy: the input `(ci, c)` is consumed
    component-wise — every guard, term, and OutTerm in `t` reads
    from the `ci` projection. The output `(co, c)` is built by
    pairing `t`'s `co` with the input's `c` projection.

    Concretely:

    a.  Define a `pairFstInCtor :: InCtor ci ifs -> InCtor (ci, c) ifs`
        that pre-projects: `icMatch = m . fst; icBuild = poison`
        (poisoned the same way `lmapCi`'s contramapped InCtor
        is — `firstSym`'s output cannot be inverted by
        `solveOutput` either, same caveat).

    b.  Walk `t`'s edges. For each edge:

        - Rewrite the guard via `contraPredFst :: HsPred rs ci ->
          HsPred rs (ci, c)` (applied with `pairFstInCtor` at
          every embedded `InCtor`-using node).

        - Rewrite the update via `contraUpdateFst`.

        - For the output `Maybe (OutTerm rs ci co)`:

            * `Nothing` stays `Nothing` (the edge is silent on
              both halves; no `c` to thread).

            * `Just (OPack ic wc fields)` becomes a new OPack
              whose `WireCtor (co, c) (cfields, c, ())` — wait,
              this gets complex. The cleanest approach: change
              the output's WireCtor's field-tuple structure to
              add a `c` field at the end. The existing fields
              come from `OutFields rs ci fields`; the new
              fields are `OutFields rs (ci, c) (fields, c, ())`
              where the trailing `c` reads from a fresh
              `pairSndInCtor :: InCtor (ci, c) '[("snd", c)]` via
              `TInpCtorField pairSndInCtor ZIdx`.

              Concretely:

                  let newWc :: WireCtor (co, c) (fields_with_c)
                      newWc = WireCtor
                        { wcName = wcName wc <> "_first"
                        , wcMatch = \(_co, _c) -> Nothing  -- lossy
                        , wcBuild = \(fs, c, ()) ->
                            (wcBuild wc fs, c)
                        }

              The `OutFields` walk re-targets every embedded
              `Term rs ci r` through `contraTermFst`, then
              appends `TInpCtorField pairSndInCtor ZIdx *: oNil`
              at the end.

              The math on the field-tuple types:
              `OutFields rs (ci, c) (fields, c, ())` is the
              right-extended HList. The original `fields` is
              already a nested-pair tuple (e.g. `(Text, (UTCTime,
              ()))` for a two-field wire); appending `c` gives
              `(Text, (UTCTime, (c, ())))`. The OutFields appender
              walks the original HList structure.

              See the OFCons/OFNil structure in `Keiki.Core` line
              352 for the field-tuple math.

    c.  `target` and per-edge `update`'s `w` slot list are
        unchanged — `firstSym` doesn't add any register slots
        (it doesn't need to: the `c` thread-through is read
        directly from input via `pairSndInCtor` on every output
        evaluation).

    d.  `initial`, `initialRegs`, `isFinal` are the same as `t`'s.

2.  In `src/Keiki/Profunctor.hs`, the public Strong instance:

        import Data.Profunctor (Strong (..))

        instance Strong SomeSymTransducer where
          first' (SomeSymTransducer t) =
            SomeSymTransducer (firstSym t)

          second' (SomeSymTransducer t) =
            -- second' :: p a b -> p (c, a) (c, b)
            -- Implement via swap:
            --   second' t = lmapCi swap . first' . rmapCo swap
            -- where swap :: (a, b) -> (b, a)
            SomeSymTransducer (lmapCi swap (rmapCo swap (firstSym t)))
            where
              swap (x, y) = (y, x)

    The `second'` derivation via `swap` is tidy but introduces two
    `lmapCi`/`rmapCo` rewrites. A direct `secondSym` could be
    written symmetrically to `firstSym` for ~10% better
    performance; defer that as a future-improvement note.

3.  In `test/Keiki/StrongSpec.hs`:

    a.  Fixture: `someEmail = someSymTransducer emailDelivery`.

    b.  Type-level: `first' someEmail :: SomeSymTransducer
        (EmailCmd, RequestId) (EmailEvent, RequestId)` typechecks.

    c.  Forward-evaluation: pull the first edge from the
        `first'`-rewritten transducer; on a sample input
        `(SendEmail ..., 42 :: RequestId)`, evaluate the
        output's OutFields and assert the produced wire-tuple
        wraps to a value whose `snd` is `42`. (This is the
        thread-through assertion.)

    d.  `isSingleValuedSym` survives `first'`.

    e.  `second'` agrees with `lmapCi swap . first' . rmapCo
        swap` (literal equality of edge structures, or
        forward-evaluation parity).

Acceptance for M2: tests pass; build is clean.

### M3 — Arrow instance + arr

Scope: add `arr`, `(>>>)` (delegating to Category), and `first`
(delegating to Strong). `(>>>)` and `first` are trivial
delegations; `arr` is the new construction.

What will exist at the end:

1.  In `src/Keiki/Profunctor.hs`:

        import qualified Control.Arrow as Arr
        import Control.Arrow ((>>>), (<<<))

        -- A stateless transducer that lifts an arbitrary Haskell
        -- function. The output cannot be inverted by 'solveOutput'
        -- (no inverse function in general); same lossy contract as
        -- `lmapCi`/`rmapCo`/`first'`.
        arrTransducer
          :: forall a b.
             (a -> b)
          -> SymTransducer (HsPred '[] a) '[] IdVertex a b
        arrTransducer f = SymTransducer
          { edgesOut    = \IdVertex ->
              [ Edge { guard  = PTop
                     , update = UKeep
                     , output = Just arrOut
                     , target = IdVertex
                     }
              ]
          , initial     = IdVertex
          , initialRegs = RNil
          , isFinal     = const True
          }
          where
            arrOut :: OutTerm '[] a b
            arrOut = OPack identityInCtor arrWc
                       (OFCons (TInpCtorField identityInCtor ZIdx) OFNil)

            arrWc :: WireCtor b (a, ())
            arrWc = WireCtor
              { wcName  = "arr"
              , wcMatch = \_b -> Nothing
              , wcBuild = \(a, ()) -> f a
              }

        instance Arr.Arrow SomeSymTransducer where
          arr f = SomeSymTransducer (arrTransducer f)
          first  = first'   -- from Strong
          second = second'

        -- (>>>) and (<<<) come from Category for free.

    `Arrow`'s default `(***)` and `(&&&)` use `first` / `second`
    plus `arr` and `(>>>)`; they work out of the box once the
    above three methods are in place.

2.  Note: `identityInCtor` was *private* in EP-28. M3 needs to
    re-export it (or move `arrTransducer`'s use of it inside
    `Keiki.Profunctor` if it's in the same module — which it
    is — so no export change needed; just remove the "private"
    haddock comment if any).

3.  In `test/Keiki/ArrowSpec.hs`:

    a.  Type-level: `arr (Text.pack . show) :: SomeSymTransducer
        Int Text` typechecks.

    b.  Forward-evaluation: pull the edge from `arr show`;
        evaluate its output on a sample `Int = 42`; assert the
        produced wire value is `"42"`.

    c.  `(>>>)`: compose `arr show >>> arr length :: SomeSymTransducer
        Int Int`; assert forward-evaluation produces the right
        Int.

    d.  `first` delegation: `first (arr show) :: SomeSymTransducer
        (Int, Text) (Text, Text)`; on input `(42, "extra")`, assert
        forward output is `("42", "extra")`.

    e.  `solveOutput` returns `Nothing` on `arr`-built transducers
        (the documented lossy-inversion contract).

4.  Wire `Keiki.StrongSpec`, `Keiki.ChoiceSpec`, and
    `Keiki.ArrowSpec` into `keiki.cabal` and `test/Spec.hs`. (M1
    and M2 already wired their respective specs; M3 only adds
    Arrow.)

5.  Update `docs/masterplans/9-profunctor-and-category-instances-on-symtransducer.md`:

    - Mark the EP-29 milestones in Progress as complete.
    - Set EP-29's status in the Exec-Plan Registry to `Complete`.
    - Add a Surprises & Discoveries entry recording the `parallel`
      decline + the in-house `firstSym` resolution; cross-reference
      MP-8's EP-24 design milestone.
    - Update the "Out of scope" list: the previously-listed
      `Closed`, `Costrong`, `Cochoice` remain out of scope; add
      `ArrowChoice` to the same list.
    - Update the Vision & Scope's `Arrow` bullet to clarify that
      `arr`-produced transducers do not support `solveOutput`.

6.  Update `docs/research/architecture-comparison-keiki-vs-crem.md`:
    the section that names crem-parity gaps gets a one-line update
    noting the gap is closed (modulo the lossy-`solveOutput`
    caveat for `lmap`/`rmap`/`first`/`arr`).

Acceptance for M3: `cabal test keiki-test --test-show-details=direct`
succeeds. The new `Keiki.Profunctor (Strong)`, `(Choice)`, and
`(Arrow)` describe blocks all pass.


## Concrete Steps

All commands run from `/Users/shinzui/Keikaku/bokuno/keiki/`.

### M0 commands

    cabal build all
    cabal test keiki-test --test-show-details=direct 2>&1 | tail -30
    grep -n "^alternative\|^identityTransducer\|instance.*Category" \
         src/Keiki/Composition.hs src/Keiki/Profunctor.hs

Record `N examples, 0 failures` from the test summary.

### M1 commands

1.  Edit `src/Keiki/Profunctor.hs`: add the Choice instance and
    its imports.

2.  Build: `cabal build all`. Expected: success. If GHC complains
    about `Disjoint (Names rs) (Names '[])` not being solvable
    automatically, add the explicit `unsafeCoerceDisjointness`
    pattern as in the M1 plan-of-work.

3.  Create `test/Keiki/ChoiceSpec.hs`. Use
    `test/Keiki/CompositionAlternativeSpec.hs` as the template
    for the Pinger fixture (copy-paste the inline `data Pinger`,
    `pingerTransducer`, etc. definitions verbatim).

4.  Edit `keiki.cabal` and `test/Spec.hs` to register the new
    spec.

5.  Run `cabal test keiki-test --test-show-details=direct 2>&1 |
    tail -50`. Expected: a `Keiki.Profunctor (Choice)` block with
    three or more green lines.

6.  Commit M1:

        git commit -m "$(cat <<'EOF'
        feat(profunctor): EP-29 M1 — Choice instance via alternative

        Add Data.Profunctor.Choice SomeSymTransducer instance with
        left' / right' delegating to Keiki.Composition.alternative
        and the wrapper's identityTransducer. (+++) and (|||) come
        from Choice's default methods.

        Spec covers left', right', (+++), and survival of
        isSingleValuedSym.

        MasterPlan: docs/masterplans/9-profunctor-and-category-instances-on-symtransducer.md
        ExecPlan: docs/plans/29-strong-choice-and-arrow-instances-on-the-symtransducer-wrapper.md
        Intention: intention_01knjzws4qezz9w8b0743zfqv8
        EOF
        )"

### M2 commands

1.  Edit `src/Keiki/Profunctor.hs`: add `firstSym`, the Strong
    instance, helpers (`pairFstInCtor`, `pairSndInCtor`,
    `contraTermFst`, etc.).

2.  Build incrementally. Expected: success after each helper.
    If the OutFields field-tuple math fails to typecheck, the
    most likely cause is a mis-tracked nested-pair shape; check
    `OFCons :: Term ... -> OutFields ... fs -> OutFields ... (f,
    fs)` and walk the type carefully.

3.  Create `test/Keiki/StrongSpec.hs`. Wire it in.

4.  Run `cabal test`. Expected: `Keiki.Profunctor (Strong)`
    block green.

5.  Commit M2.

### M3 commands

1.  Edit `src/Keiki/Profunctor.hs`: add `arrTransducer`, the
    Arrow instance.

2.  Build. Expected: success.

3.  Create `test/Keiki/ArrowSpec.hs`. Wire it in.

4.  Run `cabal test`. Expected: `Keiki.Profunctor (Arrow)` block
    green.

5.  Update MP-9 and the crem-comparison research doc per the
    M3 plan-of-work.

6.  Commit M3 with the full closure summary.


## Validation and Acceptance

The user-visible success criterion: `cabal test keiki-test
--test-show-details=direct` passes with three new describe blocks
green — `Keiki.Profunctor (Choice)`, `Keiki.Profunctor (Strong)`,
`Keiki.Profunctor (Arrow)` — totaling at least 12 new assertions
across them (3 each at minimum, more in practice).

The `cabal repl` smoke check:

    > import Keiki.Profunctor
    > import Keiki.Examples.EmailDelivery
    > import qualified Control.Arrow as Arr
    > import Data.Profunctor

    > :type first' (someSymTransducer emailDelivery)
    first' (someSymTransducer emailDelivery)
      :: SomeSymTransducer (EmailCmd, c) (EmailEvent, c)

    > :type Arr.arr show :: SomeSymTransducer Int String
    Arr.arr show :: SomeSymTransducer Int String :: SomeSymTransducer Int String

The keiki guarantees survival pattern (asserted in tests):

- `isSingleValuedSym` returns `True` after `first'` / `right'` /
  `arr` wrapping when it returned `True` on the underlying
  transducer.
- `solveOutput` returns `Nothing` on `arr`-produced transducers,
  on `first'`-rewritten transducers, and on `right'`-rewritten
  transducers, *as documented*. The test suite asserts this on at
  least one representative case for each.


## Idempotence and Recovery

All steps are idempotent. `cabal build` and `cabal test` re-run
cleanly. Edits are text-level; no migrations.

The most likely failure mode at M2 is the OutFields field-tuple
math failing to typecheck. The fix is to print the inferred type
of `firstSym`'s intermediate values via a `:type` in `cabal repl`
and adjust the OFCons/OFNil structure to match. The `_` underscore-
hole technique helps:

    let foo = OFCons _ OFNil :: OutFields '[] (Int, String) (Int, ())

GHC tells you what the hole's type is.

The most likely failure mode at M3 is `arr`-produced transducers
crashing in tests that try to invoke `solveOutput` on them.
Resolution: that's the documented contract. The test should assert
`Nothing`, not unwrap a `Just`.

A rollback is `git reset --hard` and `cabal clean`. Nothing outside
the working tree is touched.


## Interfaces and Dependencies

### New module surface added by this plan

`src/Keiki/Profunctor.hs` gains:

    -- M1 (Choice):
    instance Choice SomeSymTransducer

    -- M2 (Strong):
    instance Strong SomeSymTransducer
    -- (private helper:)
    firstSym
      :: ( WeakenR rs, KnownSlotNames rs )
      => SymTransducer (HsPred rs ci) rs s ci co
      -> SymTransducer (HsPred rs (ci, c)) rs s (ci, c) (co, c)

    -- M3 (Arrow):
    instance Arrow SomeSymTransducer
    arrTransducer
      :: (a -> b)
      -> SymTransducer (HsPred '[] a) '[] IdVertex a b

### External dependencies

No new package dependency. `Control.Arrow` is in `base`. The
`Strong` and `Choice` classes are in the `profunctors` package
(already added by EP-27).

### Imported keiki modules

`Keiki.Profunctor` imports from `Keiki.Core` (already), from
`Keiki.Composition` (added by EP-28 for `compose`; used here also
for `alternative`), and from `base` and `profunctors`. No cycle
risk.

### Downstream consumers

None planned. MP-9 closes with this plan; future work extending
the typeclass surface (e.g. `Closed`, `Costrong`, `Cochoice`,
`ArrowChoice`) would be a separate MasterPlan.
