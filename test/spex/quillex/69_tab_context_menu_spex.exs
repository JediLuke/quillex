defmodule Quillex.TabContextMenuSpex do
  @moduledoc """
  Right-click a tab → bulk close, driven through the real pointer.

  The popup is scene-owned primitives that RootScene draws and hit-tests
  itself, so almost nothing about it can be checked from a unit test: whether
  a right-click reaches the root scene at all, whether the popup takes the
  keyboard away from the document, whether a chosen row closes the right
  tabs, and whether the batch's single "Unsaved Changes" prompt does what it
  says. Those are the claims here. The pure decisions underneath (which tabs
  each action targets, which of those are dirty, which row a click is on)
  are pinned in `test/gui/scenes/tab_context_menu_test.exs`.
  """
  use SexySpex
  @moduletag timeout: 300_000

  alias ScenicMcp.Probes
  alias ScenicMcp.Query
  alias Quillex.TestHelpers.SemanticProbe
  alias Quillex.TestHelpers.Integration

  # Row geometry, mirrored from RootScene's @tab_ctx_* attributes. A drift
  # here shows up as a click landing on the wrong row, which is exactly the
  # failure this file exists to catch, so it is deliberately stated rather
  # than read back out of the scene.
  @row_height 28
  @pad 6

  setup_all do
    case Application.ensure_all_started(:quillex) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :quillex}} -> :ok
      {:error, reason} -> raise "Failed to start Quillex: #{inspect(reason)}"
    end

    Process.sleep(1_500)
    Quillex.TestHelpers.AppReset.reset!()
    Process.sleep(400)
    :ok
  end

  # ── driving the pointer ────────────────────────────────────────────────────

  # Probes has no right-click wrapper; the driver-level tool does, and it is
  # the same path Probes.click/2 takes.
  defp right_click(x, y) do
    {:ok, _} =
      ScenicMcp.Tools.handle_mouse_click(%{"x" => x, "y" => y, "button" => "right"})

    Process.sleep(350)
    :ok
  end

  defp tab_centre(%{uuid: uuid}) do
    %{entry: %{screen_bounds: b}} = SemanticProbe.dump("tab_bar_#{uuid}")
    {b.left + b.width / 2, b.top + b.height / 2}
  end

  defp right_click_tab(buf_ref) do
    {x, y} = tab_centre(buf_ref)
    right_click(x, y)
  end

  # The popup is drawn at the press point (clamped to the window), so the row
  # to click is derived from where RootScene actually put it.
  defp click_menu_row(index) do
    %{pos: {x, y}} = root_state().tab_context_menu
    Probes.click(x + 40, y + @pad + index * @row_height + div(@row_height, 2))
    Process.sleep(500)
    :ok
  end

  # ── observing ──────────────────────────────────────────────────────────────

  defp root_state, do: :sys.get_state(Process.whereis(Quillex.RootScene)).assigns.state

  defp menu_open?, do: Query.text_visible?("Close Tabs to the Right")

  defp buffer_names, do: Enum.map(Quillex.Buffer.list(), & &1.name)

  defp active_name do
    case Quillex.Buffer.active_buf() do
      nil -> nil
      ref -> ref.name
    end
  end

  defp active_lines do
    {:ok, snapshot} = Quillex.Buffer.fetch(Quillex.Buffer.active_buf())
    snapshot.lines
  end

  # ── fixtures ───────────────────────────────────────────────────────────────

  # Exactly these tabs, in this left-to-right order, and nothing else.
  #
  # AppReset leaves the editor holding one empty "untitled" buffer — the
  # editor always shows one — so the reset alone is not a blank strip. The
  # leftover is closed AFTER the fixtures exist, because BufferManager
  # declines to close the last buffer.
  defp only_tabs(names) do
    Quillex.TestHelpers.AppReset.reset!()
    Process.sleep(300)
    leftovers = Quillex.Buffer.list()

    refs =
      Enum.map(names, fn name ->
        {:ok, ref} = Quillex.Buffer.new(%{name: name, data: [name]})
        Process.sleep(150)
        ref
      end)

    Enum.each(leftovers, &Quillex.Buffer.close(&1, :discard))
    Process.sleep(400)

    assert Enum.map(Quillex.Buffer.list(), & &1.name) == names,
           "fixture did not produce the tab strip it asked for"

    refs
  end

  defp four_tabs, do: only_tabs(~w(ctx-a.txt ctx-b.txt ctx-c.txt ctx-d.txt))

  defp dismiss_everything do
    Probes.send_keys("escape", [])
    Process.sleep(250)
    Probes.send_keys("escape", [])
    Process.sleep(250)
  end

  # ===========================================================================

  spex "The tab context menu opens on a tab and owns the keyboard",
    description: "Right-clicking a tab raises the bulk-close popup; Escape takes it away again",
    tags: [:tabs, :context_menu],
    fail_on_error_logs: false do
    scenario "Right-clicking a tab raises the bulk-close actions" do
      given_ "four tabs, with the editor demonstrably holding the keyboard", context do
        [a, b, c, d] = four_tabs()

        refute menu_open?(), "no context menu should be showing before the right-click"

        # Establish, before the popup exists, that the editor really is taking
        # keystrokes. Without this the "swallowed while open" scenario below
        # passes for the wrong reason — a pane that never had focus ignores
        # keys whether or not the menu is doing its job.
        Integration.ensure_editor_focused()
        assert Integration.editor_focused?()

        before = active_lines()
        Probes.send_text("y")
        Process.sleep(300)

        assert active_lines() != before,
               "the editor must be accepting keystrokes before this file proves it stops"

        {:ok, Map.merge(context, %{a: a, b: b, c: c, d: d})}
      end

      when_ "we right-click the second tab", context do
        right_click_tab(context.b)
        {:ok, context}
      end

      then_ "all three bulk-close actions are on screen", context do
        rendered = Query.rendered_text()

        for label <- ["Close Other Tabs", "Close Tabs to the Right", "Close All Tabs"] do
          assert String.contains?(rendered, label),
                 "expected #{inspect(label)} in the popup. Got: #{inspect(rendered)}"
        end

        {:ok, context}
      end

      then_ "the popup is anchored to the tab that was clicked", context do
        assert root_state().tab_context_menu.uuid == context.b.uuid,
               "the menu must act on the right-clicked tab, not the active one"

        {:ok, context}
      end
    end

    scenario "While it is open, the editor does not have the keyboard" do
      given_ "the popup is up over a document with known content", context do
        assert menu_open?()
        {:ok, Map.put(context, :lines_before, active_lines())}
      end

      then_ "the editor pane has been taken off the keyboard", context do
        refute Integration.editor_focused?(),
               "opening the menu must blur and gate the editor pane"

        {:ok, context}
      end

      when_ "we type a printable character", context do
        Probes.send_text("z")
        Process.sleep(300)
        {:ok, context}
      end

      then_ "the document is untouched", context do
        assert active_lines() == context.lines_before,
               "a keystroke under an open context menu must not edit the document"

        {:ok, context}
      end
    end

    scenario "Escape closes it, changing nothing" do
      when_ "we press Escape", context do
        Probes.send_keys("escape", [])
        Process.sleep(400)
        {:ok, context}
      end

      then_ "the popup is gone and every tab is still open", context do
        refute menu_open?(), "Escape must dismiss the context menu"
        assert length(buffer_names()) == 4, "Escape must not close anything"
        assert root_state().tab_context_menu == nil
        {:ok, context}
      end

      then_ "the editor has the keyboard back", context do
        assert Integration.editor_focused?(),
               "closing the menu must hand the keyboard back to the editor pane"

        before = active_lines()
        Probes.send_text("k")
        Process.sleep(300)

        assert active_lines() != before,
               "closing the menu must hand the keyboard back to the document"

        {:ok, context}
      end
    end
  end

  spex "Bulk closes act relative to the right-clicked tab",
    description: "Close Others / Close to the Right / Close All, and the active buffer after",
    tags: [:tabs, :context_menu],
    fail_on_error_logs: false do
    scenario "Close Tabs to the Right closes only the tabs after the clicked one" do
      given_ "four tabs", context do
        [a, b, c, d] = four_tabs()
        {:ok, Map.merge(context, %{a: a, b: b, c: c, d: d})}
      end

      when_ "we right-click the second tab and choose Close Tabs to the Right", context do
        right_click_tab(context.b)
        assert menu_open?()
        click_menu_row(1)
        {:ok, context}
      end

      then_ "only the two tabs to its left remain", context do
        assert buffer_names() == ["ctx-a.txt", "ctx-b.txt"]
        refute menu_open?(), "choosing an action must dismiss the popup"
        {:ok, context}
      end
    end

    scenario "Close Other Tabs leaves the clicked tab, and it is the active buffer" do
      given_ "four tabs with the LAST one active", context do
        [a, b, c, d] = four_tabs()
        assert active_name() == "ctx-d.txt"
        {:ok, Map.merge(context, %{a: a, b: b, c: c, d: d})}
      end

      when_ "we right-click a tab that is NOT the active one and choose Close Other Tabs",
            context do
        right_click_tab(context.b)
        assert menu_open?()
        click_menu_row(0)
        {:ok, context}
      end

      then_ "only that tab is left, and the editor is showing it", context do
        assert buffer_names() == ["ctx-b.txt"]

        assert active_name() == "ctx-b.txt",
               "closing the active tab must leave a sane active buffer, not nil"

        {:ok, context}
      end
    end

    scenario "Close All Tabs leaves one empty buffer, not the last tab" do
      given_ "four tabs", context do
        four_tabs()
        {:ok, context}
      end

      when_ "we right-click a tab and choose Close All Tabs", context do
        [_a, b | _] = Quillex.Buffer.list()
        right_click_tab(b)
        assert menu_open?()
        click_menu_row(2)
        Process.sleep(400)
        {:ok, context}
      end

      then_ "the editor holds exactly one fresh untitled buffer", context do
        names = buffer_names()

        assert length(names) == 1,
               "Close All Tabs should end with one buffer, got #{inspect(names)}"

        refute String.starts_with?(hd(names), "ctx-"),
               "the surviving buffer must be a fresh one, not a leftover tab: #{inspect(names)}"

        assert active_lines() == [""], "the fresh buffer should be empty"
        {:ok, context}
      end
    end
  end

  spex "A bulk close over unsaved work asks once, for the whole batch",
    description: "One prompt covers every dirty tab: cancel closes none, discard closes all",
    tags: [:tabs, :context_menu, :unsaved],
    fail_on_error_logs: false do
    scenario "Cancelling the prompt closes nothing" do
      given_ "three tabs, two of them dirty", context do
        [a, b, c] = tabs_with_two_dirty()
        assert length(buffer_names()) == 3
        {:ok, Map.merge(context, %{a: a, b: b, c: c})}
      end

      when_ "we right-click the clean tab and choose Close Other Tabs", context do
        right_click_tab(context.a)
        assert menu_open?()
        click_menu_row(0)
        {:ok, context}
      end

      then_ "exactly one Unsaved Changes prompt appears, naming both dirty tabs", context do
        rendered = Query.rendered_text()

        assert String.contains?(rendered, "Unsaved Changes")
        assert String.contains?(rendered, "dirty-b.txt")
        assert String.contains?(rendered, "dirty-c.txt")

        assert length(buffer_names()) == 3,
               "nothing may close while the batch is still waiting on an answer"

        {:ok, context}
      end

      when_ "we cancel it", context do
        Probes.send_keys("escape", [])
        Process.sleep(500)
        {:ok, context}
      end

      then_ "every tab is still open and no batch is left queued", context do
        refute Query.text_visible?("Unsaved Changes")
        assert length(buffer_names()) == 3, "Cancel must close nothing at all"

        assert root_state().pending_tab_context_close == [],
               "a cancelled batch must not stay queued in scene state"

        {:ok, context}
      end
    end

    scenario "Discarding closes the whole batch, clean tabs included" do
      given_ "three tabs, two of them dirty", context do
        [a, b, c] = tabs_with_two_dirty()
        {:ok, Map.merge(context, %{a: a, b: b, c: c})}
      end

      when_ "we right-click the clean tab, choose Close Other Tabs and discard", context do
        right_click_tab(context.a)
        assert menu_open?()
        click_menu_row(0)
        assert Query.text_visible?("Unsaved Changes")
        Probes.send_keys("d", [])
        Process.sleep(700)
        {:ok, context}
      end

      then_ "only the clicked tab is left", context do
        refute Query.text_visible?("Unsaved Changes")
        assert buffer_names() == ["clean-a.txt"]

        assert root_state().pending_tab_context_close == [],
               "the queue must be emptied by the answer, not left behind"

        {:ok, context}
      end

      then_ "cleanup", context do
        dismiss_everything()
        Quillex.TestHelpers.AppReset.reset!()
        {:ok, context}
      end
    end
  end

  # One clean tab followed by two tabs made dirty through the editor, so the
  # dirty? flags are the real ones the close path reads back out of each
  # Buffer.Process.
  defp tabs_with_two_dirty do
    refs = only_tabs(~w(clean-a.txt dirty-b.txt dirty-c.txt))
    [_clean | dirty] = refs

    Enum.each(dirty, fn ref ->
      Quillex.Buffer.activate(ref)
      Process.sleep(250)
      Probes.send_text("!")
      Process.sleep(250)
    end)

    Process.sleep(300)
    assert Enum.map(Quillex.Buffer.dirty_buffers(), & &1.name) == ["dirty-b.txt", "dirty-c.txt"]
    refs
  end
end
