defmodule Quillex.DebugTextTruncationTest do
  use ExUnit.Case
  
  alias Quillex.Structs.BufState
  alias Quillex.GUI.Components.BufferPane
  alias Quillex.Buffer.Process.Reducer
  
  test "text insertion without truncation" do
    # Create a buffer with some text
    buf = %BufState{
      data: ["Hello world"],
      cursors: [%BufState.Cursor{line: 1, col: 12}],  # After "Hello world"
      selection: nil
    }
    
    # Insert text
    result = Reducer.process(buf, {:insert, " selection test", :at_cursor})
    
    assert result.data == ["Hello world selection test"]
  end
  
  test "select all and replace text" do
    # Create a buffer with multi-line text
    buf = %BufState{
      data: ["Some text on the first line", "Second line has more content", "Third line"],
      cursors: [%BufState.Cursor{line: 1, col: 1}],
      selection: nil
    }
    
    # Select all
    buf_with_selection = Reducer.process(buf, :select_all)
    
    IO.puts("\nAfter select all:")
    IO.puts("Selection: #{inspect(buf_with_selection.selection)}")
    IO.puts("Cursor: #{inspect(buf_with_selection.cursors)}")
    
    # Replace with new text
    result = Reducer.process(buf_with_selection, {:insert, "All content replaced", :at_cursor})
    
    IO.puts("\nAfter replacement:")
    IO.puts("Data: #{inspect(result.data)}")
    
    assert result.data == ["All content replaced"]
  end
  
  test "replace selected text with longer text" do
    # Create a buffer with short text
    buf = %BufState{
      data: ["Short"],
      cursors: [%BufState.Cursor{line: 1, col: 1}],
      selection: nil
    }
    
    # Select all
    buf = BufferPane.Mutator.select_all(buf)
    
    # Replace with longer text - exactly 26 characters
    result = Reducer.process(buf, {:insert, "RETRY-All content replaced", :at_cursor})
    
    IO.puts("\nReplacing 'Short' with 26-char text:")
    IO.puts("Result: #{inspect(result.data)}")
    
    assert result.data == ["RETRY-All content replaced"]
    assert String.length(hd(result.data)) == 26
  end
  
  test "direct buffer mutation functions" do
    # Test the low-level functions directly
    buf = %BufState{
      data: ["Test"],
      cursors: [%BufState.Cursor{line: 1, col: 1}],
      selection: %{start: {1, 1}, end: {1, 5}}
    }
    
    # Delete selected text
    buf = BufferPane.Mutator.delete_selected_text(buf)
    assert buf.data == [""]
    
    # Insert text at cursor
    buf = BufferPane.Mutator.insert_text(buf, {1, 1}, "All content replaced")
    assert buf.data == ["All content replaced"]
  end
end