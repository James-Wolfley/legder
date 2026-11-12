--  Tests for Legder.File_Device. Plain Ada, no framework.
--
--    file_device_tests [PARENT]       unit tests in a fresh child of PARENT
--    file_device_tests write PATH     commit Puts forever, print "ack N"
--    file_device_tests check PATH N   reopen after a kill: N acked
--
--  write and check are the halves of crash_test.sh, which kills the
--  writer at a random moment and checks that what reopens is exactly
--  the acknowledged prefix, give or take the one Put in flight.

with Ada.Command_Line;     use Ada.Command_Line;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Text_IO;          use Ada.Text_IO;
with GNAT.OS_Lib;
with Legder;               use Legder;
with Legder.File_Device;
with Legder.Store;

procedure File_Device_Tests is

   K_Bytes : constant Key_Size   := 8;
   V_Bytes : constant Value_Size := 8;

   package Dev  is new Legder.File_Device (Last_Block => 63);
   package Dev2 is new Legder.File_Device (Last_Block => 63);
   package KV   is new Legder.Store (K_Bytes, V_Bytes, Dev.Block_Count, Dev.Read, Dev.Write, Dev.Sync);
   package KV16 is new Legder.Store (K_Bytes, 16, Dev.Block_Count, Dev.Read, Dev.Write, Dev.Sync);

   package Big is new Legder.File_Device (Last_Block => Block_Index'Last);
   package KVB is new Legder.Store (K_Bytes, V_Bytes, Big.Block_Count, Big.Read, Big.Write, Big.Sync);

   use type Dev.Open_Result;
   use type Dev2.Open_Result;
   use type Big.Open_Result;

   Failures : Natural := 0;

   procedure Check (Name : String; Cond : Boolean) is
   begin
      Put_Line ((if Cond then "PASS  " else "FAIL  ") & Name);
      if not Cond then
         Failures := Failures + 1;
      end if;
   end Check;

   function Pad (S : String; N : Positive) return Byte_Array is
     ([for I in 1 .. N =>
         (if I <= S'Length then Byte (Character'Pos (S (S'First + I - 1))) else 0)]);

   function K (S : String) return Key is
     ((Length => K_Bytes, Bytes => Pad (S, Max_Key)));

   function V (S : String) return Value is
     ((Length => V_Bytes, Bytes => Pad (S, Max_Value)));

   function Trim (S : String) return String is
     (if S'Length > 0 and then S (S'First) = ' ' then S (S'First + 1 .. S'Last) else S);

   ---------------------------------------------------------------------
   --  Poking the file behind the device's back
   ---------------------------------------------------------------------

   function Size (Path : String) return Long_Integer is
     (Long_Integer (Ada.Directories.Size (Path)));

   function Slurp (Path : String) return Byte_Array is
      use GNAT.OS_Lib;
      FD  : constant File_Descriptor := Open_Read (Path, Binary);
      Len : constant Natural := Natural (File_Length (FD));
      R   : Byte_Array (0 .. Len - 1);
      N   : Integer := 0;
   begin
      if Len > 0 then
         N := Read (FD, R (0)'Address, Len);
      end if;
      Close (FD);
      pragma Assert (N = Len);
      return R;
   end Slurp;

   procedure Spit (Path : String; Data : Byte_Array) is
      use GNAT.OS_Lib;
      FD : constant File_Descriptor := Create_File (Path, Binary);
      N  : Integer := 0;
   begin
      if Data'Length > 0 then
         N := Write (FD, Data (Data'First)'Address, Data'Length);
      end if;
      Close (FD);
      pragma Assert (N = Data'Length);
   end Spit;

   procedure Tear (Path : String; Index : Block_Index) is
      --  Front half of the block replaced, as an interrupted write.
      Img : Byte_Array := Slurp (Path);
      At0 : constant Natural := Natural (Index) * Block_Size;
   begin
      for I in 0 .. Block_Size / 2 - 1 loop
         Img (At0 + I) := Byte ((I * 7 + 13) mod 256);
      end loop;
      Spit (Path, Img);
   end Tear;

   procedure Truncate (Path : String; Len : Natural) is
      Img : constant Byte_Array := Slurp (Path);
   begin
      Spit (Path, Img (0 .. Len - 1));
   end Truncate;

   function Raises (Op : access procedure) return Boolean is
   begin
      Op.all;
      return False;
   exception
      when Dev.Device_Error =>
         return True;
   end Raises;

   ---------------------------------------------------------------------
   --  Unit tests
   ---------------------------------------------------------------------

   procedure Unit (Dir : String) is
      Path : constant String := Ada.Directories.Compose (Dir, "store.ldgr");
      R    : Dev.Open_Result;
      R2   : Dev2.Open_Result;
      N    : Natural;
      St   : Open_Status;
      OK   : Boolean;
      Got  : Value;
      Fnd  : Boolean;

      function Has (S : KV.Store; Name, Want : String) return Boolean is
      begin
         KV.Get (S, K (Name), Got, Fnd);
         return Fnd and then Same (Got, V (Want));
      end Has;

      function Absent (S : KV.Store; Name : String) return Boolean is
      begin
         KV.Get (S, K (Name), Got, Fnd);
         return not Fnd;
      end Absent;

      procedure Reopen is
      begin
         Dev.Close;
         Dev.Open (Path, R);
      end Reopen;

      procedure Read_Closed is
         B : Block;
      begin
         Dev.Read (0, B);
      end Read_Closed;

      procedure Store_On_Closed is
         S : KV.Store;
      begin
         KV.Open (S, N, St);
      end Store_On_Closed;

      procedure Write_Past_End is
      begin
         Dev.Write (Dev.Block_Count + 1, [others => 0]);
      end Write_Past_End;

   begin
      Put_Line ("-- fresh file");
      Dev.Open (Path, R);
      Check ("new file opens", R = Dev.Ok);
      Check ("new file is full size", Size (Path) = Dev.Image_Bytes);
      Check ("new file is erased", (for all B of Slurp (Path) => B = 16#FF#));
      declare
         S : KV.Store;
      begin
         KV.Open (S, N, St);
         Check ("store opens on it, nothing replayed", St = Opened and then N = 0);
         declare
            Img : constant Byte_Array := Slurp (Path);
         begin
            Check ("header in block 0 reads 52 47 44 4C",
                   Img (0) = 16#52# and then Img (1) = 16#47#
                   and then Img (2) = 16#44# and then Img (3) = 16#4C#);
         end;
         KV.Put (S, K ("a"), V ("1"), OK);
         KV.Put (S, K ("b"), V ("2"), OK);
         KV.Put (S, K ("a"), V ("3"), OK);
         KV.Delete (S, K ("b"), OK);
         Check ("four commits", OK);
      end;

      Put_Line ("-- one writer");
      Dev.Open (Path, R);
      Check ("second Open on an open instance is Already_Open", R = Dev.Already_Open);
      Dev2.Open (Path, R2);
      Check ("another instance on the same file is Locked", R2 = Dev2.Locked);
      Check ("refused open left it closed", not Dev2.Is_Open);

      Put_Line ("-- survives close and reopen");
      Reopen;
      Check ("reopen", R = Dev.Ok);
      declare
         S : KV.Store;
      begin
         KV.Open (S, N, St);
         Check ("replays all four", St = Opened and then N = 4);
         Check ("a = 3", Has (S, "a", "3"));
         Check ("b deleted", Absent (S, "b"));
      end;
      Dev.Close;
      Dev2.Open (Path, R2);
      Check ("lock released by Close", R2 = Dev2.Ok);
      Dev2.Close;

      Put_Line ("-- torn last block");
      Tear (Path, 4);
      Dev.Open (Path, R);
      declare
         S : KV.Store;
      begin
         KV.Open (S, N, St);
         Check ("torn delete is dropped", St = Opened and then N = 3);
         Check ("b back to 2", Has (S, "b", "2"));
         KV.Put (S, K ("c"), V ("4"), OK);
         Check ("next commit reuses the torn block", OK);
      end;
      Reopen;
      declare
         S : KV.Store;
      begin
         KV.Open (S, N, St);
         Check ("four again, c present", N = 4 and then Has (S, "c", "4"));
      end;
      Dev.Close;

      Put_Line ("-- short file (crash while extending)");
      Truncate (Path, 4 * Block_Size + 10);   --  inside the 29-byte record
      Dev.Open (Path, R);
      Check ("short file opens", R = Dev.Ok);
      Check ("and is extended to full size", Size (Path) = Dev.Image_Bytes);
      declare
         S : KV.Store;
      begin
         KV.Open (S, N, St);
         Check ("partial block is torn, prefix kept",
                St = Opened and then N = 3 and then Absent (S, "c"));
      end;

      Put_Line ("-- wrong K/V for this file");
      declare
         Before : constant Byte_Array := Slurp (Path);
         S      : KV16.Store;
      begin
         KV16.Open (S, N, St);
         Check ("different V is Wrong_Sizes", St = Wrong_Sizes);
         Check ("and nothing written", Slurp (Path) = Before);
      end;

      Put_Line ("-- fail-stop");
      Check ("write past the last block raises", Raises (Write_Past_End'Access));
      Dev.Close;
      Check ("read on a closed device raises", Raises (Read_Closed'Access));
      Check ("store open on a closed device raises", Raises (Store_On_Closed'Access));

      Put_Line ("-- erase");
      Dev.Open (Path, R);
      Dev.Erase;
      declare
         S : KV.Store;
      begin
         KV.Open (S, N, St);
         Check ("erased file is a fresh store", St = Opened and then N = 0);
      end;
      Dev.Close;

      Put_Line ("-- files that are not ours");
      declare
         Txt  : constant String := Ada.Directories.Compose (Dir, "notes.txt");
         Text : constant Byte_Array := Pad ("hello, this is not a store", 26);
      begin
         Spit (Txt, Text);
         Dev.Open (Txt, R);
         Check ("foreign file refused", R = Dev.Foreign and then not Dev.Is_Open);
         Check ("and left untouched", Slurp (Txt) = Text);
      end;
      declare
         Huge : constant String := Ada.Directories.Compose (Dir, "huge.ldgr");
      begin
         Spit (Huge, [0 .. Natural (Dev.Image_Bytes) + Block_Size - 1 => 16#FF#]);
         Dev.Open (Huge, R);
         Check ("bigger than the device is Too_Large", R = Dev.Too_Large);
         Check ("and left untouched", Size (Huge) = Dev.Image_Bytes + Block_Size);
      end;
      Dev.Open (Dir, R);
      Check ("a directory is Cannot_Open", R = Dev.Cannot_Open);
      Dev.Open (Dir & "/no/such/dir.ldgr", R);
      Check ("a missing directory is Cannot_Open", R = Dev.Cannot_Open);

      Ada.Directories.Delete_Tree (Dir);
   exception
      when others =>
         Ada.Directories.Delete_Tree (Dir);
         raise;
   end Unit;

   ---------------------------------------------------------------------
   --  Crash test halves
   ---------------------------------------------------------------------

   Keys : constant := 16;

   function Key_Of (I : Positive) return Key is (K ("k" & Trim (Natural'Image (I mod Keys))));
   function Val_Of (I : Positive) return Value is (V (Trim (I'Image)));

   procedure Writer (Path : String) is
      R  : Big.Open_Result;
      N  : Natural;
      St : Open_Status;
      OK : Boolean;
      S  : KVB.Store;
   begin
      Big.Open (Path, R);
      if R /= Big.Ok then
         Put_Line ("open " & R'Image);
         Set_Exit_Status (Failure);
         return;
      end if;
      KVB.Open (S, N, St);
      if St /= Opened or else N /= 0 then
         Put_Line ("store " & St'Image);
         Set_Exit_Status (Failure);
         return;
      end if;
      for I in Positive loop
         KVB.Put (S, Key_Of (I), Val_Of (I), OK);
         exit when not OK;
         Put_Line ("ack" & I'Image);
         Flush;
      end loop;
      Put_Line ("full");
   end Writer;

   procedure Checker (Path : String; Acked : Natural) is
      R   : Big.Open_Result;
      N   : Natural;
      St  : Open_Status;
      S   : KVB.Store;
      Got : Value;
      Fnd : Boolean;
      Bad : Boolean := False;
   begin
      Big.Open (Path, R);
      if R /= Big.Ok then
         Put_Line ("FAIL  open " & R'Image);
         Set_Exit_Status (Failure);
         return;
      end if;
      KVB.Open (S, N, St);
      if St /= Opened or else N < Acked or else N > Acked + 1 then
         Put_Line ("FAIL  " & St'Image & " replayed" & N'Image & " acked" & Acked'Image);
         Set_Exit_Status (Failure);
         return;
      end if;
      --  The table must be the replay of Puts 1 .. N.
      for J in 0 .. Keys - 1 loop
         declare
            Last : Natural := 0;
         begin
            for I in 1 .. N loop
               if I mod Keys = J then
                  Last := I;
               end if;
            end loop;
            KVB.Get (S, K ("k" & Trim (J'Image)), Got, Fnd);
            if Fnd /= (Last > 0) or else (Fnd and then not Same (Got, Val_Of (Last))) then
               Bad := True;
            end if;
         end;
      end loop;
      Put_Line ((if Bad then "FAIL  " else "PASS  ")
                & "acked" & Acked'Image & ", recovered" & N'Image);
      if Bad then
         Set_Exit_Status (Failure);
      end if;
   end Checker;

begin
   if Argument_Count >= 2 and then Argument (1) = "write" then
      Writer (Argument (2));
   elsif Argument_Count >= 3 and then Argument (1) = "check" then
      Checker (Argument (2), Natural'Value (Argument (3)));
   else
      declare
         Parent : constant String := (if Argument_Count >= 1 then Argument (1) else ".");
         I      : Natural := 1;
      begin
         Ada.Directories.Create_Path (Parent);
         loop
            declare
               Name : constant String :=
                 Ada.Directories.Compose
                   (Parent, "file-device-test-" & Trim (Natural'Image (I)));
               Made : Boolean := False;
            begin
               begin
                  Ada.Directories.Create_Directory (Name);
                  Made := True;
               exception
                  when Ada.Directories.Use_Error =>
                     if not Ada.Directories.Exists (Name) then
                        raise;
                     end if;
               end;
               if Made then
                  Unit (Name);
                  exit;
               end if;
            end;
            I := I + 1;
         end loop;
      end;
      if Failures = 0 then
         Put_Line ("all file device tests passed");
      else
         Put_Line (Failures'Image & " FAILED");
         Set_Exit_Status (Failure);
      end if;
   end if;
exception
   when E : others =>
      Put_Line ("FAIL  unexpected " & Ada.Exceptions.Exception_Information (E));
      Set_Exit_Status (Failure);
end File_Device_Tests;
