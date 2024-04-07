with GUI;
with Texture_PSU;
with Texture_Logo;
with Network;
with STM32;
with STM32.Board;
with DIF_Manager;   use DIF_Manager;
with IPCP_Manager;  use IPCP_Manager;
with Ada.Real_Time; use Ada.Real_Time;
with Demo_IPCP;
with HAL.Bitmap;
with Debug;
with HAL.Touch_Panel;

procedure Demo is
   Period : constant Time_Span := Milliseconds (1 / GUI.Frame_Rate * 1_000);
   Next_Render : Time               := Clock;
   This_DIF    : DIF_Access;
   This_IPCP   : IPCP;
   Show_Menu : Boolean := False;
   Show_Network_Stats : Boolean := False;
   Show_Device_Info : Boolean := False;
begin
   GUI.Initialize;
   STM32.Board.Touch_Panel.Initialize;
   Network.Initialize;
   STM32.Board.Touch_Panel.Initialize;
   STM32.Board.Configure_User_Button_GPIO;
   STM32.Board.Initialize_LEDs;
   STM32.Board.All_LEDs_Off;

   --  Create a new DIF
   This_DIF := DIF_Manager.Create ("ethAB.DIF", Ethernet);

   DIF_Manager.DIF_List.Append (This_DIF);

   --  Create the IPC process we want to enroll into the DIF
   This_IPCP := IPCP_Manager.Create ("b.IPCP");

   --  Enroll this IPCP into the DIF
   This_DIF.Enroll (This_IPCP);
   
   --  Register test server application to this DIF
   This_DIF.Register ("TestServer", Demo_IPCP'Access);

   --  Render loop keeps the board from immediately terminating
   loop
      declare
        State : HAL.Touch_Panel.TP_State := STM32.Board.Touch_Panel.Get_All_Touch_Points;
      begin

      GUI.Draw_Rectangle ((0, 0), GUI.Board_Resolution, HAL.Bitmap.White);

      --  This is really ugly, but I'm not good enough with generics to figure out how to make it look better
      --  Perhaps Texture should be a tagged record instead so we can use dot notation here
      Texture_PSU.PSU.Print (Texture_PSU.Bitmap, (5, 8));
      Texture_Logo.Logo.Print (Texture_Logo.Bitmap, (75, 0));

      -- if the menu button on screen is pressed, set the Show_Menu flag, if the menu button is pressed again, unset the flag
      if GUI.Has_Touch(State => State) then
        if GUI.Has_Touch_Within_Area(State => State, P => (75, 45), S => (48, 25)) then
          Show_Menu := not Show_Menu;
        end if;
      end if;


      -- when the user presses the menu button, show the submenu
      if Show_Menu then
         GUI.Fill_Rounded_Rectangle ((75, 45), (48, 25), GUI.Button_Selected_Color, 2);
         GUI.Draw_Rounded_Rectangle ((125, 45), (150,65), HAL.Bitmap.Black, 2, 1);

          GUI.Fill_Rounded_Rectangle ((130, 50), (140, 25), GUI.Button_Color, 2);
          GUI.Print ("Network Stats", (150, 60));

          GUI.Fill_Rounded_Rectangle ((130, 78), (140, 25), GUI.Button_Color, 2);
          GUI.Print ("Device Info", (155, 87));
          
          -- if there is a touch event while the menu is open
          if (GUI.Has_Touch(State => State)) then
            -- check if the touch event is within the area of the network stats button
            if GUI.Has_Touch_Within_Area(State => State, P => (130, 50), S => (140, 25)) then
              Show_Network_Stats := not Show_Network_Stats;
            end if;
            -- check if the touch event is within the area of the device info button
            if GUI.Has_Touch_Within_Area(State => State, P => (130, 78), S => (140, 25)) then
              Show_Device_Info := not Show_Device_Info;
            end if;
          end if;
      else
        GUI.Fill_Rounded_Rectangle ((75, 45), (48, 25), GUI.Button_Color, 2);
      end if;
      GUI.Print ("Menu", (82, 53));


      GUI.Print_Large ("Console", (5, 105));
      GUI.Draw_Rounded_Rectangle
        ((5, 120), (GUI.Board_Resolution.Width - 8, 145), HAL.Bitmap.Black, 2,
         1);

      if Show_Device_Info then
        GUI.Draw_Rounded_Rectangle ((277, 2), (200, 36), HAL.Bitmap.Black, 2, 1);
        GUI.Print ("  Mac: 00:81:E1:05:05:01", (280, 12));
        GUI.Print ("Board:   STM32F746-DISCO", (280, 24));
      end if;

      if Show_Network_Stats then
        GUI.Draw_Rounded_Rectangle
          ((277, 40), (200, 20), HAL.Bitmap.Black, 2, 1);

        GUI.Fill_Rounded_Rectangle
          ((330, 46), (25, 10), GUI.Get_RX_Status_Color, 1);
        GUI.Print ("RX", (300, 48));

        GUI.Fill_Rounded_Rectangle
          ((420, 46), (25, 10), GUI.Get_TX_Status_Color, 1);
        GUI.Print ("TX", (390, 48));
      end if;


      GUI.Print ("Version: " & GUI.Build_Verson, (362, 105));

      --  GUI.Print ("Status: ", (80, 45));
      --  GUI.Print ("Waiting for enrollment request", (145, 45));

      --  GUI.Print
      --    ("Ignored Packets: " & Network.Ifnet.Rx_Stats.Ignored'Image, (80, 30));

      Debug.Render;
      GUI.Update;

      --  Set activation time of next render in loop
      Next_Render := Next_Render + Period;

      delay until Next_Render;
      end;
   end loop;
end Demo;
