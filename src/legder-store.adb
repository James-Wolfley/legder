with Legder.Record_Format;
package body Legder.Store with SPARK_Mode is

   use Legder.Record_Format;

   --  PLACEHOLDER index: linear scan. See the spec.

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

   --  Apply one record to the table. Used by Open (replay) and by
   --  Put/Delete (after commit). One code path, so replay and live
   --  updates cannot drift apart.
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
                  --  F = 0: table full during replay. Cannot happen if
                  --  Put refused the key when it was first written (S3),
                  --  unless Max_Entries shrank between runs.
               end;
            end if;
         when Delete =>
            if I /= 0 then
               T (Entry_Index (I)).Live := False;
               Live := Live - 1;
            end if;
      end case;
   end Apply;

   -------------
   -- Is_Open --
   -------------

   function Is_Open (S : Store) return Boolean is (S.Log.Opened);

   ----------
   -- Open --
   ----------

   procedure Open (S : out Store; Replayed : out Natural; Status : out Open_Status) is
      procedure Visit (R : Log_Record);
      procedure Visit (R : Log_Record) is
      begin
         Apply (S.Table, S.Live, R);
      end Visit;
      procedure Replay_All is new L.Scan (Visit);
   begin
      S.Table := [others => <>];
      S.Live := 0;
      L.Open (S.Log, Replayed, Status);
      if Status = Opened then
         Replay_All (S.Log);
      end if;
   end Open;

   ------------
   -- Unload --
   ------------

   procedure Unload (S : in out Store) is
   begin
      S.Table := [others => <>];
      S.Live := 0;
      S.Log.Opened := False;
   end Unload;

   ---------
   -- Put --
   ---------

   procedure Put (S : in out Store; K : Key; V : Value; Success : out Boolean) is
   begin
      if not S.Log.Opened then
         Success := False;
         return;
      end if;
      if Find (S.Table, K) = 0 and then Free_Slot (S.Table) = 0 then
         Success := False;  --  S3: refuse before touching the log
         return;
      end if;
      L.Append (S.Log, Record_Format.Put, K, V, Success);
      if Success then
         Apply (S.Table, S.Live,
                (Seq => S.Log.Last_Seq, Kind => Record_Format.Put, K => K, V => V));
      end if;
   end Put;

   ------------
   -- Delete --
   ------------

   procedure Delete (S : in out Store; K : Key; Success : out Boolean) is
      None : Value;
   begin
      if not S.Log.Opened then
         Success := False;
         return;
      end if;
      L.Append (S.Log, Record_Format.Delete, K, None, Success);
      if Success then
         Apply (S.Table, S.Live,
                (Seq => S.Log.Last_Seq, Kind => Record_Format.Delete, K => K, V => None));
      end if;
   end Delete;

   ---------
   -- Get --
   ---------

   procedure Get (S : Store; K : Key; V : out Value; Found : out Boolean) is
      I : Natural;
   begin
      if not S.Log.Opened then
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
     (if S.Log.Opened then S.Live else 0);

end Legder.Store;
