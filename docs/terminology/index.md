---
okf_version: "0.2"
---

# Keiki terminology

Controlled vocabulary for developers familiar with event sourcing and new to Keiki.
Definitions describe the pure library; persistence and effect execution belong to its embedding runtime.

The shared profile is [terminology](mori://shinzui/okf-profiles/profiles/terminology), pinned to v0.18.0 in [profile.dhall](profile.dhall). Stable handles resolve under `mori://shinzui/keiki/okf/terminology/concepts/TERM-N`.

## Core

| Handle | Term | Definition |
|---|---|---|
| TERM-1 | [symbolic-register finite-state transducer](transducer.md) | A finite control graph whose guarded transitions read typed registers and inputs, update registers, and emit ordered output words. |
| TERM-2 | [control vertex](control-vertex.md) | A named position in the finite control graph that determines which outgoing transitions are available. |
| TERM-3 | [edge](edge.md) | A declared transition with a guard, register update, ordered output expressions, target vertex, and execution mode. |
| TERM-4 | [register file](register-file.md) | The typed heterogeneous collection of named values retained across transitions. |
| TERM-5 | [slot](slot.md) | A register location identified by a type-level name and its value type. |
| TERM-6 | [guard](guard.md) | A predicate over the pre-transition registers and input that determines whether an edge is eligible. |
| TERM-7 | [output word](output-word.md) | The ordered list of events emitted by one edge execution. |
| TERM-8 | [command](command.md) | An input value offered to a transducer for a forward decision. |
| TERM-9 | [event](event.md) | An output value emitted by a transition and consumable as evidence during replay. |
| TERM-10 | [multi-event edge](multi-event-edge.md) | An edge whose output word contains two or more events. |
| TERM-11 | [epsilon edge](epsilon-edge.md) | An edge with an empty output word. |
| TERM-12 | [snapshot update semantics](snapshot-update-semantics.md) | The rule that an edge evaluates its register assignments and output expressions against the same pre-transition registers and input. |

## Replay

| Handle | Term | Definition |
|---|---|---|
| TERM-13 | [replay](replay.md) | Reconstruction of model state by consuming emitted events through the transducer declaration. |
| TERM-14 | [chunk replay](chunk-replay.md) | Replay of a complete event chunk that must finish with no pending events from a multi-event edge. |
| TERM-15 | [in-flight replay state](in-flight-replay-state.md) | A streaming replay state that remembers a target vertex and the remaining expected events of a partially consumed output word. |
| TERM-16 | [output inversion](output-inversion.md) | Recovery of a candidate input command from an observed event and the pre-transition register file. |
| TERM-17 | [replay safety](replay-safety.md) | The model properties checked to support reconstruction of forward state changes from emitted events. |
| TERM-18 | [hidden input](hidden-input.md) | A command input required by an edge that cannot be recovered from its invertible output fields. |
| TERM-19 | [recompute-and-verify](recompute-and-verify.md) | Replay verification of a derived event field by evaluating its expression using recovered input and pre-transition registers. |
| TERM-20 | [replay-only edge](replay-only-edge.md) | An edge excluded from forward decisions but available as a fallback for replaying historical events. |

## Composition

| Handle | Term | Definition |
|---|---|---|
| TERM-21 | [B-view](b-view.md) | A vertex-indexed presentation of the register slots designated live at that control vertex. |
| TERM-22 | [sequential composition](sequential-composition.md) | Construction of a transducer that feeds the first component's outputs into the second component's inputs. |
| TERM-23 | [acceptor](acceptor.md) | A one-alphabet state machine derived to recognize accepted input or output sequences. |
| TERM-24 | [feedback1](feedback1.md) | A single-step two-copy cascade that routes one transducer copy's output through a policy transducer into a second copy. |
| TERM-35 | [alternative](alternative.md) | Composition that dispatches disjoint input alternatives to separate transducer components. |
| TERM-36 | [forward equivalence](forward-equivalence.md) | Agreement of forward transitions and emitted outputs over every command sequence, comparing control states up to the documented state isomorphism. |

## Analysis

| Handle | Term | Definition |
|---|---|---|
| TERM-25 | [trusted wire schema](trusted-wire-schema.md) | Structural evidence derived through trusted constructor bindings for aligning event constructors and their payload fields. |
| TERM-26 | [symbolic analysis](symbolic-analysis.md) | Build-time reasoning about transducer predicates and outputs using symbolic values and a solver. |
| TERM-27 | [translation strength](translation-strength.md) | The reported distinction between an exact symbolic translation and a conservative approximation. |
| TERM-28 | [field projection](field-projection.md) | A nominally identified getter that exposes a field of a consumer-owned value to terms and symbolic reasoning. |
| TERM-29 | [exact projection domain](exact-projection-domain.md) | A declaration of exactly the values a field projection can return, paired with reconstruction of an owner for each admitted value. |

## Codecs

| Handle | Term | Definition |
|---|---|---|
| TERM-30 | [shape hash](shape-hash.md) | A codec-independent structural fingerprint of a register slot list or control-state datatype. |
| TERM-31 | [wire kind](wire-kind.md) | The JSON discriminator identifying an event constructor on the wire. |
| TERM-32 | [event schema version](event-schema-version.md) | The in-band JSON version used to select the migration path for a stored event envelope. |
| TERM-33 | [golden fixture](golden-fixture.md) | A fixed expected encoding used to detect unintended changes in a slot or register-file codec. |
| TERM-34 | [upcaster](upcaster.md) | A function that transforms a stored event envelope from one schema version to the next before decoding. |

## Presentation

| Handle | Term | Definition |
|---|---|---|
| TERM-37 | [topology diagram](topology-diagram.md) | A rendering focused on graph connectivity rather than the complete behavior of each edge. |

