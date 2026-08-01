# SBV version audit — what the 14.x releases do and do not offer keiki

**Audit date: 2026-07-31. Versions in scope: 14.0 through 14.5 (plus the unreleased 14.6).**

This note records a survey of recent SBV releases against keiki's actual usage, its
in-flight plans, and its unimplemented ones. It exists so the findings are not
re-derived from scratch at the next upgrade prompt. It is a point-in-time audit, not a
living contract: re-run the checks in the last section before acting on anything here.

The dependency is canonically `mori://LeventErkok/sbv/packages/sbv`. Note that the local
Mori corpus can lead or lag Hackage — at audit time it held 14.6, which is *unreleased*.
Always confirm against Hackage and upstream tags before choosing bounds, per
[Plan 83](../plans/83-add-exact-reconstructible-symbolic-field-projection-domains.md)'s
dependency rules.


## Bottom line

keiki is already on the newest SBV release. `cabal.project`'s resolved plan selects
**14.5**, the latest on Hackage, under the existing `>=11.7 && <15` bound in
`keiki.cabal` and `jitsurei/jitsurei.cabal`. No version bump is available or needed.

Exactly one actionable item came out of this audit, and it is a build-time cost, not a
feature: **the `compile_examples` flag is still on.** Everything else is either
inapplicable to keiki's usage or is a design fact worth carrying into Plans 83 and 60.


## The one action item: turn off `compile_examples`

SBV 14.2 added a manual cabal flag gating the `Documentation.SBV.Examples.*` modules. It
defaults to `True`, so every SBV build in this project compiles **142 example modules**
that keiki never imports — including the TP proof examples, which are among the slowest
modules in the package. keiki imports only `Data.SBV`, so nothing we use is affected.

The cost is not hypothetical. At audit time `~/.cabal/store` held 50 distinct SBV builds
(6× 14.0, 17× 14.1, 4× 14.2, 4× 14.3, 12× 14.4, 7× 14.5), and
[Plan 7](../plans/7-upgrade-keiki-to-ghc-9-12.md) line 353 already records the SBV build
taking "several minutes."

The flag is `manual: True`, so cabal will not flip it on its own. It must be set
explicitly in `cabal.project`:

```
package sbv
  flags: -compile_examples
```

This was not done as part of the audit; it remains outstanding.


## Operational knob worth knowing: `SBV_COMM_TIMEOUT_FACTOR`

SBV 14.1 consolidated its internal solver-IPC timeouts behind an environment variable
that scales them (e.g. `2` to double). This is relevant because `src/Keiki/Symbolic.hs`
handles `Unknown` and `UnknownTimeOut` explicitly, and it is the cheapest lever if the
symbolic suite gets flaky on slower CI machines. `docs/guide/symbolic-ci.md` does not
currently mention it.


## Findings for Plan 83 (exact reconstructible projection domains)

[Plan 83](../plans/83-add-exact-reconstructible-symbolic-field-projection-domains.md) had
all five milestones open at audit time and is the next symbolic work item. Three of its
load-bearing premises were checked against SBV source and hold.

**The regex capability it needs already exists, and needs no version bump.**
`Data.SBV.RegExp` provides exactly the constructs the plan's text language enumerates:
literals, `Range`, concatenation, union, `Opt`, and — for bounded repetition — `Loop i j`
and `Power n`, together with full-string `match`. The plan's `TextPattern` smart
constructors map onto these one-for-one.

**The U+2FFFF rejection bound is correct against source, not folklore.** SBV sets
`maxBound :: SChar` to `chr 0x2FFFF` in `Data/SBV/Core/Model.hs:4045-4049`, with a comment
naming the SMT-LIB restriction as the reason. The plan's requirement that every smart
constructor reject code points above U+2FFFF — so the pure matcher and the SBV constraint
cannot denote different sets — rests on a real and verifiable limit.

**The `str.to_re` fix is already in effect and was never blocking.** SBV 14.4 changed
regex literal emission from the pre-standard `(str.to.re ...)` to SMT-LIB's
`(str.to_re ...)` in `Data/SBV/Core/Symbolic.hs:471` (upstream commit `1a5e65ca0`). Every
literal in a TypeID-shaped pattern — prefix, version and variant positions — goes through
that line, so it sits squarely on Plan 83's path. Two reasons it is not a concern:
keiki resolves 14.5, and z3 4.16.0 accepts *both* spellings (verified directly; see
below). It would only have mattered on an older SBV together with a solver that rejects
the legacy name. Worth remembering if keiki ever supports a solver other than the z3 it
currently pins in `src/Keiki/Symbolic.hs`.


## Findings for Plan 60 (first-class collection registers, design-gated)

[Plan 60](../plans/60-first-class-collection-registers-design-gated.md) is awaiting a
maintainer GO/NO-GO, and its deferred **Option A** (full symbolic collections) is costed
in the plan as "z3 array/finite-set theory, plus quantifiers for `PAll`/`PAny`." That
quantifier requirement is a large part of why Option A reads as expensive. Two source
facts should be folded in whenever the gate is reconsidered.

**Quantifiers may not be required at all.** `Data.SBV.List` exports `elem`, `notElem`,
`length`, `all`, `any`, `filter`, and `foldl`/`foldr` as first-class sequence operations.
Between them these cover `PMember`, `PNotMember`, `PSizeCmp`, `PAll`, and `PAny` directly.
If that holds up, Option A's cost estimate is too pessimistic.

**`SSet` cannot carry `PSizeCmp`, so "finite-set theory" points at the wrong carrier.**
`Data.SBV.Set` documents that a symbolic set is either finite or has a finite complement,
and that consequently you cannot compute its size, enumerate it, or convert it to a list.
`PSizeCmp` is therefore unimplementable over `SSet`. `SList` is the carrier if size
comparison is in scope.

Neither fact is a reason to reopen the gate now. Option B was chosen because the committed
consumer (keiro-runtime-jitsurei) does not exercise the symbolic story, and that reasoning
is untouched by this audit. The caveat on the first point: `all`/`any` over symbolic lists
route through SBV's lambda support, so solver performance deserves a spike before any
re-costing is relied upon.


## What is not relevant to keiki

keiki's SBV surface is deliberately narrow — `SymVal`, `literal`/`free`, `constrain`,
`ite`, `sat`/`prove`, `SatResult` constructors, `getModelValue`, and `OrdSymbolic`. No
reals, no rationals, no floats, no `Data.SBV.Dynamic`, no `smtFunction`, no TP, no
quasi-quoters. Nearly all recent SBV work lands outside that surface:

| Feature | Release | Applies? |
|---|---|---|
| `sRationalToSReal` / `sRealToSRational` | 14.5 | No — no `SReal`/`SRational` |
| `smtLib2Compliant` config field | 14.5 | No — integers and reals are never mixed |
| `sRealToSIntegerRM`, rounding-mode variants | 14.5 | No |
| `svDivide` fix in `Data.SBV.Dynamic` | 14.5 | No — `Data.SBV.Dynamic` is unused |
| `curry`/`uncurry` for symbolic tuples | 14.4 | No — `Data.SBV.Tuple` is unused |
| Adder examples (BitPrecise, TP) | 14.4 | No |
| Termination measures over bit-vectors | 14.3 | No — no `smtFunction` |
| Dropping `pi` as `SReal` | 14.3 | No |
| `(.**)` integer exponentiation | 14.6 (unreleased) | No |

Two changes in the window are absorbed harmlessly. The 14.5 **breaking** rename
`sRealToSInteger` → `sRealToSIntegerFloor` does not touch keiki, which uses no reals.
14.3's improved capture of solver error messages before process termination is a quiet
benefit to the `ProofError` path and needs no code change.

One deliberate non-finding: nothing in 14.x would let `predicateTranslationExact` or
`constrainFieldProjection` be exact where they are currently conservative. The capability
that would help is richer structural modeling of projections, and the 14.x work in that
area (the `sCase`/`pCase` quasi-quoters, `smtFunction` termination) targets the
theorem-proving surface, not the free-variable-plus-constraint style keiki uses. Plan 83's
own domain algebra is the route to exactness, not an SBV upgrade.


## Reproducing this audit

```sh
# Resolved version — read the build plan, not the store, which holds stale builds.
python3 -c "import json;print({x['pkg-version'] for x in json.load(open('dist-newstyle/cache/plan.json'))['install-plan'] if x['pkg-name']=='sbv'})"

# Latest release. The Mori corpus may hold an unreleased version; Hackage is authoritative.
curl -s https://hackage.haskell.org/package/sbv/preferred -H 'Accept: application/json'

# Corpus source and changelog.
mori registry show LeventErkok/sbv --full
```

The z3 spelling check that settled the `str.to_re` question:

```sh
printf '(set-logic QF_S)\n(declare-const s String)\n(assert (str.in_re s (str.to.re "ab")))\n(check-sat)\n' | z3 -in
printf '(set-logic QF_S)\n(declare-const s String)\n(assert (str.in_re s (str.to_re "ab")))\n(check-sat)\n' | z3 -in
```

Both returned `sat` on z3 4.16.0.
