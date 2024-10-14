defmodule Quillex.Buffer.Process do
  @moduledoc """
  This is the _actual buffer_ process, which runs not as part
  of the GUI, it runs under the Buffer SUpervision tree.

  Ignore user input in the actual Buffer process, wait for the GUI to convert it to actions
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
    buf_tag = {buf.uuid, __MODULE__}
    via_tuple = {:via, Registry, {Quillex.BufferRegistry, buf_tag}}
    GenServer.start_link(__MODULE__, buf, name: via_tuple)
  end

  def init(%Quillex.Structs.Buffer{} = buf) do
    {:ok, _state = buf}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_cast({:action, a}, state) when is_tuple(a) do
    # convenience API for single actions
    handle_cast({:action, [a]}, state)
  end

  def handle_cast({:action, actions}, state) when is_list(actions) do
    IO.puts("BUFFER GOT ACTIONS: #{inspect(actions)}")

    # TODO use wormhole here
    new_state =
      actions
      |> Enum.reduce(state, fn action, state_acc ->
        Quillex.GUI.Components.Buffer.Reducer.process(state_acc, action)
        |> case do
          :ignore ->
            state_acc

          new_state ->
            new_state
        end
      end)

    # This ideally is where Scenic is able to go, no need to re-render if the state hasn't changed,
    # however at this point I dont know how to do it... we might need to diff
    # states or something very complex

    # for now we just try and make sure that anything which needs to be done
    # by a lower level component, gets L:re-routed to that component - this means
    # that the FluxBuffer state should only change when its probably necessary to
    # re-render anyway

    # if something needs to be managed on both levels e.g. the cursor position, maybe
    # throw 2 actions, one for the buffer, one for the component?? we'll see

    notify_gui(new_state)

    {:noreply, new_state}
  end

  def notify_gui(buf) do
    Quillex.Buffer.BufferManager.send_to_buffer_gui_component(buf, {:state_change, buf})
  end
end

# def move_cursor(buffer_name, direction) do
#   GenServer.cast(via_tuple(buffer_name), {:move_cursor, direction})
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

# defp calculate_new_cursor({line, col}, direction) do
#   # Implement cursor movement logic
# end
