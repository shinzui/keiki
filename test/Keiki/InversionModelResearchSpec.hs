-- | Test-only, unsupported prototype for ExecPlan 86. This module is research
-- evidence, not a production API or a proposed public naming scheme.
module Keiki.InversionModelResearchSpec (spec) where

import Data.Proxy (Proxy (..))
import Data.SBV qualified as SBV
import Keiki.Core
import Keiki.Symbolic (satResultIsProvablyUnsat)
import Test.Hspec

data CandidateScope = CandidateA | CandidateB
  deriving stock (Eq, Show)

data CandidateVars = CandidateVars
  { candidateConstructor :: SBV.SInteger,
    candidateOuterArm :: SBV.SBool,
    candidateField0 :: SBV.SInteger,
    candidateField1 :: SBV.SInteger,
    candidateOpaqueAtom :: SBV.SBool
  }

data DualCandidateEnv = DualCandidateEnv
  { sharedRegister0 :: SBV.SInteger,
    sharedRegister1 :: SBV.SInteger,
    candidateA :: CandidateVars,
    candidateB :: CandidateVars
  }

data InversionProofVerdict
  = InversionProvedDisjoint
  | InversionSatisfiable
  | InversionInconclusive
  deriving stock (Eq, Show)

mkCandidateVars :: CandidateScope -> SBV.Symbolic CandidateVars
mkCandidateVars scope = do
  let prefix = case scope of
        CandidateA -> "candidate-a"
        CandidateB -> "candidate-b"
  CandidateVars
    <$> SBV.free (prefix <> "/constructor")
    <*> SBV.free (prefix <> "/outer-arm")
    <*> SBV.free (prefix <> "/field/0")
    <*> SBV.free (prefix <> "/field/1")
    <*> SBV.free (prefix <> "/opaque/0")

mkDualCandidateEnv :: SBV.Symbolic DualCandidateEnv
mkDualCandidateEnv =
  DualCandidateEnv
    <$> SBV.free "register/0/duplicate-diagnostic-label"
    <*> SBV.free "register/1/duplicate-diagnostic-label"
    <*> mkCandidateVars CandidateA
    <*> mkCandidateVars CandidateB

classifyResult :: SBV.SatResult -> InversionProofVerdict
classifyResult result@(SBV.SatResult status)
  | satResultIsProvablyUnsat result = InversionProvedDisjoint
  | otherwise = case status of
      SBV.Satisfiable {} -> InversionSatisfiable
      _ -> InversionInconclusive

solveVerdict :: SBV.Symbolic SBV.SBool -> IO InversionProofVerdict
solveVerdict query = classifyResult <$> SBV.sat query

separateConstructorQuery :: SBV.Symbolic SBV.SBool
separateConstructorQuery = do
  env <- mkDualCandidateEnv
  pure $
    candidateConstructor (candidateA env) SBV..== 0
      SBV..&& candidateConstructor (candidateB env) SBV..== 1

singleConstructorNegativeControl :: SBV.Symbolic SBV.SBool
singleConstructorNegativeControl = do
  oneCommandConstructor <- SBV.free "incorrectly-shared-command/constructor"
  pure $
    oneCommandConstructor SBV..== (0 :: SBV.SInteger)
      SBV..&& oneCommandConstructor SBV..== 1

sharedRegisterDisjointQuery :: SBV.Symbolic SBV.SBool
sharedRegisterDisjointQuery = do
  env <- mkDualCandidateEnv
  let shared = sharedRegister0 env
  pure $
    candidateConstructor (candidateA env) SBV..== 0
      SBV..&& candidateConstructor (candidateB env) SBV..== 1
      SBV..&& shared SBV..< 0
      SBV..&& shared SBV..>= 0

sameConstructorCorrelatedFieldsQuery :: SBV.Symbolic SBV.SBool
sameConstructorCorrelatedFieldsQuery = do
  env <- mkDualCandidateEnv
  let a = candidateA env
      b = candidateB env
  pure $
    candidateConstructor a SBV..== 7
      SBV..&& candidateConstructor b SBV..== 7
      SBV..&& candidateField1 a SBV..== candidateField0 a + 1
      SBV..&& candidateField1 b SBV..== candidateField0 b + 1
      SBV..&& candidateField0 a SBV..== 3
      SBV..&& candidateField0 b SBV..== 9

separateEitherArmsQuery :: SBV.Symbolic SBV.SBool
separateEitherArmsQuery = do
  env <- mkDualCandidateEnv
  pure (candidateOuterArm (candidateA env) SBV..&& SBV.sNot (candidateOuterArm (candidateB env)))

separateOpaqueAtomsQuery :: SBV.Symbolic SBV.SBool
separateOpaqueAtomsQuery = do
  env <- mkDualCandidateEnv
  pure (candidateOpaqueAtom (candidateA env) SBV..&& candidateOpaqueAtom (candidateB env))

duplicateDiagnosticLabelsQuery :: SBV.Symbolic SBV.SBool
duplicateDiagnosticLabelsQuery = do
  env <- mkDualCandidateEnv
  pure (sharedRegister0 env SBV..== 0 SBV..&& sharedRegister1 env SBV..== 1)

data FieldCarrier = IntegerCarrier | BooleanCarrier
  deriving stock (Eq, Show)

data DescriptorOrigin
  = GeneratedDescriptor
  | ValidatedManualDescriptor
  | UntrustedManualDescriptor
  | DishonestDescriptor
  deriving stock (Eq, Show)

data StructuralField = StructuralField
  { structuralFieldPosition :: Int,
    structuralFieldCarrier :: FieldCarrier
  }
  deriving stock (Eq, Show)

data WireSchema = WireSchema
  { schemaDiagnosticName :: String,
    schemaConstructorIdentity :: String,
    schemaFields :: [StructuralField],
    schemaOrigin :: DescriptorOrigin
  }
  deriving stock (Eq, Show)

data SchemaAlignment
  = ExactSchemaAlignment
  | NoSafeSchemaAlignment String
  deriving stock (Eq, Show)

trustedDescriptor :: DescriptorOrigin -> Bool
trustedDescriptor GeneratedDescriptor = True
trustedDescriptor ValidatedManualDescriptor = True
trustedDescriptor UntrustedManualDescriptor = False
trustedDescriptor DishonestDescriptor = False

alignSchemas :: WireSchema -> WireSchema -> SchemaAlignment
alignSchemas left right
  | not (trustedDescriptor (schemaOrigin left) && trustedDescriptor (schemaOrigin right)) =
      NoSafeSchemaAlignment "descriptor law is not established"
  | schemaConstructorIdentity left /= schemaConstructorIdentity right =
      NoSafeSchemaAlignment "constructor identities differ"
  | schemaFields left /= schemaFields right =
      NoSafeSchemaAlignment "field positions or carriers differ"
  | otherwise = ExactSchemaAlignment

singleIntegerSchema :: DescriptorOrigin -> WireSchema
singleIntegerSchema origin =
  WireSchema
    { schemaDiagnosticName = "Observed",
      schemaConstructorIdentity = "wire/example/observed/v1",
      schemaFields = [StructuralField 0 IntegerCarrier],
      schemaOrigin = origin
    }

data OutputFieldForm
  = TopLevelCommandField
  | LiteralField
  | RegisterAuditField
  | ExactArithmeticDerivedField
  | OpaqueApplicationDerivedField
  | ExactStructuralProjectionField
  | UnconstrainedProjectionField
  deriving stock (Eq, Show)

data FieldRelation
  = EquateObservedWithCommand
  | EquateObservedWithDerivedValue
  | LeaveObservedUnconstrained
  | DropUnsupportedRelation
  deriving stock (Eq, Show)

fieldRelation :: OutputFieldForm -> FieldRelation
fieldRelation TopLevelCommandField = EquateObservedWithCommand
fieldRelation LiteralField = LeaveObservedUnconstrained
fieldRelation RegisterAuditField = LeaveObservedUnconstrained
fieldRelation ExactArithmeticDerivedField = EquateObservedWithDerivedValue
fieldRelation OpaqueApplicationDerivedField = DropUnsupportedRelation
fieldRelation ExactStructuralProjectionField = EquateObservedWithDerivedValue
fieldRelation UnconstrainedProjectionField = DropUnsupportedRelation

sharedObservedHeadQuery :: Integer -> Integer -> SBV.Symbolic SBV.SBool
sharedObservedHeadQuery guardA guardB = do
  env <- mkDualCandidateEnv
  observedHeadField <- SBV.free "observed-head/field/0"
  let a = candidateA env
      b = candidateB env
  pure $
    candidateField0 a SBV..== observedHeadField
      SBV..&& candidateField0 b SBV..== observedHeadField
      SBV..&& candidateField0 a SBV..== SBV.literal guardA
      SBV..&& candidateField0 b SBV..== SBV.literal guardB

concreteSharedHeadAmbiguities :: (Integer -> Bool) -> (Integer -> Bool) -> [Integer]
concreteSharedHeadAmbiguities acceptsA acceptsB =
  [observed | observed <- [-3 .. 3], acceptsA observed && acceptsB observed]

headOnlyTailControl :: SBV.Symbolic SBV.SBool
headOnlyTailControl = do
  env <- mkDualCandidateEnv
  observedHeadField <- SBV.free "head-only/observed/field/0"
  let a = candidateA env
      b = candidateB env
  -- Deliberately no symbolic tail relation: runtime chooses a candidate from
  -- the head before its InFlight tail can be equality-checked.
  pure $
    candidateField0 a SBV..== observedHeadField
      SBV..&& candidateField0 b SBV..== observedHeadField

type ResearchInputFields = '[ '("value", Integer)]

data ResearchCommand
  = ResearchCommandA Integer
  | ResearchCommandB Integer
  deriving stock (Eq, Show)

data ResearchEvent = ResearchObserved Integer
  deriving stock (Eq, Show)

data ResearchVertex = ResearchSource | ResearchAcceptedA | ResearchAcceptedB
  deriving stock (Bounded, Enum, Eq, Show)

researchCommandA :: InCtor ResearchCommand ResearchInputFields
researchCommandA =
  InCtor
    { icName = "ResearchCommandA",
      icMatch = \case
        ResearchCommandA value -> Just (RCons (Proxy @"value") value RNil)
        ResearchCommandB _ -> Nothing,
      icBuild = \(RCons _ value RNil) -> ResearchCommandA value
    }

researchCommandB :: InCtor ResearchCommand ResearchInputFields
researchCommandB =
  InCtor
    { icName = "ResearchCommandB",
      icMatch = \case
        ResearchCommandA _ -> Nothing
        ResearchCommandB value -> Just (RCons (Proxy @"value") value RNil),
      icBuild = \(RCons _ value RNil) -> ResearchCommandB value
    }

researchWire :: WireCtor ResearchEvent (Integer, ())
researchWire =
  WireCtor
    { wcName = "ResearchObserved",
      wcMatch = \(ResearchObserved value) -> Just (value, ()),
      wcBuild = \(value, ()) -> ResearchObserved value
    }

researchOutputA :: OutTerm '[] ResearchCommand ResearchEvent
researchOutputA =
  OPack
    researchCommandA
    researchWire
    (OFCons (TInpCtorField researchCommandA ZIdx) OFNil)

researchOutputB :: OutTerm '[] ResearchCommand ResearchEvent
researchOutputB =
  OPack
    researchCommandB
    researchWire
    (OFCons (TInpCtorField researchCommandB ZIdx) OFNil)

researchGuardA :: HsPred '[] ResearchCommand
researchGuardA = PEq (TInpCtorField researchCommandA ZIdx) (TLit 0)

researchGuardB :: Integer -> HsPred '[] ResearchCommand
researchGuardB expected = PEq (TInpCtorField researchCommandB ZIdx) (TLit expected)

researchTransducer :: Integer -> SymTransducer (HsPred '[] ResearchCommand) '[] ResearchVertex ResearchCommand ResearchEvent
researchTransducer expectedB =
  SymTransducer
    { edgesOut = \case
        ResearchSource ->
          [ Edge researchGuardA UKeep [researchOutputA] ResearchAcceptedA Live,
            Edge (researchGuardB expectedB) UKeep [researchOutputB] ResearchAcceptedB Live
          ]
        ResearchAcceptedA -> []
        ResearchAcceptedB -> [],
      initial = ResearchSource,
      initialRegs = RNil,
      isFinal = (/= ResearchSource)
    }

actualCandidateCount :: Integer -> ResearchEvent -> Int
actualCandidateCount expectedB observed =
  length
    [ ()
    | edge <- edgesOut (researchTransducer expectedB) ResearchSource,
      outputTerm : _ <- [output edge],
      Just command <- [solveOutput outputTerm RNil observed],
      models (guard edge) (RNil, command)
    ]

spec :: Spec
spec = describe "full symbolic replay-inversion research" $ do
  describe "two candidate-scoped commands with shared registers" $ do
    it "keeps different command constructors independently eligible" $
      solveVerdict separateConstructorQuery `shouldReturn` InversionSatisfiable

    it "shows why one shared command constructor answers the wrong question" $
      solveVerdict singleConstructorNegativeControl `shouldReturn` InversionProvedDisjoint

    it "shares register values across candidates and agrees with finite concrete semantics" $ do
      solveVerdict sharedRegisterDisjointQuery `shouldReturn` InversionProvedDisjoint
      [r | r <- [-3 .. 3], r < 0 && r >= 0] `shouldBe` ([] :: [Integer])

    it "keeps same-constructor field correlations candidate-local" $
      solveVerdict sameConstructorCorrelatedFieldsQuery `shouldReturn` InversionSatisfiable

    it "keeps Either arms candidate-local" $
      solveVerdict separateEitherArmsQuery `shouldReturn` InversionSatisfiable

    it "keeps opaque occurrences candidate-local and not proved disjoint" $
      solveVerdict separateOpaqueAtomsQuery `shouldReturn` InversionSatisfiable

    it "uses structural register positions despite duplicate diagnostic labels" $
      solveVerdict duplicateDiagnosticLabelsQuery `shouldReturn` InversionSatisfiable

    it "passes Unknown and ProofError through the conservative proof gate" $ do
      let unknown = SBV.SatResult (SBV.Unknown SBV.z3 SBV.UnknownTimeOut)
          proofError = SBV.SatResult (SBV.ProofError SBV.z3 ["research-control"] Nothing)
      classifyResult unknown `shouldBe` InversionInconclusive
      classifyResult proofError `shouldBe` InversionInconclusive

  describe "typed shared observed-head relation" $ do
    it "proves an output-dependent pair disjoint and agrees with finite enumeration" $ do
      alignSchemas
        (singleIntegerSchema GeneratedDescriptor)
        (singleIntegerSchema GeneratedDescriptor)
        `shouldBe` ExactSchemaAlignment
      solveVerdict (sharedObservedHeadQuery 0 1) `shouldReturn` InversionProvedDisjoint
      concreteSharedHeadAmbiguities (== 0) (== 1) `shouldBe` []
      inversionAmbiguityWarnings (researchTransducer 1) `shouldSatisfy` (not . null)
      let candidateCounts =
            [ actualCandidateCount 1 (ResearchObserved observed)
            | observed <- [-3 .. 3]
            ]
      candidateCounts `shouldSatisfy` all (<= 1)

    it "finds the overlapping output-dependent control satisfiable" $ do
      solveVerdict (sharedObservedHeadQuery 0 0) `shouldReturn` InversionSatisfiable
      concreteSharedHeadAmbiguities (== 0) (== 0) `shouldBe` [0]
      actualCandidateCount 0 (ResearchObserved 0) `shouldBe` 2

    it "does not align equal diagnostic names with different existential carriers" $ do
      let integerSchema = singleIntegerSchema GeneratedDescriptor
          booleanSchema =
            integerSchema
              { schemaFields = [StructuralField 0 BooleanCarrier]
              }
      schemaDiagnosticName integerSchema `shouldBe` schemaDiagnosticName booleanSchema
      alignSchemas integerSchema booleanSchema
        `shouldBe` NoSafeSchemaAlignment "field positions or carriers differ"

    it "does not trust dishonest or unvalidated manual descriptors" $ do
      alignSchemas
        (singleIntegerSchema DishonestDescriptor)
        (singleIntegerSchema GeneratedDescriptor)
        `shouldBe` NoSafeSchemaAlignment "descriptor law is not established"
      alignSchemas
        (singleIntegerSchema UntrustedManualDescriptor)
        (singleIntegerSchema GeneratedDescriptor)
        `shouldBe` NoSafeSchemaAlignment "descriptor law is not established"

    it "classifies exact, observed-only, and conservative field forms" $ do
      fieldRelation TopLevelCommandField `shouldBe` EquateObservedWithCommand
      fieldRelation LiteralField `shouldBe` LeaveObservedUnconstrained
      fieldRelation RegisterAuditField `shouldBe` LeaveObservedUnconstrained
      fieldRelation ExactArithmeticDerivedField `shouldBe` EquateObservedWithDerivedValue
      fieldRelation ExactStructuralProjectionField `shouldBe` EquateObservedWithDerivedValue
      fieldRelation OpaqueApplicationDerivedField `shouldBe` DropUnsupportedRelation
      fieldRelation UnconstrainedProjectionField `shouldBe` DropUnsupportedRelation

    it "keeps a head-overlapping pair satisfiable even when tails would differ" $
      solveVerdict headOnlyTailControl `shouldReturn` InversionSatisfiable
