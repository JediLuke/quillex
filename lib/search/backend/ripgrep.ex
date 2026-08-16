defmodule Quillex.Search.Backend.Ripgrep do
  @moduledoc """
  `Quillex.Search.Backend` on top of ripgrep's `--json` output.

  ripgrep already skips binaries and honours `.gitignore`; on top of that we
  pass every exclude as an anchored `--glob`. Its byte offsets are converted
  to grapheme columns here so callers never see bytes.
  """

  @behaviour Quillex.Search.Backend

  alias Quillex.Search.{Backend, Match}

  @impl true
  def available?, do: System.find_executable("rg") != nil

  @impl true
  def search(root, query, opts) when is_binary(root) and is_binary(query) and query != "" do
    max_results = Keyword.get(opts, :max_results, 5_000)
    excludes = Keyword.get(opts, :excludes, [])

    args =
      ["--json", "--ignore-case", "--fixed-strings", "--no-messages", "--sort", "path"] ++
        glob_args(root, excludes) ++ ["--regexp", query, "--", "."]

    case System.cmd("rg", args, cd: root, stderr_to_stdout: false) do
      # rg exits 1 when nothing matched — not an error
      {output, code} when code in [0, 1] ->
        {:ok, output |> parse(root) |> Enum.take(max_results)}

      {output, code} ->
        {:error, {:ripgrep_exit, code, String.slice(output, 0, 500)}}
    end
  end

  def search(_root, "", _opts), do: {:ok, []}

  # Every exclude becomes an anchored ignore-glob. ripgrep's globs follow
  # gitignore rules: a leading slash anchors the pattern to the search root, so
  # excluding lib/foo does not also hide lib/bar/foo.
  defp glob_args(root, excludes) do
    always = Enum.flat_map(Backend.default_excludes(), &["--glob", "!#{&1}"])

    scoped =
      Enum.flat_map(excludes, fn exclude ->
        relative = exclude |> Path.expand(root) |> Path.relative_to(root)
        ["--glob", "!/#{relative}"]
      end)

    always ++ scoped
  end

  defp parse(output, root) do
    output
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case Jason.decode(line) do
        {:ok, %{"type" => "match", "data" => data}} -> matches_from(data, root)
        _ -> []
      end
    end)
  end

  defp matches_from(
         %{
           "path" => %{"text" => path},
           "line_number" => line_number,
           "lines" => %{"text" => text},
           "submatches" => submatches
         },
         root
       ) do
    text = String.trim_trailing(text, "\n") |> String.trim_trailing("\r")
    absolute = Path.expand(path, root)

    Enum.map(submatches, fn %{"start" => start, "match" => %{"text" => matched}} ->
      %Match{
        path: absolute,
        line: line_number,
        col: Backend.byte_offset_to_col(text, start),
        text: text,
        matched: matched
      }
    end)
  end

  # Binary content, or anything else without a decodable line, is skipped.
  defp matches_from(_data, _root), do: []
end
