defmodule Quillex.ViewportResizeSpex do
  @moduledoc """
  Phase 21: Viewport Resize / Reflow (Roadmap 1.0, Phase 2 regression coverage)

  Guards against the "internal app doesn't resize" bug from the 2026-07-31
  manual QA pass: the `:reshape` handler rebuilt the root frame, but
  `needs_buffer_pane_recreation?/2` didn't consider frame changes, so the
  render took the incremental branch and every child kept its old geometry.

  Fixed by adding `frame_changed` to the recreation predicate, which forces
  the full bottom-to-top rebuild with the new frames (cursor and scroll are
  preserved via the `_restore_*` state keys, same as the word-wrap toggle).

  Resize events are injected with `Quillex.TestHelpers.ViewportResizer` —
  the same `{:viewport, {:reshape, _}}` input the GLFW driver sends.
  """
  use SexySpex

  alias ScenicMcp.Probes
  alias ScenicMcp.Query
  alias Quillex.TestHelpers.ViewportResizer

  # The :test window boots at 2000x1200 (Quillex.App.window_size/0).
  @boot_size {2000, 1200}
  @shrunk_size {1400, 900}

  setup_all do
    case Application.ensure_all_started(:quillex) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :quillex}} -> :ok
      {:error, reason} -> raise "Failed to start Quillex: #{inspect(reason)}"
    end

    Process.sleep(2000)

    # Known LAYOUT to start from (overlays dismissed, file navigator
    # closed) without touching buffers — an open navigator shifts the
    # editor pane 250px right and makes fixed-x clicks miss it.
    Quillex.TestHelpers.AppReset.reset_layout!()
    :ok
  end

  spex "Reshape reflows the layout without losing editor state",
    description:
      "A viewport reshape rebuilds every pane at the new geometry while preserving text, cursor and focus",
    tags: [:phase_21, :resize, :reflow] do
    scenario "Content and editing survive a shrink" do
      given_ "text has been typed into the editor", context do
        Probes.send_keys("escape", [])
        Process.sleep(200)

        Probes.send_text("resize probe alpha")
        Process.sleep(400)
        assert Query.text_visible?("resize probe alpha"), "typed setup text never appeared"
        {:ok, context}
      end

      when_ "the viewport is reshaped smaller", context do
        {w, h} = @shrunk_size
        ViewportResizer.resize(w, h)
        Process.sleep(600)
        {:ok, context}
      end

      then_ "the text is still on screen and typing continues at the cursor", context do
        assert Query.text_visible?("resize probe alpha"),
               "buffer content vanished after reshape — pane not recreated with restore keys?"

        Probes.send_text(" beta")
        Process.sleep(300)

        assert Query.text_visible?("beta"),
               "typing after reshape failed — editor lost focus or cursor during recreation"

        Quillex.TestHelpers.Invariants.assert_invariants!()
        {:ok, context}
      end
    end

    scenario "The top bar is functional at the new size" do
      given_ "the viewport is at the shrunk size", context do
        {:ok, context}
      end

      when_ "the user opens the View menu", context do
        Probes.click_element("icon_menu_view")
        Process.sleep(300)
        {:ok, context}
      end

      then_ "the menu opens (icon menu was re-laid-out and re-registered)", context do
        assert Query.text_visible?("Line Numbers"),
               "View menu did not open after resize — icon menu not functional at new geometry"

        Probes.send_keys("escape", [])
        Process.sleep(200)
        Quillex.TestHelpers.Invariants.assert_invariants!()
        {:ok, context}
      end
    end

    scenario "Cleanup: restore the boot size" do
      given_ "the viewport is at the shrunk size", context do
        {:ok, context}
      end

      when_ "the viewport is reshaped back to the boot size", context do
        {w, h} = @boot_size
        ViewportResizer.resize(w, h)
        Process.sleep(600)
        {:ok, context}
      end

      then_ "the editor is intact for subsequent spex", context do
        assert Query.text_visible?("resize probe alpha")
        Quillex.TestHelpers.Invariants.assert_invariants!()
        {:ok, context}
      end
    end
  end
end
