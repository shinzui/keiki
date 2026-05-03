-- | EP-34 M3: cross-form equivalence test for the chainTo-based
-- builder form of LoanApplication. Mirrors
-- 'Jitsurei.UserRegistrationChainedSpec' but compares
-- 'loanApplication' (the canonical builder form with explicit @from@
-- blocks) against 'loanApplicationChained' (the same transducer
-- with the silent CollectingDocuments → UnderReview advance moved
-- inside the StartApplication body via 'Keiki.Builder.chainTo').
module Jitsurei.LoanApplicationChainedSpec (spec) where

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

import Keiki.Core
import Jitsurei.LoanApplication


t :: Integer -> UTCTime
t s = UTCTime (fromGregorian 2026 5 3) (secondsToDiffTime s)


canonicalEvidenceLog :: [LoanEvent]
canonicalEvidenceLog =
  [ ApplicationStarted     (ApplicationStartedData     "alice" 250_000 "home" (t 0))
  , IncomeDocumentReceived (IncomeDocumentReceivedData "doc-income-1"   (t 10))
  , IncomeDocumentReceived (IncomeDocumentReceivedData "doc-income-2"   (t 20))
  , IdDocumentReceived     (IdDocumentReceivedData     "doc-id-1"       (t 30))
  , CreditScoreRecorded    (CreditScoreRecordedData    720             (t 40))
  , EmploymentChecked      (EmploymentCheckedData      True             (t 50))
  ]


spec :: Spec
spec = do
  describe "EP-34 M3: chainTo form vs explicit form on the evidence log" $ do

    it "reconstitute returns the same vertex for both forms" $ do
      let chainedResult = reconstitute loanApplicationChained canonicalEvidenceLog
          builtResult   = reconstitute loanApplication        canonicalEvidenceLog
      fmap fst chainedResult `shouldBe` fmap fst builtResult

    it "isFinal predicate matches across all six vertices" $ do
      let vs = [Intake, CollectingDocuments, UnderReview, Approved, Declined, Withdrawn]
      [ isFinal loanApplicationChained v | v <- vs ]
        `shouldBe` [ isFinal loanApplication v | v <- vs ]

    it "edge counts per vertex match between forms" $ do
      let vs = [Intake, CollectingDocuments, UnderReview, Approved, Declined, Withdrawn]
      [ length (edgesOut loanApplicationChained v) | v <- vs ]
        `shouldBe` [ length (edgesOut loanApplication v) | v <- vs ]

    it "every prefix lands at the same vertex in both forms" $ do
      let prefixes =
            [ take n canonicalEvidenceLog
            | n <- [0 .. length canonicalEvidenceLog] ]
          chainedStates = [ fmap fst (reconstitute loanApplicationChained p) | p <- prefixes ]
          builtStates   = [ fmap fst (reconstitute loanApplication        p) | p <- prefixes ]
      chainedStates `shouldBe` builtStates

  describe "EP-34 M3: silent advance reachable in both forms" $ do
    it "Continue from threshold-met regs reaches UnderReview in both forms" $
      case ( reconstitute loanApplicationChained canonicalEvidenceLog
           , reconstitute loanApplication        canonicalEvidenceLog ) of
        ( Just (CollectingDocuments, regsC)
          , Just (CollectingDocuments, regsB) ) -> do
            fmap fst (delta loanApplicationChained CollectingDocuments regsC Continue)
              `shouldBe` Just UnderReview
            fmap fst (delta loanApplication        CollectingDocuments regsB Continue)
              `shouldBe` Just UnderReview
        _ -> expectationFailure "evidence log did not land at CollectingDocuments"
