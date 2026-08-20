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
  # rg is handed the whole search and gives back the whole answer: its output
  # is collected by System.cmd before a line of it is parsed, so there is no
  # point in the middle at which a piece could be handed over. It also
  # finishes inside the debounce on trees where the Elixir walk takes a
  # tenth of a second, so there is nothing to hand over early.
  def stream(root, query, opts) do
    with {:ok, matches} <- search(root, query, opts), do: {:ok, matches}
  end

  @impl true
  def search(root, query, opts) when is_binary(root) and is_binary(query) and query != "" do
    max_results = Keyword.get(opts, :max_results, 5_000)
    excludes = Keyword.get(opts, :excludes, [])
    exclude_globs = Keyword.get(opts, :exclude_globs, [])

    args =
      ["--json", "--no-messages", "--sort", "path"] ++
        match_args(opts) ++
        glob_args(root, excludes, exclude_globs) ++ ["--regexp", query, "--", "."]

    # stderr is folded in so a rejected pattern can be reported in ripgrep's own
    # words. Safe for the success path: parse/2 keeps only lines that decode as
    # JSON, and a diagnostic never will.
    case System.cmd("rg", args, cd: root, stderr_to_stdout: true) do
      # rg exits 1 when nothing matched — not an error
      {output, code} when code in [0, 1] ->
        {:ok, output |> parse(root) |> Enum.take(max_results)}

      # A pattern rg will not compile also exits 2. The user is mid-keystroke
      # on a regex far more often than ripgrep is genuinely broken, so say so
      # in the pane's own words rather than reporting an exit code.
      {output, 2} ->
        {:error, {:bad_pattern, first_line(output)}}

      {output, code} ->
        {:error, {:ripgrep_exit, code, String.slice(output, 0, 500)}}
    end
  end

  def search(_root, "", _opts), do: {:ok, []}

  defp first_line(output) do
    output |> String.split("\n", trim: true) |> List.first() |> to_string() |> String.slice(0, 200)
  end

  # ripgrep's own equivalents of the search options. `--fixed-strings` is what
  # makes a literal query literal, so it is dropped — not negated — in regex
  # mode, where the query IS the pattern.
  defp match_args(opts) do
    case_args =
      if Keyword.get(opts, :case_sensitive, false),
        do: ["--case-sensitive"],
        else: ["--ignore-case"]

    regex_args = if Keyword.get(opts, :regex, false), do: [], else: ["--fixed-strings"]

    case_args ++ regex_args
  end

  # Every exclude becomes an anchored ignore-glob. ripgrep's globs follow
  # gitignore rules: a leading slash anchors the pattern to the search root, so
  # excluding lib/foo does not also hide lib/bar/foo.
  defp glob_args(root, excludes, exclude_globs) do
    always = Enum.flat_map(Backend.default_excludes(), &["--glob", "!#{&1}"])

    scoped =
      Enum.flat_map(excludes, fn exclude ->
        relative = exclude |> Path.expand(root) |> Path.relative_to(root)
        ["--glob", "!/#{relative}"]
      end)

    # The exclude field is passed through verbatim: ripgrep's glob dialect is
    # the one Quillex.Search.Glob was written to imitate, so what the user
    # typed means the same thing to both backends.
    typed = Enum.flat_map(exclude_globs, &["--glob", "!#{&1}"])

    always ++ scoped ++ typed
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
