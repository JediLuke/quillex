defmodule QuillEx.GUI.Components.PlainText do
  use Scenic.Component
  alias Widgex.Structs.Frame

  # Define the struct for PlainText
  # We could have 2 structs, one which is the state, and one which is the component
  # instead of defstruct macro, use like defwidget or defcomponent
  defstruct text: nil

  # Validate function to ensure proper parameters are being passed.
  def validate({%__MODULE__{text: text} = state, %Frame{} = frame}) when is_binary(text) do
    {:ok, {state, frame}}
  end

  def init(scene, {%__MODULE__{} = state, %Frame{} = frame}, _opts) do
    init_graph = render(state, frame)
    new_scene = scene |> assign(graph: init_graph) |> push_graph(init_graph)

    {:ok, new_scene}
  end

  # def handle_info(:redraw, scene) do
  #   new_graph = render(%{text: scene.assigns.text, frame: scene.assigns.frame})

  #   new_scene = scene |> assign(graph: new_graph) |> push_graph(new_graph)
  #   {:noreply, new_scene}
  # end

  # TODO apply scissor
  def render(%__MODULE__{text: text}, %Frame{} = frame) when is_binary(text) do
    Scenic.Graph.build()
    |> Scenic.Primitives.group(
      fn graph ->
        graph |> Scenic.Primitives.text(text, font: :ibm_plex_mono, t: {0, 24})
      end,
      id: :plain_text
      # translate: frame.pin
    )
  end
end
