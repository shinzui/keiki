-- | Stateful fixtures for EP-74's sequential-composition regressions.
-- Keep these transducers independent of hspec so later property suites can
-- compare 'compose' with an explicit sequential reference.
module Keiki.Fixtures.ComposeStateful
  ( SourceCmd (..),
    MidVal (..),
    OutVal (..),
    StageOut (..),
    PairCmd (..),
    Mid2 (..),
    WrongOut (..),
    M2SourceCmd (..),
    CounterRegs,
    SinkRegs,
    PhaseRegs,
    CounterVertex (..),
    SinkVertex (..),
    PhaseVertex (..),
    PairVertex (..),
    M2SourceVertex (..),
    WrongVertex (..),
    counterSource,
    lastValueSink,
    pairSource,
    twoPhaseSink,
    m2aSource,
    wrongOrderSink,
    readSourceCount,
    readSinkLast,
    readPhase,
  )
where

import Data.Proxy (Proxy (..))
import Keiki.Core
import Keiki.Generics (Append)

data SourceCmd = Tick
  deriving stock (Eq, Show)

data MidVal = MidVal Int
  deriving stock (Eq, Show)

data OutVal = OutVal Int
  deriving stock (Eq, Show)

data StageOut = Stage1 Int | Stage2 Int
  deriving stock (Eq, Show)

data PairCmd = Go
  deriving stock (Eq, Show)

data M2SourceCmd = ProduceA
  deriving stock (Eq, Show)

data Mid2 = M2A Int | M2B Int
  deriving stock (Eq, Show)

data WrongOut = SawA Int | SawB Int
  deriving stock (Eq, Show)

type CounterRegs = '[ '("srcCount", Int)]

type SinkRegs = '[ '("sinkLast", Int)]

type PhaseRegs = '[ '("phase", Int)]

data CounterVertex = CounterVertex
  deriving stock (Eq, Ord, Show, Enum, Bounded)

data SinkVertex = SinkVertex
  deriving stock (Eq, Ord, Show, Enum, Bounded)

data PairVertex = PairVertex
  deriving stock (Eq, Ord, Show, Enum, Bounded)

data PhaseVertex = PhaseVertex
  deriving stock (Eq, Ord, Show, Enum, Bounded)

data M2SourceVertex = M2SourceVertex
  deriving stock (Eq, Ord, Show, Enum, Bounded)

data WrongVertex = WrongVertex
  deriving stock (Eq, Ord, Show, Enum, Bounded)

inCtorTick :: InCtor SourceCmd '[]
inCtorTick =
  InCtor
    { icName = "Tick",
      icMatch = \case Tick -> Just RNil,
      icBuild = \RNil -> Tick
    }

inCtorGo :: InCtor PairCmd '[]
inCtorGo =
  InCtor
    { icName = "Go",
      icMatch = \case Go -> Just RNil,
      icBuild = \RNil -> Go
    }

inCtorProduceA :: InCtor M2SourceCmd '[]
inCtorProduceA =
  InCtor
    { icName = "ProduceA",
      icMatch = \case ProduceA -> Just RNil,
      icBuild = \RNil -> ProduceA
    }

inCtorMidVal :: InCtor MidVal '[ '("v", Int)]
inCtorMidVal =
  InCtor
    { icName = "MidVal",
      icMatch = \case MidVal v -> Just (RCons (Proxy @"v") v RNil),
      icBuild = \(RCons _ v RNil) -> MidVal v
    }

inCtorM2A :: InCtor Mid2 '[ '("a", Int)]
inCtorM2A =
  InCtor
    { icName = "M2A",
      icMatch = \case
        M2A a -> Just (RCons (Proxy @"a") a RNil)
        M2B _ -> Nothing,
      icBuild = \(RCons _ a RNil) -> M2A a
    }

inCtorM2B :: InCtor Mid2 '[ '("b", Int)]
inCtorM2B =
  InCtor
    { icName = "M2B",
      icMatch = \case
        M2A _ -> Nothing
        M2B b -> Just (RCons (Proxy @"b") b RNil),
      icBuild = \(RCons _ b RNil) -> M2B b
    }

wireMidVal :: WireCtor MidVal (Int, ())
wireMidVal =
  WireCtor
    { wcName = "MidVal",
      wcMatch = \case MidVal v -> Just (v, ()),
      wcBuild = \(v, ()) -> MidVal v
    }

wireM2A :: WireCtor Mid2 (Int, ())
wireM2A =
  WireCtor
    { wcName = "M2A",
      wcMatch = \case
        M2A a -> Just (a, ())
        M2B _ -> Nothing,
      wcBuild = \(a, ()) -> M2A a
    }

wireOutVal :: WireCtor OutVal (Int, ())
wireOutVal =
  WireCtor
    { wcName = "OutVal",
      wcMatch = \case OutVal v -> Just (v, ()),
      wcBuild = \(v, ()) -> OutVal v
    }

wireStage1 :: WireCtor StageOut (Int, ())
wireStage1 =
  WireCtor
    { wcName = "Stage1",
      wcMatch = \case
        Stage1 v -> Just (v, ())
        Stage2 _ -> Nothing,
      wcBuild = \(v, ()) -> Stage1 v
    }

wireStage2 :: WireCtor StageOut (Int, ())
wireStage2 =
  WireCtor
    { wcName = "Stage2",
      wcMatch = \case
        Stage1 _ -> Nothing
        Stage2 v -> Just (v, ()),
      wcBuild = \(v, ()) -> Stage2 v
    }

wireSawA :: WireCtor WrongOut (Int, ())
wireSawA =
  WireCtor
    { wcName = "SawA",
      wcMatch = \case
        SawA v -> Just (v, ())
        SawB _ -> Nothing,
      wcBuild = \(v, ()) -> SawA v
    }

wireSawB :: WireCtor WrongOut (Int, ())
wireSawB =
  WireCtor
    { wcName = "SawB",
      wcMatch = \case
        SawA _ -> Nothing
        SawB v -> Just (v, ()),
      wcBuild = \(v, ()) -> SawB v
    }

counterSource :: SymTransducer (HsPred CounterRegs SourceCmd) CounterRegs CounterVertex SourceCmd MidVal
counterSource =
  SymTransducer
    { edgesOut = \CounterVertex ->
        [ Edge
            { guard = matchInCtor inCtorTick,
              update =
                USet
                  (#srcCount :: IndexN "srcCount" CounterRegs Int)
                  (proj (#srcCount :: Index CounterRegs Int) .+ lit 1),
              output =
                [ pack
                    inCtorTick
                    wireMidVal
                    (proj (#srcCount :: Index CounterRegs Int) *: oNil)
                ],
              target = CounterVertex
            }
        ],
      initial = CounterVertex,
      initialRegs = RCons (Proxy @"srcCount") 0 RNil,
      isFinal = const True
    }

lastValueSink :: SymTransducer (HsPred SinkRegs MidVal) SinkRegs SinkVertex MidVal OutVal
lastValueSink =
  SymTransducer
    { edgesOut = \SinkVertex ->
        [ Edge
            { guard = matchInCtor inCtorMidVal,
              update =
                USet
                  (#sinkLast :: IndexN "sinkLast" SinkRegs Int)
                  (inpCtor inCtorMidVal (#v :: Index '[ '("v", Int)] Int)),
              output =
                [ pack
                    inCtorMidVal
                    wireOutVal
                    (inpCtor inCtorMidVal (#v :: Index '[ '("v", Int)] Int) *: oNil)
                ],
              target = SinkVertex
            }
        ],
      initial = SinkVertex,
      initialRegs = RCons (Proxy @"sinkLast") (-1) RNil,
      isFinal = const True
    }

pairSource :: SymTransducer (HsPred '[] PairCmd) '[] PairVertex PairCmd MidVal
pairSource =
  SymTransducer
    { edgesOut = \PairVertex ->
        [ Edge
            { guard = matchInCtor inCtorGo,
              update = UKeep,
              output =
                [ pack inCtorGo wireMidVal (lit 10 *: oNil),
                  pack inCtorGo wireMidVal (lit 20 *: oNil)
                ],
              target = PairVertex
            }
        ],
      initial = PairVertex,
      initialRegs = RNil,
      isFinal = const True
    }

twoPhaseSink :: SymTransducer (HsPred PhaseRegs MidVal) PhaseRegs PhaseVertex MidVal StageOut
twoPhaseSink =
  SymTransducer
    { edgesOut = \PhaseVertex ->
        [ Edge
            { guard =
                matchInCtor inCtorMidVal
                  .&& (proj (#phase :: Index PhaseRegs Int) .== lit 0),
              update = USet (#phase :: IndexN "phase" PhaseRegs Int) (lit 1),
              output =
                [ pack
                    inCtorMidVal
                    wireStage1
                    (inpCtor inCtorMidVal (#v :: Index '[ '("v", Int)] Int) *: oNil)
                ],
              target = PhaseVertex
            },
          Edge
            { guard =
                matchInCtor inCtorMidVal
                  .&& (proj (#phase :: Index PhaseRegs Int) .== lit 1),
              update = USet (#phase :: IndexN "phase" PhaseRegs Int) (lit 2),
              output =
                [ pack
                    inCtorMidVal
                    wireStage2
                    (inpCtor inCtorMidVal (#v :: Index '[ '("v", Int)] Int) *: oNil)
                ],
              target = PhaseVertex
            }
        ],
      initial = PhaseVertex,
      initialRegs = RCons (Proxy @"phase") 0 RNil,
      isFinal = const True
    }

m2aSource :: SymTransducer (HsPred '[] M2SourceCmd) '[] M2SourceVertex M2SourceCmd Mid2
m2aSource =
  SymTransducer
    { edgesOut = \M2SourceVertex ->
        [ Edge
            { guard = matchInCtor inCtorProduceA,
              update = UKeep,
              output = [pack inCtorProduceA wireM2A (lit 5 *: oNil)],
              target = M2SourceVertex
            }
        ],
      initial = M2SourceVertex,
      initialRegs = RNil,
      isFinal = const True
    }

wrongOrderSink :: SymTransducer (HsPred '[] Mid2) '[] WrongVertex Mid2 WrongOut
wrongOrderSink =
  SymTransducer
    { edgesOut = \WrongVertex ->
        [ Edge
            { guard =
                matchInCtor inCtorM2A
                  .&& (inpCtor inCtorM2A (#a :: Index '[ '("a", Int)] Int) .== lit 5),
              update = UKeep,
              output =
                [ pack
                    inCtorM2A
                    wireSawA
                    (inpCtor inCtorM2A (#a :: Index '[ '("a", Int)] Int) *: oNil)
                ],
              target = WrongVertex
            },
          Edge
            { guard =
                (inpCtor inCtorM2B (#b :: Index '[ '("b", Int)] Int) .== lit 5)
                  .&& matchInCtor inCtorM2B,
              update = UKeep,
              output =
                [ pack
                    inCtorM2B
                    wireSawB
                    (inpCtor inCtorM2B (#b :: Index '[ '("b", Int)] Int) *: oNil)
                ],
              target = WrongVertex
            }
        ],
      initial = WrongVertex,
      initialRegs = RNil,
      isFinal = const True
    }

readSourceCount :: RegFile (Append CounterRegs SinkRegs) -> Int
readSourceCount regs = regs ! (#srcCount :: Index (Append CounterRegs SinkRegs) Int)

readSinkLast :: RegFile (Append CounterRegs SinkRegs) -> Int
readSinkLast regs = regs ! (#sinkLast :: Index (Append CounterRegs SinkRegs) Int)

readPhase :: RegFile (Append '[] PhaseRegs) -> Int
readPhase regs = regs ! (#phase :: Index (Append '[] PhaseRegs) Int)
