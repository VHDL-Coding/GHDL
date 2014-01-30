--  GHDL Run Time (GRT) - VCD generator.
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
with Interfaces;
with Grt.Stdio; use Grt.Stdio;
with System.Storage_Elements; --  Work around GNAT bug.
pragma Unreferenced (System.Storage_Elements);
with Grt.Errors; use Grt.Errors;
with Grt.Signals; use Grt.Signals;
with Grt.Table;
with Grt.Astdio; use Grt.Astdio;
with Grt.C; use Grt.C;
with Grt.Hooks; use Grt.Hooks;
with Grt.Rtis; use Grt.Rtis;
with Grt.Rtis_Addr; use Grt.Rtis_Addr;
with Grt.Rtis_Types; use Grt.Rtis_Types;
with Grt.Vstrings;
pragma Elaborate_All (Grt.Table);

package body Grt.Vcd is
   --  If TRUE, put $date in vcd file.
   --  Can be set to FALSE to make vcd comparaison easier.
   Flag_Vcd_Date : Boolean := True;

   Stream : FILEs;

   procedure My_Vcd_Put (Str : String)
   is
      R : size_t;
      pragma Unreferenced (R);
   begin
      R := fwrite (Str'Address, Str'Length, 1, Stream);
   end My_Vcd_Put;

   procedure My_Vcd_Putc (C : Character)
   is
      R : int;
      pragma Unreferenced (R);
   begin
      R := fputc (Character'Pos (C), Stream);
   end My_Vcd_Putc;

   procedure My_Vcd_Close is
   begin
      fclose (Stream);
      Stream := NULL_Stream;
   end My_Vcd_Close;

   --  VCD filename.
   --  Stream corresponding to the VCD filename.
   --Vcd_Stream : FILEs;

   --  Index type of the table of vcd variables to dump.
   type Vcd_Index_Type is new Integer;

   --  Return TRUE if OPT is an option for VCD.
   function Vcd_Option (Opt : String) return Boolean
   is
      F : constant Natural := Opt'First;
      Mode : constant String := "wt" & NUL;
      Vcd_Filename : String_Access;
   begin
      if Opt'Length < 5 or else Opt (F .. F + 4) /= "--vcd" then
         return False;
      end if;
      if Opt'Length = 12 and then Opt (F + 5 .. F + 11) = "-nodate" then
         Flag_Vcd_Date := False;
         return True;
      end if;
      if Opt'Length > 6 and then Opt (F + 5) = '=' then
         if Vcd_Close /= null then
            Error ("--vcd: file already set");
            return True;
         end if;

         --  Add an extra NUL character.
         Vcd_Filename := new String (1 .. Opt'Length - 6 + 1);
         Vcd_Filename (1 .. Opt'Length - 6) := Opt (F + 6 .. Opt'Last);
         Vcd_Filename (Vcd_Filename'Last) := NUL;

         if Vcd_Filename.all = "-" & NUL then
            Stream := stdout;
         else
            Stream := fopen (Vcd_Filename.all'Address, Mode'Address);
            if Stream = NULL_Stream then
               Error_C ("cannot open ");
               Error_E (Vcd_Filename (Vcd_Filename'First
                                      .. Vcd_Filename'Last - 1));
               return True;
            end if;
         end if;
         Vcd_Putc := My_Vcd_Putc'Access;
         Vcd_Put := My_Vcd_Put'Access;
         Vcd_Close := My_Vcd_Close'Access;
         return True;
      else
         return False;
      end if;
   end Vcd_Option;

   procedure Vcd_Help is
   begin
      Put_Line (" --vcd=FILENAME     dump signal values into a VCD file");
      Put_Line (" --vcd-nodate       do not write date in VCD file");
   end Vcd_Help;

   procedure Vcd_Newline is
   begin
      Vcd_Putc (Nl);
   end Vcd_Newline;

   procedure Vcd_Putline (Str : String) is
   begin
      Vcd_Put (Str);
      Vcd_Newline;
   end Vcd_Putline;

--    procedure Vcd_Put (Str : Ghdl_Str_Len_Type)
--    is
--    begin
--       Put_Str_Len (Vcd_Stream, Str);
--    end Vcd_Put;

   procedure Vcd_Put_I32 (V : Ghdl_I32)
   is
      Str : String (1 .. 11);
      First : Natural;
   begin
      Vstrings.To_String (Str, First, V);
      Vcd_Put (Str (First .. Str'Last));
   end Vcd_Put_I32;

   procedure Vcd_Put_Idcode (N : Vcd_Index_Type)
   is
      Str : String (1 .. 8);
      V, R : Vcd_Index_Type;
      L : Natural;
   begin
      L := 0;
      V := N;
      loop
         R := V mod 93;
         V := V / 93;
         L := L + 1;
         Str (L) := Character'Val (33 + R);
         exit when V = 0;
      end loop;
      Vcd_Put (Str (1 .. L));
   end Vcd_Put_Idcode;

   procedure Vcd_Put_Name (Obj : VhpiHandleT)
   is
      Name : String (1 .. 128);
      Name_Len : Integer;
   begin
      Vhpi_Get_Str (VhpiNameP, Obj, Name, Name_Len);
      if Name_Len <= Name'Last then
         Vcd_Put (Name (1 .. Name_Len));
      else
         --  Truncate.
         Vcd_Put (Name);
      end if;
   end Vcd_Put_Name;

   procedure Vcd_Put_End is
   begin
      Vcd_Putline ("$end");
   end Vcd_Put_End;

   --  Called before elaboration.
   procedure Vcd_Init
   is
   begin
      if Vcd_Close = null then
         return;
      end if;
      if Flag_Vcd_Date then
         Vcd_Putline ("$date");
         Vcd_Put ("  ");
         declare
            type time_t is new Interfaces.Integer_64;
            Cur_Time : time_t;

            function time (Addr : Address) return time_t;
            pragma Import (C, time);

            function ctime (Timep: Address) return Ghdl_C_String;
            pragma Import (C, ctime);

            Ct : Ghdl_C_String;
         begin
            Cur_Time := time (Null_Address);
            Ct := ctime (Cur_Time'Address);
            for I in Positive loop
               exit when Ct (I) = NUL;
               Vcd_Putc (Ct (I));
            end loop;
            -- Note: ctime already append a LF.
         end;
         Vcd_Put_End;
      end if;
      Vcd_Putline ("$version");
      Vcd_Putline ("  GHDL v0");
      Vcd_Put_End;
      Vcd_Putline ("$timescale");
      Vcd_Putline ("  1 fs");
      Vcd_Put_End;
   end Vcd_Init;

   package Vcd_Table is new Grt.Table
     (Table_Component_Type => Verilog_Wire_Info,
      Table_Index_Type => Vcd_Index_Type,
      Table_Low_Bound => 0,
      Table_Initial => 32);

   procedure Avhpi_Error (Err : AvhpiErrorT)
   is
      pragma Unreferenced (Err);
   begin
      Put_Line ("Vcd.Avhpi_Error!");
      null;
   end Avhpi_Error;

   function Rti_To_Vcd_Kind (Rti : Ghdl_Rti_Access) return Vcd_Var_Kind
   is
      Rti1 : Ghdl_Rti_Access;
   begin
      if Rti.Kind = Ghdl_Rtik_Subtype_Scalar then
         Rti1 := To_Ghdl_Rtin_Subtype_Scalar_Acc (Rti).Basetype;
      else
         Rti1 := Rti;
      end if;

      if Rti1 = Std_Standard_Boolean_RTI_Ptr then
         return Vcd_Bool;
      end if;
      if Rti1 = Std_Standard_Bit_RTI_Ptr then
         return Vcd_Bit;
      end if;
      if Rti1 = Ieee_Std_Logic_1164_Std_Ulogic_RTI_Ptr then
         return Vcd_Stdlogic;
      end if;
      if Rti1.Kind = Ghdl_Rtik_Type_I32 then
         return Vcd_Integer32;
      end if;
      if Rti1.Kind = Ghdl_Rtik_Type_F64 then
         return Vcd_Float64;
      end if;
      return Vcd_Bad;
   end Rti_To_Vcd_Kind;

   function Rti_To_Vcd_Kind (Rti : Ghdl_Rtin_Type_Array_Acc)
                            return Vcd_Var_Kind
   is
      It : Ghdl_Rti_Access;
   begin
      if Rti.Nbr_Dim /= 1 then
         return Vcd_Bad;
      end if;
      It := Rti.Indexes (0);
      if It.Kind /= Ghdl_Rtik_Subtype_Scalar then
         return Vcd_Bad;
      end if;
      if To_Ghdl_Rtin_Subtype_Scalar_Acc (It).Basetype.Kind
        /= Ghdl_Rtik_Type_I32
      then
         return Vcd_Bad;
      end if;
      case Rti_To_Vcd_Kind (Rti.Element) is
         when Vcd_Bit =>
            return Vcd_Bitvector;
         when Vcd_Stdlogic =>
            return Vcd_Stdlogic_Vector;
         when others =>
            return Vcd_Bad;
      end case;
   end Rti_To_Vcd_Kind;

   procedure Get_Verilog_Wire (Sig : VhpiHandleT; Info : out Verilog_Wire_Info)
   is
      Sig_Type : VhpiHandleT;
      Rti : Ghdl_Rti_Access;
      Error : AvhpiErrorT;
      Sig_Addr : Address;
   begin
      --  Extract type of the signal.
      Vhpi_Handle (VhpiSubtype, Sig, Sig_Type, Error);
      if Error /= AvhpiErrorOk then
         Avhpi_Error (Error);
         return;
      end if;

      Rti := Avhpi_Get_Rti (Sig_Type);
      Sig_Addr := Avhpi_Get_Address (Sig);
      Info.Kind := Vcd_Bad;
      case Rti.Kind is
         when Ghdl_Rtik_Type_B2
           | Ghdl_Rtik_Type_E8
           | Ghdl_Rtik_Subtype_Scalar =>
            Info.Kind := Rti_To_Vcd_Kind (Rti);
            Info.Addr := Sig_Addr;
            Info.Irange := null;
         when Ghdl_Rtik_Subtype_Array =>
            declare
               St : Ghdl_Rtin_Subtype_Array_Acc;
            begin
               St := To_Ghdl_Rtin_Subtype_Array_Acc (Rti);
               Info.Kind := Rti_To_Vcd_Kind (St.Basetype);
               Info.Addr := Sig_Addr;
               Info.Irange := To_Ghdl_Range_Ptr
                 (Loc_To_Addr (St.Common.Depth, St.Bounds,
                               Avhpi_Get_Context (Sig)));
            end;
         when Ghdl_Rtik_Type_Array =>
            declare
               Uc : Ghdl_Uc_Array_Acc;
            begin
               Info.Kind := Rti_To_Vcd_Kind
                 (To_Ghdl_Rtin_Type_Array_Acc (Rti));
               Uc := To_Ghdl_Uc_Array_Acc (Sig_Addr);
               Info.Addr := Uc.Base;
               Info.Irange := To_Ghdl_Range_Ptr (Uc.Bounds);
            end;
         when others =>
            Info.Irange := null;
      end case;

      --  Do not allow null-array.
      if Info.Irange /= null and then Info.Irange.I32.Len = 0 then
         Info.Kind := Vcd_Bad;
         Info.Irange := null;
         return;
      end if;

      if Vhpi_Get_Kind (Sig) = VhpiPortDeclK then
         case Vhpi_Get_Mode (Sig) is
            when VhpiInMode
              | VhpiInoutMode
              | VhpiBufferMode
              | VhpiLinkageMode =>
               Info.Val := Vcd_Effective;
            when VhpiOutMode =>
               Info.Val := Vcd_Driving;
            when VhpiErrorMode =>
               Info.Kind := Vcd_Bad;
         end case;
      else
         Info.Val := Vcd_Effective;
      end if;
   end Get_Verilog_Wire;

   procedure Add_Signal (Sig : VhpiHandleT)
   is
      N : Vcd_Index_Type;
      Vcd_El : Verilog_Wire_Info;
   begin
      Get_Verilog_Wire (Sig, Vcd_El);

      if Vcd_El.Kind = Vcd_Bad then
         Vcd_Put ("$comment ");
         Vcd_Put_Name (Sig);
         Vcd_Put (" is not handled");
         --Vcd_Put (Ghdl_Type_Kind'Image (Desc.Kind));
         Vcd_Putc (' ');
         Vcd_Put_End;
         return;
      else
         Vcd_Table.Increment_Last;
         N := Vcd_Table.Last;

         Vcd_Table.Table (N) := Vcd_El;
         Vcd_Put ("$var ");
         case Vcd_El.Kind is
            when Vcd_Integer32 =>
               Vcd_Put ("integer 32");
            when Vcd_Float64 =>
               Vcd_Put ("real 64");
            when Vcd_Bool
              | Vcd_Bit
              | Vcd_Stdlogic =>
               Vcd_Put ("reg 1");
            when Vcd_Bitvector
              | Vcd_Stdlogic_Vector =>
               Vcd_Put ("reg ");
               Vcd_Put_I32 (Ghdl_I32 (Vcd_El.Irange.I32.Len));
            when Vcd_Bad =>
               null;
         end case;
         Vcd_Putc (' ');
         Vcd_Put_Idcode (N);
         Vcd_Putc (' ');
         Vcd_Put_Name (Sig);
         if Vcd_El.Irange /= null then
            Vcd_Putc ('[');
            Vcd_Put_I32 (Vcd_El.Irange.I32.Left);
            Vcd_Putc (':');
            Vcd_Put_I32 (Vcd_El.Irange.I32.Right);
            Vcd_Putc (']');
         end if;
         Vcd_Putc (' ');
         Vcd_Put_End;
         if Boolean'(False) then
            Vcd_Put ("$comment ");
            Vcd_Put_Name (Sig);
            Vcd_Put (" is ");
            case Vcd_El.Val is
               when Vcd_Effective =>
                  Vcd_Put ("effective ");
               when Vcd_Driving =>
                  Vcd_Put ("driving ");
            end case;
            Vcd_Put_End;
         end if;
      end if;
   end Add_Signal;

   procedure Vcd_Put_Hierarchy (Inst : VhpiHandleT)
   is
      Decl_It : VhpiHandleT;
      Decl : VhpiHandleT;
      Error : AvhpiErrorT;
   begin
      Vhpi_Iterator (VhpiDecls, Inst, Decl_It, Error);
      if Error /= AvhpiErrorOk then
         Avhpi_Error (Error);
         return;
      end if;

      --  Extract signals.
      loop
         Vhpi_Scan (Decl_It, Decl, Error);
         exit when Error = AvhpiErrorIteratorEnd;
         if Error /= AvhpiErrorOk then
            Avhpi_Error (Error);
            return;
         end if;

         case Vhpi_Get_Kind (Decl) is
            when VhpiPortDeclK
              | VhpiSigDeclK =>
               Add_Signal (Decl);
            when others =>
               null;
         end case;
      end loop;

      --  Extract sub-scopes.
      Vhpi_Iterator (VhpiInternalRegions, Inst, Decl_It, Error);
      if Error /= AvhpiErrorOk then
         Avhpi_Error (Error);
         return;
      end if;

      loop
         Vhpi_Scan (Decl_It, Decl, Error);
         exit when Error = AvhpiErrorIteratorEnd;
         if Error /= AvhpiErrorOk then
            Avhpi_Error (Error);
            return;
         end if;

         case Vhpi_Get_Kind (Decl) is
            when VhpiIfGenerateK
              | VhpiForGenerateK
              | VhpiBlockStmtK
              | VhpiCompInstStmtK =>
               Vcd_Put ("$scope module ");
               Vcd_Put_Name (Decl);
               Vcd_Putc (' ');
               Vcd_Put_End;
               Vcd_Put_Hierarchy (Decl);
               Vcd_Put ("$upscope ");
               Vcd_Put_End;
            when others =>
               null;
         end case;
      end loop;

   end Vcd_Put_Hierarchy;

   procedure Vcd_Put_Bit (V : Ghdl_B2)
   is
      C : Character;
   begin
      if V then
         C := '1';
      else
         C := '0';
      end if;
      Vcd_Putc (C);
   end Vcd_Put_Bit;

   procedure Vcd_Put_Stdlogic (V : Ghdl_E8)
   is
      type Map_Type is array (Ghdl_E8 range 0 .. 8) of Character;
      --                             "UX01ZWLH-"
   -- Map_Vlg : constant Map_Type := "xx01zz01x";
      Map_Std : constant Map_Type := "UX01ZWLH-";
   begin
      if V not in Map_Type'Range then
         Vcd_Putc ('?');
      else
         Vcd_Putc (Map_Std (V));
      end if;
   end Vcd_Put_Stdlogic;

   procedure Vcd_Put_Integer32 (V : Ghdl_U32)
   is
      Val : Ghdl_U32;
      N : Natural;
   begin
      Val := V;
      N := 32;
      while N > 1 loop
         exit when (Val and 16#8000_0000#) /= 0;
         Val := Val * 2;
         N := N - 1;
      end loop;

      while N > 0 loop
         if (Val and 16#8000_0000#) /= 0 then
            Vcd_Putc ('1');
         else
            Vcd_Putc ('0');
         end if;
         Val := Val * 2;
         N := N - 1;
      end loop;
   end Vcd_Put_Integer32;

   -- Using the floor attribute of Ghdl_F64 will result on a link error while
   -- trying to simulate a design. So it was needed to create a floor function
   function Digit_Floor (V : Ghdl_F64) return Ghdl_I32
   is
      Var : Ghdl_I32;
   begin
      -- V is always positive here and only of interest when it is a digit
      if V > 10.0 then
         return -1;
      else
         Var := Ghdl_I32(V-0.5); --Ghdl_I32 rounds to the nearest integer
         -- The rounding made by Ghdl_I32 is asymetric :
         -- 0.5 will be rounded to 1, but -0.5 to -1 instead of 0
         if Var > 0 then
            return Var;
         else
            return 0;
         end if;
      end if;
   end Digit_Floor;

   procedure Vcd_Put_Float64 (V : Ghdl_F64)
   is
      Val_tmp, Fact : Ghdl_F64;
      Digit, Exp, Delta_Exp, N_Exp : Ghdl_I32;
      --
   begin
      Exp := 0;
      if V /= V then
         Vcd_Put("NaN");
         return;
      end if;
      if V < 0.0 then
         Vcd_Putc ('-');
         Val_tmp := -V;
      elsif V = 0.0 then
         Vcd_Put("0.0");
         return;
      else
         Val_tmp := V;
      end if;
      if Val_tmp > Ghdl_F64'Last then
         Vcd_Put("Inf");
         return;
      elsif Val_tmp < 1.0 then
         Fact := 10.0;
         Delta_Exp := -1;
      else
         Fact := 0.1;
         Delta_Exp := 1;
      end if;

      -- Seek the first digit
      loop
         Digit := Digit_Floor(Val_tmp);
         if Digit > 0 then
            exit;
         end if;
         Exp := Exp + Delta_Exp;
         Val_tmp := Val_tmp * Fact;
      end loop;
      Vcd_Putc(Character'Val(Digit + 48));
      Vcd_Putc('.');
      for i in 0..4 loop -- 5 digits displayed after the point
         Val_tmp := abs(Val_tmp - Ghdl_F64(Digit))*10.0;
         Digit := Digit_Floor(Val_tmp);
         Vcd_Putc(Character'Val(Digit + 48));
      end loop;
      Vcd_Putc('E');
      if Exp < 0 then
         Vcd_Putc('-');
         Exp := -Exp;
      end if;
      N_Exp := 100;
      while N_Exp > 0 loop
         Vcd_Putc(Character'Val(Exp/N_Exp + 48));
         Exp := Exp mod N_Exp;
         N_Exp := N_Exp/10;
      end loop;
   end Vcd_Put_Float64;

   procedure Vcd_Put_Var (I : Vcd_Index_Type)
   is
      Addr : Address;
      V : Verilog_Wire_Info renames Vcd_Table.Table (I);
      Len : Ghdl_Index_Type;
   begin
      Addr := V.Addr;
      if V.Irange = null then
         Len := 1;
      else
         Len := V.Irange.I32.Len;
      end if;
      case V.Val is
         when Vcd_Effective =>
            case V.Kind is
               when Vcd_Bit
                 | Vcd_Bool =>
                  Vcd_Put_Bit (To_Signal_Arr_Ptr (Addr)(0).Value.B2);
               when Vcd_Stdlogic =>
                  Vcd_Put_Stdlogic (To_Signal_Arr_Ptr (Addr)(0).Value.E8);
               when Vcd_Integer32 =>
                  Vcd_Putc ('b');
                  Vcd_Put_Integer32 (To_Signal_Arr_Ptr (Addr)(0).Value.E32);
                  Vcd_Putc (' ');
               when Vcd_Float64 =>
                  Vcd_Putc ('r');
                  Vcd_Put_Float64 (To_Signal_Arr_Ptr (Addr)(0).Value.F64);
                  Vcd_Putc (' ');
               when Vcd_Bitvector =>
                  Vcd_Putc ('b');
                  for J in 0 .. Len - 1 loop
                     Vcd_Put_Bit (To_Signal_Arr_Ptr (Addr)(J).Value.B2);
                  end loop;
                  Vcd_Putc (' ');
               when Vcd_Stdlogic_Vector =>
                  Vcd_Putc ('b');
                  for J in 0 .. Len - 1 loop
                     Vcd_Put_Stdlogic (To_Signal_Arr_Ptr (Addr)(J).Value.E8);
                  end loop;
                  Vcd_Putc (' ');
               when Vcd_Bad =>
                  null;
            end case;
         when Vcd_Driving =>
            case V.Kind is
               when Vcd_Bit
                 | Vcd_Bool =>
                  Vcd_Put_Bit
                    (To_Signal_Arr_Ptr (Addr)(0).Driving_Value.B2);
               when Vcd_Stdlogic =>
                  Vcd_Put_Stdlogic
                    (To_Signal_Arr_Ptr (Addr)(0).Driving_Value.E8);
               when Vcd_Integer32 =>
                  Vcd_Putc ('b');
                  Vcd_Put_Integer32
                    (To_Signal_Arr_Ptr (Addr)(0).Driving_Value.E32);
                  Vcd_Putc (' ');
               when Vcd_Float64 =>
                  Vcd_Putc ('r');
                  Vcd_Put_Float64 (To_Signal_Arr_Ptr (Addr)(0)
                                           .Driving_Value.F64);
                  Vcd_Putc (' ');
               when Vcd_Bitvector =>
                  Vcd_Putc ('b');
                  for J in 0 .. Len - 1 loop
                     Vcd_Put_Bit
                       (To_Signal_Arr_Ptr (Addr)(J).Driving_Value.B2);
                  end loop;
                  Vcd_Putc (' ');
               when Vcd_Stdlogic_Vector =>
                  Vcd_Putc ('b');
                  for J in 0 .. Len - 1 loop
                     Vcd_Put_Stdlogic
                       (To_Signal_Arr_Ptr (Addr)(J).Driving_Value.E8);
                  end loop;
                  Vcd_Putc (' ');
               when Vcd_Bad =>
                  null;
            end case;
      end case;
      Vcd_Put_Idcode (I);
      Vcd_Newline;
   end Vcd_Put_Var;

   function Verilog_Wire_Changed (Info : Verilog_Wire_Info;
                                  Last : Std_Time)
                                 return Boolean
   is
      Len : Ghdl_Index_Type;
   begin
      if Info.Irange = null then
         Len := 1;
      else
         Len := Info.Irange.I32.Len;
      end if;

      case Info.Val is
         when Vcd_Effective =>
            case Info.Kind is
               when Vcd_Bit
                 | Vcd_Bool
                 | Vcd_Stdlogic
                 | Vcd_Bitvector
                 | Vcd_Stdlogic_Vector
                 | Vcd_Integer32
                 | Vcd_Float64 =>
                  for J in 0 .. Len - 1 loop
                     if To_Signal_Arr_Ptr (Info.Addr)(J).Last_Event = Last then
                        return True;
                     end if;
                  end loop;
               when Vcd_Bad =>
                  null;
            end case;
         when Vcd_Driving =>
            case Info.Kind is
               when Vcd_Bit
                 | Vcd_Bool
                 | Vcd_Stdlogic
                 | Vcd_Bitvector
                 | Vcd_Stdlogic_Vector
                 | Vcd_Integer32
                 | Vcd_Float64 =>
                  for J in 0 .. Len - 1 loop
                     if To_Signal_Arr_Ptr (Info.Addr)(J).Last_Active = Last
                     then
                        return True;
                     end if;
                  end loop;
               when Vcd_Bad =>
                  null;
            end case;
      end case;
      return False;
   end Verilog_Wire_Changed;

   procedure Vcd_Put_Time
   is
      Str : String (1 .. 21);
      First : Natural;
   begin
      Vcd_Putc ('#');
      Vstrings.To_String (Str, First, Ghdl_I64 (Cycle_Time));
      Vcd_Put (Str (First .. Str'Last));
      Vcd_Newline;
   end Vcd_Put_Time;

   procedure Vcd_Cycle;

   --  Called after elaboration.
   procedure Vcd_Start
   is
      Root : VhpiHandleT;
   begin
      --  Do nothing if there is no VCD file to generate.
      if Vcd_Close = null then
         return;
      end if;

      --  Be sure the RTI of std_ulogic is set.
      Search_Types_RTI;

      --  Put hierarchy.
      Get_Root_Inst (Root);
      Vcd_Put_Hierarchy (Root);

      --  End of header.
      Vcd_Put ("$enddefinitions ");
      Vcd_Put_End;

      Register_Cycle_Hook (Vcd_Cycle'Access);
   end Vcd_Start;

   --  Called before each non delta cycle.
   procedure Vcd_Cycle is
   begin
      --  Disp values.
      Vcd_Put_Time;
      if Cycle_Time = 0 then
         --  Disp all values.
         for I in Vcd_Table.First .. Vcd_Table.Last loop
            Vcd_Put_Var (I);
         end loop;
      else
         --  Disp only values changed.
         for I in Vcd_Table.First .. Vcd_Table.Last loop
            if Verilog_Wire_Changed (Vcd_Table.Table (I), Cycle_Time) then
               Vcd_Put_Var (I);
            end if;
         end loop;
      end if;
   end Vcd_Cycle;

   --  Called at the end of the simulation.
   procedure Vcd_End is
   begin
      if Vcd_Close /= null then
         Vcd_Close.all;
      end if;
   end Vcd_End;

   Vcd_Hooks : aliased constant Hooks_Type :=
     (Option => Vcd_Option'Access,
      Help => Vcd_Help'Access,
      Init => Vcd_Init'Access,
      Start => Vcd_Start'Access,
      Finish => Vcd_End'Access);

   procedure Register is
   begin
      Register_Hooks (Vcd_Hooks'Access);
   end Register;
end Grt.Vcd;
