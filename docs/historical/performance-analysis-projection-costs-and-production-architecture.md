# Performance Analysis

Performance concerns for using this library in a production event-sourced
system, ordered from most to least critical.

---

## 1. The `outputProjection` Linear Scan — The Main Problem

**Severity: High (if used naively)**

The derived `apply` function from `toDecider` does a **linear scan of the
entire command alphabet** on every call:

```haskell
-- outputProjection, called per event during reconstitution:
findTransition t' s e =
  let matches =
        [ s' | c <- allCommands          -- O(|C|) enumeration
             , omega t' s c == Just e    -- O(1) per command
             , Just s' <- [delta t' s c] -- O(1) per command
             ]
  in case matches of
       (s' : _) -> Just s'
       []       -> Nothing
```

**Cost per `apply` call:** O(|C|) where |C| is the number of commands.

**Cost of reconstitution:** O(N × |C|) where N is the number of events.

For a typical DDD aggregate with 4-10 commands, this is fine. But consider:

| |C| (commands) | N (events) | `apply` calls | Overhead vs. direct pattern match |
|---|---|---|---|
| 4 | 100 | 100 | 4x |
| 10 | 1,000 | 1,000 | 10x |
| 50 | 10,000 | 10,000 | 50x |
| 50 | 100,000 | 100,000 | 50x |

A hand-written `apply` (direct pattern match) is O(1) per call.
The derived `apply` is O(|C|) per call. For an aggregate with 50 commands
replaying 100,000 events, that's 5,000,000 command comparisons instead
of 100,000 pattern matches.

### Mitigations

**Option A: Pre-compute a lookup table at construction time.**

Build a `Map (s, e) s` when `toDecider` is called, so runtime `apply`
is O(log(|S| × |E|)) instead of O(|C|):

```haskell
toDeciderFast
  :: (Enum s, Bounded s, Enum c, Bounded c, Eq e, Ord s, Ord e)
  => Transducer s c e
  -> Decider c e s
toDeciderFast t =
  let table = Map.fromList
        [ ((s, e), s')
        | s <- [minBound..maxBound]
        , c <- [minBound..maxBound]
        , Just s' <- [delta t s c]
        , Just e  <- [omega t s c]
        ]
  in Decider
    { exec    = omega t
    , apply   = \s e -> Map.lookup (s, e) table   -- O(log n) per call
    , initial = initial t
    , isFinal = isFinal t
    }
```

Construction cost: O(|S| × |C|) — paid once.
Runtime `apply` cost: O(log(|S| × |E|)) per call.

**Option B: User-provided `apply` (Approach 3 / MultiDecider).**

The user writes `apply` as a direct pattern match — O(1) per call.
Verify correctness with Hedgehog's exhaustive property test.
This is what we recommend for production anyway.

**Option C: Use an unboxed array for the lookup table.**

If `s` and `e` derive `Enum`/`Bounded`, use a 2D array indexed by
`(fromEnum s, fromEnum e)` for O(1) lookup:

```haskell
toDeciderArray
  :: (Enum s, Bounded s, Enum c, Bounded c, Enum e, Bounded e, Eq e)
  => Transducer s c e
  -> Decider c e s
toDeciderArray t =
  let sRange = (fromEnum (minBound @s), fromEnum (maxBound @s))
      eRange = (fromEnum (minBound @e), fromEnum (maxBound @e))
      arr = Array.array ((fst sRange, fst eRange), (snd sRange, snd eRange))
        [ ((fromEnum s, fromEnum e), findNext s e)
        | s <- [minBound..maxBound]
        , e <- [minBound..maxBound]
        ]
      findNext s e =
        listToMaybe [ s' | c <- [minBound..maxBound]
                         , omega t s c == Just e
                         , Just s' <- [delta t s c] ]
  in Decider
    { exec    = omega t
    , apply   = \s e -> arr Array.! (fromEnum s, fromEnum e)  -- O(1)
    , initial = initial t
    , isFinal = isFinal t
    }
```

Construction: O(|S| × |E| × |C|). Runtime `apply`: O(1).

### Recommendation

Use **Option B** (user-provided `apply`) for production aggregates.
Use `toDecider` / `toDeciderFast` for testing and prototyping.
The exhaustive Hedgehog property guarantees the hand-written `apply`
matches the derived one.

---

## 2. Reconstitution Without Snapshots

**Severity: High (for long-lived aggregates)**

`reconstitute` replays the entire event history from S₀:

```haskell
reconstitute d events = foldlM (apply d) (initial d) events
```

This is O(N) where N is the total number of events for the aggregate.
For a long-lived aggregate with 100,000 events, every command requires
replaying all 100,000 events to recover the current state.

This is not specific to this library — it's inherent to event sourcing.
But the library currently provides no snapshotting support.

### Mitigation: Snapshot Layer

Snapshots belong in the infrastructure layer, not in the aggregate model.
The library should provide a hook point:

```haskell
-- | Reconstitute from a snapshot + remaining events.
--
-- Instead of replaying from S₀, start from a known-good state
-- and replay only the events after the snapshot.
reconstituteFrom :: Decider c e s -> s -> [e] -> Maybe s
reconstituteFrom d snapshot events = foldlM (apply d) snapshot events
```

The snapshot storage strategy (every N events, time-based, etc.) is an
infrastructure concern. The library just needs `reconstituteFrom` —
which is trivial, since `reconstitute` is just `reconstituteFrom` with
`initial d` as the snapshot.

**Cost with snapshots:** O(K) where K is events since last snapshot,
typically K << N.

---

## 3. `Maybe` Allocation on Every Transition

**Severity: Low-Medium**

Every `delta`, `omega`, `exec`, and `apply` call wraps its result in
`Maybe`, allocating a `Just` constructor:

```haskell
delta :: s -> c -> Maybe s     -- allocates Just on success
omega :: s -> c -> Maybe e     -- allocates Just on success
```

In a hot reconstitution loop processing 100,000 events, that's 100,000+
`Just` allocations.

### Mitigation

GHC is very good at optimizing `Maybe` in strict code. With `-O2` and
the right strictness annotations, the `Just` constructor is often
unboxed or eliminated entirely.

Ensure reconstitution is strict:

```haskell
reconstitute :: Decider c e s -> [e] -> Maybe s
reconstitute d = foldl' step (Just (initial d))  -- strict fold
  where
    step Nothing  _ = Nothing
    step (Just s) e = apply d s e
```

If profiling shows `Maybe` allocation as a bottleneck, provide an
unsafe unchecked path for trusted event streams (where all events
are known valid because they came from the event store):

```haskell
-- | Reconstitute from a trusted event stream.
-- UNSAFE: crashes on invalid events instead of returning Nothing.
reconstituteUnsafe :: Decider c e s -> [e] -> s
reconstituteUnsafe d = foldl' step (initial d)
  where
    step s e = case apply d s e of
      Just s' -> s'
      Nothing -> error "reconstituteUnsafe: invalid event in trusted stream"
```

In practice, events from the store should always be valid (they were
validated on write). The `Maybe` is a safety net, not an expected path.

---

## 4. Expanded State Wrapper (Approach 2)

**Severity: Low-Medium**

The GSM expansion wraps states in `Expanded s e`:

```haskell
data Expanded s e = Settled s | Mid s [e]
```

Two concerns:

**Pattern match overhead**: Every `apply` call matches on `Settled`/`Mid`.
GHC compiles this to a tag check — negligible.

**`Mid` carries a list**: `Mid s [e]` holds the remaining events to emit.
For a command producing N events, this list has N-1 elements and is
consumed one at a time. Each `Tick` transition conses off the head.
For typical multi-event commands (2-5 events), this is fine.

If a command produces 100 events, `Mid` carries a 99-element list
through 99 intermediate states. This is unlikely in DDD but worth noting.

### Mitigation

Use Approach 3 (direct MultiDecider) for production. The `Expanded`
wrapper is most useful for testing and formal verification, not runtime.

---

## 5. Product State Growth from Composition

**Severity: Low**

Each `compose` or `union` nests the state type:

```haskell
compose t1 t2  :: Transducer (s1, s2) c e
compose (compose t1 t2) t3 :: Transducer ((s1, s2), s3) c e
```

Three compositions deep gives `(((s1, s2), s3), s4)`. This is:
- More pointer chasing (nested tuples are boxed by default)
- Harder for GHC to optimize
- Awkward to pattern match on

### Mitigation

For a chain of N compositions, use a flat product type instead:

```haskell
data PipelineState = PipelineState !s1 !s2 !s3 !s4
```

Define the composed transducer with the flat state directly rather than
mechanically composing. Use `compose` for prototyping, flatten for
production.

Alternatively, use strict unboxed tuples or a record with strict fields
to avoid pointer chasing.

---

## 6. Existential Quantification Prevents Specialization

**Severity: Medium (if using coalgebraic encoding)**

The coalgebraic encoding hides state behind an existential:

```haskell
data EffTransducer m c e = forall s. EffTransducer
  { eState :: s
  , eStep  :: s -> c -> m (Maybe (s, Maybe e))
  , eFinal :: s -> Bool
  }
```

GHC cannot specialize `eStep` through the existential boundary. The step
function becomes an indirect call (dictionary lookup), preventing inlining
and fusion.

For a reconstitution loop, this means:
- No unboxing of the state type
- No fusion of consecutive `apply` calls
- Indirect function call per step

### Mitigation

**Keep the concrete `Transducer s c e` for the hot path.** Use the
existential `EffTransducer` / `TransCat` only at composition boundaries
where you need type erasure.

Pattern:

```haskell
-- Define with concrete state (GHC can specialize)
registration :: Transducer RegState RegCommand RegEvent

-- Derive decider with concrete state (GHC can inline apply)
decider :: Decider RegCommand RegEvent RegState
decider = toDeciderFast registration

-- Only erase state at the API boundary
registrationRuntime :: EffTransducer IO RegCommand RegEvent
registrationRuntime = toEff registration
```

The `SPECIALIZE` pragma can help if you must use existentials:

```haskell
{-# SPECIALIZE eStep :: RegState -> RegCommand -> IO (...) #-}
```

---

## 7. No Streaming Reconstitution

**Severity: Medium (for large event streams)**

`reconstitute` takes `[e]` — a full list in memory:

```haskell
reconstitute :: Decider c e s -> [e] -> Maybe s
```

For an aggregate with 1,000,000 events, this loads all events into a
Haskell list before folding. The list itself is O(N) memory even though
the fold only needs O(1) working state.

### Mitigation

Provide a streaming interface:

```haskell
-- | Fold over an event stream without materializing it.
-- Works with any Foldable, including streaming libraries.
reconstituteF
  :: (Foldable f)
  => Decider c e s
  -> f e
  -> Maybe s
reconstituteF d = foldl' step (Just (initial d))
  where
    step Nothing  _ = Nothing
    step (Just s) e = apply d s e

-- | Streaming reconstitution with effectful event source.
-- Pulls events one at a time from an IO action.
reconstituteM
  :: (Monad m)
  => Decider c e s
  -> ConduitT () e m ()         -- or any streaming abstraction
  -> m (Maybe s)
```

With GHC's list fusion (`-O2`), a strict left fold over a list that is
produced lazily (e.g., from a database cursor) will run in O(1) memory
if the producer and consumer fuse. But this fusion is fragile — a
streaming library (conduit, streaming, streamly) provides a guarantee.

---

## Summary

| Concern | Severity | Root Cause | Fix |
|---------|----------|-----------|-----|
| `outputProjection` linear scan | **High** | O(\|C\|) per `apply` | Pre-compute lookup table or user-provided `apply` |
| No snapshots | **High** | O(N) full replay | Add `reconstituteFrom` + infrastructure layer |
| Existential prevents specialization | **Medium** | Indirect calls | Keep concrete types on hot path |
| No streaming reconstitution | **Medium** | `[e]` materialization | `Foldable` or streaming interface |
| `Maybe` allocation | **Low** | Boxing overhead | Strict fold + `-O2`; unsafe path for trusted streams |
| Expanded state wrapper | **Low** | Extra constructors | Use Approach 3 for production |
| Product state nesting | **Low** | Composition depth | Flatten state for production pipelines |

### Production Architecture Recommendation

```
                        ┌─────────────────────────────┐
                        │     Aggregate Definition     │
                        │                             │
Define:                 │  Transducer s c e  (or GSM) │ ← pure, testable
                        │                             │
                        └──────────┬──────────────────┘
                                   │
                        ┌──────────▼──────────────────┐
                        │      Decider c e s           │
Derive or               │                             │
hand-write:             │  exec = omega t              │ ← O(1) per command
                        │  apply = hand-written        │ ← O(1) per event
                        │                             │
                        └──────────┬──────────────────┘
                                   │
                        ┌──────────▼──────────────────┐
                        │   Infrastructure Layer       │
                        │                             │
Wrap:                   │  Snapshot store              │ ← O(K) reconstitution
                        │  Event store (streaming)    │ ← O(1) memory
                        │  Command handler (effectful)│
                        │                             │
                        └─────────────────────────────┘
```

The library provides the top two layers. The infrastructure layer is
separate — it handles persistence, snapshotting, streaming, and effects.

The key discipline: **define the Transducer for correctness, derive or
hand-write the Decider for performance, verify equivalence with Hedgehog.**
