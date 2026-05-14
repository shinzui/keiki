-- | EP-36 M3 sensitivity tests (P7.4).
--
-- The baseline 'ExemplarSlots' shape hash is computed once, and each
-- mutation from EP-36 §4 (cases #1–9) is asserted to produce a /different/
-- hash. This is the discrimination side of the shape hash contract: any
-- structural change in the slot list must flip the hash.
module Keiki.Codec.JSON.SensitivitySpec (spec) where

import Data.Proxy (Proxy (..))
import Test.Hspec (Spec, describe, it, shouldSatisfy)

import Keiki.Shape (regFileShapeHash)

import Keiki.Codec.JSON.Fixtures
  ( AddSlots
  , ExemplarSlots
  , NewtypeWrapSlots
  , RecordReplaceSlots
  , RemoveSlots
  , RenameSlots
  , RenamedTypeSlots
  , ReorderSlots
  , SplitSlots
  , TypeChangeSameJsonSlots
  )


spec :: Spec
spec = describe "Sensitivity (EP-36 §4 cases #1–9)" $ do
  let baseline = regFileShapeHash (Proxy @ExemplarSlots)

  it "#1 add slot flips the hash" $
    regFileShapeHash (Proxy @AddSlots) `shouldSatisfy` (/= baseline)

  it "#2 remove slot flips the hash" $
    regFileShapeHash (Proxy @RemoveSlots) `shouldSatisfy` (/= baseline)

  it "#3 rename slot flips the hash" $
    regFileShapeHash (Proxy @RenameSlots) `shouldSatisfy` (/= baseline)

  it "#4 reorder slots flips the hash (P10)" $
    regFileShapeHash (Proxy @ReorderSlots) `shouldSatisfy` (/= baseline)

  it "#5 slot type change (Int → Word32) flips the hash" $
    regFileShapeHash (Proxy @TypeChangeSameJsonSlots)
      `shouldSatisfy` (/= baseline)

  it "#6 newtype wrap (Text → OrderId) flips the hash" $
    regFileShapeHash (Proxy @NewtypeWrapSlots) `shouldSatisfy` (/= baseline)

  it "#7 primitive → record (Text → Address) flips the hash" $
    regFileShapeHash (Proxy @RecordReplaceSlots) `shouldSatisfy` (/= baseline)

  it "#8 split slot flips the hash" $
    regFileShapeHash (Proxy @SplitSlots) `shouldSatisfy` (/= baseline)

  it "#9 type rename (Address → RenamedAddress) flips the hash" $
    regFileShapeHash (Proxy @RenamedTypeSlots) `shouldSatisfy` (/= baseline)
