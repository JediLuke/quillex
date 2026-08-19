defmodule Quillex.Search.ExcludesTest do
  @moduledoc """
  The exclude list is a file the person using the editor owns.

  It used to be a constant compiled in — a snapshot of one author's languages.
  The day a project arrives with a `target/` or a `vendor/` in it, a hardcoded
  list has nothing to offer and no way to be told.
  """
  use ExUnit.Case, async: false

  alias Quillex.Search.{Excludes, IgnoreFile}

  setup do
    dir = Path.join(System.tmp_dir!(), "qlx_excludes_#{System.unique_integer([:positive])}")
    System.put_env("XDG_CONFIG_HOME", dir)
    on_exit(fn -> File.rm_rf(dir) end)
    :ok
  end

  describe "the list" do
    test "is written on first use, so it can be found and changed" do
      refute File.exists?(Excludes.path())

      patterns = Excludes.patterns()

      assert File.exists?(Excludes.path()),
             "asking for the list should leave one on disk to edit"

      assert "node_modules" in patterns
      assert "_build" in patterns
    end

    test "a directory pattern covers the directory and everything under it" do
      patterns = Excludes.patterns()

      # The walk prunes on the directory itself, but a path reported from
      # inside one has to be rejected too.
      assert "deps" in patterns
      assert "deps/**" in patterns
    end

    test "what the person writes is what the search uses" do
      File.mkdir_p!(Path.dirname(Excludes.path()))
      File.write!(Excludes.path(), "# mine\ntarget\nvendor/\n")

      patterns = Excludes.patterns()

      assert "target" in patterns
      assert "vendor" in patterns
      refute "node_modules" in patterns, "the defaults are a seed, not a floor"
    end

    test "comments and blank lines are not patterns" do
      assert Excludes.parse("# a comment\n\n  \nreal\n") == ["real", "real/**"]
    end
  end

  describe "the project's own ignore file" do
    setup do
      root = Path.join(System.tmp_dir!(), "qlx_ignore_#{System.unique_integer([:positive])}")
      File.mkdir_p!(root)
      on_exit(fn -> File.rm_rf(root) end)
      {:ok, root: root}
    end

    test "is read as exclusions", %{root: root} do
      File.write!(Path.join(root, ".gitignore"), "*.log\nbuild/\n")

      %{ignore: ignore} = IgnoreFile.rules(root)

      assert "*.log" in ignore
      assert "build" in ignore
      assert "build/**" in ignore
    end

    test "comments and blanks are dropped", %{root: root} do
      File.write!(Path.join(root, ".gitignore"), "# generated\n\n*.beam\n")

      assert IgnoreFile.rules(root).ignore == ["*.beam", "*.beam/**"]
    end

    test "a negation un-ignores", %{root: root} do
      File.write!(Path.join(root, ".gitignore"), "*.log\n!keep.log\n")

      %{ignore: ignore, unignore: unignore} = IgnoreFile.rules(root)

      assert "*.log" in ignore
      assert "keep.log" in unignore
    end

    test "a leading slash anchors to the root rather than matching at depth", %{root: root} do
      File.write!(Path.join(root, ".gitignore"), "/build\n")

      # Glob anchors any pattern containing a separator, so the slash is
      # removed rather than translated.
      assert "build" in IgnoreFile.rules(root).ignore
    end

    test "no ignore file is not an error", %{root: root} do
      assert IgnoreFile.rules(root) == %{ignore: [], unignore: []}
    end
  end

  describe "what actually gets skipped" do
    setup do
      root = Path.join(System.tmp_dir!(), "qlx_skip_#{System.unique_integer([:positive])}")
      File.mkdir_p!(root)
      on_exit(fn -> File.rm_rf(root) end)
      {:ok, root: root}
    end

    test "a negation rescues a file the ignore rules caught", %{root: root} do
      globs = Quillex.Search.Glob.compile_list(["*.log"])
      unignore = Quillex.Search.Glob.compile_list(["keep.log"])

      assert Quillex.Search.Backend.excluded?(Path.join(root, "noise.log"), root, [], globs, unignore)

      refute Quillex.Search.Backend.excluded?(
               Path.join(root, "keep.log"),
               root,
               [],
               globs,
               unignore
             )
    end

    test "but a negation does not override the scope tree", %{root: root} do
      # Unticking something in the pane is this person's decision about this
      # search; a project's .gitignore has no opinion about it.
      unignore = Quillex.Search.Glob.compile_list(["keep.log"])
      unticked = [Path.join(root, "keep.log")]

      assert Quillex.Search.Backend.excluded?(
               Path.join(root, "keep.log"),
               root,
               unticked,
               [],
               unignore
             )
    end
  end
end
