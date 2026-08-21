defmodule Quillex.SearchResultsTreeSpex do
  @moduledoc """
  The tree view shows where the results are, not just what they are.

  The slider had two positions and they were the same idea twice. What it
  called "tree" was a flat run of file rows with their matches under them —
  a LIST — and what it called "list" was the same results again with the file
  name repeated onto every row. Neither told you where in the project
  anything was.

  So the two positions are now genuinely two views:

      list   lib/core/engine.ex  (2)      every matching file, one after
               12  def needle(x)          another, path shown in full
             lib/web/router.ex   (1)
               8   # the needle

      tree   v lib                        the project's own shape, with
               v core                     only the directories that
                 engine.ex  (2)           contain a match
                   12  def needle(x)
               v web
                 router.ex  (1)
                   8   # the needle

  Read out of the pane's graph: which rows exist, what they say, and how far
  in they are drawn. Indentation IS the tree — a hierarchy whose rows all
  start at the same x is a list with extra rows in it.
  """
  use SexySpex
  @moduletag timeout: 300_000

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.AppReset

  defp pane_scene do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))

    case Scenic.Scene.child(root, :project_search_pane) do
      {:ok, [pid | _]} -> :sys.get_state(pid, 30_000)
      _ -> nil
    end
  end

  defp pane_open?, do: pane_scene() != nil
  defp pane_graph, do: pane_scene().assigns.graph

  defp drawn_rows do
    pane_graph().ids
    |> Map.keys()
    |> Enum.filter(&match?({:row_bg, _}, &1))
    |> Enum.map(fn {:row_bg, id} -> id end)
  end

  defp drawn_dirs, do: drawn_rows() |> Enum.filter(&match?({:dir, _}, &1))
  defp drawn_files, do: drawn_rows() |> Enum.filter(&match?({:file, _}, &1))
  defp drawn_matches, do: drawn_rows() |> Enum.filter(&match?({:match, _, _, _}, &1))

  # Every result row as DRAWN: how far down, how far in, and what it says.
  # Rows are groups translated by their y, holding a text translated by its x.
  defp drawn_row_text do
    graph = pane_graph()

    case Scenic.Graph.get(graph, :search_pane_scroll) do
      [%{data: uids}] ->
        uids
        |> Enum.flat_map(fn uid ->
          case Map.get(graph.primitives, uid) do
            %{module: Scenic.Primitive.Group, data: kids} = group ->
              {_gx, gy} = Scenic.Primitive.get_transform(group, :translate) || {0, 0}

              kids
              |> Enum.map(&Map.get(graph.primitives, &1))
              |> Enum.filter(&(&1 && &1.module == Scenic.Primitive.Text))
              |> Enum.map(fn text ->
                {tx, _ty} = Scenic.Primitive.get_transform(text, :translate) || {0, 0}
                {gy, tx, text.data}
              end)

            _ ->
              []
          end
        end)
        |> Enum.sort()

      _ ->
        []
    end
  end

  defp indent_of(fragment) do
    case Enum.find(drawn_row_text(), fn {_y, _x, t} -> String.contains?(t, fragment) end) do
      {_y, x, _t} -> x
      nil -> nil
    end
  end

  defp drawn?(fragment),
    do: Enum.any?(drawn_row_text(), fn {_y, _x, t} -> String.contains?(t, fragment) end)

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

  # A project with actual shape to it.
  defp write_fixture(root) do
    File.rm_rf!(root)

    %{
      "lib/core/engine.ex" => "defmodule Engine do\n  def needle(x), do: x\n  # another needle\nend\n",
      "lib/web/router.ex" => "defmodule Router do\n  # routes the needle\nend\n",
      "test/engine_test.exs" => "test \"needle\" do\nend\n",
      "README.md" => "# Fixture\n\nfind the needle here\n"
    }
    |> Enum.each(fn {path, contents} ->
      full = Path.join(root, path)
      File.mkdir_p!(Path.dirname(full))
      File.write!(full, contents)
    end)

    :ok
  end

  defp open_pane_with(root, query) do
    AppReset.reset!()
    Quillex.RadixCache.ViewStore.set_file_nav_path(root)
    Process.sleep(400)

    Probes.send_keys("f", [:ctrl, :shift])
    true = wait_until(fn -> pane_open?() end)

    Probes.click_element("search_pane_clear")
    Process.sleep(200)
    Probes.send_text(query)
    true = wait_until(fn -> drawn_matches() != [] end, 15_000)
    :ok
  end

  # Through the slider, the way a person changes it — the setting lives in the
  # view store and only reaches the pane with a model push, so setting the
  # store behind the pane's back changes nothing on the screen.
  defp set_view(view) do
    unless pane_scene().assigns.state.results_view == view do
      Probes.click_element("search_pane_view")
      true = wait_until(fn -> pane_scene().assigns.state.results_view == view end)
    end

    :ok
  end

  setup_all do
    {:ok, _} = Application.ensure_all_started(:quillex)
    Process.sleep(1_000)
    AppReset.reset!()

    root = Path.join(System.tmp_dir!(), "quillex_search_results_tree")
    write_fixture(root)

    on_exit(fn ->
      Quillex.RadixCache.ViewStore.set_file_nav_path(File.cwd!())
      Process.sleep(200)
      File.rm_rf!(root)
    end)

    {:ok, root: root}
  end

  spex "Results can be read as a list or as the project's own tree",
    description: "The tree view keeps the directory layout the files live in",
    tags: [:phase_41, :project_search, :search_pane, :results_view] do
    scenario "as a list" do
      given_ "results for 'needle', as a list", context do
        write_fixture(context.root)
        :ok = open_pane_with(context.root, "needle")
        :ok = set_view(:list)

        {:ok, context}
      end

      then_ "every matching file is a row, and no directory is", context do
        assert drawn_files() != [], "a list of files with no files in it"

        assert drawn_dirs() == [],
               "a list has no directory rows: #{inspect(drawn_dirs())}"

        {:ok, context}
      end

      then_ "and each file says where it is, in full", context do
        assert drawn?("lib/core/engine.ex"),
               """
               with nothing else to say where a file is, its row has to say it
               itself: #{inspect(drawn_row_text())}
               """

        {:ok, context}
      end
    end

    scenario "as the project's tree" do
      when_ "the view is switched to tree", context do
        :ok = set_view(:tree)
        {:ok, context}
      end

      then_ "the directories the matches live in are drawn", context do
        assert wait_until(fn -> drawn_dirs() != [] end),
               "the tree view drew no directories at all: #{inspect(drawn_rows())}"

        dirs = drawn_dirs() |> Enum.map(fn {:dir, path} -> path end) |> Enum.sort()

        assert "lib" in dirs, "the top-level directories should be there: #{inspect(dirs)}"
        assert "lib/core" in dirs, "and the ones inside them: #{inspect(dirs)}"
        assert "lib/web" in dirs
        assert "test" in dirs

        {:ok, context}
      end

      then_ "and only the directories that contain a match", context do
        dirs = drawn_dirs() |> Enum.map(fn {:dir, path} -> path end)

        refute Enum.any?(dirs, &String.contains?(&1, "empty")),
               "the tree is the results' shape, not the whole project's: #{inspect(dirs)}"

        {:ok, context}
      end

      then_ "a file in the tree is named, not pathed", context do
        assert drawn?("engine.ex"),
               "the file should still be there: #{inspect(drawn_row_text())}"

        refute drawn?("lib/core/engine.ex"),
               """
               in a tree the folders say where the file is, so repeating the
               whole path on the file's own row says it twice.
                 #{inspect(drawn_row_text())}
               """

        {:ok, context}
      end

      then_ "and the tree is drawn as a tree — each level further in", context do
        lib = indent_of("lib")
        core = indent_of("core")
        engine = indent_of("engine.ex")
        match = indent_of("def needle")

        assert lib && core && engine && match,
               "expected all four rows to be drawn: #{inspect(drawn_row_text())}"

        assert lib < core,
               "lib/core sits inside lib, so it is drawn further in (#{lib} vs #{core})"

        assert core < engine,
               "and engine.ex inside that (#{core} vs #{engine})"

        assert engine < match,
               "and its matches inside that (#{engine} vs #{match})"

        {:ok, context}
      end

      then_ "and a file at the top of the project sits at the top level", context do
        readme = indent_of("README.md")
        lib = indent_of("lib")

        assert readme == lib,
               """
               README.md is in no directory, so it belongs beside the
               directories rather than inside one (#{readme} vs #{lib}).
               """

        {:ok, context}
      end
    end

    scenario "collapsing a directory" do
      when_ "the lib directory row is clicked", context do
        before = length(drawn_rows())
        Probes.click_element("search_pane_dir_lib")
        Process.sleep(300)

        {:ok, Map.put(context, :before, before)}
      end

      then_ "everything under it goes away, and it stays", context do
        assert wait_until(fn -> length(drawn_rows()) < context.before end),
               "collapsing lib removed nothing"

        assert {:dir, "lib"} in drawn_dirs(),
               "the row you clicked has to stay, or you cannot click it again"

        refute drawn?("engine.ex"),
               "a file inside a collapsed directory is still drawn: #{inspect(drawn_row_text())}"

        refute {:dir, "lib/core"} in drawn_dirs(),
               "and so is a directory inside it"

        # But its neighbours are untouched.
        assert drawn?("README.md"), "collapsing lib took the whole tree with it"
        assert {:dir, "test"} in drawn_dirs()

        {:ok, context}
      end

      when_ "it is clicked again", context do
        Probes.click_element("search_pane_dir_lib")
        Process.sleep(300)
        {:ok, context}
      end

      then_ "the subtree comes back", context do
        assert wait_until(fn -> length(drawn_rows()) == context.before end),
               "expanding lib did not restore what collapsing it removed"

        assert drawn?("engine.ex")

        {:ok, context}
      end
    end
  end
end
