# legder

A crash-safe transactional storage engine you can prove correct.
Fixed block device underneath, write-ahead log in the middle, a
bounded key-value store on top. Ada/SPARK, no heap, no access types.

GNAT Academic Program capstone project. Proposal title: *Legder:
Embedded Transactional Storage Engine*.

## What it is

Every embedded product that keeps settings, counters or logs across
power cycles has one of these, usually hand-rolled and usually wrong
the first three times. The failure is always the same: power goes at
the wrong moment and the device comes back with half a record.

legder's claim is small and provable: **after any crash, what you read
back is exactly the set of operations that had been acknowledged, in
order, and nothing else.**

The mechanism:

- One record per device block. A block write is atomic or torn; a
  torn block fails its CRC.
- Every record carries the next sequence number. Recovery reads
  blocks in order and stops at the first block that is not a valid
  record with sequence = previous + 1.
- Put and Delete write the record and sync *before* touching the
  in-memory table. The table is always a replay of the log.

## What is in the seed

```
src/legder.ads                Byte, Block, Key, Value, Sequence, CRC          done
src/legder-record_format.ads  the on-disk record, Encode/Decode with CRC     done
src/legder-log.ads            generic WAL: Open (recover), Append, Scan      done
src/legder-store.ads          generic KV store on the log                    done, PLACEHOLDER index
src/legder-ram_device.ads     in-memory device with crash injection          done
devices/file/                 file-backed device (milestone 2, desktop)      done
showcase/                     write, tear a block, recover, check            acceptance test
tests/                        30 checks incl. CRC vectors and crash cases    extend as you go
```

Everything compiles, the crash tests pass, and recovery works. What is
a placeholder is the store's index: a linear scan over a 256-entry
array. Correct and slow. What is missing entirely is compaction: the
log only grows, and when the device is full, Put fails.

Read `ARCHITECTURE.md` before touching anything.

See [design documentation](docs/README.md) for the class diagram and its
editable diagrams.net source.

## Milestones

1. **Prove the record format.** `Legder.Record_Format` under
   `gnatprove --mode=all`: index safety (R2) and, if you can, the
   round trip (R1). First real proof, small package.
2. **A real device.** Implement Read/Write/Sync over a file on the
   desktop, then over SD or flash on a board. Run the showcase on it.
   Pull the plug on a real board mid-write. Recover.
3. **Compaction.** When the log is nearly full, write the live table
   as a fresh sequence of records into a second region and switch.
   This is where the crash-safety argument gets interesting: the
   switch itself must be atomic.
4. **A real index.** Replace the linear scan. Sorted array with binary
   search is enough; a B-tree is a stretch. Do not change the commit
   order while doing this.
5. **Prove S1.** State the store's meaning as a ghost functional map
   and prove Put, Delete and Open against it. The year's headline.

## Build

Three [Alire](https://alire.ada.dev) crates; showcase and tests pin
the library by path.

```
alr build                       # library
cd showcase && alr build && alr run
cd tests && alr build && ./bin/tests
alr with gnatprove && alr exec -- gnatprove -P legder.gpr --mode=flow
```

Contracts are checked at runtime in every build (`-gnata`).

## Rules of the road

- Warnings are errors, style checks on. Run tests before every push.
  Do not add CI workflows until further notice.
- `src/` is SPARK. Devices other than RAM live in `devices/<name>/`
  and are the only place `SPARK_Mode => Off` is allowed.
- Never write to the table before the log has synced. That is the
  invariant. A change that breaks it is wrong however fast it is.
- The fault model is: one block may be torn, writes before the last
  Sync are durable, writes after it may vanish. A device that cannot
  promise that is not a legder device; put a translation layer under it.

See `CONTRIBUTING.md` for the fork workflow.

## Contact

Olivier Henley, GAP Coordinator, AdaCore. Weekly meeting, plus the
project Discord.

## License

Apache-2.0. See `LICENSE`.
