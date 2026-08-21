defmodule Quillex.SearchLoadingStateSpex do
  @moduledoc """
  The search pane says what it is doing.

  A project search is asynchronous and debounced: 150ms after the last
  keystroke a task starts, and it finishes whenever it finishes. In between,
  the pane went on showing the previous query's results with nothing to say
  they were the previous query's — so a slow search was indistinguishable
  from a finished one that had found those particular files, and the only way
  to tell was to wait and see whether the list changed.

  Three states, published with the results rather than inferred from them:

      :debouncing   a keystroke has landed; the search has not started yet
      :searching    the task is running
      {:done, …}    these results answer the query in the box

  What the pane does with them:

    * the STATUS LINE always says which of the three it is in;
    * results from the previous query are drawn FADED for as long as they are
      the previous query's, so they read as the last answer rather than this
      one;
    * a search with nothing to fade — the first one — says so in the body
      instead of showing an empty pane.

  Everything below is read off the pane's graph. A status the pane knows and
  does not draw is a status nobody can see.
  """
  use SexySpex
  @moduletag timeout: 300_000

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.AppReset

  # ── What is on the screen ─────────────────────────────────────────────────

  defp pane_scene do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))

    case Scenic.Scene.child(root, :project_search_pane) do
      {:ok, [pid | _]} -> :sys.get_state(pid, 30_000)
      _ -> nil
    end
  end

  defp pane_open?, do: pane_scene() != nil
  defp pane_graph, do: pane_scene().assigns.graph

  defp drawn_text do
    pane_graph().primitives
    |> Map.values()
    |> Enum.filter(&(&1.module == Scenic.Primitive.Text))
    |> Enum.map(& &1.data)
  end

  # The STATUS LINE, which is a header widget. Told apart from the body's own
  # "Searching…" line by WHERE it is drawn — a graph's primitives are a map,
  # and which of two matching strings comes out first is nobody's promise.
  defp status_text do
    graph = pane_graph()
    body = Enum.map(body_primitives(), & &1.data)

    graph.primitives
    |> Map.values()
    |> Enum.filter(&(&1.module == Scenic.Primitive.Text))
    |> Enum.map(& &1.data)
    |> Kernel.--(body)
    |> Enum.find(&(&1 =~ ~r/^(\d+ in \d+ files?  \(\d+ms\)|no matches|searching…|typing…|Type to search|Search [~\/…])/))
  end

  defp drawn_rows do
    pane_graph().ids
    |> Map.keys()
    |> Enum.filter(&match?({:row_bg, _}, &1))
    |> Enum.map(fn {:row_bg, id} -> id end)
  end

  # The BODY's primitives specifically — walked down from the body group, so
  # the header's text cannot be mistaken for a result row's.
  defp body_primitives do
    graph = pane_graph()

    case Scenic.Graph.get(graph, :search_pane_body) do
      [group] -> descendants(graph, group)
      [] -> []
    end
  end

  defp descendants(graph, %{module: Scenic.Primitive.Group, data: uids}) do
    Enum.flat_map(uids, fn uid ->
      case Map.get(graph.primitives, uid) do
        nil -> []
        child -> descendants(graph, child)
      end
    end)
  end

  defp descendants(_graph, primitive), do: [primitive]

  defp body_text do
    body_primitives()
    |> Enum.filter(&(&1.module == Scenic.Primitive.Text))
    |> Enum.map(& &1.data)
  end

  # The colours the result rows' text is actually drawn in.
  defp row_text_fills do
    body_primitives()
    |> Enum.filter(&(&1.module == Scenic.Primitive.Text))
    |> Enum.map(&Scenic.Primitive.get_style(&1, :fill))
    |> Enum.uniq()
    |> Enum.sort()
  end

  # ── Driving it ────────────────────────────────────────────────────────────

  # An empty pane now names the project it is about to search, rather than
  # describing what searching is. It still says the old thing when there is no
  # project open at all.
  defp idle?(nil), do: false
  defp idle?(text), do: (text =~ ~r/^Search [~\/…]/) or text =~ "Type to search"

  defp wait_until(predicate, timeout \\ 8_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait(predicate, deadline)
  end

  defp do_wait(predicate, deadline) do
    cond do
      predicate.() -> true
      System.monotonic_time(:millisecond) >= deadline -> false
      true -> Process.sleep(20) && do_wait(predicate, deadline)
    end
  end

  # Watch the pane closely while a search runs, and report everything it drew
  # on the way: which status lines appeared, and which colours the rows were
  # drawn in. Sampling is how a loading state has to be tested — it is a state
  # the pane passes THROUGH, and a single look after the fact only ever sees
  # the end of it.
  defp sample_through_search(timeout \\ 8_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_sample(deadline, [], [])
  end

  defp do_sample(deadline, statuses, fills) do
    status = status_text()
    statuses = if status && status not in statuses, do: statuses ++ [status], else: statuses
    fills = Enum.uniq(fills ++ row_text_fills())

    cond do
      status && status =~ ~r/^(\d+ in \d+ files?|no matches)/ and length(statuses) > 1 ->
        %{statuses: statuses, fills: fills}

      System.monotonic_time(:millisecond) >= deadline ->
        %{statuses: statuses, fills: fills}

      true ->
        Process.sleep(15)
        do_sample(deadline, statuses, fills)
    end
  end

  defp in_flight?(status), do: status in ["typing…", "searching…"]

  # ── The project ───────────────────────────────────────────────────────────

  defp write_fixture(root) do
    File.rm_rf!(root)
    File.mkdir_p!(Path.join(root, "lib"))

    Enum.each(1..12, fn i ->
      File.write!(
        Path.join(root, "lib/module_#{i}.ex"),
        Enum.map_join(1..40, "\n", fn n ->
          if rem(n, 4) == 0, do: "  def needle_#{n}(x), do: x", else: "  # line #{n}"
        end)
      )
    end)

    :ok
  end

  defp close_fixture_buffers(root) do
    Quillex.Buffer.list()
    |> Enum.filter(&(is_binary(&1.path) and String.starts_with?(&1.path, root)))
    |> Enum.each(&Quillex.Buffer.close(&1, :discard))

    Process.sleep(250)
  end

  defp open_empty_pane(root) do
    AppReset.reset!()
    close_fixture_buffers(root)
    Quillex.RadixCache.ViewStore.set_file_nav_path(root)
    Process.sleep(400)

    Probes.send_keys("f", [:ctrl, :shift])
    true = wait_until(fn -> pane_open?() end)

    # The pane keeps the last query it was given; the × is how a person empties
    # it, and it hands the keyboard back to the query field.
    Probes.click_element("search_pane_clear")
    true = wait_until(fn -> idle?(status_text()) end)
    :ok
  end

  setup_all do
    {:ok, _} = Application.ensure_all_started(:quillex)
    Process.sleep(1_000)
    AppReset.reset!()

    root = Path.join(System.tmp_dir!(), "quillex_search_loading_state")
    write_fixture(root)

    on_exit(fn ->
      Quillex.RadixCache.ViewStore.set_file_nav_path(File.cwd!())
      Process.sleep(200)
      File.rm_rf!(root)
    end)

    {:ok, root: root}
  end

  spex "The pane says what it is doing while it does it",
    description: "A debounced, asynchronous search has a visible loading state",
    tags: [:phase_41, :project_search, :search_pane, :loading_state] do
    scenario "the very first search, with nothing to show yet" do
      given_ "an empty search pane on a project", context do
        write_fixture(context.root)
        :ok = open_empty_pane(context.root)

        assert drawn_rows() == [], "the pane should be empty before the first search"
        {:ok, context}
      end

      when_ "a query is typed and the pane watched all the way through", context do
        Probes.send_text("needle")
        sample = sample_through_search()

        {:ok, Map.put(context, :sample, sample)}
      end

      then_ "it said it was working before it said what it found", context do
        %{statuses: statuses} = context.sample

        assert Enum.any?(statuses, &in_flight?/1),
               """
               the pane went from empty straight to results with nothing in
               between. A search that takes a while is indistinguishable from
               one that has not started.
                 drew: #{inspect(statuses)}
               """

        assert List.last(statuses) =~ ~r/^\d+ in \d+ files?/,
               "and it should end by saying what it found: #{inspect(statuses)}"

        # In flight FIRST, results after — not the other way round.
        in_flight_at = Enum.find_index(statuses, &in_flight?/1)
        done_at = Enum.find_index(statuses, &(&1 =~ ~r/^\d+ in \d+ files?/))

        assert in_flight_at < done_at,
               "the working state has to come before the answer: #{inspect(statuses)}"

        {:ok, context}
      end

      then_ "and it distinguished waiting for the keyboard from searching", context do
        %{statuses: statuses} = context.sample

        assert "typing…" in statuses,
               """
               the 150ms debounce after a keystroke is its own state: the
               search has not started, and the pane should not claim it has.
                 drew: #{inspect(statuses)}
               """

        {:ok, context}
      end
    end

    scenario "a second search, with the previous answer still on the screen" do
      given_ "results for the first query", context do
        assert wait_until(fn -> drawn_rows() != [] end), "no results to work from"

        {:ok, Map.put(context, :settled_fills, row_text_fills())}
      end

      when_ "the query is changed and the pane watched again", context do
        # "needle_1" still matches, so the results before and after are alike —
        # what changes in between is only whether they are the ANSWER.
        Probes.send_text("_1")
        sample = sample_through_search()

        {:ok, Map.put(context, :sample, sample)}
      end

      then_ "the old results were drawn faded while they were the old ones", context do
        %{fills: fills} = context.sample

        faded = fills -- context.settled_fills

        refute faded == [],
               """
               the previous query's results were drawn in exactly the colours
               of an answer for the whole time they were not one. Nothing on
               the screen said they were stale.
                 colours seen: #{inspect(fills)}
                 when settled: #{inspect(context.settled_fills)}
               """

        {:ok, context}
      end

      then_ "and they went back to full strength once they were the answer", context do
        assert wait_until(fn -> status_text() =~ ~r/^\d+ in \d+ files?/ end),
               "the search never finished: #{inspect(status_text())}"

        assert wait_until(fn -> row_text_fills() == context.settled_fills end),
               """
               the results are the answer now, and are still drawn as though
               they were not.
                 now:      #{inspect(row_text_fills())}
                 settled:  #{inspect(context.settled_fills)}
               """

        {:ok, context}
      end

      then_ "and the status line counts them again", context do
        assert status_text() =~ ~r/^\d+ in \d+ files?  \(\d+ms\)$/,
               "a finished search says what it found and how long it took: #{inspect(status_text())}"

        {:ok, context}
      end
    end

    scenario "a search with nothing on the screen to fade" do
      when_ "the pane is cleared and a fresh query typed", context do
        Probes.click_element("search_pane_clear")
        assert wait_until(fn -> drawn_rows() == [] end), "the × did not empty the pane"

        Probes.send_text("needle")
        {:ok, context}
      end

      then_ "the body says it is searching rather than sitting blank", context do
        assert wait_until(fn -> Enum.any?(body_text(), &(&1 =~ ~r/Searching/i)) end, 3_000),
               """
               with no previous results to fade, an in-flight search showed an
               empty pane — which is what "no matches" looks like.
                 body: #{inspect(body_text())}
               """

        {:ok, context}
      end

      then_ "and it gives way to the results when they arrive", context do
        assert wait_until(fn -> drawn_rows() != [] end), "the results never landed"

        refute Enum.any?(body_text(), &(&1 =~ ~r/Searching/i)),
               "the searching line outlived the search: #{inspect(body_text())}"

        {:ok, context}
      end
    end
  end
end
