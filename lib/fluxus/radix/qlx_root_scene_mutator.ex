defmodule QuillEx.RootScene.Mutator do
  require Logger

  def add_buffer(%QuillEx.RootScene.State{} = state, buf_ref) do
    if Enum.any?(state.buffers, & &1.uuid == buf_ref.uuid) do
      raise "tried to add a buffer that was already open... #{inspect buf_ref}"
      # Logger.warning "tried to add a buffer that was already open... #{inspect buf_ref}"
      state
    else
      %{state | buffers: state.buffers ++ [buf_ref]}
    end
  end

  # def set_active_buffer(state, %{uuid: active_buf_uuid}) do
  #   case Enum.find_index(state.buffers, &(&1.uuid == active_buf_uuid)) do
  #     nil ->
  #       raise "Buffer with UUID #{active_buf_uuid} not found - unable to set active buffer"

  #     index ->
  #       # nobody says "open the 0th buffer"...
  #       %{state | active_buf: index + 1}
  #   end
  # end

  def activate_buffer(state, n) when is_integer(n) and n >= 1 do

    # # we count buffers starting at 1 but elixir uses 0 for list index
    # {before, [head | tail]} = Enum.split(state.buffers, n - 1)

    # %{state | buffers: [head | before ++ tail]}
    # %{state | active_buf: n - 1}

    # %{state | active_buf: active_buf}

    # nobody says "open the 0th buffer"...
    case Enum.at(state.buffers, n-1) do
      nil ->
        raise "Buffer number #{n} not found - unable to set active buffer"

      %Quillex.Structs.BufState.BufRef{} = buf_ref ->
        activate_buffer(state, buf_ref)
    end
  end

  def activate_buffer(state, %Quillex.Structs.BufState.BufRef{} = buf_ref) do
    case Enum.find(state.buffers, &(&1.uuid == buf_ref.uuid)) do
      nil ->
        raise "Buffer with UUID #{buf_ref.uuid} not found - unable to set active buffer"

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
