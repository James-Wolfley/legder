--  A block device in memory, with crash injection.

generic
   Blocks : Positive := 256;
package Legder.RAM_Device with SPARK_Mode is

   subtype Block_Total is Positive range 1 .. Max_Blocks;
   Valid_Blocks : constant Block_Total := Blocks;
   Last_Block : constant Block_Index := Block_Index (Valid_Blocks - 1);

   procedure Read  (Index : Block_Index; Data : out Block; Result : out Device_Result);
   procedure Write (Index : Block_Index; Data : Block; Result : out Device_Result);
   procedure Sync (Result : out Device_Result);

   procedure Erase;

   procedure Tear_Next_Write;
   procedure Drop_Unsynced;

   function Writes return Natural;
   function Syncs  return Natural;

end Legder.RAM_Device;
