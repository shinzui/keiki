-- | Shared fixture, integration point 4 of
-- @docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md@:
-- consumed by EP-71 (validation alignment), EP-73 (round-trip property
-- harness), and EP-74 (composition semantics). Do not fold into a spec module.
module Keiki.Fixtures.RegisterEmission
  ( RegisterCmd (..),
    RegisterEvent (..),
    RegisterVertex (..),
    RegisterEmissionRegs,
    registerEmission,
    registerCommands,
  )
where

import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Keiki.Core

data RegisterCmd
  = Open Text
  | Add Int
  | Close
  deriving stock (Eq, Show)

data RegisterEvent
  = Opened Text
  | Added Int Text
  | Closed Text
  | Archived Text
  deriving stock (Eq, Show)

data RegisterVertex = Fresh | Active | Finished
  deriving stock (Eq, Ord, Show, Enum, Bounded)

type RegisterEmissionRegs =
  '[ '("owner", Text),
     '("total", Int)
   ]

inCtorOpen :: InCtor RegisterCmd '[ '("owner", Text)]
inCtorOpen =
  InCtor
    { icName = "Open",
      icMatch = \case Open owner -> Just (RCons (Proxy @"owner") owner RNil); _ -> Nothing,
      icBuild = \(RCons _ owner RNil) -> Open owner
    }

inCtorAdd :: InCtor RegisterCmd '[ '("amount", Int)]
inCtorAdd =
  InCtor
    { icName = "Add",
      icMatch = \case Add amount -> Just (RCons (Proxy @"amount") amount RNil); _ -> Nothing,
      icBuild = \(RCons _ amount RNil) -> Add amount
    }

inCtorClose :: InCtor RegisterCmd '[]
inCtorClose =
  InCtor
    { icName = "Close",
      icMatch = \case Close -> Just RNil; _ -> Nothing,
      icBuild = \RNil -> Close
    }

wireOpened :: WireCtor RegisterEvent (Text, ())
wireOpened =
  WireCtor
    { wcName = "Opened",
      wcMatch = \case Opened owner -> Just (owner, ()); _ -> Nothing,
      wcBuild = \(owner, ()) -> Opened owner
    }

wireAdded :: WireCtor RegisterEvent (Int, (Text, ()))
wireAdded =
  WireCtor
    { wcName = "Added",
      wcMatch = \case Added amount owner -> Just (amount, (owner, ())); _ -> Nothing,
      wcBuild = \(amount, (owner, ())) -> Added amount owner
    }

wireClosed :: WireCtor RegisterEvent (Text, ())
wireClosed =
  WireCtor
    { wcName = "Closed",
      wcMatch = \case Closed owner -> Just (owner, ()); _ -> Nothing,
      wcBuild = \(owner, ()) -> Closed owner
    }

wireArchived :: WireCtor RegisterEvent (Text, ())
wireArchived =
  WireCtor
    { wcName = "Archived",
      wcMatch = \case Archived owner -> Just (owner, ()); _ -> Nothing,
      wcBuild = \(owner, ()) -> Archived owner
    }

registerEmission :: SymTransducer (HsPred RegisterEmissionRegs RegisterCmd) RegisterEmissionRegs RegisterVertex RegisterCmd RegisterEvent
registerEmission =
  SymTransducer
    { edgesOut = \case
        Fresh ->
          [ Edge
              { guard = matchInCtor inCtorOpen,
                update = USet (#owner :: IndexN "owner" RegisterEmissionRegs Text) (TInpCtorField inCtorOpen (#owner :: Index '[ '("owner", Text)] Text)),
                output = [pack inCtorOpen wireOpened (TInpCtorField inCtorOpen (#owner :: Index '[ '("owner", Text)] Text) *: oNil)],
                target = Active,
                mode = Live
              }
          ]
        Active ->
          [ Edge
              { guard = matchInCtor inCtorAdd,
                update = USet (#total :: IndexN "total" RegisterEmissionRegs Int) (TInpCtorField inCtorAdd (#amount :: Index '[ '("amount", Int)] Int)),
                output =
                  [ pack
                      inCtorAdd
                      wireAdded
                      ( TInpCtorField inCtorAdd (#amount :: Index '[ '("amount", Int)] Int)
                          *: TReg (#owner :: Index RegisterEmissionRegs Text)
                          *: oNil
                      )
                  ],
                target = Active,
                mode = Live
              },
            Edge
              { guard = matchInCtor inCtorClose,
                update = UKeep,
                output =
                  [ pack inCtorClose wireClosed (TReg (#owner :: Index RegisterEmissionRegs Text) *: oNil),
                    pack inCtorClose wireArchived (TReg (#owner :: Index RegisterEmissionRegs Text) *: oNil)
                  ],
                target = Finished,
                mode = Live
              }
          ]
        Finished -> [],
      initial = Fresh,
      initialRegs = RCons (Proxy @"owner") "" (RCons (Proxy @"total") 0 RNil),
      isFinal = (== Finished)
    }

registerCommands :: [RegisterCmd]
registerCommands = [Open "alice", Add 7, Close]
