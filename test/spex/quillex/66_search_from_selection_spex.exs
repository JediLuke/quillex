defmodule Quillex.SearchFromSelectionSpex do
  @moduledoc """
  Highlight a word, press find, and it is already in the box.

  This is how you read code: you see a symbol, you want its other references,
  and you double-click it and press Ctrl+Shift+F. Before this, both find bars
  seeded from the word under the CURSOR — which a double-click does leave in
  roughly the right place — but the project search preferred whatever it had
  last searched for, so the second time you did it you got the previous
  symbol, and the third time too. The one case the feature exists for was the
  one case it did not work.

  Selection wins over both. A person who has just highlighted a word has
  answered the question; anything remembered is a worse answer to it.
  """
  use SexySpex
  @moduletag timeout: 300_000

  alias ScenicMcp.Probes
  alias ScenicMcp.Query
  alias Quillex.TestHelpers.AppReset

  @word "haystack"
  @other "needle"

  defp pane_scene do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))

    case Scenic.Scene.child(root, :project_search_pane) do
      {:ok, [pid | _]} -> :sys.get_state(pid, 30_000)
      _ -> nil
    end
  end

  defp pane_open?, do: pane_scene() != nil
  defp pane_query, do: pane_scene().assigns.state.query

  defp search_bar_query do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))

    case Scenic.Scene.child(root, :search_bar) do
      {:ok, [pid | _]} -> :sys.get_state(pid, 30_000).assigns.state.query
      _ -> nil
    end
  end

  defp buffer_selection do
    state = :sys.get_state(Process.whereis(QuillEx.RootScene)).assigns.state

    with ref when not is_nil(ref) <- state.active_buf,
         {:ok, buf} <- Quillex.Buffer.Process.fetch_buf(ref) do
      Quillex.Buffer.Core.Selection.selected_text(buf)
    else
      _ -> ""
    end
  end

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

  defp write_fixture(root) do
    File.rm_rf!(root)
    File.mkdir_p!(Path.join(root, "lib"))

    # The word alone on the first line, so a selection can be made from a known
    # place — Ctrl+Home then Shift+Ctrl+Right — instead of from coordinates
    # guessed against a gutter.
    File.write!(
      Path.join(root, "lib/subject.ex"),
      """
      #{@word}
      defmodule Subject do
        def #{@word}(x), do: x
        def other(y), do: #{@other}(y)
      end
      """
    )

    File.write!(Path.join(root, "lib/elsewhere.ex"), "  # #{@word} again\n")
    :ok
  end

  # Highlight the word. Double-clicking is how a person does it, and that it
  # selects a word is 56_selection_and_mouse's business; what THIS spex is
  # about is what happens next, so the selection is made from a known place
  # rather than from coordinates guessed against a gutter.
  defp select_word_in_buffer do
    assert wait_until(fn -> Query.text_visible?(@word) end), "the fixture is not on screen"

    click_into_buffer()
    Probes.send_keys("home", [:ctrl])
    Process.sleep(150)

    # Shift+Right a character at a time. Ctrl+Shift+Right is what a person
    # presses, and it selects a word now — see test/word_selection_test.exs.
    # The driver cannot send that chord: it passes [:ctrl, :shift] and Scenic
    # hands the component [:shift]. HOW the selection is made is not what this
    # spex is about, so it is made a way the driver can manage.
    Enum.each(1..String.length(@word), fn _ ->
      Probes.send_keys("right", [:shift])
      Process.sleep(40)
    end)

    Process.sleep(300)
    :ok
  end

  # The pointer has to have been in the pane before the keyboard means
  # anything to it — the same precondition 56_selection_and_mouse documents.
  defp click_into_buffer do
    %{x: fx, y: fy} = Quillex.TestHelpers.SemanticHelpers.get_buffer_frame()
    Probes.click(trunc(fx + 70), trunc(fy + 16))
    Process.sleep(200)
  end

  setup_all do
    {:ok, _} = Application.ensure_all_started(:quillex)
    Process.sleep(1_000)
    AppReset.reset!()

    root = Path.join(System.tmp_dir!(), "quillex_search_from_selection")
    write_fixture(root)

    on_exit(fn ->
      Quillex.RadixCache.ViewStore.set_file_nav_path(File.cwd!())
      Process.sleep(200)
      File.rm_rf!(root)
    end)

    {:ok, root: root}
  end

  spex "Finding what you have highlighted",
    description: "Select a word in a buffer; find and project search open holding it",
    tags: [:phase_41, :project_search, :find, :selection] do
    scenario "project search, from a selection" do
      given_ "a file open with the word in it, and a previous search remembered", context do
        write_fixture(context.root)
        AppReset.reset!()
        Quillex.RadixCache.ViewStore.set_file_nav_path(context.root)
        Process.sleep(300)

        :ok = Quillex.TestHelpers.FileOpener.open_file(Path.join(context.root, "lib/subject.ex"))
        Process.sleep(500)

        # The case that used to fail: something already in the box.
        Quillex.RadixCache.ProjectSearchStore.set_query(@other)
        Quillex.RadixCache.ProjectSearchStore.sync()

        {:ok, context}
      end

      when_ "the word is double-clicked and Ctrl+Shift+F pressed", context do
        :ok = select_word_in_buffer()

        assert buffer_selection() != "",
               "nothing got selected, so the rest of this would prove nothing"

        Probes.send_keys("f", [:ctrl, :shift])
        assert wait_until(fn -> pane_open?() end), "Ctrl+Shift+F did not open the pane"

        {:ok, Map.put(context, :selected, buffer_selection())}
      end

      then_ "the pane opens already searching for it", context do
        assert wait_until(fn -> pane_query() == String.trim(context.selected) end),
               """
               the pane opened searching for #{inspect(pane_query())} where the
               selection was #{inspect(context.selected)}.
               """

        refute pane_query() == @other,
               "it used the query it remembered instead of the one just highlighted"

        {:ok, context}
      end

      then_ "and found it in the project", context do
        assert wait_until(fn ->
                 match?({:done, n, _f, _ms} when n > 0,
                        Quillex.RadixCache.ProjectSearchStore.get_state().status)
               end),
               "the seeded query never ran"

        {:ok, context}
      end
    end

    scenario "the find bar, from a selection" do
      given_ "the pane closed and the word selected again", context do
        Probes.send_keys("escape", [])
        Process.sleep(300)
        assert wait_until(fn -> not pane_open?() end), "the pane would not close"

        :ok = select_word_in_buffer()
        assert buffer_selection() != "", "nothing got selected"

        {:ok, Map.put(context, :selected, buffer_selection())}
      end

      when_ "Ctrl+F is pressed", context do
        Probes.send_keys("f", [:ctrl])
        Process.sleep(500)
        {:ok, context}
      end

      then_ "the find bar opens holding it too", context do
        assert wait_until(fn -> search_bar_query() == String.trim(context.selected) end),
               """
               the find bar opened holding #{inspect(search_bar_query())} where
               the selection was #{inspect(context.selected)}.
               """

        {:ok, context}
      end
    end
  end
end
