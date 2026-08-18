defmodule Quillex.Commands do
  @moduledoc """
  Single registry for user-visible commands, shortcuts, menus, and help text.

  One entry buys three things: the menu row, the shortcut printed beside it,
  and the line in Help → Keyboard Shortcuts. Registering a command is therefore
  the whole of "can a user find this without being told?" — the question item 8
  of the 1.0 roadmap asks of every feature.

  `menu:` says which menu a command belongs in, or `nil` for the ones that are
  keyboard-only *by nature*. Cursor movement is the clear case: nobody reaches
  for a menu to move one word left, and thirteen rows of it would bury the
  commands people do reach for. Those still appear in the shortcut reference —
  which is the point. A binding absent from this file is invisible: not in a
  menu, not in the reference, discoverable only by guessing.

  `section:` groups the reference; `shortcut_lines/0` prints those headings.
  """

  @commands [
    %{
      id: :new,
      label: "New Buffer",
      shortcut: "Ctrl+N",
      menu: :file,
      description: "Create a new unsaved text buffer."
    },
    %{
      id: :open,
      label: "Open File…",
      shortcut: "Ctrl+O",
      menu: :file,
      description: "Choose a text file to open in a new tab."
    },
    %{
      id: :save,
      label: "Save",
      shortcut: "Ctrl+S",
      menu: :file,
      description: "Write the active buffer to its current file."
    },
    %{
      id: :save_as,
      label: "Save As…",
      shortcut: "Ctrl+Shift+S",
      menu: :file,
      description: "Write the active buffer to a new file path."
    },
    %{
      id: :close,
      label: "Close Buffer",
      shortcut: "Ctrl+W",
      menu: :file,
      description: "Close the active tab, prompting if it has unsaved changes."
    },
    %{
      id: :undo,
      label: "Undo",
      shortcut: "Ctrl+Z",
      menu: :edit,
      description: "Undo the most recent editing action."
    },
    %{
      id: :redo,
      label: "Redo",
      shortcut: "Ctrl+Shift+Z",
      menu: :edit,
      description: "Reapply the most recently undone action."
    },
    %{
      id: :cut,
      label: "Cut",
      shortcut: "Ctrl+X",
      menu: :edit,
      description: "Remove the selection and copy it to the clipboard."
    },
    %{
      id: :copy,
      label: "Copy",
      shortcut: "Ctrl+C",
      menu: :edit,
      description: "Copy the selected text to the clipboard."
    },
    %{
      id: :paste,
      label: "Paste",
      shortcut: "Ctrl+V",
      menu: :edit,
      description: "Insert clipboard text at the cursor."
    },
    %{
      id: :select_all,
      label: "Select All",
      shortcut: "Ctrl+A",
      menu: :edit,
      description: "Select the entire contents of the active buffer."
    },
    %{
      id: :delete_line,
      label: "Delete Line",
      shortcut: "Ctrl+D",
      menu: :edit,
      description: "Remove the line the cursor is on."
    },
    %{
      id: :find,
      label: "Find",
      shortcut: "Ctrl+F",
      menu: :edit,
      description: "Search within the active buffer."
    },
    %{
      id: :find_replace,
      label: "Find & Replace",
      shortcut: "Ctrl+H",
      menu: :edit,
      description: "Search for text and replace matching occurrences."
    },
    %{
      id: :find_in_project,
      label: "Find in Project",
      shortcut: "Ctrl+Shift+F",
      menu: :edit,
      description: "Search every file under the project root; results open in the sidebar."
    },
    %{
      id: :replace_in_project,
      label: "Replace in Project",
      shortcut: "Ctrl+Shift+H",
      menu: :edit,
      description: "Search the project and replace every match across its files."
    },
    %{
      id: :find_next,
      label: "Find Next",
      shortcut: "F3",
      menu: :edit,
      description: "Move to the next search match."
    },
    %{
      id: :goto_line,
      label: "Go to Line…",
      shortcut: "Ctrl+G",
      menu: :edit,
      section: "Moving around",
      description: "Jump the cursor to a line number."
    },
    %{
      id: :toggle_fold,
      section: "Folding",
      label: "Toggle Fold",
      shortcut: "Ctrl+Alt+[",
      menu: :view,
      description: "Fold or unfold the code block containing the cursor."
    },
    %{
      id: :unfold_all,
      section: "Folding",
      label: "Unfold All",
      shortcut: "Ctrl+Alt+]",
      menu: :view,
      description: "Expand every folded code block in the active buffer."
    },
    %{
      id: :shortcuts,
      label: "Keyboard Shortcuts",
      shortcut: nil,
      menu: :help,
      description: "Show the complete keyboard shortcut reference."
    },

    # ── Keyboard-only, by nature ────────────────────────────────────────────
    #
    # Movement and indentation. These have no menu row on purpose — nobody
    # opens a menu to move one word left — but they were invisible before,
    # because a binding that is not registered here appears nowhere at all.
    %{
      id: :word_left,
      label: "Move to Previous Word",
      shortcut: "Ctrl+Left",
      menu: nil,
      section: "Moving around",
      description: "Move the cursor to the start of the previous word."
    },
    %{
      id: :word_right,
      label: "Move to Next Word",
      shortcut: "Ctrl+Right",
      menu: nil,
      section: "Moving around",
      description: "Move the cursor to the start of the next word."
    },
    %{
      id: :line_start,
      label: "Start of Line",
      shortcut: "Home",
      menu: nil,
      section: "Moving around",
      description: "Move the cursor to the first column of the current line."
    },
    %{
      id: :line_end,
      label: "End of Line",
      shortcut: "End",
      menu: nil,
      section: "Moving around",
      description: "Move the cursor past the last character of the current line."
    },
    %{
      id: :doc_start,
      label: "Start of Document",
      shortcut: "Ctrl+Home",
      menu: nil,
      section: "Moving around",
      description: "Move the cursor to the very beginning of the buffer."
    },
    %{
      id: :doc_end,
      label: "End of Document",
      shortcut: "Ctrl+End",
      menu: nil,
      section: "Moving around",
      description: "Move the cursor to the very end of the buffer."
    },
    %{
      id: :page_up,
      label: "Page Up",
      shortcut: "PageUp",
      menu: nil,
      section: "Moving around",
      description: "Move the cursor up by one screenful."
    },
    %{
      id: :page_down,
      label: "Page Down",
      shortcut: "PageDown",
      menu: nil,
      section: "Moving around",
      description: "Move the cursor down by one screenful."
    },
    %{
      id: :extend_selection,
      label: "Extend Selection",
      shortcut: "Shift+Move",
      menu: nil,
      section: "Selecting",
      description:
        "Hold Shift while moving the cursor — arrows, Home, End, Ctrl+Home, " <>
          "Ctrl+End — to select as you go."
    },
    %{
      id: :delete_prev_word,
      label: "Delete Previous Word",
      shortcut: "Ctrl+Backspace",
      menu: nil,
      section: "Editing",
      description: "Remove the word before the cursor."
    },
    %{
      id: :delete_next_word,
      label: "Delete Next Word",
      shortcut: "Ctrl+Delete",
      menu: nil,
      section: "Editing",
      description: "Remove the word after the cursor."
    },
    %{
      id: :indent,
      label: "Indent",
      shortcut: "Tab",
      menu: nil,
      section: "Editing",
      description: "Insert one indentation unit at the cursor."
    },
    %{
      id: :unindent,
      label: "Unindent",
      shortcut: "Shift+Tab",
      menu: nil,
      section: "Editing",
      description: "Remove one indentation unit from the start of the line."
    },
    %{
      id: :zoom_in,
      label: "Zoom In",
      shortcut: "Ctrl++",
      menu: nil,
      section: "Interface",
      description: "Scale the application chrome up, leaving the editor text alone."
    },
    %{
      id: :zoom_out,
      label: "Zoom Out",
      shortcut: "Ctrl+-",
      menu: nil,
      section: "Interface",
      description: "Scale the application chrome down, leaving the editor text alone."
    },
    %{
      id: :zoom_reset,
      label: "Reset Zoom",
      shortcut: "Ctrl+0",
      menu: nil,
      section: "Interface",
      description: "Return the application chrome to its normal size."
    },
    %{
      id: :dismiss,
      label: "Dismiss",
      shortcut: "Escape",
      menu: nil,
      section: "Interface",
      description: "Close the find bar, a dialog, or an open menu."
    }
  ]

  def all, do: @commands

  def fetch!(id) do
    Enum.find(@commands, &(&1.id == id)) ||
      raise ArgumentError, "unknown command #{inspect(id)}"
  end

  def menu_label(id) do
    command = fetch!(id)
    if command.shortcut, do: "#{command.label} (#{command.shortcut})", else: command.label
  end

  @sections [
    "File",
    "Editing",
    "Finding",
    "Moving around",
    "Selecting",
    "Folding",
    "Interface"
  ]

  @doc """
  The reference shown by Help → Keyboard Shortcuts, grouped under headings.

  Commands with no `section:` are grouped by the menu they live in, so the
  reference reads in the same order as the menu bar and a user can find a
  shortcut where they would look for the command.
  """
  def shortcut_lines do
    @commands
    |> Enum.reject(&is_nil(&1.shortcut))
    |> Enum.group_by(&section/1)
    |> Enum.sort_by(fn {section, _} -> Enum.find_index(@sections, &(&1 == section)) end)
    |> Enum.flat_map(fn {section, commands} ->
      [section] ++ Enum.map(commands, &"  #{String.pad_trailing(&1.shortcut, 16)}#{&1.label}")
    end)
  end

  @doc "The reference's section headings, in the order they are printed."
  def sections, do: @sections

  defp section(%{section: section}) when is_binary(section), do: section
  defp section(%{menu: :file}), do: "File"
  defp section(%{menu: :edit, id: id}) when id in [:find, :find_replace, :find_next, :find_in_project, :replace_in_project], do: "Finding"
  defp section(%{menu: :edit}), do: "Editing"
  defp section(%{menu: :view}), do: "Interface"
  defp section(_command), do: "Interface"
end
