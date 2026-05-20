# Symbolic CI

How to wire keiki's symbolic single-valuedness check into a CI
pipeline so a malformed transducer fails the build, not production.

This guide is the operator companion to
`docs/research/symbolic-analysis-and-runtime-implications.md`
(what symbolic analysis means and what it costs) and the user-guide
§7 (what the API looks like). Read those first if you need context.

---

## 1. What you get

```haskell
isSingleValuedSym (withSymPred yourAggregate) :: Bool
```

`True` iff, at every reachable vertex, no two outgoing-edge guards
are simultaneously satisfiable. This is the synthesis-§7
single-valuedness invariant decided symbolically by z3.

The pre-symbolic alternative is a Hedgehog property test — it
generates inputs and checks that at most one edge fires per case.
Property tests are sound under their generator's coverage but
imprecise: a counterexample the generator never produces can hide
indefinitely. The symbolic check answers the question
exhaustively.

---

## 2. The shopping list

For a CI image to run the check, three things need to be present.

| Requirement | Provisioned by |
|---|---|
| `sbv ^>=11.7` resolved into the build plan | `keiki.cabal` already lists it |
| `z3` binary on `PATH` | OS install on the CI image |
| GHC 9.10.3+ | The repo's `flake.nix` / `cabal.project` pins |

For the OS install:

- **Debian/Ubuntu CI image.** `apt-get install -y z3`
- **Alpine.** `apk add z3`
- **macOS runner.** `brew install z3`
- **Nix-driven CI.** Add `pkgs.z3` to the dev shell or test build
  inputs. The repo's `flake.nix` already pulls a compatible z3.

A dropped-in z3 binary (downloaded artifact, copied into the
image) works as well — SBV looks up the binary on `PATH` and
shells out. There's no deeper integration.

---

## 3. The minimal spec

A single Hspec block per aggregate is enough:

```haskell
module YourAggregateSymbolicSpec (spec) where

import Test.Hspec
import Keiki.Symbolic (isSingleValuedSym, withSymPred)
import YourModule (yourAggregate)

spec :: Spec
spec = describe "isSingleValuedSym (withSymPred yourAggregate)" $
  it "answers True (the structural single-valuedness gate)" $
    isSingleValuedSym (withSymPred yourAggregate) `shouldBe` True
```

The `withSymPred` adapter re-tags the transducer's edge guards
from `HsPred` to `SymPred` so the v2 `BoolAlg` instance fires.
The aggregate itself stays in `HsPred`-shape — no source-level
changes to your transducer.

The reference fixture at
`jitsurei/test/Jitsurei/UserRegistrationSymbolicSpec.hs` adds three
optional bands of coverage worth borrowing for any non-trivial
aggregate:

```haskell
describe "sat over the aggregate" $ do
  it "satisfiable: PInCtor on a real ctor" $
    isJust (sat (SymPred (PInCtor inCtorConfirm))) `shouldBe` True

  it "unsatisfiable: PInCtor mutex" $
    isJust (sat (SymPred (PAnd (PInCtor inCtorConfirm)
                               (PInCtor inCtorResend))))
      `shouldBe` False

describe "symSatExt round-trip" $ do
  it "edge-guard sat → witness → models agrees" $ do
    let g = guard (head (edgesOut yourAggregate SomeVertex))
    case symSatExt g of
      Nothing       -> expectationFailure "edge guard reported unsat"
      Just (rs, ci) -> evalPred g rs ci `shouldBe` True
```

The first band sanity-checks the SBV translation hasn't drifted
(satisfiable predicates still satisfy; mutexes still report
unsat). The second band verifies witness extraction — the solver
gives back a model, and `evalPred` on the reconstructed
`(RegFile, ci)` agrees with the predicate. Drift in either is a
signal something has changed in the symbolic surface or the
aggregate's input ctor declarations.

> Since EP-44, `sat` is a method of the `Sat` class (a subclass of `BoolAlg`,
> not `BoolAlg` itself) and on `SymPred` returns the **same real witness** as
> `symSatExt` — so `case sat (SymPred g) of Just w -> models (SymPred g) w` is a
> valid round-trip too (it was a crash before EP-44, when `sat` returned a
> placeholder). The witness-free "is it satisfiable?" check that needs no
> `ExtractRegFile`/`KnownInCtors` evidence is `not . symIsBot`.

---

## 4. Where to put it in the test tree

The repo convention (followed by `UserRegistrationSymbolicSpec`):

```
test/
  Keiki/
    Examples/
      YourAggregateSymbolicSpec.hs    -- this module
```

Hook into the test suite via `Spec.hs`'s discovery (Hspec auto-
discovers `*Spec.hs` modules under the test source dir). Confirm
with `cabal test --test-show-details=direct` and look for the
`describe` line in the output.

---

## 5. CI pipeline shape

The pipeline does five things in order:

```
1. Resolve build plan        ← cabal needs sbv to resolve
2. Install z3                ← OS package; cache it
3. Build                     ← cabal build
4. Test                      ← cabal test, including the symbolic spec
5. Report                    ← test summary
```

Steps 1 and 3 don't need z3. Steps 2 and 4 do. If your CI is
slow, cache the z3 install — it doesn't change between runs.

A representative GitHub Actions snippet:

```yaml
- name: Install z3
  run: sudo apt-get install -y z3

- name: Build and test
  run: |
    cabal build all
    cabal test all
```

For Nix-driven CI, `nix flake check` already pulls the dev shell's
z3 transitively. No separate install step is needed.

---

## 6. Cost and timing

Per `docs/research/symbolic-analysis-and-runtime-implications.md`:

- ~10ms per `isBot` call warm.
- `isSingleValuedSym` calls `isBot` once per pair of outgoing
  edges per vertex. For an aggregate with five vertices and at
  most three edges per vertex, the upper bound is
  5 × C(3, 2) = 15 calls. Real-world: a few hundred milliseconds
  total in the test stage.

This is well below typical test-suite overhead and should not
visibly slow CI. If you see it dominating wall time, you're
likely hitting an edge case where SBV's z3 dispatch is doing
something pathological — open an issue with the predicate that
triggers it.

`Unknown` from the solver (out-of-fragment / timeout) is treated
conservatively: `isBot` returns `False`, so
`isSingleValuedSym` returns `False`. A spurious `False` will fail
your CI check; the surrounding error will name the edges. Most
real-world predicates over the curated `Sym` set
(`Bool`/`Int`/`Integer`/`Text`/`UTCTime`) are inside z3's
decidable fragment.

---

## 7. When the check fails

If `isSingleValuedSym (withSymPred yourAggregate) == False`, the
diagnosis path:

1. **Find the offending vertex.** Add a debug print or break the
   spec into per-vertex assertions:
   ```haskell
   forM_ [minBound .. maxBound] $ \v ->
     it ("vertex " <> show v <> " is single-valued") $
       all (\(g1, g2) -> isBot (g1 `conj` g2))
           (edgePairs (withSymPred yourAggregate) v)
         `shouldBe` True
   ```
2. **Read the offending pair's guards.** They must be
   simultaneously satisfiable. Common causes:
   - Two edges out of the same vertex that match the same input
     constructor without disambiguating predicates (`requireEq`).
     Fix: add `requireEq` (or, for a threshold, the ordering verbs
     `requireLt`/`requireLe`/`requireGt`/`requireGe`, or
     `requireGuard`) to one edge so the guards become mutually
     exclusive. Ordering guards (`PCmp`) are solver-visible over the
     curated numeric types, so `requireGe #amount (lit 1000)` on one
     edge and `requireLt #amount (lit 1000)` on the other proves the
     split.
   - An edge with a stronger and a weaker form of the same
     condition (`top` and `requireEq … …`). Either merge them or
     add a negation.
3. **`symSatExt` the conjunction.** A concrete witness will tell
   you exactly which input fires both edges.

If the check legitimately *should* return `False` (the aggregate
is intentionally non-deterministic), suppress the spec for that
aggregate and document the choice. Non-deterministic FSTs lose
keiki's analytical guarantees; this is a deliberate move, not the
default.

---

## 8. When **not** to wire the check

The check is a hard CI gate. Skip it for:

- Aggregates with `TApp1` / `TApp2` escape hatches in their
  guards. The translator falls back to fresh variables and the
  check loses precision (it may say `False` when the answer is
  `True`). Either drop the escape hatch or accept a property test
  in its place. Note: a bare threshold (`amount >= 1000`) needs no
  escape — use the structural ordering guard (`PCmp` via `requireGe`
  etc.); and a *computed* operand (a weighted sum, a derived cap)
  needs no escape either since EP-43 — write it with the structural
  arithmetic terms `tadd`/`tsub`/`tmul`. Only genuinely opaque
  Haskell (or fractional `Double`/SReal arithmetic, out of scope)
  still needs `TApp`.
- Local prototype aggregates that haven't stabilised yet. The
  check is a good signal at PR time but a bad signal during early
  drafting — false positives slow you down. Add it once the
  aggregate has shape.
- Aggregates whose register file uses types outside the curated
  `Sym` set (`Bool`, `Int`, `Integer`, `Text`, `UTCTime`, and the
  fixed-width integers `Word8`/`Word16`/`Word32`/`Word64`/`Int32`/
  `Int64`). The translator falls back to fresh variables for other
  types; same precision loss. Either add a `Sym` instance for the
  type or treat the imprecision as known.

For everything else — and certainly for any aggregate that ships
to production — the check belongs in CI.

---

## 9. Pointers

- `Keiki.Symbolic` — module-level haddock; per-export
  documentation.
- `docs/research/symbolic-analysis-and-runtime-implications.md`
  — what symbolic analysis is, what it does, what it costs.
- `docs/research/sbv-boolalg-design.md` — the design log
  behind the SBV-backed `BoolAlg` instance.
- `jitsurei/test/Jitsurei/UserRegistrationSymbolicSpec.hs` — the
  reference fixture: single-valuedness gate, sat smoke checks,
  `symSatExt` round-trip.
