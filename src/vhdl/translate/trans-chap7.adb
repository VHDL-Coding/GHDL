--  Iir to ortho translator.
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

with Ada.Text_IO;
with Name_Table;
with Iirs_Utils; use Iirs_Utils;
with Iir_Chains; use Iir_Chains;
with Std_Package; use Std_Package;
with Errorout; use Errorout;
with Flags; use Flags;
with Canon;
with Evaluation; use Evaluation;
with Trans.Chap3;
with Trans.Chap4;
with Trans.Chap6;
with Trans.Chap8;
with Trans.Chap14;
with Trans.Rtis;
with Trans_Decls; use Trans_Decls;
with Trans.Helpers2; use Trans.Helpers2;
with Trans.Foreach_Non_Composite;

package body Trans.Chap7 is
   use Trans.Helpers;

   function Is_Static_Constant (Decl : Iir_Constant_Declaration) return Boolean
   is
      Expr  : constant Iir := Get_Default_Value (Decl);
      Atype : Iir;
      Info  : Iir;
   begin
      if Expr = Null_Iir
        or else Get_Kind (Expr) = Iir_Kind_Overflow_Literal
      then
         --  Deferred constant.
         return False;
      end if;

      if Get_Expr_Staticness (Decl) = Locally then
         return True;
      end if;

      --  Only aggregates are handled.
      if Get_Kind (Expr) /= Iir_Kind_Aggregate then
         return False;
      end if;

      Atype := Get_Type (Decl);
      --  Bounds must be known (and static).
      if Get_Type_Staticness (Atype) /= Locally then
         return False;
      end if;

      --  Currently, only array aggregates are handled.
      if Get_Kind (Get_Base_Type (Atype)) /= Iir_Kind_Array_Type_Definition
      then
         return False;
      end if;

      --  Aggregate elements must be locally static.
      --  Note: this does not yet handled aggregates of aggregates.
      if Get_Value_Staticness (Expr) /= Locally then
         return False;
      end if;
      Info := Get_Aggregate_Info (Expr);
      while Info /= Null_Iir loop
         if Get_Aggr_Dynamic_Flag (Info) then
            raise Internal_Error;
         end if;

         --  Currently, only positionnal aggregates are handled.
         if Get_Aggr_Named_Flag (Info) then
            return False;
         end if;
         --  Currently, others choice are not handled.
         if Get_Aggr_Others_Flag (Info) then
            return False;
         end if;

         Info := Get_Sub_Aggregate_Info (Info);
      end loop;
      return True;
   end Is_Static_Constant;

   procedure Translate_Static_String_Literal_Inner
     (List : in out O_Array_Aggr_List;
      Str     : Iir;
      El_Type : Iir)
   is
      use Name_Table;

      Literal_List : constant Iir_List :=
        Get_Enumeration_Literal_List (Get_Base_Type (El_Type));
      Len          : constant Nat32 := Get_String_Length (Str);
      Ptr          : constant String_Fat_Acc := Get_String_Fat_Acc (Str);
      Lit          : Iir;
   begin
      for I in 1 .. Len loop
         Lit := Find_Name_In_List (Literal_List, Get_Identifier (Ptr (I)));
         New_Array_Aggr_El (List, Get_Ortho_Expr (Lit));
      end loop;
   end Translate_Static_String_Literal_Inner;

   procedure Translate_Static_Bit_String_Literal_Inner
     (List    : in out O_Array_Aggr_List;
      Lit     : Iir_Bit_String_Literal;
      El_Type : Iir)
   is
      pragma Unreferenced (El_Type);
      L_0 : constant O_Cnode := Get_Ortho_Expr (Get_Bit_String_0 (Lit));
      L_1 : constant O_Cnode := Get_Ortho_Expr (Get_Bit_String_1 (Lit));
      Ptr : constant String_Fat_Acc := Get_String_Fat_Acc (Lit);
      Len : constant Nat32 := Get_String_Length (Lit);
      V   : O_Cnode;
   begin
      for I in 1 .. Len loop
         case Ptr (I) is
            when '0' =>
               V := L_0;
            when '1' =>
               V := L_1;
            when others =>
               raise Internal_Error;
         end case;
         New_Array_Aggr_El (List, V);
      end loop;
   end Translate_Static_Bit_String_Literal_Inner;

   procedure Translate_Static_Aggregate_1 (List    : in out O_Array_Aggr_List;
                                           Aggr    : Iir;
                                           Info    : Iir;
                                           El_Type : Iir)
   is
      N_Info : constant Iir := Get_Sub_Aggregate_Info (Info);
      Assoc  : Iir;
      Sub    : Iir;
   begin
      case Get_Kind (Aggr) is
         when Iir_Kind_Aggregate =>
            Assoc := Get_Association_Choices_Chain (Aggr);
            while Assoc /= Null_Iir loop
               Sub := Get_Associated_Expr (Assoc);
               case Get_Kind (Assoc) is
                  when Iir_Kind_Choice_By_None =>
                     if N_Info = Null_Iir then
                        New_Array_Aggr_El
                          (List, Translate_Static_Expression (Sub, El_Type));
                     else
                        Translate_Static_Aggregate_1
                          (List, Sub, N_Info, El_Type);
                     end if;
                  when others =>
                     Error_Kind ("translate_static_aggregate_1(2)", Assoc);
               end case;
               Assoc := Get_Chain (Assoc);
            end loop;
         when Iir_Kind_String_Literal =>
            if N_Info /= Null_Iir then
               raise Internal_Error;
            end if;
            Translate_Static_String_Literal_Inner (List, Aggr, El_Type);
         when Iir_Kind_Bit_String_Literal =>
            if N_Info /= Null_Iir then
               raise Internal_Error;
            end if;
            Translate_Static_Bit_String_Literal_Inner (List, Aggr, El_Type);
         when others =>
            Error_Kind ("translate_static_aggregate_1", Aggr);
      end case;
   end Translate_Static_Aggregate_1;

   function Translate_Static_Aggregate (Aggr : Iir) return O_Cnode
   is
      Aggr_Type : constant Iir := Get_Type (Aggr);
      El_Type   : constant Iir := Get_Element_Subtype (Aggr_Type);
      List      : O_Array_Aggr_List;
      Res       : O_Cnode;
   begin
      Chap3.Translate_Anonymous_Type_Definition (Aggr_Type, True);
      Start_Array_Aggr (List, Get_Ortho_Type (Aggr_Type, Mode_Value));

      Translate_Static_Aggregate_1
        (List, Aggr, Get_Aggregate_Info (Aggr), El_Type);
      Finish_Array_Aggr (List, Res);
      return Res;
   end Translate_Static_Aggregate;

   function Translate_Static_Simple_Aggregate (Aggr : Iir) return O_Cnode
   is
      Aggr_Type : constant Iir := Get_Type (Aggr);
      El_List   : constant Iir_List := Get_Simple_Aggregate_List (Aggr);
      El_Type   : constant Iir := Get_Element_Subtype (Aggr_Type);
      El        : Iir;
      List      : O_Array_Aggr_List;
      Res       : O_Cnode;
   begin
      Chap3.Translate_Anonymous_Type_Definition (Aggr_Type, True);
      Start_Array_Aggr (List, Get_Ortho_Type (Aggr_Type, Mode_Value));

      for I in Natural loop
         El := Get_Nth_Element (El_List, I);
         exit when El = Null_Iir;
         New_Array_Aggr_El
           (List, Translate_Static_Expression (El, El_Type));
      end loop;

      Finish_Array_Aggr (List, Res);
      return Res;
   end Translate_Static_Simple_Aggregate;

   function Translate_Static_String_Literal (Str : Iir) return O_Cnode
   is
      use Name_Table;

      Lit_Type     : constant Iir := Get_Type (Str);
      Element_Type : constant Iir := Get_Element_Subtype (Lit_Type);
      Arr_Type     : O_Tnode;
      List         : O_Array_Aggr_List;
      Res          : O_Cnode;
   begin
      Chap3.Translate_Anonymous_Type_Definition (Lit_Type, True);
      Arr_Type := Get_Ortho_Type (Lit_Type, Mode_Value);

      Start_Array_Aggr (List, Arr_Type);

      Translate_Static_String_Literal_Inner (List, Str, Element_Type);

      Finish_Array_Aggr (List, Res);
      return Res;
   end Translate_Static_String_Literal;

   --  Create a variable (constant) for string or bit string literal STR.
   --  The type of the literal element is ELEMENT_TYPE, and the ortho type
   --  of the string (a constrained array type) is STR_TYPE.
   function Create_String_Literal_Var_Inner
     (Str : Iir; Element_Type : Iir; Str_Type : O_Tnode) return Var_Type
   is
      use Name_Table;

      Val_Aggr : O_Array_Aggr_List;
      Res      : O_Cnode;
   begin
      Start_Array_Aggr (Val_Aggr, Str_Type);
      case Get_Kind (Str) is
         when Iir_Kind_String_Literal =>
            Translate_Static_String_Literal_Inner
              (Val_Aggr, Str, Element_Type);
         when Iir_Kind_Bit_String_Literal =>
            Translate_Static_Bit_String_Literal_Inner
              (Val_Aggr, Str, Element_Type);
         when others =>
            raise Internal_Error;
      end case;
      Finish_Array_Aggr (Val_Aggr, Res);

      return Create_Global_Const
        (Create_Uniq_Identifier, Str_Type, O_Storage_Private, Res);
   end Create_String_Literal_Var_Inner;

   --  Create a variable (constant) for string or bit string literal STR.
   function Create_String_Literal_Var (Str : Iir) return Var_Type
   is
      use Name_Table;

      Str_Type : constant Iir := Get_Type (Str);
      Arr_Type : O_Tnode;
   begin
      --  Create the string value.
      Arr_Type := New_Constrained_Array_Type
        (Get_Info (Str_Type).T.Base_Type (Mode_Value),
         New_Unsigned_Literal (Ghdl_Index_Type,
           Unsigned_64 (Get_String_Length (Str))));

      return Create_String_Literal_Var_Inner
        (Str, Get_Element_Subtype (Str_Type), Arr_Type);
   end Create_String_Literal_Var;

   --  Some strings literal have an unconstrained array type,
   --  eg: 'image of constant.  Its type is not constrained
   --  because it is not so in VHDL!
   function Translate_Non_Static_String_Literal (Str : Iir) return O_Enode
   is
      use Name_Table;

      Lit_Type        : constant Iir := Get_Type (Str);
      Type_Info       : constant Type_Info_Acc := Get_Info (Lit_Type);
      Index_Type      : constant Iir := Get_Index_Type (Lit_Type, 0);
      Index_Type_Info : constant Type_Info_Acc := Get_Info (Index_Type);
      Bound_Aggr      : O_Record_Aggr_List;
      Index_Aggr      : O_Record_Aggr_List;
      Res_Aggr        : O_Record_Aggr_List;
      Res             : O_Cnode;
      Len             : Int32;
      Val             : Var_Type;
      Bound           : Var_Type;
      R               : O_Enode;
   begin
      --  Create the string value.
      Len := Get_String_Length (Str);
      Val := Create_String_Literal_Var (Str);

      if Type_Info.Type_Mode = Type_Mode_Fat_Array then
         --  Create the string bound.
         Start_Record_Aggr (Bound_Aggr, Type_Info.T.Bounds_Type);
         Start_Record_Aggr (Index_Aggr, Index_Type_Info.T.Range_Type);
         New_Record_Aggr_El
           (Index_Aggr,
            New_Signed_Literal
              (Index_Type_Info.Ortho_Type (Mode_Value), 0));
         New_Record_Aggr_El
           (Index_Aggr,
            New_Signed_Literal (Index_Type_Info.Ortho_Type (Mode_Value),
              Integer_64 (Len - 1)));
         New_Record_Aggr_El
           (Index_Aggr, Ghdl_Dir_To_Node);
         New_Record_Aggr_El
           (Index_Aggr,
            New_Unsigned_Literal (Ghdl_Index_Type, Unsigned_64 (Len)));
         Finish_Record_Aggr (Index_Aggr, Res);
         New_Record_Aggr_El (Bound_Aggr, Res);
         Finish_Record_Aggr (Bound_Aggr, Res);
         Bound := Create_Global_Const
           (Create_Uniq_Identifier, Type_Info.T.Bounds_Type,
            O_Storage_Private, Res);

         --  The descriptor.
         Start_Record_Aggr (Res_Aggr, Type_Info.Ortho_Type (Mode_Value));
         New_Record_Aggr_El
           (Res_Aggr,
            New_Global_Address (Get_Var_Label (Val),
              Type_Info.T.Base_Ptr_Type (Mode_Value)));
         New_Record_Aggr_El
           (Res_Aggr,
            New_Global_Address (Get_Var_Label (Bound),
              Type_Info.T.Bounds_Ptr_Type));
         Finish_Record_Aggr (Res_Aggr, Res);

         Val := Create_Global_Const
           (Create_Uniq_Identifier, Type_Info.Ortho_Type (Mode_Value),
            O_Storage_Private, Res);
      elsif Type_Info.Type_Mode = Type_Mode_Array then
         --  Type of string literal isn't statically known; check the
         --  length.
         Chap6.Check_Bound_Error
           (New_Compare_Op
              (ON_Neq,
               New_Lit (New_Index_Lit (Unsigned_64 (Len))),
               Chap3.Get_Array_Type_Length (Lit_Type),
               Ghdl_Bool_Type),
            Str, 1);
      else
         raise Internal_Error;
      end if;

      R := New_Address (Get_Var (Val),
                        Type_Info.Ortho_Ptr_Type (Mode_Value));
      return R;
   end Translate_Non_Static_String_Literal;

   --  Only for Strings of STD.Character.
   function Translate_Static_String (Str_Type : Iir; Str_Ident : Name_Id)
                                    return O_Cnode
   is
      use Name_Table;

      Literal_List : Iir_List;
      Lit          : Iir;
      List         : O_Array_Aggr_List;
      Res          : O_Cnode;
   begin
      Chap3.Translate_Anonymous_Type_Definition (Str_Type, True);

      Start_Array_Aggr (List, Get_Ortho_Type (Str_Type, Mode_Value));

      Literal_List := Get_Enumeration_Literal_List (Character_Type_Definition);
      Image (Str_Ident);
      for I in 1 .. Name_Length loop
         Lit := Get_Nth_Element (Literal_List,
                                 Character'Pos (Name_Buffer (I)));
         New_Array_Aggr_El (List, Get_Ortho_Expr (Lit));
      end loop;

      Finish_Array_Aggr (List, Res);
      return Res;
   end Translate_Static_String;

   function Translate_Static_Bit_String_Literal (Lit : Iir_Bit_String_Literal)
                                                return O_Cnode
   is
      Lit_Type : constant Iir := Get_Type (Lit);
      Res      : O_Cnode;
      List     : O_Array_Aggr_List;
   begin
      Chap3.Translate_Anonymous_Type_Definition (Lit_Type, True);
      Start_Array_Aggr (List, Get_Ortho_Type (Lit_Type, Mode_Value));
      Translate_Static_Bit_String_Literal_Inner (List, Lit, Lit_Type);
      Finish_Array_Aggr (List, Res);
      return Res;
   end Translate_Static_Bit_String_Literal;

   function Translate_String_Literal (Str : Iir) return O_Enode
   is
      Str_Type : constant Iir := Get_Type (Str);
      Var      : Var_Type;
      Info     : Type_Info_Acc;
      Res      : O_Cnode;
      R        : O_Enode;
   begin
      if Get_Constraint_State (Str_Type) = Fully_Constrained
        and then Get_Type_Staticness (Get_Index_Type (Str_Type, 0)) = Locally
      then
         Chap3.Create_Array_Subtype (Str_Type, True);
         case Get_Kind (Str) is
            when Iir_Kind_String_Literal =>
               Res := Translate_Static_String_Literal (Str);
            when Iir_Kind_Bit_String_Literal =>
               Res := Translate_Static_Bit_String_Literal (Str);
            when Iir_Kind_Simple_Aggregate =>
               Res := Translate_Static_Simple_Aggregate (Str);
            when Iir_Kind_Simple_Name_Attribute =>
               Res := Translate_Static_String
                 (Get_Type (Str), Get_Simple_Name_Identifier (Str));
            when others =>
               raise Internal_Error;
         end case;
         Info := Get_Info (Str_Type);
         Var := Create_Global_Const
           (Create_Uniq_Identifier, Info.Ortho_Type (Mode_Value),
            O_Storage_Private, Res);
         R := New_Address (Get_Var (Var), Info.Ortho_Ptr_Type (Mode_Value));
         return R;
      else
         return Translate_Non_Static_String_Literal (Str);
      end if;
   end Translate_String_Literal;

   function Translate_Static_Implicit_Conv
     (Expr : O_Cnode; Expr_Type : Iir; Res_Type : Iir) return O_Cnode
   is
      Expr_Info : Type_Info_Acc;
      Res_Info  : Type_Info_Acc;
      Val       : Var_Type;
      Res       : O_Cnode;
      List      : O_Record_Aggr_List;
      Bound     : Var_Type;
   begin
      if Res_Type = Expr_Type then
         return Expr;
      end if;
      if Get_Kind (Expr_Type) /= Iir_Kind_Array_Subtype_Definition then
         raise Internal_Error;
      end if;
      if Get_Kind (Res_Type) = Iir_Kind_Array_Subtype_Definition then
         return Expr;
      end if;
      if Get_Kind (Res_Type) /= Iir_Kind_Array_Type_Definition then
         raise Internal_Error;
      end if;
      Expr_Info := Get_Info (Expr_Type);
      Res_Info := Get_Info (Res_Type);
      Val := Create_Global_Const
        (Create_Uniq_Identifier, Expr_Info.Ortho_Type (Mode_Value),
         O_Storage_Private, Expr);
      Bound := Expr_Info.T.Array_Bounds;
      if Bound = Null_Var then
         Bound := Create_Global_Const
           (Create_Uniq_Identifier, Expr_Info.T.Bounds_Type,
            O_Storage_Private,
            Chap3.Create_Static_Array_Subtype_Bounds (Expr_Type));
         Expr_Info.T.Array_Bounds := Bound;
      end if;

      Start_Record_Aggr (List, Res_Info.Ortho_Type (Mode_Value));
      New_Record_Aggr_El
        (List, New_Global_Address (Get_Var_Label (Val),
         Res_Info.T.Base_Ptr_Type (Mode_Value)));
      New_Record_Aggr_El
        (List, New_Global_Address (Get_Var_Label (Bound),
         Expr_Info.T.Bounds_Ptr_Type));
      Finish_Record_Aggr (List, Res);
      return Res;
   end Translate_Static_Implicit_Conv;

   function Translate_Numeric_Literal (Expr : Iir; Res_Type : O_Tnode)
                                      return O_Cnode is
   begin
      case Get_Kind (Expr) is
         when Iir_Kind_Integer_Literal =>
            return New_Signed_Literal
              (Res_Type, Integer_64 (Get_Value (Expr)));

         when Iir_Kind_Enumeration_Literal =>
            return Get_Ortho_Expr (Get_Enumeration_Decl (Expr));

         when Iir_Kind_Floating_Point_Literal =>
            return New_Float_Literal
              (Res_Type, IEEE_Float_64 (Get_Fp_Value (Expr)));

         when Iir_Kind_Physical_Int_Literal
            | Iir_Kind_Physical_Fp_Literal
            | Iir_Kind_Unit_Declaration =>
            return New_Signed_Literal
              (Res_Type, Integer_64 (Get_Physical_Value (Expr)));

         when others =>
            Error_Kind ("translate_numeric_literal", Expr);
      end case;
   exception
      when Constraint_Error =>
         --  Can be raised by Get_Physical_Unit_Value because of the kludge
         --  on staticness.
         Error_Msg_Elab ("numeric literal not in range", Expr);
         return New_Signed_Literal (Res_Type, 0);
   end Translate_Numeric_Literal;

   function Translate_Numeric_Literal (Expr : Iir; Res_Type : Iir)
                                      return O_Cnode
   is
      Expr_Type  : constant Iir := Get_Type (Expr);
      Expr_Otype : O_Tnode;
      Tinfo      : Type_Info_Acc;
   begin
      Tinfo := Get_Info (Expr_Type);
      if Res_Type /= Null_Iir then
         Expr_Otype := Get_Ortho_Type (Res_Type, Mode_Value);
      else
         if Tinfo = null then
            --  FIXME: this is a working kludge, in the case where EXPR_TYPE
            --  is a subtype which was not yet translated.
            --  (eg: evaluated array attribute)
            Tinfo := Get_Info (Get_Base_Type (Expr_Type));
         end if;
         Expr_Otype := Tinfo.Ortho_Type (Mode_Value);
      end if;
      return Translate_Numeric_Literal (Expr, Expr_Otype);
   end Translate_Numeric_Literal;

   function Translate_Static_Expression (Expr : Iir; Res_Type : Iir)
                                        return O_Cnode
   is
      Expr_Type : constant Iir := Get_Type (Expr);
   begin
      case Get_Kind (Expr) is
         when Iir_Kind_Integer_Literal
            | Iir_Kind_Enumeration_Literal
            | Iir_Kind_Floating_Point_Literal
            | Iir_Kind_Physical_Int_Literal
            | Iir_Kind_Unit_Declaration
            | Iir_Kind_Physical_Fp_Literal =>
            return Translate_Numeric_Literal (Expr, Res_Type);

         when Iir_Kind_String_Literal =>
            return Translate_Static_Implicit_Conv
              (Translate_Static_String_Literal (Expr), Expr_Type, Res_Type);
         when Iir_Kind_Bit_String_Literal =>
            return Translate_Static_Implicit_Conv
              (Translate_Static_Bit_String_Literal (Expr),
               Expr_Type, Res_Type);
         when Iir_Kind_Simple_Aggregate =>
            return Translate_Static_Implicit_Conv
              (Translate_Static_Simple_Aggregate (Expr),
               Expr_Type, Res_Type);
         when Iir_Kind_Aggregate =>
            return Translate_Static_Implicit_Conv
              (Translate_Static_Aggregate (Expr), Expr_Type, Res_Type);

         when Iir_Kinds_Denoting_Name =>
            return Translate_Static_Expression
              (Get_Named_Entity (Expr), Res_Type);
         when others =>
            Error_Kind ("translate_static_expression", Expr);
      end case;
   end Translate_Static_Expression;

   function Translate_Static_Range_Left
     (Expr : Iir; Range_Type : Iir := Null_Iir) return O_Cnode
   is
      Bound : constant Iir := Get_Left_Limit (Expr);
      Left  : O_Cnode;
   begin
      Left := Chap7.Translate_Static_Expression (Bound, Range_Type);
      --  if Range_Type /= Null_Iir
      --    and then Get_Type (Bound) /= Range_Type then
      --   Left := New_Convert_Ov
      --      (Left, Get_Ortho_Type (Range_Type, Mode_Value));
      --  end if;
      return Left;
   end Translate_Static_Range_Left;

   function Translate_Static_Range_Right
     (Expr : Iir; Range_Type : Iir := Null_Iir) return O_Cnode
   is
      Right : O_Cnode;
   begin
      Right := Chap7.Translate_Static_Expression (Get_Right_Limit (Expr),
                                                  Range_Type);
      --          if Range_Type /= Null_Iir then
      --             Right := New_Convert_Ov
      --               (Right, Get_Ortho_Type (Range_Type, Mode_Value));
      --          end if;
      return Right;
   end Translate_Static_Range_Right;

   function Translate_Static_Range_Dir (Expr : Iir) return O_Cnode is
   begin
      case Get_Direction (Expr) is
         when Iir_To =>
            return Ghdl_Dir_To_Node;
         when Iir_Downto =>
            return Ghdl_Dir_Downto_Node;
      end case;
   end Translate_Static_Range_Dir;

   function Translate_Static_Range_Length (Expr : Iir) return O_Cnode
   is
      Ulen : Unsigned_64;
   begin
      Ulen := Unsigned_64 (Eval_Discrete_Range_Length (Expr));
      return New_Unsigned_Literal (Ghdl_Index_Type, Ulen);
   end Translate_Static_Range_Length;

   function Translate_Range_Expression_Left
     (Expr : Iir; Range_Type : Iir := Null_Iir) return O_Enode
   is
      Left : O_Enode;
   begin
      Left := Chap7.Translate_Expression (Get_Left_Limit (Expr));
      if Range_Type /= Null_Iir then
         Left := New_Convert_Ov (Left,
                                 Get_Ortho_Type (Range_Type, Mode_Value));
      end if;
      return Left;
   end Translate_Range_Expression_Left;

   function Translate_Range_Expression_Right
     (Expr : Iir; Range_Type : Iir := Null_Iir) return O_Enode
   is
      Right : O_Enode;
   begin
      Right := Chap7.Translate_Expression (Get_Right_Limit (Expr));
      if Range_Type /= Null_Iir then
         Right := New_Convert_Ov (Right,
                                  Get_Ortho_Type (Range_Type, Mode_Value));
      end if;
      return Right;
   end Translate_Range_Expression_Right;

   --  Compute the length of LEFT DIR (to/downto) RIGHT.
   function Compute_Range_Length
     (Left : O_Enode; Right : O_Enode; Dir : Iir_Direction) return O_Enode
   is
      Rng_Type : constant O_Tnode := Ghdl_I32_Type;
      L        : constant O_Enode := New_Convert_Ov (Left, Rng_Type);
      R        : constant O_Enode := New_Convert_Ov (Right, Rng_Type);
      Val      : O_Enode;
      Tmp      : O_Dnode;
      Res      : O_Dnode;
      If_Blk   : O_If_Block;
   begin
      case Dir is
         when Iir_To =>
            Val := New_Dyadic_Op (ON_Sub_Ov, R, L);
         when Iir_Downto =>
            Val := New_Dyadic_Op (ON_Sub_Ov, L, R);
      end case;

      Res := Create_Temp (Ghdl_Index_Type);
      Open_Temp;
      Tmp := Create_Temp (Rng_Type);
      New_Assign_Stmt (New_Obj (Tmp), Val);
      Start_If_Stmt
        (If_Blk,
         New_Compare_Op (ON_Lt, New_Obj_Value (Tmp),
           New_Lit (New_Signed_Literal (Rng_Type, 0)),
           Ghdl_Bool_Type));
      Init_Var (Res);
      New_Else_Stmt (If_Blk);
      Val := New_Convert_Ov (New_Obj_Value (Tmp), Ghdl_Index_Type);
      Val := New_Dyadic_Op (ON_Add_Ov, Val, New_Lit (Ghdl_Index_1));
      New_Assign_Stmt (New_Obj (Res), Val);
      Finish_If_Stmt (If_Blk);
      Close_Temp;
      return New_Obj_Value (Res);
   end Compute_Range_Length;

   function Translate_Range_Expression_Length (Expr : Iir) return O_Enode
   is
      Left, Right : O_Enode;
   begin
      if Get_Expr_Staticness (Expr) = Locally then
         return New_Lit (Translate_Static_Range_Length (Expr));
      else
         Left := Chap7.Translate_Expression (Get_Left_Limit (Expr));
         Right := Chap7.Translate_Expression (Get_Right_Limit (Expr));

         return Compute_Range_Length (Left, Right, Get_Direction (Expr));
      end if;
   end Translate_Range_Expression_Length;

   function Translate_Range_Length (Expr : Iir) return O_Enode is
   begin
      case Get_Kind (Expr) is
         when Iir_Kind_Range_Expression =>
            return Translate_Range_Expression_Length (Expr);
         when Iir_Kind_Range_Array_Attribute =>
            return Chap14.Translate_Length_Array_Attribute (Expr, Null_Iir);
         when others =>
            Error_Kind ("translate_range_length", Expr);
      end case;
   end Translate_Range_Length;

   function Translate_Association (Assoc : Iir) return O_Enode
   is
      Formal      : constant Iir := Get_Formal (Assoc);
      Formal_Base : constant Iir := Get_Association_Interface (Assoc);
      Actual      : Iir;
   begin
      case Get_Kind (Assoc) is
         when Iir_Kind_Association_Element_By_Expression =>
            Actual := Get_Actual (Assoc);
         when Iir_Kind_Association_Element_Open =>
            Actual := Get_Default_Value (Formal);
         when others =>
            Error_Kind ("translate_association", Assoc);
      end case;

      case Get_Kind (Formal_Base) is
         when Iir_Kind_Interface_Constant_Declaration
            | Iir_Kind_Interface_File_Declaration =>
            return Chap3.Maybe_Insert_Scalar_Check
              (Translate_Expression (Actual, Get_Type (Formal)),
               Actual, Get_Type (Formal));
         when Iir_Kind_Interface_Signal_Declaration =>
            return Translate_Implicit_Conv
              (M2E (Chap6.Translate_Name (Actual)),
               Get_Type (Actual),
               Get_Type (Formal_Base),
               Mode_Signal, Assoc);
         when others =>
            Error_Kind ("translate_association", Formal);
      end case;
   end Translate_Association;

   function Translate_Function_Call (Imp : Iir; Assoc_Chain : Iir; Obj : Iir)
                                    return O_Enode
   is
      Info   : constant Subprg_Info_Acc := Get_Info (Imp);
      Constr : O_Assoc_List;
      Assoc  : Iir;
      Res    : Mnode;
   begin
      if Info.Use_Stack2 then
         Create_Temp_Stack2_Mark;
      end if;

      if Info.Res_Interface /= O_Dnode_Null then
         --  Composite result.
         --  If we need to allocate, do it before starting the call!
         declare
            Res_Type : Iir;
            Res_Info : Type_Info_Acc;
         begin
            Res_Type := Get_Return_Type (Imp);
            Res_Info := Get_Info (Res_Type);
            Res := Create_Temp (Res_Info);
            if Res_Info.Type_Mode /= Type_Mode_Fat_Array then
               Chap4.Allocate_Complex_Object (Res_Type, Alloc_Stack, Res);
            end if;
         end;
      end if;

      Start_Association (Constr, Info.Ortho_Func);

      if Info.Res_Interface /= O_Dnode_Null then
         --  Composite result.
         New_Association (Constr, M2E (Res));
      end if;

      --  If the subprogram is a method, pass the protected object.
      if Obj /= Null_Iir then
         New_Association (Constr, M2E (Chap6.Translate_Name (Obj)));
      else
         Subprgs.Add_Subprg_Instance_Assoc (Constr, Info.Subprg_Instance);
      end if;

      Assoc := Assoc_Chain;
      while Assoc /= Null_Iir loop
         --  FIXME: evaluate expression before, because we
         --  may allocate objects.
         New_Association (Constr, Translate_Association (Assoc));
         Assoc := Get_Chain (Assoc);
      end loop;

      if Info.Res_Interface /= O_Dnode_Null then
         --  Composite result.
         New_Procedure_Call (Constr);
         return M2E (Res);
      else
         return New_Function_Call (Constr);
      end if;
   end Translate_Function_Call;

   function Translate_Operator_Function_Call
     (Imp : Iir; Left : Iir;  Right : Iir; Res_Type : Iir) return O_Enode
   is
      function Create_Assoc (Actual : Iir; Formal : Iir) return Iir
      is
         R : Iir;
      begin
         R := Create_Iir (Iir_Kind_Association_Element_By_Expression);
         Location_Copy (R, Actual);
         Set_Actual (R, Actual);
         Set_Formal (R, Formal);
         return R;
      end Create_Assoc;

      Inter : Iir;
      El_L  : Iir;
      El_R  : Iir;
      Res   : O_Enode;
   begin
      Inter := Get_Interface_Declaration_Chain (Imp);

      El_L := Create_Assoc (Left, Inter);

      if Right /= Null_Iir then
         Inter := Get_Chain (Inter);
         El_R := Create_Assoc (Right, Inter);
         Set_Chain (El_L, El_R);
      end if;

      Res := Translate_Function_Call (Imp, El_L, Null_Iir);

      Free_Iir (El_L);
      if Right /= Null_Iir then
         Free_Iir (El_R);
      end if;

      return Translate_Implicit_Conv
        (Res, Get_Return_Type (Imp), Res_Type, Mode_Value, Left);
   end Translate_Operator_Function_Call;

   function Convert_Constrained_To_Unconstrained
     (Expr : Mnode; Res_Type : Iir) return Mnode
   is
      Type_Info   : constant Type_Info_Acc := Get_Info (Res_Type);
      Kind        : constant Object_Kind_Type := Get_Object_Kind (Expr);
      Stable_Expr : Mnode;
      Res         : Mnode;
   begin
      Res := Create_Temp (Type_Info, Kind);
      Stable_Expr := Stabilize (Expr);
      New_Assign_Stmt
        (M2Lp (Chap3.Get_Array_Base (Res)),
         New_Convert_Ov (M2Addr (Chap3.Get_Array_Base (Stable_Expr)),
           Type_Info.T.Base_Ptr_Type (Kind)));
      New_Assign_Stmt
        (M2Lp (Chap3.Get_Array_Bounds (Res)),
         M2Addr (Chap3.Get_Array_Bounds (Stable_Expr)));
      return Res;
   end Convert_Constrained_To_Unconstrained;

   function Convert_Array_To_Thin_Array
     (Expr : Mnode; Expr_Type : Iir; Atype : Iir; Loc : Iir) return Mnode
   is
      Expr_Indexes  : constant Iir_List := Get_Index_Subtype_List (Expr_Type);
      Expr_Stable   : Mnode;
      Success_Label : O_Snode;
      Failure_Label : O_Snode;
   begin
      Expr_Stable := Stabilize (Expr);

      Open_Temp;
      --  Check each dimension.
      Start_Loop_Stmt (Success_Label);
      Start_Loop_Stmt (Failure_Label);
      for I in 1 .. Get_Nbr_Elements (Expr_Indexes) loop
         Gen_Exit_When
           (Failure_Label,
            New_Compare_Op
              (ON_Neq,
               Chap6.Get_Array_Bound_Length
                 (Expr_Stable, Expr_Type, I),
               Chap6.Get_Array_Bound_Length
                 (T2M (Atype, Get_Object_Kind (Expr_Stable)), Atype, I),
               Ghdl_Bool_Type));
      end loop;
      New_Exit_Stmt (Success_Label);
      Finish_Loop_Stmt (Failure_Label);
      Chap6.Gen_Bound_Error (Loc);
      Finish_Loop_Stmt (Success_Label);
      Close_Temp;

      return Chap3.Get_Array_Base (Expr_Stable);
   end Convert_Array_To_Thin_Array;

   function Translate_Implicit_Array_Conversion
     (Expr : Mnode; Expr_Type : Iir; Res_Type : Iir; Loc : Iir) return Mnode
   is
      Ainfo : Type_Info_Acc;
      Einfo : Type_Info_Acc;
   begin
      pragma Assert
        (Get_Kind (Expr_Type) in Iir_Kinds_Array_Type_Definition);

      if Res_Type = Expr_Type then
         return Expr;
      end if;

      Ainfo := Get_Info (Res_Type);
      Einfo := Get_Info (Expr_Type);
      case Ainfo.Type_Mode is
         when Type_Mode_Fat_Array =>
            --  X to unconstrained.
            case Einfo.Type_Mode is
               when Type_Mode_Fat_Array =>
                  --  unconstrained to unconstrained.
                  return Expr;
               when Type_Mode_Array =>
                  --  constrained to unconstrained.
                  return Convert_Constrained_To_Unconstrained
                    (Expr, Res_Type);
               when others =>
                  raise Internal_Error;
            end case;
         when Type_Mode_Array =>
            --  X to constrained.
            if Einfo.Type_Locally_Constrained
              and then Ainfo.Type_Locally_Constrained
            then
               --  FIXME: optimize static vs non-static
               --  constrained to constrained.
               if not Chap3.Locally_Array_Match (Expr_Type, Res_Type) then
                  --  FIXME: generate a bound error ?
                  --  Even if this is caught at compile-time,
                  --  the code is not required to run.
                  Chap6.Gen_Bound_Error (Loc);
               end if;
               return Expr;
            else
               --  Unbounded/bounded array to bounded array.
               return Convert_Array_To_Thin_Array
                 (Expr, Expr_Type, Res_Type, Loc);
            end if;
         when others =>
            raise Internal_Error;
      end case;
   end Translate_Implicit_Array_Conversion;

   --  Convert (if necessary) EXPR translated from EXPR_ORIG to type ATYPE.
   function Translate_Implicit_Conv (Expr      : O_Enode;
                                     Expr_Type : Iir;
                                     Atype     : Iir;
                                     Is_Sig    : Object_Kind_Type;
                                     Loc       : Iir)
                                    return O_Enode is
   begin
      --  Same type: nothing to do.
      if Atype = Expr_Type then
         return Expr;
      end if;

      if Expr_Type = Universal_Integer_Type_Definition then
         return New_Convert_Ov (Expr, Get_Ortho_Type (Atype, Mode_Value));
      elsif Expr_Type = Universal_Real_Type_Definition then
         return New_Convert_Ov (Expr, Get_Ortho_Type (Atype, Mode_Value));
      elsif Get_Kind (Expr_Type) in Iir_Kinds_Array_Type_Definition then
         return M2E (Translate_Implicit_Array_Conversion
                     (E2M (Expr, Get_Info (Expr_Type), Is_Sig),
                        Expr_Type, Atype, Loc));
      else
         return Expr;
      end if;
   end Translate_Implicit_Conv;

   type Predefined_To_Onop_Type is
     array (Iir_Predefined_Functions) of ON_Op_Kind;
   Predefined_To_Onop : constant Predefined_To_Onop_Type :=
     (Iir_Predefined_Boolean_Or => ON_Or,
      Iir_Predefined_Boolean_Not => ON_Not,
      Iir_Predefined_Boolean_And => ON_And,
      Iir_Predefined_Boolean_Xor => ON_Xor,

      Iir_Predefined_Bit_Not => ON_Not,
      Iir_Predefined_Bit_And => ON_And,
      Iir_Predefined_Bit_Or => ON_Or,
      Iir_Predefined_Bit_Xor => ON_Xor,

      Iir_Predefined_Integer_Equality => ON_Eq,
      Iir_Predefined_Integer_Inequality => ON_Neq,
      Iir_Predefined_Integer_Less_Equal => ON_Le,
      Iir_Predefined_Integer_Less => ON_Lt,
      Iir_Predefined_Integer_Greater => ON_Gt,
      Iir_Predefined_Integer_Greater_Equal => ON_Ge,
      Iir_Predefined_Integer_Plus => ON_Add_Ov,
      Iir_Predefined_Integer_Minus => ON_Sub_Ov,
      Iir_Predefined_Integer_Mul => ON_Mul_Ov,
      Iir_Predefined_Integer_Rem => ON_Rem_Ov,
      Iir_Predefined_Integer_Mod => ON_Mod_Ov,
      Iir_Predefined_Integer_Div => ON_Div_Ov,
      Iir_Predefined_Integer_Absolute => ON_Abs_Ov,
      Iir_Predefined_Integer_Negation => ON_Neg_Ov,

      Iir_Predefined_Enum_Equality => ON_Eq,
      Iir_Predefined_Enum_Inequality => ON_Neq,
      Iir_Predefined_Enum_Greater_Equal => ON_Ge,
      Iir_Predefined_Enum_Greater => ON_Gt,
      Iir_Predefined_Enum_Less => ON_Lt,
      Iir_Predefined_Enum_Less_Equal => ON_Le,

      Iir_Predefined_Physical_Equality => ON_Eq,
      Iir_Predefined_Physical_Inequality => ON_Neq,
      Iir_Predefined_Physical_Less => ON_Lt,
      Iir_Predefined_Physical_Less_Equal => ON_Le,
      Iir_Predefined_Physical_Greater => ON_Gt,
      Iir_Predefined_Physical_Greater_Equal => ON_Ge,
      Iir_Predefined_Physical_Negation => ON_Neg_Ov,
      Iir_Predefined_Physical_Absolute => ON_Abs_Ov,
      Iir_Predefined_Physical_Minus => ON_Sub_Ov,
      Iir_Predefined_Physical_Plus => ON_Add_Ov,

      Iir_Predefined_Floating_Greater => ON_Gt,
      Iir_Predefined_Floating_Greater_Equal => ON_Ge,
      Iir_Predefined_Floating_Less => ON_Lt,
      Iir_Predefined_Floating_Less_Equal => ON_Le,
      Iir_Predefined_Floating_Equality => ON_Eq,
      Iir_Predefined_Floating_Inequality => ON_Neq,
      Iir_Predefined_Floating_Minus => ON_Sub_Ov,
      Iir_Predefined_Floating_Plus => ON_Add_Ov,
      Iir_Predefined_Floating_Mul => ON_Mul_Ov,
      Iir_Predefined_Floating_Div => ON_Div_Ov,
      Iir_Predefined_Floating_Negation => ON_Neg_Ov,
      Iir_Predefined_Floating_Absolute => ON_Abs_Ov,

      others => ON_Nil);

   function Translate_Shortcut_Operator
     (Imp : Iir_Implicit_Function_Declaration; Left, Right : Iir)
     return O_Enode
   is
      Rtype    : Iir;
      Res      : O_Dnode;
      Res_Type : O_Tnode;
      If_Blk   : O_If_Block;
      Val      : Integer;
      V        : O_Cnode;
      Kind     : Iir_Predefined_Functions;
      Invert   : Boolean;
   begin
      Rtype := Get_Return_Type (Imp);
      Res_Type := Get_Ortho_Type (Rtype, Mode_Value);
      Res := Create_Temp (Res_Type);
      Open_Temp;
      New_Assign_Stmt (New_Obj (Res), Chap7.Translate_Expression (Left));
      Close_Temp;
      Kind := Get_Implicit_Definition (Imp);

      --  Short cut: RIGHT is the result (and must be evaluated) iff
      --  LEFT is equal to VAL (ie '0' or false for 0, '1' or true for 1).
      case Kind is
         when Iir_Predefined_Bit_And
            | Iir_Predefined_Boolean_And =>
            Invert := False;
            Val := 1;
         when Iir_Predefined_Bit_Nand
            | Iir_Predefined_Boolean_Nand =>
            Invert := True;
            Val := 1;
         when Iir_Predefined_Bit_Or
            | Iir_Predefined_Boolean_Or =>
            Invert := False;
            Val := 0;
         when Iir_Predefined_Bit_Nor
            | Iir_Predefined_Boolean_Nor =>
            Invert := True;
            Val := 0;
         when others =>
            Ada.Text_IO.Put_Line
              ("translate_shortcut_operator: cannot handle "
               & Iir_Predefined_Functions'Image (Kind));
            raise Internal_Error;
      end case;

      V := Get_Ortho_Expr
        (Get_Nth_Element (Get_Enumeration_Literal_List (Rtype), Val));
      Start_If_Stmt (If_Blk,
                     New_Compare_Op (ON_Eq,
                       New_Obj_Value (Res), New_Lit (V),
                       Ghdl_Bool_Type));
      Open_Temp;
      New_Assign_Stmt (New_Obj (Res), Chap7.Translate_Expression (Right));
      Close_Temp;
      Finish_If_Stmt (If_Blk);
      if Invert then
         return New_Monadic_Op (ON_Not, New_Obj_Value (Res));
      else
         return New_Obj_Value (Res);
      end if;
   end Translate_Shortcut_Operator;

   function Translate_Lib_Operator (Left, Right : O_Enode; Func : O_Dnode)
                                   return O_Enode
   is
      Constr : O_Assoc_List;
   begin
      Start_Association (Constr, Func);
      New_Association (Constr, Left);
      if Right /= O_Enode_Null then
         New_Association (Constr, Right);
      end if;
      return New_Function_Call (Constr);
   end Translate_Lib_Operator;

   function Translate_Predefined_Lib_Operator
     (Left, Right : O_Enode; Func : Iir_Implicit_Function_Declaration)
     return O_Enode
   is
      Info   : constant Subprg_Info_Acc := Get_Info (Func);
      Constr : O_Assoc_List;
   begin
      Start_Association (Constr, Info.Ortho_Func);
      Subprgs.Add_Subprg_Instance_Assoc (Constr, Info.Subprg_Instance);
      New_Association (Constr, Left);
      if Right /= O_Enode_Null then
         New_Association (Constr, Right);
      end if;
      return New_Function_Call (Constr);
   end Translate_Predefined_Lib_Operator;

   function Translate_Predefined_Array_Operator
     (Left, Right : O_Enode; Func : Iir) return O_Enode
   is
      Info      : constant Type_Info_Acc := Get_Info (Get_Return_Type (Func));
      Func_Info : constant Subprg_Info_Acc := Get_Info (Func);
      Res       : O_Dnode;
      Constr    : O_Assoc_List;
   begin
      Create_Temp_Stack2_Mark;
      Res := Create_Temp (Info.Ortho_Type (Mode_Value));
      Start_Association (Constr, Func_Info.Ortho_Func);
      Subprgs.Add_Subprg_Instance_Assoc (Constr, Func_Info.Subprg_Instance);
      New_Association (Constr,
                       New_Address (New_Obj (Res),
                                    Info.Ortho_Ptr_Type (Mode_Value)));
      New_Association (Constr, Left);
      if Right /= O_Enode_Null then
         New_Association (Constr, Right);
      end if;
      New_Procedure_Call (Constr);
      return New_Address (New_Obj (Res), Info.Ortho_Ptr_Type (Mode_Value));
   end Translate_Predefined_Array_Operator;

   function Translate_Predefined_Array_Operator_Convert
     (Left, Right : O_Enode; Func : Iir; Res_Type : Iir) return O_Enode
   is
      Ret_Type : constant Iir := Get_Return_Type (Func);
      Res      : O_Enode;
   begin
      Res := Translate_Predefined_Array_Operator (Left, Right, Func);
      return Translate_Implicit_Conv
        (Res, Ret_Type, Res_Type, Mode_Value, Func);
   end Translate_Predefined_Array_Operator_Convert;

   --  Create an array aggregate containing one element, EL.
   function Translate_Element_To_Array (El : O_Enode; Arr_Type : Iir)
                                       return O_Enode
   is
      Ainfo : constant Type_Info_Acc := Get_Info (Arr_Type);
      Einfo : constant Type_Info_Acc :=
        Get_Info (Get_Element_Subtype (Arr_Type));
      Res   : O_Dnode;
      V     : O_Dnode;
   begin
      Res := Create_Temp (Ainfo.Ortho_Type (Mode_Value));
      if Is_Composite (Einfo) then
         New_Assign_Stmt
           (New_Selected_Element (New_Obj (Res),
            Ainfo.T.Base_Field (Mode_Value)),
            New_Convert_Ov (El, Ainfo.T.Base_Ptr_Type (Mode_Value)));
      else
         V := Create_Temp_Init (Einfo.Ortho_Type (Mode_Value), El);
         New_Assign_Stmt
           (New_Selected_Element (New_Obj (Res),
            Ainfo.T.Base_Field (Mode_Value)),
            New_Convert_Ov (New_Address (New_Obj (V),
              Einfo.Ortho_Ptr_Type (Mode_Value)),
              Ainfo.T.Base_Ptr_Type (Mode_Value)));
      end if;
      New_Assign_Stmt
        (New_Selected_Element (New_Obj (Res),
         Ainfo.T.Bounds_Field (Mode_Value)),
         New_Address (Get_Var (Ainfo.T.Array_1bound),
           Ainfo.T.Bounds_Ptr_Type));
      return New_Address (New_Obj (Res), Ainfo.Ortho_Ptr_Type (Mode_Value));
   end Translate_Element_To_Array;

   function Translate_Concat_Operator (Left_Tree, Right_Tree : O_Enode;
                                       Imp : Iir_Implicit_Function_Declaration;
                                       Res_Type : Iir;
                                       Loc : Iir)
                                      return O_Enode
   is
      Ret_Type : constant Iir := Get_Return_Type (Imp);
      Kind     : constant Iir_Predefined_Functions :=
        Get_Implicit_Definition (Imp);
      Arr_El1  : O_Enode;
      Arr_El2  : O_Enode;
      Res      : O_Enode;
   begin
      case Kind is
         when Iir_Predefined_Element_Array_Concat
            | Iir_Predefined_Element_Element_Concat =>
            Arr_El1 := Translate_Element_To_Array (Left_Tree, Ret_Type);
         when others =>
            Arr_El1 := Left_Tree;
      end case;
      case Kind is
         when Iir_Predefined_Array_Element_Concat
            | Iir_Predefined_Element_Element_Concat =>
            Arr_El2 := Translate_Element_To_Array (Right_Tree, Ret_Type);
         when others =>
            Arr_El2 := Right_Tree;
      end case;
      Res := Translate_Predefined_Array_Operator (Arr_El1, Arr_El2, Imp);
      return Translate_Implicit_Conv
        (Res, Ret_Type, Res_Type, Mode_Value, Loc);
   end Translate_Concat_Operator;

   function Translate_Scalar_Min_Max
     (Op : ON_Op_Kind; Left, Right : Iir; Res_Type : Iir) return O_Enode
   is
      Res_Otype : constant O_Tnode := Get_Ortho_Type (Res_Type, Mode_Value);
      Res, L, R : O_Dnode;
      If_Blk    : O_If_Block;
   begin
      --  Create a variable for the result.
      Res := Create_Temp (Res_Otype);

      Open_Temp;
      L := Create_Temp_Init
        (Res_Otype, Translate_Expression (Left, Res_Type));
      R := Create_Temp_Init
        (Res_Otype, Translate_Expression (Right, Res_Type));

      Start_If_Stmt (If_Blk, New_Compare_Op (Op,
                                             New_Obj_Value (L),
                                             New_Obj_Value (R),
                                             Ghdl_Bool_Type));
      New_Assign_Stmt (New_Obj (Res), New_Obj_Value (L));
      New_Else_Stmt (If_Blk);
      New_Assign_Stmt (New_Obj (Res), New_Obj_Value (R));
      Finish_If_Stmt (If_Blk);
      Close_Temp;

      return New_Obj_Value (Res);
   end Translate_Scalar_Min_Max;

   function Translate_Predefined_Vector_Min_Max
     (Is_Min : Boolean; Left : Iir; Res_Type : Iir) return O_Enode
   is
      Res_Otype    : constant O_Tnode := Get_Ortho_Type (Res_Type, Mode_Value);
      Left_Type    : constant Iir := Get_Type (Left);
      Res, El, Len : O_Dnode;
      Arr          : Mnode;
      If_Blk       : O_If_Block;
      Label        : O_Snode;
      Op           : ON_Op_Kind;
   begin
      --  Create a variable for the result.
      Res := Create_Temp (Res_Otype);

      Open_Temp;
      if Is_Min then
         Op := ON_Lt;
      else
         Op := ON_Gt;
      end if;
      New_Assign_Stmt
        (New_Obj (Res),
         Chap14.Translate_High_Low_Type_Attribute (Res_Type, Is_Min));

      El := Create_Temp (Res_Otype);
      Arr := Stabilize (E2M (Translate_Expression (Left),
                        Get_Info (Left_Type), Mode_Value));
      Len := Create_Temp_Init
        (Ghdl_Index_Type,
         M2E (Chap3.Range_To_Length
                (Chap3.Get_Array_Range (Arr, Left_Type, 1))));

      --  Create:
      --    loop
      --      exit when LEN = 0;
      --      LEN := LEN - 1;
      --      if ARR[LEN] </> RES then
      --         RES := ARR[LEN];
      --      end if;
      --    end loop;
      Start_Loop_Stmt (Label);
      Gen_Exit_When (Label, New_Compare_Op (ON_Eq, New_Obj_Value (Len),
                                            New_Lit (Ghdl_Index_0),
                                            Ghdl_Bool_Type));
      Dec_Var (Len);
      New_Assign_Stmt
        (New_Obj (El),
         M2E (Chap3.Index_Base (Chap3.Get_Array_Base (Arr),
                                Left_Type, New_Obj_Value (Len))));
      Start_If_Stmt (If_Blk, New_Compare_Op (Op,
                                             New_Obj_Value (El),
                                             New_Obj_Value (Res),
                                             Ghdl_Bool_Type));
      New_Assign_Stmt (New_Obj (Res), New_Obj_Value (El));
      Finish_If_Stmt (If_Blk);
      Finish_Loop_Stmt (Label);

      Close_Temp;

      return New_Obj_Value (Res);
   end Translate_Predefined_Vector_Min_Max;

   function Translate_Std_Ulogic_Match
     (Func : O_Dnode; L, R : O_Enode; Res_Type : O_Tnode) return O_Enode
   is
      Constr : O_Assoc_List;
   begin
      Start_Association (Constr, Func);
      New_Association (Constr, New_Convert_Ov (L, Ghdl_I32_Type));
      New_Association (Constr, New_Convert_Ov (R, Ghdl_I32_Type));
      return New_Convert_Ov (New_Function_Call (Constr), Res_Type);
   end Translate_Std_Ulogic_Match;

   function Translate_To_String (Subprg   : O_Dnode;
                                 Res_Type : Iir;
                                 Loc      : Iir;
                                 Val      : O_Enode;
                                 Arg2     : O_Enode := O_Enode_Null;
                                 Arg3     : O_Enode := O_Enode_Null)
                                return O_Enode
   is
      Val_Type : constant Iir := Get_Base_Type (Res_Type);
      Res      : O_Dnode;
      Assoc    : O_Assoc_List;
   begin
      Res := Create_Temp (Std_String_Node);
      Create_Temp_Stack2_Mark;
      Start_Association (Assoc, Subprg);
      New_Association (Assoc,
                       New_Address (New_Obj (Res), Std_String_Ptr_Node));
      New_Association (Assoc, Val);
      if Arg2 /= O_Enode_Null then
         New_Association (Assoc, Arg2);
         if Arg3 /= O_Enode_Null then
            New_Association (Assoc, Arg3);
         end if;
      end if;
      New_Procedure_Call (Assoc);
      return M2E (Translate_Implicit_Array_Conversion
                  (Dv2M (Res, Get_Info (Val_Type), Mode_Value),
                   Val_Type, Res_Type, Loc));
   end Translate_To_String;

   function Translate_Bv_To_String (Subprg   : O_Dnode;
                                    Val      : O_Enode;
                                    Val_Type : Iir;
                                    Res_Type : Iir;
                                    Loc      : Iir)
                                   return O_Enode
   is
      Arr : Mnode;
   begin
      Arr := Stabilize (E2M (Val, Get_Info (Val_Type), Mode_Value));
      return Translate_To_String
        (Subprg, Res_Type, Loc,
         M2E (Chap3.Get_Array_Base (Arr)),
         M2E (Chap3.Range_To_Length
                (Chap3.Get_Array_Range (Arr, Val_Type, 1))));
   end Translate_Bv_To_String;

   subtype Predefined_Boolean_Logical is Iir_Predefined_Functions range
     Iir_Predefined_Boolean_And .. Iir_Predefined_Boolean_Xnor;

   function Translate_Predefined_Logical
     (Op : Predefined_Boolean_Logical; Left, Right : O_Enode) return O_Enode is
   begin
      case Op is
         when Iir_Predefined_Boolean_And =>
            return New_Dyadic_Op (ON_And, Left, Right);
         when Iir_Predefined_Boolean_Or =>
            return New_Dyadic_Op (ON_Or, Left, Right);
         when Iir_Predefined_Boolean_Nand =>
            return New_Monadic_Op
              (ON_Not, New_Dyadic_Op (ON_And, Left, Right));
         when Iir_Predefined_Boolean_Nor =>
            return New_Monadic_Op
              (ON_Not, New_Dyadic_Op (ON_Or, Left, Right));
         when Iir_Predefined_Boolean_Xor =>
            return New_Dyadic_Op (ON_Xor, Left, Right);
         when Iir_Predefined_Boolean_Xnor =>
            return New_Monadic_Op
              (ON_Not, New_Dyadic_Op (ON_Xor, Left, Right));
      end case;
   end Translate_Predefined_Logical;

   function Translate_Predefined_TF_Array_Element
     (Op : Predefined_Boolean_Logical;
      Left, Right : Iir;
      Res_Type : Iir;
      Loc : Iir)
     return O_Enode
   is
      Arr_Type      : constant Iir := Get_Type (Left);
      Res_Btype     : constant Iir := Get_Base_Type (Res_Type);
      Res_Info      : constant Type_Info_Acc := Get_Info (Res_Btype);
      Base_Ptr_Type : constant O_Tnode :=
        Res_Info.T.Base_Ptr_Type (Mode_Value);
      Arr           : Mnode;
      El            : O_Dnode;
      Base          : O_Dnode;
      Len           : O_Dnode;
      Label         : O_Snode;
      Res           : Mnode;
   begin
      --  Translate the array.
      Arr := Stabilize (E2M (Translate_Expression (Left),
                        Get_Info (Arr_Type), Mode_Value));

      --  Extract its length.
      Len := Create_Temp_Init
        (Ghdl_Index_Type,
         M2E (Chap3.Range_To_Length
                (Chap3.Get_Array_Range (Arr, Arr_Type, 1))));

      --  Allocate the result array.
      Base := Create_Temp_Init
        (Base_Ptr_Type,
         Gen_Alloc (Alloc_Stack, New_Obj_Value (Len), Base_Ptr_Type));

      Open_Temp;
      --  Translate the element.
      El := Create_Temp_Init (Get_Ortho_Type (Get_Type (Right), Mode_Value),
                              Translate_Expression (Right));
      --  Create:
      --    loop
      --      exit when LEN = 0;
      --      LEN := LEN - 1;
      --      BASE[LEN] := EL op ARR[LEN];
      --    end loop;
      Start_Loop_Stmt (Label);
      Gen_Exit_When (Label, New_Compare_Op (ON_Eq, New_Obj_Value (Len),
                                            New_Lit (Ghdl_Index_0),
                                            Ghdl_Bool_Type));
      Dec_Var (Len);
      New_Assign_Stmt
        (New_Indexed_Acc_Value (New_Obj (Base),
                                New_Obj_Value (Len)),
         Translate_Predefined_Logical
           (Op,
            New_Obj_Value (El),
            M2E (Chap3.Index_Base (Chap3.Get_Array_Base (Arr),
                                   Arr_Type, New_Obj_Value (Len)))));
      Finish_Loop_Stmt (Label);
      Close_Temp;

      Res := Create_Temp (Res_Info, Mode_Value);
      New_Assign_Stmt (M2Lp (Chap3.Get_Array_Base (Res)),
                       New_Obj_Value (Base));
      New_Assign_Stmt (M2Lp (Chap3.Get_Array_Bounds (Res)),
                       M2Addr (Chap3.Get_Array_Bounds (Arr)));

      return Translate_Implicit_Conv (M2E (Res), Res_Btype, Res_Type,
                                      Mode_Value, Loc);
   end Translate_Predefined_TF_Array_Element;

   function Translate_Predefined_TF_Reduction
     (Op : ON_Op_Kind; Operand : Iir; Res_Type : Iir) return O_Enode
   is
      Arr_Type  : constant Iir := Get_Type (Operand);
      Enums     : constant Iir_List :=
        Get_Enumeration_Literal_List (Get_Base_Type (Res_Type));
      Init_Enum : Iir;

      Res      : O_Dnode;
      Arr_Expr : O_Enode;
      Arr      : Mnode;
      Len      : O_Dnode;
      Label    : O_Snode;
   begin
      if Op = ON_And then
         Init_Enum := Get_Nth_Element (Enums, 1);
      else
         Init_Enum := Get_Nth_Element (Enums, 0);
      end if;

      Res := Create_Temp_Init (Get_Ortho_Type (Res_Type, Mode_Value),
                               New_Lit (Get_Ortho_Expr (Init_Enum)));

      Open_Temp;
      --  Translate the array.  Note that Translate_Expression may create
      --  the info for the array type, so be sure to call it before calling
      --  Get_Info.
      Arr_Expr := Translate_Expression (Operand);
      Arr := Stabilize (E2M (Arr_Expr, Get_Info (Arr_Type), Mode_Value));

      --  Extract its length.
      Len := Create_Temp_Init
        (Ghdl_Index_Type,
         M2E (Chap3.Range_To_Length
                (Chap3.Get_Array_Range (Arr, Arr_Type, 1))));

      --  Create:
      --    loop
      --      exit when LEN = 0;
      --      LEN := LEN - 1;
      --      RES := RES op ARR[LEN];
      --    end loop;
      Start_Loop_Stmt (Label);
      Gen_Exit_When (Label, New_Compare_Op (ON_Eq, New_Obj_Value (Len),
                                            New_Lit (Ghdl_Index_0),
                                            Ghdl_Bool_Type));
      Dec_Var (Len);
      New_Assign_Stmt
        (New_Obj (Res),
         New_Dyadic_Op
           (Op,
            New_Obj_Value (Res),
            M2E (Chap3.Index_Base (Chap3.Get_Array_Base (Arr),
                                   Arr_Type, New_Obj_Value (Len)))));
      Finish_Loop_Stmt (Label);
      Close_Temp;

      return New_Obj_Value (Res);
   end Translate_Predefined_TF_Reduction;

   function Translate_Predefined_Array_Min_Max
     (Is_Min                : Boolean;
      Left, Right           : O_Enode;
      Left_Type, Right_Type : Iir;
      Res_Type              : Iir;
      Imp                   : Iir;
      Loc                   : Iir)
     return O_Enode
   is
      Arr_Type : constant Iir := Get_Base_Type (Left_Type);
      Arr_Info : constant Type_Info_Acc := Get_Info (Arr_Type);
      L, R     : Mnode;
      If_Blk   : O_If_Block;
      Res      : Mnode;
   begin
      Res := Create_Temp (Arr_Info, Mode_Value);
      L := Stabilize (E2M (Left, Get_Info (Left_Type), Mode_Value));
      R := Stabilize (E2M (Right, Get_Info (Right_Type), Mode_Value));
      Start_If_Stmt
        (If_Blk,
         New_Compare_Op
           (ON_Eq,
            Translate_Predefined_Lib_Operator (M2E (L), M2E (R), Imp),
            New_Lit (Ghdl_Compare_Lt),
            Std_Boolean_Type_Node));
      if Is_Min then
         Copy_Fat_Pointer (Res, Translate_Implicit_Array_Conversion
                           (L, Left_Type, Arr_Type, Loc));
      else
         Copy_Fat_Pointer (Res, Translate_Implicit_Array_Conversion
                           (R, Right_Type, Arr_Type, Loc));
      end if;
      New_Else_Stmt (If_Blk);
      if Is_Min then
         Copy_Fat_Pointer (Res, Translate_Implicit_Array_Conversion
                           (R, Right_Type, Arr_Type, Loc));
      else
         Copy_Fat_Pointer (Res, Translate_Implicit_Array_Conversion
                           (L, Left_Type, Arr_Type, Loc));
      end if;
      Finish_If_Stmt (If_Blk);

      return M2E (Translate_Implicit_Array_Conversion
                  (Res, Arr_Type, Res_Type, Loc));
   end Translate_Predefined_Array_Min_Max;

   function Translate_Predefined_TF_Edge (Is_Rising : Boolean; Left : Iir)
                                         return O_Enode
   is
      Enums : constant Iir_List :=
        Get_Enumeration_Literal_List (Get_Base_Type (Get_Type (Left)));
      Name  : Mnode;
   begin
      Name := Stabilize (Chap6.Translate_Name (Left), True);
      return New_Dyadic_Op
        (ON_And,
         New_Value (Chap14.Get_Signal_Field (Name, Ghdl_Signal_Event_Field)),
         New_Compare_Op
           (ON_Eq,
            New_Value (New_Access_Element (M2E (Name))),
            New_Lit (Get_Ortho_Expr
                       (Get_Nth_Element (Enums, Boolean'Pos (Is_Rising)))),
            Std_Boolean_Type_Node));
   end Translate_Predefined_TF_Edge;

   function Translate_Predefined_Std_Ulogic_Array_Match
     (Subprg : O_Dnode; Left, Right : Iir; Res_Type : Iir) return O_Enode
   is
      Res_Otype      : constant O_Tnode :=
        Get_Ortho_Type (Res_Type, Mode_Value);
      L_Type         : constant Iir := Get_Type (Left);
      R_Type         : constant Iir := Get_Type (Right);
      L_Expr, R_Expr : O_Enode;
      L, R           : Mnode;
      Assoc          : O_Assoc_List;

      Res : O_Dnode;
   begin
      Res := Create_Temp (Ghdl_I32_Type);

      Open_Temp;
      --  Translate the arrays.  Note that Translate_Expression may create
      --  the info for the array type, so be sure to call it before calling
      --  Get_Info.
      L_Expr := Translate_Expression (Left);
      L := Stabilize (E2M (L_Expr, Get_Info (L_Type), Mode_Value));

      R_Expr := Translate_Expression (Right);
      R := Stabilize (E2M (R_Expr, Get_Info (R_Type), Mode_Value));

      Start_Association (Assoc, Subprg);
      New_Association
        (Assoc,
         New_Convert_Ov (M2E (Chap3.Get_Array_Base (L)), Ghdl_Ptr_Type));
      New_Association
        (Assoc,
         M2E (Chap3.Range_To_Length (Chap3.Get_Array_Range (L, L_Type, 1))));

      New_Association
        (Assoc,
         New_Convert_Ov (M2E (Chap3.Get_Array_Base (R)), Ghdl_Ptr_Type));
      New_Association
        (Assoc,
         M2E (Chap3.Range_To_Length (Chap3.Get_Array_Range (R, R_Type, 1))));

      New_Assign_Stmt (New_Obj (Res), New_Function_Call (Assoc));

      Close_Temp;

      return New_Convert_Ov (New_Obj_Value (Res), Res_Otype);
   end Translate_Predefined_Std_Ulogic_Array_Match;

   function Translate_Predefined_Operator
     (Imp         : Iir_Implicit_Function_Declaration;
      Left, Right : Iir;
      Res_Type    : Iir;
      Loc         : Iir)
     return O_Enode
   is
      Kind       : constant Iir_Predefined_Functions :=
        Get_Implicit_Definition (Imp);
      Left_Tree  : O_Enode;
      Right_Tree : O_Enode;
      Left_Type  : Iir;
      Right_Type : Iir;
      Res_Otype  : O_Tnode;
      Op         : ON_Op_Kind;
      Inter      : Iir;
      Res        : O_Enode;
   begin
      case Kind is
         when Iir_Predefined_Bit_And
            | Iir_Predefined_Bit_Or
            | Iir_Predefined_Bit_Nand
            | Iir_Predefined_Bit_Nor
            | Iir_Predefined_Boolean_And
            | Iir_Predefined_Boolean_Or
            | Iir_Predefined_Boolean_Nand
            | Iir_Predefined_Boolean_Nor =>
            --  Right operand of shortcur operators may not be evaluated.
            return Translate_Shortcut_Operator (Imp, Left, Right);

            --  Operands of min/max are evaluated in a declare block.
         when Iir_Predefined_Enum_Minimum
            | Iir_Predefined_Integer_Minimum
            | Iir_Predefined_Floating_Minimum
            | Iir_Predefined_Physical_Minimum =>
            return Translate_Scalar_Min_Max (ON_Le, Left, Right, Res_Type);
         when Iir_Predefined_Enum_Maximum
            | Iir_Predefined_Integer_Maximum
            | Iir_Predefined_Floating_Maximum
            | Iir_Predefined_Physical_Maximum =>
            return Translate_Scalar_Min_Max (ON_Ge, Left, Right, Res_Type);

            --  Avoid implicit conversion of the array parameters to the
            --  unbounded type for optimizing purpose.  FIXME: should do the
            --  same for the result.
         when Iir_Predefined_TF_Array_Element_And =>
            return Translate_Predefined_TF_Array_Element
              (Iir_Predefined_Boolean_And, Left, Right, Res_Type, Loc);
         when Iir_Predefined_TF_Element_Array_And =>
            return Translate_Predefined_TF_Array_Element
              (Iir_Predefined_Boolean_And, Right, Left, Res_Type, Loc);
         when Iir_Predefined_TF_Array_Element_Or =>
            return Translate_Predefined_TF_Array_Element
              (Iir_Predefined_Boolean_Or, Left, Right, Res_Type, Loc);
         when Iir_Predefined_TF_Element_Array_Or =>
            return Translate_Predefined_TF_Array_Element
              (Iir_Predefined_Boolean_Or, Right, Left, Res_Type, Loc);
         when Iir_Predefined_TF_Array_Element_Nand =>
            return Translate_Predefined_TF_Array_Element
              (Iir_Predefined_Boolean_Nand, Left, Right, Res_Type, Loc);
         when Iir_Predefined_TF_Element_Array_Nand =>
            return Translate_Predefined_TF_Array_Element
              (Iir_Predefined_Boolean_Nand, Right, Left, Res_Type, Loc);
         when Iir_Predefined_TF_Array_Element_Nor =>
            return Translate_Predefined_TF_Array_Element
              (Iir_Predefined_Boolean_Nor, Left, Right, Res_Type, Loc);
         when Iir_Predefined_TF_Element_Array_Nor =>
            return Translate_Predefined_TF_Array_Element
              (Iir_Predefined_Boolean_Nor, Right, Left, Res_Type, Loc);
         when Iir_Predefined_TF_Array_Element_Xor =>
            return Translate_Predefined_TF_Array_Element
              (Iir_Predefined_Boolean_Xor, Left, Right, Res_Type, Loc);
         when Iir_Predefined_TF_Element_Array_Xor =>
            return Translate_Predefined_TF_Array_Element
              (Iir_Predefined_Boolean_Xor, Right, Left, Res_Type, Loc);
         when Iir_Predefined_TF_Array_Element_Xnor =>
            return Translate_Predefined_TF_Array_Element
              (Iir_Predefined_Boolean_Xnor, Left, Right, Res_Type, Loc);
         when Iir_Predefined_TF_Element_Array_Xnor =>
            return Translate_Predefined_TF_Array_Element
              (Iir_Predefined_Boolean_Xnor, Right, Left, Res_Type, Loc);

            --  Avoid implicit conversion of the array parameters to the
            --  unbounded type for optimizing purpose.
         when Iir_Predefined_TF_Reduction_And =>
            return Translate_Predefined_TF_Reduction
              (ON_And, Left, Res_Type);
         when Iir_Predefined_TF_Reduction_Or =>
            return Translate_Predefined_TF_Reduction
              (ON_Or, Left, Res_Type);
         when Iir_Predefined_TF_Reduction_Nand =>
            return New_Monadic_Op
              (ON_Not,
               Translate_Predefined_TF_Reduction (ON_And, Left, Res_Type));
         when Iir_Predefined_TF_Reduction_Nor =>
            return New_Monadic_Op
              (ON_Not,
               Translate_Predefined_TF_Reduction (ON_Or, Left, Res_Type));
         when Iir_Predefined_TF_Reduction_Xor =>
            return Translate_Predefined_TF_Reduction
              (ON_Xor, Left, Res_Type);
         when Iir_Predefined_TF_Reduction_Xnor =>
            return New_Monadic_Op
              (ON_Not,
               Translate_Predefined_TF_Reduction (ON_Xor, Left, Res_Type));

         when Iir_Predefined_Vector_Minimum =>
            return Translate_Predefined_Vector_Min_Max
              (True, Left, Res_Type);
         when Iir_Predefined_Vector_Maximum =>
            return Translate_Predefined_Vector_Min_Max
              (False, Left, Res_Type);

         when Iir_Predefined_Bit_Rising_Edge
            | Iir_Predefined_Boolean_Rising_Edge =>
            return Translate_Predefined_TF_Edge (True, Left);
         when Iir_Predefined_Bit_Falling_Edge
            | Iir_Predefined_Boolean_Falling_Edge =>
            return Translate_Predefined_TF_Edge (False, Left);

         when Iir_Predefined_Std_Ulogic_Array_Match_Equality =>
            return Translate_Predefined_Std_Ulogic_Array_Match
              (Ghdl_Std_Ulogic_Array_Match_Eq, Left, Right, Res_Type);
         when Iir_Predefined_Std_Ulogic_Array_Match_Inequality =>
            return Translate_Predefined_Std_Ulogic_Array_Match
              (Ghdl_Std_Ulogic_Array_Match_Ne, Left, Right, Res_Type);

         when others =>
            null;
      end case;

      --  Evaluate parameters.
      Res_Otype := Get_Ortho_Type (Res_Type, Mode_Value);
      Inter := Get_Interface_Declaration_Chain (Imp);
      if Left = Null_Iir then
         Left_Tree := O_Enode_Null;
      else
         Left_Type := Get_Type (Inter);
         Left_Tree := Translate_Expression (Left, Left_Type);
      end if;

      if Right = Null_Iir then
         Right_Tree := O_Enode_Null;
      else
         Right_Type := Get_Type (Get_Chain (Inter));
         Right_Tree := Translate_Expression (Right, Right_Type);
      end if;

      Op := Predefined_To_Onop (Kind);
      if Op /= ON_Nil then
         case Op is
            when ON_Eq
               | ON_Neq
               | ON_Ge
               | ON_Gt
               | ON_Le
               | ON_Lt =>
               Res := New_Compare_Op (Op, Left_Tree, Right_Tree,
                                      Std_Boolean_Type_Node);
            when ON_Add_Ov
               | ON_Sub_Ov
               | ON_Mul_Ov
               | ON_Div_Ov
               | ON_Rem_Ov
               | ON_Mod_Ov
               | ON_Xor =>
               Res := New_Dyadic_Op (Op, Left_Tree, Right_Tree);
            when ON_Abs_Ov
               | ON_Neg_Ov
               | ON_Not =>
               Res := New_Monadic_Op (Op, Left_Tree);
            when others =>
               Ada.Text_IO.Put_Line
                 ("translate_predefined_operator: cannot handle "
                  & ON_Op_Kind'Image (Op));
               raise Internal_Error;
         end case;
         Res := Translate_Implicit_Conv
           (Res, Get_Return_Type (Imp), Res_Type, Mode_Value, Loc);
         return Res;
      end if;

      case Kind is
         when Iir_Predefined_Bit_Xnor
            | Iir_Predefined_Boolean_Xnor =>
            return Translate_Predefined_Logical
              (Iir_Predefined_Boolean_Xnor, Left_Tree, Right_Tree);
         when Iir_Predefined_Bit_Match_Equality =>
            return New_Compare_Op (ON_Eq, Left_Tree, Right_Tree,
                                   Get_Ortho_Type (Res_Type, Mode_Value));
         when Iir_Predefined_Bit_Match_Inequality =>
            return New_Compare_Op (ON_Neq, Left_Tree, Right_Tree,
                                   Get_Ortho_Type (Res_Type, Mode_Value));

         when Iir_Predefined_Bit_Condition =>
            return New_Compare_Op
              (ON_Eq, Left_Tree, New_Lit (Get_Ortho_Expr (Bit_1)),
               Std_Boolean_Type_Node);

         when Iir_Predefined_Integer_Identity
            | Iir_Predefined_Floating_Identity
            | Iir_Predefined_Physical_Identity =>
            return Translate_Implicit_Conv
              (Left_Tree, Left_Type, Res_Type, Mode_Value, Loc);

         when Iir_Predefined_Access_Equality
            | Iir_Predefined_Access_Inequality =>
            if Is_Composite (Get_Info (Left_Type)) then
               --  a fat pointer.
               declare
                  T        : Type_Info_Acc;
                  B        : Type_Info_Acc;
                  L, R     : O_Dnode;
                  V1, V2   : O_Enode;
                  Op1, Op2 : ON_Op_Kind;
               begin
                  if Kind = Iir_Predefined_Access_Equality then
                     Op1 := ON_Eq;
                     Op2 := ON_And;
                  else
                     Op1 := ON_Neq;
                     Op2 := ON_Or;
                  end if;
                  T := Get_Info (Left_Type);
                  B := Get_Info (Get_Designated_Type (Left_Type));
                  L := Create_Temp (T.Ortho_Ptr_Type (Mode_Value));
                  R := Create_Temp (T.Ortho_Ptr_Type (Mode_Value));
                  New_Assign_Stmt (New_Obj (L), Left_Tree);
                  New_Assign_Stmt (New_Obj (R), Right_Tree);
                  V1 := New_Compare_Op
                    (Op1,
                     New_Value_Selected_Acc_Value
                       (New_Obj (L), B.T.Base_Field (Mode_Value)),
                     New_Value_Selected_Acc_Value
                       (New_Obj (R), B.T.Base_Field (Mode_Value)),
                     Std_Boolean_Type_Node);
                  V2 := New_Compare_Op
                    (Op1,
                     New_Value_Selected_Acc_Value
                       (New_Obj (L), B.T.Bounds_Field (Mode_Value)),
                     New_Value_Selected_Acc_Value
                       (New_Obj (R), B.T.Bounds_Field (Mode_Value)),
                     Std_Boolean_Type_Node);
                  return New_Dyadic_Op (Op2, V1, V2);
               end;
            else
               --  a thin pointer.
               if Kind = Iir_Predefined_Access_Equality then
                  return New_Compare_Op
                    (ON_Eq, Left_Tree, Right_Tree, Std_Boolean_Type_Node);
               else
                  return New_Compare_Op
                    (ON_Neq, Left_Tree, Right_Tree, Std_Boolean_Type_Node);
               end if;
            end if;

         when Iir_Predefined_Physical_Integer_Div =>
            return New_Dyadic_Op (ON_Div_Ov, Left_Tree,
                                  New_Convert_Ov (Right_Tree, Res_Otype));
         when Iir_Predefined_Physical_Physical_Div =>
            return New_Convert_Ov
              (New_Dyadic_Op (ON_Div_Ov, Left_Tree, Right_Tree), Res_Otype);

            --  LRM 7.2.6
            --  Multiplication of a value P of a physical type Tp by a
            --  value I of type INTEGER is equivalent to the following
            --  computation: Tp'Val (Tp'Pos (P) * I)
            --  FIXME: this is not what is really done...
         when Iir_Predefined_Integer_Physical_Mul =>
            return New_Dyadic_Op (ON_Mul_Ov,
                                  New_Convert_Ov (Left_Tree, Res_Otype),
                                  Right_Tree);
         when Iir_Predefined_Physical_Integer_Mul =>
            return New_Dyadic_Op (ON_Mul_Ov, Left_Tree,
                                  New_Convert_Ov (Right_Tree, Res_Otype));

            --  LRM 7.2.6
            --  Multiplication of a value P of a physical type Tp by a
            --  value F of type REAL is equivalten to the following
            --  computation: Tp'Val (INTEGER (REAL (Tp'Pos (P)) * F))
            --  FIXME: we do not restrict with INTEGER.
         when Iir_Predefined_Physical_Real_Mul =>
            declare
               Right_Otype : O_Tnode;
            begin
               Right_Otype := Get_Ortho_Type (Right_Type, Mode_Value);
               return New_Convert_Ov
                 (New_Dyadic_Op (ON_Mul_Ov,
                  New_Convert_Ov (Left_Tree, Right_Otype),
                  Right_Tree),
                  Res_Otype);
            end;
         when Iir_Predefined_Physical_Real_Div =>
            declare
               Right_Otype : O_Tnode;
            begin
               Right_Otype := Get_Ortho_Type (Right_Type, Mode_Value);
               return New_Convert_Ov
                 (New_Dyadic_Op (ON_Div_Ov,
                  New_Convert_Ov (Left_Tree, Right_Otype),
                  Right_Tree),
                  Res_Otype);
            end;
         when Iir_Predefined_Real_Physical_Mul =>
            declare
               Left_Otype : O_Tnode;
            begin
               Left_Otype := Get_Ortho_Type (Left_Type, Mode_Value);
               return New_Convert_Ov
                 (New_Dyadic_Op (ON_Mul_Ov,
                  Left_Tree,
                  New_Convert_Ov (Right_Tree, Left_Otype)),
                  Res_Otype);
            end;

         when Iir_Predefined_Universal_R_I_Mul =>
            return New_Dyadic_Op (ON_Mul_Ov,
                                  Left_Tree,
                                  New_Convert_Ov (Right_Tree, Res_Otype));

         when Iir_Predefined_Floating_Exp =>
            Res := Translate_Lib_Operator
              (New_Convert_Ov (Left_Tree, Std_Real_Otype),
               Right_Tree, Ghdl_Real_Exp);
            return New_Convert_Ov (Res, Res_Otype);
         when Iir_Predefined_Integer_Exp =>
            Res := Translate_Lib_Operator
              (New_Convert_Ov (Left_Tree, Std_Integer_Otype),
               Right_Tree,
               Ghdl_Integer_Exp);
            return New_Convert_Ov (Res, Res_Otype);

         when Iir_Predefined_Array_Inequality
            | Iir_Predefined_Record_Inequality =>
            return New_Monadic_Op
              (ON_Not, Translate_Predefined_Lib_Operator
                 (Left_Tree, Right_Tree, Imp));
         when Iir_Predefined_Array_Equality
            | Iir_Predefined_Record_Equality =>
            return Translate_Predefined_Lib_Operator
              (Left_Tree, Right_Tree, Imp);

         when Iir_Predefined_Array_Greater =>
            return New_Compare_Op
              (ON_Eq,
               Translate_Predefined_Lib_Operator (Left_Tree, Right_Tree,
                 Imp),
               New_Lit (Ghdl_Compare_Gt),
               Std_Boolean_Type_Node);
         when Iir_Predefined_Array_Greater_Equal =>
            return New_Compare_Op
              (ON_Ge,
               Translate_Predefined_Lib_Operator (Left_Tree, Right_Tree,
                 Imp),
               New_Lit (Ghdl_Compare_Eq),
               Std_Boolean_Type_Node);
         when Iir_Predefined_Array_Less =>
            return New_Compare_Op
              (ON_Eq,
               Translate_Predefined_Lib_Operator (Left_Tree, Right_Tree,
                 Imp),
               New_Lit (Ghdl_Compare_Lt),
               Std_Boolean_Type_Node);
         when Iir_Predefined_Array_Less_Equal =>
            return New_Compare_Op
              (ON_Le,
               Translate_Predefined_Lib_Operator (Left_Tree, Right_Tree,
                 Imp),
               New_Lit (Ghdl_Compare_Eq),
               Std_Boolean_Type_Node);

         when Iir_Predefined_TF_Array_And
            | Iir_Predefined_TF_Array_Or
            | Iir_Predefined_TF_Array_Nand
            | Iir_Predefined_TF_Array_Nor
            | Iir_Predefined_TF_Array_Xor
            | Iir_Predefined_TF_Array_Xnor
            | Iir_Predefined_TF_Array_Not
            | Iir_Predefined_Array_Srl
            | Iir_Predefined_Array_Sra
            | Iir_Predefined_Array_Ror =>
            return Translate_Predefined_Array_Operator_Convert
              (Left_Tree, Right_Tree, Imp, Res_Type);

         when Iir_Predefined_Array_Sll
            | Iir_Predefined_Array_Sla
            | Iir_Predefined_Array_Rol =>
            Right_Tree := New_Monadic_Op (ON_Neg_Ov, Right_Tree);
            return Translate_Predefined_Array_Operator_Convert
              (Left_Tree, Right_Tree, Imp, Res_Type);

         when Iir_Predefined_Array_Array_Concat
            | Iir_Predefined_Element_Array_Concat
            | Iir_Predefined_Array_Element_Concat
            | Iir_Predefined_Element_Element_Concat =>
            return Translate_Concat_Operator
              (Left_Tree, Right_Tree, Imp, Res_Type, Loc);

         when Iir_Predefined_Endfile =>
            return Translate_Lib_Operator
              (Left_Tree, O_Enode_Null, Ghdl_File_Endfile);

         when Iir_Predefined_Now_Function =>
            return New_Obj_Value (Ghdl_Now);

         when Iir_Predefined_Std_Ulogic_Match_Equality =>
            return Translate_Std_Ulogic_Match
              (Ghdl_Std_Ulogic_Match_Eq,
               Left_Tree, Right_Tree, Res_Otype);
         when Iir_Predefined_Std_Ulogic_Match_Inequality =>
            return Translate_Std_Ulogic_Match
              (Ghdl_Std_Ulogic_Match_Ne,
               Left_Tree, Right_Tree, Res_Otype);
         when Iir_Predefined_Std_Ulogic_Match_Less =>
            return Translate_Std_Ulogic_Match
              (Ghdl_Std_Ulogic_Match_Lt,
               Left_Tree, Right_Tree, Res_Otype);
         when Iir_Predefined_Std_Ulogic_Match_Less_Equal =>
            return Translate_Std_Ulogic_Match
              (Ghdl_Std_Ulogic_Match_Le,
               Left_Tree, Right_Tree, Res_Otype);
         when Iir_Predefined_Std_Ulogic_Match_Greater =>
            return Translate_Std_Ulogic_Match
              (Ghdl_Std_Ulogic_Match_Lt,
               Right_Tree, Left_Tree, Res_Otype);
         when Iir_Predefined_Std_Ulogic_Match_Greater_Equal =>
            return Translate_Std_Ulogic_Match
              (Ghdl_Std_Ulogic_Match_Le,
               Right_Tree, Left_Tree, Res_Otype);

         when Iir_Predefined_Bit_Array_Match_Equality =>
            return New_Compare_Op
              (ON_Eq,
               Translate_Predefined_Lib_Operator
                 (Left_Tree, Right_Tree, Imp),
               New_Lit (Std_Boolean_True_Node),
               Res_Otype);
         when Iir_Predefined_Bit_Array_Match_Inequality =>
            return New_Compare_Op
              (ON_Eq,
               Translate_Predefined_Lib_Operator
                 (Left_Tree, Right_Tree, Imp),
               New_Lit (Std_Boolean_False_Node),
               Res_Otype);

         when Iir_Predefined_Array_Minimum =>
            return Translate_Predefined_Array_Min_Max
              (True, Left_Tree, Right_Tree, Left_Type, Right_Type,
               Res_Type, Imp, Loc);
         when Iir_Predefined_Array_Maximum =>
            return Translate_Predefined_Array_Min_Max
              (False, Left_Tree, Right_Tree, Left_Type, Right_Type,
               Res_Type, Imp, Loc);

         when Iir_Predefined_Integer_To_String =>
            case Get_Info (Left_Type).Type_Mode is
               when Type_Mode_I32 =>
                  return Translate_To_String
                    (Ghdl_To_String_I32, Res_Type, Loc,
                     New_Convert_Ov (Left_Tree, Ghdl_I32_Type));
               when others =>
                  raise Internal_Error;
            end case;
         when Iir_Predefined_Enum_To_String =>
            --  LRM08 5.7 String representations
            --  - For a given value of type CHARACTER, [...]
            --
            --  So special case for character.
            if Get_Base_Type (Left_Type) = Character_Type_Definition then
               return Translate_To_String
                 (Ghdl_To_String_Char, Res_Type, Loc, Left_Tree);
            end if;

            --  LRM08 5.7 String representations
            --  - For a given value of type other than CHARACTER, [...]
            declare
               Conv   : O_Tnode;
               Subprg : O_Dnode;
            begin
               case Get_Info (Left_Type).Type_Mode is
                  when Type_Mode_B1 =>
                     Subprg := Ghdl_To_String_B1;
                     Conv := Ghdl_Bool_Type;
                  when Type_Mode_E8 =>
                     Subprg := Ghdl_To_String_E8;
                     Conv := Ghdl_I32_Type;
                  when Type_Mode_E32 =>
                     Subprg := Ghdl_To_String_E32;
                     Conv := Ghdl_I32_Type;
                  when others =>
                     raise Internal_Error;
               end case;
               return Translate_To_String
                 (Subprg, Res_Type, Loc,
                  New_Convert_Ov (Left_Tree, Conv),
                  New_Lit (Rtis.New_Rti_Address
                    (Get_Info (Left_Type).Type_Rti)));
            end;
         when Iir_Predefined_Floating_To_String =>
            return Translate_To_String
              (Ghdl_To_String_F64, Res_Type, Loc,
               New_Convert_Ov (Left_Tree, Ghdl_Real_Type));
         when Iir_Predefined_Real_To_String_Digits =>
            return Translate_To_String
              (Ghdl_To_String_F64_Digits, Res_Type, Loc,
               New_Convert_Ov (Left_Tree, Ghdl_Real_Type),
               New_Convert_Ov (Right_Tree, Ghdl_I32_Type));
         when Iir_Predefined_Real_To_String_Format =>
            return Translate_To_String
              (Ghdl_To_String_F64_Format, Res_Type, Loc,
               New_Convert_Ov (Left_Tree, Ghdl_Real_Type),
               Right_Tree);
         when Iir_Predefined_Physical_To_String =>
            declare
               Conv   : O_Tnode;
               Subprg : O_Dnode;
            begin
               case Get_Info (Left_Type).Type_Mode is
                  when Type_Mode_P32 =>
                     Subprg := Ghdl_To_String_P32;
                     Conv := Ghdl_I32_Type;
                  when Type_Mode_P64 =>
                     Subprg := Ghdl_To_String_P64;
                     Conv := Ghdl_I64_Type;
                  when others =>
                     raise Internal_Error;
               end case;
               return Translate_To_String
                 (Subprg, Res_Type, Loc,
                  New_Convert_Ov (Left_Tree, Conv),
                  New_Lit (Rtis.New_Rti_Address
                    (Get_Info (Left_Type).Type_Rti)));
            end;
         when Iir_Predefined_Time_To_String_Unit =>
            return Translate_To_String
              (Ghdl_Time_To_String_Unit, Res_Type, Loc,
               Left_Tree, Right_Tree,
               New_Lit (Rtis.New_Rti_Address
                 (Get_Info (Left_Type).Type_Rti)));
         when Iir_Predefined_Bit_Vector_To_Ostring =>
            return Translate_Bv_To_String
              (Ghdl_BV_To_Ostring, Left_Tree, Left_Type, Res_Type, Loc);
         when Iir_Predefined_Bit_Vector_To_Hstring =>
            return Translate_Bv_To_String
              (Ghdl_BV_To_Hstring, Left_Tree, Left_Type, Res_Type, Loc);
         when Iir_Predefined_Array_Char_To_String =>
            declare
               El_Type : constant Iir := Get_Element_Subtype (Left_Type);
               Subprg  : O_Dnode;
               Arg     : Mnode;
            begin
               Arg := Stabilize
                 (E2M (Left_Tree, Get_Info (Left_Type), Mode_Value));
               case Get_Info (El_Type).Type_Mode is
                  when Type_Mode_B1 =>
                     Subprg := Ghdl_Array_Char_To_String_B1;
                  when Type_Mode_E8 =>
                     Subprg := Ghdl_Array_Char_To_String_E8;
                  when Type_Mode_E32 =>
                     Subprg := Ghdl_Array_Char_To_String_E32;
                  when others =>
                     raise Internal_Error;
               end case;
               return Translate_To_String
                 (Subprg, Res_Type, Loc,
                  New_Convert_Ov (M2E (Chap3.Get_Array_Base (Arg)),
                    Ghdl_Ptr_Type),
                  Chap3.Get_Array_Length (Arg, Left_Type),
                  New_Lit (Rtis.New_Rti_Address
                    (Get_Info (El_Type).Type_Rti)));
            end;

         when others =>
            Ada.Text_IO.Put_Line
              ("translate_predefined_operator(2): cannot handle "
               & Iir_Predefined_Functions'Image (Kind));
            raise Internal_Error;
            return O_Enode_Null;
      end case;
   end Translate_Predefined_Operator;

   --  Assign EXPR to TARGET.
   procedure Translate_Assign
     (Target : Mnode; Val : O_Enode; Expr : Iir; Target_Type : Iir; Loc : Iir)
   is
      T_Info : constant Type_Info_Acc := Get_Info (Target_Type);
   begin
      case T_Info.Type_Mode is
         when Type_Mode_Scalar =>
            New_Assign_Stmt
              (M2Lv (Target),
               Chap3.Maybe_Insert_Scalar_Check (Val, Expr, Target_Type));
         when Type_Mode_Acc
            | Type_Mode_File =>
            New_Assign_Stmt (M2Lv (Target), Val);
         when Type_Mode_Fat_Acc =>
            Chap3.Translate_Object_Copy (Target, Val, Target_Type);
         when Type_Mode_Fat_Array =>
            declare
               T : Mnode;
               E : O_Dnode;
            begin
               T := Stabilize (Target);
               E := Create_Temp_Init
                 (T_Info.Ortho_Ptr_Type (Mode_Value), Val);
               Chap3.Check_Array_Match
                 (Target_Type, T,
                  Get_Type (Expr), Dp2M (E, T_Info, Mode_Value), Loc);
               Chap3.Translate_Object_Copy
                 (T, New_Obj_Value (E), Target_Type);
            end;
         when Type_Mode_Array =>
            --  Source is of type TARGET_TYPE, so no length check is
            --  necessary.
            Chap3.Translate_Object_Copy (Target, Val, Target_Type);
         when Type_Mode_Record =>
            Chap3.Translate_Object_Copy (Target, Val, Target_Type);
         when Type_Mode_Unknown
            | Type_Mode_Protected =>
            raise Internal_Error;
      end case;
   end Translate_Assign;

   procedure Translate_Assign (Target : Mnode; Expr : Iir; Target_Type : Iir)
   is
      Val : O_Enode;
   begin
      if Get_Kind (Expr) = Iir_Kind_Aggregate then
         --  FIXME: handle overlap between TARGET and EXPR.
         Translate_Aggregate (Target, Target_Type, Expr);
      else
         Open_Temp;
         Val := Chap7.Translate_Expression (Expr, Target_Type);
         Translate_Assign (Target, Val, Expr, Target_Type, Expr);
         Close_Temp;
      end if;
   end Translate_Assign;

   --  If AGGR is of the form (others => (others => EXPR)) (where the
   --   number of (others => ) sub-aggregate is at least 1, return EXPR
   --   otherwise return NULL_IIR.
   function Is_Aggregate_Others (Aggr : Iir_Aggregate) return Iir
   is
      Chain : Iir;
      Aggr1 : Iir;
      --Type_Info : Type_Info_Acc;
   begin
      Aggr1 := Aggr;
      --  Do not use translate_aggregate_others for a complex type.
      --Type_Info := Get_Info (Get_Type (Aggr));
      --if Type_Info.C /= null and then Type_Info.C.Builder_Need_Func then
      --   return Null_Iir;
      --end if;
      loop
         Chain := Get_Association_Choices_Chain (Aggr1);
         if not Is_Chain_Length_One (Chain) then
            return Null_Iir;
         end if;
         if Get_Kind (Chain) /= Iir_Kind_Choice_By_Others then
            return Null_Iir;
         end if;
         Aggr1 := Get_Associated_Expr (Chain);
         case Get_Kind (Aggr1) is
            when Iir_Kind_Aggregate =>
               if Get_Type (Aggr1) /= Null_Iir then
                  --  Stop when a sub-aggregate is in fact an aggregate.
                  return Aggr1;
               end if;
            when Iir_Kind_String_Literal
               | Iir_Kind_Bit_String_Literal =>
               return Null_Iir;
               --Error_Kind ("is_aggregate_others", Aggr1);
            when others =>
               return Aggr1;
         end case;
      end loop;
   end Is_Aggregate_Others;

   --  Generate code for (others => EL).
   procedure Translate_Aggregate_Others
     (Target : Mnode; Target_Type : Iir; El : Iir)
   is
      Base_Ptr : Mnode;
      Info     : Type_Info_Acc;
      It       : O_Dnode;
      Len      : O_Dnode;
      Len_Val  : O_Enode;
      Label    : O_Snode;
      Arr_Var  : Mnode;
      El_Node  : Mnode;
   begin
      Open_Temp;

      Info := Get_Info (Target_Type);
      case Info.Type_Mode is
         when Type_Mode_Fat_Array =>
            Arr_Var := Stabilize (Target);
            Base_Ptr := Stabilize (Chap3.Get_Array_Base (Arr_Var));
            Len_Val := Chap3.Get_Array_Length (Arr_Var, Target_Type);
         when Type_Mode_Array =>
            Base_Ptr := Stabilize (Chap3.Get_Array_Base (Target));
            Len_Val := Chap3.Get_Array_Type_Length (Target_Type);
         when others =>
            raise Internal_Error;
      end case;
      --  FIXME: use this (since this use one variable instead of two):
      --  I := length;
      --  loop
      --    exit when I = 0;
      --    I := I - 1;
      --    A[I] := xxx;
      --  end loop;
      Len := Create_Temp_Init (Ghdl_Index_Type, Len_Val);
      if True then
         It := Create_Temp (Ghdl_Index_Type);
      else
         New_Var_Decl (It, Wki_I, O_Storage_Local, Ghdl_Index_Type);
      end if;
      Init_Var (It);
      Start_Loop_Stmt (Label);
      Gen_Exit_When
        (Label, New_Compare_Op (ON_Eq,
         New_Obj_Value (It), New_Obj_Value (Len),
         Ghdl_Bool_Type));
      El_Node := Chap3.Index_Base (Base_Ptr, Target_Type,
                                   New_Obj_Value (It));
      --New_Assign_Stmt (El_Node, Chap7.Translate_Expression (El));
      Translate_Assign (El_Node, El, Get_Element_Subtype (Target_Type));
      Inc_Var (It);
      Finish_Loop_Stmt (Label);

      Close_Temp;
   end Translate_Aggregate_Others;

   procedure Translate_Array_Aggregate_Gen
     (Base_Ptr   : Mnode;
      Bounds_Ptr : Mnode;
      Aggr       : Iir;
      Aggr_Type  : Iir;
      Dim        : Natural;
      Var_Index  : O_Dnode)
   is
      Index_List : Iir_List;
      Expr_Type  : Iir;
      Final      : Boolean;

      procedure Do_Assign (Expr : Iir)
      is
      begin
         if Final then
            Translate_Assign (Chap3.Index_Base (Base_Ptr, Aggr_Type,
                              New_Obj_Value (Var_Index)),
                              Expr, Expr_Type);
            Inc_Var (Var_Index);
         else
            Translate_Array_Aggregate_Gen
              (Base_Ptr, Bounds_Ptr, Expr, Aggr_Type, Dim + 1, Var_Index);
         end if;
      end Do_Assign;

      P  : Natural;
      El : Iir;
   begin
      case Get_Kind (Aggr) is
         when Iir_Kind_Aggregate =>
            --  Continue below.
            null;
         when Iir_Kind_String_Literal
            | Iir_Kind_Bit_String_Literal =>
            declare
               Len : constant Nat32 := Get_String_Length (Aggr);

               --  Type of the unconstrained array type.
               Arr_Type : O_Tnode;

               --  Type of the constrained array type.
               Str_Type : O_Tnode;

               Cst   : Var_Type;
               Var_I : O_Dnode;
               Label : O_Snode;
            begin
               Expr_Type := Get_Element_Subtype (Aggr_Type);

               --  Create a constant for the string.
               --  First, create its type, because the literal has no
               --  type (subaggregate).
               Arr_Type := New_Array_Type
                 (Get_Ortho_Type (Expr_Type, Mode_Value),
                  Ghdl_Index_Type);
               New_Type_Decl (Create_Uniq_Identifier, Arr_Type);
               Str_Type := New_Constrained_Array_Type
                 (Arr_Type, New_Index_Lit (Unsigned_64 (Len)));
               Cst := Create_String_Literal_Var_Inner
                 (Aggr, Expr_Type, Str_Type);

               --  Copy it.
               Open_Temp;
               Var_I := Create_Temp (Ghdl_Index_Type);
               Init_Var (Var_I);
               Start_Loop_Stmt (Label);
               Gen_Exit_When
                 (Label,
                  New_Compare_Op (ON_Eq,
                    New_Obj_Value (Var_I),
                    New_Lit (New_Index_Lit (Nat32'Pos (Len))),
                    Ghdl_Bool_Type));
               New_Assign_Stmt
                 (M2Lv (Chap3.Index_Base (Base_Ptr, Aggr_Type,
                  New_Obj_Value (Var_Index))),
                  New_Value (New_Indexed_Element (Get_Var (Cst),
                    New_Obj_Value (Var_I))));
               Inc_Var (Var_I);
               Inc_Var (Var_Index);
               Finish_Loop_Stmt (Label);
               Close_Temp;
            end;
            return;
         when others =>
            raise Internal_Error;
      end case;

      Index_List := Get_Index_Subtype_List (Aggr_Type);

      --  FINAL is true if the elements of the aggregate are elements of
      --  the array.
      if Get_Nbr_Elements (Index_List) = Dim then
         Expr_Type := Get_Element_Subtype (Aggr_Type);
         Final:= True;
      else
         Final := False;
      end if;

      El := Get_Association_Choices_Chain (Aggr);

      --  First, assign positionnal association.
      --  FIXME: count the number of positionnal association and generate
      --   an error if there is more positionnal association than elements
      --   in the array.
      P := 0;
      loop
         if El = Null_Iir then
            --  There is only positionnal associations.
            return;
         end if;
         exit when Get_Kind (El) /= Iir_Kind_Choice_By_None;
         Do_Assign (Get_Associated_Expr (El));
         P := P + 1;
         El := Get_Chain (El);
      end loop;

      --  Then, assign named or others association.
      if Get_Chain (El) = Null_Iir then
         --  There is only one choice
         case Get_Kind (El) is
            when Iir_Kind_Choice_By_Others =>
               --  falltrough...
               null;
            when Iir_Kind_Choice_By_Expression =>
               Do_Assign (Get_Associated_Expr (El));
               return;
            when Iir_Kind_Choice_By_Range =>
               declare
                  Var_Length : O_Dnode;
                  Var_I      : O_Dnode;
                  Label      : O_Snode;
               begin
                  Open_Temp;
                  Var_Length := Create_Temp_Init
                    (Ghdl_Index_Type,
                     Chap7.Translate_Range_Length (Get_Choice_Range (El)));
                  Var_I := Create_Temp (Ghdl_Index_Type);
                  Init_Var (Var_I);
                  Start_Loop_Stmt (Label);
                  Gen_Exit_When (Label,
                                 New_Compare_Op (ON_Eq,
                                   New_Obj_Value (Var_I),
                                   New_Obj_Value (Var_Length),
                                   Ghdl_Bool_Type));
                  Do_Assign (Get_Associated_Expr (El));
                  Inc_Var (Var_I);
                  Finish_Loop_Stmt (Label);
                  Close_Temp;
               end;
               return;
            when others =>
               Error_Kind ("translate_array_aggregate_gen", El);
         end case;
      end if;

      --  Several choices..
      declare
         Range_Type : Iir;
         Var_Pos    : O_Dnode;
         Var_Len    : O_Dnode;
         Range_Ptr  : Mnode;
         Rtinfo     : Type_Info_Acc;
         If_Blk     : O_If_Block;
         Case_Blk   : O_Case_Block;
         Label      : O_Snode;
         El_Assoc   : Iir;
         Len_Tmp    : O_Enode;
      begin
         Open_Temp;
         --  Create a loop from left +- number of positionnals associations
         --   to/downto right.
         Range_Type :=
           Get_Base_Type (Get_Nth_Element (Index_List, Dim - 1));
         Rtinfo := Get_Info (Range_Type);
         Var_Pos := Create_Temp (Rtinfo.Ortho_Type (Mode_Value));
         Range_Ptr := Stabilize
           (Chap3.Bounds_To_Range (Bounds_Ptr, Aggr_Type, Dim));
         New_Assign_Stmt (New_Obj (Var_Pos),
                          M2E (Chap3.Range_To_Left (Range_Ptr)));
         Var_Len := Create_Temp (Ghdl_Index_Type);
         if P /= 0 then
            Start_If_Stmt
              (If_Blk,
               New_Compare_Op (ON_Eq,
                 M2E (Chap3.Range_To_Dir (Range_Ptr)),
                 New_Lit (Ghdl_Dir_To_Node),
                 Ghdl_Bool_Type));
            Chap8.Gen_Update_Iterator (Var_Pos, Iir_To, Unsigned_64 (P),
                                       Range_Type);
            New_Else_Stmt (If_Blk);
            Chap8.Gen_Update_Iterator (Var_Pos, Iir_Downto, Unsigned_64 (P),
                                       Range_Type);
            Finish_If_Stmt (If_Blk);
         end if;

         Len_Tmp := M2E (Chap3.Range_To_Length (Range_Ptr));
         if P /= 0 then
            Len_Tmp := New_Dyadic_Op
              (ON_Sub_Ov,
               Len_Tmp,
               New_Lit (New_Unsigned_Literal (Ghdl_Index_Type,
                 Unsigned_64 (P))));
         end if;
         New_Assign_Stmt (New_Obj (Var_Len), Len_Tmp);

         --  Start loop.
         Start_Loop_Stmt (Label);
         --  Check if end of loop.
         Gen_Exit_When
           (Label,
            New_Compare_Op (ON_Eq,
              New_Obj_Value (Var_Len),
              New_Lit (Ghdl_Index_0),
              Ghdl_Bool_Type));

         --  convert aggr into a case statement.
         Start_Case_Stmt (Case_Blk, New_Obj_Value (Var_Pos));
         El_Assoc := Null_Iir;
         while El /= Null_Iir loop
            Start_Choice (Case_Blk);
            Chap8.Translate_Case_Choice (El, Range_Type, Case_Blk);
            if Get_Associated_Expr (El) /= Null_Iir then
               El_Assoc := Get_Associated_Expr (El);
            end if;
            Finish_Choice (Case_Blk);
            Do_Assign (El_Assoc);
            P := P + 1;
            El := Get_Chain (El);
         end loop;
         Finish_Case_Stmt (Case_Blk);
         --  Update var_pos
         Start_If_Stmt
           (If_Blk,
            New_Compare_Op (ON_Eq,
              M2E (Chap3.Range_To_Dir (Range_Ptr)),
              New_Lit (Ghdl_Dir_To_Node),
              Ghdl_Bool_Type));
         Chap8.Gen_Update_Iterator (Var_Pos, Iir_To, Unsigned_64 (1),
                                    Range_Type);
         New_Else_Stmt (If_Blk);
         Chap8.Gen_Update_Iterator (Var_Pos, Iir_Downto, Unsigned_64 (1),
                                    Range_Type);
         Finish_If_Stmt (If_Blk);
         New_Assign_Stmt
           (New_Obj (Var_Len),
            New_Dyadic_Op (ON_Sub_Ov,
              New_Obj_Value (Var_Len),
              New_Lit (Ghdl_Index_1)));
         Finish_Loop_Stmt (Label);
         Close_Temp;
      end;
   end Translate_Array_Aggregate_Gen;

   procedure Translate_Record_Aggregate (Target : Mnode; Aggr : Iir)
   is
      Targ           : Mnode;
      Aggr_Type      : constant Iir := Get_Type (Aggr);
      Aggr_Base_Type : constant Iir_Record_Type_Definition :=
        Get_Base_Type (Aggr_Type);
      El_List        : constant Iir_List :=
        Get_Elements_Declaration_List (Aggr_Base_Type);
      El_Index       : Natural;
      Nbr_El         : constant Natural := Get_Nbr_Elements (El_List);

      --  Record which elements of the record have been set.  The 'others'
      --  clause applies to all elements not already set.
      type Bool_Array_Type is array (0 .. Nbr_El - 1) of Boolean;
      pragma Pack (Bool_Array_Type);
      Set_Array : Bool_Array_Type := (others => False);

      --  The expression associated.
      El_Expr : Iir;

      --  Set an elements.
      procedure Set_El (El : Iir_Element_Declaration) is
      begin
         Translate_Assign (Chap6.Translate_Selected_Element (Targ, El),
                           El_Expr, Get_Type (El));
         Set_Array (Natural (Get_Element_Position (El))) := True;
      end Set_El;

      Assoc     : Iir;
      N_El_Expr : Iir;
   begin
      Open_Temp;
      Targ := Stabilize (Target);
      El_Index := 0;
      Assoc := Get_Association_Choices_Chain (Aggr);
      while Assoc /= Null_Iir loop
         N_El_Expr := Get_Associated_Expr (Assoc);
         if N_El_Expr /= Null_Iir then
            El_Expr := N_El_Expr;
         end if;
         case Get_Kind (Assoc) is
            when Iir_Kind_Choice_By_None =>
               Set_El (Get_Nth_Element (El_List, El_Index));
               El_Index := El_Index + 1;
            when Iir_Kind_Choice_By_Name =>
               Set_El (Get_Choice_Name (Assoc));
               El_Index := Natural'Last;
            when Iir_Kind_Choice_By_Others =>
               for J in Set_Array'Range loop
                  if not Set_Array (J) then
                     Set_El (Get_Nth_Element (El_List, J));
                  end if;
               end loop;
            when others =>
               Error_Kind ("translate_record_aggregate", Assoc);
         end case;
         Assoc := Get_Chain (Assoc);
      end loop;
      Close_Temp;
   end Translate_Record_Aggregate;

   procedure Translate_Array_Aggregate
     (Target : Mnode; Target_Type : Iir; Aggr : Iir)
   is
      Aggr_Type       : constant Iir := Get_Type (Aggr);
      Index_List      : constant Iir_List :=
        Get_Index_Subtype_List (Aggr_Type);
      Targ_Index_List : constant Iir_List :=
        Get_Index_Subtype_List (Target_Type);

      Aggr_Info : Iir_Aggregate_Info;
      Base      : Mnode;
      Bounds    : Mnode;
      Var_Index : O_Dnode;
      Targ      : Mnode;

      Rinfo : Type_Info_Acc;
      Bt    : Iir;

      --  Generate code for: (LVAL lop RNG.left) or (RVAL rop RNG.right)
      function Check_Value (Lval : Iir;
                            Lop  : ON_Op_Kind;
                            Rval : Iir;
                            Rop  : ON_Op_Kind;
                            Rng  : Mnode)
                               return O_Enode
      is
         L, R : O_Enode;
      begin
         L := New_Compare_Op
           (Lop,
            New_Lit (Translate_Static_Expression (Lval, Bt)),
            M2E (Chap3.Range_To_Left (Rng)),
            Ghdl_Bool_Type);
         R := New_Compare_Op
           (Rop,
            New_Lit (Translate_Static_Expression (Rval, Bt)),
            M2E (Chap3.Range_To_Right (Rng)),
            Ghdl_Bool_Type);
         return New_Dyadic_Op (ON_Or, L, R);
      end Check_Value;

      Range_Ptr    : Mnode;
      Subtarg_Type : Iir;
      Subaggr_Type : Iir;
      L, H         : Iir;
      Min          : Iir_Int32;
      Has_Others   : Boolean;

      Var_Err : O_Dnode;
      E       : O_Enode;
      If_Blk  : O_If_Block;
      Op      : ON_Op_Kind;
   begin
      Open_Temp;
      Targ := Stabilize (Target);
      Base := Stabilize (Chap3.Get_Array_Base (Targ));
      Bounds := Stabilize (Chap3.Get_Array_Bounds (Targ));
      Aggr_Info := Get_Aggregate_Info (Aggr);

      --  Check type
      for I in Natural loop
         Subaggr_Type := Get_Index_Type (Index_List, I);
         exit when Subaggr_Type = Null_Iir;
         Subtarg_Type := Get_Index_Type (Targ_Index_List, I);

         Bt := Get_Base_Type (Subaggr_Type);
         Rinfo := Get_Info (Bt);

         if Get_Aggr_Dynamic_Flag (Aggr_Info) then
            --  Dynamic range, must evaluate it.
            Open_Temp;
            declare
               A_Range : O_Dnode;
               Rng_Ptr : O_Dnode;
            begin
               --  Evaluate the range.
               Chap3.Translate_Anonymous_Type_Definition
                 (Subaggr_Type, True);

               A_Range := Create_Temp (Rinfo.T.Range_Type);
               Rng_Ptr := Create_Temp_Ptr
                 (Rinfo.T.Range_Ptr_Type, New_Obj (A_Range));
               Chap7.Translate_Range_Ptr
                 (Rng_Ptr,
                  Get_Range_Constraint (Subaggr_Type),
                  Subaggr_Type);

               --  Check range length VS target length.
               Chap6.Check_Bound_Error
                 (New_Compare_Op
                    (ON_Neq,
                     M2E (Chap3.Range_To_Length
                       (Dv2M (A_Range,
                            Rinfo,
                            Mode_Value,
                            Rinfo.T.Range_Type,
                            Rinfo.T.Range_Ptr_Type))),
                     M2E (Chap3.Range_To_Length
                       (Chap3.Bounds_To_Range
                            (Bounds, Target_Type, I + 1))),
                     Ghdl_Bool_Type),
                  Aggr, I);
            end;
            Close_Temp;
         elsif Get_Type_Staticness (Subaggr_Type) /= Locally
           or else Subaggr_Type /= Subtarg_Type
         then
            --  Note: if the aggregate has no others, then the bounds
            --  must be the same, otherwise, aggregate bounds must be
            --  inside type bounds.
            Has_Others := Get_Aggr_Others_Flag (Aggr_Info);
            Min := Get_Aggr_Min_Length (Aggr_Info);
            L := Get_Aggr_Low_Limit (Aggr_Info);

            if Min > 0 or L /= Null_Iir then
               Open_Temp;

               --  Pointer to the range.
               Range_Ptr := Stabilize
                 (Chap3.Bounds_To_Range (Bounds, Target_Type, I + 1));
               Var_Err := Create_Temp (Ghdl_Bool_Type);
               H := Get_Aggr_High_Limit (Aggr_Info);

               if L /= Null_Iir then
                  --  Check the index range of the aggregrate is equal
                  --  (or within in presence of 'others') the index range
                  --  of the target.
                  Start_If_Stmt
                    (If_Blk,
                     New_Compare_Op (ON_Eq,
                       M2E (Chap3.Range_To_Dir (Range_Ptr)),
                       New_Lit (Ghdl_Dir_To_Node),
                       Ghdl_Bool_Type));
                  if Has_Others then
                     E := Check_Value (L, ON_Lt, H, ON_Gt, Range_Ptr);
                  else
                     E := Check_Value (L, ON_Neq, H, ON_Neq, Range_Ptr);
                  end if;
                  New_Assign_Stmt (New_Obj (Var_Err), E);
                  New_Else_Stmt (If_Blk);
                  if Has_Others then
                     E := Check_Value (H, ON_Gt, L, ON_Lt, Range_Ptr);
                  else
                     E := Check_Value (H, ON_Neq, L, ON_Neq, Range_Ptr);
                  end if;
                  New_Assign_Stmt (New_Obj (Var_Err), E);
                  Finish_If_Stmt (If_Blk);
                  -- If L and H are greather than the minimum length,
                  -- then there is no need to check with min.
                  if Iir_Int32 (Eval_Pos (H) - Eval_Pos (L) + 1) >= Min then
                     Min := 0;
                  end if;
               end if;

               if Min > 0 then
                  --  Check the number of elements is equal (or less in
                  --  presence of 'others') than the length of the index
                  --  range of the target.
                  if Has_Others then
                     Op := ON_Lt;
                  else
                     Op := ON_Neq;
                  end if;
                  E := New_Compare_Op
                    (Op,
                     M2E (Chap3.Range_To_Length (Range_Ptr)),
                     New_Lit (New_Unsigned_Literal (Ghdl_Index_Type,
                       Unsigned_64 (Min))),
                     Ghdl_Bool_Type);
                  if L /= Null_Iir then
                     E := New_Dyadic_Op (ON_Or, E, New_Obj_Value (Var_Err));
                  end if;
                  New_Assign_Stmt (New_Obj (Var_Err), E);
               end if;
               Chap6.Check_Bound_Error (New_Obj_Value (Var_Err), Aggr, I);
               Close_Temp;
            end if;
         end if;

         --  Next dimension.
         Aggr_Info := Get_Sub_Aggregate_Info (Aggr_Info);
      end loop;

      Var_Index := Create_Temp_Init
        (Ghdl_Index_Type, New_Lit (Ghdl_Index_0));
      Translate_Array_Aggregate_Gen
        (Base, Bounds, Aggr, Aggr_Type, 1, Var_Index);
      Close_Temp;

      --  FIXME: creating aggregate subtype is expensive and rarely used.
      --  (one of the current use - only ? - is check_array_match).
      Chap3.Translate_Anonymous_Type_Definition (Aggr_Type, False);
   end Translate_Array_Aggregate;

   procedure Translate_Aggregate
     (Target : Mnode; Target_Type : Iir; Aggr : Iir)
   is
      Aggr_Type : constant Iir := Get_Type (Aggr);
      El        : Iir;
   begin
      case Get_Kind (Aggr_Type) is
         when Iir_Kind_Array_Subtype_Definition
            | Iir_Kind_Array_Type_Definition =>
            El := Is_Aggregate_Others (Aggr);
            if El /= Null_Iir then
               Translate_Aggregate_Others (Target, Target_Type, El);
            else
               Translate_Array_Aggregate (Target, Target_Type, Aggr);
            end if;
         when Iir_Kind_Record_Type_Definition
            | Iir_Kind_Record_Subtype_Definition =>
            Translate_Record_Aggregate (Target, Aggr);
         when others =>
            Error_Kind ("translate_aggregate", Aggr_Type);
      end case;
   end Translate_Aggregate;

   function Translate_Allocator_By_Expression (Expr : Iir) return O_Enode
   is
      Val    : O_Enode;
      Val_M  : Mnode;
      A_Type : constant Iir := Get_Type (Expr);
      A_Info : constant Type_Info_Acc := Get_Info (A_Type);
      D_Type : constant Iir := Get_Designated_Type (A_Type);
      D_Info : constant Type_Info_Acc := Get_Info (D_Type);
      R      : Mnode;
      Rtype  : O_Tnode;
   begin
      --  Compute the expression.
      Val := Translate_Expression (Get_Expression (Expr), D_Type);
      --  Allocate memory for the object.
      case A_Info.Type_Mode is
         when Type_Mode_Fat_Acc =>
            R := Dv2M (Create_Temp (D_Info.Ortho_Type (Mode_Value)),
                       D_Info, Mode_Value);
            Val_M := Stabilize (E2M (Val, D_Info, Mode_Value));
            Chap3.Translate_Object_Allocation
              (R, Alloc_Heap, D_Type,
               Chap3.Get_Array_Bounds (Val_M));
            Val := M2E (Val_M);
            Rtype := A_Info.Ortho_Ptr_Type (Mode_Value);
         when Type_Mode_Acc =>
            R := Dp2M (Create_Temp (D_Info.Ortho_Ptr_Type (Mode_Value)),
                       D_Info, Mode_Value);
            Chap3.Translate_Object_Allocation
              (R, Alloc_Heap, D_Type, Mnode_Null);
            Rtype := A_Info.Ortho_Type (Mode_Value);
         when others =>
            raise Internal_Error;
      end case;
      Chap3.Translate_Object_Copy (R, Val, D_Type);
      return New_Convert_Ov (M2Addr (R), Rtype);
   end Translate_Allocator_By_Expression;

   function Translate_Allocator_By_Subtype (Expr : Iir) return O_Enode
   is
      P_Type   : constant Iir := Get_Type (Expr);
      P_Info   : constant Type_Info_Acc := Get_Info (P_Type);
      D_Type   : constant Iir := Get_Designated_Type (P_Type);
      D_Info   : constant Type_Info_Acc := Get_Info (D_Type);
      Sub_Type : Iir;
      Bounds   : Mnode;
      Res      : Mnode;
      Rtype    : O_Tnode;
   begin
      case P_Info.Type_Mode is
         when Type_Mode_Fat_Acc =>
            Res := Dv2M (Create_Temp (D_Info.Ortho_Type (Mode_Value)),
                         D_Info, Mode_Value);
            --  FIXME: should allocate bounds, and directly set bounds
            --  from the range.
            Sub_Type := Get_Subtype_Indication (Expr);
            Sub_Type := Get_Type_Of_Subtype_Indication (Sub_Type);
            Chap3.Create_Array_Subtype (Sub_Type, True);
            Bounds := Chap3.Get_Array_Type_Bounds (Sub_Type);
            Rtype := P_Info.Ortho_Ptr_Type (Mode_Value);
         when Type_Mode_Acc =>
            Res := Dp2M (Create_Temp (D_Info.Ortho_Ptr_Type (Mode_Value)),
                         D_Info, Mode_Value);
            Bounds := Mnode_Null;
            Rtype := P_Info.Ortho_Type (Mode_Value);
         when others =>
            raise Internal_Error;
      end case;
      Chap3.Translate_Object_Allocation (Res, Alloc_Heap, D_Type, Bounds);
      Chap4.Init_Object (Res, D_Type);
      return New_Convert_Ov (M2Addr (Res), Rtype);
   end Translate_Allocator_By_Subtype;

   function Translate_Fat_Array_Type_Conversion
     (Expr : O_Enode; Expr_Type : Iir; Res_Type : Iir; Loc : Iir)
     return O_Enode;

   function Translate_Array_Subtype_Conversion
     (Expr : O_Enode; Expr_Type : Iir; Res_Type : Iir; Loc : Iir)
     return O_Enode
   is
      Res_Info  : constant Type_Info_Acc := Get_Info (Res_Type);
      Expr_Info : constant Type_Info_Acc := Get_Info (Expr_Type);
      E         : Mnode;
   begin
      E := Stabilize (E2M (Expr, Expr_Info, Mode_Value));
      case Res_Info.Type_Mode is
         when Type_Mode_Array =>
            Chap3.Check_Array_Match
              (Res_Type, T2M (Res_Type, Mode_Value),
               Expr_Type, E,
               Loc);
            return New_Convert_Ov
              (M2Addr (Chap3.Get_Array_Base (E)),
               Res_Info.Ortho_Ptr_Type (Mode_Value));
         when Type_Mode_Fat_Array =>
            declare
               Res : Mnode;
            begin
               Res := Create_Temp (Res_Info);
               Copy_Fat_Pointer (Res, E);
               Chap3.Check_Array_Match (Res_Type, Res, Expr_Type, E, Loc);
               return M2Addr (Res);
            end;
         when others =>
            Error_Kind ("translate_array_subtype_conversion", Res_Type);
      end case;
   end Translate_Array_Subtype_Conversion;

   function Translate_Type_Conversion
     (Expr : O_Enode; Expr_Type : Iir; Res_Type : Iir; Loc : Iir)
     return O_Enode
   is
      Res_Info : constant Type_Info_Acc := Get_Info (Res_Type);
      Res      : O_Enode;
   begin
      case Get_Kind (Res_Type) is
         when Iir_Kinds_Scalar_Type_Definition =>
            Res := New_Convert_Ov (Expr, Res_Info.Ortho_Type (Mode_Value));
            if Chap3.Need_Range_Check (Null_Iir, Res_Type) then
               Res := Chap3.Insert_Scalar_Check
                 (Res, Null_Iir, Res_Type, Loc);
            end if;
            return Res;
         when Iir_Kinds_Array_Type_Definition =>
            if Get_Constraint_State (Res_Type) = Fully_Constrained then
               return Translate_Array_Subtype_Conversion
                 (Expr, Expr_Type, Res_Type, Loc);
            else
               return Translate_Fat_Array_Type_Conversion
                 (Expr, Expr_Type, Res_Type, Loc);
            end if;
         when Iir_Kind_Record_Type_Definition
            | Iir_Kind_Record_Subtype_Definition =>
            return Expr;
         when others =>
            Error_Kind ("translate_type_conversion", Res_Type);
      end case;
   end Translate_Type_Conversion;

   function Translate_Fat_Array_Type_Conversion
     (Expr : O_Enode; Expr_Type : Iir; Res_Type : Iir; Loc : Iir)
     return O_Enode
   is
      Res_Info     : constant Type_Info_Acc := Get_Info (Res_Type);
      Expr_Info    : constant Type_Info_Acc := Get_Info (Expr_Type);
      Res_Indexes  : constant Iir_List :=
        Get_Index_Subtype_List (Res_Type);
      Expr_Indexes : constant Iir_List :=
        Get_Index_Subtype_List (Expr_Type);

      Res_Base_Type     : constant Iir := Get_Base_Type (Res_Type);
      Expr_Base_Type    : constant Iir := Get_Base_Type (Expr_Type);
      Res_Base_Indexes  : constant Iir_List :=
        Get_Index_Subtype_List (Res_Base_Type);
      Expr_Base_Indexes : constant Iir_List :=
        Get_Index_Subtype_List (Expr_Base_Type);
      Res               : Mnode;
      E                 : Mnode;
      Bounds            : O_Dnode;
      R_El              : Iir;
      E_El              : Iir;
   begin
      Res := Create_Temp (Res_Info, Mode_Value);
      Bounds := Create_Temp (Res_Info.T.Bounds_Type);
      E := Stabilize (E2M (Expr, Expr_Info, Mode_Value));
      Open_Temp;
      --  Set base.
      New_Assign_Stmt
        (M2Lp (Chap3.Get_Array_Base (Res)),
         New_Convert_Ov (M2Addr (Chap3.Get_Array_Base (E)),
           Res_Info.T.Base_Ptr_Type (Mode_Value)));
      --  Set bounds.
      New_Assign_Stmt
        (M2Lp (Chap3.Get_Array_Bounds (Res)),
         New_Address (New_Obj (Bounds), Res_Info.T.Bounds_Ptr_Type));

      --  Convert bounds.
      for I in Natural loop
         R_El := Get_Index_Type (Res_Indexes, I);
         E_El := Get_Index_Type (Expr_Indexes, I);
         exit when R_El = Null_Iir;
         declare
            Rb_Ptr          : Mnode;
            Eb_Ptr          : Mnode;
            Ee              : O_Enode;
            Same_Index_Type : constant Boolean :=
              (Get_Index_Type (Res_Base_Indexes, I)
               = Get_Index_Type (Expr_Base_Indexes, I));
         begin
            Open_Temp;
            Rb_Ptr := Stabilize
              (Chap3.Get_Array_Range (Res, Res_Type, I + 1));
            Eb_Ptr := Stabilize
              (Chap3.Get_Array_Range (E, Expr_Type, I + 1));
            --  Convert left and right (unless they have the same type -
            --  this is an optimization but also this deals with null
            --  array in common cases).
            Ee := M2E (Chap3.Range_To_Left (Eb_Ptr));
            if not Same_Index_Type then
               Ee := Translate_Type_Conversion (Ee, E_El, R_El, Loc);
            end if;
            New_Assign_Stmt (M2Lv (Chap3.Range_To_Left (Rb_Ptr)), Ee);
            Ee := M2E (Chap3.Range_To_Right (Eb_Ptr));
            if not Same_Index_Type then
               Ee := Translate_Type_Conversion (Ee, E_El, R_El, Loc);
            end if;
            New_Assign_Stmt (M2Lv (Chap3.Range_To_Right (Rb_Ptr)), Ee);
            --  Copy Dir and Length.
            New_Assign_Stmt (M2Lv (Chap3.Range_To_Dir (Rb_Ptr)),
                             M2E (Chap3.Range_To_Dir (Eb_Ptr)));
            New_Assign_Stmt (M2Lv (Chap3.Range_To_Length (Rb_Ptr)),
                             M2E (Chap3.Range_To_Length (Eb_Ptr)));
            Close_Temp;
         end;
      end loop;
      Close_Temp;
      return M2E (Res);
   end Translate_Fat_Array_Type_Conversion;

   function Sig2val_Prepare_Composite
     (Targ : Mnode; Targ_Type : Iir; Data : Mnode) return Mnode
   is
      pragma Unreferenced (Targ, Targ_Type);
   begin
      if Get_Type_Info (Data).Type_Mode = Type_Mode_Fat_Array then
         return Stabilize (Chap3.Get_Array_Base (Data));
      else
         return Stabilize (Data);
      end if;
   end Sig2val_Prepare_Composite;

   function Sig2val_Update_Data_Array
     (Val : Mnode; Targ_Type : Iir; Index : O_Dnode) return Mnode is
   begin
      return Chap3.Index_Base (Val, Targ_Type, New_Obj_Value (Index));
   end Sig2val_Update_Data_Array;

   function Sig2val_Update_Data_Record
     (Val : Mnode; Targ_Type : Iir; El : Iir_Element_Declaration) return Mnode
   is
      pragma Unreferenced (Targ_Type);
   begin
      return Chap6.Translate_Selected_Element (Val, El);
   end Sig2val_Update_Data_Record;

   procedure Sig2val_Finish_Data_Composite (Data : in out Mnode)
   is
      pragma Unreferenced (Data);
   begin
      null;
   end Sig2val_Finish_Data_Composite;

   procedure Translate_Signal_Assign_Effective_Non_Composite
     (Targ : Mnode; Targ_Type : Iir; Data : Mnode)
   is
      pragma Unreferenced (Targ_Type);
   begin
      New_Assign_Stmt (New_Access_Element (M2E (Targ)), M2E (Data));
   end Translate_Signal_Assign_Effective_Non_Composite;

   procedure Translate_Signal_Assign_Effective is new Foreach_Non_Composite
     (Data_Type => Mnode,
      Composite_Data_Type => Mnode,
      Do_Non_Composite => Translate_Signal_Assign_Effective_Non_Composite,
      Prepare_Data_Array => Sig2val_Prepare_Composite,
      Update_Data_Array => Sig2val_Update_Data_Array,
      Finish_Data_Array => Sig2val_Finish_Data_Composite,
      Prepare_Data_Record => Sig2val_Prepare_Composite,
      Update_Data_Record => Sig2val_Update_Data_Record,
      Finish_Data_Record => Sig2val_Finish_Data_Composite);

   procedure Translate_Signal_Assign_Driving_Non_Composite
     (Targ : Mnode; Targ_Type : Iir; Data: Mnode) is
   begin
      New_Assign_Stmt
        (Chap14.Get_Signal_Value_Field (M2E (Targ), Targ_Type,
         Ghdl_Signal_Driving_Value_Field),
         M2E (Data));
   end Translate_Signal_Assign_Driving_Non_Composite;

   procedure Translate_Signal_Assign_Driving is new Foreach_Non_Composite
     (Data_Type => Mnode,
      Composite_Data_Type => Mnode,
      Do_Non_Composite => Translate_Signal_Assign_Driving_Non_Composite,
      Prepare_Data_Array => Sig2val_Prepare_Composite,
      Update_Data_Array => Sig2val_Update_Data_Array,
      Finish_Data_Array => Sig2val_Finish_Data_Composite,
      Prepare_Data_Record => Sig2val_Prepare_Composite,
      Update_Data_Record => Sig2val_Update_Data_Record,
      Finish_Data_Record => Sig2val_Finish_Data_Composite);

   function Translate_Signal_Value (Sig : O_Enode; Sig_Type : Iir)
                                   return O_Enode
   is
      procedure Translate_Signal_Non_Composite
        (Targ      : Mnode;
         Targ_Type : Iir;
         Data      : Mnode) is
      begin
         New_Assign_Stmt (M2Lv (Targ),
                          Read_Value (M2E (Data), Targ_Type));
      end Translate_Signal_Non_Composite;

      procedure Translate_Signal_Target is new Foreach_Non_Composite
        (Data_Type => Mnode,
         Composite_Data_Type => Mnode,
         Do_Non_Composite => Translate_Signal_Non_Composite,
         Prepare_Data_Array => Sig2val_Prepare_Composite,
         Update_Data_Array => Sig2val_Update_Data_Array,
         Finish_Data_Array => Sig2val_Finish_Data_Composite,
         Prepare_Data_Record => Sig2val_Prepare_Composite,
         Update_Data_Record => Sig2val_Update_Data_Record,
         Finish_Data_Record => Sig2val_Finish_Data_Composite);

      Tinfo : Type_Info_Acc;
   begin
      Tinfo := Get_Info (Sig_Type);
      if Tinfo.Type_Mode in Type_Mode_Scalar then
         return Read_Value (Sig, Sig_Type);
      else
         declare
            Res     : Mnode;
            Var_Val : Mnode;
         begin
            --  allocate result array
            if Tinfo.Type_Mode = Type_Mode_Fat_Array then
               Res := Create_Temp (Tinfo);

               Var_Val := Stabilize (E2M (Sig, Tinfo, Mode_Signal));

               --  Copy bounds.
               New_Assign_Stmt
                 (M2Lp (Chap3.Get_Array_Bounds (Res)),
                  M2Addr (Chap3.Get_Array_Bounds (Var_Val)));

               --  Allocate base.
               Chap3.Allocate_Fat_Array_Base (Alloc_Stack, Res, Sig_Type);
            elsif Is_Complex_Type (Tinfo) then
               Res := Create_Temp (Tinfo);
               Chap4.Allocate_Complex_Object (Sig_Type, Alloc_Stack, Res);
            else
               Res := Create_Temp (Tinfo);
            end if;

            Open_Temp;

            if Tinfo.Type_Mode /= Type_Mode_Fat_Array then
               Var_Val := Stabilize (E2M (Sig, Tinfo, Mode_Signal));
            end if;

            Translate_Signal_Target (Res, Sig_Type, Var_Val);
            Close_Temp;
            return M2Addr (Res);
         end;
      end if;
   end Translate_Signal_Value;

   --  Get the effective value of a simple signal SIG.
   function Read_Signal_Value (Sig : O_Enode; Sig_Type : Iir) return O_Enode
   is
      pragma Unreferenced (Sig_Type);
   begin
      return New_Value (New_Access_Element (Sig));
   end Read_Signal_Value;

   --  Get the value of signal SIG.
   function Translate_Signal is new Translate_Signal_Value
     (Read_Value => Read_Signal_Value);

   function Translate_Signal_Effective_Value
     (Sig : O_Enode; Sig_Type : Iir) return O_Enode
         renames Translate_Signal;

   function Read_Signal_Driving_Value (Sig : O_Enode; Sig_Type : Iir)
                                      return O_Enode is
   begin
      return New_Value (Chap14.Get_Signal_Value_Field
                        (Sig, Sig_Type, Ghdl_Signal_Driving_Value_Field));
   end Read_Signal_Driving_Value;

   function Translate_Signal_Driving_Value_1 is new Translate_Signal_Value
     (Read_Value => Read_Signal_Driving_Value);

   function Translate_Signal_Driving_Value
     (Sig : O_Enode; Sig_Type : Iir) return O_Enode
         renames Translate_Signal_Driving_Value_1;

   procedure Set_Effective_Value
     (Sig : Mnode; Sig_Type : Iir; Val : Mnode)
         renames Translate_Signal_Assign_Effective;
   procedure Set_Driving_Value
     (Sig : Mnode; Sig_Type : Iir; Val : Mnode)
         renames Translate_Signal_Assign_Driving;

   function Translate_Expression (Expr : Iir; Rtype : Iir := Null_Iir)
                                 return O_Enode
   is
      Imp       : Iir;
      Expr_Type : Iir;
      Res_Type  : Iir;
      Res       : O_Enode;
   begin
      Expr_Type := Get_Type (Expr);
      if Rtype = Null_Iir then
         Res_Type := Expr_Type;
      else
         Res_Type := Rtype;
      end if;
      case Get_Kind (Expr) is
         when Iir_Kind_Integer_Literal
            | Iir_Kind_Enumeration_Literal
            | Iir_Kind_Floating_Point_Literal =>
            return New_Lit (Translate_Static_Expression (Expr, Rtype));

         when Iir_Kind_Physical_Int_Literal =>
            declare
               Unit      : Iir;
               Unit_Info : Object_Info_Acc;
            begin
               Unit := Get_Unit_Name (Expr);
               Unit_Info := Get_Info (Unit);
               if Unit_Info = null then
                  return New_Lit
                    (Translate_Static_Expression (Expr, Rtype));
               else
                  --  Time units might be not locally static.
                  return New_Dyadic_Op
                    (ON_Mul_Ov,
                     New_Lit (New_Signed_Literal
                       (Get_Ortho_Type (Expr_Type, Mode_Value),
                            Integer_64 (Get_Value (Expr)))),
                     New_Value (Get_Var (Unit_Info.Object_Var)));
               end if;
            end;

         when Iir_Kind_Physical_Fp_Literal =>
            declare
               Unit      : Iir;
               Unit_Info : Object_Info_Acc;
               L, R      : O_Enode;
            begin
               Unit := Get_Unit_Name (Expr);
               Unit_Info := Get_Info (Unit);
               if Unit_Info = null then
                  return New_Lit
                    (Translate_Static_Expression (Expr, Rtype));
               else
                  --  Time units might be not locally static.
                  L := New_Lit
                    (New_Float_Literal
                       (Ghdl_Real_Type, IEEE_Float_64 (Get_Fp_Value (Expr))));
                  R := New_Convert_Ov
                    (New_Value (Get_Var (Unit_Info.Object_Var)),
                     Ghdl_Real_Type);
                  return New_Convert_Ov
                    (New_Dyadic_Op (ON_Mul_Ov, L, R),
                     Get_Ortho_Type (Expr_Type, Mode_Value));
               end if;
            end;

         when Iir_Kind_Unit_Declaration =>
            declare
               Unit_Info : Object_Info_Acc;
            begin
               Unit_Info := Get_Info (Expr);
               if Unit_Info = null then
                  return New_Lit
                    (Translate_Static_Expression (Expr, Rtype));
               else
                  --  Time units might be not locally static.
                  return New_Value (Get_Var (Unit_Info.Object_Var));
               end if;
            end;

         when Iir_Kind_String_Literal
            | Iir_Kind_Bit_String_Literal
            | Iir_Kind_Simple_Aggregate
            | Iir_Kind_Simple_Name_Attribute =>
            Res := Translate_String_Literal (Expr);

         when Iir_Kind_Aggregate =>
            declare
               Aggr_Type : Iir;
               Tinfo     : Type_Info_Acc;
               Mres      : Mnode;
            begin
               --  Extract the type of the aggregate.  Use the type of the
               --  context if it is fully constrained.
               Aggr_Type := Expr_Type;
               if Rtype /= Null_Iir
                 and then Is_Fully_Constrained_Type (Rtype)
               then
                  Aggr_Type := Rtype;
               else
                  pragma Assert (Is_Fully_Constrained_Type (Expr_Type));
                  null;
               end if;

               if Get_Kind (Aggr_Type) = Iir_Kind_Array_Subtype_Definition
               then
                  Chap3.Create_Array_Subtype (Aggr_Type, True);
               end if;

               --  FIXME: this may be not necessary
               Tinfo := Get_Info (Aggr_Type);

               --  The result area has to be created
               if Is_Complex_Type (Tinfo) then
                  Mres := Create_Temp (Tinfo);
                  Chap4.Allocate_Complex_Object
                    (Aggr_Type, Alloc_Stack, Mres);
               else
                  --  if thin array/record:
                  --    create result
                  Mres := Create_Temp (Tinfo);
               end if;

               Translate_Aggregate (Mres, Aggr_Type, Expr);
               Res := M2E (Mres);

               if Rtype /= Null_Iir and then Aggr_Type /= Rtype then
                  Res := Translate_Implicit_Conv
                    (Res, Aggr_Type, Rtype, Mode_Value, Expr);
               end if;
               return Res;
            end;

         when Iir_Kind_Null_Literal =>
            declare
               Tinfo : constant Type_Info_Acc := Get_Info (Expr_Type);
               Otype : constant O_Tnode := Tinfo.Ortho_Type (Mode_Value);
               L     : O_Dnode;
               B     : Type_Info_Acc;
            begin
               if Tinfo.Type_Mode = Type_Mode_Fat_Acc then
                  --  Create a fat null pointer.
                  --  FIXME: should be optimized!!
                  L := Create_Temp (Otype);
                  B := Get_Info (Get_Designated_Type (Expr_Type));
                  New_Assign_Stmt
                    (New_Selected_Element (New_Obj (L),
                     B.T.Base_Field (Mode_Value)),
                     New_Lit
                       (New_Null_Access (B.T.Base_Ptr_Type (Mode_Value))));
                  New_Assign_Stmt
                    (New_Selected_Element
                       (New_Obj (L), B.T.Bounds_Field (Mode_Value)),
                     New_Lit (New_Null_Access (B.T.Bounds_Ptr_Type)));
                  return New_Address (New_Obj (L),
                                      Tinfo.Ortho_Ptr_Type (Mode_Value));
               else
                  return New_Lit (New_Null_Access (Otype));
               end if;
            end;

         when Iir_Kind_Overflow_Literal =>
            declare
               Tinfo : constant Type_Info_Acc := Get_Info (Expr_Type);
               Otype : constant O_Tnode := Tinfo.Ortho_Type (Mode_Value);
               L     : O_Dnode;
            begin
               --  Generate the error message
               Chap6.Gen_Bound_Error (Expr);

               --  Create a dummy value
               L := Create_Temp (Otype);
               if Tinfo.Type_Mode = Type_Mode_Fat_Acc then
                  return New_Address (New_Obj (L),
                                      Tinfo.Ortho_Ptr_Type (Mode_Value));
               else
                  return New_Obj_Value (L);
               end if;
            end;

         when Iir_Kind_Parenthesis_Expression =>
            return Translate_Expression (Get_Expression (Expr), Rtype);

         when Iir_Kind_Allocator_By_Expression =>
            return Translate_Allocator_By_Expression (Expr);
         when Iir_Kind_Allocator_By_Subtype =>
            return Translate_Allocator_By_Subtype (Expr);

         when Iir_Kind_Qualified_Expression =>
            --  FIXME: check type.
            Res := Translate_Expression (Get_Expression (Expr), Expr_Type);

         when Iir_Kind_Constant_Declaration
            | Iir_Kind_Variable_Declaration
            | Iir_Kind_Signal_Declaration
            | Iir_Kind_File_Declaration
            | Iir_Kind_Object_Alias_Declaration
            | Iir_Kind_Interface_Constant_Declaration
            | Iir_Kind_Interface_Variable_Declaration
            | Iir_Kind_Interface_Signal_Declaration
            | Iir_Kind_Interface_File_Declaration
            | Iir_Kind_Indexed_Name
            | Iir_Kind_Slice_Name
            | Iir_Kind_Selected_Element
            | Iir_Kind_Dereference
            | Iir_Kind_Implicit_Dereference
            | Iir_Kind_Stable_Attribute
            | Iir_Kind_Quiet_Attribute
            | Iir_Kind_Delayed_Attribute
            | Iir_Kind_Transaction_Attribute
            | Iir_Kind_Guard_Signal_Declaration
            | Iir_Kind_Attribute_Value
            | Iir_Kind_Attribute_Name =>
            declare
               L : Mnode;
            begin
               L := Chap6.Translate_Name (Expr);

               Res := M2E (L);
               if Get_Object_Kind (L) = Mode_Signal then
                  Res := Translate_Signal (Res, Expr_Type);
               end if;
            end;

         when Iir_Kind_Iterator_Declaration =>
            declare
               Expr_Info : Ortho_Info_Acc;
            begin
               Expr_Info := Get_Info (Expr);
               Res := New_Value (Get_Var (Expr_Info.Iterator_Var));
               if Rtype /= Null_Iir then
                  Res := New_Convert_Ov
                    (Res, Get_Ortho_Type (Rtype, Mode_Value));
               end if;
               return Res;
            end;

         when Iir_Kinds_Dyadic_Operator =>
            Imp := Get_Implementation (Expr);
            if Get_Kind (Imp) = Iir_Kind_Implicit_Function_Declaration then
               return Translate_Predefined_Operator
                 (Imp, Get_Left (Expr), Get_Right (Expr), Res_Type, Expr);
            else
               return Translate_Operator_Function_Call
                 (Imp, Get_Left (Expr), Get_Right (Expr), Res_Type);
            end if;
         when Iir_Kinds_Monadic_Operator =>
            Imp := Get_Implementation (Expr);
            if Get_Kind (Imp) = Iir_Kind_Implicit_Function_Declaration then
               return Translate_Predefined_Operator
                 (Imp, Get_Operand (Expr), Null_Iir, Res_Type, Expr);
            else
               return Translate_Operator_Function_Call
                 (Imp, Get_Operand (Expr), Null_Iir, Res_Type);
            end if;
         when Iir_Kind_Function_Call =>
            Imp := Get_Implementation (Expr);
            declare
               Assoc_Chain : Iir;
            begin
               if Get_Kind (Imp) = Iir_Kind_Implicit_Function_Declaration
               then
                  declare
                     Left, Right : Iir;
                  begin
                     Assoc_Chain := Get_Parameter_Association_Chain (Expr);
                     if Assoc_Chain = Null_Iir then
                        Left := Null_Iir;
                        Right := Null_Iir;
                     else
                        Left := Get_Actual (Assoc_Chain);
                        Assoc_Chain := Get_Chain (Assoc_Chain);
                        if Assoc_Chain = Null_Iir then
                           Right := Null_Iir;
                        else
                           Right := Get_Actual (Assoc_Chain);
                        end if;
                     end if;
                     return Translate_Predefined_Operator
                       (Imp, Left, Right, Res_Type, Expr);
                  end;
               else
                  Canon.Canon_Subprogram_Call (Expr);
                  Assoc_Chain := Get_Parameter_Association_Chain (Expr);
                  Res := Translate_Function_Call
                    (Imp, Assoc_Chain, Get_Method_Object (Expr));
                  Expr_Type := Get_Return_Type (Imp);
               end if;
            end;

         when Iir_Kind_Type_Conversion =>
            declare
               Conv_Expr : Iir;
            begin
               Conv_Expr := Get_Expression (Expr);
               Res := Translate_Type_Conversion
                 (Translate_Expression (Conv_Expr), Get_Type (Conv_Expr),
                  Expr_Type, Expr);
            end;

         when Iir_Kind_Length_Array_Attribute =>
            return Chap14.Translate_Length_Array_Attribute
              (Expr, Res_Type);
         when Iir_Kind_Low_Array_Attribute =>
            return Chap14.Translate_Low_Array_Attribute (Expr);
         when Iir_Kind_High_Array_Attribute =>
            return Chap14.Translate_High_Array_Attribute (Expr);
         when Iir_Kind_Left_Array_Attribute =>
            return Chap14.Translate_Left_Array_Attribute (Expr);
         when Iir_Kind_Right_Array_Attribute =>
            return Chap14.Translate_Right_Array_Attribute (Expr);
         when Iir_Kind_Ascending_Array_Attribute =>
            return Chap14.Translate_Ascending_Array_Attribute (Expr);

         when Iir_Kind_Val_Attribute =>
            return Chap14.Translate_Val_Attribute (Expr);
         when Iir_Kind_Pos_Attribute =>
            return Chap14.Translate_Pos_Attribute (Expr, Res_Type);

         when Iir_Kind_Succ_Attribute
            | Iir_Kind_Pred_Attribute =>
            return Chap14.Translate_Succ_Pred_Attribute (Expr);

         when Iir_Kind_Image_Attribute =>
            Res := Chap14.Translate_Image_Attribute (Expr);

         when Iir_Kind_Value_Attribute =>
            return Chap14.Translate_Value_Attribute (Expr);

         when Iir_Kind_Event_Attribute =>
            return Chap14.Translate_Event_Attribute (Expr);
         when Iir_Kind_Active_Attribute =>
            return Chap14.Translate_Active_Attribute (Expr);
         when Iir_Kind_Last_Value_Attribute =>
            Res := Chap14.Translate_Last_Value_Attribute (Expr);

         when Iir_Kind_High_Type_Attribute =>
            return Chap14.Translate_High_Low_Type_Attribute
              (Get_Type (Expr), True);
         when Iir_Kind_Low_Type_Attribute =>
            return Chap14.Translate_High_Low_Type_Attribute
              (Get_Type (Expr), False);
         when Iir_Kind_Left_Type_Attribute =>
            return M2E
              (Chap3.Range_To_Left
                 (Lv2M (Translate_Range (Get_Prefix (Expr), Expr_Type),
                  Get_Info (Get_Base_Type (Expr_Type)), Mode_Value)));
         when Iir_Kind_Right_Type_Attribute =>
            return M2E
              (Chap3.Range_To_Right
                 (Lv2M (Translate_Range (Get_Prefix (Expr), Expr_Type),
                  Get_Info (Get_Base_Type (Expr_Type)), Mode_Value)));

         when Iir_Kind_Last_Event_Attribute =>
            return Chap14.Translate_Last_Time_Attribute
              (Get_Prefix (Expr), Ghdl_Signal_Last_Event_Field);
         when Iir_Kind_Last_Active_Attribute =>
            return Chap14.Translate_Last_Time_Attribute
              (Get_Prefix (Expr), Ghdl_Signal_Last_Active_Field);

         when Iir_Kind_Driving_Value_Attribute =>
            Res := Chap14.Translate_Driving_Value_Attribute (Expr);
         when Iir_Kind_Driving_Attribute =>
            Res := Chap14.Translate_Driving_Attribute (Expr);

         when Iir_Kind_Path_Name_Attribute
            | Iir_Kind_Instance_Name_Attribute =>
            Res := Chap14.Translate_Path_Instance_Name_Attribute (Expr);

         when Iir_Kind_Simple_Name
            | Iir_Kind_Character_Literal
            | Iir_Kind_Selected_Name =>
            return Translate_Expression (Get_Named_Entity (Expr), Rtype);

         when others =>
            Error_Kind ("translate_expression", Expr);
      end case;

      --  Quick test to avoid useless calls.
      if Expr_Type /= Res_Type then
         Res := Translate_Implicit_Conv
           (Res, Expr_Type, Res_Type, Mode_Value, Expr);
      end if;

      return Res;
   end Translate_Expression;

   --  Check if RNG is of the form:
   --     1 to T'length
   --  or T'Length downto 1
   --  or 0 to T'length - 1
   --  or T'Length - 1 downto 0
   --  In either of these cases, return T'Length
   function Is_Length_Range_Expression (Rng : Iir_Range_Expression) return Iir
   is
      --  Pattern of a bound.
      type Length_Pattern is
        (
         Pat_Unknown,
         Pat_Length,
         Pat_Length_1,  --  Length - 1
         Pat_1,
         Pat_0
        );
      Length_Attr : Iir := Null_Iir;

      --  Classify the bound.
      --  Set LENGTH_ATTR is the pattern is Pat_Length.
      function Get_Length_Pattern (Expr : Iir; Recurse : Boolean)
                                      return Length_Pattern
      is
      begin
         case Get_Kind (Expr) is
            when Iir_Kind_Length_Array_Attribute =>
               Length_Attr := Expr;
               return Pat_Length;
            when Iir_Kind_Integer_Literal =>
               case Get_Value (Expr) is
                  when 0 =>
                     return Pat_0;
                  when 1 =>
                     return Pat_1;
                  when others =>
                     return Pat_Unknown;
               end case;
            when Iir_Kind_Substraction_Operator =>
               if not Recurse then
                  return Pat_Unknown;
               end if;
               if Get_Length_Pattern (Get_Left (Expr), False) = Pat_Length
                 and then
                   Get_Length_Pattern (Get_Right (Expr), False) = Pat_1
               then
                  return Pat_Length_1;
               else
                  return Pat_Unknown;
               end if;
            when others =>
               return Pat_Unknown;
         end case;
      end Get_Length_Pattern;
      Left_Pat, Right_Pat : Length_Pattern;
   begin
      Left_Pat := Get_Length_Pattern (Get_Left_Limit (Rng), True);
      if Left_Pat = Pat_Unknown then
         return Null_Iir;
      end if;
      Right_Pat := Get_Length_Pattern (Get_Right_Limit (Rng), True);
      if Right_Pat = Pat_Unknown then
         return Null_Iir;
      end if;
      case Get_Direction (Rng) is
         when Iir_To =>
            if (Left_Pat = Pat_1 and Right_Pat = Pat_Length)
              or else (Left_Pat = Pat_0 and Right_Pat = Pat_Length_1)
            then
               return Length_Attr;
            end if;
         when Iir_Downto =>
            if (Left_Pat = Pat_Length and Right_Pat = Pat_1)
              or else (Left_Pat = Pat_Length_1 and Right_Pat = Pat_0)
            then
               return Length_Attr;
            end if;
      end case;
      return Null_Iir;
   end Is_Length_Range_Expression;

   procedure Translate_Range_Expression_Ptr
     (Res_Ptr : O_Dnode; Expr : Iir; Range_Type : Iir)
   is
      T_Info      : constant Type_Info_Acc := Get_Info (Range_Type);
      Length_Attr : Iir;
   begin
      Open_Temp;
      New_Assign_Stmt
        (New_Selected_Acc_Value (New_Obj (Res_Ptr), T_Info.T.Range_Left),
         Chap7.Translate_Range_Expression_Left (Expr, Range_Type));
      New_Assign_Stmt
        (New_Selected_Acc_Value (New_Obj (Res_Ptr), T_Info.T.Range_Right),
         Chap7.Translate_Range_Expression_Right (Expr, Range_Type));
      New_Assign_Stmt
        (New_Selected_Acc_Value (New_Obj (Res_Ptr), T_Info.T.Range_Dir),
         New_Lit (Chap7.Translate_Static_Range_Dir (Expr)));
      if T_Info.T.Range_Length /= O_Fnode_Null then
         if Get_Expr_Staticness (Expr) = Locally then
            New_Assign_Stmt
              (New_Selected_Acc_Value (New_Obj (Res_Ptr),
               T_Info.T.Range_Length),
               New_Lit (Translate_Static_Range_Length (Expr)));
         else
            Length_Attr := Is_Length_Range_Expression (Expr);
            if Length_Attr = Null_Iir then
               Open_Temp;
               New_Assign_Stmt
                 (New_Selected_Acc_Value (New_Obj (Res_Ptr),
                  T_Info.T.Range_Length),
                  Compute_Range_Length
                    (New_Value_Selected_Acc_Value (New_Obj (Res_Ptr),
                     T_Info.T.Range_Left),
                     New_Value_Selected_Acc_Value (New_Obj (Res_Ptr),
                       T_Info.T.Range_Right),
                     Get_Direction (Expr)));
               Close_Temp;
            else
               New_Assign_Stmt
                 (New_Selected_Acc_Value (New_Obj (Res_Ptr),
                  T_Info.T.Range_Length),
                  Chap14.Translate_Length_Array_Attribute
                    (Length_Attr, Null_Iir));
            end if;
         end if;
      end if;
      Close_Temp;
   end Translate_Range_Expression_Ptr;

   --  Reverse range ARANGE.
   procedure Translate_Reverse_Range
     (Res : Mnode; Arange : O_Lnode; Range_Type : Iir)
   is
      Rinfo  : constant Type_Info_Acc := Get_Info (Get_Base_Type (Range_Type));
      Res1   : Mnode;
      Arange1 : Mnode;
      If_Blk : O_If_Block;
   begin
      Open_Temp;
      Arange1 := Stabilize (Lv2M (Arange, Rinfo, Mode_Value,
                                  Rinfo.T.Range_Type,
                                  Rinfo.T.Range_Ptr_Type));
      Res1 := Stabilize (Res);
      New_Assign_Stmt (M2Lv (Chap3.Range_To_Left (Res1)),
                       M2E (Chap3.Range_To_Right (Arange1)));
      New_Assign_Stmt (M2Lv (Chap3.Range_To_Right (Res1)),
                       M2E (Chap3.Range_To_Left (Arange1)));
      New_Assign_Stmt (M2Lv (Chap3.Range_To_Length (Res1)),
                       M2E (Chap3.Range_To_Length (Arange1)));
      Start_If_Stmt
        (If_Blk, New_Compare_Op (ON_Eq,
                                 M2E (Chap3.Range_To_Dir (Arange1)),
                                 New_Lit (Ghdl_Dir_To_Node),
                                 Ghdl_Bool_Type));
      New_Assign_Stmt (M2Lv (Chap3.Range_To_Dir (Res1)),
                       New_Lit (Ghdl_Dir_Downto_Node));
      New_Else_Stmt (If_Blk);
      New_Assign_Stmt (M2Lv (Chap3.Range_To_Dir (Res1)),
                       New_Lit (Ghdl_Dir_To_Node));
      Finish_If_Stmt (If_Blk);
      Close_Temp;
   end Translate_Reverse_Range;

   procedure Copy_Range (Dest_Ptr : O_Dnode;
                         Src_Ptr  : O_Dnode;
                         Info     : Type_Info_Acc) is
   begin
      New_Assign_Stmt
        (New_Selected_Acc_Value (New_Obj (Dest_Ptr), Info.T.Range_Left),
         New_Value_Selected_Acc_Value (New_Obj (Src_Ptr),
           Info.T.Range_Left));
      New_Assign_Stmt
        (New_Selected_Acc_Value (New_Obj (Dest_Ptr), Info.T.Range_Right),
         New_Value_Selected_Acc_Value (New_Obj (Src_Ptr),
           Info.T.Range_Right));
      New_Assign_Stmt
        (New_Selected_Acc_Value (New_Obj (Dest_Ptr), Info.T.Range_Dir),
         New_Value_Selected_Acc_Value (New_Obj (Src_Ptr),
           Info.T.Range_Dir));
      if Info.T.Range_Length /= O_Fnode_Null then
         New_Assign_Stmt
           (New_Selected_Acc_Value (New_Obj (Dest_Ptr),
            Info.T.Range_Length),
            New_Value_Selected_Acc_Value (New_Obj (Src_Ptr),
              Info.T.Range_Length));
      end if;
   end Copy_Range;

   procedure Translate_Range_Ptr
     (Res_Ptr : O_Dnode; Arange : Iir; Range_Type : Iir) is
   begin
      case Get_Kind (Arange) is
         when Iir_Kind_Range_Array_Attribute =>
            declare
               Ptr   : O_Dnode;
               Rinfo : constant Type_Info_Acc :=
                 Get_Info (Get_Base_Type (Range_Type));
            begin
               Open_Temp;
               Ptr := Create_Temp_Ptr
                 (Rinfo.T.Range_Ptr_Type,
                  Chap14.Translate_Range_Array_Attribute (Arange));
               Copy_Range (Res_Ptr, Ptr, Rinfo);
               Close_Temp;
            end;
         when Iir_Kind_Reverse_Range_Array_Attribute =>
            declare
               Rinfo : constant Type_Info_Acc :=
                 Get_Info (Get_Base_Type (Range_Type));
            begin
               Translate_Reverse_Range
                 (Dp2M (Res_Ptr, Rinfo, Mode_Value,
                        Rinfo.T.Range_Type, Rinfo.T.Range_Ptr_Type),
                  Chap14.Translate_Range_Array_Attribute (Arange),
                  Range_Type);
            end;
         when Iir_Kind_Range_Expression =>
            Translate_Range_Expression_Ptr (Res_Ptr, Arange, Range_Type);
         when others =>
            Error_Kind ("translate_range_ptr", Arange);
      end case;
   end Translate_Range_Ptr;

   procedure Translate_Discrete_Range_Ptr (Res_Ptr : O_Dnode; Arange : Iir) is
   begin
      case Get_Kind (Arange) is
         when Iir_Kind_Integer_Subtype_Definition
            | Iir_Kind_Enumeration_Subtype_Definition =>
            if not Is_Anonymous_Type_Definition (Arange) then
               declare
                  Rinfo : constant Type_Info_Acc := Get_Info (Arange);
                  Ptr   : O_Dnode;
               begin
                  Open_Temp;
                  Ptr := Create_Temp_Ptr
                    (Rinfo.T.Range_Ptr_Type, Get_Var (Rinfo.T.Range_Var));
                  Copy_Range (Res_Ptr, Ptr, Rinfo);
                  Close_Temp;
               end;
            else
               Translate_Range_Ptr (Res_Ptr,
                                    Get_Range_Constraint (Arange),
                                    Get_Base_Type (Arange));
            end if;
         when Iir_Kind_Range_Array_Attribute
            | Iir_Kind_Reverse_Range_Array_Attribute
            | Iir_Kind_Range_Expression =>
            Translate_Range_Ptr (Res_Ptr, Arange, Get_Type (Arange));
         when others =>
            Error_Kind ("translate_discrete_range_ptr", Arange);
      end case;
   end Translate_Discrete_Range_Ptr;

   function Translate_Range (Arange : Iir; Range_Type : Iir) return O_Lnode is
   begin
      case Get_Kind (Arange) is
         when Iir_Kinds_Denoting_Name =>
            return Translate_Range (Get_Named_Entity (Arange), Range_Type);
         when Iir_Kind_Subtype_Declaration =>
            --  Must be a scalar subtype.  Range of types is static.
            return Get_Var (Get_Info (Get_Type (Arange)).T.Range_Var);
         when Iir_Kind_Range_Array_Attribute =>
            return Chap14.Translate_Range_Array_Attribute (Arange);
         when Iir_Kind_Reverse_Range_Array_Attribute =>
            declare
               Rinfo   : constant Type_Info_Acc := Get_Info (Range_Type);
               Res     : O_Dnode;
            begin
               Res := Create_Temp (Rinfo.T.Range_Type);
               Translate_Reverse_Range
                 (Dv2M (Res, Rinfo, Mode_Value),
                  Chap14.Translate_Range_Array_Attribute (Arange),
                  Range_Type);
               return New_Obj (Res);
            end;
         when Iir_Kind_Range_Expression =>
            declare
               Res    : O_Dnode;
               Ptr    : O_Dnode;
               T_Info : constant Type_Info_Acc := Get_Info (Range_Type);
            begin
               Res := Create_Temp (T_Info.T.Range_Type);
               Open_Temp;
               Ptr := Create_Temp_Ptr (T_Info.T.Range_Ptr_Type, New_Obj (Res));
               Translate_Range_Expression_Ptr (Ptr, Arange, Range_Type);
               Close_Temp;
               return New_Obj (Res);
            end;
         when others =>
            Error_Kind ("translate_range", Arange);
      end case;
      return O_Lnode_Null;
   end Translate_Range;

   function Translate_Static_Range (Arange : Iir; Range_Type : Iir)
                                   return O_Cnode
   is
      Constr : O_Record_Aggr_List;
      Res    : O_Cnode;
      T_Info : Type_Info_Acc;
   begin
      T_Info := Get_Info (Range_Type);
      Start_Record_Aggr (Constr, T_Info.T.Range_Type);
      New_Record_Aggr_El
        (Constr, Chap7.Translate_Static_Range_Left (Arange, Range_Type));
      New_Record_Aggr_El
        (Constr, Chap7.Translate_Static_Range_Right (Arange, Range_Type));
      New_Record_Aggr_El
        (Constr, Chap7.Translate_Static_Range_Dir (Arange));
      if T_Info.T.Range_Length /= O_Fnode_Null then
         New_Record_Aggr_El
           (Constr, Chap7.Translate_Static_Range_Length (Arange));
      end if;
      Finish_Record_Aggr (Constr, Res);
      return Res;
   end Translate_Static_Range;

   procedure Translate_Predefined_Array_Compare (Subprg : Iir)
   is
      procedure Gen_Compare (L, R : O_Dnode)
      is
         If_Blk1, If_Blk2 : O_If_Block;
      begin
         Start_If_Stmt
           (If_Blk1,
            New_Compare_Op (ON_Neq, New_Obj_Value (L), New_Obj_Value (R),
              Ghdl_Bool_Type));
         Start_If_Stmt
           (If_Blk2,
            New_Compare_Op (ON_Gt, New_Obj_Value (L), New_Obj_Value (R),
              Ghdl_Bool_Type));
         New_Return_Stmt (New_Lit (Ghdl_Compare_Gt));
         New_Else_Stmt (If_Blk2);
         New_Return_Stmt (New_Lit (Ghdl_Compare_Lt));
         Finish_If_Stmt (If_Blk2);
         Finish_If_Stmt (If_Blk1);
      end Gen_Compare;

      Arr_Type     : constant Iir_Array_Type_Definition :=
        Get_Type (Get_Interface_Declaration_Chain (Subprg));
      Info         : constant Type_Info_Acc := Get_Info (Arr_Type);
      Id           : constant Name_Id :=
        Get_Identifier (Get_Type_Declarator (Arr_Type));
      Arr_Ptr_Type : constant O_Tnode := Info.Ortho_Ptr_Type (Mode_Value);

      F_Info               : Subprg_Info_Acc;
      L, R                 : O_Dnode;
      Interface_List       : O_Inter_List;
      If_Blk               : O_If_Block;
      Var_L_Len, Var_R_Len : O_Dnode;
      Var_L_El, Var_R_El   : O_Dnode;
      Var_I, Var_Len       : O_Dnode;
      Label                : O_Snode;
      El_Otype             : O_Tnode;
   begin
      F_Info := Add_Info (Subprg, Kind_Subprg);
      --Chap2.Clear_Instance_Data (F_Info.Subprg_Instance);

      --  Create function.
      Start_Function_Decl (Interface_List, Create_Identifier (Id, "_CMP"),
                           Global_Storage, Ghdl_Compare_Type);
      New_Interface_Decl (Interface_List, L, Wki_Left, Arr_Ptr_Type);
      New_Interface_Decl (Interface_List, R, Wki_Right, Arr_Ptr_Type);
      Finish_Subprogram_Decl (Interface_List, F_Info.Ortho_Func);

      if Global_Storage = O_Storage_External then
         return;
      end if;

      El_Otype := Get_Ortho_Type
        (Get_Element_Subtype (Arr_Type), Mode_Value);
      Start_Subprogram_Body (F_Info.Ortho_Func);
      --  Compute length of L and R.
      New_Var_Decl (Var_L_Len, Wki_L_Len,
                    O_Storage_Local, Ghdl_Index_Type);
      New_Var_Decl (Var_R_Len, Wki_R_Len,
                    O_Storage_Local, Ghdl_Index_Type);
      New_Var_Decl (Var_Len, Wki_Length, O_Storage_Local, Ghdl_Index_Type);
      New_Var_Decl (Var_I, Wki_I, O_Storage_Local, Ghdl_Index_Type);
      New_Assign_Stmt (New_Obj (Var_L_Len),
                       Chap6.Get_Array_Bound_Length
                         (Dp2M (L, Info, Mode_Value), Arr_Type, 1));
      New_Assign_Stmt (New_Obj (Var_R_Len),
                       Chap6.Get_Array_Bound_Length
                         (Dp2M (R, Info, Mode_Value), Arr_Type, 1));
      --  Find the minimum length.
      Start_If_Stmt (If_Blk,
                     New_Compare_Op (ON_Ge,
                       New_Obj_Value (Var_L_Len),
                       New_Obj_Value (Var_R_Len),
                       Ghdl_Bool_Type));
      New_Assign_Stmt (New_Obj (Var_Len), New_Obj_Value (Var_R_Len));
      New_Else_Stmt (If_Blk);
      New_Assign_Stmt (New_Obj (Var_Len), New_Obj_Value (Var_L_Len));
      Finish_If_Stmt (If_Blk);

      --  for each element, compare elements; if not equal return the
      --       comparaison result.
      Init_Var (Var_I);
      Start_Loop_Stmt (Label);
      Start_If_Stmt (If_Blk, New_Compare_Op (ON_Ge,
                     New_Obj_Value (Var_I),
                     New_Obj_Value (Var_Len),
                     Ghdl_Bool_Type));
      --  Compare the length and return the result.
      Gen_Compare (Var_L_Len, Var_R_Len);
      New_Return_Stmt (New_Lit (Ghdl_Compare_Eq));
      Finish_If_Stmt (If_Blk);
      Start_Declare_Stmt;
      New_Var_Decl (Var_L_El, Get_Identifier ("l_el"), O_Storage_Local,
                    El_Otype);
      New_Var_Decl (Var_R_El, Get_Identifier ("r_el"), O_Storage_Local,
                    El_Otype);
      New_Assign_Stmt
        (New_Obj (Var_L_El),
         M2E (Chap3.Index_Base
           (Chap3.Get_Array_Base (Dp2M (L, Info, Mode_Value)),
                Arr_Type,
                New_Obj_Value (Var_I))));
      New_Assign_Stmt
        (New_Obj (Var_R_El),
         M2E (Chap3.Index_Base
           (Chap3.Get_Array_Base (Dp2M (R, Info, Mode_Value)),
                Arr_Type,
                New_Obj_Value (Var_I))));
      Gen_Compare (Var_L_El, Var_R_El);
      Finish_Declare_Stmt;
      Inc_Var (Var_I);
      Finish_Loop_Stmt (Label);
      Finish_Subprogram_Body;
   end Translate_Predefined_Array_Compare;

   --  Find the declaration of the predefined function IMP in type
   --  definition BASE_TYPE.
   function Find_Predefined_Function
     (Base_Type : Iir; Imp : Iir_Predefined_Functions) return Iir
   is
      El : Iir;
   begin
      El := Get_Chain (Get_Type_Declarator (Base_Type));
      while El /= Null_Iir loop
         case Get_Kind (El) is
            when Iir_Kind_Implicit_Function_Declaration
               | Iir_Kind_Implicit_Procedure_Declaration =>
               if Get_Implicit_Definition (El) = Imp then
                  return El;
               else
                  El := Get_Chain (El);
               end if;
            when others =>
               raise Internal_Error;
         end case;
      end loop;
      raise Internal_Error;
   end Find_Predefined_Function;

   function Translate_Equality (L, R : Mnode; Etype : Iir) return O_Enode
   is
      Tinfo : Type_Info_Acc;
   begin
      Tinfo := Get_Type_Info (L);
      case Tinfo.Type_Mode is
         when Type_Mode_Scalar
            | Type_Mode_Acc =>
            return New_Compare_Op (ON_Eq, M2E (L), M2E (R),
                                   Ghdl_Bool_Type);
         when Type_Mode_Fat_Acc =>
            --  a fat pointer.
            declare
               B      : Type_Info_Acc;
               Ln, Rn : Mnode;
               V1, V2 : O_Enode;
            begin
               B := Get_Info (Get_Designated_Type (Etype));
               Ln := Stabilize (L);
               Rn := Stabilize (R);
               V1 := New_Compare_Op
                 (ON_Eq,
                  New_Value (New_Selected_Element
                    (M2Lv (Ln), B.T.Base_Field (Mode_Value))),
                  New_Value (New_Selected_Element
                    (M2Lv (Rn), B.T.Base_Field (Mode_Value))),
                  Std_Boolean_Type_Node);
               V2 := New_Compare_Op
                 (ON_Eq,
                  New_Value (New_Selected_Element
                    (M2Lv (Ln), B.T.Bounds_Field (Mode_Value))),
                  New_Value (New_Selected_Element
                    (M2Lv (Rn), B.T.Bounds_Field (Mode_Value))),
                  Std_Boolean_Type_Node);
               return New_Dyadic_Op (ON_And, V1, V2);
            end;

         when Type_Mode_Array =>
            declare
               Lc, Rc    : O_Enode;
               Base_Type : Iir_Array_Type_Definition;
               Func      : Iir;
            begin
               Base_Type := Get_Base_Type (Etype);
               Lc := Translate_Implicit_Conv
                 (M2E (L), Etype, Base_Type, Mode_Value, Null_Iir);
               Rc := Translate_Implicit_Conv
                 (M2E (R), Etype, Base_Type, Mode_Value, Null_Iir);
               Func := Find_Predefined_Function
                 (Base_Type, Iir_Predefined_Array_Equality);
               return Translate_Predefined_Lib_Operator (Lc, Rc, Func);
            end;

         when Type_Mode_Record =>
            declare
               Func : Iir;
            begin
               Func := Find_Predefined_Function
                 (Get_Base_Type (Etype), Iir_Predefined_Record_Equality);
               return Translate_Predefined_Lib_Operator
                 (M2E (L), M2E (R), Func);
            end;

         when Type_Mode_Unknown
            | Type_Mode_File
            | Type_Mode_Fat_Array
            | Type_Mode_Protected =>
            raise Internal_Error;
      end case;
   end Translate_Equality;

   procedure Translate_Predefined_Array_Equality (Subprg : Iir)
   is
      F_Info         : Subprg_Info_Acc;
      Arr_Type       : Iir_Array_Type_Definition;
      Arr_Ptr_Type   : O_Tnode;
      Info           : Type_Info_Acc;
      Id             : Name_Id;
      Var_L, Var_R   : O_Dnode;
      L, R           : Mnode;
      Interface_List : O_Inter_List;
      Indexes        : Iir_List;
      Nbr_Indexes    : Natural;
      If_Blk         : O_If_Block;
      Var_I          : O_Dnode;
      Var_Len        : O_Dnode;
      Label          : O_Snode;
      Le, Re         : Mnode;
      El_Type        : Iir;
   begin
      Arr_Type := Get_Type (Get_Interface_Declaration_Chain (Subprg));
      El_Type := Get_Element_Subtype (Arr_Type);
      Info := Get_Info (Arr_Type);
      Id := Get_Identifier (Get_Type_Declarator (Arr_Type));
      Arr_Ptr_Type := Info.Ortho_Ptr_Type (Mode_Value);

      F_Info := Add_Info (Subprg, Kind_Subprg);

      --  Create function.
      Start_Function_Decl (Interface_List, Create_Identifier (Id, "_EQ"),
                           Global_Storage, Std_Boolean_Type_Node);
      Subprgs.Create_Subprg_Instance (Interface_List, Subprg);
      New_Interface_Decl (Interface_List, Var_L, Wki_Left, Arr_Ptr_Type);
      New_Interface_Decl (Interface_List, Var_R, Wki_Right, Arr_Ptr_Type);
      Finish_Subprogram_Decl (Interface_List, F_Info.Ortho_Func);

      if Global_Storage = O_Storage_External then
         return;
      end if;

      L := Dp2M (Var_L, Info, Mode_Value);
      R := Dp2M (Var_R, Info, Mode_Value);

      Indexes := Get_Index_Subtype_List (Arr_Type);
      Nbr_Indexes := Get_Nbr_Elements (Indexes);

      Start_Subprogram_Body (F_Info.Ortho_Func);
      Subprgs.Start_Subprg_Instance_Use (Subprg);
      --  for each dimension:  if length mismatch: return false
      for I in 1 .. Nbr_Indexes loop
         Start_If_Stmt
           (If_Blk,
            New_Compare_Op
              (ON_Neq,
               M2E (Chap3.Range_To_Length
                 (Chap3.Get_Array_Range (L, Arr_Type, I))),
               M2E (Chap3.Range_To_Length
                 (Chap3.Get_Array_Range (R, Arr_Type, I))),
               Std_Boolean_Type_Node));
         New_Return_Stmt (New_Lit (Std_Boolean_False_Node));
         Finish_If_Stmt (If_Blk);
      end loop;

      --  for each element: if element is not equal, return false
      New_Var_Decl (Var_I, Wki_I, O_Storage_Local, Ghdl_Index_Type);
      New_Var_Decl (Var_Len, Wki_Length, O_Storage_Local, Ghdl_Index_Type);
      Open_Temp;
      New_Assign_Stmt (New_Obj (Var_Len),
                       Chap3.Get_Array_Length (L, Arr_Type));
      Close_Temp;
      Init_Var (Var_I);
      Start_Loop_Stmt (Label);
      --  If the end of the array is reached, return TRUE.
      Start_If_Stmt (If_Blk,
                     New_Compare_Op (ON_Ge,
                       New_Obj_Value (Var_I),
                       New_Obj_Value (Var_Len),
                       Ghdl_Bool_Type));
      New_Return_Stmt (New_Lit (Std_Boolean_True_Node));
      Finish_If_Stmt (If_Blk);
      Open_Temp;
      Le := Chap3.Index_Base (Chap3.Get_Array_Base (L), Arr_Type,
                              New_Obj_Value (Var_I));
      Re := Chap3.Index_Base (Chap3.Get_Array_Base (R), Arr_Type,
                              New_Obj_Value (Var_I));
      Start_If_Stmt
        (If_Blk,
         New_Monadic_Op (ON_Not, Translate_Equality (Le, Re, El_Type)));
      New_Return_Stmt (New_Lit (Std_Boolean_False_Node));
      Finish_If_Stmt (If_Blk);
      Close_Temp;
      Inc_Var (Var_I);
      Finish_Loop_Stmt (Label);
      Subprgs.Finish_Subprg_Instance_Use (Subprg);
      Finish_Subprogram_Body;
   end Translate_Predefined_Array_Equality;

   procedure Translate_Predefined_Record_Equality (Subprg : Iir)
   is
      F_Info         : Subprg_Info_Acc;
      Rec_Type       : Iir_Record_Type_Definition;
      Rec_Ptr_Type   : O_Tnode;
      Info           : Type_Info_Acc;
      Id             : Name_Id;
      Var_L, Var_R   : O_Dnode;
      L, R           : Mnode;
      Interface_List : O_Inter_List;
      If_Blk         : O_If_Block;
      Le, Re         : Mnode;

      El_List : Iir_List;
      El      : Iir_Element_Declaration;
   begin
      Rec_Type := Get_Type (Get_Interface_Declaration_Chain (Subprg));
      Info := Get_Info (Rec_Type);
      Id := Get_Identifier (Get_Type_Declarator (Rec_Type));
      Rec_Ptr_Type := Info.Ortho_Ptr_Type (Mode_Value);

      F_Info := Add_Info (Subprg, Kind_Subprg);
      --Chap2.Clear_Instance_Data (F_Info.Subprg_Instance);

      --  Create function.
      Start_Function_Decl (Interface_List, Create_Identifier (Id, "_EQ"),
                           Global_Storage, Std_Boolean_Type_Node);
      Subprgs.Create_Subprg_Instance (Interface_List, Subprg);
      New_Interface_Decl (Interface_List, Var_L, Wki_Left, Rec_Ptr_Type);
      New_Interface_Decl (Interface_List, Var_R, Wki_Right, Rec_Ptr_Type);
      Finish_Subprogram_Decl (Interface_List, F_Info.Ortho_Func);

      if Global_Storage = O_Storage_External then
         return;
      end if;

      Start_Subprogram_Body (F_Info.Ortho_Func);
      Subprgs.Start_Subprg_Instance_Use (Subprg);

      L := Dp2M (Var_L, Info, Mode_Value);
      R := Dp2M (Var_R, Info, Mode_Value);

      --   Compare each element.
      El_List := Get_Elements_Declaration_List (Rec_Type);
      for I in Natural loop
         El := Get_Nth_Element (El_List, I);
         exit when El = Null_Iir;
         Le := Chap6.Translate_Selected_Element (L, El);
         Re := Chap6.Translate_Selected_Element (R, El);

         Open_Temp;
         Start_If_Stmt
           (If_Blk,
            New_Monadic_Op (ON_Not,
              Translate_Equality (Le, Re, Get_Type (El))));
         New_Return_Stmt (New_Lit (Std_Boolean_False_Node));
         Finish_If_Stmt (If_Blk);
         Close_Temp;
      end loop;
      New_Return_Stmt (New_Lit (Std_Boolean_True_Node));
      Subprgs.Finish_Subprg_Instance_Use (Subprg);
      Finish_Subprogram_Body;
   end Translate_Predefined_Record_Equality;

   procedure Translate_Predefined_Array_Array_Concat (Subprg : Iir)
   is
      F_Info       : Subprg_Info_Acc;
      Arr_Type     : constant Iir := Get_Return_Type (Subprg);

      --  Info for the array type.
      Info : constant Type_Info_Acc := Get_Info (Arr_Type);
      Arr_Ptr_Type : constant O_Tnode := Info.Ortho_Ptr_Type (Mode_Value);

      --  Info for the index type.
      Iinfo      : Type_Info_Acc;
      Index_Type : Iir;

      Id : constant Name_Id := Get_Identifier (Get_Type_Declarator (Arr_Type));

      Index_Otype                      : O_Tnode;
      Interface_List                   : O_Inter_List;
      Var_Res, Var_L, Var_R            : O_Dnode;
      Res, L, R                        : Mnode;
      Var_Length, Var_L_Len, Var_R_Len : O_Dnode;
      Var_Bounds, Var_Right            : O_Dnode;
      V_Bounds                         : Mnode;
      If_Blk                           : O_If_Block;
   begin
      F_Info := Add_Info (Subprg, Kind_Subprg);
      F_Info.Use_Stack2 := True;

      --  Create function.
      Start_Procedure_Decl
        (Interface_List, Create_Identifier (Id, "_CONCAT"), Global_Storage);
      --  Note: contrary to user function which returns composite value
      --  via a result record, a concatenation returns its value without
      --  the use of the record.
      Subprgs.Create_Subprg_Instance (Interface_List, Subprg);
      New_Interface_Decl (Interface_List, Var_Res, Wki_Res, Arr_Ptr_Type);
      New_Interface_Decl (Interface_List, Var_L, Wki_Left, Arr_Ptr_Type);
      New_Interface_Decl (Interface_List, Var_R, Wki_Right, Arr_Ptr_Type);
      Finish_Subprogram_Decl (Interface_List, F_Info.Ortho_Func);

      if Global_Storage = O_Storage_External then
         return;
      end if;

      Index_Type := Get_Index_Type (Arr_Type, 0);
      Iinfo := Get_Info (Index_Type);
      Index_Otype := Iinfo.Ortho_Type (Mode_Value);

      Start_Subprogram_Body (F_Info.Ortho_Func);
      Subprgs.Start_Subprg_Instance_Use (Subprg);
      New_Var_Decl (Var_Length, Wki_Length, O_Storage_Local,
                    Ghdl_Index_Type);
      New_Var_Decl (Var_L_Len, Wki_L_Len, O_Storage_Local, Ghdl_Index_Type);
      New_Var_Decl (Var_R_Len, Wki_R_Len, O_Storage_Local, Ghdl_Index_Type);
      New_Var_Decl (Var_Bounds, Get_Identifier ("bounds"), O_Storage_Local,
                    Info.T.Bounds_Ptr_Type);

      L := Dp2M (Var_L, Info, Mode_Value);
      R := Dp2M (Var_R, Info, Mode_Value);
      Res := Dp2M (Var_Res, Info, Mode_Value);
      V_Bounds := Dp2M (Var_Bounds, Info, Mode_Value,
                        Info.T.Bounds_Type, Info.T.Bounds_Ptr_Type);

      --  Compute length.
      New_Assign_Stmt
        (New_Obj (Var_L_Len), Chap3.Get_Array_Length (L, Arr_Type));
      New_Assign_Stmt
        (New_Obj (Var_R_Len), Chap3.Get_Array_Length (R, Arr_Type));
      New_Assign_Stmt
        (New_Obj (Var_Length), New_Dyadic_Op (ON_Add_Ov,
         New_Obj_Value (Var_L_Len),
         New_Obj_Value (Var_R_Len)));

      --  Check case where the result is the right operand.
      declare
         Len : O_Enode;
      begin
         if Flags.Vhdl_Std = Vhdl_87 then
            --  LRM87 7.2.4
            --  [...], unless the left operand is a null array, in which
            --  case the result of the concatenation is the right operand.
            Len := New_Obj_Value (Var_L_Len);

         else
            --  LRM93 7.2.4
            --  If both operands are null arrays, then the result of the
            --  concatenation is the right operand.
            --  GHDL: since the length type is unsigned, then both operands
            --   are null arrays iff the result is a null array.
            Len := New_Obj_Value (Var_Length);
         end if;

         Start_If_Stmt
           (If_Blk, New_Compare_Op (ON_Eq, Len, New_Lit (Ghdl_Index_0),
                                    Ghdl_Bool_Type));
         Copy_Fat_Pointer (Res, R);
         New_Return_Stmt;
         Finish_If_Stmt (If_Blk);
      end;

      --  Allocate bounds.
      New_Assign_Stmt
        (New_Obj (Var_Bounds),
         Gen_Alloc (Alloc_Return,
           New_Lit (New_Sizeof (Info.T.Bounds_Type,
             Ghdl_Index_Type)),
           Info.T.Bounds_Ptr_Type));
      New_Assign_Stmt
        (M2Lp (Chap3.Get_Array_Bounds (Res)), New_Obj_Value (Var_Bounds));

      --  Set bound.
      if Flags.Vhdl_Std = Vhdl_87 then
         --  Set length.
         New_Assign_Stmt
           (M2Lv (Chap3.Range_To_Length
                    (Chap3.Bounds_To_Range (V_Bounds, Arr_Type, 1))),
            New_Obj_Value (Var_Length));

         --  Set direction, left bound and right bound.
         --  LRM87 7.2.4
         --  The left bound of this result is the left bound of the left
         --  operand, unless the left operand is a null array, in which
         --  case the result of the concatenation is the right operand.
         --  The direction of the result is the direction of the left
         --  operand, unless the left operand is a null array, in which
         --  case the direction of the result is that of the right operand.
         declare
            Var_Dir, Var_Left : O_Dnode;
            Var_Length1       : O_Dnode;
         begin
            Start_Declare_Stmt;
            New_Var_Decl (Var_Right, Get_Identifier ("right_bound"),
                          O_Storage_Local, Index_Otype);
            New_Var_Decl (Var_Dir, Wki_Dir, O_Storage_Local,
                          Ghdl_Dir_Type_Node);
            New_Var_Decl (Var_Left, Get_Identifier ("left_bound"),
                          O_Storage_Local, Iinfo.Ortho_Type (Mode_Value));
            New_Var_Decl (Var_Length1, Get_Identifier ("length_1"),
                          O_Storage_Local, Ghdl_Index_Type);

            --  Copy direction from left.
            New_Assign_Stmt
              (New_Obj (Var_Dir),
               M2E (Chap3.Range_To_Dir
                      (Chap3.Get_Array_Range (L, Arr_Type, 1))));
            New_Assign_Stmt
              (M2Lv (Chap3.Range_To_Dir
                       (Chap3.Bounds_To_Range (V_Bounds, Arr_Type, 1))),
               New_Obj_Value (Var_Dir));

            --  Get left bound of left parameter and copy it to result.
            New_Assign_Stmt
              (New_Obj (Var_Left),
               M2E (Chap3.Range_To_Left
                      (Chap3.Get_Array_Range (L, Arr_Type, 1))));
            New_Assign_Stmt
              (M2Lv (Chap3.Range_To_Left
                       (Chap3.Bounds_To_Range (V_Bounds, Arr_Type, 1))),
               New_Obj_Value (Var_Left));

            --  Note this substraction cannot overflow, since LENGTH >= 1.
            New_Assign_Stmt
              (New_Obj (Var_Length1),
               New_Dyadic_Op (ON_Sub_Ov,
                              New_Obj_Value (Var_Length),
                              New_Lit (Ghdl_Index_1)));

            --  Compute right bound of result:
            --    if dir = dir_to then
            --        right := left + length_1;
            --    else
            --        right := left - length_1;
            --    end if;
            Start_If_Stmt
              (If_Blk,
               New_Compare_Op (ON_Eq, New_Obj_Value (Var_Dir),
                               New_Lit (Ghdl_Dir_To_Node), Ghdl_Bool_Type));
            New_Assign_Stmt
              (New_Obj (Var_Right),
               New_Dyadic_Op (ON_Add_Ov,
                              New_Obj_Value (Var_Left),
                              New_Convert_Ov (New_Obj_Value (Var_Length1),
                                              Index_Otype)));
            New_Else_Stmt (If_Blk);
            New_Assign_Stmt
              (New_Obj (Var_Right),
               New_Dyadic_Op (ON_Sub_Ov,
                              New_Obj_Value (Var_Left),
                              New_Convert_Ov (New_Obj_Value (Var_Length1),
                                              Index_Otype)));
            Finish_If_Stmt (If_Blk);

            --   Check the right bounds is inside the bounds of the
            --   index type.
            Chap3.Check_Range (Var_Right, Null_Iir, Index_Type, Subprg);
            New_Assign_Stmt
              (M2Lv (Chap3.Range_To_Right
               (Chap3.Bounds_To_Range (V_Bounds, Arr_Type, 1))),
               New_Obj_Value (Var_Right));
            Finish_Declare_Stmt;
         end;
      else
         --  LRM93 7.2.4
         --  [...], the direction and bounds of the result are determined
         --  as follows: Let S be the index subtype of the base type of the
         --  result.  The direction of the result of the concatenation is
         --  the direction of S, and the left bound of the result is
         --  S'LEFT.
         Chap3.Create_Range_From_Length
           (Index_Type, Var_Length,
            Chap3.Bounds_To_Range (V_Bounds, Arr_Type, 1), Subprg);
      end if;

      --  Allocate array base.
      Chap3.Allocate_Fat_Array_Base (Alloc_Return, Res, Arr_Type);

      --  Copy left.
      declare
         V_Arr   : O_Dnode;
         Var_Arr : Mnode;
      begin
         Open_Temp;
         V_Arr := Create_Temp (Info.Ortho_Type (Mode_Value));
         Var_Arr := Dv2M (V_Arr, Info, Mode_Value);
         New_Assign_Stmt
           (M2Lp (Chap3.Get_Array_Bounds (Var_Arr)),
            M2Addr (Chap3.Get_Array_Bounds (L)));
         New_Assign_Stmt
           (M2Lp (Chap3.Get_Array_Base (Var_Arr)),
            M2Addr (Chap3.Get_Array_Base (Res)));
         Chap3.Translate_Object_Copy
           (Var_Arr, New_Obj_Value (Var_L), Arr_Type);
         Close_Temp;
      end;

      --  Copy right.
      declare
         V_Arr   : O_Dnode;
         Var_Arr : Mnode;
      begin
         Open_Temp;
         V_Arr := Create_Temp (Info.Ortho_Type (Mode_Value));
         Var_Arr := Dv2M (V_Arr, Info, Mode_Value);
         New_Assign_Stmt
           (M2Lp (Chap3.Get_Array_Bounds (Var_Arr)),
            M2Addr (Chap3.Get_Array_Bounds (R)));
         New_Assign_Stmt
           (M2Lp (Chap3.Get_Array_Base (Var_Arr)),
            M2Addr (Chap3.Slice_Base (Chap3.Get_Array_Base (Res),
                                      Arr_Type,
                                      New_Obj_Value (Var_L_Len))));
         Chap3.Translate_Object_Copy
           (Var_Arr, New_Obj_Value (Var_R), Arr_Type);
         Close_Temp;
      end;
      Subprgs.Finish_Subprg_Instance_Use (Subprg);
      Finish_Subprogram_Body;
   end Translate_Predefined_Array_Array_Concat;

   procedure Translate_Predefined_Array_Logical (Subprg : Iir)
   is
      Arr_Type          : constant Iir_Array_Type_Definition :=
        Get_Type (Get_Interface_Declaration_Chain (Subprg));
      --  Info for the array type.
      Info              : constant Type_Info_Acc := Get_Info (Arr_Type);
      --  Identifier of the type.
      Id                : constant Name_Id :=
        Get_Identifier (Get_Type_Declarator (Arr_Type));
      Arr_Ptr_Type      : constant O_Tnode := Info.Ortho_Ptr_Type (Mode_Value);
      F_Info            : Subprg_Info_Acc;
      Interface_List    : O_Inter_List;
      Var_Res           : O_Dnode;
      Res               : Mnode;
      L, R              : O_Dnode;
      Var_Length, Var_I : O_Dnode;
      Var_Base          : O_Dnode;
      Var_L_Base        : O_Dnode;
      Var_R_Base        : O_Dnode;
      If_Blk            : O_If_Block;
      Label             : O_Snode;
      Name              : O_Ident;
      Is_Monadic        : Boolean;
      El, L_El          : O_Enode;
      Op                : ON_Op_Kind;
      Do_Invert         : Boolean;
   begin
      F_Info := Add_Info (Subprg, Kind_Subprg);
      --Chap2.Clear_Instance_Data (F_Info.Subprg_Instance);
      F_Info.Use_Stack2 := True;

      Is_Monadic := False;
      case Get_Implicit_Definition (Subprg) is
         when Iir_Predefined_TF_Array_And =>
            Name := Create_Identifier (Id, "_AND");
            Op := ON_And;
            Do_Invert := False;
         when Iir_Predefined_TF_Array_Or =>
            Name := Create_Identifier (Id, "_OR");
            Op := ON_Or;
            Do_Invert := False;
         when Iir_Predefined_TF_Array_Nand =>
            Name := Create_Identifier (Id, "_NAND");
            Op := ON_And;
            Do_Invert := True;
         when Iir_Predefined_TF_Array_Nor =>
            Name := Create_Identifier (Id, "_NOR");
            Op := ON_Or;
            Do_Invert := True;
         when Iir_Predefined_TF_Array_Xor =>
            Name := Create_Identifier (Id, "_XOR");
            Op := ON_Xor;
            Do_Invert := False;
         when Iir_Predefined_TF_Array_Xnor =>
            Name := Create_Identifier (Id, "_XNOR");
            Op := ON_Xor;
            Do_Invert := True;
         when Iir_Predefined_TF_Array_Not =>
            Name := Create_Identifier (Id, "_NOT");
            Is_Monadic := True;
            Op := ON_Not;
            Do_Invert := False;
         when others =>
            raise Internal_Error;
      end case;

      --  Create function.
      Start_Procedure_Decl (Interface_List, Name, Global_Storage);
      --  Note: contrary to user function which returns composite value
      --  via a result record, a concatenation returns its value without
      --  the use of the record.
      New_Interface_Decl (Interface_List, Var_Res, Wki_Res, Arr_Ptr_Type);
      New_Interface_Decl (Interface_List, L, Wki_Left, Arr_Ptr_Type);
      if not Is_Monadic then
         New_Interface_Decl (Interface_List, R, Wki_Right, Arr_Ptr_Type);
      end if;
      Finish_Subprogram_Decl (Interface_List, F_Info.Ortho_Func);

      if Global_Storage = O_Storage_External then
         return;
      end if;

      Start_Subprogram_Body (F_Info.Ortho_Func);
      New_Var_Decl (Var_Length, Wki_Length, O_Storage_Local,
                    Ghdl_Index_Type);
      New_Var_Decl (Var_I, Wki_I, O_Storage_Local, Ghdl_Index_Type);
      New_Var_Decl (Var_Base, Get_Identifier ("base"), O_Storage_Local,
                    Info.T.Base_Ptr_Type (Mode_Value));
      New_Var_Decl (Var_L_Base, Get_Identifier ("l_base"), O_Storage_Local,
                    Info.T.Base_Ptr_Type (Mode_Value));
      if not Is_Monadic then
         New_Var_Decl
           (Var_R_Base, Get_Identifier ("r_base"), O_Storage_Local,
            Info.T.Base_Ptr_Type (Mode_Value));
      end if;
      Open_Temp;
      --  Get length of LEFT.
      New_Assign_Stmt (New_Obj (Var_Length),
                       Chap6.Get_Array_Bound_Length
                         (Dp2M (L, Info, Mode_Value), Arr_Type, 1));
      --  If dyadic, check RIGHT has the same length.
      if not Is_Monadic then
         Chap6.Check_Bound_Error
           (New_Compare_Op (ON_Neq,
            New_Obj_Value (Var_Length),
            Chap6.Get_Array_Bound_Length
              (Dp2M (R, Info, Mode_Value), Arr_Type, 1),
            Ghdl_Bool_Type),
            Subprg, 0);
      end if;

      --  Create the result from LEFT bound.
      Res := Dp2M (Var_Res, Info, Mode_Value);
      Chap3.Translate_Object_Allocation
        (Res, Alloc_Return, Arr_Type,
         Chap3.Get_Array_Bounds (Dp2M (L, Info, Mode_Value)));
      New_Assign_Stmt
        (New_Obj (Var_Base), M2Addr (Chap3.Get_Array_Base (Res)));
      New_Assign_Stmt
        (New_Obj (Var_L_Base),
         M2Addr (Chap3.Get_Array_Base (Dp2M (L, Info, Mode_Value))));
      if not Is_Monadic then
         New_Assign_Stmt
           (New_Obj (Var_R_Base),
            M2Addr (Chap3.Get_Array_Base (Dp2M (R, Info, Mode_Value))));
      end if;

      --  Do the logical operation on each element.
      Init_Var (Var_I);
      Start_Loop_Stmt (Label);
      Start_If_Stmt (If_Blk,
                     New_Compare_Op (ON_Ge,
                       New_Obj_Value (Var_I),
                       New_Obj_Value (Var_Length),
                       Ghdl_Bool_Type));
      New_Return_Stmt;
      Finish_If_Stmt (If_Blk);
      L_El := New_Value (New_Indexed_Element
                         (New_Acc_Value (New_Obj (Var_L_Base)),
                            New_Obj_Value (Var_I)));
      if Is_Monadic then
         El := New_Monadic_Op (Op, L_El);
      else
         El := New_Dyadic_Op
           (Op, L_El,
            New_Value (New_Indexed_Element
              (New_Acc_Value (New_Obj (Var_R_Base)),
                   New_Obj_Value (Var_I))));
      end if;
      if Do_Invert then
         El := New_Monadic_Op (ON_Not, El);
      end if;

      New_Assign_Stmt (New_Indexed_Element
                       (New_Acc_Value (New_Obj (Var_Base)),
                          New_Obj_Value (Var_I)),
                       El);
      Inc_Var (Var_I);
      Finish_Loop_Stmt (Label);
      Close_Temp;
      Finish_Subprogram_Body;
   end Translate_Predefined_Array_Logical;

   procedure Translate_Predefined_Array_Shift (Subprg : Iir)
   is
      F_Info         : Subprg_Info_Acc;
      Inter          : Iir;
      Arr_Type       : Iir_Array_Type_Definition;
      Arr_Ptr_Type   : O_Tnode;
      Int_Type       : O_Tnode;
      --  Info for the array type.
      Info           : Type_Info_Acc;
      Id             : Name_Id;
      Interface_List : O_Inter_List;
      Var_Res        : O_Dnode;
      Var_L, Var_R   : O_Dnode;
      Name           : O_Ident;

      type Shift_Kind is (Sh_Logical, Sh_Arith, Rotation);
      Shift : Shift_Kind;

      --  Body;
      Var_Length, Var_I, Var_I1 : O_Dnode;
      Var_Res_Base, Var_L_Base  : O_Dnode;
      Var_Rl                    : O_Dnode;
      Var_E                     : O_Dnode;
      L                         : Mnode;
      If_Blk, If_Blk1           : O_If_Block;
      Label                     : O_Snode;
      Res                       : Mnode;

      procedure Do_Shift (To_Right : Boolean)
      is
         Tmp : O_Enode;
      begin
         --  LEFT:
         --  * I := 0;
         if not To_Right then
            Init_Var (Var_I);
         end if;

         --  * If R < LENGTH then
         Start_If_Stmt (If_Blk1,
                        New_Compare_Op (ON_Lt,
                          New_Obj_Value (Var_Rl),
                          New_Obj_Value (Var_Length),
                          Ghdl_Bool_Type));
         --  Shift the elements (that remains in the result).
         --  RIGHT:
         --  *   for I = R to LENGTH - 1 loop
         --  *     RES[I] := L[I - R]
         --  LEFT:
         --  *   for I = 0 to LENGTH - R loop
         --  *     RES[I] := L[R + I]
         if To_Right then
            New_Assign_Stmt (New_Obj (Var_I), New_Obj_Value (Var_Rl));
            Init_Var (Var_I1);
         else
            New_Assign_Stmt (New_Obj (Var_I1), New_Obj_Value (Var_Rl));
         end if;
         Start_Loop_Stmt (Label);
         if To_Right then
            Tmp := New_Obj_Value (Var_I);
         else
            Tmp := New_Obj_Value (Var_I1);
         end if;
         Gen_Exit_When (Label, New_Compare_Op (ON_Ge,
                        Tmp,
                        New_Obj_Value (Var_Length),
                        Ghdl_Bool_Type));
         New_Assign_Stmt
           (New_Indexed_Acc_Value (New_Obj (Var_Res_Base),
            New_Obj_Value (Var_I)),
            New_Value
              (New_Indexed_Acc_Value (New_Obj (Var_L_Base),
               New_Obj_Value (Var_I1))));
         Inc_Var (Var_I);
         Inc_Var (Var_I1);
         Finish_Loop_Stmt (Label);
         --  RIGHT:
         --  * else
         --  *   R := LENGTH;
         if To_Right then
            New_Else_Stmt (If_Blk1);
            New_Assign_Stmt (New_Obj (Var_Rl), New_Obj_Value (Var_Length));
         end if;
         Finish_If_Stmt (If_Blk1);

         --  Pad the result.
         --  RIGHT:
         --  * For I = 0 to R - 1
         --  *   RES[I] := 0/L[0/LENGTH-1]
         --  LEFT:
         --  * For I = LENGTH - R to LENGTH - 1
         --  *   RES[I] := 0/L[0/LENGTH-1]
         if To_Right then
            Init_Var (Var_I);
         else
            --  I is yet correctly set.
            null;
         end if;
         if Shift = Sh_Arith then
            if To_Right then
               Tmp := New_Lit (Ghdl_Index_0);
            else
               Tmp := New_Dyadic_Op
                 (ON_Sub_Ov,
                  New_Obj_Value (Var_Length),
                  New_Lit (Ghdl_Index_1));
            end if;
            New_Assign_Stmt
              (New_Obj (Var_E),
               New_Value (New_Indexed_Acc_Value (New_Obj (Var_L_Base),
                 Tmp)));
         end if;
         Start_Loop_Stmt (Label);
         if To_Right then
            Tmp := New_Obj_Value (Var_Rl);
         else
            Tmp := New_Obj_Value (Var_Length);
         end if;
         Gen_Exit_When (Label, New_Compare_Op (ON_Ge,
                        New_Obj_Value (Var_I),
                        Tmp,
                        Ghdl_Bool_Type));
         case Shift is
            when Sh_Logical =>
               declare
                  Enum_List : Iir_List;
               begin
                  Enum_List := Get_Enumeration_Literal_List
                    (Get_Base_Type (Get_Element_Subtype (Arr_Type)));
                  Tmp := New_Lit
                    (Get_Ortho_Expr (Get_First_Element (Enum_List)));
               end;
            when Sh_Arith =>
               Tmp := New_Obj_Value (Var_E);
            when Rotation =>
               raise Internal_Error;
         end case;

         New_Assign_Stmt
           (New_Indexed_Acc_Value (New_Obj (Var_Res_Base),
            New_Obj_Value (Var_I)), Tmp);
         Inc_Var (Var_I);
         Finish_Loop_Stmt (Label);
      end Do_Shift;
   begin
      Inter := Get_Interface_Declaration_Chain (Subprg);

      Info := Get_Info (Get_Type (Get_Chain (Inter)));
      Int_Type := Info.Ortho_Type (Mode_Value);

      Arr_Type := Get_Type (Inter);
      Info := Get_Info (Arr_Type);
      Id := Get_Identifier (Get_Type_Declarator (Arr_Type));
      Arr_Ptr_Type := Info.Ortho_Ptr_Type (Mode_Value);

      F_Info := Add_Info (Subprg, Kind_Subprg);
      --Chap2.Clear_Instance_Data (F_Info.Subprg_Instance);
      F_Info.Use_Stack2 := True;

      case Get_Implicit_Definition (Subprg) is
         when Iir_Predefined_Array_Sll
            | Iir_Predefined_Array_Srl =>
            --  Shift logical.
            Name := Create_Identifier (Id, "_SHL");
            Shift := Sh_Logical;
         when Iir_Predefined_Array_Sla
            | Iir_Predefined_Array_Sra =>
            --  Shift arithmetic.
            Name := Create_Identifier (Id, "_SHA");
            Shift := Sh_Arith;
         when Iir_Predefined_Array_Rol
            | Iir_Predefined_Array_Ror =>
            --  Rotation
            Name := Create_Identifier (Id, "_ROT");
            Shift := Rotation;
         when others =>
            raise Internal_Error;
      end case;

      --  Create function.
      Start_Procedure_Decl (Interface_List, Name, Global_Storage);
      --  Note: contrary to user function which returns composite value
      --  via a result record, a shift returns its value without
      --  the use of the record.
      New_Interface_Decl (Interface_List, Var_Res, Wki_Res, Arr_Ptr_Type);
      New_Interface_Decl (Interface_List, Var_L, Wki_Left, Arr_Ptr_Type);
      New_Interface_Decl (Interface_List, Var_R, Wki_Right, Int_Type);
      Finish_Subprogram_Decl (Interface_List, F_Info.Ortho_Func);

      if Global_Storage = O_Storage_External then
         return;
      end if;

      --  Body
      Start_Subprogram_Body (F_Info.Ortho_Func);
      New_Var_Decl (Var_Length, Wki_Length, O_Storage_Local,
                    Ghdl_Index_Type);
      if Shift /= Rotation then
         New_Var_Decl (Var_Rl, Get_Identifier ("rl"), O_Storage_Local,
                       Ghdl_Index_Type);
      end if;
      New_Var_Decl (Var_I, Wki_I, O_Storage_Local, Ghdl_Index_Type);
      New_Var_Decl (Var_I1, Get_Identifier ("I1"), O_Storage_Local,
                    Ghdl_Index_Type);
      New_Var_Decl (Var_Res_Base, Get_Identifier ("res_base"),
                    O_Storage_Local, Info.T.Base_Ptr_Type (Mode_Value));
      New_Var_Decl (Var_L_Base, Get_Identifier ("l_base"),
                    O_Storage_Local, Info.T.Base_Ptr_Type (Mode_Value));
      if Shift = Sh_Arith then
         New_Var_Decl (Var_E, Get_Identifier ("E"), O_Storage_Local,
                       Get_Info (Get_Element_Subtype (Arr_Type)).
                         Ortho_Type (Mode_Value));
      end if;
      Res := Dp2M (Var_Res, Info, Mode_Value);
      L := Dp2M (Var_L, Info, Mode_Value);

      --  LRM93 7.2.3
      --  The index subtypes of the return values of all shift operators is
      --  the same as the index subtype of their left arguments.
      New_Assign_Stmt
        (M2Lp (Chap3.Get_Array_Bounds (Res)),
         M2Addr (Chap3.Get_Array_Bounds (L)));

      --  Get length of LEFT.
      New_Assign_Stmt (New_Obj (Var_Length),
                       Chap3.Get_Array_Length (L, Arr_Type));

      --  LRM93 7.2.3 [6 times]
      --  That is, if R is 0 or L is a null array, the return value is L.
      Start_If_Stmt
        (If_Blk,
         New_Dyadic_Op
           (ON_Or,
            New_Compare_Op (ON_Eq,
              New_Obj_Value (Var_R),
              New_Lit (New_Signed_Literal (Int_Type, 0)),
              Ghdl_Bool_Type),
            New_Compare_Op (ON_Eq,
              New_Obj_Value (Var_Length),
              New_Lit (Ghdl_Index_0),
              Ghdl_Bool_Type)));
      New_Assign_Stmt
        (M2Lp (Chap3.Get_Array_Base (Res)),
         M2Addr (Chap3.Get_Array_Base (L)));
      New_Return_Stmt;
      Finish_If_Stmt (If_Blk);

      --  Allocate base.
      New_Assign_Stmt
        (New_Obj (Var_Res_Base),
         Gen_Alloc (Alloc_Return, New_Obj_Value (Var_Length),
           Info.T.Base_Ptr_Type (Mode_Value)));
      New_Assign_Stmt (M2Lp (Chap3.Get_Array_Base (Res)),
                       New_Obj_Value (Var_Res_Base));

      New_Assign_Stmt (New_Obj (Var_L_Base),
                       M2Addr (Chap3.Get_Array_Base (L)));

      Start_If_Stmt (If_Blk,
                     New_Compare_Op (ON_Gt,
                       New_Obj_Value (Var_R),
                       New_Lit (New_Signed_Literal (Int_Type,
                         0)),
                       Ghdl_Bool_Type));
      --  R > 0.
      --  Ie, to the right
      case Shift is
         when Rotation =>
            --  * I1 := LENGTH - (R mod LENGTH)
            New_Assign_Stmt
              (New_Obj (Var_I1),
               New_Dyadic_Op
                 (ON_Sub_Ov,
                  New_Obj_Value (Var_Length),
                  New_Dyadic_Op (ON_Mod_Ov,
                    New_Convert_Ov (New_Obj_Value (Var_R),
                      Ghdl_Index_Type),
                    New_Obj_Value (Var_Length))));

         when Sh_Logical
            | Sh_Arith =>
            --  Real SRL or SRA.
            New_Assign_Stmt
              (New_Obj (Var_Rl),
               New_Convert_Ov (New_Obj_Value (Var_R), Ghdl_Index_Type));

            Do_Shift (True);
      end case;

      New_Else_Stmt (If_Blk);

      --  R < 0, to the left.
      case Shift is
         when Rotation =>
            --  * I1 := (-R) mod LENGTH
            New_Assign_Stmt
              (New_Obj (Var_I1),
               New_Dyadic_Op (ON_Mod_Ov,
                 New_Convert_Ov
                   (New_Monadic_Op (ON_Neg_Ov,
                    New_Obj_Value (Var_R)),
                    Ghdl_Index_Type),
                 New_Obj_Value (Var_Length)));
         when Sh_Logical
            | Sh_Arith =>
            --  Real SLL or SLA.
            New_Assign_Stmt
              (New_Obj (Var_Rl),
               New_Convert_Ov (New_Monadic_Op (ON_Neg_Ov,
                 New_Obj_Value (Var_R)),
                 Ghdl_Index_Type));

            Do_Shift (False);
      end case;
      Finish_If_Stmt (If_Blk);

      if Shift = Rotation then
         --  *     If I1 = LENGTH then
         --  *        I1 := 0
         Start_If_Stmt (If_Blk, New_Compare_Op (ON_Ge,
                        New_Obj_Value (Var_I1),
                        New_Obj_Value (Var_Length),
                        Ghdl_Bool_Type));
         Init_Var (Var_I1);
         Finish_If_Stmt (If_Blk);

         --  *   for I = 0 to LENGTH - 1 loop
         --  *     RES[I] := L[I1];
         Init_Var (Var_I);
         Start_Loop_Stmt (Label);
         Gen_Exit_When (Label, New_Compare_Op (ON_Ge,
                        New_Obj_Value (Var_I),
                        New_Obj_Value (Var_Length),
                        Ghdl_Bool_Type));
         New_Assign_Stmt
           (New_Indexed_Acc_Value (New_Obj (Var_Res_Base),
            New_Obj_Value (Var_I)),
            New_Value
              (New_Indexed_Acc_Value (New_Obj (Var_L_Base),
               New_Obj_Value (Var_I1))));
         Inc_Var (Var_I);
         --  *     I1 := I1 + 1
         Inc_Var (Var_I1);
         --  *     If I1 = LENGTH then
         --  *        I1 := 0
         Start_If_Stmt (If_Blk, New_Compare_Op (ON_Ge,
                        New_Obj_Value (Var_I1),
                        New_Obj_Value (Var_Length),
                        Ghdl_Bool_Type));
         Init_Var (Var_I1);
         Finish_If_Stmt (If_Blk);
         Finish_Loop_Stmt (Label);
      end if;
      Finish_Subprogram_Body;
   end Translate_Predefined_Array_Shift;

   procedure Translate_File_Subprogram (Subprg : Iir; File_Type : Iir)
   is
      Etype      : Iir;
      Tinfo      : Type_Info_Acc;
      Kind       : Iir_Predefined_Functions;
      F_Info     : Subprg_Info_Acc;
      Name       : O_Ident;
      Inter_List : O_Inter_List;
      Id         : Name_Id;
      Var_File   : O_Dnode;
      Var_Val    : O_Dnode;

      procedure Translate_Rw (Val : Mnode; Val_Type : Iir; Proc : O_Dnode);

      procedure Translate_Rw_Array
        (Val : Mnode; Val_Type : Iir; Var_Max : O_Dnode; Proc : O_Dnode)
      is
         Var_It : O_Dnode;
         Label  : O_Snode;
      begin
         Var_It := Create_Temp (Ghdl_Index_Type);
         Init_Var (Var_It);
         Start_Loop_Stmt (Label);
         Gen_Exit_When
           (Label,
            New_Compare_Op (ON_Eq,
              New_Obj_Value (Var_It),
              New_Obj_Value (Var_Max),
              Ghdl_Bool_Type));
         Translate_Rw
           (Chap3.Index_Base (Val, Val_Type, New_Obj_Value (Var_It)),
            Get_Element_Subtype (Val_Type), Proc);
         Inc_Var (Var_It);
         Finish_Loop_Stmt (Label);
      end Translate_Rw_Array;

      procedure Translate_Rw (Val : Mnode; Val_Type : Iir; Proc : O_Dnode)
      is
         Val_Info : Type_Info_Acc;
         Assocs   : O_Assoc_List;
      begin
         Val_Info := Get_Type_Info (Val);
         case Val_Info.Type_Mode is
            when Type_Mode_Scalar =>
               Start_Association (Assocs, Proc);
               --    compute file parameter (get an index)
               New_Association (Assocs, New_Obj_Value (Var_File));
               --    compute the value.
               New_Association
                 (Assocs, New_Convert_Ov (M2Addr (Val), Ghdl_Ptr_Type));
               --    length.
               New_Association
                 (Assocs,
                  New_Lit (New_Sizeof (Val_Info.Ortho_Type (Mode_Value),
                    Ghdl_Index_Type)));
               --    call a predefined procedure
               New_Procedure_Call (Assocs);
            when Type_Mode_Record =>
               declare
                  El_List : Iir_List;
                  El      : Iir;
                  Val1    : Mnode;
               begin
                  Open_Temp;
                  Val1 := Stabilize (Val);
                  El_List := Get_Elements_Declaration_List
                    (Get_Base_Type (Val_Type));
                  for I in Natural loop
                     El := Get_Nth_Element (El_List, I);
                     exit when El = Null_Iir;
                     Translate_Rw
                       (Chap6.Translate_Selected_Element (Val1, El),
                        Get_Type (El), Proc);
                  end loop;
                  Close_Temp;
               end;
            when Type_Mode_Array =>
               declare
                  Var_Max : O_Dnode;
               begin
                  Open_Temp;
                  Var_Max := Create_Temp (Ghdl_Index_Type);
                  New_Assign_Stmt
                    (New_Obj (Var_Max),
                     Chap3.Get_Array_Type_Length (Val_Type));
                  Translate_Rw_Array (Val, Val_Type, Var_Max, Proc);
                  Close_Temp;
               end;
            when Type_Mode_Unknown
               | Type_Mode_File
               | Type_Mode_Acc
               | Type_Mode_Fat_Acc
               | Type_Mode_Fat_Array
               | Type_Mode_Protected =>
               raise Internal_Error;
         end case;
      end Translate_Rw;

      procedure Translate_Rw_Length (Var_Length : O_Dnode; Proc : O_Dnode)
      is
         Assocs : O_Assoc_List;
      begin
         Start_Association (Assocs, Proc);
         New_Association (Assocs, New_Obj_Value (Var_File));
         New_Association
           (Assocs, New_Unchecked_Address (New_Obj (Var_Length),
            Ghdl_Ptr_Type));
         New_Association
           (Assocs,
            New_Lit (New_Sizeof (Ghdl_Index_Type, Ghdl_Index_Type)));
         New_Procedure_Call (Assocs);
      end Translate_Rw_Length;

      Var : Mnode;
   begin
      Etype := Get_Type (Get_File_Type_Mark (File_Type));
      Tinfo := Get_Info (Etype);
      if Tinfo.Type_Mode in Type_Mode_Scalar then
         --  Intrinsic.
         return;
      end if;

      F_Info := Add_Info (Subprg, Kind_Subprg);
      --Chap2.Clear_Instance_Data (F_Info.Subprg_Instance);
      F_Info.Use_Stack2 := False;

      Id := Get_Identifier (Get_Type_Declarator (File_Type));
      Kind := Get_Implicit_Definition (Subprg);
      case Kind is
         when Iir_Predefined_Write =>
            Name := Create_Identifier (Id, "_WRITE");
         when Iir_Predefined_Read
            | Iir_Predefined_Read_Length =>
            Name := Create_Identifier (Id, "_READ");
         when others =>
            raise Internal_Error;
      end case;

      --  Create function.
      if Kind = Iir_Predefined_Read_Length then
         Start_Function_Decl
           (Inter_List, Name, Global_Storage, Std_Integer_Otype);
      else
         Start_Procedure_Decl (Inter_List, Name, Global_Storage);
      end if;
      Subprgs.Create_Subprg_Instance (Inter_List, Subprg);

      New_Interface_Decl
        (Inter_List, Var_File, Get_Identifier ("FILE"),
         Ghdl_File_Index_Type);
      New_Interface_Decl
        (Inter_List, Var_Val, Wki_Val,
         Tinfo.Ortho_Ptr_Type (Mode_Value));
      Finish_Subprogram_Decl (Inter_List, F_Info.Ortho_Func);

      if Global_Storage = O_Storage_External then
         return;
      end if;

      Start_Subprogram_Body (F_Info.Ortho_Func);
      Subprgs.Start_Subprg_Instance_Use (Subprg);
      Push_Local_Factory;

      Var := Dp2M (Var_Val, Tinfo, Mode_Value);

      case Kind is
         when Iir_Predefined_Write =>
            if Tinfo.Type_Mode = Type_Mode_Fat_Array then
               declare
                  Var_Max : O_Dnode;
               begin
                  Open_Temp;
                  Var_Max := Create_Temp_Init
                    (Ghdl_Index_Type,
                     Chap3.Get_Array_Length (Var, Etype));
                  Translate_Rw_Length (Var_Max, Ghdl_Write_Scalar);
                  Translate_Rw_Array (Chap3.Get_Array_Base (Var), Etype,
                                      Var_Max, Ghdl_Write_Scalar);
                  Close_Temp;
               end;
            else
               Translate_Rw (Var, Etype, Ghdl_Write_Scalar);
            end if;
         when Iir_Predefined_Read =>
            Translate_Rw (Var, Etype, Ghdl_Read_Scalar);

         when Iir_Predefined_Read_Length =>
            declare
               Var_Len : O_Dnode;
            begin
               Open_Temp;
               Var_Len := Create_Temp (Ghdl_Index_Type);
               Translate_Rw_Length (Var_Len, Ghdl_Read_Scalar);

               Chap6.Check_Bound_Error
                 (New_Compare_Op (ON_Gt,
                  New_Obj_Value (Var_Len),
                  Chap3.Get_Array_Length (Var, Etype),
                  Ghdl_Bool_Type),
                  Subprg, 1);
               Translate_Rw_Array (Chap3.Get_Array_Base (Var), Etype,
                                   Var_Len, Ghdl_Read_Scalar);
               New_Return_Stmt (New_Convert_Ov (New_Obj_Value (Var_Len),
                                Std_Integer_Otype));
               Close_Temp;
            end;
         when others =>
            raise Internal_Error;
      end case;
      Subprgs.Finish_Subprg_Instance_Use (Subprg);
      Pop_Local_Factory;
      Finish_Subprogram_Body;
   end Translate_File_Subprogram;

   procedure Init_Implicit_Subprogram_Infos
     (Infos : out Implicit_Subprogram_Infos) is
   begin
      --  Be independant of declaration order since the same subprogram
      --  may be used for several implicit operators (eg. array comparaison)
      Infos.Arr_Eq_Info := null;
      Infos.Arr_Cmp_Info := null;
      Infos.Arr_Concat_Info := null;
      Infos.Rec_Eq_Info := null;
      Infos.Arr_Shl_Info := null;
      Infos.Arr_Sha_Info := null;
      Infos.Arr_Rot_Info := null;
   end Init_Implicit_Subprogram_Infos;

   procedure Translate_Implicit_Subprogram
     (Subprg : Iir; Infos : in out Implicit_Subprogram_Infos)
   is
      Kind : constant Iir_Predefined_Functions :=
        Get_Implicit_Definition (Subprg);
   begin
      if Predefined_To_Onop (Kind) /= ON_Nil then
         --  Intrinsic.
         return;
      end if;

      case Kind is
         when Iir_Predefined_Error =>
            raise Internal_Error;
         when Iir_Predefined_Boolean_And
            | Iir_Predefined_Boolean_Or
            | Iir_Predefined_Boolean_Xor
            | Iir_Predefined_Boolean_Not
            | Iir_Predefined_Enum_Equality
            | Iir_Predefined_Enum_Inequality
            | Iir_Predefined_Enum_Less
            | Iir_Predefined_Enum_Less_Equal
            | Iir_Predefined_Enum_Greater
            | Iir_Predefined_Enum_Greater_Equal
            | Iir_Predefined_Bit_And
            | Iir_Predefined_Bit_Or
            | Iir_Predefined_Bit_Xor
            | Iir_Predefined_Bit_Not
            | Iir_Predefined_Integer_Equality
            | Iir_Predefined_Integer_Inequality
            | Iir_Predefined_Integer_Less
            | Iir_Predefined_Integer_Less_Equal
            | Iir_Predefined_Integer_Greater
            | Iir_Predefined_Integer_Greater_Equal
            | Iir_Predefined_Integer_Negation
            | Iir_Predefined_Integer_Absolute
            | Iir_Predefined_Integer_Plus
            | Iir_Predefined_Integer_Minus
            | Iir_Predefined_Integer_Mul
            | Iir_Predefined_Integer_Div
            | Iir_Predefined_Integer_Mod
            | Iir_Predefined_Integer_Rem
            | Iir_Predefined_Floating_Equality
            | Iir_Predefined_Floating_Inequality
            | Iir_Predefined_Floating_Less
            | Iir_Predefined_Floating_Less_Equal
            | Iir_Predefined_Floating_Greater
            | Iir_Predefined_Floating_Greater_Equal
            | Iir_Predefined_Floating_Negation
            | Iir_Predefined_Floating_Absolute
            | Iir_Predefined_Floating_Plus
            | Iir_Predefined_Floating_Minus
            | Iir_Predefined_Floating_Mul
            | Iir_Predefined_Floating_Div
            | Iir_Predefined_Physical_Equality
            | Iir_Predefined_Physical_Inequality
            | Iir_Predefined_Physical_Less
            | Iir_Predefined_Physical_Less_Equal
            | Iir_Predefined_Physical_Greater
            | Iir_Predefined_Physical_Greater_Equal
            | Iir_Predefined_Physical_Negation
            | Iir_Predefined_Physical_Absolute
            | Iir_Predefined_Physical_Plus
            | Iir_Predefined_Physical_Minus =>
            pragma Assert (Predefined_To_Onop (Kind) /= ON_Nil);
            return;

         when Iir_Predefined_Boolean_Nand
            | Iir_Predefined_Boolean_Nor
            | Iir_Predefined_Boolean_Xnor
            | Iir_Predefined_Bit_Nand
            | Iir_Predefined_Bit_Nor
            | Iir_Predefined_Bit_Xnor
            | Iir_Predefined_Bit_Match_Equality
            | Iir_Predefined_Bit_Match_Inequality
            | Iir_Predefined_Bit_Match_Less
            | Iir_Predefined_Bit_Match_Less_Equal
            | Iir_Predefined_Bit_Match_Greater
            | Iir_Predefined_Bit_Match_Greater_Equal
            | Iir_Predefined_Bit_Condition
            | Iir_Predefined_Boolean_Rising_Edge
            | Iir_Predefined_Boolean_Falling_Edge
            | Iir_Predefined_Bit_Rising_Edge
            | Iir_Predefined_Bit_Falling_Edge =>
            --  Intrinsic.
            null;

         when Iir_Predefined_Enum_Minimum
            | Iir_Predefined_Enum_Maximum
            | Iir_Predefined_Enum_To_String =>
            --  Intrinsic.
            null;

         when Iir_Predefined_Integer_Identity
            | Iir_Predefined_Integer_Exp
            | Iir_Predefined_Integer_Minimum
            | Iir_Predefined_Integer_Maximum
            | Iir_Predefined_Integer_To_String =>
            --  Intrinsic.
            null;
         when Iir_Predefined_Universal_R_I_Mul
            | Iir_Predefined_Universal_I_R_Mul
            | Iir_Predefined_Universal_R_I_Div =>
            --  Intrinsic
            null;

         when Iir_Predefined_Physical_Identity
            | Iir_Predefined_Physical_Minimum
            | Iir_Predefined_Physical_Maximum
            | Iir_Predefined_Physical_To_String
            | Iir_Predefined_Time_To_String_Unit =>
            null;

         when Iir_Predefined_Physical_Integer_Mul
            | Iir_Predefined_Physical_Integer_Div
            | Iir_Predefined_Integer_Physical_Mul
            | Iir_Predefined_Physical_Real_Mul
            | Iir_Predefined_Physical_Real_Div
            | Iir_Predefined_Real_Physical_Mul
            | Iir_Predefined_Physical_Physical_Div =>
            null;

         when Iir_Predefined_Floating_Exp
            | Iir_Predefined_Floating_Identity
            | Iir_Predefined_Floating_Minimum
            | Iir_Predefined_Floating_Maximum
            | Iir_Predefined_Floating_To_String
            | Iir_Predefined_Real_To_String_Digits
            | Iir_Predefined_Real_To_String_Format =>
            null;

         when Iir_Predefined_Record_Equality
            | Iir_Predefined_Record_Inequality =>
            if Infos.Rec_Eq_Info = null then
               Translate_Predefined_Record_Equality (Subprg);
               Infos.Rec_Eq_Info := Get_Info (Subprg);
            else
               Set_Info (Subprg, Infos.Rec_Eq_Info);
            end if;

         when Iir_Predefined_Array_Equality
            | Iir_Predefined_Array_Inequality
            | Iir_Predefined_Bit_Array_Match_Equality
            | Iir_Predefined_Bit_Array_Match_Inequality =>
            if Infos.Arr_Eq_Info = null then
               Translate_Predefined_Array_Equality (Subprg);
               Infos.Arr_Eq_Info := Get_Info (Subprg);
            else
               Set_Info (Subprg, Infos.Arr_Eq_Info);
            end if;

         when Iir_Predefined_Array_Greater
            | Iir_Predefined_Array_Greater_Equal
            | Iir_Predefined_Array_Less
            | Iir_Predefined_Array_Less_Equal
            | Iir_Predefined_Array_Minimum
            | Iir_Predefined_Array_Maximum =>
            if Infos.Arr_Cmp_Info = null then
               Translate_Predefined_Array_Compare (Subprg);
               Infos.Arr_Cmp_Info := Get_Info (Subprg);
            else
               Set_Info (Subprg, Infos.Arr_Cmp_Info);
            end if;

         when Iir_Predefined_Array_Array_Concat
            | Iir_Predefined_Array_Element_Concat
            | Iir_Predefined_Element_Array_Concat
            | Iir_Predefined_Element_Element_Concat =>
            if Infos.Arr_Concat_Info = null then
               Translate_Predefined_Array_Array_Concat (Subprg);
               Infos.Arr_Concat_Info := Get_Info (Subprg);
            else
               Set_Info (Subprg, Infos.Arr_Concat_Info);
            end if;

         when Iir_Predefined_Vector_Minimum
            | Iir_Predefined_Vector_Maximum =>
            null;

         when Iir_Predefined_TF_Array_And
            | Iir_Predefined_TF_Array_Or
            | Iir_Predefined_TF_Array_Nand
            | Iir_Predefined_TF_Array_Nor
            | Iir_Predefined_TF_Array_Xor
            | Iir_Predefined_TF_Array_Xnor
            | Iir_Predefined_TF_Array_Not =>
            Translate_Predefined_Array_Logical (Subprg);

         when Iir_Predefined_TF_Reduction_And
            | Iir_Predefined_TF_Reduction_Or
            | Iir_Predefined_TF_Reduction_Nand
            | Iir_Predefined_TF_Reduction_Nor
            | Iir_Predefined_TF_Reduction_Xor
            | Iir_Predefined_TF_Reduction_Xnor
            | Iir_Predefined_TF_Reduction_Not
            | Iir_Predefined_TF_Array_Element_And
            | Iir_Predefined_TF_Element_Array_And
            | Iir_Predefined_TF_Array_Element_Or
            | Iir_Predefined_TF_Element_Array_Or
            | Iir_Predefined_TF_Array_Element_Nand
            | Iir_Predefined_TF_Element_Array_Nand
            | Iir_Predefined_TF_Array_Element_Nor
            | Iir_Predefined_TF_Element_Array_Nor
            | Iir_Predefined_TF_Array_Element_Xor
            | Iir_Predefined_TF_Element_Array_Xor
            | Iir_Predefined_TF_Array_Element_Xnor
            | Iir_Predefined_TF_Element_Array_Xnor =>
            null;

         when Iir_Predefined_Array_Sll
            | Iir_Predefined_Array_Srl =>
            if Infos.Arr_Shl_Info = null then
               Translate_Predefined_Array_Shift (Subprg);
               Infos.Arr_Shl_Info := Get_Info (Subprg);
            else
               Set_Info (Subprg, Infos.Arr_Shl_Info);
            end if;

         when Iir_Predefined_Array_Sla
            | Iir_Predefined_Array_Sra =>
            if Infos.Arr_Sha_Info = null then
               Translate_Predefined_Array_Shift (Subprg);
               Infos.Arr_Sha_Info := Get_Info (Subprg);
            else
               Set_Info (Subprg, Infos.Arr_Sha_Info);
            end if;

         when Iir_Predefined_Array_Rol
            | Iir_Predefined_Array_Ror =>
            if Infos.Arr_Rot_Info = null then
               Translate_Predefined_Array_Shift (Subprg);
               Infos.Arr_Rot_Info := Get_Info (Subprg);
            else
               Set_Info (Subprg, Infos.Arr_Rot_Info);
            end if;

         when Iir_Predefined_Access_Equality
            | Iir_Predefined_Access_Inequality =>
            --  Intrinsic.
            null;
         when Iir_Predefined_Deallocate =>
            --  Intrinsic.
            null;

         when Iir_Predefined_File_Open
            | Iir_Predefined_File_Open_Status
            | Iir_Predefined_File_Close
            | Iir_Predefined_Flush
            | Iir_Predefined_Endfile =>
            --  All of them have predefined definitions.
            null;

         when Iir_Predefined_Write
            | Iir_Predefined_Read_Length
            | Iir_Predefined_Read =>
            declare
               Param     : Iir;
               File_Type : Iir;
            begin
               Param := Get_Interface_Declaration_Chain (Subprg);
               File_Type := Get_Type (Param);
               if not Get_Text_File_Flag (File_Type) then
                  Translate_File_Subprogram (Subprg, File_Type);
               end if;
            end;

         when Iir_Predefined_Attribute_Image
            | Iir_Predefined_Attribute_Value
            | Iir_Predefined_Attribute_Pos
            | Iir_Predefined_Attribute_Val
            | Iir_Predefined_Attribute_Succ
            | Iir_Predefined_Attribute_Pred
            | Iir_Predefined_Attribute_Leftof
            | Iir_Predefined_Attribute_Rightof
            | Iir_Predefined_Attribute_Left
            | Iir_Predefined_Attribute_Right
            | Iir_Predefined_Attribute_Event
            | Iir_Predefined_Attribute_Active
            | Iir_Predefined_Attribute_Last_Event
            | Iir_Predefined_Attribute_Last_Active
            | Iir_Predefined_Attribute_Last_Value
            | Iir_Predefined_Attribute_Driving
            | Iir_Predefined_Attribute_Driving_Value =>
            raise Internal_Error;

         when Iir_Predefined_Array_Char_To_String
            | Iir_Predefined_Bit_Vector_To_Ostring
            | Iir_Predefined_Bit_Vector_To_Hstring
            | Iir_Predefined_Std_Ulogic_Match_Equality
            | Iir_Predefined_Std_Ulogic_Match_Inequality
            | Iir_Predefined_Std_Ulogic_Match_Less
            | Iir_Predefined_Std_Ulogic_Match_Less_Equal
            | Iir_Predefined_Std_Ulogic_Match_Greater
            | Iir_Predefined_Std_Ulogic_Match_Greater_Equal
            | Iir_Predefined_Std_Ulogic_Array_Match_Equality
            | Iir_Predefined_Std_Ulogic_Array_Match_Inequality =>
            null;

         when Iir_Predefined_Now_Function =>
            null;

            --  when others =>
            --     Error_Kind ("translate_implicit_subprogram ("
            --                 & Iir_Predefined_Functions'Image (Kind) & ")",
            --                 Subprg);
      end case;
   end Translate_Implicit_Subprogram;
end Trans.Chap7;