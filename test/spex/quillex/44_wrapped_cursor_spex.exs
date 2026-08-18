defmodule Quillex.WrappedCursorSpex do
  @moduledoc """
  Part II item 5b: the cursor lives in source space, the screen is in display
  space.

  Word wrap turns one source line into several visual rows. Two things were
  never told:

  a) Down/Up stepped to the next *numbered* line, skipping the rest of a
     wrapped one.
  b) A click on the second visual row measured its X against the source line
     from the first character, landing on the wrong column.

  Both are now resolved in display space and converted back to the source
  `{line, col}` the buffer stores. These scenarios drive the real editor with
  wrap on and assert on the buffer's cursor.
  """
  use SexySpex
  @moduletag timeout: 300_000

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.AppReset
  alias ScenicWidgets.TextField.Renderer

  defp root_state, do: :sys.get_state(Process.whereis(QuillEx.RootScene)).assigns.state

  defp pane_state do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, [pid | _]} = Scenic.Scene.child(root, :buffer_pane)
    :sys.get_state(pid, 30_000).assigns.state
  end

  defp cursor do
    {:ok, snapshot} = Quillex.Buffer.fetch(root_state().active_buf)
    snapshot.cursor
  end

  defp wait_until(predicate, timeout \\ 3_000) do
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

  # A line long enough that it certainly wraps at any sane pane width, made of
  # distinguishable words so a wrong column is obvious in a failure message.
  @wrapped_line Enum.map_join(1..60, " ", &"word#{&1}")

  defp ensure_word_wrap do
    unless pane_state().wrap_mode == :word do
      Probes.click_element("icon_menu_view")
      Process.sleep(120)
      Probes.click_element("icon_menu_view_word_wrap")
      Process.sleep(350)
    end

    true = wait_until(fn -> pane_state().wrap_mode == :word end)
    :ok
  end

  setup_all do
    {:ok, _} = Application.ensure_all_started(:quillex)
    Process.sleep(1_000)
    AppReset.reset!()

    {:ok, buf} =
      Quillex.Buffer.new(%{
        name: "wrapped-cursor.txt",
        data: ["first line", @wrapped_line, "last line"]
      })

    :ok = Quillex.Buffer.activate(buf)
    Process.sleep(400)
    ensure_word_wrap()
    {:ok, buf: buf}
  end

  spex "Down moves by visual row, not by line number",
    description: "A wrapped line is walked row by row, and the goal column survives the trip",
    tags: [:phase_44, :word_wrap, :cursor] do
    scenario "stepping down through a line that wraps to several rows" do
      given_ "the cursor is at the start of the wrapped line", context do
        {:ok, buf} =
          Quillex.Buffer.new(%{
            name: "wrapped-down.txt",
            data: ["first line", @wrapped_line, "last line"]
          })

        :ok = Quillex.Buffer.activate(buf)
        Process.sleep(400)
        ensure_word_wrap()
        Probes.click(700, 300)
        Process.sleep(150)
        {:ok, _} = Quillex.Buffer.dispatch(buf, [{:set_cursor, {2, 1}}])
        assert wait_until(fn -> cursor() == {2, 1} end)

        rows = wrapped_row_count()

        assert rows >= 3,
               "the fixture line must wrap to at least three rows; it wrapped to #{rows}"

        {:ok, Map.put(context, :rows, rows)}
      end

      when_ "Down is pressed once", context do
        Probes.send_keys("down", [])

        assert wait_until(fn -> cursor() != {2, 1} end),
               "Down did nothing"

        {:ok, context}
      end

      then_ "the cursor is still on the same source line, further along it", context do
        {line, col} = cursor()

        assert line == 2,
               "Down skipped the rest of the wrapped line and landed on line #{line}"

        assert col > 1, "Down should have moved along the line, but the column is #{col}"

        # And it is exactly one visual row down.
        state = pane_state()
        {row, _col} = Renderer.source_to_display_cursor(state, {line, col})
        {start_row, _} = Renderer.source_to_display_cursor(state, {2, 1})
        assert row == start_row + 1
        {:ok, context}
      end

      then_ "pressing Down through the rest of the rows reaches the next line", context do
        for _ <- 1..(context.rows - 1), do: Probes.send_keys("down", [])

        assert wait_until(fn -> match?({3, _}, cursor()) end),
               "walking every visual row should eventually reach line 3, cursor is #{inspect(cursor())}"

        {:ok, context}
      end

      then_ "Up walks back into the wrapped line rather than over it", context do
        Probes.send_keys("up", [])

        assert wait_until(fn -> match?({2, _}, cursor()) end),
               "Up from line 3 should land inside the wrapped line, not above it"

        {:ok, context}
      end
    end
  end

  spex "The goal column survives a short row",
    description: "Stepping through a short line does not ratchet the column leftward",
    tags: [:phase_44, :word_wrap, :cursor] do
    scenario "down, down, and back up across a short line" do
      given_ "a document whose middle line is short", context do
        {:ok, buf} =
          Quillex.Buffer.new(%{
            name: "goal-column.txt",
            data: ["aaaaaaaaaaaaaaaaaaaa", "bb", "cccccccccccccccccccc"]
          })

        :ok = Quillex.Buffer.activate(buf)
        Process.sleep(400)
        Probes.click(700, 300)
        Process.sleep(150)
        {:ok, _} = Quillex.Buffer.dispatch(buf, [{:set_cursor, {1, 15}}])
        assert wait_until(fn -> cursor() == {1, 15} end)
        {:ok, context}
      end

      when_ "Down is pressed twice, through the short line", context do
        Probes.send_keys("down", [])
        assert wait_until(fn -> match?({2, _}, cursor()) end)
        assert cursor() == {2, 3}, "the short line clamps to its end"

        Probes.send_keys("down", [])
        assert wait_until(fn -> match?({3, _}, cursor()) end)
        {:ok, context}
      end

      then_ "the column comes back on the next long line", context do
        assert cursor() == {3, 15},
               "the goal column was clipped by the short line instead of being remembered"

        {:ok, context}
      end
    end
  end

  spex "Clicking a wrapped row lands on the character under the pointer",
    description: "X is measured against the visual row that was clicked, not the source line",
    tags: [:phase_44, :word_wrap, :cursor] do
    scenario "clicking on the second visual row of a wrapped line" do
      given_ "the wrapped document is active with wrap on", context do
        {:ok, buf} =
          Quillex.Buffer.new(%{
            name: "wrapped-click.txt",
            data: ["first line", @wrapped_line, "last line"]
          })

        :ok = Quillex.Buffer.activate(buf)
        Process.sleep(400)
        ensure_word_wrap()
        Probes.click(700, 300)
        Process.sleep(150)
        {:ok, context}
      end

      then_ "the click maps through the display row, not the source line", context do
        state = pane_state()

        # The second visual row of line 2. Asking the widget where that row
        # begins and clicking a few characters into it is the whole test: the
        # old mapping measured from the FIRST row's first character and so
        # answered with a column from the wrong segment.
        {first_row, _} = Renderer.source_to_display_cursor(state, {2, 1})
        second_row = first_row + 1
        row_text = Renderer.display_row_text(state, second_row)
        assert row_text != "", "line 2 should wrap to more than one row"

        {line, col} =
          ScenicWidgets.TextField.State.click_to_cursor(
            state,
            click_point(state, second_row, 5)
          )

        assert line == 2

        expected =
          Renderer.display_to_source_cursor(state, {second_row, 5}) |> elem(1)

        assert col == expected,
               "a click on the second visual row resolved to column #{col}, not #{expected}"

        # And the character it landed on is the one drawn there.
        {:ok, snapshot} = Quillex.Buffer.fetch(root_state().active_buf)
        source = Enum.at(snapshot.lines, line - 1)
        assert String.at(source, col - 1) == String.at(row_text, 4)
        {:ok, context}
      end
    end
  end

  # The number of visual rows the fixture's second line occupies.
  defp wrapped_row_count do
    state = pane_state()
    {start_row, _} = Renderer.source_to_display_cursor(state, {2, 1})

    {end_row, _} =
      Renderer.source_to_display_cursor(state, {2, String.length(@wrapped_line) + 1})

    end_row - start_row + 1
  end

  # A point inside the content area, on `display_row`, `column` characters in.
  # Mirrors what State.click_to_cursor/2 undoes.
  defp click_point(state, display_row, column) do
    gutter = if state.show_line_numbers, do: state.line_number_width, else: 0
    line_height = ScenicWidgets.TextField.State.line_height(state)
    char_w = ScenicWidgets.TextField.State.string_width(state, "m")

    # A quarter of a character in, not half: find_column/5 rounds to the
    # NEXT column once the click passes a glyph's midpoint, so aiming at the
    # midpoint is a coin flip.
    x = gutter + 10 + (column - 1) * char_w + char_w * 0.25 - state.scroll.offset_x
    y = (display_row - 1) * line_height + 4 - state.scroll.offset_y + line_height / 2 - 2
    {x, y}
  end
end
