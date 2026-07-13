# Architecture Decision Records (ADRs)

This directory holds **Architecture Decision Records**: short, durable
notes that capture one significant decision, the context that forced it,
and the consequences that follow.

The goal is to make the *why* behind the codebase findable without
reading every execution plan in `docs/plans/`.

## ADRs vs. ExecPlans

- **ExecPlans** (`docs/plans/`) are execution documents: living,
  step-by-step accounts of how a change was or will be implemented,
  with progress, surprises, and a running decision log.
- **ADRs** (here) are decision documents: one stable decision per file,
  written so a newcomer can understand a structural choice and its
  trade-offs in a few minutes. An ADR can link back to the ExecPlan that
  carried it out, but it should stand on its own.

When a plan reaches a decision worth remembering beyond that plan,
promote it to an ADR.

## Format

Each ADR is one Markdown file named `NNNN-kebab-case-title.md`, where
`NNNN` is a zero-padded sequence number. Use this template:

```markdown
# ADR-NNNN: <Title>

- **Status:** Proposed | Accepted | Superseded by ADR-MMMM | Deprecated
- **Date:** YYYY-MM-DD
- **Plan(s):** docs/plans/<N>-<slug>.md (optional)

## Context
What forces the decision? The problem, constraints, and the options considered.

## Decision
What we chose, stated plainly.

## Consequences
What becomes easier, what becomes harder, and the trade-offs/caveats accepted.
```

**Status lifecycle:** an ADR starts `Proposed`, becomes `Accepted` when
adopted, and is marked `Superseded by ADR-MMMM` rather than deleted
when a later ADR overrides it. Use `Deprecated` for a decision that no
longer applies but was not replaced.

ADRs are append-only in spirit: correct small factual errors in place,
but record a *change of decision* as a new ADR that supersedes the old
one.

## Index

| ADR | Title | Status |
|-----|-------|--------|
| [0001](0001-structural-re-indexing-for-sound-replay.md) | Structural re-indexing of `Term`/`OutFields` for sound replay | Accepted |
| [0002](0002-event-logs-must-reproduce-forward-state.md) | Event logs must reproduce forward state | Accepted |
| [0003](0003-proof-gates-fail-conservatively.md) | Proof gates fail conservatively | Accepted |
| [0004](0004-composition-uses-snapshot-updates-and-checked-boundaries.md) | Composition uses snapshot updates and checked boundaries | Accepted |
| [0005](0005-persisted-wire-identities-are-explicit-and-versioned.md) | Persisted wire identities are explicit and versioned | Accepted |
