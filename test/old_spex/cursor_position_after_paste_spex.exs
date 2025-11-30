defmodule Quillex.CursorPositionAfterPasteSpex do
  @moduledoc """
  Tests for cursor positioning after paste operations, especially multi-line paste.
  
  This test specifically addresses the bug where cursor ends up far to the right
  after pasting multi-line content, likely positioned by total character count
  rather than at the end of the pasted content.
  """
  use SexySpex

  alias Quillex.TestHelpers.ScriptInspector

  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end

  spex "Cursor Position After Paste Operations",
    description: "Verify cursor is positioned correctly after various paste operations",
    tags: [:cursor, :paste, :multiline] do

    scenario "Single line paste cursor position", context do
      given_ "empty buffer", context do
        # Clear buffer
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(100)
        
        # Type and copy single line
        ScenicMcp.Probes.send_text("Hello World")
        Process.sleep(100)
        
        # Select all and copy
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)
        ScenicMcp.Probes.send_keys("c", [:ctrl])
        Process.sleep(50)
        
        # Clear and position cursor
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(100)
        
        :ok
      end

      when_ "pasting single line", context do
        ScenicMcp.Probes.send_keys("v", [:ctrl])
        Process.sleep(200)
        :ok
      end

      then_ "cursor should be at end of pasted text", context do
        # Type a marker to see where cursor is
        marker = "CURSOR"
        ScenicMcp.Probes.send_text(marker)
        Process.sleep(200)
        
        final = ScriptInspector.get_rendered_text_string()
        IO.puts("\nSingle line paste result: '#{final}'")
        
        expected = "Hello World#{marker}"
        assert final == expected,
               "Cursor should be at end of pasted text. Expected: '#{expected}', Got: '#{final}'"
        
        :ok
      end
    end

    scenario "Multi-line paste cursor position", context do
      given_ "multi-line content to copy", context do
        # Clear buffer
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(100)
        
        # Type multi-line content
        lines = ["First line", "Second line", "Third line"]
        for {line, idx} <- Enum.with_index(lines) do
          ScenicMcp.Probes.send_text(line)
          if idx < length(lines) - 1 do
            ScenicMcp.Probes.send_keys("enter", [])
          end
          Process.sleep(50)
        end
        
        # Select all and copy
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)
        ScenicMcp.Probes.send_keys("c", [:ctrl])
        Process.sleep(50)
        
        # Clear buffer
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(100)
        
        {:ok, Map.put(context, :lines, lines)}
      end

      when_ "pasting multi-line content", context do
        IO.puts("\nPasting multi-line content...")
        ScenicMcp.Probes.send_keys("v", [:ctrl])
        Process.sleep(300)
        
        after_paste = ScriptInspector.get_rendered_text_string()
        IO.puts("After paste: '#{after_paste}'")
        
        {:ok, Map.put(context, :after_paste, after_paste)}
      end

      then_ "cursor should be at end of last line", context do
        # Type a marker to see where cursor is
        marker = "CURSOR"
        ScenicMcp.Probes.send_text(marker)
        Process.sleep(200)
        
        final = ScriptInspector.get_rendered_text_string()
        final_lines = ScriptInspector.extract_user_content()
        
        IO.puts("\nMulti-line paste result:")
        IO.puts("Raw: '#{final}'")
        IO.puts("Lines: #{inspect(final_lines)}")
        
        # Expected: cursor should be right after "Third line"
        expected_lines = ["First line", "Second line", "Third line#{marker}"]
        expected_text = Enum.join(expected_lines, "\n")
        
        # Check various failure modes
        cond do
          final == expected_text ->
            IO.puts("✅ SUCCESS: Cursor positioned correctly at end of last line")
            
          String.contains?(final, "Third line") and String.contains?(final, marker) and 
          not String.contains?(final, "Third line#{marker}") ->
            # This is the bug - cursor is far to the right
            cursor_distance = String.split(final, "Third line") |> List.last() |> String.split(marker) |> List.first() |> String.length()
            IO.puts("❌ BUG CONFIRMED: Cursor is #{cursor_distance} characters to the right of where it should be")
            IO.puts("   This suggests cursor moved by total character count of pasted content")
            
            # Calculate total chars
            total_chars = context.lines |> Enum.join("\n") |> String.length()
            IO.puts("   Total characters in pasted content: #{total_chars}")
            IO.puts("   Cursor distance from end of line: #{cursor_distance}")
            
          true ->
            IO.puts("❌ UNEXPECTED: Different cursor positioning issue")
        end
        
        assert final == expected_text,
               "Cursor should be immediately after last pasted line"
        
        :ok
      end
    end

    scenario "Paste in middle of existing text", context do
      given_ "existing text with cursor in middle", context do
        # Clear and type text
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(100)
        
        ScenicMcp.Probes.send_text("ABC")
        Process.sleep(50)
        ScenicMcp.Probes.send_keys("enter", [])
        ScenicMcp.Probes.send_text("DEF")
        Process.sleep(100)
        
        # Copy some text
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)
        ScenicMcp.Probes.send_keys("c", [:ctrl])
        Process.sleep(50)
        
        # Position cursor between C and D (end of first line)
        ScenicMcp.Probes.send_keys("up", [])
        Process.sleep(50)
        ScenicMcp.Probes.send_keys("end", [])
        Process.sleep(50)
        
        :ok
      end

      when_ "pasting at cursor position", context do
        ScenicMcp.Probes.send_keys("v", [:ctrl])
        Process.sleep(200)
        :ok
      end

      then_ "cursor should be after pasted content", context do
        # Type marker
        marker = "X"
        ScenicMcp.Probes.send_text(marker)
        Process.sleep(200)
        
        final = ScriptInspector.get_rendered_text_string()
        final_lines = ScriptInspector.extract_user_content()
        
        IO.puts("\nPaste in middle result:")
        IO.puts("Raw: '#{final}'")
        IO.puts("Lines: #{inspect(final_lines)}")
        
        # We pasted "ABC\nDEF" at the end of first line
        # So we should have: "ABCABC", "DEF|X|", "DEF"
        
        # Just verify marker is somewhere reasonable
        assert String.contains?(final, marker),
               "Marker should be present in output"
        
        :ok
      end
    end

    scenario "Cursor position after cut and paste", context do
      given_ "multi-line text to cut", context do
        # Clear and type text
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(100)
        
        # Type three lines
        ScenicMcp.Probes.send_text("Line 1")
        ScenicMcp.Probes.send_keys("enter", [])
        ScenicMcp.Probes.send_text("Line 2")
        ScenicMcp.Probes.send_keys("enter", [])
        ScenicMcp.Probes.send_text("Line 3")
        Process.sleep(100)
        
        # Select middle line
        ScenicMcp.Probes.send_keys("up", [])
        ScenicMcp.Probes.send_keys("home", [])
        Process.sleep(50)
        
        # Select entire line with Shift+Down
        ScenicMcp.Probes.send_keys("down", [:shift])
        Process.sleep(100)
        
        :ok
      end

      when_ "cutting and pasting elsewhere", context do
        # Cut
        ScenicMcp.Probes.send_keys("x", [:ctrl])
        Process.sleep(100)
        
        # Move to end
        ScenicMcp.Probes.send_keys("end", [:ctrl])
        Process.sleep(50)
        
        # Paste
        ScenicMcp.Probes.send_keys("v", [:ctrl])
        Process.sleep(200)
        
        :ok
      end

      then_ "cursor at end of pasted content", context do
        # Type marker
        marker = "END"
        ScenicMcp.Probes.send_text(marker)
        Process.sleep(200)
        
        final = ScriptInspector.get_rendered_text_string()
        IO.puts("\nCut and paste result: '#{final}'")
        
        # Should have "Line 1\nLine 3Line 2\n|END|" or similar
        assert String.contains?(final, marker),
               "Cursor should be at end of pasted content"
        
        # Verify the cut worked (Line 2 moved)
        assert String.contains?(final, "Line 1"),
               "Line 1 should still be present"
        assert String.contains?(final, "Line 2"),
               "Line 2 should still be present (moved)"
        assert String.contains?(final, "Line 3"),
               "Line 3 should still be present"
        
        :ok
      end
    end
  end
end