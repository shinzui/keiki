{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE QualifiedDo #-}
{-# LANGUAGE TemplateHaskell #-}

-- | A small Email Delivery aggregate, the second worked example in
-- the keiki repository. Pairs with 'Jitsurei.UserRegistration'
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
module Keiki.Fixtures.EmailDelivery
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
  , emailDeliveryAST
  , emptyEmailRegs
    -- * Wire constructors (exported for testing / composition)
  , wireEmailSent
    -- * Input constructors (exported for testing / composition)
  , inCtorSendEmail
  , inpSendEmail
    -- * B-presentation views (TH-derived; see EP-13 / MP-5)
  , SEmailVertex (..)
  , EmailView (..)
  , emailView
  ) where

import Data.Text (Text)
import Data.Time (UTCTime)
import GHC.Generics (Generic)
import Keiki.Core
import qualified Keiki.Builder as B
import Keiki.Builder ((.=))
import Keiki.Generics (emptyRegFile)
import Keiki.Generics.TH (deriveAggregateCtors, deriveView, deriveWireCtors)
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


-- * B-presentation views (TH-derived) ------------------------------------
--
-- The B-view exposes only the slots that are live in each control
-- vertex. 'EmailPending' is the initial state — no slots are bound,
-- so 'EmailPendingV' is nullary. 'EmailSentVertex' is terminal after
-- a 'SendEmail' command, by which point all three slots
-- ('emailRecipient', 'emailSubject', 'emailSentAt') are live, so
-- 'EmailSentVertexV' carries them as record fields.

$(deriveView ''EmailVertex ''EmailRegs
    "SEmailVertex" "EmailView" "emailView"
    [ ("EmailPending",     [])
    , ("EmailSentVertex",  ["emailRecipient", "emailSubject", "emailSentAt"])
    ])


-- * The transducer ---------------------------------------------------------

-- | The aggregate's transducer, authored with 'Keiki.Builder'. This
-- is the canonical form every downstream consumer
-- ('Keiki.Composition.compose', the deciders, the symbolic
-- analyses, the example specs) uses by name.
emailDelivery
  :: SymTransducer (HsPred EmailRegs EmailCmd)
                   EmailRegs
                   EmailVertex
                   EmailCmd
                   EmailEvent
emailDelivery = B.buildTransducer EmailPending emptyEmailRegs
                  (\case EmailSentVertex -> True; _ -> False) do

    B.from EmailPending do
      B.onCmd inCtorSendEmail $ \d -> B.do
        B.slot @"emailRecipient" .= d.recipient
        B.slot @"emailSubject"   .= d.subject
        B.slot @"emailSentAt"    .= d.at
        B.emit wireEmailSent EmailSentTermFields
          { recipient = d.recipient
          , subject   = d.subject
          , at        = d.at
          }
        B.goto EmailSentVertex


-- * AST form (legacy, retained for the M4 equivalence test) ----------------

-- | The same transducer hand-authored against the post-MP-6
-- "Keiki.Core" AST. Retained as a side-by-side reference for the
-- 'Keiki.Fixtures.EmailDeliveryBuilderSpec' equivalence test;
-- removable in a follow-up plan once the migration is judged
-- stable.
emailDeliveryAST
  :: SymTransducer (HsPred EmailRegs EmailCmd)
                   EmailRegs
                   EmailVertex
                   EmailCmd
                   EmailEvent
emailDeliveryAST = SymTransducer
  { edgesOut    = emailDeliveryASTEdges
  , initial     = EmailPending
  , initialRegs = emptyEmailRegs
  , isFinal     = \case EmailSentVertex -> True; _ -> False
  }


emailDeliveryASTEdges
  :: EmailVertex
  -> [Edge (HsPred EmailRegs EmailCmd) EmailRegs EmailCmd EmailEvent EmailVertex]
emailDeliveryASTEdges = \case

  EmailPending ->
    [ Edge
        { guard  = isSendEmail
        , update =
            USet (#emailRecipient :: IndexN "emailRecipient" EmailRegs Email)
                 (inpSendEmail #recipient)
              `combine`
            USet (#emailSubject :: IndexN "emailSubject" EmailRegs Subject)
                 (inpSendEmail #subject)
              `combine`
            USet (#emailSentAt :: IndexN "emailSentAt" EmailRegs UTCTime)
                 (inpSendEmail #at)
        , output = [ pack
            inCtorSendEmail
            wireEmailSent
            (OFCons (inpSendEmail #recipient)
              (OFCons (inpSendEmail #subject)
                (OFCons (inpSendEmail #at) OFNil))) ]
        , target = EmailSentVertex
        }
    ]

  EmailSentVertex -> []
