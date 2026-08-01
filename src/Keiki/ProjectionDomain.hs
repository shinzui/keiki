-- | Backend-neutral exact domains for nominal field projections.
--
-- A 'ProjectionDomain' is interpreted twice by Keiki: concretely through
-- 'memberProjectionDomain', and symbolically by the SBV translator. Text
-- patterns always match the complete 'Text' value. Their constructors reject
-- code points above U+2FFFF, invalid ranges, and invalid repetition bounds so
-- the two interpretations cannot silently diverge.
--
-- A domain used by 'Keiki.Core.exactFieldWitness' is a consumer-owned proof
-- declaration: every concrete owner must project into it, and every admitted
-- key must reconstruct an owner that projects back to the same key. Keiki's
-- law helpers and satisfying-model checks exercise this contract, but only a
-- consumer or generator can test that no real owner key was omitted.
module Keiki.ProjectionDomain
  ( ProjectionDomain,
    TextPattern,
    DomainConstructionError (..),
    maximumSmtCodePoint,
    finiteProjectionDomain,
    wholeProjectionDomain,
    textProjectionDomain,
    textLiteral,
    textCharSet,
    textCharRanges,
    textConcat,
    textAlternation,
    textRepeatBetween,
    memberProjectionDomain,
    matchesTextPattern,
  )
where

import Keiki.Internal.ProjectionDomain
