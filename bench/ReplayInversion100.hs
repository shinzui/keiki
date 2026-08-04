{-# LANGUAGE GHC2024 #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE TypeApplications #-}

-- Manual, non-CI startup-cost benchmark for Plan 87. Run with:
--
-- nix develop -c cabal exec -- runghc -package=keiki bench/ReplayInversion100.hs
module Main (main) where

import Control.Monad (unless)
import GHC.Generics (Generic)
import Keiki.Generics (FieldsOf, RegFieldsOf, mkInCtorVia, mkWireCtorVia)
import Keiki.Symbolic
import System.CPUTime (getCPUTime)
import Text.Printf (printf)

data Payload = Payload {value :: Int}
  deriving stock (Eq, Show, Generic)

data Command = Submit Payload
  deriving stock (Eq, Show, Generic)

data Event = Submitted Payload
  deriving stock (Eq, Show, Generic)

data Vertex = Only
  deriving stock (Eq, Show, Enum, Bounded)

inputCtor :: InCtor Command (RegFieldsOf Payload)
inputCtor = mkInCtorVia @"Submit"

wireCtor :: WireCtor Event (FieldsOf Payload)
wireCtor = mkWireCtorVia @"Submitted"

emitted :: OutTerm '[] Command Event
emitted = pack inputCtor wireCtor (TInpCtorField inputCtor (#value) *: oNil)

oneEdge :: EdgeMode -> Edge (HsPred '[] Command) '[] Command Event Vertex
oneEdge edgeMode =
  Edge
    { guard = PInCtor inputCtor,
      update = UKeep,
      output = [emitted],
      target = Only,
      mode = edgeMode
    }

benchmarkMachine :: SymTransducer (HsPred '[] Command) '[] Vertex Command Event
benchmarkMachine =
  SymTransducer
    { edgesOut = \Only -> replicate 10 (oneEdge Live) ++ replicate 11 (oneEdge ReplayOnly),
      initial = Only,
      initialRegs = RNil,
      isFinal = const True
    }

main :: IO ()
main = do
  started <- getCPUTime
  details <- checkInversionAmbiguitySymDetailed benchmarkMachine
  finished <- getCPUTime
  unless (length details == 100) $
    error ("expected 100 same-phase pairs, got " <> show (length details))
  printf "100 replay-inversion pairs: %.3f CPU seconds\n" (fromIntegral (finished - started) / 1.0e12 :: Double)
