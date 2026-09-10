defmodule Quillex.ShowcaseSpex do
  @moduledoc """
  The short demo: forty-five seconds of the parts of Quillex that look like
  something, with nothing typed into the editor but the code.

  It shows, in this order, editing (a function typed into a module, highlighted
  as it lands, undone and redone), find in the buffer, find across the project
  with results opening as previews, folding two functions from the gutter, and
  two themes. That is the same tour the README gif records — minus the recorder
  — and the order is chosen so each act sets up the next: project search opens
  other files, folding brings the code back, and the themes recolour a screen
  that by then has code, tabs and a navigator on it.

  Run it with `scripts/run_demo --short`. The long form, `scripts/run_demo`,
  is `60_demo_spex.exs`: every feature of 1.0, narrated, ten minutes or so.

  It asserts as it goes, like the demo does, because a showcase that plays
  through a broken feature is worse than no showcase at all. And it is meant to
  be watched with the spex output beside it: the given/when/then lines ARE the
  narration.
  """
  use SexySpex
  @moduletag timeout: 300_000

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.AppReset
  alias Quillex.GUI.Palette
  alias Quillex.RadixCache.ViewStore
  import Quillex.TestHelpers.Integration, only: [ensure_editor_focused: 0]

  @demo_dir "/tmp/quillex_showcase"

  # The editor text and chrome are scaled up for the 2000px test window, so a
  # room can read it. Same numbers the README gif uses.
  @text_size 24
  @chrome_zoom 150

  # ── Pacing ────────────────────────────────────────────────────────────────
  #
  # `scripts/run_demo --short --fast` runs the same script as a plain test.

  defp fast?, do: System.get_env("DEMO_SPEED", "watch") == "fast"

  defp dwell(ms), do: Process.sleep(if fast?(), do: max(div(ms, 8), 10), else: ms)

  # ── Reading the editor ────────────────────────────────────────────────────

  defp root_state, do: :sys.get_state(Process.whereis(Quillex.RootScene)).assigns.state

  defp child_state(id) do
    root = :sys.get_state(Process.whereis(Quillex.RootScene))
    {:ok, [pid | _]} = Scenic.Scene.child(root, id)
    :sys.get_state(pid, 30_000).assigns.state
  end

  defp text_field_state, do: child_state(:buffer_pane)

  defp active_buf, do: root_state().active_buf

  defp active_buffer do
    {:ok, snapshot} = Quillex.Buffer.fetch(active_buf())
    snapshot
  end

  defp text, do: Enum.join(active_buffer().lines, "\n")
  defp cursor, do: active_buffer().cursor

  defp buffer_named(name) do
    [buf] = Enum.filter(Quillex.Buffer.list(), &(&1.name == name))
    buf
  end

  defp wait_until(predicate, timeout \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait(predicate, deadline)
  end

  defp do_wait(predicate, deadline) do
    cond do
      predicate.() -> true
      System.monotonic_time(:millisecond) >= deadline -> false
      true -> Process.sleep(30) && do_wait(predicate, deadline)
    end
  end

  # ── Driving the editor ────────────────────────────────────────────────────

  # A character at a time, because a demo that pastes is a screenshot.
  defp type(string) do
    for <<char::utf8 <- string>> do
      Probes.send_text(<<char::utf8>>)
      Process.sleep(if fast?(), do: 0, else: 40)
    end

    Process.sleep(60)
  end

  defp key(k, mods \\ []) do
    Probes.send_keys(k, mods)
    Process.sleep(if fast?(), do: 25, else: 180)
  end

  # Undo is per edit and typing is per character, so a function unwinds a
  # keystroke at a time. That is what it looks like to a user.
  defp press_until(k, mods, done?, remaining \\ 200) do
    cond do
      done?.() ->
        :ok

      remaining == 0 ->
        :ok

      true ->
        Probes.send_keys(k, mods)
        Process.sleep(if fast?(), do: 5, else: 12)
        press_until(k, mods, done?, remaining - 1)
    end
  end

  # Open the dropdown only if it is shut (choosing a toggle leaves it open),
  # then click the row. Menus need real time to open, even in fast mode.
  defp menu(menu_id, item_id) do
    unless child_state(:icon_menu).active_menu == menu_id do
      Probes.click_element("icon_menu_#{menu_id}")
      Process.sleep(500)
    end

    Probes.click_element("icon_menu_#{menu_id}_#{item_id}")
    Process.sleep(600)
  end

  defp close_menus do
    key("escape")
    Process.sleep(200)
  end

  defp open(name) do
    {:ok, _} = Quillex.API.FileAPI.open(Path.join(@demo_dir, name))
    Process.sleep(500)
    :ok = Quillex.Buffer.activate(buffer_named(Path.basename(name)))
    Process.sleep(400)
    ensure_editor_focused()
  end

  # ── Setup ─────────────────────────────────────────────────────────────────

  setup_all do
    {:ok, _} = Application.ensure_all_started(:quillex)
    Process.sleep(1_500)
    AppReset.reset!()
    Process.sleep(500)

    File.rm_rf!(@demo_dir)
    File.mkdir_p!(Path.join(@demo_dir, "lib"))
    File.mkdir_p!(Path.join(@demo_dir, "test"))

    File.write!(Path.join(@demo_dir, "lib/greeter.ex"), """
    defmodule Demo.Greeter do
      @moduledoc "A little module, so there is some code to look at."

      def greet(name) do
        if name == "" do
          "hello, stranger"
        else
          "hello, " <> name
        end
      end

      def farewell(name) do
        "goodbye, " <> name
      end

      def greet_all(names) do
        Enum.map(names, &greet/1)
      end
    end
    """)

    File.write!(Path.join(@demo_dir, "lib/notes.txt"), """
    hello from a second file
    project search finds the word hello across all of these
    and opens each result in a reusable preview tab
    """)

    File.write!(Path.join(@demo_dir, "test/greeter_test.exs"), """
    defmodule Demo.GreeterTest do
      use ExUnit.Case

      test "greets by name" do
        assert Demo.Greeter.greet("world") == "hello, world"
      end
    end
    """)

    File.write!(
      Path.join(@demo_dir, "README.md"),
      "# demo\n\nA project for the Quillex showcase.\n"
    )

    File.write!(
      Path.join(@demo_dir, "mix.exs"),
      "defmodule Demo.MixProject do\n  use Mix.Project\nend\n"
    )

    ViewStore.set_theme(Palette.default())
    ViewStore.set_text_size(@text_size)
    ViewStore.set_chrome_zoom(@chrome_zoom)
    ViewStore.set_file_nav_path(@demo_dir)
    ViewStore.open_file_nav()
    Process.sleep(800)

    on_exit(fn ->
      ViewStore.set_theme(Palette.default())
      ViewStore.set_text_size(14)
      ViewStore.set_chrome_zoom(100)
      ViewStore.set_file_nav_path(File.cwd!())
      Process.sleep(200)
      File.rm_rf!(@demo_dir)
    end)

    :ok
  end

  # ══════════════════════════════════════════════════════════════════════════

  spex "Quillex in forty-five seconds",
    description: "Editing, find, project search, folding and themes — the short demo",
    tags: [:demo, :showcase] do
    scenario "the tour" do
      given_ "a project open in the navigator, with a module on screen", context do
        assert wait_until(fn -> root_state().show_file_nav end)
        open("lib/greeter.ex")
        assert active_buf().name == "greeter.ex"

        for buf <- Quillex.Buffer.list(), buf.name == "untitled" do
          Quillex.Buffer.close(buf, :discard)
        end

        Process.sleep(300)
        refute Enum.any?(root_state().buffers, &(&1.name == "untitled"))
        dwell(1_200)
        {:ok, context}
      end

      when_ "a function is typed, highlighted as it lands, undone, and redone", context do
        # Line 15 is the blank line after farewell/1. Auto-indent is off while
        # typing so the indentation on screen is exactly what was typed.
        {:ok, _} = Quillex.Buffer.dispatch(active_buf(), [{:set_cursor, {15, 1}}])
        assert wait_until(fn -> cursor() == {15, 1} end)
        ViewStore.set_auto_indent(false)
        Process.sleep(120)

        key("enter")
        type("  def shout(name) do")
        key("enter")
        type("    name |> greet() |> String.upcase()")
        key("enter")
        type("  end")
        key("enter")

        ViewStore.set_auto_indent(true)
        assert wait_until(fn -> text() =~ "def shout" end), "typing did not reach the buffer"
        dwell(1_000)

        press_until("z", [:ctrl], fn -> not (text() =~ "shout") end)
        refute text() =~ "shout", "undo did not remove the typed function"
        dwell(700)

        press_until("z", [:ctrl, :shift], fn -> text() =~ "String.upcase()" end)
        assert text() =~ "def shout", "redo did not restore it"
        dwell(1_000)
        {:ok, context}
      end

      when_ "Ctrl+F finds the word hello, and F3 walks the matches", context do
        key("f", [:ctrl])
        assert wait_until(fn -> root_state().show_search_bar end)
        dwell(400)
        type("hello")
        dwell(900)
        key("escape")
        ensure_editor_focused()
        key("f3")
        dwell(700)
        key("f3")
        dwell(900)
        {:ok, context}
      end

      when_ "Ctrl+Shift+F searches the project, and results open as previews", context do
        key("f", [:ctrl, :shift])
        assert wait_until(fn -> root_state().show_project_search end)
        dwell(400)
        type("hello")
        :ok = Quillex.RadixCache.ProjectSearchStore.await_idle()

        assert wait_until(fn ->
                 match?(%{status: {:done, _, _, _}}, root_state().project_search)
               end),
               "the project search never finished"

        dwell(1_400)

        %{files: files} = root_state().project_search
        {notes_path, [m | _]} = Enum.find(files, fn {p, _} -> Path.basename(p) == "notes.txt" end)
        Probes.click_element("search_pane_match_#{m.line}_#{m.col}_#{notes_path}")

        assert wait_until(fn -> root_state().active_buf.name == "notes.txt" end),
               "clicking a result should open that file"

        dwell(1_400)

        {test_path, [m2 | _]} =
          Enum.find(files, fn {p, _} -> Path.basename(p) == "greeter_test.exs" end)

        Probes.click_element("search_pane_match_#{m2.line}_#{m2.col}_#{test_path}")
        assert wait_until(fn -> root_state().active_buf.name == "greeter_test.exs" end)
        dwell(1_200)

        ViewStore.close_project_search()
        assert wait_until(fn -> not root_state().show_project_search end)
        dwell(400)
        {:ok, context}
      end

      when_ "two functions fold from the gutter, and Unfold All opens them", context do
        :ok = Quillex.Buffer.activate(buffer_named("greeter.ex"))
        Process.sleep(400)
        ensure_editor_focused()
        dwell(500)

        # Hover a foldable line number so its triangle appears, then click it.
        # farewell (line 12) folds first: folding greet would hide lines 5-10
        # and move every later line up the screen.
        for line <- [12, 4] do
          %{frame: frame, font: %{size: line_height}} = text_field_state()
          x = frame.pin.x + 6
          y = frame.pin.y + 8 + (line - 1) * line_height

          Probes.send_mouse_move(x, y)

          assert wait_until(fn -> text_field_state().fold_hover_line == line end),
                 "hovering line #{line} should show its fold triangle"

          dwell(500)
          Probes.click(x, y)

          assert wait_until(fn -> MapSet.member?(text_field_state().folds, line) end),
                 "clicking the triangle should fold the block on line #{line}"

          dwell(900)
        end

        dwell(800)
        menu(:view, :unfold_all)

        assert wait_until(fn -> MapSet.size(text_field_state().folds) == 0 end),
               "Unfold All should open every fold"

        dwell(500)
        close_menus()
        dwell(900)
        {:ok, context}
      end

      then_ "two themes from the View menu recolour everything on screen", context do
        # Open the View menu so the Theme row is on screen while the palette
        # changes; the row itself is not clicked (its Select sits below the
        # dropdown's fold, and a click there has landed on the Text Size
        # slider). The store drives the switch, and the menu recolours with it.
        Probes.click_element("icon_menu_view")
        Process.sleep(500)
        assert child_state(:icon_menu).active_menu == :view
        dwell(700)

        for id <- [:solarized_dark, :alchemical_light] do
          ViewStore.set_theme(id)
          assert wait_until(fn -> root_state().theme == id end)
          dwell(1_300)
        end

        close_menus()
        ViewStore.set_theme(Palette.default())
        assert wait_until(fn -> root_state().theme == Palette.default() end)
        dwell(1_800)
        {:ok, context}
      end
    end
  end
end
