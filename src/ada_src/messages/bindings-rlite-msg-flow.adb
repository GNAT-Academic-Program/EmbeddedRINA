--  Temp disabling
pragma Style_Checks (Off);

with Names;
  use Names;

with Exceptions;

package body Bindings.Rlite.Msg.Flow is

   procedure Deserialize (Self : in out Request; fd : OS.File_Descriptor) is
   begin
      raise Exceptions.Not_Implemented_Exception;
   end Deserialize;

   function Serialize (Self : in Request) return Byte_Buffer is
      Hdr_Ptr        : constant Byte_Buffer(1 .. Self.Hdr'Size / 8)
                        with Address => Self.Hdr'Address, Import, Volatile;

      Flow_Spec      : constant Byte_Buffer(1 .. Self.Flow_Spec'Size / 8)
                        with Address => Self.Flow_Spec'Address, Import, Volatile;

      Upper_Ipcp_Id  : constant Byte_Buffer(1 .. Self.Upper_Ipcp_Id'Size / 8)
                        with Address => Self.Upper_Ipcp_Id'Address, Import, Volatile;

      Local_Port     : constant Byte_Buffer(1 .. Self.Local_Port'Size / 8)
                        with Address => Self.Local_Port'Address, Import, Volatile;
         
      Local_Cep      : constant Byte_Buffer(1 .. Self.Local_Cep'Size / 8)
                        with Address => Self.Local_Cep'Address, Import, Volatile;

      Uid            : constant Byte_Buffer(1 .. Self.Uid'Size / 8)
                        with Address => Self.Uid'Address, Import, Volatile;
                     
      Cookie         : constant Byte_Buffer(1 .. Self.Cookie'Size / 8)
                        with Address => Self.Cookie'Address, Import, Volatile;

      Local_Appl_Size : constant Unsigned_16 := Unsigned_16 (Used_Size (Self.Local_Appl));

      Local_Appl_Size_Ptr : constant Byte_Buffer(1 .. Local_Appl_Size'Size / 8)
                           with Address => Local_Appl_Size'Address, Import, Volatile;

      Local_Appl_Ptr   : constant Byte_Buffer := To_Packed_Buffer (Self.Local_Appl);

      Remote_Appl_Size : constant Unsigned_16 := Unsigned_16 (Used_Size (Self.Remote_Appl));

      Remote_Appl_Size_Ptr : constant Byte_Buffer(1 .. Remote_Appl_Size'Size / 8)
                           with Address => Remote_Appl_Size'Address, Import, Volatile;

      Remote_Appl_Ptr   : constant Byte_Buffer := To_Packed_Buffer (Self.Remote_Appl);

      DIF_Name_Size : constant Unsigned_16 := Unsigned_16 (Used_Size (Self.Dif_Name));

      DIF_Name_Size_Ptr : constant Byte_Buffer(1 .. DIF_Name_Size'Size / 8)
                           with Address => DIF_Name_Size'Address, Import, Volatile;

      DIF_Name_Ptr   : constant Byte_Buffer := To_Packed_Buffer (Self.Dif_Name);

      Serialized_Msg : constant Byte_Buffer := Hdr_Ptr & Flow_Spec & Upper_Ipcp_Id & Local_Port & Local_Cep & Uid & Cookie & Local_Appl_Size_Ptr & Local_Appl_Ptr & Remote_Appl_Size_Ptr & Remote_Appl_Ptr & DIF_Name_Size_Ptr & DIF_Name_Ptr;
   begin
      return Serialized_Msg;
   end Serialize;

   procedure Deserialize (Self : in out Response_Arrived; fd : OS.File_Descriptor) is
   begin
      raise Exceptions.Not_Implemented_Exception;
   end Deserialize;

   function Serialize (Self : Response_Arrived) return Byte_Buffer is
      Buf : constant Byte_Buffer(0 .. 128) := (others => 0);
   begin
      return Buf;
   end Serialize;

   procedure Deserialize (Self : in out Response; fd : OS.File_Descriptor) is
      Buffer   : constant Byte_Buffer := Read_Next_Msg(fd);
      Msg_Data : constant Byte_Buffer := Buffer(Rl_Msg_Hdr'Size / 8 .. Buffer'Size / 8);
   begin
      --  Byte buffer must not include any tagged record parts. This assumes
      --  byte_buffer is coming from C struct read from FD and not Ada!
      Self.Hdr := Buffer_To_Rl_Msg_Hdr (Buffer (1 .. Rl_Msg_Hdr'Size / 8));

      --  We are processing the wrong message
      if Self.Hdr.Msg_Type /= RLITE_KER_FA_REQ_ARRIVED then
         return;
      end if;

      --  [===== HDR =====][==== KeventId ====][== PortId ==][== IpcpId ==][===== FlowSpec =====][= Local_Appl_Size =][======= Local_Appl =======][= Remote_Appl_Size =][======= Remote_Appl =======][= Dif_Name_Size =][======= Dif_Name =======]
      Self.Kevent_Id    := Buffer_To_Unsigned_32 (Buffer_Reverse (Msg_Data (Msg_Data'First .. Msg_Data'First + 3)));
      Self.Port_Id      := Rl_Port_T (Buffer_To_Unsigned_16 (Buffer_Reverse (Msg_Data (Msg_Data'First + 3 .. Msg_Data'First + 4))));
      Self.Ipcp_Id      := Rl_Ipcp_Id_T (Buffer_To_Unsigned_16 (Buffer_Reverse (Msg_Data (Msg_Data'First + 4 .. Msg_Data'First + 5))));
      
      --  Appl_Name decoding
      --declare
         --  Fix endianness of bytes
      --   Name_Buffer : constant Byte_Buffer := Buffer_Reverse (Msg_Data (Msg_Data'First + 8 .. Msg_Data'First + 9));

         --  Covert these bytes to a 16-bit u16
      --   Name_Length : constant Unsigned_16 := Buffer_To_Unsigned_16 (Name_Buffer);

         --  Now we know the length of the Appl_Name string, pull it out of the buffer
      --   Name : constant String := Buffer_To_String (Msg_Data (Msg_Data'First + 11 .. Msg_Data'First + 11 + Integer (Name_Length)));
      --begin
         --  Convert pulled string into a bounded one for use the response object
      --   resp.Appl_Name := To_Bounded_String (Name);
      --end;
   end Deserialize;

   function Serialize (Self : Response) return Byte_Buffer is
      Buf : constant Byte_Buffer(0 .. 128) := (others => 0);
   begin
      return Buf;
   end Serialize;

   procedure Deserialize (Self : in out Request_Arrived; fd : OS.File_Descriptor) is
   begin
      raise Exceptions.Not_Implemented_Exception;
   end Deserialize;

   function Serialize (Self : Request_Arrived) return Byte_Buffer is
      Buf : constant Byte_Buffer(0 .. 128) := (others => 0);
   begin
      return Buf;
   end Serialize;

end Bindings.Rlite.Msg.Flow;