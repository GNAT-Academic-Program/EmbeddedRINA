with Buffers; use Buffers;
with Ada.Containers.Vectors;
with IPCP_Manager; use IPCP_Manager; use IPCP_Manager.IPCP_Name;

package DIF_Manager is
   --  Max of 16 DIFs can exist in the system
   MAX_DIF_COUNT        : constant Natural := 16;

   --  Max of 8 IPCs can be registered to a DIF
   MAX_IPC_COUNT        : constant Natural := 8;

   type IPCP_Array is array (Natural range <>) of IPCP;

   type DIF_Types is (Normal, Ethernet);

   type DIF is tagged record
      Name     : Bounded_String;
      DIF_Type : DIF_Types := Normal;
      IPCPs    : IPCP_Vector;
      IPCP_Count : Natural := 0;
   end record;

   type DIF_Access is access all DIF;

   --  Enrollment is the procedure by which an IPCP joins an existing DIF and is initialized
   --  with enough information to become a fully operational DIF member. 
   procedure Enroll (Self : in out DIF; IPC_Process : IPCP); -- Flow_Req : Flow);

   function Get_IPCP (Name : String) return IPCP;
   function IPCP_Exists (Name : String) return Boolean;

   --  Checks the set of all DIFs in the system for a DIF with the matching name and type
   function Get (Name : String; DIF_Type : DIF_Types) return DIF;

   --  MT: TODO: Implement these
   function Create (Name : String; DIF_Type : DIF_Types) return DIF_Access;
   procedure Register (Appl_Name : String; DIF_Name : String; IO_Buf : access Byte_Buffer) is null;

   --  Stores all DIFs in the system
   package DIF_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive,
      Element_Type => DIF_Access);

   subtype DIF_Vector is DIF_Vectors.Vector;

   DIF_List : DIF_Vector;
end DIF_Manager;
