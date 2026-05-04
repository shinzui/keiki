-- | EP-34 M6 + EP-35 M3: Mermaid render goldens for the
-- LoanApplication, Loan, and CoreBankingSync aggregates and for the
-- 3-deep right-associative composite 'loanWorkflow'. The pinned
-- blocks below are mirrored verbatim by the
-- @docs/guide/diagrams/loan-*.mmd@ files so the tutorial in EP-34
-- M7 can embed identical diagrams without re-generating them.
--
-- The composite goldens were deferred during EP-34 M6 because none
-- of the renderers shipped through EP-33 fits the
-- @Composite LoanAppVertex (Composite SyncVertex LoanVertex)@ shape
-- (right-associative 3-deep with three distinct types). EP-35
-- closed the gap by adding 'Keiki.Render.Mermaid.toMermaidCompose3'
-- (flat) and 'Keiki.Render.Mermaid.toMermaidCompose3Nested'
-- (one-level nested); both are pinned below.
module Jitsurei.Render.MermaidLoanSpec (spec) where

import Data.Text (Text)
import qualified Data.Text as T
import Test.Hspec

import Jitsurei.CoreBankingSync (coreBankingSync)
import Jitsurei.Loan (loan)
import Jitsurei.LoanApplication (loanApplication)
import Jitsurei.LoanWorkflow (loanWorkflow)
import Keiki.Render.Mermaid
  ( toMermaid
  , toMermaidCompose3
  , toMermaidCompose3Nested
  )


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

  describe "toMermaidCompose3 loanWorkflow" $
    it "renders the 54-vertex flat block" $
      toMermaidCompose3 loanWorkflow `shouldBe` loanWorkflowFlatCanonical

  describe "toMermaidCompose3Nested loanWorkflow" $
    it "renders the 6-outer × 9-inner nested block" $
      toMermaidCompose3Nested loanWorkflow
        `shouldBe` loanWorkflowNestedCanonical


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


-- | Canonical render for @toMermaidCompose3 loanWorkflow@. Mirrored
-- verbatim by @docs/guide/diagrams/loan-workflow.mmd@. The flat
-- shape lists every reachable composite edge directly under the
-- @stateDiagram-v2@ header; vertices that are neither sources of an
-- edge nor final are omitted (same convention as the single-
-- aggregate renders above).
loanWorkflowFlatCanonical :: Text
loanWorkflowFlatCanonical = unlinesNoTrail
  [ "stateDiagram-v2"
  , "    [*] --> Intake_SyncIdle_LoanInitial"
  , "    Intake_SyncIdle_LoanInitial --> CollectingDocuments_SyncRequested_LoanAwaiting : StartApplication / LoanCreated"
  , "    Intake_SyncIdle_LoanInitial --> Withdrawn_SyncRequested_LoanAwaiting : WithdrawApplication / LoanCreated"
  , "    Intake_SyncIdle_LoanAwaiting --> CollectingDocuments_SyncRequested_LoanLinked : StartApplication / LegacyLoanIdAssigned"
  , "    Intake_SyncIdle_LoanAwaiting --> Withdrawn_SyncRequested_LoanLinked : WithdrawApplication / LegacyLoanIdAssigned"
  , "    Intake_SyncRequested_LoanInitial --> CollectingDocuments_SyncSettled_LoanAwaiting : StartApplication / LoanCreated"
  , "    Intake_SyncRequested_LoanInitial --> Withdrawn_SyncSettled_LoanAwaiting : WithdrawApplication / LoanCreated"
  , "    Intake_SyncRequested_LoanAwaiting --> CollectingDocuments_SyncSettled_LoanLinked : StartApplication / LegacyLoanIdAssigned"
  , "    Intake_SyncRequested_LoanAwaiting --> Withdrawn_SyncSettled_LoanLinked : WithdrawApplication / LegacyLoanIdAssigned"
  , "    CollectingDocuments_SyncIdle_LoanInitial --> CollectingDocuments_SyncRequested_LoanAwaiting : SubmitIncomeDocument / LoanCreated"
  , "    CollectingDocuments_SyncIdle_LoanInitial --> CollectingDocuments_SyncRequested_LoanAwaiting : SubmitIdDocument / LoanCreated"
  , "    CollectingDocuments_SyncIdle_LoanInitial --> CollectingDocuments_SyncRequested_LoanAwaiting : RecordCreditScore / LoanCreated"
  , "    CollectingDocuments_SyncIdle_LoanInitial --> CollectingDocuments_SyncRequested_LoanAwaiting : RecordEmploymentCheck / LoanCreated"
  , "    CollectingDocuments_SyncIdle_LoanInitial --> Withdrawn_SyncRequested_LoanAwaiting : WithdrawApplication / LoanCreated"
  , "    CollectingDocuments_SyncIdle_LoanInitial --> UnderReview_SyncIdle_LoanInitial : Continue / \x03B5"
  , "    CollectingDocuments_SyncIdle_LoanAwaiting --> CollectingDocuments_SyncRequested_LoanLinked : SubmitIncomeDocument / LegacyLoanIdAssigned"
  , "    CollectingDocuments_SyncIdle_LoanAwaiting --> CollectingDocuments_SyncRequested_LoanLinked : SubmitIdDocument / LegacyLoanIdAssigned"
  , "    CollectingDocuments_SyncIdle_LoanAwaiting --> CollectingDocuments_SyncRequested_LoanLinked : RecordCreditScore / LegacyLoanIdAssigned"
  , "    CollectingDocuments_SyncIdle_LoanAwaiting --> CollectingDocuments_SyncRequested_LoanLinked : RecordEmploymentCheck / LegacyLoanIdAssigned"
  , "    CollectingDocuments_SyncIdle_LoanAwaiting --> Withdrawn_SyncRequested_LoanLinked : WithdrawApplication / LegacyLoanIdAssigned"
  , "    CollectingDocuments_SyncIdle_LoanAwaiting --> UnderReview_SyncIdle_LoanAwaiting : Continue / \x03B5"
  , "    CollectingDocuments_SyncIdle_LoanLinked --> UnderReview_SyncIdle_LoanLinked : Continue / \x03B5"
  , "    CollectingDocuments_SyncRequested_LoanInitial --> CollectingDocuments_SyncSettled_LoanAwaiting : SubmitIncomeDocument / LoanCreated"
  , "    CollectingDocuments_SyncRequested_LoanInitial --> CollectingDocuments_SyncSettled_LoanAwaiting : SubmitIdDocument / LoanCreated"
  , "    CollectingDocuments_SyncRequested_LoanInitial --> CollectingDocuments_SyncSettled_LoanAwaiting : RecordCreditScore / LoanCreated"
  , "    CollectingDocuments_SyncRequested_LoanInitial --> CollectingDocuments_SyncSettled_LoanAwaiting : RecordEmploymentCheck / LoanCreated"
  , "    CollectingDocuments_SyncRequested_LoanInitial --> Withdrawn_SyncSettled_LoanAwaiting : WithdrawApplication / LoanCreated"
  , "    CollectingDocuments_SyncRequested_LoanInitial --> UnderReview_SyncRequested_LoanInitial : Continue / \x03B5"
  , "    CollectingDocuments_SyncRequested_LoanAwaiting --> CollectingDocuments_SyncSettled_LoanLinked : SubmitIncomeDocument / LegacyLoanIdAssigned"
  , "    CollectingDocuments_SyncRequested_LoanAwaiting --> CollectingDocuments_SyncSettled_LoanLinked : SubmitIdDocument / LegacyLoanIdAssigned"
  , "    CollectingDocuments_SyncRequested_LoanAwaiting --> CollectingDocuments_SyncSettled_LoanLinked : RecordCreditScore / LegacyLoanIdAssigned"
  , "    CollectingDocuments_SyncRequested_LoanAwaiting --> CollectingDocuments_SyncSettled_LoanLinked : RecordEmploymentCheck / LegacyLoanIdAssigned"
  , "    CollectingDocuments_SyncRequested_LoanAwaiting --> Withdrawn_SyncSettled_LoanLinked : WithdrawApplication / LegacyLoanIdAssigned"
  , "    CollectingDocuments_SyncRequested_LoanAwaiting --> UnderReview_SyncRequested_LoanAwaiting : Continue / \x03B5"
  , "    CollectingDocuments_SyncRequested_LoanLinked --> UnderReview_SyncRequested_LoanLinked : Continue / \x03B5"
  , "    CollectingDocuments_SyncSettled_LoanInitial --> UnderReview_SyncSettled_LoanInitial : Continue / \x03B5"
  , "    CollectingDocuments_SyncSettled_LoanAwaiting --> UnderReview_SyncSettled_LoanAwaiting : Continue / \x03B5"
  , "    CollectingDocuments_SyncSettled_LoanLinked --> UnderReview_SyncSettled_LoanLinked : Continue / \x03B5"
  , "    UnderReview_SyncIdle_LoanInitial --> Approved_SyncRequested_LoanAwaiting : Continue / LoanCreated"
  , "    UnderReview_SyncIdle_LoanInitial --> Declined_SyncRequested_LoanAwaiting : Continue / LoanCreated"
  , "    UnderReview_SyncIdle_LoanInitial --> Withdrawn_SyncRequested_LoanAwaiting : WithdrawApplication / LoanCreated"
  , "    UnderReview_SyncIdle_LoanAwaiting --> Approved_SyncRequested_LoanLinked : Continue / LegacyLoanIdAssigned"
  , "    UnderReview_SyncIdle_LoanAwaiting --> Declined_SyncRequested_LoanLinked : Continue / LegacyLoanIdAssigned"
  , "    UnderReview_SyncIdle_LoanAwaiting --> Withdrawn_SyncRequested_LoanLinked : WithdrawApplication / LegacyLoanIdAssigned"
  , "    UnderReview_SyncRequested_LoanInitial --> Approved_SyncSettled_LoanAwaiting : Continue / LoanCreated"
  , "    UnderReview_SyncRequested_LoanInitial --> Declined_SyncSettled_LoanAwaiting : Continue / LoanCreated"
  , "    UnderReview_SyncRequested_LoanInitial --> Withdrawn_SyncSettled_LoanAwaiting : WithdrawApplication / LoanCreated"
  , "    UnderReview_SyncRequested_LoanAwaiting --> Approved_SyncSettled_LoanLinked : Continue / LegacyLoanIdAssigned"
  , "    UnderReview_SyncRequested_LoanAwaiting --> Declined_SyncSettled_LoanLinked : Continue / LegacyLoanIdAssigned"
  , "    UnderReview_SyncRequested_LoanAwaiting --> Withdrawn_SyncSettled_LoanLinked : WithdrawApplication / LegacyLoanIdAssigned"
  , "    Approved_SyncSettled_LoanLinked --> [*]"
  , "    Declined_SyncSettled_LoanLinked --> [*]"
  , "    Withdrawn_SyncSettled_LoanLinked --> [*]"
  ]


-- | Canonical render for @toMermaidCompose3Nested loanWorkflow@.
-- Mirrored verbatim by @docs/guide/diagrams/loan-workflow-nested.mmd@.
-- Same edge / final lines as the flat variant; differs by wrapping
-- the cross-product in six @state \<outer\> { … }@ blocks (one per
-- 'Jitsurei.LoanApplication.LoanAppVertex'), each listing the nine
-- @Composite SyncVertex LoanVertex@ inner identifiers under that
-- outer aggregate.
loanWorkflowNestedCanonical :: Text
loanWorkflowNestedCanonical = unlinesNoTrail
  [ "stateDiagram-v2"
  , "    [*] --> Intake_SyncIdle_LoanInitial"
  , "    state Intake {"
  , "        Intake_SyncIdle_LoanInitial"
  , "        Intake_SyncIdle_LoanAwaiting"
  , "        Intake_SyncIdle_LoanLinked"
  , "        Intake_SyncRequested_LoanInitial"
  , "        Intake_SyncRequested_LoanAwaiting"
  , "        Intake_SyncRequested_LoanLinked"
  , "        Intake_SyncSettled_LoanInitial"
  , "        Intake_SyncSettled_LoanAwaiting"
  , "        Intake_SyncSettled_LoanLinked"
  , "    }"
  , "    state CollectingDocuments {"
  , "        CollectingDocuments_SyncIdle_LoanInitial"
  , "        CollectingDocuments_SyncIdle_LoanAwaiting"
  , "        CollectingDocuments_SyncIdle_LoanLinked"
  , "        CollectingDocuments_SyncRequested_LoanInitial"
  , "        CollectingDocuments_SyncRequested_LoanAwaiting"
  , "        CollectingDocuments_SyncRequested_LoanLinked"
  , "        CollectingDocuments_SyncSettled_LoanInitial"
  , "        CollectingDocuments_SyncSettled_LoanAwaiting"
  , "        CollectingDocuments_SyncSettled_LoanLinked"
  , "    }"
  , "    state UnderReview {"
  , "        UnderReview_SyncIdle_LoanInitial"
  , "        UnderReview_SyncIdle_LoanAwaiting"
  , "        UnderReview_SyncIdle_LoanLinked"
  , "        UnderReview_SyncRequested_LoanInitial"
  , "        UnderReview_SyncRequested_LoanAwaiting"
  , "        UnderReview_SyncRequested_LoanLinked"
  , "        UnderReview_SyncSettled_LoanInitial"
  , "        UnderReview_SyncSettled_LoanAwaiting"
  , "        UnderReview_SyncSettled_LoanLinked"
  , "    }"
  , "    state Approved {"
  , "        Approved_SyncIdle_LoanInitial"
  , "        Approved_SyncIdle_LoanAwaiting"
  , "        Approved_SyncIdle_LoanLinked"
  , "        Approved_SyncRequested_LoanInitial"
  , "        Approved_SyncRequested_LoanAwaiting"
  , "        Approved_SyncRequested_LoanLinked"
  , "        Approved_SyncSettled_LoanInitial"
  , "        Approved_SyncSettled_LoanAwaiting"
  , "        Approved_SyncSettled_LoanLinked"
  , "    }"
  , "    state Declined {"
  , "        Declined_SyncIdle_LoanInitial"
  , "        Declined_SyncIdle_LoanAwaiting"
  , "        Declined_SyncIdle_LoanLinked"
  , "        Declined_SyncRequested_LoanInitial"
  , "        Declined_SyncRequested_LoanAwaiting"
  , "        Declined_SyncRequested_LoanLinked"
  , "        Declined_SyncSettled_LoanInitial"
  , "        Declined_SyncSettled_LoanAwaiting"
  , "        Declined_SyncSettled_LoanLinked"
  , "    }"
  , "    state Withdrawn {"
  , "        Withdrawn_SyncIdle_LoanInitial"
  , "        Withdrawn_SyncIdle_LoanAwaiting"
  , "        Withdrawn_SyncIdle_LoanLinked"
  , "        Withdrawn_SyncRequested_LoanInitial"
  , "        Withdrawn_SyncRequested_LoanAwaiting"
  , "        Withdrawn_SyncRequested_LoanLinked"
  , "        Withdrawn_SyncSettled_LoanInitial"
  , "        Withdrawn_SyncSettled_LoanAwaiting"
  , "        Withdrawn_SyncSettled_LoanLinked"
  , "    }"
  , "    Intake_SyncIdle_LoanInitial --> CollectingDocuments_SyncRequested_LoanAwaiting : StartApplication / LoanCreated"
  , "    Intake_SyncIdle_LoanInitial --> Withdrawn_SyncRequested_LoanAwaiting : WithdrawApplication / LoanCreated"
  , "    Intake_SyncIdle_LoanAwaiting --> CollectingDocuments_SyncRequested_LoanLinked : StartApplication / LegacyLoanIdAssigned"
  , "    Intake_SyncIdle_LoanAwaiting --> Withdrawn_SyncRequested_LoanLinked : WithdrawApplication / LegacyLoanIdAssigned"
  , "    Intake_SyncRequested_LoanInitial --> CollectingDocuments_SyncSettled_LoanAwaiting : StartApplication / LoanCreated"
  , "    Intake_SyncRequested_LoanInitial --> Withdrawn_SyncSettled_LoanAwaiting : WithdrawApplication / LoanCreated"
  , "    Intake_SyncRequested_LoanAwaiting --> CollectingDocuments_SyncSettled_LoanLinked : StartApplication / LegacyLoanIdAssigned"
  , "    Intake_SyncRequested_LoanAwaiting --> Withdrawn_SyncSettled_LoanLinked : WithdrawApplication / LegacyLoanIdAssigned"
  , "    CollectingDocuments_SyncIdle_LoanInitial --> CollectingDocuments_SyncRequested_LoanAwaiting : SubmitIncomeDocument / LoanCreated"
  , "    CollectingDocuments_SyncIdle_LoanInitial --> CollectingDocuments_SyncRequested_LoanAwaiting : SubmitIdDocument / LoanCreated"
  , "    CollectingDocuments_SyncIdle_LoanInitial --> CollectingDocuments_SyncRequested_LoanAwaiting : RecordCreditScore / LoanCreated"
  , "    CollectingDocuments_SyncIdle_LoanInitial --> CollectingDocuments_SyncRequested_LoanAwaiting : RecordEmploymentCheck / LoanCreated"
  , "    CollectingDocuments_SyncIdle_LoanInitial --> Withdrawn_SyncRequested_LoanAwaiting : WithdrawApplication / LoanCreated"
  , "    CollectingDocuments_SyncIdle_LoanInitial --> UnderReview_SyncIdle_LoanInitial : Continue / \x03B5"
  , "    CollectingDocuments_SyncIdle_LoanAwaiting --> CollectingDocuments_SyncRequested_LoanLinked : SubmitIncomeDocument / LegacyLoanIdAssigned"
  , "    CollectingDocuments_SyncIdle_LoanAwaiting --> CollectingDocuments_SyncRequested_LoanLinked : SubmitIdDocument / LegacyLoanIdAssigned"
  , "    CollectingDocuments_SyncIdle_LoanAwaiting --> CollectingDocuments_SyncRequested_LoanLinked : RecordCreditScore / LegacyLoanIdAssigned"
  , "    CollectingDocuments_SyncIdle_LoanAwaiting --> CollectingDocuments_SyncRequested_LoanLinked : RecordEmploymentCheck / LegacyLoanIdAssigned"
  , "    CollectingDocuments_SyncIdle_LoanAwaiting --> Withdrawn_SyncRequested_LoanLinked : WithdrawApplication / LegacyLoanIdAssigned"
  , "    CollectingDocuments_SyncIdle_LoanAwaiting --> UnderReview_SyncIdle_LoanAwaiting : Continue / \x03B5"
  , "    CollectingDocuments_SyncIdle_LoanLinked --> UnderReview_SyncIdle_LoanLinked : Continue / \x03B5"
  , "    CollectingDocuments_SyncRequested_LoanInitial --> CollectingDocuments_SyncSettled_LoanAwaiting : SubmitIncomeDocument / LoanCreated"
  , "    CollectingDocuments_SyncRequested_LoanInitial --> CollectingDocuments_SyncSettled_LoanAwaiting : SubmitIdDocument / LoanCreated"
  , "    CollectingDocuments_SyncRequested_LoanInitial --> CollectingDocuments_SyncSettled_LoanAwaiting : RecordCreditScore / LoanCreated"
  , "    CollectingDocuments_SyncRequested_LoanInitial --> CollectingDocuments_SyncSettled_LoanAwaiting : RecordEmploymentCheck / LoanCreated"
  , "    CollectingDocuments_SyncRequested_LoanInitial --> Withdrawn_SyncSettled_LoanAwaiting : WithdrawApplication / LoanCreated"
  , "    CollectingDocuments_SyncRequested_LoanInitial --> UnderReview_SyncRequested_LoanInitial : Continue / \x03B5"
  , "    CollectingDocuments_SyncRequested_LoanAwaiting --> CollectingDocuments_SyncSettled_LoanLinked : SubmitIncomeDocument / LegacyLoanIdAssigned"
  , "    CollectingDocuments_SyncRequested_LoanAwaiting --> CollectingDocuments_SyncSettled_LoanLinked : SubmitIdDocument / LegacyLoanIdAssigned"
  , "    CollectingDocuments_SyncRequested_LoanAwaiting --> CollectingDocuments_SyncSettled_LoanLinked : RecordCreditScore / LegacyLoanIdAssigned"
  , "    CollectingDocuments_SyncRequested_LoanAwaiting --> CollectingDocuments_SyncSettled_LoanLinked : RecordEmploymentCheck / LegacyLoanIdAssigned"
  , "    CollectingDocuments_SyncRequested_LoanAwaiting --> Withdrawn_SyncSettled_LoanLinked : WithdrawApplication / LegacyLoanIdAssigned"
  , "    CollectingDocuments_SyncRequested_LoanAwaiting --> UnderReview_SyncRequested_LoanAwaiting : Continue / \x03B5"
  , "    CollectingDocuments_SyncRequested_LoanLinked --> UnderReview_SyncRequested_LoanLinked : Continue / \x03B5"
  , "    CollectingDocuments_SyncSettled_LoanInitial --> UnderReview_SyncSettled_LoanInitial : Continue / \x03B5"
  , "    CollectingDocuments_SyncSettled_LoanAwaiting --> UnderReview_SyncSettled_LoanAwaiting : Continue / \x03B5"
  , "    CollectingDocuments_SyncSettled_LoanLinked --> UnderReview_SyncSettled_LoanLinked : Continue / \x03B5"
  , "    UnderReview_SyncIdle_LoanInitial --> Approved_SyncRequested_LoanAwaiting : Continue / LoanCreated"
  , "    UnderReview_SyncIdle_LoanInitial --> Declined_SyncRequested_LoanAwaiting : Continue / LoanCreated"
  , "    UnderReview_SyncIdle_LoanInitial --> Withdrawn_SyncRequested_LoanAwaiting : WithdrawApplication / LoanCreated"
  , "    UnderReview_SyncIdle_LoanAwaiting --> Approved_SyncRequested_LoanLinked : Continue / LegacyLoanIdAssigned"
  , "    UnderReview_SyncIdle_LoanAwaiting --> Declined_SyncRequested_LoanLinked : Continue / LegacyLoanIdAssigned"
  , "    UnderReview_SyncIdle_LoanAwaiting --> Withdrawn_SyncRequested_LoanLinked : WithdrawApplication / LegacyLoanIdAssigned"
  , "    UnderReview_SyncRequested_LoanInitial --> Approved_SyncSettled_LoanAwaiting : Continue / LoanCreated"
  , "    UnderReview_SyncRequested_LoanInitial --> Declined_SyncSettled_LoanAwaiting : Continue / LoanCreated"
  , "    UnderReview_SyncRequested_LoanInitial --> Withdrawn_SyncSettled_LoanAwaiting : WithdrawApplication / LoanCreated"
  , "    UnderReview_SyncRequested_LoanAwaiting --> Approved_SyncSettled_LoanLinked : Continue / LegacyLoanIdAssigned"
  , "    UnderReview_SyncRequested_LoanAwaiting --> Declined_SyncSettled_LoanLinked : Continue / LegacyLoanIdAssigned"
  , "    UnderReview_SyncRequested_LoanAwaiting --> Withdrawn_SyncSettled_LoanLinked : WithdrawApplication / LegacyLoanIdAssigned"
  , "    Approved_SyncSettled_LoanLinked --> [*]"
  , "    Declined_SyncSettled_LoanLinked --> [*]"
  , "    Withdrawn_SyncSettled_LoanLinked --> [*]"
  ]


unlinesNoTrail :: [Text] -> Text
unlinesNoTrail = T.intercalate (T.pack "\n")
