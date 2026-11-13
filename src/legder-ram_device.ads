--  A block device in memory, with crash injection.

package Legder.RAM_Device with SPARK_Mode is

   Block_Count : constant Block_Index := 255;  --  256 blocks, 128 KiB

   procedure Read  (Index : Block_Index; Data : out Block; Result : out Device_Result);
   procedure Write (Index : Block_Index; Data : Block; Result : out Device_Result);
   procedure Sync (Result : out Device_Result);

   procedure Erase;

   procedure Tear_Next_Write;
   procedure Drop_Unsynced;

   function Writes return Natural;
   function Syncs  return Natural;

end Legder.RAM_Device;
