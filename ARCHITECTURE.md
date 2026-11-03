# Architecture

## Layers

```
application
     |
Legder.Store        bounded KV map = replay of the log        generic over the device
     |
Legder.Log          append-only WAL, recovery by scan         generic over the device
     |
Legder.Record_Format  one block <-> one record, CRC           pure
     |
Legder.Header       block 0: magic, version, K, V, CRC        pure
     |
Legder              Byte, Block, Key, Value, Sequence, CRC    pure
     |
device              Read (Index, out Block) / Write (Index, Block) / Sync
                    Legder.RAM_Device in the seed; file, SD, flash are milestones
```

The device is three generic formal subprograms, not a tagged type.
A store is instantiated once with one device; there is nothing to
dispatch on at runtime, and SPARK sees plain calls.

## Fundamental types

| Type | Definition | Why |
|---|---|---|
| `Block` | 512 bytes | SD sector, flash page granule; a record never spans two |
| `Block_Index` | 0 .. 4095 | 2 MiB max device, bounded so the log is an array |
| `Key` | length + 32 bytes | fixed, so a record has a fixed layout |
| `Value` | length + 256 bytes | same |
| `Sequence` | mod 2**64 | never wraps in practice; consecutive = adjacent |
| `CRC32` | mod 2**32 | IEEE 802.3, the zlib one, table-free body |

Keys compare on live bytes only (`"="` is overridden); padding is
never significant.

## Header

Block 0 holds a 12-byte header: magic, version, key size, value size,
and a CRC-32 over the first eight bytes. It declares K and V once, and
they are fixed for the life of the store. It is written on an erased
device before any record, and validated on every open. A block 0 that
is neither erased nor a valid header is refused, never overwritten.

## Record format

One record per block, fixed offsets (table in
`legder-record_format.ads`). Kind, sequence, key, value, CRC over
everything before it. No magic and no lengths: the header supplies K
and V, so every record carries exactly K + V payload bytes, and a
Delete writes V zero bytes that `Decode` checks. `Decode` is total:
anything that is not a record (erased FF, zeroed, torn, bit-flipped)
comes back `Valid = False`.

Why fixed layout and one block per record: a partial write corrupts
at most one record, and that record fails its CRC. That single fact is
what the whole crash argument rests on. Packing several records per
block would need a second-level commit marker; not for v1.

## Log

Block 0 holds the header. Records occupy blocks `1 .. Block_Count` in
order. `Head` is the next free block.

Commit: encode with `Seq = Last_Seq + 1`, write block `Head`, `Sync`,
then advance. Recovery (`Open`): read and validate block 0, then read
records from block 1, accept a block only if `Valid` and
`Seq = previous + 1`, stop at the first that is not. The accepted
prefix is exactly the set of commits whose `Sync` returned.

An erased block 0 is a fresh store: the header is written there and
synced first. Any other unusable block 0 refuses the open, reporting
`Bad_Header`, `Bad_Version` or `Wrong_Sizes`.

Three cases at the record boundary, all handled by the same test:
- block never written (erased): not Valid, stop
- block torn: CRC fails, not Valid, stop
- block holds an old valid record from a previous life of the device
  (e.g. after a future compaction): Seq is wrong, stop

`Scan` replays the accepted prefix through a generic `Visit`. `Open`
and the store use the same walk, so they cannot disagree.

No compaction in v1: when Head passes Block_Count the log is full and
Append fails. Milestone 3.

## Store

A fixed array of `Max_Entries` slots. `Put`/`Delete`: refuse early if
the table cannot take the key (S3), else `Append`, and only on success
`Apply` the record to the table. `Open`: `Log.Open` then `Scan` with
`Apply` as the visitor. One `Apply` for both live updates and replay.

The index (linear scan) is the placeholder. Replace it; keep the
commit order.

## RAM device and fault injection

`Legder.RAM_Device` keeps a durable copy and a pending copy per block.
`Write` goes to pending, `Sync` promotes pending to durable.
`Tear_Next_Write` corrupts the front half of the next block written.
`Drop_Unsynced` discards pending. Together they model exactly the
fault model the log promises to survive, and nothing more. A real
device is expected to behave at least this well; if it does not (flash
without a write-complete guarantee, an SD card that lies about sync),
a translation layer underneath is the fix, not a weaker log.

## Proof plan

- R2 (record index safety): free with SPARK, all offsets are constants.
- R1 (round trip): needs a lemma per field; doable.
- L1 (scan stops at the first gap): loop invariant over the prefix.
- L2, L3: need a ghost model of the device (an array of blocks plus a
  "durable" flag); write it in the tests first as executable ghost
  code, then lift.
- S1 (store meaning): a ghost functional map `Model (S)`, with
  `Put`/`Delete`/`Open` postconditions stated on it. This is the goal.

## What is deliberately not here

- No transactions spanning several operations. One record is one
  commit. Multi-op atomicity is a `Begin`/`Commit` marker pair on top
  of this log; design it after S1 proves.
- No wear levelling, no bad-block handling. A device layer's job.
- No concurrency. One writer.
