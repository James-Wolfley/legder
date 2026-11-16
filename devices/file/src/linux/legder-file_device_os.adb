--  Linux bodies for Legder.File_Device_OS. Values are the asm-generic
--  ones in /usr/include.

with Interfaces.C;  use Interfaces.C;
with GNAT.OS_Lib;   use GNAT.OS_Lib;

package body Legder.File_Device_OS with SPARK_Mode => Off is

   pragma Compile_Time_Error
     (long'Size /= 64, "Linux file device requires 64-bit C long");

   EINTR       : constant Integer := 4;
   EWOULDBLOCK : constant Integer := 11;
   LOCK_EX_NB  : constant int := 6;   --  LOCK_EX (2) or LOCK_NB (4)

   function Fsync (FD : int) return int
     with Import, Convention => C, External_Name => "fsync";

   function Flock (FD : int; Operation : int) return int
     with Import, Convention => C, External_Name => "flock";

   function Pread
     (FD : int; Buffer : System.Address; Length : size_t; Offset : long)
      return long
     with Import, Convention => C, External_Name => "pread";

   function Pwrite
     (FD : int; Buffer : System.Address; Length : size_t; Offset : long)
      return long
     with Import, Convention => C, External_Name => "pwrite";

   function File_Sync (FD : File_Descriptor) return Boolean is
      R : int;
   begin
      loop
         R := Fsync (int (FD));
         exit when R = 0 or else Errno /= EINTR;
      end loop;
      return R = 0;
   end File_Sync;

   function Lock (FD : File_Descriptor) return Lock_Result is
      R : int;
   begin
      loop
         R := Flock (int (FD), LOCK_EX_NB);
         exit when R = 0 or else Errno /= EINTR;
      end loop;
      if R = 0 then
         return Locked;
      elsif Errno = EWOULDBLOCK then
         return Busy;
      else
         return Failed;
      end if;
   end Lock;

   function Sync_Directory (Path : String) return Boolean is
      Dir : constant File_Descriptor := Open_Read (Path, Binary);
      R   : int;
      Ok  : Boolean;
   begin
      if Dir = Invalid_FD then
         return False;
      end if;
      loop
         R := Fsync (int (Dir));
         exit when R = 0 or else Errno /= EINTR;
      end loop;
      Ok := R = 0;   --  before Close, which may change Errno
      Close (Dir);
      return Ok;
   end Sync_Directory;

   function Read_At
     (FD     : File_Descriptor;
      Buffer : System.Address;
      Length : Natural;
      Offset : Long_Integer) return Integer
   is
      N : constant long :=
        Pread (int (FD), Buffer, size_t (Length), long (Offset));
   begin
      if N < 0 then
         return -1;
      end if;
      return Integer (N);
   end Read_At;

   function Write_At
     (FD     : File_Descriptor;
      Buffer : System.Address;
      Length : Natural;
      Offset : Long_Integer) return Integer
   is
      N : constant long :=
        Pwrite (int (FD), Buffer, size_t (Length), long (Offset));
   begin
      if N < 0 then
         return -1;
      end if;
      return Integer (N);
   end Write_At;

end Legder.File_Device_OS;
