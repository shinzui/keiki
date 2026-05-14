{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- | EP-36 M4 — performance baselines for the four §10 reference cases
-- (condensed to keep CI bench duration under ~30 seconds total).
--
-- For each fixture, four measurements:
--
-- * @encode-via-Value@      — @Aeson.encode . regFileToJSON@
-- * @encode-via-Encoding@   — @encodingToLazyByteString . regFileToEncoding@
-- * @decode@                — @regFileFromJSON . fromJust . Aeson.decode@
-- * @hash@                  — @regFileShapeHash (Proxy \@SlotList)@
--
-- Run with @cabal bench keiki-codec-json:keiki-codec-json-bench@. The
-- baseline numbers are checked in at @bench/baseline.csv@; CI compares
-- new runs against the baseline and flags drift, but DOES NOT block
-- merges. The cross-GHC hash gate (M5) is the release-blocking gate;
-- the bench is a tracked metric.
module Main (main) where

import Control.DeepSeq (NFData (..))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Encoding as AesonEnc
import qualified Data.ByteString.Lazy as LBS
import Data.Proxy (Proxy (..))
import qualified Data.Text as T
import Data.Text (Text)
import Test.Tasty.Bench (bench, bgroup, defaultMain, nf)

import Keiki.Codec.JSON (regFileFromJSON, regFileToEncoding, regFileToJSON)
import Keiki.Core (RegFile (..), Slot)
import Keiki.Shape (regFileShapeHash)


-- * NFData for RegFile rs (bench-local orphan) -------------------------------

-- Bench measurements use 'nf', which needs 'NFData'. Inductive walker
-- forces every slot's value to normal form via the slot type's
-- 'NFData' instance.
class NFDataRegFile (rs :: [Slot]) where
  rnfRegFile :: RegFile rs -> ()

instance NFDataRegFile '[] where
  rnfRegFile RNil = ()

instance (NFData t, NFDataRegFile rs)
       => NFDataRegFile ('(s, t) ': rs) where
  rnfRegFile (RCons _ x rest) = rnf x `seq` rnfRegFile rest

instance NFDataRegFile rs => NFData (RegFile rs) where
  rnf = rnfRegFile


-- * §10 Case A — Multi-party contract signing (condensed) -------------------
--
-- 5 parties, 50 audit entries → ~5 KB encoded.

type SlotsA =
  '[ '("retryCount", Int)
   , '("auditLog", [Text])
   , '("currentPhase", Text)
   ]


fixtureA :: RegFile SlotsA
fixtureA =
  RCons (Proxy @"retryCount") 3
    $ RCons (Proxy @"auditLog") (replicate 50 (T.pack "audit:partial-signature-recorded"))
    $ RCons (Proxy @"currentPhase") (T.pack "phase-3-awaiting-final-signature") RNil


-- * §10 Case B — Long-running batch reconciliation (condensed) --------------
--
-- 5000 processed items → ~250 KB encoded. This is the streaming-encoder
-- motivating case (R10) — the Value path allocates the intermediate
-- @Aeson.Value@ for the whole list; the Encoding path walks slot-by-
-- slot.

type SlotsB =
  '[ '("processedItems", [(Int, Text)])
   , '("phase", Text)
   ]


fixtureB :: RegFile SlotsB
fixtureB =
  RCons (Proxy @"processedItems")
        [(i, T.pack ("item-result-" <> show i)) | i <- [1 .. 5000]]
    $ RCons (Proxy @"phase") (T.pack "reconciling") RNil


-- * §10 Case C — Customer support ticket aggregate (condensed) --------------
--
-- 100 comments + 10 escalation entries → ~25 KB encoded.

type SlotsC =
  '[ '("comments", [Text])
   , '("escalationHistory", [Text])
   , '("priority", Text)
   , '("channel", Text)
   ]


fixtureC :: RegFile SlotsC
fixtureC =
  RCons (Proxy @"comments")
        [T.pack ("comment-" <> show i <> ": " <> "lorem-ipsum-dolor-sit-amet")
          | i <- [1 :: Int .. 100]]
    $ RCons (Proxy @"escalationHistory")
        [T.pack ("escalation-" <> show i) | i <- [1 :: Int .. 10]]
    $ RCons (Proxy @"priority") (T.pack "high")
    $ RCons (Proxy @"channel") (T.pack "email") RNil


-- * §10 Case D — Real-time auction aggregate (condensed) --------------------
--
-- 1000 bids → ~50 KB encoded. High-write-rate snapshot pressure.

type SlotsD =
  '[ '("bidHistory", [(Int, Int)])
   , '("status", Text)
   , '("watchers", [Int])
   ]


fixtureD :: RegFile SlotsD
fixtureD =
  RCons (Proxy @"bidHistory")
        [(t, t * 110 + 5000) | t <- [1 :: Int .. 1000]]
    $ RCons (Proxy @"status") (T.pack "active")
    $ RCons (Proxy @"watchers") [10000 .. 10100] RNil


-- * Driver -------------------------------------------------------------------

main :: IO ()
main = do
  let bytesA = Aeson.encode (regFileToJSON fixtureA)
      bytesB = Aeson.encode (regFileToJSON fixtureB)
      bytesC = Aeson.encode (regFileToJSON fixtureC)
      bytesD = Aeson.encode (regFileToJSON fixtureD)
  -- Force the input bytes so the decode benchmark isn't paying for
  -- the encode work as a side effect.
  _ <- pure $! LBS.length bytesA + LBS.length bytesB
            + LBS.length bytesC + LBS.length bytesD
  defaultMain
    [ bgroup "BenchA_ContractSign"
        [ bench "encode-via-Value"    $ nf (Aeson.encode . regFileToJSON) fixtureA
        , bench "encode-via-Encoding" $ nf (AesonEnc.encodingToLazyByteString . regFileToEncoding) fixtureA
        , bench "decode"              $ nf (decodeFixtureA) bytesA
        , bench "hash"                $ nf (\() -> regFileShapeHash (Proxy @SlotsA)) ()
        ]
    , bgroup "BenchB_BatchRecon"
        [ bench "encode-via-Value"    $ nf (Aeson.encode . regFileToJSON) fixtureB
        , bench "encode-via-Encoding" $ nf (AesonEnc.encodingToLazyByteString . regFileToEncoding) fixtureB
        , bench "decode"              $ nf (decodeFixtureB) bytesB
        , bench "hash"                $ nf (\() -> regFileShapeHash (Proxy @SlotsB)) ()
        ]
    , bgroup "BenchC_TicketAgg"
        [ bench "encode-via-Value"    $ nf (Aeson.encode . regFileToJSON) fixtureC
        , bench "encode-via-Encoding" $ nf (AesonEnc.encodingToLazyByteString . regFileToEncoding) fixtureC
        , bench "decode"              $ nf (decodeFixtureC) bytesC
        , bench "hash"                $ nf (\() -> regFileShapeHash (Proxy @SlotsC)) ()
        ]
    , bgroup "BenchD_Auction"
        [ bench "encode-via-Value"    $ nf (Aeson.encode . regFileToJSON) fixtureD
        , bench "encode-via-Encoding" $ nf (AesonEnc.encodingToLazyByteString . regFileToEncoding) fixtureD
        , bench "decode"              $ nf (decodeFixtureD) bytesD
        , bench "hash"                $ nf (\() -> regFileShapeHash (Proxy @SlotsD)) ()
        ]
    ]


decodeFixtureA :: LBS.ByteString -> Either String (RegFile SlotsA)
decodeFixtureA bs = case Aeson.decode bs of
  Nothing -> Left "Aeson.decode failed"
  Just v -> regFileFromJSON v


decodeFixtureB :: LBS.ByteString -> Either String (RegFile SlotsB)
decodeFixtureB bs = case Aeson.decode bs of
  Nothing -> Left "Aeson.decode failed"
  Just v -> regFileFromJSON v


decodeFixtureC :: LBS.ByteString -> Either String (RegFile SlotsC)
decodeFixtureC bs = case Aeson.decode bs of
  Nothing -> Left "Aeson.decode failed"
  Just v -> regFileFromJSON v


decodeFixtureD :: LBS.ByteString -> Either String (RegFile SlotsD)
decodeFixtureD bs = case Aeson.decode bs of
  Nothing -> Left "Aeson.decode failed"
  Just v -> regFileFromJSON v
