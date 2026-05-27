--  Assertion-based tests for the SMS core against the spec's normative
--  contract (S 5 state machine, S 9 invariants, S 10 gating, S 11 worked
--  example). Exits non-zero if any check fails.

with Ada.Text_IO;      use Ada.Text_IO;
with Ada.Command_Line; use Ada.Command_Line;
with Ada.Strings.Fixed;
with SMS;              use SMS;

procedure SMS_Tests is

   Passed : Natural := 0;
   Failed : Natural := 0;

   procedure Check (Cond : Boolean; Name : String) is
   begin
      if Cond then
         Passed := Passed + 1;
      else
         Failed := Failed + 1;
         Put_Line ("  FAIL: " & Name);
      end if;
   end Check;

   function Has_Adv (S : SMS_State; Text : String) return Boolean is
   begin
      for I in 1 .. S.Adv_Count loop
         if Msg_Pkg.To_String (S.Advisories (I)) = Text then
            return True;
         end if;
      end loop;
      return False;
   end Has_Adv;

   function Has_Eff_With (S : SMS_State; Sub : String) return Boolean is
      use Ada.Strings.Fixed;
   begin
      for I in 1 .. S.Eff_Count loop
         if Index (Msg_Pkg.To_String (S.Effects (I)), Sub) > 0 then
            return True;
         end if;
      end loop;
      return False;
   end Has_Eff_With;

   procedure Finish (S : in out SMS_State) is
      St : Natural;
   begin
      while Burst_In_Progress (S) loop
         St := Releasing_Station (S);
         exit when St = 0;
         S := Apply (S, Ev_Pulse_Done (Station_Id (St)));
      end loop;
   end Finish;

   function MK82_Remaining (S : SMS_State) return Natural is
      Total : Natural := 0;
   begin
      for St in Station_Id loop
         if S.Stations (St).Present
           and then S.Stations (St).Item.Kind = MK82
         then
            Total := Total + S.Stations (St).Item.Quantity;
         end if;
      end loop;
      return Total;
   end MK82_Remaining;

begin
   --  ---- Initial / sample states (S 8.3, Appendix B defaults) ----
   declare
      I : constant SMS_State := Initial_State;
      S : constant SMS_State := Sample_State;
   begin
      Check (I.Arm = Safe and I.Employ = AG and I.Mode = CCIP, "init defaults");
      Check (I.Rpl_Qty = 1 and I.Rpl_Int = 100, "init ripple defaults");
      Check (Has_Adv (I, "M.ARM SAFE"), "init advisory M.ARM SAFE");
      Check (not I.Stations (1).Present, "init station empty");

      Check (S.Stations (1).Item.Kind = AIM9, "sample sta1 AIM9");
      Check (not S.Stations (2).Present, "sample sta2 empty");
      Check (S.Stations (3).Item.Kind = MK82 and S.Stations (3).Item.Quantity = 2,
             "sample sta3 MK82 x2");
      Check (S.Stations (3).Item.Fuze = Nose_Tail, "sample MK82 fuze NOSE_TAIL");
      Check (S.Stations (5).Item.Kind = TANK, "sample sta5 TANK");
      Check (MK82_Remaining (S) = 6, "sample has 6 MK82");
   end;

   --  ---- STATION_SELECT toggle, EMPTY STA, INVALID SEL ----
   declare
      S : SMS_State := Sample_State;
   begin
      S := Apply (S, Ev_Select (3));
      Check (Is_Selected (S, 3) and Selection_Count (S) = 1, "select sta3 (T3)");
      S := Apply (S, Ev_Select (3));
      Check (not Is_Selected (S, 3) and Selection_Count (S) = 0, "deselect (T4)");

      S := Apply (S, Ev_Select (2));   --  empty hardpoint
      Check (Has_Adv (S, "EMPTY STA") and Selection_Count (S) = 0,
             "select empty -> EMPTY STA");

      S := Apply (S, Ev_Select (5));   --  TANK in A/G
      Check (Has_Adv (S, "INVALID SEL") and Selection_Count (S) = 0,
             "select TANK -> INVALID SEL");

      S := Apply (S, Ev_Select (1));   --  AIM9 in A/G (not employable)
      Check (Has_Adv (S, "INVALID SEL"), "select AIM9 in A/G -> INVALID SEL");
   end;

   --  ---- Invariant: SELECTED <=> in selection (S 9.2) ----
   declare
      S : SMS_State := Sample_State;
   begin
      S := Apply (S, Ev_Select (3));
      S := Apply (S, Ev_Select (7));
      Check (Is_Selected (S, 3) and Is_Selected (S, 7)
             and not Is_Selected (S, 4) and Selection_Count (S) = 2,
             "selection-state invariant");
   end;

   --  ---- Mode cycle + ripple param wrap (S 9.1) ----
   declare
      S : SMS_State := Sample_State;
   begin
      Check (S.Mode = CCIP, "mode starts CCIP");
      S := Apply (S, Ev_Mode_Cycle); Check (S.Mode = CCRP, "CCIP->CCRP");
      S := Apply (S, Ev_Mode_Cycle); Check (S.Mode = Ripple, "CCRP->RIPPLE");
      S := Apply (S, Ev_Mode_Cycle); Check (S.Mode = CCIP, "RIPPLE->CCIP");

      for K in 1 .. 5 loop S := Apply (S, Ev_Qty_Inc); end loop;
      Check (S.Rpl_Qty = 6, "qty inc to 6");
      S := Apply (S, Ev_Qty_Inc); Check (S.Rpl_Qty = 1, "qty wraps 6->1");

      while S.Rpl_Int < 500 loop S := Apply (S, Ev_Int_Inc); end loop;
      Check (S.Rpl_Int = 500, "int reaches 500");
      S := Apply (S, Ev_Int_Inc); Check (S.Rpl_Int = 50, "int wraps 500->50");
   end;

   --  ---- Fuze cycle on selected bombs (S 9.1) ----
   declare
      S : SMS_State := Sample_State;
   begin
      S := Apply (S, Ev_Select (3));   --  MK82, fuze NOSE_TAIL
      S := Apply (S, Ev_Fuze_Cycle);   Check (S.Stations (3).Item.Fuze = Safe, "NT->SAFE");
      S := Apply (S, Ev_Fuze_Cycle);   Check (S.Stations (3).Item.Fuze = Nose, "SAFE->NOSE");
      S := Apply (S, Ev_Fuze_Cycle);   Check (S.Stations (3).Item.Fuze = Tail, "NOSE->TAIL");
      S := Apply (S, Ev_Fuze_Cycle);   Check (S.Stations (3).Item.Fuze = Nose_Tail, "TAIL->NT");
   end;

   --  ---- Gate G1: SAFE blocks live release (S 10.2) ----
   declare
      S : SMS_State := Sample_State;
      Before : SMS_State;
   begin
      S := Apply (S, Ev_Select (3));
      Before := S;
      S := Apply (S, Ev_Release (Pressed => True));   --  arm SAFE
      Check (S.Stations = Before.Stations, "G1 SAFE: no release");
      Check (Has_Adv (S, "M.ARM SAFE"), "G1 SAFE: advisory");
      Check (not Burst_In_Progress (S), "G1 SAFE: no burst");
   end;

   --  ---- Gate G2: empty selection -> NO STA SEL (S 10.2) ----
   declare
      S : SMS_State := Sample_State;
   begin
      S := Apply (S, Ev_Set_Arm (Arm));
      S := Apply (S, Ev_Release (Pressed => True));
      Check (Has_Adv (S, "NO STA SEL"), "G2: NO STA SEL");
   end;

   --  ---- Worked example (S 11): RIPPLE-2 string in CCIP, ARM, commit ----
   declare
      S  : SMS_State := Sample_State;
      S1 : SMS_State;
   begin
      S := Apply (S, Ev_Select (3));
      S := Apply (S, Ev_Select (4));
      S := Apply (S, Ev_Select (6));
      S := Apply (S, Ev_Select (7));
      Check (Selection_Count (S) = 4, "WE: 4 selected");

      S := Apply (S, Ev_Mode_Cycle);   --  CCRP
      S := Apply (S, Ev_Mode_Cycle);   --  RIPPLE
      S := Apply (S, Ev_Qty_Inc);      --  qty 2
      S := Apply (S, Ev_Mode_Cycle);   --  back to CCIP
      Check (S.Mode = CCIP and S.Rpl_Qty = 2, "WE: CCIP, string qty 2");

      S := Apply (S, Ev_Set_Arm (Arm));
      S := Apply (S, Ev_Release (Pressed => True));
      S1 := S;
      Check (Releasing_Station (S1) = 3, "WE: first pulse releases STA3");
      Check (Has_Eff_With (S1, "LIVE") and Has_Eff_With (S1, "MK82 STA3"),
             "WE: pulse 1 LIVE effect");

      Finish (S);
      Check (not S.Stations (3).Present and S.Stations (3).Item.Quantity = 0,
             "WE: STA3 emptied (both pulses, T7)");
      Check (Is_Selected (S, 4) and Is_Selected (S, 6) and Is_Selected (S, 7),
             "WE: STA4/6/7 still SELECTED");
      Check (MK82_Remaining (S) = 4, "WE: 4 MK82 remain");
      Check (Has_Adv (S, "RIPPLE CPLT"), "WE: RIPPLE CPLT advisory");
      Check (not Burst_In_Progress (S), "WE: burst complete");
   end;

   --  ---- SIM: identical transitions, qty decrements, SIM effect (S 7.4) ----
   declare
      S  : SMS_State := Sample_State;
      S1 : SMS_State;
   begin
      S := Apply (S, Ev_Select (3));   --  MK82 x2
      S := Apply (S, Ev_Set_Arm (Sim));
      S := Apply (S, Ev_Release (Pressed => True));
      S1 := S;
      Check (Has_Eff_With (S1, "SIM") and Has_Eff_With (S1, "MK82 STA3"),
             "SIM: simulated effect, not live");
      Finish (S);
      Check (S.Stations (3).Item.Quantity = 1, "SIM: qty still decremented");
   end;

   --  ---- A/A FOX-2 (S 10.4) ----
   declare
      S : SMS_State := Sample_State;
   begin
      S := Apply (S, Ev_Toggle_Employ);     --  A/A, clears selection
      Check (S.Employ = AA and Selection_Count (S) = 0, "AA toggle clears sel");
      S := Apply (S, Ev_Select (1));         --  AIM9
      Check (Is_Selected (S, 1), "AA: select AIM9 sta1");
      S := Apply (S, Ev_Set_Arm (Arm));
      S := Apply (S, Ev_Release (Pressed => True));
      Check (Has_Adv (S, "FOX-2"), "AA: FOX-2 advisory");
      Check (not S.Stations (1).Present, "AA: AIM9 expended");
   end;

   --  ---- A/A FOX-1 with AIM7 ----
   declare
      S : SMS_State := Initial_State;
   begin
      S := Apply (S, Ev_Load (4, AIM7, 1));
      S := Apply (S, Ev_Toggle_Employ);
      S := Apply (S, Ev_Select (4));
      S := Apply (S, Ev_Set_Arm (Arm));
      S := Apply (S, Ev_Release (Pressed => True));
      Check (Has_Adv (S, "FOX-1") and not S.Stations (4).Present, "AA: FOX-1");
   end;

   --  ---- Jettison (T8/T9): two-press arm/confirm empties selection ----
   declare
      S : SMS_State := Sample_State;
   begin
      S := Apply (S, Ev_Select (3));
      S := Apply (S, Ev_Jett_Arm);
      Check (S.Jett_Armed and Has_Adv (S, "JETT ARMED"), "JETT armed");
      S := Apply (S, Ev_Jett_Confirm);
      Check (not S.Stations (3).Present and not S.Jett_Armed, "JETT empties sta3");
   end;

   --  ---- CCRP pending, cancel, and release-point execution (S 7.2/10.2) ----
   declare
      S : SMS_State := Sample_State;
   begin
      S := Apply (S, Ev_Select (7));         --  MK82 x2
      S := Apply (S, Ev_Qty_Inc);             --  string qty 2 (release both)
      S := Apply (S, Ev_Mode_Cycle);          --  CCRP
      S := Apply (S, Ev_Set_Arm (Arm));
      S := Apply (S, Ev_Release (Pressed => True));
      Check (Pending_CCRP (S) and not Burst_In_Progress (S), "CCRP: pending armed");
      S := Apply (S, Ev_Release (Pressed => False));  --  cancel
      Check (not Pending_CCRP (S) and Has_Adv (S, "CCRP CANCEL"), "CCRP: cancel");

      --  re-arm and reach point
      S := Apply (S, Ev_Release (Pressed => True));
      S := Apply (S, Ev_Point_Reached);
      Finish (S);
      Check (not S.Stations (7).Present, "CCRP: point reached -> released x2");
   end;

   --  ---- STEP (PB16): move selection to next like-type station ----
   declare
      S : SMS_State := Sample_State;
   begin
      S := Apply (S, Ev_Select (3));          --  MK82
      S := Apply (S, Ev_Step);                --  -> next MK82 (sta4)
      Check (not Is_Selected (S, 3) and Is_Selected (S, 4), "STEP 3->4");
   end;

   --  ---- LOAD_STORE / STORE_REMOVED (T1/T2) ----
   declare
      S : SMS_State := Initial_State;
   begin
      S := Apply (S, Ev_Load (3, MK82, 3));
      Check (S.Stations (3).Present and S.Stations (3).Item.Quantity = 3
             and S.Stations (3).Item.Fuze = Nose_Tail, "LOAD MK82 x3 (T1)");
      S := Apply (S, Ev_Load (3, MK82, 1));   --  occupied
      Check (Has_Adv (S, "STA OCCUPIED") and S.Stations (3).Item.Quantity = 3,
             "LOAD occupied rejected");
      S := Apply (S, Ev_Remove (3));
      Check (not S.Stations (3).Present, "STORE_REMOVED (T2)");
   end;

   --  ---- Report ----
   New_Line;
   Put_Line ("SMS tests: " & Passed'Image & " passed," & Failed'Image & " failed.");
   if Failed > 0 then
      Set_Exit_Status (1);
   else
      Set_Exit_Status (0);
   end if;
end SMS_Tests;
