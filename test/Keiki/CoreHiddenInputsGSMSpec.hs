module Keiki.CoreHiddenInputsGSMSpec (spec) where

import Data.List (isInfixOf)
import Data.Proxy (Proxy (..))
import Keiki.Core
import Test.Hspec

-- | A 3-slot input constructor used to stress the union check.
data MultiInput = Begin Int Int Int deriving (Eq, Show)

data MultiOutput
  = OutAB Int Int -- recovers slots a, b
  | OutBC Int Int -- recovers slots b, c
  | OutA Int -- recovers slot a only
  deriving (Eq, Show)

inCtorBegin :: InCtor MultiInput '[ '("a", Int), '("b", Int), '("c", Int)]
inCtorBegin =
  InCtor
    { icName = "Begin",
      icMatch = \case
        Begin a b c ->
          Just $
            RCons (Proxy @"a") a $
              RCons (Proxy @"b") b $
                RCons (Proxy @"c") c $
                  RNil,
      icBuild = \(RCons _ a (RCons _ b (RCons _ c RNil))) -> Begin a b c
    }

wcAB :: WireCtor MultiOutput (Int, (Int, ()))
wcAB =
  WireCtor
    { wcName = "OutAB",
      wcMatch = \case
        OutAB a b -> Just (a, (b, ()))
        _ -> Nothing,
      wcBuild = \(a, (b, ())) -> OutAB a b
    }

wcBC :: WireCtor MultiOutput (Int, (Int, ()))
wcBC =
  WireCtor
    { wcName = "OutBC",
      wcMatch = \case
        OutBC b c -> Just (b, (c, ()))
        _ -> Nothing,
      wcBuild = \(b, (c, ())) -> OutBC b c
    }

wcA :: WireCtor MultiOutput (Int, ())
wcA =
  WireCtor
    { wcName = "OutA",
      wcMatch = \case
        OutA a -> Just (a, ())
        _ -> Nothing,
      wcBuild = \(a, ()) -> OutA a
    }

-- | The "well-formed" multi-event edge: two OPacks whose union of
-- visited slots covers all three of @Begin@'s slots.
-- OPack #1 (OutAB) visits {a, b}; OPack #2 (OutBC) visits {b, c}.
-- Union = {a, b, c} = full InCtor coverage. No warning expected.
goodUnion :: SymTransducer (HsPred '[] MultiInput) '[] Bool MultiInput MultiOutput
goodUnion =
  SymTransducer
    { edgesOut = \case
        False ->
          [ Edge
              { guard = matchInCtor inCtorBegin,
                update = UKeep,
                output =
                  [ pack
                      inCtorBegin
                      wcAB
                      ( OFCons
                          (TInpCtorField inCtorBegin (#a :: Index '[ '("a", Int), '("b", Int), '("c", Int)] Int))
                          (OFCons (TInpCtorField inCtorBegin (#b :: Index '[ '("a", Int), '("b", Int), '("c", Int)] Int)) OFNil)
                      ),
                    pack
                      inCtorBegin
                      wcBC
                      ( OFCons
                          (TInpCtorField inCtorBegin (#b :: Index '[ '("a", Int), '("b", Int), '("c", Int)] Int))
                          (OFCons (TInpCtorField inCtorBegin (#c :: Index '[ '("a", Int), '("b", Int), '("c", Int)] Int)) OFNil)
                      )
                  ],
                target = True
              }
          ]
        True -> [],
      initial = False,
      initialRegs = RNil,
      isFinal = id
    }

-- | The "ill-formed" multi-event edge: two OPacks whose union of
-- visited slots is {a, b}, leaving slot @c@ unrecovered. Both OPacks
-- name the same InCtor (@Begin@); the union check should flag @c@.
badUnion :: SymTransducer (HsPred '[] MultiInput) '[] Bool MultiInput MultiOutput
badUnion =
  SymTransducer
    { edgesOut = \case
        False ->
          [ Edge
              { guard = matchInCtor inCtorBegin,
                update = UKeep,
                output =
                  [ pack
                      inCtorBegin
                      wcAB
                      ( OFCons
                          (TInpCtorField inCtorBegin (#a :: Index '[ '("a", Int), '("b", Int), '("c", Int)] Int))
                          (OFCons (TInpCtorField inCtorBegin (#b :: Index '[ '("a", Int), '("b", Int), '("c", Int)] Int)) OFNil)
                      ),
                    pack
                      inCtorBegin
                      wcA
                      (OFCons (TInpCtorField inCtorBegin (#a :: Index '[ '("a", Int), '("b", Int), '("c", Int)] Int)) OFNil)
                  ],
                target = True
              }
          ]
        True -> [],
      initial = False,
      initialRegs = RNil,
      isFinal = id
    }

-- | A single-event edge that does NOT cover all slots of its InCtor.
-- Legacy behaviour: the per-OPack check fires. Confirms the union
-- check is a strict generalisation (not a regression) of the legacy
-- single-event check.
badSingle :: SymTransducer (HsPred '[] MultiInput) '[] Bool MultiInput MultiOutput
badSingle =
  SymTransducer
    { edgesOut = \case
        False ->
          [ Edge
              { guard = matchInCtor inCtorBegin,
                update = UKeep,
                output =
                  [ pack
                      inCtorBegin
                      wcA
                      (OFCons (TInpCtorField inCtorBegin (#a :: Index '[ '("a", Int), '("b", Int), '("c", Int)] Int)) OFNil)
                  ],
                target = True
              }
          ]
        True -> [],
      initial = False,
      initialRegs = RNil,
      isFinal = id
    }

spec :: Spec
spec = do
  describe "checkHiddenInputs union strengthening (EP-19 M4)" $ do
    it "well-formed multi-event edge (union covers all slots) ⇒ no warnings" $
      checkHiddenInputs goodUnion `shouldBe` []

    it "ill-formed multi-event edge (union still misses slot c) ⇒ warning names c" $ do
      let warnings = checkHiddenInputs badUnion
      length warnings `shouldBe` 1
      case warnings of
        [w] -> do
          hiwEdgeSource w `shouldBe` "False"
          hiwReason w `shouldSatisfy` ("Begin" `isInfixOf`)
          hiwReason w `shouldSatisfy` ("\"c\"" `isInfixOf`)
        _ -> expectationFailure "expected exactly one warning"

    it "single-event edge missing slots fires too (legacy compat)" $ do
      let warnings = checkHiddenInputs badSingle
      length warnings `shouldBe` 1
      case warnings of
        [w] -> do
          hiwEdgeSource w `shouldBe` "False"
          hiwReason w `shouldSatisfy` ("Begin" `isInfixOf`)
          -- Legacy behaviour: missing both b and c.
          hiwReason w `shouldSatisfy` ("\"b\"" `isInfixOf`)
          hiwReason w `shouldSatisfy` ("\"c\"" `isInfixOf`)
        _ -> expectationFailure "expected exactly one warning"
