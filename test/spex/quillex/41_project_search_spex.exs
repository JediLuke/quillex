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

  defp status_widget do
    pane_state()
    |> ScenicWidgets.SearchPane.State.header_widgets()
    |> Enum.find(&(&1.id == :status))
  end

  defp drawn_header_height do
    [%{data: {_w, h}}] = Scenic.Graph.get(pane_scene().assigns.graph, :search_pane_header_bg)
    h
  end

  defp pane_scene do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, child} = Scenic.Scene.child(root, :project_search_pane)
    :sys.get_state(if(is_list(child), do: List.first(child), else: child))
  end

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

  # The tree/list control moved off the status bar and into the settings
  # drawer, where it is an either/or menu row with a name per position.
  defp choose_view(view) do
    unless pane_state().domain_open? do
      Probes.click_element("search_pane_domain")
      true = wait_until(fn -> pane_state().domain_open? end)
    end

    Probes.click_element("search_pane_view_#{view}")
    true = wait_until(fn -> pane_state().results_view == view end)

    Probes.click_element("search_pane_domain")
    true = wait_until(fn -> not pane_state().domain_open? end)
    :ok
  end

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
    close_fixture_buffers(root)
    Quillex.RadixCache.ViewStore.set_file_nav_path(root)
    Process.sleep(200)
    ProjectSearchStore.set_option(:case_sensitive, false)
    ProjectSearchStore.set_option(:regex, false)
    ProjectSearchStore.set_root(root)
    ProjectSearchStore.set_query("")
    Quillex.RadixCache.ViewStore.open_project_search()
    Process.sleep(400)
    ProjectSearchStore.set_query(query)

    # And tell the PANE, which is where a person would have typed it. Setting
    # only the store leaves the pane's field empty, and an empty field reports
    # itself the moment anything makes it redraw — wiping the query this
    # helper just set.
    Scenic.Scene.put_child(
      :sys.get_state(Process.whereis(QuillEx.RootScene)),
      :project_search_pane,
      {:set_query, query}
    )

    :ok = ProjectSearchStore.await_idle()
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

  # A buffer open on a fixture file OVERLAYS the disk results with its own
  # content — which is correct behaviour, and ruinous for a scenario that just
  # rewrote the fixture on disk: the previous spex's replaced text is what the
  # search would find. AppReset keeps one buffer, and that one can be a dirty
  # fixture file, so close them explicitly.
  defp close_fixture_buffers(root) do
    Quillex.Buffer.list()
    |> Enum.filter(&(is_binary(&1.path) and String.starts_with?(&1.path, root)))
    |> Enum.each(&Quillex.Buffer.close(&1, :discard))

    Process.sleep(250)
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

    # NOT under test/support, which is compiled into the test build. This
    # fixture is .ex files full of deliberate nonsense ("line 1 needle here"),
    # and a run interrupted before its on_exit leaves them behind — after
    # which `mix test` cannot compile the project at all.
    root = Path.join(System.tmp_dir!(), "quillex_project_search_fixture")
    write_fixture(root)

    Quillex.RadixCache.ViewStore.set_file_nav_path(root)
    Process.sleep(300)

    # Point the navigator somewhere that still exists before deleting the
    # fixture. Left pointing at a removed directory, the next file's navigator
    # renders an empty tree and its scenarios fail for a reason that has
    # nothing to do with them.
    on_exit(fn ->
      Quillex.RadixCache.ViewStore.set_file_nav_path(File.cwd!())
      Process.sleep(200)
      File.rm_rf!(root)
    end)

    {:ok, root: root}
  end

  spex "The SearchPane searches the project from its own fields",
    description: "Ctrl+Shift+F opens a pane that owns its query; results are grouped by file",
    tags: [:phase_41, :project_search, :search_pane] do
    scenario "opening, typing, and reading the results" do
      when_ "Ctrl+Shift+F is pressed and a query typed into the pane", context do
        write_fixture(context.root)
        AppReset.reset!()
        close_fixture_buffers(context.root)
        # Give the cursor a word to sit on, so the pane really does open
        # seeded and the assertion below has something to prove.
        {:ok, seed_buf} = Quillex.Buffer.new(%{name: "seed.txt", data: ["haystack"]})
        :ok = Quillex.Buffer.activate(seed_buf)
        Process.sleep(300)
        Quillex.RadixCache.ViewStore.set_file_nav_path(context.root)
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

        # Typing schedules one debounced search per character. await_idle
        # returns once none is in flight, which is the only moment the results
        # are known to belong to the whole query rather than a prefix of it.
        :ok = ProjectSearchStore.await_idle()
        assert wait_until(fn -> search_done?() end), "the project search should finish"
        assert wait_until(fn -> pane_files() == store_files() end)
        {:ok, context}
      end

      then_ "the pane's own query field holds what was typed", context do
        # And only what was typed: the pane opens seeded with the word under
        # the cursor, shown selected, so the first character typed replaces it
        # rather than appending to a guess.
        assert pane_state().query == "needle"
        assert pane_state().focused, "the pane must hold the keyboard while it is up"
        {:ok, context}
      end

      then_ "results are grouped by file and skip build directories", context do
        %{status: {:done, matches, files, _ms}, files: grouped} = results()

        assert matches == 8,
               "found #{matches} in #{files}: #{inspect(Enum.map(grouped, &elem(&1, 0)))}"

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

        # And the match is MARKED. Landing on a line with nothing highlighted
        # leaves you to find, by eye, the thing you just clicked on.
        assert wait_until(fn -> buffer_pane_state().search_matches != [] end),
               "the occurrences should be highlighted, got #{inspect(buffer_pane_state().search_matches)}"

        assert Enum.any?(buffer_pane_state().search_matches, fn {line, col, _text} ->
                 {line, col} == {match.line, match.col}
               end),
               "including the one that was clicked"

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
        # The replacement row is behind a disclosure now, the same as the find
        # bar's: most searches are searches.
        Probes.click_element("search_pane_replace_caret")

        assert wait_until(fn -> pane_state().replace_open? end),
               "the caret should open the replacement row"

        Process.sleep(300)

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

  spex "The scope tree belongs to the settings section",
    description: "It appears with SEARCH SETTINGS, not among the results",
    tags: [:phase_41, :project_search, :scope] do
    scenario "showing and hiding the scope tree" do
      given_ "results for 'needle'", context do
        :ok = open_pane_with(context.root, "needle")
        {:ok, context}
      end

      then_ "with settings shut, there is no scope tree anywhere", context do
        refute pane_state().domain_open?, "settings start shut"
        assert ScenicWidgets.SearchPane.State.scope_rows(pane_state()) == []

        {:ok, context}
      end

      when_ "SEARCH SETTINGS is opened", context do
        Probes.click_element("search_pane_domain")

        assert wait_until(fn -> pane_state().domain_open? end),
               "clicking the heading should open the settings"

        {:ok, context}
      end

      then_ "the HEADER redraws, not just the results", context do
        # The bug this catches: opening the settings was in neither of the
        # renderizer's "has anything changed" checks, so the header kept its
        # old shape — old height, old status position, triangle still shut —
        # while the body redrew and showed the scope tree on its own. Typing
        # any character afterwards changed the status text, tripped the widget
        # check, and set it all right, which is what made it look intermittent.
        st = pane_state()
        widgets = ScenicWidgets.SearchPane.State.header_widgets(st)

        for id <- [{:domain, :open_buffers_only}, {:domain, :use_ignore_files}, :edit_excludes] do
          assert Enum.any?(widgets, &(&1.id == id)),
                 "#{inspect(id)} should be in the header once the settings are open"
        end

        status = Enum.find(widgets, &(&1.id == :status))
        options = Enum.filter(widgets, &match?({:domain, _}, &1.id))

        # The settings are a PANEL now, dropped out of the cog on the status
        # bar and drawn over the results — so the options hang below that bar
        # rather than sitting above it. They used to be rows in the header,
        # and every inline arrangement of them moved something: above the bar
        # it pushed the cog down out from under the pointer that had clicked
        # it, below the bar it shoved the results about.
        assert Enum.all?(options, &(&1.y >= status.y)),
               "the options hang below the bar the cog is on"

        # And the panel has to be DRAWN, not merely known about — this is the
        # assertion that catches a header which has not caught up with its own
        # state, which is what used to leave a band of bare pane behind.
        assert Scenic.Graph.get(pane_scene().assigns.graph, :search_pane_settings) != [],
               "the settings are open and no panel was drawn for them"

        {:ok, context}
      end

      then_ "the scope tree is in the settings panel, below the bar", context do
        st = pane_state()
        widgets = ScenicWidgets.SearchPane.State.header_widgets(st)

        scope = Enum.filter(widgets, &match?({:scope_row, _}, &1.id))
        refute scope == [], "the scope tree belongs to the header now, with the settings"

        status = Enum.find(widgets, &(&1.id == :status))

        assert Enum.all?(scope, &(&1.y >= status.y)),
               "the scope belongs in the panel, which hangs below the bar"

        # And NOT among the results, which is where it used to sit.
        kinds = st |> ScenicWidgets.SearchPane.State.rows() |> Enum.map(& &1.kind)
        refute :scope_header in kinds, "and not among the results: #{inspect(kinds)}"

        {:ok, context}
      end

      then_ "expanding the tree grows the PANEL, and moves nothing else", context do
        # Expanding a folder adds rows to the panel, which is drawn over the
        # results — so the panel gets taller and the pane behind it does not
        # move at all. It used to add rows to the HEADER, which pushed the
        # status line, the cog and every result down the screen.
        before_status = status_widget().y
        before_panel = ScenicWidgets.SearchPane.State.settings_height(pane_state())

        Probes.click_element("search_pane_scope")

        assert wait_until(fn -> pane_state().scope_open? end),
               "clicking the scope summary should open the tree"

        assert wait_until(fn ->
                 ScenicWidgets.SearchPane.State.settings_height(pane_state()) > before_panel
               end),
               "the panel should grow as the tree does"

        assert status_widget().y == before_status,
               "and nothing behind it should move: #{status_widget().y} vs #{before_status}"

        rows = ScenicWidgets.SearchPane.State.scope_rows(pane_state())
        assert length(rows) > 1, "the tree itself should be showing: #{inspect(rows)}"

        Probes.click_element("search_pane_scope")
        assert wait_until(fn -> not pane_state().scope_open? end)

        {:ok, context}
      end

      then_ "and shutting the settings takes it away again", context do
        Probes.click_element("search_pane_domain")

        assert wait_until(fn -> not pane_state().domain_open? end)
        assert ScenicWidgets.SearchPane.State.scope_rows(pane_state()) == []

        {:ok, context}
      end
    end
  end

  spex "Results show as a tree or a list",
    description: "One slider with two positions, and the choice is remembered",
    tags: [:phase_41, :project_search, :results_view] do
    scenario "sliding between them" do
      given_ "results for 'needle'", context do
        Quillex.RadixCache.ViewStore.set_search_results_view(:tree)
        Quillex.RadixCache.ViewStore.sync()
        :ok = open_pane_with(context.root, "needle")

        assert wait_until(fn -> pane_state().results_view == :tree end)
        {:ok, context}
      end

      then_ "as a tree, the project's directories hold the files", context do
        kinds = pane_state() |> ScenicWidgets.SearchPane.State.rows() |> Enum.map(& &1.kind)

        assert :dir in kinds,
               "a tree keeps the shape of the project: #{inspect(Enum.uniq(kinds))}"

        assert :file in kinds, "with the files inside it: #{inspect(Enum.uniq(kinds))}"
        {:ok, context}
      end

      when_ "the view control is set to list", context do
        # It lives in the settings drawer now, as an either/or menu row, and
        # each position publishes its own name.
        :ok = choose_view(:list)

        assert wait_until(fn -> pane_state().results_view == :list end),
               "clicking the list position should show a list"

        {:ok, context}
      end

      then_ "as a list, the files run one after another with their paths", context do
        rows = pane_state() |> ScenicWidgets.SearchPane.State.rows()
        kinds = rows |> Enum.map(& &1.kind) |> Enum.uniq()

        refute :dir in kinds, "a list has no directories in it: #{inspect(kinds)}"
        assert :file in kinds and :match in kinds, "#{inspect(kinds)}"

        # Nothing above a row says where its file is, so the row says it.
        assert Enum.any?(rows, fn row ->
                 row.kind == :file and String.contains?(row.label, "/")
               end),
               "a file row should carry its path: #{inspect(Enum.map(rows, & &1.label))}"

        {:ok, context}
      end

      then_ "and the choice is a setting, kept with the others", context do
        # It lives in the view store, which is what Save Settings as Default
        # writes — so it survives the session rather than resetting to tree
        # every time the pane opens.
        assert Quillex.RadixCache.ViewStore.get_state().search_results_view == :list

        assert :search_results_view in Quillex.SettingsFile.persisted_keys(),
               "the view is one of the settings that can be saved"

        {:ok, context}
      end

      then_ "and setting it back to tree restores the directories", context do
        :ok = choose_view(:tree)
        assert wait_until(fn -> pane_state().results_view == :tree end)

        kinds = pane_state() |> ScenicWidgets.SearchPane.State.rows() |> Enum.map(& &1.kind)
        assert :dir in kinds and :file in kinds

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

      when_ "lib/ is unticked in the scope tree", context do
        # Narrowing a search is pointing at things, not writing a pattern for
        # them: the scope tree is the whole mechanism, and a directory takes
        # its subtree with it.
        ProjectSearchStore.toggle_scope(Path.join(context.root, "lib"))

        assert wait_until(fn ->
                 search_done?() and
                   not Enum.any?(results().files, fn {p, _} -> String.contains?(p, "/lib/") end)
               end),
               "unticking lib/ should remove every file under it"

        {:ok, context}
      end

      then_ "ticking it again brings them back", context do
        ProjectSearchStore.toggle_scope(Path.join(context.root, "lib"))

        assert wait_until(fn ->
                 search_done?() and
                   Enum.any?(results().files, fn {p, _} -> String.contains?(p, "/lib/") end)
               end)

        {:ok, context}
      end

      then_ "a single file can be unticked too, and only that file goes", context do
        [{victim, _} | _] = results().files
        others = results().files |> Enum.map(&elem(&1, 0)) |> Enum.reject(&(&1 == victim))

        ProjectSearchStore.toggle_scope(victim)

        assert wait_until(fn ->
                 search_done?() and
                   not Enum.any?(results().files, fn {p, _} -> p == victim end)
               end),
               "unticking #{Path.basename(victim)} should remove it from the results"

        remaining = Enum.map(results().files, &elem(&1, 0))

        for path <- others do
          assert path in remaining,
                 "excluding one file must not take #{Path.basename(path)} with it"
        end

        ProjectSearchStore.toggle_scope(victim)
        assert wait_until(fn -> search_done?() end)

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
               "an upper-case occurrence must not match a lower-case query — " <>
                 "cs=#{inspect(results().case_sensitive)} status=#{inspect(results().status)} " <>
                 "matched=#{inspect(Enum.flat_map(results().files, fn {_p, ms} -> Enum.map(ms, & &1.matched) end))}"

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
