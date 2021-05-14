defmodule QuillEx.Scene.SingleFile do
    use Scenic.Scene
    alias Scenic.ViewPort
    alias QuillEx.Utils
    alias QuillEx.Scenic.Component.MenuBar
    import Scenic.Primitives
    import Scenic.Components
    import QuillEx.Scenic.Component.TextPad, only: [{:text_pad, 3}]
    require Logger
  

    def init(state, opts) do
      
      graph =
        Scenic.Graph.build()
        |> text_pad(
            ["This is is", "the first text we render."],
            id: :pad,
            width: Utils.vp_width(opts[:viewport]),
            height: Utils.vp_height(opts[:viewport]))
        |> MenuBar.add_to_graph()
  
      state = %{
        viewport: opts[:viewport],
        graph: graph,
        files: [%{title: "untitled", saved?: false}]
      }
  
      {:ok, state, push: graph}
    end
  

    def handle_input(event, _context, state) do
        Logger.info("Received event: #{inspect(event)}")
        {:noreply, state}
    end
    
    
    def filter_event(e, _from, state) do
        IO.puts("Sample button was clicked! #{inspect e}")
        {:noreply, state}
    end
end
  