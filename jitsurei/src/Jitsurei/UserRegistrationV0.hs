{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE PolyKinds #-}

-- | The User Registration aggregate with the *unfixed* synthesis-§4
-- schema: 'AccountConfirmedDataV0' omits the @confirmCode@ field, so
-- the right-code 'guard' on the Confirm edge reads an input field
-- ('d.confirmCode') that the produced event does not carry. This is
-- the canonical hidden-input bug from synthesis §4 step 4.
--
-- The module exists so that EP-4's M7 can demonstrate two things on
-- the same schema:
--
--   1. **Replay fails.** 'reconstitute' over a V0 event log returns
--      'Nothing', because the user-supplied inverse on the Confirm
--      edge cannot fabricate a correct @d.confirmCode@ from the
--      observed event — and any guess will be rejected by the edge's
--      equality guard against @regs ! #confirmCode@.
--   2. **The hidden-input check produces warnings.** Post-EP-1 the
--      check walks each 'OPack''s 'OutFields' against the 'InCtor'
--      named on it; if any slot of the 'InCtor' is unvisited the
--      check reports the missing field by name. The Confirm edge
--      surfaces as @InCtor "ConfirmAccount" leaves field
--      \{"confirmCode"\} unrecovered@.
--
-- Most of the surface mirrors 'Jitsurei.UserRegistration' (V5,
-- the fixed schema). Only the 'AccountConfirmed' wire and the right-
-- code Confirm edge differ.
module Jitsurei.UserRegistrationV0
  ( -- * V0 event with the missing field
    AccountConfirmedDataV0 (..),
    UserEventV0 (..),

    -- * V0 transducer
    userRegV0,

    -- * The V0 "canonical" event log used by the M7 demonstration
    canonicalLogV0,
  )
where

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import GHC.Generics (Generic)
import Jitsurei.UserRegistration
  ( AccountDeletedData (..),
    ConfirmationCode,
    ConfirmationEmailSentData (..),
    ConfirmationResentData (..),
    Email,
    RegistrationStartedData (..),
    UserCmd (..),
    UserRegRegs,
    Vertex (..),
    inCtorConfirm,
    inCtorGdpr,
    inCtorResend,
    inCtorStart,
    inpConfirm,
    inpGdpr,
    inpResend,
    inpStart,
  )
import Keiki.Core
import Keiki.Generics (FieldsOf, emptyRegFile, mkWireCtorVia)

-- * V0 event with the missing field ----------------------------------------

-- | Synthesis §4 step-4 unfixed schema: no @confirmCode@.
data AccountConfirmedDataV0 = AccountConfirmedDataV0
  { email :: Email,
    at :: UTCTime
  }
  deriving (Eq, Show, Generic)

data UserEventV0
  = RegistrationStartedV0 RegistrationStartedData
  | ConfirmationEmailSentV0 ConfirmationEmailSentData
  | AccountConfirmedV0 AccountConfirmedDataV0
  | ConfirmationResentV0 ConfirmationResentData
  | AccountDeletedV0 AccountDeletedData
  deriving (Eq, Show, Generic)

-- * Transducer scaffolding ------------------------------------------------

emptyRegsV0 :: RegFile UserRegRegs
emptyRegsV0 = emptyRegFile

-- | Per-constructor guards. Migrated from v1 'matchCmd' to v2
-- 'matchInCtor' alongside the V5 aggregate so the SBV-backed
-- 'BoolAlg' instance recognizes constructor mutex on the V0 form
-- too. The 'evalPred' semantics is preserved.
isStart, isConfirm, isResend, isGdpr :: Pred UserRegRegs UserCmd
isStart = matchInCtor inCtorStart
isConfirm = matchInCtor inCtorConfirm
isResend = matchInCtor inCtorResend
isGdpr = matchInCtor inCtorGdpr

-- * V0 wire constructors ---------------------------------------------------

--
-- All five 'WireCtor' values are 'mkWireCtorVia'-built; both the
-- sum-side match\/wrap and the nested-pair field tuple come from
-- 'UserEventV0' and each event record's 'Generic' instances.

wireRegistrationStartedV0 :: WireCtor UserEventV0 (FieldsOf RegistrationStartedData)
wireRegistrationStartedV0 = mkWireCtorVia @"RegistrationStartedV0"

wireConfirmationEmailSentV0 :: WireCtor UserEventV0 (FieldsOf ConfirmationEmailSentData)
wireConfirmationEmailSentV0 = mkWireCtorVia @"ConfirmationEmailSentV0"

-- | The hidden-input culprit: 'AccountConfirmedDataV0' does not carry
-- @confirmCode@. The forward direction emits @(email, at)@; the
-- inverse cannot recover @ci.confirmCode@.
wireAccountConfirmedV0 :: WireCtor UserEventV0 (FieldsOf AccountConfirmedDataV0)
wireAccountConfirmedV0 = mkWireCtorVia @"AccountConfirmedV0"

wireConfirmationResentV0 :: WireCtor UserEventV0 (FieldsOf ConfirmationResentData)
wireConfirmationResentV0 = mkWireCtorVia @"ConfirmationResentV0"

wireAccountDeletedV0 :: WireCtor UserEventV0 (FieldsOf AccountDeletedData)
wireAccountDeletedV0 = mkWireCtorVia @"AccountDeletedV0"

-- * The V0 transducer ------------------------------------------------------

userRegV0 ::
  Guarded UserRegRegs Vertex UserCmd UserEventV0
userRegV0 =
  SymTransducer
    { edgesOut = userRegV0Edges,
      initial = PotentialCustomer,
      initialRegs = emptyRegsV0,
      isFinal = \case Deleted -> True; _ -> False
    }

userRegV0Edges ::
  Vertex ->
  [Edge (Pred UserRegRegs UserCmd) UserRegRegs UserCmd UserEventV0 Vertex]
userRegV0Edges = \case
  -- EP-19 M7: collapsed entrance into one length-2 multi-event edge,
  -- matching V5. V0's hidden-input bug is on the Confirm edge below,
  -- not the entrance chain, so the collapse preserves the demo.
  PotentialCustomer ->
    [ Edge
        { guard = isStart,
          update =
            USet (#email :: IndexN "email" UserRegRegs Email) (inpStart #email)
              `combine` USet
                (#confirmCode :: IndexN "confirmCode" UserRegRegs ConfirmationCode)
                (inpStart #confirmCode)
              `combine` USet
                (#registeredAt :: IndexN "registeredAt" UserRegRegs UTCTime)
                (inpStart #at),
          output =
            [ pack
                inCtorStart
                wireRegistrationStartedV0
                ( OFCons
                    (inpStart #email)
                    ( OFCons
                        (inpStart #confirmCode)
                        (OFCons (inpStart #at) OFNil)
                    )
                ),
              pack
                inCtorStart
                wireConfirmationEmailSentV0
                (OFCons (inpStart #email) OFNil)
            ],
          target = RequiresConfirmation
        }
    ]
  RequiresConfirmation ->
    [ -- Right-code Confirm edge — UNFIXED. The OutFields walks only
      -- (#email, #at): the wireAccountConfirmedV0 wire's tuple shape
      -- still drops confirmCode. The structural inverse therefore
      -- cannot find a value for inCtorConfirm's "confirmCode" slot
      -- and solveOutput returns Nothing — replay halts. The hidden-
      -- input check (post-EP-1) names this missing field precisely.
      Edge
        { guard =
            isConfirm
              .&& ( inpConfirm #confirmCode
                      .== proj (#confirmCode :: Index UserRegRegs ConfirmationCode)
                  ),
          update =
            USet
              (#confirmedAt :: IndexN "confirmedAt" UserRegRegs UTCTime)
              (inpConfirm #at),
          output =
            [ pack
                inCtorConfirm
                wireAccountConfirmedV0
                ( OFCons
                    (proj (#email :: Index UserRegRegs Email))
                    (OFCons (inpConfirm #at) OFNil)
                )
            ],
          target = Confirmed
        },
      Edge
        { guard = isResend,
          update =
            USet
              (#confirmCode :: IndexN "confirmCode" UserRegRegs ConfirmationCode)
              (inpResend #code)
              `combine` USet
                (#registeredAt :: IndexN "registeredAt" UserRegRegs UTCTime)
                (inpResend #at),
          output =
            [ pack
                inCtorResend
                wireConfirmationResentV0
                ( OFCons
                    (proj (#email :: Index UserRegRegs Email))
                    ( OFCons
                        (inpResend #code)
                        (OFCons (inpResend #at) OFNil)
                    )
                )
            ],
          target = RequiresConfirmation
        },
      Edge
        { guard = isGdpr,
          update =
            USet
              (#deletedAt :: IndexN "deletedAt" UserRegRegs UTCTime)
              (inpGdpr #at),
          output = [],
          target = Deleted
        }
    ]
  Confirmed ->
    [ Edge
        { guard = isGdpr,
          update =
            USet
              (#deletedAt :: IndexN "deletedAt" UserRegRegs UTCTime)
              (inpGdpr #at),
          output =
            [ pack
                inCtorGdpr
                wireAccountDeletedV0
                ( OFCons
                    (proj (#email :: Index UserRegRegs Email))
                    (OFCons (inpGdpr #at) OFNil)
                )
            ],
          target = Deleted
        }
    ]
  Deleted -> []

-- * The V0 canonical event log --------------------------------------------

canonicalLogV0 :: [UserEventV0]
canonicalLogV0 =
  [ RegistrationStartedV0 (RegistrationStartedData "alice@x" "Z9F4" (mkT 0)),
    ConfirmationEmailSentV0 (ConfirmationEmailSentData "alice@x"),
    ConfirmationResentV0 (ConfirmationResentData "alice@x" "K2P7" (mkT 100)),
    AccountConfirmedV0 (AccountConfirmedDataV0 "alice@x" (mkT 200)),
    AccountDeletedV0 (AccountDeletedData "alice@x" (mkT 300))
  ]
  where
    mkT s = UTCTime (fromGregorian 2026 5 1) (secondsToDiffTime s)
