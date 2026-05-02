# Composition

How to compose two transducers with `Keiki.Composition.compose`.

This guide assumes you've read the main `user-guide.md` and have at
least one working aggregate. For the formal semantics, the
substitution algorithm, and the proof sketches see
`docs/research/composition-combinators-design.md`.

---

## 1. The shape

```haskell
compose
  :: ( WeakenR rs1
     , Disjoint (Names rs1) (Names rs2)
     )
  => SymTransducer (HsPred rs1 ci1) rs1 s1 ci1 mid
  -> SymTransducer (HsPred rs2 mid) rs2 s2 mid co
  -> SymTransducer (HsPred (Append rs1 rs2) ci1)
                   (Append rs1 rs2)
                   (Composite s1 s2)
                   ci1
                   co
```

Read the type left to right. `compose t1 t2` builds a transducer
whose:

- **input alphabet** is `t1`'s input (`ci1`),
- **output alphabet** is `t2`'s output (`co`),
- **mid alphabet** (`mid`) is shared: `t1`'s output equals `t2`'s
  input,
- **vertex** is `Composite s1 s2` (a strict pair newtype),
- **register file** is `Append rs1 rs2` (the slot lists
  concatenated).

The composite preserves keiki's three core guarantees:

1. **Mechanical inversion.** `solveOutput` on the composite walks
   `t2`'s wire form back through `t1`'s structural reads, recovering
   `ci1`.
2. **Hidden-input detection.** `checkHiddenInputs` surfaces fields
   that are transitively hidden — a `ci1` field `t1` keeps in `mid`
   but `t2` drops on the wire is flagged at the composite level.
3. **Symbolic single-valuedness.** The composite is single-valued
   when `t1` and `t2` are individually single-valued; substitution
   is a syntactic rewrite that preserves unsatisfiability.

---

## 2. The two preconditions

### 2.1 Disjoint slot names

```haskell
Disjoint (Names rs1) (Names rs2)
```

`rs1` and `rs2` must not share a slot label. Violating this is a
compile-time `TypeError` naming the duplicate.

The keiki `RegFile` is positional, so a name collision wouldn't
*break* the runtime — but distinct names also keep the SBV
translation's free-variable names unambiguous, and they make the
composite read clearly. If two aggregates both want `"at"`, prefix
them: `"alertAt"`, `"emailAt"`.

### 2.2 Mid-side alphabet alignment

`t1`'s output type must equal `t2`'s input type. The
`AlertSource ⨾ EmailDelivery` test fixture aligns the two by
declaring `AlertSource`'s output to *be* `EmailCmd`:

```haskell
type AlertEvent = EmailCmd

alertSource :: SymTransducer (HsPred AlertRegs AlertCmd)
                              AlertRegs AlertVertex AlertCmd EmailCmd
```

When the two natural alphabets don't match, you can either:

- Author one aggregate's events to be the other's commands directly
  (the simplest case, above), or
- Insert a small adapter transducer between them — itself a
  one-edge transducer that translates events to commands.

---

## 3. A worked example

The composition spec at `test/Keiki/CompositionSpec.hs` builds a
two-stage pipeline. Reading it top to bottom:

```haskell
-- Stage 1: AlertSource. Defined inline in the spec.
alertSource
  :: SymTransducer (HsPred AlertRegs AlertCmd)
                   AlertRegs AlertVertex AlertCmd EmailCmd

-- Stage 2: the EmailDelivery example aggregate.
emailDelivery
  :: SymTransducer (HsPred EmailRegs EmailCmd)
                   EmailRegs EmailVertex EmailCmd EmailEvent

-- The pipeline.
pipeline
  :: SymTransducer
       (HsPred (Append AlertRegs EmailRegs) AlertCmd)
       (Append AlertRegs EmailRegs)
       (Composite AlertVertex EmailVertex)
       AlertCmd
       EmailEvent
pipeline = compose alertSource emailDelivery
```

Running one external command through the composite:

```haskell
case step pipeline (initial pipeline, initialRegs pipeline) sampleTrigger of
  Just (Composite av ev, _, Just co) -> …
  -- av  = AlertEmitted        (s1 advanced)
  -- ev  = EmailSentVertex     (s2 advanced)
  -- co  = EmailSent {...}     (the wire event)
```

One external `TriggerAlert` command produces one external `EmailSent`
event. The intermediate `EmailCmd` never escapes — `compose` fuses
the two stages into a single transition.

---

## 4. ε-edges in composition

Composition handles `t1`'s ε-edges specially: each ε-edge of `t1`
from `s1` produces one composite edge that advances `s1` and leaves
`s2` unchanged. `t2`'s ε-edges are not chained transitively — `t1`
must explicitly emit a `mid` event for `t2` to fire.

In practice this means:

- A pipeline where every stage emits is the simple case
  (`compose` round-trips `reconstitute` cleanly).
- A pipeline whose first stage emits ε events on some commands has
  composite edges where `s2` doesn't advance. Replay over the event
  log reaches the right place because `applyEvent` only sees the
  emitted events.

The design note's §"Semantics" enumerates the cases.

---

## 5. What composition does **not** preserve

Three things `compose` is documented as *not* carrying through.
Each is a known limitation, not a defect.

- **`TApp1` / `TApp2` opaque escape hatches in `t2`'s mid-side
  reads.** The substitution algorithm rewrites mid-side terms
  against `t1`'s output term. Opaque Haskell functions can't be
  substituted through — the composite uses the original `t2` term
  and the input-recovery proof falters. Avoid `TApp1`/`TApp2` over
  the input alphabet on the second stage.
- **Non-`OPack` outputs on `t1`.** `OPack` is the only output
  constructor today, so this is automatic. Listed in the design
  note for completeness if a future output shape is added.
- **Non-structural `t2` mid-side guards.** Same reason as the
  first item: substitution over `PEq` requires both sides be
  structurally walkable.

`checkHiddenInputs` on the composite catches the practical
consequence (a hidden field somewhere in the chain) — run it after
each `compose`.

---

## 6. Verifying a composite

After building the composite, the standard verification gates:

```haskell
-- 1. No hidden inputs.
checkHiddenInputs pipeline `shouldBe` []

-- 2. Single-valued (symbolic, requires Keiki.Symbolic + z3).
isSingleValuedSym (withSymPred pipeline) `shouldBe` True

-- 3. Round-trip on a sample event log.
reconstitute pipeline [sampleEmailEvent] `shouldSatisfy` isJust
```

The first two are zero-cost in CI (single-valuedness costs the
solver dispatch — see `symbolic-ci.md`). The third costs as much
as one `applyEvent` per event in the fixture.

---

## 7. Composing more than two

`compose` is sequential and binary. For three stages, fold left:

```haskell
threeStage = compose (compose t1 t2) t3
```

The associativity proof isn't formally written down in the design
note; treat the parenthesisation as a free choice and test the
result. The vertex type stacks: `Composite (Composite s1 s2) s3`,
which `Bounded`/`Enum` derive cleanly.

For non-sequential composition shapes (parallel, feedback loops,
choreography) see
`docs/research/orchestration-sagas-choreography-and-feedback-loops-as-transducers.md`
and
`docs/research/future-directions-profunctors-effects-and-composition.md`.
keiki ships only sequential `compose` today; the others are
deferred.

---

## 8. Common errors

**Slot-name collision.**

```
• Slot name "at" appears in both rs1 and rs2
```

Rename slots in one of the two aggregates.

**Mid alphabet mismatch.**

```
• Couldn't match type ‘EmailCmd’ with ‘OtherCmd’
```

`t1`'s output type doesn't equal `t2`'s input type. Either align
them at the source or insert an adapter aggregate.

**Hidden input on the composite, but not on either stage.**

```
checkHiddenInputs pipeline `shouldBe` []   -- fails
```

A field that `t1` writes into a `mid` event but `t2` doesn't
re-emit on the wire. Either widen `t2`'s output to carry the
field, or accept that the composite's `applyEvent` for that edge
won't recover from the event log alone.

---

## 9. Pointers

- `src/Keiki/Composition.hs` — implementation; the haddock at
  `compose` summarises the mechanics.
- `docs/research/composition-combinators-design.md` — formal
  semantics, substitution algorithm, single-valuedness proof
  sketch, the full `crem` catalogue compared.
- `test/Keiki/CompositionSpec.hs` — the canonical
  `AlertSource ⨾ EmailDelivery` fixture, end to end.
- `docs/research/orchestration-sagas-choreography-and-feedback-loops-as-transducers.md`
  — the bigger design picture for non-sequential composition.
