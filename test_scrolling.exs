#!/usr/bin/env elixir

# Test script to examine scrolling functionality
IO.puts("Testing Quillex Scrolling Implementation")
IO.puts("=======================================")

# Test FileAPI functionality
file_result = Quillex.API.FileAPI.open("test/support/spinozas_ethics_p1.txt")
IO.puts("FileAPI open result: #{inspect(file_result)}")

# Check if we can get buffer info
case file_result do
  {:ok, result} ->
    IO.puts("Successfully opened file!")
    IO.puts("Buffer ref: #{inspect(result.buffer_ref)}")
    IO.puts("File path: #{result.file_path}")
    IO.puts("Lines: #{result.lines}")
    IO.puts("Bytes: #{result.bytes}")
    
    # Get current buffer info
    info_result = Quillex.API.FileAPI.info()
    IO.puts("Buffer info: #{inspect(info_result)}")
    
    # Test buffer pane state functions
    alias Quillex.GUI.Components.BufferPane.State, as: BPState
    
    # Create a buffer pane state
    state = BPState.new(%{})
    IO.puts("Initial buffer pane state: #{inspect(state)}")
    IO.puts("Initial scroll_acc: #{inspect(state.scroll_acc)}")
    
    # Test scrolling functions
    IO.puts("\nTesting scrolling functions:")
    
    # Test basic scroll
    scrolled_state = BPState.scroll(state, {0, -100})
    IO.puts("After scroll(0, -100): #{inspect(scrolled_state.scroll_acc)}")
    
    # Test line scrolling  
    line_scrolled = BPState.scroll_lines(state, -5)
    IO.puts("After scroll_lines(-5): #{inspect(line_scrolled.scroll_acc)}")
    
    # Test character scrolling
    char_scrolled = BPState.scroll_chars(state, 10)
    IO.puts("After scroll_chars(10): #{inspect(char_scrolled.scroll_acc)}")
    
    # Test ensure cursor visible
    cursor = %{line: 10, col: 5}
    cursor_visible = BPState.ensure_cursor_visible(state, cursor, 800, 600)
    IO.puts("After ensure_cursor_visible for line 10: #{inspect(cursor_visible.scroll_acc)}")

  {:error, reason} ->
    IO.puts("Failed to open file: #{reason}")
end