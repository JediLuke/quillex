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
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))

    case Scenic.Scene.child(root, id) do
      {:ok, [pid | _]} -> :sys.get_state(pid, 30_000).assigns.state.theme
      _ -> nil
    end
  end

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

        assert_in_delta ratio, 1.5, 0.15,
                        "150% zoom scaled the tabs by #{Float.round(ratio, 2)}"

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
  end
end
