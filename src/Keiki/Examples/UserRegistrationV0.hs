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
--   2. **The hidden-input check produces warnings.** v1's check is
--      conservative — it flags every 'OPack' edge whose 'OutFields'
--      contains 'TInpField', plus every 'OFn' edge. With the chosen
--      DSL it cannot field-name-match input reads in @guard@ against
--      input reads in @output@, but the warning list is the v1
--      "candidates to review" surface. v2's structural input
--      projection makes the check field-precise.
--
-- Most of the surface mirrors 'Keiki.Examples.UserRegistration' (V5,
-- the fixed schema). Only the 'AccountConfirmed' wire and the right-
-- code Confirm edge differ.
module Keiki.Examples.UserRegistrationV0
  ( -- * V0 event with the missing field
    AccountConfirmedDataV0 (..)
  , UserEventV0 (..)
    -- * V0 transducer
  , userRegV0
    -- * The V0 "canonical" event log used by the M7 demonstration
  , canonicalLogV0
  ) where

import Data.Proxy (Proxy (..))
import Data.Time (UTCTime, fromGregorian, secondsToDiffTime, UTCTime (..))
import Keiki.Core
import Keiki.Examples.UserRegistration
  ( Email
  , ConfirmationCode
  , StartRegistrationData (..)
  , ConfirmAccountData (..)
  , ResendConfirmationData (..)
  , FulfillGDPRRequestData (..)
  , UserCmd (..)
  , RegistrationStartedData (..)
  , ConfirmationEmailSentData (..)
  , ConfirmationResentData (..)
  , AccountDeletedData (..)
  , UserRegRegs
  , Vertex (..)
  )


-- * V0 event with the missing field ----------------------------------------

-- | Synthesis §4 step-4 unfixed schema: no @confirmCode@.
data AccountConfirmedDataV0 = AccountConfirmedDataV0
  { email :: Email
  , at    :: UTCTime
  } deriving (Eq, Show)


data UserEventV0
  = RegistrationStartedV0   RegistrationStartedData
  | ConfirmationEmailSentV0 ConfirmationEmailSentData
  | AccountConfirmedV0      AccountConfirmedDataV0
  | ConfirmationResentV0    ConfirmationResentData
  | AccountDeletedV0        AccountDeletedData
  deriving (Eq, Show)


-- * Transducer scaffolding ------------------------------------------------

emptyRegsV0 :: RegFile UserRegRegs
emptyRegsV0 =
  RCons (Proxy @"email")        (error "uninit: email")
  $ RCons (Proxy @"confirmCode")  (error "uninit: confirmCode")
  $ RCons (Proxy @"registeredAt") (error "uninit: registeredAt")
  $ RCons (Proxy @"confirmedAt")  (error "uninit: confirmedAt")
  $ RCons (Proxy @"deletedAt")    (error "uninit: deletedAt")
  $ RNil


inpStart :: (StartRegistrationData -> r) -> Term UserRegRegs UserCmd r
inpStart f = TInpField $ \case
  StartRegistration d -> f d
  _ -> error "inpStart"

inpConfirm :: (ConfirmAccountData -> r) -> Term UserRegRegs UserCmd r
inpConfirm f = TInpField $ \case
  ConfirmAccount d -> f d
  _ -> error "inpConfirm"

inpResend :: (ResendConfirmationData -> r) -> Term UserRegRegs UserCmd r
inpResend f = TInpField $ \case
  ResendConfirmation d -> f d
  _ -> error "inpResend"

inpGdpr :: (FulfillGDPRRequestData -> r) -> Term UserRegRegs UserCmd r
inpGdpr f = TInpField $ \case
  FulfillGDPRRequest d -> f d
  _ -> error "inpGdpr"


isStart, isConfirm, isResend, isGdpr, isContinue :: HsPred UserRegRegs UserCmd
isStart    = matchCmd $ \case StartRegistration{}  -> True; _ -> False
isConfirm  = matchCmd $ \case ConfirmAccount{}     -> True; _ -> False
isResend   = matchCmd $ \case ResendConfirmation{} -> True; _ -> False
isGdpr     = matchCmd $ \case FulfillGDPRRequest{} -> True; _ -> False
isContinue = matchCmd $ \case Continue             -> True; _ -> False


-- * V0 wire constructors ---------------------------------------------------

wireRegistrationStartedV0
  :: WireCtor UserEventV0 (Email, (ConfirmationCode, (UTCTime, ())))
wireRegistrationStartedV0 = WireCtor
  { wcName  = "RegistrationStartedV0"
  , wcMatch = \case
      RegistrationStartedV0 d -> Just (d.email, (d.confirmCode, (d.at, ())))
      _ -> Nothing
  , wcBuild = \(e, (cc, (a, ()))) ->
      RegistrationStartedV0 (RegistrationStartedData e cc a)
  }


wireConfirmationEmailSentV0
  :: WireCtor UserEventV0 (Email, ())
wireConfirmationEmailSentV0 = WireCtor
  { wcName  = "ConfirmationEmailSentV0"
  , wcMatch = \case
      ConfirmationEmailSentV0 d -> Just (d.email, ())
      _ -> Nothing
  , wcBuild = \(e, ()) ->
      ConfirmationEmailSentV0 (ConfirmationEmailSentData e)
  }


-- | The hidden-input culprit: AccountConfirmedDataV0 does not carry
-- @confirmCode@. The forward direction emits @(email, at)@; the
-- inverse cannot recover @ci.confirmCode@.
wireAccountConfirmedV0
  :: WireCtor UserEventV0 (Email, (UTCTime, ()))
wireAccountConfirmedV0 = WireCtor
  { wcName  = "AccountConfirmedV0"
  , wcMatch = \case
      AccountConfirmedV0 d -> Just (d.email, (d.at, ()))
      _ -> Nothing
  , wcBuild = \(e, (a, ())) ->
      AccountConfirmedV0 (AccountConfirmedDataV0 e a)
  }


wireConfirmationResentV0
  :: WireCtor UserEventV0 (Email, (ConfirmationCode, (UTCTime, ())))
wireConfirmationResentV0 = WireCtor
  { wcName  = "ConfirmationResentV0"
  , wcMatch = \case
      ConfirmationResentV0 d -> Just (d.email, (d.confirmCode, (d.at, ())))
      _ -> Nothing
  , wcBuild = \(e, (cc, (a, ()))) ->
      ConfirmationResentV0 (ConfirmationResentData e cc a)
  }


wireAccountDeletedV0
  :: WireCtor UserEventV0 (Email, (UTCTime, ()))
wireAccountDeletedV0 = WireCtor
  { wcName  = "AccountDeletedV0"
  , wcMatch = \case
      AccountDeletedV0 d -> Just (d.email, (d.at, ()))
      _ -> Nothing
  , wcBuild = \(e, (a, ())) ->
      AccountDeletedV0 (AccountDeletedData e a)
  }


-- * The V0 transducer ------------------------------------------------------

userRegV0
  :: SymTransducer (HsPred UserRegRegs UserCmd)
                   UserRegRegs
                   Vertex
                   UserCmd
                   UserEventV0
userRegV0 = SymTransducer
  { edgesOut = userRegV0Edges
  , initial     = PotentialCustomer
  , initialRegs = emptyRegsV0
  , isFinal     = \case Deleted -> True; _ -> False
  }


userRegV0Edges
  :: Vertex
  -> [Edge (HsPred UserRegRegs UserCmd) UserRegRegs UserCmd UserEventV0 Vertex]
userRegV0Edges = \case
  PotentialCustomer ->
    [ Edge
        { guard  = isStart
        , update =
            USet (#email :: Index UserRegRegs Email) (inpStart (.email))
              `unsafeCombine`
            USet (#confirmCode :: Index UserRegRegs ConfirmationCode)
                 (inpStart (.confirmCode))
              `unsafeCombine`
            USet (#registeredAt :: Index UserRegRegs UTCTime)
                 (inpStart (.at))
        , output = Just $ pack
            wireRegistrationStartedV0
            (OFCons (inpStart (.email))
              (OFCons (inpStart (.confirmCode))
                (OFCons (inpStart (.at)) OFNil)))
            (\_regs co -> case co of
                RegistrationStartedV0 ev ->
                  Just $ StartRegistration $ StartRegistrationData
                    ev.email ev.confirmCode ev.at
                _ -> Nothing)
        , target = Registering
        }
    ]

  Registering ->
    [ Edge
        { guard  = isContinue
        , update = UKeep
        , output = Just $ pack
            wireConfirmationEmailSentV0
            (OFCons (proj (#email :: Index UserRegRegs Email)) OFNil)
            (\_regs co -> case co of
                ConfirmationEmailSentV0 _ -> Just Continue
                _ -> Nothing)
        , target = RequiresConfirmation
        }
    ]

  RequiresConfirmation ->
    [ -- Right-code Confirm edge — UNFIXED. Output OutFields no longer
      -- carry confirmCode. The hand-written inverse cannot recover
      -- ci.confirmCode, so it returns Nothing — replay halts.
      Edge
        { guard  = PAnd isConfirm
            (inpConfirm (.confirmCode)
              .== proj (#confirmCode :: Index UserRegRegs ConfirmationCode))
        , update = USet (#confirmedAt :: Index UserRegRegs UTCTime)
                        (inpConfirm (.at))
        , output = Just $ pack
            wireAccountConfirmedV0
            (OFCons (proj (#email :: Index UserRegRegs Email))
              (OFCons (inpConfirm (.at)) OFNil))
            -- Honest inverse: the V0 wire can't supply confirmCode,
            -- so no consistent ci can be reconstructed. Returning
            -- Nothing surfaces the bug at replay time.
            (\_regs _co -> Nothing)
        , target = Confirmed
        }
    , Edge
        { guard  = isResend
        , update =
            USet (#confirmCode :: Index UserRegRegs ConfirmationCode)
                 (inpResend (.code))
              `unsafeCombine`
            USet (#registeredAt :: Index UserRegRegs UTCTime)
                 (inpResend (.at))
        , output = Just $ pack
            wireConfirmationResentV0
            (OFCons (proj (#email :: Index UserRegRegs Email))
              (OFCons (inpResend (.code))
                (OFCons (inpResend (.at)) OFNil)))
            (\_regs co -> case co of
                ConfirmationResentV0 ev ->
                  Just $ ResendConfirmation $ ResendConfirmationData
                    ev.confirmCode ev.at
                _ -> Nothing)
        , target = RequiresConfirmation
        }
    , Edge
        { guard  = isGdpr
        , update = USet (#deletedAt :: Index UserRegRegs UTCTime)
                        (inpGdpr (.at))
        , output = Nothing
        , target = Deleted
        }
    ]

  Confirmed ->
    [ Edge
        { guard  = isGdpr
        , update = USet (#deletedAt :: Index UserRegRegs UTCTime)
                        (inpGdpr (.at))
        , output = Just $ pack
            wireAccountDeletedV0
            (OFCons (proj (#email :: Index UserRegRegs Email))
              (OFCons (inpGdpr (.at)) OFNil))
            (\_regs co -> case co of
                AccountDeletedV0 ev ->
                  Just $ FulfillGDPRRequest $ FulfillGDPRRequestData ev.at
                _ -> Nothing)
        , target = Deleted
        }
    ]

  Deleted -> []


-- * The V0 canonical event log --------------------------------------------

canonicalLogV0 :: [UserEventV0]
canonicalLogV0 =
  [ RegistrationStartedV0   (RegistrationStartedData   "alice@x" "Z9F4" (mkT 0))
  , ConfirmationEmailSentV0 (ConfirmationEmailSentData "alice@x")
  , ConfirmationResentV0    (ConfirmationResentData    "alice@x" "K2P7" (mkT 100))
  , AccountConfirmedV0      (AccountConfirmedDataV0    "alice@x"        (mkT 200))
  , AccountDeletedV0        (AccountDeletedData        "alice@x"        (mkT 300))
  ]
  where
    mkT s = UTCTime (fromGregorian 2026 5 1) (secondsToDiffTime s)
