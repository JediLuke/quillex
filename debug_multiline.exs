#!/usr/bin/env elixir

# Simple script to debug multi-line selection
Mix.install([])

defmodule MultilineDebug do
  alias Quillex.Structs.{BufState, Cursor}
  alias Quillex.GUI.Components.BufferPane.Mutator

  def test_multiline_selection do
    # Create initial buffer state
    buf = %BufState{
      data: ["First line text", "Second line text", "Third line text"],
      cursors: [%Cursor{line: 2, col: 1}],  # Start at beginning of line 2
      selection: nil
    }

    IO.puts("=== INITIAL STATE ===")
    IO.puts("Data: #{inspect(buf.data)}")
    IO.puts("Cursor: #{inspect(hd(buf.cursors))}")
    IO.puts("Selection: #{inspect(buf.selection)}")

    # Simulate the exact same selection as the test:
    # 7 x Shift+Right (select "Second ")
    buf1 = Enum.reduce(1..7, buf, fn _, acc -> 
      result = Mutator.select_text(acc, :right, 1)
      IO.puts("After right #{inspect(acc.cursors)} -> #{inspect(result.cursors)}, selection: #{inspect(result.selection)}")
      result
    end)

    IO.puts("\n=== AFTER SELECTING 'Second ' ===")
    IO.puts("Selection: #{inspect(buf1.selection)}")

    # 1 x Shift+Down (extend to next line)
    buf2 = Mutator.select_text(buf1, :down, 1)

    IO.puts("\n=== AFTER SHIFT+DOWN ===")
    IO.puts("Selection: #{inspect(buf2.selection)}")

    # 5 x Shift+Right (select "Third")
    buf3 = Enum.reduce(1..5, buf2, fn _, acc ->
      result = Mutator.select_text(acc, :right, 1)
      IO.puts("After right #{inspect(acc.cursors)} -> #{inspect(result.cursors)}, selection: #{inspect(result.selection)}")
      result
    end)

    IO.puts("\n=== FINAL SELECTION ===")
    IO.puts("Selection: #{inspect(buf3.selection)}")

    # Test deletion
    buf4 = Mutator.delete_selected_text(buf3)

    IO.puts("\n=== AFTER DELETION ===")
    IO.puts("Data: #{inspect(buf4.data)}")
    IO.puts("Cursor: #{inspect(hd(buf4.cursors))}")
    IO.puts("Selection: #{inspect(buf4.selection)}")

    # Test insertion
    buf5 = Mutator.insert_text(buf4, {hd(buf4.cursors).line, hd(buf4.cursors).col}, "REPLACED")

    IO.puts("\n=== AFTER INSERTING 'REPLACED' ===")
    IO.puts("Data: #{inspect(buf5.data)}")

    buf5
  end
end

MultilineDebug.test_multiline_selection()