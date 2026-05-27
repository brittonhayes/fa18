--  F/A-18C Hornet -- Stores Management System (SMS) Stores Page.
--
--  Proof-of-concept core. Implements the normative contract from
--  docs/sms-stores-page-spec.md: the data model (S 8), the input event
--  model (S 9), the per-station state machine (S 5), and release logic /
--  gating (S 10).
--
--  Single source of truth: every state change flows through the total
--  reducer Apply (State, Event) -> State. Apply never raises on bad input;
--  an invalid event returns the state unchanged plus an advisory.

with Ada.Strings.Bounded;

package SMS is

   --  ---------------------------------------------------------------------
   --  Domain types (S 8 schema, Appendix A type sketch)
   --  ---------------------------------------------------------------------

   type Station_Id    is range 1 .. 9;
   type Store_Type    is (MK82, AIM9, AIM7, TANK);
   type Fuze_Type     is (Nose, Tail, Nose_Tail, Safe, NA);
   type Station_State is (Empty, Loaded, Selected, Releasing, Jettison);
   type Release_Mode  is (CCIP, CCRP, Ripple);
   type Master_Arm    is (Safe, Arm, Sim);
   type Employ_Mode   is (AG, AA);

   subtype Quantity    is Natural  range 0 .. 3;     --  per-station, S 6
   subtype Ripple_Qty  is Positive range 1 .. 6;     --  S 7.3
   subtype Interval_Ms is Positive range 50 .. 500;  --  S 7.3, step 50

   type Store is record
      Kind     : Store_Type := MK82;
      Quantity : SMS.Quantity := 0;
      Fuze     : Fuze_Type    := NA;
   end record;

   type Station_Record is record
      Present : Boolean       := False;  --  False => physically empty hardpoint
      Item    : Store;
      State   : Station_State := Empty;
   end record;

   type Loadout is array (Station_Id) of Station_Record;

   --  Advisory / effect strings are short, render-only (Appendix B).
   package Msg_Pkg is new Ada.Strings.Bounded.Generic_Bounded_Length (24);
   subtype Message is Msg_Pkg.Bounded_String;

   Max_Messages : constant := 16;
   type Message_List is array (1 .. Max_Messages) of Message;

   --  Burst bookkeeping for an in-progress CCIP/RIPPLE/CCRP release.
   --  Not part of the JSON schema; the schema captures in-progress pulses via
   --  Station_State = Releasing. We additionally retain the fixed draw-down
   --  order so successive RELEASE_PULSE_DONE events advance deterministically.
   Max_Pulses : constant := 27;  --  9 stations * max qty 3
   type Order_Index is range 0 .. Max_Pulses;
   type Order_Array is array (1 .. Max_Pulses) of Station_Id;

   type Burst_Record is record
      Active : Boolean      := False;
      Order  : Order_Array  := (others => Station_Id'First);
      Length : Order_Index  := 0;   --  valid entries in Order
      Limit  : Order_Index  := 0;   --  pulses to fire (N capped by Length)
      Next   : Order_Index  := 1;   --  index of next pulse to fire
      Done   : Order_Index  := 0;   --  pulses completed
      Live   : Boolean      := False;  --  ARM (live) vs SIM at burst start
   end record;

   --  Full runtime model. Loadout + selection/mode/master-arm + per-station
   --  state. "selection" (S 8) is derived from Station_State = Selected, so
   --  the SELECTED <=> in-selection invariant holds by construction.
   type SMS_State is record
      Stations       : Loadout;
      Mode           : Release_Mode := CCIP;
      Rpl_Qty        : Ripple_Qty   := 1;
      Rpl_Int        : Interval_Ms  := 100;
      Arm            : Master_Arm   := Safe;
      Employ         : Employ_Mode  := AG;
      Jett_Armed     : Boolean      := False;
      Pending_Active : Boolean      := False;  --  CCRP release armed
      Pending_Qty    : Natural      := 0;
      Burst          : Burst_Record;
      Adv_Count      : Natural      := 0;
      Advisories     : Message_List;
      Eff_Count      : Natural      := 0;
      Effects        : Message_List;  --  release effects emitted this Apply
   end record;

   --  ---------------------------------------------------------------------
   --  Input events (S 9 catalog) as a tagged union.
   --  ---------------------------------------------------------------------

   type Event_Kind is
     (Load_Store, Store_Removed, Station_Select, Step, Mode_Cycle,
      Ripple_Qty_Inc, Ripple_Int_Inc, Fuze_Cycle, Master_Arm_Set,
      Employ_Mode_Toggle, Jettison_Arm, Jettison_Confirm, Release_Command,
      Release_Point_Reached, Release_Pulse_Done);

   type Input_Event (Kind : Event_Kind := Mode_Cycle) is record
      case Kind is
         when Load_Store =>
            L_Station : Station_Id;
            L_Type    : Store_Type;
            L_Qty     : Quantity;
            L_Fuze    : Fuze_Type := NA;
         when Store_Removed | Station_Select =>
            Station : Station_Id;
         when Master_Arm_Set =>
            Arm_Value : Master_Arm;
         when Release_Command =>
            Pressed : Boolean;
         when Release_Pulse_Done =>
            P_Station : Station_Id;
         when others =>
            null;
      end case;
   end record;

   --  Event constructors (readability helpers).
   function Ev_Load
     (Station : Station_Id; T : Store_Type; Qty : Quantity;
      F : Fuze_Type := NA) return Input_Event;
   function Ev_Remove (Station : Station_Id) return Input_Event;
   function Ev_Select (Station : Station_Id) return Input_Event;
   function Ev_Step return Input_Event;
   function Ev_Mode_Cycle return Input_Event;
   function Ev_Qty_Inc return Input_Event;
   function Ev_Int_Inc return Input_Event;
   function Ev_Fuze_Cycle return Input_Event;
   function Ev_Set_Arm (V : Master_Arm) return Input_Event;
   function Ev_Toggle_Employ return Input_Event;
   function Ev_Jett_Arm return Input_Event;
   function Ev_Jett_Confirm return Input_Event;
   function Ev_Release (Pressed : Boolean := True) return Input_Event;
   function Ev_Point_Reached return Input_Event;
   function Ev_Pulse_Done (Station : Station_Id) return Input_Event;

   --  ---------------------------------------------------------------------
   --  Core reducer and starting states
   --  ---------------------------------------------------------------------

   --  Total reducer. Never raises; invalid events are no-ops + advisory.
   function Apply (State : SMS_State; Event : Input_Event) return SMS_State;

   --  Power-on default: all stations empty, SAFE / AG / CCIP (Appendix B).
   function Initial_State return SMS_State;

   --  The S 8.3 sample instance, also the worked-example starting state.
   function Sample_State return SMS_State;

   --  ---------------------------------------------------------------------
   --  Pushbutton dispatch (S 4.3 legend map). Maps a physical DDI button to
   --  the event it raises in the current state (handles MARM/MODE cycling and
   --  the JETT arm/confirm two-press behavior). Inert buttons are no-ops.
   --  ---------------------------------------------------------------------

   subtype PB_Index is Positive range 1 .. 20;
   function Press (State : SMS_State; PB : PB_Index) return SMS_State;

   --  ---------------------------------------------------------------------
   --  Queries (for renderer and for an external pulse driver)
   --  ---------------------------------------------------------------------

   function Is_Selected (State : SMS_State; S : Station_Id) return Boolean;
   function Selection_Count (State : SMS_State) return Natural;
   function Burst_In_Progress (State : SMS_State) return Boolean;
   function Pending_CCRP (State : SMS_State) return Boolean;

   --  The single station currently in RELEASING (0 if none). The external
   --  pulse driver feeds back Ev_Pulse_Done for this station after the ripple
   --  interval to advance the burst.
   function Releasing_Station (State : SMS_State) return Natural;

   --  Per-type helpers (also used by the renderer / loadout validation).
   function Max_Quantity (T : Store_Type) return Quantity;
   function Default_Fuze (T : Store_Type) return Fuze_Type;
   function Is_Bomb (T : Store_Type) return Boolean;
   function Selectable (Item : Store; Employ : Employ_Mode) return Boolean;
   function Compatible (Station : Station_Id; T : Store_Type) return Boolean;

end SMS;
