defmodule Quillex.SearchPaneVirtualisationSpex do
  @moduledoc """
  The global search pane draws a screenful, not a result set.

  `Ctrl+Shift+F` on a real project routinely returns several hundred matches.
  The pane used to build and draw a row for every one of them — five
  primitives each, some two and a half thousand for five hundred results — of
  which about forty were ever on the screen. That cost landed on the frame
  where the results arrived, and again on any change that touched the body, so
  the pane stalled for a tenth of a second at exactly the moment it was
  supposed to be showing you something.

  Rows are a uniform height, so which ones the viewport can show is
  arithmetic. These scenarios assert on the DRAWN graph — the row background
  primitives that actually exist in the pane's graph — that only that window
  is built, that it is the right window, and that scrolling moves it.

  A count of state rows would pass either way; that is the whole point of
  looking at the primitives instead.
  """
  use SexySpex
  @moduletag timeout: 300_000

  alias ScenicMcp.Probes
  alias ScenicWidgets.SearchPane.{Renderizer, State}
  alias Quillex.TestHelpers.AppReset
  alias Quillex.RadixCache.ProjectSearchStore

  # 30 files with 20 matches apiece: 600 matches, 630 rows, and a viewport
  # that holds a few dozen. Small enough to search in under a second, large
  # enough that drawing all of it is unmistakable in the primitive count.
  @files 30
  @matches_per_file 20

  # A generous ceiling on the window: what the pane can show plus its
  # overscan, doubled. A regression that draws the result set blows past this
  # by an order of magnitude, which is what this is for — it is a tripwire,
  # not a measurement.
  @window_ceiling 120

  # Two 60fps frames. The old code took ~45ms to build a body this size and
  # the frame budget is 16.7ms, so this fails loudly if the window comes off.
  @render_budget_ms 33

  defp pane_scene do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, [pid | _]} = Scenic.Scene.child(root, :project_search_pane)
    :sys.get_state(pid, 30_000)
  end

  defp pane_state, do: pane_scene().assigns.state

  # What the pane has actually DRAWN. Every row it draws puts down a
  # background rectangle under a `{:row_bg, id}` — the id that makes a hover a
  # repaint of one rectangle — so the set of those ids in the graph is the set
  # of rows on the screen, straight out of the graph rather than out of state.
  defp drawn_row_ids do
    pane_scene().assigns.graph.ids
    |> Map.keys()
    |> Enum.filter(&match?({:row_bg, _}, &1))
    |> MapSet.new()
  end

  defp expected_row_ids do
    pane_state() |> State.visible_rows() |> Enum.map(&{:row_bg, &1.id}) |> MapSet.new()
  end

  defp pane_primitive_count, do: map_size(pane_scene().assigns.graph.primitives)

  defp results, do: :sys.get_state(Process.whereis(QuillEx.RootScene)).assigns.state.project_search

  defp search_done?, do: match?(%{status: {:done, _, _, _}}, results())

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

  # A project big enough to be worth virtualising: every file has the same
  # twenty matches, so the row count is exactly known.
  defp write_fixture(root) do
    File.rm_rf!(root)
    File.mkdir_p!(Path.join(root, "lib"))

    Enum.each(1..@files, fn f ->
      body =
        Enum.map_join(1..(@matches_per_file * 3), "\n", fn i ->
          if rem(i, 3) == 0,
            do: "  def haystack_#{div(i, 3)}(needle), do: needle",
            else: "  # line #{i}"
        end)

      File.write!(Path.join(root, "lib/module_#{String.pad_leading("#{f}", 2, "0")}.ex"), body)
    end)

    :ok
  end

  defp close_fixture_buffers(root) do
    Quillex.Buffer.list()
    |> Enum.filter(&(is_binary(&1.path) and String.starts_with?(&1.path, root)))
    |> Enum.each(&Quillex.Buffer.close(&1, :discard))

    Process.sleep(250)
  end

  defp open_pane_with(root, query) do
    AppReset.reset!()
    close_fixture_buffers(root)
    Quillex.RadixCache.ViewStore.set_file_nav_path(root)
    Process.sleep(200)
    Quillex.RadixCache.ViewStore.set_search_results_view(:tree)
    ProjectSearchStore.set_option(:case_sensitive, false)
    ProjectSearchStore.set_option(:regex, false)
    ProjectSearchStore.set_root(root)
    ProjectSearchStore.set_query("")
    Quillex.RadixCache.ViewStore.open_project_search()
    Process.sleep(400)
    ProjectSearchStore.set_query(query)

    Scenic.Scene.put_child(
      :sys.get_state(Process.whereis(QuillEx.RootScene)),
      :project_search_pane,
      {:set_query, query}
    )

    :ok = ProjectSearchStore.await_idle()
    true = wait_until(fn -> search_done?() end)
    true = wait_until(fn -> length(pane_state().model.files) == length(results().files) end)
    :ok
  end

  # The middle of the pane's scrolling body, in screen coordinates — where a
  # wheel event has to land for the pane to take it.
  defp body_point do
    state = pane_state()
    {px, py} = state.frame.pin.point
    body = State.body_frame(state)
    {_bx, by} = body.pin.point

    {trunc(px + state.frame.size.width / 2), trunc(py + by + body.size.height / 2)}
  end

  setup_all do
    {:ok, _} = Application.ensure_all_started(:quillex)
    Process.sleep(1_000)
    AppReset.reset!()

    root = Path.expand("test/support/search_pane_virtualisation_fixture")
    write_fixture(root)

    on_exit(fn ->
      Quillex.RadixCache.ViewStore.set_file_nav_path(File.cwd!())
      Process.sleep(200)
      File.rm_rf!(root)
    end)

    {:ok, root: root}
  end

  spex "Six hundred matches draw as one screenful",
    description: "The pane builds the window under the viewport, not the result set",
    tags: [:phase_41, :project_search, :search_pane, :performance] do
    scenario "a project-sized result set" do
      given_ "a project with #{@files * @matches_per_file} matches, searched", context do
        write_fixture(context.root)
        :ok = open_pane_with(context.root, "needle")

        total = State.row_count(pane_state())

        assert total > 500,
               "the fixture is meant to overwhelm the viewport, but the pane has " <>
                 "only #{total} rows — every assertion below would be vacuous"

        {:ok, Map.put(context, :total_rows, total)}
      end

      then_ "the pane DREW a window, not the result set", context do
        drawn = drawn_row_ids()

        assert MapSet.size(drawn) <= @window_ceiling,
               "the pane drew #{MapSet.size(drawn)} rows for #{context.total_rows} results — " <>
                 "it is drawing the result set, not the screenful it can show"

        # And it drew ENOUGH: a window that is bounded but empty is a blank
        # pane, which passes a ceiling and fails a person.
        on_screen = ceil(State.body_frame(pane_state()).size.height / pane_state().theme.row_height)

        assert MapSet.size(drawn) >= on_screen,
               "the viewport holds #{on_screen} rows but only #{MapSet.size(drawn)} were drawn — " <>
                 "the bottom of the pane is blank"

        IO.puts(
          "\n  [virtualisation] #{context.total_rows} rows, #{MapSet.size(drawn)} drawn, " <>
            "#{pane_primitive_count()} primitives in the pane's graph"
        )

        {:ok, context}
      end

      then_ "and the rows it drew are exactly the ones under the viewport", context do
        assert MapSet.equal?(drawn_row_ids(), expected_row_ids()),
               "the drawn rows and the pane's own idea of its window disagree — " <>
                 "drawn #{MapSet.size(drawn_row_ids())}, expected #{MapSet.size(expected_row_ids())}"

        {:ok, context}
      end

      then_ "so rebuilding the body costs a frame, not a stall", context do
        # The same work the pane does when results land, timed against the
        # live state. Unvirtualised this was ~45ms for a body this size.
        {us, _graph} = :timer.tc(fn -> Renderizer.render(pane_state()) end)
        ms = us / 1000

        IO.puts("  [virtualisation] rebuilding the pane took #{Float.round(ms, 2)} ms\n")

        assert ms < @render_budget_ms,
               "building the pane for #{context.total_rows} results took #{Float.round(ms, 2)} ms, " <>
                 "over the #{@render_budget_ms} ms budget"

        {:ok, context}
      end
    end

    scenario "scrolling moves the window" do
      given_ "the same search, scrolled to the top", context do
        :ok = open_pane_with(context.root, "needle")

        before = drawn_row_ids()
        assert MapSet.size(before) > 0, "nothing was drawn to scroll"

        {:ok, Map.put(context, :before, before)}
      end

      when_ "the wheel is turned a long way down over the results", context do
        # The same gesture the file navigator takes to mean "down", because
        # the two panes live in the same sidebar and used to disagree about it.
        {x, y} = body_point()
        Enum.each(1..12, fn _ -> Probes.send_scroll(0, -5, x, y) end)
        Process.sleep(600)

        assert wait_until(fn -> pane_state().scroll.offset_y > 0 end),
               "the wheel did not reach the pane's body"

        {:ok, context}
      end

      then_ "the pane drew different rows — the ones now under it", context do
        after_ids = drawn_row_ids()

        refute MapSet.equal?(context.before, after_ids),
               "the same rows are drawn after scrolling past them; the window did not move"

        assert MapSet.equal?(after_ids, expected_row_ids()),
               "what was drawn after the scroll is not the window the pane says it has"

        {:ok, context}
      end

      then_ "and it is still one screenful", context do
        drawn = drawn_row_ids()

        assert MapSet.size(drawn) <= @window_ceiling,
               "after scrolling the pane holds #{MapSet.size(drawn)} rows — " <>
                 "the window is accumulating rather than moving"

        {:ok, context}
      end
    end
  end
end
