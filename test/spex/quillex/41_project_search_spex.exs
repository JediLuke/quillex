defmodule Quillex.ProjectSearchSpex do
  @moduledoc """
  Phase 41: Project-wide find and replace.

  Ctrl+Shift+F opens the top-right find popup AND a results pane in the
  sidebar slot; the popup's query drives both the active buffer and the
  project search. Rows open files at the match; the SCOPE tree ticks
  directories in and out; "All" in replace mode rewrites the whole project.
  """
  use SexySpex
  @moduletag timeout: 300_000

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.AppReset
  alias Quillex.RadixCache.ProjectSearchStore

  defp root_state, do: :sys.get_state(Process.whereis(QuillEx.RootScene)).assigns.state

  defp pane_state do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, [pid | _]} = Scenic.Scene.child(root, :buffer_pane)
    :sys.get_state(pid, 30_000).assigns.state
  end

  # Click on the text of a sidebar row (not its chevron), from the SideNav's
  # own layout. Rows can be wider than the pane, so their semantic centre is
  # not a safe place to click.
  defp click_row(item_id) do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, [pid | _]} = Scenic.Scene.child(root, :project_search_pane)
    st = :sys.get_state(pid).assigns.state
    %{y: y} = Map.fetch!(st.item_bounds, item_id)
    {px, py} = st.frame.pin.point
    {_tx, ty} = Widgex.Scroll.ScrollState.translate_offset(st.scroll)
    Probes.click(px + 110, trunc(py + ty + y + st.theme.item_height / 2))
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

  defp results, do: root_state().project_search

  setup_all do
    {:ok, _} = Application.ensure_all_started(:quillex)
    Process.sleep(1_000)
    AppReset.reset!()

    root = Path.expand("test/support/project_search_fixture")
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

    Quillex.RadixCache.ViewStore.set_file_nav_path(root)
    Process.sleep(300)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root}
  end

  spex "Ctrl+Shift+F searches the whole project from the find popup",
    description: "One query, two searches: the popup drives the buffer and the sidebar",
    tags: [:phase_41, :project_search, :find] do
    scenario "opening, typing, visiting a result, scoping, closing" do
      when_ "Ctrl+Shift+F is pressed and a query typed", context do
        Probes.click(800, 300)
        Process.sleep(100)
        Probes.send_keys("f", [:ctrl, :shift])
        Process.sleep(400)

        st = root_state()
        assert st.show_search_bar, "the find popup should open"
        assert st.show_project_search, "the project-search pane should open"

        Probes.send_text("needle")

        assert wait_until(fn -> match?(%{status: {:done, _, _, _}}, results()) end),
               "the project search should finish"

        {:ok, context}
      end

      then_ "results are grouped by file and skip build directories", context do
        %{status: {:done, matches, files, _ms}, files: grouped} = results()
        assert matches == 8
        assert files == 3
        refute Enum.any?(grouped, fn {path, _} -> String.contains?(path, "_build") end)

        Probes.take_screenshot("41_project_search_results")
        {:ok, context}
      end

      then_ "clicking a result opens that file at the match", context do
        %{files: grouped} = results()

        {path, [%{line: line, col: col} | _]} =
          Enum.find(grouped, fn {p, _} -> String.ends_with?(p, "README.md") end)

        click_row("qlx-search://match/#{line}/#{col}/#{path}")

        assert wait_until(fn ->
                 st = root_state()
                 st.active_buf && st.active_buf.name == "README.md"
               end),
               "README.md should become the active buffer"

        assert wait_until(fn -> pane_state().cursor == {line, col} end),
               "the cursor should sit on the match"

        # The popup stays: browsing results is the point of the pane
        assert root_state().show_search_bar
        {:ok, context}
      end

      then_ "Escape closes the popup but leaves the results pane", context do
        Probes.send_keys("escape", [])
        Process.sleep(300)
        st = root_state()
        refute st.show_search_bar
        assert st.show_project_search
        {:ok, context}
      end

      then_ "unticking a directory in SCOPE narrows the search", context do
        Probes.click_element("chevron_qlx-search://scope")
        Process.sleep(300)
        click_row("qlx-search://scope/#{context.root}/lib")

        assert wait_until(fn -> match?(%{status: {:done, 2, 1, _}}, results()) end),
               "excluding lib/ should leave README's two matches"

        assert MapSet.member?(results().excluded, Path.join(context.root, "lib"))
        Probes.take_screenshot("41_project_search_scoped")
        {:ok, context}
      end

      then_ "Ctrl+Shift+H reopens the popup in replace mode with the pane's query", context do
        Probes.click(800, 400)
        Process.sleep(100)
        Probes.send_keys("h", [:ctrl, :shift])
        Process.sleep(400)
        st = root_state()
        assert st.show_search_bar and st.show_replace
        assert st.search_query == "needle"
        {:ok, context}
      end

      then_ "Replace All rewrites every in-scope match across the project", context do
        # Tab moves from the find field to the replace field
        Probes.send_keys("tab", [])
        Process.sleep(100)
        Probes.send_text("pin")
        Process.sleep(150)
        Probes.click_element("replace_all_btn_bg")

        assert wait_until(fn ->
                 (root_state().status_message || "") =~ "Replaced 2 matches in 1 file"
               end),
               "the status bar should report the project replace"

        # README is open (and was clean): edited through its buffer, now dirty
        {:ok, buf} = Quillex.Buffer.Process.fetch_buf(root_state().active_buf)
        assert buf.data == ["# fixture", "no pins? yes pin"]
        assert buf.dirty?
        # lib/ was out of scope: untouched on disk
        assert File.read!(Path.join(context.root, "lib/deep/beta.txt")) =~ "needle"
        {:ok, context}
      end

      then_ "the close row hides the pane", context do
        Probes.send_keys("escape", [])
        Process.sleep(200)
        click_row("qlx-search://close")
        assert wait_until(fn -> not root_state().show_project_search end)
        ProjectSearchStore.sync()
        {:ok, context}
      end
    end
  end
end
