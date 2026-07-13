{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE GADTs #-}

-- | Reusable decide/replay round-trip properties for keiki test fixtures.
module Keiki.RoundTrip
  ( RoundTripFixture (..),
    TamperExpectation (..),
    TamperCase (..),
    roundTripSpec,
    teethSpec,
    genUTCTime,
    genShortText,
    genFromPool,
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Keiki.Core
  ( HsPred,
    RegFile,
    ReplayFailure,
    SymTransducer (..),
    applyEventsEither,
    defaultValidationOptions,
    reconstituteEither,
    step,
    validateTransducer,
  )
import Test.Hspec (Spec, describe, it, shouldBe, shouldNotBe)
import Test.QuickCheck
  ( Gen,
    Property,
    checkCoverage,
    chooseInt,
    chooseInteger,
    counterexample,
    cover,
    elements,
    expectFailure,
    forAllShrinkShow,
    frequency,
    property,
    shrinkList,
    sized,
    vectorOf,
    (===),
  )

-- | What a fixture-specific log mutation promises.
data TamperExpectation = MustFailReplay | MustNotSilentlyMatch

-- | A semantically justified mutation of an event log.
data TamperCase co = TamperCase
  { tcName :: String,
    tcMutate :: [co] -> Maybe [co],
    tcExpect :: TamperExpectation
  }

-- | Everything the generic properties need for one aggregate.
data RoundTripFixture where
  RoundTripFixture ::
    (Bounded s, Enum s, Eq s, Ord s, Show s, Show ci, Eq co, Show co) =>
    { rtName :: String,
      rtTransducer :: SymTransducer (HsPred rs ci) rs s ci co,
      rtGenCommand :: s -> RegFile rs -> Gen ci,
      rtObserve :: s -> RegFile rs -> Text,
      rtTamperCases :: [TamperCase co]
    } ->
    RoundTripFixture

data StepMark = Accepted | Rejected | Epsilon

data TraceStep s ci co = TraceStep
  { tsCommand :: ci,
    tsMark :: StepMark,
    tsEvents :: [co],
    tsState :: s,
    tsObservation :: Text
  }

data ForwardRun s ci co = ForwardRun
  { frTrace :: [TraceStep s ci co],
    frEvents :: [co],
    frFinalState :: s,
    frFinalObservation :: Text
  }

roundTripSpec :: RoundTripFixture -> Spec
roundTripSpec (RoundTripFixture name transducer genCommand observe tamperCases) =
  describe name do
    it "passes validateTransducer with defaultValidationOptions" $
      validateTransducer defaultValidationOptions transducer `shouldBe` []
    it "P1: whole-log replay reproduces the forward state" $
      wholeLogProperty transducer genCommand observe
    it "P2: chunked replay agrees at every command boundary" $
      chunkedProperty transducer genCommand observe
    mapM_ (tamperSpec transducer genCommand observe) tamperCases

teethSpec :: RoundTripFixture -> Spec
teethSpec (RoundTripFixture name transducer genCommand observe _tamperCases) =
  describe (name <> " (teeth)") do
    it "default validation rejects the fixture" $
      validateTransducer defaultValidationOptions transducer `shouldNotBe` []
    it "P1: whole-log replay detects the defect" $
      expectFailure (wholeLogProperty transducer genCommand observe)
    it "P2: chunked replay detects the defect" $
      expectFailure (chunkedProperty transducer genCommand observe)

wholeLogProperty ::
  (Eq s, Show s, Show ci, Eq co, Show co) =>
  SymTransducer (HsPred rs ci) rs s ci co ->
  (s -> RegFile rs -> Gen ci) ->
  (s -> RegFile rs -> Text) ->
  Property
wholeLogProperty transducer genCommand observe =
  forAllCommands transducer genCommand $ \commands ->
    let run = forwardRun transducer observe commands
        result = reconstituteEither transducer run.frEvents
        context = renderRun run <> "\nreplay: " <> renderReplay observe result
     in counterexample context case result of
          Left _ -> property False
          Right (replayState, replayRegs) ->
            (replayState, observe replayState replayRegs)
              === (run.frFinalState, run.frFinalObservation)

chunkedProperty ::
  (Eq s, Show s, Show ci, Eq co, Show co) =>
  SymTransducer (HsPred rs ci) rs s ci co ->
  (s -> RegFile rs -> Gen ci) ->
  (s -> RegFile rs -> Text) ->
  Property
chunkedProperty transducer genCommand observe =
  forAllCommands transducer genCommand $ \commands ->
    let run = forwardRun transducer observe commands
        result = replayChunks (transducer.initial, transducer.initialRegs) run.frTrace
        context = renderRun run <> "\nchunked replay: " <> renderChunkResult result
     in counterexample context case result of
          Left _ -> property False
          Right (replayState, replayRegs) ->
            (replayState, observe replayState replayRegs)
              === (run.frFinalState, run.frFinalObservation)
  where
    replayChunks seed [] = Right seed
    replayChunks seed (traceStep : rest) = case traceStep.tsMark of
      Rejected -> replayChunks seed rest
      Accepted -> advance seed traceStep
      Epsilon -> advance seed traceStep
      where
        advance current stepResult = do
          next@(actualState, actualRegs) <-
            case applyEventsEither transducer current stepResult.tsEvents of
              Left replayFailure -> Left ("replay failure: " <> show replayFailure)
              Right replayed -> Right replayed
          if (actualState, observe actualState actualRegs)
            == (stepResult.tsState, stepResult.tsObservation)
            then replayChunks next rest
            else
              Left
                ( "boundary mismatch after "
                    <> show stepResult.tsCommand
                    <> ": expected "
                    <> renderState stepResult.tsState stepResult.tsObservation
                    <> ", got "
                    <> renderState actualState (observe actualState actualRegs)
                )

tamperSpec ::
  (Eq s, Show s, Show ci, Eq co, Show co) =>
  SymTransducer (HsPred rs ci) rs s ci co ->
  (s -> RegFile rs -> Gen ci) ->
  (s -> RegFile rs -> Text) ->
  TamperCase co ->
  Spec
tamperSpec transducer genCommand observe tamperCase =
  it ("tamper: " <> tamperCase.tcName) $
    checkCoverage $
      forAllCommands transducer genCommand $ \commands ->
        let run = forwardRun transducer observe commands
         in case tamperCase.tcMutate run.frEvents of
              Nothing ->
                cover 30 False "mutation applies" (property True)
              Just mutatedEvents ->
                let replay = reconstituteEither transducer mutatedEvents
                    context =
                      renderRun run
                        <> "\nmutated log:\n  "
                        <> show mutatedEvents
                        <> "\nmutated replay: "
                        <> renderReplay observe replay
                    assertion = case tamperCase.tcExpect of
                      MustFailReplay -> case replay of
                        Left _ -> property True
                        Right _ -> property False
                      MustNotSilentlyMatch -> case replay of
                        Left _ -> property True
                        Right (replayState, replayRegs) ->
                          property $
                            (replayState, observe replayState replayRegs)
                              /= (run.frFinalState, run.frFinalObservation)
                 in cover 30 True "mutation applies" (counterexample context assertion)

forAllCommands ::
  (Show ci) =>
  SymTransducer (HsPred rs ci) rs s ci co ->
  (s -> RegFile rs -> Gen ci) ->
  ([ci] -> Property) ->
  Property
forAllCommands transducer genCommand =
  forAllShrinkShow
    (genCommands transducer genCommand)
    (shrinkList (const []))
    renderCommands

genCommands ::
  SymTransducer (HsPred rs ci) rs s ci co ->
  (s -> RegFile rs -> Gen ci) ->
  Gen [ci]
genCommands transducer genCommand = sized $ \size -> do
  count <- chooseInt (1, max 1 (min 15 size))
  go count transducer.initial transducer.initialRegs
  where
    go 0 _ _ = pure []
    go remaining state regs = do
      command <- genCommand state regs
      let next = case step transducer (state, regs) command of
            Nothing -> (state, regs)
            Just (state', regs', _) -> (state', regs')
      rest <- go (remaining - 1) (fst next) (snd next)
      pure (command : rest)

forwardRun ::
  SymTransducer (HsPred rs ci) rs s ci co ->
  (s -> RegFile rs -> Text) ->
  [ci] ->
  ForwardRun s ci co
forwardRun transducer observe = go transducer.initial transducer.initialRegs [] []
  where
    go state regs traceRev eventsRev [] =
      ForwardRun
        { frTrace = reverse traceRev,
          frEvents = concat (reverse eventsRev),
          frFinalState = state,
          frFinalObservation = observe state regs
        }
    go state regs traceRev eventsRev (command : commands) =
      case step transducer (state, regs) command of
        Nothing ->
          go
            state
            regs
            (TraceStep command Rejected [] state (observe state regs) : traceRev)
            eventsRev
            commands
        Just (nextState, nextRegs, events) ->
          let mark = if null events then Epsilon else Accepted
           in go
                nextState
                nextRegs
                (TraceStep command mark events nextState (observe nextState nextRegs) : traceRev)
                (events : eventsRev)
                commands

renderCommands :: (Show ci) => [ci] -> String
renderCommands commands =
  "commands:\n"
    <> unlines
      [ "  " <> show index <> ". " <> show command
      | (index, command) <- zip [(1 :: Int) ..] commands
      ]

renderRun :: (Show s, Show ci, Show co) => ForwardRun s ci co -> String
renderRun run =
  "commands (* accepted, - rejected, epsilon accepted-with-zero-output):\n"
    <> unlines
      [ "  " <> show index <> ". " <> renderMark traceStep.tsMark <> " " <> show traceStep.tsCommand
      | (index, traceStep) <- zip [(1 :: Int) ..] run.frTrace
      ]
    <> "event log:\n  "
    <> show run.frEvents
    <> "\nforward final: "
    <> renderState run.frFinalState run.frFinalObservation

renderMark :: StepMark -> String
renderMark Accepted = "*"
renderMark Rejected = "-"
renderMark Epsilon = "epsilon"

renderState :: (Show s) => s -> Text -> String
renderState state observation = show state <> " | " <> Text.unpack observation

renderReplay :: (Show s, Show co) => (s -> RegFile rs -> Text) -> Either (ReplayFailure s co) (s, RegFile rs) -> String
renderReplay observe = \case
  Left failure -> "Left " <> show failure
  Right (state, regs) -> "Right (" <> renderState state (observe state regs) <> ")"

renderChunkResult :: (Show s) => Either String (s, RegFile rs) -> String
renderChunkResult = \case
  Left message -> "Left (" <> message <> ")"
  Right (state, _) -> "Right (" <> show state <> ")"

-- | Whole-second timestamps keep generated values and counterexamples compact.
genUTCTime :: Gen UTCTime
genUTCTime =
  posixSecondsToUTCTime . fromInteger <$> chooseInteger (0, 2_000_000_000)

-- | A compact text generator suitable for domain identifiers and payloads.
genShortText :: Gen Text
genShortText = do
  length' <- chooseInt (1, 10)
  Text.pack <$> vectorOf length' (elements ['a' .. 'z'])

-- | Prefer a collision-friendly pool while retaining arbitrary short values.
genFromPool :: [Text] -> Gen Text
genFromPool [] = genShortText
genFromPool pool = frequency [(4, elements pool), (1, genShortText)]
