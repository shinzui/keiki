{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE QualifiedDo #-}
{-# LANGUAGE TemplateHaskell #-}
-- Constructor derivation emits predicate helpers in addition to the exported
-- constructors and field projections used by this example.
{-# OPTIONS_GHC -Wno-unused-top-binds #-}

-- | The CoreBankingSync Process aggregate (EP-34 M4). A *Process* in
-- the keiki sense is a transducer whose input alphabet is *events*
-- from one bounded context and whose output alphabet is *commands*
-- to another. Mirrors the production
-- 'MlsService.LegacyQaCreator.Process' shape:
--
--   * On a 'LoanCreatedIn' inbound event (the upstream Loan
--     aggregate just created itself), set pending state and emit
--     'SyncToLegacyRequested' as an audit signal. The runtime
--     adapter consumes the audit event and calls the legacy core-
--     banking system with the pending fields.
--   * On a 'LegacyCallbackReceivedIn' inbound event (the legacy
--     system replied with a legacy loan id), confirm the
--     identifier matches the pending loanId, emit
--     'LegacyAssignmentCommanded' carrying the
--     'AssignLegacyLoanId' command, and transition to 'SyncSettled'.
--
-- Replays are idempotent /by construction/: a duplicate
-- 'LegacyCallbackReceivedIn' for the same loanId finds the Process
-- already in 'SyncSettled' (terminal, no outgoing edges) and
-- 'delta' returns 'Nothing'. A callback whose loanId mismatches
-- the pending loanId fails the 'requireEq' guard and 'delta' also
-- returns 'Nothing'.
--
-- Constructors are suffixed @In@ on the input alphabet and named
-- ordinarily on the output alphabet so the M5 composition can
-- distinguish them.
module Jitsurei.CoreBankingSync
  ( -- * Input alphabet (events from upstream)
    LoanCreatedInData (..),
    LegacyCallbackReceivedInData (..),
    SyncInput (..),

    -- * Output alphabet (audit + command-out)
    SyncToLegacyRequestedData (..),
    LegacyAssignmentCommandedData (..),
    SyncOutput (..),

    -- * Register file and control vertices
    SyncRegs,
    SyncVertex (..),

    -- * The transducer
    coreBankingSync,
    emptySyncRegs,

    -- * Wire constructors (exported for testing / composition)
    wireSyncToLegacyRequested,
    wireLegacyAssignmentCommanded,

    -- * Input constructors (exported for testing / composition)
    inCtorLoanCreatedIn,
    inCtorLegacyCallbackReceivedIn,
    inpLoanCreatedIn,
    inpLegacyCallbackReceivedIn,
  )
where

import Data.Text (Text)
import GHC.Generics (Generic)
import Jitsurei.Loan
  ( AssignLegacyLoanIdData (..),
    LoanCmd' (AssignLegacyLoanId),
  )
import Keiki.Builder ((.=))
import Keiki.Builder qualified as B
import Keiki.Core
import Keiki.Generics (emptyRegFile)
import Keiki.Generics.TH (deriveAggregateCtors, deriveWireCtors)
import Keiki.Symbolic (KnownInCtors (..), SomeInCtor (..))

-- * Input alphabet ---------------------------------------------------------

-- | Inbound from the upstream Loan stream: a Loan aggregate just
-- emitted its 'LoanCreated' event. Carries the natural-key
-- @loanId@ that the legacy core-banking system deduplicates on,
-- plus the applicantId and principal needed to populate the
-- legacy request.
data LoanCreatedInData = LoanCreatedInData
  { loanId :: Text,
    applicantId :: Text,
    principal :: Int
  }
  deriving (Eq, Show, Generic)

-- | Inbound from the legacy callback channel: the legacy system
-- has issued a legacy loan id for the named loanId.
data LegacyCallbackReceivedInData = LegacyCallbackReceivedInData
  { loanId :: Text,
    legacyLoanId :: Text
  }
  deriving (Eq, Show, Generic)

data SyncInput
  = LoanCreatedIn LoanCreatedInData
  | LegacyCallbackReceivedIn LegacyCallbackReceivedInData
  deriving (Eq, Show, Generic)

-- * Output alphabet --------------------------------------------------------

-- | Audit event surfaced when the Process moves into pending state.
-- The runtime adapter consumes this event to invoke the legacy
-- core-banking system; the pure layer never performs the actual
-- legacy call.
data SyncToLegacyRequestedData = SyncToLegacyRequestedData
  { loanId :: Text,
    applicantId :: Text,
    principal :: Int
  }
  deriving (Eq, Show, Generic)

-- | Single-field wrapper for the embedded 'LoanCmd''. The wrapper
-- is required by 'Keiki.Generics.TH.deriveWireCtors', which
-- generates a @TermFields@ type per event constructor payload and
-- wants one record-syntax data constructor with named fields. The
-- field carries the 'AssignLegacyLoanId' command the Process emits
-- on the legacy-callback edge.
newtype LegacyAssignmentCommandedData = LegacyAssignmentCommandedData
  { assignment :: LoanCmd'
  }
  deriving (Eq, Show, Generic)

-- | The Process's output is either the audit event
-- ('SyncToLegacyRequested') or the command directed at the
-- downstream Loan aggregate (a 'LegacyAssignmentCommanded' wrapper
-- around the embedded 'LoanCmd''). The wrapping keeps the output
-- type composable with 'Jitsurei.Loan's input alphabet via the
-- M5 'lmapMaybeCi' adapter.
data SyncOutput
  = SyncToLegacyRequested SyncToLegacyRequestedData
  | LegacyAssignmentCommanded LegacyAssignmentCommandedData
  deriving (Eq, Show, Generic)

-- * Register file and control vertices -------------------------------------

type SyncRegs =
  '[ '("syncPendingLoanId", Text),
     '("syncPendingApplicantId", Text),
     '("syncPendingPrincipal", Int)
   ]

data SyncVertex
  = SyncIdle
  | SyncRequested
  | SyncSettled
  deriving (Eq, Ord, Show, Enum, Bounded)

emptySyncRegs :: RegFile SyncRegs
emptySyncRegs = emptyRegFile

-- * Per-constructor input projections + guards (TH-derived) --------------

$( deriveAggregateCtors
     ''SyncInput
     ''SyncRegs
     [ ("LoanCreatedIn", "LoanCreatedIn"),
       ("LegacyCallbackReceivedIn", "LegacyCallbackReceivedIn")
     ]
 )

instance KnownInCtors SyncInput where
  allInCtors =
    [ SomeInCtor inCtorLoanCreatedIn,
      SomeInCtor inCtorLegacyCallbackReceivedIn
    ]

-- * Wire constructors for events (TH-derived) ----------------------------

$( deriveWireCtors
     ''SyncOutput
     [ ("SyncToLegacyRequested", "SyncToLegacyRequested"),
       ("LegacyAssignmentCommanded", "LegacyAssignmentCommanded")
     ]
 )

-- * The transducer ---------------------------------------------------------

coreBankingSync :: Guarded SyncRegs SyncVertex SyncInput SyncOutput
coreBankingSync = B.buildTransducer
  SyncIdle
  emptySyncRegs
  (\case SyncSettled -> True; _ -> False)
  do
    B.from SyncIdle do
      B.onCmd inCtorLoanCreatedIn $ \d -> B.do
        B.slot @"syncPendingLoanId" .= d.loanId
        B.slot @"syncPendingApplicantId" .= d.applicantId
        B.slot @"syncPendingPrincipal" .= d.principal
        B.emit
          wireSyncToLegacyRequested
          SyncToLegacyRequestedTermFields
            { loanId = d.loanId,
              applicantId = d.applicantId,
              principal = d.principal
            }
        B.goto SyncRequested

    B.from SyncRequested do
      B.onCmd inCtorLegacyCallbackReceivedIn $ \d -> B.do
        -- Idempotency anchor: the loanId on the callback must match
        -- the pending loanId. A duplicate callback for some other
        -- loan fails this guard; the duplicate-for-same-loan case
        -- is handled by 'SyncSettled' being terminal (no outgoing
        -- edges from it after the first callback resolves).
        B.requireEq d.loanId #syncPendingLoanId
        B.emit
          wireLegacyAssignmentCommanded
          LegacyAssignmentCommandedTermFields
            { assignment = TApp2 buildAssign d.loanId d.legacyLoanId
            }
        B.goto SyncSettled
  where
    -- SyncSettled is terminal; default to [].

    -- Build the embedded 'AssignLegacyLoanId' command from the
    -- callback's two fields. Lifted to 'TApp2' so the term-level
    -- output expression can read the input fields structurally.
    buildAssign :: Text -> Text -> LoanCmd'
    buildAssign lid llid =
      AssignLegacyLoanId
        (AssignLegacyLoanIdData {loanId = lid, legacyLoanId = llid})
