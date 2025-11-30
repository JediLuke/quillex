defmodule Quillex.VerifyCursorColumnFixSpex do
  @moduledoc """
  Simple verification that cursor column adjustment is working
  """
  use SexySpex

  alias Quillex.TestHelpers.ScriptInspector

  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end

  spex "Verify Cursor Column Fix",
    description: "Simple test to verify cursor adjusts to end of shorter line",
    tags: [:cursor, :verify] do

    scenario "Column adjustment works", context do
      given_ "setup with long and short line", context do
        # Clear buffer
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(100)
        
        # Type a long line with exact position
        # Column:  123456789012345678901234567890
        ScenicMcp.Probes.send_text("ABCDEFGHIJKLMNOPQRSTUVWXYZ1234")
        Process.sleep(100)
        
        # Now we're at column 31 (after '4')
        
        # Press enter and type short line
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(100)
        ScenicMcp.Probes.send_text("SHORT")
        Process.sleep(100)
        
        # Move back up to first line
        ScenicMcp.Probes.send_keys("up", [])
        Process.sleep(100)
        
        # Move to a known position - let's go to column 20 (after 'T')
        ScenicMcp.Probes.send_keys("home", [])
        Process.sleep(50)
        for _ <- 1..19 do
          ScenicMcp.Probes.send_keys("right", [])
          Process.sleep(20)
        end
        Process.sleep(100)
        
        # Verify setup
        initial = ScriptInspector.extract_user_content()
        IO.puts("\nInitial lines: #{inspect(initial)}")
        IO.puts("Cursor should be at column 20 on first line")
        
        :ok
      end

      when_ "moving down to shorter line", context do
        # Take screenshot before moving
        ScenicMcp.Probes.take_screenshot("before_down")
        
        # Move down - cursor at column 20 should adjust to column 6 (end of "SHORT")
        ScenicMcp.Probes.send_keys("down", [])
        Process.sleep(500)
        
        # Take screenshot after moving
        ScenicMcp.Probes.take_screenshot("after_down")
        
        # Type marker
        ScenicMcp.Probes.send_text("*")
        Process.sleep(500)
        
        # Take screenshot after typing
        ScenicMcp.Probes.take_screenshot("after_marker")
        
        :ok
      end

      then_ "cursor at end of SHORT", context do
        lines = ScriptInspector.extract_user_content()
        IO.puts("\nFinal lines: #{inspect(lines)}")
        
        second_line = Enum.at(lines, 1) || ""
        IO.puts("Second line: '#{second_line}'")
        
        # We expect the cursor to be at the end of "SHORT"
        assert second_line == "SHORT*",
               "Cursor should be at end of SHORT (column adjusted from 20 to 6)"
        
        :ok
      end
    end
  end
end