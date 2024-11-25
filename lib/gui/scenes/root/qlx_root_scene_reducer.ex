defmodule QuillEx.RootScene.Reducer do

  def process(%QuillEx.RootScene.State{} = state, :new_tab) do
    {:ok, buf_ref} = Quillex.Buffer.BufferManager.new_buffer()
    QuillEx.RootScene.Mutator.add_tab(state, buf_ref)
  end
end
