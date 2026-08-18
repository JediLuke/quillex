defmodule Quillex.ProjectSearchSpex do
  @moduledoc """
  Phase 41 / Part II item 4: the SearchPane.

  `Ctrl+Shift+F` opens a pane in the sidebar slot that owns its own query,
  replacement and exclude fields — the floating `Ctrl+F` popup is a different
  thing searching a different scope, and the two never talk to each other.

  These scenarios drive the pane the way a person does: type into it, click a
  result, dismiss what should not be replaced, replace what should. The pane's
  own rows and buttons are registered as semantic elements, so they are clicked
  by name rather than by arithmetic on the layout.
  """
  use SexySpex
  @moduletag timeout: 300_000

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.AppReset
  alias Quillex.RadixCache.ProjectSearchStore

  defp root_state, do: :sys.get_state(Process.whereis(QuillEx.RootScene)).assigns.state

  defp pane_state do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, [pid | _]} = Scenic.Scene.child(root, :project_search_pane)
    :sys.get_state(pid, 30_000).assigns.state
  end

  defp buffer_pane_state do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, [pid | _]} = Scenic.Scene.child(root, :buffer_pane)
    :sys.get_state(pid, 30_000).assigns.state
  end

  defp results, do: root_state().project_search

  defp match_at(path_suffix) do
    {path, [match | _]} =
      Enum.find(results().files, fn {path, _} -> String.ends_with?(path, path_suffix) end)

    {path, match}
  end

  defp wait_until(predicate, timeout \\ 4_000) do
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

  defp search_done?, do: match?(%{status: {:done, _, _, _}}, results())

  # Each spex owns its own starting state. Spex 07's lesson, applied here: a
  # scenario that inherits the previous one's buffers and query fails for
  # reasons that have nothing to do with what it is testing, and the suite runs
  # in a different order every time.
  defp open_pane_with(root, query) do
    write_fixture(root)
    AppReset.reset!()
    Quillex.RadixCache.ViewStore.set_file_nav_path(root)
    Process.sleep(200)
    ProjectSearchStore.set_exclude("")
    ProjectSearchStore.set_option(:case_sensitive, false)
    ProjectSearchStore.set_option(:regex, false)
    ProjectSearchStore.set_root(root)
    ProjectSearchStore.set_query("")
    Quillex.RadixCache.ViewStore.open_project_search()
    Process.sleep(400)
    ProjectSearchStore.set_query(query)
    true = wait_until(fn -> search_done?() end)

    # And wait for the PANE, not just the store: the rows and their buttons are
    # what the scenarios click, and they exist only once the model has landed.
    true = wait_until(fn -> pane_files() == store_files() end)
    :ok
  end

  defp pane_files, do: Enum.map(pane_state().model.files, & &1.path)
  defp store_files, do: Enum.map(results().files, fn {path, _matches} -> path end)

  # Every row and button the pane draws publishes a semantic id; these mirror
  # ScenicWidgets.SearchPane.semantic_id/1.
  defp match_id(path, %{line: line, col: col}), do: "search_pane_match_#{line}_#{col}_#{path}"
  defp dismiss_match_id(path, %{line: l, col: c}), do: "search_pane_dismiss_match_#{l}_#{c}_#{path}"
  defp replace_file_id(path), do: "search_pane_replace_file_#{path}"

  # Component ids reach the semantic index as strings from some widgets and as
  # atoms from others; try both rather than guess.
  defp element_centre(id) do
    viewport = :sys.get_state(Process.whereis(QuillEx.RootScene)).viewport

    [{_id, key}] =
      case :ets.lookup(viewport.semantic_index, id) do
        [] -> :ets.lookup(viewport.semantic_index, String.to_atom(id))
        found -> found
      end

    [{_key, entry}] = :ets.lookup(viewport.semantic_table, key)
    %{left: left, top: top, width: width, height: height} = entry.screen_bounds
    {trunc(left + width / 2), trunc(top + height / 2)}
  end

  # Rewritten before every spex: these scenarios replace text on disk, and the
  # suite runs in a different order each time.
  defp write_fixture(root) do
    File.rm_rf!(root)
    File.mkdir_p!(Path.join(root, "lib/deep"))
    File.mkdir_p!(Path.join(root, "_build"))

    File.write!(
      Path.join(root, "lib/alpha.ex"),
      Enum.map_join(1..80, "\n", fn i ->
        if rem(i, 20) == 0, do: "line #{i} needle here", else: "line #{i}"
      end)
    )

    File.write!(Path.join(root, "lib/deep/beta.txt"), "a needle in a haystack\nno\nNEEDLE again")
    File.write!(Path.join(root, "README.md"), "# fixture\nno needles? yes needle")
    File.write!(Path.join(root, "_build/ignored.txt"), "needle in a build artefact")
    :ok
  end

  setup_all do
    {:ok, _} = Application.ensure_all_started(:quillex)
    Process.sleep(1_000)
    AppReset.reset!()

    root = Path.expand("test/support/project_search_fixture")
    write_fixture(root)

    Quillex.RadixCache.ViewStore.set_file_nav_path(root)
    Process.sleep(300)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root}
  end

  spex "The SearchPane searches the project from its own fields",
    description: "Ctrl+Shift+F opens a pane that owns its query; results are grouped by file",
    tags: [:phase_41, :project_search, :search_pane] do
    scenario "opening, typing, and reading the results" do
      when_ "Ctrl+Shift+F is pressed and a query typed into the pane", context do
        write_fixture(context.root)
        AppReset.reset!()
        Quillex.RadixCache.ViewStore.set_file_nav_path(context.root)
        ProjectSearchStore.set_exclude("")
        ProjectSearchStore.set_option(:case_sensitive, false)
        ProjectSearchStore.set_query("")
        Process.sleep(400)

        Probes.click(800, 300)
        Process.sleep(100)
        Probes.send_keys("f", [:ctrl, :shift])
        Process.sleep(500)

        st = root_state()
        assert st.show_project_search, "the project-search pane should open"

        refute st.show_search_bar,
               "the pane owns its own query — the floating find popup must stay out of it"

        Probes.send_text("needle")

        assert wait_until(fn -> search_done?() end), "the project search should finish"
        assert wait_until(fn -> pane_files() == store_files() end)
        {:ok, context}
      end

      then_ "the pane's own query field holds what was typed", context do
        assert pane_state().query == "needle"
        assert pane_state().focused, "the pane must hold the keyboard while it is up"
        {:ok, context}
      end

      then_ "results are grouped by file and skip build directories", context do
        %{status: {:done, matches, files, _ms}, files: grouped} = results()
        assert matches == 8
        assert files == 3
        refute Enum.any?(grouped, fn {path, _} -> String.contains?(path, "_build") end)

        Probes.take_screenshot("41_search_pane_results")
        {:ok, context}
      end

      then_ "each match row knows where the match sits inside its excerpt", context do
        model = Quillex.GUI.SearchPaneModel.build(results())
        rows = Enum.flat_map(model.files, & &1.matches)
        assert length(rows) == 8

        for row <- rows do
          assert String.slice(row.text, row.match_start, row.match_len) =~ ~r/needle/i,
                 "row #{inspect(row)} does not mark its own match"
        end

        {:ok, context}
      end
    end
  end

  spex "Results open into one reusable preview tab",
    description: "Walking results leaves one tab, not thirty; double-clicking keeps one",
    tags: [:phase_41, :project_search, :preview_tab] do
    scenario "a result opens a preview, the next one replaces it, promotion keeps it" do
      given_ "results for 'needle' are showing", context do
        :ok = open_pane_with(context.root, "needle")
        {:ok, Map.put(context, :tabs_before, length(root_state().buffers))}
      end

      when_ "a result in README.md is clicked", context do
        {path, match} = match_at("README.md")
        Probes.click_element(match_id(path, match))

        assert wait_until(fn ->
                 st = root_state()
                 st.active_buf && st.active_buf.name == "README.md"
               end),
               "README.md should become the active buffer"

        assert wait_until(fn -> buffer_pane_state().cursor == {match.line, match.col} end),
               "the cursor should sit on the match"

        {:ok, Map.put(context, :readme_uuid, root_state().active_buf.uuid)}
      end

      then_ "that tab is the preview tab", context do
        assert root_state().preview_buf_uuid == context.readme_uuid
        {:ok, context}
      end

      then_ "a result in another file reuses the same slot", context do
        tabs_before = length(root_state().buffers)
        {path, match} = match_at("beta.txt")
        Probes.click_element(match_id(path, match))

        assert wait_until(fn ->
                 st = root_state()
                 st.active_buf && st.active_buf.name == "beta.txt"
               end)

        assert wait_until(fn -> length(root_state().buffers) == tabs_before end),
               "the preview tab should have been reused, not added to"

        refute Enum.any?(root_state().buffers, &(&1.uuid == context.readme_uuid)),
               "the previous preview should be gone"

        {:ok, Map.put(context, :beta_uuid, root_state().active_buf.uuid)}
      end

      then_ "double-clicking the tab promotes it, and the next result opens beside it",
            context do
        # Resolve the tab's position ONCE and press twice. Two click_element
        # calls put a semantic lookup inside the double-click window, which is
        # a race against the widget's own timing rather than a test of it.
        {x, y} = element_centre("tab_bar_#{context.beta_uuid}")
        Probes.click(x, y)
        Probes.click(x, y)

        assert wait_until(fn -> root_state().preview_buf_uuid == nil end),
               "a double-clicked tab should stop being provisional"

        tabs_before = length(root_state().buffers)
        {path, match} = match_at("README.md")
        Probes.click_element(match_id(path, match))

        assert wait_until(fn -> length(root_state().buffers) == tabs_before + 1 end),
               "a promoted tab must not be recycled"

        Probes.take_screenshot("41_search_pane_preview_tab")
        {:ok, context}
      end
    end
  end

  spex "Dismissal is what makes Replace All reviewable",
    description: "A dismissed match leaves the results and every replace path",
    tags: [:phase_41, :project_search, :replace] do
    scenario "dismiss one match, replace one file, then replace the rest" do
      given_ "a fresh search for 'needle'", context do
        :ok = open_pane_with(context.root, "needle")
        assert {:done, 8, 3, _} = results().status
        {:ok, context}
      end

      when_ "a replacement is typed into the pane's own replace field", context do
        Probes.click_element("search_pane_field_replace")
        Process.sleep(150)
        Probes.send_text("pin")

        assert wait_until(fn -> pane_state().replace == "pin" end),
               "the pane owns the replacement text"

        {:ok, context}
      end

      when_ "one match in beta.txt is dismissed", context do
        {path, match} = match_at("beta.txt")
        Probes.click_element(dismiss_match_id(path, match))

        assert wait_until(fn -> match?({:done, 7, 3, _}, results().status) end),
               "the dismissed match should leave the visible results"

        assert MapSet.member?(results().dismissed, {path, match.line, match.col})
        Probes.take_screenshot("41_search_pane_dismissed")
        {:ok, Map.merge(context, %{beta_path: path, dismissed: match})}
      end

      then_ "replacing that whole file leaves the dismissed match alone", context do
        Probes.click_element(replace_file_id(context.beta_path))

        assert wait_until(fn ->
                 (root_state().status_message || "") =~ "Replaced 1 match in 1 file"
               end),
               "only the one surviving match in beta.txt should have been replaced"

        assert wait_until(fn -> search_done?() end)

        # beta.txt is "a needle in a haystack / no / NEEDLE again". The first
        # match was dismissed, so only the upper-case one is rewritten.
        assert File.read!(context.beta_path) == "a needle in a haystack\nno\npin again"
        {:ok, context}
      end

      then_ "Replace All rewrites what is left, everywhere", context do
        Probes.click_element("search_pane_replace_all")

        assert wait_until(fn ->
                 (root_state().status_message || "") =~ "Replaced 6 matches in 2 files"
               end),
               "the six matches outside beta.txt should go in one step"

        assert File.read!(Path.join(context.root, "README.md")) == "# fixture\nno pins? yes pin"

        # Still dismissed, still there: a replace never reaches a match the
        # user has taken out of the set.
        assert File.read!(context.beta_path) =~ "a needle in a haystack"
        {:ok, context}
      end
    end
  end

  spex "The pane's header steers the search",
    description: "Exclude globs, case sensitivity and the close button",
    tags: [:phase_41, :project_search, :search_options] do
    scenario "excluding a subtree, matching case, and closing" do
      given_ "a search for 'needle' across the fixture", context do
        :ok = open_pane_with(context.root, "needle")
        {:ok, context}
      end

      when_ "an exclude glob hides lib/", context do
        ProjectSearchStore.set_exclude("lib/**")

        assert wait_until(fn ->
                 search_done?() and
                   not Enum.any?(results().files, fn {p, _} -> String.contains?(p, "/lib/") end)
               end),
               "the exclude glob should remove every file under lib/"

        {:ok, context}
      end

      then_ "clearing it brings them back", context do
        ProjectSearchStore.set_exclude("")

        assert wait_until(fn ->
                 search_done?() and
                   Enum.any?(results().files, fn {p, _} -> String.contains?(p, "/lib/") end)
               end)

        {:ok, context}
      end

      then_ "the Aa toggle makes the search case-sensitive", context do
        assert Enum.any?(results().files, fn {_path, matches} ->
                 Enum.any?(matches, &(&1.matched == "NEEDLE"))
               end),
               "the fixture should hold an upper-case occurrence to distinguish"

        Probes.click_element("search_pane_toggle_case_sensitive")

        assert wait_until(fn -> results().case_sensitive end),
               "clicking Aa should turn on case sensitivity"

        # Wait for the RESULT, not for a status that may still be the previous
        # search's — a toggle re-runs asynchronously and {:done, …} is true both
        # before and after.
        assert wait_until(fn ->
                 search_done?() and
                   not Enum.any?(results().files, fn {_path, matches} ->
                     Enum.any?(matches, &(&1.matched == "NEEDLE"))
                   end)
               end),
               "an upper-case occurrence must not match a lower-case query"

        Probes.click_element("search_pane_toggle_case_sensitive")
        assert wait_until(fn -> not results().case_sensitive end)
        {:ok, context}
      end

      then_ "the close button hides the pane and hands the keyboard back", context do
        Probes.click_element("search_pane_close")

        assert wait_until(fn -> not root_state().show_project_search end),
               "the close button should hide the pane"

        ProjectSearchStore.sync()
        {:ok, context}
      end
    end
  end
end
