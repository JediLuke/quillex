defmodule Quillex.Buffer.Process do
  @moduledoc """
  The buffer GenServer. Runs under the Buffer supervision tree (not the GUI).

  User input is ignored here — the GUI component converts input to actions and
  sends them via `handle_call/handle_cast({:action, ...})`. Buffer state changes
  are broadcast over PubSub so the GUI can re-render.
  """
  use GenServer
  require Logger

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
    # Each buffer process IS a RadixCache store: it registers a retained
    # Scenic.PubSub source and publishes its full BufState after every reduce.
    Scenic.PubSub.register(Quillex.RadixCache.Sources.buffer(buf.uuid))
    Scenic.PubSub.publish(Quillex.RadixCache.Sources.buffer(buf.uuid), buf)
    {:ok, buf}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call({:action, actions}, _from, state) when is_list(actions) do
    new_state = apply_actions(state, actions)
    {:reply, {:ok, new_state}, new_state}
  end

  def handle_call({:action, a}, from, state) when is_tuple(a) or is_atom(a) do
    handle_call({:action, [a]}, from, state)
  end

  # Handle async action casts from TextField (store_backed mode)
  def handle_cast({:action, actions}, state) when is_list(actions) do
    {:noreply, apply_actions(state, actions)}
  end

  def handle_cast({:action, a}, state) when is_tuple(a) or is_atom(a) do
    handle_cast({:action, [a]}, state)
  end

  # Clipboard shell-outs leave port-closed messages behind
  def handle_info({_port, :closed}, state) do
    {:noreply, state}
  end

  # The single reduce-and-broadcast path shared by call and cast entry points.
  defp apply_actions(state, actions) do
    new_state =
      Enum.reduce(actions, state, fn action, state_acc ->
        try do
          case Quillex.Buffer.Process.Reducer.process(state_acc, action) do
            :ignore ->
              state_acc

            %Quillex.Structs.BufState{} = new_state ->
              new_state
          end
        rescue
          error ->
            Logger.warning("Buffer action failed: #{inspect(action)}, error: #{inspect(error)}")
            state_acc
        end
      end)

    # Edge-cast display metadata to the buffer-list store only on transition,
    # so the tab bar's BufRefs stay fresh without per-keystroke list publishes
    if new_state.dirty? != state.dirty? or new_state.name != state.name do
      Quillex.Buffer.BufferManager.update_buffer_meta(new_state.uuid, %{
        dirty?: new_state.dirty?,
        name: new_state.name
      })
    end

    Scenic.PubSub.publish(Quillex.RadixCache.Sources.buffer(new_state.uuid), new_state)

    new_state
  end
end
