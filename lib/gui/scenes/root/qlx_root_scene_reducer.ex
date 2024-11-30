defmodule QuillEx.RootScene.Reducer do
  alias QuillEx.RootScene

  def process(%QuillEx.RootScene.State{} = state, :new_tab) do
    {:ok, buf_ref} = Quillex.Buffer.BufferManager.new_buffer()

    RootScene.Mutator.add_buffer(state, buf_ref)
    # |> RootScene.Mutator.set_active_buffer(buf_ref)
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
end
