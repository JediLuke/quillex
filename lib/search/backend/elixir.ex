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
    max_results = Keyword.get(opts, :max_results, 5_000)
    excludes = Keyword.get(opts, :excludes, [])

    matches =
      root
      |> text_files(root, excludes)
      |> Stream.flat_map(&matches_in_file(&1, query))
      |> Enum.take(max_results)

    {:ok, matches}
  end

  defp text_files(dir, root, excludes) do
    Stream.resource(
      fn -> [dir] end,
      fn
        [] ->
          {:halt, []}

        [path | rest] ->
          cond do
            Backend.excluded?(path, root, excludes) and path != root ->
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

  defp matches_in_file(path, query) do
    case File.read(path) do
      # Not UTF-8 (Latin-1, UTF-16, a NUL-free binary): not a text file we
      # can search — the caseless unicode scan raises on invalid bytes.
      {:ok, content} when not is_binary(content) or byte_size(content) == 0 ->
        []

      {:ok, content} ->
        if String.valid?(content), do: matches_in_lines(path, query, content), else: []

      {:error, _} ->
        []
    end
  end

  defp matches_in_lines(path, query, content) do
    lines = String.split(content, "\n")

    lines
    |> Search.matches(query)
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
