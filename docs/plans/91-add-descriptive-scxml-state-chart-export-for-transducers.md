---
id: 91
slug: add-descriptive-scxml-state-chart-export-for-transducers
title: "Add descriptive SCXML state-chart export for transducers"
kind: exec-plan
created_at: 2026-10-02T21:57:55Z
intention: "intention_01m3z9y4sjed185fjpx1c8snk2"
provenance:
  created_by:
    model: "gpt-6-astra"
    harness: "codex-cli"
    at: 2026-10-02T21:57:55Z
---

# Add descriptive SCXML state-chart export for transducers


This ExecPlan is a living document. Keep Progress, Surprises & Discoveries, Decision Log, and Outcomes & Retrospective current during implementation. The authorized deliverable of the authoring session is this plan; implementation remains pending.

## Purpose / Big Picture


A keiki user will be able to call `Keiki.Render.SCXML.toSCXML` on a finite transducer and save the result as a `.scxml` file representing its control states and transitions. State Chart XML (SCXML) is a standard XML notation for state machines. The exported document will contain a portable, flat state-chart structure together with readable descriptions of the guards, register assignments, and emitted events derived from the same declaration.

This is a descriptive export for inspection and state-chart interchange. It does not compile Haskell behavior into an executable SCXML program. In particular, loading the document into an interpreter does not reproduce keiki's command rejection, guard evaluation, register updates, event emission, or replay. The document itself and the API documentation must state that limitation. Generic viewers can show the states and event-labelled arrows; whether they display or retain descriptive comments depends on the viewer. Supporting a particular graphical editor, importing SCXML into keiki, and guaranteeing editor round-trips are outside this plan.

The observable demonstration is an exported Email Delivery chart with an initial pending state, a `SendEmail` arrow to its terminal sent state, and readable metadata describing the three register assignments and `EmailSent` output. An independent XML parser will read the actual generated file and verify its graph and descriptions.

## Progress


- [ ] Milestone 1: The public exporter produces an independently parsed Email Delivery chart with correct states, initial reference, transition, and terminal marker.
- [ ] Milestone 2: Descriptions, replay-edge policy, acceptance markers, unusual names, and malformed finite-state enumeration are handled explicitly and covered by semantic and parser tests.
- [ ] Milestone 3: The documented export example, repeatable CI acceptance gate, regression checks, and durable rendering decision are delivered.

## Surprises & Discoveries


## Decision Log


Decision (2026-10-02): Export a descriptive flat SCXML graph, with behavior in XML comments and no generated executable expressions. SCXML's null data model cannot interpret Haskell expressions, and its processor conformance section leaves behavior on foreign elements and attributes undefined. Comments retain descriptions without requiring an extension namespace. This is an interchange subset, not a behavioral equivalence claim.

Decision (2026-10-02): Default to forward edges, preserve replay-only edge descriptions as comments, and provide an explicit all-declared-edges view. Replay-only edges exist to interpret historical events and must not silently appear as command transitions in the default graph.

Decision (2026-10-02): A keiki accepting state becomes SCXML `<final>` only when it has no displayed outgoing edges. Other accepting states remain `<state>` with an acceptance annotation. `isFinal` is an acceptance predicate; keiki forward stepping does not consult it to prohibit further transitions.

Decision (2026-10-02): Keep the exporter pure and use existing Haskell dependencies. Validate generated documents independently with Python's standard XML and JSON parsers, adding Python only to development/CI tooling. This avoids coupling the core package to an XML implementation or a graphical editor.

## Outcomes & Retrospective


## Context and Orientation


`src/Keiki/Core.hs` defines `SymTransducer`, which has `initial`, `initialRegs`, `isFinal`, and `edgesOut`. A control state is one value of its state type. A register file holds the data associated with the machine separately from that state. An `Edge` contains a guard (the condition for taking it), an update (register assignments), an ordered output list, a target state, and a `Live` or `ReplayOnly` mode. An empty output list means no emitted event; it does not mean that the edge needs no input command. Rendering must inspect these declarations without evaluating commands, predicates, register values, function closures, or output constructors.

Existing renderers enumerate states with `[minBound .. maxBound]`. `src/Keiki/Render/Mermaid.hs` implements Mermaid diagrams. Its `edgeInputName` returns the first constructor found even under disjunction and negation; it is a display heuristic, not a sound event-trigger analysis. Its output helpers already escape Mermaid text and must not be reused to produce XML. `src/Keiki/Render/Pretty.hs` provides unescaped `prettyPred`, `prettyUpdate`, and `prettyTerm`. Ordinary literals use retained `Show` evidence; deliberately opaque literals display `<lit>`, and opaque applications display `<fn>(...)`. `src/Keiki/Render/Inspector.hs` demonstrates inspecting existentially typed `OPack` and `OutFields` values without executing them.

`test/Keiki/Fixtures/EmailDelivery.hs` supplies the canonical two-state demonstration. Its initial registers contain deferred errors, making it useful evidence that rendering does not force the register file. `test/Keiki/Render/MermaidSpec.hs`, `test/Keiki/ReplayOnlySpec.hs`, and `test/Keiki/CompositionStatefulSpec.hs` provide patterns for unusual labels, historical edges, and stateful updates. `test/Spec.hs` registers Hspec tests. `keiki.cabal` lists public modules and test modules explicitly. `README.md` and `docs/capabilities/diagram-rendering.md` describe the current rendering contract. Existing suites use GHC 9.12.4 and z3 through the Nix development shell; `flake.module.nix` owns project-specific tooling and the CI shell. Do not edit the managed shell configuration in `nix/haskell.nix` to add tools.

The relevant architecture decisions were read after scanning local ADR filenames and headings. [ADR-6](../adr/0006-readable-business-semantics-are-the-primary-rendering-contract.md), in `docs/adr/0006-readable-business-semantics-are-the-primary-rendering-contract.md`, requires readable behavior by default and explicit redaction; its literal and pretty-printing policy applies here. [ADR-4](../adr/0004-composition-uses-snapshot-updates-and-checked-boundaries.md), in `docs/adr/0004-composition-uses-snapshot-updates-and-checked-boundaries.md`, establishes that sibling assignments read the register values from before the edge. Do not present them as sequential executable `<assign>` operations. [ADR-2](../adr/0002-event-logs-must-reproduce-forward-state.md), in `docs/adr/0002-event-logs-must-reproduce-forward-state.md`, distinguishes forward execution from replay and says edge indices are local declaration positions, not durable identifiers. Preserve output order and label these indices accordingly.

`docs/adr/` is a profile-governed Open Knowledge Format bundle, confirmed with `mori show --full`. Follow `docs/guide/adr-conventions.md` and the local `docs/adr/profile.dhall` when updating it. Preserve `ADR-6`; no new decision number is needed to extend its rendering contract.

External format authority is the [W3C SCXML Recommendation](https://www.w3.org/TR/scxml/), particularly its sections on states, transitions, finals, identifiers, conformance, and the null data model. The selected subset uses a namespaced `scxml` root, `state`, `final`, event-labelled `transition`, and XML comments. Conditions and actions are descriptive text only. Comments contain JSON objects; JSON is a structured text format used here solely to retain strings and ordered arrays without ambiguity. Independent validation uses the documented [ElementTree parser](https://docs.python.org/3/library/xml.etree.elementtree.html) and [JSON decoder](https://docs.python.org/3/library/json.html). Mori's registry was consulted for Python; no CPython source project was registered, so these official references supply the parser API documentation. No dependency version or compatibility workaround is chosen by this plan.

## Plan of Work


### Milestone 1: Export a real transducer through the public API


Create `src/Keiki/Render/SCXML.hs` with the API below and expose it in `keiki.cabal`. Create `test/Keiki/Render/SCXMLSpec.hs` and `test/Keiki/Render/SCXMLFixtures.hs`, register both in the test component, and register the spec in `test/Spec.hs` under `Keiki.Render.SCXML`. Start with Email Delivery and the default configuration. Build the state-ID table before rendering references. Return a structured error when the enumeration is empty or an initial/target state is absent; never produce a dangling reference or crash through a partial lookup.

Emit XML 1.0 as UTF-8 text, with root `xmlns="http://www.w3.org/2005/07/scxml"`, `version="1.0"`, `datamodel="null"`, and `initial` referencing the declared initial state. Enumerate all states, including unreachable and isolated states. Preserve declaration order for states and outgoing edges. Use IDs of the form `s0_EmailPending`, where the decimal index is the enumeration position and the suffix replaces every character outside ASCII letters, digits, and underscore with underscore. The prefix makes IDs legal and collision-free even when two `Show` values coincide or sanitize identically. Store the exact display name in metadata. These IDs are deterministic for a fixed declaration, not persistent identity across reordered state types.

Use `<final>` for an accepting state with no displayed edges, and `<state>` otherwise. Emit one transition per displayed edge, including self-loops and zero-output edges. Never split multi-event output into multiple transitions. There is no nested-state or `<parallel>` reconstruction in this version. A transducer whose state is an ordinary enumerable product can still render as a flat graph; specialized `Composite` adapters are outside scope.

For readable `event` attributes, extract a constructor name only when the entire guard uses conjunctions, contains exactly one `PInCtor` occurrence, and contains no disjunction or negation. Emit that name only if it matches `[A-Za-z_][A-Za-z0-9_]*` and does not start with the reserved exporter prefix `keiki_`. Otherwise use `keiki_edge_sN_eM`, where N is the source enumeration position and M is the original outgoing index. This conservative rule provides familiar labels for Builder declarations without pretending a disjunction, negation, wildcard, or arbitrary constructor display string denotes a single SCXML event. Always retain the full guard in metadata, and document all `event` values as diagram labels, not a command encoding. Never omit `event`: in SCXML omission means an automatically eligible eventless transition.

Exercise the producer/consumer boundary immediately. Add `scripts/check-scxml.sh` to generate fixtures from the compiled test component, and `scripts/check-scxml.py` to parse them. Add `pkgs.python3` to `haskellProject.extraDevPackages` in `flake.module.nix`, which also feeds the CI shell. The shell script must stop on export failure or missing files; success from GHCi alone is insufficient. At this milestone the Python checker must independently see two Email Delivery vertices, the correct initial reference, exactly one arrow labelled `SendEmail`, its correct target, and a terminal sent vertex. Do not expand fixture coverage before this actual generated-file check passes.

### Milestone 2: Preserve descriptions and edge policies without changing execution


Finish metadata and option handling in `src/Keiki/Render/SCXML.hs`. Use comments beginning with `keiki-scxml-v1 ` followed by a JSON object. Put a document record immediately inside the root, a state record inside each state/final element, and a displayed edge record inside its transition. Put an omitted replay-only edge record directly in its source state. Each record carries a `kind` discriminator. Specify fixed field ordering for repeatable output; downstream readers should use field names.

The document record contains `purpose: "descriptive-only"`, the edge view, and a plain warning that guards, assignments, output, and replay semantics are not executed. State records contain the exact display label and an `accepting` boolean. Edge records contain source and target IDs, original `edgeIndex`, `mode`, `displayed`, and the chosen `event` label. With behavior enabled they also contain the full pretty guard, full pretty update, and an ordered `outputs` array. Each output object contains its constructor name and its ordered pretty-printed field expressions. Inspect `OPack` and recursively inspect `OFNil`/`OFCons`; do not use constructor display names as proof of semantic identity. An empty output array is explicit. Existing `<lit>` and `<fn>` markers must survive decoding exactly. Record that all update right-hand sides describe reads from the edge-entry snapshot.

Implement only the small private JSON encoder needed for these fixed objects, arrays, strings, booleans, and integer indices; do not introduce a public general serialization framework. Escape JSON quotes, backslashes, control characters, and XML-forbidden characters, including surrogate code points if encountered. Encode every hyphen in string content as JSON `\u002d` so arbitrary names containing `--` or `-->` cannot end or invalidate a comment. Encode XML-illegal noncharacters as JSON escapes as well. Comment delimiters and framing must never form an interior `--`. Unlike XML attributes, comment content does not decode XML entities; do not entity-escape strings inside JSON. Use real XML escaping for any attribute text. Preserve Unicode and multiline content after XML parsing plus JSON decoding. Specify a trailing newline and stable indentation.

Default `ForwardEdges` displays only `Live` transitions. It retains replay-only records as non-transition comments, so historical information remains available without altering the forward graph. `AllDeclaredEdges` displays both modes; replay-only transitions use reserved synthetic labels `keiki_replay_sN_eM` even when a constructor name is available. Their records and the document record explain that these arrows are historical inversion paths. Compute terminal-element eligibility against displayed edges, so an accepting vertex with replay-only outgoing edges can be `<final>` in the default view and `<state>` in the all-edges view. Validate targets for every recorded edge, including omitted replay-only edges.

`includeBehavior = False` is an explicit structural view. It keeps state names, references, acceptance, edge mode/index, and diagnostic event labels, but omits guards, assignments, and output fields. It must not evaluate behavior pretty-printers or literal `Show` instances. The default remains readable behavior. Neither mode reads `initialRegs` or evaluates any stored function; ordinary readable literals retain the same disclosure and partial-`Show` limitations as ADR-6.

Acceptance at this milestone includes parsed metadata equality, not just substring assertions. Extend the shared fixtures to cover duplicate/sanitization-colliding state names; Unicode, quotes, ampersands, angle brackets, newlines, backslashes, `--`, `-->`, and an XML-forbidden control character; zero and multiple outputs; accepting states with outgoing edges; replay-only edges; PTop/POr/PNot guards; unknown or unsafe constructor names; and unreachable/isolated states. A bottom-valued initial register file must render successfully. A literal whose `Show` fails must not be forced by structural mode, and an opaque function whose body fails must never run in either mode. Add explicit malformed-enumeration tests for all three error cases. Existing runtime and Mermaid behavior must remain unchanged.

### Milestone 3: Make export discoverable and continuously verified


Finish `scripts/check-scxml.sh` as a repeatable public check and add `just scxml-check` to `justfile`. Run it in `.github/workflows/ci.yml` after the normal build, within the existing CI shell. The script generates current documents into its own temporary directory, runs the independent checker, and cleans only files it owns. Allow an optional output directory for retaining demonstration artifacts; do not delete a user-supplied directory. The checker accepts only the documented subset, resolves every `initial` and `target`, validates ID uniqueness, requires nonempty event labels, decodes metadata, and verifies each fixture's expected graph and descriptions. It must reject broken XML, a missing target, or missing behavioral data where expected. It is a validator for this export contract, not a general SCXML conformance checker.

Add `docs/guide/scxml-export.md`, update the rendering section of `README.md`, extend `docs/capabilities/diagram-rendering.md`, and add an unreleased `CHANGELOG.md` entry. Document the API, how to write UTF-8 output, the exact subset and comment schema, default versus all-edge views, terminal-state treatment, and the fact that generic viewers can ignore comments. Do not advertise any named editor as compatible without testing it. Include a generated Email Delivery example at `docs/examples/email-delivery.scxml`; compare it against fresh output in the check rather than maintaining it by hand. Add new scripts/example assets to `extra-source-files` in `keiki.cabal` so the acceptance path also exists in a source distribution. Do not assert a released `since` version for the new functionality before release.

Extend ADR-6 with the SCXML descriptive boundary and comment convention, preserving its stable `docId`. Follow the local profile for authorship metadata and record the ADR and capability changes in their bundle logs and indexes using the installed OKF CLI. Consult `okf log add --help` and `okf index --help` for exact installed syntax; do not hand-invent profile metadata. Run the strict checks below. Run the focused SCXML acceptance, then the existing core and codec regressions and ordinary build gates once on the final candidate. No package release, publishing, or dependency upgrade is part of this plan.

## Concrete Steps


All commands run from the repository root, `/Users/shinzui/Keikaku/bokuno/keiki` in the authoring checkout. Use `nix develop -c` so the checked-in compiler and z3 are used. After adding Python, stage only the new project files needed by Nix evaluation; do not stage unrelated work. Record the current implementation agent's provenance with `agents/skills/exec-plan/record-provenance.ts`, using the runtime discovery instructions alongside that script.

During milestones 1 and 2:

```bash
nix develop -c cabal build all
nix develop -c cabal test keiki:keiki-test --test-show-details=direct --test-options='--match Keiki.Render.SCXML'
nix develop -c bash scripts/check-scxml.sh
```

Implement the shell script's generation step using the registered fixture module and the Cabal test component, whose extension/dependency settings already compile the fixtures. The shared fixture module exports `scxmlFixtures :: Either ScxmlError [(FilePath, Text)]`. It must collect failures rather than silently dropping an unsuccessful fixture. A direct diagnostic equivalent, with the output directory created beforehand, is:

```bash
mkdir -p .tmp/scxml
nix develop -c cabal repl keiki:keiki-test <<'GHCI'
:m + Keiki.Render.SCXMLFixtures
:m + Data.Text.IO
case scxmlFixtures of Left err -> error (show err); Right xs -> mapM_ (\(name, xml) -> Data.Text.IO.writeFile (".tmp/scxml/" ++ name) xml) xs
:quit
GHCI
nix develop -c python3 scripts/check-scxml.py .tmp/scxml
```

Fixture names are fixed basenames ending in `.scxml`; they must not contain path traversal. The script version should use its selected output directory consistently. Give the Python checker an explicit expected file set so GHCi errors, stale artifacts, or a partially generated directory cannot report success. The shell wrapper must start with an empty owned directory when run in CI. Expected evidence is a passing Hspec group and a parser summary such as:

```text
SCXML fixtures: all expected documents parsed; graph and metadata checks passed
```

At milestone 3, the documented public route and required final checks are:

```bash
nix develop -c just scxml-check
nix develop -c cabal build all
nix develop -c cabal test keiki:keiki-test --test-show-details=direct
nix develop -c cabal test keiki-codec-json:keiki-codec-json-test --test-show-details=direct
nix develop -c just compile-fail-check
nix develop -c cabal check
nix fmt
```

`cabal check` should report no new package-distribution issues. Inspect formatting changes and preserve unrelated work. OKF and Dhall are host tools in the current repository, outside the Nix tool list. After updating ADR/capability metadata and logs, run:

```bash
dhall type --file docs/adr/profile.dhall
okf validate docs/adr --strict --profile docs/adr/profile.dhall --profile-enforce --log-enforce
dhall type --file docs/capabilities/profile.dhall
okf validate docs/capabilities --strict --profile docs/capabilities/profile.dhall --profile-enforce --log-enforce
git diff --check
```

These checks must exit successfully; distinguish any pre-existing bundle defects from this change and record concrete evidence. Commit implementation at coherent verified boundaries on the current branch, using Conventional Commits and both trailers:

```text
feat(render): export descriptive SCXML state charts

ExecPlan: docs/plans/91-add-descriptive-scxml-state-chart-export-for-transducers.md
Intention: intention_01m3z9y4sjed185fjpx1c8snk2
```

## Validation and Acceptance


A consumer imports `Keiki.Render.SCXML`, calls `toSCXML emailDelivery`, obtains `Right text`, writes it with `Data.Text.IO.writeFile`, and parses the resulting file as XML. The initial ID points at pending, the single `SendEmail` transition targets sent, and sent is a `<final>`. Decoded comments expose the exact pretty guard, all three assignments, and `EmailSent` with ordered field descriptions. Repeating export with the same options and declaration yields identical bytes.

The default view has exactly as many arrows as declared live edges. A replay-only edge is present as an annotated record but contributes no arrow; the all-edge option adds exactly that arrow with a reserved replay label. An accepting state with a live self-loop retains both the loop and its acceptance annotation. A no-output edge still has an event label and an explicit empty output array. Multi-output edges retain event order and remain single arrows. The exporter neither prunes guards it thinks are false nor claims that all drawn paths are feasible.

The hostile-text fixture must parse and recover its complete strings after JSON decoding, including sequences that would otherwise break XML comments. State name collisions cannot merge vertices. Missing initial/target references return `Left` with deterministic diagnostic context, never a partly valid document. Structural mode omits behavior and does not force its literal display functions. Opaque terms remain visibly opaque.

Required evidence consists of the focused Hspec results, independent parser results on freshly generated outputs, byte comparison of the documented example, unchanged existing regression results, and strict documentation checks. No browser/editor screenshot or interpreter-equivalence proof is required. Do not represent passing this subset checker as exhaustive validation of the W3C specification or arbitrary third-party tools.

## Idempotence and Recovery


This change is additive: no persistent data migration, register encoding change, or event-log rewrite is involved. Re-running generation replaces only owned fixture files and produces identical content. Generate into a fresh temporary directory before comparing or copying the documentation example, so failed export cannot leave a misleading successful artifact. On a parser failure, retain or explicitly regenerate into a user-selected diagnostic directory, inspect the offending XML, fix escaping or graph construction, and rerun the focused check.

Do not relax acceptance by moving Haskell expressions into `cond` or suppressing metadata that fails to serialize. Fix the boundary. Preserve unrelated working-tree edits, avoid broad resets, and keep optional all-edge output clearly descriptive. If a future user needs a specific editor or executable SCXML, record it as separate scope with its own compatibility or semantic tests.

## Interfaces and Dependencies


The new public module `Keiki.Render.SCXML` should export this small surface; field names below are the intended contract:

```haskell
data ScxmlEdgeView = ForwardEdges | AllDeclaredEdges
  deriving stock (Eq, Show)

data ScxmlOptions = ScxmlOptions
  { edgeView :: ScxmlEdgeView
  , includeBehavior :: Bool
  }
  deriving stock (Eq, Show)

defaultScxmlOptions :: ScxmlOptions
-- ScxmlOptions ForwardEdges True

data ScxmlError
  = EmptyStateEnumeration
  | InitialStateNotEnumerated
  | TargetStateNotEnumerated
      { sourceStateId :: Text
      , edgeIndex :: Int
      }
  deriving stock (Eq, Show)

toSCXML ::
  (Eq s, Enum s, Bounded s, Show s) =>
  SymTransducer (HsPred rs ci) rs s ci co ->
  Either ScxmlError Text

toSCXMLWith ::
  (Eq s, Enum s, Bounded s, Show s) =>
  ScxmlOptions ->
  SymTransducer (HsPred rs ci) rs s ci co ->
  Either ScxmlError Text
```

`toSCXML` delegates to `toSCXMLWith defaultScxmlOptions`. Use equality to locate enumerated states instead of relying on `Show` equality or assuming `fromEnum` gives a dense range. Require lawful finite `Enum`/`Bounded`/`Eq` instances and finite edge lists; detecting nontermination or arbitrary broken instances is outside scope. Check empty enumeration, then initial membership, then targets in enumeration/declaration order. Errors report the original local edge index, including historical edges omitted from the displayed graph. XML and comment encoding helpers stay private.

The library uses existing `base`, `text`, and, if helpful, `containers`. It does not add JSON codecs, XML libraries, solvers, file IO, or external processes to export. Python is a check-time tool supplied by the existing Nix toolchain, not a runtime requirement for library consumers. Before introducing any additional dependency or compatibility workaround during implementation, use Mori to locate its sources and documentation, then verify registry releases and upstream tags before selecting bounds. Never search the filesystem root or `/nix/store` for dependency sources.
