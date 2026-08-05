{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TypeApplications #-}

module TrustedWireCtorUpdate where

import GHC.Generics (Generic)
import Keiki.Core (WireCtor (..))
import Keiki.Generics (FieldsOf, mkWireCtorVia)

data Payload = Payload {value :: Int}
  deriving stock (Generic)

data Event = Recorded Payload
  deriving stock (Generic)

trustedWire :: WireCtor Event (FieldsOf Payload)
trustedWire = mkWireCtorVia @"Recorded"

dishonestWire :: WireCtor Event (FieldsOf Payload)
dishonestWire = trustedWire {wcMatch = const Nothing}
