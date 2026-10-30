--  Unit tests. Plain Ada, no framework, non-zero exit on failure.
--  One critical case per contract; add more when a bug needs one.

with Ada.Assertions;        use Ada.Assertions;
with Ada.Command_Line;
with Ada.Text_IO;           use Ada.Text_IO;
with Legder;                use Legder;
with Legder.Record_Format;  use Legder.Record_Format;
with Legder.RAM_Device;
with Legder.Log;
with Legder.Store;
with Legder.Header;         use Legder.Header;

procedure Tests is

   package Dev renames Legder.RAM_Device;

   K_Bytes : constant Key_Size   := 8;
   V_Bytes : constant Value_Size := 8;

   package L is new Legder.Log
     (K_Bytes, V_Bytes, Dev.Block_Count, Dev.Read, Dev.Write, Dev.Sync);
   package KV is new Legder.Store
     (K_Bytes, V_Bytes, Dev.Block_Count, Dev.Read, Dev.Write, Dev.Sync);

   Failures : Natural := 0;

   procedure Check (Name : String; Cond : Boolean) is
   begin
      Put_Line ((if Cond then "PASS  " else "FAIL  ") & Name);
      if not Cond then Failures := Failures + 1; end if;
   end Check;

   --  Keys and values are fixed width: zero padded, padding included.
   function K (S : String) return Key is
      R : Key;
   begin
      R.Length := K_Bytes;
      for I in 1 .. K_Bytes loop
         R.Bytes (I) :=
           (if I <= S'Length then Byte (Character'Pos (S (S'First + I - 1))) else 0);
      end loop;
      return R;
   end K;

   function V (S : String) return Value is
      R : Value;
   begin
      R.Length := V_Bytes;
      for I in 1 .. V_Bytes loop
         R.Bytes (I) :=
           (if I <= S'Length then Byte (Character'Pos (S (S'First + I - 1))) else 0);
      end loop;
      return R;
   end V;

   function All_Zero (X : Value) return Boolean is
     (for all I in 1 .. X.Length => X.Bytes (I) = 0);

   --  A valid header block at the current version.
   procedure Header_Block (KS : Key_Size; VS : Value_Size; B : out Block) is
   begin
      Legder.Header.Encode
        ((Version => Legder.Header.Current_Version, K => KS, V => VS), B);
   end Header_Block;

   --  Little-endian CRC-32 of the bytes before Off.
   procedure Put_CRC (B : in out Block; Off : Block_Offset) is
      Sum : CRC32 := CRC (B (0 .. Off - 1));
   begin
      for I in 0 .. 3 loop
         B (Off + I) := Byte (Sum and 16#FF#);
         Sum := Sum / 256;
      end loop;
   end Put_CRC;

   ---------------------------------------------------------------------

   procedure Test_CRC is
      Check_Str : constant Byte_Array (1 .. 9) :=
        [16#31#, 16#32#, 16#33#, 16#34#, 16#35#, 16#36#, 16#37#, 16#38#, 16#39#];  --  "123456789"
   begin
      Check ("CRC '123456789' = CBF43926", CRC (Check_Str) = 16#CBF43926#);
   end Test_CRC;

   procedure Test_Header is
      S           : L.State;
      N           : Natural;
      St          : Open_Status;
      W           : Natural;
      B           : Block;
      H           : Legder.Header.Header;
      HS          : Legder.Header.Status;
      Saw_Version : Boolean;
      Want        : constant Legder.Header.Header :=
        (Version => Legder.Header.Current_Version, K => K_Bytes, V => V_Bytes);
   begin
      --  The twelve bytes on disk are the format; decode must agree.
      Legder.Header.Encode (Want, B);
      Legder.Header.Decode (B, H, HS);
      declare
         C : Block := B;
      begin
         C (8 .. 11) := [others => 0];
         Put_CRC (C, 8);
         Check ("header layout and round trip",
                B (0) = 16#52# and B (1) = 16#47#
                and B (2) = 16#44# and B (3) = 16#4C#
                and B (4) = Byte (Legder.Header.Current_Version)
                and B (5) = Byte (K_Bytes)
                and B (6) = Byte (V_Bytes) and B (7) = 0
                and (for all I in 12 .. Block_Size - 1 => B (I) = 0)
                and C = B
                and HS = Legder.Header.Ok
                and H.Version = Want.Version
                and H.K = Want.K and H.V = Want.V);
      end;

      --  A damaged header is refused and nothing is overwritten.
      Header_Block (K_Bytes, V_Bytes, B);
      Dev.Erase;
      Dev.Write (0, B);
      Dev.Sync;
      Dev.Read (0, B);
      B (5) := B (5) xor 1;
      Dev.Write (0, B);
      Dev.Sync;
      W := Dev.Writes;
      L.Open (S, N, St);
      Check ("damaged header refused, nothing written",
             St = Bad_Header and not S.Opened and Dev.Writes = W);

      --  Headers from another schema: a newer version, another layout.
      declare
         B2 : Block;
      begin
         Header_Block (K_Bytes, V_Bytes, B2);
         B2 (4) := 2;
         Put_CRC (B2, 8);
         Dev.Erase;
         Dev.Write (0, B2);
         Dev.Sync;
         L.Open (S, N, St);
         Saw_Version := St = Bad_Version;

         Header_Block (K_Bytes + 1, V_Bytes, B2);
         Dev.Erase;
         Dev.Write (0, B2);
         Dev.Sync;
         L.Open (S, N, St);
         Check ("foreign header refused", Saw_Version and St = Wrong_Sizes);
      end;
   end Test_Header;

   procedure Test_Record is
      R, D       : Log_Record;
      B          : Block;
      Valid      : Boolean;
      Round_Trip : Boolean := True;
      Rejected   : Boolean := True;
   begin
      R := (Seq => 42, Kind => Put, K => K ("key"), V => V ("value"));
      Encode (R, K_Bytes, V_Bytes, B);
      Decode (B, K_Bytes, V_Bytes, D, Valid);
      Round_Trip := Valid and D.Seq = 42 and D.Kind = Put
                    and D.K = K ("key") and Same (D.V, V ("value"));

      R := (Seq => 1, Kind => Delete, K => K ("gone"), V => V ("ignored"));
      Encode (R, K_Bytes, V_Bytes, B);
      Decode (B, K_Bytes, V_Bytes, D, Valid);
      Round_Trip := Round_Trip and Valid and D.Kind = Delete
                    and D.K = K ("gone") and All_Zero (D.V);
      Check ("record round trip", Round_Trip);

      --  A torn record, erased flash, a zeroed block, and a Delete that
      --  carries a payload must all be rejected.
      Encode ((Seq => 7, Kind => Put, K => K ("a"), V => V ("1")),
              K_Bytes, V_Bytes, B);
      declare
         Bad : Block := B;
      begin
         Bad (2) := Bad (2) xor 1;
         Decode (Bad, K_Bytes, V_Bytes, D, Valid);
         Rejected := Rejected and not Valid;
      end;

      B := [others => 16#FF#];
      Decode (B, K_Bytes, V_Bytes, D, Valid);
      Rejected := Rejected and not Valid;

      B := [others => 0];
      Decode (B, K_Bytes, V_Bytes, D, Valid);
      Rejected := Rejected and not Valid;

      declare
         Bad : Block;
         Val : constant Block_Offset := 9 + K_Bytes;
      begin
         Encode ((Seq => 1, Kind => Delete, K => K ("gone"), V => V ("x")),
                 K_Bytes, V_Bytes, Bad);
         Bad (Val) := 1;
         Put_CRC (Bad, 9 + K_Bytes + V_Bytes);
         Decode (Bad, K_Bytes, V_Bytes, D, Valid);
         Check ("malformed blocks rejected", Rejected and not Valid);
      end;
   end Test_Record;

   procedure Test_Log is
      S    : L.State;
      N    : Natural;
      St   : Open_Status;
      OK   : Boolean;
      Torn : Boolean;
   begin
      Dev.Erase;
      L.Open (S, N, St);
      L.Append (S, Put, K ("a"), V ("1"), OK);
      L.Append (S, Put, K ("b"), V ("2"), OK);
      L.Append (S, Put, K ("c"), V ("3"), OK);
      L.Open (S, N, St);
      Check ("appends recover",
             N = 3 and S.Head = 4 and S.Last_Seq = 3 and Dev.Syncs = 4);

      --  A torn write is not recovered, the next append reuses its
      --  block, and a stale record beyond it is not adopted.
      Dev.Tear_Next_Write;
      L.Append (S, Put, K ("d"), V ("4"), OK);
      L.Open (S, N, St);
      Torn := N = 3 and S.Head = 4;

      L.Append (S, Put, K ("e"), V ("5"), OK);
      declare
         B : Block;
         R : constant Log_Record :=
           (Seq => 99, Kind => Put, K => K ("stale"), V => V ("x"));
      begin
         Encode (R, K_Bytes, V_Bytes, B);
         Dev.Write (5, B);
         Dev.Sync;
      end;
      L.Open (S, N, St);
      Check ("torn and stale blocks stop recovery",
             Torn and N = 4 and S.Last_Seq = 4);
   end Test_Log;

   procedure Test_Store is
      N     : Natural;
      St    : Open_Status;
      OK    : Boolean;
      Got   : Value;
      Found : Boolean;
      Has_X : Boolean;
   begin
      Dev.Erase;
      declare
         S : KV.Store;
      begin
         KV.Open (S, N, St);
         KV.Put (S, K ("x"), V ("1"), OK);
         KV.Put (S, K ("y"), V ("2"), OK);
         KV.Put (S, K ("x"), V ("3"), OK);
         KV.Delete (S, K ("y"), OK);
         KV.Get (S, K ("x"), Got, Found);
         Has_X := Found and Same (Got, V ("3"));
         KV.Get (S, K ("y"), Got, Found);
         Check ("store: overwrite and delete",
                St = Opened and Has_X and not Found and KV.Count (S) = 1);
      end;
      declare
         S : KV.Store;
      begin
         KV.Open (S, N, St);
         KV.Get (S, K ("x"), Got, Found);
         Check ("store: reopen replays the log",
                N = 4 and Found and Same (Got, V ("3")) and KV.Count (S) = 1);
      end;
   end Test_Store;

   procedure Test_Lengths is
      S       : KV.Store;
      N       : Natural;
      St      : Open_Status;
      OK      : Boolean;
      W       : Natural;
      Short   : Key   := K ("a");
      SV      : Value := V ("v");
      Refused : Boolean := True;
   begin
      Dev.Erase;
      KV.Open (S, N, St);
      Short.Length := K_Bytes - 1;
      SV.Length    := V_Bytes - 1;
      W := Dev.Writes;

      begin
         KV.Put (S, Short, V ("1"), OK);
         Refused := False;
      exception
         when Assertion_Error =>
            null;
      end;
      begin
         KV.Put (S, K ("a"), SV, OK);
         Refused := False;
      exception
         when Assertion_Error =>
            null;
      end;
      Check ("wrong key or value length refused", Refused and Dev.Writes = W);
   end Test_Lengths;

   procedure Test_Capacity is
      N  : Natural;
      St : Open_Status;
      OK : Boolean;
      S  : KV.Store;
      W  : Natural;
   begin
      Dev.Erase;
      KV.Open (S, N, St);
      for I in 1 .. KV.Max_Entries loop
         KV.Put (S, K ("k" & I'Image), V ("v"), OK);
         exit when not OK;
      end loop;
      W := Dev.Writes;
      KV.Put (S, K ("one more"), V ("v"), OK);
      Check ("full store refuses without writing",
             not OK and KV.Count (S) = 255 and Dev.Writes = W);
   end Test_Capacity;

begin
   Test_CRC;
   Test_Header;
   Test_Record;
   Test_Log;
   Test_Store;
   Test_Lengths;
   Test_Capacity;
   New_Line;
   if Failures = 0 then
      Put_Line ("all tests passed");
   else
      Put_Line (Failures'Image & " failure(s)");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Tests;
