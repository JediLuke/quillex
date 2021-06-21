defmodule QuillEx.Scene.EditingDesk do
   use Scenic.Scene


   def init(_, opts) do

      graph =
         Scenic.Graph.build()
         |> QuillEx.ScenicComponent.MenuBar.add_to_graph()

      #NOTE: This process holds the root state of the *entire application*

      state = %{
         graph: graph,               # the %Scenic.Graph{} currenly being rendered
         viewport: opts[:viewport],
         buffer_list: [],            # holds a reference to each open buffer
         active_buffer: nil,         # holds a reference to the `active` buffer
      }

      {:ok, state, push: graph}
   end


   def filter_event(event, from, state) do
      # it just gets cluttered trying to keep all this logic in this module...
      QuillEx.Scene.EditingDesk.EventHandler.filter_event(event, from, state)
   end


   def handle_input(input, context, state) do
      # it just gets cluttered trying to keep all this logic in this module...
      QuillEx.Scene.EditingDesk.InputHandler.handle_input(input, context, state)
   end
end