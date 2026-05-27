with Ada.Text_IO; use Ada.Text_IO;

package body SMS.Render is

   NL : constant String := "" & ASCII.LF;
   W  : constant := 8;  --  station block column width

   type Slot_Array is array (Positive range <>) of Natural;

   function Pad (S : String) return String is
   begin
      if S'Length >= W then
         return S (S'First .. S'First + W - 1);
      else
         return S & (1 .. W - S'Length => ' ');
      end if;
   end Pad;

   function Num (N : Natural) return String is
      Img : constant String := Natural'Image (N);
   begin
      return Img (Img'First + 1 .. Img'Last);
   end Num;

   --  S 5.3 state -> indicator (boxed text approximated with brackets).
   function Indicator (St : Station_Record) return String is
   begin
      case St.State is
         when Empty     => return "";
         when Loaded    => return "RDY";
         when Selected  => return "[SEL]";
         when Releasing => return "*REL*";
         when Jettison  => return "!JET!";
      end case;
   end Indicator;

   --  Three content lines of a station block (S 4.2).
   procedure Block (St : Station_Id; State : SMS_State;
                    L1, L2, L3 : out String) is
      R : constant Station_Record := State.Stations (St);
   begin
      L1 := Pad ("STA" & Num (Natural (St)));
      if R.Present then
         L2 := Pad (Store_Type'Image (R.Item.Kind) & " x" & Num (R.Item.Quantity));
      else
         L2 := Pad ("----");
      end if;
      L3 := Pad (Indicator (R));
   end Block;

   function Blank_Cell return String is (Pad (""));

   function Page (State : SMS_State) return String is
      Result : String (1 .. 4096);
      Len    : Natural := 0;

      procedure Emit (S : String) is
      begin
         Result (Len + 1 .. Len + S'Length) := S;
         Len := Len + S'Length;
      end Emit;

      procedure Line (S : String) is
      begin
         Emit (S);
         Emit (NL);
      end Line;

      --  Render one planform row from up to 7 station slots (0 => blank).
      procedure Plan_Row (Slots : Slot_Array) is
         L1, L2, L3 : String (1 .. W);
         R1 : String (1 .. (W + 1) * Slots'Length) := (others => ' ');
         R2 : String (1 .. (W + 1) * Slots'Length) := (others => ' ');
         R3 : String (1 .. (W + 1) * Slots'Length) := (others => ' ');
         P  : Natural := 0;
      begin
         for I in Slots'Range loop
            if Slots (I) = 0 then
               R1 (P + 1 .. P + W) := Blank_Cell;
               R2 (P + 1 .. P + W) := Blank_Cell;
               R3 (P + 1 .. P + W) := Blank_Cell;
            else
               Block (Station_Id (Slots (I)), State, L1, L2, L3);
               R1 (P + 1 .. P + W) := L1;
               R2 (P + 1 .. P + W) := L2;
               R3 (P + 1 .. P + W) := L3;
            end if;
            P := P + W + 1;  --  one-space gutter
         end loop;
         Line (R1);
         Line (R2);
         Line (R3);
         Line ("");
      end Plan_Row;

      function Arm_Field return String is
      begin
         case State.Arm is
            when Safe => return "SAFE";
            when Arm  => return "[ARM]";   --  boxed / caution (S 7.4)
            when Sim  => return "SIM";
         end case;
      end Arm_Field;

   begin
      Line ("=============== DDI: STORES FORMAT ===============");
      --  Top bezel PB1..PB5
      Line (" PB1 STA1   PB2 STA2   PB3 STA3   PB4 STA4   PB5 STA5");
      Line ("");

      --  Planform (S 4.1): wingtips over outboard pylons.
      --  Row A: sta1 ............................. sta9
      Plan_Row (Slot_Array'(1, 0, 0, 0, 0, 0, 9));
      --  Row B: sta2 sta3 sta4 sta5 sta6 sta7 sta8
      Plan_Row (Slot_Array'(2, 3, 4, 5, 6, 7, 8));

      --  Status strip (S 4.2).
      Line (" MASTER ARM: " & Arm_Field
            & "   MODE: " & Release_Mode'Image (State.Mode)
            & "   QTY " & Num (Natural (State.Rpl_Qty))
            & "  INT " & Num (Natural (State.Rpl_Int))
            & "   EMPLOY: " & (if State.Employ = AG then "A/G" else "A/A"));

      if State.Pending_Active then
         Line (" CCRP: RELEASE PENDING (qty" & Natural'Image (State.Pending_Qty)
               & " ) -- awaiting RELEASE POINT");
      end if;

      --  Advisories (S 8.2 render-only list).
      if State.Adv_Count > 0 then
         Emit (" ADV:");
         for I in 1 .. State.Adv_Count loop
            Emit (" " & Msg_Pkg.To_String (State.Advisories (I)));
            if I < State.Adv_Count then
               Emit (" |");
            end if;
         end loop;
         Line ("");
      end if;

      --  Release effects emitted this frame (logged, not a hardware command).
      if State.Eff_Count > 0 then
         Emit (" FX :");
         for I in 1 .. State.Eff_Count loop
            Emit (" " & Msg_Pkg.To_String (State.Effects (I)));
         end loop;
         Line ("");
      end if;

      Line ("");
      Line (" PB10 MODE  PB11 QTY  PB12 INT  PB13 FUZE  PB14 MARM=" & Arm_Field);
      Line (" PB15 " & (if State.Jett_Armed then "JETT*ARMED*" else "JETT")
            & "  PB16 STEP  PB20 "
            & (if State.Employ = AG then "A/G" else "A/A"));
      Line ("==================================================");

      return Result (1 .. Len);
   end Page;

   procedure Put_Page (State : SMS_State) is
   begin
      Put (Page (State));
   end Put_Page;

end SMS.Render;
