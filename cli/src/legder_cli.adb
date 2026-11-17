with Ada.Text_IO;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Characters.Handling;
with Ada.Exceptions;
with Legder;
with Legder.Store;
with Legder.File_Device;
with Legder.RAM_Device;

procedure Legder_CLI is
   use Ada.Text_IO;
   use Ada.Strings.Fixed;
   use Ada.Characters.Handling;
   package Model is new Legder (K_Size => 32, V_Size => 64);
   use type Model.Open_Status;
   use type Model.Byte;

   package File_Dev is new Model.File_Device (Blocks => 256);
   package RAM_Dev is new Model.RAM_Device (Blocks => 256);
   use type File_Dev.Open_Result;

   package File_KV is new Model.Store
     (Last_Block => File_Dev.Last_Block,
      Read => File_Dev.Read, Write => File_Dev.Write,
      Sync => File_Dev.Sync, Capacity => 128);

   package RAM_KV is new Model.Store
     (Last_Block => RAM_Dev.Last_Block,
      Read => RAM_Dev.Read,
      Write => RAM_Dev.Write,
      Sync => RAM_Dev.Sync, Capacity => 128);

   type Device_Kind is (None, File_Backend, RAM_Backend);
   Active : Device_Kind := None;
   File_DB : File_KV.Store;
   RAM_DB  : RAM_KV.Store;
   Path : String (1 .. 512) := [others => ' '];
   Path_Len : Natural := 0;

   function Make_Key (S : String) return Model.Key is
      K : Model.Key;
   begin
      for I in S'Range loop
         K (I - S'First + 1) :=
           Model.Byte (Character'Pos (S (I)));
      end loop;
      return K;
   end Make_Key;

   function Make_Value (S : String) return Model.Value is
      V : Model.Value;
   begin
      for I in S'Range loop
         V (I - S'First + 1) :=
           Model.Byte (Character'Pos (S (I)));
      end loop;
      return V;
   end Make_Value;

   function Value_Text (V : Model.Value) return String is
      N : Natural := 0;
   begin
      for I in V'Range loop
         exit when V (I) = 0;
         N := I;
      end loop;
      declare
         S : String (1 .. N);
      begin
         for I in S'Range loop
            S (I) := Character'Val (Integer (V (I)));
         end loop;
         return S;
      end;
   end Value_Text;

   procedure Unload is
   begin
      case Active is
         when File_Backend =>
            File_KV.Unload (File_DB);
            File_Dev.Close;
         when RAM_Backend =>
            RAM_KV.Unload (RAM_DB);
         when None =>
            null;
      end case;
      Active := None;
   end Unload;

   procedure Open_File (Name : String) is
      Result : File_Dev.Open_Result;
      Status : Model.Open_Status;
      Replayed : Natural;
   begin
      if Name'Length = 0 or else Name'Length > Path'Length then
         Put_Line ("Invalid file path.");
         return;
      end if;
      Unload;
      File_Dev.Open (Name, Result);
      if Result /= File_Dev.Ok then
         Put_Line ("Device error: " & Result'Image);
         return;
      end if;
      begin
         File_KV.Open (File_DB, Replayed, Status);
      exception
         when others =>
            File_Dev.Close;
            raise;
      end;
      if Status /= Model.Opened then
         Put_Line ("Store error: " & Status'Image);
         File_Dev.Close;
         return;
      end if;
      Active := File_Backend;
      Path := [others => ' '];
      Path (1 .. Name'Length) := Name;
      Path_Len := Name'Length;
      Put_Line
        ("File store opened. Records replayed:" & Replayed'Image);
   end Open_File;

   procedure Open_RAM is
      Status : Model.Open_Status;
      Replayed : Natural;
   begin
      Unload;
      --  Preserve RAM blocks so reopening replays the log.
      RAM_KV.Open (RAM_DB, Replayed, Status);
      if Status = Model.Opened then
         Active := RAM_Backend;
         Put_Line
           ("RAM store opened. Records replayed:" & Replayed'Image);
      else
         Put_Line ("RAM store error: " & Status'Image);
      end if;
   end Open_RAM;

   procedure Store_Put
     (K : Model.Key; V : Model.Value; Result : out Model.Update_Result)
   is
   begin
      case Active is
         when File_Backend =>
            File_KV.Put (File_DB, K, V, Result);
         when RAM_Backend =>
            RAM_KV.Put (RAM_DB, K, V, Result);
         when None =>
            Result := Model.Closed;
      end case;
   end Store_Put;

   procedure Store_Get
     (K : Model.Key; V : out Model.Value; Found : out Boolean)
   is
   begin
      case Active is
         when File_Backend =>
            File_KV.Get (File_DB, K, V, Found);
         when RAM_Backend =>
            RAM_KV.Get (RAM_DB, K, V, Found);
         when None =>
            V := [others => 0];
            Found := False;
      end case;
   end Store_Get;

   procedure Store_Delete
     (K : Model.Key; Result : out Model.Update_Result)
   is
   begin
      case Active is
         when File_Backend =>
            File_KV.Delete (File_DB, K, Result);
         when RAM_Backend =>
            RAM_KV.Delete (RAM_DB, K, Result);
         when None =>
            Result := Model.Closed;
      end case;
   end Store_Delete;

   procedure Report_Update (Result : Model.Update_Result) is
   begin
      case Result is
         when Model.Applied =>
            Put_Line ("OK");
         when Model.No_Space =>
            Put_Line ("Update failed: no space.");
         when Model.Closed =>
            Put_Line ("Update failed: store closed.");
         when Model.Storage_Failure =>
            Put_Line ("Update failed: storage failure. Store unloaded.");
            Unload;
      end case;
   end Report_Update;

   function Store_Count return Natural is
   begin
      case Active is
         when File_Backend =>
            return File_KV.Count (File_DB);
         when RAM_Backend =>
            return RAM_KV.Count (RAM_DB);
         when None =>
            return 0;
      end case;
   end Store_Count;

   procedure Help is
   begin
      Put_Line ("open file <path>   Open/create file store");
      Put_Line ("open <path>        File store (legacy syntax)");
      Put_Line ("open ram           Open in-memory store");
      Put_Line ("put <key> <value>  Write a value");
      Put_Line ("get <key>          Read a value");
      Put_Line ("delete <key>       Delete a key");
      Put_Line ("count              Count live keys");
      Put_Line ("reopen             Unload/replay active store");
      Put_Line ("unload             Unload active store");
      Put_Line ("status             Display active device");
      Put_Line ("ram erase          Erase RAM store (RAM only)");
      Put_Line ("help | exit");
      Put_Line ("Keys: 1 .." & Model.Key'Length'Image & " bytes; values: 1 .."
                & Model.Value'Length'Image & " bytes.");
   end Help;


   --  Parse a key, allowing double quotes around keys with spaces.
   --  Next_Pos points to the first character after the key.
   function Parse_Key
     (Args : String; Key_Text : out Ada.Strings.Unbounded.Unbounded_String;
      Next_Pos : out Natural) return Boolean
   is
      use Ada.Strings.Unbounded;
      First : Natural := Args'First;
      Last  : Natural;
   begin
      Key_Text := Null_Unbounded_String;
      Next_Pos := Args'Last + 1;

      if Args'Length = 0 then
         return False;
      end if;

      while First <= Args'Last and then Args (First) = ' ' loop
         First := First + 1;
      end loop;

      if First > Args'Last then
         return False;
      end if;

      if Args (First) = '"' then
         First := First + 1;
         Last := First;

         while Last <= Args'Last loop
            exit when Args (Last) = '"';
            Last := Last + 1;
         end loop;

         if Last > Args'Last or else Last = First then
            return False;
         end if;

         Key_Text := To_Unbounded_String (Args (First .. Last - 1));
         Next_Pos := Last + 1;

         if Next_Pos <= Args'Last
           and then Args (Next_Pos) /= ' '
         then
            return False;
         end if;
      else
         Last := First;

         while Last <= Args'Last loop
            exit when Args (Last) = ' ';
            Last := Last + 1;
         end loop;

         Key_Text := To_Unbounded_String (Args (First .. Last - 1));
         Next_Pos := Last;
      end if;

      return Length (Key_Text) > 0
        and then Length (Key_Text) <= Model.Key'Length;
   end Parse_Key;

   procedure Execute (Line : String) is
      Space_1 : constant Natural := Index (Line, " ");
      Cmd : constant String := To_Lower
        (if Space_1 = 0 then Line
         else Line (Line'First .. Space_1 - 1));
      Args : constant String :=
        (if Space_1 = 0 then ""
         else Trim
           (Line (Space_1 + 1 .. Line'Last),
            Ada.Strings.Both));
      Found : Boolean;
      Result : Model.Update_Result;
      V : Model.Value;
   begin
      if Cmd = "help" then
         Help;

      elsif Cmd = "open" then
         if To_Lower (Args) = "ram" then
            Open_RAM;
         elsif Args'Length >= 5
           and then To_Lower
             (Args (Args'First .. Args'First + 4)) = "file "
         then
            Open_File
              (Trim
                (Args (Args'First + 5 .. Args'Last),
                 Ada.Strings.Both));
         elsif Args'Length > 0 then
            Open_File (Args);
         else
            Put_Line ("Usage: open ram | open file <path>");
         end if;

      elsif Cmd = "unload" then
         Unload;
         Put_Line ("Store unloaded.");

      elsif Cmd = "reopen" then
         case Active is
            when RAM_Backend =>
               Open_RAM;
            when File_Backend =>
               declare
                  Saved : constant String := Path (1 .. Path_Len);
               begin
                  Open_File (Saved);
               end;
            when None =>
               Put_Line ("No active store to reopen.");
         end case;

      elsif Cmd = "ram" and then To_Lower (Args) = "erase" then
         if Active = RAM_Backend then
            Unload;
            RAM_Dev.Erase;
            Open_RAM;
            Put_Line ("RAM store erased.");
         else
            Put_Line ("Open the RAM store first.");
         end if;

      elsif Cmd = "status" then
         Put_Line ("Device: " & Active'Image);
         if Active = File_Backend then
            Put_Line ("Path: " & Path (1 .. Path_Len));
            Put_Line
              ("Device failed: " &
               Boolean'Image (File_Dev.Has_Failed));
         elsif Active = RAM_Backend then
            Put_Line
              ("RAM writes:" &
               Natural'Image (RAM_Dev.Writes));
            Put_Line
              ("RAM syncs:" &
               Natural'Image (RAM_Dev.Syncs));
         end if;
         if Active /= None then
            Put_Line ("Live keys:" & Natural'Image (Store_Count));
         end if;

      elsif Cmd = "count" then
         if Active = None then
            Put_Line ("Open a store first.");
         else
            Put_Line ("Live keys:" & Natural'Image (Store_Count));
         end if;

      elsif Cmd = "put" then
         if Active = None then
            Put_Line ("Open a store first.");
         else
            declare
               use Ada.Strings.Unbounded;
               Key_Text : Unbounded_String;
               Next_Pos : Natural;
            begin
               if not Parse_Key (Args, Key_Text, Next_Pos) then
                  Put_Line ("Usage: put <key> <value>");
               elsif Next_Pos > Args'Last then
                  Put_Line ("Usage: put <key> <value>");
               else
                  declare
                     Data : constant String :=
                       Trim (Args (Next_Pos .. Args'Last),
                             Ada.Strings.Both);
                  begin
                     if Data'Length = 0
                       or else Data'Length > Model.Value'Length
                     then
                        Put_Line ("Invalid value length.");
                     else
                        Store_Put
                          (Make_Key (To_String (Key_Text)),
                           Make_Value (Data), Result);
                        Report_Update (Result);
                     end if;
                  end;
               end if;
            end;
         end if;


      elsif Cmd = "get" or else Cmd = "delete" then
         if Active = None then
            Put_Line ("Open a store first.");
         else
            declare
               use Ada.Strings.Unbounded;
               Key_Text : Unbounded_String;
               Next_Pos : Natural;
            begin
               if not Parse_Key (Args, Key_Text, Next_Pos) then
                  Put_Line ("Usage: " & Cmd & " <key>");
               elsif Next_Pos <= Args'Last
                 and then
                   Trim (Args (Next_Pos .. Args'Last),
                         Ada.Strings.Both) /= ""
               then
                  Put_Line ("Usage: " & Cmd & " <key>");
               elsif Cmd = "get" then
                  Store_Get
                    (Make_Key (To_String (Key_Text)), V, Found);
                  Put_Line
                    (if Found then "Value: " & Value_Text (V)
                     else "Key not found.");
               else
                  Store_Delete
                    (Make_Key (To_String (Key_Text)), Result);
                  Report_Update (Result);
               end if;
            end;
         end if;

      elsif Cmd'Length > 0 then
         Put_Line ("Unknown command. Type help.");
      end if;
   end Execute;


begin
   Put_Line ("Legder CLI - file and RAM devices");
   Help;

   loop
      Put ("legder> ");
      Flush;
      declare
         Input : constant String :=
           Trim (Get_Line, Ada.Strings.Both);
      begin
         exit when To_Lower (Input) = "exit";
         begin
            Execute (Input);
         exception
            when E : others =>
               Put_Line
                 ("Command error: " &
                  Ada.Exceptions.Exception_Message (E));
               Unload;
               Put_Line ("Store unloaded after error.");
         end;
      end;
   end loop;

   Unload;
   Put_Line ("Goodbye.");

exception
   when End_Error =>
      Unload;
   when E : others =>
      Put_Line
        ("Fatal error: " &
         Ada.Exceptions.Exception_Message (E));
      Unload;
end Legder_CLI;
