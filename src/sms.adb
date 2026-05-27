package body SMS is

   use Msg_Pkg;

   --  Image of a Natural with no leading blank ("3" rather than " 3").
   function Trim_Num (N : Natural) return String is
      Img : constant String := Natural'Image (N);
   begin
      return Img (Img'First + 1 .. Img'Last);
   end Trim_Num;

   --  ---------------------------------------------------------------------
   --  Per-type rules (S 6)
   --  ---------------------------------------------------------------------

   function Max_Quantity (T : Store_Type) return Quantity is
   begin
      case T is
         when MK82 => return 3;   --  TER-capable
         when others => return 1;
      end case;
   end Max_Quantity;

   function Default_Fuze (T : Store_Type) return Fuze_Type is
   begin
      case T is
         when MK82 => return Nose_Tail;  --  Appendix B
         when others => return NA;
      end case;
   end Default_Fuze;

   function Is_Bomb (T : Store_Type) return Boolean is
   begin
      return T = MK82;
   end Is_Bomb;

   --  Selectable for *employment* (S 6, S 9.3). A/G employs bombs, A/A employs
   --  missiles. TANK is never selectable (S 6: jettison-only).
   function Selectable (Item : Store; Employ : Employ_Mode) return Boolean is
   begin
      case Employ is
         when AG => return Item.Kind = MK82;
         when AA => return Item.Kind = AIM9 or else Item.Kind = AIM7;
      end case;
   end Selectable;

   --  Advisory station/type compatibility (S 4.1). Non-blocking: used to
   --  validate loadouts at load time only; runtime never re-checks.
   function Compatible (Station : Station_Id; T : Store_Type) return Boolean is
   begin
      case Station is
         when 1 | 9 => return T = AIM9;
         when 2 | 8 => return T = MK82 or else T = AIM9;
         when 3 | 7 => return T = MK82 or else T = TANK;
         when 4     => return T = AIM7 or else T = TANK;
         when 5     => return T = TANK or else T = MK82;
         when 6     => return T = AIM7;
      end case;
   end Compatible;

   --  ---------------------------------------------------------------------
   --  Message helpers (advisories + effects, render-only, rebuilt per Apply)
   --  ---------------------------------------------------------------------

   procedure Add_Advisory (S : in out SMS_State; Text : String) is
      M : constant Message := To_Bounded_String (Text);
   begin
      for I in 1 .. S.Adv_Count loop
         if S.Advisories (I) = M then
            return;  --  dedup
         end if;
      end loop;
      if S.Adv_Count < Max_Messages then
         S.Adv_Count := S.Adv_Count + 1;
         S.Advisories (S.Adv_Count) := M;
      end if;
   end Add_Advisory;

   procedure Add_Effect (S : in out SMS_State; Text : String) is
   begin
      if S.Eff_Count < Max_Messages then
         S.Eff_Count := S.Eff_Count + 1;
         S.Effects (S.Eff_Count) := To_Bounded_String (Text);
      end if;
   end Add_Effect;

   --  ---------------------------------------------------------------------
   --  Selection helpers. "selection" is derived from Station_State.
   --  ---------------------------------------------------------------------

   type Sel_Array is array (1 .. 9) of Station_Id;

   procedure Selection (S : SMS_State; List : out Sel_Array; N : out Natural) is
   begin
      N := 0;
      for St in Station_Id loop
         if S.Stations (St).State = Selected then
            N := N + 1;
            List (N) := St;
         end if;
      end loop;
   end Selection;

   function Is_Selected (State : SMS_State; S : Station_Id) return Boolean is
   begin
      return State.Stations (S).State = Selected;
   end Is_Selected;

   function Selection_Count (State : SMS_State) return Natural is
      L : Sel_Array;
      N : Natural;
   begin
      Selection (State, L, N);
      return N;
   end Selection_Count;

   function Burst_In_Progress (State : SMS_State) return Boolean is
   begin
      return State.Burst.Active;
   end Burst_In_Progress;

   function Pending_CCRP (State : SMS_State) return Boolean is
   begin
      return State.Pending_Active;
   end Pending_CCRP;

   function Releasing_Station (State : SMS_State) return Natural is
   begin
      for St in Station_Id loop
         if State.Stations (St).State = Releasing then
            return Natural (St);
         end if;
      end loop;
      return 0;
   end Releasing_Station;

   --  ---------------------------------------------------------------------
   --  Event constructors
   --  ---------------------------------------------------------------------

   function Ev_Load
     (Station : Station_Id; T : Store_Type; Qty : Quantity;
      F : Fuze_Type := NA) return Input_Event is
   begin
      return (Kind => Load_Store, L_Station => Station, L_Type => T,
              L_Qty => Qty, L_Fuze => F);
   end Ev_Load;

   function Ev_Remove (Station : Station_Id) return Input_Event is
   begin
      return (Kind => Store_Removed, Station => Station);
   end Ev_Remove;

   function Ev_Select (Station : Station_Id) return Input_Event is
   begin
      return (Kind => Station_Select, Station => Station);
   end Ev_Select;

   function Ev_Step return Input_Event is
   begin
      return (Kind => Step);
   end Ev_Step;

   function Ev_Mode_Cycle return Input_Event is
   begin
      return (Kind => Mode_Cycle);
   end Ev_Mode_Cycle;

   function Ev_Qty_Inc return Input_Event is
   begin
      return (Kind => Ripple_Qty_Inc);
   end Ev_Qty_Inc;

   function Ev_Int_Inc return Input_Event is
   begin
      return (Kind => Ripple_Int_Inc);
   end Ev_Int_Inc;

   function Ev_Fuze_Cycle return Input_Event is
   begin
      return (Kind => Fuze_Cycle);
   end Ev_Fuze_Cycle;

   function Ev_Set_Arm (V : Master_Arm) return Input_Event is
   begin
      return (Kind => Master_Arm_Set, Arm_Value => V);
   end Ev_Set_Arm;

   function Ev_Toggle_Employ return Input_Event is
   begin
      return (Kind => Employ_Mode_Toggle);
   end Ev_Toggle_Employ;

   function Ev_Jett_Arm return Input_Event is
   begin
      return (Kind => Jettison_Arm);
   end Ev_Jett_Arm;

   function Ev_Jett_Confirm return Input_Event is
   begin
      return (Kind => Jettison_Confirm);
   end Ev_Jett_Confirm;

   function Ev_Release (Pressed : Boolean := True) return Input_Event is
   begin
      return (Kind => Release_Command, Pressed => Pressed);
   end Ev_Release;

   function Ev_Point_Reached return Input_Event is
   begin
      return (Kind => Release_Point_Reached);
   end Ev_Point_Reached;

   function Ev_Pulse_Done (Station : Station_Id) return Input_Event is
   begin
      return (Kind => Release_Pulse_Done, P_Station => Station);
   end Ev_Pulse_Done;

   --  ---------------------------------------------------------------------
   --  Starting states
   --  ---------------------------------------------------------------------

   function Initial_State return SMS_State is
      S : SMS_State;  --  defaults: all Empty, SAFE, AG, CCIP, qty 1, int 100
   begin
      --  Standing advisory shown while SAFE (matches S 8.3 sample instance).
      S.Adv_Count := 1;
      S.Advisories (1) := To_Bounded_String ("M.ARM SAFE");
      return S;
   end Initial_State;

   function Sample_State return SMS_State is
      S : SMS_State := Initial_State;

      procedure Hang (St : Station_Id; T : Store_Type; Q : Quantity) is
      begin
         S.Stations (St) :=
           (Present => True,
            Item    => (Kind => T, Quantity => Q, Fuze => Default_Fuze (T)),
            State   => Loaded);
      end Hang;
   begin
      Hang (1, AIM9, 1);
      --  station 2 empty
      Hang (3, MK82, 2);
      Hang (4, MK82, 1);
      Hang (5, TANK, 1);
      Hang (6, MK82, 1);
      Hang (7, MK82, 2);
      --  station 8 empty
      Hang (9, AIM9, 1);
      return S;
   end Sample_State;

   --  ---------------------------------------------------------------------
   --  Mode / fuze cycling
   --  ---------------------------------------------------------------------

   function Next_Mode (M : Release_Mode) return Release_Mode is
   begin
      case M is
         when CCIP   => return CCRP;
         when CCRP   => return Ripple;
         when Ripple => return CCIP;
      end case;
   end Next_Mode;

   function Next_Fuze (F : Fuze_Type) return Fuze_Type is
   begin
      case F is
         when Nose      => return Tail;
         when Tail      => return Nose_Tail;
         when Nose_Tail => return Safe;
         when Safe      => return Nose;
         when NA        => return NA;  --  non-bomb: unchanged
      end case;
   end Next_Fuze;

   --  ---------------------------------------------------------------------
   --  Event handlers
   --  ---------------------------------------------------------------------

   procedure Clear_Station (R : out Station_Record) is
   begin
      R := (Present => False, Item => (others => <>), State => Empty);
   end Clear_Station;

   --  T1: LOAD_STORE (EMPTY -> LOADED). Rejected if occupied or qty invalid.
   --  Station/type incompatibility is advisory only (S 4.1) -- the sample
   --  loadout in S 8.3 deliberately uses "incompatible" stations.
   procedure Do_Load (S : in out SMS_State; E : Input_Event) is
      R : Station_Record renames S.Stations (E.L_Station);
   begin
      if R.Present then
         Add_Advisory (S, "STA OCCUPIED");
         return;
      end if;
      if E.L_Qty < 1 or else E.L_Qty > Max_Quantity (E.L_Type) then
         Add_Advisory (S, "INVALID LOAD");
         return;
      end if;
      R := (Present => True,
            Item    => (Kind     => E.L_Type,
                        Quantity => E.L_Qty,
                        Fuze     => (if E.L_Fuze = NA and then Is_Bomb (E.L_Type)
                                     then Default_Fuze (E.L_Type)
                                     else E.L_Fuze)),
            State   => Loaded);
      if not Compatible (E.L_Station, E.L_Type) then
         Add_Advisory (S, "LOAD WARN");
      end if;
   end Do_Load;

   --  T2: STORE_REMOVED (LOADED -> EMPTY).
   procedure Do_Remove (S : in out SMS_State; St : Station_Id) is
   begin
      if S.Stations (St).Present then
         Clear_Station (S.Stations (St));
      else
         Add_Advisory (S, "EMPTY STA");
      end if;
   end Do_Remove;

   --  T3 / T4: STATION_SELECT toggle, with selectability validation (S 9.3).
   procedure Do_Select (S : in out SMS_State; St : Station_Id) is
      R : Station_Record renames S.Stations (St);
   begin
      if not R.Present then
         Add_Advisory (S, "EMPTY STA");
         return;
      end if;
      if not Selectable (R.Item, S.Employ) then
         Add_Advisory (S, "INVALID SEL");
         return;
      end if;
      case R.State is
         when Loaded   => R.State := Selected;
         when Selected => R.State := Loaded;
         when others   => null;  --  releasing/jettison: ignore
      end case;
   end Do_Select;

   --  PB16 STEP: move selection from the lowest selected like-type station to
   --  the next LOADED station of the same store type (cyclic).
   procedure Do_Step (S : in out SMS_State) is
      Sel : Sel_Array;
      N   : Natural;
   begin
      Selection (S, Sel, N);
      if N = 0 then
         Add_Advisory (S, "NO STA SEL");
         return;
      end if;
      declare
         Cur : constant Station_Id := Sel (1);
         T   : constant Store_Type := S.Stations (Cur).Item.Kind;
         Off : Natural;
         Cand : Station_Id;
      begin
         for K in 1 .. 8 loop
            Off := (Natural (Cur) - 1 + K) mod 9 + 1;
            Cand := Station_Id (Off);
            if S.Stations (Cand).State = Loaded
              and then S.Stations (Cand).Present
              and then S.Stations (Cand).Item.Kind = T
            then
               S.Stations (Cur).State  := Loaded;
               S.Stations (Cand).State := Selected;
               return;
            end if;
         end loop;
         Add_Advisory (S, "NO STEP");
      end;
   end Do_Step;

   --  PB13 FUZE: cycle fuze on every selected bomb station (S 9.1).
   procedure Do_Fuze (S : in out SMS_State) is
      Any : Boolean := False;
   begin
      for St in Station_Id loop
         if S.Stations (St).State = Selected
           and then Is_Bomb (S.Stations (St).Item.Kind)
         then
            S.Stations (St).Item.Fuze := Next_Fuze (S.Stations (St).Item.Fuze);
            Any := True;
         end if;
      end loop;
      if not Any then
         Add_Advisory (S, "NO STA SEL");
      end if;
   end Do_Fuze;

   --  PB20 EMPLOY_MODE_TOGGLE: AG<->AA, clears selection (S 9.1).
   procedure Do_Toggle_Employ (S : in out SMS_State) is
   begin
      S.Employ := (if S.Employ = AG then AA else AG);
      for St in Station_Id loop
         if S.Stations (St).State = Selected then
            S.Stations (St).State := Loaded;
         end if;
      end loop;
      S.Jett_Armed := False;
   end Do_Toggle_Employ;

   --  T8 / T9: JETTISON_CONFIRM empties all selected stations (unarmed).
   procedure Do_Jettison (S : in out SMS_State) is
      Count : Natural := 0;
   begin
      if not S.Jett_Armed then
         return;  --  confirm without prior arm: ignore
      end if;
      for St in Station_Id loop
         if S.Stations (St).State = Selected then
            Clear_Station (S.Stations (St));
            Count := Count + 1;
         end if;
      end loop;
      S.Jett_Armed := False;
      if Count = 0 then
         Add_Advisory (S, "NO STA SEL");
      else
         Add_Effect (S, "JETTISON x" & Count'Image);
      end if;
   end Do_Jettison;

   --  Fire one pulse: put the next draw-down station into RELEASING and emit
   --  the (live or simulated) release effect (S 10.3 step 2).
   procedure Fire_Pulse (S : in out SMS_State) is
      St : constant Station_Id := S.Burst.Order (Integer (S.Burst.Next));
      T  : constant Store_Type := S.Stations (St).Item.Kind;
   begin
      S.Stations (St).State := Releasing;
      Add_Effect (S,
        (if S.Burst.Live then "LIVE " else "SIM  ") &
        Store_Type'Image (T) & " STA" & Trim_Num (Natural (St)));
      S.Burst.Next := S.Burst.Next + 1;
   end Fire_Pulse;

   --  Build the draw-down order and start a burst (S 10.3 step 1-2).
   procedure Start_Burst (S : in out SMS_State; N : Positive) is
      Sel : Sel_Array;
      Cnt : Natural;
      Len : Order_Index := 0;
   begin
      Selection (S, Sel, Cnt);
      for I in 1 .. Cnt loop
         declare
            St : constant Station_Id := Sel (I);
            Q  : constant Quantity   := S.Stations (St).Item.Quantity;
         begin
            for J in 1 .. Q loop
               Len := Len + 1;
               S.Burst.Order (Integer (Len)) := St;
            end loop;
         end;
      end loop;

      if Len = 0 then
         Add_Advisory (S, "NO STORES");
         return;
      end if;

      S.Burst.Active := True;
      S.Burst.Length := Len;
      S.Burst.Limit  := Order_Index'Min (Order_Index (N), Len);
      S.Burst.Next   := 1;
      S.Burst.Done   := 0;
      S.Burst.Live   := S.Arm = Arm;
      Fire_Pulse (S);
   end Start_Burst;

   --  A/A employment (S 10.4): fire one missile from the lowest selected AAM.
   procedure Do_AA_Release (S : in out SMS_State) is
      Sel : Sel_Array;
      N   : Natural;
   begin
      Selection (S, Sel, N);
      for I in 1 .. N loop
         declare
            St : constant Station_Id := Sel (I);
            K  : constant Store_Type := S.Stations (St).Item.Kind;
         begin
            if (K = AIM9 or else K = AIM7)
              and then S.Stations (St).Item.Quantity > 0
            then
               Clear_Station (S.Stations (St));
               Add_Advisory (S, (if K = AIM9 then "FOX-2" else "FOX-1"));
               Add_Effect (S,
                 (if S.Arm = Arm then "LIVE " else "SIM  ") &
                 Store_Type'Image (K) & " STA" & Trim_Num (Natural (St)));
               return;
            end if;
         end;
      end loop;
      Add_Advisory (S, "INVALID SEL");
   end Do_AA_Release;

   --  RELEASE_COMMAND with gates G1-G4 (S 10.1 / 10.2).
   procedure Do_Release_Command (S : in out SMS_State; Pressed : Boolean) is
      Sel  : Sel_Array;
      N    : Natural;
      Bombs, Avail : Natural := 0;
   begin
      if not Pressed then
         if S.Pending_Active then
            S.Pending_Active := False;
            S.Pending_Qty    := 0;
            Add_Advisory (S, "CCRP CANCEL");
         end if;
         return;
      end if;

      if S.Burst.Active then
         return;  --  busy; ignore re-trigger mid-burst
      end if;

      --  G1: Master Arm. SAFE blocks live release (advisory via rebuild).
      if S.Arm = Safe then
         return;
      end if;

      --  G2: non-empty selection.
      Selection (S, Sel, N);
      if N = 0 then
         Add_Advisory (S, "NO STA SEL");
         return;
      end if;

      if S.Employ = AA then
         Do_AA_Release (S);
         return;
      end if;

      --  A/G gates G3 / G4.
      for I in 1 .. N loop
         declare
            R : Station_Record renames S.Stations (Sel (I));
         begin
            if Is_Bomb (R.Item.Kind) then
               Bombs := Bombs + 1;
               Avail := Avail + R.Item.Quantity;
            end if;
         end;
      end loop;

      if Bombs = 0 then            --  G3
         Add_Advisory (S, "INVALID SEL");
         return;
      end if;
      if Avail = 0 then            --  G4
         Add_Advisory (S, "NO STORES");
         return;
      end if;

      --  FUZE SAFE advisory (informational, non-blocking).
      for I in 1 .. N loop
         if Is_Bomb (S.Stations (Sel (I)).Item.Kind)
           and then S.Stations (Sel (I)).Item.Fuze = Safe
         then
            Add_Advisory (S, "FUZE SAFE");
         end if;
      end loop;

      --  String/burst size N is the ripple quantity in every delivery mode.
      --  S 7.1 ("a ripple burst if RIPPLE qty set") and the S 11 worked example
      --  (CCIP commit drops 2 = string size) take precedence over the
      --  N = (mode==RIPPLE)?qty:1 shorthand in S 10.2. CCIP/RIPPLE fire
      --  immediately; CCRP defers the same burst to the release point.
      declare
         Burst_N : constant Positive := Positive (S.Rpl_Qty);
      begin
         case S.Mode is
            when CCIP | Ripple =>
               Start_Burst (S, Burst_N);
            when CCRP =>
               S.Pending_Active := True;
               S.Pending_Qty    := Burst_N;
         end case;
      end;
   end Do_Release_Command;

   --  RELEASE_POINT_REACHED: execute a pending CCRP release.
   procedure Do_Release_Point (S : in out SMS_State) is
      Q : Positive;
   begin
      if not S.Pending_Active then
         return;
      end if;
      Q := Positive (S.Pending_Qty);
      S.Pending_Active := False;
      S.Pending_Qty    := 0;
      Start_Burst (S, Q);
   end Do_Release_Point;

   --  RELEASE_PULSE_DONE: complete a pulse, decrement, then advance (T6/T7).
   procedure Advance_Ripple (S : in out SMS_State; St : Station_Id) is
      R : Station_Record renames S.Stations (St);
   begin
      if not S.Burst.Active or else R.State /= Releasing then
         return;
      end if;

      if R.Item.Quantity > 0 then
         R.Item.Quantity := R.Item.Quantity - 1;
      end if;

      if R.Item.Quantity = 0 then     --  T7
         Clear_Station (R);
      else                            --  T6
         R.State := Selected;
      end if;

      S.Burst.Done := S.Burst.Done + 1;

      if S.Burst.Done < S.Burst.Limit then
         Fire_Pulse (S);
      else
         if S.Burst.Limit > 1 then
            Add_Advisory (S, "RIPPLE CPLT");
         end if;
         S.Burst.Active := False;
      end if;
   end Advance_Ripple;

   --  ---------------------------------------------------------------------
   --  Standing advisories (rebuilt at the end of every Apply, S 9.3)
   --  ---------------------------------------------------------------------

   procedure Rebuild_Advisories (S : in out SMS_State) is
   begin
      if S.Arm = Safe then
         Add_Advisory (S, "M.ARM SAFE");
      end if;
      if S.Jett_Armed then
         Add_Advisory (S, "JETT ARMED");
      end if;
   end Rebuild_Advisories;

   --  ---------------------------------------------------------------------
   --  The reducer
   --  ---------------------------------------------------------------------

   function Apply (State : SMS_State; Event : Input_Event) return SMS_State is
      S : SMS_State := State;
   begin
      S.Adv_Count := 0;
      S.Eff_Count := 0;

      case Event.Kind is
         when Load_Store         => Do_Load (S, Event);
         when Store_Removed      => Do_Remove (S, Event.Station);
         when Station_Select     => Do_Select (S, Event.Station);
         when Step               => Do_Step (S);
         when Mode_Cycle         => S.Mode := Next_Mode (S.Mode);
         when Ripple_Qty_Inc     =>
            S.Rpl_Qty := (if S.Rpl_Qty = Ripple_Qty'Last
                          then Ripple_Qty'First else S.Rpl_Qty + 1);
         when Ripple_Int_Inc     =>
            S.Rpl_Int := (if S.Rpl_Int = Interval_Ms'Last
                          then Interval_Ms'First else S.Rpl_Int + 50);
         when Fuze_Cycle         => Do_Fuze (S);
         when Master_Arm_Set     => S.Arm := Event.Arm_Value;
         when Employ_Mode_Toggle => Do_Toggle_Employ (S);
         when Jettison_Arm       => S.Jett_Armed := True;
         when Jettison_Confirm   => Do_Jettison (S);
         when Release_Command    => Do_Release_Command (S, Event.Pressed);
         when Release_Point_Reached => Do_Release_Point (S);
         when Release_Pulse_Done => Advance_Ripple (S, Event.P_Station);
      end case;

      Rebuild_Advisories (S);
      return S;
   end Apply;

   --  ---------------------------------------------------------------------
   --  Pushbutton dispatch (S 4.3)
   --  ---------------------------------------------------------------------

   function Next_Arm (M : Master_Arm) return Master_Arm is
   begin
      case M is
         when Safe => return Arm;
         when Arm  => return Sim;
         when Sim  => return Safe;
      end case;
   end Next_Arm;

   function Press (State : SMS_State; PB : PB_Index) return SMS_State is
   begin
      case PB is
         when 1 .. 9 =>
            return Apply (State, Ev_Select (Station_Id (PB)));
         when 10 =>
            return Apply (State, Ev_Mode_Cycle);
         when 11 =>
            return Apply (State, Ev_Qty_Inc);
         when 12 =>
            return Apply (State, Ev_Int_Inc);
         when 13 =>
            return Apply (State, Ev_Fuze_Cycle);
         when 14 =>
            return Apply (State, Ev_Set_Arm (Next_Arm (State.Arm)));
         when 15 =>
            if State.Jett_Armed then
               return Apply (State, Ev_Jett_Confirm);
            else
               return Apply (State, Ev_Jett_Arm);
            end if;
         when 16 =>
            return Apply (State, Ev_Step);
         when 17 .. 19 =>
            return State;  --  inert (S 4.3)
         when 20 =>
            return Apply (State, Ev_Toggle_Employ);
      end case;
   end Press;

end SMS;
