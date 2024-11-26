defmodule QuillEx.RootScene.Mutator do

  def add_tab(%QuillEx.RootScene.State{} = state, buf_ref) do
    # state
    # |> put_in([:tabs], state.tabs ++ [buf_ref])
    # |> put_in([:buffers], state.buffers ++ [buf_ref])

    # put new buffer in first place so it's the active buffer
    %{state|buffers: [buf_ref] ++ state.buffers}
  end

  def activate_buffer(state, n) when is_integer(n) and n >= 1 do
    # we count buffers starting at 1 but elixir uses 0 for list index
    {before, [head | tail]} = Enum.split(state.buffers, n-1)

    %{state|buffers: [head | before ++ tail]}
  end
end
