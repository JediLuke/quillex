defmodule Quillex.GlobalSearchJourneySpex do
  @moduledoc """
  One person, one project, one search — the whole way through.

  Every other search spex drives a feature: it sets the store, or clicks one
  control and checks one flag. That is how a pane whose tree/list slider does
  nothing and whose scope tree cannot untick a directory passed a green suite.
  Features tested one at a time are features that work one at a time.

  So this is a JOURNEY. It opens the pane with the keyboard, types the query a
  character at a time, and from there touches nothing but the controls a
  person can see: it clicks them by the name they publish to the semantic
  layer, and it believes only what the pane has actually DRAWN — the row
  primitives in its graph and the text in them. No store is called, no state
  is set, no snapshot is pushed. If a click does not reach the thing it points
  at, this fails.

  The story:

    1. open the pane, search the project, read the results as a tree
    2. collapse a file, and put it back
    3. slide from tree to list, and back
    4. open the settings, open the scope tree, and narrow the search:
       expand a directory WITHOUT changing what it searches, untick a
       directory that has children, and untick the project root to clear
       the lot at once
    5. match case, and stop matching case
    6. dismiss a result, replace the rest, clear the query, close the pane

  ## What this spex asserts must EXIST

  Two things the pane does not publish today, both of which the story needs
  and a person needs just as much:

    * `search_pane_scope_<path>` must TICK a directory, whatever else it can
      do. A directory with children currently swallows the click to expand
      itself, so the commonest thing you want from a scope tree — "not that
      folder" — cannot be done to any folder that has anything in it.

    * `search_pane_scope_expand_<path>` must be its own control. Expanding
      and excluding are different intentions and cannot share one rectangle.

  And one node:

    * the project root is the FIRST row of the scope tree, so that "search
      nothing but…" and "search everything again" are one click each.
  """
  use SexySpex
  @moduletag timeout: 300_000

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.AppReset

  # ── Reading what is on the screen ─────────────────────────────────────────
  #
  # All of it comes out of the pane's own graph. A row that exists in state
  # and not in the graph is a row nobody can see or click.

  defp pane_scene do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))

    case Scenic.Scene.child(root, :project_search_pane) do
      {:ok, [pid | _]} -> :sys.get_state(pid, 30_000)
      _ -> nil
    end
  end

  defp pane_open?, do: pane_scene() != nil

  defp pane_graph, do: pane_scene().assigns.graph

  # Every drawn row puts down a background rectangle keyed by the row's id.
  defp drawn_rows do
    pane_graph().ids
    |> Map.keys()
    |> Enum.filter(&match?({:row_bg, _}, &1))
    |> Enum.map(fn {:row_bg, id} -> id end)
  end

  defp drawn_files, do: drawn_rows() |> Enum.filter(&match?({:file, _}, &1))
  defp drawn_dirs, do: drawn_rows() |> Enum.filter(&match?({:dir, _}, &1))
  defp drawn_matches, do: drawn_rows() |> Enum.filter(&match?({:match, _, _, _}, &1))

  defp drawn_file_paths, do: drawn_files() |> Enum.map(fn {:file, path} -> path end)

  defp drawn_match_paths,
    do: drawn_matches() |> Enum.map(fn {:match, path, _l, _c} -> path end) |> Enum.uniq()

  # Everything the pane has written on the screen, TOP TO BOTTOM. A graph's
  # primitives are a map and have no order of their own, so the order comes
  # from where each one is drawn — which is the order they are read in anyway.
  defp drawn_lines do
    pane_graph().primitives
    |> Map.values()
    |> Enum.filter(&(&1.module == Scenic.Primitive.Text))
    |> Enum.map(fn p ->
      {_x, y} = Map.get(p.transforms, :translate, {0, 0})
      {y, p.data}
    end)
    |> Enum.sort()
  end

  defp drawn_text, do: drawn_lines() |> Enum.map(&elem(&1, 1))

  defp drawn?(text), do: Enum.any?(drawn_text(), &String.contains?(&1, text))

  # The query and replacement fields are TextField components with graphs of
  # their own, so what they contain is read off the screen rather than out of
  # the pane's graph.
  defp on_screen?(text), do: ScenicMcp.Query.text_visible?(text)

  # The status line, as drawn: "12 in 4 files  (7ms)".
  defp status_text do
    # "Search " with its trailing space is the empty pane naming the project;
    # "Searching…" is the body's own line and has no space there.
    Enum.find(
      drawn_text(),
      &(&1 =~ ~r/^(\d+ in \d+ files?  \(\d+ms\)|no matches|searching…|typing…|Type to search|Search [~\/…])/)
    )
  end

  defp match_count do
    case status_text() do
      nil -> nil
      text -> case Regex.run(~r/^(\d+) in (\d+)/, text) do
                [_, n, f] -> {String.to_integer(n), String.to_integer(f)}
                nil -> {0, 0}
              end
    end
  end

  # The scope tree, top to bottom, as `[x] lib` / `[ ] docs`.
  #
  # The tick is DRAWN now — a box with a check in it, since the tree is a
  # generic Menu.Model.Tree row and a font cannot be trusted with a tick any
  # more than with a triangle. So its state is read from what the pane
  # PUBLISHES for each node, which is the surface anything driving the pane
  # uses and is generated from the same layout that draws it.
  defp scope_labels do
    viewport = :sys.get_state(Process.whereis(QuillEx.RootScene)).viewport

    :ets.match_object(viewport.semantic_table, {{:search_pane, :_}, :_})
    |> Enum.map(fn {{_, id}, entry} -> {id, entry} end)
    |> Enum.filter(fn {id, _entry} ->
      id = to_string(id)
      String.starts_with?(id, "search_pane_scope_") and
        not String.starts_with?(id, "search_pane_scope_expand_")
    end)
    |> Enum.sort_by(fn {_id, entry} -> entry.local_bounds.top end)
    |> Enum.map(fn {_id, entry} -> entry.label end)
  end

  defp ticked?(name), do: "[x] #{name}" in scope_labels()
  defp unticked?(name), do: "[ ] #{name}" in scope_labels()

  # ── Driving it the way a person does ──────────────────────────────────────

  defp click_named(id) do
    Probes.click_element(id)
    Process.sleep(250)
    :ok
  end

  defp semantic?(id) do
    viewport = :sys.get_state(Process.whereis(QuillEx.RootScene)).viewport

    case :ets.lookup(viewport.semantic_index, id) do
      [] -> :ets.lookup(viewport.semantic_index, String.to_atom(id)) != []
      _ -> true
    end
  end

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
      true -> Process.sleep(25) && do_wait(predicate, deadline)
    end
  end

  # ── The project being searched ────────────────────────────────────────────
  #
  # Small enough to count by hand, shaped like something real: source under
  # lib in two subdirectories, a test, a doc, a readme, and a build directory
  # that the ignore rules are supposed to keep out of the results.

  defp fixture_files do
    %{
      "lib/core/engine.ex" => "defmodule Engine do\n  def needle(x), do: x\n  # another needle\nend\n",
      "lib/core/parser.ex" => "defmodule Parser do\n  def parse(needle), do: needle\nend\n",
      "lib/web/router.ex" => "defmodule Router do\n  # routes the needle\nend\n",
      "test/engine_test.exs" => "test \"needle\" do\n  assert true\nend\n",
      "docs/guide.md" => "# Guide\n\nA NEEDLE, capitalised.\n",
      "README.md" => "# Fixture\n\nfind the needle here\n",
      "_build/generated.ex" => "# needle in a build artefact\n",
      # Ignored by the project's .gitignore but NOT by the always-skipped
      # list, so it is the one that answers whether the ignore-files switch
      # does anything. _build is skipped either way and would prove nothing.
      "scratch/notes.ex" => "# a needle in scratch\n"
    }
  end

  # Every file "needle" appears in, outside _build. The search is
  # case-insensitive until told otherwise, so the capitalised NEEDLE in the
  # docs is in here too — it is what the Match Case scenario takes away.
  defp expected_paths(root) do
    ["lib/core/engine.ex", "lib/core/parser.ex", "lib/web/router.ex",
     "test/engine_test.exs", "docs/guide.md", "README.md"]
    |> Enum.map(&Path.join(root, &1))
    |> MapSet.new()
  end

  defp write_fixture(root) do
    File.rm_rf!(root)

    Enum.each(fixture_files(), fn {path, contents} ->
      full = Path.join(root, path)
      File.mkdir_p!(Path.dirname(full))
      File.write!(full, contents)
    end)

    File.write!(Path.join(root, ".gitignore"), "_build/\nscratch/\n")
    :ok
  end

  defp close_fixture_buffers(root) do
    Quillex.Buffer.list()
    |> Enum.filter(&(is_binary(&1.path) and String.starts_with?(&1.path, root)))
    |> Enum.each(&Quillex.Buffer.close(&1, :discard))

    Process.sleep(250)
  end

  setup_all do
    {:ok, _} = Application.ensure_all_started(:quillex)
    Process.sleep(1_000)
    AppReset.reset!()

    # NOT under test/support: everything there is compiled into the test
    # build, and this fixture is real Elixir source with real modules in it.
    # A run interrupted before its on_exit leaves the files behind, and the
    # next `mix test` then fails to compile a project whose lib/ contains
    # somebody else's Engine.
    root = Path.join(System.tmp_dir!(), "quillex_global_search_journey")
    write_fixture(root)

    on_exit(fn ->
      Quillex.RadixCache.ViewStore.set_file_nav_path(File.cwd!())
      Process.sleep(200)
      File.rm_rf!(root)
    end)

    {:ok, root: root}
  end

  spex "Searching a whole project, start to finish",
    description: "Open the pane, search, narrow, read both ways, replace, close — all by hand",
    tags: [:phase_41, :project_search, :search_pane, :journey] do
    scenario "the search itself" do
      given_ "a project is open in the editor", context do
        write_fixture(context.root)
        AppReset.reset!()
        close_fixture_buffers(context.root)

        # Which project is open is the ONLY thing set from behind; everything
        # about the search below goes through the keyboard and the mouse.
        Quillex.RadixCache.ViewStore.set_file_nav_path(context.root)
        Process.sleep(400)

        {:ok, context}
      end

      when_ "Ctrl+Shift+F is pressed", context do
        Probes.send_keys("f", [:ctrl, :shift])
        Process.sleep(600)
        {:ok, context}
      end

      then_ "the search pane is on the screen", context do
        assert wait_until(fn -> pane_open?() end), "Ctrl+Shift+F did not open the pane"
        assert drawn?("SEARCH"), "the pane has no heading: #{inspect(drawn_text())}"

        {:ok, context}
      end

      when_ "the × beside the status line clears whatever was in it", context do
        # The pane keeps the last query it was given, which is what you want
        # of it — so a journey that starts from empty has to ASK for empty,
        # rather than assume a pane nobody has used yet.
        click_named("search_pane_clear")
        {:ok, context}
      end

      then_ "it is empty, and says what to do with it", context do
        assert wait_until(fn -> idle?(status_text()) end),
               "the clear button left the pane saying: #{inspect(status_text())}"

        assert drawn_rows() == [], "clearing left rows on the screen"

        {:ok, context}
      end

      when_ "'needle' is typed into it", context do
        Probes.send_text("needle")
        Process.sleep(800)
        {:ok, context}
      end

      then_ "the project's matches are drawn, grouped under their files", context do
        assert wait_until(fn -> drawn_files() != [] end),
               "typing found nothing: status #{inspect(status_text())}"

        expected = expected_paths(context.root)

        assert wait_until(fn -> MapSet.new(drawn_file_paths()) == expected end),
               """
               the wrong files are showing.
                 drawn:    #{inspect(Enum.sort(drawn_file_paths()))}
                 expected: #{inspect(Enum.sort(MapSet.to_list(expected)))}
               """

        assert drawn_matches() != [], "file headings with no matches under them"

        {:ok, context}
      end

      then_ "and neither the build output nor the ignored directory is in it", context do
        refute Enum.any?(drawn_file_paths(), &String.contains?(&1, "_build")),
               "build output is skipped by every search: #{inspect(drawn_file_paths())}"

        refute Enum.any?(drawn_file_paths(), &String.contains?(&1, "scratch")),
               "the project's own .gitignore should keep scratch/ out: #{inspect(drawn_file_paths())}"

        {:ok, context}
      end

      then_ "and the status line counts what is on the screen", context do
        {n, files} = match_count()

        assert files == length(drawn_file_paths()),
               "the status says #{files} files, the pane drew #{length(drawn_file_paths())}"

        assert n == length(drawn_matches()),
               "the status says #{n} matches, the pane drew #{length(drawn_matches())}"

        {:ok, Map.put(context, :all_matches, n)}
      end
    end

    scenario "collapsing a file, and putting it back" do
      when_ "the heading of the file with two matches is clicked", context do
        path = Path.join(context.root, "lib/core/engine.ex")
        before = length(drawn_matches())

        click_named("search_pane_file_#{path}")

        {:ok, context |> Map.put(:engine, path) |> Map.put(:before_collapse, before)}
      end

      then_ "its matches leave the screen, and its heading stays", context do
        assert wait_until(fn -> length(drawn_matches()) < context.before_collapse end),
               "collapsing the file did not remove any of its matches"

        refute Enum.any?(drawn_match_paths(), &(&1 == context.engine)),
               "the collapsed file still has matches drawn under it"

        assert {:file, context.engine} in drawn_files(),
               "collapsing a file should leave its heading to click again"

        {:ok, context}
      end

      when_ "it is clicked again", context do
        click_named("search_pane_file_#{context.engine}")
        {:ok, context}
      end

      then_ "they come back", context do
        assert wait_until(fn -> length(drawn_matches()) == context.before_collapse end),
               "expanding the file did not bring its matches back"

        {:ok, context}
      end
    end

    scenario "reading the results as a list, and back as the project's tree" do
      when_ "the view is set to list, from the settings drawer", context do
        click_named("search_pane_domain")
        click_named("search_pane_view_list")
        click_named("search_pane_domain")
        {:ok, context}
      end

      then_ "the results are a flat run of files, with no directories", context do
        assert wait_until(fn -> drawn_dirs() == [] end),
               """
               the slider did not change the results — directory rows are
               still drawn: #{inspect(drawn_dirs())}
               """

        assert drawn_files() != [], "a list of files with no files in it"
        assert drawn_matches() != [], "and no matches under them"

        {:ok, context}
      end

      then_ "and each file says where it is, in full", context do
        # With no folders above it, the row itself has to say where the file
        # is — which is the difference between this view and the other one.
        assert drawn?("lib/core/engine.ex"),
               "a list row should carry its whole path: #{inspect(drawn_text())}"

        {:ok, context}
      end

      when_ "it is set back to tree", context do
        click_named("search_pane_domain")
        click_named("search_pane_view_tree")
        click_named("search_pane_domain")
        {:ok, context}
      end

      then_ "the project's directories come back around the results", context do
        assert wait_until(fn -> drawn_dirs() != [] end),
               "the slider would not go back to tree"

        dirs = drawn_dirs() |> Enum.map(fn {:dir, path} -> path end)

        assert "lib" in dirs and "lib/core" in dirs,
               "the tree should show the folders the matches are in: #{inspect(dirs)}"

        assert MapSet.new(drawn_file_paths()) == expected_paths(context.root),
               "and all the same files, still: #{inspect(drawn_file_paths())}"

        refute drawn?("lib/core/engine.ex"),
               """
               in a tree the folders say where the file is, so its own row
               should not say it again: #{inspect(drawn_text())}
               """

        {:ok, context}
      end
    end

    scenario "narrowing the search with the scope tree" do
      when_ "the settings disclosure is opened", context do
        click_named("search_pane_domain")
        {:ok, context}
      end

      then_ "the scope summary says the whole project is being searched", context do
        assert wait_until(fn -> drawn?("SCOPE") end),
               "the settings section has no scope line: #{inspect(drawn_text())}"

        # The row is a generic Menu.Model.Tree now, and says how many of its
        # nodes are switched off — a tree of anything can count that, where
        # "excluded" only means something to a search.
        refute Enum.any?(drawn_text(), &String.contains?(&1, "off)")),
               "nothing is switched off yet, so nothing should be counted: #{inspect(drawn_text())}"

        {:ok, context}
      end

      when_ "the scope line is clicked to open the tree", context do
        click_named("search_pane_scope")
        {:ok, context}
      end

      then_ "the project root is the first row of the tree", context do
        assert wait_until(fn -> scope_labels() != [] end),
               "the scope tree did not open: #{inspect(drawn_text())}"

        root_name = Path.basename(context.root)

        assert List.first(scope_labels()) == "[x] #{root_name}",
               """
               the tree needs the project itself at the top of it, so that
               "search only this one folder" and "search everything again" are
               one click each instead of one click per folder.
                 drawn: #{inspect(scope_labels())}
               """

        {:ok, Map.put(context, :root_name, root_name)}
      end

      when_ "the disclosure triangle on 'lib' is clicked", context do
        lib = Path.join(context.root, "lib")

        assert semantic?("search_pane_scope_expand_#{lib}"),
               """
               a directory's triangle has to be its own control. Expanding a
               folder and excluding it are different intentions, and one
               rectangle cannot carry both.
               """

        click_named("search_pane_scope_expand_#{lib}")
        {:ok, Map.put(context, :lib, lib)}
      end

      then_ "its subdirectories appear, and lib is still being searched", context do
        assert wait_until(fn -> Enum.any?(scope_labels(), &String.ends_with?(&1, "core")) end),
               "expanding lib did not show what is inside it: #{inspect(scope_labels())}"

        assert ticked?("lib"),
               """
               opening a folder is not the same as excluding it — the triangle
               expands, and nothing else.
                 drawn: #{inspect(scope_labels())}
               """

        {:ok, context}
      end

      when_ "'core' — a directory with files in it — is unticked", context do
        core = Path.join(context.root, "lib/core")
        click_named("search_pane_scope_#{core}")
        {:ok, Map.put(context, :core, core)}
      end

      then_ "it shows as excluded and its files leave the results", context do
        assert wait_until(fn -> unticked?("core") end),
               """
               a directory with children could not be unticked at all: its row
               spent the click on expanding itself. "Not that folder" is the
               whole job of a scope tree.
                 drawn: #{inspect(scope_labels())}
               """

        assert wait_until(fn ->
                 not Enum.any?(drawn_file_paths(), &String.contains?(&1, "lib/core"))
               end),
               """
               core is unticked but its results are still on the screen.
                 drawn: #{inspect(drawn_file_paths())}
               """

        assert drawn?("1 off"),
               """
               the summary counts a switched-off branch ONCE, not once per
               thing inside it: #{inspect(drawn_text())}
               """

        # And the rest of the project is untouched.
        assert Enum.any?(drawn_file_paths(), &String.contains?(&1, "lib/web")),
               "excluding lib/core took lib/web with it"

        {:ok, context}
      end

      when_ "it is ticked again", context do
        click_named("search_pane_scope_#{context.core}")
        {:ok, context}
      end

      then_ "its files come back", context do
        assert wait_until(fn -> MapSet.new(drawn_file_paths()) == expected_paths(context.root) end),
               "re-ticking core did not bring its results back: #{inspect(drawn_file_paths())}"

        {:ok, context}
      end

      when_ "the project root itself is unticked", context do
        click_named("search_pane_scope_#{context.root}")
        {:ok, context}
      end

      then_ "nothing is being searched at all", context do
        assert wait_until(fn -> drawn_files() == [] and drawn_matches() == [] end),
               """
               unticking the root should clear the search in one click — that
               is what the root row is FOR.
                 drawn: #{inspect(drawn_file_paths())}
               """

        assert drawn?("1 off"),
               "and the project itself counts as the one thing switched off: #{inspect(drawn_text())}"

        assert Enum.all?(scope_labels(), &String.starts_with?(&1, "[ ] ")),
               """
               a folder that is not being searched cannot have anything under
               it that is — every row below the root should have lost its tick
               along with the root.
                 drawn: #{inspect(scope_labels())}
               """

        {:ok, context}
      end

      when_ "the root is ticked again", context do
        click_named("search_pane_scope_#{context.root}")
        {:ok, context}
      end

      then_ "the whole project is being searched again", context do
        assert wait_until(fn -> MapSet.new(drawn_file_paths()) == expected_paths(context.root) end),
               "re-ticking the root did not restore the search: #{inspect(drawn_file_paths())}"

        refute Enum.any?(drawn_text(), &String.contains?(&1, "off)")),
               "and nothing should be counted as off again: #{inspect(drawn_text())}"

        {:ok, context}
      end

      when_ "the settings are shut again", context do
        click_named("search_pane_domain")
        {:ok, context}
      end

      then_ "the tree goes away and the results stay", context do
        assert wait_until(fn -> scope_labels() == [] end),
               "the scope tree outlived the settings section it lives in"

        assert MapSet.new(drawn_file_paths()) == expected_paths(context.root)

        {:ok, context}
      end
    end

    scenario "matching case" do
      when_ "the Aa toggle is clicked", context do
        click_named("search_pane_toggle_case_sensitive")
        {:ok, context}
      end

      then_ "the capitalised NEEDLE in the docs stops matching", context do
        assert wait_until(fn ->
                 not Enum.any?(drawn_file_paths(), &String.contains?(&1, "guide.md"))
               end),
               """
               with Match Case on, "needle" should not find "NEEDLE".
                 drawn: #{inspect(drawn_file_paths())}
               """

        assert Enum.any?(drawn_file_paths(), &String.contains?(&1, "README.md")),
               "and the lowercase ones should still be there"

        {:ok, context}
      end

      when_ "it is switched off again", context do
        click_named("search_pane_toggle_case_sensitive")
        {:ok, context}
      end

      then_ "the capitalised one comes back", context do
        assert wait_until(fn ->
                 Enum.any?(drawn_file_paths(), &String.contains?(&1, "guide.md"))
               end),
               "case-insensitive search should find NEEDLE again"

        {:ok, context}
      end
    end

    scenario "searching with a regular expression" do
      when_ "the query is replaced with a pattern", context do
        click_named("search_pane_field_query")
        Probes.send_keys("a", [:ctrl])
        Process.sleep(200)
        Probes.send_text("ne+dle")
        Process.sleep(800)

        {:ok, context}
      end

      then_ "as literal text it matches nothing", context do
        assert wait_until(fn -> status_text() =~ "no matches" end),
               """
               with the regex toggle off the query is literal text, and no
               file contains "ne+dle": #{inspect(status_text())}
               """

        {:ok, context}
      end

      when_ "the .* toggle is switched on", context do
        click_named("search_pane_toggle_regex")
        {:ok, context}
      end

      then_ "the same query finds every needle in the project", context do
        assert wait_until(fn -> MapSet.new(drawn_file_paths()) == expected_paths(context.root) end),
               """
               read as a pattern, ne+dle matches needle everywhere.
                 drawn: #{inspect(drawn_file_paths())}
                 status: #{inspect(status_text())}
               """

        {:ok, context}
      end

      when_ "the toggle is switched off and the plain query typed back", context do
        click_named("search_pane_toggle_regex")
        click_named("search_pane_field_query")
        Probes.send_keys("a", [:ctrl])
        Process.sleep(200)
        Probes.send_text("needle")
        Process.sleep(800)

        {:ok, context}
      end

      then_ "the results are as they were", context do
        assert wait_until(fn -> MapSet.new(drawn_file_paths()) == expected_paths(context.root) end),
               "the search did not come back to where it started: #{inspect(drawn_file_paths())}"

        {:ok, context}
      end
    end

    scenario "changing which files are in scope at all" do
      when_ "the settings are opened and the ignore files switched off", context do
        click_named("search_pane_domain")
        assert wait_until(fn -> semantic?("search_pane_domain_use_ignore_files") end),
               "the settings section has no ignore-files switch"

        click_named("search_pane_domain_use_ignore_files")
        {:ok, context}
      end

      then_ "the directory the .gitignore was hiding shows up", context do
        assert wait_until(fn ->
                 Enum.any?(drawn_file_paths(), &String.contains?(&1, "scratch"))
               end),
               """
               with the project's own ignore rules switched off, the match in
               scratch/ should be among the results.
                 drawn: #{inspect(drawn_file_paths())}
               """

        # The always-skipped list is not a setting. Build output stays out.
        refute Enum.any?(drawn_file_paths(), &String.contains?(&1, "_build")),
               "_build is skipped by every search, ignore files or not"

        {:ok, context}
      end

      when_ "the ignore files are switched back on", context do
        click_named("search_pane_domain_use_ignore_files")
        {:ok, context}
      end

      then_ "it goes away again", context do
        assert wait_until(fn ->
                 not Enum.any?(drawn_file_paths(), &String.contains?(&1, "scratch"))
               end),
               "the ignore rules did not come back: #{inspect(drawn_file_paths())}"

        {:ok, context}
      end

      when_ "the search is narrowed to open buffers only", context do
        click_named("search_pane_domain_open_buffers_only")
        {:ok, context}
      end

      then_ "nothing matches, because none of these files are open", context do
        assert wait_until(fn -> status_text() =~ "no matches" end),
               """
               "open buffers only" with no buffer open on any of these files
               should find nothing at all: #{inspect(status_text())}
               """

        {:ok, context}
      end

      when_ "the whole project is searched again and the settings shut", context do
        click_named("search_pane_domain_open_buffers_only")
        assert wait_until(fn -> MapSet.new(drawn_file_paths()) == expected_paths(context.root) end),
               "the results did not come back: #{inspect(drawn_file_paths())}"

        click_named("search_pane_domain")
        {:ok, context}
      end

      then_ "the pane is back to a plain search of the project", context do
        assert wait_until(fn -> scope_labels() == [] end),
               "the settings section did not shut"

        assert MapSet.new(drawn_file_paths()) == expected_paths(context.root)

        {:ok, context}
      end
    end

    scenario "acting on the results" do
      when_ "the one match in the README is dismissed with the × beside it", context do
        readme = Path.join(context.root, "README.md")

        {:match, ^readme, line, col} =
          Enum.find(drawn_matches(), &match?({:match, ^readme, _l, _c}, &1))

        before = length(drawn_matches())
        click_named("search_pane_dismiss_match_#{line}_#{col}_#{readme}")

        {:ok, context |> Map.put(:readme, readme) |> Map.put(:before_dismiss, before)}
      end

      then_ "it leaves the screen, and takes its file heading with it", context do
        assert wait_until(fn -> length(drawn_matches()) == context.before_dismiss - 1 end),
               "dismissing a match did not remove it from the results"

        refute context.readme in drawn_file_paths(),
               "it was the file's only match, so the heading has nothing left to head"

        {n, _files} = match_count()

        assert n == length(drawn_matches()),
               "the status still counts the dismissed match: says #{n}, drew #{length(drawn_matches())}"

        {:ok, context}
      end

      when_ "the replacement row is opened and a replacement typed", context do
        click_named("search_pane_replace_caret")

        assert wait_until(fn -> semantic?("search_pane_field_replace") end),
               "the disclosure did not open the replacement field"

        click_named("search_pane_field_replace")
        Probes.send_text("thimble")
        Process.sleep(400)

        {:ok, context}
      end

      then_ "the replacement went into the replacement field, not the query", context do
        assert on_screen?("thimble"),
               "the replacement was typed but is nowhere on the screen"

        refute status_text() =~ "no matches",
               """
               the query is no longer matching anything, which means the
               replacement was typed into the QUERY field — clicking the
               replacement field did not move the keyboard to it.
                 status: #{inspect(status_text())}
               """

        {:ok, context}
      end

      when_ "the ↺ beside one match in the router is clicked", context do
        router = Path.join(context.root, "lib/web/router.ex")

        {:match, ^router, line, col} =
          Enum.find(drawn_matches(), &match?({:match, ^router, _l, _c}, &1))

        click_named("search_pane_replace_match_#{line}_#{col}_#{router}")
        Process.sleep(1_200)

        {:ok, Map.put(context, :router, router)}
      end

      then_ "that one occurrence is replaced, and only that one", context do
        assert wait_until(fn -> File.read!(context.router) =~ "thimble" end, 10_000),
               "replacing a single match did not reach the file: #{inspect(File.read!(context.router))}"

        engine = Path.join(context.root, "lib/core/engine.ex")

        refute File.read!(engine) =~ "thimble",
               "replacing one match reached another file entirely"

        {:ok, context}
      end

      when_ "Replace All is clicked", context do
        click_named("search_pane_replace_all")
        Process.sleep(1_500)
        {:ok, context}
      end

      then_ "every match on the screen was replaced, in the files themselves", context do
        assert wait_until(fn -> status_text() =~ "no matches" end, 10_000),
               "after replacing every match the search should find none: #{inspect(status_text())}"

        assert drawn_matches() == [], "results are still drawn after Replace All"

        replaced =
          context.root
          |> expected_paths()
          |> MapSet.delete(context.readme)

        Enum.each(replaced, fn path ->
          contents = File.read!(path)

          assert String.contains?(contents, "thimble"),
                 "#{Path.relative_to(path, context.root)} was on the screen but was not replaced: #{inspect(contents)}"

          refute contents =~ ~r/needle/i,
                 "#{Path.relative_to(path, context.root)} still has a match in it: #{inspect(contents)}"
        end)

        {:ok, context}
      end

      then_ "and the match that was dismissed was left exactly where it was", context do
        contents = File.read!(context.readme)

        assert String.contains?(contents, "needle"),
               """
               Replace All reached a match that had been dismissed. Dismissing
               is the safety valve that makes Replace All reviewable — a valve
               that only hides things is not one.
                 #{inspect(contents)}
               """

        refute String.contains?(contents, "thimble")

        {:ok, context}
      end

      when_ "the query is cleared", context do
        click_named("search_pane_clear")
        {:ok, context}
      end

      then_ "the pane goes back to waiting to be typed into", context do
        assert wait_until(fn -> idle?(status_text()) end),
               "clearing the query left the pane saying: #{inspect(status_text())}"

        assert drawn_rows() == [], "clearing the query left rows on the screen"

        {:ok, context}
      end

      when_ "the pane is closed", context do
        click_named("search_pane_close")
        {:ok, context}
      end

      then_ "it is gone", context do
        assert wait_until(fn -> not pane_open?() end),
               "the close button did not close the pane"

        {:ok, context}
      end

      when_ "it is opened again and Escape pressed", context do
        Probes.send_keys("f", [:ctrl, :shift])
        assert wait_until(fn -> pane_open?() end), "the pane would not reopen"

        Probes.send_keys("escape", [])
        Process.sleep(400)

        {:ok, context}
      end

      then_ "Escape closes it too", context do
        assert wait_until(fn -> not pane_open?() end),
               "Escape in the query field should shut the pane, as it does everywhere else"

        {:ok, context}
      end
    end
  end
end
