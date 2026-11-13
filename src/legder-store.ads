--  The store: a bounded key-value map, durable through Legder.Log.
--  Updates synchronize the log before changing the in-memory table.

with Legder.Log;

generic
   K_Size      : Key_Size;
   V_Size      : Value_Size;
   Block_Count : Block_Index;
   with procedure Read
     (Index : Block_Index; Data : out Block; Result : out Device_Result);
   with procedure Write
     (Index : Block_Index; Data : Block; Result : out Device_Result);
   with procedure Sync (Result : out Device_Result);
   Capacity : Positive := 256;
package Legder.Store with SPARK_Mode is

   Max_Entries : constant Positive := Capacity;

   type Store is limited private;

   function Is_Open (S : Store) return Boolean;

   procedure Open (S : out Store; Replayed : out Natural; Status : out Open_Status)
     with Pre  => Fits_In_Block (K_Size, V_Size),
          Post => (if Status = Opened then Is_Open (S) else not Is_Open (S));
   --  Replayed counts the validated prefix, including on capacity refusal.
   --  Capacity_Exceeded means the final live set does not fit. The table
   --  is empty, the store closed, and the log untouched. Storage_Failure
   --  leaves the table empty and Replayed zero, but may follow a write.
   --  Open takes O (Replayed**2) time and O (Capacity) space in the worst case.

   procedure Unload (S : in out Store)
     with Post => not Is_Open (S);
   --  Discards the in-memory table without device I/O.

   procedure Put (S : in out Store; K : Key; V : Value; Result : out Update_Result)
     with Pre => K.Length = K_Size and then V.Length = V_Size;
   --  Applied after synchronization. No_Space means the log or table is
   --  full. Storage_Failure closes the store and discards its table.

   procedure Delete (S : in out Store; K : Key; Result : out Update_Result)
     with Pre => K.Length = K_Size;
   --  Applied after synchronization, including for an absent key.
   --  Closed calls do no device I/O.

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
