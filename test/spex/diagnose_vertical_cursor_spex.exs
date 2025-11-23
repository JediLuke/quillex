defmodule Quillex.DiagnoseVerticalCursorSpex do
  @moduledoc """
  Diagnose vertical cursor movement issues
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
    
    # Verify and retry if needed
    content = ScriptInspector.get_rendered_text_string()
    
    # Try up to 3 times to clear the buffer
    Enum.reduce_while(0..2, content, fn retry_count, current_content ->
      if current_content == "" or current_content == nil do
        {:halt, current_content}
      else
        # Try different deletion approaches
        case retry_count do
          0 ->
            # Try backspace instead
            ScenicMcp.Probes.send_keys("a", [:ctrl])
            Process.sleep(50)
            ScenicMcp.Probes.send_keys("backspace", [])
            Process.sleep(100)
          1 ->
            # Try Ctrl+End then select all and delete
            ScenicMcp.Probes.send_keys("end", [:ctrl])
            Process.sleep(50)
            ScenicMcp.Probes.send_keys("a", [:ctrl])
            Process.sleep(50)
            ScenicMcp.Probes.send_keys("delete", [])
            Process.sleep(100)
          2 ->
            # Last resort: spam delete/backspace
            for _ <- 1..50 do
              ScenicMcp.Probes.send_keys("delete", [])
              Process.sleep(10)
            end
            for _ <- 1..50 do
              ScenicMcp.Probes.send_keys("backspace", [])
              Process.sleep(10)
            end
        end
        
        new_content = ScriptInspector.get_rendered_text_string()
        {:cont, new_content}
      end
    end)
    
    # Final sleep to ensure buffer is settled
    Process.sleep(100)
  end

  spex "Diagnose Vertical Cursor Movement",
    description: "Understand why vertical cursor movement test fails",
    tags: [:diagnostic, :cursor, :vertical] do

    scenario "Test cursor position after up arrow", context do
      given_ "three lines of text", context do
        clear_buffer_reliable()
        
        # Type three lines
        ScenicMcp.Probes.send_text("First line")
        Process.sleep(100)
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(100)
        
        ScenicMcp.Probes.send_text("Second line")
        Process.sleep(100)
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(100)
        
        ScenicMcp.Probes.send_text("Third line")
        Process.sleep(100)
        
        content = ScriptInspector.get_rendered_text_string()
        IO.puts("\n📄 Initial content:")
        IO.puts("'#{content}'")
        
        :ok
      end

      when_ "moving cursor up twice", context do
        IO.puts("\n🔼 CURSOR MOVEMENT SEQUENCE:")
        
        # Try different approaches
        IO.puts("\n1. Starting position - at end of 'Third line'")
        Process.sleep(200)
        
        # Approach 1: Direct up arrow
        IO.puts("\n2. Pressing UP arrow once...")
        ScenicMcp.Probes.send_keys("up", [])
        Process.sleep(200)
        
        content1 = ScriptInspector.get_rendered_text_string()
        IO.puts("   Content after first UP: '#{content1}'")
        
        # Type a marker to see where cursor is
        ScenicMcp.Probes.send_text("X")
        Process.sleep(100)
        
        content1x = ScriptInspector.get_rendered_text_string()
        IO.puts("   After typing 'X': '#{content1x}'")
        
        # Delete the X
        ScenicMcp.Probes.send_keys("backspace", [])
        Process.sleep(100)
        
        IO.puts("\n3. Pressing UP arrow again...")
        ScenicMcp.Probes.send_keys("up", [])
        Process.sleep(200)
        
        content2 = ScriptInspector.get_rendered_text_string()
        IO.puts("   Content after second UP: '#{content2}'")
        
        # Type another marker
        ScenicMcp.Probes.send_text("Y")
        Process.sleep(100)
        
        content2y = ScriptInspector.get_rendered_text_string()
        IO.puts("   After typing 'Y': '#{content2y}'")
        
        # Delete the Y
        ScenicMcp.Probes.send_keys("backspace", [])
        Process.sleep(100)
        
        IO.puts("\n4. Now typing 'EDITED '...")
        ScenicMcp.Probes.send_text("EDITED ")
        Process.sleep(300)
        
        final = ScriptInspector.get_rendered_text_string()
        IO.puts("   Final content: '#{final}'")
        
        {:ok, Map.put(context, :final_content, final)}
      end

      then_ "analyze where text was inserted", context do
        IO.puts("\n📊 ANALYSIS:")
        
        if ScriptInspector.rendered_text_contains?("EDITED") do
          IO.puts("✅ EDITED text was successfully inserted")
          
          # Check where it was inserted
          lines = String.split(context.final_content, "\n")
          Enum.with_index(lines, fn line, idx ->
            if String.contains?(line, "EDITED") do
              IO.puts("   Found on line #{idx + 1}: '#{line}'")
            end
          end)
        else
          IO.puts("❌ EDITED text was NOT inserted!")
          IO.puts("Final content: '#{context.final_content}'")
        end
        
        :ok
      end
    end

    scenario "Test with Home key first", context do
      given_ "three lines of text", context do
        clear_buffer_reliable()
        
        # Type three lines
        ScenicMcp.Probes.send_text("AAA")
        Process.sleep(50)
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(50)
        
        ScenicMcp.Probes.send_text("BBB")
        Process.sleep(50)
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(50)
        
        ScenicMcp.Probes.send_text("CCC")
        Process.sleep(100)
        
        :ok
      end

      when_ "using Home then Up arrows", context do
        IO.puts("\n🏠 HOME + UP SEQUENCE:")
        
        # Press Home first
        IO.puts("1. Pressing HOME...")
        ScenicMcp.Probes.send_keys("home", [])
        Process.sleep(200)
        
        # Now press Up
        IO.puts("2. Pressing UP...")
        ScenicMcp.Probes.send_keys("up", [])
        Process.sleep(200)
        
        IO.puts("3. Pressing UP again...")
        ScenicMcp.Probes.send_keys("up", [])
        Process.sleep(200)
        
        IO.puts("4. Typing 'TEST'...")
        ScenicMcp.Probes.send_text("TEST")
        Process.sleep(300)
        
        final = ScriptInspector.get_rendered_text_string()
        IO.puts("Final: '#{final}'")
        
        {:ok, Map.put(context, :final_content, final)}
      end

      then_ "check if TEST appeared", context do
        if ScriptInspector.rendered_text_contains?("TEST") do
          IO.puts("✅ TEST was inserted")
        else
          IO.puts("❌ TEST was NOT inserted")
        end
        
        :ok
      end
    end
  end
end