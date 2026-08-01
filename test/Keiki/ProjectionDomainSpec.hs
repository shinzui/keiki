{-# LANGUAGE TypeFamilies #-}

module Keiki.ProjectionDomainSpec where

import Control.Monad (forM_, replicateM)
import Data.Int (Int32, Int64)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime)
import Data.Word (Word16, Word32, Word64, Word8)
import Keiki.Core
import Keiki.ProjectionDomain
import Keiki.Symbolic (symIsBot, symbolicWholeCarrierExact)
import Numeric.Natural (Natural)
import Test.Hspec

expectRight :: (HasCallStack, Show e) => Either e a -> IO a
expectRight (Right value) = pure value
expectRight (Left err) = do
  expectationFailure (show err)
  fail "expected Right"

smallPattern :: TextPattern
smallPattern = either (error . show) id $ do
  chars <- textCharSet ('a' :| ['b'])
  textRepeatBetween 1 2 chars

data SmallTextProjection

instance FieldProjection SmallTextProjection where
  type FieldName SmallTextProjection = "key"
  type FieldOwner SmallTextProjection = Text
  type FieldResult SmallTextProjection = Text
  fieldShapeId _ = "test.small-text.v1"
  projectFieldValue _ = id

instance ExactFieldProjection SmallTextProjection where
  fieldProjectionDomain _ = textProjectionDomain smallPattern
  reconstructFieldOwner _ key
    | matchesTextPattern smallPattern key = Just key
    | otherwise = Nothing

smallTextWitness :: FieldWitness SmallTextProjection
smallTextWitness = exactFieldWitness @SmallTextProjection

type SmallTextRegs = '[ '("owner", Text)]

smallTextOwner :: Index SmallTextRegs Text
smallTextOwner = #owner

spec :: Spec
spec = describe "projection domain" $ do
  it "deduplicates finite values while preserving membership" $ do
    let domain =
          finiteProjectionDomain ("open" :| ["closed", "open"]) ::
            ProjectionDomain Text
    memberProjectionDomain domain "open" `shouldBe` True
    memberProjectionDomain domain "closed" `shouldBe` True
    memberProjectionDomain domain "invented" `shouldBe` False

  it "matches literals as complete strings" $ do
    textPattern <- expectRight (textLiteral "type_")
    matchesTextPattern textPattern "type_" `shouldBe` True
    matchesTextPattern textPattern "type_value" `shouldBe` False

  it "composes sets, ranges, alternation, and bounded repetition" $ do
    prefix <- expectRight (textLiteral "id_")
    lower <- expectRight (textCharRanges (('a', 'z') :| []))
    digits <- expectRight (textCharSet ('0' :| ['1']))
    suffix <- expectRight (textRepeatBetween 2 3 digits)
    let textPattern = textConcat (prefix :| [textAlternation (lower :| [digits]), suffix])
    matchesTextPattern textPattern "id_a01" `shouldBe` True
    matchesTextPattern textPattern "id_1011" `shouldBe` True
    matchesTextPattern textPattern "id_a0" `shouldBe` False
    matchesTextPattern textPattern "id_A01" `shouldBe` False
    matchesTextPattern textPattern "xid_a01" `shouldBe` False

  it "gives the pure matcher and SBV compiler the same small language" $ do
    let samples = T.pack <$> concatMap (`replicateM` "abx") [0 .. 3]
    forM_ samples $ \sample -> do
      let concrete = matchesTextPattern smallPattern sample
          predicate =
            regProj smallTextWitness smallTextOwner .== TLit sample ::
              HsPred SmallTextRegs ()
      symIsBot predicate `shouldBe` not concrete

  it "checks both directions of an exact witness declaration" $ do
    checkFieldProjectionOwner smallTextWitness "ab" `shouldBe` Right ()
    checkFieldProjectionKey smallTextWitness "ba" `shouldBe` Right "ba"
    checkFieldProjectionOwner smallTextWitness "x"
      `shouldBe` Left ProjectedKeyOutsideDeclaredDomain

  it "classifies every curated whole carrier conservatively" $ do
    symbolicWholeCarrierExact @Bool `shouldBe` True
    symbolicWholeCarrierExact @Int `shouldBe` False
    symbolicWholeCarrierExact @Integer `shouldBe` True
    symbolicWholeCarrierExact @Natural `shouldBe` True
    symbolicWholeCarrierExact @Text `shouldBe` False
    symbolicWholeCarrierExact @UTCTime `shouldBe` False
    symbolicWholeCarrierExact @Word64 `shouldBe` True
    symbolicWholeCarrierExact @Word32 `shouldBe` True
    symbolicWholeCarrierExact @Word16 `shouldBe` True
    symbolicWholeCarrierExact @Word8 `shouldBe` True
    symbolicWholeCarrierExact @Int64 `shouldBe` True
    symbolicWholeCarrierExact @Int32 `shouldBe` True

  it "rejects reversed ranges and repetition intervals" $ do
    textCharRanges (('z', 'a') :| [])
      `shouldBe` Left (ReversedCharacterRange 'z' 'a')
    literal <- expectRight (textLiteral "x")
    textRepeatBetween 2 1 literal
      `shouldBe` Left (InvalidRepetitionInterval 2 1)

  it "accepts U+2FFFF and rejects U+30000 in every character constructor" $ do
    textLiteral (T.singleton maximumSmtCodePoint) `shouldSatisfy` isRight
    textCharSet (maximumSmtCodePoint :| []) `shouldSatisfy` isRight
    textCharRanges ((maximumSmtCodePoint, maximumSmtCodePoint) :| [])
      `shouldSatisfy` isRight
    let firstUnrepresentable = '\x30000'
    textLiteral (T.singleton firstUnrepresentable)
      `shouldBe` Left (CodePointAboveSmtMaximum firstUnrepresentable)
    textCharSet (firstUnrepresentable :| [])
      `shouldBe` Left (CodePointAboveSmtMaximum firstUnrepresentable)
    textCharRanges ((firstUnrepresentable, firstUnrepresentable) :| [])
      `shouldBe` Left (CodePointAboveSmtMaximum firstUnrepresentable)
  where
    isRight (Right _) = True
    isRight (Left _) = False
