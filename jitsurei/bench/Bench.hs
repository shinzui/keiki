-- | EP-22 M3: per-step performance benchmark for the keiki pure
-- core. Exercises 'delta', 'omega', 'step', 'applyEvent', and
-- 'reconstitute' on two example aggregates ('UserRegistration' and
-- 'OrderCart'), each in two authoring forms (builder and AST).
--
-- Run: @cabal bench@. Capture a baseline:
--   @cabal bench --benchmark-options "--csv baseline.csv"@.
-- Compare against a baseline:
--   @cabal bench --benchmark-options "--baseline baseline.csv"@.
--
-- The 'head-to-head' group decorates the AST-form @step@ and
-- @reconstitute@ benches with @bcompare@ pointers at their
-- builder-form counterparts so each row prints a relative ratio.
module Main (main) where

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import qualified Data.Text as T
import Test.Tasty.Bench
  ( Benchmark, bcompare, bench, bgroup, defaultMain, whnf )
import Keiki.Core
  ( HsPred
  , SymTransducer (initial, initialRegs)
  , applyEvent
  , delta
  , omega
  , reconstitute
  , step
  )
import qualified Jitsurei.OrderCart        as OC
import qualified Jitsurei.UserRegistration as UR


-- * Time fixture ------------------------------------------------------------

-- | Synthetic UTC fixture: every moment is on the same day, offset
-- by N seconds. Concrete dates do not matter for replay correctness
-- or for measurement.
t :: Integer -> UTCTime
t s = UTCTime (fromGregorian 2026 5 1) (secondsToDiffTime s)


-- * UserRegistration fixtures -----------------------------------------------

-- | A length-32 UserRegistration replay log. Walks PotentialCustomer
-- -> Registering -> RequiresConfirmation, then loops 'Resend' 28
-- times (each rotates the confirmation code), then completes via
-- AccountConfirmed -> Confirmed -> Deleted. Total: 4 + 28 = 32 events.
urLog :: [UR.UserEvent]
urLog =
  UR.RegistrationStarted   (UR.RegistrationStartedData "alice@x" "C0000" (t 0))
  : UR.ConfirmationEmailSent (UR.ConfirmationEmailSentData "alice@x")
  : [ UR.ConfirmationResent
        (UR.ConfirmationResentData
          "alice@x"
          (T.pack ("C" <> pad4 i))
          (t (fromIntegral i)))
    | i <- [1 .. 28 :: Int]
    ]
 ++ [ UR.AccountConfirmed (UR.AccountConfirmedData "alice@x" "C0028" (t 1000))
    , UR.AccountDeleted   (UR.AccountDeletedData   "alice@x"          (t 2000))
    ]
  where
    pad4 :: Int -> String
    pad4 n
      | n < 10    = "000" <> show n
      | n < 100   = "00"  <> show n
      | n < 1000  = "0"   <> show n
      | otherwise = show n


-- | A single command for the per-step UserRegistration benches:
-- 'StartRegistration', the canonical first transition.
urCmd :: UR.UserCmd
urCmd = UR.StartRegistration
          (UR.StartRegistrationData "alice@x" "C0000" (t 0))


-- | A single event for the UserRegistration applyEvent bench:
-- 'RegistrationStarted', the canonical first event.
urEvt :: UR.UserEvent
urEvt = UR.RegistrationStarted
          (UR.RegistrationStartedData "alice@x" "C0000" (t 0))


-- * OrderCart fixtures ------------------------------------------------------

-- | A length-32 OrderCart replay log on the happy path: 27 ItemAdded
-- events (1 transitions Empty -> OpenWithItems, 26 self-loop on
-- OpenWithItems), then DiscountApplied, OrderReserved,
-- PaymentConfirmed, OrderShipped, OrderDelivered. Total: 27 + 5 = 32
-- events.
ocLog :: [OC.OrderEvent]
ocLog =
  [ OC.ItemAdded (OC.ItemAddedData
                    (T.pack ("S" <> pad4 i))
                    (fromIntegral i)
                    (100 + 10 * fromIntegral i)
                    (t (fromIntegral i)))
  | i <- [1 .. 27 :: Int]
  ]
 ++
  [ OC.DiscountApplied  (OC.DiscountAppliedData  "SAVE10"     1000 (t 28))
  , OC.OrderReserved    (OC.OrderReservedData    "RES-0001"        (t 29))
  , OC.PaymentConfirmed (OC.PaymentConfirmedData "PAY-0001" 99999  (t 30))
  , OC.OrderShipped     (OC.OrderShippedData     "UPS" "TRACK-0001" (t 31))
  , OC.OrderDelivered   (OC.OrderDeliveredData                      (t 32))
  ]
  where
    pad4 :: Int -> String
    pad4 n
      | n < 10    = "000" <> show n
      | n < 100   = "00"  <> show n
      | n < 1000  = "0"   <> show n
      | otherwise = show n


-- | A single command for the per-step OrderCart benches: AddItem
-- against the empty initial cart (Empty -> OpenWithItems).
ocCmd :: OC.OrderCmd
ocCmd = OC.AddItem
          (OC.AddItemData "S0001" 1 100 (t 0))


-- | A single event for the OrderCart applyEvent bench: ItemAdded
-- (matches the first entry of 'ocLog').
ocEvt :: OC.OrderEvent
ocEvt = OC.ItemAdded (OC.ItemAddedData "S0001" 1 110 (t 1))


-- * Per-aggregate operation matrix ------------------------------------------

-- | One bgroup per (aggregate, form) carrying five leaf benches: one
-- per pure-core operation. Keeps each measurement under a unique
-- path so 'bcompare' can address the builder-form counterparts.
urOps
  :: String
  -> SymTransducer (HsPred UR.UserRegRegs UR.UserCmd)
                   UR.UserRegRegs UR.Vertex
                   UR.UserCmd UR.UserEvent
  -> Benchmark
urOps form tr =
  bgroup form
    [ bench "delta"        $ whnf (delta tr v0 r0) urCmd
    , bench "omega"        $ whnf (omega tr v0 r0) urCmd
    , bench "step"         $ whnf (step  tr (v0, r0)) urCmd
    , bench "applyEvent"   $ whnf (applyEvent tr v0 r0) urEvt
    , bench "reconstitute" $ whnf (reconstitute tr) urLog
    ]
  where
    v0 = initial tr
    r0 = initialRegs tr


ocOps
  :: String
  -> SymTransducer (HsPred OC.OrderCartRegs OC.OrderCmd)
                   OC.OrderCartRegs OC.OrderVertex
                   OC.OrderCmd OC.OrderEvent
  -> Benchmark
ocOps form tr =
  bgroup form
    [ bench "delta"        $ whnf (delta tr v0 r0) ocCmd
    , bench "omega"        $ whnf (omega tr v0 r0) ocCmd
    , bench "step"         $ whnf (step  tr (v0, r0)) ocCmd
    , bench "applyEvent"   $ whnf (applyEvent tr v0 r0) ocEvt
    , bench "reconstitute" $ whnf (reconstitute tr) ocLog
    ]
  where
    v0 = initial tr
    r0 = initialRegs tr


-- * Head-to-head group ------------------------------------------------------

-- | Build an AWK pattern that matches a unique benchmark by its full
-- path. 'bcompare' uses tasty's pattern matcher to locate the
-- baseline; '$NF == ...' compares the innermost path segment,
-- '$(NF-1) == ...' the next outer, etc. The path elements are given
-- outer-to-inner ([\"All\", \"UserReg\", \"builder\", \"step\"]).
awkPath :: [String] -> String
awkPath segments =
  case segments of
    [] -> "1"
    _  -> intercalateAwk (zipWith pieceAt [0 :: Int ..] (reverse segments))
  where
    pieceAt 0 s = "$NF == \""        <> s <> "\""
    pieceAt k s = "$(NF-" <> show k <> ") == \"" <> s <> "\""

    intercalateAwk []     = ""
    intercalateAwk [x]    = x
    intercalateAwk (x:xs) = x <> " && " <> intercalateAwk xs


-- | Side-by-side ratios on the two highest-signal pure-core
-- operations: 'step' (combined transition + output) and
-- 'reconstitute' (full-log replay). The bench under each entry runs
-- independently of the per-aggregate group above, so the ratio is
-- reported on a fresh measurement of the AST form vs the baseline
-- builder form (located by the AWK pattern).
headToHead :: [Benchmark]
headToHead =
  [ bcompare (awkPath ["All", "UserReg", "builder", "step"]) $
      bench "UserReg/ast vs builder/step" $
        whnf (step UR.userRegAST (initial UR.userRegAST,
                                  initialRegs UR.userRegAST)) urCmd
  , bcompare (awkPath ["All", "UserReg", "builder", "reconstitute"]) $
      bench "UserReg/ast vs builder/reconstitute" $
        whnf (reconstitute UR.userRegAST) urLog
  , bcompare (awkPath ["All", "OrderCart", "builder", "step"]) $
      bench "OrderCart/ast vs builder/step" $
        whnf (step OC.orderCartAST (initial OC.orderCartAST,
                                    initialRegs OC.orderCartAST)) ocCmd
  , bcompare (awkPath ["All", "OrderCart", "builder", "reconstitute"]) $
      bench "OrderCart/ast vs builder/reconstitute" $
        whnf (reconstitute OC.orderCartAST) ocLog
  ]


-- * Entry point -------------------------------------------------------------

main :: IO ()
main = defaultMain
  [ bgroup "UserReg"
      [ urOps "builder" UR.userReg
      , urOps "ast"     UR.userRegAST
      ]
  , bgroup "OrderCart"
      [ ocOps "builder" OC.orderCart
      , ocOps "ast"     OC.orderCartAST
      ]
  , bgroup "head-to-head" headToHead
  ]
