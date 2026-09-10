defmodule Quillex.Utils.FileTree do
  @moduledoc """
  Converts a filesystem directory into a SideNav.Item tree structure.

  Used for the file explorer sidebar in Quillex.
  """

  alias ScenicWidgets.SideNav.Item

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

  @doc "A deterministic structural signature of entries visible in the navigator."
  def signature(path) when is_binary(path) do
    if File.dir?(path) do
      path
      |> visible_paths(path)
      |> Enum.sort()
      |> :erlang.phash2()
    else
      :missing
    end
  end

  defp visible_paths(path, root) do
    case File.ls(path) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&should_show?(&1, path))
        |> Enum.flat_map(fn entry ->
          full_path = Path.join(path, entry)
          relative = Path.relative_to(full_path, root)

          if File.dir?(full_path) do
            [{:directory, relative} | visible_paths(full_path, root)]
          else
            [{:file, relative}]
          end
        end)

      {:error, reason} ->
        [{:unreadable, Path.relative_to(path, root), reason}]
    end
  end

  defp build_tree(path, _name) do
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

      # Everything else is shown. There is deliberately no extension whitelist:
      # opening a file is gated on its content (see Quillex.Files.TextFile),
      # not its name, so the navigator should not second-guess that.
      true ->
        true
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
