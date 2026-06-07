module Main (main) where

import Jitsurei.CoreBankingSyncSpec qualified
import Jitsurei.EmailDeliveryBuilderSpec qualified
import Jitsurei.EmailDeliveryViewSpec qualified
import Jitsurei.LoanApplicationBuilderSpec qualified
import Jitsurei.LoanApplicationSpec qualified
import Jitsurei.LoanApplicationSymbolicSpec qualified
import Jitsurei.LoanApplicationViewSpec qualified
import Jitsurei.LoanSpec qualified
import Jitsurei.LoanWorkflowSpec qualified
import Jitsurei.OrderCartBuilderSpec qualified
import Jitsurei.OrderCartSpec qualified
import Jitsurei.OrderCartSymbolicSpec qualified
import Jitsurei.Render.MermaidLoanSpec qualified
import Jitsurei.UserRegistrationBuilderSpec qualified
import Jitsurei.UserRegistrationGSMSpec qualified
import Jitsurei.UserRegistrationSpec qualified
import Jitsurei.UserRegistrationSymbolicSpec qualified
import Jitsurei.UserRegistrationV0Spec qualified
import Jitsurei.UserRegistrationViewSpec qualified
import Test.Hspec

main :: IO ()
main = hspec $ do
  describe "Jitsurei.EmailDelivery (builder)" Jitsurei.EmailDeliveryBuilderSpec.spec
  describe "Jitsurei.EmailDelivery (view)" Jitsurei.EmailDeliveryViewSpec.spec
  describe "Jitsurei.LoanApplication" Jitsurei.LoanApplicationSpec.spec
  describe "Jitsurei.LoanApplication (builder)" Jitsurei.LoanApplicationBuilderSpec.spec
  describe "Jitsurei.LoanApplication (view)" Jitsurei.LoanApplicationViewSpec.spec
  describe "Jitsurei.LoanApplication (symbolic)" Jitsurei.LoanApplicationSymbolicSpec.spec
  describe "Jitsurei.Loan" Jitsurei.LoanSpec.spec
  describe "Jitsurei.CoreBankingSync" Jitsurei.CoreBankingSyncSpec.spec
  describe "Jitsurei.LoanWorkflow" Jitsurei.LoanWorkflowSpec.spec
  describe "Jitsurei.Render.MermaidLoan (EP-34 M6)" Jitsurei.Render.MermaidLoanSpec.spec
  describe "Jitsurei.OrderCart" Jitsurei.OrderCartSpec.spec
  describe "Jitsurei.OrderCart (builder)" Jitsurei.OrderCartBuilderSpec.spec
  describe "Jitsurei.OrderCart (symbolic)" Jitsurei.OrderCartSymbolicSpec.spec
  describe "Jitsurei.UserRegistration" Jitsurei.UserRegistrationSpec.spec
  describe "Jitsurei.UserRegistration (builder)" Jitsurei.UserRegistrationBuilderSpec.spec
  describe "Jitsurei.UserRegistration (GSM EP-19 M7)" Jitsurei.UserRegistrationGSMSpec.spec
  describe "Jitsurei.UserRegistration (symbolic)" Jitsurei.UserRegistrationSymbolicSpec.spec
  describe "Jitsurei.UserRegistration (view)" Jitsurei.UserRegistrationViewSpec.spec
  describe "Jitsurei.UserRegistrationV0" Jitsurei.UserRegistrationV0Spec.spec
