defmodule Quillex.ChromeZoomSpex do
  @moduledoc """
  Zooming the chrome scales the chrome.

  It didn't. The layout reads the zoom directly, so the frames moved — the top
  bar got taller, the sidebar got wider — but every child kept the theme it
  had been created with, and a theme is where the font sizes live. The result
  was 13pt tabs in a bar that had grown to 52 tall, and a search pane whose
  text was the same size at 200% as at 50%.

  The cause was one clause: the repaint path fired only when the palette
  changed, and compared only `:theme`. Chrome zoom is not the palette, so it
  repainted nothing. And what it pushed was the palette's colours — so even
  when it did fire, sizes never travelled.

  This asserts on what the children are actually holding, since that is what
  they draw from, and covers going back down as well as up: a zoom that grows
  and never shrinks looks fine until you try it twice.
  """
  use SexySpex
  @moduletag timeout: 300_000

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.AppReset

  defp child_theme(id) do
    root = :sys.get_state(Process.whereis(Quillex.RootScene))

    case Scenic.Scene.child(root, id) do
      {:ok, [pid | _]} -> :sys.get_state(pid, 30_000).assigns.state.theme
      _ -> nil
    end
  end

  # Where the root scene has PLACED a sidebar child: the translate it gave the
  # component in its own graph. Each child rebuilds its contents from the frame
  # it is handed, but only this decides where on screen those contents land.
  defp placed_at(id) do
    root = :sys.get_state(Process.whereis(Quillex.RootScene))

    case Scenic.Graph.get(root.assigns.graph, id) do
      [primitive] -> primitive.transforms[:translate]
      _ -> nil
    end
  end

  defp root_state, do: :sys.get_state(Process.whereis(Quillex.RootScene)).assigns.state

  defp zoom(n) do
    Quillex.RadixCache.ViewStore.set_chrome_zoom(n)
    Quillex.RadixCache.ViewStore.sync()
    Process.sleep(700)
    :ok
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

  setup_all do
    {:ok, _} = Application.ensure_all_started(:quillex)
    Process.sleep(1_000)
    AppReset.reset!()

    on_exit(fn ->
      Quillex.RadixCache.ViewStore.set_chrome_zoom(100)
      Process.sleep(300)
    end)

    :ok
  end

  spex "Zooming the chrome scales the chrome",
    description: "Every piece of chrome takes its type from the zoom, up and back down",
    tags: [:chrome, :zoom, :view_settings] do
    scenario "up and back" do
      given_ "the editor at 100%, with the search pane open", context do
        :ok = zoom(100)
        Probes.send_keys("f", [:ctrl, :shift])
        assert wait_until(fn -> child_theme(:project_search_pane) != nil end)

        at_100 = %{
          pane: child_theme(:project_search_pane).font_size,
          tabs: child_theme(:tab_bar).font_size,
          icons: child_theme(:icon_menu).icon_font_size
        }

        {:ok, Map.put(context, :at_100, at_100)}
      end

      when_ "the chrome is zoomed to 150%", context do
        :ok = zoom(150)
        {:ok, context}
      end

      then_ "every piece of chrome is drawn larger", context do
        at_150 = %{
          pane: child_theme(:project_search_pane).font_size,
          tabs: child_theme(:tab_bar).font_size,
          icons: child_theme(:icon_menu).icon_font_size
        }

        for {what, before} <- context.at_100 do
          now = Map.fetch!(at_150, what)

          assert now > before,
                 """
                 #{what} is still #{now}pt at 150% zoom, where it was #{before}
                 at 100%. The frames grew and the type stayed behind.
                 """
        end

        {:ok, Map.put(context, :at_150, at_150)}
      end

      then_ "and roughly by the amount asked for", context do
        # Not exactly: each is rounded, and the navigator's label has a floor.
        ratio = context.at_150.tabs / context.at_100.tabs

        assert_in_delta ratio, 1.5, 0.15, "150% zoom scaled the tabs by #{Float.round(ratio, 2)}"

        {:ok, context}
      end

      when_ "it is put back to 100%", context do
        :ok = zoom(100)
        {:ok, context}
      end

      then_ "everything returns to the size it was", context do
        back = %{
          pane: child_theme(:project_search_pane).font_size,
          tabs: child_theme(:tab_bar).font_size,
          icons: child_theme(:icon_menu).icon_font_size
        }

        assert back == context.at_100,
               """
               zooming out did not undo zooming in — a chrome that grows and
               never shrinks looks right until you try it twice.
                 was:  #{inspect(context.at_100)}
                 now:  #{inspect(back)}
               """

        {:ok, context}
      end
    end

    scenario "the navigator follows the tab bar" do
      given_ "the file navigator open at 100%", context do
        Quillex.RadixCache.ViewStore.close_project_search()
        Quillex.RadixCache.ViewStore.open_file_nav()
        Quillex.RadixCache.ViewStore.sync()
        :ok = zoom(100)
        assert wait_until(fn -> placed_at(:file_nav) != nil end)

        {_x, header_y} = placed_at(:file_nav_path_header)
        {_x, nav_y} = placed_at(:file_nav)
        {:ok, Map.merge(context, %{header_y: header_y, nav_y: nav_y})}
      end

      when_ "the chrome is zoomed to 200%", context do
        :ok = zoom(200)
        {:ok, context}
      end

      then_ "the path header and the tree sit below the taller tab bar", context do
        {_x, header_y} = placed_at(:file_nav_path_header)
        {_x, nav_y} = placed_at(:file_nav)

        # The tab bar is 35px of chrome and the path header 27px; at 200% each
        # is twice that. Both children were handed frames that far down, and
        # this checks they were also MOVED there: zooming used to leave them at
        # the 100% positions, half-hidden under the tabs.
        %{frame: %{pin: %{point: {_fx, frame_top}}}} = root_state()

        assert header_y == frame_top + 70,
               """
               the path header is drawn at y=#{header_y} at 200% zoom, where the
               tab bar now ends at #{frame_top + 70}. It was at #{context.header_y}
               at 100%: the frame moved down, the component did not.
               """

        assert nav_y == header_y + 54,
               """
               the file tree is drawn at y=#{nav_y} at 200% zoom, but the path
               header above it now ends at #{header_y + 54}. It was at
               #{context.nav_y} at 100%.
               """

        {:ok, context}
      end

      when_ "it is put back to 100%", context do
        :ok = zoom(100)
        {:ok, context}
      end

      then_ "both return to where they were", context do
        assert placed_at(:file_nav_path_header) |> elem(1) == context.header_y
        assert placed_at(:file_nav) |> elem(1) == context.nav_y
        {:ok, context}
      end
    end
  end
end
