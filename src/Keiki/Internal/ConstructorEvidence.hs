-- | Package-private capability for constructing schema-bearing input and wire
-- constructors. The module is listed under @other-modules@, so downstream
-- packages cannot obtain the constructor needed by Keiki's trusted producers.
module Keiki.Internal.ConstructorEvidence
  ( ConstructorEvidence (..),
    constructorEvidence,
  )
where

data ConstructorEvidence = ConstructorEvidence

constructorEvidence :: ConstructorEvidence
constructorEvidence = ConstructorEvidence
