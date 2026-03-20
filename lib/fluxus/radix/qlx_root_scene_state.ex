
defmodule QuillEx.RootScene.State do
  use StructAccess

  defstruct [
    frame: nil,
    tabs: [],
    toolbar: nil,
    buffers: [],
    active_buf: nil,
    show_ubuntu_bar: true,
    # Editor settings (synced with View menu toggles)
    show_line_numbers: true,
    word_wrap: false,
    tab_width: 4,
    # File navigator sidebar
    show_file_nav: false,
    file_nav_path: nil,
    file_nav_width: 250,
    # Modal dialogs
    show_file_picker: false,
    # Search bar
    show_search_bar: false,
    search_query: "",
    search_current_match: 0,
    search_total_matches: 0,
    # Replace mode (Ctrl+H)
    show_replace: false,
    # Cursor position tracking for scroll routing
    cursor_pos: {0, 0},
    # Transient status notification (shown briefly at bottom of viewport)
    # Set by actions like run_verification; cleared by :clear_status_message after a timeout.
    status_message: nil,   # string or nil
    status_severity: :info, # :info | :warning | :error
    # Unique reference stamped when a status message is shown. The
    # {:clear_status_message, ref} timer only clears the message if the ref
    # still matches, so a stale timer cannot erase a newer message.
    status_ref: nil
  ]

  def new(%{frame: %Widgex.Frame{} = frame, buffers: buffers}) when is_list(buffers) do
    %__MODULE__{
      frame: frame,
      toolbar: %{
        height: 50
      },
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
