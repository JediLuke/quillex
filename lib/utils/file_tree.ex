defmodule Quillex.Utils.FileTree do
  @moduledoc """
  Converts a filesystem directory into a SideNav.Item tree structure.

  Used for the file explorer sidebar in Quillex.
  """

  alias ScenicWidgets.SideNav.Item

  # File extensions to show (common code/text files)
  @shown_extensions ~w(.ex .exs .eex .heex .txt .md .json .yaml .yml .toml .xml .html .css .js .ts .sh .gitignore .tool-versions)

  # Directories to hide
  @hidden_dirs ~w(.git _build deps node_modules .elixir_ls .lexical)

  @doc """
  Build a file tree from a directory path.

  Returns a list of SideNav.Item structs representing the directory structure.
  Files are sorted alphabetically with directories first.
  """
  def build(path) when is_binary(path) do
    if File.dir?(path) do
      build_tree(path, Path.basename(path))
    else
      []
    end
  end

  defp build_tree(path, name) do
    entries =
      path
      |> File.ls!()
      |> Enum.filter(&should_show?(&1, path))
      |> Enum.sort_by(fn entry ->
        full_path = Path.join(path, entry)
        # Directories first, then alphabetical
        {!File.dir?(full_path), String.downcase(entry)}
      end)
      |> Enum.map(fn entry ->
        full_path = Path.join(path, entry)
        build_item(full_path, entry)
      end)

    entries
  end

  defp build_item(path, name) do
    if File.dir?(path) do
      children = build_tree(path, name)
      %Item{
        id: path,
        title: name,
        type: :group,
        url: nil,
        children: children,
        expanded: false
      }
    else
      %Item{
        id: path,
        title: name,
        type: :page,
        url: path,
        children: [],
        expanded: false
      }
    end
  end

  defp should_show?(entry, parent_path) do
    full_path = Path.join(parent_path, entry)

    cond do
      # Hide dotfiles except specific ones
      String.starts_with?(entry, ".") and entry not in [".gitignore", ".tool-versions"] ->
        false

      # Hide specific directories
      File.dir?(full_path) and entry in @hidden_dirs ->
        false

      # Show all directories (that aren't hidden)
      File.dir?(full_path) ->
        true

      # Show files with allowed extensions or no extension
      true ->
        ext = Path.extname(entry)
        ext == "" or ext in @shown_extensions
    end
  end

  @doc """
  Get the working directory for the file tree.
  Uses the current working directory by default.
  """
  def default_path do
    File.cwd!()
  end
end
