-- | EP-22 M2: cross-form equivalence test for the OrderCart aggregate.
-- Asserts that the builder-form 'orderCart' and the AST-form
-- 'orderCartAST' produce identical reconstitute / per-step state on a
-- multi-event canonical log walking the happy path.
module Jitsurei.OrderCartBuilderSpec (spec) where

import Data.Text (Text)
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Data.Word (Word16, Word32, Word64)
import Jitsurei.OrderCart
import Keiki.Core
import Test.Hspec

-- | Snapshot of the slots written on the happy path. 'cancelledAt'
-- and 'refundedAt' are excluded because the canonical happy-path log
-- never visits the Cancelled / Refunded vertices, leaving those slots
-- bound to 'emptyRegFile''s deferred @uninit@ error; reading them
-- would crash with no information added to the equivalence check.
type HappySnapshot =
  ( Word32,
    Word16,
    Text,
    Text,
    Word64,
    Text,
    Text,
    UTCTime,
    UTCTime
  )

happySnapshot :: RegFile OrderCartRegs -> HappySnapshot
happySnapshot regs =
  ( regs ! #itemCount,
    regs ! #discountBp,
    regs ! #reservationId,
    regs ! #paymentRef,
    regs ! #amountPaid,
    regs ! #shippingCarrier,
    regs ! #trackingId,
    regs ! #shippedAt,
    regs ! #deliveredAt
  )

t :: Integer -> UTCTime
t s = UTCTime (fromGregorian 2026 5 1) (secondsToDiffTime s)

-- | Happy-path canonical log: Empty -> OpenWithItems (x4 AddItems) ->
-- DiscountApplied -> Reserved -> Paid -> Shipped -> Delivered. Eight
-- events; the bench fixture in @bench/Bench.hs@ uses a longer log
-- (>= 32) but for an equivalence check the shorter log is enough —
-- it walks every happy-path edge at least once.
canonicalLog :: [OrderEvent]
canonicalLog =
  [ ItemAdded (ItemAddedData "S0001" 1 100 (t 0)),
    ItemAdded (ItemAddedData "S0002" 2 250 (t 1)),
    ItemAdded (ItemAddedData "S0003" 1 500 (t 2)),
    ItemAdded (ItemAddedData "S0004" 5 125 (t 3)),
    DiscountApplied (DiscountAppliedData "SAVE10" 1000 (t 4)),
    OrderReserved (OrderReservedData "RES-42" (t 5)),
    PaymentConfirmed (PaymentConfirmedData "PAY-99" 1925 (t 6)),
    OrderShipped (OrderShippedData "UPS" "TRACK-1" (t 7)),
    OrderDelivered (OrderDeliveredData (t 8))
  ]

-- | Cancellation-path canonical log: Empty -> OpenWithItems -> Cancelled.
cancelLog :: [OrderEvent]
cancelLog =
  [ ItemAdded (ItemAddedData "S0001" 1 100 (t 0)),
    OrderCancelled (OrderCancelledData "out-of-stock" (t 1))
  ]

-- | Refund-path canonical log: Empty -> Open -> Reserved -> Paid ->
-- (RefundRequested self-loop) -> Refunded.
refundLog :: [OrderEvent]
refundLog =
  [ ItemAdded (ItemAddedData "S0001" 1 100 (t 0)),
    OrderReserved (OrderReservedData "RES-7" (t 1)),
    PaymentConfirmed (PaymentConfirmedData "PAY-7" 100 (t 2)),
    RefundRequested (RefundRequestedData "buyer-remorse" (t 3)),
    OrderRefunded (OrderRefundedData "RFND-7" 100 (t 4))
  ]

spec :: Spec
spec = do
  describe "EP-22 M2: builder vs AST agreement on three canonical logs" $ do
    it "happy-path log: reconstitute returns the same (state, snapshot)" $ do
      let astResult = reconstitute orderCartAST canonicalLog
          builtResult = reconstitute orderCart canonicalLog
      case (astResult, builtResult) of
        (Just (sA, regsA), Just (sB, regsB)) -> do
          sA `shouldBe` sB
          happySnapshot regsA `shouldBe` happySnapshot regsB
          sA `shouldBe` Delivered
        (a, b) ->
          expectationFailure
            ( "reconstitute results differ: "
                <> show (fmap fst a)
                <> " vs "
                <> show (fmap fst b)
            )

    it "cancel-path log: reconstitute agrees and lands in Cancelled" $ do
      reconstituteVertex orderCart cancelLog `shouldBe` Just Cancelled
      reconstituteVertex orderCartAST cancelLog `shouldBe` Just Cancelled

    it "refund-path log: reconstitute agrees and lands in Refunded" $ do
      reconstituteVertex orderCart refundLog `shouldBe` Just Refunded
      reconstituteVertex orderCartAST refundLog `shouldBe` Just Refunded

    it "isFinal predicate matches across all eight vertices" $ do
      let vs =
            [ Empty,
              OpenWithItems,
              Reserved,
              Paid,
              Shipped,
              Delivered,
              Cancelled,
              Refunded
            ]
      [isFinal orderCartAST v | v <- vs]
        `shouldBe` [isFinal orderCart v | v <- vs]

    it "edge counts per vertex match between forms" $ do
      let vs =
            [ Empty,
              OpenWithItems,
              Reserved,
              Paid,
              Shipped,
              Delivered,
              Cancelled,
              Refunded
            ]
      [length (edgesOut orderCartAST v) | v <- vs]
        `shouldBe` [length (edgesOut orderCart v) | v <- vs]

  describe "EP-22 M2: per-step applyEvent agreement on the happy log" $ do
    it "every step of the happy-path log lands in the same target vertex" $
      walkBoth
        (0 :: Int)
        canonicalLog
        (initial orderCart, initialRegs orderCart)
        (initial orderCartAST, initialRegs orderCartAST)
  where
    reconstituteVertex tr log_ = fmap fst (reconstitute tr log_)

    -- Walk the canonical log step-by-step, asserting that the
    -- builder-form and AST-form transducers land in the same target
    -- vertex on every event. Per-step register snapshots are not
    -- compared because intermediate states have uninitialised slots
    -- that would crash on read; the end-to-end snapshot test above
    -- compares once every slot is set.
    walkBoth _ [] _ _ = pure ()
    walkBoth i (ev : rest) (sB, rB) (sA, rA) =
      case (applyEvent orderCart sB rB ev, applyEvent orderCartAST sA rA ev) of
        (Just (sB', rB'), Just (sA', rA')) -> do
          sB' `shouldBe` sA'
          walkBoth (i + 1) rest (sB', rB') (sA', rA')
        (nB, nA) ->
          expectationFailure
            ( "step "
                <> show i
                <> ": applyEvent disagreement: "
                <> "builder="
                <> show (fmap fst nB)
                <> " ast="
                <> show (fmap fst nA)
            )
