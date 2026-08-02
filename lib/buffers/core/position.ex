defmodule Quillex.Buffer.Core.Position do
  @moduledoc "One-based line/column utilities shared by editing transitions."

  def clamp(lines, {line, col}) when is_list(lines) do
    line = line |> max(1) |> min(max(length(lines), 1))
    text = Enum.at(lines, line - 1, "")
    {line, col |> max(1) |> min(String.length(text) + 1)}
  end

  def normalize(first, second),
    do: if(first <= second, do: {first, second}, else: {second, first})

  def between?(position, first, last) do
    {low, high} = normalize(first, last)
    position >= low and position <= high
  end

  def strictly_between?(position, first, last) do
    {low, high} = normalize(first, last)
    position > low and position < high
  end
end
