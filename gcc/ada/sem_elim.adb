------------------------------------------------------------------------------
--                                                                          --
--                         GNAT COMPILER COMPONENTS                         --
--                                                                          --
--                             S E M _ E L I M                              --
--                                                                          --
--                                 B o d y                                  --
--                                                                          --
--          Copyright (C) 1997-2004 Free Software Foundation, Inc.          --
--                                                                          --
-- GNAT is free software;  you can  redistribute it  and/or modify it under --
-- terms of the  GNU General Public License as published  by the Free Soft- --
-- ware  Foundation;  either version 2,  or (at your option) any later ver- --
-- sion.  GNAT is distributed in the hope that it will be useful, but WITH- --
-- OUT ANY WARRANTY;  without even the  implied warranty of MERCHANTABILITY --
-- or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License --
-- for  more details.  You should have  received  a copy of the GNU General --
-- Public License  distributed with GNAT;  see file COPYING.  If not, write --
-- to  the Free Software Foundation,  59 Temple Place - Suite 330,  Boston, --
-- MA 02111-1307, USA.                                                      --
--                                                                          --
-- GNAT was originally developed  by the GNAT team at  New York University. --
-- Extensive contributions were provided by Ada Core Technologies Inc.      --
--                                                                          --
------------------------------------------------------------------------------

with Atree;   use Atree;
with Einfo;   use Einfo;
with Errout;  use Errout;
with Namet;   use Namet;
with Nlists;  use Nlists;
with Sinput;  use Sinput;
with Sinfo;   use Sinfo;
with Snames;  use Snames;
with Stand;   use Stand;
with Stringt; use Stringt;
with Table;

with GNAT.HTable; use GNAT.HTable;
package body Sem_Elim is

   No_Elimination : Boolean;
   --  Set True if no Eliminate pragmas active

   ---------------------
   -- Data Structures --
   ---------------------

   --  A single pragma Eliminate is represented by the following record

   type Elim_Data;
   type Access_Elim_Data is access Elim_Data;

   type Names is array (Nat range <>) of Name_Id;
   --  Type used to represent set of names. Used for names in Unit_Name
   --  and also the set of names in Argument_Types.

   type Access_Names is access Names;

   type Elim_Data is record

      Unit_Name : Access_Names;
      --  Unit name, broken down into a set of names (e.g. A.B.C is
      --  represented as Name_Id values for A, B, C in sequence).

      Entity_Name : Name_Id;
      --  Entity name if Entity parameter if present. If no Entity parameter
      --  was supplied, then Entity_Node is set to Empty, and the Entity_Name
      --  field contains the last identifier name in the Unit_Name.

      Entity_Scope : Access_Names;
      --  Static scope of the entity within the compilation unit represented by
      --  Unit_Name.

      Entity_Node : Node_Id;
      --  Save node of entity argument, for posting error messages. Set
      --  to Empty if there is no entity argument.

      Parameter_Types : Access_Names;
      --  Set to set of names given for parameter types. If no parameter
      --  types argument is present, this argument is set to null.

      Result_Type : Name_Id;
      --  Result type name if Result_Types parameter present, No_Name if not

      Source_Location : Name_Id;
      --  String describing the source location of subprogram defining name if
      --  Source_Location parameter present, No_Name if not

      Hash_Link : Access_Elim_Data;
      --  Link for hash table use

      Homonym : Access_Elim_Data;
      --  Pointer to next entry with same key

      Prag : Node_Id;
      --  Node_Id for Eliminate pragma

   end record;

   ----------------
   -- Hash_Table --
   ----------------

   --  Setup hash table using the Entity_Name field as the hash key

   subtype Element is Elim_Data;
   subtype Elmt_Ptr is Access_Elim_Data;

   subtype Key is Name_Id;

   type Header_Num is range 0 .. 1023;

   Null_Ptr : constant Elmt_Ptr := null;

   ----------------------
   -- Hash_Subprograms --
   ----------------------

   package Hash_Subprograms is

      function Equal (F1, F2 : Key) return Boolean;
      pragma Inline (Equal);

      function Get_Key (E : Elmt_Ptr) return Key;
      pragma Inline (Get_Key);

      function Hash (F : Key) return Header_Num;
      pragma Inline (Hash);

      function Next (E : Elmt_Ptr) return Elmt_Ptr;
      pragma Inline (Next);

      procedure Set_Next (E : Elmt_Ptr; Next : Elmt_Ptr);
      pragma Inline (Set_Next);

   end Hash_Subprograms;

   package body Hash_Subprograms is

      -----------
      -- Equal --
      -----------

      function Equal (F1, F2 : Key) return Boolean is
      begin
         return F1 = F2;
      end Equal;

      -------------
      -- Get_Key --
      -------------

      function Get_Key (E : Elmt_Ptr) return Key is
      begin
         return E.Entity_Name;
      end Get_Key;

      ----------
      -- Hash --
      ----------

      function Hash (F : Key) return Header_Num is
      begin
         return Header_Num (Int (F) mod 1024);
      end Hash;

      ----------
      -- Next --
      ----------

      function Next (E : Elmt_Ptr) return Elmt_Ptr is
      begin
         return E.Hash_Link;
      end Next;

      --------------
      -- Set_Next --
      --------------

      procedure Set_Next (E : Elmt_Ptr; Next : Elmt_Ptr) is
      begin
         E.Hash_Link := Next;
      end Set_Next;
   end Hash_Subprograms;

   ------------
   -- Tables --
   ------------

   --  The following table records the data for each pragmas, using the
   --  entity name as the hash key for retrieval. Entries in this table
   --  are set by Process_Eliminate_Pragma and read by Check_Eliminated.

   package Elim_Hash_Table is new Static_HTable (
      Header_Num => Header_Num,
      Element    => Element,
      Elmt_Ptr   => Elmt_Ptr,
      Null_Ptr   => Null_Ptr,
      Set_Next   => Hash_Subprograms.Set_Next,
      Next       => Hash_Subprograms.Next,
      Key        => Key,
      Get_Key    => Hash_Subprograms.Get_Key,
      Hash       => Hash_Subprograms.Hash,
      Equal      => Hash_Subprograms.Equal);

   --  The following table records entities for subprograms that are
   --  eliminated, and corresponding eliminate pragmas that caused the
   --  elimination. Entries in this table are set by Check_Eliminated
   --  and read by Eliminate_Error_Msg.

   type Elim_Entity_Entry is record
      Prag : Node_Id;
      Subp : Entity_Id;
   end record;

   package Elim_Entities is new Table.Table (
     Table_Component_Type => Elim_Entity_Entry,
     Table_Index_Type     => Name_Id,
     Table_Low_Bound      => First_Name_Id,
     Table_Initial        => 50,
     Table_Increment      => 200,
     Table_Name           => "Elim_Entries");

   ----------------------
   -- Check_Eliminated --
   ----------------------

   procedure Check_Eliminated (E : Entity_Id) is
      Elmt : Access_Elim_Data;
      Scop : Entity_Id;
      Form : Entity_Id;

      function Original_Chars (S : Entity_Id) return Name_Id;
      --  If the candidate subprogram is a protected operation of a single
      --  protected object, the scope of the operation is the created
      --  protected type, and we have to retrieve the original name of
      --  the object.

      --------------------
      -- Original_Chars --
      --------------------

      function Original_Chars (S : Entity_Id) return Name_Id is
      begin
         if Ekind (S) /= E_Protected_Type
           or else Comes_From_Source (S)
         then
            return Chars (S);
         else
            return Chars (Defining_Identifier (Original_Node (Parent (S))));
         end if;
      end Original_Chars;

   --  Start of processing for Check_Eliminated

   begin
      if No_Elimination then
         return;

      --  Elimination of objects and types is not implemented yet

      elsif Ekind (E) not in Subprogram_Kind then
         return;
      end if;

      --  Loop through homonyms for this key

      Elmt := Elim_Hash_Table.Get (Chars (E));
      while Elmt /= null loop
         declare
            procedure Set_Eliminated;
            --  Set current subprogram entity as eliminated

            procedure Set_Eliminated is
            begin
               Set_Is_Eliminated (E);
               Elim_Entities.Append ((Prag => Elmt.Prag, Subp => E));
            end Set_Eliminated;

         begin
            --  First we check that the name of the entity matches

            if Elmt.Entity_Name /= Chars (E) then
               goto Continue;
            end if;

            --  Then we need to see if the static scope matches within the
            --  compilation unit.

            --  At the moment, gnatelim does not consider block statements as
            --  scopes (even if a block is named)

            Scop := Scope (E);
            while Ekind (Scop) = E_Block loop
               Scop := Scope (Scop);
            end loop;

            if Elmt.Entity_Scope /= null then
               for J in reverse Elmt.Entity_Scope'Range loop
                  if Elmt.Entity_Scope (J) /= Original_Chars (Scop) then
                     goto Continue;
                  end if;

                  Scop := Scope (Scop);
                  while Ekind (Scop) = E_Block loop
                     Scop := Scope (Scop);
                  end loop;

                  if not Is_Compilation_Unit (Scop) and then J = 1 then
                     goto Continue;
                  end if;
               end loop;
            end if;

            --  Now see if compilation unit matches

            for J in reverse Elmt.Unit_Name'Range loop
               if Elmt.Unit_Name (J) /= Chars (Scop) then
                  goto Continue;
               end if;

               Scop := Scope (Scop);
               while Ekind (Scop) = E_Block loop
                  Scop := Scope (Scop);
               end loop;

               if Scop /= Standard_Standard and then J = 1 then
                  goto Continue;
               end if;
            end loop;

            if Scop /= Standard_Standard then
               goto Continue;
            end if;

            --  Check for case of given entity is a library level subprogram
            --  and we have the single parameter Eliminate case, a match!

            if Is_Compilation_Unit (E)
              and then Is_Subprogram (E)
              and then No (Elmt.Entity_Node)
            then
               Set_Eliminated;
               return;

               --  Check for case of type or object with two parameter case

            elsif (Is_Type (E) or else Is_Object (E))
              and then Elmt.Result_Type = No_Name
              and then Elmt.Parameter_Types = null
            then
               Set_Eliminated;
               return;

            --  Check for case of subprogram

            elsif Ekind (E) = E_Function
              or else Ekind (E) = E_Procedure
            then
               --  If Source_Location present, then see if it matches

               if Elmt.Source_Location /= No_Name then
                  Get_Name_String (Elmt.Source_Location);

                  declare
                     Sloc_Trace : constant String :=
                                    Name_Buffer (1 .. Name_Len);

                     Idx : Natural := Sloc_Trace'First;
                     --  Index in Sloc_Trace, if equals to 0, then we have
                     --  completely traversed Sloc_Trace

                     Last : constant Natural := Sloc_Trace'Last;

                     P      : Source_Ptr;
                     Sindex : Source_File_Index;

                     function File_Mame_Match return Boolean;
                     --  This function is supposed to be called when Idx points
                     --  to the beginning of the new file name, and Name_Buffer
                     --  is set to contain the name of the proper source file
                     --  from the chain corresponding to the Sloc of E. First
                     --  it checks that these two files have the same name. If
                     --  this check is successful, moves Idx to point to the
                     --  beginning of the column number.

                     function Line_Num_Match return Boolean;
                     --  This function is supposed to be called when Idx points
                     --  to the beginning of the column number, and P is
                     --  set to point to the proper Sloc the chain
                     --  corresponding to the Sloc of E. First it checks that
                     --  the line number Idx points on and the line number
                     --  corresponding to P are the same. If this check is
                     --  successful, moves Idx to point to the beginning of
                     --  the next file name in Sloc_Trace. If there is no file
                     --  name any more, Idx is set to 0.

                     function Different_Trace_Lengths return Boolean;
                     --  From Idx and P, defines if there are in both traces
                     --  more element(s) in the instantiation chains. Returns
                     --  False if one trace contains more element(s), but
                     --  another does not. If both traces contains more
                     --  elements (that is, the function returns False), moves
                     --  P ahead in the chain corresponding to E, recomputes
                     --  Sindex and sets the name of the corresponding file in
                     --  Name_Buffer

                     function Skip_Spaces return Natural;
                     --  If Sloc_Trace (Idx) is not space character, returns
                     --  Idx. Otherwise returns the index of the nearest
                     --  non-space character in Sloc_Trace to the right of
                     --  Idx. Returns 0 if there is no such character.

                     -----------------------------
                     -- Different_Trace_Lengths --
                     -----------------------------

                     function Different_Trace_Lengths return Boolean is
                     begin
                        P := Instantiation (Sindex);

                        if (P = No_Location and then Idx /= 0)
                          or else
                           (P /= No_Location and then Idx = 0)
                        then
                           return True;

                        else
                           if P /= No_Location then
                              Sindex := Get_Source_File_Index (P);
                              Get_Name_String (File_Name (Sindex));
                           end if;

                           return False;
                        end if;
                     end Different_Trace_Lengths;

                     function File_Mame_Match return Boolean is
                        Tmp_Idx : Positive := 1;
                        End_Idx : Positive := 1;
                        --  Initializations are to stop warnings

                        --  But are warnings possibly valid ???
                        --  Why are loops below guaranteed to exit ???

                     begin
                        if Idx = 0 then
                           return False;
                        end if;

                        for J in Idx .. Last loop
                           if Sloc_Trace (J) = ':' then
                              Tmp_Idx := J - 1;
                              exit;
                           end if;
                        end loop;

                        for J in reverse Idx .. Tmp_Idx loop
                           if Sloc_Trace (J) /= ' ' then
                              End_Idx := J;
                              exit;
                           end if;
                        end loop;

                        if Sloc_Trace (Idx .. End_Idx) =
                           Name_Buffer (1 .. Name_Len)
                        then
                           Idx := Tmp_Idx + 2;

                           Idx := Skip_Spaces;

                           return True;
                        else
                           return False;
                        end if;
                     end File_Mame_Match;

                     --------------------
                     -- Line_Num_Match --
                     --------------------

                     function Line_Num_Match return Boolean is
                        N : Int := 0;

                     begin
                        if Idx = 0 then
                           return False;
                        end if;

                        while Idx <= Last
                           and then Sloc_Trace (Idx) in '0' .. '9'
                        loop
                           N := N * 10 +
                            (Character'Pos (Sloc_Trace (Idx)) -
                             Character'Pos ('0'));
                           Idx := Idx + 1;
                        end loop;

                        if Get_Physical_Line_Number (P) =
                           Physical_Line_Number (N)
                        then
                           while Sloc_Trace (Idx) /= '['
                               and then Idx <= Last
                           loop
                              Idx := Idx + 1;
                           end loop;

                           if Sloc_Trace (Idx) = '['
                             and then Idx < Last
                           then
                              Idx := Idx + 1;
                              Idx := Skip_Spaces;
                           else
                              Idx := 0;
                           end if;

                           return True;
                        else
                           return False;
                        end if;
                     end Line_Num_Match;

                     -----------------
                     -- Skip_Spaces --
                     -----------------

                     function Skip_Spaces return Natural is
                        Res : Natural := Idx;

                     begin
                        while Sloc_Trace (Res) = ' ' loop
                           Res := Res + 1;

                           if Res > Last then
                              Res := 0;
                              exit;
                           end if;
                        end loop;

                        return Res;
                     end Skip_Spaces;

                  begin
                     P := Sloc (E);
                     Sindex := Get_Source_File_Index (P);
                     Get_Name_String (File_Name (Sindex));

                     Idx := Skip_Spaces;
                     while Idx > 0 loop
                        if not File_Mame_Match then
                           goto Continue;
                        elsif not Line_Num_Match then
                           goto Continue;
                        end if;

                        if Different_Trace_Lengths then
                           goto Continue;
                        end if;
                     end loop;
                  end;
               end if;

               --  If we have a Result_Type, then we must have a function
               --  with the proper result type

               if Elmt.Result_Type /= No_Name then
                  if Ekind (E) /= E_Function
                    or else Chars (Etype (E)) /= Elmt.Result_Type
                  then
                     goto Continue;
                  end if;
               end if;

               --  If we have Parameter_Types, they must match

               if Elmt.Parameter_Types /= null then
                  Form := First_Formal (E);

                  if No (Form)
                    and then Elmt.Parameter_Types'Length = 1
                    and then Elmt.Parameter_Types (1) = No_Name
                  then
                     --  Parameterless procedure matches

                     null;

                  elsif Elmt.Parameter_Types = null then
                     goto Continue;

                  else
                     for J in Elmt.Parameter_Types'Range loop
                        if No (Form)
                          or else
                            Chars (Etype (Form)) /= Elmt.Parameter_Types (J)
                        then
                           goto Continue;
                        else
                           Next_Formal (Form);
                        end if;
                     end loop;

                     if Present (Form) then
                        goto Continue;
                     end if;
                  end if;
               end if;

               --  If we fall through, this is match

               Set_Eliminated;
               return;
            end if;
         end;

      <<Continue>>
         Elmt := Elmt.Homonym;
      end loop;

      return;
   end Check_Eliminated;

   -------------------------
   -- Eliminate_Error_Msg --
   -------------------------

   procedure Eliminate_Error_Msg (N : Node_Id; E : Entity_Id) is
   begin
      for J in Elim_Entities.First .. Elim_Entities.Last loop
         if E = Elim_Entities.Table (J).Subp then
            Error_Msg_Sloc := Sloc (Elim_Entities.Table (J).Prag);
            Error_Msg_NE ("cannot call subprogram & eliminated #", N, E);
            return;
         end if;
      end loop;

      --  Should never fall through, since entry should be in table

      pragma Assert (False);
   end Eliminate_Error_Msg;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize is
   begin
      Elim_Hash_Table.Reset;
      Elim_Entities.Init;
      No_Elimination := True;
   end Initialize;

   ------------------------------
   -- Process_Eliminate_Pragma --
   ------------------------------

   procedure Process_Eliminate_Pragma
     (Pragma_Node         : Node_Id;
      Arg_Unit_Name       : Node_Id;
      Arg_Entity          : Node_Id;
      Arg_Parameter_Types : Node_Id;
      Arg_Result_Type     : Node_Id;
      Arg_Source_Location : Node_Id)
   is
      Data : constant Access_Elim_Data := new Elim_Data;
      --  Build result data here

      Elmt : Access_Elim_Data;

      Num_Names : Nat := 0;
      --  Number of names in unit name

      Lit       : Node_Id;
      Arg_Ent   : Entity_Id;
      Arg_Uname : Node_Id;

      function OK_Selected_Component (N : Node_Id) return Boolean;
      --  Test if N is a selected component with all identifiers, or a
      --  selected component whose selector is an operator symbol. As a
      --  side effect if result is True, sets Num_Names to the number
      --  of names present (identifiers and operator if any).

      ---------------------------
      -- OK_Selected_Component --
      ---------------------------

      function OK_Selected_Component (N : Node_Id) return Boolean is
      begin
         if Nkind (N) = N_Identifier
           or else Nkind (N) = N_Operator_Symbol
         then
            Num_Names := Num_Names + 1;
            return True;

         elsif Nkind (N) = N_Selected_Component then
            return OK_Selected_Component (Prefix (N))
              and then OK_Selected_Component (Selector_Name (N));

         else
            return False;
         end if;
      end OK_Selected_Component;

   --  Start of processing for Process_Eliminate_Pragma

   begin
      Data.Prag := Pragma_Node;
      Error_Msg_Name_1 := Name_Eliminate;

      --  Process Unit_Name argument

      if Nkind (Arg_Unit_Name) = N_Identifier then
         Data.Unit_Name := new Names'(1 => Chars (Arg_Unit_Name));
         Num_Names := 1;

      elsif OK_Selected_Component (Arg_Unit_Name) then
         Data.Unit_Name := new Names (1 .. Num_Names);

         Arg_Uname := Arg_Unit_Name;
         for J in reverse 2 .. Num_Names loop
            Data.Unit_Name (J) := Chars (Selector_Name (Arg_Uname));
            Arg_Uname := Prefix (Arg_Uname);
         end loop;

         Data.Unit_Name (1) := Chars (Arg_Uname);

      else
         Error_Msg_N
           ("wrong form for Unit_Name parameter of pragma%", Arg_Unit_Name);
         return;
      end if;

      --  Process Entity argument

      if Present (Arg_Entity) then
         Num_Names := 0;

         if Nkind (Arg_Entity) = N_Identifier
           or else Nkind (Arg_Entity) = N_Operator_Symbol
         then
            Data.Entity_Name  := Chars (Arg_Entity);
            Data.Entity_Node  := Arg_Entity;
            Data.Entity_Scope := null;

         elsif OK_Selected_Component (Arg_Entity) then
            Data.Entity_Scope := new Names (1 .. Num_Names - 1);
            Data.Entity_Name  := Chars (Selector_Name (Arg_Entity));
            Data.Entity_Node  := Arg_Entity;

            Arg_Ent := Prefix (Arg_Entity);
            for J in reverse 2 .. Num_Names - 1 loop
               Data.Entity_Scope (J) := Chars (Selector_Name (Arg_Ent));
               Arg_Ent := Prefix (Arg_Ent);
            end loop;

            Data.Entity_Scope (1) := Chars (Arg_Ent);

         elsif Nkind (Arg_Entity) = N_String_Literal then
            String_To_Name_Buffer (Strval (Arg_Entity));
            Data.Entity_Name := Name_Find;
            Data.Entity_Node := Arg_Entity;

         else
            Error_Msg_N
              ("wrong form for Entity_Argument parameter of pragma%",
               Arg_Unit_Name);
            return;
         end if;
      else
         Data.Entity_Node := Empty;
         Data.Entity_Name := Data.Unit_Name (Num_Names);
      end if;

      --  Process Parameter_Types argument

      if Present (Arg_Parameter_Types) then

         --  Case of one name, which looks like a parenthesized literal
         --  rather than an aggregate.

         if Nkind (Arg_Parameter_Types) = N_String_Literal
           and then Paren_Count (Arg_Parameter_Types) = 1
         then
            String_To_Name_Buffer (Strval (Arg_Parameter_Types));

            if Name_Len = 0 then

               --  Parameterless procedure

               Data.Parameter_Types := new Names'(1 => No_Name);

            else
               Data.Parameter_Types := new Names'(1 => Name_Find);
            end if;

         --  Otherwise must be an aggregate

         elsif Nkind (Arg_Parameter_Types) /= N_Aggregate
           or else Present (Component_Associations (Arg_Parameter_Types))
           or else No (Expressions (Arg_Parameter_Types))
         then
            Error_Msg_N
              ("Parameter_Types for pragma% must be list of string literals",
               Arg_Parameter_Types);
            return;

         --  Here for aggregate case

         else
            Data.Parameter_Types :=
              new Names
                (1 .. List_Length (Expressions (Arg_Parameter_Types)));

            Lit := First (Expressions (Arg_Parameter_Types));
            for J in Data.Parameter_Types'Range loop
               if Nkind (Lit) /= N_String_Literal then
                  Error_Msg_N
                    ("parameter types for pragma% must be string literals",
                     Lit);
                  return;
               end if;

               String_To_Name_Buffer (Strval (Lit));
               Data.Parameter_Types (J) := Name_Find;
               Next (Lit);
            end loop;
         end if;
      end if;

      --  Process Result_Types argument

      if Present (Arg_Result_Type) then

         if Nkind (Arg_Result_Type) /= N_String_Literal then
            Error_Msg_N
              ("Result_Type argument for pragma% must be string literal",
               Arg_Result_Type);
            return;
         end if;

         String_To_Name_Buffer (Strval (Arg_Result_Type));
         Data.Result_Type := Name_Find;

      else
         Data.Result_Type := No_Name;
      end if;

      --  Process Source_Location argument

      if Present (Arg_Source_Location) then

         if Nkind (Arg_Source_Location) /= N_String_Literal then
            Error_Msg_N
              ("Source_Location argument for pragma% must be string literal",
               Arg_Source_Location);
            return;
         end if;

         String_To_Name_Buffer (Strval (Arg_Source_Location));
         Data.Source_Location := Name_Find;

      else
         Data.Source_Location := No_Name;
      end if;

      Elmt := Elim_Hash_Table.Get (Hash_Subprograms.Get_Key (Data));

      --  If we already have an entry with this same key, then link
      --  it into the chain of entries for this key.

      if Elmt /= null then
         Data.Homonym := Elmt.Homonym;
         Elmt.Homonym := Data;

      --  Otherwise create a new entry

      else
         Elim_Hash_Table.Set (Data);
      end if;

      No_Elimination := False;
   end Process_Eliminate_Pragma;

end Sem_Elim;
