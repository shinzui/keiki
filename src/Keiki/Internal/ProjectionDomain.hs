{-# LANGUAGE GADTs #-}

-- | Internal representation shared by the backend-neutral public API and the
-- SBV compiler. The constructors stay hidden from package consumers so every
-- textual pattern is validated before it can be used as exact evidence.
module Keiki.Internal.ProjectionDomain
  ( ProjectionDomain (..),
    TextPattern (..),
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

import Data.Foldable (traverse_)
import Data.List (stripPrefix)
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NE
import Data.Text (Text)
import Data.Text qualified as T
import Numeric.Natural (Natural)

-- | The exact image of a field projection. The text constructor is indexed so
-- a text pattern cannot accidentally be attached to another result carrier.
data ProjectionDomain a where
  ProjectionWhole :: ProjectionDomain a
  ProjectionFinite :: (Eq a) => NonEmpty a -> ProjectionDomain a
  ProjectionText :: TextPattern -> ProjectionDomain Text

-- | A deliberately small full-string pattern language. Every constructor has
-- both a pure interpreter and an exact SBV regular-expression translation.
data TextPattern
  = TextLiteral Text
  | TextRanges (NonEmpty (Char, Char))
  | TextConcat (NonEmpty TextPattern)
  | TextAlternation (NonEmpty TextPattern)
  | TextRepeatBetween Natural Natural TextPattern
  deriving stock (Eq, Show)

-- | Why a textual exact-domain declaration could not be constructed.
data DomainConstructionError
  = CodePointAboveSmtMaximum Char
  | ReversedCharacterRange Char Char
  | InvalidRepetitionInterval Natural Natural
  | RepetitionBoundTooLarge Natural
  deriving stock (Eq, Show)

-- | SMT-LIB strings contain code points U+0000 through U+2FFFF.
maximumSmtCodePoint :: Char
maximumSmtCodePoint = '\x2FFFF'

-- | Construct a non-empty finite domain, removing duplicates while retaining
-- the first occurrence of every value. The symbolic compiler separately
-- verifies that each retained literal round-trips through its representation
-- and satisfies backend bounds; failure omits the entire constraint and makes
-- the containing translation conservative.
finiteProjectionDomain :: (Eq a) => NonEmpty a -> ProjectionDomain a
finiteProjectionDomain = ProjectionFinite . stableNub
  where
    stableNub (x :| xs) = x :| go [x] xs
    go _ [] = []
    go seen (x : xs)
      | x `elem` seen = go seen xs
      | otherwise = x : go (x : seen) xs

-- | Declare that every value of the result carrier belongs to the image.
-- Exact witnesses may use this only when Keiki classifies the symbolic
-- representation as a whole-carrier isomorphism.
wholeProjectionDomain :: ProjectionDomain a
wholeProjectionDomain = ProjectionWhole

-- | Lift a validated full-string pattern into a 'Text' projection domain.
textProjectionDomain :: TextPattern -> ProjectionDomain Text
textProjectionDomain = ProjectionText

-- | Match one literal text value. Code points outside SMT-LIB's string domain
-- are rejected instead of making the pure and symbolic meanings disagree.
textLiteral :: Text -> Either DomainConstructionError TextPattern
textLiteral value = TextLiteral value <$ validateCharacters (T.unpack value)

-- | Match exactly one member of a non-empty character set.
textCharSet :: NonEmpty Char -> Either DomainConstructionError TextPattern
textCharSet chars = do
  validateCharacters (NE.toList chars)
  pure (TextRanges ((\c -> (c, c)) <$> stableNub chars))
  where
    stableNub (x :| xs) = x :| go [x] xs
    go _ [] = []
    go seen (x : xs)
      | x `elem` seen = go seen xs
      | otherwise = x : go (x : seen) xs

-- | Match exactly one character from one of the supplied inclusive ranges.
textCharRanges ::
  NonEmpty (Char, Char) ->
  Either DomainConstructionError TextPattern
textCharRanges ranges = do
  traverse_ validateRange ranges
  pure (TextRanges ranges)
  where
    validateRange (lower, upper)
      | lower > upper = Left (ReversedCharacterRange lower upper)
      | otherwise = validateCharacters [lower, upper]

-- | Concatenate a non-empty sequence of full-string patterns.
textConcat :: NonEmpty TextPattern -> TextPattern
textConcat = TextConcat

-- | Match any one of a non-empty sequence of full-string patterns.
textAlternation :: NonEmpty TextPattern -> TextPattern
textAlternation = TextAlternation

-- | Match a pattern between the inclusive lower and upper bounds. SBV's
-- regular-expression node stores machine 'Int' bounds, so larger naturals are
-- rejected at construction rather than truncated.
textRepeatBetween ::
  Natural ->
  Natural ->
  TextPattern ->
  Either DomainConstructionError TextPattern
textRepeatBetween lower upper textPattern
  | lower > upper = Left (InvalidRepetitionInterval lower upper)
  | lower > maxInt = Left (RepetitionBoundTooLarge lower)
  | upper > maxInt = Left (RepetitionBoundTooLarge upper)
  | otherwise = Right (TextRepeatBetween lower upper textPattern)
  where
    maxInt = fromIntegral (maxBound :: Int)

-- | Decide concrete membership in the exact domain.
memberProjectionDomain :: (Eq a) => ProjectionDomain a -> a -> Bool
memberProjectionDomain ProjectionWhole _ = True
memberProjectionDomain (ProjectionFinite values) value = value `elem` values
memberProjectionDomain (ProjectionText textPattern) value =
  matchesTextPattern textPattern value

-- | Interpret a 'TextPattern' as a complete-string matcher.
matchesTextPattern :: TextPattern -> Text -> Bool
matchesTextPattern textPattern value = any null (match textPattern (T.unpack value))
  where
    match :: TextPattern -> String -> [String]
    match (TextLiteral literal) input =
      maybe [] pure (T.unpack literal `stripPrefix` input)
    match (TextRanges ranges) input = case input of
      [] -> []
      c : rest
        | any (\(lower, upper) -> lower <= c && c <= upper) ranges -> [rest]
        | otherwise -> []
    match (TextConcat patterns) input =
      foldl (\remainders next -> remainders >>= match next) [input] patterns
    match (TextAlternation patterns) input =
      concatMap (`match` input) patterns
    match (TextRepeatBetween lower upper repeated) input =
      concatMap (\count -> applyCount count input) [lower .. upper]
      where
        applyCount 0 current = [current]
        applyCount count current =
          match repeated current >>= applyCount (count - 1)

validateCharacters :: [Char] -> Either DomainConstructionError ()
validateCharacters = traverse_ validateCharacter
  where
    validateCharacter c
      | c <= maximumSmtCodePoint = Right ()
      | otherwise = Left (CodePointAboveSmtMaximum c)
