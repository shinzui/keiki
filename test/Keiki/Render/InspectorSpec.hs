-- | Golden tests for "Keiki.Render.Inspector": the Markdown edge-detail
-- renderer. Pins the exact document produced for the real multi-edge
-- fixture 'Keiki.Fixtures.UserRegistration.userReg' — the same
-- transducer the Mermaid golden renders — so a reviewer can diff the
-- inspector document against the diagram and see they describe the same
-- edges.
module Keiki.Render.InspectorSpec (spec) where

import Data.Text (Text)
import Data.Text qualified as T
import Keiki.Fixtures.UserRegistration (userReg)
import Keiki.Render.Inspector
  ( EdgeInspectorOptions (..),
    defaultEdgeInspectorOptions,
    renderEdgeInspector,
  )
import Test.Hspec

spec :: Spec
spec = do
  describe "renderEdgeInspector (default options)" $
    it "renders userReg to the canonical Markdown inspector block" $
      renderEdgeInspector defaultEdgeInspectorOptions userReg
        `shouldBe` userRegInspectorCanonical

  describe "renderEdgeInspector (includePrettyGuard)" $
    it "shows both the structural and the domain-readable guard" $
      renderEdgeInspector
        (defaultEdgeInspectorOptions {includePrettyGuard = True})
        userReg
        `shouldBe` userRegInspectorPrettyGuardCanonical

  describe "renderEdgeInspector (includeOutputFields)" $
    it "lists each output field's term positionally" $
      renderEdgeInspector
        (defaultEdgeInspectorOptions {includeOutputFields = True})
        userReg
        `shouldBe` userRegInspectorOutputFieldsCanonical

-- | The default inspector document for @userReg@: edge index, structural
-- guard, and written slots on; pretty guard and output fields off.
-- @Deleted@ has no outgoing edges, so it produces no section; the
-- @FulfillGDPRRequest@ edge from @RequiresConfirmation@ emits no event,
-- so its output renders the literal ε (U+03B5). Edge indices are the
-- 0-based @edgesOut@ positions (note the self-loop at index 1 and the
-- delete edge at index 2).
userRegInspectorCanonical :: Text
userRegInspectorCanonical =
  T.intercalate
    (T.pack "\n")
    [ "# Edge inspector",
      "",
      "### PotentialCustomer",
      "",
      "- **PotentialCustomer -> RequiresConfirmation**",
      "  - edge index: 0",
      "  - input: StartRegistration",
      "  - output: RegistrationStarted; ConfirmationEmailSent",
      "  - guard (structural): PInCtor",
      "  - written slots: registeredAt; confirmCode; email",
      "",
      "### RequiresConfirmation",
      "",
      "- **RequiresConfirmation -> Confirmed**",
      "  - edge index: 0",
      "  - input: ConfirmAccount",
      "  - output: AccountConfirmed",
      "  - guard (structural): PAnd PInCtor PEq",
      "  - written slots: confirmedAt",
      "- **RequiresConfirmation -> RequiresConfirmation**",
      "  - edge index: 1",
      "  - input: ResendConfirmation",
      "  - output: ConfirmationResent",
      "  - guard (structural): PInCtor",
      "  - written slots: registeredAt; confirmCode",
      "- **RequiresConfirmation -> Deleted**",
      "  - edge index: 2",
      "  - input: FulfillGDPRRequest",
      "  - output: AccountDeleted",
      "  - guard (structural): PInCtor",
      "  - written slots: deletedAt",
      "",
      "### Confirmed",
      "",
      "- **Confirmed -> Deleted**",
      "  - edge index: 0",
      "  - input: FulfillGDPRRequest",
      "  - output: AccountDeleted",
      "  - guard (structural): PInCtor",
      "  - written slots: deletedAt"
    ]

-- | With @includePrettyGuard = True@ each edge shows BOTH the structural
-- guard and the domain-readable guard (from
-- 'Keiki.Render.Pretty.prettyPred'). The contrast is the payoff: the
-- @ConfirmAccount@ edge reads @PAnd PInCtor PEq@ structurally and
-- @(ConfirmAccount && ConfirmAccount.confirmCode == confirmCode)@ pretty.
userRegInspectorPrettyGuardCanonical :: Text
userRegInspectorPrettyGuardCanonical =
  T.intercalate
    (T.pack "\n")
    [ "# Edge inspector",
      "",
      "### PotentialCustomer",
      "",
      "- **PotentialCustomer -> RequiresConfirmation**",
      "  - edge index: 0",
      "  - input: StartRegistration",
      "  - output: RegistrationStarted; ConfirmationEmailSent",
      "  - guard (structural): PInCtor",
      "  - guard (pretty): StartRegistration",
      "  - written slots: registeredAt; confirmCode; email",
      "",
      "### RequiresConfirmation",
      "",
      "- **RequiresConfirmation -> Confirmed**",
      "  - edge index: 0",
      "  - input: ConfirmAccount",
      "  - output: AccountConfirmed",
      "  - guard (structural): PAnd PInCtor PEq",
      "  - guard (pretty): (ConfirmAccount && ConfirmAccount.confirmCode == confirmCode)",
      "  - written slots: confirmedAt",
      "- **RequiresConfirmation -> RequiresConfirmation**",
      "  - edge index: 1",
      "  - input: ResendConfirmation",
      "  - output: ConfirmationResent",
      "  - guard (structural): PInCtor",
      "  - guard (pretty): ResendConfirmation",
      "  - written slots: registeredAt; confirmCode",
      "- **RequiresConfirmation -> Deleted**",
      "  - edge index: 2",
      "  - input: FulfillGDPRRequest",
      "  - output: AccountDeleted",
      "  - guard (structural): PInCtor",
      "  - guard (pretty): FulfillGDPRRequest",
      "  - written slots: deletedAt",
      "",
      "### Confirmed",
      "",
      "- **Confirmed -> Deleted**",
      "  - edge index: 0",
      "  - input: FulfillGDPRRequest",
      "  - output: AccountDeleted",
      "  - guard (structural): PInCtor",
      "  - guard (pretty): FulfillGDPRRequest",
      "  - written slots: deletedAt"
    ]

-- | With @includeOutputFields = True@ each edge that emits at least one
-- output field gains an @output fields@ bullet listing each field's term
-- positionally (via 'Keiki.Render.Pretty.prettyTerm'), grouped by output
-- constructor. Fields are labelled by position only — 'WireCtor' carries
-- no field names. The ε-edge (no output) gets no such bullet. Note the
-- terms mix input-field reads (@StartRegistration.email@) and register
-- reads (@email@).
userRegInspectorOutputFieldsCanonical :: Text
userRegInspectorOutputFieldsCanonical =
  T.intercalate
    (T.pack "\n")
    [ "# Edge inspector",
      "",
      "### PotentialCustomer",
      "",
      "- **PotentialCustomer -> RequiresConfirmation**",
      "  - edge index: 0",
      "  - input: StartRegistration",
      "  - output: RegistrationStarted; ConfirmationEmailSent",
      "  - output fields: RegistrationStarted[field 0: StartRegistration.email; field 1: StartRegistration.confirmCode; field 2: StartRegistration.at]; ConfirmationEmailSent[field 0: StartRegistration.email]",
      "  - guard (structural): PInCtor",
      "  - written slots: registeredAt; confirmCode; email",
      "",
      "### RequiresConfirmation",
      "",
      "- **RequiresConfirmation -> Confirmed**",
      "  - edge index: 0",
      "  - input: ConfirmAccount",
      "  - output: AccountConfirmed",
      "  - output fields: AccountConfirmed[field 0: email; field 1: ConfirmAccount.confirmCode; field 2: ConfirmAccount.at]",
      "  - guard (structural): PAnd PInCtor PEq",
      "  - written slots: confirmedAt",
      "- **RequiresConfirmation -> RequiresConfirmation**",
      "  - edge index: 1",
      "  - input: ResendConfirmation",
      "  - output: ConfirmationResent",
      "  - output fields: ConfirmationResent[field 0: email; field 1: ResendConfirmation.code; field 2: ResendConfirmation.at]",
      "  - guard (structural): PInCtor",
      "  - written slots: registeredAt; confirmCode",
      "- **RequiresConfirmation -> Deleted**",
      "  - edge index: 2",
      "  - input: FulfillGDPRRequest",
      "  - output: AccountDeleted",
      "  - output fields: AccountDeleted[field 0: email; field 1: FulfillGDPRRequest.at]",
      "  - guard (structural): PInCtor",
      "  - written slots: deletedAt",
      "",
      "### Confirmed",
      "",
      "- **Confirmed -> Deleted**",
      "  - edge index: 0",
      "  - input: FulfillGDPRRequest",
      "  - output: AccountDeleted",
      "  - output fields: AccountDeleted[field 0: email; field 1: FulfillGDPRRequest.at]",
      "  - guard (structural): PInCtor",
      "  - written slots: deletedAt"
    ]
