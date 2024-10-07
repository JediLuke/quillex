defmodule Quillex.GUI.Components.Buffer.Render do
  alias Quillex.GUI.Components.Buffer
  alias Flamelex.GUI.Utils.Draw

  @no_limits_to_tomorrow "~ The only limit to our realization of tomorrow is our doubts of today ~"
  # - Frankin D. Roosevelt

  @typewriter %{
    text: :black,
    slate: :white
  }

  @cauldron %{
    text: :white,
    slate: :medium_slate_blue
  }

  def go(%Widgex.Frame{} = frame, %Quillex.Structs.Buffer{} = buf) do
    Scenic.Graph.build() |> draw(frame, buf)
  end

  # The draw function that builds the graph and renders the buffer
  # TODO apply scissor, move to renbder module
  defp draw(%Scenic.Graph{} = graph, %Widgex.Frame{} = frame, buf) do
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
        # TODO maybe send it a list of lines instead? Do the rope calc here??
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
