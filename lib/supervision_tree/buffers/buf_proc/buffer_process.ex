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
  alias Quillex.GUI.Components.BufferPane

  def start_link(%Quillex.Structs.BufState{} = buf) do
    buf_tag = {buf.uuid, __MODULE__}
    via_tuple = {:via, Registry, {Quillex.BufferRegistry, buf_tag}}
    GenServer.start_link(__MODULE__, buf, name: via_tuple)
  end

  def fetch_buf(%Quillex.Structs.BufState.BufRef{} = buf_ref) do
    Quillex.Buffer.BufferManager.call_buffer(buf_ref, :get_state)
  end

  def init(%Quillex.Structs.BufState{} = buf) do
    {:ok, _state = buf}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call({:action, actions}, _from, state) when is_list(actions) do
    # TODO use wormhole here
    new_state =
      actions
      |> Enum.reduce(state, fn action, state_acc ->
        BufferPane.Reducer.process(state_acc, action)
        |> case do
          :ignore ->
            state_acc

          # {:cast_parent, actions} ->
          #   # in these situations we need to pass the action back up to the parent,
          #   # this can happen when "exceptions" occur e.g. we get an action
          #   # to save a file, but we don't have a filename to save it to
          #   # cast_parent(scene, {:action, actions})
          #   state_acc

          # the above seems correct until you realise that this is the _buffer_
          # process, not the GUI component, so we can't just cast_parent because
          # we aren't in the Scenic process tree - buffers are kind of weird this way
          # so we need to re-route the action to the GUI component, potentially,
          # or some other kind of "request" e.g. {:req_save, buf_ref}

          # :re_routed ->
          #   state_acc
          # {:fwd, Quillex.GUI.Components.Buffer, msgs} ->
          #   BufferManager.cast_to_gui_component(state_acc, {:buffer_request, msgs})
          #   state_acc

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
    # IO.puts "NOTIFY GUI"

    {:reply, :ok, new_state}
  end

  def handle_call({:action, a}, from, state) when is_tuple(a) do
    # convenience API for single actions
    handle_call({:action, [a]}, from, state)
  end

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

  def notify_gui(buf) do
    Quillex.Buffer.BufferManager.cast_to_gui_component({:state_change, buf})
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
