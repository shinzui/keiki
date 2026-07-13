-- |
-- Module      : Keiki.Codec.JSON.Test.GoldenFile
-- Description : Checked-in whole-RegFile JSON golden-file discipline.
--
-- 'regFileGoldenFileSpec' checks both persistence directions: the current
-- decoder must read bytes checked into source control as the fixed expected
-- value, and the current Value-path encoder must reproduce those bytes exactly.
--
-- To accept an intentional wire-format change, run the consumer test suite once
-- with @KEIKI_UPDATE_GOLDENS=1@. The helper rewrites the file and deliberately
-- fails; unset the variable, review the diff, and rerun before committing.
module Keiki.Codec.JSON.Test.GoldenFile
  ( regFileGoldenFileSpec,
  )
where

import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Keiki.Codec.JSON (RegFileToJSON, regFileFromJSON, regFileToJSON)
import Keiki.Codec.JSON.Test (EqRegFile (eqRegFile))
import Keiki.Core (RegFile)
import System.Environment (lookupEnv)
import Test.Hspec (Spec, describe, expectationFailure, it, runIO, shouldBe)

-- | Pin a fixed register file against a checked-in Value-path JSON file.
--
-- The file path is resolved relative to the consumer package's test working
-- directory. Add it to the package's @extra-source-files@ so source
-- distributions retain the compatibility evidence.
regFileGoldenFileSpec ::
  forall rs.
  (RegFileToJSON rs, EqRegFile rs) =>
  String ->
  FilePath ->
  RegFile rs ->
  Spec
regFileGoldenFileSpec label path expected = describe label $ do
  update <- runIO (lookupEnv "KEIKI_UPDATE_GOLDENS")
  case update of
    Just _ -> do
      runIO (LBS.writeFile path currentBytes)
      it "regenerates and requires a clean review run" $
        expectationFailure regenerationMessage
    Nothing -> do
      historicalBytes <- runIO (LBS.readFile path)
      it "decodes checked-in bytes to the fixed value" $
        case Aeson.decode historicalBytes of
          Nothing -> expectationFailure "golden file is not valid JSON"
          Just value -> case regFileFromJSON @rs value of
            Left message -> expectationFailure ("golden decode failed: " <> message)
            Right actual -> eqRegFile actual expected `shouldBe` True
      it "freezes current Value-path bytes" $
        currentBytes `shouldBe` historicalBytes
  where
    currentBytes = Aeson.encode (regFileToJSON expected)

regenerationMessage :: String
regenerationMessage =
  "golden regenerated; unset KEIKI_UPDATE_GOLDENS, re-run, and review git diff"
