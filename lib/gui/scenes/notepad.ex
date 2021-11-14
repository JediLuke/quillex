defmodule QuillEx.Scene.NotePad do
  use Scenic.Scene
  require Logger

  @init_graph Scenic.Graph.build()
  |> Scenic.Primitives.rect({10, 10}, translate: {10, 10}, fill: :red)

  def init(scene, _params, _opts) do
    Logger.debug "#{__MODULE__} initializing..."

    new_scene = scene
    |> assign(graph: @init_graph)
    |> push_graph(@init_graph)

    {:ok, new_scene}
  end
end