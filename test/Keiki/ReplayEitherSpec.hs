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

canonicalLog :: [UserEvent]
canonicalLog =
  [ headEvent,
    tailEvent,
    ConfirmationResent (ConfirmationResentData "alice@x" "K2P7" (t 100)),
    AccountConfirmed (AccountConfirmedData "alice@x" "K2P7" (t 200)),
    AccountDeleted (AccountDeletedData "alice@x" (t 300))
  ]

type Snapshot = (Email, ConfirmationCode, UTCTime, UTCTime, UTCTime)

snapshot :: RegFile UserRegRegs -> Snapshot
snapshot regs =
  ( regs ! #email,
    regs ! #confirmCode,
    regs ! #registeredAt,
    regs ! #confirmedAt,
    regs ! #deletedAt
  )

expectedSnapshot :: Snapshot
expectedSnapshot = ("alice@x", "K2P7", t 100, t 200, t 300)

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

singleStepSpec :: Spec
singleStepSpec = describe "applyEventStreamingEither" $ do
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

spec :: Spec
spec = do
  singleStepSpec

  describe "reconstituteEither" $ do
    it "replays the canonical log to Deleted with the expected snapshot" $
      case reconstituteEither userReg canonicalLog of
        Right (finalVertex, finalRegs) ->
          (finalVertex, snapshot finalRegs)
            `shouldBe` (Deleted, expectedSnapshot)
        Left failure -> expectationFailure ("unexpected replay failure: " <> show failure)

    it "names the exact corrupted event index and queue mismatch" $
      let observed = AccountDeleted (AccountDeletedData "alice@x" (t 999))
          corrupted = headEvent : observed : drop 2 canonicalLog
       in case reconstituteEither userReg corrupted of
            Left failure ->
              failure
                `shouldBe` ReplayFailure
                  { replayFailedIndex = 1,
                    replayFailedState = InFlight RequiresConfirmation [tailEvent],
                    replayFailureReason =
                      ReplayEventFailed
                        ( ReplayQueueMismatch
                            RequiresConfirmation
                            observed
                            [tailEvent]
                        )
                  }
            Right _ -> expectationFailure "expected corrupted log to fail"

    it "reports a foreign first event at index zero" $
      let foreignEvent = AccountConfirmed (AccountConfirmedData "alice@x" "Z9F4" (t 0))
       in case reconstituteEither userReg [foreignEvent] of
            Left failure ->
              failure
                `shouldBe` ReplayFailure
                  { replayFailedIndex = 0,
                    replayFailedState = Settled PotentialCustomer,
                    replayFailureReason =
                      ReplayEventFailed
                        ( ReplayNoInvertingEdge
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
                        )
                  }
            Right _ -> expectationFailure "expected foreign event to fail"

    it "reports a truncated multi-event chain at the input length" $
      case reconstituteEither userReg [headEvent] of
        Left failure ->
          failure
            `shouldBe` ReplayFailure
              { replayFailedIndex = 1,
                replayFailedState = InFlight RequiresConfirmation [tailEvent],
                replayFailureReason = ReplayLogTruncated [tailEvent]
              }
        Right _ -> expectationFailure "expected truncated chain to fail"

  describe "replayEvents" $ do
    it "resumes from a caller-supplied mid-chain seed" $
      case applyEventStreamingEither
        userReg
        (Settled PotentialCustomer)
        (initialRegs userReg)
        headEvent of
        Left failure -> expectationFailure ("could not build seed: " <> show failure)
        Right (wrapper, regsAfterHead) ->
          case replayEvents userReg (wrapper, regsAfterHead) [tailEvent] of
            Right (Settled RequiresConfirmation, regsAfterTail) -> do
              regsAfterTail ! #email `shouldBe` "alice@x"
              regsAfterTail ! #confirmCode `shouldBe` "Z9F4"
              regsAfterTail ! #registeredAt `shouldBe` t 0
            Right (other, _) ->
              expectationFailure ("expected settled state, got " <> show other)
            Left failure ->
              expectationFailure ("mid-chain resume failed: " <> show failure)

    it "returns a final InFlight wrapper without treating it as truncation" $
      case replayEvents
        userReg
        (Settled PotentialCustomer, initialRegs userReg)
        [headEvent] of
        Right (wrapper, _) ->
          wrapper `shouldBe` InFlight RequiresConfirmation [tailEvent]
        Left failure -> expectationFailure ("unexpected fold failure: " <> show failure)

  describe "Maybe compatibility wrappers" $
    it "return Nothing exactly where the strict variants return Left" $ do
      let observed = AccountDeleted (AccountDeletedData "alice@x" (t 999))
          corrupted = headEvent : observed : drop 2 canonicalLog
      case reconstitute userReg corrupted of
        Nothing -> pure ()
        Just _ -> expectationFailure "reconstitute accepted corrupted log"
      case applyEvents userReg (initial userReg, initialRegs userReg) corrupted of
        Nothing -> pure ()
        Just _ -> expectationFailure "applyEvents accepted corrupted log"
      case reconstituteEither userReg corrupted of
        Left _ -> pure ()
        Right _ -> expectationFailure "reconstituteEither accepted corrupted log"
      case applyEventsEither userReg (initial userReg, initialRegs userReg) corrupted of
        Left _ -> pure ()
        Right _ -> expectationFailure "applyEventsEither accepted corrupted log"

  describe "former Decider behavioral coverage" $ do
    it "replays the complete multi-event output of one forward step" $ do
      let command = StartRegistration (StartRegistrationData "alice@x" "Z9F4" (t 0))
      case stepEither userReg (initial userReg, initialRegs userReg) command of
        Left failure -> expectationFailure ("forward step failed: " <> show failure)
        Right (_, _, emitted) -> do
          emitted `shouldBe` [headEvent, tailEvent]
          case applyEventsEither userReg (initial userReg, initialRegs userReg) emitted of
            Right (vertex, _) -> vertex `shouldBe` RequiresConfirmation
            Left failure -> expectationFailure ("multi-event replay failed: " <> show failure)

    it "preserves the durable pre-confirmation deletion path" $ do
      let startCommand = StartRegistration (StartRegistrationData "bob@x" "S0E1" (t 0))
          deleteCommand = FulfillGDPRRequest (FulfillGDPRRequestData (t 999))
      case stepEither userReg (initial userReg, initialRegs userReg) startCommand of
        Left failure -> expectationFailure ("registration failed: " <> show failure)
        Right (_, _, startEvents) ->
          case applyEventsEither userReg (initial userReg, initialRegs userReg) startEvents of
            Left failure -> expectationFailure ("registration replay failed: " <> show failure)
            Right preDeletion@(RequiresConfirmation, _) ->
              case stepEither userReg preDeletion deleteCommand of
                Left failure -> expectationFailure ("deletion failed: " <> show failure)
                Right (_, _, deletionEvents) -> do
                  deletionEvents
                    `shouldBe` [AccountDeleted (AccountDeletedData "bob@x" (t 999))]
                  case applyEventsEither userReg preDeletion deletionEvents of
                    Right (vertex, _) -> vertex `shouldBe` Deleted
                    Left failure -> expectationFailure ("deletion replay failed: " <> show failure)
            Right (other, _) ->
              expectationFailure ("expected RequiresConfirmation, got " <> show other)
