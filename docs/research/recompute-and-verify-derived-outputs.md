# Recompute-and-verify derived event outputs (EP-47 M1)

This note formalizes **recompute-and-verify**, the strategy by which `solveOutput`
(`src/Keiki/Core.hs`) could admit an event that stores a *derived* output field while
preserving keiki's foundational guarantee that the event uniquely determines the command,
certified at build time. It is the design-and-analysis deliverable of EP-47's M1
**ratification gate**: it ends with a written go/no-go recommendation, and **no change to
`src/Keiki/Core.hs` is made until a maintainer records a go decision**.

The companion prototype is `test/Keiki/RecomputeVerifySpec.hs` (5 examples, all green), which
exercises the strategy against the real keiki types with no core edit.

Parent: `docs/masterplans/13-keiki-api-improvements-surfaced-by-the-rei-migration.md`.
Sibling that documents *today's* (strict) contract: `docs/guide/output-invertibility.md`
(created by EP-46, now present).


## 0. The problem in one paragraph

Today `solveOutput` succeeds only when **every** output field is directly invertible — a
literal (`TLit`), a register read (`TReg`), or a command-field projection (`TInpCtorField`).
The field walk `gatherInpEntries`/`stepOne` (`src/Keiki/Core.hs` ~1054–1071) returns `Nothing`
the moment it meets a `TArith`/`TApp1`/`TApp2` field, and that single `Nothing` kills the
**whole edge** on replay — even fields that are not command slots at all. So an event with one
derived field (an audit `previous*` value, a running total `quantity * unitPrice`) cannot
round-trip, forcing the "Direction-A" mirror-command workaround (a redundant command whose only
job is to carry the already-computed value). Recompute-and-verify removes the "one derived
field poisons the edge" failure.


## 1. The relaxed contract

`solveOutput (OPack ic ctor fields) regs co` succeeds **iff**:

- **(a) Recoverability (unchanged in spirit).** For every slot of `ic`, *some* top-level
  invertible field (a `TInpCtorField ic _`) of `fields` reads that slot — i.e. the command is
  fully recoverable from the **invertible fields alone**.
- **(b) Verification (the relaxation).** Every derived field, recomputed forward against the
  recovered command and the pre-update register file, equals the value observed in the event.

Contrast with today: clause (a) is unchanged; clause (b) replaces today's *"every field must
be invertible"* with *"every derived field must verify"*. A derived field is therefore a
**redundant cross-check**, never a source of command information.

Concretely, the intended `solveOutput` shape (whole-event form — see §3):

```haskell
solveOutput (OPack ic@InCtor{} ctor fields) regs co = do
  fs_obs  <- wcMatch ctor co
  entries <- gatherInvertible fields fs_obs ic   -- skip derived fields, don't fail on them
  rf      <- assemble entries                     -- (a): fails if a slot is uncovered
  let ci = icBuild ic rf
  if evalOut (OPack ic ctor fields) regs ci == co -- (b): recompute & verify
    then Just ci
    else Nothing
```


## 2. Proof that "event determines command" is preserved

Let an edge be *admitted* (clause (a) holds: every `ic` slot is read by some top-level
`TInpCtorField`). Claim: on an admitted edge, the recovered command is a function of the
observed event alone, so two distinct commands cannot produce the same observed event.

*Argument.* Command recovery (Phase 1) reads **only** the invertible fields: each
`TInpCtorField ic ix` slot is read straight out of the observed event's field tuple
(`wcMatch ctor co`) and fed to `icBuild`. Derived fields contribute **nothing** to recovery
(Phase 1 skips them). So the recovered command `ci = icBuild ic (assemble entries)` is
determined entirely by the observed values of the invertible fields, which are determined by
`co`. Hence `co` ↦ `ci` is a well-defined function: if `c1 ≠ c2` both produced the same
observed `o` on the same admitted edge, then since each emits `o`'s invertible fields by
copying its own command fields (forward `evalOut`), and those fields are equal (both equal
`o`'s), the recovered command is equal — contradiction.

Clause (b) only ever **rejects** (it can fail a replay whose derived field doesn't verify); it
never *accepts* a command it would not otherwise accept, so it cannot introduce a collision.
Therefore admitting redundant derived fields cannot make two commands collide on one event:
injectivity (the "event determines command" guarantee) is intact. ∎

The build-time half of the invariant ("fails detectably at build time when malformed") is
preserved by the `checkHiddenInputs` refinement in §4: a schema that violates clause (a) — a
command slot read *only* inside a derived field — is flagged before any replay.


## 3. The equality mechanism: whole-event `Eq co`, not field-level `Eq`

Recompute-and-verify must compare each recomputed derived value to the observed one. The
question M1 had to settle is *where* the `Eq` constraint is demanded. Two options were
investigated against the live types.

### Option A — field-level `Eq` (investigated, **rejected as invasive**)

Compare each derived field individually: at a derived field `t :: Term rs ci f` with observed
value `v :: f`, check `evalTerm t regs ci == v`, demanding `Eq f` only on the derived field's
type. This is more precise about *which* field mismatched. **But it cannot be done without
modifying the `Term` GADT.** The live constructors (`src/Keiki/Core.hs` ~245–273) are:

```haskell
TApp1  :: (a -> r) -> Term rs ci a -> Term rs ci r                       -- no constraint on r
TApp2  :: (a -> b -> r) -> Term rs ci a -> Term rs ci b -> Term rs ci r  -- no constraint on r
TArith :: (Num r, Typeable r) => NumOp -> Term rs ci r -> Term rs ci r -> Term rs ci r
```

Pattern-matching a derived field gives **no `Eq r` in scope**: `TArith` carries `Num`+`Typeable`
(and `Num` does not imply `Eq`), and `TApp1`/`TApp2` carry *nothing* about `r` — not even
`Typeable`, so there is not even a dynamic-equality (`Typeable`-cast) fallback for the `TApp`
cases. Demanding `Eq f` therefore requires **adding `Eq r` to the `TArith`/`TApp1`/`TApp2`
constructors**, which:

- changes a core GADT's contract and forces `Eq r` at every construction site (the discard
  criterion in M1 §6 — "an invasive change to `Term` that breaks existing call sites");
- is *semantically wrong* for `TApp`: an opaque escape hatch may legitimately produce a value
  whose type has no `Eq` (it is only ever run forward), so requiring `Eq` on `TApp` results
  narrows a deliberately-general escape hatch.

### Option B — whole-event `Eq co` (recommended)

Recover the command from the invertible fields, then recompute the **whole** output forward
with the existing `evalOut` and compare the rebuilt event to the observed one:
`evalOut (OPack ic ctor fields) regs ci == co`. This demands only `Eq co`.

This is **equivalent** to field-level verification of the derived fields, and strictly simpler:

- The invertible fields recompute to *exactly* their observed values, tautologically. `TLit`
  is constant; `TReg ix` reads the pre-update registers, which are the same registers
  `solveOutput` is handed at emit-replay time; `TInpCtorField ix` reads `ci`, which was
  *assembled from* those observed values. So on an admitted edge the invertible fields always
  match, and `evalOut … == co` reduces to "every derived field matches" — precisely clause (b).
- It is **not a new idea in keiki.** `applyEventStreaming` (`src/Keiki/Core.hs` ~953) already
  recomputes multi-event *tail* outputs forward and matches them by `==`
  (`evaluatedTail = [ evalOut o regs ci | o <- drop 1 (output e) ]`, compared with `Eq co`).
  Whole-event recompute-verify applies the same proven pattern to the *head* output.
- It is **free downstream.** keiro — the only consumer of these replay paths — already requires
  `Eq co` on every hydration entry point (`keiro/src/Keiro/Command.hs` ~112). So whole-event
  `Eq co` adds **no** obligation a keiro user does not already meet.

**Recommendation: Option B (whole-event `Eq co`).** It is non-invasive (no `Term`/`OutFields`
change), provably equivalent to field-level verification, reuses an existing pattern, and is
free for the actual consumer. The only thing Option A buys — naming *which* derived field
mismatched — is a diagnostics nicety obtainable later (a debug helper can field-diff after a
whole-event mismatch) without touching the GADT. The prototype implements Option B.

> Note vs. the plan's earlier Decision Log: EP-47's Decision Log tentatively preferred
> field-level `Eq`. M1's investigation against live constructor constraints inverts that
> preference: field-level is the *invasive* option here (it has no `Typeable` fallback for
> `TApp`), so the documented fallback "require `Eq co` on the whole event type" is in fact the
> *cleaner* primary choice. This is exactly the kind of finding the M1 gate exists to surface,
> and it materially lowers the implementation risk.


## 4. The `checkHiddenInputs` precision refinement

Today `checkHiddenInputs` (`src/Keiki/Core.hs` ~1104) computes one "visited" set per `InCtor`
via `visitedSlotsOf`/`goTerm`, which **descends into derived terms** and counts their nested
`TInpCtorField` slots as visited (~1177–1179). Under today's strict runtime that leniency is
harmless (the runtime rejects *any* derived-containing edge anyway). Under the relaxation it
would be *unsafe*: a schema whose command slot appears **only** inside a derived field (a
genuine hidden input) would pass the build-time check, yet fail at replay (Phase 1's `assemble`
returns `Nothing`).

The refinement computes the **invertible-visited** set — slots read by a *top-level*
`TInpCtorField` field, **without** descending into `TApp`/`TArith` — and uses *that* union for
the well-formedness condition:

```text
missing = allSlots \\ nub invertibleVisitedUnion      -- error iff non-empty
```

This is strictly stronger than today's any-visited check. It:

- **errors** on a hidden input (slot only inside a derived term) — clause (a) violated; and
- **admits** a redundant derived field (its slots also appear top-level invertibly) — clause
  (a) satisfied.

Implementation: add a second walker (`invertibleVisitedSlotsOf`) that inspects only the head
constructor of each `OutFields` entry and does not recurse into `TApp`/`TArith`; keep the
existing descending walk only if still useful for diagnostics. `formatMiss`'s message may need a
word change if it references "visited".


## 5. Newly-admissible output term shapes

Under recompute-and-verify, the following become admissible as **derived** output fields,
*provided every command slot they read is also read by a top-level invertible field of the same
edge* (the redundancy precondition enforced by §4):

- `TArith op a b` — structural arithmetic (a running total, a derived cap).
- `TApp1 f t` / `TApp2 f a b` — opaque function application.

Crucially, even an **opaque** `TApp` is fine: recompute-and-verify only ever runs it
**forward** via `evalTerm` (which already handles `TApp1`/`TApp2`/`TArith`, ~728–737); it never
inverts it. Invertibility of the wrapped function is never required.


## 6. Promotion / discard assessment

The M1 promotion criteria and their status:

| Criterion | Status |
|---|---|
| (i) Prototype green: a `TArith`-output edge round-trips | ✅ `RecomputeVerifySpec`, 5/5 green |
| (ii) The "event determines command" proof holds | ✅ §2 (and the prototype's determinism group) |
| (iii) The `Eq` mechanism compiles against real types without weakening a constraint | ✅ via **whole-event `Eq co`** (no `Term` change); ❌ for field-level `Eq` (would need invasive `Eq r` on `TArith`/`TApp`) |

The discard criterion ("field-level `Eq` cannot be demanded without an invasive `Term` change")
*is* met — so per the plan, the resolution is the documented fallback: **require `Eq co` on the
whole event type**. That fallback turns out to be the better primary mechanism (§3), so the
approach is promotable rather than discarded.


## Analysis and recommendation

### (a) Soundness argument, and where it could fail

The soundness argument is §2: recovery reads only invertible fields; derived fields only
verify. The places it could break, and how each is handled:

- **A derived field's nested command read is not actually covered by an invertible field (a
  hidden input).** This would let a command slot have no recovery source. *Handled* by the §4
  `checkHiddenInputs` refinement (invertible-visited union must cover every slot), which fails
  such a schema at build time. Tested by M3's negative test.
- **Register-file timing (pre- vs. post-update).** `evalTerm` recompute must run against the
  *pre-update* registers — the same registers the edge saw when it emitted. `solveOutput` is
  already handed the pre-update register file at the call sites (`applyEvent` ~886 calls
  `solveOutput o regs co` *before* `applyEdgeUpdate`), so threading that same `regs` into the
  recompute is correct. *Risk if mishandled:* a derived field reading a register would verify
  against the wrong snapshot. The fixture for M3 should include a register-reading derived field
  to lock this down (the M1 prototype's derived field reads only command fields, which is the
  common case but not the only one).
- **The verify `Eq` disagrees with keiro's tail-matching `Eq`.** With whole-event `Eq co` they
  are the *same* `Eq co` instance, so they cannot disagree (this is another point in favour of
  Option B over field-level `Eq`).

### (b) Risks and blast radius

M2 would touch exactly three symbols in `src/Keiki/Core.hs`:

- **`solveOutput`** — starts using its currently-ignored `_regs` argument and adds the Phase-2
  recompute-verify. *Risk:* low. The all-invertible path produces an empty derived set, so
  `evalOut … == co` is the tautology above and the result is byte-for-byte today's behavior.
  The signature is unchanged.
- **`gatherInpEntries`/`stepOne`** — the derived arms change from `Nothing` to "skip"
  (contributing no entries) so recovery proceeds from the invertible fields. *Risk:* low–medium;
  the invertible arms are untouched. (With whole-event Option B, the deferred-derived list is
  not even needed — `evalOut` recomputes the whole output — so this change is just "don't fail
  on derived"; simpler than the field-level plan envisaged.)
- **`checkHiddenInputs`** — the §4 refinement, *strictly stronger*. *Risk:* must not regress
  existing fixtures. The regression guard is the existing suite, especially
  `test/Keiki/CoreHiddenInputsGSMSpec.hs` and every aggregate fixture
  (`Keiki.Fixtures.UserRegistration`, `jitsurei/*`) whose edges are all-invertible and must
  still report no warnings.

`applyEvent`/`applyEventStreaming`/`applyEvents`/`reconstitute` need **no** change — they
already pass `regs` and gain the new behavior transparently. No type signatures change. No new
`unsafeCoerce`. The change is additive.

### (c) The docs-only alternative, weighed

A legitimate **no-go** outcome is to relax nothing and keep Rei keiki #1 as a documented
contract. EP-46 already ships `docs/guide/output-invertibility.md` describing today's strict
behavior *and* the Direction-A mirror-command workaround, so a no-go does not leave the finding
unaddressed — it leaves it *documented* rather than *fixed*.

- **Cost of no-go:** consumers keep paying the mirror-command tax — a redundant command per
  derived-value event, doubling vocabulary for affected aggregates (Rei's Reminder, Disruption,
  Cycle, …). The "one derived field poisons the whole edge" sharp edge remains.
- **Benefit of no-go:** keiki's foundational invariant code (`solveOutput`) is not touched at
  all; zero risk to the decisive technical win.

### (d) Recommendation

**Recommend GO, implementing the whole-event `Eq co` mechanism (Option B).** The rationale:

1. The soundness proof (§2) holds; the prototype demonstrates both the round-trip and that the
   recovered command stays unique (5/5 green).
2. The mechanism is **non-invasive** — `Eq co` only, no `Term`/`OutFields` change — and is the
   *same* `Eq co` keiro already requires, so there is no new consumer burden.
3. It **reuses a pattern already in the codebase** (the `applyEventStreaming` tail recompute),
   so it is not a foreign concept being bolted on.
4. Blast radius is small and additive; the all-invertible fast path is provably unchanged, with
   the existing suite as the regression guard.
5. The build-time guarantee is preserved by a *strictly stronger* `checkHiddenInputs`.

This recommendation differs from the plan's tentative field-level-`Eq` Decision Log entry; the
difference (whole-event `Eq co` instead) is the substantive M1 finding and should be ratified
along with the go decision. If the maintainer prefers, for now, not to touch the foundational
invariant, **no-go (docs-only via EP-46) remains a fully legitimate outcome** and this note
plus the prototype stand as the record for revisiting it later.

**This is the ratification gate. M2 does not begin until a maintainer records a go decision in
EP-47's Decision Log.**


## M2 refinement (2026-05-21): recompute *only* derived fields, not the whole output

The gate was approved **GO — whole-event `Eq co`**. Implementing the literal "recompute the
whole output forward and compare (`evalOut o regs ci == co`)" form revealed it is **too
strict**: it re-verifies the *invertible* fields too, which the contract says are not verified.
Two concrete breakages surfaced (both real regressions, not test bugs):

1. **`TReg` audit fields.** An edge that emits `email = #email` (a register read) must round-trip
   even when replay starts from a state whose registers are not yet populated — EP-46 documents
   exactly this ("a `TReg` audit field already round-trips"). Whole-event recompute reads the
   register file and compares the recomputed value to the observed event field, so it rejects
   such a replay when the register is empty (e.g. a streaming step from a synthetic mid-state).
2. **Forcing `ci`.** `evalOut` forces the recovered command `ci`; for an `lmapCi`-rewritten
   edge whose `icBuild` is deliberately poisoned, the poison then fires *inside* `solveOutput`
   rather than lazily at the call site, changing observable behavior.

The correction keeps the **same `Eq co` constraint** but verifies at field granularity: rebuild
the observed field tuple recomputing **only** the derived (`TApp1`/`TApp2`/`TArith`) fields and
leaving every invertible (`TLit`/`TReg`/`TInpCtorField`) field at its observed value, then
compare the rebuilt event to the observed one:

```haskell
solveOutput (OPack ic@InCtor{} ctor fields) regs co = do
  fs_obs  <- wcMatch ctor co
  entries <- gatherInpEntries fields fs_obs ic          -- skips derived fields
  rf      <- assemble entries
  let ci      = icBuild ic rf
      rebuilt = wcBuild ctor (recomputeDerivedFields fields fs_obs regs ci)
  if rebuilt == co then Just ci else Nothing

recomputeDerivedFields :: OutFields rs ci fs -> fs -> RegFile rs -> ci -> fs
-- recompute TApp1/TApp2/TArith via evalTerm; keep observed value otherwise.
```

This is still "whole-event `Eq co`" in the sense that the comparison is on `co` and the
constraint is `Eq co` (so §3's non-invasiveness argument and the keiro cost note are unchanged),
but it verifies *exactly* the derived fields — equivalent to the field-level intent of §1's
clause (b), without the over-verification. Because invertible fields are copied from the
observed tuple, an all-invertible edge rebuilds the observed event by construction (a no-op
check) and never forces `ci`, so both breakages above disappear and the fast path is unchanged.

The §1 contract and the §2 proof are unaffected: command recovery still reads only the
invertible fields (clause a); derived fields still only *verify* (clause b). Sections 1 and 3's
prose that says "recompute the whole output / `evalOut … == co`" should be read as "rebuild the
event recomputing only the derived fields", per this addendum.
