--  The showcase: the acceptance test for the project.
--
--  Writes a few keys, then simulates the two crashes the log is built
--  for (a torn block, and a write that never reached the medium),
--  reopens the store, and checks that exactly the committed records
--  survived. The last sections are the application conversion
--  examples: String to K bytes, Integer to V bytes. Exits non-zero if
--  anything is off.

with Ada.Command_Line;
with Ada.Text_IO;       use Ada.Text_IO;
with Interfaces;
with Legder;            use Legder;
with Legder.RAM_Device;
with Legder.Store;

procedure Showcase is

   package Dev renames Legder.RAM_Device;

   K_Bytes : constant Key_Size   := 8;
   V_Bytes : constant Value_Size := 4;

   package KV is new Legder.Store
     (K_Bytes, V_Bytes, Dev.Block_Count, Dev.Read, Dev.Write, Dev.Sync);

   --  Signed 32-bit, two's complement, little-endian: the integer
   --  example. V is 4, so the codec occupies exactly V bytes.
   subtype Int32 is Interfaces.Integer_32;

   use type Interfaces.Integer_32;
   use type Interfaces.Integer_64;
   use type Interfaces.Unsigned_32;

   pragma Compile_Time_Error (V_Bytes /= 4, "the integer codec needs V = 4");

   Int32_First : constant Interfaces.Integer_64 :=
     Interfaces.Integer_64 (Int32'First);
   Int32_Last  : constant Interfaces.Integer_64 :=
     Interfaces.Integer_64 (Int32'Last);

   --  Out-of-range input is refused here, not wrapped.
   function Fits_Int32 (X : Interfaces.Integer_64) return Boolean is
     (X >= Int32_First and then X <= Int32_Last);

   function Int_Value (X : Int32) return Value is
      R : Value;
      --  Two's complement is the signed value mod 2**32.
      U : Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32 (Interfaces.Integer_64 (X) mod 2 ** 32);
   begin
      R.Length := V_Bytes;
      for I in 1 .. V_Bytes loop
         R.Bytes (I) := Byte (U and 16#FF#);
         U := U / 256;
      end loop;
      return R;
   end Int_Value;

   function Value_Int (X : Value) return Int32 is
      U : Interfaces.Unsigned_32 := 0;
      S : Interfaces.Integer_64;
   begin
      for I in reverse 1 .. V_Bytes loop
         U := U * 256 + Interfaces.Unsigned_32 (X.Bytes (I));
      end loop;
      S := Interfaces.Integer_64 (U);
      if S >= 2 ** 31 then
         S := S - 2 ** 32;   --  sign extension
      end if;
      return Int32 (S);
   end Value_Int;

   --  Keys and values are fixed width: zero padded, padding included.
   --  Overlong input is refused; the store never truncates for you.
   function K (S : String) return Key is
      R : Key;
   begin
      if S'Length > K_Bytes then
         raise Constraint_Error with "key longer than" & K_Bytes'Image & " bytes";
      end if;
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
      if S'Length > V_Bytes then
         raise Constraint_Error with "value longer than" & V_Bytes'Image & " bytes";
      end if;
      R.Length := V_Bytes;
      for I in 1 .. V_Bytes loop
         R.Bytes (I) :=
           (if I <= S'Length then Byte (Character'Pos (S (S'First + I - 1))) else 0);
      end loop;
      return R;
   end V;

   --  Drop the zero padding before printing.
   function Img (X : Value) return String is
      Last : Natural := X.Length;
   begin
      while Last > 0 and then X.Bytes (Last) = 0 loop
         Last := Last - 1;
      end loop;
      return Result : String (1 .. Last) do
         for I in Result'Range loop
            Result (I) := Character'Val (X.Bytes (I));
         end loop;
      end return;
   end Img;

   Failed : Boolean := False;

   procedure Check (Name : String; Cond : Boolean) is
   begin
      Put_Line ("  " & (if Cond then "ok   " else "FAIL ") & Name);
      if not Cond then
         Failed := True;
      end if;
   end Check;

   procedure Expect (S : KV.Store; Name : String; Want : String; Present : Boolean := True) is
      Got   : Value;
      Found : Boolean;
   begin
      KV.Get (S, K (Name), Got, Found);
      if Found /= Present or else (Found and then Img (Got) /= Want) then
         Put_Line ("  FAIL " & Name & ": found=" & Found'Image
                   & (if Found then " '" & Img (Got) & "'" else "")
                   & " wanted " & (if Present then "'" & Want & "'" else "absent"));
         Failed := True;
      else
         Put_Line ("  ok   " & Name & " = " & (if Present then "'" & Want & "'" else "absent"));
      end if;
   end Expect;

   OK : Boolean;
   N  : Natural;

   --  Every open here expects a healthy store and a known replay count.
   procedure Open (S : out KV.Store; Want : Natural) is
      St : Open_Status;
   begin
      KV.Open (S, N, St);
      Put_Line ("  replayed" & N'Image & " (expect" & Want'Image & ")");
      if St /= Opened or else N /= Want then
         Put_Line ("  FAIL open: status" & Open_Status'Image (St));
         Failed := True;
      end if;
   end Open;

begin
   Dev.Erase;

   Put_Line ("1. fresh device, open");
   declare
      S : KV.Store;
   begin
      Open (S, 0);

      --  Longer than K or V is refused, not cut to fit.
      begin
         KV.Put (S, K ("123456789"), V ("x"), OK);
         Check ("overlong key refused", False);
      exception
         when Constraint_Error =>
            Check ("overlong key refused", True);
      end;
      begin
         KV.Put (S, K ("alpha"), V ("12345"), OK);
         Check ("overlong value refused", False);
      exception
         when Constraint_Error =>
            Check ("overlong value refused", True);
      end;

      KV.Put (S, K ("alpha"), V ("1"), OK);
      KV.Put (S, K ("beta"),  V ("2"), OK);
      KV.Put (S, K ("alpha"), V ("11"), OK);
      KV.Delete (S, K ("beta"), OK);
      KV.Put (S, K ("gamma"), V ("3"), OK);
      Put_Line ("  wrote 5 records, live keys:" & KV.Count (S)'Image);
   end;

   Put_Line ("2. reopen, replay");
   declare
      S : KV.Store;
   begin
      Open (S, 5);
      Expect (S, "alpha", "11");
      Expect (S, "beta", "", Present => False);
      Expect (S, "gamma", "3");

      Put_Line ("3. torn write: next block lands half garbage");
      Dev.Tear_Next_Write;
      KV.Put (S, K ("delta"), V ("4"), OK);
      --  The store believes delta committed. The medium disagrees.
   end;

   Put_Line ("4. reopen after the torn write");
   declare
      S : KV.Store;
   begin
      Open (S, 5);
      Expect (S, "gamma", "3");
      Expect (S, "delta", "", Present => False);

      Put_Line ("5. write after recovery reuses the torn block");
      KV.Put (S, K ("epsilon"), V ("5"), OK);
      Put_Line ("  writes" & Dev.Writes'Image & " syncs" & Dev.Syncs'Image
                & " (one sync per commit, plus the header)");
   end;

   Put_Line ("6. final reopen");
   declare
      S : KV.Store;
   begin
      Open (S, 6);
      Expect (S, "alpha", "11");
      Expect (S, "gamma", "3");
      Expect (S, "epsilon", "5");
      Expect (S, "delta", "", Present => False);
   end;

   Put_Line ("7. integer codec: signed 32-bit, little-endian");
   declare
      V4 : Value;
   begin
      --  Byte order is the format, not the machine.
      V4 := Int_Value (16#12345678#);
      Check ("16#12345678# stored as 78 56 34 12",
             V4.Bytes (1) = 16#78# and then V4.Bytes (2) = 16#56#
             and then V4.Bytes (3) = 16#34# and then V4.Bytes (4) = 16#12#);
      Check ("out of int32 range refused",
             not Fits_Int32 (2 ** 31) and not Fits_Int32 (-(2 ** 31) - 1));
   end;

   Put_Line ("8. integer values through the store");
   declare
      Samples : constant array (1 .. 5) of Int32 :=
        [0, 1, -1, Int32'Last, Int32'First];
   begin
      Dev.Erase;
      declare
         S : KV.Store;
      begin
         Open (S, 0);
         for I in Samples'Range loop
            KV.Put (S, K ("n" & I'Image), Int_Value (Samples (I)), OK);
         end loop;
      end;

      declare
         S     : KV.Store;
         Got   : Value;
         Found : Boolean;
         Exact : Boolean := True;
      begin
         Open (S, Samples'Length);
         for I in Samples'Range loop
            KV.Get (S, K ("n" & I'Image), Got, Found);
            Exact := Exact and then Found and then Value_Int (Got) = Samples (I);
         end loop;
         Check ("integer round trip exact", Exact);
      end;
   end;

   if Failed then
      Put_Line ("SHOWCASE FAILED");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Put_Line ("showcase ok");
   end if;
end Showcase;
