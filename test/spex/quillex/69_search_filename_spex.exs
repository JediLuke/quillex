defmodule Quillex.SearchFilenameSpex do
  @moduledoc """
  Finding a file by its NAME, in the two places that answer that question.

  `Ctrl+P` opens a quick-open popup: type part of a file's name, get the
  files that are called that, Enter opens one. It is scene-owned, exactly
  like Go to Line — RootScene collects the keystrokes and draws the prompt
  itself — so the thing worth checking is not that it filters (that is
  `Quillex.Search.FilenameTest`, off-screen and exact) but that it OWNS THE
  KEYBOARD while it is up and gives it back on every way out. A popup that
  quietly leaks its query into the document is the failure that matters.

  The project search pane answers the same question a second way, as a
  "Files matching by name" group beside the text results. Those rows are for
  finding your way to a file and nothing more: they are kept out of the
  store's `files`, which is what every replace path acts on, and a filename
  is not a thing a text replacement can touch.
  """
  use SexySpex
  @moduletag timeout: 300_000

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.AppReset
  alias Quillex.RadixCache.ProjectSearchStore
  alias Quillex.GUI.SearchPaneModel
  import Quillex.TestHelpers.Integration, only: [ensure_editor_focused: 0]

  defp root_state, do: :sys.get_state(Process.whereis(Quillex.RootScene)).assigns.state

  defp pane_state do
    root = :sys.get_state(Process.whereis(Quillex.RootScene))
    {:ok, [pid | _]} = Scenic.Scene.child(root, :project_search_pane)
    :sys.get_state(pid, 30_000).assigns.state
  end

  defp finder_labels, do: Enum.map(root_state().file_finder_results, & &1.label)

  defp active_path, do: root_state().active_buf && root_state().active_buf.path

  defp document_lines do
    case root_state().active_buf do
      nil ->
        []

      ref ->
        {:ok, %{lines: lines}} = Quillex.Buffer.fetch(ref)
        lines
    end
  end

  defp wait_until(predicate, timeout \\ 5_000) do
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

  # Names chosen so a prefix picks out a known pair in a known order, and so
  # nothing here can be confused with a file of the editor's own.
  defp write_fixture(root) do
    File.rm_rf!(root)

    %{
      "lib/quicksilver.ex" => "defmodule Quicksilver do\n  # mercury\nend\n",
      "lib/deep/quicksand.txt" => "just sand\n",
      "notes/quill.md" => "a quill and some ink\n",
      "README.md" => "nothing to see here\n"
    }
    |> Enum.each(fn {path, contents} ->
      full = Path.join(root, path)
      File.mkdir_p!(Path.dirname(full))
      File.write!(full, contents)
    end)

    :ok
  end

  defp close_fixture_buffers(root) do
    Quillex.Buffer.list()
    |> Enum.filter(&(is_binary(&1.path) and String.starts_with?(&1.path, root)))
    |> Enum.each(&Quillex.Buffer.close(&1, :discard))

    Process.sleep(250)
  end

  # The popup lists the project the file navigator is pointing at, so that is
  # what has to be set — and the root scene learns it by broadcast, not by
  # return value, so it has to be waited for.
  defp point_at_fixture(root) do
    AppReset.reset!()
    close_fixture_buffers(root)
    Quillex.RadixCache.ViewStore.set_file_nav_path(root)
    true = wait_until(fn -> root_state().file_nav_path == root end)
    ensure_editor_focused()
    Process.sleep(200)
    :ok
  end

  defp dismiss_finder do
    if root_state().show_file_finder do
      Probes.send_keys("escape", [])
      Process.sleep(300)
    end

    :ok
  end

  setup_all do
    {:ok, _} = Application.ensure_all_started(:quillex)
    Process.sleep(1_000)
    AppReset.reset!()

    # NOT under test/support, which is compiled into the test build: a run
    # interrupted before its on_exit would leave .ex files full of deliberate
    # nonsense where `mix test` tries to compile them.
    root = Path.join(System.tmp_dir!(), "quillex_search_filename_fixture")
    write_fixture(root)

    on_exit(fn ->
      Quillex.RadixCache.ViewStore.set_file_nav_path(File.cwd!())
      Process.sleep(200)
      File.rm_rf!(root)
    end)

    {:ok, root: root}
  end

  spex "Ctrl+P opens a file by name",
    description: "Type part of a name, get the files called that, Enter opens one",
    tags: [:phase_69, :navigation, :search_filename] do
    scenario "the popup opens, filters, and opens the chosen file" do
      given_ "a project of distinctive filenames and a focused editor", context do
        write_fixture(context.root)
        point_at_fixture(context.root)
        refute root_state().show_file_finder
        {:ok, context}
      end

      when_ "Ctrl+P is pressed", context do
        before = document_lines()
        Probes.send_keys("p", [:ctrl])
        Process.sleep(400)

        assert root_state().show_file_finder, "Ctrl+P did not open the Search Filename popup"

        assert root_state().keyboard_owner == :file_finder,
               "the popup must become the sole keyboard owner"

        # The keystroke that opened it must not also land in it.
        assert root_state().file_finder_input == ""

        # The listing is taken ONCE, here — a keystroke filters it, it never
        # walks the tree again.
        assert root_state().file_finder_index != [],
               "the popup opened without listing the project"

        {:ok, Map.put(context, :before_lines, before)}
      end

      when_ "part of a file's name is typed", context do
        Probes.send_text("quicks")
        Process.sleep(400)
        {:ok, context}
      end

      then_ "the matching files are offered, nearest name first", context do
        assert root_state().file_finder_input == "quicks"

        assert finder_labels() == ["lib/quicksilver.ex", "lib/deep/quicksand.txt"],
               "got #{inspect(finder_labels())}"

        assert document_lines() == context.before_lines,
               "typing into the popup must leave the document byte-for-byte unchanged"

        {:ok, context}
      end

      then_ "Enter opens the first of them and hands the keyboard back", context do
        Probes.send_keys("enter", [])
        Process.sleep(700)

        expected = Path.join(context.root, "lib/quicksilver.ex")
        assert wait_until(fn -> active_path() == expected end), "landed on #{active_path()}"

        refute root_state().show_file_finder
        assert root_state().keyboard_owner == :buffer

        assert root_state().file_finder_index == [],
               "the listing should not outlive the popup that took it"

        {:ok, context}
      end
    end

    scenario "the arrows choose a file other than the first" do
      given_ "the popup showing both quick- files", context do
        point_at_fixture(context.root)
        Probes.send_keys("p", [:ctrl])
        Process.sleep(400)
        Probes.send_text("quicks")
        Process.sleep(400)
        assert length(root_state().file_finder_results) == 2
        assert root_state().file_finder_selected == 0
        {:ok, context}
      end

      when_ "the selection is moved down and Enter pressed", context do
        Probes.send_keys("down", [])
        Process.sleep(250)
        assert root_state().file_finder_selected == 1
        Probes.send_keys("enter", [])
        Process.sleep(700)
        {:ok, context}
      end

      then_ "the second file is the one that opened", context do
        expected = Path.join(context.root, "lib/deep/quicksand.txt")
        assert wait_until(fn -> active_path() == expected end), "landed on #{active_path()}"
        refute root_state().show_file_finder
        {:ok, context}
      end
    end

    scenario "Escape abandons it and the editor gets the keyboard back" do
      given_ "a file open and the popup up over it", context do
        point_at_fixture(context.root)
        Probes.send_keys("p", [:ctrl])
        Process.sleep(400)
        Probes.send_text("quill")
        Process.sleep(300)
        assert root_state().file_finder_results != []
        {:ok, Map.merge(context, %{path_before: active_path(), lines_before: document_lines()})}
      end

      when_ "Escape is pressed", context do
        Probes.send_keys("escape", [])
        Process.sleep(400)
        {:ok, context}
      end

      then_ "nothing opened and the query was thrown away", context do
        refute root_state().show_file_finder
        assert root_state().keyboard_owner == :buffer
        assert root_state().file_finder_input == ""
        assert active_path() == context.path_before
        {:ok, context}
      end

      then_ "and the editor answers to the keyboard again", context do
        ensure_editor_focused()
        Process.sleep(200)
        Probes.send_text("Z")
        Process.sleep(400)

        assert wait_until(fn -> document_lines() != context.lines_before end),
               "the editor never got the keyboard back after the popup closed"

        {:ok, context}
      end
    end

    scenario "the close button and a click outside both dismiss it" do
      given_ "the popup open", context do
        point_at_fixture(context.root)
        Probes.send_keys("p", [:ctrl])
        Process.sleep(400)
        assert root_state().show_file_finder
        {:ok, context}
      end

      when_ "its close button is clicked", context do
        Probes.click_element("file_finder_close")
        Process.sleep(400)
        {:ok, context}
      end

      then_ "the popup is gone and the keyboard is the editor's", context do
        refute root_state().show_file_finder
        assert root_state().keyboard_owner == :buffer
        {:ok, context}
      end

      when_ "it is opened again and clicked away from", context do
        Probes.send_keys("p", [:ctrl])
        Process.sleep(400)
        assert root_state().show_file_finder

        # Bottom-left of the window: the popup is a narrow strip at the top
        # centre, so nothing of it is anywhere near here.
        Probes.click(30, round(root_state().frame.size.height - 60))
        Process.sleep(400)
        {:ok, context}
      end

      then_ "clicking outside dismisses it too", context do
        refute root_state().show_file_finder
        assert root_state().keyboard_owner == :buffer
        {:ok, context}
      end
    end

    scenario "a row can simply be clicked" do
      given_ "the popup showing both quick- files", context do
        point_at_fixture(context.root)
        Probes.send_keys("p", [:ctrl])
        Process.sleep(400)
        Probes.send_text("quicks")
        Process.sleep(400)
        assert length(root_state().file_finder_results) == 2
        {:ok, context}
      end

      when_ "the second row is clicked", context do
        Probes.click_element("file_finder_row_1")
        Process.sleep(700)
        {:ok, context}
      end

      then_ "that file opens", context do
        expected = Path.join(context.root, "lib/deep/quicksand.txt")
        assert wait_until(fn -> active_path() == expected end), "landed on #{active_path()}"
        refute root_state().show_file_finder
        {:ok, context}
      end
    end

    scenario "it is discoverable in the Edit menu, not only by shortcut" do
      given_ "no popup open", context do
        point_at_fixture(context.root)
        refute root_state().show_file_finder
        {:ok, context}
      end

      when_ "Edit → Search Filename is chosen", context do
        Probes.click_element("icon_menu_edit")
        Process.sleep(300)
        Probes.click_element("icon_menu_edit_search_filename")
        Process.sleep(500)
        {:ok, context}
      end

      then_ "the popup opens and owns the keyboard", context do
        assert root_state().show_file_finder,
               "Search Filename must be reachable from the Edit menu, not only via Ctrl+P"

        assert root_state().keyboard_owner == :file_finder
        dismiss_finder()
        {:ok, context}
      end
    end
  end

  spex "A file whose NAME matches shows up in the project search",
    description: "Its own group, apart from the text results a replace acts on",
    tags: [:phase_69, :project_search, :search_filename] do
    scenario "searching for something that is both a word and a filename" do
      given_ "the project search pane open on the fixture", context do
        write_fixture(context.root)
        AppReset.reset!()
        close_fixture_buffers(context.root)
        Quillex.RadixCache.ViewStore.set_file_nav_path(context.root)
        Process.sleep(200)
        ProjectSearchStore.set_option(:case_sensitive, false)
        ProjectSearchStore.set_option(:regex, false)
        ProjectSearchStore.set_root(context.root)
        ProjectSearchStore.set_query("")
        Quillex.RadixCache.ViewStore.open_project_search()
        Process.sleep(400)
        {:ok, context}
      end

      when_ "a query that is a word in one file and the NAME of it is run", context do
        ProjectSearchStore.set_query("quill")

        Scenic.Scene.put_child(
          :sys.get_state(Process.whereis(Quillex.RootScene)),
          :project_search_pane,
          {:set_query, "quill"}
        )

        :ok = ProjectSearchStore.await_idle()

        assert wait_until(fn ->
                 Enum.any?(pane_state().model.files, &(&1.path == filename_group_path()))
               end),
               "the pane never drew a Files matching by name group: " <>
                 inspect(Enum.map(pane_state().model.files, & &1.path))

        {:ok, context}
      end

      then_ "the name group is drawn first, and is not one of the text results", context do
        [first | _] = pane_state().model.files
        assert first.path == filename_group_path()
        assert first.label == "Files matching by name"

        assert Enum.map(first.matches, & &1.line) == [1],
               "a filename row carries an index, not a line number"

        # The half that matters: `files` is what Replace All acts on, and a
        # filename is not a thing a text replacement can touch.
        store_paths = Enum.map(ProjectSearchStore.get_state().files, &elem(&1, 0))
        refute filename_group_path() in store_paths

        assert Enum.map(ProjectSearchStore.get_state().filename_matches, & &1.label) == [
                 "notes/quill.md"
               ]

        {:ok, context}
      end

      then_ "clicking one of its rows opens the file it names", context do
        Probes.click_element("search_pane_match_1_1_#{filename_group_path()}")
        Process.sleep(700)

        expected = Path.join(context.root, "notes/quill.md")
        assert wait_until(fn -> active_path() == expected end), "landed on #{active_path()}"

        {:ok, context}
      end

      then_ "and a query that names nothing leaves the group out", context do
        ProjectSearchStore.set_query("mercury")

        Scenic.Scene.put_child(
          :sys.get_state(Process.whereis(Quillex.RootScene)),
          :project_search_pane,
          {:set_query, "mercury"}
        )

        :ok = ProjectSearchStore.await_idle()

        assert wait_until(fn ->
                 not Enum.any?(pane_state().model.files, &(&1.path == filename_group_path()))
               end),
               "no file is CALLED mercury, so there should be no name group at all"

        # But the word is in a file, so the text results are still there.
        assert wait_until(fn -> ProjectSearchStore.get_state().files != [] end)

        Quillex.RadixCache.ViewStore.close_project_search()
        Process.sleep(300)
        {:ok, context}
      end
    end
  end

  defp filename_group_path, do: SearchPaneModel.filename_matches_path()
end
