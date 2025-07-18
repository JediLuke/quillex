defmodule QuillEx.RootScene.Reducer do
  alias QuillEx.RootScene

  def process(%QuillEx.RootScene.State{} = state, :new_buffer) do
    # this is why we dont need to wait for a callback when opening a new buffer
    # via the _actions_, and it's why we should use actions for making a new buffer fvia the API

    # Either that, OR, we _do_ put the callback in the BufferManager, then
    # we need to _stop_ adding in the state here again
    {:ok, _buf_ref} = Quillex.Buffer.BufferManager.new_buffer()

    state
    # |> RootScene.Mutator.add_buffer(buf_ref)
    # |> RootScene.Mutator.activate_buffer(buf_ref)
  end

  def process(state, {:activate_buffer, n}) when is_integer(n) do
    RootScene.Mutator.activate_buffer(state, n)
  end

  def process(state, {:activate_buffer, %Quillex.Structs.BufState.BufRef{} = buf_ref}) do
    RootScene.Mutator.activate_buffer(state, buf_ref)
  end

  def process(_state, {:new_color_schema, _colors}) do
    :cast_to_children
  end

  def process(%QuillEx.RootScene.State{} = state, :toggle_ubuntu_bar) do
    %{state | show_ubuntu_bar: not state.show_ubuntu_bar}
  end
end
