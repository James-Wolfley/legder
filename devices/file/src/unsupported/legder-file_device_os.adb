--  Selected when LEGDER_OS is not linux or windows.

package body Legder.File_Device_OS with SPARK_Mode => Off is

   pragma Compile_Time_Error
     (True, "Legder.File_Device supports only Linux and Windows; build with"
            & " -XLEGDER_OS=linux or -XLEGDER_OS=windows");

end Legder.File_Device_OS;
