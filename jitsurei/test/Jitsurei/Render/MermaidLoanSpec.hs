-- | EP-34 M6: Mermaid render goldens for the LoanApplication, Loan,
-- and CoreBankingSync aggregates. The pinned blocks below are
-- mirrored verbatim by the @docs/guide/diagrams/loan-*.mmd@ files
-- so the tutorial in M7 can embed identical diagrams without re-
-- generating them.
--
-- The 3-deep composite 'loanWorkflow' is intentionally not pinned:
-- the keiki renderer's flat 'toMermaidComposite' produces a
-- 6 × 3 × 3 = 54-vertex diagram whose composite identifiers
-- contain literal whitespace from the inner 'Composite' Show
-- instance ("Composite SyncIdle LoanInitial"), which most Mermaid
-- backends reject. The single-aggregate diagrams are sufficient
-- for the tutorial's pedagogical aims; a richer renderer for
-- nested composites is a follow-up.
module Jitsurei.Render.MermaidLoanSpec (spec) where

import Data.Text (Text)
import qualified Data.Text as T
import Test.Hspec

import Jitsurei.CoreBankingSync (coreBankingSync)
import Jitsurei.Loan (loan)
import Jitsurei.LoanApplication (loanApplication)
import Keiki.Render.Mermaid (toMermaid)


spec :: Spec
spec = do

  describe "toMermaid loanApplication" $
    it "renders the canonical six-vertex stateDiagram-v2 block" $
      toMermaid loanApplication `shouldBe` loanApplicationCanonical

  describe "toMermaid loan" $
    it "renders the three-vertex stateDiagram-v2 block" $
      toMermaid loan `shouldBe` loanCanonical

  describe "toMermaid coreBankingSync" $
    it "renders the three-vertex stateDiagram-v2 block" $
      toMermaid coreBankingSync `shouldBe` coreBankingSyncCanonical


-- | Canonical render for 'loanApplication'. Mirrored verbatim by
-- @docs/guide/diagrams/loan-application.mmd@.
loanApplicationCanonical :: Text
loanApplicationCanonical = unlinesNoTrail
  [ "stateDiagram-v2"
  , "    [*] --> Intake"
  , "    Intake --> CollectingDocuments : StartApplication / ApplicationStarted"
  , "    Intake --> Withdrawn : WithdrawApplication / ApplicationWithdrawn"
  , "    CollectingDocuments --> CollectingDocuments : SubmitIncomeDocument / IncomeDocumentReceived"
  , "    CollectingDocuments --> CollectingDocuments : SubmitIdDocument / IdDocumentReceived"
  , "    CollectingDocuments --> CollectingDocuments : RecordCreditScore / CreditScoreRecorded"
  , "    CollectingDocuments --> CollectingDocuments : RecordEmploymentCheck / EmploymentChecked"
  , "    CollectingDocuments --> Withdrawn : WithdrawApplication / ApplicationWithdrawn"
  , "    CollectingDocuments --> UnderReview : Continue / \x03B5"
  , "    UnderReview --> Approved : Continue / ApplicationApproved"
  , "    UnderReview --> Declined : Continue / ApplicationDeclined"
  , "    UnderReview --> Withdrawn : WithdrawApplication / ApplicationWithdrawn"
  , "    Approved --> [*]"
  , "    Declined --> [*]"
  , "    Withdrawn --> [*]"
  ]


-- | Canonical render for 'loan'. Mirrored verbatim by
-- @docs/guide/diagrams/loan.mmd@.
loanCanonical :: Text
loanCanonical = unlinesNoTrail
  [ "stateDiagram-v2"
  , "    [*] --> LoanInitial"
  , "    LoanInitial --> LoanAwaiting : CreateLoan / LoanCreated"
  , "    LoanAwaiting --> LoanLinked : AssignLegacyLoanId / LegacyLoanIdAssigned"
  , "    LoanLinked --> [*]"
  ]


-- | Canonical render for 'coreBankingSync'. Mirrored verbatim by
-- @docs/guide/diagrams/core-banking-sync.mmd@.
coreBankingSyncCanonical :: Text
coreBankingSyncCanonical = unlinesNoTrail
  [ "stateDiagram-v2"
  , "    [*] --> SyncIdle"
  , "    SyncIdle --> SyncRequested : LoanCreatedIn / SyncToLegacyRequested"
  , "    SyncRequested --> SyncSettled : LegacyCallbackReceivedIn / LegacyAssignmentCommanded"
  , "    SyncSettled --> [*]"
  ]


unlinesNoTrail :: [Text] -> Text
unlinesNoTrail = T.intercalate (T.pack "\n")
