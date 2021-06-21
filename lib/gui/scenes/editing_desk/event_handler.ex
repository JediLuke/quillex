defmodule QuillEx.Scene.EditingDesk.EventHandler do
   @moduledoc false
   require Logger
   alias QuillEx.ScenicComponent.{EmeraldTablet, MenuBar}
   alias QuillEx.Utils


   def filter_event({:menubar, {:click, :new_file}}, _from, %{buffer_list: []} = state) do
      # User clicks the MenuBar button to open a new file
      # when we have no currently open buffers

      new_buffer_list = [
         %{
            title: "untitled",
            saved?: false,
            lines: [""],
            path: nil
         }
      ]

      active_buffer = 0 # first entry in the buffer_list, indexed at 0 because that's what Enum wants

      #TODO this graph doesn't have tabs to open multiple files (yet!)
      #TODO much more-betterer would be to update the existing Graph, but
      #     this seems like maybe something you might have to do at the
      #     ViewPort level...
      #     I guess one nice thing about re-generating everything all the
      #     time is the inherent simplicity of doing it, and the robustness
      #     that comes from a program which is designed to be generated from
      #     a state, rather than mutating what's already there
      new_graph =
         Scenic.Graph.build()
         |> EmeraldTablet.add_to_graph(
               [""],
               id: {:slate, 1},
               width: Utils.vp_width(state.viewport),
               height: Utils.vp_height(state.viewport) - MenuBar.height(),
               translate: {0, MenuBar.height()})
         |> MenuBar.add_to_graph()

      new_state =
         state
         |> Map.replace!(:graph, new_graph)
         |> Map.replace!(:buffer_list, new_buffer_list)
         |> Map.replace!(:active_buffer, active_buffer)

      {:noreply, new_state, push: new_state.graph}
   end


   def filter_event({:menubar, {:click, :new_file}}, _from, state) do
      Logger.warn "Unable to open a new blank file."
      {:noreply, state}
   end


   def filter_event(event, _from, state) do
      Logger.warn "Ignoring event: #{inspect event}"
      {:halt, state} #REMINDER: `:halt` just means, don't propagate the event any further
   end
end