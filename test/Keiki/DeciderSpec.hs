module Keiki.DeciderSpec (spec) where

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec
import Keiki.Core
import Keiki.Decider
import Keiki.Fixtures.UserRegistration


-- | Same time fixture as 'Keiki.Fixtures.UserRegistrationSpec' so the
-- decider round-trip lands on the snapshot 'reconstitute' produces.
t :: Integer -> UTCTime
t s = UTCTime (fromGregorian 2026 5 1) (secondsToDiffTime s)


type Snapshot = (Email, ConfirmationCode, UTCTime, UTCTime, UTCTime)


snapshot :: RegFile UserRegRegs -> Snapshot
snapshot regs =
  ( regs ! #email
  , regs ! #confirmCode
  , regs ! #registeredAt
  , regs ! #confirmedAt
  , regs ! #deletedAt
  )


-- | The forward command sequence whose 'omega' trace matches
-- 'Keiki.Fixtures.UserRegistrationSpec.canonicalLog'. The reconstitute
-- spec fixes the events; this fixture records the inputs that produce
-- them on the User Registration edge graph.
canonicalCmds :: [UserCmd]
canonicalCmds =
  [ StartRegistration  (StartRegistrationData  "alice@x" "Z9F4" (t 0))
  , Continue
  , ResendConfirmation (ResendConfirmationData          "K2P7" (t 100))
  , ConfirmAccount     (ConfirmAccountData              "K2P7" (t 200))
  , FulfillGDPRRequest (FulfillGDPRRequestData                  (t 300))
  ]


-- | Hand-computed snapshot at the end of replay. Same values as
-- 'Keiki.Fixtures.UserRegistrationSpec.expectedSnapshot' so the two
-- specs validate the same end-state from opposite directions.
expectedSnapshot :: Snapshot
expectedSnapshot =
  ( "alice@x"
  , "K2P7"
  , t 100   -- registeredAt rotated by ResendConfirmation
  , t 200   -- confirmedAt
  , t 300   -- deletedAt
  )


-- | Run one decide/evolve round on the (s, regs) pair: the façade
-- emits zero or one event, and 'evolve' folds the (zero or one) event
-- back into the state.
runRound
  :: Decider UserCmd UserEvent (Vertex, RegFile UserRegRegs)
  -> (Vertex, RegFile UserRegRegs)
  -> UserCmd
  -> (Vertex, RegFile UserRegRegs)
runRound d acc cmd = foldl (evolve d) acc (decide d cmd acc)


spec :: Spec
spec = do
  describe "toDecider userReg" $ do
    it "round-trips the canonical command sequence to (Deleted, expectedSnapshot)" $ do
      let d                   = toDecider userReg
          (sFinal, regsFinal) = foldl (runRound d) (initialState d) canonicalCmds
      (sFinal, snapshot regsFinal) `shouldBe` (Deleted, expectedSnapshot)

    it "isTerminal d reports True after the canonical sequence" $ do
      let d   = toDecider userReg
          end = foldl (runRound d) (initialState d) canonicalCmds
      isTerminal d end `shouldBe` True

    it "decide on the very first command emits exactly one event" $ do
      let d   = toDecider userReg
          evs = decide d (head canonicalCmds) (initialState d)
      length evs `shouldBe` 1

    it "ε-edge limitation: GDPR from RequiresConfirmation yields [] from decide" $ do
      -- Drive the aggregate as far as RequiresConfirmation by replaying
      -- StartRegistration and Continue, then attempt the silent ε-edge
      -- (FulfillGDPRRequest before the user has confirmed).
      let d         = toDecider userReg
          preGdpr   = foldl (runRound d) (initialState d)
                        [ StartRegistration
                            (StartRegistrationData "bob@x" "S0E1" (t 0))
                        , Continue
                        ]
          gdprCmd   = FulfillGDPRRequest (FulfillGDPRRequestData (t 999))
          evs       = decide d gdprCmd preGdpr
          afterGdpr = foldl (evolve d) preGdpr evs
      fst preGdpr        `shouldBe` RequiresConfirmation
      evs                `shouldBe` []
      -- The ε-edge limitation: with no event, evolve is a no-op, so
      -- the façade leaves the state at RequiresConfirmation even
      -- though the keiki delta would transition to Deleted.
      fst afterGdpr      `shouldBe` RequiresConfirmation

    it "ε-edge cross-check: delta does transition the same input to Deleted" $ do
      -- Companion to the previous case: confirm that the keiki
      -- transducer itself can drive the ε-edge via 'delta'. The point
      -- is that the limitation lives at the façade boundary, not in
      -- the underlying transducer.
      let d         = toDecider userReg
          preGdpr   = foldl (runRound d) (initialState d)
                        [ StartRegistration
                            (StartRegistrationData "carol@x" "T1V2" (t 0))
                        , Continue
                        ]
          (vAtRC, regsAtRC) = preGdpr
          gdprCmd   = FulfillGDPRRequest (FulfillGDPRRequestData (t 999))
      vAtRC `shouldBe` RequiresConfirmation
      case delta userReg vAtRC regsAtRC gdprCmd of
        Just (vNext, _) -> vNext `shouldBe` Deleted
        Nothing         -> expectationFailure "delta returned Nothing"
