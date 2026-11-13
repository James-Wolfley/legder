with Legder.Header; use Legder.Header;

package body Legder.Log with SPARK_Mode is

   procedure Inspect
     (S : out State; Recovered : out Natural; Status : out Open_Status)
   is
      B      : Block;
      H      : Header.Header;
      HS     : Header.Status;
      R      : Log_Record;
      Valid  : Boolean;
      Result : Device_Result;
      Seq    : Sequence := 0;
      Head   : Position := 1;
      Needs_Header : Boolean := False;
   begin
      Recovered := 0;
      S := (others => <>);
      Read (0, B, Result);
      if Result = Failed then
         Status := Storage_Failure;
         return;
      end if;
      if (for all I in Block_Offset => B (I) = 16#FF#) then
         Needs_Header := True;
      else
         Header.Decode (B, H, HS);
         if HS /= Ok then
            Status := (if HS = Unsupported_Version
                       then Bad_Version else Bad_Header);
            return;
         end if;
         if H.K /= K_Size or else H.V /= V_Size then
            Status := Wrong_Sizes;
            return;
         end if;
      end if;

      for I in Block_Index range 1 .. Block_Count loop
         pragma Loop_Invariant (Head = Natural (I));
         pragma Loop_Invariant (Recovered = Natural (I) - 1);
         Read (I, B, Result);
         if Result = Failed then
            Recovered := 0;
            Status := Storage_Failure;
            return;
         end if;
         Decode (B, K_Size, V_Size, R, Valid);
         exit when not Valid or else R.Seq /= Seq + 1;
         Seq := R.Seq;
         Head := Head + 1;
         Recovered := Recovered + 1;
      end loop;

      S := (Head => Head, Last_Seq => Seq, Phase => Prepared,
            Needs_Header => Needs_Header);
      Status := Opened;
   end Inspect;

   procedure Open (S : in out State; Status : out Open_Status) is
      B      : Block;
      Result : Device_Result;
   begin
      if S.Phase /= Prepared then
         S.Phase := Closed;
         Status := Storage_Failure;
         return;
      end if;
      if S.Needs_Header then
         Header.Encode
           ((Version => Current_Version, K => K_Size, V => V_Size), B);
         Write (0, B, Result);
         if Result = Failed then
            S.Phase := Closed;
            Status := Storage_Failure;
            return;
         end if;
      end if;
      Sync (Result);
      if Result = Failed then
         S.Phase := Closed;
         Status := Storage_Failure;
         return;
      end if;
      S.Needs_Header := False;
      S.Phase := Ready;
      Status := Opened;
   end Open;

   procedure Append
     (S : in out State; Kind : Op_Kind; K : Key; V : Value;
      Result : out Update_Result)
   is
      B  : Block;
      R  : Log_Record;
      IO : Device_Result;
   begin
      if S.Phase /= Ready then
         Result := Closed;
         return;
      end if;
      if Is_Full (S) then
         Result := No_Space;
         return;
      end if;
      R := (Seq => S.Last_Seq + 1, Kind => Kind, K => K, V => V);
      Encode (R, K_Size, V_Size, B);
      Write (Block_Index (S.Head), B, IO);
      if IO = Failed then
         S.Phase := Closed;
         Result := Storage_Failure;
         return;
      end if;
      Sync (IO);
      if IO = Failed then
         S.Phase := Closed;
         Result := Storage_Failure;
         return;
      end if;
      S.Head := S.Head + 1;
      S.Last_Seq := R.Seq;
      Result := Applied;
   end Append;

   procedure Scan (S : State; Complete : out Boolean) is
      B     : Block;
      R     : Log_Record;
      Valid : Boolean;
      IO    : Device_Result;
      Seq   : Sequence := 0;
   begin
      Complete := False;
      if S.Phase = Closed or else S.Head = 0 then
         return;
      end if;
      for P in 1 .. S.Head - 1 loop
         Read (Block_Index (P), B, IO);
         if IO = Failed then
            return;
         end if;
         Decode (B, K_Size, V_Size, R, Valid);
         if not Valid or else R.Seq /= Seq + 1 then
            return;
         end if;
         Seq := R.Seq;
         Visit (R);
      end loop;
      Complete := Seq = S.Last_Seq;
   end Scan;

end Legder.Log;
