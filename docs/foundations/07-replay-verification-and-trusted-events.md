# Replay Verification and Trusted Events

Keiki replays an event by asking which outgoing edge could have produced it.
That sounds like ordinary forward evaluation in reverse, but it is intentionally
not a complete equation between the edge's output expression and the stored
event. Some output fields reconstruct the command; other fields are recomputed
and checked. Knowing which is which is essential when deciding what an event
log is allowed to prove.

## Head attribution comes first

For each candidate edge, replay applies `solveOutput` to the edge's first
`OPack`:

1. `wcMatch` projects the observed event into its ordered field tuple.
2. Top-level `TInpCtorField` positions supply values for the candidate command.
3. `icBuild` reconstructs that candidate command once every command field is
   available.
4. Derived output positions are recomputed from the pre-event registers and
   reconstructed command.
5. The rebuilt event must equal the observation, and the edge guard must hold
   for the reconstructed command.

Multi-event tails do not participate in this choice. Once the head attributes
the event to one edge, replay checks the tail sequentially through its in-flight
state.

## Invertible fields retain the observation

`solveOutput` keeps these output positions at their observed values:

- `TLit`
- `TOpaqueLit`
- `TReg`
- `TInpCtorField`

They are called *invertible* positions because replay can accept their observed
values without evaluating the original output expression. A top-level
`TInpCtorField` additionally contributes that value to command reconstruction.

This means an output `TLit 3` does not prove that the stored field is `3`, and
an output `TReg #balance` does not prove that the stored audit value equals the
current replay register. Rechecking the latter would make old events depend on
whatever register snapshot replay happened to start from. The observation is
the value for these positions.

If an application requires a stored value to be derived from other command or
state data, it must express that relationship as a derived term or validate it
at another trusted boundary. A literal-looking output field is presentation,
not an integrity constraint.

## Derived fields are recomputed

These positions are recomputed and compared with the observation:

- `TArith`
- `TApp1`
- `TApp2`
- `TFieldProj`

For example, if an event stores both a quantity and
`lineTotal = quantity * unitPrice`, replay reconstructs the command from its
invertible quantity and unit-price positions, recomputes `lineTotal`, and
rejects a tampered total.

The concrete evaluator can run every Haskell function, but the optional
symbolic checker cannot inspect an arbitrary `TApp1` or `TApp2`. Symbolic
analysis therefore drops an unsupported relationship and retains the ambiguity
warning. Losing precision is acceptable; manufacturing a false disjointness
proof is not.

## Structural evidence controls cross-edge sharing

Two edges may use the same diagnostic `wcName` without exposing the same event
constructor or field order. Keiki shares one symbolic observed field between
replay candidates only when both `WireCtor`s carry trusted Generic-derived
schemas with the same constructor path and a position-by-position type
alignment.

Manual constructors state `wcSchema = wireSchemaUnavailable`. Composition
prefixes evidence across checked `Either` arms. Transformations that change a
matcher or field meaning drop it. An unavailable or prefix-related schema keeps
the existing warning; it never authorizes a cast or name-based proof.

## What the validation layers guarantee

The layers answer different questions:

- `checkHiddenInputs` verifies that the head carries every command field replay
  needs.
- default `inversionAmbiguityWarnings` remains pure and conservative; it starts
  no solver.
- `checkInversionAmbiguitySymDetailed` is an explicit IO analysis. It models two
  independently reconstructed commands against shared pre-event registers and,
  when structurally witnessed, shared observed fields.
- only a definite solver `Unsatisfiable` result removes a compatibility
  warning. Satisfiable means “not proved disjoint,” not “a concrete ambiguity
  witness exists.” Unknown, timeout, missing z3, unsupported carriers, opaque
  functions, and missing schemas all retain the warning.

Runtime replay and these build-time checks rely on the documented honesty laws
of `InCtor` and `WireCtor`: their matchers and builders must describe the
constructor they claim. Structural schemas prevent accidental cross-edge field
alignment from names, but they do not make arbitrary consumer-owned Haskell
functions trustworthy.

## Where to go deeper

The executable model and its soundness polarity are documented in
[`full-symbolic-replay-inversion-model.md`](../research/full-symbolic-replay-inversion-model.md).
The governing decisions are
[ADR-0001](../adr/0001-structural-re-indexing-for-sound-replay.md) for typed
alignment and [ADR-0003](../adr/0003-proof-gates-fail-conservatively.md) for
conservative proof gates. Persisted wire kinds and schema versions are a
separate concern covered by
[ADR-0005](../adr/0005-persisted-wire-identities-are-explicit-and-versioned.md).
