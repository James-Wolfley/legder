package body Legder.Record_Format with SPARK_Mode is

   Off_Kind : constant := 0;
   Off_Seq  : constant := 1;
   Off_Key  : constant := 9;

   function Off_Value (K_Size : Key_Size) return Block_Offset is
     (Block_Offset (Off_Key + K_Size));

   function Off_CRC (K_Size : Key_Size; V_Size : Value_Size) return Block_Offset is
     (Block_Offset (Off_Key + K_Size + V_Size))
     with Pre => Off_Key + K_Size + V_Size <= Block_Size - 4;
   --  The CRC trails the payload, so its input is one unbroken range.

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

   ------------
   -- Encode --
   ------------

   procedure Encode (R : Log_Record; K_Size : Key_Size; V_Size : Value_Size; B : out Block) is
      CRC_At : constant Block_Offset := Off_CRC (K_Size, V_Size);
      Val_At : constant Block_Offset := Off_Value (K_Size);
   begin
      B := [others => 0];
      B (Off_Kind) := (case R.Kind is when Put => 0, when Delete => 1);
      Put_U64 (B, Off_Seq, R.Seq);
      for I in 1 .. K_Size loop
         B (Off_Key + I - 1) := R.K.Bytes (I);
      end loop;
      if R.Kind = Put then
         for I in 1 .. V_Size loop
            B (Val_At + I - 1) := R.V.Bytes (I);
         end loop;
      end if;
      Put_U32 (B, CRC_At, CRC (B (0 .. CRC_At - 1)));
   end Encode;

   ------------
   -- Decode --
   ------------

   procedure Decode (B : Block; K_Size : Key_Size; V_Size : Value_Size;
                     R : out Log_Record; Valid : out Boolean) is
      CRC_At : constant Block_Offset := Off_CRC (K_Size, V_Size);
      Val_At : constant Block_Offset := Off_Value (K_Size);
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

      R.K.Length := K_Size;
      for I in 1 .. K_Size loop
         R.K.Bytes (I) := B (Off_Key + I - 1);
      end loop;

      R.V.Length := V_Size;
      if R.Kind = Put then
         for I in 1 .. V_Size loop
            R.V.Bytes (I) := B (Val_At + I - 1);
         end loop;
      elsif (for some I in 1 .. V_Size => B (Val_At + I - 1) /= 0) then
         --  A Delete's payload is V zero bytes.
         return;
      end if;

      Valid := True;
   end Decode;

end Legder.Record_Format;
