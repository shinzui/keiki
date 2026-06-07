-- | Round-trip tests for the small downstream Loan aggregate
-- (EP-34 M4). The aggregate has only two transitions, so the spec
-- is a single happy-path replay plus a per-step sanity check.
module Jitsurei.LoanSpec (spec) where

import Jitsurei.Loan
import Keiki.Core
import Test.Hspec

canonicalLog :: [LoanEvent']
canonicalLog =
  [ LoanCreated (LoanCreatedData "loan-001" "alice" 250_000),
    LegacyLoanIdAssigned (LegacyLoanIdAssignedData "loan-001" "LEG-42")
  ]

spec :: Spec
spec = do
  describe "loan aggregate end-to-end" $ do
    it "reconstitute lands at LoanLinked with all four slots set" $
      case reconstitute loan canonicalLog of
        Just (LoanLinked, regs) -> do
          regs ! #loanLoanId `shouldBe` "loan-001"
          regs ! #loanApplicantId `shouldBe` "alice"
          regs ! #loanPrincipal `shouldBe` 250_000
          regs ! #loanLegacyLoanId `shouldBe` "LEG-42"
        _ -> expectationFailure "reconstitute did not land at LoanLinked"

    it "isFinal is True at LoanLinked, False elsewhere" $ do
      [isFinal loan v | v <- [LoanInitial, LoanAwaiting, LoanLinked]]
        `shouldBe` [False, False, True]

  describe "loan replay rejects an AssignLegacyLoanId on a different loanId" $
    it "delta with a mismatched loanId returns Nothing" $ do
      case reconstitute loan (take 1 canonicalLog) of
        Just (LoanAwaiting, regs) -> do
          let mismatched =
                AssignLegacyLoanId
                  (AssignLegacyLoanIdData "loan-OTHER" "LEG-X")
          fmap fst (delta loan LoanAwaiting regs mismatched)
            `shouldBe` Nothing
        _ -> expectationFailure "first event did not land at LoanAwaiting"
