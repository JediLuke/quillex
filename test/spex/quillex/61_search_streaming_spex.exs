defmodule Quillex.SearchStreamingSpex do
  @moduledoc """
  Results appear while the search is still running.

  The backend walks a project tree file by file, and on a real project the
  first match is known within a few milliseconds while the last one takes the
  best part of a tenth of a second — measured on Quillex itself:

      walking the tree alone       9.8 ms   (466 files)
      until the FIRST file matches 4.4 ms
      until the LAST               ~85 ms

  So ~95% of the wait happened after the answer's first line was already
  known, and every bit of it was spent holding that line back. The search
  now publishes what it has as it goes, and the pane draws it — faded and
  under a "searching…" line, because a partial result is not the answer yet,
  but on the screen rather than in a task nobody can see.

  This is deliberately tested on a project big enough for the search to take
  real time. A fixture that answers in three milliseconds cannot show the
  difference between streaming and not, and would pass either way.
  """
  use SexySpex
  @moduletag timeout: 300_000

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.AppReset

  # Big enough that the walk takes long enough to watch: 250 files of 800
  # lines is ~200k lines to scan, one match apiece.
  @files 250
  @lines_per_file 800

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

  # The STATUS LINE, which is a header widget — told apart from the body's
  # own "Searching…" line by where it is drawn rather than by what it says,
  # since a graph's primitives are a map and their order is nobody's promise.
  defp status_text do
    graph = pane_graph()
    body = body_uids(graph)

    graph.primitives
    |> Enum.reject(fn {uid, _p} -> MapSet.member?(body, uid) end)
    |> Enum.map(fn {_uid, p} -> p end)
    |> Enum.filter(&(&1.module == Scenic.Primitive.Text))
    |> Enum.map(& &1.data)
    |> Enum.find(&(&1 =~ ~r/^(\d+ in \d+ files?  \(\d+ms\)|no matches|searching…|typing…|Type to search|Search [~\/…])/))
  end

  defp body_uids(graph) do
    case Scenic.Graph.get(graph, :search_pane_body) do
      [%{data: uids}] -> uids |> Enum.flat_map(&expand_uid(graph, &1)) |> MapSet.new()
      _ -> MapSet.new()
    end
  end

  defp expand_uid(graph, uid) do
    case Map.get(graph.primitives, uid) do
      %{module: Scenic.Primitive.Group, data: kids} ->
        [uid | Enum.flat_map(kids, &expand_uid(graph, &1))]

      nil -> []
      _ -> [uid]
    end
  end

  defp drawn_row_count do
    pane_graph().ids |> Map.keys() |> Enum.count(&match?({:row_bg, _}, &1))
  end

  defp in_flight?(status), do: status in ["typing…", "searching…"]
  defp done?(status), do: is_binary(status) and status =~ ~r/^(\d+ in \d+ files?|no matches)/

  # An empty pane now names the project it is about to search, rather than
  # describing what searching is. It still says the old thing when there is no
  # project open at all.
  defp idle?(nil), do: false
  defp idle?(text), do: (text =~ ~r/^Search [~\/…]/) or text =~ "Type to search"

  defp wait_until(predicate, timeout \\ 30_000) do
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

  # Every sample the pane went through, as {status, rows drawn}. The whole
  # claim is about what was on the screen BEFORE the end, so the end is not
  # where you can look for it.
  defp sample_through_search(timeout \\ 30_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_sample(deadline, [])
  end

  defp do_sample(deadline, samples) do
    sample = {status_text(), drawn_row_count(), System.monotonic_time(:millisecond)}
    samples = samples ++ [sample]

    cond do
      done?(elem(sample, 0)) and length(samples) > 1 -> samples
      System.monotonic_time(:millisecond) >= deadline -> samples
      true -> Process.sleep(10) && do_sample(deadline, samples)
    end
  end

  defp write_fixture(root) do
    File.rm_rf!(root)
    File.mkdir_p!(Path.join(root, "lib"))

    Enum.each(1..@files, fn f ->
      body =
        Enum.map_join(1..@lines_per_file, "\n", fn n ->
          if n == div(@lines_per_file, 2),
            do: "  def needle_#{f}(x), do: x",
            else: "  # padding line #{n} of module #{f}"
        end)

      File.write!(
        Path.join(root, "lib/module_#{String.pad_leading("#{f}", 4, "0")}.ex"),
        body
      )
    end)

    :ok
  end

  defp open_empty_pane(root) do
    AppReset.reset!()
    Quillex.RadixCache.ViewStore.set_file_nav_path(root)
    Process.sleep(400)

    Probes.send_keys("f", [:ctrl, :shift])
    true = wait_until(fn -> pane_open?() end)

    Probes.click_element("search_pane_clear")
    true = wait_until(fn -> idle?(status_text()) end)
    :ok
  end

  setup_all do
    {:ok, _} = Application.ensure_all_started(:quillex)
    Process.sleep(1_000)
    AppReset.reset!()

    root = Path.join(System.tmp_dir!(), "quillex_search_streaming")
    write_fixture(root)

    on_exit(fn ->
      Quillex.RadixCache.ViewStore.set_file_nav_path(File.cwd!())
      Process.sleep(200)
      File.rm_rf!(root)
    end)

    {:ok, root: root}
  end

  spex "A slow search shows its results as it finds them",
    description: "Partial results reach the screen before the search is over",
    tags: [:phase_41, :project_search, :search_pane, :streaming] do
    scenario "watching a big project be searched" do
      given_ "an empty pane on a project of #{@files} files", context do
        :ok = open_empty_pane(context.root)

        # This whole spex is about the gap between the first result and the
        # last, so a fixture without one proves nothing. Measured here, before
        # anything is asserted about it.
        {us, {:ok, matches}} =
          :timer.tc(fn ->
            Quillex.Search.Backend.Elixir.search(context.root, "needle",
              excludes: [],
              exclude_globs: [],
              unignore_globs: [],
              max_results: 5_000
            )
          end)

        ms = us / 1000

        assert ms > 100,
               """
               the backend answers this fixture in #{Float.round(ms, 1)}ms —
               too fast for a partial result to exist, let alone be seen.
               """

        assert length(matches) == @files,
               "expected one match per file, got #{length(matches)}"

        IO.puts("\n  [streaming] the walk takes #{Float.round(ms, 1)} ms for #{@files} files")

        {:ok, context}
      end

      when_ "a query is typed and the pane watched all the way through", context do
        Probes.send_text("needle")
        samples = sample_through_search()

        {:ok, Map.put(context, :samples, samples)}
      end

      then_ "the search really did take long enough to be worth streaming", context do
        # Otherwise everything below passes for the wrong reason.
        searching = Enum.count(context.samples, fn {s, _, _} -> s == "searching…" end)

        assert searching >= 5,
               """
               the SEARCH itself (not the debounce before it) was only seen
               running #{searching} times at 10ms a sample. This fixture
               answers too fast to tell streaming from not streaming, and
               nothing below would mean anything.
                 samples: #{inspect(context.samples)}
               """

        {:ok, context}
      end

      then_ "results were on the screen BEFORE the search finished", context do
        partial = Enum.filter(context.samples, fn {s, rows, _t} -> in_flight?(s) and rows > 0 end)

        refute partial == [],
               """
               the pane drew nothing until the search was over. Every result
               was known long before the last one was, and all of them waited
               for it.
                 samples: #{inspect(context.samples)}
               """

        {:ok, Map.put(context, :partial, partial)}
      end

      then_ "and the list grew as more were found", context do
        counts = context.partial |> Enum.map(&elem(&1, 1))

        assert counts == Enum.sort(counts),
               "a partial result set should only ever grow: #{inspect(counts)}"

        {:ok, context}
      end

      then_ "so the wait for something to look at was much shorter", context do
        {_s, _rows, first_at} = List.first(context.partial)
        {_s2, _rows2, done_at} = List.last(context.samples)

        saved = done_at - first_at

        IO.puts(
          "  [streaming] first results on screen #{saved} ms before the search finished\n"
        )

        assert saved > 0,
               "results and the end of the search arrived together: nothing was gained"

        {:ok, context}
      end

      then_ "and the finished pane agrees with its own status line", context do
        assert wait_until(fn -> done?(status_text()) end), "the search never finished"

        [_, n, files] = Regex.run(~r/^(\d+) in (\d+) files?/, status_text())

        assert String.to_integer(n) == @files,
               "every file has one match, so the count should be #{@files}: #{status_text()}"

        assert String.to_integer(files) == @files

        {:ok, context}
      end
    end
  end
end
