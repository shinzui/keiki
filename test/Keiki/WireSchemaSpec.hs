{-# LANGUAGE DuplicateRecordFields #-}
{-# OPTIONS_GHC -Wno-deprecations #-}

module Keiki.WireSchemaSpec (spec) where

import GHC.Generics (Generic)
import Keiki.Composition (leftWireCtor, rightWireCtor)
import Keiki.Core
import Keiki.Generics (FieldsOf, mkWireCtor, mkWireCtor0Via, mkWireCtorVia)
import Test.Hspec

data FirstPayload = FirstPayload
  { repeated :: Int,
    trailing :: Bool
  }
  deriving stock (Eq, Show, Generic)

data SecondPayload = SecondPayload
  { repeated :: Int
  }
  deriving stock (Eq, Show, Generic)

data SchemaEvent
  = First FirstPayload
  | Second SecondPayload
  | Empty
  deriving stock (Eq, Show, Generic)

wireFirst :: WireCtor SchemaEvent (FieldsOf FirstPayload)
wireFirst = mkWireCtorVia @"First"

wireFirstAgain :: WireCtor SchemaEvent (FieldsOf FirstPayload)
wireFirstAgain = mkWireCtorVia @"First"

wireSecond :: WireCtor SchemaEvent (FieldsOf SecondPayload)
wireSecond = mkWireCtorVia @"Second"

wireEmpty :: WireCtor SchemaEvent ()
wireEmpty = mkWireCtor0Via @"Empty"

manualFirst :: WireCtor SchemaEvent (FieldsOf FirstPayload)
manualFirst =
  WireCtor
    { wcName = "First",
      wcSchema = wireSchemaUnavailable,
      wcMatch = \case
        First payload -> Just (payload.repeated, (payload.trailing, ()))
        _ -> Nothing,
      wcBuild = \(value, (flag, ())) -> First (FirstPayload value flag)
    }

closureFirst :: WireCtor SchemaEvent (FieldsOf FirstPayload)
closureFirst =
  mkWireCtor
    "First"
    (\case First payload -> Just payload; _ -> Nothing)
    First

spec :: Spec
spec = do
  describe "trusted Generic wire schemas" $ do
    it "covers nullary, one-field, and multi-field constructors" $ do
      map
        someWireAvailability
        [ SomeWire wireEmpty,
          SomeWire wireSecond,
          SomeWire wireFirst
        ]
        `shouldBe` replicate 3 WireSchemaTrusted

    it "aligns independently derived bindings for the same constructor" $
      classifyWireHeads wireFirst wireFirstAgain
        `shouldBe` WireHeadsStructurallyEqual

    it "uses ordered field types rather than selector labels" $ do
      let first = wireFirst {wcName = "Repeated"}
          second = wireSecond {wcName = "Repeated"}
      classifyWireHeads first second
        `shouldBe` WireHeadsStructurallyDifferent

    it "keeps match/build round trips unchanged" $ do
      wcMatch wireFirst (First (FirstPayload 7 True))
        `shouldBe` Just (7, (True, ()))
      wcBuild wireSecond (9, ())
        `shouldBe` Second (SecondPayload 9)
      wcMatch wireEmpty Empty `shouldBe` Just ()

  describe "unavailable schemas" $ do
    it "marks manual records and closure-taking helpers unavailable" $ do
      wireSchemaAvailability manualFirst.wcSchema
        `shouldBe` WireSchemaUnavailable
      wireSchemaAvailability closureFirst.wcSchema
        `shouldBe` WireSchemaUnavailable

    it "uses the legacy name fallback only for unavailable evidence" $ do
      wireHeadsMayAliasForDefault manualFirst wireFirst `shouldBe` True
      wireHeadsMayAliasForDefault
        (manualFirst {wcName = "Other"})
        wireFirst
        `shouldBe` False

  describe "checked Either composition" $ do
    it "preserves schemas on a repeated arm" $ do
      let leftA = leftWireCtor wireFirst :: WireCtor (Either SchemaEvent SchemaEvent) (FieldsOf FirstPayload)
          leftB = leftWireCtor wireFirstAgain :: WireCtor (Either SchemaEvent SchemaEvent) (FieldsOf FirstPayload)
      wireSchemaAvailability leftA.wcSchema `shouldBe` WireSchemaTrusted
      classifyWireHeads leftA leftB `shouldBe` WireHeadsStructurallyEqual

    it "prefixes opposite arms into structurally different paths" $ do
      let left = leftWireCtor wireFirst :: WireCtor (Either SchemaEvent SchemaEvent) (FieldsOf FirstPayload)
          right = rightWireCtor wireFirst :: WireCtor (Either SchemaEvent SchemaEvent) (FieldsOf FirstPayload)
      classifyWireHeads left right `shouldBe` WireHeadsStructurallyDifferent
      wireHeadsMayAliasForDefault left right `shouldBe` False

    it "does not strengthen an unavailable schema" $ do
      let lifted = leftWireCtor manualFirst :: WireCtor (Either SchemaEvent Bool) (FieldsOf FirstPayload)
      wireSchemaAvailability lifted.wcSchema
        `shouldBe` WireSchemaUnavailable

    it "keeps proper-prefix trusted paths may-alias" $
      wireSchemaPrefixRelationForTesting
        `shouldBe` WireHeadsUnwitnessed

data SomeWire co where
  SomeWire :: WireCtor co fields -> SomeWire co

someWireAvailability :: SomeWire co -> WireSchemaAvailability
someWireAvailability (SomeWire wire) = wireSchemaAvailability wire.wcSchema
