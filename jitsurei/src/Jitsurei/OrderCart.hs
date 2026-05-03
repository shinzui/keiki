{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE QualifiedDo #-}
{-# LANGUAGE TemplateHaskell #-}

-- | The Order/Cart aggregate: a richer, lifecycle-shaped fixture
-- introduced by EP-22 to anchor the @keiki-bench@ benchmark suite.
-- Sized so that 'reconstitute' over a 32+ event log meaningfully
-- amortises per-step setup, and shaped after the textbook online-
-- shopping aggregate (Empty -> OpenWithItems -> Reserved -> Paid ->
-- Shipped -> Delivered, plus Cancelled / Refunded branches).
--
-- Pairs with 'Jitsurei.UserRegistration' as the second
-- multi-command authoring showcase. Both builder-form ('orderCart')
-- and AST-form ('orderCartAST') values are exposed so
-- 'Jitsurei.OrderCartBuilderSpec' can assert byte-identical
-- replay agreement and the bench module can pit the two forms
-- head-to-head with @tasty-bench@'s @bcompare@.
module Jitsurei.OrderCart
  ( -- * Domain types
    Sku
  , DiscountBp
  , ItemQuantity
  , Money
  , ItemCount
    -- * Command payloads
  , AddItemData (..)
  , RemoveItemData (..)
  , ApplyDiscountData (..)
  , ReserveData (..)
  , ConfirmPaymentData (..)
  , ShipData (..)
  , DeliverData (..)
  , CancelData (..)
  , RequestRefundData (..)
  , ProcessRefundData (..)
  , OrderCmd (..)
    -- * Event payloads
  , ItemAddedData (..)
  , ItemRemovedData (..)
  , DiscountAppliedData (..)
  , OrderReservedData (..)
  , PaymentConfirmedData (..)
  , OrderShippedData (..)
  , OrderDeliveredData (..)
  , OrderCancelledData (..)
  , RefundRequestedData (..)
  , OrderRefundedData (..)
  , OrderEvent (..)
    -- * Register file and control vertices
  , OrderCartRegs
  , OrderVertex (..)
    -- * The transducer
  , orderCart
  , orderCartAST
  , emptyOrderRegs
    -- * Wire constructors (exported for testing)
  , wireItemAdded
  , wireItemRemoved
  , wireDiscountApplied
  , wireOrderReserved
  , wirePaymentConfirmed
  , wireOrderShipped
  , wireOrderDelivered
  , wireOrderCancelled
  , wireRefundRequested
  , wireOrderRefunded
    -- * Input constructors (exported for testing)
  , inCtorAddItem
  , inCtorRemoveItem
  , inCtorApplyDiscount
  , inCtorReserve
  , inCtorConfirmPayment
  , inCtorShip
  , inCtorDeliver
  , inCtorCancel
  , inCtorRequestRefund
  , inCtorProcessRefund
  , inpAddItem
  , inpRemoveItem
  , inpApplyDiscount
  , inpReserve
  , inpConfirmPayment
  , inpShip
  , inpDeliver
  , inpCancel
  , inpRequestRefund
  , inpProcessRefund
  ) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Data.Word (Word16, Word32, Word64)
import GHC.Generics (Generic)
import Keiki.Core
import qualified Keiki.Builder as B
import Keiki.Builder ((.=))
import Keiki.Generics (emptyRegFile)
import Keiki.Generics.TH (deriveAggregateCtors, deriveWireCtors)

-- | NB: no 'KnownInCtors OrderCmd' instance is provided here. That
-- typeclass is a witness for the SBV-backed @symSatExt@ pipeline,
-- which requires every slot type to be in 'Keiki.Symbolic.Sym'.
-- 'OrderCartRegs' carries 'Word16', 'Word32', and 'Word64' slots
-- that are not in the curated registry, and EP-22's plan declares
-- SBV-bound analyses out of scope for the OrderCart fixture (see
-- the EP-22 Decision Log entry "no symbolic-analysis instance for
-- OrderCmd"). The pure-core operations the benchmarks measure
-- ('delta', 'omega', 'step', 'applyEvent', 'reconstitute') are
-- unaffected.


-- * Domain types ------------------------------------------------------------

type Sku          = Text
type DiscountBp   = Word16   -- ^ Discount in basis points (0--10000).
type ItemQuantity = Word16
type Money        = Word64   -- ^ Fixed-point currency (e.g. cents).
type ItemCount    = Word32   -- ^ Number of items currently in the cart.


-- * Command payloads --------------------------------------------------------

data AddItemData = AddItemData
  { sku      :: Sku
  , quantity :: ItemQuantity
  , price    :: Money
  , at       :: UTCTime
  } deriving (Eq, Show, Generic)

data RemoveItemData = RemoveItemData
  { sku :: Sku
  , at  :: UTCTime
  } deriving (Eq, Show, Generic)

data ApplyDiscountData = ApplyDiscountData
  { code      :: Text
  , percentBp :: DiscountBp
  , at        :: UTCTime
  } deriving (Eq, Show, Generic)

data ReserveData = ReserveData
  { reservationId :: Text
  , at            :: UTCTime
  } deriving (Eq, Show, Generic)

data ConfirmPaymentData = ConfirmPaymentData
  { paymentRef :: Text
  , amountPaid :: Money
  , at         :: UTCTime
  } deriving (Eq, Show, Generic)

data ShipData = ShipData
  { carrier    :: Text
  , trackingId :: Text
  , at         :: UTCTime
  } deriving (Eq, Show, Generic)

newtype DeliverData = DeliverData { at :: UTCTime }
  deriving (Eq, Show, Generic)

data CancelData = CancelData
  { reason :: Text
  , at     :: UTCTime
  } deriving (Eq, Show, Generic)

data RequestRefundData = RequestRefundData
  { reason :: Text
  , at     :: UTCTime
  } deriving (Eq, Show, Generic)

data ProcessRefundData = ProcessRefundData
  { refundRef      :: Text
  , amountRefunded :: Money
  , at             :: UTCTime
  } deriving (Eq, Show, Generic)


data OrderCmd
  = AddItem        AddItemData
  | RemoveItem     RemoveItemData
  | ApplyDiscount  ApplyDiscountData
  | Reserve        ReserveData
  | ConfirmPayment ConfirmPaymentData
  | Ship           ShipData
  | Deliver        DeliverData
  | Cancel         CancelData
  | RequestRefund  RequestRefundData
  | ProcessRefund  ProcessRefundData
  deriving (Eq, Show, Generic)


-- * Event payloads ----------------------------------------------------------
--
-- Five event constructors carry an @"Order"@ prefix that disambiguates
-- them from same-named vertex constructors below ('Reserved',
-- 'Shipped', 'Delivered', 'Cancelled', 'Refunded'); within a Haskell
-- module two type-level data constructors cannot share a name even
-- across distinct sum types. The plan's narrative names the events
-- without the prefix (M2 Decision Log entry "event renaming").

data ItemAddedData = ItemAddedData
  { sku      :: Sku
  , quantity :: ItemQuantity
  , price    :: Money
  , at       :: UTCTime
  } deriving (Eq, Show, Generic)

data ItemRemovedData = ItemRemovedData
  { sku :: Sku
  , at  :: UTCTime
  } deriving (Eq, Show, Generic)

data DiscountAppliedData = DiscountAppliedData
  { code      :: Text
  , percentBp :: DiscountBp
  , at        :: UTCTime
  } deriving (Eq, Show, Generic)

data OrderReservedData = OrderReservedData
  { reservationId :: Text
  , at            :: UTCTime
  } deriving (Eq, Show, Generic)

data PaymentConfirmedData = PaymentConfirmedData
  { paymentRef :: Text
  , amountPaid :: Money
  , at         :: UTCTime
  } deriving (Eq, Show, Generic)

data OrderShippedData = OrderShippedData
  { carrier    :: Text
  , trackingId :: Text
  , at         :: UTCTime
  } deriving (Eq, Show, Generic)

newtype OrderDeliveredData = OrderDeliveredData { at :: UTCTime }
  deriving (Eq, Show, Generic)

data OrderCancelledData = OrderCancelledData
  { reason :: Text
  , at     :: UTCTime
  } deriving (Eq, Show, Generic)

data RefundRequestedData = RefundRequestedData
  { reason :: Text
  , at     :: UTCTime
  } deriving (Eq, Show, Generic)

data OrderRefundedData = OrderRefundedData
  { refundRef      :: Text
  , amountRefunded :: Money
  , at             :: UTCTime
  } deriving (Eq, Show, Generic)


data OrderEvent
  = ItemAdded         ItemAddedData
  | ItemRemoved       ItemRemovedData
  | DiscountApplied   DiscountAppliedData
  | OrderReserved     OrderReservedData
  | PaymentConfirmed  PaymentConfirmedData
  | OrderShipped      OrderShippedData
  | OrderDelivered    OrderDeliveredData
  | OrderCancelled    OrderCancelledData
  | RefundRequested   RefundRequestedData
  | OrderRefunded     OrderRefundedData
  deriving (Eq, Show, Generic)


-- * Register file and control vertices -------------------------------------

-- | Eleven slots covering the cart's evolving state. 'itemCount' is a
-- running tally evolved by 'TApp1' arithmetic on AddItem/RemoveItem;
-- the rest are simple per-event copies of input fields.
type OrderCartRegs =
  '[ '("itemCount",       ItemCount)
   , '("discountBp",      DiscountBp)
   , '("reservationId",   Text)
   , '("paymentRef",      Text)
   , '("amountPaid",      Money)
   , '("shippingCarrier", Text)
   , '("trackingId",      Text)
   , '("shippedAt",       UTCTime)
   , '("deliveredAt",     UTCTime)
   , '("cancelledAt",     UTCTime)
   , '("refundedAt",      UTCTime)
   ]


data OrderVertex
  = Empty
  | OpenWithItems
  | Reserved
  | Paid
  | Shipped
  | Delivered
  | Cancelled
  | Refunded
  deriving (Eq, Show, Enum, Bounded)


-- | Initial register file. Each slot is pre-bound to a deferred
-- @"uninit: <slot>"@ error by 'Keiki.Generics.emptyRegFile' so reads
-- of an uninitialized slot crash with a targeted message instead of
-- a silent bottom.
emptyOrderRegs :: RegFile OrderCartRegs
emptyOrderRegs = emptyRegFile


-- * Per-constructor input projections + guards (TH-derived) --------------

$(deriveAggregateCtors ''OrderCmd ''OrderCartRegs
    [ ("AddItem",        "AddItem")
    , ("RemoveItem",     "RemoveItem")
    , ("ApplyDiscount",  "ApplyDiscount")
    , ("Reserve",        "Reserve")
    , ("ConfirmPayment", "ConfirmPayment")
    , ("Ship",           "Ship")
    , ("Deliver",        "Deliver")
    , ("Cancel",         "Cancel")
    , ("RequestRefund",  "RequestRefund")
    , ("ProcessRefund",  "ProcessRefund")
    ])


-- * Wire constructors for events (TH-derived) ----------------------------

$(deriveWireCtors ''OrderEvent
    [ ("ItemAdded",        "ItemAdded")
    , ("ItemRemoved",      "ItemRemoved")
    , ("DiscountApplied",  "DiscountApplied")
    , ("OrderReserved",    "OrderReserved")
    , ("PaymentConfirmed", "PaymentConfirmed")
    , ("OrderShipped",     "OrderShipped")
    , ("OrderDelivered",   "OrderDelivered")
    , ("OrderCancelled",   "OrderCancelled")
    , ("RefundRequested",  "RefundRequested")
    , ("OrderRefunded",    "OrderRefunded")
    ])


-- * The transducer ---------------------------------------------------------

-- | The aggregate's transducer, authored with 'Keiki.Builder'. Twelve
-- edges across eight vertices; the canonical happy path is
-- Empty -> OpenWithItems -> Reserved -> Paid -> Shipped -> Delivered.
orderCart :: SymTransducer (HsPred OrderCartRegs OrderCmd)
                           OrderCartRegs
                           OrderVertex
                           OrderCmd
                           OrderEvent
orderCart = B.buildTransducer Empty emptyOrderRegs
              (\case Delivered -> True
                     Cancelled -> True
                     Refunded  -> True
                     _         -> False) do

  B.from Empty do
    -- The first AddItem seeds itemCount from a literal rather than
    -- reading the (uninitialised) #itemCount slot.
    B.onCmd inCtorAddItem $ \d -> B.do
      B.slot @"itemCount" .= lit (1 :: ItemCount)
      B.emit wireItemAdded ItemAddedTermFields
        { sku      = d.sku
        , quantity = d.quantity
        , price    = d.price
        , at       = d.at
        }
      B.goto OpenWithItems

  B.from OpenWithItems do
    B.onCmd inCtorAddItem $ \d -> B.do
      B.slot @"itemCount" .= TApp1 (+ 1) #itemCount
      B.emit wireItemAdded ItemAddedTermFields
        { sku      = d.sku
        , quantity = d.quantity
        , price    = d.price
        , at       = d.at
        }
      B.goto OpenWithItems

    B.onCmd inCtorRemoveItem $ \d -> B.do
      B.slot @"itemCount" .= TApp1 (subtract 1) #itemCount
      B.emit wireItemRemoved ItemRemovedTermFields
        { sku = d.sku
        , at  = d.at
        }
      B.goto OpenWithItems

    B.onCmd inCtorApplyDiscount $ \d -> B.do
      B.slot @"discountBp" .= d.percentBp
      B.emit wireDiscountApplied DiscountAppliedTermFields
        { code      = d.code
        , percentBp = d.percentBp
        , at        = d.at
        }
      B.goto OpenWithItems

    B.onCmd inCtorReserve $ \d -> B.do
      B.slot @"reservationId" .= d.reservationId
      B.emit wireOrderReserved OrderReservedTermFields
        { reservationId = d.reservationId
        , at            = d.at
        }
      B.goto Reserved

    B.onCmd inCtorCancel $ \d -> B.do
      B.slot @"cancelledAt" .= d.at
      B.emit wireOrderCancelled OrderCancelledTermFields
        { reason = d.reason
        , at     = d.at
        }
      B.goto Cancelled

  B.from Reserved do
    B.onCmd inCtorConfirmPayment $ \d -> B.do
      B.slot @"paymentRef" .= d.paymentRef
      B.slot @"amountPaid" .= d.amountPaid
      B.emit wirePaymentConfirmed PaymentConfirmedTermFields
        { paymentRef = d.paymentRef
        , amountPaid = d.amountPaid
        , at         = d.at
        }
      B.goto Paid

    B.onCmd inCtorCancel $ \d -> B.do
      B.slot @"cancelledAt" .= d.at
      B.emit wireOrderCancelled OrderCancelledTermFields
        { reason = d.reason
        , at     = d.at
        }
      B.goto Cancelled

  B.from Paid do
    B.onCmd inCtorShip $ \d -> B.do
      B.slot @"shippingCarrier" .= d.carrier
      B.slot @"trackingId"      .= d.trackingId
      B.slot @"shippedAt"       .= d.at
      B.emit wireOrderShipped OrderShippedTermFields
        { carrier    = d.carrier
        , trackingId = d.trackingId
        , at         = d.at
        }
      B.goto Shipped

    -- RequestRefund self-loops on Paid: emits an audit event but
    -- writes no slot. ProcessRefund is the actual refund step.
    B.onCmd inCtorRequestRefund $ \d -> B.do
      B.emit wireRefundRequested RefundRequestedTermFields
        { reason = d.reason
        , at     = d.at
        }
      B.goto Paid

    B.onCmd inCtorProcessRefund $ \d -> B.do
      B.slot @"refundedAt" .= d.at
      B.emit wireOrderRefunded OrderRefundedTermFields
        { refundRef      = d.refundRef
        , amountRefunded = d.amountRefunded
        , at             = d.at
        }
      B.goto Refunded

  B.from Shipped do
    B.onCmd inCtorDeliver $ \d -> B.do
      B.slot @"deliveredAt" .= d.at
      B.emit wireOrderDelivered OrderDeliveredTermFields
        { at = d.at
        }
      B.goto Delivered

  -- Delivered, Cancelled, Refunded are terminal (default []).


-- * AST form (for the M2 equivalence test and the head-to-head bench) ----

-- | The same transducer hand-authored against the post-MP-6
-- "Keiki.Core" AST. Retained as a side-by-side reference for the
-- 'Jitsurei.OrderCartBuilderSpec' equivalence test and for the
-- builder/AST head-to-head group of @keiki-bench@.
orderCartAST :: SymTransducer (HsPred OrderCartRegs OrderCmd)
                              OrderCartRegs
                              OrderVertex
                              OrderCmd
                              OrderEvent
orderCartAST = SymTransducer
  { edgesOut    = orderCartASTEdges
  , initial     = Empty
  , initialRegs = emptyOrderRegs
  , isFinal     = \case Delivered -> True
                        Cancelled -> True
                        Refunded  -> True
                        _         -> False
  }


orderCartASTEdges
  :: OrderVertex
  -> [Edge (HsPred OrderCartRegs OrderCmd)
           OrderCartRegs OrderCmd OrderEvent OrderVertex]
orderCartASTEdges = \case

  Empty ->
    [ Edge
        { guard  = isAddItem
        , update = USet (#itemCount :: IndexN "itemCount" OrderCartRegs ItemCount)
                        (lit (1 :: ItemCount))
        , output = Just $ pack
            inCtorAddItem
            wireItemAdded
            (OFCons (inpAddItem #sku)
              (OFCons (inpAddItem #quantity)
                (OFCons (inpAddItem #price)
                  (OFCons (inpAddItem #at) OFNil))))
        , target = OpenWithItems
        }
    ]

  OpenWithItems ->
    [ Edge
        { guard  = isAddItem
        , update = USet (#itemCount :: IndexN "itemCount" OrderCartRegs ItemCount)
                        (TApp1 (+ 1) (proj (#itemCount :: Index OrderCartRegs ItemCount)))
        , output = Just $ pack
            inCtorAddItem
            wireItemAdded
            (OFCons (inpAddItem #sku)
              (OFCons (inpAddItem #quantity)
                (OFCons (inpAddItem #price)
                  (OFCons (inpAddItem #at) OFNil))))
        , target = OpenWithItems
        }
    , Edge
        { guard  = isRemoveItem
        , update = USet (#itemCount :: IndexN "itemCount" OrderCartRegs ItemCount)
                        (TApp1 (subtract 1)
                               (proj (#itemCount :: Index OrderCartRegs ItemCount)))
        , output = Just $ pack
            inCtorRemoveItem
            wireItemRemoved
            (OFCons (inpRemoveItem #sku)
              (OFCons (inpRemoveItem #at) OFNil))
        , target = OpenWithItems
        }
    , Edge
        { guard  = isApplyDiscount
        , update = USet (#discountBp :: IndexN "discountBp" OrderCartRegs DiscountBp)
                        (inpApplyDiscount #percentBp)
        , output = Just $ pack
            inCtorApplyDiscount
            wireDiscountApplied
            (OFCons (inpApplyDiscount #code)
              (OFCons (inpApplyDiscount #percentBp)
                (OFCons (inpApplyDiscount #at) OFNil)))
        , target = OpenWithItems
        }
    , Edge
        { guard  = isReserve
        , update = USet (#reservationId :: IndexN "reservationId" OrderCartRegs Text)
                        (inpReserve #reservationId)
        , output = Just $ pack
            inCtorReserve
            wireOrderReserved
            (OFCons (inpReserve #reservationId)
              (OFCons (inpReserve #at) OFNil))
        , target = Reserved
        }
    , Edge
        { guard  = isCancel
        , update = USet (#cancelledAt :: IndexN "cancelledAt" OrderCartRegs UTCTime)
                        (inpCancel #at)
        , output = Just $ pack
            inCtorCancel
            wireOrderCancelled
            (OFCons (inpCancel #reason)
              (OFCons (inpCancel #at) OFNil))
        , target = Cancelled
        }
    ]

  Reserved ->
    [ Edge
        { guard  = isConfirmPayment
        , update =
            USet (#paymentRef :: IndexN "paymentRef" OrderCartRegs Text)
                 (inpConfirmPayment #paymentRef)
              `combine`
            USet (#amountPaid :: IndexN "amountPaid" OrderCartRegs Money)
                 (inpConfirmPayment #amountPaid)
        , output = Just $ pack
            inCtorConfirmPayment
            wirePaymentConfirmed
            (OFCons (inpConfirmPayment #paymentRef)
              (OFCons (inpConfirmPayment #amountPaid)
                (OFCons (inpConfirmPayment #at) OFNil)))
        , target = Paid
        }
    , Edge
        { guard  = isCancel
        , update = USet (#cancelledAt :: IndexN "cancelledAt" OrderCartRegs UTCTime)
                        (inpCancel #at)
        , output = Just $ pack
            inCtorCancel
            wireOrderCancelled
            (OFCons (inpCancel #reason)
              (OFCons (inpCancel #at) OFNil))
        , target = Cancelled
        }
    ]

  Paid ->
    [ Edge
        { guard  = isShip
        , update =
            USet (#shippingCarrier :: IndexN "shippingCarrier" OrderCartRegs Text)
                 (inpShip #carrier)
              `combine`
            USet (#trackingId :: IndexN "trackingId" OrderCartRegs Text)
                 (inpShip #trackingId)
              `combine`
            USet (#shippedAt :: IndexN "shippedAt" OrderCartRegs UTCTime)
                 (inpShip #at)
        , output = Just $ pack
            inCtorShip
            wireOrderShipped
            (OFCons (inpShip #carrier)
              (OFCons (inpShip #trackingId)
                (OFCons (inpShip #at) OFNil)))
        , target = Shipped
        }
    , Edge
        { guard  = isRequestRefund
        , update = UKeep
        , output = Just $ pack
            inCtorRequestRefund
            wireRefundRequested
            (OFCons (inpRequestRefund #reason)
              (OFCons (inpRequestRefund #at) OFNil))
        , target = Paid
        }
    , Edge
        { guard  = isProcessRefund
        , update = USet (#refundedAt :: IndexN "refundedAt" OrderCartRegs UTCTime)
                        (inpProcessRefund #at)
        , output = Just $ pack
            inCtorProcessRefund
            wireOrderRefunded
            (OFCons (inpProcessRefund #refundRef)
              (OFCons (inpProcessRefund #amountRefunded)
                (OFCons (inpProcessRefund #at) OFNil)))
        , target = Refunded
        }
    ]

  Shipped ->
    [ Edge
        { guard  = isDeliver
        , update = USet (#deliveredAt :: IndexN "deliveredAt" OrderCartRegs UTCTime)
                        (inpDeliver #at)
        , output = Just $ pack
            inCtorDeliver
            wireOrderDelivered
            (OFCons (inpDeliver #at) OFNil)
        , target = Delivered
        }
    ]

  Delivered -> []
  Cancelled -> []
  Refunded  -> []
