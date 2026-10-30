--  A block device in memory, with crash injection.
--
--  This is the test double for every other device. Besides Read /
--  Write / Sync it can simulate the fault model the log is designed
--  for:
--    * Tear_Next_Write: the next Write lands with its front half
--      replaced by garbage, as a power loss mid-record would leave it.
--    * Drop_Unsynced: forget every Write since the last Sync, as a
--      power loss between Write and Sync would.
--  The showcase and the tests use these to check that Open recovers
--  exactly the committed prefix. A real device gets neither.

package Legder.RAM_Device with SPARK_Mode is

   Block_Count : constant Block_Index := 255;  --  256 blocks, 128 KiB

   procedure Read  (Index : Block_Index; Data : out Block);
   procedure Write (Index : Block_Index; Data : Block);
   procedure Sync;

   procedure Erase;
   --  All blocks to 16#FF#, like fresh flash.

   procedure Tear_Next_Write;
   procedure Drop_Unsynced;

   function Writes return Natural;
   function Syncs  return Natural;

end Legder.RAM_Device;
