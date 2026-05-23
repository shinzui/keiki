# Architecture Decision Records (ADRs)

This directory holds **Architecture Decision Records**: short, durable notes that
capture a single significant decision — the context that forced it, the decision
itself, and the consequences that follow. The goal is to make the *why* behind the
codebase findable in one place, without reading every ExecPlan in `docs/plans/`.

## ADRs vs. ExecPlans

- **ExecPlans** (`docs/plans/`) are *execution* documents: a living, step-by-step
  account of how a change was (or will be) implemented, with progress, surprises, and
  a running decision log. They are detailed and tied to a unit of work.
- **ADRs** (here) are *decision* documents: one decision per file, distilled and
  stable, written so a newcomer can understand a structural choice and its trade-offs
  in a couple of minutes. An ADR usually links back to the ExecPlan(s) that carried it
  out, but it stands on its own.

When a plan reaches a decision worth remembering beyond that plan, promote it to an ADR.

## Format

Each ADR is one Markdown file named `NNNN-kebab-case-title.md`, where `NNNN` is a
zero-padded sequence number. Use this template:

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

**Status lifecycle:** an ADR starts `Proposed`, becomes `Accepted` when adopted, and
is marked `Superseded by ADR-MMMM` (not deleted) when a later ADR overrides it — the
history stays readable. Use `Deprecated` for a decision that no longer applies but was
not replaced.

ADRs are append-only in spirit: correct a small factual error in place, but record a
*change of decision* as a new ADR that supersedes the old one.

## Index

| ADR | Title | Status |
|-----|-------|--------|
| [0001](0001-structural-re-indexing-for-sound-replay.md) | Structural re-indexing of `Term`/`OutFields` for sound replay | Accepted |
