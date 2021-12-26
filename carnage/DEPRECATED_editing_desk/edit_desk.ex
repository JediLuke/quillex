# defmodule QuillEx.Scene.EditDesk do
#    use Scenic.Scene

#    import Scenic.Primitives
#    import Scenic.Components
#          # graph =
#       #    Scenic.Graph.build()
#          # |> QuillEx.ScenicComponent.MenuBar.add_to_graph()

#       #NOTE: This process holds the root state of the *entire application*

#       # state = %{
#       #    graph: graph,               # the %Scenic.Graph{} currenly being rendered
#       #    viewport: opts[:viewport],
#       #    buffer_list: [],            # holds a reference to each open buffer
#       #    active_buffer: nil,         # holds a reference to the `active` buffer
#       # }

#    @graph Scenic.Graph.build()
#             |> group( fn graph ->
#             graph
#             |> text( "Count: " <> inspect(@initial_count), id: :count )
#             |> button( "Click Me", id: :btn, translate: {0, 30} )
#             end,
#             translate: {100, 100}
#           )

#    defp graph(), do: @graph

#    # def init(scene, _, opts) do

#    #    new_graph =
#    #       Scenic.Graph.build()
#    #       |> Scenic.Primitives.rect({400, 400}, translate: {10, 10}, fill: :cornflower_blue, stroke: {1, :ghost_white})

#    #    scene
#    #    |> push_graph(new_graph)

#    #    {:ok, scene}
#    # end

#    def init(scene, _params, _opts) do
#       scene =
#         scene
#         |> assign( count: 0 )
#         |> push_graph( graph() )

#       capture_input(scene, [:key])
#       {:ok, scene}
#     end


#    # def filter_event(event, from, state) do
#    #    # it just gets cluttered trying to keep all this logic in this module...
#    #    QuillEx.Scene.EditingDesk.EventHandler.filter_event(event, from, state)
#    # end

#    @impl Scenic.Scene
#   def handle_event({:click, :btn}, _, %{assigns: %{count: count}} = scene ) do
#     count = count + 1

#     # modify the graph to show the current click count
#     graph =
#       graph()
#       |> Scenic.Graph.modify(:count, &text(&1, "Count: " <> inspect(count)))

#     # update the count and push the modified graph
#     scene =
#       scene
#       |> assign( count: count )
#       |> push_graph( graph )

#     # return the updated scene
#     { :noreply, scene }
#   end


#    def handle_input(input, context, scene) do
#       IO.puts "GETTING INPUT!"
#       # it just gets cluttered trying to keep all this logic in this module...
#       # QuillEx.Scene.EditingDesk.InputHandler.handle_input(input, context, state)
#       {:noreply, scene}
#    end
# end