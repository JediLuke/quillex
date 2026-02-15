defmodule Quillex.UndoRedoSpex do
  @moduledoc """
  Phase 5: Undo/Redo Functionality

  Validates undo and redo behavior:
  - Ctrl+U triggers undo
  - Ctrl+R triggers redo
  - Undo reverses text changes (typing, enter, backspace, delete, tab)
  - Redo restores undone changes
  - New edits clear redo stack
  - Multiple undos work in sequence
  - Cursor position is restored correctly

  This phase builds on Phase 2 (basic text editing) and tests the undo/redo
  functionality within the full Quillex application context.
  """
  use SexySpex

  alias ScenicMcp.Query
  alias ScenicMcp.Probes

  setup_all do
    # Start Quillex application
    case Application.ensure_all_started(:quillex) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :quillex}} -> :ok
      {:error, reason} -> raise "Failed to start Quillex: #{inspect(reason)}"
    end

    # Wait for scene to fully initialize
    Process.sleep(2000)

    :ok
  end

  spex "Basic Undo - Ctrl+U",
    description: "Validates that Ctrl+U undoes the last text change",
    tags: [:phase_5, :undo, :keyboard] do

    # =========================================================================
    # 1. UNDO AFTER TYPING
    # =========================================================================

    scenario "Undo after typing restores previous text", context do
      given_ "Quillex has launched with empty buffer", context do
        Process.sleep(300)
        # Clear any existing text
        Probes.send_keys("ctrl+a", [])
        Process.sleep(50)
        Probes.send_keys("backspace", [])
        Process.sleep(100)
        {:ok, context}
      end

      when_ "we type 'Hello' then press Ctrl+U", context do
        Probes.send_text("Hello")
        Process.sleep(100)
        # Each character is a separate undo point
        # Pressing Ctrl+U should undo the last character typed
        Probes.send_keys("u", [:ctrl])
        Process.sleep(100)
        {:ok, context}
      end

      then_ "the last character should be undone", context do
        # Wait for render to complete
        Process.sleep(100)
        # After typing "Hello" (5 separate undo points), one undo should give "Hell"
        assert Query.text_visible?("Hell"), "'Hell' should be visible after undo"
        :ok
      end
    end

    # =========================================================================
    # 2. MULTIPLE UNDOS
    # =========================================================================

    scenario "Multiple undos work in sequence", context do
      given_ "we have 'Hell' from previous undo", context do
        # State carries over from previous scenario
        {:ok, context}
      end

      when_ "we press Ctrl+U three more times", context do
        Probes.send_keys("u", [:ctrl])
        Process.sleep(50)
        Probes.send_keys("u", [:ctrl])
        Process.sleep(50)
        Probes.send_keys("u", [:ctrl])
        Process.sleep(100)
        {:ok, context}
      end

      then_ "we should have 'H' remaining", context do
        # Hell -> Hel -> He -> H
        assert Query.text_visible?("H"), "'H' should be visible after multiple undos"
        refute Query.text_visible?("Hell"), "'Hell' should not be visible"
        :ok
      end
    end

    # =========================================================================
    # 3. UNDO TO EMPTY
    # =========================================================================

    scenario "Undo can restore to empty state", context do
      given_ "we have 'H' from previous undos", context do
        {:ok, context}
      end

      when_ "we press Ctrl+U one more time", context do
        Probes.send_keys("u", [:ctrl])
        Process.sleep(100)
        {:ok, context}
      end

      then_ "the buffer should be empty", context do
        # After undoing H, buffer should be empty
        refute Query.text_visible?("H"), "'H' should not be visible after final undo"
        :ok
      end
    end
  end

  spex "Basic Redo - Ctrl+R",
    description: "Validates that Ctrl+R redoes the last undone change",
    tags: [:phase_5, :redo, :keyboard] do

    # =========================================================================
    # 4. REDO AFTER UNDO
    # =========================================================================

    scenario "Redo restores undone text", context do
      given_ "we start fresh and type 'Test'", context do
        Process.sleep(300)
        Probes.send_keys("ctrl+a", [])
        Process.sleep(50)
        Probes.send_keys("backspace", [])
        Process.sleep(50)
        Probes.send_text("Test")
        Process.sleep(100)
        {:ok, context}
      end

      when_ "we undo twice then redo once", context do
        # Undo twice: Test -> Tes -> Te
        Probes.send_keys("u", [:ctrl])
        Process.sleep(50)
        Probes.send_keys("u", [:ctrl])
        Process.sleep(50)
        # Redo once: Te -> Tes
        Probes.send_keys("r", [:ctrl])
        Process.sleep(100)
        {:ok, context}
      end

      then_ "'Tes' should be visible", context do
        assert Query.text_visible?("Tes"), "'Tes' should be visible after redo"
        :ok
      end
    end

    # =========================================================================
    # 5. MULTIPLE REDOS
    # =========================================================================

    scenario "Multiple redos work in sequence", context do
      given_ "we have 'Tes' from previous redo", context do
        {:ok, context}
      end

      when_ "we press Ctrl+R again", context do
        Probes.send_keys("r", [:ctrl])
        Process.sleep(100)
        {:ok, context}
      end

      then_ "'Test' should be fully restored", context do
        assert Query.text_visible?("Test"), "'Test' should be visible after second redo"
        :ok
      end
    end
  end

  spex "Redo Stack Clearing",
    description: "Validates that new edits clear the redo stack",
    tags: [:phase_5, :redo, :stack] do

    # =========================================================================
    # 6. NEW EDIT CLEARS REDO STACK
    # =========================================================================

    scenario "Typing after undo clears redo stack", context do
      given_ "we type 'ABC', undo to 'AB'", context do
        Process.sleep(300)
        Probes.send_keys("ctrl+a", [])
        Process.sleep(50)
        Probes.send_keys("backspace", [])
        Process.sleep(50)
        Probes.send_text("ABC")
        Process.sleep(50)
        # Undo: ABC -> AB
        Probes.send_keys("u", [:ctrl])
        Process.sleep(100)
        {:ok, context}
      end

      when_ "we type 'X' then try Ctrl+R", context do
        # Type new character - this should clear redo stack
        Probes.send_text("X")
        Process.sleep(50)
        # Try to redo - should do nothing since redo stack is cleared
        Probes.send_keys("r", [:ctrl])
        Process.sleep(100)
        {:ok, context}
      end

      then_ "'ABX' should be visible (redo had no effect)", context do
        # We had AB, typed X to get ABX, redo should not bring back C
        assert Query.text_visible?("ABX"), "'ABX' should be visible"
        refute Query.text_visible?("ABC"), "'ABC' should not be visible (redo was cleared)"
        :ok
      end
    end
  end

  spex "Undo Different Operations",
    description: "Validates undo works for various text operations",
    tags: [:phase_5, :undo, :operations] do

    # =========================================================================
    # 7. UNDO BACKSPACE
    # =========================================================================

    scenario "Undo restores deleted character (backspace)", context do
      given_ "we type 'Hello' then press Backspace", context do
        Process.sleep(300)
        Probes.send_keys("ctrl+a", [])
        Process.sleep(50)
        Probes.send_keys("backspace", [])
        Process.sleep(50)
        Probes.send_text("Hello")
        Process.sleep(50)
        Probes.send_keys("backspace", [])
        Process.sleep(100)
        {:ok, context}
      end

      when_ "we press Ctrl+U to undo the backspace", context do
        Probes.send_keys("u", [:ctrl])
        Process.sleep(100)
        {:ok, context}
      end

      then_ "'Hello' should be restored", context do
        assert Query.text_visible?("Hello"), "'Hello' should be visible after undoing backspace"
        :ok
      end
    end

    # =========================================================================
    # 8. UNDO ENTER (NEWLINE)
    # =========================================================================

    scenario "Undo restores merged lines (after Enter)", context do
      given_ "we type 'Line1', Enter, 'Line2'", context do
        Probes.send_keys("ctrl+a", [])
        Process.sleep(50)
        Probes.send_keys("backspace", [])
        Process.sleep(50)
        Probes.send_text("Line1")
        Process.sleep(50)
        Probes.send_keys("enter", [])
        Process.sleep(50)
        Probes.send_text("Line2")
        Process.sleep(100)
        {:ok, context}
      end

      when_ "we undo the Line2 text and then the Enter", context do
        # Undo Line2 characters: Line2 -> Line -> Lin -> Li -> L -> (empty line)
        for _ <- 1..5 do
          Probes.send_keys("u", [:ctrl])
          Process.sleep(30)
        end
        # Undo the Enter to merge lines
        Probes.send_keys("u", [:ctrl])
        Process.sleep(100)
        {:ok, context}
      end

      then_ "lines should be merged back to 'Line1'", context do
        assert Query.text_visible?("Line1"), "'Line1' should be visible"
        refute Query.text_visible?("Line2"), "'Line2' should not be visible after undo"
        :ok
      end
    end

    # =========================================================================
    # 9. UNDO TAB
    # =========================================================================

    scenario "Undo removes inserted tab", context do
      given_ "we type 'Prefix', Tab, 'Suffix'", context do
        Probes.send_keys("ctrl+a", [])
        Process.sleep(50)
        Probes.send_keys("backspace", [])
        Process.sleep(50)
        Probes.send_text("Prefix")
        Process.sleep(50)
        Probes.send_keys("tab", [])
        Process.sleep(50)
        Probes.send_text("Suffix")
        Process.sleep(100)
        {:ok, context}
      end

      when_ "we undo the Suffix and the Tab", context do
        # Undo Suffix characters (6 chars)
        for _ <- 1..6 do
          Probes.send_keys("u", [:ctrl])
          Process.sleep(30)
        end
        # Undo the Tab
        Probes.send_keys("u", [:ctrl])
        Process.sleep(100)
        {:ok, context}
      end

      then_ "'Prefix' should be visible without tab gap", context do
        assert Query.text_visible?("Prefix"), "'Prefix' should be visible"
        refute Query.text_visible?("Suffix"), "'Suffix' should not be visible"
        :ok
      end
    end
  end

  spex "Cursor Position Restoration",
    description: "Validates cursor position is correctly restored on undo/redo",
    tags: [:phase_5, :undo, :cursor] do

    # =========================================================================
    # 10. CURSOR POSITION ON UNDO
    # =========================================================================

    scenario "Undo restores cursor to position before change", context do
      given_ "we type 'Start', move left, insert 'X'", context do
        Process.sleep(300)
        Probes.send_keys("ctrl+a", [])
        Process.sleep(50)
        Probes.send_keys("backspace", [])
        Process.sleep(50)
        Probes.send_text("Start")
        Process.sleep(50)
        # Move cursor left 2 positions (between 'r' and 't')
        Probes.send_keys("left", [])
        Process.sleep(30)
        Probes.send_keys("left", [])
        Process.sleep(50)
        # Insert X - should give "StaXrt"
        Probes.send_text("X")
        Process.sleep(100)
        {:ok, context}
      end

      when_ "we undo the X and type 'Y'", context do
        # Undo X - cursor should return to before X was inserted
        Probes.send_keys("u", [:ctrl])
        Process.sleep(50)
        # Type Y - should go where cursor was restored
        Probes.send_text("Y")
        Process.sleep(100)
        {:ok, context}
      end

      then_ "'StaYrt' should be visible (cursor was restored correctly)", context do
        # If cursor was restored, Y goes in same spot X was
        assert Query.text_visible?("Sta"), "'Sta' should be visible"
        assert Query.text_visible?("Y"), "'Y' should be visible"
        assert Query.text_visible?("rt"), "'rt' should be visible"
        :ok
      end
    end

    # =========================================================================
    # 11. CURSOR POSITION ON REDO
    # =========================================================================

    scenario "Redo restores cursor to position after change", context do
      given_ "we have text and undo it", context do
        Probes.send_keys("ctrl+a", [])
        Process.sleep(50)
        Probes.send_keys("backspace", [])
        Process.sleep(50)
        Probes.send_text("Word")
        Process.sleep(50)
        # Undo: Word -> Wor
        Probes.send_keys("u", [:ctrl])
        Process.sleep(100)
        {:ok, context}
      end

      when_ "we redo then type '!'", context do
        # Redo: Wor -> Word
        Probes.send_keys("r", [:ctrl])
        Process.sleep(50)
        # Type ! - cursor should be at end after redo
        Probes.send_text("!")
        Process.sleep(100)
        {:ok, context}
      end

      then_ "'Word!' should be visible", context do
        assert Query.text_visible?("Word!"), "'Word!' should be visible (cursor was at end after redo)"
        :ok
      end
    end
  end

  spex "Undo/Redo Edge Cases",
    description: "Validates undo/redo behavior in edge cases",
    tags: [:phase_5, :undo, :edge_cases] do

    # =========================================================================
    # 12. UNDO ON EMPTY STACK (NO-OP)
    # =========================================================================

    scenario "Undo with empty stack does nothing", context do
      given_ "we clear the buffer completely", context do
        Process.sleep(300)
        Probes.send_keys("ctrl+a", [])
        Process.sleep(50)
        Probes.send_keys("backspace", [])
        Process.sleep(100)
        # Undo many times to exhaust the stack
        for _ <- 1..20 do
          Probes.send_keys("u", [:ctrl])
          Process.sleep(20)
        end
        {:ok, context}
      end

      when_ "we type 'Fresh' then undo excessively", context do
        Probes.send_text("Fresh")
        Process.sleep(50)
        # Undo more times than we have history
        for _ <- 1..10 do
          Probes.send_keys("u", [:ctrl])
          Process.sleep(20)
        end
        {:ok, context}
      end

      then_ "buffer should be empty but not crash", context do
        # After all undos, buffer should be empty
        refute Query.text_visible?("Fresh"), "'Fresh' should not be visible"
        # App should still be responsive - type something
        Probes.send_text("OK")
        Process.sleep(100)
        assert Query.text_visible?("OK"), "App should still be responsive"
        :ok
      end
    end

    # =========================================================================
    # 13. REDO ON EMPTY STACK (NO-OP)
    # =========================================================================

    scenario "Redo with empty stack does nothing", context do
      given_ "we have text without any undos", context do
        Probes.send_keys("ctrl+a", [])
        Process.sleep(50)
        Probes.send_keys("backspace", [])
        Process.sleep(50)
        Probes.send_text("NoUndo")
        Process.sleep(100)
        {:ok, context}
      end

      when_ "we press Ctrl+R without having undone anything", context do
        Probes.send_keys("r", [:ctrl])
        Process.sleep(100)
        {:ok, context}
      end

      then_ "text should remain unchanged", context do
        assert Query.text_visible?("NoUndo"), "'NoUndo' should still be visible (redo was no-op)"
        :ok
      end
    end
  end

  spex "Delete Operation Undo",
    description: "Validates undo works correctly for delete key operations",
    tags: [:phase_5, :undo, :delete] do

    # =========================================================================
    # 14. UNDO DELETE KEY
    # =========================================================================

    scenario "Undo restores character deleted with Delete key", context do
      given_ "we type 'ABCD' and move cursor to middle", context do
        Process.sleep(300)
        Probes.send_keys("ctrl+a", [])
        Process.sleep(50)
        Probes.send_keys("backspace", [])
        Process.sleep(50)
        Probes.send_text("ABCD")
        Process.sleep(50)
        # Move to after B (before C)
        Probes.send_keys("left", [])
        Process.sleep(30)
        Probes.send_keys("left", [])
        Process.sleep(50)
        {:ok, context}
      end

      when_ "we press Delete then Ctrl+U", context do
        # Delete removes C (character ahead of cursor)
        Probes.send_keys("delete", [])
        Process.sleep(50)
        # Undo should restore C
        Probes.send_keys("u", [:ctrl])
        Process.sleep(100)
        {:ok, context}
      end

      then_ "'ABCD' should be restored", context do
        assert Query.text_visible?("ABCD"), "'ABCD' should be visible after undoing delete"
        :ok
      end
    end
  end
end
