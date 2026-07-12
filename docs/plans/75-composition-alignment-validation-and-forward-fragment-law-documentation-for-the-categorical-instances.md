---
id: 75
slug: composition-alignment-validation-and-forward-fragment-law-documentation-for-the-categorical-instances
title: "Composition alignment validation and forward-fragment law documentation for the categorical instances"
kind: exec-plan
created_at: 2026-07-12T04:16:45Z
master_plan: "docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md"
---

# Composition alignment validation and forward-fragment law documentation for the categorical instances

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

keiki's composition surface (`src/Keiki/Composition.hs`: `compose`, `alternative`,
`feedback1`; `src/Keiki/Profunctor.hs`: the `SomeSymTransducer` wrapper with its
`Profunctor` / `Category` / `Strong` / `Choice` / `Arrow` instances) currently contains
three silent-failure paths and one piece of false documentation, all surfaced by the
2026-07 architecture review:

1. `alternative`'s haddock claims the two arms of an `Either`-input composite can never
   both fire on one input. That claim is false for edges whose guard has no structural
   input-constructor test — most notably every edge authored with the builder's
   `onEpsilon`, whose guard seed is exactly `PTop`. Such an edge fires on inputs meant
   for the *other* arm, producing silent command rejection (two matched edges makes
   `delta` return `Nothing`) or, worse, a wrong-arm `error` crash.
2. The variance combinators `lmapCi` / `rmapCo` (and everything built on them: the
   `Profunctor` instance, `Strong`'s `firstSym`, `Arrow`'s `arr`) rewrite constructor
   behaviour while keeping the constructor *names* unchanged — and `compose` matches
   purely by name. Composing a mapped transducer therefore silently *skips the map*:
   `t2 . rmap g t1` never applies `g` to what `t2` sees.
3. There is no build-time check that the wire-constructor names one transducer emits
   line up with the input-constructor names the next transducer expects; a mismatch
   yields edges that never fire or a runtime `error` deep inside evaluation.
4. The categorical instances violate their laws at the inversion-observable level
   (`dimap id id` poisons round-trips; `arr f >>> arr g` is a dead composite), but this
   is documented only as scattered per-function caveats with no single statement of
   which laws hold at which observational level.

After this plan: `alternative` automatically arm-restricts guards so both-arms-fire is
impossible; composing a mapped ("poisoned") transducer fails loudly with a structured
diagnostic instead of silently mis-composing; a callable, conservative alignment
validator (`checkComposeAlignment`, plus a `composeChecked` entry point) reports every
emitted-name / expected-name / field-arity mismatch before a composite is used; and one
prominent module-level haddock section in `src/Keiki/Profunctor.hs` states precisely
which typeclass laws hold at the *forward* observational level (step semantics) versus
the *inversion/replay* level, with `ROADMAP.md` kept consistent. Each behaviour change
is demonstrated by a test that fails before the change and passes after.

Consumer risk is zero: the keiro survey recorded in
`docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md`
(Integration Point 6) found *no* downstream consumer of any composition operator or of
`SomeSymTransducer`, so this plan may change behaviour and signatures freely. The same
master plan's release-gate decision permits Phase 3 (this plan and EP-74) to ship in
`0.1.0.0` merely marked experimental in the module haddocks if schedule forces a cut —
Milestone 4 adds that marking regardless, so the fallback costs nothing extra.

Dependencies: this plan has a HARD dependency on
`docs/plans/74-fix-compose-update-snapshot-semantics-and-multi-event-chain-expansion-under-stateful-transducers.md`
(EP-74) — it finalizes `compose`'s update-snapshot and multi-event chain semantics, and
documenting or validating semantics that are about to change would be wasted work. Do
not start Milestones 3–5 until EP-74 is Complete; Milestones 1 and 2 touch
`alternative` and the wrapper only and may proceed in parallel with EP-74. There is a
SOFT dependency on
`docs/plans/69-replace-the-fabricated-weakenr-and-knownslotnames-dictionary-in-category-composition-with-real-induction-witnesses.md`
(EP-69), which replaces the wrapper's fabricated constraint dictionaries with real
induction witnesses and therefore reshapes the `SomeSymTransducer` representation: the
poison-provenance fields of Milestone 2 should be designed against the post-EP-69
representation when it exists, and against the current constructor otherwise (the
design below works for both).


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented
here, even if it requires splitting a partially completed task into two ("done" vs.
"remaining"). This section must always reflect the actual current state of the work.

- [ ] M1: failing test — `alternative` with a `PTop`-guarded (onEpsilon-style) t2 edge misfires on `Left` inputs
- [ ] M1: `anyLeftCtor` / `anyRightCtor` arm-tag `InCtor`s and `guardIsArmRestricted` scan added to `src/Keiki/Composition.hs`
- [ ] M1: `alternative` conjoins arm tags onto non-arm-restricted lifted guards; haddock's false mutual-exclusion claim rewritten
- [ ] M1: M1 tests green (`cabal test all`), including symbolic single-valuedness on the fixed composite
- [ ] M2: name stamping — `contraInCtor` / `contraMaybeInCtor` append `"#lmapped"`, `mapWireCtor` appends `"#rmapped"` in `src/Keiki/Profunctor.hs`
- [ ] M2: poison provenance carried on `SomeSymTransducer`; set by `Profunctor` / `Strong` / `Arrow` instances
- [ ] M2: `Cat..` raises `PoisonedCompositionError` when the boundary alphabet is poisoned; tests for both directions
- [ ] M3: `ComposeAlignmentWarning` type + `checkComposeAlignment` in `src/Keiki/Composition.hs`
- [ ] M3: `composeChecked` entry point; misaligned-names, arity-mismatch, and poisoned-name specs
- [ ] M4: module-level "Law status" haddock section in `src/Keiki/Profunctor.hs`; scattered caveats point at it
- [ ] M4: `ROADMAP.md` composition bullets updated; experimental marking added to both modules
- [ ] M5: forward-observational law tests (multi-step, stateful) added; full suite green; `nix fmt -- --no-cache` clean


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet. Authoring-time findings that shaped the design are recorded in the Decision
Log and in "Context and Orientation" below.)


## Decision Log

- Decision: fix the `alternative` arm-exclusion hole by *automatically* conjoining a
  structural arm-restriction predicate onto lifted guards that lack one, rather than
  rejecting or merely warning at `alternative` call time.
  Rationale: the module already learned this exact lesson for `identityTransducer`
  (`src/Keiki/Profunctor.hs:294-306`, EP-29 M1): a `PTop` guard was replaced by
  `PInCtor identityInCtor` precisely so `liftLPredAlt` / `liftRPredAlt` would make it
  arm-discriminating. Auto-lifting generalizes that fix to every user transducer and
  implements the author's evident intent (an `onEpsilon` edge means "fires on any input
  *for this transducer*", which under `alternative` means "for this arm"). Rejection
  would break every existing `onEpsilon` user of `alternative` with no migration
  besides hand-writing the same conjunct. Investigation confirmed the machinery
  permits a structural "input is `Left _`" guard without a payload match: `PInCtor`
  only ever consults `icMatch` on the forward path (`src/Keiki/Core.hs:828-830`), and
  guard-position `InCtor`s never reach `solveOutput` (which walks only the `OPack`'s
  `InCtor`, `src/Keiki/Core.hs` `solveOutput`), so a payload-free tag `InCtor` with a
  poisoned-but-unreachable `icBuild` is sound.
  Date: 2026-07-11

- Decision: conjoin the arm tag only when the lifted guard is not already
  arm-restricted (per the recursive `guardIsArmRestricted` rule in Milestone 1), never
  unconditionally.
  Rationale: the symbolic translator encodes `PInCtor ic` as
  `seInputCtor .== literal (icName ic)` over a *single* symbolic constructor tag
  (`src/Keiki/Symbolic.hs:494-512`). Conjoining a tag named `"keiki#altLeft"` onto a
  guard that already contains `PInCtor "SendEmail"` would make the edge symbolically
  unsatisfiable (one tag cannot equal two literals), silently blinding the symbolic
  single-valuedness and dead-edge gates. Conjoining only onto guards with no positive
  structural constructor test avoids that; the residual caveat (the tag itself is a
  non-partitioning constructor name, like `identityTransducer`'s `"Identity"`) is
  documented in the haddock and falls under EP-76's symbolic-caveats scope
  (`docs/plans/76-symbolic-soundness-solver-unknown-handling-encoding-gap-caveats-and-a-stronger-pure-overlap-check.md`).
  Date: 2026-07-11

- Decision: make wrapper poisoning visible with BOTH a name stamp (rename rewritten
  constructor names with `"#lmapped"` / `"#rmapped"` suffixes) AND wrapper-level
  provenance flags that make `Cat..` fail loudly; documentation alone is rejected.
  Rationale: `t2 . rmap g t1` is a silent-corruption path — `compose`'s substitution is
  purely name-based (`src/Keiki/Composition.hs:387-424`, `474-478`) while `mapWireCtor`
  keeps `wcName` unchanged (`src/Keiki/Profunctor.hs:834-840`), so t2's field reads
  wire to t1's raw pre-`g` terms. The name stamp guarantees the *primitive* `compose`
  can never silently match a poisoned name (mismatch substitutes guards to `PBot` — a
  dead edge, same failure shape as `arrTransducer`, and one the Milestone 3 validator
  reports with a dedicated constructor). The provenance flags upgrade dead-composite to
  loud-throw on the wrapper path, which is where `Profunctor`-produced values actually
  get composed. `"#"` is chosen as the marker character because it cannot occur in a
  Haskell constructor name, so no `Generic`-derived name can collide.
  Date: 2026-07-11

- Decision: a consequence of the poison throw — `Arrow`'s derived `***` / `&&&`
  (which route through `arr` and `>>>`) change from silently-dead composites to loud
  `PoisonedCompositionError` throws.
  Rationale: today `first' f >>> arr swap >>> ...` produces a composite that
  typechecks and never fires (the `"_first"` wire rename plus `arr`'s
  `"arr"`/`"Identity"` name mismatch, `src/Keiki/Profunctor.hs:616-627` and `725-738`).
  A loud error naming the poisoned side is strictly more diagnosable than an aggregate
  that ignores every command. Zero consumers exist; the law-status haddock (Milestone
  4) states this plainly.
  Date: 2026-07-11

- Decision: the alignment validator returns a NEW composition-specific warning type
  (`ComposeAlignmentWarning s1 s2` in `src/Keiki/Composition.hs`) rather than extending
  `TransducerValidationWarning` in `src/Keiki/Core.hs`; only the `EdgeRef` locator
  vocabulary (`src/Keiki/Core.hs:923-927`) is shared.
  Rationale: masterplan 16 Integration Point 1 assigns ownership of the
  `TransducerValidationWarning` constructor set to EP-71
  (`docs/plans/71-align-build-time-validation-with-replay-head-recoverability-cross-edge-inversion-ambiguity-and-guard-implies-input-read-checks.md`)
  because keiro pattern-matches that type exhaustively — every added constructor is a
  coordinated downstream break. Composition warnings also structurally need TWO vertex
  type parameters (a t1 locator and a t2 locator), which does not fit
  `TransducerValidationWarning s`. A separate type in a zero-consumer module costs
  nothing and requires no coordination. If EP-71 later wants to fold these in, that is
  its call to make.
  Date: 2026-07-11

- Decision: `compose` itself stays unchecked; the option-gated checked path is a new
  `composeChecked` (returns `Either [ComposeAlignmentWarning s1 s2] (SymTransducer …)`),
  and the wrapper's `Cat..` runs only the cheap poison-provenance check by default,
  not the full alignment scan.
  Rationale: `compose` is pure and total today; making it throw or changing its return
  type would ripple through `feedback1`, `Cat..`, and every render/spec call site for
  a check that is conservative (it can have false positives on exotic guard shapes).
  The full scan needs `Bounded`/`Enum` on both vertex types (to enumerate reachable
  pairs), which `compose` currently does not demand. An explicit `composeChecked` plus
  a callable `checkComposeAlignment` gives build-time callers (tests, CI gates) the
  strong check without taxing or destabilizing the primitive.
  Date: 2026-07-11

- Decision: (placeholder — record every further decision made while implementing.)
  Rationale: …
  Date: …


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

Work happens in the repository root (the directory containing `keiki.cabal`,
`flake.nix`, and `src/`). All commands below assume that working directory. Enter the
dev shell with `nix develop`; the toolchain is GHC 9.12. Build with `cabal build all`,
test with `cabal test all`, and format with `nix fmt -- --no-cache` before committing.

### The machine being composed

A `SymTransducer` (`src/Keiki/Core.hs`) is keiki's pure aggregate model: a finite set
of control vertices (an enum type `s`), a typed register file (`RegFile rs`, a
heterogeneous list of named slots), and per-vertex outgoing *edges*. An `Edge` carries
a `guard` (an `HsPred rs ci` predicate over registers and the incoming command of type
`ci`), an `update` (register writes), an `output` (a list of `OutTerm`s — zero for an
ε-edge, one for a letter edge, many for a multi-event edge), and a `target` vertex.
Stepping (`delta`/`omega`/`step`, `src/Keiki/Core.hs:866-918`) fires the *unique* edge
whose guard holds; if two guards hold, `delta` returns `Nothing` — the command is
silently rejected.

Two name-carrying records are the composition currency. An `InCtor ci ifs` names one
constructor of the command type `ci` and can match it (`icMatch :: ci -> Maybe (RegFile
ifs)`) and rebuild it (`icBuild :: RegFile ifs -> ci`); guards test constructors with
`PInCtor`, and terms read command fields with `TInpCtorField`. A `WireCtor co fs` names
one constructor of the event type `co` and can build it (`wcBuild`) and match it back
(`wcMatch`); every emitted event is an `OPack ic wc fields` pairing the input
constructor the edge consumed with the wire constructor it emits. `solveOutput`
inverts an `OPack` mechanically — that inversion (replay recovering the command from
the event) is the library's reason to exist.

Sequential composition (`compose`, `src/Keiki/Composition.hs:879-1065`) fuses `t1 ::
… ci1 mid` and `t2 :: … mid co` into one transducer by *substituting* t2's reads of the
mid alphabet against t1's emitted terms. The substitution is keyed on STRING NAME
EQUALITY: `substTerm` accepts a t2 field read only when `icName ic2 == wcName wc1`
(`src/Keiki/Composition.hs:387-424`; a name mismatch inside a term is a runtime
`error`, and an out-of-range field position is the `nthTerm` overflow `error` at
`src/Keiki/Composition.hs:401-412`), and `substPred` rewrites a t2 `PInCtor` to `PTop`
on a name match and `PBot` otherwise (`src/Keiki/Composition.hs:474-478`). Name-based
matching is thus the linchpin of the whole composition story, and nothing checks the
names line up until an edge silently never fires or evaluation crashes.

Disjoint-input dispatch (`alternative`, `src/Keiki/Composition.hs:1112-1198`) runs t1
and t2 side by side over `Either ci1 ci2`: each arm's edges are lifted so their
`InCtor`s match only the correct `Either` arm (`leftInCtor` / `rightInCtor`,
`src/Keiki/Composition.hs:549-569`). `feedback1`
(`src/Keiki/Composition.hs:1260-1275`) is `compose t (compose f t)` and inherits
whatever `compose` does.

The wrapper (`SomeSymTransducer`, `src/Keiki/Profunctor.hs:110-119`) existentially
hides `rs` and `s` so a transducer can participate in `Profunctor` / `Category` /
`Strong` / `Choice` / `Arrow`. `Cat..` delegates to `compose` after a runtime slot-name
overlap check that throws `CategoryOverlapError`
(`src/Keiki/Profunctor.hs:434-469`). EP-69 will replace this file's fabricated
constraint dictionaries (`unsafeCoerceWrapperDict` and friends,
`src/Keiki/Profunctor.hs:351-396`) with real induction witnesses, reshaping the
wrapper's packed evidence; Milestone 2's provenance fields ride whatever constructor
shape exists when this plan is implemented.

### Defect 1 — `alternative`'s false mutual-exclusion claim (medium-high)

The haddock at `src/Keiki/Composition.hs:1099-1106` asserts that t1-arm guards
"require `Left _` via `leftInCtor`" and that therefore "**No cross-transducer
mutual-exclusion check is needed**". That is true only when every guard actually
carries a `PInCtor` conjunct for the lifters to wrap. The lifters are purely
structural: `liftRPredAlt PTop = PTop` (`src/Keiki/Composition.hs:659`; symmetrically
`liftLPredAlt PTop = PTop` at line 632) — there is nothing to wrap, so the lifted
guard still fires on *any* input, including the other arm's. The builder's `onEpsilon`
seeds its guard with exactly `PTop` (`peGuard = PTop`, `src/Keiki/Builder.hs:689-706`),
so every ε-edge authored with the DSL has this shape; so does any guard built only
from register predicates (`PEq`/`PCmp` over `TReg` reads).

Concretely, take `alternative t1 t2` where t2 has a `PTop`-guarded ε-edge. Feed the
composite a `Left c1` that also satisfies a t1 edge: `delta` sees two matched edges
(t1's correct one and t2's wrong-arm ε-edge) and returns `Nothing` — a valid command
is silently rejected. If instead the wrong-arm edge is the *only* match, the composite
advances the wrong arm's vertex. Worst case: a wrong-arm guard that reads input fields
without a leading `PInCtor` (e.g. `PEq (TInpCtorField …) …` alone) evaluates
`TInpCtorField` against the other arm's payload and hits the `evalTerm` guard-violation
`error` at `src/Keiki/Core.hs:792-794` — a crash from safe-looking code. The module
already knows this failure mode: `identityTransducer` was switched from `PTop` to
`PInCtor identityInCtor` for exactly this reason (`src/Keiki/Profunctor.hs:294-306`),
but the lesson was never surfaced as a user-facing precondition or fixed in
`alternative` itself.

### Defect 2 — poisoned-wrapper composition is silent (medium-high)

`lmapCi` rewrites every `InCtor` so `icMatch` pre-composes with `f`, poisoning
`icBuild` (`contraInCtor`, `src/Keiki/Profunctor.hs:803-809`; the poison error at
`822-831`); `rmapCo` rewrites every `WireCtor` so `wcBuild` post-composes with `g`,
setting `wcMatch` to `const Nothing` (`mapWireCtor`, `src/Keiki/Profunctor.hs:834-840`).
Both keep the NAMES (`icName`, `wcName`) unchanged. Since `compose` substitutes purely
by name, `t2 . rmap g t1` composes as if `g` did not exist: t2's `TInpCtorField` reads
substitute against t1's *raw* output terms (names still match), so what t2 "sees" in
the composite is the un-mapped value — `g` is applied only on the final wire via
`wcBuild`, *after* t2's guards and reads already routed on the raw terms. If `g`
remaps constructors (e.g. swaps two event constructors), the wrong t2 edge fires and
the composite is silently wrong, not merely lossy. The current haddocks document only
the `solveOutput` loss, not this forward-semantics corruption. `arrTransducer`
accidentally demonstrates the safe failure shape: its wire is *renamed* (`"arr"`), so
`arr f >>> arr g` merely goes dead (`PBot` guards) rather than mis-routing —
documented at `src/Keiki/Profunctor.hs:725-738`.

### Defect 3 — no alignment validation (the linchpin is unchecked)

Nothing verifies, at build time, that the `wcName`s t1 emits are the `icName`s t2
expects, nor that when names match the field *positions* t2 reads exist in t1's
`OutFields`. A typo'd constructor name yields a composite full of `PBot` edges (never
fires — silent), and a structural mismatch with matching names hits the `nthTerm`
overflow `error` at `src/Keiki/Composition.hs:401-412` only when the edge is evaluated.
The fix is a conservative structural scan, callable standalone and via a checked
compose entry point, returning structured warnings that reuse the `EdgeRef` locator
vocabulary from `src/Keiki/Core.hs:923-927`.

### Defect 4 — law status is scattered and partly wrong-level (medium-low)

The instances satisfy their laws only at the *forward* observational level — equality
of `delta`/`omega`/`step` behaviour — and violate them at the inversion-observable
level, and in two cases even forward: `dimap id id t` is not observationally `t`
(icBuild/wcMatch are poisoned even though forward steps agree; instance at
`src/Keiki/Profunctor.hs:223-235`); `arr id` is not `Cat.id` (it materializes a real
transducer, asserted in `test/Keiki/ArrowSpec.hs:43-57`); `arr f >>> arr g` is a dead
composite (`src/Keiki/Profunctor.hs:725-738`); `first' f >>> first' g` is dead because
`firstSym` renames the wire with a `"_first"` suffix (`src/Keiki/Profunctor.hs:616-627`)
that the downstream `first'`'s reads do not expect. These facts live in per-function
caveats with no single authoritative statement, and `ROADMAP.md`'s composition section
(lines 66-95, plus the "Law-faithful `Arrow` fusion" bullet at lines 177-182) must stay
consistent with whatever the module-level section ends up saying — including the
Milestone 2 change that dead composites become loud errors.

### Existing tests (verified 2026-07-11)

`test/Keiki/ProfunctorSpec.hs`, `test/Keiki/ChoiceSpec.hs`, `test/Keiki/StrongSpec.hs`,
and `test/Keiki/ArrowSpec.hs` are routing-only: every assertion fires a single command
from the initial state (`fireFromInitial` / one `omega` call) and checks the emitted
event or the poisoned-inversion contract. `test/Keiki/CategorySpec.hs` checks the laws
"behaviourally, up to state-isomorphism" — also on one representative input. No spec
drives a composed or mapped transducer through a multi-step, register-mutating script,
so a law violation that only manifests after state evolves would be invisible today.
Milestone 5 adds exactly those tests. Fixtures to reuse: `Keiki.Fixtures.EmailDelivery`
(used by the wrapper specs), the `Ping`/`Pong` arm fixture in
`test/Keiki/CompositionAlternativeSpec.hs`, and the stateful composition fixtures EP-74
adds under `test/Keiki/Fixtures/` (masterplan 16, Integration Point 4) — do not invent
parallel stateful fixtures.


## Plan of Work

The work is five milestones. Milestones 1 and 2 are independent of EP-74 and of each
other; Milestone 3 needs EP-74's final `compose` semantics (and Milestone 2's name
markers, which it must recognize); Milestone 4 documents the state of the world after
1–3; Milestone 5 certifies everything with the multi-step law tests.

### Milestone 1 — arm-restrict `alternative` (fixes Defect 1)

Scope: `src/Keiki/Composition.hs` and a new spec section in
`test/Keiki/CompositionAlternativeSpec.hs`. At the end of this milestone, an
`alternative` composite can never fire a t1 edge on a `Right` input or a t2 edge on a
`Left` input, regardless of how the arms' guards were authored, and the haddock no
longer overclaims.

First write the failing test. In `test/Keiki/CompositionAlternativeSpec.hs`, build a
right-arm transducer with a `PTop`-guarded edge — author it through
`Keiki.Builder.onEpsilon` so the test pins the real DSL path (guard seed `PTop`,
`src/Keiki/Builder.hs:689-706`), with a register-only guard conjunct such as
`requireGuard` on a `PEq` over `TReg` so the edge is realistic. Form
`alternative emailDelivery thatTransducer` (or reuse the spec's existing Ping fixture
as the left arm) and `step` the composite with a `Left` command that matches a left-arm
edge. Before the fix this must fail: `delta` returns `Nothing` because both the left
edge and the wrong-arm ε-edge match. Assert the *correct* behaviour (left arm
advances, right sub-vertex unchanged) so the test is red now and green after.

Then implement. Add to `src/Keiki/Composition.hs`, near the existing lifters:

- `anyLeftCtor :: InCtor (Either ci1 ci2) '[]` and
  `anyRightCtor :: InCtor (Either ci1 ci2) '[]` — payload-free arm tags. `icName` is
  `"keiki#altLeft"` / `"keiki#altRight"` (the `"#"` guarantees no collision with a
  `Generic`-derived constructor name; the two names must differ from each other so the
  structural determinism check, which compares `PInCtor` names at
  `src/Keiki/Core.hs:1805`, does not conflate a left ε-edge with a right one).
  `icMatch` inspects only the `Either` constructor (`Left _ -> Just RNil`,
  `Right _ -> Nothing`, and symmetrically); `icBuild :: RegFile '[] -> Either ci1 ci2`
  cannot produce a value and is poisoned with an `error` naming the tag and stating it
  is guard-only — it is unreachable in practice because the tag never appears inside
  an `OPack`, and `solveOutput` only invokes the `OPack`'s own `InCtor`.
- `guardIsArmRestricted :: HsPred rs ci -> Bool` — the conservative structural scan:
  `PInCtor _` is `True`; `PAnd p q` is `guardIsArmRestricted p || guardIsArmRestricted q`
  (one restricting conjunct restricts the whole conjunction); `POr p q` is
  `… p && … q` (a disjunction restricts only if every disjunct does); everything else
  (`PTop`, `PBot`, `PEq`, `PCmp`, `PNot _`) is `False`. The direction of conservatism
  matters and is asymmetric: wrongly answering `False` merely adds a redundant tag
  conjunct (semantically a no-op — the guard already implied the arm — but it would
  make the edge symbolically unsatisfiable, per the Decision Log's second entry), while
  wrongly answering `True` leaves the arm hole open. The rule above never answers
  `True` unless a positive `PInCtor` genuinely gates every path through the guard, and
  never conjoins on a guard that already has one, so neither bad case occurs.
- In `alternative`'s `liftEdgeL` (`src/Keiki/Composition.hs:1146-1171`): after
  building the lifted guard, if `guardIsArmRestricted` on the *original* `guard e1` is
  `False`, replace the lifted guard with
  `PAnd liftedGuard (PInCtor anyLeftCtor)`. Symmetrically `liftEdgeR` conjoins
  `PInCtor anyRightCtor`.

Rewrite the haddock bullet at `src/Keiki/Composition.hs:1099-1106`: the
mutual-exclusion property now HOLDS BY CONSTRUCTION — either the author's own
`PInCtor` conjunct becomes arm-restricted through the lifters, or `alternative`
conjoins the arm tag. Document the symbolic caveat: the tag names participate in the
single-tag symbolic encoding of `PInCtor` (`src/Keiki/Symbolic.hs:494-512`), so, like
`identityTransducer`'s `"Identity"`, they are non-partitioning constructor names; the
composite's symbolic single-valuedness check treats a tagged ε-edge as disjoint from
same-arm named edges, which is sound whenever each arm passed its own single-valuedness
check standalone (cross-reference EP-76 for the symbolic caveat inventory). State this
in the haddock in those words.

Acceptance: the new spec is green; every pre-existing test in
`test/Keiki/CompositionAlternativeSpec.hs`, `test/Keiki/ChoiceSpec.hs` (whose `left'` /
`right'` are built on `alternative`), and the Mermaid render specs still passes; and a
new assertion shows `isSingleValuedSym` still holds on an `alternative` composite
containing a tagged edge.

### Milestone 2 — make wrapper poisoning visible (fixes Defect 2)

Scope: `src/Keiki/Profunctor.hs`, spec additions in `test/Keiki/ProfunctorSpec.hs` and
`test/Keiki/CategorySpec.hs`. At the end, composing through a mapped alphabet either
throws a structured error (wrapper path) or produces provably-dead-and-flagged edges
(concrete path), never a silently mis-routed composite.

Name stamping: change `contraInCtor` and `contraMaybeInCtor`
(`src/Keiki/Profunctor.hs:803-820`) to set `icName = n <> "#lmapped"`, and
`mapWireCtor` (`:834-840`) to set `wcName = n <> "#rmapped"`. This is behaviour-neutral
for standalone forward processing (names are consulted only by `compose`'s
substitution, the hidden-input grouping — which renames uniformly within one
transducer — the symbolic literal encoding — likewise uniform — and diagnostics/
renderers), but it makes name-based substitution *incapable* of silently matching a
poisoned constructor against its raw ancestor: the mismatch substitutes t2 guards to
`PBot`, the same visible-dead shape as `arrTransducer`. Check the Mermaid specs under
`test/Keiki/Render/` for snapshot text containing rewritten names and update
expectations if any fixture there passes through `lmapCi`/`rmapCo` (none is expected
to; verify rather than assume).

Provenance: extend the `SomeSymTransducer` constructor
(`src/Keiki/Profunctor.hs:110-119`; or the post-EP-69 witness record if EP-69 has
landed — the fields are representation-agnostic) with two strict `Bool` fields, input-
side and output-side poison (a small record `PoisonProvenance { poisonedInput ::
!Bool, poisonedOutput :: !Bool }` reads better than bare Bools; choose and record).
`someSymTransducer` sets both `False`. The instances set them: `lmap`/`lmapMaybeCi`
paths set input-side; `rmap` sets output-side; `dimap` sets both; `first'`/`second'`
set both (the paired `InCtor` is poisoned and the wire is renamed/unmatchable);
`Arr.arr` sets output-side (its wire is `"arr"`-named with `wcMatch = const Nothing`)
and input-side stays honest `False` (its `identityInCtor` still round-trips). The
sentinel `SomeSymIdentity` is never poisoned.

Loud failure: add `data PoisonedCompositionError = PoisonedCompositionError
{ pceSide :: String, pceDetail :: String }` (an `Exception`, alongside
`CategoryOverlapError` at `src/Keiki/Profunctor.hs:341-346`). In `composeWrappers`
(reached from `Cat..`, `src/Keiki/Profunctor.hs:439-469`): before the overlap check,
if t1 (the upstream) is output-side poisoned or t2 (the downstream) is input-side
poisoned, throw it, with a message naming which operand and which map caused it and
pointing at the law-status haddock section. Only the *boundary* alphabet matters: a
`lmap` on t1's input or an `rmap` on t2's output composes fine and must NOT throw —
but the resulting composite must *carry forward* those outer flags so a later
composition still sees them.

Tests: `t2 . rmap g t1` (via `Cat..` on wrapped `EmailDelivery`-based fixtures) throws
`PoisonedCompositionError`; `rmap g (t2 . t1)` does not throw and applies `g` (the
correct spelling users should migrate to — assert its forward output); `lmap f t2 .
t1` throws; outer maps compose fine and their flags persist through one more `Cat..`.
On the concrete path, assert that composing a stamped transducer with `compose`
directly yields edges whose guards are dead (fire a command; no edge matches) —
pending Milestone 3, which upgrades this to a structured warning.

Acceptance: new specs green; `test/Keiki/ArrowSpec.hs` updated where `***`/`&&&`-style
compositions would now throw (the current spec only composes with the sentinel, which
must keep working unchanged); full suite green.

### Milestone 3 — the alignment validator (fixes Defect 3; requires EP-74 complete)

Scope: `src/Keiki/Composition.hs` exports, a new spec file
`test/Keiki/CompositionAlignmentSpec.hs` registered in `test/Spec.hs` the same way the
sibling specs are. At the end, a caller can ask, before ever stepping a composite,
"does every name t1 emits meet a consumer in t2, and vice versa?"

Add the warning type, reusing `EdgeRef` (`src/Keiki/Core.hs:923-927`):

```haskell
-- src/Keiki/Composition.hs
data ComposeAlignmentWarning s1 s2
  = UnconsumedWireOutput
      { cawT1Edge :: EdgeRef s1,
        cawWireName :: String,
        cawT2Vertex :: s2
      }
  | UnmatchedInCtorExpectation
      { cawT2Edge :: EdgeRef s2,
        cawInCtorName :: String,
        cawT1Vertex :: s1
      }
  | FieldArityMismatch
      { cawT1EdgeA :: EdgeRef s1,
        cawT2EdgeA :: EdgeRef s2,
        cawSharedName :: String,
        cawReadPosition :: Int,
        cawAvailableFields :: Int
      }
  | PoisonedNameInComposition
      { cawName :: String,
        cawSide :: String
      }
  deriving stock (Eq, Show)
```

and the checker plus checked entry point:

```haskell
checkComposeAlignment ::
  (Bounded s1, Enum s1, Ord s1, Bounded s2, Enum s2, Ord s2) =>
  SymTransducer (HsPred rs1 ci1) rs1 s1 ci1 mid ->
  SymTransducer (HsPred rs2 mid) rs2 s2 mid co ->
  [ComposeAlignmentWarning s1 s2]

composeChecked ::
  ( WeakenR rs1, Disjoint (Names rs1) (Names rs2),
    Bounded s1, Enum s1, Ord s1, Bounded s2, Enum s2, Ord s2
  ) =>
  SymTransducer (HsPred rs1 ci1) rs1 s1 ci1 mid ->
  SymTransducer (HsPred rs2 mid) rs2 s2 mid co ->
  Either
    [ComposeAlignmentWarning s1 s2]
    (SymTransducer (HsPred (Append rs1 rs2) ci1) (Append rs1 rs2) (Composite s1 s2) ci1 co)
```

The scan is structural and conservative, and works on the two component transducers
(no composite construction needed). Helpers: `edgeEmittedWireNames` (the `wcName` of
every `OPack` in a t1 edge's `output`) and `edgeExpectedInCtorNames` (every `icName`
appearing in a t2 edge's guard `PInCtor` atoms and in `TInpCtorField` reads across its
guard, update, and outputs — a fold over the closed `HsPred`/`Update`/`Term`/`OutFields`
ASTs, in the style of `Keiki.Core.termReadsInput` at `src/Keiki/Core.hs:1455-1461`).
Compute the reachable set of composite vertex pairs by breadth-first search from
`(initial t1, initial t2)` following, per EP-74's finalized semantics, the pair
transitions `compose` itself would build (ε-edges advance s1 alone; single-output
edges advance both; multi-event edges advance s2 through each mid symbol in order —
mirror `compose`'s own `composeEdge` structure at `src/Keiki/Composition.hs:923-932`
so the validator and the constructor cannot drift; if EP-74 changed that structure,
follow the code as it stands, not this paragraph). For each reachable pair `(v1, v2)`:
every wire name `w` emitted by a t1 edge out of `v1` must be consumed by at least one
t2 edge out of `v2` — "consumed" meaning the t2 edge's expected-name set contains `w`,
or the t2 edge's guard has no `PInCtor` at all (it fires regardless of the mid
constructor; post-Milestone-1 note: within `compose` there is no arm tagging, so plain
`PTop`-guarded t2 edges do consume everything) — otherwise emit `UnconsumedWireOutput`.
Symmetrically, a t2 edge whose expected-name set is non-empty but intersects no wire
name emitted by any t1 edge out of `v1` gets `UnmatchedInCtorExpectation`. When names
DO match, verify arity: for each t2 `TInpCtorField` read at position `n` against name
`w`, and each t1 `OPack` emitting `w` with an `OutFields` chain of length `m`, emit
`FieldArityMismatch` when `n >= m` — this surfaces the `nthTerm` overflow `error`
(`src/Keiki/Composition.hs:401-412`) at validation time instead of evaluation time.
Finally, any name on either side carrying a Milestone 2 marker (`"#lmapped"` /
`"#rmapped"`) or the `"_first"` suffix (`src/Keiki/Profunctor.hs:621-627`) yields
`PoisonedNameInComposition`. Names are compared with plain `==`; keep the check purely
syntactic — no solver, no evaluation.

`composeChecked` runs the scan and returns `Left` on any warning, `Right (compose t1
t2)` otherwise. Do not change `compose` (Decision Log). Export the new names from the
module header's export list with haddocks stating the conservatism contract: no false
"all clear" is promised (exotic guards can hide expectations behind `PNot`), but every
warning is a real structural fact about the two machines.

Tests (`test/Keiki/CompositionAlignmentSpec.hs`): an aligned pair (reuse the
`compose` fixtures from `test/Keiki/CompositionSpec.hs`) returns `[]` and
`composeChecked` returns `Right`; a deliberately misnamed t2 (clone a fixture `InCtor`
with a typo'd name) yields both `UnconsumedWireOutput` and
`UnmatchedInCtorExpectation` with the exact `EdgeRef`s asserted; an arity mismatch
(t2 reads field 2 of a 1-field wire) yields `FieldArityMismatch`; `rmapCo`-stamped t1
yields `PoisonedNameInComposition`; and a multi-event t1 edge (reuse EP-74's stateful
multi-event fixture) is scanned through the chain, not just its first symbol.

Acceptance: new spec green; `cabal test all` green; running `checkComposeAlignment` on
every existing in-tree composed fixture pair returns `[]` (add that as one blanket
assertion — it certifies the validator has no false positives on known-good inputs).

### Milestone 4 — the law-status section and ROADMAP consistency (fixes Defect 4)

Scope: haddock in `src/Keiki/Profunctor.hs`, edits to `ROADMAP.md`. Purely
documentation, but with a precise contract: ONE prominent module-level section is the
authority, and every scattered caveat defers to it.

Write a new module haddock section in `src/Keiki/Profunctor.hs` (in the module header
comment, under a heading like `== Law status: which laws hold at which observational
level`). Define the two observational levels in plain language: *forward* equivalence
(two transducers are equivalent when `delta`/`omega`/`step` agree on every command
sequence — states compared up to the documented state-isomorphism, as
`test/Keiki/CategorySpec.hs` already phrases it) and *inversion* equivalence (forward
equivalence PLUS `solveOutput` round-trips agree). Then state, exhaustively:

- `Profunctor`: `dimap id id = id` and the composition law hold at the forward level
  only; at the inversion level they fail because the rewrites poison `icBuild` /
  `wcMatch` (`src/Keiki/Profunctor.hs:223-235`, `803-840`) — "the forward fragment of
  the Profunctor laws", hence this plan's title.
- `Functor`: same status as `rmap`.
- `Category`: identity laws hold definitionally (sentinel short-circuit,
  `src/Keiki/Profunctor.hs:434-441`); associativity holds at the forward level;
  composition throws `CategoryOverlapError` on slot collision and (after Milestone 2)
  `PoisonedCompositionError` on a poisoned boundary.
- `Choice`: holds at BOTH levels — `left'`/`right'` are built on `alternative`, whose
  arm lifters preserve round-trip; after Milestone 1 the arm exclusion is by
  construction. This is the only instance with no inversion loss.
- `Strong`: forward level only, standalone; `first' f >>> first' g` and any further
  composition through a `"_first"`-renamed wire throws at the wrapper boundary
  (Milestone 2) rather than composing.
- `Arrow`: `arr` is a standalone adapter — forward level only, no inversion, and
  `arr f >>> arr g ≠ arr (g . f)`: it throws after Milestone 2 (previously a silently
  dead composite). The derived `***`/`&&&` therefore also throw. This is by design:
  admitting arbitrary function application into the symbolic `Term` AST would make
  guards untranslatable to SBV (see `Keiki.Symbolic.translateTermSym`), destroying the
  build-time guarantees keiki exists for.

Shrink each per-function caveat (`lmapCi`, `rmapCo`, `dimapTransducer`, `lmapMaybeCi`,
`firstSym`, `arrTransducer`, the instance haddocks) to one line pointing at the
section; keep the mechanism notes (what exactly is poisoned) with the mechanisms. Add
the experimental marking to the module headers of BOTH `src/Keiki/Profunctor.hs` and
`src/Keiki/Composition.hs` — a short "Stability: experimental" note stating the
composition surface may change without a major-version bump until it has real
consumers — which is also masterplan 16's sanctioned fallback if this plan cannot fully
land before `0.1.0.0`.

Update `ROADMAP.md`: the `Category`/`Choice`/`Strong`/`Arrow` bullets (lines 76-95)
must state the forward-fragment framing and the new loud-failure behaviour (overlap
error AND poisoned-composition error; `first'` chains and `arr` fusion throw rather
than go dead); the "Law-faithful `Arrow` fusion" deferred bullet (lines 177-182) stays
but should mention the new error; add one line for the alignment validator and the
`alternative` arm-restriction fix under "Composition & the typeclass tower". Keep the
`_Last updated:_` line current.

Acceptance: `cabal haddock keiki` (inside `nix develop`) builds without new warnings;
a reviewer can answer "does law X hold?" from exactly one place; `grep -n "first'"
ROADMAP.md` shows the updated framing.

### Milestone 5 — forward-observational law tests, multi-step and stateful (Defect 5)

Scope: test-only. The existing wrapper specs are routing-only (verified above); this
milestone adds law tests that drive *state evolution*, so regressions in guard/update
rewriting — the parts a single-command test cannot see — get caught.

Add a shared helper (in a small `test/Keiki/LawHelpers.hs` or at the top of the
touched specs — prefer the shared module if used from more than one spec): `runScript
:: SymTransducer (HsPred rs ci) rs s ci co -> [ci] -> [(s, [co])]`, a left fold of
`Keiki.Core.step` from `(initial t, initialRegs t)` collecting the vertex and emitted
events after each command (a rejected command records the unchanged vertex and `[]`).
Forward equivalence of two transducers over a script means their `runScript` traces
agree pointwise on outputs and on vertex traces up to the fixture's known isomorphism
(where vertex types differ, compare outputs and `isFinal` flags instead).

Then the law tests, each over a script of at least four commands against a stateful
fixture (EP-74's stateful composition fixtures under `test/Keiki/Fixtures/`, falling
back to `Keiki.Fixtures.EmailDelivery`/the OrderCart fixture if this milestone starts
first): in `test/Keiki/ProfunctorSpec.hs`, `dimap id id t` forward-equals `t`, and
`dimap (f' . f) (g . g') t` forward-equals `dimap f g (dimap f' g' t)`, on multi-step
scripts (wrap/unwrap newtypes as `WrappedCmd`/`WrappedEvent` already do); in
`test/Keiki/CategorySpec.hs`, associativity `(t3 . t2) . t1` vs `t3 . (t2 . t1)` on a
multi-step script through STATEFUL components (this leans on EP-69's witness fix — if
EP-69 has not landed, mark the nested-stateful case pending with a reference to
`docs/plans/69-…`, and keep a stateless-middle variant green); in
`test/Keiki/ChoiceSpec.hs`, an interleaved `[Left …, Right …, Left …, Right …]` script
through `left'`-then-`right'` composites asserting the two sub-states evolve
independently (this doubles as the multi-step regression test for Milestone 1); in
`test/Keiki/StrongSpec.hs`, `first' t` over a multi-step script asserting the threaded
`c` value is returned untouched at every step while `t`'s registers evolve. Also add
the diagnostic specs any earlier milestone deferred, so the plan's five deliverables
each have a named failing-before/passing-after test.

Acceptance: `cabal test all` green; deliberately re-introducing any one defect (e.g.
reverting Milestone 1's conjunction locally) makes at least one new test fail —
spot-check this once for each milestone's flagship test and note the result in
Surprises & Discoveries.


## Concrete Steps

All commands run at the repository root. Enter the environment once per shell:

```bash
nix develop
```

Iterate per milestone in the order test-first, implement, verify:

```bash
cabal build all
cabal test all
```

To run only the specs this plan touches while iterating (hspec pattern matching):

```bash
cabal test keiki-test --test-options='--match "alternative"'
cabal test keiki-test --test-options='--match "Alignment"'
cabal test keiki-test --test-options='--match "Poisoned"'
```

Expected shape of a healthy full run (counts will differ; zero failures is the
criterion):

```text
Finished in 12.34 seconds
287 examples, 0 failures
```

For Milestone 4's haddock check:

```bash
cabal haddock keiki
```

Before every commit:

```bash
nix fmt -- --no-cache
git add -A && git commit
```

Use conventional-commit messages, one commit per milestone at minimum, e.g.:

```text
fix(composition): arm-restrict alternative guards lacking a PInCtor conjunct
feat(profunctor): stamp poisoned ctor names and fail Cat. composition loudly
feat(composition): ComposeAlignmentWarning, checkComposeAlignment, composeChecked
docs(profunctor): single law-status section; ROADMAP forward-fragment framing
test(composition): multi-step stateful forward-law and diagnostic specs
```

Update the Progress checklist and (when anything unexpected appears) Surprises &
Discoveries at every stopping point.


## Validation and Acceptance

The plan is complete when all of the following observable behaviours hold, in a fresh
checkout, inside `nix develop`, with `cabal test all` green:

1. Arm exclusion. The Milestone 1 spec constructs `alternative` with an
   `onEpsilon`-authored right arm and steps a `Left` command: the left arm advances
   and the right sub-vertex is unchanged. Reverting the `alternative` conjunction makes
   this spec fail with `delta` returning `Nothing` (two matched edges).
2. Loud poisoning. `(t2 . rmap g t1)` on wrapped fixtures throws
   `PoisonedCompositionError` whose message names the offending side; the corrected
   spelling `rmap g (t2 . t1)` steps normally and its outputs show `g` applied.
3. Alignment validation. `checkComposeAlignment` returns `[]` on every in-tree aligned
   fixture pair, and returns the exact expected warnings (asserted by `EdgeRef` and
   name) on the misnamed, arity-mismatched, and stamped-name specs; `composeChecked`
   returns `Left` precisely when the scan warns.
4. Law documentation. `src/Keiki/Profunctor.hs` has one module-level law-status
   section; each instance/combinator caveat refers to it; both composition modules are
   marked experimental; `ROADMAP.md`'s composition bullets agree with the section
   (including the new throw behaviour) and the roadmap's last-updated line is current.
5. Multi-step laws. The Milestone 5 specs drive scripts of ≥4 commands through mapped
   and composed transducers with evolving registers, and each of the five defect areas
   has at least one test that fails when its fix is reverted.

Beyond compilation, the demonstrable user-visible win: a developer who composes two
transducers whose event names drift apart (a rename on one side) now gets a
`ComposeAlignmentWarning` naming the edge and the string, instead of an aggregate that
type-checks and ignores commands forever.


## Idempotence and Recovery

Every step is additive or a pure text edit in a git worktree; re-running builds, tests,
and the formatter is always safe. If a milestone lands partially, the tree still
compiles at each described boundary (each milestone compiles standalone; within a
milestone, commit only at green). To back out a milestone, `git revert` its commit(s) —
no generated artifacts, migrations, or persisted formats are involved (composition has
zero downstream consumers and nothing here touches wire formats). If Milestone 2's name
stamping unexpectedly breaks a render/golden expectation, fix the expectation, not the
stamp — the stamp is the safety property. If EP-74 turns out to still be in flight when
Milestone 3 starts, stop and wait: the validator's reachable-pair walk must mirror
`compose`'s final structure, and writing it against pre-EP-74 semantics is the one
known way to waste this plan's work.


## Interfaces and Dependencies

Libraries: only what the package already depends on — `base`, `profunctors` (instances
in `src/Keiki/Profunctor.hs`), `nothunks`, `hspec` for tests. No new dependencies.

Modules and the surface at end state:

- `src/Keiki/Composition.hs` exports, in addition to today's list: `anyLeftCtor`,
  `anyRightCtor` (arm-tag `InCtor`s, guard-only), `guardIsArmRestricted`,
  `ComposeAlignmentWarning (..)`, `checkComposeAlignment`, `composeChecked` — with the
  signatures given in Milestone 3. `compose`, `alternative`, `feedback1` keep their
  types; `alternative`'s behaviour changes as specified (arm tags), `compose`'s does
  not change in this plan (EP-74 owns its semantics).
- `src/Keiki/Profunctor.hs`: `SomeSymTransducer` gains poison-provenance fields (exact
  shape decided at implementation time against the post-EP-69 representation; record
  the choice in the Decision Log); new export `PoisonedCompositionError (..)`;
  `contraInCtor`/`contraMaybeInCtor`/`mapWireCtor` stamp names as specified; all
  instance types unchanged.
- `src/Keiki/Core.hs`: unchanged. The validator *reuses* `EdgeRef`
  (`src/Keiki/Core.hs:923-927`) and deliberately does NOT extend
  `TransducerValidationWarning` (EP-71 owns that constructor set; see the Decision
  Log). If EP-71 later wants a unified umbrella, `ComposeAlignmentWarning` is `Eq`/
  `Show` and trivially embeddable.
- Tests: `test/Keiki/CompositionAlignmentSpec.hs` (new, registered in `test/Spec.hs`),
  additions to `test/Keiki/CompositionAlternativeSpec.hs`,
  `test/Keiki/ProfunctorSpec.hs`, `test/Keiki/CategorySpec.hs`,
  `test/Keiki/ChoiceSpec.hs`, `test/Keiki/StrongSpec.hs`,
  `test/Keiki/ArrowSpec.hs`; stateful fixtures reused from EP-74/EP-71 under
  `test/Keiki/Fixtures/` per masterplan 16 Integration Point 4.
- Plans this one leans on, by path:
  `docs/plans/74-fix-compose-update-snapshot-semantics-and-multi-event-chain-expansion-under-stateful-transducers.md`
  (hard dependency — final `compose` semantics),
  `docs/plans/69-replace-the-fabricated-weakenr-and-knownslotnames-dictionary-in-category-composition-with-real-induction-witnesses.md`
  (soft — wrapper representation),
  `docs/plans/71-align-build-time-validation-with-replay-head-recoverability-cross-edge-inversion-ambiguity-and-guard-implies-input-read-checks.md`
  (coordination — warning-type ownership),
  `docs/plans/76-symbolic-soundness-solver-unknown-handling-encoding-gap-caveats-and-a-stronger-pure-overlap-check.md`
  (cross-reference — symbolic caveat for arm tags), all under
  `docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md`.

---

Revision note (2026-07-11): initial authoring — replaced the generated skeleton with
the full plan. All defect claims were re-verified against the working tree at
authoring time (file:line citations throughout refer to that state); the four
sibling plans referenced above were skeletons at authoring time, so their scope is
restated here from masterplan 16 rather than incorporated by reference.
