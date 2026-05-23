---
id: 53
slug: harden-inctor-identity-for-structural-replay
title: "Harden InCtor identity for structural replay"
kind: exec-plan
created_at: 2026-05-23T04:34:53Z
---

# Harden InCtor identity for structural replay

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

Structural replay in keiki recovers an input command from an observed output event by walking an `OutTerm`. Today that recovery treats two `InCtor` values as the same constructor when their public `icName :: String` fields match, and then uses `unsafeCoerce` to reinterpret an input-field index. A malformed or hand-written pair of `InCtor`s can reuse the same name with different field schemas, making replay type-unsafe.

After this change, replay still uses constructor names for human-readable diagnostics, Mermaid labels, and grouping, but it no longer treats a string match as type evidence. The implementation compares richer schema evidence before accepting a `TInpCtorField` as belonging to the `OPack`'s `InCtor`; if the names match but the schemas differ, `solveOutput` returns `Nothing` instead of coercing an index. The behavior is visible through a regression test that constructs two colliding `InCtor`s and proves the bad output no longer round-trips.

Scope, stated precisely: this change buys *type soundness* — after it, the index recovered from a `TInpCtorField` is provably valid for the schema it is assembled into, with no `unsafeCoerce` — not *semantic constructor identity*. Two genuinely different constructors that happen to share both `icName` and field schema would still compare equal; ruling that out is out of scope. A larger alternative that would remove the runtime comparison altogether — re-indexing `Term` / `OutFields` by the input schema `ifs` so the `OPack`'s `InCtor` and the `TInpCtorField` agree by construction — is deliberately *not* attempted here: it is a substantial, unproven re-parameterization of the term/output language rather than a tidy field removal (both schemas are existentially hidden today, and `Term` is a shared InCtor-agnostic AST). See the Decision Log entry dated 2026-05-23 on scoping for why, and for the suggestion to spike that redesign before committing to it.


## Progress

- [ ] Add a focused regression test in `test/Keiki/CoreSpec.hs` that demonstrates the current `icName` collision hazard.
- [ ] Add schema evidence to `Keiki.Core.InCtor` and use it to compare `TInpCtorField` schemas before assembling `ByIndex` entries.
- [ ] Remove the `unsafeCoerce` import and call from `src/Keiki/Core.hs` if no other code in the module needs it.
- [ ] Update public Haddock in `src/Keiki/Core.hs` to state the new replay identity rule and the remaining uniqueness expectation for `icName`.
- [ ] Audit constructor helpers in `src/Keiki/Generics.hs` and `src/Keiki/Generics/TH.hs` to ensure generated `InCtor`s still compile and require no caller changes.
- [ ] Run the targeted and full validation commands listed in this plan.


## Surprises & Discoveries

- Validation pass (2026-05-23): every code reference in this plan was checked against the working tree and confirmed accurate — the dangerous `unsafeCoerce` in `gatherInpEntries.stepOne` (`src/Keiki/Core.hs:1133`), the `InCtor` GADT and its `(AssembleRegFile ifs, KnownSlotNames ifs)` context (`src/Keiki/Core.hs:297`), the test vocabulary in `test/Keiki/CoreSpec.hs` (`TinyCmd`, `inCtorTinyFoo`, `wireTinyFoo`, `TinyCmdOut`/`TinyFooOut`, and the `"solveOutput structural path (TInpCtorField)"` group), and the helper names in `src/Keiki/Generics.hs`. The toolchain is GHC 9.12.2 with `default-language: GHC2024`. `cabal test all` builds the four suites named in Validation (`keiki-test`, `jitsurei-test`, `keiki-codec-json-test`, `keiki-codec-json-test-test`).

- The exact comparison import already exists and is exercised in the project: `src/Keiki/Symbolic.hs:96` reads `import Type.Reflection (eqTypeRep, typeRep, type (:~~:) (HRefl))`, and lines 241–251 use the `Just HRefl <- eqTypeRep (typeRep @r) (typeRep @…)` shape. This is a working precedent for the `sameInCtorReplaySchema` helper, including the `forall`-scoped `@`-type-application style.

- Two `InCtor` *construction* sites beyond the generics helpers exist and were verified safe: `inCtorUnit` (`src/Keiki/Symbolic.hs:737`, concrete `InCtor () '[]`, `Typeable` automatic) and `leftInCtor` / `rightInCtor` (`src/Keiki/Composition.hs:496`/`508`, polymorphic `ifs` but they pattern-match `InCtor{ ... }`, which releases the new `Typeable ifs` evidence into scope, so the reconstruction compiles unchanged). Milestone 4 now names all five construction sites.

- Subtlety in the regression fixture: `inCtorTinyFooRenamed` reuses the field *types* `Int, Int` and only renames the slots, so the pre-fix `unsafeCoerce` is value-safe and incorrectly recovers `Just (TinyFoo 7 11)` rather than crashing. The negative-result test (`== Nothing`) still proves the schema-identity rule. Forcing a *memory*-unsafe collision through `solveOutput` is hard because the `WireCtor`'s field-tuple type pins each projected field's type, so a schema-identity test is the right shape here.


## Decision Log

- Decision: Compare `InCtor` field-schema type evidence before accepting a matching `icName`.
  Rationale: This is the smallest change that removes the type-unsound use of `unsafeCoerce` while preserving the existing authoring API, generated names, rendered labels, and user-facing diagnostics. A fully unforgeable constructor identity would require a larger API redesign and is not necessary to stop the concrete type-safety bug.
  Date: 2026-05-23

- Decision: Keep `icName` as a human-readable label and require it to remain unique within a command alphabet for semantic clarity.
  Rationale: Two different constructors with the same name and the same field schema would no longer be type-unsafe after schema comparison, but they would still be confusing for diagnostics, symbolic constructor tags, and composition. The implementation should document the uniqueness rule and tests should cover the type-unsafe different-schema collision.
  Date: 2026-05-23

- Decision: Specify the `sameInCtorReplaySchema` helper with an explicit `forall ci ifs1 ifs2.` and `InCtor{}` pattern matches on both arguments, and pin the import to `Type.Reflection (eqTypeRep, typeRep, type (:~~:) (HRefl))`.
  Rationale: Validation showed the type-only sketch would not compile as written. Under GHC2024 the `@ifs1` / `@ifs2` type applications require the variables to be lexically scoped (explicit `forall`), and the `Typeable ifs` evidence needed by `typeRep` is packed in the GADT and only released by matching the `InCtor` constructor (the `icName` selector does not release it). The chosen import line is the one already used in `src/Keiki/Symbolic.hs`.
  Date: 2026-05-23

- Decision: Treat only `mkInCtor` and `mkInCtorVia` as needing a new `Typeable ifs` constraint; leave `mkInCtor0`, `inCtorUnit`, `leftInCtor`, `rightInCtor`, and the TH splices untouched.
  Rationale: Validation enumerated all five construction sites. `mkInCtor` / `mkInCtorVia` construct at polymorphic `ifs` and cannot discharge `Typeable` internally. The others either construct at a concrete `ifs` (automatic `Typeable`) or pattern-match an existing `InCtor` (which releases the evidence), so adding constraints there would be unnecessary churn.
  Date: 2026-05-23

- Decision: Scope this plan to a runtime schema comparison rather than a type-level redesign of the term/output language.
  Rationale: The reason a comparison is needed at all is that an `OutTerm` stores an `InCtor` in *two* places — once on `OPack` and once on each `TInpCtorField` inside its `OutFields` — with nothing forcing the two to agree, so `gatherInpEntries` must reconcile the `OPack`'s `ifs` against the `TInpCtorField`'s hidden `ifs2` at run time. This runtime reconciliation is not just an oversight that a small refactor would remove: both `ifs` values are *existentially hidden* (the `TInpCtorField`'s inside `Term rs ci r`, the `OPack`'s inside `OutTerm rs ci co`), so simply dropping the `InCtor` field from `TInpCtorField` would remove the witness used to reconcile them without making the schemas line up — it leaves the inversion *more* stuck, not less. Making the schemas agree *by construction* would require indexing `Term` / `OutFields` by `ifs` (or introducing a separate input-projection term type), which works against `Term`'s role as a single InCtor-agnostic AST shared by register updates (`USet`), predicates (`PEq` / `PCmp`), and output fields — a `Term rs ci Int` can even type-check arithmetic mixing `TInpCtorField`s from two different constructors. Such a re-parameterization is a substantially larger, unproven change that would ripple into the SBV translator (`src/Keiki/Symbolic.hs`), the composition lifters (`src/Keiki/Composition.hs`), the generated `inp<Name>` splice (`src/Keiki/Generics/TH.hs` `recordDecls`), the analysis walks and evaluators in `src/Keiki/Core.hs`, and the public authoring surface, and whether it lands cleanly is not established. The runtime `eqTypeRep` check is therefore the deliberately-scoped fix: it removes the type-unsoundness now at ~30 lines with no API churn and near-zero risk. A future contributor who wants to eliminate the runtime reconciliation entirely should first *spike* re-indexing `OutFields` / `Term` by `ifs` to see whether the type errors cascade before committing to it; that cleanup is correctness-neutral relative to this change (this plan already secures soundness) and should compete for priority on its own merits, not be bundled here. Note also that the interim is cheaply discarded — any such redesign would delete these lines rather than build on them.
  Caveat on naming: this plan hardens *type soundness* (the recovered index is provably valid for the target schema), not *semantic constructor identity* — two distinct constructors that share both `icName` and field schema still compare equal. Establishing true unforgeable identity is out of scope.
  Date: 2026-05-23


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

The core types live in `src/Keiki/Core.hs`. A `RegFile rs` is a typed heterogeneous list of register values, indexed by a type-level list of slots. A slot is a pair of a type-level `Symbol` and a Haskell type, written as `'(name, type)`. An `Index rs r` is a typed pointer into a `RegFile rs` that proves the selected slot has value type `r`.

An `InCtor ci ifs` describes one constructor of the input command type `ci`. Its `ifs` parameter is the field schema for that constructor: another type-level slot list. For example, a command constructor `TinyFoo Int Int` may have an `InCtor TinyCmd '[ '("a", Int), '("b", Int) ]`. The `InCtor` record currently exposes three fields in `src/Keiki/Core.hs`: `icName :: String`, `icMatch :: ci -> Maybe (RegFile ifs)`, and `icBuild :: RegFile ifs -> ci`.

An `OutTerm rs ci co` describes how an edge emits an output event of type `co` from registers `rs` and input command `ci`. Its `OPack` constructor stores the `InCtor` that the output is recoverable from, a `WireCtor` for the output event constructor, and an `OutFields` list of terms. A `TInpCtorField` term reads one field from a command constructor through an `InCtor` and an `Index` into that constructor's field schema.

Replay goes through `solveOutput` in `src/Keiki/Core.hs`. Given an `OutTerm`, current registers, and an observed event, `solveOutput` tries to reconstruct the original input command. It calls `gatherInpEntries`, which walks the output fields and collects `TInpCtorField` values into a list of `ByIndex ifs`. The current dangerous code is in `gatherInpEntries`: when the `TInpCtorField`'s `icName` equals the `OPack`'s `icName`, it returns `ByIndex (unsafeCoerce ix) val`. That assumes a string match proves the two hidden field schemas are the same. It does not.

Most `InCtor` values are produced by helpers, not by hand. `src/Keiki/Generics.hs` defines `mkInCtor`, `mkInCtor0`, and `mkInCtorVia`, which derive constructor matching and rebuilding from `GHC.Generics`. `src/Keiki/Generics/TH.hs` defines Template Haskell splices such as `deriveAggregateCtors` and `deriveAggregateCtorsAll`, which generate top-level `inCtor<Name>` declarations. The implementation plan should preserve those helpers so ordinary aggregate authors do not need to change call sites.

Tests for the core structural replay path are in `test/Keiki/CoreSpec.hs`, especially the `"solveOutput structural path (TInpCtorField)"` group. Tests for derived-field replay behavior are in `test/Keiki/RecomputeVerifySpec.hs`. The full project uses Cabal; commands should be run from `/Users/shinzui/Keikaku/bokuno/keiki`.


## Plan of Work

Milestone 1 proves the bug with a narrow regression fixture. Add a test in `test/Keiki/CoreSpec.hs` near the existing `solveOutput structural path` tests. Define a second `InCtor TinyCmd '[ '("x", Int), '("y", Int) ]` with the same `icName` as `inCtorTinyFoo`, but with different field names from `inCtorTinyFoo`'s schema `'[ '("a", Int), '("b", Int) ]`. Use both of its fields in an `OutTerm` whose `OPack` names `inCtorTinyFoo`. The observed event should not be accepted, because the field terms belong to an incompatible constructor schema. Before the fix, this test exposes the hazard by incorrectly recovering `Just (TinyFoo 7 11)`; after the fix, it should pass by observing `solveOutput ... == Nothing`.

Milestone 2 adds real schema evidence to `InCtor`. Modify the `InCtor` GADT constructor in `src/Keiki/Core.hs` so it carries a `Typeable ifs` constraint in addition to `AssembleRegFile ifs` and `KnownSlotNames ifs`. This does not add a field visible to users; it adds evidence available when pattern matching on `InCtor`. The class `Typeable` is already imported (`import Data.Typeable (Typeable)` near the top of the module), so the constraint annotation needs no new import. For the comparison machinery, add the exact import line that the project already uses in `src/Keiki/Symbolic.hs` (line 96):

```haskell
import Type.Reflection (eqTypeRep, typeRep, type (:~~:) (HRefl))
```

Do not also import `Typeable` from `Type.Reflection`; it is the same class already imported from `Data.Typeable`, so a second unqualified import is redundant. Then add a small helper in `src/Keiki/Core.hs`, close to the `InCtor` definition or close to `gatherInpEntries`. Two details are load-bearing and a literal transcription of the type-only sketch below will *not* compile without them: (1) the signature needs an explicit `forall` so that `@ifs1` / `@ifs2` type applications in the body refer to the signature's variables (GHC2024 keeps the "explicit `forall` to scope type variables" rule); and (2) the body must pattern-match *both* arguments with `InCtor{}` to release the packed `Typeable ifs` dictionaries into scope — the record selector `icName` alone does not bring those constraints into scope, only matching the data constructor does. Write it like this:

```haskell
sameInCtorReplaySchema
  :: forall ci ifs1 ifs2.
     InCtor ci ifs1
  -> InCtor ci ifs2
  -> Maybe (ifs1 :~~: ifs2)
sameInCtorReplaySchema ic1@InCtor{} ic2@InCtor{}
  | icName ic1 == icName ic2 = eqTypeRep (typeRep @ifs1) (typeRep @ifs2)
  | otherwise                = Nothing
```

`eqTypeRep` returns `Just HRefl` exactly when the two field-schema `TypeRep`s are equal and `Nothing` otherwise, so the guard above yields `Just HRefl` only when both `icName` matches and the schemas are identical. This proven `(:~~:)` / `HRefl` shape mirrors the existing `Just HRefl <- eqTypeRep (typeRep @r) (typeRep @Bool)` usages in `src/Keiki/Symbolic.hs`, so prefer it over `(:~:)`. The important property is that the success branch refines `ifs1` and `ifs2` to the same type without `unsafeCoerce`. The schemas compared are concrete slot lists of kind `[Slot]` (e.g. `'[ '("a", Int), '("b", Int) ]`); `Typeable` for promoted list/tuple constructors, `Symbol` literals, and ordinary field types is provided automatically under GHC 9.12, so `eqTypeRep` can tell `'[ '("a", Int), '("b", Int) ]` apart from `'[ '("x", Int), '("y", Int) ]`.

Milestone 3 replaces the unsafe replay path. In `gatherInpEntries`, change the `TInpCtorField` arm so it calls the schema comparison helper. On success, return `Just [ByIndex ix val]` with no coercion. On failure, return `Nothing`. This means name collision with incompatible schemas becomes a clean replay failure. After this edit, remove `import Unsafe.Coerce (unsafeCoerce)` from `src/Keiki/Core.hs` if the module no longer uses it.

Milestone 4 updates documentation and generated-helper compatibility. Update the Haddock on `InCtor` in `src/Keiki/Core.hs` to say that `icName` is a stable human-readable constructor label and must be unique within the command alphabet for unambiguous diagnostics and symbolic tags, but replay identity is checked using both `icName` and the constructor field schema.

Then audit every site that *constructs* an `InCtor` (pattern-match sites need no change — matching `InCtor{}` only gains the new evidence). There are exactly five construction sites in the repository, and only the two polymorphic helpers in `src/Keiki/Generics.hs` need an edit:

- `mkInCtor` (`src/Keiki/Generics.hs`, ~line 129) and `mkInCtorVia` (~line 415) build an `InCtor ci ifs` at a *polymorphic* `ifs`, so GHC cannot discharge `Typeable ifs` internally. Add the minimal `Typeable ifs` constraint to both signatures. (`mkInCtorVia` is below the inspection range shown in Concrete Steps; read lines 400–460 too.) Downstream callers pass a concrete `ifs`, where `Typeable` is automatic, so no call site changes.
- `mkInCtor0` (~line 157) builds `InCtor ci '[]` at the *concrete* empty slot list; `Typeable '[]` is automatic, so it needs no change. State this so the implementer does not over-edit.
- `inCtorUnit` in `src/Keiki/Symbolic.hs` (~line 737) builds `InCtor () '[]` at a concrete slot list; `Typeable` is automatic, so it needs no change.
- `leftInCtor` and `rightInCtor` in `src/Keiki/Composition.hs` (~lines 496 and 508) have polymorphic `ifs` (`InCtor ci1 ifs -> InCtor (Either ci1 ci2) ifs`) but they pattern-match the incoming `InCtor{ ... }`, which releases the packed `Typeable ifs` dictionary; the reconstructed `InCtor{ ... }` on the right-hand side reuses that evidence, so they compile unchanged. The nearby `unsafeCoerceInCtor` (`src/Keiki/Composition.hs`, ~line 484) only changes the phantom `ci`, leaving `ifs` fixed, so the wholesale `unsafeCoerce` still type-checks.

Check `src/Keiki/Generics/TH.hs` generated signatures only if compilation requires it. The splices emit `InCtor` declarations at concrete slot lists (`mkInCtor0` for singletons, `mkInCtorVia @"Ctor"` at `InCtor Cmd (RegFieldsOf payTy)` for records), so `Typeable` is solved at each generated declaration and the generated signatures remain source-compatible for downstream users.

Milestone 5 validates the project. Run the targeted core test, the TH/generic tests, and then the full test suite. The fix is accepted only when the new collision test passes, `src/Keiki/Core.hs` no longer uses `unsafeCoerce` for `ByIndex` construction, generated aggregates still compile, and the full test suite passes.


## Concrete Steps

Work from the repository root:

```bash
cd /Users/shinzui/Keikaku/bokuno/keiki
```

First, inspect the relevant source and tests:

```bash
sed -n '270,315p;1035,1145p' src/Keiki/Core.hs
sed -n '1,240p' test/Keiki/CoreSpec.hs
sed -n '120,170p;400,460p' src/Keiki/Generics.hs
```

Add the regression test to `test/Keiki/CoreSpec.hs`. The test should be in the existing `"solveOutput structural path (TInpCtorField)"` group so it shares the `TinyCmd`, `TinyCmdOut`, `inCtorTinyFoo`, and `wireTinyFoo` vocabulary. Use a fixture like this, adjusted as needed to compile:

```haskell
let inCtorTinyFooRenamed :: InCtor TinyCmd '[ '("x", Int), '("y", Int) ]
    inCtorTinyFooRenamed = InCtor
      { icName = "TinyFoo"
      , icMatch = \case
          TinyFoo a b -> Just (RCons (Proxy @"x") a
                              $ RCons (Proxy @"y") b
                              $ RNil)
          _ -> Nothing
      , icBuild = \(RCons _ x (RCons _ y RNil)) -> TinyFoo x y
      }

    outSchemaCollision :: OutTerm '[] TinyCmd TinyCmdOut
    outSchemaCollision = OPack
      inCtorTinyFoo
      wireTinyFoo
      (OFCons (TInpCtorField inCtorTinyFooRenamed
                 (#x :: Index '[ '("x", Int), '("y", Int) ] Int))
        (OFCons (TInpCtorField inCtorTinyFooRenamed
                   (#y :: Index '[ '("x", Int), '("y", Int) ] Int))
          OFNil))
```

The assertion should state that replay rejects the collision:

```haskell
it "rejects a TInpCtorField whose icName matches but schema differs" $
  solveOutput outSchemaCollision RNil (TinyFooOut 7 11) `shouldBe` Nothing
```

Then change `src/Keiki/Core.hs`. Add `Typeable` evidence to the `InCtor` constructor. Add a helper that compares both name and field-schema `TypeRep`. Replace the current `unsafeCoerce` branch in `gatherInpEntries` with a pattern match on that helper.

Run the targeted test:

```bash
cabal test keiki:keiki-test --test-options="--match 'solveOutput structural path'"
```

Expected result after the fix is a passing `keiki-test` subset with the structural replay examples succeeding. The exact number of examples may change when the new test is added, but the final output should end with:

```text
0 failures
Test suite keiki-test: PASS
```

Run the broader checks that exercise generated `InCtor`s and downstream packages:

```bash
cabal test keiki:keiki-test --test-options="--match 'Keiki.Generics.TH'"
cabal test keiki:keiki-test --test-options="--match 'Keiki.RecomputeVerify'"
cabal test all
```

Finally, confirm that `src/Keiki/Core.hs` no longer contains the unsafe replay coercion:

```bash
rg -n "unsafeCoerce|sameInCtorReplaySchema|TInpCtorField" src/Keiki/Core.hs
```

It is acceptable for other modules such as `src/Keiki/Composition.hs` and `src/Keiki/Profunctor.hs` to still contain documented `unsafeCoerce` uses. This plan only removes the `Keiki.Core.gatherInpEntries` coercion justified solely by `icName`.


## Validation and Acceptance

The primary acceptance behavior is a negative replay case. Given an `OPack` whose declared input constructor is `inCtorTinyFoo :: InCtor TinyCmd '[ '("a", Int), '("b", Int) ]`, and whose output fields contain `TInpCtorField`s from a different `InCtor` with the same `icName` but schema `'[ '("x", Int), '("y", Int) ]`, `solveOutput` must return `Nothing`. The test named `"rejects a TInpCtorField whose icName matches but schema differs"` proves this behavior.

Existing positive behavior must remain unchanged. The existing tests in `test/Keiki/CoreSpec.hs` must still show that a complete `TInpCtorField` pair for `inCtorTinyFoo` recovers `Just (TinyFoo 7 11)`, while an incomplete output still returns `Nothing`. The existing tests in `test/Keiki/RecomputeVerifySpec.hs` must still show that derived fields are recomputed and verified, and that hidden inputs are still reported by `checkHiddenInputs`.

Run these commands from `/Users/shinzui/Keikaku/bokuno/keiki`:

```bash
cabal test keiki:keiki-test --test-options="--match 'solveOutput structural path'"
cabal test keiki:keiki-test --test-options="--match 'Keiki.RecomputeVerify'"
cabal test all
```

Acceptance requires all three commands to pass. The final `cabal test all` output should report all four test suites passing: `keiki-test`, `jitsurei-test`, `keiki-codec-json-test`, and `keiki-codec-json-test-test`.

Also run:

```bash
rg -n "unsafeCoerce" src/Keiki/Core.hs
```

Acceptance requires no output from that command. If `rg` exits with status 1 because there are no matches, that is success.


## Idempotence and Recovery

The plan is safe to run incrementally. Adding the regression test first may make the targeted test fail until the implementation is complete; that is expected and is the proof that the test covers the hazard. Re-running the same Cabal test commands is safe. Re-running the `rg` checks is safe.

If adding `Typeable ifs` to `InCtor` causes compile errors in helper functions, do not weaken the schema check. Instead, add the missing `Typeable ifs` constraints to helper signatures in `src/Keiki/Generics.hs` (`mkInCtor` and `mkInCtorVia`; see Milestone 4) or generated signatures in `src/Keiki/Generics/TH.hs`, then rerun the targeted tests. A site that *pattern-matches* an existing `InCtor` (such as `leftInCtor` / `rightInCtor` in `src/Keiki/Composition.hs`) gains the `Typeable ifs` evidence from the match and needs no new constraint — if such a site fails to compile, the fix is to ensure it actually matches the `InCtor{}` constructor, not to add a constraint. If a broader downstream module fails because it manually constructs `InCtor` for a non-`Typeable` field schema, inspect that constructor. Concrete type-level slot lists of symbols and ordinary Haskell field types should have `Typeable` instances under GHC 9.12; a failure is likely a missing constraint, not a fundamental incompatibility.

If the equality witness helper is hard to type with `(:~~:)`, try `(:~:)` from `Data.Type.Equality` after confirming both compared schemas have the same kind. Keep the property that the success branch gives GHC real equality evidence and does not use `unsafeCoerce`.

No destructive commands are needed. If an attempted edit goes in the wrong direction, use `git diff` to inspect it and manually adjust with a small patch. Do not use `git reset --hard` unless the maintainer explicitly asks for it.


## Interfaces and Dependencies

This plan uses only `base`, which is already a dependency of `keiki`. The relevant type-equality tools live in modules shipped with GHC. Prefer `Type.Reflection` for `Typeable`, `typeRep`, and `eqTypeRep` because `src/Keiki/Shape.hs` already uses `Type.Reflection` in this project. If the implementation uses `Data.Type.Equality` for `(:~:)`, that is also from `base`.

At the end of the implementation, `src/Keiki/Core.hs` must expose the same public `InCtor` record fields:

```haskell
data InCtor ci (ifs :: [Slot]) where
  InCtor
    :: (AssembleRegFile ifs, KnownSlotNames ifs, Typeable ifs)
    => { icName  :: String
       , icMatch :: ci -> Maybe (RegFile ifs)
       , icBuild :: RegFile ifs -> ci
       }
    -> InCtor ci ifs
```

The exact ordering of constraints is not important. The public fields should remain source-compatible for normal record construction, except that manually-written polymorphic helpers may need a `Typeable ifs` constraint.

`src/Keiki/Core.hs` should also contain an internal helper equivalent to:

```haskell
sameInCtorReplaySchema
  :: forall ci ifs1 ifs2.
     InCtor ci ifs1
  -> InCtor ci ifs2
  -> Maybe (ifs1 :~~: ifs2)
sameInCtorReplaySchema ic1@InCtor{} ic2@InCtor{}
  | icName ic1 == icName ic2 = eqTypeRep (typeRep @ifs1) (typeRep @ifs2)
  | otherwise                = Nothing
```

This helper does not need to be exported. It exists to make `gatherInpEntries` safe without exposing new API. The explicit `forall` and the `InCtor{}` pattern matches are required (see Milestone 2): the former scopes `ifs1` / `ifs2` for the `@`-type-applications, the latter releases the packed `Typeable ifs` dictionaries.

`gatherInpEntries` must no longer use `unsafeCoerce`. Its `TInpCtorField` case should behave like:

```haskell
stepOne (TInpCtorField ic2 ix) val ic1 =
  case sameInCtorReplaySchema ic1 ic2 of
    Just HRefl -> Just [ByIndex ix val]
    Nothing    -> Nothing
```

The exact names may differ, but the implementation must have that type-safety property. Note that in `gatherInpEntries` the argument passed as `ic1` is the `OPack`'s declared `InCtor` (schema `ifs`) and `ic2` is the `TInpCtorField`'s `InCtor` (existentially-hidden schema `ifs2`); `Just HRefl` refines `ifs ~ ifs2`, so `ix :: Index ifs2 r` becomes usable as `Index ifs r` and `ByIndex ix val :: ByIndex ifs` type-checks against the `Maybe [ByIndex ifs]` result.


## Revision Notes

- 2026-05-23 — Validation pass. Verified every codebase reference against the working tree (all accurate: the `unsafeCoerce` at `src/Keiki/Core.hs:1133`, the `InCtor` GADT, the `CoreSpec` test vocabulary, the generics helpers, GHC 9.12.2 / GHC2024, and the four `cabal test all` suites). Made the plan compile-correct and more self-contained: (1) the `sameInCtorReplaySchema` sketch now shows the explicit `forall` and the `InCtor{}` pattern matches that the type-only version omitted — without these the helper does not compile, because `@ifs1`/`@ifs2` need scoped variables and `typeRep` needs the GADT-packed `Typeable` evidence; (2) pinned the import to the exact `Type.Reflection (eqTypeRep, typeRep, type (:~~:) (HRefl))` line already used in `src/Keiki/Symbolic.hs`, and noted `Typeable` is already imported from `Data.Typeable`; (3) Milestone 4 now enumerates all five `InCtor` construction sites — `mkInCtor` and `mkInCtorVia` need the new `Typeable ifs` constraint, while `mkInCtor0`, `inCtorUnit` (`src/Keiki/Symbolic.hs`), and `leftInCtor`/`rightInCtor` (`src/Keiki/Composition.hs`) need none; (4) widened the Concrete Steps `Generics.hs` inspection range to include `mkInCtorVia`; (5) recorded the regression-fixture nuance (same field types ⇒ the pre-fix coercion is value-safe, so the test asserts the schema-identity rule via `== Nothing`). Decision Log, Surprises & Discoveries, and Idempotence updated accordingly.

- 2026-05-23 — Scoping clarification (follow-up to the validation discussion). Added a Decision Log entry recording that this plan deliberately implements a runtime schema comparison, and tightened the Purpose section to state precisely that the change delivers type soundness, not semantic constructor identity. No change to the implementation steps, milestones, or acceptance criteria — framing and future-work guidance only.

- 2026-05-23 — Softened the "alternative redesign" framing in both the Decision Log scoping entry and the Purpose section. An earlier draft of these called the alternative the "structurally cleaner fix" and described it as removing the redundant `InCtor` from `TInpCtorField`. That overstated it: a closer reading of the types shows both the `TInpCtorField`'s and the `OPack`'s `ifs` are existentially hidden, so dropping the field would remove the reconciliation witness without making the schemas line up — making the inversion more stuck, not less. The genuine alternative is to re-index `Term` / `OutFields` by `ifs`, which fights `Term`'s role as a shared InCtor-agnostic AST and is a substantial, unproven change. The wording now describes it as a larger re-parameterization to spike before committing, not a tidy refactor that is obviously better. No change to the implementation steps, milestones, or acceptance criteria.
