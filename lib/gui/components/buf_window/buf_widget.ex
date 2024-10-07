defmodule Quillex.GUI.Components.Buffer do
  use Scenic.Component
  alias Flamelex.GUI.Utils.Draw
  alias Scenic.Graph

  @no_limits_to_tomorrow "~ The only limit to our realization of tomorrow is our doubts of today ~"

  @typewriter %{
    text: :black,
    slate: :white
  }

  @cauldron %{
    text: :white,
    slate: :medium_slate_blue
  }

  def validate(
        %{frame: %Widgex.Frame{} = f, buf_ref: %Quillex.Structs.Buffer.BufRef{} = buf_ref} = data
      ) do
    # go fetch the bu

    # {:ok, %{frame: f, state: buf}}
    {:ok, data}
  end

  # def validate(_), do: :invalid_data

  # @impl Scenic.Component
  # def init(%{frame: frame, state: buf_ref} = data, opts) do
  #   graph = draw(Graph.build(), frame, buf_ref)

  #   # You can add custom initialization logic here if necessary.
  #   {:ok, %{graph: graph, frame: frame, buf_ref: buf_ref}, push: graph}
  # end

  def init(
        scene,
        # %{frame: %Widgex.Frame{} = frame, state: %Quillex.Structs.Buffer{} = buf},
        data,
        _opts
      ) do
    {:ok, %Quillex.Structs.Buffer{} = buf} = GenServer.call(data.buf_ref.pid, :get_state)
    # TODO this would be a cool place to do something better here...
    # buf = Flamelex.Fluxus.RadixStore.get().apps.qlx_wrap.buffers |> List.first()

    graph =
      Scenic.Graph.build()
      |> draw(data.frame, buf)

    # |> BufferWidget.add_to_graph(%{frame: data.frame, buf_ref: data.buf_ref})

    init_scene =
      scene
      |> assign(frame: data.frame)
      |> assign(graph: graph)
      |> assign(state: buf)
      |> push_graph(graph)

    Quillex.Utils.PubSub.subscribe(topic: {:buffers, buf.uuid})

    {:ok, init_scene}
  end

  # The draw function that builds the graph and renders the buffer
  defp draw(%Graph{} = graph, %Widgex.Frame{} = frame, buf) do
    # Fetch the text from the buffer, for now use default placeholder text
    text = @no_limits_to_tomorrow
    font_size = 24
    font_name = :ibm_plex_mono

    # Fetch font metrics (this could be passed into the state)
    font_metrics = Flamelex.Fluxus.RadixStore.get().fonts.ibm_plex_mono.metrics
    ascent = FontMetrics.ascent(font_size, font_metrics)

    font = %{
      name: font_name,
      size: font_size,
      metrics: font_metrics
    }

    colors = @cauldron

    # Build the graph for rendering
    graph
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        |> Draw.background(frame, colors.slate)
        |> Scenic.Primitives.text(
          text,
          font_size: font_size,
          font: font_name,
          fill: colors.text,
          translate: {10, ascent + 10}
        )
        |> Quillex.GUI.Component.Buffer.CursorCaret.add_to_graph(
          %{
            buffer_uuid: buf.uuid,
            coords: {10, 10},
            height: font_size,
            mode: :cursor,
            font: font
          },
          id: :cursor
        )
      end,
      translate: frame.pin.point
    )
  end
end

# defmodule Quillex.GUI.Components.Buffer do
#   alias Flamelex.GUI.Utils.Draw

#   @no_limits_to_tomorrow "~ The only limit to our realization of tomorrow is our doubts of today ~"

#   @typewriter %{
#     text: :black,
#     slate: :white
#   }

#   @cauldron %{
#     text: :white,
#     slate: :medium_slate_blue
#   }

#   def draw(
#         %Scenic.Graph{} = graph,
#         %Widgex.Frame{} = frame,
#         %Quillex.Structs.Buffer.BufRef{} = buf_ref
#       ) do
#     # TODO fetch the text from the buffer anbd render it
#     text = @no_limits_to_tomorrow
#     font_size = 24
#     font_name = :ibm_plex_mono

#     # TODO this is a little cheeky, should pass it through via the state somehow...
#     font_metrics = Flamelex.Fluxus.RadixStore.get().fonts.ibm_plex_mono.metrics
#     ascent = FontMetrics.ascent(font_size, font_metrics)

#     font = %{
#       name: font_name,
#       size: font_size,
#       metrics: font_metrics
#     }

#     colors = @cauldron

#     graph
#     |> Scenic.Primitives.group(
#       fn graph ->
#         graph
#         |> Draw.background(frame, colors.slate)
#         |> Scenic.Primitives.text(
#           text,
#           font_size: font_size,
#           font: font_name,
#           fill: colors.text,
#           translate: {10, ascent + 10}
#           # translate: {10, 10}
#         )
#         |> Quillex.GUI.Component.Buffer.CursorCaret.add_to_graph(
#           %{
#             buffer_uuid: buf_ref.uuid,
#             coords: {10, 10},
#             height: font_size,
#             mode: :cursor,
#             font: font
#           },
#           id: :cursor
#         )
#       end,
#       translate: frame.pin.point
#     )
#   end
# end
