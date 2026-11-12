--  Legder interactive CLI.
--  File-backed testing interface for the transactional store.
--  Keys and values are fixed-size and zero-padded.

with Ada.Text_IO;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Characters.Handling;
with Ada.Exceptions;
with Legder;
with Legder.Store;
with Legder.File_Device;

procedure Legder_CLI is
   use Ada.Text_IO;
   use Ada.Strings.Fixed;
   use Ada.Characters.Handling;
   use type Legder.Open_Status;

   Key_Bytes   : constant Legder.Key_Size := 32;
   Value_Bytes : constant Legder.Value_Size := 64;

   --  Instantiate one file-backed device and one store.
   package Dev is new Legder.File_Device
     (Last_Block => 255);

   use type Dev.Open_Result;

   package KV is new Legder.Store
     (K_Size      => Key_Bytes,
      V_Size      => Value_Bytes,
      Block_Count => Dev.Block_Count,
      Read        => Dev.Read,
      Write       => Dev.Write,
      Sync        => Dev.Sync,
      Capacity    => 128);

   DB       : KV.Store;
   Loaded   : Boolean := False;
   Path     : String (1 .. 512) := (others => ' ');
   Path_Len : Natural := 0;

   --  Convert a text key into the fixed-size store format.
   function Make_Key (Text : String) return Legder.Key is
      Result : Legder.Key;
   begin
      Result.Length := Key_Bytes;

      for I in Text'Range loop
         Result.Bytes (I - Text'First + 1) :=
           Legder.Byte (Character'Pos (Text (I)));
      end loop;

      return Result;
   end Make_Key;

   --  Convert a text value into the fixed-size store format.
   function Make_Value (Text : String) return Legder.Value is
      Result : Legder.Value;
   begin
      Result.Length := Value_Bytes;

      for I in Text'Range loop
         Result.Bytes (I - Text'First + 1) :=
           Legder.Byte (Character'Pos (Text (I)));
      end loop;

      return Result;
   end Make_Value;

   --  Decode until the first zero-padding byte.
   function Value_Text (V : Legder.Value) return String is
      Last : Natural := 0;
   begin
      for I in 1 .. Natural (Value_Bytes) loop
         exit when V.Bytes (I) = 0;
         Last := I;
      end loop;

      declare
         Result : String (1 .. Last);
      begin
         for I in Result'Range loop
            Result (I) :=
              Character'Val (Integer (V.Bytes (I)));
         end loop;
         return Result;
      end;
   end Value_Text;

   --  Release the store before closing the device.
   procedure Unload is
   begin
      if Loaded then
         KV.Unload (DB);
         Loaded := False;
      end if;

      Dev.Close;
   end Unload;

   --  Open a file and recover committed records.
   procedure Open_Database (File_Name : String) is
      Result   : Dev.Open_Result;
      Status   : Legder.Open_Status;
      Replayed : Natural;
   begin
      if File_Name'Length = 0
        or else File_Name'Length > Path'Length
      then
         Put_Line ("Invalid database path.");
         return;
      end if;

      Unload;

      Dev.Open (File_Name, Result);

      if Result /= Dev.Ok then
         Put_Line ("Device error: " & Result'Image);
         return;
      end if;

      KV.Open (DB, Replayed, Status);

      if Status = Legder.Opened then
         Loaded := True;

         Path := (others => ' ');
         Path (1 .. File_Name'Length) := File_Name;
         Path_Len := File_Name'Length;

         Put_Line ("Database opened successfully.");
         Put_Line ("Records replayed:" & Replayed'Image);
      else
         Put_Line ("Store error: " & Status'Image);
         Dev.Close;
      end if;
   end Open_Database;

   --  Print supported commands.
   procedure Show_Help is
   begin
      Put_Line ("");
      Put_Line ("Legder CLI");
      Put_Line ("-------------------------------");
      Put_Line ("open <file>       Open/create database");
      Put_Line ("put <key> <value> Store a value");
      Put_Line ("get <key>         Retrieve a value");
      Put_Line ("delete <key>      Delete a key");
      Put_Line ("count             Count live keys");
      Put_Line ("reopen            Reload from disk");
      Put_Line ("unload            Close database");
      Put_Line ("status            Show store status");
      Put_Line ("help              Show commands");
      Put_Line ("exit              Quit");
      Put_Line ("");
      Put_Line ("Maximum key length: 32 bytes");
      Put_Line ("Maximum value length: 64 bytes");
      Put_Line ("Values may contain spaces.");
      Put_Line ("");
   end Show_Help;

   --  Execute one command entered by the user.
   procedure Execute (Line : String) is
      Separator : constant Natural := Index (Line, " ");

      Command : constant String :=
        To_Lower
          (if Separator = 0 then Line
           else Line (Line'First .. Separator - 1));

      Args : constant String :=
        (if Separator = 0 then ""
         else Trim
           (Line (Separator + 1 .. Line'Last),
            Ada.Strings.Both));

      Second : constant Natural := Index (Args, " ");

      Success : Boolean;
      Found   : Boolean;
      V       : Legder.Value;
   begin
      if Command = "help" then
         Show_Help;

      elsif Command = "open" then
         if Args'Length = 0 then
            Put_Line ("Usage: open <file>");
         else
            Open_Database (Args);
         end if;

      elsif Command = "unload" then
         Unload;
         Put_Line ("Database unloaded.");

      elsif Command = "reopen" then
         if Path_Len = 0 then
            Put_Line ("No previous database.");
         else
            declare
               Saved : constant String :=
                 Path (1 .. Path_Len);
            begin
               Open_Database (Saved);
            end;
         end if;

      elsif Command = "status" then
         Put_Line
           ("Device open: " & Boolean'Image (Dev.Is_Open));
         Put_Line
           ("Device failed: " & Boolean'Image (Dev.Has_Failed));
         Put_Line
           ("Store loaded: " & Boolean'Image (Loaded));

         if Path_Len > 0 then
            Put_Line ("File: " & Path (1 .. Path_Len));
         end if;

         if Loaded then
            Put_Line
              ("Live keys:" & Natural'Image (KV.Count (DB)));
         end if;

      elsif Command = "count" then
         if not Loaded then
            Put_Line ("Open a database first.");
         else
            Put_Line
              ("Live keys:" & Natural'Image (KV.Count (DB)));
         end if;

      elsif Command = "put" then
         if not Loaded then
            Put_Line ("Open a database first.");
         elsif Second = 0 then
            Put_Line ("Usage: put <key> <value>");
         else
            declare
               Key_Text : constant String :=
                 Args (Args'First .. Second - 1);

               Data_Text : constant String :=
                 Trim
                   (Args (Second + 1 .. Args'Last),
                    Ada.Strings.Both);
            begin
               if Key_Text'Length = 0
                 or else Key_Text'Length > Natural (Key_Bytes)
                 or else Data_Text'Length = 0
                 or else Data_Text'Length > Natural (Value_Bytes)
               then
                  Put_Line ("Invalid key or value length.");
               else
                  KV.Put
                    (DB,
                     Make_Key (Key_Text),
                     Make_Value (Data_Text),
                     Success);

                  if Success then
                     Put_Line ("OK");
                  else
                     Put_Line ("Put failed: capacity or log full.");
                  end if;
               end if;
            end;
         end if;

      elsif Command = "get" or else Command = "delete" then
         if not Loaded then
            Put_Line ("Open a database first.");
         elsif Args'Length = 0
           or else Args'Length > Natural (Key_Bytes)
           or else Second /= 0
         then
            Put_Line ("Usage: " & Command & " <key>");
         elsif Command = "get" then
            KV.Get (DB, Make_Key (Args), V, Found);

            if Found then
               Put_Line ("Value: " & Value_Text (V));
            else
               Put_Line ("Key not found.");
            end if;
         else
            KV.Delete (DB, Make_Key (Args), Success);

            if Success then
               Put_Line ("OK");
            else
               Put_Line ("Delete failed.");
            end if;
         end if;

      elsif Command'Length > 0 then
         Put_Line ("Unknown command. Type help.");
      end if;
   end Execute;

begin
   Put_Line ("Legder Interactive CLI");
   Show_Help;

   loop
      Put ("legder> ");
      Flush;

      declare
         Line : constant String := Get_Line;
         Input : constant String :=
           Trim (Line, Ada.Strings.Both);
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
