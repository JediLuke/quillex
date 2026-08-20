defmodule Quillex.DemoSpex do
  @moduledoc """
  The demo. Every feature of Quillex 1.0, in the order you would meet them,
  narrated by the editor into its own buffer.

  Written to be *presented* — it explains what Quillex is and what it is for
  before it starts pressing keys, and it lingers on the ordinary editing
  everybody needs before reaching the parts that were interesting to build.

  Run it with `scripts/run_demo` and watch; `--fast` runs the same script as a
  regression test.

  It is paced to be *watched*, which means it is slow: a quarter of an hour,
  most of it deliberate pauses on something that just changed. An audience
  needs several seconds to find the thing that moved before they can
  understand it; the test needs none, which is what `--fast` is for.

  It is both at once, deliberately: a showcase and the most complete
  integration test in the suite. **Every act asserts**, so it cannot play
  through a feature that is broken — and it has already earned that. Writing it
  found the syntax highlighter dying on an em dash, a superseded search
  publishing its results under the wrong query, and a click in empty space
  failing to focus the editor.

  ## The feature list

  Part of what 1.0 means is that the list below is the whole of it, so the demo
  walks all of it:

  - typing, undo and redo, indent and unindent, delete-line
  - cursor: word-wise movement, line and document ends, page up and down,
    go-to-line with clamping, and the mouse — including clicks past the end of
    a line
  - selection: Shift with any movement key, double-click a word, select-all
  - clipboard: copy and paste against the system clipboard
  - files: opening, dirty tracking, and both halves of noticing an edit made
    underneath the editor — a clean buffer reloads, a dirty one is flagged
  - tabs, the file navigator, and the reusable preview tab
  - find in the buffer with F3, and across the project with dismissals and
    replace
  - reading code: structural syntax highlighting, folding, current line and
    column guides, word wrap
  - the window itself: wheel scrolling, dragging the scrollbar thumb, and a
    sidebar divider that both resizes and — dragged far enough — closes
  - looking at it: five themes, editor text size, interface zoom
  - finding out: menus for everything, and a generated shortcut reference

  One thing it does NOT show, so that this list stays honest: dragging a tab to
  reorder it, which is covered by `38_tab_reorder_spex.exs` — a drag is hard to
  make legible at this pace.
  """
  use SexySpex
  @moduletag timeout: 1_800_000

  # The chrome above the editor. The divider's grab handle is placed relative
  # to the content BELOW it.
  @top_bar_height 35

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.AppReset
  alias Quillex.TestHelpers.SemanticHelpers
  alias Quillex.GUI.Palette
  import Quillex.TestHelpers.Integration, only: [ensure_editor_focused: 0, buffer_pane_frame: 0]

  @demo_dir "/tmp/quillex_demo"

  # ── Pacing ────────────────────────────────────────────────────────────────

  defp speed, do: System.get_env("DEMO_SPEED", "watch")
  defp fast?, do: speed() == "fast"

  defp beat(ms), do: Process.sleep(if fast?(), do: max(div(ms, 8), 10), else: ms)

  # A deliberate pause on something that just changed, so a room has time to
  # see it. This is the difference between demonstrating a feature and merely
  # exercising it — an audience needs several seconds to FIND the thing that
  # moved before they can understand it, and the test needs none.
  #
  # Watched, these run half again as long as they read on the page. The demo
  # was paced by someone who already knew where to look.
  defp dwell(ms), do: beat(if fast?(), do: ms, else: round(ms * 1.5))

  # Typing speed. A fast human types four or five characters a second; this is
  # quicker than that, because the room is reading rather than watching the
  # keystrokes — but nothing like the old 9ms, which put a paragraph on screen
  # faster than anyone could start reading it.
  defp per_char_ms, do: if(fast?(), do: 0, else: Process.get(:demo_pace, 42))

  # The opening is slower still: that is when a room reads most closely, and
  # when nobody yet knows what they are looking at.
  defp pace(:slow), do: Process.put(:demo_pace, 68)
  defp pace(:normal), do: Process.put(:demo_pace, 42)

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

  # Keystrokes that MOVE something need to be seen moving. At 90ms a run of
  # arrow keys was a blur; at 200 you can follow the cursor.
  defp key(k, mods \\ []) do
    Probes.send_keys(k, mods)
    Process.sleep(if fast?(), do: 25, else: 200)
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

    # The narration types its own leading spaces, and auto-indent would add the
    # previous line's on top of them — so a bullet list walks steadily right
    # across the screen. Off while narrating; the demo turns it back on and
    # shows it deliberately.
    Quillex.RadixCache.ViewStore.set_auto_indent(false)
    Process.sleep(120)

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

    Quillex.RadixCache.ViewStore.set_auto_indent(true)
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

  # Narration that introduces something happening on ANOTHER page: say it, let
  # it land, then go back to whatever was showing so the demonstration follows
  # immediately rather than after a buffer switch.
  defp narrate_aside(lines) do
    previous = active_buf()
    narrate(lines)
    dwell(3_000)

    if previous && previous.name != @narration_page do
      :ok = Quillex.Buffer.activate(previous)
      beat(600)
      focus_editor()
    end

    :ok
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
        pace(:slow)
        focus_editor()
        select_all_and_delete()
        assert wait_until(fn -> active_buffer().lines == [""] end)
        {:ok, context}
      end

      when_ "it introduces itself", context do
        narrate([
          "This is Quillex.",
          "",
          "A text editor, written in Elixir, drawn by Scenic,",
          "running as an OTP application.",
          "",
          "Everything you are about to see is being typed by the",
          "editor, into itself, by a test that asserts as it goes."
        ])

        dwell(3_500)
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
          "a snapshot. The GUI holds nothing, and can be killed at",
          "any moment. The backend does not know a GUI exists."
        ])

        dwell(4_000)
        {:ok, context}
      end

      then_ "it says what you are about to see", context do
        narrate([
          "1.0 means the feature list is finished — not the work.",
          "",
          "Here is the tour:",
          "",
          "   1.  the ordinary editing everybody needs",
          "   2.  buffers, tabs, and the project navigator",
          "   3.  finding things — here, and across the project",
          "   4.  reading code: highlighting and folding",
          "   5.  the window itself: scrollbars, panes, dividers",
          "   6.  making it yours: text size, tab stops, themes",
          "",
          "If something is missing from this tour, it is missing",
          "from Quillex. Read this list and you have the claims,",
          "whether or not you stay for the proof."
        ])

        assert Enum.at(active_buffer().lines, 0) =~ "1.0 means"
        Probes.take_screenshot("60_demo_01_prologue")
        dwell(5_500)
        pace(:normal)
        {:ok, context}
      end
    end

    # ════════════════════════════════════════════════════════════════════════
    # 1. THE ORDINARY EDITING
    # ════════════════════════════════════════════════════════════════════════

    scenario "Act I — the basics, told first" do
      given_ "the list of what an editor has to get right", context do
        narrate([
          "First, all the usual things. Quillex has:",
          "",
          "   *  typing, undo and redo",
          "   *  delete a line, indent and unindent",
          "   *  select with the keyboard or the mouse",
          "   *  cut, copy and paste, with the system clipboard",
          "   *  move by word, by line, by page, or to a line number",
          "",
          "Let us go through them."
        ])

        dwell(5_000)
        {:ok, context}
      end

      when_ "a new buffer is made and typed into", context do
        narrate(["Ctrl+N makes a new buffer. Then you type into it."])
        dwell(2_000)

        page("editing.txt", [""])
        type("The quick brown fox jumps over the lazy dog.")
        dwell(2_500)

        assert wait_until(fn -> text() =~ "lazy dog" end), "typing did not reach the buffer"
        {:ok, context}
      end

      then_ "undo takes it back one edit at a time, and redo returns it", context do
        undo_until(fn -> not (text() =~ "lazy") end)
        dwell(2_500)
        refute text() =~ "lazy", "undo did not remove the typed text"

        redo_until(fn -> text() =~ "lazy dog" end)
        dwell(2_500)
        assert text() =~ "lazy dog", "redo did not restore it"
        {:ok, context}
      end

      then_ "Ctrl+D removes a whole line — and undo brings it back", context do
        narrate([
          "Ctrl+D deletes the line the cursor is on.",
          "",
          "And because every edit goes through one undo stack,",
          "Ctrl+Z brings it straight back."
        ])

        dwell(2_500)

        # page/2 focuses, and focusing is a CLICK — which moves the cursor. So
        # position the cursor after focusing, never before.
        page("deleting.txt", ["keep this one", "delete this one", "and keep this"])
        {:ok, _} = Quillex.Buffer.dispatch(active_buf(), [{:set_cursor, {2, 1}}])
        assert wait_until(fn -> cursor() == {2, 1} end)
        dwell(2_500)

        key("d", [:ctrl])

        assert wait_until(fn -> active_buffer().lines == ["keep this one", "and keep this"] end),
               "Ctrl+D should remove line 2, got #{inspect(active_buffer().lines)}"

        dwell(3_000)

        key("z", [:ctrl])

        assert wait_until(fn ->
                 active_buffer().lines == ["keep this one", "delete this one", "and keep this"]
               end),
               "undo should bring the deleted line back, got #{inspect(active_buffer().lines)}"

        dwell(3_000)
        Probes.take_screenshot("60_demo_02_delete_line")
        {:ok, context}
      end

      then_ "Tab indents, and Shift+Tab takes the indent back", context do
        focus_editor()
        {:ok, _} = Quillex.Buffer.dispatch(active_buf(), [{:set_cursor, {1, 1}}])
        assert wait_until(fn -> cursor() == {1, 1} end)

        key("tab")
        dwell(2_000)
        assert wait_until(fn -> text() =~ ~r/^\t/ end), "Tab did not indent"

        key("tab", [:shift])
        dwell(2_000)
        assert wait_until(fn -> not (text() =~ ~r/^\t/) end), "Shift+Tab did not unindent"
        {:ok, context}
      end
    end

    # ────────────────────────────────────────────────────────────────────────
    scenario "Act II — moving around" do
      given_ "a page with several lines", context do
        narrate([
          "Moving around. Arrows a character at a time — but also",
          "by word with Ctrl, to the ends of a line with Home and",
          "End, to the ends of the file with Ctrl+Home and Ctrl+End,",
          "a screen at a time with Page Up and Page Down, and",
          "straight to a line number with Ctrl+G."
        ])

        dwell(4_000)

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
        dwell(2_500)

        assert {1, col} = cursor()
        assert col > 10, "three word jumps should be well into the line, got column #{col}"
        {:ok, context}
      end

      then_ "End and Home reach the ends of the line", context do
        key("end")
        dwell(1_800)
        assert cursor() == {1, String.length("alpha beta gamma delta") + 1}

        key("home")
        dwell(1_800)
        assert cursor() == {1, 1}
        {:ok, context}
      end

      then_ "Ctrl+End and Ctrl+Home reach the ends of the document", context do
        key("end", [:ctrl])
        dwell(2_000)
        assert wait_until(fn -> match?({4, _}, cursor()) end), "Ctrl+End should reach line 4"

        key("home", [:ctrl])
        dwell(2_000)
        assert wait_until(fn -> cursor() == {1, 1} end), "Ctrl+Home should return to the start"
        {:ok, context}
      end

      then_ "Page Down and Page Up move a screenful at a time", context do
        long = page("paging.txt", Enum.map(1..300, &"line #{&1}"))
        focus_editor()
        {:ok, _} = Quillex.Buffer.dispatch(long, [{:set_cursor, {1, 1}}])
        assert wait_until(fn -> cursor() == {1, 1} end)
        dwell(1_800)

        key("page_down")
        dwell(2_200)

        assert {down_line, _} = cursor()
        assert down_line > 10, "Page Down should move a screenful, got line #{down_line}"

        key("page_down")
        dwell(2_200)

        key("page_up")
        dwell(2_200)

        assert wait_until(fn -> elem(cursor(), 0) < down_line * 2 end),
               "Page Up should move back up, got #{inspect(cursor())}"

        {:ok, context}
      end

      then_ "Go to Line jumps, and clamps rather than refusing", context do
        narrate(["Ctrl+G goes straight to a line number."])
        dwell(2_000)

        :ok = Quillex.Buffer.activate(buffer_named("paging.txt"))
        beat(600)
        focus_editor()

        key("g", [:ctrl])
        dwell(1_500)
        assert root_state().show_goto_line, "Ctrl+G should open the prompt"

        digits("150")
        dwell(1_500)
        key("enter")
        dwell(2_500)
        assert wait_until(fn -> match?({150, _}, cursor()) end), "Ctrl+G did not jump to line 150"

        narrate([
          "And if you ask for a line past the end, it takes you to",
          "the end — because 999999 is what people type when they",
          "mean 'the bottom'. Refusing would be correct and useless."
        ])

        dwell(3_000)

        :ok = Quillex.Buffer.activate(buffer_named("paging.txt"))
        beat(600)
        focus_editor()

        key("g", [:ctrl])
        dwell(1_200)
        digits("999999")
        dwell(1_200)
        key("enter")
        dwell(2_500)

        last = length(active_buffer().lines)

        assert wait_until(fn -> match?({^last, _}, cursor()) end),
               "Go to Line should clamp to the last line rather than refuse"

        Probes.take_screenshot("60_demo_03_goto_line")
        {:ok, context}
      end

      then_ "and the mouse puts the cursor where you point, including past the text",
            context do
        narrate([
          "The mouse does what you expect — including clicking",
          "past the end of a line, or below the last one."
        ])

        dwell(2_500)

        page("moving.txt", [
          "alpha beta gamma delta",
          "the second line of the file",
          "a third line here",
          "and a fourth"
        ])

        %{x: fx, y: fy, width: fw} = SemanticHelpers.get_buffer_frame()

        Probes.click(fx + 120, fy + 16 + 24)
        dwell(2_200)
        assert wait_until(fn -> match?({2, _}, cursor()) end), "a click should move the cursor"

        Probes.click(fx + trunc(fw * 0.75), fy + 16 + 3 * 24)
        dwell(2_200)

        assert wait_until(fn -> cursor() == {4, String.length("and a fourth") + 1} end),
               "clicking past the end of line 4 should land at its end, got #{inspect(cursor())}"

        {:ok, context}
      end
    end

    # ────────────────────────────────────────────────────────────────────────
    scenario "Act III — selecting, and the clipboard" do
      given_ "a page to select in", context do
        narrate([
          "Selecting. Hold Shift while you move — any movement key,",
          "not just the arrows. Or double-click a word. Or drag.",
          "",
          "Then cut, copy and paste, against the system clipboard,",
          "so it works with everything else on your desktop."
        ])

        dwell(4_000)

        page("selecting.txt", ["copy this line", "leave this one alone"])
        {:ok, _} = Quillex.Buffer.dispatch(active_buf(), [{:set_cursor, {1, 1}}])
        assert wait_until(fn -> cursor() == {1, 1} end)
        {:ok, context}
      end

      when_ "Shift and the arrows select as the cursor moves", context do
        keys("right", [:shift], 4)
        dwell(2_500)

        assert wait_until(fn -> selection() != nil end), "Shift+Right should start a selection"
        assert %{start: {1, 1}, end: {1, 5}} = selection()
        {:ok, context}
      end

      then_ "double-clicking selects the word under the pointer", context do
        %{x: fx, y: fy} = SemanticHelpers.get_buffer_frame()

        Probes.click(fx + 60, fy + 16)
        Process.sleep(80)
        Probes.click(fx + 60, fy + 16)
        dwell(2_500)

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
        dwell(2_500)

        assert wait_until(fn -> selection() != nil end), "Ctrl+A should select everything"
        assert %{start: {1, 1}} = selection()
        {:ok, context}
      end

      then_ "and copy and paste carry text through the system clipboard", context do
        page("selecting.txt", ["copy this line", "leave this one alone"])
        {:ok, _} = Quillex.Buffer.dispatch(active_buf(), [{:set_cursor, {1, 1}}])
        assert wait_until(fn -> cursor() == {1, 1} end)

        key("end", [:shift])
        dwell(1_800)
        key("c", [:ctrl])
        dwell(1_800)

        assert wait_until(fn -> selection() != nil end),
               "Shift+End should have selected the line before copying"

        key("end", [:ctrl])
        newline()
        key("v", [:ctrl])
        dwell(2_500)

        assert wait_until(fn -> length(active_buffer().lines) == 3 end),
               "paste should have added a line, got #{inspect(active_buffer().lines)}"

        assert List.last(active_buffer().lines) == "copy this line",
               "paste should reproduce the copied line, got #{inspect(active_buffer().lines)}"

        Probes.take_screenshot("60_demo_04_clipboard")
        {:ok, context}
      end
    end

    # ════════════════════════════════════════════════════════════════════════
    # 2. BUFFERS, TABS AND THE PROJECT
    # ════════════════════════════════════════════════════════════════════════

    scenario "Act IV — many buffers, and the project navigator" do
      given_ "the narration sets the scene", context do
        narrate([
          "Every open document is a buffer, and every buffer is a",
          "tab. Open as many as you like — the bar scrolls, and the",
          "asterisk tells you which ones have unsaved work.",
          "",
          "The navigator on the left is the project itself: click to",
          "open a file, drag one to move it."
        ])

        dwell(4_500)
        {:ok, context}
      end

      when_ "a handful of buffers are opened at once", context do
        for n <- 1..6 do
          page("scratch-#{n}.txt", ["buffer number #{n}"])
          beat(500)
        end

        dwell(3_500)

        assert length(root_state().buffers) >= 6, "six buffers should be open"
        Probes.take_screenshot("60_demo_05_many_tabs")
        {:ok, context}
      end

      when_ "the navigator is opened and two real files are opened from it", context do
        Quillex.RadixCache.ViewStore.open_file_nav()
        assert wait_until(fn -> root_state().show_file_nav end)
        dwell(3_000)

        {:ok, _} = Quillex.API.FileAPI.open(Path.join(@demo_dir, "lib/kernel.ex"))
        dwell(2_500)
        {:ok, _} = Quillex.API.FileAPI.open(Path.join(@demo_dir, "lib/notes.txt"))
        dwell(2_500)
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
        dwell(2_500)

        assert wait_until(fn ->
                 Enum.any?(root_state().buffers, &(&1.name == "notes.txt" and &1.dirty?))
               end),
               "typing should mark the buffer dirty"

        Probes.take_screenshot("60_demo_06_tabs")
        {:ok, context}
      end

      then_ "a file changed underneath a CLEAN buffer is quietly reloaded", context do
        narrate([
          "If a file changes on disk while you have it open, Quillex",
          "notices. A buffer with no unsaved work simply reloads —",
          "and says so."
        ])

        dwell(3_000)

        path = Path.join(@demo_dir, "lib/kernel.ex")
        :ok = Quillex.Buffer.activate(buffer_named("kernel.ex"))
        beat(700)
        refute buffer_named("kernel.ex").dirty?, "kernel.ex should still be clean here"

        File.write!(path, File.read!(path) <> "\n# changed on disk by someone else\n")
        Quillex.Files.ExternalFileSync.poll_now()

        assert wait_until(fn -> text() =~ "changed on disk by someone else" end, 8_000),
               "an external edit to a clean buffer should be picked up"

        assert (root_state().status_message || "") =~ "Reloaded",
               "and it should say so, rather than changing the document in silence"

        dwell(3_500)
        {:ok, context}
      end

      then_ "but a file changed under UNSAVED work is flagged, not overwritten", context do
        narrate([
          "But if you had unsaved work in it, that would be a",
          "conflict — so it flags the tab and keeps your edits.",
          "It will never throw away something you typed."
        ])

        dwell(3_000)

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

        assert text() =~ "...edited", "the unsaved work must be preserved, not overwritten"

        Probes.take_screenshot("60_demo_07_external_change")
        dwell(3_500)
        {:ok, context}
      end
    end

    # ════════════════════════════════════════════════════════════════════════
    # 3. FINDING THINGS
    # ════════════════════════════════════════════════════════════════════════

    scenario "Act V — finding things" do
      given_ "a narrated introduction", context do
        narrate([
          "Finding things. Two different jobs, two different tools.",
          "",
          "Ctrl+F searches this buffer, and F3 walks the matches.",
          "",
          "Ctrl+Shift+F searches the whole project, in a pane with",
          "its own query, its own replacement and its own exclude",
          "field — results grouped by file, with the match marked",
          "inside the line."
        ])

        dwell(4_500)
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
        dwell(2_000)
        assert root_state().show_search_bar, "Ctrl+F should open the find bar"

        type("needle")
        dwell(2_500)

        assert wait_until(fn -> match?({1, _}, cursor()) end, 6_000),
               "the first match is on line 1, got #{inspect(cursor())}"

        key("escape")
        beat(500)
        focus_editor()
        key("f3")
        dwell(2_500)

        assert wait_until(fn -> match?({3, _}, cursor()) end, 6_000),
               "F3 should move to the next match on line 3, got #{inspect(cursor())}"

        Probes.take_screenshot("60_demo_08_find")
        {:ok, context}
      end

      when_ "the project search runs", context do
        narrate(["Now the whole project at once."])
        dwell(2_000)

        key("f", [:ctrl, :shift])
        dwell(2_000)
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

        dwell(4_000)
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

        Probes.take_screenshot("60_demo_09_project_search")
        {:ok, context}
      end

      then_ "clicking a result opens it in one reusable preview tab", context do
        narrate_aside([
          "Clicking a result opens it in a preview tab — italic, and",
          "reused. Walk thirty results and you have one tab open,",
          "not thirty."
        ])

        # Read the results AFTER the narration, and after the store settles.
        # Narration types into a buffer, and the pane is live for open buffers,
        # so a match id captured beforehand can be stale by the time it is
        # clicked.
        :ok = Quillex.RadixCache.ProjectSearchStore.await_idle()
        %{files: files} = root_state().project_search

        found = Enum.find(files, fn {p, _} -> Path.basename(p) == "kernel.ex" end)

        assert found,
               "kernel.ex left the results after narrating: " <>
                 "#{inspect(Enum.map(files, fn {p, ms} -> {Path.basename(p), length(ms)} end))} " <>
                 "query=#{inspect(root_state().project_search.query)} " <>
                 "status=#{inspect(root_state().project_search.status)}"

        {kernel_path, [kernel_match | _]} = found

        tabs_before = length(root_state().buffers)

        Probes.click_element(
          "search_pane_match_#{kernel_match.line}_#{kernel_match.col}_#{kernel_path}"
        )

        assert wait_until(fn -> root_state().active_buf.name == "kernel.ex" end),
               "clicking a result should open that file"

        assert root_state().preview_buf_uuid == root_state().active_buf.uuid,
               "a result opens into the preview slot, drawn in italics"

        dwell(3_000)

        {notes_path, [notes_match | _]} =
          Enum.find(files, fn {p, _} -> Path.basename(p) == "notes.txt" end)

        Probes.click_element(
          "search_pane_match_#{notes_match.line}_#{notes_match.col}_#{notes_path}"
        )

        assert wait_until(fn -> root_state().active_buf.name == "notes.txt" end)

        assert length(root_state().buffers) <= tabs_before + 1,
               "the preview tab should be reused, not accumulated"

        Probes.take_screenshot("60_demo_10_preview_tab")
        dwell(3_000)
        {:ok, context}
      end

      then_ "a match is dismissed, and then everything else is replaced", context do
        narrate_aside([
          "You can dismiss a match. Once dismissed, no replace can",
          "reach it — which is what makes Replace All reviewable",
          "rather than an act of faith."
        ])

        :ok = Quillex.RadixCache.ProjectSearchStore.await_idle()
        %{files: files} = root_state().project_search
        {path, [match | _]} = Enum.find(files, fn {p, _} -> Path.basename(p) == "notes.txt" end)

        before = Enum.sum(Enum.map(files, fn {_p, ms} -> length(ms) end))

        Probes.click_element("search_pane_dismiss_match_#{match.line}_#{match.col}_#{path}")

        assert wait_until(fn ->
                 %{files: after_files} = root_state().project_search
                 Enum.sum(Enum.map(after_files, fn {_p, ms} -> length(ms) end)) == before - 1
               end),
               "dismissing a match should remove it from the results"

        dwell(3_000)

        # The replacement row lives behind a disclosure, like the find bar's —
        # so it has to be opened before there is a field to click.
        Probes.click_element("search_pane_replace_caret")
        beat(400)

        Probes.click_element("search_pane_field_replace")
        beat(600)
        type("g'day")
        dwell(2_000)
        Probes.click_element("search_pane_replace_all")

        assert wait_until(fn -> (root_state().status_message || "") =~ "Replaced" end),
               "Replace All reported nothing"

        dwell(3_500)
        {:ok, context}
      end

      then_ "the dismissed occurrence survived, which is the whole point", context do
        {:ok, snapshot} = Quillex.Buffer.fetch(buffer_named("notes.txt"))
        content = Enum.join(snapshot.lines, "\n")

        assert content =~ "hello", "a dismissed match must be untouched by Replace All"
        assert content =~ "g'day", "the matches that were not dismissed should have been replaced"

        assert snapshot.ref.dirty?,
               "an open file is replaced through its buffer, so Undo still works there"

        Probes.take_screenshot("60_demo_11_replaced")
        Quillex.RadixCache.ViewStore.close_project_search()
        dwell(2_000)
        {:ok, context}
      end
    end

    # ════════════════════════════════════════════════════════════════════════
    # 4. READING CODE
    # ════════════════════════════════════════════════════════════════════════

    scenario "Act VI — reading code" do
      given_ "a source file on screen", context do
        narrate([
          "Reading code.",
          "",
          "Syntax highlighting here is structural: weight, slant and",
          "underline rather than colour. It reads the same for every",
          "kind of colour vision, and it needs no palette of its own,",
          "so it survives every theme.",
          "",
          "Watch what happens to the keywords and the comments."
        ])

        dwell(4_000)

        # Open it here rather than reaching for whatever an earlier act left
        # lying around: the search act opens files into a PREVIEW tab, which is
        # a single reusable slot, so the file it showed is not guaranteed to
        # still be open by the time this act runs.
        {:ok, _} = Quillex.API.FileAPI.open(Path.join(@demo_dir, "lib/kernel.ex"))
        beat(900)
        :ok = Quillex.Buffer.activate(buffer_named("kernel.ex"))
        beat(900)
        focus_editor()
        dwell(4_000)
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

        Probes.take_screenshot("60_demo_12_syntax")
        {:ok, context}
      end

      then_ "folding collapses the file to its shape", context do
        narrate_aside([
          "Folding collapses a block to its first line, so you can",
          "see the shape of a file rather than its contents.",
          "",
          "Set the fold level and the whole file folds at once."
        ])

        :ok = Quillex.Buffer.activate(buffer_named("kernel.ex"))
        beat(800)
        focus_editor()
        dwell(2_500)

        Quillex.RadixCache.ViewStore.set_fold_level(2)
        assert wait_until(fn -> root_state().fold_level == 2 end)
        dwell(4_500)
        Probes.take_screenshot("60_demo_13_folded")

        Quillex.RadixCache.ViewStore.set_fold_level(1)
        assert wait_until(fn -> root_state().fold_level == 1 end)
        dwell(4_500)

        menu(:view, :unfold_all)
        dwell(3_000)
        {:ok, context}
      end

      then_ "the guides mark where you are", context do
        narrate_aside([
          "And there are guides for the line and the column you are",
          "on, if you want them."
        ])

        :ok = Quillex.Buffer.activate(buffer_named("kernel.ex"))
        beat(800)

        for id <- ["current_line_highlight", "current_column_highlight"] do
          key =
            if id == "current_line_highlight",
              do: :highlight_current_line,
              else: :highlight_current_column

          before = Map.get(root_state(), key)
          menu(:view, id)

          assert wait_until(fn -> Map.get(root_state(), key) != before end),
                 "View → #{id} did not take effect"

          dwell(3_500)
        end

        close_menus()
        dwell(2_000)
        Probes.take_screenshot("60_demo_14_guides")
        {:ok, context}
      end

      then_ "and word wrap keeps a long line on screen", context do
        narrate_aside([
          "Word wrap folds a long line into the window instead of",
          "scrolling sideways — and the cursor follows the visual",
          "rows, not the numbered lines."
        ])

        page("wrapping.txt", [Enum.map_join(1..70, " ", &"word#{&1}")])

        refute root_state().word_wrap
        dwell(2_500)
        menu(:view, "word_wrap")

        assert wait_until(fn -> root_state().word_wrap end), "Word Wrap did not turn on"
        dwell(4_000)
        assert child_state(:buffer_pane).wrap_mode == :word

        focus_editor()
        {:ok, _} = Quillex.Buffer.dispatch(active_buf(), [{:set_cursor, {1, 1}}])
        assert wait_until(fn -> cursor() == {1, 1} end)
        key("down")
        dwell(2_500)

        assert {1, col} = cursor()

        assert col > 1,
               "under wrap, Down should move along the wrapped line, got #{inspect(cursor())}"

        Probes.take_screenshot("60_demo_15_wrap")
        menu(:view, "word_wrap")
        assert wait_until(fn -> not root_state().word_wrap end)
        dwell(2_000)
        {:ok, context}
      end
    end

    # ════════════════════════════════════════════════════════════════════════
    # 5. MAKING IT YOURS
    # ════════════════════════════════════════════════════════════════════════

    # ────────────────────────────────────────────────────────────────────────
    # None of this is text-editor functionality. It is the furniture the
    # editor is built out of — frames that lay themselves out, scrollbars that
    # know how tall the document is, a divider that can be dragged and
    # collapsed — and it is most of the code.
    scenario "Act VII — the window and its furniture" do
      given_ "a document taller than the window", context do
        narrate([
          "None of what follows is text editing.",
          "",
          "It is the furniture: panes that lay themselves out from a",
          "frame, scrollbars that recompute the document's height",
          "whenever it changes, a divider you can drag. It is most of",
          "the code, and you only notice it when it is wrong."
        ])

        dwell(5_000)

        :ok = Quillex.Buffer.activate(buffer_named("paging.txt"))
        beat(900)
        focus_editor()
        dwell(2_500)
        {:ok, context}
      end

      when_ "the wheel is turned", context do
        %{x: x, y: y, width: w, height: h} = buffer_pane_frame()
        mid = {x + trunc(w * 0.4), y + trunc(h * 0.5)}

        # Down the document and back up, slowly enough to watch the thumb
        # travel with it.
        for _ <- 1..14 do
          Probes.send_scroll(0, -3, elem(mid, 0), elem(mid, 1))
          beat(220)
        end

        dwell(2_500)

        for _ <- 1..14 do
          Probes.send_scroll(0, 3, elem(mid, 0), elem(mid, 1))
          beat(220)
        end

        dwell(2_000)
        {:ok, context}
      end

      then_ "the scrollbar thumb can be grabbed and thrown", context do
        narrate_aside([
          "The thumb is draggable, and its LENGTH is the fraction of",
          "the document you can see — so it grows and shrinks as the",
          "text size changes."
        ])

        %{x: x, y: y, width: w, height: h} = buffer_pane_frame()
        bar_x = x + w - 10

        Probes.mouse_down(bar_x, y + 15)
        beat(400)

        for fraction <- [0.15, 0.3, 0.45, 0.6, 0.75] do
          Probes.send_mouse_move(bar_x, y + trunc(h * fraction))
          beat(300)
        end

        Probes.mouse_up(bar_x, y + trunc(h * 0.75))
        dwell(3_000)

        Probes.take_screenshot("60_demo_18_scrollbar_drag")
        {:ok, context}
      end

      then_ "the divider resizes the sidebar, and collapses it", context do
        narrate_aside([
          "The sidebar divider is draggable too. Drag it past its",
          "minimum and the sidebar closes — the same gesture that",
          "resizes it also puts it away."
        ])

        Quillex.RadixCache.ViewStore.open_file_nav()
        assert wait_until(fn -> root_state().show_file_nav end)
        beat(1_200)

        # The divider's grab handle is a small pill near the BOTTOM of the
        # sidebar — 90% down the content area, not halfway down the pane. Miss
        # it and the whole drag is inert, which is how this act first "passed"
        # while resizing nothing at all.
        grab_y = @top_bar_height + trunc((root_state().frame.size.height - @top_bar_height) * 0.9)

        start_width = root_state().file_nav_width
        Probes.send_mouse_move(start_width, grab_y)
        beat(400)
        Probes.mouse_down(start_width, grab_y)
        beat(400)

        assert root_state().file_nav_resizing,
               "the divider did not take the press at #{inspect({start_width, grab_y})}"

        # Out to a wide sidebar, back in to a narrow one. The buffer pane
        # reflows under it the whole way.
        for width <- [start_width, 340, 430, 500, 430, 340, 250, 190] do
          Probes.send_mouse_move(width, grab_y)
          beat(260)
        end

        Probes.mouse_up(190, grab_y)
        dwell(2_500)

        assert root_state().show_file_nav, "dragging within range must not close it"

        assert root_state().file_nav_width != start_width,
               "the drag should have actually resized the sidebar"

        Probes.take_screenshot("60_demo_19_divider_drag")

        # And now past the minimum, which closes it.
        current = root_state().file_nav_width
        Probes.send_mouse_move(current, grab_y)
        beat(300)
        Probes.mouse_down(current, grab_y)
        beat(400)

        for width <- [current, 150, 110, 70, 30] do
          Probes.send_mouse_move(width, grab_y)
          beat(280)
        end

        Probes.mouse_up(30, grab_y)
        dwell(3_000)

        refute root_state().show_file_nav,
               "dragging the divider past its minimum should close the sidebar"

        {:ok, context}
      end
    end

    scenario "Act VIII — making it yours" do
      given_ "a file with some structure to look at", context do
        narrate([
          "Making it yours. All of this is in the View menu, and all",
          "of it changes while you watch.",
          "",
          "Text size first — and notice the scrollbars, which have to",
          "recompute the whole document's height every time it moves."
        ])

        dwell(4_000)

        :ok = Quillex.Buffer.activate(buffer_named("paging.txt"))
        beat(800)
        focus_editor()
        {:ok, context}
      end

      when_ "the text size is walked up and back down", context do
        for size <- [28, 32, 16, 12, 24] do
          Quillex.RadixCache.ViewStore.set_text_size(size)
          assert wait_until(fn -> root_state().text_size == size end)
          dwell(2_800)
        end

        assert root_state().text_size == 24
        Probes.take_screenshot("60_demo_16_text_size")
        {:ok, context}
      end

      then_ "tab stops change under the text that is already written", context do
        narrate_aside([
          "Tab stops, too — and the indentation that is already on",
          "screen re-flows to match."
        ])

        page("tabs.txt", [
          "defmodule Indented do",
          "\tdef one do",
          "\t\t:deeper",
          "\tend",
          "end"
        ])

        dwell(3_000)

        for width <- [8, 12, 2, 4] do
          Quillex.RadixCache.ViewStore.set_tab_width(width)
          assert wait_until(fn -> root_state().tab_width == width end)
          dwell(4_000)
        end

        assert root_state().tab_width == 4
        Probes.take_screenshot("60_demo_17_tab_stops")
        {:ok, context}
      end

      then_ "and the theme repaints everything at once", context do
        narrate_aside([
          "And five themes. Each one paints the whole interface —",
          "the editor, the tabs, the menus and the sidebar together —",
          "because a light buffer in a dark sidebar reads as broken",
          "rather than as a theme."
        ])

        :ok = Quillex.Buffer.activate(buffer_named("kernel.ex"))
        beat(800)

        # The sidebar is part of the claim being made here — and the previous
        # act closed it by dragging its divider off the edge, which is how
        # this step first went looking for a component that no longer existed.
        Quillex.RadixCache.ViewStore.open_file_nav()
        assert wait_until(fn -> root_state().show_file_nav end)
        beat(1_000)

        for {id, _label} <- Palette.themes() do
          Quillex.RadixCache.ViewStore.set_theme(id)

          assert wait_until(fn -> root_state().theme == id end)

          assert wait_until(fn ->
                   child_state(:buffer_pane).colors.background == Palette.get(id).editor_bg
                 end),
                 "#{id} never reached the editor"

          dwell(3_500)
          Probes.take_screenshot("60_demo_18_theme_#{id}")
        end

        Quillex.RadixCache.ViewStore.set_theme(Palette.default())
        assert wait_until(fn -> root_state().theme == Palette.default() end)

        palette = Palette.get(Palette.default())
        assert child_state(:tab_bar).theme.background == palette.chrome_bg
        assert child_state(:icon_menu).theme.background == palette.chrome_bg
        assert child_state(:file_nav).theme.background == palette.pane_bg
        dwell(2_500)
        {:ok, context}
      end
    end

    # ════════════════════════════════════════════════════════════════════════
    # AND WHAT YOU WERE TOLD
    # ════════════════════════════════════════════════════════════════════════

    scenario "Epilogue — what you just saw" do
      given_ "the recap", context do
        Quillex.RadixCache.ViewStore.close_file_nav()
        beat(500)

        narrate([
          "So — that was:",
          "",
          "   1.  typing, undo, delete-line, indent, selection,",
          "       the clipboard, and every way of moving a cursor",
          "   2.  buffers and tabs, the project navigator, and",
          "       noticing a file that changed underneath you",
          "   3.  find here, find everywhere, dismiss and replace",
          "   4.  structural highlighting, folding, guides, wrap",
          "   5.  scrollbars, a draggable divider, panes that",
          "       reflow — the furniture, which is most of the code",
          "   6.  text size, tab stops and five themes, live",
          "",
          "That is the whole feature list. That is what 1.0 means."
        ])

        dwell(6_000)
        {:ok, context}
      end

      when_ "the shortcut reference is opened", context do
        narrate_aside([
          "Every one of those is in a menu, and every shortcut is in",
          "Help, Keyboard Shortcuts — generated from one registry, so",
          "a command cannot exist without appearing in it."
        ])

        menu(:help, :shortcuts)
        assert wait_until(fn -> root_state().show_shortcuts end)
        dwell(6_000)
        Probes.take_screenshot("60_demo_19_shortcuts")
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

      then_ "and it signs off", context do
        pace(:slow)

        # Clear the desk before signing it. The current-line and
        # current-column guides were turned on two acts ago to show what they
        # do, and a highlight band drawn straight through the middle of a
        # drawing is the one thing you cannot un-see.
        Quillex.RadixCache.ViewStore.set_current_line_highlight(false)
        Quillex.RadixCache.ViewStore.set_current_column_highlight(false)
        Quillex.RadixCache.ViewStore.sync()
        beat(600)

        page("quillex.txt", [""])

        # The first commit, 5 May 2021, contained nothing but this quote. It
        # turned out to be the design document.
        narrate([
          "                                             .",
          "                                       ,///'",
          "                                    ,//////'",
          "                                 ,////////'",
          "                              ,//////////'",
          "                           ,////////////'",
          "                        ,//////////////'",
          "                      ,///////////////'",
          "                    ,///////////////'",
          "                   ,//////////////'",
          "                  ,/////////////'",
          "                 ,////////////'",
          "                ,///////////'",
          "                ,//////////'",
          "               ,/////////'",
          "               ,///////'",
          "              ,//////'",
          "              ,////'",
          "             ,///'",
          "             ,//'",
          "             ,/'",
          "            //",
          "           //",
          "          //",
          "         //",
          "        //",
          "       //",
          "      \\/",
          "       .",
          "",
          "   \"Simplicity is the highest goal, achievable when you",
          "    have overcome all difficulties. After one has played",
          "    a vast quantity of notes and more notes, it is",
          "    simplicity that emerges as the crowning reward of art.\"",
          "",
          "                                        — Frederic Chopin",
          "",
          "",
          "                      Q U I L L E X   1 . 0",
          "",
          "        Written in Elixir. Rendered by Scenic.",
          "        Demonstrated, and tested, by itself."
        ])

        # By content, not by line number: the drawing above it is art, and art
        # gets redrawn.
        assert Enum.any?(active_buffer().lines, &(&1 =~ "Simplicity is the highest goal")),
               "the quote should be on screen, got #{inspect(active_buffer().lines)}"

        Probes.take_screenshot("60_demo_20_end")
        dwell(20_000)
        pace(:normal)
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
