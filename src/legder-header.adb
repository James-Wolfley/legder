package body Legder.Header with SPARK_Mode is

   Off_Magic      : constant := 0;
   Off_Version    : constant := 4;
   Off_Key_Size   : constant := 5;
   Off_Value_Size : constant := 6;
   Off_CRC        : constant := 8;

   procedure Put_U16 (B : in out Block; At_Off : Block_Offset; V : Natural)
     with Pre => At_Off <= Block_Size - 2 and then V < 2 ** 16;
   function Get_U16 (B : Block; At_Off : Block_Offset) return Natural
     with Pre => At_Off <= Block_Size - 2;
   procedure Put_U32 (B : in out Block; At_Off : Block_Offset; V : CRC32)
     with Pre => At_Off <= Block_Size - 4;
   function Get_U32 (B : Block; At_Off : Block_Offset) return CRC32
     with Pre => At_Off <= Block_Size - 4;

   procedure Put_U16 (B : in out Block; At_Off : Block_Offset; V : Natural) is
      X : Natural := V;
   begin
      for I in 0 .. 1 loop
         B (At_Off + I) := Byte (X mod 256);
         X := X / 256;
      end loop;
   end Put_U16;

   function Get_U16 (B : Block; At_Off : Block_Offset) return Natural is
      X : Natural := 0;
   begin
      for I in reverse 0 .. 1 loop
         X := X * 256 + Natural (B (At_Off + I));
      end loop;
      return X;
   end Get_U16;

   procedure Put_U32 (B : in out Block; At_Off : Block_Offset; V : CRC32) is
      X : CRC32 := V;
   begin
      for I in 0 .. 3 loop
         B (At_Off + I) := Byte (X and 16#FF#);
         X := X / 256;
      end loop;
   end Put_U32;

   function Get_U32 (B : Block; At_Off : Block_Offset) return CRC32 is
      X : CRC32 := 0;
   begin
      for I in reverse 0 .. 3 loop
         X := X * 256 + CRC32 (B (At_Off + I));
      end loop;
      return X;
   end Get_U32;

   ------------
   -- Encode --
   ------------

   procedure Encode (H : Header; B : out Block) is
   begin
      B := [others => 0];
      Put_U32 (B, Off_Magic, Magic);
      B (Off_Version)  := Byte (H.Version);
      B (Off_Key_Size) := Byte (H.K);
      Put_U16 (B, Off_Value_Size, H.V);
      Put_U32 (B, Off_CRC, CRC (B (Off_Magic .. Off_CRC - 1)));
   end Encode;

   ------------
   -- Decode --
   ------------

   procedure Decode (B : Block; H : out Header; Result : out Status) is
      Found_K : constant Natural := Natural (B (Off_Key_Size));
      Found_V : constant Natural := Get_U16 (B, Off_Value_Size);
      --  Magic and checksum first: until both hold, the version byte
      --  and the sizes are noise, not evidence.
      Intact  : constant Boolean :=
        Get_U32 (B, Off_Magic) = Magic
        and then Get_U32 (B, Off_CRC) = CRC (B (Off_Magic .. Off_CRC - 1));
   begin
      H := (others => <>);
      --  The version byte is reported even when nothing else is valid.
      H.Version := Natural (B (Off_Version));

      if not Intact then
         Result := Bad_Header;
      elsif H.Version /= Current_Version then
         Result := Unsupported_Version;
      elsif Found_K not in Key_Size
        or else Found_V not in Value_Size
        or else not Fits_In_Block (Found_K, Found_V)
      then
         Result := Bad_Header;
      else
         H.K := Found_K;
         H.V := Found_V;
         Result := Ok;
      end if;
   end Decode;

end Legder.Header;
