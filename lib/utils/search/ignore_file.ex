defmodule Quillex.Search.IgnoreFile do
  @moduledoc """
  The project's own `.gitignore`, read as search exclusions.

  A project already says what isn't source — build output, dependencies, logs,
  editor droppings — and it says it in a file it maintains anyway. Searching
  that stuff is never what anybody wanted, and asking them to write the same
  list again in an editor setting is asking twice.

  ## The dialect, and where it stops

  Patterns go through `Quillex.Search.Glob`, which already implements the
  gitignore rules that matter: `**` spans segments, a pattern with no `/`
  matches at any depth, everything else is literal. On top of that this
  handles the three bits of gitignore syntax that live in the file rather
  than in the pattern:

  - `# comment` and blank lines are dropped
  - a trailing `/` means "a directory", which for a search means the
    directory AND everything under it
  - a leading `!` un-ignores something an earlier rule caught

  What it does NOT do is git's ordering. In git, later rules win over earlier
  ones and a `!` can be re-overridden further down the file. Here the
  negations are collected and applied as a single override: a path is
  excluded if some ignore rule matches it and no negation does. That is wrong
  for a file which is ignored, un-ignored, then ignored again — a shape which
  is rare, and whose failure mode is showing a file that git would hide,
  which is the safe direction for a search to be wrong in.
  """

  alias Quillex.Search.Glob

  @ignore_files [".gitignore", ".ignore"]

  @doc """
  The ignore rules in effect at `root`.

  Returns `%{ignore: [pattern], unignore: [pattern]}`, both as glob strings
  for `Quillex.Search.Glob`. Missing or unreadable files simply contribute
  nothing — a project without a .gitignore is not an error.
  """
  def rules(root) when is_binary(root) do
    @ignore_files
    |> Enum.map(&Path.join(root, &1))
    |> Enum.flat_map(&read_lines/1)
    |> Enum.reduce(%{ignore: [], unignore: []}, &classify/2)
    |> Map.new(fn {key, patterns} -> {key, Enum.reverse(patterns)} end)
  end

  @doc "The compiled form: `{ignore_regexes, unignore_regexes}`."
  def compiled(root) when is_binary(root) do
    %{ignore: ignore, unignore: unignore} = rules(root)
    {Glob.compile_list(ignore), Glob.compile_list(unignore)}
  end

  defp read_lines(path) do
    case File.read(path) do
      {:ok, contents} -> String.split(contents, "\n")
      {:error, _} -> []
    end
  end

  defp classify(line, acc) do
    line = String.trim(line)

    cond do
      line == "" -> acc
      String.starts_with?(line, "#") -> acc
      String.starts_with?(line, "!") -> add(acc, :unignore, String.slice(line, 1..-1//1))
      true -> add(acc, :ignore, line)
    end
  end

  defp add(acc, key, pattern) do
    case expand(String.trim(pattern)) do
      [] -> acc
      patterns -> Map.update!(acc, key, &(Enum.reverse(patterns) ++ &1))
    end
  end

  # A directory rule has to catch the directory itself and everything in it,
  # and a leading slash is gitignore's way of anchoring to the root — which is
  # what Glob already does for any pattern containing a separator, so the
  # slash is simply removed.
  defp expand(""), do: []

  defp expand(pattern) do
    pattern = String.trim_leading(pattern, "/")

    if String.ends_with?(pattern, "/") do
      base = String.trim_trailing(pattern, "/")
      [base, base <> "/**"]
    else
      [pattern, pattern <> "/**"]
    end
  end
end
