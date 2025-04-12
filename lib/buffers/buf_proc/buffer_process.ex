defmodule Quillex.Buffer.Process do
  @moduledoc """
  This is the _actual buffer_ process, which runs not as part
  of the GUI, it runs under the Buffer SUpervision tree.

  Ignore user input in the actual Buffer process, wait for the GUI to convert it to actions


    # TODO this is the way... combine the buffer & the component!!
  # NOTE that didnt go so well actually... but good try
  # use Scenic.Component
  # @behaviour Scenic.Component
  # use Scenic.Scene


  """
  use GenServer

  def fetch_buf(%Quillex.Structs.BufState.BufRef{} = buf_ref) do
    Quillex.Buffer.BufferManager.call_buffer(buf_ref, :get_state)
  end

  def save_as(%Quillex.Structs.BufState.BufRef{} = buf_ref, file_path) do
    Quillex.Buffer.BufferManager.call_buffer(buf_ref, {:action, {:save_as, file_path}})
  end

  def start_link(%Quillex.Structs.BufState{} = buf) do
    buf_tag = {buf.uuid, __MODULE__}
    via_tuple = {:via, Registry, {Quillex.BufferRegistry, buf_tag}}
    GenServer.start_link(__MODULE__, buf, name: via_tuple)
  end

  def init(%Quillex.Structs.BufState{} = buf) do
    Quillex.Utils.PubSub.subscribe(topic: {:buffers, buf.uuid})
    {:ok, buf}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call({:action, actions}, _from, state) when is_list(actions) do
    # TODO use wormhole here
    new_state =
      actions
      |> Enum.reduce(state, fn action, state_acc ->
        case Quillex.Buffer.Process.Reducer.process(state_acc, action) do
          :ignore ->
            state_acc

          %Quillex.Structs.BufState{} = new_state ->
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

    # broadcast out buffer changes so the GUI (or whoever) can respond
    Quillex.Utils.PubSub.broadcast(
      topic: {:buffers, new_state.uuid},
      msg: {:buf_state_changes, new_state}
    )


    # notify_gui(new_state)
    # IO.puts "NOTIFY GUI"

    # #TODO broadcast an event saying it updated, then let the GUI come fetch it if it wants...


    {:reply, {:ok, new_state}, new_state}
  end

  def handle_call({:action, a}, from, state) when is_tuple(a) do
    # convenience API for single actions
    handle_call({:action, [a]}, from, state)
  end

  #TODo dont have buffers opening ports!!!
  def handle_info({_port, :closed}, scene) do
    IO.puts "dont worry abour it (INCORRECT WORRY ABOUT THIS!!)"
    {:noreply, scene}
  end

  def handle_info({:user_input, _input}, scene) do
    # buffer process doesnt respond to user input, only GUI component does, so just ignore this
    IO.puts "BUF GOT USER INPUT VERY WEIRD"
    {:noreply, scene}
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


  #   # TODO handle_update, in such a way that we just go through init/3 again, but
  #   # without needing to spin up sub-processes.... eliminate all the extra handle_cast logic

  #   def handle_cast({:redraw, %{data: nil} = args}, scene) do
  #     lines = [""]
  #     GenServer.cast(self(), {:redraw, Map.put(args, :data, lines)})
  #     {:noreply, scene}
  #   end
  #   def handle_cast({:redraw, %{data: text} = args}, scene) when is_bitstring(text) do
  #     lines = String.split(text, @newline_char)
  #     GenServer.cast(self(), {:redraw, Map.put(args, :data, lines)})
  #     {:noreply, scene}
  #   end

  #   def handle_cast({:redraw, buffer}, scene) do
  #     new_graph =
  #       scene.assigns.graph
  #       |> scroll_text_area(scene, buffer)
  #       |> update_data(scene, buffer)
  #       |> update_cursor(scene, buffer)

  #     update_scroll_limits(scene, buffer)

  # what is temperature? It's the ultimate inescapable force - temperature is the real "bottom" of our universe. Every point in the universe
  # could be mapped, and it's temperature waves analyzed & drawn from that perspective

  # temperature is the wall we cannot cross, it's gods hand forcing the boundary of our existence

  #     if new_graph == scene.assigns.graph do
  #       {:noreply, scene}
  #     else
  #       new_scene =
  #         scene
  #         |> assign(graph: new_graph)
  #         |> push_graph(new_graph)

  #       {:noreply, new_scene}
  #     end
  #   end
