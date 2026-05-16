-- | A Chassaing-shape Decider façade over a 'SymTransducer'.
--
-- Users coming from the naive functional event-sourcing world
-- (Jérémie Chassaing's /Functional Event Sourcing Decider/) work
-- with a small record:
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
-- 'decide' is built on 'omega' (the forward step that emits one or
-- more events per command after the EP-19 widening); 'evolve' is
-- built on 'applyEvent' (the letter-only inverse step). With the
-- widened @'Keiki.Core.Edge.output' :: ['Keiki.Core.OutTerm' rs ci
-- co]@ a single command can yield two or more events end-to-end
-- without any state-refinement scaffolding — 'decide' returns the
-- full list directly. EP-19 retired the previous EP-20 façades
-- (@toMultiDecider@ + @DriverConfig@); the multi-event behaviour is
-- now first-class in the AST.
--
-- == Streaming replay through multi-event edges
--
-- The 'evolve' field is letter-only (handles edges with output of
-- length 0 or 1) and remains the canonical letter-replay verb.
-- Event-by-event streaming across a length-2+ edge passes through
-- the intermediate "I just observed event 1, expecting event 2 next"
-- state; the 'evolveStreaming' field exposes this via
-- 'Keiki.Core.InFlight' and 'Keiki.Core.applyEventStreaming'. The
-- two evolve fields agree on length-0/1 commands; they diverge
-- only on length-2+ where the streaming path stays /InFlight/
-- between events.
--
-- == One semantic gap remains
--
-- /ε-edges/ — edges whose @output@ is @[]@. The transducer
-- transitions state without emitting an event. 'decide' returns
-- @[]@ for such commands, and the result is identical to "no event
-- happened" from the Decider record's perspective. Use
-- 'Keiki.Core.delta' / 'Keiki.Core.step' directly when ε-driven
-- transitions matter.
module Keiki.Decider
  ( Decider (..)
  , toDecider
  ) where

import Keiki.Core
  ( BoolAlg
  , InFlight (..)
  , RegFile
  , SymTransducer (..)
  , applyEvent
  , applyEventStreaming
  , omega
  )


-- | The Chassaing-shape Decider record. Field selectors are named
-- to match published Decider examples; conflicts with other modules
-- are avoided by importing this module qualified.
--
-- The @s_streaming@ parameter carries the InFlight-aware streaming
-- state ('Keiki.Core.InFlight' s co paired with a register file);
-- for letter-only callers it is unused.
data Decider c e s s_streaming = Decider
  { decide          :: c -> s -> [e]
  , evolve          :: s -> e -> s
  , evolveStreaming :: s_streaming -> e -> Maybe s_streaming
  , initialState    :: s
  , isTerminal      :: s -> Bool
  }


-- | Project a keiki 'SymTransducer' to a 'Decider' record. The
-- letter-replay state carrier is @(s, RegFile rs)@ and the
-- streaming-replay state carrier is @('Keiki.Core.InFlight' s co,
-- RegFile rs)@ — keiki edge guards depend on the register file as
-- well as the control vertex, and streaming replay through a
-- length-2+ edge intrinsically observes a mid-chain wrapper.
--
-- == Field-by-field correspondence
--
-- @
-- decide d cmd (s, regs)        -- = omega t s regs cmd            (EP-19 widened)
-- evolve d (s, regs) ev         -- = letter-only applyEvent;
--                               --   on length-2+ edges, falls back
--                               --   to the input state defensively
-- evolveStreaming d ws ev       -- = applyEventStreaming, returning
--                               --   the wrapped state mid-chain
-- initialState d                -- = (initial t, initialRegs t)
-- isTerminal   d (s, _regs)     -- = isFinal t s
-- @
--
-- == Defensive 'evolve'
--
-- 'applyEvent' returns 'Nothing' when an event cannot be replayed
-- letter-by-letter from @(s, regs)@. To keep the Chassaing signature
-- non-'Maybe', 'evolve' returns the input state on failure. Callers
-- that want strict replay use 'evolveStreaming' (whose 'Maybe' is
-- explicit) or 'Keiki.Core.applyEvents' (which returns 'Nothing' on
-- the first replay failure across a chunk).
toDecider
  :: (BoolAlg phi (RegFile rs, ci), Eq co)
  => SymTransducer phi rs s ci co
  -> Decider ci co (s, RegFile rs) (InFlight s co, RegFile rs)
toDecider t = Decider
  { decide = \cmd (s, regs) -> omega t s regs cmd
  , evolve = \(s, regs) ev -> case applyEvent t s regs ev of
      Just (s', regs') -> (s', regs')
      Nothing          -> (s, regs)
  , evolveStreaming = \(w, regs) ev -> applyEventStreaming t w regs ev
  , initialState    = (initial t, initialRegs t)
  , isTerminal      = \(s, _regs) -> isFinal t s
  }
