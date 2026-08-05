{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TypeApplications #-}

module TrustedInCtorSchemaUpdate where

import GHC.Generics (Generic)
import Keiki.Core (InCtor (..), inCtorSchemaUnavailable)
import Keiki.Generics (mkInCtorRecordVia)

data Input = Input {value :: Int}
  deriving stock (Generic)

trustedInput :: InCtor Input '[ '("value", Int)]
trustedInput = mkInCtorRecordVia @"Input"

schemaReplacedInput :: InCtor Input '[ '("value", Int)]
schemaReplacedInput = trustedInput {icSchema = inCtorSchemaUnavailable}
