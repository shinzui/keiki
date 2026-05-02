module Main (main) where

import Test.Hspec
import qualified Keiki.CoreSpec
import qualified Keiki.DeciderSpec
import qualified Keiki.SymbolicSpec
import qualified Keiki.Examples.UserRegistrationSpec
import qualified Keiki.Examples.UserRegistrationSymbolicSpec
import qualified Keiki.Examples.UserRegistrationV0Spec

main :: IO ()
main = hspec $ do
  describe "Keiki.Core"                                   Keiki.CoreSpec.spec
  describe "Keiki.Decider"                                Keiki.DeciderSpec.spec
  describe "Keiki.Symbolic"                               Keiki.SymbolicSpec.spec
  describe "Keiki.Examples.UserRegistration"              Keiki.Examples.UserRegistrationSpec.spec
  describe "Keiki.Examples.UserRegistration (symbolic)"   Keiki.Examples.UserRegistrationSymbolicSpec.spec
  describe "Keiki.Examples.UserRegistrationV0"            Keiki.Examples.UserRegistrationV0Spec.spec
