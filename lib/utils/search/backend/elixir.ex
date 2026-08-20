defmodule Quillex.Search.Backend.Elixir do
  @moduledoc """
  Pure-Elixir `Quillex.Search.Backend`: walks the tree with `File`, reads
  each text file and reuses the buffer search for the matching itself. Slower
  than ripgrep on big trees, needs nothing installed.
  """

  @behaviour Quillex.Search.Backend

  alias Quillex.Search.{Backend, Match}
  alias Quillex.Buffer.Core.Search

  # Files bigger than this are not what a project search is for.
  @max_file_bytes 4 * 1024 * 1024
  # A NUL in the first chunk marks a binary file.
  @sniff_bytes 8_000

  @impl true
  def available?, do: true

  @impl true
  def search(_root, "", _opts), do: {:ok, []}

  def search(root, query, opts) when is_binary(root) and is_binary(query) do
    # Compiled once for the whole walk, and validated here: a regex the user is
    # halfway through typing must come back as an error the pane can show, not
    # as a crash in the middle of a directory traversal.
    with {:ok, stream} <- stream(root, query, opts) do
      {:ok, Enum.to_list(stream)}
    end
  end

  @impl true
  def stream(_root, "", _opts), do: {:ok, []}

  # The walk was always lazy — every match was known the moment its file was
  # read, and then sat in a Stream nobody consumed until the last directory
  # had been visited. This hands the same stream out instead of running it to
  # the end first.
  def stream(root, query, opts) when is_binary(root) and is_binary(query) do
    max_results = Keyword.get(opts, :max_results, 5_000)
    excludes = Keyword.get(opts, :excludes, [])
    globs = opts |> Keyword.get(:exclude_globs, []) |> Quillex.Search.Glob.compile_list()
    unignore = opts |> Keyword.get(:unignore_globs, []) |> Quillex.Search.Glob.compile_list()

    # Compiled once for the whole walk, and validated HERE rather than
    # somewhere down the stream: a regex the user is halfway through typing
    # must come back as an error the pane can show, not as a crash in the
    # middle of a directory traversal.
    with {:ok, regex} <- Search.compile(query, opts) do
      {:ok,
       root
       |> text_files(root, excludes, globs, unignore)
       |> Stream.flat_map(&matches_in_file(&1, regex))
       |> Stream.take(max_results)}
    else
      {:error, message} -> {:error, {:bad_pattern, message}}
    end
  end

  defp text_files(dir, root, excludes, globs, unignore) do
    Stream.resource(
      fn -> [dir] end,
      fn
        [] ->
          {:halt, []}

        [path | rest] ->
          cond do
            Backend.excluded?(path, root, excludes, globs, unignore) and path != root ->
              {[], rest}

            File.dir?(path) ->
              children =
                case File.ls(path) do
                  {:ok, entries} -> entries |> Enum.sort() |> Enum.map(&Path.join(path, &1))
                  {:error, _} -> []
                end

              {[], children ++ rest}

            text_file?(path) ->
              {[path], rest}

            true ->
              {[], rest}
          end
      end,
      fn _ -> :ok end
    )
  end

  defp text_file?(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular, size: size}} when size <= @max_file_bytes ->
        case File.open(path, [:read, :binary], &IO.binread(&1, @sniff_bytes)) do
          {:ok, chunk} when is_binary(chunk) -> not String.contains?(chunk, <<0>>)
          _ -> false
        end

      _ ->
        false
    end
  end

  defp matches_in_file(path, regex) do
    case File.read(path) do
      # Not UTF-8 (Latin-1, UTF-16, a NUL-free binary): not a text file we
      # can search — the caseless unicode scan raises on invalid bytes.
      {:ok, content} when not is_binary(content) or byte_size(content) == 0 ->
        []

      {:ok, content} ->
        if String.valid?(content), do: matches_in_lines(path, regex, content), else: []

      {:error, _} ->
        []
    end
  end

  defp matches_in_lines(path, regex, content) do
    lines = String.split(content, "\n")

    lines
    |> Search.matches_with(regex)
    |> Enum.map(fn {line, col, matched} ->
      %Match{
        path: path,
        line: line,
        col: col,
        text: Enum.at(lines, line - 1) |> String.trim_trailing("\r"),
        matched: matched
      }
    end)
  end
end
