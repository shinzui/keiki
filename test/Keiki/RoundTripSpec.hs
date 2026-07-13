{-# LANGUAGE BlockArguments #-}

module Keiki.RoundTripSpec (spec) where

import Data.Text (Text)
import Data.Text qualified as Text
import Keiki.Core
import Keiki.Fixtures.BrokenTailCoverage qualified as Broken
import Keiki.Fixtures.CounterPipeline qualified as Counter
import Keiki.Fixtures.EmailDelivery qualified as Email
import Keiki.Fixtures.RegisterEmission qualified as Register
import Keiki.Fixtures.SplitCoverage qualified as Split
import Keiki.Fixtures.UserRegistration qualified as User
import Keiki.RoundTrip
import Test.Hspec (Spec, describe, it, shouldSatisfy)
import Test.QuickCheck (Gen, elements, frequency)

spec :: Spec
spec = do
  mapM_ roundTripSpec allFixtures
  teethSpec stateChangingEpsilonFixture
  teethSpec brokenTailCoverageFixture
  teethSpec counterPipelineFixture
  describe "validator/teeth agreement" do
    it "classifies the silent transition as StateChangingEpsilon" $
      validateTransducer defaultValidationOptions stateChangingEpsilon
        `shouldSatisfy` any isStateChangingEpsilon
    it "classifies BrokenTailCoverage as HeadUnrecoverable" $
      validateTransducer defaultValidationOptions Broken.brokenTailCoverage
        `shouldSatisfy` any isHeadUnrecoverable

allFixtures :: [RoundTripFixture]
allFixtures =
  [ emailDeliveryFixture,
    userRegistrationFixture,
    registerEmissionFixture,
    splitCoverageFixture
  ]

emailDeliveryFixture :: RoundTripFixture
emailDeliveryFixture =
  RoundTripFixture
    { rtName = "EmailDelivery",
      rtTransducer = Email.emailDelivery,
      rtGenCommand = \_ _ -> Email.SendEmail <$> genSendEmailData,
      rtObserve = observeEmail,
      rtTamperCases = emailTamperCases
    }

genSendEmailData :: Gen Email.SendEmailData
genSendEmailData =
  Email.SendEmailData
    <$> genShortText
    <*> genShortText
    <*> genUTCTime

observeEmail :: Email.EmailVertex -> RegFile Email.EmailRegs -> Text
observeEmail Email.EmailPending _ = "(no slots)"
observeEmail Email.EmailSentVertex regs =
  Text.pack $
    "recipient="
      <> show (regs ! #emailRecipient)
      <> " subject="
      <> show (regs ! #emailSubject)
      <> " sentAt="
      <> show (regs ! #emailSentAt)

emailTamperCases :: [TamperCase Email.EmailEvent]
emailTamperCases =
  [ TamperCase
      { tcName = "drop only event",
        tcMutate = \case
          [_] -> Just []
          _ -> Nothing,
        tcExpect = MustNotSilentlyMatch
      },
    TamperCase
      { tcName = "duplicate event",
        tcMutate = \case
          [event] -> Just [event, event]
          _ -> Nothing,
        tcExpect = MustFailReplay
      }
  ]

userRegistrationFixture :: RoundTripFixture
userRegistrationFixture =
  RoundTripFixture
    { rtName = "UserRegistration",
      rtTransducer = User.userReg,
      rtGenCommand = genUserCommand,
      rtObserve = observeUser,
      rtTamperCases = userTamperCases
    }

genUserCommand :: User.Vertex -> RegFile User.UserRegRegs -> Gen User.UserCmd
genUserCommand User.PotentialCustomer _ =
  frequency
    [ (8, User.StartRegistration <$> genStartRegistrationData),
      (1, User.ConfirmAccount <$> genConfirmAccountData "wrong"),
      (1, User.FulfillGDPRRequest . User.FulfillGDPRRequestData <$> genUTCTime)
    ]
genUserCommand User.RequiresConfirmation regs =
  frequency
    [ (5, User.ConfirmAccount <$> genConfirmAccountData (regs ! #confirmCode)),
      (2, User.ConfirmAccount <$> genConfirmAccountData "wrong"),
      (4, User.ResendConfirmation <$> genResendConfirmationData),
      (2, User.FulfillGDPRRequest . User.FulfillGDPRRequestData <$> genUTCTime)
    ]
genUserCommand User.Confirmed _ =
  frequency
    [ (8, User.FulfillGDPRRequest . User.FulfillGDPRRequestData <$> genUTCTime),
      (1, User.StartRegistration <$> genStartRegistrationData)
    ]
genUserCommand User.Deleted _ = arbitraryUserCommand

genStartRegistrationData :: Gen User.StartRegistrationData
genStartRegistrationData =
  User.StartRegistrationData
    <$> genShortText
    <*> genFromPool ["alpha", "beta", "gamma"]
    <*> genUTCTime

genConfirmAccountData :: Text -> Gen User.ConfirmAccountData
genConfirmAccountData code = User.ConfirmAccountData code <$> genUTCTime

genResendConfirmationData :: Gen User.ResendConfirmationData
genResendConfirmationData =
  User.ResendConfirmationData
    <$> genFromPool ["alpha", "beta", "gamma"]
    <*> genUTCTime

arbitraryUserCommand :: Gen User.UserCmd
arbitraryUserCommand =
  elements [User.FulfillGDPRRequest (User.FulfillGDPRRequestData epoch)]
  where
    epoch = read "1970-01-01 00:00:00 UTC"

observeUser :: User.Vertex -> RegFile User.UserRegRegs -> Text
observeUser User.PotentialCustomer _ = "(no slots)"
observeUser User.RequiresConfirmation regs =
  Text.pack $
    "email="
      <> show (regs ! #email)
      <> " confirmCode="
      <> show (regs ! #confirmCode)
      <> " registeredAt="
      <> show (regs ! #registeredAt)
observeUser User.Confirmed regs =
  observeUser User.RequiresConfirmation regs
    <> Text.pack (" confirmedAt=" <> show (regs ! #confirmedAt))
observeUser User.Deleted regs =
  Text.pack $
    "email="
      <> show (regs ! #email)
      <> " confirmCode="
      <> show (regs ! #confirmCode)
      <> " registeredAt="
      <> show (regs ! #registeredAt)
      <> " deletedAt="
      <> show (regs ! #deletedAt)

userTamperCases :: [TamperCase User.UserEvent]
userTamperCases =
  [ TamperCase
      { tcName = "drop chain tail",
        tcMutate = removeFirstConfirmationEmail,
        tcExpect = MustFailReplay
      },
    TamperCase
      { tcName = "swap chain events",
        tcMutate = swapRegistrationChain,
        tcExpect = MustFailReplay
      },
    TamperCase
      { tcName = "truncate mid-chain",
        tcMutate = truncateAfterRegistrationStarted,
        tcExpect = MustFailReplay
      },
    TamperCase
      { tcName = "duplicate chain head",
        tcMutate = duplicateRegistrationStarted,
        tcExpect = MustFailReplay
      },
    TamperCase
      { tcName = "foreign splice",
        tcMutate = \events -> Just (foreignAccountConfirmed : events),
        tcExpect = MustFailReplay
      }
  ]

removeFirstConfirmationEmail :: [User.UserEvent] -> Maybe [User.UserEvent]
removeFirstConfirmationEmail = \case
  [] -> Nothing
  User.ConfirmationEmailSent _ : rest -> Just rest
  event : rest -> (event :) <$> removeFirstConfirmationEmail rest

swapRegistrationChain :: [User.UserEvent] -> Maybe [User.UserEvent]
swapRegistrationChain = \case
  first@(User.RegistrationStarted _) : second@(User.ConfirmationEmailSent _) : rest ->
    Just (second : first : rest)
  event : rest -> (event :) <$> swapRegistrationChain rest
  [] -> Nothing

truncateAfterRegistrationStarted :: [User.UserEvent] -> Maybe [User.UserEvent]
truncateAfterRegistrationStarted = go []
  where
    go _ [] = Nothing
    go prefix (event@(User.RegistrationStarted _) : _) =
      Just (reverse (event : prefix))
    go prefix (event : rest) = go (event : prefix) rest

duplicateRegistrationStarted :: [User.UserEvent] -> Maybe [User.UserEvent]
duplicateRegistrationStarted = \case
  first@(User.RegistrationStarted _) : second@(User.ConfirmationEmailSent _) : rest ->
    Just (first : second : first : rest)
  event : rest -> (event :) <$> duplicateRegistrationStarted rest
  [] -> Nothing

foreignAccountConfirmed :: User.UserEvent
foreignAccountConfirmed =
  User.AccountConfirmed
    User.AccountConfirmedData
      { email = "foreign@example.test",
        confirmCode = "foreign-code",
        at = read "1970-01-01 00:00:00 UTC"
      }

brokenTailCoverageFixture :: RoundTripFixture
brokenTailCoverageFixture =
  RoundTripFixture
    { rtName = "BrokenTailCoverage",
      rtTransducer = Broken.brokenTailCoverage,
      rtGenCommand = \_ _ ->
        Broken.Provision
          <$> (Broken.ProvisionData <$> genShortText <*> elements [0 .. 20]),
      rtObserve = observeBrokenTailCoverage,
      rtTamperCases = []
    }

observeBrokenTailCoverage :: Broken.BrokenVertex -> RegFile Broken.BrokenRegs -> Text
observeBrokenTailCoverage Broken.BtcIdle _ = "(no slots)"
observeBrokenTailCoverage Broken.BtcProvisioned regs =
  Text.pack $
    "owner="
      <> show (regs ! #owner)
      <> " quota="
      <> show (regs ! #quota)

registerEmissionFixture :: RoundTripFixture
registerEmissionFixture =
  RoundTripFixture
    { rtName = "RegisterEmission",
      rtTransducer = Register.registerEmission,
      rtGenCommand = genRegisterCommand,
      rtObserve = observeRegister,
      rtTamperCases =
        [ TamperCase
            { tcName = "truncate mid-chain",
              tcMutate = truncateAfterClosed,
              tcExpect = MustFailReplay
            }
        ]
    }

genRegisterCommand :: Register.RegisterVertex -> RegFile Register.RegisterEmissionRegs -> Gen Register.RegisterCmd
genRegisterCommand Register.Fresh _ =
  frequency
    [ (8, Register.Open <$> genShortText),
      (1, Register.Add <$> elements [-10 .. 10]),
      (1, pure Register.Close)
    ]
genRegisterCommand Register.Active _ =
  frequency
    [ (5, Register.Add <$> elements [-10 .. 10]),
      (5, pure Register.Close),
      (1, Register.Open <$> genShortText)
    ]
genRegisterCommand Register.Finished _ = pure Register.Close

observeRegister :: Register.RegisterVertex -> RegFile Register.RegisterEmissionRegs -> Text
observeRegister Register.Fresh _ = "(initial)"
observeRegister state regs =
  Text.pack $
    show state
      <> " owner="
      <> show (regs ! #owner)
      <> " total="
      <> show (regs ! #total)

truncateAfterClosed :: [Register.RegisterEvent] -> Maybe [Register.RegisterEvent]
truncateAfterClosed = go []
  where
    go _ [] = Nothing
    go prefix (event@(Register.Closed _) : _) = Just (reverse (event : prefix))
    go prefix (event : rest) = go (event : prefix) rest

splitCoverageFixture :: RoundTripFixture
splitCoverageFixture =
  RoundTripFixture
    { rtName = "SplitCoverage.fixed",
      rtTransducer = Split.splitCoverageFixed,
      rtGenCommand = \_ _ ->
        Split.Begin
          <$> elements [-10 .. 10]
          <*> elements [-10 .. 10]
          <*> elements [-10 .. 10],
      rtObserve = \state _ -> Text.pack (show state),
      rtTamperCases =
        [ TamperCase
            { tcName = "truncate mid-chain",
              tcMutate = \case
                Split.OutABC a b c : _ -> Just [Split.OutABC a b c]
                _ -> Nothing,
              tcExpect = MustFailReplay
            }
        ]
    }

counterPipelineFixture :: RoundTripFixture
counterPipelineFixture =
  RoundTripFixture
    { rtName = "CounterPipeline.stageA (derived-only output)",
      rtTransducer = Counter.stageA,
      rtGenCommand = \_ _ -> Counter.MsgA <$> elements [0 .. 20],
      rtObserve = \Counter.StageVertex regs ->
        Text.pack ("regA=" <> show (regs ! #regA)),
      rtTamperCases = []
    }

isStateChangingEpsilon :: TransducerValidationWarning s -> Bool
isStateChangingEpsilon StateChangingEpsilon {} = True
isStateChangingEpsilon _ = False

isHeadUnrecoverable :: TransducerValidationWarning s -> Bool
isHeadUnrecoverable HeadUnrecoverable {} = True
isHeadUnrecoverable _ = False

data EpsilonVertex = EpsilonStart | EpsilonDone
  deriving (Eq, Ord, Show, Enum, Bounded)

data EpsilonCommand = EpsilonAdvance
  deriving (Eq, Show)

stateChangingEpsilonFixture :: RoundTripFixture
stateChangingEpsilonFixture =
  RoundTripFixture
    { rtName = "StateChangingEpsilon",
      rtTransducer = stateChangingEpsilon,
      rtGenCommand = \_ _ -> pure EpsilonAdvance,
      rtObserve = \state _ -> Text.pack (show state),
      rtTamperCases = []
    }

stateChangingEpsilon :: SymTransducer (HsPred '[] EpsilonCommand) '[] EpsilonVertex EpsilonCommand ()
stateChangingEpsilon =
  SymTransducer
    { initial = EpsilonStart,
      initialRegs = RNil,
      isFinal = (== EpsilonDone),
      edgesOut = \case
        EpsilonStart ->
          [ Edge
              { guard = PTop,
                update = UKeep,
                output = [],
                target = EpsilonDone
              }
          ]
        EpsilonDone -> []
    }
