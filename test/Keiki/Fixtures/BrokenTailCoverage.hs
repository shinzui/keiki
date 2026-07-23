-- | Deliberately defective EP-73 fixture. Its command coverage is split
-- across two events, so the first event cannot reconstruct the command.
-- This module exists only to prove the round-trip harness and validator catch
-- EP-71's head-recoverability defect class. It is not an authoring example.
module Keiki.Fixtures.BrokenTailCoverage
  ( ProvisionData (..),
    BrokenCommand (..),
    BrokenEvent (..),
    BrokenVertex (..),
    BrokenRegs,
    brokenTailCoverage,
  )
where

import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Keiki.Core

data ProvisionData = ProvisionData
  { owner :: Text,
    quota :: Int
  }
  deriving stock (Eq, Show)

data BrokenCommand = Provision ProvisionData
  deriving stock (Eq, Show)

newtype OwnerRecordedData = OwnerRecordedData {owner :: Text}
  deriving stock (Eq, Show)

newtype QuotaAssignedData = QuotaAssignedData {quota :: Int}
  deriving stock (Eq, Show)

data BrokenEvent
  = OwnerRecorded OwnerRecordedData
  | QuotaAssigned QuotaAssignedData
  deriving stock (Eq, Show)

data BrokenVertex = BtcIdle | BtcProvisioned
  deriving stock (Eq, Ord, Show, Enum, Bounded)

type BrokenRegs =
  '[ '("owner", Text),
     '("quota", Int)
   ]

type ProvisionFields =
  '[ '("owner", Text),
     '("quota", Int)
   ]

inCtorProvision :: InCtor BrokenCommand ProvisionFields
inCtorProvision =
  InCtor
    { icName = "Provision",
      icMatch = \case
        Provision ProvisionData {owner, quota} ->
          Just $
            RCons (Proxy @"owner") owner $
              RCons (Proxy @"quota") quota RNil,
      icBuild = \(RCons _ owner (RCons _ quota RNil)) ->
        Provision ProvisionData {owner, quota}
    }

wireOwnerRecorded :: WireCtor BrokenEvent (Text, ())
wireOwnerRecorded =
  WireCtor
    { wcName = "OwnerRecorded",
      wcMatch = \case
        OwnerRecorded OwnerRecordedData {owner} -> Just (owner, ())
        _ -> Nothing,
      wcBuild = \(owner, ()) -> OwnerRecorded OwnerRecordedData {owner}
    }

wireQuotaAssigned :: WireCtor BrokenEvent (Int, ())
wireQuotaAssigned =
  WireCtor
    { wcName = "QuotaAssigned",
      wcMatch = \case
        QuotaAssigned QuotaAssignedData {quota} -> Just (quota, ())
        _ -> Nothing,
      wcBuild = \(quota, ()) -> QuotaAssigned QuotaAssignedData {quota}
    }

provisionOwner :: Term BrokenRegs BrokenCommand ProvisionFields Text
provisionOwner = TInpCtorField inCtorProvision (#owner :: Index ProvisionFields Text)

provisionQuota :: Term BrokenRegs BrokenCommand ProvisionFields Int
provisionQuota = TInpCtorField inCtorProvision (#quota :: Index ProvisionFields Int)

brokenTailCoverage ::
  SymTransducer
    (HsPred BrokenRegs BrokenCommand)
    BrokenRegs
    BrokenVertex
    BrokenCommand
    BrokenEvent
brokenTailCoverage =
  SymTransducer
    { initial = BtcIdle,
      initialRegs =
        RCons (Proxy @"owner") "" $
          RCons (Proxy @"quota") 0 RNil,
      isFinal = (== BtcProvisioned),
      edgesOut = \case
        BtcIdle ->
          [ Edge
              { guard = matchInCtor inCtorProvision,
                update =
                  USet
                    (#owner :: IndexN "owner" BrokenRegs Text)
                    provisionOwner
                    `combine` USet
                      (#quota :: IndexN "quota" BrokenRegs Int)
                      provisionQuota,
                output =
                  [ pack
                      inCtorProvision
                      wireOwnerRecorded
                      (provisionOwner *: oNil),
                    pack
                      inCtorProvision
                      wireQuotaAssigned
                      (provisionQuota *: oNil)
                  ],
                target = BtcProvisioned,
                mode = Live
              }
          ]
        BtcProvisioned -> []
    }
