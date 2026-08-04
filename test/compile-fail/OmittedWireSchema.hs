{-# OPTIONS_GHC -Werror=missing-fields #-}

-- This fixture is intentionally excluded from the test-suite module list.
-- Compile it with @cabal exec -- ghc -fno-code@ and expect the omitted
-- @wcSchema@ field to be rejected as the Keiki 0.9 source break.
module OmittedWireSchema where

import Keiki.Core (WireCtor (..))

omittedWireSchema :: WireCtor () ()
omittedWireSchema =
  WireCtor
    { wcName = "Omitted",
      wcMatch = Just,
      wcBuild = id
    }
