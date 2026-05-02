# Emit field-keyed record sugar — design note (EP-21 M3)

## Purpose

EP-15 shipped `Keiki.Builder` with the `B.emit ic wc fs` shape;
EP-21's M1 dropped the redundant `InCtor` and M2 added `(*:)` /
`oNil` operator sugar so the HList reads top-to-bottom. The
remaining friction is at the *content* layer: `OFCons` /  `(*:)`
chains are positional, so the user must remember the wire ctor's
field order. A wrong order compiles fine and emits wrong output.

This note settles the four open questions for a field-keyed
record-syntax surface (M4 implementation, M5 migration). It is
the contract M4 consumes verbatim.

## Target surface

The post-M5 `Confirm` edge:

```haskell
B.from RequiresConfirmation do
  B.onCmd inCtorConfirm $ \d -> B.do
    B.requireEq d.confirmCode #confirmCode
    B.slot @"confirmedAt" .= d.at
    B.emit wireAccountConfirmed AccountConfirmedTermFields
      { email       = #email
      , confirmCode = d.confirmCode
      , at          = d.at
      }
    B.goto Confirmed
```

Read top-to-bottom; field names match the wire ctor's payload
type `AccountConfirmedData`; field types are `Term rs ci T`
(one level wider than the payload's `T`). The same `B.emit` also
accepts the M2 operator form unchanged:

```haskell
B.emit wireAccountConfirmed (#email *: d.confirmCode *: d.at *: B.oNil)
```

…dispatched via a typeclass on the second argument's type.

## Q1 — per-event TH-generated record vs class-driven generic

**Decision: per-event TH-generated record + `ToOutFields` instance.**

Three candidates considered:

1. **Per-event TH-generated record.** `deriveWireCtors` (or a
   sibling splice) emits a record type
   `<CtorName>TermFields rs ci` with one field per wire-side
   field, plus a `ToOutFields` instance that walks its fields in
   the same order the TH emitted them.

2. **Generic-Rep-driven record-of-Terms.** A type family
   `TermRec ctor rs ci :: Type` that walks the payload's Generic
   `Rep` to produce an anonymous record-of-Terms. Less code
   emitted; more type-level machinery.

3. **Per-event `emitFoo` helper.** TH emits a function
   `emitAccountConfirmed :: AccountConfirmedTermFields rs ci ->
   EdgeBuilder ...` directly, bypassing the typeclass. Each event
   gets its own dedicated emit function.

(1) wins on three axes:

- **Source-level discoverability.** A user reading the example
  module sees the record type by its name; jumping to its
  definition shows the field schema. (2)'s anonymous record
  type and (3)'s opaque per-event helper hide the schema behind
  a TH expansion.
- **Error messages.** Standard "missing field `at`" / "extra
  field `emial`" / "couldn't match expected type `Term rs ci
  Email`" messages reference the record type by name. (2)'s
  type-family-driven shape produces messages that mention the
  type-family expansion, which is harder to read.
- **API surface.** (3) is one extra exported function per event;
  (1) is one record type per event with a uniform `B.emit`
  entry point. The latter scales with event count without
  growing the surface a user must remember.

(1) does cost more *generated* code (one record type and one
typeclass instance per event), but the cost is paid by the TH
compiler, not the user.

## Q2 — field-name disambiguation under DuplicateRecordFields

**Decision: rely on `DuplicateRecordFields` (already on); never
use `OverloadedRecordDot` on the Term records.**

`keiki.cabal` enables `DuplicateRecordFields` project-wide, so
two record types with a shared field name (e.g.
`RegistrationStartedTermFields { email :: ... }` and
`AccountConfirmedTermFields { email :: ... }`) coexist without
conflict. The relevant operations are:

- **Construction (`Foo { email = ..., ... }`).** Unambiguous: the
  record name names the type. Always works.
- **Field selector (`email rec`).** Ambiguous when two records
  share the field; with `DuplicateRecordFields` GHC requires
  explicit disambiguation. Not needed for our use case — we
  never read fields off the record, only construct one and pass
  it to `B.emit`.
- **OverloadedRecordDot (`rec.email`).** Same ambiguity; same
  resolution. Not needed.

Net effect: M4's surface is a *write-only* record. The
constructor disambiguates the type; field selectors are not
used. Field-name clashes between events are silently fine.

## Q3 — interaction with `mkWireCtorVia` and `FieldsOf`

**Decision: TH emits the `ToOutFields` instance hand-rolled in
field order, not a generic-Rep walk.**

`WireCtor co fs` carries `fs ~ FieldsOf <Payload>`, the nested-
pair tuple `(f1, (f2, ..., (fn, ())))`. The `ToOutFields`
instance must produce an `OutFields rs ci fs` of exactly that
shape.

Two implementation paths:

1. **Hand-rolled per-event:** the TH knows the field order it
   emitted (it walks `<Payload>`'s ctor fields). The instance is:

   ```haskell
   instance ToOutFields (AccountConfirmedTermFields rs ci) rs ci
                        (Email, (ConfirmationCode, (UTCTime, ()))) where
     toOutFields r = OFCons (email r)
                       (OFCons (confirmCode r)
                         (OFCons (at r) OFNil))
   ```

   Each field selector is qualified by the record type's name
   (via `DuplicateRecordFields` / record selectors), so two
   events sharing a field name produce two distinct selectors.

2. **Generic-Rep-driven:** add a `Generic` derivation to the
   per-event record and rely on `gToTuple` (already in
   `Keiki.Generics`) to walk the Rep. Requires the record to
   have the same field *order* as `<Payload>` — fragile if a
   future TH refactor changes ordering, and it adds a `Generic`
   instance per record.

Choose (1). The TH is already walking the payload's fields; the
walk that emits the record is the same walk that emits the
instance body. Order alignment is enforced by a single TH source.

The instance constraint shape:

```haskell
class ToOutFields rec rs ci fs | rec -> rs ci fs where
  toOutFields :: rec -> OutFields rs ci fs
```

Functional dependency `rec -> rs ci fs`: a per-event record
type uniquely determines all three. This makes type inference
predictable at the call site — the user writes
`B.emit wireFoo FooTermFields { ... }` and GHC propagates `rs`,
`ci`, `fs` from the record type alone.

A second instance handles the operator form:

```haskell
instance ToOutFields (OutFields rs ci fs) rs ci fs where
  toOutFields = id
```

GHC dispatches between the two by the record type vs.
`OutFields` shape — no overlap because no record type has the
nested-pair shape `(_, (_, ..., ()))`.

## Q4 — error-message shape

**Decision: rely on stock GHC messages; no custom `TypeError`
needed at M4. Revisit at M6 if a user-facing case emerges
where the stock message is unhelpful.**

Worked cases:

| Mistake | GHC stock message | Quality |
|---|---|---|
| Missing field | `Constructor 'AccountConfirmedTermFields' does not have the required strict fields: at` | Good — names the type and the missing field. |
| Extra/typo field | `'emial' is not a (visible) constructor field name` (or similar with DuplicateRecordFields) | Good — names the offending label. |
| Wrong field type | `Couldn't match expected type 'Term rs ci ConfirmationCode' with actual type 'Term rs ci Email' • In the 'confirmCode' field of a record construction` | Good — names the field and shows the type mismatch. |
| Wrong wire ctor (e.g. `B.emit wireRegistrationStarted AccountConfirmedTermFields {...}`) | `Couldn't match type ... in the second argument of 'B.emit'` (functional dep on `ToOutFields` resolves the `fs` from the record; `WireCtor`'s `fs` is fixed by `wireRegistrationStarted`; mismatch is reported at the call site) | Good — the `fs` mismatch surfaces at the emit call. |

The existing `mkWireCtorVia` already produces messages of
similar quality on the wire side; users will find the
record-side messages familiar.

If a user case surfaces in M4/M5 testing where the stock
message is misleading (e.g. an inference failure that
materialises far from the call site), wrap the offending
constraint with a `TypeError` and re-record under
"Surprises & Discoveries" in EP-21.

## Worked example — UserRegistration `Confirm` edge

Pre-M4 (post-M2, current):

```haskell
B.from RequiresConfirmation do
  B.onCmd inCtorConfirm $ \d -> B.do
    B.requireEq d.confirmCode #confirmCode
    B.slot @"confirmedAt" .= d.at
    B.emit wireAccountConfirmed
      (#email *: d.confirmCode *: d.at *: B.oNil)
    B.goto Confirmed
```

Post-M5:

```haskell
B.from RequiresConfirmation do
  B.onCmd inCtorConfirm $ \d -> B.do
    B.requireEq d.confirmCode #confirmCode
    B.slot @"confirmedAt" .= d.at
    B.emit wireAccountConfirmed AccountConfirmedTermFields
      { email       = #email
      , confirmCode = d.confirmCode
      , at          = d.at
      }
    B.goto Confirmed
```

Under the hood, `AccountConfirmedTermFields` is generated by the
extended `deriveWireCtors`:

```haskell
data AccountConfirmedTermFields rs ci = AccountConfirmedTermFields
  { email       :: Term rs ci Email
  , confirmCode :: Term rs ci ConfirmationCode
  , at          :: Term rs ci UTCTime
  }

instance ToOutFields (AccountConfirmedTermFields rs ci) rs ci
                     (Email, (ConfirmationCode, (UTCTime, ()))) where
  toOutFields r = OFCons (email r)
                    (OFCons (confirmCode r)
                      (OFCons (at r) OFNil))
```

The pattern is mechanical: one record per event ctor, one
instance per record. `B.emit` is overloaded once.

## Implementation outline (M4)

Tasks, in order:

1. **Define the `ToOutFields` typeclass** in `Keiki.Builder`
   (or in a new `Keiki.Builder.Types` if the surface bloats —
   not expected at M4).
2. **Add the passthrough instance** for `OutFields rs ci fs` so
   the M2 operator form continues to work through the same
   `B.emit` overload.
3. **Extend `Keiki.Generics.TH.genWire`** (or add a sibling
   helper) to emit, per event ctor:
   - the record data type `<CtorName>TermFields rs ci` with
     `Term rs ci T` fields keyed by the payload's selector
     names, in the payload's field order;
   - the `ToOutFields` instance.
4. **Replace the existing `B.emit`** (which currently takes
   `WireCtor co fs -> OutFields rs ci fs`) with a typeclass-
   overloaded version:

   ```haskell
   emit :: ToOutFields rec rs ci fs
        => WireCtor co fs -> rec -> EdgeBuilder rs ci co v w w ()
   ```

5. **Add 2–3 unit cases** to `test/Keiki/BuilderSpec.hs`
   asserting the record form and the operator form produce
   identical `OutFields` for the same data.

## Out of scope for M4

- Auto-derived `WireCtor` from the record-of-Terms type alone.
  The wire ctor still comes from `mkWireCtorVia` on the payload.
- A quasi-quoter (`[emit| ... |]`).
- Customising the record name; it is always
  `<CtorName>TermFields`.
- Singleton (no-payload) events. The existing
  `deriveWireCtors` rejects them; M4 does the same.

## Open questions deferred to M5/M6

- Whether the existing operator form should be deprecated at M6
  (after example migration). Decision deferred to M6's
  documentation pass; M5's migration data informs the call.
- Whether `emitWith` (the explicit-InCtor escape hatch) should
  also accept a `<CtorName>TermFields` record. Likely yes for
  consistency; folded into M4 if cheap.
