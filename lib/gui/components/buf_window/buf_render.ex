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
    colors = @cauldron

    data = if buf.data == [], do: [@no_limits_to_tomorrow], else: buf.data

    font_size = 24
    font_name = :ibm_plex_mono
    font_metrics = Flamelex.Fluxus.RadixStore.get().fonts.ibm_plex_mono.metrics
    ascent = FontMetrics.ascent(font_size, font_metrics)

    font = %{
      name: font_name,
      size: font_size,
      ascent: ascent,
      metrics: font_metrics
    }

    Scenic.Graph.build()
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        |> Draw.background(frame, colors.slate)
        |> render_text(frame, data, font, colors)
        |> render_cursor(frame, buf, :start_of_buffer, font, colors)

        # |> Quillex.GUI.Component.Buffer.CursorCaret.add_to_graph(
        #   %{
        #     buffer_uuid: buf.uuid,
        #     coords: {10, 10},
        #     # height: font_size,
        #     mode: :cursor,
        #     font: font
        #   },
        #   id: :cursor
        # )
      end,
      # TODO apply scissor
      translate: frame.pin.point
    )
  end

  def render_cursor(
        %Scenic.Graph{} = graph,
        %Widgex.Frame{} = frame,
        %Quillex.Structs.Buffer{} = buf,
        # coords,
        :start_of_buffer,
        # height,
        font,
        colors
      ) do
    graph
    |> Quillex.GUI.Component.Buffer.CursorCaret.add_to_graph(
      %{
        buffer_uuid: buf.uuid,
        coords: {10, 10},
        height: font.size,
        mode: :cursor,
        font: font
      },
      id: :cursor
    )
  end

  def render_text(
        %Scenic.Graph{} = graph,
        %Widgex.Frame{} = frame,
        lines,
        font,
        colors
      )
      when is_list(lines) do
    # Enum.reduce(lines, graph, fn line, graph_acc ->
    #   graph_acc
    #   |> Scenic.Primitives.text(
    #     line,
    #     font_size: font_size,
    #     font: font_name,
    #     fill: colors.text,
    #     translate: {10, ascent + 10}
    #   )
    #   |> Map.update!(:translate, fn {x, y} -> {x, y + font_size} end)
    # end)

    # TODO maybe send it a list of lines instead? Do the rope calc here??

    # this is the very direct method, the way above is actually
    # treating the rendering of each line as a separate operation,
    # which is probably the way to go
    graph
    |> Scenic.Primitives.text(
      convert_lines_to_text(lines),
      font_size: font.size,
      font: font.name,
      fill: colors.text,
      translate: {10, font.ascent + 10}
    )
  end

  defp convert_lines_to_text(lines) when is_list(lines) do
    Enum.join(lines, "\n")
  end
end
