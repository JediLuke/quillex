defmodule Quillex.MinimalVerticalBugSpex do
  @moduledoc """
  Minimal test case to reproduce vertical cursor movement bug
  """
  use SexySpex

  alias Quillex.TestHelpers.ScriptInspector

  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end

  # Helper function for reliable buffer clearing
  defp clear_buffer_reliable() do
    # Try multiple approaches to ensure buffer is truly cleared
    
    # First, make sure we're not in any special mode
    ScenicMcp.Probes.send_keys("escape", [])
    Process.sleep(50)
    
    # Select all and delete
    ScenicMcp.Probes.send_keys("a", [:ctrl])
    Process.sleep(100)
    ScenicMcp.Probes.send_keys("delete", [])
    Process.sleep(100)
    
    # Final sleep to ensure buffer is settled
    Process.sleep(100)
  end

  spex "Minimal Vertical Cursor Bug Reproduction",
    description: "Simplest case to show line reordering bug",
    tags: [:bug, :vertical, :minimal] do

    scenario "Type on different lines", context do
      given_ "two simple lines", context do
        clear_buffer_reliable()
        
        # Type line 1
        ScenicMcp.Probes.send_text("LINE1")
        Process.sleep(100)
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(100)
        
        # Type line 2
        ScenicMcp.Probes.send_text("LINE2")
        Process.sleep(100)
        
        initial = ScriptInspector.get_rendered_text_string()
        IO.puts("\n📄 Initial state:")
        IO.puts("'#{initial}'")
        assert initial == "LINE1\nLINE2", "Initial state should be correct"
        
        :ok
      end

      when_ "moving up and typing", context do
        IO.puts("\n🔼 ACTIONS:")
        
        # Move up to first line
        IO.puts("1. Pressing UP arrow...")
        ScenicMcp.Probes.send_keys("up", [])
        Process.sleep(200)
        
        after_up = ScriptInspector.get_rendered_text_string()
        IO.puts("   After UP: '#{after_up}'")
        
        # Type X at the end of first line
        IO.puts("2. Typing 'X'...")
        ScenicMcp.Probes.send_text("X")
        Process.sleep(200)
        
        after_x = ScriptInspector.get_rendered_text_string()
        IO.puts("   After X: '#{after_x}'")
        
        {:ok, Map.put(context, :final, after_x)}
      end

      then_ "lines should not be reordered", context do
        IO.puts("\n✅ EXPECTED: 'LINE1X\\nLINE2' or 'LINXE1\\nLINE2'")
        IO.puts("❌ BUG IF: Lines are in different order")
        
        # Check if X was inserted
        assert String.contains?(context.final, "X"), "X should be present"
        
        # Check line order
        lines = String.split(context.final, "\n")
        IO.puts("\nActual lines:")
        Enum.with_index(lines, fn line, idx ->
          IO.puts("  #{idx}: '#{line}'")
        end)
        
        # The bug manifests as lines being reordered
        if lines == ["LINE2", "LINE1X"] or lines == ["LINE2", "LINXE1"] do
          IO.puts("\n❌ BUG REPRODUCED: Lines were reordered!")
          IO.puts("This is the vertical cursor movement bug.")
        else
          IO.puts("\n✅ Lines are in correct order")
        end
        
        :ok
      end
    end
  end
end