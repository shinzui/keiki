# User Registration topology

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
    PotentialCustomer --> Registering : StartRegistration / RegistrationStarted
    Registering --> RequiresConfirmation : Continue / ConfirmationEmailSent
    RequiresConfirmation --> Confirmed : ConfirmAccount / AccountConfirmed
    RequiresConfirmation --> RequiresConfirmation : ResendConfirmation / ConfirmationResent
    RequiresConfirmation --> Deleted : FulfillGDPRRequest / ε
    Confirmed --> Deleted : FulfillGDPRRequest / AccountDeleted
    Deleted --> [*]
```

The `RequiresConfirmation --> Deleted` edge labelled `FulfillGDPRRequest /
ε` is an ε-edge (no event emitted) — a GDPR delete request received before
confirmation tears the account down silently. Every other edge produces a
wire event named after the slash's right-hand side.
