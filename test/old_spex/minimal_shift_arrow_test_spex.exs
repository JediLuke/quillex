defmodule Quillex.MinimalShiftArrowTestSpex do
  @moduledoc """
  Minimal test to isolate the Shift+Arrow selection issue
  """
  use SexySpex

  alias Quillex.TestHelpers.ScriptInspector

  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end

  spex "Minimal Shift+Arrow Test",
    description: "Test single Shift+Right followed by normal typing",
    tags: [:minimal, :selection] do

    scenario "Single Shift+Right selection", context do
      given_ "simple text", context do
        # Clear and type simple text
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(100)
        
        ScenicMcp.Probes.send_text("Hello")
        Process.sleep(200)
        
        # Move cursor to beginning
        ScenicMcp.Probes.send_keys("home", [])
        Process.sleep(100)
        
        initial = ScriptInspector.get_rendered_text_string()
        IO.puts("\nInitial: '#{initial}'")
        
        :ok
      end

      when_ "pressing Shift+Right once", context do
        IO.puts("\nPressing Shift+Right...")
        ScenicMcp.Probes.send_keys("right", [:shift])
        Process.sleep(200)
        
        ScenicMcp.Probes.take_screenshot("after_shift_right")
        :ok
      end

      then_ "typing should replace selection", context do
        IO.puts("\nTyping 'X'...")
        ScenicMcp.Probes.send_text("X")
        Process.sleep(200)
        
        final = ScriptInspector.get_rendered_text_string()
        IO.puts("Final: '#{final}'")
        
        # Should be "Xello" (H replaced by X)
        expected = "Xello"
        if final == expected do
          IO.puts("✅ SUCCESS: Selection worked!")
        else
          IO.puts("❌ FAILURE: Expected '#{expected}', got '#{final}'")
        end
        
        ScenicMcp.Probes.take_screenshot("final_result")
        :ok
      end
    end

    scenario "Two Shift+Rights selection", context do
      given_ "simple text again", context do
        # Clear and type simple text
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(100)
        
        ScenicMcp.Probes.send_text("Hello")
        Process.sleep(200)
        
        # Move cursor to beginning
        ScenicMcp.Probes.send_keys("home", [])
        Process.sleep(100)
        
        :ok
      end

      when_ "pressing Shift+Right twice", context do
        IO.puts("\nPressing Shift+Right twice...")
        ScenicMcp.Probes.send_keys("right", [:shift])
        Process.sleep(200)
        IO.puts("  After first Shift+Right")
        
        ScenicMcp.Probes.send_keys("right", [:shift])
        Process.sleep(200)
        IO.puts("  After second Shift+Right")
        
        ScenicMcp.Probes.take_screenshot("after_two_shift_rights")
        :ok
      end

      then_ "typing should replace both characters", context do
        IO.puts("\nTyping 'XX'...")
        ScenicMcp.Probes.send_text("XX")
        Process.sleep(200)
        
        final = ScriptInspector.get_rendered_text_string()
        IO.puts("Final: '#{final}'")
        
        # Should be "XXllo" (He replaced by XX)
        expected = "XXllo"
        if final == expected do
          IO.puts("✅ SUCCESS: Two-char selection worked!")
        else
          IO.puts("❌ FAILURE: Expected '#{expected}', got '#{final}'")
        end
        
        :ok
      end
    end
  end
end