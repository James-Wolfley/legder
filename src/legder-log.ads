--  Append-only write-ahead log. Block 0 holds the header.
--  The device must have one writer and stable reads throughout inspection,
--  replay, and finalization. A successful Sync persists all readable bytes,
--  including effects of failed writes. Recovery may include an update that
--  was not acknowledged.

with Legder.Record_Format; use Legder.Record_Format;

generic
   K_Size      : Key_Size;
   V_Size      : Value_Size;
   Block_Count : Block_Index;
   with procedure Read
     (Index : Block_Index; Data : out Block; Result : out Device_Result);
   with procedure Write
     (Index : Block_Index; Data : Block; Result : out Device_Result);
   with procedure Sync (Result : out Device_Result);
package Legder.Log with SPARK_Mode is

   subtype Position is Natural range 0 .. Max_Blocks;
   type Log_Phase is (Closed, Prepared, Ready);

   type State is record
      Head         : Position := 1;
      Last_Seq     : Sequence := 0;
      Phase        : Log_Phase := Closed;
      Needs_Header : Boolean := False;
   end record;

   function Is_Full (S : State) return Boolean is
     (S.Head > Natural (Block_Count));

   procedure Inspect
     (S : out State; Recovered : out Natural; Status : out Open_Status)
     with Pre  => Fits_In_Block (K_Size, V_Size),
          Post => (if Status = Opened then S.Phase = Prepared
                   else S.Phase = Closed)
                  and then (if Status = Storage_Failure then Recovered = 0);
   --  Read the candidate prefix without writing or synchronizing.

   procedure Open (S : in out State; Status : out Open_Status)
     with Post => (if Status = Opened then S.Phase = Ready
                   else S.Phase = Closed)
                  and then S.Head = S.Head'Old
                  and then S.Last_Seq = S.Last_Seq'Old;
   --  Finalize the prepared prefix and synchronize before permitting writes.

   procedure Append
     (S : in out State; Kind : Op_Kind; K : Key; V : Value;
      Result : out Update_Result)
     with Pre  => K.Length = K_Size
                  and then (if Kind = Put then V.Length = V_Size),
          Post => (if Result = Applied then
                      S.Phase = Ready
                      and then S.Head = S.Head'Old + 1
                      and then S.Last_Seq = S.Last_Seq'Old + 1
                   else
                      S.Head = S.Head'Old
                      and then S.Last_Seq = S.Last_Seq'Old
                      and then (if Result = Storage_Failure then S.Phase = Closed
                                else S.Phase = S.Phase'Old));

   generic
      with procedure Visit (R : Log_Record);
   procedure Scan (S : State; Complete : out Boolean);
   --  Visit the entire prepared or ready prefix, or report a read or
   --  validation failure. Callers must discard partial results on failure.

end Legder.Log;
