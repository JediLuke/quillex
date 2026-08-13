defmodule Quillex.Commands do
  @moduledoc """
  Single registry for user-visible commands, shortcuts, menus, and help text.
  """

  @commands [
    %{id: :new, label: "New Buffer", shortcut: "Ctrl+N", menu: :file},
    %{id: :open, label: "Open File…", shortcut: "Ctrl+O", menu: :file},
    %{id: :save, label: "Save", shortcut: "Ctrl+S", menu: :file},
    %{id: :save_as, label: "Save As…", shortcut: "Ctrl+Shift+S", menu: :file},
    %{id: :close, label: "Close Buffer", shortcut: "Ctrl+W", menu: :file},
    %{id: :undo, label: "Undo", shortcut: "Ctrl+Z", menu: :edit},
    %{id: :redo, label: "Redo", shortcut: "Ctrl+Shift+Z", menu: :edit},
    %{id: :cut, label: "Cut", shortcut: "Ctrl+X", menu: :edit},
    %{id: :copy, label: "Copy", shortcut: "Ctrl+C", menu: :edit},
    %{id: :paste, label: "Paste", shortcut: "Ctrl+V", menu: :edit},
    %{id: :find, label: "Find", shortcut: "Ctrl+F", menu: :edit},
    %{id: :find_replace, label: "Find & Replace", shortcut: "Ctrl+H", menu: :edit},
    %{id: :find_next, label: "Find Next", shortcut: "Ctrl+G", menu: :edit},
    %{id: :toggle_fold, label: "Toggle Fold", shortcut: "Ctrl+Alt+[", menu: :view},
    %{id: :unfold_all, label: "Unfold All", shortcut: "Ctrl+Alt+]", menu: :view},
    %{id: :shortcuts, label: "Keyboard Shortcuts", shortcut: nil, menu: :help}
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
