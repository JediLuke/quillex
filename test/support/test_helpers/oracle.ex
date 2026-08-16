defmodule Quillex.TestHelpers.Oracle do
  @moduledoc """
  Independent reference model for GUI conformance tests.

  This deliberately has no dependency on Quillex buffer structs, reducers,
  stores, or processes. Keeping the model small and separate means a shared
  implementation bug cannot make both sides of a conformance assertion pass.
  """

  defstruct lines: [""], line: 1, col: 1

  @type t :: %__MODULE__{lines: [String.t()], line: pos_integer(), col: pos_integer()}

  @doc "A fresh empty document, as File → New produces."
  @spec new_document() :: t()
  def new_document, do: %__MODULE__{}

  @doc "Apply the semantic action vocabulary used by the conformance spex."
  @spec apply_actions(t(), list()) :: t()
  def apply_actions(%__MODULE__{} = document, actions) when is_list(actions) do
    Enum.reduce(actions, document, &apply_action(&2, &1))
  end

  @doc "The complete document text."
  def text(%__MODULE__{lines: lines}), do: Enum.join(lines, "\n")

  @doc "The one-based cursor position."
  def cursor(%__MODULE__{line: line, col: col}), do: {line, col}

  defp apply_action(document, {:insert, text, :at_cursor}) when is_binary(text) do
    current = current_line(document)
    {left, right} = String.split_at(current, document.col - 1)
    inserted = String.split(text, "\n")

    replacement =
      case inserted do
        [single] ->
          [left <> single <> right]

        many ->
          [left <> hd(many)] ++
            Enum.slice(many, 1, length(many) - 2) ++ [List.last(many) <> right]
      end

    lines = List.replace_at(document.lines, document.line - 1, replacement) |> List.flatten()
    final_line = document.line + length(inserted) - 1

    final_col =
      if length(inserted) == 1,
        do: document.col + String.length(text),
        else: String.length(List.last(inserted)) + 1

    %{document | lines: lines, line: final_line, col: final_col}
  end

  defp apply_action(document, {:newline, :at_cursor}) do
    current = current_line(document)
    {left, right} = String.split_at(current, document.col - 1)
    indent = Regex.run(~r/^\s*/, current) |> hd()

    lines =
      document.lines
      |> List.replace_at(document.line - 1, left)
      |> List.insert_at(document.line, indent <> right)

    %{document | lines: lines, line: document.line + 1, col: String.length(indent) + 1}
  end

  defp apply_action(%{col: col} = document, {:delete, :before_cursor}) when col > 1 do
    current = current_line(document)
    {left, right} = String.split_at(current, col - 1)
    {kept, _deleted} = String.split_at(left, -1)

    %{
      document
      | lines: List.replace_at(document.lines, document.line - 1, kept <> right),
        col: col - 1
    }
  end

  defp apply_action(%{line: line, col: 1} = document, {:delete, :before_cursor}) when line > 1 do
    previous = Enum.at(document.lines, line - 2)
    current = current_line(document)

    lines =
      document.lines
      |> List.delete_at(line - 1)
      |> List.replace_at(line - 2, previous <> current)

    %{document | lines: lines, line: line - 1, col: String.length(previous) + 1}
  end

  defp apply_action(document, {:delete, :before_cursor}), do: document

  defp apply_action(document, {:delete, :at_cursor}) do
    current = current_line(document)

    cond do
      document.col <= String.length(current) ->
        {left, right} = String.split_at(current, document.col - 1)
        {_deleted, kept} = String.split_at(right, 1)
        %{document | lines: List.replace_at(document.lines, document.line - 1, left <> kept)}

      document.line < length(document.lines) ->
        next = Enum.at(document.lines, document.line)

        lines =
          document.lines
          |> List.delete_at(document.line)
          |> List.replace_at(document.line - 1, current <> next)

        %{document | lines: lines}

      true ->
        document
    end
  end

  defp apply_action(document, {:move_cursor, :line_start}), do: %{document | col: 1}

  defp apply_action(document, {:move_cursor, :line_end}),
    do: %{document | col: String.length(current_line(document)) + 1}

  defp apply_action(document, {:move_cursor, :left, count}),
    do: %{document | col: max(1, document.col - count)}

  defp apply_action(document, {:move_cursor, :right, count}),
    do: %{document | col: min(String.length(current_line(document)) + 1, document.col + count)}

  defp apply_action(document, {:move_cursor, :up, count}) do
    line = max(1, document.line - count)
    %{document | line: line, col: min(document.col, line_length(document, line) + 1)}
  end

  defp apply_action(document, {:move_cursor, :down, count}) do
    line = min(length(document.lines), document.line + count)
    %{document | line: line, col: min(document.col, line_length(document, line) + 1)}
  end

  defp current_line(document), do: Enum.at(document.lines, document.line - 1)
  defp line_length(document, line), do: document.lines |> Enum.at(line - 1) |> String.length()
end
