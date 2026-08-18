defmodule Quillex.Commands do
  @moduledoc """
  Single registry for user-visible commands, shortcuts, menus, and help text.
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
      description: "Jump the cursor to a line number."
    },
    %{
      id: :toggle_fold,
      label: "Toggle Fold",
      shortcut: "Ctrl+Alt+[",
      menu: :view,
      description: "Fold or unfold the code block containing the cursor."
    },
    %{
      id: :unfold_all,
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

  def shortcut_lines do
    @commands
    |> Enum.reject(&is_nil(&1.shortcut))
    |> Enum.map(&(String.pad_trailing(&1.shortcut, 18) <> &1.label))
  end
end
