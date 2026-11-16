package body Legder.RAM_Device with SPARK_Mode is

   subtype Idx is Block_Index range 0 .. Block_Count;
   type Blocks is array (Idx) of Block;

   Durable   : Blocks := [others => [others => 16#FF#]];
   Pending   : Blocks := [others => [others => 16#FF#]];
   Dirty     : array (Idx) of Boolean := [others => False];
   Tear      : Boolean := False;
   N_Writes  : Natural := 0;
   N_Syncs   : Natural := 0;

   procedure Read (Index : Block_Index; Data : out Block; Result : out Device_Result) is
   begin
      if Index > Block_Count then
         Data := [others => 16#FF#];
         Result := Failed;
         return;
      elsif Dirty (Index) then
         Data := Pending (Index);
      else
         Data := Durable (Index);
      end if;
      Result := Success;
   end Read;

   procedure Write (Index : Block_Index; Data : Block; Result : out Device_Result) is
   begin
      if Index > Block_Count then
         Result := Failed;
         return;
      end if;
      N_Writes := N_Writes + 1;
      if Tear then
         Tear := False;
         declare
            Torn : Block := Data;
         begin
            for I in 0 .. Block_Size / 2 - 1 loop
               Torn (I) := Byte ((I * 7 + 13) mod 256);
            end loop;
            Pending (Index) := Torn;
         end;
      else
         Pending (Index) := Data;
      end if;
      Dirty (Index) := True;
      Result := Success;
   end Write;

   procedure Sync (Result : out Device_Result) is
   begin
      N_Syncs := N_Syncs + 1;
      for I in Idx loop
         if Dirty (I) then
            Durable (I) := Pending (I);
            Dirty (I) := False;
         end if;
      end loop;
      Result := Success;
   end Sync;

   procedure Erase is
   begin
      Durable := [others => [others => 16#FF#]];
      Pending := Durable;
      Dirty := [others => False];
      Tear := False;
      N_Writes := 0;
      N_Syncs := 0;
   end Erase;

   procedure Tear_Next_Write is
   begin
      Tear := True;
   end Tear_Next_Write;

   procedure Drop_Unsynced is
   begin
      for I in Idx loop
         if Dirty (I) then
            Pending (I) := Durable (I);
            Dirty (I) := False;
         end if;
      end loop;
   end Drop_Unsynced;

   function Writes return Natural is (N_Writes);
   function Syncs  return Natural is (N_Syncs);

end Legder.RAM_Device;
