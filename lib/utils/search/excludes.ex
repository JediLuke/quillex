defmodule Quillex.Search.Excludes do
  @moduledoc """
  What a project search skips, as a list the person using it owns.

  ## Why it is a file and not a constant

  It used to be `~w(.git _build deps node_modules …)` compiled into the
  editor. That list is a snapshot of the languages its author happened to use:
  the day a project arrives with a `target/` or a `vendor/` or a `.zig-cache/`
  in it, the search wades through thousands of build artefacts and there is
  nothing the person at the keyboard can do about it short of patching the
  editor.

  So it lives in a file, seeded with those defaults the first time it is
  wanted, and it is a file this editor can open — see
  **View → Edit Search Excludes**. Adding a directory to it is one line, and
  the next search honours it.

  ## The format

  One pattern per line, `#` for comments, blank lines ignored. The dialect is
  `Quillex.Search.Glob` — the same one `.gitignore` uses, and the same one
  the ignore files themselves are read with, because having two spellings for
  "skip this folder" in the same editor would be indefensible.
  """

  alias Quillex.Search.Glob

  @seed """
  # What a project search skips.
  #
  # One pattern per line. `#` starts a comment. The syntax is the one
  # .gitignore uses: `**` spans directories, a pattern with no slash matches
  # at any depth, so `node_modules` skips it wherever it appears.
  #
  # This file is yours — add whatever your projects are full of. The list
  # below is only a starting point, and a starting point from one particular
  # decade of programming at that.
  #
  # Your project's own .gitignore is honoured separately, and can be turned
  # off in the search pane. This list is not: it is the stuff you never want
  # searched, in any project.

  .git
  .hg
  .svn
  _build
  deps
  node_modules
  .elixir_ls
  .cache
  """

  @doc "Where the list lives — beside the rest of this editor's settings."
  def path do
    Quillex.ConfigDir.file("search_excludes")
  end

  @doc """
  The patterns, as glob strings.

  Writes the file with its seed contents the first time it is asked for, so
  that the list is discoverable — a setting nobody can see is a setting
  nobody can change.
  """
  def patterns do
    file = path()

    contents =
      case File.read(file) do
        {:ok, contents} ->
          contents

        {:error, :enoent} ->
          seed(file)
          @seed

        {:error, _reason} ->
          @seed
      end

    parse(contents)
  end

  @doc "The compiled form, for a whole search to share."
  def compiled, do: Glob.compile_list(patterns())

  @doc "The contents written on first use. Public so a test can compare against it."
  def seed_contents, do: @seed

  @doc false
  def parse(contents) when is_binary(contents) do
    contents
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Enum.flat_map(&expand/1)
  end

  # A bare directory name has to catch the directory AND its contents: the
  # walk prunes on the directory, but a match reported inside one has to be
  # rejected too.
  defp expand(pattern) do
    pattern = String.trim_trailing(pattern, "/")
    [pattern, pattern <> "/**"]
  end

  defp seed(file) do
    with :ok <- File.mkdir_p(Path.dirname(file)) do
      File.write(file, @seed)
    end
  end
end
