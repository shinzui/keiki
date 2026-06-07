module Keiki.OperatorsSpec (spec) where

import Keiki.Core
import Test.Hspec

-- A trivial command type; the operators here never read it.
data NoCmd = NoCmd deriving (Eq, Show)

-- Evaluate a predicate over the empty register file / NoCmd input.
p :: HsPred '[] NoCmd -> Bool
p pr = evalPred pr RNil NoCmd

-- Evaluate an Int term the same way.
n :: Term '[] NoCmd ifs Int -> Int
n t = evalTerm t RNil NoCmd

-- A guard written at the aliased type Pred…
sampleGuard :: Pred '[] NoCmd
sampleGuard = lit (1 :: Int) .>= lit 0 .&& lit (2 :: Int) ./= lit 5

-- …is accepted where an HsPred is expected (evalPred takes HsPred).
-- If `Pred` were not a true synonym for `HsPred`, this would not compile.

spec :: Spec
spec = do
  describe "comparison operators" $ do
    it ".>= computes >=" $ do
      p (lit (5 :: Int) .>= lit 3) `shouldBe` True
      p (lit (3 :: Int) .>= lit 3) `shouldBe` True
      p (lit (2 :: Int) .>= lit 3) `shouldBe` False
    it ".<= computes <=" $ do
      p (lit (2 :: Int) .<= lit 3) `shouldBe` True
      p (lit (4 :: Int) .<= lit 3) `shouldBe` False
    it ".> computes >" $ do
      p (lit (4 :: Int) .> lit 3) `shouldBe` True
      p (lit (3 :: Int) .> lit 3) `shouldBe` False
    it ".< computes <" $ do
      p (lit (2 :: Int) .< lit 3) `shouldBe` True
      p (lit (3 :: Int) .< lit 3) `shouldBe` False
    it "./= computes /=" $ do
      p (lit (2 :: Int) ./= lit 3) `shouldBe` True
      p (lit (3 :: Int) ./= lit 3) `shouldBe` False

  describe "operator equals its constructor (behavioural identity)" $ do
    it ".>= matches PCmp CmpGe on a grid" $
      [p (lit a .>= lit b) | a <- g, b <- g]
        `shouldBe` [p (PCmp CmpGe (lit a) (lit b)) | a <- g, b <- g]
    it ".== matches PEq on a grid" $
      [p (lit a .== lit b) | a <- g, b <- g]
        `shouldBe` [p (PEq (lit a) (lit b)) | a <- g, b <- g]
    it "./= matches PNot . PEq on a grid" $
      [p (lit a ./= lit b) | a <- g, b <- g]
        `shouldBe` [p (PNot (PEq (lit a) (lit b))) | a <- g, b <- g]

  describe "logical operators" $ do
    it ".&& is conjunction" $ do
      p (lit (1 :: Int) .== lit 1 .&& lit (2 :: Int) .== lit 2) `shouldBe` True
      p (lit (1 :: Int) .== lit 1 .&& lit (2 :: Int) .== lit 3) `shouldBe` False
    it ".|| is disjunction" $ do
      p (lit (1 :: Int) .== lit 9 .|| lit (2 :: Int) .== lit 2) `shouldBe` True
      p (lit (1 :: Int) .== lit 9 .|| lit (2 :: Int) .== lit 8) `shouldBe` False
    it "pnot is negation" $ do
      p (pnot (lit (1 :: Int) .== lit 1)) `shouldBe` False
      p (pnot (lit (1 :: Int) .== lit 2)) `shouldBe` True

  describe "arithmetic operators (and fixity)" $ do
    it ".+ .- .* compute the arithmetic" $ do
      n (lit 2 .+ lit 3) `shouldBe` 5
      n (lit 7 .- lit 4) `shouldBe` 3
      n (lit 6 .* lit 7) `shouldBe` 42
    it ".* binds tighter than .+ (infixl 7 vs 6)" $
      n (lit 2 .+ lit 3 .* lit 4) `shouldBe` 14
    it "arithmetic feeds a comparison without parens" $
      p (lit (10 :: Int) .<= lit 3 .* lit 4) `shouldBe` True

  describe "type synonyms" $
    it "Pred is interchangeable with HsPred" $
      evalPred sampleGuard RNil NoCmd `shouldBe` True
  where
    g = [1, 2, 3] :: [Int]
