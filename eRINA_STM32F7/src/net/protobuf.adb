--  This package exists to support Protobuf encoded
--  messages such as the CDAP ones coming from rLite
--  https://protobuf.dev/programming-guides/encoding/
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Unchecked_Conversion;

package body Protobuf is
   use type Ada.Containers.Count_Type;

   function Bit_Array_To_Uint64 is
     new Ada.Unchecked_Conversion (Source => Bit_Array, Target => Uint64);

   function Has_MSB (Input : Byte) return Boolean is
      Result : constant Byte := input and 2#1000_0000#;
   begin
      return (Result = 128);
   end Has_MSB;
   
   function Get_Bit_At (Input : Byte; Pos : Natural) return Bit is
      Shifted : constant Byte := Shift_Right(Input, Pos) and 2#0000_0001#;
   begin
      return Bit (Shifted);
   end Get_Bit_At;

   function Tag_To_Wire_Type (Input : Byte) return Wire is
      Wire_Type_Num : constant Byte := Input and 2#0000_0111#;
   begin
      case Wire_Type_Num is
         when 0 =>
            return VARINT;
         when 1 =>
            return I64;
         when 2 =>
            return LEN;
         when 3 =>
            return SGROUP;
         when 4 =>
            return EGROUP;
         when 5 =>
            return I32;
         when others =>
            raise Constraint_Error with "Invalid wire type";
      end case;
   end Tag_To_Wire_Type;

   function Tag_To_Field_Number (Input : Byte) return CDAP_Field is
      --  Drop most significant bit and shift right 3 times
      Value : constant Byte := Shift_Right (Input and 2#0111_1111#, 3);
   begin
      --  MT: TODO: Debug only! Remove Me!
      Put_Line ("Decoded tagged field :: " & CDAP_Field'Enum_Val (Value)'Image);

      --  MT: TODO: Need to handle weird case when resulting value does not match an enum in CDAP_Field
      return CDAP_Field'Enum_Val (Value);
   end Tag_To_Field_Number;

   function To_VARINT (V : in Byte_Vector) return Uint64 is
      Working_Byte_Vector : Byte_Vector;
      Working_Bit_Array : Bit_Array(1 .. 64) := (others => 0);
      Result : Uint64 := 0;

      procedure Remove_MSB (C : Byte_Cursor) is
         MSB_Removed : constant Byte := V (C) and 2#0111_1111#;
      begin
         Working_Byte_Vector.Append (MSB_Removed);
      end Remove_MSB;

   begin
      --  MT: TODO: dropping this requirement for now
      --  Note we are checking vector capacity (max elements), not length (total elements)
      --  if Capacity (V) /= 10 then
      --     raise Constraint_Error with "Invalid VARINT vector capacity";
      --  end if;

      --  This is a good indicator something went horribly wrong or the packet is malformed
      if Byte_Vectors.Length (V) > 10 or Byte_Vectors.Length (V) < 1 then
         raise Constraint_Error with "Invalid VARINT vector length";
      end if;

      --  Flip endianness and drop the MSB of each byte
      --  The MSB is just there to tell us whether we've reached the end of the number
      --  V.Reverse_Iterate (Process => Remove_MSB'Access);

      --  For each byte
      for I in V.First_Index .. V.Last_Index loop
         --  For each bit in this byte, note 1 .. 7 and not 1 .. 8, we ignore the MSB
         for J in 1 .. 7 loop
            Working_Bit_Array((I - V.First_Index) * 7 + J) := Get_Bit_At (V(I), J - 1);
         end loop;
      end loop;
      
      --  MT: TODO: Debug only! Remove Me!
      Put_Line ("Decoded VARINT to be :: " & Uint64'Image(Bit_Array_To_Uint64 (Working_Bit_Array)));

      --  MT: TODO: May need some idiot proofing
      return Bit_Array_To_Uint64 (Working_Bit_Array);
   end To_VARINT;

   function To_CDAP(V : in Byte_Vector) return CDAPMessage is
      Result_Msg : CDAPMessage;
      Wire_Type : Wire;
      Field_Id : CDAP_Field;
      Is_Tag_Field : Boolean := True;

      --  Using a cursor here instead of an iterative loop so we can skip elements
      C : Byte_Vectors.Cursor := V.First;
      use type Byte_Vectors.Cursor;
   begin
      while C /= Byte_Vectors.No_Element loop
         if Is_Tag_Field then
            Wire_Type := Tag_To_Wire_Type (V(C));
            Field_Id := Tag_To_Field_Number (V(C));
            Is_Tag_Field := False;
         else
            if Wire_Type = VARINT then
               declare
                  VARINT_Vector : Byte_Vector;
               begin
                  --  Keep reading bytes until we no longer have a MSB of 1
                  while C /= Byte_Vectors.No_Element loop
                     VARINT_Vector.Append (V(C));
                     exit when (not Has_MSB (V(C)));
                     C := Byte_Vectors.Next (C);
                  end loop;

                  --  Decode and update message
                  Result_Msg.Set_Field (Field_Id, To_VARINT (VARINT_Vector));
               end;
            end if;

            --  LEN can be a string, embedded messages, packed repeated fields, or even just an array of bytes
            --  For our purposes we always return a vector of bytes, then let the known tag field dictate what this
            --  should turn into...
            if Wire_Type = LEN then
               declare
                  LEN_Vector : Byte_Vector;
                  Data_Vector : Byte_Vector;
                  LEN_Length : Natural := 0;
                  LEN_Iterator : Natural := 0;
               begin
                  while C /= Byte_Vectors.No_Element loop
                     LEN_Vector.Append (V(C));
                     C := Byte_Vectors.Next (C);
                     exit when (not Has_MSB (V(C)));
                  end loop;

                  --  The VARINT storing the length is an int32
                  LEN_Length := Natural (To_VARINT (LEN_Vector));
                  Put_Line ("Found LEN with length: " & LEN_Length'Image);

                  while C /= Byte_Vectors.No_Element loop
                     Data_Vector.Append (V(C));
                     LEN_Iterator := LEN_Iterator + 1;
                     exit when (LEN_Iterator = LEN_Length);
                     C := Byte_Vectors.Next (C);
                  end loop;

                  Put_Line ("Decoded LEN of size (" & LEN_Length'Image & ") to be :: " & Buffer_To_String (Byte_Vector_To_Buffer (Data_Vector)));
                  Result_Msg.Set_Field (Field_Id, Byte_Vector_To_Buffer (Data_Vector));
               end;
            end if;

            --  Next field will be a tag field
            Is_Tag_Field := True;
         end if;

         C := Byte_Vectors.Next (C);
      end loop;

      return Result_Msg;
   end To_CDAP;
end Protobuf;
