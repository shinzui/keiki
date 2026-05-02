---
id: 7
slug: multi-event-command-support-gsm-widening-vs-state-refinement-ergonomics
title: "Multi-event command support: GSM widening vs state-refinement ergonomics"
kind: master-plan
created_at: 2026-05-02T14:51:23Z
intention: "intention_01kqmjp9k8e478db6xjah31455"
---

# Multi-event command support: GSM widening vs state-refinement ergonomics

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Vision & Scope

The keiki library currently models its core formalism as a *letter Finite
State Transducer* (letter FST): every edge of a `SymTransducer` produces
zero or exactly one observable event. This is the shape committed to in
`docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`,
the working baseline of the project, which names letter FST as the
foundation. The relevant declaration is
`src/Keiki/Core.hs:411-419`:

    data Edge phi rs ci co s = Edge
      { guard  :: phi
      , update :: Update rs ci
      , output :: Maybe (OutTerm rs ci co)   -- Nothing = ε; Just o = one event
      , target :: s
      }

A command that semantically produces two or more events on a single input —
the canonical example is `StartRegistration` in
`src/Keiki/Examples/UserRegistration.hs`, which logically emits both
`RegistrationStarted` and `ConfirmationEmailSent` — is handled today via
*state refinement*: an intermediate vertex (`Registering`) and a
synthetic internal command (`Continue`) chain the events as a sequence
of letter edges. The aggregate's vertex enum and command enum each
carry one extra constructor per multi-event command.

The library needs to make multi-event commands ergonomic. There are
exactly two viable directions, both fully fleshed out in child
ExecPlans below:

- *Path A (EP-19) — GSM widening.* Generalize the AST so multi-event
  is first-class: widen `Edge.output` from `Maybe (OutTerm rs ci co)`
  to `[OutTerm rs ci co]`. Length-0 reproduces ε, length-1 reproduces
  today's letter behavior, length-2+ admits multi-event commands
  directly. Composition concatenates output lists; `omega` returns
  `[co]`; replay through length-2+ edges streams through a wrapped
  `InFlight s co` state for runtimes without command boundaries. The
  formalism shifts from strict letter FST to GSM (Generalized
  Sequential Machine).

- *Path B (EP-20) — state-refinement ergonomics.* Keep the AST as a
  strict letter FST. Add three pieces of ergonomic support:
  `Keiki.Core.applyEvents` (chunk-replay over a letter chain
  corresponding to one logical command); `Keiki.Decider.DriverConfig`
  + `Keiki.Decider.toMultiDecider` (a façade whose `decide` drives
  letter chains end-to-end through user-declared internal vertices,
  collecting events transparently); `Keiki.Builder.chainTo` (a new
  builder DSL verb that compiles a multi-`emit` block to a chain of
  letter edges through user-named intermediates). The user declares
  intermediate vertices and internal commands as today; the library
  handles driver chaining and authoring sugar.

  Plan 15
  (`docs/plans/15-edge-builder-monadic-dsl-for-authoring-symtransducer-edges.md`)
  shipped on 2026-05-02 with all milestones complete; `Keiki.Builder`
  exports `buildTransducer`, `from`, `onCmd`, `onEpsilon`, `(.=)`,
  `slot`, `emit`, `emitWith`, `noEmit`, `goto`, `requireEq`,
  `requireGuard`. Both example aggregates
  (`Keiki.Examples.EmailDelivery`, `Keiki.Examples.UserRegistration`)
  are now in builder form, with the AST form preserved as
  `emailDeliveryAST` and `userRegAST` for cross-form equivalence
  testing. EP-20's M5 (`chainTo`) extends this builder; the
  soft-dependency on Plan 15 documented in earlier drafts of this
  MasterPlan is now satisfied.

Both paths yield identical user-visible decider behavior on
multi-event commands. The choice is between *where the semantic
complexity lives*: in the AST itself (Path A) or in user-declared
intermediate state plus authoring/runtime helpers (Path B).

This MasterPlan ships both as fully-fleshed ExecPlans so the user can
decide after detailed review. **The MasterPlan recommends Path B
(EP-20).** Three reinforcing reasons:

1. **Theoretical soundness.** The synthesis foundation note's §1
   names mechanical `apply` derivation as "the decisive technical
   win" of the symbolic-register formalism. That win, plus the
   build-time hidden-input check
   (`Keiki.Core.checkHiddenInputs`), plus the symbolic-emptiness
   story over `Keiki.Symbolic.HsPred`, all rest on the letter
   property: one `OutTerm` per edge, decidable per-edge. Widening
   to GSM does not invalidate these but moves the analyses from
   per-edge to per-edge-list. The hidden-input check, in particular,
   weakens from "this `OutTerm` recovers its input" to "the *union*
   of `OutTerm`s on this edge recovers the input," which couples
   the analysis across the list and is harder to discharge cleanly
   under composition.

2. **Future-facing alignment.** Two specific future capabilities
   benefit from letter FST: (a) diagram generation, where each edge
   renders as one labeled arrow `c / e` — multi-event edges either
   render as multi-line labels (visually noisy, the reader can't see
   where each event lands) or synthesize anonymous intermediate
   nodes that diverge from the AST. (b) a future move toward
   dependent-typing, where edges are indexed by the event
   constructor they emit (`Edge from to cmdCtor (eCtor :: Maybe
   Symbol)`) — list-output edges turn this into `[Symbol]` with
   per-edge analyses becoming quantification over the list.

3. **Realistic distribution.** The user reports that 1–2 events per
   command is the norm; commands with three or more events are rare
   (the canonical exotic case is a property-sync command emitting up
   to 12 conditional events, and even that decomposes more cleanly
   into 12 disjoint-guarded edges than into one length-12 edge). At
   the realistic distribution, Path B's cost is one intermediate
   vertex and one internal command per length-2 command —
   manageable, and the `chainTo` DSL verb compresses authoring
   further.

The MasterPlan is *decision-shaped*, not pipeline-shaped. **Only one
of the two child plans will be implemented.** The other will be
marked Cancelled in the Exec-Plan Registry once the user chooses,
with a Decision Log entry recording the choice and rationale. Both
child plans are written as fully-implementable so the user can
review them in detail before deciding.

Out of scope for this MasterPlan:

- Approach 3 from
  `docs/research/multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md`
  (direct MultiDecider with hand-written `apply`). Excluded because
  the synthesis foundation rejects it — surrendering apply
  derivation is exactly what the formalism exists to prevent.
- The runtime side of multi-event commands (event-store batching,
  transaction boundaries, idempotency keys, retry semantics).
  keiki is the pure core; the runtime adapter handles those.
- A new "GSM" formalism module parallel to `Keiki.Core`. Both
  child plans extend or supplement the existing single AST;
  neither introduces a parallel core.


## Tradeoff Analysis (retrospective, augmented 2026-05-02)

Vision & Scope's three-reason argument — theoretical soundness,
future-facing alignment, realistic distribution — was sufficient to
act on but undersold EP-19's genuine strengths and overstated one of
its weaknesses. This section augments Vision & Scope with six
dimensions of evaluation grounded in the actual code and plan
specifications. It does not reverse the shipped choice; it makes the
deliberation honest in the project history. The shipped path (EP-20)
remains the right call for the reasons in the closing verdict, but
the analysis surfaces real costs EP-20 carries that the original
Vision & Scope did not name.


### 1. Authoring ergonomics — side by side

The canonical multi-event command is `StartRegistration →
[RegistrationStarted, ConfirmationEmailSent]`. Under each path, here
is the literal authoring shape in the builder DSL.

EP-19 (multi-emit, never implemented):

    from PotentialCustomer $ B.onCmd inCtorStart $ do
      email       .= inpStart #email
      confirmCode .= inpStart #confirmCode
      emit wireRegistrationStarted
        (inpStart #email *: inpStart #confirmCode *: inpStart #at *: oNil)
      emit wireConfirmationEmailSent
        (inpStart #email *: oNil)
      goto RequiresConfirmation

EP-20 (`chainTo`, shipped at `src/Keiki/Builder.hs:443-448`):

    from PotentialCustomer $ B.onCmd inCtorStart $ do
      email       .= inpStart #email
      confirmCode .= inpStart #confirmCode
      emit wireRegistrationStarted
        (inpStart #email *: inpStart #confirmCode *: inpStart #at *: oNil)
      B.chainTo Registering inCtorContinue
      emit wireConfirmationEmailSent
        (inpStart #email *: oNil)
      goto RequiresConfirmation

Inside the `from` block, EP-20 costs one extra line. The hidden cost
is naming: `Registering` must be a constructor of the user's `Vertex`
enum, `inCtorContinue` must reference an `InCtor` derived from a
`Continue` constructor in the user's `ci` enum, and both must appear
in `deriveAggregateCtors` and `deriveView` spec lists. Adding one
length-2 command costs roughly six lines of declarative overhead
*outside* the `from` block under EP-20; zero under EP-19.

For length-N commands the gap widens linearly: each additional event
inside one logical command needs one more intermediate vertex
constructor declared in the `Vertex` enum and one more `chainTo` call
(the `Continue` advancement command can be reused). Under EP-19,
additional events are additional `emit` calls and nothing else.

Verdict: EP-19 wins on byte-cost per multi-event command. EP-20's
`chainTo` compresses the in-block authoring well but leaves the
out-of-block declarations (vertex constructor, command constructor,
TH spec entries) as the load-bearing cost.


### 2. Cognitive surface — what a user must learn

EP-19 expands one concept and cascades it through the existing
operators: `Edge.output` becomes a list with three semantic cases
(length-0 = ε, length-1 = today's letter, length-≥2 = multi-event).
Composition concatenates lists. `omega` returns a list. Replay through
a length-≥2 edge needs an `InFlight` wrapper that the caller of
`applyEvent` sees in the type. Total: one new conceptual change with
four mechanical adaptations.

EP-20 adds three independent library surfaces: `Keiki.Core.applyEvents`
(chunk-replay primitive), `Keiki.Decider.DriverConfig` +
`Keiki.Decider.toMultiDecider` (façade with a per-aggregate
configuration value that must stay in sync with the `Vertex` enum),
and `Keiki.Builder.chainTo` (sugar that desugars to existing
primitives). Each surface is small and learnable on its own, but a
user who wants the full multi-event story must understand all three
plus the conceptual claim that intermediate vertices like `Registering`
are real states in their model even though no business event lives
there.

The "real state in your model" framing is a load-bearing modelling
claim, not a sugar artefact. Under EP-20 a user reading
`Keiki.Examples.UserRegistration` sees `Registering` in the `Vertex`
enum, in any future diagram, in the `View` projection, and in the
driver config. They have to learn that `Registering` is a synthetic
checkpoint with no intrinsic semantics beyond "between event 1 and
event 2 of one logical command." This is a real cognitive cost the
original Vision & Scope did not surface.

Verdict: EP-19 wins on conceptual count (one new idea vs three), but
the EP-19 idea (lists in `output`) reshapes the foundation. EP-20's
three ideas are each smaller and additive. The framing of the user's
state space — does it include synthetic checkpoints or not — is the
deeper cognitive choice; EP-20 says yes, EP-19 says no. Both are
defensible models.


### 3. State-space cost as commands grow

For a length-N multi-event command, EP-20 adds N−1 intermediate
vertex constructors and one advancement command constructor (the
`Continue` constructor is typically shared across all multi-event
commands in an aggregate). EP-19 adds nothing — the length-N edge has
output list of length N and no extra state.

For an aggregate with K length-2 commands sharing one `Continue`:
EP-20 adds K vertex constructors plus one `Continue` constructor.
EP-19 adds zero.

Vision & Scope dismisses the length-12 property-sync case by noting it
"decomposes more cleanly into 12 disjoint-guarded edges than into one
length-12 edge." That observation is correct but applies to *both*
paths equally: 12 disjoint-guarded letter edges from one source
vertex work fine under EP-20 (each is letter, no intermediates needed)
and under EP-19 (each is letter, length-1 output list). The
length-12-edge construction is a strawman — neither path actually
wants it.

So the realistic-distribution argument from Vision & Scope, on closer
look, only differentiates the paths for length-2 and length-3
commands where decomposition into disjoint edges is unnatural. There
the state-space cost gap is real: each length-2 command costs EP-20
one vertex constructor that EP-19 does not pay.

Verdict: EP-19 wins on state-space economy. The cost under EP-20 is
modest (one constructor per length-2 command, with derivation
overhead) but it is not zero, and the original Vision & Scope's
"manageable" framing buries the linear growth.


### 4. Composition under composeEdge

This dimension is the strongest hidden argument for EP-20 and was
not named in the original Vision & Scope.

Today's `Keiki.Composition.composeEdge` (at
`src/Keiki/Composition.hs:401-447`) takes one first-edge `e1` and
either drops it (ε-edge → `epsilonEdge`) or pairs it with each
second-edge `e2` whose guard accepts the produced mid-symbol via
`productEdge`. The result is a list of composed letter edges, one
per matching `e2`. `productEdge`'s output is `fmap (\o2 -> substOut
o2 o1) (output e2)` — a single `Maybe`.

Under EP-20, composition stays per-letter-edge throughout. A
multi-event chain in the first transducer
(`PotentialCustomer → Registering → RequiresConfirmation` via two
letter edges) composes by composing each letter edge against the
second transducer separately. The composed transducer has the same
chain shape with `Composite` source/target states; chain length grows
additively in composition, not multiplicatively. The existing
`composeEdge` works unchanged.

Under EP-19, composition of a length-2 first-edge is fundamentally
harder than composition of a letter edge. The first-edge produces two
mid-symbols `[o1a, o1b]`; the second transducer steps on `o1a` from
state `s2`, transitions to some `s2'`, then must step on `o1b` from
`s2'`. A single composed edge from `(s1, s2)` cannot express this —
its output list reflects T2's behaviour from `s2` for both events, but
T2's state changes between events. A sound composition must either:

- Restrict multi-event edges to those whose internal events all
  trigger the same downstream edge (severe restriction unlikely to
  hold in practice), or
- Internally expand multi-event edges into a chain of letter edges
  before composition (which *is* state refinement, performed by the
  library).

Either way, EP-19's plan M6 ("`composeEdge` adapts to compose
multi-event edges by concatenating output lists with the existing
`substOut` substitution applied to each") understates this. The
naïve concatenation works only when T2's transition on `o1a` lands
on a state from which `o1b` triggers the same edge T2 would have
taken from `s2` on `o1b` standalone. That is not a property the
type system enforces; it is an unstated invariant that breaks at
composition time under realistic T2 shapes.

Verdict: EP-20 wins decisively on composition. The reason is
structural: multi-event composition is not a closed operation on a
single edge. EP-20 keeps composition simple by keeping all edges
letter; EP-19 either restricts the multi-event class (losing
expressiveness) or hides chain expansion inside composition
(re-introducing state refinement under a different name).


### 5. Migration cost — what if we change later

If EP-20 ships and we later decide multi-event edges should be
first-class in the AST: add `output :: [OutTerm rs ci co]` (or a
parallel field) to `Edge`, adapt the ~24 call sites EP-19's M0
inventories, leave the shipped `chainTo` either as deprecated sugar
or re-target it to compile to a length-2 edge directly, retire
`DriverConfig` and `toMultiDecider` for the multi-event case (they
remain valid for genuine internal control vertices), shrink user
`Vertex` and `ci` enums where the intermediates collapse. The
shipped `applyEvents` stays valid in either world.

The reverse migration (EP-19 → EP-20) is harder. Collapsing back to
letter requires synthesising intermediate vertices for every
multi-event edge in every aggregate, naming them, threading them
through diagrams and projections, and hand-editing every consuming
spec. Tooling could automate the synthesis but the names are
load-bearing for the user's mental model and have to be chosen by
hand.

Verdict: EP-20 wins on migration optionality. The shipped path keeps
the door open to GSM widening later if real-world authoring pain
warrants it. EP-19 closes the door on returning to letter-FST-only.
This is the strongest conservative argument for EP-20 that Vision &
Scope did not name.


### 6. The hidden-input check — what the original argument got right and wrong

Vision & Scope claims widening "weakens the hidden-input check from
'this `OutTerm` recovers its input' to 'the *union* of `OutTerm`s on
this edge recovers the input,' which couples the analysis across the
list and is harder to discharge cleanly under composition." The
honest version is narrower.

The current `Keiki.Core.checkHiddenInputs` walks every edge of every
vertex, computes for each `OutTerm` which `InCtor` slots it visits,
and flags any slot read by guard or update that the visited set does
not cover. It is decidable per-edge because each edge has at most
one `OutTerm`.

Under EP-19, the check generalises to set-union over the edge's
output list: for each `InCtor` named in any `OPack` of the list, the
union of slots covered by the `OPack`s referencing that `InCtor`
must include every slot read by guard or update. This is still
decidable per-edge (set union and set difference are decidable). It
is not "weakened" in the rigorous sense — both versions catch every
genuinely hidden input.

What the generalised check loses is *edge-locality of the fix*.
Under EP-20's letter chain, the first edge of a multi-event command
has its own `update` and `output`, and the hidden-input check on
that edge fires if the update reads a slot not in the single output.
The user fixes it by adding a slot reference to that edge's emit.
Under EP-19, a hidden-input warning on a length-2 edge says "the
union of these two OPacks does not cover slot X read by update"; the
fix could be in either OPack, and the user has to choose where to
expose the slot. The check still fires; the fix is less locally
constrained.

The "harder to discharge cleanly under composition" claim is also
softer than Vision & Scope implies. Post-composition, the
composite's edges are still edges with output lists; the union check
on the composite's edges is the same set-union operation, decidable.
It is not "harder" in any algorithmic sense; it operates on possibly
longer output lists.

Verdict: the hidden-input check argument from Vision & Scope holds
*directionally* (the check becomes coarser-grained and the fix less
locally constrained) but does not hold in the strong form Vision &
Scope used. EP-20 keeps the check edge-local; EP-19 keeps it
decidable but coarser. Both are sound.


### Verdict (revised)

Across the six dimensions, the score is mixed:

- **EP-19 wins on**: authoring ergonomics (1), cognitive surface
  count (2), state-space economy (3).
- **EP-20 wins on**: composition (4), migration optionality (5),
  hidden-input check locality (6).

The original Vision & Scope's three reasons (theoretical soundness,
future-facing alignment, realistic distribution) map onto dimensions
6, 4-via-diagrams-implication, and 3 respectively. The expanded
analysis preserves the verdict (EP-20 is the right call) but for a
different weighting than Vision & Scope used:

- The decisive technical argument is **composition** (dimension 4),
  not the hidden-input check (dimension 6). Multi-event composition
  is fundamentally non-local, and EP-19 either restricts multi-event
  edges or re-introduces state refinement under composition.
- The decisive strategic argument is **migration optionality**
  (dimension 5), not future-facing alignment. EP-20 → EP-19 is
  recoverable later if authoring pain warrants; EP-19 → EP-20 is
  not.
- EP-19's authoring and state-space wins are real and the original
  Vision & Scope underweighted them. The decision to pay those
  costs is informed by composition + migration arguments above, not
  by realistic-distribution alone.

The shipped `chainTo` verb (EP-20 M5) is the most important
ergonomic mitigation: it reduces the in-`from` authoring overhead
to one extra line per length-N command, so the day-to-day cost
lives in the `Vertex` and `ci` enum declarations and TH spec lists,
not in the edge bodies. Without `chainTo`, EP-19's authoring win
would be larger and the verdict closer.

The shipped path stands. This section makes the deliberation
honest; no rework follows from it.


## Decomposition Strategy

The MasterPlan decomposes into exactly two child ExecPlans because
the two paths are *mutually exclusive design alternatives*, not
sequential or parallel work streams. Both paths produce identical
external behavior (a single `decide` call returns a 2-element event
list for `StartRegistration`) but commit the library to different
shapes of its core AST. The user reads both, weighs the trade-offs,
and selects one for implementation.

Why two and not three:

- The third approach catalogued in the multi-event note (direct
  MultiDecider with hand-written `apply`) is excluded as
  theoretically incompatible with the synthesis foundation. Its
  rejection is recorded in the Decision Log below.

- A "design milestone" plan (the conventional first child of a
  coordinating MasterPlan) is unnecessary because the design space
  is already articulated in
  `docs/research/multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md`
  and refined in this MasterPlan's Vision & Scope. The decision to
  be made is between two well-specified implementations; the M1
  design note inside each child plan covers the per-path design
  rationale.

Why not merge the two into one plan with a feature flag:

- The two paths edit the same files in incompatible ways. Most
  notably, `src/Keiki/Core.hs:411-419` (the `Edge` declaration) and
  `src/Keiki/Core.hs:564-611` (the `omega` and `applyEvent`
  signatures) are touched by EP-19 with type-level breaking changes
  and untouched by EP-20. A single plan would be a fork-on-day-one,
  not a unified specification.

The two paths share these invariants — both child plans must respect
them so that whichever path is chosen, the surrounding library stays
coherent:

- They both update
  `docs/research/multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md`
  to record the chosen approach as canonical and retire the others.
- They both update
  `docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`'s
  line 974 ("the multi-event document's three approaches still apply
  (state refinement is the cleanest under the symbolic-register
  formalism, as the User Registration example shows)") with a verdict
  appropriate to the chosen path.
- They both demonstrate the new path on
  `src/Keiki/Examples/UserRegistration.hs`'s multi-event entrance
  (`StartRegistration → RegistrationStarted + ConfirmationEmailSent`).
  EP-19 modifies the example aggregate (collapses
  `Registering` + `Continue`); EP-20 leaves the aggregate unchanged
  and adds a `userRegDriverConfig` value.
- Both ship a spec asserting the new path produces a 2-element event
  list from the single multi-event command.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| 1 | Multi-event commands via Edge.output widening (GSM expansion) | docs/plans/19-multi-event-commands-via-edge-output-widening-gsm-expansion.md | None | None (Plan 15 shipped 2026-05-02; cascade now lives inside EP-19's M2/M7) | Cancelled (2026-05-02 — user selected EP-20) |
| 2 | Multi-event commands via state-refinement ergonomics | docs/plans/20-multi-event-commands-via-state-refinement-ergonomics.md | None | None (Plan 15's soft-dep is satisfied; M5 is unconditional) | Complete (2026-05-02) |

Status values: Not Started, In Progress, Complete, Cancelled.

Note: this MasterPlan is decision-shaped. Only one child plan will be
implemented; the other moves to Cancelled once the user chooses. The
"Recommended" annotation on EP-2 indicates the MasterPlan's verdict;
the user retains the choice.


## Dependency Graph

There are no hard dependencies between EP-19 and EP-20. They are
alternatives. The user picks one; the other becomes Cancelled.

Plan 15
(`docs/plans/15-edge-builder-monadic-dsl-for-authoring-symtransducer-edges.md`)
shipped on 2026-05-02 with all milestones complete. `Keiki.Builder`
exists with `from`, `onCmd`, `emit`, `noEmit`, `goto`, `(.=)`,
`requireEq`, `requireGuard` and other verbs; both example aggregates
are migrated to builder form. This eliminates the soft-dependency
that earlier drafts of this MasterPlan recorded for EP-20's M5: the
`chainTo` verb can be added to the existing builder unconditionally.

EP-20 (state-refinement ergonomics) is now fully unblocked. Its
seven milestones can be implemented end-to-end without external
dependencies.

EP-19 (GSM widening) gains an *additional cascade* now that the
builder is shipped: widening `Edge.output :: Maybe (OutTerm rs ci
co)` to `[OutTerm rs ci co]` requires updating the builder's
internal `PartialEdge` accumulator (currently single-event;
`src/Keiki/Builder.hs:235-260` declares the partial-edge state) and
its `emit`/`noEmit` semantics so multiple `emit`s in one `onCmd`
block accumulate into a list rather than failing or replacing.
Both example aggregates' builder-form transducers
(`emailDelivery` and `userReg` — now the canonical forms; the
`*AST` versions are kept only for cross-form equivalence) must be
re-checked for behavior equivalence after the widening. EP-19's M0
inventory must include the builder modules and their tests.

There are no parallel-work opportunities within either child plan
that would benefit from further decomposition; both plans are
linear sequences of milestones.


## Integration Points

Both child plans touch overlapping files but propose incompatible
edits. This section documents the integration surface so the
selected path can preserve the other's authoring guidance as design
rationale even after the alternative is Cancelled.

1. **`src/Keiki/Core.hs:411-419` — the `Edge` declaration.**

   - EP-19 widens `output :: Maybe (OutTerm rs ci co)` to `output ::
     [OutTerm rs ci co]`. Cascade: `omega` returns `[co]`,
     `applyEvent` operates on wrapped `InFlight s co` state, and
     all sites that pattern-match `Just`/`Nothing` on `output`
     (~24 sites enumerated in EP-19's M0) need adaptation.
   - EP-20 leaves the declaration unchanged. The letter FST shape
     is preserved.

2. **`src/Keiki/Core.hs` — replay primitives.**

   - EP-19 replaces `applyEvent`'s signature with one operating on
     `InFlight s co` and adds `applyEvents` for chunk replay.
   - EP-20 keeps `applyEvent`'s signature unchanged and adds
     `applyEvents` as a fold of the existing `applyEvent`. No
     wrapper type.

3. **`src/Keiki/Decider.hs` — the decider façade.**

   - EP-19 retires the docstring caveat about "at most one event
     per command" (currently lines 30-39) and updates the `decide`
     lift to walk `omega`'s new `[co]` directly. Adds an
     `evolveStreaming` field for wrapped-state replay.
   - EP-20 adds `DriverConfig s ci` and `toMultiDecider` as
     additive extensions; the existing `Decider` record and
     `toDecider` remain unchanged.

4. **`src/Keiki/Composition.hs:401-447` — `composeEdge`.**

   - EP-19 changes the signature; sequential composition of
     multi-event edges concatenates output lists with the existing
     `substOut` substitution applied to each `OutTerm`.
   - EP-20 leaves it unchanged.

5. **`src/Keiki/Examples/UserRegistration.hs` — the canonical
   multi-event aggregate.**

   - EP-19 collapses the `Registering` intermediate vertex and the
     `Continue` command. Vertex enum drops one constructor (5→4);
     command enum drops one constructor (5→4); two letter edges
     become one length-2 edge. The `deriveAggregateCtors` and
     `deriveView` spec lists drop the `Registering` and `Continue`
     entries.
   - EP-20 preserves `Registering` and `Continue` exactly. Adds a
     `userRegDriverConfig` value declaring `Registering` as
     internal with `Continue` as the advancement command.

6. **Documentation surface.** Both plans update the same two notes
   with path-appropriate verdicts:

   - `docs/research/synthesis-c-foundation-b-presentation-with-worked-examples.md`
     line 974 — "state refinement is the cleanest under the
     symbolic-register formalism" — replaced with path-specific
     text per each child plan's M6 (EP-19) / M6 (EP-20).
   - `docs/research/multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md`'s
     Recommendation section (currently "Default to Approach 3")
     replaced with "Approach 2 with library widening" (EP-19) or
     "Approach 1 with library ergonomics" (EP-20).

7. **`src/Keiki/Builder.hs` — the monadic builder DSL.**

   Plan 15 shipped this module on 2026-05-02 with `from`, `onCmd`,
   `onEpsilon`, `(.=)`, `slot`, `emit`, `emitWith`, `noEmit`,
   `goto`, `requireEq`, `requireGuard`. The internal accumulator
   `PartialEdge rs ci co v (w :: [Symbol])` (declared at
   `src/Keiki/Builder.hs:235-260`) carries a single optional
   `OutTerm`, mirroring the AST's `Maybe (OutTerm rs ci co)`. Both
   paths interact:

   - EP-19 widens the AST's `Edge.output` to a list; this cascades
     into `Keiki.Builder`. `PartialEdge` must hold a list of
     `OutTerm`s (or be re-architected to accumulate them); `emit`
     becomes appending rather than setting; a single `emit` in an
     `onCmd` block produces a length-1 list (today's letter
     behavior); two or more `emit`s accumulate. `noEmit` and the
     finalize step must reject inconsistent combinations (e.g.
     `noEmit` followed by `emit`). The builder's existing tests in
     `test/Keiki/BuilderSpec.hs` and the spike in
     `test/Keiki/BuilderSpike.hs` must be re-greened.
   - EP-20 adds a new verb `chainTo :: v -> InCtor ci '[] ->
     EdgeBuilder rs ci co v w w ()` to `Keiki.Builder`, leaving
     `emit` unchanged. `chainTo` partitions the surrounding
     `onCmd` block into a sequence of `Edge` values through the
     named intermediate vertex, with the named `InCtor` (typically
     a singleton `Continue`) as the advancement command's input
     constructor.

8. **`src/Keiki/Examples/EmailDelivery.hs` and
   `src/Keiki/Examples/UserRegistration.hs` — builder-form
   aggregates.**

   Both files now declare the transducer twice: once via the
   builder (`emailDelivery`, `userReg` — the canonical forms used
   by all other specs), and once via the AST (`emailDeliveryAST`,
   `userRegAST` — preserved for cross-form equivalence testing per
   Plan 15's M4/M5 pattern).

   - EP-19's M7 (collapse `Registering` and `Continue`) must edit
     the builder-form `userReg` (now using a length-2 `emit` block
     with no `goto Registering` between events) *and* the AST-form
     `userRegAST` (collapsing the two `Edge` literals into one with
     `output = [pack ..., pack ...]`). Cross-form equivalence is
     re-checked.
   - EP-20's M4 (add `userRegDriverConfig`) is purely additive and
     touches neither aggregate's transducer definition.


## Progress

Track milestone-level progress across all child plans. This section
provides an at-a-glance view of the entire initiative. Once a child
plan is selected for implementation, the corresponding milestones
become live; the unselected plan's milestones are marked Cancelled.

EP-19 (GSM widening — Path A): **Cancelled** on 2026-05-02 when the
user selected EP-20.

- [-] EP-19 / M0–M8: not pursued.

EP-20 (state-refinement ergonomics — Path B, recommended): **Complete**
on 2026-05-02.

- [x] EP-20 / M0: Verify prerequisites; baseline 149 examples,
      0 failures.
- [x] EP-20 / M1: Design note shipped at
      `docs/research/multi-decider-via-state-refinement.md` (335
      lines).
- [x] EP-20 / M2: `applyEvents` added to `Keiki.Core`; +3 specs.
- [x] EP-20 / M3: `DriverConfig` + `toMultiDecider` added to
      `Keiki.Decider`; +3 specs.
- [x] EP-20 / M4: `userRegDriverConfig` added to
      `Keiki.Examples.UserRegistration`; +3 specs.
- [x] EP-20 / M5: `chainTo` builder verb shipped, `userRegChained`
      authored; +8 specs (cross-form equivalence).
- [x] EP-20 / M6: synthesis note line 974 + multi-event note
      Recommendation section updated.
- [x] EP-20 / M7: commit (in progress at this writing).


## Surprises & Discoveries

Document cross-plan insights, dependency changes, scope adjustments,
or unexpected interactions between child plans. Provide concise
evidence.

(None yet.)


## Decision Log

Record every decomposition or coordination decision made while
working on the master plan.

- **Decision**: Excluded Approach 3 (direct MultiDecider with
  hand-written `apply`) from the decision space.
  **Rationale**: the synthesis foundation note's §1 names mechanical
  `apply` derivation as "the decisive technical win" of the
  symbolic-register formalism. Approach 3 surrenders this property
  by definition — the user writes `apply` by hand, so the library
  cannot certify the reconstitution-event-determinism contract at
  build time. Including Approach 3 in the decision space would force
  the user to weigh giving up the foundation's central guarantee
  against a marginal ergonomic gain that Approach 1 + library
  helpers (EP-20) can match without that cost.
  **Date**: 2026-05-02

- **Decision**: Decompose into two alternative ExecPlans rather than
  three (no preliminary "design milestone" plan).
  **Rationale**: the design space is already articulated in
  `docs/research/multi-event-commands-state-refinement-gsm-expansion-and-multidecider.md`
  and refined in this MasterPlan's Vision & Scope. A separate child
  plan whose only output is a design note would duplicate that
  work. Each child plan instead carries its own M1 design note
  scoped to its specific path.
  **Date**: 2026-05-02

- **Decision**: MasterPlan recommends Path B (EP-20,
  state-refinement ergonomics) over Path A (EP-19, GSM widening).
  **Rationale**: three reinforcing reasons recorded in Vision &
  Scope — (1) theoretical soundness: letter FST is the foundation
  named in the synthesis note; widening to GSM moves analyses from
  per-edge to per-edge-list and weakens the hidden-input check; (2)
  future-facing alignment: diagram generation and dependent-typing
  both prefer letter FST; (3) realistic distribution: 1–2 events
  per command is the norm, and Path B's cost (one intermediate
  vertex per length-2 command) is manageable and further compressed
  by the `chainTo` DSL verb.
  **Caveat**: this is a recommendation, not the decision. The user
  explicitly requested both ExecPlans be fully fleshed out so the
  choice can be made after detailed review. The actual selection is
  recorded as a follow-up Decision Log entry once made; selecting
  EP-19 reverses the recommendation, and selecting EP-20 confirms
  it.
  **Date**: 2026-05-02

- **Decision**: EP-20's M5 (`chainTo` DSL verb) is soft-deferred
  behind Plan 15.
  **Rationale**: Plan 15 specifies the entire builder DSL
  (`from`, `onCmd`, `emit`, `goto`, `(.=)`); `chainTo` extends that
  surface. Building `chainTo` requires the `EdgeBuilder` monad to
  exist. A hard dependency on Plan 15 would serialize the work
  unnecessarily — the rest of EP-20 (M2, M3, M4, M6) is independent
  of the builder and provides the core multi-event ergonomics.
  EP-20's M1 design note records the deferral plan so Plan 15's
  implementation absorbs `chainTo` cleanly if EP-20 closes without
  M5.
  **Date**: 2026-05-02
  **Superseded 2026-05-02**: Plan 15 has now shipped (M0–M7
  complete). The deferral path in EP-20's M1 is no longer needed;
  EP-20's M5 is unconditional. The deferral plan in EP-20's M1
  design note is preserved as a "what would have happened if Plan
  15 had not landed" note for posterity.

- **Decision**: User selected EP-20 (state-refinement ergonomics) for
  implementation; EP-19 (GSM widening) is Cancelled.
  **Rationale**: confirms the MasterPlan's standing recommendation
  (recorded in the 2026-05-02 entry above). EP-20 is the additive
  path: it preserves the letter-FST AST and ships
  `Keiki.Core.applyEvents`, `Keiki.Decider.DriverConfig +
  toMultiDecider`, `userRegDriverConfig`, and `Keiki.Builder.chainTo`
  as ergonomic layers above the existing formalism. EP-19's
  type-level breaking change (`Edge.output :: Maybe (OutTerm rs ci
  co)` → `[OutTerm rs ci co]`), `InFlight` wrapper, and ~24-site
  cascade are not pursued.
  **Date**: 2026-05-02

- **Decision**: Plan 15's completion changes the integration
  surface for EP-19.
  **Rationale**: with the builder shipped and both example
  aggregates now in builder form (per `Keiki.Examples.EmailDelivery`
  and `Keiki.Examples.UserRegistration` on master),
  EP-19's `Edge.output` widening cascades into
  `src/Keiki/Builder.hs`'s `PartialEdge` accumulator and `emit`
  semantics. EP-19's M0 inventory and M2 widening must include the
  builder modules; EP-19's M7 must edit both the builder-form
  `userReg` and the AST-form `userRegAST`. The MasterPlan's
  Integration Points section captures this; EP-19's plan body must
  be updated to reflect the cascade.
  **Date**: 2026-05-02

- **Decision**: Augment the MasterPlan with a retrospective
  six-dimension Tradeoff Analysis section between Vision & Scope and
  Decomposition Strategy. The shipped path (EP-20) is preserved; the
  augmentation is informational.
  **Rationale**: the original Vision & Scope's three-reason argument
  (theoretical soundness, future-facing alignment, realistic
  distribution) was sufficient to act on but undersold EP-19's
  genuine strengths (no synthetic vertices, no `DriverConfig` sync,
  smaller library surface) and overstated one of its weaknesses (the
  hidden-input check is generalised, not weakened). The new section
  covers six dimensions — authoring ergonomics, cognitive surface,
  state-space cost as commands grow, composition under `composeEdge`,
  migration optionality, hidden-input check honest framing — so the
  project history reflects honest deliberation. The expanded analysis
  preserves the verdict but reweights the supporting arguments: the
  decisive technical argument becomes composition (multi-event
  composition is fundamentally non-local), and the decisive
  strategic argument becomes migration optionality (EP-20 → EP-19 is
  recoverable, the reverse is not). EP-19's wins on authoring,
  cognitive count, and state-space economy are real and explicitly
  acknowledged.
  **Date**: 2026-05-02


## Outcomes & Retrospective

MasterPlan 7 closed on 2026-05-02 with EP-20 (state-refinement
ergonomics) shipped end-to-end and EP-19 (GSM widening) Cancelled.

The original vision — make multi-event commands ergonomic without
sacrificing the foundation's mechanically-derived `apply` — is met:

- The user can model a multi-event command (canonical example:
  `StartRegistration` → `RegistrationStarted +
  ConfirmationEmailSent`) in three idiomatic ways, all yielding
  identical observable behavior:
  1. AST-form: two `Edge` literals chained through an intermediate
     `Registering` vertex.
  2. Builder-form (existing): two `from` blocks, one per source
     vertex.
  3. Builder-form with `chainTo` (new in EP-20): one `onCmd` body
     with a `chainTo Registering inCtorContinue` between two
     `emit` calls.
- Callers see the chain end-to-end via `toMultiDecider userReg
  userRegDriverConfig`, which returns a 2-element event list from
  a single `decide` call.
- `applyEvents` provides chunk-replay for runtimes with command
  boundaries.

The letter-FST AST is preserved unchanged; every existing analysis
keeps its decidable-per-edge property. The diagram-generation and
dependent-typing futures named in Vision & Scope remain
unobstructed.

Test count: baseline 149 → 166 (17 new specs across M2/M3/M4/M5);
0 failures throughout implementation.

Surprises (recorded in EP-20's Decision Log and Outcomes section):

- The plan's draft `chainTo :: ... EdgeBuilder rs ci co v w w ()`
  signature was not type-correct given the value-level `peUpdate`
  reset to `UKeep`. The shipped signature ends in `'[]` rather
  than `w`. Side-benefit: the user can write to the same slot
  name across a `chainTo` boundary because the segments are
  distinct edges with their own update fields.
- `EdgeListBuilder`'s single-`[Edge]` accumulator was insufficient
  for `chainTo` expansion (which produces edges from a different
  source vertex than the surrounding `from`). Refactor:
  `EdgeListAcc { elaMain, elaChain }`, with `from` distributing
  chained-source edges into the `VertexBuilder` map and
  `buildTransducer` switching from `lookup` to `concatMap+filter`
  to merge duplicate-vertex entries.

No cross-plan discoveries to record (only one child plan was
implemented).

Decomposition retrospective: the decision-shaped MasterPlan format
worked as intended. The user's choice between EP-19 and EP-20 was
informed by both child plans being fully fleshed out, the
MasterPlan's recommendation in Vision & Scope, and the standing
synthesis-foundation argument. The shipped path matched the
recommendation; no rework was needed.


## Revision Notes

- **2026-05-02 (initial draft)**: MasterPlan and both child
  ExecPlans created. EP-20's M5 documented as soft-deferred
  pending Plan 15.

- **2026-05-02 (Plan 15 shipped)**: Plan 15 completed all
  milestones (M0–M7) on master. `Keiki.Builder` exports the
  monadic DSL; both `Keiki.Examples.EmailDelivery` and
  `Keiki.Examples.UserRegistration` are now in builder form with
  AST forms preserved as `*AST` for cross-form equivalence.
  Updated:
  - **Vision & Scope**: noted Plan 15's completion and its impact on
    EP-20's M5.
  - **Exec-Plan Registry**: EP-20's soft dep removed; EP-19's row
    annotated to record the new builder cascade.
  - **Dependency Graph**: rewrote to reflect that EP-20's M5 is now
    unconditional and EP-19 has an additional cascade into the
    builder modules.
  - **Integration Points**: replaced the old §7 "Plan 15" entry with
    a richer §7 covering `Keiki.Builder`'s current shape and how
    each path interacts; added a new §8 covering the builder-form
    aggregates.
  - **Decision Log**: amended the M5-defer entry with a "Superseded"
    note; added a new entry recording the EP-19 cascade impact.

  Cascading edits to child plans
  (`docs/plans/19-multi-event-commands-via-edge-output-widening-gsm-expansion.md`
  and
  `docs/plans/20-multi-event-commands-via-state-refinement-ergonomics.md`)
  carry the same change.

- **2026-05-02 (retrospective tradeoff augmentation)**: Added a new
  "Tradeoff Analysis (retrospective, augmented 2026-05-02)" section
  between Vision & Scope and Decomposition Strategy. The section
  evaluates EP-19 vs EP-20 along six dimensions (authoring
  ergonomics, cognitive surface, state-space cost as commands grow,
  composition under `composeEdge`, migration optionality,
  hidden-input check honest framing) and closes with a revised
  verdict that preserves the EP-20 selection but reweights the
  supporting arguments: composition (dimension 4) and migration
  optionality (dimension 5) replace theoretical soundness and
  future-facing alignment as the load-bearing reasons. EP-19's wins
  on authoring (dimension 1), cognitive count (dimension 2), and
  state-space economy (dimension 3) are explicitly acknowledged.
  Added a corresponding Decision Log entry. No child-plan cascade
  required; the analysis is informational and does not change any
  shipped artefact.
