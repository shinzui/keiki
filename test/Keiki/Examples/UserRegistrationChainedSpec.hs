-- | EP-20 M5: cross-form equivalence test for the chainTo-based
-- builder form of UserRegistration. Mirrors
-- 'Keiki.Examples.UserRegistrationBuilderSpec' but compares
-- @userReg@ (the canonical builder form with two explicit @from@
-- blocks) against @userRegChained@ (the same transducer authored
-- with 'Keiki.Builder.chainTo' between two @emit@ calls in a
-- single @onCmd@ body).
module Keiki.Examples.UserRegistrationChainedSpec (spec) where

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec
import Keiki.Core
import Keiki.Examples.UserRegistration


-- | Five-tuple snapshot of the register file (no Eq instance on
-- 'RegFile' itself).
type Snapshot = (Email, ConfirmationCode, UTCTime, UTCTime, UTCTime)


snapshot :: RegFile UserRegRegs -> Snapshot
snapshot regs =
  ( regs ! #email
  , regs ! #confirmCode
  , regs ! #registeredAt
  , regs ! #confirmedAt
  , regs ! #deletedAt
  )


t :: Integer -> UTCTime
t s = UTCTime (fromGregorian 2026 5 1) (secondsToDiffTime s)


canonicalLog :: [UserEvent]
canonicalLog =
  [ RegistrationStarted   (RegistrationStartedData   "alice@x" "Z9F4" (t 0))
  , ConfirmationEmailSent (ConfirmationEmailSentData "alice@x")
  , ConfirmationResent    (ConfirmationResentData    "alice@x" "K2P7" (t 100))
  , AccountConfirmed      (AccountConfirmedData      "alice@x" "K2P7" (t 200))
  , AccountDeleted        (AccountDeletedData        "alice@x"        (t 300))
  ]


spec :: Spec
spec = do
  describe "EP-20 M5: chainTo form vs. two-from form on the canonical log" $ do

    it "reconstitute returns the same (state, snapshot) for both forms" $ do
      let chainedResult = reconstitute userRegChained canonicalLog
          builtResult   = reconstitute userReg        canonicalLog
      case (chainedResult, builtResult) of
        (Just (sC, regsC), Just (sB, regsB)) -> do
          sC `shouldBe` sB
          snapshot regsC `shouldBe` snapshot regsB
        (a, b) ->
          expectationFailure ("reconstitute results differ: "
                             <> show (fmap fst a) <> " vs " <> show (fmap fst b))

    it "isFinal predicate matches across all five vertices" $ do
      let vs = [PotentialCustomer, Registering, RequiresConfirmation, Confirmed, Deleted]
      [ isFinal userRegChained v | v <- vs ]
        `shouldBe` [ isFinal userReg v | v <- vs ]

    it "edge counts per vertex match between forms" $ do
      let vs = [PotentialCustomer, Registering, RequiresConfirmation, Confirmed, Deleted]
      [ length (edgesOut userRegChained v) | v <- vs ]
        `shouldBe` [ length (edgesOut userReg v) | v <- vs ]

  describe "EP-20 M5: per-step delta/omega agreement" $ do

    it "step 1 (PotentialCustomer + RegistrationStarted) — both forms agree" $
      stepAgreement PotentialCustomer emptyRegs (head canonicalLog)

    it "step 2 (Registering + ConfirmationEmailSent) — both forms agree" $ do
      Just (s1, r1) <- pure (applyEvent userReg PotentialCustomer emptyRegs (head canonicalLog))
      stepAgreement s1 r1 (canonicalLog !! 1)

    it "step 3 (RequiresConfirmation + ConfirmationResent) — both forms agree" $ do
      Just (s2, r2) <- pure (foldlReplay userReg (PotentialCustomer, emptyRegs) (take 2 canonicalLog))
      stepAgreement s2 r2 (canonicalLog !! 2)

    it "step 4 (RequiresConfirmation + AccountConfirmed) — both forms agree" $ do
      Just (s3, r3) <- pure (foldlReplay userReg (PotentialCustomer, emptyRegs) (take 3 canonicalLog))
      stepAgreement s3 r3 (canonicalLog !! 3)

    it "step 5 (Confirmed + AccountDeleted) — both forms agree" $ do
      Just (s4, r4) <- pure (foldlReplay userReg (PotentialCustomer, emptyRegs) (take 4 canonicalLog))
      stepAgreement s4 r4 (canonicalLog !! 4)


-- | Helper: assert that applying one event from state @(s, regs)@
-- produces identical post-state vertices in both forms.
stepAgreement :: Vertex -> RegFile UserRegRegs -> UserEvent -> Expectation
stepAgreement s regs ev = do
  let chainedStep = applyEvent userRegChained s regs ev
      builtStep   = applyEvent userReg        s regs ev
  fmap fst chainedStep `shouldBe` fmap fst builtStep


foldlReplay :: SymTransducer (HsPred UserRegRegs UserCmd) UserRegRegs Vertex
                             UserCmd UserEvent
            -> (Vertex, RegFile UserRegRegs) -> [UserEvent]
            -> Maybe (Vertex, RegFile UserRegRegs)
foldlReplay _  acc        []         = Just acc
foldlReplay tr (s, regs) (ev : rest) = do
  next <- applyEvent tr s regs ev
  foldlReplay tr next rest
