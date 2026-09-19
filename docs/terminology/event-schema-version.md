---
type: Term
title: "event schema version"
description: "The in-band JSON version used to select the migration path for a stored event envelope."
generated:
  by: process:codex
  at: "2026-09-19T17:47:50Z"
termId: TERM-32
status: current
tags: [codecs]
related: [TERM-31, TERM-34, TERM-30]
anchors:
  - kind: file
    resource: keiki-codec-json/README.md
---

# event schema version

The in-band JSON version used to select the migration path for a stored event envelope.

The v field defaults to version 1 when absent. A decoder configured for a newer version applies the declared upcaster chain before constructor dispatch; the number is not a library release or a shape hash.

See [the supporting source or guide](../../keiki-codec-json/README.md).
