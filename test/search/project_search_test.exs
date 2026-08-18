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

  for backend <- [Backend.Elixir, Backend.Ripgrep] do
    @backend backend

    describe "#{inspect(backend)}" do
      test "finds every match with grapheme columns, in path order", %{root: root} do
        if @backend.available?() do
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
        if @backend.available?() do
          {:ok, matches} = @backend.search(root, "the", excludes: [Path.join(root, "vendor")])
          refute Enum.any?(matches, &String.contains?(&1.path, "vendor"))

          {:ok, matches} = @backend.search(root, "the", excludes: ["lib/deep"])
          refute Enum.any?(matches, &String.contains?(&1.path, "deep"))

          {:ok, matches} = @backend.search(root, "the", max_results: 2)
          assert length(matches) == 2
        end
      end

      test "skips files that are not valid UTF-8", %{root: root} do
        if @backend.available?() do
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
        if @backend.available?() do
          {:ok, matches} = @backend.search(root, "THE", case_sensitive: true)

          assert Enum.map(matches, &{Path.relative_to(&1.path, root), &1.line, &1.col}) ==
                   [{"lib/a.ex", 3, 1}]
        end
      end

      test "regex treats the query as a pattern, and does not by default", %{root: root} do
        if @backend.available?() do
          {:ok, literal} = @backend.search(root, "th.", [])
          assert literal == []

          {:ok, matches} = @backend.search(root, "th.", regex: true)
          assert Enum.map(matches, & &1.matched) |> Enum.uniq() |> Enum.sort() == ["THE", "the"]
        end
      end

      test "a pattern that will not compile is reported, not raised", %{root: root} do
        if @backend.available?() do
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
