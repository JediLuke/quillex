defmodule Quillex.InputFocusRoutingSpex do
  @moduledoc """
  Phase 19: Input Focus Routing (Roadmap 1.0, Phase 1 regression coverage)

  Guards against the two double-delivery bugs found in the 2026-07-31 manual
  QA pass:

  1. With the file nav open, pressing Enter in the editor both inserted a
     newline AND activated the nav's focused item (opening a file / new
     buffer). Root cause: SideNav requested [:key] globally with no focus
     gate — fixed by gating all SideNav key handlers on component focus.

  2. Scrolling over the file nav also scrolled the text pane. Root cause:
     TextField processed :cursor_scroll regardless of pointer position —
     fixed by bound-checking scroll coordinates against the TextField frame.

  Both scenarios FAIL on the pre-fix code by construction: scenario 1 types
  after pressing Enter and asserts the earlier text is still on screen
  (a buffer switch would hide it); scenario 2 asserts the top-of-file text
  is still on screen after aggressive scrolling over the nav.
  """
  use SexySpex

  alias ScenicMcp.Probes
  alias ScenicMcp.Query

  # Test window is 2000x1200 (see QuillEx.App.window_size/0 for :test).
  # The file nav occupies the left 250px below the 35px top bar.
  @nav_point {125, 500}
  @buffer_point {900, 600}

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

  # Open the View menu, then click the file-nav toggle (same helper as spex 10).
  defp toggle_file_nav do
    Probes.click_element("icon_menu_view")
    Process.sleep(200)
    Probes.click_element("icon_menu_view_file_nav")
    Process.sleep(500)
  end

  # The file nav renders the project tree, which always contains "mix.exs".
  defp file_nav_visible?, do: Query.text_visible?("mix.exs")

  defp ensure_file_nav_visible do
    unless file_nav_visible?(), do: toggle_file_nav()
  end

  defp ensure_file_nav_hidden do
    if file_nav_visible?(), do: toggle_file_nav()
  end

  spex "Keyboard focus is exclusive between editor and file nav",
    description:
      "Enter (and other keys) typed into the editor must not activate items in the file nav sidebar",
    tags: [:phase_19, :focus, :input_routing] do
    scenario "Enter in the editor inserts a newline and nothing else" do
      given_ "the file nav is open and the editor has focus with text typed", context do
        Probes.send_keys("escape", [])
        Process.sleep(200)
        ensure_file_nav_visible()
        assert file_nav_visible?()

        # Click into the buffer area to give the editor focus
        {bx, by} = @buffer_point
        Probes.click(bx, by)
        Process.sleep(200)

        Probes.send_text("alpha")
        Process.sleep(300)
        assert Query.text_visible?("alpha")
        {:ok, context}
      end

      when_ "the user presses Down then Enter, then keeps typing", context do
        # Pre-fix, Down moved the nav's item focus and Enter activated it
        # (opening a file in a new buffer, hiding this buffer's content).
        Probes.send_keys("down", [])
        Process.sleep(150)
        Probes.send_keys("enter", [])
        Process.sleep(300)
        Probes.send_text("beta")
        Process.sleep(300)
        {:ok, context}
      end

      then_ "both texts are on screen — same buffer, newline honoured", context do
        assert Query.text_visible?("alpha"),
               "text typed before Enter vanished — Enter switched buffers (nav received the key)"

        assert Query.text_visible?("beta"),
               "text typed after Enter is not visible — focus was lost to the file nav"

        Quillex.TestHelpers.Invariants.assert_invariants!()
        {:ok, context}
      end
    end
  end

  spex "Scroll is positional between editor and file nav",
    description: "Scrolling with the pointer over the file nav must not scroll the text pane",
    tags: [:phase_19, :scroll, :input_routing] do
    scenario "Wheel events over the nav leave the editor viewport untouched" do
      given_ "a tall document is open with its first line visible, nav open", context do
        Probes.send_keys("escape", [])
        Process.sleep(200)

        :ok =
          Quillex.TestHelpers.FileOpener.open_file(
            Path.expand("biblio/spinozas_ethics_p1.txt")
          )

        Process.sleep(800)
        ensure_file_nav_visible()

        # ScriptInspector = actually-drawn text; the semantic table holds the
        # whole document regardless of scroll and cannot detect scrolling.
        assert Quillex.TestHelpers.ScriptInspector.rendered_text_contains?("CONCERNING GOD"),
               "expected the top of the Ethics to be on screen after opening it"

        {:ok, context}
      end

      when_ "the user scrolls aggressively with the pointer over the file nav", context do
        {nx, ny} = @nav_point

        for _ <- 1..10 do
          Probes.send_scroll(0, -5, nx, ny)
          Process.sleep(50)
        end

        Process.sleep(300)
        {:ok, context}
      end

      then_ "the editor still shows the first line of the file", context do
        assert Quillex.TestHelpers.ScriptInspector.rendered_text_contains?("CONCERNING GOD"),
               "the text pane scrolled even though the pointer was over the file nav"

        Quillex.TestHelpers.Invariants.assert_invariants!()
        {:ok, context}
      end
    end

    scenario "Cleanup: close the file nav for subsequent spex" do
      given_ "the file nav is open", context do
        {:ok, context}
      end

      when_ "we toggle it off", context do
        ensure_file_nav_hidden()
        {:ok, context}
      end

      then_ "the project tree is no longer rendered", context do
        refute file_nav_visible?()
        Quillex.TestHelpers.Invariants.assert_invariants!()
        {:ok, context}
      end
    end
  end
end
