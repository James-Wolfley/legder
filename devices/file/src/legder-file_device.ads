--  A block device backed by one file on a desktop file system.
--
--  This is the Storage_Adapter of the design: the three subprograms
--  Read, Write and Sync are the actuals for the device formals of
--  Legder.Log and Legder.Store. Instantiate it once per file:
--
--     package Dev is new Legder.File_Device (Last_Block => 255);
--     package KV  is new Legder.Store
--       (K, V, Dev.Block_Count, Dev.Read, Dev.Write, Dev.Sync);
--
--     Dev.Open ("settings.ldgr", Result);   --  then KV.Open (...)
--
--  The file is the device image: blocks 0 .. Block_Count, 512 bytes
--  each, at offset Index * Block_Size. A new file is created at full
--  size and filled with 16#FF#, like erased flash, and flushed before
--  Open returns.
--
--  Fault model, as README.md requires of a legder device:
--    * Sync returns only after the operating system reports every
--      earlier Write durable: fsync on Linux, _commit on Windows.
--    * A block write that is cut short leaves one torn block, which
--      the record CRC rejects. Nothing else is overwritten.
--    * Writes after the last Sync may be lost. The log never relies
--      on them.
--
--  Errors are fail-stop. The device formals have no status out
--  parameter, and a Write or Sync that failed must never look like a
--  commit, so Read, Write and Sync raise Device_Error instead. After an
--  error the device refuses all I/O until it is closed and reopened,
--  because after a failed fsync the kernel may already have dropped the
--  dirty pages: retrying Sync could report success for data that is gone.
--  A Store over this device does not recover by itself: discard it,
--  close the device, reopen both and let replay recover the log.
--
--  One writer: Open takes an exclusive, non-blocking lock on the file,
--  so a second process (or a second instance in this one) gets Locked.
--
--  This package is outside SPARK: with Legder.File_Device_OS it is the
--  only place that touches the operating system.

generic
   Last_Block : Block_Index;
   --  Last block of the device. The file is (Last_Block + 1) * 512
   --  bytes, at most 2 MiB.
package Legder.File_Device with SPARK_Mode => Off is

   Block_Count : constant Block_Index := Last_Block;
   --  The actual for Legder.Store's Block_Count, named as on the RAM
   --  device so the two swap without other changes.

   type Open_Result is
     (Ok,            --  open, locked, full size; ready for Store.Open
      Already_Open,  --  this instance already has a file; nothing done
      Cannot_Open,   --  the file could not be opened or created
      Locked,        --  another open device holds the file
      Too_Large,     --  bigger than this Block_Count; would lose blocks
      Foreign,       --  block 0 is neither erased nor a legder header
      IO_Failed);    --  read, extend or sync failed while opening
   --  Every result other than Ok leaves the device closed, except
   --  Already_Open, which leaves the open device untouched. Only a
   --  missing or short file is ever written by Open.

   Device_Error : exception;
   --  Raised by Read, Write, Sync and Erase on I/O failure, on use of a
   --  closed or failed device, and by Write past Block_Count.

   Image_Bytes : constant Long_Integer :=
     (Long_Integer (Block_Count) + 1) * Block_Size;
   --  Size of the device file.

   procedure Open (Path : String; Result : out Open_Result);
   --  Opens Path, creating it as an erased image if it does not exist.
   --  An existing file shorter than Image_Bytes (a crash while it was
   --  being created) is extended with 16#FF#, which reads as erased or,
   --  inside a partial block, as torn. A file whose block 0 is neither
   --  erased nor a valid legder header is refused as Foreign, untouched.
   --  On Ok the file is locked and everything this call wrote is
   --  durable. Linux also confirms the containing directory entry;
   --  Windows leaves that entry to the file system's journal.

   procedure Close;
   --  Releases the file and the lock. No Sync: anything not synced may
   --  be lost, exactly as on power loss. Safe to repeat. Clears a
   --  failed state.

   function Is_Open return Boolean;
   --  True after Open returned Ok, until Close.

   function Has_Failed return Boolean;
   --  True once an I/O error has been raised, until Close.

   procedure Read (Index : Block_Index; Data : out Block);
   --  The last block written at Index (durable or not). An index past
   --  Block_Count reads as erased, like the RAM device.

   procedure Write (Index : Block_Index; Data : Block);
   --  Writes one block at Index. Not durable until Sync returns.

   procedure Sync;
   --  Returns only when every earlier Write is on stable storage.

   procedure Erase;
   --  Every block to 16#FF#, then Sync. Destroys the store in the file.

end Legder.File_Device;
