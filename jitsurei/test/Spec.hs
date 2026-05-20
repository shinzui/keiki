module Main (main) where

import Test.Hspec
import qualified Jitsurei.EmailDeliveryBuilderSpec
import qualified Jitsurei.EmailDeliveryViewSpec
import qualified Jitsurei.LoanApplicationBuilderSpec
import qualified Jitsurei.LoanApplicationSpec
import qualified Jitsurei.LoanApplicationSymbolicSpec
import qualified Jitsurei.CoreBankingSyncSpec
import qualified Jitsurei.LoanApplicationViewSpec
import qualified Jitsurei.LoanSpec
import qualified Jitsurei.LoanWorkflowSpec
import qualified Jitsurei.OrderCartBuilderSpec
import qualified Jitsurei.OrderCartSymbolicSpec
import qualified Jitsurei.Render.MermaidLoanSpec
import qualified Jitsurei.OrderCartSpec
import qualified Jitsurei.UserRegistrationBuilderSpec
import qualified Jitsurei.UserRegistrationGSMSpec
import qualified Jitsurei.UserRegistrationSpec
import qualified Jitsurei.UserRegistrationSymbolicSpec
import qualified Jitsurei.UserRegistrationV0Spec
import qualified Jitsurei.UserRegistrationViewSpec

main :: IO ()
main = hspec $ do
  describe "Jitsurei.EmailDelivery (builder)"       Jitsurei.EmailDeliveryBuilderSpec.spec
  describe "Jitsurei.EmailDelivery (view)"          Jitsurei.EmailDeliveryViewSpec.spec
  describe "Jitsurei.LoanApplication"               Jitsurei.LoanApplicationSpec.spec
  describe "Jitsurei.LoanApplication (builder)"     Jitsurei.LoanApplicationBuilderSpec.spec
  describe "Jitsurei.LoanApplication (view)"        Jitsurei.LoanApplicationViewSpec.spec
  describe "Jitsurei.LoanApplication (symbolic)"    Jitsurei.LoanApplicationSymbolicSpec.spec
  describe "Jitsurei.Loan"                          Jitsurei.LoanSpec.spec
  describe "Jitsurei.CoreBankingSync"               Jitsurei.CoreBankingSyncSpec.spec
  describe "Jitsurei.LoanWorkflow"                  Jitsurei.LoanWorkflowSpec.spec
  describe "Jitsurei.Render.MermaidLoan (EP-34 M6)" Jitsurei.Render.MermaidLoanSpec.spec
  describe "Jitsurei.OrderCart"                     Jitsurei.OrderCartSpec.spec
  describe "Jitsurei.OrderCart (builder)"           Jitsurei.OrderCartBuilderSpec.spec
  describe "Jitsurei.OrderCart (symbolic)"          Jitsurei.OrderCartSymbolicSpec.spec
  describe "Jitsurei.UserRegistration"              Jitsurei.UserRegistrationSpec.spec
  describe "Jitsurei.UserRegistration (builder)"    Jitsurei.UserRegistrationBuilderSpec.spec
  describe "Jitsurei.UserRegistration (GSM EP-19 M7)" Jitsurei.UserRegistrationGSMSpec.spec
  describe "Jitsurei.UserRegistration (symbolic)"   Jitsurei.UserRegistrationSymbolicSpec.spec
  describe "Jitsurei.UserRegistration (view)"       Jitsurei.UserRegistrationViewSpec.spec
  describe "Jitsurei.UserRegistrationV0"            Jitsurei.UserRegistrationV0Spec.spec
