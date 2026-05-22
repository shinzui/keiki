module Main (main) where

import Test.Hspec
import qualified Keiki.AcceptorSpec
import qualified Keiki.ArrowSpec
import qualified Keiki.BuilderSpec
import qualified Keiki.BuilderSpike
import qualified Keiki.CategorySpec
import qualified Keiki.ChoiceSpec
import qualified Keiki.CompositionSpec
import qualified Keiki.CompositionAlternativeSpec
import qualified Keiki.CompositionFeedback1Spec
import qualified Keiki.CompositionMultiEventSpec
import qualified Keiki.CompositionNarySpec
import qualified Keiki.CoreApplyEventsSpec
import qualified Keiki.CoreHiddenInputsGSMSpec
import qualified Keiki.CoreInFlightSpec
import qualified Keiki.CoreSpec
import qualified Keiki.DeciderSpec
import qualified Keiki.Generics.THSpec
import qualified Keiki.NoThunksSpec
import qualified Keiki.OperatorsSpec
import qualified Keiki.ProfunctorSpec
import qualified Keiki.RecomputeVerifySpec
import qualified Keiki.Render.MermaidSpec
import qualified Keiki.ShapeSpec
import qualified Keiki.StrongSpec
import qualified Keiki.SymbolicSpec

main :: IO ()
main = hspec $ do
  describe "Keiki.Acceptor"                               Keiki.AcceptorSpec.spec
  describe "Keiki.Builder (EP-15 M6)"                     Keiki.BuilderSpec.spec
  describe "Keiki.BuilderSpike (EP-15 M2)"                Keiki.BuilderSpike.spec
  describe "Keiki.Profunctor (Category, EP-28)"           Keiki.CategorySpec.spec
  describe "Keiki.Profunctor (Choice, EP-29 M1)"          Keiki.ChoiceSpec.spec
  describe "Keiki.Composition"                            Keiki.CompositionSpec.spec
  describe "Keiki.Composition (alternative, EP-25)"       Keiki.CompositionAlternativeSpec.spec
  describe "Keiki.Composition (feedback1, EP-26)"         Keiki.CompositionFeedback1Spec.spec
  describe "Keiki.Composition (multi-event, EP-19 M6)"    Keiki.CompositionMultiEventSpec.spec
  describe "Keiki.Composition (N-ary codec, EP-48)"       Keiki.CompositionNarySpec.spec
  describe "Keiki.Core"                                   Keiki.CoreSpec.spec
  describe "Keiki.Core.applyEvents (EP-20 M2)"            Keiki.CoreApplyEventsSpec.spec
  describe "Keiki.Core.InFlight / streaming (EP-19 M3)"   Keiki.CoreInFlightSpec.spec
  describe "Keiki.Core.checkHiddenInputs (EP-19 M4 union)" Keiki.CoreHiddenInputsGSMSpec.spec
  describe "Keiki.Decider"                                Keiki.DeciderSpec.spec
  describe "Keiki.Generics.TH"                            Keiki.Generics.THSpec.spec
  describe "Keiki.NoThunks"                               Keiki.NoThunksSpec.spec
  describe "Keiki.Core operators (EP-45)"                 Keiki.OperatorsSpec.spec
  describe "Keiki.Profunctor (EP-27)"                     Keiki.ProfunctorSpec.spec
  describe "Keiki.Profunctor (Strong, EP-29 M2)"          Keiki.StrongSpec.spec
  describe "Keiki.Profunctor (Arrow, EP-29 M3)"           Keiki.ArrowSpec.spec
  describe "Keiki.RecomputeVerify (EP-47)"                Keiki.RecomputeVerifySpec.spec
  describe "Keiki.Render.Mermaid (EP-30, EP-31, EP-32, EP-33)" Keiki.Render.MermaidSpec.spec
  describe "Keiki.Shape (EP-36 M1)"                       Keiki.ShapeSpec.spec
  describe "Keiki.Symbolic"                               Keiki.SymbolicSpec.spec
