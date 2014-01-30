--  GHDL Run Time (GRT) - 'value subprograms.
--  Copyright (C) 2002 - 2014 Tristan Gingold
--
--  GHDL is free software; you can redistribute it and/or modify it under
--  the terms of the GNU General Public License as published by the Free
--  Software Foundation; either version 2, or (at your option) any later
--  version.
--
--  GHDL is distributed in the hope that it will be useful, but WITHOUT ANY
--  WARRANTY; without even the implied warranty of MERCHANTABILITY or
--  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
--  for more details.
--
--  You should have received a copy of the GNU General Public License
--  along with GCC; see the file COPYING.  If not, write to the Free
--  Software Foundation, 59 Temple Place - Suite 330, Boston, MA
--  02111-1307, USA.
--
--  As a special exception, if other files instantiate generics from this
--  unit, or you link this unit with other files to produce an executable,
--  this unit does not by itself cause the resulting executable to be
--  covered by the GNU General Public License. This exception does not
--  however invalidate any other reasons why the executable file might be
--  covered by the GNU Public License.
with Grt.Types; use Grt.Types;
with Grt.Rtis; use Grt.Rtis;

package Grt.Values is
   function Ghdl_Value_B2 (Str : Std_String_Ptr; Rti : Ghdl_Rti_Access)
      return Ghdl_B2;
   function Ghdl_Value_E8 (Str : Std_String_Ptr; Rti : Ghdl_Rti_Access)
      return Ghdl_E8;
   function Ghdl_Value_E32 (Str : Std_String_Ptr; Rti : Ghdl_Rti_Access)
      return Ghdl_E32;
   function Ghdl_Value_I32 (Str : Std_String_Ptr) return Ghdl_I32;
   function Ghdl_Value_F64 (Str : Std_String_Ptr) return Ghdl_F64;
   function Ghdl_Value_P64 (Str : Std_String_Ptr; Rti : Ghdl_Rti_Access)
      return Ghdl_I64;
   function Ghdl_Value_P32 (Str : Std_String_Ptr; Rti : Ghdl_Rti_Access)
      return Ghdl_I32;
private
   pragma Export (Ada, Ghdl_Value_B2, "__ghdl_value_b2");
   pragma Export (C, Ghdl_Value_E8, "__ghdl_value_e8");
   pragma Export (C, Ghdl_Value_E32, "__ghdl_value_e32");
   pragma Export (C, Ghdl_Value_I32, "__ghdl_value_i32");
   pragma Export (C, Ghdl_Value_F64, "__ghdl_value_f64");
   pragma Export (C, Ghdl_Value_P64, "__ghdl_value_p64");
   pragma Export (C, Ghdl_Value_P32, "__ghdl_value_p32");
end Grt.Values;
