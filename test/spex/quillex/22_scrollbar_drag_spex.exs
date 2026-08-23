defmodule Quillex.ScrollbarDragSpex do
  @moduledoc """
  Phase 22: Scroll interactions (extracted from the 07 monolith — Roadmap 3.5)

  Two scenarios that were flaky inside `07_integration_v1_spex.exs`, each for
  a structural reason this file fixes:

  1. **Scrollbar-thumb drag** hardcoded window-size-dependent coordinates
     (scrollbar x = 1990), but the WM may grant a smaller window than the
     requested 2000x1200 and the layout reflows to match — AND
     `Scenic.ViewPort.info/1` still reports the configured size, so it can't
     be used either. Coordinates here come from the buffer pane's *semantic
     frame* (its actual rendered bounds).

  2. **Shift+Scroll horizontal** depends on the Shift keypress reaching the
     TextField, which is gated on keyboard focus — after ~20 stateful
     monolith scenarios, focus could be anywhere. Here the setup clicks
     into the pane first and asserts the typed text landed.
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

  spex "Dragging the vertical scrollbar thumb scrolls the buffer",
    description: "Grab the thumb near the top, drag down, verify the visible text changed",
    tags: [:phase_22, :scroll, :mouse] do
    scenario "Thumb drag scrolls a large file" do
      given_ "Spinoza is open, focused, showing its first line", context do
        Probes.send_keys("escape", [])
        Process.sleep(200)

        :ok =
          Quillex.TestHelpers.FileOpener.open_file(Path.expand("biblio/spinozas_ethics_p1.txt"))

        Process.sleep(800)

        # Click into the pane to guarantee focus
        frame = SemanticHelpers.get_buffer_frame()
        assert frame != nil, "buffer pane semantic frame not available"
        Probes.click(frame.x + trunc(frame.width * 0.3), frame.y + trunc(frame.height * 0.3))
        Process.sleep(200)

        # NOTE: must use ScriptInspector (actually-DRAWN text), not
        # Query.text_visible? — the semantic table contains the whole
        # document regardless of scroll, so it cannot detect scrolling.
        assert Quillex.TestHelpers.ScriptInspector.rendered_text_contains?("CONCERNING GOD"),
               "expected the top of the Ethics to be on screen after opening it"

        {:ok, Map.put(context, :frame, frame)}
      end

      when_ "the thumb is grabbed near the top and dragged down", context do
        {_x0, initial_y} = SemanticHelpers.get_scroll_offset()

        # All coordinates derived from the pane's ACTUAL rendered frame.
        # The vertical scrollbar hugs the pane's right edge (~10px wide);
        # with a large file the thumb is short, at pane-local y 0-28.
        frame = context.frame
        x = frame.x + frame.width - 10
        grab_y = frame.y + 15
        drop_y = frame.y + trunc(frame.height * 0.6)

        Probes.mouse_down(x, grab_y)
        Process.sleep(100)
        Probes.send_mouse_move(x, frame.y + trunc(frame.height * 0.3))
        Process.sleep(50)
        Probes.send_mouse_move(x, drop_y)
        Process.sleep(100)
        Probes.mouse_up(x, drop_y)
        Process.sleep(400)

        {:ok, Map.put(context, :initial_y, initial_y)}
      end

      then_ "the vertical scroll offset has moved", context do
        # NOTE: asserted via the semantic scroll offset. Text-presence
        # assertions CANNOT detect scrolling: the semantic table holds the
        # whole document, and ScriptInspector reads script-table runs
        # without applying group transforms/scissor, so drawn-but-offscreen
        # text still "exists". Transform-aware ScriptInspector is a
        # Roadmap 4b (render invariants) prerequisite.
        {_x, final_y} = SemanticHelpers.get_scroll_offset()

        assert final_y > context.initial_y,
               "vertical scroll offset did not increase (#{context.initial_y} -> #{final_y}) — thumb drag had no effect"

        Quillex.TestHelpers.Invariants.assert_invariants!()
        {:ok, context}
      end
    end
  end

  spex "Shift+Scroll scrolls horizontally",
    description: "With a long unwrapped line, holding Shift converts wheel scroll to horizontal",
    tags: [:phase_22, :scroll, :horizontal] do
    scenario "Shift+wheel moves the horizontal offset" do
      given_ "a fresh focused buffer with one very long line", context do
        Probes.send_keys("escape", [])
        Process.sleep(200)

        # Fresh buffer via File → New (UI-based)
        Probes.click_element("icon_menu_file")
        Process.sleep(200)
        Probes.click_element("icon_menu_file_new")
        Process.sleep(500)

        # Guarantee pane focus, then type — and PROVE the typing landed
        frame = SemanticHelpers.get_buffer_frame()
        assert frame != nil, "buffer pane semantic frame not available"
        cx = frame.x + trunc(frame.width * 0.3)
        cy = frame.y + trunc(frame.height * 0.3)
        Probes.click(cx, cy)
        Process.sleep(200)

        Probes.send_text("marker_start_" <> String.duplicate("x", 200))
        Process.sleep(300)

        assert Query.text_visible?("marker_start_"),
               "typed text is not on screen — pane was not focused"

        Probes.send_keys("home", [])
        Process.sleep(100)

        {initial_x, _y} = SemanticHelpers.get_scroll_offset()
        {:ok, context |> Map.put(:initial_x, initial_x) |> Map.put(:pane_point, {cx, cy})}
      end

      when_ "Shift is held while scrolling the wheel over the pane", context do
        {cx, cy} = context.pane_point
        Probes.key_press("shift")
        Process.sleep(50)

        for _ <- 1..5 do
          Probes.send_scroll(0, -1, cx, cy)
          Process.sleep(30)
        end

        Process.sleep(100)
        Probes.key_release("shift")
        Process.sleep(50)
        {:ok, context}
      end

      then_ "the horizontal scroll offset has changed", context do
        {final_x, _y} = SemanticHelpers.get_scroll_offset()

        assert final_x != context.initial_x,
               "horizontal scroll offset did not change (#{context.initial_x} -> #{final_x})"

        Quillex.TestHelpers.Invariants.assert_invariants!()
        {:ok, context}
      end
    end
  end
end
