--  Fundamental types for the block device, log, and bounded store.

package Legder with SPARK_Mode, Pure is

   type Byte is mod 2 ** 8 with Size => 8;

   type Byte_Array is array (Natural range <>) of Byte with Pack;

   Block_Size : constant := 512;
   --  A record never spans a block.

   subtype Block_Offset is Natural range 0 .. Block_Size - 1;
   subtype Block is Byte_Array (Block_Offset);

   Max_Blocks : constant := 4096;

   type Block_Index is range 0 .. Max_Blocks - 1;

   Magic : constant := 16#4C444752#;
   --  "LDGR". Serialized little-endian, so the on-disk bytes are
   --  52 47 44 4C. Records carry no magic of their own.

   subtype Key_Size is Natural range 1 .. 255;
   subtype Value_Size is Natural range 1 .. 65_535;

   Record_Overhead : constant := 13;

   Max_Key   : constant := 32;
   Max_Value : constant := 256;

   function Fits_In_Block (K : Key_Size; V : Value_Size) return Boolean is
     (K <= Max_Key and then V <= Max_Value
      and then Record_Overhead + K + V <= Block_Size);

   type Device_Result is (Success, Failed);
   type Update_Result is (Applied, No_Space, Closed, Storage_Failure);
   type Open_Status is
     (Opened, Bad_Header, Bad_Version, Wrong_Sizes, Capacity_Exceeded,
      Storage_Failure);

   subtype Key_Length   is Natural range 0 .. Max_Key;
   subtype Value_Length is Natural range 0 .. Max_Value;

   type Key is record
      Length : Key_Length := 0;
      Bytes  : Byte_Array (1 .. Max_Key) := [others => 0];
   end record;

   type Value is record
      Length : Value_Length := 0;
      Bytes  : Byte_Array (1 .. Max_Value) := [others => 0];
   end record;

   function "=" (L, R : Key) return Boolean is
     (L.Length = R.Length
      and then (for all I in 1 .. L.Length => L.Bytes (I) = R.Bytes (I)));
   --  Keys compare on their live bytes only; padding is ignored.

   function Same (L, R : Value) return Boolean is
     (L.Length = R.Length
      and then (for all I in 1 .. L.Length => L.Bytes (I) = R.Bytes (I)));

   type Sequence is mod 2 ** 64;
   --  Every committed record carries the next sequence number. Two
   --  records are adjacent in the log if and only if their sequences
   --  are consecutive. That is what makes torn and stale blocks
   --  detectable: recovery stops at the first gap.

   type CRC32 is mod 2 ** 32;

   function CRC (Data : Byte_Array) return CRC32
     with Global => null;
   --  CRC-32 (IEEE 802.3, reflected, init and final xor 16#FFFFFFFF#),
   --  implemented table-free.

end Legder;
