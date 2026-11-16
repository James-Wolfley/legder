with Legder.Record_Format;
package body Legder.Store with SPARK_Mode is

   use Legder.Record_Format;
   use type L.Log_Phase;

   function Find (T : Entry_Array; K : Key) return Natural;
   function Free_Slot (T : Entry_Array) return Natural;
   procedure Apply (T : in out Entry_Array; Live : in out Natural; R : Log_Record);

   function Find (T : Entry_Array; K : Key) return Natural is
   begin
      for I in Entry_Index loop
         if T (I).Live and then T (I).K = K then
            return Natural (I);
         end if;
      end loop;
      return 0;
   end Find;

   function Free_Slot (T : Entry_Array) return Natural is
   begin
      for I in Entry_Index loop
         if not T (I).Live then
            return Natural (I);
         end if;
      end loop;
      return 0;
   end Free_Slot;

   procedure Apply (T : in out Entry_Array; Live : in out Natural; R : Log_Record) is
      I : constant Natural := Find (T, R.K);
   begin
      case R.Kind is
         when Put =>
            if I /= 0 then
               T (Entry_Index (I)).V := R.V;
            else
               declare
                  F : constant Natural := Free_Slot (T);
               begin
                  if F /= 0 then
                     T (Entry_Index (F)) := (Live => True, K => R.K, V => R.V);
                     Live := Live + 1;
                  end if;
               end;
            end if;
         when Delete =>
            if I /= 0 then
               T (Entry_Index (I)).Live := False;
               Live := Live - 1;
            end if;
      end case;
   end Apply;

   function Is_Open (S : Store) return Boolean is (S.Log.Phase = L.Ready);

   procedure Open (S : out Store; Replayed : out Natural; Status : out Open_Status) is
      Exceeded : Boolean := False;
      Failed_Scan : Boolean := False;
      Complete : Boolean;

      procedure Visit (R : Log_Record);
      procedure Visit (R : Log_Record) is
      begin
         if R.Kind = Put and then not Exceeded then
            declare
               Superseded : Boolean := False;
               Scanned : Boolean;
               procedure Check (Later : Log_Record);
               procedure Check (Later : Log_Record) is
               begin
                  if Later.Seq > R.Seq and then Later.K = R.K then
                     Superseded := True;
                  end if;
               end Check;
               procedure Scan_All is new L.Scan (Check);
            begin
               Scan_All (S.Log, Scanned);
               if not Scanned then
                  Failed_Scan := True;
               elsif not Superseded then
                  if S.Live = Capacity then
                     Exceeded := True;
                  else
                     S.Live := S.Live + 1;
                     S.Table (Entry_Index (S.Live)) :=
                       (Live => True, K => R.K, V => R.V);
                  end if;
               end if;
            end;
         end if;
      end Visit;
      procedure Replay_Final is new L.Scan (Visit);
   begin
      S.Table := [others => <>];
      S.Live := 0;
      L.Inspect (S.Log, Replayed, Status);
      if Status = Opened then
         Replay_Final (S.Log, Complete);
         if not Complete or else Failed_Scan then
            Unload (S);
            Replayed := 0;
            Status := Storage_Failure;
         elsif Exceeded then
            Unload (S);
            Status := Capacity_Exceeded;
         else
            L.Open (S.Log, Status);
            if Status /= Opened then
               Unload (S);
               Replayed := 0;
            end if;
         end if;
      end if;
   end Open;

   procedure Unload (S : in out Store) is
   begin
      S.Table := [others => <>];
      S.Live := 0;
      S.Log.Phase := L.Closed;
   end Unload;

   procedure Put (S : in out Store; K : Key; V : Value; Result : out Update_Result) is
   begin
      if not Is_Open (S) then
         Result := Closed;
         return;
      end if;
      if Find (S.Table, K) = 0 and then Free_Slot (S.Table) = 0 then
         Result := No_Space;
         return;
      end if;
      L.Append (S.Log, Record_Format.Put, K, V, Result);
      if Result = Applied then
         Apply (S.Table, S.Live,
                (Seq => S.Log.Last_Seq, Kind => Record_Format.Put, K => K, V => V));
      elsif Result = Storage_Failure then
         Unload (S);
      end if;
   end Put;

   procedure Delete (S : in out Store; K : Key; Result : out Update_Result) is
      None : Value;
   begin
      if not Is_Open (S) then
         Result := Closed;
         return;
      end if;
      L.Append (S.Log, Record_Format.Delete, K, None, Result);
      if Result = Applied then
         Apply (S.Table, S.Live,
                (Seq => S.Log.Last_Seq, Kind => Record_Format.Delete, K => K, V => None));
      elsif Result = Storage_Failure then
         Unload (S);
      end if;
   end Delete;

   procedure Get (S : Store; K : Key; V : out Value; Found : out Boolean) is
      I : Natural;
   begin
      if not Is_Open (S) then
         V := (others => <>);
         Found := False;
         return;
      end if;
      I := Find (S.Table, K);
      if I = 0 then
         V := (others => <>);
         Found := False;
      else
         V := S.Table (Entry_Index (I)).V;
         Found := True;
      end if;
   end Get;

   function Count (S : Store) return Natural is
     (if Is_Open (S) then S.Live else 0);

end Legder.Store;
