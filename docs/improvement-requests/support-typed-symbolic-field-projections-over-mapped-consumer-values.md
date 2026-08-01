---
type: Improvement Request
title: Support typed symbolic field projections over mapped consumer-owned values
description: >-
  Add a first-class, solver-visible field-projection term so a guard can read one scalar field
  out of a mapped consumer-owned value without an opaque TApp escape hatch.
timestamp: 2026-08-01T00:14:56Z
requestId: IR-1
status: released
origin: mori://shinzui/keiro
plan: docs/plans/79-typed-symbolic-field-projections-over-mapped-consumer-owned-values.md
reviews:
  - kind: model
    reviewer: codex
    reviewed_at: 2026-08-01T00:14:56Z
    document_timestamp: 2026-08-01T00:14:56Z
    scope: technical-accuracy
    outcome: approved
    provider: openai
    model: gpt-5
    effort: unspecified
    context: >-
      Revalidated the released IR-1 projection contract while deriving IR-3 and IR-4; corrected
      stale downstream Keiro bounds and confirmed the released getter remains intentionally
      one-way, motivating conservative exactness and exact-domain follow-ups.
---

# Improvement Request: Support Typed Symbolic Field Projections over Mapped Consumer-Owned Values

## Status

**Released.** Implemented by ExecPlan 79 and published on 2026-07-28 as
[`keiki-0.4.0.0`](https://hackage.haskell.org/package/keiki-0.4.0.0), with the coordinated
`keiki-codec-json-0.4.0.0` and `keiki-codec-json-test-0.4.0.0` releases. The implementation
uses a structural `ProjBase`, nominal projection-tag/owner/result memo identity, and
derived-term treatment in the inversion machinery. Keiro subsequently adopted the capability and
currently constrains Keiki to `>=0.6 && <0.7` across its active packages.

**Previously planned.** Accepted on 2026-07-28 after validation against the codebase;
implementation was specified by ExecPlan 79
(`docs/plans/79-typed-symbolic-field-projections-over-mapped-consumer-owned-values.md`).

**Post-release exactness clarification.** The released one-way `FieldProjection` contract provides
path-stable, solver-visible over-approximation: every concrete getter result can be represented and
repeated reads share one variable, but the solver can also choose result values outside the
getter's image. Concrete-to-symbolic agreement is therefore one-way. Definite UNSAT over that
larger domain remains a sound emptiness proof, while SAT is not necessarily backed by a concrete
owner and must not be reported as exact. IR-3 and IR-4 respectively specify the conservative
classification repair and the explicit domain/reconstruction evidence needed to regain exactness.

**Originally proposed.** Keiro is implementing structural consumer-owned types in `keiro-dsl` (Keiro's
improvement request IR-1, `docs/improvement-requests/support-structural-consumer-owned-types-in-keiro-dsl.md`
in the `shinzui/keiro` repository, coordinated by Keiro's master plan 25). That work deliberately
requires **no Keiki change**: mapped consumer values are whole values — copied wholesale into
events and registers — and every decision-relevant scalar is promoted to an explicit command or
register field.

This request is the next ergonomic tier, filed now so it is not lost. It is the prerequisite
Keiki capability for ever letting a Keiro specification write a checked guard such as
`when register.doc.contentHash != command.contentHash` instead of promoting `contentHash` to a
separate scalar. Keiro's research note
(`docs/research/14-structural-consumer-type-tradeoffs.md` in `shinzui/keiro`, section 4 and
Experiment C) fixes the sequencing rule this request honors: Keiki must have the first-class
term, evaluator, symbolic translation, validator support, and tests **before** any DSL syntax
claims the capability. Keiro will not expose surface syntax until this request is released.

## Context

Keiki already solves this problem for input constructors. `TInpCtorField` in `src/Keiki/Core.hs`
projects field `ix` of an input constructor structurally, through an `InCtor` witness carrying a
lawful `icMatch`/`icBuild` round trip, and the SBV translator reads it for real. `TArith` did the
same for arithmetic: unlike the deliberately opaque `TApp1`/`TApp2` escape hatches, the solver
sees through it. The curated symbolic registry in `src/Keiki/Symbolic.hs` (`Sym`, `discoverSym`)
covers `Bool`, `Int`, `Integer`, `Text`, `UTCTime`, and the fixed-width integers, and the
`SymEnv` memo cache (EP-42 of MasterPlan 12) shares one SBV variable per register slot / input
field across repeated reads so `proj #x .== proj #x` is valid, not merely satisfiable.

What is missing is the same treatment for a field of a **mapped consumer-owned value** — an
application record such as Mori's `DocInfo` that occupies a single register slot or input field
as one opaque-to-Keiki Haskell value. Today the only way to read `contentHash` out of such a
value inside a guard is `TApp1 getContentHash`, which:

- is invisible to the SBV translator, so mutual-exclusion and dead-edge analyses degrade;
- triggers the `OpaqueGuard` audit warning (`src/Keiki/Core.hs`, `predHasOpaqueTerm`), which
  Keiro's stream boundary treats as a validation failure under its forced options; and
- carries no field identity, so two reads of the same field are unrelated symbolic terms and
  diagnostics cannot name the path.

The consequence is the promote-to-scalar discipline Keiro's IR-1 codifies. That discipline is
often good domain modeling and remains the sanctioned pattern, but for values with several
decision-relevant fields it duplicates data into commands and registers purely to satisfy the
symbolic layer.

## The Request

Add a first-class field-projection term to `Term`, semantically equivalent to:

```haskell
-- | Witness that field @name@ of the consumer-owned type @owner@ has type @r@.
-- Generated from a structural binding graph (see provenance note below);
-- Keiki defines and tests its laws, not its provenance.
data FieldWitness (name :: Symbol) owner r = FieldWitness
  { fwShapeId :: String   -- stable identity of the owning declared shape
  , fwGet     :: owner -> r  -- total projection
  }

TFieldProj ::
  (KnownSymbol name, Typeable r) =>
  FieldWitness name owner r ->
  Term rs ci ifs owner ->
  Term rs ci ifs r
```

The exact spelling belongs to Keiki; the required semantics are:

1. **Evaluation.** `evalTerm` applies `fwGet`. The getter must be total for every well-formed
   `owner` value; partial projections are not expressible through this term.
2. **Symbolic translation.** `translateTermSym` allocates one shared SBV variable per
   *(base term, shape identity, field name)* path, extending the existing `SymEnv` memo cache,
   so repeated reads of the same field are the same symbolic variable and
   `proj #doc #contentHash .== proj #doc #contentHash` is valid. Only the projected **result**
   type `r` must be in the curated `Sym` registry (via `discoverSym`); the `owner` type needs no
   `Sym` instance. An unsupported result type is a construction- or validation-time rejection,
   never a silent fallback to opacity.
3. **Validator visibility.** A projection is not an opaque term: `predHasOpaqueTerm` (and hence
   the `OpaqueGuard` audit) does not fire on it, while continuing to fire on `TApp1`/`TApp2`.
   The pure-fragment extraction, mutual-exclusion (`symIsBot`), and dead-edge analyses retain
   path-stable projection identity. With only the released one-way witness they use a conservative
   over-approximation: definite UNSAT is sound, while SAT is not an exact concrete witness.
   Projecting out of an input-constructor field remains subject to the established `PInCtor` guard
   discipline exactly as direct field reads are today.
4. **Replay and inversion soundness — guards only.** In this request a projection may appear in
   guards. Using projections inside `OutFields` or register-write terms is out of scope: mapped
   values continue to move as whole-value copies (Keiro IR-1's contract). For the hidden-input
   and head-recoverability analyses in `validateTransducer`, a projected read counts,
   conservatively, as a read of the whole underlying register slot or input field. Replay
   semantics are unchanged; `reconstitute` needs no new machinery.
5. **Diagnostics.** Warnings, validation output, and rendered guards name the dotted path
   (for example `doc.contentHash`), using `KnownSymbol` field names and `fwShapeId`.
6. **Chained projections.** Nested access (`a.b.c`) may be supported by composing witnesses only
   if the memoization path key and diagnostics cover the full path; otherwise multi-hop
   projection is rejected at construction with a clear diagnostic. Single-hop projection is the
   acceptance bar; chaining may be staged.

**Provenance note.** A `FieldWitness` is just a getter plus identity; nothing in Keiki can prove
it matches the wire schema of the consumer type. Truthfulness comes from generation: Keiro
generates witnesses from the same resolved structural binding graph that generates its codecs
(Keiro IR-1), and Keiro's generated conformance harness carries the mutation tests proving a
wrong witness fails. Keiki's obligation is to define the laws (totality, stable identity,
evaluation/translation agreement) and provide the property-test harness for them — not to accept
arbitrary hand-written witnesses as checked claims. Keiki documentation for the term must state
this division explicitly.

## Out of Scope

- Collection membership, quantified guards, element update, or any solver-visible collection
  semantics (Keiro research note, research-grade tier).
- Projections in outputs, register writes, or event construction — whole-value copies remain the
  only mapped-value writes.
- Adding `Natural` (or other types) to the curated `Sym` registry — a separate, smaller request
  if adoption shows the need.
- Lifecycle-aware uninitialized registers (the "absent until initialized" model from Keiro's
  research note section 6) — a separate request.
- Any `keiro-dsl` surface syntax, scaffolding, or codec work — Keiro-side, and gated on this
  request being released and tagged first.

## Acceptance

The request is complete when all of the following are demonstrated in Keiki:

- the projection term and witness type exist with Haddocks stating the totality and identity
  laws and the provenance division above;
- `evalTerm`, `translateTermSym`, and `translatePred` support the term, with a property test
  that each concrete evaluation has the corresponding symbolic assignment; the released one-way
  witness does not claim that every symbolic assignment reconstructs a concrete owner;
- the `SymEnv` cache keys projections by path and a test proves
  `proj #doc #contentHash .== proj #doc #contentHash` is valid (z3-backed, alongside the
  existing memoization tests);
- `OpaqueGuard` does not fire for projection-only guards and still fires for `TApp1` guards, with
  tests for both directions;
- `validateTransducer` treats projected reads under the same `PInCtor` and hidden-input
  discipline as direct reads, with tests, and replay behavior is proven unchanged
  (forward/replay equality over a transducer whose guards use projections);
- diagnostics render dotted field paths;
- a negative property harness exists that Keiro's generated conformance tests can instantiate to
  catch a witness whose getter disagrees with the declared field; and
- the capability is released and tagged so Keiro can pin an authoritative version.

## Compatibility Baseline

Keiro's IR-1 review verified on 2026-07-28 that `keiki` is released and tagged at `0.3.1.0`.
Implementation must repeat the Hackage and upstream-tag check before choosing bounds or
declaring the capability released.

## References

- Requesting project: `mori://shinzui/keiro` — improvement request IR-1
  (`docs/improvement-requests/support-structural-consumer-owned-types-in-keiro-dsl.md`),
  research note (`docs/research/14-structural-consumer-type-tradeoffs.md`, section 4 and
  Experiment C), and master plan
  (`docs/masterplans/25-structural-consumer-type-ergonomics-and-soundness-preserving-adoption-for-keiro-dsl.md`).
- Keiki prior art this request extends: `src/Keiki/Core.hs` (`TInpCtorField`, `InCtor`,
  `TArith`, `predHasOpaqueTerm`, `validateTransducer`), `src/Keiki/Symbolic.hs` (`Sym`,
  `discoverSym`, `SymEnv` memo cache, `symIsBot`), `docs/research/tinpproj-design.md`, and
  `docs/research/sbv-boolalg-design.md`.
