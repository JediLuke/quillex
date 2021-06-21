defmodule QuillEx.Scene.EditingDesk.InputHandler do
   @moduledoc false
   require Logger

   @ignored_inputs [:cursor_pos, :cursor_exit, :cursor_enter, :cursor_button]

   def handle_input({i, _coords}, _context, state) when i in @ignored_inputs do
      {:noreply, state}
   end


   def handle_input(input, _context, state) do
      Logger.warn "Ignoring input: #{inspect input}"
      {:noreply, state}
   end
end