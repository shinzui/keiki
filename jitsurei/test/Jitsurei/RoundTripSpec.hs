{-# LANGUAGE BlockArguments #-}

module Jitsurei.RoundTripSpec (spec) where

import Data.Text (Text)
import Data.Text qualified as Text
import Jitsurei.CoreBankingSync qualified as Sync
import Jitsurei.EmailDelivery qualified as Email
import Jitsurei.Loan qualified as Loan
import Jitsurei.LoanApplication qualified as Application
import Jitsurei.LoanWorkflow qualified as Workflow
import Jitsurei.OrderCart qualified as Order
import Jitsurei.RoundTrip
import Jitsurei.UserRegistration qualified as User
import Jitsurei.UserRegistrationV0 qualified as UserV0
import Keiki.Core
import Test.Hspec (Spec)
import Test.QuickCheck (Gen, elements, frequency)

spec :: Spec
spec = do
  mapM_ roundTripSpec allFixtures
  roundTripSpecUnchecked loanWorkflowFixture
  teethSpec coreBankingSyncFixture
  teethSpec loanApplicationFixture
  teethSpec userRegistrationV0Fixture

allFixtures :: [RoundTripFixture]
allFixtures =
  [ emailDeliveryFixture,
    loanFixture,
    orderCartFixture,
    userRegistrationFixture
  ]

emailDeliveryFixture :: RoundTripFixture
emailDeliveryFixture =
  RoundTripFixture
    { rtName = "EmailDelivery",
      rtTransducer = Email.emailDelivery,
      rtGenCommand = \_ _ -> Email.SendEmail <$> genEmailData,
      rtObserve = \case
        Email.EmailPending -> \_ -> "(no slots)"
        Email.EmailSentVertex -> \regs ->
          render
            [ ("recipient", show (regs ! #emailRecipient)),
              ("subject", show (regs ! #emailSubject)),
              ("sentAt", show (regs ! #emailSentAt))
            ],
      rtTamperCases =
        [ TamperCase
            { tcName = "drop only event",
              tcMutate = \case [_] -> Just []; _ -> Nothing,
              tcExpect = MustNotSilentlyMatch
            }
        ]
    }

genEmailData :: Gen Email.SendEmailData
genEmailData =
  Email.SendEmailData <$> genShortText <*> genShortText <*> genUTCTime

loanFixture :: RoundTripFixture
loanFixture =
  RoundTripFixture
    { rtName = "Loan",
      rtTransducer = Loan.loan,
      rtGenCommand = genLoanCommand,
      rtObserve = observeLoan,
      rtTamperCases = []
    }

genLoanCommand :: Loan.LoanVertex -> RegFile Loan.LoanRegs -> Gen Loan.LoanCmd'
genLoanCommand Loan.LoanInitial _ =
  Loan.CreateLoan <$> genCreateLoanData
genLoanCommand Loan.LoanAwaiting regs =
  frequency
    [ (8, Loan.AssignLegacyLoanId <$> genAssignmentData (regs ! #loanLoanId)),
      (1, Loan.AssignLegacyLoanId <$> genAssignmentData "wrong-loan")
    ]
genLoanCommand Loan.LoanLinked _ = Loan.CreateLoan <$> genCreateLoanData

genCreateLoanData :: Gen Loan.CreateLoanData
genCreateLoanData =
  Loan.CreateLoanData
    <$> genShortText
    <*> genShortText
    <*> elements [1 .. 1_000_000]

genAssignmentData :: Text -> Gen Loan.AssignLegacyLoanIdData
genAssignmentData loanId =
  Loan.AssignLegacyLoanIdData loanId <$> genShortText

observeLoan :: Loan.LoanVertex -> RegFile Loan.LoanRegs -> Text
observeLoan Loan.LoanInitial _ = "(no slots)"
observeLoan Loan.LoanAwaiting regs =
  render
    [ ("loanId", show (regs ! #loanLoanId)),
      ("applicantId", show (regs ! #loanApplicantId)),
      ("principal", show (regs ! #loanPrincipal))
    ]
observeLoan Loan.LoanLinked regs =
  observeLoan Loan.LoanAwaiting regs
    <> render [("legacyLoanId", show (regs ! #loanLegacyLoanId))]

loanApplicationFixture :: RoundTripFixture
loanApplicationFixture =
  RoundTripFixture
    { rtName = "LoanApplication",
      rtTransducer = Application.loanApplication,
      rtGenCommand = genApplicationCommand,
      rtObserve = observeApplication,
      rtTamperCases = []
    }

genApplicationCommand :: Application.LoanAppVertex -> RegFile Application.LoanAppRegs -> Gen Application.LoanCmd
genApplicationCommand Application.Intake _ =
  frequency
    [ (9, Application.StartApplication <$> genStartApplicationData),
      (1, Application.WithdrawApplication <$> genWithdrawApplicationData)
    ]
genApplicationCommand Application.CollectingDocuments regs =
  frequency
    [ (8, nextEvidenceCommand regs),
      (1, Application.WithdrawApplication <$> genWithdrawApplicationData),
      (1, Application.StartApplication <$> genStartApplicationData)
    ]
genApplicationCommand Application.UnderReview _ =
  frequency
    [ (9, pure Application.Continue),
      (1, Application.WithdrawApplication <$> genWithdrawApplicationData)
    ]
genApplicationCommand _ _ = pure Application.Continue

nextEvidenceCommand :: RegFile Application.LoanAppRegs -> Gen Application.LoanCmd
nextEvidenceCommand regs
  | regs ! #appIncomeDocCount < Application.minimumIncomeDocs =
      Application.SubmitIncomeDocument <$> genIncomeDocumentData
  | regs ! #appIdDocCount < Application.minimumIdDocs =
      Application.SubmitIdDocument <$> genIdDocumentData
  | regs ! #appCreditScore < Application.approvalThresholdScore =
      Application.RecordCreditScore <$> genCreditScoreData
  | not (regs ! #appEmploymentVerified) =
      Application.RecordEmploymentCheck <$> genEmploymentData
  | otherwise = pure Application.Continue

genStartApplicationData :: Gen Application.StartApplicationData
genStartApplicationData =
  Application.StartApplicationData
    <$> genShortText
    <*> elements [1_000 .. 500_000]
    <*> genShortText
    <*> genUTCTime

genIncomeDocumentData :: Gen Application.SubmitIncomeDocumentData
genIncomeDocumentData =
  Application.SubmitIncomeDocumentData <$> genShortText <*> genUTCTime

genIdDocumentData :: Gen Application.SubmitIdDocumentData
genIdDocumentData =
  Application.SubmitIdDocumentData <$> genShortText <*> genUTCTime

genCreditScoreData :: Gen Application.RecordCreditScoreData
genCreditScoreData =
  Application.RecordCreditScoreData <$> elements [650 .. 850] <*> genUTCTime

genEmploymentData :: Gen Application.RecordEmploymentCheckData
genEmploymentData =
  Application.RecordEmploymentCheckData True <$> genUTCTime

genWithdrawApplicationData :: Gen Application.WithdrawApplicationData
genWithdrawApplicationData =
  Application.WithdrawApplicationData <$> genShortText <*> genUTCTime

observeApplication :: Application.LoanAppVertex -> RegFile Application.LoanAppRegs -> Text
observeApplication Application.Intake _ = "(no slots)"
observeApplication Application.CollectingDocuments regs = observeApplicationBase regs
observeApplication Application.UnderReview regs = observeApplicationBase regs
observeApplication Application.Approved regs =
  observeApplicationBase regs <> render [("decidedAt", show (regs ! #appDecidedAt))]
observeApplication Application.Declined regs =
  observeApplicationBase regs
    <> render
      [ ("decidedAt", show (regs ! #appDecidedAt)),
        ("reason", show (regs ! #appDeclineReason))
      ]
observeApplication Application.Withdrawn regs =
  render
    [ ("applicantId", show (regs ! #appApplicantId)),
      ("withdrawnAt", show (regs ! #appWithdrawnAt))
    ]

observeApplicationBase :: RegFile Application.LoanAppRegs -> Text
observeApplicationBase regs =
  render
    [ ("applicantId", show (regs ! #appApplicantId)),
      ("amount", show (regs ! #appRequestedAmount)),
      ("purpose", show (regs ! #appPurpose)),
      ("incomeDocs", show (regs ! #appIncomeDocCount)),
      ("idDocs", show (regs ! #appIdDocCount)),
      ("score", show (regs ! #appCreditScore)),
      ("employment", show (regs ! #appEmploymentVerified))
    ]

loanWorkflowFixture :: RoundTripFixture
loanWorkflowFixture =
  RoundTripFixture
    { rtName = "LoanWorkflow (lockstep wiring)",
      rtTransducer = Workflow.loanWorkflow,
      rtGenCommand = \_ _ -> pure Application.Continue,
      rtObserve = \state _ -> Text.pack (show state),
      rtTamperCases = []
    }

orderCartFixture :: RoundTripFixture
orderCartFixture =
  RoundTripFixture
    { rtName = "OrderCart",
      rtTransducer = Order.orderCart,
      rtGenCommand = genOrderCommand,
      rtObserve = observeOrder,
      rtTamperCases = []
    }

genOrderCommand :: Order.OrderVertex -> RegFile Order.OrderCartRegs -> Gen Order.OrderCmd
genOrderCommand Order.Empty _ = Order.AddItem <$> genAddItemData
genOrderCommand Order.OpenWithItems _ =
  frequency
    [ (3, Order.AddItem <$> genAddItemData),
      (1, Order.RemoveItem <$> genRemoveItemData),
      (1, Order.ApplyDiscount <$> genDiscountData),
      (4, Order.Reserve <$> genReserveData),
      (1, Order.Cancel <$> genCancelData)
    ]
genOrderCommand Order.Reserved _ =
  frequency
    [ (8, Order.ConfirmPayment <$> genPaymentData),
      (2, Order.Cancel <$> genCancelData)
    ]
genOrderCommand Order.Paid _ =
  frequency
    [ (6, Order.Ship <$> genShipData),
      (2, Order.RequestRefund <$> genRefundRequestData),
      (2, Order.ProcessRefund <$> genProcessRefundData)
    ]
genOrderCommand Order.Shipped _ = Order.Deliver . Order.DeliverData <$> genUTCTime
genOrderCommand _ _ = Order.AddItem <$> genAddItemData

genAddItemData :: Gen Order.AddItemData
genAddItemData =
  Order.AddItemData <$> genShortText <*> elements [1 .. 5] <*> elements [1 .. 10_000] <*> genUTCTime

genRemoveItemData :: Gen Order.RemoveItemData
genRemoveItemData = Order.RemoveItemData <$> genShortText <*> genUTCTime

genDiscountData :: Gen Order.ApplyDiscountData
genDiscountData =
  Order.ApplyDiscountData <$> genShortText <*> elements [0 .. 10_000] <*> genUTCTime

genReserveData :: Gen Order.ReserveData
genReserveData = Order.ReserveData <$> genShortText <*> genUTCTime

genPaymentData :: Gen Order.ConfirmPaymentData
genPaymentData =
  Order.ConfirmPaymentData <$> genShortText <*> elements [1 .. 1_000_000] <*> genUTCTime

genShipData :: Gen Order.ShipData
genShipData = Order.ShipData <$> genShortText <*> genShortText <*> genUTCTime

genCancelData :: Gen Order.CancelData
genCancelData = Order.CancelData <$> genShortText <*> genUTCTime

genRefundRequestData :: Gen Order.RequestRefundData
genRefundRequestData = Order.RequestRefundData <$> genShortText <*> genUTCTime

genProcessRefundData :: Gen Order.ProcessRefundData
genProcessRefundData =
  Order.ProcessRefundData <$> genShortText <*> elements [1 .. 1_000_000] <*> genUTCTime

observeOrder :: Order.OrderVertex -> RegFile Order.OrderCartRegs -> Text
observeOrder Order.Empty _ = "(no slots)"
observeOrder Order.OpenWithItems regs = orderItems regs
observeOrder Order.Reserved regs =
  orderItems regs <> render [("reservation", show (regs ! #reservationId))]
observeOrder Order.Paid regs = observePaid regs
observeOrder Order.Shipped regs =
  observePaid regs
    <> render
      [ ("carrier", show (regs ! #shippingCarrier)),
        ("tracking", show (regs ! #trackingId)),
        ("shippedAt", show (regs ! #shippedAt))
      ]
observeOrder Order.Delivered regs =
  observeOrder Order.Shipped regs <> render [("deliveredAt", show (regs ! #deliveredAt))]
observeOrder Order.Cancelled regs =
  orderItems regs <> render [("cancelledAt", show (regs ! #cancelledAt))]
observeOrder Order.Refunded regs =
  observePaid regs <> render [("refundedAt", show (regs ! #refundedAt))]

orderItems :: RegFile Order.OrderCartRegs -> Text
orderItems regs = render [("itemCount", show (regs ! #itemCount))]

observePaid :: RegFile Order.OrderCartRegs -> Text
observePaid regs =
  observeOrder Order.Reserved regs
    <> render
      [ ("paymentRef", show (regs ! #paymentRef)),
        ("amountPaid", show (regs ! #amountPaid))
      ]

userRegistrationFixture :: RoundTripFixture
userRegistrationFixture =
  userFixture
    "UserRegistration"
    User.userReg
    genUserCommand
    [ TamperCase
        { tcName = "truncate mid-chain",
          tcMutate = \case
            User.RegistrationStarted event : _ ->
              Just [User.RegistrationStarted event]
            _ -> Nothing,
          tcExpect = MustFailReplay
        }
    ]

userRegistrationV0Fixture :: RoundTripFixture
userRegistrationV0Fixture =
  userFixture
    "UserRegistrationV0 (hidden confirm code)"
    UserV0.userRegV0
    genUserV0Command
    []

userFixture ::
  (Eq event, Show event) =>
  String ->
  SymTransducer (HsPred User.UserRegRegs User.UserCmd) User.UserRegRegs User.Vertex User.UserCmd event ->
  (User.Vertex -> RegFile User.UserRegRegs -> Gen User.UserCmd) ->
  [TamperCase event] ->
  RoundTripFixture
userFixture name transducer genCommand tamperCases =
  RoundTripFixture
    { rtName = name,
      rtTransducer = transducer,
      rtGenCommand = genCommand,
      rtObserve = observeUser,
      rtTamperCases = tamperCases
    }

genUserCommand :: User.Vertex -> RegFile User.UserRegRegs -> Gen User.UserCmd
genUserCommand User.PotentialCustomer _ =
  frequency
    [ (9, User.StartRegistration <$> genStartRegistrationData),
      (1, User.FulfillGDPRRequest . User.FulfillGDPRRequestData <$> genUTCTime)
    ]
genUserCommand User.RequiresConfirmation regs =
  frequency
    [ (5, User.ConfirmAccount <$> genConfirmData (regs ! #confirmCode)),
      (2, User.ConfirmAccount <$> genConfirmData "wrong"),
      (3, User.ResendConfirmation <$> genResendData),
      (2, User.FulfillGDPRRequest . User.FulfillGDPRRequestData <$> genUTCTime)
    ]
genUserCommand User.Confirmed _ =
  User.FulfillGDPRRequest . User.FulfillGDPRRequestData <$> genUTCTime
genUserCommand User.Deleted _ =
  User.FulfillGDPRRequest . User.FulfillGDPRRequestData <$> genUTCTime

genUserV0Command :: User.Vertex -> RegFile User.UserRegRegs -> Gen User.UserCmd
genUserV0Command User.PotentialCustomer _ =
  User.StartRegistration <$> genStartRegistrationData
genUserV0Command User.RequiresConfirmation regs =
  User.ConfirmAccount <$> genConfirmData (regs ! #confirmCode)
genUserV0Command User.Confirmed _ =
  User.FulfillGDPRRequest . User.FulfillGDPRRequestData <$> genUTCTime
genUserV0Command User.Deleted _ =
  User.FulfillGDPRRequest . User.FulfillGDPRRequestData <$> genUTCTime

genStartRegistrationData :: Gen User.StartRegistrationData
genStartRegistrationData =
  User.StartRegistrationData
    <$> genShortText
    <*> genFromPool ["alpha", "beta", "gamma"]
    <*> genUTCTime

genConfirmData :: Text -> Gen User.ConfirmAccountData
genConfirmData code = User.ConfirmAccountData code <$> genUTCTime

genResendData :: Gen User.ResendConfirmationData
genResendData =
  User.ResendConfirmationData
    <$> genFromPool ["alpha", "beta", "gamma"]
    <*> genUTCTime

observeUser :: User.Vertex -> RegFile User.UserRegRegs -> Text
observeUser User.PotentialCustomer _ = "(no slots)"
observeUser User.RequiresConfirmation regs = observeUserBase regs
observeUser User.Confirmed regs =
  observeUserBase regs <> render [("confirmedAt", show (regs ! #confirmedAt))]
observeUser User.Deleted regs =
  observeUserBase regs <> render [("deletedAt", show (regs ! #deletedAt))]

observeUserBase :: RegFile User.UserRegRegs -> Text
observeUserBase regs =
  render
    [ ("email", show (regs ! #email)),
      ("code", show (regs ! #confirmCode)),
      ("registeredAt", show (regs ! #registeredAt))
    ]

coreBankingSyncFixture :: RoundTripFixture
coreBankingSyncFixture =
  RoundTripFixture
    { rtName = "CoreBankingSync (derived command output)",
      rtTransducer = Sync.coreBankingSync,
      rtGenCommand = genSyncCommand,
      rtObserve = observeSync,
      rtTamperCases = []
    }

genSyncCommand :: Sync.SyncVertex -> RegFile Sync.SyncRegs -> Gen Sync.SyncInput
genSyncCommand Sync.SyncIdle _ =
  Sync.LoanCreatedIn
    <$> (Sync.LoanCreatedInData <$> genShortText <*> genShortText <*> elements [1 .. 1_000_000])
genSyncCommand Sync.SyncRequested regs =
  Sync.LegacyCallbackReceivedIn
    <$> (Sync.LegacyCallbackReceivedInData (regs ! #syncPendingLoanId) <$> genShortText)
genSyncCommand Sync.SyncSettled _ =
  Sync.LegacyCallbackReceivedIn
    <$> (Sync.LegacyCallbackReceivedInData <$> genShortText <*> genShortText)

observeSync :: Sync.SyncVertex -> RegFile Sync.SyncRegs -> Text
observeSync Sync.SyncIdle _ = "(no slots)"
observeSync state regs =
  Text.pack (show state)
    <> render
      [ ("loanId", show (regs ! #syncPendingLoanId)),
        ("applicantId", show (regs ! #syncPendingApplicantId)),
        ("principal", show (regs ! #syncPendingPrincipal))
      ]

render :: [(String, String)] -> Text
render = Text.pack . unwords . map (\(name, value) -> name <> "=" <> value)
