-- | Backend-neutral exact domains for nominal field projections.
--
-- A 'ProjectionDomain' is interpreted twice by Keiki: concretely through
-- 'memberProjectionDomain', and symbolically by the SBV translator. Text
-- patterns always match the complete 'Text' value. Their constructors reject
-- code points above U+2FFFF, invalid ranges, and invalid repetition bounds so
-- the two interpretations cannot silently diverge.
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
