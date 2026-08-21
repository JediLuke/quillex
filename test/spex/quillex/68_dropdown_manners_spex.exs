defmodule Quillex.DropdownMannersSpex do
  @moduledoc """
  The things a dropdown has to do that nobody writes down.

  Every one of these is a product requirement that is obvious the moment it is
  missing and invisible the rest of the time — which is exactly why they need
  guarding. They were all found by using the editor, not by reading it:

    * Escape puts a menu away. And puts away the MENU, not everything: shutting
      the whole search pane because a menu happened to be open throws away the
      search too.
    * Scrolling somewhere else puts it away. Scrolling what is behind a menu is
      a person having finished with the menu; leaving it up means it hangs over
      what they are now reading.
    * Whatever redraws underneath it must not land on top of it. A menu buried
      by the thing it is floating over is worse than one that never opened.

  The third had a real cause worth remembering: a replaced piece of a Scenic
  graph lands at the END, which is what puts it on top. Every other piece of
  this pane is disjoint so it never mattered — but the settings panel
  deliberately overlaps the results, so results rebuilt AFTER it were drawn
  over it. Toggling a settings option is exactly the case: the panel redraws
  for the option, then the search it started comes back and rebuilds the body.
  """
  use SexySpex
  @moduletag timeout: 300_000

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.AppReset

  defp pane_scene do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))

    case Scenic.Scene.child(root, :project_search_pane) do
      {:ok, [pid | _]} -> :sys.get_state(pid, 30_000)
      _ -> nil
    end
  end

  defp pane_open?, do: pane_scene() != nil
  defp pane_state, do: pane_scene().assigns.state
  defp pane_graph, do: pane_scene().assigns.graph

  defp settings_open?, do: pane_open?() and pane_state().domain_open?

  # Which of the two overlapping pieces is drawn LAST, and so on top.
  #
  # Not by uid — a primitive does not carry one — and not by position in
  # `graph.primitives`, which is a map. Drawing order is the order of the ROOT
  # group's child list, which is the thing Scenic walks.
  defp settings_above_results? do
    graph = pane_graph()
    children = Map.get(graph.primitives, 0).data

    with [settings] <- Map.get(graph.ids, :search_pane_settings),
         [body] <- Map.get(graph.ids, :search_pane_body),
         settings_at when is_integer(settings_at) <- Enum.find_index(children, &(&1 == settings)),
         body_at when is_integer(body_at) <- Enum.find_index(children, &(&1 == body)) do
      settings_at > body_at
    else
      _ -> :no_panel
    end
  end

  defp icon_menu_state do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, [pid | _]} = Scenic.Scene.child(root, :icon_menu)
    :sys.get_state(pid, 30_000).assigns.state
  end

  defp wait_until(predicate, timeout \\ 8_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait(predicate, deadline)
  end

  defp do_wait(predicate, deadline) do
    cond do
      predicate.() -> true
      System.monotonic_time(:millisecond) >= deadline -> false
      true -> Process.sleep(25) && do_wait(predicate, deadline)
    end
  end

  defp write_fixture(root) do
    File.rm_rf!(root)
    File.mkdir_p!(Path.join(root, "lib"))

    Enum.each(1..6, fn i ->
      File.write!(Path.join(root, "lib/mod_#{i}.ex"), "def needle_#{i}(x), do: x\n")
    end)

    :ok
  end

  defp open_pane_with(root, query) do
    AppReset.reset!()
    Quillex.RadixCache.ViewStore.set_file_nav_path(root)
    Process.sleep(400)

    Probes.send_keys("f", [:ctrl, :shift])
    true = wait_until(fn -> pane_open?() end)

    Probes.click_element("search_pane_clear")
    Process.sleep(200)
    Probes.send_text(query)
    true = wait_until(fn -> pane_state().model.files != [] end, 15_000)
    :ok
  end

  defp open_settings do
    unless settings_open?() do
      Probes.click_element("search_pane_domain")
      true = wait_until(fn -> settings_open?() end)
    end

    :ok
  end

  defp panel_centre do
    state = pane_state()
    panel = ScenicWidgets.SearchPane.State.settings_frame(state)
    {px, py} = panel.pin.point
    {pin_x, pin_y} = state.frame.pin.point

    {trunc(pin_x + px + panel.size.width / 2), trunc(pin_y + py + panel.size.height / 2)}
  end

  setup_all do
    {:ok, _} = Application.ensure_all_started(:quillex)
    Process.sleep(1_000)
    AppReset.reset!()

    root = Path.join(System.tmp_dir!(), "quillex_dropdown_manners")
    write_fixture(root)

    on_exit(fn ->
      Quillex.RadixCache.ViewStore.set_file_nav_path(File.cwd!())
      Process.sleep(200)
      File.rm_rf!(root)
    end)

    {:ok, root: root}
  end

  spex "A dropdown behaves like a dropdown",
    description: "Escape and scroll put it away; nothing redraws over the top of it",
    tags: [:phase_41, :search_pane, :menubar, :manners] do
    scenario "results redrawing underneath it" do
      given_ "the search pane with results, and the settings open", context do
        write_fixture(context.root)
        :ok = open_pane_with(context.root, "needle")
        :ok = open_settings()

        assert settings_above_results?() == true,
               "the panel is not on top of the results to begin with"

        {:ok, context}
      end

      when_ "a setting is toggled, which starts a new search", context do
        Probes.click_element("search_pane_domain_open_buffers_only")
        Process.sleep(200)

        # And wait for the RESULTS to come back, which is the redraw that used
        # to bury it — not for the click, which is not the problem.
        assert wait_until(fn ->
                 match?({:done, _, _, _}, Quillex.RadixCache.ProjectSearchStore.get_state().status)
               end, 10_000),
               "the toggle never produced a finished search"

        Process.sleep(300)
        {:ok, context}
      end

      then_ "the panel is still on top of them", context do
        assert settings_open?(), "the toggle closed the settings"

        assert settings_above_results?() == true,
               """
               the results were rebuilt after the panel and drew over it. A
               replaced piece of the graph lands at the end, which is what puts
               it on top — so the panel has to be re-rendered whenever anything
               under it is.
               """

        {:ok, context}
      end

      when_ "the setting is toggled back", context do
        Probes.click_element("search_pane_domain_open_buffers_only")

        assert wait_until(fn -> pane_state().model.files != [] end, 10_000),
               "the results never came back"

        Process.sleep(300)
        {:ok, context}
      end

      then_ "it is still on top", context do
        assert settings_above_results?() == true,
               "the second toggle buried it, which is exactly how this was noticed"

        {:ok, context}
      end
    end

    scenario "putting it away" do
      given_ "the settings open", context do
        :ok = open_settings()
        {:ok, context}
      end

      when_ "the wheel is turned somewhere that is not the panel", context do
        state = pane_state()
        {pin_x, pin_y} = state.frame.pin.point
        body = ScenicWidgets.SearchPane.State.body_frame(state)
        {_bx, by} = body.pin.point

        # Over the results, well below the panel.
        Probes.send_scroll(0, -1, trunc(pin_x + 40), trunc(pin_y + by + body.size.height - 20))
        Process.sleep(300)

        {:ok, context}
      end

      then_ "it goes away", context do
        assert wait_until(fn -> not settings_open?() end),
               """
               scrolling what is behind a menu is a person having finished with
               the menu. Left open, it hangs over what they are now reading.
               """

        {:ok, context}
      end

      when_ "it is opened again and Escape pressed", context do
        :ok = open_settings()
        Probes.send_keys("escape", [])
        Process.sleep(300)

        {:ok, context}
      end

      then_ "Escape closes the MENU, and leaves the pane", context do
        assert wait_until(fn -> not settings_open?() end),
               "Escape did not put the settings away"

        assert pane_open?(),
               """
               Escape shut the whole pane. One Escape, one thing: closing the
               search because a menu happened to be open throws away the search
               as well as the menu.
               """

        {:ok, context}
      end

      then_ "and a second Escape closes the pane, as it always did", context do
        Probes.send_keys("escape", [])

        assert wait_until(fn -> not pane_open?() end),
               "with no menu open, Escape should still close the pane"

        {:ok, context}
      end
    end

    scenario "the menubar's dropdowns keep the same manners" do
      when_ "a top-bar menu is open and the wheel turned elsewhere", context do
        Probes.click_element("icon_menu_view")
        assert wait_until(fn -> icon_menu_state().active_menu != nil end), "the view menu did not open"

        # Down in the document, nowhere near the dropdown.
        {_w, h} = Quillex.TestHelpers.ViewportResizer.viewport_size()
        Probes.send_scroll(0, -1, 400, trunc(h - 60))
        Process.sleep(300)

        {:ok, context}
      end

      then_ "it goes away too", context do
        assert wait_until(fn -> icon_menu_state().active_menu == nil end),
               """
               the top bar's dropdowns should behave the same way as the
               pane's — the rule is about menus, not about which menu.
               """

        {:ok, context}
      end
    end
  end
end
