defmodule Quillex.Buffer.Core.History do
  @moduledoc "Explicit undo/redo snapshot ownership for the editing core."

  alias Quillex.Structs.BufState

  def push(%BufState{} = buf) do
    snapshot = {buf.data, buf.cursor, buf.selection}

    %{
      buf
      | undo_stack: Enum.take([snapshot | buf.undo_stack], buf.undo_max_size),
        redo_stack: [],
        dirty?: true
    }
  end

  def undo(%BufState{undo_stack: []} = buf), do: buf

  def undo(%BufState{undo_stack: [{data, cursor, selection} | rest]} = buf) do
    current = {buf.data, buf.cursor, buf.selection}

    %{
      buf
      | data: data,
        cursor: cursor,
        selection: selection,
        undo_stack: rest,
        redo_stack: [current | buf.redo_stack]
    }
  end

  def redo(%BufState{redo_stack: []} = buf), do: buf

  def redo(%BufState{redo_stack: [{data, cursor, selection} | rest]} = buf) do
    current = {buf.data, buf.cursor, buf.selection}

    %{
      buf
      | data: data,
        cursor: cursor,
        selection: selection,
        redo_stack: rest,
        undo_stack: [current | buf.undo_stack]
    }
  end
end
