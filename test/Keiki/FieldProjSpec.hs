{-# LANGUAGE TypeFamilies #-}

module Keiki.FieldProjSpec where

import Data.Proxy (Proxy (..))
import Data.SBV qualified as SBV
import Data.Text (Text)
import Data.Text qualified as T
import Keiki.Core
import Keiki.Symbolic
  ( SymEnv (..),
    constrainFieldProjection,
    mkSymEnv,
    symIsBot,
    translatePred,
  )
import Test.Hspec
import Test.QuickCheck
  ( expectFailure,
    ioProperty,
    property,
  )
import Test.QuickCheck.Property (withMaxSuccess)

data DocInfo = DocInfo
  { diHash :: Text,
    diTitle :: Text,
    diNumbers :: [Int]
  }
  deriving stock (Eq, Show)

data DocContentHash

instance FieldProjection DocContentHash where
  type FieldName DocContentHash = "contentHash"
  type FieldOwner DocContentHash = DocInfo
  type FieldResult DocContentHash = Text
  fieldShapeId _ = "test.doc-info.v1"
  projectFieldValue _ = diHash

data DocTitle

instance FieldProjection DocTitle where
  type FieldName DocTitle = "title"
  type FieldOwner DocTitle = DocInfo
  type FieldResult DocTitle = Text
  fieldShapeId _ = "test.doc-info.v1"
  projectFieldValue _ = diTitle

data DocContentHashAlias

instance FieldProjection DocContentHashAlias where
  type FieldName DocContentHashAlias = "contentHash"
  type FieldOwner DocContentHashAlias = DocInfo
  type FieldResult DocContentHashAlias = Text
  fieldShapeId _ = "test.doc-info.v1"
  projectFieldValue _ = diHash

data DocNumbers

instance FieldProjection DocNumbers where
  type FieldName DocNumbers = "numbers"
  type FieldOwner DocNumbers = DocInfo
  type FieldResult DocNumbers = [Int]
  fieldShapeId _ = "test.doc-info.v1"
  projectFieldValue _ = diNumbers

data DocIdentity

instance FieldProjection DocIdentity where
  type FieldName DocIdentity = "self"
  type FieldOwner DocIdentity = DocInfo
  type FieldResult DocIdentity = DocInfo
  fieldShapeId _ = "test.doc-info.v1"
  projectFieldValue _ = id

data AdversarialHash

instance FieldProjection AdversarialHash where
  type FieldName AdversarialHash = "content/|\\hash"
  type FieldOwner AdversarialHash = DocInfo
  type FieldResult AdversarialHash = Text
  fieldShapeId _ = "shape/|\\doc"
  projectFieldValue _ = diHash

docHashW :: FieldWitness DocContentHash
docHashW = fieldWitness @DocContentHash

docTitleW :: FieldWitness DocTitle
docTitleW = fieldWitness @DocTitle

docHashAliasW :: FieldWitness DocContentHashAlias
docHashAliasW = fieldWitness @DocContentHashAlias

docNumbersW :: FieldWitness DocNumbers
docNumbersW = fieldWitness @DocNumbers

docIdentityW :: FieldWitness DocIdentity
docIdentityW = fieldWitness @DocIdentity

adversarialHashW :: FieldWitness AdversarialHash
adversarialHashW = fieldWitness @AdversarialHash

type DocRegs = '[ '("doc", DocInfo)]

docIx :: Index DocRegs DocInfo
docIx = #doc

docN :: IndexN "doc" DocRegs DocInfo
docN = IZ

data DocCmd = NewDoc DocInfo
  deriving stock (Eq, Show)

type NewDocFields = '[ '("doc", DocInfo)]

newDocCtor :: InCtor DocCmd NewDocFields
newDocCtor =
  InCtor
    { icName = "NewDoc",
      icMatch = \case
        NewDoc doc -> Just (RCons (Proxy @"doc") doc RNil),
      icBuild = \(RCons _ doc RNil) -> NewDoc doc
    }

data DocEvent = DocAccepted DocInfo
  deriving stock (Eq, Show)

docAcceptedWire :: WireCtor DocEvent (DocInfo, ())
docAcceptedWire =
  WireCtor
    { wcName = "DocAccepted",
      wcMatch = \case DocAccepted doc -> Just (doc, ()),
      wcBuild = \(doc, ()) -> DocAccepted doc
    }

data DocState = DocState
  deriving stock (Eq, Ord, Show, Enum, Bounded)

initialDocInfo :: DocInfo
initialDocInfo = DocInfo "old-hash" "old title" []

docProjectionTransducer ::
  SymTransducer (HsPred DocRegs DocCmd) DocRegs DocState DocCmd DocEvent
docProjectionTransducer =
  SymTransducer
    { edgesOut = \DocState ->
        [ Edge
            { guard =
                PAnd
                  (matchInCtor newDocCtor)
                  (regProj docHashW docIx ./= inpProj docHashW newDocCtor #doc),
              update = USet docN (TInpCtorField newDocCtor #doc),
              output =
                [ pack
                    newDocCtor
                    docAcceptedWire
                    (OFCons (TInpCtorField newDocCtor #doc) OFNil)
                ],
              target = DocState,
              mode = Live
            }
        ],
      initial = DocState,
      initialRegs = RCons (Proxy @"doc") initialDocInfo RNil,
      isFinal = const True
    }

inputProjectionTransducer ::
  SymTransducer (HsPred '[] DocCmd) '[] DocState DocCmd DocEvent
inputProjectionTransducer =
  SymTransducer
    { edgesOut = \DocState ->
        [ Edge
            { guard =
                PAnd
                  (matchInCtor newDocCtor)
                  (inpProj docHashW newDocCtor #doc .== TLit "new-hash"),
              update = UKeep,
              output =
                [ pack
                    newDocCtor
                    docAcceptedWire
                    (OFCons (TInpCtorField newDocCtor #doc) OFNil)
                ],
              target = DocState,
              mode = Live
            }
        ],
      initial = DocState,
      initialRegs = RNil,
      isFinal = const True
    }

data PairInts = PairInts Int Int
  deriving stock (Eq, Show)

data WrongFirst

instance FieldProjection WrongFirst where
  type FieldName WrongFirst = "first"
  type FieldOwner WrongFirst = PairInts
  type FieldResult WrongFirst = Int
  fieldShapeId _ = "test.pair-ints.v1"
  projectFieldValue _ (PairInts _ second) = second

wrongFirstW :: FieldWitness WrongFirst
wrongFirstW = fieldWitness @WrongFirst

data NumberOwner = NumberOwner Int Integer

data NumberAsInt

instance FieldProjection NumberAsInt where
  type FieldName NumberAsInt = "number"
  type FieldOwner NumberAsInt = NumberOwner
  type FieldResult NumberAsInt = Int
  fieldShapeId _ = "test.number-owner.v1"
  projectFieldValue _ (NumberOwner value _) = value

data NumberAsInteger

instance FieldProjection NumberAsInteger where
  type FieldName NumberAsInteger = "number"
  type FieldOwner NumberAsInteger = NumberOwner
  type FieldResult NumberAsInteger = Integer
  fieldShapeId _ = "test.number-owner.v1"
  projectFieldValue _ (NumberOwner _ value) = value

type NumberRegs = '[ '("numberOwner", NumberOwner)]

numberIntW :: FieldWitness NumberAsInt
numberIntW = fieldWitness @NumberAsInt

numberIntegerW :: FieldWitness NumberAsInteger
numberIntegerW = fieldWitness @NumberAsInteger

proveConcreteAgreement ::
  HsPred rs ci ->
  (SymEnv -> SBV.Symbolic ()) ->
  Bool ->
  IO Bool
proveConcreteAgreement predicate bindConcrete concrete = do
  result <- SBV.prove $ do
    env <- mkSymEnv
    translated <- translatePred env predicate
    bindConcrete env
    pure (translated SBV..<=> SBV.literal concrete)
  pure (not (SBV.modelExists result))

spec :: Spec
spec = do
  describe "concrete field projection" $ do
    let doc = DocInfo "hash-1" "title-1" [1, 2]
        regs = RCons (Proxy @"doc") doc RNil

    it "evaluates a register-owned field" $
      evalTerm (regProj docHashW docIx :: Term DocRegs DocCmd '[] Text) regs (NewDoc doc)
        `shouldBe` "hash-1"

    it "evaluates an input-owned field" $
      evalTerm
        (inpProj docHashW newDocCtor #doc :: Term '[] DocCmd NewDocFields Text)
        RNil
        (NewDoc doc)
        `shouldBe` "hash-1"

    it "keeps projection guards out of the opaque audit while TApp1 remains opaque" $ do
      opaqueGuardWarnings docProjectionTransducer `shouldBe` []
      let opaque =
            docProjectionTransducer
              { edgesOut = \DocState ->
                  [ Edge
                      { guard = PEq (TApp1 diHash (TReg docIx)) (TLit "old-hash"),
                        update = UKeep,
                        output = [],
                        target = DocState,
                        mode = Live
                      }
                  ]
              }
      opaqueGuardWarnings opaque `shouldSatisfy` (not . null)

  describe "path-keyed symbolic projection" $ do
    it "shares one variable for the same nominal projection and base" $
      symIsBot
        ( regProj docHashW docIx ./= regProj docHashW docIx ::
            HsPred DocRegs ()
        )
        `shouldBe` True

    it "keeps distinct fields of one owner independent" $
      symIsBot
        ( PAnd
            (regProj docHashW docIx .== TLit "left")
            (regProj docTitleW docIx .== TLit "right") ::
            HsPred DocRegs ()
        )
        `shouldBe` False

    it "keeps nominal tags independent even with identical diagnostics" $
      symIsBot
        ( PAnd
            (regProj docHashW docIx .== TLit "left")
            (regProj docHashAliasW docIx .== TLit "right") ::
            HsPred DocRegs ()
        )
        `shouldBe` False

    it "keeps Int and Integer results independent despite a shared SBV representation" $
      symIsBot
        ( PAnd
            (regProj numberIntW (#numberOwner :: Index NumberRegs NumberOwner) .== TLit 0)
            (regProj numberIntegerW (#numberOwner :: Index NumberRegs NumberOwner) .== TLit 1) ::
            HsPred NumberRegs ()
        )
        `shouldBe` False

    it "uses index position when duplicate diagnostic labels are constructed manually" $ do
      let first = ZIdx :: Index '[ '("doc", DocInfo), '("doc", DocInfo)] DocInfo
          second = SIdx ZIdx :: Index '[ '("doc", DocInfo), '("doc", DocInfo)] DocInfo
      symIsBot
        ( PAnd
            (regProj docHashW first .== TLit "left")
            (regProj docHashW second .== TLit "right") ::
            HsPred '[ '("doc", DocInfo), '("doc", DocInfo)] ()
        )
        `shouldBe` False

    it "keeps register and input bases distinct even when dotted paths coincide" $ do
      let registerBase = ZIdx :: Index '[ '("NewDoc.doc", DocInfo)] DocInfo
      symIsBot
        ( PAnd
            (regProj docHashW registerBase .== TLit "left")
            (inpProj docHashW newDocCtor #doc .== TLit "right") ::
            HsPred '[ '("NewDoc.doc", DocInfo)] DocCmd
        )
        `shouldBe` False

    it "never sends adversarial diagnostic strings to SBV labels" $
      let adversarialIx = ZIdx :: Index '[ '("doc/|\\owner", DocInfo)] DocInfo
       in symIsBot
            ( regProj adversarialHashW adversarialIx
                ./= regProj adversarialHashW adversarialIx ::
                HsPred '[ '("doc/|\\owner", DocInfo)] ()
            )
            `shouldBe` True

  describe "concrete-to-symbolic agreement" $ do
    it "agrees for register projections in both truth directions" $
      withMaxSuccess 25 $
        property $ \rawHash same ->
          let owner = DocInfo (T.pack rawHash) "title" []
              comparison = if same then diHash owner else diHash owner <> "#different"
              regs = RCons (Proxy @"doc") owner RNil
              predicate = regProj docHashW docIx .== TLit comparison
              concrete = evalPred predicate regs (NewDoc owner)
           in ioProperty $
                proveConcreteAgreement
                  predicate
                  (\env -> constrainFieldProjection env docHashW (PBReg docIx) (diHash owner))
                  concrete

    it "agrees for input projections in both truth directions" $
      withMaxSuccess 25 $
        property $ \rawHash same ->
          let owner = DocInfo (T.pack rawHash) "title" []
              comparison = if same then diHash owner else diHash owner <> "#different"
              input = NewDoc owner
              predicate =
                PAnd
                  (matchInCtor newDocCtor)
                  (inpProj docHashW newDocCtor #doc .== TLit comparison)
              concrete = evalPred predicate RNil input
           in ioProperty $
                proveConcreteAgreement
                  predicate
                  ( \env -> do
                      SBV.constrain (seInputCtor env SBV..== SBV.literal "NewDoc")
                      constrainFieldProjection
                        env
                        docHashW
                        (PBInp newDocCtor #doc)
                        (diHash owner)
                  )
                  concrete

  describe "instance law harness" $ do
    it "accepts the truthful generated-style witness" $
      property $ \rawHash rawTitle ->
        let owner = DocInfo (T.pack rawHash) (T.pack rawTitle) []
         in fieldWitnessAgrees docHashW diHash owner

    it "finds a deliberately wrong coherent instance" $
      expectFailure $
        property $ \value ->
          fieldWitnessAgrees
            wrongFirstW
            (\(PairInts first _) -> first)
            (PairInts value (value + 1))

  describe "validation and replay" $ do
    it "validates the projection-guarded transducer under default options" $
      validateTransducer defaultValidationOptions docProjectionTransducer
        `shouldBe` []

    it "replays a projection-selected event to the complete forward state" $ do
      let nextDoc = DocInfo "new-hash" "new title" [3]
      case stepEither
        docProjectionTransducer
        (initial docProjectionTransducer, initialRegs docProjectionTransducer)
        (NewDoc nextDoc) of
        Left failure -> expectationFailure ("forward step failed: " <> show failure)
        Right (forwardState, forwardRegs, events) ->
          case reconstituteEither docProjectionTransducer events of
            Left failure -> expectationFailure ("replay failed: " <> show failure)
            Right (replayState, replayRegs) -> do
              replayState `shouldBe` forwardState
              replayRegs ! docIx `shouldBe` forwardRegs ! docIx
