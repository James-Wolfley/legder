# legder file device

Milestone 2, desktop half: a legder block device backed by one file.
This is the Storage_Adapter in the class diagram; its `Read`, `Write`
and `Sync` are the device formals of `Legder.Log` / `Legder.Store`.

```ada
with Legder;
with Legder.File_Device;
with Legder.Store;

package Model is new Legder (K_Size => 8, V_Size => 4);
package Dev is new Model.File_Device (Blocks => 256);
package KV is new Model.Store
  (Dev.Last_Block, Dev.Read, Dev.Write, Dev.Sync, Capacity => 256);

Dev.Open ("settings.ldgr", Result);
if Result = Dev.Ok then
   KV.Open (S, Replayed, Status);
end if;
```

Add `legder_file_device` to your crate's dependencies (pinned by path
like `legder`), and `with "legder_file_device";` in your project.

This configuration uses 25-byte blocks and a 6,400-byte image, including
the header block. Omitting K and V selects 32 and 256, producing 301-byte
blocks. `Blocks` includes the header and is independent of live capacity.

## Storage behavior

| Fault model (top-level README) | How |
|---|---|
| logical block addressing | block `I` lives at byte `I * Block_Size` |
| writes before the last Sync are durable | `fsync` (Linux), `_commit` (Windows) |
| writes after it may vanish | nothing relies on them |

Plus:

- **New files are erased flash.** Created at full size, filled with
  `FF` and synced before `Open` returns `Ok`. Linux also syncs the
  containing directory.
- **Short files recover.** A file cut off mid-creation is extended with
  `FF` after header validation; a partial record remains torn.
- **It never scribbles on files that are not stores.** If block 0 is
  neither erased nor a legder header, `Open` returns `Foreign` and
  writes nothing. Version 1 images return `Bad_Version`, and different
  K/V sizes return `Wrong_Sizes`, before extension. An oversized file
  returns `Too_Large` without modification.
- **One writer.** `Open` takes a non-blocking exclusive lock
  (`flock` / `LockFileEx`); a second opener gets `Locked`.
- **Fail-stop.** The device formals report `Failed` on I/O errors.
  Direct exception-bearing operations raise `Device_Error`. The device
  refuses further I/O until `Close` + `Open`. That resets the device
  handle, but does not establish safe recovery after a Linux writeback
  error. Shared recovery protection is tracked in
  [#29](https://github.com/James-Wolfley/legder/issues/29).

Target-selected Ada bindings implement sync, locking, and positional I/O.
Linux retries interrupted calls and completes short transfers.
This crate is outside SPARK. Logical block size does not establish a
physical failure boundary; the backend requirements remain those in
`../../docs/storage-contract.md`.

## Tests

```
cd tests && alr build
./bin/file_device_tests        # unit: reopen, torn block, short file, lock, foreign, fail-stop
./crash_test.sh 25             # SIGKILL a writer at random, check the acked prefix survives
```

The crash test kills the process at any instruction, including during
file creation and the header write, and checks that the reopened store
is exactly Puts `1 .. N` with `N` = last ack or last ack + 1 (the Put
that committed before its ack was printed). `SIGKILL` keeps the kernel
page cache, so these checks do not establish power-loss safety or recovery
after failed writeback.

Verified on 64-bit Linux. Windows testing is not complete yet.
