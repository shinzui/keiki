module Main (main) where

import Test.Hspec (hspec, describe, it, shouldBe)

main :: IO ()
main = hspec $ do
  describe "keiki-codec-json" $ do
    it "is the M0 scaffold; the codec lands in M2" $ True `shouldBe` True
