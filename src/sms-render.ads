--  Text renderer for the STORES DDI format (S 4). Pure function of the model:
--  Page (State) -> screen text. The renderer never mutates state.

package SMS.Render is

   --  Full STORES page as a multi-line string.
   function Page (State : SMS_State) return String;

   --  Convenience: render and print to standard output.
   procedure Put_Page (State : SMS_State);

end SMS.Render;
