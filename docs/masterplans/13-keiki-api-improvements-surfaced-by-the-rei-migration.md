---
id: 13
slug: keiki-api-improvements-surfaced-by-the-rei-migration
title: "Keiki API improvements surfaced by the Rei migration"
kind: master-plan
created_at: 2026-05-21T22:59:08Z
intention: "intention_01ks6ber3jedc8ff6zzma2jr53"
---

# Keiki API improvements surfaced by the Rei migration

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Vision & Scope

Rei is the first non-trivial consumer of keiki (the pure symbolic-register transducer
core), and porting ~25 aggregates onto it surfaced a set of sharp edges. This initiative
addresses the keiki-only subset of those findings, captured in the consumer's own write-up
at `../rei-project/rei.keiro-migration/docs/dev/design/keiro-stack-improvement-suggestions.md`
(the "keiki" section, items #1–#6). Every item was evaluated against keiki's foundational
invariant before being accepted, reshaped, or rejected. That invariant, from
`docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md` §1, is:

> The decisive technical win: `apply` derivation comes back for well-formed schemas
> (output term invertible in input fields), and fails detectably at build time when a
> schema is malformed (hidden inputs, non-injective output).

In plain terms: keiki never lets the user hand-write `apply`. It *derives* the
event→state replay function by inverting each edge's output term (`solveOutput` in
`src/Keiki/Core.hs`, wired into `evolve` by `Keiki.Decider.toDecider`). Output
invertibility is the property the library exists to guarantee. Any change is faithful
only if it preserves "the event uniquely determines the command, certified at build time."

After this initiative is complete:

- A single consumer-facing document states the exact output-invertibility contract — which
  output term shapes round-trip on replay (`TLit`, `TReg`, `TInpCtorField`) and which abort
  it (`TApp1`, `TApp2`, `TArith`) — with worked "this event stores a derived value → do X"
  recipes. Today this rule is real but scattered across three research notes and was only
  discoverable by reading `solveOutput`'s source, which cost Rei the most time of any keiki
  finding.
- `solveOutput` accepts derived (currently non-invertible) output fields via a
  **recompute-and-verify** strategy — recover the command from the invertible fields, then
  recompute each derived field forward and check it equals the observed event value —
  *while preserving* the build-time certification that the event determines the command.
  This is the faithful answer to "derived event fields can't round-trip" (Rei keiki #1):
  it relaxes an over-strong requirement (every field invertible) without surrendering the
  guarantee (the command is still uniquely recovered from the invertible fields).
- A multi-family event stream composes from N already-derived event families without a
  hand-maintained flat union, generalizing the existing binary `Either`-based
  `leftWireCtor`/`rightWireCtor`/`alternative` machinery in `src/Keiki/Composition.hs`;
  and `deriveWireCtors` supports zero-argument (singleton) events. This addresses Rei's
  forced 48-constructor flat `IntentionRootEvent` (keiki #2).
- The edge builder gains a non-breaking `:=` synonym for `.=` (which collides with
  `Control.Lens.(.=)`) and a `reg @"slot"` register-read helper mirroring the existing
  write-side `slot @"name"` (keiki #4).
- The Mermaid renderer gains an atlas entry point that assembles many transducer diagrams
  into one labelled document, and an opt-in structural edge-summary annotation (written-slot
  names and a guard-constructor/comparison summary), with the default label format left
  byte-identical so the pedagogy in `docs/guide/deriving-lifecycle-transitions.md` (which
  relies on the renderer "deliberately omitting the guard") still holds (keiki #5).

**Explicitly out of scope** (rejected on faithfulness grounds; see Decision Log):

- A user-supplied `backward` closure on an output term (Rei keiki #1 suggestion a). The
  library could not certify `forward ∘ backward = id`; it would be an unverifiable
  trust-me escape that defeats the very build-time guarantee.
- A "recorder edge" / "value-event" with a hand-written forward `apply` (Rei keiki #1
  suggestion b). This is the already-rejected "Approach 3 / Direct MultiDecider"
  (`docs/research/multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md`
  §, masterplan-7 Decision Log): it surrenders mechanical `apply` derivation by definition.
- A variadic / `TApp3`/`TApp4`/`TAppN` apply (Rei keiki #3). `TApp` carries an opaque
  Haskell function that is **not** translated to SMT (it becomes a fresh `SBV.free`
  variable); the entire recent arc of the project (EP-41/43/44/45) moved *away* from `TApp`
  toward structural terms the solver can read. More arity buys nothing for the solver and
  encourages the anti-pattern. The cited cases have structural answers documented in EP-46.
- Auto-derivation of positional multi-argument constructors (Rei keiki #2, first half).
  The symbolic alphabet projects fields *by name* (`InCtor`'s `ifs :: [Slot]` are
  `(Symbol, Type)` pairs); positional args have no names. The idiomatic shape — a single
  named-record payload — is documented in EP-46 instead.
- Full guard/update AST in Mermaid edge labels (Rei keiki #5, first half, in its literal
  form). There is no pretty-printer for `HsPred`/`Term`/`Update` and the AST carries
  unprintable functions; masterplan-10 already rejected the full-AST form as clutter.
  EP-50 delivers a *structural summary* instead.

The whole initiative is keiki-only. The keiro and kiroku findings, and the cross-cutting
"tagged releases" and "combined migration cookbook" suggestions in the same source
document, are out of scope here.


## Decomposition Strategy

The work was decomposed by functional concern, not by file, so each work stream produces
an independently verifiable behavior. Five streams emerged:

- **EP-46 (documentation)** isolates the zero-code, immediately-deliverable win: writing
  down the invertibility contract that already governs the code today, plus the modeling
  redirects for the rejected items (#3 structural-guard answers, #2a single-record idiom).
  It is separated from the code changes because it ships value on day one and because it
  is the artifact EP-47 later amends.
- **EP-47 (recompute-and-verify)** is the theoretically substantive keystone. It is its own
  stream because it touches the foundational invariant in `solveOutput` and therefore opens
  with a design milestone (a research note plus a prototype) before any core edit. Bundling
  it with anything else would couple the riskiest change to unrelated work.
- **EP-48 (codec composition)** is the multi-family event-stream feature. It lives in
  `src/Keiki/Composition.hs` and generalizes machinery that already exists there; it shares
  no code with the other streams.
- **EP-49 (builder ergonomics)** is two small, self-contained additions to
  `src/Keiki/Builder.hs` and the label machinery. It is deliberately kept tiny and
  independent.
- **EP-50 (Mermaid)** is two additions to `src/Keiki/Render/Mermaid.hs`. It is independent
  except for one shared contract with EP-46 (the default label format must stay guard-free).

Principles applied: each stream is independently verifiable (docs by link/build check, the
three feature streams by their own golden/property tests); cross-plan coupling is minimal
(only EP-46↔EP-47 share the contract docs, and EP-46↔EP-50 share the "default omits guard"
contract); natural ordering is respected (EP-46 documents the contract that EP-47 changes,
so EP-46 goes first). The four no-dependency streams (EP-46, EP-48, EP-49, EP-50) form
Phase 1 and can proceed in parallel; EP-47 is Phase 2.

Alternatives considered and rejected during decomposition: (1) folding the EP-46 redirects
for items #2a and #3 into separate plans — rejected because they are pure documentation with
no code and belong with the other docs; (2) merging EP-49 and EP-50 as "miscellaneous
ergonomics" — rejected because they touch unrelated modules and have independent acceptance;
(3) implementing EP-47 without a design milestone — rejected because it changes the core
invariant and must be designed and prototyped before code.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| 46 | Document the output-invertibility contract and derived-value modeling patterns | docs/plans/46-document-the-output-invertibility-contract-and-derived-value-modeling-patterns.md | None | None | Complete |
| 47 | Recompute-and-verify derived event outputs in solveOutput replay | docs/plans/47-recompute-and-verify-derived-event-outputs-in-solveoutput-replay.md | None | EP-46 | Complete (gate GO) |
| 48 | N-ary event-family codec composition and singleton-event support | docs/plans/48-n-ary-event-family-codec-composition-and-singleton-event-support.md | None | None | Complete |
| 49 | Builder ergonomics: assignment synonym and register-read label helper | docs/plans/49-builder-ergonomics-assignment-synonym-and-register-read-label-helper.md | None | None | Complete |
| 50 | Mermaid renderer: atlas entry point and structural edge-summary annotations | docs/plans/50-mermaid-renderer-atlas-entry-point-and-structural-edge-summary-annotations.md | None | EP-46 | Complete |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix (e.g., EP-46).


## Dependency Graph

There are no hard dependencies: every plan compiles and is verifiable on its own. The
ordering is governed by two soft dependencies.

EP-47 soft-depends on EP-46. EP-46 writes down the output-invertibility contract as it
stands today; EP-47 *relaxes* that contract (admitting recompute-and-verify of derived
fields). Doing EP-46 first means EP-47's final milestone amends an existing, accurate
contract page rather than writing it from scratch. If EP-47 is somehow taken first, it must
itself create the contract page; the soft dependency simply avoids duplicated effort.

EP-50 soft-depends on EP-46 for a single shared invariant: `docs/guide/deriving-lifecycle-transitions.md`
(referenced and cross-linked by EP-46) teaches a bug-spotting technique that relies on
`Keiki.Render.Mermaid` "deliberately omitting the guard" from edge labels. EP-50 adds an
*opt-in* guard summary; its default must remain guard-free so that pedagogy survives. EP-50
can proceed before EP-46, but whoever does EP-50 must preserve the guard-free default.

EP-48 and EP-49 are fully independent and can be done at any time, in parallel with
everything else.

Recommended waves: **Phase 1** — EP-46, EP-48, EP-49, EP-50 in parallel. **Phase 2** —
EP-47 (its own design milestone first, then implementation, then a docs amendment that
closes the loop with EP-46).

EP-47's design milestone (M1) is a hard ratification gate, not an ordinary first milestone:
it produces the research note, a prototype, and a written analysis/recommendation, then STOPS
for an explicit maintainer go/no-go before any `solveOutput` change (M2). A no-go outcome is
legitimate — #1 then stays docs-only, carried entirely by EP-46. So Phase 2 does not
auto-proceed from design to implementation.


## Integration Points

- **The output-invertibility contract documentation.** Involved: EP-46 (defines), EP-47
  (amends). The shared artifact is a new consumer-facing guide page (working name
  `docs/guide/output-invertibility.md`) plus the relevant glossary entries in
  `docs/guide/user-guide.md`. EP-46 creates it describing today's behavior: `solveOutput`
  inverts only `TLit`/`TReg`/`TInpCtorField` and returns `Nothing` (not an exception; the
  named `HydrationReplayFailed` belongs to the keiro/Rei runtime) for `TApp1`/`TApp2`/`TArith`.
  EP-47's final milestone edits this same page to document the relaxed recompute-and-verify
  contract. Neither plan may silently diverge from this page; EP-47 must update it in lockstep
  with the code.

- **`solveOutput` and its static companion in `src/Keiki/Core.hs`.** Involved: EP-47
  (modifies), EP-46 (documents, does not modify). The shared symbols are `solveOutput`
  (Core.hs ~1039), its helper `gatherInpEntries`/`stepOne` (the term accept/reject site,
  ~1054–1071), `applyEvent`/`applyEventStreaming` (~882–966), and the build-time analysis
  `checkHiddenInputs` (~1104–1197). EP-46 must describe their *current* behavior accurately;
  EP-47 owns all edits to them. The `Eq co` (event-type equality) requirement that
  recompute-and-verify introduces is EP-47's to define.

- **`WireCtor` / `OutTerm` / `OPack` and the `Composition` lift family.** Involved: EP-48
  (extends), EP-47 (reasons about, does not extend). The shared artifacts are `WireCtor`
  (Core.hs ~404), `OutTerm`/`OPack` (Core.hs ~451), and the existing coproduct lifts
  `leftWireCtor`/`rightWireCtor`/`leftInCtor`/`rightInCtor` and the `liftLOutAlt`/`liftROutAlt`
  AST re-taggers in `src/Keiki/Composition.hs` (~485–671). EP-48 owns the N-ary
  generalization. The correctness obligation both plans share: `solveOutput`/`stepOne` match
  `OPack`s by `icName`/`wcName` *string equality* (Core.hs ~1067), so any summed alphabet
  must keep those names unambiguous across families. EP-48 is responsible for enforcing/testing
  that.

- **Mermaid default label format.** Involved: EP-50 (extends), EP-46 (depends on the
  guard-free default). The shared artifact is `edgeLabel`/`renderTopology` in
  `src/Keiki/Render/Mermaid.hs` and the golden tests in `test/Keiki/Render/`. EP-50 must add
  its guard summary as opt-in and keep the no-options default byte-identical to today's
  `<input> / <output>` format, proven by an unchanged golden.

- **`Keiki.Builder` operator/label surface.** Involved: EP-49 only. Listed here because the
  `.=` operator and the `slot`/`IsLabel` machinery in `src/Keiki/Builder.hs` and
  `src/Keiki/Core.hs` are touched by EP-49's additions; no other plan modifies them.


## Progress

Track milestone-level progress across all child plans. Each entry names the child plan and
the milestone. (Milestones are seeded top-down here for coordination; each child plan owns
the authoritative, detailed version.)

- [x] EP-46 M1 (2026-05-21): New `docs/guide/output-invertibility.md` stating the exact accept/reject term list and the `Nothing` (not-an-exception) semantics; also the all-or-nothing-per-edge failure, output-only scoping, and `checkHiddenInputs` net.
- [x] EP-46 M2 (2026-05-21): Worked "derived value → do X" recipes (audit field via `TReg` already round-trips; computed total via mirror-command today + forward pointer to EP-47; the Direction-A mirror workaround).
- [x] EP-46 M3 (2026-05-21): Cross-link sweep + modeling redirects — #3 general structural-guard guidance (bounds→`PCmp`, multi-way branching→disjoint edges, computed operands→`tadd`/`tsub`/`tmul`) with the note that the validated Rei residual is collection-register *update* tuple-threading, not guards; #2a single-record idiom (source the dropped id from a register). Plus corrected the stale `solveOutput` "build-time analysis" label in both user-guide glossary occurrences.
- [~] EP-47 M1 (design milestone + ratification gate) — DELIVERABLES COMPLETE; STOPPED for maintainer go/no-go (2026-05-21): Research note `docs/research/recompute-and-verify-derived-outputs.md` + prototype `test/Keiki/RecomputeVerifySpec.hs` (5/5 green, no `src/` change) + written analysis. Recommendation **GO** via **whole-event `Eq co`** (the M1 investigation found field-level `Eq` invasive — `TApp` carries no `Typeable`; whole-event `Eq co` is non-invasive, equivalent, and already required by keiro). Decision pending; M2 blocked until a go is recorded (no-go = keep #1 docs-only, EP-46 carries it).
- [x] EP-47 M2 (2026-05-21): Implemented recompute-and-verify in `solveOutput`/`gatherInpEntries` (derived fields skipped in recovery, recomputed-and-verified via a new `recomputeDerivedFields` + `Eq co`); refined `checkHiddenInputs`/`detectMissingInCtorFields` to the invertible-visited set. `Eq co` propagated to `applyEvent`/`outputAcceptor`. (The whole-event `evalOut` form over-verified `TReg` fields; corrected to derived-only recompute — see EP-47 Surprises.)
- [x] EP-47 M3 (2026-05-21): Round-trip (order-cart derived total via `applyEvents`, tampered rejected), determinism (grid through real `solveOutput`), and negative (`checkHiddenInputs` flags a hidden input) tests in `test/Keiki/RecomputeVerifySpec.hs`.
- [x] EP-47 M4 (2026-05-21): Amended the EP-46 contract page `docs/guide/output-invertibility.md` + user-guide glossary to the relaxed recompute-and-verify contract; closed.
- [x] EP-48 M1 (2026-05-21): N-ary `WireCtor`-sum design confirmed via ghci prototype — right-nested `Either`, family *k* = `rightX^(k-1) . leftX`, composed from the already-exported binary lifts. Decision: ship arity-3 wrappers + general recipe, no type-indexed witness.
- [x] EP-48 M2 (2026-05-21): Implemented arity-3 injectors (`wireCtor3At{1,2,3}`/`inCtor3At{1,2,3}`/`outTerm3At{1,2,3}`) in `src/Keiki/Composition.hs`, additively (binary `alternative`/lifts untouched; `Keiki.Core` untouched; no new `unsafeCoerce`).
- [x] EP-48 M3 (2026-05-21): Singleton-event support — `mkWireCtor0` in `src/Keiki/Generics.hs` + a `Just Nothing` arm in `genWire`; `deriveWireCtors` accepts zero-arg ctors. Existing derivations unchanged.
- [x] EP-48 M4 (2026-05-21): `test/Keiki/CompositionNarySpec.hs` (multi-family round-trip via `solveOutput` + `icName`/`wcName` uniqueness + singleton round-trip; registered in cabal + Spec.hs) + `docs/guide/composition.md` §8.7. keiki-test 253→260, 0 failures.
- [x] EP-49 M1 (2026-05-21): `=:` non-breaking synonym for `.=` in `Keiki.Builder` (same `infixr 6` fixity), exported + haddock. (Planned `:=` is impossible — colon-prefixed operators are data constructors in Haskell; maintainer chose `=:`.)
- [x] EP-49 M2 (2026-05-21): `reg @"slot"` register-read helper mirroring `slot @"name"`, exported + haddock.
- [x] EP-49 M3 (2026-05-21): Dogfood in `jitsurei` LoanApplication (guards→`reg`, one edge→`=:`); `(=:)`≡`(.=)` test; new generic-lens interop guide `docs/guide/generic-lens-and-label-reads.md` (new projects: don't import `Data.Generics.Labels ()` globally; helpers are the no-refactor path); doc notes + glossary rows in user-guide. Full `cabal test all` green.
- [x] EP-50 M1 (2026-05-21): Atlas entry point `toMermaidAtlas :: [(Text, Text)] -> Text` assembling N labelled diagrams into one Markdown document.
- [x] EP-50 M2 (2026-05-21): Opt-in structural edge summary (`MermaidOptions`/`toMermaidWith`: written-slot names + guard/`Cmp` tag walk); default unchanged (guard-free).
- [x] EP-50 M3 (2026-05-21): Goldens — default byte-identical (pre-existing golden unchanged, actively verified) + annotated + atlas (all captured, not hand-typed); new `docs/guide/mermaid-rendering.md` + cross-link. keiki-test 253/0.


## Surprises & Discoveries

Document cross-plan insights, dependency changes, scope adjustments, or unexpected
interactions between child plans. Provide concise evidence.

- During evaluation it surfaced that part of Rei keiki #1's pain is avoidable on today's
  code: an event field that stores a register's *prior* value (a `previous*` audit field)
  is a plain `TReg` read, and `TReg` already round-trips (`stepOne (TReg _) = Just []`,
  Core.hs ~1064; outputs are evaluated against the pre-update register file). Rei hit the
  wall only by writing such fields as derived `TApp` expressions. EP-46 must call this out
  explicitly so the next consumer reaches for `TReg` first.
- The named error `HydrationReplayFailed` does not exist anywhere in keiki (verified by
  repo-wide grep); keiki's inversion failure is a plain `Maybe`/`Nothing`. The named error
  is the keiro/Rei runtime's translation of that `Nothing`. EP-46 must not attribute it to
  keiki.
- The recompute-and-verify mechanism EP-47 introduces is not foreign to keiki: the
  multi-event tail machinery in `applyEventStreaming` (Core.hs ~959–966) already evaluates
  tail outputs *forward* and matches them by `Eq`. EP-47 generalizes that within-edge for
  derived head-output fields.

Discovered during child-plan drafting (2026-05-21), each verified against live source:

- **Test harness is a manual aggregator, hspec-only — affects EP-47, EP-48, EP-49, EP-50.**
  `test/Spec.hs` lists each spec module with explicit `import qualified … Spec` lines (not
  `hspec-discover`), and `keiki.cabal`'s test stanza depends on `hspec` with **no QuickCheck
  or Hedgehog**. Consequence for every plan that adds a test module: register it in *both*
  `keiki.cabal` `other-modules` and `test/Spec.hs`, and write "property" tests as finite
  enumerations rather than generator-driven. The suite name is `keiki-test`
  (`cabal test keiki-test`); `jitsurei` has its own `jitsurei-test`.
- **`solveOutput` already receives the `RegFile` but ignores it (param `_regs`,
  Core.hs ~1040) — affects EP-47.** The recompute path therefore needs *no signature change*;
  M2 just starts using the argument already in scope.
- **The user-guide glossary mislabels `solveOutput` as "the build-time analysis" — affects
  EP-46 and EP-47.** `solveOutput` is the *runtime* inverter; `checkHiddenInputs` is the
  build-time analysis. `docs/guide/user-guide.md` (~§10.3, and the `#name` description near
  ~320–321 which mis-says reads go via `proj` of an `IndexN`) needs correcting. EP-46 M3 and
  EP-49 M3 both touch these lines — coordinate so they don't conflict.
- **Mermaid written-slot recovery is NOT via `KnownSlotNames` over the write-set `w` —
  affects EP-50.** `w :: [Symbol]` is existentially quantified at the `Edge` record with no
  class dictionary carried, and `KnownSlotNames` is indexed by `[Slot]` (wrong kind). The
  faithful route is structural recursion over the `Update` *value* (`USet ix _` brings its
  `KnownSymbol` into scope; `indexNName ix` from `Keiki.Internal.Slots` yields the name).
  EP-50 was written around a `writtenSlots :: Update rs w ci -> [Text]` helper accordingly.
- **`deriveWireCtors`'s singleton arm must bypass `genTermFieldsRecord` — affects EP-48.**
  `mkWireCtor0 :: Eq co => String -> co -> WireCtor co ()` carries field type `()` and the
  new `genWire` arm emits only the `wire<Short>` declaration (no `TermFields` record).
  `mkInCtor0` (the command-side precedent) is at `src/Keiki/Generics.hs` ~156–161.
- **`Keiki.Builder` does not currently import `TReg`/`proj` from `Keiki.Core` — affects
  EP-49.** The builder only ever wrote slots; the new `reg @"slot"` read helper must add
  `TReg` to the import list. `IsLabel s (Term rs ci r)` builds `#slot` via `TReg (indexOf …)`
  over an `Index` (not `proj`/`IndexN`), so the bare-`#slot` read path exists in keiki — but
  see the validation finding below: it is unusable in a consumer prelude that re-exports
  generic-lens.

Validation against the consumer (Rei) and the runtime (keiro), 2026-05-21, each verified
against live source in `../rei-project/rei.keiro-migration` and `../keiro`:

- **Attribution for #1 confirmed: the fix belongs in keiki, not keiro.** keiro stores ONLY
  events — the Kiroku `RecordedEvent` (`kiroku-store/.../Types.hs`) carries no command field,
  and keiro's codec persists only `payload = encode event`. Every keiki state-reconstruction
  primitive keiki exports (`applyEventStreaming`, `applyEvents`, `reconstitute`, `applyEvent`)
  recovers the command by inverting the output through `solveOutput`; keiki exposes NO forward
  event→state fold that bypasses inversion. keiro's `Keiro.Command.hydrate`
  (`keiro/src/Keiro/Command.hs` ~110) is a thin pass-through whose `hydrateFull`/`replayFrom`
  helpers call `Keiki.applyEventStreaming` and turn its `Nothing` into the keiro-owned error
  `HydrationReplayFailed` (`Command.hs` ~175, ~244). keiro could only sidestep the constraint
  by changing its STORAGE FORMAT (persist the command in event metadata and re-run `step`
  forward) — a wire/schema change, not a faithful fix, and useless for existing logs. So
  EP-47 belongs in keiki; the recompute-and-verify forward consumer is exactly what keiro
  cannot synthesize from today's keiki surface.
- **EP-47 is well-aligned with keiro and lower-burden than feared.** keiro ALREADY requires
  `Eq co` for all hydration (`Command.hs` ~112), so the field-level `Eq` EP-47 introduces
  imposes no new burden on keiro consumers. The fix benefits BOTH keiro's replay path
  (`applyEventStreaming` via `hydrate`) and its snapshot path (`applyEvents` via
  `writeSnapshotIfNeeded`, `Command.hs` ~440). Two keiro-owned signals must NOT be conflated
  with the #1 bug: `HydrationReplayFailed` also fires on a final `InFlight` wrapper
  (mid-chain truncation), and codec failures are a SEPARATE `HydrationDecodeFailed`.
- **#1 is harsher than the source doc states — strengthens EP-46/EP-47.** A SINGLE
  non-invertible output field makes `gatherInpEntries` return `Nothing` and kills the WHOLE
  edge on replay, even fields that are not command slots. So an aggregate with even one
  state-resolved `previous*` field (Rei's Reminder, Disruption) is dragged into Direction A.
  Recompute-and-verify (EP-47) directly removes this "one field poisons the edge" failure.
  Rei's Cycle is the canonical Direction-A example
  (`rei-core/src/Rei/Modules/Cycle/Domain/Transducer.hs`), with a `CycleStreamCommand` whose
  constructors mirror each event verbatim. Note: ~18 `*StreamCommand` types exist in Rei but
  only ~8 are forced by derived values; the rest adopted Direction A for uniformity or for
  positional multi-arg commands (which is really #2). The doubled-vocabulary cost is thus
  partly self-imposed.
- **#2 confirmed exactly; keiro does not mitigate it.** The flat `IntentionRootEvent`
  (`rei-core/src/Rei/Modules/Intention/Domain/RootEvent.hs`) is a hand-unified single-level
  sum of exactly 48 constructors across 5 families; a two-level wrapper fails at keiki's TH
  (`conPayload`/`genWire`/`genTermFieldsRecord`). keiro's codec is a hand-supplied
  `encode`/`decode` pair agnostic to constructor shape, so it neither helps nor hurts —
  the constraint is purely keiki's TH, confirming EP-48 is keiki-only. The multi-arg→single-record
  flatten (sourcing the dropped id from a register, e.g. Focus
  `UpdateFocus !FocusId !UpdateFocusData` → single record + `proj` of `focusId`) is pervasive
  and is exactly the redirect EP-46 documents — Rei's working code validates that redirect.
- **#3 was MIS-STATED — downgrade and re-anchor (affects EP-46 and the #3 decision below).**
  The Cycle date-bounds + map-membership GUARDS and the 3-way conditional cited in the source
  doc DO NOT EXIST in Rei's ported transducer — Direction A moved them to the (deferred)
  application layer. The only residual tuple-nesting in all of `rei-core/src` is two
  `Map.insert` register UPDATES that thread a (map, key, value) triple
  (`Cycle/Domain/Transducer.hs`, `CustomProperty/.../PropertyAssignmentTransducer.hs`):
  3 inputs, never a guard, never >3, never breaks replay. The real (Low-priority) ergonomic
  is collection-register update tuple-threading, which belongs to the collection-registers
  roadmap — not a `TApp` arity bump. Our rejection stands; the anchor changes.
- **#4 confirmed and STRONGER than credited — corrects our framing.** Rei reads registers via
  `proj (indexOf @"slot" @Regs @Ty)` in 100% of cases (10 occurrences; ZERO bare `#slot`,
  ZERO annotated `#slot`), because `Rei.Prelude` re-exports generic-lens whose `IsLabel`
  instance shadows keiki's `IsLabel s (Term rs ci r)` (annotated inline in
  `Cycle/Domain/Transducer.hs`). So the bare-`#slot` read path is effectively UNAVAILABLE to
  any consumer using lens/generic-lens — Rei's framing was NOT inaccurate. `reg @"slot"`
  (TypeApplication, no overloaded label) is the genuine fix precisely because it avoids
  `IsLabel`; it is essential, not merely convenient. `hiding ((.=))` appears in 9 files.
- **#5 confirmed.** Rei's ~70 lines of atlas glue (`rei-core/test/Rei/Diagrams/Transducers.hs`,
  golden-tested) is exactly what an atlas entry point subsumes; the transducers are
  heterogeneously typed (a 25-entry list of different `SymTransducer` types), confirming
  EP-50's `[(Text, Text)]` (label, pre-rendered) signature over a typed list. A structural
  edge summary suffices for review; Rei does not need full term-expression rendering.
- **#6 confirmed positive.** Rei split Intention into small scalar aggregates (root keeps two
  scalar registers, no collection registers); the atomic dormancy auto-wake is a genuine
  multi-event edge replayed via keiki's `InFlight` machinery, proven by `RootKeiroSpec`.

Discovered during EP-46 implementation (2026-05-21):

- **The `solveOutput` "build-time analysis" mislabel appears TWICE in `docs/guide/user-guide.md`,
  not once — affects EP-49.** The earlier Surprises note flagged the §10.3 glossary entry
  (line 756). EP-46 M3 found a *second* identical mislabel in §10.7 "Naming origins" (line 885,
  "The build-time analysis that *solves* for the input…") and fixed both: §10.3 now reads "The
  *runtime* inverter on the replay path (called by `applyEvent`/`applyEventStreaming`/
  `reconstitute`)…" and §10.7 "The *runtime* inverter that *solves* for the input…".
  `checkHiddenInputs` keeps its (correct) "build-time analysis" label. EP-49 M3 also edits this
  glossary region (the `#name`/`IndexN` read description near lines 320–321 that it owns) — it
  must not re-introduce the old `solveOutput` wording. EP-46 deliberately left lines 320–321
  untouched so the two plans do not conflict.
- **EP-47's amendment surface is set up as planned.** The new page's "What inverts today" (§2)
  opens with an explicit "as of this writing; EP-47 will relax it" admonition, and the §7.2 /
  §4 forward pointers all name `docs/plans/47-…`. EP-47 M4 can amend §2 (and the §4/§7.2
  forward pointers) as a localized edit rather than a rewrite, exactly as the integration point
  intends.

Discovered during EP-49 implementation (2026-05-21):

- **The planned `:=` operator is a hard Haskell impossibility — affected EP-49 M1.** GHC
  reserves operators beginning with a colon (`:`) for *data constructors*, so `(:=) = (.=)`
  fails to compile (GHC-94426, "Invalid data constructor '(:=)' in type signature"). The
  master plan's Vision/Decision-Log text and EP-49's body all named `:=`; that glyph cannot be
  a value-level synonym. The maintainer chose `=:` (a valid `=`-prefixed operator, no
  `lens`/`aeson` clash, same `infixr 6`/body). **Anywhere this MasterPlan says `:=` (Vision §4
  bullet, the EP-49 Decision Log entry, the EP-49 M1 progress seed), read `=:`.** `reg` (M2) was
  unaffected. Lesson for future plans: validate a proposed operator glyph against Haskell's
  lexical rules (colon-prefix ⇒ constructor) before committing it.
- **The user-guide `#name` "proj of an IndexN" mislabel (flagged earlier as EP-46↔EP-49 shared
  territory) was corrected by EP-49, not EP-46.** EP-46 deliberately left user-guide lines
  ~320–321 untouched; EP-49 M3 rewrote them to "`#name` resolves via `IsLabel s (Term rs ci r)`
  to a `TReg`" and added the `reg @"name"` form. No conflict occurred between the two plans on
  that region.

Discovered during EP-50 implementation (2026-05-21):

- **The `Edge.update` record selector can't be used as a function (escaped existential).**
  EP-50's plan claimed `update e` works as a selector; it does not — `Edge`'s
  `update :: Update rs w ci` existentially quantifies `w`, so GHC rejects the selector
  (GHC-55876). The fix is pattern-matching the edge (`e@Edge { update = u, guard = g }`). This
  is a general keiki fact for any future code reading an edge's update: pattern-match, never use
  the selector. (`guard`, a non-existential field, is fine as a selector.)
- **The EP-46↔EP-50 soft alignment held with no coordination.** EP-50 keeps `toMermaid`'s
  default byte-identical and guard-free (pinned by the unchanged `userRegCanonical` golden,
  actively verified by flipping a default), so the bug-spotting pedagogy in
  `docs/guide/deriving-lifecycle-transitions.md` that EP-46 cross-links remains valid. EP-50
  also repointed the note EP-46 left there (which forward-referenced the EP-50 *plan*) to the
  now-shipped `docs/guide/mermaid-rendering.md`.

Discovered during EP-48 implementation (2026-05-21):

- **All six binary `Either` lifts were already exported from `Keiki.Composition`**, so the
  N-ary codec story needed no new export of primitives — the arity-3 injectors are pure
  point-free compositions of the shipped lifts, GHC inferring the `Either` nests from each
  helper's signature with no ambiguity and no new `unsafeCoerce`. The chosen deliverable is
  fixed-arity-3 wrappers + a documented general recipe (family *k* = `rightX^(k-1) . leftX`),
  not a type-indexed witness — recorded in the EP-48 Decision Log as more code for no semantic
  gain at the realistic arities.
- **The string-equality name-match obligation (shared with EP-47) stayed independent.** EP-48
  enforces `icName`/`wcName` cross-family uniqueness by contract + test (a colliding alphabet
  is caught by a `nub` check); EP-47 only *reasons about* the same `stepOne` site and does not
  change it. The two plans needed no coordination, as the Integration Points predicted.


## Decision Log

- Decision: Decompose into five work streams (EP-46 docs, EP-47 recompute-and-verify,
  EP-48 codec composition, EP-49 builder ergonomics, EP-50 Mermaid), in two phases.
  Rationale: by functional concern, minimal coupling, EP-47 isolated as the only change to
  the core invariant. The four no-dep streams parallelize as Phase 1; EP-47 is Phase 2.
  Date: 2026-05-21

- Decision: Accept Rei keiki #1 only as (a) documentation (EP-46) and (b) recompute-and-verify
  (EP-47). Reject the user-supplied backward-closure form and the recorder-edge/hand-written-apply
  form.
  Rationale: a backward closure is unverifiable (the library cannot certify
  `forward ∘ backward = id`), and a hand-written `apply` is the deliberately-rejected
  "Approach 3 / Direct MultiDecider" that surrenders the decisive technical win (mechanical
  `apply` derivation; synthesis note §1, masterplan-7). Recompute-and-verify preserves the
  guarantee — the command is still uniquely recovered from the invertible fields — while
  relaxing the over-strong "every field invertible" requirement.
  Date: 2026-05-21

- Decision: Accept Rei keiki #2 only as the N-ary event-family codec composition + singleton
  events (EP-48). Reject auto-derivation of positional multi-argument constructors.
  Rationale: the symbolic alphabet projects fields by name (`InCtor` slots are
  `(Symbol, Type)`); positional args have no names, and synthesizing them erodes the
  named-slot discipline the formalism rests on. The idiomatic single-record payload is
  documented in EP-46. The multi-family ask is design-aligned: it generalizes the existing
  `leftWireCtor`/`rightWireCtor`/`alternative` coproduct machinery.
  Date: 2026-05-21

- Decision: Reject Rei keiki #3 (variadic / `TApp3`+ apply); redirect via documentation
  (EP-46).
  Rationale: `TApp` carries an opaque function that is not SMT-translated (becomes a fresh
  `SBV.free`); higher arity buys no solver precision and encourages the anti-pattern the
  recent EP-41/43/44/45 work moved away from. The cited cases have structural answers:
  date bounds → `PCmp` over a curated ordered type; 3-way conditional → disjoint guarded
  edges; map-membership → the on-roadmap structural collection-content guards.
  Date: 2026-05-21
  REVISED 2026-05-21 after validation: the rejection stands but the ANCHOR was wrong. The
  date-bounds/map-membership GUARDS and 3-way conditional the source doc cited do not exist
  in Rei's ported code (Direction A dissolved them). The sole residual tuple-nesting is two
  `Map.insert` register UPDATES threading a (map, key, value) triple — never a guard,
  never >2 logical operations beyond the pair. The real (Low) ergonomic is collection-register
  update tuple-threading, which belongs to the collection-registers roadmap, not a `TApp`
  arity bump. EP-46 must re-anchor the #3 note on this, not on guards Rei never shipped.

- Decision: Accept Rei keiki #4 (both papercuts) as EP-49.
  Rationale: a `:=` synonym for `.=` is a trivial non-breaking alias resolving the
  documented `Control.Lens` collision; a `reg @"slot"` helper mirrors the existing
  write-side `slot @"name"` with ~3 lines over existing machinery.
  Date: 2026-05-21
  REVISED 2026-05-21 after validation: our parenthetical that Rei's read framing was "partly
  inaccurate" was WRONG. Rei reads via `proj (indexOf @…)` in 100% of cases (zero bare or
  annotated `#slot`) because `Rei.Prelude` re-exports generic-lens, whose `IsLabel` instance
  shadows keiki's `IsLabel s (Term rs ci r)`, making the bare-`#slot` read path unusable for
  any lens/generic-lens consumer. `reg @"slot"` is TypeApplication-based (no overloaded
  label), so it sidesteps the collision entirely — it is therefore ESSENTIAL, not just an
  annotation-saver. EP-49 must reflect this; the read papercut is the higher-value half.

- Decision: Accept Rei keiki #5 as EP-50 with the guard annotation reshaped to a structural
  summary (opt-in), plus the atlas entry point.
  Rationale: there is no pretty-printer for `HsPred`/`Term`/`Update` and the AST carries
  unprintable functions, so only a structural summary (written-slot names, guard-constructor/`Cmp`
  tag) is renderable; masterplan-10 already rejected the full-AST form. The default label
  format must stay guard-free to preserve the bug-spotting pedagogy in
  `docs/guide/deriving-lifecycle-transitions.md`.
  Date: 2026-05-21

- Decision: Keep the whole initiative keiki-only; exclude keiro/kiroku findings and the
  cross-cutting release/cookbook suggestions from the source document.
  Rationale: the user scoped the evaluation to keiki requests.
  Date: 2026-05-21

- Decision: Validate the evaluation against the consumer (Rei) and the runtime (keiro)
  before committing to implementation; keep all five plans, with the corrections recorded
  above (#3 re-anchored, #4 reframed, #1 strengthened) and no change to EP-48/EP-50.
  Rationale: Rei reaches keiki through keiro, so the constraints could have lived at the
  runtime layer. Validation against live source confirmed the #1 attribution is keiki's
  (keiro stores only events and has no forward event-fold), confirmed #2/#4/#5/#6 against
  Rei's real code, and corrected #3 (the cited guards do not exist in Rei's ported code).
  EP-48 (codec composition) and EP-50 (Mermaid) were confirmed exactly as written.
  Date: 2026-05-21

- Decision: Add a generic-lens interop guide to EP-49 (folded into its M3 docs milestone)
  establishing, for NEW projects, the principle of not importing `Data.Generics.Labels ()`
  globally (e.g. not re-exporting it from a shared prelude) so keiki's
  `IsLabel s (Term rs ci r)` instance is not shadowed and bare `#slot` register reads work.
  Rationale: this is the root cause of the #4 read papercut (a global generic-lens labels
  import shadows keiki's overloaded-label instance, forcing the verbose `proj (indexOf @…)`
  form). The guide is the guiding principle for new projects ONLY; it does NOT ask existing
  projects to refactor — the `reg @"slot"` and `:=` helpers remain the no-refactor path for
  projects (like Rei) already committed to a global generic-lens import. The two are
  complementary. EP-49's milestone count stays at 3 (the guide is part of M3).
  Date: 2026-05-21

- Decision: Make EP-47's M1 an explicit feedback-and-ratification gate. The prototype and
  analysis are still built, but the plan STOPS after M1 and requires an explicit maintainer
  go/no-go before any `solveOutput` change (M2–M4). A no-go is a legitimate outcome: #1 then
  remains docs-only, carried by EP-46.
  Rationale: the maintainer is not yet comfortable committing to relaxing `solveOutput` — it
  is the only change in the initiative that touches keiki's foundational invariant. Gating it
  behind a prototype-plus-analysis review de-risks the one irreversible-in-spirit decision
  while still producing the evidence needed to decide.
  Date: 2026-05-21


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion. Compare
the result against the original vision.

**Outcome (2026-05-21): all five plans Complete; the initiative met its vision.** Every
keiki-only finding from the Rei migration was addressed faithfully, and keiki's foundational
output-invertibility invariant was preserved (and, for EP-47, deliberately relaxed only with a
maintainer-ratified, proof-backed change).

- **EP-46 (docs)** — `docs/guide/output-invertibility.md` now states the contract, the recipes,
  and the (a)–(e) modeling redirects; cross-linked from four guides. Shipped value on day one
  and became the page EP-47 later amended.
- **EP-49 (builder ergonomics)** — `=:` (the `:=` the request named is impossible — colon
  operators are constructors in Haskell) and `reg @"slot"`, dogfooded in jitsurei; plus the
  generic-lens import-scoping guide.
- **EP-50 (Mermaid)** — `toMermaidAtlas` and the opt-in `toMermaidWith`/`MermaidOptions`
  structural edge summary, with the default kept byte-identical (guard-free) and actively
  verified; new `docs/guide/mermaid-rendering.md`.
- **EP-48 (codec composition)** — arity-3 N-ary coproduct injectors composed from the existing
  binary lifts + singleton-event support (`mkWireCtor0`); name-uniqueness obligation tested.
- **EP-47 (recompute-and-verify)** — the keystone. The M1 ratification gate produced a research
  note + prototype + analysis; the maintainer approved GO; M2–M4 relaxed `solveOutput` so
  *redundant* derived output fields round-trip via recompute-and-verify while a hidden input
  still fails at build time. "The event determines the command, certified at build time" is
  preserved.

**Phasing held:** Phase 1 (EP-46/48/49/50) shipped independently; Phase 2 (EP-47) followed
behind its gate. The two soft dependencies played out as designed (EP-46↔EP-47 share the
contract page — EP-46 created it, EP-47 amended it; EP-46↔EP-50 share the guard-free default —
preserved and golden-pinned). No hard dependency ever blocked progress.

**Lessons (each recorded in the relevant plan):**
- The plans were design-accurate but three concrete details only surfaced on contact with the
  compiler/types, and the per-plan gates/tests caught them: `:=` is impossible (EP-49);
  `Edge.update` can't be used as a record selector due to its existential write-set (EP-50);
  and — most importantly — the M1 gate's value: EP-47's `Eq` mechanism flipped from field-level
  to whole-event `Eq co`, and then the whole-event `evalOut` form was found (in M2, by the
  existing suite) to over-verify `TReg` audit fields, requiring the final derived-only-recompute
  design. Ratification gates and a real regression suite earned their keep.
- Every change stayed additive: no existing fixture's behavior changed, the all-invertible
  `solveOutput` fast path is byte-identical, and `cabal test all` is green
  (keiki-test 266, jitsurei 96, codec 40+7).


## Revision Notes

- 2026-05-21 — Validated the evaluation against the consumer (Rei,
  `../rei-project/rei.keiro-migration`) and the runtime (keiro, `../keiro`) at the user's
  request, since Rei uses keiki *through* keiro and the hydration constraint could have lived
  at the runtime layer. Outcome: the #1 attribution is confirmed keiki's (keiro stores only
  events and exposes no forward event-fold; `HydrationReplayFailed` merely surfaces keiki's
  `Nothing`). Recorded the per-request validation findings in Surprises & Discoveries.
  Corrected two Decision Log entries: #3's rejection stands but is re-anchored on
  collection-register update tuple-threading (the cited guards do not exist in Rei's ported
  code), and #4 is reframed (the verbose `proj (indexOf @…)` form is forced by a generic-lens
  `IsLabel` collision, so `reg @"slot"` is essential, not just convenient; the #1 trigger is
  also harsher than stated — one non-invertible field poisons the whole edge). EP-46, EP-47,
  and EP-49 were updated to reflect these corrections; EP-48 and EP-50 were confirmed
  unchanged.

- 2026-05-21 — Extended EP-49's M3 (documentation) with a generic-lens interop guide
  (`docs/guide/generic-lens-and-label-reads.md`) that, for NEW projects, recommends against a
  global `import Data.Generics.Labels ()` so keiki's overloaded-label register reads (`#slot`)
  are not shadowed. Per the user's direction, this is a guiding principle for new projects
  only and does NOT change the plan to offer the `reg @"slot"` / `:=` helpers, which remain
  the no-refactor path for existing generic-lens consumers. Recorded as a Decision Log entry;
  EP-49 milestone count unchanged (3).

- 2026-05-21 — Tidied the EP-46 M3 Progress seed line to match the validated #3 re-anchor
  (general structural-guard guidance + the note that Rei's real residual is collection-register
  *update* tuple-threading, not guards). Reframed EP-47's M1 as a hard feedback-and-ratification
  gate at the maintainer's request: the prototype/analysis are still produced, but the plan
  stops for an explicit go/no-go before any `solveOutput` change, with "keep #1 docs-only" as a
  legitimate no-go outcome. Updated EP-47's Progress line, the Dependency Graph phasing note,
  and added a Decision Log entry; the change is also reflected in `docs/plans/47-...`.
