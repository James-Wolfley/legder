--  The store: a bounded key-value map, durable through Legder.Log.
--
--  This is what applications use. Put and Delete commit to the log
--  before they touch the in-memory table, so the table is always a
--  replay of the log. Open replays the log to rebuild the table.
--
--  The in-memory table in the seed is a PLACEHOLDER: a linear array
--  scanned on every Get. Correct, slow, and the thing to replace with
--  a real index (sorted array, hash, B-tree) once the crash tests
--  pass. Do not touch the commit order while doing so.
--
--  PROOF TARGET (the whole point of the project)
--    S1  After Open, for every key K: Get (K) is the value of the last
--        Put (K) in the committed log, or absent if the last operation
--        on K was Delete or there was none.
--    S2  Put/Delete change the table only after Append returned
--        Success, so a crash at any point leaves the table rebuilt by
--        Open equal to what the log says (S1 applied to the prefix).
--    S3  Capacity: the table never overflows; Put on a full table with
--        a new key fails before writing to the log.
--  S1 is the target for the year. State it as a ghost model (a
--  functional map) and prove Put, Delete and Open against it.

with Legder.Log;

generic
   K_Size      : Key_Size;
   V_Size      : Value_Size;
   Block_Count : Block_Index;
   with procedure Read  (Index : Block_Index; Data : out Block);
   with procedure Write (Index : Block_Index; Data : Block);
   with procedure Sync;
   Capacity : Positive := 256;
package Legder.Store with SPARK_Mode is

   Max_Entries : constant Positive := Capacity;
   --  Live keys the table can hold, fixed at instantiation. Bounded; a
   --  full table refuses new keys rather than allocating.

   type Store is limited private;

   function Is_Open (S : Store) return Boolean;
   --  True after a successful Open, until Unload.

   procedure Open (S : out Store; Replayed : out Natural; Status : out Open_Status)
     with Pre  => Fits_In_Block (K_Size, V_Size),
          Post => (if Status = Opened then Is_Open (S) else not Is_Open (S));
   --  Recovers from the device. Replayed is the number of committed
   --  records in the validated prefix, even when the capacity check
   --  refuses. Replay keeps only the last live Put for each key, so it
   --  accepts any log whose final live set fits Capacity, whatever its
   --  peak. Only Status = Opened leaves a usable store. Capacity_Exceeded
   --  means the final live set does not fit; the table is empty, the
   --  store closed, and the log untouched. Worst case Open takes time
   --  quadratic in Replayed and uses O (Capacity) space.

   procedure Unload (S : in out Store)
     with Post => not Is_Open (S);
   --  Discards the in-memory table. The log stays durable on the
   --  device; no device I/O. Safe to repeat.

   procedure Put (S : in out Store; K : Key; V : Value; Success : out Boolean)
     with Pre => K.Length = K_Size and then V.Length = V_Size;
   --  Durable on return with Success. False when the log is full or
   --  the table is full and K is new. On a closed store, False with
   --  no device I/O and no table change.

   procedure Delete (S : in out Store; K : Key; Success : out Boolean)
     with Pre => K.Length = K_Size;
   --  Durable on return with Success. Deleting an absent key is a
   --  successful no-op that still writes a record (simplest correct
   --  behaviour; optimising it away is fine once S1 is proved).
   --  On a closed store, False with no device I/O and no table change.

   procedure Get (S : Store; K : Key; V : out Value; Found : out Boolean)
     with Pre => K.Length = K_Size;
   --  On a closed store, V is zero and Found is False.

   function Count (S : Store) return Natural;
   --  Live keys. Zero on a closed store.

private

   type Entry_Rec is record
      Live : Boolean := False;
      K    : Key;
      V    : Value;
   end record;

   subtype Entry_Index is Positive range 1 .. Capacity;
   type Entry_Array is array (Entry_Index) of Entry_Rec;

   package L is new Legder.Log (K_Size, V_Size, Block_Count, Read, Write, Sync);

   type Store is limited record
      Log   : L.State;
      Table : Entry_Array;
      Live  : Natural := 0;
   end record;

end Legder.Store;
