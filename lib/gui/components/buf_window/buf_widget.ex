defmodule Quillex.GUI.Components.Buffer do
  use Scenic.Component
  alias Flamelex.GUI.Utils.Draw
  alias Scenic.Graph
  use ScenicWidgets.ScenicEventsDefinitions

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

  def validate(
        %{
          frame: %Widgex.Frame{} = f,
          buf_ref: %Quillex.Structs.Buffer.BufRef{} = buf_ref
        } = data
      ) do
    {:ok, data}
  end

  def init(scene, data, _opts) do
    # TODO this would be a cool place to do something better here...
    {:ok, %Quillex.Structs.Buffer{} = buf} = GenServer.call(data.buf_ref.pid, :get_state)
    # buf = Flamelex.Fluxus.RadixStore.get().apps.qlx_wrap.buffers |> List.first()

    graph =
      Scenic.Graph.build()
      |> draw(data.frame, buf)

    init_scene =
      scene
      |> assign(frame: data.frame)
      |> assign(graph: graph)
      |> assign(state: buf)
      |> push_graph(graph)

    # TODO I _think_ this will register the GUI widget the same way we register the actual Buffer process
    Registry.register(Quillex.BufferRegistry, {data.buf_ref.uuid, __MODULE__}, nil)

    Quillex.Utils.PubSub.subscribe(topic: {:buffers, buf.uuid})

    {:ok, init_scene}
  end

  # a convenience function to make it easy to forward user input to the GUI component
  def fwd_input(%Quillex.Structs.Buffer.BufRef{} = buf_ref, input) do
    case Registry.lookup(Quillex.BufferRegistry, {buf_ref.uuid, __MODULE__}) do
      [{pid, _meta}] ->
        send(pid, {:user_input_fwd, input})

      [] ->
        raise "Could not find GUI component for buffer: #{inspect(buf_ref)}"
    end
  end

  def handle_info({:user_input_fwd, @right_arrow}, %{assigns: %{state: %{mode: :edit}}} = scene) do
    # todo here should convert input to actions, then broascast actions to do on the pubsub
    # ignore user input in the actual Buffer process, wait for the GUI to convert it to actions

    {:ok, [cursor_pid]} = Scenic.Scene.child(scene, :cursor)
    GenServer.cast(cursor_pid, {:move_cursor, :right, 1})

    {:noreply, scene}
  end

  def handle_info({:user_input_fwd, _input}, scene) do
    # todo here should convert input to actions, then broascast actions to do on the pubsub
    # ignore user input in the actual Buffer process, wait for the GUI to convert it to actions
    {:noreply, scene}
  end

  # TODO
  # def handle_cast({:frame_reshape, new_frame}, scene)

  #   def handle_cast(
  #         {:scroll_limits, %{inner: %{width: _w, height: _h}, frame: _f} = new_scroll_state},
  #         scene
  #       ) do
  #     # update the RadixStore, without broadcasting the changes,
  #     # so we can keep accurate calculations for scrolling
  #     radix_store(scene)

  #     radix_store(scene).get()
  #     |> radix_reducer(scene).change_editor_scroll_state(new_scroll_state)
  #     |> radix_store(scene).put()

  #     {:noreply, scene}
  #   end

  # The draw function that builds the graph and renders the buffer
  # TODO apply scissor, move to renbder module
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
