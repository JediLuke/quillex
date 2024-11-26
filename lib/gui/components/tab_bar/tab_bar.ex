defmodule Quillex.GUI.Components.TabBar do
  use Scenic.Component

  def validate(
    %{
      frame: %Widgex.Frame{} = _f,
      state: %{
        tabs: t_list
      }
    } = data
  ) when is_list(t_list) do
    {:ok, data}
  end


  def init(scene, %{frame: frame, state: state}, _opts) do
    graph =
      Scenic.Graph.build()
      |> Scenic.Primitives.rect(
        frame.size.box,
        id: :tab_bar,
        fill: :grey,
        translate: frame.pin.point,
        hidden: length(state.tabs) <= 1
      )

    scene =
      scene
      |> assign(state: state)
      |> assign(graph: graph)
      |> push_graph(graph)

    #TODO this might actually cause problems if we end up with multi9ple BGufferPanes open with different tab bars...
    Process.register(self(), __MODULE__)

    {:ok, scene}
  end

  def handle_cast({:state_change, new_state}, scene) do

    if new_state.tabs == scene.assigns.state.tabs do
      {:noreply, scene}
    else
      hide_tabs? = length(new_state.tabs) <= 1

      new_graph = scene.assigns.graph
      |> Scenic.Graph.modify(:tab_bar, &Scenic.Primitives.update_opts(&1, hidden: hide_tabs?))

      new_scene =
        scene
        |> assign(state: new_state)
        |> assign(graph: new_graph)
        |> push_graph(new_graph)

      {:noreply, new_scene}
    end
  end
end
