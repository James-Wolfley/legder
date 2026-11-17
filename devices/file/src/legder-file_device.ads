--  A block device backed by one file on a desktop file system.
--  Sync uses fsync on Linux and _commit on Windows. After an I/O error,
--  the device refuses I/O until closed and reopened. A failed fsync may
--  have discarded dirty pages, so retrying Sync is not safe. Reopen the
--  store as well to recover through replay.

generic
   Blocks : Positive := 256;
package Legder.File_Device with SPARK_Mode => Off is

   Last_Block : constant Block_Index := Block_Index (Blocks - 1);

   type Open_Result is
     (Ok,            --  open, locked, full size; ready for Store.Open
      Already_Open,  --  this instance already has a file; nothing done
      Cannot_Open,   --  the file could not be opened or created
      Locked,        --  another open device holds the file
      Too_Large,     --  bigger than this image; would lose blocks
      Foreign,       --  block 0 is neither erased nor a legder header
      Bad_Version,   --  unsupported on-disk format version
      Wrong_Sizes,   --  header sizes do not match this instance
      IO_Failed);    --  read, extend or sync failed while opening
   --  Every result other than Ok leaves the device closed, except
   --  Already_Open, which leaves the open device untouched. Only a
   --  missing or short file is ever written by Open.

   Device_Error : exception;
   --  Raised by Read, Write, Sync and Erase on I/O failure, on use of a
   --  closed or failed device, and by Read or Write past Last_Block.

   Image_Bytes : constant Long_Integer :=
     Long_Integer
       (Long_Long_Integer (Blocks) * Long_Long_Integer (Block_Size));

   procedure Open (Path : String; Result : out Open_Result);
   --  Opens Path, creating it as an erased image if it does not exist.
   --  An existing file shorter than Image_Bytes (a crash while it was
   --  being created) is extended with 16#FF# only when its header is
   --  erased or valid for this instance. Incompatible files are untouched.
   --  On Ok the file is locked and everything this call wrote is
   --  durable. Linux also confirms the containing directory entry;
   --  Windows leaves that entry to the file system's journal.

   procedure Close;
   --  Releases the file and the lock. No Sync: anything not synced may
   --  be lost, exactly as on power loss. Safe to repeat. Clears a
   --  failed state.

   function Is_Open return Boolean;

   function Has_Failed return Boolean;

   procedure Read (Index : Block_Index; Data : out Block);
   --  The last block written at Index (durable or not).

   procedure Write (Index : Block_Index; Data : Block);

   procedure Sync;
   --  Returns only when every earlier Write is on stable storage.

   procedure Read
     (Index : Block_Index; Data : out Block; Result : out Device_Result);
   procedure Write
     (Index : Block_Index; Data : Block; Result : out Device_Result);
   procedure Sync (Result : out Device_Result);
   --  Result-bearing device operations for Store and Log. Failed may
   --  follow a partial write; it does not promise unchanged storage.

   procedure Erase;
   --  Every block to 16#FF#, then Sync. Destroys the store in the file.

end Legder.File_Device;
