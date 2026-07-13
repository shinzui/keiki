{-# LANGUAGE TemplateHaskell #-}
-- Constructor derivation emits complete command/event helper families; this
-- spec deliberately exercises only the helpers needed for composition.
{-# OPTIONS_GHC -Wno-unused-top-binds #-}

-- | EP-48: N-ary event-family codec composition and singleton events.
--
-- Three groups:
--
--   1. /Multi-family round-trip/ — sum three independently-derived
--      families into one alphabet via the arity-3 injectors, build an
--      edge output in family 1 and in family 2, and assert 'solveOutput'
--      inverts the summed event back to the (injected) command.
--   2. /Name uniqueness/ — the injected constructor names are pairwise
--      distinct (the precondition 'solveOutput' relies on, since it
--      matches by @icName@/@wcName@ string equality), and a colliding
--      alphabet is caught by the same check.
--   3. /Singleton events/ — 'deriveWireCtors' now derives a zero-arg
--      event 'WireCtor', and 'solveOutput' inverts a singleton event to
--      its singleton command.
module Keiki.CompositionNarySpec (spec) where

import Data.List (nub)
import Data.Maybe (isNothing)
import GHC.Generics (Generic)
import Keiki.Composition
  ( inCtor3At1,
    inCtor3At2,
    inCtor3At3,
    outTerm3At1,
    outTerm3At2,
    wireCtor3At1,
    wireCtor3At2,
    wireCtor3At3,
  )
import Keiki.Core
  ( InCtor (..),
    OutFields (..),
    OutTerm,
    RegFile (..),
    WireCtor (..),
    pack,
    solveOutput,
  )
import Keiki.Generics (FieldsOf, RegFieldsOf, mkWireCtor0)
import Keiki.Generics.TH (deriveAggregateCtors, deriveWireCtors)
import Test.Hspec

-- * Three independent event families ------------------------------------

-- None of these aggregates use registers, so the register schema is
-- empty; the output fields read from the input command, not from state.
type Regs = '[]

-- Family 1 (A): a record-payload command/event pair.
data AData = AData {aVal :: Int} deriving (Eq, Show, Generic)

data ACmd = AFlip AData deriving (Eq, Show, Generic)

data AEvt = AFlipped AData deriving (Eq, Show, Generic)

-- Family 2 (B).
data BData = BData {bVal :: Int} deriving (Eq, Show, Generic)

data BCmd = BFlip BData deriving (Eq, Show, Generic)

data BEvt = BFlipped BData deriving (Eq, Show, Generic)

-- Family 3 (C) — present so the 3-way sum is concrete and so the
-- uniqueness check has a third name to compare.
data CData = CData {cVal :: Int} deriving (Eq, Show, Generic)

data CCmd = CFlip CData deriving (Eq, Show, Generic)

data CEvt = CFlipped CData deriving (Eq, Show, Generic)

$(deriveAggregateCtors ''ACmd ''Regs [("AFlip", "AFlip")])
$(deriveWireCtors ''AEvt [("AFlipped", "AFlipped")])
$(deriveAggregateCtors ''BCmd ''Regs [("BFlip", "BFlip")])
$(deriveWireCtors ''BEvt [("BFlipped", "BFlipped")])
$(deriveAggregateCtors ''CCmd ''Regs [("CFlip", "CFlip")])
$(deriveWireCtors ''CEvt [("CFlipped", "CFlipped")])

-- The right-nested 3-family summed alphabets.
type SumCmd = Either ACmd (Either BCmd CCmd)

type SumEvt = Either AEvt (Either BEvt CEvt)

-- Edge output terms re-homed into the summed alphabet, one per family.
sumOutA :: OutTerm Regs SumCmd SumEvt
sumOutA = outTerm3At1 (pack inCtorAFlip wireAFlipped (OFCons (inpAFlip #aVal) OFNil))

sumOutB :: OutTerm Regs SumCmd SumEvt
sumOutB = outTerm3At2 (pack inCtorBFlip wireBFlipped (OFCons (inpBFlip #bVal) OFNil))

-- Injected wire/in constructors, used by the uniqueness group.
sumWireA :: WireCtor SumEvt (FieldsOf AData)
sumWireA = wireCtor3At1 wireAFlipped

sumWireB :: WireCtor SumEvt (FieldsOf BData)
sumWireB = wireCtor3At2 wireBFlipped

sumWireC :: WireCtor SumEvt (FieldsOf CData)
sumWireC = wireCtor3At3 wireCFlipped

sumInA :: InCtor SumCmd (RegFieldsOf AData)
sumInA = inCtor3At1 inCtorAFlip

sumInB :: InCtor SumCmd (RegFieldsOf BData)
sumInB = inCtor3At2 inCtorBFlip

sumInC :: InCtor SumCmd (RegFieldsOf CData)
sumInC = inCtor3At3 inCtorCFlip

-- * A singleton (payload-free) event family -----------------------------

data DoorCmd = OpenDoor | CloseDoor deriving (Eq, Show, Generic)

data DoorEvt = DoorOpened | DoorClosed deriving (Eq, Show, Generic)

$( deriveAggregateCtors
     ''DoorCmd
     ''Regs
     [("OpenDoor", "OpenDoor"), ("CloseDoor", "CloseDoor")]
 )

-- This is the new capability: deriveWireCtors over zero-arg event ctors.
$( deriveWireCtors
     ''DoorEvt
     [("DoorOpened", "DoorOpened"), ("DoorClosed", "DoorClosed")]
 )

spec :: Spec
spec = do
  describe "summing N event families" $ do
    it "round-trips a family-1 event through solveOutput" $
      solveOutput sumOutA RNil (Left (AFlipped (AData 5)))
        `shouldBe` Just (Left (AFlip (AData 5)))

    it "round-trips a family-2 event through solveOutput" $
      solveOutput sumOutB RNil (Right (Left (BFlipped (BData 7))))
        `shouldBe` Just (Right (Left (BFlip (BData 7))))

    it "rejects an event from the wrong family arm" $
      -- sumOutA inverts only family-1 (Left) events; a family-2 value
      -- does not match its WireCtor, so inversion yields Nothing.
      solveOutput sumOutA RNil (Right (Left (BFlipped (BData 7))))
        `shouldBe` Nothing

  describe "icName/wcName uniqueness" $ do
    -- solveOutput/stepOne match by name string (src/Keiki/Core.hs ~1067),
    -- so the summed families' constructor names must be pairwise distinct.
    it "injected family names are pairwise distinct" $ do
      let wcNames = [wcName sumWireA, wcName sumWireB, wcName sumWireC]
          icNames = [icName sumInA, icName sumInB, icName sumInC]
      (length wcNames, length (nub wcNames)) `shouldBe` (3, 3)
      (length icNames, length (nub icNames)) `shouldBe` (3, 3)

    it "a colliding alphabet is caught by the uniqueness check" $ do
      -- Two distinct families that both name a ctor "Dup": were they
      -- summed, solveOutput's name-equality match could mis-invert. The
      -- nub-based uniqueness check flags the collision.
      let collidingNames =
            [ wcName (mkWireCtor0 "Dup" () :: WireCtor () ()),
              wcName (mkWireCtor0 "Dup" 'x' :: WireCtor Char ())
            ]
      (length collidingNames == length (nub collidingNames)) `shouldBe` False

  describe "singleton events" $ do
    it "deriveWireCtors derives a zero-arg event WireCtor" $ do
      wcName wireDoorOpened `shouldBe` "DoorOpened"
      wcMatch wireDoorOpened DoorOpened `shouldBe` Just ()
      isNothing (wcMatch wireDoorOpened DoorClosed) `shouldBe` True
      wcBuild wireDoorOpened () `shouldBe` DoorOpened

    it "solveOutput inverts a singleton event to its singleton command" $
      solveOutput (pack inCtorOpenDoor wireDoorOpened OFNil) RNil DoorOpened
        `shouldBe` Just OpenDoor
