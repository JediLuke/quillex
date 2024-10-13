defmodule Quillex.GUI.Components.Buffer do
  use Scenic.Component
  use ScenicWidgets.ScenicEventsDefinitions

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

    graph = Quillex.GUI.Components.Buffer.Render.go(data.frame, buf)

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

  def handle_info({:user_input_fwd, input}, scene) do
    # todo here should convert input to actions, then broascast actions to do on the pubsub
    # ignore user input in the actual Buffer process, wait for the GUI to convert it to actions

    case Quillex.GUI.Components.Buffer.UserInputHandler.handle(scene, input) do
      :ignore ->
        {:noreply, scene}

      actions when is_list(actions) ->
        # process_actions(scene, actions)
        IO.puts("NEED TO HANDLE #{inspect(actions)}")
        {:noreply, scene}
        # new_rdx =
        #   Enum.reduce(actions, rdx, fn action, rdx_acc ->
        #     case Flamelex.Fluxus.RadixReducer.process(rdx_acc, action) do
        #       :ignore ->
        #         :ignore

        #       new_rdx ->
        #         new_rdx
        #     end
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
end
