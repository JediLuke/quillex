defmodule QuillEx.RootScene.State do
  @moduledoc """
  RootScene's working state — a local view assembled from the RadixCache
  stores plus scene-owned transient interaction state.

  Ownership:
  - `buffers` / `active_buf` mirror the `:radix_buffers` store (BufferManager)
  - editor settings, file-nav flags and the status message mirror the
    `:radix_view` store (ViewStore) — see @view_keys in the scene
  - search-bar and dialog flags are scene-owned transient interaction state:
    single-consumer chrome whose choreography (child blur/focus sequencing,
    word-under-cursor prefill) lives in the scene process by design
  - file-navigator resize hover/drag flags and its live width preview are
    scene-owned gesture state; only the resulting width and visibility are
    committed to `ViewStore` when the gesture ends
  - `frame` and `cursor_pos` are per-scene input/layout state
  """
  use StructAccess

  defstruct frame: nil,
            buffers: [],
            active_buf: nil,
            # Editor settings (synced with View menu toggles)
            show_line_numbers: true,
            word_wrap: false,
            tab_width: 4,
            text_size: 24,
            # File navigator sidebar
            show_file_nav: false,
            file_nav_path: nil,
            file_nav_width: 250,
            file_nav_revision: 0,
            file_nav_resize_hovered: false,
            file_nav_resizing: false,
            file_nav_resize_hide?: false,
            # Modal dialogs
            show_file_picker: false,
            show_unsaved_prompt: false,
            show_about: false,
            show_shortcuts: false,
            pending_close_buf_ref: nil,
            quit_dirty_buffers: [],
            pending_nav_delete: [],
            show_nav_delete_prompt: false,
            # Search bar
            show_search_bar: false,
            search_query: "",
            search_current_match: 0,
            search_total_matches: 0,
            # Replace mode (Ctrl+H)
            show_replace: false,
            # Cursor position tracking for scroll routing
            cursor_pos: {0, 0},
            # Transient status notification, mirrored from ViewStore (:radix_view).
            # The show/clear lifecycle — including the stale-timer guard — lives in
            # Quillex.RadixCache.ViewStore.
            # string or nil
            status_message: nil,
            # :info | :warning | :error
            status_severity: :info,
            # Render-only restoration hints. Keeping these as real struct fields
            # preserves RootScene.State's type through resize/settings updates.
            _restore_cursor: nil,
            _restore_first_visible_line: nil

  def new(%{frame: %Widgex.Frame{} = frame, buffers: buffers}) when is_list(buffers) do
    %__MODULE__{
      frame: frame,
      buffers: buffers,
      active_buf: hd(buffers),
      file_nav_path: File.cwd!()
    }
  end

  # this is a convenience function so we can pass in a %Scenic.Scene{}
  def active_buf(%{assigns: %{state: state}}) do
    active_buf(state)
  end

  def active_buf(%__MODULE__{} = state) do
    # # we count buffers starting at one, need to offset this cause Elixir uses zero for Enums
    # Enum.at(state.buffers, state.active_buf - 1)
    state.active_buf
  end
end
