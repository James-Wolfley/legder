with Legder;
with Legder.RAM_Device;
with Legder.Store;

package Flow_Instances with SPARK_Mode is
   package Model is new Legder;
   package Device is new Model.RAM_Device;
   package KV is new Model.Store
     (Device.Last_Block, Device.Read, Device.Write, Device.Sync);
end Flow_Instances;
