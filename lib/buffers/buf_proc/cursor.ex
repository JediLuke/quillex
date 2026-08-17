defmodule Quillex.Structs.BufState.Cursor do
  use ScenicWidgets.Core.Utils.CustomGuards

  @type t :: %__MODULE__{
          num: pos_integer() | nil,
          line: pos_integer(),
          col: pos_integer()
        }

  defstruct [
    # TODO maybe we don't need cursor nums, we can just use the place in the list of cursors as their number...
    # which number cursor this is in the buffer, cursor 1 is considered the main cursor
    # TODO consider using UUId to identify cursors
    num: nil,
    # which line the cursor is on
    line: 1,
    # which column the cursor is on. Think of this like a block cursor ("normal mode") not a baret cursor ("insert mode")
    col: 1
    # mode: m
    # TODO consider cursors by other users, or by AI agents
  ]

  @doc "Create a default cursor at line 1, column 1."
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc "Create a cursor at the given line and column (both must be positive integers)."
  @spec new(pos_integer(), pos_integer()) :: t()
  def new(line, col) when all_positive_integers(line, col) do
    %__MODULE__{
      line: line,
      col: col
    }
  end

  @doc """
  Move the cursor to an absolute position. If either coordinate is invalid (not a
  positive integer) it is clamped to the nearest safe value.
  """
  @spec move(t(), {number(), number()}) :: t()
  def move(%__MODULE__{} = old_cursor, {new_line, new_col})
      when all_positive_integers(new_line, new_col) do
    old_cursor
    |> Map.put(:line, new_line)
    |> Map.put(:col, new_col)
  end

  # Clamp invalid coordinates to safe values instead of crashing
  def move(%__MODULE__{} = old_cursor, {new_line, new_col}) do
    safe_line = clamp_coord(new_line, old_cursor.line)
    safe_col = clamp_coord(new_col, old_cursor.col)

    old_cursor
    |> Map.put(:line, safe_line)
    |> Map.put(:col, safe_col)
  end

  @doc "Move the cursor up by `x` lines (will not go above line 1)."
  @spec move_up(t(), integer()) :: t()
  def move_up(%__MODULE__{} = cursor, x) when is_integer(x) do
    cursor
    |> Map.update!(:line, &max(1, &1 - x))
  end

  @doc "Move the cursor down by `x` lines."
  @spec move_down(t(), integer()) :: t()
  def move_down(%__MODULE__{} = cursor, x) when is_integer(x) do
    cursor
    |> Map.update!(:line, &(&1 + x))
  end

  @doc "Move the cursor left by `x` columns (will not go past column 1)."
  @spec move_left(t(), integer()) :: t()
  def move_left(%__MODULE__{} = cursor, x) when is_integer(x) do
    cursor
    |> Map.update!(:col, &max(1, &1 - x))
  end

  @doc "Move the cursor right by `x` columns."
  @spec move_right(t(), integer()) :: t()
  def move_right(%__MODULE__{} = cursor, x) when is_integer(x) do
    cursor
    |> Map.update!(:col, &(&1 + x))
  end

  # Clamp a coordinate to a safe positive integer, falling back to the current value
  defp clamp_coord(val, _fallback) when is_integer(val) and val >= 1, do: val
  defp clamp_coord(val, _fallback) when is_integer(val), do: 1
  defp clamp_coord(val, _fallback) when is_float(val), do: max(1, round(val))
  defp clamp_coord(_val, fallback), do: fallback
end
