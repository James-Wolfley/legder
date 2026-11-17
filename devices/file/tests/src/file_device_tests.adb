--  Tests for Legder.File_Device. Plain Ada, no framework.

with Ada.Command_Line;     use Ada.Command_Line;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Text_IO;          use Ada.Text_IO;
with GNAT.OS_Lib;
with Legder;
with Legder.File_Device;
with Legder.Store;
with Legder.Header;

procedure File_Device_Tests is

   package App is new Legder (8, 8);
   use App;
   package Hdr is new App.Header;
   K_Bytes : constant := Key'Length;
   V_Bytes : constant := Value'Length;

   package Dev  is new App.File_Device (Blocks => 64);
   package Dev2 is new App.File_Device (Blocks => 64);
   package KV   is new App.Store (Dev.Last_Block, Dev.Read, Dev.Write, Dev.Sync);
   package Other is new Legder (4, 12);
   package Other_Dev is new Other.File_Device (Blocks => 64);

   package Big is new App.File_Device (Blocks => Max_Blocks);
   package KVB is new App.Store (Big.Last_Block, Big.Read, Big.Write, Big.Sync);

   use type Dev.Open_Result;
   use type Dev2.Open_Result;
   use type Big.Open_Result;
   use type Other_Dev.Open_Result;

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
     (Key (Pad (S, K_Bytes)));

   function V (S : String) return Value is
     (Value (Pad (S, V_Bytes)));

   function Trim (S : String) return String is
     (if S'Length > 0 and then S (S'First) = ' ' then S (S'First + 1 .. S'Last) else S);

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

   procedure Unit (Dir : String) is
       Path   : constant String := Ada.Directories.Compose (Dir, "store.ldgr");
       R      : Dev.Open_Result;
       R2     : Dev2.Open_Result;
       N      : Natural;
       St     : Open_Status;
       Update : Update_Result;
       Got    : Value;
       Fnd    : Boolean;

      function Has (S : KV.Store; Name, Want : String) return Boolean is
      begin
         KV.Get (S, K (Name), Got, Fnd);
          return Fnd and then Got = V (Want);
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

      procedure Write_Past_End is
      begin
          Dev.Write (Dev.Last_Block + 1, [others => 0]);
      end Write_Past_End;

   begin
      Put_Line ("-- fresh file");
      Dev.Open (Path, R);
      Check ("new file opens", R = Dev.Ok);
       Check ("new file is full size", Size (Path) = 64 * (8 + 8 + 13));
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
          KV.Put (S, K ("a"), V ("1"), Update);
          KV.Put (S, K ("b"), V ("2"), Update);
          KV.Put (S, K ("a"), V ("3"), Update);
           KV.Delete (S, K ("b"), Update);
           Check ("four commits", Update = Applied);
           declare
              Img : constant Byte_Array := Slurp (Path);
           begin
              Check ("records start at the configured stride",
                     Img (29) = 0 and then Img (30) = 1
                     and then Img (29 + 9) = Byte (Character'Pos ('a'))
                     and then Img (4 * 29) = 1
                     and then Img (4 * 29 + 1) = 4);
           end;
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
          KV.Put (S, K ("c"), V ("4"), Update);
          Check ("next commit reuses the torn block", Update = Applied);
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
       Dev.Close;
       declare
          Before : constant Byte_Array := Slurp (Path);
          Other_Result : Other_Dev.Open_Result;
       begin
          Other_Dev.Open (Path, Other_Result);
          Check ("same stride but different K/V refused without writes",
                 Other_Result = Other_Dev.Wrong_Sizes
                 and then not Other_Dev.Is_Open and then Slurp (Path) = Before);
       end;
       Dev.Open (Path, R);

      Put_Line ("-- fail-stop");
      Check ("write past the last block raises", Raises (Write_Past_End'Access));
      Dev.Close;
      Check ("read on a closed device raises", Raises (Read_Closed'Access));
       declare
          S : KV.Store;
       begin
          KV.Open (S, N, St);
          Check ("store reports a closed-device failure",
                 St = Storage_Failure and then N = 0 and then not KV.Is_Open (S));
       end;

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
          Old_Path : constant String := Ada.Directories.Compose (Dir, "old.ldgr");
          Header : Block;
          Image : Byte_Array (0 .. 511) := [others => 16#FF#];
          Sum : CRC32;
       begin
          Hdr.Encode ((Version => Hdr.Current_Version, K => K_Bytes, V => V_Bytes), Header);
          Header (4) := 1;
          Sum := CRC (Header (0 .. 7));
          for I in 0 .. 3 loop
             Header (8 + I) := Byte (Sum and 16#FF#);
             Sum := Sum / 256;
          end loop;
          Image (0 .. Block_Size - 1) := Header;
          Image (Block_Size .. 511) := [others => 0];
          Spit (Old_Path, Image);
          Dev.Open (Old_Path, R);
          Check ("version 1 image refused without writes",
                 R = Dev.Bad_Version and then not Dev.Is_Open
                 and then Slurp (Old_Path) = Image);
       end;
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
         Check ("and left untouched",
                Size (Huge) = Dev.Image_Bytes + Long_Integer (Block_Size));
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

   Keys : constant := 16;

   function Key_Of (I : Positive) return Key is (K ("k" & Trim (Natural'Image (I mod Keys))));
   function Val_Of (I : Positive) return Value is (V (Trim (I'Image)));

   procedure Writer (Path : String) is
       R      : Big.Open_Result;
       N      : Natural;
       St     : Open_Status;
       Update : Update_Result;
       S      : KVB.Store;
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
          KVB.Put (S, Key_Of (I), Val_Of (I), Update);
          exit when Update = No_Space;
          if Update /= Applied then
             Put_Line ("update " & Update'Image);
             Set_Exit_Status (Failure);
             return;
          end if;
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
             if Fnd /= (Last > 0) or else (Fnd and then Got /= Val_Of (Last)) then
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
