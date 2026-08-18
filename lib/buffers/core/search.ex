defmodule Quillex.Buffer.Core.Search do
  @moduledoc "Pure search, navigation, and replacement transitions."

  alias Quillex.Buffer.Core.Navigation
  alias Quillex.Structs.BufState

  # Incremental search: the current match is the first one that ends after
  # the cursor — the one under it, when the query came from the word there,
  # or the next one down the document — and the cursor goes to it so the
  # view reveals it. Wraps to the first match when nothing follows.
  def set(buf, query, opts \\ [])

  def set(%BufState{cursor: %{line: line, col: col}} = buf, query, opts)
      when is_binary(query) and query != "" do
    found = matches(buf.data, query, opts)

    index =
      Enum.find_index(found, fn {l, c, text} -> {l, c + String.length(text)} > {line, col} end) ||
        0

    apply_matches(%{buf | search_query: query, search_opts: opts}, found, index)
  end

  def set(%BufState{} = buf, _, _opts),
    do: %{buf | search_query: nil, search_opts: [], search_matches: [], search_current_index: 0}

  def clear(%BufState{} = buf), do: set(buf, nil)

  @doc """
  Recompute the matches after the text changed underneath an active search.

  Keeps the current-match index (clamped) and does NOT move the cursor —
  the user was editing, not navigating. A no-op when nothing relevant changed.
  """
  def resync(%BufState{search_query: nil} = buf, _previous), do: buf
  def resync(%BufState{data: data} = buf, %BufState{data: data}), do: buf

  def resync(%BufState{} = buf, _previous) do
    found = matches(buf.data, buf.search_query, buf.search_opts)
    index = if found == [], do: 0, else: min(buf.search_current_index, length(found) - 1)
    %{buf | search_matches: found, search_current_index: index}
  end

  def next(%BufState{search_matches: []} = buf), do: buf

  def next(%BufState{search_matches: found, search_current_index: index} = buf),
    do: move_to(buf, rem(index + 1, length(found)))

  def previous(%BufState{search_matches: []} = buf), do: buf

  def previous(%BufState{search_matches: found, search_current_index: index} = buf),
    do: move_to(buf, if(index == 0, do: length(found) - 1, else: index - 1))

  def replace(%BufState{search_matches: []} = buf, _replacement), do: buf

  def replace(%BufState{} = buf, replacement) when is_binary(replacement) do
    case Enum.at(buf.search_matches, buf.search_current_index) do
      {line, col, matched} ->
        replaced =
          replace_at(Quillex.Buffer.Core.History.push(buf), line, col, matched, replacement)

        # Land on the next match AFTER the text we just wrote. Keeping the same
        # index is wrong when the replacement itself still matches (a
        # case-insensitive "the" → "THE"): Enter would replace the same spot
        # forever. Wraps to the first match when nothing follows.
        found = matches(replaced.data, buf.search_query, buf.search_opts)
        after_replacement = {line, col + String.length(replacement)}
        next = Enum.find_index(found, fn {l, c, _} -> {l, c} >= after_replacement end) || 0
        apply_matches(replaced, found, next)

      nil ->
        buf
    end
  end

  def replace_all(%BufState{search_matches: []} = buf, _replacement), do: buf

  def replace_all(%BufState{} = buf, replacement) when is_binary(replacement) do
    updated =
      buf.search_matches
      |> Enum.reverse()
      |> Enum.reduce(Quillex.Buffer.Core.History.push(buf), fn {line, col, matched}, acc ->
        replace_at(acc, line, col, matched, replacement)
      end)

    refresh(updated, buf.search_query, buf.search_opts, 0)
  end

  @doc """
  Compile `query` into the regex a search will scan with.

  Options, both defaulting to `false` so the historical contract — literal,
  case-insensitive — is what you get for a bare query:

    * `:case_sensitive`
    * `:regex` — treat the query as a pattern instead of literal text

  Returns `{:error, message}` when the user's pattern will not compile. That is
  a boundary, not a bug: `foo(` is an ordinary thing to have typed halfway
  through writing `foo(bar)`, and it arrives here on every keystroke. Callers
  taking user input validate here and report the message; everything below
  assumes a query that compiles.
  """
  @spec compile(String.t(), keyword()) :: {:ok, Regex.t()} | {:error, String.t()}
  def compile(query, opts \\ []) when is_binary(query) do
    pattern = if Keyword.get(opts, :regex, false), do: query, else: Regex.escape(query)

    # Caseless matching on the ORIGINAL line, not on a downcased copy: for
    # some scripts downcasing changes the byte length, and positions found in
    # the copy would not line up with the text they are meant to describe.
    flags = if Keyword.get(opts, :case_sensitive, false), do: "u", else: "iu"

    case Regex.compile(pattern, flags) do
      {:ok, regex} ->
        {:ok, regex}

      # Regex.compile reports the reason as a CHARLIST, which string
      # interpolation refuses (String.Chars has no impl for lists) — building
      # the message the obvious way raises inside the error path itself.
      {:error, {reason, at}} ->
        {:error, "#{describe(reason)} (at position #{at})"}

      {:error, reason} ->
        {:error, describe(reason)}
    end
  end

  defp describe(reason) when is_list(reason), do: List.to_string(reason)
  defp describe(reason) when is_binary(reason), do: reason
  defp describe(reason), do: inspect(reason)

  @doc """
  Every occurrence of `query`, as `{line, col, matched_text}` with 1-based
  grapheme columns, in document order.

  Takes the same options as `compile/2`, and requires a query that compiles
  under them — validate user input with `compile/2` first.
  """
  def matches(lines, query, opts \\ []) when is_list(lines) and is_binary(query) do
    {:ok, regex} = compile(query, opts)
    matches_with(lines, regex)
  end

  @doc """
  `matches/3` against an already-compiled regex.

  For callers scanning many documents with one query — a project search walks
  thousands of files, and recompiling the pattern for each is pure waste.
  """
  def matches_with(lines, %Regex{} = regex) when is_list(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} -> matches_in_line(line, regex, line_number) end)
  end

  defp replace_at(buf, line, col, matched, replacement) do
    current = Enum.at(buf.data, line - 1, "")
    before = String.slice(current, 0, col - 1)
    after_match = String.slice(current, (col - 1 + String.length(matched))..-1//1)

    %{
      buf
      | data: List.replace_at(buf.data, line - 1, before <> replacement <> after_match),
        dirty?: true
    }
  end

  defp refresh(buf, query, opts, desired_index) do
    found = matches(buf.data, query, opts)
    apply_matches(buf, found, desired_index)
  end

  defp apply_matches(buf, [], _desired_index),
    do: %{buf | search_matches: [], search_current_index: 0}

  defp apply_matches(buf, found, desired_index) do
    index = min(desired_index, length(found) - 1)
    move_to(%{buf | search_matches: found, search_current_index: index}, index)
  end

  defp move_to(%BufState{search_matches: found} = buf, index) do
    case Enum.at(found, index) do
      {line, col, _text} ->
        buf
        |> Navigation.move_cursor({line, col})
        |> Map.put(:search_current_index, index)

      nil ->
        buf
    end
  end

  # The scan yields BYTE offsets; columns are graphemes. Convert incrementally,
  # counting only the text between consecutive matches — a byte offset used as
  # a column put every highlight after an em dash two characters to the right
  # (and would have made Replace splice the wrong characters out).
  defp matches_in_line(line, regex, line_number) do
    # A caseless unicode scan raises on invalid UTF-8; such a line holds no
    # text we could match anyway.
    scanned = if String.valid?(line), do: Regex.scan(regex, line, return: :index), else: []

    scanned
    |> Enum.map_reduce({0, 1}, fn [{byte_start, byte_len}], {prev_byte, prev_col} ->
      col = prev_col + String.length(binary_part(line, prev_byte, byte_start - prev_byte))
      {{line_number, col, binary_part(line, byte_start, byte_len)}, {byte_start, col}}
    end)
    |> elem(0)
  end
end
