# ADR-0001: Structural re-indexing of `Term`/`OutFields` for sound replay

- **Status:** Accepted
- **Date:** 2026-05-23
- **Plan(s):** `docs/plans/53-harden-inctor-identity-for-structural-replay.md`;
  follow-up `docs/plans/54-thread-input-field-schema-through-edgebuilder-to-remove-emit-s-coercion.md`
- **Implementation:** commit `30c89fa` (`feat(core)!: re-index Term/OutFields by input
  schema for sound replay`)

## Context

Structural replay recovers an input command from an observed output event by walking an
`OutTerm`. An `OutTerm`'s `OPack` stores an `InCtor ci ifs` (the input constructor and its
field schema `ifs`) *and* an `OutFields` list of `Term`s; a top-level `TInpCtorField` term
reads one field of the input constructor through its own `InCtor` and an `Index` into *that*
constructor's schema.

Originally nothing forced the `OPack`'s `InCtor` schema and a `TInpCtorField`'s schema to
agree, because both schemas were existentially hidden. `gatherInpEntries` reconciled them at
run time: when the two `icName :: String` fields matched, it did
`ByIndex (unsafeCoerce ix) val`, reinterpreting one constructor's field index as another's.
A malformed or hand-written pair of `InCtor`s reusing one `icName` with different field
schemas would drive a **type- and memory-unsound** index recovery. The fix had to make the
recovered index provably valid for the schema it is assembled into.

Two approaches were considered:

1. **Runtime schema comparison** (the original plan): carry `Typeable ifs` on `InCtor` and
   compare `TypeRep`s via `eqTypeRep` before accepting a field. This proved *unimplementable*:
   `Typeable ifs` cannot be supplied for two polymorphic phantom `InCtor`s in
   `Keiki.Profunctor` (`identityInCtor`, `pairSndInCtor`) that flow through the fixed-signature
   `Profunctor`/`Strong`/`Arrow`/`Choice` typeclass instances, and forging the dictionary with
   `unsafeCoerce` would be unsound (a bogus `TypeRep` makes `eqTypeRep` lie).
2. **Type-level structural re-indexing**: make the two schemas the *same type variable* by
   construction, so no runtime comparison or coercion is needed.

## Decision

Adopt the type-level re-indexing ("Design A-refined"):

- `Term` gains an `ifs :: [Slot]` parameter — the input field schema it may project from.
  It is **pinned** by `TInpCtorField`, **free** on `TLit`/`TReg`, and **threaded** through
  `TApp1`/`TApp2`/`TArith`.
- `OutFields` exposes that `ifs`, and `OPack :: InCtor ci ifs -> WireCtor co fields ->
  OutFields rs ci ifs fields -> OutTerm rs ci co` ties the `OutFields`' schema to the
  `InCtor`'s. A top-level `TInpCtorField` inside an `OutFields` is therefore an `Index` into
  the `OPack`'s constructor schema *by construction*.
- `gatherInpEntries` returns `ByIndex ix val` with **no coercion**; the `icName` equality
  check is retained only as a runtime *diagnostic* for malformed edges, not as type evidence.
- `Update` (`USet`) and `HsPred` (`PEq`/`PCmp`) **existentially hide** the term's `ifs`, so
  `Edge` and `SymTransducer` keep their kinds and the change does not ripple into the
  transducer surface or the authoring API.
- `firstSym` (the `Strong`/`Arrow` lossy combinator, whose `solveOutput` is dead) is reworked
  to a combined `InCtor (ci, c)` so its threaded-`c` projection and the original fields share
  one schema.

No `Typeable` is required anywhere, and the `Keiki.Profunctor` phantom `InCtor`s are
untouched.

## Consequences

**Positive**

- The field-schema collision is now a **compile error** (un-representable), not a runtime
  failure. The recovered index is provably valid for the target schema. `Keiki.Core`
  contains zero `unsafeCoerce`.
- Achieved with **no `Typeable`** and **no change to how aggregates are authored** —
  record-syntax / `*:`-chain authoring is inference-driven; the four `jitsurei` aggregates
  compiled unchanged. All four test suites pass (279 + 96 + 40 + 7 examples, 0 failures).

**Negative / trade-offs**

- **Breaking type change:** `Term`, `OutFields`, and the `ToOutFields` class gained an `ifs`
  type parameter; the TH-generated `<Short>TermFields` record gained one too. Downstream code
  with *explicit* `Term`/`OutFields` annotations must add the parameter (record-syntax/`*:`
  authoring is unaffected).
- **Scope of the guarantee:** this is *type soundness* (the recovered index is valid for the
  schema it is assembled into), **not** *semantic constructor identity*. Two genuinely
  different constructors that share both `icName` and field schema still compare equal; the
  `icName` check is a diagnostic, not proof of identity. Establishing unforgeable identity is
  out of scope.
- **Residual `unsafeCoerce` outside the replay path** (pre-existing trust boundaries, not
  new soundness holes in inversion):
  - `Keiki.Composition.unsafeCoerceTerm` / `unsafeCoerceInCtor` — `compose`'s substitution
    relies on a runtime structural-alignment invariant (`icName == wcName` ⇒ same
    Generic-derived shape). `unsafeCoerceTerm` was *extended* to also realign `ifs` under the
    same justification.
  - `Keiki.Profunctor.unsafeCoerceDisjointness` / `unsafeCoerceWrapperDict` — dictionary
    fabrication for `Disjoint`/`Wrapper`, unrelated to `ifs`.
  - `Keiki.Builder.reIndexPinnedInCtor` — **new**: `emit` bridges the existential `PeInCtor`'s
    hidden `ifs` to the per-event record's schema. Justified by `onCmd` storing one and the
    same `InCtor` in both places; it does **not** weaken replay soundness (the `OPack` it
    builds is well-typed). Whether it can be eliminated by threading `ifs` through
    `EdgeBuilder` is the subject of ADR-follow-up plan
    `docs/plans/54-thread-input-field-schema-through-edgebuilder-to-remove-emit-s-coercion.md`.
- **`firstSym` complexity:** the combined-`InCtor` rework adds an index-shifting re-home walk
  whose correctness rests on the "one input constructor per edge" invariant (documented in
  the code). Its `solveOutput` is dead, so this affects only forward processing, which the
  `Arrow`/`Strong` tests cover.
