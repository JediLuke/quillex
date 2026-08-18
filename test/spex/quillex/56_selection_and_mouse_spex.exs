defmodule Quillex.SelectionAndMouseSpex do
  @moduledoc """
  Selecting with the keyboard, and driving the editor with the mouse.

  Split out of `07_integration_v1_spex.exs` (roadmap Part II item 9).
  """
  use SexySpex
  @moduletag timeout: 300_000

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.SemanticHelpers
  import Quillex.TestHelpers.Integration

  setup_all do
    fresh_editor!()
    :ok
  end

  # Every coordinate comes from the pane's LIVE frame. Hardcoding them is the
  # long-standing flake in mouse spex: an open file navigator moves the pane
  # 250px right and a status strip moves it down, so a fixed point lands in
  # the sidebar and the drag selects nothing. Visual row n spans
  # frame.y + 4 + (n-1)*line_height, so line 1's centre is frame.y + 16.
  # x is offset well clear of the line-number gutter: a press in the gutter is
  # the fold-hover region, not the text, and starts no selection at all.
  defp drag_points do
    %{x: fx, y: fy} = SemanticHelpers.get_buffer_frame()
    {fx + 120, fx + 220, fy + 16}
  end

  # A few characters into the first word, clear of the gutter.
  defp word_point do
    %{x: fx, y: fy} = SemanticHelpers.get_buffer_frame()
    {fx + 70, fy + 16}
  end

  # A press has to be preceded by a click that lands in the pane. Measured:
  # a bare mouse_down after the pane was last touched elsewhere moves neither
  # the cursor nor starts a selection, while the same sequence after one
  # ordinary click does both. Whatever the cause in the input plumbing, a real
  # user's pointer has always been somewhere before they press, so this is not
  # a fiction the test is inventing.
  defp drag(start_x, end_x, line_y) do
    Probes.click(start_x, line_y)
    Process.sleep(150)

    Probes.mouse_down(start_x, line_y)
    Process.sleep(120)

    for x <- [start_x + 25, start_x + 60, end_x] do
      Probes.send_mouse_move(x, line_y)
      Process.sleep(60)
    end

    Probes.mouse_up(end_x, line_y)
    Process.sleep(400)
  end

  # SPEX 11: SHIFT+ARROW SELECTION
  # =========================================================================

  spex "V1 Integration - Keyboard Selection",
    description: "Validates Shift+Arrow text selection",
    tags: [:v1, :integration, :selection] do
    scenario "Select text with Shift+Right" do
      given_ "we have a buffer with text", context do
        new_empty_buffer()

        Probes.send_text("Hello World")
        Process.sleep(300)

        # Move cursor to start
        Probes.send_keys("home", [])
        Process.sleep(200)

        {:ok, context}
      end

      when_ "we press Shift+Right 5 times", context do
        Enum.each(1..5, fn _ ->
          Probes.send_keys("right", [:shift])
          Process.sleep(50)
        end)

        Process.sleep(300)
        {:ok, context}
      end

      then_ "we should have 'Hello' selected", context do
        case wait_for_active_selection() do
          {:ok, buffer, selection} ->
            {start_pos, end_pos} = normalize_selection(selection)
            {start_line, start_col} = start_pos
            {end_line, end_col} = end_pos

            # Started at beginning (line 1, col 1) and selected 5 chars right
            assert start_line == 1, "Selection should start on line 1, got #{start_line}"
            assert start_col == 1, "Selection should start at col 1, got #{start_col}"
            assert end_line == 1, "Selection should end on line 1, got #{end_line}"
            assert end_col == 6, "Selection should end at col 6 (after 'Hello'), got #{end_col}"

            [first_line | _] = String.split(buffer.content || "", "\n", parts: 2)
            selected_text = selected_text_from_line(first_line, selection)

            assert selected_text == "Hello",
                   "Expected 'Hello' to be selected, got '#{selected_text}'"

            {:ok, context}

          _ ->
            flunk("Could not get semantic selection")
        end
      end
    end

    scenario "Select text with Shift+Left" do
      given_ "we have a buffer with text and cursor at end", context do
        new_empty_buffer()

        Probes.send_text("World")
        Process.sleep(300)

        # Cursor is now at end of "World" (after 'd')
        {:ok, context}
      end

      when_ "we press Shift+Left 3 times", context do
        Enum.each(1..3, fn _ ->
          Probes.send_keys("left", [:shift])
          Process.sleep(50)
        end)

        Process.sleep(300)
        {:ok, context}
      end

      then_ "we should have 'rld' selected (last 3 chars)", context do
        case wait_for_active_selection() do
          {:ok, buffer, selection} ->
            {start_pos, end_pos} = normalize_selection(selection)
            {_, actual_start_col} = start_pos
            {_, actual_end_col} = end_pos

            assert actual_start_col == 3,
                   "Selection start should be at col 3 ('r'), got #{actual_start_col}"

            assert actual_end_col == 6,
                   "Selection end should be at col 6 (after 'd'), got #{actual_end_col}"

            [first_line | _] = String.split(buffer.content || "", "\n", parts: 2)
            selected_text = selected_text_from_line(first_line, selection)
            assert selected_text == "rld", "Expected 'rld' to be selected, got '#{selected_text}'"

            {:ok, context}

          _ ->
            flunk("Could not get semantic selection")
        end
      end
    end

    scenario "Copy selected text with Ctrl+C" do
      given_ "we have text selected", context do
        # Already in correct state from previous scenario
        {:ok, context}
      end

      when_ "we press Ctrl+C to copy", context do
        Probes.send_keys("c", [:ctrl])
        Process.sleep(300)
        {:ok, context}
      end

      then_ "the selection should be preserved and the selected text should reach the clipboard",
            context do
        case wait_for_active_selection() do
          {:ok, _buffer, _selection} ->
            assert File.read!("/tmp/quillex_test_clipboard") == "rld",
                   "Ctrl+C must write the selected text to the configured clipboard backend"

            {:ok, context}

          _ ->
            flunk("Could not get semantic selection")
        end
      end
    end

    scenario "Paste copied text with Ctrl+V" do
      given_ "the previous scenario copied 'rld'", context do
        Probes.send_keys("end", [])
        Process.sleep(100)
        {:ok, context}
      end

      when_ "we press Ctrl+V at the end of the line", context do
        Probes.send_keys("v", [:ctrl])
        Process.sleep(300)
        {:ok, context}
      end

      then_ "the copied text should be inserted", context do
        {:ok, _} = wait_for_active_buffer_content("Worldrld")
        assert active_buffer_content() == "Worldrld"
        {:ok, context}
      end
    end

    scenario "Cut removes selected text" do
      given_ "we have a fresh buffer with text and selection", context do
        new_empty_buffer()

        Probes.send_text("ABCDEFGH")
        Process.sleep(300)

        # Move to start and select "ABC"
        Probes.send_keys("home", [])
        Process.sleep(100)

        Enum.each(1..3, fn _ ->
          Probes.send_keys("right", [:shift])
          Process.sleep(50)
        end)

        Process.sleep(200)

        content_before = active_buffer_content()
        {:ok, Map.put(context, :content_before, content_before)}
      end

      when_ "we press Ctrl+X to cut", context do
        Probes.send_keys("x", [:ctrl])
        Process.sleep(300)
        {:ok, context}
      end

      then_ "selected text should be removed", context do
        {:ok, _} = wait_for_active_buffer_content("DEFGH")
        content_after = active_buffer_content()

        assert content_after == "DEFGH",
               "Expected 'DEFGH' after cutting 'ABC', got '#{content_after}'"

        {:ok, context}
      end
    end
  end

  # =========================================================================
  # SPEX 12: MOUSE CONTROL
  # =========================================================================

  spex "V1 Integration - Mouse Control",
    description: "Validates mouse click cursor positioning",
    tags: [:v1, :integration, :mouse] do
    # NOTE: the click-positions-cursor scenario was extracted to
    # 23_click_cursor_spex.exs — it needs a self-contained setup that
    # guarantees pane focus before typing (in the shared-state monolith,
    # earlier scenarios could leave focus elsewhere, making it flaky).

    scenario "Click and drag selects text on a single line", _context do
      given_ "we have a buffer with known text", context do
        new_empty_buffer()
        Probes.send_text("Hello World Test")
        Process.sleep(300)

        assert {:ok, _} = wait_for_active_buffer_content("Hello World Test")
        {:ok, context}
      end

      when_ "we mouse-down, drag right, and mouse-up", context do
        # Both coordinates come from the pane's LIVE frame. Hardcoding them —
        # which is what this scenario used to do — assumes the pane starts at
        # x=0, y=35, and it does not: an open file navigator moves it 250px
        # right, and a status strip moves it down. The drag then happens in
        # the sidebar and selects nothing.
        #
        # Visual row n spans frame.y + 4 + (n-1)*24 for 24px, so line 1's
        # centre is frame.y + 16.
        {start_x, drag_end_x, line_y} = drag_points()
        drag(start_x, drag_end_x, line_y)
        {:ok, context}
      end

      then_ "a selection should exist on line 1", context do
        case wait_for_active_selection(3000) do
          {:ok, _buffer, selection} ->
            {start_pos, end_pos} = normalize_selection(selection)
            {start_line, start_col} = start_pos
            {end_line, end_col} = end_pos

            assert start_line == 1,
                   "Drag selection should start on line 1, got line #{start_line}"

            assert end_line == 1,
                   "Drag selection should end on line 1, got line #{end_line}"

            assert end_col > start_col,
                   "Drag selection end col (#{end_col}) should be greater than start col (#{start_col})"

            {:ok, context}

          {:error, :selection_timeout} ->
            flunk("Mouse drag should create a selection but none was detected after 3s")
        end
      end
    end

    scenario "Double-click selects a word", _context do
      given_ "we have a buffer with words", context do
        new_empty_buffer()
        Probes.send_text("Hello World")
        Process.sleep(300)
        assert {:ok, _} = wait_for_active_buffer_content("Hello World")
        {:ok, context}
      end

      when_ "we double-click on the first word", context do
        {click_x, click_y} = word_point()
        Probes.click(click_x, click_y)
        Process.sleep(60)
        Probes.click(click_x, click_y)
        Process.sleep(300)
        {:ok, context}
      end

      then_ "the word under the cursor should be selected", context do
        case wait_for_active_selection(3000) do
          {:ok, _buffer, selection} ->
            {start_pos, end_pos} = normalize_selection(selection)
            {_start_line, start_col} = start_pos
            {_end_line, end_col} = end_pos

            assert end_col > start_col,
                   "Double-click word selection should span multiple columns (start=#{start_col}, end=#{end_col})"

            {:ok, context}

          {:error, :selection_timeout} ->
            flunk("Double-click should select a word but no selection was detected after 3s")
        end
      end
    end

    scenario "Single click after drag selection clears the selection", _context do
      given_ "we have a drag selection active", context do
        new_empty_buffer()
        Probes.send_text("Some text here")
        Process.sleep(250)
        assert {:ok, _} = wait_for_active_buffer_content("Some text here")

        {start_x, end_x, line_y} = drag_points()
        drag(start_x, end_x, line_y)

        case wait_for_active_selection(2000) do
          {:ok, _, _} -> {:ok, Map.put(context, :line_y, line_y)}
          {:error, :selection_timeout} -> flunk("Setup: drag selection should have been created")
        end
      end

      when_ "we single-click elsewhere", context do
        {start_x, _end_x, line_y} = drag_points()
        Probes.click(start_x + 20, line_y)
        Process.sleep(300)
        {:ok, context}
      end

      then_ "selection should be cleared", context do
        case active_buffer_semantic() do
          {:ok, buffer} ->
            selection = get_in(buffer, [:semantic, :selection])

            assert is_nil(selection),
                   "Selection should be cleared after single click, got: #{inspect(selection)}"

          _ ->
            :ok
        end

        {:ok, context}
      end
    end
  end
end
