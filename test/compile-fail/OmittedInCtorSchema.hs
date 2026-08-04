{-# LANGUAGE DataKinds #-}
{-# OPTIONS_GHC -Werror=missing-fields #-}

-- This fixture is intentionally excluded from the test-suite module list.
-- Compile it with @cabal exec -- ghc -fno-code@ and expect the omitted
-- @icSchema@ field to be rejected as the next Keiki source break.
module OmittedInCtorSchema where

import Keiki.Core (InCtor (..), RegFile (..))

omittedInCtorSchema :: InCtor () '[]
omittedInCtorSchema =
  InCtor
    { icName = "Omitted",
      icMatch = \() -> Just RNil,
      icBuild = \RNil -> ()
    }
