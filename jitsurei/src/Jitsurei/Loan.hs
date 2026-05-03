{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE QualifiedDo #-}
{-# LANGUAGE TemplateHaskell #-}

-- | The downstream Loan aggregate (EP-34 M4). Mirrors the production
-- @QualifiedAgent@ aggregate at
-- @\/Users\/shinzui\/Keikaku\/work\/microtan\/mls-service-v2-master\/@:
-- created on its own stream after the upstream LoanApplication
-- emits 'ApplicationApproved'; carries an initially-unset
-- @loanLegacyLoanId@ slot that the 'Jitsurei.CoreBankingSync'
-- Process eventually populates via the 'AssignLegacyLoanId' command.
--
-- The aggregate is intentionally tiny — three vertices, two
-- transitions — so the M5 composition with 'LoanApplication' and
-- 'CoreBankingSync' is the focus.
--
-- Constructors are primed (@LoanCmd'@ / @LoanEvent'@) to avoid
-- collisions with 'Jitsurei.LoanApplication.LoanCmd' /
-- 'Jitsurei.LoanApplication.LoanEvent' if a reader imports both
-- modules unqualified at once.
--
-- No AST form, no per-vertex View — both are unjustified by the
-- aggregate's small surface area.
module Jitsurei.Loan
  ( -- * Domain types
    LoanId
  , LegacyLoanId
    -- * Command payloads
  , CreateLoanData (..)
  , AssignLegacyLoanIdData (..)
  , LoanCmd' (..)
    -- * Event payloads
  , LoanCreatedData (..)
  , LegacyLoanIdAssignedData (..)
  , LoanEvent' (..)
    -- * Register file and control vertices
  , LoanRegs
  , LoanVertex (..)
    -- * The transducer
  , loan
  , emptyLoanRegs
    -- * Wire constructors (exported for testing / composition)
  , wireLoanCreated
  , wireLegacyLoanIdAssigned
    -- * Input constructors (exported for testing / composition)
  , inCtorCreateLoan
  , inCtorAssignLegacyLoanId
  , inpCreateLoan
  , inpAssignLegacyLoanId
  ) where

import Data.Text (Text)
import GHC.Generics (Generic)
import Keiki.Core
import qualified Keiki.Builder as B
import Keiki.Builder ((.=))
import Keiki.Generics (emptyRegFile)
import Keiki.Generics.TH (deriveAggregateCtors, deriveWireCtors)
import Keiki.Symbolic (KnownInCtors (..), SomeInCtor (..))


-- * Domain types ------------------------------------------------------------

type LoanId       = Text
type LegacyLoanId = Text


-- * Command payloads --------------------------------------------------------

data CreateLoanData = CreateLoanData
  { loanId      :: LoanId
  , applicantId :: Text
  , principal   :: Int
  } deriving (Eq, Show, Generic)

data AssignLegacyLoanIdData = AssignLegacyLoanIdData
  { loanId       :: LoanId
  , legacyLoanId :: LegacyLoanId
  } deriving (Eq, Show, Generic)

data LoanCmd'
  = CreateLoan          CreateLoanData
  | AssignLegacyLoanId  AssignLegacyLoanIdData
  deriving (Eq, Show, Generic)


-- * Event payloads ----------------------------------------------------------

data LoanCreatedData = LoanCreatedData
  { loanId      :: LoanId
  , applicantId :: Text
  , principal   :: Int
  } deriving (Eq, Show, Generic)

data LegacyLoanIdAssignedData = LegacyLoanIdAssignedData
  { loanId       :: LoanId
  , legacyLoanId :: LegacyLoanId
  } deriving (Eq, Show, Generic)

data LoanEvent'
  = LoanCreated           LoanCreatedData
  | LegacyLoanIdAssigned  LegacyLoanIdAssignedData
  deriving (Eq, Show, Generic)


-- * Register file and control vertices -------------------------------------

-- | Slot names use the @loan@ prefix so the M5 'compose' with
-- 'LoanApplication' (@app@ prefix) and 'CoreBankingSync'
-- (@sync@ prefix) satisfies @Disjoint@ at the type level.
type LoanRegs =
  '[ '("loanLoanId",       LoanId)
   , '("loanApplicantId",  Text)
   , '("loanPrincipal",    Int)
   , '("loanLegacyLoanId", LegacyLoanId)
   ]


data LoanVertex
  = LoanInitial
  | LoanAwaiting
  | LoanLinked
  deriving (Eq, Show, Enum, Bounded)


emptyLoanRegs :: RegFile LoanRegs
emptyLoanRegs = emptyRegFile


-- * Per-constructor input projections + guards (TH-derived) --------------

$(deriveAggregateCtors ''LoanCmd' ''LoanRegs
    [ ("CreateLoan",         "CreateLoan")
    , ("AssignLegacyLoanId", "AssignLegacyLoanId")
    ])


instance KnownInCtors LoanCmd' where
  allInCtors =
    [ SomeInCtor inCtorCreateLoan
    , SomeInCtor inCtorAssignLegacyLoanId
    ]


-- * Wire constructors for events (TH-derived) ----------------------------

$(deriveWireCtors ''LoanEvent'
    [ ("LoanCreated",          "LoanCreated")
    , ("LegacyLoanIdAssigned", "LegacyLoanIdAssigned")
    ])


-- * The transducer ---------------------------------------------------------

loan :: SymTransducer (HsPred LoanRegs LoanCmd')
                      LoanRegs
                      LoanVertex
                      LoanCmd'
                      LoanEvent'
loan = B.buildTransducer LoanInitial emptyLoanRegs
         (\case LoanLinked -> True; _ -> False) do

  B.from LoanInitial do
    B.onCmd inCtorCreateLoan $ \d -> B.do
      B.slot @"loanLoanId"      .= d.loanId
      B.slot @"loanApplicantId" .= d.applicantId
      B.slot @"loanPrincipal"   .= d.principal
      B.emit wireLoanCreated LoanCreatedTermFields
        { loanId      = d.loanId
        , applicantId = d.applicantId
        , principal   = d.principal
        }
      B.goto LoanAwaiting

  B.from LoanAwaiting do
    B.onCmd inCtorAssignLegacyLoanId $ \d -> B.do
      B.requireEq d.loanId #loanLoanId
      B.slot @"loanLegacyLoanId" .= d.legacyLoanId
      B.emit wireLegacyLoanIdAssigned LegacyLoanIdAssignedTermFields
        { loanId       = d.loanId
        , legacyLoanId = d.legacyLoanId
        }
      B.goto LoanLinked

  -- LoanLinked is terminal; default to [].
