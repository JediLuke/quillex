# TODO rename to BufrWindow
defmodule Quillex.GUI.Components.Buffer do
  use Scenic.Component
  use ScenicWidgets.ScenicEventsDefinitions
  alias Quillex.GUI.Components.Buffer

  @no_limits_to_tomorrow "~ The only limit to our realization of tomorrow is our doubts of today ~"
  # - Frankin D. Roosevelt

  def validate(
        %{
          frame: %Widgex.Frame{} = f,
          buf_ref: %Quillex.Structs.Buffer.BufRef{} = buf_ref
        } = data
      ) do
    {:ok, data}
  end

  @cauldron %{
    text: :white,
    slate: :medium_slate_blue
  }

  def init(scene, data, _opts) do
    # TODO this would be a cool place to do something better here...
    # I'm going to keep experimenting with this, I think it's more in-keeping
    # with the Zen of scenic to go and fetch state upon our boot, since that
    # keeps the integrity our gui thread even if the external data sdource if bad,
    # plus I think it's more efficient in terms of data transfer to just get it once rather than pass it around everywhere (maybe?)
    {:ok, %Quillex.Structs.Buffer{} = buf} = GenServer.call(data.buf_ref.pid, :get_state)

    # this dissapears after you type or do something, but I like it! It's magical!
    buf =
      if buf.data == [] do
        buf
        |> Buffer.Mutator.insert_text({1, 1}, "#{@no_limits_to_tomorrow}")
      else
        buf
      end

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

    colors = @cauldron

    graph = Buffer.Render.go(data.frame, buf, font, colors)

    init_scene =
      scene
      |> assign(frame: data.frame)
      |> assign(graph: graph)
      |> assign(state: buf)
      |> assign(font: font)
      |> assign(colors: colors)
      |> push_graph(graph)

    register_process(data.buf_ref)

    {:ok, init_scene}
  end

  def register_process(buf_ref) do
    # this will register the GUI widget the same way we register the actual Buffer process
    Registry.register(Quillex.BufferRegistry, {buf_ref.uuid, __MODULE__}, nil)
  end

  def handle_info({:user_input_fwd, input}, scene) do
    # the GUI component converts raw user input to actions,
    # which are then passed back up the component tree for processing
    case Buffer.UserInputHandler.handle(scene.assigns.state, input) do
      :ignore ->
        {:noreply, scene}

      actions ->
        # TODO consider remembering & passing back the %BufRef{} here, though this gets the job done
        cast_parent(scene, {:gui_action, %{uuid: scene.assigns.state.uuid}, actions})
        {:noreply, scene}
    end
  end

  def handle_info({:state_change, new_state}, %{assigns: %{state: old_state}} = scene) do
    # when the Buffer process state changes, we update the GUI component

    # TODO this will work but I want to figure out how to do it without re-rendering & restarting new components all the time!!

    # TODO somehow we want to resist re-rendering all the time, we should mutate instead
    # by pushing input events down to the lowest level that can handle them

    new_scene =
      scene
      #   |> process_name_changes(scene.assigns.state)
      |> Buffer.Render.process_text_changes(new_state)
      |> Buffer.Render.process_cursor_changes(new_state)
      |> assign(state: new_state)

    # TODO maybe this will work, to optimize not calling push_graph? if new_scene.assigns.graph != scene.assigns.graph do
    new_scene = push_graph(new_scene, new_scene.assigns.graph)

    {:noreply, new_scene}
  end
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
