module Main (main) where

import Test.Hspec
import qualified Keiki.AcceptorSpec
import qualified Keiki.BuilderSpike
import qualified Keiki.CompositionSpec
import qualified Keiki.CoreSpec
import qualified Keiki.DeciderSpec
import qualified Keiki.Generics.THSpec
import qualified Keiki.SymbolicSpec
import qualified Keiki.Examples.EmailDeliveryBuilderSpec
import qualified Keiki.Examples.EmailDeliveryViewSpec
import qualified Keiki.Examples.UserRegistrationSpec
import qualified Keiki.Examples.UserRegistrationSymbolicSpec
import qualified Keiki.Examples.UserRegistrationV0Spec
import qualified Keiki.Examples.UserRegistrationViewSpec

main :: IO ()
main = hspec $ do
  describe "Keiki.Acceptor"                               Keiki.AcceptorSpec.spec
  describe "Keiki.BuilderSpike (EP-15 M2)"                Keiki.BuilderSpike.spec
  describe "Keiki.Composition"                            Keiki.CompositionSpec.spec
  describe "Keiki.Core"                                   Keiki.CoreSpec.spec
  describe "Keiki.Decider"                                Keiki.DeciderSpec.spec
  describe "Keiki.Generics.TH"                            Keiki.Generics.THSpec.spec
  describe "Keiki.Symbolic"                               Keiki.SymbolicSpec.spec
  describe "Keiki.Examples.EmailDelivery (builder)"       Keiki.Examples.EmailDeliveryBuilderSpec.spec
  describe "Keiki.Examples.EmailDelivery (view)"          Keiki.Examples.EmailDeliveryViewSpec.spec
  describe "Keiki.Examples.UserRegistration"              Keiki.Examples.UserRegistrationSpec.spec
  describe "Keiki.Examples.UserRegistration (symbolic)"   Keiki.Examples.UserRegistrationSymbolicSpec.spec
  describe "Keiki.Examples.UserRegistration (view)"       Keiki.Examples.UserRegistrationViewSpec.spec
  describe "Keiki.Examples.UserRegistrationV0"            Keiki.Examples.UserRegistrationV0Spec.spec
