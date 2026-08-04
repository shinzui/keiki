# Architecture Decision Records (ADRs)

`docs/adr/` holds **Architecture Decision Records**: short, durable notes that
capture one significant decision, the context that forced it, and the
consequences that follow. The bundle is an [Open Knowledge Format
(OKF)](https://github.com/shinzui/okf-profiles) bundle governed by
`docs/adr/profile.dhall`, the shared `documentation.architectureDecisions`
profile. See `docs/adr/index.md` for the generated list of every ADR and
`docs/adr/log.md` for the bundle's change history.

The goal is to make the *why* behind the codebase findable without
reading every execution plan in `docs/plans/`.

## ADRs vs. ExecPlans

- **ExecPlans** (`docs/plans/`) are execution documents: living,
  step-by-step accounts of how a change was or will be implemented,
  with progress, surprises, and a running decision log.
- **ADRs** (`docs/adr/`) are decision documents: one stable decision per
  file, written so a newcomer can understand a structural choice and its
  trade-offs in a few minutes. An ADR can link back to the ExecPlan that
  carried it out, but it should stand on its own.

When a plan reaches a decision worth remembering beyond that plan,
promote it to an ADR.

## Format

Each ADR is one Markdown file at the bundle root with OKF frontmatter
followed by the historical prose template:

```markdown
---
type: Architecture Decision Record
title: <Title, without the ADR number>
description: <One sentence summary of the decision>
docId: ADR-<N>          # stable handle; allocate with `okf id next docs/adr --profile docs/adr/profile.dhall ADR`
status: Accepted         # Proposed | Accepted | Superseded by ADR-<N> | Deprecated
date: YYYY-MM-DD          # original decision date
generated:
  by: human:<your-id>    # or process:<id> / <producer>/<version>
  at: YYYY-MM-DDTHH:MM:SSZ
---

# ADR-<N>: <Title>

- **Plan(s):** docs/plans/<N>-<slug>.md (optional)

## Context
What forces the decision? The problem, constraints, and the options considered.

## Decision
What we chose, stated plainly.

## Consequences
What becomes easier, what becomes harder, and the trade-offs/caveats accepted.
```

New filenames may use whatever slug is convenient; the bundle-root path
pattern does not encode the ID, so the `docId` frontmatter field—not the
filename—is the canonical, rename-stable handle. Existing ADRs keep their
historical `NNNN-kebab-case-title.md` filenames and `# ADR-NNNN: <Title>`
headings; only their frontmatter carries the unpadded `ADR-N` handle.

**Status lifecycle:** an ADR starts `Proposed`, becomes `Accepted` when
adopted, and is marked `Superseded by ADR-N` rather than deleted when a
later ADR overrides it. Use `Deprecated` for a decision that no longer
applies but was not replaced.

ADRs are append-only in spirit: correct small factual errors in place,
but record a *change of decision* as a new ADR that supersedes the old
one.

## Validation

```bash
okf validate docs/adr \
  --profile docs/adr/profile.dhall \
  --profile-enforce \
  --log-enforce
```

Run this alongside the repository's other documentation checks (see
`justfile`) before committing a new or amended ADR, and append an
`okf log add docs/adr --kind ... --message ...` entry describing the change.
