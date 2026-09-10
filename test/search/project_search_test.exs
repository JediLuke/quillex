defmodule Quillex.Search.ProjectTest do
  use ExUnit.Case, async: false

  alias Quillex.Search.{Backend, Match, Project}
  alias Quillex.RadixCache.ProjectSearchStore

  setup do
    root =
      Path.join(System.tmp_dir!(), "qlx_project_search_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(root, "lib/deep"))
    File.mkdir_p!(Path.join(root, "vendor"))
    File.mkdir_p!(Path.join(root, "_build"))
    File.write!(Path.join(root, "lib/a.ex"), "the cat\nno match here\nTHE end — the\n")
    File.write!(Path.join(root, "lib/deep/b.txt"), "and yet the")
    File.write!(Path.join(root, "vendor/c.txt"), "the vendor")
    File.write!(Path.join(root, "_build/d.txt"), "the build")
    File.write!(Path.join(root, "bin.dat"), <<0, 1, 2, "the", 0>>)
    # Latin-1: no NUL bytes, but not UTF-8 — must be skipped, not crash the scan
    File.write!(Path.join(root, "latin1.txt"), <<"caf", 0xE9, " the">>)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root}
  end

  # `if @backend.available?()` inside each test means an absent backend reports
  # PASS while asserting nothing — the ripgrep half of this file is invisible
  # unless `rg` is installed. Say so once, out loud, so a green run cannot be
  # mistaken for coverage it does not have.
  test "ripgrep backend coverage is real on this machine" do
    if Backend.Ripgrep.available?() do
      assert true
    else
      IO.warn(
        "ripgrep is not installed: every Backend.Ripgrep test in this file " <>
          "passed without asserting anything. Install rg to cover that backend."
      )
    end
  end

  # Through a variable, so the type checker cannot see that the Elixir
  # backend's answer is always true and warn on every `if` in the loop.
  defp available?(backend), do: backend.available?()

  for backend <- [Backend.Elixir, Backend.Ripgrep] do
    @backend backend

    describe "#{inspect(backend)}" do
      test "finds every match with grapheme columns, in path order", %{root: root} do
        if available?(@backend) do
          {:ok, matches} = @backend.search(root, "the", [])

          assert Enum.map(
                   matches,
                   &{Path.relative_to(&1.path, root), &1.line, &1.col, &1.matched}
                 ) ==
                   [
                     {"lib/a.ex", 1, 1, "the"},
                     {"lib/a.ex", 3, 1, "THE"},
                     {"lib/a.ex", 3, 11, "the"},
                     {"lib/deep/b.txt", 1, 9, "the"},
                     {"vendor/c.txt", 1, 1, "the"}
                   ]

          assert %Match{text: "THE end — the"} = Enum.at(matches, 1)
        end
      end

      test "honours scope excludes and the max_results cap", %{root: root} do
        if available?(@backend) do
          {:ok, matches} = @backend.search(root, "the", excludes: [Path.join(root, "vendor")])
          refute Enum.any?(matches, &String.contains?(&1.path, "vendor"))

          {:ok, matches} = @backend.search(root, "the", excludes: ["lib/deep"])
          refute Enum.any?(matches, &String.contains?(&1.path, "deep"))

          {:ok, matches} = @backend.search(root, "the", max_results: 2)
          assert length(matches) == 2
        end
      end

      test "skips files that are not valid UTF-8", %{root: root} do
        if available?(@backend) do
          {:ok, matches} = @backend.search(root, "the", [])
          refute Enum.any?(matches, &String.ends_with?(&1.path, "latin1.txt"))
        end
      end

      test "an empty query matches nothing", %{root: root} do
        assert {:ok, []} = @backend.search(root, "", [])
      end

      # The two backends reach the same answers by completely different routes —
      # ripgrep flags versus a compiled Elixir regex — so the options are worth
      # asserting on both. A pane that means one thing under ripgrep and another
      # without it would be worse than having no toggles at all.
      test "case_sensitive matches only the exact casing", %{root: root} do
        if available?(@backend) do
          {:ok, matches} = @backend.search(root, "THE", case_sensitive: true)

          assert Enum.map(matches, &{Path.relative_to(&1.path, root), &1.line, &1.col}) ==
                   [{"lib/a.ex", 3, 1}]
        end
      end

      test "regex treats the query as a pattern, and does not by default", %{root: root} do
        if available?(@backend) do
          {:ok, literal} = @backend.search(root, "th.", [])
          assert literal == []

          {:ok, matches} = @backend.search(root, "th.", regex: true)
          assert Enum.map(matches, & &1.matched) |> Enum.uniq() |> Enum.sort() == ["THE", "the"]
        end
      end

      test "a pattern that will not compile is reported, not raised", %{root: root} do
        if available?(@backend) do
          assert {:error, {:bad_pattern, message}} = @backend.search(root, "foo(", regex: true)
          assert is_binary(message)
        end
      end
    end
  end

  test "Project.search groups by file", %{root: root} do
    {:ok, files} = Project.search(root, "the")

    assert Enum.map(files, fn {p, ms} -> {Path.basename(p), length(ms)} end) ==
             [{"a.ex", 3}, {"b.txt", 1}, {"c.txt", 1}]
  end

  test "Project.replace_all rewrites files on disk by grapheme column", %{root: root} do
    {:ok, files} = Project.search(root, "the")
    paths = Enum.map(files, &elem(&1, 0))

    assert {:ok, %{files: 3, matches: 5}} = Project.replace_all(paths, "the", "a")
    assert File.read!(Path.join(root, "lib/a.ex")) == "a cat\nno match here\na end — a\n"
    assert File.read!(Path.join(root, "vendor/c.txt")) == "a vendor"
    assert {:ok, []} = Project.search(root, "the")
  end

  test "Project.replace_matches touches exactly the matches it is given", %{root: root} do
    {:ok, files} = Project.search(root, "the")
    {a_path, [first | _rest]} = Enum.find(files, fn {p, _} -> Path.basename(p) == "a.ex" end)

    # One match out of the file's three: dismissal is the reason this exists,
    # and a replace that reached the other two would defeat it.
    assert {:ok, %{files: 1, matches: 1}} = Project.replace_matches([{a_path, [first]}], "a")
    assert File.read!(a_path) == "a cat\nno match here\nTHE end — the\n"
  end

  test "Project.replace_matches skips files with nothing selected", %{root: root} do
    path = Path.join(root, "vendor/c.txt")
    assert {:ok, %{files: 0, matches: 0}} = Project.replace_matches([{path, []}], "a")
    assert File.read!(path) == "the vendor"
  end

  test "an exclude glob narrows the search the same way for every backend", %{root: root} do
    {:ok, files} = Project.search(root, "the", exclude_globs: ["**/deep/**"])

    assert Enum.map(files, fn {p, _ms} -> Path.basename(p) end) == ["a.ex", "c.txt"]
  end

  # ── Files matching by NAME ────────────────────────────────────────────────
  #
  # They ride the same task and the same ref as the text search, so they
  # honour the same scope and a superseded search takes its filename answer
  # down with it. They are published apart from `files` on purpose: `files` is
  # what every replace path acts on, and a filename is not a thing a text
  # replacement can touch.

  defp filename_labels(snapshot), do: Enum.map(snapshot.filename_matches, & &1.label)

  defp wait_for_closed(ref, attempts \\ 100) do
    cond do
      not Enum.any?(Quillex.Buffer.list(), &(&1.uuid == ref.uuid)) ->
        :ok

      attempts == 0 ->
        :ok

      true ->
        Process.sleep(10)
        wait_for_closed(ref, attempts - 1)
    end
  end

  test "a filename match is published even when nothing in the project contains the query",
       %{root: root} do
    # "latin" is in no file's TEXT — latin1.txt holds "café the" — so this is
    # the whole answer, and it comes from the walk alone.
    ProjectSearchStore.set_root(root)
    ProjectSearchStore.set_query("latin")
    :ok = ProjectSearchStore.await_idle()

    snapshot = eventually(&match?(%{status: {:done, 0, 0, _}}, &1))
    assert snapshot.files == []
    assert filename_labels(snapshot) == ["latin1.txt"]
  end

  test "filename matches never enter the results a replace acts on", %{root: root} do
    ProjectSearchStore.set_root(root)
    ProjectSearchStore.set_query("latin")
    :ok = ProjectSearchStore.await_idle()
    snapshot = eventually(&(&1.filename_matches != []))

    refute Enum.any?(snapshot.files, fn {path, _} -> Path.basename(path) == "latin1.txt" end),
           "a filename match must not appear in `files`, which is what Replace All acts on"
  end

  test "emptying the query takes the filename answer down with it", %{root: root} do
    ProjectSearchStore.set_root(root)
    ProjectSearchStore.set_query("latin")
    :ok = ProjectSearchStore.await_idle()
    assert eventually(&(&1.filename_matches != [])).filename_matches != []

    # Nothing is being searched any more, so nothing may still be answering.
    ProjectSearchStore.set_query("")
    :ok = ProjectSearchStore.await_idle()
    assert eventually(&(&1.status == :idle)).filename_matches == []
  end

  test "a new query's filename answer replaces the last one's", %{root: root} do
    ProjectSearchStore.set_root(root)
    ProjectSearchStore.set_query("latin")
    :ok = ProjectSearchStore.await_idle()
    assert eventually(&(&1.filename_matches != [])).filename_matches != []

    # "the" is in every file's text and in no file's name.
    ProjectSearchStore.set_query("the")
    :ok = ProjectSearchStore.await_idle()
    snapshot = eventually(&match?(%{status: {:done, 5, _, _}}, &1))
    assert snapshot.filename_matches == []
  end

  test "filename matches honour the scope tree, exactly as the text search does", %{root: root} do
    ProjectSearchStore.set_root(root)
    ProjectSearchStore.set_query("b")
    :ok = ProjectSearchStore.await_idle()

    assert eventually(&(length(&1.filename_matches) == 2)) |> filename_labels() |> Enum.sort() ==
             ["bin.dat", "lib/deep/b.txt"]

    ProjectSearchStore.toggle_scope(Path.join(root, "lib"))
    :ok = ProjectSearchStore.await_idle()

    assert eventually(&(length(&1.filename_matches) == 1)) |> filename_labels() == ["bin.dat"],
           "unticking lib must take lib/deep/b.txt out of the names as well as the text"
  end

  test "scoped to open buffers, only the open buffers are named", %{root: root} do
    open_path = Path.join(root, "lib/deep/b.txt")
    {:ok, %{buffer_ref: ref}} = Quillex.API.FileAPI.open(open_path)

    # The store is a singleton and this option is sticky: put it back even if
    # the assertion below never runs, or every later test in this file
    # searches nothing but the open buffers.
    on_exit(fn ->
      if ProjectSearchStore.get_state().open_buffers_only,
        do: ProjectSearchStore.toggle_option(:open_buffers_only)

      ProjectSearchStore.sync()

      # And wait for the buffer to be GONE, not merely told to go. Anything
      # that walks `Quillex.Buffer.list()` and then calls the processes it
      # names — the external-file watcher does — falls over a ref whose
      # process died between the two, and it does it in whichever test file
      # happens to run next.
      Quillex.Buffer.close(ref, :discard)
      wait_for_closed(ref)
    end)

    ProjectSearchStore.set_root(root)
    ProjectSearchStore.toggle_option(:open_buffers_only)
    ProjectSearchStore.set_query("b")
    :ok = ProjectSearchStore.await_idle()

    assert eventually(&(&1.filename_matches != [])) |> filename_labels() == ["lib/deep/b.txt"],
           "bin.dat is not open, so its name is not in scope either"
  end

  test "the section is a signpost, not a directory listing: it is capped", %{root: root} do
    Enum.each(1..150, &File.write!(Path.join(root, "capped_#{&1}.txt"), ""))

    ProjectSearchStore.set_root(root)
    ProjectSearchStore.set_query("capped_")
    :ok = ProjectSearchStore.await_idle()

    # A one-letter query names most of a project; the store takes the first
    # hundred and stops.
    assert length(eventually(&(length(&1.filename_matches) == 100)).filename_matches) == 100
  end

  test "the store keeps skipped matches visible and excludes them from replace", %{root: root} do
    ProjectSearchStore.set_root(root)
    ProjectSearchStore.set_query("the")
    :ok = ProjectSearchStore.await_idle()
    assert {:done, 5, 3, _} = eventually(&match?(%{status: {:done, 5, _, _}}, &1)).status

    a_path = Path.join(root, "lib/a.ex")
    ProjectSearchStore.dismiss_match(a_path, 1, 1)
    ProjectSearchStore.sync()

    snapshot = eventually(&(MapSet.size(&1.dismissed) == 1))
    assert {:done, 5, 3, _} = snapshot.status

    assert Enum.any?(snapshot.files, fn {_path, matches} ->
             Enum.any?(matches, &({&1.path, &1.line, &1.col} == {a_path, 1, 1}))
           end)

    ProjectSearchStore.replace_all("a")
    :ok = ProjectSearchStore.await_idle()

    # The dismissed occurrence is the only "the" left in the file.
    assert File.read!(a_path) == "the cat\nno match here\na end — a\n"
  end

  test "project navigation selects exact matches and wraps", %{root: root} do
    ProjectSearchStore.set_root(root)
    ProjectSearchStore.set_query("the")
    :ok = ProjectSearchStore.await_idle()
    snapshot = eventually(&match?(%{status: {:done, 5, _, _}}, &1))
    all = for {_path, matches} <- snapshot.files, match <- matches, do: match

    assert ProjectSearchStore.select_match(
             List.last(all).path,
             List.last(all).line,
             List.last(all).col
           ) ==
             List.last(all)

    assert ProjectSearchStore.select_next() == List.first(all)
    assert ProjectSearchStore.select_previous() == List.last(all)
  end

  test "a descendant can be re-enabled beneath an excluded root", %{root: root} do
    wanted = Path.join(root, "lib/a.ex")
    ProjectSearchStore.set_root(root)
    ProjectSearchStore.set_query("the")
    ProjectSearchStore.toggle_scope(root)
    :ok = ProjectSearchStore.await_idle()
    assert {:done, 0, 0, _} = eventually(&match?(%{status: {:done, 0, 0, _}}, &1)).status

    ProjectSearchStore.toggle_scope(wanted)
    :ok = ProjectSearchStore.await_idle()
    snapshot = eventually(&match?(%{status: {:done, 2, 1, _}}, &1))
    assert Enum.map(snapshot.files, &elem(&1, 0)) == [wanted]
  end

  test "re-enabling a directly excluded directory clears every exclusion below it", %{root: root} do
    child = Path.join(root, "lib/a.ex")
    ProjectSearchStore.set_root(root)
    ProjectSearchStore.set_query("the")

    ProjectSearchStore.toggle_scope(child)
    ProjectSearchStore.toggle_scope(root)
    :ok = ProjectSearchStore.await_idle()
    assert MapSet.member?(ProjectSearchStore.get_state().excluded, child)

    ProjectSearchStore.toggle_scope(root)
    :ok = ProjectSearchStore.await_idle()

    snapshot = eventually(&match?(%{status: {:done, 5, _, _}}, &1))
    assert snapshot.excluded == MapSet.new()
  end

  test "dismissals are cleared when the query changes, not when a replace re-runs",
       %{root: root} do
    ProjectSearchStore.set_root(root)
    ProjectSearchStore.set_query("the")
    :ok = ProjectSearchStore.await_idle()
    eventually(&match?(%{status: {:done, 5, _, _}}, &1))

    ProjectSearchStore.dismiss_file(Path.join(root, "vendor/c.txt"))
    ProjectSearchStore.sync()

    assert eventually(&(MapSet.size(&1.dismissed_files) == 1)).dismissed_files |> MapSet.size() ==
             1

    ProjectSearchStore.set_query("cat")
    :ok = ProjectSearchStore.await_idle()
    assert eventually(&(MapSet.size(&1.dismissed_files) == 0)).dismissed_files == MapSet.new()
  end

  test "the store searches asynchronously and publishes grouped results", %{root: root} do
    ProjectSearchStore.set_root(root)
    ProjectSearchStore.set_query("the")
    :ok = ProjectSearchStore.await_idle()

    snapshot = eventually(&match?(%{status: {:done, _, _, _}}, &1))
    assert snapshot.root == root
    assert snapshot.query == "the"
    assert {:done, 5, 3, _ms} = snapshot.status

    ProjectSearchStore.toggle_scope(Path.join(root, "vendor"))
    :ok = ProjectSearchStore.await_idle()
    assert {:done, 4, 2, _ms} = eventually(&match?(%{status: {:done, 4, _, _}}, &1)).status

    ProjectSearchStore.set_query("")
    :ok = ProjectSearchStore.await_idle()
    assert eventually(&match?(%{status: :idle}, &1)).status == :idle
  end

  # Scenic.PubSub.publish is a send; the retained ETS value lands a moment
  # after the store's reply. Poll for the snapshot we expect.
  defp eventually(predicate, attempts \\ 100) do
    snapshot = ProjectSearchStore.get_state()

    cond do
      predicate.(snapshot) ->
        snapshot

      attempts == 0 ->
        snapshot

      true ->
        Process.sleep(10)
        eventually(predicate, attempts - 1)
    end
  end
end
