{- | Regression tests for "Keiki.Render.Mermaid".

Pins the canonical Mermaid 'stateDiagram-v2' blocks produced by
'toMermaid' over 'Keiki.Fixtures.UserRegistration.userReg' (EP-30),
'toMermaidComposite' over the @AlertSource ⨾ EmailDelivery@
composite from "Keiki.CompositionSpec" (EP-31),
'toMermaidCompositeNested' over the same composite (EP-32),
'toMermaidAlternative' over @alternative emailDelivery pinger@
from "Keiki.CompositionAlternativeSpec" (EP-33),
'toMermaidFeedback1' over @feedback1 toggleAgg togglePolicy@ from
"Keiki.CompositionFeedback1Spec" (EP-33), and 'toMermaidCompose3' /
'toMermaidCompose3Nested' over the inline three-toy fixture
@toy3deep = toy1 \`compose\` (toy2 \`compose\` toy3)@ defined at
the bottom of this file (EP-35), so that any accidental formatting
drift surfaces in CI.

See:

  * @docs/plans/30-mermaid-renderer-for-single-symtransducer-canonical-example-diagrams.md@
    — single-transducer renderer.
  * @docs/plans/31-mermaid-rendering-for-composite-symtransducers.md@
    — composite renderer (flat cross-product, Shape A).
  * @docs/plans/32-shape-b-nested-subgraph-mermaid-rendering-for-larger-composites.md@
    — nested-subgraph renderer (Shape B).
  * @docs/plans/33-shape-aware-mermaid-renderers-for-alternative-and-feedback1-composites.md@
    — shape-aware renderers for `alternative` (parallel arms) and
    `feedback1` (flat 3-deep cross-product).
  * @docs/plans/35-mermaid-renderer-for-right-associative-3-deep-compose-composites.md@
    — right-associative 3-deep compose renderers (flat + one-level
    nested) and the synthetic three-toy fixture.
-}
module Keiki.Render.MermaidSpec (spec) where

import Data.Text (Text)
import Data.Text qualified as T
import Test.Hspec

import Keiki.Composition (Composite, compose)
import Keiki.CompositionAlternativeSpec (pinger)
import Keiki.CompositionFeedback1Spec (toggleAgg, togglePolicy)
import Keiki.CompositionSpec (alertSource)
import Keiki.Core (
    Edge (..),
    HsPred (..),
    InCtor (..),
    OutFields (..),
    RegFile (..),
    SymTransducer (..),
    Update (..),
    WireCtor (..),
    pack,
 )
import Keiki.Fixtures.EmailDelivery (emailDelivery)
import Keiki.Fixtures.UserRegistration (Vertex (..), userReg)
import Keiki.Render.Mermaid (
    MermaidGuardMode (..),
    MermaidLabelLayout (..),
    MermaidOptions (..),
    MermaidOutputLayout (..),
    MermaidStateLabels (..),
    defaultMermaidOptions,
    duplicateStateIds,
    toMermaid,
    toMermaidAlternative,
    toMermaidAtlas,
    toMermaidCompose3,
    toMermaidCompose3Nested,
    toMermaidComposite,
    toMermaidCompositeNested,
    toMermaidFeedback1,
    toMermaidWith,
    toMermaidWithLabels,
    vertexLabel,
 )

spec :: Spec
spec = do
    describe "toMermaid (single SymTransducer)" $
        it "renders userReg to the canonical stateDiagram-v2 block" $
            toMermaid userReg `shouldBe` userRegCanonical

    describe "toMermaidComposite (composite SymTransducer)" $
        it "renders the AlertSource ⨾ EmailDelivery pipeline" $
            toMermaidComposite (compose alertSource emailDelivery)
                `shouldBe` alertEmailCompositeCanonical

    describe "toMermaidCompositeNested (composite SymTransducer)" $
        it "renders the AlertSource ⨾ EmailDelivery pipeline in nested form" $
            toMermaidCompositeNested (compose alertSource emailDelivery)
                `shouldBe` alertEmailCompositeNestedCanonical

    describe "toMermaidAlternative (alternative composite)" $
        it "renders alternative emailDelivery pinger as parallel arms" $
            toMermaidAlternative emailDelivery pinger
                `shouldBe` emailPingerAltCanonical

    describe "toMermaidFeedback1 (feedback1 composite)" $
        it "renders feedback1 toggleAgg togglePolicy as flat 3-deep cross-product" $
            toMermaidFeedback1 toggleAgg togglePolicy
                `shouldBe` toggleFeedback1Canonical

    describe "toMermaidCompose3 (right-associative 3-deep compose)" $
        it "renders the toy1 ⨾ (toy2 ⨾ toy3) flat block" $
            toMermaidCompose3 toy3deep `shouldBe` toy3deepFlatCanonical

    describe "toMermaidCompose3Nested (right-associative 3-deep compose)" $
        it "renders the toy1 ⨾ (toy2 ⨾ toy3) one-level nested block" $
            toMermaidCompose3Nested toy3deep `shouldBe` toy3deepNestedCanonical

    -- EP-50 M3: the default must stay byte-identical to today (the
    -- guard-free pedagogy in deriving-lifecycle-transitions.md depends on
    -- it). The pre-existing "toMermaid (single SymTransducer)" golden above
    -- is the primary proof; this guards against toMermaid and toMermaidWith
    -- diverging under a future refactor.
    describe "toMermaidWith defaultMermaidOptions (byte-identical default)" $
        it "equals toMermaid userReg exactly" $
            toMermaidWith defaultMermaidOptions userReg `shouldBe` toMermaid userReg

    describe "toMermaidWith (annotated edge summary)" $
        it "renders userReg with written-slot and guard-summary suffixes" $
            toMermaidWith
                (defaultMermaidOptions{showWrittenSlots = True, showGuardSummary = True})
                userReg
                `shouldBe` userRegAnnotatedCanonical

    describe "toMermaidWith (MermaidGuardPretty, EP-61)" $
        it "renders userReg guards in domain-readable form" $
            toMermaidWith
                (defaultMermaidOptions{guardMode = MermaidGuardPretty})
                userReg
                `shouldBe` userRegPrettyGuardCanonical

    describe "toMermaidWith (multiline label layout, EP-63)" $
        it "renders userReg labels with <br/>-separated segments" $
            toMermaidWith
                ( defaultMermaidOptions
                    { showWrittenSlots = True
                    , showGuardSummary = True
                    , labelLayout = MermaidLabelMultiline
                    }
                )
                userReg
                `shouldBe` userRegMultilineCanonical

    describe "toMermaidWith (written-slot truncation, EP-63)" $
        it "truncates a long written-slot list with +N more" $
            toMermaidWith
                ( defaultMermaidOptions
                    { showWrittenSlots = True
                    , maxInlineWrittenSlots = Just 2
                    }
                )
                userReg
                `shouldBe` userRegSlotTruncCanonical

    describe "toMermaidWith (guard-width truncation, EP-63)" $
        it "truncates an over-long guard segment with an ellipsis" $
            toMermaidWith
                ( defaultMermaidOptions
                    { showGuardSummary = True
                    , maxInlineGuardWidth = Just 10
                    }
                )
                userReg
                `shouldBe` userRegGuardTruncCanonical

    describe "toMermaidWith (MermaidOutputSemicolon default, EP-63)" $
        it "renders multiEvt with the length-based default output layout" $
            toMermaid multiEvt `shouldBe` multiEvtSemicolonCanonical

    describe "toMermaidWith (MermaidOutputMultiline, EP-63)" $
        it "renders every multi-event edge one event per line" $
            toMermaidWith
                (defaultMermaidOptions{outputLayout = MermaidOutputMultiline})
                multiEvt
                `shouldBe` multiEvtMultilineCanonical

    describe "toMermaidWith (MermaidOutputCounted, EP-63)" $
        it "renders multi-event edges as an N events count" $
            toMermaidWith
                (defaultMermaidOptions{outputLayout = MermaidOutputCounted})
                multiEvt
                `shouldBe` multiEvtCountedCanonical

    describe "toMermaidWithLabels (stable ASCII ids, spaced display labels, EP-64)" $
        it "renders userReg with friendly labels and stable ids" $
            toMermaidWithLabels defaultMermaidOptions userRegLabels userReg
                `shouldBe` userRegLabeledCanonical

    describe "toMermaidWithLabels (id == display is byte-identical, EP-64)" $
        it "equals toMermaidWith when stateId == stateDisplayLabel" $
            toMermaidWithLabels
                defaultMermaidOptions
                (MermaidStateLabels{stateId = vertexLabel, stateDisplayLabel = vertexLabel})
                userReg
                `shouldBe` toMermaidWith defaultMermaidOptions userReg

    describe "duplicateStateIds (EP-64)" $ do
        it "is empty for a unique-id labels record" $
            duplicateStateIds userRegLabels userReg `shouldBe` []
        it "reports the colliding id for a clashing labels record" $
            duplicateStateIds collidingLabels userReg
                `shouldBe` [T.pack "X"]

    describe "toMermaidAtlas (multi-diagram document)" $
        it "assembles two labelled diagrams into one document" $
            toMermaidAtlas
                [ (T.pack "User registration", toMermaid userReg)
                , (T.pack "Alert \x2A3E Email", toMermaidComposite (compose alertSource emailDelivery))
                ]
                `shouldBe` atlasCanonical

{- | The canonical Mermaid block for @userReg@, mirrored verbatim from
the aggregate's diagram in @docs/guide/diagrams/user-registration.md@.
Stored inline (not in an external fixture file) so a formatting change
requires touching this file alongside the producer change.
-}
userRegCanonical :: Text
userRegCanonical =
    unlinesNoTrail
        -- EP-19 M7: the entrance is now a single length-2 multi-event edge;
        -- the renderer's length-based switchover formats it with a "; "
        -- separator (per the design note's Mermaid section).
        [ "stateDiagram-v2"
        , "    [*] --> PotentialCustomer"
        , "    PotentialCustomer --> RequiresConfirmation : StartRegistration / RegistrationStarted; ConfirmationEmailSent"
        , "    RequiresConfirmation --> Confirmed : ConfirmAccount / AccountConfirmed"
        , "    RequiresConfirmation --> RequiresConfirmation : ResendConfirmation / ConfirmationResent"
        , "    RequiresConfirmation --> Deleted : FulfillGDPRRequest / \x03B5"
        , "    Confirmed --> Deleted : FulfillGDPRRequest / AccountDeleted"
        , "    Deleted --> [*]"
        ]
  where
    unlinesNoTrail = T.intercalate (T.pack "\n")

{- | EP-50: the canonical block for @userReg@ rendered with both summary
flags on (@MermaidOptions True True@). Differs from 'userRegCanonical'
only by the bracketed @[w: …; g: …]@ suffixes. Captured verbatim from
the renderer (the slot order is the @UCombine@ nesting order, and each
guard is the actual 'HsPred' shape @onCmd@ produced — a bare 'PInCtor'
except where 'requireEq' added a 'PEq', giving @PAnd PInCtor PEq@).
-}
userRegAnnotatedCanonical :: Text
userRegAnnotatedCanonical =
    T.intercalate
        (T.pack "\n")
        [ "stateDiagram-v2"
        , "    [*] --> PotentialCustomer"
        , "    PotentialCustomer --> RequiresConfirmation : StartRegistration / RegistrationStarted; ConfirmationEmailSent [w: registeredAt; confirmCode; email; g: PInCtor]"
        , "    RequiresConfirmation --> Confirmed : ConfirmAccount / AccountConfirmed [w: confirmedAt; g: PAnd PInCtor PEq]"
        , "    RequiresConfirmation --> RequiresConfirmation : ResendConfirmation / ConfirmationResent [w: registeredAt; confirmCode; g: PInCtor]"
        , "    RequiresConfirmation --> Deleted : FulfillGDPRRequest / \x03B5 [w: deletedAt; g: PInCtor]"
        , "    Confirmed --> Deleted : FulfillGDPRRequest / AccountDeleted [w: deletedAt; g: PInCtor]"
        , "    Deleted --> [*]"
        ]

{- | EP-61: the canonical block for @userReg@ rendered with
@guardMode = MermaidGuardPretty@ and 'showWrittenSlots' left at its
default 'False', so each label carries only a domain-readable
@[g: …]@ segment. Differs from 'userRegAnnotatedCanonical' by
rendering real names — @ConfirmAccount@, @confirmCode@ — instead of
the structural constructor-tag walk (@PAnd PInCtor PEq@). Captured
verbatim from the renderer.
-}
userRegPrettyGuardCanonical :: Text
userRegPrettyGuardCanonical =
    T.intercalate
        (T.pack "\n")
        [ "stateDiagram-v2"
        , "    [*] --> PotentialCustomer"
        , "    PotentialCustomer --> RequiresConfirmation : StartRegistration / RegistrationStarted; ConfirmationEmailSent [g: StartRegistration]"
        , "    RequiresConfirmation --> Confirmed : ConfirmAccount / AccountConfirmed [g: (ConfirmAccount && ConfirmAccount.confirmCode == confirmCode)]"
        , "    RequiresConfirmation --> RequiresConfirmation : ResendConfirmation / ConfirmationResent [g: ResendConfirmation]"
        , "    RequiresConfirmation --> Deleted : FulfillGDPRRequest / \x03B5 [g: FulfillGDPRRequest]"
        , "    Confirmed --> Deleted : FulfillGDPRRequest / AccountDeleted [g: FulfillGDPRRequest]"
        , "    Deleted --> [*]"
        ]

{- | EP-63: @userReg@ rendered with both summary flags on and
@labelLayout = MermaidLabelMultiline@. Same per-edge content as
'userRegAnnotatedCanonical', but the bracketed inline suffix is replaced
by @<br/>@-separated segments: the @command / event@ base on the first
line, the @w: …@ segment next, the @g: …@ segment last. The 2-event
output @RegistrationStarted; ConfirmationEmailSent@ keeps its @;@
separator because that is the base segment's own (length-based) output
rendering, not a label segment.
-}
userRegMultilineCanonical :: Text
userRegMultilineCanonical =
    T.intercalate
        (T.pack "\n")
        [ "stateDiagram-v2"
        , "    [*] --> PotentialCustomer"
        , "    PotentialCustomer --> RequiresConfirmation : StartRegistration / RegistrationStarted; ConfirmationEmailSent<br/>w: registeredAt; confirmCode; email<br/>g: PInCtor"
        , "    RequiresConfirmation --> Confirmed : ConfirmAccount / AccountConfirmed<br/>w: confirmedAt<br/>g: PAnd PInCtor PEq"
        , "    RequiresConfirmation --> RequiresConfirmation : ResendConfirmation / ConfirmationResent<br/>w: registeredAt; confirmCode<br/>g: PInCtor"
        , "    RequiresConfirmation --> Deleted : FulfillGDPRRequest / \x03B5<br/>w: deletedAt<br/>g: PInCtor"
        , "    Confirmed --> Deleted : FulfillGDPRRequest / AccountDeleted<br/>w: deletedAt<br/>g: PInCtor"
        , "    Deleted --> [*]"
        ]

{- | EP-63: @userReg@ rendered with @showWrittenSlots = True@ and
@maxInlineWrittenSlots = Just 2@. The only edge writing more than two
slots is @StartRegistration@ (three slots), which truncates to the first
two followed by a single @+1 more@ token; every other edge writes two or
fewer slots and is unchanged.
-}
userRegSlotTruncCanonical :: Text
userRegSlotTruncCanonical =
    T.intercalate
        (T.pack "\n")
        [ "stateDiagram-v2"
        , "    [*] --> PotentialCustomer"
        , "    PotentialCustomer --> RequiresConfirmation : StartRegistration / RegistrationStarted; ConfirmationEmailSent [w: registeredAt; confirmCode; +1 more]"
        , "    RequiresConfirmation --> Confirmed : ConfirmAccount / AccountConfirmed [w: confirmedAt]"
        , "    RequiresConfirmation --> RequiresConfirmation : ResendConfirmation / ConfirmationResent [w: registeredAt; confirmCode]"
        , "    RequiresConfirmation --> Deleted : FulfillGDPRRequest / \x03B5 [w: deletedAt]"
        , "    Confirmed --> Deleted : FulfillGDPRRequest / AccountDeleted [w: deletedAt]"
        , "    Deleted --> [*]"
        ]

{- | EP-63: @userReg@ rendered with @showGuardSummary = True@ and
@maxInlineGuardWidth = Just 10@. The only guard whose structural text
exceeds ten characters is @ConfirmAccount@'s @PAnd PInCtor PEq@ (length
16), truncated to the first ten characters plus the ellipsis @…@. The
other guards (@PInCtor@, length 7) are within the width and unchanged.
-}
userRegGuardTruncCanonical :: Text
userRegGuardTruncCanonical =
    T.intercalate
        (T.pack "\n")
        [ "stateDiagram-v2"
        , "    [*] --> PotentialCustomer"
        , "    PotentialCustomer --> RequiresConfirmation : StartRegistration / RegistrationStarted; ConfirmationEmailSent [g: PInCtor]"
        , "    RequiresConfirmation --> Confirmed : ConfirmAccount / AccountConfirmed [g: PAnd PInCt\x2026]"
        , "    RequiresConfirmation --> RequiresConfirmation : ResendConfirmation / ConfirmationResent [g: PInCtor]"
        , "    RequiresConfirmation --> Deleted : FulfillGDPRRequest / \x03B5 [g: PInCtor]"
        , "    Confirmed --> Deleted : FulfillGDPRRequest / AccountDeleted [g: PInCtor]"
        , "    Deleted --> [*]"
        ]

{- | EP-63: the @multiEvt@ fixture (defined at the bottom of this file)
rendered with the default @outputLayout = MermaidOutputSemicolon@. The
3-event edge joins with @<br/>@ (three or more events), the 2-event edge
joins with @;@ — exactly the renderer's historical length-based
behaviour, so @toMermaid multiEvt@ pins it.
-}
multiEvtSemicolonCanonical :: Text
multiEvtSemicolonCanonical =
    T.intercalate
        (T.pack "\n")
        [ "stateDiagram-v2"
        , "    [*] --> MS0"
        , "    MS0 --> MS1 : Go / A<br/>B<br/>C"
        , "    MS1 --> MS2 : Go / A; B"
        , "    MS2 --> [*]"
        ]

{- | EP-63: @multiEvt@ rendered with @outputLayout =
MermaidOutputMultiline@. Every multi-event edge is one event per line
regardless of count, so the 2-event edge becomes @A<br/>B@ (unlike the
default's @A; B@) and the 3-event edge is unchanged from the default.
-}
multiEvtMultilineCanonical :: Text
multiEvtMultilineCanonical =
    T.intercalate
        (T.pack "\n")
        [ "stateDiagram-v2"
        , "    [*] --> MS0"
        , "    MS0 --> MS1 : Go / A<br/>B<br/>C"
        , "    MS1 --> MS2 : Go / A<br/>B"
        , "    MS2 --> [*]"
        ]

{- | EP-63: @multiEvt@ rendered with @outputLayout =
MermaidOutputCounted@. Each multi-event edge collapses to an @N events@
count.
-}
multiEvtCountedCanonical :: Text
multiEvtCountedCanonical =
    T.intercalate
        (T.pack "\n")
        [ "stateDiagram-v2"
        , "    [*] --> MS0"
        , "    MS0 --> MS1 : Go / 3 events"
        , "    MS1 --> MS2 : Go / 2 events"
        , "    MS2 --> [*]"
        ]

{- | EP-64: a labels record mapping each @userReg@ 'Vertex' to its
@show@-derived stable ASCII id and a friendly spaced display label.
@Confirmed@ and @Deleted@ map to display labels equal to their ids, so
they get no @state \"…\" as …@ declaration; @PotentialCustomer@ and
@RequiresConfirmation@ get spaced labels and therefore declarations.
-}
userRegLabels :: MermaidStateLabels Vertex
userRegLabels =
    MermaidStateLabels
        { stateId = T.pack . show
        , stateDisplayLabel = \case
            PotentialCustomer -> T.pack "Potential Customer"
            RequiresConfirmation -> T.pack "Requires Confirmation"
            Confirmed -> T.pack "Confirmed"
            Deleted -> T.pack "Deleted"
        }

{- | EP-64: a deliberately broken labels record collapsing every
'Vertex' onto the single id @\"X\"@, so 'duplicateStateIds' reports
@\"X\"@ once.
-}
collidingLabels :: MermaidStateLabels Vertex
collidingLabels =
    MermaidStateLabels
        { stateId = const (T.pack "X")
        , stateDisplayLabel = T.pack . show
        }

{- | EP-64: @userReg@ rendered by 'toMermaidWithLabels' with
'userRegLabels'. Two @state \"…\" as …@ declarations (for the two
spaced labels) precede the initial-state line; every transition arrow
still uses the stable ASCII id, so the topology below the declarations
is byte-identical to 'userRegCanonical'.
-}
userRegLabeledCanonical :: Text
userRegLabeledCanonical =
    T.intercalate
        (T.pack "\n")
        [ "stateDiagram-v2"
        , "    state \"Potential Customer\" as PotentialCustomer"
        , "    state \"Requires Confirmation\" as RequiresConfirmation"
        , "    [*] --> PotentialCustomer"
        , "    PotentialCustomer --> RequiresConfirmation : StartRegistration / RegistrationStarted; ConfirmationEmailSent"
        , "    RequiresConfirmation --> Confirmed : ConfirmAccount / AccountConfirmed"
        , "    RequiresConfirmation --> RequiresConfirmation : ResendConfirmation / ConfirmationResent"
        , "    RequiresConfirmation --> Deleted : FulfillGDPRRequest / \x03B5"
        , "    Confirmed --> Deleted : FulfillGDPRRequest / AccountDeleted"
        , "    Deleted --> [*]"
        ]

{- | EP-50: the canonical atlas document for @userReg@ + the
@AlertSource ⨾ EmailDelivery@ composite. Built from the same canonical
diagram blocks the other goldens pin, wrapped in the atlas format
('toMermaidAtlas': a @## @ heading then a fenced @mermaid@ block per
section, sections joined by a blank line) — so this golden pins the
atlas wrapping/joining independently of the diagram contents.
-}
atlasCanonical :: Text
atlasCanonical =
    T.intercalate
        (T.pack "\n\n")
        [ T.pack "## User registration\n\n```mermaid\n"
            <> userRegCanonical
            <> T.pack "\n```"
        , T.pack "## Alert \x2A3E Email\n\n```mermaid\n"
            <> alertEmailCompositeCanonical
            <> T.pack "\n```"
        ]

{- | The canonical Mermaid block for the @AlertSource ⨾ EmailDelivery@
composite, mirrored verbatim from the diagram in
@docs/guide/diagrams/composite-alert-email.md@. Three lines: the
initial-state marker pointing at @Composite AlertQuiescent
EmailPending@, the single cross-product edge that advances both
component vertices in one step, and the final-state marker for the
terminal composite vertex. The other two reachable composite
vertices have no outgoing edges and are not final, so the renderer
omits them (same convention as 'toMermaid').
-}
alertEmailCompositeCanonical :: Text
alertEmailCompositeCanonical =
    T.intercalate
        (T.pack "\n")
        [ "stateDiagram-v2"
        , "    [*] --> AlertQuiescent_EmailPending"
        , "    AlertQuiescent_EmailPending --> AlertEmitted_EmailSentVertex : TriggerAlert / EmailSent"
        , "    AlertEmitted_EmailSentVertex --> [*]"
        ]

{- | The canonical Mermaid block for the same composite under
'toMermaidCompositeNested' (Shape B). Differences from
'alertEmailCompositeCanonical': the body adds two
@state AlertQuiescent { … } / state AlertEmitted { … }@ blocks
(between the initial-state line and the edge line) listing every
composite vertex grouped under its outer @s1@ parent. The
cross-cutting transition and the final-state line are emitted at
the top level using the same flat
@\<show s1\>_\<show s2\>@ identifiers; no Mermaid
@Outer.Inner@ dotted syntax is used. See
@docs/guide/diagrams/composite-alert-email-nested.md@.
-}
alertEmailCompositeNestedCanonical :: Text
alertEmailCompositeNestedCanonical =
    T.intercalate
        (T.pack "\n")
        [ "stateDiagram-v2"
        , "    [*] --> AlertQuiescent_EmailPending"
        , "    state AlertQuiescent {"
        , "        AlertQuiescent_EmailPending"
        , "        AlertQuiescent_EmailSentVertex"
        , "    }"
        , "    state AlertEmitted {"
        , "        AlertEmitted_EmailPending"
        , "        AlertEmitted_EmailSentVertex"
        , "    }"
        , "    AlertQuiescent_EmailPending --> AlertEmitted_EmailSentVertex : TriggerAlert / EmailSent"
        , "    AlertEmitted_EmailSentVertex --> [*]"
        ]

{- | The canonical Mermaid block for @toMermaidAlternative
emailDelivery pinger@. Two top-level @[*] -->@ initial markers,
one for each arm; two named @state … { … }@ blocks holding each
arm's edges; two top-level @--> [*]@ final markers. Mirrors the
diagram in
@docs/guide/diagrams/composite-email-pinger-alternative.md@.
-}
emailPingerAltCanonical :: Text
emailPingerAltCanonical =
    T.intercalate
        (T.pack "\n")
        [ "stateDiagram-v2"
        , "    [*] --> EmailPending"
        , "    [*] --> PingIdle"
        , "    state LeftArm {"
        , "        EmailPending --> EmailSentVertex : SendEmail / EmailSent"
        , "    }"
        , "    state RightArm {"
        , "        PingIdle --> PingDone : Ping / Pong"
        , "    }"
        , "    EmailSentVertex --> [*]"
        , "    PingDone --> [*]"
        ]

{- | The canonical Mermaid block for @toMermaidFeedback1 toggleAgg
togglePolicy@. Flat 3-deep cross-product labels
@\<outer\>_\<policy\>_\<inner\>@. All four composite vertices
appear because the cascade fires at every enumerated vertex
(the policy + inner-toggle synchronisation is independent of
which vertex the outer toggle currently occupies), and both
'toggleAgg' and 'togglePolicy' use @isFinal = const True@ so
every composite vertex is final. Two of the four (the
@Off_Pol_On@ / @On_Pol_Off@ pair) are unreachable from the
initial vertex; the renderer surfaces them anyway because the
enumeration walks the static cross-product. See the diagram in
@docs/guide/diagrams/composite-toggle-feedback1.md@ and the
Decision Log entry of 2026-05-03 in
@docs/plans/33-shape-aware-mermaid-renderers-for-alternative-and-feedback1-composites.md@.
-}
toggleFeedback1Canonical :: Text
toggleFeedback1Canonical =
    T.intercalate
        (T.pack "\n")
        [ "stateDiagram-v2"
        , "    [*] --> Off_Pol_Off"
        , "    Off_Pol_Off --> On_Pol_On : TgFlip / TgFlipped"
        , "    Off_Pol_On --> On_Pol_Off : TgFlip / TgFlipped"
        , "    On_Pol_Off --> Off_Pol_On : TgFlip / TgFlipped"
        , "    On_Pol_On --> Off_Pol_Off : TgFlip / TgFlipped"
        , "    Off_Pol_Off --> [*]"
        , "    Off_Pol_On --> [*]"
        , "    On_Pol_Off --> [*]"
        , "    On_Pol_On --> [*]"
        ]

-- * Synthetic 3-deep compose fixture (EP-35 M1 / M2) -------------------

{- | A minimal shared command/event type for the three toy aggregates.
Single nullary constructor so each toy's edge needs only a trivial
guard ('PInCtor' on 'inCtorTick') and a trivial output ('pack' over
the same constructor on both sides). The empty payload also makes
the 'InCtor' / 'WireCtor' values fully recoverable without any TH.
-}
data Tick = Tick
    deriving (Eq, Show)

inCtorTick :: InCtor Tick '[]
inCtorTick =
    InCtor
        { icName = "Tick"
        , icMatch = \Tick -> Just RNil
        , icBuild = \RNil -> Tick
        }

wireTick :: WireCtor Tick ()
wireTick =
    WireCtor
        { wcName = "Tick"
        , wcMatch = \Tick -> Just ()
        , wcBuild = \() -> Tick
        }

data T1 = T1A | T1B
    deriving (Eq, Show, Enum, Bounded)

data T2 = T2A | T2B
    deriving (Eq, Show, Enum, Bounded)

data T3 = T3A | T3B
    deriving (Eq, Show, Enum, Bounded)

{- | Each toy advances on a single 'Tick' command from the @A@ vertex
to the @B@ vertex; the @B@ vertex is final and has no outgoing
edges. All three toys share the @Tick@ alphabet so the
right-associative 'compose' chain type-checks without lifters.
-}
toy1 :: SymTransducer (HsPred '[] Tick) '[] T1 Tick Tick
toy1 =
    mkToy
        T1A
        T1B
        (\case T1A -> True; T1B -> False)
        (\case T1B -> True; T1A -> False)

toy2 :: SymTransducer (HsPred '[] Tick) '[] T2 Tick Tick
toy2 =
    mkToy
        T2A
        T2B
        (\case T2A -> True; T2B -> False)
        (\case T2B -> True; T2A -> False)

toy3 :: SymTransducer (HsPred '[] Tick) '[] T3 Tick Tick
toy3 =
    mkToy
        T3A
        T3B
        (\case T3A -> True; T3B -> False)
        (\case T3B -> True; T3A -> False)

{- | Shared toy-aggregate factory: one Tick edge from the source
vertex to the target vertex; target is final. Parameterised on the
vertex predicates so each call site uses its own concrete vertex
type.
-}
mkToy ::
    s ->
    s ->
    (s -> Bool) ->
    (s -> Bool) ->
    SymTransducer (HsPred '[] Tick) '[] s Tick Tick
mkToy src tgt isSrc isFinalAt =
    SymTransducer
        { edgesOut = \s ->
            if isSrc s
                then
                    [ Edge
                        { guard = PInCtor inCtorTick
                        , update = UKeep
                        , output = [pack inCtorTick wireTick OFNil]
                        , target = tgt
                        }
                    ]
                else []
        , initial = src
        , initialRegs = RNil
        , isFinal = isFinalAt
        }

{- | The right-associative 3-deep compose @toy1 \`compose\` (toy2
\`compose\` toy3)@. Vertex type
@'Composite' T1 ('Composite' T2 T3)@; 2 × 2 × 2 = 8 composite
vertices walked by the renderer's @[minBound .. maxBound]@.
-}
toy3deep ::
    SymTransducer
        (HsPred '[] Tick)
        '[]
        (Composite T1 (Composite T2 T3))
        Tick
        Tick
toy3deep = toy1 `compose` (toy2 `compose` toy3)

{- | Canonical Mermaid block for @toMermaidCompose3 toy3deep@.
Generated by running the renderer at the REPL and pasted verbatim;
regenerate via the recipe in
@docs/plans/35-mermaid-renderer-for-right-associative-3-deep-compose-composites.md@'s
Concrete Steps section if 'toMermaidCompose3' or 'compose'
semantics ever change.
-}
toy3deepFlatCanonical :: Text
toy3deepFlatCanonical =
    T.intercalate
        (T.pack "\n")
        [ "stateDiagram-v2"
        , "    [*] --> T1A_T2A_T3A"
        , "    T1A_T2A_T3A --> T1B_T2B_T3B : Tick / Tick"
        , "    T1B_T2B_T3B --> [*]"
        ]

{- | Canonical Mermaid block for @toMermaidCompose3Nested toy3deep@.
Same fixture as the flat variant; differs in the per-outer
@state … { … }@ wrapping. Outer @T1@ vertices each list four
@T1?_T2?_T3?@ inner identifiers (the @T2@ × @T3@ cross-product
enumerated within @Composite T2 T3@'s 'Bounded' / 'Enum'
instances). Edges and finals remain at the top level using flat
identifiers.
-}
toy3deepNestedCanonical :: Text
toy3deepNestedCanonical =
    T.intercalate
        (T.pack "\n")
        [ "stateDiagram-v2"
        , "    [*] --> T1A_T2A_T3A"
        , "    state T1A {"
        , "        T1A_T2A_T3A"
        , "        T1A_T2A_T3B"
        , "        T1A_T2B_T3A"
        , "        T1A_T2B_T3B"
        , "    }"
        , "    state T1B {"
        , "        T1B_T2A_T3A"
        , "        T1B_T2A_T3B"
        , "        T1B_T2B_T3A"
        , "        T1B_T2B_T3B"
        , "    }"
        , "    T1A_T2A_T3A --> T1B_T2B_T3B : Tick / Tick"
        , "    T1B_T2B_T3B --> [*]"
        ]

-- * Multi-event output fixture (EP-63 M2) -----------------------------

{- | A three-constructor event type so an edge can emit two and three
distinct events, exercising every 'MermaidOutputLayout'. The wire-ctor
names (@A@, @B@, @C@) are what the renderer prints.
-}
data MEvt = MA | MB | MC
    deriving (Eq, Show)

-- | A single nullary command for the multi-event fixture.
data MCmd = MGo
    deriving (Eq, Show)

{- | Three vertices: @MS0@ emits three events, @MS1@ emits two, @MS2@
is final with no outgoing edge — enough to show all three output
layouts and the length-based default's @;@-vs-@<br/>@ switchover.
-}
data MS = MS0 | MS1 | MS2
    deriving (Eq, Show, Enum, Bounded)

inCtorGo :: InCtor MCmd '[]
inCtorGo =
    InCtor
        { icName = "Go"
        , icMatch = \MGo -> Just RNil
        , icBuild = \RNil -> MGo
        }

wireMA, wireMB, wireMC :: WireCtor MEvt ()
wireMA =
    WireCtor
        { wcName = "A"
        , wcMatch = \case MA -> Just (); _ -> Nothing
        , wcBuild = \() -> MA
        }
wireMB =
    WireCtor
        { wcName = "B"
        , wcMatch = \case MB -> Just (); _ -> Nothing
        , wcBuild = \() -> MB
        }
wireMC =
    WireCtor
        { wcName = "C"
        , wcMatch = \case MC -> Just (); _ -> Nothing
        , wcBuild = \() -> MC
        }

{- | A tiny transducer whose @MS0@ edge emits three events and whose
@MS1@ edge emits two, so the three 'MermaidOutputLayout' goldens differ
observably. Both edges share the trivial guard @PInCtor inCtorGo@, so
the input half of every label reads @Go@.
-}
multiEvt :: SymTransducer (HsPred '[] MCmd) '[] MS MCmd MEvt
multiEvt =
    SymTransducer
        { edgesOut = \case
            MS0 ->
                [ Edge
                    { guard = PInCtor inCtorGo
                    , update = UKeep
                    , output =
                        [ pack inCtorGo wireMA OFNil
                        , pack inCtorGo wireMB OFNil
                        , pack inCtorGo wireMC OFNil
                        ]
                    , target = MS1
                    }
                ]
            MS1 ->
                [ Edge
                    { guard = PInCtor inCtorGo
                    , update = UKeep
                    , output =
                        [ pack inCtorGo wireMA OFNil
                        , pack inCtorGo wireMB OFNil
                        ]
                    , target = MS2
                    }
                ]
            MS2 -> []
        , initial = MS0
        , initialRegs = RNil
        , isFinal = \case MS2 -> True; _ -> False
        }
