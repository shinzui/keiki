{-# LANGUAGE BlockArguments #-}

-- | Acceptance tests for the 'Data.Profunctor.Choice.Choice' instance
-- on 'SomeSymTransducer' (EP-29 of MasterPlan 9, M1).
--
-- The Choice instance routes @Either@-shaped inputs to one of two
-- arms: @left'@ wraps the underlying transducer into the @Left@ arm
-- and lifts an identity transducer into the @Right@ arm; @right'@ is
-- the symmetric routing. The implementation delegates to
-- 'Keiki.Composition.alternative' with 'identityTransducer' on the
-- pass-through arm.
--
-- Fixture: 'Keiki.Fixtures.EmailDelivery' wrapped in
-- 'someSymTransducer'. The tests cover:
--
--   * Forward routing — a @Left@ input lands on the wrapped arm's
--     edges and emits a @Left@ wire event; a @Right@ input passes
--     straight through unchanged.
--   * Survival of 'Keiki.Symbolic.isSingleValuedSym'.
--   * Sentinel preservation: @left' Cat.id == Cat.id@ on the wrapper
--     by construction (the instance returns 'SomeSymIdentity' on the
--     sentinel arm).
module Keiki.ChoiceSpec (spec) where

import Control.Category qualified as Cat
import Data.Profunctor (Choice (..))
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import Keiki.Core
import Keiki.Fixtures.ComposeStateful
import Keiki.Fixtures.CounterPipeline
import Keiki.Fixtures.EmailDelivery
import Keiki.LawHelpers (emittedLog, runScript)
import Keiki.Profunctor
import Keiki.Symbolic (isSingleValuedSym, withSymPred)
import Test.Hspec

-- * Fixtures ----------------------------------------------------------------

sampleAt :: UTCTime
sampleAt = UTCTime (fromGregorian 2026 5 9) (secondsToDiffTime 0)

sampleSendEmail :: EmailCmd
sampleSendEmail =
  SendEmail
    SendEmailData
      { recipient = "alice@example.com",
        subject = "hello",
        at = sampleAt
      }

sampleEmailEvent :: EmailEvent
sampleEmailEvent =
  EmailSent
    EmailSentData
      { recipient = "alice@example.com",
        subject = "hello",
        at = sampleAt
      }

someEmail :: SomeSymTransducer EmailCmd EmailEvent
someEmail = someSymTransducer emailDelivery

-- | Fold 'step' over inputs, retaining state between steps and
-- collecting each step's emissions.
runSteps :: SomeSymTransducer ci co -> [ci] -> Maybe [[co]]
runSteps (SomeSymTransducer t) inputs = go (initial t, initialRegs t) inputs
  where
    go _ [] = Just []
    go st (ci : rest) = case step t st ci of
      Nothing -> Nothing
      Just (s', regs', cos_) -> (cos_ :) <$> go (s', regs') rest
runSteps SomeSymIdentity inputs = Just (map (: []) inputs)

-- * Specs -------------------------------------------------------------------

spec :: Spec
spec = do
  describe "left'" $ do
    it "Left input routes through the wrapped transducer" $ do
      let routedLeft :: SomeSymTransducer (Either EmailCmd Int) (Either EmailEvent Int)
          routedLeft = left' someEmail
      case routedLeft of
        SomeSymTransducer t ->
          omega t (initial t) (initialRegs t) (Left sampleSendEmail)
            `shouldBe` [(Left sampleEmailEvent)]
        SomeSymIdentity ->
          expectationFailure
            "left' (someSymTransducer emailDelivery) unexpectedly returned \
            \the identity sentinel"

    it "Right input passes through unchanged on the identity arm" $ do
      let routedLeft :: SomeSymTransducer (Either EmailCmd Int) (Either EmailEvent Int)
          routedLeft = left' someEmail
      case routedLeft of
        SomeSymTransducer t ->
          omega t (initial t) (initialRegs t) (Right (42 :: Int))
            `shouldBe` [(Right 42)]
        SomeSymIdentity ->
          expectationFailure
            "left' (someSymTransducer emailDelivery) unexpectedly returned \
            \the identity sentinel"

    it "preserves Cat.id on the sentinel: left' Cat.id == Cat.id" $ do
      let lifted :: SomeSymTransducer (Either Int Bool) (Either Int Bool)
          lifted = left' (Cat.id :: SomeSymTransducer Int Int)
      case lifted of
        SomeSymIdentity -> pure ()
        SomeSymTransducer _ ->
          expectationFailure "left' Cat.id should preserve the identity sentinel"

    it "composes statefully with another left' result" $ do
      let bL =
            left' (someSymTransducer stageB) ::
              SomeSymTransducer (Either MsgB Bool) (Either MsgC Bool)
          cL =
            left' (someSymTransducer stageC) ::
              SomeSymTransducer (Either MsgC Bool) (Either MsgD Bool)
      runSteps (cL Cat.. bL) [Left (MsgB 1), Right True, Left (MsgB 2)]
        `shouldBe` Just [[Left (MsgD 2)], [Right True], [Left (MsgD 5)]]

    it "evolves independently over an interleaved four-command script" $ do
      let lifted =
            left' (someSymTransducer counterSource) ::
              SomeSymTransducer (Either SourceCmd Bool) (Either MidVal Bool)
          script = [Left Tick, Right True, Left Tick, Right False]
      case lifted of
        SomeSymTransducer transducer -> do
          runScript transducer script
            `shouldBe` [ [Left (MidVal 0)],
                         [Right True],
                         [Left (MidVal 1)],
                         [Right False]
                       ]
          case reconstituteEither transducer (emittedLog transducer script) of
            Right _ -> pure ()
            Left _ -> expectationFailure "Choice replay failed"
        SomeSymIdentity -> expectationFailure "left' stateful fixture returned identity"

  describe "right'" $ do
    it "Right input routes through the wrapped transducer" $ do
      let routedRight :: SomeSymTransducer (Either Int EmailCmd) (Either Int EmailEvent)
          routedRight = right' someEmail
      case routedRight of
        SomeSymTransducer t ->
          omega t (initial t) (initialRegs t) (Right sampleSendEmail)
            `shouldBe` [(Right sampleEmailEvent)]
        SomeSymIdentity ->
          expectationFailure
            "right' (someSymTransducer emailDelivery) unexpectedly returned \
            \the identity sentinel"

    it "Left input passes through unchanged on the identity arm" $ do
      let routedRight :: SomeSymTransducer (Either Int EmailCmd) (Either Int EmailEvent)
          routedRight = right' someEmail
      case routedRight of
        SomeSymTransducer t ->
          omega t (initial t) (initialRegs t) (Left (7 :: Int))
            `shouldBe` [(Left 7)]
        SomeSymIdentity ->
          expectationFailure
            "right' (someSymTransducer emailDelivery) unexpectedly returned \
            \the identity sentinel"

    it "preserves Cat.id on the sentinel: right' Cat.id == Cat.id" $ do
      let lifted :: SomeSymTransducer (Either Bool Int) (Either Bool Int)
          lifted = right' (Cat.id :: SomeSymTransducer Int Int)
      case lifted of
        SomeSymIdentity -> pure ()
        SomeSymTransducer _ ->
          expectationFailure "right' Cat.id should preserve the identity sentinel"

    it "composes statefully with another right' result" $ do
      let bR =
            right' (someSymTransducer stageB) ::
              SomeSymTransducer (Either Bool MsgB) (Either Bool MsgC)
          cR =
            right' (someSymTransducer stageC) ::
              SomeSymTransducer (Either Bool MsgC) (Either Bool MsgD)
      runSteps (cR Cat.. bR) [Right (MsgB 1), Left False, Right (MsgB 2)]
        `shouldBe` Just [[Right (MsgD 2)], [Left False], [Right (MsgD 5)]]

  describe "isSingleValuedSym survives left' / right'" $ do
    it "single-valuedness is preserved across left'" $
      case left' someEmail ::
             SomeSymTransducer (Either EmailCmd Int) (Either EmailEvent Int) of
        SomeSymTransducer t ->
          isSingleValuedSym (withSymPred t) `shouldBe` True
        SomeSymIdentity ->
          expectationFailure
            "left' on a non-identity wrapper returned the identity sentinel"

    it "single-valuedness is preserved across right'" $
      case right' someEmail ::
             SomeSymTransducer (Either Int EmailCmd) (Either Int EmailEvent) of
        SomeSymTransducer t ->
          isSingleValuedSym (withSymPred t) `shouldBe` True
        SomeSymIdentity ->
          expectationFailure
            "right' on a non-identity wrapper returned the identity sentinel"
