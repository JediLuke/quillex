defmodule Quillex.FluxBuffer do
  # use Scenic.Component
  # @behaviour Scenic.Component
  # use Scenic.Scene
  use GenServer
  alias QuillEx.Structs.Buffer
  use ScenicWidgets.ScenicEventsDefinitions

  # TODO this is the way... combine the buffer & the component!!
  # NOTE that didnt go so well actually... but good try

  # Public API
  def start_link(%Buffer{} = buf) do
    GenServer.start_link(__MODULE__, buf, name: via_tuple(buf.uuid))
  end

  # Validate function for Scenic component
  # def validate(%{frame: %Widgex.Frame{}} = data) do
  #   raise "dont expect to have this get called though"
  #   {:ok, data}
  # end

  def init(%Buffer{} = buf) do
    # IO.puts("BUFFER SERVER INITIALIZIUNGINGING")
    Flamelex.Lib.Utils.PubSub.subscribe(topic: {:buffers, buf.uuid})

    {:ok, buf}
  end

  # def init(scene, %{frame: %Widgex.Frame{} = frame}, _opts) do
  # def init(scene, %Buffer{} = buf, _opts) do
  #   #   # state = Flamelex.Fluxus.RadixStore.get().apps.editor
  #   #   # graph = Render.go(frame, state)
  #   #   # graph = render(frame, buf)

  #   # TODO need to register name here because of Scenics ass backwards way of doing everything lol

  #   #   frame =
  #   #     Widgex.Frame.new(%{
  #   #       width: 800,
  #   #       height: 600,
  #   #       pin: {50, 50}
  #   #     })

  #   #   init_scene =
  #   #     scene
  #   #     |> assign(frame: frame)
  #   #     |> assign(graph: graph)
  #   #     |> assign(state: state)
  #   #     |> push_graph(graph)

  #   #   # Flamelex.Lib.Utils.PubSub.subscribe(topic: :radix_state_change)
  #   #   # Flamelex.Lib.Utils.PubSub.subscribe(topic: {:buffers, hd(state.buffers).uuid})

  #   # {:ok, init_scene}
  #   {:ok, scene}
  # end

  # # GenServer callbacks
  # def init(state) do
  #   IO.puts("BUFFER SERVER INITIALIZIUNGINGING")
  #   {:ok, state}
  # end

  # def insert_text(buffer_name, text) do
  #   GenServer.cast(via_tuple(buffer_name), {:insert_text, text})
  # end

  # def move_cursor(buffer_name, direction) do
  #   GenServer.cast(via_tuple(buffer_name), {:move_cursor, direction})
  # end

  # Helper to get the via tuple
  defp via_tuple(name), do: {:via, Registry, {Quillex.BufferRegistry, name}}

  def handle_cast({:user_input_fwd, @right_arrow}, state) do
    # Handle user input
    IO.puts("BUFFER GOT RIGHT ARRROWWWW")

    Flamelex.Lib.Utils.PubSub.broadcast(
      topic: {:buffers, state.uuid},
      msg: {:move_cursor, :right, 1}
    )

    {:noreply, state}
  end

  def handle_cast({:user_input_fwd, input}, state) do
    # Handle user input
    IO.puts("BUFFER GOT INPUT #{inspect(input)}")
    {:noreply, state}
  end

  def handle_info({:move_cursor, _dir, _x}, state) do
    # sort of weird, we fire this event but also recv it, we just ignore it but cursor needs to catch it
    {:noreply, state}
  end

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
end

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
