---
type: Architecture Decision Record
title: "Structural re-indexing of `Term`/`OutFields` for sound replay"
description: >-
  Recover replay indices by type-level structural re-indexing of Term and OutFields schemas
  instead of runtime coercion, eliminating unsound unsafeCoerce-based index recovery.
docId: ADR-1
status: Accepted
date: 2026-05-23
timestamp: 2026-08-05T02:29:30Z
generated:
  by: adopt-architecture-decisions/0.8.0
  at: 2026-08-04T16:35:24Z
---

# ADR-0001: Structural re-indexing of `Term`/`OutFields` for sound replay

- **Plan(s):** `docs/plans/53-harden-inctor-identity-for-structural-replay.md`;
  follow-up `docs/plans/54-thread-input-field-schema-through-edgebuilder-to-remove-emit-s-coercion.md`;
  research `docs/plans/86-research-a-full-symbolic-replay-inversion-model.md`;
  implementation `docs/plans/87-add-structural-wire-schemas-for-optional-symbolic-replay-inversion.md`;
  sealing and cast-removal follow-up
  `docs/plans/89-repair-inversion-compatibility-pairing-and-seal-wire-evidence-boundaries.md`
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

Full symbolic replay inversion exposes the same evidence boundary across two edges. Equal
`WireCtor.wcName` values and two independently existential `OutFields` values do not prove that
the opaque matchers project the same constructor or field tuple from one observed event. A shared
symbolic observation therefore requires additional typed structural wire-schema evidence; it
cannot be recovered from diagnostic names or casts.

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

This decision also governs cross-edge inversion proofs. Every `WireCtor` carries an abstract
`WireSchema`; Generic and TH producers provide a trusted constructor path plus an ordered,
typed field spine. The symbolic replay checker shares observed fields only after two trusted
schemas prove equal paths and a position-by-position type alignment. Hand-written constructors
state `wireSchemaUnavailable`; checked sum composition prefixes evidence, while mapped or
meaning-changing wires drop it. Missing or prefix-related evidence retains the conservative
ambiguity warning.

The raw `MkWireCtor` and `MkInCtor` constructors are private. Public construction and record
update are blocked by unidirectional record patterns; manual closure-taking constructors always
stamp evidence unavailable, and diagnostic-only rename helpers preserve the existing evidence.
Trusted in-package producers require a strict capability whose constructor and value live in a
hidden Cabal module, so downstream code cannot import the authority needed by the internal trusted
hooks.

Composition-only identity evidence carries a typed prefix spine: the root pins the field to the
carrier, and Left/Right constructors retain each proven `Either` arm. Comparing two spines in
lockstep refines their hidden field types directly. Schema alignment therefore contains no cast,
including the polymorphic identity case.

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
- **Scope of the guarantee:** diagnostic names remain outside the proof relation. Generic/TH
  constructor paths and typed field spines establish structural identity; unavailable manual
  evidence cannot authorize alignment even when names and runtime behavior happen to agree.
- **Breaking construction change:** downstream code can neither construct nor record-update
  `WireCtor` / `InCtor` through their public record patterns. Manual behavior must use the
  unavailable smart constructors, while Generic, TH, and structure-preserving in-package
  combinators retain the hidden trusted authority. Nominal schema roles prevent ordinary coercion
  from minting proof evidence.
- **Residual `unsafeCoerce` outside the replay path** (current trust boundaries, not
  soundness holes in core inversion or schema alignment):
  - `Keiki.Composition` retains confined existential re-indexing for the already-aligned
    upstream input schema, pending multi-event terms after their register result type is proved,
    and the composite output's original input constructor. None compares constructor names or
    manufactures an input-to-wire field equality.
  - `Keiki.Profunctor.unsafeCoerceDisjointness` fabricates only the
    methodless `Disjoint` constraint after a runtime slot-name overlap
    check. The former `unsafeCoerceWrapperDict` / `KnownSlotNames`
    fabrication was removed; `KnownSlots` evidence is now derived by
    structural induction.
- **Completed follow-up:** the builder now threads the enclosing
  `onCmd` schema through `EdgeBuilder`; `emit` needs no coercion and
  mismatched schemas are compile-time errors. Eager builder validation
  also rejects contradictory `emitWith` constructors.
- **`firstSym` complexity:** the combined-`InCtor` rework adds an index-shifting re-home walk
  whose correctness rests on the "one input constructor per edge" invariant (documented in
  the code). Its `solveOutput` is dead, so this affects only forward processing, which the
  `Arrow`/`Strong` tests cover.
