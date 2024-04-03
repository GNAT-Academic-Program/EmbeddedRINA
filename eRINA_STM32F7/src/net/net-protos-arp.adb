-----------------------------------------------------------------------
--  net-protos-arp -- ARP Network protocol
--  Copyright (C) 2016 Stephane Carrez
--  Written by Stephane Carrez (Stephane.Carrez@gmail.com)
--
--  Licensed under the Apache License, Version 2.0 (the "License");
--  you may not use this file except in compliance with the License.
--  You may obtain a copy of the License at
--
--      http://www.apache.org/licenses/LICENSE-2.0
--
--  Unless required by applicable law or agreed to in writing, software
--  distributed under the License is distributed on an "AS IS" BASIS,
--  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--  See the License for the specific language governing permissions and
--  limitations under the License.
-----------------------------------------------------------------------
with Ada.Real_Time;
with Ada.Exceptions; use Ada.Exceptions;
with DIF_Manager;
with IPCP_Manager;
with Debug;

with Net.Headers;
package body Net.Protos.Arp is

   use type Ada.Real_Time.Time;

   Broadcast_Mac : constant Ether_Addr := (others => 16#ff#);

   Arp_Retry_Timeout : constant Ada.Real_Time.Time_Span :=
     Ada.Real_Time.Seconds (1);
   Arp_Entry_Timeout : constant Ada.Real_Time.Time_Span :=
     Ada.Real_Time.Seconds (30);
   Arp_Unreachable_Timeout : constant Ada.Real_Time.Time_Span :=
     Ada.Real_Time.Seconds (120);
   Arp_Stale_Timeout : constant Ada.Real_Time.Time_Span :=
     Ada.Real_Time.Seconds (120);

   --  The ARP table index uses the last byte of the IP address.  We assume our network is
   --  a /24 which means we can have 253 valid IP addresses (0 and 255 are excluded).
   subtype Arp_Index is Uint8 range 1 .. 254;

   --  Maximum number of ARP entries we can remember.  We could increase to 253 but most
   --  application will only send packets to a small number of hosts.
   ARP_MAX_ENTRIES : constant Positive := 32;

   --  Accept to queue at most 30 packets.
   QUEUE_LIMIT : constant Natural := 30;

   --  The maximum number of packets which can be queued for each entry.
   QUEUE_ENTRY_LIMIT : constant Uint8 := 3;

   ARP_MAX_RETRY : constant Positive := 15;

   type Arp_Entry;
   type Arp_Entry_Access is access all Arp_Entry;

   type Arp_Entry is record
      Ether       : Ether_Addr;
      Expire      : Ada.Real_Time.Time;
      Queue       : Net.Buffers.Buffer_List;
      Retry       : Natural   := 0;
      Index       : Arp_Index := Arp_Index'First;
      Queue_Size  : Uint8     := 0;
      Valid       : Boolean   := False;
      Unreachable : Boolean   := False;
      Pending     : Boolean   := False;
      Stale       : Boolean   := False;
      Free        : Boolean   := True;
   end record;

   type Arp_Entry_Table is array (1 .. ARP_MAX_ENTRIES) of aliased Arp_Entry;
   type Arp_Table is array (Arp_Index) of Arp_Entry_Access;
   type Arp_Refresh is array (1 .. ARP_MAX_ENTRIES) of Arp_Index;

   --  ARP database.
   --  To make it simple and avoid dynamic memory allocation, we maintain a maximum of 256
   --  entries which correspond to a class C network.  We only keep entries that are for our
   --  network.  The lookup is in O(1).
   protected Database is

      procedure Timeout
        (Ifnet   : in out Net.Interfaces.Ifnet_Type'Class;
         Refresh :    out Arp_Refresh; Count : out Natural);

      procedure Resolve
        (Ifnet  : in out Net.Interfaces.Ifnet_Type'Class; Ip : in Ip_Addr;
         Mac    :    out Ether_Addr; Packet : in out Net.Buffers.Buffer_Type;
         Result :    out Arp_Status);

      procedure Update
        (Ip   : in     Ip_Addr; Mac : in Ether_Addr;
         List :    out Net.Buffers.Buffer_List);

   private
      Entries    : Arp_Entry_Table;
      Table      : Arp_Table := (others => null);
      Queue_Size : Natural   := 0;
   end Database;

   protected body Database is

      procedure Drop_Queue
        (Ifnet : in out Net.Interfaces.Ifnet_Type'Class;
         Rt    : in     Arp_Entry_Access)
      is
         pragma Unreferenced (Ifnet);
      begin
         if Rt.Queue_Size > 0 then
            Queue_Size    := Queue_Size - Natural (Rt.Queue_Size);
            Rt.Queue_Size := 0;
            Net.Buffers.Release (Rt.Queue);
         end if;
      end Drop_Queue;

      procedure Timeout
        (Ifnet   : in out Net.Interfaces.Ifnet_Type'Class;
         Refresh :    out Arp_Refresh; Count : out Natural)
      is
         Now : constant Ada.Real_Time.Time := Ada.Real_Time.Clock;
      begin
         Count := 0;
         for I in Entries'Range loop
            if not Entries (I).Free and then Entries (I).Expire < Now then
               if Entries (I).Valid then
                  Entries (I).Valid  := False;
                  Entries (I).Stale  := True;
                  Entries (I).Expire := Now + Arp_Stale_Timeout;

               elsif Entries (I).Stale then
                  Entries (I).Free          := True;
                  Table (Entries (I).Index) := null;

               elsif Entries (I).Retry > 5 then
                  Entries (I).Unreachable := True;
                  Entries (I).Expire      := Now + Arp_Unreachable_Timeout;
                  Entries (I).Retry       := 0;
                  Drop_Queue (Ifnet, Entries (I)'Access);

               else
                  Count              := Count + 1;
                  Refresh (Count)    := Entries (I).Index;
                  Entries (I).Retry  := Entries (I).Retry + 1;
                  Entries (I).Expire := Now + Arp_Retry_Timeout;
               end if;
            end if;
         end loop;
      end Timeout;

      procedure Resolve
        (Ifnet  : in out Net.Interfaces.Ifnet_Type'Class; Ip : in Ip_Addr;
         Mac    :    out Ether_Addr; Packet : in out Net.Buffers.Buffer_Type;
         Result :    out Arp_Status)
      is
         Index : constant Arp_Index          := Ip (Ip'Last);
         Rt    : Arp_Entry_Access            := Table (Index);
         Now   : constant Ada.Real_Time.Time := Ada.Real_Time.Clock;
      begin
         if Rt = null then
            for I in Entries'Range loop
               if Entries (I).Free then
                  Rt            := Entries (I)'Access;
                  Rt.Free       := False;
                  Rt.Index      := Index;
                  Table (Index) := Rt;
                  exit;
               end if;
            end loop;
            if Rt = null then
               Result := ARP_QUEUE_FULL;
               return;
            end if;
         end if;
         if Rt.Valid and then Now < Rt.Expire then
            Mac    := Rt.Ether;
            Result := ARP_FOUND;

         elsif Rt.Unreachable and then Now < Rt.Expire then
            Result := ARP_UNREACHABLE;

            --  Send the first ARP request for the target IP resolution.
         elsif not Rt.Pending then
            Rt.Pending := True;
            Rt.Retry   := 1;
            Rt.Stale   := False;
            Rt.Expire  := Now + Arp_Retry_Timeout;
            Result     := ARP_NEEDED;

         elsif Rt.Expire < Now then
            if Rt.Retry > ARP_MAX_RETRY then
               Rt.Unreachable := True;
               Rt.Expire      := Now + Arp_Unreachable_Timeout;
               Rt.Pending     := False;
               Result         := ARP_UNREACHABLE;
               Drop_Queue (Ifnet, Rt);
            else
               Rt.Retry  := Rt.Retry + 1;
               Rt.Expire := Now + Arp_Retry_Timeout;
               Result    := ARP_NEEDED;
            end if;
         else
            Result := ARP_PENDING;
         end if;

         --  Queue the packet unless the queue is full.
         if (Result = ARP_PENDING or Result = ARP_NEEDED)
           and then not Packet.Is_Null
         then
            if Queue_Size < QUEUE_LIMIT and Rt.Queue_Size < QUEUE_ENTRY_LIMIT
            then
               Queue_Size := Queue_Size + 1;
               Net.Buffers.Insert (Rt.Queue, Packet);
               Rt.Queue_Size := Rt.Queue_Size + 1;
            else
               Result := ARP_QUEUE_FULL;
            end if;
         end if;
      end Resolve;

      procedure Update
        (Ip   : in     Ip_Addr; Mac : in Ether_Addr;
         List :    out Net.Buffers.Buffer_List)
      is
         Rt : constant Arp_Entry_Access := Table (Ip (Ip'Last));
      begin
         --  We may receive a ARP response without having a valid arp entry in our table.
         --  This could happen when packets are forged (ARP poisoning) or when we dropped
         --  the arp entry before we received any ARP response.
         if Rt /= null then
            Rt.Ether       := Mac;
            Rt.Valid       := True;
            Rt.Unreachable := False;
            Rt.Pending     := False;
            Rt.Stale       := False;
            Rt.Expire      := Ada.Real_Time.Clock + Arp_Entry_Timeout;

            --  If we have some packets waiting for the ARP resolution, return the packet list.
            if Rt.Queue_Size > 0 then
               Net.Buffers.Transfer (List, Rt.Queue);
               Queue_Size    := Queue_Size - Natural (Rt.Queue_Size);
               Rt.Queue_Size := 0;
            end if;
         end if;
      end Update;

   end Database;

   --  ------------------------------
   --  Proceed to the ARP database timeouts, cleaning entries and re-sending pending
   --  ARP requests.  The procedure should be called once every second.
   --  ------------------------------
   procedure Timeout (Ifnet : in out Net.Interfaces.Ifnet_Type'Class) is
      Refresh : Arp_Refresh;
      Count   : Natural;
      Ip      : Net.Ip_Addr;
   begin
      Database.Timeout (Ifnet, Refresh, Count);
      for I in 1 .. Count loop
         Ip           := Ifnet.Ip;
         Ip (Ip'Last) := Refresh (I);
         --  MT: TODO: Update me to use IPCP names instead of IP
         --  Request (Ifnet, Ifnet.Ip, Ip, Ifnet.Mac);
      end loop;
   end Timeout;

   --  ------------------------------
   --  Resolve the target IP address to obtain the associated Ethernet address
   --  from the ARP table.  The Status indicates whether the IP address is
   --  found, or a pending ARP resolution is in progress or it was unreachable.
   --  ------------------------------
   procedure Resolve
     (Ifnet  : in out Net.Interfaces.Ifnet_Type'Class; Target_Ip : in Ip_Addr;
      Mac    :    out Ether_Addr; Packet : in out Net.Buffers.Buffer_Type;
      Status :    out Arp_Status)
   is
   begin
      Database.Resolve (Ifnet, Target_Ip, Mac, Packet, Status);
      if Status = ARP_NEEDED then
         null;
         --  MT: TODO: Update me to use IPCP names instead of IP
         --  Request (Ifnet, Ifnet.Ip, Target_Ip, Ifnet.Mac);
      end if;
   end Resolve;

   --  ------------------------------
   --  Update the arp table with the IP address and the associated Ethernet address.
   --  ------------------------------
   procedure Update
     (Ifnet : in out Net.Interfaces.Ifnet_Type'Class; Target_Ip : in Ip_Addr;
      Mac   : in     Ether_Addr)
   is
      Waiting : Net.Buffers.Buffer_List;
      Ether   : Net.Headers.Ether_Header_Access;
      Packet  : Net.Buffers.Buffer_Type;
   begin
      Database.Update (Target_Ip, Mac, Waiting);
      while not Net.Buffers.Is_Empty (Waiting) loop
         Net.Buffers.Peek (Waiting, Packet);
         Ether             := Packet.Ethernet;
         Ether.Ether_Dhost := Mac;
         Ifnet.Send (Packet);
      end loop;
   end Update;

   use type Net.Headers.Length_Delimited_String;
   use type Net.Headers.Arp_Packet_Access;

   procedure Receive
     (Ifnet  : in out Net.Interfaces.Ifnet_Type'Class;
      Packet : in out Net.Buffers.Buffer_Type)
   is
      Req              : constant Net.Headers.Arp_Packet_Access := Packet.Arp;
      Pac              : Net.Buffers.Buffer_Type;
      Str_Fixed_Length : Uint8                                  := 0;
   begin
      begin         
         --  Do nothing if parse failed
         if Req = null then
            Debug.Print (Debug.Error, "Parse failed!");
            return;
         end if;

         --  Check for valid hardware (mac addr) length and protocol type.
         if Req.Arp.Ea_Hdr.Ar_Pro = Net.Headers.To_Network (ETHERTYPE_RINA) and
           Req.Arp.Ea_Hdr.Ar_Hln = Ifnet.Mac'Length
         then

            case Net.Headers.To_Host (Req.Arp.Ea_Hdr.Ar_Op) is
               when ARPOP_REQUEST =>
                  Debug.Print
                    (Debug.Info,
                     "RINA ARP Request Received " & Req.Arp.Arp_Spa.all &
                     " => " & Req.Arp.Arp_Tpa.all);

                  Debug.Print
                    (Debug.Info, "Searching for: " & Req.Arp.Arp_Tpa.all);
                  
                  --  Check if the requested IPCP exists in any of our local DIFs
                  if DIF_Manager.IPCP_Exists (Req.Arp.Arp_Tpa.all) or DIF_Manager.Application_Exists (Req.Arp.Arp_Tpa.all) then
                     Net.Buffers.Allocate (Pac);

                     if Pac.Is_Null then
                        Debug.Print (Debug.Error, "Buf is NULL");
                        return;
                     end if;

                     --  Packet.Set_Type (Net.Buffers.ARP_PACKET);
                     Pac.Set_Type (Net.Buffers.ETHER_PACKET);

                     --  Where packet will be routed
                     Pac.Ethernet.Ether_Dhost :=
                       Broadcast_Mac; -- Req.Ethernet.Ether_Shost;
                     Pac.Ethernet.Ether_Shost := Ifnet.Mac;
                     Pac.Ethernet.Ether_Type  :=
                       Net.Headers.To_Network (ETHERTYPE_ARP);

                     Pac.Put_Uint16 (ARPHRD_ETHER);
                     Pac.Put_Uint16 (Net.Protos.ETHERTYPE_RINA);
                     Pac.Put_Uint8 (Ifnet.Mac'Length);

                     Str_Fixed_Length :=
                       Uint8'Max
                         (Req.Arp.Arp_Tpa.all'Length,
                          Req.Arp.Arp_Spa.all'Length);
                     Pac.Put_Uint8 (Str_Fixed_Length);
                     Pac.Put_Uint16 (ARPOP_REPLY);

                     Pac.Put_Ether_Addr (Ifnet.Mac);
                     Pac.Put_String (Req.Arp.Arp_Tpa.all, Str_Fixed_Length);

                     Pac.Put_Ether_Addr (Req.Ethernet.Ether_Shost);
                     Pac.Put_String (Req.Arp.Arp_Spa.all, Str_Fixed_Length);

                     --  Send the corresponding ARP reply with our Ethernet address.
                     Pac.Set_Length
                       (Net.Buffers.Offsets (Net.Buffers.ETHER_PACKET) + 20 +
                        2 * Uint16 (Str_Fixed_Length));

                     Ifnet.Send (Pac);

                     Debug.Print
                       (Debug.Info,
                        "Matching local IPCP found! ARP response sent");
                  else
                     Debug.Print
                       (Debug.Warning,
                        "No matching local IPCP, ignoring ARP request");
                  end if;

               when ARPOP_REPLY =>
                  Debug.Print (Debug.Warning, "ARPOP_REPLY");
                  --if Req.Arp.Arp_Tpa = Ifnet.Ip and Req.Arp.Arp_Tha = Ifnet.Mac then
                  --   Update (Ifnet, Req.Arp.Arp_Spa, Req.Arp.Arp_Sha);
                  --end if;
               when others =>
                  Ifnet.Rx_Stats.Ignored := Ifnet.Rx_Stats.Ignored + 1;
            end case;
         else
            --  Ignore any future processing of this ARP message if it's not RINA-related
            Ifnet.Rx_Stats.Ignored := Ifnet.Rx_Stats.Ignored + 1;
            return;
         end if;
      end;
   end Receive;

end Net.Protos.Arp;
