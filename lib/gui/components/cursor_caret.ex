defmodule Quillex.GUI.Component.Buffer.CursorCaret do
  use Scenic.Component
  require Logger

  # Width of the cursor in pixels
  @cursor_width 2
  # Blink interval in milliseconds
  @blink_interval 500
  # Supported cursor modes
  @valid_modes [:cursor, :block]
  # The fill color of the cursor
  @color :black

  # Validate the data passed to the component
  def validate(%{coords: _coords, height: _height, mode: mode, buffer_uuid: _uuid} = data)
      when mode in @valid_modes do
    {:ok, data}
  end

  # Initialize the component
  def init(scene, args, _opts) do
    # Extract initial position and mode
    %{coords: {x_pos, y_pos}, height: height, mode: mode, font: font} = args

    # Build the initial graph
    graph =
      Scenic.Graph.build()
      |> Scenic.Primitives.group(
        fn graph ->
          graph
          |> Scenic.Primitives.rect(
            {calc_width(mode, font), height},
            id: :cursor_rect,
            fill: @color
          )
        end,
        id: :cursor,
        translate: {x_pos, y_pos}
      )

    # Start the blinking timer
    {:ok, timer} = :timer.send_interval(@blink_interval, :blink)

    # Capture keyboard input events
    # scene = capture_input(scene, [:key])

    Flamelex.Lib.Utils.PubSub.subscribe(topic: {:buffers, args.buffer_uuid})

    # Assign initial state
    scene =
      scene
      |> assign(graph: graph)
      |> assign(x_pos: x_pos)
      |> assign(y_pos: y_pos)
      |> assign(height: height)
      |> assign(mode: mode)
      |> assign(font: font)
      # Cursor is initially visible
      |> assign(visible: true)
      |> assign(timer: timer)
      |> assign(char_width: FontMetrics.width("W", font.size, font.metrics))
      |> push_graph(graph)

    {:ok, scene}
  end

  # Handle blinking
  def handle_info(:blink, %{assigns: %{visible: visible, graph: graph}} = scene) do
    # Toggle visibility
    new_visible = !visible

    # Update the graph
    graph =
      graph
      |> Scenic.Graph.modify(
        :cursor_rect,
        &Scenic.Primitives.update_opts(&1, hidden: !new_visible)
      )

    # Update the scene
    scene =
      scene
      |> assign(visible: new_visible)
      |> assign(graph: graph)
      |> push_graph(graph)

    {:noreply, scene}
  end

  def handle_info({:user_input_fwd, _iid}, scene) do
    # ignore user input in this component for now since input
    # needs to get routed through the parent component
    {:noreply, scene}
  end

  def handle_info({:move_cursor, direction, _x}, scene) do
    move_cursor(scene, direction)
  end

  # # Handle input events
  # def handle_input({:key, {:key_left, 1, _}}, _context, scene) do
  #   move_cursor(scene, :left)
  # end

  # def handle_input({:key, {:key_right, 1, _}}, _context, scene) do
  #   move_cursor(scene, :right)
  # end

  # def handle_input({:key, {:key_up, 1, _}}, _context, scene) do
  #   move_cursor(scene, :up)
  # end

  # def handle_input({:key, {:key_down, 1, _}}, _context, scene) do
  #   move_cursor(scene, :down)
  # end

  # Ignore other keys
  # def handle_input(_input, _context, scene) do
  #   {:noreply, scene}
  # end

  # Helper function to move the cursor
  defp move_cursor(scene, direction) do
    %{
      assigns: %{x_pos: x_pos, y_pos: y_pos, char_width: char_width, height: height, graph: graph}
    } = scene

    {new_x, new_y} =
      case direction do
        :left -> {x_pos - char_width, y_pos}
        :right -> {x_pos + char_width, y_pos}
        :up -> {x_pos, y_pos - height}
        :down -> {x_pos, y_pos + height}
      end

    # Update the graph
    graph =
      graph
      |> Scenic.Graph.modify(
        :cursor,
        &Scenic.Primitives.update_opts(&1, translate: {new_x, new_y})
      )

    # Update the scene
    scene =
      scene
      |> assign(x_pos: new_x)
      |> assign(y_pos: new_y)
      |> assign(graph: graph)
      |> push_graph(graph)

    {:noreply, scene}
  end

  # Helper function to calculate the width of the cursor based on the mode
  defp calc_width(:cursor, _font), do: @cursor_width

  defp calc_width(:block, font) do
    FontMetrics.width("W", font.size, font.metrics)
  end
end
