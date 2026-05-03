{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE PolyKinds #-}

-- | Sequential composition of the three EP-34 aggregates:
--
--   LoanApplication ⨾ CoreBankingSync ⨾ Loan
--
-- exposed as a single 'Keiki.Core.SymTransducer'. The composition
-- mirrors the production
-- @AgentQualification → QualifiedAgent → LegacyQaCreator Process@
-- shape from
-- @\/Users\/shinzui\/Keikaku\/work\/microtan\/mls-service-v2-master\/@.
--
-- == Variance caveat (important)
--
-- 'Keiki.Composition.compose' is lockstep: every non-ε composite
-- edge fires *both* legs simultaneously. Cross-context creation
-- flows are async — the runtime observes LoanApplication's
-- 'ApplicationApproved' event, *then* (in a separate transactional
-- step) issues a LoanCreated/CreateLoan command on the
-- CoreBankingSync stream, *then later* the legacy callback channel
-- delivers a 'LegacyCallbackReceivedIn' event. There is no
-- single LoanCmd input that fires the entire chain in one
-- composite step; the composite is therefore largely a *type-
-- level wiring diagram* whose firing semantics are restricted to
-- the (Compose t1 t2 t3) edges where all three legs happen to
-- align — which, given the adapter functions' 'Maybe' results, is
-- essentially never. The 'Jitsurei.LoanWorkflowSpec' exercises
-- the cross-context jumps by driving each aggregate directly
-- through the adapter functions exposed below; that test is the
-- one that mirrors the runtime's actual behaviour.
--
-- See the EP-34 plan's Surprises & Discoveries entry of 2026-05-03
-- for the full discussion.
module Jitsurei.LoanWorkflow
  ( -- * The composed transducer (type-level wiring)
    loanWorkflow
    -- * Adapter functions (the runtime adapter calls these)
  , loanEventToSyncInput
  , syncOutputToLoanCmd
  ) where

import Keiki.Composition (Composite, compose)
import Keiki.Core (HsPred, SymTransducer)
import Keiki.Generics (Append)
import Keiki.Profunctor (lmapMaybeCi)

import Jitsurei.CoreBankingSync
  ( SyncInput (..)
  , SyncOutput (..)
  , SyncRegs
  , SyncVertex
  , LoanCreatedInData (..)
  , LegacyAssignmentCommandedData (..)
  , coreBankingSync
  )
import Jitsurei.Loan
  ( LoanCmd' (..)
  , LoanEvent'
  , LoanRegs
  , LoanVertex
  , loan
  )
import Jitsurei.LoanApplication
  ( ApplicationApprovedData (..)
  , LoanAppRegs
  , LoanAppVertex
  , LoanCmd
  , LoanEvent (..)
  , loanApplication
  )


-- | Adapter from the upstream LoanApplication's event alphabet to
-- the CoreBankingSync Process's input alphabet. Only
-- 'ApplicationApproved' maps to a meaningful CoreBankingSync
-- input ('LoanCreatedIn' — the loan has been approved, the
-- Process should kick off the legacy sync). All other LoanEvents
-- are unrelated to the legacy-sync workflow and translate to
-- 'Nothing', so the rewritten CoreBankingSync transducer's
-- guards filter them out.
--
-- The synthetic loanId is derived from the applicantId — in a
-- production system the runtime would mint a UUID; the pure layer
-- doesn't need a fresh-randomness source.
loanEventToSyncInput :: LoanEvent -> Maybe SyncInput
loanEventToSyncInput (ApplicationApproved a) =
  Just (LoanCreatedIn (LoanCreatedInData
    { loanId      = "loan-" <> a.applicantId
    , applicantId = a.applicantId
    , principal   = a.requestedAmount
    }))
loanEventToSyncInput _ = Nothing


-- | Adapter from the CoreBankingSync Process's output alphabet to
-- the Loan aggregate's command alphabet. Only the
-- 'LegacyAssignmentCommanded' wrapper carries a Loan command;
-- 'SyncToLegacyRequested' is an audit signal that the runtime
-- adapter consumes (to invoke the legacy core-banking system) and
-- doesn't drive the Loan aggregate directly.
syncOutputToLoanCmd :: SyncOutput -> Maybe LoanCmd'
syncOutputToLoanCmd (LegacyAssignmentCommanded d) = Just d.assignment
syncOutputToLoanCmd (SyncToLegacyRequested  _)    = Nothing


-- | The three-aggregate composition. Type-level only — see the
-- module's variance caveat.
loanWorkflow
  :: SymTransducer
       (HsPred (Append LoanAppRegs (Append SyncRegs LoanRegs)) LoanCmd)
       (Append LoanAppRegs (Append SyncRegs LoanRegs))
       (Composite LoanAppVertex (Composite SyncVertex LoanVertex))
       LoanCmd
       LoanEvent'
loanWorkflow =
  loanApplication
    `compose`
  lmapMaybeCi loanEventToSyncInput
    (coreBankingSync `compose` lmapMaybeCi syncOutputToLoanCmd loan)
