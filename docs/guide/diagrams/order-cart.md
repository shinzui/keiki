# Order / Cart topology

Rendered by `Keiki.Render.Mermaid.toMermaid` over
`Jitsurei.OrderCart.orderCart`. To refresh:

    cabal repl keiki
    ghci> import Keiki.Render.Mermaid (toMermaid)
    ghci> import Jitsurei.OrderCart (orderCart)
    ghci> import qualified Data.Text.IO as TIO
    ghci> TIO.putStrLn (toMermaid orderCart)

```mermaid
stateDiagram-v2
    [*] --> Empty
    Empty --> OpenWithItems : AddItem / ItemAdded
    OpenWithItems --> OpenWithItems : AddItem / ItemAdded
    OpenWithItems --> OpenWithItems : RemoveItem / ItemRemoved
    OpenWithItems --> OpenWithItems : ApplyDiscount / DiscountApplied
    OpenWithItems --> Reserved : Reserve / OrderReserved
    OpenWithItems --> Cancelled : Cancel / OrderCancelled
    Reserved --> Paid : ConfirmPayment / PaymentConfirmed
    Reserved --> Cancelled : Cancel / OrderCancelled
    Paid --> Shipped : Ship / OrderShipped
    Paid --> Paid : RequestRefund / RefundRequested
    Paid --> Refunded : ProcessRefund / OrderRefunded
    Shipped --> Delivered : Deliver / OrderDelivered
    Delivered --> [*]
    Cancelled --> [*]
    Refunded --> [*]
```

The lifecycle-shaped aggregate introduced by EP-22 to anchor the
benchmark suite. Three terminal vertices (`Delivered`, `Cancelled`,
`Refunded`); the `OpenWithItems` and `Paid` vertices each carry
self-loops (multiple edits / refund requests stay on the same vertex
while updating the register file). No ε-edges in this aggregate; every
transition emits a wire event.
