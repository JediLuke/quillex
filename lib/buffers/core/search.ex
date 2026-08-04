defmodule Quillex.Buffer.Core.Search do
  @moduledoc "Pure search, navigation, and replacement transitions."

  alias Quillex.Buffer.Core.Navigation
  alias Quillex.Structs.BufState

  def set(%BufState{} = buf, query) when is_binary(query) and query != "" do
    %{
      buf
      | search_query: query,
        search_matches: matches(buf.data, query),
        search_current_index: 0
    }
  end

  def set(%BufState{} = buf, _),
    do: %{buf | search_query: nil, search_matches: [], search_current_index: 0}

  def clear(%BufState{} = buf), do: set(buf, nil)
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
        buf
        |> Quillex.Buffer.Core.History.push()
        |> replace_at(line, col, matched, replacement)
        |> refresh(buf.search_query, buf.search_current_index)

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

    refresh(updated, buf.search_query, 0)
  end

  def matches(lines, query) when is_list(lines) and is_binary(query) do
    query_lower = String.downcase(query)
    query_length = String.length(query)

    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      matches_in_line(line, String.downcase(line), query_lower, query_length, line_number, 1, [])
    end)
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

  defp refresh(buf, query, desired_index) do
    found = matches(buf.data, query)
    index = if found == [], do: 0, else: min(desired_index, length(found) - 1)
    updated = %{buf | search_matches: found, search_current_index: index}
    if found == [], do: updated, else: move_to(updated, index)
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

  defp matches_in_line(line, lower, query, query_length, line_number, col, acc) do
    case :binary.match(lower, query) do
      {position, _length} ->
        match_col = col + position
        matched = String.slice(line, position, query_length)
        offset = position + query_length

        matches_in_line(
          String.slice(line, offset..-1//1),
          String.slice(lower, offset..-1//1),
          query,
          query_length,
          line_number,
          match_col + query_length,
          [{line_number, match_col, matched} | acc]
        )

      :nomatch ->
        Enum.reverse(acc)
    end
  end
end
