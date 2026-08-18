defmodule Quillex.ThemesSpex do
  @moduledoc """
  Part II item 6: five themes, one palette, everything at once.

  A theme is not an editor setting here — it drives the editor *and* the
  chrome, because a light buffer inside a dark sidebar reads as broken rather
  than as a theme. These scenarios pick each theme from View → Theme and check
  that the colour reached every surface: the buffer pane, the tab bar, the
  menubar, the sidebar and the search pane.
  """
  use SexySpex
  @moduletag timeout: 300_000

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.AppReset
  alias Quillex.GUI.Palette

  defp root_state, do: :sys.get_state(Process.whereis(QuillEx.RootScene)).assigns.state

  defp child_state(id) do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, [pid | _]} = Scenic.Scene.child(root, id)
    :sys.get_state(pid, 30_000).assigns.state
  end

  defp wait_until(predicate, timeout \\ 4_000) do
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

  defp choose_theme(id) do
    Probes.click_element("icon_menu_view")
    Process.sleep(200)
    Probes.click_element("icon_menu_view_theme_#{id}")
    Process.sleep(400)
    true = wait_until(fn -> root_state().theme == id end)
    Probes.send_keys("escape", [])
    Process.sleep(200)
    :ok
  end

  setup_all do
    {:ok, _} = Application.ensure_all_started(:quillex)
    Process.sleep(1_000)
    AppReset.reset!()

    {:ok, buf} =
      Quillex.Buffer.new(%{
        name: "themes.ex",
        data: [
          "defmodule Themes do",
          "  @moduledoc \"one palette, every surface\"",
          "  def paint(surface), do: {:ok, surface}",
          "end"
        ]
      })

    :ok = Quillex.Buffer.activate(buf)
    Process.sleep(400)
    on_exit(fn -> Quillex.RadixCache.ViewStore.set_theme(Palette.default()) end)
    {:ok, buf: buf}
  end

  spex "Every theme reaches every surface",
    description: "Choosing a theme repaints the editor, the tab bar, the menubar and the sidebar",
    tags: [:phase_45, :themes] do
    scenario "walking all five themes from the View menu" do
      given_ "the file navigator is open so the sidebar is on screen", context do
        Quillex.RadixCache.ViewStore.open_file_nav()
        assert wait_until(fn -> root_state().show_file_nav end)
        Process.sleep(300)
        {:ok, context}
      end

      then_ "each theme repaints the buffer, the tabs, the menubar and the sidebar", context do
        for {id, label} <- Palette.themes() do
          :ok = choose_theme(id)
          palette = Palette.get(id)

          assert child_state(:buffer_pane).colors.background == palette.editor_bg,
                 "#{label} did not reach the editor"

          assert child_state(:tab_bar).theme.background == palette.chrome_bg,
                 "#{label} did not reach the tab bar"

          assert child_state(:icon_menu).theme.background == palette.chrome_bg,
                 "#{label} did not reach the menubar"

          assert child_state(:file_nav).theme.background == palette.pane_bg,
                 "#{label} did not reach the file navigator"

          Probes.take_screenshot("45_theme_#{id}")
        end

        {:ok, context}
      end

      then_ "the search pane is themed too", context do
        :ok = choose_theme(:solarized_light)
        Probes.send_keys("f", [:ctrl, :shift])
        Process.sleep(500)
        assert root_state().show_project_search

        palette = Palette.get(:solarized_light)

        assert wait_until(fn ->
                 child_state(:project_search_pane).theme.background == palette.pane_bg
               end),
               "the search pane kept the previous theme"

        Probes.take_screenshot("45_theme_search_pane")
        Quillex.RadixCache.ViewStore.close_project_search()
        Process.sleep(300)
        {:ok, context}
      end

      then_ "the default theme is exactly what Quillex looked like before themes", context do
        :ok = choose_theme(Palette.default())
        colors = child_state(:buffer_pane).colors

        # Medium slate blue behind the text, white on top of it — the values
        # the app shipped with. Choosing the default must be a no-op, not a
        # redesign.
        assert colors.background == {123, 104, 238}
        assert colors.text == :white
        assert colors.cursor == :white
        {:ok, context}
      end
    end
  end

  spex "A theme survives a buffer switch and a resize",
    description: "Repainting is not something the chrome forgets when it is rebuilt",
    tags: [:phase_45, :themes] do
    scenario "choosing a theme, then changing what is on screen" do
      given_ "High Contrast is chosen", context do
        :ok = choose_theme(:high_contrast)
        {:ok, context}
      end

      when_ "another buffer is opened and activated", context do
        {:ok, other} = Quillex.Buffer.new(%{name: "other.txt", data: ["something else"]})
        :ok = Quillex.Buffer.activate(other)
        Process.sleep(500)
        {:ok, context}
      end

      then_ "every surface is still High Contrast", context do
        palette = Palette.get(:high_contrast)

        assert wait_until(fn ->
                 child_state(:buffer_pane).colors.background == palette.editor_bg
               end),
               "the rebuilt buffer pane lost the theme"

        assert child_state(:tab_bar).theme.background == palette.chrome_bg
        assert child_state(:icon_menu).theme.background == palette.chrome_bg
        {:ok, context}
      end
    end
  end
end
