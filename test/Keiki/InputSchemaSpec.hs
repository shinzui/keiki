{-# LANGUAGE DuplicateRecordFields #-}
{-# OPTIONS_GHC -Wno-deprecations #-}

module Keiki.InputSchemaSpec (spec) where

import Control.Exception (evaluate)
import Data.Proxy (Proxy (..))
import GHC.Generics (Generic)
import Keiki.Composition (leftInCtor, rightInCtor)
import Keiki.Core
import Keiki.Generics (RegFieldsOf, mkInCtor, mkInCtorVia)
import Test.Hspec

data OnePayload = OnePayload
  { value :: Int
  }
  deriving stock (Eq, Show, Generic)

data ManyPayload = ManyPayload
  { value :: Int,
    enabled :: Bool
  }
  deriving stock (Eq, Show, Generic)

data SchemaCommand
  = Empty
  | One OnePayload
  | Many ManyPayload
  deriving stock (Eq, Show, Generic)

inEmpty :: InCtor SchemaCommand '[]
inEmpty = mkInCtorVia @"Empty"

inOne :: InCtor SchemaCommand (RegFieldsOf OnePayload)
inOne = mkInCtorVia @"One"

inOneAgain :: InCtor SchemaCommand (RegFieldsOf OnePayload)
inOneAgain = mkInCtorVia @"One"

inMany :: InCtor SchemaCommand (RegFieldsOf ManyPayload)
inMany = mkInCtorVia @"Many"

manualOne :: InCtor SchemaCommand (RegFieldsOf OnePayload)
manualOne =
  unavailableInCtor
    "One"
    ( \case
        One payload -> Just (RCons (Proxy @"value") payload.value RNil)
        _ -> Nothing
    )
    (\(RCons _ field RNil) -> One (OnePayload field))

closureOne :: InCtor SchemaCommand (RegFieldsOf OnePayload)
closureOne =
  mkInCtor
    "One"
    (\case One payload -> Just payload; _ -> Nothing)
    One

spec :: Spec
spec = do
  describe "trusted Generic input schemas" $ do
    it "covers nullary, one-field, and multi-field constructors" $
      map
        someInputAvailability
        [ SomeInput inEmpty,
          SomeInput inOne,
          SomeInput inMany
        ]
        `shouldBe` replicate 3 InCtorSchemaTrusted

    it "aligns independently derived bindings for the same constructor" $
      classifyInputHeads inOne inOneAgain
        `shouldBe` InputHeadsStructurallyEqual

    it "uses structure rather than diagnostic names" $ do
      let one = renameInCtor "Repeated" inOne
          many = renameInCtor "Repeated" inMany
      classifyInputHeads one many
        `shouldBe` InputHeadsStructurallyDifferent

    it "preserves trusted evidence and behavior when renamed" $ do
      let renamed = renameInCtor "RenamedOne" inOne
      renamed.icName `shouldBe` "RenamedOne"
      inCtorSchemaAvailability renamed.icSchema `shouldBe` InCtorSchemaTrusted
      case renamed.icMatch (One (OnePayload 7)) of
        Just fields -> renamed.icBuild fields `shouldBe` One (OnePayload 7)
        Nothing -> expectationFailure "renamed trusted input constructor did not match"

    it "keeps match/build round trips unchanged" $ do
      case icMatch inOne (One (OnePayload 7)) of
        Just fields -> fields ! #value `shouldBe` 7
        Nothing -> expectationFailure "trusted input constructor did not match"
      icBuild
        inMany
        ( RCons
            (Proxy @"value")
            9
            (RCons (Proxy @"enabled") True RNil)
        )
        `shouldBe` Many (ManyPayload 9 True)
      case icMatch inEmpty Empty of
        Just RNil -> pure ()
        Nothing -> expectationFailure "trusted nullary input constructor did not match"

  describe "unavailable input schemas" $
    it "marks manual constructors and closure-taking helpers unavailable" $ do
      inCtorSchemaAvailability manualOne.icSchema
        `shouldBe` InCtorSchemaUnavailable
      inCtorSchemaAvailability closureOne.icSchema
        `shouldBe` InCtorSchemaUnavailable

  describe "checked Either composition" $ do
    it "preserves schemas on a repeated arm" $ do
      let leftA = leftInCtor inOne :: InCtor (Either SchemaCommand SchemaCommand) (RegFieldsOf OnePayload)
          leftB = leftInCtor inOneAgain :: InCtor (Either SchemaCommand SchemaCommand) (RegFieldsOf OnePayload)
      inCtorSchemaAvailability leftA.icSchema
        `shouldBe` InCtorSchemaTrusted
      classifyInputHeads leftA leftB
        `shouldBe` InputHeadsStructurallyEqual

    it "prefixes opposite arms into structurally different paths" $ do
      let left = leftInCtor inOne :: InCtor (Either SchemaCommand SchemaCommand) (RegFieldsOf OnePayload)
          right = rightInCtor inOne :: InCtor (Either SchemaCommand SchemaCommand) (RegFieldsOf OnePayload)
      classifyInputHeads left right
        `shouldBe` InputHeadsStructurallyDifferent

    it "does not strengthen unavailable evidence" $ do
      let lifted = leftInCtor manualOne :: InCtor (Either SchemaCommand Bool) (RegFieldsOf OnePayload)
      inCtorSchemaAvailability lifted.icSchema
        `shouldBe` InCtorSchemaUnavailable

    it "keeps proper-prefix trusted paths may-alias" $
      inCtorSchemaPrefixRelationForTesting
        `shouldBe` InputHeadsUnwitnessed

  describe "trusted construction capability" $
    it "bottoms when the capability argument is bottom" $
      evaluate
        ( trustedInCtorInternal undefined "Forged" inCtorSchemaUnavailable (const Nothing) (\RNil -> Empty) ::
            InCtor SchemaCommand '[]
        )
        `shouldThrow` anyException

data SomeInput ci where
  SomeInput :: InCtor ci fields -> SomeInput ci

someInputAvailability :: SomeInput ci -> InCtorSchemaAvailability
someInputAvailability (SomeInput inputCtor) =
  inCtorSchemaAvailability inputCtor.icSchema
