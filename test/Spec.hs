module Main (main) where

import Test.Hspec
import qualified Keiki.AcceptorSpec
import qualified Keiki.BuilderSpec
import qualified Keiki.BuilderSpike
import qualified Keiki.CompositionSpec
import qualified Keiki.CompositionAlternativeSpec
import qualified Keiki.CompositionFeedback1Spec
import qualified Keiki.CoreApplyEventsSpec
import qualified Keiki.CoreSpec
import qualified Keiki.DeciderMultiSpec
import qualified Keiki.DeciderSpec
import qualified Keiki.Generics.THSpec
import qualified Keiki.NoThunksSpec
import qualified Keiki.ProfunctorSpec
import qualified Keiki.Render.MermaidSpec
import qualified Keiki.SymbolicSpec
import qualified Keiki.Examples.EmailDeliveryBuilderSpec
import qualified Keiki.Examples.EmailDeliveryViewSpec
import qualified Keiki.Examples.OrderCartBuilderSpec
import qualified Keiki.Examples.OrderCartSpec
import qualified Keiki.Examples.UserRegistrationBuilderSpec
import qualified Keiki.Examples.UserRegistrationChainedSpec
import qualified Keiki.Examples.UserRegistrationMultiSpec
import qualified Keiki.Examples.UserRegistrationSpec
import qualified Keiki.Examples.UserRegistrationSymbolicSpec
import qualified Keiki.Examples.UserRegistrationV0Spec
import qualified Keiki.Examples.UserRegistrationViewSpec

main :: IO ()
main = hspec $ do
  describe "Keiki.Acceptor"                               Keiki.AcceptorSpec.spec
  describe "Keiki.Builder (EP-15 M6)"                     Keiki.BuilderSpec.spec
  describe "Keiki.BuilderSpike (EP-15 M2)"                Keiki.BuilderSpike.spec
  describe "Keiki.Composition"                            Keiki.CompositionSpec.spec
  describe "Keiki.Composition (alternative, EP-25)"       Keiki.CompositionAlternativeSpec.spec
  describe "Keiki.Composition (feedback1, EP-26)"         Keiki.CompositionFeedback1Spec.spec
  describe "Keiki.Core"                                   Keiki.CoreSpec.spec
  describe "Keiki.Core.applyEvents (EP-20 M2)"            Keiki.CoreApplyEventsSpec.spec
  describe "Keiki.Decider"                                Keiki.DeciderSpec.spec
  describe "Keiki.Decider.toMultiDecider (EP-20 M3)"      Keiki.DeciderMultiSpec.spec
  describe "Keiki.Generics.TH"                            Keiki.Generics.THSpec.spec
  describe "Keiki.NoThunks"                               Keiki.NoThunksSpec.spec
  describe "Keiki.Profunctor (EP-27)"                     Keiki.ProfunctorSpec.spec
  describe "Keiki.Render.Mermaid (EP-30, EP-31, EP-32)"   Keiki.Render.MermaidSpec.spec
  describe "Keiki.Symbolic"                               Keiki.SymbolicSpec.spec
  describe "Keiki.Examples.EmailDelivery (builder)"       Keiki.Examples.EmailDeliveryBuilderSpec.spec
  describe "Keiki.Examples.EmailDelivery (view)"          Keiki.Examples.EmailDeliveryViewSpec.spec
  describe "Keiki.Examples.OrderCart"                     Keiki.Examples.OrderCartSpec.spec
  describe "Keiki.Examples.OrderCart (builder)"           Keiki.Examples.OrderCartBuilderSpec.spec
  describe "Keiki.Examples.UserRegistration"              Keiki.Examples.UserRegistrationSpec.spec
  describe "Keiki.Examples.UserRegistration (builder)"    Keiki.Examples.UserRegistrationBuilderSpec.spec
  describe "Keiki.Examples.UserRegistration (chained EP-20)" Keiki.Examples.UserRegistrationChainedSpec.spec
  describe "Keiki.Examples.UserRegistration (multi EP-20)" Keiki.Examples.UserRegistrationMultiSpec.spec
  describe "Keiki.Examples.UserRegistration (symbolic)"   Keiki.Examples.UserRegistrationSymbolicSpec.spec
  describe "Keiki.Examples.UserRegistration (view)"       Keiki.Examples.UserRegistrationViewSpec.spec
  describe "Keiki.Examples.UserRegistrationV0"            Keiki.Examples.UserRegistrationV0Spec.spec
