-- | Shared fixture, integration point 4 of
-- @docs/masterplans/16-harden-keiki-correctness-and-api-surfaces-surfaced-by-the-2026-07-architecture-review.md@:
-- consumed by EP-71 (validation alignment), EP-73 (round-trip property
-- harness), and EP-74 (composition semantics). Do not fold into a spec module.
module Keiki.Fixtures.SplitCoverage
  ( SplitCmd (..),
    SplitEvent (..),
    inCtorBegin,
    wireOutAB,
    wireOutBC,
    wireOutABC,
    wireOutA,
    splitCoverageBad,
    splitCoverageFixed,
    splitCoverageUnionMiss,
    splitCoverageSingleMiss,
  )
where

import Data.Proxy (Proxy (..))
import Keiki.Core

-- | One three-field command used to expose the difference between union
-- coverage and replay's head-only inversion contract.
data SplitCmd = Begin Int Int Int
  deriving stock (Eq, Show)

-- | Event constructors for complete, split, and incomplete coverage shapes.
data SplitEvent
  = OutAB Int Int
  | OutBC Int Int
  | OutABC Int Int Int
  | OutA Int
  deriving stock (Eq, Show)

type BeginFields =
  '[ '("a", Int),
     '("b", Int),
     '("c", Int)
   ]

inCtorBegin :: InCtor SplitCmd BeginFields
inCtorBegin =
  InCtor
    { icName = "Begin",
      icMatch = \case
        Begin a b c ->
          Just $
            RCons (Proxy @"a") a $
              RCons (Proxy @"b") b $
                RCons (Proxy @"c") c RNil,
      icBuild = \(RCons _ a (RCons _ b (RCons _ c RNil))) -> Begin a b c
    }

wireOutAB :: WireCtor SplitEvent (Int, (Int, ()))
wireOutAB =
  WireCtor
    { wcName = "OutAB",
      wcMatch = \case OutAB a b -> Just (a, (b, ())); _ -> Nothing,
      wcBuild = \(a, (b, ())) -> OutAB a b
    }

wireOutBC :: WireCtor SplitEvent (Int, (Int, ()))
wireOutBC =
  WireCtor
    { wcName = "OutBC",
      wcMatch = \case OutBC b c -> Just (b, (c, ())); _ -> Nothing,
      wcBuild = \(b, (c, ())) -> OutBC b c
    }

wireOutABC :: WireCtor SplitEvent (Int, (Int, (Int, ())))
wireOutABC =
  WireCtor
    { wcName = "OutABC",
      wcMatch = \case OutABC a b c -> Just (a, (b, (c, ()))); _ -> Nothing,
      wcBuild = \(a, (b, (c, ()))) -> OutABC a b c
    }

wireOutA :: WireCtor SplitEvent (Int, ())
wireOutA =
  WireCtor
    { wcName = "OutA",
      wcMatch = \case OutA a -> Just (a, ()); _ -> Nothing,
      wcBuild = \(a, ()) -> OutA a
    }

beginA :: Term '[] SplitCmd BeginFields Int
beginA = TInpCtorField inCtorBegin (#a :: Index BeginFields Int)

beginB :: Term '[] SplitCmd BeginFields Int
beginB = TInpCtorField inCtorBegin (#b :: Index BeginFields Int)

beginC :: Term '[] SplitCmd BeginFields Int
beginC = TInpCtorField inCtorBegin (#c :: Index BeginFields Int)

splitTransducer :: [OutTerm '[] SplitCmd SplitEvent] -> SymTransducer (HsPred '[] SplitCmd) '[] Bool SplitCmd SplitEvent
splitTransducer outputs =
  SymTransducer
    { edgesOut = \case
        False ->
          [ Edge
              { guard = matchInCtor inCtorBegin,
                update = UKeep,
                output = outputs,
                target = True,
                mode = Live
              }
          ]
        True -> [],
      initial = False,
      initialRegs = RNil,
      isFinal = id
    }

-- | Defective shape: the output union covers @a,b,c@, but the head covers
-- only @a,b@, so replay cannot reconstruct @Begin@ from the first event.
splitCoverageBad :: SymTransducer (HsPred '[] SplitCmd) '[] Bool SplitCmd SplitEvent
splitCoverageBad =
  splitTransducer
    [ pack inCtorBegin wireOutAB (beginA *: beginB *: oNil),
      pack inCtorBegin wireOutBC (beginB *: beginC *: oNil)
    ]

-- | Repaired shape: the head event alone covers all command fields.
splitCoverageFixed :: SymTransducer (HsPred '[] SplitCmd) '[] Bool SplitCmd SplitEvent
splitCoverageFixed =
  splitTransducer
    [ pack inCtorBegin wireOutABC (beginA *: beginB *: beginC *: oNil),
      pack inCtorBegin wireOutBC (beginB *: beginC *: oNil)
    ]

-- | The output union still omits @c@ entirely.
splitCoverageUnionMiss :: SymTransducer (HsPred '[] SplitCmd) '[] Bool SplitCmd SplitEvent
splitCoverageUnionMiss =
  splitTransducer
    [ pack inCtorBegin wireOutAB (beginA *: beginB *: oNil),
      pack inCtorBegin wireOutA (beginA *: oNil)
    ]

-- | A one-event edge that omits @b@ and @c@.
splitCoverageSingleMiss :: SymTransducer (HsPred '[] SplitCmd) '[] Bool SplitCmd SplitEvent
splitCoverageSingleMiss =
  splitTransducer [pack inCtorBegin wireOutA (beginA *: oNil)]
