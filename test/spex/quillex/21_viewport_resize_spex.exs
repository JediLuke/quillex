defmodule Quillex.ViewportResizeSpex do
  @moduledoc """
  Phase 21: Viewport Resize / Reflow (Roadmap 1.0, Phase 2 regression coverage)

  Guards both resize correctness and the resize hot path. Reshapes are
  frame-coalesced and update live child processes in place; a window-manager
  event burst must converge to its latest size without process churn or a
  backlog of obsolete full redraws.

  Resize events are injected with `Quillex.TestHelpers.ViewportResizer` —
  the same `{:viewport, {:reshape, _}}` input the GLFW driver sends.
  """
  use SexySpex

  alias ScenicMcp.Probes
  alias ScenicMcp.Query
  alias Quillex.TestHelpers.ViewportResizer
  alias Quillex.TestHelpers.Perf

  # The :test window boots at 2000x1200 (QuillEx.App.window_size/0).
  @boot_size {2000, 1200}
  @shrunk_size {1400, 900}

  defp child_pid(id) do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, child} = Scenic.Scene.child(root, id)
    if is_list(child), do: List.first(child), else: child
  end

  defp wait_for_size(size, attempts \\ 100)
  defp wait_for_size(_size, 0), do: flunk("resize did not converge")

  defp wait_for_size(size, attempts) do
    frame = :sys.get_state(Process.whereis(QuillEx.RootScene)).assigns.state.frame

    if frame.size.box == size do
      :ok
    else
      Process.sleep(20)
      wait_for_size(size, attempts - 1)
    end
  end

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

  spex "Resize bursts remain elastic and bounded",
    description:
      "Rapid reshape input coalesces to the latest dimensions while heavyweight components stay alive",
    tags: [:phase_21, :resize, :performance] do
    scenario "a drag-sized burst of reshape events", _context do
      given_ "the navigator is visible and component identities are recorded", context do
        Quillex.RadixCache.ViewStore.open_file_nav()
        Quillex.RadixCache.ViewStore.sync()
        Process.sleep(400)

        pids =
          Map.new([:buffer_pane, :file_nav, :tab_bar, :cursor_pos_label, :icon_menu], fn id ->
            {id, child_pid(id)}
          end)

        Perf.reset()
        {:ok, Map.put(context, :pids, pids)}
      end

      when_ "one hundred and twenty intermediate sizes arrive without pauses", context do
        sizes =
          for index <- 0..119 do
            {1200 + rem(index * 17, 600), 720 + rem(index * 11, 300)}
          end

        Enum.each(sizes, fn {width, height} -> ViewportResizer.resize(width, height) end)
        final_size = List.last(sizes)
        wait_for_size(final_size)
        Process.sleep(250)
        {:ok, Map.put(context, :final_size, final_size)}
      end

      then_ "only current frames render and the existing components remain responsive", context do
        assert :sys.get_state(Process.whereis(QuillEx.RootScene)).assigns.state.frame.size.box ==
                 context.final_size

        Enum.each(context.pids, fn {id, original_pid} ->
          assert child_pid(id) == original_pid, "#{id} was destroyed during viewport resize"
          assert Process.alive?(original_pid)
        end)

        resize_stats = Perf.stats().handler_stats[:viewport_resize]
        assert resize_stats.count <= 10, "120 inputs caused #{resize_stats.count} full reflows"
        assert resize_stats.max_ms < 100, "resize handler stalled for #{resize_stats.max_ms}ms"

        Probes.click(context.final_size |> elem(0) |> div(2), 300)
        Probes.send_text(" elastic")
        Process.sleep(200)
        assert Query.text_visible?("elastic")
        {:ok, context}
      end
    end
  end
end
