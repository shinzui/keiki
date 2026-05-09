# Symbolic Analysis in keiki and its Runtime Implications

This note answers two questions for someone integrating keiki into a
real codebase:

1. What does it mean that "keiki uses symbolic analysis"?
2. What does that buy me, and what does it cost me at build / test /
   runtime?

The design log behind these decisions lives in
`docs/research/sbv-boolalg-design.md` and the synthesis doc §7. This
note is the operational summary. The implementation is
`src/Keiki/Symbolic.hs`.

---

## 1. What we mean by "symbolic analysis"

Edge guards in keiki are predicates over `(RegFile rs, ci)` — the
register file and the input command. The library exports two
`BoolAlg` instances over `HsPred rs ci`:

- **v1, concrete-only.** Lives in `Keiki.Core`. `models` evaluates
  the predicate on a value; `sat` returns `Nothing`; `isBot` returns
  `True` only for `PBot`. No solver in the loop.
- **v2, SBV-backed.** Wrapped as `SymPred rs ci` in `Keiki.Symbolic`.
  Same predicate constructors, but `sat` and `isBot` translate the
  predicate to an SMT-LIB formula and dispatch z3 via SBV.

That second instance is what we mean by "symbolic analysis":
predicates are walked as syntax, lifted to symbolic SBV expressions,
and decided by an external solver.

The two instances coexist. A consumer who imports only `Keiki.Core`
gets the concrete v1 surface and pulls in no solver. Importing
`Keiki.Symbolic` opts into the v2 surface (and re-exports
`Keiki.Core`, so one import is enough).

## 2. What it's used for

Three load-bearing analyses, all in `Keiki.Symbolic`:

- **`symIsBot p`** — is `p` unsatisfiable? "Are these two edge
  guards mutually exclusive?" reduces to
  `isBot (g1 \`conj\` g2)`.
- **`symSat p`** — is there any `(regs, ci)` satisfying `p`? Wired
  into `BoolAlg.sat`, which returns a placeholder witness on a hit.
- **`symSatExt p`** — same as `symSat`, but reconstructs a concrete
  `(RegFile rs, ci)` witness from the solver's model. Requires
  `ExtractRegFile rs` and `KnownInCtors ci` evidence.
- **`isSingleValuedSym t`** — for every reachable vertex, asks
  `isBot` of every pairwise conjunction of outgoing-edge guards.
  Returns `True` iff the transducer is single-valued (synthesis §7
  invariant — at most one edge fires per input).

Single-valuedness is the headline use case. Without symbolic
analysis it's a Hedgehog property test (v1); with it, it's a decided
answer in CI.

## 3. What gets translated, what doesn't

`translatePred` walks `HsPred` structurally:

| Constructor | Translation |
|---|---|
| `PTop` / `PBot` | `sTrue` / `sFalse` |
| `PAnd` / `POr` / `PNot` | `(.&&)` / `(.||)` / `sNot` |
| `PEq a b` | `(.==)` when both terms have a `Sym` instance; else fresh `SBool` (lose precision) |
| `PInCtor ic` | `seInputCtor .== literal (icName ic)` against a shared tag |

`Term` translation:

| Constructor | Translation |
|---|---|
| `TLit r` | `literal . toSym` |
| `TReg ix` | fresh SBV var named `"reg/<slotName>"` |
| `TInpCtorField ic ix` | fresh SBV var named `"inp/<icName>/<slotName>"` |
| `TApp1` / `TApp2` | fresh anonymous SBV var of the result type (opaque) |

Curated `Sym` instances cover `Bool`, `Int`, `Integer`, `Text`, and
`UTCTime`. Any slot or input field whose value type is in that set
translates structurally; anything outside falls back to a fresh
variable. The User Registration aggregate hits none of the escape
hatches.

## 4. What pulling in `Keiki.Symbolic` costs you

A library consumer who imports `Keiki.Symbolic` inherits:

- **Cabal dep on `sbv ^>=11.7`.** Hard, not behind a flag — the
  synthesis-§7 single-valuedness invariant is load-bearing for the
  formalism, and a flag would split the test matrix into "with SBV"
  and "without SBV" paths. (See sbv-boolalg-design.md §"Cabal flag".)
- **z3 binary in `PATH` at runtime.** SBV dispatches to z3 by
  default. Install with `brew install z3` on macOS or
  `apt install z3` on Debian. If it's missing, SBV throws at the
  first solver call with a clear "Couldn't find solver" message.
- **GHC 9.10.3 or newer.** `sbv ^>=11.7` and the rest of the pin set
  agree on this floor.

A consumer who only imports `Keiki.Core` pays none of this. The v1
best-effort `BoolAlg HsPred` is unchanged.

## 5. When the solver actually runs

`symIsBot`, `symSat`, and `symSatExt` are **pure** functions wrapping
SBV calls in `unsafePerformIO` with `NOINLINE`. The wrapping is
deliberate: solver queries are deterministic for a given predicate
and side-effect-free outside the solver process, so referential
transparency holds.

Intended call sites:

- **Tests and CI.** `isSingleValuedSym (withSymPred t) == True` as a
  spec assertion. This is the v2 retrospective's gate.
- **Build-time / interactive.** Authors and users in `ghci` or
  `cabal repl` interrogating a transducer.

Intended **non**-call sites:

- **Per-event hot path.** `delta`, `omega`, `applyEvent`, and
  `reconstitute` all use the concrete `models` (v1 `evalPred`) — no
  solver call. **z3 is not a runtime dependency for processing
  events**, only for analyzing transducers.

Order-of-magnitude cost: ~10ms per warm call (mostly solver
dispatch). For the User Registration aggregate's
`isSingleValuedSym`, this lands at a few hundred milliseconds total
across a five-vertex transducer — fine for a test suite, not fine
for a per-event predicate check.

If you author your own analysis that pages through edges and asks
`isBot` per pair, budget accordingly and run it from tests, not from
request handlers.

## 6. Soundness vs. precision

The translation is **sound** for the structural fragment — no false
unsat, no false sat for predicates that don't escape into Haskell
functions. Where precision is lost:

- **`TApp1` / `TApp2` escape hatches.** Translated to fresh
  variables; the solver picks *some* value, possibly inconsistent
  with what the Haskell function would compute. `isBot` may say
  `False` when the true answer is `True` — never the other way.
- **Repeated reads of the same slot or input field in one
  predicate.** SBV uniquifies repeated variable names by appending
  `_N`. `proj #x .== proj #x` becomes a comparison of two
  independent symbolic values, not a tautology. Sound for sat/unsat
  (over-approximates SAT). For `symSatExt`, witnesses reconstructed
  by name lookup may not satisfy structural-equality predicates with
  this shape. Memoization is a deferred improvement (see
  `symSatExt`'s haddock).
- **Solver `Unknown` / timeout.** Treated conservatively: `isBot`
  returns `False`, `sat` returns `Nothing`. SBV's default has no
  timeout; a 5s cap is configured in `mkSymEnv`'s site.
- **Slot or input-field types outside the curated `Sym` set.** A
  compile error pointing at the missing instance. Add a `Sym`
  instance for the type or reshape the slot.

## 7. The `withSymPred` adapter

Example aggregates author their guards in `HsPred`-shape (the v1
predicate carrier). To run `isSingleValuedSym` (or any other
`BoolAlg`-polymorphic analysis) against the v2 instance, lift the
transducer's edges:

```haskell
withSymPred
  :: SymTransducer (HsPred rs ci) rs s ci co
  -> SymTransducer (SymPred rs ci) rs s ci co
```

`withSymPred` re-tags every edge guard with the `SymPred` newtype;
control graph and update / output terms are unchanged. This means
the v1 and v2 instances coexist on the same example without
source-level changes — `userReg` stays in `HsPred`-shape; the
symbolic spec wraps before checking.

## 8. What this means for someone integrating keiki

A short integration checklist:

- Pulling in `keiki` in a project that won't run analyses: import
  `Keiki.Core`. No SBV, no z3, no overhead. Per-event processing is
  concrete throughout.
- Pulling in `keiki` and wanting CI to verify single-valuedness or
  guard mutual exclusion: import `Keiki.Symbolic`, install z3 in the
  CI image, add `isSingleValuedSym (withSymPred t) == True` to a
  spec.
- Authoring guards: stay in the structural fragment (`PEq` over
  `Sym`-typed terms, `PInCtor`, boolean combinations). `TApp1` and
  `TApp2` work but reduce analytical precision; reach for them only
  when the structural fragment can't express the constraint.
- Authoring slots: register-file slot types should land in the
  curated `Sym` set (`Bool`, `Int`, `Integer`, `Text`, `UTCTime`).
  Adding a new `Sym` instance is a few lines if the type has a
  natural SBV representation.

## 9. Pointers

- `src/Keiki/Symbolic.hs` — implementation, with per-export haddock.
- `docs/research/sbv-boolalg-design.md` — the design log (why SBV,
  why z3, why a separate `Keiki.Symbolic` module, the
  `unsafePerformIO` justification, the `WitnessExtract` story).
- `docs/research/data-direction-c-symbolic-and-register-automata.md`
  §5 — the SMT-backed phase as originally sketched.
- `docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`
  §7 — single-valuedness as a formalism invariant.
- `docs/foundations/05-data-carrying-alphabets.md` — vocabulary
  (predicates instead of enumerated symbols, what `BoolAlg` is). The
  right starting point for a reader who hasn't seen any of this
  before.
- `test/Keiki/SymbolicSpec.hs` and
  `jitsurei/test/Jitsurei/UserRegistrationSymbolicSpec.hs` — what calls
  through z3 in the existing test suite.
