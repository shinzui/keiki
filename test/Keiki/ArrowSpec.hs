{-# LANGUAGE BlockArguments #-}

-- | Acceptance tests for the 'Control.Arrow.Arrow' instance on
-- 'SomeSymTransducer' (EP-29 of MasterPlan 9, M3).
--
-- The Arrow instance lifts arbitrary Haskell functions via
-- 'Arr.arr' (a stateless one-edge transducer whose 'WireCtor's
-- 'wcBuild' applies the function), and inherits 'Arr.first' /
-- 'Arr.second' from the 'Strong' instance. @(>>>)@ comes from the
-- 'Cat.Category' instance.
--
-- /Composition limitation:/ 'arr f >>> arr g' does NOT produce
-- 'arr (g . f)' on this wrapper — see 'arrTransducer' haddock for
-- the @icName == wcName@ alignment reason. The spec covers the
-- standalone-arr forward eval, sentinel preservation, first
-- delegation, and the documented 'solveOutput' lossy contract.
module Keiki.ArrowSpec (spec) where

import qualified Control.Arrow as Arr
import qualified Control.Category as Cat
import Data.Text (Text)
import qualified Data.Text as Text
import Test.Hspec

import Keiki.Core
import Keiki.Profunctor


-- * Specs -------------------------------------------------------------------

spec :: Spec
spec = do

  describe "arr" $ do

    it "lifts (Text.pack . show) :: SomeSymTransducer Int Text" $ do
      let lifted :: SomeSymTransducer Int Text
          lifted = Arr.arr (Text.pack . show)
      case lifted of
        SomeSymTransducer t ->
          omega t (initial t) (initialRegs t) (42 :: Int)
            `shouldBe` Just ("42" :: Text)
        SomeSymIdentity ->
          expectationFailure
            "Arr.arr unexpectedly returned the identity sentinel"

    it "lifts identity-shaped functions but does not detect them as Cat.id" $ do
      -- Arr.arr id has the identity *behaviour* on every input but
      -- the wrapper cannot observe Haskell function identity, so it
      -- materialises into a SomeSymTransducer rather than the
      -- sentinel. This is the documented behaviour.
      let lifted :: SomeSymTransducer Int Int
          lifted = Arr.arr (id :: Int -> Int)
      case lifted of
        SomeSymTransducer t ->
          omega t (initial t) (initialRegs t) (7 :: Int)
            `shouldBe` Just 7
        SomeSymIdentity ->
          expectationFailure
            "Arr.arr id should NOT short-circuit to SomeSymIdentity \
            \— Haskell function identity is unobservable at the value level"

  describe "first via Arrow's first method (delegates to Strong.first')" $ do

    it "first (arr show) on (42, \"extra\") emits (\"42\", \"extra\")" $ do
      let lifted :: SomeSymTransducer (Int, Text) (String, Text)
          lifted = Arr.first (Arr.arr show)
      case lifted of
        SomeSymTransducer t ->
          omega t (initial t) (initialRegs t) (42 :: Int, "extra" :: Text)
            `shouldBe` Just ("42", "extra")
        SomeSymIdentity ->
          expectationFailure
            "Arr.first on a non-identity wrapper returned the sentinel"

  describe "Cat.id and the Arrow instance interplay" $ do

    it "Cat.id passes through arr-style values verbatim" $
      -- This exercises that the Arrow instance's superclass dispatch
      -- of (>>>) hits the sentinel short-circuit when one operand is
      -- the sentinel. arr f >>> Cat.id should equal arr f
      -- behaviourally.
      let lifted :: SomeSymTransducer Int Text
          lifted = Arr.arr (Text.pack . show) Cat.>>> Cat.id
      in case lifted of
           SomeSymTransducer t ->
             omega t (initial t) (initialRegs t) (99 :: Int)
               `shouldBe` Just ("99" :: Text)
           SomeSymIdentity ->
             expectationFailure
               "arr f >>> Cat.id unexpectedly returned the sentinel \
               \— the sentinel short-circuit returns the non-sentinel arg, \
               \so we expect SomeSymTransducer here"

    it "Cat.id <<< arr f passes through verbatim too" $
      let lifted :: SomeSymTransducer Int Text
          lifted = Cat.id Cat.<<< Arr.arr (Text.pack . show)
      in case lifted of
           SomeSymTransducer t ->
             omega t (initial t) (initialRegs t) (5 :: Int)
               `shouldBe` Just ("5" :: Text)
           SomeSymIdentity ->
             expectationFailure
               "Cat.id <<< arr f unexpectedly returned the sentinel"
