# Debug Spex Files Summary

This document preserves important findings from debug spex files before cleanup.

## Known Bugs Still Active

### 1. Vertical Cursor Line Reordering Bug
**File**: `minimal_vertical_bug_spex.exs` (KEPT)
**Issue**: When moving cursor up with arrow key and typing, lines get reordered
**Status**: Active bug, minimal reproduction kept

### 2. Selection State Bug  
**File**: `debug_selection_bug_spex.exs` (KEPT)
**Issue**: Shift+Right x2 then Shift+Left x2 doesn't properly cancel selection
**Status**: Active bug, test case kept

### 3. Multi-line Copy/Paste Cursor Position
**File**: `multiline_paste_cursor_position_spex.exs` (KEPT)
**Issue**: Cursor ends up far to the right after pasting multi-line content
**Status**: Active bug, new test created

## Fixed Issues (Tests Removed)

### Text Truncation Issues
- **Files removed**: debug_text_truncation_spex.exs, debug_truncation_bug_spex.exs, debug_retry_truncation_spex.exs
- **Issue**: Text was being truncated when replacing selected content
- **Resolution**: Fixed by adding proper async text rendering synchronization

### Select All Timing Issues
- **Files removed**: debug_select_all_*.exs files
- **Issue**: Ctrl+A was pressed before text finished rendering
- **Resolution**: Fixed with wait_for_text_to_appear() helper

### Script Inspector Issues
- **Files removed**: debug_script_inspector_spex.exs, diagnose_script_inspector_spex.exs
- **Issue**: Script inspector was returning lines in wrong order
- **Resolution**: Fixed by sorting text operations by y-position

## Important Test Patterns Preserved

### Async Text Handling
```elixir
defp wait_for_text_to_appear(expected_text, timeout_seconds \\ 2) do
  max_attempts = timeout_seconds * 10
  Enum.reduce_while(1..max_attempts, nil, fn attempt, _acc ->
    Process.sleep(100)
    current_lines = ScriptInspector.extract_user_content()
    current_text = Enum.join(current_lines, "\n")
    if String.contains?(current_text, expected_text) do
      {:halt, :ok}
    else
      if rem(attempt, 5) == 0 do
        IO.puts("Waiting (#{attempt}/#{max_attempts}): '#{current_text}'")
      end
      {:cont, nil}
    end
  end)
end
```

### Reliable Buffer Clearing
The clear_buffer_reliable() function in text_editing_spex.exs handles:
- Escape to exit special modes
- Ctrl+A doesn't work with multi-line, so fallback to Ctrl+End, Ctrl+Shift+Home
- Multiple retry attempts if needed

## Test Organization After Cleanup

1. **Basic Tests**: hello_world_spex.exs
2. **Main Test Suite**: text_editing_spex.exs
3. **Comprehensive Coverage**: comprehensive_text_editing_spex.exs
4. **Bug Reproductions**: 
   - minimal_vertical_bug_spex.exs
   - debug_selection_bug_spex.exs
   - multiline_paste_cursor_position_spex.exs
5. **Regression Tests**:
   - verify_backspace_fix_spex.exs
   - isolated_enter_key_spex.exs
   - isolated_selection_edge_case_spex.exs

## Lessons Learned

1. **Async is Everything**: Most "bugs" were actually race conditions in tests
2. **Isolation Helps**: Running tests in isolation often reveals different behavior
3. **Visual Debugging**: Screenshots are invaluable for GUI testing
4. **Minimal Reproductions**: Keep minimal bug reproductions separate from comprehensive tests