module Main (main) where

import Keiki.AcceptorSpec qualified
import Keiki.ArrowSpec qualified
import Keiki.BuilderSpec qualified
import Keiki.BuilderSpike qualified
import Keiki.CategorySpec qualified
import Keiki.ChoiceSpec qualified
import Keiki.CollectionSpike qualified
import Keiki.CompositionAlternativeSpec qualified
import Keiki.CompositionFeedback1Spec qualified
import Keiki.CompositionMultiEventSpec qualified
import Keiki.CompositionNarySpec qualified
import Keiki.CompositionSpec qualified
import Keiki.CoreApplyEventsSpec qualified
import Keiki.CoreHiddenInputsGSMSpec qualified
import Keiki.CoreInFlightSpec qualified
import Keiki.CoreSpec qualified
import Keiki.DeciderSpec qualified
import Keiki.Generics.THSpec qualified
import Keiki.NoThunksSpec qualified
import Keiki.OperatorsQualifiedSpec qualified
import Keiki.OperatorsSpec qualified
import Keiki.ProfunctorSpec qualified
import Keiki.RecomputeVerifySpec qualified
import Keiki.Render.InspectorSpec qualified
import Keiki.Render.MarkdownSpec qualified
import Keiki.Render.MermaidSpec qualified
import Keiki.Render.PrettySpec qualified
import Keiki.Render.ValidateSpec qualified
import Keiki.ShapeSpec qualified
import Keiki.StepEitherSpec qualified
import Keiki.StrongSpec qualified
import Keiki.SymbolicSpec qualified
import Keiki.ValidationSpec qualified
import Test.Hspec

main :: IO ()
main = hspec $ do
    describe "Keiki.Acceptor" Keiki.AcceptorSpec.spec
    describe "Keiki.Builder (EP-15 M6)" Keiki.BuilderSpec.spec
    describe "Keiki.BuilderSpike (EP-15 M2)" Keiki.BuilderSpike.spec
    describe "Keiki.Profunctor (Category, EP-28)" Keiki.CategorySpec.spec
    describe "Keiki.Profunctor (Choice, EP-29 M1)" Keiki.ChoiceSpec.spec
    describe "Keiki.Composition" Keiki.CompositionSpec.spec
    describe "Keiki.Composition (alternative, EP-25)" Keiki.CompositionAlternativeSpec.spec
    describe "Keiki.Composition (feedback1, EP-26)" Keiki.CompositionFeedback1Spec.spec
    describe "Keiki.Composition (multi-event, EP-19 M6)" Keiki.CompositionMultiEventSpec.spec
    describe "Keiki.Composition (N-ary codec, EP-48)" Keiki.CompositionNarySpec.spec
    describe "Keiki.Core" Keiki.CoreSpec.spec
    describe "Keiki.Core.stepEither (EP-55)" Keiki.StepEitherSpec.spec
    describe "Keiki.Core.applyEvents (EP-20 M2)" Keiki.CoreApplyEventsSpec.spec
    describe "Keiki.Core.InFlight / streaming (EP-19 M3)" Keiki.CoreInFlightSpec.spec
    describe "Keiki.Core.checkHiddenInputs (EP-19 M4 union)" Keiki.CoreHiddenInputsGSMSpec.spec
    describe "Keiki.Decider" Keiki.DeciderSpec.spec
    describe "Keiki.Generics.TH" Keiki.Generics.THSpec.spec
    describe "Keiki.NoThunks" Keiki.NoThunksSpec.spec
    describe "Keiki.Core operators (EP-45)" Keiki.OperatorsSpec.spec
    describe "Keiki.Operators (qualified import, EP-58)" Keiki.OperatorsQualifiedSpec.spec
    describe "Keiki.Profunctor (EP-27)" Keiki.ProfunctorSpec.spec
    describe "Keiki.Profunctor (Strong, EP-29 M2)" Keiki.StrongSpec.spec
    describe "Keiki.Profunctor (Arrow, EP-29 M3)" Keiki.ArrowSpec.spec
    describe "Keiki.RecomputeVerify (EP-47)" Keiki.RecomputeVerifySpec.spec
    describe "Keiki.Render.Inspector (EP-62)" Keiki.Render.InspectorSpec.spec
    describe "Keiki.Render.Markdown (EP-65)" Keiki.Render.MarkdownSpec.spec
    describe "Keiki.Render.Mermaid (EP-30, EP-31, EP-32, EP-33)" Keiki.Render.MermaidSpec.spec
    describe "Keiki.Render.Pretty (EP-61)" Keiki.Render.PrettySpec.spec
    describe "Keiki.Render.Validate (EP-66)" Keiki.Render.ValidateSpec.spec
    describe "Keiki.Shape (EP-36 M1)" Keiki.ShapeSpec.spec
    describe "Keiki.Symbolic" Keiki.SymbolicSpec.spec
    describe "Keiki.CollectionSpike (EP-60 M1 ratification gate)" Keiki.CollectionSpike.spec
    describe "Keiki.Core.validateTransducer (EP-56)" Keiki.ValidationSpec.spec
