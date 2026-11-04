with Ada.Directories;
with Interfaces.C;           use Interfaces.C;
with Interfaces.C.Strings;
with GNAT.OS_Lib;          use GNAT.OS_Lib;
with Legder.Header;          use type Legder.Header.Status;

package body Legder.File_Device with SPARK_Mode => Off is

   ---------------------------------------------------------------------
   --  The C shim, legder_file_device.c: the calls GNAT.OS_Lib lacks.
   ---------------------------------------------------------------------

   function Fd_Sync (FD : int) return int
     with Import, Convention => C, External_Name => "legder_fd_sync";
   --  0 when every write to FD is on stable storage.

   function Fd_Lock (FD : int) return int
     with Import, Convention => C, External_Name => "legder_fd_lock";
   --  0 locked, 1 held by someone else, -1 error.

   function Dir_Sync (Path : Interfaces.C.Strings.chars_ptr) return int
     with Import, Convention => C, External_Name => "legder_dir_sync";
   --  0 when the directory entries in Path are durable.

   ---------------------------------------------------------------------
   --  State: one file per instance.
   ---------------------------------------------------------------------

   FD     : File_Descriptor := Invalid_FD;
   Failed : Boolean := False;

   Erased : constant Block := [others => 16#FF#];

   function Offset (Index : Block_Index) return Long_Integer is
     (Long_Integer (Index) * Block_Size);

   procedure Fail (Why : String) with No_Return;

   procedure Fail (Why : String) is
   begin
      Failed := True;
      raise Device_Error with Why;
   end Fail;

   procedure Check_Usable;
   --  Raises unless the device is open and has not failed.

   function Pwrite (Data : Byte_Array; At_Offset : Long_Integer) return Boolean;
   function Pread
     (Data : out Byte_Array; At_Offset : Long_Integer; Got : out Natural) return Boolean;
   --  Raw transfers. Both loop over short counts; False means an OS
   --  error. Pread fills past EOF with 16#FF#, and reports in Got how
   --  many bytes the file held.

   function Sync_Directory (Path : String) return Boolean;
   --  Makes the directory entry for Path durable.

   procedure Abandon (Result : out Open_Result; Why : Open_Result);
   --  Closes a half-opened file and reports Why.

   procedure Check_Usable is
   begin
      if FD = Invalid_FD then
         raise Device_Error with "file device is not open";
      elsif Failed then
         raise Device_Error with "file device failed earlier; close and reopen";
      end if;
   end Check_Usable;

   function Pwrite (Data : Byte_Array; At_Offset : Long_Integer) return Boolean is
      Done : Natural := 0;
      N    : Integer;
   begin
      Lseek (FD, At_Offset, Seek_Set);
      while Done < Data'Length loop
         N := GNAT.OS_Lib.Write
           (FD, Data (Data'First + Done)'Address, Data'Length - Done);
         if N <= 0 then
            return False;
         end if;
         Done := Done + N;
      end loop;
      return True;
   end Pwrite;

   function Pread
     (Data : out Byte_Array; At_Offset : Long_Integer; Got : out Natural) return Boolean
   is
      N : Integer;
   begin
      Data := [others => 16#FF#];
      Got := 0;
      Lseek (FD, At_Offset, Seek_Set);
      while Got < Data'Length loop
         N := GNAT.OS_Lib.Read (FD, Data (Data'First + Got)'Address, Data'Length - Got);
         if N < 0 then
            return False;
         end if;
         exit when N = 0;   --  EOF: the rest stays erased
         Got := Got + N;
      end loop;
      return True;
   end Pread;

   function Sync_Directory (Path : String) return Boolean is
      Dir : Interfaces.C.Strings.chars_ptr;
      R   : int;
   begin
      Dir := Interfaces.C.Strings.New_String
        (Ada.Directories.Containing_Directory (Ada.Directories.Full_Name (Path)));
      R := Dir_Sync (Dir);
      Interfaces.C.Strings.Free (Dir);
      return R = 0;
   exception
      when others =>
         return False;
   end Sync_Directory;

   procedure Abandon (Result : out Open_Result; Why : Open_Result) is
   begin
      if FD /= Invalid_FD then
         GNAT.OS_Lib.Close (FD);
         FD := Invalid_FD;
      end if;
      Failed := False;
      Result := Why;
   end Abandon;

   ----------
   -- Open --
   ----------

   procedure Open (Path : String; Result : out Open_Result) is
      Created : Boolean := False;
      Length  : Long_Integer;
      B0      : Block;
      Got     : Natural;
   begin
      if FD /= Invalid_FD then
         Result := Already_Open;
         return;
      end if;
      Failed := False;

      if Is_Regular_File (Path) then
         FD := Open_Read_Write (Path, Binary);
      elsif Is_Directory (Path) then
         Result := Cannot_Open;
         return;
      else
         --  Create_New_File is O_EXCL but write-only: create, then
         --  reopen for both directions.
         FD := Create_New_File (Path, Binary);
         if FD /= Invalid_FD then
            GNAT.OS_Lib.Close (FD);
            Created := True;
            FD := Open_Read_Write (Path, Binary);
         end if;
      end if;
      if FD = Invalid_FD then
         Result := Cannot_Open;
         return;
      end if;

      case Fd_Lock (int (FD)) is
         when 0      => null;
         when 1      => Abandon (Result, Locked); return;
         when others => Abandon (Result, IO_Failed); return;
      end case;

      Length := File_Length (FD);
      if Length < 0 then
         Abandon (Result, IO_Failed);
         return;
      elsif Length > Image_Bytes then
         Abandon (Result, Too_Large);
         return;
      end if;

      --  Never write into a file that is not ours. Block 0 decides:
      --  erased (missing bytes count as erased) or a legder header.
      if not Pread (B0, 0, Got) then
         Abandon (Result, IO_Failed);
         return;
      end if;
      if B0 /= Erased then
         declare
            H  : Legder.Header.Header;
            HS : Legder.Header.Status;
         begin
            Legder.Header.Decode (B0, H, HS);
            if HS = Legder.Header.Bad_Header then
               Abandon (Result, Foreign);
               return;
            end if;
            --  Unsupported_Version is still a legder file: Store.Open
            --  reports it as Bad_Version without writing.
         end;
      end if;

      --  Bring a short file to full size, as erased blocks, and make
      --  that durable before the log can write a header into it.
      if Length < Image_Bytes then
         declare
            Pos : Long_Integer := Length;
            Len : Long_Integer;
         begin
            while Pos < Image_Bytes loop
               Len := Long_Integer'Min (Block_Size - Pos mod Block_Size, Image_Bytes - Pos);
               if not Pwrite (Erased (0 .. Natural (Len) - 1), Pos) then
                  Abandon (Result, IO_Failed);
                  return;
               end if;
               Pos := Pos + Len;
            end loop;
         end;
         if Fd_Sync (int (FD)) /= 0 then
            Abandon (Result, IO_Failed);
            return;
         end if;
      end if;
      if Created and then not Sync_Directory (Path) then
         Abandon (Result, IO_Failed);
         return;
      end if;

      Result := Ok;
   end Open;

   -----------
   -- Close --
   -----------

   procedure Close is
   begin
      if FD /= Invalid_FD then
         GNAT.OS_Lib.Close (FD);   --  also drops the lock
         FD := Invalid_FD;
      end if;
      Failed := False;
   end Close;

   function Is_Open return Boolean is (FD /= Invalid_FD);

   function Has_Failed return Boolean is (Failed);

   ----------
   -- Read --
   ----------

   procedure Read (Index : Block_Index; Data : out Block) is
      Got : Natural;
   begin
      Check_Usable;
      if Index > Block_Count then
         Data := Erased;
         return;
      end if;
      if not Pread (Data, Offset (Index), Got) then
         Fail ("read failed at block" & Index'Image);
      end if;
   end Read;

   -----------
   -- Write --
   -----------

   procedure Write (Index : Block_Index; Data : Block) is
   begin
      Check_Usable;
      if Index > Block_Count then
         --  Silently dropping it would let a commit look durable.
         raise Device_Error with "write past last block" & Block_Count'Image;
      end if;
      if not Pwrite (Data, Offset (Index)) then
         Fail ("write failed at block" & Index'Image);
      end if;
   end Write;

   ----------
   -- Sync --
   ----------

   procedure Sync is
   begin
      Check_Usable;
      if Fd_Sync (int (FD)) /= 0 then
         Fail ("sync failed");
      end if;
   end Sync;

   -----------
   -- Erase --
   -----------

   procedure Erase is
   begin
      Check_Usable;
      for I in Block_Index range 0 .. Block_Count loop
         Write (I, Erased);
      end loop;
      Sync;
   end Erase;

end Legder.File_Device;
