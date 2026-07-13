module Keiki.LawHelpers
  ( runScript,
    emittedLog,
  )
where

import Keiki.Core

-- | Drive a command script from the initial state. Rejected commands leave
-- state unchanged and contribute an empty output batch.
runScript ::
  SymTransducer (HsPred rs ci) rs s ci co ->
  [ci] ->
  [[co]]
runScript transducer = go (initial transducer, initialRegs transducer)
  where
    go _ [] = []
    go state (command : rest) = case step transducer state command of
      Nothing -> [] : go state rest
      Just (vertex, registers, outputs) ->
        outputs : go (vertex, registers) rest

emittedLog ::
  SymTransducer (HsPred rs ci) rs s ci co ->
  [ci] ->
  [co]
emittedLog transducer = concat . runScript transducer
