#!/usr/bin/env elixir

# Test script to examine buffer pane scrolling state functionality
IO.puts("Testing Buffer Pane Scrolling State")
IO.puts("===================================")

# Test buffer pane state functions
alias Quillex.GUI.Components.BufferPane.State, as: BPState

# Create a buffer pane state
state = BPState.new(%{})
IO.puts("Initial buffer pane state: #{inspect(state, pretty: true)}")
IO.puts("Initial scroll_acc: #{inspect(state.scroll_acc)}")

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

# Test setting scroll position
set_scroll_state = BPState.set_scroll(state, {50, 200})
IO.puts("After set_scroll(50, 200): #{inspect(set_scroll_state.scroll_acc)}")

# Test reset scroll
reset_state = BPState.reset_scroll(set_scroll_state)
IO.puts("After reset_scroll: #{inspect(reset_state.scroll_acc)}")

# Test ensure cursor visible with different scenarios
IO.puts("\nTesting ensure_cursor_visible:")

# Test with cursor at line 1 (should be visible)
cursor1 = %{line: 1, col: 5}
visible1 = BPState.ensure_cursor_visible(state, cursor1, 800, 600)
IO.puts("Cursor at line 1: #{inspect(visible1.scroll_acc)}")

# Test with cursor at line 50 (should need scrolling)
cursor2 = %{line: 50, col: 5}
visible2 = BPState.ensure_cursor_visible(state, cursor2, 800, 600)
IO.puts("Cursor at line 50: #{inspect(visible2.scroll_acc)}")

# Test with cursor when already scrolled down
scrolled_down = BPState.scroll(state, {0, -1000}) # Scroll down significantly
cursor3 = %{line: 5, col: 5} # Cursor near top
visible3 = BPState.ensure_cursor_visible(scrolled_down, cursor3, 800, 600)
IO.puts("When scrolled down, cursor at line 5: #{inspect(visible3.scroll_acc)}")

# Test cumulative scrolling
IO.puts("\nTesting cumulative scrolling:")
cumulative = state
  |> BPState.scroll({10, 20})
  |> BPState.scroll({5, -30})
  |> BPState.scroll_lines(3)
  |> BPState.scroll_chars(-2)
IO.puts("After multiple scroll operations: #{inspect(cumulative.scroll_acc)}")

IO.puts("\nScrolling state test complete!")