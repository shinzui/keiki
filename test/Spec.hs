module Main (main) where

import Test.Hspec
import qualified Keiki.CoreSpec

main :: IO ()
main = hspec $ do
  describe "Keiki.Core" Keiki.CoreSpec.spec
