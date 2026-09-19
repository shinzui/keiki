---
type: Term
title: "upcaster"
description: "A function that transforms a stored event envelope from one schema version to the next before decoding."
generated:
  by: process:codex
  at: "2026-09-19T17:47:50Z"
termId: TERM-34
status: current
tags: [codecs]
related: [TERM-32, TERM-20]
anchors:
  - kind: file
    resource: keiki-codec-json/README.md
---

# upcaster

A function that transforms a stored event envelope from one schema version to the next before decoding.

A version-1 envelope can be rewritten into version-2 form before constructor dispatch. The derived codec requires every historical rung up to the configured current version; an upcaster is not a replay-only transition.

See [the supporting source or guide](../../keiki-codec-json/README.md).
