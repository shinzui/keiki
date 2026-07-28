# Typed field projections over consumer-owned values

This note specifies Keiki's first-class, solver-visible projection of one
scalar field from a consumer-owned value. It records the trust boundary and
the deliberate limits of the feature introduced by ExecPlan 79. The older
[`tinpproj-design.md`](tinpproj-design.md) explains the related but different
case where the scalar is already a slot in an input-constructor schema.

## Problem and scope

A consumer may map an application record into one Keiki register slot or one
input field and copy that value wholesale into events. Before this feature, a
guard could inspect an inner scalar only with `TApp1`. That function is opaque
to symbolic analysis: repeated calls do not share a solver value, the opaque
guard audit fires, and diagnostics cannot name the path.

`TFieldProj` makes one single-hop getter structural when its owner is a direct
register slot or a matched input-constructor field. It is a guard capability.
Validation rejects projections in updates and outputs, so whole-value copying
and replay inversion keep their existing contract. Collections, nested
projection chains, and reconstruction of application records from solver
models remain out of scope.

## Public shape and laws

A projection is named by a fresh tag type with one coherent instance:

```haskell
class FieldProjection projection where
  type FieldName projection :: Symbol
  type FieldOwner projection :: Type
  type FieldResult projection :: Type
  fieldShapeId :: Proxy projection -> String
  projectFieldValue ::
    Proxy projection -> FieldOwner projection -> FieldResult projection
```

`FieldWitness projection` is abstract and has a nominal role. `fieldWitness`
constructs it only when the tag, owner, and result have runtime type identity.
`regProj` and `inpProj` restrict the owner base to `PBReg` and `PBInp`; callers
cannot hide an arbitrary computed owner behind a supposedly structural path.

Instances obey these laws:

1. `projectFieldValue` is total for every well-formed owner.
2. One fresh nominal tag denotes one logical projection. Normal Haskell
   instance coherence supplies one getter per tag; incoherent instances are
   outside Keiki's supported contract.
3. `FieldName` and `fieldShapeId` truthfully describe the getter.
4. A generator reuses one canonical tag at every occurrence of the same
   logical field. Distinct tags for the same getter are sound but imprecise,
   because the solver treats them as independent projections.

Keiki owns the term semantics and exports `fieldWitnessAgrees` as the law
harness. A binding generator such as Keiro owns schema provenance: it generates
the instance and tests the getter against the same resolved binding graph used
for codecs. A dishonest coherent instance can mislabel which field the DSL
denotes, but caller-controlled strings cannot make two different tags share a
solver variable.

## Concrete and symbolic semantics

Concrete evaluation reads the owner from the named base and applies the total
getter. An input base has the same dynamic precondition as `TInpCtorField`: its
`InCtor` must match the current command, and validation requires the matching
`PInCtor` guard.

Symbolic translation does not need a `Sym` instance for the owner. It allocates
one variable for the projected result, which must be in Keiki's curated
symbolic registry. The memo key is structured as:

```text
(base kind, base name, base position,
 projection TypeRep, owner TypeRep, result TypeRep)
```

Register and input bases remain distinct even when their diagnostic dotted
paths happen to match. Nominal projection tags remain distinct even when field
and shape strings match. Owner and result identities prevent accidental
sharing across representation coincidences such as `Int` and `Integer`. SBV
receives only an internal `proj/<ordinal>` label, so arbitrary schema names do
not enter its restricted label namespace.

The agreement claim is intentionally one-way. For concrete registers and an
input, `constrainFieldProjection` binds each encountered projection variable to
`projectFieldValue owner`. Translating an equality or supported comparison
under those bindings has the same Boolean result as `evalPred`:

```text
concrete owner
    | total getter
    v
projected scalar  ==constraint==>  symbolic projection variable
```

Therefore every concrete execution has a matching symbolic valuation. The
converse is false in general: independently free scalar projections may not be
jointly realizable by any owner. `symSatExt` reconstructs ordinary scalar
register and input slots by their established labels, but it cannot reconstruct
an arbitrary consumer-owned value from projection variables. A satisfiable
projection-backed formula is thus a scalar abstraction, not an owner witness.
This is a conservative over-approximation for proof gates: it can lose proof
precision, but it cannot create a false proof of unsatisfiability.

## Validation and replay

`validateTransducer` applies three unconditional checks:

- `ProjectionResultUnsupported` when a guard projection's result is absent
  from the equality-capable symbolic registry;
- `ProjectionOrderingUnsupported` when `PCmp` uses a projected type absent
  from the ordering registry, such as `Text`; and
- `ProjectionOutsideGuard` for every projection in an update or output.

Projection nodes are structural, so the opt-in `OpaqueGuard` audit does not
flag them. Input-based projections still count as input reads for the
guard-implies-constructor rule. In outputs they conservatively count as reads
of the whole owner field, so the hidden-input analysis does not mistake an
inner getter for recoverable wire data.

Replay treats a projection as derived. Forward evaluation can recompute it,
while inversion gathers no command entries from it. Valid transducers contain
projections only in guards, so forward/replay behavior is unchanged; total raw
evaluation remains available to make malformed transducers diagnosable.

## Composition policy

Composition can substitute a mapped producer expression for the downstream
owner base. The rewrite has three cases:

- Preserve `TFieldProj` when the substituted owner is still a direct `TReg` or
  `TInpCtorField`; the nominal witness and structural path remain available.
- Fold the getter when the owner becomes `TLit`.
- Lower the getter to `TApp1` when the owner is computed or comes from a
  pending write in a multi-event chain.

The last case preserves concrete forward behavior but loses symbolic identity
and becomes opaque. Raw `compose` keeps that forward-correct result.
`composeChecked` reports `NonStructuralProjectionBoundary`, with both boundary
edge references, dotted path, shape, and reason, and refuses to certify it.
This follows the repository-wide rule that checked boundaries fail loudly
when a structural proof obligation cannot be preserved.

## Practical guidance

Prefer explicit scalar registers for central decision facts, especially when a
solver must return concrete witnesses. Use typed field projections when a
consumer-owned value must remain whole and a guard needs a small number of
scalar observations. Generate tags from schema provenance, test each getter
with `fieldWitnessAgrees`, validate every transducer, and use `composeChecked`
for durable pipelines.
