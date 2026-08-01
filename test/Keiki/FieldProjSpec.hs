{-# LANGUAGE TypeFamilies #-}

module Keiki.FieldProjSpec where

import Data.Foldable (toList)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Maybe (isNothing)
import Data.Proxy (Proxy (..))
import Data.SBV qualified as SBV
import Data.Text (Text)
import Data.Text qualified as T
import Keiki.Core
import Keiki.ProjectionDomain
import Keiki.Symbolic
  ( DeadEdgeAnalysisDetail (..),
    DeterminismAnalysisDetail (..),
    KnownInCtors (..),
    PredicateVerification (..),
    PredicateVerificationDetail (..),
    ProjectionBaseDescriptor (..),
    ProjectionDescriptor (..),
    ProjectionModel (..),
    SomeInCtor (..),
    SymEnv (..),
    TranslationIssue (..),
    TranslationStrength (..),
    checkDeadEdgesSym,
    checkDeadEdgesSymDetailed,
    checkTransitionDeterminismSym,
    checkTransitionDeterminismSymDetailed,
    constrainFieldProjection,
    mkSymEnv,
    predicateTranslationExact,
    predicateTranslationReport,
    projectionModelKeyAs,
    projectionModelOwnerAs,
    symIsBot,
    symSatExt,
    translatePred,
    verifyPredicate,
    verifyPredicateDetailed,
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

data BoolKey

instance FieldProjection BoolKey where
  type FieldName BoolKey = "key"
  type FieldOwner BoolKey = Bool
  type FieldResult BoolKey = Text
  fieldShapeId _ = "test.bool-key.v1"
  projectFieldValue _ False = "disabled"
  projectFieldValue _ True = "enabled"

instance ExactFieldProjection BoolKey where
  fieldProjectionDomain _ =
    finiteProjectionDomain ("disabled" :| ["enabled"])
  reconstructFieldOwner _ "disabled" = Just False
  reconstructFieldOwner _ "enabled" = Just True
  reconstructFieldOwner _ _ = Nothing

type BoolOwnerRegs = '[ '("owner", Bool)]

boolKeyW :: FieldWitness BoolKey
boolKeyW = fieldWitness @BoolKey

exactBoolKeyW :: FieldWitness BoolKey
exactBoolKeyW = exactFieldWitness @BoolKey

boolOwnerIx :: Index BoolOwnerRegs Bool
boolOwnerIx = #owner

exhaustiveProjectionPredicate :: HsPred BoolOwnerRegs ()
exhaustiveProjectionPredicate =
  PAnd
    (regProj boolKeyW boolOwnerIx ./= TLit "disabled")
    (regProj boolKeyW boolOwnerIx ./= TLit "enabled")

repeatedProjectionContradiction :: HsPred BoolOwnerRegs ()
repeatedProjectionContradiction =
  regProj boolKeyW boolOwnerIx ./= regProj boolKeyW boolOwnerIx

exactExhaustiveProjectionPredicate :: HsPred BoolOwnerRegs ()
exactExhaustiveProjectionPredicate =
  PAnd
    (regProj exactBoolKeyW boolOwnerIx ./= TLit "disabled")
    (regProj exactBoolKeyW boolOwnerIx ./= TLit "enabled")

exactEnabledProjectionPredicate :: HsPred BoolOwnerRegs ()
exactEnabledProjectionPredicate =
  regProj exactBoolKeyW boolOwnerIx .== TLit "enabled"

data BoolAsInt

instance FieldProjection BoolAsInt where
  type FieldName BoolAsInt = "asInt"
  type FieldOwner BoolAsInt = Bool
  type FieldResult BoolAsInt = Int
  fieldShapeId _ = "test.bool-as-int.v1"
  projectFieldValue _ False = 0
  projectFieldValue _ True = 1

instance ExactFieldProjection BoolAsInt where
  fieldProjectionDomain _ = finiteProjectionDomain (0 :| [1])
  reconstructFieldOwner _ 0 = Just False
  reconstructFieldOwner _ 1 = Just True
  reconstructFieldOwner _ _ = Nothing

exactBoolAsIntW :: FieldWitness BoolAsInt
exactBoolAsIntW = exactFieldWitness @BoolAsInt

data RichOwner = RichOwner Bool Bool
  deriving stock (Eq, Show)

data RichFirst

instance FieldProjection RichFirst where
  type FieldName RichFirst = "first"
  type FieldOwner RichFirst = RichOwner
  type FieldResult RichFirst = Bool
  fieldShapeId _ = "test.rich-owner.v1"
  projectFieldValue _ (RichOwner first _) = first

instance ExactFieldProjection RichFirst where
  fieldProjectionDomain _ = wholeProjectionDomain
  reconstructFieldOwner _ first = Just (RichOwner first False)

data RichSecond

instance FieldProjection RichSecond where
  type FieldName RichSecond = "second"
  type FieldOwner RichSecond = RichOwner
  type FieldResult RichSecond = Bool
  fieldShapeId _ = "test.rich-owner.v1"
  projectFieldValue _ (RichOwner _ second) = second

instance ExactFieldProjection RichSecond where
  fieldProjectionDomain _ = wholeProjectionDomain
  reconstructFieldOwner _ second = Just (RichOwner False second)

exactRichFirstW :: FieldWitness RichFirst
exactRichFirstW = exactFieldWitness @RichFirst

exactRichSecondW :: FieldWitness RichSecond
exactRichSecondW = exactFieldWitness @RichSecond

type RichRegs = '[ '("left", RichOwner), '("right", RichOwner)]

richLeftIx :: Index RichRegs RichOwner
richLeftIx = #left

richRightIx :: Index RichRegs RichOwner
richRightIx = #right

data BrokenRejectInverse

instance FieldProjection BrokenRejectInverse where
  type FieldName BrokenRejectInverse = "brokenReject"
  type FieldOwner BrokenRejectInverse = Bool
  type FieldResult BrokenRejectInverse = Text
  fieldShapeId _ = "test.broken-reject.v1"
  projectFieldValue _ False = "disabled"
  projectFieldValue _ True = "enabled"

instance ExactFieldProjection BrokenRejectInverse where
  fieldProjectionDomain _ = finiteProjectionDomain ("enabled" :| [])
  reconstructFieldOwner _ _ = Nothing

data BrokenRoundTripInverse

instance FieldProjection BrokenRoundTripInverse where
  type FieldName BrokenRoundTripInverse = "brokenRoundTrip"
  type FieldOwner BrokenRoundTripInverse = Bool
  type FieldResult BrokenRoundTripInverse = Text
  fieldShapeId _ = "test.broken-round-trip.v1"
  projectFieldValue _ False = "disabled"
  projectFieldValue _ True = "enabled"

instance ExactFieldProjection BrokenRoundTripInverse where
  fieldProjectionDomain _ = finiteProjectionDomain ("enabled" :| [])
  reconstructFieldOwner _ _ = Just False

data UnderDeclaredDomain

instance FieldProjection UnderDeclaredDomain where
  type FieldName UnderDeclaredDomain = "underDeclared"
  type FieldOwner UnderDeclaredDomain = Bool
  type FieldResult UnderDeclaredDomain = Text
  fieldShapeId _ = "test.under-declared.v1"
  projectFieldValue _ False = "disabled"
  projectFieldValue _ True = "enabled"

instance ExactFieldProjection UnderDeclaredDomain where
  fieldProjectionDomain _ = finiteProjectionDomain ("disabled" :| [])
  reconstructFieldOwner _ "disabled" = Just False
  reconstructFieldOwner _ _ = Nothing

data BoolProjectionCmd = WithOwner Bool | WithoutOwner
  deriving stock (Eq, Show)

type WithOwnerFields = '[ '("owner", Bool)]

withOwnerCtor :: InCtor BoolProjectionCmd WithOwnerFields
withOwnerCtor =
  InCtor
    { icName = "WithOwner",
      icMatch = \case
        WithOwner owner -> Just (RCons (Proxy @"owner") owner RNil)
        WithoutOwner -> Nothing,
      icBuild = \(RCons _ owner RNil) -> WithOwner owner
    }

withoutOwnerCtor :: InCtor BoolProjectionCmd '[]
withoutOwnerCtor =
  InCtor
    { icName = "WithoutOwner",
      icMatch = \case
        WithoutOwner -> Just RNil
        WithOwner _ -> Nothing,
      icBuild = \RNil -> WithoutOwner
    }

instance KnownInCtors BoolProjectionCmd where
  allInCtors = [SomeInCtor withOwnerCtor, SomeInCtor withoutOwnerCtor]

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

translationIssuesOf :: HsPred rs ci -> [TranslationIssue]
translationIssuesOf predicate = case predicateTranslationReport predicate of
  ExactTranslation -> []
  ConservativeOverApproximation issues -> toList issues

isConflictingViews :: TranslationIssue -> Bool
isConflictingViews ConflictingProjectionViews {} = True
isConflictingViews _ = False

isDirectAndProjected :: TranslationIssue -> Bool
isDirectAndProjected DirectAndProjectedOwnerRead {} = True
isDirectAndProjected _ = False

isUnguardedProjection :: TranslationIssue -> Bool
isUnguardedProjection UnguardedProjectionInputRead {} = True
isUnguardedProjection _ = False

isOutsideEquality :: TranslationIssue -> Bool
isOutsideEquality ProjectionUsedOutsideEquality {} = True
isOutsideEquality _ = False

data ProjectionAnalysisState = ProjectionAnalysisState
  deriving stock (Eq, Show, Enum, Bounded)

projectionAnalysisEdge ::
  HsPred BoolOwnerRegs () ->
  Edge (HsPred BoolOwnerRegs ()) BoolOwnerRegs () () ProjectionAnalysisState
projectionAnalysisEdge edgeGuard =
  Edge
    { guard = edgeGuard,
      update = UKeep,
      output = [],
      target = ProjectionAnalysisState,
      mode = Live
    }

projectionDeterminismTransducer ::
  SymTransducer
    (HsPred BoolOwnerRegs ())
    BoolOwnerRegs
    ProjectionAnalysisState
    ()
    ()
projectionDeterminismTransducer =
  SymTransducer
    { edgesOut = \ProjectionAnalysisState ->
        [ projectionAnalysisEdge
            (regProj exactBoolKeyW boolOwnerIx .== TLit "disabled"),
          projectionAnalysisEdge
            (regProj exactBoolKeyW boolOwnerIx .== TLit "enabled")
        ],
      initial = ProjectionAnalysisState,
      initialRegs = RCons (Proxy @"owner") False RNil,
      isFinal = const True
    }

projectionDeadEdgeTransducer ::
  SymTransducer
    (HsPred BoolOwnerRegs ())
    BoolOwnerRegs
    ProjectionAnalysisState
    ()
    ()
projectionDeadEdgeTransducer =
  SymTransducer
    { edgesOut = \ProjectionAnalysisState ->
        [projectionAnalysisEdge exactExhaustiveProjectionPredicate],
      initial = ProjectionAnalysisState,
      initialRegs = RCons (Proxy @"owner") False RNil,
      isFinal = const True
    }

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

  describe "projection verification" $ do
    it "checks every owner and key in the finite exact image" $
      mapM_
        ( \(owner, key) -> do
            checkFieldProjectionOwner exactBoolKeyW owner `shouldBe` Right ()
            checkFieldProjectionKey exactBoolKeyW key `shouldBe` Right owner
        )
        [(False, "disabled"), (True, "enabled")]

    it "does not call a supported but unconstrained projection translation-exact" $ do
      -- Before the conservative classifier, z3 could invent a third Text key
      -- outside the getter's two-value image and verify that fabricated model.
      evalPred
        exhaustiveProjectionPredicate
        (RCons (Proxy @"owner") False RNil)
        ()
        `shouldBe` False
      evalPred
        exhaustiveProjectionPredicate
        (RCons (Proxy @"owner") True RNil)
        ()
        `shouldBe` False
      fieldWitnessHasExactDomain boolKeyW `shouldBe` False
      predicateTranslationExact exhaustiveProjectionPredicate `shouldBe` False
      verifyPredicate exhaustiveProjectionPredicate `shouldReturn` UnverifiedOpaque
      isNothing (symSatExt exhaustiveProjectionPredicate) `shouldBe` True

    it "keeps one-sided emptiness proofs for repeated projection reads" $ do
      predicateTranslationExact repeatedProjectionContradiction `shouldBe` False
      verifyPredicate repeatedProjectionContradiction `shouldReturn` UnverifiedOpaque
      symIsBot repeatedProjectionContradiction `shouldBe` True

    it "keeps ordinary register witness extraction" $ do
      let predicate = TReg boolOwnerIx .== TLit True :: HsPred BoolOwnerRegs ()
      case symSatExt predicate of
        Nothing -> expectationFailure "ordinary Bool register predicate lost its witness"
        Just (registers, command) ->
          evalPred predicate registers command `shouldBe` True

    it "returns no witness instead of throwing on an unguarded input projection" $ do
      let predicate =
            PAnd
              (inpProj boolKeyW withOwnerCtor #owner .== TLit "invented")
              (PInCtor withoutOwnerCtor) ::
              HsPred '[] BoolProjectionCmd
      isNothing (symSatExt predicate) `shouldBe` True

    it "proves the excluded third key unsatisfiable for an exact finite image" $ do
      predicateTranslationReport exactExhaustiveProjectionPredicate
        `shouldBe` ExactTranslation
      verifyPredicate exactExhaustiveProjectionPredicate
        `shouldReturn` VerifiedUnsatisfiable
      symIsBot exactExhaustiveProjectionPredicate `shouldBe` True

    it "returns a typed checked projection model" $ do
      detail <- verifyPredicateDetailed exactEnabledProjectionPredicate
      case detail of
        PredicateSatisfiable ExactTranslation [projectionModel] -> do
          projectionModelKeyAs @Text projectionModel `shouldBe` Just "enabled"
          projectionModelOwnerAs @Bool projectionModel `shouldBe` Just True
        other -> expectationFailure ("expected one exact projection model, got " <> show other)
      verifyPredicate exactEnabledProjectionPredicate
        `shouldReturn` VerifiedSatisfiable

    it "uses a relation-safe projection owner in full witness extraction" $
      case symSatExt exactEnabledProjectionPredicate of
        Nothing -> expectationFailure "expected exact projection owner override"
        Just (registers, ()) -> registers ! boolOwnerIx `shouldBe` True

    it "installs a relation-safe owner into the matching input constructor field" $ do
      let predicate =
            PAnd
              (PInCtor withOwnerCtor)
              (inpProj exactBoolKeyW withOwnerCtor #owner .== TLit "enabled") ::
              HsPred '[] BoolProjectionCmd
      case symSatExt predicate of
        Just (RNil, WithOwner True) -> pure ()
        other -> expectationFailure ("expected WithOwner True, got " <> show (snd <$> other))

    it "keeps path-local models distinct from an inconsistent full owner witness" $ do
      let predicate =
            PAnd
              (regProj exactBoolKeyW boolOwnerIx .== TLit "enabled")
              (regProj exactBoolAsIntW boolOwnerIx .== TLit 0) ::
              HsPred BoolOwnerRegs ()
      detail <- verifyPredicateDetailed predicate
      case detail of
        PredicateSatisfiable (ConservativeOverApproximation _) projectionModels ->
          length projectionModels `shouldBe` 2
        other -> expectationFailure ("expected conservative path models, got " <> show other)
      isNothing (symSatExt predicate) `shouldBe` True

    it "keeps equal display names distinct by structural position in models" $ do
      let first = ZIdx :: Index '[ '("owner", Bool), '("owner", Bool)] Bool
          second = SIdx ZIdx :: Index '[ '("owner", Bool), '("owner", Bool)] Bool
          predicate =
            PAnd
              (regProj exactBoolKeyW first .== TLit "disabled")
              (regProj exactBoolKeyW second .== TLit "enabled") ::
              HsPred '[ '("owner", Bool), '("owner", Bool)] ()
      detail <- verifyPredicateDetailed predicate
      case detail of
        PredicateSatisfiable ExactTranslation projectionModels -> do
          length projectionModels `shouldBe` 2
          fmap (projectionBasePosition . projectionDescriptorBase . projectionModelDescriptor) projectionModels
            `shouldBe` [0, 1]
        other -> expectationFailure ("expected two structural models, got " <> show other)

    it "reports an inverse that rejects an admitted model as a contract violation" $ do
      let witness = exactFieldWitness @BrokenRejectInverse
          predicate =
            regProj witness boolOwnerIx .== TLit "enabled" ::
              HsPred BoolOwnerRegs ()
      detail <- verifyPredicateDetailed predicate
      case detail of
        PredicateProjectionContractViolation ExactTranslation _ message ->
          message `shouldContain` show ProjectionInverseRejectedDomainKey
        other -> expectationFailure ("expected inverse rejection, got " <> show other)
      compatibility <- verifyPredicate predicate
      compatibility `shouldSatisfy` \case
        UnverifiedSolverFailure _ -> True
        _ -> False

    it "reports an inverse getter mismatch as a contract violation" $ do
      let witness = exactFieldWitness @BrokenRoundTripInverse
          predicate =
            regProj witness boolOwnerIx .== TLit "enabled" ::
              HsPred BoolOwnerRegs ()
      detail <- verifyPredicateDetailed predicate
      case detail of
        PredicateProjectionContractViolation ExactTranslation _ message ->
          message `shouldContain` show ProjectionInverseRoundTripMismatch
        other -> expectationFailure ("expected round-trip violation, got " <> show other)

    it "catches an under-declared image only through the owner-side law" $ do
      let witness = exactFieldWitness @UnderDeclaredDomain
      checkFieldProjectionOwner witness True
        `shouldBe` Left ProjectedKeyOutsideDeclaredDomain

  describe "predicate-wide projection translation report" $ do
    it "allows repeated exact reads and the same tag on distinct bases" $ do
      let repeated =
            regProj exactBoolKeyW boolOwnerIx
              .== regProj exactBoolKeyW boolOwnerIx
          distinctBases =
            PAnd
              (regProj exactRichFirstW richLeftIx .== TLit True)
              (regProj exactRichFirstW richRightIx .== TLit False)
      predicateTranslationReport repeated `shouldBe` ExactTranslation
      predicateTranslationReport distinctBases `shouldBe` ExactTranslation

    it "allows distinct exact tags only when their bases differ" $ do
      let separate =
            PAnd
              (regProj exactRichFirstW richLeftIx .== TLit True)
              (regProj exactRichSecondW richRightIx .== TLit False)
          correlated =
            PAnd
              (regProj exactRichFirstW richLeftIx .== TLit True)
              (regProj exactRichSecondW richLeftIx .== TLit False)
      predicateTranslationReport separate `shouldBe` ExactTranslation
      translationIssuesOf correlated `shouldSatisfy` any isConflictingViews

    it "rejects a direct owner read combined with its projection" $ do
      let predicate =
            PAnd
              (TReg boolOwnerIx .== TLit True)
              (regProj exactBoolKeyW boolOwnerIx .== TLit "enabled")
      translationIssuesOf predicate `shouldSatisfy` any isDirectAndProjected

    it "constrains mixed exact/unconstrained occurrences in both orders but reports both inexact" $ do
      let unconstrainedFirst =
            PAnd
              (regProj boolKeyW boolOwnerIx ./= TLit "disabled")
              (regProj exactBoolKeyW boolOwnerIx ./= TLit "enabled")
          exactFirst =
            PAnd
              (regProj exactBoolKeyW boolOwnerIx ./= TLit "enabled")
              (regProj boolKeyW boolOwnerIx ./= TLit "disabled")
      symIsBot unconstrainedFirst `shouldBe` True
      symIsBot exactFirst `shouldBe` True
      predicateTranslationExact unconstrainedFirst `shouldBe` False
      predicateTranslationExact exactFirst `shouldBe` False
      translationIssuesOf unconstrainedFirst `shouldSatisfy` any isConflictingViews
      translationIssuesOf exactFirst `shouldSatisfy` any isConflictingViews

    it "uses logical constructor domination independently of conjunction order" $ do
      let projectionAtom =
            inpProj exactBoolKeyW withOwnerCtor #owner .== TLit "enabled"
          guardFirst = PAnd (PInCtor withOwnerCtor) projectionAtom
          projectionFirst = PAnd projectionAtom (PInCtor withOwnerCtor)
          nonDominating = POr (PInCtor withOwnerCtor) projectionAtom
      predicateTranslationReport guardFirst `shouldBe` ExactTranslation
      predicateTranslationReport projectionFirst `shouldBe` ExactTranslation
      translationIssuesOf nonDominating
        `shouldSatisfy` any isUnguardedProjection

    it "keeps projection ordering and arithmetic conservative" $ do
      let ordered =
            PCmp
              CmpLt
              (regProj exactBoolAsIntW boolOwnerIx)
              (TLit 1)
          arithmetic =
            tadd (regProj exactBoolAsIntW boolOwnerIx) (TLit 1)
              .== TLit 2
      translationIssuesOf ordered `shouldSatisfy` any isOutsideEquality
      translationIssuesOf arithmetic `shouldSatisfy` any isOutsideEquality

  describe "detailed projection analyses" $ do
    it "retains one exact UNSAT result for a disjoint live pair" $ do
      details <- checkTransitionDeterminismSymDetailed projectionDeterminismTransducer
      case details of
        [DeterminismAnalysisDetail _ _ (PredicateUnsatisfiable ExactTranslation)] -> pure ()
        _ -> expectationFailure ("unexpected determinism details: " <> show (length details))
      checkTransitionDeterminismSym projectionDeterminismTransducer `shouldBe` []

    it "retains the exact dead-edge result used by the compatibility warning" $ do
      details <- checkDeadEdgesSymDetailed projectionDeadEdgeTransducer
      case details of
        [DeadEdgeAnalysisDetail _ (PredicateUnsatisfiable ExactTranslation)] -> pure ()
        _ -> expectationFailure ("unexpected dead-edge details: " <> show (length details))
      length (checkDeadEdgesSym projectionDeadEdgeTransducer) `shouldBe` 1

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
