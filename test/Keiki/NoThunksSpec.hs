{-# LANGUAGE DerivingVia #-}
-- 'Vertex' is a user-defined nullary enum in
-- "Keiki.Fixtures.UserRegistration"; we add an orphan
-- @NoThunks Vertex@ here purely for the canonical-log assertion.
-- This mirrors the pattern a real embedder would use in their own
-- module: derive via 'OnlyCheckWhnf' for small enum-like vertices.
{-# OPTIONS_GHC -Wno-orphans #-}

module Keiki.NoThunksSpec (spec) where

import Control.DeepSeq (force)
import Data.Maybe (isNothing)
import Data.Proxy (Proxy (..))
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Keiki.Core (RegFile (..), reconstitute)
import Keiki.Fixtures.UserRegistration
  ( AccountConfirmedData (..),
    AccountDeletedData (..),
    ConfirmationEmailSentData (..),
    ConfirmationResentData (..),
    RegistrationStartedData (..),
    UserEvent (..),
    Vertex,
    userReg,
  )
import Keiki.NoThunks ()
import NoThunks.Class (NoThunks, OnlyCheckWhnf (..), noThunks)
import Test.Hspec

deriving via OnlyCheckWhnf Vertex instance NoThunks Vertex

-- | A trivial UTC-time fixture, mirroring the one in
-- 'Keiki.Fixtures.UserRegistrationSpec', except deep-forced.
--
-- 'Data.Time.Clock.UTCTime'\'s fields are *lazy* — bang-binding the
-- whole value reaches WHNF (the outer constructor) but leaves
-- @utctDay@ and @utctDayTime@ as thunks. The bundled @nothunks@
-- instance derives via 'NoThunks.Class.InspectHeap' and walks the
-- entire heap closure, so it would report those internal thunks as
-- (false-positive) leaks. 'Control.DeepSeq.force' uses the @time@
-- package's 'Control.DeepSeq.NFData' instance to evaluate the
-- whole structure to NF, dispelling the false positive.
t :: Integer -> UTCTime
t s = force (UTCTime (fromGregorian 2026 5 1) (secondsToDiffTime s))

-- | The synthesis §4 canonical event log. Reproduced inline (rather
-- than imported) because the upstream definition lives in another
-- spec module's local scope; coupling test modules to share a
-- five-line literal would cost more than it saves.
canonicalLog :: [UserEvent]
canonicalLog =
  let !t0 = t 0
      !t100 = t 100
      !t200 = t 200
      !t300 = t 300
   in [ RegistrationStarted (RegistrationStartedData "alice@x" "Z9F4" t0),
        ConfirmationEmailSent (ConfirmationEmailSentData "alice@x"),
        ConfirmationResent (ConfirmationResentData "alice@x" "K2P7" t100),
        AccountConfirmed (AccountConfirmedData "alice@x" "K2P7" t200),
        AccountDeleted (AccountDeletedData "alice@x" t300)
      ]

-- A genuine thunk for the sanity check. Using @(1 + 1) :: Int@ as a
-- fixture is unreliable: GHC at -O1 may constant-fold it before the
-- thunk is ever stored. NOINLINE on a top-level binding keeps the
-- reference opaque to the optimizer.
{-# NOINLINE leakySlotValue #-}
leakySlotValue :: Int
leakySlotValue =
  error
    "leakySlotValue should not be forced; the spec only inspects \
    \the RegFile spine for thunk presence"

spec :: Spec
spec = describe "NoThunks instances" $ do
  it "RNil contains no thunks" $ do
    result <- noThunks [] RNil
    isNothing result `shouldBe` True

  it "reconstitute on the canonical UserRegistration log returns thunk-free state" $ do
    -- Bang-bind the (state, regs) tuple to mirror the realistic
    -- embedder pattern: after each 'step' the application forces the
    -- result before observing it. Without this, 'noThunks' would
    -- correctly report the *outer* tuple-projection thunk and never
    -- reach the RegFile spine — that is a binding artefact, not a
    -- leak in the state itself.
    case reconstitute userReg canonicalLog of
      Nothing -> expectationFailure "reconstitute returned Nothing"
      Just (!s, !regs) -> do
        sResult <- noThunks ["vertex"] s
        regsResult <- noThunks ["regfile"] regs
        case regsResult of
          Nothing -> pure ()
          Just ti -> expectationFailure $ "regfile thunk: " <> show ti
        case sResult of
          Nothing -> pure ()
          Just ti -> expectationFailure $ "vertex thunk: " <> show ti

  it "a deliberately-lazy RegFile reports a thunk (sanity check)" $ do
    let leaky :: RegFile '[ '("x", Int)]
        leaky = RCons (Proxy @"x") leakySlotValue RNil
    result <- noThunks ["leaky"] leaky
    case result of
      Just _ -> pure ()
      Nothing ->
        expectationFailure
          "expected NoThunks to detect the unevaluated leakySlotValue thunk"
