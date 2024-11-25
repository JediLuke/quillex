defmodule QuillEx.RootScene.Mutator do

  def add_tab(%QuillEx.RootScene.State{} = state, buf_ref) do
    state
    # |> put_in([:tabs], state.tabs ++ [buf_ref])
    |> put_in([:buffers], state.buffers ++ [buf_ref])
  end
end
