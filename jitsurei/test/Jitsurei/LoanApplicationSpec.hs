-- | Pure-core round-trip tests for the LoanApplication aggregate
-- (EP-34 M2). The canonical happy-path event log walks the
-- application from 'Intake' through the document-collection phase to
-- the end of evidence collection — a six-event prefix. Replay does
-- *not* fire silent ε-edges (output 'Nothing'), so the silent
-- @CollectingDocuments -> UnderReview@ transition (and the
-- subsequent 'ApplicationApproved' produced by 'Continue' from
-- 'UnderReview') cannot be reconstituted from a public event log
-- alone. Those steps are tested with 'delta' directly below.
module Jitsurei.LoanApplicationSpec (spec) where

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Jitsurei.LoanApplication
import Keiki.Core
import Test.Hspec

t :: Integer -> UTCTime
t s = UTCTime (fromGregorian 2026 5 3) (secondsToDiffTime s)

-- | The canonical six-event evidence-collection log. After replay
-- the aggregate sits in 'CollectingDocuments' with all four
-- thresholds satisfied, ready for the silent
-- 'inCtorContinue'-triggered advance to 'UnderReview'.
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
  describe "reconstitute over the canonical evidence-collection log" $ do
    it "lands at CollectingDocuments" $
      case reconstitute loanApplication canonicalEvidenceLog of
        Just (s, _) -> s `shouldBe` CollectingDocuments
        Nothing -> expectationFailure "reconstitute returned Nothing"

    it "lands with the expected register snapshot" $
      case reconstitute loanApplication canonicalEvidenceLog of
        Just (CollectingDocuments, regs) -> do
          regs ! #appApplicantId `shouldBe` "alice"
          regs ! #appRequestedAmount `shouldBe` 250_000
          regs ! #appPurpose `shouldBe` "home"
          regs ! #appIncomeDocCount `shouldBe` 2
          regs ! #appIdDocCount `shouldBe` 1
          regs ! #appCreditScore `shouldBe` 720
          regs ! #appEmploymentVerified `shouldBe` True
        _ -> expectationFailure "reconstitute did not land at CollectingDocuments"

    it "every prefix returns Just" $ do
      let prefixes =
            [take n canonicalEvidenceLog | n <- [0 .. length canonicalEvidenceLog]]
      mapM_
        ( \p -> case reconstitute loanApplication p of
            Just _ -> pure ()
            Nothing ->
              expectationFailure
                ( "prefix "
                    ++ show (length p)
                    ++ " returned Nothing"
                )
        )
        prefixes

  describe "Continue-driven advance from CollectingDocuments" $ do
    it "delta with Continue at the threshold-met regs reaches UnderReview" $
      case reconstitute loanApplication canonicalEvidenceLog of
        Just (CollectingDocuments, regs) ->
          case delta loanApplication CollectingDocuments regs Continue of
            Just (s, _) -> s `shouldBe` UnderReview
            Nothing ->
              expectationFailure "delta with Continue returned Nothing"
        _ -> expectationFailure "evidence log did not land at CollectingDocuments"

    it "step with Continue produces no event (the process-control ε-edge)" $
      case reconstitute loanApplication canonicalEvidenceLog of
        Just (CollectingDocuments, regs) ->
          case step loanApplication (CollectingDocuments, regs) Continue of
            Just (s, _, emitted) -> do
              s `shouldBe` UnderReview
              emitted `shouldBe` []
            Nothing ->
              expectationFailure "step with Continue returned Nothing"
        _ -> expectationFailure "evidence log did not land at CollectingDocuments"

  describe "Continue-driven approval from UnderReview" $ do
    it "delta with Continue at threshold-met regs reaches Approved" $
      case reconstitute loanApplication canonicalEvidenceLog of
        Just (CollectingDocuments, regs) ->
          case delta loanApplication CollectingDocuments regs Continue of
            Just (UnderReview, regs') ->
              case delta loanApplication UnderReview regs' Continue of
                Just (s, _) -> s `shouldBe` Approved
                Nothing ->
                  expectationFailure
                    "second Continue at UnderReview returned Nothing"
            _ ->
              expectationFailure "first Continue did not reach UnderReview"
        _ -> expectationFailure "evidence log did not land at CollectingDocuments"

    it "step at UnderReview emits the ApplicationApproved event" $
      case reconstitute loanApplication canonicalEvidenceLog of
        Just (CollectingDocuments, regs) ->
          case delta loanApplication CollectingDocuments regs Continue of
            Just (UnderReview, regs') ->
              case step loanApplication (UnderReview, regs') Continue of
                Just (Approved, _, [ApplicationApproved a]) -> do
                  a.applicantId `shouldBe` "alice"
                  a.requestedAmount `shouldBe` 250_000
                  a.creditScore `shouldBe` 720
                Just _ -> expectationFailure "unexpected event payload"
                Nothing -> expectationFailure "step at UnderReview returned Nothing"
            _ -> expectationFailure "first Continue did not reach UnderReview"
        _ -> expectationFailure "evidence log did not land at CollectingDocuments"

  describe "decline path from UnderReview" $
    it "Continue with a sub-threshold credit score lands at Declined" $ do
      let lowScoreLog =
            [ ApplicationStarted (ApplicationStartedData "bob" 50_000 "car" (t 0)),
              IncomeDocumentReceived (IncomeDocumentReceivedData "i1" (t 10)),
              IncomeDocumentReceived (IncomeDocumentReceivedData "i2" (t 20)),
              IdDocumentReceived (IdDocumentReceivedData "id1" (t 30)),
              CreditScoreRecorded (CreditScoreRecordedData 400 (t 40)),
              EmploymentChecked (EmploymentCheckedData True (t 50))
            ]
      case reconstitute loanApplication lowScoreLog of
        Just (CollectingDocuments, regs) ->
          case delta loanApplication CollectingDocuments regs Continue of
            Just (UnderReview, regs') ->
              case delta loanApplication UnderReview regs' Continue of
                Just (s, _) -> s `shouldBe` Declined
                Nothing ->
                  expectationFailure
                    "Continue at UnderReview returned Nothing"
            _ -> expectationFailure "first Continue did not reach UnderReview"
        _ -> expectationFailure "evidence log did not land at CollectingDocuments"

  describe "withdrawal" $
    it "WithdrawApplication on Intake reaches Withdrawn" $ do
      let log' =
            [ ApplicationWithdrawn
                (ApplicationWithdrawnData "" "user changed mind" (t 0))
            ]
      case reconstitute loanApplication log' of
        Just (s, _) -> s `shouldBe` Withdrawn
        Nothing -> expectationFailure "withdraw replay returned Nothing"
