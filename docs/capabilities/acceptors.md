---
title: "Input and output acceptors"
type: Capability
description: "Project a transducer onto a first-class acceptor over commands or over events to decide language membership of a sequence."
generated:
  by: adopt-capabilities/0.9.2
  at: "2026-08-08T00:00:00Z"
capabilityId: CAP-8
provider: mori://shinzui/keiki
status: shipped
stability: experimental
since: "0.1.0.0"
packages:
  - keiki
interface:
  - Keiki.Acceptor
requires:
  - CAP-1
evidence:
  - kind: test
    resource: test/Keiki/AcceptorSpec.hs
    proves: The input and output acceptors recognise exactly the command and event languages, and the output acceptor agrees with reconstitute on complete and truncated logs.
---

# Input and output acceptors

Sometimes the question is not "what is the next state" but "is this sequence
admissible at all." keiki names the two acceptor projections of a transducer as
a first-class data type so downstream code can pattern-match on a known shape
instead of re-plumbing the step functions. It projects the core declaration in
[CAP-1](typed-transducer-core.md).

## What you adopt

- **`Keiki.Acceptor`**: the input-side acceptor (π₁ — drop the events; its
  language is the set of accepted command sequences) and the output-side
  acceptor (π₂ — invert ω; its language is the set of replayable event logs).
  The output acceptor carries `(InFlight s co, RegFile rs)` and steps with
  `applyEventStreaming`, so it agrees with reconstitution on multi-event and
  truncated logs, not just letter-only logs.

## Shortest real usage

```haskell
-- Does this event log lie in the aggregate's output language?
runOutputAcceptor (outputAcceptor transducer) eventLog :: Bool
```

## Limits

- **This is recognition, not transduction.** An acceptor answers membership; it
  does not return the reconstructed state. Use the replay surface (`CAP-2`) when
  you need the resulting registers and vertex.
- **Output-acceptor agreement inherits replay's preconditions.** It agrees with
  `reconstitute` only for transducers whose logs are actually recoverable, which
  is the property the validation gate (`CAP-3`) checks.
- Evidence is a single in-package spec exercising both projections; the module
  itself is small.
