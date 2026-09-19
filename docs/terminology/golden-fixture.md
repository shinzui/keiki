---
type: Term
title: "golden fixture"
description: "A fixed expected encoding used to detect unintended changes in a slot or register-file codec."
generated:
  by: process:codex
  at: "2026-09-19T17:47:50Z"
termId: TERM-33
status: current
tags: [codecs]
related: [TERM-30]
anchors:
  - kind: file
    resource: keiki-codec-json-test/README.md
---

# golden fixture

A fixed expected encoding used to detect unintended changes in a slot or register-file codec.

An unchanged slot type can acquire a different JSON representation without changing its shape hash. Comparing its encoding to a checked-in golden fixture makes that drift visible.

See [the supporting source or guide](../../keiki-codec-json-test/README.md).
