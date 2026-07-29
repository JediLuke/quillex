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

  def process(state, {:close_buffer, %Quillex.Structs.BufState.BufRef{} = buf_ref}) do
    RootScene.Mutator.remove_buffer(state, buf_ref)
  end

  def process(%QuillEx.RootScene.State{active_buf: active_buf} = state, :close_active_buffer) when not is_nil(active_buf) do
    RootScene.Mutator.remove_buffer(state, active_buf)
  end

  def process(state, :close_active_buffer) do
    # No active buffer to close
    state
  end

  def process(_state, {:new_color_schema, _colors}) do
    :cast_to_children
  end

  # Toggle line numbers - returns special atom to signal RootScene to use update_editor_settings
  def process(%QuillEx.RootScene.State{} = state, :toggle_line_numbers) do
    {:editor_settings_change, %{state | show_line_numbers: not state.show_line_numbers}}
  end

  # Toggle word wrap - returns special atom to signal RootScene to use update_editor_settings
  def process(%QuillEx.RootScene.State{} = state, :toggle_word_wrap) do
    {:editor_settings_change, %{state | word_wrap: not state.word_wrap}}
  end

  # Open the find-and-replace bar (Ctrl+H).
  # Sets both show_search_bar and show_replace to true so the renderizer
  # draws the full search + replace panel.
  def process(%QuillEx.RootScene.State{} = state, :open_replace) do
    %{state | show_search_bar: true, show_replace: true}
  end

  # Close the find-and-replace bar — clears all search/replace UI state.
  def process(%QuillEx.RootScene.State{} = state, :close_replace) do
    %{state | show_search_bar: false, show_replace: false, search_query: "",
              search_current_match: 0, search_total_matches: 0}
  end

end
