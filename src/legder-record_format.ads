--  The on-disk record: kind, sequence, key, value, CRC. No magic and
--  no lengths: the store header supplies K and V, and every record
--  carries exactly K + V payload bytes.
--
--    offset      size  field
--         0         1  Kind      0 = Put, 1 = Delete
--         1         8  Sequence  little-endian
--         9         K  Key
--     9 + K         V  Value     all zero when Kind = Delete
--   9 + K + V       4  CRC-32 of the bytes before it, little-endian
--
generic
package Legder.Record_Format with SPARK_Mode is

   procedure Encode (R : Log_Record; B : out Block)
     with Global => null;

   procedure Decode (B : Block; R : out Log_Record; Valid : out Boolean)
     with Global => null;
   --  Valid = True only when the kind is known, the CRC matches, and,
   --  for a Delete, the value bytes are zero. When Valid = False, R is
   --  unspecified.

end Legder.Record_Format;
