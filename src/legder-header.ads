--  The store header: block 0, written once when a store is initialized.
--  The only place K and V appear; every record is read in that context.
--
--    offset  size  field
--         0     4  Magic      16#4C444752#, little-endian
--         4     1  Version    schema version, 1
--         5     1  Key size   K, 1 .. 255
--         6     2  Value size V, 1 .. 65_535, little-endian
--         8     4  CRC        CRC-32 of bytes 0 .. 7, little-endian
--
--  All little-endian: a hex dump of the magic reads "RGDL".
--
--  PROOF TARGET
--    H1  Decode (Encode (H)) = H with Result = Ok for every H that
--        Encode accepts.
--    H2  A block that Decodes as Ok holds a K and V that Encode could
--        have written (up to CRC collision).

package Legder.Header with SPARK_Mode is

   Current_Version : constant := 1;

   subtype Version_Number is Natural range 0 .. 255;
   --  One byte on disk.

   type Status is (Ok, Bad_Header, Unsupported_Version);
   --  Bad_Header covers a bad magic, checksum or size.

   type Header is record
      Version : Version_Number := Current_Version;
      K       : Key_Size       := Key_Size'First;
      V       : Value_Size     := Value_Size'First;
   end record;
   --  Decode fills Version on every path; K and V only when Result = Ok.

   procedure Encode (H : Header; B : out Block)
     with Global => null,
          Pre => H.Version = Current_Version
                 and then Fits_In_Block (H.K, H.V);

   procedure Decode (B : Block; H : out Header; Result : out Status)
     with Global => null,
          Post => (if Result = Ok
                   then H.Version = Current_Version
                        and then Fits_In_Block (H.K, H.V));
   --  The rest of the block is zero after Encode and ignored by Decode.

end Legder.Header;
