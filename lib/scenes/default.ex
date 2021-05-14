defmodule QuillEx.Scene.Default do
  use Scenic.Scene
  alias QuillEx.Scenic.Component.MenuBar


  def init(_, opts) do

    graph =
      Scenic.Graph.build()
      |> MenuBar.add_to_graph()

    state = %{
      graph: graph,
      viewport: opts[:viewport]
    }

    {:ok, state, push: graph}
  end
end
