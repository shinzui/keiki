# keiki-codec-json-test

Property-test toolkit for downstream consumers of
[keiki-codec-json](../keiki-codec-json/README.md). Two modules,
each exposing helpers wired into `hspec` test suites with one line.

## What this is for

The lede is the **case-#10 detector**: a per-slot-type golden-byte
test that catches a silent change to a slot type's `Aeson.ToJSON`
instance. This is the schema-evolution failure mode the shape hash
in [`Keiki.Shape`](../src/Keiki/Shape.hs) cannot detect by design —
the hash is over the slot type's *TypeRep*, not over its encoding.
If a consumer edits the `ToJSON` instance to change the on-the-wire
shape, the hash stays the same and old snapshots silently fail to
decode. `slotGoldenSpec` is the contract anchor that makes the drift
loud and obvious.

The secondary helpers re-expose the EP-36 M3 in-tree property
disciplines (Value-path / Encoding-path round-trip, within-path
determinism, structural sensitivity) as library functions
parameterised over the consumer's own slot list, so they don't have
to be re-authored downstream.

## Using

    import Data.Proxy (Proxy (..))
    import qualified Data.Text as T
    import Test.Hspec (Spec, describe, hspec)

    import Keiki.Codec.JSON.Test
      ( regFileCodecProps
      , regFileShapeSensitivitySpec
      , someKnownShape
      )
    import Keiki.Codec.JSON.Test.Golden
      ( SlotGolden (..)
      , slotGoldenSpec
      )

    -- Your slot type and slot lists:
    -- data Email = Email Text deriving (...)
    -- type MySlots = '[ '("email", Email), '("count", Int) ]
    -- type MySlotsRenamed = '[ '("emailAddress", Email), '("count", Int) ]

    main :: IO ()
    main = hspec $ do
      -- Case-#10 detector. One slotGoldenSpec per slot type whose
      -- ToJSON / FromJSON instances you want to pin.
      slotGoldenSpec "Email" (SlotGolden
        { sgInput = Email (T.pack "alice@example.com")
        , sgBytes = "\"alice@example.com\""
        })

      -- Round-trip + determinism over the snapshot's slot list.
      describe "props: MySlots" (regFileCodecProps @MySlots)

      -- Sensitivity: every named mutation must flip the shape hash.
      describe "sensitivity: MySlots" $
        regFileShapeSensitivitySpec
          (Proxy @MySlots)
          [ ("rename email", someKnownShape @MySlotsRenamed) ]

The toolkit assumes each slot type has `Aeson.ToJSON`,
`Aeson.FromJSON`, `Arbitrary` (for the property suite),
`CanonicalTypeName` (for the shape hash; default `Typeable`-based
instance is usually enough), `Eq`, and `Show`. If your slot type
lacks `Arbitrary`, write one — it is typically a one-liner via
`quickcheck-instances` for the standard library types.

## When you don't need this

`keiki-codec-json` alone is sufficient for production use. This
package is opt-in for test suites. Pulling it in adds `QuickCheck`,
`hspec`, and `quickcheck-instances` as transitive deps; if you only
want the codec in production, do not depend on this package.

## Running the self-test

    cabal test keiki-codec-json-test:keiki-codec-json-test-test

The self-test exercises every public helper against a small toy
fixture (`Email`, `DemoSlots`, `DemoSlotsRenamed`). Expected
output: 7 examples, 0 failures.
