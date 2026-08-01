{-# LANGUAGE TypeFamilies #-}

module Keiki.ProjectionDomainSpec where

import Control.Monad (forM_, replicateM)
import Data.Int (Int32, Int64)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Data.Word (Word16, Word32, Word64, Word8)
import Keiki.Core
import Keiki.ProjectionDomain
import Keiki.Symbolic
  ( PredicateVerificationDetail (..),
    Sym (..),
    TranslationIssue (..),
    TranslationStrength (..),
    predicateTranslationReport,
    projectionModelKeyAs,
    projectionModelOwnerAs,
    symIsBot,
    symbolicWholeCarrierExact,
    verifyPredicateDetailed,
  )
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

-- A schema-local TypeID-v7-shaped key. This fixture intentionally derives its
-- accepted language without depending on the consumer's TypeID package:
-- "order_", followed by a 26-character Crockford Base32 UUID encoding whose
-- leading character cannot overflow 128 bits, whose character 10 encodes UUID
-- version 7, and whose character 13 encodes the RFC 4122 variant.
newtype OrderTypeIdOwner = OrderTypeIdOwner Text
  deriving stock (Eq, Show)

data OrderTypeIdText

orderTypeIdPattern :: TextPattern
orderTypeIdPattern = either (error . show) id $ do
  prefix <- textLiteral "order_"
  leading <- textCharSet ('0' :| "1234567")
  crockford <- textCharSet ('0' :| "123456789abcdefghjkmnpqrstvwxyz")
  version <- textCharSet ('e' :| "f")
  variant <- textCharSet ('8' :| "9abrstv")
  beforeVersion <- textRepeatBetween 9 9 crockford
  beforeVariant <- textRepeatBetween 2 2 crockford
  afterVariant <- textRepeatBetween 12 12 crockford
  pure
    ( textConcat
        ( prefix
            :| [ leading,
                 beforeVersion,
                 version,
                 beforeVariant,
                 variant,
                 afterVariant
               ]
        )
    )

instance FieldProjection OrderTypeIdText where
  type FieldName OrderTypeIdText = "typeId"
  type FieldOwner OrderTypeIdText = OrderTypeIdOwner
  type FieldResult OrderTypeIdText = Text
  fieldShapeId _ = "test.order-type-id.v7"
  projectFieldValue _ (OrderTypeIdOwner value) = value

instance ExactFieldProjection OrderTypeIdText where
  fieldProjectionDomain _ = textProjectionDomain orderTypeIdPattern
  reconstructFieldOwner _ value
    | matchesTextPattern orderTypeIdPattern value = Just (OrderTypeIdOwner value)
    | otherwise = Nothing

orderTypeIdWitness :: FieldWitness OrderTypeIdText
orderTypeIdWitness = exactFieldWitness @OrderTypeIdText

type OrderTypeIdRegs = '[ '("owner", OrderTypeIdOwner)]

orderTypeIdOwner :: Index OrderTypeIdRegs OrderTypeIdOwner
orderTypeIdOwner = #owner

orderTypeIdSuffix :: Text
orderTypeIdSuffix = "01h455vb4pex5vsknk084sn02q"

orderTypeIdSample :: Text
orderTypeIdSample = "order_" <> orderTypeIdSuffix

replaceTextAt :: Int -> Char -> Text -> Text
replaceTextAt position replacement value =
  T.take position value <> T.singleton replacement <> T.drop (position + 1) value

replaceSuffixAt :: Int -> Char -> Text
replaceSuffixAt position replacement =
  replaceTextAt (T.length "order_" + position) replacement orderTypeIdSample

leapSecondValue :: UTCTime
leapSecondValue = UTCTime (fromGregorian 2016 12 31) (secondsToDiffTime 86400)

data FiniteLeapSecond

instance FieldProjection FiniteLeapSecond where
  type FieldName FiniteLeapSecond = "leap"
  type FieldOwner FiniteLeapSecond = UTCTime
  type FieldResult FiniteLeapSecond = UTCTime
  fieldShapeId _ = "test.finite-leap-second.v1"
  projectFieldValue _ = id

instance ExactFieldProjection FiniteLeapSecond where
  fieldProjectionDomain _ = finiteProjectionDomain (leapSecondValue :| [])
  reconstructFieldOwner _ value
    | value == leapSecondValue = Just value
    | otherwise = Nothing

finiteLeapSecondWitness :: FieldWitness FiniteLeapSecond
finiteLeapSecondWitness = exactFieldWitness @FiniteLeapSecond

data FiniteHighText

instance FieldProjection FiniteHighText where
  type FieldName FiniteHighText = "highText"
  type FieldOwner FiniteHighText = Text
  type FieldResult FiniteHighText = Text
  fieldShapeId _ = "test.finite-high-text.v1"
  projectFieldValue _ = id

instance ExactFieldProjection FiniteHighText where
  fieldProjectionDomain _ =
    finiteProjectionDomain (T.singleton '\x30000' :| [])
  reconstructFieldOwner _ value
    | value == T.singleton '\x30000' = Just value
    | otherwise = Nothing

finiteHighTextWitness :: FieldWitness FiniteHighText
finiteHighTextWitness = exactFieldWitness @FiniteHighText

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

  it "keeps leap-second UTCTime values out of the whole-carrier claim" $ do
    fromSym (toSym leapSecondValue) `shouldNotBe` leapSecondValue

  it "rejects non-representable literals from otherwise finite domains" $ do
    let leapOwner = ZIdx :: Index '[ '("owner", UTCTime)] UTCTime
        leapPredicate =
          regProj finiteLeapSecondWitness leapOwner
            .== TLit (fromSym (toSym leapSecondValue)) ::
            HsPred '[ '("owner", UTCTime)] ()
        textOwner = ZIdx :: Index '[ '("owner", Text)] Text
        textPredicate =
          regProj finiteHighTextWitness textOwner .== TLit "ordinary" ::
            HsPred '[ '("owner", Text)] ()
    predicateTranslationReport leapPredicate `shouldSatisfy` hasUnsupportedDomain
    predicateTranslationReport textPredicate `shouldSatisfy` hasUnsupportedDomain
    symIsBot leapPredicate `shouldBe` False
    symIsBot textPredicate `shouldBe` False

  it "rejects reversed ranges and repetition intervals" $ do
    textCharRanges (('z', 'a') :| [])
      `shouldBe` Left (ReversedCharacterRange 'z' 'a')
    literal <- expectRight (textLiteral "x")
    textRepeatBetween 2 1 literal
      `shouldBe` Left (InvalidRepetitionInterval 2 1)
    let tooLarge = fromIntegral (maxBound :: Int) + 1
    textRepeatBetween tooLarge tooLarge literal
      `shouldBe` Left (RepetitionBoundTooLarge tooLarge)
    textRepeatBetween 0 tooLarge literal
      `shouldBe` Left (RepetitionBoundTooLarge tooLarge)

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

  describe "TypeID-v7-shaped exact text domain" $ do
    let accepted =
          orderTypeIdSample
            : replaceSuffixAt 0 '7'
            : replaceSuffixAt 10 'f'
            : [replaceSuffixAt 13 variant | variant <- "89abrstv"]
        rejected =
          [ "",
            orderTypeIdSuffix,
            "user_" <> orderTypeIdSuffix,
            "order__" <> orderTypeIdSuffix,
            T.dropEnd 1 orderTypeIdSample,
            orderTypeIdSample <> "0",
            replaceSuffixAt 0 '8',
            replaceSuffixAt 1 'i',
            replaceSuffixAt 1 'l',
            replaceSuffixAt 1 'o',
            replaceSuffixAt 1 'u',
            replaceSuffixAt 1 'H',
            replaceSuffixAt 1 '_',
            replaceSuffixAt 10 'd',
            replaceSuffixAt 10 'g',
            replaceSuffixAt 13 'c'
          ]
        predicate sample =
          regProj orderTypeIdWitness orderTypeIdOwner .== TLit sample ::
            HsPred OrderTypeIdRegs ()

    it "accepts every version/variant boundary and rejects malformed boundaries" $ do
      forM_ accepted $ \sample -> do
        matchesTextPattern orderTypeIdPattern sample `shouldBe` True
        symIsBot (predicate sample) `shouldBe` False
      forM_ rejected $ \sample -> do
        matchesTextPattern orderTypeIdPattern sample `shouldBe` False
        symIsBot (predicate sample) `shouldBe` True

    it "reconstructs and round-trips every accepted boundary model" $
      forM_ accepted $ \sample -> do
        checkFieldProjectionKey orderTypeIdWitness sample
          `shouldBe` Right (OrderTypeIdOwner sample)
        detail <- verifyPredicateDetailed (predicate sample)
        case detail of
          PredicateSatisfiable ExactTranslation [projectionModel] -> do
            projectionModelKeyAs @Text projectionModel `shouldBe` Just sample
            projectionModelOwnerAs @OrderTypeIdOwner projectionModel
              `shouldBe` Just (OrderTypeIdOwner sample)
          other -> expectationFailure ("expected one exact TypeID model, got " <> show other)
  where
    isRight (Right _) = True
    isRight (Left _) = False
    hasUnsupportedDomain (ConservativeOverApproximation issues) =
      any isUnsupportedDomain issues
    hasUnsupportedDomain ExactTranslation = False
    isUnsupportedDomain UnsupportedProjectionDomain {} = True
    isUnsupportedDomain _ = False
