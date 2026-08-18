defmodule Quillex.DemoSpex do
  @moduledoc """
  The demo. Every feature of Quillex 1.0, top to bottom, paced to be watched.

  It narrates itself by typing its own explanations into the buffer, then does
  the thing it just described. Run it with `scripts/run_demo` and watch;
  `DEMO_SPEED=fast` makes it a regression test instead.

  It is simultaneously a showcase and the most complete integration test in the
  suite, which is exactly why it came last (roadmap Part II item 11): it can
  only be written against a feature set that has stopped moving. Every act
  asserts. A demo that plays through while the feature underneath is broken
  would be worse than no demo at all.
  """
  use SexySpex
  @moduletag timeout: 900_000

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.AppReset
  alias Quillex.GUI.Palette
  import Quillex.TestHelpers.Integration, only: [ensure_editor_focused: 0]

  @project_root Path.expand("../../..", __DIR__)
  @demo_dir "/tmp/quillex_demo"

  # How fast it plays. `fast` is for running it as a test; the default is a
  # pace a person can read at.
  defp speed, do: System.get_env("DEMO_SPEED", "watch")

  defp beat(ms), do: Process.sleep(if speed() == "fast", do: div(ms, 6), else: ms)

  defp per_char_ms, do: if(speed() == "fast", do: 0, else: 18)

  defp root_state, do: :sys.get_state(Process.whereis(QuillEx.RootScene)).assigns.state

  defp child_state(id) do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, [pid | _]} = Scenic.Scene.child(root, id)
    :sys.get_state(pid, 30_000).assigns.state
  end

  defp active_buffer do
    {:ok, snapshot} = Quillex.Buffer.fetch(root_state().active_buf)
    snapshot
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

  # Typed a character at a time, because a demo that pastes is a screenshot.
  defp type(text) do
    case per_char_ms() do
      0 ->
        Probes.send_text(text)

      ms ->
        for <<char::utf8 <- text>> do
          Probes.send_text(<<char::utf8>>)
          Process.sleep(ms)
        end
    end

    Process.sleep(80)
  end

  defp newline do
    Probes.send_keys("enter", [])
    Process.sleep(60)
  end

  # The narration itself: clear the buffer, then write what is about to happen.
  #
  # And check that it arrived. Narration needs the keyboard, and the acts that
  # follow drive the editor through its stores instead — so without this the
  # demo can lose focus, fall silent, and still play its remaining acts and
  # pass. It did exactly that: the themes changed while nothing explained them.
  defp narrate(lines) do
    lines = List.wrap(lines)
    focus_editor()
    select_all_and_delete()

    lines
    |> Enum.with_index()
    |> Enum.each(fn {line, i} ->
      if i > 0, do: newline()
      type(line)
    end)

    first = hd(lines)

    assert wait_until(fn -> Enum.at(active_buffer().lines, 0) == first end),
           """
           the narration never reached the buffer — the editor did not have the
           keyboard, so this act would have played in silence.

             expected line 1: #{inspect(first)}
             buffer line 1:   #{inspect(Enum.at(active_buffer().lines, 0))}
           """

    beat(1_200)
  end

  defp text, do: Enum.join(active_buffer().lines, "\n")

  # Undo is per edit, and typing is per character, so unwinding a word takes
  # several presses. That is what it looks like to a user, so that is what the
  # demo shows — pressing until the condition holds rather than assuming a
  # granularity.
  defp undo_until(done?), do: press_until("z", [:ctrl], done?)
  defp redo_until(done?), do: press_until("z", [:ctrl, :shift], done?)

  defp press_until(key, mods, done?, remaining \\ 40) do
    cond do
      done?.() -> :ok
      remaining == 0 -> :ok
      true ->
        Probes.send_keys(key, mods)
        Process.sleep(if speed() == "fast", do: 25, else: 70)
        press_until(key, mods, done?, remaining - 1)
    end
  end

  defp select_all_and_delete do
    Probes.send_keys("a", [:ctrl])
    Process.sleep(120)
    Probes.send_keys("backspace", [])
    Process.sleep(200)
  end

  # Not a fixed click. The demo opens the file navigator and the search pane as
  # it goes, and the search pane takes the keyboard when you type into it —
  # after which a click at some remembered coordinate may focus nothing. This
  # derives the point from the pane's live frame and verifies the pane really
  # holds the keyboard, raising if it does not.
  defp focus_editor, do: ensure_editor_focused()

  defp menu(menu_id, item_id) do
    Probes.click_element("icon_menu_#{menu_id}")
    beat(500)
    Probes.click_element("icon_menu_#{menu_id}_#{item_id}")
    beat(600)
  end

  setup_all do
    {:ok, _} = Application.ensure_all_started(:quillex)
    Process.sleep(1_500)
    AppReset.reset!()
    Process.sleep(500)

    File.rm_rf!(@demo_dir)
    File.mkdir_p!(Path.join(@demo_dir, "lib"))

    File.write!(Path.join(@demo_dir, "lib/kernel.ex"), """
    defmodule Demo.Kernel do
      @moduledoc "A little module, so the demo has some code to look at."

      def greet(name) do
        "hello, " <> name
      end

      def farewell(name) do
        "goodbye, " <> name
      end
    end
    """)

    File.write!(Path.join(@demo_dir, "lib/notes.txt"), """
    hello from a second file
    the demo will search for the word hello across both of these
    and replace it, and then put it back
    """)

    Quillex.RadixCache.ViewStore.set_file_nav_path(@demo_dir)
    Process.sleep(300)

    on_exit(fn ->
      File.rm_rf!(@demo_dir)
      Quillex.RadixCache.ViewStore.set_theme(Palette.default())
    end)

    :ok
  end

  spex "Quillex, end to end",
    description: "Every feature of 1.0, narrated by the editor into its own buffer",
    tags: [:demo, :showcase, :integration] do
    scenario "Act I — typing, undo, and the buffer" do
      given_ "an empty editor", context do
        focus_editor()
        select_all_and_delete()
        assert wait_until(fn -> active_buffer().lines == [""] end)
        {:ok, context}
      end

      when_ "it introduces itself", context do
        narrate([
          "This is Quillex — a text editor written in Elixir,",
          "drawn by Scenic, and testing itself as you watch.",
          "",
          "Everything from here on is typed by the editor, into itself."
        ])

        {:ok, context}
      end

      then_ "the text really is in the buffer", context do
        assert Enum.at(active_buffer().lines, 0) =~ "This is Quillex"
        assert length(active_buffer().lines) == 4
        Probes.take_screenshot("60_demo_01_intro")
        {:ok, context}
      end

      when_ "it demonstrates undo and redo", context do
        narrate([
          "Undo is Ctrl+Z, and redo is Ctrl+Shift+Z — one edit at a",
          "time. Watch this word unwind, then come back:"
        ])

        newline()
        type("  UNDO ME")
        beat(900)

        undo_until(fn -> not (text() =~ "UNDO ME") end)
        beat(700)
        {:ok, Map.put(context, :after_undo, text())}
      end

      then_ "undo removed it, and redo brings it back", context do
        refute context.after_undo =~ "UNDO ME"

        redo_until(fn -> text() =~ "UNDO ME" end)

        assert text() =~ "UNDO ME", "redo did not restore the text"
        beat(900)
        {:ok, context}
      end
    end

    scenario "Act II — many files, and the way around them" do
      given_ "the narration sets the scene", context do
        focus_editor()

        narrate([
          "Files open in tabs. The file navigator on the left",
          "shows the project; drag a file to move it.",
          "",
          "Opening two files now…"
        ])

        {:ok, context}
      end

      when_ "two files are opened", context do
        Quillex.RadixCache.ViewStore.open_file_nav()
        assert wait_until(fn -> root_state().show_file_nav end)
        beat(900)

        {:ok, _} = Quillex.API.FileAPI.open(Path.join(@demo_dir, "lib/kernel.ex"))
        beat(1_200)
        {:ok, _} = Quillex.API.FileAPI.open(Path.join(@demo_dir, "lib/notes.txt"))
        beat(1_200)
        {:ok, context}
      end

      then_ "both are open, and the code one is highlighted structurally", context do
        names = Enum.map(root_state().buffers, & &1.name)
        assert "kernel.ex" in names
        assert "notes.txt" in names

        # Structural highlighting: weight and slant, never colour.
        styles = Quillex.GUI.Theme.highlight_styles()
        assert styles.keyword.font == :ibm_plex_mono_bold
        assert styles.comment.font == :ibm_plex_mono_light_italic

        Probes.take_screenshot("60_demo_02_files")
        {:ok, context}
      end

      then_ "Go to Line jumps straight to a line, and clamps past the end", context do
        [kernel] = Enum.filter(root_state().buffers, &(&1.name == "kernel.ex"))
        :ok = Quillex.Buffer.activate(kernel)
        beat(800)
        focus_editor()

        Probes.send_keys("g", [:ctrl])
        beat(600)
        assert root_state().show_goto_line

        for digit <- ["5"] do
          Probes.send_keys(digit, [])
          Process.sleep(150)
        end

        Probes.send_keys("enter", [])
        beat(800)

        assert wait_until(fn -> match?({5, _}, active_buffer().cursor) end),
               "Ctrl+G did not move the cursor to line 5"

        # And 999999 means "the end", because that is what people type when
        # they mean that.
        Probes.send_keys("g", [:ctrl])
        beat(400)
        for _ <- 1..6, do: (Probes.send_keys("9", []); Process.sleep(100))
        Probes.send_keys("enter", [])
        beat(700)

        last = length(active_buffer().lines)

        assert wait_until(fn -> match?({^last, _}, active_buffer().cursor) end),
               "Go to Line should clamp to the last line rather than refuse"

        {:ok, context}
      end
    end

    scenario "Act III — finding things, everywhere" do
      given_ "a narrated introduction", context do
        {:ok, scratch} = Quillex.Buffer.new(%{name: "demo.txt", data: [""]})
        :ok = Quillex.Buffer.activate(scratch)
        beat(600)
        focus_editor()

        narrate([
          "Ctrl+F finds text in this buffer.",
          "Ctrl+Shift+F searches every file in the project, with its",
          "own query, its own replacement, and results grouped by file",
          "— with the match marked inside the line.",
          "",
          "Dismiss a match before replacing, and the replace cannot",
          "reach it. Files already open are edited through their",
          "buffer, so Undo still works on them."
        ])

        {:ok, context}
      end

      when_ "the project search runs", context do
        Probes.send_keys("f", [:ctrl, :shift])
        beat(900)
        assert root_state().show_project_search

        type("hello")

        assert wait_until(fn ->
                 match?(%{status: {:done, _, _, _}}, root_state().project_search)
               end),
               "the project search never finished"

        beat(1_500)
        {:ok, context}
      end

      then_ "it found the word in both files", context do
        snapshot = root_state().project_search
        %{files: files} = snapshot
        names = Enum.map(files, fn {path, _} -> Path.basename(path) end)

        assert "kernel.ex" in names,
               "search found #{inspect(names)}; query=#{inspect(snapshot.query)} " <>
                 "root=#{inspect(snapshot.root)} status=#{inspect(snapshot.status)}"

        assert "notes.txt" in names

        Probes.take_screenshot("60_demo_03_project_search")
        {:ok, context}
      end

      then_ "a match can be dismissed, and then everything else replaced", context do
        %{files: files} = root_state().project_search
        {path, [match | _]} = Enum.find(files, fn {p, _} -> Path.basename(p) == "notes.txt" end)

        before = Enum.sum(Enum.map(files, fn {_p, ms} -> length(ms) end))

        Probes.click_element(
          "search_pane_dismiss_match_#{match.line}_#{match.col}_#{path}"
        )

        assert wait_until(fn ->
                 %{files: after_files} = root_state().project_search
                 Enum.sum(Enum.map(after_files, fn {_p, ms} -> length(ms) end)) == before - 1
               end),
               "dismissing a match should remove it from the results"

        beat(1_200)

        Probes.click_element("search_pane_field_replace")
        beat(400)
        type("g'day")
        beat(600)
        Probes.click_element("search_pane_replace_all")

        assert wait_until(fn -> (root_state().status_message || "") =~ "Replaced" end),
               "Replace All reported nothing"

        beat(1_500)
        {:ok, Map.put(context, :notes_path, path)}
      end

      then_ "the dismissed occurrence survived, which is the whole point", context do
        # notes.txt is OPEN, so it was edited through its buffer rather than
        # rewritten on disk — which is what keeps Undo working there. So the
        # buffer is where the result lives until someone saves.
        [notes] =
          Quillex.Buffer.list()
          |> Enum.filter(&(&1.name == "notes.txt"))

        {:ok, snapshot} = Quillex.Buffer.fetch(notes)
        content = Enum.join(snapshot.lines, "\n")

        assert content =~ "hello",
               "a dismissed match must be untouched by Replace All"

        assert content =~ "g'day",
               "the matches that were not dismissed should have been replaced"

        assert snapshot.ref.dirty?,
               "an open file replaced through its buffer should be dirty, not written"

        Probes.take_screenshot("60_demo_04_replaced")
        Quillex.RadixCache.ViewStore.close_project_search()
        beat(800)
        {:ok, context}
      end
    end

    scenario "Act IV — how it looks" do
      given_ "a fresh page to narrate on", context do
        {:ok, scratch} = Quillex.Buffer.new(%{name: "themes.txt", data: [""]})
        :ok = Quillex.Buffer.activate(scratch)
        beat(600)
        focus_editor()

        narrate([
          "Five themes, and each one paints the whole interface —",
          "the editor, the tabs, the menus and the sidebar together.",
          "",
          "A light buffer inside a dark sidebar reads as broken,",
          "not as a theme. Watch:"
        ])

        {:ok, context}
      end

      when_ "each theme is chosen in turn", context do
        for {id, _label} <- Palette.themes() do
          Quillex.RadixCache.ViewStore.set_theme(id)

          assert wait_until(fn -> root_state().theme == id end)
          assert wait_until(fn ->
                   child_state(:buffer_pane).colors.background == Palette.get(id).editor_bg
                 end),
                 "#{id} never reached the editor"

          beat(1_400)
          Probes.take_screenshot("60_demo_05_theme_#{id}")
        end

        {:ok, context}
      end

      then_ "every surface followed, and the default is where we started", context do
        Quillex.RadixCache.ViewStore.set_theme(Palette.default())
        assert wait_until(fn -> root_state().theme == Palette.default() end)
        beat(800)

        palette = Palette.get(Palette.default())
        assert child_state(:tab_bar).theme.background == palette.chrome_bg
        assert child_state(:icon_menu).theme.background == palette.chrome_bg
        assert child_state(:file_nav).theme.background == palette.pane_bg
        {:ok, context}
      end
    end

    scenario "Act V — and everything is written down" do
      given_ "the closing narration", context do
        focus_editor()

        narrate([
          "Every feature here is in a menu, and every shortcut",
          "is in Help → Keyboard Shortcuts. Nothing in Quillex",
          "is discoverable only by already knowing about it.",
          "",
          "That reference is generated from one registry, so a",
          "command cannot exist without appearing in it."
        ])

        {:ok, context}
      end

      when_ "the shortcut reference is opened", context do
        menu(:help, :shortcuts)
        assert wait_until(fn -> root_state().show_shortcuts end)
        beat(2_500)
        Probes.take_screenshot("60_demo_06_shortcuts")
        {:ok, context}
      end

      then_ "it lists every registered shortcut, grouped", context do
        lines = Quillex.Commands.shortcut_lines()

        for section <- Quillex.Commands.sections() do
          assert section in lines
        end

        registered = Quillex.Commands.all() |> Enum.reject(&is_nil(&1.shortcut))
        assert length(registered) >= 30

        for command <- registered do
          assert Enum.any?(lines, &String.contains?(&1, command.shortcut)),
                 "#{command.id} is registered but does not reach the reference"
        end

        Probes.send_keys("escape", [])
        beat(800)
        {:ok, context}
      end

      then_ "it signs off", context do
        focus_editor()

        narrate([
          "That is Quillex 1.0.",
          "",
          "Written in Elixir. Rendered by Scenic.",
          "Demonstrated, and tested, by itself."
        ])

        beat(2_500)
        Probes.take_screenshot("60_demo_07_end")

        assert Enum.at(active_buffer().lines, 0) == "That is Quillex 1.0."
        {:ok, context}
      end
    end
  end
end
