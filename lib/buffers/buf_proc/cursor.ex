defmodule Quillex.Structs.BufState.Cursor do
  use ScenicWidgets.Core.Utils.CustomGuards

  @type t :: %__MODULE__{
          num: pos_integer() | nil,
          line: pos_integer(),
          col: pos_integer(),
          desired_col: pos_integer()
        }

  defstruct [
    # TODO maybe we don't need cursor nums, we can just use the place in the list of cursors as their number...
    # which number cursor this is in the buffer, cursor 1 is considered the main cursor
    # TODO consider using UUId to identify cursors
    num: nil,
    # which line the cursor is on
    line: 1,
    # which column the cursor is on. Think of this like a block cursor ("normal mode") not a baret cursor ("insert mode")
    col: 1,
    # The column the cursor WANTS — the ghost cursor. `col` is where it can
    # actually sit on this line; `desired_col` is where it was put, and where
    # it goes back to as soon as a line is wide enough to hold it. Walking
    # down through a five-character line and out the other side should not
    # cost you the column you were working in.
    #
    # `move/2` — an absolute move, which is what a click, Home/End, a word
    # jump and every text edit ultimately perform — re-establishes it.
    # `move_vertical/2` reads it and leaves it alone. That split is the whole
    # feature: the two are the only ways the column is allowed to change.
    desired_col: 1
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
      col: col,
      desired_col: col
    }
  end

  @doc """
  Move the cursor to an absolute position. If either coordinate is invalid (not a
  positive integer) it is clamped to the nearest safe value.

  An absolute move establishes a new column, so it takes the ghost cursor with
  it: after this, vertical movement aims at `new_col`.
  """
  @spec move(t(), {number(), number()}) :: t()
  def move(%__MODULE__{} = old_cursor, {new_line, new_col})
      when all_positive_integers(new_line, new_col) do
    old_cursor
    |> Map.put(:line, new_line)
    |> Map.put(:col, new_col)
    |> Map.put(:desired_col, new_col)
  end

  # Clamp invalid coordinates to safe values instead of crashing
  def move(%__MODULE__{} = old_cursor, {new_line, new_col}) do
    safe_line = clamp_coord(new_line, old_cursor.line)
    safe_col = clamp_coord(new_col, old_cursor.col)

    old_cursor
    |> Map.put(:line, safe_line)
    |> Map.put(:col, safe_col)
    |> Map.put(:desired_col, safe_col)
  end

  @doc """
  Move the cursor to another line, landing on the column it wants.

  `max_col` is the last column that line has room for (its length plus one).
  The cursor sits at `min(desired_col, max_col)` — and `desired_col` does not
  move, so the next line that IS wide enough gets the cursor back at the
  column it was put in. This is the only movement that does not establish a
  new column; everything else goes through `move/2`.
  """
  @spec move_vertical(t(), {integer(), pos_integer()}) :: t()
  def move_vertical(%__MODULE__{desired_col: desired} = cursor, {new_line, max_col}) do
    cursor
    |> Map.put(:line, new_line)
    |> Map.put(:col, min(desired, max_col))
  end

  @doc """
  Forget the column the cursor wanted and want the one it is on.

  Undo and redo restore a whole cursor, ghost and all. The edit being undone
  is what put that cursor where it is, so the column it was reaching for
  before the edit is not a column the user is still reaching for.
  """
  @spec settle(t()) :: t()
  def settle(%__MODULE__{col: col} = cursor), do: Map.put(cursor, :desired_col, col)

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
    |> settle()
  end

  @doc "Move the cursor right by `x` columns."
  @spec move_right(t(), integer()) :: t()
  def move_right(%__MODULE__{} = cursor, x) when is_integer(x) do
    cursor
    |> Map.update!(:col, &(&1 + x))
    |> settle()
  end

  # Clamp a coordinate to a safe positive integer, falling back to the current value
  defp clamp_coord(val, _fallback) when is_integer(val) and val >= 1, do: val
  defp clamp_coord(val, _fallback) when is_integer(val), do: 1
  defp clamp_coord(val, _fallback) when is_float(val), do: max(1, round(val))
  defp clamp_coord(_val, fallback), do: fallback
end
