--  Runs the S 11 worked example (6x Mk82 on sta 3/4/6/7, RIPPLE 2 string in
--  CCIP, arm, commit) end to end, rendering the STORES page at key steps, then
--  briefly exercises an A/A FOX-2 and a selective jettison.

with Ada.Text_IO; use Ada.Text_IO;
with SMS;         use SMS;
with SMS.Render;

procedure SMS_Demo is

   --  Drive an in-progress CCIP/CCRP/RIPPLE burst to completion by feeding the
   --  internal RELEASE_PULSE_DONE for whichever station is RELEASING, pacing on
   --  the ripple interval (S 7.3 / S 10.3).
   procedure Drive_Burst (S : in out SMS_State) is
      St : Natural;
   begin
      while Burst_In_Progress (S) loop
         St := Releasing_Station (S);
         exit when St = 0;
         delay Duration (S.Rpl_Int) / 1000.0;
         S := Apply (S, Ev_Pulse_Done (Station_Id (St)));
         Put_Line ("  -> pulse done STA" & St'Image
                   & "   (releasing now: " & Releasing_Station (S)'Image & ")");
      end loop;
   end Drive_Burst;

   procedure Banner (Text : String) is
   begin
      New_Line;
      Put_Line ("########## " & Text & " ##########");
   end Banner;

   S : SMS_State := Sample_State;

begin
   Banner ("WORKED EXAMPLE (spec S 11) -- starting state (S 8.3)");
   SMS.Render.Put_Page (S);

   Banner ("Steps 2-5: select stations 3, 4, 6, 7");
   S := Press (S, 3);
   S := Press (S, 4);
   S := Press (S, 6);
   S := Press (S, 7);
   SMS.Render.Put_Page (S);

   Banner ("Step 6: MODE x2 (CCIP->CCRP->RIPPLE), Step 7: QTY +1 -> 2");
   S := Press (S, 10);   --  MODE -> CCRP
   S := Press (S, 10);   --  MODE -> RIPPLE
   S := Press (S, 11);   --  QTY 1 -> 2
   SMS.Render.Put_Page (S);

   Banner ("Step 9: MODE x1 (RIPPLE->CCIP); QTY 2 retained as string size");
   S := Press (S, 10);   --  MODE -> CCIP
   SMS.Render.Put_Page (S);

   Banner ("Step 10: MASTER ARM -> ARM");
   S := Press (S, 14);   --  SAFE -> ARM
   SMS.Render.Put_Page (S);

   Banner ("Step 11: PICKLE (RELEASE_COMMAND) -- CCIP burst N=2 begins");
   S := Apply (S, Ev_Release (Pressed => True));
   Put_Line ("  first pulse fired; releasing STA"
             & Releasing_Station (S)'Image);
   Drive_Burst (S);
   SMS.Render.Put_Page (S);
   Put_Line (" Expect: STA3 empty, STA4/6/7 still SELECTED, 4x MK82 remain.");

   Banner ("Master Arm -> SAFE re-inhibits release");
   S := Press (S, 14);   --  ARM -> SIM
   S := Press (S, 14);   --  SIM -> SAFE
   declare
      Before : constant SMS_State := S;
   begin
      S := Apply (S, Ev_Release (Pressed => True));
      Put_Line ("  release attempt with SAFE -> stores unchanged: "
                & Boolean'Image (S.Stations = Before.Stations));
   end;
   SMS.Render.Put_Page (S);

   --  ------------------------------------------------------------------
   Banner ("A/A demo: toggle A/A, select wingtip AIM-9 (sta1), FOX-2");
   S := Sample_State;
   S := Press (S, 20);          --  EMPLOY -> A/A (clears selection)
   S := Press (S, 1);           --  select STA1 (AIM9)
   S := Press (S, 14);          --  ARM
   S := Apply (S, Ev_Release (Pressed => True));
   SMS.Render.Put_Page (S);

   --  ------------------------------------------------------------------
   Banner ("Jettison demo: select sta3, arm jettison (PB15 x2)");
   S := Sample_State;
   S := Press (S, 3);           --  select STA3
   S := Press (S, 15);          --  JETT (arm)
   S := Press (S, 15);          --  JETT (confirm)
   SMS.Render.Put_Page (S);
   Put_Line (" Expect: STA3 now empty (jettisoned unarmed).");

   --  ------------------------------------------------------------------
   Banner ("CCRP demo: select sta7 (x2), string qty 2, CCRP, arm, pickle, point");
   S := Sample_State;
   S := Press (S, 7);                       --  select STA7 (2x MK82)
   S := Press (S, 11);                      --  string qty 1 -> 2
   S := Press (S, 10);                      --  MODE CCIP -> CCRP
   S := Press (S, 14);                      --  ARM
   S := Apply (S, Ev_Release (Pressed => True));
   Put_Line ("  pickle pressed -> CCRP pending = "
             & Boolean'Image (Pending_CCRP (S)) & " (awaiting release point)");
   S := Apply (S, Ev_Point_Reached);        --  release point reached
   Drive_Burst (S);
   SMS.Render.Put_Page (S);
   Put_Line (" Expect: STA7 emptied at release point (2 dropped).");
end SMS_Demo;
