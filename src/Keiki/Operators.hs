{- | Re-exports of keiki's predicate and term operators, intended to be
imported __qualified__ so they cannot clash with the operators that
the @lens@ / @generic-lens@ libraries (or a service prelude that
re-exports them) bring into scope unqualified.

The sharpest clash is @(.>)@: in @lens@ it is optic composition, in
keiki it is the greater-than comparison that builds an 'HsPred'. With

@
import qualified Keiki.Operators as K
@

you write @x K..\> y@ for the keiki comparison and leave the bare
@(.>)@ to @lens@ — no @hiding@ clause required.

This module adds nothing new: every export here is defined in and
re-exported from "Keiki.Core". See @docs\/guide\/generic-lens-and-label-reads.md@
for the full import recipe and the @B.requireGt@-vs-@(.>)@ guidance.
-}
module Keiki.Operators (
    -- * Comparison (build an 'Keiki.Core.HsPred')
    (.<),
    (.<=),
    (.>),
    (.>=),
    (.==),
    (./=),

    -- * Logical
    (.&&),
    (.||),
    pnot,

    -- * Structural arithmetic on 'Keiki.Core.Term's
    (.+),
    (.-),
    (.*),

    -- * Function-style arithmetic aliases (clash-free already)
    tadd,
    tsub,
    tmul,
) where

import Keiki.Core (
    pnot,
    tadd,
    tmul,
    tsub,
    (.&&),
    (.*),
    (.+),
    (.-),
    (./=),
    (.<),
    (.<=),
    (.==),
    (.>),
    (.>=),
    (.||),
 )

-- Note: no fixity declarations are restated here. On GHC 9.12 / GHC2024 a
-- fixity signature requires an accompanying binding in the same module
-- (GHC-44432: "lacks an accompanying binding"), and these names are merely
-- re-exported, not bound here. That is harmless: a re-exported operator
-- carries the fixity from its defining module, so a qualified user of
-- @Keiki.Operators@ (e.g. @x K..> y@) gets the @infix 4@ from "Keiki.Core"
-- automatically.
