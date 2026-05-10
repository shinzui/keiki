module Main (main) where

import Test.Hspec
import qualified Keiki.AcceptorSpec
import qualified Keiki.BuilderSpec
import qualified Keiki.BuilderSpike
import qualified Keiki.CategorySpec
import qualified Keiki.ChoiceSpec
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
  describe "Keiki.Core"                                   Keiki.CoreSpec.spec
  describe "Keiki.Core.applyEvents (EP-20 M2)"            Keiki.CoreApplyEventsSpec.spec
  describe "Keiki.Decider"                                Keiki.DeciderSpec.spec
  describe "Keiki.Decider.toMultiDecider (EP-20 M3)"      Keiki.DeciderMultiSpec.spec
  describe "Keiki.Generics.TH"                            Keiki.Generics.THSpec.spec
  describe "Keiki.NoThunks"                               Keiki.NoThunksSpec.spec
  describe "Keiki.Profunctor (EP-27)"                     Keiki.ProfunctorSpec.spec
  describe "Keiki.Profunctor (Strong, EP-29 M2)"          Keiki.StrongSpec.spec
  describe "Keiki.Render.Mermaid (EP-30, EP-31, EP-32, EP-33)" Keiki.Render.MermaidSpec.spec
  describe "Keiki.Symbolic"                               Keiki.SymbolicSpec.spec
