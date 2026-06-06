module Keiki.OperatorsQualifiedSpec (spec) where

import Keiki.Core (HsPred, RegFile (..), evalPred, lit)
import Keiki.Operators qualified as K
import Test.Hspec

-- Simulate the lens clash: a local, unqualified (.>) that is NOT keiki's
-- greater-than. If the qualified K..> below accidentally resolved to this
-- one, the predicate would be ill-typed (Int, not HsPred) and would not
-- compile; if a plain (.>) were used it would shadow keiki's. The point is
-- that K..> reaches keiki's operator while (.>) stays free for other uses.
(.>) :: Int -> Int -> Int
a .> b = a + b
infixl 6 .>

-- A trivial command type; the operators here never read it.
data NoCmd = NoCmd deriving (Eq, Show)

-- Evaluate a predicate over the empty register file / NoCmd input.
runP :: HsPred '[] NoCmd -> Bool
runP pr = evalPred pr RNil NoCmd

-- A guard built entirely through the qualified import.
sampleGuard :: HsPred '[] NoCmd
sampleGuard = (lit (5 :: Int) K..> lit 3) K..&& (lit (2 :: Int) K..>= lit 2)

spec :: Spec
spec = do
    describe "qualified Keiki.Operators resolves the (.>) clash" $ do
        it "K..> builds keiki's greater-than predicate" $ do
            runP (lit (5 :: Int) K..> lit 3) `shouldBe` True
            runP (lit (3 :: Int) K..> lit 3) `shouldBe` False
        it "the local unqualified (.>) is still usable and is NOT keiki's" $
            (2 .> 3) `shouldBe` 5 -- our local addition, untouched
        it "a compound guard via qualified ops evaluates correctly" $
            runP sampleGuard `shouldBe` True
        it "arithmetic via qualified ops feeds a comparison" $
            runP (lit (10 :: Int) K..<= lit 3 K..* lit 4) `shouldBe` True
