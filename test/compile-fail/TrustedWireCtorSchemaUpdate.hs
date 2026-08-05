{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TypeApplications #-}

module TrustedWireCtorSchemaUpdate where

import GHC.Generics (Generic)
import Keiki.Core (WireCtor (..), wireSchemaUnavailable)
import Keiki.Generics (mkWireCtorRecordVia)

data Output = Output {value :: Int}
  deriving stock (Generic)

trustedWire :: WireCtor Output (Int, ())
trustedWire = mkWireCtorRecordVia @"Output"

schemaReplacedWire :: WireCtor Output (Int, ())
schemaReplacedWire = trustedWire {wcSchema = wireSchemaUnavailable}
