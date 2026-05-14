{-# LANGUAGE TemplateHaskell #-}

module Keiki.Generics.THSpec (spec) where

import Data.Maybe (isNothing)
import Data.Proxy (Proxy (..))
import GHC.Generics (Generic)
import Test.Hspec
import Keiki.Core
import Keiki.Generics ()
import Keiki.Generics.TH


-- A toy aggregate used purely to exercise the TH splices in
-- isolation. Two commands: one record-payload, one singleton. The
-- spec asserts the splices produce identifiers with the expected
-- behaviour — name, match/build, and the @inp@ projection.

data ToyData = ToyData { x :: Int, y :: Int }
  deriving (Eq, Show, Generic)


data ToyCmd
  = DoIt   ToyData
  | NoArgs
  deriving (Eq, Show, Generic)


type ToyRegs =
  '[ '("x", Int)
   , '("y", Int)
   ]


$(deriveAggregateCtors ''ToyCmd ''ToyRegs
    [ ("DoIt",   "DoIt")
    , ("NoArgs", "NoArgs")
    ])


-- | Empty register file populated with sentinel values. The 'inp'
-- projection test below reads from the input symbol via
-- 'TInpCtorField', not from the register file, so the values here do
-- not matter — they only need to be present so the carrier
-- type-checks. The 'KnownSymbol' constraints on each 'Proxy' are
-- discharged by the slot-list types in scope.
toyRegs :: RegFile ToyRegs
toyRegs = RCons (Proxy @"x") 0 (RCons (Proxy @"y") 0 RNil)


spec :: Spec
spec = do
  describe "deriveAggregateCtors on a record-payload constructor (DoIt)" $ do
    it "names the InCtor after the source ctor" $
      icName inCtorDoIt `shouldBe` "DoIt"

    it "matches a DoIt value and yields a populated RegFile" $
      let payload = ToyData 17 23
          regfile = case icMatch inCtorDoIt (DoIt payload) of
            Just rf -> rf
            Nothing -> error "icMatch returned Nothing on DoIt"
      in (regfile ! #x, regfile ! #y) `shouldBe` (17, 23)

    it "rejects a non-DoIt value" $
      isNothing (icMatch inCtorDoIt NoArgs) `shouldBe` True

    it "rebuilds DoIt from a populated RegFile" $
      let payload = ToyData 17 23
          rf      = case icMatch inCtorDoIt (DoIt payload) of
            Just r  -> r
            Nothing -> error "set-up icMatch failed"
      in icBuild inCtorDoIt rf `shouldBe` DoIt payload

    it "evalTerm (inpDoIt #x) on a DoIt input reads the x field" $
      evalTerm (inpDoIt #x) toyRegs (DoIt (ToyData 5 9)) `shouldBe` 5

    it "evalPred isDoIt agrees with constructor match" $ do
      evalPred isDoIt toyRegs (DoIt (ToyData 0 0)) `shouldBe` True
      evalPred isDoIt toyRegs NoArgs               `shouldBe` False

  describe "deriveAggregateCtors on a singleton constructor (NoArgs)" $ do
    it "names the InCtor after the source ctor" $
      icName inCtorNoArgs `shouldBe` "NoArgs"

    it "matches the NoArgs singleton" $
      case icMatch inCtorNoArgs NoArgs of
        Just _  -> pure ()
        Nothing -> expectationFailure "icMatch returned Nothing on NoArgs"

    it "rejects a record-payload value" $
      isNothing (icMatch inCtorNoArgs (DoIt (ToyData 0 0))) `shouldBe` True

    it "evalPred isNoArgs agrees with constructor match" $ do
      evalPred isNoArgs toyRegs NoArgs               `shouldBe` True
      evalPred isNoArgs toyRegs (DoIt (ToyData 0 0)) `shouldBe` False
