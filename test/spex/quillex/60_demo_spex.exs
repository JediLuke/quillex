defmodule Quillex.DemoSpex do
  @moduledoc """
  The demo. Every feature of Quillex 1.0, in the order you would meet them,
  narrated by the editor into its own buffer.

  Written to be *presented* — it explains what Quillex is and what it is for
  before it starts pressing keys, and it lingers on the ordinary editing
  everybody needs before reaching the parts that were interesting to build.

  Run it with `scripts/run_demo` and watch; `--fast` runs the same script as a
  regression test.

  It is both at once, deliberately: a showcase and the most complete
  integration test in the suite. **Every act asserts**, so it cannot play
  through a feature that is broken — and it has already earned that. Writing it
  found the syntax highlighter dying on an em dash, a superseded search
  publishing its results under the wrong query, and a click in empty space
  failing to focus the editor.

  ## The feature list

  Part of what 1.0 means is that the list below is the whole of it, so the demo
  walks all of it:

  - typing, undo and redo, indent and unindent
  - cursor: word-wise movement, line and document ends, page up and down,
    go-to-line with clamping, and the mouse — including clicks past the end of
    a line
  - selection: shift-arrows, double-click a word, select-all
  - clipboard: copy and paste against the system clipboard
  - files: opening, dirty tracking, and both halves of noticing an edit made
    underneath the editor — a clean buffer reloads, a dirty one is flagged
  - tabs, the file navigator, and the reusable preview tab
  - find in the buffer with F3, and across the project with dismissals and
    replace
  - reading code: structural syntax highlighting, folding, current line and
    column guides, word wrap
  - looking at it: five themes, editor text size, interface zoom
  - finding out: menus for everything, and a generated shortcut reference

  Two things it does NOT show, so that this list stays honest: dragging a tab
  to reorder it (covered by `38_tab_reorder_spex.exs` — a drag is hard to make
  legible at this pace), and `Ctrl+D` delete-line, which the buffer still
  implements but which has no key binding and no registry entry, so there is
  nothing to demonstrate.
  """
  use SexySpex
  @moduletag timeout: 1_800_000

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.AppReset
  alias Quillex.TestHelpers.SemanticHelpers
  alias Quillex.GUI.Palette
  import Quillex.TestHelpers.Integration, only: [ensure_editor_focused: 0]

  @demo_dir "/tmp/quillex_demo"

  # ── Pacing ────────────────────────────────────────────────────────────────

  defp speed, do: System.get_env("DEMO_SPEED", "watch")
  defp fast?, do: speed() == "fast"

  defp beat(ms), do: Process.sleep(if fast?(), do: max(div(ms, 8), 10), else: ms)

  # Narration types at about twice the speed of a person, which is quick enough
  # not to bore a room and slow enough to read along with.
  defp per_char_ms, do: if(fast?(), do: 0, else: 9)

  # ── Reading the editor ────────────────────────────────────────────────────

  defp root_state, do: :sys.get_state(Process.whereis(QuillEx.RootScene)).assigns.state

  defp child_state(id) do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, [pid | _]} = Scenic.Scene.child(root, id)
    :sys.get_state(pid, 30_000).assigns.state
  end

  defp active_buf, do: root_state().active_buf

  defp active_buffer do
    {:ok, snapshot} = Quillex.Buffer.fetch(active_buf())
    snapshot
  end

  defp text, do: Enum.join(active_buffer().lines, "\n")
  defp cursor, do: active_buffer().cursor
  defp selection, do: active_buffer().selection

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

  # Typed a character at a time, because a demo that pastes is a screenshot.
  defp type(string) do
    case per_char_ms() do
      0 ->
        Probes.send_text(string)

      ms ->
        for <<char::utf8 <- string>> do
          Probes.send_text(<<char::utf8>>)
          Process.sleep(ms)
        end
    end

    Process.sleep(60)
  end

  defp key(k, mods \\ []) do
    Probes.send_keys(k, mods)
    Process.sleep(if fast?(), do: 25, else: 90)
  end

  defp keys(k, mods, times), do: for(_ <- 1..times, do: key(k, mods))

  defp newline, do: key("enter")

  # The Go to Line prompt collects digits itself, as key events rather than
  # codepoints — it accepts only digits, so a full editable field would be more
  # machinery than the interaction deserves.
  defp digits(string), do: for(<<d <- string>>, do: key(<<d>>))

  defp focus_editor, do: ensure_editor_focused()

  defp select_all_and_delete do
    key("a", [:ctrl])
    key("backspace")
    Process.sleep(150)
  end

  # Choosing a toggle leaves the dropdown OPEN — which is right, so you can
  # flip two things without reopening the menu each time. It does mean a helper
  # that always clicks the icon first would CLOSE the menu it wants, and then
  # click a row that is no longer on screen. So: open it only if it is shut.
  #
  # Menus also need real time even in fast mode — a click on the icon while the
  # dropdown is still opening closes it again — so these sleeps have a floor
  # where everything else scales with the speed setting.
  defp menu(menu_id, item_id) do
    unless child_state(:icon_menu).active_menu == menu_id do
      Probes.click_element("icon_menu_#{menu_id}")
      Process.sleep(max(if(fast?(), do: 0, else: 500), 350))
    end

    Probes.click_element("icon_menu_#{menu_id}_#{item_id}")
    Process.sleep(max(if(fast?(), do: 0, else: 600), 400))
  end

  defp close_menus do
    key("escape")
    Process.sleep(200)
  end

  # The narration: clear the page, then write what is about to happen.
  #
  # And check that it arrived. Narration needs the keyboard, and most of what
  # follows drives the editor through its stores instead — so without this the
  # demo can lose focus, fall silent, and still play its remaining acts and
  # pass. It did exactly that once: the themes changed while nothing explained
  # them.
  defp narrate(lines) do
    lines = List.wrap(lines)
    switch_to_narration_page()
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

    beat(1_400)
  end

  # Narration always goes on its own page. It clears the buffer before it
  # types, so narrating into whatever happened to be active meant an act could
  # silently overwrite a file a later act depended on — Act V's explanation of
  # syntax highlighting once landed in notes.txt, and the project search two
  # acts later could no longer find the word it was looking for.
  @narration_page "demo.txt"

  defp switch_to_narration_page do
    buf =
      case Enum.filter(Quillex.Buffer.list(), &(&1.name == @narration_page)) do
        [existing | _] ->
          existing

        [] ->
          {:ok, new} = Quillex.Buffer.new(%{name: @narration_page, data: [""]})
          new
      end

    unless active_buf() && active_buf().uuid == buf.uuid do
      :ok = Quillex.Buffer.activate(buf)
      beat(400)
    end

    buf
  end

  # A page to work on: a fresh buffer, focused, holding exactly these lines.
  defp page(name, lines) do
    {:ok, buf} = Quillex.Buffer.new(%{name: name, data: lines})
    :ok = Quillex.Buffer.activate(buf)
    beat(500)
    focus_editor()
    buf
  end

  defp buffer_named(name) do
    [buf] = Enum.filter(Quillex.Buffer.list(), &(&1.name == name))
    buf
  end

  # ── Setup ─────────────────────────────────────────────────────────────────

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
        if name == "" do
          "hello, stranger"
        else
          "hello, " <> name
        end
      end

      def farewell(name) do
        "goodbye, " <> name
      end
    end
    """)

    File.write!(Path.join(@demo_dir, "lib/notes.txt"), """
    hello from a second file
    the demo searches for the word hello across both of these
    and replaces it, and shows you what it did not touch
    """)

    Quillex.RadixCache.ViewStore.set_file_nav_path(@demo_dir)
    Process.sleep(300)

    on_exit(fn ->
      Quillex.RadixCache.ViewStore.set_theme(Palette.default())
      Quillex.RadixCache.ViewStore.set_file_nav_path(File.cwd!())
      Process.sleep(200)
      File.rm_rf!(@demo_dir)
    end)

    :ok
  end

  # ══════════════════════════════════════════════════════════════════════════

  spex "Quillex, end to end",
    description: "Every feature of 1.0, narrated by the editor into its own buffer",
    tags: [:demo, :showcase, :integration] do
    # ────────────────────────────────────────────────────────────────────────
    scenario "Prologue — what this is" do
      given_ "an empty editor", context do
        focus_editor()
        select_all_and_delete()
        assert wait_until(fn -> active_buffer().lines == [""] end)
        {:ok, context}
      end

      when_ "it introduces itself", context do
        narrate([
          "This is Quillex: a text editor written in Elixir,",
          "drawn by Scenic, running as an OTP application.",
          "",
          "Everything you are about to see is being typed by the",
          "editor, into itself, by a test that asserts as it goes."
        ])

        beat(1_600)
        {:ok, context}
      end

      when_ "it explains what it is for", context do
        narrate([
          "Quillex is a gedit clone. That is the whole ambition:",
          "the ordinary editor a person already knows how to use,",
          "with nothing to learn and nothing to configure.",
          "",
          "It is also a reference implementation of an architecture.",
          "Every piece of state lives in a store and is published as",
          "a snapshot. The GUI holds nothing and can be killed at any",
          "moment. The editor is a view over an OTP backend, and the",
          "backend does not know a GUI exists."
        ])

        beat(1_600)
        {:ok, context}
      end

      then_ "it says what 1.0 means", context do
        narrate([
          "1.0 means the feature list is finished — not that the work",
          "is. What follows is all of it, in the order you would meet",
          "it. If something is missing from this demo, it is missing",
          "from Quillex."
        ])

        assert Enum.at(active_buffer().lines, 0) =~ "1.0 means"
        Probes.take_screenshot("60_demo_01_prologue")
        beat(1_800)
        {:ok, context}
      end
    end

    # ────────────────────────────────────────────────────────────────────────
    scenario "Act I — typing, and taking it back" do
      given_ "a page to type on", context do
        narrate([
          "Start with the part nobody notices until it is wrong:",
          "typing, and being able to take it back."
        ])

        page("editing.txt", [""])
        {:ok, context}
      end

      when_ "text is typed", context do
        type("The quick brown fox jumps over the lazy dog.")
        beat(800)

        assert wait_until(fn -> text() =~ "lazy dog" end), "typing did not reach the buffer"
        {:ok, context}
      end

      then_ "undo takes it back one edit at a time, and redo returns it", context do
        undo_until(fn -> not (text() =~ "lazy") end)
        beat(700)
        refute text() =~ "lazy", "undo did not remove the typed text"

        redo_until(fn -> text() =~ "lazy dog" end)
        beat(700)
        assert text() =~ "lazy dog", "redo did not restore it"
        {:ok, context}
      end

      then_ "Tab indents, and Shift+Tab takes the indent back", context do
        key("home")
        key("tab")
        beat(600)
        assert wait_until(fn -> text() =~ ~r/^\t/ end), "Tab did not indent"

        key("tab", [:shift])
        beat(600)
        assert wait_until(fn -> not (text() =~ ~r/^\t/) end), "Shift+Tab did not unindent"
        {:ok, context}
      end
    end

    # ────────────────────────────────────────────────────────────────────────
    scenario "Act II — moving around" do
      given_ "a page with several lines", context do
        narrate([
          "Moving around. Arrows a character at a time, but also by",
          "word, to the ends of a line, to the ends of the document,",
          "a screen at a time, and straight to a line number."
        ])

        page("moving.txt", [
          "alpha beta gamma delta",
          "the second line of the file",
          "a third line here",
          "and a fourth"
        ])

        {:ok, _} = Quillex.Buffer.dispatch(active_buf(), [{:set_cursor, {1, 1}}])
        assert wait_until(fn -> cursor() == {1, 1} end)
        {:ok, context}
      end

      when_ "the cursor walks by word", context do
        keys("right", [:ctrl], 3)
        beat(800)

        assert {1, col} = cursor()
        assert col > 10, "three word jumps should be well into the line, got column #{col}"
        {:ok, context}
      end

      then_ "End and Home reach the ends of the line", context do
        key("end")
        beat(600)
        assert cursor() == {1, String.length("alpha beta gamma delta") + 1}

        key("home")
        beat(600)
        assert cursor() == {1, 1}
        {:ok, context}
      end

      then_ "Ctrl+End and Ctrl+Home reach the ends of the document", context do
        key("end", [:ctrl])
        beat(700)
        assert wait_until(fn -> match?({4, _}, cursor()) end), "Ctrl+End should reach line 4"

        key("home", [:ctrl])
        beat(700)
        assert wait_until(fn -> cursor() == {1, 1} end), "Ctrl+Home should return to the start"
        {:ok, context}
      end

      then_ "Page Down and Page Up move a screenful at a time", context do
        long = page("paging.txt", Enum.map(1..300, &"line #{&1}"))
        {:ok, _} = Quillex.Buffer.dispatch(long, [{:set_cursor, {1, 1}}])
        assert wait_until(fn -> cursor() == {1, 1} end)
        focus_editor()

        key("page_down")
        beat(800)

        assert {down_line, _} = cursor()
        assert down_line > 10, "Page Down should move a screenful, got line #{down_line}"

        key("page_up")
        beat(800)

        assert wait_until(fn -> elem(cursor(), 0) < down_line end),
               "Page Up should move back up from line #{down_line}, got #{inspect(cursor())}"

        :ok = Quillex.Buffer.activate(buffer_named("moving.txt"))
        beat(500)
        focus_editor()
        {:ok, context}
      end

      then_ "Go to Line jumps, and clamps rather than refusing", context do
        key("g", [:ctrl])
        beat(600)
        assert root_state().show_goto_line, "Ctrl+G should open the prompt"

        digits("3")
        key("enter")
        beat(700)
        assert wait_until(fn -> match?({3, _}, cursor()) end), "Ctrl+G did not jump to line 3"

        # 999999 is what people type when they mean "the end", so that is what
        # it means here. Refusing would be technically correct and useless.
        key("g", [:ctrl])
        beat(500)
        digits("999999")
        key("enter")
        beat(800)

        last = length(active_buffer().lines)

        assert wait_until(fn -> match?({^last, _}, cursor()) end),
               "Go to Line should clamp to the last line rather than refuse"

        {:ok, context}
      end

      then_ "and the mouse puts the cursor where you point, including past the text",
            context do
        %{x: fx, y: fy, width: fw} = SemanticHelpers.get_buffer_frame()

        # On line 2's text.
        Probes.click(fx + 120, fy + 16 + 24)
        beat(800)
        assert wait_until(fn -> match?({2, _}, cursor()) end), "a click should move the cursor"

        # And far to the right of line 4, which is short: past the end of a
        # line means the end of that line.
        Probes.click(fx + trunc(fw * 0.75), fy + 16 + 3 * 24)
        beat(800)

        assert wait_until(fn -> cursor() == {4, String.length("and a fourth") + 1} end),
               "clicking past the end of line 4 should land at its end, got #{inspect(cursor())}"

        Probes.take_screenshot("60_demo_02_moving")
        {:ok, context}
      end
    end

    # ────────────────────────────────────────────────────────────────────────
    scenario "Act III — selecting, and the clipboard" do
      given_ "a page to select in", context do
        narrate([
          "Selecting: hold Shift while you move, or double-click a",
          "word, or drag across the text.",
          "",
          "Then cut, copy and paste — against the system clipboard,",
          "so it works with everything else on your desktop."
        ])

        page("selecting.txt", ["copy this line", "leave this one alone"])
        {:ok, _} = Quillex.Buffer.dispatch(active_buf(), [{:set_cursor, {1, 1}}])
        assert wait_until(fn -> cursor() == {1, 1} end)
        {:ok, context}
      end

      when_ "Shift and the arrows select as the cursor moves", context do
        keys("right", [:shift], 4)
        beat(800)

        assert wait_until(fn -> selection() != nil end), "Shift+Right should start a selection"
        assert %{start: {1, 1}, end: {1, 5}} = selection()
        {:ok, context}
      end

      then_ "double-clicking selects the word under the pointer", context do
        %{x: fx, y: fy} = SemanticHelpers.get_buffer_frame()

        Probes.click(fx + 60, fy + 16)
        Process.sleep(80)
        Probes.click(fx + 60, fy + 16)
        beat(800)

        assert wait_until(fn ->
                 case selection() do
                   %{start: {1, s}, end: {1, e}} -> e > s
                   _ -> false
                 end
               end),
               "double-click should select a word, got #{inspect(selection())}"

        {:ok, context}
      end

      then_ "Select All takes the whole document", context do
        key("a", [:ctrl])
        beat(700)

        assert wait_until(fn -> selection() != nil end), "Ctrl+A should select everything"
        assert %{start: {1, 1}} = selection()
        {:ok, context}
      end

      then_ "and copy and paste carry text through the system clipboard", context do
        {:ok, _} = Quillex.Buffer.dispatch(active_buf(), [{:set_cursor, {1, 1}}])
        assert wait_until(fn -> cursor() == {1, 1} end)

        # Shift+Arrows, not Shift+End: Home and End deliberately move the
        # cursor without extending a selection, and "Shift+Arrows" is what the
        # shortcut registry claims. The demo shows what is actually there.
        keys("right", [:shift], String.length("copy this line"))
        beat(600)
        key("c", [:ctrl])
        beat(800)

        assert wait_until(fn -> selection() != nil end),
               "Shift+Right should have selected the line before copying"

        key("end", [:ctrl])
        newline()
        key("v", [:ctrl])
        beat(900)

        assert wait_until(fn -> length(active_buffer().lines) == 3 end),
               "paste should have added a line, got #{inspect(active_buffer().lines)}"

        assert List.last(active_buffer().lines) == "copy this line",
               "paste should reproduce the copied line, got #{inspect(active_buffer().lines)}"

        Probes.take_screenshot("60_demo_03_clipboard")
        {:ok, context}
      end
    end

    # ────────────────────────────────────────────────────────────────────────
    scenario "Act IV — files, tabs and the project" do
      given_ "the narration sets the scene", context do
        narrate([
          "Files open in tabs. An asterisk means unsaved; drag a tab",
          "to reorder it. The navigator on the left is the project —",
          "click to open a file, drag to move one.",
          "",
          "Opening two files now."
        ])

        {:ok, context}
      end

      when_ "the navigator is opened and two files are opened", context do
        Quillex.RadixCache.ViewStore.open_file_nav()
        assert wait_until(fn -> root_state().show_file_nav end)
        beat(1_200)

        {:ok, _} = Quillex.API.FileAPI.open(Path.join(@demo_dir, "lib/kernel.ex"))
        beat(1_300)
        {:ok, _} = Quillex.API.FileAPI.open(Path.join(@demo_dir, "lib/notes.txt"))
        beat(1_300)
        {:ok, context}
      end

      then_ "both are open, and the editor tracks which one is dirty", context do
        names = Enum.map(root_state().buffers, & &1.name)
        assert "kernel.ex" in names
        assert "notes.txt" in names

        notes = buffer_named("notes.txt")
        refute notes.dirty?, "a freshly opened file should not be dirty"

        :ok = Quillex.Buffer.activate(notes)
        beat(700)
        focus_editor()
        key("end", [:ctrl])
        type(" ...edited")
        beat(800)

        assert wait_until(fn ->
                 Enum.any?(root_state().buffers, &(&1.name == "notes.txt" and &1.dirty?))
               end),
               "typing should mark the buffer dirty"

        Probes.take_screenshot("60_demo_04_tabs")
        {:ok, context}
      end

      then_ "a file changed underneath a CLEAN buffer is quietly reloaded", context do
        path = Path.join(@demo_dir, "lib/kernel.ex")
        :ok = Quillex.Buffer.activate(buffer_named("kernel.ex"))
        beat(700)
        refute buffer_named("kernel.ex").dirty?, "kernel.ex should still be clean here"

        File.write!(path, File.read!(path) <> "\n# changed on disk by someone else\n")
        Quillex.Files.ExternalFileSync.poll_now()

        assert wait_until(
                 fn -> text() =~ "changed on disk by someone else" end,
                 8_000
               ),
               "an external edit to a clean buffer should be picked up"

        assert (root_state().status_message || "") =~ "Reloaded",
               "and it should say so, rather than changing the document in silence"

        beat(1_600)
        {:ok, context}
      end

      then_ "but a file changed under UNSAVED work is flagged, not overwritten", context do
        path = Path.join(@demo_dir, "lib/notes.txt")
        :ok = Quillex.Buffer.activate(buffer_named("notes.txt"))
        beat(700)

        assert buffer_named("notes.txt").dirty?,
               "notes.txt should still hold the unsaved edit from a moment ago"

        File.write!(path, File.read!(path) <> "\nand someone edited this one too\n")
        Quillex.Files.ExternalFileSync.poll_now()

        assert wait_until(
                 fn ->
                   Enum.any?(
                     root_state().buffers,
                     &(&1.name == "notes.txt" and &1.external_change == :modified)
                   )
                 end,
                 8_000
               ),
               "an external edit to a DIRTY buffer is a conflict, and must be flagged"

        assert text() =~ "...edited",
               "the unsaved work must be preserved, not overwritten"

        Probes.take_screenshot("60_demo_05_external_change")
        beat(1_600)
        {:ok, context}
      end
    end

    # ────────────────────────────────────────────────────────────────────────
    scenario "Act V — reading code" do
      given_ "a source file on screen", context do
        narrate([
          "Reading code. Syntax highlighting here is structural:",
          "weight, slant and underline rather than colour, so it reads",
          "the same for every kind of colour vision — and needs no",
          "palette of its own.",
          "",
          "Folding collapses a block. Guides mark the line and column",
          "you are on. Word wrap keeps a long line on screen."
        ])

        :ok = Quillex.Buffer.activate(buffer_named("kernel.ex"))
        beat(900)
        focus_editor()
        {:ok, context}
      end

      then_ "highlighting marks the classes by weight and slant, never colour", context do
        styles = Quillex.GUI.Theme.highlight_styles()

        assert styles.keyword.font == :ibm_plex_mono_bold
        assert styles.definition.font == :ibm_plex_mono_semibold
        assert styles.comment.font == :ibm_plex_mono_light_italic
        assert styles.string.underline

        refute Enum.any?(Map.values(styles), &Map.has_key?(&1, :fill)),
               "structural highlighting must not reach for colour"

        assert child_state(:buffer_pane).highlight_styles != %{},
               "the pane should be highlighting"

        Probes.take_screenshot("60_demo_05_syntax")
        beat(1_400)
        {:ok, context}
      end

      then_ "the view toggles change what is drawn", context do
        for id <- ["current_line_highlight", "current_column_highlight"] do
          key = if id == "current_line_highlight", do: :highlight_current_line, else: :highlight_current_column
          before = Map.get(root_state(), key)
          menu(:view, id)

          assert wait_until(fn -> Map.get(root_state(), key) != before end),
                 "View → #{id} did not take effect"

          beat(1_000)
        end

        close_menus()
        beat(700)
        Probes.take_screenshot("60_demo_06_guides")
        {:ok, context}
      end

      then_ "folding collapses the file to its shape", context do
        Quillex.RadixCache.ViewStore.set_fold_level(1)
        beat(1_600)
        assert root_state().fold_level == 1

        menu(:view, :unfold_all)
        beat(1_000)
        {:ok, context}
      end

      then_ "and word wrap keeps a long line on screen", context do
        page("wrapping.txt", [Enum.map_join(1..70, " ", &"word#{&1}")])

        refute root_state().word_wrap
        menu(:view, "word_wrap")

        assert wait_until(fn -> root_state().word_wrap end), "Word Wrap did not turn on"
        beat(1_300)
        assert child_state(:buffer_pane).wrap_mode == :word

        # Down moves by VISUAL row under wrap, not to the next numbered line.
        {:ok, _} = Quillex.Buffer.dispatch(active_buf(), [{:set_cursor, {1, 1}}])
        assert wait_until(fn -> cursor() == {1, 1} end)
        focus_editor()
        key("down")
        beat(800)

        assert {1, col} = cursor()

        assert col > 1,
               "under wrap, Down should move along the wrapped line, got #{inspect(cursor())}"

        Probes.take_screenshot("60_demo_07_wrap")
        menu(:view, "word_wrap")
        assert wait_until(fn -> not root_state().word_wrap end)
        {:ok, context}
      end
    end

    # ────────────────────────────────────────────────────────────────────────
    scenario "Act VI — finding things" do
      given_ "a narrated introduction", context do
        page("finding.txt", [""])

        narrate([
          "Ctrl+F finds text in this buffer, and Ctrl+H replaces it.",
          "",
          "Ctrl+Shift+F is a different thing: the whole project, in a",
          "pane with its own query, its own replacement and its own",
          "exclude field. Results are grouped by file, with the match",
          "marked inside the line.",
          "",
          "Dismiss a match and no replace can reach it. That is what",
          "makes Replace All reviewable rather than an act of faith."
        ])

        {:ok, context}
      end

      when_ "Ctrl+F finds a word in this buffer, and F3 walks the matches", context do
        page("in-buffer-find.txt", [
          "the first needle is here",
          "nothing on this line",
          "and a second needle down here"
        ])

        {:ok, _} = Quillex.Buffer.dispatch(active_buf(), [{:set_cursor, {1, 1}}])
        assert wait_until(fn -> cursor() == {1, 1} end)

        key("f", [:ctrl])
        beat(800)
        assert root_state().show_search_bar, "Ctrl+F should open the find bar"

        type("needle")
        beat(1_000)

        assert wait_until(fn -> match?({1, _}, cursor()) end, 6_000),
               "the first match is on line 1, got #{inspect(cursor())}"

        key("escape")
        beat(500)
        focus_editor()
        key("f3")
        beat(900)

        assert wait_until(fn -> match?({3, _}, cursor()) end, 6_000),
               "F3 should move to the next match on line 3, got #{inspect(cursor())}"

        Probes.take_screenshot("60_demo_08_find")
        beat(900)
        {:ok, context}
      end

      when_ "the project search runs", context do
        key("f", [:ctrl, :shift])
        beat(1_100)
        assert root_state().show_project_search, "Ctrl+Shift+F should open the pane"

        type("hello")

        # Typing schedules one debounced search per character; await_idle is
        # the only moment the results are known to belong to the whole query
        # rather than a prefix of it.
        :ok = Quillex.RadixCache.ProjectSearchStore.await_idle()

        assert wait_until(fn ->
                 match?(%{status: {:done, _, _, _}}, root_state().project_search)
               end),
               "the project search never finished"

        beat(1_700)
        {:ok, context}
      end

      then_ "it found the word in both files", context do
        %{files: files} = root_state().project_search
        names = Enum.map(files, fn {path, _} -> Path.basename(path) end)

        {:ok, notes} = Quillex.Buffer.fetch(buffer_named("notes.txt"))

        assert "kernel.ex" in names
        assert "notes.txt" in names,
               "found #{inspect(names)}; query=#{inspect(root_state().project_search.query)} " <>
                 "notes buffer=#{inspect(notes.lines)} dirty=#{notes.ref.dirty?}"

        Probes.take_screenshot("60_demo_08_project_search")
        {:ok, context}
      end

      then_ "clicking a result opens it in one reusable preview tab", context do
        %{files: files} = root_state().project_search
        {kernel_path, [kernel_match | _]} =
          Enum.find(files, fn {p, _} -> Path.basename(p) == "kernel.ex" end)

        tabs_before = length(root_state().buffers)

        Probes.click_element(
          "search_pane_match_#{kernel_match.line}_#{kernel_match.col}_#{kernel_path}"
        )

        assert wait_until(fn -> root_state().active_buf.name == "kernel.ex" end),
               "clicking a result should open that file"

        assert root_state().preview_buf_uuid == root_state().active_buf.uuid,
               "a result opens into the preview slot, drawn in italics"

        beat(1_400)

        # The next result replaces it rather than adding a tab — walking thirty
        # results leaves one tab, not thirty.
        {notes_path, [notes_match | _]} =
          Enum.find(files, fn {p, _} -> Path.basename(p) == "notes.txt" end)

        Probes.click_element(
          "search_pane_match_#{notes_match.line}_#{notes_match.col}_#{notes_path}"
        )

        assert wait_until(fn -> root_state().active_buf.name == "notes.txt" end)

        assert length(root_state().buffers) <= tabs_before + 1,
               "the preview tab should be reused, not accumulated"

        Probes.take_screenshot("60_demo_09_preview_tab")
        beat(1_200)
        {:ok, context}
      end

      then_ "a match is dismissed, and then everything else is replaced", context do
        %{files: files} = root_state().project_search
        {path, [match | _]} = Enum.find(files, fn {p, _} -> Path.basename(p) == "notes.txt" end)

        before = Enum.sum(Enum.map(files, fn {_p, ms} -> length(ms) end))

        Probes.click_element("search_pane_dismiss_match_#{match.line}_#{match.col}_#{path}")

        assert wait_until(fn ->
                 %{files: after_files} = root_state().project_search
                 Enum.sum(Enum.map(after_files, fn {_p, ms} -> length(ms) end)) == before - 1
               end),
               "dismissing a match should remove it from the results"

        beat(1_500)

        Probes.click_element("search_pane_field_replace")
        beat(600)
        type("g'day")
        beat(800)
        Probes.click_element("search_pane_replace_all")

        assert wait_until(fn -> (root_state().status_message || "") =~ "Replaced" end),
               "Replace All reported nothing"

        beat(1_700)
        {:ok, context}
      end

      then_ "the dismissed occurrence survived, which is the whole point", context do
        {:ok, snapshot} = Quillex.Buffer.fetch(buffer_named("notes.txt"))
        content = Enum.join(snapshot.lines, "\n")

        assert content =~ "hello", "a dismissed match must be untouched by Replace All"
        assert content =~ "g'day", "the matches that were not dismissed should have been replaced"

        assert snapshot.ref.dirty?,
               "an open file is replaced through its buffer, so Undo still works there"

        Probes.take_screenshot("60_demo_09_replaced")
        Quillex.RadixCache.ViewStore.close_project_search()
        beat(1_000)
        {:ok, context}
      end
    end

    # ────────────────────────────────────────────────────────────────────────
    scenario "Act VII — how it looks" do
      given_ "a fresh page to narrate on", context do
        page("themes.txt", [""])

        narrate([
          "Five themes. Each one paints the whole interface — the",
          "editor, the tabs, the menus and the sidebar together —",
          "because a light buffer inside a dark sidebar reads as",
          "broken rather than as a theme.",
          "",
          "Editor text size and interface scale move independently,",
          "so you can have large text in a normal-sized window."
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

          beat(1_600)
          Probes.take_screenshot("60_demo_10_theme_#{id}")
        end

        {:ok, context}
      end

      then_ "every surface followed", context do
        Quillex.RadixCache.ViewStore.set_theme(Palette.default())
        assert wait_until(fn -> root_state().theme == Palette.default() end)
        beat(900)

        palette = Palette.get(Palette.default())
        assert child_state(:tab_bar).theme.background == palette.chrome_bg
        assert child_state(:icon_menu).theme.background == palette.chrome_bg
        assert child_state(:file_nav).theme.background == palette.pane_bg
        {:ok, context}
      end

      then_ "and text size and interface scale move independently", context do
        Quillex.RadixCache.ViewStore.set_text_size(30)
        assert wait_until(fn -> root_state().text_size == 30 end)
        beat(1_200)

        Quillex.RadixCache.ViewStore.set_chrome_zoom(120)
        assert wait_until(fn -> root_state().chrome_zoom == 120 end)
        beat(1_200)
        Probes.take_screenshot("60_demo_11_sizing")

        Quillex.RadixCache.ViewStore.set_text_size(24)
        Quillex.RadixCache.ViewStore.set_chrome_zoom(100)
        assert wait_until(fn -> root_state().chrome_zoom == 100 end)
        beat(800)
        {:ok, context}
      end
    end

    # ────────────────────────────────────────────────────────────────────────
    scenario "Epilogue — and everything is written down" do
      given_ "the closing narration", context do
        page("closing.txt", [""])

        narrate([
          "Every feature you have seen is in a menu, and every",
          "shortcut is in Help, Keyboard Shortcuts. Nothing in Quillex",
          "is discoverable only by already knowing about it.",
          "",
          "That reference is generated from one registry, so a command",
          "cannot exist without appearing in it."
        ])

        {:ok, context}
      end

      when_ "the shortcut reference is opened", context do
        menu(:help, :shortcuts)
        assert wait_until(fn -> root_state().show_shortcuts end)
        beat(3_500)
        Probes.take_screenshot("60_demo_12_shortcuts")
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

        key("escape")
        beat(900)
        {:ok, context}
      end

      then_ "it signs off", context do
        page("closing.txt", [""])

        narrate([
          "That is Quillex 1.0.",
          "",
          "Written in Elixir. Rendered by Scenic. A GUI over an OTP",
          "backend, with a hard line between them.",
          "",
          "Demonstrated, and tested, by itself."
        ])

        beat(3_500)
        Probes.take_screenshot("60_demo_13_end")

        assert Enum.at(active_buffer().lines, 0) == "That is Quillex 1.0."
        {:ok, context}
      end
    end
  end

  # ── Undo/redo helpers ─────────────────────────────────────────────────────
  #
  # Undo is per edit and typing is per character, so unwinding a phrase takes
  # several presses. That is what it looks like to a user, so that is what the
  # demo shows — pressing until the condition holds rather than assuming a
  # granularity.

  defp undo_until(done?), do: press_until("z", [:ctrl], done?)
  defp redo_until(done?), do: press_until("z", [:ctrl, :shift], done?)

  defp press_until(k, mods, done?, remaining \\ 120) do
    cond do
      done?.() ->
        :ok

      remaining == 0 ->
        :ok

      true ->
        Probes.send_keys(k, mods)
        Process.sleep(if fast?(), do: 10, else: 26)
        press_until(k, mods, done?, remaining - 1)
    end
  end
end
