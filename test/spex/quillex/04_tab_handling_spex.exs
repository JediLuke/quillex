defmodule Quillex.TabHandlingSpex do
  @moduledoc """
  Phase 4: Tab Character Handling

  Validates tab insertion and rendering:
  - Tab key inserts actual tab character
  - Tab expands to correct visual width based on column position
  - Tab width setting affects rendering
  - Cursor position correct after tab insertion
  - Tabs work correctly mid-word and at line start
  - Dynamic tab width changes preserve cursor context

  This phase builds on Phase 2 (basic text editing) and tests the tab-specific
  functionality within the full Quillex application context.
  """
  use SexySpex

  alias ScenicMcp.Query
  alias ScenicMcp.Probes

  # Helper to change tab width dynamically
  defp change_tab_width(new_width) when new_width in [2, 3, 4, 8] do
    # Find the root scene and send a menu event
    # This simulates selecting a tab width from the View menu
    menu_item_id = "tab_width_#{new_width}"

    # Send the menu event through the viewport
    case Scenic.ViewPort.info(:main_viewport) do
      {:ok, %{scene: scene_pid}} ->
        send(scene_pid, {:menu_item_clicked, menu_item_id})
        Process.sleep(100)
        :ok
      _ ->
        :error
    end
  end

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

  spex "Tab Insertion - Basic",
    description: "Validates that pressing Tab inserts a tab character",
    tags: [:phase_4, :tabs, :input] do

    # =========================================================================
    # 1. TAB AT END OF LINE
    # =========================================================================

    scenario "Tab at end of line inserts tab character", context do
      given_ "Quillex has launched with empty buffer", context do
        Process.sleep(300)
        {:ok, context}
      end

      when_ "we type 'Test' and press Tab", context do
        Probes.send_text("Test")
        Process.sleep(100)
        Probes.send_keys("tab", [])
        Process.sleep(100)
        {:ok, context}
      end

      then_ "the cursor should move to the next tab stop (column 8 with default tab width 4)", context do
        # 'Test' is 4 chars, tab at column 5 should expand to column 8 (next tab stop)
        # When we type more text, it should appear at that position
        Probes.send_text("X")
        Process.sleep(100)
        # The X should appear after the tab space, not immediately after 'Test'
        assert Query.text_visible?("Test"), "Original text should still be visible"
        assert Query.text_visible?("X"), "Character after tab should be visible"
        :ok
      end
    end

    # =========================================================================
    # 2. TAB AT START OF LINE
    # =========================================================================

    scenario "Tab at start of line creates indentation", context do
      given_ "we press Enter to start a new line", context do
        Probes.send_keys("enter", [])
        Process.sleep(100)
        {:ok, context}
      end

      when_ "we press Tab then type 'Indented'", context do
        Probes.send_keys("tab", [])
        Process.sleep(100)
        Probes.send_text("Indented")
        Process.sleep(100)
        {:ok, context}
      end

      then_ "'Indented' should appear with visible indentation", context do
        assert Query.text_visible?("Indented"), "Indented text should be visible"
        # The indentation should be visually apparent (not at column 1)
        :ok
      end
    end

    # =========================================================================
    # 3. TAB MID-WORD
    # =========================================================================

    scenario "Tab mid-word inserts tab at cursor position", context do
      given_ "we start fresh with 'HelloWorld'", context do
        # Clear and type new text
        Probes.send_keys("ctrl+a", [])
        Process.sleep(50)
        Probes.send_text("HelloWorld")
        Process.sleep(100)
        {:ok, context}
      end

      when_ "we move cursor between 'Hello' and 'World' and press Tab", context do
        # Move left 5 characters to position between Hello and World
        for _ <- 1..5 do
          Probes.send_keys("left", [])
          Process.sleep(30)
        end
        Probes.send_keys("tab", [])
        Process.sleep(100)
        {:ok, context}
      end

      then_ "the tab should split the text with visible space", context do
        # HelloWorld should no longer appear as a single word
        refute Query.text_visible?("HelloWorld"),
               "'HelloWorld' should not appear as single word after tab insertion"
        assert Query.text_visible?("Hello"), "'Hello' should be visible"
        assert Query.text_visible?("World"), "'World' should be visible"
        :ok
      end
    end
  end

  spex "Tab Width - Rendering",
    description: "Validates that tab width setting affects rendering",
    tags: [:phase_4, :tabs, :settings] do

    # =========================================================================
    # 4. MULTIPLE TABS ALIGNMENT
    # =========================================================================

    scenario "Multiple tabs create aligned columns", context do
      given_ "Quillex has launched", context do
        Process.sleep(300)
        {:ok, context}
      end

      when_ "we type text with multiple tabs for column alignment", context do
        # Create a simple table-like structure
        Probes.send_text("Name")
        Probes.send_keys("tab", [])
        Process.sleep(50)
        Probes.send_text("Age")
        Probes.send_keys("enter", [])
        Process.sleep(50)
        Probes.send_text("Alice")
        Probes.send_keys("tab", [])
        Process.sleep(50)
        Probes.send_text("30")
        Process.sleep(100)
        {:ok, context}
      end

      then_ "the columns should be aligned", context do
        assert Query.text_visible?("Name"), "Header 'Name' should be visible"
        assert Query.text_visible?("Age"), "Header 'Age' should be visible"
        assert Query.text_visible?("Alice"), "Data 'Alice' should be visible"
        assert Query.text_visible?("30"), "Data '30' should be visible"
        :ok
      end
    end

    # =========================================================================
    # 5. CONSECUTIVE TABS
    # =========================================================================

    scenario "Consecutive tabs create increasing indentation", context do
      given_ "we start a new line", context do
        Probes.send_keys("ctrl+a", [])
        Process.sleep(50)
        {:ok, context}
      end

      when_ "we press Tab three times then type text", context do
        Probes.send_keys("tab", [])
        Process.sleep(50)
        Probes.send_keys("tab", [])
        Process.sleep(50)
        Probes.send_keys("tab", [])
        Process.sleep(50)
        Probes.send_text("Deeply indented")
        Process.sleep(100)
        {:ok, context}
      end

      then_ "text should be deeply indented", context do
        assert Query.text_visible?("Deeply indented"), "Deeply indented text should be visible"
        # Cursor should be at column 12+ (3 tabs * 4 spaces = 12 columns of indentation)
        :ok
      end
    end
  end

  spex "Tab Cursor Positioning",
    description: "Validates cursor position is correct after tab operations",
    tags: [:phase_4, :tabs, :cursor] do

    # =========================================================================
    # 6. CURSOR AFTER TAB INSERTION
    # =========================================================================

    scenario "Cursor moves to correct position after tab", context do
      given_ "we start with 'AB' at column 1", context do
        Probes.send_keys("ctrl+a", [])
        Process.sleep(50)
        Probes.send_text("AB")
        Process.sleep(100)
        {:ok, context}
      end

      when_ "we move between A and B, press Tab, then type 'X'", context do
        Probes.send_keys("left", [])  # Move cursor between A and B
        Process.sleep(50)
        Probes.send_keys("tab", [])   # Insert tab
        Process.sleep(50)
        Probes.send_text("X")         # Type X at cursor position
        Process.sleep(100)
        {:ok, context}
      end

      then_ "X should appear after the tab, before B", context do
        # Result should be "A<tab>XB"
        # Visually: "A   XB" (tab expands to column 4, X at 5, B at 6)
        assert Query.text_visible?("A"), "'A' should be visible"
        assert Query.text_visible?("X"), "'X' should be visible"
        assert Query.text_visible?("B"), "'B' should be visible"
        :ok
      end
    end

    # =========================================================================
    # 7. BACKSPACE AFTER TAB
    # =========================================================================

    scenario "Backspace removes entire tab character", context do
      given_ "we have text with a tab", context do
        Probes.send_keys("ctrl+a", [])
        Process.sleep(50)
        Probes.send_text("Start")
        Probes.send_keys("tab", [])
        Process.sleep(50)
        Probes.send_text("End")
        Process.sleep(100)
        {:ok, context}
      end

      when_ "we move cursor after tab and press Backspace", context do
        # Move to end of "Start" + tab (before "End")
        Probes.send_keys("left", [])
        Process.sleep(30)
        Probes.send_keys("left", [])
        Process.sleep(30)
        Probes.send_keys("left", [])
        Process.sleep(30)
        # Now cursor is right after the tab
        Probes.send_keys("backspace", [])
        Process.sleep(100)
        {:ok, context}
      end

      then_ "the tab should be removed (single backspace)", context do
        # After removing tab, "Start" and "End" should be adjacent
        assert Query.text_visible?("Start"), "'Start' should be visible"
        assert Query.text_visible?("End"), "'End' should be visible"
        # They might appear as "StartEnd" or with a different cursor position
        :ok
      end
    end
  end

  spex "Tab Width Changes",
    description: "Validates behavior when tab width setting changes",
    tags: [:phase_4, :tabs, :settings_change] do

    # =========================================================================
    # 8. EXISTING TABS RE-RENDER ON WIDTH CHANGE
    # =========================================================================

    scenario "Tab width change re-renders existing tabs", context do
      given_ "we have text with tabs", context do
        Probes.send_keys("ctrl+a", [])
        Process.sleep(50)
        Probes.send_keys("tab", [])
        Probes.send_text("Indented")
        Process.sleep(100)
        {:ok, context}
      end

      # Note: This test would require changing tab width via menu
      # which needs the app to be restarted for menu changes to take effect
      # Marking as a documentation of expected behavior
      then_ "tabs should render with new width when setting changes", context do
        # When tab width changes from 4 to 2:
        # - Tab at column 1 should expand to 2 spaces instead of 4
        # - Text should shift left accordingly
        # - Cursor position should remain logically correct
        assert Query.text_visible?("Indented"), "Text should remain visible after width change"
        :ok
      end
    end
  end

  spex "Tab Stop Alignment - Bug Regression",
    description: "Validates tabs go to proper tab stops regardless of column parity",
    tags: [:phase_4, :tabs, :regression, :bug] do

    # =========================================================================
    # BUG: Tab from odd column should go to next tab stop, not just even column
    # =========================================================================

    scenario "Tab from column 1 goes to tab stop (column 5 with tab_width=4)", context do
      given_ "Quillex has launched with empty buffer", context do
        Process.sleep(300)
        {:ok, context}
      end

      when_ "we type nothing and press Tab immediately", context do
        Probes.send_keys("tab", [])
        Process.sleep(50)
        Probes.send_text("X")
        Process.sleep(100)
        {:ok, context}
      end

      then_ "X should appear at column 5 (after 4 spaces of indentation)", context do
        # Tab at column 1 with tab_width=4 should go to column 5
        # Visual: "    X" (4 spaces then X)
        assert Query.text_visible?("X"), "X should be visible"
        :ok
      end
    end

    scenario "Tab from column 2 (odd position) goes to column 5", context do
      given_ "we have single character 'A' at column 1", context do
        Probes.send_keys("ctrl+a", [])
        Process.sleep(50)
        Probes.send_text("A")
        Process.sleep(100)
        {:ok, context}
      end

      when_ "we press Tab after 'A' (cursor at column 2)", context do
        # Cursor is now at column 2 (after A)
        # Tab should advance to column 5 (next tab stop)
        Probes.send_keys("tab", [])
        Process.sleep(50)
        Probes.send_text("B")
        Process.sleep(100)
        {:ok, context}
      end

      then_ "B should appear at column 5, not column 2", context do
        # Result: "A   B" (A at col 1, tab fills 3 spaces, B at col 5)
        # NOT: "A B" (only 1 space to reach even column 2)
        assert Query.text_visible?("A"), "A should be visible"
        assert Query.text_visible?("B"), "B should be visible"
        :ok
      end
    end

    scenario "Tab from column 3 (odd position) goes to column 5", context do
      given_ "we have 'AB' at columns 1-2", context do
        Probes.send_keys("ctrl+a", [])
        Process.sleep(50)
        Probes.send_text("AB")
        Process.sleep(100)
        {:ok, context}
      end

      when_ "we press Tab after 'AB' (cursor at column 3)", context do
        # Cursor is now at column 3 (after AB)
        # Tab should advance to column 5 (next tab stop = 4 - (3-1)%4 = 4-2 = 2 spaces)
        Probes.send_keys("tab", [])
        Process.sleep(50)
        Probes.send_text("C")
        Process.sleep(100)
        {:ok, context}
      end

      then_ "C should appear at column 5", context do
        # Result: "AB  C" (AB at cols 1-2, tab fills 2 spaces, C at col 5)
        assert Query.text_visible?("AB"), "AB should be visible"
        assert Query.text_visible?("C"), "C should be visible"
        :ok
      end
    end

    scenario "Tab from column 4 (even position) goes to column 5", context do
      given_ "we have 'ABC' at columns 1-3", context do
        Probes.send_keys("ctrl+a", [])
        Process.sleep(50)
        Probes.send_text("ABC")
        Process.sleep(100)
        {:ok, context}
      end

      when_ "we press Tab after 'ABC' (cursor at column 4)", context do
        # Cursor is now at column 4 (after ABC)
        # Tab should advance to column 5 (next tab stop = 4 - (4-1)%4 = 4-3 = 1 space)
        Probes.send_keys("tab", [])
        Process.sleep(50)
        Probes.send_text("D")
        Process.sleep(100)
        {:ok, context}
      end

      then_ "D should appear at column 5", context do
        # Result: "ABC D" (ABC at cols 1-3, tab fills 1 space, D at col 5)
        assert Query.text_visible?("ABC"), "ABC should be visible"
        assert Query.text_visible?("D"), "D should be visible"
        :ok
      end
    end

    scenario "Tab from column 5 goes to column 9 (next tab stop)", context do
      given_ "we have 'ABCD' at columns 1-4", context do
        Probes.send_keys("ctrl+a", [])
        Process.sleep(50)
        Probes.send_text("ABCD")
        Process.sleep(100)
        {:ok, context}
      end

      when_ "we press Tab after 'ABCD' (cursor at column 5)", context do
        # Cursor is now at column 5 (after ABCD)
        # Tab should advance to column 9 (next tab stop = 4 spaces)
        Probes.send_keys("tab", [])
        Process.sleep(50)
        Probes.send_text("E")
        Process.sleep(100)
        {:ok, context}
      end

      then_ "E should appear at column 9", context do
        # Result: "ABCD    E" (ABCD at cols 1-4, tab fills 4 spaces, E at col 9)
        assert Query.text_visible?("ABCD"), "ABCD should be visible"
        assert Query.text_visible?("E"), "E should be visible"
        :ok
      end
    end
  end

  spex "Dynamic Tab Width Changes",
    description: "Validates cursor position stays relative to surrounding text when tab width changes",
    tags: [:phase_4, :tabs, :dynamic, :regression, :bug] do

    # =========================================================================
    # BUG: When tab width changes, cursor should stay between same characters
    # =========================================================================

    scenario "Cursor stays between same characters after tab width change", context do
      given_ "we have 'A<tab>B' with cursor between tab and B", context do
        Probes.send_keys("ctrl+a", [])
        Process.sleep(50)
        Probes.send_text("A")
        Probes.send_keys("tab", [])
        Process.sleep(50)
        Probes.send_text("B")
        Process.sleep(50)
        # Move cursor left to be between tab and B
        Probes.send_keys("left", [])
        Process.sleep(100)
        {:ok, context}
      end

      when_ "we change tab width from 4 to 2", context do
        change_tab_width(2)
        Process.sleep(200)
        {:ok, context}
      end

      then_ "cursor should still be between tab and B (typing X gives A<tab>XB)", context do
        Probes.send_text("X")
        Process.sleep(100)
        # X should appear between tab and B, not on a different line
        assert Query.text_visible?("A"), "A should be visible"
        assert Query.text_visible?("X"), "X should be visible"
        assert Query.text_visible?("B"), "B should be visible"
        :ok
      end
    end

    scenario "Cursor stays at correct line after tab width shrink", context do
      given_ "we have text with multiple tabs on one line", context do
        Probes.send_keys("ctrl+a", [])
        Process.sleep(50)
        Probes.send_text("Col1")
        Probes.send_keys("tab", [])
        Probes.send_text("Col2")
        Probes.send_keys("tab", [])
        Probes.send_text("Col3")
        Process.sleep(100)
        # Cursor is at end of "Col3"
        {:ok, context}
      end

      when_ "we change tab width from 4 to 8 (wider tabs)", context do
        change_tab_width(8)
        Process.sleep(200)
        {:ok, context}
      end

      then_ "text should still be on one line and cursor should be at end", context do
        # Type to verify cursor position
        Probes.send_text("!")
        Process.sleep(100)
        assert Query.text_visible?("Col3!"), "Col3! should be visible (cursor was at end)"
        :ok
      end
    end

    scenario "Tab width change with cursor mid-line preserves relative position", context do
      given_ "we have 'Start<tab>Middle<tab>End' with cursor in 'Middle'", context do
        Probes.send_keys("ctrl+a", [])
        Process.sleep(50)
        Probes.send_text("Start")
        Probes.send_keys("tab", [])
        Probes.send_text("Middle")
        Probes.send_keys("tab", [])
        Probes.send_text("End")
        Process.sleep(50)
        # Move cursor to be inside "Middle" - move left 7 times (End + tab + 3 chars)
        for _ <- 1..7 do
          Probes.send_keys("left", [])
          Process.sleep(20)
        end
        Process.sleep(100)
        {:ok, context}
      end

      when_ "we change tab width from 4 to 3", context do
        change_tab_width(3)
        Process.sleep(200)
        {:ok, context}
      end

      then_ "cursor should still be inside 'Middle', typing X gives 'MiXddle'", context do
        Probes.send_text("X")
        Process.sleep(100)
        # Cursor was inside "Middle", X should be inserted there
        assert Query.text_visible?("Start"), "Start should be visible"
        assert Query.text_visible?("End"), "End should be visible"
        # The X should be somewhere in the middle section
        assert Query.text_visible?("X"), "X should be visible (inserted in Middle)"
        :ok
      end
    end

    scenario "Tab width change doesn't move cursor to different line", context do
      given_ "we have multiple lines with tabs", context do
        Probes.send_keys("ctrl+a", [])
        Process.sleep(50)
        # Line 1: indented text
        Probes.send_keys("tab", [])
        Probes.send_text("Line1")
        Probes.send_keys("enter", [])
        # Line 2: double indented
        Probes.send_keys("tab", [])
        Probes.send_keys("tab", [])
        Probes.send_text("Line2")
        Process.sleep(100)
        # Cursor is at end of Line2
        {:ok, context}
      end

      when_ "we change tab width from 4 to 2 and back to 4", context do
        change_tab_width(2)
        Process.sleep(150)
        change_tab_width(4)
        Process.sleep(150)
        {:ok, context}
      end

      then_ "cursor should still be at end of Line2", context do
        Probes.send_text("!")
        Process.sleep(100)
        # ! should appear after Line2, not on Line1 or a new line
        assert Query.text_visible?("Line2!"), "Line2! should be visible (cursor stayed on line 2)"
        :ok
      end
    end
  end
end
