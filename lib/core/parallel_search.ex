defmodule Quillex.Core.ParallelSearch do
  @moduledoc """
  Multicore text search using parallel line processing.

  Spawns a process for each line to search in parallel, then aggregates results.
  This is educational and demonstrates Elixir's lightweight process model -
  spawning thousands of processes is cheap and fast!
  """

  @doc """
  Search for a pattern in a list of lines using parallel processing.

  Returns a list of matches: [{line_number, column, match_text}, ...]
  Line and column numbers are 1-indexed.

  ## Options
  - `:case_sensitive` - whether search is case sensitive (default: false)
  - `:regex` - treat pattern as regex (default: false)

  ## Example

      iex> lines = ["Hello world", "Hello Elixir", "Goodbye world"]
      iex> ParallelSearch.find_all(lines, "hello")
      [{1, 1, "Hello"}, {2, 1, "Hello"}]
  """
  def find_all(lines, pattern, opts \\ []) when is_list(lines) and is_binary(pattern) do
    case_sensitive = Keyword.get(opts, :case_sensitive, false)
    use_regex = Keyword.get(opts, :regex, false)

    # Prepare the pattern for matching
    matcher = prepare_matcher(pattern, case_sensitive, use_regex)

    # Get caller's PID for receiving results
    parent = self()
    ref = make_ref()

    # Spawn a process for each line
    lines
    |> Enum.with_index(1)
    |> Enum.each(fn {line, line_num} ->
      spawn(fn ->
        matches = find_in_line(line, line_num, matcher, case_sensitive)
        send(parent, {ref, line_num, matches})
      end)
    end)

    # Collect results from all processes
    line_count = length(lines)
    collect_results(ref, line_count, %{})
    |> Map.values()
    |> List.flatten()
    |> Enum.sort_by(fn {line, col, _} -> {line, col} end)
  end

  @doc """
  Find the next match after a given position.
  Returns `{line, col, match_text}` or `nil` if no more matches.
  """
  def find_next(lines, pattern, {current_line, current_col}, opts \\ []) do
    all_matches = find_all(lines, pattern, opts)

    Enum.find(all_matches, fn {line, col, _} ->
      line > current_line or (line == current_line and col > current_col)
    end)
  end

  @doc """
  Find the previous match before a given position.
  Returns `{line, col, match_text}` or `nil` if no more matches.
  """
  def find_prev(lines, pattern, {current_line, current_col}, opts \\ []) do
    all_matches = find_all(lines, pattern, opts)

    all_matches
    |> Enum.reverse()
    |> Enum.find(fn {line, col, _} ->
      line < current_line or (line == current_line and col < current_col)
    end)
  end

  @doc """
  Count total matches.
  """
  def count_matches(lines, pattern, opts \\ []) do
    find_all(lines, pattern, opts) |> length()
  end

  # Prepare the matcher based on options
  defp prepare_matcher(pattern, case_sensitive, use_regex) do
    if use_regex do
      opts = if case_sensitive, do: [], else: [:caseless]
      case Regex.compile(pattern, opts) do
        {:ok, regex} -> {:regex, regex}
        {:error, _} -> {:literal, pattern}  # Fall back to literal if invalid regex
      end
    else
      {:literal, pattern}
    end
  end

  # Find all occurrences in a single line
  defp find_in_line(line, line_num, {:regex, regex}, _case_sensitive) do
    regex
    |> Regex.scan(line, return: :index)
    |> Enum.map(fn [{start, len}] ->
      col = start + 1  # Convert to 1-indexed
      match_text = String.slice(line, start, len)
      {line_num, col, match_text}
    end)
  end

  defp find_in_line(line, line_num, {:literal, pattern}, case_sensitive) do
    {search_line, search_pattern} = if case_sensitive do
      {line, pattern}
    else
      {String.downcase(line), String.downcase(pattern)}
    end

    find_literal_matches(search_line, search_pattern, line, line_num, 0, [])
  end

  # Find all literal (non-regex) matches in a line
  defp find_literal_matches(search_line, pattern, original_line, line_num, offset, acc) do
    case :binary.match(search_line, pattern) do
      :nomatch ->
        Enum.reverse(acc)

      {start, len} ->
        col = offset + start + 1  # Convert to 1-indexed
        match_text = String.slice(original_line, offset + start, len)

        # Continue searching after this match
        rest_start = start + max(1, len)  # Move at least 1 char to avoid infinite loop
        rest_search = :binary.part(search_line, rest_start, byte_size(search_line) - rest_start)

        find_literal_matches(
          rest_search,
          pattern,
          original_line,
          line_num,
          offset + rest_start,
          [{line_num, col, match_text} | acc]
        )
    end
  end

  # Collect results from spawned processes
  defp collect_results(_ref, 0, results), do: results
  defp collect_results(ref, remaining, results) do
    receive do
      {^ref, line_num, matches} ->
        collect_results(ref, remaining - 1, Map.put(results, line_num, matches))
    after
      5000 ->
        # Timeout - return what we have
        results
    end
  end
end
