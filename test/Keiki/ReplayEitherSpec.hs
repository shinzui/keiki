module Keiki.ReplayEitherSpec (spec) where

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Keiki.Core
import Keiki.Fixtures.UserRegistration
import Test.Hspec

t :: Integer -> UTCTime
t seconds = UTCTime (fromGregorian 2026 5 1) (secondsToDiffTime seconds)

headEvent :: UserEvent
headEvent =
  RegistrationStarted
    (RegistrationStartedData "alice@x" "Z9F4" (t 0))

tailEvent :: UserEvent
tailEvent = ConfirmationEmailSent (ConfirmationEmailSentData "alice@x")

duplicateEntrance :: [Edge (HsPred UserRegRegs UserCmd) UserRegRegs UserCmd UserEvent Vertex]
duplicateEntrance = case edgesOut userRegAST PotentialCustomer of
  [edge] -> [edge, edge {target = Confirmed}]
  _ -> error "userRegAST must have exactly one PotentialCustomer edge"

ambiguousUserReg ::
  SymTransducer
    (HsPred UserRegRegs UserCmd)
    UserRegRegs
    Vertex
    UserCmd
    UserEvent
ambiguousUserReg =
  userRegAST
    { edgesOut = \source ->
        if source == PotentialCustomer
          then duplicateEntrance
          else edgesOut userRegAST source
    }

spec :: Spec
spec = describe "applyEventStreamingEither" $ do
  it "reports every rejected outgoing edge when no head output inverts" $
    case applyEventStreamingEither
      userReg
      (Settled PotentialCustomer)
      (initialRegs userReg)
      (AccountConfirmed (AccountConfirmedData "alice@x" "Z9F4" (t 0))) of
      Left failure ->
        failure
          `shouldBe` ReplayNoInvertingEdge
            PotentialCustomer
            [ RejectedEdgeSummary
                { rejectedEdge =
                    EdgeRef
                      { edgeSource = PotentialCustomer,
                        edgeIndex = 0
                      },
                  rejectedTarget = RequiresConfirmation,
                  rejectedGuard = False
                }
            ]
      Right _ -> expectationFailure "expected ReplayNoInvertingEdge"

  it "reports the observed event and full expected queue on a mismatch" $
    case applyEventStreamingEither
      userReg
      (InFlight RequiresConfirmation [tailEvent])
      (initialRegs userReg)
      (AccountDeleted (AccountDeletedData "alice@x" (t 999))) of
      Left failure ->
        failure
          `shouldBe` ReplayQueueMismatch
            RequiresConfirmation
            (AccountDeleted (AccountDeletedData "alice@x" (t 999)))
            [tailEvent]
      Right _ -> expectationFailure "expected ReplayQueueMismatch"

  it "reports every edge whose head output inverts ambiguously" $
    case applyEventStreamingEither
      ambiguousUserReg
      (Settled PotentialCustomer)
      (initialRegs ambiguousUserReg)
      headEvent of
      Left failure ->
        failure
          `shouldBe` ReplayAmbiguousInversions
            PotentialCustomer
            [ MatchedEdgeSummary
                { matchedEdge =
                    EdgeRef
                      { edgeSource = PotentialCustomer,
                        edgeIndex = 0
                      },
                  matchedTarget = RequiresConfirmation
                },
              MatchedEdgeSummary
                { matchedEdge =
                    EdgeRef
                      { edgeSource = PotentialCustomer,
                        edgeIndex = 1
                      },
                  matchedTarget = Confirmed
                }
            ]
      Right _ -> expectationFailure "expected ReplayAmbiguousInversions"

  it "keeps applyEventStreaming as a Nothing-returning failure wrapper" $
    case applyEventStreaming
      ambiguousUserReg
      (Settled PotentialCustomer)
      (initialRegs ambiguousUserReg)
      headEvent of
      Nothing -> pure ()
      Just _ -> expectationFailure "expected Nothing from compatibility wrapper"
