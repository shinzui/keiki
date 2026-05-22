-- | First-class projections of a 'SymTransducer' onto one alphabet
-- at a time.
--
-- The foundations chapter
-- @docs/foundations/04-projections-and-deriving-event-sourcing.md@
-- spells out the central insight that any FST has two acceptor
-- projections:
--
-- * The /input projection/ π₁ — drop the events. The remaining
--   transition function is an acceptor over commands. Its language
--   is the set of command sequences the aggregate accepts.
-- * The /output projection/ π₂ — drop the commands by inverting ω.
--   The remaining transition function is @evolve@ (the
--   event-language acceptor). Its language is the set of event
--   sequences the aggregate could have produced — the set of
--   replayable logs.
--
-- In 'Keiki.Core' these projections are /implicit/: π₁ is
-- 'Keiki.Core.delta'; π₂ is 'Keiki.Core.applyEvent'. This module
-- /names/ them as a first-class data type so downstream code (UI,
-- validation, generated documentation) can pattern-match on a known
-- shape instead of plumbing the step functions by hand.
--
-- == Quick reference
--
-- @
-- accepts (inputAcceptor t)  cmds   :: Bool   -- "is this command sequence in the input language?"
-- accepts (outputAcceptor t) events :: Bool   -- "is this event sequence in the output language?"
-- @
--
-- See @docs/research/acceptor-projections-design.md@ for the design
-- record (deferred scope, why the state carrier is
-- @(s, 'Keiki.Core.RegFile' rs)@, relationship to 'Keiki.Decider').
module Keiki.Acceptor
  ( -- * The acceptor projection
    Acceptor (..)
    -- * Projecting a transducer
  , inputAcceptor
  , outputAcceptor
    -- * Folding helpers
  , runAcceptor
  , accepts
  ) where

import Keiki.Core
  ( BoolAlg
  , RegFile
  , SymTransducer (..)
  , applyEvent
  , delta
  )


-- | A minimal acceptor over alphabet @a@ with state carrier @s@.
--
-- The three fields are the membership question reduced to its
-- essence:
--
-- * @aStep@ — single-step transition. 'Just' on a successful step;
--   'Nothing' to reject (the absence of a transition /is/ rejection).
-- * @aInitial@ — the start state.
-- * @aIsFinal@ — final-state predicate. A run accepts iff it
--   terminates in a state for which this predicate holds.
--
-- The richer return type of 'Keiki.Core.delta' /
-- 'Keiki.Core.applyEvent' (which thread an updated 'RegFile') is
-- preserved by the projections in this module by hiding the register
-- file inside @s@; see 'inputAcceptor' / 'outputAcceptor'.
--
-- 'Acceptor' carries closures and therefore has no 'Show' or 'Eq'
-- instance; assert on 'runAcceptor' or 'accepts' results instead.
data Acceptor a s = Acceptor
  { aStep    :: s -> a -> Maybe s
  , aInitial :: s
  , aIsFinal :: s -> Bool
  }


-- | Project a 'SymTransducer' to its /input/ acceptor (π₁): the
-- acceptor over the command alphabet whose step is
-- 'Keiki.Core.delta'.
--
-- The state carrier is @(s, 'RegFile' rs)@ because edge guards
-- depend on the register file as well as the control vertex.
-- 'aIsFinal' ignores the register file and consults
-- @'isFinal' t@.
--
-- @
-- accepts (inputAcceptor t) cmds  ==  True
-- @
--
-- iff successively applying 'Keiki.Core.delta' to each command
-- reaches a final control vertex. A command sequence is rejected
-- (returns 'False') as soon as any step finds zero or multiple
-- satisfied outgoing edges.
inputAcceptor
  :: BoolAlg phi (RegFile rs, ci)
  => SymTransducer phi rs s ci co
  -> Acceptor ci (s, RegFile rs)
inputAcceptor t = Acceptor
  { aStep    = \(s, regs) ci -> delta t s regs ci
  , aInitial = (initial t, initialRegs t)
  , aIsFinal = \(s, _regs) -> isFinal t s
  }


-- | Project a 'SymTransducer' to its /output/ acceptor (π₂): the
-- acceptor over the event alphabet whose step is
-- 'Keiki.Core.applyEvent'.
--
-- The state carrier is @(s, 'RegFile' rs)@ because 'applyEvent'
-- itself threads the register file through replay.
--
-- @
-- accepts (outputAcceptor t) events  ==  True
-- @
--
-- iff successively applying 'Keiki.Core.applyEvent' to each event
-- reaches a final control vertex — equivalently, iff
-- @'Keiki.Core.reconstitute' t events@ returns 'Just' a final
-- @(s, regs)@. The output acceptor /is/ the @evolve@ acceptor the
-- foundations chapter derives.
outputAcceptor
  :: (BoolAlg phi (RegFile rs, ci), Eq co)
  => SymTransducer phi rs s ci co
  -> Acceptor co (s, RegFile rs)
outputAcceptor t = Acceptor
  { aStep    = \(s, regs) co -> applyEvent t s regs co
  , aInitial = (initial t, initialRegs t)
  , aIsFinal = \(s, _regs) -> isFinal t s
  }


-- | Run an 'Acceptor' over a sequence. Returns 'Just' the terminal
-- state if every step succeeds, 'Nothing' on the first step that
-- rejects.
--
-- @runAcceptor a@ is @'foldlM' ('aStep' a) ('aInitial' a)@ written
-- longhand; the loose form keeps the import surface minimal and the
-- haddock close to the operational semantics.
runAcceptor :: Acceptor a s -> [a] -> Maybe s
runAcceptor a = go (aInitial a)
  where
    go s []       = Just s
    go s (x : xs) = aStep a s x >>= \s' -> go s' xs


-- | Decide membership: 'True' iff the input is accepted (every step
-- succeeds and the terminal state is final).
--
-- @
-- accepts a xs == case runAcceptor a xs of
--   Just s  -> aIsFinal a s
--   Nothing -> False
-- @
accepts :: Acceptor a s -> [a] -> Bool
accepts a xs = case runAcceptor a xs of
  Just s  -> aIsFinal a s
  Nothing -> False
