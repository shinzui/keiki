-- | Regression test for "Keiki.Render.Mermaid". Pins the canonical
-- Mermaid 'stateDiagram-v2' block produced by 'toMermaid' over the
-- 'Keiki.Examples.UserRegistration.userReg' aggregate so that any
-- accidental formatting drift surfaces in CI.
--
-- See @docs/plans/30-mermaid-renderer-for-single-symtransducer-canonical-example-diagrams.md@
-- for the design and the canonical-block source of truth.
module Keiki.Render.MermaidSpec (spec) where

import Data.Text (Text)
import qualified Data.Text as T
import Test.Hspec

import Keiki.Examples.UserRegistration (userReg)
import Keiki.Render.Mermaid (toMermaid)


spec :: Spec
spec = describe "toMermaid (single SymTransducer)" $
  it "renders userReg to the canonical stateDiagram-v2 block" $
    toMermaid userReg `shouldBe` userRegCanonical


-- | The canonical Mermaid block for @userReg@, mirrored verbatim from
-- the aggregate's diagram in @docs/guide/diagrams/user-registration.md@.
-- Stored inline (not in an external fixture file) so a formatting change
-- requires touching this file alongside the producer change.
userRegCanonical :: Text
userRegCanonical = unlinesNoTrail
  [ "stateDiagram-v2"
  , "    [*] --> PotentialCustomer"
  , "    PotentialCustomer --> Registering : StartRegistration / RegistrationStarted"
  , "    Registering --> RequiresConfirmation : Continue / ConfirmationEmailSent"
  , "    RequiresConfirmation --> Confirmed : ConfirmAccount / AccountConfirmed"
  , "    RequiresConfirmation --> RequiresConfirmation : ResendConfirmation / ConfirmationResent"
  , "    RequiresConfirmation --> Deleted : FulfillGDPRRequest / \x03B5"
  , "    Confirmed --> Deleted : FulfillGDPRRequest / AccountDeleted"
  , "    Deleted --> [*]"
  ]
  where
    unlinesNoTrail = T.intercalate (T.pack "\n")
