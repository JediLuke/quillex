defmodule Quillex.GUI.Components.Buffer do
  use Scenic.Component
  use ScenicWidgets.ScenicEventsDefinitions
  alias Quillex.GUI.Components.Buffer

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
    # I'm going to keep experimenting with this, I think it's more in-keeping
    # with the Zen of scenic to go and fetch state upon our boot, since that
    # keeps the integrity our gui thread even if the external data sdource if bad,
    # plus I think it's more efficient in terms of data transfer to just get it once rather than pass it around everywhere (maybe?)
    {:ok, %Quillex.Structs.Buffer{} = buf} = GenServer.call(data.buf_ref.pid, :get_state)

    graph = Buffer.Render.go(data.frame, buf)

    init_scene =
      scene
      |> assign(frame: data.frame)
      |> assign(graph: graph)
      |> assign(state: buf)
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

    # states = %{new: new_state, old: old_state}

    new_scene =
      scene
      #   |> process_name_changes(scene.assigns.state)
      #   |> process_text_changes(old_state.data, new_state.data)
      |> Buffer.Render.process_cursor_changes(new_state)
      |> assign(state: new_state)

    # graph = Quillex.GUI.Components.Buffer.Render.go(scene.assigns.frame, new_state)

    # new_scene =
    #   scene
    #   |> assign(graph: graph)
    #   |> assign(state: new_state)

    if new_scene.assigns.graph != scene.assigns.graph do
      push_graph(new_scene, new_scene.assigns.graph)
    end

    {:noreply, new_scene}

    # new_scene =
    #   scene
    #   |> assign(graph: graph)
    #   |> assign(state: new_state)
    #   |> push_graph(graph)

    {:noreply, new_scene}
  end

  # def fwd_actions(buf, actions) do
  #   IO.puts("FWDING ACTIONS: #{inspect(actions)}")

  #   case Registry.lookup(Quillex.BufferRegistry, {buf.uuid, Quillex.Buffer}) do
  #     [{pid, _meta}] ->
  #       send(pid, {:action, actions})

  #     [] ->
  #       raise "Could not find Buffer process for buffer: #{inspect(buf)}"
  #   end
  # end
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

#   # # TODO somehow we want to resist re-rendering all the time, we should mutate instead
#   # # by pushing input events down to the lowest level that can handle them
