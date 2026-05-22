# Generic-lens and label reads

keiki lets you read a register with a bare overloaded label: inside a transducer,
`#appCreditScore` resolves to a register-read `Term`, no `proj`/annotation needed. That
convenience rests on a keiki-supplied `IsLabel` instance — and it is fragile in exactly one
common situation: a project whose shared prelude re-exports `generic-lens`. When that happens,
generic-lens's own `IsLabel` instance shadows keiki's, the bare `#slot` read stops resolving to
a register read, and authors are pushed into a verbose `proj (indexOf @"slot" @Regs @Ty)`
spelling.

This page explains the mechanism, gives a one-line discipline that keeps bare `#slot` reads
working for **new** projects, and is explicit that **existing** projects need not refactor —
the `reg @"slot"` and `=:` helpers are the supported no-refactor path.

> **One-line rule (new projects).** Do not globally re-export `Data.Generics.Labels` (i.e. do
> not put `import Data.Generics.Labels ()` in a shared prelude). Import generic-lens labels only
> in the modules that actually use lens-style field optics — read models, view projections,
> handler/application code — and keep keiki transducer modules free of that import.


## 1. The mechanism

keiki ships two `IsLabel` instances in `src/Keiki/Core.hs`:

- `IsLabel s (Index rs r)` (around lines 207–210) — makes `#name` an `Index`.
- `IsLabel s (Term rs ci r)` (around lines 223–226) — makes `#name` a register-read `Term`,
  specifically `TReg (indexOf @s @rs @r)` (and `proj = TReg`, so this is the same read you would
  write as `proj (#name :: Index Regs Ty)`).

GHC picks between them by the expected result type. The second instance is what makes a bare
`#slot` usable as a register read without `proj` — *as long as it is the only `IsLabel (Term …)`
instance in scope*.

`generic-lens` provides a competing, very general `IsLabel` instance via `Data.Generics.Labels`
(its field/labels optics). The moment that instance is in scope inside a transducer module —
typically because a shared prelude re-exports it with the orphan-instance import
`import Data.Generics.Labels ()` — *both* `IsLabel` instances apply to `#slot`. The bare label
no longer resolves to keiki's register-read `Term`: it becomes ambiguous, or resolves to the
generic-lens optic, and the author is forced into the verbose
`proj (indexOf @"slot" @Regs @Ty)` form.

This is not hypothetical. The Rei migration's shared prelude does exactly this —
`rei-core/src/Rei/Prelude.hs` (line 73) has `import "generic-lens" Data.Generics.Labels ()` —
and as a result Rei reads every register via `proj (indexOf @…)`, with zero bare `#slot` reads
anywhere in its transducers.


## 2. The discipline, for new projects

A global re-export of `Data.Generics.Labels` is convenient — it makes `#field` optics available
everywhere — but it is the cheapest thing to scope, and scoping it costs nothing in the modules
that do not use field optics. So, for a new project:

- **Do** import generic-lens labels in the modules that genuinely use lens-style field optics:
  read models, view/projection code, HTTP handlers, application services.
- **Do not** re-export `Data.Generics.Labels` from a shared prelude that your keiki transducer
  modules import.

Then, inside a transducer module, bare `#slot` register reads resolve through keiki's
`IsLabel s (Term rs ci r)` instance and just work. As a bonus, keeping lens imports scoped also
reduces the parallel `.=` collision (see §5).


## 3. Before / after

**(a) Global re-export — bare `#slot` is ambiguous in a transducer.** With a prelude that
re-exports generic-lens labels:

```haskell
-- MyApp/Prelude.hs — imported by every module, including transducers
module MyApp.Prelude (module Control.Lens) where
import Control.Lens
import Data.Generics.Labels ()   -- generic-lens IsLabel. Instance imports
                                 -- are transitive regardless of the export
                                 -- list, so this is now in scope wherever
                                 -- MyApp.Prelude is imported.
```

```haskell
-- MyApp/Order/Transducer.hs
import MyApp.Prelude            -- pulls in generic-lens IsLabel
import Keiki.Builder (reg)

-- A bare #onHand read is now ambiguous / resolves to the optic, so you
-- must spell the read verbosely:
g = proj (indexOf @"onHand" @OrderRegs @Int) .>= lit 1
-- … or use keiki's reg helper, which sidesteps overloaded labels:
g = reg @"onHand" .>= lit 1
```

**(b) Scoped import — bare `#slot` compiles in the transducer.** The prelude does *not*
re-export generic-lens; modules that need field optics import them directly.

```haskell
-- MyApp/Order/Transducer.hs  (no generic-lens label instance in scope)
g = #onHand .>= lit 1          -- resolves to keiki's IsLabel (Term …) → a register read
```

```haskell
-- MyApp/Order/ReadModel.hs    (this module uses field optics, so it imports them here)
import Data.Generics.Labels ()
summary o = o ^. #status        -- generic-lens optic, scoped to where it is used
```


## 4. Existing projects need not refactor

This discipline is the recommended default for **new** projects. It is **not** a request to
refactor an existing one. A project (like Rei) already committed to a global generic-lens
re-export keeps working unchanged, because keiki ships a no-refactor path:

- **`reg @"slot"`** reads a register as a `Term` via a *type application*, not an overloaded
  label. generic-lens's `IsLabel` cannot shadow it, so `reg @"appCreditScore"` resolves to the
  register read regardless of what is in scope. It is the read-side mirror of `slot @"name"`.
- **`=:`** is an exact synonym for the builder's `.=` (see §5), so a module that also imports
  `Control.Lens` need not write `import Control.Lens hiding ((.=))`.

The two approaches are **complementary, not either/or**: import-scoping is the cheap default
for new code, and the helpers are the supported escape for code that cannot (or does not want
to) scope its imports.


## 5. The parallel `.=` collision

The same shape appears with the builder's slot-write operator `.=`, which collides with
`Control.Lens`'s state-setting `.=`. A module that authors edges *and* imports `Control.Lens`
would otherwise need `import Control.Lens hiding ((.=))`.

The fixes are parallel to the read side:

- **Scope the lens import** where you can (the same discipline as §2 — don't drag
  `Control.Lens` into transducer modules that don't need it).
- **Use `=:`** where you can't. `slot @"x" =: t` is exactly `slot @"x" .= t` (same `infixr 6`
  fixity, same resulting `Update`); it just avoids the `.=` name.

(A colon-prefixed `:=` is **not** available: Haskell reserves operators beginning with a colon
for data constructors, so a value-level synonym must start with another symbol — hence `=:`.)


## 6. Pointers

- `docs/guide/user-guide.md` — the "Terms" and "Slot writes" subsections (`#name`, `reg @"name"`,
  `.=`, `=:`).
- `src/Keiki/Core.hs` — the `IsLabel s (Index rs r)` and `IsLabel s (Term rs ci r)` instances
  (around lines 207–210 and 223–226) and `proj = TReg`.
- `src/Keiki/Builder.hs` — the `reg` and `=:` helpers.
