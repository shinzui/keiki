# B-presentation views

How to derive and consume per-vertex views — the **B-presentation
layer** that exposes only the slots live in each control vertex.

This guide assumes the user-guide vocabulary (`SymTransducer`,
`RegFile`, slot, vertex). For the design rationale see
`docs/research/genview-th-splice-design.md` and the synthesis doc
§3 ("B is an optional presentation layer").

---

## 1. What a B-view is and why you might want one

The `RegFile` of a `SymTransducer` is a flat tuple of *all* slots
the aggregate ever uses. At any single control vertex, only some
of those slots are *live* — the rest are either uninitialised or
stale:

| Vertex | Live slots in `userReg` |
|---|---|
| `PotentialCustomer` | none |
| `Registering` | none |
| `RequiresConfirmation` | `email`, `confirmCode` |
| `Confirmed` | `email`, `confirmedAt` |
| `Deleted` | `email`, `deletedAt` |

A consumer looking at "what's the state of this aggregate?" wants
to read those vertex-specific fields, not navigate the full
register file and remember which slots are live. The B-view is
that vertex-specific shape.

`deriveView` emits three things:

- A **singletons GADT** indexed by the vertex enum
  (`SUserVertex` → `SPotentialCustomer`, `SRegistering`, …).
- A **per-vertex View GADT** with one constructor per vertex
  carrying the live slots as record fields
  (`UserView` →
   `PotentialCustomerV`,
   `RegisteringV`,
   `RequiresConfirmationV { rcEmail, rcConfirmCode }`,
   `ConfirmedV { cEmail, cConfirmedAt }`,
   `DeletedV { dEmail, dDeletedAt }`).
- A **projection function** `userView :: SUserVertex v -> RegFile rs -> UserView v`.

Pattern-matching on `userView SConfirmed regs` yields a
`ConfirmedV` whose record selectors are the live slots only —
the type system blocks the reader from asking `SPotentialCustomer`
for `cConfirmedAt`.

The view is **opt-in**. Nothing in the transducer references it;
you call it from a serialiser, UI layer, or read-side projection.

---

## 2. Deriving the view

The splice signature:

```haskell
deriveView
  :: Name              -- vertex enum, e.g. ''Vertex
  -> Name              -- register-file slot list, e.g. ''UserRegRegs
  -> String            -- name of the singletons GADT  (e.g. "SUserVertex")
  -> String            -- name of the View GADT        (e.g. "UserView")
  -> String            -- name of the projection fn    (e.g. "userView")
  -> [(String, [String])]   -- per-vertex spec
  -> Q [Dec]
```

The spec is a list of `(vertexCtorName, [liveSlotName])` pairs:

```haskell
$(deriveView ''Vertex ''UserRegRegs
    "SUserVertex" "UserView" "userView"
    [ ("PotentialCustomer",    [])
    , ("Registering",          [])
    , ("RequiresConfirmation", ["email", "confirmCode"])
    , ("Confirmed",            ["email", "confirmedAt"])
    , ("Deleted",              ["email", "deletedAt"])
    ])
```

The splice runs five validation checks at compile time. Each
failure is a descriptive `fail` from the splice — read the error,
fix the spec.

| Check | Failure |
|---|---|
| Spec covers every vertex constructor | `deriveView: spec is missing constructors of …` |
| Spec doesn't name unknown vertices | `deriveView: spec lists vertex(es) … not in …` |
| Spec doesn't list a vertex twice | `deriveView: spec lists vertex(es) … twice` |
| Every named slot exists in `Regs` | `deriveView: spec entry … names slot(s) not in …` |
| Per-vertex field-name prefixes are unique | `deriveView: vertices … share field-name prefix …` |

The prefix-uniqueness check is the most surprising: the generated
record selectors are
`<vertexPrefix><SlotName>` (`cEmail`, `cConfirmedAt`, `rcEmail`,
…), so two vertices can't share a lowered-cased prefix.
`Confirmed` → `c`, `RequiresConfirmation` → `rc` is fine;
`ConfirmedAccount` and `Continuing` would collide on `c` and one
of them needs renaming.

---

## 3. Consuming a view

```haskell
import Jitsurei.UserRegistration
  ( SUserVertex (..)
  , UserView (..)
  , userView
  , Vertex (..)
  )

renderUser :: Vertex -> RegFile UserRegRegs -> Text
renderUser PotentialCustomer regs = case userView SPotentialCustomer regs of
  PotentialCustomerV -> "no user"

renderUser Confirmed regs = case userView SConfirmed regs of
  ConfirmedV { cEmail, cConfirmedAt } ->
    cEmail <> " confirmed at " <> tShow cConfirmedAt
…
```

The projection takes a singleton (`SConfirmed`, not `Confirmed`)
because the View GADT is *indexed* by the promoted vertex type.
The singleton tells the type system which `View` constructor
will come back.

Type-system guarantees the view buys you:

- Reading `cConfirmedAt` against any vertex other than `Confirmed`
  is a type error.
- A pattern match that doesn't cover all view constructors is a
  warning under `-Wincomplete-patterns`.
- Adding a new vertex to the aggregate (and to the spec) forces
  every consumer's pattern match to be updated.

---

## 4. The "ignores stale slots" property

The view projection only reads the slots its spec lists. Slots
not named in the spec aren't read — even if they're bound to
`error` or to a stale value left over from a previous transition,
the projection doesn't crash.

`jitsurei/test/Jitsurei/UserRegistrationViewSpec.hs` exercises this
explicitly:

```haskell
let partial =
        RCons (Proxy @"email")        "alice@x"
      $ RCons (Proxy @"confirmCode")  (error "unread: confirmCode")
      $ RCons (Proxy @"registeredAt") (error "unread: registeredAt")
      $ RCons (Proxy @"confirmedAt")  (t 100)
      $ RCons (Proxy @"deletedAt")    (error "unread: deletedAt")
      $ RNil
userView SConfirmed partial
  `shouldBe` ConfirmedV "alice@x" (t 100)
```

Three of the slots are bound to `error`; only `email` and
`confirmedAt` are real values. The projection succeeds because
`Confirmed`'s spec is `["email", "confirmedAt"]` — the other slots
aren't touched.

This property has two practical consequences:

1. The default `emptyRegFile` (which binds every slot to a
   deferred `"uninit: <slot>"` error) is safe to project from at
   any vertex. Reads of uninitialised slots crash with a targeted
   message; reads of stale slots that the view doesn't include
   never happen.
2. You can write a per-vertex serialiser that doesn't need to
   defensively check whether a slot has been bound. The view's
   spec encodes the invariant.

---

## 5. Naming convention for selectors

The TH splice derives record-selector names mechanically:

```
field name = vertex prefix + capitalised slot name
```

The vertex prefix is the lowercase concatenation of the vertex
constructor's uppercase letters (`RequiresConfirmation` → `rc`,
`Confirmed` → `c`, `EmailSentVertex` → `esv`).

You can read the field-name prefix table off `deriveView`'s spec
list at a glance: it's the first letter of each capitalised
fragment of the vertex name.

If the prefix-uniqueness check rejects your spec, rename a vertex
or live with the rename. The mechanical convention is a hard part
of the splice's behaviour; there's no user-facing override.

---

## 6. Adding a slot to a vertex

When the aggregate's behaviour changes and a vertex now uses a new
slot, the workflow is:

1. **Add the slot to the register file's slot list** if it wasn't
   there.
2. **Author the writes** in the transducer (in the builder, an
   extra `slot @"newSlot" .= …`; in the AST, an extra `USet …`).
3. **Update the spec list** passed to `deriveView` — add
   `"newSlot"` to the live-slot list of the affected vertex.
4. **Update consumers** — every pattern match on the View GADT
   that names the affected vertex's constructor will need to be
   updated to match the new field, or the compiler will warn.

The TH splice's compile-time checks catch the spec-vs-regs
divergence; pattern-completeness warnings catch the consumer
divergence.

---

## 7. When to use the view

Reach for the view when:

- A serialiser, UI, or external API needs the aggregate's current
  state in a vertex-specific shape.
- A read-side projection is materialising the aggregate's state
  for consumers who don't need to know about the underlying
  register file.
- A test wants to assert "the aggregate is in `Confirmed` with
  these specific fields" cleanly.

Don't use the view when:

- The transducer itself is reading state. The transducer already
  has typed access to the register file; the view is for
  consumers.
- You want to check arbitrary slot combinations that aren't
  vertex-specific. The view enforces the vertex-specific shape; if
  you need flexibility, read the register file directly.
- You need a *write* path. The view is read-only; updates flow
  through commands and the transducer.

The view is a presentation tool, not a state-management tool.

---

## 8. Why "B"

The "B" in "B-view" is alphabetical, from the data-carrying-state
exploration:

- **Direction A** — sum types with payloads (rejected; loses
  decidable analysis).
- **Direction B** — indexed state, data-per-vertex (this — the
  per-vertex shape).
- **Direction C** — symbolic and register automata (the
  formalism).

The synthesis doc settled on "C is the formalism, B is an optional
presentation layer." `deriveView` is what makes that "optional"
real: the transducer is C-shaped throughout, and the B-view is a
projection consumers opt into when they want it.

The C-foundation defines what the aggregate *is*; the B-view
defines what it *looks like* at one vertex. Both shapes are
present in the codebase because they answer different questions.

---

## 9. Pointers

- `src/Keiki/Generics/TH.hs` — `deriveView` source. The header
  haddock has the worked invocation; the body comments document
  each phase.
- `docs/research/genview-th-splice-design.md` — the design note:
  spec format, validation rules, generated-code shape, deferred
  features.
- `docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`
  §3 — why B-views are a presentation layer rather than a
  formalism.
- `jitsurei/src/Jitsurei/UserRegistration.hs` — the canonical
  five-vertex spec, with the splice and its consumers.
- `jitsurei/test/Jitsurei/UserRegistrationViewSpec.hs` — what the
  projection actually returns for each vertex, including the
  "ignores stale slots" property.
