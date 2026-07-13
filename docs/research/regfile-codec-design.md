# `RegFile` JSON codec and shape hash — design note

This document is the durable design summary for keiki's optional JSON
codec primitive and its companion shape hash. It records the
user-visible shape of the API, the worked snapshot example that drives
the design, and the architectural commitments that survive even if the
EP-36 plan is archived. For the rationale behind every choice and the
full menagerie of considered alternatives, see
[`docs/plans/36-regfile-json-codec-and-shape-hash-for-snapshot-persistence.md`](../plans/36-regfile-json-codec-and-shape-hash-for-snapshot-persistence.md).


## Two halves, two packages

The snapshot story has two primitives:

- A **shape hash** — a SHA-256 of a canonical encoding of the
  type-level slot list. Catches structural drift (slot added, removed,
  renamed, reordered, retyped) so that snapshots whose hash differs from
  the current code's hash are invalidated and replayed from scratch.
- A **codec** — encoder/decoder for `RegFile rs ↔ Aeson.Value` plus a
  streaming encoder over `Aeson.Encoding`.

These ship in two packages:

| Primitive                         | Module               | Package           | Adds dep   |
|-----------------------------------|----------------------|-------------------|------------|
| `class CanonicalTypeName`         | `Keiki.Shape`        | `keiki`           | sha256     |
| `class KnownRegFileShape`         | `Keiki.Shape`        | `keiki`           |            |
| `regFileShapeHash`                | `Keiki.Shape`        | `keiki`           |            |
| `renderStableTypeRep`             | `Keiki.Shape`        | `keiki`           |            |
| `class RegFileToJSON`             | `Keiki.Codec.JSON`   | `keiki-codec-json`| aeson      |
| `regFileToJSON`                   | `Keiki.Codec.JSON`   | `keiki-codec-json`|            |
| `regFileFromJSON`                 | `Keiki.Codec.JSON`   | `keiki-codec-json`|            |
| `regFileToEncoding`               | `Keiki.Codec.JSON`   | `keiki-codec-json`|            |

The `keiki` package never depends on `aeson`. This is structural, not
merely conventional: a downstream library that wants the hash for any
codec (CBOR, Protobuf, message-pack) gets it without picking up JSON
parser machinery. Future codec packages (`keiki-codec-cbor`,
`keiki-codec-protobuf`) live next to `keiki-codec-json` and reuse
`Keiki.Shape` directly.


## The discrimination contract: what the hash does

`regFileShapeHash :: KnownRegFileShape rs => Proxy rs -> Text`

Given a slot list `'[ '("retryCount", Int), '("cooldownUntil", UTCTime), … ]`,
the hash is

    sha256Hex (slotSym₁ ":" rendered₁ ";" slotSym₂ ":" rendered₂ ";" … "regfile:0")

where `rendered` comes from `CanonicalTypeName`. Common scalar types
have pinned module-independent names (`Int`, `Text`, `UTCTime`, and so
on), and container instances recurse through the class (`Maybe(Int)`,
`Either(Text,Int)`, ...). User-defined types may accept the
`renderStableTypeRep` default or define an application-owned stable
name. Crucially:

- Built-in identities do not depend on GHC's internal module layout.
- The fallback renderer uses only `tyConModule + tyConName + splitApps`.
- It **never** uses `tyConPackage` (varies with cabal version pins).
- It **never** uses `Show TypeRep` (not contractually stable).
- It **never** uses the raw `Type.Reflection.Fingerprint` (changes
  with GHC).

The result is that hashes over pinned built-ins are byte-equal across
supported GHC majors as well as rebuilds and dependency-tree changes.
Application types get the same guarantee when they pin their own
`CanonicalTypeName`; the default deliberately retains module identity.
The release-blocking gate at CI
(`.github/workflows/ci.yml`) asserts this for every entry in
`tested-with`; the §8 procedure documented in
[`keiki-codec-json/CONTRIBUTING.md`](../../keiki-codec-json/CONTRIBUTING.md)
spells out what to do on a failure.


## The two-discriminant snapshot pattern

The canonical consumer (keiro) writes snapshots as rows in
`keiro_snapshots` with two discriminator columns:

    CREATE TABLE keiro_snapshots (
      ...
      state_codec_version  INT      NOT NULL,
      regfile_shape_hash   TEXT     NOT NULL,
      payload              BYTEA    NOT NULL,
      ...
    );

Where:

- `state_codec_version` is the **consumer's** discriminator. Bumped
  manually when the consumer changes a slot type's `ToJSON` instance
  in a wire-breaking way (a case the hash cannot catch by design — the
  hash is over the type, not the encoding). Cases #10–#12 in the EP-36
  §4 table belong here.
- `regfile_shape_hash` is **keiki's** discriminator, computed by
  `regFileShapeHash (Proxy @rs)` at the call site. Catches every
  structural change (slot added, removed, renamed, reordered,
  retyped) — cases #1–#9 in §4.

On hydration, a snapshot is eligible iff *both* match. Either alone is
insufficient; together they are robust. The disjointness is documented
in haddock on both classes so users hit the rationale at the API
surface.


## Worked example: keiro snapshot persister

Suppose a workflow's joint state is

    type RetryRegs =
      '[ '("retryCount",    Int)
       , '("cooldownUntil", UTCTime)
       , '("correlationId", Text)
       ]

The persister:

    {-# LANGUAGE DataKinds, TypeApplications #-}

    import Data.Proxy
    import qualified Data.Aeson as Aeson
    import qualified Data.Aeson.Encoding as AesonEnc
    import qualified Data.ByteString.Lazy as LBS

    import Keiki.Core         (RegFile)
    import Keiki.Codec.JSON   (regFileFromJSON, regFileToEncoding)
    import Keiki.Shape        (regFileShapeHash)

    writeSnapshot
      :: SnapshotStore
      -> StreamId
      -> SequenceNumber
      -> (s, RegFile RetryRegs)
      -> IO ()
    writeSnapshot store stream pos (s, rf) = do
      let hash    = regFileShapeHash (Proxy @RetryRegs)
          bytes   = (encodeS s, AesonEnc.encodingToLazyByteString (regFileToEncoding rf))
          version = currentStateCodecVersion
      insertRow store stream pos version hash bytes

The hydrator:

    readSnapshot
      :: SnapshotStore
      -> StreamId
      -> SequenceNumber
      -> IO (Maybe (s, RegFile RetryRegs))
    readSnapshot store stream pos = do
      row <- lookupRow store stream pos
      case row of
        Nothing -> pure Nothing
        Just SnapshotRow{..} -> do
          let currentVersion = currentStateCodecVersion
              currentHash    = regFileShapeHash (Proxy @RetryRegs)
          if rowVersion /= currentVersion || rowHash /= currentHash
            then pure Nothing  -- replay from event 0
            else case (decodeS rowPayloadS, Aeson.decode rowPayloadRf) of
                   (Just s, Just v) -> case regFileFromJSON @RetryRegs v of
                     Right rf -> pure (Just (s, rf))
                     Left _   -> pure Nothing
                   _ -> pure Nothing

Returning `Nothing` from the hydrator is the snapshot-invalidation
signal — the runtime then replays events from the beginning. The
two-discriminant check ensures that this is a structural decision (the
shape changed) or a consumer-managed decision (the encoding changed
wire-format), never silent corruption.


## Slot-value size — when to use the streaming encoder

keiki's per-slot dispatch overhead is microseconds at any realistic
slot count (< 1000 slots). Encoding cost is dominated by each slot
value's `ToJSON` instance and the size of the value. EP-36 §10's
reference cases exhibit RegFiles of 50 KB to 10 MB encoded; the codec
serves all of them, but the Value path
(`Aeson.encode . regFileToJSON`) allocates an intermediate
`Aeson.Value` of size proportional to the output JSON. For multi-MB
slot values this is a measurable young-gen GC pressure and a P99
latency hazard.

The streaming encoder (`regFileToEncoding`) walks the slot list
directly into an `Aeson.Series` via `Aeson.pairs`, avoiding the
intermediate. Benchmarks at
[`keiki-codec-json/bench/baseline.csv`](../../keiki-codec-json/bench/baseline.csv)
show ~1.5× faster encoding and ~33 % less allocation on the §10 Case B
fixture (5,000 processedItems, ~250 KB encoded JSON). For users with
multi-megabyte RegFiles the win compounds: the streaming path has O(1)
intermediate memory pressure rather than O(output-size).

When to reach for which:

- **Streaming encoder** — RegFiles whose encoded size is > ~100 KB, or
  high snapshot rates (Case D's auction aggregate), or any case where
  the encode runs in a hot path.
- **Value encoder** — RegFiles where you also want to manipulate the
  `Aeson.Value` (overlay with other JSON, project a sub-shape, prepare
  a diff for an audit log). The Value path round-trips through
  `regFileFromJSON` exactly like the streaming path; the two are
  semantically equivalent.

Beyond the streaming encoder, EP-36 §5 P11 also notes that some bulk
slots simply do not belong in the RegFile — projecting bulk data into
a separate event stream and reading it via subscription is often
structurally cleaner. The codec primitive serves the case; the
structural decision is the user's.


## Reference

- The full ExecPlan, including alternatives considered, lock-points,
  and the §10 reference cases at length:
  [`docs/plans/36-regfile-json-codec-and-shape-hash-for-snapshot-persistence.md`](../plans/36-regfile-json-codec-and-shape-hash-for-snapshot-persistence.md).
- The MasterPlan coordinating EP-36 with the Phase B Hackage release,
  TH derivation, and property-test toolkit plans:
  [`docs/masterplans/11-keiki-codec-json-package-implementation-and-rollout.md`](../masterplans/11-keiki-codec-json-package-implementation-and-rollout.md).
- The keiki-side architectural anchor for the codec-free stance:
  [`effects-boundary.md`](effects-boundary.md) lines 72–73.
- The schema-evolution policy the hash implements:
  [`schema-evolution.md`](schema-evolution.md) lines 19–22.
- The §8 GHC upgrade procedure:
  [`../../keiki-codec-json/CONTRIBUTING.md`](../../keiki-codec-json/CONTRIBUTING.md).
