# User Registration behavior

Rendered by `Keiki.Render.Mermaid.toMermaid` over
`Jitsurei.UserRegistration.userReg`. To refresh:

    cabal repl keiki
    ghci> import Keiki.Render.Mermaid (toMermaid)
    ghci> import Jitsurei.UserRegistration (userReg)
    ghci> import qualified Data.Text.IO as TIO
    ghci> TIO.putStrLn (toMermaid userReg)

```mermaid
stateDiagram-v2
    [*] --> PotentialCustomer
    PotentialCustomer --> RequiresConfirmation : StartRegistration / RegistrationStarted; ConfirmationEmailSent<br/>u: registeredAt := StartRegistration.at, confirmCode := StartRegistration.confirmCode, email := StartRegistration.email, (keep)<br/>g: StartRegistration
    RequiresConfirmation --> Confirmed : ConfirmAccount / AccountConfirmed<br/>u: confirmedAt := ConfirmAccount.at, (keep)<br/>g: (ConfirmAccount &amp;&amp; ConfirmAccount.confirmCode == confirmCode)
    RequiresConfirmation --> RequiresConfirmation : ResendConfirmation / ConfirmationResent<br/>u: registeredAt := ResendConfirmation.at, confirmCode := ResendConfirmation.code, (keep)<br/>g: ResendConfirmation
    RequiresConfirmation --> Deleted : FulfillGDPRRequest / AccountDeleted<br/>u: deletedAt := FulfillGDPRRequest.at, (keep)<br/>g: FulfillGDPRRequest
    Confirmed --> Deleted : FulfillGDPRRequest / AccountDeleted<br/>u: deletedAt := FulfillGDPRRequest.at, (keep)<br/>g: FulfillGDPRRequest
    Deleted --> [*]
```

The `PotentialCustomer --> RequiresConfirmation` edge labelled
`StartRegistration / RegistrationStarted; ConfirmationEmailSent` is a
**multi-event edge**: one transition emits two events in declaration
order. Under the EP-19 GSM widening this is expressed as a single edge
with `output :: [OutTerm rs ci co]` of length 2. The `; ` separator in
the label is the Mermaid renderer's length-2 convention (length-3+
edges use Mermaid's `<br/>` multi-line label). See
[`multi-event-commands.md`](../multi-event-commands.md) for the
authoring guide.

Both deletion edges emit `AccountDeleted`. In particular, a GDPR request received
before confirmation is not silent: deleting state without an event would make a
persisted log replay to `RequiresConfirmation` instead of `Deleted`.
