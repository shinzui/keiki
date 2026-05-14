---
id: 36
slug: regfile-json-codec-and-shape-hash-for-snapshot-persistence
title: "RegFile JSON codec and shape hash for snapshot persistence"
kind: exec-plan
created_at: 2026-05-09T13:56:24Z
intention: "intention_01kr96br7gec191n9gqbmhvt42"
master_plan: "docs/masterplans/11-keiki-codec-json-package-implementation-and-rollout.md"
---

# RegFile JSON codec and shape hash for snapshot persistence

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

`RegFile (rs :: [Slot])` is keiki's typed heterogeneous tuple of `(Symbol, Type)` slots
and is half of every `SymTransducer phi rs s ci co`'s joint state `(s, RegFile rs)`.
Workflow concerns live there: timers, retry counters, correlation context, child-workflow
handles, awakeable handles, journaled step results.

keiki today exposes **zero** serialization machinery for `RegFile`. The keiki-side
architectural anchor at `docs/research/effects-boundary.md` lines 72–73 records this
as deliberate — "Serialization. JSON / CBOR / Protobuf to and from on-the-wire
bytes. The pure layer talks only typed Haskell values." — and the consumer-side
survey at `keiro/docs/research/02-keiki-decide-loop.md` §"Effectful Story"
reiterates the same stance from the integrator's perspective ("no built-in JSON
or binary"). `Keiki.Generics` provides only the structural pieces (`GRecord`,
`appendRegFile`, `splitRegFile`, `EmptyRegFile`, `KnownSlotNames`) — not
encode/decode, not a shape hash.

The keiki research at `docs/research/schema-evolution.md` lines 19–22 already pre-commits
the policy:

> Snapshots carry a register-file shape hash; mismatched hashes invalidate the snapshot
> and force a replay from the start.

**This ExecPlan executes on that documented commitment.** It is not introducing new
policy; it is shipping the primitive a documented policy depends on.

After this plan completes:

- A new module `Keiki.Shape` in the existing `keiki` package exposes a
  `KnownRegFileShape rs` class with a `regFileShapeHash :: Proxy rs -> Text` derivation
  and a `CanonicalTypeName` escape hatch. The hash is byte-equal across every supported
  GHC version, across rebuilds, across cabal dependency-tree changes, by construction.
- A new sibling cabal package `keiki-codec-json` exposes `Keiki.Codec.JSON` with a
  `RegFileToJSON rs` class providing strict encoder/decoder over `Aeson.Value`,
  plus an opt-in streaming encoder over `Aeson.Encoding` for users with large slot
  values (see §10 for representative cases).
- The user-visible win: a downstream library (specifically keiro, see Context) can build
  a `StateCodec (s, RegFile rs)` for snapshots that survives both schema changes (via the
  hash) and GHC upgrades (via the hash's stability guarantee), without hand-rolling a
  RegFile walker per aggregate.
- keiki adopts a multi-package layout for the first time. The existing codec-free
  commitment in `docs/research/effects-boundary.md` lines 72–73 (keiki-side anchor)
  and `keiro/docs/research/02-keiki-decide-loop.md` §"Effectful Story" (consumer-side
  reiteration) is honoured structurally: `keiki` itself never gains a dependency on
  `aeson`.

Consumers known today (only the first is in-tree; the others are documented in keiro's
research foundation):

1. **Snapshots** — keiro's `StateCodec (s, RegFile rs)` writes the joint state to a
   `keiro_snapshots` row; the row's `regfile_shape_hash` column uses §3 R3.
2. **Hydration audit / debugging** — operator dashboards inspect in-flight state via the
   browseable JSON.
3. **Future workflow journals** — keiro v2's durable execution journals step results
   inside `RegFile` slots; restart hydration deserializes them.


## Progress

- [ ] M0 — Decision pass and cabal-project shape decided. Spec read; `Decision Log`
      below carries the locked decisions; `cabal.project` updated to declare both
      packages; new package `keiki-codec-json/` directory created with empty cabal stub.
- [ ] M1 — `Keiki.Shape` lands in `keiki` with `CanonicalTypeName`, `KnownRegFileShape`,
      `regFileShapeHash`, `renderStableTypeRep`. SHA-256 dep added. Inductive instances
      and unit tests in place. `cabal test` passes.
- [ ] M2 — `keiki-codec-json` package compiles. `Keiki.Codec.JSON` exposes
      `RegFileToJSON` with strict encode/decode. Unit roundtrip tests pass.
- [ ] M3 — Property tests pass: roundtrip over QuickCheck-generated slot values
      (covering both `regFileToJSON` and `regFileToEncoding` paths), determinism
      (R9), sensitivity (P7.4). Golden hash file checked in.
- [ ] M4 — Performance baselines via `tasty-bench`. Benchmark fixtures derived from
      §10 cases A–D: condensed multi-party signing (Case A, ~100 KB), batch
      reconciliation (Case B, ~10 MB), ticket aggregate (Case C, ~500 KB), auction
      aggregate (Case D, ~2 MB). Reports encode-via-Value, encode-via-Encoding, and
      decode times per fixture; reports peak resident memory delta. Numbers checked
      in as a baseline; CI reports drift (does NOT block merges — the cross-GHC
      hash gate is the release blocker, not the bench).
- [ ] M5 — Cross-GHC CI gate active. The cross-GHC golden hash test (P7.2) runs against
      every entry in `tested-with`. A diff between rows is a release-blocking bug per
      the §8 procedure.
- [ ] M6 — Documentation: haddock on every public symbol (including the P11
      slot-value-size guidance on `RegFileToJSON` and §10-case pointers); a worked
      example in `docs/research/regfile-codec-design.md`; the keiki README's "no
      built-in JSON" passage updated to clarify that `keiki-codec-json` is a sibling
      package.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- 2026-05-13 — MP-11 (`docs/masterplans/11-keiki-codec-json-package-implementation-
  and-rollout.md`) deep-validation pass surfaced that this plan's "no built-in
  JSON or binary" citation pointed at `docs/research/02-keiki-decide-loop.md`,
  which does not exist in the keiki repository (it lives at
  `keiro/docs/research/02-keiki-decide-loop.md`). The keiki-side architectural
  anchor for the codec-free stance is `docs/research/effects-boundary.md` lines
  72–73 ("Serialization … The pure layer talks only typed Haskell values").
  All EP-36 citations of `02-keiki-decide-loop.md` were rewritten to either
  point at the keiro path explicitly (as a consumer-side reiteration) or at
  `effects-boundary.md` (as the keiki-side anchor). M6 acceptance was also
  rewritten so the doc update lands in `effects-boundary.md` (a file the keiki
  maintainer owns) rather than `02-keiki-decide-loop.md` (which lives in keiro
  and is the keiro maintainer's to update via the integration ExecPlan loop).
  Evidence: `find /Users/shinzui/Keikaku/bokuno/keiki -name '02-keiki-decide-
  loop*'` returns nothing; the file is at
  `/Users/shinzui/Keikaku/bokuno/keiro/docs/research/02-keiki-decide-loop.md`.


## Decision Log

- Decision: Implement the shape hash and `KnownRegFileShape` in the existing `keiki`
  package (new module `Keiki.Shape`); implement the JSON codec in a new sibling cabal
  package `keiki-codec-json` (new module `Keiki.Codec.JSON`).
  Rationale: Honours the codec-free commitment in
  `docs/research/effects-boundary.md` lines 72–73 (keiki-side anchor) and
  `keiro/docs/research/02-keiki-decide-loop.md` §"Effectful Story" (consumer-side
  reiteration) structurally — `keiki` itself never gains an `aeson` dependency.
  The shape hash has only `Typeable` + `text` + `bytestring`/SHA-256 deps and is
  structurally a property of `RegFile` types, so it belongs in core. Sets the
  multi-package precedent for keiki cleanly. Other splits (e.g., `keiki-symbolic`) land
  in their own ExecPlans.
  Date: 2026-05-09.

- Decision: The shape-hash type renderer uses **only** `tyConModule` and `tyConName`
  (with application via `Type.Reflection.splitApps`). Never `tyConPackage`. Never `Show
  TypeRep`. Never the raw `Fingerprint`.
  Rationale: `Fingerprint` includes the package id hash, which depends on the cabal
  dependency tree. Any cabal change to deps changes the fingerprint, which would silently
  invalidate every snapshot in production. `Show TypeRep` is documented as best-effort,
  not a stability commitment, so its format may shift across GHC releases. The
  `tyConModule + tyConName` accessors are the public, documented-stable surface of
  `Type.Reflection`. The choice is the load-bearing decision for cross-GHC stability —
  too important to leave to implementation discretion.
  Date: 2026-05-09.

- Decision: The cross-GHC golden hash test (§Validation P7.2) is **release-blocking**.
  Codified in §8. A diff between two rows of the GHC matrix in CI blocks merge and
  blocks release.
  Rationale: The whole point of this design is that GHC drift cannot occur silently. A
  non-blocking test gets ignored. If a legitimate GHC-side change requires a coordinated
  release, the maintainer follows the §8 procedure (file an upstream bug; ship a
  `CanonicalTypeName` migration path). The test's job is to *force* that conversation,
  not advise it.
  Date: 2026-05-09.

- Decision: The decoder is **strict**. Missing slots, type mismatches, **and unknown
  extra fields** all return `Left`.
  Rationale: Permissive defaults silently introduce state-shape drift; strict→permissive
  is recoverable in the consumer (catch `Left`, fall through), permissive→strict cannot
  be recovered without re-instrumenting every call site. The consumer (keiro) controls
  fallback policy.
  Date: 2026-05-09.

- Decision: The shape hash treats slot reordering as a breaking change (the hash flips).
  Rationale: Even though Symbol-keyed JSON makes order operationally irrelevant for the
  wire, slot order is part of the type's identity in Haskell, and consumers who rely on
  `Generic` walk order would silently break under an order-invariant hash. The cost of a
  full replay on a deliberate reorder is small; the cost of a silent state-shape drift
  is unbounded.
  Date: 2026-05-09.

- Decision: keiki ships `RegFileToJSON` only (Aeson). Other codec formats (CBOR,
  Protobuf) become parallel sibling packages (`keiki-codec-cbor`, etc.) if a real
  consumer asks.
  Rationale: Per keiro EP-2's "no parallel codec interface" stance, abstracting over
  codec format pre-emptively forces every slot type to have a codec-format-polymorphic
  encoding, which is far more invasive than n type classes. Defer the abstraction until
  there's a second concrete consumer.
  Date: 2026-05-09.

- Decision: Versioning is the consumer's job. keiki ships zero version metadata, zero
  upcasters, zero migration. The two-discriminant model (consumer-supplied
  `stateCodecVersion :: Int` + keiki-supplied `regFileShapeHash :: Text`) catches
  disjoint failure modes; the consumer wires both.
  Rationale: keiki has one source of truth for shape — the type. There is no "v2 of
  `RegFile rs`" because the slot list is the type. Codec evolution is downstream of this
  primitive, not part of it. See `docs/research/schema-evolution.md` for the full
  argument.
  Date: 2026-05-09.

- Decision: Promote the streaming encoder (`regFileToEncoding :: RegFile rs ->
  Aeson.Encoding`) from §9.B4 (future) to v1, as R10. The class gains a third method
  with a default implementation in terms of `regFileToJSON`; inductive instances
  override it to walk slots directly into `Aeson.Series`.
  Rationale: §10 case B (long-running batch reconciliation) shows that a 50,000-entry
  `processedItems` slot drives the `Aeson.Value` intermediate to ~10 MB JSON / 50–100
  MB of Haskell pointer overhead, with 130–300 ms encode latency per snapshot in the
  `runCommand` tail (P99 spike). Adding the streaming encoder post-hoc would force
  every affected user to migrate at the encode call site; shipping it as a
  default-method on the same class makes adoption a one-line swap. The default
  implementation keeps the migration cost zero for users who don't need it.
  Date: 2026-05-09.

- Decision: Add M4 — Performance baselines via `tasty-bench` against §10 reference
  fixtures. Bench is a tracked metric, NOT a release gate. The cross-GHC hash gate
  (M5, formerly M4) remains the release blocker.
  Rationale: Correctness ≠ performance; the existing P7 test discipline catches
  correctness drift but not perf regressions. A tracked bench surfaces regressions at
  PR review time without imposing the noisy-bench problem on release gating. The four
  fixtures (§10 A–D) cover the realistic shape space (low-rate, batch, hydration-cost,
  high-write-rate); condensing them to ~30 seconds of CI keeps the gate cheap.
  Date: 2026-05-09.


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

The reader is assumed to know nothing about keiki's internals. The full picture:

### keiki's `RegFile` in 30 seconds

Defined at `src/Keiki/Core.hs:126-129`:

    data RegFile (rs :: [Slot]) where
      RNil  :: RegFile '[]
      RCons :: KnownSymbol s
            => Proxy s -> r -> RegFile rs -> RegFile ('(s, r) ': rs)

Where `Slot = (Symbol, Type)` (`Keiki.Core` line 113). The slot value is intentionally
lazy so `emptyRegFile` (`Keiki.Generics`) can seed each slot with a deferred
`error "uninit:<slot>"` thunk — uninitialized reads fail loudly. Strictness for *written*
slots is enforced on the write path (`setSlotN`) per EP-23's rationale.

Existing helpers:

- `Keiki.Core.KnownSlotNames` (lines 249–257) — runtime recovery of slot names. Already
  inductive over the slot list; this plan reuses the same shape.
- `Keiki.Generics.GRecord` (lines 53–87) — walks `GHC.Generics.Rep` to/from `RegFile`.
  Composes with the new code via the slot-list type family `RegFieldsOf`.
- `Keiki.Generics.EmptyRegFile` (lines 296–307) — derives the all-uninit register file.

`Type.Reflection` (from `base`) is already in keiki's vocabulary at `Keiki.Symbolic`
(see `discoverSym :: Typeable r => Maybe (SymDict r)`, line 156), so the new module's
use of `someTypeRep`, `splitApps`, `tyConModule`, `tyConName` does not introduce a
foreign primitive — it extends an existing pattern.

### The downstream consumer (out of tree)

The keiro framework at `/Users/shinzui/Keikaku/bokuno/keiro` is the consumer driving
this work. Specifically:

- `keiro/docs/research/09-snapshot-strategy.md` §3 declares
  `StateCodec (s, RegFile rs)` and §6 declares the `keiro_snapshots` table with two
  discriminator columns: `state_codec_version :: Int` (consumer-managed) and
  `regfile_shape_hash :: Text` (keiki-managed via this plan's R3).
- `keiro/docs/research/11-upstream-roadmap.md` §7.1 (`keiki: Register-file <-> Aeson.Value
  helper`) and §7.2 (`keiki: Register-file shape hash`) catalogue the request from
  three customers (keiro EP-1, EP-2, EP-4).
- `keiro/docs/research/10-workflow-roadmap.md` §3 sketches the v2 durable-execution
  journal that will reuse the same primitive for journaled step results.

The consumer is design-only at the time this plan is authored; no Haskell consumer code
exists yet. Every milestone in this plan (M0 through M6) is acceptable independently of
the consumer being live — fixtures and tests are self-contained.

### Why this plan now

- The keiro research-foundation MasterPlan closed on 2026-05-06
  (`keiro/docs/masterplans/1-keiro-research-foundation.md` §"Outcomes & Retrospective").
  Its consolidated upstream backlog (`11-upstream-roadmap.md`) ranks the keiki
  register-file helper plus shape hash as **Wanted, Blocking for keiro EP-4** with three
  customers; landing both in one keiki PR is the natural shape (§7.2 *Suggested
  sequencing*: "Block 2. Lands together with §7.1.").
- `docs/research/schema-evolution.md` already commits keiki to "snapshots carry a
  register-file shape hash" as policy (line 20). Today the policy is unimplemented; this
  plan ships it.


## Design Specification

The complete spec, decision-locked. Sections numbered to allow cross-references from
later living-doc entries.

### §3 Functional requirements

**R1 — Encoder.** `regFileToJSON :: RegFile rs -> Aeson.Value`, derivable from a
`RegFileToJSON rs` class with default instances over the slot list. Output is a JSON
object keyed by each slot's `Symbol`, e.g. `{"cooldownUntil": "2026-05-09T12:00:00Z",
"retryCount": 3}`.

**R2 — Decoder, strict.** `regFileFromJSON :: Aeson.Value -> Either String (RegFile rs)`.
Total. Returns `Left` with a slot-named error on any of: missing slot, type-mismatched
slot, malformed JSON, **unknown extra field** (locked strict; see Decision Log).

**R3 — Shape hash.** `regFileShapeHash :: forall rs. KnownRegFileShape rs => Proxy rs ->
Text`. Produces `sha256Hex` (lower-case hex) over the byte-concatenation of, for each
slot in slot-list order:

    <slotSymbol> ":" <renderStableTypeRep tr> ";"

Where `renderStableTypeRep :: SomeTypeRep -> Text` walks the `TypeRep` structure using
**only** `tyConModule`, `tyConName`, and application via `Type.Reflection.splitApps`.
**Never** `tyConPackage`. **Never** `Show TypeRep`. **Never** the raw `Fingerprint`.
Pure, no `IO`.

**R4 — Cross-version stability.** The hash MUST be byte-equal across every GHC version
in `tested-with`, across rebuilds on different machines, across cabal dependency-tree
changes that do not rename or relocate the slot types' modules. Verified in CI by P7.2,
which is release-blocking.

**R5 — Hash sensitivity.** The hash MUST change when any of these change: slot rename
(Symbol), slot addition, slot removal, slot reordering, slot type's module, slot type's
type-name, slot type's applied type arguments. The hash MUST NOT change when any of
these change: a slot type's typeclass instances, a slot type's source-level
documentation, the cabal dependency tree (transitive bumps without module relocations),
GHC patch/minor/major version (within `tested-with`).

**R6 — Composition with `Keiki.Generics`.** A user who derives `mkInCtor` for an input
constructor today must be able to derive `RegFileToJSON` for the same record with the
same `deriving via` or TH experience. The internal walk reuses `GRecord` and
`KnownSlotNames` — no parallel `Generic` traversal.

**R7 — Empty register file behaviour.** Encoding a slot whose value is the
`error "uninit:<slot>"` sentinel from `Keiki/Core.hs:120-125` MUST throw with the same
`uninit:` error. The encoder is total only on register files all of whose slots have
been written through `applyEvent`. Documented; consumer responsibility.

**R8 — Package layout.** Shape hash + `KnownRegFileShape` ship in `keiki` (existing
package), in a new module `Keiki.Shape`. Codec ships in a **new sibling package
`keiki-codec-json`**, in module `Keiki.Codec.JSON`, depending on `keiki ^>= …` and
`aeson`. The `keiki` cabal **MUST NOT** gain a dependency on `aeson`.

**R9 — Encoding determinism.** Two structurally-equal `RegFile rs` values MUST produce
byte-equal `Aeson.Value` outputs. The encoder emits object keys in slot-list order
(deterministic by the type-level walk). Verified by property test.

**R10 — Streaming encoder.** `RegFileToJSON` carries a third method
`regFileToEncoding :: RegFile rs -> Aeson.Encoding` with a default implementation in
terms of `regFileToJSON` (`Aeson.toEncoding . regFileToJSON`). Inductive instances MAY
override it to walk the slot list directly into an `Aeson.Series` and avoid the
`Aeson.Value` intermediate, eliminating the O(output-size) intermediate allocation that
is load-bearing for the §10 reference cases. Users with large slot values (see §10 case
B) call `Aeson.encodingToLazyByteString . regFileToEncoding` instead of
`Aeson.encode . regFileToJSON`. The streaming encoder MUST produce a byte string that,
when re-parsed via `regFileFromJSON . fromJust . Aeson.decode`, round-trips to an equal
`RegFile`. Property-tested at M3.

### §4 Schema-evolution use cases

These are the categories of change a real keiki user will hit. The defining design move
is that **keiki ships a *detection* primitive (the hash) and a *current-shape* codec; it
does not ship migration. Migration is the consumer's responsibility.**

| #  | Category                                  | Example                                                     | Hash flips?           | Wire compatible?                | Consumer action                              |
|----|-------------------------------------------|-------------------------------------------------------------|-----------------------|---------------------------------|----------------------------------------------|
| 1  | Add slot                                  | `'[ '("retryCount",Int) ]` → … add `'("correlationId",Text)`| Yes                   | No (decoder fails: missing)     | Fall through to full replay                  |
| 2  | Remove slot                               | reverse of 1                                                | Yes                   | No (decoder fails: unknown)     | Full replay                                  |
| 3  | Rename slot                               | `"cooldownUntil"` → `"retryAfter"`                          | Yes                   | No                              | Full replay                                  |
| 4  | Reorder slots                             | swap two slots                                              | Yes                   | Wire-OK but hash flips          | Full replay (locked: §5 P10)                 |
| 5  | Slot type change, same JSON               | `Int` → `Word32`                                            | Yes (TypeRep differs) | Wire-OK but hash flips          | Full replay; the case where the hash earns its keep |
| 6  | Newtype wrap                              | `Text` → `newtype OrderId = OrderId Text deriving newtype ToJSON` | Yes             | Wire-OK                         | Full replay                                  |
| 7  | Replace primitive with record             | `Text` → `Address`                                          | Yes                   | No                              | Full replay                                  |
| 8  | Split slot                                | `addressLine :: Text` → `houseNumber + street`              | Yes                   | No                              | Full replay                                  |
| 9  | Slot type's internal record changes       | `Address` adds `country` field                              | Maybe (TypeRep)       | Yes/no depending                | Consumer bumps `stateCodecVersion`           |
| 10 | Slot type's `ToJSON` instance changes     | `Address` switches object→array encoding                    | **No**                | No                              | **Hash misses this.** Consumer MUST bump `stateCodecVersion` |
| 11 | Semantic-only change                      | `timestamp` once meant "scheduled at", now "fired at"       | No                    | Yes                             | **Hash misses this.** Consumer bumps `stateCodecVersion` |
| 12 | Tightened invariant                       | `retryCount :: Int` was unconstrained, now ≥ 0              | No                    | Yes                             | Application migration; out of scope          |

**Key observations:**

- The hash catches **structural** changes (#1–9). It cannot catch wire-format changes
  inside a slot type (#10) or semantic changes that don't move bytes (#11–12).
- The two-discriminant design (`stateCodecVersion :: Int` from the consumer +
  `regFileShapeHash :: Text` from keiki) **catches disjoint failure modes**. Either
  alone is insufficient; together they are robust.
- For #10–12 the consumer's `stateCodecVersion` bump is mandatory; the keiki helper
  plays no role.

### §5 Design principles (anti-fragility)

**P1** Two discriminants, disjoint duties. Document the disjointness in haddock.

**P2** Strict decoder. Locked.

**P3** Aeson, not abstract codec. CBOR/Protobuf become parallel sibling packages if
needed.

**P4** Versioning is the consumer's job. keiki helpers are pure functions of the current
type.

**P5** Hash uses only stable accessors: `tyConModule + tyConName + splitApps`. Locked.

**P6** Default instances, not orphans.

**P7** Test discipline, four categories (see Validation).

**P8** Compose with existing machinery (`GRecord`, `KnownSlotNames`, `RegFieldsOf`).

**P9** `CanonicalTypeName` escape hatch. Users with stability concerns override:

    class CanonicalTypeName a where
      canonicalTypeName :: Proxy a -> Text
      default canonicalTypeName :: Typeable a => Proxy a -> Text
      canonicalTypeName _ = renderStableTypeRep (someTypeRep (Proxy @a))

The hash uses `canonicalTypeName`, not `Typeable` directly. Long-term answer to "GHC
removed/renamed `tyConModule`": pinned users are unaffected.

**P10** Slot order is part of identity. Reordering flips the hash.

**P11** Slot-value-size budget is the user's responsibility, not keiki's. keiki's
per-slot encode/decode overhead is microseconds at any realistic slot count (<1000).
The actual cost is dominated by the slot type's `ToJSON`/`FromJSON` and is bounded only
by the user's data. The §10 reference cases exhibit RegFiles of 50 KB to 10 MB encoded;
keiki's primitives serve all of them, but users carrying multi-megabyte slot values
should:

1. Use `regFileToEncoding` (R10) instead of `regFileToJSON` to avoid the
   O(output-size) intermediate `Aeson.Value` allocation.
2. Consider whether the bulk slot belongs in the RegFile at all — for some workloads,
   splitting the bulk data into a separate kiroku stream and projecting it via
   subscriptions is structurally cleaner than carrying it in the workflow's RegFile.

This is documented in haddock on the `RegFileToJSON` class so users hit the guidance at
the API surface, not just in this plan.

### §6 Risks & open questions

- **Risk: `tyConModule` / `tyConName` API drift across major GHC versions.** Stable
  historically; not covenanted forever. Mitigation: P7.2 catches drift on bump; P9 gives
  per-user resilience; §8 makes the bump deliberate.
- **Risk: `error "uninit:…"` in unwritten slots.** Encoding throws (R7).
- **Locked: no `__shape__` field embedded in the JSON.** Couples wire format to hash
  algorithm; consumers attach the hash externally.
- **Deferred: partial-RegFile encoder.** v1 ships strict. If a real use case appears,
  add `regFileToJSONPartial :: RegFile rs -> Aeson.Value` that omits unwritten slots.
- **Locked: cabal package name `keiki-codec-json`.** Parallels future
  `keiki-codec-cbor`. Reject `keiki-json` (doesn't generalise) and `keiki-aeson` (leaks
  impl library).

### §7 Interface sketch

    -- New module in `keiki`: Keiki.Shape

    class CanonicalTypeName a where
      canonicalTypeName :: Proxy a -> Text
      default canonicalTypeName :: Typeable a => Proxy a -> Text
      canonicalTypeName _ = renderStableTypeRep (someTypeRep (Proxy @a))

    class KnownRegFileShape (rs :: [Slot]) where
      regFileShapeHash :: Proxy rs -> Text

    instance KnownRegFileShape '[] where
      regFileShapeHash _ = sha256Hex "regfile:0"

    instance ( KnownSymbol s, CanonicalTypeName t, KnownRegFileShape rs
             ) => KnownRegFileShape ('(s, t) ': rs) where
      regFileShapeHash _ =
        sha256Hex $ Text.concat
          [ Text.pack (symbolVal (Proxy @s)), ":"
          , canonicalTypeName (Proxy @t), ";"
          , regFileShapeHash (Proxy @rs)
          ]

    renderStableTypeRep :: SomeTypeRep -> Text
    -- Walks splitApps; per TyCon emits `<tyConModule>.<tyConName>`.
    -- Never tyConPackage. Never Show. Never Fingerprint.

    -- New package keiki-codec-json, module Keiki.Codec.JSON

    class RegFileToJSON (rs :: [Slot]) where
      regFileToJSON     :: RegFile rs -> Aeson.Value
      regFileFromJSON   :: Aeson.Value -> Either String (RegFile rs)
      regFileToEncoding :: RegFile rs -> Aeson.Encoding
      -- Default: Aeson.toEncoding . regFileToJSON.
      -- Inductive instances may override to walk slots directly into
      -- Aeson.Series, avoiding the Aeson.Value intermediate.
      -- See R10 and §10 case B.
      regFileToEncoding = Aeson.toEncoding . regFileToJSON

    -- Inductive instances over '[] and (s,t) ': rs.
    -- The (s,t) ': rs instance overrides regFileToEncoding to use
    -- Aeson.pairs (key .= value <> recurse) so the streaming path is
    -- O(1) intermediate memory.

### §8 GHC upgrade procedure (release-blocking)

When bumping `tested-with`:

1. Add the new GHC to CI.
2. Run the cross-GHC golden hash test (P7.2).
3. **If it fails: stop. Block the release.** Either the new GHC changed `tyConModule` /
   `tyConName` semantics — file an upstream bug AND ship a `CanonicalTypeName` migration
   path for affected users — or `renderStableTypeRep` has an unintentional dependency
   on a non-stable accessor (fix our code).
4. Update `tested-with` in the cabal.
5. Add a release note explicitly flagging GHC X.Y.Z as validated against the golden
   hash.

The cross-GHC golden hash test is a **release-blocking gate**, not a guideline. The
whole point of the design is that drift cannot occur silently; treating the test as
advisory defeats the design.

### §9 Future requirements catalog

This section enforces the discipline that **no future requirement forces redesign of
v1's primitives**. Extensions are additive; never reshapings. If during implementation
an unanticipated requirement does force breaking one of the v1 contracts, **stop and
revisit the spec** rather than silently bending v1.

#### §9.A Future consumers (known)

| #  | Future consumer                                      | Source                                                 | v1 design serves it?       |
|----|------------------------------------------------------|--------------------------------------------------------|----------------------------|
| A1 | keiro snapshots                                      | `keiro/docs/research/09-snapshot-strategy.md` §3       | Direct                     |
| A2 | keiro debugging / ops inspection                     | keiro EP-1 §14                                         | Direct                     |
| A3 | keiro v2 workflow journals (durable execution)       | `keiro/docs/research/10-workflow-roadmap.md` §3        | Direct                     |
| A4 | keiro v2 awakeable callbacks                         | `keiro/docs/research/10-workflow-roadmap.md` §6        | Direct                     |
| A5 | Process-manager state observability                  | keiro EP-3 §5                                          | Direct                     |
| A6 | Multi-region replication (snapshot crossing regions) | implicit                                               | Direct via R9              |
| A7 | Cross-language readers (non-Haskell process)         | implicit                                               | Direct, with caveat (slot types using Haskell-idiomatic encodings are user responsibility) |

#### §9.B Future codec needs

| #  | Future need                                | v1 path                                                                                         |
|----|--------------------------------------------|-------------------------------------------------------------------------------------------------|
| B1 | CBOR codec                                 | New sibling package `keiki-codec-cbor`. Same shape hash applies.                                |
| B2 | Protobuf codec                             | Same shape — `keiki-codec-protobuf` if ever needed.                                             |
| B3 | Field-level encryption / PII redaction     | Per-slot user-supplied transform. Out of scope for v1; design doesn't preclude.                 |
| B4 | Streaming encoder (`Encoding`-based)       | **Shipped in v1 via R10** as `regFileToEncoding :: RegFile rs -> Aeson.Encoding`. Promoted from future to v1 after §10 case B's batch-reconciliation analysis showed the `Aeson.Value` intermediate is load-bearing at production scale. Default implementation in terms of `regFileToJSON` keeps the migration cost zero for users who don't need it. |

#### §9.C Future hash needs

| #  | Future need                                | v1 path                                                                                                                                |
|----|--------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------|
| C1 | Per-slot canonical name override           | Already in v1 via P9 (`CanonicalTypeName`).                                                                                            |
| C2 | Slot-order-invariant hash                  | Future opt-in: `regFileShapeHashUnordered :: Proxy rs -> Text` sorts slots by Symbol before hashing. Additive.                         |
| C3 | Hash of a subset of slots                  | Future opt-in. v1 design unaffected.                                                                                                   |
| C4 | Hash that survives slot type's `ToJSON` change | **Cannot exist by design.** Hash is over type, not encoding. Use case #10 in §4 is what `stateCodecVersion` exists for. Document firmly. |

#### §9.D Future RegFile-shape needs

| #  | Future need                                          | v1 path                                                                                                              |
|----|------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------|
| D1 | Slot-name metadata for tooling                       | Already in keiki via `KnownSlotNames`.                                                                               |
| D2 | Slot-type metadata (rendered type per slot)          | Future additive method on `KnownRegFileShape`: `regFileShapeDescriptors :: Proxy rs -> [(Text, Text)]`. Same class.  |
| D3 | Lifting `(s, RegFile rs)` joint codec into keiki     | Defer. Two halves have different shapes; consumers concatenate in 3 lines.                                           |
| D4 | RegFile diff for incident response                   | Future tool downstream of v1. R9 (deterministic encoding) makes byte-level diff possible immediately.                |

#### §9.E Future symbolic-verification needs (z3 layer)

| #  | Future need                                           | v1 path                                                                                                                                  |
|----|-------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------|
| E1 | z3 verifies a property; persisted state must satisfy  | Indirect. z3 sees `Sym a`/`SymRep a`; codec sees `ToJSON a`/`FromJSON a`. Independent. Decoder type-correctness gives consistency. **No v1 design action.** |
| E2 | Encoded JSON readable by z3 directly                  | Out of scope. z3 reads symbolic constraints, not JSON.                                                                                   |

#### §9.F Operational needs

| #  | Future need                              | v1 path                                                                                  |
|----|------------------------------------------|------------------------------------------------------------------------------------------|
| F1 | Determinism of byte-level encoding       | Locked in R9. Verified by property test.                                                 |
| F2 | Performance benchmarks for large RegFiles| **Shipped in v1 via M4** (`tasty-bench` baseline against §10 reference fixtures). CI runs as a tracked metric, not a gate. Catches regressions; does not block merges. |
| F3 | Migration tooling (rewrite old snapshots)| **Explicitly out of keiki scope.** Application or third-party tool. v1 doesn't preclude. |


### §10 Large-RegFile reference cases

This section documents the realistic scenarios where a `RegFile rs` becomes large
enough that performance discipline matters. They are the fixtures the M4 benchmark
suite exercises, and they are the cases the R10 streaming encoder and the P11
slot-value-size guidance exist to serve. They are also durable design context: future
ExecPlans (CBOR codec, streaming-decoder, sharded snapshots, etc.) should reference these
cases when arguing about scaling.

**Note on what "large" means.** A `RegFile`'s size has two independent dimensions:

- **Slot count** — the type-level slot list's length. Bounded by what a developer
  declares at compile time. Realistic ceiling: 50 slots for a complex aggregate;
  20–30 for a workflow. **keiki's per-slot dispatch overhead is microseconds at any
  realistic slot count**, so this dimension does not drive performance.
- **Slot value size** — the size of the values held in slots. Unbounded by design.
  When this dimension is large, performance is dominated by the slot type's
  `ToJSON`/`FromJSON` implementation. **The user owns this cost.** keiki's role is to
  not amplify it (R10 streaming encoder) and to surface the constraint to users
  (P11 haddock guidance).

The four cases below cover the realistic shapes; the M4 benchmark suite uses
condensed variants of each.

#### Case A — Multi-party contract signing workflow

A workflow coordinating signature collection from multiple parties. Each party's
status, signature, and audit trail live in the workflow's RegFile.

    rs ~ '[ '("partiesInvited",     Map PartyId InviteStatus)
          , '("signaturesReceived", Map PartyId Signature)
          , '("documentVersions",   [DocumentVersion])
          , '("auditLog",           Vector AuditEntry)
          , '("currentPhase",       Phase)
          , '("expiresAt",          UTCTime)
          , '("awakeables",         Map AwakeableId AwakeableHandle)
          ]

| Quantity                            | Value at peak     |
|-------------------------------------|-------------------|
| Parties                             | 20                |
| Document versions                   | 5–10              |
| Audit log entries                   | 100–200           |
| Total RegFile encoded               | 50–500 KB         |
| Slot count                          | 7                 |

*Performance characteristics.* Encode path: `signaturesReceived` and `auditLog` are the
two slots with non-trivial size. Aeson encodes a 200-entry `Vector` of small records in
~5–10 ms. Snapshot rate is low (signatures arrive over hours/days), so encode time is
not in any hot path. **No streaming-encoder need.** Hash is straightforward.

*Why this case matters.* It's the modal case for keiro v2 workflows: bounded
concurrency, multi-day duration, moderate state. The benchmark fixture exercises it as
a sanity baseline ("does the simple case stay fast?").

#### Case B — Long-running batch reconciliation workflow

A nightly workflow processing a daily batch with intra-day partial-progress
resumability. The reference scenario for the streaming-encoder requirement.

    rs ~ '[ '("batchId",          BatchId)
          , '("inputCursor",      Cursor)
          , '("processedItems",   Map ItemId ProcessingResult)  -- the big one
          , '("failedItems",      [(ItemId, ProcessingError)])
          , '("retryAttempts",    Map ItemId Int)
          , '("metrics",          BatchMetrics)
          , '("awakeables",       Map ChildJobId AwakeableHandle)
          , '("phase",            Phase)
          , '("expiresAt",        UTCTime)
          ]

| Quantity                            | Value at peak     |
|-------------------------------------|-------------------|
| `processedItems` entries            | 50,000            |
| `processedItems` entry size (JSON)  | ~200 B            |
| `processedItems` total              | ~10 MB JSON       |
| `failedItems`, `retryAttempts`      | ~500 each         |
| Other slots combined                | <50 KB            |
| **Whole RegFile encoded**           | **~10 MB JSON**   |
| Snapshot policy                     | every 100 events  |
| Events per second at peak           | ~10               |
| Snapshot writes per minute          | ~6                |
| Slot count                          | 9                 |

*Performance characteristics, three buckets.*

1. **Compile-time / dictionary cost.** Slot count 9 → 9-deep instance chain. Negligible.
2. **Hot-path encode/decode.** `processedItems` dominates. Aeson's `Value`-producing
   encoder runs at ~30–80 MB/s on Maps of small records; 10 MB → 130–300 ms per
   encode. **This sits in `runCommand`'s tail every 100th event.** With a 10
   events/sec workload, every ~10 seconds a command takes 200 ms longer than the
   others — a P99 spike, not an average problem. Decode on restart: ~200–400 ms for
   a 10 MB Map.
3. **Memory during encode.** The `Aeson.Value` intermediate for a 10 MB output
   allocates 50–100 MB of `KeyMap`/`Vector`/`Text` nodes (Haskell pointer overhead is
   severe on small payloads). Drives young-gen GC pressure visible as latency spikes
   uncorrelated with snapshot frequency.

*Mitigations applied in this v1 design:* R10 (`regFileToEncoding`) avoids the `Value`
intermediate, runs at 2–3× throughput with O(1) intermediate memory. P11 haddock
guidance directs users to it. M4 benchmarks measure both paths against this fixture.

*Why this case matters.* It's the case that **forces** the v1 streaming-encoder
decision. Without R10, hitting this scale post-deploy would mean either accepting
P99 latency spikes or migrating to a deeper rewrite. With R10, the migration is
swapping one function call.

#### Case C — Customer support ticket aggregate

An aggregate accumulating ticket history. Long-lived (months/years) but with
moderate per-ticket activity.

    rs ~ '[ '("comments",           [Comment])
          , '("attachments",        [AttachmentMetadata])
          , '("customFieldValues",  Map FieldName Value)
          , '("slaState",           SlaTracker)
          , '("escalationHistory",  [Escalation])
          , '("assigneeHistory",    [Assignment])
          , '("tags",               Set Tag)
          , '("priority",           Priority)
          , '("channel",            Channel)
          , '("language",           Language)
          ]

| Quantity                            | Value at peak     |
|-------------------------------------|-------------------|
| Comments                            | 100s              |
| Attachment metadata entries         | 10s               |
| Custom field values                 | 10s               |
| Total RegFile encoded               | 100s of KB        |
| Slot count                          | 10                |

*Performance characteristics.* Steady-state mid-range. Encode time scales with comment
list (100s of small records → ~5–20 ms). Snapshot rate is low (most tickets see <1
event per day in steady state); encode latency is not in a tight loop. **Streaming
encoder optional but recommended** if comment volume is unbounded by domain (e.g., bot
ticketing where automation appends notes).

*Why this case matters.* It's the long-lived-aggregate shape — different from Case B's
batched-workflow shape because the snapshot rate is low and the failure mode is
restart-time hydration cost rather than steady-state encode latency. Useful for
testing hydration performance specifically.

#### Case D — Real-time auction aggregate

A short-lived but high-activity aggregate. Bid history accumulates over hours; auction
ends and aggregate is sealed.

    rs ~ '[ '("bidHistory",       Vector Bid)
          , '("currentHigh",      Maybe Bid)
          , '("reservePrice",     Money)
          , '("endsAt",           UTCTime)
          , '("status",           AuctionStatus)
          , '("watchers",         Set UserId)
          ]

| Quantity                            | Value at peak     |
|-------------------------------------|-------------------|
| Bids over auction duration          | 1,000–10,000      |
| Bid record size                     | ~150 B            |
| Watchers                            | 100s–1,000s       |
| Total RegFile encoded               | 200 KB – 2 MB     |
| Slot count                          | 6                 |

*Performance characteristics.* High write rate (bids arrive at sub-second cadence near
auction close). Snapshot rate is whatever EP-4 policy commits to — at every-100-events,
that's a snapshot every ~100 seconds at 1 bid/sec, or every ~10 seconds at 10 bids/sec.
With a 2 MB encode at 50 MB/s, that's 40 ms per snapshot, in a hot path. **Streaming
encoder strongly recommended.**

*Why this case matters.* It's the high-write-rate shape. Cases A and C are
low-write-rate; Case B is bounded-rate. Case D is the one that pressures the snapshot
policy itself: aggressive snapshot frequency × a moderately large RegFile = continuous
encode load.

#### Cases not covered (but worth flagging in future)

These shapes were considered and excluded from the M4 benchmark fixture, but should
appear in any future performance ExecPlan:

- **Aggregate carrying a denormalized projection.** A user-account aggregate that holds
  a rolling 30-day activity log in a slot. Same shape as Case C but with a higher
  steady-state size. Mitigation pattern is structural (project to a separate stream),
  not a keiki-side concern.
- **Workflow with very high awakeable concurrency.** A fan-out workflow waiting for
  10,000 child callbacks simultaneously, each as a slot in `Map`. Slot count is still
  small (one slot holding a 10,000-entry `Map`); the value-size pressure is the same as
  Case B.
- **Process manager with cross-stream correlation tables.** A PM tracking
  `Map CorrelationId InFlightState` where the table has 100,000s of entries. Same
  value-size pressure as Case B; structural advice (split into a separate stream) is
  the same.

In all three, the keiki primitive serves the case correctly; the user's structural
choices determine whether the size is reasonable.


## Plan of Work

Seven milestones, each independently verifiable.

### M0 — Cabal-project scaffolding

Convert keiki's repository from a single-package layout to a multi-package layout. The
existing `keiki` package's cabal stays where it is; a new sibling directory
`keiki-codec-json/` holds the new package's cabal. A new `cabal.project` at the
repository root declares both packages.

What exists at the end:
- `cabal.project` lists `keiki/keiki.cabal` and `keiki-codec-json/keiki-codec-json.cabal`.
- `keiki-codec-json/keiki-codec-json.cabal` exists with empty `library` and `test-suite`
  stanzas, depending on `base`, `keiki`, `aeson`, `text`.
- `keiki-codec-json/src/Keiki/Codec/JSON.hs` exists as an empty module.
- `cabal build all` succeeds (compiles the empty library plus the existing keiki).

Acceptance: `cabal build all` is green; no behavioural change.

### M1 — `Keiki.Shape` lands in `keiki`

Add a new module `Keiki.Shape` in the existing keiki package. Add the SHA-256 dep
(prefer `cryptohash-sha256` for minimalism; allow `crypton` if the maintainer prefers
the consolidated package). Implement:

- `class CanonicalTypeName a` with default via `Typeable`.
- `class KnownRegFileShape (rs :: [Slot])`.
- `regFileShapeHash :: Proxy rs -> Text`.
- `renderStableTypeRep :: SomeTypeRep -> Text` walking `splitApps`, emitting
  `<tyConModule>.<tyConName>` per `TyCon`, parenthesising applications canonically.
- `sha256Hex :: Text -> Text` helper (SHA-256 over UTF-8 encoding, lower-case hex).
- Inductive instances of `KnownRegFileShape` over `'[]` and `'(s,t) ': rs`.

Acceptance: `cabal test keiki` passes a new test module `Keiki.ShapeSpec` covering:
- The hash of `'[]` is byte-equal to a checked-in expected value.
- The hash of `'[ '("retryCount", Int) ]` is byte-equal to a checked-in expected value.
- `renderStableTypeRep (someTypeRep (Proxy @Int))` produces a checked-in expected
  string.
- `renderStableTypeRep (someTypeRep (Proxy @(Maybe Int)))` produces the expected
  parenthesised application string.

### M2 — `keiki-codec-json` codec lands

Implement `Keiki.Codec.JSON`:

- `class RegFileToJSON (rs :: [Slot])` with three methods: `regFileToJSON`,
  `regFileFromJSON`, and `regFileToEncoding` (R10). The third has a default
  implementation (`Aeson.toEncoding . regFileToJSON`); the inductive instance
  overrides it to walk slots directly into `Aeson.Series` via `Aeson.pairs`,
  avoiding the `Aeson.Value` intermediate.
- Base instance over `'[]` (encode = `Object mempty`; encoding = `Aeson.pairs mempty`;
  decode strict-rejects any non-empty object).
- Inductive instance over `'(s,t) ': rs` requiring `(KnownSymbol s, ToJSON t, FromJSON
  t, RegFileToJSON rs)`.
- Encoder walks the slot list, emitting `Aeson.Object` with one key per slot in slot-list
  order.
- Streaming encoder walks the same slot list, emitting `Aeson.Series` chained with `<>`,
  zero-copy through `Aeson.pairs`.
- Decoder validates: object shape; key set equals the slot-list set (no missing, no
  extra); per-slot value parses via `FromJSON`. On any failure, returns
  `Left "<slotName>: <reason>"`.

Acceptance: `cabal test keiki-codec-json` passes a roundtrip property and a hand-rolled
unit test exercising:
- Empty RegFile encode/decode (both paths).
- Single-slot `'[ '("retryCount", Int) ]` encode/decode (both paths).
- Multi-slot RegFile encode/decode (both paths produce byte-equal output after
  `Aeson.encode`/`Aeson.encodingToLazyByteString`).
- Strict failure on missing slot, extra slot, type mismatch.

### M3 — Property tests (R5, R9, R10, P7.4)

Add property tests in `keiki-codec-json`:

- **Roundtrip property (Value path)** — `regFileFromJSON . regFileToJSON ≡ Right` for
  every `RegFile rs` whose slots all have `Arbitrary`. QuickCheck exhaustively over a
  representative slot list.
- **Roundtrip property (Encoding path)** — `regFileFromJSON . fromJust . Aeson.decode .
  Aeson.encodingToLazyByteString . regFileToEncoding ≡ Right` over the same generator.
  Catches divergence between the two encoder paths (R10).
- **Determinism property (R9)** — for two structurally-equal `RegFile`s, the encoded
  `Aeson.Value`s are byte-equal after `Aeson.encode`. Same property for the streaming
  path.
- **Sensitivity tests (P7.4)** — a fixed exemplar slot list paired with each of the
  schema-evolution table's structural mutations (#1–9). Each mutation produces a
  different hash from the baseline.

Acceptance: `cabal test keiki-codec-json` passes all properties at default QuickCheck
sample size.

### M4 — Performance baselines (`tasty-bench`)

Add a new test suite `keiki-codec-json-bench` (or similar) using `tasty-bench`. The
fixtures are condensed variants of the §10 reference cases, sized to keep CI bench
duration under ~30 seconds total:

| Fixture                | Source              | Condensed size    | What it measures                          |
|------------------------|---------------------|-------------------|-------------------------------------------|
| `BenchA_ContractSign`  | §10 Case A          | 5 parties, 50 audit entries → ~30 KB     | Steady-state low-rate baseline             |
| `BenchB_BatchRecon`    | §10 Case B          | 5,000 processedItems → ~1 MB             | The streaming-encoder motivating case      |
| `BenchC_TicketAgg`     | §10 Case C          | 100 comments → ~50 KB                    | Hydration-cost-dominated shape             |
| `BenchD_Auction`       | §10 Case D          | 1,000 bids → ~200 KB                     | High-write-rate snapshot pressure          |

For each fixture, benchmark all of:
- `Aeson.encode . regFileToJSON` (Value path) — wall-clock + allocation.
- `Aeson.encodingToLazyByteString . regFileToEncoding` (streaming path) — same.
- `regFileFromJSON . fromJust . Aeson.decode` (decode) — same.
- `regFileShapeHash` (one-shot, demonstrates dictionary cost at first use).

Numbers checked in as a baseline file (`bench/baseline.csv` or equivalent). CI runs
the bench on every push and reports drift relative to the baseline:
- Drift >20% on any single fixture/path pair → flag in PR comment, do NOT block merge.
- Drift >50% → flag prominently and require maintainer ack.

The bench is **not** a release gate. The cross-GHC hash gate (M5) is. Performance is
tracked, not gated, because (a) bench numbers are noisier than hash determinism, and
(b) the meaningful unit of latency budget belongs to the consumer (keiro), not to
keiki itself.

Acceptance: `cabal bench` runs cleanly; baseline file is checked in; CI workflow
reports bench drift on PRs; the README documents how to interpret the report.

### M5 — Cross-GHC CI gate (P7.2, release-blocking)

Add a CI workflow step that:

1. Builds keiki-codec-json on every GHC in `tested-with` (initially: 9.12.x; expand as
   keiki bumps).
2. Runs a "golden hash" test that asserts `regFileShapeHash (Proxy @ExemplarSlots)`
   equals a checked-in `Text` literal in the test source.
3. Runs a "cross-cabal-build" variant: rebuild the same test with a perturbed
   dependency version (e.g., bump `text`'s lower bound), assert the same hash.

The exemplar slot list MUST contain types from each of: `base` (`Int`, `Text`,
`UTCTime`), a custom type defined in the test suite, and a transitively-imported library
type (e.g., `Day` from `time`).

Acceptance: CI green on every supported GHC. The §8 procedure documented in
`keiki-codec-json/CONTRIBUTING.md` (or the keiki maintainer playbook).

### M6 — Documentation and design note

- Haddock on every public symbol in `Keiki.Shape` and `Keiki.Codec.JSON`. Each class
  references the relevant §3 R-number and §5 P-number from this plan.
- The `RegFileToJSON` haddock prominently calls out **P11** (slot-value-size budget),
  recommends `regFileToEncoding` (R10) for users with multi-MB slot values, and
  references §10 reference cases A–D for shape examples. Goal: a user reading the API
  haddock alone learns when to use the streaming path without having to find this
  ExecPlan.
- A new design note `docs/research/regfile-codec-design.md` summarises the user-visible
  shape, points at this plan for rationale, walks the worked example of a snapshot
  consumer using both classes, and reproduces the §10 reference cases as durable
  design context (so the cases survive even if this ExecPlan is later moved to an
  archive folder).
- Update `docs/research/effects-boundary.md` (the keiki-side codec-free anchor) to
  note that `keiki-codec-json` is a sibling package providing optional JSON for
  `RegFile rs`, preserving the codec-free promise of `keiki` itself. The keiro-side
  survey `keiro/docs/research/02-keiki-decide-loop.md` §"Effectful Story" reiterates
  the same stance; the keiro maintainer is responsible for updating that downstream
  passage when the package ships (notify keiro via the integration ExecPlan at
  `keiro/docs/plans/9-integrate-keiki-codec-json-into-keiro-snapshot-path.md`).
- Update `docs/research/schema-evolution.md` to cross-reference this plan as the
  implementation of its "snapshots carry a register-file shape hash" commitment.

Acceptance: `cabal haddock all` is clean; the design note compiles in `mdformat` (or
whatever keiki uses for doc lint); the cross-references in `effects-boundary.md`
and `schema-evolution.md` resolve.


## Concrete Steps

Working directory: `/Users/shinzui/Keikaku/bokuno/keiki`.

### M0

1. Create `cabal.project`:

       packages: keiki/keiki.cabal
                 keiki-codec-json/keiki-codec-json.cabal

   (Or, if the existing `keiki.cabal` lives at repo root rather than under `keiki/`,
   adjust paths accordingly during M0; document the chosen layout in the M0 commit
   message.)

2. Create directories: `keiki-codec-json/src/Keiki/Codec/`,
   `keiki-codec-json/test/Keiki/Codec/`.

3. Author `keiki-codec-json/keiki-codec-json.cabal` with empty `library` and
   `test-suite` stanzas. Mirror keiki's `tested-with`, common stanzas, default extensions.

4. Author `keiki-codec-json/src/Keiki/Codec/JSON.hs` as `module Keiki.Codec.JSON where`
   with no exports.

5. `cabal build all` — expect: `keiki-0.1.0.0` builds; `keiki-codec-json-0.1.0.0`
   builds; both packages' empty test stanzas compile.

### M1

1. In `keiki/keiki.cabal`, add `keiki:Keiki.Shape` to `exposed-modules`. Add
   `cryptohash-sha256 ^>= 0.11` (or chosen SHA-256 lib) to `build-depends`.

2. Author `keiki/src/Keiki/Shape.hs` per the §7 sketch.

3. Author `keiki/test/Keiki/ShapeSpec.hs` with the four golden assertions named in M1
   acceptance.

4. `cabal test keiki` — expect all assertions pass; the golden `Text` values are
   captured into the test source as `expected` constants.

### M2

1. Add `Keiki.Codec.JSON` to `keiki-codec-json.cabal`'s `exposed-modules`. Add `aeson`,
   `keiki`, `text`, `unordered-containers` (or whichever Aeson uses on the chosen
   version) to `build-depends`.

2. Author `keiki-codec-json/src/Keiki/Codec/JSON.hs` per the §7 sketch.

3. Author `keiki-codec-json/test/Keiki/Codec/JSONSpec.hs` with the unit tests named in
   M2 acceptance.

4. `cabal test keiki-codec-json` — expect green.

### M3

1. Add `tasty-quickcheck` (or `hspec-quickcheck`, whichever keiki uses) to
   `keiki-codec-json`'s test stanza.

2. Author the four property test modules (Value-roundtrip, Encoding-roundtrip,
   determinism, sensitivity).

3. `cabal test keiki-codec-json` — expect green at default sample size; document
   sample-size tuning if any property is slow.

### M4

1. Add `tasty-bench ^>= 0.4` to `keiki-codec-json`'s build-depends in a new
   `benchmark` stanza in the cabal file.

2. Author benchmark modules under `keiki-codec-json/bench/`:
   - `Bench/Fixtures.hs` — generators for the four fixtures (BenchA, BenchB, BenchC,
     BenchD), parameterised so condensed and full sizes are both available.
   - `Bench/Encode.hs` — benchmarks for `regFileToJSON` and `regFileToEncoding`
     against each fixture.
   - `Bench/Decode.hs` — benchmarks for `regFileFromJSON` against each fixture's
     pre-encoded output.
   - `Bench/Hash.hs` — benchmarks for `regFileShapeHash` (cold + cached path).

3. Run `cabal bench keiki-codec-json` locally on the maintainer's machine to capture
   a baseline. Commit the baseline as `keiki-codec-json/bench/baseline.csv` (or
   whatever format `tasty-bench` uses for `--csv`).

4. Update CI to run `cabal bench keiki-codec-json` and emit a comparison-against-
   baseline report. Drift thresholds documented in M4 acceptance.

5. Verify on a pushed branch that the bench runs in <30 seconds total and the report
   surfaces in PR comments.

### M5

1. Author `keiki-codec-json/test/Keiki/Codec/CrossGHCGoldenSpec.hs` with the cross-GHC
   golden hash assertion.

2. Update CI configuration (path TBD; the maintainer will name the file). Add a matrix
   row per supported GHC.

3. Document the §8 procedure in `keiki-codec-json/CONTRIBUTING.md` or the keiki
   maintainer playbook.

4. Verify the matrix runs end-to-end on a pushed branch before merging.

### M6

1. Author haddock on every public symbol in the two new modules. The `RegFileToJSON`
   haddock includes a "Performance" subsection citing P11 and §10.

2. Author `docs/research/regfile-codec-design.md` (the design note; ~5–10 pages,
   reproduces §10 reference cases).

3. Update the cross-references in `docs/research/effects-boundary.md` (keiki-side
   codec-free anchor) and `docs/research/schema-evolution.md`. The keiro-side
   passage at `keiro/docs/research/02-keiki-decide-loop.md` §"Effectful Story" is
   updated by the keiro maintainer when notified via the integration ExecPlan
   (`keiro/docs/plans/9-integrate-keiki-codec-json-into-keiro-snapshot-path.md`).

4. `cabal haddock all` — expect clean.


## Validation and Acceptance

End-to-end acceptance: a downstream consumer (the keiro library when it is implemented;
testable today via a fixture) can write:

    import Keiki.Shape       (regFileShapeHash, KnownRegFileShape)
    import Keiki.Codec.JSON  (regFileToJSON, regFileFromJSON, RegFileToJSON)
    import Data.Aeson        (encode, decode)

    -- Persist:
    let bytes = encode (regFileToJSON regs)
        hash  = regFileShapeHash (Proxy @MySlots)
    -- (write bytes + hash to a snapshot row)

    -- Restore:
    case decode bytes of
      Just v  -> case regFileFromJSON v of
        Right regs' -> {- use regs' -}
        Left err    -> {- fall through to full replay -}
      Nothing -> {- fall through to full replay -}

with the guarantees that:

- The same `MySlots` produces the same `hash` byte-for-byte across every supported GHC,
  every machine, every `cabal build` (R4, P7.2 release-blocking).
- A single change in `MySlots`'s slot list (rename, add, remove, reorder, type change)
  changes `hash` (R5, P7.4 sensitivity tests).
- A change to `MySlots`'s slot types' `ToJSON` instances does NOT change `hash` —
  detection of that case is the consumer's `stateCodecVersion`.
- The encoder never silently produces a partial RegFile (R7); the decoder never silently
  accepts a malformed one (R2 strict).
- A user with a multi-megabyte slot value can swap to `regFileToEncoding` (R10) and
  observe the encode-time and memory improvements documented in M4's bench baseline,
  with zero source-code changes outside the encode call site.

The four CI test categories (P7.1–4) collectively certify the correctness guarantees on
every push. The M4 bench tracks the performance baseline and surfaces drift on every
PR.


## Idempotence and Recovery

Implementation steps are idempotent:

- Re-running `cabal build all` is safe (cabal is idempotent).
- Re-running tests is safe.
- The `cabal.project` file is created once; subsequent edits are diffs.
- M0 is reversible by deleting `cabal.project` and the `keiki-codec-json/` directory
  before any code is committed under it.

If a milestone fails partway:

- M1 partial: revert `Keiki.Shape` and the cabal edit; tests revert to the pre-M1 set.
- M2–M6 partial: revert the in-progress files; the previous milestone's acceptance is
  unaffected because `keiki-codec-json` is a separate package.

Nothing in this plan touches `keiki`'s core logic (`Keiki.Core`, `Keiki.Composition`,
`Keiki.Builder`, etc.), so the existing user base is unaffected by an aborted attempt.


## Interfaces and Dependencies

### Libraries used

- **`base ^>= 4.21`** — for `Type.Reflection` (`SomeTypeRep`, `splitApps`, `tyConModule`,
  `tyConName`, `someTypeRep`), `GHC.TypeLits` (`KnownSymbol`, `Symbol`, `symbolVal`),
  `Data.Proxy`. Already a keiki dep.
- **`text ^>= 2.1`** — `Text` for the hash output and `renderStableTypeRep`. Already a
  keiki dep.
- **`cryptohash-sha256 ^>= 0.11`** (or equivalent) — SHA-256 implementation. **New
  dep** in `keiki`. Justification: SHA-256 is the documented hash algorithm; we want a
  small, vetted, single-purpose library, not a transitive surprise. Alternative:
  `crypton` if the maintainer wants the broader cryptographic toolkit consolidated.
- **`base16-bytestring`** (or build into the SHA-256 lib) — hex rendering. New dep.
- **`aeson`** — only in `keiki-codec-json`, never in `keiki`. The `keiki` cabal MUST NOT
  gain this dep (R8).
- **`keiki`** — `keiki-codec-json` depends on `keiki ^>= 0.1`.
- **`unordered-containers`** — for `Aeson.KeyMap` operations in
  `keiki-codec-json`. Comes via `aeson`'s exports.
- **`tasty-bench ^>= 0.4`** — only in `keiki-codec-json`'s benchmark stanza, never in
  the library. Provides the M4 performance baseline against §10 reference fixtures.
  Already in the wider Haskell ecosystem (`Bodigrim/tasty-bench` in the mori
  registry).
- **`containers`** — for `Map`/`Set` types used in §10 fixtures. Already a transitive
  dep via aeson.
- **`vector`** — for `Vector`-typed fixtures in §10 cases A and D. New dep in
  `keiki-codec-json`'s benchmark stanza only (not the library).

### Modules added

In `keiki`:

- `Keiki.Shape` — exposes `class CanonicalTypeName a`, `class KnownRegFileShape (rs ::
  [Slot])`, `regFileShapeHash :: Proxy rs -> Text`, `renderStableTypeRep :: SomeTypeRep
  -> Text`.

In `keiki-codec-json`:

- `Keiki.Codec.JSON` — exposes `class RegFileToJSON (rs :: [Slot])`, `regFileToJSON ::
  RegFile rs -> Aeson.Value`, `regFileFromJSON :: Aeson.Value -> Either String (RegFile
  rs)`, `regFileToEncoding :: RegFile rs -> Aeson.Encoding`.

### Type signatures that must exist at the end of M2

    -- Keiki.Shape
    class CanonicalTypeName a where
      canonicalTypeName :: Proxy a -> Text
    class KnownRegFileShape (rs :: [Slot]) where
      regFileShapeHash  :: Proxy rs -> Text
    renderStableTypeRep :: SomeTypeRep -> Text

    -- Keiki.Codec.JSON
    class RegFileToJSON (rs :: [Slot]) where
      regFileToJSON     :: RegFile rs -> Aeson.Value
      regFileFromJSON   :: Aeson.Value -> Either String (RegFile rs)
      regFileToEncoding :: RegFile rs -> Aeson.Encoding
      regFileToEncoding =  Aeson.toEncoding . regFileToJSON  -- default; override per instance

### Backwards compatibility

No existing `keiki` API is changed. No existing test breaks. Existing keiki users are
unaffected unless they choose to depend on `Keiki.Shape` (new, opt-in) or
`keiki-codec-json` (new, opt-in).


## References

- This ExecPlan: `docs/plans/36-regfile-json-codec-and-shape-hash-for-snapshot-persistence.md`
- Pre-existing keiki commitment: `docs/research/schema-evolution.md` lines 19–22
- Codec-free architectural anchor (keiki-side):
  `docs/research/effects-boundary.md` lines 72–73
- Codec-free survey passage (consumer-side, in keiro):
  `keiro/docs/research/02-keiki-decide-loop.md` §"Effectful Story"
- `RegFile` definition: `src/Keiki/Core.hs:126-129`
- `KnownSlotNames`: `src/Keiki/Core.hs:249-257`
- `GRecord`, `EmptyRegFile`: `src/Keiki/Generics.hs:53-87`, `296-307`
- `Type.Reflection` precedent: `src/Keiki/Symbolic.hs:73-76,156-162`
- Driving consumer (out of tree):
  - `keiro/docs/research/09-snapshot-strategy.md` (§3, §6)
  - `keiro/docs/research/11-upstream-roadmap.md` §7.1, §7.2
  - `keiro/docs/research/10-workflow-roadmap.md` §3, §6
  - `keiro/docs/masterplans/1-keiro-research-foundation.md` §"Outcomes & Retrospective"


## Revisions

- 2026-05-13 — Citation cascade from MP-11's deep-validation pass. The plan
  previously cited `docs/research/02-keiki-decide-loop.md` (which lives in keiro,
  not keiki) as the "no built-in JSON or binary" anchor in five places: the
  Purpose / Big Picture intro, the "Why this plan now" subsection, the Decision
  Log entry on the package split, M6's concrete steps and acceptance, and the
  References list. All five were rewritten to use
  `docs/research/effects-boundary.md` lines 72–73 (the keiki-side anchor) as the
  primary citation and `keiro/docs/research/02-keiki-decide-loop.md` §"Effectful
  Story" as a consumer-side reiteration. The M6 acceptance criterion was changed
  from "cross-references in `02-keiki-decide-loop.md` … resolve" to
  "cross-references in `effects-boundary.md` … resolve" because the keiki
  maintainer can only update keiki-side files; the keiro-side passage is
  updated by the keiro maintainer via the integration ExecPlan loop at
  `keiro/docs/plans/9-integrate-keiki-codec-json-into-keiro-snapshot-path.md`.
  Reason: the prior citation was broken (the file does not exist in the keiki
  repository), which would have surfaced as an M6 acceptance failure during
  implementation. Decision Log and Surprises & Discoveries entries record the
  change. No design changes; citation-only revision.
