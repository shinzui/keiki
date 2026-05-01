module Keiki.Examples.UserRegistrationSpec (spec) where

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec
import Keiki.Core
import Keiki.Examples.UserRegistration


-- | Extract every register slot of 'UserRegRegs' as a tuple, since
-- 'RegFile' does not have an 'Eq' instance. Tuples are easy to
-- compare in tests.
type Snapshot = (Email, ConfirmationCode, UTCTime, UTCTime, UTCTime)


snapshot :: RegFile UserRegRegs -> Snapshot
snapshot regs =
  ( regs ! #email
  , regs ! #confirmCode
  , regs ! #registeredAt
  , regs ! #confirmedAt
  , regs ! #deletedAt
  )


-- | A trivial UTC-time fixture: every test moment is on the same day,
-- offset by N seconds. Concrete dates do not matter for replay
-- correctness.
t :: Integer -> UTCTime
t s = UTCTime (fromGregorian 2026 5 1) (secondsToDiffTime s)


-- | The synthesis §4 canonical event log, with the fix-1 schema:
-- 'AccountConfirmed' carries @confirmCode@.
canonicalLog :: [UserEvent]
canonicalLog =
  [ RegistrationStarted   (RegistrationStartedData   "alice@x" "Z9F4" (t 0))
  , ConfirmationEmailSent (ConfirmationEmailSentData "alice@x")
  , ConfirmationResent    (ConfirmationResentData    "alice@x" "K2P7" (t 100))
  , AccountConfirmed      (AccountConfirmedData      "alice@x" "K2P7" (t 200))
  , AccountDeleted        (AccountDeletedData        "alice@x"        (t 300))
  ]


-- | Hand-computed expected snapshot at the end of replay. Walk the log:
--
--   step 1: regs <- email=alice, confirmCode=Z9F4, registeredAt=t0
--   step 2: ε on registers (Continue keeps), move to RequiresConfirmation
--   step 3: resend rotates confirmCode and registeredAt:
--           regs <- ..., confirmCode=K2P7, registeredAt=t100
--   step 4: confirm sets confirmedAt=t200
--   step 5: GDPR sets deletedAt=t300
expectedSnapshot :: Snapshot
expectedSnapshot =
  ( "alice@x"
  , "K2P7"
  , t 100   -- registeredAt rotated by the resend
  , t 200   -- confirmedAt
  , t 300   -- deletedAt
  )


spec :: Spec
spec = do
  describe "userReg end-to-end on the canonical event log (fixed schema)" $ do
    it "reconstitutes to (Deleted, expectedSnapshot)" $
      case reconstitute userReg canonicalLog of
        Just (s, regs) -> (s, snapshot regs) `shouldBe` (Deleted, expectedSnapshot)
        Nothing        -> expectationFailure "reconstitute returned Nothing"

  describe "userReg one-step-at-a-time replay" $ do
    -- Sanity-check each event in isolation. If anything breaks, the
    -- end-to-end test above fails opaquely; the per-step assertions
    -- below identify the offending step.
    it "step 1: PotentialCustomer + RegistrationStarted -> Registering" $
      case applyOne PotentialCustomer emptyRegs (head canonicalLog) of
        Just (s, _) -> s `shouldBe` Registering
        Nothing     -> expectationFailure "step 1 returned Nothing"

    it "step 5: Confirmed + AccountDeleted -> Deleted" $ do
      let regsBeforeDelete =
            -- We cheat the snapshot here by replaying the first four
            -- events; if that fails the end-to-end test would already
            -- have caught it.
            case foldlEvents (initial userReg, initialRegs userReg) (init canonicalLog) of
              Just acc -> acc
              Nothing  -> error "set-up replay failed"
      case applyOne (fst regsBeforeDelete) (snd regsBeforeDelete) (last canonicalLog) of
        Just (s, _) -> s `shouldBe` Deleted
        Nothing     -> expectationFailure "step 5 returned Nothing"
  where
    applyOne s regs co =
      reconstituteFrom (s, regs) [co]

    foldlEvents = reconstituteFrom

    -- A 'reconstitute'-from-arbitrary-state helper. The library's
    -- 'reconstitute' is rooted at 'initial t'; this uses 'go' over
    -- 'applyEvent' but with our own starting state. To keep the
    -- spec self-contained we reproduce the fold here.
    reconstituteFrom acc []         = Just acc
    reconstituteFrom (s, regs) (co : rest) = do
      next <- stepEvent s regs co
      reconstituteFrom next rest

    -- Re-implement applyEvent locally, since the library does not
    -- export its internal helper.
    stepEvent s regs co =
      case [ (target e, runUpdate (update e) regs ci)
           | e <- edgesOut userReg s
           , Just o  <- [output e]
           , Just ci <- [solveOutput o regs co]
           , models (guard e) (regs, ci)
           ] of
        [single] -> Just single
        _        -> Nothing
