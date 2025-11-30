defmodule Quillex.CursorColumnAdjustmentSpex do
  @moduledoc """
  Test cursor column adjustment when moving to shorter lines.
  This addresses the bug where cursor stays at column X even when the line is shorter.
  """
  use SexySpex

  alias Quillex.TestHelpers.ScriptInspector

  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end

  spex "Cursor Column Adjustment on Shorter Lines",
    description: "Verify cursor adjusts to end of line when moving to shorter lines",
    tags: [:cursor, :column, :adjustment] do

    scenario "Cursor adjusts when moving down to shorter line", context do
      given_ "lines of decreasing length", context do
        # Clear buffer
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(100)
        
        # Type three lines of decreasing length
        ScenicMcp.Probes.send_text("This is a long line")
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(50)
        
        ScenicMcp.Probes.send_text("Short")
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(50)
        
        ScenicMcp.Probes.send_text("X")
        Process.sleep(100)
        
        # Move cursor to end of first line
        ScenicMcp.Probes.send_keys("home", [:ctrl])
        ScenicMcp.Probes.send_keys("end", [])
        Process.sleep(100)
        
        initial = ScriptInspector.extract_user_content()
        IO.puts("\nInitial setup: #{inspect(initial)}")
        assert length(initial) == 3, "Should have 3 lines"
        
        :ok
      end

      when_ "cursor moves down to shorter lines", context do
        # Move down from "This is a long line" to "Short"
        ScenicMcp.Probes.send_keys("down", [])
        Process.sleep(300)
        
        # Immediately insert text to see where cursor is
        ScenicMcp.Probes.send_text("<HERE>")
        Process.sleep(300)
        
        after_first_down = ScriptInspector.extract_user_content()
        IO.puts("\nAfter first down: #{inspect(after_first_down)}")
        
        # Move down again to "X"
        ScenicMcp.Probes.send_keys("down", [])
        Process.sleep(300)
        
        ScenicMcp.Probes.send_text("<THERE>")
        Process.sleep(300)
        
        after_second_down = ScriptInspector.extract_user_content()
        IO.puts("After second down: #{inspect(after_second_down)}")
        
        {:ok, Map.merge(context, %{
          after_first: after_first_down,
          after_second: after_second_down
        })}
      end

      then_ "cursor should be at end of each line", context do
        # Check first movement
        second_line = Enum.at(context.after_first, 1) || ""
        IO.puts("\nSecond line after first down: '#{second_line}'")
        
        # The cursor should have been adjusted to end of "Short"
        assert second_line == "Short<HERE>",
               "Cursor should be at end of 'Short', but got: '#{second_line}'"
        
        # Check second movement
        third_line = Enum.at(context.after_second, 2) || ""
        IO.puts("Third line after second down: '#{third_line}'")
        
        assert third_line == "X<THERE>",
               "Cursor should be at end of 'X', but got: '#{third_line}'"
        
        :ok
      end
    end

    scenario "Cursor adjusts when moving up to shorter line", context do
      given_ "lines with short line in middle", context do
        # Clear buffer
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(100)
        
        # Type pattern: long, short, long
        ScenicMcp.Probes.send_text("First long line here")
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(50)
        
        ScenicMcp.Probes.send_text("Mid")
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(50)
        
        ScenicMcp.Probes.send_text("Third long line here")
        Process.sleep(100)
        
        # Position at end of third line
        ScenicMcp.Probes.send_keys("end", [])
        Process.sleep(100)
        
        :ok
      end

      when_ "cursor moves up to shorter line", context do
        # Move up to "Mid"
        ScenicMcp.Probes.send_keys("up", [])
        Process.sleep(300)
        
        ScenicMcp.Probes.send_text("*")
        Process.sleep(300)
        
        result = ScriptInspector.extract_user_content()
        {:ok, Map.put(context, :result, result)}
      end

      then_ "cursor should be at end of short line", context do
        second_line = Enum.at(context.result, 1) || ""
        
        assert second_line == "Mid*",
               "Cursor should be at end of 'Mid', but got: '#{second_line}'"
        
        :ok
      end
    end

    scenario "Boundary check - cursor can't go past line end", context do
      given_ "a short line", context do
        # Clear buffer
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(100)
        
        # Type a short line
        ScenicMcp.Probes.send_text("ABC")
        Process.sleep(100)
        
        # Position at end
        ScenicMcp.Probes.send_keys("end", [])
        Process.sleep(100)
        
        :ok
      end

      when_ "attempting to move right past end", context do
        # Try to move right multiple times
        for _ <- 1..5 do
          ScenicMcp.Probes.send_keys("right", [])
          Process.sleep(50)
        end
        
        # Type marker
        ScenicMcp.Probes.send_text("*")
        Process.sleep(200)
        
        :ok
      end

      then_ "cursor stays at line end", context do
        content = ScriptInspector.get_rendered_text_string()
        
        assert content == "ABC*",
               "Cursor should stay at end of line. Got: '#{content}'"
        
        :ok
      end
    end
  end
end