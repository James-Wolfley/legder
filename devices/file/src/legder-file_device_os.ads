--  Operating-system services for Legder.File_Device: a flush that
--  reaches stable storage, a non-blocking exclusive lock, a directory
--  flush, and positional transfers.
--
--  Only Linux and Windows bodies exist. legder_file_device.gpr selects
--  src/linux or src/windows from LEGDER_OS; any other value selects a
--  body that fails to compile.

with GNAT.OS_Lib;
with System;

package Legder.File_Device_OS with SPARK_Mode => Off is

   type Lock_Result is
     (Locked,   --  this descriptor now holds the exclusive lock
      Busy,     --  another open descriptor holds it
      Failed);  --  the lock could not be attempted

   function File_Sync (FD : GNAT.OS_Lib.File_Descriptor) return Boolean;
   --  True once every earlier write to FD is on stable storage.

   function Lock (FD : GNAT.OS_Lib.File_Descriptor) return Lock_Result;
   --  Non-blocking exclusive lock on FD, released when FD is closed.

   function Sync_Directory (Path : String) return Boolean;
   --  True once the entries of directory Path are confirmed durable.
   --  Windows has no such barrier; see the Windows body.

   function Read_At
     (FD     : GNAT.OS_Lib.File_Descriptor;
      Buffer : System.Address;
      Length : Natural;
      Offset : Long_Integer) return Integer;
   --  Reads Length bytes at Offset. Returns the count read (0 at EOF),
   --  or -1 on error.

   function Write_At
     (FD     : GNAT.OS_Lib.File_Descriptor;
      Buffer : System.Address;
      Length : Natural;
      Offset : Long_Integer) return Integer;
   --  Writes Length bytes at Offset. Returns the count written, or -1.

end Legder.File_Device_OS;
