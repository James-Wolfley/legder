package body Legder.Record_Format with SPARK_Mode is

   Off_Kind : constant := 0;
   Off_Seq  : constant := 1;
   Off_Key  : constant := 9;

   Off_Value : constant Block_Offset := Off_Key + Key'Length;
   Off_CRC   : constant Block_Offset := Off_Value + Value'Length;

   procedure Put_U32 (B : in out Block; At_Off : Block_Offset; V : CRC32)
     with Pre => At_Off <= Block_Size - 4;
   function Get_U32 (B : Block; At_Off : Block_Offset) return CRC32
     with Pre => At_Off <= Block_Size - 4;
   procedure Put_U64 (B : in out Block; At_Off : Block_Offset; V : Sequence)
     with Pre => At_Off <= Block_Size - 8;
   function Get_U64 (B : Block; At_Off : Block_Offset) return Sequence
     with Pre => At_Off <= Block_Size - 8;

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

   procedure Put_U64 (B : in out Block; At_Off : Block_Offset; V : Sequence) is
      X : Sequence := V;
   begin
      for I in 0 .. 7 loop
         B (At_Off + I) := Byte (X and 16#FF#);
         X := X / 256;
      end loop;
   end Put_U64;

   function Get_U64 (B : Block; At_Off : Block_Offset) return Sequence is
      X : Sequence := 0;
   begin
      for I in reverse 0 .. 7 loop
         X := X * 256 + Sequence (B (At_Off + I));
      end loop;
      return X;
   end Get_U64;

   procedure Encode (R : Log_Record; B : out Block) is
      CRC_At : constant Block_Offset := Off_CRC;
      Val_At : constant Block_Offset := Off_Value;
   begin
      B := [others => 0];
      B (Off_Kind) := (case R.Kind is when Put => 0, when Delete => 1);
      Put_U64 (B, Off_Seq, R.Seq);
      for I in Key'Range loop
         B (Off_Key + I - 1) := R.K (I);
      end loop;
      if R.Kind = Put then
         for I in Value'Range loop
            B (Val_At + I - 1) := R.V (I);
         end loop;
      end if;
      Put_U32 (B, CRC_At, CRC (B (0 .. CRC_At - 1)));
   end Encode;

   procedure Decode (B : Block; R : out Log_Record; Valid : out Boolean) is
      CRC_At : constant Block_Offset := Off_CRC;
      Val_At : constant Block_Offset := Off_Value;
   begin
      R := (others => <>);
      Valid := False;

      if B (Off_Kind) > 1 then
         return;
      end if;

      if Get_U32 (B, CRC_At) /= CRC (B (0 .. CRC_At - 1)) then
         return;
      end if;

      R.Seq  := Get_U64 (B, Off_Seq);
      R.Kind := (if B (Off_Kind) = 0 then Put else Delete);

      for I in Key'Range loop
         R.K (I) := B (Off_Key + I - 1);
      end loop;

      if R.Kind = Put then
         for I in Value'Range loop
            R.V (I) := B (Val_At + I - 1);
         end loop;
      elsif (for some I in Value'Range => B (Val_At + I - 1) /= 0) then
         --  A Delete's payload is V zero bytes.
         return;
      end if;

      Valid := True;
   end Decode;

end Legder.Record_Format;
