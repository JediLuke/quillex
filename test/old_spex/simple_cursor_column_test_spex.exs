defmodule Quillex.SimpleCursorColumnTestSpex do
  @moduledoc """
  Simple test to verify cursor column adjustment on shorter lines
  """
  use SexySpex

  alias Quillex.TestHelpers.ScriptInspector

  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end

  spex "Simple Cursor Column Test",
    description: "Test cursor adjusts to end of shorter line",
    tags: [:cursor, :simple] do

    scenario "Basic column adjustment", context do
      given_ "two lines of different lengths", context do
        # Clear buffer
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(100)
        
        # Type a long line
        ScenicMcp.Probes.send_text("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        Process.sleep(200)
        
        lines_after_first = ScriptInspector.extract_user_content()
        IO.puts("\nAfter typing first line: #{inspect(lines_after_first)}")
        
        # Press enter and type a short line
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(200)
        
        lines_after_enter = ScriptInspector.extract_user_content()
        IO.puts("After pressing enter: #{inspect(lines_after_enter)}")
        
        ScenicMcp.Probes.send_text("123")
        Process.sleep(200)
        
        lines_after_second = ScriptInspector.extract_user_content()
        IO.puts("After typing second line: #{inspect(lines_after_second)}")
        
        # Move cursor back to end of first line
        ScenicMcp.Probes.send_keys("up", [])
        Process.sleep(200)
        ScenicMcp.Probes.send_keys("end", [])
        Process.sleep(200)
        
        initial_lines = ScriptInspector.extract_user_content()
        IO.puts("\nFinal setup state:")
        IO.puts("Lines: #{inspect(initial_lines)}")
        
        :ok
      end

      when_ "moving down to shorter line", context do
        # Move down (cursor should go from column 27 to column 4)
        ScenicMcp.Probes.send_keys("down", [])
        Process.sleep(300)
        
        lines_after_down = ScriptInspector.extract_user_content()
        IO.puts("\nAfter moving down: #{inspect(lines_after_down)}")
        
        # Type a marker to show cursor position
        ScenicMcp.Probes.send_text("*")
        Process.sleep(300)
        
        lines_after_marker = ScriptInspector.extract_user_content()
        IO.puts("After typing marker: #{inspect(lines_after_marker)}")
        
        # Try typing more text
        ScenicMcp.Probes.send_text("TEST")
        Process.sleep(300)
        
        lines_after_test = ScriptInspector.extract_user_content()
        IO.puts("After typing TEST: #{inspect(lines_after_test)}")
        
        :ok
      end

      then_ "cursor should be at end of short line", context do
        final_lines = ScriptInspector.extract_user_content()
        
        IO.puts("\nFinal state:")
        IO.puts("Lines: #{inspect(final_lines)}")
        
        # Check if any text was added to the second line
        second_line = Enum.at(final_lines, 1) || ""
        IO.puts("Second line: '#{second_line}'")
        
        # Check if cursor adjusted to end of line
        has_additions = String.contains?(second_line, "*") or 
                       String.contains?(second_line, "TEST") or
                       String.length(second_line) > 3
        
        assert has_additions,
               "Text should be added at cursor position. Line is still '#{second_line}'"
        
        # The expected behavior is cursor at end of "123", so "123*TEST"
        expected = String.contains?(second_line, "123*") or String.contains?(second_line, "123TEST")
        assert expected,
               "Cursor should be at end of short line. Got '#{second_line}'"
        
        :ok
      end
    end
  end
end