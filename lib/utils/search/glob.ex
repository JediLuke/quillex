defmodule Quillex.Search.Glob do
  @moduledoc """
  gitignore-style globs, for the search pane's exclude field.

  The pane offers one line of text — `**/deps/**`, `*.lock`, `test/**` — and
  both backends have to agree on what it means. ripgrep understands these
  patterns natively; the Elixir backend does not, so a pattern is compiled to
  a regular expression here and matched against the *root-relative* path.

  The dialect is the small one people actually type:

  - `**` matches any number of path segments, separators included
  - `*` matches anything within one segment
  - `?` matches one character within a segment
  - everything else is literal

  A pattern with no separator matches at any depth (`*.lock` hides
  `deps/foo/mix.lock`), which is the gitignore rule and the one people expect.
  A malformed pattern is a boundary — the user is typing it — so `compile/1`
  returns `{:error, message}` rather than raising.
  """

  @doc "Split a whitespace/comma separated exclude field into patterns."
  def split(""), do: []

  def split(field) when is_binary(field),
    do: field |> String.split([",", " ", "\n"], trim: true)

  @doc """
  Compile one glob to a `Regex` anchored over a whole relative path.

  Returns `{:error, message}` for a pattern Erlang's regex engine rejects —
  which, with everything escaped here, means only a pattern so long it blows
  the compiler's limits.
  """
  def compile(pattern) when is_binary(pattern) do
    source =
      if String.contains?(pattern, "/"),
        do: "^" <> translate(pattern) <> "$",
        else: "^(?:.*/)?" <> translate(pattern) <> "$"

    case Regex.compile(source) do
      {:ok, regex} -> {:ok, regex}
      {:error, {reason, _at}} -> {:error, to_string(reason)}
    end
  end

  @doc """
  Compile a list of patterns. Patterns that will not compile are dropped: the
  field is edited a character at a time, and a half-typed pattern must not take
  the search down with it.
  """
  def compile_list(patterns) when is_list(patterns) do
    Enum.flat_map(patterns, fn pattern ->
      case compile(pattern) do
        {:ok, regex} -> [regex]
        {:error, _message} -> []
      end
    end)
  end

  @doc "Split and compile a whole exclude field in one step."
  def compile_all(field) when is_binary(field), do: field |> split() |> compile_list()

  @doc "Does `relative_path` match any of the compiled globs?"
  def any_match?(_relative_path, []), do: false

  def any_match?(relative_path, regexes),
    do: Enum.any?(regexes, &Regex.match?(&1, relative_path))

  # `**` has to be consumed before `*`, so the walk is over graphemes rather
  # than a chain of String.replace/3 calls that would each see the previous
  # one's output.
  defp translate(pattern), do: translate(String.graphemes(pattern), [])

  defp translate([], acc), do: acc |> Enum.reverse() |> Enum.join()

  defp translate(["*", "*", "/" | rest], acc), do: translate(rest, ["(?:.*/)?" | acc])
  defp translate(["*", "*" | rest], acc), do: translate(rest, [".*" | acc])
  defp translate(["*" | rest], acc), do: translate(rest, ["[^/]*" | acc])
  defp translate(["?" | rest], acc), do: translate(rest, ["[^/]" | acc])
  defp translate([char | rest], acc), do: translate(rest, [Regex.escape(char) | acc])
end
