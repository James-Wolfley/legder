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
--  The record starts at offset 0 of a block and never spans two, so a
--  partial write corrupts at most one record. Decode is total: Valid =
--  False for anything that is not a record.
--
--  PROOF TARGET
--    R1  Encode then Decode returns Seq, Kind and K, and V for a Put.
--        A Delete's V is not serialized and comes back zeroed.
--    R2  Decode never reads outside the block (index safety).
--    R3  A block that Decodes as Valid matches Encode's output up to
--        the CRC, up to CRC collision.  (Documentation: CRC is not a
--        proof.)

package Legder.Record_Format with SPARK_Mode is

   type Op_Kind is (Put, Delete);

   type Log_Record is record
      Seq  : Sequence := 0;
      Kind : Op_Kind  := Put;
      K    : Key;
      V    : Value;   --  ignored when Kind = Delete
   end record;

   procedure Encode (R : Log_Record; K_Size : Key_Size; V_Size : Value_Size; B : out Block)
     with Global => null,
          Pre  => Fits_In_Block (K_Size, V_Size)
                  and then R.K.Length = K_Size
                  and then (if R.Kind = Put then R.V.Length = V_Size);

   procedure Decode (B : Block; K_Size : Key_Size; V_Size : Value_Size;
                     R : out Log_Record; Valid : out Boolean)
     with Global => null,
          Pre  => Fits_In_Block (K_Size, V_Size);
   --  Valid = True only when the kind is known, the CRC matches, and,
   --  for a Delete, the value bytes are zero. When Valid = False, R is
   --  unspecified.

end Legder.Record_Format;
