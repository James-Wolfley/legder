--  Windows bodies for Legder.File_Device_OS: the CRT descriptor is a C
--  int, the Win32 handle it wraps is address-width (intptr_t), and the
--  Win32 entry points use the Stdcall convention.

with Interfaces.C;  use Interfaces.C;
with Interfaces;    use Interfaces;
with GNAT.OS_Lib;   use GNAT.OS_Lib;
with System.Storage_Elements;

package body Legder.File_Device_OS with SPARK_Mode => Off is

   use type System.Storage_Elements.Integer_Address;

   LOCKFILE_FAIL_IMMEDIATELY : constant unsigned_long := 1;
   LOCKFILE_EXCLUSIVE_LOCK   : constant unsigned_long := 2;
   ERROR_LOCK_VIOLATION      : constant unsigned_long := 33;
   MAXDWORD                  : constant unsigned_long := 16#FFFF_FFFF#;

   type Overlapped is record
      Internal      : System.Storage_Elements.Integer_Address;   --  ULONG_PTR
      Internal_High : System.Storage_Elements.Integer_Address;   --  ULONG_PTR
      Offset        : unsigned_long;            --  DWORD
      Offset_High   : unsigned_long;            --  DWORD
      Event         : System.Address;           --  HANDLE
   end record
     with Convention => C;

   function Commit (FD : int) return int
     with Import, Convention => C, External_Name => "_commit";

   function Get_OS_Handle (FD : int) return System.Storage_Elements.Integer_Address
     with Import, Convention => C, External_Name => "_get_osfhandle";

   function Lseek64
     (FD : int; Offset : Integer_64; Origin : int) return Integer_64
     with Import, Convention => C, External_Name => "_lseeki64";

   function C_Read
     (FD : int; Buffer : System.Address; Length : unsigned) return int
     with Import, Convention => C, External_Name => "_read";

   function C_Write
     (FD : int; Buffer : System.Address; Length : unsigned) return int
     with Import, Convention => C, External_Name => "_write";

   function Lock_File_Ex
     (Handle   : System.Address;
      Flags    : unsigned_long;
      Reserved : unsigned_long;
      Low      : unsigned_long;
      High     : unsigned_long;
      Ov       : System.Address) return int
     with Import, Convention => Stdcall, External_Name => "LockFileEx";

   function Get_Last_Error return unsigned_long
     with Import, Convention => Stdcall, External_Name => "GetLastError";

   function File_Sync (FD : File_Descriptor) return Boolean is
   begin
      return Commit (int (FD)) = 0;
   end File_Sync;

   function Lock (FD : File_Descriptor) return Lock_Result is
      Handle : constant System.Storage_Elements.Integer_Address :=
        Get_OS_Handle (int (FD));
      Ov     : Overlapped := (0, 0, 0, 0, System.Null_Address);
   begin
      if Handle = -1 then
         return Failed;
      end if;
      if Lock_File_Ex
        (System.Storage_Elements.To_Address (Handle),
         LOCKFILE_EXCLUSIVE_LOCK or LOCKFILE_FAIL_IMMEDIATELY,
         0, MAXDWORD, MAXDWORD, Ov'Address) /= 0
      then
         return Locked;
      elsif Get_Last_Error = ERROR_LOCK_VIOLATION then
         return Busy;
      else
         return Failed;
      end if;
   end Lock;

   function Sync_Directory (Path : String) return Boolean is
      pragma Unreferenced (Path);
   begin
      --  Windows has no documented flush for a directory handle. The file
      --  is flushed before this call; the containing directory entry is
      --  left to the file system's metadata journal.
      return True;
   end Sync_Directory;

   function Read_At
     (FD     : File_Descriptor;
      Buffer : System.Address;
      Length : Natural;
      Offset : Long_Integer) return Integer
   is
      Pos : Integer_64;
   begin
      Pos := Lseek64 (int (FD), Integer_64 (Offset), 0);
      if Pos < 0 then
         return -1;
      end if;
      return Integer (C_Read (int (FD), Buffer, unsigned (Length)));
   end Read_At;

   function Write_At
     (FD     : File_Descriptor;
      Buffer : System.Address;
      Length : Natural;
      Offset : Long_Integer) return Integer
   is
      Pos : Integer_64;
   begin
      Pos := Lseek64 (int (FD), Integer_64 (Offset), 0);
      if Pos < 0 then
         return -1;
      end if;
      return Integer (C_Write (int (FD), Buffer, unsigned (Length)));
   end Write_At;

end Legder.File_Device_OS;
