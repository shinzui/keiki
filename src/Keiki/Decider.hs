-- | A Chassaing-shape Decider façade over a 'SymTransducer'.
--
-- Users coming from the naive functional event-sourcing world
-- (Jérémie Chassaing's /Functional Event Sourcing Decider/) work
-- with a small four-field record:
--
-- @
-- data Decider c e s = Decider
--   { decide       :: c -> s -> [e]
--   , evolve       :: s -> e -> s
--   , initialState :: s
--   , isTerminal   :: s -> Bool
--   }
-- @
--
-- 'toDecider' projects the keiki 'SymTransducer' onto this shape.
-- 'decide' is built on 'omega' (the forward step that emits an
-- event); 'evolve' is built on 'applyEvent' (the inverse step that
-- replays an event onto the state). The keiki formalism guarantees
-- the two directions agree on every non-ε edge.
--
-- == Two semantic gaps
--
-- The keiki transducer is /more expressive/ than the naive Decider
-- in two specific ways. Both manifest as visible differences in
-- behaviour through this façade and are documented at 'toDecider'.
--
-- 1. /ε-edges/ — edges whose @output@ is 'Nothing'. The transducer
--    transitions state without emitting an event. Through the
--    façade, 'decide' returns @[]@ for the input that would have
--    fired the ε-edge, and a subsequent 'evolve' on @[]@ is a
--    no-op, so the state does not transition. Use 'delta' directly
--    when ε-driven transitions matter.
--
-- 2. /At most one event per command/. The naive 'decide' returns
--    @[e]@ to support multi-event commands; the keiki 'omega'
--    returns @Maybe co@. The façade lifts via @Just co → [co]@,
--    @Nothing → []@, so the result is always empty or a singleton.
--    A future @MultiDecider@ would relax this; out of scope here.
module Keiki.Decider
  ( Decider (..)
  , toDecider
    -- * Multi-event façade (EP-20)
  , DriverConfig (..)
  , toMultiDecider
  ) where

import Keiki.Core
  ( BoolAlg
  , RegFile
  , SymTransducer (..)
  , applyEvent
  , omega
  , step
  )


-- | The Chassaing-shape Decider record. Field selectors are named
-- to match published Decider examples; conflicts with other modules
-- are avoided by importing this module qualified.
data Decider c e s = Decider
  { decide       :: c -> s -> [e]
  , evolve       :: s -> e -> s
  , initialState :: s
  , isTerminal   :: s -> Bool
  }


-- | Project a keiki 'SymTransducer' to a 'Decider' record. The
-- state carrier is the pair @(s, RegFile rs)@ because keiki edge
-- guards depend on the register file as well as the control vertex.
--
-- == Field-by-field correspondence
--
-- @
-- decide d cmd (s, regs)        -- = Just  co  → [co]
--                               --   Nothing   → []           via 'omega'
-- evolve d (s, regs) ev         -- = Just (s', regs')         via 'applyEvent'
--                               --   Nothing → (s, regs)      defensive no-op
-- initialState d                -- = (initial t, initialRegs t)
-- isTerminal   d (s, _regs)     -- = isFinal t s
-- @
--
-- == Worked illustration of the two semantic gaps
--
-- /ε-edge./ Take the User Registration aggregate's
-- @FulfillGDPRRequest@ edge from @RequiresConfirmation@: it has
-- @output = Nothing@ (silent deletion before the user ever
-- confirmed). Through the façade:
--
-- @
-- let d = toDecider userReg
--     s0 = (RequiresConfirmation, regsAtRC)
--     evs = decide d (FulfillGDPRRequest …) s0   -- evs == []
--     s1  = foldl (evolve d) s0 evs              -- s1 == s0
-- @
--
-- The naive Decider model would treat this as "no state change."
-- The keiki 'delta' would, however, transition to @Deleted@. If you
-- need ε-edges to drive state, call 'Keiki.Core.delta' directly.
--
-- /Singleton lift./ Because 'omega' is single-event by construction,
-- @decide d cmd s@ is always @[]@ or a singleton. Folding @evolve@
-- over the result is a no-op or a single replay step.
--
-- == Defensive evolve
--
-- 'applyEvent' returns 'Nothing' when an event cannot be replayed
-- from the current @(s, regs)@ — typically a malformed log. To keep
-- the Chassaing signature non-Maybe, 'evolve' returns the input
-- state in that case. Callers that want strict replay can detect
-- malformed logs by re-running 'applyEvent' themselves.
toDecider
  :: BoolAlg phi (RegFile rs, ci)
  => SymTransducer phi rs s ci co
  -> Decider ci co (s, RegFile rs)
toDecider t = Decider
  { decide = \cmd (s, regs) -> case omega t s regs cmd of
      Just co -> [co]
      Nothing -> []
  , evolve = \(s, regs) ev -> case applyEvent t s regs ev of
      Just (s', regs') -> (s', regs')
      Nothing          -> (s, regs)
  , initialState = (initial t, initialRegs t)
  , isTerminal   = \(s, _regs) -> isFinal t s
  }


-- * Multi-event façade ----------------------------------------------------

-- | Identifies internal control vertices and the command that
-- advances them. Used by 'toMultiDecider' to drive multi-event
-- letter chains end-to-end transparently.
--
-- @'isInternal' v@ returns @'Just' c@ when @v@ is an internal
-- vertex and @c@ is the command to use to advance it; 'Nothing'
-- when @v@ is a public vertex that 'decide' should treat as the
-- terminal state of one driver step.
--
-- The configuration sits outside the 'SymTransducer' on purpose:
-- it is meta about the user's state space (which vertices are
-- public, which are internal, what command advances them), not
-- part of the formalism. Multiple driver configurations can exist
-- for the same transducer.
newtype DriverConfig s ci = DriverConfig
  { isInternal :: s -> Maybe ci
  }


-- | Project a 'SymTransducer' to a 'Decider' that drives multi-event
-- letter chains end-to-end. Compared to 'toDecider', the produced
-- 'decide' may return event lists of length two or more by chaining
-- automatically through the user-declared internal vertices named in
-- the supplied 'DriverConfig'.
--
-- The 'evolve' field is a single-letter step identical to
-- 'toDecider'@'@s — event-by-event replay genuinely passes through
-- the user's intermediate vertices, which are real states the user
-- declared. Hiding them via auto-driving 'evolve' would make the
-- value-level state of the system invisible mid-replay. For
-- chunk-replay across a logical command's events use
-- 'Keiki.Core.applyEvents'.
--
-- == Driver loop
--
-- @
-- decide t cfg cmd (s, regs)
--   = run cmd from (s, regs);
--     if landed in an internal vertex,
--       look up the advancement command in cfg and recurse;
--     otherwise return the accumulated event list.
-- @
--
-- The loop terminates on a public vertex or when 'step' returns
-- 'Nothing' (no edge fires). Events on ε-edges (output 'Nothing')
-- are skipped — the chain advances state silently.
toMultiDecider
  :: BoolAlg phi (RegFile rs, ci)
  => SymTransducer phi rs s ci co
  -> DriverConfig s ci
  -> Decider ci co (s, RegFile rs)
toMultiDecider t cfg = Decider
  { decide       = \cmd (s, regs) -> driveDecide t cfg cmd (s, regs)
  , evolve       = \(s, regs) ev -> case applyEvent t s regs ev of
      Just (s', regs') -> (s', regs')
      Nothing          -> (s, regs)
  , initialState = (initial t, initialRegs t)
  , isTerminal   = \(s, _regs) -> isFinal t s
  }


-- | The driver loop. Folds 'step' across the chain induced by
-- 'isInternal'; accumulates emitted events in declaration order.
driveDecide
  :: BoolAlg phi (RegFile rs, ci)
  => SymTransducer phi rs s ci co
  -> DriverConfig s ci
  -> ci
  -> (s, RegFile rs)
  -> [co]
driveDecide t cfg ci0 (s0, regs0) = go ci0 (s0, regs0) []
  where
    go ci (s, regs) acc = case step t (s, regs) ci of
      Nothing -> reverse acc
      Just (s', regs', mco) ->
        let acc' = case mco of
              Just co -> co : acc
              Nothing -> acc
        in case isInternal cfg s' of
             Just ciNext -> go ciNext (s', regs') acc'
             Nothing     -> reverse acc'
