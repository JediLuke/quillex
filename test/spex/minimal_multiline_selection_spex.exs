defmodule Quillex.MinimalMultilineSelectionSpex do
  @moduledoc """
  Minimal test for multi-line Shift+Down selection issue
  """
  use SexySpex

  alias Quillex.TestHelpers.ScriptInspector

  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end

  spex "Minimal Multi-line Selection Test",
    description: "Test Shift+Down selection across lines",
    tags: [:minimal, :multiline, :selection] do

    scenario "Simple Shift+Down selection", context do
      given_ "two lines of text", context do
        # Clear and type two lines
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(100)
        
        ScenicMcp.Probes.send_text("AAA")
        ScenicMcp.Probes.send_keys("enter", [])
        ScenicMcp.Probes.send_text("BBB")
        Process.sleep(200)
        
        # Move cursor to start of first line
        # First go up to first line
        ScenicMcp.Probes.send_keys("up", [])
        Process.sleep(50)
        # Then go to start of line
        ScenicMcp.Probes.send_keys("home", [])
        Process.sleep(100)
        
        initial = ScriptInspector.get_rendered_text_string()
        IO.puts("\nInitial text: '#{initial}'")
        IO.puts("Lines: #{inspect(ScriptInspector.extract_user_content())}")
        
        :ok
      end

      when_ "pressing Shift+Down from start", context do
        IO.puts("\nPressing Shift+Down...")
        ScenicMcp.Probes.send_keys("down", [:shift])
        Process.sleep(300)
        
        after_down = ScriptInspector.get_rendered_text_string()
        IO.puts("After Shift+Down: '#{after_down}'")
        
        ScenicMcp.Probes.take_screenshot("after_shift_down")
        :ok
      end

      then_ "typing should replace from start to cursor", context do
        IO.puts("\nTyping 'X'...")
        ScenicMcp.Probes.send_text("X")
        Process.sleep(300)
        
        final = ScriptInspector.get_rendered_text_string()
        IO.puts("Final: '#{final}'")
        IO.puts("Final lines: #{inspect(ScriptInspector.extract_user_content())}")
        
        # Expected: Selection from start of line 1 to start of line 2 should be replaced
        # So "AAA\n" should be replaced by "X", resulting in "XBBB"
        expected_single_line = "XBBB"
        expected_with_newline = "X\nBBB"
        
        cond do
          final == expected_single_line ->
            IO.puts("✅ SUCCESS: Multi-line selection worked (single line result)!")
          final == expected_with_newline ->
            IO.puts("✅ SUCCESS: Multi-line selection worked (preserved newline)!")
          String.contains?(final, "AAAX") or String.contains?(final, "AAA\nX") ->
            IO.puts("❌ FAILURE: Text was appended instead of replacing selection!")
            IO.puts("   This confirms the bug - selection is not active when typing")
          true ->
            IO.puts("❌ FAILURE: Unexpected result")
        end
        
        ScenicMcp.Probes.take_screenshot("final_multiline_result")
        :ok
      end
    end

    scenario "Shift+Right then Shift+Down", context do
      given_ "two lines again", context do
        # Clear and type two lines
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(100)
        
        ScenicMcp.Probes.send_text("AAA")
        ScenicMcp.Probes.send_keys("enter", [])
        ScenicMcp.Probes.send_text("BBB")
        Process.sleep(200)
        
        # Move cursor to start of first line
        # First go up to first line
        ScenicMcp.Probes.send_keys("up", [])
        Process.sleep(50)
        # Then go to start of line
        ScenicMcp.Probes.send_keys("home", [])
        Process.sleep(100)
        
        :ok
      end

      when_ "Shift+Right then Shift+Down", context do
        IO.puts("\nPressing Shift+Right...")
        ScenicMcp.Probes.send_keys("right", [:shift])
        Process.sleep(200)
        IO.puts("After Shift+Right")
        
        IO.puts("\nPressing Shift+Down...")
        ScenicMcp.Probes.send_keys("down", [:shift])
        Process.sleep(200)
        IO.puts("After Shift+Down")
        
        ScenicMcp.Probes.take_screenshot("after_shift_right_down")
        :ok
      end

      then_ "selection should span from A to B", context do
        IO.puts("\nTyping 'XXX'...")
        ScenicMcp.Probes.send_text("XXX")
        Process.sleep(300)
        
        final = ScriptInspector.get_rendered_text_string()
        IO.puts("Final: '#{final}'")
        IO.puts("Final lines: #{inspect(ScriptInspector.extract_user_content())}")
        
        # Expected: "A" from line 1 and part of line 2 replaced
        if String.contains?(final, "XXX") and not String.contains?(final, "AXXX") do
          IO.puts("✅ SUCCESS: Cross-line selection worked!")
        else
          IO.puts("❌ FAILURE: Selection not working across lines")
        end
        
        :ok
      end
    end
  end
end