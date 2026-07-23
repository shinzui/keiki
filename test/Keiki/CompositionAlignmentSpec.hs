module Keiki.CompositionAlignmentSpec (spec) where

import Data.Proxy (Proxy (..))
import Keiki.Composition
import Keiki.Core
import Keiki.Fixtures.ComposeStateful
import Keiki.Fixtures.CounterPipeline
import Keiki.Profunctor (rmapCo)
import Test.Hspec

type Payload1 = '[ '("payload", Int)]

type Payload2 = '[ '("first", Int), '("second", Int)]

typoInMsgB :: InCtor MsgB Payload1
typoInMsgB =
  InCtor
    { icName = "MsgTypo",
      icMatch = \(MsgB n) -> Just (RCons (Proxy @"payload") n RNil),
      icBuild = \(RCons _ n RNil) -> MsgB n
    }

twoFieldInMsgB :: InCtor MsgB Payload2
twoFieldInMsgB =
  InCtor
    { icName = "MsgB",
      icMatch = \(MsgB n) ->
        Just
          ( RCons
              (Proxy @"first")
              n
              (RCons (Proxy @"second") n RNil)
          ),
      icBuild = \(RCons _ n (RCons _ _ RNil)) -> MsgB n
    }

misnamedStageB :: SymTransducer (HsPred BRegs MsgB) BRegs StageVertex MsgB MsgC
misnamedStageB =
  SymTransducer
    { edgesOut = \StageVertex ->
        [ Edge
            { guard = PInCtor typoInMsgB,
              update = UKeep,
              output = [],
              target = StageVertex,
              mode = Live
            }
        ],
      initial = StageVertex,
      initialRegs = RCons (Proxy @"regB") 0 RNil,
      isFinal = const True
    }

arityStageB :: SymTransducer (HsPred BRegs MsgB) BRegs StageVertex MsgB MsgC
arityStageB =
  SymTransducer
    { edgesOut = \StageVertex ->
        [ Edge
            { guard =
                PAnd
                  (PInCtor twoFieldInMsgB)
                  ( PEq
                      (TInpCtorField twoFieldInMsgB (SIdx ZIdx))
                      (TLit (0 :: Int))
                  ),
              update = UKeep,
              output = [],
              target = StageVertex,
              mode = Live
            }
        ],
      initial = StageVertex,
      initialRegs = RCons (Proxy @"regB") 0 RNil,
      isFinal = const True
    }

spec :: Spec
spec = do
  describe "checkComposeAlignment" $ do
    it "accepts aligned fixture pairs and composeChecked builds them" $ do
      checkComposeAlignment stageA stageB `shouldBe` []
      checkComposeAlignment stageB stageC `shouldBe` []
      checkComposeAlignment counterSource lastValueSink `shouldBe` []
      checkComposeAlignment pairSource twoPhaseSink `shouldBe` []
      case composeChecked stageA stageB of
        Right _ -> pure ()
        Left warnings -> expectationFailure ("aligned pair warned: " <> show warnings)

    it "reports both sides of a constructor-name drift with exact edges" $ do
      checkComposeAlignment stageA misnamedStageB
        `shouldBe` [ UnconsumedWireOutput
                       (EdgeRef StageVertex 0)
                       "MsgB"
                       StageVertex,
                     UnmatchedInCtorExpectation
                       (EdgeRef StageVertex 0)
                       "MsgTypo"
                       StageVertex
                   ]
      case composeChecked stageA misnamedStageB of
        Left _ -> pure ()
        Right _ -> expectationFailure "misnamed pair passed composeChecked"

    it "reports an out-of-range field read before evaluation" $
      checkComposeAlignment stageA arityStageB
        `shouldContain` [ FieldArityMismatch
                            (EdgeRef StageVertex 0)
                            (EdgeRef StageVertex 0)
                            "MsgB"
                            1
                            1
                        ]

    it "flags stamped mapped names explicitly" $ do
      let warnings = checkComposeAlignment (rmapCo id stageA) stageB
      warnings
        `shouldSatisfy` any (\case PoisonedNameInComposition "MsgB#rmapped" "upstream output" -> True; _ -> False)

    it "walks every symbol in a multi-event source chain" $
      checkComposeAlignment pairSource twoPhaseSink `shouldBe` []
