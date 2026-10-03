-- | The SCXML documents checked outside Haskell by
-- @scripts/check-scxml.py@ (see @scripts/check-scxml.sh@).
--
-- 'scxmlFixtures' renders every fixture through the public
-- "Keiki.Render.SCXML" API; 'writeScxmlFixtures' writes them as UTF-8
-- files. The test executable calls 'writeScxmlFixtures' instead of running
-- Hspec when @KEIKI_SCXML_EXPORT_DIR@ is set, so the independent checker
-- always reads freshly generated output from the compiled fixtures.
module Keiki.Render.SCXMLFixtures
  ( scxmlFixtures,
    writeScxmlFixtures,
    exportDirVariable,
  )
where

import Data.Text (Text)
import Data.Text.IO qualified as TIO
import Keiki.Fixtures.EmailDelivery (emailDelivery)
import Keiki.Render.SCXML
import System.Exit (exitFailure)
import System.IO
  ( IOMode (WriteMode),
    hPutStrLn,
    hSetEncoding,
    hSetNewlineMode,
    noNewlineTranslation,
    stderr,
    utf8,
    withFile,
  )

-- | The environment variable naming the directory that receives the
-- generated fixtures.
exportDirVariable :: String
exportDirVariable = "KEIKI_SCXML_EXPORT_DIR"

-- | Every fixture document, by fixed basename. The first export failure
-- is returned; no fixture is silently dropped.
scxmlFixtures :: Either ScxmlError [(FilePath, Text)]
scxmlFixtures =
  traverse
    (\(name, doc) -> (,) name <$> doc)
    [ ("email-delivery.scxml", toSCXML emailDelivery)
    ]

-- | Write every fixture into an existing directory as UTF-8 without
-- newline translation. Exits with failure (writing nothing) when any
-- fixture fails to export.
writeScxmlFixtures :: FilePath -> IO ()
writeScxmlFixtures dir = case scxmlFixtures of
  Left err -> do
    hPutStrLn stderr ("SCXML fixture export failed: " ++ show err)
    exitFailure
  Right docs -> mapM_ write docs
  where
    write (name, doc) =
      withFile (dir ++ "/" ++ name) WriteMode $ \h -> do
        hSetEncoding h utf8
        hSetNewlineMode h noNewlineTranslation
        TIO.hPutStr h doc
