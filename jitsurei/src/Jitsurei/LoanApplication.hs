{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE QualifiedDo #-}
{-# LANGUAGE TemplateHaskell #-}

-- | The Loan Application aggregate from EP-34. Mirrors the production
-- @AgentQualification@ pattern at
-- @\/Users\/shinzui\/Keikaku\/work\/microtan\/mls-service-v2-master\/@:
-- a long-lived intake aggregate that accumulates evidence
-- (documents, credit checks, employment verifications) and emits
-- @ApplicationApproved@ when the multi-field threshold is met.
--
-- Pedagogically the aggregate exercises the keiki features that none
-- of the prior worked examples cover:
--
--   * Multi-field threshold guards (credit score \(\ge\) 650 \(\wedge\)
--     employment verified \(\wedge\) requested amount \(\le\) credit-
--     score-derived cap), expressed via 'TApp1' / 'TApp2' inside an
--     'HsPred' conjunction.
--   * ε-edges (silent transitions): \"sufficient documents tipped the
--     application from CollectingDocuments to UnderReview\" emits no
--     public event.
--   * Per-vertex 'View' variance: 'Intake' exposes only
--     @applicantId@; 'Approved' exposes
--     @applicantId, requestedAmount, creditScore, decidedAt@.
--
-- Plan reference:
--
--   * @docs/plans/34-loan-application-worked-example-with-cross-context-process-and-tutorial.md@
--     — M2 design, including the prefixed slot-name convention so
--     'Loan' and 'CoreBankingSync' can be 'compose'd later (M5).
module Jitsurei.LoanApplication
  ( -- * Domain types
    Money
  , BasisPoints
    -- * Command payloads
  , StartApplicationData (..)
  , SubmitIncomeDocumentData (..)
  , SubmitIdDocumentData (..)
  , RecordCreditScoreData (..)
  , RecordEmploymentCheckData (..)
  , WithdrawApplicationData (..)
  , LoanCmd (..)
    -- * Event payloads
  , ApplicationStartedData (..)
  , IncomeDocumentReceivedData (..)
  , IdDocumentReceivedData (..)
  , CreditScoreRecordedData (..)
  , EmploymentCheckedData (..)
  , ReadyForReviewData (..)
  , ApplicationApprovedData (..)
  , ApplicationDeclinedData (..)
  , ApplicationWithdrawnData (..)
  , LoanEvent (..)
    -- * Register file and control vertices
  , LoanAppRegs
  , LoanAppVertex (..)
    -- * The transducer
  , loanApplication
  , loanApplicationAST
  , loanApplicationChained
  , emptyLoanAppRegs
    -- * Multi-event driver configuration (EP-34 M3)
  , loanApplicationDriverConfig
    -- * Wire constructors (exported for testing / composition)
  , wireApplicationStarted
  , wireIncomeDocumentReceived
  , wireIdDocumentReceived
  , wireCreditScoreRecorded
  , wireEmploymentChecked
  , wireReadyForReview
  , wireApplicationApproved
  , wireApplicationDeclined
  , wireApplicationWithdrawn
    -- * Input constructors (exported for testing / composition)
  , inCtorStart
  , inCtorSubmitIncome
  , inCtorSubmitId
  , inCtorRecordScore
  , inCtorRecordEmployment
  , inCtorWithdraw
  , inCtorContinue
  , inpStart
  , inpSubmitIncome
  , inpSubmitId
  , inpRecordScore
  , inpRecordEmployment
  , inpWithdraw
    -- * Threshold helpers (exposed for the tutorial / specs)
  , approvalThresholdScore
  , minimumIncomeDocs
  , minimumIdDocs
  , maxApprovalForScore
    -- * B-presentation views (TH-derived; see EP-13 / MP-5)
  , SLoanAppVertex (..)
  , LoanAppView (..)
  , loanAppView
  ) where

import Data.Text (Text)
import Data.Time (UTCTime)
import GHC.Generics (Generic)
import Keiki.Core
import qualified Keiki.Builder as B
import Keiki.Builder ((.=))
import Keiki.Decider (DriverConfig (..))
import Keiki.Generics (emptyRegFile)
import Keiki.Generics.TH (deriveAggregateCtors, deriveView, deriveWireCtors)
import Keiki.Symbolic (KnownInCtors (..), SomeInCtor (..))


-- * Domain types ------------------------------------------------------------

-- | Whole-currency-unit amounts. Kept as 'Int' rather than a newtype
-- so the 'Sym' curated registry recognises the slot type and the
-- symbolic analyses (@isSingleValuedSym@, @symSat@) work without a
-- bespoke 'Sym' instance.
type Money = Int

-- | Basis points (1\/100th of a percent). Same rationale as 'Money'.
type BasisPoints = Int


-- | The credit-score threshold above which a loan application is
-- eligible for approval. Exposed publicly so the tutorial and the
-- specs can refer to the same constant without re-importing the
-- module's internals.
approvalThresholdScore :: Int
approvalThresholdScore = 650

-- | The minimum number of income documents required before
-- 'CollectingDocuments' tips into 'UnderReview' on the ε-edge.
minimumIncomeDocs :: Int
minimumIncomeDocs = 2

-- | The minimum number of identity documents required before
-- 'CollectingDocuments' tips into 'UnderReview'.
minimumIdDocs :: Int
minimumIdDocs = 1

-- | Per-credit-score loan-amount cap. The function is intentionally a
-- linear approximation (@score * 1000@) — the goal is to demonstrate
-- a multi-field threshold guard, not to implement bank policy. A
-- score of 700 caps the loan at 700_000 currency units.
maxApprovalForScore :: Int -> Int
maxApprovalForScore score = score * 1000


-- * Command payloads --------------------------------------------------------

data StartApplicationData = StartApplicationData
  { applicantId     :: Text
  , requestedAmount :: Money
  , purpose         :: Text
  , at              :: UTCTime
  } deriving (Eq, Show, Generic)

data SubmitIncomeDocumentData = SubmitIncomeDocumentData
  { docRef :: Text
  , at     :: UTCTime
  } deriving (Eq, Show, Generic)

data SubmitIdDocumentData = SubmitIdDocumentData
  { docRef :: Text
  , at     :: UTCTime
  } deriving (Eq, Show, Generic)

data RecordCreditScoreData = RecordCreditScoreData
  { score :: Int
  , at    :: UTCTime
  } deriving (Eq, Show, Generic)

data RecordEmploymentCheckData = RecordEmploymentCheckData
  { verified :: Bool
  , at       :: UTCTime
  } deriving (Eq, Show, Generic)

data WithdrawApplicationData = WithdrawApplicationData
  { reason :: Text
  , at     :: UTCTime
  } deriving (Eq, Show, Generic)

-- | The aggregate's command alphabet. 'Continue' is the internal
-- advancer used by 'Keiki.Builder.chainTo' (M3) and the
-- 'MultiDecider' façade to drive the @UnderReview@ approval/decline
-- decision in the same step as the originating command.
data LoanCmd
  = StartApplication      StartApplicationData
  | SubmitIncomeDocument  SubmitIncomeDocumentData
  | SubmitIdDocument      SubmitIdDocumentData
  | RecordCreditScore     RecordCreditScoreData
  | RecordEmploymentCheck RecordEmploymentCheckData
  | WithdrawApplication   WithdrawApplicationData
  | Continue
  deriving (Eq, Show, Generic)


-- * Event payloads ----------------------------------------------------------

data ApplicationStartedData = ApplicationStartedData
  { applicantId     :: Text
  , requestedAmount :: Money
  , purpose         :: Text
  , at              :: UTCTime
  } deriving (Eq, Show, Generic)

data IncomeDocumentReceivedData = IncomeDocumentReceivedData
  { docRef :: Text
  , at     :: UTCTime
  } deriving (Eq, Show, Generic)

data IdDocumentReceivedData = IdDocumentReceivedData
  { docRef :: Text
  , at     :: UTCTime
  } deriving (Eq, Show, Generic)

data CreditScoreRecordedData = CreditScoreRecordedData
  { score :: Int
  , at    :: UTCTime
  } deriving (Eq, Show, Generic)

data EmploymentCheckedData = EmploymentCheckedData
  { verified :: Bool
  , at       :: UTCTime
  } deriving (Eq, Show, Generic)

newtype ReadyForReviewData = ReadyForReviewData { at :: UTCTime }
  deriving (Eq, Show, Generic)

data ApplicationApprovedData = ApplicationApprovedData
  { applicantId     :: Text
  , requestedAmount :: Money
  , creditScore     :: Int
  , at              :: UTCTime
  } deriving (Eq, Show, Generic)

data ApplicationDeclinedData = ApplicationDeclinedData
  { applicantId :: Text
  , reason      :: Text
  , at          :: UTCTime
  } deriving (Eq, Show, Generic)

data ApplicationWithdrawnData = ApplicationWithdrawnData
  { applicantId :: Text
  , reason      :: Text
  , at          :: UTCTime
  } deriving (Eq, Show, Generic)

data LoanEvent
  = ApplicationStarted     ApplicationStartedData
  | IncomeDocumentReceived IncomeDocumentReceivedData
  | IdDocumentReceived     IdDocumentReceivedData
  | CreditScoreRecorded    CreditScoreRecordedData
  | EmploymentChecked      EmploymentCheckedData
  | ReadyForReview         ReadyForReviewData
  | ApplicationApproved    ApplicationApprovedData
  | ApplicationDeclined    ApplicationDeclinedData
  | ApplicationWithdrawn   ApplicationWithdrawnData
  deriving (Eq, Show, Generic)


-- * Register file and control vertices -------------------------------------

-- | Slot names use the @app@ prefix so the M5 'compose' with
-- 'Loan' (@loan@ prefix) and 'CoreBankingSync' (@sync@ prefix)
-- satisfies @Disjoint (Names rs1) (Names rs2)@ at the type level.
type LoanAppRegs =
  '[ '("appApplicantId",        Text)
   , '("appRequestedAmount",    Money)
   , '("appPurpose",            Text)
   , '("appIncomeDocCount",     Int)
   , '("appIdDocCount",         Int)
   , '("appCreditScore",        Int)
   , '("appEmploymentVerified", Bool)
   , '("appDecidedAt",          UTCTime)
   , '("appWithdrawnAt",        UTCTime)
   , '("appDeclineReason",      Text)
   ]


data LoanAppVertex
  = Intake
  | CollectingDocuments
  | UnderReview
  | Approved
  | Declined
  | Withdrawn
  deriving (Eq, Show, Enum, Bounded)


-- | Initial register file. Every slot is pre-bound to a deferred
-- @"uninit: <slot>"@ error by 'Keiki.Generics.emptyRegFile'. The
-- @Intake@ vertex's only outgoing edges (StartApplication,
-- WithdrawApplication) write the slots they need before any guard
-- evaluation reads them, so the deferred-error binding is never
-- forced on the happy path.
emptyLoanAppRegs :: RegFile LoanAppRegs
emptyLoanAppRegs = emptyRegFile


-- * Per-constructor input projections + guards (TH-derived) --------------

$(deriveAggregateCtors ''LoanCmd ''LoanAppRegs
    [ ("StartApplication",      "Start")
    , ("SubmitIncomeDocument",  "SubmitIncome")
    , ("SubmitIdDocument",      "SubmitId")
    , ("RecordCreditScore",     "RecordScore")
    , ("RecordEmploymentCheck", "RecordEmployment")
    , ("WithdrawApplication",   "Withdraw")
    , ("Continue",              "Continue")
    ])


-- | Enumerate the seven 'InCtor' values of 'LoanCmd' so the symbolic
-- witness extractor can rebuild a concrete 'LoanCmd' from an SBV
-- model.
instance KnownInCtors LoanCmd where
  allInCtors =
    [ SomeInCtor inCtorStart
    , SomeInCtor inCtorSubmitIncome
    , SomeInCtor inCtorSubmitId
    , SomeInCtor inCtorRecordScore
    , SomeInCtor inCtorRecordEmployment
    , SomeInCtor inCtorWithdraw
    , SomeInCtor inCtorContinue
    ]


-- * Wire constructors for events (TH-derived) ----------------------------

$(deriveWireCtors ''LoanEvent
    [ ("ApplicationStarted",     "ApplicationStarted")
    , ("IncomeDocumentReceived", "IncomeDocumentReceived")
    , ("IdDocumentReceived",     "IdDocumentReceived")
    , ("CreditScoreRecorded",    "CreditScoreRecorded")
    , ("EmploymentChecked",      "EmploymentChecked")
    , ("ReadyForReview",         "ReadyForReview")
    , ("ApplicationApproved",    "ApplicationApproved")
    , ("ApplicationDeclined",    "ApplicationDeclined")
    , ("ApplicationWithdrawn",   "ApplicationWithdrawn")
    ])


-- * B-presentation views (TH-derived) ------------------------------------
--
-- Per-vertex View variance: 'Intake' only knows the applicant's
-- identity; 'CollectingDocuments' adds the request details and doc
-- counters; 'UnderReview' switches focus from documents to the
-- decision inputs (credit score, employment); 'Approved' /
-- 'Declined' / 'Withdrawn' present terminal-summary slots.

$(deriveView ''LoanAppVertex ''LoanAppRegs
    "SLoanAppVertex" "LoanAppView" "loanAppView"
    [ ("Intake",            ["appApplicantId"])
    , ("CollectingDocuments",
         [ "appApplicantId", "appRequestedAmount", "appPurpose"
         , "appIncomeDocCount", "appIdDocCount" ])
    , ("UnderReview",
         [ "appApplicantId", "appRequestedAmount", "appPurpose"
         , "appCreditScore", "appEmploymentVerified" ])
    , ("Approved",
         [ "appApplicantId", "appRequestedAmount"
         , "appCreditScore", "appDecidedAt" ])
    , ("Declined",
         [ "appApplicantId", "appDeclineReason", "appDecidedAt" ])
    , ("Withdrawn",
         [ "appApplicantId", "appWithdrawnAt" ])
    ])


-- * Internal helpers ------------------------------------------------------
--
-- 'StartApplication' initialises the four counter / decision slots
-- so subsequent ε-edge and Continue-driven guards can read them
-- without forcing the deferred error left by 'emptyRegFile'. Sentinel
-- values: counts start at 0; 'appCreditScore' starts at 0 (a value
-- that cannot occur as a real score because the threshold check
-- requires @>= 1@); 'appEmploymentVerified' starts at 'False' and
-- means \"not verified or not yet checked\" symmetrically.
--
-- ε-edge guard \"ready for review\":
--
--   appIncomeDocCount  >= minimumIncomeDocs
--     /\\  appIdDocCount      >= minimumIdDocs
--     /\\  appCreditScore     >= 1                 (any positive score)
--     /\\  appEmploymentVerified == True
--
-- Continue-driven approval guard:
--
--   appCreditScore     >= approvalThresholdScore
--     /\\  appEmploymentVerified == True
--     /\\  appRequestedAmount    <= maxApprovalForScore appCreditScore

readyForReviewGuard :: HsPred LoanAppRegs LoanCmd
readyForReviewGuard =
  PEq (TApp1 (>= minimumIncomeDocs) (proj (#appIncomeDocCount :: Index LoanAppRegs Int)))
      (lit True)
    `PAnd`
  PEq (TApp1 (>= minimumIdDocs) (proj (#appIdDocCount :: Index LoanAppRegs Int)))
      (lit True)
    `PAnd`
  PEq (TApp1 (>= 1) (proj (#appCreditScore :: Index LoanAppRegs Int)))
      (lit True)
    `PAnd`
  PEq (proj (#appEmploymentVerified :: Index LoanAppRegs Bool)) (lit True)


approvalGuard :: HsPred LoanAppRegs LoanCmd
approvalGuard =
  PEq (TApp1 (>= approvalThresholdScore)
        (proj (#appCreditScore :: Index LoanAppRegs Int)))
      (lit True)
    `PAnd`
  PEq (proj (#appEmploymentVerified :: Index LoanAppRegs Bool)) (lit True)
    `PAnd`
  PEq (TApp2 (<=)
        (proj (#appRequestedAmount :: Index LoanAppRegs Money))
        (TApp1 maxApprovalForScore
          (proj (#appCreditScore :: Index LoanAppRegs Int))))
      (lit True)


-- * The transducer (builder form) -----------------------------------------

loanApplication :: SymTransducer (HsPred LoanAppRegs LoanCmd)
                                 LoanAppRegs
                                 LoanAppVertex
                                 LoanCmd
                                 LoanEvent
loanApplication = B.buildTransducer Intake emptyLoanAppRegs
                    isFinalLoanApp do

  B.from Intake do
    B.onCmd inCtorStart $ \d -> B.do
      B.slot @"appApplicantId"        .= d.applicantId
      B.slot @"appRequestedAmount"    .= d.requestedAmount
      B.slot @"appPurpose"             .= d.purpose
      B.slot @"appIncomeDocCount"      .= lit 0
      B.slot @"appIdDocCount"          .= lit 0
      B.slot @"appCreditScore"         .= lit 0
      B.slot @"appEmploymentVerified"  .= lit False
      B.emit wireApplicationStarted ApplicationStartedTermFields
        { applicantId     = d.applicantId
        , requestedAmount = d.requestedAmount
        , purpose         = d.purpose
        , at              = d.at
        }
      B.goto CollectingDocuments

    B.onCmd inCtorWithdraw $ \d -> B.do
      B.slot @"appApplicantId" .= lit ""  -- unused on this branch but
                                          -- keeps RegFile total
      B.slot @"appWithdrawnAt" .= d.at
      B.emit wireApplicationWithdrawn ApplicationWithdrawnTermFields
        { applicantId = #appApplicantId
        , reason      = d.reason
        , at          = d.at
        }
      B.goto Withdrawn

  B.from CollectingDocuments do
    B.onCmd inCtorSubmitIncome $ \d -> B.do
      B.slot @"appIncomeDocCount" .= TApp1 (+ 1) #appIncomeDocCount
      B.emit wireIncomeDocumentReceived IncomeDocumentReceivedTermFields
        { docRef = d.docRef
        , at     = d.at
        }
      B.goto CollectingDocuments

    B.onCmd inCtorSubmitId $ \d -> B.do
      B.slot @"appIdDocCount" .= TApp1 (+ 1) #appIdDocCount
      B.emit wireIdDocumentReceived IdDocumentReceivedTermFields
        { docRef = d.docRef
        , at     = d.at
        }
      B.goto CollectingDocuments

    B.onCmd inCtorRecordScore $ \d -> B.do
      B.slot @"appCreditScore" .= d.score
      B.emit wireCreditScoreRecorded CreditScoreRecordedTermFields
        { score = d.score
        , at    = d.at
        }
      B.goto CollectingDocuments

    B.onCmd inCtorRecordEmployment $ \d -> B.do
      B.slot @"appEmploymentVerified" .= d.verified
      B.emit wireEmploymentChecked EmploymentCheckedTermFields
        { verified = d.verified
        , at       = d.at
        }
      B.goto CollectingDocuments

    B.onCmd inCtorWithdraw $ \d -> B.do
      B.slot @"appWithdrawnAt" .= d.at
      B.emit wireApplicationWithdrawn ApplicationWithdrawnTermFields
        { applicantId = #appApplicantId
        , reason      = d.reason
        , at          = d.at
        }
      B.goto Withdrawn

    -- "ε-edge" — no public event ('noEmit') — triggered by the
    -- driver's 'Continue' command when all four thresholds (income
    -- docs >= 2, id docs >= 1, credit score recorded, employment
    -- verified) hold. Modelled as 'onCmd inCtorContinue' rather
    -- than 'onEpsilon' so the symbolic-mutex check ('isSingleValuedSym')
    -- can reason about it as a regular Continue-keyed edge: the
    -- inCtor witness disambiguates this edge from the five
    -- evidence-collection edges out of the same vertex. Echoes the
    -- pattern in 'Jitsurei.UserRegistration's GDPR-from-
    -- 'RequiresConfirmation' edge ('onCmd inCtorGdpr' with
    -- 'noEmit'). See the plan's Decision Log entry for the
    -- onEpsilon -> onCmd inCtorContinue rationale.
    B.onCmd inCtorContinue $ \_d -> B.do
      B.requireGuard readyForReviewGuard
      B.noEmit
      B.goto UnderReview

  B.from UnderReview do
    -- Approval branch.
    B.onCmd inCtorContinue $ \d -> B.do
      B.requireGuard approvalGuard
      B.slot @"appDecidedAt" .= continueAt d
      B.emit wireApplicationApproved ApplicationApprovedTermFields
        { applicantId     = #appApplicantId
        , requestedAmount = #appRequestedAmount
        , creditScore     = #appCreditScore
        , at              = continueAt d
        }
      B.goto Approved

    -- Decline branch — the negation of 'approvalGuard'.
    B.onCmd inCtorContinue $ \d -> B.do
      B.requireGuard (PNot approvalGuard)
      B.slot @"appDecidedAt"     .= continueAt d
      B.slot @"appDeclineReason" .= lit "Below threshold"
      B.emit wireApplicationDeclined ApplicationDeclinedTermFields
        { applicantId = #appApplicantId
        , reason      = #appDeclineReason
        , at          = continueAt d
        }
      B.goto Declined

    B.onCmd inCtorWithdraw $ \d -> B.do
      B.slot @"appWithdrawnAt" .= d.at
      B.emit wireApplicationWithdrawn ApplicationWithdrawnTermFields
        { applicantId = #appApplicantId
        , reason      = d.reason
        , at          = d.at
        }
      B.goto Withdrawn

  -- Approved / Declined / Withdrawn are terminal; no @from@ blocks.

  where
    -- 'Continue' has no payload, so its 'inpContinue' projection is
    -- unavailable. The wall-clock / business-clock timestamp is
    -- pulled from a fixed sentinel; in production a richer payload
    -- would carry it. The literal is exposed only inside the
    -- builder so the test harness can override it via a richer
    -- 'Continue' alternative if needed.
    continueAt _ = lit (read "1970-01-01 00:00:00 UTC" :: UTCTime)


-- | Final / terminal vertex predicate — shared between the builder
-- and AST forms.
isFinalLoanApp :: LoanAppVertex -> Bool
isFinalLoanApp = \case
  Approved  -> True
  Declined  -> True
  Withdrawn -> True
  _         -> False


-- * AST form (legacy, retained for the M2 equivalence test) ---------------

-- | Hand-authored against the post-MP-6 'Keiki.Core' AST. Retained
-- as a side-by-side reference for the
-- 'Jitsurei.LoanApplicationBuilderSpec' equivalence test.
loanApplicationAST :: SymTransducer (HsPred LoanAppRegs LoanCmd)
                                    LoanAppRegs
                                    LoanAppVertex
                                    LoanCmd
                                    LoanEvent
loanApplicationAST = SymTransducer
  { edgesOut    = loanApplicationASTEdges
  , initial     = Intake
  , initialRegs = emptyLoanAppRegs
  , isFinal     = isFinalLoanApp
  }


loanApplicationASTEdges
  :: LoanAppVertex
  -> [Edge (HsPred LoanAppRegs LoanCmd) LoanAppRegs LoanCmd LoanEvent LoanAppVertex]
loanApplicationASTEdges = \case

  Intake ->
    [ Edge
        { guard  = isStart
        , update =
            USet (#appApplicantId :: IndexN "appApplicantId" LoanAppRegs Text)
                 (inpStart #applicantId)
              `combine`
            USet (#appRequestedAmount :: IndexN "appRequestedAmount" LoanAppRegs Money)
                 (inpStart #requestedAmount)
              `combine`
            USet (#appPurpose :: IndexN "appPurpose" LoanAppRegs Text)
                 (inpStart #purpose)
              `combine`
            USet (#appIncomeDocCount :: IndexN "appIncomeDocCount" LoanAppRegs Int)
                 (lit 0)
              `combine`
            USet (#appIdDocCount :: IndexN "appIdDocCount" LoanAppRegs Int)
                 (lit 0)
              `combine`
            USet (#appCreditScore :: IndexN "appCreditScore" LoanAppRegs Int)
                 (lit 0)
              `combine`
            USet (#appEmploymentVerified
                    :: IndexN "appEmploymentVerified" LoanAppRegs Bool)
                 (lit False)
        , output = Just $ pack
            inCtorStart
            wireApplicationStarted
            (OFCons (inpStart #applicantId)
              (OFCons (inpStart #requestedAmount)
                (OFCons (inpStart #purpose)
                  (OFCons (inpStart #at) OFNil))))
        , target = CollectingDocuments
        }
    , Edge
        { guard  = isWithdraw
        , update =
            USet (#appApplicantId :: IndexN "appApplicantId" LoanAppRegs Text)
                 (lit "")
              `combine`
            USet (#appWithdrawnAt :: IndexN "appWithdrawnAt" LoanAppRegs UTCTime)
                 (inpWithdraw #at)
        , output = Just $ pack
            inCtorWithdraw
            wireApplicationWithdrawn
            (OFCons (proj (#appApplicantId :: Index LoanAppRegs Text))
              (OFCons (inpWithdraw #reason)
                (OFCons (inpWithdraw #at) OFNil)))
        , target = Withdrawn
        }
    ]

  CollectingDocuments ->
    [ Edge
        { guard  = isSubmitIncome
        , update = USet (#appIncomeDocCount
                          :: IndexN "appIncomeDocCount" LoanAppRegs Int)
                        (TApp1 (+ 1)
                           (proj (#appIncomeDocCount :: Index LoanAppRegs Int)))
        , output = Just $ pack
            inCtorSubmitIncome
            wireIncomeDocumentReceived
            (OFCons (inpSubmitIncome #docRef)
              (OFCons (inpSubmitIncome #at) OFNil))
        , target = CollectingDocuments
        }
    , Edge
        { guard  = isSubmitId
        , update = USet (#appIdDocCount :: IndexN "appIdDocCount" LoanAppRegs Int)
                        (TApp1 (+ 1)
                           (proj (#appIdDocCount :: Index LoanAppRegs Int)))
        , output = Just $ pack
            inCtorSubmitId
            wireIdDocumentReceived
            (OFCons (inpSubmitId #docRef)
              (OFCons (inpSubmitId #at) OFNil))
        , target = CollectingDocuments
        }
    , Edge
        { guard  = isRecordScore
        , update = USet (#appCreditScore :: IndexN "appCreditScore" LoanAppRegs Int)
                        (inpRecordScore #score)
        , output = Just $ pack
            inCtorRecordScore
            wireCreditScoreRecorded
            (OFCons (inpRecordScore #score)
              (OFCons (inpRecordScore #at) OFNil))
        , target = CollectingDocuments
        }
    , Edge
        { guard  = isRecordEmployment
        , update = USet (#appEmploymentVerified
                          :: IndexN "appEmploymentVerified" LoanAppRegs Bool)
                        (inpRecordEmployment #verified)
        , output = Just $ pack
            inCtorRecordEmployment
            wireEmploymentChecked
            (OFCons (inpRecordEmployment #verified)
              (OFCons (inpRecordEmployment #at) OFNil))
        , target = CollectingDocuments
        }
    , Edge
        { guard  = isWithdraw
        , update = USet (#appWithdrawnAt :: IndexN "appWithdrawnAt" LoanAppRegs UTCTime)
                        (inpWithdraw #at)
        , output = Just $ pack
            inCtorWithdraw
            wireApplicationWithdrawn
            (OFCons (proj (#appApplicantId :: Index LoanAppRegs Text))
              (OFCons (inpWithdraw #reason)
                (OFCons (inpWithdraw #at) OFNil)))
        , target = Withdrawn
        }
      -- "ε-edge" — no public event — fired by Continue when the
      -- threshold guards hold. See builder-form comment.
    , Edge
        { guard  = PAnd isContinue readyForReviewGuard
        , update = UKeep
        , output = Nothing
        , target = UnderReview
        }
    ]

  UnderReview ->
    [ Edge
        { guard  = PAnd isContinue approvalGuard
        , update = USet (#appDecidedAt :: IndexN "appDecidedAt" LoanAppRegs UTCTime)
                        (lit (read "1970-01-01 00:00:00 UTC" :: UTCTime))
        , output = Just $ pack
            inCtorContinue
            wireApplicationApproved
            (OFCons (proj (#appApplicantId :: Index LoanAppRegs Text))
              (OFCons (proj (#appRequestedAmount :: Index LoanAppRegs Money))
                (OFCons (proj (#appCreditScore :: Index LoanAppRegs Int))
                  (OFCons (lit (read "1970-01-01 00:00:00 UTC" :: UTCTime))
                    OFNil))))
        , target = Approved
        }
    , Edge
        { guard  = PAnd isContinue (PNot approvalGuard)
        , update = USet (#appDecidedAt :: IndexN "appDecidedAt" LoanAppRegs UTCTime)
                        (lit (read "1970-01-01 00:00:00 UTC" :: UTCTime))
              `combine`
            USet (#appDeclineReason :: IndexN "appDeclineReason" LoanAppRegs Text)
                 (lit "Below threshold")
        , output = Just $ pack
            inCtorContinue
            wireApplicationDeclined
            (OFCons (proj (#appApplicantId :: Index LoanAppRegs Text))
              (OFCons (proj (#appDeclineReason :: Index LoanAppRegs Text))
                (OFCons (lit (read "1970-01-01 00:00:00 UTC" :: UTCTime))
                  OFNil)))
        , target = Declined
        }
    , Edge
        { guard  = isWithdraw
        , update = USet (#appWithdrawnAt :: IndexN "appWithdrawnAt" LoanAppRegs UTCTime)
                        (inpWithdraw #at)
        , output = Just $ pack
            inCtorWithdraw
            wireApplicationWithdrawn
            (OFCons (proj (#appApplicantId :: Index LoanAppRegs Text))
              (OFCons (inpWithdraw #reason)
                (OFCons (inpWithdraw #at) OFNil)))
        , target = Withdrawn
        }
    ]

  Approved  -> []
  Declined  -> []
  Withdrawn -> []


-- * Chained-builder form (EP-34 M3) ---------------------------------------

-- | The same transducer authored with 'Keiki.Builder.chainTo'. The
-- silent @CollectingDocuments -> UnderReview@ advance is moved into
-- the @inCtorStart@ body via 'chainTo'; the explicit
-- @from CollectingDocuments do onCmd inCtorContinue@ block is
-- therefore omitted (the chained edge replaces it). Compiles to the
-- same letter-FST 'Edge' values as 'loanApplication'; the
-- 'Jitsurei.LoanApplicationChainedSpec' equivalence test asserts
-- identical 'reconstitute' behavior on the canonical evidence-
-- collection log.
--
-- NB: only the silent advance is chained. The Continue-driven
-- approval / decline edges out of 'UnderReview' are still authored
-- as a separate @from UnderReview@ block — chaining further would
-- pick a single branch, but both branches must remain available
-- because the runtime decision depends on dynamic register state.
loanApplicationChained :: SymTransducer (HsPred LoanAppRegs LoanCmd)
                                        LoanAppRegs
                                        LoanAppVertex
                                        LoanCmd
                                        LoanEvent
loanApplicationChained = B.buildTransducer Intake emptyLoanAppRegs
                           isFinalLoanApp do

  B.from Intake do
    B.onCmd inCtorStart $ \d -> B.do
      B.slot @"appApplicantId"        .= d.applicantId
      B.slot @"appRequestedAmount"    .= d.requestedAmount
      B.slot @"appPurpose"             .= d.purpose
      B.slot @"appIncomeDocCount"      .= lit 0
      B.slot @"appIdDocCount"          .= lit 0
      B.slot @"appCreditScore"         .= lit 0
      B.slot @"appEmploymentVerified"  .= lit False
      B.emit wireApplicationStarted ApplicationStartedTermFields
        { applicantId     = d.applicantId
        , requestedAmount = d.requestedAmount
        , purpose         = d.purpose
        , at              = d.at
        }
      -- Inline the silent advance from CollectingDocuments to
      -- UnderReview as a chained Continue-keyed edge. The
      -- readyForReviewGuard determines whether this chain actually
      -- fires at multi-decider drive time; at StartApplication
      -- time the guards never hold (counters are zero), so the
      -- chain is dormant immediately after start.
      B.chainTo CollectingDocuments inCtorContinue
      B.requireGuard readyForReviewGuard
      B.noEmit
      B.goto UnderReview

    B.onCmd inCtorWithdraw $ \d -> B.do
      B.slot @"appApplicantId" .= lit ""
      B.slot @"appWithdrawnAt" .= d.at
      B.emit wireApplicationWithdrawn ApplicationWithdrawnTermFields
        { applicantId = #appApplicantId
        , reason      = d.reason
        , at          = d.at
        }
      B.goto Withdrawn

  -- No explicit @from CollectingDocuments do onCmd inCtorContinue@
  -- block — the chained edge from 'CollectingDocuments' to
  -- 'UnderReview' was registered by the @chainTo@ above. The five
  -- evidence-collection edges + the per-vertex withdraw remain.
  B.from CollectingDocuments do
    B.onCmd inCtorSubmitIncome $ \d -> B.do
      B.slot @"appIncomeDocCount" .= TApp1 (+ 1) #appIncomeDocCount
      B.emit wireIncomeDocumentReceived IncomeDocumentReceivedTermFields
        { docRef = d.docRef
        , at     = d.at
        }
      B.goto CollectingDocuments

    B.onCmd inCtorSubmitId $ \d -> B.do
      B.slot @"appIdDocCount" .= TApp1 (+ 1) #appIdDocCount
      B.emit wireIdDocumentReceived IdDocumentReceivedTermFields
        { docRef = d.docRef
        , at     = d.at
        }
      B.goto CollectingDocuments

    B.onCmd inCtorRecordScore $ \d -> B.do
      B.slot @"appCreditScore" .= d.score
      B.emit wireCreditScoreRecorded CreditScoreRecordedTermFields
        { score = d.score
        , at    = d.at
        }
      B.goto CollectingDocuments

    B.onCmd inCtorRecordEmployment $ \d -> B.do
      B.slot @"appEmploymentVerified" .= d.verified
      B.emit wireEmploymentChecked EmploymentCheckedTermFields
        { verified = d.verified
        , at       = d.at
        }
      B.goto CollectingDocuments

    B.onCmd inCtorWithdraw $ \d -> B.do
      B.slot @"appWithdrawnAt" .= d.at
      B.emit wireApplicationWithdrawn ApplicationWithdrawnTermFields
        { applicantId = #appApplicantId
        , reason      = d.reason
        , at          = d.at
        }
      B.goto Withdrawn

  B.from UnderReview do
    B.onCmd inCtorContinue $ \_d -> B.do
      B.requireGuard approvalGuard
      B.slot @"appDecidedAt" .= continueAtChained
      B.emit wireApplicationApproved ApplicationApprovedTermFields
        { applicantId     = #appApplicantId
        , requestedAmount = #appRequestedAmount
        , creditScore     = #appCreditScore
        , at              = continueAtChained
        }
      B.goto Approved

    B.onCmd inCtorContinue $ \_d -> B.do
      B.requireGuard (PNot approvalGuard)
      B.slot @"appDecidedAt"     .= continueAtChained
      B.slot @"appDeclineReason" .= lit "Below threshold"
      B.emit wireApplicationDeclined ApplicationDeclinedTermFields
        { applicantId = #appApplicantId
        , reason      = #appDeclineReason
        , at          = continueAtChained
        }
      B.goto Declined

    B.onCmd inCtorWithdraw $ \d -> B.do
      B.slot @"appWithdrawnAt" .= d.at
      B.emit wireApplicationWithdrawn ApplicationWithdrawnTermFields
        { applicantId = #appApplicantId
        , reason      = d.reason
        , at          = d.at
        }
      B.goto Withdrawn

  where
    continueAtChained =
      lit (read "1970-01-01 00:00:00 UTC" :: UTCTime)


-- * Multi-event driver configuration (EP-34 M3) ---------------------------

-- | Driver configuration for 'Keiki.Decider.toMultiDecider'. Both
-- 'CollectingDocuments' and 'UnderReview' are marked internal: at
-- those vertices the multi-decider issues 'Continue' to attempt the
-- silent advance / approval-decline transition. The guard on each
-- chained edge gates whether the advance actually fires; if the
-- guard fails (e.g. thresholds not yet met), 'step' returns
-- 'Nothing' and the driver loop terminates at the current vertex.
--
-- Pair with 'toMultiDecider' to drive a 'StartApplication' or a
-- threshold-tipping evidence command end-to-end:
--
-- @
-- let mdec = 'Keiki.Decider.toMultiDecider' 'loanApplication'
--                                           'loanApplicationDriverConfig'
-- in 'Keiki.Decider.decide' mdec (RecordEmploymentCheck …) regsAtThreshold
-- -- ⇒ [EmploymentChecked …, ApplicationApproved …]
-- @
loanApplicationDriverConfig :: DriverConfig LoanAppVertex LoanCmd
loanApplicationDriverConfig = DriverConfig
  { isInternal = \v -> case v of
      CollectingDocuments -> Just Continue
      UnderReview         -> Just Continue
      _                   -> Nothing
  }
