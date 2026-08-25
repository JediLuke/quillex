defmodule Quillex.Utils.FileTree do
  @moduledoc """
  Converts a filesystem directory into a SideNav.Item tree structure.

  Used for the file explorer sidebar in Quillex.

  ## One level at a time

  The navigator asks for `build_level/1`, not `build/1`. A directory arrives
  with its own entries and `children: :unloaded`, and is filled in by
  `build_level/1` again when somebody opens it.

  This is not a micro-optimisation. Walking a project in full costs a `File.ls`
  and a stat for every entry in it, at every depth, and the navigator did that
  before it could draw a single row — on a large tree that is seconds of
  blocked scene process for a pane that shows twenty folders. Depth is the
  expensive dimension and nobody is looking at it.

  `build/1` still walks the whole tree, for callers that genuinely need all of
  it (the project search pane's scope tree).
  """

  alias ScenicWidgets.SideNav.Item

  # File extensions to show. An allow-list, deliberately: a source tree is full
  # of things you never want to open, and hiding them beats scrolling past
  # them. But it has to actually cover the languages people edit — Quillex
  # ships a dedicated Erlang lexer, so a navigator that hides `.erl` is just
  # wrong. Extensionless files are shown regardless (see `should_show?/1`).
  @shown_extensions ~w(
    .ex .exs .eex .heex .erl .hrl .lfe .escript
    .c .h .cpp .cxx .hpp .cc .rs .go .zig .swift
    .py .rb .lua .pl .php .r .jl
    .java .kt .kts .scala .clj .cljs .cljc
    .lisp .cl .el .scm .rkt .ml .hs .nix
    .js .mjs .cjs .jsx .ts .tsx .vue .svelte
    .html .htm .css .scss .sass .less
    .json .yaml .yml .toml .xml .ini .cfg .conf .properties .env
    .sql .graphql .gql .proto .csv .tsv
    .sh .bash .zsh .fish .ps1 .bat
    .txt .md .markdown .rst .org .tex .adoc
    .diff .patch .log .mk .cmake .gradle .dockerfile
    .gitignore .gitattributes .editorconfig .tool-versions
  )

  # Directories to hide
  @hidden_dirs ~w(.git _build deps node_modules .elixir_ls .lexical)

  @doc """
  Build the full file tree under a directory, to every depth.

  Returns a list of SideNav.Item structs representing the directory structure.
  Files are sorted alphabetically with directories first.
  """
  def build(path) when is_binary(path) do
    if File.dir?(path) do
      Enum.map(entries(path), fn
        {name, full_path, :directory} ->
          %Item{
            id: full_path,
            title: name,
            type: :group,
            url: nil,
            children: build(full_path),
            expanded: false
          }

        {name, full_path, :file} ->
          file_item(full_path, name)
      end)
    else
      []
    end
  end

  @doc """
  Build one directory level.

  Directories come back `children: :unloaded` — they have contents, and nobody
  has looked. Call this again with a directory's own path to fill it in.
  """
  def build_level(path) when is_binary(path) do
    if File.dir?(path) do
      Enum.map(entries(path), fn
        {name, full_path, :directory} ->
          %Item{
            id: full_path,
            title: name,
            type: :group,
            url: nil,
            children: :unloaded,
            expanded: false
          }

        {name, full_path, :file} ->
          file_item(full_path, name)
      end)
    else
      []
    end
  end

  @doc """
  Rebuild only as much of `tree` as is actually loaded.

  A refresh has to see everything the person can see and nothing else. Walking
  from the root again would re-read the whole project to redraw twenty rows;
  pushing a bare root level instead would collapse every folder they had open.
  So each loaded directory is re-read, one level, and each unloaded one is left
  exactly as it is.
  """
  def refresh(root, tree) when is_binary(root) and is_list(tree) do
    loaded = loaded_paths(tree)
    do_refresh(root, loaded)
  end

  defp do_refresh(path, loaded) do
    path
    |> build_level()
    |> Enum.map(fn
      %Item{type: :group, id: id} = item ->
        if MapSet.member?(loaded, id),
          do: %{item | children: do_refresh(id, loaded)},
          else: item

      item ->
        item
    end)
  end

  @doc "Every directory in `tree` whose contents have been fetched."
  def loaded_paths(tree) when is_list(tree), do: MapSet.new(do_loaded_paths(tree))

  defp do_loaded_paths(tree) do
    Enum.flat_map(tree, fn
      %Item{type: :group} = item ->
        if Item.loaded?(item),
          do: [item.id | do_loaded_paths(Item.get_children(item))],
          else: []

      _item ->
        []
    end)
  end

  @doc """
  A deterministic structural signature of the directories currently on screen.

  Only the levels the navigator has actually loaded are read, and only one
  level deep each. The signature used to be taken over the whole project,
  which meant the poller re-walked every file in it twice a second to notice
  that a folder nobody had opened was unchanged.
  """
  def signature(paths) when is_list(paths) do
    paths
    |> Enum.sort()
    |> Enum.map(&level_entries/1)
    |> :erlang.phash2()
  end

  defp level_entries(path) do
    case File.ls(path) do
      {:ok, _entries} ->
        {path, Enum.map(entries(path), fn {name, _full, kind} -> {kind, name} end)}

      {:error, reason} ->
        {path, {:unreadable, reason}}
    end
  end

  # One `File.ls`, and exactly one stat per entry. Every predicate below wants
  # to know whether an entry is a directory, and asking the filesystem four
  # separate times — once to filter, once to sort, once to build — is most of
  # what a tree walk costs.
  defp entries(path) do
    path
    |> File.ls!()
    |> Enum.map(fn name -> {name, Path.join(path, name), kind(Path.join(path, name))} end)
    |> Enum.filter(&should_show?/1)
    |> Enum.sort_by(fn {name, _full_path, kind} ->
      # Directories first, then alphabetical
      {kind != :directory, String.downcase(name)}
    end)
  end

  defp kind(full_path), do: if(File.dir?(full_path), do: :directory, else: :file)

  defp file_item(full_path, name) do
    %Item{
      id: full_path,
      title: name,
      type: :page,
      url: full_path,
      children: [],
      expanded: false
    }
  end

  defp should_show?({name, _full_path, kind}) do
    cond do
      # Hide dotfiles except specific ones
      String.starts_with?(name, ".") and name not in [".gitignore", ".tool-versions"] ->
        false

      # Hide specific directories
      kind == :directory and name in @hidden_dirs ->
        false

      # Show all directories (that aren't hidden)
      kind == :directory ->
        true

      # Show files with allowed extensions or no extension
      true ->
        ext = Path.extname(name)
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
