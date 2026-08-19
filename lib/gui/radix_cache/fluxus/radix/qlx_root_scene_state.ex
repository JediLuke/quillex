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
            show_matching_brace: true,
            highlight_current_line: false,
            highlight_current_column: false,
            word_wrap: false,
            auto_indent: true,
            tab_width: 4,
            text_size: 24,
            fold_level: 1,
            show_action_feedback: true,
            show_menu_shortcuts: true,
            syntax_highlighting: true,
            # The colour scheme, mirrored from ViewStore. One palette drives
            # the editor and every piece of chrome — see Quillex.GUI.Palette.
            theme: :alchemical_dark,
            # Which key means "command" — :ctrl, or :meta (⌘) on a Mac.
            # Mirrored from ViewStore; the menus print it beside every row.
            primary_modifier: :ctrl,
            chrome_zoom: 100,
            # File navigator sidebar
            show_file_nav: false,
            file_nav_path: nil,
            file_nav_width: 250,
            file_nav_revision: 0,
            file_nav_resize_hovered: false,
            file_nav_resizing: false,
            file_nav_resize_hide?: false,
            # Project search: layout flag mirrors ViewStore; the snapshot
            # (query, scope, results) mirrors ProjectSearchStore.
            show_project_search: false,
            project_search: nil,
            # What the pane's query field is seeded with when it opens — the
            # word under the cursor, or whatever the last search was. The pane
            # owns the field from then on; this is only the seed.
            project_search_query: "",
            # Which of the pane's fields the keyboard lands in when it opens:
            # Ctrl+Shift+F means the query, Ctrl+Shift+H the replacement.
            project_search_focus_field: :query,
            # The reusable preview tab. Walking thirty results must leave one
            # tab open, not thirty, so a result opens into this slot and the
            # next result replaces it. Double-clicking the tab, or editing the
            # file, promotes it to an ordinary tab and clears this.
            preview_buf_uuid: nil,
            # Which pane owns the keyboard: :buffer or :side_pane.
            #
            # Focus used to be derived twice, in two places that disagreed. The
            # renderizer recreated the buffer pane with `focused: not
            # show_search_bar`, so any re-render while the project search pane
            # was open handed the keyboard BACK to the buffer without taking it
            # off the pane — and both then consumed every keystroke. The
            # symptom was text appearing in the document and the search field
            # at the same time.
            #
            # So it is recorded once, here, and the renderizer reads it rather
            # than guessing. Clicks reach a component, not this scene (see the
            # note on :focus_taken in the scene), so the components report the
            # click and this scene decides who holds the keyboard.
            keyboard_owner: :buffer,
            # Modal dialogs
            show_file_picker: false,
            show_unsaved_prompt: false,
            show_about: false,
            show_shortcuts: false,
            pending_close_buf_ref: nil,
            quit_dirty_buffers: [],
            pending_nav_delete: [],
            show_nav_delete_prompt: false,
            # "Save Settings as Default" explains itself before it writes
            # anything — it is the one action here that outlives the session.
            show_save_settings_prompt: false,
            # Go to Line (Ctrl+G). The digits are collected by RootScene itself
            # rather than by a text-input component: the prompt accepts only
            # digits, so a full editable field would be more machinery than the
            # interaction deserves.
            show_goto_line: false,
            goto_line_input: "",
            # Search bar
            show_search_bar: false,
            search_query: "",
            # Find options for the in-buffer search, mirrored from the bar so
            # a re-run (F3, or a fresh query) uses the same ones the person
            # can see are lit.
            search_opts: [case_sensitive: false, regex: false],
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
