with Legder.Header; use Legder.Header;

package body Legder.Log with SPARK_Mode is

   ----------
   -- Open --
   ----------

   procedure Open (S : out State; Recovered : out Natural; Status : out Open_Status) is
      B     : Block;
      H     : Header.Header;
      HS    : Header.Status;
      R     : Log_Record;
      Valid : Boolean;
      Seq   : Sequence := 0;
      Head  : Position := 1;
   begin
      Recovered := 0;
      S := (Head => 1, Last_Seq => 0, Opened => False);

      Read (0, B);
      if (for all I in Block_Offset => B (I) = 16#FF#) then
         --  Erased block 0: a fresh store. The header becomes durable
         --  before any record can follow it.
         Header.Encode
           ((Version => Current_Version, K => K_Size, V => V_Size), B);
         Write (0, B);
         Sync;
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
         Read (I, B);
         Decode (B, K_Size, V_Size, R, Valid);
         exit when not Valid or else R.Seq /= Seq + 1;
         Seq := R.Seq;
         Head := Head + 1;
         Recovered := Recovered + 1;
      end loop;

      S := (Head => Head, Last_Seq => Seq, Opened => True);
      Status := Opened;
   end Open;

   ------------
   -- Append --
   ------------

   procedure Append (S : in out State; Kind : Op_Kind; K : Key; V : Value; Success : out Boolean) is
      B : Block;
      R : Log_Record;
   begin
      if Is_Full (S) then
         Success := False;
         return;
      end if;
      R := (Seq => S.Last_Seq + 1, Kind => Kind, K => K, V => V);
      Encode (R, K_Size, V_Size, B);
      Write (Block_Index (S.Head), B);
      Sync;
      S.Head := S.Head + 1;
      S.Last_Seq := R.Seq;
      Success := True;
   end Append;

   ----------
   -- Scan --
   ----------

   procedure Scan (S : State) is
      B     : Block;
      R     : Log_Record;
      Valid : Boolean;
   begin
      for P in 1 .. S.Head - 1 loop
         Read (Block_Index (P), B);
         Decode (B, K_Size, V_Size, R, Valid);
         --  Open established every block below Head is valid and
         --  consecutive. A False here means the device changed under
         --  us; stop rather than replay garbage.
         exit when not Valid;
         Visit (R);
      end loop;
   end Scan;

end Legder.Log;
