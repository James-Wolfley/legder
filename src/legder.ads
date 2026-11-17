--  Fundamental types for the block device, log, and bounded store.

generic
   K_Size : Positive := 32;
   V_Size : Positive := 256;
package Legder with SPARK_Mode, Pure is

   type Byte is mod 2 ** 8 with Size => 8;

   type Byte_Array is array (Natural range <>) of Byte with Pack;

   subtype Key_Size is Natural range 1 .. 255;
   subtype Value_Size is Natural range 1 .. 65_535;
   Valid_K : constant Key_Size := K_Size;
   Valid_V : constant Value_Size := V_Size;
   Record_Overhead : constant := 13;
   Block_Size : constant Positive := Valid_K + Valid_V + Record_Overhead;

   subtype Block_Offset is Natural range 0 .. Block_Size - 1;
   subtype Block is Byte_Array (Block_Offset);

   Max_Blocks : constant := 4096;

   type Block_Index is range 0 .. Max_Blocks - 1;

   Magic : constant := 16#4C444752#;
   --  "LDGR". Serialized little-endian, so the on-disk bytes are
   --  52 47 44 4C. Records carry no magic of their own.

   type Device_Result is (Success, Failed);
   type Update_Result is (Applied, No_Space, Closed, Storage_Failure);
   type Open_Status is
     (Opened, Bad_Header, Bad_Version, Wrong_Sizes, Capacity_Exceeded,
      Storage_Failure);

   type Key is new Byte_Array (1 .. Valid_K)
     with Pack, Default_Component_Value => 0;
   type Value is new Byte_Array (1 .. Valid_V)
     with Pack, Default_Component_Value => 0;

   type Sequence is mod 2 ** 64;
   type Op_Kind is (Put, Delete);

   type Log_Record is record
      Seq  : Sequence := 0;
      Kind : Op_Kind := Put;
      K    : Key;
      V    : Value;
   end record;

   type CRC32 is mod 2 ** 32;

   function CRC (Data : Byte_Array) return CRC32
     with Global => null;
   --  CRC-32 (IEEE 802.3, reflected, init and final xor 16#FFFFFFFF#),
   --  implemented table-free.

end Legder;
