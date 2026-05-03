module Keiki.CoreApplyEventsSpec (spec) where

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec
import Keiki.Core (applyEvents, initial, initialRegs, (!))
import Keiki.Fixtures.UserRegistration


-- | A trivial UTC-time fixture matching 'UserRegistrationSpec's
-- convention: every test moment is on the same day, offset by N
-- seconds.
t :: Integer -> UTCTime
t s = UTCTime (fromGregorian 2026 5 1) (secondsToDiffTime s)


-- | The synthesis §4 canonical event log, identical to the one
-- exercised by 'Keiki.Fixtures.UserRegistrationSpec'. Reproduced
-- here so the spec is self-contained.
canonicalLog :: [UserEvent]
canonicalLog =
  [ RegistrationStarted   (RegistrationStartedData   "alice@x" "Z9F4" (t 0))
  , ConfirmationEmailSent (ConfirmationEmailSentData "alice@x")
  , ConfirmationResent    (ConfirmationResentData    "alice@x" "K2P7" (t 100))
  , AccountConfirmed      (AccountConfirmedData      "alice@x" "K2P7" (t 200))
  , AccountDeleted        (AccountDeletedData        "alice@x"        (t 300))
  ]


-- | The two events that 'StartRegistration' produces under state
-- refinement: the public emission and the synthetic 'Continue'-driven
-- emission. Together they take @PotentialCustomer@ to
-- @RequiresConfirmation@ via the intermediate @Registering@.
multiEventChunk :: [UserEvent]
multiEventChunk =
  [ RegistrationStarted   (RegistrationStartedData   "alice@x" "Z9F4" (t 0))
  , ConfirmationEmailSent (ConfirmationEmailSentData "alice@x")
  ]


spec :: Spec
spec = do
  describe "applyEvents folds applyEvent over a chunk" $ do
    it "round-trips the canonical 5-event log from the initial state" $
      case applyEvents userReg (initial userReg, initialRegs userReg) canonicalLog of
        Just (s, regs) ->
          (s, regs ! #email, regs ! #confirmCode) `shouldBe`
            (Deleted, "alice@x", "K2P7")
        Nothing -> expectationFailure "applyEvents returned Nothing"

    it "replays a 2-event chunk for one logical command from PotentialCustomer" $
      -- StartRegistration's two events: RegistrationStarted +
      -- ConfirmationEmailSent. Under state refinement the chunk passes
      -- through Registering and lands at RequiresConfirmation with the
      -- command's register writes applied.
      case applyEvents userReg (PotentialCustomer, emptyRegs) multiEventChunk of
        Just (s, regs) -> do
          s `shouldBe` RequiresConfirmation
          (regs ! #email, regs ! #confirmCode, regs ! #registeredAt)
            `shouldBe` ("alice@x", "Z9F4", t 0)
        Nothing -> expectationFailure "applyEvents returned Nothing"

    it "returns Nothing for an out-of-order event sequence" $
      -- ConfirmationEmailSent is not the prefix of any active edge's
      -- output at PotentialCustomer (the only outgoing letter edge
      -- emits RegistrationStarted). The fold short-circuits to
      -- Nothing. We pattern-match manually because 'RegFile
      -- UserRegRegs' has no 'Show' instance, so 'shouldBe' /
      -- 'shouldSatisfy' on the raw 'Maybe' do not type-check.
      case applyEvents userReg (PotentialCustomer, emptyRegs)
             [ConfirmationEmailSent (ConfirmationEmailSentData "alice@x")] of
        Nothing -> pure ()
        Just _  ->
          expectationFailure
            "applyEvents accepted an out-of-order event"
