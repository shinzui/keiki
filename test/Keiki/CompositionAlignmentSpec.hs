{-# OPTIONS_GHC -Wno-partial-fields #-}

module Keiki.CompositionAlignmentSpec (spec) where

import Data.Proxy (Proxy (..))
import Data.Text qualified as T
import GHC.Generics (Generic)
import Keiki.Composition
import Keiki.Core
import Keiki.FieldProjSpec qualified as FieldProj
import Keiki.Fixtures.ComposeStateful
import Keiki.Fixtures.CounterPipeline
import Keiki.Generics (mkInCtorRecordVia, mkWireCtorRecordVia)
import Keiki.Profunctor (rmapCo)
import Keiki.Render.Pretty (prettyPred, prettyTerm)
import Test.Hspec

type Payload1 = '[ '("payload", Int)]

type Payload2 = '[ '("first", Int), '("second", Int)]

typoInMsgB :: InCtor MsgB Payload1
typoInMsgB =
  unavailableInCtor
    "MsgTypo"
    (\(MsgB n) -> Just (RCons (Proxy @"payload") n RNil))
    (\(RCons _ n RNil) -> MsgB n)

twoFieldInMsgB :: InCtor MsgB Payload2
twoFieldInMsgB =
  unavailableInCtor
    "MsgB"
    ( \(MsgB n) ->
        Just
          ( RCons
              (Proxy @"first")
              n
              (RCons (Proxy @"second") n RNil)
          )
    )
    (\(RCons _ n (RCons _ _ RNil)) -> MsgB n)

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

data ProjectionSourceCmd = ProjectionSourceCmd FieldProj.DocInfo
  deriving stock (Eq, Show)

type ProjectionSourceFields = '[ '("doc", FieldProj.DocInfo)]

projectionSourceCtor :: InCtor ProjectionSourceCmd ProjectionSourceFields
projectionSourceCtor =
  unavailableInCtor
    "ProjectionSourceCmd"
    ( \(ProjectionSourceCmd doc) ->
        Just (RCons (Proxy @"doc") doc RNil)
    )
    (\(RCons _ doc RNil) -> ProjectionSourceCmd doc)

data ProjectionMid = ProjectionMid {doc :: FieldProj.DocInfo}
  deriving stock (Eq, Show, Generic)

projectionMidCtor :: InCtor ProjectionMid '[ '("doc", FieldProj.DocInfo)]
projectionMidCtor = mkInCtorRecordVia @"ProjectionMid"

projectionMidWire :: WireCtor ProjectionMid (FieldProj.DocInfo, ())
projectionMidWire = mkWireCtorRecordVia @"ProjectionMid"

data ProjectionVertex = ProjectionVertex
  deriving stock (Eq, Ord, Show, Enum, Bounded)

projectionSource ::
  Term '[] ProjectionSourceCmd ProjectionSourceFields FieldProj.DocInfo ->
  SymTransducer
    (HsPred '[] ProjectionSourceCmd)
    '[]
    ProjectionVertex
    ProjectionSourceCmd
    ProjectionMid
projectionSource ownerTerm =
  SymTransducer
    { edgesOut = \ProjectionVertex ->
        [ Edge
            { guard = matchInCtor projectionSourceCtor,
              update = UKeep,
              output =
                [ pack
                    projectionSourceCtor
                    projectionMidWire
                    (OFCons ownerTerm OFNil)
                ],
              target = ProjectionVertex,
              mode = Live
            }
        ],
      initial = ProjectionVertex,
      initialRegs = RNil,
      isFinal = const True
    }

projectionSink ::
  SymTransducer
    (HsPred '[] ProjectionMid)
    '[]
    ProjectionVertex
    ProjectionMid
    ()
projectionSink =
  SymTransducer
    { edgesOut = \ProjectionVertex ->
        [ Edge
            { guard =
                PAnd
                  (matchInCtor projectionMidCtor)
                  ( inpProj FieldProj.docHashW projectionMidCtor #doc
                      .== TLit "match"
                  ),
              update = UKeep,
              output = [],
              target = ProjectionVertex,
              mode = Live
            }
        ],
      initial = ProjectionVertex,
      initialRegs = RNil,
      isFinal = const True
    }

data CollisionMid
  = CollisionWire {wireValue :: Int}
  | CollisionInput {inputValue :: Int}
  deriving stock (Eq, Show, Generic)

collisionWire :: WireCtor CollisionMid (Int, ())
collisionWire =
  renameWireCtor "Collision" (mkWireCtorRecordVia @"CollisionWire")

collisionInput :: InCtor CollisionMid '[ '("inputValue", Int)]
collisionInput =
  renameInCtor "Collision" (mkInCtorRecordVia @"CollisionInput")

collisionSource ::
  SymTransducer
    (HsPred '[] ProjectionSourceCmd)
    '[]
    ProjectionVertex
    ProjectionSourceCmd
    CollisionMid
collisionSource =
  SymTransducer
    { edgesOut = \ProjectionVertex ->
        [ Edge
            { guard = matchInCtor projectionSourceCtor,
              update = UKeep,
              output =
                [ pack
                    projectionSourceCtor
                    collisionWire
                    (OFCons (TLit (1 :: Int)) OFNil)
                ],
              target = ProjectionVertex,
              mode = Live
            }
        ],
      initial = ProjectionVertex,
      initialRegs = RNil,
      isFinal = const True
    }

collisionSink ::
  SymTransducer
    (HsPred '[] CollisionMid)
    '[]
    ProjectionVertex
    CollisionMid
    ()
collisionSink =
  SymTransducer
    { edgesOut = \ProjectionVertex ->
        [ Edge
            { guard =
                PAnd
                  (matchInCtor collisionInput)
                  (PEq (TInpCtorField collisionInput #inputValue) (TLit (1 :: Int))),
              update = UKeep,
              output = [],
              target = ProjectionVertex,
              mode = Live
            }
        ],
      initial = ProjectionVertex,
      initialRegs = RNil,
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

    it "rejects a same-name structurally different input/wire boundary" $ do
      checkComposeAlignment collisionSource collisionSink
        `shouldBe` [ StructurallyDifferentInputWire
                       (EdgeRef ProjectionVertex 0)
                       (EdgeRef ProjectionVertex 0)
                       "Collision"
                       "Collision"
                   ]
      case composeChecked collisionSource collisionSink of
        Left warnings ->
          warnings
            `shouldContain` [ StructurallyDifferentInputWire
                                (EdgeRef ProjectionVertex 0)
                                (EdgeRef ProjectionVertex 0)
                                "Collision"
                                "Collision"
                            ]
        Right _ -> expectationFailure "same-name structural collision passed composeChecked"

  describe "typed field projection composition" $ do
    let matchingDoc = FieldProj.DocInfo "match" "title" []
        inputTerm = TInpCtorField projectionSourceCtor #doc
        passThrough = projectionSource inputTerm
        literalOwner = projectionSource (TLit matchingDoc)
        opaqueOwner = projectionSource (opaqueLit matchingDoc)
        computedOwner = projectionSource (TApp1 id inputTerm)

    it "preserves a stable input-field owner through checked composition" $ do
      checkComposeAlignment passThrough projectionSink `shouldBe` []
      case composeChecked passThrough projectionSink of
        Left warnings -> expectationFailure ("stable projection warned: " <> show warnings)
        Right pipeline -> opaqueGuardWarnings pipeline `shouldBe` []

    it "constant-folds a literal owner with display opacity but exact semantics" $ do
      case composeChecked literalOwner projectionSink of
        Left warnings -> expectationFailure ("literal fold failed checked composition: " <> show warnings)
        Right pipeline -> do
          opaqueGuardWarnings pipeline `shouldBe` []
          case edgesOut pipeline (initial pipeline) of
            [edge] ->
              prettyPred (guard edge)
                `shouldSatisfy` T.isInfixOf (T.pack "<lit>")
            _ -> expectationFailure "literal-folded pipeline no longer has one edge"
          case stepEither
            pipeline
            (initial pipeline, initialRegs pipeline)
            (ProjectionSourceCmd (FieldProj.DocInfo "ignored" "" [])) of
            Left failure -> expectationFailure ("literal-folded pipeline failed: " <> show failure)
            Right _ -> pure ()

    it "preserves literal display evidence through positional substitution" $ do
      let midRead = TInpCtorField projectionMidCtor #doc
      case edgesOut literalOwner (initial literalOwner) of
        [Edge {output = [out]}] -> do
          let substituted =
                substTerm @'[] @'[] midRead out ::
                  Term '[] ProjectionSourceCmd ProjectionSourceFields FieldProj.DocInfo
          prettyTerm substituted `shouldBe` T.pack (show matchingDoc)
        _ -> expectationFailure "readable literal source no longer has one output"
      case edgesOut opaqueOwner (initial opaqueOwner) of
        [Edge {output = [out]}] -> do
          let substituted =
                substTerm @'[] @'[] midRead out ::
                  Term '[] ProjectionSourceCmd ProjectionSourceFields FieldProj.DocInfo
          prettyTerm substituted `shouldBe` T.pack "<lit>"
        _ -> expectationFailure "opaque literal source no longer has one output"

    it "keeps raw composition forward-correct but rejects a computed owner at the checked boundary" $ do
      let pipeline = compose computedOwner projectionSink
      opaqueGuardWarnings pipeline `shouldSatisfy` (not . null)
      case stepEither
        pipeline
        (initial pipeline, initialRegs pipeline)
        (ProjectionSourceCmd matchingDoc) of
        Left failure -> expectationFailure ("raw projected pipeline failed: " <> show failure)
        Right _ -> pure ()
      case composeChecked computedOwner projectionSink of
        Right _ -> expectationFailure "computed owner passed composeChecked"
        Left warnings ->
          warnings
            `shouldSatisfy` any
              ( \case
                  NonStructuralProjectionBoundary
                    { cawProjectionReason = "upstream computed output"
                    } -> True
                  _ -> False
              )
