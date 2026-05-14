module Keiki.DeciderMultiSpec (spec) where

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec
import Keiki.Decider
  ( Decider (..)
  , DriverConfig (..)
  , toDecider
  , toMultiDecider
  )
import Keiki.Fixtures.UserRegistration


-- | A local 'DriverConfig' for 'userReg'. The canonical exported
-- value 'Keiki.Fixtures.UserRegistration.userRegDriverConfig' lands
-- in M4; this spec uses a local one so the test exercises the
-- driver API surface in isolation from the example module's edits.
userRegCfg :: DriverConfig Vertex UserCmd
userRegCfg = DriverConfig
  { isInternal = \case
      Registering -> Just Continue
      _           -> Nothing
  }


-- | Trivial UTC fixture matching the other UserRegistration specs.
t :: Integer -> UTCTime
t s = UTCTime (fromGregorian 2026 5 1) (secondsToDiffTime s)


startCmd :: UserCmd
startCmd = StartRegistration (StartRegistrationData "alice@x" "Z9F4" (t 0))


spec :: Spec
spec = do
  describe "toMultiDecider drives letter chains end-to-end" $ do
    let mdec = toMultiDecider userReg userRegCfg
        sdec = toDecider userReg

    it "decide on a multi-event command returns a 2-element list" $
      decide mdec startCmd (PotentialCustomer, emptyRegs) `shouldBe`
        [ RegistrationStarted   (RegistrationStartedData "alice@x" "Z9F4" (t 0))
        , ConfirmationEmailSent (ConfirmationEmailSentData "alice@x")
        ]

    it "underlying letter FST behavior is unchanged via toDecider" $ do
      -- Single-event lift: the public command emits exactly one event
      -- and the state lands at the intermediate Registering vertex.
      decide sdec startCmd (PotentialCustomer, emptyRegs) `shouldBe`
        [ RegistrationStarted (RegistrationStartedData "alice@x" "Z9F4" (t 0)) ]

    it "decide on a single-event command still returns a singleton" $ do
      -- Confirm the multi-decider does not over-drive past public
      -- vertices: a non-multi command from a public vertex with no
      -- internal-vertex hand-off behaves like the single-event lift.
      let resendCmd = ResendConfirmation (ResendConfirmationData "K2P7" (t 100))
          startedRegs =
            -- Walk the multi-event entrance once so we land at
            -- RequiresConfirmation with the email and codes set.
            case decide mdec startCmd (PotentialCustomer, emptyRegs) of
              [_, _] ->
                -- Ignore the events; recompute regs by stepping evolve.
                let s0 = (PotentialCustomer, emptyRegs)
                    s1 = evolve mdec s0
                           (RegistrationStarted
                             (RegistrationStartedData "alice@x" "Z9F4" (t 0)))
                in evolve mdec s1
                     (ConfirmationEmailSent
                       (ConfirmationEmailSentData "alice@x"))
              _ -> error "multi-event decode did not return 2 events"
      decide mdec resendCmd startedRegs `shouldBe`
        [ ConfirmationResent (ConfirmationResentData "alice@x" "K2P7" (t 100)) ]
