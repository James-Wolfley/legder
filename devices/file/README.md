# legder file device

Milestone 2, desktop half: a legder block device backed by one file.
This is the Storage_Adapter in the class diagram; its `Read`, `Write`
and `Sync` are the device formals of `Legder.Log` / `Legder.Store`.

```ada
with Legder.File_Device;
with Legder.Store;

package Dev is new Legder.File_Device (Last_Block => 255);   --  128 KiB file
package KV  is new Legder.Store
  (8, 4, Dev.Block_Count, Dev.Read, Dev.Write, Dev.Sync);

Dev.Open ("settings.ldgr", Result);     --  creates it on first use
if Result = Dev.Ok then
   KV.Open (S, Replayed, Status);
end if;
```

Add `legder_file_device` to your crate's dependencies (pinned by path
like `legder`), and `with "legder_file_device";` in your project.

## What it promises

| Fault model (top-level README) | How |
|---|---|
| a block write is whole or torn | block `I` lives at byte `I * 512`; a torn one fails its record CRC |
| writes before the last Sync are durable | `fsync` (Linux), `F_FULLFSYNC` (macOS), `_commit` (Windows) |
| writes after it may vanish | nothing relies on them |

Plus:

- **New files are erased flash.** Created at full size, filled with
  `FF`, synced, and the directory synced, before `Open` returns `Ok`.
- **Short files recover.** A file cut off mid-creation is extended with
  `FF`; a partial block reads as torn.
- **It never scribbles on files that are not stores.** If block 0 is
  neither erased nor a legder header, `Open` returns `Foreign` and
  writes nothing. A file larger than the device is `Too_Large`.
- **One writer.** `Open` takes a non-blocking exclusive lock
  (`flock` / `LockFileEx`); a second opener gets `Locked`.
- **Fail-stop.** The device formals have no status parameter, so I/O
  errors raise `Device_Error`. The store only touches its table after
  `Append` returns, so the table still matches the log. The device then
  refuses all I/O until `Close` + `Open`: after a failed fsync the
  kernel may have dropped the data already, so a retried Sync could lie.

`src/legder_file_device.c` is the only C: sync, lock, and directory
sync, the three calls `GNAT.OS_Lib` lacks. This crate is outside
SPARK, as the rules require for non-RAM devices.

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
page cache, so it does not lose unsynced writes the way power loss
does; that half of the milestone is the board with its plug pulled.

Tested on Linux (ext4). The macOS and Windows branches of the C shim
compile-time select the right sync and lock but have not been run.
