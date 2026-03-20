defmodule QuillEx.RootScene.Mutator do
  require Logger

  def add_buffer(%QuillEx.RootScene.State{} = state, buf_ref) do
    if Enum.any?(state.buffers, & &1.uuid == buf_ref.uuid) do
      # Buffer already in state — this can happen if the PubSub {:new_buffer_opened}
      # message arrives after a redundant activation cast. Log and return unchanged.
      Logger.warning("add_buffer: buffer already open, ignoring: #{inspect(buf_ref.name)}")
      state
    else
      %{state | buffers: state.buffers ++ [buf_ref]}
    end
  end

  def activate_buffer(state, n) when is_integer(n) and n >= 1 do
    # nobody says "open the 0th buffer"...
    case Enum.at(state.buffers, n-1) do
      nil ->
        Logger.warning("activate_buffer: buffer number #{n} not found in state, ignoring")
        state

      %Quillex.Structs.BufState.BufRef{} = buf_ref ->
        activate_buffer(state, buf_ref)
    end
  end

  def activate_buffer(state, %Quillex.Structs.BufState.BufRef{} = buf_ref) do
    case Enum.find(state.buffers, &(&1.uuid == buf_ref.uuid)) do
      nil ->
        # Buffer not yet in state — this can occur if an {:activate_buffer} cast races
        # ahead of the PubSub {:new_buffer_opened} message. Log and return unchanged.
        Logger.warning("activate_buffer: buffer UUID #{buf_ref.uuid} not found in state, ignoring")
        state

      %Quillex.Structs.BufState.BufRef{} = new_active_buf ->
        %{state | active_buf: new_active_buf}
    end
  end

  @doc """
  Remove a buffer from the state. If closing the active buffer, switch to another one.
  If this is the last buffer, create a new empty one first.
  """
  def remove_buffer(%QuillEx.RootScene.State{buffers: buffers} = state, %Quillex.Structs.BufState.BufRef{} = buf_ref) do
    case length(buffers) do
      1 ->
        # Can't close the last buffer - just return state unchanged
        Logger.warning("Cannot close the last buffer")
        state

      _ ->
        # Remove the buffer from the list
        new_buffers = Enum.reject(buffers, &(&1.uuid == buf_ref.uuid))

        # If we're closing the active buffer, switch to another one
        new_active = if state.active_buf && state.active_buf.uuid == buf_ref.uuid do
          # Switch to the first remaining buffer
          List.first(new_buffers)
        else
          state.active_buf
        end

        %{state | buffers: new_buffers, active_buf: new_active}
    end
  end
end
