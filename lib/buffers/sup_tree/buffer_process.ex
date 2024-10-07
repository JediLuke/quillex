defmodule Quillex.Buffer.Process do
  @moduledoc """
  This is the _actual buffer_ process, which runs not as part
  of the GUI, it runs under the Buffer SUpervision tree.
  """
  use GenServer
  use ScenicWidgets.ScenicEventsDefinitions
  # alias Quillex.Structs.Buffer

  # TODO this is the way... combine the buffer & the component!!
  # NOTE that didnt go so well actually... but good try
  # use Scenic.Component
  # @behaviour Scenic.Component
  # use Scenic.Scene

  def start_link(%Quillex.Structs.Buffer{} = buf) do
    GenServer.start_link(__MODULE__, buf, name: via_tuple({buf.uuid, __MODULE__}))
  end

  def init(%Quillex.Structs.Buffer{} = buf) do
    Quillex.Utils.PubSub.subscribe(topic: {:buffers, buf.uuid})
    {:ok, _state = buf}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_info({:user_input_fwd, _input}, state) do
    # ignore user input in the actual Buffer process, wait for the GUI to convert it to actions
    {:noreply, state}
  end

  # def handle_cast({:user_input_fwd, input}, %{mode: :edit} = state) do
  #   # IO.puts("BUFFER GOT INPUT: #{inspect(input)}")

  #   # TODO use wormhole here
  #   case Quillex.GUI.Components.Buffer.UserInputHandler.handle(state, input) do
  #     :ignore ->
  #       {:noreply, state}

  #     :re_routed ->
  #       IO.puts("RE ROUTED #{inspect(input)}")
  #       {:noreply, state}

  #     actions when is_list(actions) ->
  #       IO.puts("SHOULD BE DOING: #{inspect(actions)}")

  #       case Quillex.GUI.Components.Buffer.Reducer.process_all(state, actions) do
  #         :ignore ->
  #           {:noreply, state}

  #         :re_routed ->
  #           {:noreply, state}

  #         %Quillex.Structs.Buffer{} = new_state ->
  #           # This ideally is where Scenic is able to go, no need to re-render if the state hasn't changed,
  #           # however at this point I dont know how to do it... we might need to diff
  #           # states or something very complex

  #           # for now we just try and make sure that anything which needs to be done
  #           # by a lower level component, gets L:re-routed to that component - this means
  #           # that the FluxBuffer state should only change when its probably necessary to
  #           # re-render anyway

  #           # if something needs to be managed on both levels e.g. the cursor position, maybe
  #           # throw 2 actions, one for the buffer, one for the component?? we'll see
  #           # new_graph = Render.go(scene.assigns.frame, new_state)

  #           notify_gui(new_state)

  #           {:noreply, new_state}
  #       end
  #   end
  # end

  def notify_gui(buf) do
    raise "dunno lol"
    Quillex.Utils.PubSub.broadcast(topic: {:buffers, buf.uuid}, msg: {:state_change, buf})
  end

  defp via_tuple(name), do: {:via, Registry, {Quillex.BufferRegistry, name}}
end

#         %Editor.State{} = new_state ->
#           new_state
#       end

#   # apply actions to the radix state in sequence to determine the new state
#   new_state =
#     actions
#     |> Enum.reduce(state, fn action, state_acc ->
#       case Editor.Reducer.process(state_acc, action) do
#         :ignore ->
#           state_acc

#         %Editor.State{} = new_state ->
#           new_state
#       end
#     end)

#   # This ideally is where Scenic is able to go, no need to re-render if the state hasn't changed,
#   new_graph = Render.go(scene.assigns.frame, new_state)

#   new_scene =
#     scene
#     |> assign(state: new_state)
#     |> push_graph(new_graph)

#   {:noreply, new_scene}

# def handle_info({:move_cursor, _dir, _x}, state) do
#   # sort of weird, we fire this event but also recv it, we just ignore it but cursor needs to catch it
#   {:noreply, state}
# end

# def insert_text(buffer_name, text) do
#   GenServer.cast(via_tuple(buffer_name), {:insert_text, text})
# end

# def move_cursor(buffer_name, direction) do
#   GenServer.cast(via_tuple(buffer_name), {:move_cursor, direction})
# end

# Helper to get the via tuple
# def handle_cast({:user_input_fwd, input}, %{assigns: %{state: state}} = scene) do
#   Logger.debug("Editor received input: #{inspect(input)}")

#   # user input handle returns a list of actions, which must be processed by the reducer
#   # maybe on the component level we don't bother with that... though I think it will be awesome for undo/redo etc!

#   # TODO use wormhole, abstract this out somewhere
#   case Editor.UserInputHandler.handle(state, input) do
#     :ignore ->
#       {:noreply, scene}

#     :re_routed ->
#       IO.puts("RE ROUTED #{inspect(input)}")
#       {:noreply, scene}

#     actions when is_list(actions) ->
#       # TODO this gets into a repeat of the previous problem... I want to apply the actions,
#       # but I DONT wnt to always re-render!!

#       # apply actions to the radix state in sequence to determine the new state
#       new_state =
#         actions
#         |> Enum.reduce(state, fn action, state_acc ->
#           case Editor.Reducer.process(state_acc, action) do
#             :ignore ->
#               state_acc

#             # :re_routed ->
#             #   state_acc

#             %Editor.State{} = new_state ->
#               new_state
#           end
#         end)

#       # This ideally is where Scenic is able to go, no need to re-render if the state hasn't changed,
#       new_graph = Render.go(scene.assigns.frame, new_state)

#       new_scene =
#         scene
#         |> assign(state: new_state)
#         |> push_graph(new_graph)

#       # cast_children(new_state.buffers)

#       {:noreply, new_scene}
#   end

#   # new_state = Editor.UserInputHandler.handle(state, input)

#   # # TODO somehow we want to resist re-rendering all the time, we should mutate instead
#   # # by pushing input events down to the lowest level that can handle them
#   # new_graph = Render.go(scene.assigns.frame, new_state)

#   # new_scene =
#   #   scene
#   #   |> assign(state: new_state)
#   #   |> push_graph(new_graph)

#   # {:noreply, new_scene}
# end

# def handle_cast({:insert_text, text}, state) do
#   # Update the buffer content and notify subscribers
#   new_state = %{state | content: state.content <> text}
#   notify_gui(new_state)
#   {:noreply, new_state}
# end

# def handle_cast({:move_cursor, direction}, state) do
#   # Update the cursor position
#   new_cursor = calculate_new_cursor(state.cursor, direction)
#   new_state = %{state | cursor: new_cursor}
#   notify_gui(new_state)
#   {:noreply, new_state}
# end

# defp notify_gui(state) do
#   # Implement notification logic, e.g., via PubSub or direct message
# end

# defp calculate_new_cursor({line, col}, direction) do
#   # Implement cursor movement logic
# end

# def render(%Widgex.Frame{} = frame, %Buffer{data: text}) do
#   # Render the buffer content
#   Scenic.Graph.build()
#   |> Primitives.group(
#     fn graph ->
#       graph
#       # |> Draw.background(frame, colors.slate)
#       |> Draw.background(frame, :midnight_blue)
#       |> Primitives.text(
#         text,
#         font_size: 24,
#         # font: font_name,
#         # fill: colors.text,
#         # translate: {10, ascent + 10}
#         translate: {10, 10}
#         # translate: {10, 10}
#       )

#       # |> Flamelex.GUI.Component.Editor.CursorCaret.add_to_graph(
#       #   %{
#       #     buffer_uuid: hd(state.buffers).uuid,
#       #     coords: {10, 10},
#       #     height: font_size,
#       #     mode: :cursor,
#       #     font: font
#       #   },
#       #   id: :cursor
#       # )
#     end,
#     translate: frame.pin.point
#   )
# end

# def handle_cast({:user_input_fwd, input}, %{assigns: %{state: state}} = scene) do
#   Logger.debug("Editor received input: #{inspect(input)}")

#   # user input handle returns a list of actions, which must be processed by the reducer
#   # maybe on the component level we don't bother with that... though I think it will be awesome for undo/redo etc!

#   # TODO use wormhole, abstract this out somewhere
#   case Editor.UserInputHandler.handle(state, input) do
#     :ignore ->
#       {:noreply, scene}

#     :re_routed ->
#       IO.puts("RE ROUTED #{inspect(input)}")
#       {:noreply, scene}

#     actions when is_list(actions) ->
#       # TODO this gets into a repeat of the previous problem... I want to apply the actions,
#       # but I DONT wnt to always re-render!!

#       # apply actions to the radix state in sequence to determine the new state
#       new_state =
#         actions
#         |> Enum.reduce(state, fn action, state_acc ->
#           case Editor.Reducer.process(state_acc, action) do
#             :ignore ->
#               state_acc

#             # :re_routed ->
#             #   state_acc

#             %Editor.State{} = new_state ->
#               new_state
#           end
#         end)

#       # This ideally is where Scenic is able to go, no need to re-render if the state hasn't changed,
#       new_graph = Render.go(scene.assigns.frame, new_state)

#       new_scene =
#         scene
#         |> assign(state: new_state)
#         |> push_graph(new_graph)

#       # cast_children(new_state.buffers)

#       {:noreply, new_scene}
#   end

#   # new_state = Editor.UserInputHandler.handle(state, input)

#   # # TODO somehow we want to resist re-rendering all the time, we should mutate instead
#   # # by pushing input events down to the lowest level that can handle them
#   # new_graph = Render.go(scene.assigns.frame, new_state)

#   # new_scene =
#   #   scene
#   #   |> assign(state: new_state)
#   #   |> push_graph(new_graph)

#   # {:noreply, new_scene}
# end
