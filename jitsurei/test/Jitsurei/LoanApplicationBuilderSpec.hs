-- | EP-34 M2: cross-form equivalence test for the LoanApplication
-- aggregate. Asserts that 'loanApplication' (builder form) and
-- 'loanApplicationAST' (hand-authored AST form) agree on
-- 'reconstitute' over the canonical evidence-collection log, on
-- 'isFinal' and 'edgesOut' counts at every vertex, and on the
-- silent Continue-triggered advance through 'CollectingDocuments'.
module Jitsurei.LoanApplicationBuilderSpec (spec) where

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Jitsurei.LoanApplication
import Keiki.Core
import Test.Hspec

t :: Integer -> UTCTime
t s = UTCTime (fromGregorian 2026 5 3) (secondsToDiffTime s)

canonicalEvidenceLog :: [LoanEvent]
canonicalEvidenceLog =
  [ ApplicationStarted (ApplicationStartedData "alice" 250_000 "home" (t 0)),
    IncomeDocumentReceived (IncomeDocumentReceivedData "doc-income-1" (t 10)),
    IncomeDocumentReceived (IncomeDocumentReceivedData "doc-income-2" (t 20)),
    IdDocumentReceived (IdDocumentReceivedData "doc-id-1" (t 30)),
    CreditScoreRecorded (CreditScoreRecordedData 720 (t 40)),
    EmploymentChecked (EmploymentCheckedData True (t 50))
  ]

spec :: Spec
spec = do
  describe "EP-34 M2: builder vs AST agreement on the evidence log" $ do
    it "reconstitute returns the same vertex for both forms" $ do
      let astResult = reconstitute loanApplicationAST canonicalEvidenceLog
          builtResult = reconstitute loanApplication canonicalEvidenceLog
      fmap fst astResult `shouldBe` fmap fst builtResult

    it "isFinal predicate matches across all six vertices" $ do
      let vs = [Intake, CollectingDocuments, UnderReview, Approved, Declined, Withdrawn]
      [isFinal loanApplicationAST v | v <- vs]
        `shouldBe` [isFinal loanApplication v | v <- vs]

    it "edge counts per vertex match between forms" $ do
      let vs = [Intake, CollectingDocuments, UnderReview, Approved, Declined, Withdrawn]
      [length (edgesOut loanApplicationAST v) | v <- vs]
        `shouldBe` [length (edgesOut loanApplication v) | v <- vs]

    it "every prefix lands at the same vertex in both forms" $ do
      let prefixes =
            [ take n canonicalEvidenceLog
            | n <- [0 .. length canonicalEvidenceLog]
            ]
          astStates = [fmap fst (reconstitute loanApplicationAST p) | p <- prefixes]
          builtStates = [fmap fst (reconstitute loanApplication p) | p <- prefixes]
      astStates `shouldBe` builtStates

  describe "EP-34 M2: process-control Continue advance" $ do
    it "delta with Continue at threshold-met regs lands at UnderReview in both forms" $
      case ( reconstitute loanApplicationAST canonicalEvidenceLog,
             reconstitute loanApplication canonicalEvidenceLog
           ) of
        ( Just (CollectingDocuments, regsA),
          Just (CollectingDocuments, regsB)
          ) -> do
            fmap fst (delta loanApplicationAST CollectingDocuments regsA Continue)
              `shouldBe` Just UnderReview
            fmap fst (delta loanApplication CollectingDocuments regsB Continue)
              `shouldBe` Just UnderReview
        _ -> expectationFailure "evidence log did not land at CollectingDocuments"
