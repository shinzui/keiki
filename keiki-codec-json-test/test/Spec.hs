-- | Self-test for @keiki-codec-json-test@. Exercises every public
-- helper against the toy 'Email' / 'DemoSlots' / 'DemoSlotsRenamed'
-- fixtures defined in "Keiki.Codec.JSON.Test.Demo".
--
-- Running this suite is the closest a maintainer can get to "what a
-- downstream consumer's test looks like" without writing an external
-- example consumer. Failures here mean the toolkit's public surface
-- has regressed; consumer-side tests would have failed the same
-- assertions.
module Main (main) where

import Data.Proxy (Proxy (..))
import Data.Text qualified as T
import Keiki.Codec.JSON.Test
  ( regFileCodecProps,
    regFileCodecPropsEq,
    regFileShapeSensitivitySpec,
    someKnownShape,
  )
import Keiki.Codec.JSON.Test.Demo
  ( DemoSlots,
    DemoSlotsRenamed,
    Email (..),
  )
import Keiki.Codec.JSON.Test.Golden
  ( SlotGolden (..),
    slotGoldenSpec,
  )
import Test.Hspec (describe, hspec)

main :: IO ()
main = hspec $ do
  describe "Keiki.Codec.JSON.Test.Golden.slotGoldenSpec" $ do
    slotGoldenSpec
      "Email"
      ( SlotGolden
          { sgInput = Email (T.pack "a@b.c"),
            sgBytes = "\"a@b.c\""
          }
      )

  describe
    "Keiki.Codec.JSON.Test.regFileCodecProps @DemoSlots"
    (regFileCodecProps @DemoSlots)

  describe
    "Keiki.Codec.JSON.Test.regFileCodecPropsEq @DemoSlots"
    (regFileCodecPropsEq @DemoSlots)

  describe "Keiki.Codec.JSON.Test.regFileShapeSensitivitySpec" $
    regFileShapeSensitivitySpec
      (Proxy @DemoSlots)
      [ ( "rename email -> emailAddress",
          someKnownShape @DemoSlotsRenamed
        )
      ]
