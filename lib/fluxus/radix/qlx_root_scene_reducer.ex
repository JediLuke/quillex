defmodule Quillex.RootScene.Reducer do
  def process(%Quillex.RootScene.State{} = state, :new_buffer) do
    # this is why we dont need to wait for a callback when opening a new buffer
    # via the _actions_, and it's why we should use actions for making a new buffer fvia the API

    # Either that, OR, we _do_ put the callback in the BufferManager, then
    # we need to _stop_ adding in the state here again
    {:ok, _buf_ref} = Quillex.Buffer.BufferManager.new_buffer()

    state
    # |> RootScene.Mutator.add_buffer(buf_ref)
    # |> RootScene.Mutator.activate_buffer(buf_ref)
  end

  # NOTE: {:activate_buffer, _} and {:close_buffer, _} never reach this
  # reducer — RootScene intercepts them and dispatches to BufferManager, the
  # buffer-list store; the scene updates when the :radix_buffers snapshot
  # arrives.

  # NOTE: :toggle_line_numbers / :toggle_word_wrap / :toggle_file_nav never reach
  # this reducer — RootScene intercepts them in dedicated handle_call/handle_cast
  # clauses because they need the update_editor_settings flow.

  # Open the find-and-replace bar (Ctrl+H).
  # Sets both show_search_bar and show_replace to true so the renderizer
  # draws the full search + replace panel.
  def process(%Quillex.RootScene.State{} = state, :open_replace) do
    %{state | show_search_bar: true, show_replace: true}
  end

  # Close the find-and-replace bar — clears all search/replace UI state.
  def process(%Quillex.RootScene.State{} = state, :close_replace) do
    %{
      state
      | show_search_bar: false,
        show_replace: false,
        search_query: "",
        search_current_match: 0,
        search_total_matches: 0
    }
  end
end
