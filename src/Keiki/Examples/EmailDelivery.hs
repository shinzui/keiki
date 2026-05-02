{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE TemplateHaskell #-}

-- | A small Email Delivery aggregate, the second worked example in
-- the keiki repository. Pairs with 'Keiki.Examples.UserRegistration'
-- as the canonical multi-aggregate fixture for
-- 'Keiki.Composition.compose' and the M4 acceptance tests of EP-11
-- (under MasterPlan 4).
--
-- The aggregate is two-vertex: an idle Pending state transitions to
-- a terminal Sent state on a 'SendEmail' command, emitting an
-- 'EmailSent' event. The shape is deliberately minimal — one
-- vertex transition, one command constructor, one event
-- constructor — so the composite tests focus on @compose@'s
-- mechanics rather than per-aggregate complexity.
module Keiki.Examples.EmailDelivery
  ( -- * Domain types
    Email
  , Subject
    -- * Command payloads
  , SendEmailData (..)
  , EmailCmd (..)
    -- * Event payloads
  , EmailSentData (..)
  , EmailEvent (..)
    -- * Register file and control vertices
  , EmailRegs
  , EmailVertex (..)
    -- * The transducer
  , emailDelivery
  , emptyEmailRegs
    -- * Wire constructors (exported for testing / composition)
  , wireEmailSent
    -- * Input constructors (exported for testing / composition)
  , inCtorSendEmail
  , inpSendEmail
  ) where

import Data.Text (Text)
import Data.Time (UTCTime)
import GHC.Generics (Generic)
import Keiki.Core
import Keiki.Generics (emptyRegFile)
import Keiki.Generics.TH (deriveAggregateCtors, deriveWireCtors)
import Keiki.Symbolic (KnownInCtors (..), SomeInCtor (..))


-- * Domain types ------------------------------------------------------------

type Email   = Text
type Subject = Text


-- * Command payloads --------------------------------------------------------

data SendEmailData = SendEmailData
  { recipient :: Email
  , subject   :: Subject
  , at        :: UTCTime
  } deriving (Eq, Show, Generic)


data EmailCmd = SendEmail SendEmailData
  deriving (Eq, Show, Generic)


-- * Event payloads ----------------------------------------------------------

data EmailSentData = EmailSentData
  { recipient :: Email
  , subject   :: Subject
  , at        :: UTCTime
  } deriving (Eq, Show, Generic)


data EmailEvent = EmailSent EmailSentData
  deriving (Eq, Show, Generic)


-- * Register file and control vertices -------------------------------------

type EmailRegs =
  '[ '("emailRecipient", Email)
   , '("emailSubject",   Subject)
   , '("emailSentAt",    UTCTime)
   ]


data EmailVertex = EmailPending | EmailSentVertex
  deriving (Eq, Show, Enum, Bounded)


-- | Initial register file. Each slot is pre-bound to a deferred
-- @"uninit: <slot>"@ error by 'Keiki.Generics.emptyRegFile'.
emptyEmailRegs :: RegFile EmailRegs
emptyEmailRegs = emptyRegFile


-- * Per-constructor input projections + guards (TH-derived) --------------

$(deriveAggregateCtors ''EmailCmd ''EmailRegs
    [ ("SendEmail", "SendEmail")
    ])


-- | Enumerate the single 'InCtor' value of 'EmailCmd' so the
-- symbolic witness extractor can rebuild a concrete 'EmailCmd' from
-- an SBV model.
instance KnownInCtors EmailCmd where
  allInCtors = [ SomeInCtor inCtorSendEmail ]


-- * Wire constructors for events (TH-derived) ----------------------------

$(deriveWireCtors ''EmailEvent
    [ ("EmailSent", "EmailSent")
    ])


-- * The transducer ---------------------------------------------------------

emailDelivery
  :: SymTransducer (HsPred EmailRegs EmailCmd)
                   EmailRegs
                   EmailVertex
                   EmailCmd
                   EmailEvent
emailDelivery = SymTransducer
  { edgesOut    = emailDeliveryEdges
  , initial     = EmailPending
  , initialRegs = emptyEmailRegs
  , isFinal     = \case EmailSentVertex -> True; _ -> False
  }


emailDeliveryEdges
  :: EmailVertex
  -> [Edge (HsPred EmailRegs EmailCmd) EmailRegs EmailCmd EmailEvent EmailVertex]
emailDeliveryEdges = \case

  EmailPending ->
    [ Edge
        { guard  = isSendEmail
        , update =
            USet (#emailRecipient :: Index EmailRegs Email)
                 (inpSendEmail #recipient)
              `unsafeCombine`
            USet (#emailSubject :: Index EmailRegs Subject)
                 (inpSendEmail #subject)
              `unsafeCombine`
            USet (#emailSentAt :: Index EmailRegs UTCTime)
                 (inpSendEmail #at)
        , output = Just $ pack
            inCtorSendEmail
            wireEmailSent
            (OFCons (inpSendEmail #recipient)
              (OFCons (inpSendEmail #subject)
                (OFCons (inpSendEmail #at) OFNil)))
        , target = EmailSentVertex
        }
    ]

  EmailSentVertex -> []
