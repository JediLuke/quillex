#!/bin/bash
# Script to clean up debug spex files
# Based on the analysis, we're removing debug files that were for diagnosing now-fixed bugs

cd /Users/luke/workbench/flx/quillex/test/spex

# Files to remove (debug files for fixed issues or redundant tests)
TO_REMOVE=(
  # Text truncation debug files (bug fixed)
  "debug_text_truncation_spex.exs"
  "debug_truncation_bug_spex.exs"
  "debug_retry_truncation_spex.exs"
  
  # Select All debug files (functionality covered in comprehensive tests)
  "debug_select_all_spex.exs"
  "debug_select_all_slow_spex.exs"
  "debug_multiline_select_all_spex.exs"
  "diagnose_select_all_timing_spex.exs"
  "isolated_select_all_spex.exs"  # Covered by comprehensive_text_editing_spex
  
  # Enter key debug files (keep isolated version)
  "debug_enter_key_spex.exs"
  "diagnose_enter_key_failure_spex.exs"
  
  # Buffer clearing debug files
  "debug_buffer_clear_spex.exs"
  "test_buffer_clearing_spex.exs"
  "test_with_buffer_assertions_spex.exs"
  
  # Script inspector debug files (test infrastructure debugging)
  "debug_script_inspector_spex.exs"
  "diagnose_script_inspector_spex.exs"
  
  # Vertical cursor debug files (keep minimal_vertical_bug)
  "diagnose_vertical_cursor_spex.exs"
  
  # Other debug files
  "debug_space_character_spex.exs"
  "debug_script_order_spex.exs"
  "minimal_text_editing_spex.exs"
  
  # Fixed/temporary test files
  "fixed_text_editing_spex.exs"
  
  # Trace files (debugging infrastructure)
  "trace_buffer_mutation_spex.exs"
  "trace_message_flow.exs"
  "trace_rapid_ops.exs"
  "profile_operations.exs"
  
  # Other debug/test files
  "slow_visual_text_editing_spex.exs"
  "semantic_text_editing_spex.exs"
  "real_mcp_spex.exs"
  "actual_scenic_mcp_spex.exs"
  "claude_bridge_spex.exs"
)

# Files to keep
echo "Files to KEEP (with important test cases):"
echo "- isolated_enter_key_spex.exs - Clean enter key test"
echo "- isolated_selection_edge_case_spex.exs - Specific edge case test"
echo "- verify_backspace_fix_spex.exs - Regression test for backspace with selection"
echo "- hello_world_spex.exs - Basic connectivity test"
echo "- text_editing_spex.exs - Main test suite"
echo "- comprehensive_text_editing_spex.exs - Most complete coverage including edge cases"
echo "- multiline_paste_cursor_position_spex.exs - New cursor position bug"
echo "- minimal_vertical_bug_spex.exs - Line reordering bug (still exists)"
echo "- debug_selection_bug_spex.exs - Specific selection state bug (still exists)"
echo ""

echo "Files to REMOVE (${#TO_REMOVE[@]} files):"
for file in "${TO_REMOVE[@]}"; do
  if [ -f "$file" ]; then
    echo "- $file"
  fi
done

echo ""
read -p "Are you sure you want to remove these files? (y/N) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
  for file in "${TO_REMOVE[@]}"; do
    if [ -f "$file" ]; then
      rm "$file"
      echo "Removed: $file"
    fi
  done
  echo "Cleanup complete!"
else
  echo "Cleanup cancelled."
fi