defmodule QuillEx.RootScene.Reducer do

  def process(%QuillEx.RootScene.State{} = state, :new_tab) do
    {:ok, buf_ref} = Quillex.Buffer.BufferManager.new_buffer()
    QuillEx.RootScene.Mutator.add_tab(state, buf_ref)
  end

  def process(state, {:activate_buffer, n}) when is_integer(n) do
    QuillEx.RootScene.Mutator.activate_buffer(state, n)
  end

  def process(_state, {:new_color_schema, _colors}) do
    :cast_to_children
  end
end
