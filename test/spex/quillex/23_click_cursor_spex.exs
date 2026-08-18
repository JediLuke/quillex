defmodule Quillex.ClickCursorSpex do
  @moduledoc """
  Phase 23: Mouse click positions the cursor (extracted from the 07 monolith —
  Roadmap 3.5 / QA known-failure #3)

  A click in the text area moves the cursor to the clicked line and column.
  The coordinate model (verified empirically, 2026-07-31): input coords are
  transformed into the pane's local space by Scenic; the pane sits below the
  35px top bar; line_height = font size = 24; visual rows carry the +4
  cursor-block offset. So visual line n occupies global y
  [35 + (n-1)*24 + 4, 35 + n*24 + 4).

  Extracted because the monolith version ran after ~20 stateful scenarios
  that could leave keyboard focus elsewhere — its typed setup text then
  silently went nowhere. Here the setup creates a fresh buffer, clicks into
  the pane, and asserts the typed text is actually on screen before testing.
  """
  use SexySpex

  alias ScenicMcp.Probes
  alias ScenicMcp.Query
  alias Quillex.TestHelpers.SemanticHelpers

  setup_all do
    case Application.ensure_all_started(:quillex) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :quillex}} -> :ok
      {:error, reason} -> raise "Failed to start Quillex: #{inspect(reason)}"
    end

    Process.sleep(2000)

    # Start from a known-clean editor rather than inheriting whatever
    # the previous spex file left behind (buffers, open nav, scroll).
    Quillex.TestHelpers.AppReset.reset!()

    :ok
  end

  # Poll until the semantic cursor reaches the expected line (or timeout);
  # returns the final cursor either way so the assertions report reality.
  defp await_cursor_line(expected_line, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_await_cursor(expected_line, deadline)
  end

  defp do_await_cursor(expected_line, deadline) do
    cursor = our_buffer_cursor()

    case cursor do
      {^expected_line, _col} ->
        cursor

      _ ->
        if System.monotonic_time(:millisecond) >= deadline do
          cursor
        else
          Process.sleep(100)
          do_await_cursor(expected_line, deadline)
        end
    end
  end

  # Read the cursor from the semantic entry that provably belongs to OUR
  # buffer (anchored by its known content) — eliminates any residual
  # wrong-entry reads from the generic "latest text_buffer" heuristic.
  defp our_buffer_cursor do
    with {:ok, vp} <- Scenic.ViewPort.info(:main_viewport),
         {:ok, entries} <- SemanticHelpers.find_by_type_all_graphs(vp, :text_buffer),
         # Prefer the entry that is BOTH the main editor pane and holds our
         # known text; fall back to content-match, then the generic helper.
         %{} = entry <-
           Enum.find(entries, fn e ->
             get_in(e, [:semantic, :field_id]) == :buffer_pane and
               String.contains?(e.content || "", "Line two here")
           end) ||
             Enum.find(entries, fn e -> String.contains?(e.content || "", "Line two here") end) do
      get_in(entry, [:semantic, :cursor_position])
    else
      _ -> SemanticHelpers.get_cursor_position()
    end
  end

  spex "Mouse click positions the cursor at the clicked line",
    description: "Click on line 2 of a three-line buffer and verify the cursor lands there",
    tags: [:phase_23, :mouse, :cursor] do
    scenario "Click on line 2 moves the cursor to line 2" do
      given_ "a fresh buffer with three known lines, focus verified", context do
        Probes.send_keys("escape", [])
        Process.sleep(200)

        # Fresh buffer via File → New (UI-based, boundary-compliant)
        Probes.click_element("icon_menu_file")
        Process.sleep(200)
        Probes.click_element("icon_menu_file_new")
        Process.sleep(500)

        # Guarantee pane focus with a click well inside the text area
        Probes.click(400, 300)
        Process.sleep(200)

        Probes.send_text("Line one here")
        Probes.send_keys("enter", [])
        Probes.send_text("Line two here")
        Probes.send_keys("enter", [])
        Probes.send_text("Line three here")
        Process.sleep(300)

        # Prove the setup landed: the text must actually be on screen
        assert Query.text_visible?("Line two here"),
               "setup text did not reach the buffer — pane was not focused"

        initial = SemanticHelpers.get_cursor_position()
        {:ok, Map.put(context, :initial_cursor, initial)}
      end

      when_ "we click in the middle of line 2", context do
        # Line 2's visual row: global y [63, 87) — click its centre.
        # x=120 lands a few characters into the text (gutter 48 + padding 10).
        #
        # Derive the click point from the pane's ACTUAL frame rather than
        # assuming pin y=35: a status bar or search bar left open by an
        # earlier spex shifts the pane's origin, and a hardcoded y then
        # lands a line or two off. Visual row n spans
        # frame.y + 4 + (n-1)*24 .. +24, so line 2's centre is frame.y + 40.
        # Derive BOTH coordinates from the pane's live frame. Hardcoding x
        # was the long-standing flake in this spex: when an earlier file
        # leaves the file navigator open the pane starts at x=250, so a
        # click at x=120 lands in the SIDEBAR and never reaches the editor —
        # the cursor simply stays where typing left it (line 3).
        {click_x, click_y} =
          case SemanticHelpers.get_buffer_frame() do
            %{x: x, y: y} -> {x + 120, y + 40}
            _ -> {120, 75}
          end

        Probes.click(click_x, click_y)
        Process.sleep(400)

        {:ok, context}
      end

      then_ "the cursor is on line 2 at a sensible column", context do
        # Convergence-based read: the click pipeline (input → PaneStore →
        # buffer → publish → TextField sync → semantic) was measured taking
        # up to ~300ms under polluted suite state — a fixed sleep races it.
        # (That latency itself is a perf lead — see the roadmap's dispatch-
        # latency telemetry note under the performance workstream.)
        cursor = await_cursor_line(2, 2_000)

        assert cursor != nil, "no cursor position available from the semantic layer"
        {line, col} = cursor

        assert line == 2,
               "cursor should be on line 2 after clicking its row centre, got line #{line}"

        assert col >= 1 and col <= 10,
               "cursor column should be within the first 10 columns for a click at x=120, got #{col}"

        Quillex.TestHelpers.Invariants.assert_invariants!()
        {:ok, context}
      end
    end
  end

  spex "Clicking past the text still moves the cursor",
    description: "Empty space in a document belongs to the document, not to nothing",
    tags: [:phase_23, :mouse, :cursor] do
    # This had no coverage, and so it broke: TextField discarded any click
    # landing past the end of the clicked line's text, on the theory that it
    # must have been meant for something drawn above the pane. A click to the
    # right of a short line did nothing, a click below the last line did
    # nothing, and — because focus follows a click — the editor went dead to
    # the keyboard until you happened to hit a glyph.
    scenario "Clicking to the right of a line puts the cursor at end of line" do
      given_ "a buffer whose lines are short", context do
        new_buffer_with(["short", "a somewhat longer line", "end"])
        {:ok, context}
      end

      when_ "we click far to the right of line 1", context do
        %{x: fx, y: fy, width: fw} = SemanticHelpers.get_buffer_frame()
        Probes.click(fx + trunc(fw * 0.7), fy + 16)
        Process.sleep(400)
        {:ok, context}
      end

      then_ "the cursor sits at the end of line 1, not somewhere else", context do
        assert {1, col} = our_buffer_cursor(),
               "clicking right of line 1 should stay on line 1, got #{inspect(our_buffer_cursor())}"

        assert col == String.length("short") + 1,
               "clicking past the end of a line means end of line; got column #{col}"

        {:ok, context}
      end

      then_ "a single click leaves no selection behind", context do
        {:ok, snapshot} = Quillex.Buffer.fetch(active_buf())

        assert snapshot.selection == nil,
               "a single click should not select anything, got #{inspect(snapshot.selection)}"

        {:ok, context}
      end

      then_ "and the editor has the keyboard, so typing lands there", context do
        Probes.send_text("!")
        Process.sleep(300)

        assert {:ok, snapshot} = Quillex.Buffer.fetch(active_buf()),
               "no active buffer"

        assert Enum.at(snapshot.lines, 0) == "short!",
               "typing after the click should land at end of line 1, got #{inspect(snapshot.lines)}"

        {:ok, context}
      end
    end

    scenario "Clicking below the last line puts the cursor on the last line" do
      given_ "a short buffer with a lot of empty space beneath it", context do
        new_buffer_with(["alpha", "beta"])
        {:ok, context}
      end

      when_ "we click well below the last line", context do
        %{x: fx, y: fy, width: fw, height: fh} = SemanticHelpers.get_buffer_frame()
        Probes.click(fx + trunc(fw * 0.4), fy + trunc(fh * 0.7))
        Process.sleep(400)
        {:ok, context}
      end

      then_ "the cursor lands on the last line", context do
        assert {2, _col} = our_buffer_cursor(),
               "clicking below the text should land on the last line, got #{inspect(our_buffer_cursor())}"

        {:ok, context}
      end

      then_ "and the editor has the keyboard", context do
        Probes.send_text("!")
        Process.sleep(300)

        {:ok, snapshot} = Quillex.Buffer.fetch(active_buf())

        assert Enum.join(snapshot.lines, "\n") =~ "!",
               "typing after clicking empty space should reach the document, got #{inspect(snapshot.lines)}"

        {:ok, context}
      end
    end
  end

  defp active_buf do
    :sys.get_state(Process.whereis(QuillEx.RootScene)).assigns.state.active_buf
  end

  # A fresh, focused buffer holding exactly these lines.
  defp new_buffer_with(lines) do
    {:ok, buf} = Quillex.Buffer.new(%{name: "click-target.txt", data: lines})
    :ok = Quillex.Buffer.activate(buf)
    Process.sleep(500)

    # Focus by clicking on the LAST line's text — never the line under test,
    # and never at a position that could resolve to the same cursor cell.
    # Two clicks that land on the same {line, col} inside the double-click
    # window are a double click, and the editor is right to select the word:
    # an earlier version of this helper clicked line 1, the scenario clicked
    # line 1 again 300ms later, and the resulting word selection looked like a
    # bug in clicking rather than a bug in the setup.
    %{x: fx, y: fy} = SemanticHelpers.get_buffer_frame()
    Probes.click(fx + 90, fy + 16 + (length(lines) - 1) * 24)
    Process.sleep(600)

    buf
  end
end
