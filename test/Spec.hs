module Main (main) where

import Test.Hspec
import qualified Keiki.CoreSpec
import qualified Keiki.Examples.UserRegistrationSpec

main :: IO ()
main = hspec $ do
  describe "Keiki.Core"                       Keiki.CoreSpec.spec
  describe "Keiki.Examples.UserRegistration"  Keiki.Examples.UserRegistrationSpec.spec
