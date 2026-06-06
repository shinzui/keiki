{-# LANGUAGE TypeAbstractions #-}

{- | Pure, domain-readable pretty-printer for keiki's predicate, term,
and update syntax trees ('HsPred', 'Term', 'Update'). Produces
'Data.Text.Text'. No solver, no IO. Shared by the Mermaid topology
renderer ('Keiki.Render.Mermaid') and the sibling edge-inspector /
multiline-label renderers.

Two things are provably unprintable and are marked, not dropped:
applied opaque Haskell functions render as @<fn>(...)@; literal
values render as @<lit>@ (a 'TLit' carries an unconstrained type
with no 'Show').
-}
module Keiki.Render.Pretty (
    indexName,
    prettyTerm,
    prettyPred,
    prettyUpdate,
) where

import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Data.Text qualified as T
import GHC.TypeLits (symbolVal)

import Keiki.Core (
    Cmp (..),
    HsPred (..),
    InCtor (..),
    Index (..),
    NumOp (..),
    Term (..),
    Update (..),
 )
import Keiki.Internal.Slots (indexNName)

{- | Recover the slot name an 'Index' points at, by walking 'SIdx' down
to the 'ZIdx' and reading its 'KnownSymbol'. No extra class
constraint is needed: 'ZIdx' carries the slot's symbol. The @ZIdx \@s@
type-application pattern binds the existential symbol directly.
-}
indexName :: Index rs r -> String
indexName (ZIdx @s) = symbolVal (Proxy @s)
indexName (SIdx i) = indexName i

{- | Render a 'Term' as domain-readable 'Text'. Register reads render by
slot name, input-field reads as @ctor.field@, arithmetic structurally
with @+ - *@. Opaque applied functions render @<fn>(...)@; literal
values render @<lit>@ (a 'TLit' carries an unconstrained type with no
'Show').
-}
prettyTerm :: Term rs ci ifs r -> Text
prettyTerm (TLit _) = T.pack "<lit>"
prettyTerm (TReg ix) = T.pack (indexName ix)
prettyTerm (TInpCtorField ic ix) =
    T.pack (icName ic) <> T.pack "." <> T.pack (indexName ix)
prettyTerm (TApp1 _ a) = T.pack "<fn>(" <> prettyTerm a <> T.pack ")"
prettyTerm (TApp2 _ a b) =
    T.pack "<fn>(" <> prettyTerm a <> T.pack ", " <> prettyTerm b <> T.pack ")"
prettyTerm (TArith op a b) =
    T.pack "("
        <> prettyTerm a
        <> T.pack " "
        <> numOpSym op
        <> T.pack " "
        <> prettyTerm b
        <> T.pack ")"
  where
    numOpSym OpAdd = T.pack "+"
    numOpSym OpSub = T.pack "-"
    numOpSym OpMul = T.pack "*"

{- | Render an 'HsPred' guard as domain-readable 'Text'. Boolean
structure renders with @&& || !@ and parentheses; @PInCtor@ renders
the constructor name; @PEq@/@PCmp@ render their operand 'Term's around
@== < <= > >=@.
-}
prettyPred :: HsPred rs ci -> Text
prettyPred PTop = T.pack "true"
prettyPred PBot = T.pack "false"
prettyPred (PAnd a b) =
    T.pack "(" <> prettyPred a <> T.pack " && " <> prettyPred b <> T.pack ")"
prettyPred (POr a b) =
    T.pack "(" <> prettyPred a <> T.pack " || " <> prettyPred b <> T.pack ")"
prettyPred (PNot p) = T.pack "!(" <> prettyPred p <> T.pack ")"
prettyPred (PEq l r) = prettyTerm l <> T.pack " == " <> prettyTerm r
prettyPred (PInCtor ic) = T.pack (icName ic)
prettyPred (PCmp c l r) =
    prettyTerm l <> T.pack " " <> cmpSym c <> T.pack " " <> prettyTerm r
  where
    cmpSym CmpLt = T.pack "<"
    cmpSym CmpLe = T.pack "<="
    cmpSym CmpGt = T.pack ">"
    cmpSym CmpGe = T.pack ">="

{- | Render an 'Update' as domain-readable 'Text'. @UKeep@ renders
@(keep)@; @USet@ renders @slot := term@ (the slot name comes from the
name-tagged 'IndexN' via 'indexNName'); @UCombine@ joins comma-separated.
-}
prettyUpdate :: Update rs w ci -> Text
prettyUpdate UKeep = T.pack "(keep)"
prettyUpdate (USet ix t) = T.pack (indexNName ix) <> T.pack " := " <> prettyTerm t
prettyUpdate (UCombine a b) = prettyUpdate a <> T.pack ", " <> prettyUpdate b
