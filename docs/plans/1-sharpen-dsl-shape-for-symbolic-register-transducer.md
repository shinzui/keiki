---
id: 1
slug: sharpen-dsl-shape-for-symbolic-register-transducer
title: "Sharpen DSL shape for symbolic-register transducer"
kind: exec-plan
created_at: 2026-05-01T05:20:13Z
intention: "intention_01knjzws4qezz9w8b0743zfqv8"
master_plan: "docs/masterplans/1-validate-symbolic-register-direction-via-haskell-prototype.md"
---

# Sharpen DSL shape for symbolic-register transducer

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

The keiki library is being designed (no code exists yet) to handle the pure part of event
sourcing, workflow engines, and durable execution as a single formalism: the
**symbolic-register transducer**. The synthesis note that defines this direction lives at
`docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md` and the
overall project background lives at `docs/foundations/00-reading-guide.md`.

Before any Haskell prototype is written, the **shape of the embedded DSL** that users
will write to describe a transducer must be settled. The DSL is the surface a user sees
when they declare an `Edge` — the syntax for `guard`, `update`, `output`, and `target` —
and the underlying AST datatypes (`Term`, `OutTerm`, `Update`, `Edge`, `RegFile`,
`Index`, the predicate carrier `phi`) those constructors compile to.

This decision matters because **the entire validation of the synthesis hinges on whether
the DSL is tolerable to write and whether `solveOutput` is mechanically derivable from it**
(the master plan's prototype, see
`docs/masterplans/1-validate-symbolic-register-direction-via-haskell-prototype.md`,
explicitly requires both).

After this plan is complete, a new design note exists at
`docs/research/dsl-shape-for-symbolic-register.md` containing: concrete Haskell datatype
sketches for `Term` / `OutTerm` / `Update` / `Edge` / `RegFile` / `Index` / predicate
carrier; a transcription of the User Registration aggregate from the synthesis note in
the chosen DSL so a reader can see whether it is tolerable; and a list of the precise
type signatures and ergonomic helpers (`matchCmd`, `mkOut`, `proj`, `Set`, `Combine`,
`Keep`, `#emailLabel`-style indexing) that the prototype is required to implement.

The user-visible win: a future contributor reading the design note understands exactly
what DSL surface keiki is committing to before any prototype code is written, and the
prototype contributor has an unambiguous target to compile.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] Re-read the inputs (synthesis note §2 and §3, direction-C note, direction-B note)
      and write a one-paragraph restatement of the open DSL questions. (2026-05-01)
- [x] Survey RegFile representation options (hand-rolled GADT, `vinyl`, `large-records`,
      `extensible`, `superrecord`) by reading their hackage docs and code via `mori`.
      (2026-05-01 — survey in design note §"Survey of RegFile representations"; the four
      third-party candidates are not in the local `mori` registry, so the survey relies
      on published API docs as documented in the Decision Log.)
- [x] Pick a `RegFile` representation with rationale and capture a worked tiny example
      (define a 2-slot register file, set/get a slot). (2026-05-01 — chose hand-rolled
      GADT on `[(Symbol, Type)]`; worked example is the `Demo` two-slot record.)
- [x] Sketch concrete `Term rs ci r` and `OutTerm rs ci co` AST constructors.
      (2026-05-01)
- [x] Sketch concrete `Update rs ci` constructors (Keep / Set / Combine) including the
      "distinct targets" invariant for Combine. (2026-05-01 — runtime check via
      `combine :: ... -> Either String ...`; `unsafeCombine` for confident sites.)
- [x] Choose the predicate carrier (`phi`) for v1 — first-class AST shape per synthesis §7
      — and write its constructors plus the `BoolAlg` instance signature. (2026-05-01)
- [x] Decide on the user-facing helper surface: `matchCmd`, `mkOut`, `proj`,
      `OverloadedLabels` for `Index`, lambda fields, `Generic`-driven helpers — and
      describe each precisely. (2026-05-01)
- [x] Transcribe the User Registration aggregate from the synthesis note §4 in the chosen
      DSL, verbatim where possible, and read it critically for ergonomics. (2026-05-01 —
      transcription includes a v1-internal `Continue` constructor and total
      `\case ... _ -> error "guard"` pads on `inp` callbacks; both flagged in
      Surprises & Discoveries.)
- [x] Identify any ergonomic blockers or open ambiguities and either resolve them or
      record them in the Decision Log with the chosen path. (2026-05-01 — verdict is
      "painful but workable"; pain concentrated in `inp` total-callback boilerplate and
      opaque `mkOut` outputs, both with v2 fixes specified.)
- [x] Write the design note at `docs/research/dsl-shape-for-symbolic-register.md` with all
      of the above, plus a "what the prototype must implement" checklist. (2026-05-01 —
      11 sections, Prototype Implementation Checklist enumerates every type, instance,
      helper, and evaluator EP-4 must produce.)
- [ ] Commit (with `MasterPlan:`, `ExecPlan:`, `Intention:` trailers) and update this
      plan's living sections. (2026-05-01 — living sections updated; commit deferred to
      orchestrator per plan-orchestration constraints.)


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- **IP-1 (transcription divergence: total `inp` callbacks).** The synthesis §4 aggregate
  uses partial pattern-matches like `\(StartRegistration d) -> d.email` inside what the
  pseudosyntax calls a `Set`. In the chosen DSL, `inp :: (ci -> r) -> Term rs ci r`
  takes a *total* function over `ci`, so the transcription pads every callback with
  `_ -> error "guard"`. The unreachable branches are guarded by the edge's predicate,
  but the `error` calls are honest about the v1 limitation. v2's structural input
  projection (`TInpProj :: Lens' ci r -> Term rs ci r` or a `Generic`-derived selector)
  retires the boilerplate. Affects: design-note §"Worked example: User Registration";
  EP-4 must accept the `error`-padded form for v1 and ship a Hedgehog property test that
  demonstrates the unreachable branches are in fact never taken.
  (2026-05-01)

- **IP-2 (hidden-input check needs at least one structural `OPack`).** Every `output` in
  the synthesis §4 transcription is `mkOut`, which collapses to `OFn` (opaque function).
  `solveOutput` cannot invert `OFn`, so the v1 hidden-input check would flag every edge
  in the example as opaque-output and the synthesis note's headline win — "the check
  has bite" — would not be observable in the smoke test. EP-4 must therefore include
  **at least one structural `OPack`** for one event constructor (recommendation:
  `RegistrationStarted`) so the check can fire on the genuine
  `AccountConfirmed`-missing-`confirmCode` schema bug from synthesis §4. Without that,
  the master plan's acceptance criterion ("solveOutput works on the example") is not
  observable. (2026-05-01)

- **IP-5 (RegFile representation choice was robust against the missing local survey).**
  None of `vinyl`, `large-records`, `extensible`, `superrecord` are in the local `mori`
  registry; the survey relies on published docs. The chosen representation —
  hand-rolled GADT on `[(Symbol, Type)]` — depends on none of those libraries, so the
  decision is robust against the local-registry limitation. The risk is symmetric:
  if a future scaling concern wants `vinyl`'s tooling, all surface that depends on the
  representation (`RegFile`, `Index`, `IsLabel`, `(!)`) is small enough to retarget
  without touching `Term`/`OutTerm`/`Update`. (2026-05-01)

- **Cross-cutting concern for EP-2 (schema evolution).** The hidden-input check is
  exactly the lever schema evolution will use to detect "this register cannot be
  reconstructed from the new event shape". EP-2 should reuse the
  `solveOutput`/structural-`OPack` machinery rather than introduce a parallel check.
  Recommendation: EP-2's plan should cite this design note's "OutTerm and the inversion
  contract" section as the basis for any per-edge replay-compatibility check.
  (2026-05-01)

- **Cross-cutting concern for EP-3 (effects boundary).** The `mkOut`/`OFn` escape hatch
  is structurally analogous to where a v2 effects boundary would mark an edge as "this
  output is produced by an external effect, not a pure transducer". If EP-3 introduces
  an effect-marker on edges, it should align with the `OFn` constructor or extend
  `OutTerm` with an explicit `OEffect` constructor — not introduce a third path to
  "non-invertible output". Recommendation: EP-3 should consume the same `OutTerm`
  constructor set this note defines and add to it rather than parallel it. (2026-05-01)

- **Cross-cutting concern for EP-4 (the prototype itself).** The Prototype
  Implementation Checklist at the bottom of the design note is the hand-off contract.
  Every type, instance, helper, evaluator, and the hidden-input check are enumerated.
  EP-4 should not need to make further design decisions; if it discovers it does, that
  is a discovery worth surfacing in EP-4's Surprises & Discoveries section and back to
  this note for revision. (2026-05-01)


## Decision Log

Record every decision made while working on the plan.

- Decision: This plan produces a design note, not Haskell code.
  Rationale: The prototype lives in plan 4
  (`docs/plans/4-prototype-symbolic-register-core-with-user-registration-smoke-test.md`).
  Shipping concrete code here would conflate "is the DSL tolerable on paper" with "does
  the prototype compile" — each is a separate validation. Writing the DSL down in prose
  with type sketches first lets the prototype focus on implementing a known target.
  Date: 2026-04-30

- Decision: The local-survey requirement for `vinyl`, `large-records`, `extensible`, and
  `superrecord` is downgraded to "published-docs survey".
  Rationale: `mori registry search` returned no projects for any of the four packages
  (verified 2026-05-01). The user's global instructions forbid searching `/nix/store`,
  so on-disk source for those libraries is not available within the agent's
  permissions. The design note states this constraint explicitly in §"Survey of RegFile
  representations" and the survey reflects current public Hackage API documentation.
  The conclusion is robust against the limitation because the chosen representation
  (hand-rolled GADT) depends on none of the four candidates.
  Date: 2026-05-01

- Decision: `RegFile` representation is a hand-rolled GADT on `[(Symbol, Type)]` (not
  `vinyl`, not `extensible`, not `superrecord`, not `large-records`).
  Rationale: zero dependency footprint, full control over the type-level list shape,
  hand-written `IsLabel` for `OverloadedLabels` is small (~10 lines), and the
  direction-C note explicitly recommends this for v1. The `vinyl` alternative is the
  only credible competitor on tooling, but its dependency cost is non-trivial for a
  foundation library, and the User Registration example (5 slots) does not stress
  hand-written boilerplate. v2 swap to `vinyl` is mechanical because only `RegFile`,
  `Index`, `IsLabel`, and `(!)` depend on the representation; `Term`/`OutTerm`/`Update`
  are parametric.
  Date: 2026-05-01

- Decision: `OutTerm` shape is structural `Pack`-based (`OPack ctor fields`), with a v1
  escape hatch `OFn` for opaque function-style outputs.
  Rationale: structural `Pack` gives `solveOutput` a concrete AST node to walk
  (constructor tag plus per-field `Term`s); this is what makes the hidden-input check
  operational. `Generic`-driven `OutTerm` is heavier machinery for v1 with no v1 win,
  and it can be layered on top in v1.5 by deriving `WireCtor`s from a `Generic`
  representation. The `OFn` escape hatch is necessary in v1 because the User
  Registration aggregate has at least one output (`mkOut $ \regs (FulfillGDPRRequest d)
  -> AccountDeleted ...`) that needs to read the input record's field, and v1's `inp`
  is also opaque, so a fully structural transcription would require either v1 to ship
  `TInpProj` or to hand-write `WireCtor`s for every event. v1 ships `OFn` and pays the
  cost in the form of "the hidden-input check warns about every `OFn` edge"; v2 retires
  `OFn` along with `TInpField` together (they are dual sides of the same opacity).
  Date: 2026-05-01

- Decision: `Term`'s input access in v1 is `TInpField :: (ci -> r) -> Term rs ci r`
  (opaque function), with v2 replacing it with `TInpProj :: Lens' ci r -> Term rs ci r`
  (or a `Generic`-derived selector).
  Rationale: same opacity trade-off as `OFn`. v1 ships `TInpField` because writing a
  hand-rolled lens or `HasField` instance per command-payload field is more boilerplate
  than the smoke test can afford; v2 retires it for the hidden-input check to have full
  bite. The two opacities (`TInpField` and `OFn`) are flagged together in the Prototype
  Implementation Checklist's "v1-only surfaces" subsection.
  Date: 2026-05-01

- Decision: The "distinct targets" invariant on `UCombine` is enforced at runtime via a
  `combine :: Update rs ci -> Update rs ci -> Either String (Update rs ci)` smart
  constructor, with an `unsafeCombine :: ... -> ... -> Update rs ci` infix helper for
  call-sites where the author is confident.
  Rationale: type-level enforcement would require carrying the set of written register
  indices in the type of `Update`, which is implementable but intrusive (every
  `Update`-valued helper has to thread the set), and v1 has no SMT to discharge
  membership constraints automatically. A runtime check + a property test that
  exercises every `userReg` definition is the v1-shippable answer; v2's smart
  constructor enforcement (synthesis §7) takes over when the type machinery to do it
  cleanly is in place.
  Date: 2026-05-01

- Decision: `BoolAlg HsPred` instance has `sat _ = Nothing` in v1.
  Rationale: v1 ships without an SMT solver; symbolic satisfiability is impossible.
  The synthesis §7 plan is to use Hedgehog generators for v1 single-valuedness checks;
  `sat` returning `Nothing` is honest about the v1 limitation rather than pretending to
  enumerate. v2's SBV-backed instance implements `sat` properly.
  Date: 2026-05-01

- Decision: The v1 escape hatches `matchCmd`, `mkOut`, `inp`, `unsafeCombine` are
  documented as v2-retirement targets, not removed from v1.
  Rationale: removing them would block the User Registration smoke test, which needs at
  least one of each to compile. They are flagged in §"Ergonomic helpers" as v1-only and
  in the Prototype Implementation Checklist's "v1-only surfaces" subsection so the v2
  plan author can find them. The pain caused by `inp`'s total-callback boilerplate is
  the largest specific ergonomic pain point and EP-4's smoke test will demonstrate the
  pain concretely so v2's priority is clear.
  Date: 2026-05-01

- Decision: The User Registration domain types include an internal `Continue`
  constructor in `UserCmd`, which synthesis §4 only references in pseudosyntax.
  Rationale: synthesis §4's `Registering -> RequiresConfirmation` edge writes
  "internal Continue command emits the second event" and uses `\Continue -> True` as
  the guard. To transcribe the edge in concrete DSL the constructor has to exist
  somewhere; adding it to `UserCmd` is the lightest change. This is documented in IP-1
  for the prototype to acknowledge. v2 may model the ε-edge differently (e.g. a
  per-vertex internal-input alphabet) but v1 takes the simple route.
  Date: 2026-05-01


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

### 2026-05-01 — Milestone 1 complete

The design note exists at `docs/research/dsl-shape-for-symbolic-register.md`
(11 sections, all named DSL terms cross-referenced). Every open question listed in the
plan's "What this plan must settle" is resolved with rationale: `RegFile` is a
hand-rolled GADT on `[(Symbol, Type)]`; `Term` has `TLit`/`TReg`/`TInpField` plus
`TApp1`/`TApp2`; `OutTerm` is structural `OPack` with a v1 `OFn` escape hatch;
`Update` uses `UKeep`/`USet`/`UCombine` with a runtime-checked `combine` smart
constructor; `HsPred` is the small AST `PTop`/`PBot`/`PAnd`/`POr`/`PNot`/`PEq`/`PMatchC`;
the `BoolAlg HsPred` instance is fully sketched (`sat = Nothing` in v1); ergonomic
helpers `matchCmd`, `mkOut`, `proj`, `inp`, `lit`, `(!)`, `(.==)`, `combine`,
`unsafeCombine`, `pack` all have concrete signatures.

The User Registration aggregate transcribes in the chosen DSL with two structural
divergences from synthesis §4 — the total-callback padding on `inp` (IP-1) and the
all-`OFn` outputs that block the hidden-input check on the example (IP-2). Both
divergences have v2 fixes specified in the design note.

**Ergonomic verdict: painful but workable.** The pain is real (every `inp` callback is
~6 lines instead of 1) and concentrated in three v1 escape hatches (`inp`, `mkOut`,
`matchCmd`). It is not blocking: the transcription compiles in the writer's head, all
constructors are defined, and EP-4 has an unambiguous target. The verdict argues for
v2 to prioritize structural input projection (`TInpProj`) as its first ergonomic
cleanup; this is the single largest pain point and the same change retires the v1
hidden-input-check limitation on `OFn` outputs.

The Prototype Implementation Checklist enumerates 11 datatypes/typeclasses, 10 helpers,
6 evaluators, and the build-time `solveOutput` plus hidden-input check, with explicit
flags on which surfaces are v1-only. EP-4 should not need to make further design
decisions; if it does, that's a discovery worth surfacing back here.

The cross-cutting concerns surfaced for siblings: EP-2 (schema evolution) should reuse
the `solveOutput`/structural-`OPack` machinery rather than introduce a parallel
replay-compatibility check; EP-3 (effects boundary) should align with the `OFn`
constructor or extend `OutTerm`'s constructor set rather than introduce a third path
to "non-invertible output". Both are recorded in Surprises & Discoveries above for the
master plan to absorb.

### Pain points the prototype should anticipate

- Hidden-input check warning fires on every edge of the User Registration aggregate as
  written, because every output is `OFn`. EP-4 must build at least one structural
  `OPack` (recommendation: `RegistrationStarted`) to demonstrate the check has bite on
  the synthesis §4 step-4 schema bug.
- The `\case ... _ -> error "guard"` padding on `inp` callbacks is correct but ugly.
  EP-4's smoke test should not refactor this — the ugliness is the v2-priority signal.
- `unsafeCombine` is used in the transcription. EP-4 must include a Hedgehog property
  test that verifies no `userReg`-built `UCombine` overlaps; that test is the v1
  substitute for type-level distinct-targets enforcement.


## Context and Orientation

The keiki repository currently contains no Haskell code. The directory layout is:

    docs/
      foundations/    team onboarding (problem space, vocabulary)
      research/       design notes for the library itself
    docs/masterplans/   coordination plans
    docs/plans/         execution plans (this is one)
    agents/skills/      tooling for plan creation (do not edit)
    .agents/  .seihou/  .claude/  internal tooling, ignore

The two essential reads before starting are, in order:

1. `docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md` —
   the working baseline for the formalism. The headline is **"C is the formalism, B is an
   optional presentation layer."** §2 contains the type sketch this plan must concretize.
   §3 covers the optional indexed-state views (out of scope for this plan). §4 is the
   User Registration aggregate the prototype will smoke-test (also the reference example
   for ergonomic evaluation in this plan). §7 settles the predicate-carrier question
   (first-class AST in v1). §8 is the sequenced next-step list — step 1 is what this plan
   helps deliver.
2. `docs/research/data-direction-c-symbolic-and-register-automata.md` — the direction-C
   note that the synthesis is built on. Read for the rationale behind copyless updates,
   single-valuedness, and the hidden-input check.

Optional but useful:

- `docs/research/data-direction-b-indexed-state-per-vertex.md` — the per-vertex GADT
  presentation. The B-view is opt-in and **out of scope for this plan**, but its
  ergonomic motivation informs why naming matters in the DSL surface.
- `docs/foundations/00-reading-guide.md` and `docs/foundations/01-problem-space.md` —
  background on why this formalism is being built at all.

### Terms used in this plan

- **Symbolic-register transducer**: the chosen formalism. State is `(s, RegFile rs)` where
  `s` is a finite control vertex (an enumeration) and `RegFile rs` is a heterogeneous
  typed record indexed by `rs :: [Type]` (or a label-and-type list). Edges combine guard,
  update, output, and target into one value.
- **Edge**: a single transition. Carries `guard :: phi`, `update :: Update rs ci`,
  `output :: Maybe (OutTerm rs ci co)`, `target :: s`. `Nothing` output is the ε-edge
  (consumes input, produces no event).
- **`phi`**: the carrier of guards (predicates over `(RegFile rs, ci)`). The class
  `BoolAlg phi a` makes it an effective Boolean algebra: `top`, `bot`, `conj`, `disj`,
  `neg`, `models phi a -> Bool`, `sat phi -> Maybe a`, `isBot phi -> Bool`. v1 instance:
  Haskell function on `(RegFile rs, ci)`. v2 instance: SBV-backed AST.
- **`Term rs ci r`**: pure expression yielding a value of type `r`, with reads from the
  register file `rs` and the input `ci`. Used in `Set` updates.
- **`OutTerm rs ci co`**: pure expression yielding an output value `co` (an event or
  command), again reading from `rs` and `ci`. Distinguished from `Term` because it must
  be **invertible** for `solveOutput` to derive `apply`.
- **`Update rs ci`**: copyless update language; `Keep` (no change), `Set` (write one
  register from a `Term`), `Combine` (sequence two updates with distinct targets).
- **`Index rs r`**: a type-safe pointer into `rs` for a value of type `r`. The synthesis
  note uses `OverloadedLabels` syntax (`#email`) for these.
- **`solveOutput`**: a derived function that, given an `OutTerm` and an observed output
  value `co`, recovers the input `ci` (and any read-from-register dependencies). It is
  the linchpin of mechanical `apply` derivation. It only works when the output term is
  invertible in the input fields — a property the **hidden-input check** verifies at
  build time.
- **Hidden-input check**: a static analysis that flags edges where `update` or `guard`
  reads an input field (`ci.<field>`) that does not appear in `output`. If such an edge
  exists, `apply` cannot be derived for it. Synthesis §4 walks through a real instance.
- **Single-valued transducer**: at most one edge whose guard is satisfied for any given
  `(state, regs, input)`. Required for `delta`/`omega` to be well-defined. v1 enforces it
  by Hedgehog property test; v2 by smart constructors (per synthesis §7).
- **Wire types**: the JSON / queue / event-store shapes for commands and events. Per the
  synthesis: ordinary sum types with payloads, no indexing. Out of scope for this plan;
  important only as the eventual consumer of the output of the chosen DSL.

### What the synthesis note already settles (do not re-litigate)

- C is the formalism, B is opt-in presentation.
- Predicate carrier in v1 is a first-class AST (option b in §7).
- Single-valuedness is a property test in v1, smart-constructor enforcement in v2.
- v1 ships without SBV; an SBV-backed `BoolAlg` instance is v2.

### What this plan must settle

- Concrete Haskell datatype declarations for `Term`, `OutTerm`, `Update`, `Edge`,
  `SymTransducer`. These were sketched at a high level in synthesis §2 but the
  constructors of `Term` and `OutTerm` were left as `data Term  (rs :: [Type]) (ci :: Type) (r :: Type)`
  with no constructors named.
- The concrete shape of `RegFile rs` and `Index rs r`. Synthesis §2 says "Typed
  heterogeneous register tuple" without committing to `vinyl` vs hand-rolled.
  Synthesis §8 step 1 explicitly defers this: *"Decide concretely whether the register
  file is hand-rolled GADT or `vinyl`."*
- The shape of `phi` (the predicate AST) and the constructors of its v1 instance. The
  synthesis says first-class AST but does not give the constructor names.
- The user-facing helpers — `matchCmd`, `mkOut`, `proj`, the `OverloadedLabels`
  treatment of register names — that synthesis §4 uses pseudosyntactically.

### Tooling

The user's global instructions require using `mori` to find dependency source code and
docs:

- `mori registry list` — discover registered projects.
- `mori registry search <package>` — find packages.
- `mori registry show <project> --full` — source paths and metadata.
- `mori registry docs <project>` — curated guides.

For this plan, use `mori` to read the actual hackage source of `vinyl`,
`large-records`, `extensible`, and `superrecord` before picking. **Never search
`/nix/store`.**


## Plan of Work

The work is a single milestone — produce a design note. Within the milestone, proceed
top-down: pick foundational shapes first (RegFile, Index), then build up (Term, OutTerm,
Update, Edge), then ergonomic helpers, then transcribe the User Registration aggregate
to stress-test the choices.

### Milestone 1 — Author the DSL design note

**Scope:** produce a single Markdown document at
`docs/research/dsl-shape-for-symbolic-register.md` that fully specifies the DSL surface
and AST and validates it by transcribing the User Registration aggregate.

**What will exist at the end:** a design note that the prototype plan
(`docs/plans/4-prototype-symbolic-register-core-with-user-registration-smoke-test.md`)
can implement directly without further design questions — every type signature, every
constructor, and every ergonomic helper is named.

**Sub-steps in order:**

1. **Survey RegFile representations.** Use `mori registry search vinyl`, `mori registry
   show vinyl --full`, and read `Data.Vinyl.Core` and `Data.Vinyl.Lens` directly. Repeat
   for `large-records` (`Data.Record.Generic`), `extensible` (`Data.Extensible.Record`),
   and `superrecord` (`SuperRecord.Field`). For each, note: how a record value is
   constructed, how a label-indexed lookup looks at the call site, support for
   `OverloadedLabels`, and whether the type-level list is `[Symbol :-> Type]` (named) or
   `[Type]` (unnamed). The synthesis sample uses named slots
   (`'[ "email" ':-> Email, … ]`), so prefer libraries that support that natively.
   Capture findings in a short comparison table inside the design note.

2. **Pick a RegFile representation.** State the choice and justify it against four
   criteria: (a) the User Registration example reads naturally; (b) `Set #email term`
   compiles with a clear error if the term type doesn't match the slot; (c) the
   representation can be evaluated at runtime without TH (because the prototype is
   intentionally minimal); (d) zero-runtime-overhead reads are not a v1 requirement.
   Tentatively the strong candidate is **hand-rolled GADT with a type-level
   `[(Symbol, Type)]`** — minimal dependency footprint, total control, and the synthesis
   already implies this shape — but `vinyl` may win on existing tooling. Pick one and
   write a Haskell sketch of it.

3. **Sketch `Index rs r`.** Define `data Index rs r where ZIdx :: Index ('(s, t) ': rs) t;
   SIdx :: Index rs t -> Index ('(s', t') ': rs) t` (or analogous) and an
   `IsLabel s (Index rs t)` instance so users can write `#email` instead of
   `SIdx (SIdx ZIdx)`. Show a worked indexing example.

4. **Sketch `Term rs ci r`.** Decide which constructors are needed for v1. Minimum
   candidates from the User Registration aggregate's actual usage:

       data Term rs ci r where
         Lit    :: r -> Term rs ci r
         Reg    :: Index rs r -> Term rs ci r              -- read register
         Inp    :: (ci -> r) -> Term rs ci r               -- read field of input
         App2   :: (a -> b -> r) -> Term rs ci a -> Term rs ci b -> Term rs ci r
         -- more if needed; aim for as small a vocabulary as possible

   The `Inp` constructor with an opaque `ci -> r` is the v1 pragmatic choice (per
   synthesis: "in v1, from plain Haskell functions over the typed register file"). For
   v2, `Inp` would be replaced by structural projection (`InpField :: Lens' ci r ->
   …`) so the AST stays inspectable. Document this trade-off in a Decision Log entry.

5. **Sketch `OutTerm rs ci co`.** This is the hard one because it must be invertible.
   Two leading options:

   - **Structural OutTerm with explicit constructors per output shape.** A `Pack`
     constructor that takes a wire-type tag and a list of `Term`s for each field, so the
     AST can be walked to produce both the forward evaluator and the inverse mapping
     `co -> Maybe ci`.
   - **Generic-driven OutTerm.** Use `GHC.Generics` to derive the field structure of the
     output sum and a corresponding `OutTerm` shape. Heavier machinery but less manual
     bookkeeping.

   Pick one for v1, write the sketch, and explicitly call out how `solveOutput` walks
   the AST to recover `ci`. This is the second hard-defer in synthesis §8 step 1. The
   minimum must be: given an `OutTerm rs ci co` and a value `co`, return either
   `Maybe ci` or a richer `Either HiddenInput ci` so the build-time check has something
   to grab.

6. **Sketch `Update rs ci`.** Reproduce the synthesis §2 declaration (Keep / Set /
   Combine) and add the "Combine has distinct targets" invariant. Explain how the
   prototype enforces that — at the type level if possible, otherwise as a smart
   constructor that returns `Maybe (Update rs ci)` and is paired with a runtime check.
   v1 may use a runtime check; document it.

7. **Sketch `Edge phi rs ci co s` and `SymTransducer phi rs s ci co`.** These are
   essentially copied verbatim from synthesis §2; reproduce them in the design note for
   self-containment. Add the type signatures of the projections `delta`, `omega`,
   `runUpdate`, `evalTerm`, `evalOut`, `models`.

8. **Pin the predicate carrier `phi`.** v1 carrier choice from synthesis §7 is "first-class
   AST." Define the constructors:

       data HsPred rs ci where
         PTop    :: HsPred rs ci
         PBot    :: HsPred rs ci
         PAnd    :: HsPred rs ci -> HsPred rs ci -> HsPred rs ci
         POr     :: HsPred rs ci -> HsPred rs ci -> HsPred rs ci
         PNot    :: HsPred rs ci -> HsPred rs ci
         PEq     :: Eq r => Term rs ci r -> Term rs ci r -> HsPred rs ci
         PMatchC :: (ci -> Bool) -> HsPred rs ci   -- escape hatch v1; remove in v2

   Justify each constructor against an actual edge in the User Registration aggregate.
   The `PMatchC` escape hatch is what `matchCmd \(StartRegistration _) -> True` desugars
   to in v1; v2 should replace it with structural pattern AST.

9. **Define the ergonomic helpers.** For each pseudosyntactic helper used in synthesis §4,
   write a concrete signature:

       matchCmd :: (ci -> Bool) -> HsPred rs ci
       mkOut    :: (RegFile rs -> ci -> co) -> OutTerm rs ci co     -- v1 opaque; v2 structural
       proj     :: Index rs r -> Term rs ci r                       -- alias for Reg
       inp      :: (ci -> r) -> Term rs ci r                        -- alias for Inp
       (!)      :: RegFile rs -> Index rs r -> r                    -- runtime lookup

   Document which helpers are v1-only (because they leak Haskell functions into the AST
   and so block the v2 hidden-input check) and which are stable.

10. **Transcribe the User Registration aggregate.** Take synthesis §4's transducer block
    (the `userReg` value definition) and rewrite it using the concrete DSL from steps
    1–9. **No pseudosyntax.** Every constructor must be one defined above. Read the
    result and ask: would I write this if I were modelling a new aggregate? If not,
    iterate. Capture surprises in the Surprises & Discoveries section of this plan.

11. **Write a "Prototype Implementation Checklist"** at the end of the design note,
    listing every type, constructor, type-class instance, and helper the prototype plan
    must implement. This is the hand-off contract.

12. **Cross-check ergonomic acceptability.** The design note must explicitly state
    whether the DSL is judged tolerable. If something is on the borderline, list the
    specific concern and the v2 fix. The master plan's acceptance criterion is "AST
    surface ergonomics tolerable AND solveOutput works on the example" — this plan owns
    the first half.

**Acceptance:** the design note exists at the path above, the User Registration
aggregate appears verbatim in it using only concrete DSL constructors, every open DSL
question listed in synthesis §8 step 1 is resolved with rationale, and the Prototype
Implementation Checklist is complete.

**Commands to verify:**

    test -f docs/research/dsl-shape-for-symbolic-register.md && echo "design note present"

    grep -c '^## ' docs/research/dsl-shape-for-symbolic-register.md
    # expect a non-trivial number of sections (at least 8)

    grep -E '(matchCmd|mkOut|userReg|RegFile|Edge)' docs/research/dsl-shape-for-symbolic-register.md | head
    # expect to see all the named DSL terms appear at least once


## Concrete Steps

All work happens at the repository root: `/Users/shinzui/Keikaku/bokuno/keiki`.

1. Read the synthesis note in full:

       cat docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md

2. Read the direction-C note for context on copyless updates and the hidden-input check:

       cat docs/research/data-direction-c-symbolic-and-register-automata.md

3. Survey RegFile candidates with `mori`:

       mori registry search vinyl
       mori registry show vinyl --full
       mori registry search large-records
       mori registry show large-records --full
       mori registry search extensible
       mori registry show extensible --full
       mori registry search superrecord
       mori registry show superrecord --full

   For each that exists in the local registry, follow the `source-paths` field to read
   the actual hackage source on disk. Capture (a) record construction, (b) field lookup,
   (c) `OverloadedLabels` support, (d) type-level list shape.

4. Open a draft of the design note. Use the structure:

       # DSL shape for the symbolic-register transducer

       ## Inputs and prerequisites
       (recap synthesis §2 in 1-2 paragraphs; link to source notes)

       ## Open questions this note resolves
       (the list from "What this plan must settle" above)

       ## RegFile and Index
       (survey + decision + sketch)

       ## Term, Update, Edge, SymTransducer
       (sketches with type signatures)

       ## OutTerm and the inversion contract
       (sketch + how solveOutput walks it; v1 vs v2 trade-offs)

       ## Predicate carrier (HsPred)
       (constructors + BoolAlg HsPred instance signature)

       ## Ergonomic helpers
       (matchCmd, mkOut, proj, inp, (!), and any others)

       ## Worked example: User Registration
       (transcription with no pseudosyntax)

       ## Ergonomic verdict
       (tolerable / pain points / what v2 fixes)

       ## Prototype Implementation Checklist
       (the hand-off list)

5. Write the note.

6. Run the verification commands from Milestone 1 acceptance.

7. Commit:

       git add docs/research/dsl-shape-for-symbolic-register.md \
               docs/plans/1-sharpen-dsl-shape-for-symbolic-register-transducer.md \
               docs/masterplans/1-validate-symbolic-register-direction-via-haskell-prototype.md
       git commit -m "$(cat <<'EOF'
       docs(research): sharpen DSL shape for symbolic-register transducer

       Pick concrete constructors for Term, OutTerm, Update, Edge, and the
       predicate carrier, settle the RegFile representation, and transcribe
       the User Registration aggregate in the chosen DSL to validate ergonomics.

       MasterPlan: docs/masterplans/1-validate-symbolic-register-direction-via-haskell-prototype.md
       ExecPlan: docs/plans/1-sharpen-dsl-shape-for-symbolic-register-transducer.md
       Intention: intention_01knjzws4qezz9w8b0743zfqv8
       EOF
       )"

   The commit message must contain all three trailers shown.

8. Update this plan's living sections (Progress, Surprises & Discoveries, Decision Log,
   Outcomes & Retrospective). Update the master plan's Exec-Plan Registry to mark this
   plan Complete, and the Progress section to check off this plan's milestone. Commit
   that as a follow-up if needed (with the same trailers).


## Validation and Acceptance

The acceptance is a written deliverable, not an executable, so validation is by reading
the design note against this checklist:

1. **Self-containment.** A reader who has read only the synthesis note and direction-C
   note can implement the DSL from this design note. No further design questions.
2. **No pseudosyntax in the worked example.** Every constructor used in the User
   Registration transcription is defined in the same document.
3. **Ergonomic verdict is explicit.** The note states "tolerable" or names specific pain
   points with v2 fixes.
4. **Prototype Implementation Checklist** lists every type, instance, and helper the
   prototype must produce. The checklist is the hand-off contract for plan 4.
5. **Open questions from synthesis §8 step 1 are resolved**: register-file representation
   chosen with rationale, ergonomic surface for `matchCmd`/`mkOut`/`proj` defined.

A non-author reviewer should be able to take the Prototype Implementation Checklist and
draft module signatures from it without referring back to other notes.


## Idempotence and Recovery

This plan produces a single Markdown file. All steps are repeatable: re-running `mori`
queries is safe; rewriting the design note is safe; iterating on the User Registration
transcription is the expected workflow. If the design note already exists when work
resumes, read it, find the first incomplete section, and continue.

If a chosen RegFile representation turns out to be untenable while transcribing User
Registration (step 10 of Milestone 1 reveals a structural problem), document the
discovery in Surprises & Discoveries, revise the choice in step 2, and re-transcribe.
This is expected design churn.


## Interfaces and Dependencies

This plan does not touch any code, only Markdown. Its outputs are consumed exclusively
by `docs/plans/4-prototype-symbolic-register-core-with-user-registration-smoke-test.md`,
which implements the chosen DSL.

Inputs (do not modify, only read):

- `docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`
- `docs/research/data-direction-c-symbolic-and-register-automata.md`
- `docs/research/data-direction-b-indexed-state-per-vertex.md` (optional)
- `docs/foundations/00-reading-guide.md`, `docs/foundations/01-problem-space.md` (optional)

Outputs:

- `docs/research/dsl-shape-for-symbolic-register.md` — new design note.
- This plan's living sections, kept current.
- The master plan's Exec-Plan Registry and Progress section, updated on completion.

Tooling required:

- `mori` for hackage dependency surveys (per the user's global instructions). **Never
  search `/nix/store`.**
- `git` for commits with the required trailers (`MasterPlan:`, `ExecPlan:`,
  `Intention:`).

No build system, no compiler, no Haskell toolchain needed for this plan — it is purely
design.
