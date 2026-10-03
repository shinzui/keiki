-- | The SCXML fixtures shared by "Keiki.Render.SCXMLSpec" and the
-- independent checker @scripts/check-scxml.py@ (driven by
-- @scripts/check-scxml.sh@).
--
-- 'scxmlFixtures' renders every fixture document through the public
-- "Keiki.Render.SCXML" API; 'writeScxmlFixtures' writes them as UTF-8
-- files. The test executable calls 'writeScxmlFixtures' instead of running
-- Hspec when @KEIKI_SCXML_EXPORT_DIR@ is set, so the independent checker
-- always reads freshly generated output from the compiled fixtures.
--
-- The checker hard-codes the expected graph and descriptions of each
-- document, so a change to a fixture here must be mirrored there.
module Keiki.Render.SCXMLFixtures
  ( -- * Fixture documents
    scxmlFixtures,
    writeScxmlFixtures,
    exportDirVariable,

    -- * Transducers
    edgeCases,
    EcState (..),
    replayEdges,
    RpState (..),
    hostileNames,
    HState (..),
    hostileText,
    unshowableLiterals,
    UState (..),
  )
where

import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Keiki.Core
  ( Cmp (..),
    Edge (..),
    EdgeMode (..),
    HsPred (..),
    InCtor,
    Index (..),
    IndexN (..),
    OutFields (..),
    OutTerm,
    RegFile (..),
    SymTransducer (..),
    Term (..),
    Update (..),
    WireCtor,
    combine,
    lit,
    opaqueLit,
    pack,
    tadd,
    unavailableInCtor,
    unavailableWireCtor,
  )
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

structural :: ScxmlOptions
structural = defaultScxmlOptions {includeBehavior = False}

allEdges :: ScxmlOptions
allEdges = defaultScxmlOptions {edgeView = AllDeclaredEdges}

-- | Every fixture document, by fixed basename. The first export failure
-- is returned; no fixture is silently dropped.
scxmlFixtures :: Either ScxmlError [(FilePath, Text)]
scxmlFixtures =
  traverse
    (\(name, doc) -> (,) name <$> doc)
    [ ("email-delivery.scxml", toSCXML emailDelivery),
      ("email-delivery-structural.scxml", toSCXMLWith structural emailDelivery),
      ("edge-cases.scxml", toSCXML edgeCases),
      ("replay-forward.scxml", toSCXML replayEdges),
      ("replay-all-edges.scxml", toSCXMLWith allEdges replayEdges),
      ("hostile-text.scxml", toSCXML hostileNames),
      ("unshowable-structural.scxml", toSCXMLWith structural unshowableLiterals)
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

-- * Edge cases ---------------------------------------------------------------

-- | Commands for 'edgeCases'. Constructor display names are chosen per
-- 'InCtor' below, independently of these Haskell names.
data EcCmd = EcGo | EcStop | EcPing | EcOdd
  deriving (Eq, Show)

data EcEvt = EcA Int | EcB | EcC
  deriving (Eq, Show)

type EcRegs = '[ '("count", Int), '("note", Text)]

-- | @EcStart@ carries every guard shape; @EcAccepting@ is accepting but
-- has a live self-loop; @EcDone@ is accepting with no edges; @EcIsolated@
-- is unreachable and has no edges.
data EcState = EcStart | EcAccepting | EcDone | EcIsolated
  deriving (Eq, Show, Enum, Bounded)

ecInCtor :: String -> EcCmd -> InCtor EcCmd '[]
ecInCtor name c =
  unavailableInCtor name (\x -> if x == c then Just RNil else Nothing) (\RNil -> c)

inGo, inStop, inPing, inUnsafe, inReserved :: InCtor EcCmd '[]
inGo = ecInCtor "Go" EcGo
inStop = ecInCtor "Stop" EcStop
inPing = ecInCtor "Ping" EcPing
inUnsafe = ecInCtor "Do Thing" EcOdd
inReserved = ecInCtor "keiki_edge_s0_e9" EcOdd

wireA :: WireCtor EcEvt (Int, ())
wireA =
  unavailableWireCtor "A" (\case EcA n -> Just (n, ()); _ -> Nothing) (\(n, ()) -> EcA n)

wireB, wireC :: WireCtor EcEvt ()
wireB = unavailableWireCtor "B" (\case EcB -> Just (); _ -> Nothing) (\() -> EcB)
wireC = unavailableWireCtor "C" (\case EcC -> Just (); _ -> Nothing) (\() -> EcC)

countReg :: Term EcRegs EcCmd ifs Int
countReg = TReg ZIdx

noteReg :: Term EcRegs EcCmd ifs Text
noteReg = TReg (SIdx ZIdx)

liveEdge ::
  HsPred EcRegs EcCmd ->
  [OutTermEc] ->
  EcState ->
  Edge (HsPred EcRegs EcCmd) EcRegs EcCmd EcEvt EcState
liveEdge g outs tgt =
  Edge {guard = g, update = UKeep, output = outs, target = tgt, mode = Live}

type OutTermEc = OutTerm EcRegs EcCmd EcEvt

edgeCases :: SymTransducer (HsPred EcRegs EcCmd) EcRegs EcState EcCmd EcEvt
edgeCases =
  SymTransducer
    { edgesOut = \case
        EcStart ->
          [ -- e0: disjunction, zero outputs, one assignment.
            Edge
              { guard = POr (PInCtor inGo) (PInCtor inStop),
                update = USet (IZ @"count") (lit (1 :: Int)),
                output = [],
                target = EcAccepting,
                mode = Live
              },
            -- e1: negation, three ordered outputs.
            liveEdge
              (PNot (PInCtor inGo))
              [ pack inPing wireA (OFCons countReg OFNil),
                pack inPing wireB OFNil,
                pack inPing wireC OFNil
              ]
              EcDone,
            -- e2: wildcard self-loop.
            liveEdge PTop [] EcStart,
            -- e3: a constructor name using the reserved exporter prefix.
            liveEdge (PAnd (PInCtor inReserved) (PEq countReg (lit 0))) [] EcDone,
            -- e4: two constructor tests in one conjunction.
            liveEdge (PAnd (PInCtor inPing) (PInCtor inGo)) [] EcDone,
            -- e5: a constructor name that is not an event token.
            liveEdge (PAnd (PInCtor inUnsafe) PTop) [] EcDone,
            -- e6: an ordinary builder-shaped edge with arithmetic, an
            -- opaque function whose body must never run, and an opaque
            -- literal.
            Edge
              { guard = PAnd (PInCtor inGo) (PCmp CmpGt countReg (lit 0)),
                update =
                  USet (IZ @"count") (tadd countReg (lit 1))
                    `combine` USet
                      (IS (IZ @"note"))
                      (TApp1 (\_ -> error "opaque function body was run") noteReg),
                output = [pack inGo wireA (OFCons (opaqueLit 42) OFNil)],
                target = EcDone,
                mode = Live
              }
          ]
        EcAccepting -> [liveEdge (PInCtor inPing) [] EcAccepting]
        EcDone -> []
        EcIsolated -> [],
      initial = EcStart,
      initialRegs = error "edgeCases: initialRegs was forced",
      isFinal = \s -> s == EcAccepting || s == EcDone
    }

-- * Replay-only edges --------------------------------------------------------

data RpCmd = RpClose | RpReopen
  deriving (Eq, Show)

data RpEvt = RpClosed | RpReopened
  deriving (Eq, Show)

data RpState = RpOpen | RpShut
  deriving (Eq, Show, Enum, Bounded)

inClose, inReopen :: InCtor RpCmd '[]
inClose = unavailableInCtor "Close" (\case RpClose -> Just RNil; _ -> Nothing) (\RNil -> RpClose)
inReopen = unavailableInCtor "Reopen" (\case RpReopen -> Just RNil; _ -> Nothing) (\RNil -> RpReopen)

wireClosed, wireReopened :: WireCtor RpEvt ()
wireClosed = unavailableWireCtor "Closed" (\case RpClosed -> Just (); _ -> Nothing) (\() -> RpClosed)
wireReopened = unavailableWireCtor "Reopened" (\case RpReopened -> Just (); _ -> Nothing) (\() -> RpReopened)

-- | @RpShut@ is accepting and its only outgoing edge is replay-only, so it
-- is a @\<final\>@ in the forward view and a @\<state\>@ in the
-- all-edges view.
replayEdges :: SymTransducer (HsPred '[] RpCmd) '[] RpState RpCmd RpEvt
replayEdges =
  SymTransducer
    { edgesOut = \case
        RpOpen ->
          [ Edge
              { guard = PInCtor inClose,
                update = UKeep,
                output = [pack inClose wireClosed OFNil],
                target = RpShut,
                mode = Live
              },
            Edge
              { guard = PInCtor inReopen,
                update = UKeep,
                output = [pack inReopen wireReopened OFNil],
                target = RpOpen,
                mode = ReplayOnly
              }
          ]
        RpShut ->
          [ Edge
              { guard = PInCtor inReopen,
                update = UKeep,
                output = [pack inReopen wireReopened OFNil],
                target = RpOpen,
                mode = ReplayOnly
              }
          ],
      initial = RpOpen,
      initialRegs = RNil,
      isFinal = (== RpShut)
    }

-- * Hostile names ------------------------------------------------------------

-- | Text that must survive XML parsing plus JSON decoding unchanged:
-- non-ASCII (BMP and astral), quotes, markup characters, comment
-- delimiters, newlines, a backslash, an XML-forbidden control character,
-- C1/DEL, noncharacters, and a trailing hyphen.
hostileText :: String
hostileText =
  "\x00DC\&nic\x00F8\&de \x65E5\x672C \x1F389 \"quote\" 'apos' & <tag> </scxml> ]]> "
    ++ "\n new\r\nline\ttab \\ backslash -- double --> end <!-- open "
    ++ "\SOH \DEL \x0085 \xFDD0 \xFFFE \x10FFFF -"

-- | States whose 'show' text collides exactly (@HSame1@/@HSame2@), collides
-- after sanitization (@HDash@), or is hostile (@HHostile@).
data HState = HSame1 | HSame2 | HDash | HHostile
  deriving (Eq, Enum, Bounded)

instance Show HState where
  show HSame1 = "Same Name"
  show HSame2 = "Same Name"
  show HDash = "Same-Name"
  show HHostile = hostileText

data HCmd = HPoke | HOdd
  deriving (Eq, Show)

data HEvt = HEvt
  deriving (Eq, Show)

type HRegs = '[ '("a--b", Text)]

inHostile, inPoke :: InCtor HCmd '[]
inHostile = unavailableInCtor hostileText (\case HOdd -> Just RNil; _ -> Nothing) (\RNil -> HOdd)
inPoke = unavailableInCtor "Poke" (\case HPoke -> Just RNil; _ -> Nothing) (\RNil -> HPoke)

wireHostile :: WireCtor HEvt ()
wireHostile = unavailableWireCtor hostileText (\HEvt -> Just ()) (\() -> HEvt)

hostileNames :: SymTransducer (HsPred HRegs HCmd) HRegs HState HCmd HEvt
hostileNames =
  SymTransducer
    { edgesOut = \case
        HSame1 ->
          [ Edge
              { guard = PInCtor inHostile,
                update = USet (IZ @"a--b") (TReg ZIdx),
                output = [pack inHostile wireHostile OFNil],
                target = HHostile,
                mode = Live
              }
          ]
        HSame2 ->
          [ Edge
              { guard = PInCtor inPoke,
                update = UKeep,
                output = [],
                target = HSame1,
                mode = Live
              }
          ]
        HDash ->
          [ Edge
              { guard = PInCtor inPoke,
                update = UKeep,
                output = [],
                target = HSame2,
                mode = Live
              }
          ]
        HHostile -> [],
      initial = HSame1,
      initialRegs = RCons (Proxy @"a--b") (T.pack "initial") RNil,
      isFinal = (== HHostile)
    }

-- * Unshowable literals ------------------------------------------------------

-- | A literal whose 'Show' instance fails. Structural export must not
-- force it; readable export does (the ADR-6 partial-'Show' limitation).
data Unshowable = Unshowable
  deriving (Eq)

instance Show Unshowable where
  show _ = error "literal Show instance was forced"

data UCmd = UGo
  deriving (Eq, Show)

data UEvt = UEvt Unshowable

data UState = UStart | UEnd
  deriving (Eq, Show, Enum, Bounded)

type URegs = '[ '("u", Unshowable)]

inUGo :: InCtor UCmd '[]
inUGo = unavailableInCtor "UGo" (\UGo -> Just RNil) (\RNil -> UGo)

wireUEvt :: WireCtor UEvt (Unshowable, ())
wireUEvt = unavailableWireCtor "UEvt" (\(UEvt u) -> Just (u, ())) (\(u, ()) -> UEvt u)

unshowableLiterals :: SymTransducer (HsPred URegs UCmd) URegs UState UCmd UEvt
unshowableLiterals =
  SymTransducer
    { edgesOut = \case
        UStart ->
          [ Edge
              { guard = PAnd (PInCtor inUGo) (PEq (TReg ZIdx) (lit Unshowable)),
                update =
                  USet
                    (IZ @"u")
                    (TApp1 (\_ -> error "opaque function body was run") (lit Unshowable)),
                output = [pack inUGo wireUEvt (OFCons (lit Unshowable) OFNil)],
                target = UEnd,
                mode = Live
              }
          ]
        UEnd -> [],
      initial = UStart,
      initialRegs = error "unshowableLiterals: initialRegs was forced",
      isFinal = (== UEnd)
    }
