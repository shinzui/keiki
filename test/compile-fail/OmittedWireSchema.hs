{-# OPTIONS_GHC -Werror=missing-fields #-}

-- This fixture is intentionally excluded from the test-suite module list.
-- Compile it with @cabal exec -- ghc -fno-code@ and expect public record
-- construction to be rejected by the sealed unidirectional pattern.
module OmittedWireSchema where

import Keiki.Core (WireCtor (..))

omittedWireSchema :: WireCtor () ()
omittedWireSchema =
  WireCtor
    { wcName = "Omitted",
      wcMatch = Just,
      wcBuild = id
    }
