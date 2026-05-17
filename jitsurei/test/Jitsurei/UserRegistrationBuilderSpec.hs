-- | EP-15 M5: cross-form equivalence test for User Registration.
-- Asserts that the builder-form 'userReg' and the AST-form
-- 'userRegAST' produce identical reconstitute / per-step state on
-- the synthesis-§4 canonical event log.
module Jitsurei.UserRegistrationBuilderSpec (spec) where

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec
import Keiki.Core
import Jitsurei.UserRegistration


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


-- | The canonical event log from 'Jitsurei.UserRegistrationSpec'.
-- Reproduced inline so the two specs stay decoupled (the existing
-- spec's test expectations exercise the *builder* form by name; this
-- spec's expectations are about *agreement* between the two forms).
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
  describe "EP-15 M5: builder vs AST agreement on the canonical event log" $ do

    it "reconstitute returns the same (state, snapshot) for both forms" $ do
      let astResult     = reconstitute userRegAST canonicalLog
          builtResult   = reconstitute userReg    canonicalLog
      case (astResult, builtResult) of
        (Just (sA, regsA), Just (sB, regsB)) -> do
          sA `shouldBe` sB
          snapshot regsA `shouldBe` snapshot regsB
        (a, b) ->
          expectationFailure ("reconstitute results differ: "
                             <> show (fmap fst a) <> " vs " <> show (fmap fst b))

    it "isFinal predicate matches across all five vertices" $ do
      let vs = [PotentialCustomer, RequiresConfirmation, Confirmed, Deleted]
      [ isFinal userRegAST v | v <- vs ] `shouldBe` [ isFinal userReg v | v <- vs ]

    it "edge counts per vertex match between forms" $ do
      let vs = [PotentialCustomer, RequiresConfirmation, Confirmed, Deleted]
      [ length (edgesOut userRegAST v) | v <- vs ]
        `shouldBe` [ length (edgesOut userReg v) | v <- vs ]

  describe "EP-15 M5: per-step delta/omega agreement" $ do

    it "step 1 (PotentialCustomer + RegistrationStarted) — both forms agree" $ do
      stepAgreement PotentialCustomer emptyRegs (head canonicalLog)

    it "applyEvents on the 2-event entrance chunk — both forms agree on landing vertex" $ do
      -- EP-19 M7: the entrance is now a single length-2 multi-event
      -- edge. Streaming/chunked replay handles both events
      -- atomically; the result vertex must agree between forms.
      -- Snapshot equality is exercised by the end-to-end
      -- 'reconstitute' agreement test above (all slots are set by
      -- the canonical log's end).
      let chunk = take 2 canonicalLog
          astR  = applyEvents userRegAST (PotentialCustomer, emptyRegs) chunk
          bldR  = applyEvents userReg    (PotentialCustomer, emptyRegs) chunk
      fmap fst astR `shouldBe` fmap fst bldR

    it "step 3 (RequiresConfirmation + ConfirmationResent) — both forms agree" $ do
      let log' = take 2 canonicalLog
      Just (s2, r2) <- pure (foldlReplay userRegAST (PotentialCustomer, emptyRegs) log')
      stepAgreement s2 r2 (canonicalLog !! 2)

    it "step 4 (RequiresConfirmation + AccountConfirmed) — both forms agree" $ do
      let log' = take 3 canonicalLog
      Just (s3, r3) <- pure (foldlReplay userRegAST (PotentialCustomer, emptyRegs) log')
      stepAgreement s3 r3 (canonicalLog !! 3)

    it "step 5 (Confirmed + AccountDeleted) — both forms agree" $ do
      let log' = take 4 canonicalLog
      Just (s4, r4) <- pure (foldlReplay userRegAST (PotentialCustomer, emptyRegs) log')
      stepAgreement s4 r4 (canonicalLog !! 4)


-- | Helper: assert that applying one event from state @(s, regs)@
-- produces identical post-state vertices in both forms. The per-step
-- snapshot is *not* compared because intermediate states may have
-- uninitialised register slots (each unset slot is bound to a
-- deferred 'error' by 'emptyRegFile'); reading them would crash. The
-- end-to-end equivalence check above ('reconstitute') compares the
-- full snapshot once every slot is set.
stepAgreement :: Vertex -> RegFile UserRegRegs -> UserEvent -> Expectation
stepAgreement s regs ev = do
  let astStep   = applyEvent userRegAST s regs ev
      builtStep = applyEvent userReg    s regs ev
  fmap fst astStep `shouldBe` fmap fst builtStep


-- | Replay a single event against the AST form, used to set up the
-- pre-state for a per-step test. Mirrors how
-- 'Jitsurei.UserRegistrationSpec' walks the log.
replayOne :: SymTransducer (HsPred UserRegRegs UserCmd) UserRegRegs Vertex
                           UserCmd UserEvent
          -> Vertex -> RegFile UserRegRegs -> UserEvent
          -> Maybe (Vertex, RegFile UserRegRegs)
replayOne = applyEvent


-- | Chunked replay of a partial event list. EP-19 M7: the entrance
-- to UserRegistration is now a length-2 multi-event edge, so the
-- letter-only 'applyEvent' fold no longer walks the canonical log
-- correctly. 'applyEvents' threads the streaming InFlight wrapper
-- through the multi-event edge invisibly.
foldlReplay :: SymTransducer (HsPred UserRegRegs UserCmd) UserRegRegs Vertex
                             UserCmd UserEvent
            -> (Vertex, RegFile UserRegRegs) -> [UserEvent]
            -> Maybe (Vertex, RegFile UserRegRegs)
foldlReplay = applyEvents
